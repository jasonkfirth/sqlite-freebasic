/'
    Project: SQLite FreeBASIC port

    File: sqlite3_os.bas

    Purpose:

        Port the OS dispatch and VFS registry layer from src/os.c.

    Responsibilities:

        - Call file and VFS methods through their C ABI tables.
        - Register, order, find, and remove VFS instances.
        - Allocate file objects using SQLite's allocator.
        - Convert the public millisecond sleep API to VFS microseconds.
        - Apply the deterministic PRNG seed override used by sqlite3_test_control().
        - Keep SQLITE_TEST I/O-error and disk-full controls in the C ABI.

    This file intentionally does NOT contain:

        - Host-specific file operations or lock policy.
        - Automatic library initialization and default VFS registration.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_mutex.bi"
#include once "sqlite3_vfs.bi"
#include once "sqlite3_os_test.bi"

Declare Function sqlite3Malloc CDecl Alias "sqlite3Malloc" (ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Function sqlite3MallocZero CDecl Alias "sqlite3MallocZero" (ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Declare Function sqlite3JournalIsInMemory CDecl Alias "sqlite3JournalIsInMemory" ( _
    ByVal pJournalFile As sqlite3_file Ptr _
) As SQLITE_C_INT
#ifdef SQLITE_DEBUG
Declare Function sqlite3IoerrnomemError CDecl Alias "sqlite3IoerrnomemError" ( _
    ByVal lineNumber As SQLITE_C_INT _
) As SQLITE_C_INT
#endif
Declare Function sqlite3RealToI64 CDecl Alias "sqlite3RealToI64" (ByVal value As Double) As sqlite3_int64
Declare Function sqlite3_os_init CDecl Alias "sqlite3_os_init" () As SQLITE_C_INT
Declare Function sqlite3ConfigTestPrngSeed CDecl Alias "sqlite3ConfigTestPrngSeed" () As SQLITE_C_UINT

Private Const SQLITE_OS_OPEN_VALID_MASK As SQLITE_C_INT = &H1087F7F
Dim Shared sqlite3VfsList As sqlite3_vfs Ptr

#ifdef SQLITE_TEST
' Keep these counters process-wide and exported under os.c's C names because
' the C test driver links directly to them.
Dim Shared sqlite3_memdebug_vfs_oom_test As SQLITE_C_INT = 1
Dim Shared sqlite3_io_error_hit As SQLITE_C_INT
Dim Shared sqlite3_io_error_hardhit As SQLITE_C_INT
Dim Shared sqlite3_io_error_pending As SQLITE_C_INT
Dim Shared sqlite3_io_error_persist As SQLITE_C_INT
Dim Shared sqlite3_io_error_benign As SQLITE_C_INT
Dim Shared sqlite3_diskfull_pending As SQLITE_C_INT
Dim Shared sqlite3_diskfull As SQLITE_C_INT
Dim Shared sqlite3_open_file_count As SQLITE_C_INT
Dim Shared sqlite3_sync_count As SQLITE_C_INT
Dim Shared sqlite3_fullsync_count As SQLITE_C_INT

Private Function sqlite3OsTestVfsMallocFailure( _
    ByVal pFile As sqlite3_file Ptr _
) As SQLITE_C_INT
    If sqlite3_memdebug_vfs_oom_test = 0 OrElse _
       (pFile <> 0 AndAlso sqlite3JournalIsInMemory(pFile) <> 0) Then _
        Return SQLITE_OK

    ' os.c probes the allocator with a 10-byte request at each VFS boundary.
    Dim pTestAllocation As Any Ptr = sqlite3Malloc(10)
    If pTestAllocation = 0 Then
#ifdef SQLITE_DEBUG
        Return sqlite3IoerrnomemError(__LINE__)
#else
        Return SQLITE_IOERR_NOMEM
#endif
    End If
    sqlite3_free(pTestAllocation)
    Return SQLITE_OK
End Function

Private Sub sqlite3TestRecordIoError()
    sqlite3_io_error_hit += 1
    If sqlite3_io_error_benign = 0 Then sqlite3_io_error_hardhit += 1
End Sub

' Match os_common.h's persistent-error rule and countdown semantics.
Function fbTestSimulateIoError CDecl Alias "fbTestSimulateIoError" () As SQLITE_C_INT
    Dim shouldFail As SQLITE_C_INT = 0
    If sqlite3_io_error_persist <> 0 AndAlso sqlite3_io_error_hit <> 0 Then
        shouldFail = 1
    Else
        Dim pendingCount As SQLITE_C_INT = sqlite3_io_error_pending
        sqlite3_io_error_pending -= 1
        If pendingCount = 1 Then shouldFail = 1
    End If
    If shouldFail <> 0 Then sqlite3TestRecordIoError()
    Return shouldFail
End Function

Function fbTestSimulateDiskfull CDecl Alias "fbTestSimulateDiskfull" () As SQLITE_C_INT
    If sqlite3_diskfull_pending = 0 Then Return 0
    If sqlite3_diskfull_pending <> 1 Then
        sqlite3_diskfull_pending -= 1
        Return 0
    End If
    sqlite3TestRecordIoError()
    sqlite3_diskfull = 1
    sqlite3_io_error_hit = 1
    Return 1
End Function

Sub fbTestSetIoErrorBenign CDecl Alias "fbTestSetIoErrorBenign" ( _
    ByVal benign As SQLITE_C_INT _
)
    sqlite3_io_error_benign = IIf(benign <> 0, 1, 0)
End Sub
#endif

Private Function sqlite3OsVfsNameEqual( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT

    If zLeft = 0 OrElse zRight = 0 Then Return 0
    Dim i As sqlite3_uint64 = 0
    While zLeft[i] <> 0 AndAlso zRight[i] <> 0
        If zLeft[i] <> zRight[i] Then Return 0
        i += 1
    Wend
    Return IIf(zLeft[i] = 0 AndAlso zRight[i] = 0, 1, 0)
End Function

Private Sub vfsUnlink(ByVal pVfs As sqlite3_vfs Ptr)
    If pVfs = 0 Then Exit Sub
    If sqlite3VfsList = pVfs Then
        sqlite3VfsList = pVfs->pNext
        Exit Sub
    End If
    Dim pScan As sqlite3_vfs Ptr = sqlite3VfsList
    While pScan <> 0 AndAlso pScan->pNext <> pVfs
        pScan = pScan->pNext
    Wend
    If pScan <> 0 Then pScan->pNext = pVfs->pNext
End Sub

/' ------------------------------------------------------------------------- '/
/' sqlite3_file method dispatch '/
/' ------------------------------------------------------------------------- '/

Sub sqlite3OsClose CDecl Alias "sqlite3OsClose" (ByVal pFile As sqlite3_file Ptr) Export
    If pFile = 0 OrElse pFile->pMethods = 0 Then Exit Sub
    Dim pMethods As sqlite3_io_methods Ptr = pFile->pMethods
    If pMethods->xClose <> 0 Then pMethods->xClose(pFile)
    pFile->pMethods = 0
End Sub

Function sqlite3OsRead CDecl Alias "sqlite3OsRead" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal pBuffer As Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal offset As sqlite3_int64 _
) As SQLITE_C_INT Export

    If pFile = 0 OrElse pFile->pMethods = 0 OrElse _
       (pBuffer = 0 AndAlso amount > 0) OrElse amount < 0 OrElse offset < 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    Dim faultCode As SQLITE_C_INT = sqlite3OsTestVfsMallocFailure(pFile)
    If faultCode <> SQLITE_OK Then Return faultCode
#endif
    Dim pMethods As sqlite3_io_methods Ptr = pFile->pMethods
    If pMethods->xRead = 0 Then Return SQLITE_IOERR_READ
    Return pMethods->xRead(pFile, pBuffer, amount, offset)
End Function

Function sqlite3OsWrite CDecl Alias "sqlite3OsWrite" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal pBuffer As Const Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal offset As sqlite3_int64 _
) As SQLITE_C_INT Export

    If pFile = 0 OrElse pFile->pMethods = 0 OrElse _
       (pBuffer = 0 AndAlso amount > 0) OrElse amount < 0 OrElse offset < 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    Dim faultCode As SQLITE_C_INT = sqlite3OsTestVfsMallocFailure(pFile)
    If faultCode <> SQLITE_OK Then Return faultCode
#endif
    Dim pMethods As sqlite3_io_methods Ptr = pFile->pMethods
    If pMethods->xWrite = 0 Then Return SQLITE_IOERR_WRITE
    Return pMethods->xWrite(pFile, pBuffer, amount, offset)
End Function

Function sqlite3OsTruncate CDecl Alias "sqlite3OsTruncate" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal size As sqlite3_int64 _
) As SQLITE_C_INT Export

    If pFile = 0 OrElse pFile->pMethods = 0 OrElse size < 0 Then Return SQLITE_MISUSE
    If pFile->pMethods->xTruncate = 0 Then Return SQLITE_IOERR_TRUNCATE
    Return pFile->pMethods->xTruncate(pFile, size)
