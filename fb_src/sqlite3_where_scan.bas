/'
    Project: SQLite FreeBASIC port

    File: sqlite3_where_scan.bas

    Purpose:

        Find WHERE terms that can drive an index or planner shortcut.

    Responsibilities:

        - Initialize a scanner over nested WHERE-clause terms.
        - Follow equality terms to equivalent cursor and column pairs.
        - Match operator masks, index affinity, and collation requirements.

    This file intentionally does NOT contain:

        - WHERE-clause construction or query-plan selection.
'/

#lang "fb"

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_tokens.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_where_types.bi"

Declare Function sqlite3IndexAffinityOk CDecl Alias "sqlite3IndexAffinityOk" ( _
    ByVal pExpr As Any Ptr, _
    ByVal affinity As Byte _
) As SQLITE_C_INT
Declare Function sqlite3ExprAffinity CDecl Alias "sqlite3ExprAffinity" ( _
    ByVal pExpr As Any Ptr _
) As Byte
Declare Function sqlite3StrICmp CDecl Alias "sqlite3StrICmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT

/' ------------------------------------------------------------------------- '/
/' WHERE operator bits used by the scanner                                   '/
/' ------------------------------------------------------------------------- '/

Private Const WHERE_XN_ROWID As SQLITE_C_INT = -1
Private Const WHERE_XN_EXPR As SQLITE_C_INT = -2
Private Const WHERE_WO_IN As u16 = &H0001
Private Const WHERE_WO_EQ As u16 = &H0002
Private Const WHERE_WO_IS As u16 = &H0080
Private Const WHERE_WO_ISNULL As u16 = &H0100
Private Const WHERE_WO_OR As u16 = &H0200
Private Const WHERE_WO_AND As u16 = &H0400
Private Const WHERE_WO_EQUIV As u16 = &H0800
Private Const WHERE_SCAN_SLOT_COUNT As Long = 11

/' ------------------------------------------------------------------------- '/
/' Index affinity and collation matching                                      '/
/' ------------------------------------------------------------------------- '/

Private Function indexInAffinityOk CDecl Alias "indexInAffinityOk" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pTerm As SqliteWhereTerm Ptr, _
    ByVal indexAffinity As u8 _
) As Const ZString Ptr
    If pParse = 0 OrElse pTerm = 0 OrElse pTerm->pExpr = 0 Then Return 0
    If (pTerm->eOperator And WHERE_WO_IN) = 0 Then Return 0

    Dim pExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pTerm->pExpr)
    If sqlite3ExprIsVector(CPtr(Const SqliteExpr Ptr, pExpr->pLeft)) Then
        Dim pLeft As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pExpr->pLeft)
        Dim pLeftList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pLeft->x.pList)
        Dim pSelect As SqliteSelect Ptr = CPtr(SqliteSelect Ptr, pExpr->x.pSelect)
        If pLeftList = 0 OrElse pSelect = 0 Then Return 0

        Dim fieldIndex As SQLITE_C_INT = pTerm->u.x.iField - 1
        Dim pRightList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pSelect->pEList)
        If fieldIndex < 0 OrElse fieldIndex >= pLeftList->nExpr OrElse _
           pRightList = 0 OrElse fieldIndex >= pRightList->nExpr Then Return 0

        Dim vectorExpr As SqliteExpr
        vectorExpr.flags = 0
        vectorExpr.op = TK_EQ
        vectorExpr.pLeft = pLeftList->a(fieldIndex).pExpr
        vectorExpr.pRight = pRightList->a(fieldIndex).pExpr
        pExpr = @vectorExpr
    End If

    If sqlite3IndexAffinityOk(CPtr(Any Ptr, pExpr), indexAffinity) = 0 Then Return 0
    Dim pCollation As sqlite3CollSeq Ptr = _
        sqlite3ExprCompareCollSeq(pParse, CPtr(Const SqliteExpr Ptr, pExpr))
    If pCollation Then Return CPtr(Const ZString Ptr, pCollation->zName)
    Return CPtr(Const ZString Ptr, StrPtr(!"BINARY"))
End Function

/' ------------------------------------------------------------------------- '/
/' Scanner initialization                                                     '/
/' ------------------------------------------------------------------------- '/

Private Function whereScanInitIndexExpr CDecl Alias "whereScanInitIndexExpr" ( _
    ByVal pScan As SqliteWhereScan Ptr _
) As SqliteWhereTerm Ptr
    If pScan = 0 OrElse pScan->pIdxExpr = 0 Then Return 0
    pScan->idxaff = sqlite3ExprAffinity(pScan->pIdxExpr)
    Return whereScanNext(pScan)
