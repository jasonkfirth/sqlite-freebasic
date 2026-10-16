/'
    Project: SQLite FreeBASIC port

    File: sqlite3_shadow_tables.bas

    Purpose:

        Apply defensive-mode restrictions to shadow-table access.

    Responsibilities:

        - Detect the virtual-table synchronization state used during DDL.
        - Report when shadow tables must be treated as read-only.

    This file intentionally does NOT contain:

        - Shadow-table naming rules or virtual-table module registration.
        - CREATE, ALTER, or DROP statement generation.
'/ 

#lang "fb"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_constants.bi"

/' A missing transaction array during xSync means virtual tables are syncing. '/
Private Function sqlite3VtabInSync(ByVal db As sqlite3 Ptr) As SQLITE_C_INT
    If db = 0 Then Return 0
#ifndef SQLITE_OMIT_VIRTUALTABLE
    If db->nVTrans > 0 AndAlso db->aVTrans = 0 Then Return 1
#endif
    Return 0
End Function

Function sqlite3ReadOnlyShadowTables CDecl Alias "sqlite3ReadOnlyShadowTables" ( _
    ByVal database As Any Ptr _
) As SQLITE_C_INT Export
    If database = 0 Then Return 0
    Dim db As sqlite3 Ptr = CPtr(sqlite3 Ptr, database)
#ifndef SQLITE_OMIT_VIRTUALTABLE
    If (db->flags And SQLITE_Defensive) <> 0 AndAlso _
       db->pVtabCtx = 0 AndAlso db->nVdbeExec = 0 AndAlso _
       sqlite3VtabInSync(db) = 0 Then Return 1
#endif
    Return 0
End Function

/' end of sqlite3_shadow_tables.bas '/
