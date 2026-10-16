/'
    Project: SQLite FreeBASIC port

    File: sqlite3_insert.bas

    Purpose:

        Hold the autoincrement rowid VDBE helper from insert.c.

    Responsibilities:

        - Keep the maximum rowid register in sync with an inserted rowid.

    This file intentionally does NOT contain:

        - INSERT statement planning or row/index writes.
'/ 

#lang "fb"
#include once "sqlite3_vdbe_core.bi"

Private Sub autoIncStep CDecl Alias "autoIncStep" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal memId As SQLITE_C_INT, _
    ByVal rowidRegister As SQLITE_C_INT _
)
    If pParse = 0 OrElse pParse->pVdbe = 0 OrElse memId <= 0 Then Exit Sub
    sqlite3VdbeAddOp2(pParse->pVdbe, OP_MemMax, memId, rowidRegister)
End Sub

/' end of sqlite3_insert.bas '/
