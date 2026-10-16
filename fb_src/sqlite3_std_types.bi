/'
    Project: SQLite FreeBASIC port

    File: sqlite3_std_types.bi

    Purpose:

        Declare stable access to SQLite's standard type-name table.

    Responsibilities:

        - Expose the C-ordered standard type-name pointer array.

    This file intentionally does NOT contain:

        - Type affinity or schema validation behavior.
'/

#ifndef SQLITE3_FB_STD_TYPES_BI
#define SQLITE3_FB_STD_TYPES_BI

Declare Function sqlite3StdTypeTable CDecl Alias "sqlite3StdTypeTable" () As Const ZString Ptr Ptr

#endif

/' end of sqlite3_std_types.bi '/