End Function

Function whereScanInit CDecl Alias "whereScanInit" ( _
    ByVal pScan As SqliteWhereScan Ptr, _
    ByVal pWhereClause As SqliteWhereClause Ptr, _
    ByVal cursorNumber As SQLITE_C_INT, _
    ByVal columnNumber As SQLITE_C_INT, _
    ByVal operatorMask As u32, _
    ByVal pIndex As SqliteIndex Ptr _
) As SqliteWhereTerm Ptr
    If pScan = 0 OrElse pWhereClause = 0 OrElse cursorNumber < 0 Then Return 0

    pScan->pOrigWC = pWhereClause
    pScan->pWC = pWhereClause
    pScan->pIdxExpr = 0
    pScan->idxaff = 0
    pScan->zCollName = 0
    pScan->opMask = operatorMask
    pScan->k = 0
    pScan->aiCur(0) = cursorNumber
    pScan->nEquiv = 1
    pScan->iEquiv = 1

    If pIndex Then
        If pIndex->pTable = 0 OrElse pIndex->aiColumn = 0 OrElse _
           columnNumber < 0 OrElse columnNumber >= pIndex->nColumn Then Return 0

        Dim pTable As SqliteTable Ptr = pIndex->pTable
        Dim indexColumn As SQLITE_C_INT = pIndex->aiColumn[columnNumber]
        If indexColumn = pTable->iPKey Then
            indexColumn = WHERE_XN_ROWID
        ElseIf indexColumn >= 0 Then
            If pTable->aCol = 0 OrElse indexColumn >= pTable->nCol Then Return 0
            pScan->idxaff = pTable->aCol[indexColumn].affinity
            If pIndex->azColl Then pScan->zCollName = pIndex->azColl[columnNumber]
        ElseIf indexColumn = WHERE_XN_EXPR Then
            If pIndex->aColExpr = 0 Then Return 0
            Dim pExprList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pIndex->aColExpr)
            If pExprList = 0 OrElse columnNumber >= pExprList->nExpr Then Return 0
            If pIndex->azColl Then pScan->zCollName = pIndex->azColl[columnNumber]
            pScan->pIdxExpr = pExprList->a(columnNumber).pExpr
            pScan->aiColumn(0) = WHERE_XN_EXPR
            Return whereScanInitIndexExpr(pScan)
        End If
        columnNumber = indexColumn
    ElseIf columnNumber = WHERE_XN_EXPR Then
        Return 0
    End If

    pScan->aiColumn(0) = columnNumber
    Return whereScanNext(pScan)
End Function

/' ------------------------------------------------------------------------- '/
/' Matching WHERE terms                                                      '/
/' ------------------------------------------------------------------------- '/

