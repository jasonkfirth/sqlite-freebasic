/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_parse.bi

    Purpose:

        Define JSON parse-state and per-opcode JSON cache layouts.

    Responsibilities:

        - Match JsonParse ownership, reference-count, and edit fields.
        - Match the four-entry JSON translation cache stored as VDBE auxdata.
        - Declare parse-state and cache lifetime operations.

    This file intentionally does NOT contain:

        - JSON text parsing, JSONB validation, or path evaluation.
'/ 

#ifndef SQLITE3_FB_JSON_PARSE_BI
#define SQLITE3_FB_JSON_PARSE_BI

#include once "sqlite3_db_types.bi"
#include once "sqlite3_json_string.bi"
#include once "sqlite3_result.bi"
#include once "sqlite3_vdbe_mem_types.bi"

#define JSON_CACHE_ID -429938
#define JSON_CACHE_SIZE 4
#ifndef SQLITE_JSON_MAX_DEPTH
#define JSON_MAX_DEPTH 1000
#else
#define JSON_MAX_DEPTH SQLITE_JSON_MAX_DEPTH
#endif
#define JSON_EDITABLE &H01
#define JSON_KEEPERROR &H02
#define JSON_BLOB &H10
#define JSON_SUBTYPE 74
#define JSON_INVALID_CHAR &H99999

' JSON callbacks receive these mode bits through sqlite3_user_data().
#define JSON_JSON &H01
#define JSON_SQL &H02
#define JSON_ISSET &H04
#define JSON_AINS &H08
#define JSON_INSERT_TYPE(value) (((value) And &H0C) Shr 2)

#define JEDIT_DEL 1
#define JEDIT_REPL 2
#define JEDIT_INS 3
#define JEDIT_SET 4
#define JEDIT_AINS 5

#define JSON_LOOKUP_ERROR &HFFFFFFFFUL
#define JSON_LOOKUP_NOTFOUND &HFFFFFFFEUL
#define JSON_LOOKUP_NOTARRAY &HFFFFFFFDUL
#define JSON_LOOKUP_TOODEEP &HFFFFFFFCUL
#define JSON_LOOKUP_PATHERROR &HFFFFFFFBUL
#define JSON_LOOKUP_ISERROR(code) ((code) >= JSON_LOOKUP_PATHERROR)

#define JSONB_NULL 0
#define JSONB_TRUE 1
#define JSONB_FALSE 2
#define JSONB_INT 3
#define JSONB_INT5 4
#define JSONB_FLOAT 5
#define JSONB_FLOAT5 6
#define JSONB_TEXT 7
#define JSONB_TEXTJ 8
#define JSONB_TEXT5 9
#define JSONB_TEXTRAW 10
#define JSONB_ARRAY 11
#define JSONB_OBJECT 12

Type JsonParse
    aBlob As UByte Ptr
    nBlob As u32
    nBlobAlloc As u32
    zJson As ZString Ptr
    db As sqlite3 Ptr
    nJson As SQLITE_C_INT
    nJPRef As u32
    iErr As u32
    iDepth As u16
    nErr As u8
    oom As u8
    bJsonIsRCStr As u8
    hasNonstd As u8
    bReadOnly As u8
    eEdit As u8
    delta As SQLITE_C_INT
    nIns As u32
    iLabel As u32
    aIns As UByte Ptr
End Type

Type JsonCache
    db As sqlite3 Ptr
    nUsed As SQLITE_C_INT
    a(0 To JSON_CACHE_SIZE - 1) As JsonParse Ptr
End Type

