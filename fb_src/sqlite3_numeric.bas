/'
    Project: SQLite FreeBASIC port

    File: sqlite3_numeric.bas

    Purpose:

        Convert SQLite integer text and integer tokens into fixed-width values.

    Responsibilities:

        - Port sqlite3Atoi64's bounded UTF-8/UTF-16 parsing and overflow rules.
        - Port decimal/hex token conversion and 32-bit integer extraction.
        - Compare the signed 64-bit boundary and render unsigned 64-bit values.

    This file intentionally does NOT contain:

        - Floating-point parsing or SQL affinity logic.
'/

#lang "fb"
#include once "sqlite3_numeric.bi"
#include once "sqlite3_constants.bi"

Extern "C"
    Declare Function sqlite3NumericMemcpy CDecl Alias "memcpy" ( _
        ByVal destination As Any Ptr, _
        ByVal source As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
End Extern

Private Function sqlite3NumericIsSpace(ByVal value As Long) As Long
    If value = 32 OrElse (value >= 9 AndAlso value <= 13) Then Return -1
    Return 0
End Function

Private Function sqlite3NumericByte( _
    ByVal z As Const UByte Ptr, _
    ByVal byteOffset As Long, _
    ByVal enc As u8 _
) As Long
    If enc = SQLITE_UTF16BE Then Return z[byteOffset + 1]
    Return z[byteOffset]
End Function

Private Function sqlite3NumericHighByte( _
    ByVal z As Const UByte Ptr, _
    ByVal byteOffset As Long, _
    ByVal enc As u8 _
) As Long
    If enc = SQLITE_UTF16BE Then Return z[byteOffset]
    Return z[byteOffset + 1]
End Function

Private Function sqlite3NumericHexDigit(ByVal value As Long) As Long
    If value >= Asc("0") AndAlso value <= Asc("9") Then Return value - Asc("0")
    If value >= Asc("A") AndAlso value <= Asc("F") Then Return value - Asc("A") + 10
    If value >= Asc("a") AndAlso value <= Asc("f") Then Return value - Asc("a") + 10
    Return -1
End Function

Private Function compare2pow63( _
    ByVal zNum As Const UByte Ptr, _
    ByVal increment As SQLITE_C_INT _
) As SQLITE_C_INT
    If zNum = 0 OrElse (increment <> 1 AndAlso increment <> 2) Then Return 0
    ' Advance one byte per digit when comparing against the signed boundary.
    Dim prefix As Const UByte Ptr = _
        CPtr(Const UByte Ptr, StrPtr("922337203685477580"))
    Dim comparison As SQLITE_C_INT = 0
    For index As SQLITE_C_INT = 0 To 17
        If comparison <> 0 Then Exit For
        comparison = (CLng(zNum[index * increment]) - _
                      CLng(prefix[index])) * 10
    Next
    If comparison = 0 Then _
        comparison = CLng(zNum[18 * increment]) - Asc("8")
    Return comparison
End Function

Function sqlite3Atoi64 CDecl Alias "sqlite3Atoi64" ( _
    ByVal zArgument As Const Any Ptr, _
    ByVal pNum As sqlite3_int64 Ptr, _
    ByVal inputLength As SQLITE_C_INT, _
    ByVal enc As u8 _
) As SQLITE_C_INT Export

    If pNum = 0 Then Return -1
    *pNum = 0
    If zArgument = 0 OrElse inputLength < 0 Then Return -1
    If enc <> SQLITE_UTF8 AndAlso enc <> SQLITE_UTF16LE AndAlso enc <> SQLITE_UTF16BE Then
        Return -1
    End If

    Dim z As Const UByte Ptr = CPtr(Const UByte Ptr, zArgument)
    Dim byteLength As Long = inputLength
    Dim stepBytes As Long = 1
    Dim nonAsciiUtf16 As Long = 0
    If enc <> SQLITE_UTF8 Then
        byteLength = byteLength And Not 1
        stepBytes = 2
        ' Integer syntax is ASCII. Stop at the first UTF-16 code unit with a
        ' nonzero high byte, as SQLite does, and report trailing text below.
        Dim checkOffset As Long = 0
        While checkOffset < byteLength
            If sqlite3NumericHighByte(z, checkOffset, enc) <> 0 Then
                byteLength = checkOffset
                nonAsciiUtf16 = -1
                Exit While
            End If
            checkOffset += 2
        Wend
    End If

    Dim offset As Long = 0
    While offset < byteLength AndAlso sqlite3NumericIsSpace(sqlite3NumericByte(z, offset, enc)) <> 0
        offset += stepBytes
    Wend

    Dim negative As Long = 0
    If offset < byteLength Then
        Dim firstByte As Long = sqlite3NumericByte(z, offset, enc)
        If firstByte = Asc("-") Then
            negative = -1
            offset += stepBytes
        ElseIf firstByte = Asc("+") Then
            offset += stepBytes
        End If
    End If

    Dim skippedZeroes As Long = 0
    While offset < byteLength AndAlso sqlite3NumericByte(z, offset, enc) = Asc("0")
        skippedZeroes += 1
        offset += stepBytes
    Wend
    Dim digitStartOffset As Long = offset

    Dim digitCount As Long = 0
    Dim unsignedValue As ULongInt = 0
    While offset < byteLength
        Dim digit As Long = sqlite3NumericByte(z, offset, enc) - Asc("0")
        If digit < 0 OrElse digit > 9 Then Exit While
        digitCount += 1
        If digitCount <= 19 Then unsignedValue = unsignedValue * 10 + CULngInt(digit)
        offset += stepBytes
    Wend

    If skippedZeroes = 0 AndAlso digitCount = 0 Then Return -1

    Dim trailingStatus As SQLITE_C_INT = 0
    If nonAsciiUtf16 <> 0 Then
        trailingStatus = 1
    Else
        While offset < byteLength
            If sqlite3NumericIsSpace(sqlite3NumericByte(z, offset, enc)) = 0 Then
                trailingStatus = 1
                Exit While
            End If
            offset += stepBytes
        Wend
    End If

    Const MAX_SIGNED As ULongInt = &H7FFFFFFFFFFFFFFF
    ' After leading zeroes are removed, at most 19 digits fit in the unsigned
    ' accumulator. The exact 2^63 magnitude is valid only for a negative value.
    Dim overflow As Long = 0
    If digitCount > 19 Then
        overflow = -1
    ElseIf digitCount = 19 Then
        Dim zDigits As Const UByte Ptr = z + digitStartOffset
        If enc = SQLITE_UTF16BE Then zDigits += 1
        Dim comparison As SQLITE_C_INT = compare2pow63(zDigits, stepBytes)
        If comparison > 0 Then
            overflow = -1
        ElseIf comparison = 0 AndAlso negative = 0 Then
            *pNum = CLngInt(MAX_SIGNED)
            Return 3
        End If
    End If

    If overflow <> 0 Then
        If negative <> 0 Then
            *pNum = -CLngInt(MAX_SIGNED) - 1
        Else
            *pNum = CLngInt(MAX_SIGNED)
        End If
        Return 2
    End If

    If negative <> 0 Then
        If digitCount = 19 AndAlso unsignedValue = &H8000000000000000ULL Then
            *pNum = -CLngInt(MAX_SIGNED) - 1
        Else
            *pNum = -CLngInt(unsignedValue)
        End If
    Else
        *pNum = CLngInt(unsignedValue)
    End If
    Return trailingStatus
End Function

Function sqlite3DecOrHexToI64 CDecl Alias "sqlite3DecOrHexToI64" ( _
    ByVal zNum As Const ZString Ptr, _
    ByVal pNum As sqlite3_int64 Ptr _
) As SQLITE_C_INT Export

    If pNum <> 0 Then *pNum = 0
    If zNum = 0 OrElse pNum = 0 Then Return 2
    Dim z As Const UByte Ptr = CPtr(Const UByte Ptr, zNum)

    If z[0] = Asc("0") AndAlso (z[1] = Asc("x") OrElse z[1] = Asc("X")) Then
        Dim offset As Long = 2
        While z[offset] = Asc("0")
            offset += 1
        Wend
        Dim firstSignificantDigit As Long = offset
        Dim unsignedValue As ULongInt = 0
        While sqlite3NumericHexDigit(z[offset]) >= 0
            unsignedValue = unsignedValue * 16 + CULngInt(sqlite3NumericHexDigit(z[offset]))
            offset += 1
        Wend
        Dim digitCount As Long = offset - firstSignificantDigit
        ' Copy the unsigned bit pattern; values above INT64_MAX are not cast.
        sqlite3NumericMemcpy(pNum, @unsignedValue, SizeOf(unsignedValue))
        If digitCount > 16 Then Return 2
        If z[offset] <> 0 Then Return 1
        Return 0
    End If

    Dim inputLength As Long = 0
    While inputLength < &H3FFFFFFF
        Dim value As Long = z[inputLength]
        If (value >= Asc("0") AndAlso value <= Asc("9")) OrElse _
           value = Asc("+") OrElse value = Asc("-") OrElse value = 32 OrElse _
           value = 9 OrElse value = 10 Then
            inputLength += 1
        Else
            Exit While
        End If
    Wend
    If z[inputLength] <> 0 Then inputLength += 1
    Return sqlite3Atoi64(zNum, pNum, inputLength, SQLITE_UTF8)
End Function

Function sqlite3GetInt32 CDecl Alias "sqlite3GetInt32" ( _
    ByVal zArgument As Const ZString Ptr, _
    ByVal pValue As SQLITE_C_INT Ptr _
) As SQLITE_C_INT Export

    If zArgument = 0 OrElse pValue = 0 Then Return 0
    Dim z As Const UByte Ptr = CPtr(Const UByte Ptr, zArgument)
    Dim negative As Long = 0
    If z[0] = Asc("-") Then
        negative = -1
        z += 1
    ElseIf z[0] = Asc("+") Then
        z += 1
    ElseIf z[0] = Asc("0") AndAlso _
           (z[1] = Asc("x") OrElse z[1] = Asc("X")) AndAlso _
           sqlite3NumericHexDigit(z[2]) >= 0 Then
        Dim unsignedValue As ULong = 0
        z += 2
        While z[0] = Asc("0")
            z += 1
        Wend
        Dim digitCount As Long = 0
        While digitCount < 8 AndAlso sqlite3NumericHexDigit(z[digitCount]) >= 0
            unsignedValue = unsignedValue * 16 + CULng(sqlite3NumericHexDigit(z[digitCount]))
            digitCount += 1
        Wend
        If (unsignedValue And &H80000000) <> 0 OrElse _
           sqlite3NumericHexDigit(z[digitCount]) >= 0 Then Return 0
        sqlite3NumericMemcpy(pValue, @unsignedValue, SizeOf(*pValue))
        Return 1
    End If

    If z[0] < Asc("0") OrElse z[0] > Asc("9") Then Return 0
    While z[0] = Asc("0")
        z += 1
    Wend

    Dim value As sqlite3_int64 = 0
    Dim digitCount As Long = 0
    While digitCount < 11 AndAlso z[digitCount] >= Asc("0") AndAlso z[digitCount] <= Asc("9")
        value = value * 10 + (z[digitCount] - Asc("0"))
        digitCount += 1
    Wend
    If digitCount > 10 Then Return 0
    If value - negative > 2147483647 Then Return 0
    If negative <> 0 Then value = -value
    *pValue = CLng(value)
    Return 1
End Function

Function sqlite3Atoi CDecl Alias "sqlite3Atoi" ( _
    ByVal zNum As Const ZString Ptr _
) As SQLITE_C_INT Export

    Dim value As SQLITE_C_INT = 0
    sqlite3GetInt32(zNum, @value)
    Return value
End Function

Private Function sqlite3UInt64ToText( _
    ByVal value As sqlite3_uint64, _
    ByVal zOut As UByte Ptr _
) As SQLITE_C_INT
    If zOut = 0 Then Return 20
    Dim position As SQLITE_C_INT = 20
    zOut[position] = 0
    Dim remaining As ULongInt = value
    While (remaining Shr 32) <> 0
        Dim block As ULong = CULng(remaining Mod 100000000)
        remaining = remaining \ 100000000
        Dim lowerFour As ULong = block Mod 10000
        block = block \ 10000
        Dim pair3 As ULong = block \ 100
        Dim pair2 As ULong = block Mod 100
        Dim pair1 As ULong = lowerFour \ 100
        Dim pair0 As ULong = lowerFour Mod 100
        If position < 8 Then Return 20
        position -= 8
        zOut[position] = CUByte(Asc("0") + CInt(pair3 \ 10))
        zOut[position + 1] = CUByte(Asc("0") + CInt(pair3 Mod 10))
        zOut[position + 2] = CUByte(Asc("0") + CInt(pair2 \ 10))
        zOut[position + 3] = CUByte(Asc("0") + CInt(pair2 Mod 10))
        zOut[position + 4] = CUByte(Asc("0") + CInt(pair1 \ 10))
        zOut[position + 5] = CUByte(Asc("0") + CInt(pair1 Mod 10))
        zOut[position + 6] = CUByte(Asc("0") + CInt(pair0 \ 10))
        zOut[position + 7] = CUByte(Asc("0") + CInt(pair0 Mod 10))
    Wend

    Dim upperBlock As ULong = CULng(remaining)
    While upperBlock >= 10
        Dim digitPair As ULong = upperBlock Mod 100
        upperBlock = upperBlock \ 100
        If position < 2 Then Return 20
        position -= 2
        zOut[position] = CUByte(Asc("0") + CInt(digitPair \ 10))
        zOut[position + 1] = CUByte(Asc("0") + CInt(digitPair Mod 10))
    Wend
    If upperBlock <> 0 Then
        position -= 1
        zOut[position] = CUByte(Asc("0") + CInt(upperBlock))
    ElseIf position = 20 Then
        position -= 1
        zOut[position] = Asc("0")
    End If
    Return position
End Function

Function sqlite3Int64ToText CDecl Alias "sqlite3Int64ToText" ( _
    ByVal inputValue As sqlite3_int64, _
    ByVal zOut As ZString Ptr _
) As SQLITE_C_INT Export

    If zOut = 0 Then Return SQLITE_MISUSE
    Dim digitBuffer(0 To 20) As UByte
    Dim negative As Long = 0
    Dim magnitude As ULongInt
    If inputValue < 0 Then
        negative = -1
        magnitude = CULngInt(-(inputValue + 1)) + 1
    Else
        magnitude = CULngInt(inputValue)
    End If

    Dim position As SQLITE_C_INT = sqlite3UInt64ToText(magnitude, @digitBuffer(0))
    If negative <> 0 Then
        position -= 1
        digitBuffer(position) = Asc("-")
    End If

    Dim length As Long = 20 - position
    sqlite3NumericMemcpy(zOut, @digitBuffer(position), CULng(length + 1))
    Return CInt(length)
End Function

/' end of sqlite3_numeric.bas '/
