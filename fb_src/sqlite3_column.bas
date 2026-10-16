/'
    Project: SQLite FreeBASIC port

    File: sqlite3_column.bas

    Purpose:

        Return the declared type stored in SQLite's compact Column record.

    Responsibilities:

        - Read the column-name and type fields from the upstream C layout.
        - Return custom type text or a standard type name.
        - Use the caller's fallback when the column has no declared type.

    This file intentionally does NOT contain:

        - Table allocation or schema parsing.
        - The complete Column or Table structures.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_internal_api_declarations.bi"

Private Const SQLITE_COLUMN_COLFLAG_HASTYPE As UShort = &H0004
Private Const SQLITE_COLUMN_TYPE_ANY As UByte = 1
Private Const SQLITE_COLUMN_TYPE_BLOB As UByte = 2
Private Const SQLITE_COLUMN_TYPE_INT As UByte = 3
Private Const SQLITE_COLUMN_TYPE_INTEGER As UByte = 4
Private Const SQLITE_COLUMN_TYPE_REAL As UByte = 5
Private Const SQLITE_COLUMN_TYPE_TEXT As UByte = 6

Function sqlite3ColumnType CDecl Alias "sqlite3ColumnType" ( _
    ByVal pColumnArgument As Any Ptr, _
    ByVal zDefault As ZString Ptr _
) As ZString Ptr Export

    If pColumnArgument = 0 Then Return zDefault
    Dim pColumn As UByte Ptr = CPtr(UByte Ptr, pColumnArgument)
    Dim zColumnName As ZString Ptr = *CPtr(ZString Ptr Ptr, pColumnArgument)
    ' Column stores a four-byte bitfield unit, three byte fields, then two
    ' aligned UShort fields. colFlags therefore begins 10 bytes past the
    ' bitfield unit and 10 bytes after the name pointer on 32- and 64-bit ABI.
    Dim pColumnFlags As UShort Ptr = CPtr(UShort Ptr, _
        pColumn + SizeOf(Any Ptr) + 10)
    Dim columnFlags As UShort = pColumnFlags[0]

    If (columnFlags And SQLITE_COLUMN_COLFLAG_HASTYPE) <> 0 Then
        If zColumnName = 0 Then Return zDefault
        Dim nName As SQLITE_C_INT = sqlite3Strlen30(zColumnName)
        Return CPtr(ZString Ptr, CPtr(UByte Ptr, zColumnName) + nName + 1)
    End If

    ' Column.eCType is the high nibble of the first byte in the C unsigned
    ' bitfield unit on little-endian targets. Big-endian ABIs allocate the
    ' first bitfield from the high side, so the type occupies the low nibble.
    Dim packedTypes As UByte = pColumn[SizeOf(Any Ptr)]
    Dim eCType As UByte
    Dim endianProbe As UShort = 1
    If *CPtr(UByte Ptr, @endianProbe) = 1 Then
        eCType = (packedTypes Shr 4) And &HF
    Else
        eCType = packedTypes And &HF
    End If

    Select Case eCType
    Case SQLITE_COLUMN_TYPE_ANY
        Return StrPtr("ANY")
    Case SQLITE_COLUMN_TYPE_BLOB
        Return StrPtr("BLOB")
    Case SQLITE_COLUMN_TYPE_INT
        Return StrPtr("INT")
    Case SQLITE_COLUMN_TYPE_INTEGER
        Return StrPtr("INTEGER")
    Case SQLITE_COLUMN_TYPE_REAL
        Return StrPtr("REAL")
    Case SQLITE_COLUMN_TYPE_TEXT
        Return StrPtr("TEXT")
    End Select
    Return zDefault
End Function

/' end of sqlite3_column.bas '/
