/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_parse_arg.bas

    Purpose:

        Convert an SQL value into an owned JSON parse object.

    Responsibilities:

        - Accept validated JSONB blobs or parse text and text-compatible blobs.
        - Reuse and promote cached parse objects for editable callers.
        - Preserve reference-counted JSON text for the per-statement cache.
        - Report malformed input and allocation failures through the SQL context.

    This file intentionally does NOT contain:

        - JSON SQL function registration, path lookup, or JSONB-to-text rendering.
'/ 

#lang "fb"
#include once "sqlite3_json_parse.bi"
#include once "sqlite3_json_string.bi"
#include once "sqlite3_vdbe_api.bi"
#include once "sqlite3_constants.bi"

Declare Function sqlite3_context_db_handle CDecl Alias "sqlite3_context_db_handle" (ByVal pContext As Any Ptr) As Any Ptr
Declare Function sqlite3RCStrNew CDecl Alias "sqlite3RCStrNew" (ByVal nByte As sqlite3_uint64) As ZString Ptr
Declare Function sqlite3RCStrRef CDecl Alias "sqlite3RCStrRef" (ByVal zData As ZString Ptr) As ZString Ptr
Declare Sub sqlite3RCStrUnref CDecl Alias "sqlite3RCStrUnref" (ByVal zData As Any Ptr)
Declare Sub sqlite3_result_error CDecl Alias "sqlite3_result_error" (ByVal pContext As Any Ptr, ByVal zError As Const ZString Ptr, ByVal nByte As SQLITE_C_INT)
Declare Sub sqlite3_result_error_nomem CDecl Alias "sqlite3_result_error_nomem" (ByVal pContext As Any Ptr)
Declare Sub sqlite3_result_error_toobig CDecl Alias "sqlite3_result_error_toobig" (ByVal pContext As Any Ptr)

