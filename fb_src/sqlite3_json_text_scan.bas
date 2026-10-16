/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_text_scan.bas

    Purpose:

        Scan JSON5 whitespace and decode one bounded JSON escape sequence.

    Responsibilities:

        - Recognize JSON5 ASCII and Unicode whitespace plus line and block comments.
        - Skip escaped line terminators without reading beyond the supplied span.
        - Decode simple, hexadecimal, Unicode, and continued-line escapes.

    This file intentionally does NOT contain:

        - JSON token parsing, JSONB validation, or SQL value conversion.
'/ 

#lang "fb"
#include once "sqlite3_json_parse.bi"
#include once "sqlite3_json_string.bi"

Declare Function sqlite3Utf8ReadLimited CDecl Alias "sqlite3Utf8ReadLimited" ( _
    ByVal zInput As Const UByte Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal pCodepoint As u32 Ptr _
) As SQLITE_C_INT

Function json5Whitespace CDecl Alias "json5Whitespace" ( _
    ByVal zInput As Const UByte Ptr _
) As SQLITE_C_INT Export
    If zInput = 0 Then Return 0

    Dim offset As SQLITE_C_INT = 0
    While offset < &H7FFFFFFF
        Dim currentByte As UByte = zInput[offset]
        Select Case currentByte
        Case 9, 10, 11, 12, 13, 32
            offset += 1

        Case Asc("/")
            Dim nextByte As UByte = zInput[offset + 1]
            If nextByte = Asc("*") Then
                ' A block comment needs one byte after the opening delimiter.
                If zInput[offset + 2] = 0 Then Return offset
                Dim scan As SQLITE_C_INT = offset + 3
                While zInput[scan] <> 0
                    If zInput[scan] = Asc("/") AndAlso _
                       zInput[scan - 1] = Asc("*") Then Exit While
                    scan += 1
                Wend
                If zInput[scan] = 0 Then Return offset
                offset = scan + 1
            ElseIf nextByte = Asc("/") Then
                Dim scan As SQLITE_C_INT = offset + 2
                While zInput[scan] <> 0
                    Dim lineByte As UByte = zInput[scan]
                    If lineByte = 10 OrElse lineByte = 13 Then Exit While
                    If lineByte = &HE2 AndAlso zInput[scan + 1] = &H80 AndAlso _
                       (zInput[scan + 2] = &HA8 OrElse zInput[scan + 2] = &HA9) Then
                        scan += 2
                        Exit While
                    End If
                    scan += 1
                Wend
                offset = scan
                If zInput[offset] <> 0 Then offset += 1
            Else
                Return offset
            End If

        Case &HC2
            If zInput[offset + 1] <> &HA0 Then Return offset
            offset += 2

        Case &HE1
            If zInput[offset + 1] <> &H9A OrElse _
               zInput[offset + 2] <> &H80 Then Return offset
            offset += 3

        Case &HE2
            If zInput[offset + 1] = &H80 Then
                Dim trailingByte As UByte = zInput[offset + 2]
                If trailingByte < &H80 Then Return offset
                If trailingByte <= &H8A OrElse trailingByte = &HA8 OrElse _
                   trailingByte = &HA9 OrElse trailingByte = &HAF Then
                    offset += 3
                Else
                    Return offset
                End If
            ElseIf zInput[offset + 1] = &H81 AndAlso _
                   zInput[offset + 2] = &H9F Then
                offset += 3
            Else
                Return offset
            End If

        Case &HE3
            If zInput[offset + 1] <> &H80 OrElse _
               zInput[offset + 2] <> &H80 Then Return offset
            offset += 3

        Case &HEF
            If zInput[offset + 1] <> &HBB OrElse _
               zInput[offset + 2] <> &HBF Then Return offset
            offset += 3

        Case Else
            Return offset
        End Select
    Wend
    Return offset
End Function

Function jsonBytesToBypass CDecl Alias "jsonBytesToBypass" ( _
    ByVal zInput As Const UByte Ptr, _
    ByVal nByte As u32 _
) As u32 Export
    If zInput = 0 Then Return 0
    Dim offset As u32 = 0
    While nByte - offset > 1
        If zInput[offset] <> Asc(Chr(92)) Then Return offset
        Select Case zInput[offset + 1]
        Case 10
            offset += 2
        Case 13
            If nByte - offset > 2 AndAlso zInput[offset + 2] = 10 Then
                offset += 3
            Else
                offset += 2
            End If
        Case &HE2
            If nByte - offset > 3 AndAlso zInput[offset + 2] = &H80 AndAlso _
               (zInput[offset + 3] = &HA8 OrElse zInput[offset + 3] = &HA9) Then
                offset += 4
            Else
                Exit While
            End If
        Case Else
            Exit While
        End Select
    Wend
    Return offset