Declare Sub jsonParseReset CDecl Alias "jsonParseReset" (ByVal pParse As JsonParse Ptr)
Declare Sub jsonParseFree CDecl Alias "jsonParseFree" (ByVal pParse As JsonParse Ptr)
Declare Sub jsonCacheDelete CDecl Alias "jsonCacheDelete" (ByVal pCache As JsonCache Ptr)
Declare Sub jsonCacheDeleteGeneric CDecl Alias "jsonCacheDeleteGeneric" (ByVal pCache As Any Ptr)
Declare Function jsonCacheInsert CDecl Alias "jsonCacheInsert" (ByVal pContext As Any Ptr, ByVal pParse As JsonParse Ptr) As SQLITE_C_INT
Declare Function jsonCacheSearch CDecl Alias "jsonCacheSearch" (ByVal pContext As Any Ptr, ByVal pValue As Any Ptr) As JsonParse Ptr
Declare Function json5Whitespace CDecl Alias "json5Whitespace" (ByVal zInput As Const UByte Ptr) As SQLITE_C_INT
Declare Function jsonBytesToBypass CDecl Alias "jsonBytesToBypass" (ByVal zInput As Const UByte Ptr, ByVal nByte As u32) As u32
Declare Function jsonUnescapeOneChar CDecl Alias "jsonUnescapeOneChar" (ByVal zInput As Const UByte Ptr, ByVal nByte As u32, ByVal pCodepoint As u32 Ptr) As u32
Declare Function jsonLabelCompareEscaped CDecl Alias "jsonLabelCompareEscaped" (ByVal zLeft As Const UByte Ptr, ByVal nLeft As u32, ByVal rawLeft As SQLITE_C_INT, ByVal zRight As Const UByte Ptr, ByVal nRight As u32, ByVal rawRight As SQLITE_C_INT) As SQLITE_C_INT
Declare Function jsonLabelCompare CDecl Alias "jsonLabelCompare" (ByVal zLeft As Const UByte Ptr, ByVal nLeft As u32, ByVal rawLeft As SQLITE_C_INT, ByVal zRight As Const UByte Ptr, ByVal nRight As u32, ByVal rawRight As SQLITE_C_INT) As SQLITE_C_INT
Declare Function jsonBlobExpand CDecl Alias "jsonBlobExpand" (ByVal pParse As JsonParse Ptr, ByVal nByte As sqlite3_uint64) As SQLITE_C_INT
Declare Function jsonBlobMakeEditable CDecl Alias "jsonBlobMakeEditable" (ByVal pParse As JsonParse Ptr, ByVal nExtra As u32) As SQLITE_C_INT
Declare Sub jsonBlobExpandAndAppendOneByte CDecl Alias "jsonBlobExpandAndAppendOneByte" (ByVal pParse As JsonParse Ptr, ByVal value As u8)
Declare Sub jsonBlobAppendOneByte CDecl Alias "jsonBlobAppendOneByte" (ByVal pParse As JsonParse Ptr, ByVal value As u8)
Declare Sub jsonBlobExpandAndAppendNode CDecl Alias "jsonBlobExpandAndAppendNode" (ByVal pParse As JsonParse Ptr, ByVal nodeType As u8, ByVal payloadSize As sqlite3_uint64, ByVal pPayload As Const Any Ptr)
Declare Sub jsonBlobAppendNode CDecl Alias "jsonBlobAppendNode" (ByVal pParse As JsonParse Ptr, ByVal nodeType As u8, ByVal payloadSize As sqlite3_uint64, ByVal pPayload As Const Any Ptr)
Declare Function jsonBlobChangePayloadSize CDecl Alias "jsonBlobChangePayloadSize" (ByVal pParse As JsonParse Ptr, ByVal index As u32, ByVal payloadSize As u32) As SQLITE_C_INT
Declare Function jsonbPayloadSizeWide CDecl Alias "jsonbPayloadSizeWide" (ByVal pParse As Const JsonParse Ptr, ByVal index As u32, ByVal pPayloadSize As u32 Ptr, ByVal headerType As u8) As u32
Declare Function jsonbPayloadSize CDecl Alias "jsonbPayloadSize" (ByVal pParse As Const JsonParse Ptr, ByVal index As u32, ByVal pPayloadSize As u32 Ptr) As u32
Declare Function jsonbPayloadSizeInline CDecl Alias "jsonbPayloadSizeInline" (ByVal pParse As Const JsonParse Ptr, ByVal index As u32, ByVal pPayloadSize As u32 Ptr) As u32
Declare Function jsonbPayloadSizeSemiInline CDecl Alias "jsonbPayloadSizeSemiInline" (ByVal pParse As Const JsonParse Ptr, ByVal index As u32, ByVal pPayloadSize As u32 Ptr) As u32
Declare Function jsonbValidityCheck CDecl Alias "jsonbValidityCheck" (ByVal pParse As Const JsonParse Ptr, ByVal index As u32, ByVal endOffset As u32, ByVal depth As u32) As u32
Declare Function jsonTranslateTextToBlob CDecl Alias "jsonTranslateTextToBlob" (ByVal pParse As JsonParse Ptr, ByVal index As u32) As SQLITE_C_INT
Declare Function jsonConvertTextToBlob CDecl Alias "jsonConvertTextToBlob" (ByVal pParse As JsonParse Ptr, ByVal pContext As Any Ptr) As SQLITE_C_INT
Declare Function jsonArgIsJsonb CDecl Alias "jsonArgIsJsonb" (ByVal pValue As Any Ptr, ByVal pParse As JsonParse Ptr) As SQLITE_C_INT
Declare Function jsonParseFuncArg CDecl Alias "jsonParseFuncArg" (ByVal pContext As Any Ptr, ByVal pValue As Any Ptr, ByVal flags As u32) As JsonParse Ptr
Declare Sub jsonReturnStringAsBlob CDecl Alias "jsonReturnStringAsBlob" (ByVal pString As JsonString Ptr)
Declare Sub jsonReturnString CDecl Alias "jsonReturnString" (ByVal pString As JsonString Ptr, ByVal pParse As JsonParse Ptr, ByVal pContext As Any Ptr)
Declare Sub jsonReturnTextJsonFromBlob CDecl Alias "jsonReturnTextJsonFromBlob" ( _
    ByVal pContext As Any Ptr, _
    ByVal aBlob As Const UByte Ptr, _
    ByVal nBlob As u32 _
)
Declare Function jsonFunctionArgToBlob CDecl Alias "jsonFunctionArgToBlob" ( _
    ByVal pContext As SqliteResultContext Ptr, _
    ByVal pArgument As SqliteVdbeMem Ptr, _
    ByVal pParse As JsonParse Ptr _
) As SQLITE_C_INT
Declare Sub jsonReturnParse CDecl Alias "jsonReturnParse" (ByVal pContext As Any Ptr, ByVal pParse As JsonParse Ptr)
Declare Function jsonTranslateBlobToText CDecl Alias "jsonTranslateBlobToText" (ByVal pParse As JsonParse Ptr, ByVal index As u32, ByVal pOutput As JsonString Ptr) As u32
Declare Function jsonbArrayCount CDecl Alias "jsonbArrayCount" (ByVal pParse As Const JsonParse Ptr, ByVal rootIndex As u32) As u32
Declare Function jsonLookupStep CDecl Alias "jsonLookupStep" (ByVal pParse As JsonParse Ptr, ByVal rootIndex As u32, ByVal zPath As Const UByte Ptr, ByVal labelIndex As u32) As u32

#endif

/' end of sqlite3_json_parse.bi '/
