/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_text_parse.bas

    Purpose:

        Translate JSON and JSON5 text values into SQLite JSONB nodes.

    Responsibilities:

        - Parse strings, numbers, keywords, arrays, objects, and delimiters.
        - Preserve JSON5 extensions and record when they were used.
        - Build compact JSONB using the parse state's node-buffer operations.
        - Return the parser's delimiter and error codes to its callers.

    This file intentionally does NOT contain:

        - SQL JSON function registration, JSON path evaluation, or JSONB-to-text conversion.
'/ 

#lang "fb"
#include once "sqlite3_json_parse.bi"
#include once "sqlite3_json_string.bi"

Declare Function sqlite3IsIdChar CDecl Alias "sqlite3IsIdChar" (ByVal value As UByte) As SQLITE_C_INT
Declare Sub sqlite3_result_error CDecl Alias "sqlite3_result_error" (ByVal pContext As Any Ptr, ByVal zError As Const ZString Ptr, ByVal nByte As SQLITE_C_INT)
Declare Sub sqlite3_result_error_nomem CDecl Alias "sqlite3_result_error_nomem" (ByVal pContext As Any Ptr)

Private Const JSON_PARSE_OBJECT_END As SQLITE_C_INT = -2
Private Const JSON_PARSE_ARRAY_END As SQLITE_C_INT = -3
Private Const JSON_PARSE_LIST_SEPARATOR As SQLITE_C_INT = -4
Private Const JSON_PARSE_OBJECT_SEPARATOR As SQLITE_C_INT = -5

Private Function jsonParseByte( _
    ByVal pParse As JsonParse Ptr, _
    ByVal index As u32 _
) As UByte
    If pParse = 0 OrElse pParse->zJson = 0 OrElse _
       index >= CUInt(pParse->nJson) Then Return 0
    Return CPtr(Const UByte Ptr, pParse->zJson)[index]
End Function

Private Function jsonParseIsDigit(ByVal value As UByte) As SQLITE_C_INT
    Return CInt(value >= Asc("0") AndAlso value <= Asc("9"))
End Function

Private Function jsonParseIsHexDigit(ByVal value As UByte) As SQLITE_C_INT
    If jsonParseIsDigit(value) <> 0 Then Return 1
    If value >= Asc("A") AndAlso value <= Asc("F") Then Return 1
    If value >= Asc("a") AndAlso value <= Asc("f") Then Return 1
    Return 0
End Function

Private Function jsonParseIsAlnum(ByVal value As UByte) As SQLITE_C_INT
    If jsonParseIsDigit(value) <> 0 Then Return 1
    If value >= Asc("A") AndAlso value <= Asc("Z") Then Return 1
    If value >= Asc("a") AndAlso value <= Asc("z") Then Return 1
    Return 0
End Function

Private Function jsonParseIsCWhitespace(ByVal value As UByte) As SQLITE_C_INT
    Return CInt((value >= 9 AndAlso value <= 13) OrElse value = 32)
End Function

Private Function jsonParseIsJsonSpace(ByVal value As UByte) As SQLITE_C_INT
    Return CInt(value = 9 OrElse value = 10 OrElse value = 13 OrElse value = 32)
End Function

Private Function jsonParseIsIdentifierStart(ByVal value As UByte) As SQLITE_C_INT
    If sqlite3IsIdChar(value) = 0 Then Return 0
    Return CInt(jsonParseIsDigit(value) = 0)
End Function

