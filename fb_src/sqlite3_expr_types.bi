/'
    Project: SQLite FreeBASIC port

    File: sqlite3_expr_types.bi

    Purpose:

        Define the core expression, expression-list, and SELECT layouts.

    Responsibilities:

        - Preserve the common SQLite Expr and ExprList field order.
        - Define the core Select prefix used by grammar actions.
        - Declare expression allocation, list construction, and tree cleanup.
        - Preserve constant-analysis and expression-origin flags.
        - Describe flexible identifier-list, subquery, and CTE storage from the C AST.

    This file intentionally does NOT contain:

        - Name resolution, aggregate/window state, or SELECT code generation.
'/

#ifndef SQLITE3_FB_EXPR_TYPES_BI
#define SQLITE3_FB_EXPR_TYPES_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_tokens.bi"

#ifndef SQLITE_MAX_VARIABLE_NUMBER
#define SQLITE_MAX_VARIABLE_NUMBER 32766
#endif
#ifndef SQLITE_MAX_EXPR_DEPTH
#define SQLITE_MAX_EXPR_DEPTH 1000
#endif
#ifndef SQLITE_MAX_FUNCTION_ARG
#define SQLITE_MAX_FUNCTION_ARG 1000
#endif

Type SqliteExprList As SqliteExprListRecord
Type SqliteSelect As SqliteSelectRecord
Type SqliteSrcList As SqliteSrcListRecord
Type SqliteWith As SqliteWithRecord

#define EP_OuterON &H00000001
#define EP_InnerON &H00000002
#define EP_Distinct &H00000004
#define EP_HasFunc &H00000008
#define EP_Agg &H00000010
#define EP_FixedCol &H00000020
#define EP_DblQuoted &H00000080
#define EP_Collate &H00000200
#define EP_IntValue &H00000800
#define EP_xIsSelect &H00001000
#define EP_Reduced &H00004000
#define EP_VarSelect &H00000040 ' The SELECT depends on outer-query values.
#define EP_TokenOnly &H00010000
#define EP_FullSize &H00020000
#define EP_Subquery &H00400000
#define EP_Leaf &H00800000
#define EP_Subrtn &H02000000 ' Expr.y stores a subroutine register range.
#ifdef SQLITE_DEBUG
#define EP_NoReduce &H01 ' The debug verifier forbids a reduced copy.
#define EP_Immutable &H02 ' Expression is immutable after schema duplication.
#endif
#define EP_InfixFunc &H00000100
#define EP_Skip &H00002000 ' COLLATE wrapper does not change the expression value.
#define EP_Propagate (EP_Collate Or EP_Subquery Or EP_HasFunc)
#define EP_Unlikely &H00080000 ' likely()/unlikely()/likelihood() wrapper node.
#define EP_ConstFunc &H00100000
#define EP_SubtArg &H80000000UL ' Function argument participates in subtype transfer.
#define EP_IsTrue &H10000000
#define EP_IsFalse &H20000000
#define EP_Quoted &H04000000
#define EP_IfNullRow &H00040000 ' TK_IF_NULL_ROW expression node.
#define EP_CanBeNull &H00200000 ' Value may be NULL despite a NOT NULL constraint.
#define EP_FromDDL &H40000000
#define EP_Commuted &H00000400
#define EP_Static &H08000000 ' The expression storage is not owned by sqlite3_malloc.

#define ENAME_NAME 0
#define ENAME_SPAN 1
#define ENAME_TAB 2
#define ENAME_ROWID 3

' Bit positions for the ExprList_item.fg C bitfield word.
#define SQLITE_EXPRLIST_EENAME_MASK &H0003
#define SQLITE_EXPRLIST_BUSED &H0040 ' Column is used by a nested FROM subquery.
#define SQLITE_EXPRLIST_BUSINGTERM &H0080
#define SQLITE_EXPRLIST_BNOEXPAND &H0100

