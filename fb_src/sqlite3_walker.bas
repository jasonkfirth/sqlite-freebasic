/'
    Project: SQLite FreeBASIC port

    File: sqlite3_walker.bas

    Purpose:

        Walk Expr and SELECT trees with SQLite's pre-order callback rules.

    Responsibilities:

        - Support continue, prune, and abort results from walker callbacks.
        - Traverse expression children, expression lists, and compound SELECTs.
        - Visit subqueries and table-valued-function arguments in FROM lists.
        - Walk window expressions when the window subsystem is enabled.

    This file intentionally does NOT contain:

    - The callback implementations used for name resolution or rewriting.
        - CTE definition creation or SELECT expansion callbacks.
'/ 

#lang "fb"
#include once "sqlite3_walker.bi"
#include once "sqlite3_constants.bi"

Private Const SQLITE_SRCITEM_IS_SUBQUERY As SQLITE_C_UINT = &H0004
Private Const SQLITE_SRCITEM_IS_TABFUNC As SQLITE_C_UINT = &H0008

Private Function sqlite3WalkerAbortCode(ByVal resultCode As SQLITE_C_INT) As SQLITE_C_INT
    Return resultCode And WRC_ABORT
End Function

#ifndef SQLITE_OMIT_WINDOWFUNC
Private Function walkWindowList CDecl Alias "walkWindowList" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pList As SqliteWalkerWindow Ptr, _
    ByVal oneWindowOnly As SQLITE_C_INT _
) As SQLITE_C_INT
    Dim pWindow As SqliteWalkerWindow Ptr = pList
    While pWindow <> 0
        If sqlite3WalkExprList(pWalker, pWindow->pOrderBy) <> WRC_CONTINUE Then Return WRC_ABORT
        If sqlite3WalkExprList(pWalker, pWindow->pPartition) <> WRC_CONTINUE Then Return WRC_ABORT
        If sqlite3WalkExpr(pWalker, pWindow->pFilter) <> WRC_CONTINUE Then Return WRC_ABORT
        If sqlite3WalkExpr(pWalker, pWindow->pStart) <> WRC_CONTINUE Then Return WRC_ABORT
        If sqlite3WalkExpr(pWalker, pWindow->pEnd) <> WRC_CONTINUE Then Return WRC_ABORT
        If oneWindowOnly <> 0 Then Exit While
        pWindow = pWindow->pNextWin
    Wend
    Return WRC_CONTINUE
End Function
#endif

Function sqlite3WalkExprNN CDecl Alias "sqlite3WalkExprNN" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pExprArgument As SqliteExpr Ptr _
) As SQLITE_C_INT Export
    If pWalker = 0 OrElse pExprArgument = 0 OrElse pWalker->xExprCallback = 0 Then _
        Return WRC_ABORT

    Dim pExpr As SqliteExpr Ptr = pExprArgument
    Do
        Dim callbackResult As SQLITE_C_INT = _
            pWalker->xExprCallback(pWalker, pExpr)
        If callbackResult <> WRC_CONTINUE Then _
            Return sqlite3WalkerAbortCode(callbackResult)

        If (pExpr->flags And (EP_TokenOnly Or EP_Leaf)) = 0 Then
            If pExpr->pLeft <> 0 Then
                Dim rc As SQLITE_C_INT = sqlite3WalkExprNN( _
                    pWalker, CPtr(SqliteExpr Ptr, pExpr->pLeft))
                If rc <> WRC_CONTINUE Then Return WRC_ABORT
            End If

            If pExpr->pRight <> 0 Then
                pExpr = CPtr(SqliteExpr Ptr, pExpr->pRight)
                Continue Do
            ElseIf (pExpr->flags And EP_xIsSelect) <> 0 Then
                Dim pSelect As SqliteSelect Ptr = CPtr(SqliteSelect Ptr, pExpr->x.pSelect)
                If sqlite3WalkSelect(pWalker, pSelect) <> WRC_CONTINUE Then Return WRC_ABORT
            Else
                If pExpr->x.pList <> 0 Then
                    Dim pList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pExpr->x.pList)
                    If sqlite3WalkExprList(pWalker, pList) <> WRC_CONTINUE Then Return WRC_ABORT
                End If
