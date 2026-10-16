/'
    Project: SQLite FreeBASIC port

    File: sqlite3_db_types.bi

    Purpose:

        Define the FreeBASIC port's opaque connection and allocation state.

    Responsibilities:

        - Store the main VFS/B-tree handles, SQL and system error codes, and
          owned error value.
        - Retain a pending page size for the TEMP B-tree.
        - Protect interrupt state with a mutex independent of the connection lock.
        - Store the main/temp database slots and each slot's schema pointer.
        - Store active virtual-table context and transaction state.
        - Retain virtual tables queued for deferred disconnection.
        - Store named client-data entries owned by the connection.
        - Store the connection busy callback, arguments, retry count, and timeout.
        - Store per-connection user-defined scalar function definitions.
        - Store per-connection collation lookup state and the default CollSeq.
        - Track deferred and deferred-immediate foreign-key violation counts.
        - Store runtime database flags, mmap default, lock mode, temp-store mode, and pending schema state.
        - Track suppressed diagnostics and the connection's open-state marker.
        - Track temporary sorter bytes written for this connection.
        - Store per-connection lookaside allocation and OOM state.
        - Retain trace, profile, commit, rollback, update, and optional pre-update callback registrations.
        - Hold optional shared-cache blocked-connection and unlock-notify state.
        - Store the write-ahead-log callback and its application data under the connection mutex.
        - Track temporary byte-counting mode used during object cleanup.
        - Store the configured significant digits used for real-to-text output.
        - Declare the database-aware allocation routines used by engine code.
        - Define the caller-serialization contract for connection allocations.
        - Require initialization exactly once before any other operation.

    This file intentionally does NOT contain:

        - Prepared-statement or SQL execution state.
        - A layout compatible with SQLite's private C sqlite3 structure.
'/

#ifndef SQLITE3_FB_DB_TYPES_BI
#define SQLITE3_FB_DB_TYPES_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_mutex.bi"
#include once "sqlite3_hash_types.bi"
#include once "sqlite3_vdbe_compare.bi"
#include once "sqlite3_vtab_types.bi"

Type SqliteLookasideSlot
    pNext As SqliteLookasideSlot Ptr
End Type

' Connection-local lookaside pool state from src/sqliteInt.h. The small-pool
' size is stored separately because this port supports two slot classes.
Type SqliteLookasideState
    bDisable As u32
    sz As u16
    szTrue As u16
    bMalloced As u8
    nSlot As u32
    anStat(0 To 2) As u32
    pInit As SqliteLookasideSlot Ptr
    pFree As SqliteLookasideSlot Ptr
    pSmallInit As SqliteLookasideSlot Ptr
    pSmallFree As SqliteLookasideSlot Ptr
    pMiddle As UByte Ptr
    pStart As UByte Ptr
    pEnd As UByte Ptr
    pTrueEnd As UByte Ptr
    szSmall As u32
End Type

#ifndef SQLITE_OMIT_TWOSIZE_LOOKASIDE
#define SQLITE_LOOKASIDE_SMALL 128
#else
#define SQLITE_LOOKASIDE_SMALL 0
#endif

Type SqliteSavepoint
    zName As ZString Ptr
    ' Snapshot deferred-FK counts so ROLLBACK TO restores the savepoint state.
    nDeferredCons As sqlite3_int64
    nDeferredImmCons As sqlite3_int64
    pNext As SqliteSavepoint Ptr
End Type

Type SqliteProgressCallback As Function CDecl ( _
    ByVal pUserData As Any Ptr _
) As SQLITE_C_INT

Type SqliteBusyCallback As Function CDecl ( _
    ByVal pUserData As Any Ptr, _
    ByVal busyCount As SQLITE_C_INT _
) As SQLITE_C_INT

Type SqliteBusyHandler
    xBusyHandler As SqliteBusyCallback
    pBusyArg As Any Ptr
    nBusy As SQLITE_C_INT
    mxBusy As SQLITE_C_INT
End Type

