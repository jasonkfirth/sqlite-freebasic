/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_serial.bas

    Purpose:

        Select, encode, and decode SQLite record serial types.

    Responsibilities:

        - Port serial-type byte-length mapping.
        - Encode one field's header serial type and payload bytes.
        - Decode big-endian signed integers, IEEE doubles, NULLs, text, and blobs.
        - Swap the 32-bit halves of mixed-endian floating-point words when enabled.

    This file intentionally does NOT contain:

        - Full record-header construction or B-tree storage.
'/

#lang "fb"
#include once "sqlite3_vdbe_serial.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_vdbe_record.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_varint.bi"

Extern "C"
    Declare Function sqlite3SerialMemcpy CDecl Alias "memcpy" ( _
        ByVal destination As Any Ptr, _
        ByVal source As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
End Extern

Extern "C"
    Declare Function sqlite3VdbeSerialMemcpy CDecl Alias "memcpy" ( _
        ByVal destination As Any Ptr, _
        ByVal source As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
End Extern

#ifdef SQLITE_MIXED_ENDIAN_64BIT_FLOAT
Function sqlite3FloatSwap CDecl Alias "sqlite3FloatSwap" ( _
    ByVal value As sqlite3_uint64 _
) As sqlite3_uint64
    ' Mixed-endian hosts store the two 32-bit halves of a REAL word reversed.
    Dim lowWord As sqlite3_uint64 = value And &HFFFFFFFFULL
    Dim highWord As sqlite3_uint64 = (value Shr 32) And &HFFFFFFFFULL
    Return (lowWord Shl 32) Or highWord
End Function
#endif

Private Function sqlite3VdbeSerialGet7( _
    ByVal zData As Const UByte Ptr, _
    ByVal pMem As SqliteVdbeMem Ptr _
) As SQLITE_C_INT
    If zData = 0 OrElse pMem = 0 Then Return 1
    Dim bits As ULongInt = 0
    For i As Long = 0 To 7
        bits = (bits Shl 8) Or CULngInt(zData[i])
    Next
    Dim exponentMask As ULongInt = CULngInt(&H7FF00000) Shl 32
    Dim fractionMask As ULongInt = &H000FFFFFFFFFFFFF
    If (bits And exponentMask) = exponentMask AndAlso (bits And fractionMask) <> 0 Then
        pMem->flags = MEM_NULL
        Return 1
    End If
    sqlite3VdbeSerialMemcpy(@pMem->u.r, @bits, SizeOf(bits))
    pMem->flags = MEM_REAL
    Return 0
End Function

Function sqlite3VdbeSerialType CDecl Alias "sqlite3VdbeSerialType" ( _
    ByVal pMemArgument As Any Ptr, _
    ByVal fileFormat As SQLITE_C_INT, _
    ByVal pLength As SQLITE_C_UINT Ptr _
) As SQLITE_C_UINT Export

    If pMemArgument = 0 OrElse pLength = 0 Then Return 0
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pMemArgument)
    Dim flags As UShort = pMem->flags
    If (flags And MEM_NULL) <> 0 Then
        *pLength = 0
        Return 0
    End If

    If (flags And (MEM_INT Or MEM_INTREAL)) <> 0 Then
        Dim integerValue As sqlite3_int64 = pMem->u.i
        Dim magnitude As ULongInt
        If integerValue < 0 Then
            magnitude = Not CULngInt(integerValue)
        Else
            magnitude = CULngInt(integerValue)
        End If
        If magnitude <= 127 Then
            ' Serial types 8 and 9 encode the common INTEGER constants 0 and 1
            ' without a payload, beginning with database format 4.
            If (integerValue = 0 OrElse integerValue = 1) AndAlso fileFormat >= 4 Then
                *pLength = 0
                Return CUInt(8 + integerValue)
            End If
            *pLength = 1
            Return 1
        ElseIf magnitude <= 32767 Then
            *pLength = 2
            Return 2
        ElseIf magnitude <= 8388607 Then
            *pLength = 3
            Return 3
        ElseIf magnitude <= 2147483647 Then
            *pLength = 4
            Return 4
        ElseIf magnitude <= 140737488355327 Then
            ' A six-byte signed integer carries 47 magnitude bits plus sign.
            *pLength = 6
            Return 5
        End If

        *pLength = 8
        If (flags And MEM_INTREAL) <> 0 Then
            pMem->u.r = CDbl(pMem->u.i)
            pMem->flags = (pMem->flags And Not MEM_INTREAL) Or MEM_REAL
            Return 7
        End If
        Return 6
    End If

    If (flags And MEM_REAL) <> 0 Then
        *pLength = 8
        Return 7
    End If

    If pMem->n < 0 Then
        *pLength = 0
        Return 0
    End If
    Dim nByte As ULongInt = CULngInt(pMem->n)
    If (flags And MEM_ZERO) <> 0 Then
        If pMem->u.nZero < 0 Then
            *pLength = 0
            Return 0
        End If
        nByte += CULngInt(pMem->u.nZero)
    End If
    If nByte > &HFFFFFFFF Then
        *pLength = 0
        Return 0
    End If
    *pLength = CUInt(nByte)
    Return CUInt(nByte * 2 + 12 + IIf((flags And MEM_STR) <> 0, 1, 0))
End Function

Function sqlite3VdbeSerialPut CDecl Alias "sqlite3VdbeSerialPut" ( _
    ByVal pMemArgument As Any Ptr, _
    ByVal serialType As u32, _
    ByVal zHeader As UByte Ptr, _
    ByVal headerCapacity As u32, _
    ByVal pHeaderBytes As u32 Ptr, _
    ByVal zData As UByte Ptr, _
    ByVal dataCapacity As u32, _
    ByVal pDataBytes As u32 Ptr _
) As SQLITE_C_INT Export

    If pHeaderBytes = 0 OrElse pDataBytes = 0 OrElse pMemArgument = 0 Then Return SQLITE_MISUSE
    pHeaderBytes[0] = 0
    pDataBytes[0] = 0
    Dim headerBytes As u32 = CULng(sqlite3VarintLen(serialType))
    Dim dataBytes As u32 = sqlite3VdbeSerialTypeLen(serialType)
    If zHeader = 0 OrElse headerCapacity < headerBytes OrElse dataCapacity < dataBytes Then
        Return SQLITE_TOOBIG
    End If
    If dataBytes > 0 AndAlso zData = 0 Then Return SQLITE_MISUSE

    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pMemArgument)
    If serialType >= 1 AndAlso serialType <= 6 AndAlso _
       (pMem->flags And (MEM_INT Or MEM_INTREAL)) = 0 Then Return SQLITE_MISMATCH
    If serialType = 7 AndAlso (pMem->flags And MEM_REAL) = 0 Then Return SQLITE_MISMATCH
    If serialType >= 12 Then
        If (serialType And 1) <> 0 AndAlso (pMem->flags And MEM_STR) = 0 Then Return SQLITE_MISMATCH
        If (serialType And 1) = 0 AndAlso (pMem->flags And MEM_BLOB) = 0 Then Return SQLITE_MISMATCH
        If pMem->n < 0 Then Return SQLITE_MISUSE
        Dim logicalLength As ULongInt = CULngInt(pMem->n)
        If (pMem->flags And MEM_ZERO) <> 0 Then
            If pMem->u.nZero < 0 Then Return SQLITE_MISUSE
            logicalLength += CULngInt(pMem->u.nZero)
        End If
        If logicalLength <> dataBytes OrElse (pMem->n > 0 AndAlso pMem->z = 0) Then
            Return SQLITE_MISMATCH
        End If
    End If

    Dim headerLength As SQLITE_C_INT = sqlite3PutVarint(zHeader, serialType)
    If headerLength <= 0 Then Return SQLITE_CORRUPT
    pHeaderBytes[0] = CUInt(headerLength)

    If serialType >= 1 AndAlso serialType <= 6 Then
        Dim valueBits As ULongInt = CULngInt(pMem->u.i)
        For i As Long = dataBytes - 1 To 0 Step -1
            zData[i] = CUByte(valueBits And &HFF)
            valueBits = valueBits Shr 8
        Next
    ElseIf serialType = 7 Then
        Dim valueBits As ULongInt
        sqlite3SerialMemcpy(@valueBits, @pMem->u.r, SizeOf(valueBits))
        For i As Long = 7 To 0 Step -1
            zData[i] = CUByte(valueBits And &HFF)
            valueBits = valueBits Shr 8
        Next
    ElseIf serialType >= 12 Then
        If pMem->n > 0 Then sqlite3SerialMemcpy(zData, pMem->z, CULng(pMem->n))
        For i As Long = pMem->n To CInt(dataBytes) - 1
            zData[i] = 0
        Next
    End If
    pDataBytes[0] = dataBytes
    Return SQLITE_OK
