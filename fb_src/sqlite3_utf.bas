/'
    Project: SQLite FreeBASIC port

    File: sqlite3_utf.bas

    Purpose:

        Port UTF decoding, length, and conversion helpers from src/utf.c.

    Responsibilities:

        - Decode a UTF-8 code point and advance a caller-owned pointer.
        - Encode one code point into a caller-provided UTF-8 buffer.
        - Count UTF-8 characters and decode bounded input.
        - Count bytes for bounded native UTF-16 input.
        - Convert database-owned UTF-16 input into an allocated UTF-8 value.

    This file intentionally does NOT contain:

        - Text collation, case mapping, or string allocation.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_vdbe_mem_text.bi"

Private Const SQLITE_UTF8_REPLACEMENT As ULong = &HFFFD

Private Function sqlite3Utf8InitialBits(ByVal firstByte As UByte) As ULong
    If firstByte <= &HDF Then Return CULng(firstByte And &H1F)
    If firstByte <= &HEF Then Return CULng(firstByte And &H0F)
    If firstByte <= &HF7 Then Return CULng(firstByte And &H07)
    If firstByte <= &HFB Then Return CULng(firstByte And &H03)
    If firstByte <= &HFD Then Return CULng(firstByte And &H01)
    Return 0
End Function

Function sqlite3Utf8Read CDecl Alias "sqlite3Utf8Read" ( _
    ByVal pzArgument As Any Ptr _
) As u32 Export

    If pzArgument = 0 Then Return 0

    Dim pz As Const UByte Ptr Ptr = CPtr(Const UByte Ptr Ptr, pzArgument)
    Dim z As Const UByte Ptr = pz[0]
    If z = 0 Then Return 0

    Dim c As ULong = z[0]
    z += 1

    If c >= &HC0 Then
        c = sqlite3Utf8InitialBits(CUByte(c))
        While (z[0] And &HC0) = &H80
            c = (c Shl 6) + (z[0] And &H3F)
            z += 1
        Wend

        If c < &H80 OrElse (c And &HFFFFF800) = &HD800 Then
            c = SQLITE_UTF8_REPLACEMENT
        End If
    End If

    pz[0] = z
    Return c
End Function

Function sqlite3AppendOneUtf8Character CDecl Alias "sqlite3AppendOneUtf8Character" ( _
    ByVal zOut As UByte Ptr, _
    ByVal codepoint As u32 _
) As SQLITE_C_INT Export

    If zOut = 0 Then Return 0

    If codepoint < &H80 Then
        zOut[0] = CUByte(codepoint And &HFF)
        Return 1
    ElseIf codepoint < &H800 Then
        zOut[0] = CUByte(&HC0 + ((codepoint Shr 6) And &H1F))
        zOut[1] = CUByte(&H80 + (codepoint And &H3F))
        Return 2
    ElseIf codepoint < &H10000 Then
        zOut[0] = CUByte(&HE0 + ((codepoint Shr 12) And &H0F))
        zOut[1] = CUByte(&H80 + ((codepoint Shr 6) And &H3F))
        zOut[2] = CUByte(&H80 + (codepoint And &H3F))
        Return 3
    End If

    zOut[0] = CUByte(&HF0 + ((codepoint Shr 18) And &H07))
    zOut[1] = CUByte(&H80 + ((codepoint Shr 12) And &H3F))
    zOut[2] = CUByte(&H80 + ((codepoint Shr 6) And &H3F))
    zOut[3] = CUByte(&H80 + (codepoint And &H3F))
    Return 4
End Function

Function sqlite3Utf8ReadLimited CDecl Alias "sqlite3Utf8ReadLimited" ( _
    ByVal z As Const UByte Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal pCodepoint As u32 Ptr _
) As SQLITE_C_INT Export

    If z = 0 OrElse pCodepoint = 0 OrElse nByte <= 0 Then Return 0

    Dim c As ULong = z[0]
    Dim used As SQLITE_C_INT = 1

    If c >= &HC0 Then
        c = sqlite3Utf8InitialBits(CUByte(c))
        Dim nLimit As SQLITE_C_INT = nByte
        If nLimit > 4 Then nLimit = 4

        While used < nLimit AndAlso (z[used] And &HC0) = &H80
            c = (c Shl 6) + (z[used] And &H3F)
            used += 1
        Wend
    End If

    pCodepoint[0] = c
    Return used
End Function

Function sqlite3Utf8CharLen CDecl Alias "sqlite3Utf8CharLen" ( _
    ByVal zIn As Const UByte Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If zIn = 0 Then Return 0

    Dim position As LongInt = 0
    Dim characterCount As LongInt = 0

    While (nByte < 0 OrElse position < nByte) AndAlso zIn[position] <> 0
        Dim firstByte As UByte = zIn[position]
        position += 1

        If firstByte >= &HC0 Then
            While (nByte < 0 OrElse position < nByte) AndAlso _
                (zIn[position] And &HC0) = &H80
                position += 1
            Wend
        End If

        characterCount += 1
        If characterCount >= &H7FFFFFFF Then Return &H7FFFFFFF
    Wend

    Return CLng(characterCount)
End Function

Function sqlite3Utf16ByteLen CDecl Alias "sqlite3Utf16ByteLen" ( _
    ByVal zIn As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal nChar As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If zIn = 0 OrElse nByte <= 0 OrElse nChar <= 0 Then Return 0

    ' The source routine reads the high byte of each native-endian UTF-16 unit.
    Dim endianMarker As UShort = 1
    Dim littleEndian As SQLITE_C_INT = 0
    If CPtr(UByte Ptr, @endianMarker)[0] = 1 Then littleEndian = 1

    Dim z As Const UByte Ptr = CPtr(Const UByte Ptr, zIn)
    Dim position As LongInt = littleEndian
    Dim characterCount As LongInt = 0
    Dim lastByte As LongInt = nByte - 1

    While characterCount < nChar AndAlso position <= lastByte
        Dim leadingByte As UByte = z[position]
        position += 2

        If leadingByte >= &HD8 AndAlso leadingByte < &HDC AndAlso _
           position <= lastByte AndAlso z[position] >= &HDC AndAlso z[position] < &HE0 Then
            position += 2
        End If

        characterCount += 1
    Wend

    Return CLng(position - littleEndian)
End Function

Function sqlite3Utf16to8 CDecl Alias "sqlite3Utf16to8" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal z As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal enc As u8 _
) As ZString Ptr Export

    ' The Mem cell borrows the caller's input. With a null database context,
    ' conversion storage uses SQLite's global allocator as ValueNew does.
    Dim value As SqliteVdbeMem
    sqlite3VdbeMemInit(@value, db, 0)
    Dim rc As SQLITE_C_INT = sqlite3VdbeMemSetStr( _
        @value, CPtr(Const ZString Ptr, z), nByte, enc, _
        CPtr(sqlite3MemDestructor, 0))
    If rc = SQLITE_OK Then rc = sqlite3VdbeChangeEncoding(@value, SQLITE_UTF8)
    If rc <> SQLITE_OK Then
        sqlite3VdbeMemRelease(@value)
        Return 0
    End If

    If db <> 0 AndAlso db->mallocFailed <> 0 Then
        sqlite3VdbeMemRelease(@value)
        Return 0
    End If

    ' Ownership of the allocated UTF-8 text transfers to the caller.
    Return CPtr(ZString Ptr, value.z)
End Function

/' end of sqlite3_utf.bas '/
