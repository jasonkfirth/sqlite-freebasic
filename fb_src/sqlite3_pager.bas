/'
    Project: SQLite FreeBASIC port

    File: sqlite3_pager.bas

    Purpose:

        Implement pager setup, rollback journaling, database-page access, and WAL transitions.

    Responsibilities:

        - Connect a VFS file to the page cache and pager state.
        - Delay opening transient database files until a cache spill needs disk backing.
        - Acquire a shared database lock before reading pages.
        - Manage database lock levels and retry lock acquisition through the busy callback.
        - Load, zero-fill, reference, and release database pages.
        - Journal original page images and commit or roll back single-file transactions.
        - Release pager locks and reset page-cache state after I/O errors.
        - Change journal modes while protecting and deleting rollback journals.
        - Validate super-journal tails and remove orphaned super-journal files.
        - Validate journal headers and replay main-journal and sub-journal page records.
        - Preserve journal checksums and release the mmap-header freelist at close.
        - Release savepoints according to exclusive-mode journal ownership.
        - Check dirty-page/savepoint truncate invariants in debug builds.
        - Move and rekey cached pages while preserving journal/savepoint state.
        - Spill unreferenced dirty pages only after journal synchronization and lock upgrade.
        - Open and close WAL connections while preserving database lock and mmap state.
        - Retain the database handle used by optional WAL blocking-lock timeouts.
        - Route optional snapshot get/open/check/recover operations to the WAL layer.
        - Append WAL diagnostic state when SQLITE_ENABLE_WALSTAT is enabled.
        - Expose page number, cache reference count, backup pointer, and sector-size helpers.
        - Track and verify cached page hashes when SQLITE_CHECK_PAGES is enabled.
        - Expose pager statistics and I/O-error suppression hooks in SQLITE_TEST builds.

    This file intentionally does NOT contain:

        - WAL frame writes, snapshot frame selection, or mmap page access.
        - Full multi-database super-journal cleanup.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_bitvec.bi"
