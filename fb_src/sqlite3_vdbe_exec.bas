/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_exec.bas

    Purpose:

        Execute SQLite's generated VDBE instructions against database and
        virtual-table state.

    Responsibilities:

        - Dispatch the generated instructions enabled by the current build.
        - Invoke virtual-table callbacks for scans, updates, and integrity checks.
        - Invoke optional pre-update callbacks before B-tree row mutations.
        - Open transient B-tree and sorter cursors for ephemeral query state.
        - Feed and traverse external-sorter records through VDBE opcodes.
        - Add join keys to Bloom filters and reject definite misses.
        - Store, test, and extract integer rowids through RowSet opcodes.
        - Transfer control through register-backed SELECT coroutines.
        - Execute trigger subprograms in reusable VDBE frames and copy parent values.
        - Decode requested record columns and load overflow-backed large values.
        - Perform register, arithmetic, comparison, branch, row, and halt operations.
        - Preserve program-counter and statement-counter state across SQLITE_ROW.
        - Check immediate/deferred foreign-key counters while finishing a VDBE.
        - Verify active VDBE connection counters after cursor cleanup and halt.
        - Validate the linked savepoint count during debug OP_Savepoint handling.
        - Execute OP_Once state tracking and reset it at the configured trace threshold.
        - Maintain SQLITE_TEST VDBE search, found, and sort counters at opcode points.
        - Destroy database roots, unlink dropped schema objects, and reload schema entries.
        - Print debug register values and validate their Mem invariants.

    This file intentionally does NOT contain:

        - Sorter internals or scalar and aggregate SQL function implementations.
        - Application-defined virtual-table modules.
'/

#lang "fb"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_vdbe_cursor.bi"
#include once "sqlite3_vdbe_affinity.bi"
#include once "sqlite3_vdbe_compare.bi"
#include once "sqlite3_vdbe_record.bi"
#include once "sqlite3_vdbe_serial.bi"
#include once "sqlite3_vdbe_api.bi"
#include once "sqlite3_vdbe_mem_text.bi"
#include once "sqlite3_rowset.bi"
#include once "sqlite3_iotrace.bi"
#include once "sqlite3_util_numeric.bi"
#include once "sqlite3_api_constants.bi"
#include once "sqlite3_debug_assert.bi"
#include once "sqlite3_std_types.bi"
#include once "sqlite3_vdbe_test.bi"

Declare Function sqlite3VdbeCursorRestore CDecl Alias "sqlite3VdbeCursorRestore" ( _
    ByVal pCursor As SqliteVdbeCursor Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3VdbeEnter CDecl Alias "sqlite3VdbeEnter" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
Declare Sub sqlite3VdbeLeave CDecl Alias "sqlite3VdbeLeave" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
Declare Function sqlite3VdbeIdxRowid CDecl Alias "sqlite3VdbeIdxRowid" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pRowid As sqlite3_int64 Ptr _
) As SQLITE_C_INT
#ifdef SQLITE_ENABLE_PREUPDATE_HOOK
Declare Sub sqlite3VdbePreUpdateHook CDecl Alias "sqlite3VdbePreUpdateHook" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pCursor As SqliteVdbeCursor Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal zDatabase As Const ZString Ptr, _
    ByVal pTable As Any Ptr, _
    ByVal oldRowid As sqlite3_int64, _
    ByVal newValueRegister As SQLITE_C_INT, _
    ByVal blobWriteColumn As SQLITE_C_INT _
)
#endif
#ifdef SQLITE_DEBUG
#include once "sqlite3_straccum.bi"
Extern "C"
    Declare Sub sqlite3VdbeExecDebugPrintf CDecl Alias "sqlite3DebugPrintf" ( _
        ByVal format As Const ZString Ptr, _
        ... _
    )
End Extern
#endif

#ifndef SQLITE_MAX_FUNCTION_ARG
#define SQLITE_MAX_FUNCTION_ARG 1000
#endif
Private Const SQLITE3_VDBE_META_COUNT As SQLITE_C_INT = 16
Private Const SQLITE3_VDBE_SCHEMA_VERSION_META As SQLITE_C_INT = 1
Private Const SQLITE3_VDBE_FILE_FORMAT_META As SQLITE_C_INT = 2
Private Const SQLITE3_VDBE_DBFLAG_SCHEMA_CHANGE As u32 = &H0001
Private Const SQLITE3_VDBE_DBFLAG_SCHEMA_KNOWN_OK As u32 = &H0010
Private Const SQLITE3_VDBE_DBFLAG_READ_UNCOMMIT As sqlite3_uint64 = _
    &H0000000400000000ULL
Private Const SQLITE3_VDBE_DBFLAG_QUERY_ONLY As sqlite3_uint64 = &H00100000ULL
Private Const SQLITE3_VDBE_DBFLAG_CORRUPT_RDONLY As sqlite3_uint64 = _
    &H0000000200000000ULL

#ifdef SQLITE_TEST
Dim Shared sqlite3_search_count As SQLITE_C_INT
Dim Shared sqlite3_found_count As SQLITE_C_INT
Dim Shared sqlite3_sort_count As SQLITE_C_INT
#endif

Type SqliteVdbeVtabOpenProc As Function CDecl ( _
    ByVal pVtab As SqliteVtab Ptr, _
    ByVal ppCursor As SqliteVtabCursor Ptr Ptr _
) As SQLITE_C_INT
Type SqliteVdbeVtabCloseProc As Function CDecl ( _
    ByVal pCursor As SqliteVtabCursor Ptr _
) As SQLITE_C_INT
Type SqliteVdbeVtabFilterProc As Function CDecl ( _
    ByVal pCursor As SqliteVtabCursor Ptr, _
    ByVal indexNumber As SQLITE_C_INT, _
    ByVal indexString As Const ZString Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
) As SQLITE_C_INT
Type SqliteVdbeVtabNextProc As Function CDecl ( _
    ByVal pCursor As SqliteVtabCursor Ptr _
) As SQLITE_C_INT
Type SqliteVdbeVtabEofProc As Function CDecl ( _
    ByVal pCursor As SqliteVtabCursor Ptr _
) As SQLITE_C_INT
Type SqliteVdbeVtabColumnProc As Function CDecl ( _
    ByVal pCursor As SqliteVtabCursor Ptr, _
    ByVal pContext As SqliteResultContext Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As SQLITE_C_INT
Type SqliteVdbeVtabRowidProc As Function CDecl ( _
    ByVal pCursor As SqliteVtabCursor Ptr, _
    ByVal pRowid As sqlite3_int64 Ptr _
) As SQLITE_C_INT
Type SqliteVdbeVtabUpdateProc As Function CDecl ( _
    ByVal pVtab As SqliteVtab Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr, _
    ByVal pRowid As sqlite3_int64 Ptr _
) As SQLITE_C_INT
Type SqliteVdbeVtabRenameProc As Function CDecl ( _
    ByVal pVtab As SqliteVtab Ptr, _
    ByVal zNewName As Const ZString Ptr _
) As SQLITE_C_INT
Type SqliteVdbeVtabIntegrityProc As Function CDecl ( _
    ByVal pVtab As SqliteVtab Ptr, _
    ByVal zDatabaseName As Const ZString Ptr, _
    ByVal zTableName As Const ZString Ptr, _
    ByVal checkFlags As SQLITE_C_INT, _
    ByVal pzError As ZString Ptr Ptr _
) As SQLITE_C_INT

Declare Sub sqlite3VdbeValueListFree CDecl Alias "sqlite3VdbeValueListFree" ( _
    ByVal pToDelete As Any Ptr _
)
Declare Sub sqlite3VdbeExecFree CDecl Alias "sqlite3_free" ( _
    ByVal pToDelete As Any Ptr _
)
Declare Function sqlite3VtabCallDestroy CDecl Alias "sqlite3VtabCallDestroy" ( _
    ByVal db As Any Ptr, _
    ByVal databaseIndex As SQLITE_C_INT, _
    ByVal zTableName As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3Malloc CDecl Alias "sqlite3Malloc" ( _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Sub sqlite3VtabLock CDecl Alias "sqlite3VtabLock" ( _
    ByVal pVtable As Any Ptr _
)
Declare Sub sqlite3VtabUnlock CDecl Alias "sqlite3VtabUnlock" ( _
    ByVal pVtable As Any Ptr _
)
Declare Function sqlite3VtabSavepoint CDecl Alias "sqlite3VtabSavepoint" ( _
    ByVal db As Any Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal savepointIndex As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3PagerSetJournalMode CDecl Alias "sqlite3PagerSetJournalMode" ( _
    ByVal pPager As Pager Ptr, _
    ByVal journalMode As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3PagerCloseWal CDecl Alias "sqlite3PagerCloseWal" ( _
    ByVal pPager As Pager Ptr, _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
Declare Function sqlite3JournalModename CDecl Alias "sqlite3JournalModename" ( _
    ByVal journalMode As SQLITE_C_INT _
) As Const ZString Ptr
Declare Function sqlite3Checkpoint CDecl Alias "sqlite3Checkpoint" ( _
    ByVal db As Any Ptr, _
    ByVal databaseIndex As SQLITE_C_INT, _
    ByVal checkpointMode As SQLITE_C_INT, _
    ByVal pWalPages As SQLITE_C_INT Ptr, _
    ByVal pCheckpointedPages As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeExecCommit CDecl Alias "sqlite3VdbeExecCommit" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3CloseSavepoints CDecl Alias "sqlite3CloseSavepoints" ( _
    ByVal db As sqlite3 Ptr _
)
Declare Sub sqlite3CommitInternalChanges CDecl Alias "sqlite3CommitInternalChanges" ( _
    ByVal db As sqlite3 Ptr _
)
Declare Function sqlite3VdbeCloseStatement CDecl Alias "sqlite3VdbeCloseStatement" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal operation As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Sub sqlite3RollbackAll CDecl Alias "sqlite3RollbackAll" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal errorCode As SQLITE_C_INT _
)

Declare Function sqlite3StrICmp CDecl Alias "sqlite3StrICmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3RCStrRef CDecl Alias "sqlite3RCStrRef" ( _
    ByVal zData As ZString Ptr _
) As ZString Ptr
Declare Sub sqlite3RCStrUnref CDecl Alias "sqlite3RCStrUnref" ( _
    ByVal zData As Any Ptr _
)
Declare Function sqlite3RCStrNew CDecl Alias "sqlite3RCStrNew" ( _
    ByVal nDataByte As sqlite3_uint64 _
) As ZString Ptr
Declare Function sqlite3ConfigTestOnceResetThreshold CDecl Alias "sqlite3ConfigTestOnceResetThreshold" () As SQLITE_C_INT
Declare Function sqlite3AnalysisLoad CDecl Alias "sqlite3AnalysisLoad" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal databaseIndex As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3VtabBegin CDecl Alias "sqlite3VtabBegin" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pVtable As SqliteVTable Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VtabCallCreate CDecl Alias "sqlite3VtabCallCreate" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal databaseIndex As SQLITE_C_INT, _
    ByVal zTableName As Const ZString Ptr, _
    ByVal pzErrorMessage As ZString Ptr Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3VtabImportErrmsg CDecl Alias "sqlite3VtabImportErrmsg" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pVtab As SqliteVtab Ptr _
)
Declare Function sqlite3BtreeIntegrityCheck CDecl Alias "sqlite3BtreeIntegrityCheck" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pBtree As Btree Ptr, _
    ByVal rootPages As SQLITE_C_UINT Ptr, _
    ByVal objectNames As SqliteVdbeMem Ptr, _
    ByVal rootCount As SQLITE_C_INT, _
    ByVal maxErrors As SQLITE_C_INT, _
    ByVal pErrorCount As SQLITE_C_INT Ptr, _
    ByVal pzError As ZString Ptr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeFindIndexKey CDecl Alias "sqlite3VdbeFindIndexKey" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pIndex As SqliteIndex Ptr, _
    ByVal pRecord As Any Ptr, _
    ByVal pComparison As SQLITE_C_INT Ptr, _
    ByVal integrityCheck As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3WritableSchema CDecl Alias "sqlite3WritableSchema" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
Declare Function sqlite3RunVacuum CDecl Alias "sqlite3RunVacuum" ( _
    ByVal pzErrorMessage As ZString Ptr Ptr, _
    ByVal db As sqlite3 Ptr, _
    ByVal databaseIndex As SQLITE_C_INT, _
    ByVal pOutput As SqliteVdbeMem Ptr _
) As SQLITE_C_INT
#ifdef SQLITE_DEBUG
' Upstream replaces this counter call with an empty macro outside debug builds.
Declare Sub sqlite3VdbeIncrWriteCounter CDecl Alias "sqlite3VdbeIncrWriteCounter" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pCursor As SqliteVdbeCursor Ptr _
)
#endif
Declare Function sqlite3InitOne CDecl Alias "sqlite3InitOne" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal databaseIndex As SQLITE_C_INT, _
    ByVal pzErrMsg As ZString Ptr Ptr, _
    ByVal initFlags As SQLITE_C_UINT _
) As SQLITE_C_INT
Declare Function sqlite3InitCallback CDecl Alias "sqlite3InitCallback" ( _
    ByVal pArgument As Any Ptr, _
    ByVal nColumn As SQLITE_C_INT, _
    ByVal azValue As ZString Ptr Ptr, _
    ByVal azColumn As ZString Ptr Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3SchemaClear CDecl Alias "sqlite3SchemaClear" ( _
    ByVal pSchema As SqliteSchema Ptr _
)
Declare Sub sqlite3ResetAllSchemasOfConnection CDecl Alias "sqlite3ResetAllSchemasOfConnection" ( _
    ByVal db As sqlite3 Ptr _
)
Declare Function sqlite3MPrintf CDecl Alias "sqlite3MPrintf" ( _
    ByVal db As Any Ptr, _
    ByVal format As Const ZString Ptr, _
    ... _
) As ZString Ptr
Declare Function sqlite3_exec CDecl Alias "sqlite3_exec" ( _
    ByVal db As Any Ptr, _
    ByVal sql As Const ZString Ptr, _
    ByVal callback As Any Ptr, _
    ByVal callbackArgument As Any Ptr, _
    ByVal errorMessage As ZString Ptr Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3ResetOneSchema CDecl Alias "sqlite3ResetOneSchema" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal databaseIndex As SQLITE_C_INT _
)
Declare Sub sqlite3UnlinkAndDeleteTable CDecl Alias "sqlite3UnlinkAndDeleteTable" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal databaseIndex As SQLITE_C_INT, _
    ByVal tableName As Const ZString Ptr _
)
Declare Sub sqlite3UnlinkAndDeleteIndex CDecl Alias "sqlite3UnlinkAndDeleteIndex" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal databaseIndex As SQLITE_C_INT, _
    ByVal indexName As Const ZString Ptr _
)
Declare Sub sqlite3UnlinkAndDeleteTrigger CDecl Alias "sqlite3UnlinkAndDeleteTrigger" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal databaseIndex As SQLITE_C_INT, _
    ByVal triggerName As Const ZString Ptr _
)
Declare Sub sqlite3RootPageMoved CDecl Alias "sqlite3RootPageMoved" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal databaseIndex As SQLITE_C_INT, _
    ByVal movedPage As SQLITE_C_UINT, _
    ByVal oldRootPage As SQLITE_C_UINT _
)
#ifndef SQLITE_OMIT_FOREIGN_KEY
Declare Sub sqlite3FkClearTriggerCache CDecl Alias "sqlite3FkClearTriggerCache" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal databaseIndex As SQLITE_C_INT _
)
#endif
Declare Function sqlite3VdbeFilterHash CDecl Alias "sqlite3VdbeFilterHash" ( _
    ByVal pMem As Const SqliteVdbeMem Ptr, _
    ByVal pOp As Const SqliteVdbeOp Ptr _
) As sqlite3_uint64
Declare Function sqlite3VdbeSorterWrite CDecl Alias "sqlite3VdbeSorterWrite" ( _
    ByVal pCursor As Const SqliteVdbeCursor Ptr, _
    ByVal pRecord As SqliteVdbeMem Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeSorterRewind CDecl Alias "sqlite3VdbeSorterRewind" ( _
    ByVal pCursor As Const SqliteVdbeCursor Ptr, _
    ByVal pEof As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeSorterNext CDecl Alias "sqlite3VdbeSorterNext" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pCursor As Const SqliteVdbeCursor Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeSorterRowkey CDecl Alias "sqlite3VdbeSorterRowkey" ( _
    ByVal pCursor As Const SqliteVdbeCursor Ptr, _
    ByVal pResult As SqliteVdbeMem Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeSorterCompare CDecl Alias "sqlite3VdbeSorterCompare" ( _
    ByVal pCursor As Const SqliteVdbeCursor Ptr, _
    ByVal pKey As SqliteVdbeMem Ptr, _
    ByVal nKeyColumn As SQLITE_C_INT, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3VdbeSorterReset CDecl Alias "sqlite3VdbeSorterReset" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pSorter As Any Ptr _
)
Declare Sub sqlite3VdbeFrameMemDel CDecl Alias "sqlite3VdbeFrameMemDel" ( _
    ByVal pFrame As Any Ptr _
)
Declare Function sqlite3VdbeFrameRestore CDecl Alias "sqlite3VdbeFrameRestore" ( _
    ByVal pFrame As SqliteVdbeFrame Ptr _
) As SQLITE_C_INT
Declare Sub closeAllCursors CDecl Alias "closeAllCursors" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)

Extern "C"
    Declare Function sqlite3VdbeExecMemcpy CDecl Alias "memcpy" ( _
        ByVal destination As Any Ptr, _
        ByVal source As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
    Declare Sub sqlite3VdbeExecRandomness CDecl Alias "sqlite3_randomness" ( _
        ByVal nByte As SQLITE_C_INT, _
        ByVal pBuffer As Any Ptr _
    )
End Extern

/'
    Table prefix from src/sqliteInt.h. Only zName, aCol, and tabFlags are
    read by the update hook. Keep every preceding field to preserve offsets.
'/ 
Private Type SqliteVdbeHookTable
    zName As ZString Ptr
    aCol As Any Ptr
    pIndex As Any Ptr
    zColAff As ZString Ptr
    pCheck As Any Ptr
    tnum As u32
    nTabRef As u32
    tabFlags As u32
End Type

Private Dim Shared As ZString * 1 sqlite3VdbeExecEmptyPayload = !""

Private Function vdbeExecMemIsRowSet( _
    ByVal pMem As SqliteVdbeMem Ptr _
) As SQLITE_C_INT
    If pMem = 0 OrElse _
       (pMem->flags And (MEM_BLOB Or MEM_DYN)) <> (MEM_BLOB Or MEM_DYN) Then _
        Return 0
    If pMem->xDel = @sqlite3RowSetDelete Then Return 1
    Return 0
End Function

Private Function vdbeExecColumnType( _
    ByVal pColumn As SqliteColumn Ptr _
) As UByte
    If pColumn = 0 Then Return COLTYPE_CUSTOM
    Dim packedTypes As UByte = _
        CPtr(Const UByte Ptr, pColumn)[SizeOf(Any Ptr)]
    Dim endianProbe As UShort = 1
    If *CPtr(Const UByte Ptr, @endianProbe) = 1 Then
        Return (packedTypes Shr 4) And &HF
    End If
    Return packedTypes And &HF
End Function

Private Function vdbeExecMemTypeName( _
    ByVal pMem As SqliteVdbeMem Ptr _
) As Const ZString Ptr
    If pMem = 0 Then Return StrPtr(!"NULL")
    If (pMem->flags And MEM_INT) <> 0 Then Return StrPtr(!"INT")
    If (pMem->flags And (MEM_REAL Or MEM_INTREAL)) <> 0 Then _
        Return StrPtr(!"REAL")
    If (pMem->flags And MEM_STR) <> 0 Then Return StrPtr(!"TEXT")
    If (pMem->flags And MEM_BLOB) <> 0 Then Return StrPtr(!"BLOB")
    Return StrPtr(!"NULL")
End Function

Private Function vdbeExecBtreeMaskTest( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal databaseIndex As SQLITE_C_INT _
) As SQLITE_C_INT
    If pVdbe = 0 OrElse databaseIndex < 0 OrElse _
       databaseIndex >= pVdbe->db->nDb Then Return 0
#if SQLITE_MAX_ATTACHED > 30
    Dim byteIndex As SQLITE_C_INT = databaseIndex \ 8
    Dim bitIndex As SQLITE_C_INT = databaseIndex And 7
    Return CInt((pVdbe->btreeMask(byteIndex) And (1 Shl bitIndex)) <> 0)
#else
    Return CInt((pVdbe->btreeMask And (CULng(1) Shl databaseIndex)) <> 0)
#endif
End Function

Private Function vdbeOpenEphemeralCursor( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pOp As SqliteVdbeOp Ptr _
) As SQLITE_C_INT
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse pOp = 0 OrElse _
       pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
       pOp->p2 < 0 OrElse pVdbe->apCsr = 0 Then Return SQLITE_CORRUPT
    If pOp->p4type <> P4_NOTUSED AndAlso pOp->p4type <> P4_KEYINFO Then _
        Return SQLITE_CORRUPT
    If pOp->p4type = P4_KEYINFO AndAlso pOp->p4.p = 0 Then _
        Return SQLITE_CORRUPT
    If pOp->p3 < 0 OrElse _
       (pOp->p3 > 0 AndAlso (pOp->p2 <> 0 OrElse pOp->opcode <> OP_OpenEphemeral OrElse _
        pOp->p3 >= pVdbe->nMem OrElse _
        (pVdbe->aMem[pOp->p3].flags And MEM_NULL) = 0)) Then _
        Return SQLITE_CORRUPT

    Dim pKeyInfo As Any Ptr = 0
    If pOp->p4type = P4_KEYINFO Then pKeyInfo = pOp->p4.p
    Dim pCursor As SqliteVdbeCursor Ptr = allocateCursor( _
        pVdbe, pOp->p1, pOp->p2, CURTYPE_BTREE)
    If pCursor = 0 Then Return SQLITE_NOMEM
    pCursor->cursorFlags Or= VDBE_CURSOR_EPHEMERAL
    pCursor->pKeyInfo = pKeyInfo
    pCursor->isTable = CByte(pKeyInfo = 0)
    pCursor->iDb = -1
    pCursor->nullRow = 1
    pCursor->pgnoRoot = 0

    Const transientOpenFlags As SQLITE_C_INT = _
        SQLITE_OPEN_READWRITE Or SQLITE_OPEN_CREATE Or SQLITE_OPEN_EXCLUSIVE Or _
        SQLITE_OPEN_DELETEONCLOSE Or SQLITE_OPEN_TRANSIENT_DB
    Dim rc As SQLITE_C_INT = sqlite3BtreeOpen( _
        pVdbe->db->pVfs, 0, pVdbe->db, @pCursor->ub.pBtx, _
        BTREE_OMIT_JOURNAL Or BTREE_SINGLE Or pOp->p5, transientOpenFlags)
    If rc = SQLITE_OK Then _
        rc = sqlite3BtreeBeginTrans(pCursor->ub.pBtx, 1, 0)
    If rc = SQLITE_OK Then
        If pKeyInfo <> 0 Then
            rc = sqlite3BtreeCreateTable( _
                pCursor->ub.pBtx, @pCursor->pgnoRoot, BTREE_BLOBKEY Or pOp->p5)
        Else
            pCursor->pgnoRoot = 1
        End If
    End If
    If rc = SQLITE_OK Then
        rc = sqlite3BtreeCursor( _
            pCursor->ub.pBtx, pCursor->pgnoRoot, BTREE_WRCSR, _
            pKeyInfo, pCursor->uc.pCursor)
    End If
    If rc <> SQLITE_OK Then
        If pCursor->uc.pCursor <> 0 Then
            sqlite3BtreeCloseCursor(pCursor->uc.pCursor)
            pCursor->uc.pCursor = 0
        End If
        If pCursor->ub.pBtx <> 0 Then
            sqlite3BtreeClose(pCursor->ub.pBtx)
            pCursor->ub.pBtx = 0
        End If
        pVdbe->apCsr[pOp->p1] = 0
        Return rc
    End If

    sqlite3BtreeCursorHintFlags( _
        pCursor->uc.pCursor, pOp->p5 And (BTREE_BULKLOAD Or BTREE_SEEK_EQ))
    If pOp->p3 > 0 Then
        pVdbe->aMem[pOp->p3].n = 0
        pVdbe->aMem[pOp->p3].z = CPtr( _
            UByte Ptr, StrPtr(sqlite3VdbeExecEmptyPayload))
    End If
    Return SQLITE_OK
End Function

Private Function vdbeUpdateHookContext( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pCursor As SqliteVdbeCursor Ptr, _
    ByVal pOp As SqliteVdbeOp Ptr, _
    ByRef pTable As SqliteVdbeHookTable Ptr, _
    ByRef zDatabase As Const ZString Ptr _
) As SQLITE_C_INT
    pTable = 0
    zDatabase = 0
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse pCursor = 0 OrElse pOp = 0 Then _
        Return SQLITE_MISUSE
    If pOp->p4type <> P4_TABLE Then Return SQLITE_OK
    If pVdbe->db->xUpdateCallback = 0 Then
#ifdef SQLITE_ENABLE_PREUPDATE_HOOK
        If pVdbe->db->xPreUpdateCallback = 0 Then Return SQLITE_OK
#else
        Return SQLITE_OK
#endif
    End If
    If pOp->p4.p = 0 OrElse pCursor->iDb < 0 OrElse _
       pCursor->iDb >= pVdbe->db->nDb Then Return SQLITE_CORRUPT

    pTable = CPtr(SqliteVdbeHookTable Ptr, pOp->p4.p)
    zDatabase = pVdbe->db->aDb(pCursor->iDb).zDbSName
    If pTable->zName = 0 OrElse zDatabase = 0 Then Return SQLITE_CORRUPT
    Return SQLITE_OK
End Function

Private Sub vdbeInvokeUpdateHook( _
    ByVal db As sqlite3 Ptr, _
    ByVal pTable As SqliteVdbeHookTable Ptr, _
    ByVal zDatabase As Const ZString Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal rowId As sqlite3_int64 _
)
    If db = 0 OrElse pTable = 0 OrElse db->xUpdateCallback = 0 Then Exit Sub
    If (pTable->tabFlags And TF_WithoutRowid) <> 0 Then Exit Sub

    Dim xUpdate As SqliteUpdateHookProc = _
        CPtr(SqliteUpdateHookProc, db->xUpdateCallback)
    xUpdate(db->pUpdateArg, operation, zDatabase, pTable->zName, rowId)
End Sub

Private Sub sqlite3VdbeExecClearSavepoints(ByVal db As sqlite3 Ptr)
    If db = 0 Then Return
    While db->pSavepoint <> 0
        Dim pSavepoint As SqliteSavepoint Ptr = db->pSavepoint
        db->pSavepoint = pSavepoint->pNext
        sqlite3DbFree(db, pSavepoint)
    Wend
    db->nSavepoint = 0
    db->isTransactionSavepoint = 0
End Sub

/' Record statement changes for sqlite3_changes() and total_changes(). '/
Sub sqlite3VdbeSetChanges CDecl Alias "sqlite3VdbeSetChanges" ( _
    ByVal pDatabase As Any Ptr, _
    ByVal changeCount As sqlite3_int64 _
) Export
    If pDatabase = 0 Then Return
    Dim db As sqlite3 Ptr = CPtr(sqlite3 Ptr, pDatabase)
    db->nChange = changeCount
    db->nTotalChange += changeCount
End Sub

#ifndef SQLITE_OMIT_FOREIGN_KEY
Private Function vdbeFkError(ByVal pVdbe As SqliteVdbe Ptr) As SQLITE_C_INT
    If pVdbe = 0 Then Return SQLITE_MISUSE
    pVdbe->rc = SQLITE_CONSTRAINT_FOREIGNKEY
    pVdbe->errorAction = OE_ABORT
    sqlite3VdbeError(pVdbe, StrPtr("FOREIGN KEY constraint failed"))
    If (pVdbe->prepFlags And SQLITE_PREPARE_SAVESQL) = 0 Then Return SQLITE_ERROR
    Return SQLITE_CONSTRAINT_FOREIGNKEY
End Function

Function sqlite3VdbeCheckFkImmediate CDecl Alias "sqlite3VdbeCheckFkImmediate" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT Export
    If pVdbe = 0 Then Return SQLITE_MISUSE
    If pVdbe->nFkConstraint = 0 Then Return SQLITE_OK
    Return vdbeFkError(pVdbe)
End Function

Function sqlite3VdbeCheckFkDeferred CDecl Alias "sqlite3VdbeCheckFkDeferred" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT Export
    If pVdbe = 0 OrElse pVdbe->db = 0 Then Return SQLITE_MISUSE
    Dim db As sqlite3 Ptr = pVdbe->db
    If db->nDeferredCons + db->nDeferredImmCons = 0 Then Return SQLITE_OK
    Return vdbeFkError(pVdbe)
End Function
#endif

Private Function vdbeInvokeCommitHook( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pBtree As Btree Ptr _
) As SQLITE_C_INT
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse pBtree = 0 Then Return SQLITE_OK
    If sqlite3BtreeTxnState(pBtree) <> TRANS_WRITE OrElse _
       pVdbe->db->xCommitCallback = 0 Then Return SQLITE_OK

    Dim xCommit As SqliteCommitHookProc = _
        CPtr(SqliteCommitHookProc, pVdbe->db->xCommitCallback)
    If xCommit(pVdbe->db->pCommitArg) <> 0 Then Return SQLITE_CONSTRAINT_COMMITHOOK
    Return SQLITE_OK
End Function

Private Sub vdbeInvokeRollbackHook( _
    ByVal db As sqlite3 Ptr, _
    ByVal wasInTransaction As SQLITE_C_INT _
)
    If db = 0 OrElse db->xRollbackCallback = 0 OrElse _
       (wasInTransaction = 0 AndAlso db->autoCommit <> 0) Then Return

    Dim xRollback As SqliteRollbackHookProc = _
        CPtr(SqliteRollbackHookProc, db->xRollbackCallback)
    xRollback(db->pRollbackArg)
End Sub

#ifdef SQLITE_DEBUG
Private Sub checkActiveVdbeCnt(ByVal db As sqlite3 Ptr)
    If db = 0 Then
        sqlite3DebugAssert(StrPtr("db is valid"))
        Exit Sub
    End If

    Dim activeCount As SQLITE_C_INT = 0
    Dim readCount As SQLITE_C_INT = 0
    Dim writeCount As SQLITE_C_INT = 0
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, db->pVdbe)
    While pVdbe <> 0
        If pVdbe->eVdbeState = VDBE_RUN_STATE Then
            activeCount += 1
            If (pVdbe->vdbeFlags And VDBE_READONLY_MASK) = 0 Then _
                writeCount += 1
            If (pVdbe->vdbeFlags And VDBE_BISREADER_MASK) <> 0 Then _
                readCount += 1
        End If
        pVdbe = CPtr(SqliteVdbe Ptr, pVdbe->pVNext)
    Wend

    If activeCount <> db->nVdbeActive Then _
        sqlite3DebugAssert(StrPtr("active VDBE count matches db->nVdbeActive"))
    If writeCount <> db->nVdbeWrite Then _
        sqlite3DebugAssert(StrPtr("write VDBE count matches db->nVdbeWrite"))
    If readCount <> db->nVdbeRead Then _
        sqlite3DebugAssert(StrPtr("reader VDBE count matches db->nVdbeRead"))
End Sub
#endif

Private Function sqlite3VdbeExecFinish( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal resultCode As SQLITE_C_INT, _
    ByVal errorAction As SQLITE_C_INT _
) As SQLITE_C_INT
    If pVdbe = 0 OrElse pVdbe->db = 0 Then Return SQLITE_MISUSE

    ' A reset may halt a VDBE after sqlite3_step() returned SQLITE_ROW,
    ' when sqlite3VdbeExec() no longer holds the shared-cache locks.
    sqlite3VdbeEnter(pVdbe)
    closeAllCursors(pVdbe)
#ifdef SQLITE_DEBUG
    checkActiveVdbeCnt(pVdbe->db)
#endif
    Dim primaryResultCode As SQLITE_C_INT = resultCode And &HFF
    Dim isSpecialError As SQLITE_C_INT = CInt( _
        primaryResultCode = SQLITE_NOMEM OrElse _
        primaryResultCode = SQLITE_IOERR OrElse _
        primaryResultCode = SQLITE_INTERRUPT OrElse _
        primaryResultCode = SQLITE_FULL)
#ifndef SQLITE_OMIT_FOREIGN_KEY
    If resultCode = SQLITE_OK OrElse _
       (errorAction = OE_FAIL AndAlso isSpecialError = 0) Then
        Dim immediateForeignKeyCode As SQLITE_C_INT = _
            sqlite3VdbeCheckFkImmediate(pVdbe)
        If immediateForeignKeyCode <> SQLITE_OK Then
            resultCode = pVdbe->rc
            errorAction = pVdbe->errorAction
        End If
    End If
#endif
    Dim vdbeIsReadOnly As SQLITE_C_INT = CInt( _
        (pVdbe->vdbeFlags And VDBE_READONLY_MASK) <> 0)
    Dim statementOperation As SQLITE_C_INT = 0
    If (pVdbe->vdbeFlags And VDBE_BISREADER_MASK) <> 0 AndAlso _
       resultCode <> SQLITE_OK AndAlso isSpecialError <> 0 Then
        If vdbeIsReadOnly = 0 OrElse primaryResultCode <> SQLITE_INTERRUPT Then
            If (primaryResultCode = SQLITE_NOMEM OrElse _
                primaryResultCode = SQLITE_FULL) AndAlso _
               (pVdbe->vdbeFlags And VDBE_USES_STMT_JOURNAL_MASK) <> 0 Then
                statementOperation = SAVEPOINT_ROLLBACK
            Else
                ' Journal or cache writes may have stopped part-way through.
                ' Roll back the whole transaction when no statement journal
                ' can restore the database to a consistent state.
                sqlite3RollbackAll(pVdbe->db, SQLITE_ABORT_ROLLBACK)
                sqlite3CloseSavepoints(pVdbe->db)
                pVdbe->db->autoCommit = 1
                pVdbe->nChange = 0
            End If
        End If
    End If
    Dim expectedWriteCount As SQLITE_C_INT = IIf(vdbeIsReadOnly <> 0, 0, 1)
    Dim shouldCommitOnHalt As SQLITE_C_INT = CInt( _
        pVdbe->db->autoCommit <> 0 AndAlso _
        (pVdbe->vdbeFlags And VDBE_BISREADER_MASK) <> 0 AndAlso _
        pVdbe->db->nVdbeWrite = expectedWriteCount)

    If statementOperation <> 0 OrElse _
       (errorAction <> OE_ROLLBACK AndAlso _
        (pVdbe->vdbeFlags And VDBE_USES_STMT_JOURNAL_MASK) <> 0 AndAlso _
        pVdbe->iStatement <> 0) Then
        Dim statementAction As SQLITE_C_INT = statementOperation
        If statementAction = 0 Then statementAction = SAVEPOINT_RELEASE
        If statementOperation = 0 AndAlso resultCode <> SQLITE_OK AndAlso _
           errorAction <> OE_FAIL AndAlso errorAction <> OE_IGNORE Then
            statementAction = SAVEPOINT_ROLLBACK
        End If
        Dim statementCloseCode As SQLITE_C_INT = _
            sqlite3VdbeCloseStatement(pVdbe, statementAction)
        pVdbe->vdbeFlags = _
            pVdbe->vdbeFlags And Not VDBE_USES_STMT_JOURNAL_MASK
        If statementCloseCode <> SQLITE_OK Then
            resultCode = statementCloseCode
            errorAction = OE_ROLLBACK
        End If
    End If

    If resultCode = SQLITE_OK AndAlso shouldCommitOnHalt <> 0 Then
        Dim deferredCode As SQLITE_C_INT = SQLITE_OK
#ifndef SQLITE_OMIT_FOREIGN_KEY
        deferredCode = sqlite3VdbeCheckFkDeferred(pVdbe)
#endif
        If deferredCode <> SQLITE_OK Then
            resultCode = SQLITE_CONSTRAINT_FOREIGNKEY
        Else
            Dim commitCode As SQLITE_C_INT = _
                sqlite3VdbeExecCommit(pVdbe->db, pVdbe)
            If commitCode <> SQLITE_OK Then
                ' A busy explicit COMMIT must leave its transaction open so
                ' the caller can release readers and retry the commit.
                If commitCode = SQLITE_BUSY AndAlso vdbeIsReadOnly <> 0 Then
                    sqlite3VdbeLeave(pVdbe)
                    Return SQLITE_BUSY
                End If
                resultCode = commitCode
                errorAction = OE_ROLLBACK
            Else
                pVdbe->db->nStatement = 0
#ifndef SQLITE_OMIT_FOREIGN_KEY
                pVdbe->db->nDeferredCons = 0
                pVdbe->db->nDeferredImmCons = 0
                pVdbe->db->flags = _
                    pVdbe->db->flags And Not SQLITE_DeferFKs
#endif
                ' Commit closes the current schema-change epoch.
                sqlite3CommitInternalChanges(pVdbe->db)
            End If
        End If
    End If

    If resultCode <> SQLITE_OK Then
        If errorAction <> OE_ROLLBACK AndAlso _
           (pVdbe->vdbeFlags And VDBE_USES_STMT_JOURNAL_MASK) <> 0 AndAlso _
           pVdbe->iStatement <> 0 Then
            Dim statementAction As SQLITE_C_INT = SAVEPOINT_ROLLBACK
            If errorAction = OE_FAIL OrElse errorAction = OE_IGNORE Then _
                statementAction = SAVEPOINT_RELEASE
            Dim statementCloseCode As SQLITE_C_INT = _
                sqlite3VdbeCloseStatement(pVdbe, statementAction)
            pVdbe->vdbeFlags = _
                pVdbe->vdbeFlags And Not VDBE_USES_STMT_JOURNAL_MASK
            If statementCloseCode <> SQLITE_OK Then
                resultCode = statementCloseCode
                errorAction = OE_ROLLBACK
            End If
        End If

        If errorAction = OE_ROLLBACK Then
            ' Keep the statement error in resultCode. SQLITE_OK tells the
            ' B-tree layer to roll back without faulting active cursors.
            sqlite3RollbackAll(pVdbe->db, SQLITE_OK)
            pVdbe->db->autoCommit = 1
            pVdbe->db->nStatement = 0
            pVdbe->vdbeFlags = _
                pVdbe->vdbeFlags And Not VDBE_USES_STMT_JOURNAL_MASK
            sqlite3VdbeExecClearSavepoints(pVdbe->db)
            pVdbe->iStatement = 0
#ifndef SQLITE_OMIT_FOREIGN_KEY
            pVdbe->db->nDeferredCons = 0
            pVdbe->db->nDeferredImmCons = 0
            pVdbe->db->flags = _
                pVdbe->db->flags And Not SQLITE_DeferFKs
#endif
        ElseIf shouldCommitOnHalt <> 0 Then
            If errorAction = OE_FAIL OrElse errorAction = OE_IGNORE Then
                Dim commitCode As SQLITE_C_INT = SQLITE_OK
#ifndef SQLITE_OMIT_FOREIGN_KEY
                If sqlite3VdbeCheckFkDeferred(pVdbe) <> SQLITE_OK Then _
                    commitCode = SQLITE_CONSTRAINT_FOREIGNKEY
#endif
                If commitCode = SQLITE_OK Then _
                    commitCode = sqlite3VdbeExecCommit(pVdbe->db, pVdbe)
                If commitCode <> SQLITE_OK Then
                    ' The commit error is returned below; rollback itself is
                    ' an ordinary transaction abort.
                    sqlite3RollbackAll(pVdbe->db, SQLITE_OK)
                    pVdbe->db->autoCommit = 1
                    pVdbe->db->nStatement = 0
                    pVdbe->vdbeFlags = _
                        pVdbe->vdbeFlags And Not VDBE_USES_STMT_JOURNAL_MASK
                    sqlite3VdbeExecClearSavepoints(pVdbe->db)
                    pVdbe->iStatement = 0
                    resultCode = commitCode
                Else
                    sqlite3CommitInternalChanges(pVdbe->db)
                End If
            Else
                sqlite3RollbackAll(pVdbe->db, SQLITE_OK)
                pVdbe->db->autoCommit = 1
                pVdbe->db->nStatement = 0
                pVdbe->vdbeFlags = _
                    pVdbe->vdbeFlags And Not VDBE_USES_STMT_JOURNAL_MASK
                sqlite3VdbeExecClearSavepoints(pVdbe->db)
                pVdbe->iStatement = 0
#ifndef SQLITE_OMIT_FOREIGN_KEY
                pVdbe->db->nDeferredCons = 0
                pVdbe->db->nDeferredImmCons = 0
                pVdbe->db->flags = _
                    pVdbe->db->flags And Not SQLITE_DeferFKs
#endif
            End If
        End If
    End If
    If resultCode = SQLITE_OK AndAlso _
       (pVdbe->vdbeFlags And VDBE_CHANGECOUNT_MASK) <> 0 Then
        sqlite3VdbeSetChanges(pVdbe->db, pVdbe->nChange)
    End If
    pVdbe->rc = resultCode
    If pVdbe->eVdbeState = VDBE_RUN_STATE Then
        sqlite3_mutex_enter(pVdbe->db->interruptMutex)
        If pVdbe->db->nVdbeActive > 0 Then pVdbe->db->nVdbeActive -= 1
        If pVdbe->db->nVdbeActive = 0 Then pVdbe->db->isInterrupted = 0
        sqlite3_mutex_leave(pVdbe->db->interruptMutex)
        If (pVdbe->vdbeFlags And VDBE_READONLY_MASK) = 0 AndAlso _
           pVdbe->db->nVdbeWrite > 0 Then _
            pVdbe->db->nVdbeWrite -= 1
        If (pVdbe->vdbeFlags And VDBE_BISREADER_MASK) <> 0 AndAlso _
           pVdbe->db->nVdbeRead > 0 Then _
            pVdbe->db->nVdbeRead -= 1
#ifdef SQLITE_DEBUG
        If pVdbe->db->nVdbeActive < pVdbe->db->nVdbeRead Then _
            sqlite3DebugAssert(StrPtr("nVdbeActive >= nVdbeRead"))
        If pVdbe->db->nVdbeRead < pVdbe->db->nVdbeWrite Then _
            sqlite3DebugAssert(StrPtr("nVdbeRead >= nVdbeWrite"))
        If pVdbe->db->nVdbeWrite < 0 Then _
            sqlite3DebugAssert(StrPtr("nVdbeWrite >= 0"))
#endif
    End If
    pVdbe->eVdbeState = VDBE_HALT_STATE
#ifdef SQLITE_DEBUG
    checkActiveVdbeCnt(pVdbe->db)
#endif
    If pVdbe->resetSchemaOnFault <> 0 Then
        If resultCode <> SQLITE_OK Then _
            sqlite3ResetOneSchema( _
                pVdbe->db, CInt(pVdbe->resetSchemaOnFault) - 1)
        pVdbe->resetSchemaOnFault = 0
    End If
    pVdbe->pResultRow = 0
    pVdbe->db->errorCode = resultCode
    sqlite3VdbeLeave(pVdbe)
    If resultCode = SQLITE_OK Then Return SQLITE_DONE
    Return resultCode
End Function

Private Function sqlite3VdbeExecError( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal resultCode As SQLITE_C_INT _
) As SQLITE_C_INT
    If pVdbe = 0 OrElse pVdbe->db = 0 Then Return resultCode
    Dim errorAction As SQLITE_C_INT = pVdbe->errorAction
    If errorAction = 0 Then errorAction = OE_ABORT
    Dim finishCode As SQLITE_C_INT = _
        sqlite3VdbeExecFinish(pVdbe, resultCode, errorAction)
    sqlite3VdbeLeave(pVdbe)
    If finishCode = SQLITE_DONE Then Return SQLITE_DONE
    ' The VDBE abort path returns SQLITE_ERROR while retaining the original
    ' cause in pVdbe->rc for sqlite3_reset() and sqlite3_finalize().
    Return SQLITE_ERROR
End Function

Private Function sqlite3VdbeExecProgressCheck( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT
    If pVdbe = 0 OrElse pVdbe->db = 0 Then Return SQLITE_MISUSE
    Dim db As sqlite3 Ptr = pVdbe->db
    If sqlite3InterruptPending(db) <> 0 Then Return SQLITE_INTERRUPT
    If db->xProgress = 0 OrElse db->nProgressOps = 0 Then Return SQLITE_OK
    If pVdbe->aCounter(SQLITE_STMTSTATUS_VM_STEP) Mod db->nProgressOps <> 0 Then _
        Return SQLITE_OK
    Dim xProgress As SqliteProgressCallback = db->xProgress
    If xProgress(db->pProgressArg) <> 0 OrElse _
       sqlite3InterruptPending(db) <> 0 Then Return SQLITE_INTERRUPT
    Return SQLITE_OK
End Function

#ifdef SQLITE_DEBUG
Private Function checkSavepointCount CDecl Alias "checkSavepointCount" ( _
    ByVal pDb As sqlite3 Ptr _
) As SQLITE_C_INT
    If pDb = 0 Then
        sqlite3DebugAssert(StrPtr("db != 0"))
        Return 0
    End If

    Dim savepointCount As SQLITE_C_INT = 0
    Dim pSavepoint As SqliteSavepoint Ptr = pDb->pSavepoint
    While pSavepoint <> 0
        savepointCount += 1
        pSavepoint = pSavepoint->pNext
    Wend

    If savepointCount <> pDb->nSavepoint + pDb->isTransactionSavepoint Then
        sqlite3DebugAssert( _
            StrPtr("savepoint list count matches nSavepoint + isTransactionSavepoint"))
        Return 0
    End If
    Return 1
End Function
#endif

Function sqlite3VdbeHalt CDecl Alias "sqlite3VdbeHalt" ( _
    ByVal pVdbeArgument As Any Ptr _
) As SQLITE_C_INT Export
    If pVdbeArgument = 0 Then Return SQLITE_MISUSE
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pVdbeArgument)
    If pVdbe->db = 0 Then Return SQLITE_MISUSE
    If pVdbe->eVdbeState <> VDBE_RUN_STATE Then Return pVdbe->rc
    ' Reset may halt a VDBE after sqlite3_step() already returned an error.
    ' Preserve that result instead of replacing it with SQLITE_OK.
    Dim rc As SQLITE_C_INT = _
        sqlite3VdbeExecFinish(pVdbe, pVdbe->rc, OE_ABORT)
    If rc = SQLITE_DONE Then Return SQLITE_OK
    Return rc
End Function

Sub sqlite3VdbeExecResetCleanup CDecl Alias "sqlite3VdbeExecResetCleanup" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) Export
    If pVdbe = 0 OrElse pVdbe->db = 0 Then Exit Sub
    closeAllCursors(pVdbe)
End Sub

Private Function sqlite3VdbeExecArithmetic( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pOp As SqliteVdbeOp Ptr _
) As SQLITE_C_INT
    If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
       pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
       pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem Then Return SQLITE_CORRUPT

    Dim pLeft As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p1]
    Dim pRight As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p2]
    Dim pOut As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p3]
    If ((pLeft->flags Or pRight->flags) And MEM_NULL) <> 0 Then
        sqlite3VdbeMemSetNull(pOut)
        Return SQLITE_OK
    End If

    Dim leftType As UShort = sqlite3VdbeNumericType(pLeft)
    Dim rightType As UShort = sqlite3VdbeNumericType(pRight)
    If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If (leftType And rightType And MEM_INT) <> 0 Then
        Dim leftInteger As sqlite3_int64 = pLeft->u.i
        Dim rightInteger As sqlite3_int64 = pRight->u.i
        Dim overflow As SQLITE_C_INT = 0
        Select Case pOp->opcode
        Case OP_Add
            overflow = sqlite3AddInt64(@rightInteger, leftInteger)
        Case OP_Subtract
            overflow = sqlite3SubInt64(@rightInteger, leftInteger)
        Case OP_Multiply
            overflow = sqlite3MulInt64(@rightInteger, leftInteger)
        Case OP_Divide
            If leftInteger = 0 Then
                sqlite3VdbeMemSetNull(pOut)
                Return SQLITE_OK
            End If
            If leftInteger = -1 AndAlso rightInteger = &H8000000000000000LL Then
                overflow = 1
            Else
                rightInteger = rightInteger \ leftInteger
            End If
        Case OP_Remainder
            If leftInteger = 0 Then
                sqlite3VdbeMemSetNull(pOut)
                Return SQLITE_OK
            End If
            If leftInteger = -1 Then leftInteger = 1
            rightInteger -= (rightInteger \ leftInteger) * leftInteger
        End Select
        If overflow = 0 Then
            sqlite3VdbeMemSetInt64(pOut, rightInteger)
            Return SQLITE_OK
        End If
    End If

    If pOp->opcode = OP_Remainder Then
        Dim leftInteger As sqlite3_int64 = sqlite3VdbeIntValue(pLeft)
        Dim rightInteger As sqlite3_int64 = sqlite3VdbeIntValue(pRight)
        If leftInteger = 0 Then
            sqlite3VdbeMemSetNull(pOut)
            Return SQLITE_OK
        End If
        If leftInteger = -1 Then leftInteger = 1
        rightInteger -= (rightInteger \ leftInteger) * leftInteger
        sqlite3VdbeMemSetDouble(pOut, CDbl(rightInteger))
        Return SQLITE_OK
    End If

    Dim leftReal As Double = sqlite3VdbeRealValue(pLeft)
    Dim rightReal As Double = sqlite3VdbeRealValue(pRight)
    Select Case pOp->opcode
    Case OP_Add
        rightReal += leftReal
    Case OP_Subtract
        rightReal -= leftReal
    Case OP_Multiply
        rightReal *= leftReal
    Case OP_Divide
        If leftReal = 0.0 Then
            sqlite3VdbeMemSetNull(pOut)
            Return SQLITE_OK
        End If
        rightReal /= leftReal
    Case Else
        Return SQLITE_CORRUPT
    End Select
    sqlite3VdbeMemSetDouble(pOut, rightReal)
    Return SQLITE_OK
