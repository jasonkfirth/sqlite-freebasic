/'
    Project: SQLite FreeBASIC port

    File: sqlite3_fp.bi

    Purpose:

        Declare SQLite's deterministic decimal parser and VDBE real renderer.

    Responsibilities:

        - Preserve the C ABI for sqlite3AtoF.
        - Share parsing and real formatting with VDBE value conversion.

    This file intentionally does NOT contain:

        - The complete SQLite printf formatting API.
'/

#ifndef SQLITE3_FB_FP_BI
#define SQLITE3_FB_FP_BI

#include once "sqlite3_types.bi"

Declare Function sqlite3AtoF CDecl Alias "sqlite3AtoF" ( _
    ByVal z As Const ZString Ptr, _
    ByVal pResult As Double Ptr _
) As SQLITE_C_INT
Declare Function fbFpFormatDouble ( _
    ByVal value As Double, _
    ByVal significantDigits As SQLITE_C_INT, _
    ByVal zOutput As UByte Ptr, _
    ByVal outputSize As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3FpFormatPrintf CDecl Alias "sqlite3FpFormatPrintf" ( _
    ByVal value As Double, _
    ByVal formatType As UByte, _
    ByVal precision As SQLITE_C_INT, _
    ByVal alternateForm As SQLITE_C_INT, _
    ByVal zeroPad As SQLITE_C_INT, _
    ByVal thousands As SQLITE_C_INT, _
    ByVal trimZeroes As SQLITE_C_INT, _
    ByVal zOutput As UByte Ptr, _
    ByVal outputSize As SQLITE_C_INT _
) As SQLITE_C_INT

#endif

/' end of sqlite3_fp.bi '/
