/'
    Project: SQLite FreeBASIC port

    File: sqlite3_trigger_helpers.bas

    Purpose:

        Preserve small schema queries used by trigger compilation.

    Responsibilities:

        - Report whether the TEMP schema contains any triggers.

    This file intentionally does NOT contain:

        - Trigger parsing, ownership, DDL, or execution.
        - Catalog loading for the TEMP schema.
'/ 

#lang "fb"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_hash_types.bi"

/' The TEMP schema owns its trigger hash even when it contains no triggers. '/
Private Function tempTriggersExist CDecl Alias "tempTriggersExist" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
    If db = 0 OrElse db->aDb(1).pSchema = 0 Then Return 0
    If db->aDb(1).pSchema->trigHash.first = 0 Then Return 0
    Return 1
End Function

/' end of sqlite3_trigger_helpers.bas '/
