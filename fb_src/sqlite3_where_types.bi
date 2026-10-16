/'
    Project: SQLite FreeBASIC port

    File: sqlite3_where_types.bi

    Purpose:

        Define the query-planner state used by WHERE loop generation.

    Responsibilities:

        - Retain the layout of WhereLoop, WhereLevel, and WhereInfo.
        - Model clause terms, cursor masks, and planner-owned helper records.
        - Keep opaque pointers at the same size as their C counterparts.
        - Declare shared index-loop helpers used across planner modules.
        - Declare shared Bloom-filter bytecode explanation used by WHERE code.

    This file intentionally does NOT contain:

        - Query planning or VDBE instruction generation.
        - SQLite's optional STAT4 sample and debug tracing payloads.
'/ 

#ifndef SQLITE3_FB_WHERE_TYPES_BI
#define SQLITE3_FB_WHERE_TYPES_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_walker.bi"
#include once "sqlite3_vdbe_core.bi"

' Match sqliteInt.h: the trace-enabled bit also selects WhereLoop fields.
#ifndef WHERETRACE_ENABLED
#if defined(SQLITE_DEBUG) AndAlso (defined(SQLITE_TEST) OrElse defined(SQLITE_ENABLE_WHERETRACE))
#define WHERETRACE_ENABLED 1
#else
#define WHERETRACE_ENABLED 0
#endif
#endif

#define SQLITE_WHERE_BMS 64

' Distinct execution modes shared between the WHERE planner and SELECT loop.
#define WHERE_DISTINCT_NOOP 0
#define WHERE_DISTINCT_UNIQUE 1
#define WHERE_DISTINCT_ORDERED 2
#define WHERE_DISTINCT_UNORDERED 3

' Control flags used when SELECT asks WHERE to optimize aggregate DISTINCT.
#define WHERE_GROUPBY &H0040
#define WHERE_WANT_DISTINCT &H0100
#define WHERE_SORTBYGROUP &H0200
#define WHERE_AGG_DISTINCT &H0400

' Match sqliteInt.h dbOptFlags: allow identical DISTINCT and ORDER BY lists
' to share the GROUP BY processing path.
#define SQLITE_GroupByOrder &H00000004

' These flags let a one-column min() or max() use index order and stop early.
#define WHERE_ORDERBY_MIN &H0001
#define WHERE_ORDERBY_MAX &H0002
#define SQLITE_MINMAXOPT &H00010000

Type SqliteWhereTerm As SqliteWhereTermRecord
Type SqliteWhereClause As SqliteWhereClauseRecord
Type SqliteWhereInfo As SqliteWhereInfoRecord
Type SqliteInLoop As SqliteInLoopRecord

' Return codes from sqlite3FindInIndex().
#define IN_INDEX_ROWID 1
#define IN_INDEX_EPH 2
#define IN_INDEX_INDEX_ASC 3
#define IN_INDEX_INDEX_DESC 4
#define IN_INDEX_NOOP 5
#define IN_INDEX_LOOP &H0004

' WhereLoop flags used by index equality-term generation.
#define WHERE_COLUMN_IN &H00000004
#define WHERE_IPK &H00000100
#define WHERE_INDEXED &H00000200
#define WHERE_VIRTUALTABLE &H00000400
#define WHERE_IN_ABLE &H00000800
#define WHERE_MULTI_OR &H00002000
#define WHERE_IN_EARLYOUT &H00040000
#define WHERE_IN_SEEKSCAN &H00100000
#define WHERE_TRANSCONS &H00200000
#define WHERE_IDX_ONLY &H00000040 ' Use index-only access when table columns are covered.
#define WHERE_EXPRIDX &H04000000 ' Expression-index coverage keeps the table cursor open.
#define WO_EQUIV &H0800

' RIGHT JOIN loop generation reads these stable WhereTerm flag values.
#define TERM_VIRTUAL &H0002
#define TERM_SLICE &H8000
#define WO_ROWVAL &H2000
#define WHERE_RIGHT_JOIN &H1000

Type SqliteSrcListRecord
    nSrc As SQLITE_C_INT
    nAlloc As u32
    a(0 To 0) As SqliteSrcItem
End Type

Type SqliteWhereMemBlock
    pNext As Any Ptr
    sz As sqlite3_uint64
End Type

