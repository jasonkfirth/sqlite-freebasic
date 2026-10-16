/'
    Project: SQLite FreeBASIC port

    File: sqlite3_memdb.bas

    Purpose:

        Provide a VFS whose database files are stored in resizable memory.

    Responsibilities:

        - Implement memory-backed file reads, writes, locks, and mapping.
        - Share named stores between connections with a VFS mutex.
        - Forward unrelated VFS services to the registered underlying VFS.

    This file intentionally does NOT contain:

        - sqlite3_serialize() and sqlite3_deserialize() connection operations.
        - The B-tree and pager policy that opens a database through this VFS.
'/

#lang "fb"
#ifndef SQLITE_OMIT_DESERIALIZE
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_mutex.bi"
#include once "sqlite3_vfs.bi"
#include once "sqlite3_memdb.bi"
#include once "sqlite3_memdb_types.bi"

Declare Function sqlite3Malloc CDecl Alias "sqlite3Malloc" (ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Function sqlite3MallocZero CDecl Alias "sqlite3MallocZero" (ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Function sqlite3Realloc CDecl Alias "sqlite3Realloc" ( _
    ByVal pOld As Any Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)

Declare Function memdbSystemMemcpy CDecl Alias "memcpy" ( _
    ByVal pDestination As Any Ptr, _
    ByVal pSource As Const Any Ptr, _
    ByVal nByte As SQLITE_SIZE_T _
) As Any Ptr
Declare Function memdbSystemMemset CDecl Alias "memset" ( _
    ByVal pDestination As Any Ptr, _
    ByVal fillValue As SQLITE_C_INT, _
    ByVal nByte As SQLITE_SIZE_T _
) As Any Ptr

Private Const MEMDB_MAX_PATHNAME As SQLITE_C_INT = 1024

Declare Function sqlite3ConfigMemdbMaxSize CDecl Alias "sqlite3ConfigMemdbMaxSize" () As sqlite3_int64
Declare Function sqlite3_file_control CDecl Alias "sqlite3_file_control" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zDatabase As Const ZString Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT

/' ------------------------------------------------------------------------- '/
/' File and shared-store layouts '/
/' ------------------------------------------------------------------------- '/

Private Dim Shared memdbStores As MemdbFileSystem
Private Dim Shared memdbVfs As sqlite3_vfs
Private Dim Shared memdbIoMethods As sqlite3_io_methods
Private Dim Shared memdbMethodsReady As SQLITE_C_INT

/' ------------------------------------------------------------------------- '/
/' File-method declarations '/
/' ------------------------------------------------------------------------- '/

Declare Function memdbFileClose CDecl Alias "memdbClose" (ByVal pFile As Any Ptr) As SQLITE_C_INT
Declare Function memdbFileRead CDecl Alias "memdbRead" ( _
    ByVal pFile As Any Ptr, _
    ByVal pBuffer As Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal offset As sqlite3_int64 _
) As SQLITE_C_INT
Declare Function memdbFileWrite CDecl Alias "memdbWrite" ( _
    ByVal pFile As Any Ptr, _
    ByVal pBuffer As Const Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal offset As sqlite3_int64 _
) As SQLITE_C_INT
Declare Function memdbFileTruncate CDecl Alias "memdbTruncate" ( _
    ByVal pFile As Any Ptr, _
    ByVal size As sqlite3_int64 _
) As SQLITE_C_INT
Declare Function memdbFileSync CDecl Alias "memdbSync" ( _
    ByVal pFile As Any Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function memdbFileSize CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal pSize As sqlite3_int64 Ptr _
) As SQLITE_C_INT
Declare Function memdbFileLock CDecl Alias "memdbLock" ( _
    ByVal pFile As Any Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function memdbFileUnlock CDecl Alias "memdbUnlock" ( _
    ByVal pFile As Any Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function memdbFileControl CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT
Declare Function memdbDeviceCharacteristics CDecl (ByVal pFile As Any Ptr) As SQLITE_C_INT
Declare Function memdbFileFetch CDecl Alias "memdbFetch" ( _
    ByVal pFile As Any Ptr, _
    ByVal offset As sqlite3_int64, _
    ByVal amount As SQLITE_C_INT, _
    ByVal ppBuffer As Any Ptr Ptr _
) As SQLITE_C_INT
Declare Function memdbFileUnfetch CDecl Alias "memdbUnfetch" ( _
    ByVal pFile As Any Ptr, _
    ByVal offset As sqlite3_int64, _
    ByVal pBuffer As Any Ptr _
) As SQLITE_C_INT

/' ------------------------------------------------------------------------- '/
/' VFS-method declarations '/
/' ------------------------------------------------------------------------- '/

Declare Function memdbVfsOpen CDecl Alias "memdbOpen" ( _
    ByVal pVfs As Any Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal pOutFlags As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Function memdbVfsAccess CDecl Alias "memdbAccess" ( _
    ByVal pVfs As Any Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Function memdbVfsFullPathname CDecl Alias "memdbFullPathname" ( _
    ByVal pVfs As Any Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal outputSize As SQLITE_C_INT, _
    ByVal zOutput As ZString Ptr _
) As SQLITE_C_INT
Declare Function memdbVfsDlOpen CDecl Alias "memdbDlOpen" (ByVal pVfs As Any Ptr, ByVal zName As Const ZString Ptr) As Any Ptr
Declare Sub memdbVfsDlError CDecl Alias "memdbDlError" ( _
    ByVal pVfs As Any Ptr, _
    ByVal outputSize As SQLITE_C_INT, _
    ByVal zOutput As ZString Ptr _
)
Declare Function memdbVfsDlSym CDecl Alias "memdbDlSym" ( _
    ByVal pVfs As Any Ptr, _
    ByVal pHandle As Any Ptr, _
    ByVal zSymbol As Const ZString Ptr _
) As Any Ptr
Declare Sub memdbVfsDlClose CDecl Alias "memdbDlClose" (ByVal pVfs As Any Ptr, ByVal pHandle As Any Ptr)
Declare Function memdbVfsRandomness CDecl Alias "memdbRandomness" ( _
    ByVal pVfs As Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal zOutput As ZString Ptr _
) As SQLITE_C_INT
Declare Function memdbVfsSleep CDecl Alias "memdbSleep" ( _
    ByVal pVfs As Any Ptr, _
    ByVal microseconds As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function memdbVfsGetLastError CDecl Alias "memdbGetLastError" ( _
    ByVal pVfs As Any Ptr, _
    ByVal outputSize As SQLITE_C_INT, _
    ByVal zOutput As ZString Ptr _
) As SQLITE_C_INT
Declare Function memdbVfsCurrentTimeInt64 CDecl Alias "memdbCurrentTimeInt64" ( _
    ByVal pVfs As Any Ptr, _
    ByVal pJulianDay As sqlite3_int64 Ptr _
) As SQLITE_C_INT

/' ------------------------------------------------------------------------- '/
/' Shared helpers '/
/' ------------------------------------------------------------------------- '/

Private Function memdbOriginalVfs(ByVal pVfs As sqlite3_vfs Ptr) As sqlite3_vfs Ptr
    If pVfs = 0 OrElse pVfs->pAppData = 0 Then Return 0
    Return CPtr(sqlite3_vfs Ptr, pVfs->pAppData)
End Function

Private Sub memdbStoreEnter CDecl Alias "memdbEnter" (ByVal pStore As MemdbStore Ptr)
    If pStore <> 0 AndAlso pStore->pMutex <> 0 Then sqlite3_mutex_enter(pStore->pMutex)
End Sub

Private Sub memdbStoreLeave CDecl Alias "memdbLeave" (ByVal pStore As MemdbStore Ptr)
    If pStore <> 0 AndAlso pStore->pMutex <> 0 Then sqlite3_mutex_leave(pStore->pMutex)
End Sub

Function memdbFromDbSchema CDecl Alias "memdbFromDbSchema" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zSchema As Const ZString Ptr _
) As MemdbFile Ptr
    If db = 0 OrElse zSchema = 0 Then Return 0

    Dim pFile As MemdbFile Ptr = 0
    If sqlite3_file_control(db, zSchema, SQLITE_FCNTL_FILE_POINTER, @pFile) <> SQLITE_OK Then _
        Return 0
    If pFile = 0 OrElse pFile->base.pMethods <> @memdbIoMethods Then Return 0

    Dim pStore As MemdbStore Ptr = pFile->pStore
    If pStore = 0 Then Return 0
    memdbStoreEnter(pStore)
    If pStore->zFName <> 0 Then pFile = 0
    memdbStoreLeave(pStore)
    Return pFile
End Function

Private Function memdbStringLength(ByVal zText As Const ZString Ptr) As SQLITE_C_INT
    If zText = 0 Then Return -1
    Dim i As SQLITE_C_INT = 0
    While i <= MEMDB_MAX_PATHNAME AndAlso zText[i] <> 0
        i += 1
    Wend
    If i > MEMDB_MAX_PATHNAME Then Return -1
    Return i
End Function

Private Function memdbStringEqual( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As SQLITE_C_INT
    If zLeft = 0 OrElse zRight = 0 OrElse nByte < 0 Then Return 0
    For i As SQLITE_C_INT = 0 To nByte - 1
        If zLeft[i] <> zRight[i] Then Return 0
    Next
    Return 1
End Function

Private Function memdbStringDup(ByVal zText As Const ZString Ptr, ByVal nByte As SQLITE_C_INT) As ZString Ptr
    If zText = 0 OrElse nByte < 0 OrElse nByte > MEMDB_MAX_PATHNAME Then Return 0
    Dim pNameBytes As UByte Ptr = CPtr(UByte Ptr, sqlite3Malloc(CULngInt(nByte) + 1))
    If pNameBytes = 0 Then Return 0
    If nByte > 0 Then memdbSystemMemcpy(pNameBytes, zText, CULngInt(nByte))
    pNameBytes[nByte] = 0
    Return CPtr(ZString Ptr, pNameBytes)
End Function

Private Function memdbNewStore(ByVal zName As Const ZString Ptr, ByVal nName As SQLITE_C_INT) As MemdbStore Ptr
    Dim pStore As MemdbStore Ptr = CPtr(MemdbStore Ptr, sqlite3MallocZero(SizeOf(MemdbStore)))
    If pStore = 0 Then Return 0
    pStore->mFlags = SQLITE_DESERIALIZE_RESIZEABLE Or SQLITE_DESERIALIZE_FREEONCLOSE
    pStore->szMax = sqlite3ConfigMemdbMaxSize()
    If zName <> 0 Then
        pStore->zFName = memdbStringDup(zName, nName)
        If pStore->zFName = 0 Then
            sqlite3_free(pStore)
            Return 0
        End If
        pStore->pMutex = sqlite3_mutex_alloc(SQLITE_MUTEX_FAST)
        If pStore->pMutex = 0 Then
            sqlite3_free(pStore->zFName)
            sqlite3_free(pStore)
            Return 0
        End If
    End If
    pStore->nRef = 1
    Return pStore
End Function

Private Sub memdbFreeStore(ByVal pStore As MemdbStore Ptr)
    If pStore = 0 Then Exit Sub
    If (pStore->mFlags And SQLITE_DESERIALIZE_FREEONCLOSE) <> 0 Then sqlite3_free(pStore->aData)
    If pStore->zFName <> 0 Then sqlite3_free(pStore->zFName)
    sqlite3_mutex_free(pStore->pMutex)
    sqlite3_free(pStore)
End Sub

Private Function memdbEnlarge(ByVal pStore As MemdbStore Ptr, ByVal requiredSize As sqlite3_int64) As SQLITE_C_INT
    If pStore = 0 OrElse requiredSize < 0 Then Return SQLITE_MISUSE
    If (pStore->mFlags And SQLITE_DESERIALIZE_RESIZEABLE) = 0 OrElse pStore->nMmap <> 0 Then Return SQLITE_FULL
    If requiredSize > pStore->szMax Then Return SQLITE_FULL

    Dim newSize As sqlite3_int64 = requiredSize
    If newSize <= &H3FFFFFFFFFFFFFFF Then
        newSize *= 2
    End If
    If newSize < requiredSize OrElse newSize > pStore->szMax Then newSize = pStore->szMax
    If newSize < requiredSize OrElse newSize <= 0 OrElse _
       CULngInt(newSize) > SQLITE_MAX_ALLOCATION_SIZE Then Return SQLITE_FULL

    Dim pNew As UByte Ptr = CPtr(UByte Ptr, sqlite3Realloc(pStore->aData, CULngInt(newSize)))
    If pNew = 0 Then Return SQLITE_IOERR_NOMEM
    pStore->aData = pNew
    pStore->szAlloc = newSize
    Return SQLITE_OK
End Function

Private Sub memdbInitializeIoMethods()
    ' The public mutex API preserves one-time setup in no-op mutex profiles.
    Dim pMutex As Any Ptr = sqlite3_mutex_alloc(SQLITE_MUTEX_STATIC_MAIN)
    If pMutex = 0 Then Exit Sub
    sqlite3_mutex_enter(pMutex)
    If memdbMethodsReady = 0 Then
        memdbIoMethods.iVersion = 3
        memdbIoMethods.xClose = @memdbFileClose
        memdbIoMethods.xRead = @memdbFileRead
        memdbIoMethods.xWrite = @memdbFileWrite
        memdbIoMethods.xTruncate = @memdbFileTruncate
        memdbIoMethods.xSync = @memdbFileSync
        memdbIoMethods.xFileSize = @memdbFileSize
        memdbIoMethods.xLock = @memdbFileLock
        memdbIoMethods.xUnlock = @memdbFileUnlock
        memdbIoMethods.xCheckReservedLock = 0
        memdbIoMethods.xFileControl = @memdbFileControl
        memdbIoMethods.xSectorSize = 0
        memdbIoMethods.xDeviceCharacteristics = @memdbDeviceCharacteristics
        memdbIoMethods.xShmMap = 0
        memdbIoMethods.xShmLock = 0
        memdbIoMethods.xShmBarrier = 0
        memdbIoMethods.xShmUnmap = 0
        memdbIoMethods.xFetch = @memdbFileFetch
        memdbIoMethods.xUnfetch = @memdbFileUnfetch
        memdbMethodsReady = 1
    End If
    sqlite3_mutex_leave(pMutex)
End Sub

/' ------------------------------------------------------------------------- '/
/' sqlite3_file methods '/
/' ------------------------------------------------------------------------- '/

Private Function memdbFileClose CDecl Alias "memdbClose" (ByVal pFile As Any Ptr) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
    Dim pMemFile As MemdbFile Ptr = CPtr(MemdbFile Ptr, pFile)
    Dim pStore As MemdbStore Ptr = pMemFile->pStore
    If pStore = 0 Then Return SQLITE_MISUSE

    If pStore->zFName <> 0 Then
        Dim pVfsMutex As Any Ptr = sqlite3_mutex_alloc(SQLITE_MUTEX_STATIC_VFS1)
        If pVfsMutex = 0 Then Return SQLITE_ERROR
        sqlite3_mutex_enter(pVfsMutex)
        memdbStoreEnter(pStore)
        For i As SQLITE_C_INT = 0 To memdbStores.nMemStore - 1
            If memdbStores.apMemStore[i] = pStore Then
                If pStore->nRef = 1 Then
                    memdbStores.nMemStore -= 1
                    memdbStores.apMemStore[i] = memdbStores.apMemStore[memdbStores.nMemStore]
                    If memdbStores.nMemStore = 0 Then
                        sqlite3_free(memdbStores.apMemStore)
                        memdbStores.apMemStore = 0
                    End If
                End If
                Exit For
            End If
        Next
        sqlite3_mutex_leave(pVfsMutex)
    Else
        memdbStoreEnter(pStore)
    End If

    If pStore->nRef <= 0 Then
        memdbStoreLeave(pStore)
        Return SQLITE_CORRUPT
    End If
    pStore->nRef -= 1
    Dim freeStore As SQLITE_C_INT = IIf(pStore->nRef = 0, 1, 0)
    memdbStoreLeave(pStore)
    If freeStore <> 0 Then memdbFreeStore(pStore)
    pMemFile->pStore = 0
    Return SQLITE_OK
End Function

Private Function memdbFileRead CDecl Alias "memdbRead" ( _
    ByVal pFile As Any Ptr, _
    ByVal pBuffer As Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal offset As sqlite3_int64 _
) As SQLITE_C_INT

    If pFile = 0 OrElse (amount > 0 AndAlso pBuffer = 0) OrElse amount < 0 OrElse offset < 0 Then Return SQLITE_MISUSE
    Dim pStore As MemdbStore Ptr = CPtr(MemdbFile Ptr, pFile)->pStore
    If pStore = 0 Then Return SQLITE_MISUSE
    If offset > &H7FFFFFFFFFFFFFFF - amount Then Return SQLITE_IOERR_SHORT_READ

    memdbStoreEnter(pStore)
    If pStore->sz > 0 AndAlso pStore->aData = 0 Then
        memdbStoreLeave(pStore)
        Return SQLITE_CORRUPT
    End If
    Dim readEnd As sqlite3_int64 = offset + amount
    If readEnd > pStore->sz Then
        If amount > 0 Then memdbSystemMemset(pBuffer, 0, CULngInt(amount))
        If offset < pStore->sz Then
            Dim copySize As SQLITE_C_INT = CInt(pStore->sz - offset)
            If copySize > 0 Then memdbSystemMemcpy(pBuffer, pStore->aData + offset, CULngInt(copySize))
        End If
        memdbStoreLeave(pStore)
        Return SQLITE_IOERR_SHORT_READ
    End If
    If amount > 0 Then memdbSystemMemcpy(pBuffer, pStore->aData + offset, CULngInt(amount))
    memdbStoreLeave(pStore)
    Return SQLITE_OK
End Function

Private Function memdbFileWrite CDecl Alias "memdbWrite" ( _
    ByVal pFile As Any Ptr, _
    ByVal pBuffer As Const Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal offset As sqlite3_int64 _
) As SQLITE_C_INT

    If pFile = 0 OrElse (amount > 0 AndAlso pBuffer = 0) OrElse amount < 0 OrElse offset < 0 Then Return SQLITE_MISUSE
    If amount = 0 Then Return SQLITE_OK
    If offset > &H7FFFFFFFFFFFFFFF - amount Then Return SQLITE_FULL
    Dim pStore As MemdbStore Ptr = CPtr(MemdbFile Ptr, pFile)->pStore
    If pStore = 0 Then Return SQLITE_MISUSE

    memdbStoreEnter(pStore)
    If (pStore->mFlags And SQLITE_DESERIALIZE_READONLY) <> 0 Then
        memdbStoreLeave(pStore)
        Return SQLITE_IOERR_WRITE
    End If
    If pStore->sz > 0 AndAlso pStore->aData = 0 Then
        memdbStoreLeave(pStore)
        Return SQLITE_CORRUPT
    End If
    Dim writeEnd As sqlite3_int64 = offset + amount
    If writeEnd > pStore->sz Then
        Dim rc As SQLITE_C_INT = SQLITE_OK
        If writeEnd > pStore->szAlloc Then rc = memdbEnlarge(pStore, writeEnd)
        If rc <> SQLITE_OK Then
            memdbStoreLeave(pStore)
            Return rc
        End If
        If offset > pStore->sz Then
            memdbSystemMemset(pStore->aData + pStore->sz, 0, CULngInt(offset - pStore->sz))
        End If
        pStore->sz = writeEnd
    End If
    If amount > 0 Then memdbSystemMemcpy(pStore->aData + offset, pBuffer, CULngInt(amount))
    memdbStoreLeave(pStore)
    Return SQLITE_OK
End Function

Private Function memdbFileTruncate CDecl Alias "memdbTruncate" ( _
    ByVal pFile As Any Ptr, _
    ByVal size As sqlite3_int64 _
) As SQLITE_C_INT
    If pFile = 0 OrElse size < 0 Then Return SQLITE_MISUSE
    Dim pStore As MemdbStore Ptr = CPtr(MemdbFile Ptr, pFile)->pStore
    If pStore = 0 Then Return SQLITE_MISUSE
    memdbStoreEnter(pStore)
    If size > pStore->sz Then
        memdbStoreLeave(pStore)
        Return SQLITE_CORRUPT
    End If
    pStore->sz = size
    memdbStoreLeave(pStore)
    Return SQLITE_OK
End Function

Private Function memdbFileSync CDecl Alias "memdbSync" ( _
    ByVal pFile As Any Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
    Return SQLITE_OK
End Function

Private Function memdbFileSize CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal pSize As sqlite3_int64 Ptr _
) As SQLITE_C_INT
    If pFile = 0 OrElse pSize = 0 Then Return SQLITE_MISUSE
    Dim pStore As MemdbStore Ptr = CPtr(MemdbFile Ptr, pFile)->pStore
    If pStore = 0 Then Return SQLITE_MISUSE
    memdbStoreEnter(pStore)
    pSize[0] = pStore->sz
    memdbStoreLeave(pStore)
    Return SQLITE_OK
End Function

Private Function memdbFileLock CDecl Alias "memdbLock" ( _
    ByVal pFile As Any Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT

    If pFile = 0 OrElse lockLevel < SQLITE_LOCK_SHARED OrElse lockLevel > SQLITE_LOCK_EXCLUSIVE Then Return SQLITE_MISUSE
    Dim pMemFile As MemdbFile Ptr = CPtr(MemdbFile Ptr, pFile)
    Dim pStore As MemdbStore Ptr = pMemFile->pStore
    If pStore = 0 Then Return SQLITE_MISUSE
    If lockLevel <= pMemFile->eLock Then Return SQLITE_OK
    If lockLevel > SQLITE_LOCK_SHARED AndAlso (pStore->mFlags And SQLITE_DESERIALIZE_READONLY) <> 0 Then Return SQLITE_READONLY
    If lockLevel > SQLITE_LOCK_SHARED AndAlso pMemFile->eLock < SQLITE_LOCK_SHARED Then Return SQLITE_MISUSE

    memdbStoreEnter(pStore)
    Dim rc As SQLITE_C_INT = SQLITE_OK
    Select Case lockLevel
    Case SQLITE_LOCK_SHARED
        If pMemFile->eLock <> SQLITE_LOCK_NONE Then
            rc = SQLITE_MISUSE
        ElseIf pStore->nWrLock > 0 Then
            rc = SQLITE_BUSY
        ElseIf pStore->nRdLock = &H7FFFFFFF Then
            rc = SQLITE_FULL
        Else
            pStore->nRdLock += 1
        End If
    Case SQLITE_LOCK_RESERVED, SQLITE_LOCK_PENDING
        If pMemFile->eLock = SQLITE_LOCK_SHARED Then
            If pStore->nWrLock > 0 Then
                rc = SQLITE_BUSY
            Else
                pStore->nWrLock = 1
            End If
        End If
    Case SQLITE_LOCK_EXCLUSIVE
        If pStore->nRdLock > 1 Then
            rc = SQLITE_BUSY
        ElseIf pMemFile->eLock = SQLITE_LOCK_SHARED Then
            pStore->nWrLock = 1
        End If
    End Select
    If rc = SQLITE_OK Then pMemFile->eLock = lockLevel
    memdbStoreLeave(pStore)
    Return rc
End Function

Private Function memdbFileUnlock CDecl Alias "memdbUnlock" ( _
    ByVal pFile As Any Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT

    If pFile = 0 Then Return SQLITE_MISUSE
    Dim pMemFile As MemdbFile Ptr = CPtr(MemdbFile Ptr, pFile)
    Dim pStore As MemdbStore Ptr = pMemFile->pStore
    If pStore = 0 Then Return SQLITE_MISUSE
    If lockLevel >= pMemFile->eLock Then Return SQLITE_OK
    If lockLevel <> SQLITE_LOCK_SHARED AndAlso lockLevel <> SQLITE_LOCK_NONE Then Return SQLITE_MISUSE

    memdbStoreEnter(pStore)
    If lockLevel = SQLITE_LOCK_SHARED Then
        If pMemFile->eLock > SQLITE_LOCK_SHARED Then
            If pStore->nWrLock <= 0 Then
                memdbStoreLeave(pStore)
                Return SQLITE_CORRUPT
            End If
            pStore->nWrLock -= 1
        End If
    Else
        If pMemFile->eLock > SQLITE_LOCK_SHARED Then
            If pStore->nWrLock <= 0 Then
                memdbStoreLeave(pStore)
                Return SQLITE_CORRUPT
            End If
            pStore->nWrLock -= 1
        End If
        If pMemFile->eLock >= SQLITE_LOCK_SHARED Then
            If pStore->nRdLock <= 0 Then
                memdbStoreLeave(pStore)
                Return SQLITE_CORRUPT
            End If
            pStore->nRdLock -= 1
        End If
    End If
    pMemFile->eLock = lockLevel
    memdbStoreLeave(pStore)
    Return SQLITE_OK
End Function

Private Function memdbFileControl CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT

    If pFile = 0 Then Return SQLITE_MISUSE
    Dim pStore As MemdbStore Ptr = CPtr(MemdbFile Ptr, pFile)->pStore
    If pStore = 0 Then Return SQLITE_MISUSE
    If pArgument = 0 AndAlso (operation = SQLITE_FCNTL_VFSNAME OrElse operation = SQLITE_FCNTL_SIZE_LIMIT) Then Return SQLITE_MISUSE

    memdbStoreEnter(pStore)
    Select Case operation
    Case SQLITE_FCNTL_VFSNAME
        Dim description As String = "memdb(0x" & Hex(CULngInt(pStore->aData)) & "," & Trim(Str(pStore->sz)) & ")"
        Dim pDescription As UByte Ptr = CPtr(UByte Ptr, sqlite3Malloc(CULngInt(Len(description)) + 1))
        If pDescription = 0 Then
            memdbStoreLeave(pStore)
            Return SQLITE_NOMEM
        End If
        memdbSystemMemcpy(pDescription, StrPtr(description), CULngInt(Len(description)))
        pDescription[Len(description)] = 0
        CPtr(ZString Ptr Ptr, pArgument)[0] = CPtr(ZString Ptr, pDescription)
        memdbStoreLeave(pStore)
        Return SQLITE_OK
    Case SQLITE_FCNTL_SIZE_LIMIT
        Dim pLimit As sqlite3_int64 Ptr = CPtr(sqlite3_int64 Ptr, pArgument)
        Dim limit As sqlite3_int64 = pLimit[0]
        If limit < pStore->sz Then
            If limit < 0 Then
                limit = pStore->szMax
            Else
                limit = pStore->sz
            End If
        End If
        pStore->szMax = limit
        pLimit[0] = limit
        memdbStoreLeave(pStore)
        Return SQLITE_OK
    End Select
    memdbStoreLeave(pStore)
    Return SQLITE_NOTFOUND
End Function

Private Function memdbDeviceCharacteristics CDecl (ByVal pFile As Any Ptr) As SQLITE_C_INT
    If pFile = 0 Then Return 0
    Return SQLITE_IOCAP_ATOMIC Or SQLITE_IOCAP_POWERSAFE_OVERWRITE Or _
           SQLITE_IOCAP_SAFE_APPEND Or SQLITE_IOCAP_SEQUENTIAL
End Function

Private Function memdbFileFetch CDecl Alias "memdbFetch" ( _
    ByVal pFile As Any Ptr, _
    ByVal offset As sqlite3_int64, _
    ByVal amount As SQLITE_C_INT, _
    ByVal ppBuffer As Any Ptr Ptr _
) As SQLITE_C_INT

    If pFile = 0 OrElse ppBuffer = 0 OrElse amount < 0 OrElse offset < 0 Then Return SQLITE_MISUSE
    ppBuffer[0] = 0
    If offset > &H7FFFFFFFFFFFFFFF - amount Then Return SQLITE_OK
    Dim pStore As MemdbStore Ptr = CPtr(MemdbFile Ptr, pFile)->pStore
    If pStore = 0 Then Return SQLITE_MISUSE
    memdbStoreEnter(pStore)
    If amount > 0 AndAlso pStore->aData <> 0 AndAlso offset + amount <= pStore->sz AndAlso _
       (pStore->mFlags And SQLITE_DESERIALIZE_RESIZEABLE) = 0 Then
        If pStore->nMmap = &H7FFFFFFF Then
            memdbStoreLeave(pStore)
            Return SQLITE_FULL
        End If
        pStore->nMmap += 1
        ppBuffer[0] = pStore->aData + offset
    End If
    memdbStoreLeave(pStore)
    Return SQLITE_OK
End Function

Private Function memdbFileUnfetch CDecl Alias "memdbUnfetch" ( _
    ByVal pFile As Any Ptr, _
    ByVal offset As sqlite3_int64, _
    ByVal pBuffer As Any Ptr _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
    Dim pStore As MemdbStore Ptr = CPtr(MemdbFile Ptr, pFile)->pStore
    If pStore = 0 Then Return SQLITE_MISUSE
    memdbStoreEnter(pStore)
    If pStore->nMmap <= 0 Then
        memdbStoreLeave(pStore)
        Return SQLITE_CORRUPT
    End If
    pStore->nMmap -= 1
    memdbStoreLeave(pStore)
    Return SQLITE_OK
End Function

/' ------------------------------------------------------------------------- '/
/' sqlite3_vfs methods '/
/' ------------------------------------------------------------------------- '/

Private Function memdbVfsOpen CDecl Alias "memdbOpen" ( _
    ByVal pVfs As Any Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal pOutFlags As SQLITE_C_INT Ptr _
) As SQLITE_C_INT

    If pFile = 0 OrElse zName = 0 Then Return SQLITE_CANTOPEN
    Dim nameLength As SQLITE_C_INT = memdbStringLength(zName)
    If nameLength < 0 Then Return SQLITE_CANTOPEN
    Dim sharedName As SQLITE_C_INT = 0
    If nameLength > 1 AndAlso (zName[0] = Asc("/") OrElse zName[0] = Asc("\\")) Then sharedName = 1

    memdbInitializeIoMethods()
    If memdbMethodsReady = 0 Then Return SQLITE_ERROR
    memdbSystemMemset(pFile, 0, SizeOf(MemdbFile))
    Dim pMemFile As MemdbFile Ptr = CPtr(MemdbFile Ptr, pFile)
    Dim pStore As MemdbStore Ptr = 0
    Dim storeLocked As SQLITE_C_INT = 0

    If sharedName <> 0 Then
        Dim pVfsMutex As Any Ptr = sqlite3_mutex_alloc(SQLITE_MUTEX_STATIC_VFS1)
        If pVfsMutex = 0 Then Return SQLITE_ERROR
        sqlite3_mutex_enter(pVfsMutex)
        For i As SQLITE_C_INT = 0 To memdbStores.nMemStore - 1
            Dim pCandidate As MemdbStore Ptr = memdbStores.apMemStore[i]
            If pCandidate <> 0 AndAlso memdbStringEqual(pCandidate->zFName, zName, nameLength + 1) <> 0 Then
                pStore = pCandidate
                Exit For
            End If
        Next

        If pStore = 0 Then
            pStore = memdbNewStore(zName, nameLength)
            If pStore = 0 Then
                sqlite3_mutex_leave(pVfsMutex)
                Return SQLITE_NOMEM
            End If
            If memdbStores.nMemStore = &H7FFFFFFF Then
                memdbFreeStore(pStore)
                sqlite3_mutex_leave(pVfsMutex)
                Return SQLITE_FULL
            End If
            Dim newCount As sqlite3_uint64 = CULngInt(memdbStores.nMemStore) + 1
            Dim nByte As sqlite3_uint64 = newCount * SizeOf(MemdbStore Ptr)
            If nByte > SQLITE_MAX_ALLOCATION_SIZE Then
                memdbFreeStore(pStore)
                sqlite3_mutex_leave(pVfsMutex)
                Return SQLITE_FULL
            End If
            Dim pNewArray As MemdbStore Ptr Ptr = CPtr(MemdbStore Ptr Ptr, _
                sqlite3Realloc(memdbStores.apMemStore, nByte))
            If pNewArray = 0 Then
                memdbFreeStore(pStore)
                sqlite3_mutex_leave(pVfsMutex)
                Return SQLITE_NOMEM
            End If
            memdbStores.apMemStore = pNewArray
            memdbStores.apMemStore[memdbStores.nMemStore] = pStore
            memdbStores.nMemStore += 1
        Else
            If pStore->nRef = &H7FFFFFFF Then
                sqlite3_mutex_leave(pVfsMutex)
                Return SQLITE_FULL
            End If
            memdbStoreEnter(pStore)
            pStore->nRef += 1
            storeLocked = 1
        End If
        If storeLocked = 0 Then memdbStoreEnter(pStore)
        sqlite3_mutex_leave(pVfsMutex)
    Else
        pStore = memdbNewStore(0, 0)
        If pStore = 0 Then Return SQLITE_NOMEM
        memdbStoreEnter(pStore)
    End If

    pMemFile->base.pMethods = @memdbIoMethods
    pMemFile->pStore = pStore
    If pOutFlags <> 0 Then pOutFlags[0] = flags Or SQLITE_OPEN_MEMORY
    memdbStoreLeave(pStore)
    Return SQLITE_OK
End Function

Private Function memdbVfsAccess CDecl Alias "memdbAccess" ( _
    ByVal pVfs As Any Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pResult = 0 Then Return SQLITE_MISUSE
    pResult[0] = 0
    Return SQLITE_OK
End Function

Private Function memdbVfsFullPathname CDecl Alias "memdbFullPathname" ( _
    ByVal pVfs As Any Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal outputSize As SQLITE_C_INT, _
    ByVal zOutput As ZString Ptr _
) As SQLITE_C_INT
    If zName = 0 OrElse zOutput = 0 OrElse outputSize <= 0 Then Return SQLITE_MISUSE
    Dim nName As SQLITE_C_INT = memdbStringLength(zName)
    If nName < 0 OrElse nName + 1 > outputSize Then Return SQLITE_CANTOPEN
    If nName > 0 Then memdbSystemMemcpy(zOutput, zName, CULngInt(nName))
    zOutput[nName] = 0
    Return SQLITE_OK
End Function

Private Function memdbVfsDlOpen CDecl Alias "memdbDlOpen" (ByVal pVfs As Any Ptr, ByVal zName As Const ZString Ptr) As Any Ptr
    Dim pOriginal As sqlite3_vfs Ptr = memdbOriginalVfs(CPtr(sqlite3_vfs Ptr, pVfs))
    If pOriginal = 0 OrElse pOriginal->xDlOpen = 0 Then Return 0
    Return pOriginal->xDlOpen(pOriginal, zName)
End Function

Private Sub memdbVfsDlError CDecl Alias "memdbDlError" ( _
    ByVal pVfs As Any Ptr, _
    ByVal outputSize As SQLITE_C_INT, _
    ByVal zOutput As ZString Ptr _
)
    If zOutput = 0 OrElse outputSize <= 0 Then Exit Sub
    Dim pOriginal As sqlite3_vfs Ptr = memdbOriginalVfs(CPtr(sqlite3_vfs Ptr, pVfs))
    If pOriginal <> 0 AndAlso pOriginal->xDlError <> 0 Then
        pOriginal->xDlError(pOriginal, outputSize, zOutput)
    Else
        zOutput[0] = 0
    End If
End Sub

Private Function memdbVfsDlSym CDecl Alias "memdbDlSym" ( _
    ByVal pVfs As Any Ptr, _
    ByVal pHandle As Any Ptr, _
    ByVal zSymbol As Const ZString Ptr _
) As Any Ptr
    Dim pOriginal As sqlite3_vfs Ptr = memdbOriginalVfs(CPtr(sqlite3_vfs Ptr, pVfs))
    If pOriginal = 0 OrElse pOriginal->xDlSym = 0 Then Return 0
    Return pOriginal->xDlSym(pOriginal, pHandle, zSymbol)
End Function

Private Sub memdbVfsDlClose CDecl Alias "memdbDlClose" (ByVal pVfs As Any Ptr, ByVal pHandle As Any Ptr)
    Dim pOriginal As sqlite3_vfs Ptr = memdbOriginalVfs(CPtr(sqlite3_vfs Ptr, pVfs))
    If pOriginal <> 0 AndAlso pOriginal->xDlClose <> 0 Then pOriginal->xDlClose(pOriginal, pHandle)
End Sub

Private Function memdbVfsRandomness CDecl Alias "memdbRandomness" ( _
    ByVal pVfs As Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal zOutput As ZString Ptr _
) As SQLITE_C_INT
    If amount < 0 OrElse (amount > 0 AndAlso zOutput = 0) Then Return 0
    Dim pOriginal As sqlite3_vfs Ptr = memdbOriginalVfs(CPtr(sqlite3_vfs Ptr, pVfs))
    If pOriginal = 0 OrElse pOriginal->xRandomness = 0 Then Return 0
    Return pOriginal->xRandomness(pOriginal, amount, zOutput)
End Function

Private Function memdbVfsSleep CDecl Alias "memdbSleep" ( _
    ByVal pVfs As Any Ptr, _
    ByVal microseconds As SQLITE_C_INT _
) As SQLITE_C_INT
    Dim pOriginal As sqlite3_vfs Ptr = memdbOriginalVfs(CPtr(sqlite3_vfs Ptr, pVfs))
    If pOriginal = 0 OrElse pOriginal->xSleep = 0 Then Return 0
    Return pOriginal->xSleep(pOriginal, microseconds)
End Function

Private Function memdbVfsGetLastError CDecl Alias "memdbGetLastError" ( _
    ByVal pVfs As Any Ptr, _
    ByVal outputSize As SQLITE_C_INT, _
    ByVal zOutput As ZString Ptr _
) As SQLITE_C_INT
    If zOutput = 0 OrElse outputSize <= 0 Then Return SQLITE_MISUSE
    Dim pOriginal As sqlite3_vfs Ptr = memdbOriginalVfs(CPtr(sqlite3_vfs Ptr, pVfs))
    If pOriginal = 0 OrElse pOriginal->xGetLastError = 0 Then
        zOutput[0] = 0
        Return SQLITE_OK
    End If
    Return pOriginal->xGetLastError(pOriginal, outputSize, zOutput)
End Function

Private Function memdbVfsCurrentTimeInt64 CDecl Alias "memdbCurrentTimeInt64" ( _
    ByVal pVfs As Any Ptr, _
    ByVal pJulianDay As sqlite3_int64 Ptr _
) As SQLITE_C_INT
    If pJulianDay = 0 Then Return SQLITE_MISUSE
    Dim pOriginal As sqlite3_vfs Ptr = memdbOriginalVfs(CPtr(sqlite3_vfs Ptr, pVfs))
    If pOriginal = 0 OrElse pOriginal->xCurrentTimeInt64 = 0 Then Return SQLITE_ERROR
    Return pOriginal->xCurrentTimeInt64(pOriginal, pJulianDay)
End Function

/' ------------------------------------------------------------------------- '/
/' VFS registration '/
/' ------------------------------------------------------------------------- '/

Function sqlite3MemdbInit CDecl Alias "sqlite3MemdbInit" () As SQLITE_C_INT Export
    ' Keep registration idempotent without clearing a linked VFS's pNext field.
    Dim pRegistered As sqlite3_vfs Ptr = sqlite3_vfs_find(StrPtr("memdb"))
    If pRegistered = @memdbVfs Then Return SQLITE_OK
    Dim pOriginal As sqlite3_vfs Ptr = sqlite3_vfs_find(0)
    If pOriginal = 0 Then Return SQLITE_ERROR
    memdbInitializeIoMethods()
    If memdbMethodsReady = 0 Then Return SQLITE_ERROR

    memdbVfs.iVersion = 2
    memdbVfs.szOsFile = IIf(pOriginal->szOsFile > SizeOf(MemdbFile), pOriginal->szOsFile, SizeOf(MemdbFile))
    memdbVfs.mxPathname = MEMDB_MAX_PATHNAME
    memdbVfs.pNext = 0
    memdbVfs.zName = StrPtr("memdb")
    memdbVfs.pAppData = pOriginal
    memdbVfs.xOpen = @memdbVfsOpen
    memdbVfs.xDelete = 0
    memdbVfs.xAccess = @memdbVfsAccess
    memdbVfs.xFullPathname = @memdbVfsFullPathname
    memdbVfs.xDlOpen = @memdbVfsDlOpen
    memdbVfs.xDlError = @memdbVfsDlError
    memdbVfs.xDlSym = @memdbVfsDlSym
    memdbVfs.xDlClose = @memdbVfsDlClose
    memdbVfs.xRandomness = @memdbVfsRandomness
    memdbVfs.xSleep = @memdbVfsSleep
    memdbVfs.xCurrentTime = 0
    memdbVfs.xGetLastError = @memdbVfsGetLastError
    memdbVfs.xCurrentTimeInt64 = @memdbVfsCurrentTimeInt64
    memdbVfs.xSetSystemCall = 0
    memdbVfs.xGetSystemCall = 0
    memdbVfs.xNextSystemCall = 0
    Return sqlite3_vfs_register(@memdbVfs, 0)
End Function

Function sqlite3IsMemdb CDecl Alias "sqlite3IsMemdb" (ByVal pVfs As Const sqlite3_vfs Ptr) As SQLITE_C_INT Export
    If pVfs = 0 Then Return 0
    Return IIf(pVfs = @memdbVfs, 1, 0)
End Function
#endif

/' end of sqlite3_memdb.bas '/
