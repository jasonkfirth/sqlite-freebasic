/'
    Project: SQLite FreeBASIC port

    File: sqlite3_std_types.bas

    Purpose:

        Hold the process-wide standard type-name table from src/global.c.

    Responsibilities:

        - Keep the C-ordered name pointers at one stable address.

    This file intentionally does NOT contain:

        - Type affinity, length, or schema validation behavior.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_std_types.bi"

/'
** Standard SQLite type names from src/global.c.
** Their order follows the COLTYPE_* constants.
'/
Private Dim Shared As Const ZString * 8 sqlite3StdTypeText(0 To 5) = { _
    "ANY", _
    "BLOB", _
    "INT", _
    "INTEGER", _
    "REAL", _
    "TEXT"}

Private Dim Shared As Const ZString Ptr sqlite3StdTypePointers(0 To 5) = { _
    CPtr(Const ZString Ptr, @sqlite3StdTypeText(0)), _
    CPtr(Const ZString Ptr, @sqlite3StdTypeText(1)), _
    CPtr(Const ZString Ptr, @sqlite3StdTypeText(2)), _
    CPtr(Const ZString Ptr, @sqlite3StdTypeText(3)), _
    CPtr(Const ZString Ptr, @sqlite3StdTypeText(4)), _
    CPtr(Const ZString Ptr, @sqlite3StdTypeText(5))}

Function sqlite3StdTypeTable CDecl Alias "sqlite3StdTypeTable" () As Const ZString Ptr Ptr
    Return @sqlite3StdTypePointers(0)
End Function

/' end of sqlite3_std_types.bas '/
