/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_insert_helpers.bi

    Purpose:

        Declare shared INSERT helper procedures whose C linkage is file-local.

    Responsibilities:

        - Share the AUTOINCREMENT setup helper with the transfer-optimization batch.

    This file intentionally does NOT contain:

        - INSERT planning or VDBE generation.
        - The AUTOINCREMENT helper implementation.
'/

#ifndef SQLITE3_FB_INSERT_HELPERS_BI
#define SQLITE3_FB_INSERT_HELPERS_BI

#include once "sqlite3_types.bi"

Declare Function autoIncBegin CDecl Alias "autoIncBegin" ( _
    ByVal parseArgument As Any Ptr, _
    ByVal databaseIndex As SQLITE_C_INT, _
    ByVal tableArgument As Any Ptr _
) As SQLITE_C_INT

#endif

/' end of sqlite3_insert_helpers.bi '/
