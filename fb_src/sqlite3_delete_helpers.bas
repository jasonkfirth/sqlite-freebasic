/'
    Project: SQLite FreeBASIC port

    File: sqlite3_delete_helpers.bas

    Purpose:

        Provide shared DELETE/UPDATE planning helpers from src/delete.c.

    Responsibilities:

        - Resolve a pending VDBE label when a partial-index branch exists.
        - Build the row-key subquery used by UPDATE/DELETE LIMIT clauses.

    This file intentionally does NOT contain:

        - DELETE or UPDATE row/index mutation.
'/ 

#lang "fb"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_vdbe_core.bi"

Declare Function sqlite3Expr CDecl Alias "sqlite3Expr" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal zToken As Const ZString Ptr _
) As SqliteExpr Ptr
Declare Function sqlite3PrimaryKeyIndex CDecl Alias "sqlite3PrimaryKeyIndex" ( _
    ByVal pTable As SqliteTable Ptr _
) As SqliteIndex Ptr
Declare Function sqlite3SrcListDup CDecl Alias "sqlite3SrcListDup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pList As SqliteSrcList Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SqliteSrcList Ptr
Declare Sub sqlite3PExprAddSelect CDecl Alias "sqlite3PExprAddSelect" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
)

Sub sqlite3ResolvePartIdxLabel CDecl Alias "sqlite3ResolvePartIdxLabel" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal label As SQLITE_C_INT _
) Export
    If pParse = 0 OrElse pParse->pVdbe = 0 OrElse label = 0 Then Return
    sqlite3VdbeResolveLabel(CPtr(SqliteVdbe Ptr, pParse->pVdbe), label)
End Sub

Private Const DELETE_SRCITEM_IS_INDEXED_BY As SQLITE_C_UINT = &H0002
Private Const DELETE_SRCITEM_IS_CTE As SQLITE_C_UINT = &H0200
Private Const DELETE_SF_INCLUDE_HIDDEN As u32 = &H00020000

Function sqlite3LimitWhere CDecl Alias "sqlite3LimitWhere" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSource As SqliteSrcList Ptr, _
    ByVal pWhere As SqliteExpr Ptr, _
    ByVal pOrderBy As SqliteExprList Ptr, _
    ByVal pLimit As SqliteExpr Ptr, _
    ByVal zStatementType As ZString Ptr _
) As SqliteExpr Ptr
    If pParse = 0 OrElse pParse->db = 0 OrElse pSource = 0 OrElse _
       pSource->nSrc <= 0 Then Return 0

    Dim db As sqlite3 Ptr = pParse->db
    If pOrderBy AndAlso pLimit = 0 Then
        sqlite3ErrorMsg(pParse, StrPtr(!"ORDER BY without LIMIT on %s"), _
            zStatementType)
        sqlite3ExprDelete(db, pWhere)
        sqlite3ExprListDelete(db, pOrderBy)
        Return 0
    End If
    If pLimit = 0 Then Return pWhere

    Dim pTable As SqliteTable Ptr = _
        CPtr(SqliteTable Ptr, pSource->a(0).pSTab)
    If pTable = 0 Then Return 0

    Dim pLeft As SqliteExpr Ptr = 0
    Dim pSelectList As SqliteExprList Ptr = 0
    If (pTable->tabFlags And TF_WithoutRowid) = 0 Then
        pLeft = sqlite3PExpr(pParse, TK_ROW, 0, 0)
        Dim pRowidExpr As SqliteExpr Ptr = sqlite3PExpr(pParse, TK_ROW, 0, 0)
        pSelectList = sqlite3ExprListAppend(pParse, 0, pRowidExpr)
    Else
        Dim pPrimaryKey As SqliteIndex Ptr = sqlite3PrimaryKeyIndex(pTable)
        If pPrimaryKey = 0 OrElse pPrimaryKey->nKeyCol < 1 Then Return 0

        If pPrimaryKey->nKeyCol = 1 Then
            Dim columnNumber As SQLITE_C_INT = pPrimaryKey->aiColumn[0]
            If columnNumber < 0 OrElse columnNumber >= pTable->nCol Then Return 0
            Dim zColumnName As Const ZString Ptr = _
                pTable->aCol[columnNumber].zCnName
            pLeft = sqlite3Expr(db, TK_ID, zColumnName)
            pSelectList = sqlite3ExprListAppend(pParse, 0, _
                sqlite3Expr(db, TK_ID, zColumnName))
        Else
            For keyColumn As SQLITE_C_INT = 0 To pPrimaryKey->nKeyCol - 1
                Dim columnNumber As SQLITE_C_INT = pPrimaryKey->aiColumn[keyColumn]
                If columnNumber < 0 OrElse columnNumber >= pTable->nCol Then Return 0
                pSelectList = sqlite3ExprListAppend(pParse, pSelectList, _
                    sqlite3Expr(db, TK_ID, pTable->aCol[columnNumber].zCnName))
            Next
            pLeft = sqlite3PExpr(pParse, TK_VECTOR, 0, 0)
            If pLeft Then _
                pLeft->x.pList = sqlite3ExprListDup(db, pSelectList, 0)
        End If
    End If

    ' The source list serves both the mutation and its row-key SELECT. Hide
    ' the resolved Table pointer while copying, then restore the caller's item.
    Dim savedTablePointer As Any Ptr = pSource->a(0).pSTab
    pSource->a(0).pSTab = 0
    Dim pSelectSource As SqliteSrcList Ptr = sqlite3SrcListDup(db, pSource, 0)
    pSource->a(0).pSTab = savedTablePointer

    Dim sourceFlags As SQLITE_C_UINT = pSource->a(0).fg.flags
    If (sourceFlags And DELETE_SRCITEM_IS_INDEXED_BY) <> 0 Then
        pSource->a(0).u2.pIBIndex = 0
        pSource->a(0).fg.flags = _
            pSource->a(0).fg.flags And Not DELETE_SRCITEM_IS_INDEXED_BY
        sqlite3DbFree(db, pSource->a(0).u1.zIndexedBy)
    ElseIf (sourceFlags And DELETE_SRCITEM_IS_CTE) <> 0 AndAlso _
           pSource->a(0).u2.pCteUse <> 0 Then
        ' CteUse begins with nUse; the duplicate SELECT adds one reference.
        Dim pUseCount As SQLITE_C_INT Ptr = _
            CPtr(SQLITE_C_INT Ptr, pSource->a(0).u2.pCteUse)
        pUseCount[0] += 1
    End If

    Dim pSelect As SqliteSelect Ptr = sqlite3SelectNew(pParse, _
        pSelectList, pSelectSource, pWhere, 0, 0, pOrderBy, _
        DELETE_SF_INCLUDE_HIDDEN, pLimit)
    Dim pInClause As SqliteExpr Ptr = sqlite3PExpr(pParse, TK_IN, pLeft, 0)
    sqlite3PExprAddSelect(pParse, pInClause, pSelect)
    Return pInClause
End Function

/' end of sqlite3_delete_helpers.bas '/
