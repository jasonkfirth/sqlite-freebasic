/'
    Project: SQLite FreeBASIC port

    File: sqlite3_limit.bas

    Purpose:

        Store and enforce per-connection SQL complexity limits.

    Responsibilities:

        - Initialize each connection from SQLite's compile-time hard limits.
        - Implement sqlite3_limit() with SQLite's clamping rules.

    This file intentionally does NOT contain:

        - sqlite3_config() or runtime mutation of global hard-limit defaults.
        - Enforcement paths for schema features that are not yet ported.
'/

#lang "fb"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_mutex.bi"

Private Dim Shared sqlite3HardLimitValues(0 To SQLITE_N_LIMIT - 1) As SQLITE_C_INT = { _
    SQLITE_MAX_LENGTH, _
    SQLITE_MAX_SQL_LENGTH, _
    SQLITE_MAX_COLUMN, _
    SQLITE_MAX_EXPR_DEPTH, _
    SQLITE_MAX_COMPOUND_SELECT, _
    SQLITE_MAX_VDBE_OP, _
    SQLITE_MAX_FUNCTION_ARG, _
    SQLITE_MAX_ATTACHED, _
    SQLITE_MAX_LIKE_PATTERN_LENGTH, _
    SQLITE_MAX_VARIABLE_NUMBER, _
    SQLITE_MAX_TRIGGER_DEPTH, _
    SQLITE_MAX_WORKER_THREADS, _
    SQLITE_MAX_PARSER_DEPTH, _
    SQLITE_MAX_SCHEMA, _
    SQLITE_MAX_TRIGGER_STEPS _
}

Function sqlite3LimitHardValueTable CDecl Alias "sqlite3LimitHardValueTable" () _
    As Const SQLITE_C_INT Ptr Export
    Return @sqlite3HardLimitValues(0)
End Function

Private Function sqlite3LimitHardValue( _
    ByVal limitId As SQLITE_C_INT _
) As SQLITE_C_INT
    If limitId < 0 OrElse limitId >= SQLITE_N_LIMIT Then Return -1
    Return sqlite3HardLimitValues(limitId)
End Function

Function sqlite3LimitInitialize CDecl Alias "sqlite3LimitInitialize" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT Export
    If db = 0 Then Return SQLITE_MISUSE
    For limitId As SQLITE_C_INT = 0 To SQLITE_N_LIMIT - 1
        Dim hardLimit As SQLITE_C_INT = sqlite3LimitHardValue(limitId)
        If hardLimit < 0 Then Return SQLITE_CORRUPT
        db->aLimit(limitId) = hardLimit
    Next
    db->lengthLimit = db->aLimit(SQLITE_LIMIT_LENGTH)
    Return SQLITE_OK
End Function

Function sqlite3_limit CDecl Alias "sqlite3_limit" ( _
    ByVal pDatabase As Any Ptr, _
    ByVal limitId As SQLITE_C_INT, _
    ByVal newLimit As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pDatabase = 0 OrElse limitId < 0 OrElse limitId >= SQLITE_N_LIMIT Then Return -1
    Dim db As sqlite3 Ptr = CPtr(sqlite3 Ptr, pDatabase)
    sqlite3_mutex_enter(db->mutex)
    Dim priorLimit As SQLITE_C_INT = db->aLimit(limitId)
    If newLimit >= 0 Then
        Dim hardLimit As SQLITE_C_INT = sqlite3LimitHardValue(limitId)
        If newLimit > hardLimit Then
            newLimit = hardLimit
        ElseIf limitId = SQLITE_LIMIT_LENGTH AndAlso newLimit < SQLITE_MIN_LENGTH Then
            newLimit = SQLITE_MIN_LENGTH
        End If
        db->aLimit(limitId) = newLimit
        If limitId = SQLITE_LIMIT_LENGTH Then db->lengthLimit = newLimit
    End If
    sqlite3_mutex_leave(db->mutex)
    Return priorLimit
End Function

/' end of sqlite3_limit.bas '/
