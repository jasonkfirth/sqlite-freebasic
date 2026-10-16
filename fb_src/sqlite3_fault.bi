/'
    Project: SQLite FreeBASIC port

    File: sqlite3_fault.bi

    Purpose:

        Declare the internal hook used to install SQLite fault callbacks.

    Responsibilities:

        - Provide the fault-callback interface used by sqlite3_test_control.
        - Declare begin/end markers for non-fatal allocator work.
        - Declare the fault-simulation callback dispatch.

    This file intentionally does NOT contain:

        - Public API declarations or test-runner implementations.
'/ 

#ifndef SQLITE3_FB_FAULT_BI
#define SQLITE3_FB_FAULT_BI

#include once "sqlite3_types.bi"

Declare Sub sqlite3FaultSimSetCallback CDecl Alias "sqlite3FaultSimSetCallback" ( _
    ByVal pCallback As Any Ptr _
)
Declare Function sqlite3FaultSim CDecl Alias "sqlite3FaultSim" ( _
    ByVal testCode As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Sub sqlite3BeginBenignMalloc CDecl Alias "sqlite3BeginBenignMalloc" ()
Declare Sub sqlite3EndBenignMalloc CDecl Alias "sqlite3EndBenignMalloc" ()

#endif

/' end of sqlite3_fault.bi '/
