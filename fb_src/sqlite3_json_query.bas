/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_query.bas

    Purpose:

        Traverse JSONB paths for query and edit operations.

    Responsibilities:

        - Traverse JSONB object labels and array indexes.
        - Apply JSONB insert, replace, delete, and set edits.
        - Build nested object or array nodes when an edit creates missing paths.
        - Count top-level array values and construct path error messages.
        - Implement json_type() and json_array_length() with optional paths.

    This file intentionally does NOT contain:

        - JSON text parsing, wildcard search, extraction callbacks, or table-valued functions.
'/ 

#lang "fb"
#include once "sqlite3_json_query.bi"
#include once "sqlite3_vdbe_api.bi"
#include once "sqlite3_constants.bi"

Declare Function sqlite3_strglob CDecl Alias "sqlite3_strglob" ( _
    ByVal zPattern As Const ZString Ptr, _
    ByVal zText As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function jsonQueryMPrintf CDecl Alias "sqlite3_mprintf" ( _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) As ZString Ptr
Declare Sub jsonQueryFree CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Declare Sub sqlite3_result_error CDecl Alias "sqlite3_result_error" ( _
    ByVal pContext As Any Ptr, _
    ByVal zError As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT _
)
Declare Sub sqlite3_result_error_nomem CDecl Alias "sqlite3_result_error_nomem" ( _
    ByVal pContext As Any Ptr _
)
Declare Sub sqlite3_result_text CDecl Alias "sqlite3_result_text" ( _
    ByVal pContext As Any Ptr, _
    ByVal zText As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal pDestructor As Any Ptr _
)
Declare Sub sqlite3_result_int64 CDecl Alias "sqlite3_result_int64" ( _
    ByVal pContext As Any Ptr, _
    ByVal value As sqlite3_int64 _
)
Declare Function jsonQueryMemset CDecl Alias "memset" ( _
    ByVal pDestination As Any Ptr, _
    ByVal fillValue As SQLITE_C_INT, _
    ByVal nByte As SQLITE_SIZE_T _
) As Any Ptr
Declare Function jsonQueryMemcpy CDecl Alias "memcpy" ( _
    ByVal pDestination As Any Ptr, _
    ByVal pSource As Const Any Ptr, _
    ByVal nByte As SQLITE_SIZE_T _
) As Any Ptr
Declare Sub jsonQueryBlobEdit CDecl Alias "jsonBlobEdit" ( _
    ByVal pParse As JsonParse Ptr, _
    ByVal index As u32, _
    ByVal deleteBytes As u32, _
    ByVal pInsert As Const UByte Ptr, _
    ByVal insertBytes As u32 _
)
Declare Sub jsonQueryAfterEditSizeAdjust CDecl Alias "jsonAfterEditSizeAdjust" ( _
    ByVal pParse As JsonParse Ptr, _
    ByVal rootIndex As u32 _
)

Private Dim Shared As Const UByte jsonQueryEmptyContainerHeader(0 To 1) = _
    {JSONB_ARRAY, JSONB_OBJECT}

Private Function jsonQueryPathByte( _
    ByVal zPath As Const UByte Ptr, _
    ByVal offset As u32 _
) As UByte
    If zPath = 0 Then Return 0
    Return zPath[offset]
End Function

Private Function jsonQueryDigit(ByVal value As UByte) As SQLITE_C_INT
    Return CInt(value >= Asc("0") AndAlso value <= Asc("9"))
End Function

Private Function jsonQueryHexDigit(ByVal value As UByte) As SQLITE_C_INT
    If jsonQueryDigit(value) <> 0 Then Return 1
    If value >= Asc("A") AndAlso value <= Asc("F") Then Return 1
    If value >= Asc("a") AndAlso value <= Asc("f") Then Return 1
    Return 0
End Function

Private Function jsonCreateEditSubstructure CDecl Alias "jsonCreateEditSubstructure" ( _
    ByVal pParse As JsonParse Ptr, _
    ByVal pInsert As JsonParse Ptr, _
    ByVal zTail As Const UByte Ptr _
) As u32
    If pParse = 0 OrElse pInsert = 0 OrElse zTail = 0 Then Return JSON_LOOKUP_ERROR
    jsonQueryMemset(pInsert, 0, SizeOf(JsonParse))
    pInsert->db = pParse->db
    If zTail[0] = 0 Then
        pInsert->aBlob = pParse->aIns
        pInsert->nBlob = pParse->nIns
        Return 0
    End If

    pInsert->nBlob = 1
    Dim headerIndex As SQLITE_C_INT = 0
    If zTail[0] = Asc(".") Then headerIndex = 1
    pInsert->aBlob = CPtr(UByte Ptr, @jsonQueryEmptyContainerHeader(headerIndex))
    pInsert->eEdit = pParse->eEdit
    pInsert->nIns = pParse->nIns
    pInsert->aIns = pParse->aIns
    pInsert->iDepth = pParse->iDepth + 1
    If pInsert->iDepth >= JSON_MAX_DEPTH Then Return JSON_LOOKUP_TOODEEP

    Dim resultCode As u32 = jsonLookupStep(pInsert, 0, zTail, 0)
    ' The recursively built temporary parse owns this nesting level.
    pInsert->iDepth -= 1
    pParse->oom = pParse->oom Or pInsert->oom
    Return resultCode
End Function

Function jsonbArrayCount CDecl Alias "jsonbArrayCount" ( _
    ByVal pParse As Const JsonParse Ptr, _
    ByVal rootIndex As u32 _
) As u32 Export
    If pParse = 0 OrElse pParse->aBlob = 0 Then Return 0
    Dim payloadSize As u32 = 0
    Dim headerSize As u32 = jsonbPayloadSize(pParse, rootIndex, @payloadSize)
    If headerSize = 0 Then Return 0
    Dim cursor As sqlite3_uint64 = _
        CULngInt(rootIndex) + CULngInt(headerSize)
    Dim endOffset As sqlite3_uint64 = cursor + CULngInt(payloadSize)
    Dim availableBytes As u32 = pParse->nBlob
    If pParse->nBlobAlloc > availableBytes Then availableBytes = pParse->nBlobAlloc
    If endOffset > CULngInt(availableBytes) Then Return 0

    Dim count As u32 = 0
    While cursor < endOffset
        If cursor > &HFFFFFFFFULL Then Exit While
        Dim childSize As u32 = 0
        Dim childHeader As u32 = jsonbPayloadSizeSemiInline( _
            pParse, CUInt(cursor), @childSize)
        If childHeader = 0 Then Exit While
        Dim nextOffset As sqlite3_uint64 = _
            cursor + CULngInt(childHeader) + CULngInt(childSize)
        If nextOffset > endOffset Then Exit While
        cursor = nextOffset
        count += 1
    Wend
    Return count
End Function

Function jsonBadPathError CDecl Alias "jsonBadPathError" ( _
    ByVal pContext As Any Ptr, _
    ByVal zPath As Const UByte Ptr, _
    ByVal resultCode As u32 _
) As ZString Ptr Export
    Dim zMessage As ZString Ptr
    Select Case resultCode
    Case JSON_LOOKUP_NOTARRAY
        zMessage = jsonQueryMPrintf(StrPtr("not an array element: %Q"), zPath)
    Case JSON_LOOKUP_ERROR
        zMessage = jsonQueryMPrintf(StrPtr("malformed JSON"))
    Case JSON_LOOKUP_TOODEEP
        zMessage = jsonQueryMPrintf(StrPtr("JSON path too deep"))
    Case Else
        zMessage = jsonQueryMPrintf(StrPtr("bad JSON path: %Q"), zPath)
    End Select
    If pContext = 0 Then Return zMessage
    If zMessage = 0 Then
        sqlite3_result_error_nomem(pContext)
    Else
        sqlite3_result_error(pContext, zMessage, -1)
        jsonQueryFree(zMessage)
    End If
    Return 0
End Function

Function jsonLookupStep CDecl Alias "jsonLookupStep" ( _
    ByVal pParse As JsonParse Ptr, _
    ByVal rootIndex As u32, _
    ByVal zPath As Const UByte Ptr, _
    ByVal labelIndex As u32 _
) As u32 Export
    If pParse = 0 OrElse pParse->aBlob = 0 OrElse zPath = 0 Then _
        Return JSON_LOOKUP_ERROR
    If zPath[0] = 0 Then
        If pParse->eEdit <> 0 AndAlso _
           jsonBlobMakeEditable(pParse, pParse->nIns) <> 0 Then
            Dim payloadSize As u32 = 0
            Dim headerSize As u32 = jsonbPayloadSize(pParse, rootIndex, @payloadSize)
            If headerSize = 0 Then Return JSON_LOOKUP_ERROR
            Dim deleteBytes As u32 = headerSize + payloadSize
            Select Case pParse->eEdit
            Case JEDIT_DEL
                If labelIndex > 0 Then
                    deleteBytes += rootIndex - labelIndex
                    rootIndex = labelIndex
                End If
                jsonQueryBlobEdit(pParse, rootIndex, deleteBytes, 0, 0)
            Case JEDIT_INS
                ' json_insert leaves an existing value unchanged.
            Case JEDIT_AINS
                If zPath[-1] <> Asc("]") Then Return JSON_LOOKUP_NOTARRAY
                jsonQueryBlobEdit(pParse, rootIndex, 0, pParse->aIns, pParse->nIns)
            Case Else
                jsonQueryBlobEdit(pParse, rootIndex, deleteBytes, _
                                  pParse->aIns, pParse->nIns)
            End Select
        End If
        pParse->iLabel = labelIndex
        Return rootIndex
    End If

    Dim pathOffset As u32 = 0
    Dim nodeType As UByte
    Dim payloadSize As u32 = 0
    Dim headerSize As u32

    If zPath[0] = Asc(".") Then
        pathOffset = 1
        Dim keyStart As u32
        Dim keyLength As u32
        Dim keyIsRaw As SQLITE_C_INT = 1
        If jsonQueryPathByte(zPath, pathOffset) = Asc(Chr(34)) Then
            keyStart = pathOffset + 1
            Dim scanOffset As u32 = keyStart
            While zPath[scanOffset] <> 0 AndAlso _
                  zPath[scanOffset] <> Asc(Chr(34))
                If zPath[scanOffset] = Asc(Chr(92)) AndAlso _
                   zPath[scanOffset + 1] <> 0 Then
                    keyIsRaw = 0
                    scanOffset += 1
                End If
                scanOffset += 1
            Wend
            If zPath[scanOffset] <> Asc(Chr(34)) Then Return JSON_LOOKUP_PATHERROR
            keyLength = scanOffset - keyStart
            pathOffset = scanOffset + 1
        Else
            keyStart = pathOffset
            While zPath[pathOffset] <> 0 AndAlso _
                  zPath[pathOffset] <> Asc(".") AndAlso _
                  zPath[pathOffset] <> Asc("[")
                pathOffset += 1
            Wend
            keyLength = pathOffset - keyStart
            If keyLength = 0 Then Return JSON_LOOKUP_PATHERROR
        End If

        If rootIndex >= pParse->nBlob Then Return JSON_LOOKUP_ERROR
        nodeType = pParse->aBlob[rootIndex] And &HF
        If nodeType <> JSONB_OBJECT Then Return JSON_LOOKUP_NOTFOUND
        headerSize = jsonbPayloadSize(pParse, rootIndex, @payloadSize)
        If headerSize = 0 Then Return JSON_LOOKUP_ERROR
        Dim cursor As sqlite3_uint64 = _
            CULngInt(rootIndex) + CULngInt(headerSize)
        Dim objectEnd As sqlite3_uint64 = cursor + CULngInt(payloadSize)
        Dim availableBytes As u32 = pParse->nBlob
        If pParse->nBlobAlloc > availableBytes Then availableBytes = pParse->nBlobAlloc
        If objectEnd > CULngInt(availableBytes) Then Return JSON_LOOKUP_ERROR

        While cursor < objectEnd
            If cursor > &HFFFFFFFFULL Then Return JSON_LOOKUP_ERROR
            Dim labelOffset As u32 = CUInt(cursor)
            Dim labelType As UByte = pParse->aBlob[labelOffset] And &HF
            If labelType < JSONB_TEXT OrElse labelType > JSONB_TEXTRAW Then _
                Return JSON_LOOKUP_ERROR
            Dim labelSize As u32 = 0
            Dim labelHeader As u32 = jsonbPayloadSizeSemiInline( _
                pParse, labelOffset, @labelSize)
            If labelHeader = 0 Then Return JSON_LOOKUP_ERROR
            Dim labelBytesOffset As sqlite3_uint64 = _
                CULngInt(labelOffset) + CULngInt(labelHeader)
            Dim valueOffset As sqlite3_uint64 = labelBytesOffset + CULngInt(labelSize)
            If valueOffset >= objectEnd Then Return JSON_LOOKUP_ERROR
            If valueOffset > CULngInt(availableBytes) Then Return JSON_LOOKUP_ERROR

            If jsonLabelCompare(zPath + keyStart, keyLength, keyIsRaw, _
                                pParse->aBlob + labelBytesOffset, labelSize, _
                                CInt(labelType = JSONB_TEXT OrElse labelType = JSONB_TEXTRAW)) <> 0 Then
                Dim valueIndex As u32 = CUInt(valueOffset)
                Dim valueType As UByte = pParse->aBlob[valueIndex] And &HF
                If valueType > JSONB_OBJECT Then Return JSON_LOOKUP_ERROR
                Dim valueSize As u32 = 0
                Dim valueHeader As u32 = jsonbPayloadSize(pParse, valueIndex, @valueSize)
                If valueHeader = 0 Then Return JSON_LOOKUP_ERROR
                Dim valueEnd As sqlite3_uint64 = _
                    CULngInt(valueIndex) + CULngInt(valueHeader) + CULngInt(valueSize)
                If valueEnd > objectEnd OrElse valueEnd > CULngInt(availableBytes) Then _
                    Return JSON_LOOKUP_ERROR
                pParse->iLabel = labelOffset
                If pParse->iDepth + 1 >= JSON_MAX_DEPTH Then _
                    Return JSON_LOOKUP_TOODEEP
                pParse->iDepth += 1
                Dim childResult As u32 = jsonLookupStep( _
                    pParse, valueIndex, zPath + pathOffset, labelOffset)
                pParse->iDepth -= 1
                If pParse->delta <> 0 Then _
                    jsonQueryAfterEditSizeAdjust(pParse, rootIndex)
                Return childResult
            End If

            Dim valueIndexAfterLabel As u32 = CUInt(valueOffset)
            Dim valueTypeAfterLabel As UByte = _
                pParse->aBlob[valueIndexAfterLabel] And &HF
            If valueTypeAfterLabel > JSONB_OBJECT Then Return JSON_LOOKUP_ERROR
            Dim valueSizeAfterLabel As u32 = 0
            Dim valueHeaderAfterLabel As u32 = jsonbPayloadSizeSemiInline( _
                pParse, valueIndexAfterLabel, @valueSizeAfterLabel)
            If valueHeaderAfterLabel = 0 Then Return JSON_LOOKUP_ERROR
            cursor = valueOffset + CULngInt(valueHeaderAfterLabel) + _
                     CULngInt(valueSizeAfterLabel)
            If cursor > objectEnd Then Return JSON_LOOKUP_ERROR
        Wend
        If cursor <> objectEnd Then Return JSON_LOOKUP_ERROR
        If pParse->eEdit >= JEDIT_INS Then
            If pParse->eEdit = JEDIT_AINS AndAlso _
               sqlite3_strglob(StrPtr("*]"), _
                    CPtr(Const ZString Ptr, zPath + pathOffset)) <> 0 Then _
                Return JSON_LOOKUP_NOTARRAY

            Dim insertedValue As JsonParse
            Dim labelHeader As JsonParse
            jsonQueryMemset(@insertedValue, 0, SizeOf(insertedValue))
            jsonQueryMemset(@labelHeader, 0, SizeOf(labelHeader))
            labelHeader.db = pParse->db
            jsonBlobAppendNode(@labelHeader, _
                IIf(keyIsRaw <> 0, JSONB_TEXTRAW, JSONB_TEXT5), keyLength, 0)
            pParse->oom = pParse->oom Or labelHeader.oom

            Dim resultCode As u32 = jsonCreateEditSubstructure( _
                pParse, @insertedValue, CPtr(Const UByte Ptr, zPath + pathOffset))
            Dim requiredSize As sqlite3_uint64 = _
                CULngInt(labelHeader.nBlob) + CULngInt(keyLength) + _
                CULngInt(insertedValue.nBlob)
            If requiredSize > SQLITE_MAX_ALLOCATION_SIZE Then
                pParse->oom = 1
            ElseIf JSON_LOOKUP_ISERROR(resultCode) = 0 AndAlso _
                   jsonBlobMakeEditable(pParse, CUInt(requiredSize)) <> 0 Then
                jsonQueryBlobEdit(pParse, CUInt(cursor), 0, 0, CUInt(requiredSize))
                If pParse->oom = 0 Then
                    jsonQueryMemcpy(@pParse->aBlob[CUInt(cursor)], _
                        labelHeader.aBlob, labelHeader.nBlob)
                    Dim keyOutput As u32 = CUInt(cursor) + labelHeader.nBlob
                    jsonQueryMemcpy(@pParse->aBlob[keyOutput], _
                        zPath + keyStart, keyLength)
                    keyOutput += keyLength
                    If insertedValue.nBlob > 0 Then _
                        jsonQueryMemcpy(@pParse->aBlob[keyOutput], _
                            insertedValue.aBlob, insertedValue.nBlob)
                    If pParse->delta <> 0 Then _
                        jsonQueryAfterEditSizeAdjust(pParse, rootIndex)
                End If
            End If
            jsonParseReset(@insertedValue)
            jsonParseReset(@labelHeader)
            Return resultCode
        End If
        Return JSON_LOOKUP_NOTFOUND

    ElseIf zPath[0] = Asc("[") Then
        If rootIndex >= pParse->nBlob Then Return JSON_LOOKUP_ERROR
        nodeType = pParse->aBlob[rootIndex] And &HF
        If nodeType <> JSONB_ARRAY Then Return JSON_LOOKUP_NOTFOUND
        headerSize = jsonbPayloadSize(pParse, rootIndex, @payloadSize)
        If headerSize = 0 Then Return JSON_LOOKUP_ERROR

        Dim arrayIndex As sqlite3_uint64 = 0
        pathOffset = 1
        While jsonQueryDigit(zPath[pathOffset]) <> 0
            If arrayIndex < &HFFFFFFFFULL Then _
                arrayIndex = arrayIndex * 10 + CULng(zPath[pathOffset] - Asc("0"))
            pathOffset += 1
        Wend
        If pathOffset < 2 OrElse zPath[pathOffset] <> Asc("]") Then
            If zPath[1] <> Asc("#") Then Return JSON_LOOKUP_PATHERROR
            arrayIndex = jsonbArrayCount(pParse, rootIndex)
            pathOffset = 2
            If zPath[pathOffset] = Asc("-") AndAlso _
               jsonQueryDigit(zPath[pathOffset + 1]) <> 0 Then
                Dim fromEnd As sqlite3_uint64 = 0
                pathOffset = 3
                Do While jsonQueryDigit(zPath[pathOffset]) <> 0
                    If fromEnd < &HFFFFFFFFULL Then _
                        fromEnd = fromEnd * 10 + CULng(zPath[pathOffset] - Asc("0"))
                    pathOffset += 1
                Loop
                If fromEnd > arrayIndex Then Return JSON_LOOKUP_NOTFOUND
                arrayIndex -= fromEnd
            End If
            If zPath[pathOffset] <> Asc("]") Then Return JSON_LOOKUP_PATHERROR
        End If

        Dim cursor As sqlite3_uint64 = _
            CULngInt(rootIndex) + CULngInt(headerSize)
        Dim arrayEnd As sqlite3_uint64 = cursor + CULngInt(payloadSize)
        Dim availableBytes As u32 = pParse->nBlob
        If pParse->nBlobAlloc > availableBytes Then availableBytes = pParse->nBlobAlloc
        If arrayEnd > CULngInt(availableBytes) Then Return JSON_LOOKUP_ERROR
        While cursor < arrayEnd
            If cursor > &HFFFFFFFFULL Then Return JSON_LOOKUP_ERROR
            If arrayIndex = 0 Then
                If pParse->iDepth + 1 >= JSON_MAX_DEPTH Then _
                    Return JSON_LOOKUP_TOODEEP
                pParse->iDepth += 1
                Dim childResult As u32 = jsonLookupStep( _
                    pParse, CUInt(cursor), zPath + pathOffset + 1, 0)
                pParse->iDepth -= 1
                If pParse->delta <> 0 Then _
                    jsonQueryAfterEditSizeAdjust(pParse, rootIndex)
                Return childResult
            End If
            arrayIndex -= 1
            Dim childSize As u32 = 0
            Dim childHeader As u32 = jsonbPayloadSizeSemiInline( _
                pParse, CUInt(cursor), @childSize)
            If childHeader = 0 Then Return JSON_LOOKUP_ERROR
            cursor += CULngInt(childHeader) + CULngInt(childSize)
            If cursor > arrayEnd Then Return JSON_LOOKUP_ERROR
        Wend
        If cursor <> arrayEnd Then Return JSON_LOOKUP_ERROR
        If arrayIndex > 0 Then Return JSON_LOOKUP_NOTFOUND
        If pParse->eEdit >= JEDIT_INS Then
            Dim insertedValue As JsonParse
            jsonQueryMemset(@insertedValue, 0, SizeOf(insertedValue))
            Dim resultCode As u32 = jsonCreateEditSubstructure( _
                pParse, @insertedValue, _
                CPtr(Const UByte Ptr, zPath + pathOffset + 1))
            If JSON_LOOKUP_ISERROR(resultCode) = 0 AndAlso _
               jsonBlobMakeEditable(pParse, insertedValue.nBlob) <> 0 Then
                jsonQueryBlobEdit(pParse, CUInt(cursor), 0, _
                    insertedValue.aBlob, insertedValue.nBlob)
                If pParse->delta <> 0 Then _
                    jsonQueryAfterEditSizeAdjust(pParse, rootIndex)
            End If
            jsonParseReset(@insertedValue)
            Return resultCode
        End If
        Return JSON_LOOKUP_NOTFOUND
    End If
    Return JSON_LOOKUP_PATHERROR
End Function

Sub jsonArrayLengthFunc CDecl Alias "jsonArrayLengthFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
) Export
    If pContext = 0 OrElse pArguments = 0 OrElse _
       (argumentCount <> 1 AndAlso argumentCount <> 2) Then Return
    Dim pParse As JsonParse Ptr = jsonParseFuncArg(pContext, pArguments[0], 0)
    If pParse = 0 Then Return

    Dim errorSeen As SQLITE_C_INT = 0
    Dim nodeIndex As u32 = 0
    If argumentCount = 2 Then
        Dim zPath As Const UByte Ptr = CPtr(Const UByte Ptr, _
            sqlite3_value_text(pArguments[1]))
        If zPath = 0 Then
            jsonParseFree(pParse)
            Return
        End If
        If zPath[0] = Asc("$") Then
            nodeIndex = jsonLookupStep(pParse, 0, zPath + 1, 0)
        Else
            nodeIndex = jsonLookupStep(pParse, 0, StrPtr("@"), 0)
        End If
        If JSON_LOOKUP_ISERROR(nodeIndex) Then
            If nodeIndex <> JSON_LOOKUP_NOTFOUND Then _
                jsonBadPathError(pContext, zPath, nodeIndex)
            errorSeen = 1
            nodeIndex = 0
        End If
    End If

    Dim arrayLength As sqlite3_int64 = 0
    If errorSeen = 0 AndAlso nodeIndex < pParse->nBlob AndAlso _
       (pParse->aBlob[nodeIndex] And &HF) = JSONB_ARRAY Then
        arrayLength = jsonbArrayCount(pParse, nodeIndex)
    End If
    If errorSeen = 0 Then sqlite3_result_int64(pContext, arrayLength)
    jsonParseFree(pParse)
