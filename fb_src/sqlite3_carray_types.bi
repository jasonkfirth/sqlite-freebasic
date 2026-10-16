/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_carray_types.bi

    Purpose:

        Define fixed private layouts used by the carray virtual-table module.

    Responsibilities:

        - Preserve the carray bind object and cursor field order.
        - Keep the public sqlite3_vtab_cursor base at the start of the cursor.
        - Describe the system iovec pair used for CARRAY_BLOB inputs.

    This file intentionally does NOT contain:

        - Virtual-table callback implementations or module registration.
        - Runtime offset checks against the C structures.
'/

#ifndef SQLITE3_FB_CARRAY_TYPES_BI
#define SQLITE3_FB_CARRAY_TYPES_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_vtab_types.bi"

#define SQLITE3_CARRAY_COLUMN_VALUE 0
#define SQLITE3_CARRAY_COLUMN_POINTER 1
#define SQLITE3_CARRAY_COLUMN_COUNT 2
#define SQLITE3_CARRAY_COLUMN_CTYPE 3

Type SqliteCarrayBind
    aData As Any Ptr
    nData As SQLITE_C_INT
    mFlags As SQLITE_C_INT
    xDel As Any Ptr
    pDel As Any Ptr
End Type

Type SqliteCarrayCursor
    base As SqliteVtabCursor
    iRowid As sqlite3_int64
    pPtr As Any Ptr
    iCnt As sqlite3_int64
    eType As UByte
End Type

Type SqliteCarrayIovec
    iov_base As Any Ptr
    iov_len As SQLITE_SIZE_T
End Type

#ifdef SQLITE_ENABLE_CARRAY
Declare Function sqlite3CarrayTypeTable CDecl Alias "sqlite3CarrayTypeTable" () _
    As Const ZString Ptr Ptr
#endif

#endif

/' end of sqlite3_carray_types.bi '/
