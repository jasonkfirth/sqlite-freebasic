/'
    Project: SQLite FreeBASIC port

    File: sqlite3_straccum.bi

    Purpose:

        Define the string accumulator layout and APIs from src/printf.c.

    Responsibilities:

        - Preserve the sqlite3_str field order and C-compatible widths.
        - Declare allocation, append, finish, and inspection operations.

    This file intentionally does NOT contain:

        - Format-string parsing or variadic argument handling.
'/

#ifndef SQLITE3_FB_STRACCUM_BI
#define SQLITE3_FB_STRACCUM_BI

#include once "sqlite3_db_types.bi"
#include once "sqlite3_vdbe_mem_types.bi"

#define SQLITE_PRINTF_INTERNAL 1
#define SQLITE_PRINTF_SQLFUNC 2
#define SQLITE_PRINTF_MALLOCED 4

Type sqlite3_str
    db As sqlite3 Ptr
    zText As UByte Ptr
    nAlloc As u32
    mxAlloc As u32
    nChar As u32
    accError As u8
    printfFlags As u8
    ' Optional caller workspace for printf fields that must not allocate.
    pPrintfScratch As UByte Ptr
    nPrintfScratch As u32
End Type

' SQL printf() supplies values through this array instead of a C vararg list.
Type SqlitePrintfArguments
    nArg As SQLITE_C_INT
    nUsed As SQLITE_C_INT
    apArg As SqliteVdbeMem Ptr Ptr
End Type

Declare Sub sqlite3StrAccumInit CDecl Alias "sqlite3StrAccumInit" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal db As sqlite3 Ptr, _
    ByVal zBase As UByte Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal maxByte As SQLITE_C_INT _
)
Declare Function sqlite3StrAccumEnlarge CDecl Alias "sqlite3StrAccumEnlarge" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal nByte As sqlite3_int64 _
) As SQLITE_C_INT
Declare Function sqlite3StrAccumEnlargeIfNeeded CDecl Alias "sqlite3StrAccumEnlargeIfNeeded" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal nByte As sqlite3_int64 _
) As SQLITE_C_INT
Declare Function sqlite3StrAccumFinish CDecl Alias "sqlite3StrAccumFinish" ( _
    ByVal pAccum As sqlite3_str Ptr _
) As ZString Ptr
Declare Sub sqlite3StrAccumSetError CDecl Alias "sqlite3StrAccumSetError" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal errorCode As u8 _
)

Declare Function sqlite3_str_new CDecl Alias "sqlite3_str_new" ( _
    ByVal db As sqlite3 Ptr _
) As sqlite3_str Ptr
Declare Function sqlite3_str_finish CDecl Alias "sqlite3_str_finish" ( _
    ByVal pAccum As sqlite3_str Ptr _
) As ZString Ptr
Declare Sub sqlite3_str_free CDecl Alias "sqlite3_str_free" ( _
    ByVal pAccum As sqlite3_str Ptr _
)
Declare Sub sqlite3_str_append CDecl Alias "sqlite3_str_append" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zText As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT _
)
Declare Sub sqlite3_str_appendall CDecl Alias "sqlite3_str_appendall" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zText As Const ZString Ptr _
)
Declare Sub sqlite3_str_appendchar CDecl Alias "sqlite3_str_appendchar" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal count As SQLITE_C_INT, _
    ByVal character As Byte _
)
Declare Sub sqlite3_str_reset CDecl Alias "sqlite3_str_reset" ( _
    ByVal pAccum As sqlite3_str Ptr _
)
Declare Sub sqlite3_str_truncate CDecl Alias "sqlite3_str_truncate" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal nByte As SQLITE_C_INT _
)
Declare Function sqlite3_str_errcode CDecl Alias "sqlite3_str_errcode" ( _
    ByVal pAccum As sqlite3_str Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_str_length CDecl Alias "sqlite3_str_length" ( _
    ByVal pAccum As sqlite3_str Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_str_value CDecl Alias "sqlite3_str_value" ( _
    ByVal pAccum As sqlite3_str Ptr _
) As ZString Ptr

#endif

/' end of sqlite3_straccum.bi '/
