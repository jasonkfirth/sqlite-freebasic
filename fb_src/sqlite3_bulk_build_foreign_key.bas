/'
    Project: SQLite FreeBASIC port

    File: sqlite3_bulk_build_foreign_key.bas

    Purpose:

        Attach foreign-key definitions to a table under construction.

    Responsibilities:

        - Match child column names to the current table's column array.
        - Store referenced table and optional parent-column names in one allocation.
        - Link each foreign key into the child table and parent-name hash chains.
        - Release parser-owned column lists on success and failure paths.

    This file intentionally does NOT contain:

        - Foreign-key trigger generation or runtime constraint checking.
        - Lemon actions for the REFERENCES grammar productions.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_fkey_types.bi"
#include once "sqlite3_hash_types.bi"

Declare Function sqlite3_stricmp CDecl Alias "sqlite3_stricmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal zText As Const ZString Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3Dequote CDecl Alias "sqlite3Dequote" (ByVal zText As ZString Ptr)
Declare Function sqlite3RenameTokenMap CDecl Alias "sqlite3RenameTokenMap" ( _
    ByVal pParse As Any Ptr, ByVal pPointer As Any Ptr, ByVal pToken As Any Ptr _
) As Any Ptr
Declare Sub sqlite3RenameTokenRemap CDecl Alias "sqlite3RenameTokenRemap" ( _
    ByVal pParse As Any Ptr, ByVal pPointer As Any Ptr, ByVal pToken As Any Ptr _
)

Sub sqlite3CreateForeignKey CDecl Alias "sqlite3CreateForeignKey" ( _
    ByVal parseContext As Any Ptr, _
    ByVal fromColumns As Any Ptr, _
    ByVal referencedTable As Any Ptr, _
    ByVal toColumns As Any Ptr, _
    ByVal actionFlags As SQLITE_C_INT _
)
    Dim pParse As SqliteParseContext Ptr = CPtr(SqliteParseContext Ptr, parseContext)
    If pParse = 0 OrElse pParse->db = 0 Then Exit Sub

    Dim db As sqlite3 Ptr = pParse->db
    Dim pFromColumns As SqliteExprList Ptr = _
        CPtr(SqliteExprList Ptr, fromColumns)
    Dim pToToken As sqlite3ParserToken Ptr = _
        CPtr(sqlite3ParserToken Ptr, referencedTable)
    Dim pToColumns As SqliteExprList Ptr = _
        CPtr(SqliteExprList Ptr, toColumns)
    Dim pForeignKey As SqliteFKey Ptr = 0
    Dim pTable As SqliteTable Ptr = 0
    Dim pToItem As SqliteExprListItem Ptr = 0
    Dim pFromItem As SqliteExprListItem Ptr = 0
    Dim pColumnName As Const ZString Ptr = 0
    Dim pParentName As Const UByte Ptr = 0
    Dim pText As UByte Ptr = 0
    Dim pSchema As SqliteSchema Ptr = 0
    Dim pNextTo As SqliteFKey Ptr = 0
    Dim zFromColumn As Const ZString Ptr = 0
    Dim columnCount As SQLITE_C_INT = 0
    Dim matchedColumn As SQLITE_C_INT = -1
    Dim tableColumn As SQLITE_C_INT = 0
    Dim nameLength As SQLITE_C_INT = 0
    Dim allocationSize As sqlite3_uint64 = 0
    Dim i As SQLITE_C_INT = 0
    Dim iByte As sqlite3_uint64 = 0

