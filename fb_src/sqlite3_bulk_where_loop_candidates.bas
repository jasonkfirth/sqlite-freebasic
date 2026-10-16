/'
    Project: SQLite FreeBASIC port

    File: sqlite3_bulk_where_loop_candidates.bas

    Purpose:

        Generate and retain indexed B-tree and one-row WHERE loop candidates.

    Responsibilities:

        - Port whereLoopAddBtreeIndex from src/where.c.
        - Port the unique-row and INTEGER PRIMARY KEY shortcut.
        - Check index coverage and process partial-index expressions.
        - Move OR-plan cost sets without aliasing their scratch storage.
        - Keep the local source helpers needed by both planner paths.

    This file intentionally does NOT contain:

        - Virtual-table loop callbacks or general loop enumeration.
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
Declare Function sqlite3ExprIsLikeOperator CDecl Alias "sqlite3ExprIsLikeOperator" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3CompareAffinity CDecl Alias "sqlite3CompareAffinity" (ByVal arg0 As Any Ptr, ByVal arg1 As Byte) As Byte
Declare Function sqlite3TableColumnAffinity CDecl Alias "sqlite3TableColumnAffinity" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Byte
Declare Function sqlite3ExprAffinity CDecl Alias "sqlite3ExprAffinity" (ByVal arg0 As Any Ptr) As Byte
Type c2fb_callback_8 As Sub CDecl(ByVal arg0 As Any Ptr)
Type c2fb_callback_82 As Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function indexColumnNotNull CDecl Alias "indexColumnNotNull" (ByVal arg0 As SqliteIndex Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function estLog CDecl Alias "estLog" (ByVal arg0 As Short) As Short
Declare Function constraintCompatibleWithOuterJoin CDecl Alias "constraintCompatibleWithOuterJoin" (ByVal arg0 As Const SqliteWhereTerm Ptr, ByVal arg1 As Const SqliteSrcItem Ptr) As SQLITE_C_INT
Declare Function whereRangeAdjust CDecl Alias "whereRangeAdjust" (ByVal arg0 As SqliteWhereTerm Ptr, ByVal arg1 As Short) As Short
Declare Function whereRangeScanEst CDecl Alias "whereRangeScanEst" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteWhereLoopBuilder Ptr, ByVal arg2 As SqliteWhereTerm Ptr, ByVal arg3 As SqliteWhereTerm Ptr, ByVal arg4 As SqliteWhereLoop Ptr) As SQLITE_C_INT
Declare Function whereLoopResize CDecl Alias "whereLoopResize" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteWhereLoop Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function exprNodePatternLengthEst CDecl Alias "exprNodePatternLengthEst" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function estLikePatternLength CDecl Alias "estLikePatternLength" (ByVal arg0 As SqliteExpr Ptr, ByVal arg1 As UShort) As SQLITE_C_INT
Declare Sub whereLoopOutputAdjust CDecl Alias "whereLoopOutputAdjust" (ByVal arg0 As SqliteWhereClause Ptr, ByVal arg1 As SqliteWhereLoop Ptr, ByVal arg2 As Short)
Declare Function whereRangeVectorLen CDecl Alias "whereRangeVectorLen" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteIndex Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SqliteWhereTerm Ptr) As SQLITE_C_INT
Declare Function whereShortCut CDecl Alias "whereShortCut" (ByVal arg0 As SqliteWhereLoopBuilder Ptr) As SQLITE_C_INT
Declare Function c2fb_crt_memcpy CDecl Alias "memcpy" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_SIZE_T) As Any Ptr

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

Private Function estLog CDecl Alias "estLog" (ByVal arg0 As Short) As Short
    Return IIf((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0) <= Cast(SQLITE_C_INT, 10ULL))))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, sqlite3LogEst(arg0)) - Cast(SQLITE_C_INT, 33ULL))))
End Function

Private Function constraintCompatibleWithOuterJoin CDecl Alias "constraintCompatibleWithOuterJoin" (ByVal arg0 As Const SqliteWhereTerm Ptr, ByVal arg1 As Const SqliteSrcItem Ptr) As SQLITE_C_INT
    ' C unused-parameter annotation
    ' empty C statement
    ' empty C statement
    ' empty C statement
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((CPtr(SqliteExpr Ptr, arg0->pExpr))->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000001ULL) Or Cast(SQLITE_C_INT, &H000002ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))) OrElse (-Cast(SQLITE_C_INT, ((CPtr(SqliteExpr Ptr, arg0->pExpr)->w.iJoin <> arg1->iCursor)))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H10ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((CPtr(SqliteExpr Ptr, arg0->pExpr))->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000002ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    Return Cast(SQLITE_C_INT, 1ULL)
End Function

Private Function whereRangeAdjust CDecl Alias "whereRangeAdjust" (ByVal arg0 As SqliteWhereTerm Ptr, ByVal arg1 As Short) As Short
    Dim local0 As Short
    Dim c2fb_temp_0 As Short
    Dim c2fb_temp_1 As Short

    local0 = arg1
    If arg0 Then
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->truthProb) <= Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_0 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0) + Cast(SQLITE_C_INT, arg0->truthProb))))
            local0 = c2fb_temp_0
        Else
            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->wtFlags) And Cast(SQLITE_C_INT, &H0080ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_1 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0) - Cast(SQLITE_C_INT, 20ULL))))
                local0 = c2fb_temp_1
                ' C unused-parameter annotation
            End If
        End If
    End If
    Return local0
End Function

Private Function whereRangeScanEst CDecl Alias "whereRangeScanEst" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteWhereLoopBuilder Ptr, ByVal arg2 As SqliteWhereTerm Ptr, ByVal arg3 As SqliteWhereTerm Ptr, ByVal arg4 As SqliteWhereLoop Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim local2 As Short
    Dim c2fb_temp_0 As Short
    Dim c2fb_temp_1 As Short
    Dim c2fb_temp_2 As Short
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As Short
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As Short Ptr
    Dim c2fb_temp_7 As Short

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    local1 = arg4->nOut
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(Short, whereRangeAdjust(arg2, local1))
    local2 = c2fb_temp_0
    c2fb_temp_1 = Cast(Short, whereRangeAdjust(arg3, local2))
    local2 = c2fb_temp_1
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg2 AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg2->truthProb) > Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso arg3)))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg3->truthProb) > Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        c2fb_temp_2 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local2) - Cast(SQLITE_C_INT, 20ULL))))
        local2 = c2fb_temp_2
    End If
    c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local1 - Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg2 <> Cast(SQLITE_C_INT, &O0ULL)))))) + ((-Cast(SQLITE_C_INT, ((arg3 <> Cast(SQLITE_C_INT, &O0ULL)))))))))))
    local1 = c2fb_temp_3
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2) < Cast(SQLITE_C_INT, 10ULL))))) Then
        c2fb_temp_4 = Cast(Short, Cast(SQLITE_C_INT, 10ULL))
        local2 = c2fb_temp_4
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2) < local1)))) Then
        c2fb_temp_5 = Cast(SQLITE_C_INT, local2)
        local1 = c2fb_temp_5
    End If
    c2fb_temp_6 = @(arg4->nOut)
    c2fb_temp_7 = Cast(Short, Cast(Short, local1))
    (*c2fb_temp_6) = c2fb_temp_7
    Return local0
End Function

Private Function whereLoopResize CDecl Alias "whereLoopResize" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteWhereLoop Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SqliteWhereTerm Ptr Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SqliteWhereTerm Ptr Ptr
    Dim c2fb_temp_2 As Any Ptr
    Dim c2fb_temp_3 As Any Ptr Ptr Ptr
    Dim c2fb_temp_4 As SqliteWhereTerm Ptr Ptr
    Dim c2fb_temp_5 As u16 Ptr
    Dim c2fb_temp_6 As UShort

    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->nLSlot) >= arg2)))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (arg2 + Cast(SQLITE_C_INT, 7ULL)))) And Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, 7ULL))))))
    arg2 = c2fb_temp_0
    c2fb_temp_1 = CPtr(SqliteWhereTerm Ptr Ptr, CPtr(Any Ptr, sqlite3DbMallocRawNN(CPtr(Any Ptr, arg0), Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereTerm Ptr))) * Cast(sqlite3_uint64, arg2))))))
    local0 = c2fb_temp_1
    If (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, 7ULL)
    End If
    c2fb_temp_2 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, local0), CPtr(Const Any Ptr, CPtr(SqliteWhereTerm Ptr Ptr, arg1->aLTerm)), Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereTerm Ptr))) * Cast(sqlite3_uint64, arg1->nLSlot)))))
    If (-Cast(SQLITE_C_INT, ((CPtr(SqliteWhereTerm Ptr Ptr, arg1->aLTerm) <> CPtr(SqliteWhereTerm Ptr Ptr, (@arg1->aLTermSpace(0))))))) Then
        sqlite3DbFreeNN(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteWhereTerm Ptr Ptr, arg1->aLTerm)))
    End If
    c2fb_temp_3 = @(arg1->aLTerm)
    c2fb_temp_4 = local0
    (*c2fb_temp_3) = CPtr(Any Ptr Ptr, local0)
    c2fb_temp_4 = CPtr(SqliteWhereTerm Ptr Ptr, (*c2fb_temp_3))
    c2fb_temp_5 = @(arg1->nLSlot)
    c2fb_temp_6 = Cast(UShort, arg2)
    (*c2fb_temp_5) = Cast(u16, Cast(UShort, arg2))
    c2fb_temp_6 = Cast(UShort, (*c2fb_temp_5))
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function exprNodePatternLengthEst CDecl Alias "exprNodePatternLengthEst" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As UByte Ptr
    Dim local2 As UByte
    Dim local3 As UByte
    Dim local4 As UByte
    Dim local5 As UByte
    Dim c2fb_temp_0 As UByte
    Dim c2fb_temp_1 As UByte
    Dim c2fb_temp_2 As UByte
    Dim c2fb_temp_3 As UByte
    Dim c2fb_temp_4 As UByte
    Dim c2fb_temp_5 As UByte
    Dim c2fb_temp_6 As UByte Ptr
    Dim c2fb_temp_7 As UByte
    Dim c2fb_temp_8 As UByte Ptr
    Dim c2fb_temp_9 As UByte Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT Ptr
    Dim c2fb_temp_12 As SQLITE_C_INT

    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 118ULL))))) Then
        local0 = Cast(SQLITE_C_INT, &O0ULL)
        local1 = CPtr(UByte Ptr, CPtr(ZString Ptr, arg1->u.zToken))
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        If arg0->eCode Then
            c2fb_temp_0 = Cast(UByte, Cast(SQLITE_C_INT, 37))
            local3 = c2fb_temp_0
            c2fb_temp_1 = Cast(UByte, Cast(SQLITE_C_INT, 95))
            local4 = c2fb_temp_1
            c2fb_temp_2 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
            local5 = c2fb_temp_2
        Else
            c2fb_temp_3 = Cast(UByte, Cast(SQLITE_C_INT, 42))
            local3 = c2fb_temp_3
            c2fb_temp_4 = Cast(UByte, Cast(SQLITE_C_INT, 63))
            local4 = c2fb_temp_4
            c2fb_temp_5 = Cast(UByte, Cast(SQLITE_C_INT, 91))
            local5 = c2fb_temp_5
        End If
        Do
            c2fb_temp_6 = local1
            local1 = (c2fb_temp_6 + 1)
            c2fb_temp_7 = Cast(UByte, (*(c2fb_temp_6)))
            local2 = c2fb_temp_7
            If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (c2fb_temp_7)) <> Cast(SQLITE_C_INT, &O0ULL))))) = 0) Then Goto c2fb_flow_0
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2) = Cast(SQLITE_C_INT, local5))))) Then
                If (*local1) Then
                    c2fb_temp_8 = local1
                    local1 = (c2fb_temp_8 + 1)
                End If
                While (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (*local1)) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (*local1)) <> Cast(SQLITE_C_INT, 93)))))))))
                    c2fb_temp_9 = local1
                    local1 = (c2fb_temp_9 + 1)
                c2fb_flow_3:
                Wend
                c2fb_flow_2:
            Else
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2) <> Cast(SQLITE_C_INT, local3))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2) <> Cast(SQLITE_C_INT, local4))))))))) Then
                    c2fb_temp_10 = local0
                    local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_10 + 1)))
                End If
            End If
        c2fb_flow_1:
        Loop
        c2fb_flow_0:
        If (-Cast(SQLITE_C_INT, ((local0 > arg0->u.sz)))) Then
            c2fb_temp_11 = @(arg0->u.sz)
            c2fb_temp_12 = Cast(SQLITE_C_INT, local0)
            (*c2fb_temp_11) = c2fb_temp_12
        End If
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function estLikePatternLength CDecl Alias "estLikePatternLength" (ByVal arg0 As SqliteExpr Ptr, ByVal arg1 As UShort) As SQLITE_C_INT
    Dim local0 As SqliteWalker
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As UShort Ptr
    Dim c2fb_temp_3 As UShort
    Dim c2fb_temp_4 As SqliteWalkerExprCallback Ptr
    Dim c2fb_temp_5 As c2fb_callback_82
    Dim c2fb_temp_6 As SqliteWalkerSelectCallback Ptr
    Dim c2fb_temp_7 As c2fb_callback_82

    ' C automatic storage declaration
    c2fb_temp_0 = @(local0.u.sz)
    c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_0) = c2fb_temp_1
    c2fb_temp_2 = @(local0.eCode)
    c2fb_temp_3 = Cast(UShort, arg1)
    (*c2fb_temp_2) = c2fb_temp_3
    c2fb_temp_4 = @(local0.xExprCallback)
    c2fb_temp_5 = CPtr(c2fb_callback_82, ProcPtr(exprNodePatternLengthEst))
    (*c2fb_temp_4) = Cast(SqliteWalkerExprCallback, CPtr(c2fb_callback_82, ProcPtr(exprNodePatternLengthEst)))
    c2fb_temp_5 = CPtr(c2fb_callback_82, (*c2fb_temp_4))
    c2fb_temp_6 = @(local0.xSelectCallback)
    c2fb_temp_7 = CPtr(c2fb_callback_82, ProcPtr(sqlite3SelectWalkFail))
    (*c2fb_temp_6) = Cast(SqliteWalkerSelectCallback, CPtr(c2fb_callback_82, ProcPtr(sqlite3SelectWalkFail)))
    c2fb_temp_7 = CPtr(c2fb_callback_82, (*c2fb_temp_6))
    sqlite3WalkExpr(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local0))), CPtr(Any Ptr, arg0))
    Return local0.u.sz
