/'
    Project: SQLite FreeBASIC port

    File: sqlite3_wal.bas

    Purpose:

        Implement WAL handle management, transactions, frame access, and checkpoints.

    Responsibilities:

        - Advance a hash slot while preserving the WAL-index mask.
        - Release a WAL iterator allocated through SQLite's allocator.
        - Open and tear down a WAL handle.
        - Expose WAL callback progress, file access, and exclusive-mode transitions.
        - Read the committed database size from an open WAL handle.
        - Acquire WAL locks and retry them through the busy callback.
        - Reset checkpoint marks and apply WAL size limits.
        - Report page size and heap-memory mode.
        - Backfill checkpoint-safe WAL frames into the database file.
        - Report checkpoint progress and implement restart/truncate modes.
        - Encode and append WAL frames, then publish committed index updates.
        - Apply optional VFS blocking-lock hints for WAL readers and writers.
        - Acquire writer locks and roll back uncommitted frames and savepoints.
        - Read a WAL frame into a caller-provided page buffer.
        - Check the SEH build's shared-memory lock mask against WAL lock state.
        - Record Windows in-page exceptions and inject the matching fault code.
        - Find the newest committed frame for a database page.
        - Serialize WAL-index and checkpoint counters for optional WALSTAT diagnostics.
        - Validate frames and maintain frame-to-page hash entries.
        - Recover the WAL index from a WAL file while holding recovery locks.
        - Release transient locks and restore deferred index-page state after an SEH fault.
        - Format lock names for debug and test traces.
        - Start and end read transactions against a stable WAL-index snapshot.
        - Create, open, validate, and recover optional WAL snapshots.

    This file intentionally does NOT contain:

        - Public snapshot API wrappers and complete SEH/lock-timeout profiles.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_api_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_vfs.bi"
#include once "sqlite3_pager.bi"
#include once "sqlite3_straccum.bi"
#include once "sqlite3_debug_assert.bi"
#include once "sqlite3_win_exception_types.bi"

Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Declare Function sqlite3_malloc64 CDecl Alias "sqlite3_malloc64" (ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Function sqlite3MallocZero CDecl Alias "sqlite3MallocZero" (ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Function sqlite3Realloc CDecl Alias "sqlite3Realloc" (ByVal pOld As Any Ptr, ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Function walSystemMemcpy CDecl Alias "memcpy" (ByVal pDestination As Any Ptr, ByVal pSource As Const Any Ptr, ByVal nByte As SQLITE_SIZE_T) As Any Ptr
Declare Function walSystemMemcmp CDecl Alias "memcmp" (ByVal pLeft As Const Any Ptr, ByVal pRight As Const Any Ptr, ByVal nByte As SQLITE_SIZE_T) As SQLITE_C_INT
Declare Sub sqlite3BeginBenignMalloc CDecl Alias "sqlite3BeginBenignMalloc" ()
Declare Sub sqlite3EndBenignMalloc CDecl Alias "sqlite3EndBenignMalloc" ()
Declare Function sqlite3Get4byte CDecl Alias "sqlite3Get4byte" (ByVal p As Const UByte Ptr) As SQLITE_C_UINT
Declare Sub sqlite3Put4byte CDecl Alias "sqlite3Put4byte" (ByVal p As UByte Ptr, ByVal value As SQLITE_C_UINT)
Declare Sub sqlite3_randomness CDecl Alias "sqlite3_randomness" (ByVal amount As SQLITE_C_INT, ByVal pBuffer As Any Ptr)
Declare Function sqlite3FaultSim CDecl Alias "sqlite3FaultSim" (ByVal testNumber As SQLITE_C_INT) As SQLITE_C_INT
#if defined(SQLITE_OS_WIN) AndAlso defined(SQLITE_USE_SEH)
Declare Sub winRaiseException StdCall Lib "kernel32" Alias "RaiseException" ( _
    ByVal exceptionCode As SQLITE_C_UINT, _
    ByVal exceptionFlags As SQLITE_C_UINT, _
    ByVal argumentCount As SQLITE_C_UINT, _
    ByVal pArguments As Const SQLITE_SIZE_T Ptr _
)
#endif
Declare Sub sqlite3_log CDecl Alias "sqlite3_log" (ByVal errorCode As SQLITE_C_INT, ByVal format As Const ZString Ptr, ...)
Declare Sub sqlite3_str_appendf CDecl Alias "sqlite3_str_appendf" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)

' SQLite's 4096 page hash range uses two slots per page.
Private Const SQLITE_WAL_HASHTABLE_NSLOT As SQLITE_C_INT = 4096 * 2
Private Const SQLITE_WALINDEX_HASH_PAGE_FRAMES As SQLITE_C_INT = 4096
' The first page reserves 34 u32 words for its duplicated header and checkpoint info.
Private Const SQLITE_WALINDEX_FIRST_PAGE_FRAMES As SQLITE_C_INT = 4062
' SQLite's WAL hash multiplier disperses page numbers across the 8192 slots.
Private Const SQLITE_WALINDEX_HASH_1 As SQLITE_C_INT = 383
Private Const SQLITE_WALINDEX_PAGE_SIZE As SQLITE_C_INT = 32768
' The file header and each frame header have fixed 32-byte and 24-byte lengths.
Private Const SQLITE_WAL_HEADER_SIZE As SQLITE_C_INT = 32
Private Const SQLITE_WAL_FRAME_HEADER_SIZE As SQLITE_C_INT = 24
Private Const WAL_NORMAL_MODE As SQLITE_C_INT = 0
Private Const WAL_EXCLUSIVE_MODE As SQLITE_C_INT = 1
Private Const WAL_HEAPMEMORY_MODE As SQLITE_C_INT = 2
Private Const WAL_RDONLY As u8 = 1
Private Const WAL_SHM_RDONLY As u8 = 2
Private Const WAL_WRITE_LOCK As SQLITE_C_INT = 0
Private Const WAL_CKPT_LOCK As SQLITE_C_INT = 1
Private Const WAL_RECOVER_LOCK As SQLITE_C_INT = 2
Private Const WAL_READ_LOCK_BASE As SQLITE_C_INT = 3
Private Const WAL_ALL_BUT_WRITE As SQLITE_C_INT = 1
' WAL-index has five reader marks, including the no-lock slot at index zero.
Private Const WAL_NREADER As SQLITE_C_INT = 5
Private Const WAL_RETRY As SQLITE_C_INT = -1
Private Const WAL_RETRY_PROTOCOL_LIMIT As SQLITE_C_INT = 100
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
Private Const WAL_RETRY_BLOCKED_MASK As SQLITE_C_INT = &H10000000
#else
Private Const WAL_RETRY_BLOCKED_MASK As SQLITE_C_INT = 0
#endif
' This sentinel marks a shared-memory reader slot as unused.
Private Const READMARK_NOT_USED As u32 = &HFFFFFFFF
Private Const SQLITE_WALINDEX_HEADER_SIZE As SQLITE_C_INT = 136
Private Const SQLITE_WALINDEX_MAX_VERSION As u32 = 3007000
' WAL file magic has a low bit that records checksum byte order.
Private Const SQLITE_WAL_MAGIC As u32 = &H377F0682
' The low sync bits apply to WAL frames; the next two bits apply to checkpoints.
#define WAL_SYNC_FLAGS(syncFlags) ((syncFlags) And &H03)
#define CKPT_SYNC_FLAGS(syncFlags) (((syncFlags) Shr 2) And &H03)

#include once "sqlite3_wal_types.bi"

#if defined(SQLITE_DEBUG) AndAlso defined(SQLITE_USE_SEH)
Private Function walAssertLockmask CDecl Alias "walAssertLockmask" ( _
    ByVal pWal As SqliteWal Ptr _
) As SQLITE_C_INT
    If pWal = 0 Then Return 0
    If pWal->exclusiveMode = WAL_NORMAL_MODE Then
        Dim expectedMask As u32 = 0
        If pWal->readLock >= 0 Then
            If pWal->readLock >= WAL_NREADER Then
                sqlite3DebugAssert(StrPtr("WAL reader lock index is in range"))
                Return 0
            End If
            expectedMask Or= (1 Shl (WAL_READ_LOCK_BASE + pWal->readLock))
        End If
        If pWal->writeLock <> 0 Then _
            expectedMask Or= (1 Shl SQLITE_SHM_NLOCK) Shl WAL_WRITE_LOCK
        If pWal->checkpointLock <> 0 Then _
            expectedMask Or= (1 Shl SQLITE_SHM_NLOCK) Shl WAL_CKPT_LOCK
#ifdef SQLITE_ENABLE_SNAPSHOT
        If pWal->pSnapshot <> 0 Then _
            expectedMask Or= pWal->lockMask And (1 Shl WAL_CKPT_LOCK)
#endif
        If expectedMask <> pWal->lockMask Then
            sqlite3DebugAssert(StrPtr("WAL lock mask agrees with lock state"))
        End If
    End If
    Return 1
End Function
#endif

#if defined(SQLITE_TEST) AndAlso defined(SQLITE_DEBUG)
Declare Function sqlite3WalSnprintf CDecl Alias "sqlite3_snprintf" ( _
    ByVal nByte As SQLITE_C_INT, _
    ByVal zBuffer As ZString Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) As ZString Ptr

Private Function walLockName(ByVal lockIndex As SQLITE_C_INT) As Const ZString Ptr
    Static lockName(0 To 14) As Byte

    If lockIndex = WAL_WRITE_LOCK Then Return StrPtr(!"WRITE-LOCK")
    If lockIndex = WAL_CKPT_LOCK Then Return StrPtr(!"CKPT-LOCK")
    If lockIndex = WAL_RECOVER_LOCK Then Return StrPtr(!"RECOVER-LOCK")

    Return CPtr(Const ZString Ptr, sqlite3WalSnprintf( _
        Cast(SQLITE_C_INT, SizeOf(lockName)), _
        CPtr(ZString Ptr, @lockName(0)), StrPtr(!"READ-LOCK[%d]"), _
        lockIndex - WAL_READ_LOCK_BASE))
End Function
#endif

Private Function walNextHash CDecl Alias "walNextHash" ( _
    ByVal priorHash As SQLITE_C_INT _
) As SQLITE_C_INT
    Return (priorHash + 1) And (SQLITE_WAL_HASHTABLE_NSLOT - 1)
End Function

Private Sub walIteratorFree CDecl Alias "walIteratorFree" ( _
    ByVal pIterator As Any Ptr _
)
    sqlite3_free(pIterator)
End Sub

Private Sub walIndexClose CDecl Alias "walIndexClose" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal deleteFlag As SQLITE_C_INT _
)
    If pWal = 0 Then Exit Sub
    If pWal->exclusiveMode = WAL_HEAPMEMORY_MODE OrElse pWal->sharedMemoryUnreliable <> 0 Then
        If pWal->walIndexData <> 0 Then
            For pageIndex As SQLITE_C_INT = 0 To pWal->walIndexDataCount - 1
                If pWal->walIndexData[pageIndex] <> 0 Then
                    sqlite3_free(pWal->walIndexData[pageIndex])
                    pWal->walIndexData[pageIndex] = 0
                End If
            Next
        End If
    End If
    If pWal->exclusiveMode <> WAL_HEAPMEMORY_MODE AndAlso pWal->pDbFile <> 0 Then
        sqlite3OsShmUnmap(pWal->pDbFile, deleteFlag)
    End If
End Sub

Private Function walIndexPageRealloc CDecl Alias "walIndexPageRealloc" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal pageIndex As SQLITE_C_INT, _
    ByVal ppPage As u32 Ptr Ptr _
) As SQLITE_C_INT

    If ppPage = 0 Then Return SQLITE_MISUSE
    ppPage[0] = 0
    If pWal = 0 OrElse pageIndex < 0 Then Return SQLITE_MISUSE

    If pWal->walIndexDataCount <= pageIndex Then
        If CULngInt(pageIndex) >= CULngInt(SQLITE_MAX_ALLOCATION_SIZE) \ SizeOf(u32 Ptr) Then Return SQLITE_NOMEM
        Dim newCount As sqlite3_uint64 = CULngInt(pageIndex) + 1
        Dim newBytes As sqlite3_uint64 = newCount * SizeOf(u32 Ptr)
        Dim pNew As u32 Ptr Ptr = CPtr(u32 Ptr Ptr, sqlite3Realloc(pWal->walIndexData, newBytes))
        If pNew = 0 Then Return SQLITE_NOMEM
        For iPage As SQLITE_C_INT = pWal->walIndexDataCount To pageIndex
            pNew[iPage] = 0
        Next
        pWal->walIndexData = pNew
        pWal->walIndexDataCount = pageIndex + 1
    End If

    If pWal->walIndexData[pageIndex] <> 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pWal->exclusiveMode = WAL_HEAPMEMORY_MODE Then
        pWal->walIndexData[pageIndex] = CPtr(u32 Ptr, sqlite3MallocZero(SQLITE_WALINDEX_PAGE_SIZE))
        If pWal->walIndexData[pageIndex] = 0 Then rc = SQLITE_NOMEM
    Else
        Dim pMappedPage As Any Ptr = 0
        rc = sqlite3OsShmMap(pWal->pDbFile, pageIndex, SQLITE_WALINDEX_PAGE_SIZE, _
                             pWal->writeLock, @pMappedPage)
        pWal->walIndexData[pageIndex] = CPtr(u32 Ptr, pMappedPage)
        If rc = SQLITE_OK Then
            If pMappedPage = 0 AndAlso pageIndex > 0 Then rc = SQLITE_IOERR_SHMMAP
        ElseIf (rc And &HFF) = SQLITE_READONLY Then
            pWal->readOnly = pWal->readOnly Or WAL_SHM_RDONLY
            If rc = SQLITE_READONLY Then rc = SQLITE_OK
        End If
    End If

    ppPage[0] = pWal->walIndexData[pageIndex]
    Return rc
End Function

Private Function walIndexPage CDecl Alias "walIndexPage" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal pageIndex As SQLITE_C_INT, _
    ByVal ppPage As u32 Ptr Ptr _
) As SQLITE_C_INT

    If pWal = 0 OrElse ppPage = 0 OrElse pageIndex < 0 Then Return SQLITE_MISUSE
    If pageIndex >= pWal->walIndexDataCount OrElse pWal->walIndexData[pageIndex] = 0 Then
        Return walIndexPageRealloc(pWal, pageIndex, ppPage)
    End If
    ppPage[0] = pWal->walIndexData[pageIndex]
    Return SQLITE_OK
End Function

Private Function walCkptInfo CDecl Alias "walCkptInfo" ( _
    ByVal pWal As SqliteWal Ptr _
) As SqliteWalCheckpointInfo Ptr
    If pWal = 0 OrElse pWal->walIndexDataCount = 0 OrElse pWal->walIndexData = 0 OrElse _
       pWal->walIndexData[0] = 0 Then Return 0
    Dim pHeaderBytes As UByte Ptr = CPtr(UByte Ptr, pWal->walIndexData[0])
    Return CPtr(SqliteWalCheckpointInfo Ptr, pHeaderBytes + (2 * SizeOf(SqliteWalIndexHeader)))
End Function

Private Function walIndexHdr CDecl Alias "walIndexHdr" ( _
    ByVal pWal As SqliteWal Ptr _
) As SqliteWalIndexHeader Ptr
    If pWal = 0 OrElse pWal->walIndexDataCount = 0 OrElse pWal->walIndexData = 0 Then Return 0
    Return CPtr(SqliteWalIndexHeader Ptr, pWal->walIndexData[0])
End Function

Private Sub walShmBarrier CDecl Alias "walShmBarrier" ( _
    ByVal pWal As SqliteWal Ptr _
)
    If pWal = 0 OrElse pWal->exclusiveMode = WAL_HEAPMEMORY_MODE OrElse pWal->pDbFile = 0 Then Exit Sub
    sqlite3OsShmBarrier(pWal->pDbFile)
End Sub

Private Function walByteSwap32(ByVal value As u32) As u32
    Return ((value And &H000000FF) Shl 24) Or _
           ((value And &H0000FF00) Shl 8) Or _
           ((value And &H00FF0000) Shr 8) Or _
           ((value And &HFF000000) Shr 24)
End Function

Private Sub walChecksumBytes CDecl Alias "walChecksumBytes" ( _
    ByVal nativeChecksum As SQLITE_C_INT, _
    ByVal pBytes As UByte Ptr, _
    ByVal byteCount As SQLITE_C_INT, _
    ByVal pInitial As Const u32 Ptr, _
    ByVal pOutput As u32 Ptr _
)
    If pBytes = 0 OrElse pOutput = 0 OrElse byteCount < 8 OrElse _
       (byteCount And 7) <> 0 OrElse byteCount > 65536 Then Exit Sub
    Dim sum1 As u32 = 0
    Dim sum2 As u32 = 0
    If pInitial <> 0 Then
        sum1 = pInitial[0]
        sum2 = pInitial[1]
    End If
    Dim pWords As Const u32 Ptr = CPtr(Const u32 Ptr, pBytes)
    For byteOffset As SQLITE_C_INT = 0 To byteCount - 1 Step 8
        Dim word1 As u32 = pWords[byteOffset \ 4]
        Dim word2 As u32 = pWords[(byteOffset \ 4) + 1]
        If nativeChecksum = 0 Then
            word1 = walByteSwap32(word1)
            word2 = walByteSwap32(word2)
        End If
        sum1 = CUInt((CULngInt(sum1) + word1 + sum2) And &HFFFFFFFFULL)
        sum2 = CUInt((CULngInt(sum2) + word2 + sum1) And &HFFFFFFFFULL)
    Next
    pOutput[0] = sum1
    pOutput[1] = sum2
End Sub

Private Sub walIndexWriteHdr CDecl Alias "walIndexWriteHdr" ( _
    ByVal pWal As SqliteWal Ptr _
)
    If pWal = 0 OrElse pWal->writeLock = 0 Then Exit Sub
    Dim pPage0 As u32 Ptr = 0
    If walIndexPage(pWal, 0, @pPage0) <> SQLITE_OK OrElse pPage0 = 0 Then Exit Sub

    pWal->header.isInitialized = 1
    pWal->header.version = SQLITE_WALINDEX_MAX_VERSION
    walChecksumBytes(1, CPtr(UByte Ptr, @pWal->header), 40, 0, @pWal->header.checksum(0))
    Dim pHeader As SqliteWalIndexHeader Ptr = CPtr(SqliteWalIndexHeader Ptr, pPage0)
    pHeader[1] = pWal->header
    walShmBarrier(pWal)
    pHeader[0] = pWal->header
End Sub

Private Function walLockShared CDecl Alias "walLockShared" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal lockIndex As SQLITE_C_INT _
) As SQLITE_C_INT
    If pWal = 0 OrElse lockIndex < 0 OrElse lockIndex >= SQLITE_SHM_NLOCK Then Return SQLITE_MISUSE
    If pWal->exclusiveMode <> WAL_NORMAL_MODE Then Return SQLITE_OK
    Dim rc As SQLITE_C_INT = sqlite3OsShmLock(pWal->pDbFile, lockIndex, 1, _
        SQLITE_SHM_LOCK Or SQLITE_SHM_SHARED)
#ifdef SQLITE_USE_SEH
    If rc = SQLITE_OK Then pWal->lockMask = pWal->lockMask Or (1 Shl lockIndex)
