/'
    Project: SQLite FreeBASIC port

    File: sqlite3_numeric.bi

    Purpose:

        Declare SQLite's integer parsing helpers.

    Responsibilities:

        - Preserve the C ABI for integer conversion from UTF-8 and UTF-16.
        - Share integer token parsers with VDBE value-cell routines.

    This file intentionally does NOT contain:

        - Floating-point text conversion or SQL affinity logic.
'/

#ifndef SQLITE3_FB_NUMERIC_BI
#define SQLITE3_FB_NUMERIC_BI

#include once "sqlite3_types.bi"

Declare Function sqlite3Atoi64 CDecl Alias "sqlite3Atoi64" ( _
    ByVal zNum As Const Any Ptr, _
    ByVal pNum As sqlite3_int64 Ptr, _
    ByVal length As SQLITE_C_INT, _
    ByVal enc As u8 _
) As SQLITE_C_INT
Declare Function sqlite3DecOrHexToI64 CDecl Alias "sqlite3DecOrHexToI64" ( _
    ByVal zNum As Const ZString Ptr, _
    ByVal pNum As sqlite3_int64 Ptr _
) As SQLITE_C_INT
Declare Function sqlite3GetInt32 CDecl Alias "sqlite3GetInt32" ( _
    ByVal zNum As Const ZString Ptr, _
    ByVal pValue As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Function sqlite3Atoi CDecl Alias "sqlite3Atoi" ( _
    ByVal zNum As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3Int64ToText CDecl Alias "sqlite3Int64ToText" ( _
    ByVal value As sqlite3_int64, _
    ByVal zOut As ZString Ptr _
) As SQLITE_C_INT

#endif

/' end of sqlite3_numeric.bi '/