End Function

Function sqlite3OsSync CDecl Alias "sqlite3OsSync" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pFile = 0 OrElse pFile->pMethods = 0 OrElse pFile->pMethods->xSync = 0 Then Return SQLITE_IOERR_FSYNC
#ifdef SQLITE_TEST
    Dim faultCode As SQLITE_C_INT = sqlite3OsTestVfsMallocFailure(pFile)
    If faultCode <> SQLITE_OK Then Return faultCode
#endif
    If flags = 0 Then Return SQLITE_OK
    Return pFile->pMethods->xSync(pFile, flags)
End Function

Function sqlite3OsFileSize CDecl Alias "sqlite3OsFileSize" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal pSize As sqlite3_int64 Ptr _
) As SQLITE_C_INT Export

    If pFile = 0 OrElse pFile->pMethods = 0 OrElse pSize = 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    Dim faultCode As SQLITE_C_INT = sqlite3OsTestVfsMallocFailure(pFile)
    If faultCode <> SQLITE_OK Then Return faultCode
#endif
    If pFile->pMethods->xFileSize = 0 Then Return SQLITE_IOERR_FSTAT
    Return pFile->pMethods->xFileSize(pFile, pSize)
End Function

Function sqlite3OsLock CDecl Alias "sqlite3OsLock" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pFile = 0 OrElse pFile->pMethods = 0 OrElse _
       lockLevel < SQLITE_LOCK_SHARED OrElse lockLevel > SQLITE_LOCK_EXCLUSIVE Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    Dim faultCode As SQLITE_C_INT = sqlite3OsTestVfsMallocFailure(pFile)
    If faultCode <> SQLITE_OK Then Return faultCode
