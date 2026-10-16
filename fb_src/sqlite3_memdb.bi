/'
    Project: SQLite FreeBASIC port

    File: sqlite3_memdb.bi

    Purpose:

        Declare SQLite's in-memory database VFS entry points.

    Responsibilities:

        - Expose registration of the memory database VFS.
        - Identify VFS instances backed by the memory database store.

    This file intentionally does NOT contain:

        - Serialization APIs that require B-tree and connection state.
        - The in-memory file and shared-store layouts.
'/

#ifndef SQLITE3_FB_MEMDB_BI
#define SQLITE3_FB_MEMDB_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_vfs.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_memdb_types.bi"

Declare Function sqlite3MemdbInit CDecl Alias "sqlite3MemdbInit" () As SQLITE_C_INT
Declare Function sqlite3IsMemdb CDecl Alias "sqlite3IsMemdb" ( _
    ByVal pVfs As Const sqlite3_vfs Ptr _
) As SQLITE_C_INT
Declare Function memdbFromDbSchema CDecl Alias "memdbFromDbSchema" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zSchema As Const ZString Ptr _
) As MemdbFile Ptr

#endif

/' end of sqlite3_memdb.bi '/
