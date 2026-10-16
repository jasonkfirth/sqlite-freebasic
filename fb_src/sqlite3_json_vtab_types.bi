/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_vtab_types.bi

    Purpose:

        Define the cursor and connection records used by json_each() and
        json_tree() virtual tables.

    Responsibilities:

        - Match the fixed parent, cursor, and connection layouts in src/json.c.
        - Reuse the JSON parse and path-string records owned by the JSON module.

    This file intentionally does NOT contain:

        - JSON path evaluation or iteration behavior.
        - Virtual-table registration or SQL function callbacks.
'/

#ifndef SQLITE3_FB_JSON_VTAB_TYPES_BI
#define SQLITE3_FB_JSON_VTAB_TYPES_BI

#include once "sqlite3_vtab_types.bi"
#include once "sqlite3_json_string.bi"
#include once "sqlite3_json_parse.bi"

Type SqliteJsonParent
    iHead As u32
    iValue As u32
    iEnd As u32
    nPath As u32
    iKey As sqlite3_int64
End Type

Type SqliteJsonEachCursor
    base As SqliteVtabCursor
    iRowid As u32
    i As u32
    iEnd As u32
    nRoot As u32
    eType As u8
    bRecursive As u8
    eMode As u8
    nParent As u32
    nParentAlloc As u32
    aParent As SqliteJsonParent Ptr
    db As sqlite3 Ptr
    path As JsonString
    sParse As JsonParse
End Type

Type SqliteJsonEachConnection
    base As SqliteVtab
    db As sqlite3 Ptr
    eMode As u8
    bRecursive As u8
End Type

#endif

/' end of sqlite3_json_vtab_types.bi '/