#endif
    If pFile->pMethods->xLock = 0 Then Return SQLITE_IOERR_LOCK
    Return pFile->pMethods->xLock(pFile, lockLevel)
End Function

Function sqlite3OsUnlock CDecl Alias "sqlite3OsUnlock" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pFile = 0 OrElse pFile->pMethods = 0 OrElse _
       (lockLevel <> SQLITE_LOCK_NONE AndAlso lockLevel <> SQLITE_LOCK_SHARED) Then Return SQLITE_MISUSE
    If pFile->pMethods->xUnlock = 0 Then Return SQLITE_IOERR_UNLOCK
    Return pFile->pMethods->xUnlock(pFile, lockLevel)
End Function

Function sqlite3OsCheckReservedLock CDecl Alias "sqlite3OsCheckReservedLock" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT Export

    If pFile = 0 OrElse pFile->pMethods = 0 OrElse pResult = 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    Dim faultCode As SQLITE_C_INT = sqlite3OsTestVfsMallocFailure(pFile)
    If faultCode <> SQLITE_OK Then Return faultCode
#endif
    If pFile->pMethods->xCheckReservedLock = 0 Then Return SQLITE_IOERR_CHECKRESERVEDLOCK
    Return pFile->pMethods->xCheckReservedLock(pFile, pResult)
End Function

Function sqlite3OsFileControl CDecl Alias "sqlite3OsFileControl" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export

    If pFile = 0 OrElse pFile->pMethods = 0 OrElse pFile->pMethods->xFileControl = 0 Then Return SQLITE_NOTFOUND
#ifdef SQLITE_TEST
    If operation <> SQLITE_FCNTL_COMMIT_PHASETWO AndAlso _
       operation <> SQLITE_FCNTL_LOCK_TIMEOUT AndAlso _
       operation <> SQLITE_FCNTL_CKPT_DONE AndAlso _
       operation <> SQLITE_FCNTL_CKPT_START Then
        Dim faultCode As SQLITE_C_INT = sqlite3OsTestVfsMallocFailure(pFile)
        If faultCode <> SQLITE_OK Then Return faultCode
    End If