#endif
    Return rc
End Function

Private Sub walUnlockShared CDecl Alias "walUnlockShared" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal lockIndex As SQLITE_C_INT _
)
    If pWal = 0 OrElse lockIndex < 0 OrElse lockIndex >= SQLITE_SHM_NLOCK Then Exit Sub
    If pWal->exclusiveMode <> WAL_NORMAL_MODE Then Exit Sub
    sqlite3OsShmLock(pWal->pDbFile, lockIndex, 1, SQLITE_SHM_UNLOCK Or SQLITE_SHM_SHARED)
#ifdef SQLITE_USE_SEH
    pWal->lockMask = pWal->lockMask And Not (1 Shl lockIndex)
#endif
End Sub

Private Function walLockExclusive CDecl Alias "walLockExclusive" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal lockIndex As SQLITE_C_INT, _
    ByVal lockCount As SQLITE_C_INT _
) As SQLITE_C_INT
    If pWal = 0 OrElse lockIndex < 0 OrElse lockCount <= 0 OrElse _
       lockCount > SQLITE_SHM_NLOCK - lockIndex Then Return SQLITE_MISUSE
    If pWal->exclusiveMode <> WAL_NORMAL_MODE Then Return SQLITE_OK
    Dim rc As SQLITE_C_INT = sqlite3OsShmLock(pWal->pDbFile, lockIndex, lockCount, _
        SQLITE_SHM_LOCK Or SQLITE_SHM_EXCLUSIVE)
#ifdef SQLITE_USE_SEH
    If rc = SQLITE_OK Then pWal->lockMask = pWal->lockMask Or _
        (((1 Shl lockCount) - 1) Shl (SQLITE_SHM_NLOCK + lockIndex))
#endif
    Return rc
End Function

#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
Private Function walEnableBlockingMs CDecl Alias "walEnableBlockingMs" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal milliseconds As SQLITE_C_INT _
) As SQLITE_C_INT
    If pWal = 0 OrElse pWal->pDbFile = 0 Then Return 0
    Dim timeout As SQLITE_C_INT = milliseconds
    ' File control returns the previous timeout through the same integer slot.
    Return IIf(sqlite3OsFileControl( _
        pWal->pDbFile, SQLITE_FCNTL_LOCK_TIMEOUT, @timeout) = SQLITE_OK, 1, 0)
End Function

Private Function walEnableBlocking CDecl Alias "walEnableBlocking" ( _
    ByVal pWal As SqliteWal Ptr _
) As SQLITE_C_INT
    If pWal = 0 OrElse pWal->db = 0 OrElse pWal->db->setlkTimeout = 0 Then Return 0
    Return walEnableBlockingMs(pWal, pWal->db->setlkTimeout)
End Function

Private Sub walDisableBlocking CDecl Alias "walDisableBlocking" ( _
    ByVal pWal As SqliteWal Ptr _
)
    If pWal = 0 OrElse pWal->pDbFile = 0 Then Exit Sub
    Dim timeout As SQLITE_C_INT = 0
    sqlite3OsFileControl(pWal->pDbFile, SQLITE_FCNTL_LOCK_TIMEOUT, @timeout)
End Sub
#endif

Private Function walBusyLock CDecl Alias "walBusyLock" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal xBusy As SqliteWalBusyCallback, _
    ByVal pBusyArg As Any Ptr, _
    ByVal lockIndex As SQLITE_C_INT, _
    ByVal lockCount As SQLITE_C_INT _
) As SQLITE_C_INT
    Dim rc As SQLITE_C_INT
    Do
        rc = walLockExclusive(pWal, lockIndex, lockCount)
        If xBusy = 0 OrElse rc <> SQLITE_BUSY Then Exit Do
        If xBusy(pBusyArg) = 0 Then Exit Do
    Loop
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    If rc = SQLITE_BUSY_TIMEOUT Then
        walDisableBlocking(pWal)
        rc = SQLITE_BUSY
    End If
#endif
    Return rc
End Function

Private Sub walUnlockExclusive CDecl Alias "walUnlockExclusive" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal lockIndex As SQLITE_C_INT, _
    ByVal lockCount As SQLITE_C_INT _
)
    If pWal = 0 OrElse lockIndex < 0 OrElse lockCount <= 0 OrElse _
       lockCount > SQLITE_SHM_NLOCK - lockIndex Then Exit Sub
    If pWal->exclusiveMode <> WAL_NORMAL_MODE Then Exit Sub
    sqlite3OsShmLock(pWal->pDbFile, lockIndex, lockCount, _
        SQLITE_SHM_UNLOCK Or SQLITE_SHM_EXCLUSIVE)
#ifdef SQLITE_USE_SEH
    pWal->lockMask = pWal->lockMask And Not _
        (((1 Shl lockCount) - 1) Shl (SQLITE_SHM_NLOCK + lockIndex))
#endif
End Sub

#ifdef SQLITE_USE_SEH
#ifdef SQLITE_OS_WIN
Private Function sehExceptionFilter CDecl Alias "sehExceptionFilter" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal exceptionCode As SQLITE_C_INT, _
    ByVal pExceptionPointers As SqliteWinExceptionPointers Ptr _
) As SQLITE_C_INT
    If pWal = 0 Then Return 0
#ifdef SQLITE_DEBUG
    pWal->sehTryCount -= 1
#endif
    If Cast(SQLITE_C_UINT, exceptionCode) = &HC0000006UL Then
        If pExceptionPointers <> 0 AndAlso _
           pExceptionPointers->pExceptionRecord <> 0 AndAlso _
           pExceptionPointers->pExceptionRecord->numberParameters >= 3 Then
            ' The third argument carries the NTSTATUS that caused the page fault.
            pWal->systemErrorNumber = Cast( _
                SQLITE_C_INT, _
                pExceptionPointers->pExceptionRecord->exceptionInformation(2))
        End If
        Return 1
    End If
    Return 0
End Function

Private Sub sehInjectFault CDecl Alias "sehInjectFault" ( _
    ByVal pWal As SqliteWal Ptr _
)
    If pWal = 0 Then Exit Sub
#ifdef SQLITE_DEBUG
    If pWal->sehTryCount <= 0 Then _
        sqlite3DebugAssert(StrPtr("SEH fault injection requires an active WAL try block"))
#endif
    ' Fault-simulation point 650 models a shared-memory page fault.
    Dim simulatedError As SQLITE_C_INT = sqlite3FaultSim(650)
    If simulatedError = 0 Then Exit Sub

    Dim exceptionArguments(0 To 2) As SQLITE_SIZE_T
    exceptionArguments(0) = 0
    exceptionArguments(1) = 0
    exceptionArguments(2) = CULngInt(simulatedError)
    winRaiseException( _
        &HC0000006UL, 0, 3, @exceptionArguments(0))
End Sub
#endif

Private Function walHandleException CDecl Alias "walHandleException" ( _
    ByVal pWal As SqliteWal Ptr _
) As SQLITE_C_INT
    If pWal = 0 Then Return SQLITE_MISUSE

    If pWal->exclusiveMode = 0 Then
        Const WAL_SHARED_LOCK_BIT As u32 = 1
        Const WAL_EXCLUSIVE_LOCK_BIT As u32 = (1 Shl SQLITE_SHM_NLOCK)
        Dim retainedLocks As u32 = 0

        If pWal->writeLock = 2 Then pWal->writeLock = 0
        If pWal->readLock >= 0 Then _
            retainedLocks Or= WAL_SHARED_LOCK_BIT Shl _
                (WAL_READ_LOCK_BASE + pWal->readLock)
        If pWal->writeLock <> 0 Then _
            retainedLocks Or= WAL_EXCLUSIVE_LOCK_BIT Shl WAL_WRITE_LOCK
        If pWal->checkpointLock <> 0 Then _
            retainedLocks Or= WAL_EXCLUSIVE_LOCK_BIT Shl WAL_CKPT_LOCK
#ifdef SQLITE_ENABLE_SNAPSHOT
        If pWal->pSnapshot <> 0 Then _
            retainedLocks Or= pWal->lockMask And (1 Shl WAL_CKPT_LOCK)
#endif

        Dim unlockMask As u32 = pWal->lockMask And Not retainedLocks
        For lockIndex As SQLITE_C_INT = 0 To SQLITE_SHM_NLOCK - 1
            If (unlockMask And (WAL_SHARED_LOCK_BIT Shl lockIndex)) <> 0 Then _
                walUnlockShared(pWal, lockIndex)
            If (unlockMask And (WAL_EXCLUSIVE_LOCK_BIT Shl lockIndex)) <> 0 Then _
                walUnlockExclusive(pWal, lockIndex, 1)
        Next
    End If

    sqlite3_free(pWal->pFree)
    pWal->pFree = 0
    If pWal->pWalIndexValue <> 0 Then
        pWal->walIndexData[pWal->walIndexPage] = pWal->pWalIndexValue
        pWal->pWalIndexValue = 0
    End If
    Return SQLITE_IOERR_IN_PAGE
End Function
#endif

#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
Function sqlite3WalWriteLock CDecl Alias "sqlite3WalWriteLock" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal bLock As SQLITE_C_INT _
) As SQLITE_C_INT
    If pWal = 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_DEBUG
    If pWal->readLock >= 0 AndAlso bLock <> 0 Then _
        sqlite3DebugAssert(StrPtr("WAL write lock is requested without a read lock"))
#endif

    Dim rc As SQLITE_C_INT = SQLITE_OK
    If bLock <> 0 Then
#ifdef SQLITE_DEBUG
        If pWal->db = 0 Then _
            sqlite3DebugAssert(StrPtr("WAL database handle is set before locking"))
#endif
        If walEnableBlocking(pWal) <> 0 Then
            rc = walLockExclusive(pWal, WAL_WRITE_LOCK, 1)
            If rc = SQLITE_OK Then pWal->writeLock = 1
            walDisableBlocking(pWal)
        End If
    ElseIf pWal->writeLock <> 0 Then
        walUnlockExclusive(pWal, WAL_WRITE_LOCK, 1)
        pWal->writeLock = 0
    End If
    Return rc
End Function
#endif

Private Function walIndexTryHdr CDecl Alias "walIndexTryHdr" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal pChanged As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pWal = 0 OrElse pChanged = 0 Then Return 1
    Dim pWalIndexHeader As SqliteWalIndexHeader Ptr = walIndexHdr(pWal)
    If pWalIndexHeader = 0 Then Return 1

    Dim firstHeader As SqliteWalIndexHeader
    Dim secondHeader As SqliteWalIndexHeader
    walSystemMemcpy(@firstHeader, pWalIndexHeader, SizeOf(firstHeader))
    walShmBarrier(pWal)
    walSystemMemcpy(@secondHeader, pWalIndexHeader + 1, SizeOf(secondHeader))
    If walSystemMemcmp(@firstHeader, @secondHeader, SizeOf(firstHeader)) <> 0 Then Return 1
    If firstHeader.isInitialized = 0 Then Return 1

    Dim expectedChecksum(0 To 1) As u32
    walChecksumBytes(1, CPtr(UByte Ptr, @firstHeader), _
        SizeOf(firstHeader) - (2 * SizeOf(u32)), 0, @expectedChecksum(0))
    If expectedChecksum(0) <> firstHeader.checksum(0) OrElse _
       expectedChecksum(1) <> firstHeader.checksum(1) Then Return 1

    If walSystemMemcmp(@pWal->header, @firstHeader, SizeOf(firstHeader)) <> 0 Then
        pChanged[0] = 1
        pWal->header = firstHeader
        Dim encodedPageSize As u32 = pWal->header.pageSize
        pWal->pageSize = (encodedPageSize And &HFE00) + _
            ((encodedPageSize And 1) Shl 16)
    End If
    Return 0
End Function

Function sqlite3WalOpen CDecl Alias "sqlite3WalOpen" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal pDbFile As sqlite3_file Ptr, _
    ByVal zWalName As Const ZString Ptr, _
    ByVal noSharedMemory As SQLITE_C_INT, _
    ByVal maxWalSize As sqlite3_int64, _
    ByVal ppWal As Any Ptr Ptr _
) As SQLITE_C_INT

    If ppWal = 0 Then Return SQLITE_MISUSE
    ppWal[0] = 0
    If pVfs = 0 OrElse pDbFile = 0 OrElse zWalName = 0 OrElse zWalName[0] = 0 OrElse _
       pVfs->szOsFile <= 0 OrElse noSharedMemory < 0 OrElse noSharedMemory > 1 Then Return SQLITE_MISUSE
#ifdef SQLITE_OMIT_WAL
    Return SQLITE_OK
#else
    If CULngInt(pVfs->szOsFile) > SQLITE_MAX_ALLOCATION_SIZE - SizeOf(SqliteWal) Then Return SQLITE_NOMEM
    Dim allocationSize As sqlite3_uint64 = CULngInt(SizeOf(SqliteWal)) + CULngInt(pVfs->szOsFile)
    Dim pMemory As Any Ptr = sqlite3MallocZero(allocationSize)
    If pMemory = 0 Then Return SQLITE_NOMEM

    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pMemory)
    pWal->pVfs = pVfs
    pWal->pDbFile = pDbFile
    pWal->pWalFile = CPtr(sqlite3_file Ptr, CPtr(UByte Ptr, pMemory) + SizeOf(SqliteWal))
    pWal->readLock = -1
    pWal->maxWalSize = maxWalSize
    ' The name is borrowed for the lifetime of the Pager and is never modified.
    pWal->walName = CPtr(ZString Ptr, zWalName)
    pWal->syncHeader = 1
    pWal->padToSectorBoundary = 1
    pWal->exclusiveMode = IIf(noSharedMemory <> 0, WAL_HEAPMEMORY_MODE, WAL_NORMAL_MODE)

    Dim openFlags As SQLITE_C_INT = SQLITE_OPEN_READWRITE Or SQLITE_OPEN_CREATE Or SQLITE_OPEN_WAL
    Dim actualFlags As SQLITE_C_INT = openFlags
    Dim rc As SQLITE_C_INT = sqlite3OsOpen(pVfs, zWalName, pWal->pWalFile, openFlags, @actualFlags)
    If rc = SQLITE_OK AndAlso (actualFlags And SQLITE_OPEN_READONLY) <> 0 Then pWal->readOnly = 1

    If rc <> SQLITE_OK Then
        walIndexClose(pWal, 0)
        sqlite3OsClose(pWal->pWalFile)
        sqlite3_free(pWal)
        Return rc
    End If

    Dim deviceCharacteristics As SQLITE_C_INT = sqlite3OsDeviceCharacteristics(pDbFile)
    If (deviceCharacteristics And SQLITE_IOCAP_SEQUENTIAL) <> 0 Then pWal->syncHeader = 0
    If (deviceCharacteristics And SQLITE_IOCAP_POWERSAFE_OVERWRITE) <> 0 Then _
        pWal->padToSectorBoundary = 0
    ppWal[0] = pWal
    Return SQLITE_OK
#endif
End Function

Function sqlite3WalDbsize CDecl Alias "sqlite3WalDbsize" ( _
    ByVal pWal As Any Ptr _
) As u32
#ifdef SQLITE_OMIT_WAL
    Return 0
#else
    If pWal = 0 Then Return 0
    Dim pWalPrefix As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWal)
    If pWalPrefix->readLock < 0 Then Return 0
    Return pWalPrefix->header.pageCount
#endif
End Function


' ---------------------------------------------------------------------------
' WAL mode control and checkpoint state
' ---------------------------------------------------------------------------

Private Function walPagesize CDecl Alias "walPagesize" ( _
    ByVal pWalArgument As Any Ptr _
) As SQLITE_C_INT
    If pWalArgument = 0 Then Return 0
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    Dim encodedPageSize As SQLITE_C_UINT = pWal->header.pageSize
    Return Cast(SQLITE_C_INT, _
        (encodedPageSize And &HFE00) Or ((encodedPageSize And &H0001) Shl 16))
End Function

Sub sqlite3WalLimit CDecl Alias "sqlite3WalLimit" ( _
    ByVal pWalArgument As Any Ptr, _
    ByVal maximumWalSize As sqlite3_int64 _
)
    If pWalArgument = 0 Then Exit Sub
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    pWal->maxWalSize = maximumWalSize
End Sub

Function sqlite3WalHeapMemory CDecl Alias "sqlite3WalHeapMemory" ( _
    ByVal pWalArgument As Any Ptr _
) As SQLITE_C_INT
    If pWalArgument = 0 Then Return 0
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    Return IIf(pWal->exclusiveMode = WAL_HEAPMEMORY_MODE, 1, 0)
End Function

#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
Sub sqlite3WalDb CDecl Alias "sqlite3WalDb" ( _
    ByVal pWalArgument As Any Ptr, _
    ByVal dbArgument As Any Ptr _
)
    If pWalArgument = 0 Then Exit Sub
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    pWal->db = CPtr(sqlite3 Ptr, dbArgument)
End Sub
#endif

#ifdef SQLITE_USE_SEH
Function sqlite3WalSystemErrno CDecl Alias "sqlite3WalSystemErrno" ( _
    ByVal pWalArgument As Any Ptr _
) As SQLITE_C_INT
    If pWalArgument = 0 Then Return 0
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    Dim systemError As SQLITE_C_INT = pWal->systemErrorNumber
    pWal->systemErrorNumber = 0
    Return systemError
End Function
#endif

Private Sub walRestartHdr CDecl Alias "walRestartHdr" ( _
    ByVal pWalArgument As Any Ptr, _
    ByVal newSalt As u32 _
)
    If pWalArgument = 0 Then Exit Sub
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    If pWal->writeLock = 0 Then Exit Sub

    Dim pInfo As SqliteWalCheckpointInfo Ptr = walCkptInfo(pWal)
    If pInfo = 0 Then Exit Sub

    pWal->checkpointSequence += 1
    pWal->header.maxFrame = 0
    Dim pSaltBytes As UByte Ptr = CPtr(UByte Ptr, @pWal->header.salt(0))
    Dim nextSalt As sqlite3_uint64 = _
        CULngInt(sqlite3Get4byte(pSaltBytes)) + 1ULL
    sqlite3Put4byte(pSaltBytes, CUInt(nextSalt And &HFFFFFFFFULL))
    pWal->header.salt(1) = newSalt
    walIndexWriteHdr(pWal)

    ' Publish the new WAL header before clearing checkpoint and reader marks.
    walShmBarrier(pWal)
    pInfo->nBackfill = 0
    pInfo->nBackfillAttempted = 0
    pInfo->readMark(1) = 0
    For readIndex As SQLITE_C_INT = 2 To WAL_NREADER - 1
        pInfo->readMark(readIndex) = READMARK_NOT_USED
    Next
    walShmBarrier(pWal)
End Sub

Private Sub walLimitSize CDecl Alias "walLimitSize" ( _
    ByVal pWalArgument As Any Ptr, _
    ByVal maximumBytes As sqlite3_int64 _
)
    If pWalArgument = 0 OrElse maximumBytes < 0 Then Exit Sub
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    If pWal->pWalFile = 0 Then Exit Sub

    Dim fileSize As sqlite3_int64 = 0
    sqlite3BeginBenignMalloc()
    Dim rc As SQLITE_C_INT = sqlite3OsFileSize(pWal->pWalFile, @fileSize)
    If rc = SQLITE_OK AndAlso fileSize > maximumBytes Then
        rc = sqlite3OsTruncate(pWal->pWalFile, maximumBytes)
    End If
    sqlite3EndBenignMalloc()
    If rc <> SQLITE_OK AndAlso pWal->walName <> 0 Then
        sqlite3_log(rc, StrPtr(!"cannot limit WAL size: %s"), pWal->walName)
    End If
