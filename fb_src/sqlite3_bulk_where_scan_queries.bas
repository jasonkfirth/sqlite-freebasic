/'
    Project: SQLite FreeBASIC port

    File: sqlite3_bulk_where_scan_queries.bas

    Purpose:

        Find index-compatible WHERE terms and redundant DISTINCT clauses.

    Responsibilities:

        - Port sqlite3WhereFindTerm and isDistinctRedundant.
        - Use the shared WHERE scanner and expression-affinity helpers.
        - Preserve cursor, index, collation, and NULLability checks.

    This file intentionally does NOT contain:

        - WHERE-clause construction or general loop enumeration.
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
#include once "sqlite3_vtab_types.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_util_numeric.bi"
Declare Function sqlite3StrICmp CDecl Alias "sqlite3StrICmp" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT
Declare Function findIndexCol CDecl Alias "findIndexCol" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExprList Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SqliteIndex Ptr, ByVal arg4 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function indexColumnNotNull CDecl Alias "indexColumnNotNull" (ByVal arg0 As SqliteIndex Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function isDistinctRedundant CDecl Alias "isDistinctRedundant" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As SqliteWhereClause Ptr, ByVal arg3 As SqliteExprList Ptr) As SQLITE_C_INT

Function sqlite3WhereFindTerm CDecl Alias "sqlite3WhereFindTerm" (ByVal arg0 As SqliteWhereClause Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As sqlite3_uint64, ByVal arg4 As SQLITE_C_UINT, ByVal arg5 As SqliteIndex Ptr) As SqliteWhereTerm Ptr
    Dim local0 As SqliteWhereTerm Ptr
    Dim local1 As SqliteWhereTerm Ptr
    Dim local2 As SqliteWhereScan
    Dim c2fb_temp_0 As SqliteWhereTerm Ptr
    Dim c2fb_temp_1 As SQLITE_C_UINT
    Dim c2fb_temp_2 As SqliteWhereTerm Ptr
    Dim c2fb_temp_3 As SqliteWhereTerm Ptr

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    c2fb_temp_0 = CPtr(SqliteWhereTerm Ptr, whereScanInit(CPtr(SqliteWhereScan Ptr, @(local2)), arg0, arg1, arg2, arg4, arg5))
    local1 = c2fb_temp_0
    c2fb_temp_1 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (arg4 And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0080ULL)))))))
    arg4 = c2fb_temp_1
    While local1
        If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local1->prereqRight And arg3))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local1->prereqRight = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, local1->eOperator) And arg4))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
                ' empty C statement
                Return local1
            End If
            If (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_2 = local1
                local0 = c2fb_temp_2
            End If
        End If
        c2fb_temp_3 = CPtr(SqliteWhereTerm Ptr, whereScanNext(CPtr(SqliteWhereScan Ptr, @(local2))))
        local1 = c2fb_temp_3
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    Return local0
End Function

Private Function findIndexCol CDecl Alias "findIndexCol" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExprList Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SqliteIndex Ptr, ByVal arg4 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As Const ZString Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local2 As SqliteExpr Ptr
    Dim local3 As sqlite3CollSeq Ptr

    ' C automatic storage declaration
    local1 = CPtr(Const ZString Ptr Ptr, arg3->azColl)[arg4]
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((local0 < arg1->nExpr))))
        local2 = CPtr(SqliteExpr Ptr, sqlite3ExprSkipCollateAndLikely(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg1->a(local0).pExpr))))
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((local2 <> Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->op) = Cast(SQLITE_C_INT, 168ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->op) = Cast(SQLITE_C_INT, 170ULL)))))))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->iColumn) = Cast(SQLITE_C_INT, arg3->aiColumn[arg4]))))))))) AndAlso (-Cast(SQLITE_C_INT, ((local2->iTable = arg2)))))))) Then
            local3 = CPtr(sqlite3CollSeq Ptr, sqlite3ExprNNCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg1->a(local0).pExpr))))
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = sqlite3StrICmp(CPtr(Const ZString Ptr, local3->zName), local1))))) Then
                Return local0
            End If
        End If
    c2fb_flow_1:
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    Wend
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))
End Function

