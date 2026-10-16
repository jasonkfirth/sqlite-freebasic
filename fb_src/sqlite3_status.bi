/'
    Project: SQLite FreeBASIC port

    File: sqlite3_status.bi

    Purpose:

        Declare SQLite's global status counters and public status APIs.

    Responsibilities:

        - Expose process-wide allocation and page-cache status identifiers.
        - Declare the status counter operations used by allocator modules.

    This file intentionally does NOT contain:

        - Per-connection sqlite3_db_status() counters.
        - Pager or page-cache measurement logic.
'/

#ifndef SQLITE3_FB_STATUS_BI
#define SQLITE3_FB_STATUS_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"

Declare Function sqlite3StatusValue CDecl Alias "sqlite3StatusValue" ( _
    ByVal operation As SQLITE_C_INT _
) As sqlite3_int64
Declare Sub sqlite3StatusUp CDecl Alias "sqlite3StatusUp" ( _
    ByVal operation As SQLITE_C_INT, _
    ByVal amount As SQLITE_C_INT _
)
Declare Sub sqlite3StatusDown CDecl Alias "sqlite3StatusDown" ( _
    ByVal operation As SQLITE_C_INT, _
    ByVal amount As SQLITE_C_INT _
)
Declare Sub sqlite3StatusHighwater CDecl Alias "sqlite3StatusHighwater" ( _
    ByVal operation As SQLITE_C_INT, _
    ByVal value As SQLITE_C_INT _
)
Declare Function sqlite3MallocMutex CDecl Alias "sqlite3MallocMutex" () As Any Ptr
Declare Function sqlite3Pcache1Mutex CDecl Alias "sqlite3Pcache1Mutex" () As Any Ptr

Declare Function sqlite3_status64 CDecl Alias "sqlite3_status64" ( _
    ByVal operation As SQLITE_C_INT, _
    ByVal pCurrent As sqlite3_int64 Ptr, _
    ByVal pHighwater As sqlite3_int64 Ptr, _
    ByVal resetFlag As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3_status CDecl Alias "sqlite3_status" ( _
    ByVal operation As SQLITE_C_INT, _
    ByVal pCurrent As SQLITE_C_INT Ptr, _
    ByVal pHighwater As SQLITE_C_INT Ptr, _
    ByVal resetFlag As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3_memory_used CDecl Alias "sqlite3_memory_used" () As sqlite3_int64
Declare Function sqlite3_memory_highwater CDecl Alias "sqlite3_memory_highwater" ( _
    ByVal resetFlag As SQLITE_C_INT _
) As sqlite3_int64

#endif

/' end of sqlite3_status.bi '/