End Sub


Function sqlite3WalReadFrame CDecl Alias "sqlite3WalReadFrame" ( _
    ByVal pWalArgument As Any Ptr, _
    ByVal frameIndex As SQLITE_C_UINT, _
    ByVal outputSize As SQLITE_C_INT, _
    ByVal pOutput As UByte Ptr _
) As SQLITE_C_INT
    If pWalArgument = 0 OrElse frameIndex = 0 OrElse outputSize < 0 OrElse _
       (outputSize > 0 AndAlso pOutput = 0) Then Return SQLITE_MISUSE
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    If pWal->pWalFile = 0 Then Return SQLITE_MISUSE

    Dim pageSize As SQLITE_C_INT = walPagesize(pWal)
    If pageSize <= 0 OrElse pageSize > 65536 Then Return SQLITE_CORRUPT
    Dim bytesToRead As SQLITE_C_INT = outputSize
    If bytesToRead > pageSize Then
        ' SQLite callers may request a larger page buffer than the WAL page.
        For byteIndex As SQLITE_C_INT = pageSize To bytesToRead - 1
            pOutput[byteIndex] = 0
        Next
        bytesToRead = pageSize
    End If
    If bytesToRead = 0 Then Return SQLITE_OK

    Dim frameBytes As sqlite3_uint64 = _
        CULngInt(pageSize) + SQLITE_WAL_FRAME_HEADER_SIZE
    Dim fileOffset As sqlite3_uint64 = SQLITE_WAL_HEADER_SIZE + _
        (CULngInt(frameIndex) - 1) * frameBytes + SQLITE_WAL_FRAME_HEADER_SIZE
    If fileOffset > &H7FFFFFFFFFFFFFFFULL Then Return SQLITE_TOOBIG
    Return sqlite3OsRead(pWal->pWalFile, pOutput, bytesToRead, CLngInt(fileOffset))
End Function


' ---------------------------------------------------------------------------
' WAL-index frame lookup
' ---------------------------------------------------------------------------

Private Function walHash CDecl Alias "walHash" ( _
    ByVal pageNumber As u32 _
) As SQLITE_C_INT
    Return Cast(SQLITE_C_INT, _
        (CULngInt(pageNumber) * SQLITE_WALINDEX_HASH_1) And _
        (SQLITE_WAL_HASHTABLE_NSLOT - 1))
End Function

Private Function walFramePage CDecl Alias "walFramePage" ( _
    ByVal frameIndex As u32 _
) As SQLITE_C_INT
    ' Frame zero maps to index page zero, matching the WAL-index layout formula.
    If frameIndex = 0 Then Return 0
    Dim adjustedFrame As sqlite3_uint64 = _
        CULngInt(frameIndex) + SQLITE_WALINDEX_HASH_PAGE_FRAMES - _
        SQLITE_WALINDEX_FIRST_PAGE_FRAMES - 1
    Return CLngInt(adjustedFrame \ SQLITE_WALINDEX_HASH_PAGE_FRAMES)
End Function

Private Function walHashGet CDecl Alias "walHashGet" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal hashPageIndex As SQLITE_C_INT, _
    ByVal pLocation As SqliteWalHashLocation Ptr _
) As SQLITE_C_INT
    If pWal = 0 OrElse pLocation = 0 OrElse hashPageIndex < 0 Then Return SQLITE_MISUSE
    pLocation->aPgno = 0
    pLocation->aHash = 0
    pLocation->iZero = 0

    Dim pPage As u32 Ptr = 0
    Dim rc As SQLITE_C_INT = walIndexPage(pWal, hashPageIndex, @pPage)
    If rc <> SQLITE_OK Then Return rc
    If pPage = 0 Then Return SQLITE_ERROR

    pLocation->aHash = CPtr(UShort Ptr, pPage + SQLITE_WALINDEX_HASH_PAGE_FRAMES)
    If hashPageIndex = 0 Then
        pLocation->aPgno = pPage + (SQLITE_WALINDEX_HEADER_SIZE \ SizeOf(u32))
        pLocation->iZero = 0
    Else
        pLocation->aPgno = pPage
        Dim firstFrame As sqlite3_uint64 = _
            CULngInt(SQLITE_WALINDEX_FIRST_PAGE_FRAMES) + _
            (CULngInt(hashPageIndex) - 1ULL) * SQLITE_WALINDEX_HASH_PAGE_FRAMES
        pLocation->iZero = CUInt(firstFrame)
    End If
    Return SQLITE_OK
End Function

Private Function walFramePgno CDecl Alias "walFramePgno" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal frameIndex As u32 _
) As u32
    If pWal = 0 OrElse frameIndex = 0 Then Return 0
    Dim hashPageIndex As SQLITE_C_INT = walFramePage(frameIndex)
    If hashPageIndex < 0 OrElse hashPageIndex >= pWal->walIndexDataCount OrElse _
       pWal->walIndexData = 0 OrElse pWal->walIndexData[hashPageIndex] = 0 Then Return 0

    Dim pageEntry As SQLITE_C_INT
    If hashPageIndex = 0 Then
        pageEntry = (SQLITE_WALINDEX_HEADER_SIZE \ SizeOf(u32)) + _
                    CLngInt(frameIndex) - 1
    Else
        pageEntry = (CLngInt(frameIndex) - 1 - SQLITE_WALINDEX_FIRST_PAGE_FRAMES) And _
                    (SQLITE_WALINDEX_HASH_PAGE_FRAMES - 1)
    End If
    If pageEntry < 0 OrElse pageEntry >= SQLITE_WALINDEX_HASH_PAGE_FRAMES Then Return 0
    Return pWal->walIndexData[hashPageIndex][pageEntry]
End Function

Private Function walFindFrame CDecl Alias "walFindFrame" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal pageNumber As u32, _
    ByVal pReadFrame As u32 Ptr _
) As SQLITE_C_INT
    If pWal = 0 OrElse pReadFrame = 0 OrElse pageNumber = 0 Then Return SQLITE_MISUSE
    pReadFrame[0] = 0
    If pWal->readLock < 0 Then Return SQLITE_MISUSE

    Dim lastFrame As u32 = pWal->header.maxFrame
    If lastFrame = 0 OrElse _
       (pWal->readLock = 0 AndAlso pWal->sharedMemoryUnreliable = 0) Then Return SQLITE_OK
    If pWal->minFrame = 0 AndAlso pWal->sharedMemoryUnreliable = 0 Then _
        Return SQLITE_CORRUPT
    ' Read-only SHM recovery may leave minFrame at zero. In that case the
    ' WAL hash search begins at its first page, matching wal.c.
    Dim firstHashPage As SQLITE_C_INT = walFramePage(pWal->minFrame)
    Dim lastHashPage As SQLITE_C_INT = walFramePage(lastFrame)
    If firstHashPage < 0 OrElse lastHashPage < firstHashPage Then Return SQLITE_CORRUPT

    Dim foundFrame As u32 = 0
    For hashPageIndex As SQLITE_C_INT = lastHashPage To firstHashPage Step -1
        Dim location As SqliteWalHashLocation
        Dim rc As SQLITE_C_INT = walHashGet(pWal, hashPageIndex, @location)
        If rc <> SQLITE_OK Then Return rc

        walShmBarrier(pWal)
        Dim hashIndex As SQLITE_C_INT = walHash(pageNumber)
        Dim collisionsRemaining As SQLITE_C_INT = SQLITE_WAL_HASHTABLE_NSLOT
        While 1
            Dim hashValue As UShort = location.aHash[hashIndex]
            If hashValue = 0 Then Exit While
            If collisionsRemaining = 0 Then Return SQLITE_CORRUPT
            collisionsRemaining -= 1

            ' The page-number slot is written before its hash slot. The
            ' barrier pairs with the writer's publication of the hash entry.
            walShmBarrier(pWal)
            Dim candidateFrame64 As sqlite3_uint64 = _
                CULngInt(hashValue) + CULngInt(location.iZero)
            If candidateFrame64 <= &HFFFFFFFFULL Then
                Dim candidateFrame As u32 = CUInt(candidateFrame64)
                Dim pageEntry As SQLITE_C_INT = _
                    (CLngInt(hashValue) - 1) And (SQLITE_WALINDEX_HASH_PAGE_FRAMES - 1)
                If candidateFrame <= lastFrame AndAlso _
                   candidateFrame >= pWal->minFrame AndAlso _
                   location.aPgno[pageEntry] = pageNumber Then
                    If candidateFrame > foundFrame Then foundFrame = candidateFrame
                End If
            End If
            hashIndex = walNextHash(hashIndex)
        Wend
        If foundFrame <> 0 Then Exit For
    Next

    pReadFrame[0] = foundFrame
    Return SQLITE_OK
End Function

Function sqlite3WalFindFrame CDecl Alias "sqlite3WalFindFrame" ( _
    ByVal pWalArgument As Any Ptr, _
    ByVal pageNumber As SQLITE_C_UINT, _
    ByVal pReadFrame As SQLITE_C_UINT Ptr _
) As SQLITE_C_INT
    If pWalArgument = 0 OrElse pReadFrame = 0 Then Return SQLITE_MISUSE
    Return walFindFrame(CPtr(SqliteWal Ptr, pWalArgument), pageNumber, pReadFrame)
End Function


' ---------------------------------------------------------------------------
' WAL frame validation and hash-index updates
' ---------------------------------------------------------------------------

Private Function walHostIsBigEndian() As SQLITE_C_INT
    Dim byteOrderProbe As u32 = 1
    Return IIf(CPtr(UByte Ptr, @byteOrderProbe)[0] = 0, 1, 0)
End Function

Private Function walDecodeFrame CDecl Alias "walDecodeFrame" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal pPageNumber As u32 Ptr, _
    ByVal pDatabaseSize As u32 Ptr, _
    ByVal pData As UByte Ptr, _
    ByVal pFrame As UByte Ptr _
) As SQLITE_C_INT
    If pWal = 0 OrElse pPageNumber = 0 OrElse pDatabaseSize = 0 OrElse _
       pData = 0 OrElse pFrame = 0 OrElse pWal->pageSize = 0 Then Return 0

    If walSystemMemcmp(@pWal->header.salt(0), pFrame + 8, 8) <> 0 Then Return 0
    Dim pageNumber As u32 = sqlite3Get4byte(pFrame)
    If pageNumber = 0 Then Return 0

    Dim nativeChecksum As SQLITE_C_INT = _
        IIf(pWal->header.bigEndianChecksum = walHostIsBigEndian(), 1, 0)
    walChecksumBytes(nativeChecksum, pFrame, 8, _
        @pWal->header.frameChecksum(0), @pWal->header.frameChecksum(0))
    walChecksumBytes(nativeChecksum, pData, CLng(pWal->pageSize), _
        @pWal->header.frameChecksum(0), @pWal->header.frameChecksum(0))
    If pWal->header.frameChecksum(0) <> sqlite3Get4byte(pFrame + 16) OrElse _
       pWal->header.frameChecksum(1) <> sqlite3Get4byte(pFrame + 20) Then Return 0

    pPageNumber[0] = pageNumber
    pDatabaseSize[0] = sqlite3Get4byte(pFrame + 4)
    Return 1
End Function

Private Sub walCleanupHash CDecl Alias "walCleanupHash" ( _
    ByVal pWal As SqliteWal Ptr _
)
    If pWal = 0 OrElse pWal->writeLock = 0 OrElse pWal->header.maxFrame = 0 Then Exit Sub

    Dim hashPageIndex As SQLITE_C_INT = walFramePage(pWal->header.maxFrame)
    If hashPageIndex < 0 Then Exit Sub
    Dim location As SqliteWalHashLocation
    If walHashGet(pWal, hashPageIndex, @location) <> SQLITE_OK OrElse _
       location.aPgno = 0 OrElse location.aHash = 0 Then Exit Sub

    Dim indexLimit As u32 = pWal->header.maxFrame - location.iZero
    If indexLimit = 0 Then Exit Sub
    For hashIndex As SQLITE_C_INT = 0 To SQLITE_WAL_HASHTABLE_NSLOT - 1
        If CUInt(location.aHash[hashIndex]) > indexLimit Then _
            location.aHash[hashIndex] = 0
    Next

    Dim pageNumberSlots As SQLITE_C_INT = SQLITE_WALINDEX_HASH_PAGE_FRAMES
    If hashPageIndex = 0 Then pageNumberSlots = SQLITE_WALINDEX_FIRST_PAGE_FRAMES
    If indexLimit >= CUInt(pageNumberSlots) Then Exit Sub
    For entryIndex As SQLITE_C_INT = CLng(indexLimit) To pageNumberSlots - 1
        location.aPgno[entryIndex] = 0
    Next
End Sub

Private Function walIndexAppend CDecl Alias "walIndexAppend" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal frameIndex As u32, _
    ByVal pageNumber As u32 _
) As SQLITE_C_INT
    If pWal = 0 OrElse frameIndex = 0 OrElse pageNumber = 0 OrElse _
       pWal->writeLock = 0 Then Return SQLITE_MISUSE

    Dim hashPageIndex As SQLITE_C_INT = walFramePage(frameIndex)
    If hashPageIndex < 0 Then Return SQLITE_CORRUPT
    Dim location As SqliteWalHashLocation
    Dim rc As SQLITE_C_INT = walHashGet(pWal, hashPageIndex, @location)
    If rc <> SQLITE_OK Then Return rc
    If location.aPgno = 0 OrElse location.aHash = 0 Then Return SQLITE_CORRUPT

    Dim index As u32 = frameIndex - location.iZero
    Dim pageNumberSlots As SQLITE_C_INT = SQLITE_WALINDEX_HASH_PAGE_FRAMES
    If hashPageIndex = 0 Then pageNumberSlots = SQLITE_WALINDEX_FIRST_PAGE_FRAMES
    If index = 0 OrElse index > CUInt(pageNumberSlots) OrElse _
       index > (SQLITE_WAL_HASHTABLE_NSLOT \ 2) + 1 Then Return SQLITE_CORRUPT

    If index = 1 Then
        ' A new hash page starts with empty page-number and hash arrays.
        For entryIndex As SQLITE_C_INT = 0 To pageNumberSlots - 1
            location.aPgno[entryIndex] = 0
        Next
        For hashIndex As SQLITE_C_INT = 0 To SQLITE_WAL_HASHTABLE_NSLOT - 1
            location.aHash[hashIndex] = 0
        Next
    End If

    Dim pageEntry As SQLITE_C_INT = _
        (CLng(index) - 1) And (SQLITE_WALINDEX_HASH_PAGE_FRAMES - 1)
    If location.aPgno[pageEntry] <> 0 Then
        walCleanupHash(pWal)
        If location.aPgno[pageEntry] <> 0 Then Return SQLITE_CORRUPT
    End If

    Dim hashIndex As SQLITE_C_INT = walHash(pageNumber)
    Dim collisionsRemaining As SQLITE_C_INT = CLng(index)
    While location.aHash[hashIndex] <> 0
        If collisionsRemaining = 0 Then Return SQLITE_CORRUPT
        collisionsRemaining -= 1
        hashIndex = walNextHash(hashIndex)
    Wend

    location.aPgno[pageEntry] = pageNumber
    walShmBarrier(pWal)
    location.aHash[hashIndex] = CUShort(index)
    Return SQLITE_OK
End Function


' ---------------------------------------------------------------------------
' WAL checkpoint iterator
' ---------------------------------------------------------------------------

Private Function walIteratorHeaderBytes() As sqlite3_uint64
    Return SizeOf(SqliteWalIterator) - SizeOf(SqliteWalSegment)
End Function

Private Function walMerge( _
    ByVal pContent As Const u32 Ptr, _
    ByVal pLeft As UShort Ptr, _
    ByVal leftCount As SQLITE_C_INT, _
    ByVal ppRight As UShort Ptr Ptr, _
    ByVal pRightCount As SQLITE_C_INT Ptr, _
    ByVal pTemporary As UShort Ptr _
) As SQLITE_C_INT
    If pContent = 0 OrElse pLeft = 0 OrElse ppRight = 0 OrElse _
       pRightCount = 0 OrElse pTemporary = 0 OrElse leftCount <= 0 OrElse _
       ppRight[0] = 0 OrElse pRightCount[0] <= 0 Then Return SQLITE_MISUSE

    Dim pRight As UShort Ptr = ppRight[0]
    Dim rightCount As SQLITE_C_INT = pRightCount[0]
    Dim leftIndex As SQLITE_C_INT = 0
    Dim rightIndex As SQLITE_C_INT = 0
    Dim outputIndex As SQLITE_C_INT = 0

    While rightIndex < rightCount OrElse leftIndex < leftCount
        Dim slot As UShort
        If leftIndex < leftCount AndAlso _
           (rightIndex >= rightCount OrElse _
            pContent[pLeft[leftIndex]] < pContent[pRight[rightIndex]]) Then
            slot = pLeft[leftIndex]
            leftIndex += 1
        Else
            slot = pRight[rightIndex]
            rightIndex += 1
        End If

        Dim pageNumber As u32 = pContent[slot]
        pTemporary[outputIndex] = slot
        outputIndex += 1
        If leftIndex < leftCount AndAlso pContent[pLeft[leftIndex]] = pageNumber Then _
            leftIndex += 1
    Wend

    ppRight[0] = pLeft
    pRightCount[0] = outputIndex
    walSystemMemcpy(pLeft, pTemporary, _
        CULngInt(outputIndex) * SizeOf(UShort))
    Return SQLITE_OK
End Function

