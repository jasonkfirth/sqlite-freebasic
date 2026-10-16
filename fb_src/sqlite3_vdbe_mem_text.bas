/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_mem_text.bas

    Purpose:

        Convert VDBE numeric and text values into requested string encodings.

    Responsibilities:

        - Render integer and real Mem values as SQLite text.
        - Translate UTF-8 and UTF-16 Mem strings while preserving ownership.
        - Provide value text and byte-count helpers used by the public API.

    This file intentionally does NOT contain:

        - Text collation, SQL printf formatting, or statement execution.
'/

#lang "fb"
#include once "sqlite3_vdbe_mem_text.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_numeric.bi"
#include once "sqlite3_fp.bi"
#include once "sqlite3_rowset.bi"
#include once "sqlite3_vdbe_affinity.bi"

Declare Function sqlite3AppendOneUtf8Character CDecl Alias "sqlite3AppendOneUtf8Character" ( _
    ByVal zOut As UByte Ptr, _
    ByVal codepoint As u32 _
) As SQLITE_C_INT

Private Function sqlite3VdbeTextIsRowSet(ByVal pMem As SqliteVdbeMem Ptr) As Long
    If pMem = 0 OrElse (pMem->flags And (MEM_BLOB Or MEM_DYN)) <> (MEM_BLOB Or MEM_DYN) Then
        Return 0
    End If
    If pMem->xDel = @sqlite3RowSetDelete Then Return -1
    Return 0
End Function

Private Function sqlite3VdbeUtf8InitialBits(ByVal firstByte As UByte) As u32
    If firstByte <= &HDF Then Return firstByte And &H1F
    If firstByte <= &HEF Then Return firstByte And &H0F
    If firstByte <= &HF7 Then Return firstByte And &H07
    If firstByte <= &HFB Then Return firstByte And &H03
    If firstByte <= &HFD Then Return firstByte And &H01
    Return 0
End Function

Private Function sqlite3VdbeUtf8ReadBounded( _
    ByVal z As Const UByte Ptr, _
    ByVal remainingBytes As Long, _
    ByRef codepoint As u32 _
) As Long
    If z = 0 OrElse remainingBytes <= 0 Then
        codepoint = 0
        Return 0
    End If
    Dim used As Long = 1
    codepoint = z[0]
    If codepoint >= &HC0 Then
        codepoint = sqlite3VdbeUtf8InitialBits(z[0])
        While used < remainingBytes AndAlso (z[used] And &HC0) = &H80
            codepoint = (codepoint Shl 6) + (z[used] And &H3F)
            used += 1
        Wend
        If codepoint < &H80 OrElse (codepoint And &HFFFFF800) = &HD800 Then
            codepoint = &HFFFD
        End If
    End If
    Return used
End Function

Private Sub sqlite3VdbeUtf16Write( _
    ByVal zOut As UByte Ptr, _
    ByRef offset As Long, _
    ByVal codepoint As u32, _
    ByVal eEncoding As u8 _
)
    ' UTF-16 surrogate pairs are emitted in the same byte order as the
    ' requested encoding, including SQLite's treatment of unusual codepoints.
    If codepoint <= &HFFFF Then
        If eEncoding = SQLITE_UTF16LE Then
            zOut[offset] = CUByte(codepoint And &HFF)
            zOut[offset + 1] = CUByte((codepoint Shr 8) And &HFF)
        Else
            zOut[offset] = CUByte((codepoint Shr 8) And &HFF)
            zOut[offset + 1] = CUByte(codepoint And &HFF)
        End If
        offset += 2
        Exit Sub
    End If

    Dim adjusted As u32 = codepoint - &H10000
    If eEncoding = SQLITE_UTF16LE Then
        zOut[offset] = CUByte(((codepoint Shr 10) And &H3F) + ((adjusted Shr 10) And &HC0))
        zOut[offset + 1] = CUByte(&HD8 + ((adjusted Shr 18) And &H03))
        zOut[offset + 2] = CUByte(codepoint And &HFF)
        zOut[offset + 3] = CUByte(&HDC + ((codepoint Shr 8) And &H03))
    Else
        zOut[offset] = CUByte(&HD8 + ((adjusted Shr 18) And &H03))
        zOut[offset + 1] = CUByte(((codepoint Shr 10) And &H3F) + ((adjusted Shr 10) And &HC0))
        zOut[offset + 2] = CUByte(&HDC + ((codepoint Shr 8) And &H03))
        zOut[offset + 3] = CUByte(codepoint And &HFF)
    End If
    offset += 4
