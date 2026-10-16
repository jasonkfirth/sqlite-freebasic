/'
    Project: SQLite FreeBASIC port

    File: sqlite3_tokenize.bas

    Purpose:

        Split UTF-8 SQL input into SQLite parser tokens.

    Responsibilities:

        - Port sqlite3GetToken() and sqlite3IsIdChar() from src/tokenize.c.
        - Resolve keywords using the generated Lemon token and keyword tables.
        - Implement the public SQLite keyword inspection functions.

    This file intentionally does NOT contain:

        - The Lemon parser or SQL grammar actions.
        - SQL compilation, execution, or database state.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_tokens.bi"
#include once "sqlite3_character_classes.bi"
#include once "sqlite3_keyword_data.bi"

/' ------------------------------------------------------------------------- '/
/' Character classification '/
/' ------------------------------------------------------------------------- '/

' These values match the CC_ classes in src/tokenize.c.
Private Const CC_X As UByte = 0
Private Const CC_KYWD0 As UByte = 1
Private Const CC_KYWD As UByte = 2
Private Const CC_DIGIT As UByte = 3
Private Const CC_DOLLAR As UByte = 4
Private Const CC_VARALPHA As UByte = 5
Private Const CC_VARNUM As UByte = 6
Private Const CC_SPACE As UByte = 7
Private Const CC_QUOTE As UByte = 8
Private Const CC_QUOTE2 As UByte = 9
Private Const CC_PIPE As UByte = 10
Private Const CC_MINUS As UByte = 11
Private Const CC_LT As UByte = 12
Private Const CC_GT As UByte = 13
Private Const CC_EQ As UByte = 14
Private Const CC_BANG As UByte = 15
Private Const CC_SLASH As UByte = 16
Private Const CC_LP As UByte = 17
Private Const CC_RP As UByte = 18
Private Const CC_SEMI As UByte = 19
Private Const CC_PLUS As UByte = 20
Private Const CC_STAR As UByte = 21
Private Const CC_PERCENT As UByte = 22
Private Const CC_COMMA As UByte = 23
Private Const CC_AND As UByte = 24
Private Const CC_TILDA As UByte = 25
Private Const CC_DOT As UByte = 26
Private Const CC_ID As UByte = 27
Private Const CC_ILLEGAL As UByte = 28
Private Const CC_NUL As UByte = 29
Private Const CC_BOM As UByte = 30

' SQLite's numeric scanner accepts underscores between digits.
Private Const SQLITE_DIGIT_SEPARATOR As UByte = Asc("_")

Private Function sqlite3TokenIsIdChar(ByVal c As UByte) As SQLITE_C_INT
    If c >= &H80 Then Return 1
    If c = &H24 OrElse c = &H5F Then Return 1
    If c >= &H30 AndAlso c <= &H39 Then Return 1
    If c >= &H41 AndAlso c <= &H5A Then Return 1
    If c >= &H61 AndAlso c <= &H7A Then Return 1
    Return 0
End Function

Private Function sqlite3TokenIsSpace(ByVal c As UByte) As SQLITE_C_INT
    Select Case c
    Case 9 To 13, 32
        Return 1
    End Select
    Return 0
End Function

Private Function sqlite3TokenIsDigit(ByVal c As UByte) As SQLITE_C_INT
    If c >= Asc("0") AndAlso c <= Asc("9") Then Return 1
    Return 0
End Function

Private Function sqlite3TokenIsHexDigit(ByVal c As UByte) As SQLITE_C_INT
    If sqlite3TokenIsDigit(c) Then Return 1
    If c >= Asc("A") AndAlso c <= Asc("F") Then Return 1
    If c >= Asc("a") AndAlso c <= Asc("f") Then Return 1
    Return 0
End Function

Private Function sqlite3TokenLowerAscii(ByVal c As UByte) As UByte
    If c >= Asc("A") AndAlso c <= Asc("Z") Then Return c + &H20
    Return c
