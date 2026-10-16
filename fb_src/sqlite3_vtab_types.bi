/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vtab_types.bi

    Purpose:

        Define virtual-table ABI records used by xBestIndex and the planner.

    Responsibilities:

        - Preserve the public sqlite3_index_info field order and widths.
        - Preserve the private tail used by SQLite's virtual-table planner.
        - Type the xBestIndex callback while retaining the public module layout.
        - Preserve the public sqlite3_vtab_cursor base record.
        - Describe the internal VTable and module records used by where.c.

    This file intentionally does NOT contain:

        - Virtual-table planning or lifecycle callback invocation.
        - The allocation policy for variable-length constraint arrays.
'/

#ifndef SQLITE3_FB_VTAB_TYPES_BI
#define SQLITE3_FB_VTAB_TYPES_BI

#include once "sqlite3_types.bi"

Type SqliteIndexConstraint
    iColumn As SQLITE_C_INT
    op As UByte
    usable As UByte
    iTermOffset As SQLITE_C_INT
End Type

Type SqliteIndexOrderBy
    iColumn As SQLITE_C_INT
    desc As UByte
End Type

Type SqliteIndexConstraintUsage
    argvIndex As SQLITE_C_INT
    omit As UByte
    ' Preserve the C array stride: int, byte, then three padding bytes.
    padding(0 To 2) As UByte
End Type

Type SqliteIndexInfo
    nConstraint As SQLITE_C_INT
    aConstraint As SqliteIndexConstraint Ptr
    nOrderBy As SQLITE_C_INT
    aOrderBy As SqliteIndexOrderBy Ptr
    aConstraintUsage As SqliteIndexConstraintUsage Ptr
    idxNum As SQLITE_C_INT
    idxStr As ZString Ptr
    needToFreeIdxStr As SQLITE_C_INT
    orderByConsumed As SQLITE_C_INT
    estimatedCost As Double
    estimatedRows As sqlite3_int64
    idxFlags As SQLITE_C_INT
    colUsed As sqlite3_uint64
End Type

' SQLite appends this variable-length record after SqliteIndexInfo.
Type SqliteHiddenIndexInfo
    pWC As Any Ptr
    pParse As Any Ptr
    eDistinct As SQLITE_C_INT
    mIn As u32
    mHandleIn As u32
    aRhs(0 To 0) As Any Ptr
End Type

Type SqliteModuleBestIndexProc As Function CDecl ( _
    ByVal pVtab As Any Ptr, _
    ByVal pIndexInfo As SqliteIndexInfo Ptr _
) As SQLITE_C_INT

Type SqliteModuleCallbacks
    iVersion As SQLITE_C_INT
    xCreate As Any Ptr
    xConnect As Any Ptr
    xBestIndex As SqliteModuleBestIndexProc
    xDisconnect As Any Ptr
    xDestroy As Any Ptr
    xOpen As Any Ptr
    xClose As Any Ptr
    xFilter As Any Ptr
    xNext As Any Ptr
    xEof As Any Ptr
    xColumn As Any Ptr
    xRowid As Any Ptr
    xUpdate As Any Ptr
    xBegin As Any Ptr
    xSync As Any Ptr
    xCommit As Any Ptr
    xRollback As Any Ptr
    xFindFunction As Any Ptr
    xRename As Any Ptr
    xSavepoint As Any Ptr
    xRelease As Any Ptr
    xRollbackTo As Any Ptr
    xShadowName As Any Ptr
    xIntegrity As Any Ptr
End Type

Type SqliteVtab
    pModule As Const SqliteModuleCallbacks Ptr
    nRef As SQLITE_C_INT
    zErrMsg As ZString Ptr
End Type

Type SqliteVtabCursor
    pVtab As SqliteVtab Ptr
End Type

Type SqliteModule
    pModule As Const SqliteModuleCallbacks Ptr
    zName As Const ZString Ptr
    nRefModule As SQLITE_C_INT
    pAux As Any Ptr
    xDestroy As Any Ptr
    pEpoTab As Any Ptr
End Type

Type SqliteVTable
    db As Any Ptr
    pMod As SqliteModule Ptr
    pVtab As SqliteVtab Ptr
    nRef As SQLITE_C_INT
    bConstraint As u8
    bAllSchemas As u8
    eVtabRisk As u8
    iSavepoint As SQLITE_C_INT
    pNext As Any Ptr
End Type

#endif

/' end of sqlite3_vtab_types.bi '/