#include once "sqlite3_pcache.bi"
#include once "sqlite3_varint.bi"
#include once "sqlite3_vfs.bi"
#include once "sqlite3_memjournal.bi"
#include once "sqlite3_pager.bi"
#include once "sqlite3_os_test.bi"
#include once "sqlite3_debug_assert.bi"
Declare Function sqlite3Malloc CDecl Alias "sqlite3Malloc" (ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Function sqlite3MallocZero CDecl Alias "sqlite3MallocZero" (ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Function sqlite3Realloc CDecl Alias "sqlite3Realloc" (ByVal pOld As Any Ptr, ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" (ByVal z As Const ZString Ptr) As SQLITE_C_INT
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Declare Function sqlite3_create_filename CDecl Alias "sqlite3_create_filename" ( _
    ByVal zDatabase As Const ZString Ptr, _
    ByVal zJournal As Const ZString Ptr, _
    ByVal zWal As Const ZString Ptr, _
    ByVal parameterCount As SQLITE_C_INT, _
    ByVal parameters As Const ZString Ptr Ptr _
) As Const ZString Ptr
Declare Function sqlite3_filename_journal CDecl Alias "sqlite3_filename_journal" ( _
    ByVal zFilename As Const ZString Ptr _
) As Const ZString Ptr
Declare Function sqlite3_filename_wal CDecl Alias "sqlite3_filename_wal" ( _
    ByVal zFilename As Const ZString Ptr _
) As Const ZString Ptr
Declare Sub sqlite3_free_filename CDecl Alias "sqlite3_free_filename" ( _
    ByVal zFilename As Const ZString Ptr _
)
Declare Function sqlite3_snprintf CDecl Alias "sqlite3_snprintf" ( _
    ByVal bufferSize As SQLITE_C_INT, _
    ByVal pBuffer As ZString Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) As ZString Ptr
Declare Function pagerStmtJournalSpillLimit CDecl Alias "pagerStmtJournalSpillLimit" () As SQLITE_C_INT
Declare Sub sqlite3_randomness CDecl Alias "sqlite3_randomness" ( _
    ByVal byteCount As SQLITE_C_INT, _
    ByVal pOutput As Any Ptr _
)
Declare Function pagerOpentemp CDecl Alias "pagerOpentemp" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Sub pager_write_changecounter CDecl Alias "pager_write_changecounter" ( _
    ByVal pPage As PgHdr Ptr _
)
Declare Function pagerWalCommitBridge CDecl Alias "pagerWalCommitBridge" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
Declare Function pagerWalFrames CDecl Alias "pagerWalFrames" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pPageList As PgHdr Ptr, _
    ByVal truncatePages As u32, _
    ByVal isCommit As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function pagerEndTransactionBridge CDecl Alias "pagerEndTransactionBridge" ( _
    ByVal pPager As Pager Ptr, _
    ByVal hasSuperJournal As SQLITE_C_INT, _
    ByVal isCommit As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function pagerTruncateBridge CDecl Alias "pagerTruncateBridge" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pageCount As u32 _
) As SQLITE_C_INT
Declare Sub pagerUnlockAndRollbackBridge CDecl Alias "pagerUnlockAndRollbackBridge" ( _
    ByVal pPager As Pager Ptr _
)
Declare Function pagerRollbackWalBridge CDecl Alias "pagerRollbackWalBridge" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
Declare Function pagerPlaybackBridge CDecl Alias "pagerPlaybackBridge" ( _
    ByVal pPager As Pager Ptr, _
    ByVal isHot As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3_libversion_number CDecl Alias "sqlite3_libversion_number" () As SQLITE_C_INT
Declare Function sqlite3WalDbsize CDecl Alias "sqlite3WalDbsize" (ByVal pWal As Any Ptr) As u32
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
Declare Sub sqlite3WalDb CDecl Alias "sqlite3WalDb" ( _
    ByVal pWal As Any Ptr, _
    ByVal db As Any Ptr _
)
Declare Function sqlite3WalWriteLock CDecl Alias "sqlite3WalWriteLock" ( _
    ByVal pWal As Any Ptr, _
    ByVal bLock As SQLITE_C_INT _
) As SQLITE_C_INT
#endif
Declare Sub setGetterMethod CDecl Alias "setGetterMethod" (ByVal pPager As Pager Ptr)
#ifndef SQLITE_OMIT_WAL
Declare Function pagerOpenWalIfPresent CDecl Alias "pagerOpenWalIfPresent" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
#endif
Declare Sub sqlite3BeginBenignMalloc CDecl Alias "sqlite3BeginBenignMalloc" ()
Declare Sub sqlite3EndBenignMalloc CDecl Alias "sqlite3EndBenignMalloc" ()

Private Const PAGER_MAX_SECTOR_SIZE As Long = &H10000
Private Const PAGER_MIN_SECTOR_SIZE As SQLITE_C_INT = 32
Private Const PAGER_DEFAULT_SECTOR_SIZE As SQLITE_C_INT = 512
Private Const PAGER_FILE_VERSION_OFFSET As sqlite3_int64 = 24
' These mode bits distinguish persistent rollback journals from WAL mode.
Private Const PAGER_JOURNALMODE_ROLLBACK_MASK As u8 = &H05
Private Const PAGER_JOURNALMODE_WAL_BIT As u8 = &H01
Declare Sub pagerUnlockIfUnused (ByVal pPager As Pager Ptr)
Declare Sub releaseAllSavepoints (ByVal pPager As Pager Ptr)
Declare Sub pager_reset CDecl Alias "pager_reset" (ByVal pPager As Pager Ptr)
Declare Sub setSectorSize CDecl Alias "setSectorSize" (ByVal pPager As Pager Ptr)
Declare Sub pagerFixMaplimit CDecl Alias "pagerFixMaplimit" (ByVal pPager As Pager Ptr)
Declare Sub sqlite3BackupRestart CDecl Alias "sqlite3BackupRestart" (ByVal pBackup As Any Ptr)
Declare Sub sqlite3BackupUpdate CDecl Alias "sqlite3BackupUpdate" ( _
    ByVal pBackup As Any Ptr, _
    ByVal pageNumber As u32, _
    ByVal pPageData As Const UByte Ptr _
)
Declare Function pagerJournalMagicByte (ByVal index As Long) As UByte
Declare Function pager_cksum CDecl Alias "pager_cksum" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pData As Const UByte Ptr _
) As u32
Declare Sub pagerFreeMapHdrs CDecl Alias "pagerFreeMapHdrs" ( _
    ByVal pPager As Pager Ptr _
)
Declare Function pagerSyncHotJournal CDecl Alias "pagerSyncHotJournal" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
Declare Function pagerAddToSavepointBitvecs (ByVal pPager As Pager Ptr, ByVal pageNumber As u32) As SQLITE_C_INT
Declare Function pagerStress CDecl ( _
    ByVal pArgument As Any Ptr, _
    ByVal pPage As PgHdr Ptr _
) As SQLITE_C_INT

Private Function pagerStringLength(ByVal z As Const ZString Ptr) As SQLITE_C_INT
    If z = 0 Then Return 0
    Dim n As SQLITE_C_INT = 0
    While n < SQLITE_MAX_LENGTH AndAlso z[n] <> 0
        n += 1
    Wend
    Return n
End Function

Private Function pagerStringDup(ByVal z As Const ZString Ptr) As ZString Ptr
    Dim n As SQLITE_C_INT = pagerStringLength(z)
    Dim copyBytes As UByte Ptr = CPtr(UByte Ptr, sqlite3Malloc(CULngInt(n) + 1))
    If copyBytes = 0 Then Return 0
    Dim sourceBytes As Const UByte Ptr = CPtr(Const UByte Ptr, z)
    For i As Long = 0 To n - 1
        copyBytes[i] = sourceBytes[i]
    Next
    copyBytes[n] = 0
    Return CPtr(ZString Ptr, copyBytes)
End Function

Private Function pagerStringWithSuffix( _
    ByVal z As Const ZString Ptr, _
    ByVal zSuffix As Const ZString Ptr _
) As ZString Ptr

    Dim nBase As SQLITE_C_INT = pagerStringLength(z)
    Dim nSuffix As SQLITE_C_INT = pagerStringLength(zSuffix)
    If nBase > SQLITE_MAX_LENGTH - nSuffix - 1 Then Return 0
    Dim resultBytes As UByte Ptr = CPtr(UByte Ptr, sqlite3Malloc(CULngInt(nBase) + nSuffix + 1))
    If resultBytes = 0 Then Return 0
    Dim baseBytes As Const UByte Ptr = CPtr(Const UByte Ptr, z)
    Dim suffixBytes As Const UByte Ptr = CPtr(Const UByte Ptr, zSuffix)
    For i As Long = 0 To nBase - 1
        resultBytes[i] = baseBytes[i]
    Next
    For i As Long = 0 To nSuffix - 1
        resultBytes[nBase + i] = suffixBytes[i]
    Next
    resultBytes[nBase + nSuffix] = 0
    Return CPtr(ZString Ptr, resultBytes)
End Function

' VFS filenames use SQLite's packed layout so sqlite3_uri_parameter() can
' read the query tail and sqlite3_filename_database() can find the DB path.
' Keep the database, journal, and WAL names in one sqlite3_filename allocation.
Private Function pagerCreatePackedFilename( _
    ByVal zDatabase As Const ZString Ptr, _
    ByVal zSourceFilename As Const ZString Ptr, _
    ByVal ppJournal As ZString Ptr Ptr, _
    ByVal ppWal As ZString Ptr Ptr _
) As ZString Ptr
    If zDatabase = 0 OrElse ppJournal = 0 OrElse ppWal = 0 Then Return 0
    ppJournal[0] = 0
    ppWal[0] = 0

    Dim databaseLength As SQLITE_C_INT = sqlite3Strlen30(zDatabase)
    Dim parameterCount As SQLITE_C_INT = 0
    Dim pSource As Const UByte Ptr = CPtr(Const UByte Ptr, zSourceFilename)
    If databaseLength > 0 AndAlso pSource <> 0 Then
        Dim sourceLength As SQLITE_C_INT = sqlite3Strlen30(zSourceFilename)
        Dim pOption As Const UByte Ptr = pSource + sourceLength + 1
        While pOption[0] <> 0
            Dim keyLength As SQLITE_C_INT = sqlite3Strlen30( _
                CPtr(Const ZString Ptr, pOption))
            pOption += keyLength + 1
            Dim valueLength As SQLITE_C_INT = sqlite3Strlen30( _
                CPtr(Const ZString Ptr, pOption))
            pOption += valueLength + 1
            If parameterCount >= SQLITE_MAX_ALLOCATION_SIZE \ 2 Then Return 0
            parameterCount += 1
        Wend
    End If

    Dim parameterArray As Const ZString Ptr Ptr = 0
    If parameterCount > 0 Then
        Dim pointerCount As sqlite3_uint64 = CULngInt(parameterCount) * 2
        If pointerCount > CULngInt(SQLITE_MAX_ALLOCATION_SIZE) \ _
                            SizeOf(Any Ptr) Then Return 0
        parameterArray = CPtr(Const ZString Ptr Ptr, _
            sqlite3MallocZero(pointerCount * SizeOf(Any Ptr)))
        If parameterArray = 0 Then Return 0

        Dim sourceLength As SQLITE_C_INT = sqlite3Strlen30(zSourceFilename)
        Dim pOption As Const UByte Ptr = pSource + sourceLength + 1
        For parameterIndex As SQLITE_C_INT = 0 To parameterCount - 1
            parameterArray[parameterIndex * 2] = _
                CPtr(Const ZString Ptr, pOption)
            Dim keyLength As SQLITE_C_INT = sqlite3Strlen30( _
                CPtr(Const ZString Ptr, pOption))
            pOption += keyLength + 1
            parameterArray[parameterIndex * 2 + 1] = _
                CPtr(Const ZString Ptr, pOption)
            Dim valueLength As SQLITE_C_INT = sqlite3Strlen30( _
                CPtr(Const ZString Ptr, pOption))
            pOption += valueLength + 1
        Next
    End If

    Dim zJournalName As ZString Ptr = StrPtr("")
    Dim zWalName As ZString Ptr = StrPtr("")
    If databaseLength > 0 Then
        zJournalName = pagerStringWithSuffix(zDatabase, StrPtr("-journal"))
        If zJournalName = 0 Then
            If parameterArray <> 0 Then sqlite3_free(CPtr(Any Ptr, parameterArray))
            Return 0
        End If
#ifndef SQLITE_OMIT_WAL
        zWalName = pagerStringWithSuffix(zDatabase, StrPtr("-wal"))
        If zWalName = 0 Then
            sqlite3_free(CPtr(Any Ptr, zJournalName))
            If parameterArray <> 0 Then sqlite3_free(CPtr(Any Ptr, parameterArray))
            Return 0
        End If
#endif
    End If

    Dim zPacked As Const ZString Ptr = sqlite3_create_filename( _
        zDatabase, zJournalName, zWalName, parameterCount, parameterArray)
    If databaseLength > 0 Then
        sqlite3_free(CPtr(Any Ptr, zJournalName))
#ifndef SQLITE_OMIT_WAL
        sqlite3_free(CPtr(Any Ptr, zWalName))
#endif
    End If
    If parameterArray <> 0 Then sqlite3_free(CPtr(Any Ptr, parameterArray))
    If zPacked = 0 Then Return 0

    If databaseLength > 0 Then
        ppJournal[0] = CPtr(ZString Ptr, sqlite3_filename_journal(zPacked))
#ifndef SQLITE_OMIT_WAL
        ppWal[0] = CPtr(ZString Ptr, sqlite3_filename_wal(zPacked))
#endif
    End If
    Return CPtr(ZString Ptr, zPacked)
End Function

Private Function pagerPageGetNormal( _
    ByVal pPager As Pager Ptr, _
    ByVal pageNumber As u32, _
    ByVal ppPage As PgHdr Ptr Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT

    If pPager = 0 OrElse ppPage = 0 Then Return SQLITE_MISUSE
    ppPage[0] = 0
    If pageNumber = 0 Then Return SQLITE_CORRUPT
    If pPager->errCode <> SQLITE_OK Then Return pPager->errCode
    If pPager->eState < PAGER_READER Then
        Dim rcLock As SQLITE_C_INT = sqlite3PagerSharedLock(pPager)
        If rcLock <> SQLITE_OK Then Return rcLock
    End If

    Dim pBase As sqlite3_pcache_page Ptr = sqlite3PcacheFetch(pPager->pPCache, pageNumber, 3)
    If pBase = 0 Then
        Dim rcStress As SQLITE_C_INT = sqlite3PcacheFetchStress(pPager->pPCache, pageNumber, @pBase)
        If rcStress <> SQLITE_OK Then Return rcStress
        If pBase = 0 Then Return SQLITE_NOMEM
    End If

    Dim pPage As PgHdr Ptr = sqlite3PcacheFetchFinish(pPager->pPCache, pageNumber, pBase)
    If pPage = 0 Then Return SQLITE_CORRUPT
    ppPage[0] = pPage
    If pPage->pPager <> 0 AndAlso (flags And PAGER_GET_NOCONTENT) = 0 Then
        pPager->aStat(PAGER_STAT_HIT) += 1
        Return SQLITE_OK
    End If

    If pageNumber = pPager->lckPgno Then GoTo pager_get_error_corrupt
    If pageNumber > pPager->mxPgno Then GoTo pager_get_error_full
    pPage->pPager = pPager
    pPager->aStat(PAGER_STAT_MISS) += 1

    If pPager->fd = 0 OrElse pPager->fd->pMethods = 0 OrElse _
       pageNumber > pPager->dbSize OrElse (flags And PAGER_GET_NOCONTENT) <> 0 Then
        Dim pData As UByte Ptr = CPtr(UByte Ptr, pPage->pData)
        For i As sqlite3_int64 = 0 To pPager->pageSize - 1
            pData[i] = 0
        Next
    Else
        Dim rcRead As SQLITE_C_INT = readDbPage(pPage)
        If rcRead <> SQLITE_OK Then
            sqlite3PcacheDrop(pPage)
            ppPage[0] = 0
            pagerUnlockIfUnused(pPager)
            Return rcRead
        End If
    End If
    Return SQLITE_OK

pager_get_error_corrupt:
    sqlite3PcacheDrop(pPage)
    ppPage[0] = 0
    pagerUnlockIfUnused(pPager)
    Return SQLITE_CORRUPT

pager_get_error_full:
    sqlite3PcacheDrop(pPage)
    ppPage[0] = 0
    pagerUnlockIfUnused(pPager)
    Return SQLITE_FULL
End Function

Private Function pagerAcquireMapPage CDecl Alias "pagerAcquireMapPage" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pageNumber As u32, _
    ByVal pData As Any Ptr, _
    ByVal ppPage As PgHdr Ptr Ptr _
) As SQLITE_C_INT
    If ppPage = 0 Then Return SQLITE_MISUSE
    ppPage[0] = 0
    If pPager = 0 OrElse pData = 0 OrElse pageNumber = 0 Then Return SQLITE_MISUSE
    If pPager->nExtra < 8 Then
        sqlite3OsUnfetch(pPager->fd, _
            (CLngInt(pageNumber) - 1) * pPager->pageSize, pData)
        Return SQLITE_CORRUPT
    End If

    Dim pPage As PgHdr Ptr = CPtr(PgHdr Ptr, pPager->pMmapFreelist)
    If pPage <> 0 Then
        pPager->pMmapFreelist = pPage->pDirty
        pPage->pDirty = 0
        Dim pExtraBytes As UByte Ptr = CPtr(UByte Ptr, pPage->pExtra)
        For i As Long = 0 To 7
            pExtraBytes[i] = 0
        Next
    Else
        Dim allocationBytes As sqlite3_uint64 = _
            CULngInt(SizeOf(PgHdr)) + CULngInt(pPager->nExtra)
        If allocationBytes > SQLITE_MAX_ALLOCATION_SIZE Then
            sqlite3OsUnfetch(pPager->fd, _
                (CLngInt(pageNumber) - 1) * pPager->pageSize, pData)
            Return SQLITE_TOOBIG
        End If
        pPage = CPtr(PgHdr Ptr, sqlite3MallocZero(allocationBytes))
        If pPage = 0 Then
            sqlite3OsUnfetch(pPager->fd, _
                (CLngInt(pageNumber) - 1) * pPager->pageSize, pData)
            Return SQLITE_NOMEM
        End If
        pPage->pExtra = CPtr(UByte Ptr, pPage) + SizeOf(PgHdr)
        pPage->flags = PGHDR_MMAP
        pPage->nRef = 1
        pPage->pPager = pPager
    End If

    pPage->pPage = 0
    pPage->pCache = 0
    pPage->flags = PGHDR_MMAP
    pPage->nRef = 1
    pPage->pPager = pPager
    pPage->pgno = pageNumber
    pPage->pData = pData
    pPager->nMmapOut += 1
    ppPage[0] = pPage
    Return SQLITE_OK
End Function

Private Sub pagerReleaseMapPage CDecl Alias "pagerReleaseMapPage" ( _
    ByVal pPage As PgHdr Ptr _
)
    If pPage = 0 Then Exit Sub
    Dim pPager As Pager Ptr = CPtr(Pager Ptr, pPage->pPager)
    If pPager = 0 Then Exit Sub

    If pPager->nMmapOut > 0 Then pPager->nMmapOut -= 1
    pPage->pDirty = pPager->pMmapFreelist
    pPager->pMmapFreelist = pPage
    Dim fileOffset As sqlite3_int64 = _
        (CLngInt(pPage->pgno) - 1) * pPager->pageSize
    sqlite3OsUnfetch(pPager->fd, fileOffset, pPage->pData)
End Sub

Function getPageMMap CDecl Alias "getPageMMap" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pageNumber As u32, _
    ByVal ppPage As PgHdr Ptr Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT
    If pPager = 0 OrElse ppPage = 0 Then Return SQLITE_MISUSE
    ppPage[0] = 0
    If pageNumber = 0 Then Return SQLITE_CORRUPT
    If pPager->errCode <> SQLITE_OK Then Return pPager->errCode
    If pPager->bUseFetch = 0 OrElse pPager->eState < PAGER_READER Then _
        Return pagerPageGetNormal(pPager, pageNumber, ppPage, flags)

#if SQLITE_MAX_MMAP_SIZE > 0
    Dim mmapAllowed As SQLITE_C_INT = CInt( _
        pageNumber > 1 AndAlso _
        (pPager->eState = PAGER_READER OrElse (flags And PAGER_GET_READONLY) <> 0))
    Dim frameIndex As u32 = 0
    Dim rc As SQLITE_C_INT = SQLITE_OK
#ifndef SQLITE_OMIT_WAL
    If mmapAllowed <> 0 AndAlso pPager->pWal <> 0 Then
        rc = sqlite3WalFindFrame(pPager->pWal, pageNumber, @frameIndex)
        If rc <> SQLITE_OK Then Return rc
    End If
#endif

    If mmapAllowed <> 0 AndAlso frameIndex = 0 Then
        Dim fileOffset As sqlite3_int64 = _
            (CLngInt(pageNumber) - 1) * pPager->pageSize
        Dim pData As Any Ptr = 0
        rc = sqlite3OsFetch(pPager->fd, fileOffset, CInt(pPager->pageSize), @pData)
        If rc <> SQLITE_OK Then Return rc
        If pData <> 0 Then
            Dim pPage As PgHdr Ptr = 0
            If pPager->eState > PAGER_READER OrElse pPager->tempFile <> 0 Then _
                pPage = sqlite3PagerLookup(pPager, pageNumber)
            If pPage = 0 Then
                rc = pagerAcquireMapPage(pPager, pageNumber, pData, @pPage)
                If rc <> SQLITE_OK Then Return rc
            Else
                sqlite3OsUnfetch(pPager->fd, fileOffset, pData)
            End If
            If pPage <> 0 Then
                ppPage[0] = pPage
                Return SQLITE_OK
            End If
        End If
    End If
#endif
    Return pagerPageGetNormal(pPager, pageNumber, ppPage, flags)
End Function

Private Function pagerPageGetError( _
    ByVal pPager As Pager Ptr, _
    ByVal pageNumber As u32, _
    ByVal ppPage As PgHdr Ptr Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT

    If ppPage <> 0 Then ppPage[0] = 0
    If pPager = 0 Then Return SQLITE_MISUSE
    Return pPager->errCode
End Function

Private Sub pagerSetGetterMethod(ByVal pPager As Pager Ptr)
    If pPager <> 0 Then setGetterMethod(pPager)
End Sub

Private Sub pagerUnlockIfUnused(ByVal pPager As Pager Ptr)
    If pPager = 0 OrElse pPager->pPCache = 0 Then Exit Sub
    If pPager->nMmapOut <> 0 Then Exit Sub
    If sqlite3PcacheRefCount(pPager->pPCache) <> 0 Then Exit Sub

    ' Releasing the final page also closes any pager transaction. In WAL mode
    ' this must drop the read mark as well as the database-file lock.
    pagerUnlockAndRollbackBridge(pPager)
End Sub

Private Function pagerTryBusyLock(ByVal pPager As Pager Ptr, ByVal lockLevel As SQLITE_C_INT) As SQLITE_C_INT
    If pPager->noLock <> 0 OrElse pPager->eLock >= lockLevel Then Return SQLITE_OK
    Dim rc As SQLITE_C_INT
    Dim nAttempt As SQLITE_C_INT = 0
    Do
        rc = sqlite3OsLock(pPager->fd, lockLevel)
        If rc <> SQLITE_BUSY OrElse pPager->xBusyHandler = 0 Then Exit Do
        Dim xBusy As SqlitePagerBusyProc = CPtr(SqlitePagerBusyProc, pPager->xBusyHandler)
        If xBusy(pPager->pBusyHandlerArg) = 0 Then Exit Do
        nAttempt += 1
        If nAttempt = &H7FFFFFFF Then Exit Do
    Loop
    If rc = SQLITE_OK Then pPager->eLock = lockLevel
    Return rc
End Function

Private Function pagerUnlockDb CDecl Alias "pagerUnlockDb" ( _
    ByVal pPager As Pager Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT
    If pPager = 0 OrElse (lockLevel <> NO_LOCK AndAlso lockLevel <> SHARED_LOCK) Then _
        Return SQLITE_MISUSE

    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim pFile As sqlite3_file Ptr = pPager->fd
    If pFile <> 0 AndAlso pFile->pMethods <> 0 Then
        If pPager->noLock = 0 Then rc = sqlite3OsUnlock(pFile, lockLevel)
        If pPager->eLock <> UNKNOWN_LOCK Then pPager->eLock = CByte(lockLevel)
    End If

    pPager->changeCountDone = pPager->tempFile
    Return rc
End Function

Private Function pagerLockDb CDecl Alias "pagerLockDb" ( _
    ByVal pPager As Pager Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT
    If pPager = 0 OrElse _
       (lockLevel <> SHARED_LOCK AndAlso lockLevel <> RESERVED_LOCK AndAlso _
        lockLevel <> EXCLUSIVE_LOCK) Then Return SQLITE_MISUSE

    If pPager->eLock < lockLevel OrElse pPager->eLock = UNKNOWN_LOCK Then
        Dim rc As SQLITE_C_INT = SQLITE_OK
        If pPager->noLock = 0 Then
            If pPager->fd = 0 OrElse pPager->fd->pMethods = 0 Then Return SQLITE_MISUSE
            rc = sqlite3OsLock(pPager->fd, lockLevel)
        End If
        If rc = SQLITE_OK AndAlso _
           (pPager->eLock <> UNKNOWN_LOCK OrElse lockLevel = EXCLUSIVE_LOCK) Then
            pPager->eLock = CByte(lockLevel)
        End If
        Return rc
    End If

    Return SQLITE_OK
End Function

Private Function pager_wait_on_lock CDecl Alias "pager_wait_on_lock" ( _
    ByVal pPager As Pager Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT
    If pPager = 0 Then Return SQLITE_MISUSE

    Dim rc As SQLITE_C_INT
    Dim xBusy As SqlitePagerBusyProc
    Do
        rc = pagerLockDb(pPager, lockLevel)
        If rc <> SQLITE_BUSY OrElse pPager->xBusyHandler = 0 Then Exit Do
        xBusy = CPtr(SqlitePagerBusyProc, pPager->xBusyHandler)
        If xBusy(pPager->pBusyHandlerArg) = 0 Then Exit Do
    Loop

    Return rc
End Function

Private Sub pagerPutU32(ByVal pOutput As UByte Ptr, ByVal value As u32)
    If pOutput = 0 Then Exit Sub
    pOutput[0] = CByte((value Shr 24) And &HFF)
    pOutput[1] = CByte((value Shr 16) And &HFF)
    pOutput[2] = CByte((value Shr 8) And &HFF)
    pOutput[3] = CByte(value And &HFF)
End Sub

Private Function pagerWriteJournalU32 CDecl Alias "write32bits" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal offset As sqlite3_int64, _
    ByVal value As u32 _
) As SQLITE_C_INT

    Dim bytes(0 To 3) As UByte
    pagerPutU32(@bytes(0), value)
    Return sqlite3OsWrite(pFile, @bytes(0), 4, offset)
End Function

Private Function writeJournalHdr CDecl Alias "writeJournalHdr" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
    If pPager = 0 OrElse pPager->jfd = 0 OrElse pPager->jfd->pMethods = 0 OrElse _
       pPager->pTmpSpace = 0 OrElse pPager->pageSize < 28 OrElse _
       pPager->sectorSize < 28 Then Return SQLITE_MISUSE
    If pPager->nSavepoint > 0 AndAlso pPager->aSavepoint = 0 Then Return SQLITE_CORRUPT

    ' Savepoints created since the last header begin at this journal position.
    For savepointIndex As SQLITE_C_INT = 0 To pPager->nSavepoint - 1
        If pPager->aSavepoint[savepointIndex].iHdrOffset = 0 Then _
            pPager->aSavepoint[savepointIndex].iHdrOffset = pPager->journalOff
    Next

    Dim sectorSize As sqlite3_int64 = pPager->sectorSize
    Dim pageSize As sqlite3_int64 = pPager->pageSize
    Dim headerSize As sqlite3_int64 = pageSize
    If headerSize > sectorSize Then headerSize = sectorSize
    If headerSize < 28 OrElse headerSize > pageSize Then Return SQLITE_MISUSE

    Dim headerOffset As sqlite3_int64 = 0
    If pPager->journalOff <> 0 Then
        headerOffset = ((pPager->journalOff - 1) \ sectorSize + 1) * sectorSize
    End If
    pPager->journalHdr = headerOffset
    pPager->journalOff = headerOffset

    Dim allRecordsValid As SQLITE_C_INT = 0
    If pPager->noSync <> 0 OrElse _
       pPager->journalMode = PAGER_JOURNALMODE_MEMORY Then
        allRecordsValid = 1
    Else
        If pPager->fd = 0 OrElse pPager->fd->pMethods = 0 Then Return SQLITE_MISUSE
        Dim deviceCharacteristics As SQLITE_C_INT = _
            sqlite3OsDeviceCharacteristics(pPager->fd)
        If (deviceCharacteristics And SQLITE_IOCAP_SAFE_APPEND) <> 0 Then _
            allRecordsValid = 1
    End If

    If allRecordsValid <> 0 Then
        For byteIndex As SQLITE_C_INT = 0 To 7
            pPager->pTmpSpace[byteIndex] = pagerJournalMagicByte(byteIndex)
        Next
        pagerPutU32(pPager->pTmpSpace + 8, &HFFFFFFFF)
    Else
        For byteIndex As SQLITE_C_INT = 0 To 11
            pPager->pTmpSpace[byteIndex] = 0
        Next
    End If

    ' In-memory journals start empty, so randomizing their checksum seed is needless.
    If pPager->journalMode <> PAGER_JOURNALMODE_MEMORY Then
        sqlite3_randomness(SizeOf(pPager->cksumInit), @pPager->cksumInit)
    End If
    pagerPutU32(pPager->pTmpSpace + 12, pPager->cksumInit)
    pagerPutU32(pPager->pTmpSpace + 16, pPager->dbOrigSize)
    pagerPutU32(pPager->pTmpSpace + 20, pPager->sectorSize)
    pagerPutU32(pPager->pTmpSpace + 24, CUInt(pPager->pageSize))
    For byteIndex As sqlite3_int64 = 28 To headerSize - 1
        pPager->pTmpSpace[byteIndex] = 0
    Next

    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim bytesWritten As sqlite3_int64 = 0
    While rc = SQLITE_OK AndAlso bytesWritten < sectorSize
        rc = sqlite3OsWrite( _
            pPager->jfd, pPager->pTmpSpace, CLng(headerSize), pPager->journalOff)
        pPager->journalOff += headerSize
        bytesWritten += headerSize
    Wend
    Return rc
End Function

Private Function pagerJournalBufferSize(ByVal pPager As Pager Ptr) As SQLITE_C_INT
#if defined(SQLITE_ENABLE_ATOMIC_WRITE) OrElse defined(SQLITE_ENABLE_BATCH_ATOMIC_WRITE)
    If pPager = 0 OrElse pPager->fd = 0 OrElse pPager->fd->pMethods = 0 Then Return 0
    Dim deviceCharacteristics As SQLITE_C_INT = _
        sqlite3OsDeviceCharacteristics(pPager->fd)
#else
    Return 0
#endif

#ifdef SQLITE_ENABLE_BATCH_ATOMIC_WRITE
    If pPager->dbSize > 0 AndAlso _
       (deviceCharacteristics And SQLITE_IOCAP_BATCH_ATOMIC) <> 0 Then Return -1
#endif

#ifdef SQLITE_ENABLE_ATOMIC_WRITE
    Dim pageSize As SQLITE_C_INT = pPager->pageSize
    Dim sectorSize As SQLITE_C_INT = pPager->sectorSize
    Dim atomicCapabilities As SQLITE_C_INT = _
        SQLITE_IOCAP_ATOMIC Or (pageSize Shr 8)
    If (deviceCharacteristics And atomicCapabilities) = 0 AndAlso _
       sectorSize <= pageSize Then Return 0
    Return sectorSize + pageSize + 8
#endif

    Return 0
End Function

Private Function pagerDatabaseIsUnmoved(ByVal pPager As Pager Ptr) As SQLITE_C_INT
    If pPager = 0 Then Return SQLITE_MISUSE
    If pPager->tempFile <> 0 OrElse pPager->dbSize = 0 Then Return SQLITE_OK
    If pPager->fd = 0 OrElse pPager->zFilename = 0 OrElse _
       pPager->zFilename[0] = 0 Then Return SQLITE_MISUSE

    Dim hasMoved As SQLITE_C_INT = 0
    Dim rc As SQLITE_C_INT = sqlite3OsFileControl( _
        pPager->fd, SQLITE_FCNTL_HAS_MOVED, @hasMoved)
    If rc = SQLITE_NOTFOUND Then Return SQLITE_OK
    If rc = SQLITE_OK AndAlso hasMoved <> 0 Then Return SQLITE_READONLY_DBMOVED
    Return rc
End Function

Function pager_open_journal CDecl Alias "pager_open_journal" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
    If pPager = 0 OrElse pPager->eState <> PAGER_WRITER_LOCKED Then Return SQLITE_MISUSE
    If pPager->errCode <> SQLITE_OK Then Return pPager->errCode
    If pPager->pInJournal <> 0 Then Return SQLITE_MISUSE

    Dim useWal As SQLITE_C_INT = 0
#ifndef SQLITE_OMIT_WAL
    If pPager->pWal <> 0 Then useWal = 1
#endif

    Dim rc As SQLITE_C_INT = SQLITE_OK
    If useWal = 0 AndAlso pPager->journalMode <> PAGER_JOURNALMODE_OFF Then
        pPager->pInJournal = sqlite3BitvecCreate(pPager->dbSize)
        If pPager->pInJournal = 0 Then Return SQLITE_NOMEM

        If pPager->jfd = 0 Then Return SQLITE_MISUSE
        If pPager->jfd->pMethods = 0 Then
            If pPager->journalMode = PAGER_JOURNALMODE_MEMORY Then
                sqlite3MemJournalOpen(pPager->jfd)
            Else
                Dim openFlags As SQLITE_C_INT = SQLITE_OPEN_READWRITE Or SQLITE_OPEN_CREATE
                Dim spillSize As SQLITE_C_INT
                If pPager->tempFile <> 0 Then
                    openFlags = openFlags Or SQLITE_OPEN_DELETEONCLOSE Or _
                        SQLITE_OPEN_TEMP_JOURNAL Or SQLITE_OPEN_EXCLUSIVE
                    spillSize = pagerStmtJournalSpillLimit()
                Else
                    openFlags = openFlags Or SQLITE_OPEN_MAIN_JOURNAL
                    spillSize = pagerJournalBufferSize(pPager)
                End If

                rc = pagerDatabaseIsUnmoved(pPager)
                If rc = SQLITE_OK Then
                    rc = sqlite3JournalOpen( _
                        pPager->pVfs, pPager->zJournal, pPager->jfd, _
                        openFlags, spillSize)
                End If
            End If
        End If

        If rc = SQLITE_OK Then
            pPager->nRec = 0
            pPager->journalOff = 0
            pPager->setSuper = 0
            pPager->journalHdr = 0
            rc = writeJournalHdr(pPager)
        End If
    End If

    If rc <> SQLITE_OK Then
        sqlite3BitvecDestroy(pPager->pInJournal)
        pPager->pInJournal = 0
        pPager->journalOff = 0
    Else
        pPager->eState = PAGER_WRITER_CACHEMOD
    End If
    Return rc
End Function

Private Function pagerAddPageToRollbackJournal(ByVal pPage As PgHdr Ptr) As SQLITE_C_INT
    If pPage = 0 OrElse pPage->pPager = 0 Then Return SQLITE_MISUSE
    Dim pPager As Pager Ptr = CPtr(Pager Ptr, pPage->pPager)
    If pPager->pInJournal = 0 OrElse pPage->pgno > pPager->dbOrigSize Then Return SQLITE_OK
    Dim pInJournal As Any Ptr = pPager->pInJournal
    If sqlite3BitvecTest(pInJournal, pPage->pgno) <> 0 Then Return SQLITE_OK
    If pPager->jfd = 0 OrElse pPager->jfd->pMethods = 0 Then Return SQLITE_IOERR_WRITE

    pPage->flags = pPage->flags Or PGHDR_NEED_SYNC
    Dim recordOffset As sqlite3_int64 = pPager->journalOff
    Dim rc As SQLITE_C_INT = pagerWriteJournalU32(pPager->jfd, recordOffset, pPage->pgno)
    If rc <> SQLITE_OK Then Return rc
    rc = sqlite3OsWrite(pPager->jfd, pPage->pData, CLng(pPager->pageSize), recordOffset + 4)
    If rc <> SQLITE_OK Then Return rc
    Dim checksum As u32 = pager_cksum(pPager, CPtr(Const UByte Ptr, pPage->pData))
    rc = pagerWriteJournalU32(pPager->jfd, recordOffset + pPager->pageSize + 4, checksum)
    If rc <> SQLITE_OK Then Return rc

    pPager->journalOff += pPager->pageSize + 8
    pPager->nRec += 1
    rc = sqlite3BitvecSet(pInJournal, pPage->pgno)
    If rc = SQLITE_OK Then rc = pagerAddToSavepointBitvecs(pPager, pPage->pgno)
    Return rc
End Function

Private Function pagerAddToSavepointBitvecs CDecl Alias "addToSavepointBitvecs" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pageNumber As u32 _
) As SQLITE_C_INT
    If pPager = 0 OrElse pPager->nSavepoint = 0 Then Return SQLITE_OK
    If pPager->aSavepoint = 0 Then Return SQLITE_CORRUPT
    Dim rc As SQLITE_C_INT = SQLITE_OK
    For i As Long = 0 To pPager->nSavepoint - 1
        Dim pSavepoint As PagerSavepoint Ptr = @pPager->aSavepoint[i]
        If pageNumber <= pSavepoint->nOrig Then
            rc = rc Or sqlite3BitvecSet(pSavepoint->pInSavepoint, pageNumber)
        End If
    Next
    Return rc
End Function

Function openSubJournal CDecl Alias "openSubJournal" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
    If pPager = 0 OrElse pPager->sjfd = 0 Then Return SQLITE_MISUSE
    If pPager->sjfd->pMethods <> 0 Then Return SQLITE_OK

    Dim openFlags As SQLITE_C_INT = _
        SQLITE_OPEN_SUBJOURNAL Or SQLITE_OPEN_READWRITE Or SQLITE_OPEN_CREATE Or _
        SQLITE_OPEN_EXCLUSIVE Or SQLITE_OPEN_DELETEONCLOSE
    Dim spillSize As SQLITE_C_INT = pagerStmtJournalSpillLimit()
    If pPager->journalMode = PAGER_JOURNALMODE_MEMORY OrElse _
       pPager->subjInMemory <> 0 Then spillSize = -1
    Return sqlite3JournalOpen(pPager->pVfs, 0, pPager->sjfd, openFlags, spillSize)
End Function

Private Function subjRequiresPage CDecl Alias "subjRequiresPage" ( _
    ByVal pPage As PgHdr Ptr _
) As SQLITE_C_INT
    If pPage = 0 OrElse pPage->pPager = 0 Then Return 0
    Dim pPager As Pager Ptr = CPtr(Pager Ptr, pPage->pPager)
    If pPager->nSavepoint <= 0 OrElse pPager->aSavepoint = 0 Then Return 0
    For i As SQLITE_C_INT = 0 To pPager->nSavepoint - 1
        Dim pSavepoint As PagerSavepoint Ptr = @pPager->aSavepoint[i]
        If pSavepoint->nOrig >= pPage->pgno AndAlso _
           sqlite3BitvecTestNotNull(pSavepoint->pInSavepoint, pPage->pgno) = 0 Then
            For laterSavepoint As SQLITE_C_INT = i + 1 To pPager->nSavepoint - 1
                pPager->aSavepoint[laterSavepoint].bTruncateOnRelease = 0
            Next
            Return 1
        End If
    Next
    Return 0
End Function

Private Function pagerSubjournalPage CDecl Alias "subjournalPage" ( _
    ByVal pPage As PgHdr Ptr _
) As SQLITE_C_INT
    If pPage = 0 OrElse pPage->pPager = 0 Then Return SQLITE_MISUSE
    Dim pPager As Pager Ptr = CPtr(Pager Ptr, pPage->pPager)
    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pPager->journalMode <> PAGER_JOURNALMODE_OFF Then
        If pPager->useJournal = 0 Then Return SQLITE_MISUSE
        rc = openSubJournal(pPager)
        If rc = SQLITE_OK Then
            If pPage->pData = 0 OrElse pPager->pageSize = 0 Then Return SQLITE_CORRUPT
            Dim offset As sqlite3_int64 = CLngInt(pPager->nSubRec) * (4 + pPager->pageSize)
            rc = pagerWriteJournalU32(pPager->sjfd, offset, pPage->pgno)
            If rc = SQLITE_OK Then
                rc = sqlite3OsWrite(pPager->sjfd, pPage->pData, CLng(pPager->pageSize), offset + 4)
            End If
        End If
    End If
    If rc = SQLITE_OK Then
        ' Savepoint record numbering advances even when journaling mode skips
        ' the physical write, so later savepoint offsets remain consistent.
        pPager->nSubRec += 1
        rc = pagerAddToSavepointBitvecs(pPager, pPage->pgno)
    End If
    Return rc
End Function

Private Function pagerSubjournalPageIfRequired CDecl Alias "subjournalPageIfRequired" ( _
    ByVal pPage As PgHdr Ptr _
) As SQLITE_C_INT
    If pPage = 0 OrElse pPage->pPager = 0 Then Return SQLITE_MISUSE
    If subjRequiresPage(pPage) = 0 Then Return SQLITE_OK
    Return pagerSubjournalPage(pPage)
End Function

Private Function pagerSyncJournal CDecl Alias "syncJournal" ( _
    ByVal pPager As Pager Ptr, _
    ByVal startNewHeader As SQLITE_C_INT _
) As SQLITE_C_INT
    If pPager = 0 OrElse pPager->sectorSize = 0 Then Return SQLITE_MISUSE
    If pPager->eState <> PAGER_WRITER_CACHEMOD AndAlso _
       pPager->eState <> PAGER_WRITER_DBMOD Then Return SQLITE_MISUSE
#ifndef SQLITE_OMIT_WAL
    If pPager->pWal <> 0 Then Return SQLITE_MISUSE
#endif

    Dim rc As SQLITE_C_INT = pagerTryBusyLock(pPager, EXCLUSIVE_LOCK)
    If rc <> SQLITE_OK Then Return rc

    If pPager->noSync = 0 Then
        If pPager->jfd <> 0 AndAlso pPager->jfd->pMethods <> 0 AndAlso _
           pPager->journalMode <> PAGER_JOURNALMODE_MEMORY Then
            If pPager->fd = 0 OrElse pPager->fd->pMethods = 0 Then Return SQLITE_MISUSE
            Dim deviceCharacteristics As SQLITE_C_INT = _
                sqlite3OsDeviceCharacteristics(pPager->fd)
            Dim safeAppend As SQLITE_C_INT = _
                IIf((deviceCharacteristics And SQLITE_IOCAP_SAFE_APPEND) <> 0, 1, 0)
            Dim sequentialWrites As SQLITE_C_INT = _
                IIf((deviceCharacteristics And SQLITE_IOCAP_SEQUENTIAL) <> 0, 1, 0)

            If safeAppend = 0 Then
                Dim nextHeaderOffset As sqlite3_int64 = 0
                If pPager->journalOff <> 0 Then
                    nextHeaderOffset = _
                        ((pPager->journalOff - 1) \ pPager->sectorSize + 1) * pPager->sectorSize
                End If

                Dim nextMagic(0 To 7) As UByte
                rc = sqlite3OsRead(pPager->jfd, @nextMagic(0), 8, nextHeaderOffset)
                If rc = SQLITE_OK Then
                    Dim matchesMagic As SQLITE_C_INT = 1
                    For byteIndex As SQLITE_C_INT = 0 To 7
                        If nextMagic(byteIndex) <> pagerJournalMagicByte(byteIndex) Then
                            matchesMagic = 0
                            Exit For
                        End If
                    Next
                    If matchesMagic <> 0 Then
                        Dim zeroByte As UByte = 0
                        rc = sqlite3OsWrite(pPager->jfd, @zeroByte, 1, nextHeaderOffset)
                    End If
                End If
                If rc <> SQLITE_OK AndAlso rc <> SQLITE_IOERR_SHORT_READ Then Return rc

                If pPager->fullSync <> 0 AndAlso sequentialWrites = 0 Then
                    rc = sqlite3OsSync(pPager->jfd, pPager->syncFlags)
                    If rc <> SQLITE_OK Then Return rc
                End If

                Dim recordHeader(0 To 11) As UByte
                For byteIndex As SQLITE_C_INT = 0 To 7
                    recordHeader(byteIndex) = pagerJournalMagicByte(byteIndex)
                Next
                pagerPutU32(@recordHeader(8), pPager->nRec)
                rc = sqlite3OsWrite( _
                    pPager->jfd, @recordHeader(0), 12, pPager->journalHdr)
                If rc <> SQLITE_OK Then Return rc
            End If

            If sequentialWrites = 0 Then
                Dim journalSyncFlags As SQLITE_C_INT = pPager->syncFlags
                If pPager->syncFlags = SQLITE_SYNC_FULL Then _
                    journalSyncFlags = journalSyncFlags Or SQLITE_SYNC_DATAONLY
                rc = sqlite3OsSync(pPager->jfd, journalSyncFlags)
                If rc <> SQLITE_OK Then Return rc
            End If

            pPager->journalHdr = pPager->journalOff
            If startNewHeader <> 0 AndAlso safeAppend = 0 Then
                pPager->nRec = 0
                rc = writeJournalHdr(pPager)
                If rc <> SQLITE_OK Then Return rc
            End If
        Else
            pPager->journalHdr = pPager->journalOff
        End If
    End If

    sqlite3PcacheClearSyncFlags(pPager->pPCache)
    pPager->eState = PAGER_WRITER_DBMOD
    Return SQLITE_OK
End Function

Function sqlite3PagerBegin CDecl Alias "sqlite3PagerBegin" ( _
    ByVal pPager As Pager Ptr, _
    ByVal exclusiveFlag As SQLITE_C_INT, _
    ByVal subjournalInMemory As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pPager = 0 Then Return SQLITE_MISUSE
    If pPager->errCode <> SQLITE_OK Then Return pPager->errCode
    If pPager->readOnly <> 0 Then Return SQLITE_READONLY
    If pPager->eState >= PAGER_WRITER_LOCKED Then Return SQLITE_OK
    If pPager->eState < PAGER_READER Then
        Dim rcRead As SQLITE_C_INT = sqlite3PagerSharedLock(pPager)
        If rcRead <> SQLITE_OK Then Return rcRead
    End If

    pPager->subjInMemory = IIf(subjournalInMemory <> 0, 1, 0)

#ifndef SQLITE_OMIT_WAL
    If pPager->pWal <> 0 Then
        ' WAL writers lock the log; database-file RESERVED locks are for rollback mode.
        If pPager->exclusiveMode <> 0 AndAlso _
           sqlite3WalExclusiveMode(pPager->pWal, -1) <> 0 Then
            Dim rcExclusive As SQLITE_C_INT = pagerLockDb(pPager, EXCLUSIVE_LOCK)
            If rcExclusive <> SQLITE_OK Then Return rcExclusive
            sqlite3WalExclusiveMode(pPager->pWal, 1)
        End If

        Dim rcWalLock As SQLITE_C_INT = _
            sqlite3WalBeginWriteTransaction(pPager->pWal)
        If rcWalLock <> SQLITE_OK Then Return rcWalLock
    Else
#endif
        If pPager->noLock = 0 AndAlso pPager->eLock < RESERVED_LOCK Then
            Dim rcLock As SQLITE_C_INT = sqlite3OsLock(pPager->fd, RESERVED_LOCK)
            If rcLock <> SQLITE_OK Then Return rcLock
            pPager->eLock = RESERVED_LOCK
        End If
        If exclusiveFlag <> 0 Then
            Dim rcExclusive As SQLITE_C_INT = pagerTryBusyLock(pPager, EXCLUSIVE_LOCK)
            If rcExclusive <> SQLITE_OK Then Return rcExclusive
        End If
#ifndef SQLITE_OMIT_WAL
    End If
#endif

    pPager->eState = PAGER_WRITER_LOCKED
    pPager->dbHintSize = pPager->dbSize
    pPager->dbFileSize = pPager->dbSize
    pPager->dbOrigSize = pPager->dbSize
    pPager->journalOff = 0
    pPager->journalHdr = 0
    pPager->nRec = 0
    pPager->setSuper = 0
    Return SQLITE_OK
End Function

Private Function pagerWriteLargeSector(ByVal pPage As PgHdr Ptr) As SQLITE_C_INT
    If pPage = 0 OrElse pPage->pPager = 0 Then Return SQLITE_MISUSE
    If pPage->pgno = 0 Then Return SQLITE_CORRUPT
    Dim pPager As Pager Ptr = CPtr(Pager Ptr, pPage->pPager)
    If pPager->sectorSize <= pPager->pageSize OrElse pPager->tempFile <> 0 Then Return SQLITE_MISUSE
    Dim pagesPerSector As u32 = CULng(pPager->sectorSize) \ CULng(pPager->pageSize)
    If pagesPerSector = 0 Then Return SQLITE_MISUSE
    If (pPager->doNotSpill And SPILLFLAG_NOSYNC) <> 0 Then Return SQLITE_MISUSE

    ' Keep the journal records for a sector together. A cache spill must not
    ' write another journal header between pages that can be damaged together.
    Dim savedDoNotSpill As u8 = pPager->doNotSpill
    pPager->doNotSpill = pPager->doNotSpill Or SPILLFLAG_NOSYNC

    Dim firstPage As u32 = ((pPage->pgno - 1) \ pagesPerSector) * pagesPerSector + 1
    Dim pageCount As u32 = 0
    Dim databasePageCount As u32 = pPager->dbSize
    If pPage->pgno > databasePageCount Then
        pageCount = pPage->pgno - firstPage + 1
    ElseIf CULngInt(firstPage) + pagesPerSector - 1 > databasePageCount Then
        pageCount = databasePageCount + 1 - firstPage
    Else
        pageCount = pagesPerSector
    End If
    If pageCount = 0 Then
        pPager->doNotSpill = savedDoNotSpill
        Return SQLITE_CORRUPT
    End If

    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim needSync As SQLITE_C_INT = 0
    For pageIndex As u32 = 0 To pageCount - 1
        Dim sectorPage As u32 = firstPage + pageIndex
        Dim isTarget As SQLITE_C_INT = IIf(sectorPage = pPage->pgno, 1, 0)
        Dim isJournaled As SQLITE_C_INT = 0
        If pPager->pInJournal <> 0 Then
            isJournaled = sqlite3BitvecTest(pPager->pInJournal, sectorPage)
        End If

        If isTarget <> 0 OrElse isJournaled = 0 Then
            ' The locking page can share a sector with database pages, but it
            ' is reserved for file locks and must never be read as page data.
            If sectorPage <> pPager->lckPgno Then
                Dim pSectorPage As PgHdr Ptr = 0
                If sectorPage = pPage->pgno Then
                    pSectorPage = pPage
                Else
                    rc = sqlite3PagerGet(pPager, sectorPage, @pSectorPage, 0)
                    If rc <> SQLITE_OK Then Exit For
                End If

                If pPager->eState = PAGER_WRITER_LOCKED Then
                    rc = pager_open_journal(pPager)
                End If
                If rc = SQLITE_OK Then
                    sqlite3PcacheMakeDirty(pSectorPage)
                    If pPager->pInJournal <> 0 AndAlso _
                       sqlite3BitvecTest(pPager->pInJournal, pSectorPage->pgno) = 0 Then
                        If pSectorPage->pgno <= pPager->dbOrigSize Then
                            rc = pagerAddPageToRollbackJournal(pSectorPage)
                        ElseIf pPager->eState <> PAGER_WRITER_DBMOD Then
                            pSectorPage->flags = pSectorPage->flags Or PGHDR_NEED_SYNC
                        End If
                    End If
                    If rc = SQLITE_OK Then
                        pSectorPage->flags = pSectorPage->flags Or PGHDR_WRITEABLE
                        rc = pagerSubjournalPageIfRequired(pSectorPage)
                        If pSectorPage->pgno > pPager->dbSize Then pPager->dbSize = pSectorPage->pgno
                    End If
                    If (pSectorPage->flags And PGHDR_NEED_SYNC) <> 0 Then needSync = 1
                End If
                If sectorPage <> pPage->pgno Then sqlite3PagerUnrefNotNull(pSectorPage)
                If rc <> SQLITE_OK Then Exit For
            End If
        Else
            Dim pSectorPage As PgHdr Ptr = sqlite3PagerLookup(pPager, sectorPage)
            If pSectorPage <> 0 Then
                If (pSectorPage->flags And PGHDR_NEED_SYNC) <> 0 Then needSync = 1
                sqlite3PagerUnrefNotNull(pSectorPage)
            End If
        End If
    Next

    If rc = SQLITE_OK AndAlso needSync <> 0 Then
        For pageIndex As u32 = 0 To pageCount - 1
            Dim pSectorPage As PgHdr Ptr = sqlite3PagerLookup(pPager, firstPage + pageIndex)
            If pSectorPage <> 0 Then
                pSectorPage->flags = pSectorPage->flags Or PGHDR_NEED_SYNC
                sqlite3PagerUnrefNotNull(pSectorPage)
            End If
        Next
    End If

    pPager->doNotSpill = savedDoNotSpill
    Return rc
End Function

Function sqlite3PagerWrite CDecl Alias "sqlite3PagerWrite" (ByVal pPage As PgHdr Ptr) As SQLITE_C_INT Export
    If pPage = 0 OrElse pPage->pPager = 0 Then Return SQLITE_MISUSE
    If pPage->pgno = 0 Then Return SQLITE_CORRUPT
    Dim pPager As Pager Ptr = CPtr(Pager Ptr, pPage->pPager)
    If (pPage->flags And PGHDR_WRITEABLE) <> 0 AndAlso pPager->dbSize >= pPage->pgno Then
        If pPager->nSavepoint > 0 Then Return pagerSubjournalPageIfRequired(pPage)
        Return SQLITE_OK
    End If
    If pPager->errCode <> SQLITE_OK Then Return pPager->errCode
    If pPager->readOnly <> 0 Then Return SQLITE_READONLY
    If pPager->eState < PAGER_WRITER_LOCKED OrElse pPager->eState > PAGER_WRITER_DBMOD Then Return SQLITE_MISUSE
    If pPager->sectorSize > CULng(pPager->pageSize) Then Return pagerWriteLargeSector(pPage)

    If pPager->eState = PAGER_WRITER_LOCKED Then
        Dim rcOpen As SQLITE_C_INT = pager_open_journal(pPager)
        If rcOpen <> SQLITE_OK Then Return rcOpen
    End If
    sqlite3PcacheMakeDirty(pPage)

    If pPager->pInJournal <> 0 Then
        If pPage->pgno <= pPager->dbOrigSize Then
            If sqlite3BitvecTest(pPager->pInJournal, pPage->pgno) = 0 Then
                Dim rcJournal As SQLITE_C_INT = pagerAddPageToRollbackJournal(pPage)
                If rcJournal <> SQLITE_OK Then Return rcJournal
            End If
        ElseIf pPager->eState <> PAGER_WRITER_DBMOD Then
            pPage->flags = pPage->flags Or PGHDR_NEED_SYNC
        End If
    End If

    pPage->flags = pPage->flags Or PGHDR_WRITEABLE
    If pPager->dbSize < pPage->pgno Then pPager->dbSize = pPage->pgno
    If pPager->nSavepoint > 0 Then Return pagerSubjournalPageIfRequired(pPage)
    Return SQLITE_OK
End Function

Function sqlite3PagerMovepage CDecl Alias "sqlite3PagerMovepage" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pPage As PgHdr Ptr, _
    ByVal newPageNumber As u32, _
    ByVal isCommit As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pPager = 0 OrElse pPage = 0 OrElse pPage->nRef <= 0 OrElse _
       pPage->pPager <> pPager OrElse newPageNumber = 0 OrElse _
       (isCommit <> 0 AndAlso isCommit <> 1) Then Return SQLITE_MISUSE
    If pPager->eState <> PAGER_WRITER_CACHEMOD AndAlso _
       pPager->eState <> PAGER_WRITER_DBMOD Then Return SQLITE_MISUSE
    If pPage->pgno = newPageNumber Then Return SQLITE_OK

    ' A memory-backed file has no rollback journal file, so force the pager's
    ' subjournal path to capture the source image before changing its key.
    If pPager->tempFile <> 0 Then
        Dim rcWrite As SQLITE_C_INT = sqlite3PagerWrite(pPage)
        If rcWrite <> SQLITE_OK Then Return rcWrite
    End If
    If (pPage->flags And PGHDR_DIRTY) <> 0 Then
        Dim rcSubjournal As SQLITE_C_INT = pagerSubjournalPageIfRequired(pPage)
        If rcSubjournal <> SQLITE_OK Then Return rcSubjournal
    End If

    Dim needSyncPageNumber As u32 = 0
    If (pPage->flags And PGHDR_NEED_SYNC) <> 0 AndAlso isCommit = 0 Then
        needSyncPageNumber = pPage->pgno
    End If

    pPage->flags = pPage->flags And Not PGHDR_NEED_SYNC
    Dim pOldPage As PgHdr Ptr = sqlite3PagerLookup(pPager, newPageNumber)
    If pOldPage <> 0 Then
        If pOldPage->nRef <> 1 Then
            sqlite3PagerUnrefNotNull(pOldPage)
            Return SQLITE_CORRUPT
        End If
        pPage->flags = pPage->flags Or (pOldPage->flags And PGHDR_NEED_SYNC)
        If pPager->tempFile <> 0 Then
            If pPager->dbSize = &HFFFFFFFF Then
                sqlite3PagerUnrefNotNull(pOldPage)
                Return SQLITE_FULL
            End If
            sqlite3PcacheMove(pOldPage, pPager->dbSize + 1)
            If pOldPage->pgno <> pPager->dbSize + 1 Then
                sqlite3PagerUnrefNotNull(pOldPage)
                Return SQLITE_CORRUPT
            End If
        Else
            sqlite3PcacheDrop(pOldPage)
            pOldPage = 0
        End If
    End If

    Dim originalPageNumber As u32 = pPage->pgno
    sqlite3PcacheMove(pPage, newPageNumber)
    If pPage->pgno <> newPageNumber Then
        If pOldPage <> 0 Then sqlite3PagerUnrefNotNull(pOldPage)
        Return SQLITE_CORRUPT
    End If
    sqlite3PcacheMakeDirty(pPage)

    If pPager->tempFile <> 0 AndAlso pOldPage <> 0 Then
        sqlite3PcacheMove(pOldPage, originalPageNumber)
        If pOldPage->pgno <> originalPageNumber Then
            sqlite3PagerUnrefNotNull(pOldPage)
            Return SQLITE_CORRUPT
        End If
        sqlite3PagerUnrefNotNull(pOldPage)
        pOldPage = 0
    End If
    If pOldPage <> 0 Then
        sqlite3PagerUnrefNotNull(pOldPage)
        pOldPage = 0
    End If

    If needSyncPageNumber <> 0 Then
        Dim pSyncPage As PgHdr Ptr = 0
        Dim rcSyncPage As SQLITE_C_INT = sqlite3PagerGet(pPager, needSyncPageNumber, @pSyncPage, 0)
        If rcSyncPage <> SQLITE_OK Then
            If needSyncPageNumber <= pPager->dbOrigSize AndAlso _
               pPager->pInJournal <> 0 AndAlso pPager->pTmpSpace <> 0 Then
                sqlite3BitvecClear(pPager->pInJournal, needSyncPageNumber, pPager->pTmpSpace)
            End If
            Return rcSyncPage
        End If
        pSyncPage->flags = pSyncPage->flags Or PGHDR_NEED_SYNC
        sqlite3PcacheMakeDirty(pSyncPage)
        sqlite3PagerUnrefNotNull(pSyncPage)
    End If

    Return SQLITE_OK
End Function

Sub sqlite3PagerTruncateImage CDecl Alias "sqlite3PagerTruncateImage" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pageCount As u32 _
) Export
    If pPager = 0 OrElse pageCount > pPager->dbSize OrElse _
       pPager->eState < PAGER_WRITER_CACHEMOD Then Return
    pPager->dbSize = pageCount
End Sub

Sub sqlite3PagerRekey CDecl Alias "sqlite3PagerRekey" ( _
    ByVal pPage As PgHdr Ptr, _
    ByVal newPageNumber As u32, _
    ByVal flags As u16 _
) Export

    If pPage = 0 OrElse pPage->pgno = newPageNumber OrElse newPageNumber = 0 Then Return
    pPage->flags = flags
    sqlite3PcacheMove(pPage, newPageNumber)
End Sub

Function sqlite3PagerOpen CDecl Alias "sqlite3PagerOpen" ( _
    ByVal pVfsArgument As sqlite3_vfs Ptr, _
    ByVal ppPager As Pager Ptr Ptr, _
    ByVal zFilename As Const ZString Ptr, _
    ByVal nExtra As SQLITE_C_INT, _
    ByVal flags As SQLITE_C_INT, _
    ByVal vfsFlags As SQLITE_C_INT, _
    ByVal xReinit As SqlitePagerReinitProc _
) As SQLITE_C_INT Export

    Dim openError As SQLITE_C_INT = SQLITE_CANTOPEN
    Dim pVfs As sqlite3_vfs Ptr = pVfsArgument
    Dim rcInit As SQLITE_C_INT = SQLITE_OK
    Dim pPager As Pager Ptr = 0
    Dim memDb As SQLITE_C_INT = 0
    Dim tempFile As SQLITE_C_INT = 0
    Dim pathBuffer As ZString Ptr = 0
    Dim pathLimit As SQLITE_C_INT = 0
    Dim rcPath As SQLITE_C_INT = SQLITE_OK
    Dim useJournal As SQLITE_C_INT = 0
    Dim readOnly As SQLITE_C_INT = 0
    Dim memoryVfs As SQLITE_C_INT = 0
    Dim openFlags As SQLITE_C_INT = 0
    Dim outFlags As SQLITE_C_INT = 0
    Dim zOpenName As Const ZString Ptr = 0
    Dim rcOpen As SQLITE_C_INT = SQLITE_OK
    Dim pageSize As u32 = SQLITE_DEFAULT_PAGE_SIZE
    Dim sectorSize As SQLITE_C_INT = SQLITE_DEFAULT_SECTOR_SIZE
    Dim rcCache As SQLITE_C_INT = SQLITE_OK

    If ppPager = 0 OrElse nExtra < 8 OrElse nExtra >= 1000 Then Return SQLITE_MISUSE
    ppPager[0] = 0
    If pVfs = 0 Then
        pVfs = sqlite3_vfs_find(0)
        If pVfs = 0 Then
            rcInit = sqlite3OsInit()
            If rcInit <> SQLITE_OK Then Return rcInit
            pVfs = sqlite3_vfs_find(0)
        End If
    End If
    If pVfs = 0 OrElse pVfs->szOsFile < SizeOf(sqlite3_file) Then Return SQLITE_CANTOPEN

    pPager = CPtr(Pager Ptr, sqlite3MallocZero(SizeOf(Pager)))
    If pPager = 0 Then Return SQLITE_NOMEM
    pPager->pVfs = pVfs
    Dim journalFileBytes As SQLITE_C_INT = sqlite3JournalSize(pVfs)
    If journalFileBytes < SizeOf(sqlite3_file) OrElse journalFileBytes > SQLITE_MAX_ALLOCATION_SIZE Then GoTo pager_open_cantopen
    pPager->pPCache = CPtr(PCache Ptr, sqlite3MallocZero(sqlite3PcacheSize()))
    pPager->jfd = CPtr(sqlite3_file Ptr, sqlite3MallocZero(CULngInt(journalFileBytes)))
    pPager->sjfd = CPtr(sqlite3_file Ptr, sqlite3MallocZero(CULngInt(journalFileBytes)))
    If pPager->pPCache = 0 OrElse pPager->jfd = 0 OrElse pPager->sjfd = 0 Then GoTo pager_open_nomem

    memDb = IIf((flags And PAGER_MEMORY) <> 0, 1, 0)
    tempFile = IIf(zFilename = 0 OrElse zFilename[0] = 0 OrElse memDb <> 0, 1, 0)
    pathLimit = pVfs->mxPathname + 1
    If pathLimit < 2 OrElse pathLimit > SQLITE_MAX_ALLOCATION_SIZE Then GoTo pager_open_cantopen
    If tempFile = 0 Then
        pathBuffer = CPtr(ZString Ptr, sqlite3MallocZero(CULngInt(pathLimit)))
        If pathBuffer = 0 Then GoTo pager_open_nomem
        rcPath = sqlite3OsFullPathname(pVfs, zFilename, pathLimit, pathBuffer)
        If rcPath <> SQLITE_OK Then
            openError = rcPath
            sqlite3_free(pathBuffer)
            pathBuffer = 0
            GoTo pager_open_error
        End If
        Dim pathNameLength As SQLITE_C_INT = sqlite3Strlen30(pathBuffer)
        If pathNameLength < 0 OrElse _
           CULngInt(pathNameLength) + 8 > CULngInt(pVfs->mxPathname) Then
            openError = SQLITE_CANTOPEN
            sqlite3_free(pathBuffer)
            pathBuffer = 0
            GoTo pager_open_error
        End If
    ElseIf memDb <> 0 AndAlso zFilename <> 0 AndAlso zFilename[0] <> 0 Then
        ' Named in-memory databases retain their name and URI cache options.
        pathBuffer = pagerStringDup(zFilename)
    Else
        pathBuffer = pagerStringDup(StrPtr(""))
    End If
    If pathBuffer = 0 Then GoTo pager_open_nomem

    pPager->zFilename = pagerCreatePackedFilename( _
        pathBuffer, zFilename, @pPager->zJournal, @pPager->zWal)
    sqlite3_free(pathBuffer)
    pathBuffer = 0
    If pPager->zFilename = 0 Then GoTo pager_open_nomem

    useJournal = IIf((flags And PAGER_OMIT_JOURNAL) = 0, 1, 0)
    If tempFile <> 0 Then
        ' Transient pagers keep their file handle unopened until the first
        ' spill. Small ephemeral B-trees therefore remain in the page cache.
        pPager->fd = CPtr(sqlite3_file Ptr, _
            sqlite3MallocZero(CULngInt(pVfs->szOsFile)))
        If pPager->fd = 0 Then GoTo pager_open_nomem
        readOnly = IIf((vfsFlags And SQLITE_OPEN_READONLY) <> 0, 1, 0)
    ElseIf memDb <> 0 Then
        pPager->fd = CPtr(sqlite3_file Ptr, _
            sqlite3MallocZero(CULngInt(pVfs->szOsFile)))
        If pPager->fd = 0 Then GoTo pager_open_nomem
    Else
        openFlags = vfsFlags
        If (openFlags And (SQLITE_OPEN_READONLY Or SQLITE_OPEN_READWRITE)) = 0 Then
            openFlags = SQLITE_OPEN_READWRITE Or SQLITE_OPEN_CREATE Or SQLITE_OPEN_MAIN_DB
        End If
        outFlags = 0
        rcOpen = sqlite3OsOpenMalloc( _
            pVfs, CPtr(Const ZString Ptr, pPager->zFilename), _
            @pPager->fd, openFlags, @outFlags)
        If rcOpen <> SQLITE_OK Then
            openError = rcOpen
            GoTo pager_open_error
        End If
        readOnly = IIf((outFlags And SQLITE_OPEN_READONLY) <> 0, 1, 0)
        memoryVfs = IIf((outFlags And SQLITE_OPEN_MEMORY) <> 0, 1, 0)
    End If

    pageSize = SQLITE_DEFAULT_PAGE_SIZE
    sectorSize = SQLITE_DEFAULT_SECTOR_SIZE
    If pPager->fd = 0 OrElse pPager->fd->pMethods = 0 Then
        sectorSize = 512
    ElseIf readOnly = 0 Then
        setSectorSize(pPager)
        sectorSize = CLng(pPager->sectorSize)
        If pageSize < sectorSize Then pageSize = sectorSize
        If pageSize > SQLITE_MAX_DEFAULT_PAGE_SIZE Then pageSize = SQLITE_MAX_DEFAULT_PAGE_SIZE
    End If

    pPager->tempFile = tempFile
    pPager->exclusiveMode = tempFile
    pPager->changeCountDone = tempFile
    pPager->memDb = memDb
    pPager->memVfs = memoryVfs
    pPager->readOnly = readOnly
    pPager->noLock = tempFile
    pPager->useJournal = useJournal
    pPager->journalMode = IIf(useJournal <> 0, PAGER_JOURNALMODE_DELETE, PAGER_JOURNALMODE_OFF)
    If useJournal <> 0 AndAlso (memDb <> 0 OrElse memoryVfs <> 0) Then _
        pPager->journalMode = PAGER_JOURNALMODE_MEMORY
    pPager->eState = IIf(tempFile <> 0, PAGER_READER, PAGER_OPEN)
    pPager->eLock = IIf(tempFile <> 0, EXCLUSIVE_LOCK, NO_LOCK)
    pPager->hasHeldSharedLock = IIf(tempFile <> 0, 1, 0)
    pPager->pageSize = pageSize
    pPager->nReserve = 0
    pPager->nExtra = (nExtra + 7) And Not 7
    pPager->sectorSize = sectorSize
    pPager->mxPgno = SQLITE_MAX_PAGE_COUNT
    pPager->lckPgno = (PENDING_BYTE \ pageSize) + 1
    pPager->journalSizeLimit = SQLITE_DEFAULT_JOURNAL_SIZE_LIMIT
    pPager->vfsFlags = vfsFlags
    setSectorSize(pPager)
    pPager->xReiniter = xReinit
    pPager->pTmpSpace = CPtr(UByte Ptr, sqlite3PageMalloc(CLng(pageSize) + 8))
    If pPager->pTmpSpace = 0 Then GoTo pager_open_nomem
    For i As Long = 0 To 7
        pPager->pTmpSpace[pageSize + i] = 0
    Next
    rcCache = sqlite3PcacheOpen(CLng(pageSize), pPager->nExtra, IIf(memDb = 0, 1, 0), _
                                @pagerStress, pPager, pPager->pPCache)
    If rcCache <> SQLITE_OK Then
        openError = rcCache
        GoTo pager_open_error
    End If
    ' The upstream open path sets the default page size through
    ' sqlite3PagerSetPagesize(), which resets the initial data-version state.
    ' This implementation initializes the page cache directly, so perform
    ' the same reset after the cache has been created.
    pager_reset(pPager)
    sqlite3PagerSetFlags(pPager, (SQLITE_DEFAULT_SYNCHRONOUS + 1) Or PAGER_CACHESPILL)
    pagerSetGetterMethod(pPager)
    *ppPager = pPager
    Return SQLITE_OK

pager_open_nomem:
    If pathBuffer <> 0 Then sqlite3_free(pathBuffer)
    sqlite3PagerClose(pPager, 0)
    Return SQLITE_NOMEM
pager_open_cantopen:
    sqlite3PagerClose(pPager, 0)
    Return SQLITE_CANTOPEN
pager_open_error:
    If pathBuffer <> 0 Then sqlite3_free(pathBuffer)
    sqlite3PagerClose(pPager, 0)
    Return openError
End Function

Private Function pagerPagecount CDecl Alias "pagerPagecount" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pPageCount As u32 Ptr _
) As SQLITE_C_INT
    If pPager = 0 OrElse pPageCount = 0 OrElse pPager->pageSize = 0 Then Return SQLITE_MISUSE

    Dim pageCount As u32 = 0
#ifndef SQLITE_OMIT_WAL
    pageCount = sqlite3WalDbsize(pPager->pWal)
#endif
    If pageCount = 0 Then
        If pPager->fd = 0 OrElse pPager->fd->pMethods = 0 Then Return SQLITE_MISUSE
        Dim fileSize As sqlite3_int64 = 0
        Dim rc As SQLITE_C_INT = sqlite3OsFileSize(pPager->fd, @fileSize)
        If rc <> SQLITE_OK Then Return rc
        If fileSize < 0 Then Return SQLITE_IOERR_FSTAT

        Dim pageCount64 As sqlite3_uint64 = CULngInt(fileSize) \ CULngInt(pPager->pageSize)
        If (CULngInt(fileSize) Mod CULngInt(pPager->pageSize)) <> 0 Then pageCount64 += 1
        If pageCount64 > &HFFFFFFFF Then Return SQLITE_FULL
        pageCount = CULng(pageCount64)
    End If

    If pageCount > pPager->mxPgno Then pPager->mxPgno = pageCount
    pPageCount[0] = pageCount
    Return SQLITE_OK
End Function

Private Function pagerGetPagecountFromFile(ByVal pPager As Pager Ptr, ByVal pPageCount As u32 Ptr) As SQLITE_C_INT
    If pPager = 0 OrElse pPageCount = 0 Then Return SQLITE_MISUSE
    If pPager->fd = 0 OrElse pPager->fd->pMethods = 0 Then
        pPageCount[0] = pPager->dbSize
        Return SQLITE_OK
    End If
    Dim nByte As sqlite3_int64 = 0
    Dim rc As SQLITE_C_INT = sqlite3OsFileSize(pPager->fd, @nByte)
    If rc <> SQLITE_OK Then Return rc
    If nByte <= 0 Then
        pPageCount[0] = 0
    Else
        Dim nPage As sqlite3_uint64 = (CULngInt(nByte) + CULngInt(pPager->pageSize) - 1) \ CULngInt(pPager->pageSize)
        If nPage > &HFFFFFFFF Then Return SQLITE_FULL
        pPageCount[0] = CULng(nPage)
    End If
    If pPageCount[0] > pPager->mxPgno Then pPager->mxPgno = pPageCount[0]
    Return SQLITE_OK
End Function

/' ------------------------------------------------------------------------- '/
/' Rollback journal recovery '/
/' ------------------------------------------------------------------------- '/

' On-disk rollback journal layout:
'   Header sector: 8-byte magic, record count, checksum seed, original page
'   count, sector size, page size, then sector padding.
'   Page record: 4-byte big-endian page number, one page image, and a
'   4-byte checksum. Super-journal metadata, if present, occupies the tail.

Private Function pagerJournalMagicByte(ByVal index As Long) As UByte
    Select Case index
    Case 0: Return &HD9
    Case 1: Return &HD5
    Case 2: Return &H05
    Case 3: Return &HF9
    Case 4: Return &H20
    Case 5: Return &HA1
    Case 6: Return &H63
    Case 7: Return &HD7
    End Select
    Return 0
End Function

Private Function pagerJournalMagicMatches(ByVal pBytes As Const UByte Ptr) As SQLITE_C_INT
    If pBytes = 0 Then Return 0
    For i As Long = 0 To 7
        If pBytes[i] <> pagerJournalMagicByte(i) Then Return 0
    Next
    Return 1
End Function

Private Function pagerReadJournalU32 CDecl Alias "read32bits" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal offset As sqlite3_int64, _
    ByVal pValue As u32 Ptr _
) As SQLITE_C_INT

    If pFile = 0 OrElse pValue = 0 Then Return SQLITE_MISUSE
    Dim bytes(0 To 3) As UByte
    Dim rc As SQLITE_C_INT = sqlite3OsRead(pFile, @bytes(0), 4, offset)
    If rc <> SQLITE_OK Then Return rc
    pValue[0] = (CULng(bytes(0)) Shl 24) Or _
                (CULng(bytes(1)) Shl 16) Or _
                (CULng(bytes(2)) Shl 8) Or _
                CULng(bytes(3))
    Return SQLITE_OK
End Function

Function readJournalHdr CDecl Alias "readJournalHdr" ( _
    ByVal pPager As Pager Ptr, _
    ByVal isHot As SQLITE_C_INT, _
    ByVal journalSize As sqlite3_int64, _
    ByVal pNRec As u32 Ptr, _
    ByVal pDbSize As u32 Ptr _
) As SQLITE_C_INT
    If pPager = 0 OrElse pNRec = 0 OrElse pDbSize = 0 OrElse _
       pPager->jfd = 0 OrElse pPager->jfd->pMethods = 0 Then Return SQLITE_MISUSE
    If pPager->sectorSize <= 0 Then Return SQLITE_CORRUPT

    Dim headerOffset As sqlite3_int64 = 0
    If pPager->journalOff <> 0 Then
        headerOffset = ((pPager->journalOff - 1) \ pPager->sectorSize + 1) * _
            pPager->sectorSize
    End If
    pPager->journalOff = headerOffset
    If headerOffset < 0 OrElse headerOffset > journalSize OrElse _
       CULngInt(pPager->sectorSize) > CULngInt(journalSize - headerOffset) Then Return SQLITE_DONE

    Dim headerOffsetInFile As sqlite3_int64 = headerOffset
    If isHot <> 0 OrElse headerOffsetInFile <> pPager->journalHdr Then
        Dim magic(0 To 7) As UByte
        Dim rc As SQLITE_C_INT = sqlite3OsRead( _
            pPager->jfd, @magic(0), 8, headerOffsetInFile)
        If rc <> SQLITE_OK Then Return rc
        If pagerJournalMagicMatches(@magic(0)) = 0 Then Return SQLITE_DONE
    End If

    Dim rc As SQLITE_C_INT = pagerReadJournalU32( _
        pPager->jfd, headerOffsetInFile + 8, pNRec)
    If rc = SQLITE_OK Then rc = pagerReadJournalU32( _
        pPager->jfd, headerOffsetInFile + 12, @pPager->cksumInit)
    If rc = SQLITE_OK Then rc = pagerReadJournalU32( _
        pPager->jfd, headerOffsetInFile + 16, pDbSize)
    If rc <> SQLITE_OK Then Return rc

    If headerOffsetInFile = 0 Then
        Dim sectorSizeInHeader As u32 = 0
        Dim pageSizeInHeader As u32 = 0
        rc = pagerReadJournalU32( _
            pPager->jfd, headerOffsetInFile + 20, @sectorSizeInHeader)
        If rc = SQLITE_OK Then rc = pagerReadJournalU32( _
            pPager->jfd, headerOffsetInFile + 24, @pageSizeInHeader)
        If rc <> SQLITE_OK Then Return rc

        If pageSizeInHeader = 0 Then pageSizeInHeader = CULng(pPager->pageSize)
        If pageSizeInHeader < 512 OrElse sectorSizeInHeader < 32 OrElse _
           pageSizeInHeader > SQLITE_MAX_PAGE_SIZE OrElse _
           sectorSizeInHeader > PAGER_MAX_SECTOR_SIZE OrElse _
           (pageSizeInHeader And (pageSizeInHeader - 1)) <> 0 OrElse _
           (sectorSizeInHeader And (sectorSizeInHeader - 1)) <> 0 Then Return SQLITE_DONE

        rc = sqlite3PagerSetPagesize(pPager, @pageSizeInHeader, -1)
        pPager->sectorSize = sectorSizeInHeader
    End If

    pPager->journalOff = headerOffsetInFile + pPager->sectorSize
    Return rc
End Function

Private Function pager_cksum CDecl Alias "pager_cksum" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pData As Const UByte Ptr _
) As u32
    Dim checksum As u32 = pPager->cksumInit
    Dim i As Long = CLng(pPager->pageSize) - 200
    While i > 0
        checksum += pData[i]
        i -= 200
    Wend
    Return checksum
End Function

#ifdef SQLITE_CHECK_PAGES
#ifndef SQLITE_DEBUG
Declare Sub pagerAbort CDecl Alias "abort" ()
#endif

Private Sub pagerCheckPagesAssertion( _
    ByVal condition As SQLITE_C_INT, _
    ByVal expression As Const ZString Ptr _
)
#ifndef NDEBUG
    If condition <> 0 Then Exit Sub
#ifdef SQLITE_DEBUG
    sqlite3DebugAssert(expression)
#else
    pagerAbort()
#endif
#endif
End Sub

' SQLite's debug checksum uses 1039 as its fixed page-byte multiplier.
Private Function pager_datahash CDecl Alias "pager_datahash" ( _
    ByVal byteCount As SQLITE_C_INT, _
    ByVal pData As UByte Ptr _
) As u64
    If byteCount <= 0 OrElse pData = 0 Then Return 0

    Dim hashValue As u64 = 0
    For byteIndex As SQLITE_C_INT = 0 To byteCount - 1
        hashValue = (hashValue * 1039ULL) + CULngInt(pData[byteIndex])
    Next
    Return hashValue
End Function

Private Function pager_pagehash CDecl Alias "pager_pagehash" ( _
    ByVal pPage As PgHdr Ptr _
) As u64
    If pPage = 0 OrElse pPage->pData = 0 OrElse pPage->pPager = 0 Then Return 0
    Dim pPager As Pager Ptr = CPtr(Pager Ptr, pPage->pPager)
    If pPager->pageSize <= 0 Then Return 0
    Return pager_datahash(CLng(pPager->pageSize), CPtr(UByte Ptr, pPage->pData))
End Function

Private Sub pager_set_pagehash CDecl Alias "pager_set_pagehash" ( _
    ByVal pPage As PgHdr Ptr _
)
    If pPage = 0 Then Exit Sub
    pPage->pageHash = pager_pagehash(pPage)
End Sub

Sub pagerPageCheck CDecl Alias "checkPage" ( _
    ByVal pPage As PgHdr Ptr _
)
    If pPage = 0 Then
        pagerCheckPagesAssertion(0, StrPtr("pPage != 0"))
        Exit Sub
    End If
    If pPage->pPager = 0 Then
        pagerCheckPagesAssertion(0, StrPtr("pPage->pPager != 0"))
        Exit Sub
    End If
    Dim pPager As Pager Ptr = CPtr(Pager Ptr, pPage->pPager)
    pagerCheckPagesAssertion( _
        CInt(pPager->eState <> PAGER_ERROR), _
        StrPtr("pPager->eState != PAGER_ERROR"))
    pagerCheckPagesAssertion( _
        CInt((pPage->flags And PGHDR_DIRTY) <> 0 OrElse _
             pPage->pageHash = pager_pagehash(pPage)), _
        StrPtr("clean page contents match the saved page hash"))
End Sub
#endif

Private Sub pagerSetPageHash(ByVal pPage As PgHdr Ptr)
    If pPage = 0 Then Exit Sub
#ifdef SQLITE_CHECK_PAGES
    pager_set_pagehash(pPage)
#endif
End Sub

Private Sub pagerFreeMapHdrs CDecl Alias "pagerFreeMapHdrs" ( _
    ByVal pPager As Pager Ptr _
)
    If pPager = 0 Then Return
    Dim pPage As PgHdr Ptr = pPager->pMmapFreelist
    While pPage <> 0
        Dim pNext As PgHdr Ptr = pPage->pDirty
        sqlite3_free(pPage)
        pPage = pNext
    Wend
    pPager->pMmapFreelist = 0
End Sub

Private Function pagerIsSuperJournalName(ByVal pName As Const UByte Ptr, ByVal nName As u32) As SQLITE_C_INT
    If pName = 0 OrElse nName < 12 Then Return 0
    Dim i As u32 = nName - 12
    If pName[i] <> Asc("-") OrElse pName[i + 1] <> Asc("m") OrElse pName[i + 2] <> Asc("j") Then Return 0
    If pName[nName - 3] <> Asc("9") Then Return 0
    For i = nName - 9 To nName - 1
        Dim c As UByte = pName[i]
        If Not ((c >= Asc("0") AndAlso c <= Asc("9")) OrElse _
                (c >= Asc("a") AndAlso c <= Asc("f")) OrElse _
                (c >= Asc("A") AndAlso c <= Asc("F"))) Then Return 0
    Next
    Return 1
End Function

Private Function pagerReadSuperJournal( _
    ByVal pPager As Pager Ptr, _
    ByVal pJournal As sqlite3_file Ptr, _
    ByVal journalSize As sqlite3_int64, _
    ByVal pzSuper As ZString Ptr Ptr _
) As SQLITE_C_INT

    If pPager = 0 OrElse pJournal = 0 OrElse pzSuper = 0 Then Return SQLITE_MISUSE
    pzSuper[0] = 0
    If journalSize < 16 Then Return SQLITE_OK

    Dim nName As u32 = 0
    Dim checksum As u32 = 0
    Dim rc As SQLITE_C_INT = pagerReadJournalU32(pJournal, journalSize - 16, @nName)
    If rc <> SQLITE_OK Then
        If rc = SQLITE_IOERR_SHORT_READ Then Return SQLITE_OK
        Return rc
    End If
    If nName = 0 OrElse nName > pPager->pVfs->mxPathname OrElse _
       CULngInt(nName) > CULngInt(journalSize - 16) Then Return SQLITE_OK
    rc = pagerReadJournalU32(pJournal, journalSize - 12, @checksum)
    If rc <> SQLITE_OK Then
        If rc = SQLITE_IOERR_SHORT_READ Then Return SQLITE_OK
        Return rc
    End If

    Dim magic(0 To 7) As UByte
    rc = sqlite3OsRead(pJournal, @magic(0), 8, journalSize - 8)
    If rc <> SQLITE_OK Then
        If rc = SQLITE_IOERR_SHORT_READ Then Return SQLITE_OK
        Return rc
    End If
    If pagerJournalMagicMatches(@magic(0)) = 0 Then Return SQLITE_OK

    Dim pName As UByte Ptr = CPtr(UByte Ptr, sqlite3Malloc(CULngInt(nName) + 1))
    If pName = 0 Then Return SQLITE_NOMEM
    rc = sqlite3OsRead(pJournal, pName, CLng(nName), journalSize - 16 - nName)
    If rc <> SQLITE_OK Then
        sqlite3_free(pName)
        If rc = SQLITE_IOERR_SHORT_READ Then Return SQLITE_OK
        Return rc
    End If

    Dim sum As u32 = checksum
    For i As u32 = 0 To nName - 1
        If pName[i] = 0 Then
            sqlite3_free(pName)
            Return SQLITE_OK
        End If
        sum -= pName[i]
    Next
    If sum <> 0 OrElse pagerIsSuperJournalName(pName, nName) = 0 Then
        sqlite3_free(pName)
        Return SQLITE_OK
    End If
    pName[nName] = 0
    pzSuper[0] = CPtr(ZString Ptr, pName)
    Return SQLITE_OK
End Function

Function readSuperJournal CDecl Alias "readSuperJournal" ( _
    ByVal pJournal As sqlite3_file Ptr, _
    ByVal maximumNameBytes As sqlite3_uint64, _
    ByVal pzSuperJournal As ZString Ptr Ptr _
) As SQLITE_C_INT
    If pJournal = 0 OrElse pzSuperJournal = 0 Then Return SQLITE_MISUSE
    pzSuperJournal[0] = 0

    Dim journalSize As sqlite3_int64 = 0
    Dim rc As SQLITE_C_INT = sqlite3OsFileSize(pJournal, @journalSize)
    If rc <> SQLITE_OK OrElse journalSize < 16 Then Return rc

    Dim nameLength As u32 = 0
    Dim checksum As u32 = 0
    rc = pagerReadJournalU32(pJournal, journalSize - 16, @nameLength)
    If rc <> SQLITE_OK Then Return rc
    If CULngInt(nameLength) >= maximumNameBytes OrElse nameLength = 0 OrElse _
       CULngInt(nameLength) > CULngInt(journalSize - 16) Then Return SQLITE_OK

    rc = pagerReadJournalU32(pJournal, journalSize - 12, @checksum)
    If rc <> SQLITE_OK Then Return rc
    Dim magic(0 To 7) As UByte
    rc = sqlite3OsRead(pJournal, @magic(0), 8, journalSize - 8)
    If rc <> SQLITE_OK Then Return rc

    Dim pAllocation As UByte Ptr = CPtr(UByte Ptr, _
        sqlite3MallocZero(CULngInt(nameLength) + 6))
    If pAllocation = 0 Then
        If pagerJournalMagicMatches(@magic(0)) = 0 Then Return SQLITE_OK
        Return SQLITE_NOMEM
    End If
    Dim pName As UByte Ptr = pAllocation + 4

    rc = sqlite3OsRead(pJournal, pName, CLng(nameLength), _
        journalSize - 16 - nameLength)
    If rc = SQLITE_OK Then
        For i As u32 = 0 To nameLength - 1
            checksum -= pName[i]
        Next
    End If

    If rc <> SQLITE_OK OrElse pagerIsSuperJournalName(pName, nameLength) = 0 OrElse _
       checksum <> 0 OrElse pagerJournalMagicMatches(@magic(0)) = 0 Then
        sqlite3_free(pAllocation)
        Return rc
    End If

    pzSuperJournal[0] = CPtr(ZString Ptr, pName)
    Return SQLITE_OK
End Function

Private Function pagerPlayHotJournal( _
    ByVal pPager As Pager Ptr, _
    ByVal journalSize As sqlite3_int64, _
    ByVal restoreMode As SQLITE_C_INT, _
    ByVal isHot As SQLITE_C_INT _
) As SQLITE_C_INT
    If pPager = 0 OrElse (restoreMode < 0 OrElse restoreMode > 2) OrElse _
       (isHot <> 0 AndAlso isHot <> 1) Then Return SQLITE_MISUSE
    Dim savedPageSize As u32 = CULng(pPager->pageSize)
    Dim originalDbSize As u32 = 0
    Dim journalOffset As sqlite3_int64 = 0
    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim haveHeader As SQLITE_C_INT = 0
    Dim stopPlayback As SQLITE_C_INT = 0
    Dim finalHeader As SQLITE_C_INT = 0

    While stopPlayback = 0
        Dim headerOffset As sqlite3_int64 = 0
        If journalOffset <> 0 Then
            headerOffset = ((journalOffset - 1) \ pPager->sectorSize + 1) * pPager->sectorSize
        End If
        If headerOffset < 0 OrElse headerOffset + pPager->sectorSize > journalSize Then Exit While

        Dim magic(0 To 7) As UByte
        rc = sqlite3OsRead(pPager->jfd, @magic(0), 8, headerOffset)
        If rc = SQLITE_IOERR_SHORT_READ Then
            rc = SQLITE_OK
            Exit While
        End If
        If rc <> SQLITE_OK Then Return rc
        If pagerJournalMagicMatches(@magic(0)) = 0 Then Exit While

        Dim nRecord As u32 = 0
        Dim checksumSeed As u32 = 0
        Dim dbSize As u32 = 0
        rc = pagerReadJournalU32(pPager->jfd, headerOffset + 8, @nRecord)
        If rc = SQLITE_OK Then rc = pagerReadJournalU32(pPager->jfd, headerOffset + 12, @checksumSeed)
        If rc = SQLITE_OK Then rc = pagerReadJournalU32(pPager->jfd, headerOffset + 16, @dbSize)
        If rc = SQLITE_IOERR_SHORT_READ Then
            rc = SQLITE_OK
            Exit While
        End If
        If rc <> SQLITE_OK Then Return rc

        If haveHeader = 0 Then
            Dim sectorSize As u32 = 0
            Dim pageSize As u32 = 0
            rc = pagerReadJournalU32(pPager->jfd, headerOffset + 20, @sectorSize)
            If rc = SQLITE_OK Then rc = pagerReadJournalU32(pPager->jfd, headerOffset + 24, @pageSize)
            If rc = SQLITE_IOERR_SHORT_READ Then
                rc = SQLITE_OK
                Exit While
            End If
            If rc <> SQLITE_OK Then Return rc
            If pageSize = 0 Then pageSize = CULng(pPager->pageSize)
            If pageSize < 512 OrElse pageSize > SQLITE_MAX_PAGE_SIZE OrElse _
               (pageSize And (pageSize - 1)) <> 0 OrElse sectorSize < 32 OrElse _
               sectorSize > PAGER_MAX_SECTOR_SIZE OrElse (sectorSize And (sectorSize - 1)) <> 0 Then Exit While

            If isHot <> 0 Then
                rc = sqlite3PagerSetPagesize(pPager, @pageSize, -1)
                If rc <> SQLITE_OK Then Return rc
            ElseIf pageSize <> pPager->pageSize Then
                Return SQLITE_CORRUPT
            End If
            pPager->sectorSize = sectorSize
            originalDbSize = dbSize
            pPager->dbOrigSize = dbSize
            pPager->dbSize = dbSize
            pPager->mxPgno = IIf(pPager->mxPgno < dbSize, dbSize, pPager->mxPgno)
            If restoreMode = 0 Then
                Dim originalBytes As sqlite3_int64 = CLngInt(dbSize) * pageSize
                rc = sqlite3OsTruncate(pPager->fd, originalBytes)
                If rc <> SQLITE_OK Then Return rc
            End If
            pPager->dbFileSize = dbSize
            haveHeader = 1
        End If

        journalOffset = headerOffset + pPager->sectorSize
        If nRecord = &HFFFFFFFF Then
            Dim unboundedRecords As sqlite3_int64 = (journalSize - journalOffset) \ (pPager->pageSize + 8)
            If unboundedRecords > &HFFFFFFFF Then unboundedRecords = &HFFFFFFFF
            nRecord = CULng(unboundedRecords)
            finalHeader = 1
        ElseIf nRecord = 0 Then
            If isHot <> 0 Then Exit While
            ' A live rollback can see an unfinished header with records after it.
            Dim remainingBytes As sqlite3_int64 = journalSize - journalOffset
            If remainingBytes < 0 Then Return SQLITE_CORRUPT
            Dim rollbackRecords As sqlite3_int64 = _
                remainingBytes \ (pPager->pageSize + 8)
            If rollbackRecords > &HFFFFFFFF Then rollbackRecords = &HFFFFFFFF
            nRecord = CULng(rollbackRecords)
            If nRecord = 0 Then Exit While
        End If

        Dim availableRecords As sqlite3_int64 = 0
        If journalSize > journalOffset Then
            availableRecords = (journalSize - journalOffset) \ (pPager->pageSize + 8)
        End If
        Dim nRecordToRead As u32 = nRecord
        If CULngInt(nRecordToRead) > CULngInt(availableRecords) Then nRecordToRead = CULng(availableRecords)

        For iRecord As sqlite3_int64 = 0 To CLngInt(nRecordToRead) - 1
            Dim pageNumber As u32 = 0
            rc = pagerReadJournalU32(pPager->jfd, journalOffset, @pageNumber)
            If rc = SQLITE_IOERR_SHORT_READ Then
                rc = SQLITE_OK
                stopPlayback = 1
                Exit For
            End If
            If rc <> SQLITE_OK Then Return rc
            If pageNumber = 0 OrElse pageNumber = pPager->lckPgno Then
                stopPlayback = 1
                Exit For
            End If

            rc = sqlite3OsRead(pPager->jfd, pPager->pTmpSpace, CLng(pPager->pageSize), journalOffset + 4)
            If rc = SQLITE_IOERR_SHORT_READ Then
                rc = SQLITE_OK
                stopPlayback = 1
                Exit For
            End If
            If rc <> SQLITE_OK Then Return rc
            Dim recordChecksum As u32 = 0
            rc = pagerReadJournalU32(pPager->jfd, journalOffset + pPager->pageSize + 4, @recordChecksum)
            If rc = SQLITE_IOERR_SHORT_READ Then
                rc = SQLITE_OK
                stopPlayback = 1
                Exit For
            End If
            If rc <> SQLITE_OK Then Return rc
            journalOffset += pPager->pageSize + 8
            pPager->cksumInit = checksumSeed
            If pager_cksum(pPager, pPager->pTmpSpace) <> recordChecksum Then
                stopPlayback = 1
                Exit For
            End If
            If pageNumber <= originalDbSize AndAlso restoreMode = 0 Then
                Dim dbOffset As sqlite3_int64 = (CLngInt(pageNumber) - 1) * pPager->pageSize
                rc = sqlite3OsWrite(pPager->fd, pPager->pTmpSpace, CLng(pPager->pageSize), dbOffset)
                If pPager->pBackup <> 0 Then
                    sqlite3BackupUpdate(pPager->pBackup, pageNumber, _
                        CPtr(Const UByte Ptr, pPager->pTmpSpace))
                End If
                If rc <> SQLITE_OK Then Return rc
            End If
            If pageNumber <= originalDbSize Then
                Dim pRestore As PgHdr Ptr = sqlite3PagerLookup(pPager, pageNumber)
                If pRestore = 0 AndAlso restoreMode = 1 Then
                    rc = sqlite3PagerGet(pPager, pageNumber, @pRestore, PAGER_GET_NOCONTENT)
                    If rc <> SQLITE_OK Then Return rc
                End If
                If pRestore <> 0 Then
                    Dim pRestoreData As UByte Ptr = CPtr(UByte Ptr, pRestore->pData)
                    For i As sqlite3_int64 = 0 To pPager->pageSize - 1
                        pRestoreData[i] = pPager->pTmpSpace[i]
                    Next
                    If pageNumber = 1 Then
                        pPager->nReserve = pRestoreData[20]
                        For i As Long = 0 To 15
                            pPager->dbFileVers(i) = pRestoreData[24 + i]
                        Next
                    End If
                    If pPager->xReiniter <> 0 Then
                        Dim xReinit As SqlitePagerReinitProc = CPtr(SqlitePagerReinitProc, pPager->xReiniter)
                        xReinit(pRestore)
                    End If
                    If (pRestore->flags And PGHDR_DIRTY) <> 0 Then sqlite3PcacheMakeClean(pRestore)
                    sqlite3PagerUnrefNotNull(pRestore)
                End If
            End If
        Next

        If stopPlayback <> 0 OrElse finalHeader <> 0 OrElse _
           CULngInt(nRecordToRead) < CULngInt(nRecord) Then Exit While
    Wend

    If haveHeader <> 0 Then
        If isHot <> 0 Then
            Dim restorePageSize As u32 = savedPageSize
            rc = sqlite3PagerSetPagesize(pPager, @restorePageSize, -1)
            If rc <> SQLITE_OK Then Return rc
        ElseIf pPager->pageSize <> savedPageSize Then
            Return SQLITE_CORRUPT
        End If
        setSectorSize(pPager)
        rc = pagerGetPagecountFromFile(pPager, @pPager->dbSize)
        If rc <> SQLITE_OK Then Return rc
        pPager->dbFileSize = pPager->dbSize
        If restoreMode <> 0 Then sqlite3PcacheTruncate(pPager->pPCache, originalDbSize)
    End If
    Return SQLITE_OK
End Function

Function pager_playback_one_page CDecl Alias "pager_playback_one_page" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pOffset As sqlite3_int64 Ptr, _
    ByVal pDoneArgument As Any Ptr, _
    ByVal isMainJournal As SQLITE_C_INT, _
    ByVal isSavepoint As SQLITE_C_INT _
) As SQLITE_C_INT
    If pPager = 0 OrElse pOffset = 0 OrElse pPager->pTmpSpace = 0 OrElse _
       (isMainJournal <> 0 AndAlso isMainJournal <> 1) OrElse _
       (isSavepoint <> 0 AndAlso isSavepoint <> 1) Then Return SQLITE_MISUSE
    If (isMainJournal = 0 AndAlso pDoneArgument = 0) OrElse _
       (isSavepoint = 0 AndAlso pDoneArgument <> 0) Then Return SQLITE_MISUSE
    If pPager->pageSize <= 0 OrElse pOffset[0] < 0 Then Return SQLITE_CORRUPT

    Dim pDone As Any Ptr = pDoneArgument
    Dim journalFile As sqlite3_file Ptr = pPager->sjfd
    If isMainJournal <> 0 Then journalFile = pPager->jfd
    If journalFile = 0 OrElse journalFile->pMethods = 0 Then Return SQLITE_MISUSE

    Dim pageNumber As u32 = 0
    Dim rc As SQLITE_C_INT = pagerReadJournalU32(journalFile, pOffset[0], @pageNumber)
    If rc <> SQLITE_OK Then Return rc

    rc = sqlite3OsRead(journalFile, pPager->pTmpSpace, CInt(pPager->pageSize), _
        pOffset[0] + 4)
    If rc <> SQLITE_OK Then Return rc

    ' Journal records store a four-byte page number and data; only the main
    ' journal adds a four-byte checksum after the page image.
    Dim recordSize As sqlite3_int64 = pPager->pageSize + 4 + (isMainJournal * 4)
    If pOffset[0] > &H7FFFFFFFFFFFFFFFLL - recordSize Then Return SQLITE_CORRUPT
    pOffset[0] += recordSize

    If pageNumber = 0 OrElse pageNumber = pPager->lckPgno Then Return SQLITE_DONE
    If pageNumber > pPager->dbSize OrElse sqlite3BitvecTest(pDone, pageNumber) <> 0 Then _
        Return SQLITE_OK

    If isMainJournal <> 0 Then
        Dim storedChecksum As u32 = 0
        rc = pagerReadJournalU32(journalFile, pOffset[0] - 4, @storedChecksum)
        If rc <> SQLITE_OK Then Return rc
        If isSavepoint = 0 AndAlso _
           pager_cksum(pPager, pPager->pTmpSpace) <> storedChecksum Then _
            Return SQLITE_DONE
    End If

    If pDone <> 0 Then
        rc = sqlite3BitvecSet(pDone, pageNumber)
        If rc <> SQLITE_OK Then Return rc
    End If

    If pageNumber = 1 Then
        ' Byte 20 in the database header stores the reserved-space count.
        If pPager->nReserve <> pPager->pTmpSpace[20] Then _
            pPager->nReserve = pPager->pTmpSpace[20]
    End If

    Dim pPage As PgHdr Ptr = 0
#ifndef SQLITE_OMIT_WAL
    If pPager->pWal = 0 Then pPage = sqlite3PagerLookup(pPager, pageNumber)
#else
    pPage = sqlite3PagerLookup(pPager, pageNumber)
#endif

    Dim isSynced As SQLITE_C_INT
    If isMainJournal <> 0 Then
        isSynced = CInt(pPager->noSync <> 0 OrElse pOffset[0] <= pPager->journalHdr)
    Else
        isSynced = CInt(pPage = 0 OrElse (pPage->flags And PGHDR_NEED_SYNC) = 0)
    End If

    If pPager->fd <> 0 AndAlso pPager->fd->pMethods <> 0 AndAlso _
       (pPager->eState >= PAGER_WRITER_DBMOD OrElse pPager->eState = PAGER_OPEN) AndAlso _
       isSynced <> 0 Then
        Dim databaseOffset As sqlite3_int64 = _
            (CLngInt(pageNumber) - 1) * pPager->pageSize
        rc = sqlite3OsWrite(pPager->fd, pPager->pTmpSpace, _
            CInt(pPager->pageSize), databaseOffset)
        If pageNumber > pPager->dbFileSize Then pPager->dbFileSize = pageNumber
        If pPager->pBackup <> 0 Then _
            sqlite3BackupUpdate(pPager->pBackup, pageNumber, pPager->pTmpSpace)
    ElseIf isMainJournal = 0 AndAlso pPage = 0 Then
        ' Keep a restored sub-journal page from spilling before rollback uses it.
        If (pPager->doNotSpill And SPILLFLAG_ROLLBACK) <> 0 Then Return SQLITE_MISUSE
        pPager->doNotSpill = pPager->doNotSpill Or SPILLFLAG_ROLLBACK
        rc = sqlite3PagerGet(pPager, pageNumber, @pPage, PAGER_GET_NOCONTENT)
        pPager->doNotSpill = pPager->doNotSpill And Not SPILLFLAG_ROLLBACK
        If rc <> SQLITE_OK Then Return rc
        sqlite3PcacheMakeDirty(pPage)
    End If

    If pPage <> 0 Then
        Dim pPageData As UByte Ptr = CPtr(UByte Ptr, pPage->pData)
        For i As sqlite3_int64 = 0 To pPager->pageSize - 1
            pPageData[i] = pPager->pTmpSpace[i]
        Next
        If pPager->xReiniter <> 0 Then
            Dim xReinit As SqlitePagerReinitProc = _
                CPtr(SqlitePagerReinitProc, pPager->xReiniter)
            xReinit(pPage)
        End If
        pagerSetPageHash(pPage)
        If pageNumber = 1 Then
            For i As Long = 0 To 15
                pPager->dbFileVers(i) = pPageData[PAGER_FILE_VERSION_OFFSET + i]
            Next
        End If
        sqlite3PcacheRelease(pPage)
    End If
    Return rc
End Function

Private Function hasHotJournal CDecl Alias "hasHotJournal" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pExists As SQLITE_C_INT Ptr _
) As SQLITE_C_INT

    If pPager = 0 OrElse pExists = 0 OrElse pPager->fd = 0 OrElse _
       pPager->jfd = 0 OrElse pPager->zJournal = 0 Then Return SQLITE_MISUSE
    If pPager->useJournal = 0 OrElse pPager->eState <> PAGER_OPEN Then Return SQLITE_MISUSE

    Dim journalOpen As SQLITE_C_INT = IIf(pPager->jfd->pMethods <> 0, 1, 0)
    Dim journalExists As SQLITE_C_INT = 1
    Dim rc As SQLITE_C_INT = SQLITE_OK
    pExists[0] = 0

    If journalOpen = 0 Then
        rc = sqlite3OsAccess(pPager->pVfs, pPager->zJournal, SQLITE_ACCESS_EXISTS, @journalExists)
    End If
    If rc <> SQLITE_OK OrElse journalExists = 0 Then Return rc

    Dim reservedLock As SQLITE_C_INT = 0
    rc = sqlite3OsCheckReservedLock(pPager->fd, @reservedLock)
    If rc <> SQLITE_OK OrElse reservedLock <> 0 Then Return rc

    Dim pageCount As u32 = 0
    rc = pagerPagecount(pPager, @pageCount)
    If rc <> SQLITE_OK Then Return rc

    If pageCount = 0 AndAlso journalOpen = 0 Then
        ' The journal belongs to a deleted or not-yet-created database. Hold a
        ' RESERVED lock while deleting it so a new writer cannot race the check.
        sqlite3BeginBenignMalloc()
        If pagerLockDb(pPager, RESERVED_LOCK) = SQLITE_OK Then
            sqlite3OsDelete(pPager->pVfs, pPager->zJournal, 0)
            If pPager->exclusiveMode = 0 Then pagerUnlockDb(pPager, SHARED_LOCK)
        End If
        sqlite3EndBenignMalloc()
        Return SQLITE_OK
    End If

    If journalOpen = 0 Then
        Dim outFlags As SQLITE_C_INT = SQLITE_OPEN_READONLY Or SQLITE_OPEN_MAIN_JOURNAL
        rc = sqlite3OsOpen(pPager->pVfs, pPager->zJournal, pPager->jfd, outFlags, @outFlags)
    End If
    If rc = SQLITE_OK Then
        Dim firstByte As UByte = 0
        rc = sqlite3OsRead(pPager->jfd, @firstByte, 1, 0)
        If rc = SQLITE_IOERR_SHORT_READ Then rc = SQLITE_OK
        If journalOpen = 0 Then sqlite3OsClose(pPager->jfd)
        If rc = SQLITE_OK AndAlso firstByte <> 0 Then pExists[0] = 1
    ElseIf rc = SQLITE_CANTOPEN Then
        ' A concurrent connection may have removed the journal after access().
        ' Treat that race as a possible hot journal and let recovery decide.
        pExists[0] = 1
        rc = SQLITE_OK
    End If
    Return rc