Union SqliteExprTokenValue
    zToken As UByte Ptr
    iValue As SQLITE_C_INT
End Union

Union SqliteExprSelectValue
    pList As SqliteExprList Ptr
    pSelect As SqliteSelect Ptr
End Union

Union SqliteExprJoinOffset
    iJoin As SQLITE_C_INT
    iOfst As SQLITE_C_INT
End Union

Type SqliteExprSubroutine
    iAddr As SQLITE_C_INT
    regReturn As SQLITE_C_INT
End Type

Union SqliteExprYValue
    pTab As Any Ptr
    pWin As Any Ptr
    nReg As SQLITE_C_INT
    sub As SqliteExprSubroutine
End Union

Type SqliteExpr
    op As u8
    affExpr As Byte
    op2 As u8
#ifdef SQLITE_DEBUG
    vvaFlags As u8
#endif
    flags As u32
    u As SqliteExprTokenValue
    pLeft As SqliteExpr Ptr
    pRight As SqliteExpr Ptr
    x As SqliteExprSelectValue
#if SQLITE_MAX_EXPR_DEPTH > 0
    nHeight As SQLITE_C_INT
#endif
    iTable As SQLITE_C_INT
#if SQLITE_MAX_VARIABLE_NUMBER < 32767
    iColumn As Short
#else
    iColumn As SQLITE_C_INT
#endif
    iAgg As Short
    w As SqliteExprJoinOffset
    pAggInfo As Any Ptr
    y As SqliteExprYValue
End Type

Type SqliteExprListItemIndex
    iOrderByCol As UShort
    iAlias As UShort
End Type

Union SqliteExprListItemValue
    x As SqliteExprListItemIndex
    iConstExprReg As SQLITE_C_INT
End Union

Type SqliteExprListFlags
    sortFlags As u8
    ' SQLite stores the following C bitfields in one unsigned int.
    flags As u32
End Type

Type SqliteExprListItem
    pExpr As SqliteExpr Ptr
    zEName As UByte Ptr
    fg As SqliteExprListFlags
    u As SqliteExprListItemValue
End Type

Type SqliteExprListRecord
    nExpr As SQLITE_C_INT
    nAlloc As SQLITE_C_INT
    a(0 To 0) As SqliteExprListItem
End Type

' IdList uses a C flexible array after nId. The first item keeps the same
' offset and stride as the allocated trailing items.
Type SqliteIdListItem
    zName As ZString Ptr
End Type

Type SqliteIdList
    nId As SQLITE_C_INT
    a(0 To 0) As SqliteIdListItem
End Type

' Subquery keeps a SELECT pointer followed by three VDBE register fields.
Type SqliteSubquery
    pSelect As SqliteSelect Ptr
    addrFillSub As SQLITE_C_INT
    regReturn As SQLITE_C_INT
    regResult As SQLITE_C_INT
End Type

' The parse-tree prefix and memory ownership fields from src/sqliteInt.h.
Type SqliteUpsert
    pUpsertTarget As Any Ptr
    pUpsertTargetWhere As Any Ptr
    pUpsertSet As Any Ptr
    pUpsertWhere As Any Ptr
    pNextUpsert As SqliteUpsert Ptr
    isDoUpdate As u8
    isDup As u8
    pToFree As Any Ptr
    pUpsertIdx As Any Ptr
    pUpsertSrc As Any Ptr
    regData As SQLITE_C_INT
    iDataCur As SQLITE_C_INT
    iIdxCur As SQLITE_C_INT
End Type

Declare Function sqlite3ExprListItemAt CDecl Alias "sqlite3ExprListItemAt" ( _
    ByVal pList As SqliteExprList Ptr, _
    ByVal itemIndex As SQLITE_C_INT _
) As SqliteExprListItem Ptr
Declare Function sqlite3ExprListFlags CDecl Alias "sqlite3ExprListFlags" ( _
    ByVal pList As Const SqliteExprList Ptr _
) As u32

