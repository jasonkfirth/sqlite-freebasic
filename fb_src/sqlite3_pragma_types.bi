/'
    Project: SQLite FreeBASIC port

    File: sqlite3_pragma_types.bi

    Purpose:

        Define the metadata and cursor records for pragma virtual tables.

    Responsibilities:

        - Match the generated PragmaName metadata layout.
        - Match the virtual-table and cursor records in src/pragma.c.

    This file intentionally does NOT contain:

        - The generated pragma-name table storage or pragma handlers.
        - Virtual-table callback behavior.
'/

#ifndef SQLITE3_FB_PRAGMA_TYPES_BI
#define SQLITE3_FB_PRAGMA_TYPES_BI

#include once "sqlite3_db_types.bi"
#include once "sqlite3_vtab_types.bi"

Type SqlitePragmaName
    zName As Const ZString Ptr
    ePragTyp As u8
    mPragFlg As u8
    iPragCName As u8
    nPragCName As u8
    iArg As sqlite3_uint64
End Type

#include once "sqlite3_pragma_data.bi"

Type SqlitePragmaEncodingName
    zName As Const ZString Ptr
    enc As UByte
End Type

Type SqlitePragmaVtab
    base As SqliteVtab
    db As sqlite3 Ptr
    pName As SqlitePragmaName Ptr
    nHidden As u8
    iHidden As u8
End Type

Type SqlitePragmaVtabCursor
    base As SqliteVtabCursor
    pPragma As Any Ptr
    iRowid As sqlite3_int64
    azArg(0 To 1) As ZString Ptr
End Type

#endif

/' end of sqlite3_pragma_types.bi '/
