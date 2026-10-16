/'
    Project: SQLite FreeBASIC port

    File: sqlite3_walk_contexts.bi

    Purpose:

        Define small records passed through tree walks and SELECT rewrites.

    Responsibilities:

        - Match the index-coverage context stored in Walker's private union.
        - Match the reference/exclusion state for source-list scans.
        - Match the nested join-check state used by SELECT walkers.
        - Match the substitution state used while flattening SELECT terms.
        - Match the five-pointer WindowRewrite state passed through Walker.
        - Match deferred sorter row-loading state passed by SELECT codegen.

    This file intentionally does NOT contain:

        - Walker traversal logic or query planning.
        - Ownership of the arrays referenced by these contexts.
'/ 

#ifndef SQLITE3_FB_WALK_CONTEXTS_BI
#define SQLITE3_FB_WALK_CONTEXTS_BI

#include once "sqlite3_where_types.bi"

Type SqliteIdxCover
    pIdx As SqliteIndex Ptr
    iCur As SQLITE_C_INT
End Type

Type SqliteSubstContext
    pParse As SqliteParseContext Ptr
    iTable As SQLITE_C_INT
    iNewTable As SQLITE_C_INT
    isOuterJoin As SQLITE_C_INT
    nSelDepth As SQLITE_C_INT
    pEList As SqliteExprList Ptr
    pCList As SqliteExprList Ptr
End Type

Type SqliteRowLoadInfo
    regResult As SQLITE_C_INT
    ecelFlags As u8
#ifdef SQLITE_ENABLE_SORTER_REFERENCES
    pExtra As SqliteExprList Ptr
    regExtraResult As SQLITE_C_INT
#endif
End Type

Type SqliteDeferredCsr
    pTab As SqliteTable Ptr
    iCsr As SQLITE_C_INT
    nKey As SQLITE_C_INT
End Type

Type SqliteSortContext
    pOrderBy As SqliteExprList Ptr
    nOBSat As SQLITE_C_INT
    iECursor As SQLITE_C_INT
    regReturn As SQLITE_C_INT
    labelBkOut As SQLITE_C_INT
    addrSortIndex As SQLITE_C_INT
    labelDone As SQLITE_C_INT
    labelOBLopt As SQLITE_C_INT
    sortFlags As u8
#ifdef SQLITE_ENABLE_SORTER_REFERENCES
    nDefer As u8
    aDefer(0 To 3) As SqliteDeferredCsr
#endif
    pDeferredRowLoad As SqliteRowLoadInfo Ptr
#ifdef SQLITE_ENABLE_STMT_SCANSTATUS
    addrPush As SQLITE_C_INT
    addrPushEnd As SQLITE_C_INT
#endif
End Type

Type SqliteRefSrcList
    db As sqlite3 Ptr
    pRef As SqliteSrcList Ptr
    nExclude As sqlite3_int64
    aiExclude As SQLITE_C_INT Ptr
End Type

Type SqliteCheckOnContext
    pSrc As SqliteSrcList Ptr
    iJoin As SQLITE_C_INT
    bFuncArg As SQLITE_C_INT
    pParent As SqliteCheckOnContext Ptr
End Type

#ifndef SQLITE_OMIT_WINDOWFUNC
Type SqliteWindowRewriteContext
    pWin As SqliteWalkerWindow Ptr
    pSrc As SqliteSrcList Ptr
    pSub As SqliteExprList Ptr
    pTab As SqliteTable Ptr
    pSubSelect As SqliteSelect Ptr
End Type
#endif

#endif

/' end of sqlite3_walk_contexts.bi '/
