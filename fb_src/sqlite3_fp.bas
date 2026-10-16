/'
    Project: SQLite FreeBASIC port

    File: sqlite3_fp.bas

    Purpose:

        Parse SQLite decimal text and render doubles deterministically.

    Responsibilities:

        - Port SQLite's base-10 power tables and integer multiplication helpers.
        - Preserve sqlite3AtoF's mantissa, exponent, and parse-status behavior.
        - Render the VDBE's significant-digit real format from the same tables.

    This file intentionally does NOT contain:

        - General SQL printf formatting or arbitrary-precision decimal arithmetic.
'/

#lang "fb"
#include once "sqlite3_fp.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_fp10_tables.bi"
#ifdef SQLITE_DEBUG
#include once "sqlite3_debug_assert.bi"
#endif

Extern "C"
    Declare Function sqlite3FpCopy CDecl Alias "memcpy" ( _
        ByVal destination As Any Ptr, _
        ByVal source As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
End Extern

Private Const SQLITE_FP_POWERSOF10_FIRST As Long = -348
Private Const SQLITE_FP_POWERSOF10_LAST As Long = 347
Private Const SQLITE_FP_MANTISSA_LIMIT As ULongInt = 1844674407370955160
Private Const SQLITE_FP_WORD_MASK As ULongInt = &HFFFFFFFF

Private Type SqliteFpDecode
    n As Long
    iDP As Long
    z As UByte Ptr
    zBuf(0 To 20) As UByte
    sign As UByte
    isSpecial As UByte
End Type

Private Function sqlite3FpU64Bit(ByVal bitNumber As Long) As ULongInt
    If bitNumber < 0 OrElse bitNumber > 63 Then Return 0
    Return CULngInt(1) Shl bitNumber
End Function

Private Function sqlite3FpJoinWords(ByVal highWord As ULong, ByVal lowWord As ULong) As ULongInt
    Return (CULngInt(highWord) Shl 32) Or CULngInt(lowWord)
End Function

Private Function sqlite3Multiply128( _
    ByVal a As ULongInt, _
    ByVal b As ULongInt, _
    ByVal pLow As ULongInt Ptr _
) As ULongInt

    If pLow = 0 Then Return 0
    Dim a0 As ULongInt = a And SQLITE_FP_WORD_MASK
    Dim a1 As ULongInt = a Shr 32
    Dim b0 As ULongInt = b And SQLITE_FP_WORD_MASK
    Dim b1 As ULongInt = b Shr 32
    Dim a0b0 As ULongInt = a0 * b0
    Dim a1b1 As ULongInt = a1 * b1
    Dim a0b1 As ULongInt = a0 * b1
    Dim a1b0 As ULongInt = a1 * b0
    Dim t As ULongInt = (a0b0 Shr 32) + (a0b1 And SQLITE_FP_WORD_MASK) + _
                        (a1b0 And SQLITE_FP_WORD_MASK)
    *pLow = (a0b0 And SQLITE_FP_WORD_MASK) Or (t Shl 32)
    Return a1b1 + (a0b1 Shr 32) + (a1b0 Shr 32) + (t Shr 32)
End Function

Private Function sqlite3Multiply160( _
    ByVal a As ULongInt, _
    ByVal aLow As ULong, _
    ByVal b As ULongInt, _
    ByVal pLow As ULong Ptr _
) As ULongInt

    If pLow = 0 Then Return 0
    Dim x2 As ULongInt = a Shr 32
    Dim x1 As ULongInt = a And SQLITE_FP_WORD_MASK
    Dim x0 As ULongInt = aLow
    Dim y1 As ULongInt = b Shr 32
    Dim y0 As ULongInt = b And SQLITE_FP_WORD_MASK
    Dim x2y1 As ULongInt = x2 * y1
    Dim r4 As ULongInt = x2y1 Shr 32
    Dim x2y0 As ULongInt = x2 * y0
    Dim x1y1 As ULongInt = x1 * y1
    Dim r3 As ULongInt = (x2y1 And SQLITE_FP_WORD_MASK) + (x2y0 Shr 32) + (x1y1 Shr 32)
    Dim x1y0 As ULongInt = x1 * y0
    Dim x0y1 As ULongInt = x0 * y1
    Dim r2 As ULongInt = (x2y0 And SQLITE_FP_WORD_MASK) + (x1y1 And SQLITE_FP_WORD_MASK) + _
                         (x1y0 Shr 32) + (x0y1 Shr 32)
    Dim x0y0 As ULongInt = x0 * y0
    Dim r1 As ULongInt = (x1y0 And SQLITE_FP_WORD_MASK) + (x0y1 And SQLITE_FP_WORD_MASK) + _
                         (x0y0 Shr 32)
    r2 += r1 Shr 32
    r3 += r2 Shr 32
    *pLow = CULng(r2 And SQLITE_FP_WORD_MASK)
    Return (r4 Shl 32) + r3
End Function

Private Function powerOfTen( _
    ByVal exponent As Long, _
    ByVal pLow As ULong Ptr _
) As ULongInt

    If pLow = 0 OrElse exponent < SQLITE_FP_POWERSOF10_FIRST OrElse _
       exponent > SQLITE_FP_POWERSOF10_LAST Then Return 0

    Dim groupIndex As Long
    Dim baseIndex As Long
    If exponent < 0 Then
        If exponent = -1 Then
            *pLow = sqlite3Fp10ScaleTail(13)
            Return sqlite3FpJoinWords(sqlite3Fp10ScaleHigh(13), sqlite3Fp10ScaleLow(13))
        End If
        groupIndex = -((-exponent) \ 27)
        baseIndex = exponent - groupIndex * 27
        If baseIndex <> 0 Then
            groupIndex -= 1
            baseIndex += 27
        End If
    ElseIf exponent < 27 Then
        *pLow = 0
        Return sqlite3FpJoinWords(sqlite3Fp10BaseHigh(exponent), sqlite3Fp10BaseLow(exponent))
    Else
        groupIndex = exponent \ 27
        baseIndex = exponent - groupIndex * 27
    End If

    Dim scaleIndex As Long = groupIndex + 13
    If scaleIndex < 0 OrElse scaleIndex > 25 OrElse baseIndex < 0 OrElse baseIndex > 26 Then
        *pLow = 0
        Return 0
    End If
    Dim scaleValue As ULongInt = sqlite3FpJoinWords( _
        sqlite3Fp10ScaleHigh(scaleIndex), sqlite3Fp10ScaleLow(scaleIndex))
    If baseIndex = 0 Then
        *pLow = sqlite3Fp10ScaleTail(scaleIndex)
        Return scaleValue
    End If

    Dim lowWord As ULong = 0
    Dim result As ULongInt = sqlite3Multiply160( _
        scaleValue, sqlite3Fp10ScaleTail(scaleIndex), _
        sqlite3FpJoinWords(sqlite3Fp10BaseHigh(baseIndex), sqlite3Fp10BaseLow(baseIndex)), _
        @lowWord)
    If (result And sqlite3FpU64Bit(63)) = 0 Then
        result = (result Shl 1) Or CULngInt((lowWord Shr 31) And 1)
        lowWord = (lowWord Shl 1) Or 1
    End If
    *pLow = lowWord
    Return result
End Function

Private Function pwr10to2(ByVal exponent As Long) As Long
    Dim numerator As LongInt = CLngInt(exponent) * 108853
    If numerator >= 0 Then Return CLng(numerator \ 32768)
    Return -CLng((-numerator + 32767) \ 32768)
End Function

Private Function pwr2to10(ByVal exponent As Long) As Long
    Dim numerator As LongInt = CLngInt(exponent) * 78913
    If numerator >= 0 Then Return CLng(numerator \ 262144)
    Return -CLng((-numerator + 262143) \ 262144)
End Function

Private Function countLeadingZeros(ByVal value As ULongInt) As Long
    If value = 0 Then Return 64
    Dim count As Long = 0
    Dim remaining As ULongInt = value
    While (remaining And sqlite3FpU64Bit(63)) = 0
        count += 1
        remaining = remaining Shl 1
    Wend
    Return count
End Function

Private Function sqlite3Fp10Convert2(ByVal significand As ULongInt, ByVal exponent As Long) As Double
    If significand = 0 Then Return 0.0
    If exponent < SQLITE_FP_POWERSOF10_FIRST Then Return 0.0
    If exponent > SQLITE_FP_POWERSOF10_LAST Then
        Dim infinityBits As ULongInt = sqlite3FpJoinWords(&H7FF00000, 0)
        Dim infinityValue As Double
        sqlite3FpCopy(@infinityValue, @infinityBits, SizeOf(infinityBits))
        Return infinityValue
    End If

    Dim bitCount As Long = 64 - countLeadingZeros(significand)
    Dim logarithm As Long = pwr10to2(exponent)
    Dim binaryExponent As Long = 53 - bitCount - logarithm
    If binaryExponent > 1074 Then
        If binaryExponent >= 1130 Then Return 0.0
        binaryExponent = 1074
    End If

    Dim shift As Long = -(binaryExponent - (64 - bitCount) + logarithm + 3)
    If shift < 0 OrElse shift > 63 Then Return 0.0
    Dim powerLow As ULong = 0
    Dim powerHigh As ULongInt = powerOfTen(exponent, @powerLow)
    If powerLow <> 0 Then
        powerHigh += 1
        powerLow = powerLow Xor &HFFFFFFFF
    End If

    Dim normalizedSignificand As ULongInt = significand Shl (64 - bitCount)
    Dim lowProduct As ULongInt = 0
    Dim highProduct As ULongInt = sqlite3Multiply128(normalizedSignificand, powerHigh, @lowProduct)
    Dim middleHigh As ULong = CULng(lowProduct Shr 32)
    Dim sticky As ULongInt = 1
    If (highProduct And (sqlite3FpU64Bit(shift) - 1)) = 0 Then
        Dim ignoredLow As ULongInt = 0
        Dim partialProduct As ULongInt = sqlite3Multiply128( _
            normalizedSignificand, CULngInt(powerLow) Shl 32, @ignoredLow)
        Dim middleLow As ULong = CULng(partialProduct Shr 32)
        Dim difference As ULong = middleHigh - middleLow
        sticky = 0
        If difference > 1 Then sticky = 1
        If middleHigh < middleLow Then highProduct -= 1
    End If

    Dim rounded As ULongInt = (highProduct Shr shift) Or sticky
    Dim adjustment As Long = 0
    If rounded >= sqlite3FpU64Bit(55) - 2 Then adjustment = 1
    If adjustment <> 0 Then
        rounded = (rounded Shr adjustment) Or (rounded And 1)
        binaryExponent -= adjustment
    End If

    Dim mantissa As ULongInt = (rounded + 1 + ((rounded Shr 2) And 1)) Shr 2
    If binaryExponent <= -972 Then
        Dim infinityBits As ULongInt = sqlite3FpJoinWords(&H7FF00000, 0)
        Dim infinityValue As Double
        sqlite3FpCopy(@infinityValue, @infinityBits, SizeOf(infinityBits))
        Return infinityValue
    End If
    If (mantissa And sqlite3FpU64Bit(52)) <> 0 Then
        mantissa = (mantissa And Not sqlite3FpU64Bit(52)) Or _
                   (CULngInt(1075 - binaryExponent) Shl 52)
    End If

    Dim result As Double
    sqlite3FpCopy(@result, @mantissa, SizeOf(mantissa))
    Return result
End Function

Private Sub sqlite3Fp2Convert10( _
    ByVal significand As ULongInt, _
    ByVal binaryExponent As Long, _
    ByVal digitCount As Long, _
    ByRef decimalSignificand As ULongInt, _
    ByRef decimalExponent As Long _
)
    Dim powerExponent As Long = digitCount - 1 - pwr2to10(binaryExponent + 63)
    Dim powerLow As ULong = 0
    Dim lowProduct As ULongInt = 0
    Dim highProduct As ULongInt = sqlite3Multiply128( _
        significand, powerOfTen(powerExponent, @powerLow), @lowProduct)
    Dim shift As Long = -(binaryExponent + pwr10to2(powerExponent) + 1)

    If digitCount = 18 Then
        shift -= 1
        If shift < 0 OrElse shift > 63 Then
            decimalSignificand = 0
            decimalExponent = 0
            Exit Sub
        End If
        highProduct = highProduct Shr shift
        decimalSignificand = (highProduct + ((highProduct Shl 1) And 2)) Shr 1
    Else
        If shift < 0 OrElse shift > 63 Then
            decimalSignificand = 0
            decimalExponent = 0
            Exit Sub
        End If
        decimalSignificand = highProduct Shr shift
    End If
    decimalExponent = -powerExponent
End Sub

Private Function sqlite3FpUint64ToText( _
    ByVal value As ULongInt, _
    ByVal zOutput As UByte Ptr _
) As Long
    Dim position As Long = 20
    zOutput[position] = 0
    Do
        position -= 1
        zOutput[position] = CUByte(Asc("0") + CInt(value Mod 10))
        value = value \ 10
    Loop While value <> 0
    Return position
End Function

Private Sub sqlite3FpDecode( _
    ByRef result As SqliteFpDecode, _
    ByVal inputValue As Double, _
    ByVal requestedDigits As Long, _
    ByVal maxDigits As Long _
)
    Dim value As Double = inputValue
    Dim bits As ULongInt
    Dim significand As ULongInt
    Dim binaryExponent As Long
    Dim decimalSignificand As ULongInt
    Dim decimalExponent As Long = 0
    Dim index As Long

    result.isSpecial = 0
    If value < 0.0 Then
        result.sign = Asc("-")
        value = -value
    ElseIf value = 0.0 Then
        result.sign = Asc("+")
        result.n = 1
        result.iDP = 1
        result.zBuf(0) = Asc("0")
        result.zBuf(1) = 0
        result.z = @result.zBuf(0)
        Exit Sub
    Else
        result.sign = Asc("+")
    End If

    sqlite3FpCopy(@bits, @value, SizeOf(bits))
    binaryExponent = CInt((bits Shr 52) And &H7FF)
    If binaryExponent = &H7FF Then
        result.isSpecial = 1
        If bits <> sqlite3FpJoinWords(&H7FF00000, 0) Then result.isSpecial = 2
        result.n = 0
        result.iDP = 0
        result.z = @result.zBuf(0)
        Exit Sub
    End If

    significand = bits And &H000FFFFFFFFFFFFF
    If binaryExponent = 0 Then
        Dim leadingZeroes As Long = countLeadingZeros(significand)
        significand = significand Shl leadingZeroes
        binaryExponent = -1074 - leadingZeroes
    Else
        significand = (significand Shl 11) Or sqlite3FpU64Bit(63)
        binaryExponent -= 1086
    End If

    Dim conversionDigits As Long = requestedDigits
    If conversionDigits <= 0 OrElse conversionDigits >= 18 Then conversionDigits = 18
    If conversionDigits < 18 Then conversionDigits += 1
    sqlite3Fp2Convert10(significand, binaryExponent, conversionDigits, _
                        decimalSignificand, decimalExponent)
    If decimalSignificand = 0 Then
        result.n = 1
        result.iDP = 1
        result.zBuf(0) = Asc("0")
        result.zBuf(1) = 0
        result.z = @result.zBuf(0)
        Exit Sub
    End If

    index = sqlite3FpUint64ToText(decimalSignificand, @result.zBuf(0))
    result.n = 20 - index
    result.iDP = result.n + decimalExponent
    If requestedDigits <= 0 Then
        requestedDigits = result.iDP - requestedDigits
        If requestedDigits = 0 AndAlso result.zBuf(index) >= Asc("5") Then
            requestedDigits = 1
            index -= 1
            result.zBuf(index) = Asc("0")
            result.n += 1
            result.iDP += 1
        End If
    End If

    Dim zDigits As UByte Ptr = @result.zBuf(index)
    If requestedDigits > 0 AndAlso _
       (requestedDigits < result.n OrElse result.n > maxDigits) Then
        If requestedDigits > maxDigits Then requestedDigits = maxDigits
        If requestedDigits = 17 Then
            If zDigits[15] = Asc("9") AndAlso zDigits[14] = Asc("9") Then
                Dim checkDigits As Long = 14
                While checkDigits > 0 AndAlso zDigits[checkDigits - 1] = Asc("9")
                    checkDigits -= 1
                Wend
                Dim candidate As ULongInt = 1
                If checkDigits <> 0 Then
                    candidate = CULngInt(zDigits[0] - Asc("0"))
                    For i As Long = 1 To checkDigits - 1
                        candidate = candidate * 10 + CULngInt(zDigits[i] - Asc("0"))
                    Next
                    candidate += 1
                End If
                If sqlite3Fp10Convert2(candidate, decimalExponent + result.n - checkDigits) = value Then
                    requestedDigits = checkDigits + 1
                End If
            ElseIf result.iDP >= result.n OrElse _
                   (zDigits[15] = Asc("0") AndAlso zDigits[14] = Asc("0") AndAlso _
                    zDigits[13] = Asc("0")) Then
                Dim checkDigits As Long = 13
                While zDigits[checkDigits - 1] = Asc("0")
                    checkDigits -= 1
                Wend
                Dim candidate As ULongInt = CULngInt(zDigits[0] - Asc("0"))
                For i As Long = 1 To checkDigits - 1
                    candidate = candidate * 10 + CULngInt(zDigits[i] - Asc("0"))
                Next
                If sqlite3Fp10Convert2(candidate, decimalExponent + result.n - checkDigits) = value Then
                    requestedDigits = checkDigits + 1
                End If
            End If
        End If

        result.n = requestedDigits
        If zDigits[requestedDigits] >= Asc("5") Then
            Dim roundPosition As Long = requestedDigits - 1
            While 1
                zDigits[roundPosition] += 1
                If zDigits[roundPosition] <= Asc("9") Then Exit While
                zDigits[roundPosition] = Asc("0")
                If roundPosition = 0 Then
                    zDigits -= 1
                    zDigits[0] = Asc("1")
                    result.n += 1
                    result.iDP += 1
                    Exit While
                End If
                roundPosition -= 1
            Wend
        End If
    End If

    While result.n > 1 AndAlso zDigits[result.n - 1] = Asc("0")
        result.n -= 1
    Wend
    result.z = zDigits
End Sub

Private Sub sqlite3FpAppendByte( _
    ByVal zOutput As UByte Ptr, _
    ByRef outputLength As Long, _
    ByVal value As Long _
)
    zOutput[outputLength] = CUByte(value)
    outputLength += 1
End Sub

Function fbFpFormatDouble ( _
    ByVal value As Double, _
    ByVal significantDigitsInput As SQLITE_C_INT, _
    ByVal zOutput As UByte Ptr, _
    ByVal outputSize As SQLITE_C_INT _
) As SQLITE_C_INT

    If zOutput = 0 Then Return -SQLITE_MISUSE
    If outputSize < 32 Then Return -SQLITE_TOOBIG
    Dim significantDigits As Long = significantDigitsInput
    If significantDigits < 1 Then significantDigits = 6
    If significantDigits > 23 Then significantDigits = 23

    Dim decoded As SqliteFpDecode
    sqlite3FpDecode(decoded, value, significantDigits, 20)
    Dim outputLength As Long = 0
    If decoded.isSpecial = 2 Then
        sqlite3FpAppendByte(zOutput, outputLength, Asc("N"))
        sqlite3FpAppendByte(zOutput, outputLength, Asc("a"))
        sqlite3FpAppendByte(zOutput, outputLength, Asc("N"))
    ElseIf decoded.isSpecial = 1 Then
        If decoded.sign = Asc("-") Then sqlite3FpAppendByte(zOutput, outputLength, Asc("-"))
        sqlite3FpAppendByte(zOutput, outputLength, Asc("I"))
        sqlite3FpAppendByte(zOutput, outputLength, Asc("n"))
        sqlite3FpAppendByte(zOutput, outputLength, Asc("f"))
    Else
        If decoded.sign = Asc("-") Then sqlite3FpAppendByte(zOutput, outputLength, Asc("-"))
        Dim decimalExponent As Long = decoded.iDP - 1
        Dim formatPrecision As Long = significantDigits - 1
        Dim scientific As Long = 0
        If decimalExponent < -4 OrElse decimalExponent > formatPrecision Then scientific = -1

        If scientific <> 0 Then
            sqlite3FpAppendByte(zOutput, outputLength, decoded.z[0])
            sqlite3FpAppendByte(zOutput, outputLength, Asc("."))
            If decoded.n > 1 Then
                For i As Long = 1 To decoded.n - 1
                    sqlite3FpAppendByte(zOutput, outputLength, decoded.z[i])
                Next
            Else
                sqlite3FpAppendByte(zOutput, outputLength, Asc("0"))
            End If
            sqlite3FpAppendByte(zOutput, outputLength, Asc("e"))
            If decimalExponent < 0 Then
                sqlite3FpAppendByte(zOutput, outputLength, Asc("-"))
                decimalExponent = -decimalExponent
            Else
                sqlite3FpAppendByte(zOutput, outputLength, Asc("+"))
            End If
            If decimalExponent >= 100 Then
                sqlite3FpAppendByte(zOutput, outputLength, Asc("0") + (decimalExponent \ 100))
                decimalExponent = decimalExponent Mod 100
            End If
            sqlite3FpAppendByte(zOutput, outputLength, Asc("0") + (decimalExponent \ 10))
            sqlite3FpAppendByte(zOutput, outputLength, Asc("0") + (decimalExponent Mod 10))
        Else
            Dim decimalPoint As Long = decoded.iDP
            If decimalPoint <= 0 Then
                sqlite3FpAppendByte(zOutput, outputLength, Asc("0"))
            Else
                Dim storedIntegerDigits As Long = decimalPoint
                If storedIntegerDigits > decoded.n Then storedIntegerDigits = decoded.n
                For i As Long = 0 To storedIntegerDigits - 1
                    sqlite3FpAppendByte(zOutput, outputLength, decoded.z[i])
                Next
                For i As Long = decoded.n To decimalPoint - 1
                    sqlite3FpAppendByte(zOutput, outputLength, Asc("0"))
                Next
            End If

            sqlite3FpAppendByte(zOutput, outputLength, Asc("."))
            Dim fractionStart As Long = outputLength
            If decimalPoint < 0 Then
                For i As Long = 0 To -decimalPoint - 1
                    sqlite3FpAppendByte(zOutput, outputLength, Asc("0"))
                Next
                For i As Long = 0 To decoded.n - 1
                    sqlite3FpAppendByte(zOutput, outputLength, decoded.z[i])
                Next
            ElseIf decimalPoint < decoded.n Then
                For i As Long = decimalPoint To decoded.n - 1
                    sqlite3FpAppendByte(zOutput, outputLength, decoded.z[i])
                Next
            End If
            While outputLength > fractionStart AndAlso zOutput[outputLength - 1] = Asc("0")
                outputLength -= 1
            Wend
            If outputLength = fractionStart Then sqlite3FpAppendByte(zOutput, outputLength, Asc("0"))
        End If
    End If

    If outputLength >= outputSize Then Return -SQLITE_TOOBIG
    zOutput[outputLength] = 0
    Return CInt(outputLength)
End Function

Private Function sqlite3FpFormatAppend( _
    ByVal zOutput As UByte Ptr, _
    ByRef outputLength As Long, _
    ByVal outputSize As Long, _
    ByVal value As Long _
) As Long
    If outputLength < 0 OrElse outputLength >= outputSize - 1 Then Return 0
    zOutput[outputLength] = CUByte(value)
    outputLength += 1
    Return -1
End Function

Function sqlite3FpFormatPrintf CDecl Alias "sqlite3FpFormatPrintf" ( _
    ByVal value As Double, _
    ByVal formatType As UByte, _
    ByVal precisionInput As SQLITE_C_INT, _
    ByVal alternateForm As SQLITE_C_INT, _
    ByVal zeroPad As SQLITE_C_INT, _
    ByVal thousands As SQLITE_C_INT, _
    ByVal trimZeroes As SQLITE_C_INT, _
    ByVal zOutput As UByte Ptr, _
    ByVal outputSize As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If zOutput = 0 OrElse outputSize < 2 Then Return -SQLITE_MISUSE
    If formatType <> Asc("f") AndAlso formatType <> Asc("F") AndAlso _
       formatType <> Asc("e") AndAlso formatType <> Asc("E") AndAlso _
       formatType <> Asc("g") AndAlso formatType <> Asc("G") Then Return -SQLITE_MISUSE

    Dim precision As Long = precisionInput
    If precision < 0 Then precision = 6
    If precision > outputSize - 16 Then Return -SQLITE_TOOBIG

    Dim formatMode As UByte = formatType
    Dim significantDigits As Long
    If formatMode = Asc("f") OrElse formatMode = Asc("F") Then
        significantDigits = 0 - precision
    ElseIf formatMode = Asc("e") OrElse formatMode = Asc("E") Then
        significantDigits = precision + 1
    Else
        If precision = 0 Then precision = 1
        significantDigits = precision
    End If

    Dim decoded As SqliteFpDecode
    ' SQLite keeps 16 digits normally and extends to 20 for the alternate ! form.
    Dim maxDigits As Long = 16
    If trimZeroes = 2 Then maxDigits = 20
    sqlite3FpDecode(decoded, value, significantDigits, maxDigits)
    Dim outputLength As Long = 0

    If decoded.isSpecial = 2 AndAlso zeroPad <> 0 Then
        If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("n")) = 0 OrElse _
           sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("u")) = 0 OrElse _
           sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("l")) = 0 OrElse _
           sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("l")) = 0 Then Return -SQLITE_TOOBIG
        zOutput[outputLength] = 0
        Return outputLength
    ElseIf decoded.isSpecial = 2 Then
        If decoded.sign = Asc("-") Then
            If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("-")) = 0 Then Return -SQLITE_TOOBIG
        End If
        If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("N")) = 0 OrElse _
           sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("a")) = 0 OrElse _
           sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("N")) = 0 Then Return -SQLITE_TOOBIG
        zOutput[outputLength] = 0
        Return outputLength
    ElseIf decoded.isSpecial = 1 AndAlso zeroPad <> 0 Then
        decoded.isSpecial = 0
        decoded.z[0] = Asc("9")
        decoded.iDP = 1000
        decoded.n = 1
    ElseIf decoded.isSpecial = 1 Then
        If decoded.sign = Asc("-") Then
            If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("-")) = 0 Then Return -SQLITE_TOOBIG
        End If
        If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("I")) = 0 OrElse _
           sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("n")) = 0 OrElse _
           sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("f")) = 0 Then Return -SQLITE_TOOBIG
        zOutput[outputLength] = 0
        Return outputLength
    End If

    Dim isGeneric As Long = CInt(formatMode = Asc("g") OrElse formatMode = Asc("G"))
    Dim isExponent As Long = CInt(formatMode = Asc("e") OrElse formatMode = Asc("E"))
    Dim exponentValue As Long = decoded.iDP - 1
    Dim fractionDigits As Long = precision
    If isGeneric <> 0 Then
        If exponentValue < -4 OrElse exponentValue >= precision Then
            isExponent = -1
            fractionDigits = precision - 1
        Else
            isExponent = 0
            fractionDigits = precision - decoded.iDP
            If fractionDigits < 0 Then fractionDigits = 0
        End If
    End If

    If decoded.sign = Asc("-") Then
        If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("-")) = 0 Then Return -SQLITE_TOOBIG
    End If

    Dim mantissaStart As Long = outputLength
    If isExponent <> 0 Then
        Dim firstDigit As Long = 0
        If decoded.n > 0 Then firstDigit = decoded.z[0]
        If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, firstDigit) = 0 Then Return -SQLITE_TOOBIG
        If fractionDigits > 0 OrElse alternateForm <> 0 OrElse trimZeroes <> 0 Then
            If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc(".")) = 0 Then Return -SQLITE_TOOBIG
        End If
        For digitIndex As Long = 0 To fractionDigits - 1
            Dim digit As Long = Asc("0")
            If digitIndex + 1 < decoded.n Then digit = decoded.z[digitIndex + 1]
            If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, digit) = 0 Then Return -SQLITE_TOOBIG
        Next
    Else
        If decoded.iDP <= 0 Then
            If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("0")) = 0 Then Return -SQLITE_TOOBIG
        Else
            For digitIndex As Long = 0 To decoded.iDP - 1
                Dim digit As Long = Asc("0")
                If digitIndex < decoded.n Then digit = decoded.z[digitIndex]
                If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, digit) = 0 Then Return -SQLITE_TOOBIG
                Dim digitsAfter As Long = decoded.iDP - digitIndex - 1
                If thousands <> 0 AndAlso digitsAfter > 0 AndAlso digitsAfter Mod 3 = 0 Then
                    If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc(",")) = 0 Then Return -SQLITE_TOOBIG
                End If
            Next
        End If
        If fractionDigits > 0 OrElse alternateForm <> 0 OrElse trimZeroes <> 0 Then
            If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc(".")) = 0 Then Return -SQLITE_TOOBIG
        End If
        For digitIndex As Long = 0 To fractionDigits - 1
            Dim sourceIndex As Long = decoded.iDP + digitIndex
            Dim digit As Long = Asc("0")
            If sourceIndex >= 0 AndAlso sourceIndex < decoded.n Then digit = decoded.z[sourceIndex]
            If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, digit) = 0 Then Return -SQLITE_TOOBIG
        Next
    End If

    If trimZeroes = 2 OrElse (trimZeroes = 1 AndAlso alternateForm = 0) Then
        While outputLength > mantissaStart AndAlso zOutput[outputLength - 1] = Asc("0")
            outputLength -= 1
        Wend
        If outputLength > mantissaStart AndAlso zOutput[outputLength - 1] = Asc(".") Then
            If trimZeroes = 2 Then
                If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("0")) = 0 Then Return -SQLITE_TOOBIG
            Else
                outputLength -= 1
            End If
        End If
    End If

    If isExponent <> 0 Then
        Dim exponentMarker As Long = Asc("e")
        If formatMode = Asc("E") OrElse formatMode = Asc("G") Then exponentMarker = Asc("E")
        If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, exponentMarker) = 0 Then Return -SQLITE_TOOBIG
        If exponentValue < 0 Then
            If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("-")) = 0 Then Return -SQLITE_TOOBIG
            exponentValue = 0 - exponentValue
        Else
            If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("+")) = 0 Then Return -SQLITE_TOOBIG
        End If
        If exponentValue >= 100 Then
            If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("0") + exponentValue \ 100) = 0 Then Return -SQLITE_TOOBIG
            exponentValue = exponentValue Mod 100
        End If
        If sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("0") + exponentValue \ 10) = 0 OrElse _
           sqlite3FpFormatAppend(zOutput, outputLength, outputSize, Asc("0") + exponentValue Mod 10) = 0 Then Return -SQLITE_TOOBIG
    End If

    zOutput[outputLength] = 0
    Return outputLength
