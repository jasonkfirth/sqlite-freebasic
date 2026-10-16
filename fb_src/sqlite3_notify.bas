/'
    Project: SQLite FreeBASIC port

    File: sqlite3_notify.bas

    Purpose:

        Port SQLite's shared-cache unlock-notify graph and callback dispatch.

    Responsibilities:

        - Track connections blocked by shared-cache locks under STATIC_MAIN.
        - Detect cycles before registering an unlock-notify callback.
        - Dispatch callbacks in groups while bounding callback-argument memory.
        - Remove a closing connection from the graph.

    This file intentionally does NOT contain:

        - Shared-cache lock acquisition or B-tree transaction management.
        - The callback implementation supplied by the application.
'/ 

#lang "fb"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_mutex.bi"
#include once "sqlite3_constants.bi"

#ifdef SQLITE_ENABLE_UNLOCK_NOTIFY

Declare Function sqlite3SafetyCheckOk CDecl Alias "sqlite3SafetyCheckOk" ( _
    ByVal db As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3ErrorWithMsg CDecl Alias "sqlite3ErrorWithMsg" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal resultCode As SQLITE_C_INT, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Function sqlite3Malloc CDecl Alias "sqlite3Malloc" ( _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Function sqlite3MallocSize CDecl Alias "sqlite3MallocSize" ( _
    ByVal p As Const Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Declare Sub sqlite3BeginBenignMalloc CDecl Alias "sqlite3BeginBenignMalloc" ()
Declare Sub sqlite3EndBenignMalloc CDecl Alias "sqlite3EndBenignMalloc" ()

' -------------------------------------------------------------------------
' Shared-cache blocked-connection graph
' -------------------------------------------------------------------------

' The list is only read or changed while SQLITE_MUTEX_STATIC_MAIN is held.
Dim Shared sqlite3BlockedList As sqlite3 Ptr

Private Sub notifyAssert CDecl (ByVal condition As SQLITE_C_INT)
#ifdef SQLITE_DEBUG
    If condition = 0 Then
        Print "sqlite3 unlock-notify invariant failed"
        End 1
    End If
#endif
End Sub

Private Sub assertMutexHeld CDecl ()
#ifdef SQLITE_DEBUG
    notifyAssert(sqlite3_mutex_held(sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MAIN)))
#endif
End Sub

Private Sub checkListProperties CDecl (ByVal db As sqlite3 Ptr)
#ifdef SQLITE_DEBUG
    Dim p As sqlite3 Ptr = sqlite3BlockedList
    While p <> 0
        notifyAssert(p->pUnlockConnection <> 0 OrElse p->pBlockingConnection <> 0)

        Dim seen As SQLITE_C_INT = 0
        Dim p2 As sqlite3 Ptr = sqlite3BlockedList
        While p2 <> p
            If p2->xUnlockNotify = p->xUnlockNotify Then seen = 1
            notifyAssert(p2->xUnlockNotify = p->xUnlockNotify OrElse seen = 0)
            If db <> 0 Then
                notifyAssert(p->pUnlockConnection <> db)
                notifyAssert(p->pBlockingConnection <> db)
            End If
            p2 = p2->pNextBlocked
        Wend
        p = p->pNextBlocked
    Wend
#else
    If db = 0 Then Exit Sub
#endif
End Sub

Private Sub removeFromBlockedList CDecl (ByVal db As sqlite3 Ptr)
    assertMutexHeld()

    Dim p As sqlite3 Ptr = sqlite3BlockedList
    Dim pPrevious As sqlite3 Ptr = 0
    While p <> 0
        If p = db Then
            If pPrevious = 0 Then
                sqlite3BlockedList = p->pNextBlocked
            Else
                pPrevious->pNextBlocked = p->pNextBlocked
            End If
            Exit While
        End If
        pPrevious = p
        p = p->pNextBlocked
    Wend
End Sub

Private Sub addToBlockedList CDecl (ByVal db As sqlite3 Ptr)
    assertMutexHeld()

    Dim p As sqlite3 Ptr = sqlite3BlockedList
    Dim pPrevious As sqlite3 Ptr = 0
    While p <> 0 AndAlso p->xUnlockNotify <> db->xUnlockNotify
        pPrevious = p
        p = p->pNextBlocked
    Wend

    db->pNextBlocked = p
    If pPrevious = 0 Then
        sqlite3BlockedList = db
    Else
        pPrevious->pNextBlocked = db
    End If
End Sub

Private Sub enterMutex CDecl ()
    sqlite3_mutex_enter(sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MAIN))
    checkListProperties(0)
End Sub

Private Sub leaveMutex CDecl ()
    assertMutexHeld()
    checkListProperties(0)
    sqlite3_mutex_leave(sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MAIN))
End Sub

' -------------------------------------------------------------------------
' Public unlock-notify API and graph updates
' -------------------------------------------------------------------------

Function sqlite3_unlock_notify CDecl Alias "sqlite3_unlock_notify" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal xNotifyArgument As Any Ptr, _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export
    If db = 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_ENABLE_API_ARMOR
    If sqlite3SafetyCheckOk(db) = 0 Then Return SQLITE_MISUSE
