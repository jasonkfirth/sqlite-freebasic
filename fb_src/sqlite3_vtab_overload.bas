/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vtab_overload.bas

    Purpose:

        Give virtual-table modules an opportunity to replace selected functions.

    Responsibilities:

        - Detect calls whose first argument is a virtual-table column.
        - Invoke the module's xFindFunction callback.
        - Allocate an ephemeral FuncDef with an owned copy of its function name.

    This file intentionally does NOT contain:

        - Virtual-table construction, planning, or transaction callbacks.
        - Runtime tests of third-party xFindFunction modules.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_vtab_types.bi"
#include once "sqlite3_result.bi"

Type SqliteVtabFindFunctionCallback As Function CDecl ( _
    ByVal pVtab As SqliteVtab Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal zName As Const ZString Ptr, _
    ByVal pScalarFunction As SqliteScalarFunction Ptr, _
    ByVal ppUserData As Any Ptr Ptr _
) As SQLITE_C_INT

Declare Function sqlite3GetVTable CDecl Alias "sqlite3GetVTable" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pTable As SqliteTable Ptr _
) As SqliteVTable Ptr
Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal z As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VtabOverloadMemcpy CDecl Alias "memcpy" ( _
    ByVal destination As Any Ptr, _
    ByVal source As Const Any Ptr, _
    ByVal byteCount As SQLITE_SIZE_T _
) As Any Ptr

Function sqlite3VtabOverloadFunction CDecl Alias "sqlite3VtabOverloadFunction" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pDefinition As SqliteFuncDef Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pExpr As SqliteExpr Ptr _
) As SqliteFuncDef Ptr
    If pDefinition = 0 OrElse pExpr = 0 Then Return pDefinition
    If pExpr->op <> TK_COLUMN Then Return pDefinition

    Dim pTable As SqliteTable Ptr = CPtr(SqliteTable Ptr, pExpr->y.pTab)
    If pTable = 0 OrElse pTable->eTabType <> TABTYP_VTAB Then _
        Return pDefinition

    Dim pVTable As SqliteVTable Ptr = sqlite3GetVTable(db, pTable)
    If pVTable = 0 OrElse pVTable->pVtab = 0 OrElse _
       pVTable->pVtab->pModule = 0 Then Return pDefinition

    Dim pModule As Const SqliteModuleCallbacks Ptr = pVTable->pVtab->pModule
    If pModule->xFindFunction = 0 Then Return pDefinition

    Dim xFindFunction As SqliteVtabFindFunctionCallback = _
        CPtr(SqliteVtabFindFunctionCallback, pModule->xFindFunction)
    Dim scalarFunction As SqliteScalarFunction = 0
    Dim userData As Any Ptr = 0
    If xFindFunction(pVTable->pVtab, argumentCount, pDefinition->zName, _
                     @scalarFunction, @userData) = 0 Then Return pDefinition

    Dim nameLength As SQLITE_C_INT = sqlite3Strlen30(pDefinition->zName)
    If nameLength < 0 Then Return pDefinition
    Dim allocationSize As sqlite3_uint64 = _
        SizeOf(SqliteFuncDef) + Cast(sqlite3_uint64, nameLength) + 1
    Dim pNew As SqliteFuncDef Ptr = CPtr(SqliteFuncDef Ptr, _
        sqlite3DbMallocZero(db, allocationSize))
    If pNew = 0 Then Return pDefinition

    *pNew = *pDefinition
    Dim zNameCopy As UByte Ptr = CPtr(UByte Ptr, pNew) + SizeOf(SqliteFuncDef)
    pNew->zName = CPtr(Const ZString Ptr, zNameCopy)
    sqlite3VtabOverloadMemcpy(zNameCopy, pDefinition->zName, _
                              Cast(SQLITE_SIZE_T, nameLength + 1))
    pNew->xSFunc = scalarFunction
    pNew->pUserData = userData
    pNew->funcFlags Or= SQLITE_FUNC_EPHEM
    Return pNew
End Function

/' end of sqlite3_vtab_overload.bas '/