End Function

Private Function sqlite3FpIsDigit(ByVal value As Long) As Long
    If value >= Asc("0") AndAlso value <= Asc("9") Then Return -1
    Return 0
End Function

Private Function sqlite3FpIsSpace(ByVal value As Long) As Long
    If value = 32 OrElse (value >= 9 AndAlso value <= 13) Then Return -1
    Return 0
End Function

Private Sub sqlite3FpParseIntegerPart( _
    ByVal z As Const UByte Ptr, _
    ByRef offset As LongInt, _
    ByRef significand As ULongInt, _
    ByRef exponent As Long, _
    ByRef parseState As Long _
)
    parseState = 1
    significand = CULngInt(z[offset] - Asc("0"))
    offset += 1
    While sqlite3FpIsDigit(z[offset]) <> 0
        significand = significand * 10 + CULngInt(z[offset] - Asc("0"))
        offset += 1
        If significand >= SQLITE_FP_MANTISSA_LIMIT Then
            parseState = 9
            While sqlite3FpIsDigit(z[offset]) <> 0
                offset += 1
                exponent += 1
            Wend
            Exit While
        End If
    Wend
End Sub

Function sqlite3AtoF CDecl Alias "sqlite3AtoF" ( _
    ByVal zArgument As Const ZString Ptr, _
    ByVal pResult As Double Ptr _
) As SQLITE_C_INT Export

    If pResult = 0 Then Return 0
    *pResult = 0.0
    If zArgument = 0 Then Return 0

    Dim z As Const UByte Ptr = CPtr(Const UByte Ptr, zArgument)
    Dim offset As LongInt = 0
    Dim negative As Long = 0
    Dim significand As ULongInt = 0
    Dim exponent As Long = 0
    Dim parseState As Long = 0

    While sqlite3FpIsSpace(z[offset]) <> 0
        offset += 1
    Wend
    If sqlite3FpIsDigit(z[offset]) <> 0 Then
        sqlite3FpParseIntegerPart(z, offset, significand, exponent, parseState)
    ElseIf z[offset] = Asc("-") Then
        negative = 1
        offset += 1
        If sqlite3FpIsDigit(z[offset]) <> 0 Then
            sqlite3FpParseIntegerPart(z, offset, significand, exponent, parseState)
        End If
    ElseIf z[offset] = Asc("+") Then
        offset += 1
        If sqlite3FpIsDigit(z[offset]) <> 0 Then
            sqlite3FpParseIntegerPart(z, offset, significand, exponent, parseState)
        End If
    End If

    If z[offset] = Asc(".") Then
        offset += 1
        If sqlite3FpIsDigit(z[offset]) <> 0 Then
            parseState = parseState Or 1
            While sqlite3FpIsDigit(z[offset]) <> 0
                If significand < SQLITE_FP_MANTISSA_LIMIT Then
                    significand = significand * 10 + CULngInt(z[offset] - Asc("0"))
                    exponent -= 1
                Else
                    parseState = 11
                End If
                offset += 1
            Wend
        ElseIf parseState = 0 Then
            Return 0
        End If
        parseState = parseState Or 2
    ElseIf parseState = 0 Then
        Return 0
    End If

    If z[offset] = Asc("e") OrElse z[offset] = Asc("E") Then
        Dim exponentStart As LongInt = offset
        offset += 1
        Dim exponentSign As Long = 1
        If z[offset] = Asc("-") Then
            exponentSign = -1
            offset += 1
        ElseIf z[offset] = Asc("+") Then
            offset += 1
        End If
        If sqlite3FpIsDigit(z[offset]) <> 0 Then
            Dim exponentValue As Long = z[offset] - Asc("0")
            offset += 1
            parseState = parseState Or 2
            While sqlite3FpIsDigit(z[offset]) <> 0
                If exponentValue < 10000 Then
                    exponentValue = exponentValue * 10 + z[offset] - Asc("0")
                Else
                    exponentValue = 10000
                End If
                offset += 1
            Wend
            exponent += exponentSign * exponentValue
        Else
            offset = exponentStart
        End If
    End If

    If significand = 0 Then
        *pResult = 0.0
        parseState = parseState Or 4
    Else
        *pResult = sqlite3Fp10Convert2(significand, exponent)
    End If
    If negative <> 0 Then *pResult = -*pResult

    If z[offset] = 0 Then Return parseState
    If sqlite3FpIsSpace(z[offset]) <> 0 Then
        While sqlite3FpIsSpace(z[offset]) <> 0
            offset += 1
        Wend
        If z[offset] = 0 Then Return parseState
    End If
    Return -16 Or parseState