Private Function walMergesort( _
    ByVal pContent As Const u32 Ptr, _
    ByVal pTemporary As UShort Ptr, _
    ByVal pList As UShort Ptr, _
    ByVal pListCount As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pContent = 0 OrElse pTemporary = 0 OrElse pList = 0 OrElse _
       pListCount = 0 OrElse pListCount[0] <= 0 OrElse _
       pListCount[0] > SQLITE_WALINDEX_HASH_PAGE_FRAMES Then Return SQLITE_MISUSE

    Dim sublistCount(0 To 12) As SQLITE_C_INT
    Dim sublist(0 To 12) As UShort Ptr
    Dim listIndex As SQLITE_C_INT
    Dim sublistIndex As SQLITE_C_INT
    Dim mergedCount As SQLITE_C_INT
    Dim pMerged As UShort Ptr

    For sublistIndex = 0 To 12
        sublistCount(sublistIndex) = 0
        sublist(sublistIndex) = 0
    Next

    Dim listCount As SQLITE_C_INT = pListCount[0]
    For listIndex = 0 To listCount - 1
        mergedCount = 1
        pMerged = pList + listIndex
        sublistIndex = 0
        While sublistIndex < 13 AndAlso _
              (listIndex And (1 Shl sublistIndex)) <> 0
            If sublist(sublistIndex) = 0 OrElse sublistCount(sublistIndex) <= 0 Then _
                Return SQLITE_CORRUPT
            Dim rc As SQLITE_C_INT = walMerge(pContent, sublist(sublistIndex), _
                sublistCount(sublistIndex), @pMerged, @mergedCount, pTemporary)
            If rc <> SQLITE_OK Then Return rc
            sublistIndex += 1
        Wend
        If sublistIndex >= 13 Then Return SQLITE_CORRUPT
        sublist(sublistIndex) = pMerged
        sublistCount(sublistIndex) = mergedCount
    Next

    sublistIndex += 1
    While sublistIndex < 13
        If (listCount And (1 Shl sublistIndex)) <> 0 Then
            If sublist(sublistIndex) = 0 OrElse sublistCount(sublistIndex) <= 0 Then _
                Return SQLITE_CORRUPT
            Dim rc As SQLITE_C_INT = walMerge(pContent, sublist(sublistIndex), _
                sublistCount(sublistIndex), @pMerged, @mergedCount, pTemporary)
            If rc <> SQLITE_OK Then Return rc
        End If
        sublistIndex += 1
    Wend

    If pMerged <> pList Then Return SQLITE_CORRUPT
    pListCount[0] = mergedCount
    Return SQLITE_OK
End Function

Private Function walIteratorInit CDecl Alias "walIteratorInit" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal backfillFrame As u32, _
    ByVal ppIterator As SqliteWalIterator Ptr Ptr _
) As SQLITE_C_INT
    If ppIterator = 0 Then Return SQLITE_MISUSE
    ppIterator[0] = 0
    If pWal = 0 OrElse pWal->checkpointLock = 0 OrElse _
       pWal->header.maxFrame = 0 OrElse backfillFrame >= pWal->header.maxFrame Then _
        Return SQLITE_OK
    If backfillFrame = &HFFFFFFFFUL Then Return SQLITE_CORRUPT

    Dim firstHashPage As SQLITE_C_INT = walFramePage(backfillFrame + 1)
    Dim lastHashPage As SQLITE_C_INT = walFramePage(pWal->header.maxFrame)
    If firstHashPage < 0 OrElse lastHashPage < firstHashPage Then Return SQLITE_CORRUPT

    Dim firstFrameZero As sqlite3_uint64 = 0
    If firstHashPage > 0 Then
        firstFrameZero = CULngInt(SQLITE_WALINDEX_FIRST_PAGE_FRAMES) + _
            (CULngInt(firstHashPage) - 1ULL) * SQLITE_WALINDEX_HASH_PAGE_FRAMES
    End If
    If CULngInt(pWal->header.maxFrame) < firstFrameZero Then Return SQLITE_CORRUPT
    Dim frameSpan As sqlite3_uint64 = CULngInt(pWal->header.maxFrame) - firstFrameZero
    Dim pageCount As sqlite3_uint64 = CULngInt(pWal->header.pageCount)
    Dim pageMapMode As SQLITE_C_INT = 0
    If pageCount > 0 AndAlso _
       frameSpan * SizeOf(UShort) > pageCount * SizeOf(u32) Then pageMapMode = 1

    Dim segmentCount As SQLITE_C_INT = lastHashPage - firstHashPage + 1
    If pageMapMode <> 0 Then segmentCount = 1
    If segmentCount <= 0 Then Return SQLITE_CORRUPT

    Dim headerBytes As sqlite3_uint64 = walIteratorHeaderBytes()
    Dim segmentBytes As sqlite3_uint64 = _
        CULngInt(segmentCount) * SizeOf(SqliteWalSegment)
    Dim indexBytes As sqlite3_uint64 = 0
    Dim extraBytes As sqlite3_uint64 = 0
    If pageMapMode <> 0 Then
        extraBytes = pageCount * SizeOf(u32)
    Else
        indexBytes = frameSpan * SizeOf(UShort)
        Dim temporarySlots As sqlite3_uint64 = CULngInt(pWal->header.maxFrame)
        If temporarySlots > SQLITE_WALINDEX_HASH_PAGE_FRAMES Then _
            temporarySlots = SQLITE_WALINDEX_HASH_PAGE_FRAMES
        extraBytes = temporarySlots * SizeOf(UShort)
    End If

    If headerBytes > SQLITE_MAX_ALLOCATION_SIZE OrElse _
       segmentBytes > SQLITE_MAX_ALLOCATION_SIZE - headerBytes Then Return SQLITE_NOMEM
    Dim objectBytes As sqlite3_uint64 = headerBytes + segmentBytes
    If indexBytes > SQLITE_MAX_ALLOCATION_SIZE - objectBytes Then Return SQLITE_NOMEM
    objectBytes += indexBytes
    If extraBytes > SQLITE_MAX_ALLOCATION_SIZE - objectBytes Then Return SQLITE_NOMEM
    Dim allocationBytes As sqlite3_uint64 = objectBytes + extraBytes

    Dim pMemory As Any Ptr = sqlite3MallocZero(allocationBytes)
    If pMemory = 0 Then Return SQLITE_NOMEM
    Dim pIterator As SqliteWalIterator Ptr = CPtr(SqliteWalIterator Ptr, pMemory)
    Dim pSegments As SqliteWalSegment Ptr = CPtr(SqliteWalSegment Ptr, _
        CPtr(UByte Ptr, pMemory) + headerBytes)
    pIterator->nSegment = segmentCount

    If pageMapMode <> 0 Then
        pIterator->nPagemap = CUInt(pageCount)
        ' aPgno[0] aliases iZero; aPgno[1..nPagemap] follows the segment.
        pSegments[0].aPgno = @pSegments[0].iZero
    End If

    Dim pTemporary As UShort Ptr = 0
    If pageMapMode = 0 AndAlso extraBytes <> 0 Then
        pTemporary = CPtr(UShort Ptr, CPtr(UByte Ptr, pMemory) + objectBytes)
    End If

    Dim rc As SQLITE_C_INT = SQLITE_OK
    For hashPage As SQLITE_C_INT = firstHashPage To lastHashPage
        Dim location As SqliteWalHashLocation
        rc = walHashGet(pWal, hashPage, @location)
        If rc <> SQLITE_OK Then Exit For
        If location.aPgno = 0 Then
            rc = SQLITE_CORRUPT
            Exit For
        End If

        Dim entryCount As SQLITE_C_INT
        If hashPage = lastHashPage Then
            If CULngInt(pWal->header.maxFrame) < CULngInt(location.iZero) Then
                rc = SQLITE_CORRUPT
                Exit For
            End If
            entryCount = CInt(pWal->header.maxFrame - location.iZero)
        ElseIf hashPage = 0 Then
            entryCount = SQLITE_WALINDEX_FIRST_PAGE_FRAMES
        Else
            entryCount = SQLITE_WALINDEX_HASH_PAGE_FRAMES
        End If
        If entryCount <= 0 OrElse entryCount > SQLITE_WALINDEX_HASH_PAGE_FRAMES Then
            rc = SQLITE_CORRUPT
            Exit For
        End If

        If pageMapMode <> 0 Then
            For entryIndex As SQLITE_C_INT = 0 To entryCount - 1
                Dim pageNumber As u32 = location.aPgno[entryIndex]
                If pageNumber > 0 AndAlso pageNumber <= pIterator->nPagemap Then
                    Dim frameNumber As sqlite3_uint64 = _
                        CULngInt(location.iZero) + CULngInt(entryIndex) + 1ULL
                    If frameNumber > &HFFFFFFFFULL Then
                        rc = SQLITE_CORRUPT
                        Exit For
                    End If
                    pSegments[0].aPgno[pageNumber] = CUInt(frameNumber)
                End If
            Next
            If rc <> SQLITE_OK Then Exit For
        Else
            If CULngInt(location.iZero) < firstFrameZero Then
                rc = SQLITE_CORRUPT
                Exit For
            End If
            Dim indexOffset As sqlite3_uint64 = headerBytes + segmentBytes + _
                (CULngInt(location.iZero) - firstFrameZero) * SizeOf(UShort)
            If indexOffset > objectBytes OrElse _
               CULngInt(entryCount) * SizeOf(UShort) > objectBytes - indexOffset Then
                rc = SQLITE_CORRUPT
                Exit For
            End If
            Dim pIndex As UShort Ptr = CPtr(UShort Ptr, _
                CPtr(UByte Ptr, pMemory) + indexOffset)
            For entryIndex As SQLITE_C_INT = 0 To entryCount - 1
                pIndex[entryIndex] = CUShort(entryIndex)
            Next
            Dim firstFrame As sqlite3_uint64 = CULngInt(location.iZero) + 1ULL
            If firstFrame > &HFFFFFFFFULL Then
                rc = SQLITE_CORRUPT
                Exit For
            End If
            Dim sortedCount As SQLITE_C_INT = entryCount
            rc = walMergesort(location.aPgno, pTemporary, pIndex, @sortedCount)
            If rc <> SQLITE_OK Then Exit For

            Dim segmentIndex As SQLITE_C_INT = hashPage - firstHashPage
            pSegments[segmentIndex].iZero = CUInt(firstFrame)
            pSegments[segmentIndex].nEntry = sortedCount
            pSegments[segmentIndex].aIndex = pIndex
            pSegments[segmentIndex].aPgno = location.aPgno
        End If
    Next

    If rc <> SQLITE_OK Then
        sqlite3_free(pMemory)
        Return rc
    End If
    ppIterator[0] = pIterator
    Return SQLITE_OK
End Function

Private Function walIteratorNext CDecl Alias "walIteratorNext" ( _
    ByVal pIterator As SqliteWalIterator Ptr, _
    ByVal pPageNumber As u32 Ptr, _
    ByVal pFrameNumber As u32 Ptr _
) As SQLITE_C_INT
    If pIterator = 0 OrElse pPageNumber = 0 OrElse pFrameNumber = 0 Then _
        Return SQLITE_MISUSE
    Dim nextPage As u32 = &HFFFFFFFFUL

    If pIterator->nPagemap <> 0 Then
        Dim pPageMap As u32 Ptr = pIterator->aSegment(0).aPgno
        If pPageMap = 0 Then Return SQLITE_CORRUPT
        While pIterator->iPrior < pIterator->nPagemap
            pIterator->iPrior += 1
            If pPageMap[pIterator->iPrior] <> 0 Then
                nextPage = pIterator->iPrior
                pFrameNumber[0] = pPageMap[pIterator->iPrior]
                Exit While
            End If
        Wend
    Else
        Dim minimumPage As u32 = pIterator->iPrior
        Dim pSegments As SqliteWalSegment Ptr = @pIterator->aSegment(0)
        For segmentIndex As SQLITE_C_INT = pIterator->nSegment - 1 To 0 Step -1
            Dim pSegment As SqliteWalSegment Ptr = @pSegments[segmentIndex]
            While pSegment->iNext < pSegment->nEntry
                Dim slot As UShort = pSegment->aIndex[pSegment->iNext]
                Dim pageNumber As u32 = pSegment->aPgno[slot]
                If pageNumber > minimumPage Then
                    If pageNumber < nextPage Then
                        nextPage = pageNumber
                        pFrameNumber[0] = pSegment->iZero + slot
                    End If
                    Exit While
                End If
                pSegment->iNext += 1
            Wend
        Next
    End If

    pPageNumber[0] = nextPage
    pIterator->iPrior = nextPage
    Return IIf(nextPage = &HFFFFFFFFUL, 1, 0)
End Function

Private Sub walClearIndexHeader(ByVal pWal As SqliteWal Ptr)
    If pWal = 0 Then Exit Sub
    pWal->header.version = 0
    pWal->header.unused = 0
    pWal->header.changeCounter = 0
    pWal->header.isInitialized = 0
    pWal->header.bigEndianChecksum = 0
    pWal->header.pageSize = 0
    pWal->header.maxFrame = 0
    pWal->header.pageCount = 0
    pWal->header.frameChecksum(0) = 0
    pWal->header.frameChecksum(1) = 0
    pWal->header.salt(0) = 0
    pWal->header.salt(1) = 0
    pWal->header.checksum(0) = 0
    pWal->header.checksum(1) = 0
End Sub


' ---------------------------------------------------------------------------
' WAL-index recovery
' ---------------------------------------------------------------------------

Private Const SQLITE_WAL_MIN_PAGE_SIZE As SQLITE_C_INT = 512

Private Function walFrameOffset( _
    ByVal frameIndex As u32, _
    ByVal pageSize As u32 _
) As sqlite3_int64
    If frameIndex = 0 Then Return 0
    Dim frameSize As sqlite3_uint64 = _
        CULngInt(pageSize) + SQLITE_WAL_FRAME_HEADER_SIZE
    Dim offset As sqlite3_uint64 = SQLITE_WAL_HEADER_SIZE + _
        (CULngInt(frameIndex) - 1ULL) * frameSize
    Return CLngInt(offset)
End Function

Private Function walIndexRecover CDecl Alias "walIndexRecover" ( _
    ByVal pWal As SqliteWal Ptr _
) As SQLITE_C_INT
    If pWal = 0 OrElse pWal->writeLock = 0 OrElse pWal->checkpointLock > 1 Then _
        Return SQLITE_MISUSE

    Dim lockIndex As SQLITE_C_INT = WAL_ALL_BUT_WRITE + pWal->checkpointLock
    Dim lockCount As SQLITE_C_INT = WAL_READ_LOCK_BASE - lockIndex
    If lockCount <= 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = walLockExclusive(pWal, lockIndex, lockCount)
    If rc <> SQLITE_OK Then Return rc

    Dim fileSize As sqlite3_int64 = 0
    Dim frameBuffer As UByte Ptr = 0
    Dim privateIndexPage As u32 Ptr = 0
    Dim pageSize As SQLITE_C_INT = 0
    Dim frameSize As SQLITE_C_INT = 0
    Dim lastFrame As u32 = 0
    Dim committedChecksum(0 To 1) As u32
    committedChecksum(0) = 0
    committedChecksum(1) = 0

    ' A failed or empty log starts recovery from an empty cached header.
    pWal->header.version = 0
    pWal->header.unused = 0
    pWal->header.changeCounter = 0
    pWal->header.isInitialized = 0
    pWal->header.bigEndianChecksum = 0
    pWal->header.pageSize = 0
    pWal->header.maxFrame = 0
    pWal->header.pageCount = 0
    pWal->header.frameChecksum(0) = 0
    pWal->header.frameChecksum(1) = 0
    pWal->header.salt(0) = 0
    pWal->header.salt(1) = 0
    pWal->header.checksum(0) = 0
    pWal->header.checksum(1) = 0
    pWal->pageSize = 0

    rc = sqlite3OsFileSize(pWal->pWalFile, @fileSize)
    If rc <> SQLITE_OK Then GoTo recovery_cleanup

    If fileSize > SQLITE_WAL_HEADER_SIZE Then
        Dim walHeader(0 To SQLITE_WAL_HEADER_SIZE - 1) As UByte
        rc = sqlite3OsRead(pWal->pWalFile, @walHeader(0), _
                           SQLITE_WAL_HEADER_SIZE, 0)
        If rc <> SQLITE_OK Then GoTo recovery_cleanup

        Dim magic As u32 = sqlite3Get4byte(@walHeader(0))
        pageSize = CInt(sqlite3Get4byte(@walHeader(8)))
        If (magic And &HFFFFFFFE) <> SQLITE_WAL_MAGIC OrElse _
           pageSize < SQLITE_WAL_MIN_PAGE_SIZE OrElse _
           pageSize > SQLITE_MAX_PAGE_SIZE OrElse _
           (pageSize And (pageSize - 1)) <> 0 Then
            rc = SQLITE_OK
            GoTo recovery_finish
        End If

        pWal->header.bigEndianChecksum = CByte(magic And 1)
        pWal->pageSize = CUInt(pageSize)
        pWal->checkpointSequence = sqlite3Get4byte(@walHeader(12))
        walSystemMemcpy(@pWal->header.salt(0), @walHeader(16), 8)

        Dim nativeChecksum As SQLITE_C_INT = _
            IIf(pWal->header.bigEndianChecksum = walHostIsBigEndian(), 1, 0)
        walChecksumBytes(nativeChecksum, @walHeader(0), _
            SQLITE_WAL_HEADER_SIZE - 8, 0, @pWal->header.frameChecksum(0))
        If pWal->header.frameChecksum(0) <> sqlite3Get4byte(@walHeader(24)) OrElse _
           pWal->header.frameChecksum(1) <> sqlite3Get4byte(@walHeader(28)) Then
            rc = SQLITE_OK
            GoTo recovery_finish
        End If

        Dim version As u32 = sqlite3Get4byte(@walHeader(4))
        If version <> SQLITE_WALINDEX_MAX_VERSION Then
            rc = SQLITE_CANTOPEN
            GoTo recovery_cleanup
        End If

        frameSize = pageSize + SQLITE_WAL_FRAME_HEADER_SIZE
        Dim allocationSize As sqlite3_uint64 = _
            CULngInt(frameSize) + SQLITE_WALINDEX_PAGE_SIZE
        If allocationSize > SQLITE_MAX_ALLOCATION_SIZE Then
            rc = SQLITE_NOMEM
            GoTo recovery_cleanup
        End If
        frameBuffer = CPtr(UByte Ptr, sqlite3_malloc64(allocationSize))
        If frameBuffer = 0 Then
            rc = SQLITE_NOMEM
            GoTo recovery_cleanup
        End If

        Dim pData As UByte Ptr = frameBuffer + SQLITE_WAL_FRAME_HEADER_SIZE
        privateIndexPage = CPtr(u32 Ptr, pData + pageSize)
        Dim lastFrame64 As sqlite3_uint64 = _
            CULngInt(fileSize - SQLITE_WAL_HEADER_SIZE) \ CULngInt(frameSize)
        If lastFrame64 > &HFFFFFFFFULL Then
            rc = SQLITE_CORRUPT
            GoTo recovery_cleanup
        End If
        lastFrame = CUInt(lastFrame64)

        Dim lastHashPage As SQLITE_C_INT = walFramePage(lastFrame)
        If lastHashPage < 0 Then
            rc = SQLITE_CORRUPT
            GoTo recovery_cleanup
        End If

        For pageIndex As SQLITE_C_INT = 0 To lastHashPage
            Dim pSharedPage As u32 Ptr = 0
            rc = walIndexPage(pWal, pageIndex, @pSharedPage)
            If pSharedPage = 0 Then
                If rc = SQLITE_OK Then rc = SQLITE_IOERR_SHMMAP
                Exit For
            End If

            ' Recovery builds each index page privately, then publishes it
            ' while the writer and recovery locks exclude competing writers.
            Dim pageWordCount As SQLITE_C_INT = _
                SQLITE_WALINDEX_PAGE_SIZE \ SizeOf(u32)
            For wordIndex As SQLITE_C_INT = 0 To pageWordCount - 1
                privateIndexPage[wordIndex] = 0
            Next
            pWal->walIndexData[pageIndex] = privateIndexPage

            Dim firstFrame As sqlite3_uint64 = 1
            If pageIndex > 0 Then
                firstFrame += SQLITE_WALINDEX_FIRST_PAGE_FRAMES
                firstFrame += (CULngInt(pageIndex) - 1ULL) * _
                              SQLITE_WALINDEX_HASH_PAGE_FRAMES
            End If
            Dim lastFrameInPage As sqlite3_uint64 = _
                CULngInt(SQLITE_WALINDEX_FIRST_PAGE_FRAMES) + _
                CULngInt(pageIndex) * SQLITE_WALINDEX_HASH_PAGE_FRAMES
            If lastFrameInPage > lastFrame Then lastFrameInPage = lastFrame

            Dim frameIndex As sqlite3_uint64 = firstFrame
            While frameIndex <= lastFrameInPage
                Dim fileOffset As sqlite3_int64 = _
                    walFrameOffset(CUInt(frameIndex), CUInt(pageSize))
                rc = sqlite3OsRead(pWal->pWalFile, frameBuffer, frameSize, fileOffset)
                If rc <> SQLITE_OK Then Exit While

                Dim pageNumber As u32 = 0
                Dim truncatePages As u32 = 0
                If walDecodeFrame(pWal, @pageNumber, @truncatePages, _
                                  pData, frameBuffer) = 0 Then Exit While
                rc = walIndexAppend(pWal, CUInt(frameIndex), pageNumber)
                If rc <> SQLITE_OK Then Exit While

                If truncatePages <> 0 Then
                    pWal->header.maxFrame = CUInt(frameIndex)
                    pWal->header.pageCount = truncatePages
                    pWal->header.pageSize = CUShort( _
                        (pageSize And &HFF00) Or (pageSize Shr 16))
                    committedChecksum(0) = pWal->header.frameChecksum(0)
                    committedChecksum(1) = pWal->header.frameChecksum(1)
                End If
                frameIndex += 1
            Wend

            pWal->walIndexData[pageIndex] = pSharedPage
            Dim headerBytes As SQLITE_C_INT = 0
            If pageIndex = 0 Then headerBytes = SQLITE_WALINDEX_HEADER_SIZE
            Dim headerWords As SQLITE_C_INT = headerBytes \ SizeOf(u32)
