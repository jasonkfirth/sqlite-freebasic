/'
    Project: SQLite FreeBASIC port

    File: sqlite3_varint.bas

    Purpose:

        Read and write SQLite varints and big-endian fixed-width integers.

    Responsibilities:

        - Encode/decode SQLite's 1-to-9-byte unsigned varint format.
        - Read/write four-byte and read eight-byte big-endian values.

    This file intentionally does NOT contain:

        - Record layout, B-tree pages, or pager operations.
'/

#lang "fb"
#include once "sqlite3_varint.bi"

Extern "C"
    Declare Function sqlite3VarintMemcpy CDecl Alias "memcpy" ( _
        ByVal destination As Any Ptr, _
        ByVal source As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
End Extern

Private Function putVarint64( _
    ByVal zOut As UByte Ptr, _
    ByVal value As sqlite3_uint64 _
) As SQLITE_C_INT
    If zOut = 0 Then Return 0
    If (value And &HFF00000000000000) <> 0 Then
        zOut[8] = CUByte(value And &HFF)
        Dim remaining As ULongInt = value Shr 8
        For i As Long = 7 To 0 Step -1
            zOut[i] = CUByte((remaining And &H7F) Or &H80)
            remaining = remaining Shr 7
        Next
        Return 9
    End If

    Dim reverseBytes(0 To 8) As UByte
    Dim count As Long = 0
    Dim remaining As ULongInt = value
    Do
        reverseBytes(count) = CUByte((remaining And &H7F) Or &H80)
        remaining = remaining Shr 7
        count += 1
    Loop While remaining <> 0
    reverseBytes(0) = reverseBytes(0) And &H7F
    For i As Long = 0 To count - 1
        zOut[i] = reverseBytes(count - i - 1)
    Next
    Return CInt(count)
End Function

Function sqlite3PutVarint CDecl Alias "sqlite3PutVarint" ( _
    ByVal zOut As UByte Ptr, _
    ByVal value As sqlite3_uint64 _
) As SQLITE_C_INT Export
    If zOut = 0 Then Return 0
    If value <= &H7F Then
        zOut[0] = CUByte(value And &H7F)
        Return 1
    End If
    If value <= &H3FFF Then
        zOut[0] = CUByte(((value Shr 7) And &H7F) Or &H80)
        zOut[1] = CUByte(value And &H7F)
        Return 2
    End If
    Return putVarint64(zOut, value)
End Function

Function sqlite3GetVarint CDecl Alias "sqlite3GetVarint" ( _
    ByVal zIn As Const UByte Ptr, _
    ByVal pValue As sqlite3_uint64 Ptr _
) As u8 Export
    If pValue = 0 Then Return 0
    pValue[0] = 0
    If zIn = 0 Then Return 0

    Dim value As ULongInt = zIn[0] And &H7F
    If zIn[0] < &H80 Then
        pValue[0] = value
        Return 1
    End If
    For i As Long = 1 To 7
        Dim nextByte As UByte = zIn[i]
        value = (value Shl 7) Or CULngInt(nextByte And &H7F)
        If nextByte < &H80 Then
            pValue[0] = value
            Return CUByte(i + 1)
        End If
    Next
    value = (value Shl 8) Or CULngInt(zIn[8])
    pValue[0] = value
    Return 9
End Function

Function sqlite3VarintValue CDecl Alias "sqlite3VarintValue" ( _
    ByVal zIn As Const UByte Ptr _
) As sqlite3_int64 Export
    Dim bits As sqlite3_uint64 = 0
    If sqlite3GetVarint(zIn, @bits) = 0 Then Return 0
    Dim value As sqlite3_int64 = 0
    sqlite3VarintMemcpy(@value, @bits, SizeOf(value))
    Return value
End Function

Function sqlite3GetVarint32 CDecl Alias "sqlite3GetVarint32" ( _
    ByVal zIn As Const UByte Ptr, _
    ByVal pValue As u32 Ptr _
) As u8 Export
    If zIn = 0 OrElse pValue = 0 Then Return 0
    If zIn[0] < &H80 Then
        pValue[0] = zIn[0]
        Return 1
    End If
    If zIn[1] < &H80 Then
        pValue[0] = (CULng(zIn[0] And &H7F) Shl 7) Or zIn[1]
        Return 2
    End If
    If zIn[2] < &H80 Then
        pValue[0] = (CULng(zIn[0] And &H7F) Shl 14) Or _
                    (CULng(zIn[1] And &H7F) Shl 7) Or zIn[2]
        Return 3
    End If

    Dim value64 As ULongInt = 0
    Dim count As u8 = sqlite3GetVarint(zIn, @value64)
    If value64 > &HFFFFFFFF Then
        pValue[0] = &HFFFFFFFF
    Else
        pValue[0] = CULng(value64)
    End If
    Return count
End Function

Function sqlite3VarintLen CDecl Alias "sqlite3VarintLen" ( _
    ByVal inputValue As sqlite3_uint64 _
) As SQLITE_C_INT Export
    Dim value As ULongInt = inputValue
    Dim byteCount As Long = 1
    While (value Shr 7) <> 0
        value = value Shr 7
        byteCount += 1
    Wend
    Return CInt(byteCount)
End Function

Function sqlite3Get4byte CDecl Alias "sqlite3Get4byte" ( _
    ByVal p As Const UByte Ptr _
) As u32 Export
    If p = 0 Then Return 0
    Return (CULng(p[0]) Shl 24) Or (CULng(p[1]) Shl 16) Or _
           (CULng(p[2]) Shl 8) Or CULng(p[3])
End Function

Sub sqlite3Put4byte CDecl Alias "sqlite3Put4byte" ( _
    ByVal p As UByte Ptr, _
    ByVal value As u32 _
) Export
    If p = 0 Then Exit Sub
    p[0] = CUByte((value Shr 24) And &HFF)
    p[1] = CUByte((value Shr 16) And &HFF)
    p[2] = CUByte((value Shr 8) And &HFF)
    p[3] = CUByte(value And &HFF)
End Sub

Function sqlite3Get8byte CDecl Alias "sqlite3Get8byte" ( _
    ByVal p As Const UByte Ptr _
) As sqlite3_uint64 Export
    If p = 0 Then Return 0
    Dim value As ULongInt = 0
    For i As Long = 0 To 7
        value = (value Shl 8) Or CULngInt(p[i])
    Next
    Return value
End Function

/' end of sqlite3_varint.bas '/
