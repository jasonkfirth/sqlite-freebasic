/'
    Project: SQLite FreeBASIC port
    File: sqlite3_c2fb_intrinsics.bas

    Purpose:

        Provide fixed-width operations used to lower supported C compiler builtins.

    Responsibilities:

        - Byte-swap 16-bit, 32-bit, and 64-bit unsigned values.
        - Keep byte-order conversion independent of host integer layout.

    This file intentionally does NOT contain:

        - SQLite query logic or public API entry points.
        - Compiler runtime hooks or platform-specific assembly.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"

/' ------------------------------------------------------------------------- '/
/' Fixed-width byte swaps '/
/' ------------------------------------------------------------------------- '/

Function c2fbByteSwap16 CDecl Alias "c2fbByteSwap16" (ByVal value As u16) As u16
    Dim wideValue As u32 = value
    Return Cast(u16, _
        ((wideValue And &H00FFUL) Shl 8) Or _
        ((wideValue And &HFF00UL) Shr 8))
End Function

Function c2fbByteSwap32 CDecl Alias "c2fbByteSwap32" (ByVal value As u32) As u32
    Return _
        ((value And &H000000FFUL) Shl 24) Or _
        ((value And &H0000FF00UL) Shl 8) Or _
        ((value And &H00FF0000UL) Shr 8) Or _
        ((value And &HFF000000UL) Shr 24)
End Function

Function c2fbByteSwap64 CDecl Alias "c2fbByteSwap64" (ByVal value As u64) As u64
    Return _
        ((value And &H00000000000000FFULL) Shl 56) Or _
        ((value And &H000000000000FF00ULL) Shl 40) Or _
        ((value And &H0000000000FF0000ULL) Shl 24) Or _
        ((value And &H00000000FF000000ULL) Shl 8) Or _
        ((value And &H000000FF00000000ULL) Shr 8) Or _
        ((value And &H0000FF0000000000ULL) Shr 24) Or _
        ((value And &H00FF000000000000ULL) Shr 40) Or _
        ((value And &HFF00000000000000ULL) Shr 56)
End Function

/' end of sqlite3_c2fb_intrinsics.bas '/
