/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_select_constant_propagation.bas

    Purpose:

        Port the WHERE-clause constant propagation helpers from select.c.

    Responsibilities:

        - Collect top-level column-equals-constant constraints.
        - Respect comparison affinity, collations, join boundaries, and OOM state.
        - Mark matching column expressions with their replacement values.

    This file intentionally does NOT contain:

        - SELECT planning or WHERE-loop generation, which live in sqlite3_select.bas.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_walker.bi"
#include once "sqlite3_debug_assert.bi"

Declare Function sqlite3ExprAffinity CDecl Alias "sqlite3ExprAffinity" ( _
    ByVal pExpr As Const SqliteExpr Ptr _
) As Byte
Declare Function sqlite3ExprCanReturnSubtype CDecl Alias "sqlite3ExprCanReturnSubtype" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT
Private Type SqliteWhereConst
    pParse As SqliteParseContext Ptr
    pOomFault As UByte Ptr
    nConst As SQLITE_C_INT
    nChng As SQLITE_C_INT
    bHasAffBlob As SQLITE_C_INT
    mExcludeOn As u32
    apExpr As SqliteExpr Ptr Ptr
End Type

Private Sub sqlite3SelectConstAssert( _
    ByVal condition As SQLITE_C_INT, _
    ByVal zExpression As Const ZString Ptr _
)
#ifdef SQLITE_DEBUG
    If condition = 0 Then sqlite3DebugAssert(zExpression)
#else
    If condition = 0 Then Exit Sub
#endif
End Sub

Private Sub constInsert CDecl Alias "constInsert" ( _
    ByVal pConst As SqliteWhereConst Ptr, _
    ByVal pColumn As SqliteExpr Ptr, _
    ByVal pValue As SqliteExpr Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
)
    If pConst = 0 OrElse pConst->pParse = 0 OrElse pConst->pParse->db = 0 OrElse _
       pColumn = 0 OrElse pValue = 0 OrElse pExpr = 0 Then Exit Sub

    sqlite3SelectConstAssert(pColumn->op = TK_COLUMN, _
        StrPtr("constant propagation key is a column"))
    sqlite3SelectConstAssert( _
        sqlite3ExprIsConstant(pConst->pParse, pValue) <> 0, _
        StrPtr("constant propagation value is constant"))
    If pColumn->op <> TK_COLUMN OrElse _
       sqlite3ExprIsConstant(pConst->pParse, pValue) = 0 Then Exit Sub

    If (pColumn->flags And EP_FixedCol) <> 0 Then Exit Sub
    ' Expression affinity returns zero when a value has no affinity. The
    ' SQLITE_AFF_NONE constant is a tagged column-affinity value, not zero.
    If sqlite3ExprAffinity(pValue) <> 0 Then Exit Sub
    If sqlite3IsBinary(sqlite3ExprCompareCollSeq(pConst->pParse, pExpr)) = 0 Then _
        Exit Sub
    If sqlite3ExprCanReturnSubtype(pConst->pParse, pValue) <> 0 Then Exit Sub

    ' A column may appear only once in this list. Keeping the first constant
    ' avoids propagating contradictory predicates in source order.
    For entryIndex As SQLITE_C_INT = 0 To pConst->nConst - 1
        Dim pExistingColumn As SqliteExpr Ptr = pConst->apExpr[entryIndex * 2]
        sqlite3SelectConstAssert( _
            pExistingColumn <> 0 AndAlso pExistingColumn->op = TK_COLUMN, _
            StrPtr("stored constant propagation key is a column"))
        If pExistingColumn = 0 Then Exit Sub
        If pExistingColumn->iTable = pColumn->iTable AndAlso _
           pExistingColumn->iColumn = pColumn->iColumn Then Exit Sub
    Next

    sqlite3SelectConstAssert(SQLITE_AFF_NONE < SQLITE_AFF_BLOB, _
        StrPtr("NONE affinity sorts before BLOB affinity"))
    If sqlite3ExprAffinity(pColumn) <= SQLITE_AFF_BLOB Then _
        pConst->bHasAffBlob = 1

    pConst->nConst += 1
    Dim nPointerCount As sqlite3_uint64 = _
        CULngInt(pConst->nConst) * 2ULL
    Dim nByte As sqlite3_uint64 = _
        nPointerCount * SizeOf(SqliteExpr Ptr)
    pConst->apExpr = CPtr(SqliteExpr Ptr Ptr, sqlite3DbReallocOrFree( _
        pConst->pParse->db, pConst->apExpr, nByte))
    If pConst->apExpr = 0 Then
        pConst->nConst = 0
    Else
        pConst->apExpr[pConst->nConst * 2 - 2] = pColumn
        pConst->apExpr[pConst->nConst * 2 - 1] = pValue
    End If
