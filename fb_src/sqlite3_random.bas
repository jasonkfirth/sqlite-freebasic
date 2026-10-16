/'
    Project: SQLite FreeBASIC port

    File: sqlite3_random.bas

    Purpose:

        Provide SQLite's shared ChaCha20-based random byte generator.

    Responsibilities:

        - Seed the generator from the registered VFS randomness method.
        - Serialize updates with SQLite's static PRNG mutex.
        - Preserve unconsumed bytes between sqlite3_randomness() calls.
        - Reset the generator when called with an empty or invalid request.
        - Save and restore generator state for sqlite3_test_control().

    This file intentionally does NOT contain:

        - Operating-system entropy collection outside the VFS interface.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_mutex.bi"
#include once "sqlite3_vfs.bi"

Declare Function sqlite3_initialize CDecl Alias "sqlite3_initialize" () As SQLITE_C_INT

Private Type SqlitePrngType
    s(0 To 15) As u32
    out(0 To 63) As UByte
    n As UByte
End Type

Private Dim Shared sqlite3Prng As SqlitePrngType
#ifndef SQLITE_UNTESTABLE
Private Dim Shared sqlite3SavedPrng As SqlitePrngType
#endif

Private Function sqlite3PrngAdd32(ByVal leftWord As u32, ByVal rightWord As u32) As u32
    Return CULng((CULngInt(leftWord) + CULngInt(rightWord)) And &HFFFFFFFF)
End Function

Private Function sqlite3PrngRotateLeft32(ByVal value As u32, ByVal amount As SQLITE_C_INT) As u32
    Return (value Shl amount) Or (value Shr (32 - amount))
End Function

Private Sub sqlite3PrngQuarterRound( _
    ByRef a As u32, _
    ByRef b As u32, _
    ByRef c As u32, _
    ByRef d As u32 _
)
    a = sqlite3PrngAdd32(a, b)
    d = sqlite3PrngRotateLeft32(d Xor a, 16)
    c = sqlite3PrngAdd32(c, d)
    b = sqlite3PrngRotateLeft32(b Xor c, 12)
    a = sqlite3PrngAdd32(a, b)
    d = sqlite3PrngRotateLeft32(d Xor a, 8)
    c = sqlite3PrngAdd32(c, d)
    b = sqlite3PrngRotateLeft32(b Xor c, 7)
End Sub

Private Sub chacha_block(ByVal pOutput As UByte Ptr, ByVal pInput As Const u32 Ptr)
    If pOutput = 0 OrElse pInput = 0 Then Exit Sub
    Dim x(0 To 15) As u32
    For iWord As SQLITE_C_INT = 0 To 15
        x(iWord) = pInput[iWord]
    Next

    For roundIndex As SQLITE_C_INT = 0 To 9
        sqlite3PrngQuarterRound(x(0), x(4), x(8), x(12))
        sqlite3PrngQuarterRound(x(1), x(5), x(9), x(13))
        sqlite3PrngQuarterRound(x(2), x(6), x(10), x(14))
        sqlite3PrngQuarterRound(x(3), x(7), x(11), x(15))
        sqlite3PrngQuarterRound(x(0), x(5), x(10), x(15))
        sqlite3PrngQuarterRound(x(1), x(6), x(11), x(12))
        sqlite3PrngQuarterRound(x(2), x(7), x(8), x(13))
        sqlite3PrngQuarterRound(x(3), x(4), x(9), x(14))
    Next

    For iWord As SQLITE_C_INT = 0 To 15
        x(iWord) = sqlite3PrngAdd32(x(iWord), pInput[iWord])
        CPtr(u32 Ptr, pOutput)[iWord] = x(iWord)
    Next
End Sub

Sub sqlite3_randomness CDecl Alias "sqlite3_randomness" ( _
    ByVal amount As SQLITE_C_INT, _
    ByVal pBuffer As Any Ptr _
) Export

