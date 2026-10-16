/'
    Project: SQLite FreeBASIC port

    File: sqlite3_bulk_where_expr_terms.bas

    Purpose:

        Analyze WHERE expression use and construct expression-derived terms.

    Responsibilities:

        - Port WHERE expression-use and SELECT-use mask routines.
        - Split WHERE expressions and add row-limit terms.
        - Prepare virtual-table function argument terms.

    This file intentionally does NOT contain:

        - Query-loop enumeration or VDBE bytecode generation.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_hash_types.bi"
#include once "sqlite3_pager.bi"
#include once "sqlite3_btree.bi"
#include once "sqlite3_vdbe_compare.bi"
#include once "sqlite3_walker.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_fp.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_vdbe_api.bi"
Declare Sub sqlite3SetJoinExpr CDecl Alias "sqlite3SetJoinExpr" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_UINT)
Declare Function sqlite3ExprColUsed CDecl Alias "sqlite3ExprColUsed" (ByVal arg0 As Any Ptr) As sqlite3_uint64
Declare Function exprSelectUsage CDecl Alias "exprSelectUsage" (ByVal arg0 As SqliteWhereMaskSet Ptr, ByVal arg1 As SqliteSelect Ptr) As sqlite3_uint64
Declare Sub sqlite3WhereSplit CDecl Alias "sqlite3WhereSplit" (ByVal arg0 As SqliteWhereClause Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As UByte)
Declare Sub whereAddLimitExpr CDecl Alias "whereAddLimitExpr" (ByVal arg0 As SqliteWhereClause Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteExpr Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT)
Declare Sub sqlite3WhereAddLimit CDecl Alias "sqlite3WhereAddLimit" (ByVal arg0 As SqliteWhereClause Ptr, ByVal arg1 As SqliteSelect Ptr)
Declare Sub sqlite3WhereTabFuncArgs CDecl Alias "sqlite3WhereTabFuncArgs" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcItem Ptr, ByVal arg2 As SqliteWhereClause Ptr)

Private Function exprSelectUsage CDecl Alias "exprSelectUsage" (ByVal arg0 As SqliteWhereMaskSet Ptr, ByVal arg1 As SqliteSelect Ptr) As sqlite3_uint64
    Dim local0 As sqlite3_uint64
    Dim local1 As SqliteSrcList Ptr
    Dim c2fb_temp_0 As sqlite3_uint64
    Dim c2fb_temp_1 As sqlite3_uint64
    Dim c2fb_temp_2 As sqlite3_uint64
    Dim c2fb_temp_3 As sqlite3_uint64
    Dim c2fb_temp_4 As sqlite3_uint64
    Dim local2 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As sqlite3_uint64
    Dim c2fb_temp_8 As sqlite3_uint64
    Dim c2fb_temp_9 As sqlite3_uint64
    Dim c2fb_temp_10 As SqliteSelect Ptr

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    While arg1
        local1 = CPtr(SqliteSrcList Ptr, arg1->pSrc)
        c2fb_temp_0 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprListUsage(arg0, CPtr(SqliteExprList Ptr, arg1->pEList)))))
        local0 = c2fb_temp_0
        c2fb_temp_1 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprListUsage(arg0, CPtr(SqliteExprList Ptr, arg1->pGroupBy)))))
        local0 = c2fb_temp_1
        c2fb_temp_2 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprListUsage(arg0, CPtr(SqliteExprList Ptr, arg1->pOrderBy)))))
        local0 = c2fb_temp_2
        c2fb_temp_3 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprUsage(arg0, CPtr(SqliteExpr Ptr, arg1->pWhere)))))
        local0 = c2fb_temp_3
        c2fb_temp_4 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprUsage(arg0, CPtr(SqliteExpr Ptr, arg1->pHaving)))))
        local0 = c2fb_temp_4
        If ((-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, &O0ULL)))))) Then
            ' C automatic storage declaration
            c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local2 = c2fb_temp_5
            While (-Cast(SQLITE_C_INT, ((local2 < local1->nSrc))))
                If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->a(local2).fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                    c2fb_temp_7 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or exprSelectUsage(arg0, CPtr(SqliteSelect Ptr, CPtr(SqliteSubquery Ptr, local1->a(local2).u4.pSubq)->pSelect)))))
                    local0 = c2fb_temp_7
                End If
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->a(local2).fg.flags) Shr 11) And Cast(SQLITE_C_UINT, &H1ULL))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_8 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprUsage(arg0, CPtr(SqliteExpr Ptr, local1->a(local2).u3.pOn)))))
                    local0 = c2fb_temp_8
                End If
                If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->a(local2).fg.flags) Shr 3) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                    c2fb_temp_9 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprListUsage(arg0, CPtr(SqliteExprList Ptr, local1->a(local2).u1.pFuncArg)))))
                    local0 = c2fb_temp_9
                End If
            c2fb_flow_3:
                c2fb_temp_6 = local2
                local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 + 1)))
            Wend
            c2fb_flow_2:
        End If
        c2fb_temp_10 = CPtr(SqliteSelect Ptr, arg1->pPrior)
        arg1 = c2fb_temp_10
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    Return local0
End Function

