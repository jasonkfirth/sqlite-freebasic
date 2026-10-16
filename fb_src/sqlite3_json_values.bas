/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_values.bas

    Purpose:

        Append SQL values into JSON output and implement basic JSON constructors.

    Responsibilities:

        - Preserve NULL, numeric, text-subtype, and JSONB argument behavior.
        - Quote ordinary SQL text and reject non-JSONB BLOB values.
        - Provide json_quote(), json_array(), and jsonb_array() callbacks.

    This file intentionally does NOT contain:

        - JSON path editing, aggregate JSON functions, or JSON object constructors.
'/ 

#lang "fb"
#include once "sqlite3_json_values.bi"
#include once "sqlite3_json_parse.bi"
#include once "sqlite3_vdbe_api.bi"
#include once "sqlite3_constants.bi"

Extern "C"
    Declare Function jsonValueMemset CDecl Alias "memset" ( _
        ByVal pDestination As Any Ptr, _
        ByVal fillValue As SQLITE_C_INT, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
End Extern

Declare Function jsonValueMPrintf CDecl Alias "sqlite3_mprintf" ( _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) As ZString Ptr
Declare Function jsonValueStrlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal zText As Const ZString Ptr _
) As SQLITE_C_INT
Declare Sub jsonValueFree CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Declare Sub sqlite3_result_error CDecl Alias "sqlite3_result_error" ( _
    ByVal pContext As Any Ptr, _
    ByVal zError As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT _
)
Declare Sub sqlite3_result_error_nomem CDecl Alias "sqlite3_result_error_nomem" ( _
    ByVal pContext As Any Ptr _
)
Declare Sub sqlite3_result_subtype CDecl Alias "sqlite3_result_subtype" ( _
    ByVal pContext As Any Ptr, _
    ByVal subtype As SQLITE_C_UINT _
)

Private Const JSON_VALUE_SUBTYPE As SQLITE_C_UINT = 74

Sub jsonAppendSqlValue CDecl Alias "jsonAppendSqlValue" ( _
    ByVal pOutput As JsonString Ptr, _
    ByVal pValue As SqliteVdbeMem Ptr _
) Export
    If pOutput = 0 Then Exit Sub
    Dim valueType As SQLITE_C_INT = sqlite3_value_type(pValue)
    Select Case valueType
    Case SQLITE_NULL
        jsonAppendRawNZ(pOutput, CPtr(Const UByte Ptr, StrPtr("null")), 4)

    Case SQLITE_FLOAT
        Dim zFormatted As ZString Ptr = _
            jsonValueMPrintf(StrPtr("%!0.17g"), sqlite3_value_double(pValue))
        If zFormatted = 0 Then
            jsonStringOom(pOutput)
        Else
            Dim nFormatted As SQLITE_C_INT = jsonValueStrlen30(zFormatted)
            If nFormatted < 0 Then
                jsonStringOom(pOutput)
            Else
                jsonAppendRaw(pOutput, CPtr(Const UByte Ptr, zFormatted), _
                              CUInt(nFormatted))
            End If
            jsonValueFree(zFormatted)
        End If

    Case SQLITE_INTEGER
        Dim zInteger As Const UByte Ptr = _
            CPtr(Const UByte Ptr, sqlite3_value_text(pValue))
        Dim nInteger As SQLITE_C_INT = sqlite3_value_bytes(pValue)
        If zInteger = 0 AndAlso nInteger > 0 Then
            jsonStringOom(pOutput)
        ElseIf nInteger < 0 Then
            jsonStringOom(pOutput)
        Else
            jsonAppendRaw(pOutput, zInteger, CUInt(nInteger))
        End If

    Case SQLITE_TEXT
        Dim zText As Const UByte Ptr = _
            CPtr(Const UByte Ptr, sqlite3_value_text(pValue))
        Dim nText As SQLITE_C_INT = sqlite3_value_bytes(pValue)
        If zText = 0 AndAlso nText > 0 Then
            jsonStringOom(pOutput)
        ElseIf nText < 0 Then
            jsonStringOom(pOutput)
        ElseIf sqlite3_value_subtype(pValue) = JSON_VALUE_SUBTYPE Then
            jsonAppendRaw(pOutput, zText, CUInt(nText))
        Else
            jsonAppendString(pOutput, zText, CUInt(nText))
        End If

    Case Else
        Dim parse As JsonParse
        jsonValueMemset(@parse, 0, SizeOf(parse))
        If jsonArgIsJsonb(pValue, @parse) <> 0 Then
            jsonTranslateBlobToText(@parse, 0, pOutput)
        ElseIf pOutput->eErr = 0 Then
            sqlite3_result_error(pOutput->pCtx, _
                                 StrPtr("JSON cannot hold BLOB values"), -1)
            pOutput->eErr = JSTRING_ERR
            jsonStringReset(pOutput)
        End If
    End Select
End Sub

Sub jsonQuoteFunc CDecl Alias "jsonQuoteFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
) Export
    If pContext = 0 OrElse argumentCount <> 1 OrElse pArguments = 0 Then Return
    Dim jsonOutput As JsonString
    jsonStringInit(@jsonOutput, pContext)
    jsonAppendSqlValue(@jsonOutput, pArguments[0])
    jsonReturnString(@jsonOutput, 0, 0)
    sqlite3_result_subtype(pContext, JSON_VALUE_SUBTYPE)
End Sub

Sub jsonArrayFunc CDecl Alias "jsonArrayFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
) Export
    If pContext = 0 OrElse argumentCount < 0 OrElse _
       (argumentCount > 0 AndAlso pArguments = 0) Then Return
    Dim jsonOutput As JsonString
    jsonStringInit(@jsonOutput, pContext)
    jsonAppendChar(@jsonOutput, Asc("["))
    For argumentIndex As SQLITE_C_INT = 0 To argumentCount - 1
        jsonAppendSeparator(@jsonOutput)
        jsonAppendSqlValue(@jsonOutput, pArguments[argumentIndex])
    Next
    jsonAppendChar(@jsonOutput, Asc("]"))
    jsonReturnString(@jsonOutput, 0, 0)
    sqlite3_result_subtype(pContext, JSON_VALUE_SUBTYPE)
End Sub

Sub jsonIdentityFunc CDecl Alias "jsonIdentityFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
) Export
    If pContext = 0 OrElse argumentCount <> 1 OrElse pArguments = 0 Then Return
    Dim pParse As JsonParse Ptr = jsonParseFuncArg(pContext, pArguments[0], 0)
    If pParse = 0 Then Return
    jsonReturnParse(pContext, pParse)
    jsonParseFree(pParse)
End Sub

/' end of sqlite3_json_values.bas '/