#ifndef SQLITE_SAFER_WALINDEX_RECOVERY
            walSystemMemcpy(pSharedPage + headerWords, _
                privateIndexPage + headerWords, _
                SQLITE_WALINDEX_PAGE_SIZE - headerBytes)
#else
            For wordIndex As SQLITE_C_INT = headerWords To pageWordCount - 1
                If pSharedPage[wordIndex] <> privateIndexPage[wordIndex] Then _
                    pSharedPage[wordIndex] = privateIndexPage[wordIndex]
            Next
#endif
            If rc <> SQLITE_OK OrElse frameIndex <= lastFrameInPage Then Exit For
        Next
        sqlite3_free(frameBuffer)
        frameBuffer = 0
        If rc <> SQLITE_OK Then GoTo recovery_cleanup

        pWal->header.frameChecksum(0) = committedChecksum(0)
        pWal->header.frameChecksum(1) = committedChecksum(1)
    End If

recovery_finish:
    If rc = SQLITE_OK Then
        walIndexWriteHdr(pWal)
        Dim pInfo As SqliteWalCheckpointInfo Ptr = walCkptInfo(pWal)
        If pInfo = 0 Then
            rc = SQLITE_CORRUPT
            GoTo recovery_cleanup
        End If

        pInfo->nBackfill = 0
        pInfo->nBackfillAttempted = pWal->header.maxFrame
        pInfo->readMark(0) = 0
        For readIndex As SQLITE_C_INT = 1 To WAL_NREADER - 1
            rc = walLockExclusive(pWal, WAL_READ_LOCK_BASE + readIndex, 1)
            If rc = SQLITE_OK Then
                If readIndex = 1 AndAlso pWal->header.maxFrame <> 0 Then
                    pInfo->readMark(readIndex) = pWal->header.maxFrame
                Else
                    pInfo->readMark(readIndex) = READMARK_NOT_USED
                End If
                walUnlockExclusive(pWal, WAL_READ_LOCK_BASE + readIndex, 1)
            ElseIf rc <> SQLITE_BUSY Then
                GoTo recovery_cleanup
            End If
        Next
        If rc = SQLITE_OK AndAlso pWal->header.pageCount <> 0 Then
            sqlite3_log(SQLITE_NOTICE_RECOVER_WAL, _
                StrPtr(!"recovered %d frames from WAL file %s"), _
                pWal->header.maxFrame, pWal->walName)
        End If
    End If

recovery_cleanup:
    If frameBuffer <> 0 Then sqlite3_free(frameBuffer)
    walUnlockExclusive(pWal, lockIndex, lockCount)
    Return rc
End Function


' ---------------------------------------------------------------------------
' WAL read transactions
' ---------------------------------------------------------------------------

Function sqlite3WalEndWriteTransaction CDecl Alias "sqlite3WalEndWriteTransaction" ( _
    ByVal pWalArgument As Any Ptr _
) As SQLITE_C_INT
    If pWalArgument = 0 Then Return SQLITE_MISUSE
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)

    If pWal->writeLock <> 0 Then
        walUnlockExclusive(pWal, WAL_WRITE_LOCK, 1)
        pWal->writeLock = 0
        pWal->recalculateChecksumFrame = 0
        pWal->truncateOnCommit = 0
    End If
    Return SQLITE_OK
End Function

Sub sqlite3WalEndReadTransaction CDecl Alias "sqlite3WalEndReadTransaction" ( _
    ByVal pWalArgument As Any Ptr _
)
    If pWalArgument = 0 Then Exit Sub
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)

    If pWal->readLock >= 0 Then
        sqlite3WalEndWriteTransaction(pWalArgument)
        walUnlockShared(pWal, WAL_READ_LOCK_BASE + pWal->readLock)
        pWal->readLock = -1
    End If
End Sub

Private Function walIndexReadHdr CDecl Alias "walIndexReadHdr" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal pChanged As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pWal = 0 OrElse pChanged = 0 Then Return SQLITE_MISUSE

    Dim pageZero As u32 Ptr = 0
    Dim rc As SQLITE_C_INT = walIndexPage(pWal, 0, @pageZero)
    If rc <> SQLITE_OK Then
        If rc <> SQLITE_READONLY_CANTINIT Then Return rc
        If pWal->writeLock <> 0 OrElse (pWal->readOnly And WAL_SHM_RDONLY) = 0 Then _
            Return SQLITE_CORRUPT

        ' A read-only shared-memory mapping may be stale when no writer is
        ' available to repair it. Build a private index and validate it below.
        pWal->sharedMemoryUnreliable = 1
        pWal->exclusiveMode = WAL_HEAPMEMORY_MODE
        pChanged[0] = 1
    End If

    Dim badHeader As SQLITE_C_INT = 1
    If pageZero <> 0 Then badHeader = walIndexTryHdr(pWal, pChanged)

    If badHeader <> 0 Then
        If pWal->sharedMemoryUnreliable = 0 AndAlso _
           (pWal->readOnly And WAL_SHM_RDONLY) <> 0 Then
            rc = walLockShared(pWal, WAL_WRITE_LOCK)
            If rc = SQLITE_OK Then
                walUnlockShared(pWal, WAL_WRITE_LOCK)
                rc = SQLITE_READONLY_RECOVERY
            End If
        Else
            Dim alreadyWriteLocked As SQLITE_C_INT = IIf(pWal->writeLock <> 0, 1, 0)
            If alreadyWriteLocked <> 0 Then
                rc = SQLITE_OK
            Else
                rc = walLockExclusive(pWal, WAL_WRITE_LOCK, 1)
            End If

            If rc = SQLITE_OK Then
                If alreadyWriteLocked = 0 Then pWal->writeLock = 2
                rc = walIndexPage(pWal, 0, @pageZero)
                If rc = SQLITE_OK Then
                    badHeader = walIndexTryHdr(pWal, pChanged)
                    If badHeader <> 0 Then
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
                        walDisableBlocking(pWal)
#endif
                        rc = walIndexRecover(pWal)
                        pChanged[0] = 1
                    End If
                End If

                If alreadyWriteLocked = 0 Then
                    pWal->writeLock = 0
                    walUnlockExclusive(pWal, WAL_WRITE_LOCK, 1)
                End If
            End If
        End If
    End If

    If badHeader = 0 AndAlso pWal->header.version <> SQLITE_WALINDEX_MAX_VERSION Then
        rc = SQLITE_CANTOPEN
    End If

    If pWal->sharedMemoryUnreliable <> 0 Then
        If rc <> SQLITE_OK Then
            walIndexClose(pWal, 0)
            pWal->sharedMemoryUnreliable = 0
            If rc = SQLITE_IOERR_SHORT_READ Then rc = WAL_RETRY
        End If
        pWal->exclusiveMode = WAL_NORMAL_MODE
    End If
    Return rc
End Function

Private Function walBeginShmUnreliable CDecl Alias "walBeginShmUnreliable" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal pChanged As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim pMappedPage As Any Ptr = 0
    Dim pPrivateHeader As SqliteWalIndexHeader Ptr = 0
    Dim fileSize As sqlite3_int64 = 0
    Dim walHeader(0 To SQLITE_WAL_HEADER_SIZE - 1) As UByte
    Dim frameSize As SQLITE_C_INT = 0
    Dim pFrame As UByte Ptr = 0
    Dim pData As UByte Ptr = 0
    Dim savedChecksum(0 To 1) As u32
    Dim frameIndex As u32 = 0
    Dim fileOffset As sqlite3_int64 = 0
    Dim pageNumber As u32 = 0
    Dim truncatePages As u32 = 0
    Dim pageIndex As SQLITE_C_INT

    If pWal = 0 OrElse pChanged = 0 OrElse _
       pWal->sharedMemoryUnreliable = 0 OrElse _
       (pWal->readOnly And WAL_SHM_RDONLY) = 0 OrElse _
       pWal->walIndexDataCount <= 0 OrElse pWal->walIndexData = 0 OrElse _
       pWal->walIndexData[0] = 0 Then Return SQLITE_MISUSE

    rc = walLockShared(pWal, WAL_READ_LOCK_BASE)
    If rc <> SQLITE_OK Then
        If rc = SQLITE_BUSY Then rc = WAL_RETRY
        GoTo unreliable_cleanup
    End If
    pWal->readLock = 0

    ' Re-check the VFS mapping while READ_LOCK(0) prevents checkpointing.
    ' A writable mapping means a writer can keep the shared index current.
    rc = sqlite3OsShmMap(pWal->pDbFile, 0, SQLITE_WALINDEX_PAGE_SIZE, 0, @pMappedPage)
    If rc = SQLITE_READONLY Then
        rc = WAL_RETRY
        GoTo unreliable_cleanup
    End If
    If rc <> SQLITE_READONLY_CANTINIT Then GoTo unreliable_cleanup

    pPrivateHeader = walIndexHdr(pWal)
    If pPrivateHeader = 0 Then
        rc = SQLITE_CORRUPT
        GoTo unreliable_cleanup
    End If
    pWal->header = pPrivateHeader[0]

    rc = sqlite3OsFileSize(pWal->pWalFile, @fileSize)
    If rc <> SQLITE_OK Then GoTo unreliable_cleanup
    If fileSize < SQLITE_WAL_HEADER_SIZE Then
        pChanged[0] = 1
        rc = IIf(pWal->header.maxFrame = 0, SQLITE_OK, WAL_RETRY)
        GoTo unreliable_cleanup
    End If

    rc = sqlite3OsRead(pWal->pWalFile, @walHeader(0), SQLITE_WAL_HEADER_SIZE, 0)
    If rc <> SQLITE_OK Then GoTo unreliable_cleanup
    If walSystemMemcmp(@pWal->header.salt(0), @walHeader(16), 8) <> 0 Then
        rc = WAL_RETRY
        GoTo unreliable_cleanup
    End If

    If pWal->pageSize > &HFFFFFFFFULL - SQLITE_WAL_FRAME_HEADER_SIZE Then
        rc = SQLITE_CORRUPT
        GoTo unreliable_cleanup
    End If
    frameSize = CInt(pWal->pageSize + SQLITE_WAL_FRAME_HEADER_SIZE)
    pFrame = CPtr(UByte Ptr, sqlite3_malloc64(CULngInt(frameSize)))
    If pFrame = 0 Then
        rc = SQLITE_NOMEM
        GoTo unreliable_cleanup
    End If

    pData = pFrame + SQLITE_WAL_FRAME_HEADER_SIZE
    savedChecksum(0) = pWal->header.frameChecksum(0)
    savedChecksum(1) = pWal->header.frameChecksum(1)
    If pWal->header.maxFrame = &HFFFFFFFFUL Then
        rc = SQLITE_CORRUPT
        GoTo unreliable_frame_cleanup
    End If

    frameIndex = pWal->header.maxFrame + 1
    fileOffset = walFrameOffset(frameIndex, pWal->pageSize)
    While fileOffset <= fileSize - frameSize
        rc = sqlite3OsRead(pWal->pWalFile, pFrame, frameSize, fileOffset)
        If rc <> SQLITE_OK Then Exit While

        pageNumber = 0
        truncatePages = 0
        If walDecodeFrame(pWal, @pageNumber, @truncatePages, pData, pFrame) = 0 Then Exit While
        If truncatePages <> 0 Then
            rc = WAL_RETRY
            Exit While
        End If

        If frameIndex = &HFFFFFFFFUL Then
            rc = SQLITE_CORRUPT
            Exit While
        End If
        frameIndex += 1
        fileOffset += frameSize
    Wend
    pWal->header.frameChecksum(0) = savedChecksum(0)
    pWal->header.frameChecksum(1) = savedChecksum(1)

unreliable_frame_cleanup:
    sqlite3_free(pFrame)

unreliable_cleanup:
    If rc <> SQLITE_OK Then
        If pWal->walIndexData <> 0 Then
            For pageIndex = 0 To pWal->walIndexDataCount - 1
                If pWal->walIndexData[pageIndex] <> 0 Then
                    sqlite3_free(pWal->walIndexData[pageIndex])
                    pWal->walIndexData[pageIndex] = 0
                End If
            Next
        End If
        pWal->sharedMemoryUnreliable = 0
        sqlite3WalEndReadTransaction(pWal)
        pChanged[0] = 1
    End If
    Return rc
End Function

Private Function walTryBeginRead CDecl Alias "walTryBeginRead" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal pChanged As SQLITE_C_INT Ptr, _
    ByVal useWal As SQLITE_C_INT, _
    ByVal pRetryCount As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pWal = 0 OrElse pRetryCount = 0 OrElse _
       (useWal = 0 AndAlso pChanged = 0) Then Return SQLITE_MISUSE
    If pWal->readLock >= 0 OrElse useWal < 0 OrElse useWal > 1 Then Return SQLITE_MISUSE
    If (pWal->readOnly And WAL_SHM_RDONLY) <> 0 AndAlso useWal <> 0 Then Return SQLITE_MISUSE

    Dim rc As SQLITE_C_INT = SQLITE_OK
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    Dim blockMilliseconds As SQLITE_C_INT = 0
#endif
    pRetryCount[0] += 1
    If pRetryCount[0] > 5 Then
        Dim delayMicroseconds As SQLITE_C_INT = 1
        Dim retryNumber As SQLITE_C_INT = pRetryCount[0] And Not WAL_RETRY_BLOCKED_MASK
        If retryNumber > WAL_RETRY_PROTOCOL_LIMIT Then Return SQLITE_PROTOCOL
        If retryNumber >= 10 Then
            Dim delayStep As SQLITE_C_INT = retryNumber - 9
            delayMicroseconds = delayStep * delayStep * 39
        End If
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
        blockMilliseconds = (delayMicroseconds + 998) \ 1000
        If useWal = 0 AndAlso walEnableBlockingMs(pWal, blockMilliseconds) <> 0 Then
            If (pRetryCount[0] And WAL_RETRY_BLOCKED_MASK) <> 0 Then _
                delayMicroseconds = 1
        End If
#endif
        sqlite3OsSleep(pWal->pVfs, delayMicroseconds)
        pRetryCount[0] = pRetryCount[0] And Not WAL_RETRY_BLOCKED_MASK
    End If

    If useWal = 0 Then
        If pWal->sharedMemoryUnreliable = 0 Then rc = walIndexReadHdr(pWal, pChanged)
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
        If rc = SQLITE_BUSY_TIMEOUT Then
            rc = SQLITE_BUSY
            pRetryCount[0] = pRetryCount[0] Or WAL_RETRY_BLOCKED_MASK
        End If
#endif
        If rc = SQLITE_BUSY Then
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
            walEnableBlocking(pWal)
#endif
            If pWal->walIndexData = 0 OrElse pWal->walIndexDataCount = 0 OrElse _
               pWal->walIndexData[0] = 0 Then
                rc = WAL_RETRY
            Else
                rc = walLockShared(pWal, WAL_RECOVER_LOCK)
                If rc = SQLITE_OK Then
                    walUnlockShared(pWal, WAL_RECOVER_LOCK)
                    rc = WAL_RETRY
                ElseIf rc = SQLITE_BUSY Then
                    rc = SQLITE_BUSY_RECOVERY
                End If
            End If
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
            walDisableBlocking(pWal)
#endif
        End If
        If rc <> SQLITE_OK Then Return rc
        If pWal->sharedMemoryUnreliable <> 0 Then Return walBeginShmUnreliable(pWal, pChanged)
    End If

    If pWal->walIndexDataCount <= 0 OrElse pWal->walIndexData = 0 OrElse _
       pWal->walIndexData[0] = 0 Then Return SQLITE_CORRUPT
    Dim pInfo As SqliteWalCheckpointInfo Ptr = walCkptInfo(pWal)
    If pInfo = 0 Then Return SQLITE_CORRUPT

    Dim mayIgnoreWal As SQLITE_C_INT = CInt( _
        useWal = 0 AndAlso pInfo->nBackfill = pWal->header.maxFrame)
#ifdef SQLITE_ENABLE_SNAPSHOT
    mayIgnoreWal = CInt(mayIgnoreWal <> 0 AndAlso _
        ((pWal->getSnapshot = 0 AndAlso pWal->pSnapshot = 0) OrElse _
         pWal->header.maxFrame = 0))
#endif
    If mayIgnoreWal <> 0 Then
        rc = walLockShared(pWal, WAL_READ_LOCK_BASE)
        walShmBarrier(pWal)
        If rc = SQLITE_OK Then
            Dim pSharedHeader As SqliteWalIndexHeader Ptr = walIndexHdr(pWal)
            If pSharedHeader = 0 OrElse _
               walSystemMemcmp(pSharedHeader, @pWal->header, SizeOf(pWal->header)) <> 0 Then
                walUnlockShared(pWal, WAL_READ_LOCK_BASE)
                Return WAL_RETRY
            End If
            pWal->readLock = 0
            Return SQLITE_OK
        ElseIf rc <> SQLITE_BUSY Then
            Return rc
        End If
    End If

    Dim maximumReadMark As u32 = 0
    Dim selectedReadLock As SQLITE_C_INT = 0
    Dim maximumFrame As u32 = pWal->header.maxFrame
#ifdef SQLITE_ENABLE_SNAPSHOT
    If pWal->pSnapshot <> 0 AndAlso pWal->pSnapshot->maxFrame < maximumFrame Then _
        maximumFrame = pWal->pSnapshot->maxFrame
