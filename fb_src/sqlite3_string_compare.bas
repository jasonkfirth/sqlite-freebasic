/'
    Project: SQLite FreeBASIC port

    File: sqlite3_string_compare.bas

    Purpose:

        Port SQLite's bytewise case-insensitive comparison and UTF-8
        LIKE/GLOB matching routines from src/util.c and src/func.c.

    Responsibilities:

        - Provide the public SQLite string comparison and pattern APIs.
        - Match ASCII case folding and UTF-8 character boundaries used by
          SQLite's internal pattern comparison.

    This file intentionally does NOT contain:

        - Locale-aware Unicode case folding.
        - SQL scalar-function registration or database connection state.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_global_data.bi"

Declare Function sqlite3Utf8Read CDecl Alias "sqlite3Utf8Read" ( _
    ByVal pzArgument As Any Ptr _
) As u32

Private Const SQLITE_MATCH As SQLITE_C_INT = 0
Private Const SQLITE_NOMATCH As SQLITE_C_INT = 1
Private Const SQLITE_NOWILDCARDMATCH As SQLITE_C_INT = 2

Private Type CompareInfo
    matchAll As UByte
    matchOne As UByte
    matchSet As UByte
    noCase As UByte
End Type

Private Const GLOB_MATCH_ALL As UByte = Asc("*")
Private Const GLOB_MATCH_ONE As UByte = Asc("?")
Private Const GLOB_MATCH_SET As UByte = Asc("[")
Private Const LIKE_MATCH_ALL As UByte = Asc("%")
Private Const LIKE_MATCH_ONE As UByte = Asc("_")

Private Function sqlite3AsciiToLower(ByVal value As ULong) As ULong
    If value <= &HFF Then Return sqlite3UpperToLower(value)
    Return value
End Function

Private Function sqlite3StringUtf8Read(ByRef z As Const UByte Ptr) As u32
    If z = 0 Then Return 0
    If z[0] < &H80 Then
        Dim value As ULong = z[0]
        z += 1
        Return value
    End If
    Return sqlite3Utf8Read(@z)
End Function

Private Function patternCompare( _
    ByVal zPattern As Const UByte Ptr, _
    ByVal zInput As Const UByte Ptr, _
    ByVal pInfo As Const CompareInfo Ptr, _
    ByVal matchOther As u32 _
) As SQLITE_C_INT

    If zPattern = 0 OrElse zInput = 0 OrElse pInfo = 0 Then Return SQLITE_NOMATCH

    Dim matchOne As ULong = pInfo->matchOne
    Dim matchAll As ULong = pInfo->matchAll
    Dim noCase As ULong = pInfo->noCase
    Dim zEscaped As Const UByte Ptr = 0

    Do
        Dim c As ULong = sqlite3StringUtf8Read(zPattern)
        If c = 0 Then Exit Do

        If c = matchAll Then
            Do
                c = sqlite3StringUtf8Read(zPattern)
                If c <> matchAll AndAlso Not (matchOne <> 0 AndAlso c = matchOne) Then Exit Do
                If c = matchOne Then
                    If sqlite3Utf8Read(@zInput) = 0 Then Return SQLITE_NOWILDCARDMATCH
                End If
            Loop

            If c = 0 Then Return SQLITE_MATCH

            If c = matchOther Then
                If pInfo->matchSet = 0 Then
                    c = sqlite3Utf8Read(@zPattern)
                    If c = 0 Then Return SQLITE_NOWILDCARDMATCH
                Else
                    ' A character set after a wildcard needs a recursive scan.
                    While zInput[0] <> 0
                        Dim bMatch As SQLITE_C_INT = patternCompare(zPattern - 1, zInput, pInfo, matchOther)
                        If bMatch <> SQLITE_NOMATCH Then Return bMatch
                        sqlite3Utf8Read(@zInput)
                    Wend
                    Return SQLITE_NOWILDCARDMATCH
                End If
            End If

            While zInput[0] <> 0
                Dim zCandidate As Const UByte Ptr = zInput
                Dim c2 As ULong = sqlite3StringUtf8Read(zCandidate)
                Dim isCandidate As Long = 0
                If c < &H80 Then
                    If noCase <> 0 Then
                        isCandidate = (sqlite3AsciiToLower(c2) = sqlite3AsciiToLower(c))
                    Else
                        isCandidate = (c2 = c)
                    End If
                Else
                    isCandidate = (c2 = c)
                End If
                If isCandidate Then
                    Dim bMatch As SQLITE_C_INT = patternCompare(zPattern, zCandidate, pInfo, matchOther)
                    If bMatch <> SQLITE_NOMATCH Then Return bMatch
                End If
                zInput = zCandidate
            Wend
            Return SQLITE_NOWILDCARDMATCH
        End If

        If c = matchOther Then
            If pInfo->matchSet = 0 Then
                c = sqlite3Utf8Read(@zPattern)
                If c = 0 Then Return SQLITE_NOMATCH
                zEscaped = zPattern
            Else
                Dim priorC As ULong = 0
                Dim seen As Long = 0
                Dim invert As Long = 0
                c = sqlite3Utf8Read(@zInput)
                If c = 0 Then Return SQLITE_NOMATCH
                Dim c2 As ULong = sqlite3Utf8Read(@zPattern)
                If c2 = Asc("^") Then
                    invert = 1
                    c2 = sqlite3Utf8Read(@zPattern)
                End If
                If c2 = Asc("]") Then
                    If c = Asc("]") Then seen = 1
                    c2 = sqlite3Utf8Read(@zPattern)
                End If
                While c2 <> 0 AndAlso c2 <> Asc("]")
                    If c2 = Asc("-") AndAlso zPattern[0] <> Asc("]") AndAlso _
                       zPattern[0] <> 0 AndAlso priorC > 0 Then
                        c2 = sqlite3Utf8Read(@zPattern)
                        If c >= priorC AndAlso c <= c2 Then seen = 1
                        priorC = 0
                    Else
                        If c = c2 Then seen = 1
                        priorC = c2
                    End If
                    c2 = sqlite3Utf8Read(@zPattern)
                Wend
                If c2 = 0 OrElse (seen Xor invert) = 0 Then Return SQLITE_NOMATCH
                Continue Do
            End If
        End If

        Dim c2 As ULong = sqlite3StringUtf8Read(zInput)
        If c = c2 Then Continue Do
        If noCase <> 0 AndAlso c < &H80 AndAlso c2 < &H80 AndAlso _
           sqlite3AsciiToLower(c) = sqlite3AsciiToLower(c2) Then
            Continue Do
        End If
        If c = matchOne AndAlso zPattern <> zEscaped AndAlso c2 <> 0 Then Continue Do
        Return SQLITE_NOMATCH
    Loop

    If zInput[0] = 0 Then Return SQLITE_MATCH
    Return SQLITE_NOMATCH