End Function

Private Function sqlite3VdbeExecConcat( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pOp As SqliteVdbeOp Ptr _
) As SQLITE_C_INT

    If pVdbe = 0 OrElse pOp = 0 OrElse _
       pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
       pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
       pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem Then Return SQLITE_CORRUPT

    Dim leftValue As SqliteVdbeMem
    Dim rightValue As SqliteVdbeMem
    sqlite3VdbeMemInit(@leftValue, pVdbe->db, MEM_NULL)
    sqlite3VdbeMemInit(@rightValue, pVdbe->db, MEM_NULL)
    ' OP_Concat encodes the SQL left operand in P2 and the right in P1.
    Dim rc As SQLITE_C_INT = sqlite3VdbeMemCopy( _
        @leftValue, @pVdbe->aMem[pOp->p2])
    If rc = SQLITE_OK Then rc = sqlite3VdbeMemCopy( _
        @rightValue, @pVdbe->aMem[pOp->p1])

    If rc = SQLITE_OK AndAlso _
       ((leftValue.flags Or rightValue.flags) And MEM_NULL) <> 0 Then
        sqlite3VdbeMemSetNull(@pVdbe->aMem[pOp->p3])
    ElseIf rc = SQLITE_OK Then
        If (leftValue.flags And (MEM_STR Or MEM_BLOB)) = 0 Then _
            rc = sqlite3VdbeMemStringify(@leftValue, pVdbe->db->enc, 0)
        If rc = SQLITE_OK AndAlso (leftValue.flags And MEM_ZERO) <> 0 Then _
            rc = sqlite3VdbeMemExpandBlob(@leftValue)
        If rc = SQLITE_OK AndAlso (rightValue.flags And (MEM_STR Or MEM_BLOB)) = 0 Then _
            rc = sqlite3VdbeMemStringify(@rightValue, pVdbe->db->enc, 0)
        If rc = SQLITE_OK AndAlso (rightValue.flags And MEM_ZERO) <> 0 Then _
            rc = sqlite3VdbeMemExpandBlob(@rightValue)
        If rc = SQLITE_OK Then
            If leftValue.n < 0 OrElse rightValue.n < 0 OrElse _
               leftValue.n > pVdbe->db->lengthLimit OrElse _
               rightValue.n > pVdbe->db->lengthLimit - leftValue.n Then
                rc = SQLITE_TOOBIG
            ElseIf (leftValue.n > 0 AndAlso leftValue.z = 0) OrElse _
                   (rightValue.n > 0 AndAlso rightValue.z = 0) Then
                rc = SQLITE_CORRUPT
            End If
        End If
        If rc = SQLITE_OK Then
            Dim combinedByteCount As SQLITE_C_INT = leftValue.n + rightValue.n
            Dim totalBytes As SQLITE_C_INT = combinedByteCount
            If pVdbe->db->enc <> SQLITE_UTF8 Then totalBytes = totalBytes And Not 1
            Dim allocationBytes As sqlite3_uint64 = CULngInt(combinedByteCount) + 2ULL
            Dim pCombined As UByte Ptr = CPtr(UByte Ptr, _
                sqlite3DbMallocRaw(pVdbe->db, allocationBytes))
            If pCombined = 0 Then
                rc = SQLITE_NOMEM
            Else
                If leftValue.n > 0 Then _
                    sqlite3VdbeExecMemcpy(pCombined, leftValue.z, CUInt(leftValue.n))
                If rightValue.n > 0 Then _
                    sqlite3VdbeExecMemcpy(pCombined + leftValue.n, _
                        rightValue.z, CUInt(rightValue.n))
                pCombined[totalBytes] = 0
                pCombined[totalBytes + 1] = 0
                Dim transientDestructor As sqlite3MemDestructor = _
                    CPtr(sqlite3MemDestructor, -1)
                rc = sqlite3VdbeMemSetStr( _
                    @pVdbe->aMem[pOp->p3], CPtr(Any Ptr, pCombined), _
                    totalBytes, pVdbe->db->enc, transientDestructor)
                sqlite3DbFree(pVdbe->db, pCombined)
            End If
        End If
    End If

    sqlite3VdbeMemRelease(@leftValue)
    sqlite3VdbeMemRelease(@rightValue)
    Return rc
End Function

Private Function sqlite3VdbeExecComparison( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pOp As SqliteVdbeOp Ptr, _
    ByRef shouldJump As SQLITE_C_INT, _
    ByRef comparisonResult As SQLITE_C_INT _
) As SQLITE_C_INT
    shouldJump = 0
    comparisonResult = 1
    If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
       pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem OrElse _
       pOp->p2 <= 0 OrElse pOp->p2 > pVdbe->nOp Then Return SQLITE_CORRUPT

    Dim pLeft As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p1]
    Dim pRight As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p3]
    Dim flagsLeft As UShort = pLeft->flags
    Dim flagsRight As UShort = pRight->flags
    Dim result As SQLITE_C_INT

    If ((flagsLeft Or flagsRight) And MEM_NULL) <> 0 Then
        If (pOp->p5 And SQLITE_NULLEQ) <> 0 Then
            If (flagsLeft And flagsRight And MEM_NULL) = MEM_NULL AndAlso _
               (flagsRight And MEM_CLEARED) = 0 Then
                result = 0
            ElseIf (flagsRight And MEM_NULL) <> 0 Then
                result = -1
            Else
                result = 1
            End If
        Else
            If (pOp->p5 And SQLITE_JUMPIFNULL) <> 0 Then shouldJump = 1
            comparisonResult = 1
            Return SQLITE_OK
        End If
    Else
        Dim affinity As UByte = pOp->p5 And SQLITE_AFF_MASK
        If affinity >= SQLITE_AFF_NUMERIC Then
            If (flagsLeft Or flagsRight) And MEM_STR Then
                If (flagsLeft And (MEM_INT Or MEM_INTREAL Or MEM_REAL Or MEM_STR)) = MEM_STR Then
                    sqlite3ApplyNumericAffinity(pLeft, 0)
                    flagsLeft = (pLeft->flags And Not MEM_TYPE_MASK) Or _
                                (flagsLeft And MEM_TYPE_MASK)
                End If
                If (flagsRight And (MEM_INT Or MEM_INTREAL Or MEM_REAL Or MEM_STR)) = MEM_STR Then
                    sqlite3ApplyNumericAffinity(pRight, 0)
                    flagsRight = (pRight->flags And Not MEM_TYPE_MASK) Or _
                                 (flagsRight And MEM_TYPE_MASK)
                End If
            End If
        ElseIf affinity = SQLITE_AFF_TEXT AndAlso _
               ((flagsLeft Or flagsRight) And MEM_STR) <> 0 Then
            If (flagsLeft And MEM_STR) <> 0 Then
                pLeft->flags = pLeft->flags And Not (MEM_INT Or MEM_REAL Or MEM_INTREAL)
            ElseIf (flagsLeft And (MEM_INT Or MEM_REAL Or MEM_INTREAL)) <> 0 Then
                sqlite3VdbeMemStringify(pLeft, pVdbe->db->enc, 1)
                flagsLeft = (pLeft->flags And Not MEM_TYPE_MASK) Or _
                            (flagsLeft And MEM_TYPE_MASK)
            End If
            If (flagsRight And MEM_STR) <> 0 Then
                pRight->flags = pRight->flags And Not (MEM_INT Or MEM_REAL Or MEM_INTREAL)
            ElseIf (flagsRight And (MEM_INT Or MEM_REAL Or MEM_INTREAL)) <> 0 Then
                sqlite3VdbeMemStringify(pRight, pVdbe->db->enc, 1)
                flagsRight = (pRight->flags And Not MEM_TYPE_MASK) Or _
                             (flagsRight And MEM_TYPE_MASK)
            End If
        End If

        Dim pCollation As Any Ptr = 0
        If pOp->p4type = P4_COLLSEQ Then pCollation = pOp->p4.p
        result = sqlite3MemCompare(pRight, pLeft, pCollation)
        pRight->flags = flagsRight
        pLeft->flags = flagsLeft
        If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    End If

    Select Case pOp->opcode
    Case OP_Ne
        shouldJump = IIf(result <> 0, 1, 0)
    Case OP_Eq
        shouldJump = IIf(result = 0, 1, 0)
    Case OP_Gt
        shouldJump = IIf(result > 0, 1, 0)
    Case OP_Le
        shouldJump = IIf(result <= 0, 1, 0)
    Case OP_Lt
        shouldJump = IIf(result < 0, 1, 0)
    Case OP_Ge
        shouldJump = IIf(result >= 0, 1, 0)
    Case Else
        Return SQLITE_CORRUPT
    End Select
    comparisonResult = result
    Return SQLITE_OK
End Function

Private Function sqlite3VdbeExecFinishSeek( _
    ByVal pCursor As SqliteVdbeCursor Ptr _
) As SQLITE_C_INT

    If pCursor = 0 OrElse pCursor->eCurType <> CURTYPE_BTREE OrElse _
       pCursor->uc.pCursor = 0 Then Return SQLITE_CORRUPT
    If pCursor->deferredMoveto = 0 Then Return SQLITE_OK
    If pCursor->isTable = 0 Then Return SQLITE_CORRUPT

    ' OP_DeferredSeek records rowids on table cursors only. Index cursors
    ' still pass through OP_Column and need no deferred move to finish.
    Dim seekResult As SQLITE_C_INT = 0
    Dim rc As SQLITE_C_INT = sqlite3BtreeTableMoveto( _
        pCursor->uc.pCursor, pCursor->movetoTarget, 0, @seekResult)
    If rc <> SQLITE_OK Then Return rc
    If seekResult <> 0 Then Return SQLITE_CORRUPT
#ifdef SQLITE_TEST
    sqlite3_search_count += 1
#endif
    pCursor->deferredMoveto = 0
    pCursor->nullRow = 0
    pCursor->cacheStatus = CACHE_STALE
    Return SQLITE_OK
End Function

Private Function sqlite3VdbeExecRecordColumn( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pRecord As Const UByte Ptr, _
    ByVal payloadSize As u32, _
    ByVal columnIndex As SQLITE_C_INT, _
    ByVal pOutput As SqliteVdbeMem Ptr _
) As SQLITE_C_INT

    If pVdbe = 0 OrElse pRecord = 0 OrElse pOutput = 0 OrElse _
       payloadSize = 0 OrElse payloadSize > SQLITE_MAX_ALLOCATION_SIZE OrElse _
       columnIndex < 0 Then Return SQLITE_CORRUPT

    Dim tempValue As SqliteVdbeMem
    sqlite3VdbeMemInit(@tempValue, pVdbe->db, MEM_NULL)
    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim fieldFound As SQLITE_C_INT = 0
    Dim headerOffset As Long = 0
    Dim headerSize As u32 = 0
    If sqlite3VdbeRecordReadVarint32( _
        pRecord, CLng(payloadSize), headerOffset, headerSize) = 0 OrElse _
       headerSize < CUInt(headerOffset) OrElse headerSize > payloadSize Then
        rc = SQLITE_CORRUPT
    Else
        Dim dataOffset As u32 = headerSize
        Dim currentField As SQLITE_C_INT = 0
        While headerOffset < headerSize
            Dim serialType As u32 = 0
            If sqlite3VdbeRecordReadVarint32( _
                pRecord, CLng(headerSize), headerOffset, serialType) = 0 Then
                rc = SQLITE_CORRUPT
                Exit While
            End If
            If serialType = 10 OrElse serialType = 11 Then
                rc = SQLITE_CORRUPT
                Exit While
            End If
            Dim fieldBytes As u32 = sqlite3VdbeSerialTypeLen(serialType)
            If dataOffset > payloadSize OrElse fieldBytes > payloadSize - dataOffset Then
                rc = SQLITE_CORRUPT
                Exit While
            End If
            If currentField = columnIndex Then
                sqlite3VdbeSerialGet(pRecord + dataOffset, serialType, @tempValue)
                rc = sqlite3VdbeMemCopy(pOutput, @tempValue)
                fieldFound = 1
                Exit While
            End If
            dataOffset += fieldBytes
            currentField += 1
        Wend
    End If
    If rc = SQLITE_OK AndAlso fieldFound = 0 Then sqlite3VdbeMemSetNull(pOutput)
    sqlite3VdbeMemRelease(@tempValue)
    Return rc
End Function

Private Function sqlite3VdbeExecColumnMetadata( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pCursor As SqliteVdbeCursor Ptr, _
    ByVal columnIndex As SQLITE_C_INT, _
    ByRef serialType As u32, _
    ByRef valueOffset As u32, _
    ByRef valueLength As u32, _
    ByRef localBytes As u32, _
    ByRef columnFound As SQLITE_C_INT _
) As SQLITE_C_INT
    serialType = 0
    valueOffset = 0
    valueLength = 0
    localBytes = 0
    columnFound = 0
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse _
       pCursor = 0 OrElse pCursor->uc.pCursor = 0 OrElse _
       pCursor->nField <= 0 OrElse columnIndex < 0 OrElse _
       columnIndex >= pCursor->nField OrElse pCursor->aOffset = 0 Then _
        Return SQLITE_CORRUPT

    Dim pBtreeCursor As BtCursor Ptr = pCursor->uc.pCursor
    Dim payloadSize As u32 = sqlite3BtreePayloadSize(pBtreeCursor)
    If payloadSize = 0 Then Return SQLITE_OK
    Dim pRow As Const UByte Ptr = CPtr(Const UByte Ptr, _
        sqlite3BtreePayloadFetch(pBtreeCursor, @localBytes))
    If localBytes > payloadSize OrElse (localBytes > 0 AndAlso pRow = 0) Then _
        Return SQLITE_CORRUPT
    pCursor->payloadSize = payloadSize
    pCursor->aRow = pRow
    pCursor->szRow = localBytes

    Dim prefixBytes As u32 = 9
    If payloadSize < prefixBytes Then prefixBytes = payloadSize
    Dim headerPrefix(0 To 8) As UByte
    Dim rc As SQLITE_C_INT = sqlite3BtreePayload( _
        pBtreeCursor, 0, prefixBytes, @headerPrefix(0))
    If rc <> SQLITE_OK Then Return rc

    Dim headerPosition As Long = 0
    Dim headerSize As u32 = 0
    If sqlite3VdbeRecordReadVarint32( _
        @headerPrefix(0), CLng(prefixBytes), headerPosition, headerSize) = 0 OrElse _
       headerSize < CUInt(headerPosition) OrElse headerSize > payloadSize Then _
        Return SQLITE_CORRUPT

    ' A record header has at most three bytes for each of 32768 columns,
    ' plus the three-byte header-size varint.
    If headerSize > 98307 Then Return SQLITE_CORRUPT

    Dim headerMemory As SqliteVdbeMem
    sqlite3VdbeMemInit(@headerMemory, pVdbe->db, MEM_NULL)
    Dim headerMemoryAllocated As SQLITE_C_INT = 0
    Dim pHeader As Const UByte Ptr = 0
    If headerSize <= localBytes AndAlso pRow <> 0 Then
        pHeader = pRow
    Else
        headerMemoryAllocated = 1
        rc = sqlite3VdbeMemFromBtreeZeroOffset( _
            pBtreeCursor, headerSize, @headerMemory)
        If rc <> SQLITE_OK Then
            sqlite3VdbeMemRelease(@headerMemory)
            Return rc
        End If
        pHeader = CPtr(Const UByte Ptr, headerMemory.z)
        If pHeader = 0 Then
            sqlite3VdbeMemRelease(@headerMemory)
            Return SQLITE_CORRUPT
        End If
    End If

    Dim pTypes As u32 Ptr = pCursor->aOffset - pCursor->nField
    pCursor->aOffset[0] = headerSize
    Dim dataOffset As sqlite3_uint64 = headerSize
    Dim parsedField As SQLITE_C_INT = 0
    While headerPosition < headerSize AndAlso parsedField <= columnIndex
        If parsedField >= pCursor->nField Then
            If headerMemoryAllocated <> 0 Then sqlite3VdbeMemRelease(@headerMemory)
            Return SQLITE_CORRUPT
        End If

        Dim fieldType As u32 = 0
        If sqlite3VdbeRecordReadVarint32( _
            pHeader, CLng(headerSize), headerPosition, fieldType) = 0 Then
            If headerMemoryAllocated <> 0 Then sqlite3VdbeMemRelease(@headerMemory)
            Return SQLITE_CORRUPT
        End If
        Dim fieldLength As u32 = sqlite3VdbeSerialTypeLen(fieldType)
        If dataOffset > payloadSize OrElse _
           CULngInt(fieldLength) > CULngInt(payloadSize) - dataOffset Then
            If headerMemoryAllocated <> 0 Then sqlite3VdbeMemRelease(@headerMemory)
            Return SQLITE_CORRUPT
        End If

        pTypes[parsedField] = fieldType
        pCursor->aOffset[parsedField + 1] = CUInt(dataOffset + fieldLength)
        If parsedField = columnIndex Then
            serialType = fieldType
            valueOffset = CUInt(dataOffset)
            valueLength = fieldLength
            columnFound = 1
        End If
        dataOffset += fieldLength
        parsedField += 1
    Wend

    If headerPosition > headerSize OrElse _
       (headerPosition = headerSize AndAlso dataOffset <> payloadSize) Then
        If headerMemoryAllocated <> 0 Then sqlite3VdbeMemRelease(@headerMemory)
        Return SQLITE_CORRUPT
    End If
    pCursor->nHdrParsed = CUShort(parsedField)
    pCursor->iHdrOffset = CUInt(headerPosition)
    If headerMemoryAllocated <> 0 Then sqlite3VdbeMemRelease(@headerMemory)
    Return SQLITE_OK
End Function

Private Function vdbeColumnFromOverflow CDecl Alias "vdbeColumnFromOverflow" ( _
    ByVal pCursor As SqliteVdbeCursor Ptr, _
    ByVal columnIndex As SQLITE_C_INT, _
    ByVal serialType As u32, _
    ByVal valueOffset As u32, _
    ByVal cacheStatus As u32, _
    ByVal colCacheCtr As u32, _
    ByVal pDest As SqliteVdbeMem Ptr _
) As SQLITE_C_INT
    If pCursor = 0 OrElse pDest = 0 OrElse pCursor->uc.pCursor = 0 OrElse _
       pCursor->eCurType <> CURTYPE_BTREE OrElse pDest->db = 0 Then _
        Return SQLITE_MISUSE

    Dim db As sqlite3 Ptr = pDest->db
    Dim textEncoding As u8 = pDest->enc
    Dim byteCount As u32 = sqlite3VdbeSerialTypeLen(serialType)
    If byteCount > CUInt(db->aLimit(SQLITE_LIMIT_LENGTH)) Then Return SQLITE_TOOBIG
    If byteCount > 4000 AndAlso pCursor->pKeyInfo = 0 Then
        Dim pCache As SqliteVdbeTextBlobCache Ptr = _
            CPtr(SqliteVdbeTextBlobCache Ptr, pCursor->pCache)
        If pCache = 0 Then
            pCache = CPtr(SqliteVdbeTextBlobCache Ptr, _
                sqlite3DbMallocZero(db, SizeOf(SqliteVdbeTextBlobCache)))
            If pCache = 0 Then Return SQLITE_NOMEM
            pCursor->pCache = pCache
            pCursor->cursorFlags Or= VDBE_CURSOR_COLUMN_CACHE
        End If

        Dim pBuffer As ZString Ptr = pCache->pCValue
        If pBuffer = 0 OrElse pCache->iCol <> columnIndex OrElse _
           pCache->cacheStatus <> cacheStatus OrElse _
           pCache->colCacheCtr <> colCacheCtr OrElse _
           pCache->iOffset <> sqlite3BtreeOffset(pCursor->uc.pCursor) Then
            If pBuffer <> 0 Then sqlite3RCStrUnref(pBuffer)
            pCache->pCValue = 0
            pBuffer = sqlite3RCStrNew(CULngInt(byteCount) + 3ULL)
            If pBuffer = 0 Then Return SQLITE_NOMEM
            pCache->pCValue = pBuffer
            Dim rc As SQLITE_C_INT = sqlite3BtreePayload( _
                pCursor->uc.pCursor, valueOffset, byteCount, pBuffer)
            If rc <> SQLITE_OK Then
                sqlite3RCStrUnref(pBuffer)
                pCache->pCValue = 0
                Return rc
            End If
            pBuffer[byteCount] = 0
            pBuffer[byteCount + 1] = 0
            pBuffer[byteCount + 2] = 0
            pCache->iCol = columnIndex
            pCache->cacheStatus = cacheStatus
            pCache->colCacheCtr = colCacheCtr
            pCache->iOffset = sqlite3BtreeOffset(pCursor->uc.pCursor)
        End If
        If (serialType And 1) <> 0 Then
            sqlite3RCStrRef(pBuffer)
            Dim rc As SQLITE_C_INT = sqlite3VdbeMemSetStr( _
                pDest, pBuffer, byteCount, textEncoding, @sqlite3RCStrUnref)
            If rc = SQLITE_OK Then pDest->flags Or= MEM_TERM
            Return rc
        End If

        sqlite3RCStrRef(pBuffer)
        Dim rc As SQLITE_C_INT = sqlite3VdbeMemSetStr( _
            pDest, pBuffer, byteCount, 0, @sqlite3RCStrUnref)
        If rc = SQLITE_OK Then pDest->enc = textEncoding
        Return rc
    End If

    Dim rc As SQLITE_C_INT = sqlite3VdbeMemFromBtree( _
        pCursor->uc.pCursor, valueOffset, byteCount, pDest)
    If rc <> SQLITE_OK Then Return rc
    sqlite3VdbeSerialGet(pDest->z, serialType, pDest)
    If (serialType And 1) <> 0 AndAlso textEncoding = SQLITE_UTF8 Then
        pDest->z[byteCount] = 0
        pDest->flags Or= MEM_TERM
    End If
    pDest->flags = pDest->flags And Not MEM_EPHEM
    Return SQLITE_OK
End Function

