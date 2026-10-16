/'
    Project: SQLite FreeBASIC port

    File: sqlite3_printf.bas

    Purpose:

        Port SQLite's variadic string formatting entry points from src/printf.c.

    Responsibilities:

        - Parse SQLite printf flags, width, precision, and conversion types.
        - Render numeric, text, quoting, JSON, Expr, and SrcItem fields.
        - Read printf arguments passed by SQL printf() through sqlite3_value.
        - Provide the public variadic and va_list formatting APIs.

    This file intentionally does NOT contain:

        - SQL expression evaluation or parser routines.
        - String accumulator allocation and lifecycle management.
'/

#lang "fb"
#include once "sqlite3_straccum.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_fp.bi"
#include once "sqlite3_parser_token.bi"
#include once "sqlite3_walker.bi"

Extern "C"
    Declare Function sqlite3SystemMemcpy CDecl Alias "memcpy" ( _
        ByVal pTarget As Any Ptr, _
        ByVal pSource As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
    Declare Function sqlite3DebugPrintfWrite CDecl Alias "printf" ( _
        ByVal zFormat As Const ZString Ptr, _
        ... _
    ) As SQLITE_C_INT
    Declare Function sqlite3DebugPrintfFlush CDecl Alias "fflush" ( _
        ByVal pStream As Any Ptr _
    ) As SQLITE_C_INT
End Extern

Declare Function sqlite3_malloc64 CDecl Alias "sqlite3_malloc64" (ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Function sqlite3_realloc64 CDecl Alias "sqlite3_realloc64" ( _
    ByVal pOld As Any Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" (ByVal z As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3AppendOneUtf8Character CDecl Alias "sqlite3AppendOneUtf8Character" ( _
    ByVal zOut As UByte Ptr, _
    ByVal codepoint As u32 _
) As SQLITE_C_INT
Declare Function sqlite3_initialize CDecl Alias "sqlite3_initialize" () As SQLITE_C_INT
Declare Function sqlite3_value_int64 CDecl Alias "sqlite3_value_int64" ( _
    ByVal pValue As Any Ptr _
) As sqlite3_int64
Declare Function sqlite3_value_double CDecl Alias "sqlite3_value_double" ( _
    ByVal pValue As Any Ptr _
) As Double
Declare Function sqlite3_value_text CDecl Alias "sqlite3_value_text" ( _
    ByVal pValue As Any Ptr _
) As Const UByte Ptr
Declare Sub sqlite3_str_appendf CDecl Alias "sqlite3_str_appendf" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)

/' SQLite caps floating precision at the configured limit or 100 million. '/
#ifdef SQLITE_PRINTF_PRECISION_LIMIT
#if SQLITE_PRINTF_PRECISION_LIMIT < 100000000
Private Const SQLITE_FP_PRECISION_LIMIT As Long = SQLITE_PRINTF_PRECISION_LIMIT
#else
Private Const SQLITE_FP_PRECISION_LIMIT As Long = 100000000
#endif
#else
Private Const SQLITE_FP_PRECISION_LIMIT As Long = 100000000
#endif
Private Const SQLITE_PRINTF_STACK_BUFFER_SIZE As Long = 256
Private Const SQLITE_RCSTR_REFCOUNT_MAX As sqlite3_uint64 = &HFFFFFFFFFFFFFFFF

Private Function getIntArg CDecl Alias "getIntArg" ( _
    ByVal pArguments As SqlitePrintfArguments Ptr _
) As sqlite3_int64
    If pArguments = 0 OrElse pArguments->nUsed < 0 OrElse _
       pArguments->nUsed >= pArguments->nArg OrElse _
       pArguments->apArg = 0 Then Return 0
    Dim pValue As Any Ptr = CPtr(Any Ptr, pArguments->apArg[pArguments->nUsed])
    pArguments->nUsed += 1
    Return sqlite3_value_int64(pValue)
End Function

Private Function sqlite3PrintfInt32(ByVal value As sqlite3_int64) As Long
    ' C printf width and precision arguments are cast to signed 32-bit int.
    Dim lowBits As ULong = CULng(CULngInt(value) And &HFFFFFFFFULL)
    If lowBits <= &H7FFFFFFF Then Return CLng(lowBits)
    Return CLng(CLngInt(lowBits) - &H100000000LL)
End Function

Private Function getDoubleArg CDecl Alias "getDoubleArg" ( _
    ByVal pArguments As SqlitePrintfArguments Ptr _
) As Double
    If pArguments = 0 OrElse pArguments->nUsed < 0 OrElse _
       pArguments->nUsed >= pArguments->nArg OrElse _
       pArguments->apArg = 0 Then Return 0.0
    Dim pValue As Any Ptr = CPtr(Any Ptr, pArguments->apArg[pArguments->nUsed])
    pArguments->nUsed += 1
    Return sqlite3_value_double(pValue)
End Function

Private Function getTextArg CDecl Alias "getTextArg" ( _
    ByVal pArguments As SqlitePrintfArguments Ptr _
) As Const UByte Ptr
    If pArguments = 0 OrElse pArguments->nUsed < 0 OrElse _
       pArguments->nUsed >= pArguments->nArg OrElse _
       pArguments->apArg = 0 Then Return 0
    Dim pValue As Any Ptr = CPtr(Any Ptr, pArguments->apArg[pArguments->nUsed])
    pArguments->nUsed += 1
    Return sqlite3_value_text(pValue)
End Function

Private Function printfTempBuf CDecl Alias "printfTempBuf" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal nByte As sqlite3_int64 _
) As UByte Ptr
    If pAccum = 0 Then Return 0
    If pAccum->accError <> 0 Then Return 0
    If nByte < 0 OrElse nByte > SQLITE_MAX_ALLOCATION_SIZE Then
        sqlite3StrAccumSetError(pAccum, SQLITE_TOOBIG)
        Return 0
    End If
    If CULngInt(nByte) > pAccum->nAlloc AndAlso _
       CULngInt(nByte) > pAccum->mxAlloc Then
        sqlite3StrAccumSetError(pAccum, SQLITE_TOOBIG)
        Return 0
    End If
    Dim pBuffer As Any Ptr = sqlite3_malloc64(CULngInt(nByte))
    If pBuffer = 0 Then sqlite3StrAccumSetError(pAccum, SQLITE_NOMEM)
    Return CPtr(UByte Ptr, pBuffer)
End Function

Sub sqlite3RecordErrorOffsetOfExpr CDecl Alias "sqlite3RecordErrorOffsetOfExpr" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pExpression As Const SqliteExpr Ptr _
) Export
    If db = 0 Then Return
    Dim pExpr As Const SqliteExpr Ptr = pExpression
    While pExpr <> 0
        If (pExpr->flags And (EP_Reduced Or EP_TokenOnly)) <> 0 Then Return
        If (pExpr->flags And (EP_OuterON Or EP_InnerON)) <> 0 OrElse _
           pExpr->w.iOfst <= 0 Then
            pExpr = CPtr(Const SqliteExpr Ptr, pExpr->pLeft)
        Else
            Exit While
        End If
    Wend
    If pExpr = 0 OrElse (pExpr->flags And EP_FromDDL) <> 0 Then Return
    db->errByteOffset = pExpr->w.iOfst
End Sub

