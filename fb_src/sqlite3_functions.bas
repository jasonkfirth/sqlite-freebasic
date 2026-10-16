/'
    Project: SQLite FreeBASIC port

    File: sqlite3_functions.bas

    Purpose:

        Provide scalar function definitions used by OP_Function.

    Responsibilities:

        - Register the built-in scalar functions used by the SQL compiler.
        - Register optional math and percentile built-ins after their callbacks are available.
        - Dispatch optional soundex and file/WAL diagnostic registrations.
        - Register ALTER TABLE callback functions when that feature is enabled.
        - Trigger built-in window-function registration during initialization.
        - Initialize built-in window-function registration with the scalar table.
        - Hash built-in names and link overloads for efficient lookup.
        - Score overload matches by argument count and text encoding.
        - Store per-connection application-defined scalar functions and callbacks.
        - Expose built-in hash buckets to the PRAGMA function-list implementation.
        - Implement the currently registered scalar built-ins.
        - Preserve sqlite3_context, sqlite3_value, and destructor callback contracts.

    This file intentionally does NOT contain:

        - Aggregate/window callback implementations or frame execution.
'/ 

#lang "fb"
#include once "sqlite3_result.bi"
#include once "sqlite3_function_tables.bi"
#include once "sqlite3_function_aggregate_contexts.bi"
#include once "sqlite3_straccum.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_vdbe_compare.bi"
#include once "sqlite3_vdbe_api.bi"
#include once "sqlite3_util_numeric.bi"
#include once "sqlite3_mutex.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_global_data.bi"
#include once "sqlite3_vfs.bi"
#include once "sqlite3_debug_assert.bi"

#ifndef SQLITE_OMIT_JSON
Declare Sub sqlite3RegisterJsonFunctions CDecl Alias "sqlite3RegisterJsonFunctions" ()
#endif
#ifndef SQLITE_OMIT_ALTERTABLE
Declare Sub sqlite3AlterFunctions CDecl Alias "sqlite3AlterFunctions" ()
#endif
#ifndef SQLITE_OMIT_DATETIME_FUNCS
Declare Sub sqlite3RegisterDateTimeFunctions CDecl Alias "sqlite3RegisterDateTimeFunctions" ()
#endif
#ifndef SQLITE_OMIT_WINDOWFUNC
Declare Sub sqlite3WindowFunctions CDecl Alias "sqlite3WindowFunctions" ()
#endif
Declare Sub sqlite3RegisterOptionalBuiltinFunctions CDecl Alias _
    "sqlite3RegisterOptionalBuiltinFunctions" ()

#ifndef SQLITE_MAX_FUNCTION_ARG
#define SQLITE_MAX_FUNCTION_ARG 1000
#endif
#ifndef SQLITE_MAX_LIKE_PATTERN_LENGTH
#define SQLITE_MAX_LIKE_PATTERN_LENGTH 50000
#endif

Declare Function sqlite3CreateFunc CDecl Alias "sqlite3CreateFunc" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal nArg As SQLITE_C_INT, _
    ByVal textEncoding As SQLITE_C_INT, _
    ByVal pUserData As Any Ptr, _
    ByVal xScalar As Any Ptr, _
    ByVal xStep As Any Ptr, _
    ByVal xFinal As Any Ptr, _
    ByVal xDestroy As Any Ptr, _
    ByVal xValue As Any Ptr, _
    ByVal xInverse As Any Ptr _
) As SQLITE_C_INT

