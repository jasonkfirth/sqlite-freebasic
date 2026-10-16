/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_blob_text.bas

    Purpose:

        Render one JSONB node as canonical JSON text.

    Responsibilities:

        - Render scalar JSONB values and normalize JSON5 numeric forms.
        - Escape raw text and JSON5 string contents.
        - Recursively render array and object payloads.
        - Mark malformed node data in the output accumulator.

    This file intentionally does NOT contain:

        - SQL function callbacks, pretty-printing, or path operations.
'/ 

#lang "fb"
#include once "sqlite3_json_parse.bi"
#include once "sqlite3_json_string.bi"
#include once "sqlite3_constants.bi"

Declare Function sqlite3HexToInt CDecl Alias "sqlite3HexToInt" (ByVal value As SQLITE_C_INT) As u8

Private Function jsonBlobTextByteIsOk(ByVal value As UByte) As SQLITE_C_INT
    Return CInt(value >= &H20 AndAlso value <> Asc(Chr(34)) AndAlso _
                value <> Asc(Chr(92)))
End Function

Private Function jsonBlobTextIsDigit(ByVal value As UByte) As SQLITE_C_INT
    Return CInt(value >= Asc("0") AndAlso value <= Asc("9"))
End Function

Private Function jsonBlobTextIsHexDigit(ByVal value As UByte) As SQLITE_C_INT
    If jsonBlobTextIsDigit(value) <> 0 Then Return 1
    If value >= Asc("A") AndAlso value <= Asc("F") Then Return 1
    If value >= Asc("a") AndAlso value <= Asc("f") Then Return 1
    Return 0
End Function

Private Sub jsonAppendUnsignedDecimal( _
    ByVal pOutput As JsonString Ptr, _
    ByVal value As sqlite3_uint64 _
)
    Dim digits(0 To 19) As UByte
    Dim digitCount As SQLITE_C_INT = 0
    Dim remaining As sqlite3_uint64 = value
    If remaining = 0 Then
        jsonAppendChar(pOutput, Asc("0"))
        Exit Sub
    End If
    While remaining > 0 AndAlso digitCount < 20
        digits(digitCount) = CByte(Asc("0") + (remaining Mod 10))
        remaining \= 10
        digitCount += 1
    Wend
    If remaining <> 0 Then
        pOutput->eErr = pOutput->eErr Or JSTRING_MALFORMED
        Exit Sub
    End If
    While digitCount > 0
        digitCount -= 1
        jsonAppendChar(pOutput, CByte(digits(digitCount)))
    Wend
End Sub

