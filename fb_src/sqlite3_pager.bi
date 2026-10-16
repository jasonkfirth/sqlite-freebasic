/'
    Project: SQLite FreeBASIC port

    File: sqlite3_pager.bi

    Purpose:

        Define pager state, page types, and pager-facing internal calls.

    Responsibilities:

        - Describe the Pager state shared by VFS, page-cache, and B-tree code.
        - Declare page acquisition, cache spilling, single-file rollback transactions, and pager lifecycle routines.
        - Declare pager-level database lock and mmap-limit helpers.
        - Declare opaque WAL lifecycle, transactions, frames, callbacks, undo, savepoints, and checkpoints.
        - Declare the super-journal reader used while cleaning up orphaned journals.

    This file intentionally does NOT contain:

        - WAL state layout, which is defined in sqlite3_wal_types.bi.
        - B-tree page parsing or SQL execution.
'/ 

#ifndef SQLITE3_FB_PAGER_BI
#define SQLITE3_FB_PAGER_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_vfs.bi"
#include once "sqlite3_pcache.bi"

' Test builds move this byte into small databases. The B-tree page skip and
' VFS locks must use the same offset.
Extern sqlite3PendingByte Alias "sqlite3PendingByte" As SQLITE_C_INT
#ifdef SQLITE_OMIT_WSD
#define PENDING_BYTE &H40000000
#else
#define PENDING_BYTE sqlite3PendingByte
#endif

