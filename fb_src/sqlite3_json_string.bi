/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_string.bi

    Purpose:

        Define the JSON subsystem's bounded string accumulator and helper API.

    Responsibilities:

        - Match the JsonString field order and embedded 100-byte starter buffer.
        - Declare lifecycle, growth, append, and JSON escape validation helpers.
        - Preserve the JSONB text-with-escapes type used by escape parsing.
        - Expose JSON string quoting and control-character escaping.

    This file intentionally does NOT contain:

        - JSON parsing, JSONB traversal, SQL function registration, or result
          generation beyond accumulator error reporting.
'/ 

#ifndef SQLITE3_FB_JSON_STRING_BI
#define SQLITE3_FB_JSON_STRING_BI

#include once "sqlite3_types.bi"

#define JSTRING_OOM &H01
#define JSTRING_MALFORMED &H02
#define JSTRING_TOODEEP &H04
#define JSTRING_ERR &H08

Type JsonString
    pCtx As Any Ptr
    zBuf As ZString Ptr
    nAlloc As sqlite3_uint64
    nUsed As sqlite3_uint64
    bStatic As u8
    eErr As u8
    zSpace(0 To 99) As UByte
End Type

Declare Sub jsonStringZero CDecl Alias "jsonStringZero" (ByVal p As JsonString Ptr)
Declare Sub jsonStringInit CDecl Alias "jsonStringInit" (ByVal p As JsonString Ptr, ByVal pContext As Any Ptr)
Declare Sub jsonStringReset CDecl Alias "jsonStringReset" (ByVal p As JsonString Ptr)
Declare Sub jsonStringOom CDecl Alias "jsonStringOom" (ByVal p As JsonString Ptr)
Declare Sub jsonStringTooDeep CDecl Alias "jsonStringTooDeep" (ByVal p As JsonString Ptr)
Declare Function jsonStringGrow CDecl Alias "jsonStringGrow" (ByVal p As JsonString Ptr, ByVal nByte As u32) As SQLITE_C_INT
Declare Sub jsonStringExpandAndAppend CDecl Alias "jsonStringExpandAndAppend" (ByVal p As JsonString Ptr, ByVal zInput As Const UByte Ptr, ByVal nByte As u32)
Declare Sub jsonAppendRaw CDecl Alias "jsonAppendRaw" (ByVal p As JsonString Ptr, ByVal zInput As Const UByte Ptr, ByVal nByte As u32)
Declare Sub jsonAppendRawNZ CDecl Alias "jsonAppendRawNZ" (ByVal p As JsonString Ptr, ByVal zInput As Const UByte Ptr, ByVal nByte As u32)
Declare Sub jsonAppendCharExpand CDecl Alias "jsonAppendCharExpand" (ByVal p As JsonString Ptr, ByVal character As Byte)
Declare Sub jsonAppendChar CDecl Alias "jsonAppendChar" (ByVal p As JsonString Ptr, ByVal character As Byte)
Declare Sub jsonStringTrimOneChar CDecl Alias "jsonStringTrimOneChar" (ByVal p As JsonString Ptr)
Declare Function jsonStringTerminate CDecl Alias "jsonStringTerminate" (ByVal p As JsonString Ptr) As SQLITE_C_INT
Declare Sub jsonAppendSeparator CDecl Alias "jsonAppendSeparator" (ByVal p As JsonString Ptr)
Declare Sub jsonAppendControlChar CDecl Alias "jsonAppendControlChar" (ByVal p As JsonString Ptr, ByVal character As u8)
Declare Sub jsonAppendString CDecl Alias "jsonAppendString" (ByVal p As JsonString Ptr, ByVal zInput As Const UByte Ptr, ByVal nByte As u32)

Declare Function jsonHexToInt CDecl Alias "jsonHexToInt" (ByVal value As SQLITE_C_INT) As u8
Declare Function jsonHexToInt4 CDecl Alias "jsonHexToInt4" (ByVal zHex As Const UByte Ptr) As u32
Declare Function jsonIs2Hex CDecl Alias "jsonIs2Hex" (ByVal zHex As Const UByte Ptr) As SQLITE_C_INT
Declare Function jsonIs4Hex CDecl Alias "jsonIs4Hex" (ByVal zHex As Const UByte Ptr) As SQLITE_C_INT
Declare Function jsonIs4HexB CDecl Alias "jsonIs4HexB" (ByVal zEscape As Const UByte Ptr, ByVal pOpcode As SQLITE_C_INT Ptr) As SQLITE_C_INT

#endif

/' end of sqlite3_json_string.bi '/
