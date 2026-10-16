/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_compare.bas

    Purpose:

        Compare VDBE Mem values, BINARY text, and signed integers with reals.

    Responsibilities:

        - Preserve SQLite's NaN, range-boundary, and mixed numeric ordering.
        - Truncate real values toward zero before the integer comparison.
        - Compare BINARY text bytewise and identify the built-in BINARY CollSeq.
        - Order NULL, numeric, TEXT, and BLOB Mem values with CollSeq callbacks.
        - Compare record keys against serialized index records.

    This file intentionally does NOT contain:

        - The collation registry, non-BINARY collation implementations, or VDBE opcodes.
'/

#lang "fb"
#include once "sqlite3_vdbe_compare.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_vdbe_mem_text.bi"
#include once "sqlite3_vdbe_record.bi"
#include once "sqlite3_vdbe_serial.bi"
#include once "sqlite3_rowset.bi"

Function sqlite3BinaryCompare CDecl Alias "sqlite3BinaryCompare" ( _
    ByVal pUser As Any Ptr, _
    ByVal nLeft As SQLITE_C_INT, _
    ByVal pLeftArgument As Const Any Ptr, _
    ByVal nRight As SQLITE_C_INT, _
    ByVal pRightArgument As Const Any Ptr _
) As SQLITE_C_INT Export
    If nLeft < 0 OrElse nRight < 0 Then Return 0
    If nLeft > 0 AndAlso pLeftArgument = 0 Then Return 0
    If nRight > 0 AndAlso pRightArgument = 0 Then Return 0

    Dim pLeft As Const UByte Ptr = CPtr(Const UByte Ptr, pLeftArgument)
    Dim pRight As Const UByte Ptr = CPtr(Const UByte Ptr, pRightArgument)
    Dim nCompare As SQLITE_C_INT = IIf(nLeft < nRight, nLeft, nRight)
    For byteIndex As SQLITE_C_INT = 0 To nCompare - 1
        If pLeft[byteIndex] < pRight[byteIndex] Then Return -1
        If pLeft[byteIndex] > pRight[byteIndex] Then Return 1
    Next
    If nLeft < nRight Then Return -1
    If nLeft > nRight Then Return 1
    Return 0
End Function

Function sqlite3IsBinary CDecl Alias "sqlite3IsBinary" ( _
    ByVal pCollation As Const sqlite3CollSeq Ptr _
) As SQLITE_C_INT Export
    If pCollation = 0 Then Return 1
    If pCollation->xCmp = @sqlite3BinaryCompare Then Return 1
    Return 0
End Function