#ifdef SQLITE_DEBUG
Declare Sub fpdecodeFunc CDecl Alias "fpdecodeFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As Any Ptr Ptr _
)
Declare Function sqlite3FunctionsParseUri CDecl Alias "sqlite3ParseUri" ( _
    ByVal zDefaultVfs As Const ZString Ptr, _
    ByVal zUriText As Const ZString Ptr, _
    ByVal pFlags As SQLITE_C_UINT Ptr, _
    ByVal ppVfs As sqlite3_vfs Ptr Ptr, _
    ByVal pzFile As ZString Ptr Ptr, _
    ByVal pzError As ZString Ptr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3FunctionsUriKey CDecl Alias "sqlite3_uri_key" ( _
    ByVal zFilename As Const ZString Ptr, _
    ByVal keyIndex As SQLITE_C_INT _
) As Const ZString Ptr
Declare Function sqlite3FunctionsUriParameter CDecl Alias "sqlite3_uri_parameter" ( _
    ByVal zFilename As Const ZString Ptr, _
    ByVal zParameter As Const ZString Ptr _
) As Const ZString Ptr
Declare Sub sqlite3FunctionsFreeFilename CDecl Alias "sqlite3_free_filename" ( _
    ByVal zFilename As Const ZString Ptr _
)
Declare Sub sqlite3FunctionsFree CDecl Alias "sqlite3_free" ( _
    ByVal pAllocation As Any Ptr _
)
#endif


Type SqliteFunctionDestroyCallback As Sub CDecl ( _
    ByVal pUserData As Any Ptr _
)

Dim Shared sqlite3LikeCompareInfo As SqliteLikeCompareInfo
Dim Shared sqlite3LikeCompareInfoAlt As SqliteLikeCompareInfo
Dim Shared sqlite3GlobCompareInfo As SqliteLikeCompareInfo

Declare Function sqlite3_stricmp CDecl Alias "sqlite3_stricmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal z As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3PatternCompare CDecl Alias "sqlite3PatternCompare" ( _
    ByVal zPattern As Const UByte Ptr, _
    ByVal zInput As Const UByte Ptr, _
    ByVal matchAll As UByte, _
    ByVal matchOne As UByte, _
    ByVal matchSet As UByte, _
    ByVal noCase As UByte, _
    ByVal matchOther As u32 _
) As SQLITE_C_INT
Declare Function sqlite3Utf8CharLen CDecl Alias "sqlite3Utf8CharLen" ( _
    ByVal zText As Const UByte Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3Utf8Read CDecl Alias "sqlite3Utf8Read" ( _
    ByVal pzArgument As Any Ptr _
) As u32
Declare Function sqlite3AppendOneUtf8Character CDecl Alias "sqlite3AppendOneUtf8Character" ( _
    ByVal zOutput As UByte Ptr, _
    ByVal codepoint As u32 _
) As SQLITE_C_INT
Declare Function sqlite3AtoF CDecl Alias "sqlite3AtoF" ( _
    ByVal zArgument As Const ZString Ptr, _
    ByVal pResult As Double Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_context_db_handle CDecl Alias "sqlite3_context_db_handle" ( _
    ByVal pContext As Any Ptr _
) As Any Ptr
Declare Sub sqlite3_log CDecl Alias "sqlite3_log" ( _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Function sqlite3_mprintf CDecl Alias "sqlite3_mprintf" ( _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) As ZString Ptr
Declare Function sqlite3Utf16to8 CDecl Alias "sqlite3Utf16to8" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zInput As Any Ptr, _
    ByVal byteCount As SQLITE_C_INT, _
    ByVal encoding As u8 _
) As ZString Ptr
Declare Function sqlite3_libversion CDecl Alias "sqlite3_libversion" () As Const ZString Ptr
Declare Function sqlite3_sourceid CDecl Alias "sqlite3_sourceid" () As Const ZString Ptr
Declare Function sqlite3_compileoption_used CDecl Alias "sqlite3_compileoption_used" ( _
    ByVal zOptionName As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_compileoption_get CDecl Alias "sqlite3_compileoption_get" ( _
    ByVal optionIndex As SQLITE_C_INT _
) As Const ZString Ptr
Declare Function sqlite3_last_insert_rowid CDecl Alias "sqlite3_last_insert_rowid" ( _
    ByVal db As sqlite3 Ptr _
) As sqlite3_int64
Declare Function sqlite3_changes64 CDecl Alias "sqlite3_changes64" ( _
    ByVal db As sqlite3 Ptr _
) As sqlite3_int64
Declare Function sqlite3_total_changes64 CDecl Alias "sqlite3_total_changes64" ( _
    ByVal db As sqlite3 Ptr _
) As sqlite3_int64
Declare Function sqlite3_malloc64 CDecl Alias "sqlite3_malloc64" ( _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Function sqlite3_realloc64 CDecl Alias "sqlite3_realloc64" ( _
    ByVal pOriginal As Any Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Declare Function sqlite3_load_extension CDecl Alias "sqlite3_load_extension" ( _
    ByVal db As Any Ptr, _
    ByVal zFilename As Const ZString Ptr, _
    ByVal zProcName As Const ZString Ptr, _
    ByVal pzError As ZString Ptr Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3_result_error CDecl Alias "sqlite3_result_error" ( _
    ByVal pContext As Any Ptr, _
    ByVal zError As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT _
)
Declare Sub sqlite3_result_error_nomem CDecl Alias "sqlite3_result_error_nomem" ( _
    ByVal pContext As Any Ptr _
)
Declare Sub sqlite3_result_error_toobig CDecl Alias "sqlite3_result_error_toobig" ( _
    ByVal pContext As Any Ptr _
)
Declare Sub sqlite3_result_double CDecl Alias "sqlite3_result_double" ( _
    ByVal pContext As Any Ptr, _
    ByVal value As Double _
)
Declare Sub sqlite3_result_int CDecl Alias "sqlite3_result_int" ( _
    ByVal pContext As Any Ptr, _
    ByVal value As SQLITE_C_INT _
)
Declare Sub sqlite3_result_int64 CDecl Alias "sqlite3_result_int64" ( _
    ByVal pContext As Any Ptr, _
    ByVal value As sqlite3_int64 _
)
Declare Sub sqlite3_result_null CDecl Alias "sqlite3_result_null" ( _
    ByVal pContext As Any Ptr _
)
Declare Sub sqlite3_result_text CDecl Alias "sqlite3_result_text" ( _
    ByVal pContext As Any Ptr, _
    ByVal zText As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal pDestructor As Any Ptr _
)
Declare Sub sqlite3_randomness CDecl Alias "sqlite3_randomness" ( _
    ByVal nByte As SQLITE_C_INT, _
    ByVal pBuffer As Any Ptr _
)
Declare Sub sqlite3_result_blob64 CDecl Alias "sqlite3_result_blob64" ( _
    ByVal pContext As Any Ptr, _
    ByVal pBlob As Any Ptr, _
    ByVal nByte As sqlite3_uint64, _
    ByVal pDestructor As Any Ptr _
)
Declare Function sqlite3_result_zeroblob64 CDecl Alias "sqlite3_result_zeroblob64" ( _
    ByVal pContext As Any Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As SQLITE_C_INT
Declare Function sqlite3_user_data CDecl Alias "sqlite3_user_data" ( _
    ByVal pContext As Any Ptr _
) As Any Ptr
Declare Sub sqlite3_str_appendf CDecl Alias "sqlite3_str_appendf" ( _
    ByVal pAccumulator As sqlite3_str Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Sub sqlite3_result_str CDecl Alias "sqlite3_result_str" ( _
    ByVal pContext As Any Ptr, _
    ByVal pAccumulator As sqlite3_str Ptr, _
    ByVal ownership As SQLITE_C_INT _
)
Declare Sub sqlite3_result_value CDecl Alias "sqlite3_result_value" ( _
    ByVal pContext As Any Ptr, _
    ByVal pValue As Any Ptr _
)

Private Const SQLITE_FUNC_HASH_SZ As Long = 23
Private Const SQLITE_FUNC_ENCMASK As u32 = &H0003
Private Const SQLITE_FUNC_BUILTIN As u32 = &H00800000
Private Const SQLITE_FUNC_LIKE As u32 = &H0004
Private Const SQLITE_FUNC_CASE As u32 = &H0008
Private Const SQLITE_FUNC_UNSAFE As u32 = &H00200000
Private Const FUNC_PERFECT_MATCH As SQLITE_C_INT = 6
Dim Shared As SqliteFuncDef Ptr sqlite3BuiltinFunctionBuckets( _
    0 To SQLITE_FUNC_HASH_SZ - 1)
Dim Shared As u8 sqlite3BuiltinFunctionsReady = 0

Function sqlite3BuiltinFunctionBucketsPtr CDecl Alias "sqlite3BuiltinFunctionBucketsPtr" () As SqliteFuncDef Ptr Ptr
    Return @sqlite3BuiltinFunctionBuckets(0)
End Function

Private Function sqlite3GetFuncCollSeq CDecl Alias "sqlite3GetFuncCollSeq" ( _
    ByVal pContextArgument As Any Ptr _
) As sqlite3CollSeq Ptr
    If pContextArgument = 0 Then Return 0
    Dim pContext As SqliteResultContext Ptr = _
        CPtr(SqliteResultContext Ptr, pContextArgument)
    If pContext->pVdbe = 0 OrElse pContext->iOp <= 0 Then Return 0
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pContext->pVdbe)
    If pVdbe->aOp = 0 OrElse pContext->iOp > pVdbe->nOp Then Return 0
    Dim pOp As SqliteVdbeOp Ptr = @pVdbe->aOp[pContext->iOp - 1]
    If pOp->opcode <> OP_CollSeq OrElse pOp->p4type <> P4_COLLSEQ Then Return 0
    Return CPtr(sqlite3CollSeq Ptr, pOp->p4.p)
End Function

Private Sub sqlite3SkipAccumulatorLoad CDecl Alias "sqlite3SkipAccumulatorLoad" ( _
    ByVal pContextArgument As Any Ptr _
)
    If pContextArgument = 0 Then Return
    Dim pContext As SqliteResultContext Ptr = _
        CPtr(SqliteResultContext Ptr, pContextArgument)
    pContext->isError = -1
    pContext->skipFlag = 1
End Sub

Private Sub absFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 1 Then Return
    Dim valueType As SQLITE_C_INT = sqlite3_value_type(pArguments[0])
    If valueType = SQLITE_NULL Then
        sqlite3_result_null(pContext)
    ElseIf valueType = SQLITE_INTEGER Then
        Dim value As sqlite3_int64 = sqlite3_value_int64(pArguments[0])
        If value = (-9223372036854775807LL - 1) Then
            sqlite3_result_error(pContext, StrPtr("integer overflow"), -1)
        Else
            If value < 0 Then value = -value
            sqlite3_result_int64(pContext, value)
        End If
    Else
        Dim value As Double = sqlite3_value_double(pArguments[0])
        If value < 0.0 Then value = -value
        sqlite3_result_double(pContext, value)
    End If
End Sub

Private Sub lengthFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 1 Then Return
    Dim valueType As SQLITE_C_INT = sqlite3_value_type(pArguments[0])
    Select Case valueType
    Case SQLITE_NULL
        sqlite3_result_null(pContext)
    Case SQLITE_BLOB, SQLITE_INTEGER, SQLITE_FLOAT
        sqlite3_result_int(pContext, sqlite3_value_bytes(pArguments[0]))
    Case SQLITE_TEXT
        Dim zText As Const UByte Ptr = sqlite3_value_text(pArguments[0])
        If zText = 0 Then
            sqlite3_result_error_nomem(pContext)
            Return
        End If
        Dim byteCount As SQLITE_C_INT = sqlite3_value_bytes(pArguments[0])
        If byteCount < 0 Then
            sqlite3_result_error_nomem(pContext)
            Return
        End If
        sqlite3_result_int(pContext, sqlite3Utf8CharLen(zText, byteCount))
    Case Else
        sqlite3_result_null(pContext)
    End Select
End Sub

Private Sub sqlite3BuiltinCaseConvert( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr, _
    ByVal uppercase As SQLITE_C_INT _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 1 Then Return
    Dim zInput As Const UByte Ptr = sqlite3_value_text(pArguments[0])
    If zInput = 0 Then
        If sqlite3_value_type(pArguments[0]) = SQLITE_NULL Then
            sqlite3_result_null(pContext)
        Else
            sqlite3_result_error_nomem(pContext)
        End If
        Return
    End If

    Dim byteCount As SQLITE_C_INT = sqlite3_value_bytes(pArguments[0])
    If byteCount < 0 OrElse _
       CULngInt(byteCount) >= SQLITE_MAX_ALLOCATION_SIZE Then
        sqlite3_result_error_toobig(pContext)
        Return
    End If
    Dim pResult As UByte Ptr = CPtr(UByte Ptr, _
        sqlite3_malloc64(CULngInt(byteCount) + 1))
    If pResult = 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If
    For iByte As SQLITE_C_INT = 0 To byteCount - 1
        Dim valueByte As UByte = zInput[iByte]
        If uppercase <> 0 Then
            If valueByte >= Asc("a") AndAlso valueByte <= Asc("z") Then _
                valueByte = valueByte - Asc("a") + Asc("A")
        Else
            If valueByte >= Asc("A") AndAlso valueByte <= Asc("Z") Then _
                valueByte = valueByte - Asc("A") + Asc("a")
        End If
        pResult[iByte] = valueByte
    Next
    pResult[byteCount] = 0
    sqlite3_result_text(pContext, CPtr(Const ZString Ptr, pResult), byteCount, _
                        CPtr(Any Ptr, @sqlite3_free))
End Sub

Private Sub lowerFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    sqlite3BuiltinCaseConvert(pContext, argumentCount, pArguments, 0)
End Sub

Private Sub upperFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    sqlite3BuiltinCaseConvert(pContext, argumentCount, pArguments, 1)
End Sub

Private Function contextMalloc CDecl Alias "contextMalloc" ( _
    ByVal pContext As Any Ptr, _
    ByVal nByte As sqlite3_int64 _
) As Any Ptr
    If pContext = 0 OrElse nByte <= 0 Then Return 0
    Dim pDatabase As sqlite3 Ptr = CPtr(sqlite3 Ptr, _
        sqlite3_context_db_handle(pContext))
    If pDatabase = 0 OrElse pDatabase->lengthLimit < 0 OrElse _
       nByte > pDatabase->lengthLimit OrElse _
       nByte > SQLITE_MAX_ALLOCATION_SIZE Then
        sqlite3_result_error_toobig(pContext)
        Return 0
    End If
    Dim pMemory As Any Ptr = sqlite3_malloc64(CULngInt(nByte))
    If pMemory = 0 Then sqlite3_result_error_nomem(pContext)
    Return pMemory
End Function

Private Sub hexFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 1 Then Return
    Dim byteCount As SQLITE_C_INT = sqlite3_value_bytes(pArguments[0])
    Dim pInput As Const UByte Ptr = _
        CPtr(Const UByte Ptr, sqlite3_value_blob(pArguments[0]))
    If byteCount < 0 OrElse CULngInt(byteCount) > _
       (SQLITE_MAX_ALLOCATION_SIZE - 1) \ 2 Then
        sqlite3_result_error_toobig(pContext)
        Return
    End If
    If byteCount > 0 AndAlso pInput = 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If

    Dim outputLength As SQLITE_C_INT = byteCount * 2
    Dim pOutput As UByte Ptr = CPtr(UByte Ptr, _
        contextMalloc(pContext, CULngInt(outputLength) + 1))
    If pOutput = 0 Then Return
    Dim zHex As Const UByte Ptr = CPtr(Const UByte Ptr, StrPtr("0123456789ABCDEF"))
    For iByte As SQLITE_C_INT = 0 To byteCount - 1
        pOutput[iByte * 2] = CByte(zHex[pInput[iByte] Shr 4])
        pOutput[iByte * 2 + 1] = CByte(zHex[pInput[iByte] And &H0F])
    Next
    pOutput[outputLength] = 0
    sqlite3_result_text(pContext, CPtr(Const ZString Ptr, pOutput), outputLength, _
                        CPtr(Any Ptr, @sqlite3_free))
End Sub

Private Sub roundFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse _
       (argumentCount <> 1 AndAlso argumentCount <> 2) Then Return
    Dim digits As sqlite3_int64 = 0
    If argumentCount = 2 Then
        If sqlite3_value_type(pArguments[1]) = SQLITE_NULL Then Return
        digits = sqlite3_value_int64(pArguments[1])
        If digits > 30 Then digits = 30
        If digits < 0 Then digits = 0
    End If
    If sqlite3_value_type(pArguments[0]) = SQLITE_NULL Then Return

    Dim value As Double = sqlite3_value_double(pArguments[0])
    If sqlite3IsNaN(value) <> 0 Then
        sqlite3_result_double(pContext, value)
        Return
    End If
    ' A binary64 value has no fractional part at magnitudes of 2^52 and above.
    If value >= -4503599627370496.0 AndAlso _
       value <= 4503599627370496.0 Then
        If digits = 0 Then
            Dim adjustment As Double = 0.5
            If value < 0.0 Then adjustment = -0.5
            value = CDbl(CLngInt(Fix(value + adjustment)))
        Else
            Dim zFormatted As ZString Ptr = sqlite3_mprintf( _
                StrPtr("%!.*f"), CInt(digits), value)
            If zFormatted = 0 Then
                sqlite3_result_error_nomem(pContext)
                Return
            End If
            sqlite3AtoF(zFormatted, @value)
            sqlite3_free(zFormatted)
        End If
    End If
    sqlite3_result_double(pContext, value)
End Sub

Private Sub signFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 1 Then Return
    Dim valueType As SQLITE_C_INT = sqlite3_value_numeric_type(pArguments[0])
    If valueType <> SQLITE_INTEGER AndAlso valueType <> SQLITE_FLOAT Then Return
    Dim value As Double = sqlite3_value_double(pArguments[0])
    If value < 0.0 Then
        sqlite3_result_int(pContext, -1)
    ElseIf value > 0.0 Then
        sqlite3_result_int(pContext, 1)
    Else
        sqlite3_result_int(pContext, 0)
    End If
End Sub

Private Sub instrFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 2 Then Return
    Dim haystackType As SQLITE_C_INT = sqlite3_value_type(pArguments[0])
    Dim needleType As SQLITE_C_INT = sqlite3_value_type(pArguments[1])
    If haystackType = SQLITE_NULL OrElse needleType = SQLITE_NULL Then Return

    Dim haystackLength As SQLITE_C_INT = sqlite3_value_bytes(pArguments[0])
    Dim needleLength As SQLITE_C_INT = sqlite3_value_bytes(pArguments[1])
    If haystackLength < 0 OrElse needleLength < 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If
    If needleLength = 0 Then
        sqlite3_result_int(pContext, 1)
        Return
    End If

    Dim pHaystack As Const UByte Ptr = 0
    Dim pNeedle As Const UByte Ptr = 0
    Dim pHaystackCopy As Any Ptr = 0
    Dim pNeedleCopy As Any Ptr = 0
    Dim isText As SQLITE_C_INT = 0
    If haystackType = SQLITE_BLOB AndAlso needleType = SQLITE_BLOB Then
        pHaystack = CPtr(Const UByte Ptr, sqlite3_value_blob(pArguments[0]))
        pNeedle = CPtr(Const UByte Ptr, sqlite3_value_blob(pArguments[1]))
    ElseIf haystackType <> SQLITE_BLOB AndAlso needleType <> SQLITE_BLOB Then
        pHaystack = sqlite3_value_text(pArguments[0])
        pNeedle = sqlite3_value_text(pArguments[1])
        isText = -1
    Else
        pHaystackCopy = sqlite3_value_dup(pArguments[0])
        pNeedleCopy = sqlite3_value_dup(pArguments[1])
        If pHaystackCopy = 0 OrElse pNeedleCopy = 0 Then
            sqlite3_value_free(pHaystackCopy)
            sqlite3_value_free(pNeedleCopy)
            sqlite3_result_error_nomem(pContext)
            Return
        End If
        pHaystack = sqlite3_value_text(pHaystackCopy)
        pNeedle = sqlite3_value_text(pNeedleCopy)
        haystackLength = sqlite3_value_bytes(pHaystackCopy)
        needleLength = sqlite3_value_bytes(pNeedleCopy)
        isText = -1
    End If

    If haystackLength < 0 OrElse needleLength < 0 OrElse _
       (needleLength > 0 AndAlso pNeedle = 0) OrElse _
       (haystackLength > 0 AndAlso pHaystack = 0) Then
        sqlite3_value_free(pHaystackCopy)
        sqlite3_value_free(pNeedleCopy)
        sqlite3_result_error_nomem(pContext)
        Return
    End If

    Dim matchPosition As SQLITE_C_INT = 0
    If needleLength <= haystackLength Then
        Dim scanOffset As SQLITE_C_INT = 0
        Dim characterPosition As SQLITE_C_INT = 1
        While scanOffset <= haystackLength - needleLength
            Dim matches As SQLITE_C_INT = -1
            For iByte As SQLITE_C_INT = 0 To needleLength - 1
                If pHaystack[scanOffset + iByte] <> pNeedle[iByte] Then
                    matches = 0
                    Exit For
                End If
            Next
            If matches <> 0 Then
                matchPosition = characterPosition
                Exit While
            End If

            scanOffset += 1
            If isText <> 0 Then
                While scanOffset < haystackLength AndAlso _
                      (pHaystack[scanOffset] And &HC0) = &H80
                    scanOffset += 1
                Wend
            End If
            characterPosition += 1
        Wend
    End If

    sqlite3_value_free(pHaystackCopy)
    sqlite3_value_free(pNeedleCopy)
    sqlite3_result_int(pContext, matchPosition)
End Sub

Private Function sqlite3BuiltinHexValue(ByVal byteValue As UByte) As SQLITE_C_INT
    If byteValue >= Asc("0") AndAlso byteValue <= Asc("9") Then _
        Return byteValue - Asc("0")
    If byteValue >= Asc("a") AndAlso byteValue <= Asc("f") Then _
        Return byteValue - Asc("a") + 10
    If byteValue >= Asc("A") AndAlso byteValue <= Asc("F") Then _
        Return byteValue - Asc("A") + 10
    Return -1
End Function

Private Function strContainsChar CDecl Alias "strContainsChar" ( _
    ByVal zText As Const UByte Ptr, _
    ByVal byteCount As SQLITE_C_INT, _
    ByVal wantedCodepoint As u32 _
) As SQLITE_C_INT
    If zText = 0 OrElse byteCount <= 0 Then Return 0
    Dim zCurrent As Const UByte Ptr = zText
    While zCurrent - zText < byteCount
        Dim codepoint As u32 = sqlite3Utf8Read(@zCurrent)
        If codepoint = wantedCodepoint Then Return 1
    Wend
    Return 0
End Function

Private Sub unhexFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse _
       (argumentCount <> 1 AndAlso argumentCount <> 2) Then Return
    Dim zHex As Const UByte Ptr = sqlite3_value_text(pArguments[0])
    If zHex = 0 Then Return
    Dim hexByteCount As SQLITE_C_INT = sqlite3_value_bytes(pArguments[0])
    If hexByteCount < 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If

    Dim zPass As Const UByte Ptr = CPtr(Const UByte Ptr, StrPtr(""))
    Dim passByteCount As SQLITE_C_INT = 0
    If argumentCount = 2 Then
        zPass = sqlite3_value_text(pArguments[1])
        If zPass = 0 Then Return
        passByteCount = sqlite3_value_bytes(pArguments[1])
        If passByteCount < 0 Then
            sqlite3_result_error_nomem(pContext)
            Return
        End If
    End If

    Dim allocationBytes As sqlite3_uint64 = CULngInt(hexByteCount \ 2) + 1
    Dim pResultContext As SqliteResultContext Ptr = _
        CPtr(SqliteResultContext Ptr, pContext)
    If pResultContext->pOut = 0 Then Return
    Dim byteLimit As sqlite3_uint64 = CULngInt(SQLITE_MAX_LENGTH)
    If pResultContext->pOut->db <> 0 Then
        If pResultContext->pOut->db->lengthLimit < 0 Then
            sqlite3_result_error_toobig(pContext)
            Return
        End If
        If byteLimit > CULngInt(pResultContext->pOut->db->lengthLimit) Then _
            byteLimit = CULngInt(pResultContext->pOut->db->lengthLimit)
    End If
    If allocationBytes > byteLimit OrElse _
       allocationBytes > SQLITE_MAX_ALLOCATION_SIZE Then
        sqlite3_result_error_toobig(pContext)
        Return
    End If

    Dim pBlob As UByte Ptr = CPtr(UByte Ptr, sqlite3_malloc64(allocationBytes))
    If pBlob = 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If
    Dim outputLength As SQLITE_C_INT = 0
    Dim pInput As Const UByte Ptr = zHex
    Dim invalidInput As SQLITE_C_INT = 0
    While pInput[0] <> 0
        Dim highNibble As SQLITE_C_INT = sqlite3BuiltinHexValue(pInput[0])
        While highNibble < 0 AndAlso pInput[0] <> 0
            Dim codepoint As u32 = sqlite3Utf8Read(@pInput)
            If strContainsChar( _
                zPass, passByteCount, codepoint) = 0 Then
                invalidInput = -1
                Exit While
            End If
            highNibble = sqlite3BuiltinHexValue(pInput[0])
        Wend
        If invalidInput <> 0 OrElse pInput[0] = 0 Then Exit While
        pInput += 1
        Dim lowNibble As SQLITE_C_INT = sqlite3BuiltinHexValue(pInput[0])
        If lowNibble < 0 Then
            invalidInput = -1
            Exit While
        End If
        pInput += 1
        pBlob[outputLength] = CByte((highNibble Shl 4) Or lowNibble)
        outputLength += 1
    Wend
    If invalidInput <> 0 Then
        sqlite3_free(pBlob)
        Return
    End If
    sqlite3_result_blob64( _
        pContext, pBlob, CULngInt(outputLength), CPtr(Any Ptr, @sqlite3_free))
End Sub

Private Function sqlite3BuiltinBytesMatch( _
    ByVal pLeft As Const UByte Ptr, _
    ByVal pRight As Const UByte Ptr, _
    ByVal byteCount As SQLITE_C_INT _
) As SQLITE_C_INT
    If pLeft = 0 OrElse pRight = 0 OrElse byteCount <= 0 Then Return 0
    For iByte As SQLITE_C_INT = 0 To byteCount - 1
        If pLeft[iByte] <> pRight[iByte] Then Return 0
    Next
    Return -1
End Function

Private Function sqlite3BuiltinUtf8SpanLength( _
    ByVal zText As Const UByte Ptr, _
    ByVal byteCount As SQLITE_C_INT _
) As SQLITE_C_INT
    If zText = 0 OrElse byteCount <= 0 Then Return 0
    Dim spanLength As SQLITE_C_INT = 1
    If zText[0] >= &HC0 Then
        While spanLength < byteCount AndAlso _
              (zText[spanLength] And &HC0) = &H80
            spanLength += 1
        Wend
    End If
    Return spanLength
End Function

Private Function sqlite3BuiltinFindTrimSpan( _
    ByVal pValue As Const UByte Ptr, _
    ByVal valueLength As SQLITE_C_INT, _
    ByVal pTrimSet As Const UByte Ptr, _
    ByVal setLength As SQLITE_C_INT, _
    ByVal atEnd As SQLITE_C_INT _
) As SQLITE_C_INT
    If pValue = 0 OrElse pTrimSet = 0 OrElse valueLength <= 0 OrElse setLength <= 0 Then _
        Return 0
    Dim setOffset As SQLITE_C_INT = 0
    While setOffset < setLength
        Dim characterLength As SQLITE_C_INT = sqlite3BuiltinUtf8SpanLength( _
            @pTrimSet[setOffset], setLength - setOffset)
        If characterLength <= 0 Then Return 0
        If characterLength <= valueLength Then
            Dim pCandidate As Const UByte Ptr = pValue
            If atEnd <> 0 Then _
                pCandidate = @pValue[valueLength - characterLength]
            If sqlite3BuiltinBytesMatch( _
                pCandidate, @pTrimSet[setOffset], characterLength) <> 0 Then _
                Return characterLength
        End If
        setOffset += characterLength
    Wend
    Return 0
End Function

Private Sub trimFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse _
       (argumentCount <> 1 AndAlso argumentCount <> 2) Then Return
    Dim pInput As Const UByte Ptr = sqlite3_value_text(pArguments[0])
    If pInput = 0 Then Return
    Dim inputLength As SQLITE_C_INT = sqlite3_value_bytes(pArguments[0])
    If inputLength < 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If

    Dim pTrimSet As Const UByte Ptr
    Dim setByteCount As SQLITE_C_INT
    If argumentCount = 1 Then
        pTrimSet = CPtr(Const UByte Ptr, StrPtr(" "))
        setByteCount = 1
    Else
        pTrimSet = sqlite3_value_text(pArguments[1])
        If pTrimSet = 0 Then Return
        setByteCount = sqlite3_value_bytes(pArguments[1])
        If setByteCount < 0 Then
            sqlite3_result_error_nomem(pContext)
            Return
        End If
    End If

    Dim setLength As SQLITE_C_INT = 0
    While setLength < setByteCount AndAlso pTrimSet[setLength] <> 0
        setLength += 1
    Wend
    Dim pUserData As Any Ptr = sqlite3_user_data(pContext)
    Dim trimLeft As SQLITE_C_INT = _
        CInt(pUserData = CPtr(Any Ptr, 1) OrElse pUserData = CPtr(Any Ptr, 3))
    Dim trimRight As SQLITE_C_INT = _
        CInt(pUserData = CPtr(Any Ptr, 2) OrElse pUserData = CPtr(Any Ptr, 3))
    Dim startOffset As SQLITE_C_INT = 0
    Dim endOffset As SQLITE_C_INT = inputLength

    If trimLeft <> 0 Then
        While startOffset < endOffset
            Dim matchedLength As SQLITE_C_INT = sqlite3BuiltinFindTrimSpan( _
                @pInput[startOffset], endOffset - startOffset, pTrimSet, setLength, 0)
            If matchedLength = 0 Then Exit While
            startOffset += matchedLength
        Wend
    End If
    If trimRight <> 0 Then
        While endOffset > startOffset
            Dim matchedLength As SQLITE_C_INT = sqlite3BuiltinFindTrimSpan( _
                @pInput[startOffset], endOffset - startOffset, pTrimSet, setLength, -1)
            If matchedLength = 0 Then Exit While
            endOffset -= matchedLength
        Wend
    End If
    sqlite3_result_text( _
        pContext, CPtr(Const ZString Ptr, @pInput[startOffset]), _
        endOffset - startOffset, CPtr(Any Ptr, -1))
End Sub

Private Sub replaceFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 3 Then Return
    Dim pSource As Const UByte Ptr = sqlite3_value_text(pArguments[0])
    If pSource = 0 Then Return
    Dim sourceLength As SQLITE_C_INT = sqlite3_value_bytes(pArguments[0])
    If sourceLength < 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If
    Dim pPattern As Const UByte Ptr = sqlite3_value_text(pArguments[1])
    If pPattern = 0 Then Return
    If pPattern[0] = 0 Then
        sqlite3_result_text(pContext, CPtr(Const ZString Ptr, pSource), _
                            sourceLength, CPtr(Any Ptr, -1))
        Return
    End If
    Dim patternLength As SQLITE_C_INT = sqlite3_value_bytes(pArguments[1])
    If patternLength < 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If
    Dim pReplacement As Const UByte Ptr = sqlite3_value_text(pArguments[2])
    If pReplacement = 0 Then Return
    Dim replacementLength As SQLITE_C_INT = sqlite3_value_bytes(pArguments[2])
    If replacementLength < 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If

    Dim pResultContext As SqliteResultContext Ptr = _
        CPtr(SqliteResultContext Ptr, pContext)
    If pResultContext->pOut = 0 Then Return
    Dim byteLimit As sqlite3_uint64 = CULngInt(SQLITE_MAX_LENGTH)
    If pResultContext->pOut->db <> 0 Then
        If pResultContext->pOut->db->lengthLimit < 0 Then
            sqlite3_result_error_toobig(pContext)
            Return
        End If
        If byteLimit > CULngInt(pResultContext->pOut->db->lengthLimit) Then _
            byteLimit = CULngInt(pResultContext->pOut->db->lengthLimit)
    End If
    If CULngInt(sourceLength) + 1 > byteLimit OrElse _
       CULngInt(sourceLength) + 1 > SQLITE_MAX_ALLOCATION_SIZE Then
        sqlite3_result_error_toobig(pContext)
        Return
    End If

    Dim matchCount As sqlite3_uint64 = 0
    Dim sourceOffset As SQLITE_C_INT = 0
    While sourceOffset <= sourceLength - patternLength
        If pSource[sourceOffset] = pPattern[0] AndAlso _
           sqlite3BuiltinBytesMatch( _
               @pSource[sourceOffset], pPattern, patternLength) <> 0 Then
            matchCount += 1
            sourceOffset += patternLength
        Else
            sourceOffset += 1
        End If
    Wend
    Dim removedBytes As sqlite3_uint64 = _
        matchCount * CULngInt(patternLength)
    Dim outputLength As sqlite3_uint64 = CULngInt(sourceLength) - removedBytes
    If matchCount > 0 Then
        Dim availableGrowth As sqlite3_uint64 = byteLimit - outputLength
        If CULngInt(replacementLength) > availableGrowth \ matchCount Then
            sqlite3_result_error_toobig(pContext)
            Return
        End If
        outputLength += matchCount * CULngInt(replacementLength)
    End If

    Dim pOutput As UByte Ptr = CPtr(UByte Ptr, sqlite3_malloc64(outputLength + 1))
    If pOutput = 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If
    sourceOffset = 0
    Dim outputOffset As SQLITE_C_INT = 0
    While sourceOffset <= sourceLength - patternLength
        If pSource[sourceOffset] = pPattern[0] AndAlso _
           sqlite3BuiltinBytesMatch( _
               @pSource[sourceOffset], pPattern, patternLength) <> 0 Then
            If CULngInt(outputOffset) > outputLength OrElse _
               CULngInt(replacementLength) > _
                   outputLength - CULngInt(outputOffset) Then
                sqlite3_free(pOutput)
                sqlite3_result_error_toobig(pContext)
                Return
            End If
            For iByte As SQLITE_C_INT = 0 To replacementLength - 1
                pOutput[outputOffset + iByte] = pReplacement[iByte]
            Next
            outputOffset += replacementLength
            sourceOffset += patternLength
        Else
            If CULngInt(outputOffset) >= outputLength Then
                sqlite3_free(pOutput)
                sqlite3_result_error_toobig(pContext)
                Return
            End If
            pOutput[outputOffset] = pSource[sourceOffset]
            outputOffset += 1
            sourceOffset += 1
        End If
    Wend
    If CULngInt(outputOffset) > outputLength OrElse _
       CULngInt(sourceLength - sourceOffset) > _
           outputLength - CULngInt(outputOffset) Then
        sqlite3_free(pOutput)
        sqlite3_result_error_toobig(pContext)
        Return
    End If
    While sourceOffset < sourceLength
        pOutput[outputOffset] = pSource[sourceOffset]
        outputOffset += 1
        sourceOffset += 1
    Wend
    pOutput[outputOffset] = 0
    sqlite3_result_text(pContext, CPtr(Const ZString Ptr, pOutput), _
                        outputOffset, CPtr(Any Ptr, @sqlite3_free))
End Sub

Private Sub bytelengthFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 1 Then Return
    Dim valueType As SQLITE_C_INT = sqlite3_value_type(pArguments[0])
    Dim byteCount As SQLITE_C_INT
    Select Case valueType
    Case SQLITE_BLOB
        byteCount = sqlite3_value_bytes(pArguments[0])
        If byteCount < 0 Then
            sqlite3_result_error_nomem(pContext)
        Else
            sqlite3_result_int(pContext, byteCount)
        End If
    Case SQLITE_INTEGER, SQLITE_FLOAT
        byteCount = sqlite3_value_bytes(pArguments[0])
        If byteCount < 0 Then
            sqlite3_result_error_nomem(pContext)
            Return
        End If
        ' This port opens databases as UTF-8 and does not store sqlite3.enc.
        sqlite3_result_int(pContext, byteCount)
    Case SQLITE_TEXT
        If sqlite3_value_encoding(pArguments[0]) <= SQLITE_UTF8 Then
            byteCount = sqlite3_value_bytes(pArguments[0])
        Else
            byteCount = sqlite3_value_bytes16(pArguments[0])
        End If
        If byteCount < 0 Then
            sqlite3_result_error_nomem(pContext)
        Else
            sqlite3_result_int(pContext, byteCount)
        End If
    End Select
End Sub

Private Sub substrFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse _
       (argumentCount <> 2 AndAlso argumentCount <> 3) Then Return
    Dim valueType As SQLITE_C_INT = sqlite3_value_type(pArguments[0])
    Dim startIndex As sqlite3_int64 = sqlite3_value_int64(pArguments[1])
    Dim byteCount As SQLITE_C_INT = 0
    Dim pInput As Const UByte Ptr = 0

    If valueType = SQLITE_BLOB Then
        byteCount = sqlite3_value_bytes(pArguments[0])
        pInput = CPtr(Const UByte Ptr, sqlite3_value_blob(pArguments[0]))
        If pInput = 0 Then Return
    Else
        pInput = sqlite3_value_text(pArguments[0])
        If pInput = 0 Then Return
        If startIndex < 0 Then
            Dim pScan As Const UByte Ptr = pInput
            While pScan[0] <> 0
                sqlite3Utf8Read(@pScan)
                If byteCount = &H7FFFFFFF Then
                    sqlite3_result_error_toobig(pContext)
                    Return
                End If
                byteCount += 1
            Wend
        End If
    End If
    If byteCount < 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If

    Dim characterCount As sqlite3_int64
    If argumentCount = 3 Then
        characterCount = sqlite3_value_int64(pArguments[2])
        If characterCount = 0 AndAlso _
           sqlite3_value_type(pArguments[2]) = SQLITE_NULL Then Return
    Else
        characterCount = &H7FFFFFFFFFFFFFFFLL
    End If
    If startIndex = 0 AndAlso _
       sqlite3_value_type(pArguments[1]) = SQLITE_NULL Then Return

    If startIndex < 0 Then
        startIndex += byteCount
        If startIndex < 0 Then
            If characterCount < 0 Then
                characterCount = 0
            Else
                characterCount += startIndex
            End If
            startIndex = 0
        End If
    ElseIf startIndex > 0 Then
        startIndex -= 1
    ElseIf characterCount > 0 Then
        characterCount -= 1
    End If

    If characterCount < 0 Then
        If characterCount < -startIndex Then
            characterCount = startIndex
        Else
            characterCount = -characterCount
        End If
        startIndex -= characterCount
    End If
    If startIndex < 0 OrElse characterCount < 0 Then Return

    If valueType = SQLITE_BLOB Then
        If startIndex >= byteCount Then
            startIndex = 0
            characterCount = 0
        ElseIf characterCount > byteCount - startIndex Then
            characterCount = byteCount - startIndex
        End If
        sqlite3_result_blob64( _
            pContext, CPtr(Any Ptr, @pInput[startIndex]), _
            CULngInt(characterCount), CPtr(Any Ptr, -1))
    Else
        Dim pStart As Const UByte Ptr = pInput
        For iCharacter As sqlite3_int64 = 0 To startIndex - 1
            If pStart[0] = 0 Then Exit For
            sqlite3Utf8Read(@pStart)
        Next
        Dim pEnd As Const UByte Ptr = pStart
        For iCharacter As sqlite3_int64 = 0 To characterCount - 1
            If pEnd[0] = 0 Then Exit For
            sqlite3Utf8Read(@pEnd)
        Next
        Dim outputLength As SQLITE_C_INT = CInt(pEnd - pStart)
        sqlite3_result_text( _
            pContext, CPtr(Const ZString Ptr, pStart), outputLength, _
            CPtr(Any Ptr, -1))
    End If
End Sub

Private Sub unicodeFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 1 Then Return
    Dim zText As Const UByte Ptr = sqlite3_value_text(pArguments[0])
    If zText = 0 OrElse zText[0] = 0 Then Return
    Dim zCurrent As Const UByte Ptr = zText
    sqlite3_result_int(pContext, CInt(sqlite3Utf8Read(@zCurrent)))
End Sub

Private Sub charFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse argumentCount < 0 OrElse _
       (argumentCount > 0 AndAlso pArguments = 0) Then Return
    If argumentCount > (SQLITE_MAX_ALLOCATION_SIZE - 1) \ 4 Then
        sqlite3_result_error_toobig(pContext)
        Return
    End If
    Dim outputCapacity As sqlite3_uint64 = _
        CULngInt(argumentCount) * 4 + 1
    Dim pOutput As UByte Ptr = CPtr(UByte Ptr, sqlite3_malloc64(outputCapacity))
    If pOutput = 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If

    Dim outputLength As SQLITE_C_INT = 0
    For iArgument As SQLITE_C_INT = 0 To argumentCount - 1
        Dim codepoint As sqlite3_int64 = sqlite3_value_int64(pArguments[iArgument])
        If codepoint < 0 OrElse codepoint > &H10FFFF Then codepoint = &HFFFD
        outputLength += sqlite3AppendOneUtf8Character( _
            @pOutput[outputLength], CULngInt(codepoint))
    Next
    pOutput[outputLength] = 0
    sqlite3_result_text(pContext, CPtr(Const ZString Ptr, pOutput), _
                        outputLength, CPtr(Any Ptr, @sqlite3_free))
End Sub

Private Sub randomFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse argumentCount <> 0 Then Return
    Dim value As sqlite3_int64 = 0
    sqlite3_randomness(SizeOf(value), @value)
    If value < 0 Then value = -(value And &H7FFFFFFFFFFFFFFFLL)
    sqlite3_result_int64(pContext, value)
End Sub

Private Sub randomBlob CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 1 Then Return
    Dim byteCount As sqlite3_int64 = sqlite3_value_int64(pArguments[0])
    If byteCount < 1 Then byteCount = 1
    Dim pResultContext As SqliteResultContext Ptr = _
        CPtr(SqliteResultContext Ptr, pContext)
    If pResultContext->pOut = 0 OrElse pResultContext->pOut->db = 0 Then Return
    If byteCount > SQLITE_MAX_LENGTH OrElse _
       byteCount > pResultContext->pOut->db->lengthLimit Then
        sqlite3_result_error_toobig(pContext)
        Return
    End If

    Dim pResult As UByte Ptr = CPtr(UByte Ptr, _
        sqlite3_malloc64(CULngInt(byteCount)))
    If pResult = 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If
    sqlite3_randomness(CInt(byteCount), pResult)
    sqlite3_result_blob64(pContext, pResult, CULngInt(byteCount), _
                          CPtr(Any Ptr, @sqlite3_free))
End Sub

Private Sub zeroblobFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 1 Then Return
    Dim byteCount As sqlite3_int64 = sqlite3_value_int64(pArguments[0])
    If byteCount < 0 Then byteCount = 0
    sqlite3_result_zeroblob64(pContext, CULngInt(byteCount))
End Sub

Private Function sqlite3BuiltinConcatAddBytes( _
    ByRef totalBytes As sqlite3_uint64, _
    ByVal byteCount As SQLITE_C_INT, _
    ByVal byteLimit As sqlite3_uint64 _
) As SQLITE_C_INT
    If byteCount < 0 Then Return SQLITE_NOMEM
    Dim addedBytes As sqlite3_uint64 = CULngInt(byteCount)
    If addedBytes > byteLimit OrElse totalBytes > byteLimit - addedBytes Then _
        Return SQLITE_TOOBIG
    totalBytes += addedBytes
    Return SQLITE_OK
End Function

Private Sub concatFuncCore CDecl Alias "concatFuncCore" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr, _
    ByVal separatorLength As SQLITE_C_INT, _
    ByVal pSeparator As Const UByte Ptr _
)
    If pContext = 0 OrElse argumentCount < 0 OrElse _
       (argumentCount > 0 AndAlso pArguments = 0) OrElse separatorLength < 0 Then Return

    Dim pResultContext As SqliteResultContext Ptr = _
        CPtr(SqliteResultContext Ptr, pContext)
    If pResultContext->pOut = 0 Then Return
    Dim byteLimit As sqlite3_uint64 = CULngInt(SQLITE_MAX_LENGTH)
    If pResultContext->pOut->db <> 0 Then
        If pResultContext->pOut->db->lengthLimit < 0 Then
            sqlite3_result_error_toobig(pContext)
            Return
        End If
        If byteLimit > CULngInt(pResultContext->pOut->db->lengthLimit) Then _
            byteLimit = CULngInt(pResultContext->pOut->db->lengthLimit)
    End If

    Dim outputLength As sqlite3_uint64 = 0
    Dim nonNullCount As SQLITE_C_INT = 0
    For iArgument As SQLITE_C_INT = 0 To argumentCount - 1
        If sqlite3_value_type(pArguments[iArgument]) <> SQLITE_NULL Then
            Dim byteCount As SQLITE_C_INT = sqlite3_value_bytes(pArguments[iArgument])
            Dim rc As SQLITE_C_INT = sqlite3BuiltinConcatAddBytes( _
                outputLength, byteCount, byteLimit)
            If rc = SQLITE_TOOBIG Then
                sqlite3_result_error_toobig(pContext)
                Return
            ElseIf rc <> SQLITE_OK Then
                sqlite3_result_error_nomem(pContext)
                Return
            End If
            If nonNullCount > 0 AndAlso separatorLength > 0 Then
                rc = sqlite3BuiltinConcatAddBytes( _
                    outputLength, separatorLength, byteLimit)
                If rc <> SQLITE_OK Then
                    If rc = SQLITE_TOOBIG Then
                        sqlite3_result_error_toobig(pContext)
                    Else
                        sqlite3_result_error_nomem(pContext)
                    End If
                    Return
                End If
            End If
            nonNullCount += 1
        End If
    Next

    Dim pOutput As UByte Ptr = CPtr(UByte Ptr, _
        sqlite3_malloc64(outputLength + 1))
    If pOutput = 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If
    Dim outputPosition As SQLITE_C_INT = 0
    nonNullCount = 0
    For iArgument As SQLITE_C_INT = 0 To argumentCount - 1
        Dim pValue As SqliteVdbeMem Ptr = pArguments[iArgument]
        If sqlite3_value_type(pValue) <> SQLITE_NULL Then
            Dim byteCount As SQLITE_C_INT = sqlite3_value_bytes(pValue)
            Dim zValue As Const UByte Ptr = sqlite3_value_text(pValue)
            If byteCount < 0 Then
                sqlite3_free(pOutput)
                sqlite3_result_error_nomem(pContext)
                Return
            End If
            If zValue = 0 Then Continue For
            If nonNullCount > 0 AndAlso separatorLength > 0 Then
                If pSeparator = 0 OrElse _
                   CULngInt(outputPosition) > outputLength OrElse _
                   CULngInt(separatorLength) > outputLength - CULngInt(outputPosition) Then
                    sqlite3_free(pOutput)
                    sqlite3_result_error_toobig(pContext)
                    Return
                End If
                For iByte As SQLITE_C_INT = 0 To separatorLength - 1
                    pOutput[outputPosition + iByte] = pSeparator[iByte]
                Next
                outputPosition += separatorLength
            End If
            If CULngInt(outputPosition) > outputLength OrElse _
               CULngInt(byteCount) > outputLength - CULngInt(outputPosition) Then
                sqlite3_free(pOutput)
                sqlite3_result_error_toobig(pContext)
                Return
            End If
            For iByte As SQLITE_C_INT = 0 To byteCount - 1
                pOutput[outputPosition + iByte] = zValue[iByte]
            Next
            outputPosition += byteCount
            nonNullCount += 1
        End If
    Next
    pOutput[outputPosition] = 0
    sqlite3_result_text(pContext, CPtr(Const ZString Ptr, pOutput), _
                        outputPosition, CPtr(Any Ptr, @sqlite3_free))
End Sub

Private Sub concatFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    concatFuncCore(pContext, argumentCount, pArguments, 0, 0)
End Sub

Private Sub concatwsFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount < 2 Then Return
    If sqlite3_value_type(pArguments[0]) = SQLITE_NULL Then Return
    Dim separatorLength As SQLITE_C_INT = sqlite3_value_bytes(pArguments[0])
    Dim zSeparator As Const UByte Ptr = sqlite3_value_text(pArguments[0])
    If separatorLength < 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If
    If zSeparator = 0 Then Return
    concatFuncCore( _
        pContext, argumentCount - 1, @pArguments[1], _
        separatorLength, zSeparator)
End Sub

#ifdef SQLITE_ENABLE_UNKNOWN_SQL_FUNCTION
Private Sub unknownFunc CDecl Alias "unknownFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    ' EXPLAIN-only fallback: preserving a NULL result lets bytecode inspection proceed.
End Sub
#endif

#if defined(SQLITE_DEBUG) OrElse defined(SQLITE_BUILTIN_OOM_FUNCTION)
Private Sub oomFunc CDecl Alias "oomFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 Then Return
    Dim pDatabase As sqlite3 Ptr = CPtr(sqlite3 Ptr, _
        sqlite3_context_db_handle(pContext))
    sqlite3OomFault(pDatabase)
End Sub
#endif

Sub sqlite3QuoteValue CDecl Alias "sqlite3QuoteValue" ( _
    ByVal pAccumulator As sqlite3_str Ptr, _
    ByVal pValueArgument As Any Ptr, _
    ByVal escapeControls As SQLITE_C_INT _
) Export
    If pAccumulator = 0 OrElse pValueArgument = 0 Then Return
    Dim pValue As SqliteVdbeMem Ptr = _
        CPtr(SqliteVdbeMem Ptr, pValueArgument)
    Select Case sqlite3_value_type(pValue)
    Case SQLITE_FLOAT
        sqlite3_str_appendf( _
            pAccumulator, StrPtr("%!0.17g"), sqlite3_value_double(pValue))
    Case SQLITE_INTEGER
        sqlite3_str_appendf( _
            pAccumulator, StrPtr("%lld"), sqlite3_value_int64(pValue))
    Case SQLITE_BLOB
        Dim byteCount As SQLITE_C_INT = sqlite3_value_bytes(pValue)
        Dim pBlob As Const UByte Ptr = _
            CPtr(Const UByte Ptr, sqlite3_value_blob(pValue))
        If byteCount < 0 OrElse (byteCount > 0 AndAlso pBlob = 0) Then
            sqlite3StrAccumSetError(pAccumulator, SQLITE_NOMEM)
            Return
        End If
        sqlite3_str_append(pAccumulator, StrPtr("X'"), 2)
        Dim zHex As Const UByte Ptr = _
            CPtr(Const UByte Ptr, StrPtr("0123456789ABCDEF"))
        Dim hexPair(0 To 1) As UByte
        For iByte As SQLITE_C_INT = 0 To byteCount - 1
            hexPair(0) = zHex[pBlob[iByte] Shr 4]
            hexPair(1) = zHex[pBlob[iByte] And &H0F]
            sqlite3_str_append( _
                pAccumulator, CPtr(Const ZString Ptr, @hexPair(0)), 2)
        Next
        sqlite3_str_append(pAccumulator, StrPtr("'"), 1)
    Case SQLITE_TEXT
        Dim zText As Const UByte Ptr = sqlite3_value_text(pValue)
        If zText = 0 Then
            sqlite3StrAccumSetError(pAccumulator, SQLITE_NOMEM)
            Return
        End If
        If escapeControls <> 0 Then
            sqlite3_str_appendf( _
                pAccumulator, StrPtr("%#Q"), CPtr(Const ZString Ptr, zText))
        Else
            sqlite3_str_appendf( _
                pAccumulator, StrPtr("%Q"), CPtr(Const ZString Ptr, zText))
        End If
    Case Else
        sqlite3_str_append(pAccumulator, StrPtr("NULL"), 4)
    End Select
End Sub

Private Function isNHex( _
    ByVal zHex As Const UByte Ptr, _
    ByVal digitCount As SQLITE_C_INT, _
    ByRef value As u32 _
) As SQLITE_C_INT
    If zHex = 0 OrElse digitCount <= 0 Then Return 0
    value = 0
    For iDigit As SQLITE_C_INT = 0 To digitCount - 1
        Dim digitValue As SQLITE_C_INT = sqlite3BuiltinHexValue(zHex[iDigit])
        If digitValue < 0 Then Return 0
        value = (value Shl 4) Or CUlng(digitValue)
    Next
    Return -1
End Function

Private Sub unistrFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 1 Then Return
    Dim zInput As Const UByte Ptr = sqlite3_value_text(pArguments[0])
    If zInput = 0 Then Return
    Dim inputLength As SQLITE_C_INT = sqlite3_value_bytes(pArguments[0])
    If inputLength < 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If
    Dim pOutput As UByte Ptr = CPtr(UByte Ptr, _
        sqlite3_malloc64(CULngInt(inputLength) + 1))
    If pOutput = 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If

    Dim inputOffset As SQLITE_C_INT = 0
    Dim outputLength As SQLITE_C_INT = 0
    While inputOffset < inputLength
        Dim slashOffset As SQLITE_C_INT = inputOffset
        While slashOffset < inputLength AndAlso _
              zInput[slashOffset] <> 0 AndAlso zInput[slashOffset] <> Asc("\")
            slashOffset += 1
        Wend
        If slashOffset >= inputLength OrElse zInput[slashOffset] = 0 Then
            For iByte As SQLITE_C_INT = inputOffset To inputLength - 1
                pOutput[outputLength] = zInput[iByte]
                outputLength += 1
            Next
            Exit While
        End If

        For iByte As SQLITE_C_INT = inputOffset To slashOffset - 1
            pOutput[outputLength] = zInput[iByte]
            outputLength += 1
        Next
        inputOffset = slashOffset
        Dim escapeCode As UByte = 0
        If inputOffset + 1 < inputLength Then escapeCode = zInput[inputOffset + 1]
        Dim codepoint As u32 = 0
        Dim digitOffset As SQLITE_C_INT
        Dim digitCount As SQLITE_C_INT
        Dim escapeLength As SQLITE_C_INT
        If escapeCode = Asc("\") Then
            pOutput[outputLength] = Asc("\")
            outputLength += 1
            inputOffset += 2
            Continue While
        ElseIf sqlite3BuiltinHexValue(escapeCode) >= 0 Then
            digitOffset = inputOffset + 1
            digitCount = 4
            escapeLength = 5
        ElseIf escapeCode = Asc("+") Then
            digitOffset = inputOffset + 2
            digitCount = 6
            escapeLength = 8
        ElseIf escapeCode = Asc("u") Then
            digitOffset = inputOffset + 2
            digitCount = 4
            escapeLength = 6
        ElseIf escapeCode = Asc("U") Then
            digitOffset = inputOffset + 2
            digitCount = 8
            escapeLength = 10
        Else
            sqlite3_free(pOutput)
            sqlite3_result_error(pContext, StrPtr("invalid Unicode escape"), -1)
            Return
        End If
        If inputOffset > inputLength - escapeLength OrElse _
           isNHex(@zInput[digitOffset], digitCount, codepoint) = 0 Then
            sqlite3_free(pOutput)
            sqlite3_result_error(pContext, StrPtr("invalid Unicode escape"), -1)
            Return
        End If
        outputLength += sqlite3AppendOneUtf8Character( _
            @pOutput[outputLength], codepoint)
        inputOffset += escapeLength
    Wend
    pOutput[outputLength] = 0
    sqlite3_result_text(pContext, CPtr(Const ZString Ptr, pOutput), _
                        outputLength, CPtr(Any Ptr, @sqlite3_free))
End Sub

Private Sub typeofFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 1 Then Return
    Dim zType As Const ZString Ptr
    Select Case sqlite3_value_type(pArguments[0])
    Case SQLITE_INTEGER
        zType = StrPtr("integer")
    Case SQLITE_FLOAT
        zType = StrPtr("real")
    Case SQLITE_TEXT
        zType = StrPtr("text")
    Case SQLITE_BLOB
        zType = StrPtr("blob")
    Case SQLITE_NULL
        zType = StrPtr("null")
    Case Else
        Return
    End Select
    sqlite3_result_text(pContext, zType, -1, 0)
End Sub

Private Sub subtypeFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 1 Then Return
    sqlite3_result_int(pContext, CInt(sqlite3_value_subtype(pArguments[0])))
End Sub

#ifndef SQLITE_OMIT_COMPILEOPTION_DIAGS
Private Sub compileoptionusedFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 1 Then Return
    Dim zOptionName As Const UByte Ptr = sqlite3_value_text(pArguments[0])
    If zOptionName = 0 Then Return
    sqlite3_result_int(pContext, _
        sqlite3_compileoption_used(CPtr(Const ZString Ptr, zOptionName)))
End Sub

Private Sub compileoptiongetFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 1 Then Return
    Dim optionIndex As SQLITE_C_INT = sqlite3_value_int(pArguments[0])
    sqlite3_result_text(pContext, sqlite3_compileoption_get(optionIndex), -1, 0)
End Sub
#endif

Private Sub versionFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse argumentCount <> 0 Then Return
    sqlite3_result_text(pContext, sqlite3_libversion(), -1, 0)
End Sub

Private Sub sourceidFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse argumentCount <> 0 Then Return
    sqlite3_result_text(pContext, sqlite3_sourceid(), -1, 0)
End Sub

Private Sub nullifFunc CDecl Alias "nullifFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 2 Then Return
    Dim pCollation As sqlite3CollSeq Ptr = sqlite3GetFuncCollSeq(pContext)
    If sqlite3MemCompare(pArguments[0], pArguments[1], pCollation) <> 0 Then _
        sqlite3_result_value(pContext, pArguments[0])
End Sub

Private Sub errlogFunc CDecl Alias "errlogFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pArguments = 0 OrElse argumentCount < 2 Then Return
    sqlite3_log(sqlite3_value_int(pArguments[0]), StrPtr("%s"), _
                sqlite3_value_text(pArguments[1]))
End Sub

Private Sub last_insert_rowid CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse argumentCount <> 0 Then Return
    Dim pResultContext As SqliteResultContext Ptr = _
        CPtr(SqliteResultContext Ptr, pContext)
    If pResultContext->pOut = 0 OrElse pResultContext->pOut->db = 0 Then Return
    sqlite3_result_int64( _
        pContext, sqlite3_last_insert_rowid(pResultContext->pOut->db))
End Sub

Private Sub changes CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse argumentCount <> 0 Then Return
    Dim pResultContext As SqliteResultContext Ptr = _
        CPtr(SqliteResultContext Ptr, pContext)
    If pResultContext->pOut = 0 OrElse pResultContext->pOut->db = 0 Then Return
    sqlite3_result_int64(pContext, sqlite3_changes64(pResultContext->pOut->db))
End Sub

Private Sub total_changes CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse argumentCount <> 0 Then Return
    Dim pResultContext As SqliteResultContext Ptr = _
        CPtr(SqliteResultContext Ptr, pContext)
    If pResultContext->pOut = 0 OrElse pResultContext->pOut->db = 0 Then Return
    sqlite3_result_int64( _
        pContext, sqlite3_total_changes64(pResultContext->pOut->db))
End Sub

Private Sub kahanBabuskaNeumaierStep( _
    ByVal pSum As SqliteSumContext Ptr, _
    ByVal value As Double _
)
    If pSum = 0 Then Return
    Dim currentSum As Double = pSum->rSum
    Dim nextSum As Double = currentSum + value
    If Abs(currentSum) > Abs(value) Then
        pSum->rErr += (currentSum - nextSum) + value
    Else
        pSum->rErr += (value - nextSum) + currentSum
    End If
    pSum->rSum = nextSum
End Sub

Private Sub kahanBabuskaNeumaierStepInt64( _
    ByVal pSum As SqliteSumContext Ptr, _
    ByVal value As sqlite3_int64 _
)
    If pSum = 0 Then Return
    ' At 2^52 a binary64 no longer represents every integer exactly. Split
    ' off 14 low bits so the correction term retains those bits.
    If value <= -4503599627370496LL OrElse _
       value >= 4503599627370496LL Then
        Dim smallPart As sqlite3_int64 = value Mod 16384
        Dim largePart As sqlite3_int64 = value - smallPart
        kahanBabuskaNeumaierStep(pSum, CDbl(largePart))
        kahanBabuskaNeumaierStep(pSum, CDbl(smallPart))
    Else
        kahanBabuskaNeumaierStep(pSum, CDbl(value))
    End If
End Sub

Private Sub kahanBabuskaNeumaierInit( _
    ByVal pSum As SqliteSumContext Ptr, _
    ByVal value As sqlite3_int64 _
)
    If pSum = 0 Then Return
    If value <= -4503599627370496LL OrElse _
       value >= 4503599627370496LL Then
        Dim smallPart As sqlite3_int64 = value Mod 16384
        pSum->rSum = CDbl(value - smallPart)
        pSum->rErr = CDbl(smallPart)
    Else
        pSum->rSum = CDbl(value)
        pSum->rErr = 0.0
    End If
End Sub

Private Sub sumStep CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse argumentCount <> 1 OrElse pArguments = 0 Then Return
    Dim pSum As SqliteSumContext Ptr = CPtr(SqliteSumContext Ptr, _
        sqlite3_aggregate_context(pContext, SizeOf(SqliteSumContext)))
    If pSum = 0 Then Return
    Dim valueType As SQLITE_C_INT = sqlite3_value_numeric_type(pArguments[0])
    If valueType = SQLITE_NULL Then Return
    If pSum->cnt = 9223372036854775807LL Then
        sqlite3_result_error_toobig(pContext)
        Return
    End If
    pSum->cnt += 1

    Dim integerValue As sqlite3_int64 = sqlite3_value_int64(pArguments[0])
    If pSum->approx = 0 Then
        If valueType <> SQLITE_INTEGER Then
            kahanBabuskaNeumaierInit(pSum, pSum->iSum)
            pSum->approx = 1
            kahanBabuskaNeumaierStep( _
                pSum, sqlite3_value_double(pArguments[0]))
        Else
            Dim newSum As sqlite3_int64 = pSum->iSum
            If sqlite3AddInt64(@newSum, integerValue) = 0 Then
                pSum->iSum = newSum
            Else
                pSum->ovrfl = 1
                kahanBabuskaNeumaierInit(pSum, pSum->iSum)
                pSum->approx = 1
                kahanBabuskaNeumaierStepInt64(pSum, integerValue)
            End If
        End If
    ElseIf valueType = SQLITE_INTEGER Then
        kahanBabuskaNeumaierStepInt64(pSum, integerValue)
    Else
        pSum->ovrfl = 0
        kahanBabuskaNeumaierStep(pSum, sqlite3_value_double(pArguments[0]))
    End If
End Sub

Private Sub sumInverse CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse argumentCount <> 1 OrElse pArguments = 0 Then Return
    Dim pSum As SqliteSumContext Ptr = CPtr(SqliteSumContext Ptr, _
        sqlite3_aggregate_context(pContext, SizeOf(SqliteSumContext)))
    If pSum = 0 OrElse pSum->cnt <= 0 Then Return

    Dim valueType As SQLITE_C_INT = sqlite3_value_numeric_type(pArguments[0])
    If valueType = SQLITE_NULL Then Return
    pSum->cnt -= 1

    If pSum->approx = 0 Then
        Dim integerSum As sqlite3_int64 = pSum->iSum
        If sqlite3SubInt64(@integerSum, sqlite3_value_int64(pArguments[0])) = 0 Then
            pSum->iSum = integerSum
            Return
        End If
        pSum->ovrfl = 1
        pSum->approx = 1
        kahanBabuskaNeumaierInit(pSum, pSum->iSum)
    End If

    If valueType = SQLITE_INTEGER Then
        Dim integerValue As sqlite3_int64 = sqlite3_value_int64(pArguments[0])
        If integerValue <> (-9223372036854775807LL - 1) Then
            kahanBabuskaNeumaierStepInt64(pSum, -integerValue)
        Else
            ' Negating INT64_MIN would overflow, so subtract it as two pieces.
            kahanBabuskaNeumaierStepInt64(pSum, 9223372036854775807LL)
            kahanBabuskaNeumaierStepInt64(pSum, 1)
        End If
    Else
        kahanBabuskaNeumaierStep(pSum, -sqlite3_value_double(pArguments[0]))
    End If
End Sub

Private Sub sumFinalize CDecl (ByVal pContext As Any Ptr)
    If pContext = 0 Then Return
    Dim pSum As SqliteSumContext Ptr = CPtr(SqliteSumContext Ptr, _
        sqlite3_aggregate_context(pContext, 0))
    If pSum = 0 OrElse pSum->cnt <= 0 Then Return
    If pSum->approx = 0 Then
        sqlite3_result_int64(pContext, pSum->iSum)
    ElseIf pSum->ovrfl <> 0 Then
        sqlite3_result_error(pContext, StrPtr("integer overflow"), -1)
    ElseIf sqlite3IsOverflow(pSum->rErr) = 0 Then
        sqlite3_result_double(pContext, pSum->rSum + pSum->rErr)
    Else
        sqlite3_result_double(pContext, pSum->rSum)
    End If
End Sub

Private Sub avgFinalize CDecl (ByVal pContext As Any Ptr)
    If pContext = 0 Then Return
    Dim pSum As SqliteSumContext Ptr = CPtr(SqliteSumContext Ptr, _
        sqlite3_aggregate_context(pContext, 0))
    If pSum = 0 OrElse pSum->cnt <= 0 Then Return
    Dim value As Double
    If pSum->approx = 0 Then
        value = CDbl(pSum->iSum)
    ElseIf sqlite3IsOverflow(pSum->rErr) = 0 Then
        value = pSum->rSum + pSum->rErr
    Else
        value = pSum->rSum
    End If
    sqlite3_result_double(pContext, value / CDbl(pSum->cnt))
End Sub

Private Sub totalFinalize CDecl (ByVal pContext As Any Ptr)
    If pContext = 0 Then Return
    Dim pSum As SqliteSumContext Ptr = CPtr(SqliteSumContext Ptr, _
        sqlite3_aggregate_context(pContext, 0))
    Dim value As Double = 0.0
    If pSum <> 0 Then
        If pSum->approx = 0 Then
            value = CDbl(pSum->iSum)
        ElseIf sqlite3IsOverflow(pSum->rErr) = 0 Then
            value = pSum->rSum + pSum->rErr
        Else
            value = pSum->rSum
        End If
    End If
    sqlite3_result_double(pContext, value)
End Sub

Private Sub minmaxStep CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 1 Then Return
    Dim pBest As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, _
        sqlite3_aggregate_context(pContext, SizeOf(SqliteVdbeMem)))
    If pBest = 0 Then Return
    Dim pResultContext As SqliteResultContext Ptr = _
        CPtr(SqliteResultContext Ptr, pContext)
    If pResultContext->pOut = 0 Then Return
    Dim pCandidate As SqliteVdbeMem Ptr = pArguments[0]
    If sqlite3_value_type(pCandidate) = SQLITE_NULL Then
        If pBest->flags <> 0 Then sqlite3SkipAccumulatorLoad(pContext)
        Return
    End If

    If pBest->flags <> 0 Then
        Dim comparison As SQLITE_C_INT = sqlite3MemCompare(pBest, pCandidate, 0)
        Dim wantMaximum As SQLITE_C_INT = _
            CInt(sqlite3_user_data(pContext) <> 0)
        If (wantMaximum <> 0 AndAlso comparison < 0) OrElse _
           (wantMaximum = 0 AndAlso comparison > 0) Then
            If sqlite3VdbeMemCopy(pBest, pCandidate) <> SQLITE_OK Then _
                sqlite3_result_error_nomem(pContext)
        Else
            ' Keep bare result columns from the first row when min/max does
            ' not replace its accumulator value.
            sqlite3SkipAccumulatorLoad(pContext)
        End If
    Else
        pBest->db = pResultContext->pOut->db
        If sqlite3VdbeMemCopy(pBest, pCandidate) <> SQLITE_OK Then _
            sqlite3_result_error_nomem(pContext)
    End If
End Sub

Private Sub minMaxValueFinalize( _
    ByVal pContext As Any Ptr, _
    ByVal releaseContext As SQLITE_C_INT _
)
    If pContext = 0 Then Return
    Dim pBest As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, _
        sqlite3_aggregate_context(pContext, 0))
    If pBest = 0 Then Return
    If pBest->flags <> 0 Then sqlite3_result_value(pContext, pBest)
    If releaseContext = 0 Then sqlite3VdbeMemRelease(pBest)
End Sub

Private Sub minMaxFinalize CDecl (ByVal pContext As Any Ptr)
    minMaxValueFinalize(pContext, 0)
End Sub

Private Sub minMaxValue CDecl (ByVal pContext As Any Ptr)
    minMaxValueFinalize(pContext, 1)
End Sub

Private Sub minmaxFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount < 2 Then Return
    Dim bestIndex As SQLITE_C_INT = 0
    If sqlite3_value_type(pArguments[0]) = SQLITE_NULL Then Return
    Dim wantMaximum As SQLITE_C_INT = _
        CInt(sqlite3_user_data(pContext) <> 0)
    Dim pCollation As sqlite3CollSeq Ptr = sqlite3GetFuncCollSeq(pContext)
    For iArgument As SQLITE_C_INT = 1 To argumentCount - 1
        If sqlite3_value_type(pArguments[iArgument]) = SQLITE_NULL Then Return
        Dim comparison As SQLITE_C_INT = _
            sqlite3MemCompare( _
                pArguments[bestIndex], pArguments[iArgument], pCollation)
        If (wantMaximum <> 0 AndAlso comparison <= 0) OrElse _
           (wantMaximum = 0 AndAlso comparison >= 0) Then bestIndex = iArgument
    Next
    sqlite3_result_value(pContext, pArguments[bestIndex])
End Sub

Private Sub countStep CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse (argumentCount <> 0 AndAlso argumentCount <> 1) OrElse _
       (argumentCount = 1 AndAlso pArguments = 0) Then Return
    Dim pCount As sqlite3_int64 Ptr = CPtr(sqlite3_int64 Ptr, _
        sqlite3_aggregate_context(pContext, SizeOf(sqlite3_int64)))
    If pCount = 0 Then Return
    If argumentCount = 0 OrElse _
       sqlite3_value_type(pArguments[0]) <> SQLITE_NULL Then
        If pCount[0] = &H7FFFFFFFFFFFFFFFLL Then
            sqlite3_result_error_toobig(pContext)
        Else
            pCount[0] += 1
        End If
    End If
End Sub

Private Sub countFinalize CDecl (ByVal pContext As Any Ptr)
    If pContext = 0 Then Return
    Dim pCount As sqlite3_int64 Ptr = CPtr(sqlite3_int64 Ptr, _
        sqlite3_aggregate_context(pContext, 0))
    If pCount = 0 Then
        sqlite3_result_int64(pContext, 0)
    Else
        sqlite3_result_int64(pContext, pCount[0])
    End If
End Sub

Private Sub countInverse CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse (argumentCount <> 0 AndAlso argumentCount <> 1) Then Return
    If argumentCount = 1 AndAlso pArguments = 0 Then Return
    If argumentCount = 1 AndAlso _
       sqlite3_value_type(pArguments[0]) = SQLITE_NULL Then Return

    Dim pCount As sqlite3_int64 Ptr = CPtr(sqlite3_int64 Ptr, _
        sqlite3_aggregate_context(pContext, SizeOf(sqlite3_int64)))
    If pCount = 0 OrElse pCount[0] <= 0 Then Return
    pCount[0] -= 1
End Sub

Private Sub groupConcatStep CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse _
       (argumentCount <> 1 AndAlso argumentCount <> 2) Then Return
    If sqlite3_value_type(pArguments[0]) = SQLITE_NULL Then Return
    Dim pGroup As SqliteGroupConcatContext Ptr = _
        CPtr(SqliteGroupConcatContext Ptr, _
            sqlite3_aggregate_context(pContext, SizeOf(SqliteGroupConcatContext)))
    If pGroup = 0 Then Return
    Dim pResultContext As SqliteResultContext Ptr = _
        CPtr(SqliteResultContext Ptr, pContext)
    If pResultContext->pOut = 0 OrElse pResultContext->pOut->db = 0 Then Return
    Dim firstTerm As SQLITE_C_INT = CInt(pGroup->accumulator.mxAlloc = 0)
    Dim pSeparator As Const UByte Ptr = 0
    Dim separatorLength As SQLITE_C_INT = 0
    If argumentCount = 1 Then
        If firstTerm = 0 Then
            pSeparator = CPtr(Const UByte Ptr, StrPtr(","))
            separatorLength = 1
        End If
    ElseIf firstTerm = 0 Then
        pSeparator = sqlite3_value_text(pArguments[1])
        separatorLength = sqlite3_value_bytes(pArguments[1])
        If separatorLength < 0 Then
            sqlite3StrAccumSetError(@pGroup->accumulator, SQLITE_NOMEM)
            Return
        End If
    End If

    If firstTerm <> 0 Then
        pGroup->accumulator.db = pResultContext->pOut->db
        pGroup->accumulator.mxAlloc = _
            CULngInt(pResultContext->pOut->db->lengthLimit)
        pGroup->firstSeparatorLength = _
            IIf(argumentCount = 1, 1, sqlite3_value_bytes(pArguments[1]))
    Else
        If pGroup->separatorLengths <> 0 OrElse _
           separatorLength <> pGroup->firstSeparatorLength Then
            If pGroup->termCount >= _
               (SQLITE_MAX_ALLOCATION_SIZE \ SizeOf(SQLITE_C_INT)) - 1 Then
                sqlite3StrAccumSetError(@pGroup->accumulator, SQLITE_TOOBIG)
                Return
            End If
            Dim allocationCount As ULongInt = CULngInt(pGroup->termCount)
            Dim pNewLengths As SQLITE_C_INT Ptr
            If pGroup->separatorLengths = 0 Then
                allocationCount += 1
                pNewLengths = CPtr(SQLITE_C_INT Ptr, sqlite3_malloc64( _
                    allocationCount * SizeOf(SQLITE_C_INT)))
                If pNewLengths <> 0 Then
                    For iLength As Long = 0 To CLng(pGroup->termCount) - 2
                        pNewLengths[iLength] = pGroup->firstSeparatorLength
                    Next
                End If
            Else
                pNewLengths = CPtr(SQLITE_C_INT Ptr, sqlite3_realloc64( _
                    pGroup->separatorLengths, _
                    allocationCount * SizeOf(SQLITE_C_INT)))
            End If
            If pNewLengths = 0 Then
                sqlite3StrAccumSetError(@pGroup->accumulator, SQLITE_NOMEM)
                Return
            End If
            If pGroup->termCount > 0 Then _
                pNewLengths[CLng(pGroup->termCount) - 1] = separatorLength
            pGroup->separatorLengths = pNewLengths
        End If
    End If
    If pSeparator <> 0 AndAlso separatorLength > 0 Then _
        sqlite3_str_append( _
            @pGroup->accumulator, _
            CPtr(Const ZString Ptr, pSeparator), separatorLength)
    If pGroup->termCount < 9223372036854775807LL Then _
        pGroup->termCount += 1

    Dim pValue As Const UByte Ptr = sqlite3_value_text(pArguments[0])
    If pValue <> 0 Then
        Dim valueLength As SQLITE_C_INT = sqlite3_value_bytes(pArguments[0])
        If valueLength < 0 Then
            sqlite3StrAccumSetError(@pGroup->accumulator, SQLITE_NOMEM)
        ElseIf valueLength > 0 Then
            sqlite3_str_append( _
                @pGroup->accumulator, CPtr(Const ZString Ptr, pValue), valueLength)
        End If
    End If
End Sub

Private Sub groupConcatInverse CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse (argumentCount <> 1 AndAlso argumentCount <> 2) OrElse _
       pArguments = 0 Then Return
    If sqlite3_value_type(pArguments[0]) = SQLITE_NULL Then Return

    Dim pGroup As SqliteGroupConcatContext Ptr = CPtr( _
        SqliteGroupConcatContext Ptr, _
        sqlite3_aggregate_context(pContext, SizeOf(SqliteGroupConcatContext)))
    If pGroup = 0 OrElse pGroup->termCount <= 0 Then Return

    ' Convert the removed value before asking for its byte count. This keeps
    ' UTF-16 inputs measured in the UTF-8 accumulator's current encoding.
    Dim pValue As Const UByte Ptr = sqlite3_value_text(pArguments[0])
    If pValue = 0 Then Return
    Dim bytesToRemove As SQLITE_C_INT = sqlite3_value_bytes(pArguments[0])
    If bytesToRemove < 0 Then
        sqlite3StrAccumSetError(@pGroup->accumulator, SQLITE_NOMEM)
        Return
    End If

    pGroup->termCount -= 1
    If pGroup->separatorLengths <> 0 Then
        If pGroup->termCount > 0 Then
            bytesToRemove += pGroup->separatorLengths[0]
            For iLength As Long = 0 To CLng(pGroup->termCount) - 2
                pGroup->separatorLengths[iLength] = pGroup->separatorLengths[iLength + 1]
            Next
        End If
    Else
        bytesToRemove += pGroup->firstSeparatorLength
    End If

    If bytesToRemove >= pGroup->accumulator.nChar Then
        pGroup->accumulator.nChar = 0
    Else
        Dim remainingBytes As Long = CLng(pGroup->accumulator.nChar) - bytesToRemove
        For byteIndex As Long = 0 To remainingBytes - 1
            pGroup->accumulator.zText[byteIndex] = _
                pGroup->accumulator.zText[byteIndex + bytesToRemove]
        Next
        pGroup->accumulator.nChar = CULngInt(remainingBytes)
    End If

    If pGroup->accumulator.nChar = 0 Then
        pGroup->accumulator.mxAlloc = 0
        sqlite3_free(pGroup->separatorLengths)
        pGroup->separatorLengths = 0
    End If
End Sub

Private Sub groupConcatValue CDecl (ByVal pContext As Any Ptr)
    If pContext = 0 Then Return
    Dim pGroup As SqliteGroupConcatContext Ptr = CPtr( _
        SqliteGroupConcatContext Ptr, sqlite3_aggregate_context(pContext, 0))
    If pGroup <> 0 AndAlso pGroup->termCount > 0 Then _
        sqlite3_result_str(pContext, @pGroup->accumulator, SQLITE_COPY)
End Sub

Private Sub groupConcatFinalize CDecl (ByVal pContext As Any Ptr)
    If pContext = 0 Then Return
    Dim pGroup As SqliteGroupConcatContext Ptr = CPtr( _
        SqliteGroupConcatContext Ptr, sqlite3_aggregate_context(pContext, 0))
    If pGroup <> 0 Then
        sqlite3_result_str(pContext, @pGroup->accumulator, SQLITE_XFER)
        sqlite3_free(pGroup->separatorLengths)
        pGroup->separatorLengths = 0
    End If
End Sub

Private Sub quoteFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 1 Then Return
    Dim pResultContext As SqliteResultContext Ptr = _
        CPtr(SqliteResultContext Ptr, pContext)
    If pResultContext->pOut = 0 Then Return
    Dim pAccumulator As sqlite3_str Ptr = _
        sqlite3_str_new(pResultContext->pOut->db)
    If pAccumulator = 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If
    sqlite3QuoteValue(pAccumulator, pArguments[0], _
                      CInt(sqlite3_user_data(pContext) <> 0))
    sqlite3_result_str(pContext, pAccumulator, SQLITE_FINISH)
End Sub

Private Sub likeFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse _
       (argumentCount <> 2 AndAlso argumentCount <> 3) Then Return
    Dim pResultContext As SqliteResultContext Ptr = CPtr(SqliteResultContext Ptr, pContext)
    If pResultContext->pOut = 0 OrElse pResultContext->pOut->db = 0 Then Return
    Dim pInfo As SqliteLikeCompareInfo Ptr = _
        CPtr(SqliteLikeCompareInfo Ptr, sqlite3_user_data(pContext))
    If pInfo = 0 Then Return

#ifdef SQLITE_LIKE_DOESNT_MATCH_BLOBS
    If sqlite3_value_type(pArguments[0]) = SQLITE_BLOB OrElse _
       sqlite3_value_type(pArguments[1]) = SQLITE_BLOB Then
        sqlite3_result_int(pContext, 0)
        Return
    End If
#endif

    Dim patternLength As SQLITE_C_INT = sqlite3_value_bytes(pArguments[0])
    If patternLength > pResultContext->pOut->db->aLimit( _
        SQLITE_LIMIT_LIKE_PATTERN_LENGTH) Then
        sqlite3_result_error(pContext, StrPtr("LIKE or GLOB pattern too complex"), -1)
        Return
    ElseIf patternLength < 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If

    Dim matchAll As UByte = pInfo->matchAll
    Dim matchOne As UByte = pInfo->matchOne
    Dim matchSet As UByte = pInfo->matchSet
    Dim noCase As UByte = pInfo->noCase
    Dim escape As u32 = matchSet
    If argumentCount = 3 Then
        Dim zEscape As Const UByte Ptr = sqlite3_value_text(pArguments[2])
        If zEscape = 0 Then Return
        If sqlite3Utf8CharLen(zEscape, -1) <> 1 Then
            sqlite3_result_error(pContext, _
                StrPtr("ESCAPE expression must be a single character"), -1)
            Return
        End If
        Dim pEscape As Const UByte Ptr = zEscape
        escape = sqlite3Utf8Read(@pEscape)
        If escape = matchAll Then
            matchAll = 0
        ElseIf escape = matchOne Then
            matchOne = 0
        End If
    End If

    Dim zPattern As Const UByte Ptr = sqlite3_value_text(pArguments[0])
    Dim zInput As Const UByte Ptr = sqlite3_value_text(pArguments[1])
    If zPattern = 0 OrElse zInput = 0 Then
        sqlite3_result_null(pContext)
        Return
    End If
    Dim matchResult As SQLITE_C_INT = sqlite3PatternCompare( _
        zPattern, zInput, matchAll, matchOne, matchSet, noCase, escape)
    Dim isMatch As SQLITE_C_INT = 0
    If matchResult = 0 Then isMatch = 1
    sqlite3_result_int(pContext, isMatch)
End Sub



/' ------------------------------------------------------------------------- '/
/' Built-in function hash '/
/' ------------------------------------------------------------------------- '/

Private Function sqlite3FunctionHash(ByVal zName As Const ZString Ptr) As SQLITE_C_INT
    If zName = 0 Then Return 0
    Dim firstByte As Const UByte Ptr = CPtr(Const UByte Ptr, zName)
    Dim nameLength As SQLITE_C_INT = sqlite3Strlen30(zName)
    Return (sqlite3UpperToLower(firstByte[0]) + nameLength) Mod _
        SQLITE_FUNC_HASH_SZ
End Function

Private Function matchQuality( _
    ByVal pFunction As SqliteFuncDef Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal textEncoding As UByte _
) As SQLITE_C_INT

    If pFunction = 0 OrElse argumentCount < -2 Then Return 0
    Dim registeredCount As SQLITE_C_INT = pFunction->nArg
    If registeredCount < -4 OrElse registeredCount = -2 Then Return 0

    If registeredCount <> argumentCount Then
        If argumentCount = -2 Then
            Return IIf(pFunction->xSFunc = 0, 0, FUNC_PERFECT_MATCH)
        End If
        If registeredCount >= 0 Then Return 0
        If registeredCount < -2 AndAlso _
           argumentCount < -2 - registeredCount Then Return 0
    End If

    Dim score As SQLITE_C_INT = 1
    If registeredCount = argumentCount Then score = 4

    Dim functionEncoding As UByte = _
        CByte(pFunction->funcFlags And SQLITE_FUNC_ENCMASK)
    If textEncoding = functionEncoding Then
        score += 2
    ElseIf (textEncoding And functionEncoding And 2) <> 0 Then
        score += 1
    End If
    Return score
End Function

Function sqlite3FunctionSearch CDecl Alias "sqlite3FunctionSearch" ( _
    ByVal hashValue As SQLITE_C_INT, _
    ByVal zFunction As Const ZString Ptr _
) As SqliteFuncDef Ptr Export

    If hashValue < 0 OrElse hashValue >= SQLITE_FUNC_HASH_SZ OrElse _
       zFunction = 0 Then Return 0
    Dim pFunction As SqliteFuncDef Ptr = sqlite3BuiltinFunctionBuckets(hashValue)
    While pFunction <> 0
        If sqlite3_stricmp(pFunction->zName, zFunction) = 0 Then _
            Return pFunction
        pFunction = CPtr(SqliteFuncDef Ptr, pFunction->u)
    Wend
    Return 0
End Function

Sub sqlite3InsertBuiltinFuncs CDecl Alias "sqlite3InsertBuiltinFuncs" ( _
    ByVal aDefinitions As SqliteFuncDef Ptr, _
    ByVal definitionCount As SQLITE_C_INT _
) Export

    If aDefinitions = 0 OrElse definitionCount <= 0 Then Exit Sub
    For definitionIndex As SQLITE_C_INT = 0 To definitionCount - 1
        Dim pDefinition As SqliteFuncDef Ptr = aDefinitions + definitionIndex
        If pDefinition->zName = 0 OrElse _
           (pDefinition->funcFlags And SQLITE_FUNC_BUILTIN) = 0 Then _
            Continue For

        Dim hashValue As SQLITE_C_INT = sqlite3FunctionHash(pDefinition->zName)
        Dim pOther As SqliteFuncDef Ptr = _
            sqlite3FunctionSearch(hashValue, pDefinition->zName)
        If pOther <> 0 Then
            Dim pScan As SqliteFuncDef Ptr = pOther
            While pScan <> 0 AndAlso pScan <> pDefinition
                pScan = CPtr(SqliteFuncDef Ptr, pScan->pNext)
            Wend
            If pScan = pDefinition Then Continue For

            pDefinition->pNext = pOther->pNext
            pOther->pNext = pDefinition
        Else
            pDefinition->pNext = 0
            pDefinition->u = _
                sqlite3BuiltinFunctionBuckets(hashValue)
            sqlite3BuiltinFunctionBuckets(hashValue) = pDefinition
        End If
    Next
End Sub

Private Sub printfFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pValues As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse argumentCount < 1 OrElse pValues = 0 Then Return
    Dim zFormat As Const UByte Ptr = sqlite3_value_text(pValues[0])
    If zFormat = 0 Then Return

    Dim pDatabase As sqlite3 Ptr = CPtr(sqlite3 Ptr, _
        sqlite3_context_db_handle(pContext))
    Dim maximumLength As SQLITE_C_INT = SQLITE_MAX_LENGTH
    If pDatabase <> 0 Then maximumLength = pDatabase->lengthLimit

    Dim arguments As SqlitePrintfArguments
    arguments.nArg = argumentCount - 1
    arguments.nUsed = 0
    arguments.apArg = @pValues[1]

    Dim accumulation As sqlite3_str
    sqlite3StrAccumInit(@accumulation, pDatabase, 0, 0, maximumLength)
    accumulation.printfFlags = SQLITE_PRINTF_SQLFUNC
    sqlite3_str_appendf(@accumulation, CPtr(Const ZString Ptr, zFormat), @arguments)
    sqlite3_result_str(pContext, @accumulation, SQLITE_XFER)
End Sub

Private Sub loadExt CDecl Alias "loadExt" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteVdbeMem Ptr Ptr)
    Dim local0 As Const ZString Ptr
    Dim local1 As Const ZString Ptr
    Dim local2 As sqlite3 Ptr
    Dim local3 As ZString Ptr
    Dim c2fb_temp_0 As Const ZString Ptr
    Dim c2fb_temp_1 As Const ZString Ptr

    local0 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, &O0ULL)])))
    ' C automatic storage declaration
    local2 = CPtr(sqlite3 Ptr, sqlite3_context_db_handle(CPtr(Any Ptr, arg0)))
    local3 = Cast(SQLITE_C_INT, &O0ULL)
    If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local2->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &H00020000ULL))))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
        sqlite3_result_error(CPtr(Any Ptr, arg0), StrPtr(!"not authorized"), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
        Return
    End If
    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, 2ULL))))) Then
        c2fb_temp_0 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, 1ULL)])))
        local1 = c2fb_temp_0
    Else
        c2fb_temp_1 = CPtr(Const ZString Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        local1 = c2fb_temp_1
    End If
    If (-Cast(SQLITE_C_INT, ((local0 AndAlso sqlite3_load_extension(CPtr(Any Ptr, local2), local0, local1, CPtr(ZString Ptr Ptr, @(local3))))))) Then
        sqlite3_result_error(CPtr(Any Ptr, arg0), CPtr(Const ZString Ptr, local3), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
        sqlite3_free(CPtr(Any Ptr, local3))
    End If
End Sub

#ifdef SQLITE_DEBUG
Private Sub parseuriFunc CDecl Alias "parseuriFunc" ( _
    ByVal pContext As SqliteResultContext Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount < 2 Then Return

    Dim pVfs As sqlite3_vfs Ptr = sqlite3_vfs_find(0)
    If pVfs = 0 OrElse pVfs->zName = 0 Then
        sqlite3DebugAssert(StrPtr("a default VFS is registered"))
        Return
    End If

    Dim zDefaultVfs As Const ZString Ptr = pVfs->zName
    Dim zUri As Const ZString Ptr = CPtr(Const ZString Ptr, _
        sqlite3_value_text(pArguments[0]))
    If zUri = 0 Then Return

    Dim flags As SQLITE_C_UINT = CUInt(sqlite3_value_int(pArguments[1]))
    Dim zFilename As ZString Ptr = 0
    Dim zError As ZString Ptr = 0
    Dim rc As SQLITE_C_INT = sqlite3FunctionsParseUri( _
        zDefaultVfs, zUri, @flags, @pVfs, @zFilename, @zError)
    Dim pResult As sqlite3_str Ptr = sqlite3_str_new(0)

    If pResult = 0 Then
        sqlite3_result_error_nomem(pContext)
    Else
        If sqlite3_str_errcode(pResult) = SQLITE_OK Then
            sqlite3_str_appendf(pResult, StrPtr("rc=%d"), rc)
            sqlite3_str_appendf(pResult, StrPtr(", flags=0x%x"), flags)

            Dim zVfsName As Const ZString Ptr = 0
            If pVfs <> 0 Then zVfsName = pVfs->zName
            sqlite3_str_appendf(pResult, StrPtr(", vfs=%Q"), zVfsName)
            sqlite3_str_appendf(pResult, StrPtr(", err=%Q"), zError)
            sqlite3_str_appendf(pResult, StrPtr(", file=%Q"), zFilename)

            If zFilename <> 0 Then
                Dim pOption As Const UByte Ptr = _
                    CPtr(Const UByte Ptr, zFilename) + _
                    CULngInt(sqlite3Strlen30(zFilename)) + 1
                While pOption[0] <> 0
                    sqlite3_str_appendf(pResult, StrPtr(", %Q"), _
                        CPtr(Const ZString Ptr, pOption))
                    Dim optionLength As SQLITE_C_INT = _
                        sqlite3Strlen30(CPtr(Const ZString Ptr, pOption))
                    If optionLength < 0 Then Exit While
                    pOption += CULngInt(optionLength) + 1
                Wend

                For argumentIndex As SQLITE_C_INT = 2 To argumentCount - 1
                    If sqlite3_value_type(pArguments[argumentIndex]) = SQLITE_INTEGER Then
                        Dim keyIndex As SQLITE_C_INT = _
                            sqlite3_value_int(pArguments[argumentIndex])
                        sqlite3_str_appendf(pResult, StrPtr(", '%d:%q'"), _
                            keyIndex, sqlite3FunctionsUriKey(zFilename, keyIndex))
                    Else
                        Dim zParameter As Const ZString Ptr = _
                            CPtr(Const ZString Ptr, _
                                 sqlite3_value_text(pArguments[argumentIndex]))
                        If zParameter <> 0 Then
                            sqlite3_str_appendf(pResult, StrPtr(", '%q:%q'"), _
                                zParameter, _
                                sqlite3FunctionsUriParameter(zFilename, zParameter))
                        Else
                            sqlite3_str_appendf(pResult, StrPtr(", NULL"))
                        End If
                    End If
                Next
            End If
        End If
        sqlite3_result_str(pContext, pResult, SQLITE_FINISH)
    End If

    sqlite3FunctionsFreeFilename(zFilename)
    sqlite3FunctionsFree(zError)
End Sub

Private Sub sqlite3RegisterDebugBuiltinFunctions()
    Static definitions(0 To 1) As SqliteFuncDef
    Const builtinFlags As u32 = &H00800000 Or SQLITE_FUNC_CONSTANT Or SQLITE_UTF8

    With definitions(0)
        .nArg = 3
        .funcFlags = builtinFlags
        .pUserData = 0
        .pNext = 0
        .xSFunc = @fpdecodeFunc
        .xFinalize = 0
        .xValue = 0
        .xInverse = 0
        .zName = StrPtr("fpdecode")
        .u = 0
    End With
    With definitions(1)
        .nArg = -1
        .funcFlags = builtinFlags
        .pUserData = 0
        .pNext = 0
        .xSFunc = @parseuriFunc
        .xFinalize = 0
        .xValue = 0
        .xInverse = 0
        .zName = StrPtr("parseuri")
        .u = 0
    End With
    sqlite3InsertBuiltinFuncs(@definitions(0), 2)
End Sub
#endif

Sub sqlite3RegisterBuiltinFunctions CDecl Alias "sqlite3RegisterBuiltinFunctions" ()
    Static local0(0 To 73) As SqliteFuncDef = { _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H00040000ULL))) Or Cast(SQLITE_C_INT, &H4000ULL))) Or Cast(SQLITE_C_INT, &H00400000ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))) Or (Cast(SQLITE_C_INT, &O0ULL)))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, 1ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(versionFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"implies_nonnull_row"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H00040000ULL))) Or Cast(SQLITE_C_INT, &H4000ULL))) Or Cast(SQLITE_C_INT, &H00400000ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))) Or (Cast(SQLITE_C_INT, &O0ULL)))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, 3ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(versionFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"expr_compare"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H00040000ULL))) Or Cast(SQLITE_C_INT, &H4000ULL))) Or Cast(SQLITE_C_INT, &H00400000ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))) Or (Cast(SQLITE_C_INT, &O0ULL)))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, 2ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(versionFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"expr_implies_expr"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H00040000ULL))) Or Cast(SQLITE_C_INT, &H4000ULL))) Or Cast(SQLITE_C_INT, &H00400000ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))) Or (Cast(SQLITE_C_INT, &O0ULL)))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, 4ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(versionFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"affinity"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H000080000ULL))) Or Cast(SQLITE_C_INT, &H00200000ULL))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(loadExt), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"load_extension"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H000080000ULL))) Or Cast(SQLITE_C_INT, &H00200000ULL))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(loadExt), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"load_extension"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H2000ULL))) Or Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(compileoptionusedFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"sqlite_compileoption_used"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H2000ULL))) Or Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(compileoptiongetFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"sqlite_compileoption_get"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H00400000ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))) Or (Cast(SQLITE_C_INT, &H0400ULL)))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, 99ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(versionFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"unlikely"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H00400000ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))) Or (Cast(SQLITE_C_INT, &H0400ULL)))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, 99ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(versionFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"likelihood"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H00400000ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))) Or (Cast(SQLITE_C_INT, &H0400ULL)))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, 99ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(versionFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"likely"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, 1ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(trimFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"ltrim"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, 1ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(trimFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"ltrim"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, 2ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(trimFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"rtrim"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, 2ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(trimFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"rtrim"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, 3ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(trimFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"trim"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, 3ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(trimFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"trim"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 3ULL))), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 1ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(minmaxFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"min"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 1ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))) Or Cast(SQLITE_C_INT, &H1000ULL))) Or Cast(SQLITE_C_INT, &H08000000ULL))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(minmaxStep), ProcPtr(minMaxFinalize), ProcPtr(minMaxValue), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"min"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 3ULL))), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 1ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, 1ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(minmaxFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"max"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 1ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))) Or Cast(SQLITE_C_INT, &H1000ULL))) Or Cast(SQLITE_C_INT, &H08000000ULL))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, 1ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(minmaxStep), ProcPtr(minMaxFinalize), ProcPtr(minMaxValue), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"max"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))) Or Cast(SQLITE_C_INT, &H0080ULL))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(typeofFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"typeof"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))) Or Cast(SQLITE_C_INT, &H0080ULL))) Or Cast(SQLITE_C_INT, &H000100000ULL))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(subtypeFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"subtype"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))) Or Cast(SQLITE_C_INT, &H0040ULL))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(lengthFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"length"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))) Or Cast(SQLITE_C_INT, &H00c0ULL))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(bytelengthFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"octet_length"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(instrFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"instr"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(printfFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"printf"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(printfFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"format"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(unicodeFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"unicode"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(charFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"char"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(absFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"abs"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(roundFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"round"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(roundFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"round"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(upperFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"upper"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(lowerFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"lower"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(hexFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"hex"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(unhexFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"unhex"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(unhexFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"unhex"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 3ULL))), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(concatFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"concat"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 4ULL))), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(concatwsFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"concat_ws"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H00400000ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))) Or (Cast(SQLITE_C_INT, &O0ULL)))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(versionFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"ifnull"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, &O0ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(randomFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"random"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(randomBlob), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"randomblob"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 1ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(nullifFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"nullif"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, &O0ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H2000ULL))) Or Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(versionFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"sqlite_version"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, &O0ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H2000ULL))) Or Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(sourceidFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"sqlite_source_id"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H000080000ULL))) Or Cast(SQLITE_C_INT, &H00200000ULL))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(errlogFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"sqlite_log"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(unistrFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"unistr"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(quoteFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"quote"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, 1ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(quoteFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"unistr_quote"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, &O0ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(last_insert_rowid), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"last_insert_rowid"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, &O0ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(changes), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"changes"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, &O0ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(total_changes), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"total_changes"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 3ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(replaceFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"replace"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(zeroblobFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"zeroblob"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(substrFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"substr"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 3ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(substrFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"substr"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(substrFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"substring"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 3ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(substrFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"substring"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))) Or Cast(SQLITE_C_INT, &O0ULL))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(sumStep), ProcPtr(sumFinalize), ProcPtr(sumFinalize), ProcPtr(sumInverse), StrPtr(!"sum"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))) Or Cast(SQLITE_C_INT, &O0ULL))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(sumStep), ProcPtr(totalFinalize), ProcPtr(totalFinalize), ProcPtr(sumInverse), StrPtr(!"total"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))) Or Cast(SQLITE_C_INT, &O0ULL))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(sumStep), ProcPtr(avgFinalize), ProcPtr(avgFinalize), ProcPtr(sumInverse), StrPtr(!"avg"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, &O0ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))) Or Cast(SQLITE_C_INT, &H0100ULL))) Or Cast(SQLITE_C_INT, &H08000000ULL))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(countStep), ProcPtr(countFinalize), ProcPtr(countFinalize), ProcPtr(countInverse), StrPtr(!"count"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))) Or Cast(SQLITE_C_INT, &H08000000ULL))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(countStep), ProcPtr(countFinalize), ProcPtr(countFinalize), ProcPtr(countInverse), StrPtr(!"count"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))) Or Cast(SQLITE_C_INT, &O0ULL))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(groupConcatStep), ProcPtr(groupConcatFinalize), ProcPtr(groupConcatValue), ProcPtr(groupConcatInverse), StrPtr(!"group_concat"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))) Or Cast(SQLITE_C_INT, &O0ULL))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(groupConcatStep), ProcPtr(groupConcatFinalize), ProcPtr(groupConcatValue), ProcPtr(groupConcatInverse), StrPtr(!"group_concat"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))) Or Cast(SQLITE_C_INT, &O0ULL))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(groupConcatStep), ProcPtr(groupConcatFinalize), ProcPtr(groupConcatValue), ProcPtr(groupConcatInverse), StrPtr(!"string_agg"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H0004ULL))) Or Cast(SQLITE_C_INT, &H0008ULL))), CPtr(Any Ptr, @sqlite3GlobCompareInfo), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(likeFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"glob"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H0004ULL))), CPtr(Any Ptr, @sqlite3LikeCompareInfo), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(likeFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"like"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 3ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H0004ULL))), CPtr(Any Ptr, @sqlite3LikeCompareInfo), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(likeFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"like"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 1ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H0800ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) * Cast(SQLITE_C_INT, &H0020ULL)))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(signFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"sign"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 4ULL))), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H00400000ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))) Or (Cast(SQLITE_C_INT, &O0ULL)))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(versionFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"coalesce"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 4ULL))), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H00400000ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))) Or (Cast(SQLITE_C_INT, &O0ULL)))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, 5ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(versionFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"iif"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 4ULL))), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H00400000ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))) Or (Cast(SQLITE_C_INT, &O0ULL)))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (Cast(SQLITE_C_INT, 5ULL)))))), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(versionFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"if"), Cast(Any Ptr, 0) )}

    ' C static array storage
