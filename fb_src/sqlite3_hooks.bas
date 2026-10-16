/'
    Project: SQLite FreeBASIC port

    File: sqlite3_hooks.bas

    Purpose:

        Register callbacks associated with a database connection.

    Responsibilities:

        - Set trace, profile, commit, rollback, and update callbacks.
        - Store callback arguments while holding the connection mutex.
        - Support the optional pre-update callback registration.

    This file intentionally does NOT contain:

        - VDBE trace invocation, transaction hook invocation, or pre-update state.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_mutex.bi"

Declare Function sqlite3SafetyCheckOk CDecl Alias "sqlite3SafetyCheckOk" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT

#ifndef SQLITE_OMIT_TRACE
#ifndef SQLITE_OMIT_DEPRECATED
Function sqlite3_trace CDecl Alias "sqlite3_trace" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal xTrace As Any Ptr, _
    ByVal pArgument As Any Ptr _
) As Any Ptr Export
    If db = 0 Then Return 0
#ifdef SQLITE_ENABLE_API_ARMOR
    If sqlite3SafetyCheckOk(db) = 0 Then Return 0
#endif

    sqlite3_mutex_enter(db->mutex)
    Dim oldArgument As Any Ptr = db->pTraceArg
    If xTrace <> 0 Then
        db->mTrace = SQLITE_TRACE_LEGACY
    Else
        db->mTrace = 0
    End If
    db->trace.xLegacy = xTrace
    db->pTraceArg = pArgument
    sqlite3_mutex_leave(db->mutex)
    Return oldArgument
End Function
#endif

Function sqlite3_trace_v2 CDecl Alias "sqlite3_trace_v2" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal traceMask As SQLITE_C_UINT, _
    ByVal xTrace As Any Ptr, _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export
    If db = 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_ENABLE_API_ARMOR
    If sqlite3SafetyCheckOk(db) = 0 Then Return SQLITE_MISUSE
#endif

    sqlite3_mutex_enter(db->mutex)
    If traceMask = 0 Then xTrace = 0
    If xTrace = 0 Then traceMask = 0
    db->mTrace = CUByte(traceMask And &HFF)
    db->trace.xV2 = xTrace
    db->pTraceArg = pArgument
    sqlite3_mutex_leave(db->mutex)
    Return SQLITE_OK
End Function

#ifndef SQLITE_OMIT_DEPRECATED
Function sqlite3_profile CDecl Alias "sqlite3_profile" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal xProfile As Any Ptr, _
    ByVal pArgument As Any Ptr _
) As Any Ptr Export
    If db = 0 Then Return 0
#ifdef SQLITE_ENABLE_API_ARMOR
    If sqlite3SafetyCheckOk(db) = 0 Then Return 0
#endif

    sqlite3_mutex_enter(db->mutex)
    Dim oldArgument As Any Ptr = db->pProfileArg
    db->xProfile = xProfile
    db->pProfileArg = pArgument
    db->mTrace = db->mTrace And SQLITE_TRACE_NONLEGACY_MASK
    If xProfile <> 0 Then db->mTrace = db->mTrace Or SQLITE_TRACE_XPROFILE
    sqlite3_mutex_leave(db->mutex)
    Return oldArgument
End Function
#endif
#endif

Function sqlite3_commit_hook CDecl Alias "sqlite3_commit_hook" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal xCallback As Any Ptr, _
    ByVal pArgument As Any Ptr _
) As Any Ptr Export
    If db = 0 Then Return 0
#ifdef SQLITE_ENABLE_API_ARMOR
    If sqlite3SafetyCheckOk(db) = 0 Then Return 0
#endif

    sqlite3_mutex_enter(db->mutex)
    Dim oldArgument As Any Ptr = db->pCommitArg
    db->xCommitCallback = xCallback
    db->pCommitArg = pArgument
    sqlite3_mutex_leave(db->mutex)
    Return oldArgument
End Function

Function sqlite3_update_hook CDecl Alias "sqlite3_update_hook" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal xCallback As Any Ptr, _
    ByVal pArgument As Any Ptr _
) As Any Ptr Export
    If db = 0 Then Return 0
#ifdef SQLITE_ENABLE_API_ARMOR
    If sqlite3SafetyCheckOk(db) = 0 Then Return 0
#endif

    sqlite3_mutex_enter(db->mutex)
    Dim oldArgument As Any Ptr = db->pUpdateArg
    db->xUpdateCallback = xCallback
    db->pUpdateArg = pArgument
    sqlite3_mutex_leave(db->mutex)
    Return oldArgument
End Function

Function sqlite3_rollback_hook CDecl Alias "sqlite3_rollback_hook" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal xCallback As Any Ptr, _
    ByVal pArgument As Any Ptr _
) As Any Ptr Export
    If db = 0 Then Return 0
#ifdef SQLITE_ENABLE_API_ARMOR
    If sqlite3SafetyCheckOk(db) = 0 Then Return 0
#endif

    sqlite3_mutex_enter(db->mutex)
    Dim oldArgument As Any Ptr = db->pRollbackArg
    db->xRollbackCallback = xCallback
    db->pRollbackArg = pArgument
    sqlite3_mutex_leave(db->mutex)
    Return oldArgument
End Function

#ifdef SQLITE_ENABLE_PREUPDATE_HOOK
Function sqlite3_preupdate_hook CDecl Alias "sqlite3_preupdate_hook" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal xCallback As Any Ptr, _
    ByVal pArgument As Any Ptr _
) As Any Ptr Export
    If db = 0 Then Return 0
#ifdef SQLITE_ENABLE_API_ARMOR
    If sqlite3SafetyCheckOk(db) = 0 Then Return 0
#endif

    sqlite3_mutex_enter(db->mutex)
    Dim oldArgument As Any Ptr = db->pPreUpdateArg
    db->xPreUpdateCallback = xCallback
    db->pPreUpdateArg = pArgument
    sqlite3_mutex_leave(db->mutex)
    Return oldArgument
End Function
#endif

/' end of sqlite3_hooks.bas '/
