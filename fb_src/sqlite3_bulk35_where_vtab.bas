/'
    Project: SQLite FreeBASIC port

    File: sqlite3_bulk35_where_vtab.bas

    Purpose:

        Build virtual-table constraint and ordering metadata from src/where.c.

    Responsibilities:

        - Mark constraints that can be offered to xBestIndex.
        - Allocate and populate the public index-info arrays and private tail.
        - Preserve outer-join, vector-comparison, collation, and DISTINCT rules.

    This file intentionally does NOT contain:

        - The planner's virtual-table loop selection or VDBE code generation.
        - A claim that compile acceptance establishes behavior parity.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_walker.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_vtab_types.bi"

Declare Function sqlite3ColumnColl CDecl Alias "sqlite3ColumnColl" ( _
    ByVal pColumn As SqliteColumn Ptr _
) As Const ZString Ptr
Declare Function sqlite3PrimaryKeyIndex CDecl Alias "sqlite3PrimaryKeyIndex" ( _
    ByVal pTable As SqliteTable Ptr _
) As SqliteIndex Ptr
Declare Function sqlite3_stricmp CDecl Alias "sqlite3_stricmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT

' These masks are the planner's internal WhereTerm and WhereControl bits.
Private Const VTA_TERM_OK As u16 = &H0040
Private Const VTA_TERM_VNULL As u16 = &H0080
Private Const VTA_TERM_SLICE As u16 = &H8000
Private Const VTA_WO_IN As u16 = &H0001
Private Const VTA_WO_EQ As u16 = &H0002
Private Const VTA_WO_GT As u16 = &H0004
Private Const VTA_WO_LE As u16 = &H0008
Private Const VTA_WO_LT As u16 = &H0010
Private Const VTA_WO_GE As u16 = &H0020
Private Const VTA_WO_AUX As u16 = &H0040
Private Const VTA_WO_IS As u16 = &H0080
Private Const VTA_WO_ISNULL As u16 = &H0100
Private Const VTA_WO_OR As u16 = &H0200
Private Const VTA_WO_AND As u16 = &H0400
Private Const VTA_WO_EQUIV As u16 = &H0800
Private Const VTA_WO_ALL As u16 = &H3FFF
Private Const VTA_WHERE_GROUPBY As u16 = &H0040
Private Const VTA_WHERE_DISTINCTBY As u16 = &H0080
Private Const VTA_WHERE_WANT_DISTINCT As u16 = &H0100
Private Const VTA_WHERE_SORTBYGROUP As u16 = &H0200
Private Const VTA_JOIN_OUTER_MASK As u8 = &H58
Private Const VTA_JOIN_LEFT_RIGHT_MASK As u8 = &H18
Private Const VTA_TABTYPE_VIRTUAL As u8 = TABTYP_VTAB
' rowidUsed follows fifteen earlier one-bit fields in SrcItem.fg.
Private Const VTA_SRC_ROWID_USED_MASK As u32 = &H00008000
Private Const VTA_BITMASK_BITS As SQLITE_C_INT = 64

Private Function vtabConstraintCompatibleWithOuterJoin( _
    ByVal pTerm As Const SqliteWhereTerm Ptr, _
    ByVal pSource As Const SqliteSrcItem Ptr _
) As SQLITE_C_INT
    If pTerm = 0 OrElse pSource = 0 OrElse pTerm->pExpr = 0 Then Return 0

    Dim pExpression As Const SqliteExpr Ptr = _
        CPtr(Const SqliteExpr Ptr, pTerm->pExpr)
    If (pExpression->flags And (EP_OuterON Or EP_InnerON)) = 0 OrElse _
       pExpression->w.iJoin <> pSource->iCursor Then Return 0
    If (pSource->fg.jointype And VTA_JOIN_LEFT_RIGHT_MASK) <> 0 AndAlso _
       (pExpression->flags And EP_InnerON) <> 0 Then Return 0
    Return 1
End Function

Private Function whereVtabMaskBit32(ByVal bitIndex As SQLITE_C_INT) As u32
    If bitIndex < 0 OrElse bitIndex > 31 Then Return 0
    Return CULng(1) Shl bitIndex
End Function

Private Function whereVtabMaskBit(ByVal bitIndex As SQLITE_C_INT) As sqlite3_uint64
    If bitIndex < 0 OrElse bitIndex >= VTA_BITMASK_BITS Then Return 0
    Return CULngInt(1) Shl bitIndex
End Function