End Function

Private Function sqlite3TokenReturn( _
    ByVal pTokenType As SQLITE_C_INT Ptr, _
    ByVal tokenType As SQLITE_C_INT, _
    ByVal tokenLength As LongInt _
) As LongInt

    pTokenType[0] = tokenType
    Return tokenLength
End Function

/' ------------------------------------------------------------------------- '/
/' Keyword lookup '/
/' ------------------------------------------------------------------------- '/

Private Function sqlite3TokenKeywordCode( _
    ByVal z As Const UByte Ptr, _
    ByVal n As LongInt, _
    ByRef tokenType As SQLITE_C_INT _
) As LongInt

    Dim first As ULongInt = sqlite3TokenLowerAscii(z[0])
    Dim last As ULongInt = sqlite3TokenLowerAscii(z[n - 1])
    Dim bucket As SQLITE_C_INT = CLng(((first * 4) Xor (last * 3) Xor CULngInt(n)) Mod 127)
    Dim keywordIndex As SQLITE_C_INT = sqlite3KeywordHash(bucket)

    While keywordIndex > 0
        If sqlite3KeywordLength(keywordIndex) = n Then
            Dim textOffset As SQLITE_C_INT = sqlite3KeywordOffset(keywordIndex)
            Dim j As SQLITE_C_INT
            Dim matches As SQLITE_C_INT = 1

            For j = 0 To CInt(n) - 1
                If (z[j] And &HDF) <> sqlite3KeywordText(textOffset + j) Then
                    matches = 0
                    Exit For
                End If
            Next

            If matches Then
                tokenType = sqlite3KeywordCodeTable(keywordIndex)
                Return n
            End If
        End If

        keywordIndex = sqlite3KeywordNext(keywordIndex)
    Wend

    Return n
End Function

Function sqlite3KeywordCode CDecl Alias "sqlite3KeywordCode" ( _
    ByVal z As Const UByte Ptr, _
    ByVal n As SQLITE_C_INT _
) As SQLITE_C_INT Export

    Dim tokenType As SQLITE_C_INT = TK_ID
    If z = 0 OrElse n < 2 Then Return tokenType
    sqlite3TokenKeywordCode(z, n, tokenType)
    Return tokenType
End Function

Function sqlite3IsIdChar CDecl Alias "sqlite3IsIdChar" (ByVal c As UByte) As SQLITE_C_INT Export
    Return sqlite3TokenIsIdChar(c)
End Function

Function sqlite3_keyword_count CDecl Alias "sqlite3_keyword_count" () As SQLITE_C_INT Export
    Return SQLITE_N_KEYWORD
End Function

Function sqlite3_keyword_name CDecl Alias "sqlite3_keyword_name" ( _
    ByVal i As SQLITE_C_INT, _
    ByVal pzName As Any Ptr, _
    ByVal pnName As SQLITE_C_INT Ptr _
) As SQLITE_C_INT Export

    If i < 0 OrElse i >= SQLITE_N_KEYWORD Then Return SQLITE_ERROR
    If pzName = 0 OrElse pnName = 0 Then Return SQLITE_MISUSE

    Dim pzNameOut As Const UByte Ptr Ptr = CPtr(Const UByte Ptr Ptr, pzName)
    Dim keywordIndex As SQLITE_C_INT = i + 1
    pzNameOut[0] = @sqlite3KeywordText(sqlite3KeywordOffset(keywordIndex))
    pnName[0] = sqlite3KeywordLength(keywordIndex)
    Return SQLITE_OK
End Function

