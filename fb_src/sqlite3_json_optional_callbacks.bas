/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_optional_callbacks.bas

    Purpose:

        Implement the JSON pretty-print, error-position, and aggregate callbacks.

    Responsibilities:

        - Render JSONB with caller-selected indentation.
        - Report the approximate character offset of malformed JSON text.
        - Accumulate JSON array and object aggregate rows.

    This file intentionally does NOT contain:

        - JSON function registration, path editing, or JSONB parsing primitives.
'/

#lang "fb"
#include once "sqlite3_json_parse.bi"
#include once "sqlite3_json_string.bi"
#include once "sqlite3_json_values.bi"
#include once "sqlite3_numeric.bi"
#include once "sqlite3_vdbe_api.bi"
#include once "sqlite3_constants.bi"

Declare Function jsonOptionalContextDbHandle CDecl Alias "sqlite3_context_db_handle" ( _
    ByVal pContext As Any Ptr _
) As Any Ptr
Declare Function jsonOptionalMemset CDecl Alias "memset" ( _
    ByVal pDestination As Any Ptr, _
    ByVal fillValue As SQLITE_C_INT, _
    ByVal nByte As SQLITE_SIZE_T _
) As Any Ptr
Declare Sub jsonOptionalResultErrorNoMem CDecl Alias "sqlite3_result_error_nomem" ( _
    ByVal pContext As Any Ptr _
)
Declare Sub jsonOptionalResultInt64 CDecl Alias "sqlite3_result_int64" ( _
    ByVal pContext As Any Ptr, _
    ByVal value As sqlite3_int64 _
)
Declare Function jsonOptionalStrlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal zText As Const ZString Ptr _
) As SQLITE_C_INT

Type SqliteJsonPrettyContext
    pParse As JsonParse Ptr
    pOutput As JsonString Ptr
    zIndent As Const ZString Ptr
    szIndent As u32
    nIndent As u32
End Type

Private Sub jsonPrettyIndent(ByVal pPretty As SqliteJsonPrettyContext Ptr)
    If pPretty = 0 OrElse pPretty->pOutput = 0 Then Return
    If pPretty->nIndent = 0 OrElse pPretty->szIndent = 0 Then Return
    For level As u32 = 0 To pPretty->nIndent - 1
        jsonAppendRaw(pPretty->pOutput, CPtr(Const UByte Ptr, pPretty->zIndent), _
                      pPretty->szIndent)
    Next
End Sub

