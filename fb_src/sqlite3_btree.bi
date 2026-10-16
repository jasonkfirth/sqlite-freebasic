/'
    Project: SQLite FreeBASIC port

    File: sqlite3_btree.bi

    Purpose:

        Define B-tree page state and the pager-facing page interfaces.

    Responsibilities:

        - Preserve the MemPage and BtShared layouts used by page parsing.
        - Define the payload descriptor shared by B-tree cell writers.
        - Define the cell-array layout shared with the B-tree converter pass.
        - Define page flags, transaction states, and cell metadata.
        - Declare B-tree handle lifecycle and page acquisition/decoding calls.
        - Declare root-page creation for table and index B-trees.
        - Declare full table/index tree clearing and change-count reporting.
        - Declare B-tree root-page removal and freelist reclamation.
        - Declare the VACUUM file-copy helper, which requires write transactions on both B-trees.
        - Declare cache, pager-flag, and page-size controls.
        - Declare cursor-position and empty-tree query helpers.
        - Declare cursor hints/pinning and B-tree transaction-state queries.
        - Use the shared pending-byte global and declare cross-module page-map helpers.
        - Define the five pointer-map entry types used by auto-vacuum.
        - Declare pointer-map lookup for internal cross-module callers.
        - Define opaque cursor storage required by B-tree lookup APIs.
        - Document the BtShared mutex required around page state.

    This file intentionally does NOT contain:

        - Transaction or cursor algorithms, balancing, or SQL table operations.
        - Shared-cache table-lock policy.
'/ 

#ifndef SQLITE3_FB_BTREE_BI
#define SQLITE3_FB_BTREE_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_pager.bi"

#define PTF_INTKEY &H01
#define PTF_ZERODATA &H02
#define PTF_LEAFDATA &H04
#define PTF_LEAF &H08
#define BTREE_INTKEY 1
#define BTREE_BLOBKEY 2
#define BT_MAX_LOCAL 65501
#define TRANS_NONE 0
#define TRANS_READ 1
#define TRANS_WRITE 2
#define BTS_READ_ONLY &H0001
#define BTS_PAGESIZE_FIXED &H0002
#define BTS_SECURE_DELETE &H0004
#define BTS_OVERWRITE &H0008
#define BTS_FAST_SECURE &H000C
#define BTS_INITIALLY_EMPTY &H0010
#define BTS_NO_WAL &H0020
#define BTS_EXCLUSIVE &H0040
#define BTS_PENDING &H0080

#ifdef SQLITE_ENABLE_CURSOR_HINTS
#define BTREE_HINT_RANGE 0
#define BTREE_HINT_TABLECURSOR 1
#endif
#define READ_LOCK 1
#define WRITE_LOCK 2
#define BTREE_OMIT_JOURNAL 1
#define BTREE_MEMORY 2
#define BTREE_SINGLE 4
#define BTREE_UNORDERED 8
' These indexes identify metadata words in the database header. Schema version
' advances during VACUUM so other connections know to reload their schemas.
#define BTREE_SCHEMA_VERSION 1
#define BTREE_DEFAULT_CACHE_SIZE 3
#define BTREE_TEXT_ENCODING 5
#define BTREE_USER_VERSION 6
#define BTREE_APPLICATION_ID 8
#define BTREE_DATA_VERSION 15
#define BTREE_AUTOVACUUM_NONE 0
#define BTREE_AUTOVACUUM_FULL 1
#define BTREE_AUTOVACUUM_INCR 2
#define PTRMAP_ROOTPAGE 1
#define PTRMAP_FREEPAGE 2
#define PTRMAP_OVERFLOW1 3
#define PTRMAP_OVERFLOW2 4
#define PTRMAP_BTREE 5
#define BTREE_BULKLOAD &H0001
#define BTREE_SAVEPOSITION &H02
#define BTREE_AUXDELETE &H04

