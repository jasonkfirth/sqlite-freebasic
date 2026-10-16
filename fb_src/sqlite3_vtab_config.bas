/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vtab_config.bas

    Purpose:

        Apply configuration requested by virtual-table constructors.

    Responsibilities:

        - Set constraint, innocuous, direct-only, and all-schema behavior.
        - Serialize access to the active constructor context with the DB mutex.
        - Report invalid operations through the normal connection error path.

    This file intentionally does NOT contain:

        - Virtual-table schema parsing or module callback dispatch.
        - Runtime validation of third-party virtual-table modules.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_vtab_types.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_mutex.bi"

#if defined(SQLITE_ENABLE_API_ARMOR)
Declare Function sqlite3SafetyCheckOk CDecl Alias "sqlite3SafetyCheckOk" ( _
    ByVal db As Any Ptr _
) As SQLITE_C_INT
#endif

Private Const SQLITE_VTABRISK_LOW As u8 = 0
Private Const SQLITE_VTABRISK_HIGH As u8 = 2

Private Type SqliteVtabConfigContext
    pVTable As SqliteVTable Ptr
    pTable As Any Ptr
    pPrior As Any Ptr
    bDeclared As SQLITE_C_INT
End Type

Function sqlite3_vtab_config CDecl Alias "sqlite3_vtab_config" ( _
    ByVal dbArgument As Any Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ... _
) As SQLITE_C_INT Export
    Dim db As sqlite3 Ptr = CPtr(sqlite3 Ptr, dbArgument)
    If db = 0 Then Return SQLITE_MISUSE

#if defined(SQLITE_ENABLE_API_ARMOR)
    If sqlite3SafetyCheckOk(db) = 0 Then Return SQLITE_MISUSE
#endif

    sqlite3_mutex_enter(db->mutex)
    Dim resultCode As SQLITE_C_INT = SQLITE_OK
    Dim pContext As SqliteVtabConfigContext Ptr = _
        CPtr(SqliteVtabConfigContext Ptr, db->pVtabCtx)

    If pContext = 0 OrElse pContext->pVTable = 0 Then
        resultCode = SQLITE_MISUSE
    Else
        Dim args As Cva_List
        Cva_Start(args, operation)
        Select Case operation
        Case SQLITE_VTAB_CONSTRAINT_SUPPORT
            pContext->pVTable->bConstraint = _
                Cast(u8, Cva_Arg(args, SQLITE_C_INT))
        Case SQLITE_VTAB_INNOCUOUS
            pContext->pVTable->eVtabRisk = SQLITE_VTABRISK_LOW
        Case SQLITE_VTAB_DIRECTONLY
            pContext->pVTable->eVtabRisk = SQLITE_VTABRISK_HIGH
        Case SQLITE_VTAB_USES_ALL_SCHEMAS
            pContext->pVTable->bAllSchemas = 1
        Case Else
            resultCode = SQLITE_MISUSE
        End Select
        Cva_End(args)
    End If

    If resultCode <> SQLITE_OK Then sqlite3Error(db, resultCode)
    sqlite3_mutex_leave(db->mutex)
    Return resultCode
End Function

/' end of sqlite3_vtab_config.bas '/