End Function

Private Function pagerHotJournal(ByVal pPager As Pager Ptr) As SQLITE_C_INT
    If pPager = 0 Then Return SQLITE_MISUSE
    Dim journalExists As SQLITE_C_INT = 0
    Dim rc As SQLITE_C_INT = hasHotJournal(pPager, @journalExists)
    If rc <> SQLITE_OK OrElse journalExists = 0 Then Return rc
    If pPager->readOnly <> 0 Then Return SQLITE_READONLY_ROLLBACK

    rc = pagerTryBusyLock(pPager, EXCLUSIVE_LOCK)
    If rc <> SQLITE_OK Then Return rc
    If pPager->jfd->pMethods = 0 Then
        Dim outFlags As SQLITE_C_INT = 0
        rc = sqlite3OsOpen(pPager->pVfs, pPager->zJournal, pPager->jfd, _
            SQLITE_OPEN_READWRITE Or SQLITE_OPEN_MAIN_JOURNAL, @outFlags)
        If rc = SQLITE_OK AndAlso (outFlags And SQLITE_OPEN_READONLY) <> 0 Then
            ' A read-only fallback is not writable enough to recover a hot journal.
            rc = SQLITE_CANTOPEN
            sqlite3OsClose(pPager->jfd)
        End If
        If rc <> SQLITE_OK Then Return rc
    End If

    rc = pagerSyncHotJournal(pPager)
    If rc = SQLITE_OK Then
        rc = pagerPlaybackBridge(pPager, IIf(pPager->tempFile = 0, 1, 0))
        pPager->eState = PAGER_OPEN
    End If
    Return rc