#define BTREE_APPEND &H08
#define BTREE_PREFORMAT &H80
#define BTCURSOR_MAX_DEPTH 20
#define BTCF_WRITE_FLAG &H01
#define BTCF_VALID_NKEY &H02
#define BTCF_VALID_OVFL &H04
#define BTCF_AT_LAST &H08
#define BTCF_INCRBLOB &H10
#define BTCF_MULTIPLE &H20
#define BTCF_PINNED &H40
#define CURSOR_VALID 0
#define CURSOR_INVALID 1
#define CURSOR_SKIPNEXT 2
#define CURSOR_REQUIRESEEK 3
#define CURSOR_FAULT 4
#define BTREE_WRCSR &H0004
#define BTREE_FORDELETE &H0008
#define BTREE_SEEK_EQ &H0002

Type BtShared
    pPager As Pager Ptr
    db As sqlite3 Ptr
    pCursor As Any Ptr
    pPage1 As Any Ptr
    openFlags As u8
#ifndef SQLITE_OMIT_AUTOVACUUM
    autoVacuum As u8
    incrVacuum As u8
    bDoTruncate As u8
#endif
    inTransaction As u8
    max1bytePayload As u8
    nReserveWanted As u8
    btsFlags As u16
    maxLocal As u16
    minLocal As u16
    maxLeaf As u16
    minLeaf As u16
    pageSize As u32
    usableSize As u32
    nTransaction As SQLITE_C_INT
    nPage As u32
    pSchema As Any Ptr
    xFreeSchema As Any Ptr
    mutex As Any Ptr
    pHasContent As Any Ptr
    ' Keep shared-cache slots in the private FreeBASIC layout so the converted
    ' B-tree procedures have stable fields across OMIT_SHARED_CACHE profiles.
    nRef As SQLITE_C_INT
    pNext As Any Ptr
    pLock As Any Ptr
    pWriter As Any Ptr
    pTmpSpace As UByte Ptr
    nPreformatSize As SQLITE_C_INT
End Type

Type BtLock
    pBtree As Any Ptr
    iTable As u32
    eLock As u8
    pNext As Any Ptr
End Type

Type Btree
    db As sqlite3 Ptr
    pBt As BtShared Ptr
    inTrans As u8
    sharable As u8
    locked As u8
    hasIncrblobCur As u8
    wantToLock As SQLITE_C_INT
    nBackup As SQLITE_C_INT
    iBDataVersion As u32
    pNext As Any Ptr
    pPrev As Any Ptr
#ifdef SQLITE_DEBUG
    nSeek As u64
#endif
    lock As BtLock
End Type

Type CellInfo
    nKey As i64
    pPayload As UByte Ptr
    nPayload As u32
    nLocal As u16
    nSize As u16
End Type

' Fields that do not apply to a table or index record are ignored, matching
' the BtreePayload layout from btree.h.
Type SqliteBtreePayload
    pKey As Const Any Ptr
    nKey As sqlite3_int64
    pData As Const Any Ptr
    aMem As Any Ptr
    nMem As u16
    nData As SQLITE_C_INT
    nZero As SQLITE_C_INT
End Type

' The B-tree stores these callbacks in MemPage. Any Ptr keeps the signature
' forward-declarable before MemPage while preserving the C pointer ABI.
Type BtreeCellSizeProc As Function CDecl ( _
    ByVal pPage As Any Ptr, _
    ByVal pCell As UByte Ptr _
) As u16

Type BtreeCellParseProc As Sub CDecl ( _
    ByVal pPage As Any Ptr, _
    ByVal pCell As UByte Ptr, _
    ByVal pInfo As Any Ptr _
)

Type MemPage
    isInit As u8
    intKey As u8
    intKeyLeaf As u8
    pgno As u32
    leaf As u8
    hdrOffset As u8
    childPtrSize As u8
    max1bytePayload As u8
    nOverflow As u8
    maxLocal As u16
    minLocal As u16
    cellOffset As u16
    nFree As SQLITE_C_INT
    nCell As u16
    maskPage As u16
    aiOvfl(0 To 3) As u16
    apOvfl(0 To 3) As UByte Ptr
    ' Preserve serialized sizes while overflow cells live outside a page.
    aiOvflSize(0 To 3) As u16
    pBt As BtShared Ptr
    aData As UByte Ptr
    aDataEnd As UByte Ptr
    aCellIdx As UByte Ptr
    aDataOfst As UByte Ptr
    pDbPage As PgHdr Ptr
    xCellSize As BtreeCellSizeProc
    xParseCell As BtreeCellParseProc