End Function

Function sqlite3StrICmp CDecl Alias "sqlite3StrICmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT Export

    If zLeft = 0 Then Return IIf(zRight <> 0, -1, 0)
    If zRight = 0 Then Return 1

    Dim a As Const UByte Ptr = CPtr(Const UByte Ptr, zLeft)
    Dim b As Const UByte Ptr = CPtr(Const UByte Ptr, zRight)
    Do
        Dim c As ULong = a[0]
        Dim x As ULong = b[0]
        If c = x Then
            If c = 0 Then Exit Do
        Else
            c = sqlite3AsciiToLower(c)
            x = sqlite3AsciiToLower(x)
            If c <> x Then Return CLng(c) - CLng(x)
        End If
        a += 1
        b += 1
    Loop
    Return 0
End Function

Function sqlite3_stricmp CDecl Alias "sqlite3_stricmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT Export
    Return sqlite3StrICmp(zLeft, zRight)
End Function

Function sqlite3_strnicmp CDecl Alias "sqlite3_strnicmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If zLeft = 0 Then Return IIf(zRight <> 0, -1, 0)
    If zRight = 0 Then Return 1
    If nByte <= 0 Then Return 0

    Dim a As Const UByte Ptr = CPtr(Const UByte Ptr, zLeft)
    Dim b As Const UByte Ptr = CPtr(Const UByte Ptr, zRight)
    Dim remaining As SQLITE_C_INT = nByte
    While remaining > 0 AndAlso a[0] <> 0 AndAlso _
          sqlite3AsciiToLower(a[0]) = sqlite3AsciiToLower(b[0])
        a += 1
        b += 1
        remaining -= 1
    Wend
    If remaining = 0 Then Return 0
    Return CLng(sqlite3AsciiToLower(a[0])) - CLng(sqlite3AsciiToLower(b[0]))
End Function

Function sqlite3_strglob CDecl Alias "sqlite3_strglob" ( _
    ByVal zGlobPattern As Const ZString Ptr, _
    ByVal zInput As Const ZString Ptr _
) As SQLITE_C_INT Export

    If zInput = 0 Then Return IIf(zGlobPattern <> 0, 1, 0)
    If zGlobPattern = 0 Then Return 1

    Dim globInfo As CompareInfo = (GLOB_MATCH_ALL, GLOB_MATCH_ONE, GLOB_MATCH_SET, 0)
    Return patternCompare(CPtr(Const UByte Ptr, zGlobPattern), _
                          CPtr(Const UByte Ptr, zInput), @globInfo, GLOB_MATCH_SET)
End Function

Function sqlite3PatternCompare CDecl Alias "sqlite3PatternCompare" ( _
    ByVal zPattern As Const UByte Ptr, _
    ByVal zInput As Const UByte Ptr, _
    ByVal matchAll As UByte, _
    ByVal matchOne As UByte, _
    ByVal matchSet As UByte, _
    ByVal noCase As UByte, _
    ByVal matchOther As u32 _
) As SQLITE_C_INT Export
    Dim compareInfo As CompareInfo
    compareInfo.matchAll = matchAll
    compareInfo.matchOne = matchOne
    compareInfo.matchSet = matchSet
    compareInfo.noCase = noCase
    Return patternCompare(zPattern, zInput, @compareInfo, matchOther)
End Function

Function sqlite3_strlike CDecl Alias "sqlite3_strlike" ( _
    ByVal zPattern As Const ZString Ptr, _
    ByVal zInput As Const ZString Ptr, _
    ByVal escapeCharacter As SQLITE_C_UINT _
) As SQLITE_C_INT Export

    If zInput = 0 Then Return IIf(zPattern <> 0, 1, 0)
    If zPattern = 0 Then Return 1

    Dim likeInfo As CompareInfo = (LIKE_MATCH_ALL, LIKE_MATCH_ONE, 0, 1)
    Return patternCompare(CPtr(Const UByte Ptr, zPattern), _
                          CPtr(Const UByte Ptr, zInput), @likeInfo, escapeCharacter)
End Function

/' end of sqlite3_string_compare.bas '/
