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
    File: sqlite3_bulk_objectname.bas

    Purpose:

        Validate names used for schema objects.

    Responsibilities:

        - Match schema initialization names against their stored SQL.
        - Reserve the sqlite_ namespace outside internal schema operations.
        - Reject shadow-table names when read-only shadow checks are enabled.

    This file intentionally does NOT contain:

        - Name allocation or table/index lookup.
        - Virtual-table module registration.
'/
#lang "fb"

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_schema_types.bi"

Declare Function sqlite3WritableSchema CDecl Alias "sqlite3WritableSchema" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
Declare Function sqlite3ReadOnlyShadowTables CDecl Alias "sqlite3ReadOnlyShadowTables" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
Declare Function sqlite3ShadowTableName CDecl Alias "sqlite3ShadowTableName" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_stricmp CDecl Alias "sqlite3_stricmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_strnicmp CDecl Alias "sqlite3_strnicmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr, _
    ByVal byteCount As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3ConfigExtraSchemaChecksEnabled CDecl Alias "sqlite3ConfigExtraSchemaChecksEnabled" () As SQLITE_C_INT

Dim Shared As Const ZString * 8 sqlite3ObjectNameReservedPrefix = "sqlite_"
Dim Shared As Const ZString * 64 sqlite3ObjectNameReservedError = _
    "object name reserved for internal use: %s"

Function sqlite3CheckObjectName CDecl Alias "sqlite3CheckObjectName" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal zType As Const ZString Ptr, _
    ByVal zTableName As Const ZString Ptr _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->db = 0 OrElse _
       zName = 0 OrElse zType = 0 Then Return SQLITE_MISUSE
    Dim db As sqlite3 Ptr = pParse->db

    ' SQLite defaults this process-wide schema consistency check on.
    Dim imposterTable As SQLITE_C_INT = _
        Cast(SQLITE_C_INT, (db->init.flags Shr 1) And 3)
    If sqlite3WritableSchema(db) <> 0 OrElse imposterTable <> 0 OrElse _
       sqlite3ConfigExtraSchemaChecksEnabled() = 0 Then
        Return SQLITE_OK
    End If

    If db->init.busy <> 0 Then
        Dim initializedFields As Const ZString Ptr Ptr = db->init.azInit
        If initializedFields = 0 OrElse _
           sqlite3_stricmp(zType, initializedFields[0]) <> 0 OrElse _
           sqlite3_stricmp(zName, initializedFields[1]) <> 0 OrElse _
           sqlite3_stricmp(zTableName, initializedFields[2]) <> 0 Then
            ' Schema initialization supplies the detailed corruptSchema error.
            sqlite3ErrorMsg(pParse, StrPtr(""))
            Return SQLITE_ERROR
        End If
    Else
        Dim isReservedName As SQLITE_C_INT = _
            (pParse->nested = 0 AndAlso _
             sqlite3_strnicmp(zName, _
                StrPtr(sqlite3ObjectNameReservedPrefix), 7) = 0)
        If isReservedName = 0 AndAlso _
           sqlite3ReadOnlyShadowTables(db) <> 0 Then
            isReservedName = sqlite3ShadowTableName(db, zName)
        End If
        If isReservedName <> 0 Then
            sqlite3ErrorMsg(pParse, _
                StrPtr(sqlite3ObjectNameReservedError), zName)
            Return SQLITE_ERROR
        End If
    End If

    Return SQLITE_OK
End Function

/' end of sqlite3_bulk_objectname.bas '/