End Type

' NB is 3 in btree.c, so balancing tracks six page-end/cell-end stages.
#define BTREE_BALANCE_STAGE_COUNT 6
Type BtreeCellArray
    nCell As SQLITE_C_INT
    pRef As MemPage Ptr
    apCell As UByte Ptr Ptr
    szCell As u16 Ptr
    apEnd(0 To BTREE_BALANCE_STAGE_COUNT - 1) As UByte Ptr
    ixNx(0 To BTREE_BALANCE_STAGE_COUNT - 1) As SQLITE_C_INT
End Type

Type BtCursor
    eState As u8
    curFlags As u8
    curPagerFlags As u8
    hints As u8
    skipNext As SQLITE_C_INT
    pBtree As Btree Ptr
    aOverflow As u32 Ptr
    pKey As Any Ptr
#if defined(SQLITE_ENABLE_CURSOR_HINTS) AndAlso defined(SQLITE_DEBUG)
    pCursorHintTableCursor As BtCursor Ptr
#endif
    pBt As BtShared Ptr
    pNext As BtCursor Ptr
    info As CellInfo
    nKey As i64
    pgnoRoot As u32
    iPage As Byte
    curIntKey As u8
    ix As u16
    aiIdx(0 To BTCURSOR_MAX_DEPTH - 2) As u16
    pKeyInfo As Any Ptr
    pPage As MemPage Ptr
    apPage(0 To BTCURSOR_MAX_DEPTH - 2) As MemPage Ptr
End Type

#ifndef SQLITE_OMIT_AUTOVACUUM
' Pointer-map address calculation is shared by B-tree candidate modules.
Declare Function ptrmapPageno( _
    ByVal pBt As BtShared Ptr, _
    ByVal pageNumber As u32 _
) As u32
#endif

' These page helpers are shared by other internal source modules.
Declare Function btreePageFromDbPage CDecl Alias "btreePageFromDbPage" ( _
    ByVal pDbPage As PgHdr Ptr, _
    ByVal pageNumber As u32, _
    ByVal pBt As BtShared Ptr _
) As MemPage Ptr
Declare Function btreePagecount CDecl Alias "btreePagecount" ( _
    ByVal pBt As BtShared Ptr _
) As u32
Declare Function setChildPtrmaps CDecl Alias "setChildPtrmaps" ( _
    ByVal pPage As MemPage Ptr _
) As SQLITE_C_INT
Declare Sub releasePageNotNull CDecl Alias "releasePageNotNull" ( _
    ByVal pPage As MemPage Ptr _
)
Declare Sub releasePage CDecl Alias "releasePage" (ByVal pPage As MemPage Ptr)

Declare Function sqlite3BtreeOpen CDecl Alias "sqlite3BtreeOpen" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal zFilename As Const ZString Ptr, _
    ByVal db As sqlite3 Ptr, _
    ByVal ppBtree As Btree Ptr Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal vfsFlags As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3BtreeClose CDecl Alias "sqlite3BtreeClose" (ByVal pBtree As Btree Ptr) As SQLITE_C_INT
