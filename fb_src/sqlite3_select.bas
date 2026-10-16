/'
    Project: SQLite FreeBASIC port

    File: sqlite3_select.bas

    Purpose:

        Port tableless and basic table-backed SELECT code generation from select.c.

    Responsibilities:

        - Compile tableless expressions and WHERE-driven table source scans.
        - Prepare table-backed SELECTs through name resolution and WHERE planning.
        - Emit UNION ALL terms and multiple VALUES rows.
        - Dispatch compound SELECT statements to the translated multi-select path.
        - Apply simple LIMIT and OFFSET counters.
        - Emit result-column names and the OP_ResultRow instruction.
        - Use planner order or a temporary sorter for ORDER BY and DISTINCT.
        - Report unordered DISTINCT temporary tables in EXPLAIN QUERY PLAN.
        - Compile simple and grouped table-backed aggregate queries.
        - Compile grouped and ungrouped aggregates over the implicit row when
          FROM is absent.
        - Route row-value expressions through the shared expression bytecode
          emitter.
        - Store aggregate results in ephemeral-table destinations for CTEs.
        - Rewrite window SELECTs and connect frame-state VDBE generation.
        - Walk compound SELECT chains to find their leftmost and rightmost terms.
        - Create a VDBE on demand and track recursive-CTE anchor terms.
        - Request the SQLITE_SELECT authorization check before code generation.
        - Restore the active WITH context after a compound SELECT walk.
        - Run eligible FROM subqueries as co-routines and materialize other
          CTE, view, and derived-table terms.
        - Name compound operators for parser diagnostics.
        - Reject SELECT features whose code-generation paths are not yet integrated.
        - Expand NATURAL and USING joins into equality terms and mark ON terms.

    This file intentionally does NOT contain:

        - Recursive CTE bytecode generation or window-frame implementation details.
'/

#lang "fb"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_btree.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_numeric.bi"
#include once "sqlite3_util_numeric.bi"
#include once "sqlite3_fp.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_vdbe_record.bi"
#include once "sqlite3_walker.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_agginfo_types.bi"
#include once "sqlite3_resolve_types.bi"
#include once "sqlite3_walk_contexts.bi"
#include once "sqlite3_treeview_types.bi"
#include once "sqlite3_debug_assert.bi"

#ifndef SQLITE_NullUnusedCols
#define SQLITE_NullUnusedCols &H04000000
#endif

#ifndef SQLITE_PropagateConst
#define SQLITE_PropagateConst &H00008000
#endif

#ifndef SQLITE_SimplifyJoin
' Disable LEFT/RIGHT JOIN strength reduction when this bit is set in dbOptFlags.
#define SQLITE_SimplifyJoin &H00002000
#endif

Declare Sub sqlite3SelectPrep CDecl Alias "sqlite3SelectPrep" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pOuterContext As Any Ptr _
)
Declare Function sqlite3AuthCheck CDecl Alias "sqlite3AuthCheck" ( _
    ByVal pParse As Any Ptr, _
    ByVal action As SQLITE_C_INT, _
    ByVal zArg1 As Const ZString Ptr, _
    ByVal zArg2 As Const ZString Ptr, _
    ByVal zArg3 As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3SchemaToIndex CDecl Alias "sqlite3SchemaToIndex" ( _
    ByVal db As Any Ptr, _
    ByVal pSchema As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3ExprListDeleteGeneric CDecl Alias "sqlite3ExprListDeleteGeneric" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pExpressionList As Any Ptr _
)
Declare Function sqlite3ExprImpliesNonNullRow CDecl _
    Alias "sqlite3ExprImpliesNonNullRow" ( _
    ByVal pExpression As SqliteExpr Ptr, _
    ByVal cursorNumber As SQLITE_C_INT, _
    ByVal isRightJoin As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Sub sqlite3IdListDelete CDecl Alias "sqlite3IdListDelete" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pList As SqliteIdList Ptr _
)
Declare Sub sqlite3ExprToRegister CDecl Alias "sqlite3ExprToRegister" ( _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal registerIndex As SQLITE_C_INT _
)
Declare Sub sqlite3VdbeExplainPop CDecl Alias "sqlite3VdbeExplainPop" ( _
    ByVal pParse As SqliteParseContext Ptr _
)
Declare Function sqlite3_stricmp CDecl Alias "sqlite3_stricmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT
#ifndef SQLITE_OMIT_WINDOWFUNC
Declare Function sqlite3WindowRewrite CDecl Alias "sqlite3WindowRewrite" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3WindowCodeInit CDecl Alias "sqlite3WindowCodeInit" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
)
#endif
Declare Sub sqlite3GenerateColumnNames CDecl Alias "sqlite3GenerateColumnNames" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
)
Declare Sub sqlite3WhereMinMaxOptEarlyOut CDecl _
    Alias "sqlite3WhereMinMaxOptEarlyOut" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pWhereInfo As SqliteWhereInfo Ptr _
)
Declare Function sqlite3SelectTryFlatten CDecl Alias "sqlite3SelectTryFlatten" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal sourceIndex As SQLITE_C_INT, _
    ByVal isAggregate As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function disableUnusedSubqueryResultColumns CDecl Alias "disableUnusedSubqueryResultColumns" (ByVal pItem As SqliteSrcItem Ptr) As SQLITE_C_INT
Declare Sub recomputeColumnsUsed CDecl Alias "recomputeColumnsUsed" (ByVal pSelect As SqliteSelect Ptr, ByVal pSourceItem As SqliteSrcItem Ptr)
Declare Function propagateConstants CDecl Alias "propagateConstants" (ByVal pParse As SqliteParseContext Ptr, ByVal pSelect As SqliteSelect Ptr) As SQLITE_C_INT
Declare Sub sqlite3ExprCodeCopy CDecl Alias "sqlite3ExprCodeCopy" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpression As SqliteExpr Ptr, _
    ByVal targetRegister As SQLITE_C_INT _
)
Declare Function sqlite3WhereBegin CDecl Alias "sqlite3WhereBegin" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSourceList As SqliteSrcList Ptr, _
    ByVal pWhere As SqliteExpr Ptr, _
    ByVal pOrderBy As SqliteExprList Ptr, _
    ByVal pResultSet As SqliteExprList Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal controlFlags As UShort, _
    ByVal auxiliaryArgument As SQLITE_C_INT _
) As SqliteWhereInfo Ptr
Declare Function sqlite3WhereOutputRowCount CDecl Alias "sqlite3WhereOutputRowCount" ( _
    ByVal pWhereInfo As SqliteWhereInfo Ptr _
) As Short
Declare Sub sqlite3WhereEnd CDecl Alias "sqlite3WhereEnd" ( _
    ByVal pWhereInfo As SqliteWhereInfo Ptr _
)
Declare Function sqlite3WhereIsOrdered CDecl Alias "sqlite3WhereIsOrdered" ( _
    ByVal pWhereInfo As SqliteWhereInfo Ptr _
) As SQLITE_C_INT
Declare Function sqlite3WhereIsSorted CDecl Alias "sqlite3WhereIsSorted" ( _
    ByVal pWhereInfo As SqliteWhereInfo Ptr _
) As SQLITE_C_INT
Declare Function sqlite3WhereOrderByLimitOptLabel CDecl Alias "sqlite3WhereOrderByLimitOptLabel" ( _
    ByVal pWhereInfo As SqliteWhereInfo Ptr _
) As SQLITE_C_INT
Declare Function sqlite3WhereIsDistinct CDecl Alias "sqlite3WhereIsDistinct" ( _
    ByVal pWhereInfo As SqliteWhereInfo Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3SelectDestInit CDecl Alias "sqlite3SelectDestInit" ( _
    ByVal pDestination As SqliteSelectDest Ptr, _
    ByVal destinationType As SQLITE_C_INT, _
    ByVal destinationParameter As SQLITE_C_INT _
)
Declare Function fromClauseTermCanBeCoroutine CDecl Alias "fromClauseTermCanBeCoroutine" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSourceList As SqliteSrcList Ptr, _
    ByVal sourceIndex As SQLITE_C_INT, _
    ByVal selectFlags As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3KeyInfoFromExprList CDecl Alias "sqlite3KeyInfoFromExprList" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpressionList As SqliteExprList Ptr, _
    ByVal tableCursor As SQLITE_C_INT, _
    ByVal nDataColumn As SQLITE_C_INT _
) As sqlite3VdbeKeyInfoPrefix Ptr
Declare Function sqlite3SelectEmitOutputRow CDecl Alias "sqlite3SelectEmitOutputRow" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pSort As SqliteSortContext Ptr, _
    ByVal pDistinct As SqliteDistinctContext Ptr, _
    ByVal pDestination As SqliteSelectDest Ptr, _
    ByVal pWhereInfo As SqliteWhereInfo Ptr, _
    ByVal limitRegister As SQLITE_C_INT, _
    ByVal offsetRegister As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Sub sqlite3SelectGenerateSortTail CDecl Alias "sqlite3SelectGenerateSortTail" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pSort As SqliteSortContext Ptr, _
    ByVal nColumn As SQLITE_C_INT, _
    ByVal pDestination As SqliteSelectDest Ptr _
)
Declare Sub sqlite3SelectAggregateInnerLoop CDecl Alias "sqlite3SelectAggregateInnerLoop" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pSort As SqliteSortContext Ptr, _
    ByVal pDistinct As SqliteDistinctContext Ptr, _
    ByVal pDestination As SqliteSelectDest Ptr, _
    ByVal continueLabel As SQLITE_C_INT, _
    ByVal breakLabel As SQLITE_C_INT _
)
Declare Sub sqlite3ExprAnalyzeAggregates CDecl Alias "sqlite3ExprAnalyzeAggregates" ( _
    ByVal pNameContext As SqliteNameContext Ptr, _
    ByVal pExpression As SqliteExpr Ptr _
)
Declare Sub sqlite3ExprCode CDecl Alias "sqlite3ExprCode" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpression As SqliteExpr Ptr, _
    ByVal targetRegister As SQLITE_C_INT _
)
Declare Function sqlite3SelectAggregateInfoCreate CDecl Alias "sqlite3SelectAggregateInfoCreate" ( _
    ByVal pParse As SqliteParseContext Ptr _
) As SqliteAggInfo Ptr
Declare Sub sqlite3SelectAggregateAnalyzeFuncArgs CDecl Alias "sqlite3SelectAggregateAnalyzeFuncArgs" ( _
    ByVal pAggregateInfo As SqliteAggInfo Ptr, _
    ByVal pNameContext As SqliteNameContext Ptr _
)
Declare Sub sqlite3SelectAggregateAssignRegisters CDecl Alias "sqlite3SelectAggregateAssignRegisters" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pAggregateInfo As SqliteAggInfo Ptr _
)
Declare Sub sqlite3SelectAggregateReset CDecl Alias "sqlite3SelectAggregateReset" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pAggregateInfo As SqliteAggInfo Ptr _
)
Declare Sub sqlite3SelectAggregateUpdate CDecl Alias "sqlite3SelectAggregateUpdate" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal accumulatorFlagRegister As SQLITE_C_INT, _
    ByVal pAggregateInfo As SqliteAggInfo Ptr, _
    ByVal distinctType As SQLITE_C_INT _
)
Declare Sub sqlite3SelectAggregateFinalize CDecl Alias "sqlite3SelectAggregateFinalize" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pAggregateInfo As SqliteAggInfo Ptr _
)

Private Const SQLITE_SORTFLAG_USE_SORTER As u8 = &H01 ' The ephemeral index is a sorter.
' Match src/sqliteInt.h: omit ORDER BY clauses inside subqueries when safe.
Private Const SQLITE_OMIT_ORDER_BY_MASK As u32 = &H00040000

Private Function sqlite3SelectFixDistinctOpenEph( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal distinctType As SQLITE_C_INT, _
    ByVal firstPreviousValueRegister As SQLITE_C_INT, _
    ByVal openEphemeralAddress As SQLITE_C_INT _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->db = 0 OrElse pParse->pVdbe = 0 Then _
        Return SQLITE_MISUSE
    If distinctType <> WHERE_DISTINCT_UNIQUE AndAlso _
       distinctType <> WHERE_DISTINCT_ORDERED Then Return SQLITE_OK
    If pParse->nErr <> 0 Then Return SQLITE_ERROR

    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pParse->pVdbe)
    If openEphemeralAddress < 0 OrElse _
       openEphemeralAddress >= pVdbe->nOp Then Return SQLITE_CORRUPT
    If sqlite3VdbeChangeToNoop(pVdbe, openEphemeralAddress) = 0 Then
        If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_CORRUPT
    End If

    If openEphemeralAddress < pVdbe->nOp - 1 Then
        Dim pExplainOp As SqliteVdbeOp Ptr = _
            sqlite3VdbeGetOp(pVdbe, openEphemeralAddress + 1)
        If pExplainOp <> 0 AndAlso pExplainOp->opcode = OP_Explain Then _
            sqlite3VdbeChangeToNoop(pVdbe, openEphemeralAddress + 1)
    End If

    If distinctType = WHERE_DISTINCT_ORDERED Then
        Dim pOpenOp As SqliteVdbeOp Ptr = _
            sqlite3VdbeGetOp(pVdbe, openEphemeralAddress)
        If pOpenOp = 0 Then Return SQLITE_CORRUPT
        pOpenOp->opcode = OP_Null
        pOpenOp->p1 = 1
        pOpenOp->p2 = firstPreviousValueRegister
    End If

    If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    Return SQLITE_OK
End Function

Private Function sqlite3SelectCopySortOrder( _
    ByVal pTarget As SqliteExprList Ptr, _
    ByVal pSource As SqliteExprList Ptr _
) As SQLITE_C_INT
    If pTarget = 0 Then Return 0
    If pSource = 0 OrElse pTarget->nExpr <> pSource->nExpr Then Return 0
    If pTarget->nExpr < 0 OrElse _
       pTarget->nAlloc < pTarget->nExpr OrElse _
       pSource->nAlloc < pSource->nExpr Then Return 0

    For itemIndex As SQLITE_C_INT = 0 To pTarget->nExpr - 1
        pTarget->a(itemIndex).fg.sortFlags = _
            pSource->a(itemIndex).fg.sortFlags And KEYINFO_ORDER_DESC
    Next
    Return 1
End Function

#ifdef SQLITE_DEBUG
Declare Sub sqlite3DebugPrintf CDecl Alias "sqlite3DebugPrintf" (ByVal zFormat As Const ZString Ptr, ...)

Private Sub sqlite3SelectAssert( _
    ByVal condition As SQLITE_C_INT, _
    ByVal zExpression As Const ZString Ptr _
)
    If condition = 0 Then sqlite3DebugAssert(zExpression)
End Sub

Private Function sqlite3CursorBloomable CDecl Alias "sqlite3CursorBloomable" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal iCur As SQLITE_C_INT, _
    ByVal nCol As SQLITE_C_INT _
) As SQLITE_C_INT
    If pParse = 0 Then
        sqlite3SelectAssert(0, StrPtr("pParse is valid"))
        Return 0
    End If
    If pParse->nErr <> 0 Then Return 1

    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pParse->pVdbe)
    sqlite3SelectAssert(pVdbe <> 0, StrPtr("pParse->pVdbe is valid"))
    If pVdbe = 0 Then Return 0
    sqlite3SelectAssert(nCol >= 0, StrPtr("nCol is non-negative"))
    If nCol < 0 Then Return 0

    For opcodeIndex As SQLITE_C_INT = sqlite3VdbeCurrentAddr(pVdbe) - 1 To 1 Step -1
        Dim pOp As SqliteVdbeOp Ptr = sqlite3VdbeGetOp(pVdbe, opcodeIndex)
        sqlite3SelectAssert(pOp <> 0, StrPtr("VDBE opcode address is valid"))
        If pOp = 0 Then Return 0
        If pOp->p1 <> iCur Then Continue For
        If pOp->opcode <> OP_OpenRead AndAlso _
           pOp->opcode <> OP_OpenWrite AndAlso _
           pOp->opcode <> OP_OpenEphemeral Then Continue For

        sqlite3SelectAssert(pOp->p4type = P4_KEYINFO, _
            StrPtr("index cursor opcode carries P4_KEYINFO"))
        If pOp->p4type <> P4_KEYINFO Then Return 0
        Dim pKeyInfo As Const sqlite3VdbeKeyInfoPrefix Ptr = _
            CPtr(Const sqlite3VdbeKeyInfoPrefix Ptr, pOp->p4.pKeyInfo)
        sqlite3SelectAssert(pKeyInfo <> 0, StrPtr("P4_KEYINFO pointer is valid"))
        If pKeyInfo = 0 Then Return 0
        sqlite3SelectAssert(nCol <= pKeyInfo->nAllField, _
            StrPtr("nCol does not exceed KeyInfo field count"))
        If nCol > pKeyInfo->nAllField Then Return 0

        For columnIndex As SQLITE_C_INT = 0 To nCol - 1
            sqlite3SelectAssert( _
                sqlite3IsBinary(pKeyInfo->aColl(columnIndex)) <> 0, _
                StrPtr("cursor uses BINARY collation"))
        Next
        Return 1
    Next
    Return 0
End Function
#endif

#if defined(SQLITE_DEBUG) AndAlso (defined(SQLITE_TEST) OrElse defined(SQLITE_ENABLE_SELECTTRACE) OrElse defined(SQLITE_ENABLE_TREETRACE))
Declare Sub sqlite3TreeViewExpr CDecl Alias "sqlite3TreeViewExpr" ( _
    ByVal pView As SqliteTreeView Ptr, _
    ByVal pExpr As Const SqliteExpr Ptr, _
    ByVal moreToFollow As UByte _
)

Private Sub printAggInfo CDecl Alias "printAggInfo" ( _
    ByVal pAggInfo As SqliteAggInfo Ptr _
)
    If pAggInfo = 0 Then
        sqlite3DebugAssert(StrPtr("pAggInfo is valid"))
        Exit Sub
    End If
    If pAggInfo->nColumn < 0 OrElse pAggInfo->nFunc < 0 OrElse _
       (pAggInfo->nColumn > 0 AndAlso pAggInfo->aCol = 0) OrElse _
       (pAggInfo->nFunc > 0 AndAlso pAggInfo->aFunc = 0) Then
        sqlite3DebugAssert(StrPtr("AggInfo array counts and pointers are valid"))
        Exit Sub
    End If

    sqlite3DebugPrintf(StrPtr(!"AggInfo %d/%p:\n"), pAggInfo->selId, pAggInfo)
    For columnIndex As SQLITE_C_INT = 0 To pAggInfo->nColumn - 1
        Dim pColumn As SqliteAggInfoColumn Ptr = @pAggInfo->aCol[columnIndex]
        Dim zTableName As Const ZString Ptr = StrPtr("NULL")
        If pColumn->pTab <> 0 AndAlso pColumn->pTab->zName <> 0 Then
            zTableName = pColumn->pTab->zName
        End If
        Dim zAccumulator As Const ZString Ptr = StrPtr("")
        If columnIndex < pAggInfo->nAccumulator Then _
            zAccumulator = StrPtr(" Accumulator")
        sqlite3DebugPrintf( _
            StrPtr(!"agg-column[%d] pTab=%s iTable=%d iColumn=%d iMem=%d iSorterColumn=%d %s\n"), _
            columnIndex, zTableName, pColumn->iTable, pColumn->iColumn, _
            pAggInfo->iFirstReg + columnIndex, pColumn->iSorterColumn, zAccumulator)
        sqlite3TreeViewExpr(0, pColumn->pCExpr, 0)
    Next
    For functionIndex As SQLITE_C_INT = 0 To pAggInfo->nFunc - 1
        sqlite3DebugPrintf( _
            StrPtr(!"agg-func[%d]: iMem=%d\n"), functionIndex, _
            pAggInfo->iFirstReg + pAggInfo->nColumn + functionIndex)
        sqlite3TreeViewExpr(0, pAggInfo->aFunc[functionIndex].pFExpr, 0)
    Next
End Sub
#endif

Declare Function sqlite3StrIHash CDecl Alias "sqlite3StrIHash" ( _
    ByVal zText As Const ZString Ptr _
) As UByte
Declare Function sqlite3StrICmp CDecl Alias "sqlite3StrICmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3ColumnIndex CDecl Alias "sqlite3ColumnIndex" ( _
    ByVal pTable As SqliteTable Ptr, _
    ByVal zColumn As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3IdListAppend CDecl Alias "sqlite3IdListAppend" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pList As SqliteIdList Ptr, _
    ByVal pToken As sqlite3ParserToken Ptr _
) As SqliteIdList Ptr
Declare Function sqlite3IdListIndex CDecl Alias "sqlite3IdListIndex" ( _
    ByVal pList As SqliteIdList Ptr, _
    ByVal zName As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3CreateColumnExpr CDecl Alias "sqlite3CreateColumnExpr" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pSourceList As SqliteSrcList Ptr, _
    ByVal sourceIndex As SQLITE_C_INT, _
    ByVal columnIndex As SQLITE_C_INT _
) As SqliteExpr Ptr
Declare Sub sqlite3SrcItemColumnUsed CDecl Alias "sqlite3SrcItemColumnUsed" ( _
    ByVal pItem As SqliteSrcItem Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
)
Declare Function sqlite3ExprFunction CDecl Alias "sqlite3ExprFunction" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pArguments As SqliteExprList Ptr, _
    ByVal pToken As sqlite3ParserToken Ptr, _
    ByVal dequote As SQLITE_C_INT _
) As SqliteExpr Ptr
Declare Sub sqlite3SetJoinExpr CDecl Alias "sqlite3SetJoinExpr" ( _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal tableCursor As SQLITE_C_INT, _
    ByVal joinFlags As SQLITE_C_UINT _
)
Private Const SQLITE_COLUMN_HASH_SLOT_COUNT As SQLITE_C_INT = 16

