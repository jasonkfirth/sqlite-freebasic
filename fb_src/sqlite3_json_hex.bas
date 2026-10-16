/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_hex.bas

    Purpose:

        Validate and decode hexadecimal characters used by SQLite JSON parsing.

    Responsibilities:

        - Convert one hex digit or four consecutive hex digits to integer values.
        - Check two- and four-digit escape sequences without reading null inputs.
        - Recognize the JSONB text-with-escapes marker.

    This file intentionally does NOT contain:

        - UTF escape decoding, JSON tokenization, or JSONB traversal.
'/ 

#lang "fb"
#include once "sqlite3_json_parse.bi"

Private Function jsonIsHexDigit(ByVal value As UByte) As SQLITE_C_INT
    If value >= Asc("0") AndAlso value <= Asc("9") Then Return 1
    If value >= Asc("A") AndAlso value <= Asc("F") Then Return 1
    If value >= Asc("a") AndAlso value <= Asc("f") Then Return 1
    Return 0
End Function

Function jsonHexToInt CDecl Alias "jsonHexToInt" ( _
    ByVal value As SQLITE_C_INT _
) As u8 Export
    Dim digit As SQLITE_C_INT = value
    If digit >= Asc("0") AndAlso digit <= Asc("9") Then _
        Return CByte(digit - Asc("0"))
    If digit >= Asc("A") AndAlso digit <= Asc("F") Then _
        Return CByte(digit - Asc("A") + 10)
    If digit >= Asc("a") AndAlso digit <= Asc("f") Then _
        Return CByte(digit - Asc("a") + 10)
    Return CByte(digit And &HF)
End Function

Function jsonHexToInt4 CDecl Alias "jsonHexToInt4" ( _
    ByVal zHex As Const UByte Ptr _
) As u32 Export
    If zHex = 0 Then Return 0
    Return (CULng(jsonHexToInt(zHex[0])) Shl 12) Or _
           (CULng(jsonHexToInt(zHex[1])) Shl 8) Or _
           (CULng(jsonHexToInt(zHex[2])) Shl 4) Or _
           CULng(jsonHexToInt(zHex[3]))
End Function

Function jsonIs2Hex CDecl Alias "jsonIs2Hex" ( _
    ByVal zHex As Const UByte Ptr _
) As SQLITE_C_INT Export
    If zHex = 0 Then Return 0
    Return CInt(jsonIsHexDigit(zHex[0]) <> 0 AndAlso _
                jsonIsHexDigit(zHex[1]) <> 0)
End Function

Function jsonIs4Hex CDecl Alias "jsonIs4Hex" ( _
    ByVal zHex As Const UByte Ptr _
) As SQLITE_C_INT Export
    If zHex = 0 Then Return 0
    Return CInt(jsonIs2Hex(zHex) <> 0 AndAlso jsonIs2Hex(zHex + 2) <> 0)
End Function

Function jsonIs4HexB CDecl Alias "jsonIs4HexB" ( _
    ByVal zEscape As Const UByte Ptr, _
    ByVal pOpcode As SQLITE_C_INT Ptr _
) As SQLITE_C_INT Export
    If zEscape = 0 OrElse pOpcode = 0 OrElse zEscape[0] <> Asc("u") Then Return 0
    If jsonIs4Hex(zEscape + 1) = 0 Then Return 0
    pOpcode[0] = JSONB_TEXTJ
    Return 1
End Function

/' end of sqlite3_json_hex.bas '/
