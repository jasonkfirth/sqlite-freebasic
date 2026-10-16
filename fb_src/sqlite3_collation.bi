/'
    Project: SQLite FreeBASIC port

    File: sqlite3_collation.bi

    Purpose:

        Declare the internal collation callback and registration interfaces.

    Responsibilities:

        - Share the C-compatible comparison callback type.
        - Expose the registration helper used while opening connections.
        - Keep the ASCII NOCASE and RTRIM callbacks callable across modules.

    This file intentionally does NOT contain:

        - The per-connection collation registry or lookup policy.
        - Unicode collation implementations.
'/ 

#ifndef SQLITE3_FB_COLLATION_BI
#define SQLITE3_FB_COLLATION_BI

#include once "sqlite3_db_types.bi"
#include once "sqlite3_vdbe_compare.bi"

Declare Function createCollation CDecl Alias "createCollation" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal eTextRep As u8, _
    ByVal pContext As Any Ptr, _
    ByVal xCompare As sqlite3CollationCompare, _
    ByVal xDestroy As SqliteDbDestructor _
) As SQLITE_C_INT
Declare Function rtrimCollFunc CDecl Alias "rtrimCollFunc" ( _
    ByVal pUser As Any Ptr, _
    ByVal nLeft As SQLITE_C_INT, _
    ByVal pLeft As Const Any Ptr, _
    ByVal nRight As SQLITE_C_INT, _
    ByVal pRight As Const Any Ptr _
) As SQLITE_C_INT
Declare Function nocaseCollatingFunc CDecl Alias "nocaseCollatingFunc" ( _
    ByVal pUser As Any Ptr, _
    ByVal nLeft As SQLITE_C_INT, _
    ByVal pLeft As Const Any Ptr, _
    ByVal nRight As SQLITE_C_INT, _
    ByVal pRight As Const Any Ptr _
) As SQLITE_C_INT

#endif

/' end of sqlite3_collation.bi '/