Private Function sqlite3VdbeExecColumn( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pCursor As SqliteVdbeCursor Ptr, _
    ByVal columnIndex As SQLITE_C_INT, _
    ByVal pOutput As SqliteVdbeMem Ptr, _
    ByVal columnFlags As UByte, _
    ByVal pDefault As SqliteVdbeMem Ptr _
) As SQLITE_C_INT
    Static unusedPayload(0 To 255) As UByte
    If pVdbe = 0 OrElse pCursor = 0 OrElse pOutput = 0 OrElse columnIndex < 0 Then _
        Return SQLITE_CORRUPT
    If pCursor->eCurType = CURTYPE_PSEUDO Then
        If pCursor->nullRow = 0 OrElse pCursor->seekResult <= 0 Then
            sqlite3VdbeMemSetNull(pOutput)
            Return SQLITE_OK
        End If
        If columnIndex >= pCursor->nField OrElse _
           pCursor->seekResult >= pVdbe->nMem Then
            sqlite3VdbeMemSetNull(pOutput)
            Return SQLITE_OK
        End If
        Dim pPseudoRecord As SqliteVdbeMem Ptr = _
            @pVdbe->aMem[pCursor->seekResult]
        If pPseudoRecord = pOutput OrElse _
           (pPseudoRecord->flags And MEM_BLOB) = 0 OrElse _
           pPseudoRecord->n <= 0 OrElse pPseudoRecord->z = 0 Then _
            Return SQLITE_CORRUPT
        If pPseudoRecord->n > pVdbe->db->lengthLimit Then Return SQLITE_TOOBIG
        Dim expandRc As SQLITE_C_INT = sqlite3VdbeMemExpandBlob(pPseudoRecord)
        If expandRc <> SQLITE_OK Then Return expandRc
        Return sqlite3VdbeExecRecordColumn( _
            pVdbe, pPseudoRecord->z, CUInt(pPseudoRecord->n), columnIndex, pOutput)
    End If
    If pCursor->eCurType <> CURTYPE_BTREE OrElse pCursor->uc.pCursor = 0 OrElse _
       pCursor->nField < 0 Then Return SQLITE_CORRUPT
    If pCursor->nullRow <> 0 OrElse columnIndex >= pCursor->nField Then
        sqlite3VdbeMemSetNull(pOutput)
        Return SQLITE_OK
    End If

    Dim pColumnCursor As SqliteVdbeCursor Ptr = pCursor
    Dim sourceColumnIndex As SQLITE_C_INT = columnIndex
    If pCursor->deferredMoveto <> 0 AndAlso pCursor->ub.aAltMap <> 0 Then
        ' OP_DeferredSeek supplies a map for table columns available in the
        ' current index record. Read those columns without moving the table cursor.
        Dim mappedColumn As u32 = pCursor->ub.aAltMap[columnIndex + 1]
        If mappedColumn > 0 Then
            If pCursor->pAltCursor = 0 Then Return SQLITE_CORRUPT
            pColumnCursor = pCursor->pAltCursor
            If pColumnCursor->eCurType <> CURTYPE_BTREE OrElse _
               pColumnCursor->isTable <> 0 OrElse _
               pColumnCursor->uc.pCursor = 0 OrElse _
               pColumnCursor->nField < 0 OrElse _
               CULng(mappedColumn) > CULng(pColumnCursor->nField) Then _
                Return SQLITE_CORRUPT
            sourceColumnIndex = CInt(mappedColumn - 1)
        End If
    End If

    If pColumnCursor->eCurType <> CURTYPE_BTREE OrElse _
       pColumnCursor->uc.pCursor = 0 Then Return SQLITE_CORRUPT
    Dim finishRc As SQLITE_C_INT = sqlite3VdbeExecFinishSeek(pColumnCursor)
    If finishRc <> SQLITE_OK Then Return finishRc
    If sourceColumnIndex >= pColumnCursor->nField Then
        sqlite3VdbeMemSetNull(pOutput)
        Return SQLITE_OK
    End If
    If pColumnCursor->nullRow = 0 Then
        Dim restoreResult As SQLITE_C_INT = 0
        Dim restoreRc As SQLITE_C_INT = sqlite3BtreeCursorRestore( _
            pColumnCursor->uc.pCursor, @restoreResult)
        If restoreRc <> SQLITE_OK Then Return restoreRc
    End If
    If pColumnCursor->nullRow <> 0 OrElse _
       sqlite3BtreeEof(pColumnCursor->uc.pCursor) <> 0 Then
        sqlite3VdbeMemSetNull(pOutput)
        Return SQLITE_OK
    End If
    pOutput->enc = pVdbe->db->enc

    If pColumnCursor->cacheStatus <> pVdbe->cacheCtr Then
        If (pColumnCursor->cursorFlags And VDBE_CURSOR_COLUMN_CACHE) <> 0 AndAlso _
           pColumnCursor->pCache <> 0 Then
            Dim pCache As SqliteVdbeTextBlobCache Ptr = _
                CPtr(SqliteVdbeTextBlobCache Ptr, pColumnCursor->pCache)
            pCache->colCacheCtr += 1
            If pCache->pCValue <> 0 Then
                sqlite3RCStrUnref(pCache->pCValue)
                pCache->pCValue = 0
            End If
        End If
        pColumnCursor->cacheStatus = pVdbe->cacheCtr
    End If

    Dim serialType As u32 = 0
    Dim valueOffset As u32 = 0
    Dim valueLength As u32 = 0
    Dim localBytes As u32 = 0
    Dim columnFound As SQLITE_C_INT = 0
    Dim metadataRc As SQLITE_C_INT = sqlite3VdbeExecColumnMetadata( _
        pVdbe, pColumnCursor, sourceColumnIndex, serialType, valueOffset, valueLength, _
        localBytes, columnFound)
    If metadataRc <> SQLITE_OK Then Return metadataRc
    If columnFound = 0 Then
        If pDefault <> 0 Then
            ' P4_MEM holds the ALTER TABLE default outside the stored row.
            ' The opcode borrows this value, so the destination is a shallow
            ' copy marked static rather than taking ownership of its buffer.
            sqlite3VdbeMemShallowCopy(pOutput, pDefault, MEM_STATIC)
        Else
            sqlite3VdbeMemSetNull(pOutput)
        End If
        Return SQLITE_OK
    End If
    If (pOutput->flags And MEM_DYN) <> 0 Then sqlite3VdbeMemSetNull(pOutput)

    If serialType = 10 Then
        pOutput->flags = MEM_NULL Or MEM_ZERO
        pOutput->n = 0
        pOutput->u.nZero = 0
        Return SQLITE_OK
    End If
    Dim metadataMode As UByte = columnFlags And OPFLAG_BYTELENARG
    If metadataMode <> 0 AndAlso _
       (metadataMode = OPFLAG_TYPEOFARG OrElse _
        (serialType >= 12 AndAlso _
         ((serialType And 1) = 0 OrElse metadataMode = OPFLAG_BYTELENARG))) Then
        ' The type and serial header carry all information needed by typeof(),
        ' blob length(), and octet_length(). Keep a bounded dummy payload so
        ' these VDBE cells cannot trigger reads from overflow pages.
        sqlite3VdbeSerialGet(@unusedPayload(0), serialType, pOutput)
        Return SQLITE_OK
    End If
    If valueLength = 0 Then
        Dim unusedByte As UByte = 0
        Dim localValue As SqliteVdbeMem
        sqlite3VdbeMemInit(@localValue, pVdbe->db, MEM_NULL)
        localValue.enc = pOutput->enc
        sqlite3VdbeSerialGet(@unusedByte, serialType, @localValue)
        Dim copyRc As SQLITE_C_INT = sqlite3VdbeMemCopy(pOutput, @localValue)
        sqlite3VdbeMemRelease(@localValue)
        Return copyRc
    End If
    If valueLength > CUInt(pVdbe->db->aLimit(SQLITE_LIMIT_LENGTH)) Then _
        Return SQLITE_TOOBIG

    Dim valueEnd As sqlite3_uint64 = _
        CULngInt(valueOffset) + CULngInt(valueLength)
    Dim colCacheCtr As u32 = 0
    If pColumnCursor->pCache <> 0 Then
        colCacheCtr = CPtr(SqliteVdbeTextBlobCache Ptr, pColumnCursor->pCache)->colCacheCtr
    End If
    If valueEnd <= localBytes Then
        Dim pLocalValue As Const UByte Ptr = _
            CPtr(Const UByte Ptr, pColumnCursor->aRow) + valueOffset
        Dim localValue As SqliteVdbeMem
        sqlite3VdbeMemInit(@localValue, pVdbe->db, MEM_NULL)
        localValue.enc = pOutput->enc
        sqlite3VdbeSerialGet(pLocalValue, serialType, @localValue)
        Dim copyRc As SQLITE_C_INT = sqlite3VdbeMemCopy(pOutput, @localValue)
        sqlite3VdbeMemRelease(@localValue)
        Return copyRc
    End If

    Return vdbeColumnFromOverflow( _
        pColumnCursor, sourceColumnIndex, serialType, valueOffset, _
        pVdbe->cacheCtr, colCacheCtr, pOutput)
End Function

Private Function sqlite3VdbeExecIndexCursorCompare( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pCursor As SqliteVdbeCursor Ptr, _
    ByVal pOp As SqliteVdbeOp Ptr, _
    ByRef comparison As SQLITE_C_INT _
) As SQLITE_C_INT

    If pVdbe = 0 OrElse pCursor = 0 OrElse pOp = 0 OrElse _
       pCursor->eCurType <> CURTYPE_BTREE OrElse pCursor->isTable <> 0 OrElse _
       pCursor->uc.pCursor = 0 OrElse pCursor->pKeyInfo = 0 OrElse _
       pOp->p3 <= 0 OrElse pOp->p4type <> P4_INT32 OrElse pOp->p4.i <= 0 OrElse _
       pOp->p4.i > pVdbe->nMem - pOp->p3 Then Return SQLITE_CORRUPT

    Dim restoreResult As SQLITE_C_INT = 0
    Dim restoreRc As SQLITE_C_INT = sqlite3BtreeCursorRestore( _
        pCursor->uc.pCursor, @restoreResult)
    If restoreRc <> SQLITE_OK Then Return restoreRc
    If sqlite3BtreeEof(pCursor->uc.pCursor) <> 0 Then Return SQLITE_CORRUPT

    Dim payloadSize As u32 = sqlite3BtreePayloadSize(pCursor->uc.pCursor)
    If payloadSize = 0 OrElse payloadSize > SQLITE_MAX_ALLOCATION_SIZE Then _
        Return SQLITE_CORRUPT
    If payloadSize > CULng(pVdbe->db->lengthLimit) Then Return SQLITE_TOOBIG
    Dim pRecordBytes As UByte Ptr = CPtr(UByte Ptr, _
        sqlite3DbMallocRaw(pVdbe->db, CULngInt(payloadSize)))
    If pRecordBytes = 0 Then Return SQLITE_NOMEM

    Dim rc As SQLITE_C_INT = sqlite3BtreePayloadChecked( _
        pCursor->uc.pCursor, 0, payloadSize, pRecordBytes)
    If rc = SQLITE_OK Then
        Dim unpacked As sqlite3VdbeUnpackedRecord
        unpacked.pKeyInfo = pCursor->pKeyInfo
        unpacked.aMem = @pVdbe->aMem[pOp->p3]
        unpacked.u.i = 0
        unpacked.n = 0
        unpacked.nField = CUShort(pOp->p4.i)
        If pOp->opcode = OP_IdxLE OrElse pOp->opcode = OP_IdxGT Then
            unpacked.default_rc = -1
        Else
            unpacked.default_rc = 0
        End If
        unpacked.errCode = SQLITE_OK
        unpacked.r1 = 0
        unpacked.r2 = 0
        unpacked.eqSeen = 0
        comparison = sqlite3VdbeRecordCompareWithSkip( _
            CLng(payloadSize), pRecordBytes, @unpacked, 0)
        If unpacked.errCode <> SQLITE_OK Then rc = unpacked.errCode
    End If
    sqlite3DbFree(pVdbe->db, pRecordBytes)
    Return rc
End Function

Private Function sqlite3VdbeAggregateArgCountValid( _
    ByVal pFunction As SqliteFuncDef Ptr, _
    ByVal argumentCount As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFunction = 0 OrElse argumentCount < 0 Then Return 0
    Select Case pFunction->nArg
    Case -1
        Return -1
    Case -3
        Return CInt(argumentCount >= 1)
    Case -4
        Return CInt(argumentCount >= 2)
    Case Else
        Return CInt(pFunction->nArg = argumentCount)
    End Select
End Function

Private Function sqlite3VdbeExecTypeCheck( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pOp As SqliteVdbeOp Ptr _
) As SQLITE_C_INT
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse pOp = 0 OrElse _
       pVdbe->aMem = 0 OrElse pOp->p4type <> P4_TABLE OrElse _
       pOp->p4.p = 0 Then Return SQLITE_CORRUPT

    Dim pTable As SqliteTable Ptr = CPtr(SqliteTable Ptr, pOp->p4.p)
    If pTable->aCol = 0 OrElse (pTable->tabFlags And TF_Strict) = 0 OrElse _
       pTable->nCol < 0 OrElse pOp->p3 < 0 OrElse _
       pOp->p3 >= pTable->nCol + 2 OrElse pOp->p1 <= 0 OrElse _
       pOp->p1 >= pVdbe->nMem OrElse pOp->p2 <= 0 OrElse _
       pOp->p2 > pVdbe->nMem - pOp->p1 Then Return SQLITE_CORRUPT

    Dim firstColumn As SQLITE_C_INT = 0
    Dim endColumn As SQLITE_C_INT = pTable->nCol
    If pOp->p3 < 2 Then
        If pOp->p3 = 0 AndAlso pTable->nNVCol <> pOp->p2 Then _
            Return SQLITE_CORRUPT
    Else
        firstColumn = pOp->p3 - 2
        endColumn = firstColumn + 1
        If firstColumn >= pTable->nCol OrElse pOp->p2 <> 1 OrElse _
           (pTable->aCol[firstColumn].colFlags And COLFLAG_VIRTUAL) = 0 Then _
            Return SQLITE_CORRUPT
    End If

    Dim registerIndex As SQLITE_C_INT = pOp->p1
    For columnIndex As SQLITE_C_INT = firstColumn To endColumn - 1
        Dim pColumn As SqliteColumn Ptr = @pTable->aCol[columnIndex]
        If (pColumn->colFlags And COLFLAG_GENERATED) <> 0 AndAlso pOp->p3 < 2 Then
            If (pColumn->colFlags And COLFLAG_VIRTUAL) <> 0 Then Continue For
            If pOp->p3 <> 0 Then
                registerIndex += 1
                Continue For
            End If
        End If
        If registerIndex >= pOp->p1 + pOp->p2 Then Return SQLITE_CORRUPT

        Dim eColumnType As UByte = vdbeExecColumnType(pColumn)
        If eColumnType < COLTYPE_ANY OrElse eColumnType > COLTYPE_TEXT Then _
            Return SQLITE_CORRUPT
        Dim pValue As SqliteVdbeMem Ptr = @pVdbe->aMem[registerIndex]
        sqlite3ValueApplyAffinity(pValue, CByte(pColumn->affinity), pVdbe->db->enc)
        If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM

        If (pValue->flags And MEM_NULL) = 0 Then
            Dim typeMismatch As SQLITE_C_INT = 0
            Select Case eColumnType
            Case COLTYPE_BLOB
                typeMismatch = CInt((pValue->flags And MEM_BLOB) = 0)
            Case COLTYPE_INT, COLTYPE_INTEGER
                typeMismatch = CInt((pValue->flags And MEM_INT) = 0)
            Case COLTYPE_TEXT
                typeMismatch = CInt((pValue->flags And MEM_STR) = 0)
            Case COLTYPE_REAL
                If (pValue->flags And MEM_INT) <> 0 Then
                    Dim integerValue As sqlite3_int64 = pValue->u.i
                    If integerValue <= 140737488355327LL AndAlso _
                       integerValue >= -140737488355328LL Then
                        pValue->flags = (pValue->flags Or MEM_INTREAL) And Not MEM_INT
                    Else
                        pValue->u.r = CDbl(integerValue)
                        pValue->flags = (pValue->flags Or MEM_REAL) And Not MEM_INT
                    End If
                ElseIf (pValue->flags And (MEM_REAL Or MEM_INTREAL)) = 0 Then
                    typeMismatch = 1
                End If
            Case COLTYPE_ANY
                ' ANY is the strict-table escape hatch and accepts every value.
            End Select
            If typeMismatch <> 0 Then
                Dim standardTypes As Const ZString Ptr Ptr = sqlite3StdTypeTable()
                If standardTypes = 0 OrElse pTable->zName = 0 OrElse _
                   pColumn->zCnName = 0 Then Return SQLITE_CORRUPT
                sqlite3VdbeError( _
                    pVdbe, StrPtr(!"cannot store %s value in %s column %s.%s"), _
                    vdbeExecMemTypeName(pValue), standardTypes[eColumnType - 1], _
                    pTable->zName, pColumn->zCnName)
                Return SQLITE_CONSTRAINT_DATATYPE
            End If
        End If
        registerIndex += 1
    Next
    If registerIndex <> pOp->p1 + pOp->p2 Then Return SQLITE_CORRUPT
    Return SQLITE_OK
End Function

Private Function vdbeExecStartProgram( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pOp As SqliteVdbeOp Ptr, _
    ByVal programCounter As SQLITE_C_INT, _
    ByRef nextCounter As SQLITE_C_INT _
) As SQLITE_C_INT
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse pOp = 0 OrElse _
       pVdbe->aMem = 0 OrElse pVdbe->apCsr = 0 OrElse _
       pOp->p4type <> P4_SUBPROGRAM OrElse pOp->p4.p = 0 OrElse _
       pVdbe->nMem <= 0 OrElse _
       CLngInt(pOp->p1) < -CLngInt(pVdbe->nMem) OrElse _
       pOp->p1 > pVdbe->nMem OrElse _
       pOp->p2 < 0 OrElse pOp->p2 > pVdbe->nOp OrElse _
       pOp->p3 <= 0 OrElse pOp->p3 > pVdbe->nMem - pVdbe->nCursor OrElse _
       pOp->p5 > 1 Then Return SQLITE_CORRUPT

    Dim pProgram As SqliteVdbeSubProgram Ptr = _
        CPtr(SqliteVdbeSubProgram Ptr, pOp->p4.p)
    If pProgram->aOp = 0 OrElse pProgram->nOp <= 0 OrElse _
       pProgram->nOp > SQLITE_MAX_VDBE_OP OrElse _
       pProgram->nMem < 0 OrElse pProgram->nCsr < 0 OrElse _
       pProgram->nMem > &H7FFFFFFF - pProgram->nCsr Then _
        Return SQLITE_CORRUPT

    If pOp->p5 <> 0 Then
        Dim pAncestor As SqliteVdbeFrame Ptr = _
            CPtr(SqliteVdbeFrame Ptr, pVdbe->pFrame)
        While pAncestor <> 0
            If pAncestor->token = pProgram->token Then Return SQLITE_OK
            pAncestor = pAncestor->pParent
        Wend
    End If

    If pVdbe->nFrame < 0 OrElse _
       pVdbe->nFrame >= pVdbe->db->aLimit(SQLITE_LIMIT_TRIGGER_DEPTH) Then
        sqlite3VdbeError(pVdbe, StrPtr(!"triggers nested too deep"))
        Return SQLITE_ERROR
    End If

    Dim childMemCount As SQLITE_C_INT = pProgram->nMem + pProgram->nCsr
    If pProgram->nCsr = 0 Then childMemCount += 1
    If childMemCount <= 0 Then Return SQLITE_CORRUPT

    Dim frameMemOffset As sqlite3_uint64 = _
        (CULngInt(SizeOf(SqliteVdbeFrame)) + 7ULL) And Not 7ULL
    Dim maximumAllocation As sqlite3_uint64 = _
        CULngInt(SQLITE_MAX_ALLOCATION_SIZE)
    If CULngInt(childMemCount) > _
       (maximumAllocation - frameMemOffset) \ SizeOf(SqliteVdbeMem) Then _
        Return SQLITE_TOOBIG
    Dim frameBytes As sqlite3_uint64 = frameMemOffset + _
        CULngInt(childMemCount) * SizeOf(SqliteVdbeMem)
    If CULngInt(pProgram->nCsr) > _
       (maximumAllocation - frameBytes) \ SizeOf(Any Ptr) Then _
        Return SQLITE_TOOBIG
    frameBytes += CULngInt(pProgram->nCsr) * SizeOf(Any Ptr)
    Dim onceByteCount As sqlite3_uint64 = _
        (CULngInt(pProgram->nOp) + 7) \ 8
    If onceByteCount > maximumAllocation - frameBytes OrElse _
       frameBytes + onceByteCount > &H7FFFFFFF Then Return SQLITE_TOOBIG
    frameBytes += onceByteCount

    Dim pRuntime As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p3]
    Dim frameDestructor As sqlite3MemDestructor = _
        ProcPtr(sqlite3VdbeFrameMemDel)
    Dim pFrame As SqliteVdbeFrame Ptr = 0
    If (pRuntime->flags And MEM_BLOB) = 0 Then
        pFrame = CPtr(SqliteVdbeFrame Ptr, _
            sqlite3DbMallocZero(pVdbe->db, frameBytes))
        If pFrame = 0 Then Return SQLITE_NOMEM

        sqlite3VdbeMemRelease(pRuntime)
        pRuntime->flags = MEM_BLOB Or MEM_DYN
        pRuntime->z = CPtr(UByte Ptr, pFrame)
        pRuntime->n = CInt(frameBytes)
        pRuntime->zMalloc = 0
        pRuntime->szMalloc = 0
        pRuntime->xDel = frameDestructor
        pRuntime->u.i = 0
        pRuntime->eSubtype = 0

        pFrame->v = pVdbe
        pFrame->nChildMem = childMemCount
        pFrame->nChildCsr = pProgram->nCsr
        pFrame->token = pProgram->token
#ifdef SQLITE_DEBUG
        pFrame->iFrameMagic = &H879FB71E
#endif
        Dim pChildMem As SqliteVdbeMem Ptr = CPtr( _
            SqliteVdbeMem Ptr, CPtr(UByte Ptr, pFrame) + frameMemOffset)
        For iMem As SQLITE_C_INT = 0 To childMemCount - 1
            pChildMem[iMem].db = pVdbe->db
            pChildMem[iMem].flags = MEM_UNDEFINED
        Next
    Else
        If (pRuntime->flags And (MEM_BLOB Or MEM_DYN)) <> _
              (MEM_BLOB Or MEM_DYN) OrElse pRuntime->z = 0 OrElse _
           pRuntime->xDel <> frameDestructor OrElse _
           pRuntime->n < CInt(frameBytes) Then Return SQLITE_CORRUPT
        pFrame = CPtr(SqliteVdbeFrame Ptr, pRuntime->z)
        If pFrame->nChildMem <> childMemCount OrElse _
           pFrame->nChildCsr <> pProgram->nCsr OrElse _
           pFrame->token <> pProgram->token Then Return SQLITE_CORRUPT
#ifdef SQLITE_DEBUG
        If pFrame->iFrameMagic <> &H879FB71E Then Return SQLITE_CORRUPT
#endif
    End If

    pVdbe->nFrame += 1
    pFrame->pParent = CPtr(SqliteVdbeFrame Ptr, pVdbe->pFrame)
    pFrame->lastRowid = pVdbe->db->lastRowid
    pFrame->nChange = pVdbe->nChange
    pFrame->nDbChange = pVdbe->db->nChange
    pFrame->pAuxData = pVdbe->pAuxData
    pVdbe->pAuxData = 0
    pVdbe->nChange = 0
    pFrame->pc = programCounter
    pFrame->aMem = pVdbe->aMem
    pFrame->nMem = pVdbe->nMem
    pFrame->apCsr = pVdbe->apCsr
    pFrame->nCursor = pVdbe->nCursor
    pFrame->aOp = pVdbe->aOp
    pFrame->nOp = pVdbe->nOp

    Dim pChildMemArray As SqliteVdbeMem Ptr = CPtr( _
        SqliteVdbeMem Ptr, CPtr(UByte Ptr, pFrame) + frameMemOffset)
    pVdbe->aMem = pChildMemArray
    pVdbe->nMem = childMemCount
    pVdbe->nCursor = pProgram->nCsr
    pVdbe->apCsr = CPtr(Any Ptr Ptr, @pChildMemArray[childMemCount])
    pFrame->aOnce = CPtr( _
        UByte Ptr, pVdbe->apCsr + pProgram->nCsr)
    For iByte As sqlite3_uint64 = 0 To onceByteCount - 1
        pFrame->aOnce[iByte] = 0
    Next
    pVdbe->aOp = pProgram->aOp
    pVdbe->nOp = pProgram->nOp
    pVdbe->pFrame = pFrame

#ifdef SQLITE_DEBUG
    For iMem As SQLITE_C_INT = 0 To childMemCount - 1
        pChildMemArray[iMem].pScopyFrom = 0
        pChildMemArray[iMem].flags = MEM_UNDEFINED
    Next
#endif

    nextCounter = 0
    Return SQLITE_OK
End Function

Function sqlite3VdbeExec CDecl Alias "sqlite3VdbeExec" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT Export
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse pVdbe->aOp = 0 OrElse _
       pVdbe->eVdbeState <> VDBE_RUN_STATE Then Return SQLITE_MISUSE

    ' Keep shared B-tree cursor state stable across the complete VM slice.
    sqlite3VdbeEnter(pVdbe)
#if defined(SQLITE_ENABLE_IOTRACE) AndAlso Not defined(SQLITE_OMIT_TRACE)
    sqlite3VdbeIOTraceSql(pVdbe)
#endif

    Dim programCounter As SQLITE_C_INT = pVdbe->pc
    If programCounter < 0 Then programCounter = 0
    Dim aggregateArguments(0 To SQLITE_MAX_FUNCTION_ARG - 1) As SqliteVdbeMem Ptr
    Dim compareResult As SQLITE_C_INT = 0
    Dim compareReady As SQLITE_C_INT = 0
    While programCounter < pVdbe->nOp
        Dim pOp As SqliteVdbeOp Ptr = @pVdbe->aOp[programCounter]
        Dim nextCounter As SQLITE_C_INT = programCounter + 1
        pVdbe->aCounter(SQLITE_STMTSTATUS_VM_STEP) += 1
        Select Case pOp->opcode
        Case OP_Noop, OP_Explain, OP_SeekScan
            ' The remaining work after these plan hints preserves query results.

        Case OP_CollSeq
            If pOp->p4type <> P4_COLLSEQ Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pOp->p1 <> 0 Then
                If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                sqlite3VdbeMemSetInt64(@pVdbe->aMem[pOp->p1], 0)
            End If

        Case OP_SeekHit
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 < 0 OrElse pOp->p3 < pOp->p2 OrElse _
               pOp->p3 > 65535 OrElse pVdbe->apCsr = 0 OrElse _
               pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pSeekHitCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pSeekHitCursor->seekHit < pOp->p2 Then
                pSeekHitCursor->seekHit = CUShort(pOp->p2)
            ElseIf pSeekHitCursor->seekHit > pOp->p3 Then
                pSeekHitCursor->seekHit = CUShort(pOp->p3)
            End If

        Case OP_ReadCookie
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->db->nDb OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pOp->p3 < 0 OrElse pOp->p3 >= SQLITE3_VDBE_META_COUNT OrElse _
               (pVdbe->vdbeFlags And VDBE_BISREADER_MASK) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pDatabase As SqliteDbSlot Ptr = @pVdbe->db->aDb(pOp->p1)
            If pDatabase->pBt = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim metadataValue As u32 = 0
            sqlite3BtreeGetMeta( _
                CPtr(Btree Ptr, pDatabase->pBt), pOp->p3, @metadataValue)
            Dim signedMetadataValue As SQLITE_C_INT
            sqlite3VdbeExecMemcpy( _
                @signedMetadataValue, @metadataValue, SizeOf(signedMetadataValue))
            sqlite3VdbeMemSetInt64( _
                @pVdbe->aMem[pOp->p2], signedMetadataValue)

        Case OP_SetCookie
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->db->nDb OrElse _
               pOp->p2 < 0 OrElse pOp->p2 >= SQLITE3_VDBE_META_COUNT OrElse _
               (pOp->p4type <> P4_NOTUSED AndAlso pOp->p4type <> P4_INT32) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pVdbe->vdbeFlags And VDBE_READONLY_MASK) <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_READONLY)
            Dim pDatabase As SqliteDbSlot Ptr = @pVdbe->db->aDb(pOp->p1)
            If pDatabase->pBt = 0 OrElse pDatabase->pSchema = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
#ifdef SQLITE_DEBUG
            sqlite3VdbeIncrWriteCounter(pVdbe, 0)
#endif
            Dim metadataValue As u32 = CUInt(CULngInt(pOp->p3) And &HFFFFFFFFULL)
            Dim metadataCode As SQLITE_C_INT = sqlite3BtreeUpdateMeta( _
                CPtr(Btree Ptr, pDatabase->pBt), pOp->p2, metadataValue)
            If pOp->p2 = SQLITE3_VDBE_SCHEMA_VERSION_META Then
                ' The P5 adjustment makes PRAGMA schema_version=N expire old plans.
                Dim schemaCookieBits As u32 = _
                    metadataValue - CUInt(pOp->p5)
                sqlite3VdbeExecMemcpy( _
                    @pDatabase->pSchema->schema_cookie, _
                    @schemaCookieBits, SizeOf(schemaCookieBits))
                pVdbe->db->mDbFlags Or= SQLITE3_VDBE_DBFLAG_SCHEMA_CHANGE
#ifndef SQLITE_OMIT_FOREIGN_KEY
                sqlite3FkClearTriggerCache(pVdbe->db, pOp->p1)
#endif
            ElseIf pOp->p2 = SQLITE3_VDBE_FILE_FORMAT_META Then
                pDatabase->pSchema->file_format = CByte(pOp->p3)
            End If
            If pOp->p1 = 1 Then
                sqlite3ExpirePreparedStatements(pVdbe->db, 0)
                pVdbe->vdbeFlags = _
                    pVdbe->vdbeFlags And Not VDBE_EXPIRED_MASK
            End If
            If metadataCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, metadataCode)

#ifndef SQLITE_OMIT_ANALYZE
        Case OP_LoadAnalysis
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->db->nDb Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim analysisCode As SQLITE_C_INT = _
                sqlite3AnalysisLoad(pVdbe->db, pOp->p1)
            If analysisCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, analysisCode)
#endif

#ifndef SQLITE_OMIT_INTEGRITY_CHECK
        Case OP_IntegrityCk
            If pOp->p4type <> P4_INTARRAY OrElse pOp->p4.p = 0 OrElse _
               pOp->p1 <= 0 OrElse pOp->p1 + 1 >= pVdbe->nMem OrElse _
               pOp->p2 <= 0 OrElse pOp->p3 <= 0 OrElse _
               pOp->p3 > pVdbe->nMem - pOp->p2 OrElse _
               pOp->p5 >= pVdbe->db->nDb OrElse _
               pVdbe->db->aDb(pOp->p5).pBt = 0 OrElse _
               vdbeExecBtreeMaskTest(pVdbe, pOp->p5) = 0 OrElse _
               (pVdbe->vdbeFlags And VDBE_BISREADER_MASK) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)

            Dim pRemainingErrors As SqliteVdbeMem Ptr = _
                @pVdbe->aMem[pOp->p1]
            If (pRemainingErrors->flags And MEM_INT) = 0 OrElse _
               pRemainingErrors->u.i < 0 OrElse _
               pRemainingErrors->u.i >= &H7FFFFFFF Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pRootPages As SQLITE_C_UINT Ptr = _
                CPtr(SQLITE_C_UINT Ptr, pOp->p4.p)
            If pRootPages[0] <> CUInt(pOp->p2) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)

            Dim maximumErrors As SQLITE_C_INT = CInt(pRemainingErrors->u.i + 1)
            Dim errorCount As SQLITE_C_INT = 0
            Dim zIntegrityError As ZString Ptr = 0
            Dim integrityCode As SQLITE_C_INT = sqlite3BtreeIntegrityCheck( _
                pVdbe->db, CPtr(Btree Ptr, pVdbe->db->aDb(pOp->p5).pBt), _
                pRootPages + 1, @pVdbe->aMem[pOp->p3], pOp->p2, _
                maximumErrors, @errorCount, @zIntegrityError)
            sqlite3VdbeMemSetNull(@pVdbe->aMem[pOp->p1 + 1])
            If integrityCode <> SQLITE_OK Then
                sqlite3DbFree(pVdbe->db, zIntegrityError)
                Return sqlite3VdbeExecError(pVdbe, integrityCode)
            End If
            If errorCount < 0 OrElse errorCount > maximumErrors Then
                sqlite3DbFree(pVdbe->db, zIntegrityError)
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            End If
            If errorCount = 0 Then
                If zIntegrityError <> 0 Then
                    sqlite3DbFree(pVdbe->db, zIntegrityError)
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                End If
            Else
                If zIntegrityError = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                pRemainingErrors->u.i -= errorCount - 1
                Dim transientDestructor As sqlite3MemDestructor = _
                    CPtr(sqlite3MemDestructor, -1)
                Dim messageCode As SQLITE_C_INT = sqlite3VdbeMemSetText( _
                    @pVdbe->aMem[pOp->p1 + 1], zIntegrityError, -1, _
                    transientDestructor)
                sqlite3DbFree(pVdbe->db, zIntegrityError)
                If messageCode <> SQLITE_OK Then _
                    Return sqlite3VdbeExecError(pVdbe, messageCode)
            End If
#endif

        Case OP_Destroy
            If pOp->p1 <= 1 OrElse pOp->p2 <= 0 OrElse _
               pOp->p2 >= pVdbe->nMem OrElse pOp->p3 < 0 OrElse _
               pOp->p3 >= pVdbe->db->nDb OrElse _
               pVdbe->db->aDb(pOp->p3).pBt = 0 OrElse _
               pVdbe->db->aDb(pOp->p3).pSchema = 0 OrElse _
               vdbeExecBtreeMaskTest(pVdbe, pOp->p3) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pVdbe->vdbeFlags And VDBE_READONLY_MASK) <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_READONLY)
            If pVdbe->resetSchemaOnFault <> 0 AndAlso _
               pVdbe->resetSchemaOnFault <> pOp->p3 + 1 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)

#ifdef SQLITE_DEBUG
            sqlite3VdbeIncrWriteCounter(pVdbe, 0)
#endif
            sqlite3VdbeMemSetNull(@pVdbe->aMem[pOp->p2])
            If pVdbe->db->nVdbeRead > pVdbe->db->nVDestroy + 1 Then
                pVdbe->errorAction = OE_ABORT
                Return sqlite3VdbeExecError(pVdbe, SQLITE_LOCKED)
            End If

            Dim movedRootPage As SQLITE_C_INT = 0
            Dim destroyCode As SQLITE_C_INT = sqlite3BtreeDropTable( _
                CPtr(Btree Ptr, pVdbe->db->aDb(pOp->p3).pBt), _
                pOp->p1, @movedRootPage)
            sqlite3VdbeMemSetInt64( _
                @pVdbe->aMem[pOp->p2], movedRootPage)
            If destroyCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, destroyCode)

#ifndef SQLITE_OMIT_AUTOVACUUM
            If movedRootPage <> 0 Then
                sqlite3RootPageMoved( _
                    pVdbe->db, pOp->p3, CUInt(movedRootPage), CUInt(pOp->p1))
                pVdbe->resetSchemaOnFault = CByte(pOp->p3 + 1)
            End If
#endif

#ifndef SQLITE_OMIT_WAL
        Case OP_Checkpoint
            If pOp->p1 < 0 OrElse _
               (pOp->p1 >= pVdbe->db->nDb AndAlso pOp->p1 <> SQLITE_MAX_DB) OrElse _
               pOp->p2 < SQLITE_CHECKPOINT_NOOP OrElse _
               pOp->p2 > SQLITE_CHECKPOINT_TRUNCATE OrElse _
               pOp->p3 <= 0 OrElse pOp->p3 > pVdbe->nMem - 3 OrElse _
               pOp->p4type <> P4_NOTUSED OrElse pOp->p5 <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pVdbe->vdbeFlags And VDBE_READONLY_MASK) <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_READONLY)
            Dim checkpointResults(0 To 2) As SQLITE_C_INT
            checkpointResults(0) = 0
            checkpointResults(1) = -1
            checkpointResults(2) = -1
            Dim checkpointCode As SQLITE_C_INT = sqlite3Checkpoint( _
                pVdbe->db, pOp->p1, pOp->p2, _
                @checkpointResults(1), @checkpointResults(2))
            If checkpointCode = SQLITE_BUSY Then
                checkpointResults(0) = 1
                checkpointCode = SQLITE_OK
            End If
            If checkpointCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, checkpointCode)
            For iCheckpointResult As SQLITE_C_INT = 0 To 2
                sqlite3VdbeMemSetInt64( _
                    @pVdbe->aMem[pOp->p3 + iCheckpointResult], _
                    checkpointResults(iCheckpointResult))
            Next
#endif

#ifndef SQLITE_OMIT_PRAGMA
        Case OP_JournalMode
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->db->nDb OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               (pOp->p3 <> PAGER_JOURNALMODE_QUERY AndAlso _
                (pOp->p3 < PAGER_JOURNALMODE_DELETE OrElse _
                 pOp->p3 > PAGER_JOURNALMODE_WAL)) OrElse _
               pOp->p4type <> P4_NOTUSED OrElse pOp->p5 <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pVdbe->vdbeFlags And VDBE_READONLY_MASK) <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_READONLY)
            If pVdbe->db->aDb(pOp->p1).pBt = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pJournalBtree As Btree Ptr = _
                CPtr(Btree Ptr, pVdbe->db->aDb(pOp->p1).pBt)
            Dim pJournalPager As Pager Ptr = sqlite3BtreePager(pJournalBtree)
            If pJournalPager = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim newJournalMode As SQLITE_C_INT = pOp->p3
            Dim oldJournalMode As SQLITE_C_INT = _
                sqlite3PagerGetJournalMode(pJournalPager)
            If oldJournalMode < PAGER_JOURNALMODE_DELETE OrElse _
               oldJournalMode > PAGER_JOURNALMODE_WAL Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If newJournalMode = PAGER_JOURNALMODE_QUERY Then _
                newJournalMode = oldJournalMode
            If sqlite3PagerOkToChangeJournalMode(pJournalPager) = 0 Then _
                newJournalMode = oldJournalMode

#ifndef SQLITE_OMIT_WAL
            Dim zJournalFilename As Const ZString Ptr = _
                sqlite3PagerFilename(pJournalPager, 1)
            If newJournalMode = PAGER_JOURNALMODE_WAL AndAlso _
               (zJournalFilename = 0 OrElse zJournalFilename[0] = 0 OrElse _
                sqlite3PagerWalSupported(pJournalPager) = 0) Then _
                newJournalMode = oldJournalMode
            Dim journalModeCode As SQLITE_C_INT = SQLITE_OK
            If newJournalMode <> oldJournalMode AndAlso _
               (oldJournalMode = PAGER_JOURNALMODE_WAL OrElse _
                newJournalMode = PAGER_JOURNALMODE_WAL) Then
                If pVdbe->db->autoCommit = 0 OrElse _
                   pVdbe->db->nVdbeRead > 1 Then
                    journalModeCode = SQLITE_ERROR
                    Dim zWalTransition As Const ZString Ptr = StrPtr("into")
                    If newJournalMode <> PAGER_JOURNALMODE_WAL Then _
                        zWalTransition = StrPtr("out of")
                    sqlite3VdbeError( _
                        pVdbe, _
                        StrPtr(!"cannot change %s wal mode from within a transaction"), _
                        zWalTransition)
                Else
                    If oldJournalMode = PAGER_JOURNALMODE_WAL Then
                        journalModeCode = sqlite3PagerCloseWal( _
                            pJournalPager, pVdbe->db)
                        If journalModeCode = SQLITE_OK Then _
                            sqlite3PagerSetJournalMode( _
                                pJournalPager, newJournalMode)
                    ElseIf oldJournalMode = PAGER_JOURNALMODE_MEMORY Then
                        sqlite3PagerSetJournalMode( _
                            pJournalPager, PAGER_JOURNALMODE_OFF)
                    End If
                    If journalModeCode = SQLITE_OK Then
                        Dim newFileFormat As SQLITE_C_INT = 1
                        If newJournalMode = PAGER_JOURNALMODE_WAL Then _
                            newFileFormat = 2
                        journalModeCode = sqlite3BtreeSetVersion( _
                            pJournalBtree, newFileFormat)
                    End If
                End If
            End If
#else
            Dim journalModeCode As SQLITE_C_INT = SQLITE_OK
#endif
            If journalModeCode <> SQLITE_OK Then _
                newJournalMode = oldJournalMode
            newJournalMode = sqlite3PagerSetJournalMode( _
                pJournalPager, newJournalMode)
            Dim zJournalModeName As Const ZString Ptr = _
                sqlite3JournalModename(newJournalMode)
            Dim journalTextCode As SQLITE_C_INT = sqlite3VdbeMemSetText( _
                @pVdbe->aMem[pOp->p2], zJournalModeName, -1, 0)
            If journalTextCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, journalTextCode)
            Dim journalEncodingCode As SQLITE_C_INT = sqlite3VdbeChangeEncoding( _
                @pVdbe->aMem[pOp->p2], pVdbe->db->enc)
            If journalEncodingCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, journalEncodingCode)
            If journalModeCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, journalModeCode)
#endif