#ifndef SQLITE_OMIT_ALTERTABLE
    sqlite3AlterFunctions()
#endif
#ifndef SQLITE_OMIT_WINDOWFUNC
    sqlite3WindowFunctions()
#endif
    sqlite3RegisterDateTimeFunctions()
    sqlite3RegisterJsonFunctions()
    sqlite3InsertBuiltinFuncs(CPtr(Any Ptr, CPtr(SqliteFuncDef Ptr, (@local0(0)))), (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, (74ULL * SizeOf(SqliteFuncDef)))) \ Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteFuncDef)))))))))
#ifdef SQLITE_DEBUG
    sqlite3RegisterDebugBuiltinFunctions()
#endif
    sqlite3RegisterOptionalBuiltinFunctions()
End Sub

Private Sub sqlite3BuiltinFunctionInitialize()
    If sqlite3BuiltinFunctionsReady <> 0 Then Return

    sqlite3LikeCompareInfo.matchAll = Asc("%")
    sqlite3LikeCompareInfo.matchOne = Asc("_")
    sqlite3LikeCompareInfo.matchSet = 0
    sqlite3LikeCompareInfo.noCase = 1
    sqlite3LikeCompareInfoAlt.matchAll = Asc("%")
    sqlite3LikeCompareInfoAlt.matchOne = Asc("_")
    sqlite3LikeCompareInfoAlt.matchSet = 0
    sqlite3LikeCompareInfoAlt.noCase = 0
    sqlite3GlobCompareInfo.matchAll = Asc("*")
    sqlite3GlobCompareInfo.matchOne = Asc("?")
    sqlite3GlobCompareInfo.matchSet = Asc("[")
    sqlite3GlobCompareInfo.noCase = 0

    ' Set the guard before registration because extension tables may perform lookups.
    sqlite3BuiltinFunctionsReady = 1
    sqlite3RegisterBuiltinFunctions()
