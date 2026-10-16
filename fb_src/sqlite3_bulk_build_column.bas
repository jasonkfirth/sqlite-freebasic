/'
    Project: SQLite FreeBASIC port

    File: sqlite3_bulk_build_column.bas

    Purpose:

        Add a column to the table currently being built by CREATE TABLE.

    Responsibilities:

        - Enforce the connection's column limit and reject duplicate names.
        - Store standard declared types in Column's packed type field.
        - Preserve custom type text beside the dequoted column name.
        - Update name hashes and generated/hidden column properties.

    This file intentionally does NOT contain:

        - Column constraints or table constraints.
        - The Lemon grammar actions that call this routine.
'/

#lang "fb"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_std_types.bi"

Declare Sub sqlite3Dequote CDecl Alias "sqlite3Dequote" (ByVal zText As ZString Ptr)
Declare Sub sqlite3DequoteToken CDecl Alias "sqlite3DequoteToken" (ByVal pToken As Any Ptr)
Declare Function sqlite3ColumnIndex CDecl Alias "sqlite3ColumnIndex" ( _
    ByVal pTable As Any Ptr, ByVal zColumnName As Const ZString Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3ColumnPropertiesFromName CDecl Alias "sqlite3ColumnPropertiesFromName" ( _
    ByVal pTable As Any Ptr, ByVal pColumn As Any Ptr _
)
Declare Function sqlite3StrIHash CDecl Alias "sqlite3StrIHash" ( _
    ByVal zText As Const ZString Ptr _
) As UByte
Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal zText As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3RenameTokenMap CDecl Alias "sqlite3RenameTokenMap" ( _
    ByVal pParse As Any Ptr, _
    ByVal pPointer As Any Ptr, _
    ByVal pToken As Any Ptr _
) As Any Ptr
Declare Function sqlite3_strnicmp CDecl Alias "sqlite3_strnicmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As SQLITE_C_INT
#ifdef SQLITE_ENABLE_SORTER_REFERENCES
Declare Function sqlite3ConfigSorterRefSizeValue CDecl _
    Alias "sqlite3ConfigSorterRefSizeValue" () As SQLITE_C_UINT
#endif

Private Function buildTokenSpace(ByVal value As UByte) As SQLITE_C_INT
    Select Case value
    Case 9, 10, 11, 12, 13, 32
        Return 1
    End Select
    Return 0
End Function

Private Sub buildSetColumnType(ByVal pColumn As SqliteColumn Ptr, ByVal eType As UByte)
    If pColumn = 0 Then Exit Sub
    Dim pTypeByte As UByte Ptr = CPtr(UByte Ptr, @pColumn->flags)
    Dim endianProbe As UShort = 1
    If *CPtr(UByte Ptr, @endianProbe) = 1 Then
        pTypeByte[0] = (pTypeByte[0] And &H0F) Or CByte(eType Shl 4)
    Else
        pTypeByte[0] = (pTypeByte[0] And &HF0) Or eType
    End If
End Sub

Sub sqlite3AddColumn CDecl Alias "sqlite3AddColumn" ( _
    ByVal parseContext As Any Ptr, _
    ByVal nameToken As sqlite3ParserToken, _
    ByVal typeToken As sqlite3ParserToken _
)
    Dim pParse As SqliteParseContext Ptr = _
        CPtr(SqliteParseContext Ptr, parseContext)
    If pParse = 0 OrElse pParse->db = 0 OrElse pParse->pNewTable = 0 Then Exit Sub

    Dim db As sqlite3 Ptr = pParse->db
    Dim pTable As SqliteTable Ptr = CPtr(SqliteTable Ptr, pParse->pNewTable)
    If pTable->nCol < 0 OrElse pTable->nCol >= &H7FFF Then Exit Sub
    If pTable->nCol + 1 > db->aLimit(SQLITE_LIMIT_COLUMN) Then
        sqlite3ErrorMsg(pParse, StrPtr("too many columns on %s"), pTable->zName)
        Exit Sub
    End If
    If nameToken.z = 0 OrElse nameToken.n = 0 Then Exit Sub

    Dim localName As sqlite3ParserToken = nameToken
    Dim localType As sqlite3ParserToken = typeToken
    Dim inRename As SQLITE_C_INT = CInt(pParse->eParseMode >= PARSE_MODE_RENAME)
    If inRename = 0 Then sqlite3DequoteToken(@localName)

    ' Lemon can attach the words "GENERATED ALWAYS" to a column type.
    ' Remove that suffix before deciding whether the type is standard.
    If localType.n >= 16 AndAlso sqlite3_strnicmp( _
        CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, localType.z) + localType.n - 6), _
        StrPtr("always"), 6) = 0 Then
        localType.n -= 6
        While localType.n > 0 AndAlso buildTokenSpace(localType.z[localType.n - 1]) <> 0
            localType.n -= 1
        Wend
        If localType.n >= 9 AndAlso sqlite3_strnicmp( _
            CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, localType.z) + localType.n - 9), _
            StrPtr("generated"), 9) = 0 Then
            localType.n -= 9
            While localType.n > 0 AndAlso buildTokenSpace(localType.z[localType.n - 1]) <> 0
                localType.n -= 1
            Wend
        End If
    End If

    Dim eType As UByte = COLTYPE_CUSTOM
    Dim estimatedSize As UByte = 1
    Dim affinity As Byte = SQLITE_AFF_BLOB
    If localType.n >= 3 Then
        sqlite3DequoteToken(@localType)
        Dim standardTypes As Const ZString Ptr Ptr = sqlite3StdTypeTable()
        If standardTypes <> 0 Then
            For typeIndex As SQLITE_C_INT = 0 To SQLITE_N_STDTYPE - 1
                Dim zStandardType As Const ZString Ptr = standardTypes[typeIndex]
                If zStandardType = 0 OrElse sqlite3Strlen30(zStandardType) <> localType.n Then _
                    Continue For
                If sqlite3_strnicmp( _
                    CPtr(Const ZString Ptr, localType.z), zStandardType, localType.n) <> 0 Then _
                    Continue For
                localType.n = 0
                eType = CByte(typeIndex + 1)
                affinity = sqlite3AffinityType(zStandardType, 0)
                If affinity <= SQLITE_AFF_TEXT Then estimatedSize = 5
                Exit For
            Next
        End If
    End If

    Dim nameLength As sqlite3_uint64 = CULngInt(localName.n)
    Dim typeLength As sqlite3_uint64 = CULngInt(localType.n)
    Dim allocationSize As sqlite3_uint64 = nameLength + 1 + typeLength
    If localType.n > 0 Then allocationSize += 1
    If allocationSize > SQLITE_MAX_ALLOCATION_SIZE Then Exit Sub

    Dim zColumnName As ZString Ptr = _
        CPtr(ZString Ptr, sqlite3DbMallocRaw(db, allocationSize))
    If zColumnName = 0 Then Exit Sub
    If inRename <> 0 Then sqlite3RenameTokenMap(pParse, zColumnName, @nameToken)

    Dim pNameBytes As UByte Ptr = CPtr(UByte Ptr, zColumnName)
    Dim pTokenBytes As Const UByte Ptr = CPtr(Const UByte Ptr, localName.z)
    For byteIndex As sqlite3_uint64 = 0 To nameLength - 1
        pNameBytes[byteIndex] = pTokenBytes[byteIndex]
    Next
    pNameBytes[nameLength] = 0
    sqlite3Dequote(zColumnName)

    If pTable->nCol > 0 AndAlso sqlite3ColumnIndex(pTable, zColumnName) >= 0 Then
        sqlite3ErrorMsg(pParse, StrPtr("duplicate column name: %s"), zColumnName)
        sqlite3DbFree(db, zColumnName)
        Exit Sub
    End If

    Dim newColumnCount As sqlite3_uint64 = CULngInt(pTable->nCol) + 1
    Dim newArraySize As sqlite3_uint64 = _
        newColumnCount * CULngInt(SizeOf(SqliteColumn))
    If newArraySize > SQLITE_MAX_ALLOCATION_SIZE Then
        sqlite3DbFree(db, zColumnName)
        Exit Sub
    End If
    Dim pNewColumns As SqliteColumn Ptr = CPtr(SqliteColumn Ptr, _
        sqlite3DbRealloc(db, pTable->aCol, newArraySize))
    If pNewColumns = 0 Then
        sqlite3DbFree(db, zColumnName)
        Exit Sub
    End If
    pTable->aCol = pNewColumns

    Dim pColumn As SqliteColumn Ptr = @pTable->aCol[pTable->nCol]
    Dim pColumnBytes As UByte Ptr = CPtr(UByte Ptr, pColumn)
    For byteIndex As Long = 0 To SizeOf(SqliteColumn) - 1
        pColumnBytes[byteIndex] = 0
    Next
    pColumn->zCnName = zColumnName
    pColumn->hName = sqlite3StrIHash(zColumnName)