#ifndef SQLITE_OMIT_VIRTUALTABLE
        Case OP_VCreate
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->db->nDb OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pOp->p3 <> 0 OrElse pOp->p4type <> P4_NOTUSED OrElse _
               pOp->p5 <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pVdbe->vdbeFlags And VDBE_READONLY_MASK) <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_READONLY)
            Dim virtualName As SqliteVdbeMem
            sqlite3VdbeMemInit(@virtualName, pVdbe->db, MEM_NULL)
            Dim copyNameCode As SQLITE_C_INT = sqlite3VdbeMemCopy( _
                @virtualName, @pVdbe->aMem[pOp->p2])
            If copyNameCode <> SQLITE_OK Then
                sqlite3VdbeMemRelease(@virtualName)
                Return sqlite3VdbeExecError(pVdbe, copyNameCode)
            End If
            If (virtualName.flags And MEM_STR) = 0 Then
                sqlite3VdbeMemRelease(@virtualName)
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            End If
            Dim zVirtualName As Const ZString Ptr = CPtr( _
                Const ZString Ptr, sqlite3ValueText(@virtualName, SQLITE_UTF8))
            Dim createVtabCode As SQLITE_C_INT
            If zVirtualName = 0 Then
                createVtabCode = IIf( _
                    pVdbe->db->mallocFailed <> 0, SQLITE_NOMEM, SQLITE_CORRUPT)
            Else
                createVtabCode = sqlite3VtabCallCreate( _
                    pVdbe->db, pOp->p1, zVirtualName, @pVdbe->zErrMsg)
            End If
            sqlite3VdbeMemRelease(@virtualName)
            If createVtabCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, createVtabCode)

        Case OP_VDestroy
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->db->nDb OrElse _
               (pOp->p4type <> P4_STATIC AndAlso _
                pOp->p4type <> P4_DYNAMIC) OrElse pOp->p4.z = 0 OrElse _
               pVdbe->db->nVDestroy = &H7FFFFFFF Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            pVdbe->db->nVDestroy += 1
            Dim destroyVtabCode As SQLITE_C_INT = sqlite3VtabCallDestroy( _
                pVdbe->db, pOp->p1, pOp->p4.z)
            pVdbe->db->nVDestroy -= 1
            If destroyVtabCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, destroyVtabCode)

        Case OP_VBegin
            If pOp->p4type <> P4_NOTUSED AndAlso pOp->p4type <> P4_VTAB Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pBeginVtable As SqliteVTable Ptr = 0
            If pOp->p4type = P4_VTAB AndAlso pOp->p4.p <> 0 Then _
                pBeginVtable = CPtr(SqliteVTable Ptr, pOp->p4.p)
            Dim beginVtabCode As SQLITE_C_INT = _
                sqlite3VtabBegin(pVdbe->db, pBeginVtable)
            If pBeginVtable <> 0 AndAlso pBeginVtable->pVtab <> 0 Then _
                sqlite3VtabImportErrmsg(pVdbe, pBeginVtable->pVtab)
            If beginVtabCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, beginVtabCode)

        Case OP_VRename
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p4type <> P4_VTAB OrElse pOp->p4.p = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pRenameTable As SqliteVTable Ptr = _
                CPtr(SqliteVTable Ptr, pOp->p4.p)
            If pRenameTable->pVtab = 0 OrElse _
               pRenameTable->pVtab->pModule = 0 OrElse _
               pRenameTable->pVtab->pModule->xRename = 0 OrElse _
               (pVdbe->aMem[pOp->p1].flags And MEM_STR) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim legacyAlterWasSet As SQLITE_C_INT = CInt( _
                (pVdbe->db->flags And SQLITE_LegacyAlter) <> 0)
            pVdbe->db->flags Or= SQLITE_LegacyAlter
            Dim renameCode As SQLITE_C_INT = sqlite3VdbeChangeEncoding( _
                @pVdbe->aMem[pOp->p1], SQLITE_UTF8)
            If renameCode = SQLITE_OK Then
                Dim xRename As SqliteVdbeVtabRenameProc = CPtr( _
                    SqliteVdbeVtabRenameProc, pRenameTable->pVtab->pModule->xRename)
                renameCode = xRename( _
                    pRenameTable->pVtab, pVdbe->aMem[pOp->p1].z)
            End If
            If legacyAlterWasSet = 0 Then _
                pVdbe->db->flags = pVdbe->db->flags And Not SQLITE_LegacyAlter
            sqlite3VtabImportErrmsg(pVdbe, pRenameTable->pVtab)
            pVdbe->vdbeFlags = pVdbe->vdbeFlags And Not VDBE_EXPIRED_MASK
            If renameCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, renameCode)
#endif

        Case OP_ParseSchema
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->db->nDb OrElse _
               pVdbe->db->aDb(pOp->p1).pSchema = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)

            Dim parseSchemaCode As SQLITE_C_INT = SQLITE_OK
            If pOp->p4.z = 0 Then
                If pOp->p5 = 0 OrElse _
                   (pOp->p4type <> P4_NOTUSED AndAlso _
                    pOp->p4type <> P4_DYNAMIC) Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                sqlite3SchemaClear(pVdbe->db->aDb(pOp->p1).pSchema)
                pVdbe->db->mDbFlags = pVdbe->db->mDbFlags And _
                    Not SQLITE3_VDBE_DBFLAG_SCHEMA_KNOWN_OK
                parseSchemaCode = sqlite3InitOne( _
                    pVdbe->db, pOp->p1, @pVdbe->zErrMsg, pOp->p5)
                pVdbe->db->mDbFlags Or= SQLITE3_VDBE_DBFLAG_SCHEMA_CHANGE
                pVdbe->vdbeFlags = pVdbe->vdbeFlags And _
                    Not VDBE_EXPIRED_MASK
            Else
                If pOp->p5 <> 0 OrElse _
                   pVdbe->db->aDb(pOp->p1).pBt = 0 OrElse _
                   (pOp->p4type <> P4_NOTUSED AndAlso _
                    pOp->p4type <> P4_STATIC AndAlso _
                    pOp->p4type <> P4_DYNAMIC) OrElse _
                   pVdbe->db->aDb(pOp->p1).zDbSName = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                If pVdbe->db->init.busy <> 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_LOCKED)

                Dim initData As SqliteInitData
                initData.db = pVdbe->db
                initData.iDb = pOp->p1
                initData.pzErrMsg = @pVdbe->zErrMsg
                initData.mInitFlags = 0
                initData.mxPage = sqlite3BtreeLastPage( _
                    CPtr(Btree Ptr, pVdbe->db->aDb(pOp->p1).pBt))
                    initData.rc = SQLITE_OK
                    initData.nInitRow = 0
                    Dim schemaSql As ZString Ptr = sqlite3MPrintf( _
                    pVdbe->db, _
                    StrPtr(!"SELECT*FROM\"%w\".%s WHERE %s ORDER BY rowid"), _
                    pVdbe->db->aDb(pOp->p1).zDbSName, _
                    StrPtr(!"sqlite_master"), pOp->p4.z)
                If schemaSql = 0 Then
                    parseSchemaCode = SQLITE_NOMEM
                Else
                    pVdbe->db->init.busy = 1
                    parseSchemaCode = sqlite3_exec( _
                        pVdbe->db, schemaSql, ProcPtr(sqlite3InitCallback), _
                        @initData, 0)
                    If parseSchemaCode = SQLITE_OK Then _
                        parseSchemaCode = initData.rc
                    If parseSchemaCode = SQLITE_OK AndAlso _
                       initData.nInitRow = 0 Then _
                        parseSchemaCode = SQLITE_CORRUPT
                    sqlite3DbFreeNN(pVdbe->db, schemaSql)
                    pVdbe->db->init.busy = 0
                End If
            End If
            If parseSchemaCode <> SQLITE_OK Then
                sqlite3ResetAllSchemasOfConnection(pVdbe->db)
                Return sqlite3VdbeExecError(pVdbe, parseSchemaCode)
            End If

        Case OP_SqlExec
            If pOp->p1 < 0 OrElse (pOp->p1 And Not &H0003) <> 0 OrElse _
               pOp->p3 <> 0 OrElse pOp->p5 <> 0 OrElse pOp->p4.z = 0 OrElse _
               (pOp->p4type <> P4_STATIC AndAlso _
                pOp->p4type <> P4_DYNAMIC) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)

#ifdef SQLITE_DEBUG
            sqlite3VdbeIncrWriteCounter(pVdbe, 0)
#endif
            Dim savedAuthorizer As SqliteAuthorizerCallback = _
                pVdbe->db->xAuth
            Dim savedTrace As u8 = pVdbe->db->mTrace
            Dim savedAnalysisLimit As SQLITE_C_INT = _
                pVdbe->db->nAnalysisLimit
            Dim sqlExecError As ZString Ptr = 0
            pVdbe->db->nSqlExec += 1
            If (pOp->p1 And &H0001) <> 0 Then
                pVdbe->db->xAuth = 0
                pVdbe->db->mTrace = 0
            End If
            If (pOp->p1 And &H0002) <> 0 Then _
                pVdbe->db->nAnalysisLimit = pOp->p2

            Dim sqlExecCode As SQLITE_C_INT = sqlite3_exec( _
                pVdbe->db, pOp->p4.z, 0, 0, @sqlExecError)
            pVdbe->db->nSqlExec -= 1
            pVdbe->db->xAuth = savedAuthorizer
            pVdbe->db->mTrace = savedTrace
            pVdbe->db->nAnalysisLimit = savedAnalysisLimit
            If sqlExecError <> 0 OrElse sqlExecCode <> SQLITE_OK Then
                If sqlExecError <> 0 Then _
                    sqlite3VdbeError(pVdbe, StrPtr(!"%s"), sqlExecError)
                sqlite3DbFree(pVdbe->db, sqlExecError)
                If sqlExecCode = SQLITE_OK Then sqlExecCode = SQLITE_ERROR
                Return sqlite3VdbeExecError(pVdbe, sqlExecCode)
            End If

        Case OP_DropTable, OP_DropIndex, OP_DropTrigger
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->db->nDb OrElse _
               pOp->p4.z = 0 OrElse _
               (pOp->p4type <> P4_NOTUSED AndAlso _
                pOp->p4type <> P4_STATIC AndAlso _
                pOp->p4type <> P4_DYNAMIC) OrElse _
               pVdbe->db->aDb(pOp->p1).pSchema = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pVdbe->vdbeFlags And VDBE_READONLY_MASK) <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_READONLY)
#ifdef SQLITE_DEBUG
            sqlite3VdbeIncrWriteCounter(pVdbe, 0)
#endif
            Select Case pOp->opcode
            Case OP_DropTable
                sqlite3UnlinkAndDeleteTable( _
                    pVdbe->db, pOp->p1, pOp->p4.z)
            Case OP_DropIndex
                sqlite3UnlinkAndDeleteIndex( _
                    pVdbe->db, pOp->p1, pOp->p4.z)
            Case OP_DropTrigger
                sqlite3UnlinkAndDeleteTrigger( _
                    pVdbe->db, pOp->p1, pOp->p4.z)
            End Select

#ifdef SQLITE_DEBUG
        Case OP_Abortable
            sqlite3VdbeAssertAbortable(pVdbe)

        Case OP_ReleaseReg
            If pOp->p1 <= 0 OrElse pOp->p2 < 0 OrElse _
               pOp->p1 > pVdbe->nMem OrElse _
               pOp->p2 > pVdbe->nMem - pOp->p1 + 1 OrElse _
               (pOp->p2 > 0 AndAlso pVdbe->aMem = 0) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim preserveMask As u32 = CUInt(pOp->p3)
            For iRegister As SQLITE_C_INT = 0 To pOp->p2 - 1
                Dim shouldRelease As SQLITE_C_INT = 1
                If iRegister < 32 Then
                    Dim bitMask As u32 = CULng(1) Shl iRegister
                    shouldRelease = CInt((preserveMask And bitMask) = 0)
                End If
                If shouldRelease <> 0 Then
                    Dim pMem As SqliteVdbeMem Ptr = _
                        @pVdbe->aMem[pOp->p1 + iRegister]
                    pMem->pScopyFrom = 0
                    If iRegister < 32 AndAlso pOp->p5 <> 0 Then
                        pMem->flags = pMem->flags And _
                            Not (MEM_TYPE_MASK Or MEM_ZERO)
                    End If
                End If
            Next
#endif

        Case OP_Transaction
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->db->nDb OrElse _
               pOp->p2 < 0 OrElse pOp->p2 > 2 OrElse _
               (pOp->p5 <> 0 AndAlso pOp->p5 <> 1) OrElse _
               (pOp->p5 <> 0 AndAlso pOp->p4type <> P4_INT32) OrElse _
               vdbeExecBtreeMaskTest(pVdbe, pOp->p1) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pOp->p2 <> 0 Then
                If (pVdbe->db->flags And _
                    SQLITE3_VDBE_DBFLAG_QUERY_ONLY) <> 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_READONLY)
                If (pVdbe->db->flags And _
                    SQLITE3_VDBE_DBFLAG_CORRUPT_RDONLY) <> 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            End If

            Dim pTransactionDatabase As SqliteDbSlot Ptr = _
                @pVdbe->db->aDb(pOp->p1)
            If pTransactionDatabase->pBt <> 0 Then
                Dim pTransactionBtree As Btree Ptr = _
                    CPtr(Btree Ptr, pTransactionDatabase->pBt)
                Dim schemaCookie As SQLITE_C_INT = 0
                Dim transactionCode As SQLITE_C_INT = sqlite3BtreeBeginTrans( _
                    pTransactionBtree, pOp->p2, @schemaCookie)
                If (transactionCode And &HFF) = SQLITE_BUSY Then
                    pVdbe->pc = programCounter
                    pVdbe->rc = transactionCode
                    sqlite3VdbeLeave(pVdbe)
                    Return transactionCode
                End If
                If transactionCode <> SQLITE_OK Then _
                    Return sqlite3VdbeExecError(pVdbe, transactionCode)

                If pOp->p2 <> 0 AndAlso _
                   (pVdbe->vdbeFlags And _
                    VDBE_USES_STMT_JOURNAL_MASK) <> 0 AndAlso _
                   (pVdbe->db->autoCommit = 0 OrElse _
                    pVdbe->db->nVdbeRead > 1) Then
                    If pVdbe->iStatement = 0 Then
                        If pVdbe->db->nStatement = &H7FFFFFFF Then _
                            Return sqlite3VdbeExecError(pVdbe, SQLITE_FULL)
                        pVdbe->db->nStatement += 1
                        pVdbe->iStatement = _
                            pVdbe->db->nSavepoint + pVdbe->db->nStatement
                    End If
                    transactionCode = sqlite3VtabSavepoint( _
                        pVdbe->db, SAVEPOINT_BEGIN, pVdbe->iStatement - 1)
                    If transactionCode = SQLITE_OK Then _
                        transactionCode = sqlite3BtreeBeginStmt( _
                            pTransactionBtree, pVdbe->iStatement)
                    pVdbe->nStmtDefCons = pVdbe->db->nDeferredCons
                    pVdbe->nStmtDefImmCons = pVdbe->db->nDeferredImmCons
                    If transactionCode <> SQLITE_OK Then _
                        Return sqlite3VdbeExecError(pVdbe, transactionCode)
                End If

                If pTransactionDatabase->pSchema = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                If pOp->p5 <> 0 AndAlso _
                   (schemaCookie <> pOp->p3 OrElse _
                   pTransactionDatabase->pSchema->iGeneration <> pOp->p4.i) Then
                    sqlite3DbFree(pVdbe->db, pVdbe->zErrMsg)
                    pVdbe->zErrMsg = sqlite3DbStrDup( _
                        pVdbe->db, StrPtr(!"database schema has changed"))
                    If pTransactionDatabase->pSchema->schema_cookie <> schemaCookie Then _
                        sqlite3ResetOneSchema(pVdbe->db, pOp->p1)
                    pVdbe->vdbeFlags = (pVdbe->vdbeFlags And _
                        Not VDBE_EXPIRED_MASK) Or 1
                    pVdbe->vdbeFlags = pVdbe->vdbeFlags And _
                        Not VDBE_CHANGECOUNT_MASK
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_SCHEMA)
                End If
            End If
            pVdbe->vdbeFlags Or= VDBE_BISREADER_MASK
            If pOp->p2 <> 0 Then _
                pVdbe->vdbeFlags = pVdbe->vdbeFlags And Not VDBE_READONLY_MASK

        Case OP_AutoCommit
            If (pOp->p1 <> 0 AndAlso pOp->p1 <> 1) OrElse _
               (pOp->p2 <> 0 AndAlso pOp->p2 <> 1) OrElse _
               (pOp->p1 = 0 AndAlso pOp->p2 <> 0) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pVdbe->db->autoCommit = CByte(pOp->p1) Then
                Dim autoCommitError As Const ZString Ptr
                If pOp->p1 = 0 Then
                    autoCommitError = StrPtr(!"cannot start a transaction within a transaction")
                ElseIf pOp->p2 <> 0 Then
                    autoCommitError = StrPtr(!"cannot rollback - no transaction is active")
                Else
                    autoCommitError = StrPtr(!"cannot commit - no transaction is active")
                End If
                sqlite3VdbeError(pVdbe, StrPtr(!"%s"), autoCommitError)
                Return sqlite3VdbeExecError(pVdbe, SQLITE_ERROR)
            End If

            If pOp->p2 <> 0 Then
                sqlite3RollbackAll(pVdbe->db, SQLITE_ABORT_ROLLBACK)
                pVdbe->db->autoCommit = 1
            ElseIf pOp->p1 <> 0 AndAlso pVdbe->db->nVdbeWrite > 0 Then
                sqlite3VdbeError( _
                    pVdbe, StrPtr(!"cannot commit transaction - SQL statements in progress"))
                Return sqlite3VdbeExecError(pVdbe, SQLITE_BUSY)
            ElseIf pOp->p1 <> 0 Then
                Dim deferredCode As SQLITE_C_INT = _
                    sqlite3VdbeCheckFkDeferred(pVdbe)
                If deferredCode <> SQLITE_OK Then _
                    Return sqlite3VdbeExecError(pVdbe, deferredCode)
                pVdbe->db->autoCommit = 1
            Else
                pVdbe->db->autoCommit = 0
            End If

            Dim haltCode As SQLITE_C_INT = sqlite3VdbeHalt(pVdbe)
            If haltCode = SQLITE_BUSY Then
                pVdbe->pc = programCounter
                pVdbe->db->autoCommit = CByte(1 - pOp->p1)
                pVdbe->rc = SQLITE_BUSY
                sqlite3VdbeLeave(pVdbe)
                Return SQLITE_BUSY
            End If
            sqlite3CloseSavepoints(pVdbe->db)
            sqlite3VdbeLeave(pVdbe)
            If pVdbe->rc = SQLITE_OK Then Return SQLITE_DONE
            Return SQLITE_ERROR

        Case OP_Savepoint
#ifdef SQLITE_DEBUG
            If checkSavepointCount(pVdbe->db) = 0 Then _
                sqlite3DebugAssert(StrPtr("checkSavepointCount(db)"))
#endif
            If (pOp->p1 <> SAVEPOINT_BEGIN AndAlso _
                pOp->p1 <> SAVEPOINT_RELEASE AndAlso _
                pOp->p1 <> SAVEPOINT_ROLLBACK) OrElse _
               pOp->p4.z = 0 OrElse _
               (pOp->p4type <> P4_STATIC AndAlso pOp->p4type <> P4_DYNAMIC) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)

            Dim pNameBytes As Const UByte Ptr = CPtr(Const UByte Ptr, pOp->p4.z)
            Dim nameLength As sqlite3_uint64 = 0
            While pNameBytes[nameLength] <> 0
                nameLength += 1
                If nameLength >= CULngInt(pVdbe->db->lengthLimit) OrElse _
                   nameLength > SQLITE_MAX_ALLOCATION_SIZE - _
                       SizeOf(SqliteSavepoint) - 1 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_TOOBIG)
            Wend

            If pOp->p1 = SAVEPOINT_BEGIN Then
                If pVdbe->db->nVdbeWrite > 0 Then
                    sqlite3VdbeError( _
                        pVdbe, StrPtr(!"cannot open savepoint - SQL statements in progress"))
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_BUSY)
                End If
                If pVdbe->db->nStatement > &H7FFFFFFF - _
                   pVdbe->db->nSavepoint Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_FULL)
                Dim vtabSavepointCode As SQLITE_C_INT = sqlite3VtabSavepoint( _
                    pVdbe->db, SAVEPOINT_BEGIN, _
                    pVdbe->db->nStatement + pVdbe->db->nSavepoint)
                If vtabSavepointCode <> SQLITE_OK Then _
                    Return sqlite3VdbeExecError(pVdbe, vtabSavepointCode)

                Dim allocationBytes As sqlite3_uint64 = _
                    CULngInt(SizeOf(SqliteSavepoint)) + nameLength + 1
                Dim pNewSavepoint As SqliteSavepoint Ptr = CPtr( _
                    SqliteSavepoint Ptr, _
                    sqlite3DbMallocZero(pVdbe->db, allocationBytes))
                If pNewSavepoint = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_NOMEM)
                pNewSavepoint->zName = CPtr( _
                    ZString Ptr, CPtr(UByte Ptr, pNewSavepoint) + _
                    SizeOf(SqliteSavepoint))
                If nameLength > 0 Then _
                    sqlite3VdbeExecMemcpy( _
                        pNewSavepoint->zName, pNameBytes, CULng(nameLength))
                CPtr(UByte Ptr, pNewSavepoint->zName)[nameLength] = 0
                pNewSavepoint->nDeferredCons = pVdbe->db->nDeferredCons
                pNewSavepoint->nDeferredImmCons = _
                    pVdbe->db->nDeferredImmCons
                pNewSavepoint->pNext = pVdbe->db->pSavepoint
                If pVdbe->db->autoCommit <> 0 Then
                    pVdbe->db->autoCommit = 0
                    pVdbe->db->isTransactionSavepoint = 1
                Else
                    If pVdbe->db->nSavepoint = &H7FFFFFFF Then
                        sqlite3DbFree(pVdbe->db, pNewSavepoint)
                        Return sqlite3VdbeExecError(pVdbe, SQLITE_FULL)
                    End If
                    pVdbe->db->nSavepoint += 1
                End If
                pVdbe->db->pSavepoint = pNewSavepoint
            Else
                If pOp->p1 = SAVEPOINT_RELEASE AndAlso _
                   pVdbe->db->nVdbeWrite > 0 Then
                    sqlite3VdbeError( _
                        pVdbe, StrPtr(!"cannot release savepoint - SQL statements in progress"))
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_BUSY)
                End If

                Dim pSavepoint As SqliteSavepoint Ptr = _
                    CPtr(SqliteSavepoint Ptr, pVdbe->db->pSavepoint)
                Dim savepointDepth As SQLITE_C_INT = 0
                While pSavepoint <> 0 AndAlso _
                      sqlite3StrICmp(pSavepoint->zName, pOp->p4.z) <> 0
                    savepointDepth += 1
                    pSavepoint = pSavepoint->pNext
                Wend
                If pSavepoint = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_ERROR)
                Dim isTransactionSavepoint As SQLITE_C_INT = IIf( _
                    pSavepoint->pNext = 0 AndAlso _
                    pVdbe->db->isTransactionSavepoint <> 0, 1, 0)

                If isTransactionSavepoint <> 0 AndAlso _
                   pOp->p1 = SAVEPOINT_RELEASE Then
                    Dim pOther As SqliteVdbe Ptr = _
                        CPtr(SqliteVdbe Ptr, pVdbe->db->pVdbe)
                    While pOther <> 0
                        If pOther <> pVdbe AndAlso _
                           pOther->eVdbeState = VDBE_RUN_STATE AndAlso _
                           (pOther->vdbeFlags And VDBE_READONLY_MASK) = 0 Then _
                            Return sqlite3VdbeExecError(pVdbe, SQLITE_BUSY)
                        pOther = CPtr(SqliteVdbe Ptr, pOther->pVNext)
                    Wend
                    Dim deferredCode As SQLITE_C_INT = _
                        sqlite3VdbeCheckFkDeferred(pVdbe)
                    If deferredCode <> SQLITE_OK Then _
                        Return sqlite3VdbeExecError(pVdbe, deferredCode)
                    pVdbe->db->autoCommit = 1
                    Dim haltCode As SQLITE_C_INT = _
                        sqlite3VdbeExecFinish(pVdbe, SQLITE_OK, OE_ABORT)
                    If haltCode = SQLITE_DONE Then _
                        pVdbe->db->isTransactionSavepoint = 0
                    sqlite3VdbeExecClearSavepoints(pVdbe->db)
                    sqlite3VdbeLeave(pVdbe)
                    Return haltCode
                End If

                Dim savepointIndex As SQLITE_C_INT = _
                    pVdbe->db->nSavepoint - savepointDepth - 1
                If isTransactionSavepoint <> 0 AndAlso _
                   pOp->p1 = SAVEPOINT_ROLLBACK Then savepointIndex = -1
                If (isTransactionSavepoint = 0 AndAlso _
                    (savepointIndex < 0 OrElse _
                     savepointIndex >= pVdbe->db->nSavepoint)) OrElse _
                   (isTransactionSavepoint <> 0 AndAlso _
                    pOp->p1 = SAVEPOINT_ROLLBACK AndAlso savepointIndex <> -1) Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)

                Dim isSchemaChange As SQLITE_C_INT = CInt( _
                    (pVdbe->db->mDbFlags And _
                     SQLITE3_VDBE_DBFLAG_SCHEMA_CHANGE) <> 0)
                If pOp->p1 = SAVEPOINT_ROLLBACK Then
                    For databaseIndex As SQLITE_C_INT = 0 To pVdbe->db->nDb - 1
                        Dim pSavepointBtree As Btree Ptr = CPtr( _
                            Btree Ptr, pVdbe->db->aDb(databaseIndex).pBt)
                        If pSavepointBtree <> 0 Then
                            Dim tripWriteOnly As SQLITE_C_INT = _
                                IIf(isSchemaChange = 0, 1, 0)
                            Dim tripCode As SQLITE_C_INT = _
                                sqlite3BtreeTripAllCursors( _
                                    pSavepointBtree, SQLITE_ABORT_ROLLBACK, _
                                    tripWriteOnly)
                            If tripCode <> SQLITE_OK Then _
                                Return sqlite3VdbeExecError(pVdbe, tripCode)
                        End If
                    Next
                End If

                For databaseIndex As SQLITE_C_INT = 0 To pVdbe->db->nDb - 1
                    Dim pSavepointBtree As Btree Ptr = CPtr( _
                        Btree Ptr, pVdbe->db->aDb(databaseIndex).pBt)
                    If pSavepointBtree <> 0 Then
                        Dim savepointCode As SQLITE_C_INT = _
                            sqlite3BtreeSavepoint( _
                                pSavepointBtree, pOp->p1, savepointIndex)
                        If savepointCode <> SQLITE_OK Then _
                            Return sqlite3VdbeExecError(pVdbe, savepointCode)
                    End If
                Next

                If isSchemaChange <> 0 Then
                    sqlite3ExpirePreparedStatements(pVdbe->db, 0)
                    sqlite3ResetAllSchemasOfConnection(pVdbe->db)
                    pVdbe->db->mDbFlags Or= SQLITE3_VDBE_DBFLAG_SCHEMA_CHANGE
                End If

                While pVdbe->db->pSavepoint <> pSavepoint
                    Dim pNested As SqliteSavepoint Ptr = _
                        CPtr(SqliteSavepoint Ptr, pVdbe->db->pSavepoint)
                    If pNested = 0 Then _
                        Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                    pVdbe->db->pSavepoint = pNested->pNext
                    sqlite3DbFree(pVdbe->db, pNested)
                    If pVdbe->db->nSavepoint > 0 Then _
                        pVdbe->db->nSavepoint -= 1
                Wend

                If pOp->p1 = SAVEPOINT_RELEASE Then
                    pVdbe->db->pSavepoint = pSavepoint->pNext
                    sqlite3DbFree(pVdbe->db, pSavepoint)
                    If isTransactionSavepoint = 0 AndAlso _
                       pVdbe->db->nSavepoint > 0 Then _
                        pVdbe->db->nSavepoint -= 1
                Else
                    pVdbe->db->nDeferredCons = pSavepoint->nDeferredCons
                    pVdbe->db->nDeferredImmCons = _
                        pSavepoint->nDeferredImmCons
                End If

                If isTransactionSavepoint = 0 OrElse _
                   pOp->p1 = SAVEPOINT_ROLLBACK Then
                    Dim vtabSavepointCode As SQLITE_C_INT = _
                        sqlite3VtabSavepoint( _
                            pVdbe->db, pOp->p1, savepointIndex)
                    If vtabSavepointCode <> SQLITE_OK Then _
                        Return sqlite3VdbeExecError(pVdbe, vtabSavepointCode)
                End If
            End If

#ifndef SQLITE_OMIT_VIRTUALTABLE
        Case OP_VOpen
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p4type <> P4_VTAB OrElse pOp->p4.p = 0 OrElse _
               pVdbe->apCsr = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pVirtualTable As SqliteVTable Ptr = _
                CPtr(SqliteVTable Ptr, pOp->p4.p)
            Dim pVirtualTableInstance As SqliteVtab Ptr = pVirtualTable->pVtab
            If pVirtualTableInstance = 0 OrElse _
               pVirtualTableInstance->pModule = 0 OrElse _
               pVirtualTableInstance->pModule->xOpen = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_LOCKED)

            If pVdbe->apCsr[pOp->p1] <> 0 Then
                Dim pExistingCursor As SqliteVdbeCursor Ptr = _
                    CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
                If pExistingCursor->eCurType = CURTYPE_VTAB AndAlso _
                   pExistingCursor->uc.pVtabCursor <> 0 AndAlso _
                   CPtr(SqliteVtabCursor Ptr, pExistingCursor->uc.pVtabCursor)->pVtab = _
                       pVirtualTableInstance Then Exit Select
            End If

            Dim xOpen As SqliteVdbeVtabOpenProc = _
                CPtr(SqliteVdbeVtabOpenProc, pVirtualTableInstance->pModule->xOpen)
            Dim pNewVtabCursor As SqliteVtabCursor Ptr = 0
            Dim openVtabCode As SQLITE_C_INT = _
                xOpen(pVirtualTableInstance, @pNewVtabCursor)
            sqlite3VtabImportErrmsg(pVdbe, pVirtualTableInstance)
            If openVtabCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, openVtabCode)
            If pNewVtabCursor = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            pNewVtabCursor->pVtab = pVirtualTableInstance

            If pVdbe->apCsr[pOp->p1] <> 0 Then
                sqlite3VdbeFreeCursorNN( _
                    pVdbe, CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1]))
                pVdbe->apCsr[pOp->p1] = 0
            End If
            If pVirtualTableInstance->nRef = &H7FFFFFFF Then
                If pVirtualTableInstance->pModule->xClose <> 0 Then
                    Dim xClose As SqliteVdbeVtabCloseProc = CPtr( _
                        SqliteVdbeVtabCloseProc, _
                        pVirtualTableInstance->pModule->xClose)
                    xClose(pNewVtabCursor)
                End If
                Return sqlite3VdbeExecError(pVdbe, SQLITE_FULL)
            End If
            Dim pVtabCursor As SqliteVdbeCursor Ptr = allocateCursor( _
                pVdbe, pOp->p1, 0, CURTYPE_VTAB)
            If pVtabCursor = 0 Then
                If pVirtualTableInstance->pModule->xClose <> 0 Then
                    Dim xClose As SqliteVdbeVtabCloseProc = CPtr( _
                        SqliteVdbeVtabCloseProc, _
                        pVirtualTableInstance->pModule->xClose)
                    xClose(pNewVtabCursor)
                End If
                Return sqlite3VdbeExecError(pVdbe, SQLITE_NOMEM)
            End If
            pVtabCursor->uc.pVtabCursor = pNewVtabCursor
            pVirtualTableInstance->nRef += 1
#endif

        Case OP_ReopenIdx
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 1 OrElse pOp->p3 < 0 OrElse _
               pOp->p3 >= pVdbe->db->nDb OrElse _
               (pOp->p5 And Not OPFLAG_SEEKEQ) <> 0 OrElse _
               pOp->p4type <> P4_KEYINFO OrElse pOp->p4.p = 0 OrElse _
               pVdbe->db->aDb(pOp->p3).pBt = 0 OrElse _
               vdbeExecBtreeMaskTest(pVdbe, pOp->p3) = 0 OrElse _
               pVdbe->apCsr = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim reopenKeyInfo As Any Ptr = pOp->p4.p
            Dim reopenFieldCount As SQLITE_C_INT = _
                CPtr(sqlite3VdbeKeyInfoPrefix Ptr, reopenKeyInfo)->nAllField
            If reopenFieldCount < 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)

            Dim pReopenCursor As SqliteVdbeCursor Ptr = 0
            If pVdbe->apCsr[pOp->p1] <> 0 Then
                pReopenCursor = CPtr( _
                    SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
                If pReopenCursor->eCurType <> CURTYPE_BTREE OrElse _
                   pReopenCursor->uc.pCursor = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            End If

            If pReopenCursor <> 0 AndAlso _
               pReopenCursor->iDb = pOp->p3 AndAlso _
               pReopenCursor->pgnoRoot = CUInt(pOp->p2) Then
                sqlite3BtreeClearCursor(pReopenCursor->uc.pCursor)
            Else
                pReopenCursor = allocateCursor( _
                    pVdbe, pOp->p1, reopenFieldCount, CURTYPE_BTREE)
                If pReopenCursor = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_NOMEM)
                pReopenCursor->iDb = CByte(pOp->p3)
                pReopenCursor->nullRow = 1
                pReopenCursor->cursorFlags Or= VDBE_CURSOR_ORDERED
                pReopenCursor->pgnoRoot = CUInt(pOp->p2)
                pReopenCursor->isTable = 0
                pReopenCursor->pKeyInfo = reopenKeyInfo
                Dim pReopenBtree As Btree Ptr = CPtr( _
                    Btree Ptr, pVdbe->db->aDb(pOp->p3).pBt)
                Dim reopenCode As SQLITE_C_INT = sqlite3BtreeCursor( _
                    pReopenBtree, _
                    pReopenCursor->pgnoRoot, 0, reopenKeyInfo, _
                    pReopenCursor->uc.pCursor)
                If reopenCode <> SQLITE_OK Then
                    pVdbe->apCsr[pOp->p1] = 0
                    Return sqlite3VdbeExecError(pVdbe, reopenCode)
                End If
            End If
            sqlite3BtreeCursorHintFlags( _
                pReopenCursor->uc.pCursor, _
                pOp->p5 And (BTREE_BULKLOAD Or BTREE_SEEK_EQ))

        Case OP_OpenRead, OP_OpenWrite
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p3 < 0 OrElse pOp->p3 >= pVdbe->db->nDb OrElse _
               pVdbe->db->aDb(pOp->p3).pBt = 0 OrElse _
               vdbeExecBtreeMaskTest(pVdbe, pOp->p3) = 0 OrElse _
               pVdbe->apCsr = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim rootPage As u32
            Dim writeFlags As SQLITE_C_INT = 0
            If pOp->opcode = OP_OpenWrite Then
                If (pVdbe->vdbeFlags And VDBE_READONLY_MASK) <> 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_READONLY)
                writeFlags = BTREE_WRCSR Or (pOp->p5 And OPFLAG_FORDELETE)
                If (pOp->p5 And OPFLAG_P2ISREG) <> 0 Then
                    If pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
                       (pVdbe->aMem[pOp->p2].flags And MEM_INT) = 0 Then _
                        Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                    rootPage = CUInt(pVdbe->aMem[pOp->p2].u.i)
                Else
                    If pOp->p2 <= 0 Then Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                    rootPage = CUInt(pOp->p2)
                End If
            Else
                ' Let sqlite3BtreeCursor decide whether root page zero is valid.
                If pOp->p2 < 0 OrElse (pOp->p5 And Not OPFLAG_SEEKEQ) <> 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                rootPage = CUInt(pOp->p2)
            End If
            Dim fieldCount As SQLITE_C_INT = 0
            Dim pKeyInfo As Any Ptr = 0
            If pOp->p4type = P4_KEYINFO Then
                If pOp->p4.p = 0 Then Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                pKeyInfo = pOp->p4.p
                fieldCount = CPtr(sqlite3VdbeKeyInfoPrefix Ptr, pKeyInfo)->nAllField
            ElseIf pOp->p4type = P4_INT32 Then
                fieldCount = pOp->p4.i
            ElseIf pOp->p4type <> P4_NOTUSED Then
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            End If
            If fieldCount < 0 Then Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = allocateCursor( _
                pVdbe, pOp->p1, fieldCount, CURTYPE_BTREE)
            If pCursor = 0 Then Return sqlite3VdbeExecError(pVdbe, SQLITE_NOMEM)
            pCursor->iDb = CByte(pOp->p3)
            pCursor->nullRow = 1
            pCursor->cursorFlags Or= VDBE_CURSOR_ORDERED
            pCursor->pgnoRoot = rootPage
            pCursor->isTable = IIf(pKeyInfo = 0, 1, 0)
            pCursor->pKeyInfo = pKeyInfo
#ifdef SQLITE_DEBUG
            pCursor->wrFlag = CByte(writeFlags)
#endif
            Dim pBtree As Btree Ptr = CPtr( _
                Btree Ptr, pVdbe->db->aDb(pOp->p3).pBt)
            Dim rc As SQLITE_C_INT = sqlite3BtreeCursor( _
                pBtree, pCursor->pgnoRoot, writeFlags, pKeyInfo, pCursor->uc.pCursor)
            If rc <> SQLITE_OK Then
                pVdbe->apCsr[pOp->p1] = 0
                Return sqlite3VdbeExecError(pVdbe, rc)
            End If
            sqlite3BtreeCursorHintFlags( _
                pCursor->uc.pCursor, pOp->p5 And (BTREE_BULKLOAD Or BTREE_SEEK_EQ))

        Case OP_CursorLock, OP_CursorUnlock
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pLockCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pLockCursor->eCurType <> CURTYPE_BTREE OrElse _
               pLockCursor->uc.pCursor = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pOp->opcode = OP_CursorLock Then
                sqlite3BtreeCursorPin(pLockCursor->uc.pCursor)
            Else
                sqlite3BtreeCursorUnpin(pLockCursor->uc.pCursor)
            End If

#ifndef SQLITE_OMIT_SHARED_CACHE
        Case OP_TableLock
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->db->nDb OrElse _
               pOp->p2 < 0 OrElse pOp->p3 < 0 OrElse pOp->p3 > 1 OrElse _
               pVdbe->db->aDb(pOp->p1).pBt = 0 OrElse _
               vdbeExecBtreeMaskTest(pVdbe, pOp->p1) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pOp->p3 <> 0 OrElse _
               (pVdbe->db->flags And _
                SQLITE3_VDBE_DBFLAG_READ_UNCOMMIT) = 0 Then
                Dim pLockedBtree As Btree Ptr = _
                    CPtr(Btree Ptr, pVdbe->db->aDb(pOp->p1).pBt)
                Dim tableLockCode As SQLITE_C_INT = sqlite3BtreeLockTable( _
                    pLockedBtree, pOp->p2, CByte(pOp->p3))
                If tableLockCode <> SQLITE_OK Then
                    If (tableLockCode And &HFF) = SQLITE_LOCKED Then
                        ' P4 is only needed to format a lock-conflict message.
                        Dim zTableName As Const ZString Ptr = pOp->p4.z
                        If zTableName = 0 Then zTableName = StrPtr("unknown")
                        sqlite3VdbeError( _
                            pVdbe, StrPtr(!"database table is locked: %s"), _
                            zTableName)
                    End If
                    Return sqlite3VdbeExecError(pVdbe, tableLockCode)
                End If
            End If