Function jsonTranslateBlobToText CDecl Alias "jsonTranslateBlobToText" ( _
    ByVal pParse As JsonParse Ptr, _
    ByVal startIndex As u32, _
    ByVal pOutput As JsonString Ptr _
) As u32 Export
    If pParse = 0 OrElse pOutput = 0 OrElse pParse->aBlob = 0 Then
        If pOutput <> 0 Then pOutput->eErr = pOutput->eErr Or JSTRING_MALFORMED
        If pParse <> 0 Then Return pParse->nBlob + 1
        Return 1
    End If

    Dim payloadSize As u32 = 0
    Dim headerSize As u32 = _
        jsonbPayloadSizeInline(pParse, startIndex, @payloadSize)
    If headerSize = 0 Then
        pOutput->eErr = pOutput->eErr Or JSTRING_MALFORMED
        Return pParse->nBlob + 1
    End If

    Dim nodeEnd As sqlite3_uint64 = _
        CULngInt(startIndex) + CULngInt(headerSize) + CULngInt(payloadSize)
    If nodeEnd > CULngInt(pParse->nBlobAlloc) AndAlso _
       pParse->nBlobAlloc <> 0 Then
        pOutput->eErr = pOutput->eErr Or JSTRING_MALFORMED
        Return pParse->nBlob + 1
    End If
    Dim payload As Const UByte Ptr = pParse->aBlob + startIndex + headerSize
    Dim nodeType As UByte = pParse->aBlob[startIndex] And &HF

    Select Case nodeType
    Case JSONB_NULL
        jsonAppendRawNZ(pOutput, CPtr(Const UByte Ptr, StrPtr("null")), 4)
        Return startIndex + 1
    Case JSONB_TRUE
        jsonAppendRawNZ(pOutput, CPtr(Const UByte Ptr, StrPtr("true")), 4)
        Return startIndex + 1
    Case JSONB_FALSE
        jsonAppendRawNZ(pOutput, CPtr(Const UByte Ptr, StrPtr("false")), 5)
        Return startIndex + 1

    Case JSONB_INT, JSONB_FLOAT
        If payloadSize = 0 Then GoTo malformed_jsonb
        jsonAppendRaw(pOutput, payload, payloadSize)

    Case JSONB_INT5
        If payloadSize = 0 Then GoTo malformed_jsonb
        Dim digitOffset As u32 = 2
        Dim value As sqlite3_uint64 = 0
        Dim overflow As SQLITE_C_INT = 0
        If payload[0] = Asc("-") Then
            jsonAppendChar(pOutput, Asc("-"))
            digitOffset += 1
        ElseIf payload[0] = Asc("+") Then
            digitOffset += 1
        End If
        While digitOffset < payloadSize
            Dim digit As UByte = payload[digitOffset]
            If jsonBlobTextIsHexDigit(digit) = 0 Then
                pOutput->eErr = pOutput->eErr Or JSTRING_MALFORMED
                Exit While
            ElseIf (value Shr 60) <> 0 Then
                overflow = 1
            Else
                value = value * 16 + sqlite3HexToInt(digit)
            End If
            digitOffset += 1
        Wend
        If overflow <> 0 Then
            jsonAppendRawNZ(pOutput, CPtr(Const UByte Ptr, StrPtr("9.0e999")), 7)
        Else
            jsonAppendUnsignedDecimal(pOutput, value)
        End If

    Case JSONB_FLOAT5
        If payloadSize = 0 Then GoTo malformed_jsonb
        Dim digitOffset As u32 = 0
        If payload[0] = Asc("-") Then
            jsonAppendChar(pOutput, Asc("-"))
            If payloadSize <= 1 Then GoTo malformed_jsonb
            digitOffset = 1
        End If
        If payload[digitOffset] = Asc(".") Then jsonAppendChar(pOutput, Asc("0"))
        While digitOffset < payloadSize
            Dim valueByte As UByte = payload[digitOffset]
            jsonAppendChar(pOutput, CByte(valueByte))
            If valueByte = Asc(".") AndAlso _
               (digitOffset + 1 = payloadSize OrElse _
                jsonBlobTextIsDigit(payload[digitOffset + 1]) = 0) Then _
                jsonAppendChar(pOutput, Asc("0"))
            digitOffset += 1
        Wend

    Case JSONB_TEXT, JSONB_TEXTJ
        jsonAppendChar(pOutput, Asc(Chr(34)))
        jsonAppendRaw(pOutput, payload, payloadSize)
        jsonAppendChar(pOutput, Asc(Chr(34)))

    Case JSONB_TEXT5
        Dim inputOffset As u32 = 0
        jsonAppendChar(pOutput, Asc(Chr(34)))
        While inputOffset < payloadSize AndAlso pOutput->eErr = 0
            Dim runStart As u32 = inputOffset
            While inputOffset < payloadSize AndAlso _
                  (jsonBlobTextByteIsOk(payload[inputOffset]) <> 0 OrElse _
                   payload[inputOffset] = Asc("'"))
                inputOffset += 1
            Wend
            If inputOffset > runStart Then
                jsonAppendRawNZ(pOutput, payload + runStart, inputOffset - runStart)
                If inputOffset >= payloadSize Then Exit While
            End If

            Dim currentByte As UByte = payload[inputOffset]
            If currentByte = Asc(Chr(34)) Then
                jsonAppendChar(pOutput, Asc(Chr(92)))
                jsonAppendChar(pOutput, Asc(Chr(34)))
                inputOffset += 1
            ElseIf currentByte <= &H1F Then
                jsonAppendControlChar(pOutput, currentByte)
                inputOffset += 1
            ElseIf currentByte <> Asc(Chr(92)) Then
                pOutput->eErr = pOutput->eErr Or JSTRING_MALFORMED
                Exit While
            ElseIf payloadSize - inputOffset < 2 Then
                pOutput->eErr = pOutput->eErr Or JSTRING_MALFORMED
                Exit While
            Else
                Dim escapeByte As UByte = payload[inputOffset + 1]
                Select Case escapeByte
                Case Asc("'")
                    jsonAppendChar(pOutput, Asc("'"))
                Case Asc("v")
                    jsonAppendRawNZ(pOutput, _
                        CPtr(Const UByte Ptr, StrPtr("\u000b")), 6)
                Case Asc("x")
                    If payloadSize - inputOffset < 4 Then
                        pOutput->eErr = pOutput->eErr Or JSTRING_MALFORMED
                        inputOffset = payloadSize
                        Exit While
                    End If
                    jsonAppendRawNZ(pOutput, _
                        CPtr(Const UByte Ptr, StrPtr("\u00")), 4)
                    jsonAppendRawNZ(pOutput, payload + inputOffset + 2, 2)
                    inputOffset += 2
                Case Asc("0")
                    jsonAppendRawNZ(pOutput, _
                        CPtr(Const UByte Ptr, StrPtr("\u0000")), 6)
                Case 13
                    If payloadSize - inputOffset > 2 AndAlso _
                       payload[inputOffset + 2] = 10 Then inputOffset += 1
                Case 10
                    ' JSON5 line feeds escaped with backslash are omitted.
                Case &HE2
                    If payloadSize - inputOffset < 4 OrElse _
                       payload[inputOffset + 2] <> &H80 OrElse _
                       (payload[inputOffset + 3] <> &HA8 AndAlso _
                        payload[inputOffset + 3] <> &HA9) Then
                        pOutput->eErr = pOutput->eErr Or JSTRING_MALFORMED
                        inputOffset = payloadSize
                        Exit While
                    End If
                    inputOffset += 2
                Case Else
                    jsonAppendRawNZ(pOutput, payload + inputOffset, 2)
                End Select
                inputOffset += 2
            End If
        Wend
        jsonAppendChar(pOutput, Asc(Chr(34)))

    Case JSONB_TEXTRAW
        jsonAppendString(pOutput, payload, payloadSize)

    Case JSONB_ARRAY, JSONB_OBJECT
        Dim isObject As SQLITE_C_INT = CInt(nodeType = JSONB_OBJECT)
        Dim elementOffset As u32 = startIndex + headerSize
        Dim payloadEnd As u32 = elementOffset + payloadSize
        Dim childCount As SQLITE_C_INT = 0
        If isObject <> 0 Then
            jsonAppendChar(pOutput, Asc("{"))
        Else
            jsonAppendChar(pOutput, Asc("["))
        End If
        If pParse->iDepth >= JSON_MAX_DEPTH Then
            jsonStringTooDeep(pOutput)
        Else
            pParse->iDepth += 1
            While elementOffset < payloadEnd AndAlso pOutput->eErr = 0
                elementOffset = jsonTranslateBlobToText(pParse, elementOffset, pOutput)
                If isObject <> 0 Then
                    If (childCount And 1) = 0 Then
                        jsonAppendChar(pOutput, Asc(":"))
                    Else
                        jsonAppendChar(pOutput, Asc(","))
                    End If
                    childCount += 1
                Else
                    jsonAppendChar(pOutput, Asc(","))
                End If
            Wend
            pParse->iDepth -= 1
        End If
        If elementOffset > payloadEnd Then _
            pOutput->eErr = pOutput->eErr Or JSTRING_MALFORMED
        If isObject <> 0 Then
            If (childCount And 1) <> 0 Then _
                pOutput->eErr = pOutput->eErr Or JSTRING_MALFORMED
            If payloadSize > 0 Then jsonStringTrimOneChar(pOutput)
            jsonAppendChar(pOutput, Asc("}"))
        Else
            If payloadSize > 0 Then jsonStringTrimOneChar(pOutput)
            jsonAppendChar(pOutput, Asc("]"))
        End If

    Case Else
        GoTo malformed_jsonb
    End Select

    Return CUInt(nodeEnd)

malformed_jsonb:
    pOutput->eErr = pOutput->eErr Or JSTRING_MALFORMED
    Return CUInt(nodeEnd)
End Function

/' end of sqlite3_json_blob_text.bas '/
