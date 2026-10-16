/'
    Project: SQLite FreeBASIC port

    File: sqlite3_stat4_types.bi

    Purpose:

        Define the fixed STAT4 sampling records used by ANALYZE.

    Responsibilities:

        - Preserve the fields used by StatSample and StatAccum procedures.
        - Match the optional STAT4 record shape under SQLITE_ENABLE_STAT4.

    This file intentionally does NOT contain:

        - Sample selection, histogram loading, or planner estimates.
'/ 

#ifndef SQLITE3_FB_STAT4_TYPES_BI
#define SQLITE3_FB_STAT4_TYPES_BI

#include once "sqlite3_types.bi"

Union SqliteStatSampleRowKey
    iRowid As sqlite3_int64
    aRowid As UByte Ptr
End Union

Type SqliteStatSample
    anDLt As sqlite3_uint64 Ptr
#ifdef SQLITE_ENABLE_STAT4
    anEq As sqlite3_uint64 Ptr
    anLt As sqlite3_uint64 Ptr
    u As SqliteStatSampleRowKey
    nRowid As u32
    isPSample As u8
    iCol As SQLITE_C_INT
    iHash As u32
#endif
End Type

Type SqliteStatAccum
    db As sqlite3 Ptr
    nEst As sqlite3_uint64
    nRow As sqlite3_uint64
    nLimit As SQLITE_C_INT
    nCol As SQLITE_C_INT
    nKeyCol As SQLITE_C_INT
    nSkipAhead As u8
    current As SqliteStatSample
#ifdef SQLITE_ENABLE_STAT4
    nPSample As sqlite3_uint64
    mxSample As SQLITE_C_INT
    iPrn As u32
    aBest As SqliteStatSample Ptr
    iMin As SQLITE_C_INT
    nSample As SQLITE_C_INT
    nMaxEqZero As SQLITE_C_INT
    iGet As SQLITE_C_INT
    a As SqliteStatSample Ptr
#endif
End Type

#endif

/' end of sqlite3_stat4_types.bi '/
