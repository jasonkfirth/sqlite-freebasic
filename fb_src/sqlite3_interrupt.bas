/'
    Project: SQLite FreeBASIC port

    File: sqlite3_interrupt.bas

    Purpose:

        Set and read the per-connection execution interrupt flag.

    Responsibilities:

        - Let sqlite3_interrupt() signal a VDBE without taking db->mutex.
        - Synchronize access to the interrupt flag with a separate mutex.

    This file intentionally does NOT contain:

        - VDBE opcode execution or connection close policy.
'/ 

#lang "fb"
#include once "sqlite3_db_types.bi"

Sub sqlite3_interrupt CDecl Alias "sqlite3_interrupt" ( _
    ByVal db As sqlite3 Ptr _
) Export
    If db = 0 OrElse db->interruptMutex = 0 Then Return
    sqlite3_mutex_enter(db->interruptMutex)
    db->isInterrupted = 1
    sqlite3_mutex_leave(db->interruptMutex)
End Sub

Function sqlite3InterruptPending CDecl Alias "sqlite3InterruptPending" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT Export
    If db = 0 OrElse db->interruptMutex = 0 Then Return 0
    sqlite3_mutex_enter(db->interruptMutex)
    Dim result As SQLITE_C_INT = db->isInterrupted
    sqlite3_mutex_leave(db->interruptMutex)
    Return result
End Function

Function sqlite3_is_interrupted CDecl Alias "sqlite3_is_interrupted" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT Export
    Return sqlite3InterruptPending(db)
End Function

/' end of sqlite3_interrupt.bas '/