#ifndef SQLITE_OMIT_WINDOWFUNC
                If (pExpr->flags And EP_WinFunc) <> 0 Then
                    If walkWindowList(pWalker, _
                        CPtr(SqliteWalkerWindow Ptr, pExpr->y.pWin), 1) <> WRC_CONTINUE Then
                        Return WRC_ABORT
                    End If
                End If
#endif
            End If
        End If
        Exit Do
    Loop
    Return WRC_CONTINUE
End Function

Function sqlite3WalkExpr CDecl Alias "sqlite3WalkExpr" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT Export
    If pExpr = 0 Then Return WRC_CONTINUE
    Return sqlite3WalkExprNN(pWalker, pExpr)
End Function

Function sqlite3WalkExprList CDecl Alias "sqlite3WalkExprList" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pList As SqliteExprList Ptr _
) As SQLITE_C_INT Export
    If pList = 0 Then Return WRC_CONTINUE
    If pWalker = 0 OrElse pList->nExpr < 0 OrElse pList->nAlloc < pList->nExpr Then _
        Return WRC_ABORT
    For itemIndex As SQLITE_C_INT = 0 To pList->nExpr - 1
        Dim pExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pList->a(itemIndex).pExpr)
        If sqlite3WalkExpr(pWalker, pExpr) <> WRC_CONTINUE Then Return WRC_ABORT
    Next
    Return WRC_CONTINUE
End Function

Sub sqlite3WalkWinDefnDummyCallback CDecl Alias "sqlite3WalkWinDefnDummyCallback" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) Export
    ' The callback's presence asks sqlite3WalkSelectExpr to visit window terms.
    If pWalker <> 0 AndAlso pSelect <> 0 Then Exit Sub
End Sub

Function sqlite3WalkSelectExpr CDecl Alias "sqlite3WalkSelectExpr" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) As SQLITE_C_INT Export
    If pWalker = 0 OrElse pSelect = 0 Then Return WRC_ABORT
    If sqlite3WalkExprList(pWalker, CPtr(SqliteExprList Ptr, pSelect->pEList)) <> WRC_CONTINUE Then Return WRC_ABORT
    If sqlite3WalkExpr(pWalker, CPtr(SqliteExpr Ptr, pSelect->pWhere)) <> WRC_CONTINUE Then Return WRC_ABORT
    If sqlite3WalkExprList(pWalker, CPtr(SqliteExprList Ptr, pSelect->pGroupBy)) <> WRC_CONTINUE Then Return WRC_ABORT
    If sqlite3WalkExpr(pWalker, CPtr(SqliteExpr Ptr, pSelect->pHaving)) <> WRC_CONTINUE Then Return WRC_ABORT
    If sqlite3WalkExprList(pWalker, CPtr(SqliteExprList Ptr, pSelect->pOrderBy)) <> WRC_CONTINUE Then Return WRC_ABORT
    If sqlite3WalkExpr(pWalker, CPtr(SqliteExpr Ptr, pSelect->pLimit)) <> WRC_CONTINUE Then Return WRC_ABORT
#ifndef SQLITE_OMIT_WINDOWFUNC
    If pSelect->pWinDefn <> 0 Then
        Dim visitWindowTerms As SQLITE_C_INT = 0
        If pWalker->xSelectCallback2 = @sqlite3WalkWinDefnDummyCallback Then
            visitWindowTerms = 1
        ElseIf pWalker->xSelectCallback2 = @sqlite3SelectPopWith Then
            visitWindowTerms = 1
        ElseIf pWalker->pParse <> 0 AndAlso _
               pWalker->pParse->eParseMode >= PARSE_MODE_RENAME Then
            visitWindowTerms = 1
        End If
        If visitWindowTerms <> 0 Then
            If walkWindowList(pWalker, _
                CPtr(SqliteWalkerWindow Ptr, pSelect->pWinDefn), 0) <> WRC_CONTINUE Then _
                Return WRC_ABORT
        End If
    End If
#endif
    Return WRC_CONTINUE
End Function

