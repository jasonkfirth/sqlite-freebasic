/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_vdbe_test.bi

    Purpose:

        Declare the SQLITE_TEST counters used to verify VDBE search and sort
        behavior in SQLite's C test driver.

    Responsibilities:

        - Bind VDBE execution counters to their established C symbol names.

    This file intentionally does NOT contain:

        - VDBE execution logic or test-runner code.
'/ 

#ifndef SQLITE3_FB_VDBE_TEST_BI
#define SQLITE3_FB_VDBE_TEST_BI

#ifdef SQLITE_TEST
Extern sqlite3_search_count Alias "sqlite3_search_count" As SQLITE_C_INT
Extern sqlite3_found_count Alias "sqlite3_found_count" As SQLITE_C_INT
Extern sqlite3_sort_count Alias "sqlite3_sort_count" As SQLITE_C_INT
#endif

#endif

/' end of sqlite3_vdbe_test.bi '/