End Function

Function jsonUnescapeOneChar CDecl Alias "jsonUnescapeOneChar" ( _
    ByVal zInput As Const UByte Ptr, _
    ByVal nByte As u32, _
    ByVal pCodepoint As u32 Ptr _
) As u32 Export
    If pCodepoint = 0 Then Return 0
    If zInput = 0 OrElse nByte = 0 Then
        pCodepoint[0] = JSON_INVALID_CHAR
        Return 0
    End If
    If zInput[0] <> Asc(Chr(92)) Then
        pCodepoint[0] = JSON_INVALID_CHAR
        Return 1
    End If
    If nByte < 2 Then
        pCodepoint[0] = JSON_INVALID_CHAR
        Return nByte
    End If

    Select Case zInput[1]
    Case Asc("u")
        If nByte < 6 Then
            pCodepoint[0] = JSON_INVALID_CHAR
            Return nByte
        End If
        Dim codepoint As u32 = jsonHexToInt4(zInput + 2)
        If (codepoint And &HFC00) = &HD800 AndAlso nByte >= 12 AndAlso _
           zInput[6] = Asc(Chr(92)) AndAlso zInput[7] = Asc("u") Then
            Dim lowSurrogate As u32 = jsonHexToInt4(zInput + 8)
            If (lowSurrogate And &HFC00) = &HDC00 Then
                pCodepoint[0] = ((codepoint And &H3FF) Shl 10) + _
                    (lowSurrogate And &H3FF) + &H10000
                Return 12
            End If
        End If
        pCodepoint[0] = codepoint
        Return 6

    Case Asc("b")
        pCodepoint[0] = 8
        Return 2
    Case Asc("f")
        pCodepoint[0] = 12
        Return 2
    Case Asc("n")
        pCodepoint[0] = 10
        Return 2
    Case Asc("r")
        pCodepoint[0] = 13
        Return 2
    Case Asc("t")
        pCodepoint[0] = 9
        Return 2
    Case Asc("v")
        pCodepoint[0] = 11
        Return 2
    Case Asc("0")
#ifdef SQLITE_BUG_COMPATIBLE_20250510
        pCodepoint[0] = 0
#else
        If nByte > 2 AndAlso zInput[2] >= Asc("0") AndAlso _
           zInput[2] <= Asc("9") Then
            pCodepoint[0] = JSON_INVALID_CHAR
        Else
            pCodepoint[0] = 0
        End If
#endif
        Return 2

    Case Asc("'"), Asc(Chr(34)), Asc("/"), Asc(Chr(92))
        pCodepoint[0] = zInput[1]
        Return 2

    Case Asc("x")
        If nByte < 4 Then
            pCodepoint[0] = JSON_INVALID_CHAR
            Return nByte
        End If
        pCodepoint[0] = (CULng(jsonHexToInt(zInput[2])) Shl 4) Or _
                        CULng(jsonHexToInt(zInput[3]))
        Return 4

    Case &HE2, 13, 10
        Dim nSkip As u32 = jsonBytesToBypass(zInput, nByte)
        If nSkip = 0 Then
            pCodepoint[0] = JSON_INVALID_CHAR
            Return nByte
        ElseIf nSkip = nByte Then
            pCodepoint[0] = 0
            Return nByte
        ElseIf zInput[nSkip] = Asc(Chr(92)) Then
            Return nSkip + jsonUnescapeOneChar(zInput + nSkip, nByte - nSkip, pCodepoint)
        Else
            If nByte - nSkip > &H7FFFFFFF Then
                pCodepoint[0] = JSON_INVALID_CHAR
                Return nByte
            End If
            Dim decodedBytes As SQLITE_C_INT = sqlite3Utf8ReadLimited( _
                zInput + nSkip, CInt(nByte - nSkip), pCodepoint)
            If decodedBytes <= 0 Then
                pCodepoint[0] = JSON_INVALID_CHAR
                Return nByte
            End If
            Return nSkip + CUInt(decodedBytes)
        End If

    Case Else
        pCodepoint[0] = JSON_INVALID_CHAR
        Return 2
    End Select
End Function

/' end of sqlite3_json_text_scan.bas '/
