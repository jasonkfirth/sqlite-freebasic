/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_dbpage_types.bi

    Purpose:

        Define the table and cursor records used by SQLite's dbpage virtual table.

    Responsibilities:

        - Preserve the sqlite3_vtab and sqlite3_vtab_cursor base records.
        - Store page numbers, pager handles, and pending truncate state.
        - Provide fixed layouts for C2FB translation of src/dbpage.c.

    This file intentionally does NOT contain:

        - Virtual-table callbacks or pager operations.
        - A general-purpose database page cache.
'/ 

#ifndef SQLITE3_FB_DBPAGE_TYPES_BI
#define SQLITE3_FB_DBPAGE_TYPES_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_vtab_types.bi"
#include once "sqlite3_pager.bi"
#include once "sqlite3_pcache.bi"

Type SqliteDbpageCursor
    base As SqliteVtabCursor
    pgno As u32
    mxPgno As u32
    pPager As Pager Ptr
    pPage1 As PgHdr Ptr
    iDb As SQLITE_C_INT
    szPage As SQLITE_C_INT
End Type

Type SqliteDbpageTable
    base As SqliteVtab
    db As sqlite3 Ptr
    iDbTrunc As SQLITE_C_INT
    pgnoTrunc As u32
End Type

#endif

/' end of sqlite3_dbpage_types.bi '/