#ifndef SQLITE_OMIT_AUTOINIT
    If sqlite3_initialize() <> SQLITE_OK Then Return
#endif

    Dim pMutex As Any Ptr = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_PRNG)
    sqlite3_mutex_enter(pMutex)
    If amount <= 0 OrElse pBuffer = 0 Then
        sqlite3Prng.s(0) = 0
        sqlite3_mutex_leave(pMutex)
        Return
    End If

    If sqlite3Prng.s(0) = 0 Then
        Dim pVfs As sqlite3_vfs Ptr = sqlite3_vfs_find(0)
        sqlite3Prng.s(0) = &H61707865
        sqlite3Prng.s(1) = &H3320646E
        sqlite3Prng.s(2) = &H79622D32
        sqlite3Prng.s(3) = &H6B206574
        If pVfs = 0 Then
            For iWord As SQLITE_C_INT = 4 To 14
                sqlite3Prng.s(iWord) = 0
            Next
        Else
            sqlite3OsRandomness(pVfs, 44, CPtr(ZString Ptr, @sqlite3Prng.s(4)))
        End If
        sqlite3Prng.s(15) = sqlite3Prng.s(12)
        sqlite3Prng.s(12) = 0
        sqlite3Prng.n = 0
    End If

    Dim remaining As SQLITE_C_INT = amount
    Dim pOutput As UByte Ptr = CPtr(UByte Ptr, pBuffer)
    While remaining > 0
        If remaining <= sqlite3Prng.n Then
            Dim startOffset As SQLITE_C_INT = sqlite3Prng.n - remaining
            For iByte As SQLITE_C_INT = 0 To remaining - 1
                pOutput[iByte] = sqlite3Prng.out(startOffset + iByte)
            Next
            sqlite3Prng.n -= CByte(remaining)
            Exit While
        End If

        If sqlite3Prng.n > 0 Then
            For iByte As SQLITE_C_INT = 0 To sqlite3Prng.n - 1
                pOutput[iByte] = sqlite3Prng.out(iByte)
            Next
            remaining -= sqlite3Prng.n
            pOutput += sqlite3Prng.n
        End If

        sqlite3Prng.s(12) = sqlite3PrngAdd32(sqlite3Prng.s(12), 1)
        chacha_block(@sqlite3Prng.out(0), @sqlite3Prng.s(0))
        sqlite3Prng.n = 64
    Wend
    sqlite3_mutex_leave(pMutex)
End Sub

#ifndef SQLITE_UNTESTABLE
Sub sqlite3PrngSaveState CDecl Alias "sqlite3PrngSaveState" () Export
    Dim pMutex As Any Ptr = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_PRNG)
    sqlite3_mutex_enter(pMutex)
    For iWord As SQLITE_C_INT = 0 To 15
        sqlite3SavedPrng.s(iWord) = sqlite3Prng.s(iWord)
    Next
    For iByte As SQLITE_C_INT = 0 To 63
        sqlite3SavedPrng.out(iByte) = sqlite3Prng.out(iByte)
    Next
    sqlite3SavedPrng.n = sqlite3Prng.n
    sqlite3_mutex_leave(pMutex)
End Sub

Sub sqlite3PrngRestoreState CDecl Alias "sqlite3PrngRestoreState" () Export
    Dim pMutex As Any Ptr = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_PRNG)
    sqlite3_mutex_enter(pMutex)
    For iWord As SQLITE_C_INT = 0 To 15
        sqlite3Prng.s(iWord) = sqlite3SavedPrng.s(iWord)
    Next
    For iByte As SQLITE_C_INT = 0 To 63
        sqlite3Prng.out(iByte) = sqlite3SavedPrng.out(iByte)
    Next
    sqlite3Prng.n = sqlite3SavedPrng.n
    sqlite3_mutex_leave(pMutex)
End Sub
#endif

/' end of sqlite3_random.bas '/
