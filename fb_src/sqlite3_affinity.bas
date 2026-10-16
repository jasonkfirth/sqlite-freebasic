/'
    Project: SQLite FreeBASIC port

    File: sqlite3_affinity.bas

    Purpose:

        Determine SQLite type affinity from a declared type name.

    Responsibilities:

        - Apply SQLite's ordered substring rules for INTEGER, TEXT, BLOB,
          REAL, and NUMERIC affinities.
        - Store the column width estimate used by covering-index planning.
        - Keep type-name matching independent of locale.

    This file intentionally does NOT contain:

        - Table or index width aggregation.
'/

#lang "fb"
#include once "sqlite3_constants.bi"
#include once "sqlite3_types.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_numeric.bi"

#ifdef SQLITE_ENABLE_SORTER_REFERENCES
Declare Function sqlite3ConfigSorterRefSizeValue CDecl _
    Alias "sqlite3ConfigSorterRefSizeValue" () As SQLITE_C_UINT
#endif

Function sqlite3AffinityType CDecl Alias "sqlite3AffinityType" ( _
    ByVal zType As Const ZString Ptr, _
    ByVal pColumn As Any Ptr _
) As Byte Export
    If zType = 0 Then Return CByte(SQLITE_AFF_BLOB)
    Dim affinity As UByte = CByte(SQLITE_AFF_NUMERIC)
    Dim hash As u32 = 0
    Dim index As sqlite3_uint64 = 0
    Dim pSizeHint As Const UByte Ptr = 0
    Dim pColumnInfo As SqliteColumn Ptr = CPtr(SqliteColumn Ptr, pColumn)
    ' C indexes the declared type name byte-by-byte. ZString Ptr indexing in
    ' FreeBASIC converts a substring to a number, so scan through a byte view.
    Dim typeBytes As Const UByte Ptr = CPtr(Const UByte Ptr, zType)

    While typeBytes[index] <> 0
        Dim valueByte As UByte = typeBytes[index]
        If valueByte >= Asc("A") AndAlso valueByte <= Asc("Z") Then _
            valueByte = valueByte + Asc("a") - Asc("A")
        hash = (hash Shl 8) + valueByte

        ' Four-byte rolling signatures match the suffix tests in build.c.
        If hash = &H63686172 Then
            affinity = CByte(SQLITE_AFF_TEXT)       ' CHAR
            pSizeHint = @typeBytes[index + 1]
        ElseIf hash = &H636C6F62 Then
            affinity = CByte(SQLITE_AFF_TEXT)       ' CLOB
        ElseIf hash = &H74657874 Then
            affinity = CByte(SQLITE_AFF_TEXT)       ' TEXT
        ElseIf hash = &H626C6F62 AndAlso _
               (affinity = SQLITE_AFF_NUMERIC OrElse affinity = SQLITE_AFF_REAL) Then
            affinity = CByte(SQLITE_AFF_BLOB)       ' BLOB
            If typeBytes[index + 1] = Asc("(") Then _
                pSizeHint = @typeBytes[index + 1]
        ElseIf hash = &H7265616C AndAlso affinity = SQLITE_AFF_NUMERIC Then
            affinity = CByte(SQLITE_AFF_REAL)       ' REAL
        ElseIf hash = &H666C6F61 AndAlso affinity = SQLITE_AFF_NUMERIC Then
            affinity = CByte(SQLITE_AFF_REAL)       ' FLOA
        ElseIf hash = &H646F7562 AndAlso affinity = SQLITE_AFF_NUMERIC Then
            affinity = CByte(SQLITE_AFF_REAL)       ' DOUB
        ElseIf (hash And &H00FFFFFF) = &H00696E74 Then
            affinity = CByte(SQLITE_AFF_INTEGER)    ' INT suffix takes priority
            Exit While
        End If
        index += 1
    Wend

    If pColumnInfo <> 0 Then
        Dim estimatedBytes As SQLITE_C_INT = 0
        If affinity < SQLITE_AFF_NUMERIC Then
            If pSizeHint <> 0 Then
                Dim sizeOffset As sqlite3_uint64 = 0
                While pSizeHint[sizeOffset] <> 0
                    If pSizeHint[sizeOffset] >= Asc("0") AndAlso _
                       pSizeHint[sizeOffset] <= Asc("9") Then
                        sqlite3GetInt32( _
                            CPtr(Const ZString Ptr, pSizeHint + sizeOffset), _
                            @estimatedBytes)
                        Exit While
                    End If
                    sizeOffset += 1
                Wend
            Else
                ' TEXT, CLOB, and unbounded BLOB columns use about 20 bytes.
                estimatedBytes = 16
            End If
        End If

#ifdef SQLITE_ENABLE_SORTER_REFERENCES
        If estimatedBytes >= sqlite3ConfigSorterRefSizeValue() Then _
            pColumnInfo->colFlags Or= COLFLAG_SORTERREF
#endif
        Dim estimatedSize As SQLITE_C_INT = estimatedBytes \ 4 + 1
        If estimatedSize > 255 Then estimatedSize = 255
        pColumnInfo->szEst = CByte(estimatedSize)
    End If

    Return CByte(affinity)
End Function

/' end of sqlite3_affinity.bas '/
