/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_values.bas

    Purpose:

        Build the SELECT representation and VDBE coroutine for multi-row
        VALUES clauses.

    Responsibilities:

        - Use a coroutine for eligible constant VALUES rows.
        - Fall back to a UNION ALL SELECT chain when coroutine evaluation is
          unsafe or unavailable.
        - Finish the VALUES coroutine after parsing the complete row list.

    This file intentionally does NOT contain:

        - INSERT row generation or compound SELECT execution.
'/ 

#lang "fb"
#include once "sqlite3_constants.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_walker.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_vdbe_core.bi"

' sqlite3Int.h's DBFLAG_SchemaKnownOk bit indicates that schema initialization
' has already completed for this connection.
Private Const SQLITE3_VALUES_DBFLAG_SCHEMA_KNOWN_OK As u32 = &H0010

Declare Function sqlite3ExprAffinity CDecl Alias "sqlite3ExprAffinity" ( _
    ByVal pExpr As Const SqliteExpr Ptr _
) As Byte
Declare Function sqlite3ReadSchema CDecl Alias "sqlite3ReadSchema" ( _
    ByVal pParse As SqliteParseContext Ptr _
) As SQLITE_C_INT
Declare Function sqlite3SrcItemAttachSubquery CDecl Alias "sqlite3SrcItemAttachSubquery" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pItem As SqliteSrcItem Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal amend As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Sub sqlite3SelectDestInit CDecl Alias "sqlite3SelectDestInit" ( _
    ByVal pDestination As SqliteSelectDest Ptr, _
    ByVal destinationType As SQLITE_C_INT, _
    ByVal destinationRegister As SQLITE_C_INT _
)
Declare Function sqlite3ExprCodeExprList CDecl Alias "sqlite3ExprCodeExprList" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pList As SqliteExprList Ptr, _
    ByVal targetRegister As SQLITE_C_INT, _
    ByVal onError As SQLITE_C_INT, _
    ByVal doHardCopy As UByte _
) As SQLITE_C_INT
Declare Sub sqlite3SelectWrongNumTermsError CDecl Alias "sqlite3SelectWrongNumTermsError" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
)

Private Function sqlite3ValuesExprListIsNoAffinity( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pList As SqliteExprList Ptr _
) As SQLITE_C_INT
    If pParse = 0 OrElse pList = 0 Then Return 0
    If sqlite3ExprListIsConstant(pParse, pList, 0) = 0 Then Return 0

    For expressionIndex As SQLITE_C_INT = 0 To pList->nExpr - 1
        Dim pExpr As SqliteExpr Ptr = pList->a(expressionIndex).pExpr
        If pExpr = 0 Then Return 0
        If sqlite3ExprAffinity(pExpr) <> 0 Then Return 0
    Next
    Return 1
End Function

Sub sqlite3MultiValuesEnd CDecl Alias "sqlite3MultiValuesEnd" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pValues As SqliteSelect Ptr _
)
    If pParse = 0 OrElse pValues = 0 OrElse pValues->pSrc = 0 OrElse _
       pValues->pSrc->nSrc <= 0 OrElse pParse->pVdbe = 0 Then Exit Sub

    Dim pItem As SqliteSrcItem Ptr = @pValues->pSrc->a(0)
    If (pItem->fg.flags And SRCITEM_IS_SUBQUERY) = 0 Then Exit Sub
    Dim pSubquery As SqliteSubquery Ptr = pItem->u4.pSubq
    If pSubquery = 0 OrElse pSubquery->regReturn <= 0 OrElse _
       pSubquery->addrFillSub <= 0 Then Exit Sub

    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pParse->pVdbe)
    sqlite3VdbeEndCoroutine(pVdbe, pSubquery->regReturn)
    sqlite3VdbeJumpHere(pVdbe, pSubquery->addrFillSub - 1)
End Sub

