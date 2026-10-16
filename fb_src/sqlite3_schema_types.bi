/'
    Project: SQLite FreeBASIC port

    File: sqlite3_schema_types.bi

    Purpose:

        Define the core table, column, and index records used by planning.

    Responsibilities:

        - Preserve field order and fixed-width types for schema records.
        - Keep optional sample data behind SQLite's STAT4 build condition.
        - Define the fixed IndexSample header used by STAT4 planner statistics.
        - Represent pointers to not-yet-ported schema records as opaque pointers.
        - Define the fixed index-iteration records used during INSERT checks.
        - Describe the stack-owned VtabCtx used while modules declare schemas.

    This file intentionally does NOT contain:

        - Schema object allocation, name resolution, or B-tree access.
        - A claim that all optional SQLite layouts are supported.
'/ 

#ifndef SQLITE3_FB_SCHEMA_TYPES_BI
#define SQLITE3_FB_SCHEMA_TYPES_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_fkey_types.bi"
#include once "sqlite3_vtab_types.bi"

' These values identify ordinary tables, virtual tables, and views in
' SqliteTable.eTabType, matching the private enum in src/sqliteInt.h.
#define TABTYP_NORM 0
#define TABTYP_VTAB 1
#define TABTYP_VIEW 2

' Column and table flags shared by schema construction and planner code.
#define COLFLAG_HIDDEN &H0002
#define COLFLAG_HASTYPE &H0004
#define COLFLAG_HASCOLL &H0200
#define COLFLAG_NOINSERT &H0062
#define COLFLAG_NOEXPAND &H0400
#define COLFLAG_PRIMKEY &H0001
#define COLFLAG_UNIQUE &H0008
#define COLFLAG_VIRTUAL &H0020
#define COLFLAG_STORED &H0040
#define COLFLAG_GENERATED (COLFLAG_VIRTUAL Or COLFLAG_STORED)
#define COLTYPE_CUSTOM 0
#define COLTYPE_ANY 1
#define COLTYPE_BLOB 2
#define COLTYPE_INT 3
#define COLTYPE_INTEGER 4
#define COLTYPE_REAL 5
#define COLTYPE_TEXT 6
#define SQLITE_N_STDTYPE 6
#define COLFLAG_SORTERREF &H0010
#define TF_HasHidden &H00000002
#define TF_Autoincrement &H00000008
#define TF_HasNotNull &H00000800
#define TF_OOOHidden &H00000400
#define TF_WithoutRowid &H00000080
#define TF_Ephemeral &H00004000
#define TF_NoVisibleRowid &H00000200
#define TF_Strict &H00010000

' Column.flags begins with C Column.notNull's four-bit conflict action.
#define SQLITE_COLUMN_NOTNULL_MASK &H0000000F

' Index.flags stores idxType in bits 0-1 and the remaining C bitfields above it.
#define SQLITE_INDEX_IDXTYPE_MASK &H0003
#define SQLITE_IDXTYPE_APPDEF 0
#define SQLITE_IDXTYPE_UNIQUE 1
#define SQLITE_INDEX_UNIQ_NOTNULL &H0008
#define SQLITE_INDEX_IS_COVERING &H0020
#define SQLITE_INDEX_BNOQUERY &H0100
#define SQLITE_INDEX_ASC_KEY_BUG &H0200
#define SQLITE_INDEX_HAS_VCOL &H0400
#define SQLITE_INDEX_HAS_EXPR &H0800

Type SqliteColumn
    zCnName As ZString Ptr
    flags As u32
    affinity As Byte
    szEst As u8
    hName As u8
    iDflt As u16
    colFlags As u16
End Type

Type SqliteTableTab
    addColOffset As SQLITE_C_INT
    pFKey As SqliteFKey Ptr
    pDfltList As Any Ptr
End Type

Type SqliteTableView
    pSelect As Any Ptr
End Type

Type SqliteTableVtab
    nArg As SQLITE_C_INT
    azArg As ZString Ptr Ptr
    p As SqliteVTable Ptr
End Type

Union SqliteTableUnion
    tab As SqliteTableTab
    view As SqliteTableView
    vtab As SqliteTableVtab
End Union

Type SqliteTable
    zName As ZString Ptr
    aCol As SqliteColumn Ptr
    pIndex As Any Ptr
    zColAff As ZString Ptr
    pCheck As Any Ptr
    tnum As SQLITE_C_UINT
    nTabRef As u32
    tabFlags As u32
    iPKey As Short
    nCol As Short
    nNVCol As Short
    nRowLogEst As Short
    szTabRow As Short
#ifdef SQLITE_ENABLE_COSTMULT
    costMult As Short
#endif
    keyConf As u8
    eTabType As u8
    u As SqliteTableUnion
    pTrigger As SqliteTrigger Ptr
    pSchema As Any Ptr
    aHx(0 To 15) As u8
End Type

' VtabCtx is stack-owned by the virtual-table constructor call. Its prior
' pointer links nested xCreate/xConnect invocations on the same connection.
Type SqliteVtabContext
    pVTable As SqliteVTable Ptr
    pTab As SqliteTable Ptr
    pPrior As Any Ptr
    bDeclared As SQLITE_C_INT
End Type

' STAT4 stores each sampled index key beside three row-count vectors.
Type SqliteIndexSample
    p As Any Ptr
    n As SQLITE_C_INT
    anEq As sqlite3_uint64 Ptr
    anLt As sqlite3_uint64 Ptr
    anDLt As sqlite3_uint64 Ptr
End Type

' Context passed to sqlite3_exec while loading sqlite_stat1 rows.
Type SqliteAnalysisInfo
    db As Any Ptr
    zDatabase As Const ZString Ptr
End Type

Type SqliteIndex
    zName As ZString Ptr
    aiColumn As Short Ptr
    aiRowLogEst As Short Ptr
    pTable As SqliteTable Ptr
    zColAff As ZString Ptr
    pNext As SqliteIndex Ptr
    pSchema As Any Ptr
    aSortOrder As u8 Ptr
    azColl As ZString Ptr Ptr
    pPartIdxWhere As Any Ptr
    aColExpr As Any Ptr
    tnum As SQLITE_C_UINT
    szIdxRow As Short
    nKeyCol As u16
    nColumn As u16
    onError As u8
    flags As u32
#ifdef SQLITE_ENABLE_STAT4
    nSample As SQLITE_C_INT
    mxSample As SQLITE_C_INT
    nSampleCol As SQLITE_C_INT
    aAvgEq As sqlite3_uint64 Ptr
    aSample As SqliteIndexSample Ptr
    aiRowEst As sqlite3_uint64 Ptr
    nRowEst0 As sqlite3_uint64
#endif
    colNotIdxed As sqlite3_uint64
End Type

Type SqliteIndexListTerm
    p As SqliteIndex Ptr
    ix As SQLITE_C_INT
End Type

Type SqliteIndexIteratorLink
    pIdx As SqliteIndex Ptr
End Type

Type SqliteIndexIteratorArray
    nIdx As SQLITE_C_INT
    aIdx As SqliteIndexListTerm Ptr
End Type

Union SqliteIndexIteratorUnion
    lx As SqliteIndexIteratorLink
    ax As SqliteIndexIteratorArray
End Union

Type SqliteIndexIterator
    eType As SQLITE_C_INT
    i As SQLITE_C_INT
    u As SqliteIndexIteratorUnion
End Type

#endif

/' end of sqlite3_schema_types.bi '/
