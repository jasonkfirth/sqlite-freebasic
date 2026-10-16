/'
    Project: SQLite FreeBASIC port

    File: sqlite3_process_globals.bi

    Purpose:

        Declare public process-wide directory variables shared with the VFS.

    Responsibilities:

        - Expose the C ABI globals for temporary and data directory overrides.
        - Keep declarations separate from the single storage definition.

    This file intentionally does NOT contain:

        - Allocation, ownership, or configuration policy for the pointed-to paths.
'/

#ifndef SQLITE3_FB_PROCESS_GLOBALS_BI
#define SQLITE3_FB_PROCESS_GLOBALS_BI

Extern sqlite3_temp_directory Alias "sqlite3_temp_directory" As ZString Ptr
Extern sqlite3_data_directory Alias "sqlite3_data_directory" As ZString Ptr

#endif

/' end of sqlite3_process_globals.bi '/
