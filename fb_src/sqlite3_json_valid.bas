/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_valid.bas

    Purpose:

        Validate JSON inputs and register the built-in JSON scalar and aggregate callbacks.

    Responsibilities:

        - Validate text as canonical JSON or JSON5 according to the flags value.
        - Validate JSONB blobs superficially or recursively as requested.
        - Return SQL NULL for NULL input and an error for invalid flag values.
        - Build JSON and JSONB scalar-function overload definitions.
        - Register JSON array/object aggregate overloads and window callbacks.

    This file intentionally does NOT contain:

        - JSON parsing, path traversal, or callback implementations other than json_valid().
'/ 

#lang "fb"
#include once "sqlite3_json_parse.bi"
#include once "sqlite3_json_query.bi"
#include once "sqlite3_json_values.bi"
#include once "sqlite3_vdbe_api.bi"
#include once "sqlite3_result.bi"
#include once "sqlite3_constants.bi"

#ifndef SQLITE_OMIT_JSON

Extern "C"
    Declare Function jsonValidMemset CDecl Alias "memset" ( _
        ByVal pDestination As Any Ptr, _
        ByVal fillValue As SQLITE_C_INT, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
End Extern

Declare Sub sqlite3_result_int CDecl Alias "sqlite3_result_int" ( _
    ByVal pContext As Any Ptr, _
    ByVal value As SQLITE_C_INT _
)
Declare Sub sqlite3_result_error CDecl Alias "sqlite3_result_error" ( _
    ByVal pContext As Any Ptr, _
    ByVal zError As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT _
)
Declare Sub sqlite3_result_error_nomem CDecl Alias "sqlite3_result_error_nomem" ( _
    ByVal pContext As Any Ptr _
)
Declare Sub sqlite3InsertBuiltinFuncs CDecl Alias "sqlite3InsertBuiltinFuncs" ( _
    ByVal aDefinitions As SqliteFuncDef Ptr, _
    ByVal definitionCount As SQLITE_C_INT _
)
Declare Sub jsonExtractFunc CDecl Alias "jsonExtractFunc" ( _
    ByVal pContext As SqliteResultContext Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
Declare Sub jsonSetFunc CDecl Alias "jsonSetFunc" ( _
    ByVal pContext As SqliteResultContext Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
Declare Sub jsonReplaceFunc CDecl Alias "jsonReplaceFunc" ( _
    ByVal pContext As SqliteResultContext Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
Declare Sub jsonPatchFunc CDecl Alias "jsonPatchFunc" ( _
    ByVal pContext As SqliteResultContext Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
Declare Sub jsonObjectFunc CDecl Alias "jsonObjectFunc" ( _
    ByVal pContext As SqliteResultContext Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
Declare Sub jsonRemoveFunc CDecl Alias "jsonRemoveFunc" ( _
    ByVal pContext As SqliteResultContext Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
Declare Sub jsonPrettyFunc CDecl Alias "jsonPrettyFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
#ifdef SQLITE_DEBUG
Declare Sub jsonParseFunc CDecl Alias "jsonParseFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
#endif
Declare Sub jsonErrorFunc CDecl Alias "jsonErrorFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
Declare Sub jsonArrayStep CDecl Alias "jsonArrayStep" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
Declare Sub jsonObjectStep CDecl Alias "jsonObjectStep" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
Declare Sub jsonArrayValue CDecl Alias "jsonArrayValue" (ByVal pContext As Any Ptr)
Declare Sub jsonArrayFinal CDecl Alias "jsonArrayFinal" (ByVal pContext As Any Ptr)
Declare Sub jsonObjectValue CDecl Alias "jsonObjectValue" (ByVal pContext As Any Ptr)
Declare Sub jsonObjectFinal CDecl Alias "jsonObjectFinal" (ByVal pContext As Any Ptr)
Declare Sub jsonGroupInverse CDecl Alias "jsonGroupInverse" ( _
    ByVal pContext As SqliteResultContext Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
Sub jsonValidFunc CDecl Alias "jsonValidFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
) Export
    If pContext = 0 OrElse pArguments = 0 OrElse _
       (argumentCount <> 1 AndAlso argumentCount <> 2) Then Return

    Dim flags As u8 = 1
    If argumentCount = 2 Then
        Dim requestedFlags As sqlite3_int64 = sqlite3_value_int64(pArguments[1])
        If requestedFlags < 1 OrElse requestedFlags > 15 Then
            sqlite3_result_error(pContext, _
                StrPtr("FLAGS parameter to json_valid() must be between 1 and 15"), -1)
            Return
        End If
        flags = CByte(requestedFlags And &HF)
    End If

    Dim inputType As SQLITE_C_INT = sqlite3_value_type(pArguments[0])
    If inputType = SQLITE_NULL Then
#ifdef SQLITE_LEGACY_JSON_VALID
        sqlite3_result_int(pContext, 0)
#endif
        Return
    End If

    Dim resultValue As SQLITE_C_INT = 0
    If inputType = SQLITE_BLOB Then
        Dim blobParse As JsonParse
        jsonValidMemset(@blobParse, 0, SizeOf(blobParse))
        If jsonArgIsJsonb(pArguments[0], @blobParse) <> 0 Then
            If (flags And &H04) <> 0 Then
                resultValue = 1
            ElseIf (flags And &H08) <> 0 Then
                resultValue = CInt(jsonbValidityCheck( _
                    @blobParse, 0, blobParse.nBlob, 1) = 0)
            End If
            sqlite3_result_int(pContext, resultValue)
            Return
        End If
    End If

    If (flags And &H03) <> 0 Then
        Dim pParse As JsonParse Ptr = _
            jsonParseFuncArg(pContext, pArguments[0], JSON_KEEPERROR)
        If pParse = 0 Then
            sqlite3_result_error_nomem(pContext)
            Return
        End If
        If pParse->oom <> 0 Then
            sqlite3_result_error_nomem(pContext)
        ElseIf pParse->nErr = 0 AndAlso _
               ((flags And &H02) <> 0 OrElse pParse->hasNonstd = 0) Then
            resultValue = 1
        End If
        jsonParseFree(pParse)
    End If
    sqlite3_result_int(pContext, resultValue)
End Sub

#ifdef SQLITE_DEBUG
Private Dim Shared jsonValidFunctionDefinitions(0 To 36) As SqliteFuncDef
#else
Private Dim Shared jsonValidFunctionDefinitions(0 To 35) As SqliteFuncDef
#endif
Private Dim Shared jsonValidFunctionsReady As u8

' These internal function flags match SQLITE_FUNC_BUILTIN and SQLITE_FUNC_RUNONLY.
Private Const JSON_FUNCTION_BUILTIN As u32 = &H00800000
Private Const JSON_FUNCTION_RUNONLY As u32 = &H00008000

Private Function jsonFunctionFlags( _
    ByVal useCache As SQLITE_C_INT, _
    ByVal returnsJsonSubtype As SQLITE_C_INT, _
    ByVal acceptsJsonSubtype As SQLITE_C_INT _
) As u32
    Dim flags As u32 = JSON_FUNCTION_BUILTIN Or SQLITE_FUNC_CONSTANT Or SQLITE_UTF8
    If useCache <> 0 Then flags Or= JSON_FUNCTION_RUNONLY
    If returnsJsonSubtype <> 0 Then flags Or= SQLITE_RESULT_SUBTYPE
    If acceptsJsonSubtype <> 0 Then flags Or= SQLITE_SUBTYPE
    Return flags
End Function

Private Sub jsonDefineScalar( _
    ByVal definitionIndex As SQLITE_C_INT, _
    ByVal zName As ZString Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal useCache As SQLITE_C_INT, _
    ByVal returnsJsonSubtype As SQLITE_C_INT, _
    ByVal acceptsJsonSubtype As SQLITE_C_INT, _
    ByVal returnsJsonBlob As SQLITE_C_INT, _
    ByVal argumentFlags As u32, _
    ByVal xFunction As SqliteScalarFunction _
)
    If definitionIndex < 0 OrElse definitionIndex > UBound(jsonValidFunctionDefinitions) Then Return
    With jsonValidFunctionDefinitions(definitionIndex)
        .nArg = CShort(argumentCount)
        .funcFlags = jsonFunctionFlags( _
            useCache, returnsJsonSubtype, acceptsJsonSubtype)
        .pUserData = CPtr(Any Ptr, argumentFlags Or IIf(returnsJsonBlob <> 0, JSON_BLOB, 0))
        .xSFunc = xFunction
        .zName = zName
    End With
End Sub

Private Sub jsonDefineAggregate( _
    ByVal definitionIndex As SQLITE_C_INT, _
    ByVal zName As ZString Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal returnsJsonBlob As SQLITE_C_INT, _
    ByVal xStep As SqliteScalarFunction, _
    ByVal xFinal As Any Ptr, _
    ByVal xValue As Any Ptr, _
    ByVal xInverse As Any Ptr _
)
    If definitionIndex < 0 OrElse definitionIndex > UBound(jsonValidFunctionDefinitions) Then Return
    With jsonValidFunctionDefinitions(definitionIndex)
        .nArg = CShort(argumentCount)
        .funcFlags = JSON_FUNCTION_BUILTIN Or SQLITE_FUNC_CONSTANT Or SQLITE_UTF8 Or _
                     SQLITE_SUBTYPE Or SQLITE_RESULT_SUBTYPE
        .pUserData = CPtr(Any Ptr, IIf(returnsJsonBlob <> 0, JSON_BLOB, 0))
        .xSFunc = xStep
        .xFinalize = xFinal
        .xValue = xValue
        .xInverse = xInverse
        .zName = zName
    End With
End Sub

Sub sqlite3RegisterJsonFunctions CDecl Alias "sqlite3RegisterJsonFunctions" () Export
    If jsonValidFunctionsReady <> 0 Then Exit Sub
    With jsonValidFunctionDefinitions(0)
        .nArg = 1
        .funcFlags = JSON_FUNCTION_BUILTIN Or JSON_FUNCTION_RUNONLY Or _
                            SQLITE_UTF8 Or SQLITE_FUNC_CONSTANT
        .xSFunc = @jsonValidFunc
        .zName = StrPtr("json_valid")
    End With
    With jsonValidFunctionDefinitions(1)
        .nArg = 2
        .funcFlags = JSON_FUNCTION_BUILTIN Or JSON_FUNCTION_RUNONLY Or _
                            SQLITE_UTF8 Or SQLITE_FUNC_CONSTANT
        .xSFunc = @jsonValidFunc
        .zName = StrPtr("json_valid")
    End With
    With jsonValidFunctionDefinitions(2)
        .nArg = 1
        .funcFlags = JSON_FUNCTION_BUILTIN Or SQLITE_UTF8 Or _
                            SQLITE_FUNC_CONSTANT Or SQLITE_SUBTYPE Or SQLITE_RESULT_SUBTYPE
        .xSFunc = @jsonQuoteFunc
        .zName = StrPtr("json_quote")
    End With
    With jsonValidFunctionDefinitions(3)
        .nArg = -1
        .funcFlags = JSON_FUNCTION_BUILTIN Or SQLITE_UTF8 Or _
                            SQLITE_FUNC_CONSTANT Or SQLITE_SUBTYPE Or SQLITE_RESULT_SUBTYPE
        .xSFunc = @jsonArrayFunc
        .zName = StrPtr("json_array")
    End With
    With jsonValidFunctionDefinitions(4)
        .nArg = -1
        .funcFlags = JSON_FUNCTION_BUILTIN Or SQLITE_UTF8 Or _
                            SQLITE_FUNC_CONSTANT Or SQLITE_SUBTYPE Or SQLITE_RESULT_SUBTYPE
        .pUserData = CPtr(Any Ptr, JSON_BLOB)
        .xSFunc = @jsonArrayFunc
        .zName = StrPtr("jsonb_array")
    End With
    With jsonValidFunctionDefinitions(5)
        .nArg = 1
        .funcFlags = JSON_FUNCTION_BUILTIN Or JSON_FUNCTION_RUNONLY Or _
                            SQLITE_UTF8 Or SQLITE_FUNC_CONSTANT Or SQLITE_RESULT_SUBTYPE
        .xSFunc = @jsonIdentityFunc
        .zName = StrPtr("json")
    End With
    With jsonValidFunctionDefinitions(6)
        .nArg = 1
        .funcFlags = JSON_FUNCTION_BUILTIN Or JSON_FUNCTION_RUNONLY Or _
                            SQLITE_UTF8 Or SQLITE_FUNC_CONSTANT
        .pUserData = CPtr(Any Ptr, JSON_BLOB)
        .xSFunc = @jsonIdentityFunc
        .zName = StrPtr("jsonb")
    End With
    With jsonValidFunctionDefinitions(7)
        .nArg = 1
        .funcFlags = JSON_FUNCTION_BUILTIN Or JSON_FUNCTION_RUNONLY Or _
                            SQLITE_UTF8 Or SQLITE_FUNC_CONSTANT
        .xSFunc = @jsonArrayLengthFunc
        .zName = StrPtr("json_array_length")
    End With
    With jsonValidFunctionDefinitions(8)
        .nArg = 2
        .funcFlags = JSON_FUNCTION_BUILTIN Or JSON_FUNCTION_RUNONLY Or _
                            SQLITE_UTF8 Or SQLITE_FUNC_CONSTANT
        .xSFunc = @jsonArrayLengthFunc
        .zName = StrPtr("json_array_length")
    End With
    With jsonValidFunctionDefinitions(9)
        .nArg = 1
        .funcFlags = JSON_FUNCTION_BUILTIN Or JSON_FUNCTION_RUNONLY Or _
                            SQLITE_UTF8 Or SQLITE_FUNC_CONSTANT
        .xSFunc = @jsonTypeFunc
        .zName = StrPtr("json_type")
    End With
    With jsonValidFunctionDefinitions(10)
        .nArg = 2
        .funcFlags = JSON_FUNCTION_BUILTIN Or JSON_FUNCTION_RUNONLY Or _
                            SQLITE_UTF8 Or SQLITE_FUNC_CONSTANT
        .xSFunc = @jsonTypeFunc
        .zName = StrPtr("json_type")
    End With

    jsonDefineScalar(11, StrPtr("json_array_insert"), -1, 1, 1, 1, 0, _
        JSON_AINS, CPtr(SqliteScalarFunction, ProcPtr(jsonSetFunc)))
    jsonDefineScalar(12, StrPtr("jsonb_array_insert"), -1, 1, 0, 0, 1, _
        JSON_AINS, CPtr(SqliteScalarFunction, ProcPtr(jsonSetFunc)))
    jsonDefineScalar(13, StrPtr("json_error_position"), 1, 1, 0, 0, 0, _
        0, CPtr(SqliteScalarFunction, ProcPtr(jsonErrorFunc)))
    jsonDefineScalar(14, StrPtr("json_extract"), -1, 1, 1, 1, 0, _
        0, CPtr(SqliteScalarFunction, ProcPtr(jsonExtractFunc)))
    jsonDefineScalar(15, StrPtr("jsonb_extract"), -1, 1, 0, 0, 1, _
        0, CPtr(SqliteScalarFunction, ProcPtr(jsonExtractFunc)))
    jsonDefineScalar(16, StrPtr("->"), 2, 1, 1, 0, 0, _
        JSON_JSON, CPtr(SqliteScalarFunction, ProcPtr(jsonExtractFunc)))
    jsonDefineScalar(17, StrPtr("->>"), 2, 1, 0, 0, 0, _
        JSON_SQL, CPtr(SqliteScalarFunction, ProcPtr(jsonExtractFunc)))
    jsonDefineScalar(18, StrPtr("json_insert"), -1, 1, 1, 1, 0, _
        0, CPtr(SqliteScalarFunction, ProcPtr(jsonSetFunc)))
    jsonDefineScalar(19, StrPtr("jsonb_insert"), -1, 1, 0, 1, 1, _
        0, CPtr(SqliteScalarFunction, ProcPtr(jsonSetFunc)))
    jsonDefineScalar(20, StrPtr("json_object"), -1, 0, 1, 1, 0, _
        0, CPtr(SqliteScalarFunction, ProcPtr(jsonObjectFunc)))
    jsonDefineScalar(21, StrPtr("jsonb_object"), -1, 0, 1, 1, 1, _
        0, CPtr(SqliteScalarFunction, ProcPtr(jsonObjectFunc)))
    jsonDefineScalar(22, StrPtr("json_patch"), 2, 1, 1, 0, 0, _
        0, CPtr(SqliteScalarFunction, ProcPtr(jsonPatchFunc)))
    jsonDefineScalar(23, StrPtr("jsonb_patch"), 2, 1, 0, 0, 1, _
        0, CPtr(SqliteScalarFunction, ProcPtr(jsonPatchFunc)))
    jsonDefineScalar(24, StrPtr("json_pretty"), 1, 1, 1, 0, 0, _
        0, CPtr(SqliteScalarFunction, ProcPtr(jsonPrettyFunc)))
    jsonDefineScalar(25, StrPtr("json_pretty"), 2, 1, 1, 0, 0, _
        0, CPtr(SqliteScalarFunction, ProcPtr(jsonPrettyFunc)))
    jsonDefineScalar(26, StrPtr("json_remove"), -1, 1, 1, 1, 0, _
        0, CPtr(SqliteScalarFunction, ProcPtr(jsonRemoveFunc)))
    jsonDefineScalar(27, StrPtr("jsonb_remove"), -1, 1, 0, 0, 1, _
        0, CPtr(SqliteScalarFunction, ProcPtr(jsonRemoveFunc)))
    jsonDefineScalar(28, StrPtr("json_replace"), -1, 1, 1, 1, 0, _
        0, CPtr(SqliteScalarFunction, ProcPtr(jsonReplaceFunc)))
    jsonDefineScalar(29, StrPtr("jsonb_replace"), -1, 1, 0, 1, 1, _
        0, CPtr(SqliteScalarFunction, ProcPtr(jsonReplaceFunc)))
    jsonDefineScalar(30, StrPtr("json_set"), -1, 1, 1, 1, 0, _
        JSON_ISSET, CPtr(SqliteScalarFunction, ProcPtr(jsonSetFunc)))
    jsonDefineScalar(31, StrPtr("jsonb_set"), -1, 1, 0, 1, 1, _
        JSON_ISSET, CPtr(SqliteScalarFunction, ProcPtr(jsonSetFunc)))

    Dim inverseCallback As Any Ptr = 0
#ifndef SQLITE_OMIT_WINDOWFUNC
    inverseCallback = CPtr(Any Ptr, ProcPtr(jsonGroupInverse))
#endif
    jsonDefineAggregate(32, StrPtr("json_group_array"), 1, 0, _
        CPtr(SqliteScalarFunction, ProcPtr(jsonArrayStep)), _
        CPtr(Any Ptr, ProcPtr(jsonArrayFinal)), _
        CPtr(Any Ptr, ProcPtr(jsonArrayValue)), inverseCallback)
    jsonDefineAggregate(33, StrPtr("jsonb_group_array"), 1, 1, _
        CPtr(SqliteScalarFunction, ProcPtr(jsonArrayStep)), _
        CPtr(Any Ptr, ProcPtr(jsonArrayFinal)), _
        CPtr(Any Ptr, ProcPtr(jsonArrayValue)), inverseCallback)
    jsonDefineAggregate(34, StrPtr("json_group_object"), 2, 0, _
        CPtr(SqliteScalarFunction, ProcPtr(jsonObjectStep)), _
        CPtr(Any Ptr, ProcPtr(jsonObjectFinal)), _
        CPtr(Any Ptr, ProcPtr(jsonObjectValue)), inverseCallback)
    jsonDefineAggregate(35, StrPtr("jsonb_group_object"), 2, 1, _
        CPtr(SqliteScalarFunction, ProcPtr(jsonObjectStep)), _
        CPtr(Any Ptr, ProcPtr(jsonObjectFinal)), _
        CPtr(Any Ptr, ProcPtr(jsonObjectValue)), inverseCallback)

#ifdef SQLITE_DEBUG
    jsonDefineScalar(36, StrPtr("json_parse"), 1, 1, 0, 0, 0, 0, _
        CPtr(SqliteScalarFunction, ProcPtr(jsonParseFunc)))
#endif

    sqlite3InsertBuiltinFuncs(@jsonValidFunctionDefinitions(0), _
                              UBound(jsonValidFunctionDefinitions) + 1)
    jsonValidFunctionsReady = 1
End Sub

#endif

/' end of sqlite3_json_valid.bas '/
