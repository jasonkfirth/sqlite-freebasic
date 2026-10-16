/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_return.bas

    Purpose:

        Return generated JSON text or JSONB from a SQL function context.

    Responsibilities:

        - Convert generated JSON text to a JSONB result when requested.
        - Convert JSONB text fragments and transfer JSON text to result ownership.
        - Cache source text when a parsed JSONB value can be reused.
        - Report accumulated string errors through SQLite result APIs.

    This file intentionally does NOT contain:

        - JSONB-to-text traversal internals, other SQL callbacks, or registration.
'/ 

#lang "fb"
#include once "sqlite3_json_parse.bi"
#include once "sqlite3_json_string.bi"
#include once "sqlite3_constants.bi"

Extern "C"
    Declare Function jsonReturnMemset CDecl Alias "memset" ( _
        ByVal pDestination As Any Ptr, _
        ByVal fillValue As SQLITE_C_INT, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
End Extern

Declare Function sqlite3_context_db_handle CDecl Alias "sqlite3_context_db_handle" (ByVal pContext As Any Ptr) As Any Ptr
Declare Function sqlite3_user_data CDecl Alias "sqlite3_user_data" (ByVal pContext As Any Ptr) As Any Ptr
Declare Function sqlite3RCStrRef CDecl Alias "sqlite3RCStrRef" (ByVal zData As ZString Ptr) As ZString Ptr
Declare Sub sqlite3RCStrUnref CDecl Alias "sqlite3RCStrUnref" (ByVal zData As Any Ptr)
Declare Sub sqlite3_result_blob CDecl Alias "sqlite3_result_blob" (ByVal pContext As Any Ptr, ByVal pBlob As Any Ptr, ByVal nByte As SQLITE_C_INT, ByVal pDestructor As Any Ptr)
Declare Sub sqlite3_result_text64 CDecl Alias "sqlite3_result_text64" (ByVal pContext As Any Ptr, ByVal zText As Const ZString Ptr, ByVal nByte As sqlite3_uint64, ByVal pDestructor As Any Ptr, ByVal encoding As u8)
Declare Sub sqlite3_result_error CDecl Alias "sqlite3_result_error" (ByVal pContext As Any Ptr, ByVal zError As Const ZString Ptr, ByVal nByte As SQLITE_C_INT)
Declare Sub sqlite3_result_error_nomem CDecl Alias "sqlite3_result_error_nomem" (ByVal pContext As Any Ptr)
Declare Sub sqlite3_result_error_toobig CDecl Alias "sqlite3_result_error_toobig" (ByVal pContext As Any Ptr)
Declare Sub sqlite3_result_subtype CDecl Alias "sqlite3_result_subtype" (ByVal pContext As Any Ptr, ByVal subtype As SQLITE_C_UINT)
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)

Sub jsonReturnTextJsonFromBlob CDecl Alias "jsonReturnTextJsonFromBlob" ( _
    ByVal pContext As Any Ptr, _
    ByVal aBlob As Const UByte Ptr, _
    ByVal nBlob As u32 _
)
    If pContext = 0 OrElse aBlob = 0 Then Exit Sub

    Dim parse As JsonParse
    Dim textBuffer As JsonString
    jsonReturnMemset(@parse, 0, SizeOf(parse))
    parse.aBlob = CPtr(UByte Ptr, aBlob)
    parse.nBlob = nBlob
    jsonStringInit(@textBuffer, pContext)
    jsonTranslateBlobToText(@parse, 0, @textBuffer)
    jsonReturnString(@textBuffer, 0, 0)
End Sub

Sub jsonReturnStringAsBlob CDecl Alias "jsonReturnStringAsBlob" ( _
    ByVal pString As JsonString Ptr _
) Export
    If pString = 0 OrElse pString->pCtx = 0 Then Exit Sub
    If pString->eErr <> 0 Then Exit Sub
    If pString->nUsed > SQLITE_MAX_ALLOCATION_SIZE OrElse _
       pString->nUsed > &H7FFFFFFF Then
        sqlite3_result_error_toobig(pString->pCtx)
        Exit Sub
    End If

    Dim parsed As JsonParse
    jsonReturnMemset(@parsed, 0, SizeOf(parsed))
    parsed.zJson = pString->zBuf
    parsed.nJson = CInt(pString->nUsed)
    parsed.db = CPtr(sqlite3 Ptr, sqlite3_context_db_handle(pString->pCtx))
    If parsed.db = 0 Then
        sqlite3_result_error(pString->pCtx, StrPtr("JSON context is not open"), -1)
        Exit Sub
    End If

    If jsonConvertTextToBlob(@parsed, 0) <> SQLITE_OK Then
        If parsed.oom <> 0 Then
            sqlite3_result_error_nomem(pString->pCtx)
        Else
            sqlite3_result_error(pString->pCtx, StrPtr("malformed JSON"), -1)
        End If
        jsonParseReset(@parsed)
        Exit Sub
    End If
    If parsed.aBlob = 0 OrElse parsed.nBlobAlloc = 0 Then
        jsonParseReset(@parsed)
        sqlite3_result_error(pString->pCtx, StrPtr("malformed JSON"), -1)
        Exit Sub
    End If

    ' TRANSIENT asks sqlite3_result_blob() to copy before this routine frees
    ' the database-allocated buffer.
    sqlite3_result_blob(pString->pCtx, parsed.aBlob, CInt(parsed.nBlob), _
                        CPtr(Any Ptr, -1))
    sqlite3DbFree(parsed.db, parsed.aBlob)
    parsed.aBlob = 0
    parsed.nBlobAlloc = 0
    parsed.nBlob = 0
