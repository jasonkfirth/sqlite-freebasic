/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_validate.bas

    Purpose:

        Validate one JSONB element and its nested array/object contents.

    Responsibilities:

        - Validate node payload lengths and scalar encodings.
        - Validate JSON and JSON5 string escape sequences.
        - Recursively validate array members and object key/value pairs.
        - Return the one-based byte offset of the first malformed element.

    This file intentionally does NOT contain:

        - JSON text parsing, SQL value conversion, or path lookup.
'/ 

#lang "fb"
#include once "sqlite3_json_parse.bi"
#include once "sqlite3_json_string.bi"

Private Function jsonValidationIsDigit(ByVal value As UByte) As SQLITE_C_INT
    Return CInt(value >= Asc("0") AndAlso value <= Asc("9"))
End Function

Private Function jsonValidationIsHexDigit(ByVal value As UByte) As SQLITE_C_INT
    If jsonValidationIsDigit(value) <> 0 Then Return 1
    If value >= Asc("A") AndAlso value <= Asc("F") Then Return 1
    If value >= Asc("a") AndAlso value <= Asc("f") Then Return 1
    Return 0
End Function

Private Function jsonValidationByteIsOk(ByVal value As UByte) As SQLITE_C_INT
    ' JSONB text permits UTF-8 bytes except controls, quotes, and backslashes.
    Return CInt(value >= &H20 AndAlso value <> Asc(Chr(34)) AndAlso _
                value <> Asc("'") AndAlso value <> Asc(Chr(92)))
End Function

Private Function jsonValidationSimpleEscape(ByVal value As UByte) As SQLITE_C_INT
    Select Case value
    Case Asc(Chr(34)), Asc(Chr(92)), Asc("/"), Asc("b"), Asc("f"), _
         Asc("n"), Asc("r"), Asc("t")
        Return 1
    End Select
    Return 0
End Function