End Sub

Private Sub findConstInWhere CDecl Alias "findConstInWhere" ( _
    ByVal pConst As SqliteWhereConst Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
)
    If pConst = 0 OrElse pExpr = 0 Then Exit Sub
    If (pExpr->flags And pConst->mExcludeOn) <> 0 Then Exit Sub

    If pExpr->op = TK_AND Then
        findConstInWhere(pConst, CPtr(SqliteExpr Ptr, pExpr->pRight))
        findConstInWhere(pConst, CPtr(SqliteExpr Ptr, pExpr->pLeft))
        Exit Sub
    End If
    If pExpr->op <> TK_EQ Then Exit Sub

    Dim pRight As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pExpr->pRight)
    Dim pLeft As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pExpr->pLeft)
    sqlite3SelectConstAssert(pRight <> 0, _
        StrPtr("equality expression has a right operand"))
    sqlite3SelectConstAssert(pLeft <> 0, _
        StrPtr("equality expression has a left operand"))
    If pRight = 0 OrElse pLeft = 0 Then Exit Sub

    If pRight->op = TK_COLUMN AndAlso _
       sqlite3ExprIsConstant(pConst->pParse, pLeft) <> 0 Then
        constInsert(pConst, pRight, pLeft, pExpr)
    End If
    If pLeft->op = TK_COLUMN AndAlso _
       sqlite3ExprIsConstant(pConst->pParse, pRight) <> 0 Then
        constInsert(pConst, pLeft, pRight, pExpr)
    End If
End Sub

Private Function propagateConstantExprRewriteOne CDecl Alias "propagateConstantExprRewriteOne" ( _
    ByVal pConst As SqliteWhereConst Ptr, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal ignoreBlobAffinity As SQLITE_C_INT _
) As SQLITE_C_INT
    If pConst = 0 OrElse pExpr = 0 Then Return WRC_CONTINUE
    If pConst->pOomFault = 0 OrElse pConst->pOomFault[0] <> 0 Then _
        Return WRC_PRUNE
    If pExpr->op <> TK_COLUMN Then Return WRC_CONTINUE
    If (pExpr->flags And (EP_FixedCol Or pConst->mExcludeOn)) <> 0 Then _
        Return WRC_CONTINUE

    If pConst->nConst < 0 OrElse _
       (pConst->nConst > 0 AndAlso pConst->apExpr = 0) Then Return WRC_PRUNE
    For entryIndex As SQLITE_C_INT = 0 To pConst->nConst - 1
        Dim pColumn As SqliteExpr Ptr = pConst->apExpr[entryIndex * 2]
        If pColumn = 0 Then Return WRC_PRUNE
        If pColumn = pExpr Then Continue For
        If pColumn->iTable <> pExpr->iTable Then Continue For
        If pColumn->iColumn <> pExpr->iColumn Then Continue For

        sqlite3SelectConstAssert(SQLITE_AFF_NONE < SQLITE_AFF_BLOB, _
            StrPtr("NONE affinity sorts before BLOB affinity"))
        If ignoreBlobAffinity <> 0 AndAlso _
           sqlite3ExprAffinity(pColumn) <= SQLITE_AFF_BLOB Then Exit For

        pConst->nChng += 1
        pExpr->flags = (pExpr->flags And Not EP_Leaf) Or EP_FixedCol
        sqlite3SelectConstAssert(pExpr->pLeft = 0, _
            StrPtr("fixed column has no prior replacement expression"))
        If pExpr->pLeft <> 0 Then Return WRC_PRUNE

        pExpr->pLeft = sqlite3ExprDup( _
            pConst->pParse->db, pConst->apExpr[entryIndex * 2 + 1], 0)
        If pConst->pParse->db->mallocFailed <> 0 OrElse pExpr->pLeft = 0 Then _
            Return WRC_PRUNE
        Exit For
    Next
    Return WRC_PRUNE
