/'
    Project: SQLite FreeBASIC port

    File: sqlite3_alter.bas

    Purpose:

        Hold schema-reload code generation used by ALTER TABLE operations.

    Responsibilities:

        - Update schema cookies and append schema reload opcodes.
        - Reload the temp schema after changes to another attached database.

    This file intentionally does NOT contain:

        - SQL text rewriting or the ALTER TABLE execution paths.
'/ 

#lang "fb"
#include once "sqlite3_vdbe_core.bi"

Declare Sub sqlite3ChangeCookie CDecl Alias "sqlite3ChangeCookie" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal iDb As SQLITE_C_INT _
)

Private Sub renameReloadSchema CDecl Alias "renameReloadSchema" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal iDb As SQLITE_C_INT, _
    ByVal parseFlags As UShort _
)
    If pParse = 0 OrElse pParse->pVdbe = 0 Then Exit Sub
    sqlite3ChangeCookie(pParse, iDb)
    sqlite3VdbeAddParseSchemaOp(pParse->pVdbe, iDb, 0, parseFlags)
    If iDb <> 1 Then
        sqlite3VdbeAddParseSchemaOp(pParse->pVdbe, 1, 0, parseFlags)
    End If
End Sub

/' end of sqlite3_alter.bas '/