#endif
    Return pFile->pMethods->xFileControl(pFile, operation, pArgument)
End Function

Sub sqlite3OsFileControlHint CDecl Alias "sqlite3OsFileControlHint" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal pArgument As Any Ptr _
) Export

    If pFile = 0 OrElse pFile->pMethods = 0 OrElse pFile->pMethods->xFileControl = 0 Then Exit Sub
    pFile->pMethods->xFileControl(pFile, operation, pArgument)
End Sub

Function sqlite3OsSectorSize CDecl Alias "sqlite3OsSectorSize" (ByVal pFile As sqlite3_file Ptr) As SQLITE_C_INT Export
    If pFile = 0 OrElse pFile->pMethods = 0 Then Return SQLITE_DEFAULT_SECTOR_SIZE
    If pFile->pMethods->xSectorSize = 0 Then Return SQLITE_DEFAULT_SECTOR_SIZE
    Return pFile->pMethods->xSectorSize(pFile)
End Function

Function sqlite3OsDeviceCharacteristics CDecl Alias "sqlite3OsDeviceCharacteristics" (ByVal pFile As sqlite3_file Ptr) As SQLITE_C_INT Export
    If pFile = 0 OrElse pFile->pMethods = 0 OrElse pFile->pMethods->xDeviceCharacteristics = 0 Then Return 0
    Return pFile->pMethods->xDeviceCharacteristics(pFile)
End Function

Function sqlite3OsShmMap CDecl Alias "sqlite3OsShmMap" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal pageNumber As SQLITE_C_INT, _
    ByVal pageSize As SQLITE_C_INT, _
    ByVal extendFlag As SQLITE_C_INT, _
    ByVal ppPage As Any Ptr Ptr _
) As SQLITE_C_INT Export

    If ppPage = 0 Then Return SQLITE_MISUSE
    ppPage[0] = 0
    If pFile = 0 OrElse pFile->pMethods = 0 Then Return SQLITE_IOERR_SHMMAP
    If pFile->pMethods->iVersion < 2 OrElse pFile->pMethods->xShmMap = 0 Then Return SQLITE_IOERR_SHMMAP
#ifdef SQLITE_TEST
    Dim faultCode As SQLITE_C_INT = sqlite3OsTestVfsMallocFailure(pFile)
    If faultCode <> SQLITE_OK Then Return faultCode
#endif
    Return pFile->pMethods->xShmMap(pFile, pageNumber, pageSize, extendFlag, ppPage)
End Function

Function sqlite3OsShmLock CDecl Alias "sqlite3OsShmLock" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal offset As SQLITE_C_INT, _
    ByVal count As SQLITE_C_INT, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pFile = 0 OrElse pFile->pMethods = 0 Then Return SQLITE_IOERR_SHMLOCK
    If pFile->pMethods->iVersion < 2 OrElse pFile->pMethods->xShmLock = 0 Then Return SQLITE_IOERR_SHMLOCK
    Return pFile->pMethods->xShmLock(pFile, offset, count, flags)
End Function

Sub sqlite3OsShmBarrier CDecl Alias "sqlite3OsShmBarrier" (ByVal pFile As sqlite3_file Ptr) Export
    If pFile = 0 OrElse pFile->pMethods = 0 OrElse pFile->pMethods->iVersion < 2 Then Exit Sub
    If pFile->pMethods->xShmBarrier <> 0 Then pFile->pMethods->xShmBarrier(pFile)
End Sub

Function sqlite3OsShmUnmap CDecl Alias "sqlite3OsShmUnmap" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal deleteFlag As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pFile = 0 OrElse pFile->pMethods = 0 Then Return SQLITE_IOERR_SHMOPEN
    If pFile->pMethods->iVersion < 2 OrElse pFile->pMethods->xShmUnmap = 0 Then Return SQLITE_IOERR_SHMOPEN
    Return pFile->pMethods->xShmUnmap(pFile, deleteFlag)
End Function

