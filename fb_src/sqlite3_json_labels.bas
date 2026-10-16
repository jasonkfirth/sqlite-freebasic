/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_labels.bas

    Purpose:

        Compare JSON object labels in raw UTF-8 or escaped form.

    Responsibilities:

        - Decode one UTF-8 or JSON escape codepoint from each bounded label.
        - Compare raw labels directly when neither contains escapes.
        - Stop at the first differing codepoint or at both label ends.

    This file intentionally does NOT contain:

        - JSON object traversal, path lookup, or JSONB cell decoding.
'/ 

#lang "fb"
#include once "sqlite3_json_parse.bi"

Declare Function sqlite3Utf8ReadLimited CDecl Alias "sqlite3Utf8ReadLimited" ( _
    ByVal zInput As Const UByte Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal pCodepoint As u32 Ptr _
) As SQLITE_C_INT

Function jsonLabelCompareEscaped CDecl Alias "jsonLabelCompareEscaped" ( _
    ByVal zLeftArgument As Const UByte Ptr, _
    ByVal nLeftArgument As u32, _
    ByVal rawLeft As SQLITE_C_INT, _
    ByVal zRightArgument As Const UByte Ptr, _
    ByVal nRightArgument As u32, _
    ByVal rawRight As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If (nLeftArgument > 0 AndAlso zLeftArgument = 0) OrElse _
       (nRightArgument > 0 AndAlso zRightArgument = 0) Then Return 0

    Dim zLeft As Const UByte Ptr = zLeftArgument
    Dim zRight As Const UByte Ptr = zRightArgument
    Dim nLeft As u32 = nLeftArgument
    Dim nRight As u32 = nRightArgument

    While 1
        Dim leftCodepoint As u32 = 0
        Dim rightCodepoint As u32 = 0

        If nLeft > 0 Then
            If rawLeft <> 0 OrElse zLeft[0] <> Asc(Chr(92)) Then
                leftCodepoint = zLeft[0]
                If zLeft[0] >= &HC0 Then
                    If nLeft > &H7FFFFFFF Then Return 0
                    Dim consumed As SQLITE_C_INT = _
                        sqlite3Utf8ReadLimited(zLeft, CInt(nLeft), @leftCodepoint)
                    If consumed <= 0 OrElse CUInt(consumed) > nLeft Then Return 0
                    zLeft += consumed
                    nLeft -= CUInt(consumed)
                Else
                    zLeft += 1
                    nLeft -= 1
                End If
            Else
                Dim consumed As u32 = jsonUnescapeOneChar(zLeft, nLeft, @leftCodepoint)
                If consumed = 0 OrElse consumed > nLeft Then Return 0
                zLeft += consumed
                nLeft -= consumed
            End If
        End If

        If nRight > 0 Then
            If rawRight <> 0 OrElse zRight[0] <> Asc(Chr(92)) Then
                rightCodepoint = zRight[0]
                If zRight[0] >= &HC0 Then
                    If nRight > &H7FFFFFFF Then Return 0
                    Dim consumed As SQLITE_C_INT = _
                        sqlite3Utf8ReadLimited(zRight, CInt(nRight), @rightCodepoint)
                    If consumed <= 0 OrElse CUInt(consumed) > nRight Then Return 0
                    zRight += consumed
                    nRight -= CUInt(consumed)
                Else
                    zRight += 1
                    nRight -= 1
                End If
            Else
                Dim consumed As u32 = jsonUnescapeOneChar(zRight, nRight, @rightCodepoint)
                If consumed = 0 OrElse consumed > nRight Then Return 0
                zRight += consumed
                nRight -= consumed
            End If
        End If

        If leftCodepoint <> rightCodepoint Then Return 0
        If leftCodepoint = 0 Then Return 1
    Wend
    Return 0
End Function

Function jsonLabelCompare CDecl Alias "jsonLabelCompare" ( _
    ByVal zLeft As Const UByte Ptr, _
    ByVal nLeft As u32, _
    ByVal rawLeft As SQLITE_C_INT, _
    ByVal zRight As Const UByte Ptr, _
    ByVal nRight As u32, _
    ByVal rawRight As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If rawLeft <> 0 AndAlso rawRight <> 0 Then
        If nLeft <> nRight Then Return 0
        If nLeft > 0 AndAlso (zLeft = 0 OrElse zRight = 0) Then Return 0
        Dim iByte As u32 = 0
        While iByte < nLeft
            If zLeft[iByte] <> zRight[iByte] Then Return 0
            iByte += 1
        Wend
        Return 1
    End If
    Return jsonLabelCompareEscaped(zLeft, nLeft, rawLeft, _
                                   zRight, nRight, rawRight)
End Function

/' end of sqlite3_json_labels.bas '/