End Function

Private Sub whereLoopOutputAdjust CDecl Alias "whereLoopOutputAdjust" (ByVal arg0 As SqliteWhereClause Ptr, ByVal arg1 As SqliteWhereLoop Ptr, ByVal arg2 As Short)
    Dim local0 As SqliteWhereTerm Ptr
    Dim local1 As SqliteWhereTerm Ptr
    Dim local2 As sqlite3_uint64
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As Short
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SqliteWhereTerm Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SqliteWhereTerm Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SqliteWhereTerm Ptr
    Dim c2fb_temp_7 As u32 Ptr
    Dim c2fb_temp_8 As SQLITE_C_UINT
    Dim c2fb_temp_9 As Short Ptr
    Dim c2fb_temp_10 As Short
    Dim local6 As SqliteExpr Ptr
    Dim c2fb_temp_11 As Short Ptr
    Dim c2fb_temp_12 As Short
    Dim local7 As SqliteExpr Ptr
    Dim local8 As SqliteParseContext Ptr
    Dim local9 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As u16 Ptr
    Dim c2fb_temp_16 As UShort
    Dim c2fb_temp_17 As Short
    Dim local10 As SQLITE_C_INT
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim local11 As SQLITE_C_INT
    Dim local12 As SqliteExpr Ptr
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As Short Ptr
    Dim c2fb_temp_22 As Short
    Dim c2fb_temp_23 As Short Ptr
    Dim c2fb_temp_24 As Short

    ' C automatic storage declaration
    ' C automatic storage declaration
    local2 = Cast(sqlite3_uint64, (Not (Cast(sqlite3_uint64, (arg1->prereq Or arg1->maskSelf)))))
    ' C automatic storage declaration
    ' C automatic storage declaration
    local5 = Cast(SQLITE_C_INT, &O0ULL)
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((CPtr(SqliteSrcList Ptr, CPtr(SqliteWhereInfo Ptr, arg0->pWInfo)->pTabList)->nSrc <= Cast(SQLITE_C_INT, 1ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((CPtr(SqliteExprList Ptr, CPtr(SqliteWhereInfo Ptr, arg0->pWInfo)->pOrderBy) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        Return
    End If
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, arg0->nBase)
    local3 = c2fb_temp_0
    c2fb_temp_1 = CPtr(SqliteWhereTerm Ptr, arg0->a)
    local0 = c2fb_temp_1
    While (-Cast(SQLITE_C_INT, ((local3 > Cast(SQLITE_C_INT, &O0ULL)))))
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local0->prereqAll And local2))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local0->prereqAll And arg1->maskSelf))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->wtFlags) And Cast(SQLITE_C_INT, &H0002ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_1
        End If
        c2fb_temp_4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->nLTerm) - Cast(SQLITE_C_INT, 1ULL))))
        local4 = c2fb_temp_4
        While (-Cast(SQLITE_C_INT, ((local4 >= Cast(SQLITE_C_INT, &O0ULL)))))
            c2fb_temp_6 = CPtr(SqliteWhereTerm Ptr Ptr, arg1->aLTerm)[local4]
            local1 = c2fb_temp_6
            If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                Goto c2fb_flow_3
            End If
            If (-Cast(SQLITE_C_INT, ((local1 = local0)))) Then
                Goto c2fb_flow_2
            End If
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local1->iParent >= Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((CPtr(SqliteWhereTerm Ptr, @(CPtr(SqliteWhereTerm Ptr, arg0->a)[local1->iParent]))) = local0)))))))) Then
                Goto c2fb_flow_2
            End If
        c2fb_flow_3:
            c2fb_temp_5 = local4
            local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_5 - 1)))
        Wend
        c2fb_flow_2:
        If (-Cast(SQLITE_C_INT, ((local4 < Cast(SQLITE_C_INT, &O0ULL))))) Then
            sqlite3ProgressCheck(CPtr(Any Ptr, CPtr(SqliteParseContext Ptr, CPtr(SqliteWhereInfo Ptr, arg0->pWInfo)->pParse)))
            If (-Cast(SQLITE_C_INT, ((arg1->maskSelf = local0->prereqAll)))) Then
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->eOperator) And Cast(SQLITE_C_INT, &H3fULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, CPtr(SqliteSrcList Ptr, CPtr(SqliteWhereInfo Ptr, arg0->pWInfo)->pTabList)->a(arg1->iTab).fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H40ULL))))))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                    c2fb_temp_7 = @(arg1->wsFlags)
                    c2fb_temp_8 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_7)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00800000ULL)))))
                    (*c2fb_temp_7) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_7)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00800000ULL))))))
                    c2fb_temp_8 = Cast(SQLITE_C_UINT, (*c2fb_temp_7))
                End If
            End If
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->truthProb) <= Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_9 = @(arg1->nOut)
                c2fb_temp_10 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (*c2fb_temp_9)) + Cast(SQLITE_C_INT, local0->truthProb))))
                (*c2fb_temp_9) = c2fb_temp_10
            Else
                local6 = CPtr(SqliteExpr Ptr, local0->pExpr)
                c2fb_temp_11 = @(arg1->nOut)
                c2fb_temp_12 = (*c2fb_temp_11)
                (*c2fb_temp_11) = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_12) - 1)))
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->eOperator) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0080ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->wtFlags) And Cast(SQLITE_C_INT, &O0ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                    local7 = CPtr(SqliteExpr Ptr, local6->pRight)
                    local8 = CPtr(SqliteParseContext Ptr, CPtr(SqliteWhereInfo Ptr, arg0->pWInfo)->pParse)
                    local9 = Cast(SQLITE_C_INT, &O0ULL)
                    ' empty C statement
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((sqlite3ExprIsInteger(CPtr(Any Ptr, local7), CPtr(SQLITE_C_INT Ptr, @(local9)), CPtr(Any Ptr, local8), Cast(SQLITE_C_INT, 1ULL)) AndAlso (-Cast(SQLITE_C_INT, ((local9 >= (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))))))))))) AndAlso (-Cast(SQLITE_C_INT, ((local9 <= Cast(SQLITE_C_INT, 1ULL))))))))) Then
                        c2fb_temp_13 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 10ULL))
                        local9 = c2fb_temp_13
                    Else
                        c2fb_temp_14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 20ULL))
                        local9 = c2fb_temp_14
                    End If
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local5) < local9)))) Then
                        c2fb_temp_15 = @(local0->wtFlags)
                        c2fb_temp_16 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_15))) Or Cast(SQLITE_C_INT, &H2000ULL))))
                        (*c2fb_temp_15) = Cast(u16, Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_15))) Or Cast(SQLITE_C_INT, &H2000ULL)))))
                        c2fb_temp_16 = Cast(UShort, (*c2fb_temp_15))
                        c2fb_temp_17 = Cast(Short, local9)
                        local5 = c2fb_temp_17
                    End If
                Else
                    If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local6)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000100ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local6->op) = Cast(SQLITE_C_INT, 172ULL))))))))) Then
                        ' C automatic storage declaration
                        ' C unused-parameter annotation
                        ' C unused-parameter annotation
                        c2fb_temp_18 = Cast(SQLITE_C_INT, sqlite3ExprIsLikeOperator(CPtr(Any Ptr, local6)))
                        local10 = c2fb_temp_18
                        If ((-Cast(SQLITE_C_INT, ((local10 > Cast(SQLITE_C_INT, &O0ULL)))))) Then
                            ' C automatic storage declaration
                            local12 = CPtr(SqliteExpr Ptr, CPtr(SqliteExprList Ptr, local6->x.pList)->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr)
                            c2fb_temp_19 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, ((local10 = Cast(SQLITE_C_INT, 65ULL))))))
                            local10 = c2fb_temp_19
                            c2fb_temp_20 = Cast(SQLITE_C_INT, estLikePatternLength(local12, local10))
                            local11 = c2fb_temp_20
                            If (-Cast(SQLITE_C_INT, ((local11 > Cast(SQLITE_C_INT, &O0ULL))))) Then
                                c2fb_temp_21 = @(arg1->nOut)
                                c2fb_temp_22 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (*c2fb_temp_21)) - Cast(SQLITE_C_INT, (local11 * Cast(SQLITE_C_INT, 2ULL))))))
                                (*c2fb_temp_21) = c2fb_temp_22
                            End If
                        End If
                    End If
                End If
            End If
        End If
    c2fb_flow_1:
        c2fb_temp_2 = local3
        local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_2 - 1)))
        c2fb_temp_3 = local0
        local0 = (c2fb_temp_3 + 1)
    Wend
    c2fb_flow_0:
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->nOut) > Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2) - Cast(SQLITE_C_INT, local5))))))) Then
        c2fb_temp_23 = @(arg1->nOut)
        c2fb_temp_24 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2) - Cast(SQLITE_C_INT, local5))))
        (*c2fb_temp_23) = c2fb_temp_24
    End If
End Sub