End Sub

Private Function sqlite3FindBuiltinFunctionWithEncoding( _
    ByVal zName As Const ZString Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal textEncoding As UByte _
) As SqliteFuncDef Ptr
    If zName = 0 OrElse argumentCount < -2 Then Return 0
    Dim pMutex As Any Ptr = sqlite3_mutex_alloc(SQLITE_MUTEX_STATIC_MASTER)
    If pMutex = 0 Then Return 0
    sqlite3_mutex_enter(pMutex)
    If sqlite3BuiltinFunctionsReady = 0 Then sqlite3BuiltinFunctionInitialize()
    Dim pResult As SqliteFuncDef Ptr = 0
    Dim hashValue As SQLITE_C_INT = sqlite3FunctionHash(zName)
    Dim pFunction As SqliteFuncDef Ptr = _
        sqlite3FunctionSearch(hashValue, zName)
    Dim bestScore As SQLITE_C_INT = 0
    While pFunction <> 0
        Dim score As SQLITE_C_INT = matchQuality( _
            pFunction, argumentCount, textEncoding)
        If score > bestScore Then
            pResult = pFunction
            bestScore = score
        End If
        pFunction = CPtr(SqliteFuncDef Ptr, pFunction->pNext)
    Wend
    If pResult <> 0 AndAlso pResult->xSFunc = 0 Then pResult = 0
    sqlite3_mutex_leave(pMutex)
    Return pResult