End Function

Function sqlite3VdbeSerialTypeLen CDecl Alias "sqlite3VdbeSerialTypeLen" ( _
    ByVal serialType As u32 _
) As u32 Export
    If serialType >= 12 Then Return (serialType - 12) \ 2
    Select Case serialType
    Case 1
        Return 1
    Case 2
        Return 2
    Case 3
        Return 3
    Case 4
        Return 4
    Case 5
        Return 6
    Case 6, 7
        Return 8
    End Select
    Return 0
End Function

Function sqlite3VdbeOneByteSerialTypeLen CDecl Alias "sqlite3VdbeOneByteSerialTypeLen" ( _
    ByVal serialType As u8 _
) As u8 Export
    Return CByte(sqlite3VdbeSerialTypeLen(serialType))
End Function

Sub sqlite3VdbeSerialGet CDecl Alias "sqlite3VdbeSerialGet" ( _
    ByVal zData As Const UByte Ptr, _
    ByVal serialType As u32, _
    ByVal pMemArgument As Any Ptr _
) Export

    If pMemArgument = 0 Then Exit Sub
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pMemArgument)
    If zData = 0 AndAlso sqlite3VdbeSerialTypeLen(serialType) > 0 Then
        pMem->flags = MEM_NULL
        Return
    End If

    Select Case serialType
    Case 10
        pMem->flags = MEM_NULL Or MEM_ZERO
        pMem->n = 0
        pMem->u.nZero = 0
    Case 0, 11
        pMem->flags = MEM_NULL
    Case 1
        Dim value As Long = zData[0]
        If value >= 128 Then value -= 256
        pMem->u.i = value
        pMem->flags = MEM_INT
    Case 2
        Dim value As Long = CInt(zData[0]) * 256 + CInt(zData[1])
        If value >= 32768 Then value -= 65536
        pMem->u.i = value
        pMem->flags = MEM_INT
    Case 3
        Dim value As LongInt = CInt(zData[0]) * 65536 + CInt(zData[1]) * 256 + CInt(zData[2])
        If value >= 8388608 Then value -= 16777216
        pMem->u.i = value
        pMem->flags = MEM_INT
    Case 4
        Dim value As LongInt = CULngInt(zData[0]) Shl 24
        value Or= CULngInt(zData[1]) Shl 16
        value Or= CULngInt(zData[2]) Shl 8
        value Or= zData[3]
        If (value And &H80000000) <> 0 Then value -= 4294967296
        pMem->u.i = value
        pMem->flags = MEM_INT
    Case 5
        Dim bits As ULongInt = 0
        For i As Long = 0 To 5
            bits = (bits Shl 8) Or CULngInt(zData[i])
        Next
        If (bits And &H800000000000) <> 0 Then bits = bits Or &HFFFF000000000000
        sqlite3VdbeSerialMemcpy(@pMem->u.i, @bits, SizeOf(bits))
        pMem->flags = MEM_INT
    Case 6
        Dim bits As ULongInt = 0
        For i As Long = 0 To 7
            bits = (bits Shl 8) Or CULngInt(zData[i])
        Next
        sqlite3VdbeSerialMemcpy(@pMem->u.i, @bits, SizeOf(bits))
        pMem->flags = MEM_INT
    Case 7
        sqlite3VdbeSerialGet7(zData, pMem)
    Case 8, 9
        pMem->u.i = serialType - 8
        pMem->flags = MEM_INT
    Case Else
        pMem->z = CPtr(UByte Ptr, zData)
        pMem->n = CLng((serialType - 12) \ 2)
        If (serialType And 1) = 0 Then
            pMem->flags = MEM_BLOB Or MEM_EPHEM
        Else
            pMem->flags = MEM_STR Or MEM_EPHEM
        End If
    End Select
