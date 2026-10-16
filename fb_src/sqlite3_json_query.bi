/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_query.bi

    Purpose:

        Declare JSONB path lookup and simple query callbacks.

    Responsibilities:

        - Define path-error reporting and read-only node lookup interfaces.
        - Declare json_type() and json_array_length() callbacks.

    This file intentionally does NOT contain:

        - JSON mutation operations, extraction callbacks, or virtual tables.
'/ 

#ifndef SQLITE3_FB_JSON_QUERY_BI
#define SQLITE3_FB_JSON_QUERY_BI

#include once "sqlite3_json_parse.bi"
#include once "sqlite3_result.bi"

Declare Function jsonBadPathError CDecl Alias "jsonBadPathError" ( _
    ByVal pContext As Any Ptr, _
    ByVal zPath As Const UByte Ptr, _
    ByVal resultCode As u32 _
) As ZString Ptr
Declare Sub jsonArrayLengthFunc CDecl Alias "jsonArrayLengthFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
Declare Sub jsonTypeFunc CDecl Alias "jsonTypeFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)

#endif

/' end of sqlite3_json_query.bi '/
