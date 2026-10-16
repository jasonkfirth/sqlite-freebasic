/'
    Project: SQLite FreeBASIC port

    File: sqlite3_fault.bas

    Purpose:

        Port the benign-allocation hooks from src/fault.c.

    Responsibilities:

        - Retain optional begin/end callbacks for benign allocation regions.
        - Invoke each callback when its corresponding region boundary is reached.

    This file intentionally does NOT contain:

        - Test-only fault injection or the SQLITE_TESTCTRL callback.
        - Memory allocator policy or allocation error handling.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_fault.bi"

Type sqlite3BenignMallocCallback As Sub CDecl ()
Type sqlite3FaultSimulationCallback As Function CDecl ( _
    ByVal testCode As SQLITE_C_INT _
) As SQLITE_C_INT

Private Dim Shared sqlite3BenignMallocBeginCallback As sqlite3BenignMallocCallback
Private Dim Shared sqlite3BenignMallocEndCallback As sqlite3BenignMallocCallback
Private Dim Shared sqlite3FaultCallback As sqlite3FaultSimulationCallback

Sub sqlite3BenignMallocHooks CDecl Alias "sqlite3BenignMallocHooks" ( _
    ByVal pBeginCallback As Any Ptr, _
    ByVal pEndCallback As Any Ptr _
)
    sqlite3BenignMallocBeginCallback = _
        CPtr(sqlite3BenignMallocCallback, pBeginCallback)
    sqlite3BenignMallocEndCallback = _
        CPtr(sqlite3BenignMallocCallback, pEndCallback)
End Sub

Sub sqlite3BeginBenignMalloc CDecl Alias "sqlite3BeginBenignMalloc" () Export
    If sqlite3BenignMallocBeginCallback <> 0 Then _
        sqlite3BenignMallocBeginCallback()
End Sub

Sub sqlite3EndBenignMalloc CDecl Alias "sqlite3EndBenignMalloc" () Export
    If sqlite3BenignMallocEndCallback <> 0 Then _
        sqlite3BenignMallocEndCallback()
End Sub

Function sqlite3FaultSim CDecl Alias "sqlite3FaultSim" ( _
    ByVal testCode As SQLITE_C_INT _
) As SQLITE_C_INT
    If sqlite3FaultCallback = 0 Then Return SQLITE_OK
    Return sqlite3FaultCallback(testCode)
End Function

Sub sqlite3FaultSimSetCallback CDecl Alias "sqlite3FaultSimSetCallback" ( _
    ByVal pCallback As Any Ptr _
)
    sqlite3FaultCallback = CPtr(sqlite3FaultSimulationCallback, pCallback)
End Sub

/' end of sqlite3_fault.bas '/