#endif

#ifdef SQLITE_ENABLE_COLUMN_USED_MASK
        Case OP_ColumnsUsed
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pColumnCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pColumnCursor->eCurType <> CURTYPE_BTREE Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            pColumnCursor->maskUsed = _
                (CULngInt(CUInt(pOp->p3)) Shl 32) Or CULngInt(CUInt(pOp->p2))
#endif

        Case OP_IfEmpty
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 < 0 OrElse pOp->p2 >= pVdbe->nOp OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pEmptyCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pEmptyCursor->eCurType <> CURTYPE_BTREE OrElse _
               pEmptyCursor->uc.pCursor = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim isEmpty As SQLITE_C_INT = 0
            Dim emptyCheckCode As SQLITE_C_INT = sqlite3BtreeIsEmpty( _
                pEmptyCursor->uc.pCursor, @isEmpty)
            If emptyCheckCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, emptyCheckCode)
            If isEmpty <> 0 Then nextCounter = pOp->p2

        Case OP_IfSizeBetween
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 < 0 OrElse pOp->p2 >= pVdbe->nOp OrElse _
               pOp->p3 < -1 OrElse pOp->p3 > 1280 OrElse _
               pOp->p4type <> P4_INT32 OrElse _
               pOp->p4.i < -1 OrElse pOp->p4.i > 1280 OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pSizeCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pSizeCursor->eCurType <> CURTYPE_BTREE OrElse _
               pSizeCursor->uc.pCursor = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim isSizeCursorEmpty As SQLITE_C_INT = 0
            Dim sizeCheckCode As SQLITE_C_INT = sqlite3BtreeFirst( _
                pSizeCursor->uc.pCursor, @isSizeCursorEmpty)
            If sizeCheckCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, sizeCheckCode)
            Dim sizeEstimate As sqlite3_int64 = -1
            If isSizeCursorEmpty = 0 Then
                sizeEstimate = sqlite3BtreeRowCountEst(pSizeCursor->uc.pCursor)
                If sizeEstimate <= 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                sizeEstimate = sqlite3LogEst(CULngInt(sizeEstimate))
            End If
            If sizeEstimate >= pOp->p3 AndAlso sizeEstimate <= pOp->p4.i Then _
                nextCounter = pOp->p2

        Case OP_OpenEphemeral, OP_OpenAutoindex
            If pOp->opcode = OP_OpenAutoindex AndAlso pOp->p3 <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim openCode As SQLITE_C_INT = vdbeOpenEphemeralCursor(pVdbe, pOp)
            If openCode <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, openCode)

        Case OP_OpenDup
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 < 0 OrElse pOp->p2 >= pVdbe->nCursor OrElse _
               pOp->p1 = pOp->p2 OrElse pOp->p5 <> 0 OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p2] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pOriginalCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p2])
            If pOriginalCursor->eCurType <> CURTYPE_BTREE OrElse _
               (pOriginalCursor->cursorFlags And VDBE_CURSOR_EPHEMERAL) = 0 OrElse _
               pOriginalCursor->ub.pBtx = 0 OrElse _
               pOriginalCursor->uc.pCursor = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pDuplicateCursor As SqliteVdbeCursor Ptr = allocateCursor( _
                pVdbe, pOp->p1, pOriginalCursor->nField, CURTYPE_BTREE)
            If pDuplicateCursor = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_NOMEM)

            pDuplicateCursor->nullRow = 1
            pDuplicateCursor->cursorFlags = pOriginalCursor->cursorFlags Or _
                VDBE_CURSOR_NO_REUSE
            pDuplicateCursor->pKeyInfo = pOriginalCursor->pKeyInfo
            pDuplicateCursor->isTable = pOriginalCursor->isTable
            pDuplicateCursor->iDb = pOriginalCursor->iDb
            pDuplicateCursor->pgnoRoot = pOriginalCursor->pgnoRoot
            pDuplicateCursor->ub.pBtx = pOriginalCursor->ub.pBtx
            pOriginalCursor->cursorFlags Or= VDBE_CURSOR_NO_REUSE

            Dim duplicateOpenCode As SQLITE_C_INT = sqlite3BtreeCursor( _
                pDuplicateCursor->ub.pBtx, pDuplicateCursor->pgnoRoot, _
                BTREE_WRCSR, pDuplicateCursor->pKeyInfo, _
                pDuplicateCursor->uc.pCursor)
            If duplicateOpenCode <> SQLITE_OK Then
                pVdbe->apCsr[pOp->p1] = 0
                Return sqlite3VdbeExecError(pVdbe, duplicateOpenCode)
            End If

        Case OP_SorterOpen
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 < 0 OrElse pOp->p4type <> P4_KEYINFO OrElse _
               pOp->p4.p = 0 OrElse pVdbe->apCsr = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pSorterCursor As SqliteVdbeCursor Ptr = allocateCursor( _
                pVdbe, pOp->p1, pOp->p2, CURTYPE_SORTER)
            If pSorterCursor = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_NOMEM)
            pSorterCursor->pKeyInfo = pOp->p4.p
            pSorterCursor->nullRow = 1
            Dim sorterOpenCode As SQLITE_C_INT = sqlite3VdbeSorterInit( _
                pVdbe->db, pOp->p3, pSorterCursor)
            If sorterOpenCode <> SQLITE_OK Then
                sqlite3VdbeFreeCursorNN(pVdbe, pSorterCursor)
                pVdbe->apCsr[pOp->p1] = 0
                Return sqlite3VdbeExecError(pVdbe, sorterOpenCode)
            End If

        Case OP_SequenceTest
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 > pVdbe->nOp OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pSequenceCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pSequenceCursor->eCurType <> CURTYPE_SORTER Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pSequenceCursor->seqCount = 9223372036854775807LL Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_FULL)
            If pSequenceCursor->seqCount = 0 Then nextCounter = pOp->p2
            pSequenceCursor->seqCount += 1

        Case OP_InitCoroutine
            Dim maxCoroutineRegister As SQLITE_C_INT = _
                pVdbe->nMem - pVdbe->nCursor
            If pOp->p1 <= 0 OrElse pOp->p1 > maxCoroutineRegister OrElse _
               pOp->p2 < 0 OrElse pOp->p2 >= pVdbe->nOp OrElse _
               pOp->p3 < 0 OrElse pOp->p3 >= pVdbe->nOp OrElse _
               pVdbe->aMem = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCoroutine As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p1]
            If (pCoroutine->flags And MEM_DYN) <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            sqlite3VdbeMemSetInt64(pCoroutine, pOp->p3 - 1)
            If pOp->p2 <> 0 Then nextCounter = pOp->p2

        Case OP_Yield
            Dim maxCoroutineRegister As SQLITE_C_INT = _
                pVdbe->nMem - pVdbe->nCursor
            If pOp->p1 <= 0 OrElse pOp->p1 > maxCoroutineRegister OrElse _
               pOp->p2 < 0 OrElse pOp->p2 >= pVdbe->nOp OrElse _
               pVdbe->aMem = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCoroutine As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p1]
            If pCoroutine->flags <> MEM_INT OrElse _
               pCoroutine->u.i < -1 OrElse pCoroutine->u.i >= pVdbe->nOp Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim resumeAddress As SQLITE_C_INT = CInt(pCoroutine->u.i)
            pCoroutine->u.i = programCounter
            nextCounter = resumeAddress + 1

        Case OP_EndCoroutine
            Dim maxCoroutineRegister As SQLITE_C_INT = _
                pVdbe->nMem - pVdbe->nCursor
            If pOp->p1 <= 0 OrElse pOp->p1 > maxCoroutineRegister OrElse _
               pVdbe->aMem = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCoroutine As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p1]
            If pCoroutine->flags <> MEM_INT OrElse _
               pCoroutine->u.i < 0 OrElse pCoroutine->u.i >= pVdbe->nOp Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim callerYieldIndex As SQLITE_C_INT = CInt(pCoroutine->u.i)
            Dim pCallerYield As SqliteVdbeOp Ptr = _
                @pVdbe->aOp[callerYieldIndex]
            If pCallerYield->opcode <> OP_Yield OrElse _
               pCallerYield->p2 < 0 OrElse pCallerYield->p2 >= pVdbe->nOp OrElse _
               programCounter <= 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            pCoroutine->u.i = programCounter - 1
            nextCounter = pCallerYield->p2

        Case OP_SorterInsert
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pSorterCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pSorterCursor->eCurType <> CURTYPE_SORTER Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pSorterRecord As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p2]
            If (pSorterRecord->flags And MEM_BLOB) = 0 OrElse _
               pSorterRecord->n <= 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim expandSorterCode As SQLITE_C_INT = _
                sqlite3VdbeMemExpandBlob(pSorterRecord)
            If expandSorterCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, expandSorterCode)
            Dim sorterWriteCode As SQLITE_C_INT = _
                sqlite3VdbeSorterWrite(pSorterCursor, pSorterRecord)
            If sorterWriteCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, sorterWriteCode)

        Case OP_SorterCompare
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 > pVdbe->nOp OrElse _
               pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem OrElse _
               pOp->p4type <> P4_INT32 OrElse pOp->p4.i < 0 OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pSorterCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pSorterCursor->eCurType <> CURTYPE_SORTER Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim sorterCompareResult As SQLITE_C_INT = 0
            Dim sorterCompareCode As SQLITE_C_INT = sqlite3VdbeSorterCompare( _
                pSorterCursor, @pVdbe->aMem[pOp->p3], pOp->p4.i, _
                @sorterCompareResult)
            If sorterCompareCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, sorterCompareCode)
            If sorterCompareResult <> 0 Then nextCounter = pOp->p2

        Case OP_SorterData
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pOp->p3 < 0 OrElse pOp->p3 >= pVdbe->nCursor OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 OrElse _
               pVdbe->apCsr[pOp->p3] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pSorterCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pSorterCursor->eCurType <> CURTYPE_SORTER Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim sorterRowCode As SQLITE_C_INT = sqlite3VdbeSorterRowkey( _
                pSorterCursor, @pVdbe->aMem[pOp->p2])
            If sorterRowCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, sorterRowCode)
            Dim pRowCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p3])
            pRowCursor->cacheStatus = CACHE_STALE

        Case OP_OpenPseudo
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 >= pVdbe->nMem OrElse pOp->p3 < 0 OrElse _
               pOp->p5 <> 0 OrElse pVdbe->apCsr = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = allocateCursor( _
                pVdbe, pOp->p1, pOp->p3, CURTYPE_PSEUDO)
            If pCursor = 0 Then Return sqlite3VdbeExecError(pVdbe, SQLITE_NOMEM)
            pCursor->iDb = 0
            pCursor->nullRow = 1
            pCursor->isTable = 1
            pCursor->seekResult = pOp->p2

        Case OP_Close
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pVdbe->apCsr = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pVdbe->apCsr[pOp->p1] <> 0 Then
                Dim pCursor As SqliteVdbeCursor Ptr = _
                    CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
                sqlite3VdbeFreeCursorNN(pVdbe, pCursor)
                pVdbe->apCsr[pOp->p1] = 0
            End If

        Case OP_CreateBtree
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->db->nDb OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pVdbe->db->aDb(pOp->p1).pBt = 0 OrElse _
               vdbeExecBtreeMaskTest(pVdbe, pOp->p1) = 0 OrElse _
               (pVdbe->vdbeFlags And VDBE_READONLY_MASK) <> 0 OrElse _
               (pOp->p3 <> BTREE_INTKEY AndAlso pOp->p3 <> BTREE_BLOBKEY) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_MISUSE)
            Dim rootPage As u32 = 0
            Dim pBtree As Btree Ptr = CPtr( _
                Btree Ptr, pVdbe->db->aDb(pOp->p1).pBt)
            Dim rc As SQLITE_C_INT = sqlite3BtreeCreateTable(pBtree, @rootPage, pOp->p3)
            If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
            sqlite3VdbeMemSetInt64(@pVdbe->aMem[pOp->p2], CULngInt(rootPage))

        Case OP_Rewind, OP_Sort, OP_SorterSort
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 < 0 OrElse pOp->p2 > pVdbe->nOp OrElse _
               pOp->p5 <> 0 OrElse pVdbe->apCsr = 0 OrElse _
               pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            Dim isEmpty As SQLITE_C_INT = 1
            Dim rc As SQLITE_C_INT
            If pCursor->eCurType = CURTYPE_SORTER Then
                If pOp->opcode <> OP_SorterSort Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                rc = sqlite3VdbeSorterRewind(pCursor, @isEmpty)
            Else
                If pCursor->eCurType <> CURTYPE_BTREE OrElse _
                   pCursor->uc.pCursor = 0 OrElse pOp->opcode = OP_SorterSort Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                rc = sqlite3BtreeFirst(pCursor->uc.pCursor, @isEmpty)
                pCursor->deferredMoveto = 0
            End If
            If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
#ifdef SQLITE_TEST
            If pOp->opcode = OP_Sort OrElse pOp->opcode = OP_SorterSort Then
                sqlite3_sort_count += 1
                sqlite3_search_count -= 1
            End If
#endif
            pCursor->nullRow = CByte(isEmpty)
            pCursor->cacheStatus = CACHE_STALE
            If pOp->opcode = OP_Sort OrElse pOp->opcode = OP_SorterSort Then _
                pVdbe->aCounter(SQLITE_STMTSTATUS_SORT) += 1
#ifdef SQLITE_DEBUG
            pCursor->seekOp = pOp->opcode
#endif
            If isEmpty <> 0 AndAlso pOp->p2 > 0 Then nextCounter = pOp->p2

        Case OP_SeekEnd, OP_Last
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 < 0 OrElse pOp->p2 > pVdbe->nOp OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pCursor->eCurType <> CURTYPE_BTREE OrElse pCursor->uc.pCursor = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pOp->opcode = OP_SeekEnd Then
                If pOp->p2 <> 0 Then Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                pCursor->seekResult = -1
                If sqlite3BtreeCursorIsValidNN(pCursor->uc.pCursor) <> 0 Then _
                    Exit Select
            End If
            Dim isEmpty As SQLITE_C_INT = 1
            Dim rc As SQLITE_C_INT = sqlite3BtreeLast(pCursor->uc.pCursor, @isEmpty)
            If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
            pCursor->nullRow = CByte(isEmpty)
            pCursor->deferredMoveto = 0
            pCursor->cacheStatus = CACHE_STALE
#ifdef SQLITE_DEBUG
            pCursor->seekOp = pOp->opcode
#endif
            If isEmpty <> 0 AndAlso pOp->p2 > 0 Then nextCounter = pOp->p2

        Case OP_Count
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pCursor->eCurType <> CURTYPE_BTREE OrElse pCursor->uc.pCursor = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim entryCount As sqlite3_int64 = 0
            Dim rc As SQLITE_C_INT
            If pOp->p3 <> 0 Then
                entryCount = sqlite3BtreeRowCountEst(pCursor->uc.pCursor)
            Else
                rc = sqlite3BtreeCount( _
                    pVdbe->db, pCursor->uc.pCursor, @entryCount)
                If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
            End If
            sqlite3VdbeMemSetInt64(@pVdbe->aMem[pOp->p2], entryCount)

#ifndef SQLITE_OMIT_PAGER_PRAGMAS
        Case OP_Pagecount
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->db->nDb OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pVdbe->db->aDb(pOp->p1).pBt = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim currentPageCount As u32 = sqlite3BtreeLastPage( _
                CPtr(Btree Ptr, pVdbe->db->aDb(pOp->p1).pBt))
            sqlite3VdbeMemSetInt64( _
                @pVdbe->aMem[pOp->p2], currentPageCount)

        Case OP_MaxPgcnt
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->db->nDb OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pOp->p3 < 0 OrElse pVdbe->db->aDb(pOp->p1).pBt = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pPageCountBtree As Btree Ptr = _
                CPtr(Btree Ptr, pVdbe->db->aDb(pOp->p1).pBt)
            Dim requestedMaxPage As u32 = 0
            If pOp->p3 <> 0 Then
                requestedMaxPage = sqlite3BtreeLastPage(pPageCountBtree)
                If requestedMaxPage < CUInt(pOp->p3) Then _
                    requestedMaxPage = CUInt(pOp->p3)
            End If
            Dim actualMaxPage As u32 = sqlite3BtreeMaxPageCount( _
                pPageCountBtree, requestedMaxPage)
            sqlite3VdbeMemSetInt64( _
                @pVdbe->aMem[pOp->p2], actualMaxPage)
#endif

#ifndef SQLITE_OMIT_AUTOVACUUM
        Case OP_IncrVacuum
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->db->nDb OrElse _
               pOp->p2 < 0 OrElse pOp->p2 > pVdbe->nOp OrElse _
               pVdbe->db->aDb(pOp->p1).pBt = 0 OrElse _
               vdbeExecBtreeMaskTest(pVdbe, pOp->p1) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pVdbe->vdbeFlags And VDBE_READONLY_MASK) <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_READONLY)
            Dim vacuumCode As SQLITE_C_INT = sqlite3BtreeIncrVacuum( _
                CPtr(Btree Ptr, pVdbe->db->aDb(pOp->p1).pBt))
            If vacuumCode = SQLITE_DONE Then
                nextCounter = pOp->p2
            ElseIf vacuumCode <> SQLITE_OK Then
                Return sqlite3VdbeExecError(pVdbe, vacuumCode)
            End If
#endif

#if Not defined(SQLITE_OMIT_VACUUM) AndAlso Not defined(SQLITE_OMIT_ATTACH)
        Case OP_Vacuum
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->db->nDb OrElse _
               pOp->p1 = 1 OrElse pOp->p2 < 0 OrElse _
               (pOp->p2 <> 0 AndAlso pOp->p2 >= pVdbe->nMem) OrElse _
               pOp->p3 <> 0 OrElse _
               pOp->p4type <> P4_NOTUSED OrElse pOp->p5 <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pVdbe->vdbeFlags And VDBE_READONLY_MASK) <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_READONLY)
            Dim pVacuumOutput As SqliteVdbeMem Ptr = 0
            If pOp->p2 <> 0 Then pVacuumOutput = @pVdbe->aMem[pOp->p2]
            Dim vacuumCode As SQLITE_C_INT = sqlite3RunVacuum( _
                @pVdbe->zErrMsg, pVdbe->db, pOp->p1, pVacuumOutput)
            If vacuumCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, vacuumCode)
#endif

        Case OP_Clear
            If pOp->p1 <= 0 OrElse pOp->p2 < 0 OrElse _
               pOp->p2 >= pVdbe->db->nDb OrElse _
               pVdbe->db->aDb(pOp->p2).pBt = 0 OrElse _
               vdbeExecBtreeMaskTest(pVdbe, pOp->p2) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pVdbe->vdbeFlags And VDBE_READONLY_MASK) <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_READONLY)
            If pOp->p3 > 0 AndAlso pOp->p3 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pOp->p3 > 0 AndAlso _
               (pVdbe->aMem[pOp->p3].flags And MEM_INT) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim changeCount As sqlite3_int64 = 0
            Dim pBtree As Btree Ptr = CPtr( _
                Btree Ptr, pVdbe->db->aDb(pOp->p2).pBt)
            Dim rc As SQLITE_C_INT = sqlite3BtreeClearTable( _
                pBtree, pOp->p1, @changeCount)
            If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
            If pOp->p3 <> 0 Then
                If sqlite3AddInt64(@pVdbe->nChange, changeCount) <> 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_FULL)
                pVdbe->vdbeFlags Or= VDBE_CHANGECOUNT_MASK
                If pOp->p3 > 0 Then
                    Dim pCounter As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p3]
                    If sqlite3AddInt64(@pCounter->u.i, changeCount) <> 0 Then _
                        Return sqlite3VdbeExecError(pVdbe, SQLITE_FULL)
                End If
            End If
            If pVdbe->apCsr <> 0 Then
                For iCursor As SQLITE_C_INT = 0 To pVdbe->nCursor - 1
                    If pVdbe->apCsr[iCursor] <> 0 Then
                        Dim pOpenCursor As SqliteVdbeCursor Ptr = _
                            CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[iCursor])
                        If pOpenCursor->iDb = pOp->p2 AndAlso _
                           pOpenCursor->pgnoRoot = CUInt(pOp->p1) Then
                            pOpenCursor->nullRow = 1
                            pOpenCursor->cacheStatus = CACHE_STALE
                        End If
                    End If
                Next
            End If

        Case OP_SeekRowid, OP_NotExists
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem OrElse _
               pOp->p2 < 0 OrElse pOp->p2 > pVdbe->nOp OrElse _
               (pOp->opcode = OP_NotExists AndAlso pOp->p2 = 0) OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pCursor->eCurType <> CURTYPE_BTREE OrElse pCursor->isTable = 0 OrElse _
               pCursor->uc.pCursor = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pInput As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p3]
            Dim rowId As sqlite3_int64 = 0
            If (pInput->flags And (MEM_INT Or MEM_INTREAL)) <> 0 Then
                If pOp->opcode = OP_NotExists AndAlso (pInput->flags And MEM_INT) = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                rowId = pInput->u.i
            Else
                Dim keyCopy As SqliteVdbeMem
                sqlite3VdbeMemInit(@keyCopy, pVdbe->db, MEM_NULL)
                sqlite3VdbeMemShallowCopy(@keyCopy, pInput, MEM_EPHEM)
                If (keyCopy.flags And MEM_STR) <> 0 Then _
                    sqlite3ApplyNumericAffinity(@keyCopy, 1)
                Dim keyIsInteger As SQLITE_C_INT = 0
                If (keyCopy.flags And MEM_INT) <> 0 Then
                    rowId = keyCopy.u.i
                    keyIsInteger = 1
                ElseIf (keyCopy.flags And MEM_REAL) <> 0 AndAlso _
                       keyCopy.u.r >= -9223372036854775808.0 AndAlso _
                       keyCopy.u.r <= 9223372036854774784.0 Then
                    rowId = sqlite3RealToI64(keyCopy.u.r)
                    If CDbl(rowId) = keyCopy.u.r Then keyIsInteger = 1
                End If
                sqlite3VdbeMemRelease(@keyCopy)
                If keyIsInteger = 0 Then
                    nextCounter = pOp->p2
                    Exit Select
                End If
            End If

#ifdef SQLITE_DEBUG
            If pOp->opcode = OP_SeekRowid Then pCursor->seekOp = OP_SeekRowid
#endif
            Dim seekResult As SQLITE_C_INT = 0
            Dim seekRc As SQLITE_C_INT = sqlite3BtreeTableMoveto( _
                pCursor->uc.pCursor, rowId, 0, @seekResult)
            If seekRc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, seekRc)
            pCursor->movetoTarget = rowId
            pCursor->nullRow = 0
            pCursor->cacheStatus = CACHE_STALE
            pCursor->deferredMoveto = 0
            pCursor->seekResult = seekResult
            If seekResult <> 0 Then
                If pOp->opcode = OP_SeekRowid AndAlso pOp->p2 = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                nextCounter = pOp->p2
            End If

        Case OP_SeekLT, OP_SeekLE, OP_SeekGE, OP_SeekGT
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 > pVdbe->nOp OrElse _
               pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem OrElse _
               (pOp->p4type <> P4_INT32 AndAlso _
                pOp->p4type <> P4_NOTUSED) OrElse _
               pVdbe->apCsr = 0 OrElse _
               pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pCursor->eCurType <> CURTYPE_BTREE OrElse _
               pCursor->uc.pCursor = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            ' A prior OR branch may leave a deferred position on this cursor.
            pCursor->nullRow = 0
            pCursor->deferredMoveto = 0
            pCursor->cacheStatus = CACHE_STALE
            Dim shouldCountSearch As SQLITE_C_INT = 1
            If pCursor->isTable = 0 Then
                Dim fieldCount As SQLITE_C_INT = pOp->p4.i
                If fieldCount <= 0 OrElse fieldCount > pVdbe->nMem - pOp->p3 OrElse _
                   pCursor->pKeyInfo = 0 OrElse fieldCount > _
                       CPtr(sqlite3VdbeKeyInfoPrefix Ptr, _
                           pCursor->pKeyInfo)->nAllField Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)

                Dim unpacked As sqlite3VdbeUnpackedRecord
                unpacked.pKeyInfo = pCursor->pKeyInfo
                unpacked.aMem = @pVdbe->aMem[pOp->p3]
                unpacked.u.i = 0
                unpacked.n = 0
                unpacked.nField = CUShort(fieldCount)
                If pOp->opcode = OP_SeekGT OrElse pOp->opcode = OP_SeekLE Then
                    unpacked.default_rc = -1
                Else
                    unpacked.default_rc = 1
                End If
                unpacked.errCode = SQLITE_OK
                unpacked.r1 = 0
                unpacked.r2 = 0
                unpacked.eqSeen = 0
                Dim indexResult As SQLITE_C_INT = 0
                Dim indexRc As SQLITE_C_INT = sqlite3BtreeIndexMoveto( _
                    pCursor->uc.pCursor, @unpacked, @indexResult)
                If indexRc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, indexRc)

#ifdef SQLITE_DEBUG
                pCursor->seekOp = pOp->opcode
#endif
                If sqlite3BtreeCursorHasHint(pCursor->uc.pCursor, BTREE_SEEK_EQ) <> 0 AndAlso _
                   unpacked.eqSeen = 0 Then
                    shouldCountSearch = 0
                    indexResult = 1
                ElseIf pOp->opcode >= OP_SeekGE Then
                    If indexResult < 0 OrElse _
                       (indexResult = 0 AndAlso pOp->opcode = OP_SeekGT) Then
                        indexRc = sqlite3BtreeNext(pCursor->uc.pCursor, 0)
                        If indexRc = SQLITE_DONE Then
                            indexRc = SQLITE_OK
                            indexResult = 1
                        ElseIf indexRc = SQLITE_OK Then
                            indexResult = 0
                        End If
                    Else
                        indexResult = 0
                    End If
                Else
                    If indexResult > 0 OrElse _
                       (indexResult = 0 AndAlso pOp->opcode = OP_SeekLT) Then
                        indexRc = sqlite3BtreePrevious(pCursor->uc.pCursor, 0)
                        If indexRc = SQLITE_DONE Then
                            indexRc = SQLITE_OK
                            indexResult = 1
                        ElseIf indexRc = SQLITE_OK Then
                            indexResult = 0
                        End If
                    Else
                        indexResult = sqlite3BtreeEof(pCursor->uc.pCursor)
                    End If
                End If
                If indexRc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, indexRc)
                pCursor->seekResult = indexResult
                If indexResult <> 0 Then nextCounter = pOp->p2
            Else
                If pOp->p4.i <> 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)

            Dim keyCopy As SqliteVdbeMem
            sqlite3VdbeMemInit(@keyCopy, pVdbe->db, MEM_NULL)
            sqlite3VdbeMemShallowCopy( _
                @keyCopy, @pVdbe->aMem[pOp->p3], MEM_EPHEM)
            If (keyCopy.flags And MEM_STR) <> 0 AndAlso _
               (keyCopy.flags And (MEM_INT Or MEM_INTREAL Or MEM_REAL)) = 0 Then _
                sqlite3ApplyNumericAffinity(@keyCopy, 0)
            If pVdbe->db->mallocFailed <> 0 Then
                sqlite3VdbeMemRelease(@keyCopy)
                Return sqlite3VdbeExecError(pVdbe, SQLITE_NOMEM)
            End If

            Dim effectiveOpcode As UByte = pOp->opcode
            Dim targetRowId As sqlite3_int64 = 0
            Dim hasNumericKey As SQLITE_C_INT = _
                IIf((keyCopy.flags And (MEM_INT Or MEM_INTREAL Or MEM_REAL)) <> 0, 1, 0)
            Dim rc As SQLITE_C_INT = SQLITE_OK
            Dim seekResult As SQLITE_C_INT = 0
            If hasNumericKey = 0 Then
                If (keyCopy.flags And MEM_NULL) <> 0 OrElse effectiveOpcode >= OP_SeekGE Then
                    pCursor->nullRow = 1
                    pCursor->deferredMoveto = 0
                    pCursor->cacheStatus = CACHE_STALE
                    sqlite3VdbeMemRelease(@keyCopy)
                    nextCounter = pOp->p2
                    Exit Select
                End If
                shouldCountSearch = 0
                rc = sqlite3BtreeLast(pCursor->uc.pCursor, @seekResult)
                If rc = SQLITE_OK Then
                    pCursor->nullRow = CByte(seekResult)
                    pCursor->deferredMoveto = 0
                    pCursor->cacheStatus = CACHE_STALE
                    If seekResult <> 0 Then nextCounter = pOp->p2
                End If
            Else
                If (keyCopy.flags And (MEM_INT Or MEM_INTREAL)) <> 0 Then
                    targetRowId = keyCopy.u.i
                Else
                    targetRowId = sqlite3RealToI64(keyCopy.u.r)
                    Dim integerFloatOrder As SQLITE_C_INT = _
                        sqlite3IntFloatCompare(targetRowId, keyCopy.u.r)
                    If integerFloatOrder > 0 Then
                        If effectiveOpcode = OP_SeekGT Then effectiveOpcode = OP_SeekGE
                        If effectiveOpcode = OP_SeekLE Then effectiveOpcode = OP_SeekLT
                    ElseIf integerFloatOrder < 0 Then
                        If effectiveOpcode = OP_SeekLT Then effectiveOpcode = OP_SeekLE
                        If effectiveOpcode = OP_SeekGE Then effectiveOpcode = OP_SeekGT
                    End If
                End If

                rc = sqlite3BtreeTableMoveto( _
                    pCursor->uc.pCursor, targetRowId, 0, @seekResult)
                If rc = SQLITE_OK Then
                    pCursor->movetoTarget = targetRowId
                    If effectiveOpcode >= OP_SeekGE Then
                        If seekResult < 0 OrElse _
                           (seekResult = 0 AndAlso effectiveOpcode = OP_SeekGT) Then
                            rc = sqlite3BtreeNext(pCursor->uc.pCursor, 0)
                            If rc = SQLITE_DONE Then
                                rc = SQLITE_OK
                                seekResult = 1
                            ElseIf rc = SQLITE_OK Then
                                seekResult = 0
                            End If
                        Else
                            seekResult = 0
                        End If
                    Else
                        If seekResult > 0 OrElse _
                           (seekResult = 0 AndAlso effectiveOpcode = OP_SeekLT) Then
                            rc = sqlite3BtreePrevious(pCursor->uc.pCursor, 0)
                            If rc = SQLITE_DONE Then
                                rc = SQLITE_OK
                                seekResult = 1
                            ElseIf rc = SQLITE_OK Then
                                seekResult = 0
                            End If
                        Else
                            seekResult = sqlite3BtreeEof(pCursor->uc.pCursor)
                        End If
                    End If
                    If rc = SQLITE_OK Then
                        pCursor->nullRow = CByte(IIf(seekResult <> 0, 1, 0))
                        pCursor->deferredMoveto = 0
                        pCursor->cacheStatus = CACHE_STALE
                        pCursor->seekResult = seekResult
                        If seekResult <> 0 Then nextCounter = pOp->p2
                    End If
                End If
            End If
            sqlite3VdbeMemRelease(@keyCopy)
            If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
            End If
#ifdef SQLITE_TEST
            If shouldCountSearch <> 0 Then sqlite3_search_count += 1
#endif

        Case OP_SorterNext
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 > pVdbe->nOp OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pCursor->eCurType <> CURTYPE_SORTER Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim rc As SQLITE_C_INT = sqlite3VdbeSorterNext(pVdbe->db, pCursor)
            pCursor->cacheStatus = CACHE_STALE
            If rc = SQLITE_OK Then
                pCursor->nullRow = 0
                If pOp->p5 > 0 AndAlso pOp->p5 < 9 Then _
                    pVdbe->aCounter(pOp->p5) += 1
#ifdef SQLITE_TEST
                sqlite3_search_count += 1
#endif
                nextCounter = pOp->p2
            ElseIf rc = SQLITE_DONE Then
                pCursor->nullRow = 1
            Else
                Return sqlite3VdbeExecError(pVdbe, rc)
            End If

        Case OP_ResetSorter
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pCursor->eCurType = CURTYPE_SORTER Then
                sqlite3VdbeSorterReset(pVdbe->db, pCursor->uc.pSorter)
            ElseIf pCursor->eCurType = CURTYPE_BTREE AndAlso _
                   (pCursor->cursorFlags And VDBE_CURSOR_EPHEMERAL) <> 0 AndAlso _
                   pCursor->uc.pCursor <> 0 Then
                Dim clearCode As SQLITE_C_INT = _
                    sqlite3BtreeClearTableOfCursor(pCursor->uc.pCursor)
                If clearCode <> SQLITE_OK Then _
                    Return sqlite3VdbeExecError(pVdbe, clearCode)
            Else
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            End If
            ' OP_SequenceTest tracks the cursor lifetime, not its current rows.
            pCursor->nullRow = 1
            pCursor->cacheStatus = CACHE_STALE

        Case OP_RowSetAdd
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pRowSetMem As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p1]
            Dim pRowIdMem As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p2]
            If (pRowIdMem->flags And MEM_INT) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pRowSetMem->flags And MEM_BLOB) <> 0 Then
                If vdbeExecMemIsRowSet(pRowSetMem) = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Else
                Dim rowSetCode As SQLITE_C_INT = _
                    sqlite3VdbeMemSetRowSet(pRowSetMem)
                If rowSetCode <> SQLITE_OK Then _
                    Return sqlite3VdbeExecError(pVdbe, rowSetCode)
            End If
            sqlite3RowSetInsert(pRowSetMem->z, pRowIdMem->u.i)
            If pVdbe->db->mallocFailed <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_NOMEM)

        Case OP_RowSetRead
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 < 0 OrElse pOp->p2 >= pVdbe->nOp OrElse _
               pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pRowSetMem As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p1]
            Dim nextRowId As sqlite3_int64 = 0
            Dim hasNextRow As SQLITE_C_INT = 0
            If (pRowSetMem->flags And MEM_BLOB) <> 0 Then
                If vdbeExecMemIsRowSet(pRowSetMem) = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                hasNextRow = sqlite3RowSetNext(pRowSetMem->z, @nextRowId)
            End If
            If hasNextRow = 0 Then
                sqlite3VdbeMemSetNull(pRowSetMem)
                nextCounter = pOp->p2
            Else
                sqlite3VdbeMemSetInt64(@pVdbe->aMem[pOp->p3], nextRowId)
            End If

        Case OP_RowSetTest
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 < 0 OrElse pOp->p2 >= pVdbe->nOp OrElse _
               pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem OrElse _
               pOp->p4type <> P4_INT32 OrElse pOp->p4.i < -1 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pRowSetMem As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p1]
            Dim pRowIdMem As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p3]
            If (pRowIdMem->flags And MEM_INT) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pRowSetMem->flags And MEM_BLOB) <> 0 Then
                If vdbeExecMemIsRowSet(pRowSetMem) = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Else
                Dim rowSetCode As SQLITE_C_INT = _
                    sqlite3VdbeMemSetRowSet(pRowSetMem)
                If rowSetCode <> SQLITE_OK Then _
                    Return sqlite3VdbeExecError(pVdbe, rowSetCode)
            End If
            If pOp->p4.i <> 0 Then
                If sqlite3RowSetTest( _
                    pRowSetMem->z, pOp->p4.i, pRowIdMem->u.i) <> 0 Then _
                    nextCounter = pOp->p2
            End If
            If pOp->p4.i >= 0 Then
                sqlite3RowSetInsert(pRowSetMem->z, pRowIdMem->u.i)
                If pVdbe->db->mallocFailed <> 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_NOMEM)
            End If

        Case OP_FilterAdd, OP_Filter
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p3 <= 0 OrElse pOp->p4type <> P4_INT32 OrElse _
               pOp->p4.i <= 0 OrElse pOp->p3 > pVdbe->nMem - pOp->p4.i Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pOp->opcode = OP_Filter AndAlso _
               (pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nOp) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pBloomFilter As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p1]
            If (pBloomFilter->flags And MEM_BLOB) = 0 OrElse _
               pBloomFilter->n <= 0 OrElse pBloomFilter->z = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim filterBitCount As sqlite3_uint64 = _
                CULngInt(pBloomFilter->n) * 8ULL
            If filterBitCount = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim filterHashValue As sqlite3_uint64 = _
                sqlite3VdbeFilterHash(pVdbe->aMem, pOp) Mod filterBitCount
            Dim filterByteIndex As LongInt = CLngInt(filterHashValue Shr 3)
            Dim filterBitMask As UByte = _
                CByte(1 Shl CInt(filterHashValue And 7ULL))
            If pOp->opcode = OP_FilterAdd Then
                pBloomFilter->z[filterByteIndex] Or= filterBitMask
            ElseIf (pBloomFilter->z[filterByteIndex] And filterBitMask) = 0 Then
                pVdbe->aCounter(SQLITE_STMTSTATUS_FILTER_HIT) += 1
                nextCounter = pOp->p2
            Else
                pVdbe->aCounter(SQLITE_STMTSTATUS_FILTER_MISS) += 1
            End If

        Case OP_Next
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 > pVdbe->nOp OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pCursor->eCurType <> CURTYPE_BTREE OrElse _
               pCursor->deferredMoveto <> 0 OrElse pCursor->uc.pCursor = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim rc As SQLITE_C_INT = sqlite3BtreeNext(pCursor->uc.pCursor, pOp->p3)
            pCursor->cacheStatus = CACHE_STALE
            If rc = SQLITE_OK Then
                pCursor->nullRow = 0
                If pOp->p5 > 0 AndAlso pOp->p5 < 9 Then _
                    pVdbe->aCounter(pOp->p5) += 1
