/'
    Project: SQLite FreeBASIC port

    File: sqlite3_bitvec.bas

    Purpose:

        Port SQLite's fixed-size sparse/dense bitmap from src/bitvec.c.

    Responsibilities:

        - Store small bitsets as byte arrays and larger sparse sets as hashes.
        - Promote dense hash tables into recursive sub-bitmaps.
        - Provide the bitmap operations used by the pager and B-tree.
        - Interpret the built-in test program used by sqlite3_test_control().
        - Print recursive bitmap contents for SQLITE_DEBUG diagnostics.

    This file intentionally does NOT contain:

        - Debug printing for bitmap contents.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_bitvec.bi"

Declare Function sqlite3MallocZero CDecl Alias "sqlite3MallocZero" ( _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Function sqlite3Malloc CDecl Alias "sqlite3Malloc" ( _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Declare Sub sqlite3_randomness CDecl Alias "sqlite3_randomness" ( _
    ByVal nByte As SQLITE_C_INT, _
    ByVal pBuffer As Any Ptr _
)

#ifdef SQLITE_DEBUG
Declare Sub sqlite3BitvecDebugPrintf CDecl Alias "sqlite3DebugPrintf" ( _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
#endif

Private Const BITVEC_SZ As Long = 512
Private Const BITVEC_USIZE As Long = _
    ((BITVEC_SZ - (3 * SizeOf(u32))) \ SizeOf(Any Ptr)) * SizeOf(Any Ptr)
Private Const BITVEC_NELEM As Long = BITVEC_USIZE \ SizeOf(UByte)
Private Const BITVEC_SZELEM As Long = 8
Private Const BITVEC_NBIT As Long = BITVEC_NELEM * BITVEC_SZELEM
Private Const BITVEC_NINT As Long = BITVEC_USIZE \ SizeOf(u32)
Private Const BITVEC_MXHASH As Long = BITVEC_NINT \ 2
Private Const BITVEC_NPTR As Long = BITVEC_USIZE \ SizeOf(Any Ptr)

Private Type BitvecData
    Union
        aBitmap(0 To BITVEC_NELEM - 1) As UByte
        aHash(0 To BITVEC_NINT - 1) As u32
        apSub(0 To BITVEC_NPTR - 1) As Any Ptr
    End Union
End Type

Private Type Bitvec
    iSize As u32
    nSet As u32
    iDivisor As u32
    u As BitvecData
End Type

Private Function sqlite3BitvecHash(ByVal i As u32) As u32
    Return i Mod BITVEC_NINT
End Function

Private Function sqlite3BitvecGetSub( _
    ByVal p As Bitvec Ptr, _
    ByVal index As u32 _
) As Bitvec Ptr
    Return CPtr(Bitvec Ptr, p->u.apSub(index))
End Function

Private Sub sqlite3BitvecSetSub( _
    ByVal p As Bitvec Ptr, _
    ByVal index As u32, _
    ByVal pSub As Bitvec Ptr _
)
    p->u.apSub(index) = pSub
End Sub

Function sqlite3BitvecCreate CDecl Alias "sqlite3BitvecCreate" ( _
    ByVal iSize As u32 _
) As Any Ptr Export

    ' The representation depends on the pointer-aligned union occupying
    ' the same 512-byte object size as SQLite's C implementation.
    If SizeOf(Bitvec) <> BITVEC_SZ Then Return 0

    Dim p As Bitvec Ptr = CPtr(Bitvec Ptr, sqlite3MallocZero(BITVEC_SZ))
    If p = 0 Then Return 0
    p->iSize = iSize
    Return p
End Function

Function sqlite3BitvecTestNotNull CDecl Alias "sqlite3BitvecTestNotNull" ( _
    ByVal pArgument As Any Ptr, _
    ByVal i As u32 _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return 0
    Dim p As Bitvec Ptr = CPtr(Bitvec Ptr, pArgument)
    i -= 1
    If i >= p->iSize Then Return 0

    While p->iDivisor <> 0
        Dim iSubIndex As u32 = i \ p->iDivisor
        i = i Mod p->iDivisor
        If iSubIndex >= BITVEC_NPTR Then Return 0
        p = sqlite3BitvecGetSub(p, iSubIndex)
        If p = 0 Then Return 0
    Wend

    If p->iSize <= BITVEC_NBIT Then
        Dim byteIndex As u32 = i \ BITVEC_SZELEM
        Dim bitIndex As u32 = i And (BITVEC_SZELEM - 1)
        If (p->u.aBitmap(byteIndex) And (1 Shl bitIndex)) <> 0 Then Return 1
        Return 0
    End If

    Dim h As u32 = sqlite3BitvecHash(i)
    i += 1
    While p->u.aHash(h) <> 0
        If p->u.aHash(h) = i Then Return 1
        h = (h + 1) Mod BITVEC_NINT
    Wend
    Return 0
End Function

Function sqlite3BitvecTest CDecl Alias "sqlite3BitvecTest" ( _
    ByVal p As Any Ptr, _
    ByVal i As u32 _
) As SQLITE_C_INT Export
    If p = 0 Then Return 0
    Return sqlite3BitvecTestNotNull(p, i)
End Function

Function sqlite3BitvecSet CDecl Alias "sqlite3BitvecSet" ( _
    ByVal pArgument As Any Ptr, _
    ByVal iValue As u32 _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return SQLITE_OK
    If iValue = 0 Then Return SQLITE_MISUSE

    Dim p As Bitvec Ptr = CPtr(Bitvec Ptr, pArgument)
    If iValue > p->iSize Then Return SQLITE_MISUSE
    Dim i As u32 = iValue - 1

    While p->iSize > BITVEC_NBIT AndAlso p->iDivisor <> 0
        Dim iSubIndex As u32 = i \ p->iDivisor
        i = i Mod p->iDivisor
        If iSubIndex >= BITVEC_NPTR Then Return SQLITE_MISUSE

        Dim pSub As Bitvec Ptr = sqlite3BitvecGetSub(p, iSubIndex)
        If pSub = 0 Then
            pSub = CPtr(Bitvec Ptr, sqlite3BitvecCreate(p->iDivisor))
            If pSub = 0 Then Return SQLITE_NOMEM
            sqlite3BitvecSetSub(p, iSubIndex, pSub)
        End If
        p = pSub
    Wend

    If p->iSize <= BITVEC_NBIT Then
        Dim byteIndex As u32 = i \ BITVEC_SZELEM
        Dim bitIndex As u32 = i And (BITVEC_SZELEM - 1)
        p->u.aBitmap(byteIndex) = p->u.aBitmap(byteIndex) Or CByte(1 Shl bitIndex)
        Return SQLITE_OK
    End If

    Dim h As u32 = sqlite3BitvecHash(i)
    i += 1

    If p->u.aHash(h) = 0 Then
        If p->nSet < BITVEC_NINT - 1 Then
            GoTo bitvec_set_end
        End If
        GoTo bitvec_set_rehash
    End If

    While p->u.aHash(h) <> 0
        If p->u.aHash(h) = i Then Return SQLITE_OK
        h += 1
        If h >= BITVEC_NINT Then h = 0
    Wend

bitvec_set_rehash:
    If p->nSet >= BITVEC_MXHASH Then
        Dim aiValues As u32 Ptr = CPtr(u32 Ptr, sqlite3Malloc(BITVEC_USIZE))
        If aiValues = 0 Then Return SQLITE_NOMEM

        For j As Long = 0 To BITVEC_NINT - 1
            aiValues[j] = p->u.aHash(j)
        Next
        For j As Long = 0 To BITVEC_NPTR - 1
            p->u.apSub(j) = 0
        Next

        p->iDivisor = p->iSize \ BITVEC_NPTR
        If (p->iSize Mod BITVEC_NPTR) <> 0 Then p->iDivisor += 1
        If p->iDivisor < BITVEC_NBIT Then p->iDivisor = BITVEC_NBIT

        Dim rc As SQLITE_C_INT = sqlite3BitvecSet(p, i)
        For j As Long = 0 To BITVEC_NINT - 1
            If aiValues[j] <> 0 Then rc = rc Or sqlite3BitvecSet(p, aiValues[j])
        Next
        sqlite3_free(aiValues)
        Return rc
    End If

bitvec_set_end:
    p->nSet += 1
    p->u.aHash(h) = i
    Return SQLITE_OK
End Function

Sub sqlite3BitvecClear CDecl Alias "sqlite3BitvecClear" ( _
    ByVal pArgument As Any Ptr, _
    ByVal iValue As u32, _
    ByVal pBuffer As Any Ptr _
) Export

    If pArgument = 0 OrElse iValue = 0 Then Exit Sub
    Dim p As Bitvec Ptr = CPtr(Bitvec Ptr, pArgument)
    If iValue > p->iSize Then Exit Sub
    Dim i As u32 = iValue - 1

    While p->iDivisor <> 0
        Dim iSubIndex As u32 = i \ p->iDivisor
        i = i Mod p->iDivisor
        If iSubIndex >= BITVEC_NPTR Then Exit Sub
        p = sqlite3BitvecGetSub(p, iSubIndex)
        If p = 0 Then Exit Sub
    Wend

    If p->iSize <= BITVEC_NBIT Then
        Dim byteIndex As u32 = i \ BITVEC_SZELEM
        Dim bitIndex As u32 = i And (BITVEC_SZELEM - 1)
        Dim mask As UByte = CByte(1 Shl bitIndex)
        p->u.aBitmap(byteIndex) = p->u.aBitmap(byteIndex) And Not mask
        Exit Sub
    End If

    If pBuffer = 0 Then Exit Sub
    Dim aiValues As u32 Ptr = CPtr(u32 Ptr, pBuffer)
    For j As Long = 0 To BITVEC_NINT - 1
        aiValues[j] = p->u.aHash(j)
        p->u.aHash(j) = 0
    Next
    p->nSet = 0

    For j As Long = 0 To BITVEC_NINT - 1
        If aiValues[j] <> 0 AndAlso aiValues[j] <> i + 1 Then
            Dim h As u32 = sqlite3BitvecHash(aiValues[j] - 1)
            p->nSet += 1
            While p->u.aHash(h) <> 0
                h += 1
                If h >= BITVEC_NINT Then h = 0
            Wend
            p->u.aHash(h) = aiValues[j]
        End If
    Next
End Sub

Sub sqlite3BitvecDestroy CDecl Alias "sqlite3BitvecDestroy" ( _
    ByVal pArgument As Any Ptr _
) Export

    If pArgument = 0 Then Exit Sub
    Dim p As Bitvec Ptr = CPtr(Bitvec Ptr, pArgument)
    If p->iDivisor <> 0 Then
        For i As Long = 0 To BITVEC_NPTR - 1
            sqlite3BitvecDestroy(sqlite3BitvecGetSub(p, i))
        Next
    End If
    sqlite3_free(p)
End Sub

Function sqlite3BitvecSize CDecl Alias "sqlite3BitvecSize" ( _
    ByVal pArgument As Any Ptr _
) As u32 Export

    If pArgument = 0 Then Return 0
    Dim p As Bitvec Ptr = CPtr(Bitvec Ptr, pArgument)
    Return p->iSize
End Function

#ifndef SQLITE_UNTESTABLE
Private Sub sqlite3BitvecBuiltinTestCleanup( _
    ByVal pTemporary As Any Ptr, _
    ByVal pReference As UByte Ptr, _
    ByVal pBitvec As Bitvec Ptr _
)
    sqlite3_free(pTemporary)
    sqlite3_free(pReference)
    sqlite3BitvecDestroy(pBitvec)
End Sub

Function sqlite3BitvecBuiltinTest CDecl Alias "sqlite3BitvecBuiltinTest" ( _
    ByVal size As SQLITE_C_INT, _
    ByVal pProgram As SQLITE_C_INT Ptr _
) As SQLITE_C_INT Export
    Dim pBitvec As Bitvec Ptr = 0
    Dim pReference As UByte Ptr = 0
    Dim pTemporary As Any Ptr = 0
    Dim result As SQLITE_C_INT = -1
    If pProgram = 0 Then Return SQLITE_MISUSE

    Dim bitvecSize As sqlite3_uint64
    If size <= 0 Then
        bitvecSize = Cast(sqlite3_uint64, 0) - Cast(sqlite3_int64, size)
        bitvecSize = (bitvecSize * 2) And &HFFFFFFFFULL
        pBitvec = CPtr(Bitvec Ptr, sqlite3BitvecCreate(CUInt(bitvecSize)))
        pReference = 0
    Else
        bitvecSize = CUInt(size)
        pBitvec = CPtr(Bitvec Ptr, sqlite3BitvecCreate(CUInt(size)))
        Dim referenceBytes As sqlite3_uint64 = _
            (7 + Cast(sqlite3_uint64, size)) \ 8 + 1
        pReference = CPtr(UByte Ptr, sqlite3MallocZero(referenceBytes))
    End If
    pTemporary = sqlite3Malloc(BITVEC_SZ)
    If pBitvec = 0 OrElse pTemporary = 0 OrElse _
       (pReference = 0 AndAlso size > 0) Then
        sqlite3BitvecBuiltinTestCleanup(pTemporary, pReference, pBitvec)
        Return result
    End If

    ' These calls verify that the public Bitvec routines accept a NULL object.
    sqlite3BitvecSet(0, 1)
    sqlite3BitvecClear(0, 1, pTemporary)

    If size = 0 AndAlso pProgram[0] <> 0 Then
        sqlite3BitvecBuiltinTestCleanup(pTemporary, pReference, pBitvec)
        Return SQLITE_MISUSE
    End If
    Dim pc As SQLITE_C_INT = 0
    Dim index As SQLITE_C_INT = 0
    While pProgram[pc] <> 0
        Dim opcode As SQLITE_C_INT = pProgram[pc]
        Dim nextWidth As SQLITE_C_INT
        If opcode >= 6 Then
            ' Opcodes 6 and 7 only print debug diagnostics in a C debug build.
            pc += 1
            Continue While
        End If

        Select Case opcode
        Case 1, 2, 5
            nextWidth = 4
            index = pProgram[pc + 2] - 1
            pProgram[pc + 2] += pProgram[pc + 3]
        Case Else
            nextWidth = 2
            sqlite3_randomness(SizeOf(index), @index)
        End Select

        pProgram[pc + 1] -= 1
        If pProgram[pc + 1] > 0 Then nextWidth = 0
        pc += nextWidth
        index = (index And &H7FFFFFFF) Mod size
        Dim bitNumber As SQLITE_C_INT = index + 1
        Dim byteIndex As SQLITE_C_INT = bitNumber \ 8
        Dim bitIndex As SQLITE_C_INT = bitNumber And 7
        Dim bitMask As UByte = CByte(1 Shl bitIndex)

        If (opcode And 1) <> 0 Then
            If pReference <> 0 Then _
                pReference[byteIndex] = pReference[byteIndex] Or bitMask
            If opcode <> 5 AndAlso sqlite3BitvecSet(pBitvec, bitNumber) <> SQLITE_OK Then
                sqlite3BitvecBuiltinTestCleanup(pTemporary, pReference, pBitvec)
                Return result
            End If
        Else
            If pReference <> 0 Then _
                pReference[byteIndex] = pReference[byteIndex] And Not bitMask
            sqlite3BitvecClear(pBitvec, bitNumber, pTemporary)
        End If
    Wend

    If pReference <> 0 Then
        result = sqlite3BitvecTest(0, 0) + _
                 sqlite3BitvecTest(pBitvec, CUInt(size) + 1) + _
                 sqlite3BitvecTest(pBitvec, 0) + _
                 CInt(sqlite3BitvecSize(pBitvec) - CUInt(size))
        For iBit As SQLITE_C_INT = 1 To size
            ' C's != operator produces 0 or 1; FreeBASIC True is -1.
            Dim expected As SQLITE_C_INT = 0
            If (pReference[iBit \ 8] And _
                CByte(1 Shl (iBit And 7))) <> 0 Then expected = 1
            If expected <> sqlite3BitvecTest(pBitvec, CUInt(iBit)) Then
                result = iBit
                Exit For
            End If
        Next
    Else
        result = SQLITE_OK
    End If

    sqlite3BitvecBuiltinTestCleanup(pTemporary, pReference, pBitvec)
    Return result
End Function
#endif

#ifdef SQLITE_DEBUG
Private Sub showBitvec( _
    ByVal pBitvec As Bitvec Ptr, _
    ByVal indentation As SQLITE_C_INT, _
    ByVal baseValue As u32 _
)
    If pBitvec = 0 Then
        sqlite3BitvecDebugPrintf(StrPtr(!"NULL\n"))
        Exit Sub
    End If

    sqlite3BitvecDebugPrintf( _
        StrPtr("Bitvec %p iSize=%u"), pBitvec, pBitvec->iSize)
    If pBitvec->iSize <= BITVEC_NBIT Then
        sqlite3BitvecDebugPrintf(StrPtr(!" bitmap\n"))
        sqlite3BitvecDebugPrintf(StrPtr("%*s   bits:"), indentation, StrPtr(""))
        For bitIndex As SQLITE_C_INT = 1 To BITVEC_NBIT
            If sqlite3BitvecTest(pBitvec, CUInt(bitIndex)) <> 0 Then
                Dim displayedBit As u32 = baseValue + CUInt(bitIndex)
                sqlite3BitvecDebugPrintf(StrPtr(" %u"), displayedBit)
            End If
        Next
        sqlite3BitvecDebugPrintf(StrPtr(!"\n"))
    ElseIf pBitvec->iDivisor = 0 Then
        sqlite3BitvecDebugPrintf(StrPtr(!" hash with %u entries\n"), pBitvec->nSet)
        sqlite3BitvecDebugPrintf(StrPtr("%*s   bits:"), indentation, StrPtr(""))
        For hashIndex As SQLITE_C_INT = 0 To BITVEC_NINT - 1
            If pBitvec->u.aHash(hashIndex) <> 0 Then
                Dim displayedBit As u32 = baseValue + pBitvec->u.aHash(hashIndex)
                sqlite3BitvecDebugPrintf(StrPtr(" %u"), displayedBit)
            End If
        Next
        sqlite3BitvecDebugPrintf(StrPtr(!"\n"))
    Else
        sqlite3BitvecDebugPrintf( _
            StrPtr(!" sub-bitvec with iDivisor=%u\n"), pBitvec->iDivisor)
        For childIndex As SQLITE_C_INT = 0 To BITVEC_NPTR - 1
            Dim pChild As Bitvec Ptr = CPtr(Bitvec Ptr, pBitvec->u.apSub(childIndex))
            If pChild = 0 Then Continue For
            sqlite3BitvecDebugPrintf( _
                StrPtr("%*s   apSub[%d]="), indentation, StrPtr(""), childIndex)
            Dim childBase As u32 = baseValue + CUInt(childIndex) * pBitvec->iDivisor
            showBitvec(pChild, indentation + 4, childBase)
        Next
    End If
End Sub

Sub sqlite3ShowBitvec CDecl Alias "sqlite3ShowBitvec" ( _
    ByVal pBitvecArgument As Any Ptr _
)
    showBitvec(CPtr(Bitvec Ptr, pBitvecArgument), 0, 0)
End Sub
#endif

/' end of sqlite3_bitvec.bas '/