Type SqliteWhereRightJoin
    iMatch As SQLITE_C_INT
    regBloom As SQLITE_C_INT
    regReturn As SQLITE_C_INT
    addrSubrtn As SQLITE_C_INT
    endSubrtn As SQLITE_C_INT
End Type

Type SqliteWhereLoopBtree
    nEq As u16
    nBtm As u16
    nTop As u16
    nDistinctCol As u16
    pIndex As Any Ptr
    pOrderBy As Any Ptr
End Type

Type SqliteWhereLoopVtab
    idxNum As SQLITE_C_INT
    flags As u32
    isOrdered As Byte
    omitMask As u16
    idxStr As Any Ptr
    mHandleIn As u32
End Type

Union SqliteWhereLoopUnion
    btree As SqliteWhereLoopBtree
    vtab As SqliteWhereLoopVtab
End Union

Type SqliteWhereLoop
    prereq As sqlite3_uint64
    maskSelf As sqlite3_uint64
#ifdef SQLITE_DEBUG
    cId As Byte
#endif
    iTab As u8
    iSortIdx As u8
    rSetup As Short
    rRun As Short
    nOut As Short
    u As SqliteWhereLoopUnion
    wsFlags As u32
    nLTerm As u16
    nSkip As u16
    nLSlot As u16
#if WHERETRACE_ENABLED
    rStarDelta As Short
#endif
    aLTerm As SqliteWhereTerm Ptr Ptr
    pNextLoop As Any Ptr
    aLTermSpace(0 To 2) As SqliteWhereTerm Ptr
End Type

Type SqliteWhereLevelIn
    nIn As SQLITE_C_INT
    aInLoop As SqliteInLoop Ptr
End Type

Type SqliteInLoopRecord
    iCur As SQLITE_C_INT
    addrInTop As SQLITE_C_INT
    iBase As SQLITE_C_INT
    nPrefix As SQLITE_C_INT
    eEndLoopOp As u8
End Type

Union SqliteWhereLevelUnion
    in As SqliteWhereLevelIn
    pCoveringIdx As Any Ptr
End Union

Type SqliteWhereLevel
    iLeftJoin As SQLITE_C_INT
    iTabCur As SQLITE_C_INT
    iIdxCur As SQLITE_C_INT
    addrBrk As SQLITE_C_INT
    addrHalt As SQLITE_C_INT
    addrNxt As SQLITE_C_INT
    addrSkip As SQLITE_C_INT
    addrCont As SQLITE_C_INT
    addrFirst As SQLITE_C_INT
    addrBody As SQLITE_C_INT
    regBignull As SQLITE_C_INT
    addrBignull As SQLITE_C_INT
#ifndef SQLITE_LIKE_DOESNT_MATCH_BLOBS
    iLikeRepCntr As u32
    addrLikeRep As SQLITE_C_INT
#endif
    regFilter As SQLITE_C_INT
    pRJ As Any Ptr
    iFrom As u8
    op As u8
    p3 As u8
    p5 As u8
    p1 As SQLITE_C_INT
    p2 As SQLITE_C_INT
    u As SqliteWhereLevelUnion
    pWLoop As SqliteWhereLoop Ptr
    notReady As sqlite3_uint64
#ifdef SQLITE_ENABLE_STMT_SCANSTATUS
    addrVisit As SQLITE_C_INT
#endif
End Type

Type SqliteWhereTermX
    leftColumn As SQLITE_C_INT
    iField As SQLITE_C_INT
End Type

Union SqliteWhereTermUnion
    x As SqliteWhereTermX
    pOrInfo As Any Ptr
    pAndInfo As Any Ptr
End Union

Type SqliteWhereTermRecord
    pExpr As SqliteExpr Ptr
    pWC As SqliteWhereClause Ptr
    truthProb As Short
    wtFlags As u16
    eOperator As u16
    nChild As u8
    eMatchOp As u8
    iParent As SQLITE_C_INT
    leftCursor As SQLITE_C_INT
#ifdef SQLITE_DEBUG
    iTerm As SQLITE_C_INT
#endif
    u As SqliteWhereTermUnion
    prereqRight As sqlite3_uint64
    prereqAll As sqlite3_uint64
End Type

Type SqliteWhereClauseRecord
    pWInfo As SqliteWhereInfo Ptr
    pOuter As SqliteWhereClause Ptr
    op As u8
    hasOr As u8
    nTerm As SQLITE_C_INT
    nSlot As SQLITE_C_INT
    nBase As SQLITE_C_INT
    a As SqliteWhereTerm Ptr