Private Sub sqlite3StrAppendchar64 CDecl Alias "sqlite3StrAppendchar64" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal nCharacter As sqlite3_int64, _
    ByVal character As Byte _
)
    If pAccum = 0 OrElse nCharacter <= 0 OrElse pAccum->accError <> 0 Then Return
    Dim nAppend As sqlite3_int64 = nCharacter
    If CULngInt(pAccum->nChar) + CULngInt(nAppend) >= pAccum->nAlloc Then
        nAppend = sqlite3StrAccumEnlarge(pAccum, nAppend)
    End If
    If nAppend <= 0 Then Return
    If pAccum->zText = 0 Then
        sqlite3StrAccumSetError(pAccum, SQLITE_MISUSE)
        Return
    End If
    For iByte As sqlite3_int64 = 0 To nAppend - 1
        pAccum->zText[pAccum->nChar + iByte] = CByte(character)
    Next
    pAccum->nChar = CUInt(CULngInt(pAccum->nChar) + CULngInt(nAppend))
End Sub

Private Sub sqlite3StrAppend64 CDecl Alias "sqlite3StrAppend64" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zText As Const UByte Ptr, _
    ByVal nByte As sqlite3_int64 _
)
    If pAccum = 0 OrElse nByte <= 0 OrElse pAccum->accError <> 0 Then Return
    If zText = 0 Then
        sqlite3StrAccumSetError(pAccum, SQLITE_MISUSE)
        Return
    End If
    Dim nCopy As sqlite3_int64 = nByte
    If CULngInt(pAccum->nChar) + CULngInt(nCopy) >= pAccum->nAlloc Then
        nCopy = sqlite3StrAccumEnlarge(pAccum, nCopy)
    End If
    If nCopy <= 0 Then Return
    If pAccum->zText = 0 Then
        sqlite3StrAccumSetError(pAccum, SQLITE_MISUSE)
        Return
    End If
    sqlite3SystemMemcpy(pAccum->zText + pAccum->nChar, zText, CULngInt(nCopy))
    pAccum->nChar = CUInt(CULngInt(pAccum->nChar) + CULngInt(nCopy))
End Sub

Private Function sqlite3PrintfReserveField( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByRef zField As UByte Ptr, _
    ByRef fieldCapacity As Long, _
    ByRef pOwned As Any Ptr, _
    ByVal requestedCapacity As ULongInt _
) As Long

    If requestedCapacity <= fieldCapacity Then Return -1
    If requestedCapacity > SQLITE_MAX_LENGTH OrElse requestedCapacity > &H7FFFFFFF Then Return 0
    If pAccum <> 0 AndAlso pAccum->mxAlloc = 0 Then Return 0

    zField = printfTempBuf(pAccum, CLngInt(requestedCapacity))
    If zField = 0 Then Return 0
    pOwned = zField
    fieldCapacity = CLng(requestedCapacity)
    Return -1
End Function

Private Sub sqlite3PrintfSetReserveError( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal requestedCapacity As ULongInt _
)
    If requestedCapacity > SQLITE_MAX_LENGTH OrElse _
       (pAccum <> 0 AndAlso pAccum->mxAlloc = 0) Then
        sqlite3StrAccumSetError(pAccum, SQLITE_TOOBIG)
    Else
        sqlite3StrAccumSetError(pAccum, SQLITE_NOMEM)
    End If
End Sub

Private Function sqlite3PrintfUtf8PrefixLength( _
    ByVal zText As Const UByte Ptr, _
    ByVal nCharacter As Long _
) As Long

    If zText = 0 OrElse nCharacter <= 0 Then Return 0
    Dim nByte As Long = 0
    Dim nSeen As Long = 0
    While zText[nByte] <> 0 AndAlso nSeen < nCharacter
        Dim firstByte As UByte = zText[nByte]
        nByte += 1
        If firstByte >= &HC0 Then
            While zText[nByte] <> 0 AndAlso (zText[nByte] And &HC0) = &H80
                nByte += 1
            Wend
        End If
        nSeen += 1
    Wend
    Return nByte
End Function

Private Function sqlite3PrintfUtf8ExtraBytes( _
    ByVal zText As Const UByte Ptr, _
    ByVal nByte As Long _
) As Long

    If zText = 0 OrElse nByte <= 0 Then Return 0
    Dim extraBytes As Long = 0
    For i As Long = 0 To nByte - 1
        If (zText[i] And &HC0) = &H80 Then extraBytes += 1
    Next
    Return extraBytes
End Function

Private Sub sqlite3PrintfOutputField( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zField As Const UByte Ptr, _
    ByVal nField As Long, _
    ByVal fieldWidth As Long, _
    ByVal leftJustify As Long, _
    ByVal zeroPad As Long, _
    ByVal numericField As Long _
)

    If pAccum = 0 OrElse nField < 0 Then Return
    Dim padding As Long = fieldWidth - nField
    If padding <= 0 Then
        sqlite3StrAppend64(pAccum, zField, nField)
        Return
    End If

    If leftJustify = 0 AndAlso zeroPad <> 0 AndAlso numericField <> 0 Then
        Dim prefixBytes As Long = 0
        If nField > 0 AndAlso (zField[0] = Asc("-") OrElse zField[0] = Asc("+") OrElse zField[0] = Asc(" ")) Then
            prefixBytes = 1
        End If
        If nField >= prefixBytes + 2 AndAlso zField[prefixBytes] = Asc("0") AndAlso _
           (zField[prefixBytes + 1] = Asc("x") OrElse zField[prefixBytes + 1] = Asc("X")) Then
            prefixBytes += 2
        End If
        If prefixBytes > 0 Then sqlite3StrAppend64(pAccum, zField, prefixBytes)
        sqlite3StrAppendchar64(pAccum, padding, Asc("0"))
        sqlite3StrAppend64(pAccum, zField + prefixBytes, nField - prefixBytes)
    ElseIf leftJustify = 0 Then
        sqlite3StrAppendchar64(pAccum, padding, Asc(" "))
        sqlite3StrAppend64(pAccum, zField, nField)
    Else
        sqlite3StrAppend64(pAccum, zField, nField)
        sqlite3StrAppendchar64(pAccum, padding, Asc(" "))
    End If
End Sub

Private Function sqlite3PrintfDigits(ByVal digit As Long, ByVal upperCase As Long) As UByte
    If digit < 10 Then Return CUByte(Asc("0") + digit)
    If upperCase <> 0 Then Return CUByte(Asc("A") + digit - 10)
    Return CUByte(Asc("a") + digit - 10)
End Function