Sub sqlite3WhereSplit CDecl Alias "sqlite3WhereSplit" (ByVal arg0 As SqliteWhereClause Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As UByte)
    Dim local0 As SqliteExpr Ptr
    Dim c2fb_temp_0 As u8 Ptr
    Dim c2fb_temp_1 As UByte

    local0 = CPtr(SqliteExpr Ptr, sqlite3ExprSkipCollateAndLikely(CPtr(Any Ptr, arg1)))
    c2fb_temp_0 = @(arg0->op)
    c2fb_temp_1 = Cast(UByte, arg2)
    (*c2fb_temp_0) = Cast(u8, Cast(UByte, arg2))
    c2fb_temp_1 = Cast(UByte, (*c2fb_temp_0))
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->op) <> Cast(SQLITE_C_INT, arg2))))) Then
        whereClauseInsert(arg0, arg1, Cast(SQLITE_C_INT, &O0ULL))
    Else
        sqlite3WhereSplit(arg0, CPtr(SqliteExpr Ptr, local0->pLeft), arg2)
        sqlite3WhereSplit(arg0, CPtr(SqliteExpr Ptr, local0->pRight), arg2)
    End If
End Sub

Private Sub whereAddLimitExpr CDecl Alias "whereAddLimitExpr" (ByVal arg0 As SqliteWhereClause Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteExpr Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT)
    Dim local0 As SqliteParseContext Ptr
    Dim local1 As sqlite3 Ptr
    Dim local2 As SqliteExpr Ptr
    Dim local3 As SQLITE_C_INT
    Dim local4 As SqliteExpr Ptr
    Dim c2fb_temp_0 As SqliteExpr Ptr
    Dim local5 As SqliteExpr Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SqliteExpr Ptr
    Dim local6 As SqliteWhereTerm Ptr
    Dim local7 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SqliteWhereTerm Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As u16 Ptr
    Dim c2fb_temp_9 As UShort
    Dim c2fb_temp_10 As u8 Ptr
    Dim c2fb_temp_11 As UByte

    local0 = CPtr(SqliteParseContext Ptr, CPtr(SqliteWhereInfo Ptr, arg0->pWInfo)->pParse)
    local1 = local0->db
    ' C automatic storage declaration
    local3 = Cast(SQLITE_C_INT, &O0ULL)
    If (-Cast(SQLITE_C_INT, ((sqlite3ExprIsInteger(CPtr(Any Ptr, arg2), CPtr(SQLITE_C_INT Ptr, @(local3)), CPtr(Any Ptr, local0), Cast(SQLITE_C_INT, &O0ULL)) AndAlso (-Cast(SQLITE_C_INT, ((local3 >= Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        local4 = CPtr(SqliteExpr Ptr, sqlite3ExprInt32(CPtr(Any Ptr, local1), local3))
        If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return
        End If
        c2fb_temp_0 = CPtr(SqliteExpr Ptr, sqlite3PExpr(CPtr(Any Ptr, local0), Cast(SQLITE_C_INT, 47ULL), Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, local4)))
        local2 = c2fb_temp_0
    Else
        local5 = CPtr(SqliteExpr Ptr, sqlite3ExprAlloc(CPtr(Any Ptr, local1), Cast(SQLITE_C_INT, 176ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)))
        If (-Cast(SQLITE_C_INT, ((local5 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return
        End If
        c2fb_temp_1 = @(local5->iTable)
        c2fb_temp_2 = Cast(SQLITE_C_INT, arg1)
        (*c2fb_temp_1) = c2fb_temp_2
        c2fb_temp_3 = CPtr(SqliteExpr Ptr, sqlite3PExpr(CPtr(Any Ptr, local0), Cast(SQLITE_C_INT, 47ULL), Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, local5)))
        local2 = c2fb_temp_3
    End If
    If local2 Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        c2fb_temp_4 = Cast(SQLITE_C_INT, whereClauseInsert(arg0, local2, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0001ULL) Or Cast(SQLITE_C_INT, &H0002ULL)))))
        local7 = c2fb_temp_4
        c2fb_temp_5 = CPtr(SqliteWhereTerm Ptr, @(CPtr(SqliteWhereTerm Ptr, arg0->a)[local7]))
        local6 = c2fb_temp_5
        c2fb_temp_6 = @(local6->leftCursor)
        c2fb_temp_7 = Cast(SQLITE_C_INT, arg3)
        (*c2fb_temp_6) = c2fb_temp_7
        c2fb_temp_8 = @(local6->eOperator)
        c2fb_temp_9 = Cast(UShort, Cast(SQLITE_C_INT, &H0040ULL))
        (*c2fb_temp_8) = Cast(u16, Cast(UShort, Cast(SQLITE_C_INT, &H0040ULL)))
        c2fb_temp_9 = Cast(UShort, (*c2fb_temp_8))
        c2fb_temp_10 = @(local6->eMatchOp)
        c2fb_temp_11 = Cast(UByte, arg4)
        (*c2fb_temp_10) = Cast(u8, Cast(UByte, arg4))
        c2fb_temp_11 = Cast(UByte, (*c2fb_temp_10))
    End If
End Sub

Sub sqlite3WhereAddLimit CDecl Alias "sqlite3WhereAddLimit" (ByVal arg0 As SqliteWhereClause Ptr, ByVal arg1 As SqliteSelect Ptr)
    Dim local0 As SqliteExprList Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local3 As SqliteWhereTerm Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim local4 As SqliteExpr Ptr

    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((CPtr(SqliteExprList Ptr, arg1->pGroupBy) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0000001ULL) Or Cast(SQLITE_C_INT, &H0000008ULL)))))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((CPtr(SqliteSrcList Ptr, arg1->pSrc)->nSrc = Cast(SQLITE_C_INT, 1ULL))))) AndAlso ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (CPtr(SqliteTable Ptr, CPtr(SqliteSrcList Ptr, arg1->pSrc)->a(Cast(SQLITE_C_INT, &O0ULL)).pSTab))->eTabType) = Cast(SQLITE_C_INT, 1ULL))))))))))))))) Then
        local0 = CPtr(SqliteExprList Ptr, arg1->pOrderBy)
        local1 = CPtr(SqliteSrcList Ptr, arg1->pSrc)->a(Cast(SQLITE_C_INT, &O0ULL)).iCursor
        ' C automatic storage declaration
        c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local2 = c2fb_temp_0
        While (-Cast(SQLITE_C_INT, ((local2 < arg0->nTerm))))
            If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, CPtr(SqliteWhereTerm Ptr, arg0->a)[local2].wtFlags) And Cast(SQLITE_C_INT, &H0004ULL))) Then
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                Goto c2fb_flow_1
            End If
            If CPtr(SqliteWhereTerm Ptr, arg0->a)[local2].nChild Then
                Goto c2fb_flow_1
            End If
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((CPtr(SqliteWhereTerm Ptr, arg0->a)[local2].leftCursor = local1)))) AndAlso (-Cast(SQLITE_C_INT, ((CPtr(SqliteWhereTerm Ptr, arg0->a)[local2].prereqRight = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
                Goto c2fb_flow_1
            End If
            If (-Cast(SQLITE_C_INT, ((CPtr(SqliteWhereTerm Ptr, arg0->a)[local2].iParent >= Cast(SQLITE_C_INT, &O0ULL))))) Then
                local3 = CPtr(SqliteWhereTerm Ptr, @(CPtr(SqliteWhereTerm Ptr, arg0->a)[CPtr(SqliteWhereTerm Ptr, arg0->a)[local2].iParent]))
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local3->leftCursor = local1)))) AndAlso (-Cast(SQLITE_C_INT, ((local3->prereqRight = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->nChild) = Cast(SQLITE_C_INT, 1ULL))))))))) Then
                    Goto c2fb_flow_1
                End If
            End If
            Return
        c2fb_flow_1:
            c2fb_temp_1 = local2
            local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
        Wend
        c2fb_flow_0:
        If local0 Then
            c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local2 = c2fb_temp_2
            While (-Cast(SQLITE_C_INT, ((local2 < local0->nExpr))))
                local4 = CPtr(SqliteExpr Ptr, local0->a(local2).pExpr)
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4->op) <> Cast(SQLITE_C_INT, 168ULL))))) Then
                    Return
                End If
                If (-Cast(SQLITE_C_INT, ((local4->iTable <> local1)))) Then
                    Return
                End If
                If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->a(local2).fg.sortFlags) And Cast(SQLITE_C_INT, &H02ULL))) Then
                    Return
                End If
            c2fb_flow_3:
                c2fb_temp_3 = local2
                local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_3 + 1)))
            Wend
            c2fb_flow_2:
        End If
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg1->iOffset <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000100ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
            whereAddLimitExpr(arg0, arg1->iOffset, CPtr(SqliteExpr Ptr, CPtr(SqliteExpr Ptr, arg1->pLimit)->pRight), local1, Cast(SQLITE_C_INT, 74ULL))
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg1->iOffset = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000100ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
            whereAddLimitExpr(arg0, arg1->iLimit, CPtr(SqliteExpr Ptr, CPtr(SqliteExpr Ptr, arg1->pLimit)->pLeft), local1, Cast(SQLITE_C_INT, 73ULL))
        End If
    End If