#endif
    For readIndex As SQLITE_C_INT = 1 To WAL_NREADER - 1
        Dim thisReadMark As u32 = pInfo->readMark(readIndex)
        If maximumReadMark <= thisReadMark AndAlso thisReadMark <= maximumFrame Then
            maximumReadMark = thisReadMark
            selectedReadLock = readIndex
        End If
    Next

    If (pWal->readOnly And WAL_SHM_RDONLY) = 0 AndAlso _
       (maximumReadMark < maximumFrame OrElse selectedReadLock = 0) Then
        For readIndex As SQLITE_C_INT = 1 To WAL_NREADER - 1
            rc = walLockExclusive(pWal, WAL_READ_LOCK_BASE + readIndex, 1)
            If rc = SQLITE_OK Then
                pInfo->readMark(readIndex) = maximumFrame
                walShmBarrier(pWal)
                maximumReadMark = maximumFrame
                selectedReadLock = readIndex
                walUnlockExclusive(pWal, WAL_READ_LOCK_BASE + readIndex, 1)
                Exit For
            ElseIf rc <> SQLITE_BUSY Then
                Return rc
            End If
        Next
    End If

    If selectedReadLock = 0 Then
        If rc = SQLITE_BUSY Then Return WAL_RETRY
        Return SQLITE_READONLY_CANTINIT
    End If

#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    walEnableBlockingMs(pWal, blockMilliseconds)
#endif
    rc = walLockShared(pWal, WAL_READ_LOCK_BASE + selectedReadLock)
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    walDisableBlocking(pWal)
    If rc = SQLITE_BUSY_TIMEOUT Then
        pRetryCount[0] = pRetryCount[0] Or WAL_RETRY_BLOCKED_MASK
        rc = SQLITE_BUSY
    End If
#endif
    If rc <> SQLITE_OK Then
        If rc = SQLITE_BUSY Then Return WAL_RETRY
        Return rc
    End If

    pWal->minFrame = pInfo->nBackfill + 1
    walShmBarrier(pWal)
    Dim pSharedHeader As SqliteWalIndexHeader Ptr = walIndexHdr(pWal)
    If pSharedHeader = 0 OrElse _
       pInfo->readMark(selectedReadLock) <> maximumReadMark OrElse _
       walSystemMemcmp(pSharedHeader, @pWal->header, SizeOf(pWal->header)) <> 0 Then
        walUnlockShared(pWal, WAL_READ_LOCK_BASE + selectedReadLock)
        Return WAL_RETRY
    End If

    pWal->readLock = CShort(selectedReadLock)
    Return SQLITE_OK
End Function

Private Function walBeginReadTransaction CDecl Alias "walBeginReadTransaction" ( _
    ByVal pWal As Any Ptr, _
    ByVal pChanged As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pWal = 0 OrElse pChanged = 0 Then Return SQLITE_MISUSE
    Dim pWalState As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWal)
    Dim retryCount As SQLITE_C_INT = 0
    Dim rc As SQLITE_C_INT
#ifdef SQLITE_ENABLE_SNAPSHOT
    Dim checkpointLock As SQLITE_C_INT = 0
    Dim snapshotChanged As SQLITE_C_INT = 0
    Dim pSnapshot As SqliteWalIndexHeader Ptr = pWalState->pSnapshot
    If pSnapshot <> 0 Then
        If walSystemMemcmp(pSnapshot, @pWalState->header, _
                           SizeOf(pWalState->header)) <> 0 Then _
            snapshotChanged = 1
        rc = walLockShared(pWalState, WAL_CKPT_LOCK)
        If rc <> SQLITE_OK Then Return rc
        checkpointLock = 1
    End If
#endif
    Do
        rc = walTryBeginRead(pWalState, pChanged, 0, @retryCount)
    Loop While rc = WAL_RETRY
#ifdef SQLITE_ENABLE_SNAPSHOT
    If rc = SQLITE_OK AndAlso pSnapshot <> 0 AndAlso _
       walSystemMemcmp(pSnapshot, @pWalState->header, _
                       SizeOf(pWalState->header)) <> 0 Then
        Dim pInfo As SqliteWalCheckpointInfo Ptr = walCkptInfo(pWalState)
        If pInfo = 0 OrElse pWalState->readLock < 0 OrElse _
           pWalState->readLock >= WAL_NREADER Then
            rc = SQLITE_CORRUPT
        ElseIf walSystemMemcmp(@pSnapshot->salt(0), _
                              @pWalState->header.salt(0), _
                              2 * SizeOf(u32)) = 0 AndAlso _
               pSnapshot->maxFrame >= pInfo->nBackfillAttempted AndAlso _
               pInfo->readMark(pWalState->readLock) <= pSnapshot->maxFrame Then
            walSystemMemcpy(@pWalState->header, pSnapshot, _
                            SizeOf(pWalState->header))
            pChanged[0] = snapshotChanged
        Else
            rc = SQLITE_ERROR_SNAPSHOT
        End If

        ' Older snapshots may need frames before the current backfill boundary.
        pWalState->minFrame = 1
        If rc <> SQLITE_OK Then sqlite3WalEndReadTransaction(pWal)
    End If
    If checkpointLock <> 0 Then walUnlockShared(pWalState, WAL_CKPT_LOCK)
#endif
    Return rc
End Function

Function sqlite3WalBeginReadTransaction CDecl Alias "sqlite3WalBeginReadTransaction" ( _
    ByVal pWal As Any Ptr, _
    ByVal pChanged As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    Return walBeginReadTransaction(pWal, pChanged)
End Function

' ---------------------------------------------------------------------------
' WAL write transactions
' ---------------------------------------------------------------------------

Function sqlite3WalBeginWriteTransaction CDecl Alias "sqlite3WalBeginWriteTransaction" ( _
    ByVal pWalArgument As Any Ptr _
) As SQLITE_C_INT
    If pWalArgument = 0 Then Return SQLITE_MISUSE
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    If pWal->readLock < 0 Then Return SQLITE_MISUSE
    If pWal->readOnly <> 0 Then Return SQLITE_READONLY

    Dim pSharedHeader As SqliteWalIndexHeader Ptr = walIndexHdr(pWal)
    If pSharedHeader = 0 Then Return SQLITE_CORRUPT
    If pWal->writeLock <> 0 Then
        If walSystemMemcmp(@pWal->header, pSharedHeader, SizeOf(pWal->header)) = 0 Then _
            Return SQLITE_OK
        Return SQLITE_BUSY_SNAPSHOT
    End If

    Dim rc As SQLITE_C_INT = walLockExclusive(pWal, WAL_WRITE_LOCK, 1)
    If rc <> SQLITE_OK Then Return rc
    pWal->writeLock = 1

    pSharedHeader = walIndexHdr(pWal)
    If pSharedHeader = 0 Then
        rc = SQLITE_CORRUPT
    ElseIf walSystemMemcmp(@pWal->header, pSharedHeader, SizeOf(pWal->header)) <> 0 Then
        rc = SQLITE_BUSY_SNAPSHOT
    End If

    If rc <> SQLITE_OK Then
        walUnlockExclusive(pWal, WAL_WRITE_LOCK, 1)
        pWal->writeLock = 0
    End If
    Return rc
End Function

Private Function walRestartLog CDecl Alias "walRestartLog" ( _
    ByVal pWal As SqliteWal Ptr _
) As SQLITE_C_INT
    If pWal = 0 OrElse pWal->writeLock = 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = SQLITE_OK

    If pWal->readLock = 0 Then
        Dim pInfo As SqliteWalCheckpointInfo Ptr = walCkptInfo(pWal)
        If pInfo = 0 Then Return SQLITE_CORRUPT
        If pInfo->nBackfill <> pWal->header.maxFrame Then Return SQLITE_CORRUPT

        If pInfo->nBackfill > 0 Then
            Dim salt1 As u32 = 0
            sqlite3_randomness(SizeOf(salt1), @salt1)
            rc = walLockExclusive(pWal, WAL_READ_LOCK_BASE + 1, WAL_NREADER - 1)
            If rc = SQLITE_OK Then
                walRestartHdr(pWal, salt1)
                walUnlockExclusive(pWal, WAL_READ_LOCK_BASE + 1, WAL_NREADER - 1)
            ElseIf rc <> SQLITE_BUSY Then
                Return rc
            End If
        End If

        walUnlockShared(pWal, WAL_READ_LOCK_BASE)
        pWal->readLock = -1
        Dim retryCount As SQLITE_C_INT = 0
        Dim changed As SQLITE_C_INT = 0
        Do
            rc = walTryBeginRead(pWal, @changed, 1, @retryCount)
        Loop While rc = WAL_RETRY
    End If
    Return rc
End Function

' ---------------------------------------------------------------------------
' WAL frame encoding and file writes
' ---------------------------------------------------------------------------

Private Sub walEncodeFrame CDecl Alias "walEncodeFrame" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal pageNumber As u32, _
    ByVal truncatePages As u32, _
    ByVal pData As UByte Ptr, _
    ByVal pFrame As UByte Ptr _
)
    If pWal = 0 OrElse pData = 0 OrElse pFrame = 0 Then Exit Sub

    sqlite3Put4byte(pFrame, pageNumber)
    sqlite3Put4byte(pFrame + 4, truncatePages)
    If pWal->recalculateChecksumFrame = 0 Then
        walSystemMemcpy(pFrame + 8, @pWal->header.salt(0), 8)
        Dim nativeChecksum As SQLITE_C_INT = _
            IIf(pWal->header.bigEndianChecksum = walHostIsBigEndian(), 1, 0)
        walChecksumBytes(nativeChecksum, pFrame, 8, _
            @pWal->header.frameChecksum(0), @pWal->header.frameChecksum(0))
        walChecksumBytes(nativeChecksum, pData, CInt(pWal->pageSize), _
            @pWal->header.frameChecksum(0), @pWal->header.frameChecksum(0))
        sqlite3Put4byte(pFrame + 16, pWal->header.frameChecksum(0))
        sqlite3Put4byte(pFrame + 20, pWal->header.frameChecksum(1))
    Else
        For byteIndex As SQLITE_C_INT = 8 To SQLITE_WAL_FRAME_HEADER_SIZE - 1
            pFrame[byteIndex] = 0
        Next
    End If
End Sub

Private Function walWriteToLog CDecl Alias "walWriteToLog" ( _
    ByVal pWriter As SqliteWalWriter Ptr, _
    ByVal pContent As Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal offset As sqlite3_int64 _
) As SQLITE_C_INT
    If pWriter = 0 OrElse amount < 0 OrElse offset < 0 OrElse _
       (amount > 0 AndAlso pContent = 0) Then Return SQLITE_MISUSE
    If amount = 0 Then Return SQLITE_OK
    If offset > &H7FFFFFFFFFFFFFFFLL - amount Then Return SQLITE_FULL

    Dim pBytes As UByte Ptr = CPtr(UByte Ptr, pContent)
    If offset < pWriter->syncPoint AndAlso _
       offset + amount >= pWriter->syncPoint Then
        Dim firstAmount As SQLITE_C_INT = CInt(pWriter->syncPoint - offset)
        If firstAmount <= 0 OrElse firstAmount > amount Then Return SQLITE_CORRUPT
        Dim rc As SQLITE_C_INT = sqlite3OsWrite(pWriter->pFile, pBytes, firstAmount, offset)
        If rc <> SQLITE_OK Then Return rc

        offset += firstAmount
        amount -= firstAmount
        pBytes += firstAmount
        rc = sqlite3OsSync(pWriter->pFile, WAL_SYNC_FLAGS(pWriter->syncFlags))
        If amount = 0 OrElse rc <> SQLITE_OK Then Return rc
    End If
    Return sqlite3OsWrite(pWriter->pFile, pBytes, amount, offset)
End Function

Private Function walWriteOneFrame CDecl Alias "walWriteOneFrame" ( _
    ByVal pWriter As SqliteWalWriter Ptr, _
    ByVal pPage As PgHdr Ptr, _
    ByVal truncatePages As u32, _
    ByVal offset As sqlite3_int64 _
) As SQLITE_C_INT
    If pWriter = 0 OrElse pWriter->pWal = 0 OrElse pPage = 0 OrElse _
       pPage->pData = 0 Then Return SQLITE_MISUSE
    Dim frameHeader(0 To SQLITE_WAL_FRAME_HEADER_SIZE - 1) As UByte
    walEncodeFrame(pWriter->pWal, pPage->pgno, CUInt(truncatePages), _
                   CPtr(UByte Ptr, pPage->pData), @frameHeader(0))
    Dim rc As SQLITE_C_INT = walWriteToLog(pWriter, @frameHeader(0), _
        SQLITE_WAL_FRAME_HEADER_SIZE, offset)
    If rc <> SQLITE_OK Then Return rc
    If offset > &H7FFFFFFFFFFFFFFFLL - SQLITE_WAL_FRAME_HEADER_SIZE Then Return SQLITE_FULL
    Return walWriteToLog(pWriter, pPage->pData, pWriter->pageSize, _
        offset + SQLITE_WAL_FRAME_HEADER_SIZE)
End Function

Private Function walRewriteChecksums CDecl Alias "walRewriteChecksums" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal lastFrame As u32 _
) As SQLITE_C_INT
    If pWal = 0 OrElse pWal->recalculateChecksumFrame = 0 OrElse _
       pWal->pageSize < 512 OrElse pWal->pageSize > 65536 Then Return SQLITE_MISUSE

    Dim pageSize As SQLITE_C_INT = CInt(pWal->pageSize)
    Dim frameSize As SQLITE_C_INT = pageSize + SQLITE_WAL_FRAME_HEADER_SIZE
    Dim bufferSize As sqlite3_uint64 = CULngInt(frameSize)
    Dim pBuffer As UByte Ptr = CPtr(UByte Ptr, sqlite3_malloc64(bufferSize))
    If pBuffer = 0 Then Return SQLITE_NOMEM

    Dim checksumOffset As sqlite3_int64
    If pWal->recalculateChecksumFrame = 1 Then
        checksumOffset = SQLITE_WAL_HEADER_SIZE - 8
    Else
        checksumOffset = walFrameOffset(pWal->recalculateChecksumFrame - 1, CUInt(pageSize)) + 16
    End If
    Dim rc As SQLITE_C_INT = sqlite3OsRead(pWal->pWalFile, pBuffer, 8, checksumOffset)
    If rc = SQLITE_OK Then
        pWal->header.frameChecksum(0) = sqlite3Get4byte(pBuffer)
        pWal->header.frameChecksum(1) = sqlite3Get4byte(pBuffer + SizeOf(u32))
    End If

    Dim firstFrame As u32 = pWal->recalculateChecksumFrame
    pWal->recalculateChecksumFrame = 0
    Dim frameIndex As u32 = firstFrame
    While rc = SQLITE_OK AndAlso frameIndex <= lastFrame
        Dim offset As sqlite3_int64 = walFrameOffset(frameIndex, CUInt(pageSize))
        rc = sqlite3OsRead(pWal->pWalFile, pBuffer, frameSize, offset)
        If rc = SQLITE_OK Then
            Dim pageNumber As u32 = sqlite3Get4byte(pBuffer)
            Dim truncatePages As u32 = sqlite3Get4byte(pBuffer + SizeOf(u32))
            If pageNumber = 0 Then
                rc = SQLITE_CORRUPT
                Exit While
            End If
            Dim frameHeader(0 To SQLITE_WAL_FRAME_HEADER_SIZE - 1) As UByte
            walEncodeFrame(pWal, pageNumber, truncatePages, _
                pBuffer + SQLITE_WAL_FRAME_HEADER_SIZE, @frameHeader(0))
            rc = sqlite3OsWrite(pWal->pWalFile, @frameHeader(0), _
                SQLITE_WAL_FRAME_HEADER_SIZE, offset)
        End If
        If frameIndex = &HFFFFFFFFUL Then Exit While
        frameIndex += 1
    Wend

    sqlite3_free(pBuffer)
    Return rc
End Function