Private Function sqlite3SelectNextRegister( _
    ByVal pParse As SqliteParseContext Ptr _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->db = 0 OrElse _
       pParse->nMem >= SQLITE_MAX_VDBE_OP - 1 Then Return 0
    pParse->nMem += 1
    Return pParse->nMem
End Function

Private Function findRightmost CDecl Alias "findRightmost" ( _
    ByVal pSelect As SqliteSelect Ptr _
) As SqliteSelect Ptr
    If pSelect = 0 Then Return 0
    While pSelect->pNext <> 0
        pSelect = CPtr(SqliteSelect Ptr, pSelect->pNext)
    Wend
    Return pSelect
End Function

Private Function findLeftmostExprlist CDecl Alias "findLeftmostExprlist" ( _
    ByVal pSelect As SqliteSelect Ptr _
) As SqliteExprList Ptr
    If pSelect = 0 Then Return 0
    While pSelect->pPrior <> 0
        pSelect = CPtr(SqliteSelect Ptr, pSelect->pPrior)
    Wend
    Return CPtr(SqliteExprList Ptr, pSelect->pEList)
End Function

Private Function sqlite3SelectTokenLength( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal zToken As Const UByte Ptr _
) As SQLITE_C_INT
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse zToken = 0 Then Return -1
    Dim length As SQLITE_C_INT = 0
    While length < pVdbe->db->lengthLimit AndAlso zToken[length] <> 0
        length += 1
    Wend
    If length >= pVdbe->db->lengthLimit Then Return -1
    Return length
End Function

Private Function sqlite3SelectFunctionNameEquals( _
    ByVal zFunction As Const UByte Ptr, _
    ByVal zExpected As Const ZString Ptr _
) As SQLITE_C_INT
    If zFunction = 0 OrElse zExpected = 0 Then Return 0
    Dim expectedBytes As Const UByte Ptr = _
        CPtr(Const UByte Ptr, zExpected)
    Dim index As Long = 0
    While expectedBytes[index] <> 0
        Dim valueByte As UByte = zFunction[index]
        If valueByte >= Asc("A") AndAlso valueByte <= Asc("Z") Then _
            valueByte = valueByte + Asc("a") - Asc("A")
        If valueByte <> expectedBytes[index] Then Return 0
        index += 1
    Wend
    Return CInt(zFunction[index] = 0)
End Function

Private Function sqlite3SelectMinMaxOrderFlag( _
    ByVal db As sqlite3 Ptr, _
    ByVal pFunctionExpr As SqliteExpr Ptr _
) As UShort
    If db = 0 OrElse pFunctionExpr = 0 OrElse _
       pFunctionExpr->op <> TK_AGG_FUNCTION OrElse _
       (db->dbOptFlags And SQLITE_MINMAXOPT) <> 0 Then Return 0

    Dim pArguments As SqliteExprList Ptr = _
        CPtr(SqliteExprList Ptr, pFunctionExpr->x.pList)
    If pArguments = 0 OrElse pArguments->nExpr <> 1 OrElse _
       pArguments->nAlloc < 1 OrElse pArguments->a(0).pExpr = 0 Then Return 0

    Dim zFunction As Const UByte Ptr = _
        CPtr(Const UByte Ptr, pFunctionExpr->u.zToken)
    If sqlite3SelectFunctionNameEquals(zFunction, StrPtr("min")) Then _
        Return WHERE_ORDERBY_MIN
    If sqlite3SelectFunctionNameEquals(zFunction, StrPtr("max")) Then _
        Return WHERE_ORDERBY_MAX
    Return 0
End Function

Private Function sqlite3SelectMinMaxOrderBy( _
    ByVal db As sqlite3 Ptr, _
    ByVal pFunctionExpr As SqliteExpr Ptr, _
    ByVal minMaxFlag As UShort _
) As SqliteExprList Ptr
    If db = 0 OrElse pFunctionExpr = 0 OrElse _
       (minMaxFlag <> WHERE_ORDERBY_MIN AndAlso _
        minMaxFlag <> WHERE_ORDERBY_MAX) Then Return 0

    Dim pArguments As SqliteExprList Ptr = _
        CPtr(SqliteExprList Ptr, pFunctionExpr->x.pList)
    If pArguments = 0 OrElse pArguments->nExpr <> 1 OrElse _
       pArguments->nAlloc < 1 OrElse pArguments->a(0).pExpr = 0 Then Return 0

    Dim pOrderBy As SqliteExprList Ptr = sqlite3ExprListDup( _
        db, CPtr(Const SqliteExprList Ptr, pArguments), 0)
    If pOrderBy = 0 Then Return 0
    If pOrderBy->nExpr <> 1 OrElse pOrderBy->nAlloc < 1 OrElse _
       pOrderBy->a(0).pExpr = 0 Then
        sqlite3ExprListDelete(db, pOrderBy)
        Return 0
    End If

    If minMaxFlag = WHERE_ORDERBY_MIN Then
        If sqlite3ExprCanBeNull( _
            CPtr(Const Any Ptr, pOrderBy->a(0).pExpr)) Then
            pOrderBy->a(0).fg.sortFlags = KEYINFO_ORDER_BIGNULL
        End If
    Else
        pOrderBy->a(0).fg.sortFlags = KEYINFO_ORDER_DESC
    End If
    Return pOrderBy
End Function

/' ------------------------------------------------------------------------- '/
/' Source column lookup and join-term construction                           '/
/' ------------------------------------------------------------------------- '/

Private Function tableAndColumnIndex( _
    ByVal pSourceList As SqliteSrcList Ptr, _
    ByVal firstSource As SQLITE_C_INT, _
    ByVal lastSource As SQLITE_C_INT, _
    ByVal zColumn As Const ZString Ptr, _
    ByVal pFoundSource As SQLITE_C_INT Ptr, _
    ByVal pFoundColumn As SQLITE_C_INT Ptr, _
    ByVal ignoreHidden As SQLITE_C_INT _
) As SQLITE_C_INT
    If pSourceList = 0 OrElse zColumn = 0 OrElse firstSource < 0 OrElse _
       lastSource >= pSourceList->nSrc OrElse firstSource > lastSource Then Return 0
    If (pFoundSource = 0) <> (pFoundColumn = 0) Then Return 0

    For sourceIndex As SQLITE_C_INT = firstSource To lastSource
        Dim pItem As SqliteSrcItem Ptr = @pSourceList->a(sourceIndex)
        Dim pTable As SqliteTable Ptr = pItem->pSTab
        If pTable = 0 Then Continue For
        Dim columnIndex As SQLITE_C_INT = sqlite3ColumnIndex(pTable, zColumn)
        If columnIndex < 0 Then Continue For
        If ignoreHidden <> 0 AndAlso _
           (pTable->aCol[columnIndex].colFlags And COLFLAG_HIDDEN) <> 0 Then Continue For
        If pFoundSource <> 0 Then
            sqlite3SrcItemColumnUsed(pItem, columnIndex)
            pFoundSource[0] = sourceIndex
            pFoundColumn[0] = columnIndex
        End If
        Return 1
    Next
    Return 0
End Function

Private Function sqlite3SelectCompareRegisters( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal expressionOpcode As SQLITE_C_INT, _
    ByVal leftRegister As SQLITE_C_INT, _
    ByVal rightRegister As SQLITE_C_INT, _
    ByVal outputRegister As SQLITE_C_INT, _
    ByVal pCollation As sqlite3CollSeq Ptr _
) As SQLITE_C_INT
    If pParse = 0 OrElse pVdbe = 0 OrElse leftRegister <= 0 OrElse _
       rightRegister <= 0 OrElse outputRegister <= 0 OrElse _
       leftRegister > pParse->nMem OrElse rightRegister > pParse->nMem OrElse _
       outputRegister > pParse->nMem Then Return SQLITE_CORRUPT

    Dim compareOpcode As SQLITE_C_INT
    Select Case expressionOpcode
    Case TK_EQ, TK_IS
        compareOpcode = OP_Eq
    Case TK_NE, TK_ISNOT
        compareOpcode = OP_Ne
    Case TK_LT
        compareOpcode = OP_Lt
    Case TK_LE
        compareOpcode = OP_Le
    Case TK_GT
        compareOpcode = OP_Gt
    Case TK_GE
        compareOpcode = OP_Ge
    Case Else
        Return SQLITE_MISUSE
    End Select

    Dim trueLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
    Dim doneLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
    If trueLabel = 0 OrElse doneLabel = 0 Then Return SQLITE_NOMEM
    sqlite3VdbeAddInt64(pVdbe, outputRegister, 0)

    If expressionOpcode = TK_IS OrElse expressionOpcode = TK_ISNOT Then
        sqlite3VdbeAddOp3(pVdbe, compareOpcode, rightRegister, trueLabel, leftRegister)
        If pCollation <> 0 Then _
            sqlite3VdbeAppendP4(pVdbe, pCollation, P4_COLLSEQ)
        sqlite3VdbeChangeP5(pVdbe, SQLITE_NULLEQ)
        sqlite3VdbeAddOp3(pVdbe, OP_Goto, 0, doneLabel, 0)
        sqlite3VdbeResolveLabel(pVdbe, trueLabel)
        sqlite3VdbeAddInt64(pVdbe, outputRegister, 1)
    Else
        Dim nullLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
        If nullLabel = 0 Then Return SQLITE_NOMEM
        sqlite3VdbeAddOp2(pVdbe, OP_IsNull, leftRegister, nullLabel)
        sqlite3VdbeAddOp2(pVdbe, OP_IsNull, rightRegister, nullLabel)
        sqlite3VdbeAddOp3(pVdbe, compareOpcode, rightRegister, trueLabel, leftRegister)
        If pCollation <> 0 Then _
            sqlite3VdbeAppendP4(pVdbe, pCollation, P4_COLLSEQ)
        sqlite3VdbeAddOp3(pVdbe, OP_Goto, 0, doneLabel, 0)
        sqlite3VdbeResolveLabel(pVdbe, trueLabel)
        sqlite3VdbeAddInt64(pVdbe, outputRegister, 1)
        sqlite3VdbeAddOp3(pVdbe, OP_Goto, 0, doneLabel, 0)
        sqlite3VdbeResolveLabel(pVdbe, nullLabel)
        sqlite3VdbeAddOp2(pVdbe, OP_Null, 0, outputRegister)
    End If

    sqlite3VdbeResolveLabel(pVdbe, doneLabel)
    If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    Return SQLITE_OK
End Function

Private Function sqlite3SelectCompileAggregate( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pFunction As SqliteFuncDef Ptr, _
    ByVal firstArgumentRegister As SQLITE_C_INT, _
    ByVal outputRegister As SQLITE_C_INT, _
    ByVal argumentCount As SQLITE_C_INT _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->db = 0 OrElse pParse->pVdbe = 0 OrElse _
       pFunction = 0 OrElse pFunction->xSFunc = 0 OrElse _
       pFunction->xFinalize = 0 OrElse argumentCount < 0 OrElse _
       argumentCount > pParse->db->aLimit(SQLITE_LIMIT_FUNCTION_ARG) OrElse _
       outputRegister <= 0 OrElse _
       outputRegister > pParse->nMem Then Return SQLITE_MISUSE
    If pFunction->nArg >= 0 AndAlso _
       pFunction->nArg <> argumentCount Then Return SQLITE_ERROR
    If (pFunction->nArg = -3 AndAlso argumentCount < 1) OrElse _
       (pFunction->nArg = -4 AndAlso argumentCount < 2) Then Return SQLITE_ERROR
    If argumentCount = 0 Then
        If firstArgumentRegister <> 0 Then Return SQLITE_MISUSE
    ElseIf firstArgumentRegister <= 0 OrElse _
           firstArgumentRegister > pParse->nMem - argumentCount + 1 Then
        Return SQLITE_MISUSE
    End If

    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pParse->pVdbe)
    Dim operationCountBefore As SQLITE_C_INT = pVdbe->nOp
    sqlite3VdbeAddOp2(pVdbe, OP_Null, 0, outputRegister)
    sqlite3VdbeAddOp4(pVdbe, OP_AggStep, 0, firstArgumentRegister, _
        outputRegister, CPtr(Const ZString Ptr, pFunction), P4_FUNCDEF)
    sqlite3VdbeChangeP5(pVdbe, CUShort(argumentCount))
    sqlite3VdbeAddOp4(pVdbe, OP_AggFinal, outputRegister, argumentCount, 0, _
        CPtr(Const ZString Ptr, pFunction), P4_FUNCDEF)
    If pVdbe->nOp < operationCountBefore + 3 OrElse _
       pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    Return SQLITE_OK
End Function

Private Function sqlite3SelectCompileExpr( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal outputRegister As SQLITE_C_INT, _
    ByVal depth As SQLITE_C_INT _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->db = 0 OrElse pExpr = 0 OrElse _
       outputRegister <= 0 Then Return SQLITE_ERROR
#if SQLITE_MAX_EXPR_DEPTH > 0
    If depth > pParse->db->aLimit(SQLITE_LIMIT_EXPR_DEPTH) Then Return SQLITE_ERROR
#endif
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pParse->pVdbe)
    If pVdbe = 0 Then Return SQLITE_MISUSE

    ' The shared expression compiler emits vector fields contiguously and
    ' preserves SQLite's row-comparison NULL behavior.
    If pExpr->op = TK_SELECT_COLUMN OrElse _
       sqlite3ExprIsVector(pExpr) <> 0 OrElse _
       (pExpr->pLeft <> 0 AndAlso _
        sqlite3ExprIsVector(CPtr(Const SqliteExpr Ptr, pExpr->pLeft)) <> 0) OrElse _
       (pExpr->pRight <> 0 AndAlso _
        sqlite3ExprIsVector(CPtr(Const SqliteExpr Ptr, pExpr->pRight)) <> 0) Then
        sqlite3ExprCode(pParse, pExpr, outputRegister)
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        If pParse->nErr <> 0 Then Return SQLITE_ERROR
        Return SQLITE_OK
    End If

    If (pExpr->flags And EP_IntValue) <> 0 Then
        sqlite3VdbeAddInt64(pVdbe, outputRegister, pExpr->u.iValue)
        If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_OK
    End If

    Select Case pExpr->op
    Case TK_INTEGER
        ' The shared codeInteger() path handles both decimal and hexadecimal
        ' literals, including values that do not fit in a signed 32-bit int.
        sqlite3ExprCode(pParse, pExpr, outputRegister)
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        If pParse->nErr <> 0 Then Return SQLITE_ERROR
        Return SQLITE_OK

    Case TK_FLOAT
        If pExpr->u.zToken = 0 Then Return SQLITE_CORRUPT
        Dim realValue As Double = 0.0
        If sqlite3AtoF(CPtr(Const ZString Ptr, pExpr->u.zToken), _
                       @realValue) < 0 Then Return SQLITE_ERROR
        sqlite3VdbeAddDouble(pVdbe, outputRegister, realValue)
        If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_OK

    Case TK_STRING
        If pExpr->u.zToken = 0 Then Return SQLITE_CORRUPT
        Dim transientDestructor As Any Ptr = CPtr(Any Ptr, -1)
        sqlite3VdbeAddOp4(pVdbe, OP_String8, 0, outputRegister, 0, _
            CPtr(Const ZString Ptr, pExpr->u.zToken), P4_TRANSIENT)
        If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_OK

    Case TK_BLOB
        If pExpr->u.zToken = 0 Then Return SQLITE_CORRUPT
        Dim tokenLength As SQLITE_C_INT = _
            sqlite3SelectTokenLength(pVdbe, pExpr->u.zToken)
        If tokenLength < 3 OrElse pExpr->u.zToken[0] <> Asc("x") AndAlso _
           pExpr->u.zToken[0] <> Asc("X") OrElse _
           pExpr->u.zToken[1] <> Asc("'") OrElse _
           pExpr->u.zToken[tokenLength - 1] <> Asc("'") Then Return SQLITE_CORRUPT
        Dim blobLength As SQLITE_C_INT = (tokenLength - 3) \ 2
        If ((tokenLength - 3) And 1) <> 0 Then Return SQLITE_CORRUPT
        Dim pBlob As Any Ptr = sqlite3HexToBlob( _
            pParse->db, CPtr(Const ZString Ptr, pExpr->u.zToken + 2), _
            tokenLength - 3)
        If pBlob = 0 Then
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            Return SQLITE_ERROR
        End If
        sqlite3VdbeAddOp4(pVdbe, OP_Blob, blobLength, outputRegister, 0, _
            CPtr(Const ZString Ptr, pBlob), P4_DYNAMIC)
        If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_OK

    Case TK_NULL
        sqlite3VdbeAddOp2(pVdbe, OP_Null, 0, outputRegister)
        If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_OK

    Case TK_TRUEFALSE
        sqlite3VdbeAddInt64( _
            pVdbe, outputRegister, sqlite3ExprTruthValue(pExpr))
        If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_OK

    Case TK_VARIABLE
        If pExpr->iColumn <= 0 OrElse _
           pExpr->iColumn > pParse->db->aLimit(SQLITE_LIMIT_VARIABLE_NUMBER) Then _
            Return SQLITE_CORRUPT
        sqlite3VdbeAddOp2(pVdbe, OP_Variable, pExpr->iColumn, outputRegister)
        If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_OK

    Case TK_COLLATE
        If pExpr->pLeft = 0 Then Return SQLITE_CORRUPT
        Return sqlite3SelectCompileExpr( _
            pParse, CPtr(SqliteExpr Ptr, pExpr->pLeft), outputRegister, depth + 1)

    Case TK_CAST
        If pExpr->pLeft = 0 OrElse pExpr->u.zToken = 0 Then Return SQLITE_CORRUPT
        Dim affinity As Byte = sqlite3AffinityType( _
            CPtr(Const ZString Ptr, pExpr->u.zToken), 0)
        If affinity < SQLITE_AFF_BLOB OrElse affinity > SQLITE_AFF_REAL Then _
            Return SQLITE_CORRUPT
        Dim rc As SQLITE_C_INT = sqlite3SelectCompileExpr( _
            pParse, CPtr(SqliteExpr Ptr, pExpr->pLeft), outputRegister, depth + 1)
        If rc <> SQLITE_OK Then Return rc
        sqlite3VdbeAddOp2(pVdbe, OP_Cast, outputRegister, affinity)
        If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_OK

    Case TK_FUNCTION
        If pExpr->u.zToken = 0 Then Return SQLITE_ERROR
        If pExpr->x.pList = 0 Then
            Dim pFunction As SqliteFuncDef Ptr = sqlite3FindFunction( _
                pParse->db, CPtr(Const ZString Ptr, pExpr->u.zToken), _
                0, pParse->db->enc, 0)
            If pFunction = 0 Then Return SQLITE_ERROR
            If pFunction->xFinalize <> 0 Then
                If pParse->allowAggregate = 0 OrElse depth <> 0 Then _
                    Return SQLITE_ERROR
                Return sqlite3SelectCompileAggregate( _
                    pParse, pFunction, 0, outputRegister, 0)
            End If
            Dim pVdbeBefore As SQLITE_C_INT = pVdbe->nOp
            sqlite3VdbeAddFunctionCall( _
                pParse, 0, 0, outputRegister, 0, pFunction, 0)
            If pVdbe->nOp = pVdbeBefore OrElse pVdbe->db->mallocFailed <> 0 Then _
                Return SQLITE_NOMEM
            Return SQLITE_OK
        End If
        Dim pArguments As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pExpr->x.pList)
        If pArguments->nExpr < 0 OrElse _
           pArguments->nExpr > pParse->db->aLimit(SQLITE_LIMIT_FUNCTION_ARG) OrElse _
           pArguments->nAlloc < pArguments->nExpr Then _
            Return SQLITE_CORRUPT
        If (pExpr->flags And EP_Unlikely) <> 0 Then
            If pArguments->nExpr <= 0 Then Return SQLITE_CORRUPT
            Dim pValueItem As SqliteExprListItem Ptr = _
                sqlite3ExprListItemAt(pArguments, 0)
            If pValueItem = 0 OrElse pValueItem->pExpr = 0 Then _
                Return SQLITE_CORRUPT
            ' The resolver has already validated the optional probability
            ' argument. These functions affect planner estimates only, so
            ' SELECT evaluates their value expression without a function call.
            Return sqlite3SelectCompileExpr( _
                pParse, CPtr(SqliteExpr Ptr, pValueItem->pExpr), _
                outputRegister, depth + 1)
        End If
        Dim isCoalesce As SQLITE_C_INT = _
            sqlite3SelectFunctionNameEquals(pExpr->u.zToken, StrPtr("coalesce"))
        Dim isIfNull As SQLITE_C_INT = _
            sqlite3SelectFunctionNameEquals(pExpr->u.zToken, StrPtr("ifnull"))
        Dim isNullIf As SQLITE_C_INT = _
            sqlite3SelectFunctionNameEquals(pExpr->u.zToken, StrPtr("nullif"))
        If isCoalesce <> 0 OrElse isIfNull <> 0 Then
            If isCoalesce <> 0 AndAlso pArguments->nExpr < 2 Then Return SQLITE_ERROR
            If isIfNull <> 0 AndAlso pArguments->nExpr <> 2 Then Return SQLITE_ERROR
            Dim endLabel As SQLITE_C_INT = 0
            If pArguments->nExpr > 1 Then
                endLabel = sqlite3VdbeMakeLabel(pParse)
                If endLabel = 0 Then Return SQLITE_NOMEM
            End If
            For iArgument As SQLITE_C_INT = 0 To pArguments->nExpr - 1
                Dim pItem As SqliteExprListItem Ptr = _
                    sqlite3ExprListItemAt(pArguments, iArgument)
                If pItem = 0 OrElse pItem->pExpr = 0 Then Return SQLITE_CORRUPT
                Dim rc As SQLITE_C_INT = sqlite3SelectCompileExpr( _
                    pParse, CPtr(SqliteExpr Ptr, pItem->pExpr), _
                    outputRegister, depth + 1)
                If rc <> SQLITE_OK Then Return rc
                If iArgument < pArguments->nExpr - 1 Then _
                    sqlite3VdbeAddOp2(pVdbe, OP_NotNull, outputRegister, endLabel)
            Next
            If endLabel <> 0 Then sqlite3VdbeResolveLabel(pVdbe, endLabel)
            If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            Return SQLITE_OK
        End If

        If isNullIf <> 0 Then
            If pArguments->nExpr <> 2 Then Return SQLITE_ERROR
            Dim pFirst As SqliteExprListItem Ptr = sqlite3ExprListItemAt(pArguments, 0)
            Dim pSecond As SqliteExprListItem Ptr = sqlite3ExprListItemAt(pArguments, 1)
            If pFirst = 0 OrElse pSecond = 0 OrElse _
               pFirst->pExpr = 0 OrElse pSecond->pExpr = 0 Then Return SQLITE_CORRUPT
            Dim rc As SQLITE_C_INT = sqlite3SelectCompileExpr( _
                pParse, CPtr(SqliteExpr Ptr, pFirst->pExpr), outputRegister, depth + 1)
            If rc <> SQLITE_OK Then Return rc
            Dim rightRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
            Dim compareRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
            If rightRegister = 0 OrElse compareRegister = 0 Then Return SQLITE_NOMEM
            rc = sqlite3SelectCompileExpr( _
                pParse, CPtr(SqliteExpr Ptr, pSecond->pExpr), rightRegister, depth + 1)
            If rc <> SQLITE_OK Then Return rc
            rc = sqlite3SelectCompareRegisters( _
                pParse, pVdbe, TK_EQ, outputRegister, rightRegister, compareRegister, _
                sqlite3BinaryCompareCollSeq(pParse, _
                    CPtr(Const SqliteExpr Ptr, pFirst->pExpr), _
                    CPtr(Const SqliteExpr Ptr, pSecond->pExpr)))
            If rc <> SQLITE_OK Then Return rc
            Dim nullLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
            Dim doneLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
            If nullLabel = 0 OrElse doneLabel = 0 Then Return SQLITE_NOMEM
            sqlite3VdbeAddOp3(pVdbe, OP_If, compareRegister, nullLabel, 0)
            sqlite3VdbeAddOp3(pVdbe, OP_Goto, 0, doneLabel, 0)
            sqlite3VdbeResolveLabel(pVdbe, nullLabel)
            sqlite3VdbeAddOp2(pVdbe, OP_Null, 0, outputRegister)
            sqlite3VdbeResolveLabel(pVdbe, doneLabel)
            If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            Return SQLITE_OK
        End If

        Dim pFunction As SqliteFuncDef Ptr = sqlite3FindFunction( _
            pParse->db, CPtr(Const ZString Ptr, pExpr->u.zToken), _
            pArguments->nExpr, pParse->db->enc, 0)
        If pFunction = 0 Then Return SQLITE_ERROR
        If (pFunction->funcFlags And _
            (SQLITE_FUNC_LENGTH Or SQLITE_FUNC_TYPEOF)) <> 0 Then
            If pArguments->nExpr <> 1 Then Return SQLITE_CORRUPT
            Dim pMetadataArgument As SqliteExprListItem Ptr = _
                sqlite3ExprListItemAt(pArguments, 0)
            If pMetadataArgument = 0 OrElse pMetadataArgument->pExpr = 0 Then _
                Return SQLITE_CORRUPT
            Dim pMetadataExpr As SqliteExpr Ptr = _
                CPtr(SqliteExpr Ptr, pMetadataArgument->pExpr)
            If pMetadataExpr->op = TK_COLUMN OrElse _
               pMetadataExpr->op = TK_AGG_COLUMN Then
                ' Mark direct column reads so OP_Column can inspect the record
                ' header without loading an unused overflow payload.
                pMetadataExpr->op2 = CByte( _
                    pFunction->funcFlags And SQLITE_FUNC_BYTELEN)
            End If
        End If
        Dim isAggregate As SQLITE_C_INT = CInt(pFunction->xFinalize <> 0)
        If isAggregate <> 0 AndAlso _
           (pParse->allowAggregate = 0 OrElse depth <> 0) Then Return SQLITE_ERROR
        If pParse->nMem < 0 OrElse pParse->nMem > SQLITE_MAX_VDBE_OP OrElse _
           pArguments->nExpr > SQLITE_MAX_VDBE_OP - pParse->nMem Then _
            Return SQLITE_TOOBIG
        Dim firstArgumentRegister As SQLITE_C_INT = pParse->nMem + 1
        If pArguments->nExpr = 0 Then firstArgumentRegister = 0
        pParse->nMem += pArguments->nExpr
        For iArgument As SQLITE_C_INT = 0 To pArguments->nExpr - 1
            Dim pArgument As SqliteExprListItem Ptr = _
                sqlite3ExprListItemAt(pArguments, iArgument)
            If pArgument = 0 OrElse pArgument->pExpr = 0 Then Return SQLITE_CORRUPT
            Dim rc As SQLITE_C_INT = sqlite3SelectCompileExpr( _
                pParse, CPtr(SqliteExpr Ptr, pArgument->pExpr), _
                firstArgumentRegister + iArgument, depth + 1)
            If rc <> SQLITE_OK Then Return rc
        Next
        If isAggregate <> 0 Then
            Return sqlite3SelectCompileAggregate( _
                pParse, pFunction, firstArgumentRegister, _
                outputRegister, pArguments->nExpr)
        End If
        If (pFunction->funcFlags And SQLITE_FUNC_NEEDCOLL) <> 0 Then
            Dim pCollation As sqlite3CollSeq Ptr = 0
            For iArgument As SQLITE_C_INT = 0 To pArguments->nExpr - 1
                Dim pItem As SqliteExprListItem Ptr = _
                    sqlite3ExprListItemAt(pArguments, iArgument)
                If pItem = 0 OrElse pItem->pExpr = 0 Then Return SQLITE_CORRUPT
                pCollation = sqlite3ExprCollSeq( _
                    pParse, CPtr(Const SqliteExpr Ptr, pItem->pExpr))
                If pCollation <> 0 Then Exit For
            Next
            If pCollation = 0 Then pCollation = pParse->db->pDfltColl
            If pCollation <> 0 Then
                Dim opCountBeforeCollSeq As SQLITE_C_INT = pVdbe->nOp
                sqlite3VdbeAddOp4( _
                    pVdbe, OP_CollSeq, 0, 0, 0, _
                    CPtr(Const ZString Ptr, pCollation), P4_COLLSEQ)
                If pVdbe->db->mallocFailed <> 0 OrElse _
                   pVdbe->nOp <> opCountBeforeCollSeq + 1 Then Return SQLITE_NOMEM
            End If
        End If
        Dim pVdbeBefore As SQLITE_C_INT = pVdbe->nOp
        sqlite3VdbeAddFunctionCall( _
            pParse, 0, firstArgumentRegister, outputRegister, _
            pArguments->nExpr, pFunction, 0)
        If pVdbe->nOp = pVdbeBefore OrElse pVdbe->db->mallocFailed <> 0 Then _
            Return SQLITE_NOMEM
        Return SQLITE_OK

    Case TK_CASE
        If pExpr->x.pList = 0 Then Return SQLITE_CORRUPT
        Dim pCaseList As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pExpr->x.pList)
        If pCaseList->nExpr < 2 OrElse pCaseList->nAlloc < pCaseList->nExpr Then _
            Return SQLITE_CORRUPT
        Dim endLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
        If endLabel = 0 Then Return SQLITE_NOMEM

        Dim baseRegister As SQLITE_C_INT = 0
        If pExpr->pLeft <> 0 Then
            baseRegister = sqlite3SelectNextRegister(pParse)
            If baseRegister = 0 Then Return SQLITE_NOMEM
            Dim rc As SQLITE_C_INT = sqlite3SelectCompileExpr( _
                pParse, CPtr(SqliteExpr Ptr, pExpr->pLeft), baseRegister, depth + 1)
            If rc <> SQLITE_OK Then Return rc
        End If
        Dim branchTempStart As SQLITE_C_INT = pParse->nMem
        Dim maximumRegisterCount As SQLITE_C_INT = pParse->nMem
        Dim nPair As SQLITE_C_INT = pCaseList->nExpr \ 2

        For iPair As SQLITE_C_INT = 0 To nPair - 1
            Dim pWhen As SqliteExprListItem Ptr = _
                sqlite3ExprListItemAt(pCaseList, iPair * 2)
            Dim pThen As SqliteExprListItem Ptr = _
                sqlite3ExprListItemAt(pCaseList, iPair * 2 + 1)
            If pWhen = 0 OrElse pThen = 0 OrElse _
               pWhen->pExpr = 0 OrElse pThen->pExpr = 0 Then Return SQLITE_CORRUPT

            pParse->nMem = branchTempStart
            Dim nextLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
            If nextLabel = 0 Then Return SQLITE_NOMEM
            If baseRegister = 0 Then
                Dim whenRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
                If whenRegister = 0 Then Return SQLITE_NOMEM
                Dim rc As SQLITE_C_INT = sqlite3SelectCompileExpr( _
                    pParse, CPtr(SqliteExpr Ptr, pWhen->pExpr), _
                    whenRegister, depth + 1)
                If rc <> SQLITE_OK Then Return rc
                sqlite3VdbeAddOp3(pVdbe, OP_IfNot, whenRegister, nextLabel, 1)
            Else
                Dim whenRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
                Dim compareRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
                If whenRegister = 0 OrElse compareRegister = 0 Then Return SQLITE_NOMEM
                Dim rc As SQLITE_C_INT = sqlite3SelectCompileExpr( _
                    pParse, CPtr(SqliteExpr Ptr, pWhen->pExpr), _
                    whenRegister, depth + 1)
                If rc <> SQLITE_OK Then Return rc
                rc = sqlite3SelectCompareRegisters( _
                    pParse, pVdbe, TK_EQ, baseRegister, whenRegister, compareRegister, _
                    sqlite3BinaryCompareCollSeq(pParse, _
                        CPtr(Const SqliteExpr Ptr, pExpr->pLeft), _
                        CPtr(Const SqliteExpr Ptr, pWhen->pExpr)))
                If rc <> SQLITE_OK Then Return rc
                sqlite3VdbeAddOp3(pVdbe, OP_IfNot, compareRegister, nextLabel, 1)
            End If
            If pParse->nMem > maximumRegisterCount Then _
                maximumRegisterCount = pParse->nMem

            Dim rcThen As SQLITE_C_INT = sqlite3SelectCompileExpr( _
                pParse, CPtr(SqliteExpr Ptr, pThen->pExpr), outputRegister, depth + 1)
            If rcThen <> SQLITE_OK Then Return rcThen
            If pParse->nMem > maximumRegisterCount Then _
                maximumRegisterCount = pParse->nMem
            sqlite3VdbeAddOp3(pVdbe, OP_Goto, 0, endLabel, 0)
            sqlite3VdbeResolveLabel(pVdbe, nextLabel)
        Next

        pParse->nMem = branchTempStart
        If (pCaseList->nExpr And 1) <> 0 Then
            Dim pElse As SqliteExprListItem Ptr = _
                sqlite3ExprListItemAt(pCaseList, pCaseList->nExpr - 1)
            If pElse = 0 OrElse pElse->pExpr = 0 Then Return SQLITE_CORRUPT
            Dim rcElse As SQLITE_C_INT = sqlite3SelectCompileExpr( _
                pParse, CPtr(SqliteExpr Ptr, pElse->pExpr), outputRegister, depth + 1)
            If rcElse <> SQLITE_OK Then Return rcElse
            If pParse->nMem > maximumRegisterCount Then _
                maximumRegisterCount = pParse->nMem
        Else
            sqlite3VdbeAddOp2(pVdbe, OP_Null, 0, outputRegister)
        End If
        sqlite3VdbeResolveLabel(pVdbe, endLabel)
        pParse->nMem = maximumRegisterCount
        If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_OK

    Case TK_IN
        If pExpr->pLeft = 0 Then Return SQLITE_ERROR
        If (pExpr->flags And EP_xIsSelect) <> 0 Then
            ' Subquery membership is handled by expr.c's IN implementation.
            sqlite3ExprCode(pParse, pExpr, outputRegister)
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            If pParse->nErr <> 0 Then Return SQLITE_ERROR
            Return SQLITE_OK
        End If
        Dim pList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pExpr->x.pList)
        If pList = 0 OrElse pList->nExpr = 0 Then
            sqlite3VdbeAddInt64(pVdbe, outputRegister, 0)
            If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            Return SQLITE_OK
        End If
        If pList->nExpr < 0 OrElse pList->nExpr > 32767 OrElse _
           pList->nAlloc < pList->nExpr Then Return SQLITE_CORRUPT

        Dim valueRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
        Dim sawNullRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
        Dim itemRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
        Dim compareRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
        If valueRegister = 0 OrElse sawNullRegister = 0 OrElse _
           itemRegister = 0 OrElse compareRegister = 0 Then Return SQLITE_NOMEM
        Dim rc As SQLITE_C_INT = sqlite3SelectCompileExpr( _
            pParse, CPtr(SqliteExpr Ptr, pExpr->pLeft), valueRegister, depth + 1)
        If rc <> SQLITE_OK Then Return rc
        Dim temporaryRegisterStart As SQLITE_C_INT = pParse->nMem
        Dim maximumRegisterCount As SQLITE_C_INT = pParse->nMem
        Dim foundLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
        Dim nullLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
        Dim doneLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
        If foundLabel = 0 OrElse nullLabel = 0 OrElse doneLabel = 0 Then _
            Return SQLITE_NOMEM
        ' Register Mem cells are allocated later by sqlite3VdbeMakeReady.
        ' Store this initial value as an instruction for VDBE execution.
        sqlite3VdbeAddInt64(pVdbe, sawNullRegister, 0)
        sqlite3VdbeAddInt64(pVdbe, outputRegister, 0)

        For iValue As SQLITE_C_INT = 0 To pList->nExpr - 1
            Dim pItem As SqliteExprListItem Ptr = sqlite3ExprListItemAt(pList, iValue)
            If pItem = 0 OrElse pItem->pExpr = 0 Then Return SQLITE_CORRUPT
            pParse->nMem = temporaryRegisterStart
            rc = sqlite3SelectCompileExpr( _
                pParse, CPtr(SqliteExpr Ptr, pItem->pExpr), itemRegister, depth + 1)
            If rc <> SQLITE_OK Then Return rc
            rc = sqlite3SelectCompareRegisters( _
                pParse, pVdbe, TK_EQ, valueRegister, itemRegister, compareRegister, _
                sqlite3ExprCollSeq(pParse, _
                    CPtr(Const SqliteExpr Ptr, pExpr->pLeft)))
            If rc <> SQLITE_OK Then Return rc
            If pParse->nMem > maximumRegisterCount Then _
                maximumRegisterCount = pParse->nMem

            Dim nextItemLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
            If nextItemLabel = 0 Then Return SQLITE_NOMEM
            sqlite3VdbeAddOp3(pVdbe, OP_If, compareRegister, foundLabel, 0)
            sqlite3VdbeAddOp2(pVdbe, OP_NotNull, compareRegister, nextItemLabel)
            sqlite3VdbeAddInt64(pVdbe, sawNullRegister, 1)
            sqlite3VdbeResolveLabel(pVdbe, nextItemLabel)
        Next

        sqlite3VdbeAddOp3(pVdbe, OP_If, sawNullRegister, nullLabel, 0)
        sqlite3VdbeAddOp3(pVdbe, OP_Goto, 0, doneLabel, 0)
        sqlite3VdbeResolveLabel(pVdbe, foundLabel)
        sqlite3VdbeAddInt64(pVdbe, outputRegister, 1)
        sqlite3VdbeAddOp3(pVdbe, OP_Goto, 0, doneLabel, 0)
        sqlite3VdbeResolveLabel(pVdbe, nullLabel)
        sqlite3VdbeAddOp2(pVdbe, OP_Null, 0, outputRegister)
        sqlite3VdbeResolveLabel(pVdbe, doneLabel)
        pParse->nMem = maximumRegisterCount
        If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_OK

    Case TK_UPLUS, TK_UMINUS, TK_NOT, TK_BITNOT
        If pExpr->pLeft = 0 Then Return SQLITE_ERROR
        If pExpr->op = TK_UMINUS Then
            Dim pIntegerOperand As SqliteExpr Ptr = _
                CPtr(SqliteExpr Ptr, pExpr->pLeft)
            If pIntegerOperand->op = TK_INTEGER AndAlso _
               (pIntegerOperand->flags And EP_IntValue) = 0 AndAlso _
               pIntegerOperand->u.zToken <> 0 Then
                Dim integerValue As sqlite3_int64 = 0
                Dim integerStatus As SQLITE_C_INT = sqlite3DecOrHexToI64( _
                    CPtr(Const ZString Ptr, pIntegerOperand->u.zToken), _
                    @integerValue)
                If integerStatus = 3 Then
                    ' Unary minus makes the otherwise out-of-range 2^63 literal valid.
                    Dim smallestInteger As sqlite3_int64 = _
                        -9223372036854775807LL - 1LL
                    sqlite3VdbeAddInt64(pVdbe, outputRegister, smallestInteger)
                    If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
                    Return SQLITE_OK
                End If
            End If
        End If
        Dim inputRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
        If inputRegister = 0 Then Return SQLITE_NOMEM
        Dim rc As SQLITE_C_INT = sqlite3SelectCompileExpr( _
            pParse, CPtr(SqliteExpr Ptr, pExpr->pLeft), inputRegister, depth + 1)
        If rc <> SQLITE_OK Then Return rc
        Select Case pExpr->op
        Case TK_UPLUS
            sqlite3VdbeAddOp3(pVdbe, OP_Copy, inputRegister, outputRegister, 0)
        Case TK_UMINUS
            sqlite3VdbeAddInt64(pVdbe, outputRegister, 0)
            sqlite3VdbeAddOp3(pVdbe, OP_Subtract, inputRegister, _
                outputRegister, outputRegister)
        Case TK_NOT
            sqlite3VdbeAddOp2(pVdbe, OP_Not, inputRegister, outputRegister)
        Case TK_BITNOT
            sqlite3VdbeAddOp2(pVdbe, OP_BitNot, inputRegister, outputRegister)
        End Select
        If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_OK

    Case TK_ISNULL, TK_NOTNULL
        If pExpr->pLeft = 0 Then Return SQLITE_ERROR
        Dim inputRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
        Dim doneLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
        If inputRegister = 0 OrElse doneLabel = 0 Then Return SQLITE_NOMEM
        Dim rc As SQLITE_C_INT = sqlite3SelectCompileExpr( _
            pParse, CPtr(SqliteExpr Ptr, pExpr->pLeft), inputRegister, depth + 1)
        If rc <> SQLITE_OK Then Return rc
        sqlite3VdbeAddInt64(pVdbe, outputRegister, 1)
        Dim opcode As SQLITE_C_INT = IIf(pExpr->op = TK_ISNULL, OP_IsNull, OP_NotNull)
        sqlite3VdbeAddOp2(pVdbe, opcode, inputRegister, doneLabel)
        sqlite3VdbeAddInt64(pVdbe, outputRegister, 0)
        sqlite3VdbeResolveLabel(pVdbe, doneLabel)
        If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_OK

    Case TK_BETWEEN
        If pExpr->pLeft = 0 OrElse pExpr->x.pList = 0 Then Return SQLITE_ERROR
        Dim pBounds As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pExpr->x.pList)
        If pBounds->nExpr <> 2 OrElse pBounds->nAlloc < 2 Then Return SQLITE_CORRUPT
        Dim pLower As SqliteExprListItem Ptr = sqlite3ExprListItemAt(pBounds, 0)
        Dim pUpper As SqliteExprListItem Ptr = sqlite3ExprListItemAt(pBounds, 1)
        If pLower = 0 OrElse pUpper = 0 OrElse _
           pLower->pExpr = 0 OrElse pUpper->pExpr = 0 Then Return SQLITE_CORRUPT

        Dim valueRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
        Dim lowerRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
        Dim upperRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
        Dim lowerTestRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
        Dim upperTestRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
        If valueRegister = 0 OrElse lowerRegister = 0 OrElse _
           upperRegister = 0 OrElse lowerTestRegister = 0 OrElse _
           upperTestRegister = 0 Then Return SQLITE_NOMEM

        Dim rc As SQLITE_C_INT = sqlite3SelectCompileExpr( _
            pParse, CPtr(SqliteExpr Ptr, pExpr->pLeft), valueRegister, depth + 1)
        If rc <> SQLITE_OK Then Return rc
        rc = sqlite3SelectCompileExpr( _
            pParse, CPtr(SqliteExpr Ptr, pLower->pExpr), lowerRegister, depth + 1)
        If rc <> SQLITE_OK Then Return rc
        rc = sqlite3SelectCompileExpr( _
            pParse, CPtr(SqliteExpr Ptr, pUpper->pExpr), upperRegister, depth + 1)
        If rc <> SQLITE_OK Then Return rc

        rc = sqlite3SelectCompareRegisters( _
            pParse, pVdbe, TK_GE, valueRegister, lowerRegister, lowerTestRegister, _
            sqlite3BinaryCompareCollSeq(pParse, _
                CPtr(Const SqliteExpr Ptr, pExpr->pLeft), _
                CPtr(Const SqliteExpr Ptr, pLower->pExpr)))
        If rc <> SQLITE_OK Then Return rc
        rc = sqlite3SelectCompareRegisters( _
            pParse, pVdbe, TK_LE, valueRegister, upperRegister, upperTestRegister, _
            sqlite3BinaryCompareCollSeq(pParse, _
                CPtr(Const SqliteExpr Ptr, pExpr->pLeft), _
                CPtr(Const SqliteExpr Ptr, pUpper->pExpr)))
        If rc <> SQLITE_OK Then Return rc
        sqlite3VdbeAddOp3( _
            pVdbe, OP_And, lowerTestRegister, upperTestRegister, outputRegister)
        If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_OK

    Case TK_EQ, TK_NE, TK_LT, TK_LE, TK_GT, TK_GE, TK_IS, TK_ISNOT
        If pExpr->pLeft = 0 OrElse pExpr->pRight = 0 Then Return SQLITE_ERROR
        Dim leftRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
        Dim rightRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
        If leftRegister = 0 OrElse rightRegister = 0 Then Return SQLITE_NOMEM
        Dim rc As SQLITE_C_INT = sqlite3SelectCompileExpr( _
            pParse, CPtr(SqliteExpr Ptr, pExpr->pLeft), leftRegister, depth + 1)
        If rc <> SQLITE_OK Then Return rc
        rc = sqlite3SelectCompileExpr( _
            pParse, CPtr(SqliteExpr Ptr, pExpr->pRight), rightRegister, depth + 1)
        If rc <> SQLITE_OK Then Return rc

        Return sqlite3SelectCompareRegisters( _
            pParse, pVdbe, pExpr->op, leftRegister, rightRegister, outputRegister, _
            sqlite3BinaryCompareCollSeq(pParse, _
                CPtr(Const SqliteExpr Ptr, pExpr->pLeft), _
                CPtr(Const SqliteExpr Ptr, pExpr->pRight)))

    Case TK_PLUS, TK_MINUS, TK_STAR, TK_SLASH, TK_REM, TK_CONCAT, _
         TK_BITAND, TK_BITOR, TK_LSHIFT, TK_RSHIFT, TK_AND, TK_OR
        If pExpr->pLeft = 0 OrElse pExpr->pRight = 0 Then Return SQLITE_ERROR
        Dim leftRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
        Dim rightRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
        If leftRegister = 0 OrElse rightRegister = 0 Then Return SQLITE_NOMEM
        Dim rc As SQLITE_C_INT = sqlite3SelectCompileExpr( _
            pParse, CPtr(SqliteExpr Ptr, pExpr->pLeft), leftRegister, depth + 1)
        If rc <> SQLITE_OK Then Return rc
        rc = sqlite3SelectCompileExpr( _
            pParse, CPtr(SqliteExpr Ptr, pExpr->pRight), rightRegister, depth + 1)
        If rc <> SQLITE_OK Then Return rc

        Dim opcode As SQLITE_C_INT
        Select Case pExpr->op
        Case TK_PLUS
            opcode = OP_Add
        Case TK_MINUS
            opcode = OP_Subtract
        Case TK_STAR
            opcode = OP_Multiply
        Case TK_SLASH
            opcode = OP_Divide
        Case TK_REM
            opcode = OP_Remainder
        Case TK_CONCAT
            opcode = OP_Concat
        Case TK_BITAND
            opcode = OP_BitAnd
        Case TK_BITOR
            opcode = OP_BitOr
        Case TK_LSHIFT
            opcode = OP_ShiftLeft
        Case TK_RSHIFT
            opcode = OP_ShiftRight
        Case TK_AND
            opcode = OP_And
        Case TK_OR
            opcode = OP_Or
        End Select
        If pExpr->op = TK_AND OrElse pExpr->op = TK_OR Then
            sqlite3VdbeAddOp3(pVdbe, opcode, leftRegister, rightRegister, outputRegister)
        Else
            sqlite3VdbeAddOp3(pVdbe, opcode, rightRegister, leftRegister, outputRegister)
        End If
        If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_OK
    End Select

    ' Reuse expr.c's broader emitter for operators not lowered by this
    ' tableless SELECT path.
    sqlite3ExprCode(pParse, pExpr, outputRegister)
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR
    Return SQLITE_OK
