/'
** 2009 January 28
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
*************************************************************************
** This file contains the implementation of the sqlite3_backup_XXX()
** API functions and the related features.
'/

/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_backup_types.bi

    Purpose:

        Define the private state shared by SQLite backup API routines.

    Responsibilities:

        - Preserve the field order and C widths from src/backup.c.
        - Expose remaining-page and source-page-count state to API accessors.

    This file intentionally does NOT contain:

        - Backup allocation, page copying, locking, or cleanup logic.
        - A substitute for the full backup implementation.
'/ 

#ifndef SQLITE3_FB_BACKUP_TYPES_BI
#define SQLITE3_FB_BACKUP_TYPES_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_btree.bi"

' Field order follows struct sqlite3_backup in src/backup.c. Pgno is u32.
Type SqliteBackupContext
    pDestDb As sqlite3 Ptr
    zDestDb As ZString Ptr
    pDest As Btree Ptr
    iDestSchema As u32
    bDestLocked As SQLITE_C_INT
    iNext As u32
    pSrcDb As sqlite3 Ptr
    pSrc As Btree Ptr
    rc As SQLITE_C_INT
    nRemaining As u32
    nPagecount As u32
    isAttached As SQLITE_C_INT
    pNext As Any Ptr
End Type

#endif

/' end of sqlite3_backup_types.bi '/