Private Function whereRangeVectorLen CDecl Alias "whereRangeVectorLen" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteIndex Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SqliteWhereTerm Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim local2 As Byte
    Dim local3 As Byte
    Dim local4 As sqlite3CollSeq Ptr
    Dim local5 As SqliteExpr Ptr
    Dim local6 As SqliteExpr Ptr
    Dim c2fb_temp_3 As SqliteExpr Ptr
    Dim c2fb_temp_4 As SqliteExpr Ptr
    Dim c2fb_temp_5 As SqliteExpr Ptr
    Dim c2fb_temp_6 As SqliteExpr Ptr
    Dim c2fb_temp_7 As Byte
    Dim c2fb_temp_8 As Byte
    Dim local7 As SqliteExpr Ptr
    Dim c2fb_temp_9 As SqliteExpr Ptr
    Dim c2fb_temp_10 As SqliteExpr Ptr
    Dim c2fb_temp_11 As sqlite3CollSeq Ptr

    local0 = sqlite3ExprVectorSize(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, CPtr(SqliteExpr Ptr, arg4->pExpr)->pLeft)))
    ' C automatic storage declaration
    c2fb_temp_0 = Cast(SQLITE_C_INT, (IIf((-Cast(SQLITE_C_INT, (((local0) < ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2->nColumn) - arg3)))))))), (local0), ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2->nColumn) - arg3)))))))
    local0 = c2fb_temp_0
    c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
    local1 = c2fb_temp_1
    While (-Cast(SQLITE_C_INT, ((local1 < local0))))
        ' C automatic storage declaration
        local3 = Cast(SQLITE_C_INT, &O0ULL)
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C unused-parameter annotation
        c2fb_temp_3 = CPtr(SqliteExpr Ptr, CPtr(SqliteExprList Ptr, CPtr(SqliteExpr Ptr, CPtr(SqliteExpr Ptr, arg4->pExpr)->pLeft)->x.pList)->a(local1).pExpr)
        local5 = c2fb_temp_3
        c2fb_temp_4 = CPtr(SqliteExpr Ptr, CPtr(SqliteExpr Ptr, arg4->pExpr)->pRight)
        local6 = c2fb_temp_4
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local6)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            c2fb_temp_5 = CPtr(SqliteExpr Ptr, CPtr(SqliteExprList Ptr, CPtr(SqliteSelect Ptr, local6->x.pSelect)->pEList)->a(local1).pExpr)
            local6 = c2fb_temp_5
        Else
            c2fb_temp_6 = CPtr(SqliteExpr Ptr, CPtr(SqliteExprList Ptr, local6->x.pList)->a(local1).pExpr)
            local6 = c2fb_temp_6
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local5->op) <> Cast(SQLITE_C_INT, 168ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local5->iTable <> arg1)))))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local5->iColumn) <> Cast(SQLITE_C_INT, arg2->aiColumn[Cast(SQLITE_C_INT, (local1 + arg3))]))))))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(UByte Ptr, arg2->aSortOrder)[Cast(SQLITE_C_INT, (local1 + arg3))]) <> Cast(SQLITE_C_INT, CPtr(UByte Ptr, arg2->aSortOrder)[arg3]))))))))) Then
            Goto c2fb_flow_0
        End If
        ' empty C statement
        c2fb_temp_7 = Cast(Byte, sqlite3CompareAffinity(CPtr(Any Ptr, local6), sqlite3ExprAffinity(CPtr(Any Ptr, local5))))
        local2 = c2fb_temp_7
        c2fb_temp_8 = Cast(Byte, sqlite3TableColumnAffinity(CPtr(Any Ptr, arg2->pTable), local5->iColumn))
        local3 = c2fb_temp_8
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2) <> Cast(SQLITE_C_INT, local3))))) Then
            Goto c2fb_flow_0
        End If
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((CPtr(SqliteExpr Ptr, arg4->pExpr))->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000400ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            local7 = local6
            c2fb_temp_9 = local5
            local6 = c2fb_temp_9
            c2fb_temp_10 = local7
            local5 = c2fb_temp_10
        End If
        ' empty C statement
        c2fb_temp_11 = CPtr(sqlite3CollSeq Ptr, sqlite3BinaryCompareCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local5), CPtr(Any Ptr, local6)))
        local4 = c2fb_temp_11
        If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_0
        End If
        If sqlite3StrICmp(CPtr(Const ZString Ptr, local4->zName), CPtr(Const ZString Ptr, CPtr(Const ZString Ptr Ptr, arg2->azColl)[Cast(SQLITE_C_INT, (local1 + arg3))])) Then
            Goto c2fb_flow_0
        End If
    c2fb_flow_1:
        c2fb_temp_2 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_2 + 1)))
    Wend
    c2fb_flow_0:
    Return local1
End Function