End Sub

Function sqlite3VdbeRecordReadVarint32 ( _
    ByVal zRecord As Const UByte Ptr, _
    ByVal endOffset As Long, _
    ByRef offset As Long, _
    ByRef value As u32 _
) As Long
    If zRecord = 0 OrElse offset < 0 OrElse offset >= endOffset Then Return 0
    Dim decoded As ULongInt = 0
    For i As Long = 0 To 7
        If offset + i >= endOffset Then Return 0
        Dim byteValue As UByte = zRecord[offset + i]
        decoded = (decoded Shl 7) Or CULngInt(byteValue And &H7F)
        If byteValue < &H80 Then
            offset += i + 1
            If decoded > &HFFFFFFFF Then
                value = &HFFFFFFFF
            Else
                value = CULng(decoded)
            End If
            Return i + 1
        End If
    Next

    If offset + 8 >= endOffset Then Return 0
    decoded = (decoded Shl 8) Or CULngInt(zRecord[offset + 8])
    offset += 9
    If decoded > &HFFFFFFFF Then
        value = &HFFFFFFFF
    Else
        value = CULng(decoded)
    End If
    Return 9
End Function

Sub sqlite3VdbeRecordUnpack CDecl Alias "sqlite3VdbeRecordUnpack" ( _
    ByVal nKey As SQLITE_C_INT, _
    ByVal pKey As Const Any Ptr, _
    ByVal pRecordArgument As Any Ptr _
) Export

    If pRecordArgument = 0 Then Exit Sub
    Dim pRecord As sqlite3VdbeUnpackedRecord Ptr = _
        CPtr(sqlite3VdbeUnpackedRecord Ptr, pRecordArgument)
    pRecord->default_rc = 0
    pRecord->errCode = SQLITE_OK
    If pKey = 0 OrElse nKey <= 0 OrElse pRecord->pKeyInfo = 0 OrElse _
       pRecord->aMem = 0 OrElse pRecord->nField = 0 Then
        pRecord->nField = 0
        pRecord->errCode = SQLITE_CORRUPT
        Exit Sub
    End If

    Dim pKeyInfo As sqlite3VdbeKeyInfoPrefix Ptr = _
        CPtr(sqlite3VdbeKeyInfoPrefix Ptr, pRecord->pKeyInfo)
    ' Pre-update uses inline KeyInfo storage with nAllField left uninitialized.
    ' nField is the allocated record capacity, bounded by nKeyField + 1.
    If pRecord->nField > CLng(pKeyInfo->nKeyField) + 1 OrElse _
       (pKeyInfo->enc <> SQLITE_UTF8 AndAlso pKeyInfo->enc <> SQLITE_UTF16LE AndAlso _
        pKeyInfo->enc <> SQLITE_UTF16BE) Then
        pRecord->nField = 0
        pRecord->errCode = SQLITE_CORRUPT
        Exit Sub
    End If

    Dim zRecord As Const UByte Ptr = CPtr(Const UByte Ptr, pKey)
    Dim offset As Long = 0
    Dim headerBytes As u32 = 0
    If sqlite3VdbeRecordReadVarint32(zRecord, nKey, offset, headerBytes) = 0 OrElse _
       headerBytes < CUInt(offset) OrElse headerBytes > CUInt(nKey) Then
        pRecord->nField = 0
        pRecord->errCode = SQLITE_CORRUPT
        Exit Sub
    End If

    Dim dataOffset As Long = CLng(headerBytes)
    Dim unpackedCount As Long = 0
    While offset < headerBytes AndAlso unpackedCount < pRecord->nField AndAlso dataOffset <= nKey
        Dim serialType As u32 = 0
        If sqlite3VdbeRecordReadVarint32(zRecord, CLng(headerBytes), offset, serialType) = 0 Then
            pRecord->errCode = SQLITE_CORRUPT
            Exit While
        End If
        Dim dataLength As u32 = sqlite3VdbeSerialTypeLen(serialType)
        If dataLength > CULng(nKey - dataOffset) Then
            Dim pBadMem As SqliteVdbeMem Ptr = @pRecord->aMem[unpackedCount]
            sqlite3VdbeMemInit(pBadMem, pKeyInfo->db, MEM_NULL)
            sqlite3VdbeMemSetNull(pBadMem)
            unpackedCount += 1
            pRecord->errCode = SQLITE_CORRUPT
            Exit While
        End If

        Dim pMem As SqliteVdbeMem Ptr = @pRecord->aMem[unpackedCount]
        sqlite3VdbeMemInit(pMem, pKeyInfo->db, MEM_NULL)
        pMem->enc = pKeyInfo->enc
        sqlite3VdbeSerialGet(zRecord + dataOffset, serialType, pMem)
        dataOffset += dataLength
        unpackedCount += 1
    Wend
    pRecord->nField = CUShort(unpackedCount)
End Sub

/' end of sqlite3_vdbe_serial.bas '/