End Function

Private Function sqlite3SelectStoreResultRow( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pDestination As SqliteSelectDest Ptr, _
    ByVal firstRegister As SQLITE_C_INT, _
    ByVal nColumn As SQLITE_C_INT _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->db = 0 OrElse pParse->pVdbe = 0 OrElse _
       pDestination = 0 OrElse firstRegister <= 0 OrElse nColumn <= 0 Then _
        Return SQLITE_MISUSE

    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pParse->pVdbe)
    Select Case pDestination->eDest
    Case SRT_Output
        sqlite3VdbeAddOp2(pVdbe, OP_ResultRow, firstRegister, nColumn)
    Case SRT_EphemTab, SRT_Table
        ' Temporary integer-key tables store an encoded row under a new key.
        If pDestination->iSDParm < 0 Then Return SQLITE_CORRUPT
        Dim recordRegister As SQLITE_C_INT = sqlite3GetTempReg(pParse)
        Dim rowidRegister As SQLITE_C_INT = sqlite3GetTempReg(pParse)
        If recordRegister = 0 OrElse rowidRegister = 0 Then
            sqlite3ReleaseTempReg(pParse, rowidRegister)
            sqlite3ReleaseTempReg(pParse, recordRegister)
            Return SQLITE_NOMEM
        End If
        Dim makeRecordAddress As SQLITE_C_INT = sqlite3VdbeAddOp3( _
            pVdbe, OP_MakeRecord, firstRegister, nColumn, recordRegister)
        Dim newRowidAddress As SQLITE_C_INT = sqlite3VdbeAddOp2( _
            pVdbe, OP_NewRowid, pDestination->iSDParm, rowidRegister)
        Dim insertAddress As SQLITE_C_INT = sqlite3VdbeAddOp3( _
            pVdbe, OP_Insert, pDestination->iSDParm, _
            recordRegister, rowidRegister)
        If makeRecordAddress < 0 OrElse newRowidAddress < 0 OrElse _
           insertAddress < 0 Then
            sqlite3ReleaseTempReg(pParse, rowidRegister)
            sqlite3ReleaseTempReg(pParse, recordRegister)
            Return SQLITE_NOMEM
        End If
        sqlite3VdbeChangeP5(pVdbe, OPFLAG_APPEND)
        sqlite3ReleaseTempReg(pParse, rowidRegister)
        sqlite3ReleaseTempReg(pParse, recordRegister)
    Case SRT_Mem
        If pDestination->iSDParm <= 0 OrElse _
           pDestination->nSdst <> nColumn Then Return SQLITE_CORRUPT
        If firstRegister <> pDestination->iSDParm Then
            sqlite3VdbeAddOp3( _
                pVdbe, OP_Copy, firstRegister, _
                pDestination->iSDParm, nColumn - 1)
        End If
    Case SRT_Coroutine
        If pDestination->iSDParm <= 0 Then Return SQLITE_CORRUPT
        If pDestination->iSdst = 0 Then
            pDestination->iSdst = sqlite3GetTempRange(pParse, nColumn)
            If pDestination->iSdst = 0 Then Return SQLITE_NOMEM
            pDestination->nSdst = nColumn
        ElseIf pDestination->nSdst <> nColumn OrElse _
               pDestination->iSdst > pParse->nMem - nColumn + 1 Then
            Return SQLITE_CORRUPT
        End If

        ' The parent SELECT reads these registers after this coroutine yields.
        If firstRegister <> pDestination->iSdst Then
            sqlite3VdbeAddOp3( _
                pVdbe, OP_Copy, firstRegister, pDestination->iSdst, nColumn - 1)
        End If
        Dim yieldAddress As SQLITE_C_INT = _
            sqlite3VdbeAddOp1(pVdbe, OP_Yield, pDestination->iSDParm)
        If yieldAddress < 0 Then Return SQLITE_NOMEM
    Case SRT_Exists
        If pDestination->iSDParm <= 0 Then Return SQLITE_CORRUPT
        sqlite3VdbeAddOp2(pVdbe, OP_Integer, 1, pDestination->iSDParm)
    Case SRT_Set
        If pDestination->iSDParm < 0 OrElse _
           pDestination->zAffSdst = 0 Then Return SQLITE_CORRUPT
        Dim recordRegister As SQLITE_C_INT = sqlite3GetTempReg(pParse)
        If recordRegister = 0 Then Return SQLITE_NOMEM
        Dim makeRecordAddress As SQLITE_C_INT = sqlite3VdbeAddOp4( _
            pVdbe, OP_MakeRecord, firstRegister, nColumn, recordRegister, _
            CPtr(Const ZString Ptr, pDestination->zAffSdst), nColumn)
        Dim insertAddress As SQLITE_C_INT = sqlite3VdbeAddOp4Int( _
            pVdbe, OP_IdxInsert, pDestination->iSDParm, _
            recordRegister, firstRegister, nColumn)
        If makeRecordAddress < 0 OrElse insertAddress < 0 Then
            sqlite3ReleaseTempReg(pParse, recordRegister)
            Return SQLITE_NOMEM
        End If
        If pDestination->iSDParm2 > 0 Then
            sqlite3VdbeAddOp4Int( _
                pVdbe, OP_FilterAdd, pDestination->iSDParm2, 0, _
                firstRegister, nColumn)
        End If
        sqlite3ReleaseTempReg(pParse, recordRegister)
    Case SRT_Discard
        ' Trigger-only SELECTs evaluate their expressions and discard rows.
    Case Else
        Return SQLITE_MISUSE
    End Select

    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    Return SQLITE_OK
End Function

Private Function sqlite3SelectCompileRow( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pList As SqliteExprList Ptr, _
    ByVal pDestination As SqliteSelectDest Ptr, _
    ByVal firstRegister As SQLITE_C_INT, _
    ByVal nColumn As SQLITE_C_INT, _
    ByVal tempRegisterStart As SQLITE_C_INT, _
    ByVal includeColumnNames As SQLITE_C_INT, _
    ByVal useValuesColumnNames As SQLITE_C_INT, _
    ByVal allowAggregate As SQLITE_C_INT, _
    ByVal offsetRegister As SQLITE_C_INT, _
    ByVal limitRegister As SQLITE_C_INT, _
    ByVal breakLabel As SQLITE_C_INT _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->db = 0 OrElse pParse->pVdbe = 0 OrElse _
       pSelect = 0 OrElse pList = 0 OrElse pDestination = 0 OrElse _
       nColumn <= 0 OrElse _
       (pDestination->eDest <> SRT_Output AndAlso _
        pDestination->eDest <> SRT_EphemTab AndAlso _
        pDestination->eDest <> SRT_Table AndAlso _
        pDestination->eDest <> SRT_Fifo AndAlso _
        pDestination->eDest <> SRT_DistFifo AndAlso _
        pDestination->eDest <> SRT_Queue AndAlso _
        pDestination->eDest <> SRT_DistQueue AndAlso _
        pDestination->eDest <> SRT_Coroutine AndAlso _
        pDestination->eDest <> SRT_Mem AndAlso _
        pDestination->eDest <> SRT_Exists AndAlso _
        pDestination->eDest <> SRT_Set AndAlso _
        pDestination->eDest <> SRT_Discard AndAlso _
        pDestination->eDest <> SRT_Upfrom) OrElse _
       pList->nExpr <> nColumn OrElse _
       pList->nExpr <= 0 OrElse pList->nAlloc < pList->nExpr Then _
        Return SQLITE_ERROR

    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pParse->pVdbe)
    pParse->nMem = tempRegisterStart

    Select Case pDestination->eDest
    Case SRT_Fifo, SRT_DistFifo, SRT_Queue, SRT_DistQueue, SRT_Coroutine, _
         SRT_Mem, SRT_Exists, SRT_Set, SRT_Discard, SRT_Upfrom
        ' The shared inner loop owns queue ordering, duplicate checks, and yields.
        Dim continueLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
        If continueLabel = 0 Then Return SQLITE_NOMEM
        Dim savedLimit As SQLITE_C_INT = pSelect->iLimit
        Dim savedOffset As SQLITE_C_INT = pSelect->iOffset
        pSelect->iLimit = limitRegister
        pSelect->iOffset = offsetRegister
        Dim resultCode As SQLITE_C_INT = sqlite3SelectEmitInternalRow( _
            pParse, pSelect, pDestination, continueLabel, breakLabel)
        pSelect->iLimit = savedLimit
        pSelect->iOffset = savedOffset
        Return resultCode
    End Select

    For iColumn As SQLITE_C_INT = 0 To nColumn - 1
        Dim pItem As SqliteExprListItem Ptr = sqlite3ExprListItemAt(pList, iColumn)
        If pItem = 0 OrElse pItem->pExpr = 0 Then Return SQLITE_CORRUPT
        pParse->allowAggregate = CByte(allowAggregate <> 0)
        Dim rc As SQLITE_C_INT = sqlite3SelectCompileExpr( _
            pParse, CPtr(SqliteExpr Ptr, pItem->pExpr), _
            firstRegister + iColumn, 0)
        pParse->allowAggregate = 0
        If rc <> SQLITE_OK Then Return rc
        If includeColumnNames <> 0 AndAlso pItem->zEName <> 0 Then
            rc = sqlite3VdbeSetColName(pVdbe, iColumn, COLNAME_NAME, _
                CPtr(Const ZString Ptr, pItem->zEName), CPtr(Any Ptr, -1))
            If rc <> SQLITE_OK Then Return rc
        ElseIf includeColumnNames <> 0 AndAlso useValuesColumnNames <> 0 Then
            Dim zColumnName As String = "column" & LTrim(Str(iColumn + 1))
            rc = sqlite3VdbeSetColName(pVdbe, iColumn, COLNAME_NAME, _
                StrPtr(zColumnName), CPtr(Any Ptr, -1))
            If rc <> SQLITE_OK Then Return rc
        End If
    Next
    Dim skipLabel As SQLITE_C_INT = 0
    If offsetRegister <> 0 Then
        skipLabel = sqlite3VdbeMakeLabel(pParse)
        If skipLabel = 0 Then Return SQLITE_NOMEM
        sqlite3VdbeAddOp3(pVdbe, OP_IfPos, offsetRegister, skipLabel, 1)
    End If
    Dim storeResult As SQLITE_C_INT = sqlite3SelectStoreResultRow( _
        pParse, pDestination, firstRegister, nColumn)
    If storeResult <> SQLITE_OK Then Return storeResult
    If limitRegister <> 0 Then _
        sqlite3VdbeAddOp2(pVdbe, OP_DecrJumpZero, limitRegister, breakLabel)
    If skipLabel <> 0 Then sqlite3VdbeResolveLabel(pVdbe, skipLabel)
    If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    Return SQLITE_OK
End Function

Private Function sqlite3SelectFindPriorSelfJoinView( _
    ByVal pSourceList As SqliteSrcList Ptr, _
    ByVal pCurrentItem As SqliteSrcItem Ptr, _
    ByVal firstSource As SQLITE_C_INT, _
    ByVal pastLastSource As SQLITE_C_INT _
) As SqliteSrcItem Ptr
    If pSourceList = 0 OrElse pCurrentItem = 0 OrElse _
       pCurrentItem->pSTab = 0 OrElse pCurrentItem->zName = 0 OrElse _
       pSourceList->nSrc < 0 OrElse pSourceList->nAlloc < pSourceList->nSrc OrElse _
       firstSource < 0 OrElse pastLastSource < firstSource OrElse _
       pastLastSource > pSourceList->nSrc Then Return 0

    If (pCurrentItem->fg.flags And SRCITEM_IS_SUBQUERY) = 0 Then Return 0
    Dim pCurrentSubquery As SqliteSubquery Ptr = _
        CPtr(SqliteSubquery Ptr, pCurrentItem->u4.pSubq)
    If pCurrentSubquery = 0 OrElse pCurrentSubquery->pSelect = 0 Then Return 0
    Dim pCurrentSelect As SqliteSelect Ptr = pCurrentSubquery->pSelect
    If (pCurrentSelect->selFlags And SF_PushDown) <> 0 Then Return 0

    For sourceIndex As SQLITE_C_INT = firstSource To pastLastSource - 1
        Dim pCandidate As SqliteSrcItem Ptr = @pSourceList->a(sourceIndex)
        If (pCandidate->fg.flags And SRCITEM_IS_SUBQUERY) = 0 Then Continue For
        If (pCandidate->fg.flags And SRCITEM_VIA_COROUTINE) <> 0 Then Continue For
        If pCandidate->zName = 0 OrElse pCandidate->pSTab = 0 Then Continue For
        If pCandidate->u4.pSubq = 0 Then Continue For
        If pCandidate->pSTab->pSchema <> pCurrentItem->pSTab->pSchema Then Continue For
        If sqlite3_stricmp( _
            CPtr(Const ZString Ptr, pCandidate->zName), _
            CPtr(Const ZString Ptr, pCurrentItem->zName)) <> 0 Then Continue For

        Dim pCandidateSubquery As SqliteSubquery Ptr = _
            CPtr(SqliteSubquery Ptr, pCandidate->u4.pSubq)
        Dim pCandidateSelect As SqliteSelect Ptr = pCandidateSubquery->pSelect
        If pCandidateSelect = 0 Then Continue For

        ' Two CTEs can retain the same display name after flattening. Their
        ' SELECT ids distinguish separate definitions in the temporary schema.
        If pCandidate->pSTab->pSchema = 0 AndAlso _
           pCurrentSelect->selId <> pCandidateSelect->selId Then Continue For
        If (pCandidateSelect->selFlags And SF_PushDown) <> 0 Then Continue For
        Return pCandidate
    Next
    Return 0
End Function