#ifndef SQLITE_OMIT_FOREIGN_KEY
    pTable = CPtr(SqliteTable Ptr, pParse->pNewTable)
    If pTable = 0 OrElse pTable->eTabType <> TABTYP_NORM OrElse _
       pParse->eParseMode = PARSE_MODE_DECLARE_VTAB OrElse _
       pToToken = 0 OrElse pToToken->z = 0 OrElse pToToken->n = 0 Then _
        GoTo foreign_key_cleanup

    If pFromColumns = 0 Then
        If pTable->nCol <= 0 Then GoTo foreign_key_cleanup
        If pToColumns <> 0 AndAlso pToColumns->nExpr <> 1 Then
            sqlite3ErrorMsg(pParse, _
                StrPtr("foreign key on %s should reference only one column of table %T"), _
                pTable->aCol[pTable->nCol - 1].zCnName, pToToken)
            GoTo foreign_key_cleanup
        End If
        columnCount = 1
    Else
        columnCount = pFromColumns->nExpr
        If columnCount <= 0 Then GoTo foreign_key_cleanup
        If pToColumns <> 0 AndAlso pToColumns->nExpr <> columnCount Then
            sqlite3ErrorMsg(pParse, _
                StrPtr("number of columns in foreign key does not match the number of columns in the referenced table"))
            GoTo foreign_key_cleanup
        End If
    End If

    allocationSize = _
        CULngInt(SizeOf(SqliteFKey) - SizeOf(SqliteFKeyColumn)) + _
        CULngInt(columnCount) * CULngInt(SizeOf(SqliteFKeyColumn)) + _
        CULngInt(pToToken->n) + 1
    If allocationSize > SQLITE_MAX_ALLOCATION_SIZE Then GoTo foreign_key_cleanup

    If pToColumns <> 0 Then
        For i = 0 To columnCount - 1
            pToItem = sqlite3ExprListItemAt(pToColumns, i)
            If pToItem = 0 OrElse pToItem->zEName = 0 Then GoTo foreign_key_cleanup
            nameLength = sqlite3Strlen30( _
                CPtr(Const ZString Ptr, pToItem->zEName))
            If nameLength < 0 OrElse _
               allocationSize > SQLITE_MAX_ALLOCATION_SIZE - CULngInt(nameLength) - 1 Then _
                GoTo foreign_key_cleanup
            allocationSize += CULngInt(nameLength) + 1
        Next
    End If

    pForeignKey = CPtr(SqliteFKey Ptr, sqlite3DbMallocZero(db, allocationSize))
    If pForeignKey = 0 Then GoTo foreign_key_cleanup
    pForeignKey->pFrom = pTable
    pForeignKey->pNextFrom = pTable->u.tab.pFKey
    pForeignKey->nCol = columnCount

    pText = CPtr(UByte Ptr, @pForeignKey->aCol(0)) + _
        CULngInt(columnCount) * CULngInt(SizeOf(SqliteFKeyColumn))
    pForeignKey->zTo = CPtr(ZString Ptr, pText)
    If pParse->eParseMode = PARSE_MODE_RENAME Then _
        sqlite3RenameTokenMap(pParse, pForeignKey->zTo, pToToken)
    pParentName = CPtr(Const UByte Ptr, pToToken->z)
    For iByte = 0 To CULngInt(pToToken->n) - 1
        pText[iByte] = pParentName[iByte]
    Next
    pText[pToToken->n] = 0
    sqlite3Dequote(pForeignKey->zTo)
    pText += pToToken->n + 1

    If pFromColumns = 0 Then
        pForeignKey->aCol(0).iFrom = pTable->nCol - 1
    Else
        For i = 0 To columnCount - 1
            pFromItem = sqlite3ExprListItemAt(pFromColumns, i)
            If pFromItem = 0 OrElse pFromItem->zEName = 0 Then GoTo foreign_key_cleanup
            zFromColumn = CPtr(Const ZString Ptr, pFromItem->zEName)
            matchedColumn = -1
            For tableColumn = 0 To pTable->nCol - 1
                If pTable->aCol[tableColumn].zCnName <> 0 AndAlso _
                   sqlite3_stricmp(pTable->aCol[tableColumn].zCnName, zFromColumn) = 0 Then
                    matchedColumn = tableColumn
                    Exit For
                End If
            Next
            If matchedColumn < 0 Then
                sqlite3ErrorMsg(pParse, _
                    StrPtr("unknown column ""%s"" in foreign key definition"), zFromColumn)
                GoTo foreign_key_cleanup
            End If
            pForeignKey->aCol(i).iFrom = matchedColumn
            If pParse->eParseMode = PARSE_MODE_RENAME Then _
                sqlite3RenameTokenRemap(pParse, @pForeignKey->aCol(i), pFromItem->zEName)
        Next
    End If

    If pToColumns <> 0 Then
        For i = 0 To columnCount - 1
            pToItem = sqlite3ExprListItemAt(pToColumns, i)
            pColumnName = CPtr(Const ZString Ptr, pToItem->zEName)
            nameLength = sqlite3Strlen30(pColumnName)
            pForeignKey->aCol(i).zCol = CPtr(ZString Ptr, pText)
            If pParse->eParseMode = PARSE_MODE_RENAME Then _
                sqlite3RenameTokenRemap(pParse, pText, pToItem->zEName)
            For iByte = 0 To nameLength - 1
                pText[iByte] = CPtr(Const UByte Ptr, pColumnName)[iByte]
            Next
            pText[nameLength] = 0
            pText += nameLength + 1
        Next
    End If

    pForeignKey->isDeferred = 0
    pForeignKey->aAction(0) = CByte(actionFlags And &HFF)
    pForeignKey->aAction(1) = CByte((actionFlags Shr 8) And &HFF)

    pSchema = CPtr(SqliteSchema Ptr, pTable->pSchema)
    If pSchema = 0 Then GoTo foreign_key_cleanup
    pNextTo = CPtr(SqliteFKey Ptr, _
        sqlite3HashInsert(@pSchema->fkeyHash, pForeignKey->zTo, pForeignKey))
    If pNextTo = pForeignKey Then
        sqlite3OomFault(db)
        GoTo foreign_key_cleanup
    End If
    If pNextTo <> 0 Then
        pForeignKey->pNextTo = pNextTo
        pNextTo->pPrevTo = pForeignKey
    End If
    pTable->u.tab.pFKey = pForeignKey
    pForeignKey = 0

foreign_key_cleanup:
    sqlite3DbFree(db, pForeignKey)
#endif
    sqlite3ExprListDelete(db, pFromColumns)
    sqlite3ExprListDelete(db, pToColumns)
End Sub

/' end of sqlite3_bulk_build_foreign_key.bas '/