Private Function isAllZero CDecl Alias "isAllZero" ( _
    ByVal z As Const UByte Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As Long
    For i As Long = 0 To nByte - 1
        If z = 0 OrElse z[i] <> 0 Then Return 0
    Next
    Return 1
End Function

Private Function sqlite3VdbeCompareIsRowSet(ByVal pMem As Const SqliteVdbeMem Ptr) As Long
    If pMem = 0 OrElse (pMem->flags And (MEM_BLOB Or MEM_DYN)) <> (MEM_BLOB Or MEM_DYN) Then
        Return 0
    End If
    If pMem->xDel = @sqlite3RowSetDelete Then Return -1
    Return 0
End Function

Function sqlite3IntFloatCompare CDecl Alias "sqlite3IntFloatCompare" ( _
    ByVal integerValue As sqlite3_int64, _
    ByVal realValue As Double _
) As SQLITE_C_INT Export

    If realValue <> realValue Then Return 1
    If realValue < -9223372036854775808.0 Then Return 1
    If realValue >= 9223372036854775808.0 Then Return -1

    Dim truncatedReal As sqlite3_int64 = CLngInt(Fix(realValue))
    If integerValue < truncatedReal Then Return -1
    If integerValue > truncatedReal Then Return 1

    Dim integerAsReal As Double = CDbl(integerValue)
    If integerAsReal < realValue Then Return -1
    If integerAsReal > realValue Then Return 1
    Return 0
End Function

Function sqlite3BlobCompare CDecl Alias "sqlite3BlobCompare" ( _
    ByVal pLeftArgument As Const Any Ptr, _
    ByVal pRightArgument As Const Any Ptr _
) As SQLITE_C_INT Export

    If pLeftArgument = 0 OrElse pRightArgument = 0 Then Return 0
    Dim pLeft As Const SqliteVdbeMem Ptr = CPtr(Const SqliteVdbeMem Ptr, pLeftArgument)
    Dim pRight As Const SqliteVdbeMem Ptr = CPtr(Const SqliteVdbeMem Ptr, pRightArgument)
    If sqlite3VdbeCompareIsRowSet(pLeft) <> 0 OrElse _
       sqlite3VdbeCompareIsRowSet(pRight) <> 0 Then Return 0
    If pLeft->n < 0 OrElse pRight->n < 0 Then Return 0
    Dim leftBytes As SQLITE_C_INT = pLeft->n
    Dim rightBytes As SQLITE_C_INT = pRight->n
    Dim leftZero As Long = (pLeft->flags And MEM_ZERO) <> 0
    Dim rightZero As Long = (pRight->flags And MEM_ZERO) <> 0

    If leftZero <> 0 AndAlso rightZero <> 0 Then
        Return pLeft->u.nZero - pRight->u.nZero
    ElseIf leftZero <> 0 Then
        If isAllZero(pRight->z, rightBytes) = 0 Then Return -1
        Return pLeft->u.nZero - rightBytes
    ElseIf rightZero <> 0 Then
        If isAllZero(pLeft->z, leftBytes) = 0 Then Return 1
        Return leftBytes - pRight->u.nZero
    End If

    Dim commonBytes As Long = leftBytes
    If commonBytes > rightBytes Then commonBytes = rightBytes
    For i As Long = 0 To commonBytes - 1
        If pLeft->z = 0 Then Return -1
        If pRight->z = 0 Then Return 1
        Dim leftByte As Long = pLeft->z[i]
        Dim rightByte As Long = pRight->z[i]
        If leftByte < rightByte Then Return -1
        If leftByte > rightByte Then Return 1
    Next
    Return leftBytes - rightBytes
End Function

Function sqlite3MemCompare CDecl Alias "sqlite3MemCompare" ( _
    ByVal pLeftArgument As Const Any Ptr, _
    ByVal pRightArgument As Const Any Ptr, _
    ByVal pCollation As Const Any Ptr _
) As SQLITE_C_INT Export

    If pLeftArgument = 0 OrElse pRightArgument = 0 Then Return 0
    Dim pLeft As Const SqliteVdbeMem Ptr = CPtr(Const SqliteVdbeMem Ptr, pLeftArgument)
    Dim pRight As Const SqliteVdbeMem Ptr = CPtr(Const SqliteVdbeMem Ptr, pRightArgument)
    If sqlite3VdbeCompareIsRowSet(pLeft) <> 0 OrElse _
       sqlite3VdbeCompareIsRowSet(pRight) <> 0 Then Return SQLITE_MISUSE
    If pLeft->n < 0 OrElse pRight->n < 0 Then Return SQLITE_MISUSE
    Dim leftFlags As UShort = pLeft->flags
    Dim rightFlags As UShort = pRight->flags
    Dim combinedFlags As UShort = leftFlags Or rightFlags

    If (combinedFlags And MEM_NULL) <> 0 Then
        If (leftFlags And MEM_NULL) <> 0 Then
            If (rightFlags And MEM_NULL) <> 0 Then Return 0
            Return -1
        End If
        Return 1
    End If

    If (combinedFlags And (MEM_INT Or MEM_REAL Or MEM_INTREAL)) <> 0 Then
        If (leftFlags And rightFlags And (MEM_INT Or MEM_INTREAL)) <> 0 Then
            If pLeft->u.i < pRight->u.i Then Return -1
            If pLeft->u.i > pRight->u.i Then Return 1
            Return 0
        End If
        If (leftFlags And rightFlags And MEM_REAL) <> 0 Then
            If pLeft->u.r < pRight->u.r Then Return -1
            If pLeft->u.r > pRight->u.r Then Return 1
            Return 0
        End If
        If (leftFlags And (MEM_INT Or MEM_INTREAL)) <> 0 Then
            If (rightFlags And MEM_REAL) <> 0 Then
                Return sqlite3IntFloatCompare(pLeft->u.i, pRight->u.r)
            ElseIf (rightFlags And (MEM_INT Or MEM_INTREAL)) <> 0 Then
                If pLeft->u.i < pRight->u.i Then Return -1
                If pLeft->u.i > pRight->u.i Then Return 1
                Return 0
            End If
            Return -1
        End If
        If (leftFlags And MEM_REAL) <> 0 Then
            If (rightFlags And (MEM_INT Or MEM_INTREAL)) <> 0 Then
                Return -sqlite3IntFloatCompare(pRight->u.i, pLeft->u.r)
            End If
            Return -1
        End If
        Return 1
    End If

    If (combinedFlags And MEM_STR) <> 0 Then
        If (leftFlags And MEM_STR) = 0 Then Return 1
        If (rightFlags And MEM_STR) = 0 Then Return -1
        If pCollation <> 0 Then
            Dim pColl As Const sqlite3CollSeq Ptr = CPtr(Const sqlite3CollSeq Ptr, pCollation)
            If pColl->xCmp = 0 Then Return 0
            If pLeft->enc = pColl->enc Then
                Return pColl->xCmp(pColl->pUser, pLeft->n, pLeft->z, pRight->n, pRight->z)
            End If

            Dim leftCopy As SqliteVdbeMem
            Dim rightCopy As SqliteVdbeMem
            sqlite3VdbeMemInit(@leftCopy, pLeft->db, MEM_NULL)
            sqlite3VdbeMemInit(@rightCopy, pLeft->db, MEM_NULL)
            sqlite3VdbeMemShallowCopy(@leftCopy, CPtr(Any Ptr, pLeft), MEM_EPHEM)
            sqlite3VdbeMemShallowCopy(@rightCopy, CPtr(Any Ptr, pRight), MEM_EPHEM)
            Dim leftText As UByte Ptr = CPtr(UByte Ptr, sqlite3ValueText(@leftCopy, pColl->enc))
            Dim rightText As UByte Ptr = CPtr(UByte Ptr, sqlite3ValueText(@rightCopy, pColl->enc))
            Dim comparison As SQLITE_C_INT = 0
            If leftText <> 0 AndAlso rightText <> 0 Then
                comparison = pColl->xCmp(pColl->pUser, leftCopy.n, leftText, rightCopy.n, rightText)
            End If
            sqlite3VdbeMemReleaseMalloc(@leftCopy)
            sqlite3VdbeMemReleaseMalloc(@rightCopy)
            Return comparison
        End If
    End If

    Return sqlite3BlobCompare(CPtr(Const Any Ptr, pLeft), _
                              CPtr(Const Any Ptr, pRight))
End Function

Function sqlite3VdbeRecordCompareWithSkip CDecl Alias "sqlite3VdbeRecordCompareWithSkip" ( _
    ByVal nKey As SQLITE_C_INT, _
    ByVal pKey As Const Any Ptr, _
    ByVal pRecordArgument As Any Ptr, _
    ByVal skipFirstField As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pRecordArgument = 0 OrElse pKey = 0 OrElse nKey <= 0 Then Return 0
    Dim pRecord As sqlite3VdbeUnpackedRecord Ptr = _
        CPtr(sqlite3VdbeUnpackedRecord Ptr, pRecordArgument)
    If pRecord->pKeyInfo = 0 OrElse pRecord->aMem = 0 Then
        pRecord->errCode = SQLITE_CORRUPT
        Return 0
    End If
    Dim pKeyInfo As sqlite3VdbeKeyInfoPrefix Ptr = _
        CPtr(sqlite3VdbeKeyInfoPrefix Ptr, pRecord->pKeyInfo)
    If pRecord->nField > pKeyInfo->nAllField OrElse pKeyInfo->nKeyField = 0 Then
        pRecord->errCode = SQLITE_CORRUPT
        Return 0
    End If
    If pRecord->nField = 0 OrElse (skipFirstField <> 0 AndAlso pRecord->nField < 2) Then
        pRecord->eqSeen = 1
        Return pRecord->default_rc
    End If
    pRecord->errCode = SQLITE_OK

    Dim zKey As Const UByte Ptr = CPtr(Const UByte Ptr, pKey)
    Dim headerOffset As Long = 0
    Dim headerSize As u32 = 0
    If sqlite3VdbeRecordReadVarint32(zKey, nKey, headerOffset, headerSize) = 0 OrElse _
       headerSize < CUInt(headerOffset) OrElse headerSize > CUInt(nKey) Then
        pRecord->errCode = SQLITE_CORRUPT
        Return 0
    End If

    Dim dataOffset As Long = CLng(headerSize)
    Dim fieldIndex As Long = 0
    If skipFirstField <> 0 Then
        Dim ignoredSerialType As u32 = 0
        If sqlite3VdbeRecordReadVarint32(zKey, CLng(headerSize), headerOffset, ignoredSerialType) = 0 Then
            pRecord->errCode = SQLITE_CORRUPT
            Return 0
        End If
        Dim skippedBytes As u32 = sqlite3VdbeSerialTypeLen(ignoredSerialType)
        If skippedBytes > CULng(nKey - dataOffset) Then
            pRecord->errCode = SQLITE_CORRUPT
            Return 0
        End If
        dataOffset += skippedBytes
        fieldIndex = 1
    End If

    While fieldIndex < pRecord->nField
        If headerOffset >= headerSize OrElse dataOffset > nKey Then
            pRecord->errCode = SQLITE_CORRUPT
            Return 0
        End If
        Dim serialType As u32 = 0
        If sqlite3VdbeRecordReadVarint32(zKey, CLng(headerSize), headerOffset, serialType) = 0 Then
            pRecord->errCode = SQLITE_CORRUPT
            Return 0
        End If
        Dim payloadLength As u32 = sqlite3VdbeSerialTypeLen(serialType)
        If payloadLength > CULng(nKey - dataOffset) Then
            pRecord->errCode = SQLITE_CORRUPT
            Return 0
        End If

        Dim pRight As SqliteVdbeMem Ptr = @pRecord->aMem[fieldIndex]
        Dim rightFlags As UShort = pRight->flags
        Dim comparison As SQLITE_C_INT = 0
        If serialType = 11 Then
            If (rightFlags And (MEM_INT Or MEM_INTREAL Or MEM_REAL Or MEM_NULL)) <> 0 Then
                comparison = 1
            Else
                comparison = -1
            End If
        Else
            Dim leftValue As SqliteVdbeMem
            sqlite3VdbeMemInit(@leftValue, pKeyInfo->db, MEM_NULL)
            leftValue.enc = pKeyInfo->enc
            sqlite3VdbeSerialGet(zKey + dataOffset, serialType, @leftValue)
            Dim pCollation As Any Ptr = 0
            If (rightFlags And MEM_STR) <> 0 AndAlso fieldIndex < pKeyInfo->nAllField Then
                Dim pCollations As Any Ptr Ptr = CPtr(Any Ptr Ptr, @pKeyInfo->aColl(0))
                pCollation = pCollations[fieldIndex]
            End If
            comparison = sqlite3MemCompare(@leftValue, pRight, pCollation)
            If pKeyInfo->db <> 0 AndAlso pKeyInfo->db->mallocFailed <> 0 Then
                pRecord->errCode = SQLITE_NOMEM
                Return 0
            End If
        End If

        If comparison <> 0 Then
            Dim sortFlags As UByte = 0
            If pKeyInfo->aSortFlags <> 0 AndAlso fieldIndex < pKeyInfo->nAllField Then
                sortFlags = pKeyInfo->aSortFlags[fieldIndex]
            End If
            If sortFlags <> 0 Then
                Dim shouldInvert As Long
                If (sortFlags And KEYINFO_ORDER_BIGNULL) = 0 Then
                    shouldInvert = -1
                Else
                    Dim leftIsNull As Long = 0
                    If serialType = 0 OrElse (rightFlags And MEM_NULL) <> 0 Then leftIsNull = 1
                    Dim descending As Long = 0
                    If (sortFlags And KEYINFO_ORDER_DESC) <> 0 Then descending = 1
                    shouldInvert = CInt(descending <> leftIsNull)
                End If
                If shouldInvert <> 0 Then comparison = -comparison
            End If
            Return comparison
        End If

        fieldIndex += 1
        If fieldIndex >= pRecord->nField Then Exit While
        dataOffset += payloadLength
    Wend

    pRecord->eqSeen = 1
    Return pRecord->default_rc
End Function

Function sqlite3VdbeRecordCompare CDecl Alias "sqlite3VdbeRecordCompare" ( _
    ByVal nKey As SQLITE_C_INT, _
    ByVal pKey As Const Any Ptr, _
    ByVal pRecord As Any Ptr _
) As SQLITE_C_INT Export
    Return sqlite3VdbeRecordCompareWithSkip(nKey, pKey, pRecord, 0)
End Function

/' end of sqlite3_vdbe_compare.bas '/