Function whereScanNext CDecl Alias "whereScanNext" ( _
    ByVal pScan As SqliteWhereScan Ptr _
) As SqliteWhereTerm Ptr
    If pScan = 0 OrElse pScan->nEquiv = 0 OrElse _
       pScan->nEquiv > WHERE_SCAN_SLOT_COUNT OrElse _
       pScan->iEquiv = 0 OrElse pScan->iEquiv > pScan->nEquiv Then Return 0

    Dim pWhereClause As SqliteWhereClause Ptr = CPtr(SqliteWhereClause Ptr, pScan->pWC)
    Dim startTerm As SQLITE_C_INT = pScan->k
    While 1
        If pScan->iEquiv = 0 OrElse pScan->iEquiv > pScan->nEquiv Then Return 0
        Dim equivalenceSlot As SQLITE_C_INT = pScan->iEquiv - 1
        Dim cursorNumber As SQLITE_C_INT = pScan->aiCur(equivalenceSlot)
        Dim columnNumber As Short = pScan->aiColumn(equivalenceSlot)

        Do While pWhereClause <> 0
            If pWhereClause->nTerm < 0 Then Return 0
            If pWhereClause->nTerm > 0 AndAlso pWhereClause->a = 0 Then Return 0

            Dim pTerms As SqliteWhereTerm Ptr = CPtr(SqliteWhereTerm Ptr, pWhereClause->a)
            For termIndex As SQLITE_C_INT = startTerm To pWhereClause->nTerm - 1
                Dim pTerm As SqliteWhereTerm Ptr = pTerms + termIndex
                If pTerm->leftCursor <> cursorNumber OrElse _
                   pTerm->u.x.leftColumn <> columnNumber Then Continue For
                If pTerm->pExpr = 0 Then Continue For

                Dim pExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pTerm->pExpr)
                If columnNumber = WHERE_XN_EXPR AndAlso _
                   sqlite3ExprCompareSkip(CPtr(SqliteExpr Ptr, pExpr->pLeft), _
                       CPtr(SqliteExpr Ptr, pScan->pIdxExpr), cursorNumber) <> 0 Then Continue For
                If pScan->iEquiv > 1 AndAlso (pExpr->flags And EP_OuterON) <> 0 Then Continue For

                If (pTerm->eOperator And WHERE_WO_EQUIV) <> 0 AndAlso _
                   pScan->nEquiv < WHERE_SCAN_SLOT_COUNT Then
                    Dim pRightExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pExpr->pRight)
                    If pRightExpr Then pRightExpr = sqlite3ExprSkipCollateAndLikely(pRightExpr)
                    If pRightExpr AndAlso pRightExpr->op = TK_COLUMN AndAlso _
                       (pRightExpr->flags And EP_FixedCol) = 0 Then
                        Dim equivalentSlot As SQLITE_C_INT = 0
                        While equivalentSlot < pScan->nEquiv
                            If pScan->aiCur(equivalentSlot) = pRightExpr->iTable AndAlso _
                               pScan->aiColumn(equivalentSlot) = pRightExpr->iColumn Then Exit While
                            equivalentSlot += 1
                        Wend
                        If equivalentSlot = pScan->nEquiv Then
                            pScan->aiCur(equivalentSlot) = pRightExpr->iTable
                            pScan->aiColumn(equivalentSlot) = pRightExpr->iColumn
                            pScan->nEquiv += 1
                        End If
                    End If
                End If

                If (pTerm->eOperator And pScan->opMask) = 0 Then Continue For

                If pScan->zCollName <> 0 AndAlso _
                   (pTerm->eOperator And WHERE_WO_ISNULL) = 0 Then
                    Dim pWhereInfo As SqliteWhereInfo Ptr = _
                        CPtr(SqliteWhereInfo Ptr, pWhereClause->pWInfo)
                    If pWhereInfo = 0 OrElse pWhereInfo->pParse = 0 Then Continue For
                    Dim pParse As SqliteParseContext Ptr = _
                        CPtr(SqliteParseContext Ptr, pWhereInfo->pParse)
                    Dim zCollationName As Const ZString Ptr = 0

                    If (pTerm->eOperator And WHERE_WO_IN) <> 0 Then
                        zCollationName = indexInAffinityOk(pParse, pTerm, pScan->idxaff)
                        If zCollationName = 0 Then Continue For
                    Else
                        If sqlite3IndexAffinityOk(CPtr(Any Ptr, pExpr), pScan->idxaff) = 0 Then Continue For
                        Dim pCollation As sqlite3CollSeq Ptr = _
                            sqlite3ExprCompareCollSeq(pParse, CPtr(Const SqliteExpr Ptr, pExpr))
                        If pCollation Then
                            zCollationName = CPtr(Const ZString Ptr, pCollation->zName)
                        Else
                            zCollationName = CPtr(Const ZString Ptr, StrPtr(!"BINARY"))
                        End If
                    End If
                    If sqlite3StrICmp(zCollationName, pScan->zCollName) <> 0 Then Continue For
                End If

                If (pTerm->eOperator And (WHERE_WO_EQ Or WHERE_WO_IS)) <> 0 Then
                    Dim pRightExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pExpr->pRight)
                    If pRightExpr AndAlso pRightExpr->op = TK_COLUMN AndAlso _
                       pRightExpr->iTable = pScan->aiCur(0) AndAlso _
                       pRightExpr->iColumn = pScan->aiColumn(0) Then Continue For
                End If

                pScan->pWC = pWhereClause
                pScan->k = termIndex + 1
                Return pTerm
            Next

            pWhereClause = CPtr(SqliteWhereClause Ptr, pWhereClause->pOuter)
            startTerm = 0
        Loop

        If pScan->iEquiv >= pScan->nEquiv Then Exit While
        pWhereClause = CPtr(SqliteWhereClause Ptr, pScan->pOrigWC)
        startTerm = 0
        pScan->iEquiv += 1
    Wend
    Return 0
End Function

/' end of sqlite3_where_scan.bas '/
