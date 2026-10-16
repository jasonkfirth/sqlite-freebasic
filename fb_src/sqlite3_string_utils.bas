/'
    Project: SQLite FreeBASIC port

    File: sqlite3_string_utils.bas

    Purpose:

        Port small string, token, and hashing helpers from src/util.c.

    Responsibilities:

        - Compute SQLite's bounded 30-bit string length.
        - Remove SQL identifier and string quoting in place.
        - Initialize and adjust the internal Token ABI structure.
        - Compute SQLite's 8-bit case-insensitive string hash.
        - Keep the BINARY collation name at one stable address.

    This file intentionally does NOT contain:

        - SQL parsing or expression ownership.
        - Token classification or keyword lookup.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_global_data.bi"

Private Type SqliteTokenAbi
    z As Const UByte Ptr
    n As u32
End Type

' C compares sqlite3StrBINARY by address as well as by string contents.
Dim Shared As Const ZString * 7 sqlite3StrBINARYBytes = "BINARY"

Function sqlite3StrBINARYName CDecl Alias "sqlite3StrBINARYName" () As Const ZString Ptr
    Return @sqlite3StrBINARYBytes
End Function

Private Function sqlite3IsQuote(ByVal value As UByte) As Long
    Select Case value
    Case Asc("'"), Asc(""""), Asc("["), Asc("`")
        Return -1
    End Select
    Return 0
End Function

Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal z As Const ZString Ptr _
) As SQLITE_C_INT Export

    If z = 0 Then Return 0

    Dim bytes As Const UByte Ptr = CPtr(Const UByte Ptr, z)
    Dim length As ULongInt = 0
    While bytes[length] <> 0
        length += 1
    Wend

    ' SQLite masks to 30 bits so the result always fits a signed C int.
    Return CLng(length And &H3FFFFFFF)
End Function

Function sqlite3StrIHash CDecl Alias "sqlite3StrIHash" ( _
    ByVal z As Const ZString Ptr _
) As UByte Export
    If z = 0 Then Return 0
    Dim bytes As Const UByte Ptr = CPtr(Const UByte Ptr, z)
    Dim hashValue As UByte = 0
    While bytes[0] <> 0
        hashValue = CByte((CULng(hashValue) + sqlite3UpperToLower(bytes[0])) And &HFF)
        bytes += 1
    Wend
    Return hashValue
End Function

Sub sqlite3Dequote CDecl Alias "sqlite3Dequote" ( _
    ByVal z As UByte Ptr _
) Export

    If z = 0 Then Exit Sub
    If sqlite3IsQuote(z[0]) = 0 Then Exit Sub

    Dim quote As UByte = z[0]
    If quote = Asc("[") Then quote = Asc("]")

    ' Find a real closing quote before changing the input, so a malformed
    ' unterminated token remains intact instead of being partially compacted.
    Dim closing As ULongInt = 1
    Dim foundClosing As Long = 0
    While z[closing] <> 0
        If z[closing] = quote Then
            If z[closing + 1] = quote Then
                closing += 2
                Continue While
            End If
            foundClosing = -1
            Exit While
        End If
        closing += 1
    Wend
    If foundClosing = 0 Then Exit Sub

    Dim readPosition As ULongInt = 1
    Dim writePosition As ULongInt = 0
    While readPosition < closing
        If z[readPosition] = quote AndAlso z[readPosition + 1] = quote Then
            z[writePosition] = quote
            readPosition += 2
        Else
            z[writePosition] = z[readPosition]
            readPosition += 1
        End If
        writePosition += 1
    Wend
    z[writePosition] = 0
End Sub

Sub sqlite3DequoteToken CDecl Alias "sqlite3DequoteToken" ( _
    ByVal pTokenArgument As Any Ptr _
) Export

    If pTokenArgument = 0 Then Exit Sub
    Dim pToken As SqliteTokenAbi Ptr = CPtr(SqliteTokenAbi Ptr, pTokenArgument)
    If pToken->n < 2 Then Exit Sub
    If sqlite3IsQuote(pToken->z[0]) = 0 Then Exit Sub

    Dim i As ULongInt = 1
    While i < pToken->n - 1
        If sqlite3IsQuote(pToken->z[i]) <> 0 Then Exit Sub
        i += 1
    Wend

    pToken->n -= 2
    pToken->z += 1
End Sub

Sub sqlite3TokenInit CDecl Alias "sqlite3TokenInit" ( _
    ByVal pTokenArgument As Any Ptr, _
    ByVal z As Const ZString Ptr _
) Export

    If pTokenArgument = 0 Then Exit Sub
    Dim pToken As SqliteTokenAbi Ptr = CPtr(SqliteTokenAbi Ptr, pTokenArgument)
    pToken->z = CPtr(Const UByte Ptr, z)
    pToken->n = CUInt(sqlite3Strlen30(z))
End Sub

/' end of sqlite3_string_utils.bas '/