Private Function jsonTranslateBlobToPrettyText( _
    ByVal pPretty As SqliteJsonPrettyContext Ptr, _
    ByVal startIndex As u32 _
) As u32
    If pPretty = 0 OrElse pPretty->pParse = 0 OrElse pPretty->pOutput = 0 OrElse _
       pPretty->pParse->aBlob = 0 Then
        If pPretty <> 0 AndAlso pPretty->pOutput <> 0 Then _
            pPretty->pOutput->eErr = pPretty->pOutput->eErr Or JSTRING_MALFORMED
        Return 1
    End If

    Dim payloadSize As u32 = 0
    Dim headerSize As u32 = jsonbPayloadSize( _
        pPretty->pParse, startIndex, @payloadSize)
    If headerSize = 0 OrElse CULngInt(startIndex) + CULngInt(headerSize) + _
       CULngInt(payloadSize) > CULngInt(pPretty->pParse->nBlob) Then
        pPretty->pOutput->eErr = pPretty->pOutput->eErr Or JSTRING_MALFORMED
        Return pPretty->pParse->nBlob + 1
    End If

    Dim nodeType As UByte = pPretty->pParse->aBlob[startIndex] And &HF
    Dim contentIndex As u32 = startIndex + headerSize
    Dim endIndex As u32 = contentIndex + payloadSize
    Select Case nodeType
    Case JSONB_ARRAY
        jsonAppendChar(pPretty->pOutput, Asc("["))
        If contentIndex < endIndex Then
            jsonAppendChar(pPretty->pOutput, Asc(Chr(10)))
            pPretty->nIndent += 1
            If pPretty->nIndent >= JSON_MAX_DEPTH Then _
                jsonStringTooDeep(pPretty->pOutput)
            While pPretty->pOutput->eErr = 0
                jsonPrettyIndent(pPretty)
                contentIndex = jsonTranslateBlobToPrettyText(pPretty, contentIndex)
                If contentIndex >= endIndex Then
                    If contentIndex > endIndex Then _
                        pPretty->pOutput->eErr = _
                            pPretty->pOutput->eErr Or JSTRING_MALFORMED
                    Exit While
                End If
                jsonAppendRawNZ(pPretty->pOutput, _
                    CPtr(Const UByte Ptr, StrPtr(!",\n")), 2)
            Wend
            jsonAppendChar(pPretty->pOutput, Asc(Chr(10)))
            If pPretty->nIndent > 0 Then pPretty->nIndent -= 1
            jsonPrettyIndent(pPretty)
        End If
        jsonAppendChar(pPretty->pOutput, Asc("]"))
        Return endIndex

    Case JSONB_OBJECT
        jsonAppendChar(pPretty->pOutput, Asc("{"))
        If contentIndex < endIndex Then
            jsonAppendChar(pPretty->pOutput, Asc(Chr(10)))
            pPretty->nIndent += 1
            If pPretty->nIndent >= JSON_MAX_DEPTH Then _
                jsonStringTooDeep(pPretty->pOutput)
            pPretty->pParse->iDepth = CUInt(pPretty->nIndent)
            While pPretty->pOutput->eErr = 0
                jsonPrettyIndent(pPretty)
                contentIndex = jsonTranslateBlobToText( _
                    pPretty->pParse, contentIndex, pPretty->pOutput)
                If contentIndex > endIndex Then
                    pPretty->pOutput->eErr = _
                        pPretty->pOutput->eErr Or JSTRING_MALFORMED
                    Exit While
                End If
                jsonAppendRawNZ(pPretty->pOutput, StrPtr(": "), 2)
                contentIndex = jsonTranslateBlobToPrettyText(pPretty, contentIndex)
                If contentIndex >= endIndex Then Exit While
                jsonAppendRawNZ(pPretty->pOutput, _
                    CPtr(Const UByte Ptr, StrPtr(!",\n")), 2)
            Wend
            jsonAppendChar(pPretty->pOutput, Asc(Chr(10)))
            If pPretty->nIndent > 0 Then pPretty->nIndent -= 1
            jsonPrettyIndent(pPretty)
        End If
        jsonAppendChar(pPretty->pOutput, Asc("}"))
        Return endIndex

    Case Else
        Return jsonTranslateBlobToText( _
            pPretty->pParse, startIndex, pPretty->pOutput)
    End Select
End Function

Sub jsonPrettyFunc CDecl Alias "jsonPrettyFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
) Export
    If pContext = 0 OrElse pArguments = 0 OrElse _
       (argumentCount <> 1 AndAlso argumentCount <> 2) Then Return

    Dim pretty As SqliteJsonPrettyContext
    pretty.pParse = jsonParseFuncArg(pContext, pArguments[0], 0)
    If pretty.pParse = 0 Then Return

    Dim jsonOutput As JsonString
    pretty.pOutput = @jsonOutput
    jsonStringInit(@jsonOutput, pContext)
    If argumentCount = 1 Then
        pretty.zIndent = StrPtr("    ")
        pretty.szIndent = 4
    Else
        pretty.zIndent = CPtr(Const ZString Ptr, sqlite3_value_text(pArguments[1]))
        If pretty.zIndent = 0 Then
            pretty.zIndent = StrPtr("    ")
            pretty.szIndent = 4
        Else
            pretty.szIndent = CUInt(jsonOptionalStrlen30(pretty.zIndent))
        End If
    End If

    jsonTranslateBlobToPrettyText(@pretty, 0)
    jsonReturnString(@jsonOutput, 0, 0)
    jsonParseFree(pretty.pParse)
End Sub

