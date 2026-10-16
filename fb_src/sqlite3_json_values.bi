/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_values.bi

    Purpose:

        Declare SQL value-to-JSON helpers and their scalar callbacks.

    Responsibilities:

        - Share the C callback signatures for json_quote() and json_array().
        - Expose the value-appending helper used by JSON string construction.

    This file intentionally does NOT contain:

        - JSON path operations, aggregate functions, or function registration.
'/ 

#ifndef SQLITE3_FB_JSON_VALUES_BI
#define SQLITE3_FB_JSON_VALUES_BI

#include once "sqlite3_json_string.bi"
#include once "sqlite3_result.bi"

Declare Sub jsonAppendSqlValue CDecl Alias "jsonAppendSqlValue" ( _
    ByVal pOutput As JsonString Ptr, _
    ByVal pValue As SqliteVdbeMem Ptr _
)
Declare Sub jsonQuoteFunc CDecl Alias "jsonQuoteFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
Declare Sub jsonArrayFunc CDecl Alias "jsonArrayFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
Declare Sub jsonIdentityFunc CDecl Alias "jsonIdentityFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)

#endif

/' end of sqlite3_json_values.bi '/
