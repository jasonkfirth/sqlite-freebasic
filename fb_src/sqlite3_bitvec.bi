/'
    Project: SQLite FreeBASIC port

    File: sqlite3_bitvec.bi

    Purpose:

        Declare SQLite's opaque Bitvec C ABI for pager and B-tree modules.

    Responsibilities:

        - Expose bitmap allocation, lookup, mutation, and destruction calls.
        - Keep the internal Bitvec representation private to sqlite3_bitvec.bas.

    This file intentionally does NOT contain:

        - The bitmap, hash, or recursive subdivision layout.
        - Pager or B-tree ownership rules.
'/

#ifndef SQLITE3_FB_BITVEC_BI
#define SQLITE3_FB_BITVEC_BI

#include once "sqlite3_types.bi"

Declare Function sqlite3BitvecCreate CDecl Alias "sqlite3BitvecCreate" ( _
    ByVal iSize As u32 _
) As Any Ptr
Declare Function sqlite3BitvecTestNotNull CDecl Alias "sqlite3BitvecTestNotNull" ( _
    ByVal p As Any Ptr, _
    ByVal i As u32 _
) As SQLITE_C_INT
Declare Function sqlite3BitvecTest CDecl Alias "sqlite3BitvecTest" ( _
    ByVal p As Any Ptr, _
    ByVal i As u32 _
) As SQLITE_C_INT
Declare Function sqlite3BitvecSet CDecl Alias "sqlite3BitvecSet" ( _
    ByVal p As Any Ptr, _
    ByVal i As u32 _
) As SQLITE_C_INT
Declare Sub sqlite3BitvecClear CDecl Alias "sqlite3BitvecClear" ( _
    ByVal p As Any Ptr, _
    ByVal i As u32, _
    ByVal pBuffer As Any Ptr _
)
Declare Sub sqlite3BitvecDestroy CDecl Alias "sqlite3BitvecDestroy" (ByVal p As Any Ptr)
Declare Function sqlite3BitvecSize CDecl Alias "sqlite3BitvecSize" (ByVal p As Any Ptr) As u32

#endif

/' end of sqlite3_bitvec.bi '/