Private Function sqlite3PrintfMakeInteger( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal value As ULongInt, _
    ByVal negative As Long, _
    ByVal radix As Long, _
    ByVal upperCase As Long, _
    ByVal prefixSign As Long, _
    ByVal alternateForm As Long, _
    ByVal thousands As Long, _
    ByVal fieldWidth As Long, _
    ByVal precisionInput As Long, _
    ByVal zeroPad As Long, _
    ByVal leftJustify As Long, _
    ByVal ordinal As Long, _
    ByRef zField As UByte Ptr, _
    ByRef nField As Long, _
    ByRef pOwned As Any Ptr, _
    ByRef fieldCapacity As Long _
) As Long

    If radix < 2 OrElse radix > 16 Then Return 0
    Dim reversedDigits(0 To 63) As UByte
    Dim digitCount As Long = 0
    Dim magnitude As ULongInt = value
    Do
        reversedDigits(digitCount) = sqlite3PrintfDigits(CLng(magnitude Mod CULngInt(radix)), upperCase)
        digitCount += 1
        magnitude = magnitude \ CULngInt(radix)
    Loop While magnitude <> 0 AndAlso digitCount < 64

    Dim suffixBytes(0 To 1) As UByte
    Dim suffixLength As Long = 0
    If ordinal <> 0 Then
        Dim lastTwo As Long = CLng(value Mod 100)
        Dim lastOne As Long = CLng(value Mod 10)
        If lastTwo >= 11 AndAlso lastTwo <= 13 Then
            suffixBytes(0) = Asc("t")
            suffixBytes(1) = Asc("h")
        Else
            Select Case lastOne
            Case 1
                suffixBytes(0) = Asc("s")
                suffixBytes(1) = Asc("t")
            Case 2
                suffixBytes(0) = Asc("n")
                suffixBytes(1) = Asc("d")
            Case 3
                suffixBytes(0) = Asc("r")
                suffixBytes(1) = Asc("d")
            Case Else
                suffixBytes(0) = Asc("t")
                suffixBytes(1) = Asc("h")
            End Select
        End If
        suffixLength = 2
    End If

    Dim precision As Long = precisionInput
    If precision < 0 Then precision = 0
    Dim signLength As Long = IIf(negative <> 0 OrElse prefixSign <> 0, 1, 0)
    If zeroPad <> 0 AndAlso leftJustify = 0 AndAlso fieldWidth > signLength AndAlso _
       precision < fieldWidth - signLength Then
        precision = fieldWidth - signLength
    End If
    If precision < digitCount Then precision = digitCount

    Dim prefixBytes(0 To 2) As UByte
    Dim prefixLength As Long = 0
    If negative <> 0 Then
        prefixBytes(prefixLength) = Asc("-")
        prefixLength += 1
    ElseIf prefixSign <> 0 Then
        prefixBytes(prefixLength) = CUByte(prefixSign)
        prefixLength += 1
    End If
    If alternateForm <> 0 AndAlso value <> 0 Then
        If radix = 16 Then
            prefixBytes(prefixLength) = Asc("0")
            prefixLength += 1
            If upperCase <> 0 Then
                prefixBytes(prefixLength) = Asc("X")
            Else
                prefixBytes(prefixLength) = Asc("x")
            End If
            prefixLength += 1
        ElseIf radix = 8 AndAlso (precision = 0 OrElse digitCount = 0 OrElse reversedDigits(digitCount - 1) <> Asc("0")) Then
            prefixBytes(prefixLength) = Asc("0")
            prefixLength += 1
        End If
    End If

    Dim separatorCount As Long = 0
    If thousands <> 0 AndAlso radix = 10 AndAlso precision > 1 Then
        separatorCount = (precision - 1) \ 3
    End If
    Dim requestedCapacity As ULongInt = CULngInt(prefixLength) + CULngInt(precision) + _
                                         CULngInt(separatorCount) + CULngInt(suffixLength) + 1
    If pAccum->mxAlloc = 0 AndAlso requestedCapacity > pAccum->nAlloc Then
        sqlite3StrAccumSetError(pAccum, SQLITE_TOOBIG)
        Return 0
    End If
    If sqlite3PrintfReserveField(pAccum, zField, fieldCapacity, pOwned, requestedCapacity) = 0 Then
        sqlite3PrintfSetReserveError(pAccum, requestedCapacity)
        Return 0
    End If

    nField = 0
    For i As Long = 0 To prefixLength - 1
        zField[nField] = prefixBytes(i)
        nField += 1
    Next
    Dim firstGroup As Long = precision Mod 3
    If firstGroup = 0 Then firstGroup = 3
    For digitPosition As Long = 0 To precision - 1
        Dim digit As UByte = Asc("0")
        Dim fromRight As Long = precision - digitPosition - 1
        If fromRight < digitCount Then digit = reversedDigits(fromRight)
        zField[nField] = digit
        nField += 1
        If thousands <> 0 AndAlso radix = 10 AndAlso digitPosition < precision - 1 Then
            If digitPosition + 1 = firstGroup OrElse _
               (digitPosition + 1 > firstGroup AndAlso (digitPosition + 1 - firstGroup) Mod 3 = 0) Then
                zField[nField] = Asc(",")
                nField += 1
            End If
        End If
    Next
    For i As Long = 0 To suffixLength - 1
        zField[nField] = suffixBytes(i)
        nField += 1
    Next
    zField[nField] = 0
    Return -1
End Function