Function allocateIndexInfo CDecl Alias "allocateIndexInfo" ( _
    ByVal pWhereInfo As SqliteWhereInfo Ptr, _
    ByVal pWhereClause As SqliteWhereClause Ptr, _
    ByVal unusableMask As sqlite3_uint64, _
    ByVal pSource As SqliteSrcItem Ptr, _
    ByVal pMaskNoOmit As u16 Ptr _
) As SqliteIndexInfo Ptr
    If pWhereInfo = 0 OrElse pWhereInfo->pParse = 0 OrElse _
       pWhereClause = 0 OrElse _
       pSource = 0 OrElse pMaskNoOmit = 0 Then Return 0

    Dim pParse As SqliteParseContext Ptr = _
        CPtr(SqliteParseContext Ptr, pWhereInfo->pParse)
    If pParse->db = 0 Then Return 0
    Dim pTable As SqliteTable Ptr = CPtr(SqliteTable Ptr, pSource->pSTab)
    If pTable = 0 OrElse pTable->eTabType <> VTA_TABTYPE_VIRTUAL Then Return 0

    Dim termCount As SQLITE_C_INT = 0
    Dim maskNoOmit As u16 = 0
    Dim pClause As SqliteWhereClause Ptr = pWhereClause
    While pClause <> 0
        If pClause->nTerm < 0 Then Return 0
        Dim pTerm As SqliteWhereTerm Ptr = CPtr(SqliteWhereTerm Ptr, pClause->a)
        If pClause->nTerm > 0 AndAlso pTerm = 0 Then Return 0
        For termIndex As SQLITE_C_INT = 0 To pClause->nTerm - 1
            pTerm->wtFlags = pTerm->wtFlags And Not VTA_TERM_OK
            If pTerm->leftCursor = pSource->iCursor AndAlso _
               (pTerm->prereqRight And unusableMask) = 0 AndAlso _
               (pTerm->eOperator And Not VTA_WO_EQUIV) <> 0 AndAlso _
               (pTerm->wtFlags And VTA_TERM_VNULL) = 0 Then
                Dim isOuterConstraint As SQLITE_C_INT = 1
                If (pSource->fg.jointype And VTA_JOIN_OUTER_MASK) <> 0 Then
                    isOuterConstraint = vtabConstraintCompatibleWithOuterJoin( _
                        pTerm, pSource)
                End If
                If isOuterConstraint <> 0 Then
                    If termCount >= SQLITE_MAX_LENGTH Then Return 0
                    termCount += 1
                    pTerm->wtFlags = pTerm->wtFlags Or VTA_TERM_OK
                End If
            End If
            pTerm += 1
        Next
        pClause = CPtr(SqliteWhereClause Ptr, pClause->pOuter)
    Wend

    Dim pOrderBy As SqliteExprList Ptr = _
        CPtr(SqliteExprList Ptr, pWhereInfo->pOrderBy)
    Dim orderTermCount As SQLITE_C_INT = 0
    Dim distinctMode As SQLITE_C_INT = 0
    If pOrderBy <> 0 Then
        If pOrderBy->nExpr < 0 OrElse pOrderBy->nAlloc < pOrderBy->nExpr Then Return 0
        Dim orderIndex As SQLITE_C_INT = 0
        While orderIndex < pOrderBy->nExpr
            Dim pItem As SqliteExprListItem Ptr = @pOrderBy->a(orderIndex)
            Dim pExpression As SqliteExpr Ptr = _
                CPtr(SqliteExpr Ptr, pItem->pExpr)
            If pExpression = 0 Then Return 0
            If sqlite3ExprIsConstant(0, pExpression) <> 0 Then
                orderIndex += 1
                Continue While
            End If
            If (pItem->fg.sortFlags And KEYINFO_ORDER_BIGNULL) <> 0 Then Exit While

            If pExpression->op = TK_COLUMN AndAlso _
               pExpression->iTable = pSource->iCursor Then
                orderIndex += 1
                Continue While
            End If

            If pExpression->op = TK_COLLATE AndAlso pExpression->pLeft <> 0 Then
                Dim pLeft As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pExpression->pLeft)
                If pLeft->op = TK_COLUMN AndAlso _
                   pLeft->iTable = pSource->iCursor Then
                    pExpression->iColumn = pLeft->iColumn
                    If pLeft->iColumn < 0 Then
                        orderIndex += 1
                        Continue While
                    End If
                    If pLeft->iColumn >= pTable->nCol Then Return 0
                    Dim zCollation As Const ZString Ptr = _
                        sqlite3ColumnColl(@pTable->aCol[pLeft->iColumn])
                    If zCollation = 0 Then zCollation = StrPtr("BINARY")
                    If sqlite3_stricmp( _
                        CPtr(Const ZString Ptr, pExpression->u.zToken), _
                        zCollation) = 0 Then
                        orderIndex += 1
                        Continue While
                    End If
                End If
            End If
            Exit While
        Wend

        If orderIndex = pOrderBy->nExpr Then
            orderTermCount = pOrderBy->nExpr
            Dim sortByGroup As SQLITE_C_INT = _
                CInt((pWhereInfo->wctrlFlags And VTA_WHERE_SORTBYGROUP) <> 0)
            If (pWhereInfo->wctrlFlags And VTA_WHERE_DISTINCTBY) <> 0 AndAlso _
               (pSource->fg.flags And VTA_SRC_ROWID_USED_MASK) = 0 Then
                distinctMode = 2 + sortByGroup
            ElseIf (pWhereInfo->wctrlFlags And VTA_WHERE_GROUPBY) <> 0 Then
                distinctMode = 1 - sortByGroup
            ElseIf (pWhereInfo->wctrlFlags And VTA_WHERE_WANT_DISTINCT) <> 0 Then
                distinctMode = 3
            End If
        End If
    End If

    ' The hidden record ends at the flexible aRhs array. Subtract its one
    ' placeholder pointer to recover the C offsetof(HiddenIndexInfo, aRhs).
    Dim hiddenBaseBytes As sqlite3_uint64 = _
        CULngInt(SizeOf(SqliteHiddenIndexInfo) - SizeOf(Any Ptr))
    Dim indexInfoBytes As sqlite3_uint64 = CULngInt(SizeOf(SqliteIndexInfo))
    Dim termElementBytes As sqlite3_uint64 = _
        CULngInt(SizeOf(Any Ptr)) + _
        CULngInt(SizeOf(SqliteIndexConstraint)) + _
        CULngInt(SizeOf(SqliteIndexConstraintUsage))
    Dim orderElementBytes As sqlite3_uint64 = _
        CULngInt(SizeOf(SqliteIndexOrderBy))
    Dim maximumBytes As sqlite3_uint64 = CULngInt(SQLITE_MAX_LENGTH)
    If indexInfoBytes > maximumBytes OrElse _
       hiddenBaseBytes > maximumBytes - indexInfoBytes Then Return 0
    Dim allocationBytes As sqlite3_uint64 = indexInfoBytes + hiddenBaseBytes
    If termElementBytes = 0 OrElse _
       CULngInt(termCount) > (maximumBytes - allocationBytes) \ termElementBytes Then Return 0
    allocationBytes += CULngInt(termCount) * termElementBytes
    If orderElementBytes = 0 OrElse _
       CULngInt(orderTermCount) > (maximumBytes - allocationBytes) \ orderElementBytes Then Return 0
    allocationBytes += CULngInt(orderTermCount) * orderElementBytes

    Dim pIndexInfo As SqliteIndexInfo Ptr = _
        CPtr(SqliteIndexInfo Ptr, sqlite3DbMallocZero(pParse->db, allocationBytes))
    If pIndexInfo = 0 Then
        sqlite3ErrorMsg(pParse, StrPtr("out of memory"))
        Return 0
    End If

    Dim pHidden As SqliteHiddenIndexInfo Ptr = CPtr( _
        SqliteHiddenIndexInfo Ptr, _
        CPtr(UByte Ptr, pIndexInfo) + CULngInt(SizeOf(SqliteIndexInfo)))
    Dim pConstraintArrayAddress As UByte Ptr = _
        CPtr(UByte Ptr, pIndexInfo) + indexInfoBytes + hiddenBaseBytes + _
        CULngInt(termCount) * CULngInt(SizeOf(Any Ptr))
    Dim pConstraintArray As SqliteIndexConstraint Ptr = _
        CPtr(SqliteIndexConstraint Ptr, pConstraintArrayAddress)
    Dim pOrderArray As SqliteIndexOrderBy Ptr = CPtr( _
        SqliteIndexOrderBy Ptr, _
        pConstraintArrayAddress + CULngInt(termCount) * _
        CULngInt(SizeOf(SqliteIndexConstraint)))
    Dim pUsageArray As SqliteIndexConstraintUsage Ptr = CPtr( _
        SqliteIndexConstraintUsage Ptr, _
        CPtr(UByte Ptr, pOrderArray) + _
        CULngInt(orderTermCount) * CULngInt(SizeOf(SqliteIndexOrderBy)))

    pIndexInfo->aConstraint = pConstraintArray
    pIndexInfo->aOrderBy = pOrderArray
    pIndexInfo->aConstraintUsage = pUsageArray
    pIndexInfo->colUsed = pSource->colUsed
    If (pTable->tabFlags And TF_WithoutRowid) <> 0 Then
        Dim pPrimaryKey As SqliteIndex Ptr = sqlite3PrimaryKeyIndex(pTable)
        If pPrimaryKey = 0 OrElse _
           (pPrimaryKey->nKeyCol > 0 AndAlso pPrimaryKey->aiColumn = 0) Then
            sqlite3DbFree(pParse->db, pIndexInfo)
            Return 0
        End If
        For keyIndex As SQLITE_C_INT = 0 To pPrimaryKey->nKeyCol - 1
            Dim columnIndex As SQLITE_C_INT = pPrimaryKey->aiColumn[keyIndex]
            If columnIndex < 0 Then
                sqlite3DbFree(pParse->db, pIndexInfo)
                Return 0
            End If
            If columnIndex >= VTA_BITMASK_BITS - 1 Then _
                columnIndex = VTA_BITMASK_BITS - 1
            pIndexInfo->colUsed = pIndexInfo->colUsed Or _
                                  whereVtabMaskBit(columnIndex)
        Next
    End If
    pHidden->pWC = pWhereClause
    pHidden->pParse = pParse
    pHidden->eDistinct = distinctMode
    pHidden->mIn = 0
    pHidden->mHandleIn = 0

    Dim termOffset As SQLITE_C_INT = 0
    Dim constraintIndex As SQLITE_C_INT = 0
    pClause = pWhereClause
    While pClause <> 0
        Dim pTerm As SqliteWhereTerm Ptr = CPtr(SqliteWhereTerm Ptr, pClause->a)
        For localTermIndex As SQLITE_C_INT = 0 To pClause->nTerm - 1
            If (pTerm->wtFlags And VTA_TERM_OK) <> 0 Then
                Dim constraint As SqliteIndexConstraint Ptr = _
                    pIndexInfo->aConstraint + constraintIndex
                constraint->iColumn = pTerm->u.x.leftColumn
                constraint->iTermOffset = termOffset
                Dim operatorMask As u16 = pTerm->eOperator And VTA_WO_ALL
                If operatorMask = VTA_WO_IN Then
                    If (pTerm->wtFlags And VTA_TERM_SLICE) = 0 Then _
                        pHidden->mIn = pHidden->mIn Or whereVtabMaskBit32(constraintIndex)
                    operatorMask = VTA_WO_EQ
                End If
                If operatorMask = VTA_WO_AUX Then
                    constraint->op = pTerm->eMatchOp
                ElseIf (operatorMask And (VTA_WO_ISNULL Or VTA_WO_IS)) <> 0 Then
                    If operatorMask = VTA_WO_ISNULL Then
                        constraint->op = SQLITE_INDEX_CONSTRAINT_ISNULL
                    Else
                        constraint->op = SQLITE_INDEX_CONSTRAINT_IS
                    End If
                Else
                    constraint->op = CUByte(operatorMask)
                    If (operatorMask And (VTA_WO_LT Or VTA_WO_LE Or _
                                          VTA_WO_GT Or VTA_WO_GE)) <> 0 AndAlso _
                       pTerm->pExpr <> 0 Then
                        Dim pTermExpression As SqliteExpr Ptr = _
                            CPtr(SqliteExpr Ptr, pTerm->pExpr)
                        If pTermExpression->pRight <> 0 AndAlso _
                           sqlite3ExprIsVector(CPtr(SqliteExpr Ptr, _
                               pTermExpression->pRight)) <> 0 Then
                            If constraintIndex < 16 Then _
                                maskNoOmit = maskNoOmit Or _
                                             CUInt(1) Shl constraintIndex
                            If operatorMask = VTA_WO_LT Then
                                constraint->op = SQLITE_INDEX_CONSTRAINT_LE
                            ElseIf operatorMask = VTA_WO_GT Then
                                constraint->op = SQLITE_INDEX_CONSTRAINT_GE
                            End If
                        End If
                    End If
                End If
                constraint->usable = CByte((pTerm->prereqRight And unusableMask) = 0)
                constraintIndex += 1
            End If
            termOffset += 1
            pTerm += 1
        Next
        pClause = CPtr(SqliteWhereClause Ptr, pClause->pOuter)
    Wend
    If constraintIndex <> termCount Then
        sqlite3DbFree(pParse->db, pIndexInfo)
        Return 0
    End If

    If pOrderBy <> 0 AndAlso orderTermCount > 0 Then
        Dim outputOrderIndex As SQLITE_C_INT = 0
        For orderIndex As SQLITE_C_INT = 0 To pOrderBy->nExpr - 1
            Dim pItem As SqliteExprListItem Ptr = @pOrderBy->a(orderIndex)
            Dim pExpression As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pItem->pExpr)
            If sqlite3ExprIsConstant(0, pExpression) <> 0 Then Continue For
            pIndexInfo->aOrderBy[outputOrderIndex].iColumn = pExpression->iColumn
            pIndexInfo->aOrderBy[outputOrderIndex].desc = _
                CByte(pItem->fg.sortFlags And KEYINFO_ORDER_DESC)
            outputOrderIndex += 1
        Next
        pIndexInfo->nOrderBy = outputOrderIndex
    End If
    pIndexInfo->nConstraint = constraintIndex
    pMaskNoOmit[0] = maskNoOmit
    Return pIndexInfo
End Function

/' end of sqlite3_bulk35_where_vtab.bas '/