Type SqliteSrcListHeader
    nSrc As SQLITE_C_INT
    nAlloc As SQLITE_C_INT
End Type

Type SqliteSelectRecord
    op As u8
    nSelectRow As Short
    selFlags As u32
    iLimit As SQLITE_C_INT
    iOffset As SQLITE_C_INT
    selId As u32
    pEList As SqliteExprList Ptr
    pSrc As SqliteSrcList Ptr
    pWhere As SqliteExpr Ptr
    pGroupBy As SqliteExprList Ptr
    pHaving As SqliteExpr Ptr
    pOrderBy As SqliteExprList Ptr
    pPrior As SqliteSelect Ptr
    pNext As SqliteSelect Ptr
    pLimit As SqliteExpr Ptr
    pWith As SqliteWith Ptr
#ifndef SQLITE_OMIT_WINDOWFUNC
    pWin As Any Ptr
    pWinDefn As Any Ptr
#endif
End Type

Type SqliteSelectDest
    eDest As u8
    iSDParm As SQLITE_C_INT
    iSDParm2 As SQLITE_C_INT
    iSdst As SQLITE_C_INT
    nSdst As SQLITE_C_INT
    zAffSdst As UByte Ptr
    pOrderBy As Any Ptr
End Type

Type SqliteDistinctContext
    isTnct As u8
    eTnctType As u8
    tabTnct As SQLITE_C_INT
    addrTnct As SQLITE_C_INT
End Type

#define SF_Distinct &H00000001
#define SF_All &H00000002
#define SF_Aggregate &H00000008 ' SELECT contains aggregate functions or GROUP BY.
#define SF_Compound &H00000100
#define SF_Values &H00000200
#define SF_MultiValue &H00000400
#define SF_NestedFrom &H00000800 ' SELECT is a nested FROM-clause subquery.
#define SF_PushDown &H01000000 ' A subquery was modified by WHERE push-down.
#define SF_FixedLimit &H00004000 ' nSelectRow was set by a constant LIMIT.
#define SF_Converted &H00010000 ' Compound SELECT rewritten as a subquery.
#define SF_Recursive &H00002000
#define SF_OrderByReqd &H08000000 ' The ORDER BY clause may not be omitted.
#define SF_ComplexResult &H00040000 ' Result contains a subquery or function.
#define SF_OnToWhere &H40000000
#define SF_Correlated &H20000000
#define SRT_Output 7
#define SRT_Exists 1
#define SRT_Discard 2
#define SRT_DistFifo 3
#define SRT_DistQueue 4
#define SRT_Queue 5
#define SRT_Fifo 6
#define SRT_Mem 8
#define SRT_Set 9
#define SRT_EphemTab 10
#define SRT_Coroutine 11
#define SRT_Table 12
#define SRT_Upfrom 13