Private Function walFrames CDecl Alias "walFrames" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal pageSize As SQLITE_C_INT, _
    ByVal pList As PgHdr Ptr, _
    ByVal truncatePages As u32, _
    ByVal isCommit As SQLITE_C_INT, _
    ByVal syncFlags As SQLITE_C_INT _
) As SQLITE_C_INT
    If pWal = 0 OrElse pList = 0 OrElse pWal->writeLock = 0 OrElse _
       pageSize < 512 OrElse pageSize > 65536 OrElse _
       (pageSize And (pageSize - 1)) <> 0 OrElse _
       (isCommit <> 0 AndAlso truncatePages = 0) OrElse _
       (isCommit = 0 AndAlso truncatePages <> 0) Then Return SQLITE_MISUSE

    Dim pLiveHeader As SqliteWalIndexHeader Ptr = walIndexHdr(pWal)
    If pLiveHeader = 0 Then Return SQLITE_CORRUPT
    Dim firstNewFrame As u32 = 0
    If walSystemMemcmp(@pWal->header, pLiveHeader, SizeOf(pWal->header)) <> 0 Then
        If pLiveHeader->maxFrame = &HFFFFFFFFUL Then Return SQLITE_FULL
        firstNewFrame = pLiveHeader->maxFrame + 1
    End If

    Dim rc As SQLITE_C_INT = walRestartLog(pWal)
    If rc <> SQLITE_OK Then Return rc
    If pWal->header.maxFrame = &HFFFFFFFFUL Then Return SQLITE_FULL

    If pWal->header.maxFrame = 0 Then
        Dim walHeader(0 To SQLITE_WAL_HEADER_SIZE - 1) As UByte
        Dim headerChecksum(0 To 1) As u32
        Dim magic As u32 = SQLITE_WAL_MAGIC Or CUInt(walHostIsBigEndian())
        sqlite3Put4byte(@walHeader(0), magic)
        sqlite3Put4byte(@walHeader(4), SQLITE_WALINDEX_MAX_VERSION)
        sqlite3Put4byte(@walHeader(8), CUInt(pageSize))
        sqlite3Put4byte(@walHeader(12), pWal->checkpointSequence)
        If pWal->checkpointSequence = 0 Then
            sqlite3_randomness(8, @pWal->header.salt(0))
        End If
        walSystemMemcpy(@walHeader(16), @pWal->header.salt(0), 8)
        walChecksumBytes(1, @walHeader(0), SQLITE_WAL_HEADER_SIZE - 8, _
            0, @headerChecksum(0))
        sqlite3Put4byte(@walHeader(24), headerChecksum(0))
        sqlite3Put4byte(@walHeader(28), headerChecksum(1))

        pWal->pageSize = CUInt(pageSize)
        pWal->header.bigEndianChecksum = CByte(walHostIsBigEndian())
        pWal->header.frameChecksum(0) = headerChecksum(0)
        pWal->header.frameChecksum(1) = headerChecksum(1)
        pWal->truncateOnCommit = 1

        rc = sqlite3OsWrite(pWal->pWalFile, @walHeader(0), _
            SQLITE_WAL_HEADER_SIZE, 0)
        If rc <> SQLITE_OK Then Return rc
        If pWal->syncHeader <> 0 Then
            rc = sqlite3OsSync(pWal->pWalFile, CKPT_SYNC_FLAGS(syncFlags))
            If rc <> SQLITE_OK Then Return rc
        End If
    End If

    If pWal->pageSize <> CUInt(pageSize) Then Return SQLITE_CORRUPT

    Dim writer As SqliteWalWriter
    writer.pWal = pWal
    writer.pFile = pWal->pWalFile
    writer.syncPoint = 0
    writer.syncFlags = syncFlags
    writer.pageSize = pageSize

    Dim frameSize As SQLITE_C_INT = pageSize + SQLITE_WAL_FRAME_HEADER_SIZE
    Dim frameIndex As u32 = pWal->header.maxFrame
    If frameIndex = &HFFFFFFFFUL Then Return SQLITE_FULL
    Dim fileOffset As sqlite3_int64 = walFrameOffset(frameIndex + 1, CUInt(pageSize))
    Dim pPage As PgHdr Ptr = pList
    Dim pLastPage As PgHdr Ptr = 0
    Dim extraFrameCount As SQLITE_C_INT = 0

    While pPage <> 0
        If pPage->pData = 0 OrElse pPage->pgno = 0 Then Return SQLITE_CORRUPT

        Dim appendFrame As SQLITE_C_INT = 1
        If firstNewFrame <> 0 AndAlso _
           (pPage->pDirty <> 0 OrElse isCommit = 0) Then
            Dim existingFrame As u32 = 0
            rc = walFindFrame(pWal, pPage->pgno, @existingFrame)
            If rc <> SQLITE_OK Then Return rc
            If existingFrame >= firstNewFrame Then
                Dim dataOffset As sqlite3_int64 = _
                    walFrameOffset(existingFrame, CUInt(pageSize)) + _
                    SQLITE_WAL_FRAME_HEADER_SIZE
                If pWal->recalculateChecksumFrame = 0 OrElse _
                   existingFrame < pWal->recalculateChecksumFrame Then
                    pWal->recalculateChecksumFrame = existingFrame
                End If
                rc = sqlite3OsWrite(pWal->pWalFile, pPage->pData, pageSize, dataOffset)
                If rc <> SQLITE_OK Then Return rc
                pPage->flags = pPage->flags And Not PGHDR_WAL_APPEND
                appendFrame = 0
            End If
        End If

        If appendFrame <> 0 Then
            If frameIndex = &HFFFFFFFFUL Then Return SQLITE_FULL
            frameIndex += 1
            Dim pageCommitSize As u32 = 0
            If isCommit <> 0 AndAlso pPage->pDirty = 0 Then pageCommitSize = truncatePages
            rc = walWriteOneFrame(@writer, pPage, pageCommitSize, fileOffset)
            If rc <> SQLITE_OK Then Return rc
            pLastPage = pPage
            If fileOffset > &H7FFFFFFFFFFFFFFFLL - frameSize Then Return SQLITE_FULL
            fileOffset += frameSize
            pPage->flags = pPage->flags Or PGHDR_WAL_APPEND
        End If
        pPage = pPage->pDirty
    Wend

    If isCommit <> 0 AndAlso pWal->recalculateChecksumFrame <> 0 Then
        rc = walRewriteChecksums(pWal, frameIndex)
        If rc <> SQLITE_OK Then Return rc
    End If

    If isCommit <> 0 AndAlso WAL_SYNC_FLAGS(syncFlags) <> 0 Then
        Dim syncAfterPadding As SQLITE_C_INT = 1
        If pWal->padToSectorBoundary <> 0 Then
            Dim sectorSize As SQLITE_C_INT = sqlite3SectorSize(pWal->pWalFile)
            If sectorSize <= 0 Then Return SQLITE_IOERR
            If fileOffset > &H7FFFFFFFFFFFFFFFLL - sectorSize + 1 Then Return SQLITE_FULL
            writer.syncPoint = ((fileOffset + sectorSize - 1) \ sectorSize) * sectorSize
            syncAfterPadding = IIf(writer.syncPoint = fileOffset, 1, 0)
            While fileOffset < writer.syncPoint
                If pLastPage = 0 Then Return SQLITE_CORRUPT
                rc = walWriteOneFrame(@writer, pLastPage, truncatePages, fileOffset)
                If rc <> SQLITE_OK Then Return rc
                fileOffset += frameSize
                extraFrameCount += 1
            Wend
        End If
        If syncAfterPadding <> 0 Then
            rc = sqlite3OsSync(writer.pFile, WAL_SYNC_FLAGS(syncFlags))
            If rc <> SQLITE_OK Then Return rc
        End If
    End If

    If isCommit <> 0 AndAlso pWal->truncateOnCommit <> 0 AndAlso pWal->maxWalSize >= 0 Then
        Dim sizeLimit As sqlite3_int64 = pWal->maxWalSize
        If CULngInt(frameIndex) + CULngInt(extraFrameCount) + 1ULL > &HFFFFFFFFULL Then _
            Return SQLITE_FULL
        Dim finalFrameIndex As sqlite3_uint64 = _
            CULngInt(frameIndex) + CULngInt(extraFrameCount) + 1ULL
        Dim finalWalSize As sqlite3_int64 = walFrameOffset( _
            CUInt(finalFrameIndex), CUInt(pageSize))
        If finalWalSize > pWal->maxWalSize Then sizeLimit = finalWalSize
        walLimitSize(pWal, sizeLimit)
        pWal->truncateOnCommit = 0
    End If

    frameIndex = pWal->header.maxFrame
    pPage = pList
    While pPage <> 0 AndAlso rc = SQLITE_OK
        If (pPage->flags And PGHDR_WAL_APPEND) <> 0 Then
            If frameIndex = &HFFFFFFFFUL Then Return SQLITE_FULL
            frameIndex += 1
            rc = walIndexAppend(pWal, frameIndex, pPage->pgno)
        End If
        pPage = pPage->pDirty
    Wend

    While rc = SQLITE_OK AndAlso extraFrameCount > 0
        If pLastPage = 0 OrElse frameIndex = &HFFFFFFFFUL Then Return SQLITE_CORRUPT
        frameIndex += 1
        extraFrameCount -= 1
        rc = walIndexAppend(pWal, frameIndex, pLastPage->pgno)
    Wend

    If rc = SQLITE_OK Then
        pWal->header.pageSize = CUShort((pageSize And &HFF00) Or (pageSize Shr 16))
        pWal->header.maxFrame = frameIndex
        If isCommit <> 0 Then
            pWal->header.changeCounter += 1
            pWal->header.pageCount = truncatePages
            walIndexWriteHdr(pWal)
            pWal->callbackValue = frameIndex
        End If
    End If
    Return rc
End Function

Function sqlite3WalFrames CDecl Alias "sqlite3WalFrames" ( _
    ByVal pWal As Any Ptr, _
    ByVal pageSize As SQLITE_C_INT, _
    ByVal pList As PgHdr Ptr, _
    ByVal truncatePages As u32, _
    ByVal isCommit As SQLITE_C_INT, _
    ByVal syncFlags As SQLITE_C_INT _
) As SQLITE_C_INT
    If pWal = 0 Then Return SQLITE_MISUSE
    Return walFrames(CPtr(SqliteWal Ptr, pWal), pageSize, pList, _
                     truncatePages, isCommit, syncFlags)
End Function

Private Function walCheckpoint CDecl Alias "walCheckpoint" ( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal pDb As sqlite3 Ptr, _
    ByVal mode As SQLITE_C_INT, _
    ByVal xBusy As SqliteWalBusyCallback, _
    ByVal pBusyArgument As Any Ptr, _
    ByVal syncFlags As SQLITE_C_INT, _
    ByVal pBuffer As UByte Ptr _
) As SQLITE_C_INT
    If pWal = 0 OrElse pDb = 0 OrElse mode < SQLITE_CHECKPOINT_PASSIVE OrElse _
       mode > SQLITE_CHECKPOINT_TRUNCATE Then Return SQLITE_MISUSE

    Dim pageSize As SQLITE_C_INT = walPagesize(pWal)
    Dim pInfo As SqliteWalCheckpointInfo Ptr = walCkptInfo(pWal)
    If pInfo = 0 Then Return SQLITE_CORRUPT
    If xBusy = 0 OrElse mode = SQLITE_CHECKPOINT_PASSIVE Then xBusy = 0

    Dim safeFrame As u32 = pWal->header.maxFrame
    Dim maxPage As u32 = pWal->header.pageCount
    Dim rc As SQLITE_C_INT = SQLITE_OK

    ' A restart or truncate checkpoint still needs its final reader locks
    ' after all frames have been backfilled. Skip only the page-copy work.
    If pInfo->nBackfill < pWal->header.maxFrame Then
        If pageSize <= 0 OrElse pBuffer = 0 Then Return SQLITE_MISUSE
        For readIndex As SQLITE_C_INT = 1 To WAL_NREADER - 1
            Dim readMark As u32 = pInfo->readMark(readIndex)
            If safeFrame > readMark Then
                rc = walBusyLock(pWal, xBusy, pBusyArgument, _
                    WAL_READ_LOCK_BASE + readIndex, 1)
                If rc = SQLITE_OK Then
                    If readIndex = 1 Then
                        pInfo->readMark(readIndex) = safeFrame
                    Else
                        pInfo->readMark(readIndex) = READMARK_NOT_USED
                    End If
                    walShmBarrier(pWal)
                    walUnlockExclusive(pWal, WAL_READ_LOCK_BASE + readIndex, 1)
                ElseIf rc = SQLITE_BUSY Then
                    safeFrame = readMark
                    xBusy = 0
                Else
                    Return rc
                End If
            End If
        Next
    End If

    Dim pIterator As SqliteWalIterator Ptr = 0
    If pInfo->nBackfill < safeFrame Then
        rc = walIteratorInit(pWal, pInfo->nBackfill, @pIterator)
        If rc <> SQLITE_OK Then GoTo checkpoint_cleanup
    End If

    If pIterator <> 0 Then
        rc = walBusyLock(pWal, xBusy, pBusyArgument, WAL_READ_LOCK_BASE, 1)
        If rc = SQLITE_OK Then
            Dim backfillStart As u32 = pInfo->nBackfill
            Dim pLiveHeader As SqliteWalIndexHeader Ptr = walIndexHdr(pWal)
            If pLiveHeader = 0 Then
                rc = SQLITE_CORRUPT
            ElseIf walSystemMemcmp(@pLiveHeader->salt(0), _
                    @pWal->header.salt(0), SizeOf(pWal->header.salt)) = 0 Then
                pInfo->nBackfillAttempted = safeFrame
                walShmBarrier(pWal)

                rc = sqlite3OsSync(pWal->pWalFile, CKPT_SYNC_FLAGS(syncFlags))
                If rc = SQLITE_OK Then
                    Dim requiredBytes As sqlite3_int64 = _
                        CULngInt(maxPage) * CULngInt(pageSize)
                    Dim databaseBytes As sqlite3_int64 = 0
                    sqlite3OsFileControl(pWal->pDbFile, SQLITE_FCNTL_CKPT_START, 0)
                    rc = sqlite3OsFileSize(pWal->pDbFile, @databaseBytes)
                    If rc = SQLITE_OK AndAlso databaseBytes < requiredBytes Then
                        Dim walBytesMaximum As sqlite3_int64 = _
                            CULngInt(pWal->header.maxFrame) * CULngInt(pageSize)
                        If databaseBytes > &H7FFFFFFFFFFFFFFFLL - 65536 OrElse _
                           databaseBytes + 65536 > &H7FFFFFFFFFFFFFFFLL - walBytesMaximum Then
                            rc = SQLITE_CORRUPT
                        ElseIf databaseBytes + 65536 + walBytesMaximum < requiredBytes Then
                            rc = SQLITE_CORRUPT
                        Else
                            sqlite3OsFileControlHint(pWal->pDbFile, _
                                SQLITE_FCNTL_SIZE_HINT, @requiredBytes)
                        End If
                    End If
                End If

                Dim pageNumber As u32 = 0
                Dim frameNumber As u32 = 0
                While rc = SQLITE_OK
                    Dim iteratorResult As SQLITE_C_INT = _
                        walIteratorNext(pIterator, @pageNumber, @frameNumber)
                    If iteratorResult = 1 Then Exit While
                    If iteratorResult <> 0 Then
                        rc = iteratorResult
                        Exit While
                    End If
                    If walFramePgno(pWal, frameNumber) <> pageNumber Then
                        rc = SQLITE_CORRUPT
                        Exit While
                    End If
                    If pDb->isInterrupted <> 0 Then
                        rc = IIf(pDb->mallocFailed <> 0, SQLITE_NOMEM, SQLITE_INTERRUPT)
                        Exit While
                    End If
                    If frameNumber <= backfillStart OrElse frameNumber > safeFrame OrElse _
                       pageNumber > maxPage Then Continue While

                    Dim walOffset As sqlite3_int64 = _
                        walFrameOffset(frameNumber, CUInt(pageSize)) + _
                        SQLITE_WAL_FRAME_HEADER_SIZE
                    rc = sqlite3OsRead(pWal->pWalFile, pBuffer, pageSize, walOffset)
                    If rc <> SQLITE_OK Then Exit While
                    If pageNumber = 0 OrElse _
                       CULngInt(pageNumber - 1) > &H7FFFFFFFFFFFFFFFLL \ CULngInt(pageSize) Then
                        rc = SQLITE_CORRUPT
                        Exit While
                    End If
                    Dim databaseOffset As sqlite3_int64 = _
                        CULngInt(pageNumber - 1) * CULngInt(pageSize)
                    rc = sqlite3OsWrite(pWal->pDbFile, pBuffer, pageSize, databaseOffset)
                Wend
                sqlite3OsFileControl(pWal->pDbFile, SQLITE_FCNTL_CKPT_DONE, 0)

                If rc = SQLITE_OK Then
                    pLiveHeader = walIndexHdr(pWal)
                    If pLiveHeader = 0 Then
                        rc = SQLITE_CORRUPT
                    ElseIf safeFrame = pLiveHeader->maxFrame Then
                        Dim finalDatabaseSize As sqlite3_int64 = _
                            CULngInt(pWal->header.pageCount) * CULngInt(pageSize)
                        rc = sqlite3OsTruncate(pWal->pDbFile, finalDatabaseSize)
                        If rc = SQLITE_OK Then
                            rc = sqlite3OsSync(pWal->pDbFile, CKPT_SYNC_FLAGS(syncFlags))
                        End If
                    End If
                    If rc = SQLITE_OK Then
                        pInfo->nBackfill = safeFrame
                        walShmBarrier(pWal)
                    End If
                End If
            End If
            walUnlockExclusive(pWal, WAL_READ_LOCK_BASE, 1)
        End If
    End If
    If rc = SQLITE_BUSY Then rc = SQLITE_OK

    If rc = SQLITE_OK AndAlso mode <> SQLITE_CHECKPOINT_PASSIVE Then
        If pInfo->nBackfill < pWal->header.maxFrame Then
            rc = SQLITE_BUSY
        ElseIf mode >= SQLITE_CHECKPOINT_RESTART Then
            Dim newSalt As u32 = 0
            sqlite3_randomness(SizeOf(newSalt), @newSalt)
            rc = walBusyLock(pWal, xBusy, pBusyArgument, _
                WAL_READ_LOCK_BASE + 1, WAL_NREADER - 1)
            If rc = SQLITE_OK Then
                If mode = SQLITE_CHECKPOINT_TRUNCATE Then
                    walRestartHdr(pWal, newSalt)
                    rc = sqlite3OsTruncate(pWal->pWalFile, 0)
                End If
                walUnlockExclusive(pWal, WAL_READ_LOCK_BASE + 1, WAL_NREADER - 1)
            End If
        End If
    End If

checkpoint_cleanup:
    walIteratorFree(pIterator)
    Return rc
End Function