Function whereLoopAddBtreeIndex CDecl Alias "whereLoopAddBtreeIndex" (ByVal arg0 As SqliteWhereLoopBuilder Ptr, ByVal arg1 As SqliteSrcItem Ptr, ByVal arg2 As SqliteIndex Ptr, ByVal arg3 As Short) As SQLITE_C_INT
    Dim local0 As SqliteWhereInfo Ptr
    Dim local1 As SqliteParseContext Ptr
    Dim local2 As sqlite3 Ptr
    Dim local3 As SqliteWhereLoop Ptr
    Dim local4 As SqliteWhereTerm Ptr
    Dim local5 As SQLITE_C_INT
    Dim local6 As SqliteWhereScan
    Dim local7 As sqlite3_uint64
    Dim local8 As UShort
    Dim local9 As UShort
    Dim local10 As UShort
    Dim local11 As UShort
    Dim local12 As UShort
    Dim local13 As SQLITE_C_UINT
    Dim local14 As Short
    Dim local15 As SQLITE_C_INT
    Dim local16 As Short
    Dim local17 As Short
    Dim local18 As SqliteWhereTerm Ptr
    Dim local19 As SqliteWhereTerm Ptr
    Dim c2fb_temp_0 As SqliteWhereLoop Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As UShort
    Dim c2fb_temp_5 As UShort
    Dim c2fb_temp_6 As UShort
    Dim c2fb_temp_7 As UShort
    Dim c2fb_temp_8 As UShort
    Dim c2fb_temp_9 As SQLITE_C_UINT
    Dim c2fb_temp_10 As sqlite3_uint64
    Dim c2fb_temp_11 As Short
    Dim c2fb_temp_12 As SqliteWhereTerm Ptr
    Dim c2fb_temp_13 As Short Ptr
    Dim c2fb_temp_14 As Short
    Dim c2fb_temp_15 As Short
    Dim c2fb_temp_16 As Short
    Dim c2fb_temp_17 As SqliteWhereTerm Ptr
    Dim local20 As UShort
    Dim local21 As Short
    Dim local22 As Short
    Dim local23 As SQLITE_C_INT
    Dim c2fb_temp_18 As u8 Ptr
    Dim c2fb_temp_19 As UByte
    Dim c2fb_temp_20 As u8 Ptr
    Dim c2fb_temp_21 As UByte
    Dim c2fb_temp_22 As u32 Ptr
    Dim c2fb_temp_23 As SQLITE_C_UINT
    Dim c2fb_temp_24 As u16 Ptr
    Dim c2fb_temp_25 As UShort
    Dim c2fb_temp_26 As u16 Ptr
    Dim c2fb_temp_27 As UShort
    Dim c2fb_temp_28 As u16 Ptr
    Dim c2fb_temp_29 As UShort
    Dim c2fb_temp_30 As u16 Ptr
    Dim c2fb_temp_31 As UShort
    Dim c2fb_temp_32 As u16 Ptr
    Dim c2fb_temp_33 As UShort
    Dim c2fb_temp_34 As Any Ptr Ptr
    Dim c2fb_temp_35 As SqliteWhereTerm Ptr
    Dim c2fb_temp_36 As sqlite3_uint64 Ptr
    Dim c2fb_temp_37 As sqlite3_uint64
    Dim local24 As SqliteExpr Ptr
    Dim local25 As SQLITE_C_INT
    Dim local26 As SQLITE_C_INT
    Dim c2fb_temp_38 As SQLITE_C_INT
    Dim c2fb_temp_39 As SQLITE_C_INT
    Dim c2fb_temp_40 As SQLITE_C_INT
    Dim c2fb_temp_41 As SQLITE_C_INT
    Dim c2fb_temp_42 As SQLITE_C_INT
    Dim c2fb_temp_43 As u16 Ptr
    Dim c2fb_temp_44 As UShort
    Dim c2fb_temp_45 As SQLITE_C_INT
    Dim local27 As Short
    Dim local28 As Short
    Dim local29 As Short
    Dim c2fb_temp_46 As Short
    Dim c2fb_temp_47 As Short
    Dim c2fb_temp_48 As Short
    Dim c2fb_temp_49 As u32 Ptr
    Dim c2fb_temp_50 As SQLITE_C_UINT
    Dim c2fb_temp_51 As u32 Ptr
    Dim c2fb_temp_52 As SQLITE_C_UINT
    Dim local30 As SQLITE_C_INT
    Dim c2fb_temp_53 As u32 Ptr
    Dim c2fb_temp_54 As SQLITE_C_UINT
    Dim c2fb_temp_55 As u32 Ptr
    Dim c2fb_temp_56 As SQLITE_C_UINT
    Dim c2fb_temp_57 As u32 Ptr
    Dim c2fb_temp_58 As SQLITE_C_UINT
    Dim c2fb_temp_59 As u32 Ptr
    Dim c2fb_temp_60 As SQLITE_C_UINT
    Dim c2fb_temp_61 As u32 Ptr
    Dim c2fb_temp_62 As SQLITE_C_UINT
    Dim local31 As SQLITE_C_INT
    Dim c2fb_temp_63 As u32 Ptr
    Dim c2fb_temp_64 As SQLITE_C_UINT
    Dim c2fb_temp_65 As u16 Ptr
    Dim c2fb_temp_66 As UShort
    Dim c2fb_temp_67 As SqliteWhereTerm Ptr
    Dim c2fb_temp_68 As SqliteWhereTerm Ptr
    Dim c2fb_temp_69 As SqliteWhereTerm Ptr
    Dim c2fb_temp_70 As u16 Ptr
    Dim c2fb_temp_71 As UShort
    Dim c2fb_temp_72 As Any Ptr Ptr
    Dim c2fb_temp_73 As SqliteWhereTerm Ptr
    Dim c2fb_temp_74 As u32 Ptr
    Dim c2fb_temp_75 As SQLITE_C_UINT
    Dim c2fb_temp_76 As u16 Ptr
    Dim c2fb_temp_77 As UShort
    Dim c2fb_temp_78 As u32 Ptr
    Dim c2fb_temp_79 As SQLITE_C_UINT
    Dim c2fb_temp_80 As u16 Ptr
    Dim c2fb_temp_81 As UShort
    Dim c2fb_temp_82 As SqliteWhereTerm Ptr
    Dim c2fb_temp_83 As SqliteWhereTerm Ptr
    Dim c2fb_temp_84 As u16 Ptr
    Dim c2fb_temp_85 As UShort
    Dim c2fb_temp_86 As UShort
    Dim local32 As SQLITE_C_INT
    Dim c2fb_temp_87 As Short Ptr
    Dim c2fb_temp_88 As Short
    Dim c2fb_temp_89 As Short Ptr
    Dim c2fb_temp_90 As Short
    Dim c2fb_temp_91 As Short Ptr
    Dim c2fb_temp_92 As Short
    Dim c2fb_temp_93 As Short Ptr
    Dim c2fb_temp_94 As Short
    Dim c2fb_temp_95 As Short
    Dim c2fb_temp_96 As Short
    Dim c2fb_temp_97 As Short
    Dim c2fb_temp_98 As Short Ptr
    Dim c2fb_temp_99 As Short
    Dim c2fb_temp_100 As Short Ptr
    Dim c2fb_temp_101 As Short
    Dim c2fb_temp_102 As Short
    Dim c2fb_temp_103 As Short Ptr
    Dim c2fb_temp_104 As Short
    Dim c2fb_temp_105 As Short Ptr
    Dim c2fb_temp_106 As Short
    Dim c2fb_temp_107 As Short Ptr
    Dim c2fb_temp_108 As Short
    Dim c2fb_temp_109 As SQLITE_C_INT
    Dim c2fb_temp_110 As Short Ptr
    Dim c2fb_temp_111 As Short
    Dim c2fb_temp_112 As Short Ptr
    Dim c2fb_temp_113 As Short
    Dim c2fb_temp_114 As Short Ptr
    Dim c2fb_temp_115 As Short
    Dim c2fb_temp_116 As sqlite3_uint64 Ptr
    Dim c2fb_temp_117 As sqlite3_uint64
    Dim c2fb_temp_118 As u16 Ptr
    Dim c2fb_temp_119 As UShort
    Dim c2fb_temp_120 As u16 Ptr
    Dim c2fb_temp_121 As UShort
    Dim c2fb_temp_122 As u16 Ptr
    Dim c2fb_temp_123 As UShort
    Dim c2fb_temp_124 As u16 Ptr
    Dim c2fb_temp_125 As UShort
    Dim c2fb_temp_126 As u32 Ptr
    Dim c2fb_temp_127 As SQLITE_C_UINT
    Dim c2fb_temp_128 As Short Ptr
    Dim c2fb_temp_129 As Short
    Dim c2fb_temp_130 As u16 Ptr
    Dim c2fb_temp_131 As UShort
    Dim c2fb_temp_132 As SQLITE_C_INT
    Dim c2fb_temp_133 As SQLITE_C_INT
    Dim local33 As Short
    Dim c2fb_temp_134 As u16 Ptr
    Dim c2fb_temp_135 As UShort
    Dim c2fb_temp_136 As u16 Ptr
    Dim c2fb_temp_137 As UShort
    Dim c2fb_temp_138 As u16 Ptr
    Dim c2fb_temp_139 As UShort
    Dim c2fb_temp_140 As Any Ptr Ptr
    Dim c2fb_temp_141 As SqliteWhereTerm Ptr
    Dim c2fb_temp_142 As u32 Ptr
    Dim c2fb_temp_143 As SQLITE_C_UINT
    Dim c2fb_temp_144 As Short
    Dim c2fb_temp_145 As Short Ptr
    Dim c2fb_temp_146 As Short
    Dim c2fb_temp_147 As Short
    Dim c2fb_temp_148 As Short Ptr
    Dim c2fb_temp_149 As Short
    Dim c2fb_temp_150 As u16 Ptr
    Dim c2fb_temp_151 As UShort
    Dim c2fb_temp_152 As u16 Ptr
    Dim c2fb_temp_153 As UShort
    Dim c2fb_temp_154 As u32 Ptr
    Dim c2fb_temp_155 As SQLITE_C_UINT

    local0 = CPtr(SqliteWhereInfo Ptr, arg0->pWInfo)
    local1 = CPtr(SqliteParseContext Ptr, local0->pParse)
    local2 = local1->db
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local15 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    local18 = Cast(SQLITE_C_INT, &O0ULL)
    local19 = Cast(SQLITE_C_INT, &O0ULL)
    c2fb_temp_0 = arg0->pNew
    local3 = c2fb_temp_0
    ' C unused-parameter annotation
    If local1->nErr Then
        Return local1->rc
    End If
    ' empty C statement
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If Cast(SQLITE_C_UINT, (local3->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000020ULL)))) Then
        c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 57ULL) - Cast(SQLITE_C_INT, 54ULL))))))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 56ULL) - Cast(SQLITE_C_INT, 54ULL))))))))))
        local5 = c2fb_temp_1
    Else
        ' C unused-parameter annotation
        c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0001ULL))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 55ULL) - Cast(SQLITE_C_INT, 54ULL))))))))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 58ULL) - Cast(SQLITE_C_INT, 54ULL))))))))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 57ULL) - Cast(SQLITE_C_INT, 54ULL))))))))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 56ULL) - Cast(SQLITE_C_INT, 54ULL))))))))) Or Cast(SQLITE_C_INT, &H0100ULL))) Or Cast(SQLITE_C_INT, &H0080ULL))))
        local5 = c2fb_temp_2
    End If
    If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg2->flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) Then
        c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local5 And Cast(SQLITE_C_INT, (Not (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 55ULL) - Cast(SQLITE_C_INT, 54ULL))))))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 58ULL) - Cast(SQLITE_C_INT, 54ULL))))))))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 57ULL) - Cast(SQLITE_C_INT, 54ULL))))))))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 56ULL) - Cast(SQLITE_C_INT, 54ULL)))))))))))))))
        local5 = c2fb_temp_3
    End If
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_4 = Cast(UShort, local3->u.btree.nEq)
    local9 = c2fb_temp_4
    c2fb_temp_5 = Cast(UShort, local3->u.btree.nBtm)
    local10 = c2fb_temp_5
    c2fb_temp_6 = Cast(UShort, local3->u.btree.nTop)
    local11 = c2fb_temp_6
    c2fb_temp_7 = Cast(UShort, local3->nSkip)
    local12 = c2fb_temp_7
    c2fb_temp_8 = Cast(UShort, local3->nLTerm)
    local8 = c2fb_temp_8
    c2fb_temp_9 = Cast(SQLITE_C_UINT, local3->wsFlags)
    local13 = c2fb_temp_9
    c2fb_temp_10 = Cast(sqlite3_uint64, local3->prereq)
    local7 = c2fb_temp_10
    c2fb_temp_11 = Cast(Short, local3->nOut)
    local14 = c2fb_temp_11
    c2fb_temp_12 = CPtr(SqliteWhereTerm Ptr, whereScanInit(CPtr(SqliteWhereScan Ptr, @(local6)), CPtr(SqliteWhereClause Ptr, arg0->pWC), arg1->iCursor, local9, local5, arg2))
    local4 = c2fb_temp_12
    c2fb_temp_13 = @(local3->rSetup)
    c2fb_temp_14 = Cast(Short, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_13) = c2fb_temp_14
    c2fb_temp_15 = Cast(Short, arg2->aiRowLogEst[Cast(SQLITE_C_INT, &O0ULL)])
    local16 = c2fb_temp_15
    c2fb_temp_16 = Cast(Short, estLog(local16))
    local17 = c2fb_temp_16
    While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local15 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local4 <> Cast(SQLITE_C_INT, &O0ULL)))))))))
        local20 = local4->eOperator
        ' C automatic storage declaration
        ' C automatic storage declaration
        local23 = Cast(SQLITE_C_INT, &O0ULL)
        If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local20) = Cast(SQLITE_C_INT, &H0100ULL))))) OrElse (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local4->wtFlags) And Cast(SQLITE_C_INT, &H0080ULL)))) <> Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso indexColumnNotNull(arg2, local9))))) Then
            Goto c2fb_flow_1
        End If
        If Cast(sqlite3_uint64, (local4->prereqRight And local3->maskSelf)) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local4->wtFlags) And Cast(SQLITE_C_INT, &H0100ULL))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4->eOperator) = (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 57ULL) - Cast(SQLITE_C_INT, 54ULL))))))))))))))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H40ULL))) Or Cast(SQLITE_C_INT, &H10ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (constraintCompatibleWithOuterJoin(CPtr(Const SqliteWhereTerm Ptr, local4), CPtr(Const SqliteSrcItem Ptr, arg1)) = 0))))))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (arg2)->onError) <> Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local9) = Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2->nKeyCol) - Cast(SQLITE_C_INT, 1ULL))))))))))) Then
            c2fb_temp_18 = @(arg0->bldFlags1)
            c2fb_temp_19 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_18))) Or Cast(SQLITE_C_INT, &H0002ULL))))
            (*c2fb_temp_18) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_18))) Or Cast(SQLITE_C_INT, &H0002ULL)))))
            c2fb_temp_19 = Cast(UByte, (*c2fb_temp_18))
        Else
            c2fb_temp_20 = @(arg0->bldFlags1)
            c2fb_temp_21 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_20))) Or Cast(SQLITE_C_INT, &H0001ULL))))
            (*c2fb_temp_20) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_20))) Or Cast(SQLITE_C_INT, &H0001ULL)))))
            c2fb_temp_21 = Cast(UByte, (*c2fb_temp_20))
        End If
        c2fb_temp_22 = @(local3->wsFlags)
        c2fb_temp_23 = Cast(SQLITE_C_UINT, local13)
        (*c2fb_temp_22) = Cast(u32, Cast(SQLITE_C_UINT, local13))
        c2fb_temp_23 = Cast(SQLITE_C_UINT, (*c2fb_temp_22))
        c2fb_temp_24 = @(local3->u.btree.nEq)
        c2fb_temp_25 = Cast(UShort, local9)
        (*c2fb_temp_24) = Cast(u16, Cast(UShort, local9))
        c2fb_temp_25 = Cast(UShort, (*c2fb_temp_24))
        c2fb_temp_26 = @(local3->u.btree.nBtm)
        c2fb_temp_27 = Cast(UShort, local10)
        (*c2fb_temp_26) = Cast(u16, Cast(UShort, local10))
        c2fb_temp_27 = Cast(UShort, (*c2fb_temp_26))
        c2fb_temp_28 = @(local3->u.btree.nTop)
        c2fb_temp_29 = Cast(UShort, local11)
        (*c2fb_temp_28) = Cast(u16, Cast(UShort, local11))
        c2fb_temp_29 = Cast(UShort, (*c2fb_temp_28))
        c2fb_temp_30 = @(local3->nLTerm)
        c2fb_temp_31 = Cast(UShort, local8)
        (*c2fb_temp_30) = Cast(u16, Cast(UShort, local8))
        c2fb_temp_31 = Cast(UShort, (*c2fb_temp_30))
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->nLTerm) >= Cast(SQLITE_C_INT, local3->nLSlot))))) AndAlso whereLoopResize(local2, local3, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local3->nLTerm) + Cast(SQLITE_C_INT, 1ULL)))))))) Then
            Goto c2fb_flow_0
        End If
        c2fb_temp_32 = @(local3->nLTerm)
        c2fb_temp_33 = Cast(UShort, (*c2fb_temp_32))
        (*c2fb_temp_32) = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_33) + 1)))
        c2fb_temp_34 = @(CPtr(SqliteWhereTerm Ptr Ptr, local3->aLTerm)[c2fb_temp_33])
        c2fb_temp_35 = local4
        (*c2fb_temp_34) = CPtr(Any Ptr, local4)
        c2fb_temp_35 = CPtr(SqliteWhereTerm Ptr, (*c2fb_temp_34))
        c2fb_temp_36 = @(local3->prereq)
        c2fb_temp_37 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, (local7 Or local4->prereqRight))) And Cast(sqlite3_uint64, (Not local3->maskSelf)))))
        (*c2fb_temp_36) = c2fb_temp_37
        ' C unused-parameter annotation
        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local20) And Cast(SQLITE_C_INT, &H0001ULL))) Then
            local24 = CPtr(SqliteExpr Ptr, local4->pExpr)
            If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local24)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                ' C automatic storage declaration
                local26 = Cast(SQLITE_C_INT, &O0ULL)
                c2fb_temp_38 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 46ULL))
                local23 = c2fb_temp_38
                ' C unused-parameter annotation
                c2fb_temp_39 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local25 = c2fb_temp_39
                While (-Cast(SQLITE_C_INT, ((local25 < Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local3->nLTerm) - Cast(SQLITE_C_INT, 1ULL)))))))
                    If (-Cast(SQLITE_C_INT, ((CPtr(SqliteWhereTerm Ptr Ptr, local3->aLTerm)[local25] AndAlso (-Cast(SQLITE_C_INT, ((CPtr(SqliteExpr Ptr, CPtr(SqliteWhereTerm Ptr Ptr, local3->aLTerm)[local25]->pExpr) = local24)))))))) Then
                        c2fb_temp_41 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                        local23 = c2fb_temp_41
                        If (-Cast(SQLITE_C_INT, ((CPtr(SqliteWhereTerm Ptr Ptr, local3->aLTerm)[local25]->u.x.iField = local4->u.x.iField)))) Then
                            c2fb_temp_42 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                            local26 = c2fb_temp_42
                        End If
                    End If
                c2fb_flow_3:
                    c2fb_temp_40 = local25
                    local25 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_40 + 1)))
                Wend
                c2fb_flow_2:
                If local26 Then
                    c2fb_temp_43 = @(local3->nLTerm)
                    c2fb_temp_44 = Cast(UShort, (*c2fb_temp_43))
                    (*c2fb_temp_43) = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_44) - 1)))
                    Goto c2fb_flow_1
                End If
            Else
                If ((-Cast(SQLITE_C_INT, ((CPtr(SqliteExprList Ptr, local24->x.pList) AndAlso CPtr(SqliteExprList Ptr, local24->x.pList)->nExpr))))) Then
                    c2fb_temp_45 = Cast(SQLITE_C_INT, sqlite3LogEst(CPtr(SqliteExprList Ptr, local24->x.pList)->nExpr))
                    local23 = c2fb_temp_45
                End If
            End If
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg2->flags) Shr 7) And Cast(SQLITE_C_UINT, &H1ULL))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local17) >= Cast(SQLITE_C_INT, 10ULL))))))))) Then
                ' C automatic storage declaration
                ' C automatic storage declaration
                ' C automatic storage declaration
                c2fb_temp_46 = Cast(Short, arg2->aiRowLogEst[local9])
                local27 = c2fb_temp_46
                c2fb_temp_47 = Cast(Short, estLog(local23))
                local28 = c2fb_temp_47
                c2fb_temp_48 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local27) + Cast(SQLITE_C_INT, local28))) + Cast(SQLITE_C_INT, 10ULL))) - (Cast(SQLITE_C_INT, (local23 + Cast(SQLITE_C_INT, local17)))))))
                local29 = c2fb_temp_48
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local29) >= Cast(SQLITE_C_INT, &O0ULL))))) Then
                    ' empty C statement
                Else
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg3) < Cast(SQLITE_C_INT, 2ULL))))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local2)->dbOptFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H00020000ULL)))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
                        ' empty C statement
                        c2fb_temp_49 = @(local3->wsFlags)
                        c2fb_temp_50 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_49)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00100000ULL)))))
                        (*c2fb_temp_49) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_49)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00100000ULL))))))
                        c2fb_temp_50 = Cast(SQLITE_C_UINT, (*c2fb_temp_49))
                    Else
                        ' empty C statement
                        Goto c2fb_flow_1
                    End If
                End If
            End If
            c2fb_temp_51 = @(local3->wsFlags)
            c2fb_temp_52 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_51)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000004ULL)))))
            (*c2fb_temp_51) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_51)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000004ULL))))))
            c2fb_temp_52 = Cast(SQLITE_C_UINT, (*c2fb_temp_51))
        Else
            If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local20) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0080ULL)))))) Then
                local30 = arg2->aiColumn[local9]
                c2fb_temp_53 = @(local3->wsFlags)
                c2fb_temp_54 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_53)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000001ULL)))))
                (*c2fb_temp_53) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_53)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000001ULL))))))
                c2fb_temp_54 = Cast(SQLITE_C_UINT, (*c2fb_temp_53))
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local30 = (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local30 >= Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg3) = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local9) = Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2->nKeyCol) - Cast(SQLITE_C_INT, 1ULL)))))))))))))))) Then
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local30 = (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))))))) OrElse Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg2->flags) Shr 3) And Cast(SQLITE_C_UINT, &H1ULL))))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg2->nKeyCol) = Cast(SQLITE_C_INT, 1ULL))))) AndAlso Cast(SQLITE_C_INT, arg2->onError))))) AndAlso (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local20) And Cast(SQLITE_C_INT, &H0002ULL))))))))))))) Then
                        c2fb_temp_55 = @(local3->wsFlags)
                        c2fb_temp_56 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_55)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00001000ULL)))))
                        (*c2fb_temp_55) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_55)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00001000ULL))))))
                        c2fb_temp_56 = Cast(SQLITE_C_UINT, (*c2fb_temp_55))
                    Else
                        c2fb_temp_57 = @(local3->wsFlags)
                        c2fb_temp_58 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_57)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00010000ULL)))))
                        (*c2fb_temp_57) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_57)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00010000ULL))))))
                        c2fb_temp_58 = Cast(SQLITE_C_UINT, (*c2fb_temp_57))
                    End If
                End If
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local6.iEquiv) > Cast(SQLITE_C_INT, 1ULL))))) Then
                    c2fb_temp_59 = @(local3->wsFlags)
                    c2fb_temp_60 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_59)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00200000ULL)))))
                    (*c2fb_temp_59) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_59)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00200000ULL))))))
                    c2fb_temp_60 = Cast(SQLITE_C_UINT, (*c2fb_temp_59))
                End If
            Else
                If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local20) And Cast(SQLITE_C_INT, &H0100ULL))) Then
                    c2fb_temp_61 = @(local3->wsFlags)
                    c2fb_temp_62 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_61)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000008ULL)))))
                    (*c2fb_temp_61) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_61)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000008ULL))))))
                    c2fb_temp_62 = Cast(SQLITE_C_UINT, (*c2fb_temp_61))
                Else
                    local31 = whereRangeVectorLen(local1, arg1->iCursor, arg2, local9, local4)
                    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local20) And (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 55ULL) - Cast(SQLITE_C_INT, 54ULL))))))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 58ULL) - Cast(SQLITE_C_INT, 54ULL)))))))))))) Then
                        ' empty C statement
                        ' empty C statement
                        c2fb_temp_63 = @(local3->wsFlags)
                        c2fb_temp_64 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_63)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000002ULL) Or Cast(SQLITE_C_INT, &H00000020ULL)))))))
                        (*c2fb_temp_63) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_63)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000002ULL) Or Cast(SQLITE_C_INT, &H00000020ULL))))))))
                        c2fb_temp_64 = Cast(SQLITE_C_UINT, (*c2fb_temp_63))
                        c2fb_temp_65 = @(local3->u.btree.nBtm)
                        c2fb_temp_66 = Cast(UShort, local31)
                        (*c2fb_temp_65) = Cast(u16, Cast(UShort, local31))
                        c2fb_temp_66 = Cast(UShort, (*c2fb_temp_65))
                        c2fb_temp_67 = local4
                        local19 = c2fb_temp_67
                        c2fb_temp_68 = CPtr(SqliteWhereTerm Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                        local18 = c2fb_temp_68
                        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local4->wtFlags) And Cast(SQLITE_C_INT, &H0100ULL))) Then
                            c2fb_temp_69 = CPtr(SqliteWhereTerm Ptr, @(local4[Cast(SQLITE_C_INT, 1ULL)]))
                            local18 = c2fb_temp_69
                            ' C unused-parameter annotation
                            ' C unused-parameter annotation
                            ' C unused-parameter annotation
                            If whereLoopResize(local2, local3, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local3->nLTerm) + Cast(SQLITE_C_INT, 1ULL)))) Then
                                Goto c2fb_flow_0
                            End If
                            c2fb_temp_70 = @(local3->nLTerm)
                            c2fb_temp_71 = Cast(UShort, (*c2fb_temp_70))
                            (*c2fb_temp_70) = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_71) + 1)))
                            c2fb_temp_72 = @(CPtr(SqliteWhereTerm Ptr Ptr, local3->aLTerm)[c2fb_temp_71])
                            c2fb_temp_73 = local18
                            (*c2fb_temp_72) = CPtr(Any Ptr, local18)
                            c2fb_temp_73 = CPtr(SqliteWhereTerm Ptr, (*c2fb_temp_72))
                            c2fb_temp_74 = @(local3->wsFlags)
                            c2fb_temp_75 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_74)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000010ULL)))))
                            (*c2fb_temp_74) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_74)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000010ULL))))))
                            c2fb_temp_75 = Cast(SQLITE_C_UINT, (*c2fb_temp_74))
                            c2fb_temp_76 = @(local3->u.btree.nTop)
                            c2fb_temp_77 = Cast(UShort, Cast(SQLITE_C_INT, 1ULL))
                            (*c2fb_temp_76) = Cast(u16, Cast(UShort, Cast(SQLITE_C_INT, 1ULL)))
                            c2fb_temp_77 = Cast(UShort, (*c2fb_temp_76))
                        End If
                    Else
                        ' C unused-parameter annotation
                        ' empty C statement
                        ' empty C statement
                        c2fb_temp_78 = @(local3->wsFlags)
                        c2fb_temp_79 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_78)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000002ULL) Or Cast(SQLITE_C_INT, &H00000010ULL)))))))
                        (*c2fb_temp_78) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_78)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000002ULL) Or Cast(SQLITE_C_INT, &H00000010ULL))))))))
                        c2fb_temp_79 = Cast(SQLITE_C_UINT, (*c2fb_temp_78))
                        c2fb_temp_80 = @(local3->u.btree.nTop)
                        c2fb_temp_81 = Cast(UShort, local31)
                        (*c2fb_temp_80) = Cast(u16, Cast(UShort, local31))
                        c2fb_temp_81 = Cast(UShort, (*c2fb_temp_80))
                        c2fb_temp_82 = local4
                        local18 = c2fb_temp_82
                        c2fb_temp_83 = IIf((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local3->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000020ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))), CPtr(SqliteWhereTerm Ptr Ptr, local3->aLTerm)[Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local3->nLTerm) - Cast(SQLITE_C_INT, 2ULL)))], CPtr(SqliteWhereTerm Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
                        local19 = c2fb_temp_83
                    End If
                End If
            End If
        End If
        ' C unused-parameter annotation
        If Cast(SQLITE_C_UINT, (local3->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000002ULL)))) Then
            whereRangeScanEst(local1, arg0, local19, local18, local3)
        Else
            c2fb_temp_84 = @(local3->u.btree.nEq)
            c2fb_temp_85 = Cast(UShort, (*c2fb_temp_84))
            (*c2fb_temp_84) = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_85) + 1)))
            c2fb_temp_86 = (*c2fb_temp_84)
            local32 = c2fb_temp_86
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4->truthProb) <= Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg2->aiColumn[local9]) >= Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                ' C unused-parameter annotation
                ' empty C statement
                c2fb_temp_87 = @(local3->nOut)
                c2fb_temp_88 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (*c2fb_temp_87)) + Cast(SQLITE_C_INT, local4->truthProb))))
                (*c2fb_temp_87) = c2fb_temp_88
                c2fb_temp_89 = @(local3->nOut)
                c2fb_temp_90 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (*c2fb_temp_89)) - local23)))
                (*c2fb_temp_89) = c2fb_temp_90
            Else
                c2fb_temp_91 = @(local3->nOut)
                c2fb_temp_92 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (*c2fb_temp_91)) + (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2->aiRowLogEst[local32]) - Cast(SQLITE_C_INT, arg2->aiRowLogEst[Cast(SQLITE_C_INT, (local32 - Cast(SQLITE_C_INT, 1ULL)))])))))))
                (*c2fb_temp_91) = c2fb_temp_92
                If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local20) And Cast(SQLITE_C_INT, &H0100ULL))) Then
                    c2fb_temp_93 = @(local3->nOut)
                    c2fb_temp_94 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (*c2fb_temp_93)) + Cast(SQLITE_C_INT, 10ULL))))
                    (*c2fb_temp_93) = c2fb_temp_94
                End If
            End If
        End If
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg2->flags) Shr 0) And Cast(SQLITE_C_UINT, &H3ULL))) = Cast(SQLITE_C_INT, 3ULL))))) Then
            c2fb_temp_95 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local3->nOut) + Cast(SQLITE_C_INT, 16ULL))))
            local21 = c2fb_temp_95
        Else
            c2fb_temp_96 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local3->nOut) + Cast(SQLITE_C_INT, 1ULL))) + Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 15ULL) * Cast(SQLITE_C_INT, arg2->szIdxRow)))) \ Cast(SQLITE_C_INT, CPtr(SqliteTable Ptr, arg1->pSTab)->szTabRow))))))
            local21 = c2fb_temp_96
        End If
        c2fb_temp_97 = Cast(Short, sqlite3LogEstAdd(local17, local21))
        local21 = c2fb_temp_97
        c2fb_temp_98 = @(local3->rRun)
        c2fb_temp_99 = Cast(Short, local21)
        (*c2fb_temp_98) = c2fb_temp_99
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local3->wsFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000040ULL) Or Cast(SQLITE_C_INT, &H00000100ULL))) Or Cast(SQLITE_C_INT, &H04000000ULL)))))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            c2fb_temp_100 = @(local3->rRun)
            c2fb_temp_101 = Cast(Short, sqlite3LogEstAdd(local3->rRun, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local3->nOut) + Cast(SQLITE_C_INT, 16ULL)))))
            (*c2fb_temp_100) = c2fb_temp_101
        End If
        ' empty C statement
        c2fb_temp_102 = Cast(Short, local3->nOut)
        local22 = c2fb_temp_102
        c2fb_temp_103 = @(local3->rRun)
        c2fb_temp_104 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (*c2fb_temp_103)) + Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg3) + local23)))))
        (*c2fb_temp_103) = c2fb_temp_104
        c2fb_temp_105 = @(local3->nOut)
        c2fb_temp_106 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (*c2fb_temp_105)) + Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg3) + local23)))))
        (*c2fb_temp_105) = c2fb_temp_106
        whereLoopOutputAdjust(CPtr(SqliteWhereClause Ptr, arg0->pWC), local3, local16)
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg1->fg.flags) Shr 18) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            c2fb_temp_107 = @(local3->nOut)
            c2fb_temp_108 = Cast(Short, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_107) = c2fb_temp_108
        End If
        c2fb_temp_109 = Cast(SQLITE_C_INT, whereLoopInsert(arg0, local3))
        local15 = c2fb_temp_109
        If Cast(SQLITE_C_UINT, (local3->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000002ULL)))) Then
            c2fb_temp_110 = @(local3->nOut)
            c2fb_temp_111 = Cast(Short, local14)
            (*c2fb_temp_110) = c2fb_temp_111
        Else
            c2fb_temp_112 = @(local3->nOut)
            c2fb_temp_113 = Cast(Short, local22)
            (*c2fb_temp_112) = c2fb_temp_113
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local3->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000010ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->u.btree.nEq) < Cast(SQLITE_C_INT, arg2->nColumn))))))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->u.btree.nEq) < Cast(SQLITE_C_INT, arg2->nKeyCol))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg2->flags) Shr 0) And Cast(SQLITE_C_UINT, &H3ULL))) <> Cast(SQLITE_C_INT, 2ULL)))))))))))))) Then
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->u.btree.nEq) > Cast(SQLITE_C_INT, 3ULL))))) Then
                sqlite3ProgressCheck(CPtr(Any Ptr, local1))
            End If
            whereLoopAddBtreeIndex(arg0, arg1, arg2, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg3) + local23)))
        End If
        c2fb_temp_114 = @(local3->nOut)
        c2fb_temp_115 = Cast(Short, local14)
        (*c2fb_temp_114) = c2fb_temp_115
    c2fb_flow_1:
        c2fb_temp_17 = CPtr(SqliteWhereTerm Ptr, whereScanNext(CPtr(SqliteWhereScan Ptr, @(local6))))
        local4 = c2fb_temp_17
    Wend
    c2fb_flow_0:
    c2fb_temp_116 = @(local3->prereq)
    c2fb_temp_117 = Cast(sqlite3_uint64, local7)
    (*c2fb_temp_116) = c2fb_temp_117
    c2fb_temp_118 = @(local3->u.btree.nEq)
    c2fb_temp_119 = Cast(UShort, local9)
    (*c2fb_temp_118) = Cast(u16, Cast(UShort, local9))
    c2fb_temp_119 = Cast(UShort, (*c2fb_temp_118))
    c2fb_temp_120 = @(local3->u.btree.nBtm)
    c2fb_temp_121 = Cast(UShort, local10)
    (*c2fb_temp_120) = Cast(u16, Cast(UShort, local10))
    c2fb_temp_121 = Cast(UShort, (*c2fb_temp_120))
    c2fb_temp_122 = @(local3->u.btree.nTop)
    c2fb_temp_123 = Cast(UShort, local11)
    (*c2fb_temp_122) = Cast(u16, Cast(UShort, local11))
    c2fb_temp_123 = Cast(UShort, (*c2fb_temp_122))
    c2fb_temp_124 = @(local3->nSkip)
    c2fb_temp_125 = Cast(UShort, local12)
    (*c2fb_temp_124) = Cast(u16, Cast(UShort, local12))
    c2fb_temp_125 = Cast(UShort, (*c2fb_temp_124))
    c2fb_temp_126 = @(local3->wsFlags)
    c2fb_temp_127 = Cast(SQLITE_C_UINT, local13)
    (*c2fb_temp_126) = Cast(u32, Cast(SQLITE_C_UINT, local13))
    c2fb_temp_127 = Cast(SQLITE_C_UINT, (*c2fb_temp_126))
    c2fb_temp_128 = @(local3->nOut)
    c2fb_temp_129 = Cast(Short, local14)
    (*c2fb_temp_128) = c2fb_temp_129
    c2fb_temp_130 = @(local3->nLTerm)
    c2fb_temp_131 = Cast(UShort, local8)
    (*c2fb_temp_130) = Cast(u16, Cast(UShort, local8))
    c2fb_temp_131 = Cast(UShort, (*c2fb_temp_130))
    ' C unused-parameter annotation
    c2fb_temp_133 = 0
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local9) = Cast(SQLITE_C_INT, local12))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local9) + Cast(SQLITE_C_INT, 1ULL))) < Cast(SQLITE_C_INT, arg2->nKeyCol))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local9) = Cast(SQLITE_C_INT, local3->nLTerm))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg2->flags) Shr 6) And Cast(SQLITE_C_UINT, &H1ULL))) = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg2->flags) Shr 7) And Cast(SQLITE_C_UINT, &H1ULL))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local2)->dbOptFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H00004000ULL)))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg2->aiRowLogEst[Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local9) + Cast(SQLITE_C_INT, 1ULL)))]) >= Cast(SQLITE_C_INT, 42ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg1->fg.flags) Shr 18) And Cast(SQLITE_C_UINT, &H1ULL))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        c2fb_temp_132 = Cast(SQLITE_C_INT, whereLoopResize(local2, local3, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local3->nLTerm) + Cast(SQLITE_C_INT, 1ULL)))))
        local15 = c2fb_temp_132
        c2fb_temp_133 = (-Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, (((c2fb_temp_132) = Cast(SQLITE_C_INT, &O0ULL))))) <> 0)))
    End If
    If c2fb_temp_133 Then
        ' C automatic storage declaration
        c2fb_temp_134 = @(local3->u.btree.nEq)
        c2fb_temp_135 = Cast(UShort, (*c2fb_temp_134))
        (*c2fb_temp_134) = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_135) + 1)))
        c2fb_temp_136 = @(local3->nSkip)
        c2fb_temp_137 = Cast(UShort, (*c2fb_temp_136))
        (*c2fb_temp_136) = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_137) + 1)))
        c2fb_temp_138 = @(local3->nLTerm)
        c2fb_temp_139 = Cast(UShort, (*c2fb_temp_138))
        (*c2fb_temp_138) = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_139) + 1)))
        c2fb_temp_140 = @(CPtr(SqliteWhereTerm Ptr Ptr, local3->aLTerm)[c2fb_temp_139])
        c2fb_temp_141 = CPtr(SqliteWhereTerm Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_140) = CPtr(Any Ptr, CPtr(SqliteWhereTerm Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
        c2fb_temp_141 = CPtr(SqliteWhereTerm Ptr, (*c2fb_temp_140))
        c2fb_temp_142 = @(local3->wsFlags)
        c2fb_temp_143 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_142)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00008000ULL)))))
        (*c2fb_temp_142) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_142)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00008000ULL))))))
        c2fb_temp_143 = Cast(SQLITE_C_UINT, (*c2fb_temp_142))
        c2fb_temp_144 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2->aiRowLogEst[local9]) - Cast(SQLITE_C_INT, arg2->aiRowLogEst[Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local9) + Cast(SQLITE_C_INT, 1ULL)))]))))
        local33 = c2fb_temp_144
        c2fb_temp_145 = @(local3->nOut)
        c2fb_temp_146 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (*c2fb_temp_145)) - Cast(SQLITE_C_INT, local33))))
        (*c2fb_temp_145) = c2fb_temp_146
        c2fb_temp_147 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local33) + Cast(SQLITE_C_INT, 5ULL))))
        local33 = c2fb_temp_147
        whereLoopAddBtreeIndex(arg0, arg1, arg2, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local33) + Cast(SQLITE_C_INT, arg3))))
        c2fb_temp_148 = @(local3->nOut)
        c2fb_temp_149 = Cast(Short, local14)
        (*c2fb_temp_148) = c2fb_temp_149
        c2fb_temp_150 = @(local3->u.btree.nEq)
        c2fb_temp_151 = Cast(UShort, local9)
        (*c2fb_temp_150) = Cast(u16, Cast(UShort, local9))
        c2fb_temp_151 = Cast(UShort, (*c2fb_temp_150))
        c2fb_temp_152 = @(local3->nSkip)
        c2fb_temp_153 = Cast(UShort, local12)
        (*c2fb_temp_152) = Cast(u16, Cast(UShort, local12))
        c2fb_temp_153 = Cast(UShort, (*c2fb_temp_152))
        c2fb_temp_154 = @(local3->wsFlags)
        c2fb_temp_155 = Cast(SQLITE_C_UINT, local13)
        (*c2fb_temp_154) = Cast(u32, Cast(SQLITE_C_UINT, local13))
        c2fb_temp_155 = Cast(SQLITE_C_UINT, (*c2fb_temp_154))
    End If
    ' empty C statement
    Return local15