End Function

Private Function pagerErrorInternal CDecl Alias "pager_error" ( _
    ByVal pPager As Pager Ptr, _
    ByVal rc As SQLITE_C_INT _
) As SQLITE_C_INT
    If pPager = 0 Then Return rc
    Dim baseCode As SQLITE_C_INT = rc And &HFF
    If baseCode = SQLITE_FULL OrElse baseCode = SQLITE_IOERR Then
        pPager->errCode = rc
        pPager->eState = PAGER_ERROR
        pagerSetGetterMethod(pPager)
    End If
    Return rc
End Function

Private Sub pagerSetError(ByVal pPager As Pager Ptr, ByVal rc As SQLITE_C_INT)
    pagerErrorInternal(pPager, rc)
End Sub

Private Function pagerAppendSuperJournal CDecl Alias "writeSuperJournal" ( _
    ByVal pPager As Pager Ptr, _
    ByVal zSuper As Const ZString Ptr _
) As SQLITE_C_INT
    If pPager = 0 Then Return SQLITE_MISUSE
    If pPager->setSuper <> 0 Then Return SQLITE_MISUSE
#ifndef SQLITE_OMIT_WAL
    If pPager->pWal <> 0 Then Return SQLITE_MISUSE
#endif
    If zSuper = 0 OrElse pPager->journalMode = PAGER_JOURNALMODE_MEMORY OrElse _
       pPager->jfd = 0 OrElse pPager->jfd->pMethods = 0 Then Return SQLITE_OK

    Dim nameLength As SQLITE_C_INT = pagerStringLength(zSuper)
    If nameLength <= 0 Then Return SQLITE_MISUSE
    Dim pName As Const UByte Ptr = CPtr(Const UByte Ptr, zSuper)
    If pagerIsSuperJournalName(pName, CULng(nameLength)) = 0 Then Return SQLITE_MISUSE

    If pPager->fullSync <> 0 Then
        If pPager->sectorSize = 0 Then Return SQLITE_MISUSE
        pPager->journalOff = _
            ((pPager->journalOff - 1) \ pPager->sectorSize + 1) * pPager->sectorSize
    End If
    Dim recordOffset As sqlite3_int64 = pPager->journalOff
    Dim checksum As u32 = 0
    For nameIndex As SQLITE_C_INT = 0 To nameLength - 1
        ' The journal format sums each UTF-8 byte as a signed 8-bit value.
        Dim signedByte As SQLITE_C_INT = pName[nameIndex]
        If signedByte >= 128 Then signedByte -= 256
        If signedByte < 0 Then
            checksum -= CUInt(-signedByte)
        Else
            checksum += CUInt(signedByte)
        End If
    Next

    ' A partial record still means the super-journal may be on disk.
    pPager->setSuper = 1
    Dim rc As SQLITE_C_INT = pagerWriteJournalU32( _
        pPager->jfd, recordOffset, pPager->lckPgno)
    If rc = SQLITE_OK Then
        rc = sqlite3OsWrite(pPager->jfd, zSuper, nameLength, recordOffset + 4)
    End If
    If rc = SQLITE_OK Then
        rc = pagerWriteJournalU32( _
            pPager->jfd, recordOffset + 4 + nameLength, CULng(nameLength))
    End If
    If rc = SQLITE_OK Then
        rc = pagerWriteJournalU32( _
            pPager->jfd, recordOffset + 8 + nameLength, checksum)
    End If
    If rc = SQLITE_OK Then
        Dim magic(0 To 7) As UByte
        For byteIndex As SQLITE_C_INT = 0 To 7
            magic(byteIndex) = pagerJournalMagicByte(byteIndex)
        Next
        rc = sqlite3OsWrite( _
            pPager->jfd, @magic(0), 8, recordOffset + 12 + nameLength)
    End If
    If rc <> SQLITE_OK Then Return rc

    If pPager->journalOff > &H7FFFFFFFFFFFFFFF - CULngInt(nameLength) - 20 Then _
        Return SQLITE_FULL
    pPager->journalOff += nameLength + 20

    Dim journalSize As sqlite3_int64 = 0
    rc = sqlite3OsFileSize(pPager->jfd, @journalSize)
    If rc = SQLITE_OK AndAlso journalSize > pPager->journalOff Then _
        rc = sqlite3OsTruncate(pPager->jfd, pPager->journalOff)
    Return rc
