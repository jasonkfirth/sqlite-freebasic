/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_debug_assert.bas

    Purpose:

        Report and stop on failed SQLite debug assertions.

    Responsibilities:

        - Route assertion diagnostics through SQLite's configured log callback.
        - Abort after a failed invariant so execution cannot continue corrupted.

    This file intentionally does NOT contain:

        - Release-build assertions or test-only assertion controls.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"

#ifdef SQLITE_DEBUG

Declare Sub sqlite3DebugLog CDecl Alias "sqlite3_log" ( _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Sub sqlite3DebugAbort CDecl Alias "abort" ()

Sub sqlite3DebugAssert CDecl Alias "sqlite3DebugAssert" ( _
    ByVal zExpression As Const ZString Ptr _
) Export
    If zExpression = 0 Then
        sqlite3DebugLog(SQLITE_ERROR, StrPtr("SQLite debug assertion failed"))
    Else
        sqlite3DebugLog(SQLITE_ERROR, _
            StrPtr("SQLite debug assertion failed: %s"), zExpression)
    End If
    sqlite3DebugAbort()
End Sub

#endif

/' end of sqlite3_debug_assert.bas '/