End Sub

Function sqlite3VdbeMemTranslate CDecl Alias "sqlite3VdbeMemTranslate" ( _
    ByVal pArgument As Any Ptr, _
    ByVal desiredEncoding As u8 _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return SQLITE_MISUSE
    If desiredEncoding <> SQLITE_UTF8 AndAlso desiredEncoding <> SQLITE_UTF16LE AndAlso _
       desiredEncoding <> SQLITE_UTF16BE Then Return SQLITE_MISUSE
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If (pMem->flags And MEM_STR) = 0 OrElse pMem->enc = desiredEncoding Then Return SQLITE_MISUSE
    If pMem->z = 0 OrElse pMem->n < 0 Then Return SQLITE_MISUSE

    If pMem->enc <> SQLITE_UTF8 AndAlso desiredEncoding <> SQLITE_UTF8 Then
        ' Swapping between UTF-16 byte orders does not change the byte count.
        Dim rc As SQLITE_C_INT = sqlite3VdbeMemMakeWriteable(pMem)
        If rc <> SQLITE_OK Then Return rc
        Dim limit As Long = pMem->n And Not 1
        Dim offset As Long = 0
        While offset < limit
            Dim firstByte As UByte = pMem->z[offset]
            pMem->z[offset] = pMem->z[offset + 1]
            pMem->z[offset + 1] = firstByte
            offset += 2
        Wend
        pMem->enc = desiredEncoding
        Return SQLITE_OK
    End If

    Dim inputLength As Long = pMem->n
    If desiredEncoding = SQLITE_UTF8 Then
        inputLength = inputLength And Not 1
        pMem->n = inputLength
    End If
    Dim outputCapacity As ULongInt
    If desiredEncoding = SQLITE_UTF8 Then
        outputCapacity = CULngInt(inputLength) * 2 + 1
    Else
        outputCapacity = CULngInt(inputLength) * 2 + 2
    End If
    ' Allocate a worst-case buffer before replacing the source bytes, so an
    ' OOM does not discard the current text allocation.
    Dim zOutput As UByte Ptr = CPtr(UByte Ptr, sqlite3DbMallocRaw(pMem->db, outputCapacity))
    If zOutput = 0 Then Return SQLITE_NOMEM
    Dim zInput As Const UByte Ptr = pMem->z
    Dim inputOffset As Long = 0
    Dim outputOffset As Long = 0
    If pMem->enc = SQLITE_UTF8 Then
        While inputOffset < inputLength
            Dim codepoint As u32
            Dim used As Long = sqlite3VdbeUtf8ReadBounded( _
                zInput + inputOffset, inputLength - inputOffset, codepoint)
            If used <= 0 Then used = 1
            inputOffset += used
            sqlite3VdbeUtf16Write(zOutput, outputOffset, codepoint, desiredEncoding)
        Wend
        pMem->n = outputOffset
        zOutput[outputOffset] = 0
        outputOffset += 1
    Else
        Dim inputLimit As Long = inputLength
        If pMem->enc = SQLITE_UTF16LE Then
            While inputOffset < inputLimit
                Dim codepoint As u32 = zInput[inputOffset]
                codepoint += CULng(zInput[inputOffset + 1]) Shl 8
                inputOffset += 2
                If codepoint >= &HD800 AndAlso codepoint < &HE000 AndAlso inputOffset < inputLimit Then
                    Dim second As u32 = zInput[inputOffset]
                    second += CULng(zInput[inputOffset + 1]) Shl 8
                    inputOffset += 2
                    codepoint = (second And &H03FF) + ((codepoint And &H003F) Shl 10) + _
                                (((codepoint And &H03C0) + &H0040) Shl 10)
                End If
                outputOffset += sqlite3AppendOneUtf8Character(zOutput + outputOffset, codepoint)
            Wend
        Else
            While inputOffset < inputLimit
                Dim codepoint As u32 = CULng(zInput[inputOffset]) Shl 8
                codepoint += zInput[inputOffset + 1]
                inputOffset += 2
                If codepoint >= &HD800 AndAlso codepoint < &HE000 AndAlso inputOffset < inputLimit Then
                    Dim second As u32 = CULng(zInput[inputOffset]) Shl 8
                    second += zInput[inputOffset + 1]
                    inputOffset += 2
                    codepoint = (second And &H03FF) + ((codepoint And &H003F) Shl 10) + _
                                (((codepoint And &H03C0) + &H0040) Shl 10)
                End If
                outputOffset += sqlite3AppendOneUtf8Character(zOutput + outputOffset, codepoint)
            Wend
        End If
        pMem->n = outputOffset
    End If

    zOutput[outputOffset] = 0
    Dim newFlags As UShort = MEM_STR Or MEM_TERM Or (pMem->flags And (MEM_AFF_MASK Or MEM_SUBTYPE))
    sqlite3VdbeMemRelease(pMem)
    pMem->flags = newFlags
    pMem->enc = desiredEncoding
    pMem->z = zOutput
    pMem->zMalloc = zOutput
    pMem->szMalloc = sqlite3DbMallocSize(pMem->db, zOutput)
    pMem->xDel = 0
    Return SQLITE_OK
End Function

Function sqlite3VdbeChangeEncoding CDecl Alias "sqlite3VdbeChangeEncoding" ( _
    ByVal pArgument As Any Ptr, _
    ByVal desiredEncoding As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return SQLITE_MISUSE
    If desiredEncoding <> SQLITE_UTF8 AndAlso desiredEncoding <> SQLITE_UTF16LE AndAlso _
       desiredEncoding <> SQLITE_UTF16BE Then Return SQLITE_MISUSE
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If (pMem->flags And MEM_STR) = 0 OrElse pMem->enc = desiredEncoding Then
        pMem->enc = CUByte(desiredEncoding)
        Return SQLITE_OK
    End If
    Return sqlite3VdbeMemTranslate(pMem, CUByte(desiredEncoding))
End Function

Function sqlite3VdbeMemStringify CDecl Alias "sqlite3VdbeMemStringify" ( _
    ByVal pArgument As Any Ptr, _
    ByVal eEncoding As u8, _
    ByVal forceType As u8 _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return SQLITE_MISUSE
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If eEncoding <> SQLITE_UTF8 AndAlso eEncoding <> SQLITE_UTF16LE AndAlso _
       eEncoding <> SQLITE_UTF16BE Then Return SQLITE_MISUSE
    If sqlite3VdbeTextIsRowSet(pMem) <> 0 OrElse (pMem->flags And MEM_AGG) <> 0 OrElse _
       (pMem->flags And MEM_ZERO) <> 0 OrElse _
       (pMem->flags And (MEM_STR Or MEM_BLOB)) <> 0 OrElse _
       (pMem->flags And (MEM_INT Or MEM_REAL Or MEM_INTREAL)) = 0 Then
        Return SQLITE_MISUSE
    End If

    Dim rc As SQLITE_C_INT = sqlite3VdbeMemClearAndResize(pMem, 32)
    If rc <> SQLITE_OK Then
        pMem->enc = 0
        Return rc
    End If

    If (pMem->flags And (MEM_INT Or MEM_INTREAL)) <> 0 Then
        pMem->n = sqlite3Int64ToText(pMem->u.i, CPtr(ZString Ptr, pMem->z))
        If (pMem->flags And MEM_INTREAL) <> 0 Then
            pMem->z[pMem->n] = Asc(".")
            pMem->z[pMem->n + 1] = Asc("0")
            pMem->z[pMem->n + 2] = 0
            pMem->n += 2
        End If
    Else
        ' nFpDigit controls round-trip precision for SQL rendering. A detached
        ' sqlite3_value has no connection and uses SQLite's default of 17.
        Dim significantDigits As SQLITE_C_INT = 17
        If pMem->db <> 0 Then significantDigits = pMem->db->nFpDigit
        rc = fbFpFormatDouble(pMem->u.r, significantDigits, pMem->z, 32)
        If rc < 0 Then Return -rc
        ' Keep integral REAL values distinct from INTEGER values in text form.
        Dim hasDecimalMarker As SQLITE_C_INT = 0
        Dim isPlainNumber As SQLITE_C_INT = CInt(rc > 0)
        For characterIndex As SQLITE_C_INT = 0 To rc - 1
            Dim character As UByte = pMem->z[characterIndex]
            If character = Asc(".") OrElse character = Asc("e") OrElse _
               character = Asc("E") Then
                hasDecimalMarker = 1
                Exit For
            End If
            If (character < Asc("0") OrElse character > Asc("9")) AndAlso _
               Not (characterIndex = 0 AndAlso _
                    (character = Asc("-") OrElse character = Asc("+"))) Then
                isPlainNumber = 0
            End If
        Next
        If hasDecimalMarker = 0 AndAlso isPlainNumber <> 0 AndAlso rc <= 29 Then
            pMem->z[rc] = Asc(".")
            pMem->z[rc + 1] = Asc("0")
            pMem->z[rc + 2] = 0
            rc += 2
        End If
        pMem->n = rc
    End If

    pMem->enc = SQLITE_UTF8
    pMem->flags = pMem->flags Or MEM_STR Or MEM_TERM
    If forceType <> 0 Then pMem->flags = pMem->flags And Not (MEM_INT Or MEM_REAL Or MEM_INTREAL)
    Return sqlite3VdbeChangeEncoding(pMem, eEncoding)
End Function

Function sqlite3VdbeMemCast CDecl Alias "sqlite3VdbeMemCast" ( _
    ByVal pArgument As Any Ptr, _
    ByVal affinity As u8, _
    ByVal eEncoding As u8 _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return SQLITE_MISUSE
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If (pMem->flags And MEM_NULL) <> 0 Then Return SQLITE_OK
    If sqlite3VdbeTextIsRowSet(pMem) <> 0 OrElse (pMem->flags And MEM_AGG) <> 0 Then
        Return SQLITE_MISUSE
    End If

    Select Case affinity
    Case SQLITE_AFF_BLOB
        If (pMem->flags And MEM_BLOB) = 0 Then
            sqlite3ValueApplyAffinity(pMem, SQLITE_AFF_TEXT, eEncoding)
            If (pMem->flags And MEM_STR) <> 0 Then
                pMem->flags = (pMem->flags And Not (MEM_TYPE_MASK Or MEM_ZERO)) Or MEM_BLOB
            End If
        Else
            pMem->flags = pMem->flags And Not (MEM_TYPE_MASK And Not MEM_BLOB)
        End If
    Case SQLITE_AFF_NUMERIC
        Return sqlite3VdbeMemNumerify(pMem)
    Case SQLITE_AFF_INTEGER
        Return sqlite3VdbeMemIntegerify(pMem)
    Case SQLITE_AFF_REAL
        Return sqlite3VdbeMemRealify(pMem)
    Case SQLITE_AFF_TEXT
        pMem->flags = pMem->flags Or ((pMem->flags And MEM_BLOB) Shr 3)
        sqlite3ValueApplyAffinity(pMem, SQLITE_AFF_TEXT, eEncoding)
        pMem->flags = pMem->flags And Not (MEM_INT Or MEM_REAL Or MEM_INTREAL Or MEM_BLOB Or MEM_ZERO)
        If eEncoding = SQLITE_UTF16 Then eEncoding = SQLITE_UTF16NATIVE
        If eEncoding <> SQLITE_UTF8 Then pMem->n = pMem->n And Not 1
        Dim rc As SQLITE_C_INT = sqlite3VdbeChangeEncoding(pMem, eEncoding)
        If rc <> SQLITE_OK Then Return rc
        Return sqlite3VdbeMemNulTerminate(pMem)
    Case Else
        Return SQLITE_MISUSE
    End Select
    Return SQLITE_OK
End Function

Private Function sqlite3VdbeValueToText( _
    ByVal pMem As SqliteVdbeMem Ptr, _
    ByVal eEncoding As u8 _
) As UByte Ptr
    If pMem = 0 OrElse sqlite3VdbeTextIsRowSet(pMem) <> 0 OrElse _
       (pMem->flags And MEM_AGG) <> 0 Then Return 0
    If (pMem->flags And (MEM_STR Or MEM_BLOB)) <> 0 Then
        If sqlite3VdbeMemExpandBlob(pMem) <> SQLITE_OK Then Return 0
        pMem->flags = pMem->flags Or MEM_STR
        If pMem->enc <> eEncoding Then
            If sqlite3VdbeChangeEncoding(pMem, eEncoding) <> SQLITE_OK Then Return 0
        End If
        If sqlite3VdbeMemNulTerminate(pMem) <> SQLITE_OK Then Return 0
    Else
        If (pMem->flags And (MEM_INT Or MEM_REAL Or MEM_INTREAL)) = 0 Then Return 0
        If sqlite3VdbeMemStringify(pMem, eEncoding, 0) <> SQLITE_OK Then Return 0
    End If
    If pMem->enc <> eEncoding Then Return 0
    Return pMem->z
End Function

Function sqlite3ValueText CDecl Alias "sqlite3ValueText" ( _
    ByVal pArgument As Any Ptr, _
    ByVal eEncoding As u8 _
) As Any Ptr Export

    If pArgument = 0 Then Return 0
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If eEncoding <> SQLITE_UTF8 AndAlso eEncoding <> SQLITE_UTF16LE AndAlso _
       eEncoding <> SQLITE_UTF16BE Then Return 0
    If (pMem->flags And (MEM_STR Or MEM_TERM)) = (MEM_STR Or MEM_TERM) AndAlso _
       pMem->enc = eEncoding Then Return pMem->z
    If (pMem->flags And MEM_NULL) <> 0 Then Return 0
    Return sqlite3VdbeValueToText(pMem, eEncoding)
End Function

Function sqlite3ValueBytes CDecl Alias "sqlite3ValueBytes" ( _
    ByVal pArgument As Any Ptr, _
    ByVal eEncoding As u8 _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return 0
    If eEncoding = SQLITE_UTF16 Then eEncoding = SQLITE_UTF16NATIVE
    If eEncoding <> SQLITE_UTF8 AndAlso eEncoding <> SQLITE_UTF16LE AndAlso _
       eEncoding <> SQLITE_UTF16BE Then Return 0
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If (pMem->flags And MEM_STR) <> 0 AndAlso pMem->enc = eEncoding Then Return pMem->n
    If (pMem->flags And MEM_STR) <> 0 AndAlso eEncoding <> SQLITE_UTF8 AndAlso _
       pMem->enc <> SQLITE_UTF8 Then Return pMem->n
    If (pMem->flags And MEM_BLOB) <> 0 Then
        If (pMem->flags And MEM_ZERO) <> 0 Then
            Dim totalBytes As LongInt = CLngInt(pMem->n) + CLngInt(pMem->u.nZero)
            If totalBytes > &H7FFFFFFF Then Return &H7FFFFFFF
            Return CLng(totalBytes)
        End If
        Return pMem->n
    End If
    If sqlite3VdbeValueToText(pMem, eEncoding) = 0 Then Return 0
    Return pMem->n
End Function

/' end of sqlite3_vdbe_mem_text.bas '/