Extern "C"
    Declare Function jsonParseArgMemcpy CDecl Alias "memcpy" ( _
        ByVal pDestination As Any Ptr, _
        ByVal pSource As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
End Extern

Function jsonArgIsJsonb CDecl Alias "jsonArgIsJsonb" ( _
    ByVal pValue As Any Ptr, _
    ByVal pParse As JsonParse Ptr _
) As SQLITE_C_INT Export
    If pValue = 0 OrElse pParse = 0 Then Return 0
    If sqlite3_value_type(pValue) <> SQLITE_BLOB Then Return 0

    Dim blobBytes As SQLITE_C_INT = sqlite3_value_bytes(pValue)
    If blobBytes <= 0 Then Return 0
    Dim pBlob As UByte Ptr = CPtr(UByte Ptr, sqlite3_value_blob(pValue))
    If pBlob = 0 Then Return 0
    pParse->aBlob = pBlob
    pParse->nBlob = CUInt(blobBytes)

    Dim firstByte As UByte = pBlob[0]
    Dim nodeType As UByte = firstByte And &HF
    Dim payloadSize As u32 = 0
    Dim headerSize As u32 = 0
    If nodeType <= JSONB_OBJECT Then _
        headerSize = jsonbPayloadSize(pParse, 0, @payloadSize)

    If headerSize <> 0 AndAlso _
       CULngInt(headerSize) + CULngInt(payloadSize) = CULngInt(pParse->nBlob) AndAlso _
       (nodeType > JSONB_FALSE OrElse payloadSize = 0) Then
        Dim possibleTextPrefix As SQLITE_C_INT = _
            CInt(firstByte = Asc("{") OrElse firstByte = Asc("[") OrElse _
                (firstByte >= Asc("0") AndAlso firstByte <= Asc("9")))
        If payloadSize > 7 OrElse possibleTextPrefix = 0 OrElse _
           jsonbValidityCheck(pParse, 0, pParse->nBlob, 1) = 0 Then Return 1
    End If

    pParse->aBlob = 0
    pParse->nBlob = 0
    Return 0
End Function

Function jsonParseFuncArg CDecl Alias "jsonParseFuncArg" ( _
    ByVal pContext As Any Ptr, _
    ByVal pValue As Any Ptr, _
    ByVal flags As u32 _
) As JsonParse Ptr Export
    If pContext = 0 OrElse pValue = 0 Then Return 0
    Dim valueType As SQLITE_C_INT = sqlite3_value_type(pValue)
    If valueType = SQLITE_NULL Then Return 0

    Dim pFromCache As JsonParse Ptr = jsonCacheSearch(pContext, pValue)
    If pFromCache <> 0 Then
        If pFromCache->nJPRef = &HFFFFFFFFUL Then
            sqlite3_result_error_toobig(pContext)
            Return 0
        End If
        pFromCache->nJPRef += 1
        If (flags And JSON_EDITABLE) = 0 Then Return pFromCache
    End If

    Dim db As sqlite3 Ptr = _
        CPtr(sqlite3 Ptr, sqlite3_context_db_handle(pContext))
    If db = 0 Then
        jsonParseFree(pFromCache)
        Return 0
    End If
    Dim pParse As JsonParse Ptr = 0
    Dim nBlobCopy As u32 = 0
    Dim zText As Const UByte Ptr = 0
    Dim zOwnedText As ZString Ptr = 0
    Dim parseErrorContext As Any Ptr = 0
    Dim cacheCode As SQLITE_C_INT = SQLITE_OK

rebuild_from_cache:
    pParse = CPtr(JsonParse Ptr, sqlite3DbMallocZero(db, SizeOf(JsonParse)))
    If pParse = 0 Then GoTo json_parse_arg_oom
    pParse->db = db
    pParse->nJPRef = 1

    If pFromCache <> 0 Then
        nBlobCopy = pFromCache->nBlob
        If nBlobCopy = 0 OrElse pFromCache->aBlob = 0 Then GoTo json_parse_arg_corrupt
        pParse->aBlob = CPtr(UByte Ptr, sqlite3DbMallocRaw(db, nBlobCopy))
        If pParse->aBlob = 0 Then GoTo json_parse_arg_oom
        jsonParseArgMemcpy(pParse->aBlob, pFromCache->aBlob, nBlobCopy)
        pParse->nBlobAlloc = nBlobCopy
        pParse->nBlob = nBlobCopy
        pParse->hasNonstd = pFromCache->hasNonstd
        jsonParseFree(pFromCache)
        pFromCache = 0
        Return pParse
    End If

    If valueType = SQLITE_BLOB AndAlso jsonArgIsJsonb(pValue, pParse) <> 0 Then
        If (flags And JSON_EDITABLE) <> 0 AndAlso _
           jsonBlobMakeEditable(pParse, 0) = 0 Then GoTo json_parse_arg_oom
        Return pParse
    End If

    zText = CPtr(Const UByte Ptr, sqlite3_value_text(pValue))
    pParse->zJson = CPtr(ZString Ptr, zText)
    pParse->nJson = sqlite3_value_bytes(pValue)
    If db->mallocFailed <> 0 OrElse pParse->nJson < 0 Then GoTo json_parse_arg_oom
    If pParse->nJson = 0 Then GoTo json_parse_arg_malformed
    If zText = 0 Then GoTo json_parse_arg_oom

    parseErrorContext = pContext
    If (flags And JSON_KEEPERROR) <> 0 Then parseErrorContext = 0
    If jsonConvertTextToBlob(pParse, parseErrorContext) <> SQLITE_OK Then
        If (flags And JSON_KEEPERROR) <> 0 Then
            pParse->nErr = 1
            Return pParse
        End If
        jsonParseFree(pParse)
        Return 0
    End If

    If sqlite3ValueIsOfClass(pValue, CPtr(Any Ptr, @sqlite3RCStrUnref)) = 0 Then
        zOwnedText = sqlite3RCStrNew(CULngInt(pParse->nJson))
        If zOwnedText = 0 Then GoTo json_parse_arg_oom
        If pParse->nJson > 0 Then _
            jsonParseArgMemcpy(zOwnedText, pParse->zJson, CULngInt(pParse->nJson))
        CPtr(UByte Ptr, zOwnedText)[pParse->nJson] = 0
        pParse->zJson = zOwnedText
    Else
        sqlite3RCStrRef(pParse->zJson)
    End If
    pParse->bJsonIsRCStr = 1

    cacheCode = jsonCacheInsert(pContext, pParse)
    If cacheCode = SQLITE_NOMEM Then GoTo json_parse_arg_oom
    If cacheCode <> SQLITE_OK Then
        jsonParseFree(pParse)
        pParse = 0
        Return 0
    End If
    If (flags And JSON_EDITABLE) <> 0 Then
        pFromCache = pParse
        pParse = 0
        GoTo rebuild_from_cache
    End If
    Return pParse

json_parse_arg_malformed:
    If (flags And JSON_KEEPERROR) <> 0 Then
        pParse->nErr = 1
        Return pParse
    End If
    jsonParseFree(pParse)
    sqlite3_result_error(pContext, StrPtr("malformed JSON"), -1)
    Return 0

json_parse_arg_corrupt:
    jsonParseFree(pParse)
    pParse = 0
    jsonParseFree(pFromCache)
    Return 0

json_parse_arg_oom:
    jsonParseFree(pFromCache)
    jsonParseFree(pParse)
    sqlite3_result_error_nomem(pContext)
    Return 0
End Function

/' end of sqlite3_json_parse_arg.bas '/