Type SqliteCommitHookProc As Function CDecl (ByVal pArgument As Any Ptr) As SQLITE_C_INT
Type SqliteRollbackHookProc As Sub CDecl (ByVal pArgument As Any Ptr)
Type SqliteUpdateHookProc As Sub CDecl ( _
    ByVal pArgument As Any Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal zDatabase As Const ZString Ptr, _
    ByVal zTable As Const ZString Ptr, _
    ByVal rowId As sqlite3_int64 _
)
Type SqliteAuthorizerCallback As Function CDecl ( _
    ByVal pArgument As Any Ptr, _
    ByVal action As SQLITE_C_INT, _
    ByVal zArg1 As Const ZString Ptr, _
    ByVal zArg2 As Const ZString Ptr, _
    ByVal zDatabase As Const ZString Ptr, _
    ByVal zTrigger As Const ZString Ptr _
) As SQLITE_C_INT
Type SqliteAutovacuumPagesCallback As Function CDecl ( _
    ByVal pArgument As Any Ptr, _
    ByVal zDatabase As Const ZString Ptr, _
    ByVal pageCount As SQLITE_C_UINT, _
    ByVal pageSize As SQLITE_C_UINT, _
    ByVal pageCountToFree As SQLITE_C_UINT _
) As SQLITE_C_UINT
Type SqliteDbDestructor As Sub CDecl (ByVal pArgument As Any Ptr)
Type SqliteBuiltinExtensionInitProc As Function CDecl ( _
    ByVal pDatabase As Any Ptr _
) As SQLITE_C_INT
Type SqliteUnlockNotifyCallback As Sub CDecl ( _
    ByVal aArgument As Any Ptr Ptr, _
    ByVal argumentCount As SQLITE_C_INT _
)

Type SqliteDbInitInfo
    newTnum As u32
    iDb As u8
    busy As u8
    ' Storage for C's orphanTrigger, imposterTable, and reopenMemdb bitfields.
    flags As u32
    azInit As Const ZString Ptr Ptr
End Type

Type SqliteSchema
    schema_cookie As SQLITE_C_INT
    iGeneration As SQLITE_C_INT
    tblHash As Hash
    idxHash As Hash
    trigHash As Hash
    fkeyHash As Hash
    pSeqTab As Any Ptr
    file_format As u8
    enc As u8
    schemaFlags As u16
    cache_size As SQLITE_C_INT
End Type

Type SqliteDbSlot
    zDbSName As Const ZString Ptr
    pBt As Any Ptr
    safety_level As u8
    bSyncSet As u8
    pSchema As SqliteSchema Ptr
End Type

Type SqliteDbClientData
    pNext As SqliteDbClientData Ptr
    pData As Any Ptr
    xDestructor As Any Ptr
    ' The name bytes follow the three C-compatible pointer fields.
    zName As UByte
End Type

Union SqliteTraceCallbacks
    xLegacy As Any Ptr
    xV2 As Any Ptr
End Union

' Distinct byte patterns make accidental connection-state corruption easier
' to detect. The values match src/sqliteInt.h.
#define SQLITE_STATE_OPEN &H76
#define SQLITE_STATE_CLOSED &HCE
#define SQLITE_STATE_SICK &HBA
#define SQLITE_STATE_BUSY &H6D
#define SQLITE_STATE_ERROR &HD5
#define SQLITE_STATE_ZOMBIE &HA7
#define SQLITE_CONNECTION_OPEN 1
#define SQLITE_CONNECTION_FAILED 2