Declare Sub sqlite3BtreeEnter CDecl Alias "sqlite3BtreeEnter" (ByVal pBtree As Btree Ptr)
Declare Sub sqlite3BtreeLeave CDecl Alias "sqlite3BtreeLeave" (ByVal pBtree As Btree Ptr)
Declare Sub sqlite3BtreeEnterAll CDecl Alias "sqlite3BtreeEnterAll" (ByVal db As sqlite3 Ptr)
Declare Sub sqlite3BtreeLeaveAll CDecl Alias "sqlite3BtreeLeaveAll" (ByVal db As sqlite3 Ptr)
#ifdef SQLITE_DEBUG
Declare Function sqlite3BtreeHoldsMutex CDecl Alias "sqlite3BtreeHoldsMutex" (ByVal pBtree As Btree Ptr) As SQLITE_C_INT
Declare Function sqlite3BtreeHoldsAllMutexes CDecl Alias "sqlite3BtreeHoldsAllMutexes" (ByVal db As sqlite3 Ptr) As SQLITE_C_INT
Declare Function sqlite3SchemaMutexHeld CDecl Alias "sqlite3SchemaMutexHeld" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal databaseIndex As SQLITE_C_INT, _
    ByVal pSchema As Any Ptr _
) As SQLITE_C_INT
#endif
Declare Function sqlite3BtreeGetPageSize CDecl Alias "sqlite3BtreeGetPageSize" (ByVal pBtree As Btree Ptr) As SQLITE_C_INT
Declare Function sqlite3BtreeGetFilename CDecl Alias "sqlite3BtreeGetFilename" (ByVal pBtree As Btree Ptr) As Const ZString Ptr
Declare Function sqlite3BtreeGetJournalname CDecl Alias "sqlite3BtreeGetJournalname" (ByVal pBtree As Btree Ptr) As Const ZString Ptr
Declare Function sqlite3BtreePager CDecl Alias "sqlite3BtreePager" (ByVal pBtree As Btree Ptr) As Pager Ptr
Declare Function sqlite3BtreeSchema CDecl Alias "sqlite3BtreeSchema" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal xFreeSchema As Any Ptr _
) As Any Ptr
Declare Function sqlite3BtreeLastPage CDecl Alias "sqlite3BtreeLastPage" (ByVal pBtree As Btree Ptr) As u32
Declare Function sqlite3BtreeSetCacheSize CDecl Alias "sqlite3BtreeSetCacheSize" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal maxPages As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3BtreeSetSpillSize CDecl Alias "sqlite3BtreeSetSpillSize" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal maxPages As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3BtreeSetPagerFlags CDecl Alias "sqlite3BtreeSetPagerFlags" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal flags As SQLITE_C_UINT _
) As SQLITE_C_INT
Declare Function sqlite3BtreeSetPageSize CDecl Alias "sqlite3BtreeSetPageSize" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal pageSize As SQLITE_C_INT, _
    ByVal nReserve As SQLITE_C_INT, _
    ByVal fixPageSize As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3BtreeGetReserveNoMutex CDecl Alias "sqlite3BtreeGetReserveNoMutex" ( _
    ByVal pBtree As Btree Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeGetRequestedReserve CDecl Alias "sqlite3BtreeGetRequestedReserve" ( _
    ByVal pBtree As Btree Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeMaxPageCount CDecl Alias "sqlite3BtreeMaxPageCount" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal maxPage As u32 _
) As u32
Declare Function sqlite3BtreeSecureDelete CDecl Alias "sqlite3BtreeSecureDelete" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal newFlag As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3BtreeSetAutoVacuum CDecl Alias "sqlite3BtreeSetAutoVacuum" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal autoVacuum As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3BtreeGetAutoVacuum CDecl Alias "sqlite3BtreeGetAutoVacuum" ( _
    ByVal pBtree As Btree Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeIncrVacuum CDecl Alias "sqlite3BtreeIncrVacuum" ( _
    ByVal pBtree As Btree Ptr _
) As SQLITE_C_INT

' These internal page helpers are called by the translated auto-vacuum group.
Declare Function btreeGetHasContent CDecl Alias "btreeGetHasContent" ( _
    ByVal pBt As BtShared Ptr, _
    ByVal pageNumber As u32 _
) As SQLITE_C_INT
Declare Function modifyPagePointer CDecl Alias "modifyPagePointer" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal fromPage As u32, _
    ByVal toPage As u32, _
    ByVal pointerType As u8 _
) As SQLITE_C_INT
Declare Function sqlite3BtreeIsReadonly CDecl Alias "sqlite3BtreeIsReadonly" ( _
    ByVal pBtree As Btree Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeIsEmpty CDecl Alias "sqlite3BtreeIsEmpty" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeCursorHasMoved CDecl Alias "sqlite3BtreeCursorHasMoved" ( _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeCursorIsValidNN CDecl Alias "sqlite3BtreeCursorIsValidNN" ( _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeCursorIsValid CDecl Alias "sqlite3BtreeCursorIsValid" ( _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT
Declare Function sqlite3HeaderSizeBtree CDecl Alias "sqlite3HeaderSizeBtree" () As SQLITE_C_INT
Declare Sub sqlite3BtreeClearCache CDecl Alias "sqlite3BtreeClearCache" ( _
    ByVal pBtree As Btree Ptr _
)
Declare Function sqlite3BtreeBeginTrans CDecl Alias "sqlite3BtreeBeginTrans" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal writeFlag As SQLITE_C_INT, _
    ByVal pSchemaVersion As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeTxnState CDecl Alias "sqlite3BtreeTxnState" ( _
    ByVal pBtree As Btree Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeIsInBackup CDecl Alias "sqlite3BtreeIsInBackup" ( _
    ByVal pBtree As Btree Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeCommitPhaseOne CDecl Alias "sqlite3BtreeCommitPhaseOne" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal zSuperJournal As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeCommitPhaseTwo CDecl Alias "sqlite3BtreeCommitPhaseTwo" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal cleanupFlag As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3BtreeCommit CDecl Alias "sqlite3BtreeCommit" (ByVal pBtree As Btree Ptr) As SQLITE_C_INT
#ifndef SQLITE_OMIT_WAL
Declare Function sqlite3BtreeCheckpoint CDecl Alias "sqlite3BtreeCheckpoint" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal mode As SQLITE_C_INT, _
    ByVal pLogFrames As SQLITE_C_INT Ptr, _
    ByVal pCheckpointedFrames As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
#endif
Declare Function sqlite3BtreeRollback CDecl Alias "sqlite3BtreeRollback" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal tripCode As SQLITE_C_INT, _
    ByVal writeOnly As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3BtreeBeginStmt CDecl Alias "sqlite3BtreeBeginStmt" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal statementIndex As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3BtreeSavepoint CDecl Alias "sqlite3BtreeSavepoint" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal savepointIndex As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3BtreeNewDb CDecl Alias "sqlite3BtreeNewDb" (ByVal pBtree As Btree Ptr) As SQLITE_C_INT
Declare Function sqlite3BtreeCreateTable CDecl Alias "sqlite3BtreeCreateTable" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal pRootPage As u32 Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3BtreeClearTable CDecl Alias "sqlite3BtreeClearTable" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal rootPage As SQLITE_C_INT, _
    ByVal pChangeCount As sqlite3_int64 Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeClearTableOfCursor CDecl Alias "sqlite3BtreeClearTableOfCursor" ( _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeTripAllCursors CDecl Alias "sqlite3BtreeTripAllCursors" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal writeOnly As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3BtreeDropTable CDecl Alias "sqlite3BtreeDropTable" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal rootPage As SQLITE_C_INT, _
    ByVal pMovedPage As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3BtreeGetMeta CDecl Alias "sqlite3BtreeGetMeta" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal index As SQLITE_C_INT, _
    ByVal pMeta As u32 Ptr _
)
Declare Function sqlite3BtreeUpdateMeta CDecl Alias "sqlite3BtreeUpdateMeta" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal index As SQLITE_C_INT, _
    ByVal value As u32 _
) As SQLITE_C_INT
Declare Function sqlite3BtreeCursorSize CDecl Alias "sqlite3BtreeCursorSize" () As SQLITE_C_INT
Declare Sub sqlite3BtreeCursorZero CDecl Alias "sqlite3BtreeCursorZero" (ByVal pCursor As BtCursor Ptr)
Declare Sub sqlite3BtreeClearCursor CDecl Alias "sqlite3BtreeClearCursor" (ByVal pCursor As BtCursor Ptr)
#ifdef SQLITE_ENABLE_CURSOR_HINTS
Declare Sub sqlite3BtreeCursorHint CDecl Alias "sqlite3BtreeCursorHint" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal hintType As SQLITE_C_INT, _
    ... _
)
#endif
Declare Sub sqlite3BtreeCursorHintFlags CDecl Alias "sqlite3BtreeCursorHintFlags" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal hints As SQLITE_C_UINT _
)
#if defined(SQLITE_ENABLE_CURSOR_HINTS) AndAlso defined(SQLITE_DEBUG)
Declare Function sqlite3BtreeCursorHintTblCsr CDecl Alias "sqlite3BtreeCursorHintTblCsr" ( _
    ByVal pCursor As BtCursor Ptr _
) As BtCursor Ptr
#endif
Declare Function sqlite3BtreeCursorHasHint CDecl Alias "sqlite3BtreeCursorHasHint" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal mask As SQLITE_C_UINT _
) As SQLITE_C_INT
Declare Sub sqlite3BtreeCursorPin CDecl Alias "sqlite3BtreeCursorPin" (ByVal pCursor As BtCursor Ptr)
Declare Sub sqlite3BtreeCursorUnpin CDecl Alias "sqlite3BtreeCursorUnpin" (ByVal pCursor As BtCursor Ptr)
Declare Function sqlite3BtreeLockTable CDecl Alias "sqlite3BtreeLockTable" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal tableRootPage As SQLITE_C_INT, _
    ByVal isWriteLock As UByte _
) As SQLITE_C_INT
Declare Function sqlite3BtreeSharable CDecl Alias "sqlite3BtreeSharable" (ByVal pBtree As Btree Ptr) As SQLITE_C_INT
Declare Function sqlite3BtreeConnectionCount CDecl Alias "sqlite3BtreeConnectionCount" (ByVal pBtree As Btree Ptr) As SQLITE_C_INT
Declare Function sqlite3BtreeSetVersion CDecl Alias "sqlite3BtreeSetVersion" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal version As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3BtreeCopyFile CDecl Alias "sqlite3BtreeCopyFile" ( _
    ByVal pDestination As Btree Ptr, _
    ByVal pSource As Btree Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeCursor CDecl Alias "sqlite3BtreeCursor" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal rootPage As u32, _
    ByVal writeFlags As SQLITE_C_INT, _
    ByVal pKeyInfo As Any Ptr, _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT
#ifndef SQLITE_OMIT_INCRBLOB
Declare Sub sqlite3BtreeEnterCursor CDecl Alias "sqlite3BtreeEnterCursor" (ByVal pCursor As BtCursor Ptr)
#if SQLITE_THREADSAFE > 0
Declare Sub sqlite3BtreeLeaveCursor CDecl Alias "sqlite3BtreeLeaveCursor" (ByVal pCursor As BtCursor Ptr)
#endif
#endif
Declare Function sqlite3BtreeCloseCursor CDecl Alias "sqlite3BtreeCloseCursor" (ByVal pCursor As BtCursor Ptr) As SQLITE_C_INT
Declare Function sqlite3BtreeFirst CDecl Alias "sqlite3BtreeFirst" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeLast CDecl Alias "sqlite3BtreeLast" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeNext CDecl Alias "sqlite3BtreeNext" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3BtreePrevious CDecl Alias "sqlite3BtreePrevious" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3BtreeEof CDecl Alias "sqlite3BtreeEof" (ByVal pCursor As BtCursor Ptr) As SQLITE_C_INT
Declare Function sqlite3BtreeTableMoveto CDecl Alias "sqlite3BtreeTableMoveto" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal rowId As i64, _
    ByVal biasRight As SQLITE_C_INT, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeIndexMoveto CDecl Alias "sqlite3BtreeIndexMoveto" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pIndexKey As Any Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Function btreeMoveto CDecl Alias "btreeMoveto" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pKey As Const Any Ptr, _
    ByVal keySize As i64, _
    ByVal biasRight As SQLITE_C_INT, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeCursorRestore CDecl Alias "sqlite3BtreeCursorRestore" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeInsert CDecl Alias "sqlite3BtreeInsert" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pPayload As SqliteBtreePayload Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal seekResult As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3BtreeTransferRow CDecl Alias "sqlite3BtreeTransferRow" ( _
    ByVal pDestination As BtCursor Ptr, _
    ByVal pSource As BtCursor Ptr, _
    ByVal destinationRowId As i64 _
) As SQLITE_C_INT
Declare Function sqlite3BtreeDelete CDecl Alias "sqlite3BtreeDelete" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal flags As u8 _
) As SQLITE_C_INT
Declare Function sqlite3BtreeIntegerKey CDecl Alias "sqlite3BtreeIntegerKey" (ByVal pCursor As BtCursor Ptr) As i64
Declare Function sqlite3BtreePayloadSize CDecl Alias "sqlite3BtreePayloadSize" (ByVal pCursor As BtCursor Ptr) As u32
Declare Function sqlite3BtreePayload CDecl Alias "sqlite3BtreePayload" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal offset As u32, _
    ByVal amount As u32, _
    ByVal pBuffer As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreePayloadChecked CDecl Alias "sqlite3BtreePayloadChecked" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal offset As u32, _
    ByVal amount As u32, _
    ByVal pBuffer As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreePutData CDecl Alias "sqlite3BtreePutData" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal offset As u32, _
    ByVal amount As u32, _
    ByVal pBuffer As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3BtreeIncrblobCursor CDecl Alias "sqlite3BtreeIncrblobCursor" (ByVal pCursor As BtCursor Ptr)
Declare Function sqlite3BtreePayloadFetch CDecl Alias "sqlite3BtreePayloadFetch" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pAmount As u32 Ptr _
) As Const Any Ptr
Declare Function sqlite3BtreeOffset CDecl Alias "sqlite3BtreeOffset" (ByVal pCursor As BtCursor Ptr) As i64
Declare Function sqlite3BtreeMaxRecordSize CDecl Alias "sqlite3BtreeMaxRecordSize" (ByVal pCursor As BtCursor Ptr) As i64
Declare Function sqlite3BtreeCount CDecl Alias "sqlite3BtreeCount" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pEntryCount As i64 Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeRowCountEst CDecl Alias "sqlite3BtreeRowCountEst" ( _
    ByVal pCursor As BtCursor Ptr _
) As i64
Declare Function sqlite3BtreeInitPage CDecl Alias "sqlite3BtreeInitPage" ( _
    ByVal pPage As MemPage Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeInitPageForIntegrity CDecl Alias "sqlite3BtreeInitPageForIntegrity" ( _
    ByVal pPage As MemPage Ptr _
) As SQLITE_C_INT
Declare Function btreeInitPage ( _
    ByVal pPage As MemPage Ptr _
) As SQLITE_C_INT
' The cell parser is stored as a callback and shared by translated B-tree code.
Declare Sub btreeParseCellPtr CDecl Alias "btreeParseCellPtr" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As UByte Ptr, _
    ByVal pInfo As CellInfo Ptr _
)
Declare Sub btreeParseCellPtrIndex CDecl Alias "btreeParseCellPtrIndex" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As UByte Ptr, _
    ByVal pInfo As CellInfo Ptr _
)
Declare Sub btreeParseCellPtrNoPayload CDecl Alias "btreeParseCellPtrNoPayload" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As UByte Ptr, _
    ByVal pInfo As CellInfo Ptr _
)
Declare Function cellSizePtr CDecl Alias "cellSizePtr" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As UByte Ptr _
) As u16
Declare Function cellSizePtrIdxLeaf CDecl Alias "cellSizePtrIdxLeaf" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As UByte Ptr _
) As u16
Declare Function cellSizePtrNoPayload CDecl Alias "cellSizePtrNoPayload" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As UByte Ptr _
) As u16
Declare Function cellSizePtrTableLeaf CDecl Alias "cellSizePtrTableLeaf" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As UByte Ptr _
) As u16
Declare Function sqlite3BtreeGetAndInitPage CDecl Alias "sqlite3BtreeGetAndInitPage" ( _
    ByVal pBt As BtShared Ptr, _
    ByVal pageNumber As u32, _
    ByVal ppPage As MemPage Ptr Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Sub sqlite3BtreeReleasePage CDecl Alias "sqlite3BtreeReleasePage" ( _
    ByVal pPage As MemPage Ptr _
)
Declare Function sqlite3BtreeGetCellInfo CDecl Alias "sqlite3BtreeGetCellInfo" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal cellIndex As SQLITE_C_INT, _
    ByVal pInfo As CellInfo Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeCellSize CDecl Alias "sqlite3BtreeCellSize" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As UByte Ptr _
) As u16
Declare Function sqlite3BtreeComputeFreeSpace CDecl Alias "sqlite3BtreeComputeFreeSpace" ( _
    ByVal pPage As MemPage Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeDropCell CDecl Alias "sqlite3BtreeDropCell" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal cellIndex As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3BtreeSeekCount CDecl Alias "sqlite3BtreeSeekCount" ( _
    ByVal pBtree As Btree Ptr _
) As sqlite3_uint64

#endif

/' end of sqlite3_btree.bi '/
