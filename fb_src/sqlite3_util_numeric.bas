/'
    Project: SQLite FreeBASIC port

    File: sqlite3_util_numeric.bas

    Purpose:

        Port standalone numeric and byte helpers from src/util.c.

    Responsibilities:

        - Check double encodings and parse unsigned decimal integers.
        - Perform overflow-checked signed 64-bit arithmetic.
        - Convert integers to and from planner LogEst values.
        - Decode hexadecimal blobs and maintain packed VList entries.

    This file intentionally does NOT contain:

        - SQL expression state, connection safety logging, or query planning.
'/ 

#lang "fb"
#include once "sqlite3_util_numeric.bi"
#include once "sqlite3_constants.bi"

Extern "C"
    Declare Function sqlite3UtilMemcpy CDecl Alias "memcpy" ( _
        ByVal pTarget As Any Ptr, _
        ByVal pSource As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
End Extern

Private Const SQLITE_UTIL_INT64_MAX As sqlite3_int64 = 9223372036854775807
Private Const SQLITE_UTIL_INT64_MIN As sqlite3_int64 = -9223372036854775807 - 1
Private Const SQLITE_UTIL_UINT64_MAX As sqlite3_uint64 = &HFFFFFFFFFFFFFFFF

Dim Shared As Const UByte sqlite3LogEstAddAdjustment(0 To 31) = { _
    10, 10, 9, 9, 8, 8, 7, 7, 7, 6, 6, 6, 5, 5, 5, 4, _
    4, 4, 4, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2 _
}
Dim Shared As Const UByte sqlite3LogEstMantissa(0 To 7) = {0, 2, 3, 5, 6, 7, 8, 9}

Function sqlite3IsNaN CDecl Alias "sqlite3IsNaN" (ByVal value As Double) As SQLITE_C_INT Export
    Return IIf(value <> value, 1, 0)
End Function

Function sqlite3IsOverflow CDecl Alias "sqlite3IsOverflow" (ByVal value As Double) As SQLITE_C_INT Export
    Dim bits As sqlite3_uint64 = 0
    sqlite3UtilMemcpy(@bits, @value, SizeOf(bits))
    If (bits And &H7FF0000000000000) = &H7FF0000000000000 Then Return 1
    Return 0
End Function

Function sqlite3GetUInt32 CDecl Alias "sqlite3GetUInt32" ( _
    ByVal z As Const ZString Ptr, _
    ByVal pValue As SQLITE_C_UINT Ptr _
) As SQLITE_C_INT Export

    If pValue <> 0 Then pValue[0] = 0
    If z = 0 OrElse pValue = 0 OrElse z[0] = 0 Then Return 0

    Dim value As sqlite3_uint64 = 0
    Dim position As Long = 0
    While z[position] >= Asc("0") AndAlso z[position] <= Asc("9")
        Dim digit As sqlite3_uint64 = CULngInt(z[position] - Asc("0"))
        If value > (&HFFFFFFFF - digit) \ 10 Then Return 0
        value = value * 10 + digit
        position += 1
    Wend
    If z[position] <> 0 Then Return 0
    pValue[0] = CUInt(value)
    Return 1
End Function

Function sqlite3BSwap64 CDecl Alias "sqlite3BSwap64" ( _
    ByVal inputValue As sqlite3_uint64 _
) As sqlite3_uint64 Export

    Dim value As sqlite3_uint64 = inputValue
    value = (value Shl 32) Or (value Shr 32)
    value = ((value And &H0000FFFF0000FFFF) Shl 16) Or _
            ((value And &HFFFF0000FFFF0000) Shr 16)
    value = ((value And &H00FF00FF00FF00FF) Shl 8) Or _
            ((value And &HFF00FF00FF00FF00) Shr 8)
    Return value
End Function

Function sqlite3HexToInt CDecl Alias "sqlite3HexToInt" ( _
    ByVal value As SQLITE_C_INT _
) As u8 Export

    If value >= Asc("0") AndAlso value <= Asc("9") Then Return CUByte(value - Asc("0"))
    If value >= Asc("a") AndAlso value <= Asc("f") Then Return CUByte(value - Asc("a") + 10)
    If value >= Asc("A") AndAlso value <= Asc("F") Then Return CUByte(value - Asc("A") + 10)
    Return 0
End Function

Function sqlite3HexToBlob CDecl Alias "sqlite3HexToBlob" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zHex As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As Any Ptr Export

    If db = 0 OrElse zHex = 0 OrElse nByte < 0 Then Return 0
    ' The caller has removed the closing quote from the length. The source
    ' pointer still reaches that quote, but only nByte hex digits are payload.
    If (nByte And 1) <> 0 Then Return 0
    Dim nOutput As SQLITE_C_INT = nByte \ 2
    Dim pBlob As UByte Ptr = CPtr(UByte Ptr, sqlite3DbMallocRawNN(db, CULngInt(nOutput) + 1))
    If pBlob = 0 Then Return 0

    Dim sourceOffset As SQLITE_C_INT = 0
    Dim targetOffset As SQLITE_C_INT = 0
    While sourceOffset < nByte
        Dim highDigit As SQLITE_C_INT = zHex[sourceOffset]
        Dim lowDigit As SQLITE_C_INT = zHex[sourceOffset + 1]
        Dim highValue As Long
        Dim lowValue As Long
        If highDigit >= Asc("0") AndAlso highDigit <= Asc("9") Then
            highValue = highDigit - Asc("0")
        ElseIf highDigit >= Asc("a") AndAlso highDigit <= Asc("f") Then
            highValue = highDigit - Asc("a") + 10
        ElseIf highDigit >= Asc("A") AndAlso highDigit <= Asc("F") Then
            highValue = highDigit - Asc("A") + 10
        Else
            sqlite3DbFree(db, pBlob)
            Return 0
        End If
        If lowDigit >= Asc("0") AndAlso lowDigit <= Asc("9") Then
            lowValue = lowDigit - Asc("0")
        ElseIf lowDigit >= Asc("a") AndAlso lowDigit <= Asc("f") Then
            lowValue = lowDigit - Asc("a") + 10
        ElseIf lowDigit >= Asc("A") AndAlso lowDigit <= Asc("F") Then
            lowValue = lowDigit - Asc("A") + 10
        Else
            sqlite3DbFree(db, pBlob)
            Return 0
        End If
        pBlob[targetOffset] = CUByte((highValue Shl 4) Or lowValue)
        sourceOffset += 2
        targetOffset += 1
    Wend
    pBlob[nOutput] = 0
    Return pBlob
End Function

Function sqlite3AddInt64 CDecl Alias "sqlite3AddInt64" ( _
    ByVal pValue As sqlite3_int64 Ptr, _
    ByVal addend As sqlite3_int64 _
) As SQLITE_C_INT Export

    If pValue = 0 Then Return 1
    Dim currentValue As sqlite3_int64 = pValue[0]
    If addend > 0 AndAlso currentValue > SQLITE_UTIL_INT64_MAX - addend Then Return 1
    If addend < 0 AndAlso currentValue < SQLITE_UTIL_INT64_MIN - addend Then Return 1
    pValue[0] = currentValue + addend
    Return 0
End Function

Function sqlite3SubInt64 CDecl Alias "sqlite3SubInt64" ( _
    ByVal pValue As sqlite3_int64 Ptr, _
    ByVal subtrahend As sqlite3_int64 _
) As SQLITE_C_INT Export

    If pValue = 0 Then Return 1
    Dim currentValue As sqlite3_int64 = pValue[0]
    If subtrahend < 0 AndAlso currentValue > SQLITE_UTIL_INT64_MAX + subtrahend Then Return 1
    If subtrahend > 0 AndAlso currentValue < SQLITE_UTIL_INT64_MIN + subtrahend Then Return 1
    pValue[0] = currentValue - subtrahend
    Return 0
End Function

Function sqlite3MulInt64 CDecl Alias "sqlite3MulInt64" ( _
    ByVal pValue As sqlite3_int64 Ptr, _
    ByVal multiplier As sqlite3_int64 _
) As SQLITE_C_INT Export

    If pValue = 0 Then Return 1
    Dim multiplicand As sqlite3_int64 = pValue[0]
    If multiplicand = 0 OrElse multiplier = 0 Then
        pValue[0] = 0
        Return 0
    End If

    Dim negative As Long = CInt((multiplicand < 0) Xor (multiplier < 0))
    Dim leftMagnitude As sqlite3_uint64
    Dim rightMagnitude As sqlite3_uint64
    If multiplicand < 0 Then
        leftMagnitude = CULngInt(Not multiplicand) + 1
    Else
        leftMagnitude = CULngInt(multiplicand)
    End If
    If multiplier < 0 Then
        rightMagnitude = CULngInt(Not multiplier) + 1
    Else
        rightMagnitude = CULngInt(multiplier)
    End If

    Dim limit As sqlite3_uint64 = CULngInt(SQLITE_UTIL_INT64_MAX)
    If negative <> 0 Then limit = CULngInt(1) Shl 63
    If leftMagnitude > limit \ rightMagnitude Then Return 1
    Dim product As sqlite3_uint64 = leftMagnitude * rightMagnitude

    If negative <> 0 Then
        If product = (CULngInt(1) Shl 63) Then
            pValue[0] = SQLITE_UTIL_INT64_MIN
        Else
            pValue[0] = -CLngInt(product)
        End If
    Else
        pValue[0] = CLngInt(product)
    End If
    Return 0
End Function

Function sqlite3AbsInt32 CDecl Alias "sqlite3AbsInt32" ( _
    ByVal value As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If value >= 0 Then Return value
    If value = -2147483647 - 1 Then Return &H7FFFFFFF
    Return 0 - value
End Function

Function sqlite3LogEstAdd CDecl Alias "sqlite3LogEstAdd" ( _
    ByVal leftValue As Short, _
    ByVal rightValue As Short _
) As Short Export

    Dim difference As LongInt = CLngInt(leftValue) - rightValue
    If difference >= 0 Then
        If difference > 49 Then Return leftValue
        If difference > 31 Then Return leftValue + 1
        Return leftValue + sqlite3LogEstAddAdjustment(difference)
    End If
    difference = 0 - difference
    If difference > 49 Then Return rightValue
    If difference > 31 Then Return rightValue + 1
    Return rightValue + sqlite3LogEstAddAdjustment(difference)
End Function

Function sqlite3LogEst CDecl Alias "sqlite3LogEst" ( _
    ByVal inputValue As sqlite3_uint64 _
) As Short Export

    If inputValue < 2 Then Return 0
    Dim value As sqlite3_uint64 = inputValue
    Dim estimate As Long = 40
    If value < 8 Then
        While value < 8
            estimate -= 10
            value = value Shl 1
        Wend
    Else
        While value > 15
            estimate += 10
            value = value Shr 1
        Wend
    End If
    Return sqlite3LogEstMantissa(value And 7) + estimate - 10
End Function

Function sqlite3LogEstFromDouble CDecl Alias "sqlite3LogEstFromDouble" ( _
    ByVal value As Double _
) As Short Export

    If value <= 1.0 Then Return 0
    If value <> value Then Return 0
    If value <= 2000000000.0 Then Return sqlite3LogEst(CULngInt(value))
    Dim bits As sqlite3_uint64 = 0
    sqlite3UtilMemcpy(@bits, @value, SizeOf(bits))
    Dim exponent As Long = CLng((bits Shr 52) And &H7FF) - 1022
    Return exponent * 10
End Function

Function sqlite3LogEstToInt CDecl Alias "sqlite3LogEstToInt" ( _
    ByVal inputValue As Short _
) As sqlite3_uint64 Export

    Dim value As LongInt = inputValue
    Dim remainder As LongInt = value Mod 10
    value = value \ 10
    If remainder >= 5 Then
        remainder -= 2
    ElseIf remainder >= 1 Then
        remainder -= 1
    End If
    If value > 60 Then Return CULngInt(SQLITE_UTIL_INT64_MAX)
    If value < -60 Then Return 0
    Dim mantissa As sqlite3_uint64 = CULngInt(remainder + 8)
    If value >= 3 Then
        Return mantissa Shl (value - 3)
    End If
    Return mantissa Shr (3 - value)
End Function

Function sqlite3VListAdd CDecl Alias "sqlite3VListAdd" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pListArgument As Any Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal nName As SQLITE_C_INT, _
    ByVal value As SQLITE_C_INT _
) As Any Ptr Export

    If db = 0 OrElse nName < 0 OrElse (nName > 0 AndAlso zName = 0) Then Return pListArgument
    If CULngInt(nName) > SQLITE_MAX_ALLOCATION_SIZE Then Return pListArgument
    Dim nSlotsForName As sqlite3_uint64 = CULngInt(nName) \ 4 + 3
    Dim pList As SQLITE_C_INT Ptr = CPtr(SQLITE_C_INT Ptr, pListArgument)
    If pList <> 0 AndAlso (pList[0] < 3 OrElse pList[1] < 2 OrElse pList[1] > pList[0]) Then Return pListArgument

    If pList = 0 OrElse CULngInt(pList[1]) + nSlotsForName > CULngInt(pList[0]) Then
        Dim nAlloc As sqlite3_uint64
        If pList = 0 Then
            nAlloc = 10 + nSlotsForName
        Else
            nAlloc = CULngInt(pList[0]) * 2 + nSlotsForName
        End If
        If nAlloc > SQLITE_MAX_ALLOCATION_SIZE \ SizeOf(SQLITE_C_INT) Then Return pListArgument
        Dim pNew As SQLITE_C_INT Ptr = CPtr(SQLITE_C_INT Ptr, _
            sqlite3DbRealloc(db, pList, nAlloc * SizeOf(SQLITE_C_INT)))
        If pNew = 0 Then Return pListArgument
        pList = pNew
        If pListArgument = 0 Then pList[1] = 2
        pList[0] = CLng(nAlloc)
    End If

    Dim startIndex As SQLITE_C_INT = pList[1]
    If CULngInt(startIndex) + nSlotsForName > CULngInt(pList[0]) Then Return pListArgument
    pList[startIndex] = value
    pList[startIndex + 1] = CLng(nSlotsForName)
    Dim zDestination As UByte Ptr = CPtr(UByte Ptr, @pList[startIndex + 2])
    If nName > 0 Then sqlite3UtilMemcpy(zDestination, zName, CULng(nName))
    zDestination[nName] = 0
    pList[1] = CLng(CULngInt(startIndex) + nSlotsForName)
    Return pList
End Function

Function sqlite3VListNumToName CDecl Alias "sqlite3VListNumToName" ( _
    ByVal pListArgument As Any Ptr, _
    ByVal value As SQLITE_C_INT _
) As Const ZString Ptr Export

    If pListArgument = 0 Then Return 0
    Dim pList As Const SQLITE_C_INT Ptr = CPtr(Const SQLITE_C_INT Ptr, pListArgument)
    Dim allocatedSlots As Long = pList[0]
    Dim usedSlots As Long = pList[1]
    If allocatedSlots < 3 OrElse usedSlots < 2 OrElse usedSlots > allocatedSlots Then Return 0
    Dim index As Long = 2
    While index + 1 < usedSlots
        Dim slotCount As Long = pList[index + 1]
        If slotCount < 3 OrElse index + slotCount > usedSlots Then Return 0
        If pList[index] = value Then Return CPtr(Const ZString Ptr, @pList[index + 2])
        index += slotCount
    Wend
    Return 0
End Function

Function sqlite3VListNameToNum CDecl Alias "sqlite3VListNameToNum" ( _
    ByVal pListArgument As Any Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal nName As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pListArgument = 0 OrElse zName = 0 OrElse nName < 0 Then Return 0
    Dim pList As Const SQLITE_C_INT Ptr = CPtr(Const SQLITE_C_INT Ptr, pListArgument)
    Dim allocatedSlots As Long = pList[0]
    Dim usedSlots As Long = pList[1]
    If allocatedSlots < 3 OrElse usedSlots < 2 OrElse usedSlots > allocatedSlots Then Return 0
    Dim index As Long = 2
    While index + 1 < usedSlots
        Dim slotCount As Long = pList[index + 1]
        If slotCount < 3 OrElse index + slotCount > usedSlots Then Return 0
        Dim zEntry As Const UByte Ptr = CPtr(Const UByte Ptr, @pList[index + 2])
        If CULngInt(nName) + 1 > CULngInt(slotCount - 2) * SizeOf(SQLITE_C_INT) Then
            index += slotCount
            Continue While
        End If
        Dim sameName As Long = -1
        For byteIndex As Long = 0 To nName - 1
            If zEntry[byteIndex] <> zName[byteIndex] Then
                sameName = 0
                Exit For
            End If
        Next
        If sameName <> 0 AndAlso zEntry[nName] = 0 Then Return pList[index]
        index += slotCount
    Wend
    Return 0
End Function

/' end of sqlite3_util_numeric.bas '/