End Function

Private Function whereShortCut CDecl Alias "whereShortCut" (ByVal arg0 As SqliteWhereLoopBuilder Ptr) As SQLITE_C_INT
    Dim local0 As SqliteWhereInfo Ptr
    Dim local1 As SqliteSrcItem Ptr
    Dim local2 As SqliteWhereClause Ptr
    Dim local3 As SqliteWhereTerm Ptr
    Dim local4 As SqliteWhereLoop Ptr
    Dim local5 As SQLITE_C_INT
    Dim local6 As SQLITE_C_INT
    Dim local7 As SqliteTable Ptr
    Dim local8 As SqliteIndex Ptr
    Dim local9 As SqliteWhereScan
    Dim c2fb_temp_0 As SqliteWhereInfo Ptr
    Dim c2fb_temp_1 As SqliteSrcItem Ptr
    Dim c2fb_temp_2 As SqliteTable Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SqliteWhereClause Ptr
    Dim c2fb_temp_5 As SqliteWhereLoop Ptr
    Dim c2fb_temp_6 As u32 Ptr
    Dim c2fb_temp_7 As SQLITE_C_UINT
    Dim c2fb_temp_8 As u16 Ptr
    Dim c2fb_temp_9 As UShort
    Dim c2fb_temp_10 As SqliteWhereTerm Ptr
    Dim c2fb_temp_11 As SqliteWhereTerm Ptr
    Dim c2fb_temp_12 As u32 Ptr
    Dim c2fb_temp_13 As SQLITE_C_UINT
    Dim c2fb_temp_14 As Any Ptr Ptr
    Dim c2fb_temp_15 As SqliteWhereTerm Ptr
    Dim c2fb_temp_16 As u16 Ptr
    Dim c2fb_temp_17 As UShort
    Dim c2fb_temp_18 As u16 Ptr
    Dim c2fb_temp_19 As UShort
    Dim c2fb_temp_20 As Short Ptr
    Dim c2fb_temp_21 As Short
    Dim c2fb_temp_22 As SqliteIndex Ptr
    Dim c2fb_temp_23 As SqliteIndex Ptr
    Dim local10 As SQLITE_C_INT
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As SQLITE_C_INT
    Dim c2fb_temp_26 As SQLITE_C_INT
    Dim c2fb_temp_27 As SqliteWhereTerm Ptr
    Dim c2fb_temp_28 As SqliteWhereTerm Ptr
    Dim c2fb_temp_29 As Any Ptr Ptr
    Dim c2fb_temp_30 As SqliteWhereTerm Ptr
    Dim c2fb_temp_31 As u32 Ptr
    Dim c2fb_temp_32 As SQLITE_C_UINT
    Dim c2fb_temp_33 As u32 Ptr
    Dim c2fb_temp_34 As SQLITE_C_UINT
    Dim c2fb_temp_35 As u16 Ptr
    Dim c2fb_temp_36 As UShort
    Dim c2fb_temp_37 As u16 Ptr
    Dim c2fb_temp_38 As UShort
    Dim c2fb_temp_39 As Any Ptr Ptr
    Dim c2fb_temp_40 As SqliteIndex Ptr
    Dim c2fb_temp_41 As Short Ptr
    Dim c2fb_temp_42 As Short
    Dim c2fb_temp_43 As Short Ptr
    Dim c2fb_temp_44 As Short
    Dim c2fb_temp_45 As SqliteWhereLoop Ptr Ptr
    Dim c2fb_temp_46 As SqliteWhereLoop Ptr
    Dim c2fb_temp_47 As sqlite3_uint64 Ptr
    Dim c2fb_temp_48 As sqlite3_uint64
    Dim c2fb_temp_49 As SQLITE_C_INT Ptr
    Dim c2fb_temp_50 As SQLITE_C_INT
    Dim c2fb_temp_51 As Short Ptr
    Dim c2fb_temp_52 As Short
    Dim c2fb_temp_53 As Byte Ptr
    Dim c2fb_temp_54 As Byte
    Dim c2fb_temp_55 As u8 Ptr
    Dim c2fb_temp_56 As UByte
    Dim c2fb_temp_57 As u32 Ptr
    Dim c2fb_temp_58 As SQLITE_C_UINT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    c2fb_temp_0 = CPtr(SqliteWhereInfo Ptr, arg0->pWInfo)
    local0 = c2fb_temp_0
    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->wctrlFlags) And Cast(SQLITE_C_INT, &H0020ULL))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    ' C unused-parameter annotation
    c2fb_temp_1 = CPtr(SqliteSrcItem Ptr, (@CPtr(SqliteSrcList Ptr, local0->pTabList)->a(0)))
    local1 = c2fb_temp_1
    c2fb_temp_2 = CPtr(SqliteTable Ptr, local1->pSTab)
    local7 = c2fb_temp_2
    If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local7)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 1) And Cast(SQLITE_C_UINT, &H1ULL))) OrElse Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 0) And Cast(SQLITE_C_UINT, &H1ULL))))))) Then
        ' empty C statement
        ' empty C statement
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_3 = Cast(SQLITE_C_INT, local1->iCursor)
    local5 = c2fb_temp_3
    c2fb_temp_4 = CPtr(SqliteWhereClause Ptr, @(local0->sWC))
    local2 = c2fb_temp_4
    c2fb_temp_5 = arg0->pNew
    local4 = c2fb_temp_5
    c2fb_temp_6 = @(local4->wsFlags)
    c2fb_temp_7 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_6) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))
    c2fb_temp_7 = Cast(SQLITE_C_UINT, (*c2fb_temp_6))
    c2fb_temp_8 = @(local4->nSkip)
    c2fb_temp_9 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_8) = Cast(u16, Cast(UShort, Cast(SQLITE_C_INT, &O0ULL)))
    c2fb_temp_9 = Cast(UShort, (*c2fb_temp_8))
    c2fb_temp_10 = CPtr(SqliteWhereTerm Ptr, whereScanInit(CPtr(SqliteWhereScan Ptr, @(local9)), local2, local5, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0080ULL))), Cast(SQLITE_C_INT, &O0ULL)))
    local3 = c2fb_temp_10
    While (-Cast(SQLITE_C_INT, ((local3 AndAlso local3->prereqRight))))
        c2fb_temp_11 = CPtr(SqliteWhereTerm Ptr, whereScanNext(CPtr(SqliteWhereScan Ptr, @(local9))))
        local3 = c2fb_temp_11
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    If local3 Then
        ' empty C statement
        c2fb_temp_12 = @(local4->wsFlags)
        c2fb_temp_13 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000001ULL) Or Cast(SQLITE_C_INT, &H00000100ULL))) Or Cast(SQLITE_C_INT, &H00001000ULL))))
        (*c2fb_temp_12) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000001ULL) Or Cast(SQLITE_C_INT, &H00000100ULL))) Or Cast(SQLITE_C_INT, &H00001000ULL)))))
        c2fb_temp_13 = Cast(SQLITE_C_UINT, (*c2fb_temp_12))
        c2fb_temp_14 = @(CPtr(SqliteWhereTerm Ptr Ptr, local4->aLTerm)[Cast(SQLITE_C_INT, &O0ULL)])
        c2fb_temp_15 = local3
        (*c2fb_temp_14) = CPtr(Any Ptr, local3)
        c2fb_temp_15 = CPtr(SqliteWhereTerm Ptr, (*c2fb_temp_14))
        c2fb_temp_16 = @(local4->nLTerm)
        c2fb_temp_17 = Cast(UShort, Cast(SQLITE_C_INT, 1ULL))
        (*c2fb_temp_16) = Cast(u16, Cast(UShort, Cast(SQLITE_C_INT, 1ULL)))
        c2fb_temp_17 = Cast(UShort, (*c2fb_temp_16))
        c2fb_temp_18 = @(local4->u.btree.nEq)
        c2fb_temp_19 = Cast(UShort, Cast(SQLITE_C_INT, 1ULL))
        (*c2fb_temp_18) = Cast(u16, Cast(UShort, Cast(SQLITE_C_INT, 1ULL)))
        c2fb_temp_19 = Cast(UShort, (*c2fb_temp_18))
        c2fb_temp_20 = @(local4->rRun)
        c2fb_temp_21 = Cast(Short, Cast(SQLITE_C_INT, 33ULL))
        (*c2fb_temp_20) = c2fb_temp_21
    Else
        c2fb_temp_22 = CPtr(SqliteIndex Ptr, local7->pIndex)
        local8 = c2fb_temp_22
        While local8
            ' C automatic storage declaration
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local8)->onError) <> Cast(SQLITE_C_INT, &O0ULL)))))) = 0))) OrElse (-Cast(SQLITE_C_INT, ((CPtr(SqliteExpr Ptr, local8->pPartIdxWhere) <> Cast(SQLITE_C_INT, &O0ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local8->nKeyCol) > (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, (Cast(SQLITE_C_INT, 3ULL) * SizeOf(SqliteWhereTerm Ptr)))) \ Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereTerm Ptr)))))))))))))))) Then
                Goto c2fb_flow_3
            End If
            c2fb_temp_24 = Cast(SQLITE_C_INT, IIf(Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local8->flags) Shr 3) And Cast(SQLITE_C_UINT, &H1ULL))), (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0080ULL)))), Cast(SQLITE_C_INT, &H0002ULL)))
            local10 = c2fb_temp_24
            c2fb_temp_25 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local6 = c2fb_temp_25
            While (-Cast(SQLITE_C_INT, ((local6 < Cast(SQLITE_C_INT, local8->nKeyCol)))))
                c2fb_temp_27 = CPtr(SqliteWhereTerm Ptr, whereScanInit(CPtr(SqliteWhereScan Ptr, @(local9)), local2, local5, local6, local10, local8))
                local3 = c2fb_temp_27
                While (-Cast(SQLITE_C_INT, ((local3 AndAlso local3->prereqRight))))
                    c2fb_temp_28 = CPtr(SqliteWhereTerm Ptr, whereScanNext(CPtr(SqliteWhereScan Ptr, @(local9))))
                    local3 = c2fb_temp_28
                c2fb_flow_7:
                Wend
                c2fb_flow_6:
                If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    Goto c2fb_flow_4
                End If
                ' empty C statement
                c2fb_temp_29 = @(CPtr(SqliteWhereTerm Ptr Ptr, local4->aLTerm)[local6])
                c2fb_temp_30 = local3
                (*c2fb_temp_29) = CPtr(Any Ptr, local3)
                c2fb_temp_30 = CPtr(SqliteWhereTerm Ptr, (*c2fb_temp_29))
            c2fb_flow_5:
                c2fb_temp_26 = local6
                local6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_26 + 1)))
            Wend
            c2fb_flow_4:
            If (-Cast(SQLITE_C_INT, ((local6 <> Cast(SQLITE_C_INT, local8->nKeyCol))))) Then
                Goto c2fb_flow_3
            End If
            c2fb_temp_31 = @(local4->wsFlags)
            c2fb_temp_32 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000001ULL) Or Cast(SQLITE_C_INT, &H00001000ULL))) Or Cast(SQLITE_C_INT, &H00000200ULL))))
            (*c2fb_temp_31) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000001ULL) Or Cast(SQLITE_C_INT, &H00001000ULL))) Or Cast(SQLITE_C_INT, &H00000200ULL)))))
            c2fb_temp_32 = Cast(SQLITE_C_UINT, (*c2fb_temp_31))
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local8->flags) Shr 5) And Cast(SQLITE_C_UINT, &H1ULL))) OrElse (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local1->colUsed And local8->colNotIdxed))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
                c2fb_temp_33 = @(local4->wsFlags)
                c2fb_temp_34 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_33)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000040ULL)))))
                (*c2fb_temp_33) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_33)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000040ULL))))))
                c2fb_temp_34 = Cast(SQLITE_C_UINT, (*c2fb_temp_33))
            End If
            c2fb_temp_35 = @(local4->nLTerm)
            c2fb_temp_36 = Cast(UShort, local6)
            (*c2fb_temp_35) = Cast(u16, Cast(UShort, local6))
            c2fb_temp_36 = Cast(UShort, (*c2fb_temp_35))
            c2fb_temp_37 = @(local4->u.btree.nEq)
            c2fb_temp_38 = Cast(UShort, local6)
            (*c2fb_temp_37) = Cast(u16, Cast(UShort, local6))
            c2fb_temp_38 = Cast(UShort, (*c2fb_temp_37))
            c2fb_temp_39 = @(local4->u.btree.pIndex)
            c2fb_temp_40 = local8
            (*c2fb_temp_39) = CPtr(Any Ptr, local8)
            c2fb_temp_40 = CPtr(SqliteIndex Ptr, (*c2fb_temp_39))
            c2fb_temp_41 = @(local4->rRun)
            c2fb_temp_42 = Cast(Short, Cast(SQLITE_C_INT, 39ULL))
            (*c2fb_temp_41) = c2fb_temp_42
            Goto c2fb_flow_2
        c2fb_flow_3:
            c2fb_temp_23 = local8->pNext
            local8 = c2fb_temp_23
        Wend
        c2fb_flow_2:
    End If
    If local4->wsFlags Then
        c2fb_temp_43 = @(local4->nOut)
        c2fb_temp_44 = Cast(Short, Cast(Short, Cast(SQLITE_C_INT, 1ULL)))
        (*c2fb_temp_43) = c2fb_temp_44
        c2fb_temp_45 = @(local0->a(Cast(SQLITE_C_INT, &O0ULL)).pWLoop)
        c2fb_temp_46 = local4
        (*c2fb_temp_45) = c2fb_temp_46
        ' C unused-parameter annotation
        c2fb_temp_47 = @(local4->maskSelf)
        c2fb_temp_48 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))
        (*c2fb_temp_47) = c2fb_temp_48
        c2fb_temp_49 = @(local0->a(Cast(SQLITE_C_INT, &O0ULL)).iTabCur)
        c2fb_temp_50 = Cast(SQLITE_C_INT, local5)
        (*c2fb_temp_49) = c2fb_temp_50
        c2fb_temp_51 = @(local0->nRowOut)
        c2fb_temp_52 = Cast(Short, Cast(SQLITE_C_INT, 1ULL))
        (*c2fb_temp_51) = c2fb_temp_52
        If CPtr(SqliteExprList Ptr, local0->pOrderBy) Then
            c2fb_temp_53 = @(local0->nOBSat)
            c2fb_temp_54 = Cast(Byte, CPtr(SqliteExprList Ptr, local0->pOrderBy)->nExpr)
            (*c2fb_temp_53) = c2fb_temp_54
        End If
        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->wctrlFlags) And Cast(SQLITE_C_INT, &H0100ULL))) Then
            c2fb_temp_55 = @(local0->eDistinct)
            c2fb_temp_56 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
            (*c2fb_temp_55) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 1ULL)))
            c2fb_temp_56 = Cast(UByte, (*c2fb_temp_55))
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local9.iEquiv) > Cast(SQLITE_C_INT, 1ULL))))) Then
            c2fb_temp_57 = @(local4->wsFlags)
            c2fb_temp_58 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_57)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00200000ULL)))))
            (*c2fb_temp_57) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_57)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00200000ULL))))))
            c2fb_temp_58 = Cast(SQLITE_C_UINT, (*c2fb_temp_57))
        End If
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