End Function

Function sqlite3FindBuiltinFunction CDecl Alias "sqlite3FindBuiltinFunction" ( _
    ByVal zName As Const ZString Ptr, _
    ByVal argumentCount As SQLITE_C_INT _
) As SqliteFuncDef Ptr Export
    Return sqlite3FindBuiltinFunctionWithEncoding( _
        zName, argumentCount, SQLITE_UTF8)
End Function

/' ------------------------------------------------------------------------- '/
/' Per-connection scalar callback registry '/
/' ------------------------------------------------------------------------- '/

Private Function sqlite3FunctionNameLength( _
    ByVal zName As Const ZString Ptr _
) As SQLITE_C_INT
    If zName = 0 Then Return -1
    For nameLength As SQLITE_C_INT = 0 To 255
        If zName[nameLength] = 0 Then Return nameLength
    Next
    Return -1
End Function

Private Sub sqlite3FunctionCallDestroy( _
    ByVal pDestroy As Any Ptr, _
    ByVal pUserData As Any Ptr _
)
    If pDestroy = 0 Then Return
    Dim xDestroy As SqliteFunctionDestroyCallback = _
        CPtr(SqliteFunctionDestroyCallback, pDestroy)
    xDestroy(pUserData)
End Sub

Private Sub sqlite3FunctionReleaseDestructor( _
    ByVal db As sqlite3 Ptr, _
    ByVal pDestructor As SqliteFuncDestructor Ptr _
)
    If db = 0 OrElse pDestructor = 0 OrElse pDestructor->nRef <= 0 Then Return
    pDestructor->nRef -= 1
    If pDestructor->nRef = 0 Then
        If pDestructor->xDestroy <> 0 Then _
            pDestructor->xDestroy(pDestructor->pUserData)
        sqlite3DbFree(db, pDestructor)
    End If