Type sqlite3
    ' Database allocation calls are serialized by the owning connection.
    ' Initialization and destruction require exclusive access to this object.
    mutex As Any Ptr
    ' Cross-thread interruption must not wait for the active VDBE's connection lock.
    interruptMutex As Any Ptr
    isInterrupted As SQLITE_C_INT
    nVdbeActive As SQLITE_C_INT
    pVfs As Any Ptr
    pMainBtree As Any Ptr
    nDb As SQLITE_C_INT
    ' Page size requested by VACUUM for the next TEMP database open.
    nextPagesize As SQLITE_C_INT
    ' Auto-vacuum mode requested for the next VACUUM; -1 means keep current.
    nextAutovac As Byte
    aDb(0 To SQLITE_MAX_ATTACHED + 1) As SqliteDbSlot
    pVdbe As Any Ptr
    nVdbeRead As SQLITE_C_INT
    nVdbeWrite As SQLITE_C_INT
    ' Active OP_VDestroy operations permitted during root-page destruction.
    nVDestroy As SQLITE_C_INT
    ' The owning connection mutex serializes this application-function list.
    pUserFunctions As Any Ptr
    ' Named client data and its destructors are serialized by the connection mutex.
    pDbData As SqliteDbClientData Ptr
    ' Collation entries are keyed by name and store one sequence per encoding.
    aCollSeq As Hash
    pDfltColl As sqlite3CollSeq Ptr
    xCollNeeded As Any Ptr
    xCollNeeded16 As Any Ptr
    pCollNeededArg As Any Ptr
    ' VDBE execution checks this handler under the owning connection mutex.
    xProgress As SqliteProgressCallback
    pProgressArg As Any Ptr
    nProgressOps As u32
    busyHandler As SqliteBusyHandler
    busyTimeout As SQLITE_C_INT
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    ' VFS lock timeout in milliseconds; -1 means use the longest supported wait.
    setlkTimeout As SQLITE_C_INT
    ' Preserve the block-on-connect request for newly opened database files.
    setlkFlags As SQLITE_C_INT
#endif
    nSchemaLock As u32
    nStatement As SQLITE_C_INT
    nExtension As SQLITE_C_INT
    aExtension As Any Ptr Ptr
    aModule As Hash
    init As SqliteDbInitInfo
    xAuth As SqliteAuthorizerCallback
    pAuthArg As Any Ptr
    pAutovacPagesArg As Any Ptr
    xAutovacDestr As SqliteDbDestructor
    xAutovacPages As SqliteAutovacuumPagesCallback
    ' Set only while a parser context is active on this connection.
    pParse As Any Ptr
    schemaInitBusy As u8
    pSavepoint As SqliteSavepoint Ptr
    nSavepoint As SQLITE_C_INT
    isTransactionSavepoint As u8
    noSharedCache As u8
    openFlags As SQLITE_C_UINT
    ' Current connection text encoding, initialized to UTF-8.
    enc As u8
    ' Runtime database configuration flags controlled by PRAGMA and API calls.
    flags As sqlite3_uint64
    ' Default mmap limit applied to newly opened database files.
    szMmap As sqlite3_int64
    dbOptFlags As u32
    ' Per-connection values initialized from the compile-time SQLite limits.
    aLimit(0 To SQLITE_N_LIMIT - 1) As SQLITE_C_INT
    ' Maximum rows scanned per index when ANALYZE uses a sampling limit.
    nAnalysisLimit As SQLITE_C_INT
    ' Upper bound for mmap growth of temporary sorter files.
    nMaxSorterMmap As SQLITE_C_INT
    ' Runtime SQLITE_TEMP_STORE override: 0 default, 1 file, 2 memory.
    temp_store As u8
    ' Default locking mode used when a database is attached.
    dfltLockMode As u8
    mDbFlags As u32
    errorCode As SQLITE_C_INT
    ' Controls whether API exits return primary or extended result codes.
    errMask As SQLITE_C_INT
    ' Suppress parser diagnostics while probing for optional schema objects.
    suppressErr As u8
    ' OS error code captured for SQLITE_CANTOPEN and SQLITE_IOERR failures.
    iSysErrno As SQLITE_C_INT
    ' Owned dynamic error text copied from the last VDBE error.
    pErr As Any Ptr
    lastRowid As sqlite3_int64
    nChange As sqlite3_int64
    nTotalChange As sqlite3_int64
    ' Net deferred foreign-key violations for the current transaction.
    nDeferredCons As sqlite3_int64
    nDeferredImmCons As sqlite3_int64
    ' Counts VDBE execution frames for nested trace formatting.
    nVdbeExec As SQLITE_C_INT
#ifndef SQLITE_OMIT_VIRTUALTABLE
    ' Virtual-table transaction and active connect/create context state.
    nVTrans As SQLITE_C_INT
    pVtabCtx As Any Ptr
    aVTrans As Any Ptr Ptr
    pDisconnect As SqliteVTable Ptr
    vtabOnConflict As u8