Sub jsonErrorFunc CDecl Alias "jsonErrorFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
) Export
    If pContext = 0 OrElse argumentCount <> 1 OrElse pArguments = 0 Then Return

    Dim errorPosition As sqlite3_int64 = 0
    Dim parse As JsonParse
    jsonOptionalMemset(@parse, 0, SizeOf(parse))
    parse.db = CPtr(sqlite3 Ptr, jsonOptionalContextDbHandle(pContext))
    If jsonArgIsJsonb(pArguments[0], @parse) <> 0 Then
        errorPosition = CLngInt(jsonbValidityCheck(@parse, 0, parse.nBlob, 1))
    Else
        parse.zJson = CPtr(ZString Ptr, _
            CPtr(Const UByte Ptr, sqlite3_value_text(pArguments[0])))
        If parse.zJson = 0 Then Return
        parse.nJson = sqlite3_value_bytes(pArguments[0])
        If jsonConvertTextToBlob(@parse, 0) <> SQLITE_OK Then
            If parse.oom <> 0 Then
                errorPosition = -1
            Else
                Dim zInput As Const UByte Ptr = CPtr(Const UByte Ptr, parse.zJson)
                Dim byteIndex As u32 = 0
                While byteIndex < parse.iErr AndAlso _
                      byteIndex < CUInt(parse.nJson) AndAlso zInput[byteIndex] <> 0
                    If (zInput[byteIndex] And &HC0) <> &H80 Then errorPosition += 1
                    byteIndex += 1
                Wend
                errorPosition += 1
            End If
        End If
    End If

    jsonParseReset(@parse)
    If errorPosition < 0 Then
        jsonOptionalResultErrorNoMem(pContext)
    Else
        jsonOptionalResultInt64(pContext, errorPosition)
    End If
End Sub

Sub jsonArrayStep CDecl Alias "jsonArrayStep" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
) Export
    If pContext = 0 OrElse argumentCount <> 1 OrElse pArguments = 0 Then Return
    Dim pOutput As JsonString Ptr = CPtr(JsonString Ptr, _
        sqlite3_aggregate_context(pContext, SizeOf(JsonString)))
    If pOutput = 0 Then Return

    If pOutput->zBuf = 0 Then
        jsonStringInit(pOutput, pContext)
        jsonAppendChar(pOutput, Asc("["))
    ElseIf pOutput->nUsed > 1 Then
        jsonAppendChar(pOutput, Asc(","))
    End If
    pOutput->pCtx = pContext
    jsonAppendSqlValue(pOutput, pArguments[0])
End Sub

Sub jsonObjectStep CDecl Alias "jsonObjectStep" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
) Export
    If pContext = 0 OrElse argumentCount <> 2 OrElse pArguments = 0 Then Return
    Dim pOutput As JsonString Ptr = CPtr(JsonString Ptr, _
        sqlite3_aggregate_context(pContext, SizeOf(JsonString)))
    If pOutput = 0 Then Return

    Dim zLabel As Const UByte Ptr = _
        CPtr(Const UByte Ptr, sqlite3_value_text(pArguments[0]))
    Dim labelLength As u32 = 0
    If zLabel <> 0 Then
        Dim nLabel As SQLITE_C_INT = jsonOptionalStrlen30(CPtr(Const ZString Ptr, zLabel))
        If nLabel > 0 Then labelLength = CUInt(nLabel)
    End If

    If pOutput->zBuf = 0 Then
        jsonStringInit(pOutput, pContext)
        jsonAppendChar(pOutput, Asc("{"))
    ElseIf pOutput->nUsed > 1 Then
        jsonAppendChar(pOutput, Asc(","))
    End If
    pOutput->pCtx = pContext
    If zLabel <> 0 Then
        jsonAppendString(pOutput, zLabel, labelLength)
        jsonAppendChar(pOutput, Asc(":"))
        jsonAppendSqlValue(pOutput, pArguments[1])
    Else
        pOutput->zBuf[0] = Asc("@")
        jsonAppendRawNZ(pOutput, CPtr(Const UByte Ptr, StrPtr("@")), 1)
    End If
End Sub

/' end of sqlite3_json_optional_callbacks.bas '/