Function sqlite3OsFetch CDecl Alias "sqlite3OsFetch" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal offset As sqlite3_int64, _
    ByVal amount As SQLITE_C_INT, _
    ByVal ppBuffer As Any Ptr Ptr _
) As SQLITE_C_INT Export

    If ppBuffer = 0 Then Return SQLITE_MISUSE
    ppBuffer[0] = 0
    If pFile = 0 OrElse pFile->pMethods = 0 Then Return SQLITE_MISUSE
    If pFile->pMethods->iVersion < 3 OrElse pFile->pMethods->xFetch = 0 Then Return SQLITE_OK
#ifdef SQLITE_TEST
    Dim faultCode As SQLITE_C_INT = sqlite3OsTestVfsMallocFailure(pFile)
    If faultCode <> SQLITE_OK Then Return faultCode
#endif
    Return pFile->pMethods->xFetch(pFile, offset, amount, ppBuffer)
End Function

Function sqlite3OsUnfetch CDecl Alias "sqlite3OsUnfetch" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal offset As sqlite3_int64, _
    ByVal pBuffer As Any Ptr _
) As SQLITE_C_INT Export

    If pBuffer = 0 Then Return SQLITE_OK
    If pFile = 0 OrElse pFile->pMethods = 0 Then Return SQLITE_MISUSE
    If pFile->pMethods->iVersion < 3 OrElse pFile->pMethods->xUnfetch = 0 Then Return SQLITE_OK
    Return pFile->pMethods->xUnfetch(pFile, offset, pBuffer)
End Function

/' ------------------------------------------------------------------------- '/
/' sqlite3_vfs method dispatch '/
/' ------------------------------------------------------------------------- '/

Function sqlite3OsOpen CDecl Alias "sqlite3OsOpen" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal pOutFlags As SQLITE_C_INT Ptr _
) As SQLITE_C_INT Export

    If pVfs = 0 OrElse pVfs->xOpen = 0 OrElse pFile = 0 Then Return SQLITE_MISUSE
    If zName = 0 AndAlso (flags And SQLITE_OPEN_EXCLUSIVE) = 0 Then Return SQLITE_MISUSE
    pFile->pMethods = 0
#ifdef SQLITE_TEST
    Dim faultCode As SQLITE_C_INT = sqlite3OsTestVfsMallocFailure(0)
    If faultCode <> SQLITE_OK Then Return faultCode
#endif
    ' SQLite callers may omit the optional flags returned by the VFS.
    Return pVfs->xOpen(pVfs, zName, pFile, flags And SQLITE_OS_OPEN_VALID_MASK, pOutFlags)
End Function

Function sqlite3OsDelete CDecl Alias "sqlite3OsDelete" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal syncDirectory As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pVfs = 0 OrElse zName = 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    Dim faultCode As SQLITE_C_INT = sqlite3OsTestVfsMallocFailure(0)
    If faultCode <> SQLITE_OK Then Return faultCode
#endif
    If pVfs->xDelete = 0 Then Return SQLITE_OK
    Return pVfs->xDelete(pVfs, zName, syncDirectory)
End Function

Function sqlite3OsAccess CDecl Alias "sqlite3OsAccess" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT Export

    If pVfs = 0 OrElse zName = 0 OrElse pResult = 0 OrElse pVfs->xAccess = 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    Dim faultCode As SQLITE_C_INT = sqlite3OsTestVfsMallocFailure(0)
    If faultCode <> SQLITE_OK Then Return faultCode
#endif
    pResult[0] = 0
    Return pVfs->xAccess(pVfs, zName, flags, pResult)
End Function

Function sqlite3OsFullPathname CDecl Alias "sqlite3OsFullPathname" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal outputSize As SQLITE_C_INT, _
    ByVal zOutput As ZString Ptr _
) As SQLITE_C_INT Export

    If pVfs = 0 OrElse zName = 0 OrElse outputSize <= 0 OrElse zOutput = 0 OrElse pVfs->xFullPathname = 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    Dim faultCode As SQLITE_C_INT = sqlite3OsTestVfsMallocFailure(0)
    If faultCode <> SQLITE_OK Then Return faultCode
#endif
    zOutput[0] = 0
    Return pVfs->xFullPathname(pVfs, zName, outputSize, zOutput)
End Function

Function sqlite3OsDlOpen CDecl Alias "sqlite3OsDlOpen" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal zName As Const ZString Ptr _
) As Any Ptr Export

    If pVfs = 0 OrElse zName = 0 OrElse pVfs->xDlOpen = 0 Then Return 0
    Return pVfs->xDlOpen(pVfs, zName)
