/'
    Project: SQLite FreeBASIC port

    File: sqlite3_mutex.bi

    Purpose:

        Declare SQLite's public mutex API and internal lifecycle entry points.

    Responsibilities:

        - Expose dynamic and static mutex operations to C callers.
        - Declare mutex subsystem initialization for connection setup.

    This file intentionally does NOT contain:

        - Mutex storage or pthread implementation details.
        - Runtime initialization of the SQLite library.
'/

#ifndef SQLITE3_FB_MUTEX_BI
#define SQLITE3_FB_MUTEX_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"

Declare Function sqlite3_mutex_alloc CDecl Alias "sqlite3_mutex_alloc" ( _
    ByVal mutexType As SQLITE_C_INT _
) As Any Ptr
Declare Sub sqlite3_mutex_free CDecl Alias "sqlite3_mutex_free" (ByVal pMutex As Any Ptr)
Declare Sub sqlite3_mutex_enter CDecl Alias "sqlite3_mutex_enter" (ByVal pMutex As Any Ptr)
Declare Function sqlite3_mutex_try CDecl Alias "sqlite3_mutex_try" ( _
    ByVal pMutex As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3_mutex_leave CDecl Alias "sqlite3_mutex_leave" (ByVal pMutex As Any Ptr)
Declare Function sqlite3_mutex_held CDecl Alias "sqlite3_mutex_held" ( _
    ByVal pMutex As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_mutex_notheld CDecl Alias "sqlite3_mutex_notheld" ( _
    ByVal pMutex As Any Ptr _
) As SQLITE_C_INT

Declare Function sqlite3MutexInit CDecl Alias "sqlite3MutexInit" () As SQLITE_C_INT
Declare Function sqlite3MutexEnd CDecl Alias "sqlite3MutexEnd" () As SQLITE_C_INT
Declare Function sqlite3MutexAlloc CDecl Alias "sqlite3MutexAlloc" ( _
    ByVal mutexType As SQLITE_C_INT _
) As Any Ptr
Declare Function sqlite3MutexConfigSetMethods CDecl Alias "sqlite3MutexConfigSetMethods" ( _
    ByVal pMethods As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3MutexConfigGetMethods CDecl Alias "sqlite3MutexConfigGetMethods" ( _
    ByVal pMethods As Any Ptr _
)
Declare Sub sqlite3MemoryBarrier CDecl Alias "sqlite3MemoryBarrier" ()

#endif

/' end of sqlite3_mutex.bi '/