#ifdef SQLITE_TEST
                sqlite3_search_count += 1
#endif
                nextCounter = pOp->p2
            ElseIf rc = SQLITE_DONE Then
                pCursor->nullRow = 1
            Else
                Return sqlite3VdbeExecError(pVdbe, rc)
            End If

        Case OP_Prev
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 > pVdbe->nOp OrElse _
               pOp->p3 < 0 OrElse pOp->p3 > 1 OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pCursor->eCurType <> CURTYPE_BTREE OrElse _
               pCursor->deferredMoveto <> 0 OrElse pCursor->uc.pCursor = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim rc As SQLITE_C_INT = sqlite3BtreePrevious(pCursor->uc.pCursor, pOp->p3)
            pCursor->cacheStatus = CACHE_STALE
            If rc = SQLITE_OK Then
                pCursor->nullRow = 0
                If pOp->p5 > 0 AndAlso pOp->p5 < 9 Then _
                    pVdbe->aCounter(pOp->p5) += 1
#ifdef SQLITE_TEST
                sqlite3_search_count += 1
#endif
                nextCounter = pOp->p2
            ElseIf rc = SQLITE_DONE Then
                pCursor->nullRow = 1
            Else
                Return sqlite3VdbeExecError(pVdbe, rc)
            End If

#ifndef SQLITE_OMIT_VIRTUALTABLE
        Case OP_VFilter
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 < 0 OrElse pOp->p2 > pVdbe->nOp OrElse _
               pOp->p3 <= 0 OrElse pOp->p3 + 1 >= pVdbe->nMem OrElse _
               (pOp->p4type <> P4_NOTUSED AndAlso _
                pOp->p4type <> P4_STATIC AndAlso _
                pOp->p4type <> P4_DYNAMIC) OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pVfilterCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pVfilterCursor->eCurType <> CURTYPE_VTAB OrElse _
               pVfilterCursor->uc.pVtabCursor = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pVtabCursor As SqliteVtabCursor Ptr = _
                CPtr(SqliteVtabCursor Ptr, pVfilterCursor->uc.pVtabCursor)
            If pVtabCursor->pVtab = 0 OrElse _
               pVtabCursor->pVtab->pModule = 0 OrElse _
               pVtabCursor->pVtab->pModule->xFilter = 0 OrElse _
               pVtabCursor->pVtab->pModule->xEof = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)

            Dim pQueryPlan As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p3]
            Dim pArgumentCount As SqliteVdbeMem Ptr = _
                @pVdbe->aMem[pOp->p3 + 1]
            If (pQueryPlan->flags And MEM_INT) = 0 OrElse _
               (pArgumentCount->flags And MEM_INT) = 0 OrElse _
               pArgumentCount->u.i < 0 OrElse _
               pArgumentCount->u.i > pVdbe->nArg OrElse _
               pArgumentCount->u.i > pVdbe->nMem - pOp->p3 - 2 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim filterArgumentCount As SQLITE_C_INT = _
                CInt(pArgumentCount->u.i)
            If filterArgumentCount > 0 AndAlso pVdbe->apArg = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            For iArgument As SQLITE_C_INT = 0 To filterArgumentCount - 1
                pVdbe->apArg[iArgument] = _
                    @pVdbe->aMem[pOp->p3 + 2 + iArgument]
            Next
            Dim xFilter As SqliteVdbeVtabFilterProc = CPtr( _
                SqliteVdbeVtabFilterProc, pVtabCursor->pVtab->pModule->xFilter)
            Dim filterCode As SQLITE_C_INT = xFilter( _
                pVtabCursor, CInt(pQueryPlan->u.i), pOp->p4.z, _
                filterArgumentCount, pVdbe->apArg)
            sqlite3VtabImportErrmsg(pVdbe, pVtabCursor->pVtab)
            If filterCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, filterCode)
            Dim xEof As SqliteVdbeVtabEofProc = CPtr( _
                SqliteVdbeVtabEofProc, pVtabCursor->pVtab->pModule->xEof)
            Dim filterIsEmpty As SQLITE_C_INT = xEof(pVtabCursor)
            pVfilterCursor->nullRow = 0
            If filterIsEmpty <> 0 Then nextCounter = pOp->p2

        Case OP_VNext
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 < 0 OrElse pOp->p2 > pVdbe->nOp OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pVnextCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pVnextCursor->nullRow <> 0 Then Exit Select
            If pVnextCursor->eCurType <> CURTYPE_VTAB OrElse _
               pVnextCursor->uc.pVtabCursor = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pVnext As SqliteVtabCursor Ptr = _
                CPtr(SqliteVtabCursor Ptr, pVnextCursor->uc.pVtabCursor)
            If pVnext->pVtab = 0 OrElse pVnext->pVtab->pModule = 0 OrElse _
               pVnext->pVtab->pModule->xNext = 0 OrElse _
               pVnext->pVtab->pModule->xEof = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim xNext As SqliteVdbeVtabNextProc = CPtr( _
                SqliteVdbeVtabNextProc, pVnext->pVtab->pModule->xNext)
            Dim nextCode As SQLITE_C_INT = xNext(pVnext)
            sqlite3VtabImportErrmsg(pVdbe, pVnext->pVtab)
            If nextCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, nextCode)
            Dim xVtabEof As SqliteVdbeVtabEofProc = CPtr( _
                SqliteVdbeVtabEofProc, pVnext->pVtab->pModule->xEof)
            If xVtabEof(pVnext) = 0 Then nextCounter = pOp->p2

        Case OP_VInitIn
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem OrElse _
               pOp->p2 = pOp->p3 OrElse pVdbe->apCsr = 0 OrElse _
               pVdbe->apCsr[pOp->p1] = 0 OrElse pVdbe->aMem = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pValueListCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pValueListCursor->eCurType <> CURTYPE_BTREE OrElse _
               pValueListCursor->uc.pCursor = 0 OrElse _
               (pVdbe->aMem[pOp->p2].flags And MEM_AGG) <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pValueList As SqliteValueList Ptr = CPtr( _
                SqliteValueList Ptr, sqlite3Malloc(SizeOf(SqliteValueList)))
            If pValueList = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_NOMEM)
            pValueList->pCsr = pValueListCursor->uc.pCursor
            pValueList->pOut = @pVdbe->aMem[pOp->p3]
            sqlite3VdbeMemSetPointer( _
                @pVdbe->aMem[pOp->p2], pValueList, StrPtr("ValueList"), _
                @sqlite3VdbeValueListFree)

        Case OP_VCheck
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->db->nDb OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pOp->p4type <> P4_TABLEREF OrElse pOp->p4.p = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCheckedTable As SqliteTable Ptr = _
                CPtr(SqliteTable Ptr, pOp->p4.p)
            sqlite3VdbeMemSetNull(@pVdbe->aMem[pOp->p2])
            If pCheckedTable->nTabRef = 0 OrElse _
               pCheckedTable->eTabType <> TABTYP_VTAB OrElse _
               pCheckedTable->zName = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCheckedVtable As SqliteVTable Ptr = pCheckedTable->u.vtab.p
            If pCheckedVtable <> 0 Then
                If pCheckedVtable->pVtab = 0 OrElse _
                   pCheckedVtable->pVtab->pModule = 0 OrElse _
                   pCheckedVtable->pVtab->pModule->iVersion < 4 OrElse _
                   pCheckedVtable->pVtab->pModule->xIntegrity = 0 OrElse _
                   pVdbe->db->aDb(pOp->p1).zDbSName = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                Dim zIntegrityError As ZString Ptr = 0
                sqlite3VtabLock(pCheckedVtable)
                Dim xIntegrity As SqliteVdbeVtabIntegrityProc = CPtr( _
                    SqliteVdbeVtabIntegrityProc, _
                    pCheckedVtable->pVtab->pModule->xIntegrity)
                Dim integrityCode As SQLITE_C_INT = xIntegrity( _
                    pCheckedVtable->pVtab, pVdbe->db->aDb(pOp->p1).zDbSName, _
                    pCheckedTable->zName, pOp->p3, @zIntegrityError)
                sqlite3VtabUnlock(pCheckedVtable)
                If integrityCode <> SQLITE_OK Then
                    If zIntegrityError <> 0 Then _
                        sqlite3VdbeExecFree(zIntegrityError)
                    Return sqlite3VdbeExecError(pVdbe, integrityCode)
                End If
                If zIntegrityError <> 0 Then
                    Dim integrityTextCode As SQLITE_C_INT = sqlite3VdbeMemSetStr( _
                        @pVdbe->aMem[pOp->p2], zIntegrityError, -1, _
                        SQLITE_UTF8, @sqlite3VdbeExecFree)
                    If integrityTextCode <> SQLITE_OK Then _
                        Return sqlite3VdbeExecError(pVdbe, integrityTextCode)
                    Dim integrityEncodingCode As SQLITE_C_INT = _
                        sqlite3VdbeChangeEncoding( _
                            @pVdbe->aMem[pOp->p2], pVdbe->db->enc)
                    If integrityEncodingCode <> SQLITE_OK Then _
                        Return sqlite3VdbeExecError(pVdbe, integrityEncodingCode)
                End If
            End If
#endif

        Case OP_Rowid
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pCursor->nullRow <> 0 Then
                sqlite3VdbeMemSetNull(@pVdbe->aMem[pOp->p2])
            ElseIf pCursor->deferredMoveto <> 0 Then
                If pCursor->eCurType <> CURTYPE_BTREE OrElse _
                   pCursor->isTable = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                sqlite3VdbeMemSetInt64( _
                    @pVdbe->aMem[pOp->p2], pCursor->movetoTarget)
#ifndef SQLITE_OMIT_VIRTUALTABLE
            ElseIf pCursor->eCurType = CURTYPE_VTAB Then
                If pCursor->uc.pVtabCursor = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                Dim pVrowCursor As SqliteVtabCursor Ptr = _
                    CPtr(SqliteVtabCursor Ptr, pCursor->uc.pVtabCursor)
                If pVrowCursor->pVtab = 0 OrElse _
                   pVrowCursor->pVtab->pModule = 0 OrElse _
                   pVrowCursor->pVtab->pModule->xRowid = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                Dim rowId As sqlite3_int64 = 0
                Dim xRowid As SqliteVdbeVtabRowidProc = CPtr( _
                    SqliteVdbeVtabRowidProc, pVrowCursor->pVtab->pModule->xRowid)
                Dim rowidCode As SQLITE_C_INT = xRowid(pVrowCursor, @rowId)
                sqlite3VtabImportErrmsg(pVdbe, pVrowCursor->pVtab)
                If rowidCode <> SQLITE_OK Then _
                    Return sqlite3VdbeExecError(pVdbe, rowidCode)
                sqlite3VdbeMemSetInt64(@pVdbe->aMem[pOp->p2], rowId)
#endif
            Else
                If pCursor->eCurType <> CURTYPE_BTREE OrElse pCursor->isTable = 0 OrElse _
                   pCursor->uc.pCursor = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                Dim restoreResult As SQLITE_C_INT = 0
                Dim rc As SQLITE_C_INT = sqlite3BtreeCursorRestore( _
                    pCursor->uc.pCursor, @restoreResult)
                If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
                If sqlite3BtreeEof(pCursor->uc.pCursor) <> 0 Then
                    sqlite3VdbeMemSetNull(@pVdbe->aMem[pOp->p2])
                Else
                    sqlite3VdbeMemSetInt64(@pVdbe->aMem[pOp->p2], _
                        sqlite3BtreeIntegerKey(pCursor->uc.pCursor))
                End If
            End If

        Case OP_RowData
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               (pOp->p3 <> 0 AndAlso pOp->p3 <> 1) OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pCursor->eCurType <> CURTYPE_BTREE OrElse _
               pCursor->nullRow <> 0 OrElse pCursor->deferredMoveto <> 0 OrElse _
               pCursor->uc.pCursor = 0 OrElse _
               sqlite3BtreeCursorIsValidNN(pCursor->uc.pCursor) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim payloadSize As u32 = sqlite3BtreePayloadSize(pCursor->uc.pCursor)
            If CULngInt(payloadSize) > CULngInt(pVdbe->db->lengthLimit) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_TOOBIG)
            Dim pOutput As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p2]
            sqlite3VdbeMemSetNull(pOutput)
            Dim rowDataCode As SQLITE_C_INT = sqlite3VdbeMemFromBtreeZeroOffset( _
                pCursor->uc.pCursor, payloadSize, pOutput)
            If rowDataCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, rowDataCode)
            If pOp->p3 = 0 Then
                rowDataCode = sqlite3VdbeMemMakeWriteable(pOutput)
                If rowDataCode <> SQLITE_OK Then _
                    Return sqlite3VdbeExecError(pVdbe, rowDataCode)
            End If

        Case OP_NewRowid
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pCursor->eCurType <> CURTYPE_BTREE OrElse pCursor->isTable = 0 OrElse _
               pCursor->uc.pCursor = 0 Then Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
#ifdef SQLITE_32BIT_ROWID
            Dim maximumRowId As sqlite3_int64 = &H7FFFFFFF
#else
            Dim maximumRowId As sqlite3_int64 = 9223372036854775807LL
#endif
            Dim rowId As sqlite3_int64 = 0
            Dim isEmpty As SQLITE_C_INT = 0
            Dim rc As SQLITE_C_INT = SQLITE_OK
            If (pCursor->cursorFlags And VDBE_CURSOR_RANDOM_ROWID) = 0 Then
                rc = sqlite3BtreeLast(pCursor->uc.pCursor, @isEmpty)
                If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
                If isEmpty <> 0 Then
                    rowId = 1
                Else
                    rowId = sqlite3BtreeIntegerKey(pCursor->uc.pCursor)
                    If rowId >= maximumRowId Then
                        pCursor->cursorFlags Or= VDBE_CURSOR_RANDOM_ROWID
                    Else
                        rowId += 1
                    End If
                End If
            End If

            If pOp->p3 <> 0 Then
                If pOp->p3 < 0 OrElse pOp->p3 >= pVdbe->nMem OrElse _
                   (pCursor->cursorFlags And VDBE_CURSOR_RANDOM_ROWID) <> 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_FULL)
                Dim pSequence As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p3]
                If sqlite3VdbeMemIntegerify(pSequence) <> SQLITE_OK Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                If pSequence->u.i = maximumRowId Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_FULL)
                If rowId < pSequence->u.i + 1 Then rowId = pSequence->u.i + 1
                pSequence->u.i = rowId
            End If

            If (pCursor->cursorFlags And VDBE_CURSOR_RANDOM_ROWID) <> 0 Then
                If pOp->p3 <> 0 Then Return sqlite3VdbeExecError(pVdbe, SQLITE_FULL)
                Dim foundUnused As SQLITE_C_INT = 0
                For attempt As SQLITE_C_INT = 0 To 99
                    Dim randomValue As sqlite3_int64 = 0
                    sqlite3VdbeExecRandomness(SizeOf(randomValue), @randomValue)
                    Dim rowIdBits As ULongInt = _
                        CULngInt(randomValue) And (CULngInt(maximumRowId) Shr 1)
                    rowId = CULngInt(rowIdBits + 1)
                    Dim seekResult As SQLITE_C_INT = 0
                    rc = sqlite3BtreeTableMoveto( _
                        pCursor->uc.pCursor, rowId, 0, @seekResult)
                    If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
                    If seekResult <> 0 Then
                        foundUnused = 1
                        Exit For
                    End If
                Next
                If foundUnused = 0 Then Return sqlite3VdbeExecError(pVdbe, SQLITE_FULL)
            End If

            pCursor->deferredMoveto = 0
            pCursor->cacheStatus = CACHE_STALE
            sqlite3VdbeMemSetInt64(@pVdbe->aMem[pOp->p2], rowId)

#ifndef SQLITE_OMIT_VIRTUALTABLE
        Case OP_VUpdate
            If pOp->p1 < 0 OrElse pOp->p1 > 1 OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 > pVdbe->nArg OrElse _
               pOp->p3 <= 0 OrElse pOp->p3 > pVdbe->nMem - pOp->p2 OrElse _
               pOp->p4type <> P4_VTAB OrElse pOp->p4.p = 0 OrElse _
               pVdbe->apArg = 0 OrElse _
               (pOp->p2 <> 1 AndAlso _
                pOp->p5 <> OE_FAIL AndAlso pOp->p5 <> OE_ROLLBACK AndAlso _
                pOp->p5 <> OE_ABORT AndAlso pOp->p5 <> OE_IGNORE AndAlso _
                pOp->p5 <> OE_REPLACE) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pVdbe->vdbeFlags And VDBE_READONLY_MASK) <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_READONLY)
            If pVdbe->db->mallocFailed <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_NOMEM)

            Dim pUpdateTable As SqliteVTable Ptr = _
                CPtr(SqliteVTable Ptr, pOp->p4.p)
            ' A nested DROP may disconnect this table while the outer VDBE
            ' still retains its VTable wrapper. SQLite reports this as locked.
            If pUpdateTable->pVtab = 0 OrElse _
               pUpdateTable->pVtab->pModule = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_LOCKED)
            If pUpdateTable->pVtab->pModule->xUpdate = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_READONLY)

#ifdef SQLITE_DEBUG
            sqlite3VdbeIncrWriteCounter(pVdbe, 0)
#endif
            For iArgument As SQLITE_C_INT = 0 To pOp->p2 - 1
                pVdbe->apArg[iArgument] = @pVdbe->aMem[pOp->p3 + iArgument]
            Next
            Dim previousConflictMode As u8 = pVdbe->db->vtabOnConflict
            pVdbe->db->vtabOnConflict = CByte(pOp->p5)
            Dim newRowid As sqlite3_int64 = 0
            Dim xUpdate As SqliteVdbeVtabUpdateProc = CPtr( _
                SqliteVdbeVtabUpdateProc, pUpdateTable->pVtab->pModule->xUpdate)
            Dim updateCode As SQLITE_C_INT = xUpdate( _
                pUpdateTable->pVtab, pOp->p2, pVdbe->apArg, @newRowid)
            pVdbe->db->vtabOnConflict = previousConflictMode
            sqlite3VtabImportErrmsg(pVdbe, pUpdateTable->pVtab)
            If updateCode = SQLITE_OK AndAlso pOp->p1 <> 0 Then
                If pOp->p2 <= 1 OrElse _
                   (pVdbe->aMem[pOp->p3].flags And MEM_NULL) = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                pVdbe->db->lastRowid = newRowid
            End If
            If (updateCode And &HFF) = SQLITE_CONSTRAINT AndAlso _
               pUpdateTable->bConstraint <> 0 Then
                If pOp->p5 = OE_IGNORE Then
                    updateCode = SQLITE_OK
                ElseIf pOp->p5 = OE_REPLACE Then
                    pVdbe->errorAction = OE_ABORT
                Else
                    pVdbe->errorAction = CByte(pOp->p5)
                End If
            Else
                pVdbe->nChange += 1
            End If
            If updateCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, updateCode)
#endif

        Case OP_RowCell
            If programCounter < 0 OrElse programCounter >= pVdbe->nOp - 1 OrElse _
               pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 < 0 OrElse pOp->p2 >= pVdbe->nCursor OrElse _
               pOp->p1 = pOp->p2 OrElse pOp->p3 < 0 OrElse _
               pOp->p3 >= pVdbe->nMem OrElse pOp->p4type <> P4_NOTUSED OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 OrElse _
               pVdbe->apCsr[pOp->p2] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pRowCellInsert As SqliteVdbeOp Ptr = _
                @pVdbe->aOp[programCounter + 1]
            If (pRowCellInsert->p5 And OPFLAG_PREFORMAT) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pRowCellInsert->opcode = OP_Insert AndAlso pOp->p3 <= 0) OrElse _
               (pRowCellInsert->opcode = OP_IdxInsert AndAlso pOp->p3 <> 0) OrElse _
               (pRowCellInsert->opcode <> OP_Insert AndAlso _
                pRowCellInsert->opcode <> OP_IdxInsert) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pRowCellDestination As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            Dim pRowCellSource As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p2])
            If pRowCellDestination->eCurType <> CURTYPE_BTREE OrElse _
               pRowCellSource->eCurType <> CURTYPE_BTREE OrElse _
               pRowCellDestination->uc.pCursor = 0 OrElse _
               pRowCellSource->uc.pCursor = 0 OrElse _
               pRowCellDestination->isTable <> pRowCellSource->isTable OrElse _
               (pRowCellInsert->opcode = OP_Insert AndAlso _
                pRowCellDestination->isTable = 0) OrElse _
               (pRowCellInsert->opcode = OP_IdxInsert AndAlso _
                pRowCellDestination->isTable <> 0) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pOp->p3 <> 0 AndAlso _
               (pVdbe->aMem[pOp->p3].flags And MEM_INT) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim rowCellKey As sqlite3_int64 = 0
            If pOp->p3 <> 0 Then rowCellKey = pVdbe->aMem[pOp->p3].u.i
            Dim rowCellCode As SQLITE_C_INT = sqlite3BtreeTransferRow( _
                pRowCellDestination->uc.pCursor, _
                pRowCellSource->uc.pCursor, rowCellKey)
            If rowCellCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, rowCellCode)

        Case OP_Insert
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            Dim pData As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p2]
            Dim pKey As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p3]
            If pCursor->eCurType <> CURTYPE_BTREE OrElse _
               pCursor->uc.pCursor = 0 OrElse (pKey->flags And MEM_INT) = 0 OrElse _
               ((pData->flags And (MEM_BLOB Or MEM_STR)) = 0 AndAlso pData->n <> 0) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pCursor->isTable = 0 Then
                If (pOp->p5 And OPFLAG_ISNOOP) = 0 OrElse _
                   pOp->p4type <> P4_TABLE OrElse pOp->p4.p = 0 OrElse _
                   (CPtr(SqliteVdbeHookTable Ptr, pOp->p4.p)->tabFlags And _
                    TF_WithoutRowid) = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            End If
            Dim pHookTable As SqliteVdbeHookTable Ptr = 0
            Dim zHookDatabase As Const ZString Ptr = 0
            Dim hookContextCode As SQLITE_C_INT = _
                vdbeUpdateHookContext(pVdbe, pCursor, pOp, pHookTable, zHookDatabase)
            If hookContextCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, hookContextCode)
            Dim nZero As SQLITE_C_INT = 0
            If (pData->flags And MEM_ZERO) <> 0 Then nZero = pData->u.nZero
            If pData->n < 0 OrElse nZero < 0 OrElse _
               CULngInt(pData->n) + CULngInt(nZero) > _
                   CULngInt(pVdbe->db->lengthLimit) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_TOOBIG)

            Dim payload As SqliteBtreePayload
            payload.pKey = 0
            payload.nKey = pKey->u.i
            payload.pData = pData->z
            payload.aMem = 0
            payload.nMem = 0
            payload.nData = pData->n
            payload.nZero = 0
            payload.nZero = nZero

#ifdef SQLITE_ENABLE_PREUPDATE_HOOK
            If pHookTable <> 0 Then
                If pVdbe->db->xPreUpdateCallback <> 0 AndAlso _
                   (pOp->p5 And OPFLAG_ISUPDATE) = 0 Then
                    sqlite3VdbePreUpdateHook( _
                        pVdbe, pCursor, SQLITE_INSERT, zHookDatabase, pHookTable, _
                        pKey->u.i, pOp->p2, -1)
                End If
                If pVdbe->db->xUpdateCallback = 0 OrElse _
                   pHookTable->aCol = 0 Then pHookTable = 0
            End If
            If (pOp->p5 And OPFLAG_ISNOOP) <> 0 Then Exit Select
#endif

            If (pOp->p5 And OPFLAG_NCHANGE) <> 0 Then
                pVdbe->nChange += 1
                pVdbe->vdbeFlags Or= VDBE_CHANGECOUNT_MASK
                If (pOp->p5 And OPFLAG_LASTROWID) <> 0 Then _
                    pVdbe->db->lastRowid = pKey->u.i
            End If
            Dim seekResult As SQLITE_C_INT = 0
            If (pOp->p5 And OPFLAG_USESEEKRESULT) <> 0 Then seekResult = pCursor->seekResult
            Dim insertRc As SQLITE_C_INT = sqlite3BtreeInsert(pCursor->uc.pCursor, @payload, _
                pOp->p5 And (OPFLAG_APPEND Or OPFLAG_SAVEPOSITION Or OPFLAG_PREFORMAT), _
                seekResult)
            If insertRc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, insertRc)
            pCursor->deferredMoveto = 0
            pCursor->cacheStatus = CACHE_STALE
            pCursor->seekResult = 0
            If pHookTable <> 0 Then
                Dim operation As SQLITE_C_INT = SQLITE_INSERT
                If (pOp->p5 And OPFLAG_ISUPDATE) <> 0 Then operation = SQLITE_UPDATE
                vdbeInvokeUpdateHook(pVdbe->db, pHookTable, zHookDatabase, _
                                     operation, pKey->u.i)
            End If

        Case OP_Delete
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pCursor->eCurType <> CURTYPE_BTREE OrElse _
               pCursor->uc.pCursor = 0 OrElse pCursor->deferredMoveto <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pHookTable As SqliteVdbeHookTable Ptr = 0
            Dim zHookDatabase As Const ZString Ptr = 0
            Dim hookContextCode As SQLITE_C_INT = _
                vdbeUpdateHookContext(pVdbe, pCursor, pOp, pHookTable, zHookDatabase)
            If hookContextCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, hookContextCode)
            If pCursor->isTable <> 0 AndAlso pHookTable <> 0 AndAlso _
               (pOp->p5 And OPFLAG_SAVEPOSITION) <> 0 Then _
                pCursor->movetoTarget = sqlite3BtreeIntegerKey(pCursor->uc.pCursor)
#ifdef SQLITE_ENABLE_PREUPDATE_HOOK
            If pHookTable <> 0 Then
                If pVdbe->db->xPreUpdateCallback <> 0 Then
                    Dim preupdateOperation As SQLITE_C_INT = SQLITE_DELETE
                    If (pOp->p2 And OPFLAG_ISUPDATE) <> 0 Then
                        preupdateOperation = SQLITE_UPDATE
                    End If
                    sqlite3VdbePreUpdateHook( _
                        pVdbe, pCursor, preupdateOperation, zHookDatabase, _
                        pHookTable, pCursor->movetoTarget, pOp->p3, -1)
                End If
                If pVdbe->db->xUpdateCallback = 0 OrElse _
                   pHookTable->aCol = 0 Then pHookTable = 0
            End If
            ' OP_Delete keeps hook and no-op flags in P2; P5 is B-tree flags.
            If (pOp->p2 And OPFLAG_ISNOOP) <> 0 Then Exit Select
#endif
            Dim deleteRc As SQLITE_C_INT = sqlite3BtreeDelete(pCursor->uc.pCursor, _
                pOp->p5 And (OPFLAG_SAVEPOSITION Or BTREE_AUXDELETE))
            If deleteRc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, deleteRc)
            If (pOp->p2 And OPFLAG_NCHANGE) <> 0 Then
                pVdbe->nChange += 1
                pVdbe->vdbeFlags Or= VDBE_CHANGECOUNT_MASK
                If pHookTable <> 0 Then _
                    vdbeInvokeUpdateHook(pVdbe->db, pHookTable, zHookDatabase, _
                                         SQLITE_DELETE, pCursor->movetoTarget)
            End If
            pCursor->cacheStatus = CACHE_STALE
            pCursor->seekResult = 0

#ifndef SQLITE_OMIT_VIRTUALTABLE
        Case OP_VColumn
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 < 0 OrElse pOp->p3 <= 0 OrElse _
               pOp->p3 >= pVdbe->nMem OrElse _
               (pOp->p5 <> 0 AndAlso pOp->p5 <> OPFLAG_NOCHNG) OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pVcolumnCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            Dim pDestination As SqliteVdbeMem Ptr = _
                @pVdbe->aMem[pOp->p3]
#ifdef SQLITE_DEBUG
            sqlite3VdbeMemAboutToChange(pVdbe, pDestination)
#endif
            If pVcolumnCursor->nullRow <> 0 Then
                sqlite3VdbeMemSetNull(pDestination)
            Else
                If pVcolumnCursor->eCurType <> CURTYPE_VTAB OrElse _
                   pVcolumnCursor->uc.pVtabCursor = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                Dim pVtabCursor As SqliteVtabCursor Ptr = _
                    CPtr(SqliteVtabCursor Ptr, pVcolumnCursor->uc.pVtabCursor)
                If pVtabCursor->pVtab = 0 OrElse _
                   pVtabCursor->pVtab->pModule = 0 OrElse _
                   pVtabCursor->pVtab->pModule->xColumn = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)

                Dim nullFunction As SqliteFuncDef = Type<SqliteFuncDef>(0)
                nullFunction.funcFlags = SQLITE_RESULT_SUBTYPE
                Dim columnContext As SqliteResultContext
                columnContext.pOut = pDestination
                columnContext.pFunc = @nullFunction
                columnContext.pMem = 0
                columnContext.pVdbe = pVdbe
                columnContext.iOp = programCounter
                columnContext.isError = 0
                columnContext.enc = pVdbe->db->enc
                columnContext.skipFlag = 0
                columnContext.argc = 0
                columnContext.argv(0) = 0
                sqlite3VdbeMemSetNull(pDestination)
                If (pOp->p5 And OPFLAG_NOCHNG) <> 0 Then
                    pDestination->flags = MEM_NULL Or MEM_ZERO
                    pDestination->u.nZero = 0
                End If

                Dim xColumn As SqliteVdbeVtabColumnProc = CPtr( _
                    SqliteVdbeVtabColumnProc, pVtabCursor->pVtab->pModule->xColumn)
                Dim columnCode As SQLITE_C_INT = _
                    xColumn(pVtabCursor, @columnContext, pOp->p2)
                sqlite3VtabImportErrmsg(pVdbe, pVtabCursor->pVtab)
                If columnContext.isError > 0 Then
                    Dim zColumnError As Const UByte Ptr = _
                        sqlite3ValueText(pDestination, SQLITE_UTF8)
                    If zColumnError <> 0 Then _
                        sqlite3VdbeError( _
                            pVdbe, StrPtr(!"%s"), zColumnError)
                    columnCode = columnContext.isError
                End If
                If columnCode <> SQLITE_OK Then _
                    Return sqlite3VdbeExecError(pVdbe, columnCode)
                Dim encodingCode As SQLITE_C_INT = sqlite3VdbeChangeEncoding( _
                    pDestination, pVdbe->db->enc)
                If encodingCode <> SQLITE_OK Then _
                    Return sqlite3VdbeExecError(pVdbe, encodingCode)
                If pVdbe->db->mallocFailed <> 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_NOMEM)
            End If
#endif

        Case OP_Column
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem OrElse _
               pOp->p2 < 0 OrElse pVdbe->apCsr = 0 OrElse _
               pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pColumnDefault As SqliteVdbeMem Ptr = 0
            If pOp->p4type = P4_MEM Then
                If pOp->p4.p = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                pColumnDefault = CPtr(SqliteVdbeMem Ptr, pOp->p4.p)
            End If
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            Dim rc As SQLITE_C_INT = sqlite3VdbeExecColumn( _
                pVdbe, pCursor, pOp->p2, @pVdbe->aMem[pOp->p3], _
                pOp->p5, pColumnDefault)
            If rc <> SQLITE_OK Then
                If (rc And &HFF) = SQLITE_CORRUPT AndAlso _
                   pVdbe->aOp <> 0 AndAlso pVdbe->nOp > 0 Then
                    Dim corruptTarget As SQLITE_C_INT = pVdbe->aOp[0].p3
                    If corruptTarget > 0 AndAlso corruptTarget < pVdbe->nOp Then
                        ' OP_Init.P3 routes malformed records to the integrity-check result.
                        nextCounter = corruptTarget
                    Else
                        Return sqlite3VdbeExecError(pVdbe, rc)
                    End If
                Else
                    Return sqlite3VdbeExecError(pVdbe, rc)
                End If
            End If

#ifdef SQLITE_ENABLE_OFFSET_SQL_FUNC
        Case OP_Offset
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem OrElse _
               pVdbe->apCsr = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pOffsetCursor As SqliteVdbeCursor Ptr = 0
            If pVdbe->apCsr[pOp->p1] <> 0 Then _
                pOffsetCursor = CPtr( _
                    SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pOffsetCursor = 0 OrElse _
               pOffsetCursor->eCurType <> CURTYPE_BTREE Then
                sqlite3VdbeMemSetNull(@pVdbe->aMem[pOp->p3])
            Else
                If pOffsetCursor->uc.pCursor = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                If pOffsetCursor->deferredMoveto <> 0 Then
                    Dim offsetSeekCode As SQLITE_C_INT = _
                        sqlite3VdbeExecFinishSeek(pOffsetCursor)
                    If offsetSeekCode <> SQLITE_OK Then _
                        Return sqlite3VdbeExecError(pVdbe, offsetSeekCode)
                End If
                If sqlite3BtreeEof(pOffsetCursor->uc.pCursor) <> 0 Then
                    sqlite3VdbeMemSetNull(@pVdbe->aMem[pOp->p3])
                Else
                    sqlite3VdbeMemSetInt64( _
                        @pVdbe->aMem[pOp->p3], _
                        sqlite3BtreeOffset(pOffsetCursor->uc.pCursor))
                End If
            End If
#endif

        Case OP_Affinity
            If pOp->p1 <= 0 OrElse pOp->p2 <= 0 OrElse _
               pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 > pVdbe->nMem - pOp->p1 OrElse _
               (pOp->p4type <> P4_STATIC AndAlso pOp->p4type <> P4_DYNAMIC) OrElse _
               pOp->p4.z = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            For iField As SQLITE_C_INT = 0 To pOp->p2 - 1
                Dim affinity As UByte = CPtr(Const UByte Ptr, pOp->p4.z)[iField]
                If (affinity < SQLITE_AFF_NONE OrElse affinity > SQLITE_AFF_FLEXNUM) AndAlso _
                   affinity <> SQLITE_AFF_DEFER Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                sqlite3ValueApplyAffinity( _
                    @pVdbe->aMem[pOp->p1 + iField], affinity, pVdbe->db->enc)
                If affinity = SQLITE_AFF_REAL AndAlso _
                   (pVdbe->aMem[pOp->p1 + iField].flags And MEM_INT) <> 0 Then
                    Dim rc As SQLITE_C_INT = sqlite3VdbeMemRealify( _
                        @pVdbe->aMem[pOp->p1 + iField])
                    If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
                End If
            Next

        Case OP_TypeCheck
            Dim typeCheckCode As SQLITE_C_INT = _
                sqlite3VdbeExecTypeCheck(pVdbe, pOp)
            If typeCheckCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, typeCheckCode)

        Case OP_RealAffinity
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pVdbe->aMem[pOp->p1].flags And (MEM_INT Or MEM_INTREAL)) <> 0 Then
                Dim rc As SQLITE_C_INT = sqlite3VdbeMemRealify(@pVdbe->aMem[pOp->p1])
                If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
            End If

        Case OP_Cast
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 < SQLITE_AFF_BLOB OrElse pOp->p2 > SQLITE_AFF_REAL Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim castRc As SQLITE_C_INT = sqlite3VdbeMemExpandBlob( _
                @pVdbe->aMem[pOp->p1])
            If castRc = SQLITE_OK Then castRc = sqlite3VdbeMemCast( _
                @pVdbe->aMem[pOp->p1], CByte(pOp->p2), pVdbe->db->enc)
            If castRc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, castRc)

        Case OP_SoftNull
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            pVdbe->aMem[pOp->p1].flags = _
                (pVdbe->aMem[pOp->p1].flags And _
                 Not (MEM_UNDEFINED Or MEM_AFF_MASK)) Or MEM_NULL

        Case OP_ClrSubtype
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            pVdbe->aMem[pOp->p1].flags = _
                pVdbe->aMem[pOp->p1].flags And Not MEM_SUBTYPE

        Case OP_GetSubtype
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pVdbe->aMem[pOp->p1].flags And MEM_SUBTYPE) <> 0 Then
                sqlite3VdbeMemSetInt64( _
                    @pVdbe->aMem[pOp->p2], pVdbe->aMem[pOp->p1].eSubtype)
            Else
                sqlite3VdbeMemSetNull(@pVdbe->aMem[pOp->p2])
            End If

        Case OP_SetSubtype
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pVdbe->aMem[pOp->p1].flags And MEM_NULL) <> 0 Then
                pVdbe->aMem[pOp->p2].flags = _
                    pVdbe->aMem[pOp->p2].flags And Not MEM_SUBTYPE
            ElseIf (pVdbe->aMem[pOp->p1].flags And MEM_INT) <> 0 Then
                pVdbe->aMem[pOp->p2].flags Or= MEM_SUBTYPE
                pVdbe->aMem[pOp->p2].eSubtype = _
                    CByte(CULngInt(pVdbe->aMem[pOp->p1].u.i) And &HFFULL)
            Else
                Return sqlite3VdbeExecError(pVdbe, SQLITE_MISMATCH)
            End If

        Case OP_MakeRecord
            If pOp->p1 <= 0 OrElse pOp->p2 <= 0 OrElse _
               pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 > pVdbe->nMem - pOp->p1 OrElse _
               pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem OrElse _
               (pOp->p3 >= pOp->p1 AndAlso pOp->p3 < pOp->p1 + pOp->p2) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pOp->p4type <> P4_NOTUSED AndAlso _
               pOp->p4type <> P4_STATIC AndAlso pOp->p4type <> P4_DYNAMIC Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pOp->p4.p <> 0 Then
                Dim pAffinity As Const UByte Ptr = CPtr(Const UByte Ptr, pOp->p4.p)
                For iField As SQLITE_C_INT = 0 To pOp->p2 - 1
                    Dim pValue As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p1 + iField]
                    sqlite3ValueApplyAffinity(pValue, pAffinity[iField], pVdbe->db->enc)
                    If pAffinity[iField] = SQLITE_AFF_REAL AndAlso _
                       (pValue->flags And MEM_INT) <> 0 Then
                        pValue->flags = (pValue->flags And Not MEM_INT) Or MEM_INTREAL
                    End If
                Next
            End If
            Dim rc As SQLITE_C_INT = sqlite3VdbeRecordPack( _
                pVdbe->db, @pVdbe->aMem[pOp->p3], @pVdbe->aMem[pOp->p1], _
                pOp->p2, pVdbe->minWriteFileFormat)
            If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)

        Case OP_IfNoHope, OP_Found, OP_NotFound, OP_NoConflict
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 < 0 OrElse pOp->p2 > pVdbe->nOp OrElse _
               pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem OrElse _
               pOp->p4type <> P4_INT32 OrElse pOp->p4.i < 0 OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pCursor->eCurType <> CURTYPE_BTREE OrElse pCursor->isTable <> 0 OrElse _
               pCursor->uc.pCursor = 0 OrElse pCursor->pKeyInfo = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            ' A prior seek already established this prefix, so skip the fallback lookup.
            If pOp->opcode = OP_IfNoHope AndAlso _
               pCursor->seekHit >= pOp->p4.i Then Exit Select