End Function

Private Function pager_incr_changecounter CDecl Alias "pager_incr_changecounter" ( _
    ByVal pPager As Pager Ptr, _
    ByVal directMode As SQLITE_C_INT _
) As SQLITE_C_INT
    If pPager = 0 Then Return SQLITE_MISUSE
    If pPager->eState <> PAGER_WRITER_CACHEMOD AndAlso _
       pPager->eState <> PAGER_WRITER_DBMOD Then Return SQLITE_MISUSE

#ifndef SQLITE_ENABLE_ATOMIC_WRITE
    If directMode <> 0 Then Return SQLITE_MISUSE
    Dim isDirect As SQLITE_C_INT = 0
#else
    Dim isDirect As SQLITE_C_INT = IIf(directMode <> 0, 1, 0)
#endif

    If pPager->changeCountDone = 0 AndAlso pPager->dbSize > 0 Then
        If pPager->tempFile <> 0 OrElse pPager->fd = 0 OrElse _
           pPager->fd->pMethods = 0 Then Return SQLITE_MISUSE

        Dim pPage As PgHdr Ptr = 0
        Dim rc As SQLITE_C_INT = sqlite3PagerGet(pPager, 1, @pPage, 0)
        If rc = SQLITE_OK AndAlso pPage = 0 Then Return SQLITE_CORRUPT
        If rc = SQLITE_OK AndAlso isDirect = 0 Then rc = sqlite3PagerWrite(pPage)

        If rc = SQLITE_OK Then
            pager_write_changecounter(pPage)
            If isDirect <> 0 Then
                If pPager->dbFileSize = 0 OrElse pPage->pData = 0 Then
                    rc = SQLITE_MISUSE
                Else
                    rc = sqlite3OsWrite( _
                        pPager->fd, pPage->pData, CLng(pPager->pageSize), 0)
                    pPager->aStat(PAGER_STAT_WRITE) += 1
                    If rc = SQLITE_OK Then
                        Dim pData As Const UByte Ptr = CPtr(Const UByte Ptr, pPage->pData)
                        For versionByte As SQLITE_C_INT = 0 To 15
                            pPager->dbFileVers(versionByte) = pData[24 + versionByte]
                        Next
                        pPager->changeCountDone = 1
                    End If
                End If
            Else
                ' Keep dbFileVers at the last on-disk value until page 1 is written.
                pPager->changeCountDone = 1
            End If
        End If
        If pPage <> 0 Then sqlite3PagerUnrefNotNull(pPage)
        Return rc
    End If
    Return SQLITE_OK
End Function

Private Function pager_write_pagelist CDecl Alias "pager_write_pagelist" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pList As PgHdr Ptr _
) As SQLITE_C_INT
    If pPager = 0 Then Return SQLITE_MISUSE
#ifndef SQLITE_OMIT_WAL
    If pPager->pWal <> 0 Then Return SQLITE_MISUSE
#endif
    If pPager->tempFile = 0 AndAlso pPager->eState <> PAGER_WRITER_DBMOD Then _
        Return SQLITE_MISUSE
    If pPager->eLock <> EXCLUSIVE_LOCK Then Return SQLITE_BUSY
    If pPager->fd = 0 Then Return SQLITE_MISUSE

    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pPager->fd->pMethods = 0 Then
        If pPager->tempFile = 0 Then Return SQLITE_IOERR_WRITE
        rc = pagerOpentemp(pPager, pPager->fd, pPager->vfsFlags)
        If rc <> SQLITE_OK Then Return rc
    End If

    If pList <> 0 AndAlso pPager->dbHintSize < pPager->dbSize AndAlso _
       (pList->pDirty <> 0 OrElse pList->pgno > pPager->dbHintSize) Then
        Dim hintedFileSize As sqlite3_int64 = _
            CLngInt(pPager->pageSize) * CLngInt(pPager->dbSize)
        sqlite3OsFileControlHint( _
            pPager->fd, SQLITE_FCNTL_SIZE_HINT, @hintedFileSize)
        pPager->dbHintSize = pPager->dbSize
    End If

    While rc = SQLITE_OK AndAlso pList <> 0
        Dim pageNumber As u32 = pList->pgno
        If pageNumber <= pPager->dbSize AndAlso _
           (pList->flags And PGHDR_DONT_WRITE) = 0 Then
            If (pList->flags And PGHDR_NEED_SYNC) <> 0 Then Return SQLITE_MISUSE
            If pList->pData = 0 Then Return SQLITE_CORRUPT
            If pageNumber = 1 Then pager_write_changecounter(pList)

            Dim pageOffset As sqlite3_int64 = _
                (CLngInt(pageNumber) - 1) * CLngInt(pPager->pageSize)
            Dim pData As UByte Ptr = CPtr(UByte Ptr, pList->pData)
            rc = sqlite3OsWrite( _
                pPager->fd, pData, CLng(pPager->pageSize), pageOffset)

            If pageNumber = 1 Then
                For iByte As SQLITE_C_INT = 0 To 15
                    pPager->dbFileVers(iByte) = pData[24 + iByte]
                Next
            End If
            If pageNumber > pPager->dbFileSize Then pPager->dbFileSize = pageNumber
            pPager->aStat(PAGER_STAT_WRITE) += 1
            sqlite3BackupUpdate(pPager->pBackup, pageNumber, pData)
        End If

        pagerSetPageHash(pList)
        pList = pList->pDirty
    Wend
    Return rc
End Function

Private Function pagerWriteDirtyPages(ByVal pPager As Pager Ptr) As SQLITE_C_INT
    If pPager = 0 Then Return SQLITE_MISUSE
    If pPager->memDb <> 0 Then
        If pPager->pBackup <> 0 Then
            Dim pMemoryPage As PgHdr Ptr = _
                sqlite3PcacheDirtyList(pPager->pPCache)
            While pMemoryPage <> 0
                If pMemoryPage->pgno <= pPager->dbSize AndAlso _
                   (pMemoryPage->flags And PGHDR_DONT_WRITE) = 0 Then
                    sqlite3BackupUpdate(pPager->pBackup, pMemoryPage->pgno, _
                        CPtr(Const UByte Ptr, pMemoryPage->pData))
                End If
                pMemoryPage = pMemoryPage->pDirty
            Wend
        End If
        sqlite3PcacheCleanAll(pPager->pPCache)
        Return SQLITE_OK
    End If
    Dim pList As PgHdr Ptr = sqlite3PcacheDirtyList(pPager->pPCache)
    Dim rc As SQLITE_C_INT = pager_write_pagelist(pPager, pList)
    If rc <> SQLITE_OK Then Return rc
    sqlite3PcacheCleanAll(pPager->pPCache)
    Return SQLITE_OK
End Function

Private Function pagerStress CDecl ( _
    ByVal pArgument As Any Ptr, _
    ByVal pPage As PgHdr Ptr _
) As SQLITE_C_INT
    If pArgument = 0 OrElse pPage = 0 Then Return SQLITE_MISUSE
    Dim pPager As Pager Ptr = CPtr(Pager Ptr, pArgument)
    If pPage->pPager <> pPager OrElse (pPage->flags And PGHDR_DIRTY) = 0 Then Return SQLITE_CORRUPT
    If pPager->errCode <> SQLITE_OK Then Return SQLITE_OK
    If pPager->memDb <> 0 Then Return SQLITE_OK
    If (pPager->doNotSpill And (SPILLFLAG_ROLLBACK Or SPILLFLAG_OFF)) <> 0 Then Return SQLITE_OK
    If (pPager->doNotSpill And SPILLFLAG_NOSYNC) <> 0 AndAlso _
       (pPage->flags And PGHDR_NEED_SYNC) <> 0 Then Return SQLITE_OK

    ' Committed TEMP pages may remain dirty after a small commit and spill
    ' later, after the pager has returned to reader state.
    pPager->aStat(PAGER_STAT_SPILL) += 1
    pPage->pDirty = 0

    Dim rc As SQLITE_C_INT = SQLITE_OK
#ifndef SQLITE_OMIT_WAL
    If pPager->pWal <> 0 Then
        rc = pagerSubjournalPageIfRequired(pPage)
        If rc = SQLITE_OK Then rc = pagerWalFrames(pPager, pPage, 0, 0)
    Else
#endif
        If (pPage->flags And PGHDR_NEED_SYNC) <> 0 OrElse _
           pPager->eState = PAGER_WRITER_CACHEMOD Then
            rc = pagerSyncJournal(pPager, 1)
        End If
        If rc = SQLITE_OK Then
            ' The shared writer also updates page hashes and active backups.
            rc = pager_write_pagelist(pPager, pPage)
        End If
#ifndef SQLITE_OMIT_WAL
    End If
#endif

    If rc = SQLITE_OK Then sqlite3PcacheMakeClean(pPage)
    pagerSetError(pPager, rc)
    Return rc
End Function

Function sqlite3PagerFlush CDecl Alias "sqlite3PagerFlush" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT Export
    If pPager = 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = pPager->errCode
    If rc <> SQLITE_OK OrElse pPager->memDb <> 0 OrElse pPager->pPCache = 0 Then Return rc

    Dim pList As PgHdr Ptr = sqlite3PcacheDirtyList(pPager->pPCache)
    While rc = SQLITE_OK AndAlso pList <> 0
        Dim pNext As PgHdr Ptr = pList->pDirty
        If pList->nRef = 0 Then rc = pagerStress(pPager, pList)
        pList = pNext
    Wend
    Return rc
End Function

Private Function pagerZeroJournalHdr( _
    ByVal pPager As Pager Ptr, _
    ByVal doTruncate As SQLITE_C_INT _
) As SQLITE_C_INT
    If pPager = 0 OrElse pPager->jfd = 0 OrElse pPager->jfd->pMethods = 0 Then _
        Return SQLITE_MISUSE
    If sqlite3JournalIsInMemory(pPager->jfd) <> 0 Then Return SQLITE_MISUSE
    If pPager->journalOff = 0 Then Return SQLITE_OK

    Dim journalSizeLimit As sqlite3_int64 = pPager->journalSizeLimit
    Dim rc As SQLITE_C_INT = SQLITE_OK
    If doTruncate <> 0 OrElse journalSizeLimit = 0 Then
        rc = sqlite3OsTruncate(pPager->jfd, 0)
    Else
        Dim zeroHeader(0 To 27) As UByte
        For iByte As Long = 0 To 27
            zeroHeader(iByte) = 0
        Next
        rc = sqlite3OsWrite(pPager->jfd, @zeroHeader(0), 28, 0)
    End If

    If rc = SQLITE_OK AndAlso pPager->noSync = 0 Then
        rc = sqlite3OsSync( _
            pPager->jfd, SQLITE_SYNC_DATAONLY Or pPager->syncFlags)
    End If
    If rc = SQLITE_OK AndAlso journalSizeLimit > 0 Then
        Dim fileSize As sqlite3_int64 = 0
        rc = sqlite3OsFileSize(pPager->jfd, @fileSize)
        If rc = SQLITE_OK AndAlso fileSize > journalSizeLimit Then
            rc = sqlite3OsTruncate(pPager->jfd, journalSizeLimit)
        End If
    End If
    Return rc
End Function

Private Function pagerFinalizeJournal( _
    ByVal pPager As Pager Ptr, _
    ByVal hasSuperJournal As SQLITE_C_INT _
) As SQLITE_C_INT

    If pPager = 0 OrElse pPager->jfd = 0 OrElse pPager->jfd->pMethods = 0 Then _
        Return SQLITE_OK
    If sqlite3JournalIsInMemory(pPager->jfd) <> 0 Then
        sqlite3OsClose(pPager->jfd)
        Return SQLITE_OK
    End If

    Dim rc As SQLITE_C_INT = SQLITE_OK
    Select Case pPager->journalMode
    Case PAGER_JOURNALMODE_TRUNCATE
        If pPager->journalOff <> 0 Then
            rc = sqlite3OsTruncate(pPager->jfd, 0)
            If rc = SQLITE_OK AndAlso pPager->fullSync <> 0 Then
                rc = sqlite3OsSync(pPager->jfd, pPager->syncFlags)
            End If
        End If
        pPager->journalOff = 0
    Case PAGER_JOURNALMODE_PERSIST
        rc = pagerZeroJournalHdr( _
            pPager, IIf(hasSuperJournal <> 0 OrElse pPager->tempFile <> 0, 1, 0))
        pPager->journalOff = 0
    Case Else
        If pPager->exclusiveMode <> 0 AndAlso _
           pPager->journalMode < PAGER_JOURNALMODE_WAL Then
            rc = pagerZeroJournalHdr( _
                pPager, IIf(hasSuperJournal <> 0 OrElse pPager->tempFile <> 0, 1, 0))
            pPager->journalOff = 0
        Else
            sqlite3OsClose(pPager->jfd)
            If pPager->tempFile = 0 AndAlso pPager->zJournal <> 0 Then
                rc = sqlite3OsDelete(pPager->pVfs, pPager->zJournal, pPager->extraSync)
            End If
        End If
    End Select
    Return rc
End Function

Function sqlite3PagerSync CDecl Alias "sqlite3PagerSync" ( _
    ByVal pPager As Pager Ptr, _
    ByVal zSuperJournal As Const ZString Ptr _
) As SQLITE_C_INT Export

    If pPager = 0 Then Return SQLITE_MISUSE
    If pPager->memDb <> 0 OrElse pPager->noSync <> 0 OrElse _
       pPager->fd = 0 OrElse pPager->fd->pMethods = 0 Then Return SQLITE_OK
    Dim rc As SQLITE_C_INT = sqlite3OsFileControl(pPager->fd, SQLITE_FCNTL_SYNC, CPtr(Any Ptr, zSuperJournal))
    If rc = SQLITE_NOTFOUND Then rc = SQLITE_OK
    If rc = SQLITE_OK Then rc = sqlite3OsSync(pPager->fd, pPager->syncFlags)
    Return rc
End Function