End Function

Sub sqlite3OsDlError CDecl Alias "sqlite3OsDlError" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal outputSize As SQLITE_C_INT, _
    ByVal zOutput As ZString Ptr _
) Export

    If zOutput = 0 OrElse outputSize <= 0 Then Exit Sub
    zOutput[0] = 0
    If pVfs <> 0 AndAlso pVfs->xDlError <> 0 Then pVfs->xDlError(pVfs, outputSize, zOutput)
End Sub

Function sqlite3OsDlSym CDecl Alias "sqlite3OsDlSym" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal pHandle As Any Ptr, _
    ByVal zSymbol As Const ZString Ptr _
) As Any Ptr Export

    If pVfs = 0 OrElse pVfs->xDlSym = 0 Then Return 0
    Return pVfs->xDlSym(pVfs, pHandle, zSymbol)
End Function

Sub sqlite3OsDlClose CDecl Alias "sqlite3OsDlClose" (ByVal pVfs As sqlite3_vfs Ptr, ByVal pHandle As Any Ptr) Export
    If pVfs <> 0 AndAlso pVfs->xDlClose <> 0 Then pVfs->xDlClose(pVfs, pHandle)
End Sub

Function sqlite3OsRandomness CDecl Alias "sqlite3OsRandomness" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal zOutput As ZString Ptr _
) As SQLITE_C_INT Export

    If amount < 0 OrElse (amount > 0 AndAlso zOutput = 0) Then Return SQLITE_MISUSE

    Dim configuredSeed As SQLITE_C_UINT = sqlite3ConfigTestPrngSeed()
    If configuredSeed <> 0 Then
        Dim pBytes As UByte Ptr = CPtr(UByte Ptr, zOutput)
        Dim copiedBytes As SQLITE_C_INT = amount
        If copiedBytes > SizeOf(configuredSeed) Then _
            copiedBytes = SizeOf(configuredSeed)
        If amount > 0 Then
            For iByte As SQLITE_C_INT = 0 To amount - 1
                pBytes[iByte] = 0
            Next
            Dim pSeedBytes As Const UByte Ptr = _
                CPtr(Const UByte Ptr, @configuredSeed)
            For iByte As SQLITE_C_INT = 0 To copiedBytes - 1
                pBytes[iByte] = pSeedBytes[iByte]
            Next
        End If
        Return SQLITE_OK
    End If

    If pVfs = 0 OrElse pVfs->xRandomness = 0 Then Return SQLITE_MISUSE
    Return pVfs->xRandomness(pVfs, amount, zOutput)
End Function

Function sqlite3OsSleep CDecl Alias "sqlite3OsSleep" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal microseconds As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pVfs = 0 OrElse microseconds < 0 OrElse pVfs->xSleep = 0 Then Return SQLITE_MISUSE
    Return pVfs->xSleep(pVfs, microseconds)
End Function

Function sqlite3_sleep CDecl Alias "sqlite3_sleep" ( _
    ByVal milliseconds As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Dim pVfs As sqlite3_vfs Ptr = sqlite3_vfs_find(0)
    If pVfs = 0 Then Return 0
    Dim microseconds As sqlite3_int64 = 0
    If milliseconds > 0 Then
        microseconds = CLngInt(milliseconds) * 1000
        If microseconds > 2147483647LL Then microseconds = 2147483647LL
    End If
    Return sqlite3OsSleep(pVfs, CInt(microseconds)) \ 1000
End Function

Function sqlite3OsGetLastError CDecl Alias "sqlite3OsGetLastError" (ByVal pVfs As sqlite3_vfs Ptr) As SQLITE_C_INT Export
    If pVfs = 0 OrElse pVfs->xGetLastError = 0 Then Return 0
    Return pVfs->xGetLastError(pVfs, 0, 0)
End Function

Function sqlite3OsCurrentTimeInt64 CDecl Alias "sqlite3OsCurrentTimeInt64" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal pJulianDay As sqlite3_int64 Ptr _
) As SQLITE_C_INT Export

    If pVfs = 0 OrElse pJulianDay = 0 Then Return SQLITE_MISUSE
    If pVfs->iVersion >= 2 AndAlso pVfs->xCurrentTimeInt64 <> 0 Then
        Return pVfs->xCurrentTimeInt64(pVfs, pJulianDay)
    End If
    If pVfs->xCurrentTime = 0 Then Return SQLITE_ERROR
    Dim julianDay As Double = 0
    Dim rc As SQLITE_C_INT = pVfs->xCurrentTime(pVfs, @julianDay)
    If rc <> SQLITE_OK Then Return rc
    pJulianDay[0] = sqlite3RealToI64(julianDay * 86400000.0)
    Return SQLITE_OK
