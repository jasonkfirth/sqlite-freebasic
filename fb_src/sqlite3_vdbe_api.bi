/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_api.bi

    Purpose:

        Declare scalar sqlite3_value accessors implemented over VDBE Mem cells.

    Responsibilities:

        - Preserve the C ABI for numeric and storage-class value accessors.
        - Declare the supported sqlite3_value conversion entry points.
        - Describe the iterator object used to pass an IN value list to a vtab.

    This file intentionally does NOT contain:

        - Text rendering, column accessors, or statement execution APIs.
'/

#ifndef SQLITE3_FB_VDBE_API_BI
#define SQLITE3_FB_VDBE_API_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_btree.bi"
#include once "sqlite3_vdbe_mem_types.bi"

/' The temporary cursor and output Mem used by sqlite3_vtab_in_first/next. '/
Type SqliteValueList
    pCsr As BtCursor Ptr
    pOut As SqliteVdbeMem Ptr
End Type

Declare Function sqlite3_value_type CDecl Alias "sqlite3_value_type" ( _
    ByVal pValue As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_value_numeric_type CDecl Alias "sqlite3_value_numeric_type" ( _
    ByVal pValue As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_value_double CDecl Alias "sqlite3_value_double" ( _
    ByVal pValue As Any Ptr _
) As Double
Declare Function sqlite3_value_int64 CDecl Alias "sqlite3_value_int64" ( _
    ByVal pValue As Any Ptr _
) As sqlite3_int64
Declare Function sqlite3_value_int CDecl Alias "sqlite3_value_int" ( _
    ByVal pValue As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_value_encoding CDecl Alias "sqlite3_value_encoding" ( _
    ByVal pValue As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_value_subtype CDecl Alias "sqlite3_value_subtype" ( _
    ByVal pValue As Any Ptr _
) As SQLITE_C_UINT
Declare Function sqlite3_value_pointer CDecl Alias "sqlite3_value_pointer" ( _
    ByVal pValue As Any Ptr, _
    ByVal zType As Const ZString Ptr _
) As Any Ptr
Declare Function sqlite3_value_nochange CDecl Alias "sqlite3_value_nochange" ( _
    ByVal pValue As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_value_frombind CDecl Alias "sqlite3_value_frombind" ( _
    ByVal pValue As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_value_dup CDecl Alias "sqlite3_value_dup" ( _
    ByVal pValue As Const SqliteVdbeMem Ptr _
) As Any Ptr
Declare Sub sqlite3_value_free CDecl Alias "sqlite3_value_free" ( _
    ByVal pValue As Any Ptr _
)
Declare Function sqlite3_value_blob CDecl Alias "sqlite3_value_blob" ( _
    ByVal pValue As Any Ptr _
) As Any Ptr
Declare Function sqlite3_value_text CDecl Alias "sqlite3_value_text" ( _
    ByVal pValue As Any Ptr _
) As Const UByte Ptr
Declare Function sqlite3_value_text16 CDecl Alias "sqlite3_value_text16" ( _
    ByVal pValue As Any Ptr _
) As Any Ptr
Declare Function sqlite3_value_text16le CDecl Alias "sqlite3_value_text16le" ( _
    ByVal pValue As Any Ptr _
) As Any Ptr
Declare Function sqlite3_value_text16be CDecl Alias "sqlite3_value_text16be" ( _
    ByVal pValue As Any Ptr _
) As Any Ptr
Declare Function sqlite3_value_bytes CDecl Alias "sqlite3_value_bytes" ( _
    ByVal pValue As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_value_bytes16 CDecl Alias "sqlite3_value_bytes16" ( _
    ByVal pValue As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_vtab_in_first CDecl Alias "sqlite3_vtab_in_first" ( _
    ByVal pValue As Any Ptr, _
    ByVal ppOut As Any Ptr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_vtab_in_next CDecl Alias "sqlite3_vtab_in_next" ( _
    ByVal pValue As Any Ptr, _
    ByVal ppOut As Any Ptr Ptr _
) As SQLITE_C_INT

#endif

/' end of sqlite3_vdbe_api.bi '/