Private Function pagerFlushOnCommit( _
    ByVal pPager As Pager Ptr, _
    ByVal isCommit As SQLITE_C_INT _
) As SQLITE_C_INT
    If pPager = 0 Then Return 0
    If pPager->tempFile = 0 Then Return 1
    If isCommit = 0 OrElse pPager->fd = 0 OrElse _
       pPager->fd->pMethods = 0 Then Return 0
    Return CInt(sqlite3PCachePercentDirty(pPager->pPCache) >= 25)
End Function

Function sqlite3PagerCommitPhaseOne CDecl Alias "sqlite3PagerCommitPhaseOne" ( _
    ByVal pPager As Pager Ptr, _
    ByVal zSuperJournal As Const ZString Ptr, _
    ByVal noSync As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pPager = 0 Then Return SQLITE_MISUSE
    If pPager->errCode <> SQLITE_OK Then Return pPager->errCode
    If pPager->eState = PAGER_WRITER_LOCKED Then Return SQLITE_OK
    If pPager->eState <> PAGER_WRITER_CACHEMOD AndAlso pPager->eState <> PAGER_WRITER_DBMOD Then Return SQLITE_MISUSE

    If pPager->pWal <> 0 Then
        ' WAL phase one appends the dirty page list as one committed frame set.
        Dim rcWal As SQLITE_C_INT = pagerWalCommitBridge(pPager)
        If rcWal <> SQLITE_OK Then pagerSetError(pPager, rcWal)
        Return rcWal
    End If

    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim flushOnCommit As SQLITE_C_INT = pagerFlushOnCommit(pPager, 1)

    If flushOnCommit = 0 Then
        ' In-memory databases and clean temporary files need no disk sync.
        ' Their cache pages still form the committed database image.
        sqlite3BackupRestart(pPager->pBackup)
        rc = SQLITE_OK
    Else
        rc = pager_incr_changecounter(pPager, 0)
    End If
    If flushOnCommit <> 0 Then
        If rc = SQLITE_OK Then rc = pagerAppendSuperJournal(pPager, zSuperJournal)
        If rc = SQLITE_OK Then rc = pagerSyncJournal(pPager, 0)
        If rc <> SQLITE_OK Then Return rc
        rc = pagerTryBusyLock(pPager, EXCLUSIVE_LOCK)
        If rc <> SQLITE_OK Then Return rc

        pPager->eState = PAGER_WRITER_DBMOD
        rc = pagerWriteDirtyPages(pPager)
        If rc = SQLITE_OK AndAlso pPager->dbSize > pPager->dbFileSize Then
            rc = pagerTruncateBridge(pPager, pPager->dbSize)
        End If
        If rc = SQLITE_OK AndAlso noSync = 0 Then _
            rc = sqlite3PagerSync(pPager, zSuperJournal)
    End If
    If rc = SQLITE_OK Then
        If pPager->pWal = 0 Then pPager->eState = PAGER_WRITER_FINISHED
        Return SQLITE_OK
    End If
    pagerSetError(pPager, rc)
    Return rc
End Function

Function sqlite3PagerCommitPhaseTwo CDecl Alias "sqlite3PagerCommitPhaseTwo" (ByVal pPager As Pager Ptr) As SQLITE_C_INT Export
    If pPager = 0 Then Return SQLITE_MISUSE
    If pPager->errCode <> SQLITE_OK Then Return pPager->errCode

    If pPager->pWal <> 0 Then
        pPager->iDataVersion += 1
        Dim rcWal As SQLITE_C_INT = _
            pagerEndTransactionBridge(pPager, pPager->setSuper, 1)
        pagerSetError(pPager, rcWal)
        Return rcWal
    End If

    If pPager->eState <> PAGER_WRITER_LOCKED AndAlso pPager->eState <> PAGER_WRITER_FINISHED Then Return SQLITE_MISUSE

    releaseAllSavepoints(pPager)
    Dim rc As SQLITE_C_INT = pagerFinalizeJournal(pPager, pPager->setSuper)
    If rc = SQLITE_OK AndAlso pPager->dbFileSize > pPager->dbSize Then
        rc = pagerTruncateBridge(pPager, pPager->dbSize)
    End If
    If pPager->pInJournal <> 0 Then sqlite3BitvecDestroy(pPager->pInJournal)
    pPager->pInJournal = 0
    If rc = SQLITE_OK Then
        If pPager->memDb <> 0 OrElse pagerFlushOnCommit(pPager, 1) <> 0 Then
            sqlite3PcacheCleanAll(pPager->pPCache)
        Else
            ' Keep small file-backed TEMP databases' dirty pages cached.
            sqlite3PcacheClearWritable(pPager->pPCache)
        End If
        sqlite3PcacheTruncate(pPager->pPCache, pPager->dbSize)
        pPager->dbOrigSize = pPager->dbSize
        pPager->dbFileSize = pPager->dbSize
        pPager->journalOff = 0
        pPager->journalHdr = 0
        pPager->nRec = 0
        pPager->setSuper = 0
        pPager->changeCountDone = pPager->tempFile
        pPager->iDataVersion += 1
        pPager->eState = PAGER_READER
        If pPager->exclusiveMode = 0 AndAlso pPager->noLock = 0 AndAlso pPager->fd <> 0 AndAlso _
           pPager->eLock > SHARED_LOCK Then
            rc = sqlite3OsUnlock(pPager->fd, SHARED_LOCK)
            If rc = SQLITE_OK Then pPager->eLock = SHARED_LOCK
        End If
    End If
    pagerSetError(pPager, rc)
    Return rc
End Function

Function sqlite3PagerRollback CDecl Alias "sqlite3PagerRollback" (ByVal pPager As Pager Ptr) As SQLITE_C_INT Export
    If pPager = 0 Then Return SQLITE_MISUSE
    If pPager->eState = PAGER_ERROR Then Return pPager->errCode
    If pPager->eState <= PAGER_READER Then Return SQLITE_OK

    If pPager->pWal <> 0 Then
        ' Restore the WAL snapshot before releasing the write transaction.
        Dim rcWal As SQLITE_C_INT = _
            sqlite3PagerSavepoint(pPager, SAVEPOINT_ROLLBACK, -1)
        Dim rcEnd As SQLITE_C_INT = _
            pagerEndTransactionBridge(pPager, pPager->setSuper, 0)
        If rcWal = SQLITE_OK Then rcWal = rcEnd
        pagerSetError(pPager, rcWal)
        Return rcWal
    End If

    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pPager->eState = PAGER_WRITER_LOCKED OrElse pPager->jfd = 0 OrElse _
       pPager->jfd->pMethods = 0 Then
        Dim previousState As UByte = pPager->eState
        rc = pagerEndTransactionBridge(pPager, 0, 0)
        If pPager->memDb = 0 AndAlso previousState > PAGER_WRITER_LOCKED Then
            pPager->errCode = SQLITE_ABORT
            pPager->eState = PAGER_ERROR
            pagerSetGetterMethod(pPager)
            Return rc
        End If
        pagerSetError(pPager, rc)
        Return rc
    Else
        ' A live rollback restores cached pages from the journal. It must not
        ' request an exclusive database lock just to undo uncommitted changes.
        rc = pagerPlaybackBridge(pPager, 0)
    End If

    pagerSetError(pPager, rc)
    Return rc
End Function

Private Function pagerPlaybackSavepoint(ByVal pPager As Pager Ptr, ByVal pSavepoint As PagerSavepoint Ptr) As SQLITE_C_INT
    If pPager = 0 Then Return SQLITE_MISUSE

    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim pDone As Any Ptr = 0
    Dim journalSize As sqlite3_int64 = pPager->journalOff
    Dim firstHeaderEnd As sqlite3_int64 = 0
    Dim nJournalRecords As u32 = 0
    Dim originalPageCount As u32 = 0

    If pSavepoint <> 0 Then
        pDone = sqlite3BitvecCreate(pSavepoint->nOrig)
        If pDone = 0 Then Return SQLITE_NOMEM
    End If

    If pSavepoint <> 0 Then
        pPager->dbSize = pSavepoint->nOrig
    Else
        pPager->dbSize = pPager->dbOrigSize
    End If
    pPager->changeCountDone = pPager->tempFile

#ifndef SQLITE_OMIT_WAL
    If pSavepoint = 0 AndAlso pPager->pWal <> 0 Then _
        Return pagerRollbackWalBridge(pPager)
#endif

    ' A savepoint can span several journal headers as cache spills append more
    ' records. Replay the saved segment first, then every later journal segment.
    journalSize = pPager->journalOff
    If pSavepoint <> 0 AndAlso pPager->pWal = 0 Then
        firstHeaderEnd = pSavepoint->iHdrOffset
        If firstHeaderEnd = 0 Then firstHeaderEnd = journalSize
        pPager->journalOff = pSavepoint->iOffset
        While rc = SQLITE_OK AndAlso pPager->journalOff < firstHeaderEnd
            rc = pager_playback_one_page( _
                pPager, @pPager->journalOff, pDone, 1, 1)
        Wend
    Else
        pPager->journalOff = 0
    End If

    While rc = SQLITE_OK AndAlso pPager->journalOff < journalSize
        originalPageCount = 0
        rc = readJournalHdr( _
            pPager, 0, journalSize, @nJournalRecords, @originalPageCount)
        If rc <> SQLITE_OK Then Exit While

        If nJournalRecords = 0 AndAlso _
           pPager->journalHdr + pPager->sectorSize = pPager->journalOff Then
            nJournalRecords = CUInt( _
                (journalSize - pPager->journalOff) \ (pPager->pageSize + 8))
        End If

        Dim iRecord As u32 = 0
        While rc = SQLITE_OK AndAlso iRecord < nJournalRecords AndAlso _
              pPager->journalOff < journalSize
            rc = pager_playback_one_page( _
                pPager, @pPager->journalOff, pDone, 1, 1)
            iRecord += 1
        Wend
    Wend

#ifndef SQLITE_OMIT_WAL
    If rc = SQLITE_OK AndAlso pSavepoint <> 0 AndAlso pPager->pWal <> 0 Then
        rc = sqlite3WalSavepointUndo( _
            pPager->pWal, @pSavepoint->aWalData(0))
    End If
#endif

    If rc = SQLITE_OK AndAlso pSavepoint <> 0 AndAlso _
       pPager->sjfd <> 0 AndAlso pPager->sjfd->pMethods <> 0 Then
        Dim subjournalOffset As sqlite3_int64 = _
            CLngInt(pSavepoint->iSubRec) * (4 + pPager->pageSize)
        Dim iSub As u32 = pSavepoint->iSubRec
        While rc = SQLITE_OK AndAlso iSub < pPager->nSubRec
            rc = pager_playback_one_page( _
                pPager, @subjournalOffset, pDone, 0, 1)
            If rc <> SQLITE_OK Then Exit While
            iSub += 1
        Wend
    End If

    If pDone <> 0 Then sqlite3BitvecDestroy(pDone)
    If rc = SQLITE_OK Then pPager->journalOff = journalSize
    Return rc
End Function

#ifdef SQLITE_DEBUG
' The debugger helper returns this process-wide buffer, which is overwritten
' on each call just like the static C buffer in src/pager.c.
Private Dim Shared pagerDebugStateBuffer As ZString * 1024
' The 320-byte allocation holds the complete fixed format string and terminator.
Private Dim Shared As Const ZString * 320 pagerDebugStateFormat = _
    !"Filename:      %s\n" & _
    !"State:         %s errCode=%d\n" & _
    !"Lock:          %s\n" & _
    !"Locking mode:  locking_mode=%s\n" & _
    !"Journal mode:  journal_mode=%s\n" & _
    !"Backing store: tempFile=%d memDb=%d useJournal=%d\n" & _
    !"Journal:       journalOff=%lld journalHdr=%lld\n" & _
    !"Size:          dbsize=%d dbOrigSize=%d dbFileSize=%d\n"

Function print_pager_state CDecl Alias "print_pager_state" ( _
    ByVal pPager As Pager Ptr _
) As ZString Ptr
    If pPager = 0 Then
        sqlite3_snprintf( _
            SizeOf(pagerDebugStateBuffer), @pagerDebugStateBuffer, _
            StrPtr(!"Pager: <null>\n"))
        Return @pagerDebugStateBuffer
    End If

    Dim zState As Const ZString Ptr = StrPtr("?error?")
    Select Case pPager->eState
    Case PAGER_OPEN
        zState = StrPtr("OPEN")
    Case PAGER_READER
        zState = StrPtr("READER")
    Case PAGER_WRITER_LOCKED
        zState = StrPtr("WRITER_LOCKED")
    Case PAGER_WRITER_CACHEMOD
        zState = StrPtr("WRITER_CACHEMOD")
    Case PAGER_WRITER_DBMOD
        zState = StrPtr("WRITER_DBMOD")
    Case PAGER_WRITER_FINISHED
        zState = StrPtr("WRITER_FINISHED")
    Case PAGER_ERROR
        zState = StrPtr("ERROR")
    End Select

    Dim zLock As Const ZString Ptr = StrPtr("?error?")
    Select Case pPager->eLock
    Case NO_LOCK
        zLock = StrPtr("NO_LOCK")
    Case RESERVED_LOCK
        zLock = StrPtr("RESERVED")
    Case EXCLUSIVE_LOCK
        zLock = StrPtr("EXCLUSIVE")
    Case SHARED_LOCK
        zLock = StrPtr("SHARED")
    Case UNKNOWN_LOCK
        zLock = StrPtr("UNKNOWN")
    End Select

    Dim zJournalMode As Const ZString Ptr = StrPtr("?error?")
    Select Case pPager->journalMode
    Case PAGER_JOURNALMODE_MEMORY
        zJournalMode = StrPtr("memory")
    Case PAGER_JOURNALMODE_OFF
        zJournalMode = StrPtr("off")
    Case PAGER_JOURNALMODE_DELETE
        zJournalMode = StrPtr("delete")
    Case PAGER_JOURNALMODE_PERSIST
        zJournalMode = StrPtr("persist")
    Case PAGER_JOURNALMODE_TRUNCATE
        zJournalMode = StrPtr("truncate")
    Case PAGER_JOURNALMODE_WAL
        zJournalMode = StrPtr("wal")
    End Select

    Dim zFilename As Const ZString Ptr = pPager->zFilename
    If zFilename = 0 Then zFilename = StrPtr("")
    Dim zLockingMode As Const ZString Ptr = _
        IIf(pPager->exclusiveMode <> 0, StrPtr("exclusive"), StrPtr("normal"))

    sqlite3_snprintf( _
        SizeOf(pagerDebugStateBuffer), @pagerDebugStateBuffer, _
        StrPtr(pagerDebugStateFormat), _
        zFilename, zState, pPager->errCode, zLock, zLockingMode, zJournalMode, _
        pPager->tempFile, pPager->memDb, pPager->useJournal, _
        pPager->journalOff, pPager->journalHdr, _
        Cast(SQLITE_C_INT, pPager->dbSize), _
        Cast(SQLITE_C_INT, pPager->dbOrigSize), _
        Cast(SQLITE_C_INT, pPager->dbFileSize))
    Return @pagerDebugStateBuffer
End Function

Private Function pagerDebugCheck( _
    ByVal condition As SQLITE_C_INT, _
    ByVal expression As Const ZString Ptr _
) As SQLITE_C_INT
    If condition = 0 Then
        sqlite3DebugAssert(expression)
        Return 0
    End If
    Return 1
End Function

Private Function pagerDebugFileIsOpen(ByVal pFile As sqlite3_file Ptr) As SQLITE_C_INT
    If pFile = 0 Then Return 0
    Return CInt(pFile->pMethods <> 0)
End Function

Private Function assert_pager_state CDecl Alias "assert_pager_state" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
    If pPager = 0 Then
        sqlite3DebugAssert(StrPtr("pPager != 0"))
        Return 0
    End If

    Dim usesWal As SQLITE_C_INT = 0
#ifndef SQLITE_OMIT_WAL
    usesWal = CInt(pPager->pWal <> 0)
#endif

    If pagerDebugCheck( _
        CInt(pPager->eState >= PAGER_OPEN AndAlso pPager->eState <= PAGER_ERROR), _
        StrPtr("Pager state is valid")) = 0 Then Return 0
    If pPager->pPCache = 0 Then
        sqlite3DebugAssert(StrPtr("pPager->pPCache != 0"))
        Return 0
    End If
    If pagerDebugCheck( _
        CInt(pPager->tempFile = 0 OrElse pPager->eLock = EXCLUSIVE_LOCK), _
        StrPtr("temporary pager holds an exclusive lock")) = 0 Then Return 0
    If pagerDebugCheck( _
        CInt(pPager->tempFile = 0 OrElse pPager->changeCountDone <> 0), _
        StrPtr("temporary pager has completed change-count handling")) = 0 Then Return 0
    If pagerDebugCheck( _
        CInt(pPager->journalMode = PAGER_JOURNALMODE_OFF OrElse pPager->useJournal <> 0), _
        StrPtr("journal mode OFF is the only mode without a journal")) = 0 Then Return 0
    If pagerDebugCheck( _
        CInt(pPager->journalMode <> PAGER_JOURNALMODE_OFF OrElse _
             pagerDebugFileIsOpen(pPager->jfd) = 0), _
        StrPtr("journal mode OFF has no open journal")) = 0 Then Return 0

    If pPager->memDb <> 0 Then
        If pagerDebugCheck(pagerDebugFileIsOpen(pPager->fd) = 0, _
            StrPtr("in-memory pager has no database file")) = 0 Then Return 0
        If pagerDebugCheck(pPager->noSync <> 0, _
            StrPtr("in-memory pager does not sync")) = 0 Then Return 0
        If pagerDebugCheck( _
            CInt(pPager->journalMode = PAGER_JOURNALMODE_OFF OrElse _
                 pPager->journalMode = PAGER_JOURNALMODE_MEMORY), _
            StrPtr("in-memory pager uses an in-memory journal mode")) = 0 Then Return 0
        If pagerDebugCheck( _
            CInt(pPager->eState <> PAGER_ERROR AndAlso pPager->eState <> PAGER_OPEN), _
            StrPtr("in-memory pager is outside ERROR and OPEN states")) = 0 Then Return 0
        If pagerDebugCheck(usesWal = 0, StrPtr("in-memory pager does not use WAL")) = 0 Then Return 0
    End If

    If pagerDebugCheck( _
        CInt(pPager->changeCountDone = 0 OrElse pPager->eLock >= RESERVED_LOCK), _
        StrPtr("change-count completion holds a RESERVED lock")) = 0 Then Return 0
    If pagerDebugCheck(pPager->eLock <> PENDING_LOCK, _
        StrPtr("pager does not retain a PENDING lock")) = 0 Then Return 0

    Select Case pPager->eState
    Case PAGER_OPEN
        If pagerDebugCheck(pPager->memDb = 0, StrPtr("OPEN pager is not MEMDB")) = 0 Then Return 0
        If pagerDebugCheck(pPager->errCode = SQLITE_OK, StrPtr("OPEN pager has no error")) = 0 Then Return 0
        If pagerDebugCheck( _
            CInt(sqlite3PcacheRefCount(pPager->pPCache) = 0 OrElse pPager->tempFile <> 0), _
            StrPtr("OPEN pager cache has no outstanding references")) = 0 Then Return 0
    Case PAGER_READER
        If pagerDebugCheck(pPager->errCode = SQLITE_OK, StrPtr("READER pager has no error")) = 0 Then Return 0
        If pagerDebugCheck(pPager->eLock <> UNKNOWN_LOCK, StrPtr("READER lock is known")) = 0 Then Return 0
        If pagerDebugCheck(pPager->eLock >= SHARED_LOCK, StrPtr("READER holds a shared lock")) = 0 Then Return 0
    Case PAGER_WRITER_LOCKED
        If pagerDebugCheck(pPager->eLock <> UNKNOWN_LOCK, StrPtr("writer lock is known")) = 0 Then Return 0
        If pagerDebugCheck(pPager->errCode = SQLITE_OK, StrPtr("locked writer has no error")) = 0 Then Return 0
        If usesWal = 0 AndAlso _
           pagerDebugCheck(pPager->eLock >= RESERVED_LOCK, StrPtr("rollback writer holds RESERVED")) = 0 Then Return 0
        If pagerDebugCheck(pPager->dbSize = pPager->dbOrigSize, StrPtr("database size matches original")) = 0 Then Return 0
        If pagerDebugCheck(pPager->dbOrigSize = pPager->dbFileSize, StrPtr("original size matches file size")) = 0 Then Return 0
        If pagerDebugCheck(pPager->dbOrigSize = pPager->dbHintSize, StrPtr("original size matches hinted size")) = 0 Then Return 0
        If pagerDebugCheck(pPager->setSuper = 0, StrPtr("no super-journal is set before modification")) = 0 Then Return 0
    Case PAGER_WRITER_CACHEMOD
        If pagerDebugCheck(pPager->eLock <> UNKNOWN_LOCK, StrPtr("cache-mod lock is known")) = 0 Then Return 0
        If pagerDebugCheck(pPager->errCode = SQLITE_OK, StrPtr("cache-mod writer has no error")) = 0 Then Return 0
        If usesWal = 0 Then
            If pagerDebugCheck(pPager->eLock >= RESERVED_LOCK, _
                StrPtr("rollback cache-mod writer holds RESERVED")) = 0 Then Return 0
            If pagerDebugCheck( _
                CInt(pagerDebugFileIsOpen(pPager->jfd) <> 0 OrElse _
                     pPager->journalMode = PAGER_JOURNALMODE_OFF OrElse _
                     pPager->journalMode = PAGER_JOURNALMODE_WAL), _
                StrPtr("cache-mod writer has a journal or an allowed mode")) = 0 Then Return 0
        End If
        If pagerDebugCheck(pPager->dbOrigSize = pPager->dbFileSize, _
            StrPtr("cache-mod original size matches file size")) = 0 Then Return 0
        If pagerDebugCheck(pPager->dbOrigSize = pPager->dbHintSize, _
            StrPtr("cache-mod original size matches hinted size")) = 0 Then Return 0
    Case PAGER_WRITER_DBMOD
        If pagerDebugCheck(pPager->eLock = EXCLUSIVE_LOCK, _
            StrPtr("database-modifying writer holds EXCLUSIVE")) = 0 Then Return 0
        If pagerDebugCheck(pPager->errCode = SQLITE_OK, _
            StrPtr("database-modifying writer has no error")) = 0 Then Return 0
        If pagerDebugCheck(usesWal = 0, _
            StrPtr("database-modifying writer does not use WAL")) = 0 Then Return 0
        If pagerDebugCheck(pPager->eLock >= EXCLUSIVE_LOCK, _
            StrPtr("database-modifying writer holds EXCLUSIVE or greater")) = 0 Then Return 0
        If pagerDebugFileIsOpen(pPager->jfd) = 0 AndAlso _
           pPager->journalMode <> PAGER_JOURNALMODE_OFF AndAlso _
           pPager->journalMode <> PAGER_JOURNALMODE_WAL Then
            If pPager->fd = 0 Then
                sqlite3DebugAssert(StrPtr("atomic batch mode has an open database file"))
                Return 0
            End If
            If pagerDebugCheck( _
                (sqlite3OsDeviceCharacteristics(pPager->fd) And SQLITE_IOCAP_BATCH_ATOMIC) <> 0, _
                StrPtr("database file supports atomic batches")) = 0 Then Return 0
        End If
        If pagerDebugCheck(pPager->dbOrigSize <= pPager->dbHintSize, _
            StrPtr("original size does not exceed hinted size")) = 0 Then Return 0
    Case PAGER_WRITER_FINISHED
        If pagerDebugCheck(pPager->eLock = EXCLUSIVE_LOCK, _
            StrPtr("finished writer holds EXCLUSIVE")) = 0 Then Return 0
        If pagerDebugCheck(pPager->errCode = SQLITE_OK, _
            StrPtr("finished writer has no error")) = 0 Then Return 0
        If pagerDebugCheck(usesWal = 0, _
            StrPtr("finished writer does not use WAL")) = 0 Then Return 0
        If pagerDebugFileIsOpen(pPager->jfd) = 0 AndAlso _
           pPager->journalMode <> PAGER_JOURNALMODE_OFF AndAlso _
           pPager->journalMode <> PAGER_JOURNALMODE_WAL Then
            If pPager->fd = 0 Then
                sqlite3DebugAssert(StrPtr("atomic batch mode has an open database file"))
                Return 0
            End If
            If pagerDebugCheck( _
                (sqlite3OsDeviceCharacteristics(pPager->fd) And SQLITE_IOCAP_BATCH_ATOMIC) <> 0, _
                StrPtr("database file supports atomic batches")) = 0 Then Return 0
        End If
    Case PAGER_ERROR
        If pagerDebugCheck(pPager->errCode <> SQLITE_OK, _
            StrPtr("ERROR pager has a non-OK error")) = 0 Then Return 0
        If pagerDebugCheck( _
            CInt(sqlite3PcacheRefCount(pPager->pPCache) > 0 OrElse pPager->tempFile <> 0), _
            StrPtr("ERROR pager retains a cache reference or is temporary")) = 0 Then Return 0
    End Select
    Return 1
End Function

Private Sub assertTruncateConstraintCb CDecl Alias "assertTruncateConstraintCb" ( _
    ByVal pPage As PgHdr Ptr _
)
    If pPage = 0 Then
        sqlite3DebugAssert(StrPtr("pPg != 0"))
        Exit Sub
    End If
    Dim pPager As Pager Ptr = pPage->pPager
    If pPager = 0 Then
        sqlite3DebugAssert(StrPtr("pPg->pPager != 0"))
        Exit Sub
    End If
    If (pPage->flags And PGHDR_DIRTY) = 0 Then
        sqlite3DebugAssert(StrPtr("(pPg->flags & PGHDR_DIRTY) != 0"))
        Exit Sub
    End If

    If pPage->pgno > pPager->dbSize Then
        If pPager->nSavepoint > 0 AndAlso pPager->aSavepoint = 0 Then
            sqlite3DebugAssert(StrPtr("pPager->aSavepoint != 0"))
            Exit Sub
        End If
        For iSavepoint As SQLITE_C_INT = 0 To pPager->nSavepoint - 1
            Dim pSavepoint As PagerSavepoint Ptr = @pPager->aSavepoint[iSavepoint]
            If pSavepoint->nOrig >= pPage->pgno AndAlso _
               sqlite3BitvecTestNotNull(pSavepoint->pInSavepoint, pPage->pgno) = 0 Then
                sqlite3DebugAssert( _
                    StrPtr("p->nOrig < pgno || sqlite3BitvecTestNotNull(p->pInSavepoint, pgno)"))
                Exit Sub
            End If
        Next
    End If
End Sub

Private Sub assertTruncateConstraint CDecl Alias "assertTruncateConstraint" ( _
    ByVal pPager As Pager Ptr _
)
    If pPager = 0 OrElse pPager->pPCache = 0 Then
        sqlite3DebugAssert(StrPtr("pPager != 0 && pPager->pPCache != 0"))
        Exit Sub
    End If
    sqlite3PcacheIterateDirty(pPager->pPCache, _
        CPtr(SqlitePcacheIterateProc, ProcPtr(assertTruncateConstraintCb)))
End Sub
#endif

Private Function pagerOpenSavepoint CDecl Alias "pagerOpenSavepoint" ( _
    ByVal pPager As Pager Ptr, _
    ByVal nSavepoint As SQLITE_C_INT _
) As SQLITE_C_INT
    If pPager = 0 Then Return SQLITE_MISUSE
    If nSavepoint <= pPager->nSavepoint OrElse pPager->useJournal = 0 OrElse _
       pPager->eState < PAGER_WRITER_LOCKED Then Return SQLITE_MISUSE
    Dim nCurrent As SQLITE_C_INT = pPager->nSavepoint
    Dim savepointCount As sqlite3_uint64 = CULngInt(nSavepoint)
    If savepointCount > SQLITE_MAX_ALLOCATION_SIZE \ SizeOf(PagerSavepoint) Then _
        Return SQLITE_NOMEM
    Dim allocationSize As sqlite3_uint64 = _
        savepointCount * SizeOf(PagerSavepoint)
    Dim pNew As PagerSavepoint Ptr = CPtr( _
        PagerSavepoint Ptr, sqlite3Realloc(pPager->aSavepoint, allocationSize))
    If pNew = 0 Then Return SQLITE_NOMEM
    pPager->aSavepoint = pNew

    ' Clear the expanded portion before any nested Bitvec allocation can fail.
    For iSavepoint As SQLITE_C_INT = nCurrent To nSavepoint - 1
        Dim pSave As PagerSavepoint Ptr = @pPager->aSavepoint[iSavepoint]
        pSave->iOffset = 0
        pSave->iHdrOffset = 0
        pSave->pInSavepoint = 0
        pSave->nOrig = 0
        pSave->iSubRec = 0
        pSave->bTruncateOnRelease = 0
#ifndef SQLITE_OMIT_WAL
        For iWal As SQLITE_C_INT = 0 To 3
            pSave->aWalData(iWal) = 0
        Next
#endif
    Next

    For iSavepoint As SQLITE_C_INT = nCurrent To nSavepoint - 1
        Dim pSave As PagerSavepoint Ptr = @pPager->aSavepoint[iSavepoint]
        pSave->nOrig = pPager->dbSize
        If pPager->jfd <> 0 AndAlso pPager->jfd->pMethods <> 0 AndAlso _
           pPager->journalOff > 0 Then
            pSave->iOffset = pPager->journalOff
        Else
            pSave->iOffset = pPager->sectorSize
        End If
        pSave->iSubRec = pPager->nSubRec
        pSave->pInSavepoint = sqlite3BitvecCreate(pPager->dbSize)
        pSave->bTruncateOnRelease = 1
        If pSave->pInSavepoint = 0 Then Return SQLITE_NOMEM
#ifndef SQLITE_OMIT_WAL
        If pPager->pWal <> 0 Then
            sqlite3WalSavepoint(pPager->pWal, @pSave->aWalData(0))
        End If
#endif
        pPager->nSavepoint = iSavepoint + 1
    Next
#ifdef SQLITE_DEBUG
    If pPager->nSavepoint <> nSavepoint Then
        sqlite3DebugAssert(StrPtr("pPager->nSavepoint == nSavepoint"))
        Return SQLITE_CORRUPT
    End If
    assertTruncateConstraint(pPager)
#endif
    Return SQLITE_OK
End Function

Function sqlite3PagerOpenSavepoint CDecl Alias "sqlite3PagerOpenSavepoint" ( _
    ByVal pPager As Pager Ptr, _
    ByVal nSavepoint As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pPager = 0 OrElse nSavepoint < 0 Then Return SQLITE_MISUSE
    If pPager->eState < PAGER_WRITER_LOCKED OrElse pPager->eState >= PAGER_ERROR Then _
        Return SQLITE_MISUSE
#ifdef SQLITE_DEBUG
    If assert_pager_state(pPager) = 0 Then Return SQLITE_CORRUPT
#endif
    If nSavepoint > pPager->nSavepoint AndAlso pPager->useJournal <> 0 Then _
        Return pagerOpenSavepoint(pPager, nSavepoint)
    Return SQLITE_OK
End Function

Private Sub freeSuperJournal CDecl Alias "freeSuperJournal" ( _
    ByVal zSuperJournal As ZString Ptr _
)
    If zSuperJournal <> 0 Then
        ' readSuperJournal() stores a four-byte length immediately before text.
        sqlite3_free(@zSuperJournal[-4])
    End If
End Sub

Private Sub pager_reset CDecl Alias "pager_reset" (ByVal pPager As Pager Ptr)
    If pPager = 0 Then Exit Sub
    pPager->iDataVersion += 1
    sqlite3BackupRestart(pPager->pBackup)
    sqlite3PcacheClear(pPager->pPCache)
End Sub

Private Sub releaseAllSavepoints CDecl Alias "releaseAllSavepoints" ( _
    ByVal pPager As Pager Ptr _
)
    If pPager = 0 Then Exit Sub
    For iSave As Long = 0 To pPager->nSavepoint - 1
        If pPager->aSavepoint[iSave].pInSavepoint <> 0 Then
            sqlite3BitvecDestroy(pPager->aSavepoint[iSave].pInSavepoint)
        End If
    Next
    If pPager->aSavepoint <> 0 Then sqlite3_free(pPager->aSavepoint)
    pPager->aSavepoint = 0
    pPager->nSavepoint = 0
    pPager->nSubRec = 0
    If pPager->exclusiveMode = 0 OrElse sqlite3JournalIsInMemory(pPager->sjfd) <> 0 Then
        If pPager->sjfd <> 0 AndAlso pPager->sjfd->pMethods <> 0 Then
            sqlite3OsClose(pPager->sjfd)
        End If
    End If
End Sub

Private Sub pager_unlock CDecl Alias "pager_unlock" ( _
    ByVal pPager As Pager Ptr _
)
    If pPager = 0 Then Exit Sub

    sqlite3BitvecDestroy(pPager->pInJournal)
    pPager->pInJournal = 0
    releaseAllSavepoints(pPager)

#ifndef SQLITE_OMIT_WAL
    If pPager->pWal <> 0 Then
        If pPager->eState = PAGER_ERROR Then _
            sqlite3WalEndWriteTransaction(pPager->pWal)
        sqlite3WalEndReadTransaction(pPager->pWal)
        pPager->eState = PAGER_OPEN
    ElseIf pPager->exclusiveMode = 0 Then
#else
    If pPager->exclusiveMode = 0 Then
#endif
        Dim deviceCharacteristics As SQLITE_C_INT = 0
        If pPager->fd <> 0 AndAlso pPager->fd->pMethods <> 0 Then _
            deviceCharacteristics = sqlite3OsDeviceCharacteristics(pPager->fd)

        If (deviceCharacteristics And SQLITE_IOCAP_UNDELETABLE_WHEN_OPEN) = 0 OrElse _
           (pPager->journalMode And 5) <> PAGER_JOURNALMODE_PERSIST Then
            If pPager->jfd <> 0 Then sqlite3OsClose(pPager->jfd)
        End If

        Dim unlockResult As SQLITE_C_INT = pagerUnlockDb(pPager, NO_LOCK)
        If unlockResult <> SQLITE_OK AndAlso pPager->eState = PAGER_ERROR Then _
            pPager->eLock = UNKNOWN_LOCK
        pPager->eState = PAGER_OPEN
    End If

    If pPager->errCode <> SQLITE_OK Then
        If pPager->tempFile = 0 Then
            pager_reset(pPager)
            pPager->changeCountDone = 0
            pPager->eState = PAGER_OPEN
        ElseIf pPager->jfd <> 0 AndAlso pPager->jfd->pMethods <> 0 Then
            pPager->eState = PAGER_OPEN
        Else
            pPager->eState = PAGER_READER
        End If
#if SQLITE_MAX_MMAP_SIZE > 0
        If pPager->bUseFetch <> 0 Then sqlite3OsUnfetch(pPager->fd, 0, 0)
#endif
        pPager->errCode = SQLITE_OK
        pagerSetGetterMethod(pPager)
    End If

    pPager->journalOff = 0
    pPager->journalHdr = 0
    pPager->setSuper = 0
End Sub

Private Function pagerSyncHotJournal CDecl Alias "pagerSyncHotJournal" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
    If pPager = 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pPager->noSync = 0 Then
        rc = sqlite3OsSync(pPager->jfd, SQLITE_SYNC_NORMAL)
    End If
    If rc = SQLITE_OK Then
        rc = sqlite3OsFileSize(pPager->jfd, @pPager->journalHdr)
    End If
    Return rc
End Function

Function sqlite3PagerSavepoint CDecl Alias "sqlite3PagerSavepoint" ( _
    ByVal pPager As Pager Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal savepointIndex As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pPager = 0 Then Return SQLITE_MISUSE
    If operation <> SAVEPOINT_RELEASE AndAlso operation <> SAVEPOINT_ROLLBACK Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = pPager->errCode
#ifdef SQLITE_ENABLE_ZIPVFS
    If operation = SAVEPOINT_RELEASE Then rc = SQLITE_OK
#endif
    If rc <> SQLITE_OK Then Return rc
    If savepointIndex < 0 Then
        If operation = SAVEPOINT_RELEASE Then Return SQLITE_MISUSE
        Return pagerPlaybackSavepoint(pPager, 0)
    End If
    If savepointIndex >= pPager->nSavepoint Then Return SQLITE_OK

    Dim nNew As SQLITE_C_INT = savepointIndex + IIf(operation = SAVEPOINT_RELEASE, 0, 1)
    Dim pReleased As PagerSavepoint Ptr = 0
    If operation = SAVEPOINT_RELEASE Then pReleased = @pPager->aSavepoint[nNew]
    For iSave As Long = nNew To pPager->nSavepoint - 1
        If pPager->aSavepoint[iSave].pInSavepoint <> 0 Then
            sqlite3BitvecDestroy(pPager->aSavepoint[iSave].pInSavepoint)
            pPager->aSavepoint[iSave].pInSavepoint = 0
        End If
    Next
    pPager->nSavepoint = nNew

    If operation = SAVEPOINT_RELEASE Then
        If pReleased->bTruncateOnRelease <> 0 AndAlso pPager->sjfd <> 0 AndAlso pPager->sjfd->pMethods <> 0 Then
            If sqlite3JournalIsInMemory(pPager->sjfd) <> 0 Then
                Dim subjournalSize As sqlite3_int64 = _
                    CLngInt(pReleased->iSubRec) * (4 + pPager->pageSize)
                Dim rcTruncate As SQLITE_C_INT = _
                    sqlite3OsTruncate(pPager->sjfd, subjournalSize)
                If rcTruncate <> SQLITE_OK Then Return rcTruncate
            End If
            pPager->nSubRec = pReleased->iSubRec
        End If
        Return SQLITE_OK
    End If

    Dim pSave As PagerSavepoint Ptr = @pPager->aSavepoint[nNew - 1]
    Return pagerPlaybackSavepoint(pPager, pSave)
End Function

Function sqlite3PagerIswriteable CDecl Alias "sqlite3PagerIswriteable" (ByVal pPage As PgHdr Ptr) As SQLITE_C_INT Export
    If pPage = 0 Then Return 0
    Return IIf((pPage->flags And PGHDR_WRITEABLE) <> 0, 1, 0)
End Function

Sub sqlite3PagerDontWrite CDecl Alias "sqlite3PagerDontWrite" (ByVal pPage As PgHdr Ptr) Export
    If pPage = 0 OrElse pPage->pPager = 0 Then Exit Sub
    Dim pPager As Pager Ptr = CPtr(Pager Ptr, pPage->pPager)
    If pPager->tempFile = 0 AndAlso (pPage->flags And PGHDR_DIRTY) <> 0 AndAlso pPager->nSavepoint = 0 Then
        pPage->flags = pPage->flags Or PGHDR_DONT_WRITE
        pPage->flags = pPage->flags And Not PGHDR_WRITEABLE
    End If
End Sub

Function sqlite3PagerSharedLock CDecl Alias "sqlite3PagerSharedLock" (ByVal pPager As Pager Ptr) As SQLITE_C_INT Export
    If pPager = 0 Then Return SQLITE_MISUSE
    If pPager->errCode <> SQLITE_OK Then Return pPager->errCode

    Dim rc As SQLITE_C_INT = SQLITE_OK
#ifndef SQLITE_OMIT_WAL
    If pPager->pWal = 0 AndAlso pPager->eState >= PAGER_READER Then Return SQLITE_OK
    If pPager->pWal = 0 AndAlso pPager->eState = PAGER_OPEN Then
#else
    If pPager->eState >= PAGER_READER Then Return SQLITE_OK
    If pPager->eState = PAGER_OPEN Then
#endif
        If pPager->tempFile <> 0 Then
            ' An error can leave a temp pager in OPEN state with its journal
            ' still active. Replay it before allowing the next reader to use
            ' the cache, even though temp files do not need an OS shared lock.
            If pPager->eState = PAGER_OPEN AndAlso pPager->jfd <> 0 AndAlso _
               pPager->jfd->pMethods <> 0 Then
                rc = pagerSyncHotJournal(pPager)
                If rc = SQLITE_OK Then rc = pagerPlaybackBridge(pPager, 0)
                pPager->eState = PAGER_OPEN
                If rc <> SQLITE_OK Then
                    pagerSetError(pPager, rc)
                    pager_unlock(pPager)
                    Return rc
                End If
            End If
            pPager->eState = PAGER_READER
            pPager->hasHeldSharedLock = 1
            Return SQLITE_OK
        End If
        If pPager->memDb <> 0 OrElse _
           pPager->fd = 0 OrElse pPager->fd->pMethods = 0 Then
            pPager->eState = PAGER_READER
            pPager->hasHeldSharedLock = 1
            Return SQLITE_OK
        End If

        rc = pagerTryBusyLock(pPager, SHARED_LOCK)
        If rc <> SQLITE_OK Then GoTo pager_shared_lock_error

        If pPager->useJournal <> 0 AndAlso pPager->zJournal <> 0 Then
            rc = pagerHotJournal(pPager)
            If rc <> SQLITE_OK Then GoTo pager_shared_lock_error
        End If

        If pPager->hasHeldSharedLock <> 0 Then
            Dim fileVersion(0 To 15) As UByte
            rc = sqlite3OsRead(pPager->fd, @fileVersion(0), 16, PAGER_FILE_VERSION_OFFSET)
            If rc = SQLITE_IOERR_SHORT_READ Then
                For i As Long = 0 To 15
                    fileVersion(i) = 0
                Next
                rc = SQLITE_OK
            End If
            If rc <> SQLITE_OK Then GoTo pager_shared_lock_error
            Dim changed As SQLITE_C_INT = 0
            For i As Long = 0 To 15
                If fileVersion(i) <> pPager->dbFileVers(i) Then changed = 1
            Next
            If changed <> 0 Then pager_reset(pPager)
        End If

#ifndef SQLITE_OMIT_WAL
        rc = pagerOpenWalIfPresent(pPager)
        If rc <> SQLITE_OK Then GoTo pager_shared_lock_error
#endif
    End If

#ifndef SQLITE_OMIT_WAL
    If pPager->pWal <> 0 Then
        rc = pagerBeginReadTransaction(pPager)
        If rc <> SQLITE_OK Then GoTo pager_shared_lock_error
    End If
#endif

    If pPager->tempFile = 0 AndAlso pPager->eState = PAGER_OPEN Then
        rc = pagerPagecount(pPager, @pPager->dbSize)
        If rc <> SQLITE_OK Then GoTo pager_shared_lock_error
    End If

    pPager->eState = PAGER_READER
    pPager->hasHeldSharedLock = 1
    Return SQLITE_OK

pager_shared_lock_error:
    pager_unlock(pPager)
    Return rc
End Function

Function sqlite3PagerGet CDecl Alias "sqlite3PagerGet" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pageNumber As u32, _
    ByVal ppPage As PgHdr Ptr Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pPager = 0 OrElse ppPage = 0 Then Return SQLITE_MISUSE
    Dim xGet As SqlitePagerGetProc = CPtr(SqlitePagerGetProc, pPager->xGet)
    If xGet = 0 Then
        ppPage[0] = 0
        Return SQLITE_ERROR
    End If
    Return xGet(pPager, pageNumber, ppPage, flags)
End Function

Function sqlite3PagerLookup CDecl Alias "sqlite3PagerLookup" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pageNumber As u32 _
) As PgHdr Ptr Export

    If pPager = 0 OrElse pPager->pPCache = 0 OrElse pageNumber = 0 Then Return 0
    Dim pBase As sqlite3_pcache_page Ptr = sqlite3PcacheFetch(pPager->pPCache, pageNumber, 0)
    If pBase = 0 Then Return 0
    Return sqlite3PcacheFetchFinish(pPager->pPCache, pageNumber, pBase)
End Function

Sub sqlite3PagerRef CDecl Alias "sqlite3PagerRef" (ByVal pPage As PgHdr Ptr) Export
    sqlite3PcacheRef(pPage)
End Sub

Sub sqlite3PagerUnrefNotNull CDecl Alias "sqlite3PagerUnrefNotNull" (ByVal pPage As PgHdr Ptr) Export
    If pPage = 0 Then Exit Sub
    If (pPage->flags And PGHDR_MMAP) <> 0 Then
        pagerReleaseMapPage(pPage)
    Else
        sqlite3PcacheRelease(pPage)
    End If
End Sub

Sub sqlite3PagerUnref CDecl Alias "sqlite3PagerUnref" (ByVal pPage As PgHdr Ptr) Export
    If pPage <> 0 Then sqlite3PagerUnrefNotNull(pPage)
End Sub

Sub sqlite3PagerUnrefPageOne CDecl Alias "sqlite3PagerUnrefPageOne" (ByVal pPage As PgHdr Ptr) Export
    If pPage = 0 Then Exit Sub
    Dim pPager As Pager Ptr = CPtr(Pager Ptr, pPage->pPager)
    sqlite3PagerUnrefNotNull(pPage)
    pagerUnlockIfUnused(pPager)
End Sub

Function sqlite3PagerPageRefcount CDecl Alias "sqlite3PagerPageRefcount" (ByVal pPage As PgHdr Ptr) As SQLITE_C_INT Export
    If pPage = 0 Then Return 0
    Return CLng(sqlite3PcachePageRefcount(pPage))
End Function

Function sqlite3PagerGetData CDecl Alias "sqlite3PagerGetData" (ByVal pPage As PgHdr Ptr) As Any Ptr Export
    If pPage = 0 Then Return 0
    Return pPage->pData
End Function

Function sqlite3PagerGetExtra CDecl Alias "sqlite3PagerGetExtra" (ByVal pPage As PgHdr Ptr) As Any Ptr Export
    If pPage = 0 Then Return 0
    Return pPage->pExtra
End Function

Sub sqlite3PagerPagecount CDecl Alias "sqlite3PagerPagecount" (ByVal pPager As Pager Ptr, ByVal pCount As SQLITE_C_INT Ptr) Export
    If pCount = 0 Then Exit Sub
    If pPager = 0 Then
        pCount[0] = 0
    ElseIf pPager->dbSize > &H7FFFFFFF Then
        pCount[0] = &H7FFFFFFF
    Else
        pCount[0] = CLng(pPager->dbSize)
    End If
End Sub

Function sqlite3PagerReadFileheader CDecl Alias "sqlite3PagerReadFileheader" ( _
    ByVal pPager As Pager Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal pDestination As UByte Ptr _
) As SQLITE_C_INT Export

    If pPager = 0 OrElse amount < 0 OrElse (amount > 0 AndAlso pDestination = 0) Then Return SQLITE_MISUSE
    For i As Long = 0 To amount - 1
        pDestination[i] = 0
    Next
    If pPager->fd = 0 OrElse pPager->fd->pMethods = 0 Then Return SQLITE_OK
    Dim rc As SQLITE_C_INT = sqlite3OsRead(pPager->fd, pDestination, amount, 0)
    If rc = SQLITE_IOERR_SHORT_READ Then Return SQLITE_OK
    Return rc
End Function

Private Sub setSectorSize CDecl Alias "setSectorSize" (ByVal pPager As Pager Ptr)
    If pPager = 0 Then Exit Sub
    If pPager->tempFile <> 0 OrElse pPager->fd = 0 OrElse pPager->fd->pMethods = 0 Then
        pPager->sectorSize = 512
    ElseIf (sqlite3OsDeviceCharacteristics(pPager->fd) And _
            SQLITE_IOCAP_POWERSAFE_OVERWRITE) <> 0 Then
        pPager->sectorSize = 512
    Else
        pPager->sectorSize = sqlite3SectorSize(pPager->fd)
    End If
End Sub

Function sqlite3PagerSetPagesize CDecl Alias "sqlite3PagerSetPagesize" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pPageSize As u32 Ptr, _
    ByVal nReserve As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pPager = 0 OrElse pPageSize = 0 Then Return SQLITE_MISUSE
    Dim pageSize As u32 = pPageSize[0]
    If pageSize <> 0 AndAlso (pageSize < 512 OrElse pageSize > SQLITE_MAX_PAGE_SIZE OrElse (pageSize And (pageSize - 1)) <> 0) Then Return SQLITE_MISUSE
    If pageSize = 0 Then pageSize = CULng(pPager->pageSize)
    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pageSize <> CULng(pPager->pageSize) AndAlso pPager->pPCache <> 0 AndAlso _
       sqlite3PcacheRefCount(pPager->pPCache) = 0 Then
        Dim pNew As UByte Ptr = CPtr(UByte Ptr, sqlite3PageMalloc(CLng(pageSize) + 8))
        If pNew = 0 Then Return SQLITE_NOMEM
        Dim nFile As sqlite3_int64 = 0
        If pPager->eState > PAGER_OPEN AndAlso pPager->fd <> 0 AndAlso pPager->fd->pMethods <> 0 Then
            rc = sqlite3OsFileSize(pPager->fd, @nFile)
        End If
        If rc = SQLITE_OK Then pager_reset(pPager)
        If rc = SQLITE_OK Then rc = sqlite3PcacheSetPageSize(pPager->pPCache, CLng(pageSize))
        If rc = SQLITE_OK Then
            For i As Long = 0 To 7
                pNew[pageSize + i] = 0
            Next
            sqlite3PageFree(pPager->pTmpSpace)
            pPager->pTmpSpace = pNew
            pPager->pageSize = pageSize
            pPager->dbSize = IIf(nFile > 0, CULng((CULngInt(nFile) + pageSize - 1) \ pageSize), 0)
            pPager->lckPgno = (PENDING_BYTE \ pageSize) + 1
        Else
            sqlite3PageFree(pNew)
        End If
    End If
    If nReserve >= 0 Then
        If nReserve >= 1000 Then Return SQLITE_MISUSE
        pPager->nReserve = CShort(nReserve)
    End If
    pPageSize[0] = CULng(pPager->pageSize)
    If rc = SQLITE_OK Then pagerFixMaplimit(pPager)
    Return rc
End Function

Sub sqlite3PagerSetBusyHandler CDecl Alias "sqlite3PagerSetBusyHandler" ( _
    ByVal pPager As Pager Ptr, _
    ByVal xBusy As SqlitePagerBusyProc, _
    ByVal pArgument As Any Ptr _
) Export
    If pPager = 0 Then Exit Sub
    pPager->xBusyHandler = xBusy
    pPager->pBusyHandlerArg = pArgument
End Sub

Function sqlite3PagerClose CDecl Alias "sqlite3PagerClose" (ByVal pPager As Pager Ptr, ByVal db As Any Ptr) As SQLITE_C_INT Export
    If pPager = 0 Then Return SQLITE_OK
    If pPager->pPCache <> 0 AndAlso sqlite3PcacheRefCount(pPager->pPCache) <> 0 Then Return SQLITE_BUSY
    Dim pDatabase As sqlite3 Ptr = CPtr(sqlite3 Ptr, db)
#ifdef SQLITE_TEST
    disable_simulated_io_errors()
#endif
    sqlite3BeginBenignMalloc()
    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pPager->eState >= PAGER_WRITER_LOCKED AndAlso pPager->errCode = SQLITE_OK Then
        rc = sqlite3PagerRollback(pPager)
    ElseIf pPager->errCode <> SQLITE_OK Then
        rc = pPager->errCode
    End If
    releaseAllSavepoints(pPager)
    pagerFreeMapHdrs(pPager)
    pPager->exclusiveMode = 0
#ifndef SQLITE_OMIT_WAL
    ' The final connection may checkpoint and remove the WAL sidecars. Keep
    ' the checkpoint buffer disabled when close-time checkpoints are disabled
    ' or the VFS reports that the database file has moved.
    Dim pWalCloseBuffer As UByte Ptr = 0
    If pDatabase <> 0 AndAlso _
       (pDatabase->flags And SQLITE_NoCkptOnClose) = 0 AndAlso _
       pagerDatabaseIsUnmoved(pPager) = SQLITE_OK Then
        pWalCloseBuffer = CPtr(UByte Ptr, pPager->pTmpSpace)
    End If
    sqlite3WalClose( _
        pPager->pWal, db, pPager->walSyncFlags, pPager->pageSize, _
        pWalCloseBuffer)
    pPager->pWal = 0
#endif
    pagerUnlockIfUnused(pPager)
    sqlite3EndBenignMalloc()
#ifdef SQLITE_TEST
    enable_simulated_io_errors()
#endif
    If pPager->fd <> 0 Then sqlite3OsCloseFree(pPager->fd)
    If pPager->jfd <> 0 Then sqlite3OsCloseFree(pPager->jfd)
    If pPager->sjfd <> 0 Then sqlite3OsCloseFree(pPager->sjfd)
    sqlite3PageFree(pPager->pTmpSpace)
    If pPager->pPCache <> 0 Then
        sqlite3PcacheClose(pPager->pPCache)
        sqlite3_free(pPager->pPCache)
    End If
    If pPager->zFilename <> 0 Then sqlite3_free_filename(pPager->zFilename)
    sqlite3_free(pPager)
    Return rc
End Function

Sub sqlite3PagerSetCachesize CDecl Alias "sqlite3PagerSetCachesize" ( _
    ByVal pPager As Pager Ptr, _
    ByVal maxPages As SQLITE_C_INT _
) Export
    If pPager <> 0 Then sqlite3PcacheSetCachesize(pPager->pPCache, maxPages)
End Sub

Function sqlite3PagerSetSpillsize CDecl Alias "sqlite3PagerSetSpillsize" ( _
    ByVal pPager As Pager Ptr, _
    ByVal maxPages As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pPager = 0 Then Return 0
    Return sqlite3PcacheSetSpillsize(pPager->pPCache, maxPages)
End Function

Private Sub pagerFixMaplimit CDecl Alias "pagerFixMaplimit" ( _
    ByVal pPager As Pager Ptr _
)
#if SQLITE_MAX_MMAP_SIZE > 0
    If pPager = 0 Then Exit Sub

    Dim pFile As sqlite3_file Ptr = pPager->fd
    If pFile = 0 OrElse pFile->pMethods = 0 Then Exit Sub
    If pFile->pMethods->iVersion < 3 Then Exit Sub

    Dim mapSize As sqlite3_int64 = pPager->szMmap
    If mapSize > 0 Then
        pPager->bUseFetch = 1
    Else
        pPager->bUseFetch = 0
    End If
    pagerSetGetterMethod(pPager)
    sqlite3OsFileControlHint(pFile, SQLITE_FCNTL_MMAP_SIZE, @mapSize)
#endif
End Sub

#ifndef SQLITE_OMIT_WAL
Private Function pagerExclusiveLock CDecl Alias "pagerExclusiveLock" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
    If pPager = 0 OrElse pPager->eLock < SHARED_LOCK Then Return SQLITE_MISUSE
    Dim originalLock As SQLITE_C_INT = pPager->eLock
    Dim rc As SQLITE_C_INT = pagerLockDb(pPager, EXCLUSIVE_LOCK)
    If rc <> SQLITE_OK Then pagerUnlockDb(pPager, originalLock)
    Return rc
End Function

Private Function pagerOpenWal CDecl Alias "pagerOpenWal" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
    If pPager = 0 OrElse pPager->pWal <> 0 OrElse pPager->tempFile <> 0 Then Return SQLITE_MISUSE
    If pPager->eLock <> SHARED_LOCK AndAlso pPager->eLock <> EXCLUSIVE_LOCK Then Return SQLITE_MISUSE

    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pPager->exclusiveMode <> 0 Then rc = pagerExclusiveLock(pPager)
    If rc = SQLITE_OK Then
        rc = sqlite3WalOpen(pPager->pVfs, pPager->fd, pPager->zWal, _
            pPager->exclusiveMode, pPager->journalSizeLimit, @pPager->pWal)
    End If
    pagerFixMaplimit(pPager)
    Return rc
End Function

Function sqlite3PagerOpenWal CDecl Alias "sqlite3PagerOpenWal" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pAlreadyOpen As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pPager = 0 Then Return SQLITE_MISUSE
    If pAlreadyOpen <> 0 Then pAlreadyOpen[0] = 0

    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pPager->tempFile = 0 AndAlso pPager->pWal = 0 Then
        If sqlite3PagerWalSupported(pPager) = 0 Then Return SQLITE_CANTOPEN
        If pPager->jfd <> 0 Then sqlite3OsClose(pPager->jfd)
        rc = pagerOpenWal(pPager)
        If rc = SQLITE_OK Then
            pPager->journalMode = PAGER_JOURNALMODE_WAL
            pPager->eState = PAGER_OPEN
        End If
    Else
        If pAlreadyOpen = 0 Then Return SQLITE_MISUSE
        pAlreadyOpen[0] = 1
    End If
    Return rc
End Function

Function sqlite3PagerCloseWal CDecl Alias "sqlite3PagerCloseWal" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pDatabase As Any Ptr _
) As SQLITE_C_INT
    If pPager = 0 Then Return SQLITE_MISUSE

    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pPager->pWal = 0 Then
        Dim logExists As SQLITE_C_INT = 0
        rc = pagerLockDb(pPager, SHARED_LOCK)
        If rc = SQLITE_OK Then
            rc = sqlite3OsAccess( _
                pPager->pVfs, pPager->zWal, SQLITE_ACCESS_EXISTS, @logExists)
        End If
        If rc = SQLITE_OK AndAlso logExists <> 0 Then _
            rc = pagerOpenWal(pPager)
    End If

    If rc = SQLITE_OK AndAlso pPager->pWal <> 0 Then
        rc = pagerExclusiveLock(pPager)
        If rc = SQLITE_OK Then
            rc = sqlite3WalClose(pPager->pWal, pDatabase, pPager->walSyncFlags, _
                pPager->pageSize, pPager->pTmpSpace)
            pPager->pWal = 0
            pagerFixMaplimit(pPager)
            If rc <> SQLITE_OK AndAlso pPager->exclusiveMode = 0 Then _
                pagerUnlockDb(pPager, SHARED_LOCK)
        End If
    End If
    Return rc
End Function

#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
Sub sqlite3PagerWalDb CDecl Alias "sqlite3PagerWalDb" ( _
    ByVal pPager As Pager Ptr, _
    ByVal db As Any Ptr _
)
    If pPager = 0 Then Exit Sub
    pPager->dbWal = db
    If pPager->pWal <> 0 Then sqlite3WalDb(pPager->pWal, db)
End Sub

Function sqlite3PagerWalWriteLock CDecl Alias "sqlite3PagerWalWriteLock" ( _
    ByVal pPager As Pager Ptr, _
    ByVal bLock As SQLITE_C_INT _
) As SQLITE_C_INT
    If pPager = 0 Then Return SQLITE_MISUSE
    If pPager->pWal = 0 OrElse pPager->exclusiveMode <> 0 Then Return SQLITE_OK
    Return sqlite3WalWriteLock(pPager->pWal, bLock)
End Function
#endif
#endif

#ifdef SQLITE_OMIT_WAL
Private Function pagerOpenWalIfPresent CDecl Alias "pagerOpenWalIfPresent" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
    Return SQLITE_OK
End Function
#else
Private Function pagerOpenWalIfPresent CDecl Alias "pagerOpenWalIfPresent" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
    If pPager = 0 OrElse pPager->eState <> PAGER_OPEN OrElse _
       pPager->eLock < SHARED_LOCK Then Return SQLITE_MISUSE
    If pPager->tempFile <> 0 Then Return SQLITE_OK

    Dim isWal As SQLITE_C_INT = 0
    Dim rc As SQLITE_C_INT = sqlite3OsAccess( _
        pPager->pVfs, pPager->zWal, SQLITE_ACCESS_EXISTS, @isWal)
    If rc <> SQLITE_OK Then Return rc
    If isWal <> 0 Then
        Dim pageCount As u32 = 0
        rc = pagerPagecount(pPager, @pageCount)
        If rc <> SQLITE_OK Then Return rc
        If pageCount = 0 Then
            Return sqlite3OsDelete(pPager->pVfs, pPager->zWal, 0)
        End If
        Return sqlite3PagerOpenWal(pPager, 0)
    End If

    If pPager->journalMode = PAGER_JOURNALMODE_WAL Then _
        pPager->journalMode = PAGER_JOURNALMODE_DELETE
    Return SQLITE_OK
End Function
#endif

Function sqlite3PagerSetJournalMode CDecl Alias "sqlite3PagerSetJournalMode" ( _
    ByVal pPager As Pager Ptr, _
    ByVal eMode As SQLITE_C_INT _
) As SQLITE_C_INT
    If pPager = 0 Then Return PAGER_JOURNALMODE_DELETE
    If eMode < PAGER_JOURNALMODE_DELETE OrElse eMode > PAGER_JOURNALMODE_WAL Then _
        Return pPager->journalMode

    Dim originalMode As u8 = pPager->journalMode
#ifndef SQLITE_OMIT_MEMORYDB
    If pPager->memDb <> 0 AndAlso _
       eMode <> PAGER_JOURNALMODE_MEMORY AndAlso _
       eMode <> PAGER_JOURNALMODE_OFF Then Return originalMode
#endif

    If eMode <> originalMode Then
        pPager->journalMode = CByte(eMode)

        If pPager->exclusiveMode = 0 AndAlso _
           (originalMode And PAGER_JOURNALMODE_ROLLBACK_MASK) = PAGER_JOURNALMODE_PERSIST AndAlso _
           (eMode And PAGER_JOURNALMODE_WAL_BIT) = 0 Then
            If pPager->jfd <> 0 Then sqlite3OsClose(pPager->jfd)
            If pPager->eLock >= RESERVED_LOCK Then
                sqlite3OsDelete(pPager->pVfs, pPager->zJournal, 0)
            Else
                Dim rc As SQLITE_C_INT = SQLITE_OK
                Dim originalState As u8 = pPager->eState
                If originalState = PAGER_OPEN Then rc = sqlite3PagerSharedLock(pPager)
                If pPager->eState = PAGER_READER Then
                    rc = pagerLockDb(pPager, RESERVED_LOCK)
                End If
                If rc = SQLITE_OK Then _
                    sqlite3OsDelete(pPager->pVfs, pPager->zJournal, 0)
                If rc = SQLITE_OK AndAlso originalState = PAGER_READER Then
                    pagerUnlockDb(pPager, SHARED_LOCK)
                ElseIf originalState = PAGER_OPEN Then
                    pager_unlock(pPager)
                End If
            End If
        ElseIf eMode = PAGER_JOURNALMODE_OFF OrElse _
               eMode = PAGER_JOURNALMODE_MEMORY Then
            If pPager->jfd <> 0 Then sqlite3OsClose(pPager->jfd)
        End If
    End If
    Return pPager->journalMode
End Function

Sub sqlite3PagerSetMmapLimit CDecl Alias "sqlite3PagerSetMmapLimit" ( _
    ByVal pPager As Pager Ptr, _
    ByVal sizeLimit As sqlite3_int64 _
) Export
    If pPager = 0 Then Exit Sub
    pPager->szMmap = sizeLimit
    pagerFixMaplimit(pPager)
End Sub

Sub sqlite3PagerShrink CDecl Alias "sqlite3PagerShrink" (ByVal pPager As Pager Ptr) Export
    If pPager <> 0 Then sqlite3PcacheShrink(pPager->pPCache)
End Sub

Sub sqlite3PagerSetFlags CDecl Alias "sqlite3PagerSetFlags" ( _
    ByVal pPager As Pager Ptr, _
    ByVal flags As SQLITE_C_UINT _
) Export
    If pPager = 0 Then Exit Sub
    Dim syncMode As SQLITE_C_UINT = flags And PAGER_SYNCHRONOUS_MASK
    pPager->noSync = IIf(pPager->tempFile <> 0 OrElse syncMode = PAGER_SYNCHRONOUS_OFF, 1, 0)
    pPager->fullSync = IIf(syncMode >= PAGER_SYNCHRONOUS_FULL, 1, 0)
    pPager->extraSync = IIf(syncMode = PAGER_SYNCHRONOUS_EXTRA, 1, 0)
    If pPager->noSync <> 0 Then
        pPager->syncFlags = 0
    ElseIf (flags And PAGER_FULLFSYNC) <> 0 Then
        pPager->syncFlags = SQLITE_SYNC_FULL
    Else
        pPager->syncFlags = SQLITE_SYNC_NORMAL
    End If
    pPager->walSyncFlags = pPager->syncFlags Shl 2
    If pPager->fullSync <> 0 Then pPager->walSyncFlags = pPager->walSyncFlags Or pPager->syncFlags
    If (flags And PAGER_CKPT_FULLFSYNC) <> 0 AndAlso pPager->noSync = 0 Then
        pPager->walSyncFlags = pPager->walSyncFlags Or (SQLITE_SYNC_FULL Shl 2)
    End If
    If (flags And PAGER_CACHESPILL) = 0 Then
        pPager->doNotSpill = pPager->doNotSpill Or 1
    Else
        pPager->doNotSpill = pPager->doNotSpill And Not 1
    End If
End Sub

Function sqlite3PagerMaxPageCount CDecl Alias "sqlite3PagerMaxPageCount" ( _
    ByVal pPager As Pager Ptr, _
    ByVal maxPages As u32 _
) As u32 Export
    If pPager = 0 Then Return 0
    ' OP_MaxPgcnt has already bounded this value by the B-tree's live page
    ' count. The pager's dbSize may be stale while auto-vacuum shrinks inside
    ' a transaction, so clamping to dbSize would reject a valid lower limit.
    If maxPages > 0 Then pPager->mxPgno = maxPages
    Return pPager->mxPgno
End Function

Function sqlite3PagerIsreadonly CDecl Alias "sqlite3PagerIsreadonly" (ByVal pPager As Pager Ptr) As u8 Export
    If pPager = 0 Then Return 1
    Return pPager->readOnly
End Function

Function sqlite3PagerDataVersion CDecl Alias "sqlite3PagerDataVersion" (ByVal pPager As Pager Ptr) As u32 Export
    If pPager = 0 Then Return 0
    Return pPager->iDataVersion
End Function

Function sqlite3PagerMemUsed CDecl Alias "sqlite3PagerMemUsed" (ByVal pPager As Pager Ptr) As SQLITE_C_INT Export
    If pPager = 0 Then Return 0
    Dim nPage As SQLITE_C_INT = sqlite3PcachePagecount(pPager->pPCache)
    Dim bytes As sqlite3_int64 = CLngInt(nPage) * pPager->pageSize
    If bytes > &H7FFFFFFF Then Return &H7FFFFFFF
    Return CLng(bytes)
End Function

#ifdef SQLITE_TEST
' Keep the 11 result slots in the order consumed by SQLite's C test callers.
' SQLite callers retain this process-wide array only until the next stats call.
Private Dim Shared pagerTestStats(0 To 10) As SQLITE_C_INT
Private Dim Shared pagerSavedIoErrorCount As SQLITE_C_INT

Sub disable_simulated_io_errors CDecl Alias "disable_simulated_io_errors" ()
    pagerSavedIoErrorCount = sqlite3_io_error_pending
    sqlite3_io_error_pending = -1
End Sub

Sub enable_simulated_io_errors CDecl Alias "enable_simulated_io_errors" ()
    sqlite3_io_error_pending = pagerSavedIoErrorCount
End Sub

Function sqlite3PagerStats CDecl Alias "sqlite3PagerStats" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT Ptr
    If pPager = 0 OrElse pPager->pPCache = 0 Then Return 0

    pagerTestStats(0) = CLng(sqlite3PcacheRefCount(pPager->pPCache))
    pagerTestStats(1) = sqlite3PcachePagecount(pPager->pPCache)
    pagerTestStats(2) = sqlite3PcacheGetCachesize(pPager->pPCache)
    If pPager->eState = PAGER_OPEN Then
        pagerTestStats(3) = -1
    Else
        pagerTestStats(3) = Cast(SQLITE_C_INT, pPager->dbSize)
    End If
    pagerTestStats(4) = pPager->eState
    pagerTestStats(5) = pPager->errCode
    pagerTestStats(6) = Cast(SQLITE_C_INT, pPager->aStat(PAGER_STAT_HIT) And &H7FFFFFFF)
    pagerTestStats(7) = Cast(SQLITE_C_INT, pPager->aStat(PAGER_STAT_MISS) And &H7FFFFFFF)
    pagerTestStats(8) = 0
    pagerTestStats(9) = pPager->nRead
    pagerTestStats(10) = Cast(SQLITE_C_INT, pPager->aStat(PAGER_STAT_WRITE) And &H7FFFFFFF)
    Return @pagerTestStats(0)
End Function
#endif

/' Cache status operations are contiguous from hit through spill and map onto aStat(0..3). '/
Sub sqlite3PagerCacheStat CDecl Alias "sqlite3PagerCacheStat" ( _
    ByVal pPager As Pager Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal resetFlag As SQLITE_C_INT, _
    ByVal pStatValue As sqlite3_uint64 Ptr _
)
    If pPager = 0 OrElse pStatValue = 0 Then Return
    If operation < SQLITE_DBSTATUS_CACHE_HIT OrElse _
       operation > SQLITE_DBSTATUS_CACHE_WRITE + 1 Then Return

    Dim statisticIndex As SQLITE_C_INT = operation - SQLITE_DBSTATUS_CACHE_HIT
    If statisticIndex < 0 OrElse statisticIndex > PAGER_STAT_SPILL Then Return
    pStatValue[0] += pPager->aStat(statisticIndex)
    If resetFlag <> 0 Then pPager->aStat(statisticIndex) = 0
End Sub

Function sqlite3PagerFilename CDecl Alias "sqlite3PagerFilename" (ByVal pPager As Pager Ptr, ByVal nullIfMemDb As SQLITE_C_INT) As Const ZString Ptr Export
    If pPager = 0 Then Return 0
    If nullIfMemDb <> 0 AndAlso (pPager->memDb <> 0 OrElse pPager->memVfs <> 0) Then Return StrPtr("")
    Return pPager->zFilename
End Function

Function sqlite3PagerVfs CDecl Alias "sqlite3PagerVfs" (ByVal pPager As Pager Ptr) As sqlite3_vfs Ptr Export
    If pPager = 0 Then Return 0
    Return pPager->pVfs
End Function

Function sqlite3PagerFile CDecl Alias "sqlite3PagerFile" (ByVal pPager As Pager Ptr) As sqlite3_file Ptr Export
    If pPager = 0 Then Return 0
    Return pPager->fd
End Function

Function sqlite3PagerJrnlFile CDecl Alias "sqlite3PagerJrnlFile" (ByVal pPager As Pager Ptr) As sqlite3_file Ptr Export
    If pPager = 0 Then Return 0
    Return pPager->jfd
End Function

Function sqlite3PagerJournalname CDecl Alias "sqlite3PagerJournalname" (ByVal pPager As Pager Ptr) As Const ZString Ptr Export
    If pPager = 0 Then Return 0
    Return pPager->zJournal
End Function

Function sqlite3PagerTempSpace CDecl Alias "sqlite3PagerTempSpace" (ByVal pPager As Pager Ptr) As Any Ptr Export
    If pPager = 0 Then Return 0
    Return pPager->pTmpSpace
End Function

Function sqlite3PagerIsMemdb CDecl Alias "sqlite3PagerIsMemdb" (ByVal pPager As Pager Ptr) As SQLITE_C_INT Export
    If pPager = 0 Then Return 0
    Return IIf(pPager->tempFile <> 0 OrElse pPager->memVfs <> 0, 1, 0)
End Function

Function sqlite3PagerGetJournalMode CDecl Alias "sqlite3PagerGetJournalMode" (ByVal pPager As Pager Ptr) As SQLITE_C_INT Export
    If pPager = 0 Then Return PAGER_JOURNALMODE_DELETE
    Return pPager->journalMode
End Function

Sub sqlite3PagerClearCache CDecl Alias "sqlite3PagerClearCache" (ByVal pPager As Pager Ptr) Export
    If pPager = 0 OrElse pPager->pPCache = 0 Then Exit Sub
    sqlite3PcacheClear(pPager->pPCache)
End Sub

Function sqlite3SectorSize CDecl Alias "sqlite3SectorSize" ( _
    ByVal pFile As sqlite3_file Ptr _
) As SQLITE_C_INT Export
    Dim sectorSize As SQLITE_C_INT = sqlite3OsSectorSize(pFile)
    If sectorSize < PAGER_MIN_SECTOR_SIZE Then Return PAGER_DEFAULT_SECTOR_SIZE
    If sectorSize > PAGER_MAX_SECTOR_SIZE Then Return PAGER_MAX_SECTOR_SIZE
    Return sectorSize
End Function

Function sqlite3PagerPagenumber CDecl Alias "sqlite3PagerPagenumber" ( _
    ByVal pPage As PgHdr Ptr _
) As u32 Export
    If pPage = 0 Then Return 0
    Return pPage->pgno
End Function

Function sqlite3PagerRefcount CDecl Alias "sqlite3PagerRefcount" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT Export
    If pPager = 0 OrElse pPager->pPCache = 0 Then Return 0
    Return CInt(sqlite3PcacheRefCount(pPager->pPCache))
End Function

Function sqlite3PagerBackupPtr CDecl Alias "sqlite3PagerBackupPtr" ( _
    ByVal pPager As Pager Ptr _
) As Any Ptr Ptr Export
    If pPager = 0 Then Return 0
    Return @pPager->pBackup
End Function

Function sqlite3PagerOkToChangeJournalMode CDecl Alias "sqlite3PagerOkToChangeJournalMode" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT Export
    If pPager = 0 Then Return 0
    If pPager->eState >= PAGER_WRITER_CACHEMOD Then Return 0

    Dim pJournalFile As sqlite3_file Ptr = pPager->jfd
    If pJournalFile <> 0 AndAlso pJournalFile->pMethods <> 0 AndAlso _
       pPager->journalOff > 0 Then Return 0

    Return 1
End Function

Function sqlite3PagerExclusiveLock CDecl Alias "sqlite3PagerExclusiveLock" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT Export
    If pPager = 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = pPager->errCode
    If rc <> SQLITE_OK Then Return rc

#ifndef SQLITE_OMIT_WAL
    If pPager->pWal = 0 Then rc = pager_wait_on_lock(pPager, EXCLUSIVE_LOCK)
#else
    rc = pager_wait_on_lock(pPager, EXCLUSIVE_LOCK)
#endif
    Return rc
End Function

#ifdef SQLITE_ENABLE_SNAPSHOT
#ifndef SQLITE_OMIT_WAL
Function sqlite3PagerSnapshotGet CDecl Alias "sqlite3PagerSnapshotGet" ( _
    ByVal pPager As Pager Ptr, _
    ByVal ppSnapshot As Any Ptr Ptr _
) As SQLITE_C_INT Export
    If pPager = 0 OrElse ppSnapshot = 0 Then Return SQLITE_MISUSE
    If pPager->pWal = 0 Then Return SQLITE_ERROR
    Return sqlite3WalSnapshotGet(pPager->pWal, ppSnapshot)
End Function

Function sqlite3PagerSnapshotOpen CDecl Alias "sqlite3PagerSnapshotOpen" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pSnapshot As Any Ptr _
) As SQLITE_C_INT Export
    If pPager = 0 Then Return SQLITE_MISUSE
    If pPager->pWal = 0 Then Return SQLITE_ERROR
    sqlite3WalSnapshotOpen(pPager->pWal, pSnapshot)
    Return SQLITE_OK
End Function

Function sqlite3PagerSnapshotRecover CDecl Alias "sqlite3PagerSnapshotRecover" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT Export
    If pPager = 0 Then Return SQLITE_MISUSE
    If pPager->pWal = 0 Then Return SQLITE_ERROR
    Return sqlite3WalSnapshotRecover(pPager->pWal)
End Function

Function sqlite3PagerSnapshotCheck CDecl Alias "sqlite3PagerSnapshotCheck" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pSnapshot As Any Ptr _
) As SQLITE_C_INT Export
    If pPager = 0 OrElse pSnapshot = 0 Then Return SQLITE_MISUSE
    If pPager->pWal = 0 Then Return SQLITE_ERROR
    Return sqlite3WalSnapshotCheck(pPager->pWal, pSnapshot)