Private Function jsonParseHexAt( _
    ByVal pParse As JsonParse Ptr, _
    ByVal index As u32, _
    ByVal digitCount As u32 _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->nJson < 0 OrElse _
       index > CUInt(pParse->nJson) OrElse _
       digitCount > CUInt(pParse->nJson) - index Then Return 0
    For offset As u32 = 0 To digitCount - 1
        If jsonParseIsHexDigit(jsonParseByte(pParse, index + offset)) = 0 Then Return 0
    Next
    Return 1
End Function

Private Function jsonParseHexEscapeAt( _
    ByVal pParse As JsonParse Ptr, _
    ByVal slashOffset As u32, _
    ByRef nodeType As u8 _
) As SQLITE_C_INT
    If jsonParseByte(pParse, slashOffset) <> Asc(Chr(92)) Then Return 0
    Dim uOffset As u32 = slashOffset + 1
    If jsonParseByte(pParse, uOffset) <> Asc("u") OrElse _
       jsonParseHexAt(pParse, uOffset + 1, 4) = 0 Then Return 0
    nodeType = JSONB_TEXTJ
    Return 1
End Function

Private Function jsonParseSkipJsonSpace( _
    ByVal pParse As JsonParse Ptr, _
    ByVal startOffset As u32 _
) As u32
    Dim offset As u32 = startOffset
    While jsonParseIsJsonSpace(jsonParseByte(pParse, offset)) <> 0
        offset += 1
    Wend
    Return offset
End Function

Private Function jsonParseAsciiEqualNoCase( _
    ByVal pParse As JsonParse Ptr, _
    ByVal startOffset As u32, _
    ByVal zExpected As Const ZString Ptr, _
    ByVal expectedLength As SQLITE_C_INT _
) As SQLITE_C_INT
    If pParse = 0 OrElse zExpected = 0 OrElse expectedLength < 0 OrElse _
       pParse->nJson < 0 OrElse startOffset > CUInt(pParse->nJson) OrElse _
       CUInt(expectedLength) > CUInt(pParse->nJson) - startOffset Then Return 0
    Dim expectedBytes As Const UByte Ptr = CPtr(Const UByte Ptr, zExpected)
    For index As SQLITE_C_INT = 0 To expectedLength - 1
        Dim actualByte As UByte = jsonParseByte(pParse, startOffset + CUInt(index))
        Dim expectedByte As UByte = expectedBytes[index]
        If actualByte >= Asc("A") AndAlso actualByte <= Asc("Z") Then _
            actualByte += Asc("a") - Asc("A")
        If expectedByte >= Asc("A") AndAlso expectedByte <= Asc("Z") Then _
            expectedByte += Asc("a") - Asc("A")
        If actualByte <> expectedByte Then Return 0
    Next
    Return 1
End Function

Private Function jsonParseAsciiEqual( _
    ByVal pParse As JsonParse Ptr, _
    ByVal startOffset As u32, _
    ByVal zExpected As Const ZString Ptr, _
    ByVal expectedLength As SQLITE_C_INT _
) As SQLITE_C_INT
    If pParse = 0 OrElse zExpected = 0 OrElse expectedLength < 0 OrElse _
       pParse->nJson < 0 OrElse startOffset > CUInt(pParse->nJson) OrElse _
       CUInt(expectedLength) > CUInt(pParse->nJson) - startOffset Then Return 0
    Dim expectedBytes As Const UByte Ptr = CPtr(Const UByte Ptr, zExpected)
    For index As SQLITE_C_INT = 0 To expectedLength - 1
        If jsonParseByte(pParse, startOffset + CUInt(index)) <> _
           expectedBytes[index] Then Return 0
    Next
    Return 1
End Function

Private Function jsonParseSpecialWord( _
    ByVal pParse As JsonParse Ptr, _
    ByVal startOffset As u32 _
) As SQLITE_C_INT
    If pParse = 0 Then Return 0
    Dim firstByte As UByte = jsonParseByte(pParse, startOffset)
    Dim matchLength As SQLITE_C_INT = 0
    Dim isInfinity As SQLITE_C_INT = 0
    Select Case firstByte
    Case Asc("i"), Asc("I")
        If jsonParseAsciiEqualNoCase(pParse, startOffset, StrPtr("infinity"), 8) <> 0 Then
            matchLength = 8
        ElseIf jsonParseAsciiEqualNoCase(pParse, startOffset, StrPtr("inf"), 3) <> 0 Then
            matchLength = 3
        End If
        isInfinity = 1
    Case Asc("n"), Asc("N")
        If jsonParseAsciiEqualNoCase(pParse, startOffset, StrPtr("nan"), 3) <> 0 Then matchLength = 3
    Case Asc("q"), Asc("Q")
        If jsonParseAsciiEqualNoCase(pParse, startOffset, StrPtr("qnan"), 4) <> 0 Then matchLength = 4
    Case Asc("s"), Asc("S")
        If jsonParseAsciiEqualNoCase(pParse, startOffset, StrPtr("snan"), 4) <> 0 Then matchLength = 4
    End Select
    If matchLength = 0 OrElse _
       jsonParseIsAlnum(jsonParseByte(pParse, startOffset + CUInt(matchLength))) <> 0 Then _
        Return 0

    If isInfinity <> 0 Then
        jsonBlobAppendNode(pParse, JSONB_FLOAT, 5, CPtr(Const Any Ptr, StrPtr("9e999")))
    Else
        jsonBlobAppendOneByte(pParse, JSONB_NULL)
    End If
    pParse->hasNonstd = 1
    If pParse->oom <> 0 Then
        pParse->iErr = startOffset
        Return -1
    End If
    Return CInt(startOffset + CUInt(matchLength))
End Function

Private Function jsonParseQuotedString( _
    ByVal pParse As JsonParse Ptr, _
    ByVal startOffset As u32, _
    ByVal delimiter As UByte _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->zJson = 0 OrElse _
       pParse->nJson < 0 OrElse startOffset >= CUInt(pParse->nJson) Then Return -1
    Dim nodeType As u8 = JSONB_TEXT
    Dim offset As u32 = startOffset + 1
    While offset < CUInt(pParse->nJson)
        Dim currentByte As UByte = jsonParseByte(pParse, offset)
        If currentByte = delimiter Then
            jsonBlobAppendNode(pParse, nodeType, offset - startOffset - 1, _
                CPtr(Const Any Ptr, CPtr(Const UByte Ptr, pParse->zJson) + startOffset + 1))
            If pParse->oom <> 0 Then
                pParse->iErr = offset
                Return -1
            End If
            Return CInt(offset + 1)
        ElseIf currentByte = Asc(Chr(92)) Then
            offset += 1
            If offset >= CUInt(pParse->nJson) Then
                pParse->iErr = offset
                Return -1
            End If
            currentByte = jsonParseByte(pParse, offset)
            If currentByte = Asc(Chr(34)) OrElse currentByte = Asc(Chr(92)) OrElse _
               currentByte = Asc("/") OrElse currentByte = Asc("b") OrElse _
               currentByte = Asc("f") OrElse currentByte = Asc("n") OrElse _
               currentByte = Asc("r") OrElse currentByte = Asc("t") OrElse _
               (currentByte = Asc("u") AndAlso _
                jsonParseHexAt(pParse, offset + 1, 4) <> 0) Then
                If nodeType = JSONB_TEXT Then nodeType = JSONB_TEXTJ
        ElseIf currentByte = Asc("'") OrElse currentByte = Asc("v") OrElse _
               currentByte = Asc("0") OrElse currentByte = 10 Then
#ifdef SQLITE_BUG_COMPATIBLE_20250510
                Dim legacyZeroEscape As SQLITE_C_INT = CInt(currentByte = Asc("0"))
#else
                Dim legacyZeroEscape As SQLITE_C_INT = CInt( _
                    currentByte = Asc("0") AndAlso _
                    jsonParseIsDigit(jsonParseByte(pParse, offset + 1)) = 0)
#endif
                If legacyZeroEscape <> 0 OrElse currentByte = Asc("'") OrElse _
                   currentByte = Asc("v") OrElse currentByte = 10 Then
                    nodeType = JSONB_TEXT5
                    pParse->hasNonstd = 1
                Else
                    pParse->iErr = offset
                    Return -1
                End If
            ElseIf currentByte = &HE2 AndAlso _
                   jsonParseByte(pParse, offset + 1) = &H80 AndAlso _
                   (jsonParseByte(pParse, offset + 2) = &HA8 OrElse _
                    jsonParseByte(pParse, offset + 2) = &HA9) Then
                nodeType = JSONB_TEXT5
                pParse->hasNonstd = 1
            ElseIf currentByte = Asc("x") AndAlso _
                   jsonParseHexAt(pParse, offset + 1, 2) <> 0 Then
                nodeType = JSONB_TEXT5
                pParse->hasNonstd = 1
            ElseIf currentByte = 13 Then
                If jsonParseByte(pParse, offset + 1) = 10 Then offset += 1
                nodeType = JSONB_TEXT5
                pParse->hasNonstd = 1
            Else
                pParse->iErr = offset
                Return -1
            End If
        ElseIf currentByte <= &H1F Then
            If currentByte = 0 Then
                pParse->iErr = offset
                Return -1
            End If
            nodeType = JSONB_TEXT5
            pParse->hasNonstd = 1
        ElseIf currentByte = Asc(Chr(34)) Then
            nodeType = JSONB_TEXT5
        End If
        offset += 1
    Wend
    pParse->iErr = offset
    Return -1
End Function

Private Function jsonParseNumber( _
    ByVal pParse As JsonParse Ptr, _
    ByVal startOffset As u32 _
) As SQLITE_C_INT
    If pParse = 0 Then Return -1
    Dim firstByte As UByte = jsonParseByte(pParse, startOffset)
    Dim nextByte As UByte = jsonParseByte(pParse, startOffset + 1)
    Dim flags As u8 = 0
    Dim seenExponent As u8 = 0
    Dim scanOffset As u32 = startOffset + 1
    Dim hasHexPrefix As SQLITE_C_INT = 0

    If firstByte = Asc(".") Then
        If jsonParseIsDigit(nextByte) = 0 Then
            pParse->iErr = startOffset
            Return -1
        End If
        pParse->hasNonstd = 1
        flags = &H03
    ElseIf firstByte = Asc("+") Then
        pParse->hasNonstd = 1
    End If

    If firstByte = Asc("0") Then
        Dim hexMarker As UByte = jsonParseByte(pParse, startOffset + 1)
        If (hexMarker = Asc("x") OrElse hexMarker = Asc("X")) AndAlso _
           jsonParseHexAt(pParse, startOffset + 2, 1) <> 0 Then
            pParse->hasNonstd = 1
            flags = &H01
            scanOffset = startOffset + 3
            hasHexPrefix = 1
        ElseIf jsonParseIsDigit(nextByte) <> 0 Then
            pParse->iErr = startOffset + 1
            Return -1
        End If
    ElseIf firstByte = Asc("-") OrElse firstByte = Asc("+") Then
        If jsonParseIsDigit(nextByte) = 0 Then
            If (nextByte = Asc("i") OrElse nextByte = Asc("I")) AndAlso _
               jsonParseAsciiEqualNoCase(pParse, startOffset + 1, StrPtr("inf"), 3) <> 0 Then
                pParse->hasNonstd = 1
                If firstByte = Asc("-") Then
                    jsonBlobAppendNode(pParse, JSONB_FLOAT, 6, _
                                       CPtr(Const Any Ptr, StrPtr("-9e999")))
                Else
                    jsonBlobAppendNode(pParse, JSONB_FLOAT, 5, _
                                       CPtr(Const Any Ptr, StrPtr("9e999")))
                End If
                If pParse->oom <> 0 Then
                    pParse->iErr = startOffset
                    Return -1
                End If
                Dim infinityLength As SQLITE_C_INT = 4
                If jsonParseAsciiEqualNoCase(pParse, startOffset + 4, _
                                             StrPtr("inity"), 5) <> 0 Then _
                    infinityLength = 9
                Return CInt(startOffset + CUInt(infinityLength))
            End If
            If nextByte = Asc(".") Then
                pParse->hasNonstd = 1
                flags = flags Or &H01
            Else
                pParse->iErr = startOffset
                Return -1
            End If
        End If

        If nextByte = Asc("0") Then
            Dim thirdByte As UByte = jsonParseByte(pParse, startOffset + 2)
            If jsonParseIsDigit(thirdByte) <> 0 Then
                pParse->iErr = startOffset + 1
                Return -1
            End If
            Dim hexMarker As UByte = thirdByte
            If (hexMarker = Asc("x") OrElse hexMarker = Asc("X")) AndAlso _
               jsonParseHexAt(pParse, startOffset + 3, 1) <> 0 Then
                pParse->hasNonstd = 1
                flags = flags Or &H01
                scanOffset = startOffset + 4
                hasHexPrefix = 1
            End If
        End If
    End If

    If hasHexPrefix <> 0 Then
        While jsonParseIsHexDigit(jsonParseByte(pParse, scanOffset)) <> 0
            scanOffset += 1
        Wend
    Else
        While scanOffset <= CUInt(pParse->nJson)
            Dim currentByte As UByte = jsonParseByte(pParse, scanOffset)
            If jsonParseIsDigit(currentByte) <> 0 Then
                scanOffset += 1
                Continue While
            End If
            If currentByte = Asc(".") Then
                If (flags And &H02) <> 0 Then
                    pParse->iErr = scanOffset
                    Return -1
                End If
                flags = flags Or &H02
                scanOffset += 1
                Continue While
            End If
            If currentByte = Asc("e") OrElse currentByte = Asc("E") Then
                Dim previousByte As UByte = jsonParseByte(pParse, scanOffset - 1)
                If previousByte < Asc("0") Then
                    If previousByte = Asc(".") AndAlso scanOffset >= startOffset + 2 AndAlso _
                       jsonParseIsDigit(jsonParseByte(pParse, scanOffset - 2)) <> 0 Then
                        pParse->hasNonstd = 1
                        flags = flags Or &H01
                    Else
                        pParse->iErr = scanOffset
                        Return -1
                    End If
                End If
                If seenExponent <> 0 OrElse scanOffset + 1 > CUInt(pParse->nJson) Then
                    pParse->iErr = scanOffset
                    Return -1
                End If
                flags = flags Or &H02
                seenExponent = 1
                Dim exponentByte As UByte = jsonParseByte(pParse, scanOffset + 1)
                If exponentByte = Asc("+") OrElse exponentByte = Asc("-") Then
                    scanOffset += 1
                    exponentByte = jsonParseByte(pParse, scanOffset + 1)
                End If
                If exponentByte < Asc("0") OrElse exponentByte > Asc("9") Then
                    pParse->iErr = scanOffset
                    Return -1
                End If
                scanOffset += 1
                Continue While
            End If
            Exit While
        Wend

        Dim lastByte As UByte = jsonParseByte(pParse, scanOffset - 1)
        If lastByte < Asc("0") Then
            If lastByte = Asc(".") AndAlso scanOffset >= startOffset + 2 AndAlso _
               jsonParseIsDigit(jsonParseByte(pParse, scanOffset - 2)) <> 0 Then
                pParse->hasNonstd = 1
                flags = flags Or &H01
            Else
                pParse->iErr = scanOffset
                Return -1
            End If
        End If
    End If

    Dim payloadStart As u32 = startOffset
    If firstByte = Asc("+") Then payloadStart += 1
    jsonBlobAppendNode(pParse, CByte(JSONB_INT + flags), _
                       scanOffset - payloadStart, _
                       CPtr(Const Any Ptr, CPtr(Const UByte Ptr, pParse->zJson) + payloadStart))
    If pParse->oom <> 0 Then
        pParse->iErr = startOffset
        Return -1
    End If
    Return CInt(scanOffset)
End Function

Private Function jsonTranslateArray( _
    ByVal pParse As JsonParse Ptr, _
    ByVal startOffset As u32 _
) As SQLITE_C_INT
    Dim nodeOffset As u32 = pParse->nBlob
    jsonBlobAppendNode(pParse, JSONB_ARRAY, _
                       CULngInt(pParse->nJson) - startOffset, 0)
    If pParse->oom <> 0 Then Return -1
    Dim payloadStart As u32 = pParse->nBlob
    pParse->iDepth += 1
    If pParse->iDepth > JSON_MAX_DEPTH Then
        pParse->iErr = startOffset
        Return -1
    End If

    Dim offset As u32 = startOffset + 1
    Dim closed As SQLITE_C_INT = 0
    While closed = 0
        Dim result As SQLITE_C_INT = jsonTranslateTextToBlob(pParse, offset)
        If result <= 0 Then
            If result = JSON_PARSE_ARRAY_END Then
                offset = pParse->iErr
                If pParse->nBlob <> payloadStart Then pParse->hasNonstd = 1
                closed = 1
                Exit While
            End If
            If result <> -1 Then pParse->iErr = offset
            Return -1
        End If
        offset = CUInt(result)

        If jsonParseByte(pParse, offset) = Asc(",") Then
            offset += 1
            Continue While
        End If
        If jsonParseByte(pParse, offset) = Asc("]") Then
            closed = 1
            Exit While
        End If

        If jsonParseIsCWhitespace(jsonParseByte(pParse, offset)) <> 0 Then
            offset += 1
            While jsonParseIsJsonSpace(jsonParseByte(pParse, offset)) <> 0
                offset += 1
            Wend
            If jsonParseByte(pParse, offset) = Asc(",") Then
                offset += 1
                Continue While
            End If
            If jsonParseByte(pParse, offset) = Asc("]") Then
                closed = 1
                Exit While
            End If
        End If

        result = jsonTranslateTextToBlob(pParse, offset)
        If result = JSON_PARSE_LIST_SEPARATOR Then
            offset = pParse->iErr + 1
            Continue While
        End If
        If result = JSON_PARSE_ARRAY_END Then
            offset = pParse->iErr
            closed = 1
            Exit While
        End If
        pParse->iErr = offset
        Return -1
    Wend

    jsonBlobChangePayloadSize(pParse, nodeOffset, pParse->nBlob - payloadStart)
    pParse->iDepth -= 1
    If pParse->oom <> 0 Then Return -1
    Return CInt(offset + 1)
End Function

Private Function jsonTranslateObject( _
    ByVal pParse As JsonParse Ptr, _
    ByVal startOffset As u32 _
) As SQLITE_C_INT
    Dim nodeOffset As u32 = pParse->nBlob
    jsonBlobAppendNode(pParse, JSONB_OBJECT, _
                       CULngInt(pParse->nJson) - startOffset, 0)
    If pParse->oom <> 0 Then Return -1
    Dim payloadStart As u32 = pParse->nBlob
    pParse->iDepth += 1
    If pParse->iDepth > JSON_MAX_DEPTH Then
        pParse->iErr = startOffset
        Return -1
    End If

    Dim offset As u32 = startOffset + 1
    Dim closed As SQLITE_C_INT = 0
    While closed = 0
        Dim keyBlobOffset As u32 = pParse->nBlob
        Dim result As SQLITE_C_INT = jsonTranslateTextToBlob(pParse, offset)
        If result <= 0 Then
            If result = JSON_PARSE_OBJECT_END Then
                offset = pParse->iErr
                If pParse->nBlob <> payloadStart Then pParse->hasNonstd = 1
                closed = 1
                Exit While
            End If

            Dim keyStart As u32 = offset + _
                CUInt(json5Whitespace(CPtr(Const UByte Ptr, pParse->zJson) + offset))
            Dim operation As u8 = JSONB_TEXT
            Dim currentByte As UByte = jsonParseByte(pParse, keyStart)
            If jsonParseIsIdentifierStart(currentByte) <> 0 OrElse _
               jsonParseHexEscapeAt(pParse, keyStart, operation) <> 0 Then
                Dim keyEnd As u32 = keyStart
                While True
                    currentByte = jsonParseByte(pParse, keyEnd)
                    If (sqlite3IsIdChar(currentByte) <> 0 AndAlso _
                        json5Whitespace(CPtr(Const UByte Ptr, pParse->zJson) + keyEnd) = 0) OrElse _
                       jsonParseHexEscapeAt(pParse, keyEnd, operation) <> 0 Then
                        keyEnd += 1
                    Else
                        Exit While
                    End If
                Wend
                If keyEnd = keyStart Then
                    pParse->iErr = keyStart
                    Return -1
                End If
                jsonBlobAppendNode(pParse, operation, keyEnd - keyStart, _
                    CPtr(Const Any Ptr, CPtr(Const UByte Ptr, pParse->zJson) + keyStart))
                pParse->hasNonstd = 1
                result = CInt(keyEnd)
            Else
                If result <> -1 Then pParse->iErr = keyStart
                Return -1
            End If
        End If
        If pParse->oom <> 0 Then Return -1
        If keyBlobOffset >= pParse->nBlob Then
            pParse->iErr = offset
            Return -1
        End If
        Dim keyType As UByte = pParse->aBlob[keyBlobOffset] And &HF
        If keyType < JSONB_TEXT OrElse keyType > JSONB_TEXTRAW Then
            pParse->iErr = offset
            Return -1
        End If
        offset = CUInt(result)

        If jsonParseByte(pParse, offset) = Asc(":") Then
            offset += 1
        Else
            If jsonParseIsCWhitespace(jsonParseByte(pParse, offset)) <> 0 Then
                offset += 1
                While jsonParseIsCWhitespace(jsonParseByte(pParse, offset)) <> 0
                    offset += 1
                Wend
                If jsonParseByte(pParse, offset) = Asc(":") Then
                    offset += 1
                Else
                    result = jsonTranslateTextToBlob(pParse, offset)
                    If result <> JSON_PARSE_OBJECT_SEPARATOR Then
                        If result <> -1 Then pParse->iErr = offset
                        Return -1
                    End If
                    offset = pParse->iErr + 1
                End If
            Else
                result = jsonTranslateTextToBlob(pParse, offset)
                If result <> JSON_PARSE_OBJECT_SEPARATOR Then
                    If result <> -1 Then pParse->iErr = offset
                    Return -1
                End If
                offset = pParse->iErr + 1
            End If
        End If

        result = jsonTranslateTextToBlob(pParse, offset)
        If result <= 0 Then
            If result <> -1 Then pParse->iErr = offset
            Return -1
        End If
        offset = CUInt(result)
        If jsonParseByte(pParse, offset) = Asc(",") Then
            offset += 1
            Continue While
        End If
        If jsonParseByte(pParse, offset) = Asc("}") Then
            closed = 1
            Exit While
        End If

        If jsonParseIsCWhitespace(jsonParseByte(pParse, offset)) <> 0 Then
            offset += 1
            While jsonParseIsJsonSpace(jsonParseByte(pParse, offset)) <> 0
                offset += 1
            Wend
            If jsonParseByte(pParse, offset) = Asc(",") Then
                offset += 1
                Continue While
            End If
            If jsonParseByte(pParse, offset) = Asc("}") Then
                closed = 1
                Exit While
            End If
        End If

        result = jsonTranslateTextToBlob(pParse, offset)
        If result = JSON_PARSE_LIST_SEPARATOR Then
            offset = pParse->iErr + 1
            Continue While
        End If
        If result = JSON_PARSE_OBJECT_END Then
            offset = pParse->iErr
            closed = 1
            Exit While
        End If
        pParse->iErr = offset
        Return -1
    Wend

    jsonBlobChangePayloadSize(pParse, nodeOffset, pParse->nBlob - payloadStart)
    pParse->iDepth -= 1
    If pParse->oom <> 0 Then Return -1
    Return CInt(offset + 1)
End Function

Function jsonTranslateTextToBlob CDecl Alias "jsonTranslateTextToBlob" ( _
    ByVal pParse As JsonParse Ptr, _
    ByVal startOffset As u32 _
) As SQLITE_C_INT Export
    If pParse = 0 OrElse pParse->zJson = 0 OrElse pParse->nJson < 0 Then Return -1
    If startOffset > CUInt(pParse->nJson) Then Return 0

    Dim offset As u32 = startOffset
    Dim currentByte As UByte
    While True
        currentByte = jsonParseByte(pParse, offset)
        If jsonParseIsJsonSpace(currentByte) <> 0 Then
            offset = jsonParseSkipJsonSpace(pParse, offset)
        ElseIf currentByte = 11 OrElse currentByte = 12 OrElse _
               currentByte = Asc("/") OrElse currentByte = &HC2 OrElse _
               currentByte = &HE1 OrElse currentByte = &HE2 OrElse _
               currentByte = &HE3 OrElse currentByte = &HEF Then
            Dim whitespaceBytes As SQLITE_C_INT = json5Whitespace( _
                CPtr(Const UByte Ptr, pParse->zJson) + offset)
            If whitespaceBytes <= 0 Then
                pParse->iErr = offset
                Return -1
            End If
            pParse->hasNonstd = 1
            offset += CUInt(whitespaceBytes)
        Else
            Exit While
        End If
        If offset >= CUInt(pParse->nJson) Then Return 0
    Wend

    currentByte = jsonParseByte(pParse, offset)
    Select Case currentByte
    Case Asc("{")
        Return jsonTranslateObject(pParse, offset)
    Case Asc("[")
        Return jsonTranslateArray(pParse, offset)
    Case Asc("'"), Asc(Chr(34))
        If currentByte = Asc("'") Then pParse->hasNonstd = 1
        Return jsonParseQuotedString(pParse, offset, currentByte)
    Case Asc("t")
        If jsonParseAsciiEqual(pParse, offset, StrPtr("true"), 4) <> 0 AndAlso _
           jsonParseIsAlnum(jsonParseByte(pParse, offset + 4)) = 0 Then
            jsonBlobAppendOneByte(pParse, JSONB_TRUE)
            If pParse->oom <> 0 Then pParse->iErr = offset : Return -1
            Return CInt(offset + 4)
        End If
    Case Asc("f")
        If jsonParseAsciiEqual(pParse, offset, StrPtr("false"), 5) <> 0 AndAlso _
           jsonParseIsAlnum(jsonParseByte(pParse, offset + 5)) = 0 Then
            jsonBlobAppendOneByte(pParse, JSONB_FALSE)
            If pParse->oom <> 0 Then pParse->iErr = offset : Return -1
            Return CInt(offset + 5)
        End If
    Case Asc("n")
        If jsonParseAsciiEqual(pParse, offset, StrPtr("null"), 4) <> 0 AndAlso _
           jsonParseIsAlnum(jsonParseByte(pParse, offset + 4)) = 0 Then
            jsonBlobAppendOneByte(pParse, JSONB_NULL)
            If pParse->oom <> 0 Then pParse->iErr = offset : Return -1
            Return CInt(offset + 4)
        End If
    Case Asc("+"), Asc("."), Asc("-"), Asc("0") To Asc("9")
        Return jsonParseNumber(pParse, offset)
    Case Asc("}")
        pParse->iErr = offset
        Return JSON_PARSE_OBJECT_END
    Case Asc("]")
        pParse->iErr = offset
        Return JSON_PARSE_ARRAY_END
    Case Asc(",")
        pParse->iErr = offset
        Return JSON_PARSE_LIST_SEPARATOR
    Case Asc(":")
        pParse->iErr = offset
        Return JSON_PARSE_OBJECT_SEPARATOR
    Case 0
        Return 0
    End Select

    Dim specialWord As SQLITE_C_INT = jsonParseSpecialWord(pParse, offset)
    If specialWord <> 0 Then Return specialWord
    pParse->iErr = offset
    Return -1
End Function

Function jsonConvertTextToBlob CDecl Alias "jsonConvertTextToBlob" ( _
    ByVal pParse As JsonParse Ptr, _
    ByVal pContext As Any Ptr _
) As SQLITE_C_INT Export
    If pParse = 0 OrElse pParse->zJson = 0 OrElse pParse->nJson < 0 Then _
        Return SQLITE_MISUSE

    Dim parsedEnd As SQLITE_C_INT = jsonTranslateTextToBlob(pParse, 0)
    If pParse->oom <> 0 Then parsedEnd = -1
    If parsedEnd > 0 Then
        Dim tailOffset As u32 = CUInt(parsedEnd)
        While jsonParseIsCWhitespace(jsonParseByte(pParse, tailOffset)) <> 0
            tailOffset += 1
        Wend
        If jsonParseByte(pParse, tailOffset) <> 0 Then
            Dim trailingSpace As SQLITE_C_INT = json5Whitespace( _
                CPtr(Const UByte Ptr, pParse->zJson) + tailOffset)
            tailOffset += CUInt(trailingSpace)
            If jsonParseByte(pParse, tailOffset) <> 0 Then
                If pContext <> 0 Then _
                    sqlite3_result_error(pContext, StrPtr("malformed JSON"), -1)
                jsonParseReset(pParse)
                Return SQLITE_ERROR
            End If
            pParse->hasNonstd = 1
        End If
    End If

    If parsedEnd <= 0 Then
        If pContext <> 0 Then
            If pParse->oom <> 0 Then
                sqlite3_result_error_nomem(pContext)
            Else
                sqlite3_result_error(pContext, StrPtr("malformed JSON"), -1)
            End If
        End If
        jsonParseReset(pParse)
        Return SQLITE_ERROR
    End If
    Return SQLITE_OK
End Function

/' end of sqlite3_json_text_parse.bas '/
