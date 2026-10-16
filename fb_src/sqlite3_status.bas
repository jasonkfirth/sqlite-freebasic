/'
    Project: SQLite FreeBASIC port

    File: sqlite3_status.bas

    Purpose:

        Port SQLite's process-wide status counters from src/status.c.

    Responsibilities:

        - Track current and high-water values for the 10 SQLite status codes.
        - Serialize status access with the allocator or page-cache mutex.
        - Implement sqlite3_status(), sqlite3_status64(), and memory queries.

    This file intentionally does NOT contain:

        - Per-connection cache, lookaside, statement, or schema status.
        - Page-cache counter updates before the page-cache subsystem exists.
'/

#lang "fb"
#include once "sqlite3_status.bi"
#include once "sqlite3_mutex.bi"

Private Const SQLITE_STATUS_COUNT As Long = 10

Private Type SqliteStatusValue
    currentValue As sqlite3_int64
    highwaterValue As sqlite3_int64
End Type

Dim Shared sqlite3StatusValues(0 To SQLITE_STATUS_COUNT - 1) As SqliteStatusValue

Private Function sqlite3StatusOperationValid(ByVal operation As SQLITE_C_INT) As Long
    If operation < 0 OrElse operation >= SQLITE_STATUS_COUNT Then Return 0
    Return -1
End Function

Private Function sqlite3StatusMutex(ByVal operation As SQLITE_C_INT) As Any Ptr
    Select Case operation
    Case SQLITE_STATUS_PAGECACHE_USED, SQLITE_STATUS_PAGECACHE_OVERFLOW, SQLITE_STATUS_PAGECACHE_SIZE
        Return sqlite3Pcache1Mutex()
    Case Else
        Return sqlite3MallocMutex()
    End Select
End Function

' These guards must still return the no-op mutex for single-thread builds.
Function sqlite3MallocMutex CDecl Alias "sqlite3MallocMutex" () As Any Ptr Export
    Return sqlite3_mutex_alloc(SQLITE_MUTEX_STATIC_MEM)
End Function

Function sqlite3Pcache1Mutex CDecl Alias "sqlite3Pcache1Mutex" () As Any Ptr Export
    Return sqlite3_mutex_alloc(SQLITE_MUTEX_STATIC_PMEM)
End Function

Function sqlite3StatusValue CDecl Alias "sqlite3StatusValue" ( _
    ByVal operation As SQLITE_C_INT _
) As sqlite3_int64 Export

    If sqlite3StatusOperationValid(operation) = 0 Then Return 0
    Return sqlite3StatusValues(operation).currentValue
End Function

Sub sqlite3StatusUp CDecl Alias "sqlite3StatusUp" ( _
    ByVal operation As SQLITE_C_INT, _
    ByVal amount As SQLITE_C_INT _
) Export

    If sqlite3StatusOperationValid(operation) = 0 Then Exit Sub
    Dim current As sqlite3_int64 = sqlite3StatusValues(operation).currentValue
    If amount > 0 AndAlso current > &H7FFFFFFFFFFFFFFF - amount Then
        current = &H7FFFFFFFFFFFFFFF
    ElseIf amount < 0 AndAlso current < -CLngInt(amount) Then
        current = 0
    Else
        current += amount
    End If
    If current < 0 Then current = 0
    sqlite3StatusValues(operation).currentValue = current
    If current > sqlite3StatusValues(operation).highwaterValue Then
        sqlite3StatusValues(operation).highwaterValue = current
    End If
End Sub

Sub sqlite3StatusDown CDecl Alias "sqlite3StatusDown" ( _
    ByVal operation As SQLITE_C_INT, _
    ByVal amount As SQLITE_C_INT _
) Export

    If sqlite3StatusOperationValid(operation) = 0 OrElse amount < 0 Then Exit Sub
    Dim current As sqlite3_int64 = sqlite3StatusValues(operation).currentValue
    If current <= amount Then
        sqlite3StatusValues(operation).currentValue = 0
    Else
        sqlite3StatusValues(operation).currentValue = current - amount
    End If
End Sub

Sub sqlite3StatusHighwater CDecl Alias "sqlite3StatusHighwater" ( _
    ByVal operation As SQLITE_C_INT, _
    ByVal value As SQLITE_C_INT _
) Export

    If sqlite3StatusOperationValid(operation) = 0 OrElse value < 0 Then Exit Sub
    Select Case operation
    Case SQLITE_STATUS_MALLOC_SIZE, SQLITE_STATUS_PARSER_STACK, SQLITE_STATUS_PAGECACHE_SIZE
    Case Else
        Exit Sub
    End Select
    If value > sqlite3StatusValues(operation).highwaterValue Then
        sqlite3StatusValues(operation).highwaterValue = value
    End If
End Sub

Function sqlite3_status64 CDecl Alias "sqlite3_status64" ( _
    ByVal operation As SQLITE_C_INT, _
    ByVal pCurrent As sqlite3_int64 Ptr, _
    ByVal pHighwater As sqlite3_int64 Ptr, _
    ByVal resetFlag As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If sqlite3StatusOperationValid(operation) = 0 OrElse _
       pCurrent = 0 OrElse pHighwater = 0 Then Return SQLITE_MISUSE

    Dim pMutex As Any Ptr = sqlite3StatusMutex(operation)
    sqlite3_mutex_enter(pMutex)
    pCurrent[0] = sqlite3StatusValues(operation).currentValue
    pHighwater[0] = sqlite3StatusValues(operation).highwaterValue
    If resetFlag <> 0 Then
        sqlite3StatusValues(operation).highwaterValue = sqlite3StatusValues(operation).currentValue
    End If
    sqlite3_mutex_leave(pMutex)
    Return SQLITE_OK
End Function

Function sqlite3_status CDecl Alias "sqlite3_status" ( _
    ByVal operation As SQLITE_C_INT, _
    ByVal pCurrent As SQLITE_C_INT Ptr, _
    ByVal pHighwater As SQLITE_C_INT Ptr, _
    ByVal resetFlag As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pCurrent = 0 OrElse pHighwater = 0 Then Return SQLITE_MISUSE
    Dim current As sqlite3_int64 = 0
    Dim highwater As sqlite3_int64 = 0
    Dim rc As SQLITE_C_INT = sqlite3_status64(operation, @current, @highwater, resetFlag)
    If rc = SQLITE_OK Then
        pCurrent[0] = CLng(current)
        pHighwater[0] = CLng(highwater)
    End If
    Return rc
End Function

Function sqlite3_memory_used CDecl Alias "sqlite3_memory_used" () As sqlite3_int64 Export
    Dim current As sqlite3_int64 = 0
    Dim highwater As sqlite3_int64 = 0
    If sqlite3_status64(SQLITE_STATUS_MEMORY_USED, @current, @highwater, 0) <> SQLITE_OK Then Return 0
    Return current
End Function

Function sqlite3_memory_highwater CDecl Alias "sqlite3_memory_highwater" ( _
    ByVal resetFlag As SQLITE_C_INT _
) As sqlite3_int64 Export
    Dim current As sqlite3_int64 = 0
    Dim highwater As sqlite3_int64 = 0
    If sqlite3_status64(SQLITE_STATUS_MEMORY_USED, @current, @highwater, resetFlag) <> SQLITE_OK Then Return 0
    Return highwater
End Function

/' end of sqlite3_status.bas '/