#if SQLITE_ENABLE_HIDDEN_COLUMNS
    sqlite3ColumnPropertiesFromName(pTable, pColumn)
#endif

    If localType.n = 0 Then
        pColumn->affinity = affinity
        pColumn->szEst = estimatedSize
        buildSetColumnType(pColumn, eType)
#ifdef SQLITE_ENABLE_SORTER_REFERENCES
        ' Untyped columns use SQLite's four-byte default size estimate.
        If affinity = SQLITE_AFF_BLOB AndAlso _
           4 >= sqlite3ConfigSorterRefSizeValue() Then _
            pColumn->colFlags Or= COLFLAG_SORTERREF
#endif
    Else
        Dim typeOffset As SQLITE_C_INT = sqlite3Strlen30(zColumnName) + 1
        Dim pTypeBytes As UByte Ptr = CPtr(UByte Ptr, zColumnName) + typeOffset
        Dim pSourceType As Const UByte Ptr = CPtr(Const UByte Ptr, localType.z)
        For byteIndex As SQLITE_C_INT = 0 To localType.n - 1
            pTypeBytes[byteIndex] = pSourceType[byteIndex]
        Next
        pTypeBytes[localType.n] = 0
        Dim zType As ZString Ptr = CPtr(ZString Ptr, pTypeBytes)
        sqlite3Dequote(zType)
        pColumn->affinity = sqlite3AffinityType(zType, pColumn)
        pColumn->colFlags Or= COLFLAG_HASTYPE
    End If

    If pTable->nCol <= &HFF Then
        Dim hashSlot As SQLITE_C_INT = pColumn->hName Mod SizeOf(pTable->aHx)
        pTable->aHx(hashSlot) = CByte(pTable->nCol)
    End If
    pTable->nCol += 1
    pTable->nNVCol += 1
    pParse->u1.cr.constraintName.n = 0
End Sub

/' end of sqlite3_bulk_build_column.bas '/