/' ------------------------------------------------------------------------- '/
/' Covering-index and partial-index planning helpers                        '/
/' ------------------------------------------------------------------------- '/

Private Const SQLITE_INDEX_COLUMN_EXPR As Short = -2

Private Type CoveringIndexCheck
    pIndex As SqliteIndex Ptr
    tableCursor As SQLITE_C_INT
    sawIndexedExpression As u8
    sawUnindexedColumn As u8
End Type

Private Function exprIsCoveredByIndex CDecl Alias "exprIsCoveredByIndex" ( _
    ByVal pExpression As Const SqliteExpr Ptr, _
    ByVal pIndex As Const SqliteIndex Ptr, _
    ByVal tableCursor As SQLITE_C_INT _
) As SQLITE_C_INT
    If pExpression = 0 OrElse pIndex = 0 OrElse _
       pIndex->aiColumn = 0 OrElse pIndex->aColExpr = 0 Then Return 0
    Dim pIndexExpressions As SqliteExprList Ptr = _
        CPtr(SqliteExprList Ptr, pIndex->aColExpr)
    For indexColumn As SQLITE_C_INT = 0 To pIndex->nColumn - 1
        If pIndex->aiColumn[indexColumn] = SQLITE_INDEX_COLUMN_EXPR AndAlso _
           indexColumn < pIndexExpressions->nExpr AndAlso _
           pIndexExpressions->a(indexColumn).pExpr <> 0 Then
            If sqlite3ExprCompare(0, pExpression, _
                pIndexExpressions->a(indexColumn).pExpr, tableCursor) = 0 Then
                Return 1
            End If
        End If
    Next
    Return 0