Private Function sqlite3SelectMaterializeFromSubqueries( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSourceList As SqliteSrcList Ptr, _
    ByVal selectFlags As SQLITE_C_INT _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->db = 0 OrElse pSourceList = 0 OrElse _
       pSourceList->nSrc < 0 OrElse pSourceList->nAlloc < pSourceList->nSrc Then _
        Return SQLITE_MISUSE

    Dim pVdbe As SqliteVdbe Ptr = sqlite3GetVdbe(pParse)
    If pVdbe = 0 Then Return SQLITE_NOMEM

    ' Eligible FROM terms use the single-row SRT_Coroutine interface. The
    ' remaining terms use an ephemeral table, with CteUse sharing a fill
    ' subroutine among references to the same materialized CTE.
    For sourceIndex As SQLITE_C_INT = 0 To pSourceList->nSrc - 1
        Dim pItem As SqliteSrcItem Ptr = @pSourceList->a(sourceIndex)
        Dim sourceFlags As SQLITE_C_UINT = pItem->fg.flags
        If (sourceFlags And SRCITEM_IS_SUBQUERY) = 0 Then Continue For
        If (sourceFlags And SRCITEM_IS_RECURSIVE) <> 0 OrElse _
           (sourceFlags And SRCITEM_IS_MATERIALIZED) <> 0 Then _
            Return SQLITE_ERROR

        Dim isCte As SQLITE_C_INT = _
            CInt((sourceFlags And SRCITEM_IS_CTE) <> 0)
        Dim pSubquery As SqliteSubquery Ptr = pItem->u4.pSubq
        Dim pCteUse As SqliteCteUse Ptr = 0
        If isCte <> 0 Then pCteUse = pItem->u2.pCteUse
        If pSubquery = 0 OrElse pItem->iCursor < 0 OrElse _
           pItem->iCursor >= pParse->nTab Then Return SQLITE_CORRUPT
        If isCte <> 0 AndAlso _
           (pCteUse = 0 OrElse pCteUse->nUse <= 0 OrElse _
            pCteUse->eM10d > M10D_NO) Then Return SQLITE_CORRUPT

        Dim pCteSelect As SqliteSelect Ptr = pSubquery->pSelect
        If pCteSelect = 0 OrElse pCteSelect->pEList = 0 OrElse _
           pCteSelect->pEList->nExpr <= 0 OrElse _
           pCteSelect->pEList->nAlloc < pCteSelect->pEList->nExpr Then _
            Return SQLITE_ERROR
        If pItem->pSTab = 0 OrElse _
           ((pItem->pSTab->tabFlags And TF_Ephemeral) = 0 AndAlso _
            pItem->pSTab->eTabType <> TABTYP_VIEW) OrElse _
           pItem->pSTab->nCol <> pCteSelect->pEList->nExpr Then _
            Return SQLITE_CORRUPT

        If (sourceFlags And SRCITEM_VIA_COROUTINE) <> 0 Then
            ' Multi-row VALUES builds its coroutine while parsing. Reuse that
            ' code instead of trying to allocate a second coroutine here.
            If pSubquery->addrFillSub <= 0 OrElse _
               pSubquery->regReturn <= 0 OrElse pSubquery->regResult <= 0 Then _
                Return SQLITE_CORRUPT
            Continue For
        End If

        Dim isCorrelated As SQLITE_C_INT = _
            CInt((sourceFlags And SRCITEM_IS_CORRELATED) <> 0)
        If fromClauseTermCanBeCoroutine( _
            pParse, pSourceList, sourceIndex, selectFlags) <> 0 Then
            If pSubquery->addrFillSub <> 0 OrElse pSubquery->regReturn <> 0 Then _
                Return SQLITE_CORRUPT
            If pParse->nMem < 0 OrElse _
               pParse->nMem >= SQLITE_MAX_VDBE_OP Then Return SQLITE_TOOBIG

            pParse->nMem += 1
            pSubquery->regReturn = pParse->nMem
            Dim coroutineStart As SQLITE_C_INT = _
                sqlite3VdbeCurrentAddr(pVdbe) + 1
            ' P3 starts at the first instruction after OP_InitCoroutine.
            Dim coroutineInit As SQLITE_C_INT = sqlite3VdbeAddOp3( _
                pVdbe, OP_InitCoroutine, pSubquery->regReturn, 0, coroutineStart)
            If coroutineInit < 0 Then Return SQLITE_NOMEM
            pSubquery->addrFillSub = coroutineStart

            Dim coroutineDestination As SqliteSelectDest = _
                Type<SqliteSelectDest>(0)
            sqlite3SelectDestInit( _
                @coroutineDestination, SRT_Coroutine, pSubquery->regReturn)
            ' Keep the subquery's scan and window-plan rows beneath its
            ' co-routine node in EXPLAIN QUERY PLAN output. The internal %!S
            ' formatter also gives unnamed subqueries their stable display name.
            sqlite3VdbeExplainString( _
                pParse, 1, StrPtr(!"CO-ROUTINE %!S"), _
                CPtr(Const ZString Ptr, pItem))
            Dim coroutineResult As SQLITE_C_INT = _
                sqlite3Select(pParse, pCteSelect, @coroutineDestination)
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            If pParse->nErr <> 0 Then Return SQLITE_ERROR
            If coroutineResult <> SQLITE_OK Then Return coroutineResult

            pItem->pSTab->nRowLogEst = pCteSelect->nSelectRow
            pItem->fg.flags Or= SRCITEM_VIA_COROUTINE
            pSubquery->regResult = coroutineDestination.iSdst
            sqlite3VdbeEndCoroutine(pVdbe, pSubquery->regReturn)
            sqlite3VdbeJumpHere(pVdbe, coroutineStart - 1)
            sqlite3ClearTempRegCache(pParse)
            Continue For
        End If

        If isCte <> 0 AndAlso isCorrelated = 0 AndAlso _
           pCteUse->addrM9e > 0 Then
            If pCteUse->regRtn <= 0 OrElse _
               pCteUse->regRtn > pParse->nMem OrElse _
               pCteUse->iCur < 0 OrElse pCteUse->iCur >= pParse->nTab OrElse _
               pSubquery->addrFillSub <> 0 Then Return SQLITE_CORRUPT
            sqlite3VdbeAddOp2( _
                pVdbe, OP_Gosub, pCteUse->regRtn, pCteUse->addrM9e)
            If pItem->iCursor <> pCteUse->iCur Then
                sqlite3VdbeAddOp2( _
                    pVdbe, OP_OpenDup, pItem->iCursor, pCteUse->iCur)
            End If
            pSubquery->addrFillSub = pCteUse->addrM9e
            pSubquery->regReturn = pCteUse->regRtn
            pCteSelect->nSelectRow = pCteUse->nRowEst
            pItem->pSTab->nRowLogEst = pCteUse->nRowEst
            pItem->fg.flags Or= SRCITEM_IS_MATERIALIZED
            Continue For
        End If

        ' Reuse a materialized view or derived table when another FROM term
        ' names the same unmodified subquery. Each alias still receives its
        ' own cursor, but OP_OpenDup points those cursors at one ephemeral
        ' table, matching SQLite's self-join view optimization.
        Dim pPriorView As SqliteSrcItem Ptr = _
            sqlite3SelectFindPriorSelfJoinView( _
                pSourceList, pItem, 0, sourceIndex)
        If pPriorView <> 0 Then
            If pPriorView->iCursor < 0 OrElse _
               pPriorView->iCursor >= pParse->nTab OrElse _
               pPriorView->u4.pSubq = 0 Then Return SQLITE_CORRUPT
            Dim pPriorSubquery As SqliteSubquery Ptr = _
                CPtr(SqliteSubquery Ptr, pPriorView->u4.pSubq)
            If pPriorSubquery->pSelect = 0 Then Return SQLITE_CORRUPT
            If pPriorSubquery->addrFillSub <> 0 Then
                sqlite3VdbeAddOp2( _
                    pVdbe, OP_Gosub, pPriorSubquery->regReturn, _
                    pPriorSubquery->addrFillSub)
            End If
            sqlite3VdbeAddOp2( _
                pVdbe, OP_OpenDup, pItem->iCursor, pPriorView->iCursor)
            pCteSelect->nSelectRow = pPriorSubquery->pSelect->nSelectRow
            pItem->pSTab->nRowLogEst = pCteSelect->nSelectRow
            Continue For
        End If

        If pSubquery->addrFillSub <> 0 OrElse pSubquery->regReturn <> 0 Then _
            Return SQLITE_CORRUPT

        If pParse->nMem < 0 OrElse pParse->nMem >= SQLITE_MAX_VDBE_OP Then _
            Return SQLITE_TOOBIG
        pParse->nMem += 1
        pSubquery->regReturn = pParse->nMem
        Dim jumpOverAddress As SQLITE_C_INT = sqlite3VdbeAddOp0( _
            pVdbe, OP_Goto)
        If jumpOverAddress < 0 Then Return SQLITE_NOMEM
        pSubquery->addrFillSub = jumpOverAddress + 1
        pItem->fg.flags Or= SRCITEM_IS_MATERIALIZED

        Dim onceAddress As SQLITE_C_INT = 0
        If isCorrelated = 0 Then
            onceAddress = sqlite3VdbeAddOp0(pVdbe, OP_Once)
            If onceAddress < 0 Then Return SQLITE_NOMEM
        End If
        Dim cteDestination As SqliteSelectDest = Type<SqliteSelectDest>(0)
        cteDestination.eDest = SRT_EphemTab
        cteDestination.iSDParm = pItem->iCursor
        Dim savedAuthContext As ZString Ptr = _
            CPtr(ZString Ptr, pParse->zAuthContext)
        pParse->zAuthContext = pItem->zName
        sqlite3VdbeExplainString( _
            pParse, 1, StrPtr(!"MATERIALIZE %!S"), _
            CPtr(Const ZString Ptr, pItem))
        Dim compileResult As SQLITE_C_INT = _
            sqlite3Select(pParse, pCteSelect, @cteDestination)
        pParse->zAuthContext = savedAuthContext
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        If pParse->nErr <> 0 Then Return SQLITE_ERROR
        If compileResult <> SQLITE_OK Then Return compileResult

        If onceAddress <> 0 Then sqlite3VdbeJumpHere(pVdbe, onceAddress)
        sqlite3VdbeAddOp2( _
            pVdbe, OP_Return, pSubquery->regReturn, pSubquery->addrFillSub)
        sqlite3VdbeJumpHere(pVdbe, jumpOverAddress)

        If isCte <> 0 AndAlso isCorrelated = 0 Then
            pCteUse->addrM9e = pSubquery->addrFillSub
            pCteUse->regRtn = pSubquery->regReturn
            pCteUse->iCur = pItem->iCursor
            pCteUse->nRowEst = pCteSelect->nSelectRow
        End If
        pItem->pSTab->nRowLogEst = pCteSelect->nSelectRow
    Next

    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR
    Return SQLITE_OK
End Function

Function sqlite3ProcessJoin CDecl Alias "sqlite3ProcessJoin" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) As SQLITE_C_INT Export
    If pParse = 0 OrElse pParse->db = 0 OrElse pSelect = 0 Then Return 1
    Dim db As sqlite3 Ptr = pParse->db
    Dim pSourceList As SqliteSrcList Ptr = _
        CPtr(SqliteSrcList Ptr, pSelect->pSrc)
    If pSourceList = 0 OrElse pSourceList->nSrc < 2 Then Return 0

    Dim haveTableFunctionToLeft As SQLITE_C_INT = 0
    For rightIndex As SQLITE_C_INT = 1 To pSourceList->nSrc - 1
        Dim pLeft As SqliteSrcItem Ptr = @pSourceList->a(rightIndex - 1)
        Dim pRight As SqliteSrcItem Ptr = @pSourceList->a(rightIndex)
        Dim pRightTable As SqliteTable Ptr = pRight->pSTab
        If pLeft->pSTab = 0 OrElse pRightTable = 0 Then Continue For

        Dim joinFlags As SQLITE_C_UINT = EP_InnerON
        If (pRight->fg.jointype And JT_OUTER) <> 0 Then joinFlags = EP_OuterON

        If (pRight->fg.jointype And JT_NATURAL) <> 0 Then
            If (pRight->fg.flags And SRCITEM_IS_USING) <> 0 OrElse _
               pRight->u3.pOn <> 0 Then
                sqlite3ErrorMsg(pParse, StrPtr(!"a NATURAL join may not have an ON or USING clause"))
                Return 1
            End If

            Dim pUsing As SqliteIdList Ptr = 0
            For rightColumn As SQLITE_C_INT = 0 To pRightTable->nCol - 1
                Dim pColumn As SqliteColumn Ptr = @pRightTable->aCol[rightColumn]
                If (pColumn->colFlags And COLFLAG_HIDDEN) <> 0 Then Continue For
                If tableAndColumnIndex(pSourceList, 0, rightIndex - 1, _
                    pColumn->zCnName, 0, 0, 1) <> 0 Then
                    pUsing = sqlite3IdListAppend(pParse, pUsing, 0)
                    If pUsing = 0 Then Return 1
                    Dim newItemIndex As SQLITE_C_INT = pUsing->nId - 1
                    If newItemIndex < 0 OrElse pColumn->zCnName = 0 Then
                        sqlite3IdListDelete(db, pUsing)
                        Return 1
                    End If
                    pUsing->a(newItemIndex).zName = sqlite3DbStrDup(db, pColumn->zCnName)
                    If pUsing->a(newItemIndex).zName = 0 Then
                        ' The local IdList is not attached to pRight yet.
                        ' Release its earlier names when this copy fails.
                        sqlite3IdListDelete(db, pUsing)
                        Return 1
                    End If
                End If
            Next
            If pUsing <> 0 Then
                pRight->fg.flags Or= SRCITEM_IS_USING Or SRCITEM_IS_SYNTH_USING
                pRight->u3.pUsing = pUsing
            End If
            If pParse->nErr <> 0 OrElse db->mallocFailed <> 0 Then Return 1
        End If

        If (pRight->fg.flags And SRCITEM_IS_USING) <> 0 Then
            Dim pUsing As SqliteIdList Ptr = pRight->u3.pUsing
            If pUsing = 0 Then Return 1
            For usingIndex As SQLITE_C_INT = 0 To pUsing->nId - 1
                Dim zName As ZString Ptr = pUsing->a(usingIndex).zName
                Dim leftSourceIndex As SQLITE_C_INT = 0
                Dim leftColumnIndex As SQLITE_C_INT = 0
                Dim rightColumnIndex As SQLITE_C_INT = -1
                If zName <> 0 Then rightColumnIndex = sqlite3ColumnIndex(pRightTable, zName)
                If rightColumnIndex < 0 OrElse _
                   tableAndColumnIndex(pSourceList, 0, rightIndex - 1, zName, _
                       @leftSourceIndex, @leftColumnIndex, _
                       CInt((pRight->fg.flags And SRCITEM_IS_SYNTH_USING) <> 0)) = 0 Then
                    sqlite3ErrorMsg(pParse, _
                        StrPtr(!"cannot join using column %s - column not present in both tables"), zName)
                    Return 1
                End If

                Dim pLeftExpr As SqliteExpr Ptr = sqlite3CreateColumnExpr( _
                    db, pSourceList, leftSourceIndex, leftColumnIndex)
                If pLeftExpr = 0 Then Return 1
                sqlite3SrcItemColumnUsed(@pSourceList->a(leftSourceIndex), leftColumnIndex)

                If (pSourceList->a(0).fg.jointype And JT_LTORJ) <> 0 AndAlso _
                   pParse->nErr = 0 Then
                    Dim pFunctionArguments As SqliteExprList Ptr = 0
                    pLeftExpr->flags Or= EP_CanBeNull
                    While tableAndColumnIndex(pSourceList, leftSourceIndex + 1, _
                        rightIndex - 1, zName, @leftSourceIndex, @leftColumnIndex, _
                        CInt((pRight->fg.flags And SRCITEM_IS_SYNTH_USING) <> 0)) <> 0
                        Dim pEarlierItem As SqliteSrcItem Ptr = _
                            @pSourceList->a(leftSourceIndex)
                        If (pEarlierItem->fg.flags And SRCITEM_IS_USING) = 0 OrElse _
                           sqlite3IdListIndex(pEarlierItem->u3.pUsing, zName) < 0 Then
                            sqlite3ErrorMsg(pParse, _
                                StrPtr(!"ambiguous reference to %s in USING()"), zName)
                            Exit While
                        End If
                        pFunctionArguments = sqlite3ExprListAppend( _
                            pParse, pFunctionArguments, pLeftExpr)
                        If pFunctionArguments = 0 Then Return 1
                        pLeftExpr = sqlite3CreateColumnExpr( _
                            db, pSourceList, leftSourceIndex, leftColumnIndex)
                        If pLeftExpr = 0 Then
                            sqlite3ExprListDelete(db, pFunctionArguments)
                            Return 1
                        End If
                        sqlite3SrcItemColumnUsed( _
                            @pSourceList->a(leftSourceIndex), leftColumnIndex)
                    Wend
                    If pFunctionArguments <> 0 Then
                        Dim coalesceToken As sqlite3ParserToken = _
                            Type<sqlite3ParserToken>(0)
                        coalesceToken.z = CPtr(UByte Ptr, StrPtr(!"coalesce"))
                        coalesceToken.n = 8
                        pFunctionArguments = sqlite3ExprListAppend( _
                            pParse, pFunctionArguments, pLeftExpr)
                        If pFunctionArguments = 0 Then Return 1
                        pLeftExpr = sqlite3ExprFunction( _
                            pParse, pFunctionArguments, @coalesceToken, 0)
                        If pLeftExpr <> 0 Then pLeftExpr->affExpr = SQLITE_AFF_DEFER
                    End If
                ElseIf (pRight->fg.jointype And JT_LEFT) <> 0 AndAlso _
                       pParse->nErr = 0 Then
                    pLeftExpr->flags Or= EP_CanBeNull
                End If

                Dim pRightExpr As SqliteExpr Ptr = sqlite3CreateColumnExpr( _
                    db, pSourceList, rightIndex, rightColumnIndex)
                If pRightExpr = 0 Then
                    ' pEquality has not taken ownership of the left expression.
                    sqlite3ExprDelete(db, pLeftExpr)
                    Return 1
                End If
                sqlite3SrcItemColumnUsed(pRight, rightColumnIndex)
                Dim pEquality As SqliteExpr Ptr = sqlite3PExpr( _
                    pParse, TK_EQ, pLeftExpr, pRightExpr)
                If pEquality <> 0 Then
                    pEquality->flags Or= joinFlags
                    pEquality->w.iJoin = pRightExpr->iTable
                End If
                pSelect->pWhere = sqlite3ExprAnd( _
                    pParse, CPtr(SqliteExpr Ptr, pSelect->pWhere), pEquality)
            Next
        ElseIf pRight->u3.pOn <> 0 Then
            sqlite3SetJoinExpr(pRight->u3.pOn, pRight->iCursor, joinFlags)
            pSelect->pWhere = sqlite3ExprAnd( _
                pParse, CPtr(SqliteExpr Ptr, pSelect->pWhere), pRight->u3.pOn)
            pRight->u3.pOn = 0
            pRight->fg.flags Or= SRCITEM_IS_ON
            pSelect->selFlags Or= SF_OnToWhere
        End If

        If haveTableFunctionToLeft = 0 Then
            haveTableFunctionToLeft = CInt( _
                (pLeft->fg.flags And SRCITEM_IS_TABFUNC) <> 0 AndAlso _
                pLeft->u1.pFuncArg <> 0)
        End If
        If ((pRight->fg.flags And SRCITEM_IS_TABFUNC) <> 0 AndAlso _
            joinFlags = EP_OuterON AndAlso pRight->u1.pFuncArg <> 0) OrElse _
           (haveTableFunctionToLeft <> 0 AndAlso joinFlags = EP_OuterON) Then
            pSelect->selFlags Or= SF_OnToWhere
        End If
    Next
    Return CInt(pParse->nErr <> 0 OrElse db->mallocFailed <> 0)
End Function

Private Function sqlite3SelectEmitAggregateResultRow( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pResultList As SqliteExprList Ptr, _
    ByVal pDestination As SqliteSelectDest Ptr, _
    ByVal pHaving As SqliteExpr Ptr, _
    ByVal offsetRegister As SQLITE_C_INT, _
    ByVal limitRegister As SQLITE_C_INT, _
    ByVal nColumn As SQLITE_C_INT, _
    ByVal firstResultRegister As SQLITE_C_INT _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->db = 0 OrElse pSelect = 0 OrElse _
       pResultList = 0 OrElse pDestination = 0 OrElse _
       pResultList->nExpr <> nColumn OrElse nColumn <= 0 OrElse _
       firstResultRegister <= 0 Then Return SQLITE_MISUSE

    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pParse->pVdbe)
    If pVdbe = 0 Then Return SQLITE_MISUSE

    Dim skipResultLabel As SQLITE_C_INT = 0
    If pHaving <> 0 Then
        Dim havingRegister As SQLITE_C_INT = sqlite3GetTempReg(pParse)
        skipResultLabel = sqlite3VdbeMakeLabel(pParse)
        If havingRegister = 0 OrElse skipResultLabel = 0 Then
            sqlite3ReleaseTempReg(pParse, havingRegister)
            Return SQLITE_NOMEM
        End If
        sqlite3ExprCode(pParse, pHaving, havingRegister)
        If pParse->db->mallocFailed <> 0 OrElse pParse->nErr <> 0 Then
            sqlite3ReleaseTempReg(pParse, havingRegister)
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            Return SQLITE_ERROR
        End If
        ' HAVING treats both false and NULL as a rejected group.
        sqlite3VdbeAddOp3(pVdbe, OP_IfNot, havingRegister, skipResultLabel, 1)
        sqlite3ReleaseTempReg(pParse, havingRegister)
    End If

    If pDestination->eDest = SRT_Fifo OrElse _
       pDestination->eDest = SRT_DistFifo OrElse _
       pDestination->eDest = SRT_Queue OrElse _
       pDestination->eDest = SRT_DistQueue OrElse _
       pDestination->eDest = SRT_Coroutine Then
        ' Recursive CTE anchors can be aggregate SELECTs. Route their result
        ' through the shared destination path so queue and coroutine writes
        ' retain the same behavior as ordinary SELECT rows.
        Dim doneLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
        If doneLabel = 0 Then Return SQLITE_NOMEM
        Dim savedLimit As SQLITE_C_INT = pSelect->iLimit
        Dim savedOffset As SQLITE_C_INT = pSelect->iOffset
        pSelect->iLimit = limitRegister
        pSelect->iOffset = offsetRegister
        Dim rowCode As SQLITE_C_INT = sqlite3SelectEmitInternalRow( _
            pParse, pSelect, pDestination, doneLabel, doneLabel)
        pSelect->iLimit = savedLimit
        pSelect->iOffset = savedOffset
        If rowCode <> SQLITE_OK Then Return rowCode
        sqlite3VdbeResolveLabel(pVdbe, doneLabel)
        If skipResultLabel <> 0 Then _
            sqlite3VdbeResolveLabel(pVdbe, skipResultLabel)
        Return SQLITE_OK
    End If

    If limitRegister <> 0 Then
        If skipResultLabel = 0 Then skipResultLabel = sqlite3VdbeMakeLabel(pParse)
        If skipResultLabel = 0 Then Return SQLITE_NOMEM
        sqlite3VdbeAddOp2(pVdbe, OP_IfNot, limitRegister, skipResultLabel)
    End If
    If offsetRegister <> 0 Then
        If skipResultLabel = 0 Then skipResultLabel = sqlite3VdbeMakeLabel(pParse)
        If skipResultLabel = 0 Then Return SQLITE_NOMEM
        sqlite3VdbeAddOp3(pVdbe, OP_IfPos, offsetRegister, skipResultLabel, 1)
    End If

    For resultIndex As SQLITE_C_INT = 0 To nColumn - 1
        Dim pItem As SqliteExprListItem Ptr = _
            sqlite3ExprListItemAt(pResultList, resultIndex)
        If pItem = 0 OrElse pItem->pExpr = 0 Then Return SQLITE_CORRUPT
        sqlite3ExprCode( _
            pParse, CPtr(SqliteExpr Ptr, pItem->pExpr), _
            firstResultRegister + resultIndex)
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        If pParse->nErr <> 0 Then Return SQLITE_ERROR
    Next

    Dim storeResult As SQLITE_C_INT = sqlite3SelectStoreResultRow( _
        pParse, pDestination, firstResultRegister, nColumn)
    If storeResult <> SQLITE_OK Then Return storeResult
    If limitRegister <> 0 Then _
        sqlite3VdbeAddOp2(pVdbe, OP_AddImm, limitRegister, -1)
    If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If skipResultLabel <> 0 Then sqlite3VdbeResolveLabel(pVdbe, skipResultLabel)
    Return SQLITE_OK
End Function

Private Function sqlite3SelectEmitGroupedAggregateResultRow( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pResultList As SqliteExprList Ptr, _
    ByVal pHaving As SqliteExpr Ptr, _
    ByVal pSort As SqliteSortContext Ptr, _
    ByVal pDistinct As SqliteDistinctContext Ptr, _
    ByVal pDestination As SqliteSelectDest Ptr, _
    ByVal limitRegister As SQLITE_C_INT, _
    ByVal offsetRegister As SQLITE_C_INT, _
    ByVal breakLabel As SQLITE_C_INT _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->db = 0 OrElse pSelect = 0 OrElse _
       pResultList = 0 OrElse pDestination = 0 OrElse _
       (pSort = 0 AndAlso pDistinct = 0) Then Return SQLITE_MISUSE

    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pParse->pVdbe)
    If pVdbe = 0 Then Return SQLITE_MISUSE
    Dim rowDoneLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
    If rowDoneLabel = 0 Then Return SQLITE_NOMEM

    If pHaving <> 0 Then
        Dim havingRegister As SQLITE_C_INT = sqlite3GetTempReg(pParse)
        If havingRegister = 0 Then Return SQLITE_NOMEM
        sqlite3ExprCode(pParse, pHaving, havingRegister)
        If pParse->db->mallocFailed <> 0 OrElse pParse->nErr <> 0 Then
            sqlite3ReleaseTempReg(pParse, havingRegister)
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            Return SQLITE_ERROR
        End If
        sqlite3VdbeAddOp3(pVdbe, OP_IfNot, havingRegister, rowDoneLabel, 1)
        sqlite3ReleaseTempReg(pParse, havingRegister)
    End If

    If pSort <> 0 OrElse pDistinct <> 0 Then
        pSelect->iLimit = limitRegister
        pSelect->iOffset = offsetRegister
    End If
    Dim outputBreakLabel As SQLITE_C_INT = rowDoneLabel
    If limitRegister <> 0 AndAlso breakLabel <> 0 Then _
        outputBreakLabel = breakLabel
    sqlite3SelectAggregateInnerLoop( _
        pParse, pSelect, pSort, pDistinct, pDestination, _
        rowDoneLabel, outputBreakLabel)
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR
    sqlite3VdbeResolveLabel(pVdbe, rowDoneLabel)
    Return SQLITE_OK
End Function

Private Function sqlite3SelectEmitSortedAggregateResultRow( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pHaving As SqliteExpr Ptr, _
    ByVal pSort As SqliteSortContext Ptr, _
    ByVal pDistinct As SqliteDistinctContext Ptr, _
    ByVal pDestination As SqliteSelectDest Ptr _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->db = 0 OrElse pSelect = 0 OrElse _
       pDestination = 0 OrElse (pSort = 0 AndAlso pDistinct = 0) Then _
        Return SQLITE_MISUSE

    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pParse->pVdbe)
    If pVdbe = 0 Then Return SQLITE_MISUSE
    Dim rowDoneLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
    If rowDoneLabel = 0 Then Return SQLITE_NOMEM
    If pHaving <> 0 Then
        Dim havingRegister As SQLITE_C_INT = sqlite3GetTempReg(pParse)
        If havingRegister = 0 Then Return SQLITE_NOMEM
        sqlite3ExprCode(pParse, pHaving, havingRegister)
        If pParse->db->mallocFailed <> 0 OrElse pParse->nErr <> 0 Then
            sqlite3ReleaseTempReg(pParse, havingRegister)
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            Return SQLITE_ERROR
        End If
        sqlite3VdbeAddOp3(pVdbe, OP_IfNot, havingRegister, rowDoneLabel, 1)
        sqlite3ReleaseTempReg(pParse, havingRegister)
    End If

    sqlite3SelectAggregateInnerLoop( _
        pParse, pSelect, pSort, pDistinct, pDestination, _
        rowDoneLabel, rowDoneLabel)
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR
    sqlite3VdbeResolveLabel(pVdbe, rowDoneLabel)
    Return SQLITE_OK
End Function