End Function

#ifdef SQLITE_DEBUG
Declare Function fpdecodeValueDouble CDecl Alias "sqlite3_value_double" ( _
    ByVal pValue As Any Ptr _
) As Double
Declare Function fpdecodeValueInt CDecl Alias "sqlite3_value_int" ( _
    ByVal pValue As Any Ptr _
) As SQLITE_C_INT
Declare Function fpdecodeSnprintf CDecl Alias "sqlite3_snprintf" ( _
    ByVal nByte As SQLITE_C_INT, _
    ByVal zBuffer As ZString Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) As ZString Ptr
Declare Sub fpdecodeResultText CDecl Alias "sqlite3_result_text" ( _
    ByVal pContext As Any Ptr, _
    ByVal zText As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal xDestructor As Any Ptr _
)

Sub fpdecodeFunc CDecl Alias "fpdecodeFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As Any Ptr Ptr _
) Export
    If pContext = 0 OrElse pArguments = 0 OrElse argumentCount <> 3 Then
        sqlite3DebugAssert(StrPtr("fpdecode receives exactly three arguments"))
        Exit Sub
    End If

    Dim decoded As SqliteFpDecode = Type<SqliteFpDecode>(0)
    Dim inputValue As Double = fpdecodeValueDouble(pArguments[0])
    Dim significantDigits As SQLITE_C_INT = fpdecodeValueInt(pArguments[1])
    Dim maxDigits As SQLITE_C_INT = fpdecodeValueInt(pArguments[2])
    If maxDigits <= 0 Then maxDigits = 1
    sqlite3FpDecode(decoded, inputValue, significantDigits, maxDigits)

    Dim zBuffer As ZString * 100
    If decoded.isSpecial = 2 Then
        fpdecodeSnprintf(SizeOf(zBuffer), StrPtr(zBuffer), StrPtr("NaN"))
    Else
        fpdecodeSnprintf(SizeOf(zBuffer), StrPtr(zBuffer), _
            StrPtr("%c%.*s/%d"), CInt(decoded.sign), decoded.n, _
            CPtr(Const ZString Ptr, decoded.z), decoded.iDP)
    End If
    fpdecodeResultText(pContext, StrPtr(zBuffer), -1, _
        CPtr(Any Ptr, Cast(Integer, -1)))
End Sub
#endif

/' end of sqlite3_fp.bas '/
