/'
    Project: SQLite FreeBASIC port

    File: sqlite3_win_exception_types.bi

    Purpose:

        Describe the Windows exception records inspected by WAL SEH support.

    Responsibilities:

        - Match EXCEPTION_RECORD fields used by the WAL exception filter.
        - Match the two-pointer EXCEPTION_POINTERS record.
        - Keep the pointer-sized exception arguments aligned with the target.

    This file intentionally does NOT contain:

        - Exception dispatch, WAL cleanup, or Windows API imports.
        - CONTEXT record fields, which SQLite does not inspect.
'/

#ifndef SQLITE3_WIN_EXCEPTION_TYPES_BI
#define SQLITE3_WIN_EXCEPTION_TYPES_BI

#ifdef SQLITE_OS_WIN

Type SqliteWinExceptionRecord
    exceptionCode As SQLITE_C_UINT
    exceptionFlags As SQLITE_C_UINT
    pExceptionRecord As SqliteWinExceptionRecord Ptr
    pExceptionAddress As Any Ptr
    numberParameters As SQLITE_C_UINT
    ' Windows defines fifteen pointer-sized exception arguments in this record.
    exceptionInformation(0 To 14) As SQLITE_SIZE_T
End Type

Type SqliteWinExceptionPointers
    pExceptionRecord As SqliteWinExceptionRecord Ptr
    pContextRecord As Any Ptr
End Type

#endif

#endif

/' end of sqlite3_win_exception_types.bi '/
