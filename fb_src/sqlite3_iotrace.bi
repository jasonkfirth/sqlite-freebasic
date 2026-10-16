/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_iotrace.bi

    Purpose:

        Declare the optional VDBE SQL I/O trace callback.

    Responsibilities:

        - Match the C varargs callback ABI used by sqlite3IoTrace.
        - Declare the callback storage and VDBE trace entry point when enabled.

    This file intentionally does NOT contain:

        - Test-runner callbacks or file ownership policy for trace output.
        - Trace formatting or VDBE execution logic.
'/ 

#ifndef SQLITE3_FB_IOTRACE_BI
#define SQLITE3_FB_IOTRACE_BI

#if defined(SQLITE_ENABLE_IOTRACE) AndAlso Not defined(SQLITE_OMIT_TRACE)
#include once "sqlite3_vdbe_core.bi"

Type SqliteIoTraceCallback As Sub CDecl ( _
    ByVal zFormat As Const ZString Ptr, ... _
)

Extern sqlite3IoTrace Alias "sqlite3IoTrace" As SqliteIoTraceCallback
Declare Sub sqlite3VdbeIOTraceSql CDecl Alias "sqlite3VdbeIOTraceSql" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
#endif

#endif

/' end of sqlite3_iotrace.bi '/