#ifdef SQLITE_SMALL_STACK
    aStatic(0 To 0) As SqliteWhereTerm
#else
    aStatic(0 To 7) As SqliteWhereTerm
#endif
End Type

Type SqliteWhereOrInfo
    wc As SqliteWhereClause
    indexable As sqlite3_uint64
End Type

Type SqliteWhereAndInfo
    wc As SqliteWhereClause
End Type

Type SqliteWhereMaskSet
    bVarSelect As SQLITE_C_INT
    n As SQLITE_C_INT
    ix(0 To SQLITE_WHERE_BMS - 1) As SQLITE_C_INT
End Type

Type SqliteWhereOrCost
    prereq As sqlite3_uint64
    rRun As Short
    nOut As Short
End Type

Type SqliteWhereOrSet
    n As u16
    a(0 To 2) As SqliteWhereOrCost
End Type

Type SqliteWhereScan
    pOrigWC As Any Ptr
    pWC As Any Ptr
    zCollName As Const ZString Ptr
    pIdxExpr As Any Ptr
    k As SQLITE_C_INT
    opMask As u32
    idxaff As Byte
    iEquiv As u8
    nEquiv As u8
    aiCur(0 To 10) As SQLITE_C_INT
    aiColumn(0 To 10) As Short
End Type

