/'
    Project: SQLite FreeBASIC port

    File: sqlite3_dbstat_types.bi

    Purpose:

        Describe the private cursor and page records used by the dbstat module.

    Responsibilities:

        - Preserve fixed C layouts for StatTable, StatCursor, StatPage, and StatCell.
        - Keep the sqlite3_vtab_cursor base at the start of StatCursor.

    This file intentionally does NOT contain:

        - B-tree page decoding, scan callbacks, or dbstat registration.
        - Runtime validation of the mapped C structure offsets.
'/ 

#ifndef SQLITE3_FB_DBSTAT_TYPES_BI
#define SQLITE3_FB_DBSTAT_TYPES_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_vtab_types.bi"
#include once "sqlite3_schema_types.bi"

Type SqliteDbstatCell
    nLocal As SQLITE_C_INT
    iChildPg As u32
    nOvfl As SQLITE_C_INT
    aOvfl As u32 Ptr
    nLastOvfl As SQLITE_C_INT
    iOvfl As SQLITE_C_INT
End Type

Type SqliteDbstatPage
    iPgno As u32
    aPg As UByte Ptr
    iCell As SQLITE_C_INT
    zPath As ZString Ptr
    flags As u8
    nCell As SQLITE_C_INT
    nUnused As SQLITE_C_INT
    aCell As SqliteDbstatCell Ptr
    iRightChildPg As u32
    nMxPayload As SQLITE_C_INT
End Type

Type SqliteDbstatCursor
    base As SqliteVtabCursor
    pStmt As Any Ptr
    isEof As u8
    isAgg As u8
    iDb As SQLITE_C_INT
    aPage(0 To 31) As SqliteDbstatPage
    iPage As SQLITE_C_INT
    iPageno As u32
    zName As ZString Ptr
    zPath As ZString Ptr
    zPagetype As ZString Ptr
    nPage As SQLITE_C_INT
    nCell As SQLITE_C_INT
    nMxPayload As SQLITE_C_INT
    nUnused As sqlite3_int64
    nPayload As sqlite3_int64
    iOffset As sqlite3_int64
    szPage As sqlite3_int64
End Type

Type SqliteDbstatTable
    base As SqliteVtab
    db As sqlite3 Ptr
    iDb As SQLITE_C_INT
End Type

#endif

/' end of sqlite3_dbstat_types.bi '/