Private Function sqlite3SelectCompileSimpleAggregateFromClause( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pSourceList As SqliteSrcList Ptr, _
    ByVal pResultList As SqliteExprList Ptr, _
    ByVal pDestination As SqliteSelectDest Ptr, _
    ByVal nColumn As SQLITE_C_INT _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->db = 0 OrElse pSelect = 0 OrElse _
       (pSourceList <> 0 AndAlso _
        (pSourceList->nSrc < 0 OrElse _
         pSourceList->nAlloc < pSourceList->nSrc)) OrElse _
       pResultList = 0 OrElse pDestination = 0 OrElse _
       (pDestination->eDest <> SRT_Output AndAlso _
        pDestination->eDest <> SRT_EphemTab AndAlso _
        pDestination->eDest <> SRT_Table AndAlso _
        pDestination->eDest <> SRT_Fifo AndAlso _
        pDestination->eDest <> SRT_DistFifo AndAlso _
        pDestination->eDest <> SRT_Queue AndAlso _
        pDestination->eDest <> SRT_DistQueue AndAlso _
        pDestination->eDest <> SRT_Mem AndAlso _
       pDestination->eDest <> SRT_Exists AndAlso _
       pDestination->eDest <> SRT_Set AndAlso _
       pDestination->eDest <> SRT_Discard AndAlso _
       pDestination->eDest <> SRT_Coroutine) OrElse nColumn <= 0 Then _
        Return SQLITE_MISUSE

    ' This path handles one aggregate result row. GROUP BY has a separate
    ' sorter path. Top-level DISTINCT and ORDER BY cannot change a single-row
    ' result; aggregate-local DISTINCT, ORDER BY, and FILTER use shared helpers.
    If pSelect->pGroupBy <> 0 Then Return SQLITE_ERROR

#ifndef SQLITE_OMIT_WINDOWFUNC
    If pSelect->pWin <> 0 Then Return SQLITE_ERROR
#endif

    Dim pAggregateInfo As SqliteAggInfo Ptr = _
        sqlite3SelectAggregateInfoCreate(pParse)
    If pAggregateInfo = 0 Then
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_ERROR
    End If
    pAggregateInfo->selId = pSelect->selId
#ifdef SQLITE_DEBUG
    pAggregateInfo->pSelect = pSelect
#endif

    Dim nameContext As SqliteNameContext = Type<SqliteNameContext>(0)
    nameContext.pParse = pParse
    nameContext.pSrcList = pSourceList
    nameContext.uNC.pAggInfo = pAggregateInfo
    nameContext.ncFlags = &H00000100 ' NC_UAggInfo

    For resultIndex As SQLITE_C_INT = 0 To pResultList->nExpr - 1
        Dim pItem As SqliteExprListItem Ptr = _
            sqlite3ExprListItemAt(pResultList, resultIndex)
        If pItem = 0 OrElse pItem->pExpr = 0 Then Return SQLITE_CORRUPT
        sqlite3ExprAnalyzeAggregates(@nameContext, _
            CPtr(SqliteExpr Ptr, pItem->pExpr))
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        If pParse->nErr <> 0 Then Return SQLITE_ERROR
    Next
    Dim pOrderBy As SqliteExprList Ptr = _
        CPtr(SqliteExprList Ptr, pSelect->pOrderBy)
    If pOrderBy <> 0 Then
        For orderIndex As SQLITE_C_INT = 0 To pOrderBy->nExpr - 1
            Dim pOrderItem As SqliteExprListItem Ptr = _
                sqlite3ExprListItemAt(pOrderBy, orderIndex)
            If pOrderItem = 0 OrElse pOrderItem->pExpr = 0 Then _
                Return SQLITE_CORRUPT
            sqlite3ExprAnalyzeAggregates(@nameContext, _
                CPtr(SqliteExpr Ptr, pOrderItem->pExpr))
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            If pParse->nErr <> 0 Then Return SQLITE_ERROR
        Next
    End If
    If pSelect->pHaving <> 0 Then
        sqlite3ExprAnalyzeAggregates( _
            @nameContext, CPtr(SqliteExpr Ptr, pSelect->pHaving))
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        If pParse->nErr <> 0 Then Return SQLITE_ERROR
    End If

    ' The first pass finds aggregate functions and bare result columns.
    ' Argument analysis adds input columns afterward, so nAccumulator keeps
    ' the original distinction used for bare-column row selection.
    pAggregateInfo->nAccumulator = pAggregateInfo->nColumn
    Dim minMaxFlag As UShort = 0
    Dim pMinMaxFunction As SqliteExpr Ptr = 0
    If pSelect->pHaving = 0 AndAlso pAggregateInfo->nFunc = 1 Then
        pMinMaxFunction = CPtr( _
            SqliteExpr Ptr, pAggregateInfo->aFunc[0].pFExpr)
        minMaxFlag = sqlite3SelectMinMaxOrderFlag( _
            pParse->db, pMinMaxFunction)
    End If
    sqlite3SelectAggregateAnalyzeFuncArgs(pAggregateInfo, @nameContext)
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR
    If pAggregateInfo->nFunc < 0 OrElse _
       (pAggregateInfo->nFunc > 0 AndAlso pAggregateInfo->aFunc = 0) Then _
        Return SQLITE_CORRUPT

    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pParse->pVdbe)
    If pVdbe = 0 Then Return SQLITE_MISUSE
    Dim limitRegister As SQLITE_C_INT = 0
    Dim offsetRegister As SQLITE_C_INT = 0
    Dim limitJumpAddress As SQLITE_C_INT = -1
    Dim pLimit As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pSelect->pLimit)
    If pLimit <> 0 Then
        If pLimit->op <> TK_LIMIT OrElse pLimit->pLeft = 0 Then _
            Return SQLITE_CORRUPT
        limitRegister = sqlite3SelectNextRegister(pParse)
        If limitRegister = 0 Then Return SQLITE_NOMEM
        sqlite3ExprCode(pParse, CPtr(SqliteExpr Ptr, pLimit->pLeft), limitRegister)
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        If pParse->nErr <> 0 Then Return SQLITE_ERROR
        sqlite3VdbeAddOp1(pVdbe, OP_MustBeInt, limitRegister)

        If pLimit->pRight <> 0 Then
            offsetRegister = sqlite3SelectNextRegister(pParse)
            If offsetRegister = 0 Then Return SQLITE_NOMEM
            sqlite3ExprCode( _
                pParse, CPtr(SqliteExpr Ptr, pLimit->pRight), offsetRegister)
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            If pParse->nErr <> 0 Then Return SQLITE_ERROR
            sqlite3VdbeAddOp1(pVdbe, OP_MustBeInt, offsetRegister)
        End If

        ' LIMIT zero skips aggregate input processing as well as result output.
        limitJumpAddress = sqlite3VdbeAddOp2( _
            pVdbe, OP_IfNot, limitRegister, _
            sqlite3VdbeCurrentAddr(pVdbe) + 1)
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        If pParse->nErr <> 0 OrElse limitJumpAddress < 0 Then Return SQLITE_ERROR
    End If

    For functionIndex As SQLITE_C_INT = 0 To pAggregateInfo->nFunc - 1
        Dim pFunction As SqliteAggInfoFunction Ptr = _
            @pAggregateInfo->aFunc[functionIndex]
        If pFunction->pFExpr = 0 OrElse pFunction->pFunc = 0 Then _
            Return SQLITE_CORRUPT
    Next

    If pParse->nMem < 0 OrElse _
       pAggregateInfo->nColumn > SQLITE_MAX_VDBE_OP - pParse->nMem OrElse _
       pAggregateInfo->nFunc > SQLITE_MAX_VDBE_OP - pParse->nMem - _
           pAggregateInfo->nColumn Then Return SQLITE_TOOBIG

    sqlite3SelectAggregateAssignRegisters(pParse, pAggregateInfo)
    If pParse->nErr <> 0 Then Return SQLITE_ERROR
    sqlite3SelectAggregateReset(pParse, pAggregateInfo)
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR

    Dim accumulatorFlagRegister As SQLITE_C_INT = 0
    If pAggregateInfo->nAccumulator > 0 Then
        Dim needsCollation As SQLITE_C_INT = 0
        For functionIndex As SQLITE_C_INT = 0 To pAggregateInfo->nFunc - 1
            If (pAggregateInfo->aFunc[functionIndex].pFunc->funcFlags And _
                SQLITE_FUNC_NEEDCOLL) <> 0 Then
                needsCollation = 1
                Exit For
            End If
        Next
        If needsCollation = 0 Then
            accumulatorFlagRegister = sqlite3SelectNextRegister(pParse)
            If accumulatorFlagRegister = 0 Then Return SQLITE_NOMEM
            sqlite3VdbeAddInt64( _
                CPtr(SqliteVdbe Ptr, pParse->pVdbe), accumulatorFlagRegister, 0)
        End If
    End If

    Dim pWhereInfo As SqliteWhereInfo Ptr = 0
    Dim pMinMaxOrderBy As SqliteExprList Ptr = 0
    Dim pDistinct As SqliteExprList Ptr = 0
    Dim distinctFlags As UShort = 0
    Dim distinctType As SQLITE_C_INT = 0
    Dim noInputLabel As SQLITE_C_INT = 0
    If pAggregateInfo->nAccumulator = 0 AndAlso _
       pAggregateInfo->nFunc = 1 AndAlso pAggregateInfo->aFunc <> 0 Then
        Dim pDistinctFunction As SqliteAggInfoFunction Ptr = _
            @pAggregateInfo->aFunc[0]
        If pDistinctFunction->iDistinct >= 0 AndAlso _
           pDistinctFunction->pFExpr <> 0 Then
            pDistinct = CPtr(SqliteExprList Ptr, _
                pDistinctFunction->pFExpr->x.pList)
            If pDistinct <> 0 Then _
                distinctFlags = WHERE_WANT_DISTINCT Or WHERE_AGG_DISTINCT
        End If
    End If
    If pSourceList <> 0 AndAlso pSourceList->nSrc > 0 Then
        If minMaxFlag <> 0 Then
            pMinMaxOrderBy = sqlite3SelectMinMaxOrderBy( _
                pParse->db, pMinMaxFunction, minMaxFlag)
            If pMinMaxOrderBy = 0 Then
                If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
                Return SQLITE_ERROR
            End If
        End If
        pWhereInfo = sqlite3WhereBegin( _
            pParse, pSourceList, CPtr(SqliteExpr Ptr, pSelect->pWhere), _
            pMinMaxOrderBy, pDistinct, pSelect, _
            minMaxFlag Or distinctFlags, 0)
        If pWhereInfo = 0 Then
            If pMinMaxOrderBy <> 0 Then _
                sqlite3ExprListDelete(pParse->db, pMinMaxOrderBy)
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            Return SQLITE_ERROR
        End If
        distinctType = sqlite3WhereIsDistinct(pWhereInfo)
    ElseIf pSelect->pWhere <> 0 Then
        ' A SELECT without FROM still has one implicit input row. WHERE can
        ' remove that row before aggregate step callbacks run.
        Dim whereRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
        noInputLabel = sqlite3VdbeMakeLabel(pParse)
        If whereRegister = 0 OrElse noInputLabel = 0 Then Return SQLITE_NOMEM
        Dim whereCode As SQLITE_C_INT = sqlite3SelectCompileExpr( _
            pParse, CPtr(SqliteExpr Ptr, pSelect->pWhere), whereRegister, 0)
        If whereCode <> SQLITE_OK Then Return whereCode
        sqlite3VdbeAddOp3( _
            pVdbe, OP_IfNot, whereRegister, noInputLabel, 1)
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    End If

    sqlite3SelectAggregateUpdate( _
        pParse, accumulatorFlagRegister, pAggregateInfo, distinctType)
    If pDistinct <> 0 AndAlso distinctType <> WHERE_DISTINCT_NOOP Then
        Dim pDistinctFunction As SqliteAggInfoFunction Ptr = _
            @pAggregateInfo->aFunc[0]
        Dim fixCode As SQLITE_C_INT = sqlite3SelectFixDistinctOpenEph( _
            pParse, distinctType, pDistinctFunction->iDistinct, _
            pDistinctFunction->iDistAddr)
        If fixCode <> SQLITE_OK Then Return fixCode
    End If
    If accumulatorFlagRegister <> 0 Then _
        sqlite3VdbeAddInt64( _
            CPtr(SqliteVdbe Ptr, pParse->pVdbe), accumulatorFlagRegister, 1)
    If pWhereInfo <> 0 Then
        If minMaxFlag <> 0 Then _
            sqlite3WhereMinMaxOptEarlyOut(pVdbe, pWhereInfo)
        sqlite3WhereEnd(pWhereInfo)
    End If
    If pMinMaxOrderBy <> 0 Then _
        sqlite3ExprListDelete(pParse->db, pMinMaxOrderBy)
    If noInputLabel <> 0 Then sqlite3VdbeResolveLabel(pVdbe, noInputLabel)
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR

    sqlite3SelectAggregateFinalize(pParse, pAggregateInfo)
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR

    If pParse->nMem < 0 OrElse _
       nColumn > SQLITE_MAX_VDBE_OP - pParse->nMem Then Return SQLITE_TOOBIG
    Dim firstResultRegister As SQLITE_C_INT = pParse->nMem + 1
    pParse->nMem += nColumn
    Dim resultCode As SQLITE_C_INT = sqlite3SelectEmitAggregateResultRow( _
        pParse, pSelect, pResultList, pDestination, _
        CPtr(SqliteExpr Ptr, pSelect->pHaving), _
        offsetRegister, limitRegister, nColumn, firstResultRegister)
    If resultCode <> SQLITE_OK Then Return resultCode
    If limitJumpAddress >= 0 Then _
        sqlite3VdbeChangeP2( _
            pVdbe, limitJumpAddress, sqlite3VdbeCurrentAddr(pVdbe))
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR
    Return SQLITE_OK
End Function

Private Function sqlite3SelectEmitOrderedGroupInputRow( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pAggregateInfo As SqliteAggInfo Ptr, _
    ByVal pGroupBy As SqliteExprList Ptr, _
    ByVal pResultList As SqliteExprList Ptr, _
    ByVal pSortKey As sqlite3VdbeKeyInfoPrefix Ptr, _
    ByVal previousGroupRegister As SQLITE_C_INT, _
    ByVal currentGroupRegister As SQLITE_C_INT, _
    ByVal groupHasRowsRegister As SQLITE_C_INT, _
    ByVal outputReturnRegister As SQLITE_C_INT, _
    ByVal outputSubroutineLabel As SQLITE_C_INT, _
    ByVal limitRegister As SQLITE_C_INT, _
    ByVal pSort As SqliteSortContext Ptr, _
    ByVal aggregateDistinctType As SQLITE_C_INT, _
    ByVal aggregateDistinctFlags As UShort, _
    ByVal aggregateDistinctInitialOpenAddress As SQLITE_C_INT, _
    ByVal pStopGroupsLabel As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->db = 0 OrElse pSelect = 0 OrElse _
       pAggregateInfo = 0 OrElse pGroupBy = 0 OrElse pResultList = 0 OrElse _
       pSortKey = 0 OrElse previousGroupRegister <= 0 OrElse _
       currentGroupRegister <= 0 OrElse groupHasRowsRegister <= 0 OrElse _
       outputReturnRegister <= 0 OrElse outputSubroutineLabel = 0 Then _
        Return SQLITE_MISUSE

    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pParse->pVdbe)
    If pVdbe = 0 Then Return SQLITE_MISUSE

    ' Group keys are read from the current source row on the ordered-index
    ' path. Keep GROUP BY ordinals bound to that value for result expressions.
    pAggregateInfo->directMode = 1
    For groupIndex As SQLITE_C_INT = 0 To pGroupBy->nExpr - 1
        Dim pGroupItem As SqliteExprListItem Ptr = _
            sqlite3ExprListItemAt(pGroupBy, groupIndex)
        If pGroupItem = 0 OrElse pGroupItem->pExpr = 0 Then
            pAggregateInfo->directMode = 0
            Return SQLITE_CORRUPT
        End If
        sqlite3ExprCode( _
            pParse, CPtr(SqliteExpr Ptr, pGroupItem->pExpr), _
            currentGroupRegister + groupIndex)
        If pParse->db->mallocFailed <> 0 OrElse pParse->nErr <> 0 Then
            pAggregateInfo->directMode = 0
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            Return SQLITE_ERROR
        End If

        Dim resultColumn As SQLITE_C_INT = pGroupItem->u.x.iOrderByCol
        If resultColumn > 0 Then
            If resultColumn > pResultList->nExpr Then
                pAggregateInfo->directMode = 0
                Return SQLITE_CORRUPT
            End If
            Dim pResultItem As SqliteExprListItem Ptr = _
                sqlite3ExprListItemAt(pResultList, resultColumn - 1)
            If pResultItem = 0 OrElse pResultItem->pExpr = 0 Then
                pAggregateInfo->directMode = 0
                Return SQLITE_CORRUPT
            End If
            Dim pBase As SqliteExpr Ptr = sqlite3ExprSkipCollateAndLikely( _
                CPtr(SqliteExpr Ptr, pResultItem->pExpr))
            While pBase <> 0 AndAlso pBase->op = TK_IF_NULL_ROW
                If pBase->pLeft = 0 Then Exit While
                pBase = sqlite3ExprSkipCollateAndLikely( _
                    CPtr(SqliteExpr Ptr, pBase->pLeft))
            Wend
            If pBase <> 0 AndAlso pBase->op <> TK_AGG_COLUMN AndAlso _
               pBase->op <> TK_REGISTER Then
                sqlite3ExprToRegister( _
                    CPtr(SqliteExpr Ptr, pResultItem->pExpr), _
                    previousGroupRegister + groupIndex)
            End If
        End If
    Next
    pAggregateInfo->directMode = 0

    Dim initializeGroupLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
    If initializeGroupLabel = 0 Then Return SQLITE_NOMEM
    sqlite3VdbeAddOp2( _
        pVdbe, OP_IfNot, groupHasRowsRegister, initializeGroupLabel)
    Dim pCompareKey As sqlite3VdbeKeyInfoPrefix Ptr = _
        sqlite3KeyInfoRef(pSortKey)
    If pCompareKey = 0 Then
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_ERROR
    End If
    sqlite3VdbeAddOp4( _
        pVdbe, OP_Compare, previousGroupRegister, currentGroupRegister, _
        pGroupBy->nExpr, CPtr(Const ZString Ptr, pCompareKey), P4_KEYINFO)
    Dim groupJumpAddress As SQLITE_C_INT = _
        sqlite3VdbeAddOp3(pVdbe, OP_Jump, 0, 0, 0)
    Dim groupChangeAddress As SQLITE_C_INT = sqlite3VdbeCurrentAddr(pVdbe)

    sqlite3SelectAggregateFinalize(pParse, pAggregateInfo)
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR
    sqlite3VdbeAddOp2( _
        pVdbe, OP_Gosub, outputReturnRegister, outputSubroutineLabel)

    Dim stopGroupsLabel As SQLITE_C_INT = 0
    If limitRegister <> 0 AndAlso pSort = 0 Then
        stopGroupsLabel = sqlite3VdbeMakeLabel(pParse)
        If stopGroupsLabel = 0 Then Return SQLITE_NOMEM
        If pStopGroupsLabel <> 0 Then *pStopGroupsLabel = stopGroupsLabel
        sqlite3VdbeAddOp2(pVdbe, OP_IfNot, limitRegister, stopGroupsLabel)
    End If

    sqlite3SelectAggregateReset(pParse, pAggregateInfo)
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR
    sqlite3VdbeAddInt64(pVdbe, groupHasRowsRegister, 0)

    sqlite3VdbeResolveLabel(pVdbe, initializeGroupLabel)
    For groupIndex As SQLITE_C_INT = 0 To pGroupBy->nExpr - 1
        sqlite3VdbeAddOp2( _
            pVdbe, OP_Copy, currentGroupRegister + groupIndex, _
            previousGroupRegister + groupIndex)
    Next
    Dim aggregateUpdateAddress As SQLITE_C_INT = sqlite3VdbeCurrentAddr(pVdbe)
    sqlite3VdbeChangeP1(pVdbe, groupJumpAddress, groupChangeAddress)
    sqlite3VdbeChangeP2(pVdbe, groupJumpAddress, aggregateUpdateAddress)
    sqlite3VdbeChangeP3(pVdbe, groupJumpAddress, groupChangeAddress)

    sqlite3SelectAggregateUpdate( _
        pParse, groupHasRowsRegister, pAggregateInfo, aggregateDistinctType)
    If aggregateDistinctFlags <> 0 AndAlso _
       aggregateDistinctType <> WHERE_DISTINCT_NOOP Then
        If pAggregateInfo->nFunc <> 1 OrElse pAggregateInfo->aFunc = 0 Then _
            Return SQLITE_CORRUPT
        Dim pDistinctFunction As SqliteAggInfoFunction Ptr = _
            @pAggregateInfo->aFunc[0]
        Dim fixCode As SQLITE_C_INT = sqlite3SelectFixDistinctOpenEph( _
            pParse, aggregateDistinctType, pDistinctFunction->iDistinct, _
            pDistinctFunction->iDistAddr)
        If fixCode <> SQLITE_OK Then Return fixCode
        If aggregateDistinctInitialOpenAddress >= 0 AndAlso _
           aggregateDistinctInitialOpenAddress <> pDistinctFunction->iDistAddr Then
            fixCode = sqlite3SelectFixDistinctOpenEph( _
                pParse, aggregateDistinctType, pDistinctFunction->iDistinct, _
                aggregateDistinctInitialOpenAddress)
            If fixCode <> SQLITE_OK Then Return fixCode
        End If
    End If
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR
    sqlite3VdbeAddInt64(pVdbe, groupHasRowsRegister, 1)
    Return SQLITE_OK
End Function

Private Function sqlite3SelectCompileGroupedAggregateFromClause( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pSourceList As SqliteSrcList Ptr, _
    ByVal pResultList As SqliteExprList Ptr, _
    ByVal pGroupBy As SqliteExprList Ptr, _
    ByVal pDestination As SqliteSelectDest Ptr, _
    ByVal nColumn As SQLITE_C_INT _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->db = 0 OrElse pSelect = 0 OrElse _
       (pSourceList <> 0 AndAlso _
        (pSourceList->nSrc < 0 OrElse _
         pSourceList->nAlloc < pSourceList->nSrc)) OrElse _
       pResultList = 0 OrElse pGroupBy = 0 OrElse _
       pDestination = 0 OrElse _
       (pDestination->eDest <> SRT_Output AndAlso _
        pDestination->eDest <> SRT_EphemTab AndAlso _
        pDestination->eDest <> SRT_Table AndAlso _
        pDestination->eDest <> SRT_Mem AndAlso _
        pDestination->eDest <> SRT_Exists AndAlso _
        pDestination->eDest <> SRT_Set AndAlso _
        pDestination->eDest <> SRT_Discard AndAlso _
        pDestination->eDest <> SRT_Coroutine) OrElse _
        nColumn <= 0 Then Return SQLITE_MISUSE
    If pGroupBy->nExpr <= 0 OrElse pGroupBy->nAlloc < pGroupBy->nExpr Then _
        Return SQLITE_CORRUPT
#ifndef SQLITE_OMIT_WINDOWFUNC
    If pSelect->pWin <> 0 Then Return SQLITE_ERROR
#endif

    Dim pAggregateInfo As SqliteAggInfo Ptr = _
        sqlite3SelectAggregateInfoCreate(pParse)
    If pAggregateInfo = 0 Then
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_ERROR
    End If
    pAggregateInfo->selId = pSelect->selId
    pAggregateInfo->pGroupBy = pGroupBy
    pAggregateInfo->nSortingColumn = pGroupBy->nExpr
#ifdef SQLITE_DEBUG
    pAggregateInfo->pSelect = pSelect
#endif

    Dim nameContext As SqliteNameContext = Type<SqliteNameContext>(0)
    nameContext.pParse = pParse
    nameContext.pSrcList = pSourceList
    nameContext.uNC.pAggInfo = pAggregateInfo
    nameContext.ncFlags = &H00000100 ' NC_UAggInfo
    Dim pOrderBy As SqliteExprList Ptr = _
        CPtr(SqliteExprList Ptr, pSelect->pOrderBy)
    Dim orderByGroup As SQLITE_C_INT = 0
    If pOrderBy <> 0 AndAlso _
       sqlite3SelectCopySortOrder(pGroupBy, pOrderBy) <> 0 Then
        orderByGroup = CInt( _
            sqlite3ExprListCompare(pGroupBy, pOrderBy, -1) = 0)
    End If

    For resultIndex As SQLITE_C_INT = 0 To pResultList->nExpr - 1
        Dim pItem As SqliteExprListItem Ptr = _
            sqlite3ExprListItemAt(pResultList, resultIndex)
        If pItem = 0 OrElse pItem->pExpr = 0 Then Return SQLITE_CORRUPT
        sqlite3ExprAnalyzeAggregates(@nameContext, _
            CPtr(SqliteExpr Ptr, pItem->pExpr))
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        If pParse->nErr <> 0 Then Return SQLITE_ERROR
    Next
    If pOrderBy <> 0 Then
        If pOrderBy->nExpr <= 0 OrElse pOrderBy->nAlloc < pOrderBy->nExpr Then _
            Return SQLITE_CORRUPT
        For orderIndex As SQLITE_C_INT = 0 To pOrderBy->nExpr - 1
            Dim pOrderItem As SqliteExprListItem Ptr = _
                sqlite3ExprListItemAt(pOrderBy, orderIndex)
            If pOrderItem = 0 OrElse pOrderItem->pExpr = 0 Then _
                Return SQLITE_CORRUPT
            sqlite3ExprAnalyzeAggregates(@nameContext, _
                CPtr(SqliteExpr Ptr, pOrderItem->pExpr))
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            If pParse->nErr <> 0 Then Return SQLITE_ERROR
        Next
    End If
    If pSelect->pHaving <> 0 Then
        sqlite3ExprAnalyzeAggregates( _
            @nameContext, CPtr(SqliteExpr Ptr, pSelect->pHaving))
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        If pParse->nErr <> 0 Then Return SQLITE_ERROR
    End If

    pAggregateInfo->nAccumulator = pAggregateInfo->nColumn
    sqlite3SelectAggregateAnalyzeFuncArgs(pAggregateInfo, @nameContext)
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR
    If pAggregateInfo->nColumn < 0 OrElse _
       (pAggregateInfo->nColumn > 0 AndAlso pAggregateInfo->aCol = 0) OrElse _
       pAggregateInfo->nFunc < 0 OrElse _
       (pAggregateInfo->nFunc > 0 AndAlso pAggregateInfo->aFunc = 0) Then _
        Return SQLITE_CORRUPT

    For functionIndex As SQLITE_C_INT = 0 To pAggregateInfo->nFunc - 1
        Dim pFunction As SqliteAggInfoFunction Ptr = _
            @pAggregateInfo->aFunc[functionIndex]
        If pFunction->pFExpr = 0 OrElse pFunction->pFunc = 0 Then _
            Return SQLITE_CORRUPT
    Next

    If pAggregateInfo->nSortingColumn < pGroupBy->nExpr OrElse _
       pAggregateInfo->nSortingColumn > SQLITE_MAX_VDBE_OP OrElse _
       pParse->nMem < 0 OrElse _
       pAggregateInfo->nColumn > SQLITE_MAX_VDBE_OP - pParse->nMem OrElse _
       pAggregateInfo->nFunc > SQLITE_MAX_VDBE_OP - pParse->nMem - _
           pAggregateInfo->nColumn Then Return SQLITE_TOOBIG
    If pParse->nTab < 0 OrElse pParse->nTab >= &H7FFFFFFF Then _
        Return SQLITE_TOOBIG

    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pParse->pVdbe)
    If pVdbe = 0 Then Return SQLITE_MISUSE
    Dim pSortKey As sqlite3VdbeKeyInfoPrefix Ptr = _
        sqlite3KeyInfoFromExprList( _
            pParse, pGroupBy, 0, pAggregateInfo->nColumn)
    If pSortKey = 0 Then
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_ERROR
    End If

    pAggregateInfo->sortingIdx = pParse->nTab
    pParse->nTab += 1
    Dim groupSortOpenAddress As SQLITE_C_INT = sqlite3VdbeAddOp4( _
        pVdbe, OP_SorterOpen, pAggregateInfo->sortingIdx, _
        pAggregateInfo->nSortingColumn, 0, _
        CPtr(Const ZString Ptr, pSortKey), P4_KEYINFO)
    If pParse->db->mallocFailed <> 0 OrElse groupSortOpenAddress < 0 Then _
        Return SQLITE_NOMEM

    sqlite3SelectAggregateAssignRegisters(pParse, pAggregateInfo)
    If pParse->nErr <> 0 Then Return SQLITE_ERROR
    sqlite3SelectAggregateReset(pParse, pAggregateInfo)
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR
    Dim aggregateDistinctInitialOpenAddress As SQLITE_C_INT = -1
    If pAggregateInfo->nFunc = 1 AndAlso pAggregateInfo->aFunc <> 0 AndAlso _
       pAggregateInfo->aFunc[0].iDistinct >= 0 Then
        aggregateDistinctInitialOpenAddress = _
            pAggregateInfo->aFunc[0].iDistAddr
    End If

    Dim limitRegister As SQLITE_C_INT = pSelect->iLimit
    Dim offsetRegister As SQLITE_C_INT = pSelect->iOffset
    Dim skipSourceScanLabel As SQLITE_C_INT = 0
    Dim pLimit As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pSelect->pLimit)
    If limitRegister = 0 AndAlso pLimit <> 0 Then
        If pLimit->op <> TK_LIMIT OrElse pLimit->pLeft = 0 Then _
            Return SQLITE_CORRUPT
        limitRegister = sqlite3SelectNextRegister(pParse)
        If limitRegister = 0 Then Return SQLITE_NOMEM
        sqlite3ExprCode(pParse, CPtr(SqliteExpr Ptr, pLimit->pLeft), limitRegister)
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        If pParse->nErr <> 0 Then Return SQLITE_ERROR
        sqlite3VdbeAddOp1(pVdbe, OP_MustBeInt, limitRegister)

        If pLimit->pRight <> 0 Then
            offsetRegister = sqlite3SelectNextRegister(pParse)
            If offsetRegister = 0 Then Return SQLITE_NOMEM
            sqlite3ExprCode( _
                pParse, CPtr(SqliteExpr Ptr, pLimit->pRight), offsetRegister)
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            If pParse->nErr <> 0 Then Return SQLITE_ERROR
            sqlite3VdbeAddOp1(pVdbe, OP_MustBeInt, offsetRegister)
        End If

        skipSourceScanLabel = sqlite3VdbeMakeLabel(pParse)
        If skipSourceScanLabel = 0 Then Return SQLITE_NOMEM
        sqlite3VdbeAddOp2( _
            pVdbe, OP_IfNot, limitRegister, skipSourceScanLabel)
    End If

    Dim registerBase As SQLITE_C_INT = sqlite3GetTempRange( _
        pParse, pAggregateInfo->nSortingColumn)
    Dim recordRegister As SQLITE_C_INT = sqlite3GetTempReg(pParse)
    If registerBase = 0 OrElse recordRegister = 0 Then
        If skipSourceScanLabel <> 0 Then _
            sqlite3VdbeResolveLabel(pVdbe, skipSourceScanLabel)
        Return SQLITE_NOMEM
    End If

    Dim pSort As SqliteSortContext Ptr = 0
    Dim sortContext As SqliteSortContext
    Dim sortOpenAddress As SQLITE_C_INT = -1
    If pOrderBy <> 0 Then
        If pOrderBy->nExpr <= 0 OrElse pOrderBy->nAlloc < pOrderBy->nExpr OrElse _
           pOrderBy->nExpr > SQLITE_MAX_VDBE_OP - nColumn - 1 Then _
            Return SQLITE_TOOBIG
        If pParse->nTab < 0 OrElse pParse->nTab >= &H7FFFFFFF Then _
            Return SQLITE_TOOBIG

        sortContext.pOrderBy = pOrderBy
        sortContext.nOBSat = 0
        sortContext.iECursor = pParse->nTab
        sortContext.regReturn = 0
        sortContext.labelBkOut = 0
        sortContext.addrSortIndex = -1
        sortContext.labelDone = 0
        sortContext.labelOBLopt = 0
        sortContext.sortFlags = 0
        sortContext.pDeferredRowLoad = 0
