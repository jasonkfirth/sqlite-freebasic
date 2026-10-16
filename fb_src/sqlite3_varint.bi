/'
    Project: SQLite FreeBASIC port

    File: sqlite3_varint.bi

    Purpose:

        Declare SQLite variable-length and big-endian integer helpers.

    Responsibilities:

        - Preserve C ABI for 64-bit varints and four/eight-byte big-endian values.

    This file intentionally does NOT contain:

        - B-tree cell parsing or page I/O.
'/

#ifndef SQLITE3_FB_VARINT_BI
#define SQLITE3_FB_VARINT_BI

#include once "sqlite3_types.bi"

Declare Function sqlite3PutVarint CDecl Alias "sqlite3PutVarint" ( _
    ByVal zOut As UByte Ptr, _
    ByVal value As sqlite3_uint64 _
) As SQLITE_C_INT
Declare Function sqlite3GetVarint CDecl Alias "sqlite3GetVarint" ( _
    ByVal zIn As Const UByte Ptr, _
    ByVal pValue As sqlite3_uint64 Ptr _
) As u8
Declare Function sqlite3VarintValue CDecl Alias "sqlite3VarintValue" ( _
    ByVal zIn As Const UByte Ptr _
) As sqlite3_int64
Declare Function sqlite3GetVarint32 CDecl Alias "sqlite3GetVarint32" ( _
    ByVal zIn As Const UByte Ptr, _
    ByVal pValue As u32 Ptr _
) As u8
Declare Function sqlite3VarintLen CDecl Alias "sqlite3VarintLen" ( _
    ByVal value As sqlite3_uint64 _
) As SQLITE_C_INT
Declare Function sqlite3Get4byte CDecl Alias "sqlite3Get4byte" ( _
    ByVal p As Const UByte Ptr _
) As u32
Declare Sub sqlite3Put4byte CDecl Alias "sqlite3Put4byte" ( _
    ByVal p As UByte Ptr, _
    ByVal value As u32 _
)
Declare Function sqlite3Get8byte CDecl Alias "sqlite3Get8byte" ( _
    ByVal p As Const UByte Ptr _
) As sqlite3_uint64

#endif

/' end of sqlite3_varint.bi '/