#endif
    autoCommit As u8
    errByteOffset As SQLITE_C_INT
    isOpen As u8
    isZombie As u8
    ' SQLite connection-state marker used by API armor and close handling.
    eOpenState As u8
    mallocFailed As u8
    bBenignMalloc As u8
    ' Non-NULL while freeing schemas or statements to estimate their memory use.
    pnBytesFreed As SQLITE_C_INT Ptr
    lengthLimit As SQLITE_C_INT
    ' Significant digits retained when numeric values are rendered as text.
    nFpDigit As u8
    lookaside As SqliteLookasideState
    lookasideInitCount As u32
    lookasideFreeCount As u32
    lookasideOutCount As u32
    ' Callback registrations are changed under the connection mutex.
    mTrace As u8
    ' Number of pending OP_SqlExec opcodes, used during ANALYZE code generation.
    nSqlExec As u8
    trace As SqliteTraceCallbacks
    pTraceArg As Any Ptr
#ifndef SQLITE_OMIT_DEPRECATED
    xProfile As Any Ptr
    pProfileArg As Any Ptr
#endif
    pCommitArg As Any Ptr
    xCommitCallback As Any Ptr
    pRollbackArg As Any Ptr
    xRollbackCallback As Any Ptr
    pUpdateArg As Any Ptr
    xUpdateCallback As Any Ptr
    pWalArg As Any Ptr
    xWalCallback As Any Ptr
#ifdef SQLITE_ENABLE_PREUPDATE_HOOK
    pPreUpdateArg As Any Ptr
    xPreUpdateCallback As Any Ptr
    pPreUpdate As Any Ptr
#endif
    ' Bytes written to temporary sorter files by this connection.
    nSpill As sqlite3_uint64
#ifdef SQLITE_ENABLE_UNLOCK_NOTIFY
    ' Shared-cache lock graph links and callback state, used under STATIC_MAIN.
    pBlockingConnection As sqlite3 Ptr
    pUnlockConnection As sqlite3 Ptr
    pUnlockArg As Any Ptr
    xUnlockNotify As SqliteUnlockNotifyCallback
    pNextBlocked As sqlite3 Ptr
#endif
End Type

#include once "sqlite3_stat4_types.bi"

' Stack context shared by sqlite3InitOne and sqlite3InitCallback.
Type SqliteInitData
    db As sqlite3 Ptr
    pzErrMsg As ZString Ptr Ptr
    iDb As SQLITE_C_INT
    rc As SQLITE_C_INT
    mInitFlags As u32
    nInitRow As u32
    mxPage As u32
End Type

' The callback is stored opaquely in sqlite3 so its field layout stays fixed.
Type SqliteWalHookCallback As Function CDecl ( _
    ByVal pArgument As Any Ptr, _
    ByVal db As sqlite3 Ptr, _
    ByVal zDatabase As Const ZString Ptr, _
    ByVal pageCount As SQLITE_C_INT _
) As SQLITE_C_INT

Declare Function sqlite3LimitInitialize CDecl Alias "sqlite3LimitInitialize" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
Declare Function sqlite3LimitHardValueTable CDecl Alias "sqlite3LimitHardValueTable" () As Const SQLITE_C_INT Ptr
Declare Function sqlite3ConfigLookasideSizeValue CDecl Alias "sqlite3ConfigLookasideSizeValue" () As SQLITE_C_INT
Declare Function sqlite3ConfigLookasideCountValue CDecl Alias "sqlite3ConfigLookasideCountValue" () As SQLITE_C_INT