Function sqlite3WalkSelectFrom CDecl Alias "sqlite3WalkSelectFrom" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) As SQLITE_C_INT Export
    If pWalker = 0 OrElse pSelect = 0 Then Return WRC_ABORT
    If pSelect->pSrc = 0 Then Return WRC_CONTINUE

    Dim pSourceList As SqliteSrcListHeader Ptr = _
        CPtr(SqliteSrcListHeader Ptr, pSelect->pSrc)
    If pSourceList->nSrc < 0 OrElse pSourceList->nAlloc < pSourceList->nSrc Then _
        Return WRC_ABORT
    If pSourceList->nSrc = 0 Then Return WRC_CONTINUE

    Dim pFirstItem As SqliteSrcItem Ptr = CPtr(SqliteSrcItem Ptr, _
        CPtr(UByte Ptr, pSourceList) + SizeOf(SqliteSrcListHeader))
    For itemIndex As SQLITE_C_INT = 0 To pSourceList->nSrc - 1
        Dim pItem As SqliteSrcItem Ptr = @pFirstItem[itemIndex]
        Dim flagWord As SQLITE_C_UINT = pItem->fg.flags
        If (flagWord And SQLITE_SRCITEM_IS_SUBQUERY) <> 0 Then
            If pItem->u4.pSubq = 0 Then Return WRC_ABORT
            Dim pSubquery As SqliteWalkerSubquery Ptr = _
                CPtr(SqliteWalkerSubquery Ptr, pItem->u4.pSubq)
            If sqlite3WalkSelect(pWalker, pSubquery->pSelect) <> WRC_CONTINUE Then _
                Return WRC_ABORT
        End If
        If (flagWord And SQLITE_SRCITEM_IS_TABFUNC) <> 0 AndAlso pItem->u1.pFuncArg <> 0 Then
            If sqlite3WalkExprList(pWalker, _
                CPtr(SqliteExprList Ptr, pItem->u1.pFuncArg)) <> WRC_CONTINUE Then Return WRC_ABORT
        End If
    Next
    Return WRC_CONTINUE
End Function

Function sqlite3WalkSelect CDecl Alias "sqlite3WalkSelect" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelectArgument As SqliteSelect Ptr _
) As SQLITE_C_INT Export
    If pSelectArgument = 0 Then Return WRC_CONTINUE
    If pWalker = 0 Then Return WRC_ABORT
    If pWalker->xSelectCallback = 0 Then Return WRC_CONTINUE

    Dim pSelect As SqliteSelect Ptr = pSelectArgument
    Do While pSelect <> 0
        Dim callbackResult As SQLITE_C_INT = _
            pWalker->xSelectCallback(pWalker, pSelect)
        If callbackResult <> WRC_CONTINUE Then _
            Return sqlite3WalkerAbortCode(callbackResult)
        If sqlite3WalkSelectExpr(pWalker, pSelect) <> WRC_CONTINUE OrElse _
           sqlite3WalkSelectFrom(pWalker, pSelect) <> WRC_CONTINUE Then Return WRC_ABORT
        If pWalker->xSelectCallback2 <> 0 Then _
            pWalker->xSelectCallback2(pWalker, pSelect)
        pSelect = CPtr(SqliteSelect Ptr, pSelect->pPrior)
    Loop
    Return WRC_CONTINUE
End Function

Function sqlite3WalkerDepthIncrease CDecl Alias "sqlite3WalkerDepthIncrease" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) As SQLITE_C_INT Export
    If pWalker = 0 OrElse pWalker->walkerDepth = &H7FFFFFFF Then Return WRC_ABORT
    pWalker->walkerDepth += 1
    Return WRC_CONTINUE
End Function

Sub sqlite3WalkerDepthDecrease CDecl Alias "sqlite3WalkerDepthDecrease" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) Export
    If pWalker = 0 OrElse pWalker->walkerDepth <= 0 Then Exit Sub
    pWalker->walkerDepth -= 1
End Sub

Function sqlite3ExprWalkNoop CDecl Alias "sqlite3ExprWalkNoop" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT Export
    Return WRC_CONTINUE
End Function

Function sqlite3SelectWalkNoop CDecl Alias "sqlite3SelectWalkNoop" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) As SQLITE_C_INT Export
    Return WRC_CONTINUE
End Function

/' end of sqlite3_walker.bas '/
