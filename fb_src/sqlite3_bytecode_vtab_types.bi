/'
    Project: SQLite FreeBASIC port

    File: sqlite3_bytecode_vtab_types.bi

    Purpose:

        Define the table and cursor records used by SQLite's optional bytecode virtual table.

    Responsibilities:

        - Preserve the base-vtab prefixes and the bytecode-vtab cursor fields.
        - Reuse the port's VDBE, cursor, and Mem layouts.

    This file intentionally does NOT contain:

        - Bytecode-vtab iteration, filtering, or query planning.
'/ 

#ifndef SQLITE3_FB_BYTECODE_VTAB_TYPES_BI
#define SQLITE3_FB_BYTECODE_VTAB_TYPES_BI

#include once "sqlite3_vtab_types.bi"
#include once "sqlite3_vdbe_core.bi"

Type SqliteBytecodeVtab
    base As SqliteVtab
    db As sqlite3 Ptr
    bTablesUsed As SQLITE_C_INT
End Type

Type SqliteBytecodeVtabCursor
    base As SqliteVtabCursor
    pStmt As SqliteVdbe Ptr
    iRowid As SQLITE_C_INT
    iAddr As SQLITE_C_INT
    needFinalize As SQLITE_C_INT
    showSubprograms As SQLITE_C_INT
    aOp As SqliteVdbeOp Ptr
    zP4 As ZString Ptr
    zType As Const ZString Ptr
    zSchema As Const ZString Ptr
    zName As Const ZString Ptr
    subprogram As SqliteVdbeMem
End Type

#endif

/' end of sqlite3_bytecode_vtab_types.bi '/
