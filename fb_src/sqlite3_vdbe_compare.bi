/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_compare.bi

    Purpose:

        Declare numeric, binary-text, and Mem comparison primitives.

    Responsibilities:

        - Preserve C calling conventions for integer/real, BINARY text, and Mem comparison.
        - Describe the CollSeq callback layout used by text comparisons.

    This file intentionally does NOT contain:

        - The collation registry or non-BINARY collation implementations.
'/

#ifndef SQLITE3_FB_VDBE_COMPARE_BI
#define SQLITE3_FB_VDBE_COMPARE_BI

#include once "sqlite3_types.bi"

Type sqlite3CollationCompare As Function CDecl ( _
    ByVal pUser As Any Ptr, _
    ByVal nLeft As SQLITE_C_INT, _
    ByVal pLeft As Const Any Ptr, _
    ByVal nRight As SQLITE_C_INT, _
    ByVal pRight As Const Any Ptr _
) As SQLITE_C_INT

Type sqlite3CollSeq
    zName As ZString Ptr
    enc As u8
    pUser As Any Ptr
    xCmp As sqlite3CollationCompare
    xDel As Sub CDecl (ByVal p As Any Ptr)
End Type

Declare Function sqlite3BinaryCompare CDecl Alias "sqlite3BinaryCompare" ( _
    ByVal pUser As Any Ptr, _
    ByVal nLeft As SQLITE_C_INT, _
    ByVal pLeft As Const Any Ptr, _
    ByVal nRight As SQLITE_C_INT, _
    ByVal pRight As Const Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3IsBinary CDecl Alias "sqlite3IsBinary" ( _
    ByVal pCollation As Const sqlite3CollSeq Ptr _
) As SQLITE_C_INT

Declare Function sqlite3IntFloatCompare CDecl Alias "sqlite3IntFloatCompare" ( _
    ByVal integerValue As sqlite3_int64, _
    ByVal realValue As Double _
) As SQLITE_C_INT
Declare Function sqlite3BlobCompare CDecl Alias "sqlite3BlobCompare" ( _
    ByVal pLeft As Const Any Ptr, _
    ByVal pRight As Const Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3MemCompare CDecl Alias "sqlite3MemCompare" ( _
    ByVal pLeft As Const Any Ptr, _
    ByVal pRight As Const Any Ptr, _
    ByVal pCollation As Const Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeRecordCompareWithSkip CDecl Alias "sqlite3VdbeRecordCompareWithSkip" ( _
    ByVal nKey As SQLITE_C_INT, _
    ByVal pKey As Const Any Ptr, _
    ByVal pRecord As Any Ptr, _
    ByVal skipFirstField As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3VdbeRecordCompare CDecl Alias "sqlite3VdbeRecordCompare" ( _
    ByVal nKey As SQLITE_C_INT, _
    ByVal pKey As Const Any Ptr, _
    ByVal pRecord As Any Ptr _
) As SQLITE_C_INT
#endif

/' end of sqlite3_vdbe_compare.bi '/
