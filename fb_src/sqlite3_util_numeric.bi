/'
    Project: SQLite FreeBASIC port

    File: sqlite3_util_numeric.bi

    Purpose:

        Declare numeric and byte conversion helpers from src/util.c.

    Responsibilities:

        - Expose overflow-safe integer and logarithmic estimate routines.
        - Expose hexadecimal decoding, VList, and integer text helpers.

    This file intentionally does NOT contain:

        - Query planning or SQL expression structures.
'/ 

#ifndef SQLITE3_FB_UTIL_NUMERIC_BI
#define SQLITE3_FB_UTIL_NUMERIC_BI

#include once "sqlite3_db_types.bi"

Declare Function sqlite3IsNaN CDecl Alias "sqlite3IsNaN" (ByVal value As Double) As SQLITE_C_INT
Declare Function sqlite3IsOverflow CDecl Alias "sqlite3IsOverflow" (ByVal value As Double) As SQLITE_C_INT
Declare Function sqlite3GetUInt32 CDecl Alias "sqlite3GetUInt32" ( _
    ByVal z As Const ZString Ptr, _
    ByVal pValue As SQLITE_C_UINT Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BSwap64 CDecl Alias "sqlite3BSwap64" (ByVal value As sqlite3_uint64) As sqlite3_uint64
Declare Function sqlite3HexToInt CDecl Alias "sqlite3HexToInt" (ByVal value As SQLITE_C_INT) As u8
Declare Function sqlite3HexToBlob CDecl Alias "sqlite3HexToBlob" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zHex As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As Any Ptr
Declare Function sqlite3AddInt64 CDecl Alias "sqlite3AddInt64" ( _
    ByVal pValue As sqlite3_int64 Ptr, _
    ByVal addend As sqlite3_int64 _
) As SQLITE_C_INT
Declare Function sqlite3SubInt64 CDecl Alias "sqlite3SubInt64" ( _
    ByVal pValue As sqlite3_int64 Ptr, _
    ByVal subtrahend As sqlite3_int64 _
) As SQLITE_C_INT
Declare Function sqlite3MulInt64 CDecl Alias "sqlite3MulInt64" ( _
    ByVal pValue As sqlite3_int64 Ptr, _
    ByVal multiplier As sqlite3_int64 _
) As SQLITE_C_INT
Declare Function sqlite3AbsInt32 CDecl Alias "sqlite3AbsInt32" (ByVal value As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3LogEst CDecl Alias "sqlite3LogEst" (ByVal value As sqlite3_uint64) As Short
Declare Function sqlite3LogEstAdd CDecl Alias "sqlite3LogEstAdd" ( _
    ByVal leftValue As Short, _
    ByVal rightValue As Short _
) As Short
Declare Function sqlite3LogEstFromDouble CDecl Alias "sqlite3LogEstFromDouble" (ByVal value As Double) As Short
Declare Function sqlite3LogEstToInt CDecl Alias "sqlite3LogEstToInt" (ByVal value As Short) As sqlite3_uint64
Declare Function sqlite3VListAdd CDecl Alias "sqlite3VListAdd" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pList As Any Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal nName As SQLITE_C_INT, _
    ByVal value As SQLITE_C_INT _
) As Any Ptr
Declare Function sqlite3VListNumToName CDecl Alias "sqlite3VListNumToName" ( _
    ByVal pList As Any Ptr, _
    ByVal value As SQLITE_C_INT _
) As Const ZString Ptr
Declare Function sqlite3VListNameToNum CDecl Alias "sqlite3VListNameToNum" ( _
    ByVal pList As Any Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal nName As SQLITE_C_INT _
) As SQLITE_C_INT

#endif

/' end of sqlite3_util_numeric.bi '/