#ifdef SQLITE_ENABLE_SORTER_REFERENCES
        sortContext.nDefer = 0
        For deferredIndex As SQLITE_C_INT = 0 To UBound(sortContext.aDefer)
            sortContext.aDefer(deferredIndex).pTab = 0
            sortContext.aDefer(deferredIndex).iCsr = 0
            sortContext.aDefer(deferredIndex).nKey = 0
        Next
#endif
#ifdef SQLITE_ENABLE_STMT_SCANSTATUS
        sortContext.addrPush = 0
        sortContext.addrPushEnd = 0
#endif
        pParse->nTab += 1
        Dim pOrderKey As sqlite3VdbeKeyInfoPrefix Ptr = _
            sqlite3KeyInfoFromExprList(pParse, pOrderBy, 0, nColumn)
        If pOrderKey = 0 Then
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            Return SQLITE_ERROR
        End If
        ' Bounded ORDER BY uses a B-tree because the sorter cannot keep the
        ' best rows with OP_Last and OP_IdxLE.
        Dim sortOpenOpcode As SQLITE_C_INT = OP_OpenEphemeral
        If limitRegister = 0 Then
            sortContext.sortFlags = SQLITE_SORTFLAG_USE_SORTER
            sortOpenOpcode = OP_SorterOpen
        End If
        Dim sortFieldCount As SQLITE_C_INT = pOrderBy->nExpr + 1 + nColumn
        sortOpenAddress = sqlite3VdbeAddOp4( _
            pVdbe, sortOpenOpcode, sortContext.iECursor, sortFieldCount, 0, _
            CPtr(Const ZString Ptr, pOrderKey), P4_KEYINFO)
        If pParse->db->mallocFailed <> 0 OrElse sortOpenAddress < 0 Then _
            Return SQLITE_NOMEM
        sortContext.addrSortIndex = sortOpenAddress
        pSort = @sortContext
    End If

    Dim pDistinct As SqliteDistinctContext Ptr = 0
    Dim distinctContext As SqliteDistinctContext
    If (pSelect->selFlags And SF_Distinct) <> 0 Then
        If pParse->nTab < 0 OrElse pParse->nTab >= &H7FFFFFFF Then _
            Return SQLITE_TOOBIG
        distinctContext.isTnct = 1
        distinctContext.eTnctType = WHERE_DISTINCT_UNORDERED
        distinctContext.tabTnct = pParse->nTab
        pParse->nTab += 1
        Dim pDistinctKey As sqlite3VdbeKeyInfoPrefix Ptr = _
            sqlite3KeyInfoFromExprList(pParse, pResultList, 0, 0)
        If pDistinctKey = 0 Then
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            Return SQLITE_ERROR
        End If
        distinctContext.addrTnct = sqlite3VdbeAddOp4( _
            pVdbe, OP_OpenEphemeral, distinctContext.tabTnct, 0, 0, _
            CPtr(Const ZString Ptr, pDistinctKey), P4_KEYINFO)
        sqlite3VdbeChangeP5(pVdbe, BTREE_UNORDERED)
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        pDistinct = @distinctContext
    End If

    If pParse->nTab < 0 OrElse pParse->nTab >= &H7FFFFFFF Then _
        Return SQLITE_TOOBIG
    pAggregateInfo->sortingIdxPTab = pParse->nTab
    pParse->nTab += 1
    Dim sorterRecordRegister As SQLITE_C_INT = sqlite3GetTempReg(pParse)
    Dim previousGroupRegister As SQLITE_C_INT = _
        sqlite3GetTempRange(pParse, pGroupBy->nExpr)
    Dim currentGroupRegister As SQLITE_C_INT = _
        sqlite3GetTempRange(pParse, pGroupBy->nExpr)
    Dim groupHasRowsRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
    Dim outputReturnRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
    Dim outputSubroutineLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
    If sorterRecordRegister = 0 OrElse previousGroupRegister = 0 OrElse _
       currentGroupRegister = 0 OrElse groupHasRowsRegister = 0 OrElse _
       outputReturnRegister = 0 OrElse outputSubroutineLabel = 0 Then _
        Return SQLITE_NOMEM

    If pParse->nMem < 0 OrElse _
       nColumn > SQLITE_MAX_VDBE_OP - pParse->nMem Then Return SQLITE_TOOBIG
    Dim firstResultRegister As SQLITE_C_INT = pParse->nMem + 1
    pParse->nMem += nColumn

    Dim pseudoOpenAddress As SQLITE_C_INT = sqlite3VdbeAddOp3( _
        pVdbe, OP_OpenPseudo, pAggregateInfo->sortingIdxPTab, _
        sorterRecordRegister, pAggregateInfo->nSortingColumn)
    sqlite3VdbeAddInt64(pVdbe, groupHasRowsRegister, 0)
    If pParse->db->mallocFailed <> 0 OrElse pseudoOpenAddress < 0 Then _
        Return SQLITE_NOMEM

    Dim pWhereInfo As SqliteWhereInfo Ptr = 0
    Dim noGroupRowLabel As SQLITE_C_INT = 0
    Dim pAggregateDistinctList As SqliteExprList Ptr = 0
    Dim aggregateDistinctFlags As UShort = 0
    Dim aggregateDistinctType As SQLITE_C_INT = WHERE_DISTINCT_NOOP
    Dim groupByNeedsSort As SQLITE_C_INT = 1
    Dim groupByIsSorted As SQLITE_C_INT = 0
    Dim stopGroupsLabel As SQLITE_C_INT = 0
    If pSourceList <> 0 AndAlso pSourceList->nSrc > 0 Then
        If pAggregateInfo->nFunc = 1 AndAlso pAggregateInfo->aFunc <> 0 Then
            Dim pDistinctFunction As SqliteAggInfoFunction Ptr = _
                @pAggregateInfo->aFunc[0]
            If pDistinctFunction->iDistinct >= 0 AndAlso _
               pDistinctFunction->pFExpr <> 0 Then
                Dim pArgumentList As SqliteExprList Ptr = _
                    CPtr(SqliteExprList Ptr, _
                        pDistinctFunction->pFExpr->x.pList)
                If pArgumentList = 0 OrElse pArgumentList->nExpr <> 1 Then _
                    Return SQLITE_CORRUPT
                Dim pArgumentItem As SqliteExprListItem Ptr = _
                    sqlite3ExprListItemAt(pArgumentList, 0)
                If pArgumentItem = 0 OrElse pArgumentItem->pExpr = 0 Then _
                    Return SQLITE_CORRUPT
                Dim pArgumentCopy As SqliteExpr Ptr = sqlite3ExprDup( _
                    pParse->db, CPtr(SqliteExpr Ptr, pArgumentItem->pExpr), 0)
                pAggregateDistinctList = sqlite3ExprListDup( _
                    pParse->db, pGroupBy, 0)
                If pArgumentCopy = 0 OrElse pAggregateDistinctList = 0 Then
                    If pArgumentCopy <> 0 Then _
                        sqlite3ExprDelete(pParse->db, pArgumentCopy)
                    If pAggregateDistinctList <> 0 Then _
                        sqlite3ExprListDelete(pParse->db, pAggregateDistinctList)
                    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
                    Return SQLITE_ERROR
                End If
                pAggregateDistinctList = sqlite3ExprListAppend( _
                    pParse, pAggregateDistinctList, pArgumentCopy)
                If pAggregateDistinctList = 0 Then
                    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
                    Return SQLITE_ERROR
                End If
                aggregateDistinctFlags = _
                    WHERE_GROUPBY Or WHERE_WANT_DISTINCT Or WHERE_AGG_DISTINCT
            End If
        End If
        Dim whereFlags As UShort = WHERE_GROUPBY Or aggregateDistinctFlags
        If orderByGroup <> 0 Then whereFlags Or= WHERE_SORTBYGROUP
        pWhereInfo = sqlite3WhereBegin( _
            pParse, pSourceList, CPtr(SqliteExpr Ptr, pSelect->pWhere), _
            pGroupBy, pAggregateDistinctList, pSelect, whereFlags, 0)
        If pWhereInfo = 0 Then
            If pAggregateDistinctList <> 0 Then _
                sqlite3ExprListDelete(pParse->db, pAggregateDistinctList)
            If skipSourceScanLabel <> 0 Then _
                sqlite3VdbeResolveLabel(pVdbe, skipSourceScanLabel)
            sqlite3ReleaseTempReg(pParse, recordRegister)
            sqlite3ReleaseTempRange( _
                pParse, registerBase, pAggregateInfo->nSortingColumn)
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            Return SQLITE_ERROR
        End If
        groupByNeedsSort = CInt( _
            sqlite3WhereIsOrdered(pWhereInfo) <> pGroupBy->nExpr)
        If orderByGroup <> 0 Then _
            groupByIsSorted = sqlite3WhereIsSorted(pWhereInfo)
        If groupByNeedsSort <> 0 Then
            sqlite3VdbeExplainText( _
                pParse, 0, StrPtr("USE TEMP B-TREE FOR GROUP BY"))
        Else
            pAggregateInfo->useSortingIdx = 0
        End If
        Dim needOuterOrderBy As SQLITE_C_INT = CInt( _
            pOrderBy <> 0 AndAlso _
            (orderByGroup = 0 OrElse groupByNeedsSort = 0 AndAlso _
             groupByIsSorted = 0))
        If needOuterOrderBy = 0 AndAlso pSort <> 0 Then
            If sqlite3VdbeChangeToNoop(pVdbe, sortOpenAddress) = 0 Then _
                Return SQLITE_CORRUPT
            pSort = 0
        End If
        If pAggregateDistinctList <> 0 Then
            aggregateDistinctType = sqlite3WhereIsDistinct(pWhereInfo)
            ' The WHERE planner consumes this temporary list while choosing
            ' loops and retains only the resulting distinct execution mode.
            sqlite3ExprListDelete(pParse->db, pAggregateDistinctList)
            pAggregateDistinctList = 0
        End If
    ElseIf pSelect->pWhere <> 0 Then
        ' A grouped SELECT without FROM forms one group from its implicit row.
        ' WHERE can remove that row before its key is placed in the sorter.
        Dim whereRegister As SQLITE_C_INT = sqlite3SelectNextRegister(pParse)
        noGroupRowLabel = sqlite3VdbeMakeLabel(pParse)
        If whereRegister = 0 OrElse noGroupRowLabel = 0 Then
            If skipSourceScanLabel <> 0 Then _
                sqlite3VdbeResolveLabel(pVdbe, skipSourceScanLabel)
            sqlite3ReleaseTempReg(pParse, recordRegister)
            sqlite3ReleaseTempRange( _
                pParse, registerBase, pAggregateInfo->nSortingColumn)
            Return SQLITE_NOMEM
        End If
        Dim whereCode As SQLITE_C_INT = sqlite3SelectCompileExpr( _
            pParse, CPtr(SqliteExpr Ptr, pSelect->pWhere), whereRegister, 0)
        If whereCode <> SQLITE_OK Then
            sqlite3VdbeResolveLabel(pVdbe, noGroupRowLabel)
            If skipSourceScanLabel <> 0 Then _
                sqlite3VdbeResolveLabel(pVdbe, skipSourceScanLabel)
            sqlite3ReleaseTempReg(pParse, recordRegister)
            sqlite3ReleaseTempRange( _
                pParse, registerBase, pAggregateInfo->nSortingColumn)
            Return whereCode
        End If
        sqlite3VdbeAddOp3( _
            pVdbe, OP_IfNot, whereRegister, noGroupRowLabel, 1)
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    End If

    If groupByNeedsSort <> 0 Then
        pAggregateInfo->useSortingIdx = 0
        For groupIndex As SQLITE_C_INT = 0 To pGroupBy->nExpr - 1
            Dim pGroupItem As SqliteExprListItem Ptr = _
                sqlite3ExprListItemAt(pGroupBy, groupIndex)
            If pGroupItem = 0 OrElse pGroupItem->pExpr = 0 Then
                If pWhereInfo <> 0 Then sqlite3WhereEnd(pWhereInfo)
                If noGroupRowLabel <> 0 Then _
                    sqlite3VdbeResolveLabel(pVdbe, noGroupRowLabel)
                If skipSourceScanLabel <> 0 Then _
                    sqlite3VdbeResolveLabel(pVdbe, skipSourceScanLabel)
                sqlite3ReleaseTempReg(pParse, recordRegister)
                sqlite3ReleaseTempRange( _
                    pParse, registerBase, pAggregateInfo->nSortingColumn)
                Return SQLITE_CORRUPT
            End If
            sqlite3ExprCode( _
                pParse, CPtr(SqliteExpr Ptr, pGroupItem->pExpr), _
                registerBase + groupIndex)
        Next

        pAggregateInfo->directMode = 1
        For columnIndex As SQLITE_C_INT = 0 To pAggregateInfo->nColumn - 1
            Dim pColumn As SqliteAggInfoColumn Ptr = _
                @pAggregateInfo->aCol[columnIndex]
            If pColumn->iSorterColumn >= pGroupBy->nExpr Then
                If pColumn->iSorterColumn >= pAggregateInfo->nSortingColumn OrElse _
                   pColumn->pCExpr = 0 Then
                    pAggregateInfo->directMode = 0
                    If pWhereInfo <> 0 Then sqlite3WhereEnd(pWhereInfo)
                    If noGroupRowLabel <> 0 Then _
                        sqlite3VdbeResolveLabel(pVdbe, noGroupRowLabel)
                    If skipSourceScanLabel <> 0 Then _
                        sqlite3VdbeResolveLabel(pVdbe, skipSourceScanLabel)
                    sqlite3ReleaseTempReg(pParse, recordRegister)
                    sqlite3ReleaseTempRange( _
                        pParse, registerBase, pAggregateInfo->nSortingColumn)
                    Return SQLITE_CORRUPT
                End If
                sqlite3ExprCode( _
                    pParse, CPtr(SqliteExpr Ptr, pColumn->pCExpr), _
                    registerBase + pColumn->iSorterColumn)
            End If
        Next
        pAggregateInfo->directMode = 0
        sqlite3VdbeAddOp3( _
            pVdbe, OP_MakeRecord, registerBase, _
            pAggregateInfo->nSortingColumn, recordRegister)
        sqlite3VdbeAddOp2( _
            pVdbe, OP_SorterInsert, pAggregateInfo->sortingIdx, recordRegister)
    Else
        pAggregateInfo->useSortingIdx = 0
        Dim groupRowCode As SQLITE_C_INT = sqlite3SelectEmitOrderedGroupInputRow( _
            pParse, pSelect, pAggregateInfo, pGroupBy, pResultList, pSortKey, _
            previousGroupRegister, currentGroupRegister, groupHasRowsRegister, _
            outputReturnRegister, outputSubroutineLabel, limitRegister, pSort, _
            aggregateDistinctType, aggregateDistinctFlags, _
            aggregateDistinctInitialOpenAddress, @stopGroupsLabel)
        If groupRowCode <> SQLITE_OK Then
            If pWhereInfo <> 0 Then sqlite3WhereEnd(pWhereInfo)
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            Return groupRowCode
        End If
        If sqlite3VdbeChangeToNoop(pVdbe, groupSortOpenAddress) = 0 OrElse _
           sqlite3VdbeChangeToNoop(pVdbe, pseudoOpenAddress) = 0 Then
            If pWhereInfo <> 0 Then sqlite3WhereEnd(pWhereInfo)
            Return SQLITE_CORRUPT
        End If
    End If
    If pWhereInfo <> 0 Then sqlite3WhereEnd(pWhereInfo)
    If noGroupRowLabel <> 0 Then _
        sqlite3VdbeResolveLabel(pVdbe, noGroupRowLabel)
    sqlite3ReleaseTempReg(pParse, recordRegister)
    sqlite3ReleaseTempRange( _
        pParse, registerBase, pAggregateInfo->nSortingColumn)
    If skipSourceScanLabel <> 0 Then _
        sqlite3VdbeResolveLabel(pVdbe, skipSourceScanLabel)
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR

    If groupByNeedsSort <> 0 Then
        pAggregateInfo->useSortingIdx = 1
        Dim endSortLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
        If endSortLabel = 0 Then Return SQLITE_NOMEM
        sqlite3VdbeAddOp2( _
            pVdbe, OP_SorterSort, pAggregateInfo->sortingIdx, endSortLabel)

        Dim loopTop As SQLITE_C_INT = sqlite3VdbeCurrentAddr(pVdbe)
        sqlite3VdbeAddOp3( _
            pVdbe, OP_SorterData, pAggregateInfo->sortingIdx, _
            sorterRecordRegister, pAggregateInfo->sortingIdxPTab)
        For groupIndex As SQLITE_C_INT = 0 To pGroupBy->nExpr - 1
            Dim pGroupItem As SqliteExprListItem Ptr = _
                sqlite3ExprListItemAt(pGroupBy, groupIndex)
            If pGroupItem = 0 OrElse pGroupItem->pExpr = 0 Then _
                Return SQLITE_CORRUPT
            sqlite3VdbeAddOp3( _
                pVdbe, OP_Column, pAggregateInfo->sortingIdxPTab, groupIndex, _
                currentGroupRegister + groupIndex)

            ' Reuse the sorted group key for a result expression named by its
            ' GROUP BY ordinal. Re-evaluating volatile expressions here changes
            ' the value returned for the group.
            Dim resultColumn As SQLITE_C_INT = pGroupItem->u.x.iOrderByCol
            If resultColumn > 0 Then
                If resultColumn > pResultList->nExpr Then Return SQLITE_CORRUPT
                Dim pResultItem As SqliteExprListItem Ptr = _
                    sqlite3ExprListItemAt(pResultList, resultColumn - 1)
                If pResultItem = 0 OrElse pResultItem->pExpr = 0 Then _
                    Return SQLITE_CORRUPT
                Dim pBase As SqliteExpr Ptr = sqlite3ExprSkipCollateAndLikely( _
                    CPtr(SqliteExpr Ptr, pResultItem->pExpr))
                While pBase <> 0 AndAlso pBase->op = TK_IF_NULL_ROW
                    If pBase->pLeft = 0 Then Exit While
                    pBase = sqlite3ExprSkipCollateAndLikely( _
                        CPtr(SqliteExpr Ptr, pBase->pLeft))
                Wend
                If pBase <> 0 AndAlso pBase->op <> TK_AGG_COLUMN AndAlso _
                   pBase->op <> TK_REGISTER Then
                    sqlite3ExprToRegister( _
                        CPtr(SqliteExpr Ptr, pResultItem->pExpr), _
                        previousGroupRegister + groupIndex)
                End If
            End If
        Next

        Dim initializeGroupLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
        If initializeGroupLabel = 0 Then Return SQLITE_NOMEM
        sqlite3VdbeAddOp2( _
            pVdbe, OP_IfNot, groupHasRowsRegister, initializeGroupLabel)
        Dim pCompareKey As sqlite3VdbeKeyInfoPrefix Ptr = _
            sqlite3KeyInfoRef(pSortKey)
        If pCompareKey = 0 Then
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            Return SQLITE_ERROR
        End If
        sqlite3VdbeAddOp4( _
            pVdbe, OP_Compare, previousGroupRegister, currentGroupRegister, _
            pGroupBy->nExpr, CPtr(Const ZString Ptr, pCompareKey), P4_KEYINFO)
        Dim groupJumpAddress As SQLITE_C_INT = _
            sqlite3VdbeAddOp3(pVdbe, OP_Jump, 0, 0, 0)
        Dim groupChangeAddress As SQLITE_C_INT = sqlite3VdbeCurrentAddr(pVdbe)

        sqlite3SelectAggregateFinalize(pParse, pAggregateInfo)
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        If pParse->nErr <> 0 Then Return SQLITE_ERROR
        sqlite3VdbeAddOp2( _
            pVdbe, OP_Gosub, outputReturnRegister, outputSubroutineLabel)
        If limitRegister <> 0 AndAlso pSort = 0 Then
            stopGroupsLabel = sqlite3VdbeMakeLabel(pParse)
            If stopGroupsLabel = 0 Then Return SQLITE_NOMEM
            sqlite3VdbeAddOp2(pVdbe, OP_IfNot, limitRegister, stopGroupsLabel)
        End If
        sqlite3SelectAggregateReset(pParse, pAggregateInfo)
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        If pParse->nErr <> 0 Then Return SQLITE_ERROR
        sqlite3VdbeAddInt64(pVdbe, groupHasRowsRegister, 0)

        sqlite3VdbeResolveLabel(pVdbe, initializeGroupLabel)
        For groupIndex As SQLITE_C_INT = 0 To pGroupBy->nExpr - 1
            sqlite3VdbeAddOp2( _
                pVdbe, OP_Copy, currentGroupRegister + groupIndex, _
                previousGroupRegister + groupIndex)
        Next
        Dim aggregateUpdateAddress As SQLITE_C_INT = sqlite3VdbeCurrentAddr(pVdbe)
        sqlite3VdbeChangeP1(pVdbe, groupJumpAddress, groupChangeAddress)
        sqlite3VdbeChangeP2(pVdbe, groupJumpAddress, aggregateUpdateAddress)
        sqlite3VdbeChangeP3(pVdbe, groupJumpAddress, groupChangeAddress)

        sqlite3SelectAggregateUpdate( _
            pParse, groupHasRowsRegister, pAggregateInfo, aggregateDistinctType)
        If aggregateDistinctFlags <> 0 AndAlso _
           aggregateDistinctType <> WHERE_DISTINCT_NOOP Then
            Dim pDistinctFunction As SqliteAggInfoFunction Ptr = _
                @pAggregateInfo->aFunc[0]
            Dim fixCode As SQLITE_C_INT = sqlite3SelectFixDistinctOpenEph( _
                pParse, aggregateDistinctType, pDistinctFunction->iDistinct, _
                pDistinctFunction->iDistAddr)
            If fixCode <> SQLITE_OK Then Return fixCode
            If aggregateDistinctInitialOpenAddress >= 0 AndAlso _
               aggregateDistinctInitialOpenAddress <> _
                   pDistinctFunction->iDistAddr Then
                fixCode = sqlite3SelectFixDistinctOpenEph( _
                    pParse, aggregateDistinctType, pDistinctFunction->iDistinct, _
                    aggregateDistinctInitialOpenAddress)
                If fixCode <> SQLITE_OK Then Return fixCode
            End If
        End If
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        If pParse->nErr <> 0 Then Return SQLITE_ERROR
        sqlite3VdbeAddInt64(pVdbe, groupHasRowsRegister, 1)
        sqlite3VdbeAddOp2( _
            pVdbe, OP_SorterNext, pAggregateInfo->sortingIdx, loopTop)
        sqlite3VdbeAddOp3(pVdbe, OP_Goto, 0, endSortLabel, 0)
        If stopGroupsLabel <> 0 Then
            sqlite3VdbeResolveLabel(pVdbe, stopGroupsLabel)
            sqlite3VdbeAddInt64(pVdbe, groupHasRowsRegister, 0)
            sqlite3VdbeAddOp3(pVdbe, OP_Goto, 0, endSortLabel, 0)
        End If
        sqlite3VdbeResolveLabel(pVdbe, endSortLabel)
    ElseIf stopGroupsLabel <> 0 Then
        ' LIMIT exits into this block; normal loop completion must skip it
        ' so the final group is emitted below.
        Dim afterStopGroupsLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
        If afterStopGroupsLabel = 0 Then Return SQLITE_NOMEM
        sqlite3VdbeAddOp3(pVdbe, OP_Goto, 0, afterStopGroupsLabel, 0)
        sqlite3VdbeResolveLabel(pVdbe, stopGroupsLabel)
        sqlite3VdbeAddInt64(pVdbe, groupHasRowsRegister, 0)
        sqlite3VdbeResolveLabel(pVdbe, afterStopGroupsLabel)
    End If

    Dim skipFinalGroupLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
    Dim skipOutputSubroutineLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
    If skipFinalGroupLabel = 0 OrElse skipOutputSubroutineLabel = 0 Then _
        Return SQLITE_NOMEM
    sqlite3VdbeAddOp2( _
        pVdbe, OP_IfNot, groupHasRowsRegister, skipFinalGroupLabel)
    sqlite3SelectAggregateFinalize(pParse, pAggregateInfo)
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR
    sqlite3VdbeAddOp2( _
        pVdbe, OP_Gosub, outputReturnRegister, outputSubroutineLabel)
    sqlite3VdbeResolveLabel(pVdbe, skipFinalGroupLabel)
    sqlite3VdbeAddOp3(pVdbe, OP_Goto, 0, skipOutputSubroutineLabel, 0)

    sqlite3VdbeResolveLabel(pVdbe, outputSubroutineLabel)
    Dim outputCode As SQLITE_C_INT
    If pSort <> 0 OrElse pDistinct <> 0 Then
        outputCode = sqlite3SelectEmitGroupedAggregateResultRow( _
            pParse, pSelect, pResultList, _
            CPtr(SqliteExpr Ptr, pSelect->pHaving), pSort, pDistinct, _
            pDestination, limitRegister, offsetRegister, stopGroupsLabel)
    Else
        outputCode = sqlite3SelectEmitAggregateResultRow( _
            pParse, pSelect, pResultList, pDestination, _
            CPtr(SqliteExpr Ptr, pSelect->pHaving), _
            offsetRegister, limitRegister, nColumn, firstResultRegister)
    End If
    If outputCode <> SQLITE_OK Then Return outputCode
    sqlite3VdbeAddOp1(pVdbe, OP_Return, outputReturnRegister)
    sqlite3VdbeResolveLabel(pVdbe, skipOutputSubroutineLabel)
    If groupByNeedsSort <> 0 Then
        sqlite3VdbeAddOp1(pVdbe, OP_Close, pAggregateInfo->sortingIdxPTab)
        sqlite3VdbeAddOp1(pVdbe, OP_Close, pAggregateInfo->sortingIdx)
    End If
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR
    If pSort <> 0 Then
        sqlite3SelectGenerateSortTail(pParse, pSelect, pSort, nColumn, pDestination)
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        If pParse->nErr <> 0 Then Return SQLITE_ERROR
    End If
    sqlite3ReleaseTempReg(pParse, sorterRecordRegister)
    sqlite3ReleaseTempRange(pParse, previousGroupRegister, pGroupBy->nExpr)
    sqlite3ReleaseTempRange(pParse, currentGroupRegister, pGroupBy->nExpr)
    Return SQLITE_OK