End Sub

Private Function sqlite3WhereExprUsageFull CDecl Alias "sqlite3WhereExprUsageFull" (ByVal arg0 As SqliteWhereMaskSet Ptr, ByVal arg1 As SqliteExpr Ptr) As sqlite3_uint64
    Dim local0 As sqlite3_uint64
    Dim c2fb_temp_0 As sqlite3_uint64
    Dim c2fb_temp_1 As sqlite3_uint64
    Dim c2fb_temp_2 As sqlite3_uint64
    Dim c2fb_temp_3 As SQLITE_C_INT Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As sqlite3_uint64
    Dim c2fb_temp_6 As sqlite3_uint64
    Dim c2fb_temp_7 As sqlite3_uint64
    Dim c2fb_temp_8 As sqlite3_uint64
    Dim c2fb_temp_9 As sqlite3_uint64

    ' C automatic storage declaration
    c2fb_temp_0 = Cast(sqlite3_uint64, IIf(((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 179ULL)))))), sqlite3WhereGetMask(arg0, arg1->iTable), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))))
    local0 = c2fb_temp_0
    If CPtr(SqliteExpr Ptr, arg1->pLeft) Then
        c2fb_temp_1 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprUsageNN(arg0, CPtr(SqliteExpr Ptr, arg1->pLeft)))))
        local0 = c2fb_temp_1
    End If
    If CPtr(SqliteExpr Ptr, arg1->pRight) Then
        c2fb_temp_2 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprUsageNN(arg0, CPtr(SqliteExpr Ptr, arg1->pRight)))))
        local0 = c2fb_temp_2
        ' C unused-parameter annotation
    Else
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000040ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                c2fb_temp_3 = @(arg0->bVarSelect)
                c2fb_temp_4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                (*c2fb_temp_3) = c2fb_temp_4
            End If
            c2fb_temp_5 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or exprSelectUsage(arg0, CPtr(SqliteSelect Ptr, arg1->x.pSelect)))))
            local0 = c2fb_temp_5
        Else
            If CPtr(SqliteExprList Ptr, arg1->x.pList) Then
                c2fb_temp_6 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprListUsage(arg0, CPtr(SqliteExprList Ptr, arg1->x.pList)))))
                local0 = c2fb_temp_6
            End If
        End If
    End If