End Function

Sub sqlite3PagerSnapshotUnlock CDecl Alias "sqlite3PagerSnapshotUnlock" ( _
    ByVal pPager As Pager Ptr _
) Export
    If pPager = 0 OrElse pPager->pWal = 0 Then Exit Sub
    sqlite3WalSnapshotUnlock(pPager->pWal)
End Sub
#endif
#endif

#if defined(SQLITE_DEBUG) OrElse defined(SQLITE_ENABLE_WALSTAT)
Sub sqlite3PagerWalStat CDecl Alias "sqlite3PagerWalStat" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pStr As Any Ptr _
)
    If pPager = 0 OrElse pStr = 0 Then Return
#ifndef SQLITE_OMIT_WAL
    If pPager->pWal <> 0 Then sqlite3WalStat(pPager->pWal, pStr)
#endif
End Sub
#endif

#ifdef SQLITE_ENABLE_ZIPVFS
Function sqlite3PagerWalFramesize CDecl Alias "sqlite3PagerWalFramesize" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
    If pPager = 0 Then Return 0
    ' The caller holds the pager read lock, as required by sqlite3WalFramesize.
    Return sqlite3WalFramesize(pPager->pWal)
End Function
#endif

#if defined(SQLITE_USE_SEH) AndAlso Not defined(SQLITE_OMIT_WAL)
Function sqlite3PagerWalSystemErrno CDecl Alias "sqlite3PagerWalSystemErrno" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
    If pPager = 0 OrElse pPager->pWal = 0 Then Return 0
    Return sqlite3WalSystemErrno(pPager->pWal)
End Function
#endif

/' end of sqlite3_pager.bas '/
