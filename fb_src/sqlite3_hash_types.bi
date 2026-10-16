/'
    Project: SQLite FreeBASIC port

    File: sqlite3_hash_types.bi

    Purpose:

        Define the internal Hash and HashElem layouts from src/hash.h.

    Responsibilities:

        - Preserve the C field widths and pointer relationships.
        - Make the hash-table structures available to engine modules.
        - Declare the C ABI entry points implemented in sqlite3_hash.bas.

    This file intentionally does NOT contain:

        - Hashing, allocation, or lookup routines.
        - Database connection state.
'/

#ifndef SQLITE3_FB_HASH_TYPES_BI
#define SQLITE3_FB_HASH_TYPES_BI

#include once "sqlite3_types.bi"

Type HashElem
    next As HashElem Ptr
    prev As HashElem Ptr
    data As Any Ptr
    ' SQLite treats the referenced key as immutable.  The implementation never
    ' writes through this pointer.
    pKey As ZString Ptr
    h As SQLITE_C_UINT
End Type

Type HashBucket
    count As SQLITE_C_UINT
    chain As HashElem Ptr
End Type

Type Hash
    htsize As SQLITE_C_UINT
    count As SQLITE_C_UINT
    first As HashElem Ptr
    ht As HashBucket Ptr
End Type

Declare Sub sqlite3HashInit CDecl Alias "sqlite3HashInit" (ByVal pHash As Hash Ptr)
Declare Sub sqlite3HashClear CDecl Alias "sqlite3HashClear" (ByVal pHash As Hash Ptr)
Declare Function sqlite3HashFind CDecl Alias "sqlite3HashFind" ( _
    ByVal pHash As Const Hash Ptr, _
    ByVal pKey As Const ZString Ptr _
) As Any Ptr
Declare Function sqlite3HashInsert CDecl Alias "sqlite3HashInsert" ( _
    ByVal pHash As Hash Ptr, _
    ByVal pKey As Const ZString Ptr, _
    ByVal pData As Any Ptr _
) As Any Ptr

#endif

/' end of sqlite3_hash_types.bi '/
