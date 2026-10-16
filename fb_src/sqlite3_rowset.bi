/'
    Project: SQLite FreeBASIC port

    File: sqlite3_rowset.bi

    Purpose:

        Declare the opaque RowSet C ABI for VDBE modules.

    Responsibilities:

        - Expose RowSet lifecycle, insertion, batch-test, and extraction calls.
        - Keep RowSetEntry and RowSet storage private to sqlite3_rowset.bas.

    This file intentionally does NOT contain:

        - RowSet allocation or sorting logic.
        - VDBE opcode implementations.
'/

#ifndef SQLITE3_FB_ROWSET_BI
#define SQLITE3_FB_ROWSET_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_db_types.bi"

Declare Function sqlite3RowSetInit CDecl Alias "sqlite3RowSetInit" ( _
    ByVal db As sqlite3 Ptr _
) As Any Ptr
Declare Sub sqlite3RowSetClear CDecl Alias "sqlite3RowSetClear" (ByVal p As Any Ptr)
Declare Sub sqlite3RowSetDelete CDecl Alias "sqlite3RowSetDelete" (ByVal p As Any Ptr)
Declare Sub sqlite3RowSetInsert CDecl Alias "sqlite3RowSetInsert" ( _
    ByVal p As Any Ptr, _
    ByVal rowid As i64 _
)
Declare Function sqlite3RowSetTest CDecl Alias "sqlite3RowSetTest" ( _
    ByVal p As Any Ptr, _
    ByVal batchNumber As SQLITE_C_INT, _
    ByVal rowid As i64 _
) As SQLITE_C_INT
Declare Function sqlite3RowSetNext CDecl Alias "sqlite3RowSetNext" ( _
    ByVal p As Any Ptr, _
    ByVal pRowid As i64 Ptr _
) As SQLITE_C_INT

#endif

/' end of sqlite3_rowset.bi '/
