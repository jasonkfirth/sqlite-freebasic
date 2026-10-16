/'
    Project: SQLite FreeBASIC port

    File: sqlite3_function_aggregate_contexts.bi

    Purpose:

        Declare the storage records used by built-in aggregate callbacks.

    Responsibilities:

        - Keep sum and average accumulation state visible to body candidates.
        - Describe the FreeBASIC group-concat context used by the port.
        - Keep callback context layouts separate from callback implementations.

    This file intentionally does NOT contain:

        - Aggregate callback logic or function registration.
        - Claims that the group-concat context matches SQLite's C layout.
'/

#ifndef SQLITE3_FB_FUNCTION_AGGREGATE_CONTEXTS_BI
#define SQLITE3_FB_FUNCTION_AGGREGATE_CONTEXTS_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_straccum.bi"

Type SqliteSumContext
    rSum As Double
    rErr As Double
    iSum As sqlite3_int64
    cnt As sqlite3_int64
    approx As u8
    ovrfl As u8
End Type

Type SqliteGroupConcatContext
    accumulator As sqlite3_str
    termCount As sqlite3_int64
    firstSeparatorLength As SQLITE_C_INT
    separatorLengths As SQLITE_C_INT Ptr
End Type

#endif

/' end of sqlite3_function_aggregate_contexts.bi '/