Function sqlite3WalCheckpoint CDecl Alias "sqlite3WalCheckpoint" ( _
    ByVal pWalArgument As Any Ptr, _
    ByVal pDbArgument As Any Ptr, _
    ByVal mode As SQLITE_C_INT, _
    ByVal xBusyArgument As Any Ptr, _
    ByVal pBusyArgument As Any Ptr, _
    ByVal syncFlags As SQLITE_C_INT, _
    ByVal bufferSize As SQLITE_C_INT, _
    ByVal pBuffer As UByte Ptr, _
    ByVal pLogFrames As SQLITE_C_INT Ptr, _
    ByVal pCheckpointedFrames As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pWalArgument = 0 OrElse pDbArgument = 0 OrElse _
       mode < SQLITE_CHECKPOINT_NOOP OrElse mode > SQLITE_CHECKPOINT_TRUNCATE Then _
        Return SQLITE_MISUSE
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    Dim pDb As sqlite3 Ptr = CPtr(sqlite3 Ptr, pDbArgument)
    If pWal->checkpointLock <> 0 OrElse pWal->writeLock <> 0 Then Return SQLITE_MISUSE
    If pWal->readOnly <> 0 Then Return SQLITE_READONLY

    Dim busyCallback As SqliteWalBusyCallback = 0
    If xBusyArgument <> 0 Then busyCallback = CPtr(SqliteWalBusyCallback, xBusyArgument)
    Dim effectiveMode As SQLITE_C_INT = mode
    Dim effectiveBusy As SqliteWalBusyCallback = busyCallback
    Dim rc As SQLITE_C_INT = SQLITE_OK

    If mode <> SQLITE_CHECKPOINT_NOOP Then
        rc = walLockExclusive(pWal, WAL_CKPT_LOCK, 1)
        If rc = SQLITE_OK Then
            pWal->checkpointLock = 1
            If mode <> SQLITE_CHECKPOINT_PASSIVE Then
                rc = walBusyLock(pWal, effectiveBusy, pBusyArgument, WAL_WRITE_LOCK, 1)
                If rc = SQLITE_OK Then
                    pWal->writeLock = 1
                ElseIf rc = SQLITE_BUSY Then
                    effectiveMode = SQLITE_CHECKPOINT_PASSIVE
                    effectiveBusy = 0
                    rc = SQLITE_OK
                End If
            End If
        End If
    End If

    Dim changed As SQLITE_C_INT = 0
    If rc = SQLITE_OK Then
        rc = walIndexReadHdr(pWal, @changed)
        If changed <> 0 AndAlso pWal->pDbFile <> 0 AndAlso _
           pWal->pDbFile->pMethods <> 0 AndAlso pWal->pDbFile->pMethods->iVersion >= 3 Then
            sqlite3OsUnfetch(pWal->pDbFile, 0, 0)
        End If
    End If

    If rc = SQLITE_OK Then
        sqlite3FaultSim(660)
        If pWal->header.maxFrame <> 0 AndAlso walPagesize(pWal) <> bufferSize Then
            rc = SQLITE_CORRUPT
        ElseIf effectiveMode <> SQLITE_CHECKPOINT_NOOP Then
            rc = walCheckpoint(pWal, pDb, effectiveMode, effectiveBusy, _
                pBusyArgument, syncFlags, pBuffer)
        End If
        If rc = SQLITE_OK OrElse rc = SQLITE_BUSY Then
            If pLogFrames <> 0 Then pLogFrames[0] = Cast(SQLITE_C_INT, pWal->header.maxFrame)
            If pCheckpointedFrames <> 0 Then
                Dim pInfo As SqliteWalCheckpointInfo Ptr = walCkptInfo(pWal)
                If pInfo = 0 Then
                    rc = SQLITE_CORRUPT
                Else
                    pCheckpointedFrames[0] = Cast(SQLITE_C_INT, pInfo->nBackfill)
                End If
            End If
        End If
    End If

    If changed <> 0 Then walClearIndexHeader(pWal)
    sqlite3WalEndWriteTransaction(pWalArgument)
    If pWal->checkpointLock <> 0 Then
        walUnlockExclusive(pWal, WAL_CKPT_LOCK, 1)
        pWal->checkpointLock = 0
    End If
    If rc = SQLITE_OK AndAlso mode <> effectiveMode Then Return SQLITE_BUSY
    Return rc
End Function

Function sqlite3WalUndo CDecl Alias "sqlite3WalUndo" ( _
    ByVal pWalArgument As Any Ptr, _
    ByVal xUndo As SqliteWalUndoProc, _
    ByVal pUndoContext As Any Ptr _
) As SQLITE_C_INT
    If pWalArgument = 0 OrElse xUndo = 0 Then Return SQLITE_MISUSE
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    If pWal->writeLock = 0 Then Return SQLITE_MISUSE
    Dim pSharedHeader As SqliteWalIndexHeader Ptr = walIndexHdr(pWal)
    If pSharedHeader = 0 Then Return SQLITE_CORRUPT
    Dim maximumFrame As u32 = pWal->header.maxFrame
    pWal->header = pSharedHeader[0]

    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pWal->header.maxFrame < maximumFrame Then
        If pWal->header.maxFrame = &HFFFFFFFFUL Then Return SQLITE_CORRUPT
        Dim frameIndex As u32 = pWal->header.maxFrame + 1
        While frameIndex <= maximumFrame
            Dim pageNumber As u32 = walFramePgno(pWal, frameIndex)
            If pageNumber = 0 Then Return SQLITE_CORRUPT
            rc = xUndo(pUndoContext, pageNumber)
            If rc <> SQLITE_OK Then Exit While
            If frameIndex = &HFFFFFFFFUL Then Exit While
            frameIndex += 1
        Wend
        walCleanupHash(pWal)
    End If
    pWal->recalculateChecksumFrame = 0
    Return rc
End Function

Sub sqlite3WalSavepoint CDecl Alias "sqlite3WalSavepoint" ( _
    ByVal pWalArgument As Any Ptr, _
    ByVal pWalData As u32 Ptr _
)
    If pWalArgument = 0 OrElse pWalData = 0 Then Exit Sub
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    If pWal->writeLock = 0 Then Exit Sub
    pWalData[0] = pWal->header.maxFrame
    pWalData[1] = pWal->header.frameChecksum(0)
    pWalData[2] = pWal->header.frameChecksum(1)
    pWalData[3] = pWal->checkpointSequence
End Sub

Function sqlite3WalSavepointUndo CDecl Alias "sqlite3WalSavepointUndo" ( _
    ByVal pWalArgument As Any Ptr, _
    ByVal pWalData As u32 Ptr _
) As SQLITE_C_INT
    If pWalArgument = 0 OrElse pWalData = 0 Then Return SQLITE_MISUSE
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    If pWal->writeLock = 0 Then Return SQLITE_MISUSE

    If pWalData[3] <> pWal->checkpointSequence Then
        pWalData[0] = 0
        pWalData[3] = pWal->checkpointSequence
    End If
    If pWalData[0] < pWal->header.maxFrame Then
        pWal->header.maxFrame = pWalData[0]
        pWal->header.frameChecksum(0) = pWalData[1]
        pWal->header.frameChecksum(1) = pWalData[2]
        walCleanupHash(pWal)
        If pWal->recalculateChecksumFrame > pWal->header.maxFrame Then _
            pWal->recalculateChecksumFrame = 0
    End If
    Return SQLITE_OK
End Function

Function sqlite3WalClose CDecl Alias "sqlite3WalClose" ( _
    ByVal pWalArgument As Any Ptr, _
    ByVal pDbArgument As Any Ptr, _
    ByVal syncFlags As SQLITE_C_INT, _
    ByVal bufferSize As SQLITE_C_INT, _
    ByVal pBuffer As UByte Ptr _
) As SQLITE_C_INT
    If pWalArgument = 0 Then Return SQLITE_OK
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    If pWal->pDbFile = 0 OrElse pWal->pWalFile = 0 OrElse pWal->pVfs = 0 Then _
        Return SQLITE_MISUSE
#if defined(SQLITE_DEBUG) AndAlso defined(SQLITE_USE_SEH)
    If walAssertLockmask(pWal) = 0 Then Return SQLITE_CORRUPT
#endif

    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim deleteWal As SQLITE_C_INT = 0
    If pBuffer <> 0 Then
        rc = sqlite3OsLock(pWal->pDbFile, EXCLUSIVE_LOCK)
        If rc = SQLITE_OK Then
            If pWal->exclusiveMode = WAL_NORMAL_MODE Then _
                pWal->exclusiveMode = WAL_EXCLUSIVE_MODE
            rc = sqlite3WalCheckpoint(pWalArgument, pDbArgument, _
                SQLITE_CHECKPOINT_PASSIVE, 0, 0, syncFlags, bufferSize, pBuffer, 0, 0)
            If rc = SQLITE_OK Then
                Dim persistWal As SQLITE_C_INT = -1
                sqlite3OsFileControlHint(pWal->pDbFile, _
                    SQLITE_FCNTL_PERSIST_WAL, @persistWal)
                If persistWal <> 1 Then
                    deleteWal = 1
                ElseIf pWal->maxWalSize >= 0 Then
                    walLimitSize(pWal, 0)
                End If
            End If
        End If
    End If

    walIndexClose(pWal, deleteWal)
    sqlite3OsClose(pWal->pWalFile)
    If deleteWal <> 0 Then
        sqlite3BeginBenignMalloc()
        sqlite3OsDelete(pWal->pVfs, pWal->walName, 0)
        sqlite3EndBenignMalloc()
    End If
    If pWal->walIndexData <> 0 Then sqlite3_free(pWal->walIndexData)
    sqlite3_free(pWal)
    Return rc
End Function

Function sqlite3WalCallback CDecl Alias "sqlite3WalCallback" ( _
    ByVal pWalArgument As Any Ptr _
) As SQLITE_C_INT
    If pWalArgument = 0 Then Return 0
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    Dim frameCount As u32 = pWal->callbackValue
    pWal->callbackValue = 0
    Return Cast(SQLITE_C_INT, frameCount)
End Function

Function sqlite3WalExclusiveMode CDecl Alias "sqlite3WalExclusiveMode" ( _
    ByVal pWalArgument As Any Ptr, _
    ByVal operation As SQLITE_C_INT _
) As SQLITE_C_INT
    If pWalArgument = 0 Then Return 0
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    If pWal->writeLock <> 0 Then Return 0
    If pWal->exclusiveMode = WAL_HEAPMEMORY_MODE Then Return 0

    If operation = 0 Then
        If pWal->exclusiveMode = WAL_NORMAL_MODE Then Return 0
        If pWal->readLock < 0 Then Return 0
        pWal->exclusiveMode = WAL_NORMAL_MODE
        If walLockShared(pWal, WAL_READ_LOCK_BASE + pWal->readLock) <> SQLITE_OK Then
            pWal->exclusiveMode = WAL_EXCLUSIVE_MODE
        End If
        Return IIf(pWal->exclusiveMode = WAL_NORMAL_MODE, 1, 0)
    ElseIf operation > 0 Then
        If pWal->exclusiveMode <> WAL_NORMAL_MODE OrElse pWal->readLock < 0 Then Return 0
        walUnlockShared(pWal, WAL_READ_LOCK_BASE + pWal->readLock)
        pWal->exclusiveMode = WAL_EXCLUSIVE_MODE
        Return 1
    End If
    Return IIf(pWal->exclusiveMode = WAL_NORMAL_MODE, 1, 0)
End Function

Function sqlite3WalFile CDecl Alias "sqlite3WalFile" ( _
    ByVal pWalArgument As Any Ptr _
) As sqlite3_file Ptr
    If pWalArgument = 0 Then Return 0
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    Return pWal->pWalFile
End Function

#ifdef SQLITE_ENABLE_SNAPSHOT
Private Function walSnapshotRecover( _
    ByVal pWal As SqliteWal Ptr, _
    ByVal pWalBuffer As UByte Ptr, _
    ByVal pDatabaseBuffer As UByte Ptr _
) As SQLITE_C_INT
    If pWal = 0 OrElse pWalBuffer = 0 OrElse pDatabaseBuffer = 0 Then _
        Return SQLITE_MISUSE
    If pWal->pageSize = 0 OrElse pWal->pageSize > SQLITE_MAX_PAGE_SIZE Then _
        Return SQLITE_CORRUPT

    Dim databaseSize As sqlite3_int64 = 0
    Dim rc As SQLITE_C_INT = sqlite3OsFileSize(pWal->pDbFile, @databaseSize)
    If rc <> SQLITE_OK Then Return rc

    Dim pInfo As SqliteWalCheckpointInfo Ptr = walCkptInfo(pWal)
    If pInfo = 0 Then Return SQLITE_CORRUPT

    Dim frameIndex As u32 = pInfo->nBackfillAttempted
    Dim backfilledFrame As u32 = pInfo->nBackfill
    While frameIndex > backfilledFrame
        Dim location As SqliteWalHashLocation
        rc = walHashGet(pWal, walFramePage(frameIndex), @location)
        If rc <> SQLITE_OK Then Exit While
        If frameIndex <= location.iZero OrElse location.aPgno = 0 Then _
            Return SQLITE_CORRUPT

        Dim slotIndex As sqlite3_uint64 = _
            CULngInt(frameIndex) - CULngInt(location.iZero) - 1
        Dim pageNumber As u32 = location.aPgno[slotIndex]
        If pageNumber = 0 Then Return SQLITE_CORRUPT

        Dim databaseOffset As sqlite3_uint64 = _
            (CULngInt(pageNumber) - 1ULL) * CULngInt(pWal->pageSize)
        If databaseOffset + CULngInt(pWal->pageSize) <= _
           CULngInt(databaseSize) Then
            Dim walOffset As sqlite3_int64 = _
                walFrameOffset(frameIndex, pWal->pageSize) + _
                SQLITE_WAL_FRAME_HEADER_SIZE
            rc = sqlite3OsRead(pWal->pWalFile, pWalBuffer, _
                CInt(pWal->pageSize), walOffset)
            If rc = SQLITE_OK Then
                rc = sqlite3OsRead(pWal->pDbFile, pDatabaseBuffer, _
                    CInt(pWal->pageSize), CLngInt(databaseOffset))
            End If
            If rc <> SQLITE_OK OrElse _
               walSystemMemcmp(pWalBuffer, pDatabaseBuffer, _
                   CULngInt(pWal->pageSize)) = 0 Then Exit While
        End If

        ' The exclusive checkpoint lock keeps the backfill boundary stable.
        pInfo->nBackfillAttempted = frameIndex - 1
        frameIndex -= 1
    Wend
    Return rc
End Function

Function sqlite3WalSnapshotRecover CDecl Alias "sqlite3WalSnapshotRecover" ( _
    ByVal pWalArgument As Any Ptr _
) As SQLITE_C_INT Export
    If pWalArgument = 0 Then Return SQLITE_MISUSE
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    If pWal->readLock < 0 OrElse pWal->pageSize = 0 Then Return SQLITE_MISUSE

    Dim rc As SQLITE_C_INT = walLockExclusive(pWal, WAL_CKPT_LOCK, 1)
    If rc <> SQLITE_OK Then Return rc

    Dim pWalBuffer As UByte Ptr = CPtr(UByte Ptr, _
        sqlite3_malloc64(CULngInt(pWal->pageSize)))
    Dim pDatabaseBuffer As UByte Ptr = CPtr(UByte Ptr, _
        sqlite3_malloc64(CULngInt(pWal->pageSize)))
    If pWalBuffer = 0 OrElse pDatabaseBuffer = 0 Then
        rc = SQLITE_NOMEM
    Else
        pWal->checkpointLock = 1
        rc = walSnapshotRecover(pWal, pWalBuffer, pDatabaseBuffer)
        pWal->checkpointLock = 0
    End If

    If pWalBuffer <> 0 Then sqlite3_free(pWalBuffer)
    If pDatabaseBuffer <> 0 Then sqlite3_free(pDatabaseBuffer)
    walUnlockExclusive(pWal, WAL_CKPT_LOCK, 1)
    Return rc
End Function

Function sqlite3WalSnapshotGet CDecl Alias "sqlite3WalSnapshotGet" ( _
    ByVal pWalArgument As Any Ptr, _
    ByVal ppSnapshot As Any Ptr Ptr _
) As SQLITE_C_INT Export
    If pWalArgument = 0 OrElse ppSnapshot = 0 Then Return SQLITE_MISUSE
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    If pWal->readLock < 0 OrElse pWal->writeLock <> 0 Then Return SQLITE_MISUSE

    Dim pHeader As SqliteWalIndexHeader Ptr = @pWal->header
    If pHeader->frameChecksum(0) = 0 AndAlso _
       pHeader->frameChecksum(1) = 0 AndAlso _
       pHeader->salt(0) = 0 AndAlso pHeader->salt(1) = 0 Then
        ppSnapshot[0] = 0
        Return SQLITE_ERROR
    End If

    Dim pSnapshot As SqliteWalIndexHeader Ptr = CPtr( _
        SqliteWalIndexHeader Ptr, sqlite3_malloc64(SizeOf(SqliteWalIndexHeader)))
    If pSnapshot = 0 Then Return SQLITE_NOMEM
    walSystemMemcpy(pSnapshot, pHeader, SizeOf(SqliteWalIndexHeader))
    ppSnapshot[0] = pSnapshot
    Return SQLITE_OK
End Function

Sub sqlite3WalSnapshotOpen CDecl Alias "sqlite3WalSnapshotOpen" ( _
    ByVal pWalArgument As Any Ptr, _
    ByVal pSnapshot As Any Ptr _
)
    If pWalArgument = 0 Then Exit Sub
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    If pSnapshot <> 0 AndAlso _
       CPtr(SqliteWalIndexHeader Ptr, pSnapshot)->version = 0 Then
        ' A zero-version header requests the snapshot being read right now.
        pWal->getSnapshot = 1
        pWal->pSnapshot = 0
    Else
        pWal->pSnapshot = CPtr(SqliteWalIndexHeader Ptr, pSnapshot)
        pWal->getSnapshot = 0
    End If
End Sub

Function sqlite3WalSnapshotCheck CDecl Alias "sqlite3WalSnapshotCheck" ( _
    ByVal pWalArgument As Any Ptr, _
    ByVal pSnapshotArgument As Any Ptr _
) As SQLITE_C_INT Export
    If pWalArgument = 0 OrElse pSnapshotArgument = 0 Then Return SQLITE_MISUSE
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    Dim pSnapshot As SqliteWalIndexHeader Ptr = _
        CPtr(SqliteWalIndexHeader Ptr, pSnapshotArgument)
    Dim rc As SQLITE_C_INT = walLockShared(pWal, WAL_CKPT_LOCK)
    If rc <> SQLITE_OK Then Return rc

    Dim pInfo As SqliteWalCheckpointInfo Ptr = walCkptInfo(pWal)
    If pInfo = 0 Then
        rc = SQLITE_CORRUPT
    ElseIf walSystemMemcmp(@pSnapshot->salt(0), @pWal->header.salt(0), _
                           2 * SizeOf(u32)) <> 0 OrElse _
           pSnapshot->maxFrame < pInfo->nBackfillAttempted Then
        rc = SQLITE_ERROR_SNAPSHOT
    End If
    If rc <> SQLITE_OK Then walUnlockShared(pWal, WAL_CKPT_LOCK)
    Return rc
End Function

Sub sqlite3WalSnapshotUnlock CDecl Alias "sqlite3WalSnapshotUnlock" ( _
    ByVal pWalArgument As Any Ptr _
)
    If pWalArgument = 0 Then Exit Sub
    walUnlockShared(CPtr(SqliteWal Ptr, pWalArgument), WAL_CKPT_LOCK)
End Sub
#endif

#ifdef SQLITE_ENABLE_ZIPVFS
Function sqlite3WalFramesize CDecl Alias "sqlite3WalFramesize" ( _
    ByVal pWalArgument As Any Ptr _
) As SQLITE_C_INT
    If pWalArgument = 0 Then Return 0
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    If pWal->readLock < 0 Then Return 0
    Return CInt(pWal->pageSize)
End Function
#endif

#if defined(SQLITE_DEBUG) OrElse defined(SQLITE_ENABLE_WALSTAT)
#ifndef SQLITE_OMIT_WAL
Private Sub walIndexHdrStat( _
    ByVal pHeader As SqliteWalIndexHeader Ptr, _
    ByVal pStr As sqlite3_str Ptr _
)
    If pHeader = 0 OrElse pStr = 0 Then Return
    sqlite3_str_appendf(pStr, StrPtr(!"iVersion:%u"), pHeader->version)
    sqlite3_str_appendf(pStr, StrPtr(!",iChange:%u"), pHeader->changeCounter)
    sqlite3_str_appendf(pStr, StrPtr(!",isInit:%u"), pHeader->isInitialized)
    sqlite3_str_appendf(pStr, StrPtr(!",bigEndCksum:%u"), pHeader->bigEndianChecksum)
    sqlite3_str_appendf(pStr, StrPtr(!",szPage:%u"), pHeader->pageSize)
    sqlite3_str_appendf(pStr, StrPtr(!",mxFrame:%u"), pHeader->maxFrame)
    sqlite3_str_appendf(pStr, StrPtr(!",nPage:%u"), pHeader->pageCount)
End Sub

Sub sqlite3WalStat CDecl Alias "sqlite3WalStat" ( _
    ByVal pWalArgument As Any Ptr, _
    ByVal pStrArgument As Any Ptr _
)
    If pWalArgument = 0 OrElse pStrArgument = 0 Then Return
    Dim pWal As SqliteWal Ptr = CPtr(SqliteWal Ptr, pWalArgument)
    Dim pStr As sqlite3_str Ptr = CPtr(sqlite3_str Ptr, pStrArgument)
    Dim pInfo As SqliteWalCheckpointInfo Ptr = walCkptInfo(pWal)
    Dim pHeader As SqliteWalIndexHeader Ptr = walIndexHdr(pWal)
    If pInfo = 0 OrElse pHeader = 0 Then Return

    sqlite3_str_appendf(pStr, StrPtr(!"hdr0:{"))
    walIndexHdrStat(pHeader, pStr)
    sqlite3_str_appendf(pStr, StrPtr(!"},ckpt:{"))
    sqlite3_str_appendf(pStr, StrPtr(!"nBackfill:%u"), pInfo->nBackfill)
    sqlite3_str_appendf(pStr, StrPtr(!",aReadMark:[%u"), pInfo->readMark(0))
    For readIndex As SQLITE_C_INT = 1 To WAL_NREADER - 1
        sqlite3_str_appendf(pStr, StrPtr(!",%u"), pInfo->readMark(readIndex))
    Next
    sqlite3_str_appendf(pStr, StrPtr(!"],nBackfillAttempted:%u}"), _
                        pInfo->nBackfillAttempted)
    sqlite3_str_appendf(pStr, StrPtr(!",nWiData:%d"), pWal->walIndexDataCount)
    sqlite3_str_appendf(pStr, StrPtr(!",readLock:%d"), pWal->readLock)
    sqlite3_str_appendf(pStr, StrPtr(!",minFrame:%u"), pWal->minFrame)
End Sub
#endif
#endif

/' end of sqlite3_wal.bas '/
