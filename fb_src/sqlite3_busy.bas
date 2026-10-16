/'
    Project: SQLite FreeBASIC port

    File: sqlite3_busy.bas

    Purpose:

        Manage connection busy callbacks and timeout-based lock retries.

    Responsibilities:

        - Store and invoke the per-connection busy callback.
        - Apply SQLite's bounded retry delay schedule for sqlite3_busy_timeout().
        - Pass the callback through B-tree pager locks.

    This file intentionally does NOT contain:

        - Shared-cache table-lock policy or setlk timeout callbacks.
        - Pager locking and VFS sleep implementations.
'/ 

#lang "fb"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_vfs.bi"
#include once "sqlite3_constants.bi"

Private Const SQLITE_BUSY_RETRY_COUNT As SQLITE_C_INT = 12
Dim Shared As Const UByte sqlite3BusyDelay(0 To 11) = _
    {1, 2, 5, 10, 15, 20, 25, 25, 25, 50, 50, 100}
Dim Shared As Const UShort sqlite3BusyPriorDelay(0 To 11) = _
    {0, 1, 3, 8, 18, 33, 53, 78, 103, 128, 178, 228}

Private Function sqliteDefaultBusyCallback CDecl Alias "sqliteDefaultBusyCallback" ( _
    ByVal pUserData As Any Ptr, _
    ByVal busyCount As SQLITE_C_INT _
) As SQLITE_C_INT
    If pUserData = 0 OrElse busyCount < 0 Then Return 0
    Dim db As sqlite3 Ptr = CPtr(sqlite3 Ptr, pUserData)
    Dim delay As sqlite3_int64
    Dim priorDelay As sqlite3_int64
    If busyCount < SQLITE_BUSY_RETRY_COUNT Then
        delay = sqlite3BusyDelay(busyCount)
        priorDelay = sqlite3BusyPriorDelay(busyCount)
    Else
        delay = sqlite3BusyDelay(SQLITE_BUSY_RETRY_COUNT - 1)
        priorDelay = sqlite3BusyPriorDelay(SQLITE_BUSY_RETRY_COUNT - 1) + _
            delay * (busyCount - SQLITE_BUSY_RETRY_COUNT + 1)
    End If

    Dim timeout As sqlite3_int64 = db->busyTimeout
    If priorDelay + delay > timeout Then delay = timeout - priorDelay
    If delay <= 0 Then Return 0

    Dim pVfs As sqlite3_vfs Ptr = CPtr(sqlite3_vfs Ptr, db->pVfs)
    If pVfs = 0 Then Return 0
    sqlite3OsSleep(pVfs, CInt(delay * 1000))
    Return 1
End Function

Function sqlite3InvokeBusyHandler CDecl Alias "sqlite3InvokeBusyHandler" ( _
    ByVal pHandler As SqliteBusyHandler Ptr _
) As SQLITE_C_INT Export
    If pHandler = 0 OrElse pHandler->xBusyHandler = 0 OrElse pHandler->nBusy < 0 Then _
        Return 0
    Dim xBusy As SqliteBusyCallback = pHandler->xBusyHandler
    Dim result As SQLITE_C_INT = xBusy(pHandler->pBusyArg, pHandler->nBusy)
    If result = 0 Then
        pHandler->nBusy = -1
    ElseIf pHandler->nBusy < &H7FFFFFFF Then
        pHandler->nBusy += 1
    End If
    Return result
End Function

Function sqlite3_busy_handler CDecl Alias "sqlite3_busy_handler" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal xBusyArgument As Any Ptr, _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export
    If db = 0 Then Return SQLITE_MISUSE
    sqlite3_mutex_enter(db->mutex)
    db->busyHandler.xBusyHandler = CPtr(SqliteBusyCallback, xBusyArgument)
    db->busyHandler.pBusyArg = pArgument
    db->busyHandler.nBusy = 0
    db->busyTimeout = 0
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    db->setlkTimeout = 0
#endif
    sqlite3_mutex_leave(db->mutex)
    Return SQLITE_OK
End Function

Function sqlite3_busy_timeout CDecl Alias "sqlite3_busy_timeout" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal milliseconds As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If db = 0 Then Return SQLITE_MISUSE
    sqlite3_mutex_enter(db->mutex)
    If milliseconds > 0 Then
        sqlite3_busy_handler(db, @sqliteDefaultBusyCallback, db)
        db->busyTimeout = milliseconds
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
        db->setlkTimeout = milliseconds
#endif
    Else
        sqlite3_busy_handler(db, 0, 0)
    End If
    sqlite3_mutex_leave(db->mutex)
    Return SQLITE_OK
End Function

/' end of sqlite3_busy.bas '/