Function sqlite3MultiValues CDecl Alias "sqlite3MultiValues" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pLeft As SqliteSelect Ptr, _
    ByVal pRow As SqliteExprList Ptr _
) As SqliteSelect Ptr Export
    If pParse = 0 OrElse pParse->db = 0 Then Return 0
    If pLeft = 0 OrElse pRow = 0 OrElse pLeft->pSrc = 0 OrElse _
       pLeft->pEList = 0 Then
        If pLeft <> 0 Then sqlite3SelectDelete(pParse->db, pLeft)
        If pRow <> 0 Then sqlite3ExprListDelete(pParse->db, pRow)
        pParse->rc = SQLITE_ERROR
        Return 0
    End If

    Dim useUnionAllFallback As SQLITE_C_INT = 0
    If pParse->bHasWith <> 0 OrElse pParse->db->init.busy <> 0 OrElse _
       sqlite3ExprListIsConstant(pParse, pRow, 1) = 0 OrElse _
       (pLeft->pSrc->nSrc = 0 AndAlso _
        sqlite3ValuesExprListIsNoAffinity(pParse, pLeft->pEList) = 0) OrElse _
       pParse->eParseMode <> 0 Then
        useUnionAllFallback = 1
    End If

    If useUnionAllFallback <> 0 Then
        ' A VALUES row that cannot be evaluated through a coroutine becomes
        ' the next SELECT term in an ordinary UNION ALL chain.
        Dim selectFlags As u32 = SF_Values Or SF_MultiValue
        If pLeft->pSrc->nSrc > 0 Then
            sqlite3MultiValuesEnd(pParse, pLeft)
            selectFlags = SF_Values
        ElseIf pLeft->pPrior <> 0 Then
            selectFlags = selectFlags And pLeft->selFlags
        End If

        Dim pNext As SqliteSelect Ptr = sqlite3SelectNew( _
            pParse, pRow, 0, 0, 0, 0, 0, selectFlags, 0)
        pLeft->selFlags = pLeft->selFlags And Not SF_MultiValue
        If pNext <> 0 Then
            pNext->op = TK_ALL
            pNext->pPrior = pLeft
            Return pNext
        End If
        Return pLeft
    End If

    Dim pItem As SqliteSrcItem Ptr = 0
    If pLeft->pSrc->nSrc = 0 Then
        Dim pVdbe As SqliteVdbe Ptr = sqlite3GetVdbe(pParse)
        If pVdbe = 0 Then Return pLeft

        Dim pReturn As SqliteSelect Ptr = sqlite3SelectNew( _
            pParse, 0, 0, 0, 0, 0, 0, 0, 0)
        If (pParse->db->mDbFlags And _
            SQLITE3_VALUES_DBFLAG_SCHEMA_KNOWN_OK) = 0 Then
            sqlite3ReadSchema(pParse)
        End If
        If pReturn = 0 OrElse pReturn->pSrc = 0 Then Return pLeft

        pReturn->pSrc->nSrc = 1
        ' SelectNew allocates one trailing SrcItem for an empty source list.
        ' Keep the explicit capacity in sync with nSrc for the port's SELECT
        ' validation and later source-list growth.
        pReturn->pSrc->nAlloc = 1
        pReturn->pPrior = pLeft->pPrior
        pReturn->op = pLeft->op
        If pReturn->pPrior <> 0 Then pReturn->selFlags Or= SF_Values
        pLeft->pPrior = 0
        pLeft->op = TK_SELECT

        pItem = @pReturn->pSrc->a(0)
        If pItem->u1.zIndexedBy <> 0 OrElse _
           (pItem->fg.flags And SRCITEM_IS_TABFUNC) <> 0 Then
            sqlite3SelectDelete(pParse->db, pReturn)
            pParse->rc = SQLITE_CORRUPT
            Return pLeft
        End If
        pItem->fg.flags Or= SRCITEM_VIA_COROUTINE
        pItem->iCursor = -1
        pItem->u1.nRow = 2

        If sqlite3SrcItemAttachSubquery(pParse, pItem, pLeft, 0) <> 0 Then
            Dim pSubquery As SqliteSubquery Ptr = pItem->u4.pSubq
            If pSubquery = 0 OrElse pLeft->pEList->nExpr <= 0 OrElse _
               pParse->nMem > &H7FFFFFFF - pLeft->pEList->nExpr - 6 Then
                pParse->rc = SQLITE_TOOBIG
                pParse->nErr += 1
            Else
                pSubquery->addrFillSub = sqlite3VdbeCurrentAddr(pVdbe) + 1
                pParse->nMem += 1
                pSubquery->regReturn = pParse->nMem
                sqlite3VdbeAddOp3( _
                    pVdbe, OP_InitCoroutine, pSubquery->regReturn, 0, _
                    pSubquery->addrFillSub)

                Dim destination As SqliteSelectDest
                sqlite3SelectDestInit( _
                    @destination, SRT_Coroutine, pSubquery->regReturn)
                destination.iSdst = pParse->nMem + 3
                destination.nSdst = pLeft->pEList->nExpr
                pParse->nMem += 2 + destination.nSdst
                pLeft->selFlags Or= SF_MultiValue
                sqlite3Select(pParse, pLeft, @destination)
                pSubquery->regResult = destination.iSdst
            End If
        End If
        pLeft = pReturn
    Else
        pItem = @pLeft->pSrc->a(0)
        If pItem->u4.pSubq = 0 OrElse _
           (pItem->fg.flags And SRCITEM_IS_SUBQUERY) = 0 Then
            pParse->rc = SQLITE_CORRUPT
            Return pLeft
        End If
        If pItem->u1.nRow < &HFFFFFFFFUL Then pItem->u1.nRow += 1
    End If

    If pParse->nErr = 0 Then
        If pItem = 0 OrElse pItem->u4.pSubq = 0 Then
            pParse->rc = SQLITE_CORRUPT
            pParse->nErr += 1
        Else
            Dim pSubquery As SqliteSubquery Ptr = pItem->u4.pSubq
            If pSubquery->pSelect = 0 OrElse _
               pSubquery->pSelect->pEList = 0 OrElse _
               pSubquery->regReturn <= 0 OrElse pSubquery->regResult <= 0 Then
                pParse->rc = SQLITE_CORRUPT
                pParse->nErr += 1
            ElseIf pSubquery->pSelect->pEList->nExpr <> pRow->nExpr Then
                sqlite3SelectWrongNumTermsError(pParse, pSubquery->pSelect)
            Else
                sqlite3ExprCodeExprList( _
                    pParse, pRow, pSubquery->regResult, 0, 0)
                sqlite3VdbeAddOp1( _
                    CPtr(SqliteVdbe Ptr, pParse->pVdbe), _
                    OP_Yield, pSubquery->regReturn)
            End If
        End If
    End If

    sqlite3ExprListDelete(pParse->db, pRow)
    Return pLeft
End Function

/' end of sqlite3_values.bas '/