End Function

Private Function whereIsCoveringIndexWalkCallback CDecl Alias "whereIsCoveringIndexWalkCallback" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pExpression As SqliteExpr Ptr _
) As SQLITE_C_INT
    If pWalker = 0 OrElse pExpression = 0 Then Return WRC_CONTINUE
    Dim pCheck As CoveringIndexCheck Ptr = _
        CPtr(CoveringIndexCheck Ptr, pWalker->u.pCovIdxCk)
    If pCheck = 0 OrElse pCheck->pIndex = 0 Then Return WRC_ABORT

    Dim pIndex As SqliteIndex Ptr = pCheck->pIndex
    If pExpression->op = TK_COLUMN OrElse pExpression->op = TK_AGG_COLUMN Then
        If pExpression->iTable <> pCheck->tableCursor Then Return WRC_CONTINUE
        If pIndex->aiColumn = 0 Then
            pCheck->sawUnindexedColumn = 1
            Return WRC_ABORT
        End If
        For indexColumn As SQLITE_C_INT = 0 To pIndex->nColumn - 1
            If pIndex->aiColumn[indexColumn] = pExpression->iColumn Then _
                Return WRC_CONTINUE
        Next
        pCheck->sawUnindexedColumn = 1
        Return WRC_ABORT
    End If

    If (pIndex->flags And SQLITE_INDEX_HAS_EXPR) <> 0 AndAlso _
       exprIsCoveredByIndex(pExpression, pIndex, pCheck->tableCursor) <> 0 Then
        pCheck->sawIndexedExpression = 1
        Return WRC_PRUNE
    End If
    Return WRC_CONTINUE