Declare Function sqlite3DbContextInit CDecl Alias "sqlite3DbContextInit" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal createConnectionMutex As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3DbInterruptMutexInitialize CDecl Alias "sqlite3DbInterruptMutexInitialize" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3OomClear CDecl Alias "sqlite3OomClear" ( _
    ByVal db As sqlite3 Ptr _
)
Declare Function sqlite3ApiExit CDecl Alias "sqlite3ApiExit" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal resultCode As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3DbLookasideInit CDecl Alias "sqlite3DbLookasideInit" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal slotCount As u32, _
    ByVal slotSize As u32 _
) As SQLITE_C_INT
Declare Function sqlite3DbContextDestroy CDecl Alias "sqlite3DbContextDestroy" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
Declare Function sqlite3InvokeBusyHandler CDecl Alias "sqlite3InvokeBusyHandler" ( _
    ByVal pHandler As SqliteBusyHandler Ptr _
) As SQLITE_C_INT
Declare Function sqlite3InterruptPending CDecl Alias "sqlite3InterruptPending" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
Declare Function sqlite3DbMallocRaw CDecl Alias "sqlite3DbMallocRaw" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Function sqlite3DbMallocRawNN CDecl Alias "sqlite3DbMallocRawNN" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Function sqlite3DbMallocZero CDecl Alias "sqlite3DbMallocZero" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Function sqlite3DbRealloc CDecl Alias "sqlite3DbRealloc" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal p As Any Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Function sqlite3DbReallocOrFree CDecl Alias "sqlite3DbReallocOrFree" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal p As Any Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Function sqlite3DbStrDup CDecl Alias "sqlite3DbStrDup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal z As Const ZString Ptr _
) As Any Ptr
Declare Function sqlite3DbStrNDup CDecl Alias "sqlite3DbStrNDup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal z As Const ZString Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Function sqlite3DbSpanDup CDecl Alias "sqlite3DbSpanDup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zStart As Const ZString Ptr, _
    ByVal zEnd As Const ZString Ptr _
) As Any Ptr
Declare Sub sqlite3SetString CDecl Alias "sqlite3SetString" ( _
    ByVal pz As Any Ptr, _
    ByVal db As sqlite3 Ptr, _
    ByVal zNew As Const ZString Ptr _
)
Declare Function sqlite3DbMallocSize CDecl Alias "sqlite3DbMallocSize" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal p As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3DbFree CDecl Alias "sqlite3DbFree" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal p As Any Ptr _
)
Declare Sub sqlite3DbFreeNN CDecl Alias "sqlite3DbFreeNN" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal p As Any Ptr _
)
Declare Sub sqlite3DbNNFreeNN CDecl Alias "sqlite3DbNNFreeNN" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal p As Any Ptr _
)
Declare Function sqlite3DbMallocFailed CDecl Alias "sqlite3DbMallocFailed" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3DbClearMallocFailed CDecl Alias "sqlite3DbClearMallocFailed" ( _
    ByVal db As sqlite3 Ptr _
)
Declare Sub sqlite3DbSetBenignMalloc CDecl Alias "sqlite3DbSetBenignMalloc" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal benign As SQLITE_C_INT _
)
Declare Function sqlite3OomFault CDecl Alias "sqlite3OomFault" ( _
    ByVal db As sqlite3 Ptr _
) As Any Ptr
Declare Sub sqlite3DbEnter CDecl Alias "sqlite3DbEnter" (ByVal db As sqlite3 Ptr)
Declare Sub sqlite3DbLeave CDecl Alias "sqlite3DbLeave" (ByVal db As sqlite3 Ptr)
Declare Sub sqlite3ConnectionFinishZombie CDecl Alias "sqlite3ConnectionFinishZombie" (ByVal db As sqlite3 Ptr)
Declare Sub sqlite3DbFunctionDestroy CDecl Alias "sqlite3DbFunctionDestroy" ( _
    ByVal db As sqlite3 Ptr _
)
Declare Function c2fbBuiltinExtensionArray CDecl Alias "c2fbBuiltinExtensionArray" () As SqliteBuiltinExtensionInitProc Ptr
Declare Function c2fbBuiltinExtensionCount CDecl Alias "c2fbBuiltinExtensionCount" () As SQLITE_SIZE_T
Declare Function openDatabase CDecl Alias "openDatabase" ( _
    ByVal zFilename As Const ZString Ptr, _
    ByVal ppDb As sqlite3 Ptr Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal zVfs As Const ZString Ptr _
) As SQLITE_C_INT

#endif

/' end of sqlite3_db_types.bi '/