#ifndef SQLITE_OMIT_WINDOWFUNC
    If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 172ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 169ULL)))))))))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H1000000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
        ' C unused-parameter annotation
        c2fb_temp_7 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprListUsage(arg0, CPtr(SqliteWalkerWindow Ptr, arg1->y.pWin)->pPartition))))
        local0 = c2fb_temp_7
        c2fb_temp_8 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprListUsage(arg0, CPtr(SqliteWalkerWindow Ptr, arg1->y.pWin)->pOrderBy))))
        local0 = c2fb_temp_8
        c2fb_temp_9 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprUsage(arg0, CPtr(SqliteWalkerWindow Ptr, arg1->y.pWin)->pFilter))))
        local0 = c2fb_temp_9
    End If
#endif
    Return local0
End Function

Function sqlite3WhereExprUsageNN CDecl Alias "sqlite3WhereExprUsageNN" (ByVal arg0 As SqliteWhereMaskSet Ptr, ByVal arg1 As SqliteExpr Ptr) As sqlite3_uint64
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 168ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000020ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))))))) Then
        Return sqlite3WhereGetMask(arg0, arg1->iTable)
    Else
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H010000ULL) Or Cast(SQLITE_C_INT, &H800000ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            ' C unused-parameter annotation
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
    End If
    Return sqlite3WhereExprUsageFull(arg0, arg1)
End Function

Function sqlite3WhereExprUsage CDecl Alias "sqlite3WhereExprUsage" (ByVal arg0 As SqliteWhereMaskSet Ptr, ByVal arg1 As SqliteExpr Ptr) As sqlite3_uint64
    Return IIf(arg1, sqlite3WhereExprUsageNN(arg0, arg1), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))
