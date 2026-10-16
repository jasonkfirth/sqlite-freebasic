/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_sqllog.bi

    Purpose:

        Declare the optional SQLite SQL log callback and dispatch helpers.

    Responsibilities:

        - Match the SQLITE_CONFIG_SQLLOG callback ABI.
        - Expose the feature-gated callback registration and invocation helpers.

    This file intentionally does NOT contain:

        - The test_sqllog.c implementation or log storage policy.
        - SQL expansion or VDBE execution.
'/ 

#ifndef SQLITE3_FB_SQLLOG_BI
#define SQLITE3_FB_SQLLOG_BI

#ifdef SQLITE_ENABLE_SQLLOG
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"

Type SqliteSqllogCallback As Sub CDecl ( _
    ByVal pArgument As Any Ptr, _
    ByVal pDatabase As sqlite3 Ptr, _
    ByVal zSql As Const ZString Ptr, _
    ByVal eventType As SQLITE_C_INT _
)

Declare Function sqlite3SqllogEnabled CDecl Alias "sqlite3SqllogEnabled" () _
    As SQLITE_C_INT
Declare Sub sqlite3SqllogInvoke CDecl Alias "sqlite3SqllogInvoke" ( _
    ByVal pDatabase As sqlite3 Ptr, _
    ByVal zSql As Const ZString Ptr, _
    ByVal eventType As SQLITE_C_INT _
)
#endif

#endif

/' end of sqlite3_sqllog.bi '/
