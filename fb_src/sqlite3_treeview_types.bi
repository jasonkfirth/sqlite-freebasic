/'
    Project: SQLite FreeBASIC port

    File: sqlite3_treeview_types.bi

    Purpose:

        Define the debug-only indentation state used by SQLite's parse-tree
        and query-plan printers.

    Responsibilities:

        - Match TreeView's nesting level and 100 branch-continuation flags.
        - Keep the record available to the treeview module and C2FB candidates.

    This file intentionally does NOT contain:

        - Parse-tree traversal or debug output formatting.
'/

#ifndef SQLITE3_FB_TREEVIEW_TYPES_BI
#define SQLITE3_FB_TREEVIEW_TYPES_BI

#include once "sqlite3_types.bi"

#ifdef SQLITE_DEBUG
Type SqliteTreeView
    iLevel As SQLITE_C_INT
    bLine(0 To 99) As u8
End Type
#endif

#endif

/' end of sqlite3_treeview_types.bi '/
