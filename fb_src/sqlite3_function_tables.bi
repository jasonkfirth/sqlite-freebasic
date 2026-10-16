/'
    Project: SQLite FreeBASIC port

    File: sqlite3_function_tables.bi

    Purpose:

        Declare static compare-info records stored in FuncDef tables.

    Responsibilities:

        - Preserve the four-byte C compareInfo record layout.
        - Expose LIKE and GLOB records at stable addresses for C-style tables.

    This file intentionally does NOT contain:

        - LIKE/GLOB matching logic or function registration.
'/

#ifndef SQLITE3_FB_FUNCTION_TABLES_BI
#define SQLITE3_FB_FUNCTION_TABLES_BI

Type SqliteLikeCompareInfo
    matchAll As UByte
    matchOne As UByte
    matchSet As UByte
    noCase As UByte
End Type

Extern sqlite3LikeCompareInfo Alias "sqlite3LikeCompareInfo" As SqliteLikeCompareInfo
Extern sqlite3LikeCompareInfoAlt Alias "sqlite3LikeCompareInfoAlt" As SqliteLikeCompareInfo
Extern sqlite3GlobCompareInfo Alias "sqlite3GlobCompareInfo" As SqliteLikeCompareInfo

#endif

/' end of sqlite3_function_tables.bi '/