' WHERE-term scanner entry points are shared by index and loop planning.
Declare Function whereScanNext CDecl Alias "whereScanNext" ( _
    ByVal pScan As SqliteWhereScan Ptr _
) As SqliteWhereTerm Ptr
Declare Function sqlite3WhereFindTerm CDecl Alias "sqlite3WhereFindTerm" ( _
    ByVal pWhereClause As SqliteWhereClause Ptr, _
    ByVal cursorNumber As SQLITE_C_INT, _
    ByVal columnNumber As SQLITE_C_INT, _
    ByVal prerequisiteMask As sqlite3_uint64, _
    ByVal operatorMask As SQLITE_C_UINT, _
    ByVal pIndex As SqliteIndex Ptr _
) As SqliteWhereTerm Ptr
Declare Function whereScanInit CDecl Alias "whereScanInit" ( _
    ByVal pScan As SqliteWhereScan Ptr, _
    ByVal pWhereClause As SqliteWhereClause Ptr, _
    ByVal cursorNumber As SQLITE_C_INT, _
    ByVal columnNumber As SQLITE_C_INT, _
    ByVal operatorMask As u32, _
    ByVal pIndex As SqliteIndex Ptr _
) As SqliteWhereTerm Ptr
Declare Function whereClauseInsert CDecl Alias "whereClauseInsert" ( _
    ByVal pWhereClause As SqliteWhereClause Ptr, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal termFlags As u16 _
) As SQLITE_C_INT
Declare Function sqlite3WhereExprUsageNN CDecl Alias "sqlite3WhereExprUsageNN" ( _
    ByVal pMaskSet As SqliteWhereMaskSet Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As sqlite3_uint64
Declare Function sqlite3WhereExprUsageFull CDecl Alias "sqlite3WhereExprUsageFull" ( _
    ByVal pMaskSet As SqliteWhereMaskSet Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As sqlite3_uint64
Declare Function sqlite3WhereExprUsage CDecl Alias "sqlite3WhereExprUsage" ( _
    ByVal pMaskSet As SqliteWhereMaskSet Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As sqlite3_uint64
Declare Function sqlite3WhereExprListUsage CDecl Alias "sqlite3WhereExprListUsage" ( _
    ByVal pMaskSet As SqliteWhereMaskSet Ptr, _
    ByVal pExprList As SqliteExprList Ptr _
) As sqlite3_uint64
Declare Sub whereLoopClearUnion CDecl Alias "whereLoopClearUnion" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pLoop As SqliteWhereLoop Ptr _
)
Declare Sub whereLoopDelete CDecl Alias "whereLoopDelete" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pLoop As SqliteWhereLoop Ptr _
)

Type SqliteWhereLoopBuilder
    pWInfo As Any Ptr
    pWC As Any Ptr
    pNew As SqliteWhereLoop Ptr
    pOrSet As Any Ptr
#ifdef SQLITE_ENABLE_STAT4
    pRec As Any Ptr
    nRecValid As SQLITE_C_INT
#endif
    bldFlags1 As u8
    bldFlags2 As u8
    iPlanLimit As u32
End Type

Declare Function whereLoopInsert CDecl Alias "whereLoopInsert" ( _
    ByVal pBuilder As SqliteWhereLoopBuilder Ptr, _
    ByVal pTemplate As SqliteWhereLoop Ptr _
) As SQLITE_C_INT
Declare Function whereLoopAddVirtualOne CDecl Alias "whereLoopAddVirtualOne" ( _
    ByVal pBuilder As SqliteWhereLoopBuilder Ptr, _
    ByVal prerequisiteMask As sqlite3_uint64, _
    ByVal usableMask As sqlite3_uint64, _
    ByVal excludedOperators As u16, _
    ByVal pIndexInfo As SqliteIndexInfo Ptr, _
    ByVal noOmitMask As u16, _
    ByVal pUsesIn As SQLITE_C_INT Ptr, _
    ByVal pRetryLimit As SQLITE_C_INT Ptr _
) As SQLITE_C_INT

Type SqliteWherePath
    maskLoop As sqlite3_uint64
    revLoop As sqlite3_uint64
    nRow As Short
    rCost As Short
    rUnsort As Short
    isOrdered As Byte
    aLoop As Any Ptr
End Type

Type SqliteWhereInfoRecord
    pParse As SqliteParseContext Ptr
    pTabList As SqliteSrcList Ptr
    pOrderBy As SqliteExprList Ptr
    pResultSet As SqliteExprList Ptr
#if WHERETRACE_ENABLED
    pWhere As Any Ptr
#endif
    pSelect As SqliteSelect Ptr
    aiCurOnePass(0 To 1) As SQLITE_C_INT
    iContinue As SQLITE_C_INT
    iBreak As SQLITE_C_INT
    savedNQueryLoop As SQLITE_C_INT
    wctrlFlags As u16
    iLimit As Short
    nLevel As u8
    nOBSat As Byte
    eOnePass As u8
    eDistinct As u8
    flags As u32
    nRowOut As Short
#if WHERETRACE_ENABLED
    rTotalCost As Short
#endif
    iTop As SQLITE_C_INT
    iEndWhere As SQLITE_C_INT
    pLoops As Any Ptr
    pMemToFree As Any Ptr
    revMask As sqlite3_uint64
    sWC As SqliteWhereClause
    sMaskSet As SqliteWhereMaskSet
    a(0 To 0) As SqliteWhereLevel
End Type

' Temporary allocations are reclaimed with the owning WhereInfo object.
Declare Function sqlite3WhereMalloc CDecl Alias "sqlite3WhereMalloc" ( _
    ByVal pWhereInfo As SqliteWhereInfo Ptr, _
    ByVal byteCount As sqlite3_uint64 _
) As Any Ptr
Declare Function sqlite3WhereRealloc CDecl Alias "sqlite3WhereRealloc" ( _
    ByVal pWhereInfo As SqliteWhereInfo Ptr, _
    ByVal pOld As Any Ptr, _
    ByVal byteCount As sqlite3_uint64 _
) As Any Ptr

' This allocator is shared with virtual-table planner code in another module.
Declare Function allocateIndexInfo CDecl Alias "allocateIndexInfo" ( _
    ByVal pWhereInfo As SqliteWhereInfo Ptr, _
    ByVal pWhereClause As SqliteWhereClause Ptr, _
    ByVal unusableMask As sqlite3_uint64, _
    ByVal pSource As SqliteSrcItem Ptr, _
    ByVal pMaskNoOmit As u16 Ptr _
) As SqliteIndexInfo Ptr

Declare Function sqlite3WhereGetMask CDecl Alias "sqlite3WhereGetMask" ( _
    ByVal pMaskSet As SqliteWhereMaskSet Ptr, _
    ByVal cursorNumber As SQLITE_C_INT _
) As sqlite3_uint64
Declare Sub sqlite3WhereClauseClear CDecl Alias "sqlite3WhereClauseClear" ( _
    ByVal pWhereClause As SqliteWhereClause Ptr _
)
Declare Function sqlite3WhereLoopBloomable CDecl Alias "sqlite3WhereLoopBloomable" ( _
    ByVal pLoop As Const SqliteWhereLoop Ptr _
) As SQLITE_C_INT
Declare Function sqlite3WhereExplainBloomFilter CDecl Alias "sqlite3WhereExplainBloomFilter" ( _
    ByVal pParse As Const SqliteParseContext Ptr, _
    ByVal pWhere As Const SqliteWhereInfo Ptr, _
    ByVal pLevel As Const SqliteWhereLevel Ptr _
) As SQLITE_C_INT
Declare Function sqlite3WhereCodeOneLoopStart CDecl Alias "sqlite3WhereCodeOneLoopStart" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pWhereInfo As SqliteWhereInfo Ptr, _
    ByVal levelIndex As SQLITE_C_INT, _
    ByVal pLevel As SqliteWhereLevel Ptr, _
    ByVal notReadyMask As sqlite3_uint64 _
) As sqlite3_uint64