Function jsonbValidityCheck CDecl Alias "jsonbValidityCheck" ( _
    ByVal pParse As Const JsonParse Ptr, _
    ByVal index As u32, _
    ByVal endOffset As u32, _
    ByVal depth As u32 _
) As u32 Export
    If pParse = 0 OrElse pParse->aBlob = 0 OrElse _
       depth > JSON_MAX_DEPTH OrElse index >= pParse->nBlob Then Return index + 1

    Dim payloadSize As u32 = 0
    Dim headerSize As u32 = jsonbPayloadSize(pParse, index, @payloadSize)
    If headerSize = 0 Then Return index + 1
    Dim nodeEnd As sqlite3_uint64 = _
        CULngInt(index) + CULngInt(headerSize) + CULngInt(payloadSize)
    If nodeEnd <> CULngInt(endOffset) Then Return index + 1

    ' Read from allocated storage only. Borrowed blobs use nBlob as their bound.
    Dim availableBytes As u32 = pParse->nBlob
    If pParse->nBlobAlloc > availableBytes Then availableBytes = pParse->nBlobAlloc
    If nodeEnd > CULngInt(availableBytes) Then Return index + 1

    Dim pBlob As Const UByte Ptr = pParse->aBlob
    Dim nodeType As UByte = pBlob[index] And &HF
    Select Case nodeType
    Case JSONB_NULL, JSONB_TRUE, JSONB_FALSE
        Return IIf(headerSize + payloadSize = 1, 0, index + 1)

    Case JSONB_INT
        If payloadSize < 1 Then Return index + 1
        Dim cursor As u32 = index + headerSize
        If pBlob[cursor] = Asc("-") Then
            cursor += 1
            If payloadSize < 2 Then Return index + 1
        End If
        Dim payloadEnd As u32 = index + headerSize + payloadSize
        While cursor < payloadEnd
            If jsonValidationIsDigit(pBlob[cursor]) = 0 Then Return cursor + 1
            cursor += 1
        Wend
        Return 0

    Case JSONB_INT5
        If payloadSize < 3 Then Return index + 1
        Dim cursor As u32 = index + headerSize
        If pBlob[cursor] = Asc("-") Then
            If payloadSize < 4 Then Return index + 1
            cursor += 1
        End If
        If pBlob[cursor] <> Asc("0") Then Return index + 1
        If pBlob[cursor + 1] <> Asc("x") AndAlso _
           pBlob[cursor + 1] <> Asc("X") Then Return cursor + 2
        cursor += 2
        Dim payloadEnd As u32 = index + headerSize + payloadSize
        While cursor < payloadEnd
            If jsonValidationIsHexDigit(pBlob[cursor]) = 0 Then Return cursor + 1
            cursor += 1
        Wend
        Return 0

    Case JSONB_FLOAT, JSONB_FLOAT5
        If payloadSize < 2 Then Return index + 1
        Dim cursor As u32 = index + headerSize
        Dim payloadEnd As u32 = cursor + payloadSize
        Dim seen As u8 = 0
        If pBlob[cursor] = Asc("-") Then
            cursor += 1
            If payloadSize < 3 Then Return index + 1
        End If
        If pBlob[cursor] = Asc(".") Then
            If nodeType = JSONB_FLOAT OrElse cursor + 1 >= payloadEnd OrElse _
               jsonValidationIsDigit(pBlob[cursor + 1]) = 0 Then Return cursor + 1
            cursor += 2
            seen = 1
        ElseIf pBlob[cursor] = Asc("0") AndAlso nodeType = JSONB_FLOAT Then
            If cursor + 3 > payloadEnd Then Return cursor + 1
            If pBlob[cursor + 1] <> Asc(".") AndAlso _
               pBlob[cursor + 1] <> Asc("e") AndAlso _
               pBlob[cursor + 1] <> Asc("E") Then Return cursor + 1
            cursor += 1
        End If

        While cursor < payloadEnd
            Dim value As UByte = pBlob[cursor]
            If jsonValidationIsDigit(value) <> 0 Then
                cursor += 1
                Continue While
            End If
            If value = Asc(".") Then
                If seen > 0 OrElse (nodeType = JSONB_FLOAT AndAlso _
                   (cursor + 1 >= payloadEnd OrElse _
                    jsonValidationIsDigit(pBlob[cursor + 1]) = 0)) Then Return cursor + 1
                seen = 1
                cursor += 1
                Continue While
            End If
            If value = Asc("e") OrElse value = Asc("E") Then
                If seen = 2 OrElse cursor + 1 >= payloadEnd Then Return cursor + 1
                If pBlob[cursor + 1] = Asc("+") OrElse _
                   pBlob[cursor + 1] = Asc("-") Then
                    cursor += 1
                    If cursor + 1 >= payloadEnd Then Return cursor + 1
                End If
                seen = 2
                cursor += 1
                Continue While
            End If
            Return cursor + 1
        Wend
        If seen = 0 Then Return index + 1
        Return 0

    Case JSONB_TEXT
        Dim cursor As u32 = index + headerSize
        Dim payloadEnd As u32 = cursor + payloadSize
        While cursor < payloadEnd
            If jsonValidationByteIsOk(pBlob[cursor]) = 0 AndAlso _
               pBlob[cursor] <> Asc("'") Then Return cursor + 1
            cursor += 1
        Wend
        Return 0

    Case JSONB_TEXTJ, JSONB_TEXT5
        Dim cursor As u32 = index + headerSize
        Dim payloadEnd As u32 = cursor + payloadSize
        While cursor < payloadEnd
            Dim currentByte As UByte = pBlob[cursor]
            If jsonValidationByteIsOk(currentByte) = 0 AndAlso _
               currentByte <> Asc("'") Then
                If currentByte = Asc(Chr(34)) Then
                    If nodeType = JSONB_TEXTJ Then Return cursor + 1
                ElseIf currentByte <= &H1F Then
                    If nodeType = JSONB_TEXTJ Then Return cursor + 1
                ElseIf currentByte <> Asc(Chr(92)) OrElse cursor + 1 >= payloadEnd Then
                    Return cursor + 1
                ElseIf jsonValidationSimpleEscape(pBlob[cursor + 1]) <> 0 Then
                    cursor += 1
                ElseIf pBlob[cursor + 1] = Asc("u") Then
                    If cursor + 5 >= payloadEnd OrElse _
                       jsonIs4Hex(pBlob + cursor + 2) = 0 Then Return cursor + 1
                    cursor += 1
                ElseIf nodeType <> JSONB_TEXT5 Then
                    Return cursor + 1
                Else
                    Dim decodedCodepoint As u32 = 0
                    Dim escapeSize As u32 = jsonUnescapeOneChar( _
                        pBlob + cursor, payloadEnd - cursor, @decodedCodepoint)
                    If decodedCodepoint = JSON_INVALID_CHAR OrElse escapeSize = 0 Then _
                        Return cursor + 1
                    cursor += escapeSize - 1
                End If
            End If
            cursor += 1
        Wend
        Return 0

    Case JSONB_TEXTRAW
        Return 0

    Case JSONB_ARRAY
        Dim cursor As u32 = index + headerSize
        Dim payloadEnd As u32 = cursor + payloadSize
        While cursor < payloadEnd
            Dim childPayloadSize As u32 = 0
            Dim childHeaderSize As u32 = _
                jsonbPayloadSize(pParse, cursor, @childPayloadSize)
            If childHeaderSize = 0 Then Return cursor + 1
            Dim childEnd As sqlite3_uint64 = _
                CULngInt(cursor) + CULngInt(childHeaderSize) + CULngInt(childPayloadSize)
            If childEnd > CULngInt(payloadEnd) OrElse childEnd > CULngInt(availableBytes) Then _
                Return cursor + 1
            Dim childError As u32 = jsonbValidityCheck( _
                pParse, cursor, CUInt(childEnd), depth + 1)
            If childError <> 0 Then Return childError
            cursor = CUInt(childEnd)
        Wend
        If cursor <> payloadEnd Then Return cursor + 1
        Return 0

    Case JSONB_OBJECT
        Dim cursor As u32 = index + headerSize
        Dim payloadEnd As u32 = cursor + payloadSize
        Dim childCount As u32 = 0
        While cursor < payloadEnd
            Dim childPayloadSize As u32 = 0
            Dim childHeaderSize As u32 = _
                jsonbPayloadSize(pParse, cursor, @childPayloadSize)
            If childHeaderSize = 0 Then Return cursor + 1
            Dim childEnd As sqlite3_uint64 = _
                CULngInt(cursor) + CULngInt(childHeaderSize) + CULngInt(childPayloadSize)
            If childEnd > CULngInt(payloadEnd) OrElse childEnd > CULngInt(availableBytes) Then _
                Return cursor + 1
            If (childCount And 1) = 0 Then
                Dim labelType As UByte = pBlob[cursor] And &HF
                If labelType < JSONB_TEXT OrElse labelType > JSONB_TEXTRAW Then _
                    Return cursor + 1
            End If
            Dim childError As u32 = jsonbValidityCheck( _
                pParse, cursor, CUInt(childEnd), depth + 1)
            If childError <> 0 Then Return childError
            childCount += 1
            cursor = CUInt(childEnd)
        Wend
        If cursor <> payloadEnd Then Return cursor + 1
        If (childCount And 1) <> 0 Then Return cursor + 1
        Return 0

    Case Else
        Return index + 1
    End Select
End Function

/' end of sqlite3_json_validate.bas '/