End Sub

Private Sub sqlite3FunctionDiscardDestructor( _
    ByVal db As sqlite3 Ptr, _
    ByVal pDestructor As SqliteFuncDestructor Ptr _
)
    If db = 0 OrElse pDestructor = 0 OrElse pDestructor->nRef <> 0 Then Return
    If pDestructor->xDestroy <> 0 Then _
        pDestructor->xDestroy(pDestructor->pUserData)
    sqlite3DbFree(db, pDestructor)
End Sub

Private Sub sqlite3FunctionDispose( _
    ByVal db As sqlite3 Ptr, _
    ByVal pFunction As SqliteFuncDef Ptr _
)
    If db = 0 OrElse pFunction = 0 Then Return
    Dim pDestructor As SqliteFuncDestructor Ptr = _
        CPtr(SqliteFuncDestructor Ptr, pFunction->u)
    Dim pName As Any Ptr = CPtr(Any Ptr, pFunction->zName)
    pFunction->u = 0
    pFunction->pUserData = 0
    If pName <> 0 Then sqlite3DbFree(db, pName)
    sqlite3DbFree(db, pFunction)
    sqlite3FunctionReleaseDestructor(db, pDestructor)
End Sub

Private Function sqlite3FindUserFunction( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal textEncoding As u8 _
) As SqliteFuncDef Ptr
    If db = 0 OrElse zName = 0 OrElse argumentCount < -2 Then Return 0
    Dim pBest As SqliteFuncDef Ptr = 0
    Dim bestScore As SQLITE_C_INT = 0
    Dim pCurrent As SqliteFuncDef Ptr = _
        CPtr(SqliteFuncDef Ptr, db->pUserFunctions)
    While pCurrent <> 0
        If pCurrent->zName <> 0 AndAlso _
           sqlite3_stricmp(zName, pCurrent->zName) = 0 Then
            Dim score As SQLITE_C_INT = matchQuality( _
                pCurrent, argumentCount, textEncoding)
            If score > bestScore Then
                pBest = pCurrent
                bestScore = score
            End If
        End If
        pCurrent = CPtr(SqliteFuncDef Ptr, pCurrent->pNext)
    Wend
    Return pBest
