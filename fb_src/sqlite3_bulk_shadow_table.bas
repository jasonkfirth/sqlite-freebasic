/'
** 2001 September 15
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
*************************************************************************
** This file contains C code routines that are called by the SQLite parser
** when syntax rules are reduced.  The routines in this file handle the
** following kinds of SQL syntax:
**
**     CREATE TABLE
**     DROP TABLE
**     CREATE INDEX
**     DROP INDEX
**     creating ID lists
**     BEGIN TRANSACTION
**     COMMIT
**     ROLLBACK
'/

/'
    Project: SQLite FreeBASIC port
    File: sqlite3_bulk_shadow_table.bas

    Purpose:

        Determine whether a table name belongs to a virtual table module.

    Responsibilities:

        - Find the base table name before the last underscore.
        - Look up that table and delegate the suffix check to its module.

    This file intentionally does NOT contain:

        - Virtual-table module registration or shadow-table policy.
        - CREATE TABLE parsing or error-reporting policy.
'/
#lang "fb"

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_schema_types.bi"

Declare Function sqlite3FindTable CDecl Alias "sqlite3FindTable" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal zDatabase As Const ZString Ptr _
) As SqliteTable Ptr
Declare Function sqlite3IsShadowTableOf CDecl Alias "sqlite3IsShadowTableOf" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pTable As SqliteTable Ptr, _
    ByVal zName As Const ZString Ptr _
) As SQLITE_C_INT

#ifndef SQLITE_OMIT_VIRTUALTABLE
Function sqlite3ShadowTableName CDecl Alias "sqlite3ShadowTableName" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr _
) As SQLITE_C_INT
    If db = 0 OrElse zName = 0 Then Return 0

    Dim zNameBytes As Const UByte Ptr = CPtr(Const UByte Ptr, zName)
    Dim zLastSeparator As Const UByte Ptr = 0
    Dim nameOffset As sqlite3_uint64 = 0
    While zNameBytes[nameOffset] <> 0
        If zNameBytes[nameOffset] = Asc("_") Then _
            zLastSeparator = zNameBytes + nameOffset
        nameOffset += 1
    Wend
    If zLastSeparator = 0 Then Return 0

    Dim prefixLength As sqlite3_uint64 = _
        CPtr(Const UByte Ptr, zLastSeparator) - zNameBytes
    If prefixLength > &H7FFFFFFF Then Return 0

    Dim zBaseName As Any Ptr = sqlite3DbStrNDup( _
        db, zName, prefixLength)
    Dim pTable As SqliteTable Ptr = 0
    If zBaseName <> 0 Then
        pTable = sqlite3FindTable( _
            db, CPtr(Const ZString Ptr, zBaseName), 0)
    End If
    sqlite3DbFree(db, zBaseName)

    If pTable = 0 OrElse pTable->eTabType <> TABTYP_VTAB Then Return 0
    Return sqlite3IsShadowTableOf(db, pTable, zName)
End Function
#endif

/' end of sqlite3_bulk_shadow_table.bas '/