' Pager keeps the WAL handle opaque; these calls form the boundary to wal.c.
Declare Function sqlite3WalFindFrame CDecl Alias "sqlite3WalFindFrame" ( _
    ByVal pWal As Any Ptr, _
    ByVal pageNumber As SQLITE_C_UINT, _
    ByVal pFrame As SQLITE_C_UINT Ptr _
) As SQLITE_C_INT
Declare Function sqlite3WalReadFrame CDecl Alias "sqlite3WalReadFrame" ( _
    ByVal pWal As Any Ptr, _
    ByVal frameIndex As SQLITE_C_UINT, _
    ByVal outputSize As SQLITE_C_INT, _
    ByVal pOutput As UByte Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3WalLimit CDecl Alias "sqlite3WalLimit" ( _
    ByVal pWal As Any Ptr, _
    ByVal maximumWalSize As sqlite3_int64 _
)
Declare Function sqlite3WalHeapMemory CDecl Alias "sqlite3WalHeapMemory" ( _
    ByVal pWal As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3WalOpen CDecl Alias "sqlite3WalOpen" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal pDbFile As sqlite3_file Ptr, _
    ByVal zWalName As Const ZString Ptr, _
    ByVal noSharedMemory As SQLITE_C_INT, _
    ByVal maxWalSize As sqlite3_int64, _
    ByVal ppWal As Any Ptr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3WalBeginReadTransaction CDecl Alias "sqlite3WalBeginReadTransaction" ( _
    ByVal pWal As Any Ptr, _
    ByVal pChanged As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3WalEndReadTransaction CDecl Alias "sqlite3WalEndReadTransaction" ( _
    ByVal pWal As Any Ptr _
)
Declare Function sqlite3WalEndWriteTransaction CDecl Alias "sqlite3WalEndWriteTransaction" ( _
    ByVal pWal As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3WalBeginWriteTransaction CDecl Alias "sqlite3WalBeginWriteTransaction" ( _
    ByVal pWal As Any Ptr _
) As SQLITE_C_INT
Type SqliteWalUndoProc As Function CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal pageNumber As u32 _
) As SQLITE_C_INT
Declare Function sqlite3WalUndo CDecl Alias "sqlite3WalUndo" ( _
    ByVal pWal As Any Ptr, _
    ByVal xUndo As SqliteWalUndoProc, _
    ByVal pUndoContext As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3WalSavepoint CDecl Alias "sqlite3WalSavepoint" ( _
    ByVal pWal As Any Ptr, _
    ByVal aWalData As u32 Ptr _
)
Declare Function sqlite3WalSavepointUndo CDecl Alias "sqlite3WalSavepointUndo" ( _
    ByVal pWal As Any Ptr, _
    ByVal aWalData As u32 Ptr _
) As SQLITE_C_INT
Declare Function sqlite3WalFrames CDecl Alias "sqlite3WalFrames" ( _
    ByVal pWal As Any Ptr, _
    ByVal pageSize As SQLITE_C_INT, _
    ByVal pList As PgHdr Ptr, _
    ByVal truncatePages As u32, _
    ByVal isCommit As SQLITE_C_INT, _
    ByVal syncFlags As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3WalCheckpoint CDecl Alias "sqlite3WalCheckpoint" ( _
    ByVal pWal As Any Ptr, _
    ByVal db As Any Ptr, _
    ByVal mode As SQLITE_C_INT, _
    ByVal xBusy As Any Ptr, _
    ByVal pBusyArgument As Any Ptr, _
    ByVal syncFlags As SQLITE_C_INT, _
    ByVal bufferSize As SQLITE_C_INT, _
    ByVal pBuffer As UByte Ptr, _
    ByVal pLogFrames As SQLITE_C_INT Ptr, _
    ByVal pCheckpointedFrames As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
#ifdef SQLITE_ENABLE_SNAPSHOT
Declare Function sqlite3WalSnapshotGet CDecl Alias "sqlite3WalSnapshotGet" ( _
    ByVal pWal As Any Ptr, _
    ByVal ppSnapshot As Any Ptr Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3WalSnapshotOpen CDecl Alias "sqlite3WalSnapshotOpen" ( _
    ByVal pWal As Any Ptr, _
    ByVal pSnapshot As Any Ptr _
)
Declare Function sqlite3WalSnapshotRecover CDecl Alias "sqlite3WalSnapshotRecover" ( _
    ByVal pWal As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3WalSnapshotCheck CDecl Alias "sqlite3WalSnapshotCheck" ( _
    ByVal pWal As Any Ptr, _
    ByVal pSnapshot As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3WalSnapshotUnlock CDecl Alias "sqlite3WalSnapshotUnlock" ( _
    ByVal pWal As Any Ptr _
)
#endif
Declare Function sqlite3WalClose CDecl Alias "sqlite3WalClose" ( _
    ByVal pWal As Any Ptr, _
    ByVal db As Any Ptr, _
    ByVal syncFlags As SQLITE_C_INT, _
    ByVal bufferSize As SQLITE_C_INT, _
    ByVal pBuffer As UByte Ptr _
) As SQLITE_C_INT
Declare Function sqlite3WalCallback CDecl Alias "sqlite3WalCallback" ( _
    ByVal pWal As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3WalExclusiveMode CDecl Alias "sqlite3WalExclusiveMode" ( _
    ByVal pWal As Any Ptr, _
    ByVal operation As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3WalFile CDecl Alias "sqlite3WalFile" ( _
    ByVal pWal As Any Ptr _
) As sqlite3_file Ptr
#ifdef SQLITE_ENABLE_ZIPVFS
Declare Function sqlite3WalFramesize CDecl Alias "sqlite3WalFramesize" ( _
    ByVal pWal As Any Ptr _
) As SQLITE_C_INT
#endif
#define DbPage PgHdr

#ifndef SQLITE_DEFAULT_PAGE_SIZE
#define SQLITE_DEFAULT_PAGE_SIZE 4096
#endif
#ifndef SQLITE_MAX_PAGE_SIZE
#define SQLITE_MAX_PAGE_SIZE 65536
#endif
#ifndef SQLITE_MAX_DEFAULT_PAGE_SIZE
#define SQLITE_MAX_DEFAULT_PAGE_SIZE 8192
#endif
#ifndef SQLITE_MAX_PAGE_COUNT
#define SQLITE_MAX_PAGE_COUNT &HFFFFFFFE
#endif
#ifndef SQLITE_DEFAULT_JOURNAL_SIZE_LIMIT
#define SQLITE_DEFAULT_JOURNAL_SIZE_LIMIT -1
#endif
#ifndef SQLITE_DEFAULT_SYNCHRONOUS
#define SQLITE_DEFAULT_SYNCHRONOUS 2
#endif
#ifndef SQLITE_DEFAULT_WAL_SYNCHRONOUS
#define SQLITE_DEFAULT_WAL_SYNCHRONOUS SQLITE_DEFAULT_SYNCHRONOUS
#endif

#define NO_LOCK 0
#define SHARED_LOCK 1
#define RESERVED_LOCK 2
#define PENDING_LOCK 3
#define EXCLUSIVE_LOCK 4
#define UNKNOWN_LOCK (EXCLUSIVE_LOCK + 1)

#define PAGER_OPEN 0
#define PAGER_READER 1
#define PAGER_WRITER_LOCKED 2
#define PAGER_WRITER_CACHEMOD 3
#define PAGER_WRITER_DBMOD 4
#define PAGER_WRITER_FINISHED 5
#define PAGER_ERROR 6

#define PAGER_OMIT_JOURNAL &H0001
#define PAGER_MEMORY &H0002
#define PAGER_LOCKINGMODE_QUERY -1
#define PAGER_LOCKINGMODE_NORMAL 0
#define PAGER_LOCKINGMODE_EXCLUSIVE 1
#define PAGER_JOURNALMODE_QUERY -1
#define PAGER_JOURNALMODE_DELETE 0
#define PAGER_JOURNALMODE_PERSIST 1
#define PAGER_JOURNALMODE_OFF 2
#define PAGER_JOURNALMODE_TRUNCATE 3
#define PAGER_JOURNALMODE_MEMORY 4
#define PAGER_JOURNALMODE_WAL 5
#define PAGER_GET_NOCONTENT &H01
#define PAGER_GET_READONLY &H02
#define PAGER_SYNCHRONOUS_OFF &H01
#define PAGER_SYNCHRONOUS_NORMAL &H02
#define PAGER_SYNCHRONOUS_FULL &H03
#define PAGER_SYNCHRONOUS_EXTRA &H04
#define PAGER_SYNCHRONOUS_MASK &H07
#define PAGER_FULLFSYNC &H08
#define PAGER_CKPT_FULLFSYNC &H10
#define PAGER_CACHESPILL &H20
#define PAGER_FLAGS_MASK &H38
#define PAGER_STAT_HIT 0
#define PAGER_STAT_MISS 1
#define PAGER_STAT_WRITE 2
#define PAGER_STAT_SPILL 3
#define SAVEPOINT_BEGIN 0
#define SAVEPOINT_RELEASE 1
#define SAVEPOINT_ROLLBACK 2
#define SPILLFLAG_OFF &H01
#define SPILLFLAG_ROLLBACK &H02
#define SPILLFLAG_NOSYNC &H04

Type PagerSavepoint
    iOffset As i64
    iHdrOffset As i64
    pInSavepoint As Any Ptr
    nOrig As u32
    iSubRec As u32
    bTruncateOnRelease As SQLITE_C_INT
#ifndef SQLITE_OMIT_WAL
    aWalData(0 To 3) As u32
#endif
End Type

Type Pager
    pVfs As sqlite3_vfs Ptr
    exclusiveMode As u8
    journalMode As u8
    useJournal As u8
    noSync As u8
    fullSync As u8
    extraSync As u8
    syncFlags As u8
    walSyncFlags As u8
    tempFile As u8
    noLock As u8
    readOnly As u8
    memDb As u8
    memVfs As u8
    eState As u8
    eLock As u8
    changeCountDone As u8
    setSuper As u8
    doNotSpill As u8
    subjInMemory As u8
    bUseFetch As u8
    hasHeldSharedLock As u8
    dbSize As u32
    dbOrigSize As u32
    dbFileSize As u32
    dbHintSize As u32
    errCode As SQLITE_C_INT
    nRec As SQLITE_C_INT
    cksumInit As u32
    nSubRec As u32
    pInJournal As Any Ptr
    fd As sqlite3_file Ptr
    jfd As sqlite3_file Ptr
    sjfd As sqlite3_file Ptr
    journalOff As i64
    journalHdr As i64
    pBackup As Any Ptr
    aSavepoint As PagerSavepoint Ptr
    nSavepoint As SQLITE_C_INT
    iDataVersion As u32
    dbFileVers(0 To 15) As UByte
    nMmapOut As SQLITE_C_INT
    szMmap As sqlite3_int64
    pMmapFreelist As PgHdr Ptr
    nExtra As u16
    nReserve As Short
    vfsFlags As u32
    sectorSize As u32
    mxPgno As u32
    lckPgno As u32
    pageSize As i64
    journalSizeLimit As i64
    zFilename As ZString Ptr
    zJournal As ZString Ptr
    xBusyHandler As Any Ptr
    pBusyHandlerArg As Any Ptr
    aStat(0 To 3) As u32
#ifdef SQLITE_TEST
    nRead As SQLITE_C_INT
#endif
    xReiniter As Any Ptr
    xGet As Any Ptr
    pTmpSpace As UByte Ptr
    pPCache As PCache Ptr
#ifndef SQLITE_OMIT_WAL
    pWal As Any Ptr
    zWal As ZString Ptr
#endif
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    dbWal As Any Ptr
#endif
End Type

#if defined(SQLITE_DEBUG) OrElse defined(SQLITE_ENABLE_WALSTAT)
Declare Sub sqlite3PagerWalStat CDecl Alias "sqlite3PagerWalStat" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pStr As Any Ptr _
)
Declare Sub sqlite3WalStat CDecl Alias "sqlite3WalStat" ( _
    ByVal pWal As Any Ptr, _
    ByVal pStr As Any Ptr _
)
#endif

Type SqlitePagerBusyProc As Function CDecl (ByVal pArgument As Any Ptr) As SQLITE_C_INT
Type SqlitePagerReinitProc As Sub CDecl (ByVal pPage As PgHdr Ptr)
Type SqlitePagerGetProc As Function CDecl ( _
    ByVal pPager As Pager Ptr, _
    ByVal pageNumber As u32, _
    ByVal ppPage As PgHdr Ptr Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT

Declare Function sqlite3PagerOpen CDecl Alias "sqlite3PagerOpen" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal ppPager As Pager Ptr Ptr, _
    ByVal zFilename As Const ZString Ptr, _
    ByVal nExtra As SQLITE_C_INT, _
    ByVal flags As SQLITE_C_INT, _
    ByVal vfsFlags As SQLITE_C_INT, _
    ByVal xReinit As SqlitePagerReinitProc _
) As SQLITE_C_INT
Declare Function sqlite3PagerClose CDecl Alias "sqlite3PagerClose" (ByVal pPager As Pager Ptr, ByVal db As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3PagerReadFileheader CDecl Alias "sqlite3PagerReadFileheader" (ByVal pPager As Pager Ptr, ByVal amount As SQLITE_C_INT, ByVal pDestination As UByte Ptr) As SQLITE_C_INT
Declare Sub sqlite3PagerSetBusyHandler CDecl Alias "sqlite3PagerSetBusyHandler" (ByVal pPager As Pager Ptr, ByVal xBusy As SqlitePagerBusyProc, ByVal pArgument As Any Ptr)
Declare Function sqlite3PagerSetPagesize CDecl Alias "sqlite3PagerSetPagesize" (ByVal pPager As Pager Ptr, ByVal pPageSize As u32 Ptr, ByVal nReserve As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3PagerMaxPageCount CDecl Alias "sqlite3PagerMaxPageCount" (ByVal pPager As Pager Ptr, ByVal maxPages As u32) As u32
Declare Sub sqlite3PagerSetCachesize CDecl Alias "sqlite3PagerSetCachesize" (ByVal pPager As Pager Ptr, ByVal maxPages As SQLITE_C_INT)
Declare Function sqlite3PagerSetSpillsize CDecl Alias "sqlite3PagerSetSpillsize" (ByVal pPager As Pager Ptr, ByVal maxPages As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub sqlite3PagerSetMmapLimit CDecl Alias "sqlite3PagerSetMmapLimit" (ByVal pPager As Pager Ptr, ByVal sizeLimit As sqlite3_int64)
Declare Function sqlite3SectorSize CDecl Alias "sqlite3SectorSize" (ByVal pFile As sqlite3_file Ptr) As SQLITE_C_INT
Declare Function sqlite3PagerPagenumber CDecl Alias "sqlite3PagerPagenumber" (ByVal pPage As PgHdr Ptr) As u32
Declare Function sqlite3PagerRefcount CDecl Alias "sqlite3PagerRefcount" (ByVal pPager As Pager Ptr) As SQLITE_C_INT
Declare Function sqlite3PagerBackupPtr CDecl Alias "sqlite3PagerBackupPtr" (ByVal pPager As Pager Ptr) As Any Ptr Ptr
Declare Function sqlite3PagerOkToChangeJournalMode CDecl Alias "sqlite3PagerOkToChangeJournalMode" (ByVal pPager As Pager Ptr) As SQLITE_C_INT
Declare Function sqlite3PagerExclusiveLock CDecl Alias "sqlite3PagerExclusiveLock" (ByVal pPager As Pager Ptr) As SQLITE_C_INT
Declare Sub sqlite3PagerSetFlags CDecl Alias "sqlite3PagerSetFlags" (ByVal pPager As Pager Ptr, ByVal flags As SQLITE_C_UINT)
Declare Sub sqlite3PagerShrink CDecl Alias "sqlite3PagerShrink" (ByVal pPager As Pager Ptr)
Declare Function sqlite3PagerGet CDecl Alias "sqlite3PagerGet" (ByVal pPager As Pager Ptr, ByVal pageNumber As u32, ByVal ppPage As PgHdr Ptr Ptr, ByVal flags As SQLITE_C_INT) As SQLITE_C_INT
Declare Function getPageMMap CDecl Alias "getPageMMap" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pageNumber As u32, _
    ByVal ppPage As PgHdr Ptr Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3PagerLookup CDecl Alias "sqlite3PagerLookup" (ByVal pPager As Pager Ptr, ByVal pageNumber As u32) As PgHdr Ptr
Declare Function sqlite3PagerSharedLock CDecl Alias "sqlite3PagerSharedLock" (ByVal pPager As Pager Ptr) As SQLITE_C_INT
' These helpers are file-static in C but pager_write is compiled in a separate
' FreeBASIC module. The version map keeps their aliases out of the public ABI.
Declare Function pager_open_journal CDecl Alias "pager_open_journal" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
Declare Function openSubJournal CDecl Alias "openSubJournal" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
Declare Function sqlite3PagerBegin CDecl Alias "sqlite3PagerBegin" (ByVal pPager As Pager Ptr, ByVal exclusiveFlag As SQLITE_C_INT, ByVal subjournalInMemory As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3PagerWrite CDecl Alias "sqlite3PagerWrite" (ByVal pPage As PgHdr Ptr) As SQLITE_C_INT
Declare Function sqlite3PagerMovepage CDecl Alias "sqlite3PagerMovepage" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pPage As PgHdr Ptr, _
    ByVal pageNumber As u32, _
    ByVal isCommit As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Sub sqlite3PagerTruncateImage CDecl Alias "sqlite3PagerTruncateImage" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pageCount As u32 _
)
Declare Sub sqlite3PagerRekey CDecl Alias "sqlite3PagerRekey" ( _
    ByVal pPage As PgHdr Ptr, _
    ByVal newPageNumber As u32, _
    ByVal flags As u16 _
)
Declare Function sqlite3PagerCommitPhaseOne CDecl Alias "sqlite3PagerCommitPhaseOne" (ByVal pPager As Pager Ptr, ByVal zSuperJournal As Const ZString Ptr, ByVal noSync As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3PagerCommitPhaseTwo CDecl Alias "sqlite3PagerCommitPhaseTwo" (ByVal pPager As Pager Ptr) As SQLITE_C_INT
Declare Function sqlite3PagerFlush CDecl Alias "sqlite3PagerFlush" (ByVal pPager As Pager Ptr) As SQLITE_C_INT
Declare Function sqlite3PagerRollback CDecl Alias "sqlite3PagerRollback" (ByVal pPager As Pager Ptr) As SQLITE_C_INT
Declare Function sqlite3PagerSync CDecl Alias "sqlite3PagerSync" (ByVal pPager As Pager Ptr, ByVal zSuperJournal As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3PagerIswriteable CDecl Alias "sqlite3PagerIswriteable" (ByVal pPage As PgHdr Ptr) As SQLITE_C_INT
Declare Sub sqlite3PagerDontWrite CDecl Alias "sqlite3PagerDontWrite" (ByVal pPage As PgHdr Ptr)
Declare Function sqlite3PagerOpenSavepoint CDecl Alias "sqlite3PagerOpenSavepoint" (ByVal pPager As Pager Ptr, ByVal nSavepoint As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3PagerSavepoint CDecl Alias "sqlite3PagerSavepoint" (ByVal pPager As Pager Ptr, ByVal operation As SQLITE_C_INT, ByVal savepointIndex As SQLITE_C_INT) As SQLITE_C_INT
Declare Function readJournalHdr CDecl Alias "readJournalHdr" ( _
    ByVal pPager As Pager Ptr, _
    ByVal isHot As SQLITE_C_INT, _
    ByVal journalSize As sqlite3_int64, _
    ByVal pNRec As u32 Ptr, _
    ByVal pDbSize As u32 Ptr _
) As SQLITE_C_INT
Declare Function readDbPage CDecl Alias "readDbPage" ( _
    ByVal pPage As PgHdr Ptr _
) As SQLITE_C_INT
Declare Function pager_playback_one_page CDecl Alias "pager_playback_one_page" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pOffset As sqlite3_int64 Ptr, _
    ByVal pDone As Any Ptr, _
    ByVal isMainJournal As SQLITE_C_INT, _
    ByVal isSavepoint As SQLITE_C_INT _
) As SQLITE_C_INT
#ifndef SQLITE_OMIT_WAL
Declare Function pagerBeginReadTransaction CDecl Alias "pagerBeginReadTransaction" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
#endif
Declare Function readSuperJournal CDecl Alias "readSuperJournal" ( _
    ByVal pJournal As sqlite3_file Ptr, _
    ByVal maximumNameBytes As sqlite3_uint64, _
    ByVal pzSuperJournal As ZString Ptr Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3PagerRef CDecl Alias "sqlite3PagerRef" (ByVal pPage As PgHdr Ptr)
Declare Sub sqlite3PagerUnref CDecl Alias "sqlite3PagerUnref" (ByVal pPage As PgHdr Ptr)
Declare Sub sqlite3PagerUnrefNotNull CDecl Alias "sqlite3PagerUnrefNotNull" (ByVal pPage As PgHdr Ptr)
Declare Sub sqlite3PagerUnrefPageOne CDecl Alias "sqlite3PagerUnrefPageOne" (ByVal pPage As PgHdr Ptr)
Declare Function sqlite3PagerPageRefcount CDecl Alias "sqlite3PagerPageRefcount" (ByVal pPage As PgHdr Ptr) As SQLITE_C_INT
Declare Function sqlite3PagerGetData CDecl Alias "sqlite3PagerGetData" (ByVal pPage As PgHdr Ptr) As Any Ptr
Declare Function sqlite3PagerGetExtra CDecl Alias "sqlite3PagerGetExtra" (ByVal pPage As PgHdr Ptr) As Any Ptr
Declare Sub sqlite3PagerPagecount CDecl Alias "sqlite3PagerPagecount" (ByVal pPager As Pager Ptr, ByVal pCount As SQLITE_C_INT Ptr)
Declare Function sqlite3PagerIsreadonly CDecl Alias "sqlite3PagerIsreadonly" (ByVal pPager As Pager Ptr) As u8
Declare Function sqlite3PagerDataVersion CDecl Alias "sqlite3PagerDataVersion" (ByVal pPager As Pager Ptr) As u32
Declare Function sqlite3PagerMemUsed CDecl Alias "sqlite3PagerMemUsed" (ByVal pPager As Pager Ptr) As SQLITE_C_INT
#ifdef SQLITE_TEST
Declare Sub disable_simulated_io_errors CDecl Alias "disable_simulated_io_errors" ()
Declare Sub enable_simulated_io_errors CDecl Alias "enable_simulated_io_errors" ()
Declare Function sqlite3PagerStats CDecl Alias "sqlite3PagerStats" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT Ptr
#endif
Declare Sub sqlite3PagerCacheStat CDecl Alias "sqlite3PagerCacheStat" ( _
    ByVal pPager As Pager Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal resetFlag As SQLITE_C_INT, _
    ByVal pStatValue As sqlite3_uint64 Ptr _
)
Declare Function sqlite3PagerFilename CDecl Alias "sqlite3PagerFilename" (ByVal pPager As Pager Ptr, ByVal nullIfMemDb As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3PagerVfs CDecl Alias "sqlite3PagerVfs" (ByVal pPager As Pager Ptr) As sqlite3_vfs Ptr
Declare Function sqlite3PagerFile CDecl Alias "sqlite3PagerFile" (ByVal pPager As Pager Ptr) As sqlite3_file Ptr
Declare Function sqlite3PagerJrnlFile CDecl Alias "sqlite3PagerJrnlFile" (ByVal pPager As Pager Ptr) As sqlite3_file Ptr
Declare Function sqlite3PagerJournalname CDecl Alias "sqlite3PagerJournalname" (ByVal pPager As Pager Ptr) As Const ZString Ptr
Declare Function sqlite3PagerTempSpace CDecl Alias "sqlite3PagerTempSpace" (ByVal pPager As Pager Ptr) As Any Ptr
Declare Function sqlite3PagerIsMemdb CDecl Alias "sqlite3PagerIsMemdb" (ByVal pPager As Pager Ptr) As SQLITE_C_INT
Declare Function sqlite3PagerGetJournalMode CDecl Alias "sqlite3PagerGetJournalMode" (ByVal pPager As Pager Ptr) As SQLITE_C_INT
Declare Function sqlite3PagerWalSupported CDecl Alias "sqlite3PagerWalSupported" (ByVal pPager As Pager Ptr) As SQLITE_C_INT
#ifdef SQLITE_ENABLE_ZIPVFS
Declare Function sqlite3PagerWalFramesize CDecl Alias "sqlite3PagerWalFramesize" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
#endif
#ifndef SQLITE_OMIT_WAL
Declare Function sqlite3PagerCheckpoint CDecl Alias "sqlite3PagerCheckpoint" ( _
    ByVal pPager As Pager Ptr, _
    ByVal db As Any Ptr, _
    ByVal mode As SQLITE_C_INT, _
    ByVal pLogFrames As SQLITE_C_INT Ptr, _
    ByVal pCheckpointedFrames As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Function sqlite3PagerWalCallback CDecl Alias "sqlite3PagerWalCallback" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
Declare Sub sqlite3PagerWalDb CDecl Alias "sqlite3PagerWalDb" ( _
    ByVal pPager As Pager Ptr, _
    ByVal db As Any Ptr _
)
Declare Function sqlite3PagerWalWriteLock CDecl Alias "sqlite3PagerWalWriteLock" ( _
    ByVal pPager As Pager Ptr, _
    ByVal bLock As SQLITE_C_INT _
) As SQLITE_C_INT
#endif
#ifdef SQLITE_USE_SEH
Declare Function sqlite3WalSystemErrno CDecl Alias "sqlite3WalSystemErrno" ( _
    ByVal pWal As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3PagerWalSystemErrno CDecl Alias "sqlite3PagerWalSystemErrno" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
#endif
#ifdef SQLITE_ENABLE_SNAPSHOT
Declare Function sqlite3PagerSnapshotGet CDecl Alias "sqlite3PagerSnapshotGet" ( _
    ByVal pPager As Pager Ptr, _
    ByVal ppSnapshot As Any Ptr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3PagerSnapshotOpen CDecl Alias "sqlite3PagerSnapshotOpen" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pSnapshot As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3PagerSnapshotRecover CDecl Alias "sqlite3PagerSnapshotRecover" ( _
    ByVal pPager As Pager Ptr _
) As SQLITE_C_INT
Declare Function sqlite3PagerSnapshotCheck CDecl Alias "sqlite3PagerSnapshotCheck" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pSnapshot As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3PagerSnapshotUnlock CDecl Alias "sqlite3PagerSnapshotUnlock" ( _
    ByVal pPager As Pager Ptr _
)
#endif
#endif
Declare Function sqlite3PagerOpenWal CDecl Alias "sqlite3PagerOpenWal" ( _
    ByVal pPager As Pager Ptr, _
    ByVal pAlreadyOpen As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3PagerClearCache CDecl Alias "sqlite3PagerClearCache" (ByVal pPager As Pager Ptr)

#endif

/' end of sqlite3_pager.bi '/