End Sub

Sub jsonReturnString CDecl Alias "jsonReturnString" ( _
    ByVal pString As JsonString Ptr, _
    ByVal pParse As JsonParse Ptr, _
    ByVal pContext As Any Ptr _
) Export
    If pString = 0 OrElse pString->pCtx = 0 Then Exit Sub
    If (pParse <> 0) <> (pContext <> 0) OrElse _
       (pContext <> 0 AndAlso pContext <> pString->pCtx) Then
        sqlite3_result_error(pString->pCtx, StrPtr("invalid JSON result context"), -1)
        jsonStringReset(pString)
        Exit Sub
    End If

    jsonStringTerminate(pString)
    If pString->eErr = 0 Then
        Dim userData As Any Ptr = sqlite3_user_data(pString->pCtx)
        Dim functionFlags As sqlite3_uint64 = CULngInt(userData) And &HFFFFFFFFULL
        If (functionFlags And JSON_BLOB) <> 0 Then
            jsonReturnStringAsBlob(pString)
        ElseIf pString->bStatic <> 0 Then
            sqlite3_result_text64(pString->pCtx, pString->zBuf, pString->nUsed, _
                                  CPtr(Any Ptr, -1), SQLITE_UTF8)
        Else
            If pParse <> 0 AndAlso pParse->bJsonIsRCStr = 0 AndAlso _
               pParse->nBlobAlloc > 0 Then
                pParse->zJson = sqlite3RCStrRef(pString->zBuf)
                pParse->nJson = CInt(pString->nUsed)
                pParse->bJsonIsRCStr = 1
                Dim cacheCode As SQLITE_C_INT = jsonCacheInsert(pContext, pParse)
                If cacheCode = SQLITE_NOMEM Then
                    sqlite3_result_error_nomem(pContext)
                    jsonStringReset(pString)
                    Exit Sub
                ElseIf cacheCode <> SQLITE_OK Then
                    sqlite3_result_error(pContext, StrPtr("JSON cache insertion failed"), -1)
                    jsonStringReset(pString)
                    Exit Sub
                End If
            End If
            sqlite3_result_text64(pString->pCtx, sqlite3RCStrRef(pString->zBuf), _
                                  pString->nUsed, CPtr(Any Ptr, @sqlite3RCStrUnref), _
                                  SQLITE_UTF8)
        End If
    ElseIf (pString->eErr And JSTRING_OOM) <> 0 Then
        sqlite3_result_error_nomem(pString->pCtx)
    ElseIf (pString->eErr And JSTRING_TOODEEP) <> 0 Then
        ' jsonStringTooDeep() has already sent the error to the context.
    ElseIf (pString->eErr And JSTRING_MALFORMED) <> 0 Then
        sqlite3_result_error(pString->pCtx, StrPtr("malformed JSON"), -1)
    End If
    jsonStringReset(pString)
End Sub

Sub jsonReturnParse CDecl Alias "jsonReturnParse" ( _
    ByVal pContext As Any Ptr, _
    ByVal pParse As JsonParse Ptr _
) Export
    If pContext = 0 OrElse pParse = 0 Then Exit Sub
    If pParse->oom <> 0 Then
        sqlite3_result_error_nomem(pContext)
        Exit Sub
    End If

    Dim userData As Any Ptr = sqlite3_user_data(pContext)
    Dim functionFlags As sqlite3_uint64 = CULngInt(userData) And &HFFFFFFFFULL
    If (functionFlags And JSON_BLOB) <> 0 Then
        If pParse->nBlob > &H7FFFFFFF Then
            sqlite3_result_error_toobig(pContext)
        ElseIf pParse->nBlobAlloc > 0 AndAlso pParse->bReadOnly = 0 Then
            sqlite3_result_blob(pContext, pParse->aBlob, CInt(pParse->nBlob), _
                                CPtr(Any Ptr, -1))
            sqlite3DbFree(pParse->db, pParse->aBlob)
            pParse->aBlob = 0
            pParse->nBlobAlloc = 0
        Else
            sqlite3_result_blob(pContext, pParse->aBlob, CInt(pParse->nBlob), _
                                CPtr(Any Ptr, -1))
        End If
    Else
        Dim outputString As JsonString
        jsonStringInit(@outputString, pContext)
        pParse->delta = 0
        jsonTranslateBlobToText(pParse, 0, @outputString)
        jsonReturnString(@outputString, pParse, pContext)
        sqlite3_result_subtype(pContext, JSON_SUBTYPE)
    End If
End Sub

/' end of sqlite3_json_return.bas '/