Private Function indexColumnNotNull CDecl Alias "indexColumnNotNull" (ByVal arg0 As SqliteIndex Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, arg0->aiColumn[arg1])
    local0 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, ((local0 >= Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg0->pTable->aCol[local0].flags) Shr 0) And Cast(SQLITE_C_UINT, &HFULL)))
    Else
        If (-Cast(SQLITE_C_INT, ((local0 = (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))))))) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        Else
            ' C unused-parameter annotation
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
    End If
End Function

Private Function isDistinctRedundant CDecl Alias "isDistinctRedundant" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As SqliteWhereClause Ptr, ByVal arg3 As SqliteExprList Ptr) As SQLITE_C_INT
    Dim local0 As SqliteTable Ptr
    Dim local1 As SqliteIndex Ptr
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SqliteTable Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim local4 As SqliteExpr Ptr
    Dim c2fb_temp_4 As SqliteIndex Ptr
    Dim c2fb_temp_5 As SqliteIndex Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, ((arg1->nSrc <> Cast(SQLITE_C_INT, 1ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = Cast(SQLITE_C_INT, arg1->a(Cast(SQLITE_C_INT, &O0ULL)).iCursor)
    local3 = c2fb_temp_0
    c2fb_temp_1 = CPtr(SqliteTable Ptr, arg1->a(Cast(SQLITE_C_INT, &O0ULL)).pSTab)
    local0 = c2fb_temp_1
    c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local2 = c2fb_temp_2
    While (-Cast(SQLITE_C_INT, ((local2 < arg3->nExpr))))
        local4 = CPtr(SqliteExpr Ptr, sqlite3ExprSkipCollateAndLikely(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg3->a(local2).pExpr))))
        If ((-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL)))))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4->op) <> Cast(SQLITE_C_INT, 168ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4->op) <> Cast(SQLITE_C_INT, 170ULL))))))))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local4->iTable = local3)))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4->iColumn) < Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
    c2fb_flow_1:
        c2fb_temp_3 = local2
        local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_3 + 1)))
    Wend
    c2fb_flow_0:
    c2fb_temp_4 = CPtr(SqliteIndex Ptr, local0->pIndex)
    local1 = c2fb_temp_4
    While local1
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local1)->onError) <> Cast(SQLITE_C_INT, &O0ULL)))))) = 0))) Then
            Goto c2fb_flow_3
        End If
        If CPtr(SqliteExpr Ptr, local1->pPartIdxWhere) Then
            Goto c2fb_flow_3
        End If
        c2fb_temp_6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local2 = c2fb_temp_6
        While (-Cast(SQLITE_C_INT, ((local2 < Cast(SQLITE_C_INT, local1->nKeyCol)))))
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = CPtr(SqliteWhereTerm Ptr, sqlite3WhereFindTerm(arg2, local3, local2, Cast(sqlite3_uint64, (Not Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))), Cast(SQLITE_C_INT, &H0002ULL), local1)))))) Then
                If (-Cast(SQLITE_C_INT, ((findIndexCol(arg0, arg3, local3, local1, local2) < Cast(SQLITE_C_INT, &O0ULL))))) Then
                    Goto c2fb_flow_4
                End If
                If (-Cast(SQLITE_C_INT, ((indexColumnNotNull(local1, local2) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    Goto c2fb_flow_4
                End If
            End If
        c2fb_flow_5:
            c2fb_temp_7 = local2
            local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_7 + 1)))
        Wend
        c2fb_flow_4:
        If (-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, local1->nKeyCol))))) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
    c2fb_flow_3:
        c2fb_temp_5 = local1->pNext
        local1 = c2fb_temp_5
    Wend
    c2fb_flow_2:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

/' end of sqlite3_bulk_where_scan_queries.bas '/