#ifdef SQLITE_TEST
            If pOp->opcode <> OP_NoConflict Then sqlite3_found_count += 1
#endif

            Dim keyFieldCount As SQLITE_C_INT = pOp->p4.i
            Dim pUnpacked As sqlite3VdbeUnpackedRecord
            pUnpacked.pKeyInfo = pCursor->pKeyInfo
            pUnpacked.default_rc = 0
            pUnpacked.errCode = SQLITE_OK
            pUnpacked.r1 = 0
            pUnpacked.r2 = 0
            pUnpacked.eqSeen = 0
            Dim result As SQLITE_C_INT = 0
            Dim anyNull As SQLITE_C_INT = 0
            Dim rc As SQLITE_C_INT

            If keyFieldCount > 0 Then
                If keyFieldCount > pVdbe->nMem - pOp->p3 OrElse _
                   keyFieldCount > CPtr(sqlite3VdbeKeyInfoPrefix Ptr, _
                       pCursor->pKeyInfo)->nAllField Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                pUnpacked.aMem = @pVdbe->aMem[pOp->p3]
                pUnpacked.n = 0
                pUnpacked.nField = CUShort(keyFieldCount)
                For iField As SQLITE_C_INT = 0 To keyFieldCount - 1
                    If (pUnpacked.aMem[iField].flags And MEM_NULL) <> 0 Then anyNull = 1
                Next
                rc = sqlite3BtreeIndexMoveto( _
                    pCursor->uc.pCursor, @pUnpacked, @result)
            Else
                Dim pRecordValue As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p3]
                If (pRecordValue->flags And MEM_BLOB) = 0 OrElse _
                   pRecordValue->n <= 0 OrElse pRecordValue->z = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                If pOp->opcode = OP_NoConflict Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                Dim expandRc As SQLITE_C_INT = sqlite3VdbeMemExpandBlob(pRecordValue)
                If expandRc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, expandRc)
                ' RecordUnpack reserves one extra slot for an implicit rowid.
                Dim fieldCapacity As SQLITE_C_INT = _
                    CInt(CPtr(sqlite3VdbeKeyInfoPrefix Ptr, _
                        pCursor->pKeyInfo)->nKeyField) + 1
                If fieldCapacity <= 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                Dim memoryBytes As sqlite3_uint64 = _
                    CULngInt(fieldCapacity) * SizeOf(SqliteVdbeMem)
                If memoryBytes > SQLITE_MAX_ALLOCATION_SIZE Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_TOOBIG)
                Dim pFields As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, _
                    sqlite3DbMallocZero(pVdbe->db, memoryBytes))
                If pFields = 0 Then Return sqlite3VdbeExecError(pVdbe, SQLITE_NOMEM)
                pUnpacked.aMem = pFields
                pUnpacked.n = 0
                pUnpacked.nField = CUShort(fieldCapacity)
                sqlite3VdbeRecordUnpack(pRecordValue->n, pRecordValue->z, @pUnpacked)
                If pUnpacked.errCode <> SQLITE_OK Then
                    rc = pUnpacked.errCode
                Else
                    For iField As SQLITE_C_INT = 0 To pUnpacked.nField - 1
                        If (pUnpacked.aMem[iField].flags And MEM_NULL) <> 0 Then anyNull = 1
                    Next
                    rc = sqlite3BtreeIndexMoveto( _
                        pCursor->uc.pCursor, @pUnpacked, @result)
                End If
                For iField As SQLITE_C_INT = 0 To pUnpacked.nField - 1
                    sqlite3VdbeMemRelease(@pFields[iField])
                Next
                sqlite3DbFree(pVdbe->db, pFields)
            End If
            If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)

            Dim alreadyExists As SQLITE_C_INT = IIf(result = 0, 1, 0)
            pCursor->nullRow = IIf(alreadyExists <> 0, 0, 1)
            pCursor->deferredMoveto = 0
            pCursor->cacheStatus = CACHE_STALE
            pCursor->seekResult = result
            If (pOp->opcode = OP_Found AndAlso alreadyExists <> 0) OrElse _
               (pOp->opcode <> OP_Found AndAlso _
                (alreadyExists = 0 OrElse _
                 (pOp->opcode = OP_NoConflict AndAlso anyNull <> 0))) Then _
                nextCounter = pOp->p2

#ifndef SQLITE_OMIT_INTEGRITY_CHECK
        Case OP_IFindKey
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 < 0 OrElse pOp->p2 > pVdbe->nOp OrElse _
               pOp->p3 <= 0 OrElse pOp->p4type <> P4_INDEX OrElse _
               pOp->p4.p = 0 OrElse pVdbe->apCsr = 0 OrElse _
               pVdbe->apCsr[pOp->p1] = 0 OrElse programCounter <= 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pPriorFound As SqliteVdbeOp Ptr = _
                @pVdbe->aOp[programCounter - 1]
            If pPriorFound->opcode <> OP_Found OrElse _
               pPriorFound->p4type <> P4_INT32 OrElse _
               pPriorFound->p1 <> pOp->p1 OrElse _
               pPriorFound->p3 <> pOp->p3 OrElse _
               pPriorFound->p4.i <= 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)

            Dim pIndexCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            Dim pIndex As SqliteIndex Ptr = CPtr(SqliteIndex Ptr, pOp->p4.p)
            If pIndexCursor->eCurType <> CURTYPE_BTREE OrElse _
               pIndexCursor->isTable <> 0 OrElse _
               pIndexCursor->uc.pCursor = 0 OrElse pIndexCursor->pKeyInfo = 0 OrElse _
               pIndex->nColumn = 0 OrElse _
               pIndex->nColumn > pVdbe->nMem - pOp->p3 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)

            Dim unpackedKey As sqlite3VdbeUnpackedRecord
            unpackedKey.pKeyInfo = pIndexCursor->pKeyInfo
            unpackedKey.aMem = @pVdbe->aMem[pOp->p3]
            unpackedKey.u.i = 0
            unpackedKey.n = 0
            unpackedKey.nField = pIndex->nColumn
            unpackedKey.default_rc = 0
            unpackedKey.errCode = SQLITE_OK
            unpackedKey.r1 = 0
            unpackedKey.r2 = 0
            unpackedKey.eqSeen = 0
            Dim keyComparison As SQLITE_C_INT = 0
            Dim findKeyCode As SQLITE_C_INT = sqlite3VdbeFindIndexKey( _
                pIndexCursor->uc.pCursor, pIndex, @unpackedKey, _
                @keyComparison, 1)
            If findKeyCode <> SQLITE_OK OrElse keyComparison <> 0 Then
                nextCounter = pOp->p2
            Else
                pIndexCursor->nullRow = 0
            End If
#endif

        Case OP_IdxInsert
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pOp->p3 < 0 OrElse pOp->p4.i < 0 OrElse _
               pOp->p4.i > &HFFFF OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            Dim pRecord As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p2]
            Dim fieldCount As SQLITE_C_INT = 0
            If pOp->p4type = P4_INT32 Then
                fieldCount = pOp->p4.i
            ElseIf pOp->p4type <> P4_NOTUSED OrElse pOp->p3 <> 0 Then
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            End If
            Dim preformattedIndexInsert As SQLITE_C_INT = CInt( _
                (pOp->p5 And OPFLAG_PREFORMAT) <> 0)
            If pCursor->eCurType <> CURTYPE_BTREE OrElse pCursor->isTable <> 0 OrElse _
               pCursor->uc.pCursor = 0 OrElse _
               ((pRecord->flags And MEM_BLOB) = 0 AndAlso _
                preformattedIndexInsert = 0) OrElse pRecord->n < 0 OrElse _
               (pRecord->n = 0 AndAlso preformattedIndexInsert = 0) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim zeroBytes As SQLITE_C_INT = 0
            If (pRecord->flags And MEM_ZERO) <> 0 Then zeroBytes = pRecord->u.nZero
            If zeroBytes < 0 OrElse pRecord->n > pVdbe->db->lengthLimit OrElse _
               zeroBytes > pVdbe->db->lengthLimit - pRecord->n Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_TOOBIG)
            If fieldCount > 0 Then
                If pOp->p3 <= 0 OrElse pOp->p3 > pVdbe->nMem - fieldCount OrElse _
                   pCursor->pKeyInfo = 0 OrElse fieldCount > _
                       CPtr(sqlite3VdbeKeyInfoPrefix Ptr, pCursor->pKeyInfo)->nAllField Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            ElseIf pOp->p3 <> 0 Then
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            End If
            Dim rc As SQLITE_C_INT = sqlite3VdbeMemExpandBlob(pRecord)
            If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
            If (pRecord->n = 0 AndAlso preformattedIndexInsert = 0) OrElse _
               pRecord->n > pVdbe->db->lengthLimit Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_TOOBIG)
            Dim payload As SqliteBtreePayload
            payload.pKey = pRecord->z
            payload.nKey = pRecord->n
            payload.pData = 0
            payload.aMem = 0
            If fieldCount > 0 Then payload.aMem = @pVdbe->aMem[pOp->p3]
            payload.nMem = CUShort(fieldCount)
            payload.nData = 0
            payload.nZero = 0
            If (pOp->p5 And OPFLAG_NCHANGE) <> 0 Then
                pVdbe->nChange += 1
                pVdbe->vdbeFlags Or= VDBE_CHANGECOUNT_MASK
            End If
            Dim seekResult As SQLITE_C_INT = 0
            If (pOp->p5 And OPFLAG_USESEEKRESULT) <> 0 Then _
                seekResult = pCursor->seekResult
            rc = sqlite3BtreeInsert(pCursor->uc.pCursor, @payload, _
                pOp->p5 And (OPFLAG_APPEND Or OPFLAG_SAVEPOSITION Or OPFLAG_PREFORMAT), _
                seekResult)
            If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
            pCursor->deferredMoveto = 0
            pCursor->cacheStatus = CACHE_STALE
            pCursor->seekResult = 0

        Case OP_IdxDelete
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p5 <= 0 OrElse _
               pOp->p5 > pVdbe->nMem - pOp->p2 OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pCursor->eCurType <> CURTYPE_BTREE OrElse pCursor->isTable <> 0 OrElse _
               pCursor->uc.pCursor = 0 OrElse pCursor->pKeyInfo = 0 OrElse _
               pOp->p5 > CPtr(sqlite3VdbeKeyInfoPrefix Ptr, _
                   pCursor->pKeyInfo)->nAllField Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim unpacked As sqlite3VdbeUnpackedRecord
            unpacked.pKeyInfo = pCursor->pKeyInfo
            unpacked.aMem = @pVdbe->aMem[pOp->p2]
            unpacked.u.i = 0
            unpacked.n = 0
            unpacked.nField = CUShort(pOp->p5)
            unpacked.default_rc = 0
            unpacked.errCode = SQLITE_OK
            unpacked.r1 = 0
            unpacked.r2 = 0
            unpacked.eqSeen = 0
            Dim result As SQLITE_C_INT = 0
            Dim rc As SQLITE_C_INT = sqlite3BtreeIndexMoveto( _
                pCursor->uc.pCursor, @unpacked, @result)
            If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
            If result <> 0 Then
                Dim pIndex As SqliteIndex Ptr = _
                    CPtr(SqliteIndex Ptr, pOp->p4.p)
                If pIndex = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT_INDEX)
                rc = sqlite3VdbeFindIndexKey( _
                    pCursor->uc.pCursor, pIndex, @unpacked, @result, 0)
                If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
                If result <> 0 Then
                    If sqlite3WritableSchema(pVdbe->db) = 0 Then _
                        Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT_INDEX)
                    pCursor->cacheStatus = CACHE_STALE
                    pCursor->seekResult = 0
                    Exit Select
                End If
            End If
            ' Deleting and recreating an unchanged index entry is equivalent to
            ' the upstream P3 shortcut; leaving P3 intact keeps later inserts active.
            rc = sqlite3BtreeDelete(pCursor->uc.pCursor, BTREE_AUXDELETE)
            If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
            pCursor->deferredMoveto = 0
            pCursor->cacheStatus = CACHE_STALE
            pCursor->seekResult = 0

        Case OP_IdxLE, OP_IdxGT, OP_IdxLT, OP_IdxGE
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 > pVdbe->nOp OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            Dim comparison As SQLITE_C_INT = 0
            Dim rc As SQLITE_C_INT = sqlite3VdbeExecIndexCursorCompare( _
                pVdbe, pCursor, pOp, comparison)
            If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
            Dim branchResult As SQLITE_C_INT
            If pOp->opcode = OP_IdxLE OrElse pOp->opcode = OP_IdxLT Then
                branchResult = -comparison
            Else
                branchResult = comparison + 1
            End If
            If branchResult > 0 Then nextCounter = pOp->p2

        Case OP_DeferredSeek
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p3 < 0 OrElse pOp->p3 >= pVdbe->nCursor OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 OrElse _
               pVdbe->apCsr[pOp->p3] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pIndexCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            Dim pTableCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p3])
            If pIndexCursor->eCurType <> CURTYPE_BTREE OrElse _
               pIndexCursor->isTable <> 0 OrElse _
               pIndexCursor->uc.pCursor = 0 OrElse _
               pTableCursor->eCurType <> CURTYPE_BTREE OrElse _
               pTableCursor->isTable = 0 OrElse pTableCursor->uc.pCursor = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim restoreCode As SQLITE_C_INT = sqlite3VdbeCursorRestore(pIndexCursor)
            If restoreCode <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, restoreCode)
            Dim rowId As sqlite3_int64 = 0
            If pOp->p4type <> P4_NOTUSED AndAlso pOp->p4type <> P4_INTARRAY Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pIndexCursor->nullRow = 0 Then
                Dim rc As SQLITE_C_INT = sqlite3VdbeIdxRowid( _
                    pVdbe->db, pIndexCursor->uc.pCursor, @rowId)
                If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
                pTableCursor->nullRow = 0
                pTableCursor->movetoTarget = rowId
                pTableCursor->deferredMoveto = 1
                pTableCursor->cacheStatus = CACHE_STALE
                pTableCursor->ub.aAltMap = 0
                If pOp->p4type = P4_INTARRAY Then _
                    pTableCursor->ub.aAltMap = CPtr(u32 Ptr, pOp->p4.p)
                pTableCursor->pAltCursor = pIndexCursor
            End If

#ifdef SQLITE_ENABLE_CURSOR_HINTS
        Case OP_CursorHint
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pVdbe->apCsr = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pCursor <> 0 Then
                If pCursor->eCurType <> CURTYPE_BTREE OrElse _
                   pCursor->uc.pCursor = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                If pOp->p4type = P4_EXPR Then
                    If pOp->p4.p = 0 Then _
                        Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                    sqlite3BtreeCursorHint( _
                        CPtr(BtCursor Ptr, pCursor->uc.pCursor), _
                        BTREE_HINT_RANGE, _
                        pOp->p4.p, _
                        pVdbe->aMem)
                ElseIf pOp->p3 >= 0 AndAlso pOp->p3 < pVdbe->nCursor AndAlso _
                       pVdbe->apCsr[pOp->p3] <> 0 Then
                    Dim pTableCursor As SqliteVdbeCursor Ptr = _
                        CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p3])
                    If pTableCursor->eCurType <> CURTYPE_BTREE OrElse _
                       pTableCursor->uc.pCursor = 0 Then _
                        Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                    sqlite3BtreeCursorHint( _
                        CPtr(BtCursor Ptr, pCursor->uc.pCursor), _
                        BTREE_HINT_TABLECURSOR, _
                        CPtr(BtCursor Ptr, pTableCursor->uc.pCursor))
                End If
            End If

#endif
        Case OP_FinishSeek
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pCursor->deferredMoveto <> 0 Then
                Dim rc As SQLITE_C_INT = sqlite3VdbeExecFinishSeek(pCursor)
                If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
            End If

        Case OP_IdxRowid
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pCursor->eCurType <> CURTYPE_BTREE OrElse pCursor->isTable <> 0 OrElse _
               pCursor->uc.pCursor = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim restoreCode As SQLITE_C_INT = sqlite3VdbeCursorRestore(pCursor)
            If restoreCode <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, restoreCode)
            If pCursor->nullRow <> 0 Then
                sqlite3VdbeMemSetNull(@pVdbe->aMem[pOp->p2])
            Else
                Dim rowId As sqlite3_int64 = 0
                Dim rc As SQLITE_C_INT = sqlite3VdbeIdxRowid( _
                    pVdbe->db, pCursor->uc.pCursor, @rowId)
                If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
                sqlite3VdbeMemSetInt64(@pVdbe->aMem[pOp->p2], rowId)
            End If

        Case OP_Sequence
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr = _
                CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            If pCursor->eCurType = CURTYPE_VTAB Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pCursor->seqCount = 9223372036854775807LL Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_FULL)
            sqlite3VdbeMemSetInt64(@pVdbe->aMem[pOp->p2], pCursor->seqCount)
            pCursor->seqCount += 1

        Case OP_ResetCount
            sqlite3VdbeSetChanges(pVdbe->db, pVdbe->nChange)
            pVdbe->nChange = 0

        Case OP_OffsetLimit
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem OrElse _
               (pVdbe->aMem[pOp->p1].flags And MEM_INT) = 0 OrElse _
               (pVdbe->aMem[pOp->p3].flags And MEM_INT) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim totalRows As sqlite3_int64 = pVdbe->aMem[pOp->p1].u.i
            If totalRows <= 0 Then
                totalRows = -1
            Else
                Dim offsetRows As sqlite3_int64 = pVdbe->aMem[pOp->p3].u.i
                If offsetRows > 0 AndAlso sqlite3AddInt64(@totalRows, offsetRows) <> 0 Then _
                    totalRows = -1
            End If
            sqlite3VdbeMemSetInt64(@pVdbe->aMem[pOp->p2], totalRows)

        Case OP_Gosub
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nOp Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            sqlite3VdbeMemSetInt64(@pVdbe->aMem[pOp->p1], programCounter)
            nextCounter = pOp->p2

        Case OP_Return
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               (pOp->p3 <> 0 AndAlso pOp->p3 <> 1) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pReturnAddress As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p1]
            If (pReturnAddress->flags And MEM_INT) <> 0 Then
                If pReturnAddress->u.i < 0 OrElse _
                   pReturnAddress->u.i >= pVdbe->nOp Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                nextCounter = CInt(pReturnAddress->u.i) + 1
            ElseIf pOp->p3 = 0 Then
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            End If

        Case OP_Once
            If pOp->p2 < 0 OrElse pOp->p2 > pVdbe->nOp Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)

            If pVdbe->pFrame <> 0 Then
                Dim pFrame As SqliteVdbeFrame Ptr = _
                    CPtr(SqliteVdbeFrame Ptr, pVdbe->pFrame)
                If pFrame->aOnce = 0 OrElse pVdbe->nOp <= 0 OrElse _
                   programCounter >= pVdbe->nOp Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                Dim byteIndex As SQLITE_C_INT = programCounter \ 8
                Dim bitIndex As SQLITE_C_INT = programCounter And 7
                Dim bitMask As UByte = CByte(1 Shl bitIndex)
                If (pFrame->aOnce[byteIndex] And bitMask) <> 0 Then
                    nextCounter = pOp->p2
                Else
                    pFrame->aOnce[byteIndex] = _
                        pFrame->aOnce[byteIndex] Or bitMask
                End If
            Else
                If pVdbe->nOp <= 0 OrElse _
                   pVdbe->aOp[0].opcode <> OP_Init Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                If pVdbe->aOp[0].p1 = pOp->p1 Then
                    nextCounter = pOp->p2
                Else
                    pOp->p1 = pVdbe->aOp[0].p1
                End If
            End If

        Case OP_Init, OP_Trace, OP_Goto
            If pOp->p2 < 0 OrElse pOp->p2 > pVdbe->nOp Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
#ifndef SQLITE_OMIT_TRACE
            If pOp->opcode = OP_Init OrElse pOp->opcode = OP_Trace Then _
                vdbeExecTrace(pVdbe, pOp)
#endif
            If pOp->opcode = OP_Init OrElse pOp->opcode = OP_Trace Then
                If pOp->p1 >= sqlite3ConfigTestOnceResetThreshold() Then
                    If pOp->opcode = OP_Trace Then
                        nextCounter = programCounter + 1
                    Else
                        For iOp As SQLITE_C_INT = 1 To pVdbe->nOp - 1
                            If pVdbe->aOp[iOp].opcode = OP_Once Then _
                                pVdbe->aOp[iOp].p1 = 0
                        Next
                        pOp->p1 = 0
                        pOp->p1 += 1
                        pVdbe->aCounter(SQLITE_STMTSTATUS_RUN) += 1
                        nextCounter = pOp->p2
                    End If
                Else
                    pOp->p1 += 1
                    pVdbe->aCounter(SQLITE_STMTSTATUS_RUN) += 1
                    nextCounter = pOp->p2
                End If
            Else
                nextCounter = pOp->p2
            End If

        Case OP_Expire
            If pOp->p1 <> 0 Then
                Dim expiredValue As ULong = CULng(pOp->p2 + 1) And VDBE_EXPIRED_MASK
                pVdbe->vdbeFlags = (pVdbe->vdbeFlags And Not VDBE_EXPIRED_MASK) Or expiredValue
            Else
                Dim pOther As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pVdbe->db->pVdbe)
                While pOther <> 0
                    Dim expiredValue As ULong = CULng(pOp->p2 + 1) And VDBE_EXPIRED_MASK
                    pOther->vdbeFlags = (pOther->vdbeFlags And Not VDBE_EXPIRED_MASK) Or expiredValue
                    pOther = CPtr(SqliteVdbe Ptr, pOther->pVNext)
                Wend
            End If

        Case OP_Integer
            If pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            sqlite3VdbeMemSetInt64(@pVdbe->aMem[pOp->p2], pOp->p1)

        Case OP_Int64
            If pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim lowWord As ULongInt = CULngInt(CLngInt(pOp->p1)) And &HFFFFFFFFULL
            Dim highWord As ULongInt = CULngInt(CLngInt(pOp->p3)) And &HFFFFFFFFULL
            Dim valueBits As ULongInt = (highWord Shl 32) Or lowWord
            Dim integerValue As LongInt
            sqlite3VdbeExecMemcpy(@integerValue, @valueBits, SizeOf(integerValue))
            sqlite3VdbeMemSetInt64(@pVdbe->aMem[pOp->p2], integerValue)

        Case OP_Real
            If pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim lowWord As ULongInt = CULngInt(CLngInt(pOp->p1)) And &HFFFFFFFFULL
            Dim highWord As ULongInt = CULngInt(CLngInt(pOp->p3)) And &HFFFFFFFFULL
            Dim valueBits As ULongInt = (highWord Shl 32) Or lowWord
            Dim realValue As Double
            sqlite3VdbeExecMemcpy(@realValue, @valueBits, SizeOf(realValue))
            sqlite3VdbeMemSetDouble(@pVdbe->aMem[pOp->p2], realValue)

        Case OP_Blob
            If pOp->p1 < 0 OrElse pOp->p2 <= 0 OrElse _
               pOp->p2 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pOp->p1 > pVdbe->db->lengthLimit Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_TOOBIG)
            Dim rc As SQLITE_C_INT
            If pOp->p4.p = 0 Then
                sqlite3VdbeMemSetZeroBlob(@pVdbe->aMem[pOp->p2], pOp->p1)
                rc = sqlite3VdbeMemExpandBlob(@pVdbe->aMem[pOp->p2])
            Else
                Dim transientDestructor As sqlite3MemDestructor = _
                    CPtr(sqlite3MemDestructor, -1)
                rc = sqlite3VdbeMemSetStr( _
                    @pVdbe->aMem[pOp->p2], CPtr(Const ZString Ptr, pOp->p4.p), _
                    pOp->p1, 0, transientDestructor)
            End If
            If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)

        Case OP_String8, OP_String
            If pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse pOp->p4.z = 0 OrElse _
               (pOp->opcode = OP_String AndAlso pOp->p1 < 0) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim stringLength As SQLITE_C_INT = -1
            If pOp->opcode = OP_String Then stringLength = pOp->p1
            Dim transientDestructor As sqlite3MemDestructor = CPtr(sqlite3MemDestructor, -1)
            Dim pOutput As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p2]
            Dim rc As SQLITE_C_INT = sqlite3VdbeMemSetText( _
                pOutput, pOp->p4.z, stringLength, transientDestructor)
            If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
            If pOp->opcode = OP_String8 AndAlso _
               pVdbe->db->enc <> SQLITE_UTF8 Then
                ' SQL literals begin as UTF-8, while table records use the database encoding.
                rc = sqlite3VdbeChangeEncoding(pOutput, pVdbe->db->enc)
                If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
            End If
#ifndef SQLITE_LIKE_DOESNT_MATCH_BLOBS
            If pOp->p3 > 0 Then
                If pOp->p3 >= pVdbe->nMem Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                Dim pBlobFlag As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p3]
                If (pBlobFlag->flags And MEM_INT) = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                If pBlobFlag->u.i = pOp->p5 Then
                    ' LIKE and GLOB range loops retest the upper prefix once.
                    ' The BLOB type makes the repeated lower-bound seek pass text keys.
                    pOutput->flags = (pOutput->flags And _
                        Not (MEM_NULL Or MEM_STR Or MEM_INT Or MEM_INTREAL Or _
                             MEM_REAL Or MEM_BLOB)) Or MEM_BLOB
                End If
            End If
#endif

        Case OP_BeginSubrtn, OP_Null
            If pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim lastRegister As SQLITE_C_INT = pOp->p2
            If pOp->p3 > pOp->p2 Then lastRegister = pOp->p3
            If lastRegister >= pVdbe->nMem Then Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            For iRegister As SQLITE_C_INT = pOp->p2 To lastRegister
                sqlite3VdbeMemSetNull(@pVdbe->aMem[iRegister])
                pVdbe->aMem[iRegister].n = 0
                pVdbe->aMem[iRegister].uTemp = 0
                If pOp->p1 <> 0 Then pVdbe->aMem[iRegister].flags Or= MEM_CLEARED
            Next

        Case OP_AggStep, OP_AggInverse, OP_AggStep1
            Dim inverseStep As SQLITE_C_INT = CInt( _
                pOp->opcode = OP_AggInverse OrElse _
                (pOp->opcode = OP_AggStep1 AndAlso pOp->p1 <> 0))
            If pOp->p4type <> P4_FUNCDEF OrElse pOp->p4.p = 0 OrElse _
               pOp->p1 < 0 OrElse pOp->p1 > 1 OrElse _
               (pOp->opcode = OP_AggStep AndAlso pOp->p1 <> 0) OrElse _
               (pOp->opcode = OP_AggInverse AndAlso pOp->p1 <> 1) OrElse _
               pOp->p3 <= 0 OrElse _
               pOp->p3 >= pVdbe->nMem OrElse _
               pOp->p5 > SQLITE_MAX_FUNCTION_ARG Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pFunction As SqliteFuncDef Ptr = _
                CPtr(SqliteFuncDef Ptr, pOp->p4.p)
            Dim argumentCount As SQLITE_C_INT = pOp->p5
            If pFunction->xSFunc = 0 OrElse pFunction->xFinalize = 0 OrElse _
               (inverseStep <> 0 AndAlso pFunction->xInverse = 0) OrElse _
               sqlite3VdbeAggregateArgCountValid(pFunction, argumentCount) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If argumentCount > 0 AndAlso _
               (pOp->p2 <= 0 OrElse _
                pOp->p2 > pVdbe->nMem - argumentCount + 1 OrElse _
                (pOp->p3 >= pOp->p2 AndAlso _
                 pOp->p3 < pOp->p2 + argumentCount)) Then
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            End If

            Dim pAccumulator As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p3]
            If (pAccumulator->flags And Not (MEM_NULL Or MEM_AGG)) <> 0 OrElse _
               ((pAccumulator->flags And MEM_AGG) <> 0 AndAlso _
                pAccumulator->u.pDef <> pFunction) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pAccumulator->n < &H7FFFFFFF Then pAccumulator->n += 1

            For iArgument As SQLITE_C_INT = 0 To argumentCount - 1
                aggregateArguments(iArgument) = _
                    @pVdbe->aMem[pOp->p2 + iArgument]
            Next
            Dim aggregateResult As SqliteVdbeMem
            sqlite3VdbeMemInit(@aggregateResult, pVdbe->db, MEM_NULL)
            Dim aggregateContext As SqliteResultContext
            aggregateContext.pOut = @aggregateResult
            aggregateContext.pFunc = pFunction
            aggregateContext.pMem = pAccumulator
            aggregateContext.pVdbe = pVdbe
            aggregateContext.iOp = programCounter
            aggregateContext.isError = 0
            aggregateContext.enc = pVdbe->db->enc
            aggregateContext.skipFlag = 0
            aggregateContext.argc = CUShort(argumentCount)
            aggregateContext.argv(0) = 0
            Dim aggregateCallback As SqliteScalarFunction = pFunction->xSFunc
            If inverseStep <> 0 Then _
                aggregateCallback = CPtr(SqliteScalarFunction, pFunction->xInverse)
            aggregateCallback( _
                @aggregateContext, argumentCount, @aggregateArguments(0))
            Dim aggregateError As SQLITE_C_INT = aggregateContext.isError
            If aggregateError <> 0 Then
                If aggregateError > 0 Then
                    Dim errorText As Const UByte Ptr = _
                        sqlite3_value_text(@aggregateResult)
                    If errorText <> 0 Then
                        sqlite3VdbeError( _
                            pVdbe, StrPtr(!"%s"), _
                            CPtr(Const ZString Ptr, errorText))
                    End If
                End If
                If aggregateContext.skipFlag <> 0 Then
                    If programCounter <= 0 OrElse pVdbe->aOp = 0 OrElse _
                       pVdbe->aOp[programCounter - 1].opcode <> OP_CollSeq Then
                        aggregateContext.skipFlag = 0
                        aggregateContext.isError = 0
                        sqlite3VdbeMemRelease(@aggregateResult)
                        Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                    End If
                    Dim skipRegister As SQLITE_C_INT = _
                        pVdbe->aOp[programCounter - 1].p1
                    If skipRegister < 0 OrElse skipRegister >= pVdbe->nMem Then
                        aggregateContext.skipFlag = 0
                        aggregateContext.isError = 0
                        sqlite3VdbeMemRelease(@aggregateResult)
                        Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                    End If
                    If skipRegister <> 0 Then _
                        sqlite3VdbeMemSetInt64( _
                            @pVdbe->aMem[skipRegister], 1)
                    aggregateContext.skipFlag = 0
                End If
                sqlite3VdbeMemRelease(@aggregateResult)
                aggregateContext.isError = 0
                If aggregateError > 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, aggregateError)
            End If
            sqlite3VdbeMemRelease(@aggregateResult)
            If pVdbe->db->mallocFailed <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_NOMEM)

        Case OP_AggValue, OP_AggFinal
            If pOp->p4type <> P4_FUNCDEF OrElse pOp->p4.p = 0 OrElse _
               pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 < 0 OrElse _
               pOp->p2 > SQLITE_MAX_FUNCTION_ARG Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pOp->opcode = OP_AggFinal AndAlso pOp->p3 <> 0) OrElse _
               (pOp->opcode = OP_AggValue AndAlso _
                (pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem OrElse _
                 pOp->p3 = pOp->p1)) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pFunction As SqliteFuncDef Ptr = _
                CPtr(SqliteFuncDef Ptr, pOp->p4.p)
            If (pOp->opcode = OP_AggFinal AndAlso pFunction->xFinalize = 0) OrElse _
               (pOp->opcode = OP_AggValue AndAlso pFunction->xValue = 0) OrElse _
               sqlite3VdbeAggregateArgCountValid(pFunction, pOp->p2) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pAccumulator As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p1]
            If (pAccumulator->flags And Not (MEM_NULL Or MEM_AGG)) <> 0 OrElse _
               ((pAccumulator->flags And MEM_AGG) <> 0 AndAlso _
                pAccumulator->u.pDef <> pFunction) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pAggregateResult As SqliteVdbeMem Ptr = pAccumulator
            Dim aggregateFinishCode As SQLITE_C_INT
            If pOp->opcode = OP_AggValue Then
                pAggregateResult = @pVdbe->aMem[pOp->p3]
                aggregateFinishCode = sqlite3VdbeMemAggValue( _
                    pAccumulator, pAggregateResult, pFunction)
            Else
                aggregateFinishCode = sqlite3VdbeMemFinalize( _
                    pAccumulator, pFunction)
            End If
            If aggregateFinishCode <> SQLITE_OK Then
                Dim errorText As Const UByte Ptr = _
                    sqlite3_value_text(pAggregateResult)
                If errorText <> 0 Then _
                    sqlite3VdbeError( _
                        pVdbe, StrPtr(!"%s"), CPtr(Const ZString Ptr, errorText))
                Return sqlite3VdbeExecError(pVdbe, aggregateFinishCode)
            End If
            Dim aggregateEncodingCode As SQLITE_C_INT = _
                sqlite3VdbeChangeEncoding(pAggregateResult, pVdbe->db->enc)
            If aggregateEncodingCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, aggregateEncodingCode)
            If pVdbe->db->mallocFailed <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_NOMEM)

        Case OP_Function, OP_PureFunc
            If pOp->p4type <> P4_FUNCCTX OrElse pOp->p4.p = 0 OrElse _
               pOp->p3 <= 0 OrElse _
               pOp->p3 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            ' P1 is the constant-argument bitmask used by sqlite3_set_auxdata.
            Dim pContext As SqliteResultContext Ptr = _
                CPtr(SqliteResultContext Ptr, pOp->p4.p)
            Dim pFunction As SqliteFuncDef Ptr = _
                CPtr(SqliteFuncDef Ptr, pContext->pFunc)
            If pFunction = 0 OrElse pFunction->xSFunc = 0 OrElse _
               (pFunction->nArg >= 0 AndAlso _
                pFunction->nArg <> pContext->argc) OrElse _
               (pFunction->nArg = -3 AndAlso pContext->argc < 1) OrElse _
               (pFunction->nArg = -4 AndAlso pContext->argc < 2) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pContext->argc = 0 Then
                If pOp->p2 <> 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            ElseIf pOp->p2 <= 0 OrElse _
                   pOp->p2 > pVdbe->nMem - pContext->argc + 1 Then
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            End If

            pContext->pOut = @pVdbe->aMem[pOp->p3]
            pContext->pVdbe = pVdbe
            pContext->pMem = 0
            pContext->iOp = programCounter
            pContext->isError = 0
            pContext->enc = pVdbe->db->enc
            pContext->skipFlag = 0
            For iArgument As SQLITE_C_INT = 0 To pContext->argc - 1
                pContext->argv(iArgument) = _
                    @pVdbe->aMem[pOp->p2 + iArgument]
            Next
            sqlite3VdbeMemSetNull(pContext->pOut)
            pFunction->xSFunc( _
                pContext, pContext->argc, @pContext->argv(0))
            If pContext->isError <> 0 Then
                Dim functionError As SQLITE_C_INT = pContext->isError
                If functionError > 0 Then
                    Dim errorText As Const UByte Ptr = _
                        sqlite3_value_text(pContext->pOut)
                    If errorText <> 0 Then
                        sqlite3VdbeError(pVdbe, StrPtr(!"%s"), _
                            CPtr(Const ZString Ptr, errorText))
                    End If
                End If

                If pContext->skipFlag <> 0 Then
                    If programCounter <= 0 OrElse pVdbe->aOp = 0 OrElse _
                       pVdbe->aOp[programCounter - 1].opcode <> OP_CollSeq Then
                        pContext->skipFlag = 0
                        sqlite3VdbeMemSetNull(pContext->pOut)
                        pContext->isError = 0
                        Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                    End If
                    Dim skipRegister As SQLITE_C_INT = _
                        pVdbe->aOp[programCounter - 1].p1
                    If skipRegister < 0 OrElse skipRegister >= pVdbe->nMem Then
                        pContext->skipFlag = 0
                        sqlite3VdbeMemSetNull(pContext->pOut)
                        pContext->isError = 0
                        Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                    End If
                    If skipRegister <> 0 Then _
                        sqlite3VdbeMemSetInt64(@pVdbe->aMem[skipRegister], 1)
                    pContext->skipFlag = 0
                End If

                ' A negative isError marks auxdata changes, not a failed
                ' function result. Preserve pOut while expiring stale auxdata.
                sqlite3VdbeDeleteAuxData( _
                    pVdbe->db, @pVdbe->pAuxData, programCounter, pOp->p1)
                pContext->isError = 0
                If functionError > 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, functionError)
            End If
            If pVdbe->db->mallocFailed <> 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_NOMEM)

        Case OP_Variable
            If pVdbe->aVar = 0 OrElse pOp->p1 <= 0 OrElse _
               pOp->p1 > pVdbe->nVar OrElse pOp->p2 <= 0 OrElse _
               pOp->p2 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pVariable As SqliteVdbeMem Ptr = @pVdbe->aVar[pOp->p1 - 1]
            If (pVariable->flags And (MEM_STR Or MEM_BLOB)) <> 0 Then
                If pVariable->n < 0 Then Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                Dim variableBytes As sqlite3_uint64 = CULngInt(pVariable->n)
                If (pVariable->flags And MEM_ZERO) <> 0 AndAlso pVariable->u.nZero > 0 Then _
                    variableBytes += CULngInt(pVariable->u.nZero)
                If variableBytes > CULngInt(pVdbe->db->lengthLimit) Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_TOOBIG)
            End If
            sqlite3VdbeMemShallowCopy( _
                @pVdbe->aMem[pOp->p2], pVariable, MEM_STATIC)
            pVdbe->aMem[pOp->p2].flags Or= MEM_FROM_BIND

        Case OP_Add, OP_Subtract, OP_Multiply, OP_Divide, OP_Remainder
            Dim rc As SQLITE_C_INT = sqlite3VdbeExecArithmetic(pVdbe, pOp)
            If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)

        Case OP_Concat
            Dim rc As SQLITE_C_INT = sqlite3VdbeExecConcat(pVdbe, pOp)
            If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)

        Case OP_BitAnd, OP_BitOr, OP_ShiftLeft, OP_ShiftRight
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pLeft As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p1]
            Dim pRight As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p2]
            Dim pOutput As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p3]
            If ((pLeft->flags Or pRight->flags) And MEM_NULL) <> 0 Then
                sqlite3VdbeMemSetNull(pOutput)
            Else
                Dim leftValue As sqlite3_int64 = sqlite3VdbeIntValue(pLeft)
                Dim resultValue As sqlite3_int64 = sqlite3VdbeIntValue(pRight)
                Select Case pOp->opcode
                Case OP_BitAnd
                    resultValue = resultValue And leftValue
                Case OP_BitOr
                    resultValue = resultValue Or leftValue
                Case OP_ShiftLeft, OP_ShiftRight
                    Dim shiftCount As sqlite3_int64 = leftValue
                    Dim shiftLeft As SQLITE_C_INT = IIf(pOp->opcode = OP_ShiftLeft, 1, 0)
                    If shiftCount < 0 Then
                        shiftLeft = IIf(shiftLeft <> 0, 0, 1)
                        If shiftCount <= -64 Then
                            shiftCount = 64
                        Else
                            shiftCount = -shiftCount
                        End If
                    End If
                    If shiftCount >= 64 Then
                        resultValue = IIf(resultValue < 0 AndAlso shiftLeft = 0, -1, 0)
                    ElseIf shiftCount > 0 Then
                        Dim resultBits As ULongInt = CULngInt(resultValue)
                        If shiftLeft <> 0 Then
                            resultBits = resultBits Shl shiftCount
                        Else
                            resultBits = resultBits Shr shiftCount
                            If resultValue < 0 Then
                                resultBits Or= &HFFFFFFFFFFFFFFFFULL Shl (64 - shiftCount)
                            End If
                        End If
                        sqlite3VdbeExecMemcpy( _
                            @resultValue, @resultBits, SizeOf(resultBits))
                    End If
                End Select
                sqlite3VdbeMemSetInt64(pOutput, resultValue)
            End If

        Case OP_Ne, OP_Eq, OP_Gt, OP_Le, OP_Lt, OP_Ge
            Dim shouldJump As SQLITE_C_INT
            Dim rc As SQLITE_C_INT = sqlite3VdbeExecComparison( _
                pVdbe, pOp, shouldJump, compareResult)
            If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
            If shouldJump <> 0 Then nextCounter = pOp->p2
            If shouldJump = 0 AndAlso _
               (pOp->opcode = OP_Lt OrElse pOp->opcode = OP_Gt) Then
                compareReady = 2
            Else
                compareReady = 0
            End If

        Case OP_ElseEq
            If compareReady <> 2 OrElse programCounter <= 0 OrElse _
               pOp->p2 < 0 OrElse pOp->p2 > pVdbe->nOp Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim previousCompareAddress As SQLITE_C_INT = programCounter - 1
            While previousCompareAddress >= 0 AndAlso _
                  pVdbe->aOp[previousCompareAddress].opcode = OP_ReleaseReg
                previousCompareAddress -= 1
            Wend
            If previousCompareAddress < 0 OrElse _
               (pVdbe->aOp[previousCompareAddress].opcode <> OP_Lt AndAlso _
                pVdbe->aOp[previousCompareAddress].opcode <> OP_Gt) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If compareResult = 0 Then nextCounter = pOp->p2
            compareReady = 0

        Case OP_Permutation
            If pOp->p4type <> P4_INTARRAY OrElse pOp->p4.p = 0 OrElse _
               programCounter + 1 >= pVdbe->nOp Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pPermutationOp As SqliteVdbeOp Ptr = _
                @pVdbe->aOp[programCounter + 1]
            If pPermutationOp->opcode <> OP_Compare OrElse _
               (pPermutationOp->p5 And OPFLAG_PERMUTE) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pPermutation As SQLITE_C_INT Ptr = _
                CPtr(SQLITE_C_INT Ptr, pOp->p4.p)
            If pPermutation[0] <= 0 OrElse _
               pPermutation[0] < pPermutationOp->p3 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)

        Case OP_Compare
            If pOp->p3 <= 0 OrElse pOp->p4type <> P4_KEYINFO OrElse _
               pOp->p4.p = 0 OrElse pVdbe->aMem = 0 OrElse _
               pVdbe->nCursor < 0 OrElse pVdbe->nCursor > pVdbe->nMem OrElse _
               programCounter + 1 >= pVdbe->nOp OrElse _
               pVdbe->aOp[programCounter + 1].opcode <> OP_Jump Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCompareKey As sqlite3VdbeKeyInfoPrefix Ptr = _
                CPtr(sqlite3VdbeKeyInfoPrefix Ptr, pOp->p4.pKeyInfo)
            If pCompareKey->nKeyField < pOp->p3 OrElse _
               pCompareKey->aSortFlags = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim maxRegister As SQLITE_C_INT = pVdbe->nMem - pVdbe->nCursor
            If pOp->p1 <= 0 OrElse pOp->p2 <= 0 OrElse maxRegister <= 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)

            Dim pPermutation As SQLITE_C_INT Ptr = 0
            If (pOp->p5 And OPFLAG_PERMUTE) <> 0 Then
                If programCounter = 0 OrElse _
                   pVdbe->aOp[programCounter - 1].opcode <> OP_Permutation OrElse _
                   pVdbe->aOp[programCounter - 1].p4type <> P4_INTARRAY OrElse _
                   pVdbe->aOp[programCounter - 1].p4.p = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                pPermutation = CPtr(SQLITE_C_INT Ptr, _
                    pVdbe->aOp[programCounter - 1].p4.p)
                If pPermutation[0] < pOp->p3 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            End If

            ' The permutation selects registers; KeyInfo fields stay in order.
            compareResult = 0
            For compareIndex As SQLITE_C_INT = 0 To pOp->p3 - 1
                Dim registerOffset As SQLITE_C_INT = compareIndex
                If pPermutation <> 0 Then
                    registerOffset = pPermutation[compareIndex + 1]
                    If registerOffset < 0 OrElse _
                       registerOffset > maxRegister - pOp->p1 OrElse _
                       registerOffset > maxRegister - pOp->p2 Then _
                        Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                ElseIf compareIndex > maxRegister - pOp->p1 OrElse _
                       compareIndex > maxRegister - pOp->p2 Then
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                End If

                Dim leftIndex As SQLITE_C_INT = pOp->p1 + registerOffset
                Dim rightIndex As SQLITE_C_INT = pOp->p2 + registerOffset
                Dim pLeft As SqliteVdbeMem Ptr = @pVdbe->aMem[leftIndex]
                Dim pRight As SqliteVdbeMem Ptr = @pVdbe->aMem[rightIndex]
                If (pLeft->flags And MEM_UNDEFINED) <> 0 OrElse _
                   (pRight->flags And MEM_UNDEFINED) <> 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                compareResult = sqlite3MemCompare( _
                    pLeft, pRight, pCompareKey->aColl(compareIndex))
                If compareResult <> 0 Then
                    ' KeyInfo controls NULL placement before DESC reverses the term.
                    If (pCompareKey->aSortFlags[compareIndex] And _
                        KEYINFO_ORDER_BIGNULL) <> 0 AndAlso _
                       ((pLeft->flags Or pRight->flags) And MEM_NULL) <> 0 Then
                        compareResult = -compareResult
                    End If
                    If (pCompareKey->aSortFlags[compareIndex] And _
                        KEYINFO_ORDER_DESC) <> 0 Then
                        compareResult = -compareResult
                    End If
                    Exit For
                End If
            Next
            compareReady = 1

        Case OP_Jump
            If compareReady <> 1 OrElse pOp->p1 < 0 OrElse _
               pOp->p1 > pVdbe->nOp OrElse pOp->p2 < 0 OrElse _
               pOp->p2 > pVdbe->nOp OrElse pOp->p3 < 0 OrElse _
               pOp->p3 > pVdbe->nOp Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If compareResult < 0 Then
                nextCounter = pOp->p1
            ElseIf compareResult = 0 Then
                nextCounter = pOp->p2
            Else
                nextCounter = pOp->p3
            End If
            compareReady = 0

        Case OP_Copy
            If pOp->p1 <= 0 OrElse pOp->p2 <= 0 OrElse pOp->p3 < 0 OrElse _
               pOp->p1 >= pVdbe->nMem OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pOp->p3 > pVdbe->nMem - 1 - pOp->p1 OrElse _
               pOp->p3 > pVdbe->nMem - 1 - pOp->p2 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            For iCopy As SQLITE_C_INT = 0 To pOp->p3
                Dim rc As SQLITE_C_INT = sqlite3VdbeMemCopy( _
                    @pVdbe->aMem[pOp->p2 + iCopy], _
                    @pVdbe->aMem[pOp->p1 + iCopy])
                If rc <> SQLITE_OK Then Return sqlite3VdbeExecError(pVdbe, rc)
                If (pOp->p5 And &H02) <> 0 Then _
                    pVdbe->aMem[pOp->p2 + iCopy].flags = _
                        pVdbe->aMem[pOp->p2 + iCopy].flags And Not MEM_SUBTYPE
            Next

        Case OP_SCopy
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            sqlite3VdbeMemShallowCopy( _
                @pVdbe->aMem[pOp->p2], @pVdbe->aMem[pOp->p1], MEM_EPHEM)

        Case OP_IntCopy
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               (pVdbe->aMem[pOp->p1].flags And MEM_INT) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            sqlite3VdbeMemSetInt64( _
                @pVdbe->aMem[pOp->p2], pVdbe->aMem[pOp->p1].u.i)

        Case OP_Move
            If pOp->p3 <= 0 OrElse pOp->p1 <= 0 OrElse pOp->p2 <= 0 OrElse _
               pOp->p1 > pVdbe->nMem - pOp->p3 OrElse _
               pOp->p2 > pVdbe->nMem - pOp->p3 OrElse _
               (pOp->p1 < pOp->p2 + pOp->p3 AndAlso _
                pOp->p2 < pOp->p1 + pOp->p3) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            For iMove As SQLITE_C_INT = 0 To pOp->p3 - 1
                sqlite3VdbeMemMove( _
                    @pVdbe->aMem[pOp->p2 + iMove], _
                    @pVdbe->aMem[pOp->p1 + iMove])
            Next

        Case OP_MustBeInt
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pInteger As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p1]
            If (pInteger->flags And MEM_INT) = 0 Then
                sqlite3ApplyNumericAffinity(pInteger, 1)
                If (pInteger->flags And MEM_INT) = 0 Then _
                    sqlite3VdbeIntegerAffinity(pInteger)
            End If
            If (pInteger->flags And MEM_INT) = 0 Then
                If pOp->p2 = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_MISMATCH)
                If pOp->p2 < 0 OrElse pOp->p2 > pVdbe->nOp Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                nextCounter = pOp->p2
            Else
                If sqlite3VdbeMemIntegerify(pInteger) <> SQLITE_OK Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_MISMATCH)
            End If

        Case OP_AddImm
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pInteger As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p1]
            If sqlite3VdbeMemIntegerify(pInteger) <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_MISMATCH)
            Dim valueBits As ULongInt = CULngInt(pInteger->u.i) + _
                                        CULngInt(CLngInt(pOp->p2))
            sqlite3VdbeExecMemcpy(@pInteger->u.i, @valueBits, SizeOf(valueBits))