' Shared planner helpers retained in their owning modules for C2FB batches.
Declare Function columnIsGoodIndexCandidate CDecl Alias "columnIsGoodIndexCandidate" ( _
    ByVal pTable As Const SqliteTable Ptr, _
    ByVal columnNumber As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function whereOrInsert CDecl Alias "whereOrInsert" ( _
    ByVal pSet As SqliteWhereOrSet Ptr, _
    ByVal prerequisites As sqlite3_uint64, _
    ByVal runCost As Short, _
    ByVal outputRows As Short _
) As SQLITE_C_INT
Declare Sub whereOrMove CDecl Alias "whereOrMove" ( _
    ByVal pDestination As SqliteWhereOrSet Ptr, _
    ByVal pSource As Const SqliteWhereOrSet Ptr _
)
Declare Function whereLoopAddBtreeIndex CDecl Alias "whereLoopAddBtreeIndex" ( _
    ByVal pBuilder As SqliteWhereLoopBuilder Ptr, _
    ByVal pSource As SqliteSrcItem Ptr, _
    ByVal pIndex As SqliteIndex Ptr, _
    ByVal extraRegisterCount As Short _
) As SQLITE_C_INT
Declare Function indexMightHelpWithOrderBy CDecl Alias "indexMightHelpWithOrderBy" ( _
    ByVal pBuilder As SqliteWhereLoopBuilder Ptr, _
    ByVal pIndex As SqliteIndex Ptr, _
    ByVal tableCursor As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function whereUsablePartialIndex CDecl Alias "whereUsablePartialIndex" ( _
    ByVal tableCursor As SQLITE_C_INT, _
    ByVal joinType As u8, _
    ByVal pWhereClause As SqliteWhereClause Ptr, _
    ByVal pPartialIndexExpression As SqliteExpr Ptr _
) As SQLITE_C_INT
Declare Function whereIsCoveringIndex CDecl Alias "whereIsCoveringIndex" ( _
    ByVal pWhereInfo As SqliteWhereInfo Ptr, _
    ByVal pIndex As SqliteIndex Ptr, _
    ByVal tableCursor As SQLITE_C_INT _
) As u32
Declare Sub wherePartIdxExpr CDecl Alias "wherePartIdxExpr" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pIndex As SqliteIndex Ptr, _
    ByVal pPart As SqliteExpr Ptr, _
    ByVal pMask As sqlite3_uint64 Ptr, _
    ByVal indexCursor As SQLITE_C_INT, _
    ByVal pItem As SqliteSrcItem Ptr _
)
Declare Function whereLoopAddVirtual CDecl Alias "whereLoopAddVirtual" ( _
    ByVal pBuilder As SqliteWhereLoopBuilder Ptr, _
    ByVal prerequisites As sqlite3_uint64, _
    ByVal unusableMask As sqlite3_uint64 _
) As SQLITE_C_INT
Declare Function exprMightBeIndexed2 CDecl Alias "exprMightBeIndexed2" ( _
    ByVal pFrom As SqliteSrcList Ptr, _
    ByVal aiCursorAndColumn As SQLITE_C_INT Ptr, _
    ByVal pExpression As SqliteExpr Ptr, _
    ByVal firstSourceIndex As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Sub sqlite3WhereRightJoinLoop CDecl Alias "sqlite3WhereRightJoinLoop" ( _
    ByVal pWhereInfo As SqliteWhereInfo Ptr, _
    ByVal levelIndex As SQLITE_C_INT, _
    ByVal pLevel As SqliteWhereLevel Ptr _
)

#endif

/' end of sqlite3_where_types.bi '/