End Function

Private Function sqlite3SelectOpenEphemeralDestination( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pDestination As SqliteSelectDest Ptr _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->db = 0 OrElse pSelect = 0 OrElse _
       pDestination = 0 Then Return SQLITE_MISUSE
    If pDestination->eDest <> SRT_EphemTab Then Return SQLITE_OK
    If pDestination->iSDParm < 0 OrElse pSelect->pEList = 0 OrElse _
       pSelect->pEList->nExpr <= 0 OrElse _
       pSelect->pEList->nAlloc < pSelect->pEList->nExpr Then _
        Return SQLITE_CORRUPT

    Dim pVdbe As SqliteVdbe Ptr = _
        CPtr(SqliteVdbe Ptr, sqlite3GetVdbe(pParse))
    If pVdbe = 0 Then Return SQLITE_NOMEM
    sqlite3VdbeAddOp2( _
        pVdbe, OP_OpenEphemeral, pDestination->iSDParm, _
        pSelect->pEList->nExpr)
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    pDestination->eDest = SRT_Table
    Return SQLITE_OK
End Function

Private Sub sqlite3SelectUnsetJoinExpr( _
    ByVal pExpression As SqliteExpr Ptr, _
    ByVal cursorNumber As SQLITE_C_INT, _
    ByVal nullable As SQLITE_C_INT _
)
    While pExpression <> 0
        If cursorNumber < 0 OrElse _
           ((pExpression->flags And EP_OuterON) <> 0 AndAlso _
            pExpression->w.iJoin = cursorNumber) Then
            pExpression->flags = pExpression->flags And _
                Not CUInt(EP_OuterON Or EP_InnerON)
            If cursorNumber >= 0 Then pExpression->flags Or= EP_InnerON
        End If

        If pExpression->op = TK_COLUMN AndAlso _
           pExpression->iTable = cursorNumber AndAlso nullable = 0 Then
            pExpression->flags = pExpression->flags And Not CUInt(EP_CanBeNull)
        End If

        If pExpression->op = TK_FUNCTION Then
            Dim pArguments As SqliteExprList Ptr = _
                CPtr(SqliteExprList Ptr, pExpression->x.pList)
            If pArguments <> 0 Then
                For argumentIndex As SQLITE_C_INT = 0 To pArguments->nExpr - 1
                    sqlite3SelectUnsetJoinExpr( _
                        CPtr(SqliteExpr Ptr, pArguments->a(argumentIndex).pExpr), _
                        cursorNumber, nullable)
                Next
            End If
        End If

        sqlite3SelectUnsetJoinExpr( _
            CPtr(SqliteExpr Ptr, pExpression->pLeft), cursorNumber, nullable)
        pExpression = CPtr(SqliteExpr Ptr, pExpression->pRight)
    Wend
End Sub

Private Function sqlite3SelectCompileFromClause( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pDestination As SqliteSelectDest Ptr _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->db = 0 OrElse pSelect = 0 OrElse _
       pDestination = 0 Then _
        Return SQLITE_MISUSE

    sqlite3SelectPrep(pParse, pSelect, 0)
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR

    ' A FROM term that contributes no column still requires an SQLITE_READ
    ' authorization. The empty column name preserves SQLite's callback contract
    ' for queries such as SELECT count(*) FROM table.
    Dim pAuthSourceList As SqliteSrcList Ptr = _
        CPtr(SqliteSrcList Ptr, pSelect->pSrc)
    If pAuthSourceList <> 0 Then
        If pAuthSourceList->nSrc < 0 OrElse _
           pAuthSourceList->nAlloc < pAuthSourceList->nSrc Then _
            Return SQLITE_CORRUPT
        For sourceIndex As SQLITE_C_INT = 0 To pAuthSourceList->nSrc - 1
            Dim pAuthItem As SqliteSrcItem Ptr = _
                @pAuthSourceList->a(sourceIndex)
            If pAuthItem->colUsed = 0 AndAlso pAuthItem->zName <> 0 Then
                Dim zAuthDatabase As Const ZString Ptr = 0
                If (pAuthItem->fg.flags And SRCITEM_FIXED_SCHEMA) <> 0 Then
                    Dim databaseIndex As SQLITE_C_INT = sqlite3SchemaToIndex( _
                        pParse->db, pAuthItem->u4.pSchema)
                    If databaseIndex < 0 OrElse _
                       databaseIndex >= pParse->db->nDb Then _
                        Return SQLITE_CORRUPT
                    zAuthDatabase = pParse->db->aDb(databaseIndex).zDbSName
                ElseIf (pAuthItem->fg.flags And SRCITEM_IS_SUBQUERY) = 0 Then
                    zAuthDatabase = pAuthItem->u4.zDatabase
                End If
                Dim authResult As SQLITE_C_INT = sqlite3AuthCheck( _
                    pParse, SQLITE_READ, pAuthItem->zName, StrPtr(""), _
                    zAuthDatabase)
                If authResult = SQLITE_DENY OrElse pParse->nErr <> 0 Then _
                    Return SQLITE_ERROR
            End If
        Next
    End If

    Dim pInitialResultList As SqliteExprList Ptr = _
        CPtr(SqliteExprList Ptr, pSelect->pEList)
    If pInitialResultList = 0 OrElse pInitialResultList->nExpr <= 0 OrElse _
       pInitialResultList->nAlloc < pInitialResultList->nExpr Then _
        Return SQLITE_CORRUPT
    If pDestination->eDest = SRT_Output Then _
        sqlite3GenerateColumnNames(pParse, pSelect)
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR

#ifndef SQLITE_OMIT_SUBQUERY
    ' Flatten eligible FROM subqueries before materializing the remaining ones.
    Dim flattenAggregate As SQLITE_C_INT = _
        CInt((pSelect->selFlags And SF_Aggregate) <> 0)
    Dim flattenIndex As SQLITE_C_INT = 0
    ' Flattening operates on a simple SELECT term. Compound SELECTs are
    ' handled one term at a time by the compound code generator.
    While pSelect->pPrior = 0 AndAlso pSelect->pSrc <> 0 AndAlso _
          flattenIndex < pSelect->pSrc->nSrc
        Dim pFlattenItem As SqliteSrcItem Ptr = _
            @pSelect->pSrc->a(flattenIndex)
        If (pFlattenItem->fg.jointype And (JT_LEFT Or JT_LTORJ)) <> 0 AndAlso _
           sqlite3ExprImpliesNonNullRow( _
               CPtr(SqliteExpr Ptr, pSelect->pWhere), pFlattenItem->iCursor, _
               CInt((pFlattenItem->fg.jointype And JT_LTORJ) <> 0)) <> 0 AndAlso _
           (pParse->db->dbOptFlags And SQLITE_SimplifyJoin) = 0 Then
            If (pFlattenItem->fg.jointype And JT_LEFT) <> 0 Then
                If (pFlattenItem->fg.jointype And JT_RIGHT) <> 0 Then
                    pFlattenItem->fg.jointype = pFlattenItem->fg.jointype And _
                        Not CUInt(JT_LEFT)
                Else
                    pFlattenItem->fg.jointype = pFlattenItem->fg.jointype And _
                        Not CUInt(JT_LEFT Or JT_OUTER)
                    sqlite3SelectUnsetJoinExpr( _
                        CPtr(SqliteExpr Ptr, pSelect->pWhere), _
                        pFlattenItem->iCursor, 0)
                End If
            End If

            If (pFlattenItem->fg.jointype And JT_LTORJ) <> 0 Then
                For rightJoinIndex As SQLITE_C_INT = flattenIndex + 1 To _
                    pSelect->pSrc->nSrc - 1
                    Dim pRightJoin As SqliteSrcItem Ptr = _
                        @pSelect->pSrc->a(rightJoinIndex)
                    If (pRightJoin->fg.jointype And JT_RIGHT) <> 0 Then
                        If (pRightJoin->fg.jointype And JT_LEFT) <> 0 Then
                            pRightJoin->fg.jointype = _
                                pRightJoin->fg.jointype And Not CUInt(JT_RIGHT)
                        Else
                            pRightJoin->fg.jointype = _
                                pRightJoin->fg.jointype And _
                                Not CUInt(JT_RIGHT Or JT_OUTER)
                            sqlite3SelectUnsetJoinExpr( _
                                CPtr(SqliteExpr Ptr, pSelect->pWhere), _
                                pRightJoin->iCursor, 1)
                        End If
                    End If
                Next

                For rightJoinIndex As SQLITE_C_INT = _
                    pSelect->pSrc->nSrc - 1 To 0 Step -1
                    Dim pRightJoin As SqliteSrcItem Ptr = _
                        @pSelect->pSrc->a(rightJoinIndex)
                    pRightJoin->fg.jointype = pRightJoin->fg.jointype And _
                        Not CUInt(JT_LTORJ)
                    If (pRightJoin->fg.jointype And JT_RIGHT) <> 0 Then Exit For
                Next
            End If
        End If

        If (pFlattenItem->fg.flags And SRCITEM_IS_SUBQUERY) <> 0 Then
            If pFlattenItem->u4.pSubq = 0 Then Return SQLITE_CORRUPT
            Dim pFlattenSubquery As SqliteSelect Ptr = _
                pFlattenItem->u4.pSubq->pSelect
            Dim pFlattenTable As SqliteTable Ptr = pFlattenItem->pSTab
            If pFlattenSubquery = 0 OrElse pFlattenTable = 0 OrElse _
               pFlattenSubquery->pEList = 0 Then Return SQLITE_CORRUPT
            If pFlattenTable->nCol <> pFlattenSubquery->pEList->nExpr Then
                sqlite3ErrorMsg(pParse, _
                    StrPtr("expected %d columns for '%s' but got %d"), _
                    pFlattenTable->nCol, pFlattenTable->zName, _
                    pFlattenSubquery->pEList->nExpr)
                Return SQLITE_ERROR
            End If
            Dim canFlatten As SQLITE_C_INT = 1
            Dim canOmitSubqueryOrderBy As SQLITE_C_INT = 1
            If (pFlattenItem->fg.flags And SRCITEM_IS_CTE) <> 0 Then
                Dim pCteUse As SqliteCteUse Ptr = pFlattenItem->u2.pCteUse
                If pCteUse = 0 Then Return SQLITE_CORRUPT
                If pCteUse->eM10d = M10D_YES Then
                    canFlatten = 0
                    canOmitSubqueryOrderBy = 0
                End If
            End If
            If (pFlattenSubquery->selFlags And SF_Aggregate) <> 0 Then
                canFlatten = 0
                canOmitSubqueryOrderBy = 0
            End If
            If canOmitSubqueryOrderBy <> 0 AndAlso _
               pFlattenSubquery->pOrderBy <> 0 AndAlso _
               (pSelect->pOrderBy <> 0 OrElse pSelect->pSrc->nSrc > 1) AndAlso _
               pFlattenSubquery->pLimit = 0 AndAlso _
               (pFlattenSubquery->selFlags And _
                (SF_OrderByReqd Or SF_Recursive)) = 0 AndAlso _
               (pSelect->selFlags And SF_OrderByReqd) = 0 AndAlso _
               (pParse->db->dbOptFlags And SQLITE_OMIT_ORDER_BY_MASK) = 0 Then
                Dim pOmittedOrderBy As SqliteExprList Ptr = _
                    pFlattenSubquery->pOrderBy
                ' AddCleanup may invoke the destructor immediately on OOM.
                ' Drop the Select's ownership before handing the list over.
                pFlattenSubquery->pOrderBy = 0
                If sqlite3ParserAddCleanup( _
                    pParse, @sqlite3ExprListDeleteGeneric, _
                    CPtr(Any Ptr, pOmittedOrderBy)) = 0 Then _
                    Return SQLITE_NOMEM
            End If
            If pFlattenSubquery->pLimit <> 0 AndAlso _
               (pSelect->pLimit <> 0 OrElse _
                pFlattenSubquery->pLimit->pRight <> 0 OrElse _
                (pSelect->selFlags And SF_Compound) <> 0 OrElse _
                pSelect->pSrc->nSrc > 1 OrElse flattenAggregate <> 0 OrElse _
                pSelect->pWhere <> 0 OrElse _
                (pSelect->selFlags And SF_Distinct) <> 0) Then _
                canFlatten = 0
            If pFlattenSubquery->pOrderBy <> 0 AndAlso flattenIndex = 0 AndAlso _
               (pSelect->selFlags And SF_ComplexResult) <> 0 AndAlso _
               (pSelect->pSrc->nSrc = 1 OrElse _
                (pSelect->pSrc->a(1).fg.jointype And _
                 (JT_OUTER Or JT_CROSS)) <> 0) Then canFlatten = 0

            If canFlatten <> 0 AndAlso sqlite3SelectTryFlatten( _
                pParse, pSelect, flattenIndex, flattenAggregate) <> 0 Then
                If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
                If pParse->nErr <> 0 Then Return SQLITE_ERROR
                flattenIndex = -1
            End If
        End If
        flattenIndex += 1
    Wend
#endif

    If pSelect->pWhere <> 0 AndAlso pSelect->pWhere->op = TK_AND AndAlso _
       (pParse->db->dbOptFlags And SQLITE_PropagateConst) = 0 Then
        propagateConstants(pParse, pSelect)
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        If pParse->nErr <> 0 Then Return SQLITE_ERROR
    End If

#ifndef SQLITE_OMIT_SUBQUERY
    ' Replace unreferenced FROM-subquery expressions with NULL before generating
    ' their bytecode, avoiding work in unused result columns.
    If pSelect->pPrior = 0 AndAlso _
       (pParse->db->dbOptFlags And SQLITE_NullUnusedCols) = 0 AndAlso _
       pSelect->pSrc <> 0 Then
        If pSelect->pSrc->nSrc < 0 OrElse _
           pSelect->pSrc->nAlloc < pSelect->pSrc->nSrc Then Return SQLITE_CORRUPT
        For sourceIndex As SQLITE_C_INT = 0 To pSelect->pSrc->nSrc - 1
            Dim pUnusedColumnItem As SqliteSrcItem Ptr = _
                @pSelect->pSrc->a(sourceIndex)
            If (pUnusedColumnItem->fg.flags And SRCITEM_IS_SUBQUERY) <> 0 Then
                If pUnusedColumnItem->pSTab = 0 OrElse _
                   pUnusedColumnItem->u4.pSubq = 0 Then Return SQLITE_CORRUPT
                recomputeColumnsUsed(pSelect, pUnusedColumnItem)
                disableUnusedSubqueryResultColumns(pUnusedColumnItem)
                If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            End If
        Next
    End If
#endif

#ifndef SQLITE_OMIT_WINDOWFUNC
    If pSelect->pWin <> 0 Then
        Dim windowRewriteResult As SQLITE_C_INT = _
            sqlite3WindowRewrite(pParse, pSelect)
        If windowRewriteResult <> SQLITE_OK Then Return windowRewriteResult
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        If pParse->nErr <> 0 Then Return SQLITE_ERROR
    End If
#endif

    ' Flattening a compound FROM-subquery can turn this SELECT into a
    ' compound query after sqlite3Select() chose the FROM-clause path.
    If pSelect->pPrior <> 0 Then _
        Return sqlite3SelectCompileCompound( _
            pParse, pSelect, pDestination)

    Dim destinationOpenCode As SQLITE_C_INT = _
        sqlite3SelectOpenEphemeralDestination( _
            pParse, pSelect, pDestination)
    If destinationOpenCode <> SQLITE_OK Then Return destinationOpenCode

    Dim pSourceList As SqliteSrcList Ptr = _
        CPtr(SqliteSrcList Ptr, pSelect->pSrc)
    Dim pResultList As SqliteExprList Ptr = _
        CPtr(SqliteExprList Ptr, pSelect->pEList)
    Dim pOrderBy As SqliteExprList Ptr = _
        CPtr(SqliteExprList Ptr, pSelect->pOrderBy)
    Dim isAggregate As SQLITE_C_INT = _
        CInt((pSelect->selFlags And SF_Aggregate) <> 0)
    If pSourceList = 0 OrElse pSourceList->nSrc <= 0 OrElse _
       pSourceList->nAlloc < pSourceList->nSrc OrElse _
       pResultList = 0 OrElse pResultList->nExpr <= 0 OrElse _
       pResultList->nAlloc < pResultList->nExpr Then Return SQLITE_CORRUPT

    If pSelect->pPrior <> 0 Then Return SQLITE_ERROR
    ' A multi-row VALUES fallback may wrap its coroutine in a SELECT that
    ' retains SF_Values because an earlier UNION ALL term precedes it.
    If pDestination->eDest <> SRT_Output AndAlso _
       pDestination->eDest <> SRT_EphemTab AndAlso _
       pDestination->eDest <> SRT_Table AndAlso _
       pDestination->eDest <> SRT_Fifo AndAlso _
       pDestination->eDest <> SRT_DistFifo AndAlso _
       pDestination->eDest <> SRT_Queue AndAlso _
       pDestination->eDest <> SRT_DistQueue AndAlso _
       pDestination->eDest <> SRT_Coroutine AndAlso _
       pDestination->eDest <> SRT_Mem AndAlso _
       pDestination->eDest <> SRT_Exists AndAlso _
       pDestination->eDest <> SRT_Set AndAlso _
       pDestination->eDest <> SRT_Discard AndAlso _
       pDestination->eDest <> SRT_Upfrom Then Return SQLITE_MISUSE
    Dim canRewriteDistinctAsGroup As SQLITE_C_INT = CInt( _
        (pSelect->selFlags And (SF_Distinct Or SF_Aggregate)) = SF_Distinct _
        AndAlso pOrderBy <> 0 AndAlso _
        (pParse->db->dbOptFlags And SQLITE_GroupByOrder) = 0)
#ifndef SQLITE_OMIT_WINDOWFUNC
    If pSelect->pWin <> 0 Then canRewriteDistinctAsGroup = 0
#endif
    If canRewriteDistinctAsGroup <> 0 Then
        Dim pDistinctGroupBy As SqliteExprList Ptr = _
            sqlite3ExprListDup(pParse->db, pResultList, 0)
        If pDistinctGroupBy = 0 Then
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            Return SQLITE_ERROR
        End If
        If sqlite3SelectCopySortOrder(pDistinctGroupBy, pOrderBy) <> 0 AndAlso _
           sqlite3ExprListCompare(pDistinctGroupBy, pOrderBy, -1) = 0 Then
            For itemIndex As SQLITE_C_INT = 0 To pDistinctGroupBy->nExpr - 1
                pDistinctGroupBy->a(itemIndex).u.x.iOrderByCol = itemIndex + 1
            Next
            pSelect->pGroupBy = pDistinctGroupBy
            pSelect->selFlags = pSelect->selFlags And Not CUInt(SF_Distinct)
            pSelect->selFlags = pSelect->selFlags Or SF_Aggregate
            isAggregate = 1
        Else
            sqlite3ExprListDelete(pParse->db, pDistinctGroupBy)
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        End If
    End If

    If pSelect->pGroupBy <> 0 AndAlso isAggregate = 0 Then _
        Return SQLITE_ERROR
    If pSelect->pHaving <> 0 AndAlso isAggregate = 0 Then _
        Return SQLITE_ERROR
    Dim nColumn As SQLITE_C_INT = pResultList->nExpr
    If nColumn > pParse->db->aLimit(SQLITE_LIMIT_COLUMN) Then Return SQLITE_TOOBIG
    If pParse->nMem < 0 OrElse _
       nColumn > SQLITE_MAX_VDBE_OP - pParse->nMem Then Return SQLITE_TOOBIG

    Dim materializeResult As SQLITE_C_INT = _
        sqlite3SelectMaterializeFromSubqueries( _
            pParse, pSourceList, pSelect->selFlags)
    If materializeResult <> SQLITE_OK Then Return materializeResult

    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pParse->pVdbe)
    If pVdbe = 0 Then Return SQLITE_NOMEM

    If (pSelect->selFlags And SF_FixedLimit) = 0 Then
        ' SQLite uses a log-estimate of 320 for an unconstrained SELECT.
        pSelect->nSelectRow = 320
    End If
    If isAggregate <> 0 Then
        If pSelect->pGroupBy <> 0 Then
            ' GROUP BY output is estimated at 100 rows (sqlite3LogEst(100) = 66).
            If pSelect->nSelectRow > 66 Then pSelect->nSelectRow = 66
            Return sqlite3SelectCompileGroupedAggregateFromClause( _
                pParse, pSelect, pSourceList, pResultList, _
                CPtr(SqliteExprList Ptr, pSelect->pGroupBy), _
                pDestination, nColumn)
        End If
        ' An aggregate without GROUP BY emits at most one row.
        pSelect->nSelectRow = 0
        Return sqlite3SelectCompileSimpleAggregateFromClause( _
            pParse, pSelect, pSourceList, pResultList, pDestination, nColumn)
    End If

    Dim pSort As SqliteSortContext Ptr = 0
    Dim savedSelectLimit As SQLITE_C_INT = pSelect->iLimit
    Dim savedSelectOffset As SQLITE_C_INT = pSelect->iOffset
    Dim sortLimitRegister As SQLITE_C_INT = 0
    Dim sortOffsetRegister As SQLITE_C_INT = 0
    Dim deferredSortLimit As SQLITE_C_INT = 0
    Dim sortContext As SqliteSortContext
    If pOrderBy <> 0 Then
        If pOrderBy->nExpr <= 0 OrElse _
           pOrderBy->nExpr > SQLITE_MAX_VDBE_OP - nColumn - 1 Then _
            Return SQLITE_TOOBIG
        If pParse->nTab < 0 OrElse pParse->nTab = &H7FFFFFFF Then _
            Return SQLITE_TOOBIG

        sortContext.pOrderBy = pOrderBy
        sortContext.nOBSat = 0
        sortContext.iECursor = pParse->nTab
        sortContext.regReturn = 0
        sortContext.labelBkOut = 0
        sortContext.addrSortIndex = -1
        sortContext.labelDone = 0
        sortContext.labelOBLopt = 0
        sortContext.sortFlags = 0
        sortContext.pDeferredRowLoad = 0
#ifdef SQLITE_ENABLE_SORTER_REFERENCES
        sortContext.nDefer = 0
        For deferredIndex As SQLITE_C_INT = 0 To UBound(sortContext.aDefer)
            sortContext.aDefer(deferredIndex).pTab = 0
            sortContext.aDefer(deferredIndex).iCsr = 0
            sortContext.aDefer(deferredIndex).nKey = 0
        Next
#endif
#ifdef SQLITE_ENABLE_STMT_SCANSTATUS
        sortContext.addrPush = 0
        sortContext.addrPushEnd = 0
#endif
        pParse->nTab += 1
        Dim pKeyInfo As sqlite3VdbeKeyInfoPrefix Ptr = _
            sqlite3KeyInfoFromExprList(pParse, pOrderBy, 0, nColumn)
        If pKeyInfo = 0 Then
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            Return SQLITE_ERROR
        End If
        Dim sortFieldCount As SQLITE_C_INT = pOrderBy->nExpr + 1 + nColumn
        sortContext.addrSortIndex = sqlite3VdbeAddOp4( _
            pVdbe, OP_OpenEphemeral, sortContext.iECursor, _
            sortFieldCount, 0, CPtr(Const ZString Ptr, pKeyInfo), P4_KEYINFO)
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        pSort = @sortContext
    End If

    Dim pDistinct As SqliteDistinctContext Ptr = 0
    Dim distinctContext As SqliteDistinctContext
    If (pSelect->selFlags And SF_Distinct) <> 0 Then
        If pParse->nTab < 0 OrElse pParse->nTab = &H7FFFFFFF Then _
            Return SQLITE_TOOBIG
        distinctContext.isTnct = 1
        distinctContext.eTnctType = WHERE_DISTINCT_UNORDERED
        distinctContext.tabTnct = pParse->nTab
        pParse->nTab += 1
        distinctContext.addrTnct = -1
        Dim pDistinctKey As sqlite3VdbeKeyInfoPrefix Ptr = _
            sqlite3KeyInfoFromExprList(pParse, pResultList, 0, 0)
        If pDistinctKey = 0 Then
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            Return SQLITE_ERROR
        End If
        distinctContext.addrTnct = sqlite3VdbeAddOp4( _
            pVdbe, OP_OpenEphemeral, distinctContext.tabTnct, 0, 0, _
            CPtr(Const ZString Ptr, pDistinctKey), P4_KEYINFO)
        sqlite3VdbeChangeP5(pVdbe, BTREE_UNORDERED)
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        pDistinct = @distinctContext
    End If

    Dim pLimitExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pSelect->pLimit)
    Dim limitRegister As SQLITE_C_INT = 0
    Dim offsetRegister As SQLITE_C_INT = 0
    Dim offsetLimitRegister As SQLITE_C_INT = 0
    If pSelect->iLimit <> 0 Then
        ' Compound SELECT code may pass a shared LIMIT counter into this term.
        limitRegister = pSelect->iLimit
        offsetRegister = pSelect->iOffset
    ElseIf pLimitExpr <> 0 Then
        If pLimitExpr->op <> TK_LIMIT OrElse pLimitExpr->pLeft = 0 Then _
            Return SQLITE_CORRUPT
        limitRegister = sqlite3SelectNextRegister(pParse)
        If limitRegister = 0 Then Return SQLITE_NOMEM
        Dim limitCode As SQLITE_C_INT = sqlite3SelectCompileExpr( _
            pParse, CPtr(SqliteExpr Ptr, pLimitExpr->pLeft), limitRegister, 0)
        If limitCode <> SQLITE_OK Then Return limitCode
        sqlite3VdbeAddOp1(pVdbe, OP_MustBeInt, limitRegister)
        If pLimitExpr->pRight <> 0 Then
            offsetRegister = sqlite3SelectNextRegister(pParse)
            If offsetRegister = 0 Then Return SQLITE_NOMEM
            If pSort <> 0 Then
                ' OP_OffsetLimit stores LIMIT+OFFSET in the register after OFFSET.
                offsetLimitRegister = sqlite3SelectNextRegister(pParse)
                If offsetLimitRegister = 0 Then Return SQLITE_NOMEM
                If offsetLimitRegister <> offsetRegister + 1 Then _
                    Return SQLITE_CORRUPT
            End If
            limitCode = sqlite3SelectCompileExpr( _
                pParse, CPtr(SqliteExpr Ptr, pLimitExpr->pRight), offsetRegister, 0)
            If limitCode <> SQLITE_OK Then Return limitCode
            sqlite3VdbeAddOp1(pVdbe, OP_MustBeInt, offsetRegister)
            If offsetLimitRegister <> 0 Then _
                sqlite3VdbeAddOp3( _
                    pVdbe, OP_OffsetLimit, limitRegister, _
                    offsetLimitRegister, offsetRegister)
        End If
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        pSelect->iLimit = limitRegister
        pSelect->iOffset = offsetRegister
    End If

    ' Keep the planner's row limit in LogEst form when LIMIT is a literal.
    ' WHERE_ORDERBY_LIMIT uses this estimate to compare an ordered index scan
    ' with a table scan followed by a bounded sort.
    If savedSelectLimit = 0 AndAlso pLimitExpr <> 0 Then
        Dim fixedLimitValue As SQLITE_C_INT = 0
        If sqlite3ExprIsInteger(pLimitExpr->pLeft, @fixedLimitValue, _
                                pParse, 0) <> 0 AndAlso _
           fixedLimitValue >= 0 AndAlso _
           pSelect->nSelectRow > sqlite3LogEst(CULngInt(fixedLimitValue)) Then
            pSelect->nSelectRow = sqlite3LogEst(CULngInt(fixedLimitValue))
            pSelect->selFlags Or= SF_FixedLimit
        End If
    End If

    ' Window rewrite has attached a materialized input subquery and prepared
    ' the frame state; codegen opens the window cursors before scan setup.