End Function

Function whereIsCoveringIndex CDecl Alias "whereIsCoveringIndex" ( _
    ByVal pWhereInfo As SqliteWhereInfo Ptr, _
    ByVal pIndex As SqliteIndex Ptr, _
    ByVal tableCursor As SQLITE_C_INT _
) As u32
    If pWhereInfo = 0 OrElse pIndex = 0 OrElse pWhereInfo->pSelect = 0 Then Return 0
    If (pIndex->flags And SQLITE_INDEX_HAS_EXPR) = 0 Then
        If pIndex->aiColumn = 0 Then Return 0
        Dim indexColumn As SQLITE_C_INT = 0
        While indexColumn < pIndex->nColumn AndAlso _
              pIndex->aiColumn[indexColumn] < SQLITE_WHERE_BMS - 1
            indexColumn += 1
        Wend
        If indexColumn >= pIndex->nColumn Then Return 0
    End If

    Dim check As CoveringIndexCheck = Type<CoveringIndexCheck>(0)
    check.pIndex = pIndex
    check.tableCursor = tableCursor
    Dim walker As SqliteWalker = Type<SqliteWalker>(0)
    walker.xExprCallback = CPtr(SqliteWalkerExprCallback, _
        ProcPtr(whereIsCoveringIndexWalkCallback))
    walker.xSelectCallback = CPtr(SqliteWalkerSelectCallback, _
        ProcPtr(sqlite3SelectWalkNoop))
    walker.u.pCovIdxCk = @check
    sqlite3WalkSelect(@walker, pWhereInfo->pSelect)

    If check.sawUnindexedColumn <> 0 Then Return 0
    If check.sawIndexedExpression <> 0 Then Return WHERE_EXPRIDX
    Return WHERE_IDX_ONLY
End Function

Private Sub whereIndexedExprCleanup CDecl Alias "whereIndexedExprCleanup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pObject As Any Ptr _
)
    If db = 0 OrElse pObject = 0 Then Return
    Dim ppExpression As SqliteIndexedExpr Ptr Ptr = _
        CPtr(SqliteIndexedExpr Ptr Ptr, pObject)
    While ppExpression[0] <> 0
        Dim pEntry As SqliteIndexedExpr Ptr = ppExpression[0]
        ppExpression[0] = pEntry->pIENext
        If pEntry->pExpr <> 0 Then _
            sqlite3ExprDelete(db, CPtr(SqliteExpr Ptr, pEntry->pExpr))
        sqlite3DbFreeNN(db, pEntry)
    Wend
End Sub

Sub wherePartIdxExpr CDecl Alias "wherePartIdxExpr" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pIndex As SqliteIndex Ptr, _
    ByVal pPart As SqliteExpr Ptr, _
    ByVal pMask As sqlite3_uint64 Ptr, _
    ByVal indexCursor As SQLITE_C_INT, _
    ByVal pItem As SqliteSrcItem Ptr _
)
    If pParse = 0 OrElse pIndex = 0 OrElse pPart = 0 Then Return
    If ((pItem = 0) = (pMask = 0)) Then Return
    If pItem <> 0 AndAlso (pItem->fg.jointype And JT_RIGHT) <> 0 Then Return

    If pPart->op = TK_AND Then
        wherePartIdxExpr(pParse, pIndex, pPart->pRight, pMask, indexCursor, pItem)
        pPart = pPart->pLeft
    End If
    If pPart = 0 OrElse (pPart->op <> TK_EQ AndAlso pPart->op <> TK_IS) Then Return

    Dim pLeft As SqliteExpr Ptr = pPart->pLeft
    Dim pRight As SqliteExpr Ptr = pPart->pRight
    If pLeft = 0 OrElse pRight = 0 OrElse pLeft->op <> TK_COLUMN Then Return
    If sqlite3ExprIsConstant(0, pRight) = 0 Then Return
    If sqlite3IsBinary(sqlite3ExprCompareCollSeq(pParse, pPart)) = 0 Then Return
    If pLeft->iColumn < 0 Then Return
    If pIndex->pTable = 0 OrElse pLeft->iColumn >= pIndex->pTable->nCol Then Return
    Dim affinity As u8 = pIndex->pTable->aCol[pLeft->iColumn].affinity
    If affinity < SQLITE_AFF_TEXT Then Return

    If pItem <> 0 Then
        Dim db As sqlite3 Ptr = pParse->db
        If db = 0 Then Return
        Dim pEntry As SqliteIndexedExpr Ptr = CPtr(SqliteIndexedExpr Ptr, _
            sqlite3DbMallocRaw(db, SizeOf(SqliteIndexedExpr)))
        If pEntry = 0 Then Return
        pEntry->pExpr = sqlite3ExprDup(db, pRight, 0)
        pEntry->iDataCur = pItem->iCursor
        pEntry->iIdxCur = indexCursor
        pEntry->iIdxCol = pLeft->iColumn
        pEntry->bMaybeNullRow = CByte( _
            (pItem->fg.jointype And (JT_LEFT Or JT_LTORJ)) <> 0)
        pEntry->pIENext = pParse->pIdxPartExpr
        pEntry->aff = affinity
        pParse->pIdxPartExpr = pEntry
        If pEntry->pIENext = 0 Then
            sqlite3ParserAddCleanup(pParse, _
                CPtr(SqliteParserCleanupCallback, ProcPtr(whereIndexedExprCleanup)), _
                @pParse->pIdxPartExpr)
        End If
    ElseIf pLeft->iColumn < SQLITE_WHERE_BMS - 1 Then
        pMask[0] = pMask[0] And Not (CULngInt(1) Shl pLeft->iColumn)
    End If
End Sub

Sub whereOrMove CDecl Alias "whereOrMove" ( _
    ByVal pDestination As SqliteWhereOrSet Ptr, _
    ByVal pSource As Const SqliteWhereOrSet Ptr _
)
    If pDestination = 0 OrElse pSource = 0 Then Return
    If pSource->n < 0 OrElse pSource->n > 3 Then Return
    pDestination->n = pSource->n
    For itemIndex As SQLITE_C_INT = 0 To pSource->n - 1
        pDestination->a(itemIndex) = pSource->a(itemIndex)
    Next
End Sub

/' end of sqlite3_bulk_where_loop_candidates.bas '/