End Function

Function sqlite3WhereExprListUsage CDecl Alias "sqlite3WhereExprListUsage" (ByVal arg0 As SqliteWhereMaskSet Ptr, ByVal arg1 As SqliteExprList Ptr) As sqlite3_uint64
    Dim local0 As SQLITE_C_INT
    Dim local1 As sqlite3_uint64
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As sqlite3_uint64

    ' C automatic storage declaration
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    If arg1 Then
        c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local0 = c2fb_temp_0
        While (-Cast(SQLITE_C_INT, ((local0 < arg1->nExpr))))
            c2fb_temp_2 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local1 Or sqlite3WhereExprUsage(arg0, CPtr(SqliteExpr Ptr, arg1->a(local0).pExpr)))))
            local1 = c2fb_temp_2
        c2fb_flow_1:
            c2fb_temp_1 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
        Wend
        c2fb_flow_0:
    End If
    Return local1
End Function

Sub sqlite3WhereTabFuncArgs CDecl Alias "sqlite3WhereTabFuncArgs" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcItem Ptr, ByVal arg2 As SqliteWhereClause Ptr)
    Dim local0 As SqliteTable Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As SqliteExprList Ptr
    Dim local4 As SqliteExpr Ptr
    Dim local5 As SqliteExpr Ptr
    Dim c2fb_temp_0 As SqliteTable Ptr
    Dim c2fb_temp_1 As SqliteExprList Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim local6 As SqliteExpr Ptr
    Dim local7 As SQLITE_C_UINT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SqliteExpr Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT Ptr
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As Short Ptr
    Dim c2fb_temp_11 As Short
    Dim c2fb_temp_12 As Any Ptr Ptr
    Dim c2fb_temp_13 As SqliteTable Ptr
    Dim c2fb_temp_14 As sqlite3_uint64 Ptr
    Dim c2fb_temp_15 As sqlite3_uint64
    Dim c2fb_temp_16 As SqliteExpr Ptr
    Dim c2fb_temp_17 As SqliteExpr Ptr
    Dim c2fb_temp_18 As SQLITE_C_UINT
    Dim c2fb_temp_19 As SQLITE_C_UINT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg1->fg.flags) Shr 3) And Cast(SQLITE_C_UINT, &H1ULL))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    c2fb_temp_0 = CPtr(SqliteTable Ptr, arg1->pSTab)
    local0 = c2fb_temp_0
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local0)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))) = 0))) Then
        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"'%s' is not a function"), arg1->zName)
        Return
    End If
    c2fb_temp_1 = CPtr(SqliteExprList Ptr, arg1->u1.pFuncArg)
    local3 = c2fb_temp_1
    If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local2 = c2fb_temp_2
    c2fb_temp_3 = Cast(SQLITE_C_INT, c2fb_temp_2)
    local1 = c2fb_temp_3
    While (-Cast(SQLITE_C_INT, ((local1 < local3->nExpr))))
        ' C automatic storage declaration
        ' C automatic storage declaration
        While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local2 < Cast(SQLITE_C_INT, local0->nCol))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->aCol[local2].colFlags) And Cast(SQLITE_C_INT, &H0002ULL)))) = Cast(SQLITE_C_INT, &O0ULL)))))))))
            c2fb_temp_5 = local2
            local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_5 + 1)))
        c2fb_flow_3:
        Wend
        c2fb_flow_2:
        If (-Cast(SQLITE_C_INT, ((local2 >= Cast(SQLITE_C_INT, local0->nCol))))) Then
            sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"too many arguments on %s() - max %d"), local0->zName, local1)
            Return
        End If
        c2fb_temp_6 = CPtr(SqliteExpr Ptr, sqlite3ExprAlloc(CPtr(Any Ptr, arg0->db), Cast(SQLITE_C_INT, 168ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)))
        local4 = c2fb_temp_6
        If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return
        End If
        c2fb_temp_7 = @(local4->iTable)
        c2fb_temp_8 = Cast(SQLITE_C_INT, arg1->iCursor)
        (*c2fb_temp_7) = c2fb_temp_8
        c2fb_temp_10 = @(local4->iColumn)
        c2fb_temp_9 = local2
        local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_9 + 1)))
        c2fb_temp_11 = Cast(Short, c2fb_temp_9)
        (*c2fb_temp_10) = c2fb_temp_11
        ' C unused-parameter annotation
        c2fb_temp_12 = @(local4->y.pTab)
        c2fb_temp_13 = local0
        (*c2fb_temp_12) = CPtr(Any Ptr, local0)
        c2fb_temp_13 = CPtr(SqliteTable Ptr, (*c2fb_temp_12))
        c2fb_temp_14 = @(arg1->colUsed)
        c2fb_temp_15 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, ((*c2fb_temp_14) Or sqlite3ExprColUsed(CPtr(Any Ptr, local4)))))
        (*c2fb_temp_14) = c2fb_temp_15
        c2fb_temp_16 = CPtr(SqliteExpr Ptr, sqlite3PExpr(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 173ULL), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local3->a(local1).pExpr)), Cast(SQLITE_C_INT, &O0ULL)))), Cast(SQLITE_C_INT, &O0ULL)))
        local6 = c2fb_temp_16
        c2fb_temp_17 = CPtr(SqliteExpr Ptr, sqlite3PExpr(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 54ULL), CPtr(Any Ptr, local4), CPtr(Any Ptr, local6)))
        local5 = c2fb_temp_17
        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H10ULL)))))) Then
            ' empty C statement
            ' empty C statement
            c2fb_temp_18 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H000001ULL))
            local7 = c2fb_temp_18
        Else
            ' empty C statement
            c2fb_temp_19 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H000002ULL))
            local7 = c2fb_temp_19
        End If
        sqlite3SetJoinExpr(CPtr(Any Ptr, local5), arg1->iCursor, local7)
        whereClauseInsert(arg2, local5, Cast(SQLITE_C_INT, &H0001ULL))
    c2fb_flow_1:
        c2fb_temp_4 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_4 + 1)))
    Wend
    c2fb_flow_0:
End Sub

/' end of sqlite3_bulk_where_expr_terms.bas '/