#ifndef SQLITE_OMIT_WINDOWFUNC
    If pSelect->pWin <> 0 Then sqlite3WindowCodeInit(pParse, pSelect)
#endif
    Dim whereControlFlags As UShort = _
        CUShort(pSelect->selFlags And SF_FixedLimit)
    If pDistinct <> 0 Then whereControlFlags Or= WHERE_WANT_DISTINCT
    Dim pWhereInfo As SqliteWhereInfo Ptr = sqlite3WhereBegin( _
        pParse, pSourceList, CPtr(SqliteExpr Ptr, pSelect->pWhere), _
        CPtr(SqliteExprList Ptr, pSelect->pOrderBy), _
        pResultList, pSelect, whereControlFlags, pSelect->nSelectRow)
    If pWhereInfo = 0 Then
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        Return SQLITE_ERROR
    End If
    If pDistinct <> 0 Then
        Dim plannedDistinctType As SQLITE_C_INT = _
            sqlite3WhereIsDistinct(pWhereInfo)
        If plannedDistinctType <> WHERE_DISTINCT_NOOP Then _
            pDistinct->eTnctType = plannedDistinctType
    End If
    Dim plannedRowCount As Short = sqlite3WhereOutputRowCount(pWhereInfo)
    If plannedRowCount < pSelect->nSelectRow Then
        pSelect->nSelectRow = plannedRowCount
        If pDestination->eDest <= SRT_DistQueue AndAlso _
           pDestination->eDest >= SRT_DistFifo Then _
            pSelect->nSelectRow -= 30
    End If

    If pSort <> 0 Then
        pSort->nOBSat = sqlite3WhereIsOrdered(pWhereInfo)
        pSort->labelOBLopt = sqlite3WhereOrderByLimitOptLabel(pWhereInfo)
        If pSort->nOBSat = pOrderBy->nExpr Then
            pSort->pOrderBy = 0
        End If
        sortLimitRegister = IIf(limitRegister <> 0, limitRegister, savedSelectLimit)
        sortOffsetRegister = IIf(offsetRegister <> 0, offsetRegister, savedSelectOffset)
        If pSort->pOrderBy <> 0 AndAlso sortLimitRegister <> 0 Then
            ' A bounded ephemeral index keeps the best LIMIT+OFFSET rows.
            pSelect->iLimit = sortLimitRegister
            pSelect->iOffset = sortOffsetRegister
            deferredSortLimit = 1
        End If
        If pSort->addrSortIndex >= 0 AndAlso pSort->pOrderBy = 0 Then
            sqlite3VdbeChangeToNoop(pVdbe, pSort->addrSortIndex)
        ElseIf pSort->addrSortIndex >= 0 AndAlso deferredSortLimit = 0 Then
            sqlite3VdbeChangeOpcode( _
                pVdbe, pSort->addrSortIndex, OP_SorterOpen)
            pSort->sortFlags = pSort->sortFlags Or SQLITE_SORTFLAG_USE_SORTER
        End If
    End If
    If pDistinct <> 0 AndAlso pSort <> 0 AndAlso _
       pSort->pOrderBy = 0 AndAlso pOrderBy <> 0 AndAlso _
       pDistinct->eTnctType <> WHERE_DISTINCT_UNIQUE Then
        If sqlite3ExprListCompare(pResultList, pOrderBy, -1) = 0 Then _
            pDistinct->eTnctType = WHERE_DISTINCT_ORDERED
    End If

    ' WhereBegin emits the scan setup. These expression and ResultRow
    ' instructions form the loop body, and WhereEnd closes the loop.
    Dim resultCode As SQLITE_C_INT = sqlite3SelectEmitOutputRow( _
        pParse, pSelect, pSort, pDistinct, pDestination, pWhereInfo, _
        limitRegister, offsetRegister)
#ifndef SQLITE_OMIT_WINDOWFUNC
    If pSelect->pWin = 0 Then sqlite3WhereEnd(pWhereInfo)
#else
    sqlite3WhereEnd(pWhereInfo)
#endif
    If resultCode = SQLITE_OK AndAlso pDistinct <> 0 AndAlso _
       pDistinct->eTnctType = WHERE_DISTINCT_UNORDERED Then
        sqlite3VdbeExplainText( _
            pParse, 0, StrPtr("USE TEMP B-TREE FOR DISTINCT"))
    End If
    If pParse->db->mallocFailed <> 0 Then
        If deferredSortLimit <> 0 Then
            pSelect->iLimit = savedSelectLimit
            pSelect->iOffset = savedSelectOffset
        End If
        Return SQLITE_NOMEM
    End If
    If pParse->nErr <> 0 AndAlso resultCode = SQLITE_OK Then _
        resultCode = SQLITE_ERROR
    If resultCode = SQLITE_OK AndAlso pSort <> 0 AndAlso _
       pSort->pOrderBy <> 0 Then
        sqlite3SelectGenerateSortTail( _
            pParse, pSelect, pSort, nColumn, pDestination)
        If pParse->db->mallocFailed <> 0 OrElse pParse->nErr <> 0 Then
            If deferredSortLimit <> 0 Then
                pSelect->iLimit = savedSelectLimit
                pSelect->iOffset = savedSelectOffset
            End If
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            Return SQLITE_ERROR
        End If
    End If
    If deferredSortLimit <> 0 Then
        pSelect->iLimit = savedSelectLimit
        pSelect->iOffset = savedSelectOffset
    End If
    Return resultCode
End Function

Function sqlite3Select CDecl Alias "sqlite3Select" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pDestination As SqliteSelectDest Ptr _
) As SQLITE_C_INT Export
    If pParse = 0 OrElse pParse->db = 0 OrElse pSelect = 0 OrElse _
       pDestination = 0 OrElse _
       (pDestination->eDest <> SRT_Output AndAlso _
        pDestination->eDest <> SRT_EphemTab AndAlso _
        pDestination->eDest <> SRT_Table AndAlso _
        pDestination->eDest <> SRT_Fifo AndAlso _
        pDestination->eDest <> SRT_DistFifo AndAlso _
        pDestination->eDest <> SRT_Queue AndAlso _
        pDestination->eDest <> SRT_DistQueue AndAlso _
        pDestination->eDest <> SRT_Coroutine AndAlso _
        pDestination->eDest <> SRT_Mem AndAlso _
        pDestination->eDest <> SRT_Exists AndAlso _
        pDestination->eDest <> SRT_Set AndAlso _
        pDestination->eDest <> SRT_Discard AndAlso _
        pDestination->eDest <> SRT_Upfrom) Then Return SQLITE_MISUSE

    sqlite3ProgressCheck(pParse)
    If pParse->rc = SQLITE_INTERRUPT Then Return SQLITE_INTERRUPT
    If pParse->nErr <> 0 Then Return SQLITE_ERROR
    If sqlite3AuthCheck(pParse, SQLITE_SELECT, 0, 0, 0) <> SQLITE_OK Then _
        Return SQLITE_ERROR

    ' EXISTS, discard, and distinct queue destinations do not observe result
    ' order or duplicate rows. Drop those clauses before window rewriting so
    ' they cannot create a sorter or extend a subquery that only needs one row.
    If pDestination->eDest <= SRT_DistQueue Then
        If pSelect->pOrderBy <> 0 Then
            Dim pIgnoredOrderBy As SqliteExprList Ptr = pSelect->pOrderBy
            ' AddCleanup may invoke the destructor immediately on OOM.
            ' Clear the owning field before transferring the list.
            pSelect->pOrderBy = 0
            If sqlite3ParserAddCleanup( _
                pParse, @sqlite3ExprListDeleteGeneric, pIgnoredOrderBy) = 0 Then _
                Return SQLITE_NOMEM
        End If
        pSelect->selFlags = pSelect->selFlags And Not CUInt(SF_Distinct)
    End If

    If pSelect->pPrior <> 0 Then
        sqlite3SelectPrep(pParse, pSelect, 0)
        If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
        If pParse->nErr <> 0 Then Return SQLITE_ERROR
        ' Preparation may rewrite a collated compound ORDER BY into a
        ' single SELECT over a compound FROM-subquery. Dispatch using the
        ' updated pPrior chain, as the rewrite clears pPrior on the wrapper.
        If pSelect->pPrior <> 0 Then
            If pDestination->eDest = SRT_Output Then
                If sqlite3GetVdbe(pParse) = 0 Then Return SQLITE_NOMEM
                sqlite3GenerateColumnNames(pParse, pSelect)
            End If
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            If pParse->nErr <> 0 Then Return SQLITE_ERROR
            Dim compoundCode As SQLITE_C_INT = sqlite3SelectCompileCompound( _
                pParse, pSelect, pDestination)
            If pSelect->pNext = 0 Then sqlite3VdbeExplainPop(pParse)
            Return compoundCode
        End If
    End If

#ifndef SQLITE_OMIT_WINDOWFUNC
    If pSelect->pWin <> 0 Then
        Dim windowCode As SQLITE_C_INT = sqlite3SelectCompileFromClause( _
            pParse, pSelect, pDestination)
        sqlite3VdbeExplainPop(pParse)
        Return windowCode
    End If
#endif

    If pSelect->pSrc <> 0 Then
        Dim pSourceList As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pSelect->pSrc)
        If pSourceList->nSrc > 0 Then
            Dim fromCode As SQLITE_C_INT = sqlite3SelectCompileFromClause( _
                pParse, pSelect, pDestination)
            sqlite3VdbeExplainPop(pParse)
            Return fromCode
        End If
    End If

    ' Aggregate SELECTs with no FROM clause run over one implicit input row.
    ' Prepare here so name resolution records SF_Aggregate before dispatch.
    sqlite3SelectPrep(pParse, pSelect, 0)
    If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pParse->nErr <> 0 Then Return SQLITE_ERROR

    ' A source-less SELECT scans one implicit constant row. The planner emits
    ' this line through sqlite3WhereBegin() in C; this port handles the
    ' source-less path directly, so add the same EQP entry here.
    Dim pPreparedSourceList As SqliteSrcList Ptr = _
        CPtr(SqliteSrcList Ptr, pSelect->pSrc)
    If (pPreparedSourceList = 0 OrElse pPreparedSourceList->nSrc = 0) AndAlso _
       (pSelect->selFlags And SF_MultiValue) = 0 Then
        If sqlite3GetVdbe(pParse) = 0 Then Return SQLITE_NOMEM
        sqlite3VdbeExplainText(pParse, 0, StrPtr("SCAN CONSTANT ROW"))
    End If
#ifndef SQLITE_OMIT_WINDOWFUNC
    ' Name resolution attaches window functions to the SELECT. Source-less
    ' SELECTs reach this path before that list exists, so route them through
    ' the same rewrite and code-generation path after preparation.
    If pSelect->pWin <> 0 Then
        Dim preparedWindowCode As SQLITE_C_INT = _
            sqlite3SelectCompileFromClause(pParse, pSelect, pDestination)
        sqlite3VdbeExplainPop(pParse)
        Return preparedWindowCode
    End If
#endif
    Dim destinationOpenCode As SQLITE_C_INT = _
        sqlite3SelectOpenEphemeralDestination( _
            pParse, pSelect, pDestination)
    If destinationOpenCode <> SQLITE_OK Then Return destinationOpenCode
    If (pSelect->selFlags And SF_Aggregate) <> 0 Then
        Dim pResultList As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pSelect->pEList)
        If pResultList = 0 OrElse pResultList->nExpr <= 0 OrElse _
           pResultList->nAlloc < pResultList->nExpr Then Return SQLITE_CORRUPT
        Dim nColumn As SQLITE_C_INT = pResultList->nExpr
        If nColumn > pParse->db->aLimit(SQLITE_LIMIT_COLUMN) Then _
            Return SQLITE_TOOBIG
        If pDestination->eDest = SRT_Output Then
            If sqlite3GetVdbe(pParse) = 0 Then Return SQLITE_NOMEM
            sqlite3GenerateColumnNames(pParse, pSelect)
            If pParse->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
            If pParse->nErr <> 0 Then Return SQLITE_ERROR
        End If
        Dim pSourceList As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pSelect->pSrc)
        Dim aggregateCode As SQLITE_C_INT
        If pSelect->pGroupBy <> 0 Then
            aggregateCode = sqlite3SelectCompileGroupedAggregateFromClause( _
                pParse, pSelect, pSourceList, pResultList, _
                CPtr(SqliteExprList Ptr, pSelect->pGroupBy), _
                pDestination, nColumn)
        Else
            aggregateCode = sqlite3SelectCompileSimpleAggregateFromClause( _
                pParse, pSelect, pSourceList, pResultList, _
                pDestination, nColumn)
        End If
        sqlite3VdbeExplainPop(pParse)
        Return aggregateCode
    End If

    Dim isValues As SQLITE_C_INT = IIf((pSelect->selFlags And SF_Values) <> 0, 1, 0)
    Dim isCompound As SQLITE_C_INT = IIf(pSelect->pPrior <> 0, 1, 0)
    ' A VALUES term inside an ordinary compound SELECT is one row. Its pNext
    ' pointer names the following compound term, not another VALUES row.
    Dim isMultiValue As SQLITE_C_INT = _
        IIf((pSelect->selFlags And SF_MultiValue) <> 0, 1, 0)
    Dim isRowChain As SQLITE_C_INT = _
        IIf(isMultiValue <> 0 OrElse isCompound <> 0, 1, 0)
    ' A SELECT without FROM emits at most one row, so DISTINCT cannot remove
    ' it and ORDER BY cannot change its position in the output.
    If (isCompound <> 0 AndAlso pSelect->op <> TK_ALL) OrElse _
       pSelect->pGroupBy <> 0 OrElse _
       pSelect->pHaving <> 0 Then Return SQLITE_ERROR
    If isRowChain <> 0 AndAlso pSelect->pWhere <> 0 Then Return SQLITE_ERROR
    If isValues <> 0 AndAlso pSelect->pLimit <> 0 Then Return SQLITE_ERROR
#ifndef SQLITE_OMIT_WINDOWFUNC
    If pSelect->pWin <> 0 Then Return SQLITE_ERROR
#endif
    Dim pLimitExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pSelect->pLimit)
    If pLimitExpr <> 0 Then
        If isValues <> 0 OrElse pLimitExpr->op <> TK_LIMIT OrElse _
           pLimitExpr->pLeft = 0 Then Return SQLITE_ERROR
    End If

    Dim pFirst As SqliteSelect Ptr = pSelect
    If isRowChain <> 0 Then
        Dim pPriorSlow As SqliteSelect Ptr = pSelect
        Dim pPriorFast As SqliteSelect Ptr = pSelect
        While pFirst->pPrior <> 0
            pFirst = CPtr(SqliteSelect Ptr, pFirst->pPrior)
            pPriorSlow = CPtr(SqliteSelect Ptr, pPriorSlow->pPrior)
            If pPriorFast <> 0 Then _
                pPriorFast = CPtr(SqliteSelect Ptr, pPriorFast->pPrior)
            If pPriorFast <> 0 Then _
                pPriorFast = CPtr(SqliteSelect Ptr, pPriorFast->pPrior)
            If pPriorFast <> 0 AndAlso pPriorFast = pPriorSlow Then _
                Return SQLITE_CORRUPT
        Wend
        If isCompound <> 0 AndAlso _
           (pSelect->selFlags And (SF_MultiValue Or SF_Values)) = 0 Then
            Dim compoundLimit As SQLITE_C_INT = _
                pParse->db->aLimit(SQLITE_LIMIT_COMPOUND_SELECT)
            If compoundLimit > 0 Then
                Dim compoundCount As SQLITE_C_INT = 1
                Dim pPrior As SqliteSelect Ptr = _
                    CPtr(SqliteSelect Ptr, pSelect->pPrior)
                While pPrior <> 0
                    If compoundCount >= compoundLimit Then Return SQLITE_ERROR
                    compoundCount += 1
                    pPrior = CPtr(SqliteSelect Ptr, pPrior->pPrior)
                Wend
            End If
        End If
    End If
    If pFirst->pPrior <> 0 OrElse pFirst->pEList = 0 Then Return SQLITE_CORRUPT

    Dim pFirstList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pFirst->pEList)
    If pFirstList->nExpr <= 0 OrElse pFirstList->nExpr > 32767 OrElse _
       pFirstList->nAlloc < pFirstList->nExpr Then Return SQLITE_ERROR
    Dim nColumn As SQLITE_C_INT = pFirstList->nExpr

    Dim pVdbe As SqliteVdbe Ptr = sqlite3GetVdbe(pParse)
    If pVdbe = 0 Then Return SQLITE_NOMEM

    If pParse->nMem < 0 OrElse pParse->nMem > SQLITE_MAX_VDBE_OP Then _
        Return SQLITE_TOOBIG
    Dim firstRegister As SQLITE_C_INT = pParse->nMem + 1
    If nColumn > pParse->db->aLimit(SQLITE_LIMIT_COLUMN) Then Return SQLITE_TOOBIG
    If nColumn > SQLITE_MAX_VDBE_OP - pParse->nMem Then Return SQLITE_TOOBIG
    pParse->nMem += nColumn
    If pDestination->eDest = SRT_Output AndAlso pParse->colNamesSet = 0 Then _
        sqlite3VdbeSetNumCols(pVdbe, nColumn)
    If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM

    Dim limitRegister As SQLITE_C_INT = 0
    Dim offsetRegister As SQLITE_C_INT = 0
    Dim breakLabel As SQLITE_C_INT = 0
    If pLimitExpr <> 0 OrElse pSelect->iLimit <> 0 OrElse _
       pSelect->pWhere <> 0 Then
        breakLabel = sqlite3VdbeMakeLabel(pParse)
        If breakLabel = 0 Then Return SQLITE_NOMEM
    End If
    If pSelect->iLimit <> 0 Then
        ' Compound SELECT code passes one counter through each term. Reusing
        ' it prevents every UNION ALL term from resetting the same LIMIT.
        limitRegister = pSelect->iLimit
        offsetRegister = pSelect->iOffset
    ElseIf pLimitExpr <> 0 Then
        limitRegister = sqlite3SelectNextRegister(pParse)
        If limitRegister = 0 Then Return SQLITE_NOMEM
        Dim rc As SQLITE_C_INT = sqlite3SelectCompileExpr( _
            pParse, CPtr(SqliteExpr Ptr, pLimitExpr->pLeft), limitRegister, 0)
        If rc <> SQLITE_OK Then Return rc
        sqlite3VdbeAddOp1(pVdbe, OP_MustBeInt, limitRegister)
        sqlite3VdbeAddOp2(pVdbe, OP_IfNot, limitRegister, breakLabel)
        If pLimitExpr->pRight <> 0 Then
            offsetRegister = sqlite3SelectNextRegister(pParse)
            If offsetRegister = 0 Then Return SQLITE_NOMEM
            rc = sqlite3SelectCompileExpr( _
                pParse, CPtr(SqliteExpr Ptr, pLimitExpr->pRight), offsetRegister, 0)
            If rc <> SQLITE_OK Then Return rc
            sqlite3VdbeAddOp1(pVdbe, OP_MustBeInt, offsetRegister)
        End If
        If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    End If
    If limitRegister <> 0 Then
        pSelect->iLimit = limitRegister
        pSelect->iOffset = offsetRegister
    End If

    Dim whereRegister As SQLITE_C_INT = 0
    If pSelect->pWhere <> 0 Then
        whereRegister = sqlite3SelectNextRegister(pParse)
        If whereRegister = 0 Then Return SQLITE_NOMEM
        Dim rc As SQLITE_C_INT = sqlite3SelectCompileExpr( _
            pParse, CPtr(SqliteExpr Ptr, pSelect->pWhere), whereRegister, 0)
        If rc <> SQLITE_OK Then Return rc
        ' In WHERE, both false and NULL suppress the result row.
        sqlite3VdbeAddOp3(pVdbe, OP_IfNot, whereRegister, breakLabel, 1)
        If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    End If

    Dim tempRegisterStart As SQLITE_C_INT = pParse->nMem
    Dim maximumRegisterCount As SQLITE_C_INT = pParse->nMem

    Dim pRow As SqliteSelect Ptr = pFirst
    Dim pLastRow As SqliteSelect Ptr = 0
    Dim pSlow As SqliteSelect Ptr = pFirst
    Dim pFast As SqliteSelect Ptr = pFirst
    Dim rowCount As sqlite3_uint64 = 0
    While pRow <> 0
        If pRow->pSrc = 0 OrElse _
           CPtr(SqliteSrcListHeader Ptr, pRow->pSrc)->nSrc <> 0 OrElse _
           (pRow->pWhere <> 0 AndAlso (isRowChain <> 0 OrElse pRow <> pSelect)) OrElse _
           pRow->pGroupBy <> 0 OrElse _
           pRow->pHaving <> 0 OrElse _
           (pRow->pOrderBy <> 0 AndAlso isRowChain <> 0 AndAlso _
            (pRow <> pSelect OrElse _
             (pSelect->selFlags And SF_Compound) = 0)) OrElse _
           (pRow->pLimit <> 0 AndAlso _
            (isValues <> 0 OrElse pRow <> pSelect)) OrElse _
           pRow->pEList = 0 Then Return SQLITE_ERROR
#ifndef SQLITE_OMIT_WINDOWFUNC
        If pRow->pWin <> 0 Then Return SQLITE_ERROR
#endif
        If isRowChain <> 0 AndAlso pRow <> pFirst AndAlso pRow->op <> TK_ALL Then _
            Return SQLITE_CORRUPT

        Dim pList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pRow->pEList)
        Dim rc As SQLITE_C_INT = sqlite3SelectCompileRow( _
            pParse, pRow, pList, pDestination, firstRegister, nColumn, _
            tempRegisterStart, _
            IIf(rowCount = 0 AndAlso _
                pDestination->eDest = SRT_Output AndAlso _
                pParse->colNamesSet = 0, 1, 0), _
            IIf((pFirst->selFlags And SF_Values) <> 0, 1, 0), _
            IIf(isRowChain = 0 AndAlso pRow->pWhere = 0 AndAlso _
                pRow->pLimit = 0 AndAlso _
                (pRow->selFlags And SF_Values) = 0, 1, 0), _
            offsetRegister, limitRegister, breakLabel)
        If rc <> SQLITE_OK Then Return rc
        If pParse->nMem > maximumRegisterCount Then _
            maximumRegisterCount = pParse->nMem

        rowCount += 1
        If rowCount > SQLITE_MAX_VDBE_OP Then Return SQLITE_TOOBIG
        If isRowChain = 0 Then Exit While

        pLastRow = pRow
        Dim pNext As SqliteSelect Ptr = CPtr(SqliteSelect Ptr, pRow->pNext)
        If pNext <> 0 AndAlso pNext->pPrior <> pRow Then Return SQLITE_CORRUPT
        pRow = pNext

        pSlow = CPtr(SqliteSelect Ptr, pSlow->pNext)
        If pFast <> 0 Then pFast = CPtr(SqliteSelect Ptr, pFast->pNext)
        If pFast <> 0 Then pFast = CPtr(SqliteSelect Ptr, pFast->pNext)
        If pFast <> 0 AndAlso pFast = pSlow Then Return SQLITE_CORRUPT
    Wend
    If rowCount = 0 OrElse (isRowChain <> 0 AndAlso pLastRow <> pSelect) Then _
        Return SQLITE_CORRUPT

    If breakLabel <> 0 Then sqlite3VdbeResolveLabel(pVdbe, breakLabel)
    pParse->nMem = maximumRegisterCount
    If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    sqlite3VdbeExplainPop(pParse)
    Return SQLITE_OK
End Function

Private Sub codeOffset CDecl Alias "codeOffset" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal offsetRegister As SQLITE_C_INT, _
    ByVal continueAddress As SQLITE_C_INT _
)
    If pVdbe = 0 OrElse offsetRegister <= 0 Then Exit Sub
    ' OP_IfPos decrements a positive OFFSET counter before continuing.
    sqlite3VdbeAddOp3(pVdbe, OP_IfPos, offsetRegister, continueAddress, 1)
End Sub

Private Function hasAnchor CDecl Alias "hasAnchor" ( _
    ByVal pSelectArgument As SqliteSelect Ptr _
) As SQLITE_C_INT
    Dim pSelect As SqliteSelect Ptr = pSelectArgument
    While pSelect <> 0 AndAlso (pSelect->selFlags And SF_Recursive) <> 0
        pSelect = CPtr(SqliteSelect Ptr, pSelect->pPrior)
    Wend
    Return IIf(pSelect <> 0, 1, 0)
End Function

Function sqlite3GetVdbe CDecl Alias "sqlite3GetVdbe" ( _
    ByVal pParse As SqliteParseContext Ptr _
) As SqliteVdbe Ptr Export
    If pParse = 0 OrElse pParse->db = 0 Then Return 0
    If pParse->pVdbe <> 0 Then Return CPtr(SqliteVdbe Ptr, pParse->pVdbe)
    If pParse->pToplevel = 0 Then pParse->okConstFactor = 1
    Return CPtr(SqliteVdbe Ptr, sqlite3VdbeCreate(pParse))
End Function

Sub sqlite3SelectPopWith CDecl Alias "sqlite3SelectPopWith" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) Export
    If pWalker = 0 OrElse pWalker->pParse = 0 OrElse pSelect = 0 Then Exit Sub
    Dim pParse As SqliteParseContext Ptr = pWalker->pParse
    If pParse->pWith = 0 OrElse pSelect->pPrior <> 0 Then Exit Sub

    Dim pRightmost As SqliteSelect Ptr = pSelect
    While pRightmost->pNext <> 0
        pRightmost = CPtr(SqliteSelect Ptr, pRightmost->pNext)
    Wend
    Dim pWith As SqliteWith Ptr = CPtr(SqliteWith Ptr, pRightmost->pWith)
    If pWith = 0 Then Exit Sub
    If pParse->pWith <> pWith AndAlso pParse->nErr = 0 Then Exit Sub
    pParse->pWith = pWith->pOuter
End Sub

Function sqlite3SelectOpName CDecl Alias "sqlite3SelectOpName" ( _
    ByVal selectOpcode As SQLITE_C_INT _
) As Const ZString Ptr Export
    Select Case selectOpcode
    Case TK_ALL
        Return StrPtr("UNION ALL")
    Case TK_INTERSECT
        Return StrPtr("INTERSECT")
    Case TK_EXCEPT
        Return StrPtr("EXCEPT")
    Case Else
        Return StrPtr("UNION")
    End Select
End Function

#ifdef SQLITE_DEBUG
Sub sqlite3SelectWalkAssert2 CDecl Alias "sqlite3SelectWalkAssert2" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) Export
    ' This callback is installed to prove that the second SELECT callback never runs.
    sqlite3DebugAssert(StrPtr("xSelectCallback2 is never invoked"))
End Sub
#endif

/' end of sqlite3_select.bas '/