End Function

Function sqlite3FindFunction CDecl Alias "sqlite3FindFunction" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal textEncoding As u8, _
    ByVal createFlag As u8 _
) As SqliteFuncDef Ptr Export
    If db = 0 OrElse zName = 0 OrElse argumentCount < -2 OrElse _
       (createFlag <> 0 AndAlso argumentCount < -1) Then Return 0
    Dim pFunction As SqliteFuncDef Ptr = _
        sqlite3FindUserFunction(db, zName, argumentCount, textEncoding)
    If createFlag <> 0 Then
        If pFunction <> 0 AndAlso _
           matchQuality(pFunction, argumentCount, textEncoding) = _
               FUNC_PERFECT_MATCH Then Return pFunction

        Dim nameLength As SQLITE_C_INT = sqlite3FunctionNameLength(zName)
        If nameLength < 0 Then Return 0
        Dim pNewFunction As SqliteFuncDef Ptr = _
            CPtr(SqliteFuncDef Ptr, _
                sqlite3DbMallocZero(db, SizeOf(SqliteFuncDef)))
        If pNewFunction = 0 Then Return 0
        Dim zFunctionName As ZString Ptr = CPtr(ZString Ptr, _
            sqlite3DbStrDup(db, zName))
        If zFunctionName = 0 Then
            sqlite3DbFree(db, pNewFunction)
            Return 0
        End If

        pNewFunction->nArg = CShort(argumentCount)
        pNewFunction->funcFlags = textEncoding
        pNewFunction->zName = zFunctionName
        pNewFunction->pNext = db->pUserFunctions
        db->pUserFunctions = pNewFunction
        Return pNewFunction
    End If
    If pFunction = 0 OrElse (db->mDbFlags And DBFLAG_PreferBuiltin) <> 0 Then
        Dim pBuiltin As SqliteFuncDef Ptr = _
            sqlite3FindBuiltinFunctionWithEncoding(zName, argumentCount, textEncoding)
        If pBuiltin <> 0 Then Return pBuiltin
    End If
    Return pFunction