End Sub

Sub jsonTypeFunc CDecl Alias "jsonTypeFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
) Export
    If pContext = 0 OrElse pArguments = 0 OrElse _
       (argumentCount <> 1 AndAlso argumentCount <> 2) Then Return
    Dim pParse As JsonParse Ptr = jsonParseFuncArg(pContext, pArguments[0], 0)
    If pParse = 0 Then Return

    Dim nodeIndex As u32 = 0
    If argumentCount = 2 Then
        Dim zPath As Const UByte Ptr = CPtr(Const UByte Ptr, _
            sqlite3_value_text(pArguments[1]))
        If zPath = 0 Then
            jsonParseFree(pParse)
            Return
        End If
        If zPath[0] <> Asc("$") Then
            jsonBadPathError(pContext, zPath, 0)
            jsonParseFree(pParse)
            Return
        End If
        nodeIndex = jsonLookupStep(pParse, 0, zPath + 1, 0)
        If JSON_LOOKUP_ISERROR(nodeIndex) Then
            If nodeIndex <> JSON_LOOKUP_NOTFOUND Then _
                jsonBadPathError(pContext, zPath, nodeIndex)
            jsonParseFree(pParse)
            Return
        End If
    End If

    If nodeIndex >= pParse->nBlob Then
        jsonBadPathError(pContext, 0, JSON_LOOKUP_ERROR)
        jsonParseFree(pParse)
        Return
    End If
    Dim typeName As Const ZString Ptr
    Select Case pParse->aBlob[nodeIndex] And &HF
    Case JSONB_NULL: typeName = StrPtr("null")
    Case JSONB_TRUE: typeName = StrPtr("true")
    Case JSONB_FALSE: typeName = StrPtr("false")
    Case JSONB_INT, JSONB_INT5: typeName = StrPtr("integer")
    Case JSONB_FLOAT, JSONB_FLOAT5: typeName = StrPtr("real")
    Case JSONB_TEXT, JSONB_TEXTJ, JSONB_TEXT5, JSONB_TEXTRAW
        typeName = StrPtr("text")
    Case JSONB_ARRAY: typeName = StrPtr("array")
    Case JSONB_OBJECT: typeName = StrPtr("object")
    Case Else: typeName = StrPtr("")
    End Select
    sqlite3_result_text(pContext, typeName, -1, 0)
    jsonParseFree(pParse)
End Sub

/' end of sqlite3_json_query.bas '/