#endif

    Dim xNotify As SqliteUnlockNotifyCallback = CPtr(SqliteUnlockNotifyCallback, xNotifyArgument)
    Dim result As SQLITE_C_INT = SQLITE_OK
    sqlite3_mutex_enter(db->mutex)
    enterMutex()

    If xNotify = 0 Then
        removeFromBlockedList(db)
        db->pBlockingConnection = 0
        db->pUnlockConnection = 0
        db->xUnlockNotify = 0
        db->pUnlockArg = 0
    ElseIf db->pBlockingConnection = 0 Then
        ' The lock is already gone, so the callback runs before this API returns.
        Dim callbackArguments(0 To 0) As Any Ptr
        callbackArguments(0) = pArgument
        xNotify(@callbackArguments(0), 1)
    Else
        Dim p As sqlite3 Ptr = db->pBlockingConnection
        While p <> 0 AndAlso p <> db
            p = p->pUnlockConnection
        Wend
        If p <> 0 Then
            result = SQLITE_LOCKED
        Else
            db->pUnlockConnection = db->pBlockingConnection
            db->xUnlockNotify = xNotify
            db->pUnlockArg = pArgument
            removeFromBlockedList(db)
            addToBlockedList(db)
        End If
    End If

    leaveMutex()
    notifyAssert(db->mallocFailed = 0)
    Dim errorMessage As Const ZString Ptr = 0
    If result <> SQLITE_OK Then errorMessage = StrPtr("database is deadlocked")
    sqlite3ErrorWithMsg(db, result, errorMessage)
    sqlite3_mutex_leave(db->mutex)
    Return result
End Function

Sub sqlite3ConnectionBlocked CDecl Alias "sqlite3ConnectionBlocked" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pBlocker As sqlite3 Ptr _
) Export
    If db = 0 Then Exit Sub
    enterMutex()
    If db->pBlockingConnection = 0 AndAlso db->pUnlockConnection = 0 Then _
        addToBlockedList(db)
    db->pBlockingConnection = pBlocker
    leaveMutex()
End Sub

Sub sqlite3ConnectionUnlocked CDecl Alias "sqlite3ConnectionUnlocked" ( _
    ByVal db As sqlite3 Ptr _
) Export
    If db = 0 Then Exit Sub

    Dim xUnlockNotify As SqliteUnlockNotifyCallback = 0
    Dim nArgument As SQLITE_C_INT = 0
    Dim aArgumentStatic(0 To 15) As Any Ptr
    Dim aArgument As Any Ptr Ptr = @aArgumentStatic(0)
    Dim aDynamic As Any Ptr = 0

    enterMutex()
    Dim pPrevious As sqlite3 Ptr = 0
    Dim p As sqlite3 Ptr = sqlite3BlockedList
    While p <> 0
        Dim pNext As sqlite3 Ptr = p->pNextBlocked

        If p->pBlockingConnection = db Then p->pBlockingConnection = 0

        If p->pUnlockConnection = db Then
            notifyAssert(p->xUnlockNotify <> 0)
            If p->xUnlockNotify <> xUnlockNotify AndAlso nArgument <> 0 Then
                xUnlockNotify(aArgument, nArgument)
                nArgument = 0
            End If

            sqlite3BeginBenignMalloc()
            notifyAssert(aArgument = aDynamic OrElse _
                         (aDynamic = 0 AndAlso aArgument = @aArgumentStatic(0)))
            Dim capacity As SQLITE_C_INT = 16
            If aDynamic <> 0 Then _
                capacity = sqlite3MallocSize(aDynamic) \ SizeOf(Any Ptr)
            If nArgument = capacity Then
                Dim newSize As sqlite3_uint64 = _
                    Cast(sqlite3_uint64, nArgument) * SizeOf(Any Ptr) * 2
                Dim pNew As Any Ptr Ptr = CPtr(Any Ptr Ptr, sqlite3Malloc(newSize))
                If pNew <> 0 Then
                    For i As SQLITE_C_INT = 0 To nArgument - 1
                        pNew[i] = aArgument[i]
                    Next
                    sqlite3_free(aDynamic)
                    aDynamic = pNew
                    aArgument = pNew
                Else
                    ' Allocation failure must not strand a waiter. Flush this
                    ' callback group and keep collecting with the stack buffer.
                    xUnlockNotify(aArgument, nArgument)
                    nArgument = 0
                End If
            End If
            sqlite3EndBenignMalloc()

            aArgument[nArgument] = p->pUnlockArg
            nArgument += 1
            xUnlockNotify = p->xUnlockNotify
            p->pUnlockConnection = 0
            p->xUnlockNotify = 0
            p->pUnlockArg = 0
        End If

        If p->pBlockingConnection = 0 AndAlso p->pUnlockConnection = 0 Then
            If pPrevious = 0 Then
                sqlite3BlockedList = pNext
            Else
                pPrevious->pNextBlocked = pNext
            End If
            p->pNextBlocked = 0
        Else
            pPrevious = p
        End If
        p = pNext
    Wend

    If nArgument <> 0 Then xUnlockNotify(aArgument, nArgument)
    sqlite3_free(aDynamic)
    leaveMutex()
End Sub

Sub sqlite3ConnectionClosed CDecl Alias "sqlite3ConnectionClosed" ( _
    ByVal db As sqlite3 Ptr _
) Export
    If db = 0 Then Exit Sub
    sqlite3ConnectionUnlocked(db)
    enterMutex()
    removeFromBlockedList(db)
    checkListProperties(db)
    leaveMutex()
End Sub

#endif

/' end of sqlite3_notify.bas '/
