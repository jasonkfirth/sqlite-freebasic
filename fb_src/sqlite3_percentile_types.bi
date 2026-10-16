/'
    Project: SQLite FreeBASIC port

    File: sqlite3_percentile_types.bi

    Purpose:

        Define the aggregate context used by SQLite's optional percentile functions.

    Responsibilities:

        - Preserve the value buffer, sorted state, and percentile fraction.
        - Match the fixed context cleared by percentile finalization.

    This file intentionally does NOT contain:

        - Percentile sample insertion, sorting, or interpolation.
'/ 

#ifndef SQLITE3_FB_PERCENTILE_TYPES_BI
#define SQLITE3_FB_PERCENTILE_TYPES_BI

#include once "sqlite3_types.bi"

Type SqlitePercentileContext
    nAlloc As sqlite3_uint64
    nUsed As sqlite3_uint64
    bSorted As Byte
    bKeepSorted As Byte
    bPctValid As Byte
    rPct As Double
    a As Double Ptr
End Type

#endif

/' end of sqlite3_percentile_types.bi '/
