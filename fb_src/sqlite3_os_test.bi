/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_os_test.bi

    Purpose:

        Declare the process-wide I/O fault controls used by SQLITE_TEST
        builds and their Unix VFS bridge.

    Responsibilities:

        - Bind the C test harness counters to their SQLite symbol names.
        - Expose the VFS allocation-failure test switch.
        - Declare the shared I/O-error and disk-full decision helpers.

    This file intentionally does NOT contain:

        - Test runner code or fault-injection policy for non-test builds.
'/ 

#ifndef SQLITE3_FB_OS_TEST_BI
#define SQLITE3_FB_OS_TEST_BI

#ifdef SQLITE_TEST
Extern sqlite3_memdebug_vfs_oom_test Alias "sqlite3_memdebug_vfs_oom_test" As SQLITE_C_INT
Extern sqlite3_io_error_hit Alias "sqlite3_io_error_hit" As SQLITE_C_INT
Extern sqlite3_io_error_hardhit Alias "sqlite3_io_error_hardhit" As SQLITE_C_INT
Extern sqlite3_io_error_pending Alias "sqlite3_io_error_pending" As SQLITE_C_INT
Extern sqlite3_io_error_persist Alias "sqlite3_io_error_persist" As SQLITE_C_INT
Extern sqlite3_io_error_benign Alias "sqlite3_io_error_benign" As SQLITE_C_INT
Extern sqlite3_diskfull_pending Alias "sqlite3_diskfull_pending" As SQLITE_C_INT
Extern sqlite3_diskfull Alias "sqlite3_diskfull" As SQLITE_C_INT
Extern sqlite3_open_file_count Alias "sqlite3_open_file_count" As SQLITE_C_INT
Extern sqlite3_sync_count Alias "sqlite3_sync_count" As SQLITE_C_INT
Extern sqlite3_fullsync_count Alias "sqlite3_fullsync_count" As SQLITE_C_INT

Declare Function fbTestSimulateIoError CDecl Alias "fbTestSimulateIoError" () As SQLITE_C_INT
Declare Function fbTestSimulateDiskfull CDecl Alias "fbTestSimulateDiskfull" () As SQLITE_C_INT
Declare Sub fbTestSetIoErrorBenign CDecl Alias "fbTestSetIoErrorBenign" ( _
    ByVal benign As SQLITE_C_INT _
)
#endif

#endif

/' end of sqlite3_os_test.bi '/