#ifndef SQLITE_OMIT_AUTOINCREMENT
        Case OP_MemMax
            If pOp->p1 < 0 OrElse pOp->p2 <= 0 OrElse _
               pOp->p2 >= pVdbe->nMem OrElse pOp->p3 <> 0 OrElse _
               pOp->p4type <> P4_NOTUSED OrElse pOp->p5 <> 0 OrElse _
               pVdbe->aMem = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pRootFrame As SqliteVdbeFrame Ptr = _
                CPtr(SqliteVdbeFrame Ptr, pVdbe->pFrame)
            While pRootFrame <> 0 AndAlso pRootFrame->pParent <> 0
                pRootFrame = CPtr(SqliteVdbeFrame Ptr, pRootFrame->pParent)
            Wend
            Dim pMaximum As SqliteVdbeMem Ptr
            Dim rootRegisterLimit As SQLITE_C_INT
            If pRootFrame <> 0 Then
                rootRegisterLimit = pRootFrame->nMem - pRootFrame->nCursor
                If pOp->p1 > rootRegisterLimit OrElse pRootFrame->aMem = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                pMaximum = @pRootFrame->aMem[pOp->p1]
            Else
                rootRegisterLimit = pVdbe->nMem - pVdbe->nCursor
                If pOp->p1 > rootRegisterLimit Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                pMaximum = @pVdbe->aMem[pOp->p1]
            End If
            Dim pCandidate As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p2]
            If sqlite3VdbeMemIntegerify(pMaximum) <> SQLITE_OK OrElse _
               sqlite3VdbeMemIntegerify(pCandidate) <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_MISMATCH)
            If pMaximum->u.i < pCandidate->u.i Then _
                pMaximum->u.i = pCandidate->u.i
#endif

        Case OP_Program
            Dim programCode As SQLITE_C_INT = vdbeExecStartProgram( _
                pVdbe, pOp, programCounter, nextCounter)
            If programCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, programCode)

        Case OP_Param
            If pVdbe->pFrame = 0 OrElse pOp->p1 < 0 OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
        Dim pCurrentFrame As SqliteVdbeFrame Ptr = _
            CPtr(SqliteVdbeFrame Ptr, pVdbe->pFrame)
        If pCurrentFrame->aMem = 0 OrElse pCurrentFrame->aOp = 0 OrElse _
           pCurrentFrame->pc < 0 OrElse _
           pCurrentFrame->pc >= pCurrentFrame->nOp Then _
            Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
        Dim pCallingOp As SqliteVdbeOp Ptr = _
            @pCurrentFrame->aOp[pCurrentFrame->pc]
        If pCallingOp->opcode <> OP_Program OrElse pOp->p1 < 0 OrElse _
           CLngInt(pCallingOp->p1) < -CLngInt(pCurrentFrame->nMem) OrElse _
           pCallingOp->p1 > pCurrentFrame->nMem Then _
            Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
        Dim sourceRegister As sqlite3_int64 = _
            CLngInt(pCallingOp->p1) + CLngInt(pOp->p1)
        If sourceRegister < 0 OrElse _
           sourceRegister >= pCurrentFrame->nMem Then _
            Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
        sqlite3VdbeMemShallowCopy( _
                @pVdbe->aMem[pOp->p2], _
                @pCurrentFrame->aMem[CLng(sourceRegister)], _
                MEM_EPHEM)

        Case OP_IfPos, OP_IfNotZero, OP_DecrJumpZero
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 > pVdbe->nOp Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pInteger As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p1]
            If (pInteger->flags And MEM_INT) = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Select Case pOp->opcode
            Case OP_IfPos
                If pInteger->u.i > 0 Then
                    Dim result As sqlite3_int64 = pInteger->u.i
                    If sqlite3SubInt64(@result, pOp->p3) <> 0 Then _
                        Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                    pInteger->u.i = result
                    nextCounter = pOp->p2
                End If
            Case OP_IfNotZero
                If pInteger->u.i <> 0 Then
                    If pInteger->u.i > 0 Then pInteger->u.i -= 1
                    nextCounter = pOp->p2
                End If
            Case OP_DecrJumpZero
                If pInteger->u.i > (-9223372036854775807LL - 1) Then _
                    pInteger->u.i -= 1
                If pInteger->u.i = 0 Then nextCounter = pOp->p2
            End Select

        Case OP_IsType
            If pOp->p1 < -1 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 < 0 OrElse pOp->p2 > pVdbe->nOp OrElse _
               pOp->p4type <> P4_INT32 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pOp->p1 < 0 AndAlso _
                (pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem)) OrElse _
               (pOp->p1 >= 0 AndAlso pOp->p3 < 0) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)

            Dim valueMask As UShort = 0
            If pOp->p1 < 0 Then
                Dim pValue As SqliteVdbeMem Ptr = @pVdbe->aMem[pOp->p3]
                Dim valueType As SQLITE_C_INT
                If (pValue->flags And MEM_NULL) <> 0 Then
                    valueType = SQLITE_NULL
                ElseIf (pValue->flags And (MEM_REAL Or MEM_INTREAL)) <> 0 Then
                    valueType = SQLITE_FLOAT
                ElseIf (pValue->flags And MEM_INT) <> 0 Then
                    valueType = SQLITE_INTEGER
                ElseIf (pValue->flags And MEM_STR) <> 0 Then
                    valueType = SQLITE_TEXT
                Else
                    valueType = SQLITE_BLOB
                End If
                valueMask = CUShort(1 Shl (valueType - 1))
            Else
                If pVdbe->apCsr = 0 OrElse pVdbe->apCsr[pOp->p1] = 0 Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                Dim pTypeCursor As SqliteVdbeCursor Ptr = _
                    CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
                If pTypeCursor->nField < 0 OrElse _
                   pTypeCursor->nHdrParsed > pTypeCursor->nField Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                If pOp->p3 < pTypeCursor->nHdrParsed Then
                    If pTypeCursor->aOffset = 0 OrElse _
                       pTypeCursor->nField <= 0 Then _
                        Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                    Dim pSerialTypes As u32 Ptr = _
                        pTypeCursor->aOffset - pTypeCursor->nField
                    Dim serialType As u32 = pSerialTypes[pOp->p3]
                    If serialType >= 12 Then
                        If (serialType And 1) <> 0 Then
                            valueMask = &H04
                        Else
                            valueMask = &H08
                        End If
                    Else
                        Select Case serialType
                        Case 0, 10, 11
                            valueMask = &H10
                        Case 1 To 6, 8, 9
                            valueMask = &H01
                        Case 7
                            valueMask = &H02
                        Case Else
                            Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                        End Select
                    End If
                Else
                    If pOp->p4.i < SQLITE_INTEGER OrElse _
                       pOp->p4.i > SQLITE_NULL Then _
                        Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                    valueMask = CUShort(1 Shl (pOp->p4.i - 1))
                End If
            End If
            If (pOp->p5 And valueMask) <> 0 Then nextCounter = pOp->p2

        Case OP_If, OP_IfNot
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 > pVdbe->nOp Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim nullTakesJump As SQLITE_C_INT = pOp->p3
            If pOp->opcode = OP_IfNot Then _
                nullTakesJump = IIf(pOp->p3 = 0, 1, 0)
            Dim shouldJump As SQLITE_C_INT = sqlite3VdbeBooleanValue( _
                @pVdbe->aMem[pOp->p1], nullTakesJump)
            If pOp->opcode = OP_IfNot Then shouldJump = IIf(shouldJump = 0, 1, 0)
            If shouldJump <> 0 Then nextCounter = pOp->p2

        Case OP_IsNull, OP_NotNull
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 > pVdbe->nOp Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim isNull As Long = IIf( _
                (pVdbe->aMem[pOp->p1].flags And MEM_NULL) <> 0, 1, 0)
            If (pOp->opcode = OP_IsNull AndAlso isNull <> 0) OrElse _
               (pOp->opcode = OP_NotNull AndAlso isNull = 0) Then _
                nextCounter = pOp->p2

        Case OP_ZeroOrNull
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If ((pVdbe->aMem[pOp->p1].flags Or pVdbe->aMem[pOp->p3].flags) And _
                MEM_NULL) <> 0 Then
                sqlite3VdbeMemSetNull(@pVdbe->aMem[pOp->p2])
            Else
                sqlite3VdbeMemSetInt64(@pVdbe->aMem[pOp->p2], 0)
            End If

        Case OP_IfNotOpen
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 > pVdbe->nOp OrElse _
               pVdbe->apCsr = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pVdbe->apCsr[pOp->p1] = 0 Then
                nextCounter = pOp->p2
            Else
                Dim pCursor As SqliteVdbeCursor Ptr = _
                    CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
                If pCursor->nullRow <> 0 Then nextCounter = pOp->p2
            End If

        Case OP_IfNullRow
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 > pVdbe->nOp OrElse _
               pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem OrElse _
               pVdbe->apCsr = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pVdbe->apCsr[pOp->p1] <> 0 Then
                Dim pCursor As SqliteVdbeCursor Ptr = _
                    CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
                If pCursor->nullRow <> 0 Then
                    sqlite3VdbeMemSetNull(@pVdbe->aMem[pOp->p3])
                    nextCounter = pOp->p2
                End If
            End If

        Case OP_NullRow
            If pOp->p1 < 0 OrElse pOp->p1 >= pVdbe->nCursor OrElse _
               pVdbe->apCsr = 0 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim pCursor As SqliteVdbeCursor Ptr
            If pVdbe->apCsr[pOp->p1] = 0 Then
                pCursor = allocateCursor(pVdbe, pOp->p1, 1, CURTYPE_PSEUDO)
                If pCursor = 0 Then Return sqlite3VdbeExecError(pVdbe, SQLITE_NOMEM)
                pCursor->isTable = 1
            Else
                pCursor = CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[pOp->p1])
            End If
            pCursor->nullRow = IIf(pOp->p2 = 0, 1, 0)
            pCursor->cacheStatus = CACHE_STALE
            If pCursor->eCurType = CURTYPE_BTREE AndAlso pCursor->uc.pCursor <> 0 Then _
                sqlite3BtreeClearCursor(pCursor->uc.pCursor)
#ifdef SQLITE_DEBUG
            If pCursor->seekOp = 0 Then pCursor->seekOp = OP_NullRow
#endif

        Case OP_And, OP_Or
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim leftBoolean As SQLITE_C_INT = sqlite3VdbeBooleanValue( _
                @pVdbe->aMem[pOp->p1], 2)
            Dim rightBoolean As SQLITE_C_INT = sqlite3VdbeBooleanValue( _
                @pVdbe->aMem[pOp->p2], 2)
            Dim resultBoolean As SQLITE_C_INT
            If pOp->opcode = OP_And Then
                If leftBoolean = 0 OrElse rightBoolean = 0 Then
                    resultBoolean = 0
                ElseIf leftBoolean = 2 OrElse rightBoolean = 2 Then
                    resultBoolean = 2
                Else
                    resultBoolean = 1
                End If
            Else
                If leftBoolean = 1 OrElse rightBoolean = 1 Then
                    resultBoolean = 1
                ElseIf leftBoolean = 2 OrElse rightBoolean = 2 Then
                    resultBoolean = 2
                Else
                    resultBoolean = 0
                End If
            End If
            If resultBoolean = 2 Then
                sqlite3VdbeMemSetNull(@pVdbe->aMem[pOp->p3])
            Else
                sqlite3VdbeMemSetInt64(@pVdbe->aMem[pOp->p3], resultBoolean)
            End If

        Case OP_IsTrue
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem OrElse _
               (pOp->p3 <> 0 AndAlso pOp->p3 <> 1) OrElse _
               pOp->p4type <> P4_INT32 OrElse _
               (pOp->p4.i <> 0 AndAlso pOp->p4.i <> 1) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim booleanResult As SQLITE_C_INT = sqlite3VdbeBooleanValue( _
                @pVdbe->aMem[pOp->p1], pOp->p3) Xor pOp->p4.i
            sqlite3VdbeMemSetInt64(@pVdbe->aMem[pOp->p2], booleanResult)

        Case OP_Not
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pVdbe->aMem[pOp->p1].flags And MEM_NULL) <> 0 Then
                sqlite3VdbeMemSetNull(@pVdbe->aMem[pOp->p2])
            Else
                Dim isTrue As SQLITE_C_INT = sqlite3VdbeBooleanValue( _
                    @pVdbe->aMem[pOp->p1], 0)
                sqlite3VdbeMemSetInt64( _
                    @pVdbe->aMem[pOp->p2], IIf(isTrue = 0, 1, 0))
            End If

        Case OP_BitNot
            If pOp->p1 <= 0 OrElse pOp->p1 >= pVdbe->nMem OrElse _
               pOp->p2 <= 0 OrElse pOp->p2 >= pVdbe->nMem Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pVdbe->aMem[pOp->p1].flags And MEM_NULL) <> 0 Then
                sqlite3VdbeMemSetNull(@pVdbe->aMem[pOp->p2])
            Else
                sqlite3VdbeMemSetInt64( _
                    @pVdbe->aMem[pOp->p2], Not sqlite3VdbeIntValue(@pVdbe->aMem[pOp->p1]))
            End If

#ifndef SQLITE_OMIT_FOREIGN_KEY
        Case OP_FkCounter
            If pOp->p1 < 0 OrElse pOp->p1 > 1 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pOp->p1 <> 0 Then
                pVdbe->db->nDeferredCons += pOp->p2
            ElseIf (pVdbe->db->flags And SQLITE_DeferFKs) <> 0 Then
                pVdbe->db->nDeferredImmCons += pOp->p2
            Else
                pVdbe->nFkConstraint += pOp->p2
            End If

        Case OP_FkIfZero
            If pOp->p1 < 0 OrElse pOp->p1 > 1 OrElse _
               pOp->p2 < 0 OrElse pOp->p2 >= pVdbe->nOp Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pOp->p1 <> 0 Then
                If pVdbe->db->nDeferredCons = 0 AndAlso _
                   pVdbe->db->nDeferredImmCons = 0 Then nextCounter = pOp->p2
            Else
                If pVdbe->nFkConstraint = 0 AndAlso _
                   pVdbe->db->nDeferredImmCons = 0 Then nextCounter = pOp->p2
            End If

        Case OP_FkCheck
            Dim foreignKeyCode As SQLITE_C_INT = sqlite3VdbeCheckFkImmediate(pVdbe)
            If foreignKeyCode <> SQLITE_OK Then
                Dim abortCode As SQLITE_C_INT = pVdbe->rc
                If abortCode = SQLITE_OK Then abortCode = foreignKeyCode
                Return sqlite3VdbeExecError(pVdbe, abortCode)
            End If
#endif

        Case OP_ResultRow
            If pOp->p1 <= 0 OrElse pOp->p2 < 0 OrElse _
               pOp->p2 <> pVdbe->nResColumn OrElse _
                pOp->p1 > pVdbe->nMem OrElse pOp->p2 > pVdbe->nMem - pOp->p1 + 1 Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            Dim resultProgressCode As SQLITE_C_INT = sqlite3VdbeExecProgressCheck(pVdbe)
            If resultProgressCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, resultProgressCode)
            pVdbe->cacheCtr = (pVdbe->cacheCtr + 2) Or 1
            pVdbe->pResultRow = @pVdbe->aMem[pOp->p1]
            pVdbe->pc = nextCounter
            sqlite3VdbeLeave(pVdbe)
            Return SQLITE_ROW

        Case OP_HaltIfNull
            If pOp->p3 <= 0 OrElse pOp->p3 >= pVdbe->nMem OrElse _
               pOp->p5 > 4 OrElse _
               (pOp->p4type <> P4_NOTUSED AndAlso _
                pOp->p4type <> P4_STATIC AndAlso _
                pOp->p4type <> P4_DYNAMIC) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If (pVdbe->aMem[pOp->p3].flags And MEM_NULL) = 0 Then Exit Select

            If pOp->p1 <> SQLITE_OK Then
                If pOp->p3 > 0 AndAlso pOp->p4type = P4_NOTUSED Then
                    Dim zError As Const ZString Ptr = CPtr( _
                        Const ZString Ptr, sqlite3ValueText( _
                            @pVdbe->aMem[pOp->p3], SQLITE_UTF8))
                    If zError <> 0 Then _
                        sqlite3VdbeError(pVdbe, StrPtr(!"%s"), zError)
                ElseIf pOp->p5 <> 0 Then
                    Dim zConstraint As Const ZString Ptr
                    Select Case pOp->p5
                    Case 1
                        zConstraint = StrPtr(!"NOT NULL")
                    Case 2
                        zConstraint = StrPtr(!"UNIQUE")
                    Case 3
                        zConstraint = StrPtr(!"CHECK")
                    Case 4
                        zConstraint = StrPtr(!"FOREIGN KEY")
                    End Select
                    If pOp->p4.z <> 0 Then
                        sqlite3VdbeError( _
                            pVdbe, StrPtr(!"%s constraint failed: %s"), _
                            zConstraint, pOp->p4.z)
                    Else
                        sqlite3VdbeError( _
                            pVdbe, StrPtr(!"%s constraint failed"), zConstraint)
                    End If
                ElseIf pOp->p4.z <> 0 Then
                    sqlite3VdbeError(pVdbe, StrPtr(!"%s"), pOp->p4.z)
                End If
            End If
            Dim haltIfNullProgress As SQLITE_C_INT = _
                sqlite3VdbeExecProgressCheck(pVdbe)
            If haltIfNullProgress <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, haltIfNullProgress)
            Dim haltIfNullResult As SQLITE_C_INT = _
                sqlite3VdbeExecFinish(pVdbe, pOp->p1, pOp->p2)
            sqlite3VdbeLeave(pVdbe)
            Return haltIfNullResult

        Case OP_Halt
            If pVdbe->pFrame <> 0 AndAlso pOp->p1 = SQLITE_OK Then
                Dim pCompletedFrame As SqliteVdbeFrame Ptr = _
                    CPtr(SqliteVdbeFrame Ptr, pVdbe->pFrame)
                If pVdbe->nFrame <= 0 OrElse pCompletedFrame->v <> pVdbe Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)

                Dim haltAction As SQLITE_C_INT = pOp->p2
                pVdbe->pFrame = pCompletedFrame->pParent
                pVdbe->nFrame -= 1
                sqlite3VdbeSetChanges(pVdbe->db, pVdbe->nChange)
                Dim parentProgramCounter As SQLITE_C_INT = _
                    sqlite3VdbeFrameRestore(pCompletedFrame)
                If parentProgramCounter < 0 OrElse _
                   parentProgramCounter >= pVdbe->nOp OrElse _
                   pVdbe->aOp[parentProgramCounter].opcode <> OP_Program Then _
                    Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                If haltAction = OE_IGNORE Then
                    nextCounter = pVdbe->aOp[parentProgramCounter].p2
                Else
                    nextCounter = parentProgramCounter + 1
                End If
                compareReady = 0
                Exit Select
            End If
            If pOp->p5 > 4 OrElse _
               (pOp->p4type <> P4_NOTUSED AndAlso _
                pOp->p4type <> P4_STATIC AndAlso _
                pOp->p4type <> P4_DYNAMIC) Then _
                Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
            If pOp->p1 <> SQLITE_OK Then
                If pOp->p3 > 0 AndAlso pOp->p4type = P4_NOTUSED Then
                    If pOp->p3 >= pVdbe->nMem Then _
                        Return sqlite3VdbeExecError(pVdbe, SQLITE_CORRUPT)
                    Dim zError As Const ZString Ptr = CPtr( _
                        Const ZString Ptr, sqlite3ValueText( _
                            @pVdbe->aMem[pOp->p3], SQLITE_UTF8))
                    sqlite3VdbeError(pVdbe, StrPtr(!"%s"), zError)
                ElseIf pOp->p5 <> 0 Then
                    Dim zConstraint As Const ZString Ptr
                    Select Case pOp->p5
                    Case 1
                        zConstraint = StrPtr(!"NOT NULL")
                    Case 2
                        zConstraint = StrPtr(!"UNIQUE")
                    Case 3
                        zConstraint = StrPtr(!"CHECK")
                    Case 4
                        zConstraint = StrPtr(!"FOREIGN KEY")
                    End Select
                    If pOp->p4.z <> 0 Then
                        sqlite3VdbeError( _
                            pVdbe, StrPtr(!"%s constraint failed: %s"), _
                            zConstraint, pOp->p4.z)
                    Else
                        sqlite3VdbeError( _
                            pVdbe, StrPtr(!"%s constraint failed"), zConstraint)
                    End If
                ElseIf pOp->p4.z <> 0 Then
                    sqlite3VdbeError(pVdbe, StrPtr(!"%s"), pOp->p4.z)
                End If
            End If
            Dim haltProgressCode As SQLITE_C_INT = sqlite3VdbeExecProgressCheck(pVdbe)
            If haltProgressCode <> SQLITE_OK Then _
                Return sqlite3VdbeExecError(pVdbe, haltProgressCode)
            Dim haltOpcodeResult As SQLITE_C_INT = _
                sqlite3VdbeExecFinish(pVdbe, pOp->p1, pOp->p2)
            sqlite3VdbeLeave(pVdbe)
            Return haltOpcodeResult

        Case Else
            Return sqlite3VdbeExecError(pVdbe, SQLITE_ERROR)
        End Select

        Dim loopProgressCode As SQLITE_C_INT = sqlite3VdbeExecProgressCheck(pVdbe)
        If loopProgressCode <> SQLITE_OK Then _
            Return sqlite3VdbeExecError(pVdbe, loopProgressCode)
        If pVdbe->db->mallocFailed <> 0 Then _
            Return sqlite3VdbeExecError(pVdbe, SQLITE_NOMEM)
        pVdbe->pc = nextCounter
        programCounter = nextCounter
    Wend

    Dim finalProgressCode As SQLITE_C_INT = sqlite3VdbeExecProgressCheck(pVdbe)
    If finalProgressCode <> SQLITE_OK Then _
        Return sqlite3VdbeExecError(pVdbe, finalProgressCode)
    Dim execFinishResult As SQLITE_C_INT = _
        sqlite3VdbeExecFinish(pVdbe, SQLITE_OK, OE_ABORT)
    sqlite3VdbeLeave(pVdbe)
    Return execFinishResult
End Function

#ifdef SQLITE_DEBUG
Private Sub memTracePrint(ByVal pMem As SqliteVdbeMem Ptr)
    If pMem = 0 Then
        sqlite3VdbeExecDebugPrintf(StrPtr(!" <null>"))
        Exit Sub
    End If

    Dim flags As ULongInt = CULngInt(pMem->flags)
    If (flags And MEM_UNDEFINED) <> 0 Then
        sqlite3VdbeExecDebugPrintf(StrPtr(!" undefined"))
    ElseIf (flags And MEM_NULL) <> 0 Then
        If (flags And MEM_ZERO) <> 0 Then
            sqlite3VdbeExecDebugPrintf(StrPtr(!" NULL-nochng"))
        Else
            sqlite3VdbeExecDebugPrintf(StrPtr(!" NULL"))
        End If
    ElseIf (flags And (MEM_INT Or MEM_STR)) = (MEM_INT Or MEM_STR) Then
        sqlite3VdbeExecDebugPrintf(StrPtr(!" si:%lld"), pMem->u.i)
    ElseIf (flags And MEM_INTREAL) <> 0 Then
        sqlite3VdbeExecDebugPrintf(StrPtr(!" ir:%lld"), pMem->u.i)
    ElseIf (flags And MEM_INT) <> 0 Then
        sqlite3VdbeExecDebugPrintf(StrPtr(!" i:%lld"), pMem->u.i)
#ifndef SQLITE_OMIT_FLOATING_POINT
    ElseIf (flags And MEM_REAL) <> 0 Then
        sqlite3VdbeExecDebugPrintf(StrPtr(!" r:%.17g"), pMem->u.r)
#endif
    ElseIf sqlite3VdbeMemIsRowSet(pMem) <> 0 Then
        sqlite3VdbeExecDebugPrintf(StrPtr(!" (rowset)"))
    Else
        Dim buffer(0 To 999) As UByte
        Dim accumulator As sqlite3_str
        sqlite3StrAccumInit(@accumulator, 0, @buffer(0), SizeOf(buffer), 0)
        sqlite3VdbeMemPrettyPrint(pMem, @accumulator)
        Dim zText As ZString Ptr = sqlite3StrAccumFinish(@accumulator)
        If zText <> 0 Then sqlite3VdbeExecDebugPrintf(StrPtr(!" %s"), zText)
    End If

    If (flags And MEM_SUBTYPE) <> 0 Then _
        sqlite3VdbeExecDebugPrintf(StrPtr(!" subtype=0x%02x"), CInt(pMem->eSubtype))
End Sub

Private Sub registerTrace( _
    ByVal registerNumber As SQLITE_C_INT, _
    ByVal pMem As SqliteVdbeMem Ptr _
)
    If pMem = 0 Then Exit Sub
    sqlite3VdbeExecDebugPrintf(StrPtr(!"R[%d] = "), registerNumber)
    memTracePrint(pMem)
    If pMem->pScopyFrom <> 0 Then
        If pMem->bScopy = 0 Then _
            sqlite3DebugAssert(StrPtr("Mem copy source is marked as a shallow copy"))
        Dim byteDistance As Integer = _
            CPtr(UByte Ptr, pMem->pScopyFrom) - CPtr(UByte Ptr, pMem)
        Dim elementSize As Integer = SizeOf(SqliteVdbeMem)
        If elementSize <= 0 OrElse byteDistance Mod elementSize <> 0 Then
            sqlite3DebugAssert(StrPtr("Mem shallow-copy pointer has a valid array offset"))
        Else
            Dim sourceRegister As SQLITE_C_INT = registerNumber + byteDistance \ elementSize
            sqlite3VdbeExecDebugPrintf(StrPtr(!" <== R[%d]"), sourceRegister)
        End If
    End If
    sqlite3VdbeExecDebugPrintf(StrPtr(!"\n"))
    sqlite3VdbeCheckMemInvariants(pMem)
End Sub

Sub sqlite3PrintMem CDecl Alias "sqlite3PrintMem" ( _
    ByVal pMem As SqliteVdbeMem Ptr _
)
    memTracePrint(pMem)
    sqlite3VdbeExecDebugPrintf(StrPtr(!"\n"))
End Sub

Sub sqlite3VdbeRegisterDump CDecl Alias "sqlite3VdbeRegisterDump" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
    If pVdbe = 0 OrElse pVdbe->aMem = 0 OrElse pVdbe->nMem <= 1 Then Exit Sub
    For registerNumber As SQLITE_C_INT = 1 To pVdbe->nMem - 1
        registerTrace(registerNumber, @pVdbe->aMem[registerNumber])
    Next
End Sub
#endif

/' end of sqlite3_vdbe_exec.bas '/