End Function

Private Function propagateConstantExprRewrite CDecl Alias "propagateConstantExprRewrite" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT
    If pWalker = 0 OrElse pExpr = 0 Then Return WRC_PRUNE
    Dim pConst As SqliteWhereConst Ptr = _
        CPtr(SqliteWhereConst Ptr, pWalker->u.pConst)
    If pConst = 0 Then Return WRC_PRUNE

    sqlite3SelectConstAssert(TK_GT = TK_EQ + 1, _
        StrPtr("comparison token ordering includes greater-than"))
    sqlite3SelectConstAssert(TK_LE = TK_EQ + 2, _
        StrPtr("comparison token ordering includes less-than-or-equal"))
    sqlite3SelectConstAssert(TK_LT = TK_EQ + 3, _
        StrPtr("comparison token ordering includes less-than"))
    sqlite3SelectConstAssert(TK_GE = TK_EQ + 4, _
        StrPtr("comparison token ordering includes greater-than-or-equal"))

    If pConst->bHasAffBlob <> 0 Then
        If (pExpr->op >= TK_EQ AndAlso pExpr->op <= TK_GE) OrElse _
           pExpr->op = TK_IS Then
            propagateConstantExprRewriteOne( _
                pConst, CPtr(SqliteExpr Ptr, pExpr->pLeft), 0)
            If pConst->pOomFault = 0 OrElse pConst->pOomFault[0] <> 0 Then _
                Return WRC_PRUNE
            If pExpr->pLeft = 0 OrElse _
               sqlite3ExprAffinity(CPtr(SqliteExpr Ptr, pExpr->pLeft)) <> _
                   SQLITE_AFF_TEXT Then
                propagateConstantExprRewriteOne( _
                    pConst, CPtr(SqliteExpr Ptr, pExpr->pRight), 0)
            End If
        End If
    End If
    Return propagateConstantExprRewriteOne( _
        pConst, pExpr, pConst->bHasAffBlob)
End Function

Function propagateConstants CDecl Alias "propagateConstants" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->db = 0 OrElse pSelect = 0 Then Return 0

    Dim x As SqliteWhereConst
    x.pParse = pParse
    x.pOomFault = @pParse->db->mallocFailed
    Dim nChanges As SQLITE_C_INT = 0
    Do
        x.nConst = 0
        x.nChng = 0
        x.apExpr = 0
        x.bHasAffBlob = 0
        If pSelect->pSrc <> 0 AndAlso pSelect->pSrc->nSrc > 0 AndAlso _
           (pSelect->pSrc->a(0).fg.jointype And JT_LTORJ) <> 0 Then
            x.mExcludeOn = EP_InnerON Or EP_OuterON
        Else
            x.mExcludeOn = EP_OuterON
        End If

        findConstInWhere(@x, pSelect->pWhere)
        If x.nConst > 0 Then
            Dim walker As SqliteWalker
            walker.pParse = pParse
            walker.xExprCallback = CPtr( _
                SqliteWalkerExprCallback, ProcPtr(propagateConstantExprRewrite))
            walker.xSelectCallback = CPtr( _
                SqliteWalkerSelectCallback, ProcPtr(sqlite3SelectWalkNoop))
            walker.xSelectCallback2 = 0
            walker.walkerDepth = 0
            walker.eCode = 0
            walker.mWFlags = 0
            walker.u.p = 0
            walker.u.pConst = @x
            sqlite3WalkExpr(@walker, pSelect->pWhere)
            sqlite3DbFree(pParse->db, x.apExpr)
            nChanges += x.nChng
        End If
    Loop While x.nChng <> 0
    Return nChanges
End Function

/' end of sqlite3_select_constant_propagation.bas '/
