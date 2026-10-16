/'
    Project: SQLite FreeBASIC port

    File: sqlite3_window_state.bi

    Purpose:

        Define the aggregate and rewrite-rule records used by SQLite's built-in
        window callbacks.

    Responsibilities:

        - Match the fixed C layouts for rank, ntile, nth_value, and last_value.
        - Preserve value-cell pointers used by window aggregate contexts.
        - Match the local name/frame rule records used by sqlite3WindowUpdate().
        - Describe the window-code generation context and stable builtin names.

    This file intentionally does NOT contain:

        - Window frame planning or VDBE code generation.
        - Runtime behavior for the window functions.
'/

#ifndef SQLITE3_FB_WINDOW_STATE_BI
#define SQLITE3_FB_WINDOW_STATE_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_vdbe_mem_types.bi"

Type SqliteWindowCallCount
    nValue As sqlite3_int64
    nStep As sqlite3_int64
    nTotal As sqlite3_int64
End Type

Type SqliteWindowNthValueCtx
    nStep As sqlite3_int64
    pValue As SqliteVdbeMem Ptr
End Type

Type SqliteWindowNtileCtx
    nTotal As sqlite3_int64
    nParam As sqlite3_int64
    iRow As sqlite3_int64
End Type

Type SqliteWindowLastValueCtx
    pVal As SqliteVdbeMem Ptr
    nVal As SQLITE_C_INT
End Type

' The source-local WindowUpdate record is a fixed C array element.
Type SqliteWindowUpdateRule
    zFunc As Const ZString Ptr
    eFrmType As SQLITE_C_INT
    eStart As SQLITE_C_INT
    eEnd As SQLITE_C_INT
End Type

' Stack context passed between the C window-code-generation helpers. The
' connection, parser, and Window pointers stay opaque here; C2FB uses source
' field types for typed reads and writes through those slots.
Type SqliteWindowCursorRegister
    csr As SQLITE_C_INT
    reg As SQLITE_C_INT
End Type

Type SqliteWindowCodeContext
    pParse As Any Ptr
    pMWin As Any Ptr
    pVdbe As Any Ptr
    addrGosub As SQLITE_C_INT
    regGosub As SQLITE_C_INT
    regArg As SQLITE_C_INT
    eDelete As SQLITE_C_INT
    regRowid As SQLITE_C_INT
    start As SqliteWindowCursorRegister
    current As SqliteWindowCursorRegister
    ending As SqliteWindowCursorRegister
End Type

' C compares built-in window names by address, so registration and VDBE code
' generation must use the same stable byte strings.
Const SQLITE_WINDOW_NAME_ROW_NUMBER = 1
Const SQLITE_WINDOW_NAME_DENSE_RANK = 2
Const SQLITE_WINDOW_NAME_RANK = 3
Const SQLITE_WINDOW_NAME_PERCENT_RANK = 4
Const SQLITE_WINDOW_NAME_CUME_DIST = 5
Const SQLITE_WINDOW_NAME_NTILE = 6
Const SQLITE_WINDOW_NAME_LAST_VALUE = 7
Const SQLITE_WINDOW_NAME_NTH_VALUE = 8
Const SQLITE_WINDOW_NAME_FIRST_VALUE = 9
Const SQLITE_WINDOW_NAME_LEAD = 10
Const SQLITE_WINDOW_NAME_LAG = 11

Declare Function sqlite3WindowFunctionName CDecl Alias "sqlite3WindowFunctionName" ( _
    ByVal nameId As SQLITE_C_INT _
) As Const ZString Ptr

Declare Function sqlite3WindowNoopStepFunction CDecl Alias "sqlite3WindowNoopStepFunction" () As Any Ptr

#endif

/' end of sqlite3_window_state.bi '/