Declare Sub sqlite3DequoteExpr CDecl Alias "sqlite3DequoteExpr" ( _
    ByVal pExpr As SqliteExpr Ptr _
)
Declare Sub sqlite3DequoteNumber CDecl Alias "sqlite3DequoteNumber" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
)
Declare Function sqlite3ExprAlloc CDecl Alias "sqlite3ExprAlloc" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal pToken As sqlite3ParserToken Ptr, _
    ByVal dequote As SQLITE_C_INT _
) As SqliteExpr Ptr
Declare Function sqlite3ExprDup CDecl Alias "sqlite3ExprDup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pExpr As Const SqliteExpr Ptr, _
    ByVal duplicateFlags As SQLITE_C_INT _
) As SqliteExpr Ptr
Declare Function sqlite3ExprListDup CDecl Alias "sqlite3ExprListDup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pList As Const SqliteExprList Ptr, _
    ByVal duplicateFlags As SQLITE_C_INT _
) As SqliteExprList Ptr
Declare Function sqlite3ExprForVectorField CDecl Alias "sqlite3ExprForVectorField" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pVector As SqliteExpr Ptr, _
    ByVal fieldIndex As SQLITE_C_INT, _
    ByVal fieldCount As SQLITE_C_INT _
) As SqliteExpr Ptr
Declare Function sqlite3SelectDup CDecl Alias "sqlite3SelectDup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pSelect As Const SqliteSelect Ptr, _
    ByVal duplicateFlags As SQLITE_C_INT _
) As SqliteSelect Ptr
Declare Function sqlite3ExprInt32 CDecl Alias "sqlite3ExprInt32" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal value As SQLITE_C_INT _
) As SqliteExpr Ptr
Declare Function sqlite3AffinityType CDecl Alias "sqlite3AffinityType" ( _
    ByVal zType As Const ZString Ptr, _
    ByVal pColumn As Any Ptr _
) As Byte
Declare Function sqlite3PExpr CDecl Alias "sqlite3PExpr" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal pLeft As SqliteExpr Ptr, _
    ByVal pRight As SqliteExpr Ptr _
) As SqliteExpr Ptr
Declare Function sqlite3ExprAnd CDecl Alias "sqlite3ExprAnd" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pLeft As SqliteExpr Ptr, _
    ByVal pRight As SqliteExpr Ptr _
) As SqliteExpr Ptr
Declare Function sqlite3GetTempReg CDecl Alias "sqlite3GetTempReg" ( _
    ByVal pParse As SqliteParseContext Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3ReleaseTempReg CDecl Alias "sqlite3ReleaseTempReg" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal registerNumber As SQLITE_C_INT _
)
Declare Function sqlite3GetTempRange CDecl Alias "sqlite3GetTempRange" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal registerCount As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Sub sqlite3ReleaseTempRange CDecl Alias "sqlite3ReleaseTempRange" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal firstRegister As SQLITE_C_INT, _
    ByVal registerCount As SQLITE_C_INT _
)
Declare Function sqlite3ExprSkipCollateAndLikely CDecl Alias "sqlite3ExprSkipCollateAndLikely" ( _
    ByVal pExpr As SqliteExpr Ptr _
) As SqliteExpr Ptr
Declare Function sqlite3IsTrueOrFalse CDecl Alias "sqlite3IsTrueOrFalse" ( _
    ByVal zValue As Const ZString Ptr _
) As u32
Declare Function sqlite3ExprIdToTrueFalse CDecl Alias "sqlite3ExprIdToTrueFalse" ( _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3ExprTruthValue CDecl Alias "sqlite3ExprTruthValue" ( _
    ByVal pExpr As Const SqliteExpr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3ExprCanBeNull CDecl Alias "sqlite3ExprCanBeNull" ( _
    ByVal pExpr As Const SqliteExpr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3ExprNeedsNoAffinityChange CDecl Alias "sqlite3ExprNeedsNoAffinityChange" ( _
    ByVal pExpr As Const SqliteExpr Ptr, _
    ByVal affinity As Byte _
) As SQLITE_C_INT
Declare Function sqlite3IsRowid CDecl Alias "sqlite3IsRowid" ( _
    ByVal zName As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3ExprIsConstant CDecl Alias "sqlite3ExprIsConstant" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT
Declare Function exprImpliesNotNull CDecl Alias "exprImpliesNotNull" ( _
    ByVal pParse As Const SqliteParseContext Ptr, _
    ByVal pExpr As Const SqliteExpr Ptr, _
    ByVal pNotNullExpr As Const SqliteExpr Ptr, _
    ByVal cursorNumber As SQLITE_C_INT, _
    ByVal seenNonNull As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3ExprListIsConstant CDecl Alias "sqlite3ExprListIsConstant" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pList As SqliteExprList Ptr, _
    ByVal noIsOperators As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3ExprIsConstantOrFunction CDecl Alias "sqlite3ExprIsConstantOrFunction" ( _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal isInit As u8 _
) As SQLITE_C_INT
Declare Function sqlite3ExprIsConstantOrGroupBy CDecl Alias "sqlite3ExprIsConstantOrGroupBy" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal pGroupBy As SqliteExprList Ptr _
) As SQLITE_C_INT
Declare Function sqlite3ExprIsVector CDecl Alias "sqlite3ExprIsVector" ( _
    ByVal pExpr As Const SqliteExpr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3ExprVectorSize CDecl Alias "sqlite3ExprVectorSize" ( _
    ByVal pExpr As Const SqliteExpr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VectorFieldSubexpr CDecl Alias "sqlite3VectorFieldSubexpr" ( _
    ByVal pVector As SqliteExpr Ptr, _
    ByVal fieldIndex As SQLITE_C_INT _
) As SqliteExpr Ptr
Declare Function sqlite3ExprSkipCollate CDecl Alias "sqlite3ExprSkipCollate" ( _
    ByVal pExpr As SqliteExpr Ptr _
) As SqliteExpr Ptr
Declare Function sqlite3ExprAddCollateToken CDecl Alias "sqlite3ExprAddCollateToken" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal pCollationName As Const sqlite3ParserToken Ptr, _
    ByVal dequote As SQLITE_C_INT _
) As SqliteExpr Ptr
Declare Function sqlite3ExprAddCollateString CDecl Alias "sqlite3ExprAddCollateString" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal zCollationName As Const ZString Ptr _
) As SqliteExpr Ptr
Declare Function sqlite3ExprCollSeq CDecl Alias "sqlite3ExprCollSeq" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As Const SqliteExpr Ptr _
) As sqlite3CollSeq Ptr
Declare Function sqlite3ExprNNCollSeq CDecl Alias "sqlite3ExprNNCollSeq" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As Const SqliteExpr Ptr _
) As sqlite3CollSeq Ptr
Declare Function sqlite3ExprCollSeqMatch CDecl Alias "sqlite3ExprCollSeqMatch" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pLeft As Const SqliteExpr Ptr, _
    ByVal pRight As Const SqliteExpr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BinaryCompareCollSeq CDecl Alias "sqlite3BinaryCompareCollSeq" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pLeft As Const SqliteExpr Ptr, _
    ByVal pRight As Const SqliteExpr Ptr _
) As sqlite3CollSeq Ptr
Declare Function sqlite3ExprCompareCollSeq CDecl Alias "sqlite3ExprCompareCollSeq" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As Const SqliteExpr Ptr _
) As sqlite3CollSeq Ptr
Declare Function sqlite3GetCollSeq CDecl Alias "sqlite3GetCollSeq" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal eTextRep As u8, _
    ByVal pCollation As sqlite3CollSeq Ptr, _
    ByVal zName As Const ZString Ptr _
) As sqlite3CollSeq Ptr
Declare Function sqlite3CheckCollSeq CDecl Alias "sqlite3CheckCollSeq" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pCollation As sqlite3CollSeq Ptr _
) As SQLITE_C_INT
Declare Function sqlite3ExprCompare CDecl Alias "sqlite3ExprCompare" ( _
    ByVal pParse As Any Ptr, _
    ByVal pLeft As Const SqliteExpr Ptr, _
    ByVal pRight As Const SqliteExpr Ptr, _
    ByVal tableCursor As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3ExprListCompare CDecl Alias "sqlite3ExprListCompare" ( _
    ByVal pLeft As Const SqliteExprList Ptr, _
    ByVal pRight As Const SqliteExprList Ptr, _
    ByVal tableCursor As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3ExprCompareSkip CDecl Alias "sqlite3ExprCompareSkip" ( _
    ByVal pLeft As SqliteExpr Ptr, _
    ByVal pRight As SqliteExpr Ptr, _
    ByVal tableCursor As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3ExprIsInteger CDecl Alias "sqlite3ExprIsInteger" ( _
    ByVal pExpr As Const SqliteExpr Ptr, _
    ByVal pValue As SQLITE_C_INT Ptr, _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal reprepareSmallInteger As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3ExprDeferredDelete CDecl Alias "sqlite3ExprDeferredDelete" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3ExprSetErrorOffset CDecl Alias "sqlite3ExprSetErrorOffset" ( _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal byteOffset As SQLITE_C_INT _
)
Declare Function sqlite3ExprAssignVarNumber CDecl Alias "sqlite3ExprAssignVarNumber" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal tokenLength As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Sub sqlite3ExprDelete CDecl Alias "sqlite3ExprDelete" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
)
Declare Sub sqlite3ExprDeleteGeneric CDecl Alias "sqlite3ExprDeleteGeneric" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pExpr As Any Ptr _
)
Declare Function sqlite3ExprListAppend CDecl Alias "sqlite3ExprListAppend" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pList As SqliteExprList Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SqliteExprList Ptr
Declare Sub sqlite3ExprListDelete CDecl Alias "sqlite3ExprListDelete" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pList As SqliteExprList Ptr _
)
Declare Sub sqlite3ExprListSetName CDecl Alias "sqlite3ExprListSetName" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pList As SqliteExprList Ptr, _
    ByVal pName As sqlite3ParserToken Ptr, _
    ByVal dequote As SQLITE_C_INT _
)
Declare Sub sqlite3ExprListSetSpan CDecl Alias "sqlite3ExprListSetSpan" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pList As SqliteExprList Ptr, _
    ByVal zStart As Const UByte Ptr, _
    ByVal zEnd As Const UByte Ptr _
)
Declare Sub sqlite3ExprSetHeightAndFlags CDecl Alias "sqlite3ExprSetHeightAndFlags" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
)
Declare Function sqlite3ExprCheckHeight CDecl Alias "sqlite3ExprCheckHeight" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal height As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3SelectExprHeight CDecl Alias "sqlite3SelectExprHeight" ( _
    ByVal pSelect As Const SqliteSelect Ptr _
) As SQLITE_C_INT
Declare Function sqlite3SelectNew CDecl Alias "sqlite3SelectNew" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pEList As SqliteExprList Ptr, _
    ByVal pSrc As Any Ptr, _
    ByVal pWhere As SqliteExpr Ptr, _
    ByVal pGroupBy As SqliteExprList Ptr, _
    ByVal pHaving As SqliteExpr Ptr, _
    ByVal pOrderBy As SqliteExprList Ptr, _
    ByVal flags As u32, _
    ByVal pLimit As SqliteExpr Ptr _
) As SqliteSelect Ptr
Declare Sub sqlite3SelectDelete CDecl Alias "sqlite3SelectDelete" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
)
Declare Sub sqlite3ClearTempRegCache CDecl Alias "sqlite3ClearTempRegCache" ( _
    ByVal pParse As SqliteParseContext Ptr _
)
Declare Sub sqlite3TouchRegister CDecl Alias "sqlite3TouchRegister" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal registerIndex As SQLITE_C_INT _
)
Declare Function sqlite3Select CDecl Alias "sqlite3Select" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pDestination As SqliteSelectDest Ptr _
) As SQLITE_C_INT
Declare Function sqlite3SelectCompileCompound CDecl Alias "sqlite3SelectCompileCompound" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pDestination As SqliteSelectDest Ptr _
) As SQLITE_C_INT
Declare Function sqlite3SelectEmitInternalRow CDecl Alias "sqlite3SelectEmitInternalRow" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pDestination As SqliteSelectDest Ptr, _
    ByVal continueLabel As SQLITE_C_INT, _
    ByVal breakLabel As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3MultiValues CDecl Alias "sqlite3MultiValues" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pLeft As SqliteSelect Ptr, _
    ByVal pRow As SqliteExprList Ptr _
) As SqliteSelect Ptr
Declare Sub sqlite3MultiValuesEnd CDecl Alias "sqlite3MultiValuesEnd" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pValues As SqliteSelect Ptr _
)

#endif

/' end of sqlite3_expr_types.bi '/