Private Function sqlite3PrintfBuildQuoted( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zInput As Const UByte Ptr, _
    ByVal inputLength As Long, _
    ByVal formatType As UByte, _
    ByVal alternateForm As Long, _
    ByRef zField As UByte Ptr, _
    ByRef nField As Long, _
    ByRef pOwned As Any Ptr, _
    ByRef fieldCapacity As Long _
) As Long

    Dim quoteByte As UByte = Asc("'")
    Dim needsQuotes As Long = 0
    If formatType = Asc("w") Then quoteByte = Asc("""")
    If formatType = Asc("Q") AndAlso zInput <> 0 Then needsQuotes = -1
    If zInput = 0 Then
        inputLength = IIf(formatType = Asc("Q"), 4, 6)
        Dim requestedCapacity As ULongInt = CULngInt(inputLength) + 1
        If sqlite3PrintfReserveField(pAccum, zField, fieldCapacity, pOwned, requestedCapacity) = 0 Then
            sqlite3PrintfSetReserveError(pAccum, requestedCapacity)
            Return 0
        End If
        If formatType = Asc("Q") Then
            zField[0] = Asc("N")
            zField[1] = Asc("U")
            zField[2] = Asc("L")
            zField[3] = Asc("L")
        Else
            zField[0] = Asc("(")
            zField[1] = Asc("N")
            zField[2] = Asc("U")
            zField[3] = Asc("L")
            zField[4] = Asc("L")
            zField[5] = Asc(")")
        End If
        zField[inputLength] = 0
        nField = inputLength
        Return -1
    End If

    Dim useUnistr As Long = 0
    Dim controlCount As Long = 0
    Dim backslashCount As Long = 0
    For i As Long = 0 To inputLength - 1
        If zInput[i] <= &H1F Then controlCount += 1
        If zInput[i] = Asc("\") Then backslashCount += 1
    Next
    If alternateForm <> 0 AndAlso formatType <> Asc("w") Then
        If formatType = Asc("q") OrElse controlCount > 0 Then useUnistr = -1
        If formatType = Asc("Q") AndAlso controlCount > 0 Then needsQuotes = -1
    End If

    Dim quoteEscapes As Long = 0
    For i As Long = 0 To inputLength - 1
        If zInput[i] = quoteByte Then quoteEscapes += 1
    Next
    Dim extraBytes As ULongInt = CULngInt(quoteEscapes)
    If useUnistr <> 0 Then extraBytes += CULngInt(backslashCount) + CULngInt(controlCount) * 5
    Dim outerBytes As Long = IIf(needsQuotes <> 0, 2, 0)
    If useUnistr <> 0 AndAlso formatType = Asc("Q") AndAlso controlCount > 0 Then outerBytes = 10
    Dim requestedCapacity As ULongInt = CULngInt(inputLength) + extraBytes + CULngInt(outerBytes) + 1
    If pAccum->mxAlloc = 0 AndAlso requestedCapacity > pAccum->nAlloc Then
        sqlite3StrAccumSetError(pAccum, SQLITE_TOOBIG)
        Return 0
    End If
    If sqlite3PrintfReserveField(pAccum, zField, fieldCapacity, pOwned, requestedCapacity) = 0 Then
        sqlite3PrintfSetReserveError(pAccum, requestedCapacity)
        Return 0
    End If

    nField = 0
    If useUnistr <> 0 AndAlso formatType = Asc("Q") AndAlso controlCount > 0 Then
        For i As Long = 1 To 8
            zField[nField] = Asc("unistr('", i)
            nField += 1
        Next
    ElseIf needsQuotes <> 0 Then
        zField[nField] = quoteByte
        nField += 1
    End If

    For i As Long = 0 To inputLength - 1
        Dim value As UByte = zInput[i]
        If useUnistr <> 0 AndAlso value = Asc("\") Then
            zField[nField] = Asc("\")
            nField += 1
        ElseIf useUnistr <> 0 AndAlso value <= &H1F Then
            zField[nField] = Asc("\")
            zField[nField + 1] = Asc("u")
            zField[nField + 2] = Asc("0")
            zField[nField + 3] = Asc("0")
            zField[nField + 4] = IIf(value >= &H10, Asc("1"), Asc("0"))
            zField[nField + 5] = sqlite3PrintfDigits(value And &HF, 1)
            nField += 6
            Continue For
        End If
        zField[nField] = value
        nField += 1
        If value = quoteByte Then
            zField[nField] = quoteByte
            nField += 1
        End If
    Next

    If useUnistr <> 0 AndAlso formatType = Asc("Q") AndAlso controlCount > 0 Then
        zField[nField] = Asc("'")
        zField[nField + 1] = Asc(")")
        nField += 2
    ElseIf needsQuotes <> 0 Then
        zField[nField] = quoteByte
        nField += 1
    End If
    zField[nField] = 0
    Return -1
End Function

Private Function sqlite3PrintfBuildJson( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zInput As Const UByte Ptr, _
    ByVal inputLength As Long, _
    ByVal quoted As Long, _
    ByRef zField As UByte Ptr, _
    ByRef nField As Long, _
    ByRef pOwned As Any Ptr, _
    ByRef fieldCapacity As Long _
) As Long

    If zInput = 0 Then
        Dim nullLength As Long = IIf(quoted <> 0, 4, 0)
        Dim requestedCapacity As ULongInt = CULngInt(nullLength) + 1
        If sqlite3PrintfReserveField(pAccum, zField, fieldCapacity, pOwned, requestedCapacity) = 0 Then
            sqlite3PrintfSetReserveError(pAccum, requestedCapacity)
            Return 0
        End If
        If quoted <> 0 Then
            zField[0] = Asc("n")
            zField[1] = Asc("u")
            zField[2] = Asc("l")
            zField[3] = Asc("l")
        End If
        nField = nullLength
        zField[nField] = 0
        Return -1
    End If

    Dim escapeCount As ULongInt = 0
    For i As Long = 0 To inputLength - 1
        If zInput[i] = Asc("""") OrElse zInput[i] = Asc("\") Then
            escapeCount += 1
        ElseIf zInput[i] < &H20 Then
            escapeCount += 5
        End If
    Next
    Dim outerBytes As Long = IIf(quoted <> 0, 2, 0)
    Dim requestedCapacity As ULongInt = CULngInt(inputLength) + escapeCount + CULngInt(outerBytes) + 1
    If pAccum->mxAlloc = 0 AndAlso requestedCapacity > pAccum->nAlloc Then
        sqlite3StrAccumSetError(pAccum, SQLITE_TOOBIG)
        Return 0
    End If
    If sqlite3PrintfReserveField(pAccum, zField, fieldCapacity, pOwned, requestedCapacity) = 0 Then
        sqlite3PrintfSetReserveError(pAccum, requestedCapacity)
        Return 0
    End If

    nField = 0
    If quoted <> 0 Then
        zField[nField] = Asc("""")
        nField += 1
    End If
    For i As Long = 0 To inputLength - 1
        Dim value As UByte = zInput[i]
        If value = Asc("""") OrElse value = Asc("\") Then
            zField[nField] = Asc("\")
            zField[nField + 1] = value
            nField += 2
        ElseIf value < &H20 Then
            zField[nField] = Asc("\")
            zField[nField + 1] = Asc("u")
            zField[nField + 2] = Asc("0")
            zField[nField + 3] = Asc("0")
            zField[nField + 4] = sqlite3PrintfDigits(value Shr 4, 0)
            zField[nField + 5] = sqlite3PrintfDigits(value And &HF, 0)
            nField += 6
        Else
            zField[nField] = value
            nField += 1
        End If
    Next
    If quoted <> 0 Then
        zField[nField] = Asc("""")
        nField += 1
    End If
    zField[nField] = 0
    Return -1
End Function

Sub sqlite3_str_vappendf CDecl Alias "sqlite3_str_vappendf" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ByRef sourceArgs As Cva_List _
) Export

    If pAccum = 0 OrElse zFormat = 0 Then Return
    Dim args As Cva_List
    Cva_Copy(args, sourceArgs)
    Dim pArgList As SqlitePrintfArguments Ptr = 0
    If (pAccum->printfFlags And SQLITE_PRINTF_SQLFUNC) <> 0 Then _
        pArgList = Cva_Arg(args, SqlitePrintfArguments Ptr)

    Dim zFmt As Const UByte Ptr = CPtr(Const UByte Ptr, zFormat)
    Dim position As ULongInt = 0
    Dim done As Long = 0

    Do While done = 0 AndAlso zFmt[position] <> 0 AndAlso pAccum->accError = 0
        If zFmt[position] <> Asc("%") Then
            Dim literalStart As ULongInt = position
            While zFmt[position] <> 0 AndAlso zFmt[position] <> Asc("%")
                position += 1
            Wend
            Dim literalLength As ULongInt = position - literalStart
            If literalLength > &H7FFFFFFF Then
                sqlite3StrAccumSetError(pAccum, SQLITE_TOOBIG)
                Exit Do
            End If
            sqlite3StrAppend64(pAccum, zFmt + literalStart, CLngInt(literalLength))
            Continue Do
        End If

        position += 1
        If zFmt[position] = 0 Then
            sqlite3StrAppend64(pAccum, CPtr(Const UByte Ptr, StrPtr("%")), 1)
            Exit Do
        End If

        Dim leftJustify As Long = 0
        Dim prefixFlag As Long = 0
        Dim alternateForm As Long = 0
        Dim alternateForm2 As Long = 0
        Dim zeroPad As Long = 0
        Dim thousands As Long = 0
        Dim widthValue As Long = 0
        Dim precision As Long = -1
        Dim lengthFlag As Long = 0
        Dim parseFlags As Long = -1

        While parseFlags <> 0
            Select Case zFmt[position]
            Case Asc("-")
                leftJustify = -1
            Case Asc("+")
                prefixFlag = Asc("+")
            Case Asc(" ")
                prefixFlag = Asc(" ")
            Case Asc("#")
                alternateForm = -1
            Case Asc("!")
                alternateForm2 = -1
            Case Asc("0")
                zeroPad = -1
            Case Asc(",")
                thousands = -1
            Case Else
                parseFlags = 0
                Continue While
            End Select
            position += 1
        Wend

        If zFmt[position] = Asc("*") Then
            If pArgList <> 0 Then
                widthValue = sqlite3PrintfInt32(getIntArg(pArgList))
            Else
                widthValue = Cva_Arg(args, SQLITE_C_INT)
            End If
            position += 1
            If widthValue < 0 Then
                leftJustify = -1
                If widthValue < -&H7FFFFFFF Then
                    widthValue = 0
                Else
                    widthValue = 0 - widthValue
                End If
            End If
#ifdef SQLITE_PRINTF_PRECISION_LIMIT
            If widthValue > SQLITE_PRINTF_PRECISION_LIMIT Then _
                widthValue = SQLITE_PRINTF_PRECISION_LIMIT
#endif
        Else
            ' Match C's unsigned 32-bit parse followed by masking the sign bit.
            Dim parsedWidth As ULongInt = 0
            While zFmt[position] >= Asc("0") AndAlso zFmt[position] <= Asc("9")
                Dim widthDigit As Long = zFmt[position] - Asc("0")
                parsedWidth = (parsedWidth * 10 + CULngInt(widthDigit)) And &HFFFFFFFFULL
                position += 1
            Wend
            widthValue = CLng(parsedWidth And &H7FFFFFFF)
#ifdef SQLITE_PRINTF_PRECISION_LIMIT
            If widthValue > SQLITE_PRINTF_PRECISION_LIMIT Then _
                widthValue = SQLITE_PRINTF_PRECISION_LIMIT
#endif
        End If

        If zFmt[position] = Asc(".") Then
            position += 1
            If zFmt[position] = Asc("*") Then
                If pArgList <> 0 Then
                    precision = sqlite3PrintfInt32(getIntArg(pArgList))
                Else
                    precision = Cva_Arg(args, SQLITE_C_INT)
                End If
                position += 1
                If precision < 0 Then
                    If precision >= -&H7FFFFFFF Then
                        precision = 0 - precision
                    Else
                        precision = -1
                    End If
                End If
            Else
                precision = 0
                ' Match C's unsigned 32-bit parse followed by masking the sign bit.
                Dim parsedPrecision As ULongInt = 0
                While zFmt[position] >= Asc("0") AndAlso zFmt[position] <= Asc("9")
                    Dim precisionDigit As Long = zFmt[position] - Asc("0")
                    parsedPrecision = (parsedPrecision * 10 + CULngInt(precisionDigit)) And &HFFFFFFFFULL
                    position += 1
                Wend
                precision = CLng(parsedPrecision And &H7FFFFFFF)
            End If
#ifdef SQLITE_PRINTF_PRECISION_LIMIT
            If precision > SQLITE_PRINTF_PRECISION_LIMIT Then _
                precision = SQLITE_PRINTF_PRECISION_LIMIT
#endif
        End If

        If zFmt[position] = Asc("l") Then
            lengthFlag = 1
            position += 1
            If zFmt[position] = Asc("l") Then
                lengthFlag = 2
                position += 1
            End If
        End If
        Dim formatType As UByte = zFmt[position]
        If formatType = 0 Then
            Exit Do
        End If
        position += 1

        Dim stackBuffer(0 To SQLITE_PRINTF_STACK_BUFFER_SIZE - 1) As UByte
        Dim zField As UByte Ptr = @stackBuffer(0)
        Dim fieldCapacity As Long = SQLITE_PRINTF_STACK_BUFFER_SIZE
        If pAccum->pPrintfScratch <> 0 AndAlso pAccum->nPrintfScratch > 0 AndAlso _
           pAccum->nPrintfScratch <= &H7FFFFFFF Then
            zField = pAccum->pPrintfScratch
            fieldCapacity = CLng(pAccum->nPrintfScratch)
        End If
        Dim pOwned As Any Ptr = 0
        Dim nField As Long = 0
        Dim fieldCreated As Long = 1
        Dim numericField As Long = 0
        Dim widthBytes As Long = widthValue
        Dim pOwnedWithDatabase As Long = 0

        Select Case formatType
        Case Asc("d"), Asc("i"), Asc("u"), Asc("x"), Asc("X"), Asc("o"), Asc("p"), Asc("r")
            numericField = -1
            Dim radix As Long = 10
            Dim upperCase As Long = CInt( _
                formatType = Asc("X") OrElse formatType = Asc("p"))
            If formatType = Asc("x") OrElse formatType = Asc("X") OrElse formatType = Asc("p") Then radix = 16
            If formatType = Asc("o") Then radix = 8
            Dim negative As Long = 0
            Dim signForNumber As Long = 0
            Dim numberValue As ULongInt = 0
            If formatType = Asc("d") OrElse formatType = Asc("i") OrElse formatType = Asc("r") Then
                Dim signedValue As LongInt
                If pArgList <> 0 Then
                    signedValue = getIntArg(pArgList)
                ElseIf lengthFlag = 2 Then
                    signedValue = Cva_Arg(args, sqlite3_int64)
                ElseIf lengthFlag = 1 Then
                    signedValue = Cva_Arg(args, SQLITE_C_LONG)
                Else
                    signedValue = Cva_Arg(args, SQLITE_C_INT)
                End If
                If signedValue < 0 Then
                    negative = -1
                    numberValue = CULngInt(Not signedValue) + 1
                Else
                    numberValue = CULngInt(signedValue)
                    signForNumber = prefixFlag
                End If
            ElseIf formatType = Asc("p") Then
                If pArgList <> 0 Then
                    numberValue = CULngInt(getIntArg(pArgList))
                Else
                    Dim pValue As Any Ptr = Cva_Arg(args, Any Ptr)
                    Dim pValueBits As ULongInt = 0
                    sqlite3SystemMemcpy(@pValueBits, @pValue, SizeOf(pValue))
                    numberValue = pValueBits
                End If
            ElseIf pArgList <> 0 Then
                numberValue = CULngInt(getIntArg(pArgList))
            ElseIf lengthFlag = 2 Then
                numberValue = Cva_Arg(args, sqlite3_uint64)
            ElseIf lengthFlag = 1 Then
                numberValue = Cva_Arg(args, SQLITE_C_ULONG)
            Else
                numberValue = Cva_Arg(args, SQLITE_C_UINT)
            End If
            If formatType = Asc("p") Then thousands = 0
            Dim ordinal As Long = CInt(formatType = Asc("r"))
            If sqlite3PrintfMakeInteger(pAccum, numberValue, negative, radix, upperCase, signForNumber, _
                                        alternateForm, thousands, widthValue, precision, zeroPad, _
                                        leftJustify, ordinal, zField, nField, pOwned, fieldCapacity) = 0 Then
                fieldCreated = 0
            End If
        Case Asc("f"), Asc("F"), Asc("e"), Asc("E"), Asc("g"), Asc("G")
            numericField = -1
            Dim realValue As Double
            If pArgList <> 0 Then
                realValue = getDoubleArg(pArgList)
            Else
                realValue = Cva_Arg(args, Double)
            End If
            Dim floatPrecision As Long = precision
            If floatPrecision < 0 Then floatPrecision = 6
            If floatPrecision > SQLITE_FP_PRECISION_LIMIT Then floatPrecision = SQLITE_FP_PRECISION_LIMIT
            ' Reserve headroom for the decimal exponent, grouped digits, and Inf padding.
            Dim capacityReserve As Long = 400
            If thousands <> 0 Then capacityReserve += 120 ' Up to 103 separators for finite doubles.
            If zeroPad <> 0 Then capacityReserve += 1100 ' The padded Inf sentinel uses 1,000 digits.
            Dim needed As ULongInt = CULngInt(floatPrecision) + _
                CULngInt(widthValue) + CULngInt(capacityReserve)
            If sqlite3PrintfReserveField(pAccum, zField, fieldCapacity, pOwned, needed) = 0 Then
                sqlite3PrintfSetReserveError(pAccum, needed)
                fieldCreated = 0
            Else
                Dim trimFlag As Long = 0
                If alternateForm2 <> 0 Then
                    trimFlag = 2
                ElseIf (formatType = Asc("g") OrElse formatType = Asc("G")) AndAlso alternateForm = 0 Then
                    trimFlag = 1
                End If
                Dim rendered As Long = sqlite3FpFormatPrintf(realValue, formatType, floatPrecision, _
                    alternateForm, zeroPad, thousands, trimFlag, zField, fieldCapacity)
                If rendered < 0 Then
                    sqlite3StrAccumSetError(pAccum, CUByte(-rendered))
                    fieldCreated = 0
                Else
                    nField = rendered
                    If prefixFlag <> 0 AndAlso nField > 0 AndAlso zField[0] <> Asc("-") Then
                        If sqlite3PrintfReserveField(pAccum, zField, fieldCapacity, pOwned, CULngInt(nField) + 2) = 0 Then
                            sqlite3PrintfSetReserveError(pAccum, CULngInt(nField) + 2)
                            fieldCreated = 0
                        Else
                            For i As Long = nField To 1 Step -1
                                zField[i] = zField[i - 1]
                            Next
                            zField[0] = CUByte(prefixFlag)
                            nField += 1
                        End If
                    End If
                End If
            End If
        Case Asc("s"), Asc("z")
            Dim pText As Const UByte Ptr
            If pArgList <> 0 Then
                pText = getTextArg(pArgList)
            Else
                pText = CPtr(Const UByte Ptr, Cva_Arg(args, ZString Ptr))
            End If
            Dim isDynamicText As Long = CInt( _
                pArgList = 0 AndAlso formatType = Asc("z") AndAlso pText <> 0)
            If pText = 0 Then
                pText = CPtr(Const UByte Ptr, StrPtr(""))
            End If
            Dim nText As Long = sqlite3Strlen30(CPtr(Const ZString Ptr, pText))
            If precision >= 0 Then
                If alternateForm2 <> 0 Then
                    nText = sqlite3PrintfUtf8PrefixLength(pText, precision)
                ElseIf nText > precision Then
                    nText = precision
                End If
            End If
            If alternateForm2 <> 0 Then widthBytes += sqlite3PrintfUtf8ExtraBytes(pText, nText)
            zField = CPtr(UByte Ptr, pText)
            nField = nText
            If isDynamicText <> 0 Then
                pOwned = CPtr(Any Ptr, pText)
                pOwnedWithDatabase = -1
            End If
        Case Asc("c")
            If pArgList <> 0 Then
                Dim pText As Const UByte Ptr = getTextArg(pArgList)
                If pText = 0 Then
                    zField[0] = 0
                    nField = 1
                Else
                    nField = sqlite3PrintfUtf8PrefixLength(pText, 1)
                    If nField < 1 OrElse nField > 4 Then nField = 1
                    sqlite3SystemMemcpy(zField, pText, nField)
                End If
            Else
                Dim codepoint As u32 = Cva_Arg(args, SQLITE_C_UINT)
                nField = sqlite3AppendOneUtf8Character(zField, codepoint)
                If nField < 1 OrElse nField > 4 Then
                    nField = sqlite3AppendOneUtf8Character(zField, &HFFFD)
                End If
            End If
            If precision > 1 Then
                Dim originalLength As Long = nField
                Dim repeatCount As Long = precision
                Dim needed As ULongInt = CULngInt(originalLength) * CULngInt(repeatCount) + 1
                Dim originalCharacter(0 To 3) As UByte
                For characterIndex As Long = 0 To originalLength - 1
                    originalCharacter(characterIndex) = zField[characterIndex]
                Next
                If sqlite3PrintfReserveField(pAccum, zField, fieldCapacity, pOwned, needed) = 0 Then
                    sqlite3PrintfSetReserveError(pAccum, needed)
                    fieldCreated = 0
                Else
                    For characterIndex As Long = 0 To originalLength - 1
                        zField[characterIndex] = originalCharacter(characterIndex)
                    Next
                    For repeatIndex As Long = 1 To repeatCount - 1
                        sqlite3SystemMemcpy( _
                            zField + originalLength * repeatIndex, _
                            @originalCharacter(0), originalLength)
                    Next
                    nField = originalLength * repeatCount
                End If
            End If
            widthBytes += sqlite3PrintfUtf8ExtraBytes(zField, nField)
        Case Asc("q"), Asc("Q"), Asc("w")
            Dim pText As Const UByte Ptr
            If pArgList <> 0 Then
                pText = getTextArg(pArgList)
            Else
                pText = CPtr(Const UByte Ptr, Cva_Arg(args, ZString Ptr))
            End If
            Dim nText As Long = sqlite3Strlen30(CPtr(Const ZString Ptr, pText))
            If pText = 0 Then nText = 0
            If precision >= 0 Then
                If alternateForm2 <> 0 AndAlso pText <> 0 Then
                    nText = sqlite3PrintfUtf8PrefixLength(pText, precision)
                ElseIf nText > precision Then
                    nText = precision
                End If
            End If
            If sqlite3PrintfBuildQuoted(pAccum, pText, nText, formatType, alternateForm, _
                                        zField, nField, pOwned, fieldCapacity) = 0 Then
                fieldCreated = 0
            End If
            If alternateForm2 <> 0 Then widthBytes += sqlite3PrintfUtf8ExtraBytes(zField, nField)
        Case Asc("j"), Asc("J")
            Dim pText As Const UByte Ptr
            If pArgList <> 0 Then
                pText = getTextArg(pArgList)
            Else
                pText = CPtr(Const UByte Ptr, Cva_Arg(args, ZString Ptr))
            End If
            Dim nText As Long = sqlite3Strlen30(CPtr(Const ZString Ptr, pText))
            If pText = 0 Then nText = 0
            If precision >= 0 Then
                If alternateForm2 <> 0 AndAlso pText <> 0 Then
                    nText = sqlite3PrintfUtf8PrefixLength(pText, precision)
                ElseIf nText > precision Then
                    nText = precision
                End If
            End If
            If sqlite3PrintfBuildJson(pAccum, pText, nText, CInt(formatType = Asc("J")), _
                                      zField, nField, pOwned, fieldCapacity) = 0 Then
                fieldCreated = 0
            End If
            If alternateForm2 <> 0 Then widthBytes += sqlite3PrintfUtf8ExtraBytes(zField, nField)
        Case Asc("T")
            If (pAccum->printfFlags And SQLITE_PRINTF_INTERNAL) = 0 Then
                fieldCreated = 0
                done = -1
            ElseIf alternateForm <> 0 Then
                ' %#T accepts an Expr and writes its original token into
                ' parser diagnostics, including the source byte offset.
                Dim pExpression As SqliteExpr Ptr = _
                    Cva_Arg(args, SqliteExpr Ptr)
                If pExpression <> 0 AndAlso _
                   (pExpression->flags And EP_IntValue) = 0 AndAlso _
                   pExpression->u.zToken <> 0 Then
                    zField = CPtr(UByte Ptr, pExpression->u.zToken)
                    nField = sqlite3Strlen30( _
                        CPtr(Const ZString Ptr, pExpression->u.zToken))
                    sqlite3RecordErrorOffsetOfExpr(pAccum->db, pExpression)
                End If
                widthValue = 0
                widthBytes = 0
            Else
                Dim pToken As sqlite3ParserToken Ptr = Cva_Arg(args, sqlite3ParserToken Ptr)
                If pToken <> 0 AndAlso pToken->z <> 0 AndAlso pToken->n > 0 Then
                    zField = pToken->z
                    nField = CLng(pToken->n)
                End If
                widthValue = 0
                widthBytes = 0
            End If
        Case Asc("S")
            If (pAccum->printfFlags And SQLITE_PRINTF_INTERNAL) = 0 Then
                fieldCreated = 0
                done = -1
            Else
                Dim pSourceItem As SqliteSrcItem Ptr = _
                    Cva_Arg(args, SqliteSrcItem Ptr)
                If pSourceItem <> 0 Then
                    Dim sourceFlags As SQLITE_C_UINT = pSourceItem->fg.flags
                    If pSourceItem->zAlias <> 0 AndAlso alternateForm2 = 0 Then
                        sqlite3_str_appendall(pAccum, pSourceItem->zAlias)
                    ElseIf pSourceItem->zName <> 0 Then
                        Dim pDatabaseName As Const ZString Ptr = _
                            pSourceItem->u4.zDatabase
                        If (sourceFlags And SRCITEM_FIXED_SCHEMA) = 0 AndAlso _
                           (sourceFlags And SRCITEM_IS_SUBQUERY) = 0 AndAlso _
                           pDatabaseName <> 0 Then
                            sqlite3_str_appendall(pAccum, pDatabaseName)
                            sqlite3_str_append(pAccum, StrPtr("."), 1)
                        End If
                        sqlite3_str_appendall(pAccum, pSourceItem->zName)
                    ElseIf pSourceItem->zAlias <> 0 Then
                        sqlite3_str_appendall(pAccum, pSourceItem->zAlias)
                    ElseIf (sourceFlags And SRCITEM_IS_SUBQUERY) <> 0 AndAlso _
                           pSourceItem->u4.pSubq <> 0 AndAlso _
                           pSourceItem->u4.pSubq->pSelect <> 0 Then
                        Dim pSubquerySelect As SqliteSelect Ptr = _
                            pSourceItem->u4.pSubq->pSelect
                        If (pSubquerySelect->selFlags And SF_NestedFrom) <> 0 Then
                            sqlite3_str_appendf(pAccum, StrPtr(!"(join-%u)"), _
                                pSubquerySelect->selId)
                        ElseIf (pSubquerySelect->selFlags And SF_MultiValue) <> 0 Then
                            sqlite3_str_appendf(pAccum, _
                                StrPtr(!"%u-ROW VALUES CLAUSE"), _
                                pSourceItem->u1.nRow)
                        Else
                            sqlite3_str_appendf(pAccum, _
                                StrPtr(!"(subquery-%u)"), _
                                pSubquerySelect->selId)
                        End If
                    End If
                End If
                fieldCreated = 0
                widthValue = 0
                widthBytes = 0
            End If
        Case Asc("n")
            If pArgList = 0 Then
                If lengthFlag = 2 Then
                    Dim pCount As sqlite3_int64 Ptr = Cva_Arg(args, sqlite3_int64 Ptr)
                    If pCount <> 0 Then pCount[0] = pAccum->nChar
                ElseIf lengthFlag = 1 Then
                    Dim pCount As SQLITE_C_LONG Ptr = Cva_Arg(args, SQLITE_C_LONG Ptr)
                    If pCount <> 0 Then pCount[0] = pAccum->nChar
                Else
                    Dim pCount As SQLITE_C_INT Ptr = Cva_Arg(args, SQLITE_C_INT Ptr)
                    If pCount <> 0 Then pCount[0] = pAccum->nChar
                End If
            End If
            fieldCreated = 0
        Case Asc("%")
            zField[0] = Asc("%")
            nField = 1
        Case Else
            done = -1
            fieldCreated = 0
        End Select

        If fieldCreated <> 0 AndAlso pAccum->accError = 0 Then
            sqlite3PrintfOutputField(pAccum, zField, nField, widthBytes, leftJustify, zeroPad, numericField)
        End If
        If pOwned <> 0 Then
            If pOwnedWithDatabase <> 0 Then
                sqlite3DbFree(pAccum->db, pOwned)
            Else
                sqlite3_free(pOwned)
            End If
        End If
    Loop

    Cva_End(args)
End Sub

Sub sqlite3_str_appendf CDecl Alias "sqlite3_str_appendf" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) Export
    If pAccum = 0 OrElse zFormat = 0 Then Return
    Dim args As Cva_List
    Cva_Start(args, zFormat)
    sqlite3_str_vappendf(pAccum, zFormat, args)
    Cva_End(args)
End Sub

Private Function sqlite3PrintfMakeVString( _
    ByVal db As sqlite3 Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ByRef sourceArgs As Cva_List, _
    ByVal internalFormat As Long _
) As ZString Ptr

    If db = 0 OrElse zFormat = 0 Then Return 0
    Dim buffer(0 To 69) As UByte
    Dim accum As sqlite3_str
    sqlite3StrAccumInit(@accum, db, @buffer(0), SizeOf(buffer), db->lengthLimit)
    If internalFormat <> 0 Then accum.printfFlags = accum.printfFlags Or SQLITE_PRINTF_INTERNAL
    sqlite3_str_vappendf(@accum, zFormat, sourceArgs)
    Dim result As ZString Ptr = sqlite3StrAccumFinish(@accum)
    If accum.accError = SQLITE_NOMEM Then sqlite3OomFault(db)
    Return result
End Function

Function sqlite3VMPrintf CDecl Alias "sqlite3VMPrintf" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ByRef sourceArgs As Cva_List _
) As ZString Ptr Export
    Return sqlite3PrintfMakeVString(db, zFormat, sourceArgs, -1)
End Function

Function sqlite3MPrintf CDecl Alias "sqlite3MPrintf" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) As ZString Ptr Export
    If db = 0 OrElse zFormat = 0 Then Return 0
    Dim args As Cva_List
    Cva_Start(args, zFormat)
    Dim result As ZString Ptr = sqlite3PrintfMakeVString(db, zFormat, args, -1)
    Cva_End(args)
    Return result
End Function

Function sqlite3_vmprintf CDecl Alias "sqlite3_vmprintf" ( _
    ByVal zFormat As Const ZString Ptr, _
    ByRef sourceArgs As Cva_List _
) As ZString Ptr Export
    If zFormat = 0 OrElse sqlite3_initialize() <> SQLITE_OK Then Return 0
    Dim buffer(0 To 69) As UByte
    Dim accum As sqlite3_str
    sqlite3StrAccumInit(@accum, 0, @buffer(0), SizeOf(buffer), SQLITE_MAX_LENGTH)
    sqlite3_str_vappendf(@accum, zFormat, sourceArgs)
    Return sqlite3StrAccumFinish(@accum)
End Function

Function sqlite3_mprintf CDecl Alias "sqlite3_mprintf" ( _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) As ZString Ptr Export
    If zFormat = 0 OrElse sqlite3_initialize() <> SQLITE_OK Then Return 0
    Dim args As Cva_List
    Cva_Start(args, zFormat)
    Dim result As ZString Ptr = sqlite3_vmprintf(zFormat, args)
    Cva_End(args)
    Return result
End Function

Function sqlite3_vsnprintf CDecl Alias "sqlite3_vsnprintf" ( _
    ByVal nByte As SQLITE_C_INT, _
    ByVal zBuffer As ZString Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ByRef sourceArgs As Cva_List _
) As ZString Ptr Export

    If nByte <= 0 OrElse zBuffer = 0 Then Return zBuffer
    If zFormat = 0 Then
        zBuffer[0] = 0
        Return zBuffer
    End If
    Dim accum As sqlite3_str
    sqlite3StrAccumInit(@accum, 0, CPtr(UByte Ptr, zBuffer), nByte, 0)
    sqlite3_str_vappendf(@accum, zFormat, sourceArgs)
    If accum.zText <> 0 AndAlso accum.nChar < accum.nAlloc Then accum.zText[accum.nChar] = 0
    Return zBuffer
End Function

Function sqlite3_snprintf CDecl Alias "sqlite3_snprintf" ( _
    ByVal nByte As SQLITE_C_INT, _
    ByVal zBuffer As ZString Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) As ZString Ptr Export

    If nByte <= 0 OrElse zBuffer = 0 Then Return zBuffer
    If zFormat = 0 Then
        zBuffer[0] = 0
        Return zBuffer
    End If
    Dim args As Cva_List
    Cva_Start(args, zFormat)
    Dim accum As sqlite3_str
    sqlite3StrAccumInit(@accum, 0, CPtr(UByte Ptr, zBuffer), nByte, 0)
    sqlite3_str_vappendf(@accum, zFormat, args)
    Cva_End(args)
    If accum.zText <> 0 AndAlso accum.nChar < accum.nAlloc Then accum.zText[accum.nChar] = 0
    Return zBuffer
End Function

Function sqlite3RCStrRef CDecl Alias "sqlite3RCStrRef" ( _
    ByVal zData As ZString Ptr _
) As ZString Ptr Export

    If zData = 0 Then Return 0
    Dim pHeader As sqlite3_uint64 Ptr = CPtr(sqlite3_uint64 Ptr, CPtr(UByte Ptr, zData) - SizeOf(sqlite3_uint64))
    If pHeader[0] = 0 Then Return zData
    If pHeader[0] = SQLITE_RCSTR_REFCOUNT_MAX Then
        ' A saturated count must never wrap to zero and free live strings.
        pHeader[0] = 0
    Else
        pHeader[0] += 1
    End If
    Return zData
End Function

Sub sqlite3RCStrUnref CDecl Alias "sqlite3RCStrUnref" ( _
    ByVal zData As Any Ptr _
) Export

    If zData = 0 Then Return
    Dim pHeader As UByte Ptr = CPtr(UByte Ptr, zData) - SizeOf(sqlite3_uint64)
    Dim pRefcount As sqlite3_uint64 Ptr = CPtr(sqlite3_uint64 Ptr, pHeader)
    If pRefcount[0] = 0 Then Return
    If pRefcount[0] > 1 Then
        pRefcount[0] -= 1
    Else
        sqlite3_free(pHeader)
    End If
End Sub

Function sqlite3RCStrNew CDecl Alias "sqlite3RCStrNew" ( _
    ByVal nDataByte As sqlite3_uint64 _
) As ZString Ptr Export

    Dim nHeaderByte As ULongInt = SizeOf(sqlite3_uint64)
    If nDataByte > CULngInt(SQLITE_MAX_ALLOCATION_SIZE) - nHeaderByte - 1 Then Return 0
    Dim nAllocation As sqlite3_uint64 = nDataByte + nHeaderByte + 1
    Dim pHeader As Any Ptr = sqlite3_malloc64(nAllocation)
    If pHeader = 0 Then Return 0
    CPtr(sqlite3_uint64 Ptr, pHeader)[0] = 1
    Return CPtr(ZString Ptr, CPtr(UByte Ptr, pHeader) + nHeaderByte)
End Function

Function sqlite3RCStrResize CDecl Alias "sqlite3RCStrResize" ( _
    ByVal zData As ZString Ptr, _
    ByVal nDataByte As sqlite3_uint64 _
) As ZString Ptr Export

    If zData = 0 Then Return 0
    Dim nHeaderByte As ULongInt = SizeOf(sqlite3_uint64)
    If nDataByte > CULngInt(SQLITE_MAX_ALLOCATION_SIZE) - nHeaderByte - 1 Then Return 0
    Dim pOldHeader As Any Ptr = CPtr(UByte Ptr, zData) - nHeaderByte
    Dim pOldRefcount As sqlite3_uint64 Ptr = CPtr(sqlite3_uint64 Ptr, pOldHeader)
    If pOldRefcount[0] <> 1 Then Return 0

    Dim nAllocation As sqlite3_uint64 = nDataByte + nHeaderByte + 1
    Dim pNewHeader As Any Ptr = sqlite3_realloc64(pOldHeader, nAllocation)
    If pNewHeader = 0 Then
        sqlite3_free(pOldHeader)
        Return 0
    End If
    Return CPtr(ZString Ptr, CPtr(UByte Ptr, pNewHeader) + nHeaderByte)
End Function

#ifndef SQLITE_PRINT_BUF_SIZE
#define SQLITE_PRINT_BUF_SIZE 70
#endif

#if defined(SQLITE_DEBUG) OrElse defined(SQLITE_HAVE_OS_TRACE)
Sub sqlite3DebugPrintf CDecl Alias "sqlite3DebugPrintf" ( _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) Export
    If zFormat = 0 Then Return
    Dim outputBuffer(0 To SQLITE_PRINT_BUF_SIZE * 10 - 1) As UByte
    Dim accumulation As sqlite3_str
    sqlite3StrAccumInit(@accumulation, 0, @outputBuffer(0), _
                        SizeOf(outputBuffer), 0)

    Dim args As Cva_List
    Cva_Start(args, zFormat)
    sqlite3_str_vappendf(@accumulation, zFormat, args)
    Cva_End(args)
    sqlite3StrAccumFinish(@accumulation)

    If accumulation.zText <> 0 Then
        sqlite3DebugPrintfWrite(StrPtr("%s"), _
                                CPtr(Const ZString Ptr, accumulation.zText))
        sqlite3DebugPrintfFlush(0)
    End If
End Sub
#endif

/' end of sqlite3_printf.bas '/