End Function

Function sqlite3OsOpenMalloc CDecl Alias "sqlite3OsOpenMalloc" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal ppFile As sqlite3_file Ptr Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal pOutFlags As SQLITE_C_INT Ptr _
) As SQLITE_C_INT Export

    If ppFile = 0 Then Return SQLITE_MISUSE
    ppFile[0] = 0
    If pVfs = 0 OrElse pVfs->szOsFile < SizeOf(sqlite3_file) Then Return SQLITE_MISUSE
    Dim pFile As sqlite3_file Ptr = CPtr(sqlite3_file Ptr, sqlite3MallocZero(CULngInt(pVfs->szOsFile)))
    If pFile = 0 Then Return SQLITE_NOMEM
    Dim rc As SQLITE_C_INT = sqlite3OsOpen(pVfs, zName, pFile, flags, pOutFlags)
    If rc <> SQLITE_OK Then
        If pFile->pMethods <> 0 Then sqlite3OsClose(pFile)
        sqlite3_free(pFile)
        Return rc
    End If
    ppFile[0] = pFile
    Return SQLITE_OK
End Function

Sub sqlite3OsCloseFree CDecl Alias "sqlite3OsCloseFree" (ByVal pFile As sqlite3_file Ptr) Export
    If pFile = 0 Then Exit Sub
    sqlite3OsClose(pFile)
    sqlite3_free(pFile)
End Sub

Function sqlite3OsInit CDecl Alias "sqlite3OsInit" () As SQLITE_C_INT Export
    Return sqlite3_os_init()
End Function

/' ------------------------------------------------------------------------- '/
/' VFS registry '/
/' ------------------------------------------------------------------------- '/

Function sqlite3_vfs_find CDecl Alias "sqlite3_vfs_find" (ByVal zName As Const ZString Ptr) As sqlite3_vfs Ptr Export
    Dim pMutex As Any Ptr = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MAIN)
    sqlite3_mutex_enter(pMutex)
    Dim pVfs As sqlite3_vfs Ptr = sqlite3VfsList
    While pVfs <> 0
        If zName = 0 OrElse sqlite3OsVfsNameEqual(zName, pVfs->zName) <> 0 Then Exit While
        pVfs = pVfs->pNext
    Wend
    sqlite3_mutex_leave(pMutex)
    Return pVfs
End Function

Function sqlite3_vfs_register CDecl Alias "sqlite3_vfs_register" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal makeDefault As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pVfs = 0 OrElse pVfs->zName = 0 OrElse pVfs->zName[0] = 0 OrElse _
       pVfs->szOsFile < SizeOf(sqlite3_file) OrElse pVfs->xOpen = 0 Then Return SQLITE_MISUSE

    Dim pMutex As Any Ptr = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MAIN)
    sqlite3_mutex_enter(pMutex)
    vfsUnlink(pVfs)
    If makeDefault <> 0 OrElse sqlite3VfsList = 0 Then
        pVfs->pNext = sqlite3VfsList
        sqlite3VfsList = pVfs
    Else
        pVfs->pNext = sqlite3VfsList->pNext
        sqlite3VfsList->pNext = pVfs
    End If
    sqlite3_mutex_leave(pMutex)
    Return SQLITE_OK
End Function

Function sqlite3_vfs_unregister CDecl Alias "sqlite3_vfs_unregister" (ByVal pVfs As sqlite3_vfs Ptr) As SQLITE_C_INT Export
    If pVfs = 0 Then Return SQLITE_MISUSE
    Dim pMutex As Any Ptr = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MAIN)
    sqlite3_mutex_enter(pMutex)
    vfsUnlink(pVfs)
    pVfs->pNext = 0
    sqlite3_mutex_leave(pMutex)
    Return SQLITE_OK
End Function

/' end of sqlite3_os.bas '/
