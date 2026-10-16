/'
    Project: SQLite FreeBASIC port

    File: sqlite3_metadata.bas

    Purpose:

        Provide the version and source identity entry points from SQLite's
        public C API.

    Responsibilities:

        - Export sqlite3_version and the version query functions.
        - Report the compile-time SQLITE_THREADSAFE setting.

    This file intentionally does NOT contain:

        - Database connection state or initialization.
        - SQL parsing, execution, or storage code.
'/

#lang "fb"
#include once "sqlite3_types.bi"

#ifndef SQLITE_THREADSAFE
' Match the serialized default used by a standard SQLite build.
#define SQLITE_THREADSAFE 1
#endif

/'
    These values match VERSION and the source ID generated from the Fossil
    manifest for this checkout. SQLite's generated C header uses the same
    values for SQLITE_VERSION, SQLITE_VERSION_NUMBER, and SQLITE_SOURCE_ID.
'/
Const SQLITE_VERSION_STRING As String = "3.54.0"
' SQLite encodes X.Y.Z as X*1000000 + Y*1000 + Z.
Const SQLITE_VERSION_NUMBER As SQLITE_C_INT = 3054000
Const SQLITE_SOURCE_ID As String = "2026-10-08 12:09:35 ac6ac0c22d98878cdf6042b5801cf5b5dc98c7b48077360d24a70b876921b428"

' Each fixed ZString width includes the terminating NUL byte.
Extern sqlite3_version Alias "sqlite3_version" As Const ZString * 7
Dim Shared sqlite3_version As Const ZString * 7 = SQLITE_VERSION_STRING

Dim Shared sqlite3_source_id_text As Const ZString * 85 = SQLITE_SOURCE_ID

Function sqlite3_libversion CDecl Alias "sqlite3_libversion" () As Const ZString Ptr Export
    Return @sqlite3_version
End Function

Function sqlite3_sourceid CDecl Alias "sqlite3_sourceid" () As Const ZString Ptr Export
    Return @sqlite3_source_id_text
End Function

Function sqlite3_libversion_number CDecl Alias "sqlite3_libversion_number" () As SQLITE_C_INT Export
    Return SQLITE_VERSION_NUMBER
End Function

Function sqlite3_threadsafe CDecl Alias "sqlite3_threadsafe" () As SQLITE_C_INT Export
    Return SQLITE_THREADSAFE
End Function

/' end of sqlite3_metadata.bas '/
