/'
    Project: SQLite FreeBASIC port

    File: sqlite3_agginfo_types.bi

    Purpose:

        Define the aggregate-analysis records used during SELECT planning.

    Responsibilities:

        - Match AggInfo column and function entries and their owner record.
        - Preserve the fixed fields used by expression resolution and planning.

    This file intentionally does NOT contain:

        - Aggregate expression analysis or bytecode generation.
        - Ownership logic for the flexible column and function arrays.
'/

#ifndef SQLITE3_FB_AGGINFO_TYPES_BI
#define SQLITE3_FB_AGGINFO_TYPES_BI

#include once "sqlite3_expr_types.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_result.bi"

Type SqliteAggInfoColumn
    pTab As SqliteTable Ptr
    pCExpr As SqliteExpr Ptr
    iTable As SQLITE_C_INT
    iColumn As SQLITE_C_INT
    iSorterColumn As SQLITE_C_INT
End Type

Type SqliteAggInfoFunction
    pFExpr As SqliteExpr Ptr
    pFunc As SqliteFuncDef Ptr
    iDistinct As SQLITE_C_INT
    iDistAddr As SQLITE_C_INT
    iOBTab As SQLITE_C_INT
    bOBPayload As u8
    bOBUnique As u8
    bUseSubtype As u8
End Type

Type SqliteAggInfo
    directMode As u8
    useSortingIdx As u8
    nSortingColumn As u32
    sortingIdx As SQLITE_C_INT
    sortingIdxPTab As SQLITE_C_INT
    iFirstReg As SQLITE_C_INT
    pGroupBy As SqliteExprList Ptr
    aCol As SqliteAggInfoColumn Ptr
    nColumn As SQLITE_C_INT
    nAccumulator As SQLITE_C_INT
    aFunc As SqliteAggInfoFunction Ptr
    nFunc As SQLITE_C_INT
    selId As u32
#ifdef SQLITE_DEBUG
    pSelect As SqliteSelect Ptr
#endif
End Type

#endif

/' end of sqlite3_agginfo_types.bi '/