Function sqlite3_keyword_check CDecl Alias "sqlite3_keyword_check" ( _
    ByVal zName As Const UByte Ptr, _
    ByVal nName As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If zName = 0 OrElse nName < 2 Then Return 0
    If sqlite3KeywordCode(zName, nName) <> TK_ID Then Return 1
    Return 0
End Function

/' ------------------------------------------------------------------------- '/
/' UTF-8 token scanner '/
/' ------------------------------------------------------------------------- '/

Function sqlite3GetToken CDecl Alias "sqlite3GetToken" ( _
    ByVal z As Const UByte Ptr, _
    ByVal pTokenType As SQLITE_C_INT Ptr _
) As LongInt Export

    If pTokenType = 0 Then Return 0
    If z = 0 Then Return sqlite3TokenReturn(pTokenType, TK_ILLEGAL, 0)

    Dim i As LongInt = 0
    Dim c As UByte = 0
    Dim delim As UByte = 0
    Dim tokenType As SQLITE_C_INT = TK_ILLEGAL
    Dim nVarChar As LongInt = 0
    Dim firstClass As UByte = sqlite3TokenCharacterClass(z[0])

    Select Case firstClass
    Case CC_SPACE
        i = 1
        While sqlite3TokenIsSpace(z[i])
            i += 1
        Wend
        Return sqlite3TokenReturn(pTokenType, TK_SPACE, i)

    Case CC_MINUS
        If z[1] = Asc("-") Then
            i = 2
            While z[i] <> 0 AndAlso z[i] <> 10
                i += 1
            Wend
            Return sqlite3TokenReturn(pTokenType, TK_COMMENT, i)
        ElseIf z[1] = Asc(">") Then
            If z[2] = Asc(">") Then Return sqlite3TokenReturn(pTokenType, TK_PTR, 3)
            Return sqlite3TokenReturn(pTokenType, TK_PTR, 2)
        End If
        Return sqlite3TokenReturn(pTokenType, TK_MINUS, 1)

    Case CC_LP
        Return sqlite3TokenReturn(pTokenType, TK_LP, 1)
    Case CC_RP
        Return sqlite3TokenReturn(pTokenType, TK_RP, 1)
    Case CC_SEMI
        Return sqlite3TokenReturn(pTokenType, TK_SEMI, 1)
    Case CC_PLUS
        Return sqlite3TokenReturn(pTokenType, TK_PLUS, 1)
    Case CC_STAR
        Return sqlite3TokenReturn(pTokenType, TK_STAR, 1)

    Case CC_SLASH
        If z[1] <> Asc("*") OrElse z[2] = 0 Then
            Return sqlite3TokenReturn(pTokenType, TK_SLASH, 1)
        End If

        i = 3
        c = z[2]
        Do
            If c = Asc("*") AndAlso z[i] = Asc("/") Then Exit Do
            c = z[i]
            If c = 0 Then Exit Do
            i += 1
        Loop
        If c <> 0 Then i += 1
        Return sqlite3TokenReturn(pTokenType, TK_COMMENT, i)

    Case CC_PERCENT
        Return sqlite3TokenReturn(pTokenType, TK_REM, 1)

    Case CC_EQ
        If z[1] = Asc("=") Then Return sqlite3TokenReturn(pTokenType, TK_EQ, 2)
        Return sqlite3TokenReturn(pTokenType, TK_EQ, 1)

    Case CC_LT
        c = z[1]
        If c = Asc("=") Then Return sqlite3TokenReturn(pTokenType, TK_LE, 2)
        If c = Asc(">") Then Return sqlite3TokenReturn(pTokenType, TK_NE, 2)
        If c = Asc("<") Then Return sqlite3TokenReturn(pTokenType, TK_LSHIFT, 2)
        Return sqlite3TokenReturn(pTokenType, TK_LT, 1)

    Case CC_GT
        c = z[1]
        If c = Asc("=") Then Return sqlite3TokenReturn(pTokenType, TK_GE, 2)
        If c = Asc(">") Then Return sqlite3TokenReturn(pTokenType, TK_RSHIFT, 2)
        Return sqlite3TokenReturn(pTokenType, TK_GT, 1)

    Case CC_BANG
        If z[1] <> Asc("=") Then Return sqlite3TokenReturn(pTokenType, TK_ILLEGAL, 1)
        Return sqlite3TokenReturn(pTokenType, TK_NE, 2)

    Case CC_PIPE
        If z[1] <> Asc("|") Then Return sqlite3TokenReturn(pTokenType, TK_BITOR, 1)
        Return sqlite3TokenReturn(pTokenType, TK_CONCAT, 2)

    Case CC_COMMA
        Return sqlite3TokenReturn(pTokenType, TK_COMMA, 1)
    Case CC_AND
        Return sqlite3TokenReturn(pTokenType, TK_BITAND, 1)
    Case CC_TILDA
        Return sqlite3TokenReturn(pTokenType, TK_BITNOT, 1)

    Case CC_QUOTE
        delim = z[0]
        i = 1
        While z[i] <> 0
            c = z[i]
            If c = delim Then
                If z[i + 1] = delim Then
                    i += 1
                Else
                    Exit While
                End If
            End If
            i += 1
        Wend

        If z[i] = 0 Then Return sqlite3TokenReturn(pTokenType, TK_ILLEGAL, i)
        If delim = Asc("'") Then Return sqlite3TokenReturn(pTokenType, TK_STRING, i + 1)
        Return sqlite3TokenReturn(pTokenType, TK_ID, i + 1)

    Case CC_DOT
#ifndef SQLITE_OMIT_FLOATING_POINT
        If sqlite3TokenIsDigit(z[1]) = 0 Then Return sqlite3TokenReturn(pTokenType, TK_DOT, 1)
        GoTo number_token
#else
        Return sqlite3TokenReturn(pTokenType, TK_DOT, 1)
#endif

    Case CC_DIGIT
        GoTo number_token

    Case CC_QUOTE2
        i = 1
        c = z[0]
        While c <> Asc("]") AndAlso z[i] <> 0
            c = z[i]
            i += 1
        Wend
        If c = Asc("]") Then Return sqlite3TokenReturn(pTokenType, TK_ID, i)
        Return sqlite3TokenReturn(pTokenType, TK_ILLEGAL, i)

    Case CC_VARNUM
        i = 1
        While sqlite3TokenIsDigit(z[i])
            i += 1
        Wend
        Return sqlite3TokenReturn(pTokenType, TK_VARIABLE, i)

    Case CC_DOLLAR, CC_VARALPHA
        tokenType = TK_VARIABLE
        i = 1
        While z[i] <> 0
            c = z[i]
            If sqlite3TokenIsIdChar(c) Then
                nVarChar += 1
#ifndef SQLITE_OMIT_TCL_VARIABLE
            ElseIf c = Asc("(") AndAlso nVarChar > 0 Then
                i += 1
                While z[i] <> 0 AndAlso sqlite3TokenIsSpace(z[i]) = 0 AndAlso z[i] <> Asc(")")
                    i += 1
                Wend
                If z[i] = Asc(")") Then
                    i += 1
                Else
                    tokenType = TK_ILLEGAL
                End If
                Exit While
            ElseIf c = Asc(":") AndAlso z[i + 1] = Asc(":") Then
                i += 1
#endif
            Else
                Exit While
            End If
            i += 1
        Wend
        If nVarChar = 0 Then tokenType = TK_ILLEGAL
        Return sqlite3TokenReturn(pTokenType, tokenType, i)

    Case CC_KYWD0
        If sqlite3TokenCharacterClass(z[1]) > CC_KYWD Then
            i = 1
            GoTo identifier_token
        End If

        i = 2
        While sqlite3TokenCharacterClass(z[i]) <= CC_KYWD
            i += 1
        Wend
        If sqlite3TokenIsIdChar(z[i]) Then
            i += 1
            GoTo identifier_token
        End If

        tokenType = TK_ID
        sqlite3TokenKeywordCode(z, i, tokenType)
        Return sqlite3TokenReturn(pTokenType, tokenType, i)

    Case CC_X
#ifndef SQLITE_OMIT_BLOB_LITERAL
        If z[1] = Asc("'") Then
            tokenType = TK_BLOB
            i = 2
            While sqlite3TokenIsHexDigit(z[i])
                i += 1
            Wend
            If z[i] <> Asc("'") OrElse (i And 1) <> 0 Then
                tokenType = TK_ILLEGAL
                While z[i] <> 0 AndAlso z[i] <> Asc("'")
                    i += 1
                Wend
            End If
            If z[i] <> 0 Then i += 1
            Return sqlite3TokenReturn(pTokenType, tokenType, i)
        End If
#endif
        i = 1
        GoTo identifier_token

    Case CC_KYWD, CC_ID
        i = 1
        GoTo identifier_token

    Case CC_BOM
        If z[1] = &HBB AndAlso z[2] = &HBF Then
            Return sqlite3TokenReturn(pTokenType, TK_SPACE, 3)
        End If
        i = 1
        GoTo identifier_token

    Case CC_NUL
        Return sqlite3TokenReturn(pTokenType, TK_ILLEGAL, 0)

    Case Else
        Return sqlite3TokenReturn(pTokenType, TK_ILLEGAL, 1)
    End Select

number_token:
    tokenType = TK_INTEGER
#ifndef SQLITE_OMIT_HEX_INTEGER
    If z[0] = Asc("0") AndAlso (z[1] = Asc("x") OrElse z[1] = Asc("X")) AndAlso sqlite3TokenIsHexDigit(z[2]) Then
        i = 3
        Do
            If sqlite3TokenIsHexDigit(z[i]) = 0 Then
                If z[i] = SQLITE_DIGIT_SEPARATOR Then
                    tokenType = TK_QNUMBER
                Else
                    Exit Do
                End If
            End If
            i += 1
        Loop
    Else
#endif
        i = 0
        Do
            If sqlite3TokenIsDigit(z[i]) = 0 Then
                If z[i] = SQLITE_DIGIT_SEPARATOR Then
                    tokenType = TK_QNUMBER
                Else
                    Exit Do
                End If
            End If
            i += 1
        Loop
#ifndef SQLITE_OMIT_FLOATING_POINT
        If z[i] = Asc(".") Then
            If tokenType = TK_INTEGER Then tokenType = TK_FLOAT
            i += 1
            Do
                If sqlite3TokenIsDigit(z[i]) = 0 Then
                    If z[i] = SQLITE_DIGIT_SEPARATOR Then
                        tokenType = TK_QNUMBER
                    Else
                        Exit Do
                    End If
                End If
                i += 1
            Loop
        End If

        If (z[i] = Asc("e") OrElse z[i] = Asc("E")) AndAlso _
           (sqlite3TokenIsDigit(z[i + 1]) OrElse _
            ((z[i + 1] = Asc("+") OrElse z[i + 1] = Asc("-")) AndAlso sqlite3TokenIsDigit(z[i + 2]))) Then
            If tokenType = TK_INTEGER Then tokenType = TK_FLOAT
            i += 2
            Do
                If sqlite3TokenIsDigit(z[i]) = 0 Then
                    If z[i] = SQLITE_DIGIT_SEPARATOR Then
                        tokenType = TK_QNUMBER
                    Else
                        Exit Do
                    End If
                End If
                i += 1
            Loop
        End If
#endif
#ifndef SQLITE_OMIT_HEX_INTEGER
    End If
#endif

    While sqlite3TokenIsIdChar(z[i])
        tokenType = TK_ILLEGAL
        i += 1
    Wend
    Return sqlite3TokenReturn(pTokenType, tokenType, i)

identifier_token:
    While sqlite3TokenIsIdChar(z[i])
        i += 1
    Wend
    Return sqlite3TokenReturn(pTokenType, TK_ID, i)
End Function

/' end of sqlite3_tokenize.bas '/