End Function

Sub sqlite3RegisterLikeFunctions CDecl Alias "sqlite3RegisterLikeFunctions" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal caseSensitive As SQLITE_C_INT _
)
    Dim pInfo As SqliteLikeCompareInfo Ptr
    Dim functionFlags As u32

    If caseSensitive <> 0 Then
        pInfo = @sqlite3LikeCompareInfoAlt
        functionFlags = SQLITE_FUNC_LIKE Or SQLITE_FUNC_CASE
    Else
        pInfo = @sqlite3LikeCompareInfo
        functionFlags = SQLITE_FUNC_LIKE
    End If

    For argumentCount As SQLITE_C_INT = 2 To 3
        sqlite3CreateFunc(db, StrPtr(!"like"), argumentCount, SQLITE_UTF8, _
            CPtr(Any Ptr, pInfo), _
            CPtr(Any Ptr, ProcPtr(likeFunc)), _
            CPtr(Any Ptr, 0), CPtr(Any Ptr, 0), CPtr(Any Ptr, 0), _
            CPtr(Any Ptr, 0), CPtr(Any Ptr, 0))

        Dim pFunction As SqliteFuncDef Ptr = _
            sqlite3FindFunction(db, StrPtr(!"like"), argumentCount, _
                                SQLITE_UTF8, 0)
        ASSERT(pFunction <> 0)
        If pFunction Then
            pFunction->funcFlags Or= functionFlags
            pFunction->funcFlags And= Not SQLITE_FUNC_UNSAFE
        End If
    Next
End Sub

Private Function sqlite3FunctionExpireStatements( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
    ' Function opcodes retain FuncDef pointers until their statements are reset.
    If db->nVdbeActive <> 0 Then
        sqlite3ErrorWithMsg(db, SQLITE_BUSY, StrPtr(_
            !"unable to delete/modify user-function due to active statements"))
        Return SQLITE_BUSY
    End If
    sqlite3ExpirePreparedStatements(db, 0)
    Return SQLITE_OK
End Function

Private Function sqlite3FunctionApiFinish( _
    ByVal db As sqlite3 Ptr, _
    ByVal resultCode As SQLITE_C_INT _
) As SQLITE_C_INT
    ' Public API exits must convert deferred allocation failures into NOMEM.
    Dim rc As SQLITE_C_INT = resultCode
    If db->mallocFailed <> 0 Then
        sqlite3DbClearMallocFailed(db)
        db->errorCode = SQLITE_NOMEM
        rc = SQLITE_NOMEM
    ElseIf rc <> SQLITE_OK Then
        db->errorCode = rc
    End If
    sqlite3DbLeave(db)
    Return rc
End Function

Function sqlite3_create_function_v2 CDecl Alias "sqlite3_create_function_v2" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal functionFlags As SQLITE_C_INT, _
    ByVal pUserData As Any Ptr, _
    ByVal xFunction As Any Ptr, _
    ByVal xStep As Any Ptr, _
    ByVal xFinal As Any Ptr, _
    ByVal xDestroy As Any Ptr _
) As SQLITE_C_INT Export
    If db = 0 OrElse db->isOpen <> 1 OrElse db->isZombie <> 0 Then _
        Return SQLITE_MISUSE
    sqlite3DbEnter(db)

    Dim nameLength As SQLITE_C_INT = sqlite3FunctionNameLength(zName)
    Dim isDeletion As SQLITE_C_INT = _
        CInt(xFunction = 0 AndAlso xStep = 0 AndAlso xFinal = 0)
    Dim isScalarRegistration As SQLITE_C_INT = _
        CInt(xFunction <> 0 AndAlso xStep = 0 AndAlso xFinal = 0)
    Dim isAggregateRegistration As SQLITE_C_INT = _
        CInt(xFunction = 0 AndAlso xStep <> 0 AndAlso xFinal <> 0)
    If nameLength < 0 OrElse argumentCount < -1 OrElse _
       argumentCount > SQLITE_MAX_FUNCTION_ARG OrElse _
       (isDeletion = 0 AndAlso isScalarRegistration = 0 AndAlso _
        isAggregateRegistration = 0) Then
        ' Window callbacks and mixed scalar/aggregate definitions are unsupported.
        sqlite3FunctionCallDestroy(xDestroy, pUserData)
        Return sqlite3FunctionApiFinish(db, SQLITE_MISUSE)
    End If

    Dim pExisting As SqliteFuncDef Ptr = _
        sqlite3FindUserFunction(db, zName, argumentCount, db->enc)
    If pExisting <> 0 AndAlso pExisting->nArg <> argumentCount Then _
        pExisting = 0
    Dim pBuiltin As SqliteFuncDef Ptr = 0
    If pExisting = 0 AndAlso isDeletion = 0 Then _
        pBuiltin = sqlite3FindBuiltinFunction(zName, argumentCount)

    If isDeletion <> 0 Then
        If pExisting = 0 Then
            sqlite3FunctionCallDestroy(xDestroy, pUserData)
            Return sqlite3FunctionApiFinish(db, SQLITE_OK)
        End If
        Dim rc As SQLITE_C_INT = sqlite3FunctionExpireStatements(db)
        If rc <> SQLITE_OK Then
            sqlite3FunctionCallDestroy(xDestroy, pUserData)
            Return sqlite3FunctionApiFinish(db, rc)
        End If

        Dim pPrevious As SqliteFuncDef Ptr = 0
        Dim pCurrent As SqliteFuncDef Ptr = _
            CPtr(SqliteFuncDef Ptr, db->pUserFunctions)
        While pCurrent <> 0
            If pCurrent = pExisting Then
                If pPrevious = 0 Then
                    db->pUserFunctions = pCurrent->pNext
                Else
                    pPrevious->pNext = pCurrent->pNext
                End If
                Exit While
            End If
            pPrevious = pCurrent
            pCurrent = CPtr(SqliteFuncDef Ptr, pCurrent->pNext)
        Wend
        sqlite3FunctionDispose(db, pExisting)
        sqlite3FunctionCallDestroy(xDestroy, pUserData)
        Return sqlite3FunctionApiFinish(db, SQLITE_OK)
    End If

    If pExisting <> 0 OrElse pBuiltin <> 0 Then
        Dim rc As SQLITE_C_INT = sqlite3FunctionExpireStatements(db)
        If rc <> SQLITE_OK Then
            sqlite3FunctionCallDestroy(xDestroy, pUserData)
            Return sqlite3FunctionApiFinish(db, rc)
        End If
    End If

    Dim normalizedEncoding As SQLITE_C_INT = functionFlags And &H07
    If normalizedEncoding <> SQLITE_UTF8 AndAlso _
       normalizedEncoding <> SQLITE_UTF16LE AndAlso _
       normalizedEncoding <> SQLITE_UTF16BE AndAlso _
       normalizedEncoding <> SQLITE_UTF16 AndAlso _
       normalizedEncoding <> SQLITE_ANY Then normalizedEncoding = SQLITE_UTF8
    Dim storedFunctionFlags As u32 = CULngInt(functionFlags)
    storedFunctionFlags = storedFunctionFlags And Not CULng(&HF)
    storedFunctionFlags Or= CULng(normalizedEncoding)
    Dim xImplementation As Any Ptr = xFunction
    If xImplementation = 0 Then xImplementation = xStep

    Dim pDestructor As SqliteFuncDestructor Ptr = 0
    If xDestroy <> 0 Then
        pDestructor = CPtr(SqliteFuncDestructor Ptr, _
            sqlite3DbMallocZero(db, SizeOf(SqliteFuncDestructor)))
        If pDestructor = 0 Then
            sqlite3OomFault(db)
            sqlite3FunctionCallDestroy(xDestroy, pUserData)
            Return sqlite3FunctionApiFinish(db, SQLITE_NOMEM)
        End If
        pDestructor->xDestroy = _
            CPtr(SqliteDbDestructor, xDestroy)
        pDestructor->pUserData = pUserData
    End If

    If pExisting <> 0 Then
        Dim pOldDestructor As SqliteFuncDestructor Ptr = _
            CPtr(SqliteFuncDestructor Ptr, pExisting->u)
        pExisting->funcFlags = storedFunctionFlags
        pExisting->pUserData = pUserData
        pExisting->xSFunc = CPtr(SqliteScalarFunction, xImplementation)
        pExisting->xFinalize = xFinal
        pExisting->u = pDestructor
        If pDestructor <> 0 Then pDestructor->nRef += 1
        sqlite3FunctionReleaseDestructor(db, pOldDestructor)
        Return sqlite3FunctionApiFinish(db, SQLITE_OK)
    End If

    Dim pFunction As SqliteFuncDef Ptr = CPtr(SqliteFuncDef Ptr, _
        sqlite3DbMallocZero(db, SizeOf(SqliteFuncDef)))
    If pFunction = 0 Then
        sqlite3FunctionDiscardDestructor(db, pDestructor)
        Return sqlite3FunctionApiFinish(db, SQLITE_NOMEM)
    End If
    Dim zFunctionName As ZString Ptr = CPtr(ZString Ptr, _
        sqlite3DbStrDup(db, zName))
    If zFunctionName = 0 Then
        sqlite3DbFree(db, pFunction)
        sqlite3FunctionDiscardDestructor(db, pDestructor)
        Return sqlite3FunctionApiFinish(db, SQLITE_NOMEM)
    End If
    pFunction->nArg = CShort(argumentCount)
    pFunction->funcFlags = storedFunctionFlags
    pFunction->pUserData = pUserData
    pFunction->xSFunc = CPtr(SqliteScalarFunction, xImplementation)
    pFunction->xFinalize = xFinal
    pFunction->zName = zFunctionName
    pFunction->u = pDestructor
    If pDestructor <> 0 Then pDestructor->nRef += 1
    pFunction->pNext = db->pUserFunctions
    db->pUserFunctions = pFunction
    Return sqlite3FunctionApiFinish(db, SQLITE_OK)
End Function

Function sqlite3_create_function CDecl Alias "sqlite3_create_function" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal functionFlags As SQLITE_C_INT, _
    ByVal pUserData As Any Ptr, _
    ByVal xFunction As Any Ptr, _
    ByVal xStep As Any Ptr, _
    ByVal xFinal As Any Ptr _
) As SQLITE_C_INT Export
    Return sqlite3_create_function_v2( _
        db, zName, argumentCount, functionFlags, pUserData, _
        xFunction, xStep, xFinal, 0)
End Function

Function sqlite3_create_function16 CDecl Alias "sqlite3_create_function16" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal functionFlags As SQLITE_C_INT, _
    ByVal pUserData As Any Ptr, _
    ByVal xFunction As Any Ptr, _
    ByVal xStep As Any Ptr, _
    ByVal xFinal As Any Ptr _
) As SQLITE_C_INT Export
    If db = 0 OrElse zName = 0 OrElse db->isOpen <> 1 OrElse db->isZombie <> 0 Then _
        Return SQLITE_MISUSE
    sqlite3DbEnter(db)
    Dim zUtf8Name As ZString Ptr = sqlite3Utf16to8( _
        db, zName, -1, SQLITE_UTF16NATIVE)
    If zUtf8Name = 0 Then
        Dim rc As SQLITE_C_INT = SQLITE_MISUSE
        If db->mallocFailed <> 0 Then
            sqlite3DbClearMallocFailed(db)
            db->errorCode = SQLITE_NOMEM
            rc = SQLITE_NOMEM
        End If
        sqlite3DbLeave(db)
        Return rc
    End If
    Dim rc As SQLITE_C_INT = sqlite3_create_function( _
        db, zUtf8Name, argumentCount, functionFlags, pUserData, _
        xFunction, xStep, xFinal)
    sqlite3DbFree(db, zUtf8Name)
    sqlite3DbLeave(db)
    Return rc
End Function

Sub sqlite3_progress_handler CDecl Alias "sqlite3_progress_handler" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal operationInterval As SQLITE_C_INT, _
    ByVal xProgress As Any Ptr, _
    ByVal pUserData As Any Ptr _
) Export
    If db = 0 OrElse db->isOpen <> 1 OrElse db->isZombie <> 0 Then Return
    sqlite3DbEnter(db)
    If operationInterval > 0 Then
        db->xProgress = CPtr(SqliteProgressCallback, xProgress)
        db->nProgressOps = CULngInt(operationInterval)
        db->pProgressArg = pUserData
    Else
        db->xProgress = 0
        db->nProgressOps = 0
        db->pProgressArg = 0
    End If
    sqlite3DbLeave(db)
End Sub

Sub sqlite3DbFunctionDestroy CDecl Alias "sqlite3DbFunctionDestroy" ( _
    ByVal db As sqlite3 Ptr _
) Export
    If db = 0 Then Return
    While db->pUserFunctions <> 0
        Dim pFunction As SqliteFuncDef Ptr = _
            CPtr(SqliteFuncDef Ptr, db->pUserFunctions)
        db->pUserFunctions = pFunction->pNext
        sqlite3FunctionDispose(db, pFunction)
    Wend
End Sub

/' end of sqlite3_functions.bas '/
