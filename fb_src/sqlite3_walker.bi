/'
    Project: SQLite FreeBASIC port

    File: sqlite3_walker.bi

    Purpose:

        Define the callback state and source-list layouts used by tree walks.

    Responsibilities:

        - Match the Walker callback and traversal state field order.
        - Preserve the database-fixer context embedded in Walker callbacks.
        - Define the feature-gated cursor-hint context carried through Walker.u.
        - Provide SrcItem, Subquery, CTE, and Window fields plus source-item flag masks.
        - Declare expression and SELECT tree-walking entry points.

    This file intentionally does NOT contain:

        - Name resolution, schema repair, or window-function execution.
'/ 

#ifndef SQLITE3_FB_WALKER_BI
#define SQLITE3_FB_WALKER_BI

#include once "sqlite3_expr_types.bi"
#include once "sqlite3_window_state.bi"

#define WRC_CONTINUE 0
#define WRC_PRUNE 1
#define WRC_ABORT 2

#define M10D_YES 0
#define M10D_ANY 1
#define M10D_NO 2

' Join masks used by single-source constraint checks in expr.c.
#define JT_LEFT &H08
#define JT_NATURAL &H04
#define JT_RIGHT &H10
#define JT_OUTER &H20
#define JT_INNER &H01
#define JT_CROSS &H02
#define JT_ERROR &H80
#define JT_LTORJ &H40

' Bit positions in SrcItem.fg after its one-byte jointype field.
#define SRCITEM_IS_SUBQUERY &H00000004
#define SRCITEM_IS_CORRELATED &H00000010
#define SRCITEM_IS_MATERIALIZED &H00000020
#define SRCITEM_VIA_COROUTINE &H00000040
#define SRCITEM_IS_TABFUNC &H00000008
#define SRCITEM_IS_RECURSIVE &H00000080
#define SRCITEM_FROM_DDL &H00000100
#define SRCITEM_IS_CTE &H00000200
#define SRCITEM_NOT_CTE &H00000400
#define SRCITEM_IS_USING &H00000800
#define SRCITEM_IS_ON &H00001000
#define SRCITEM_IS_SYNTH_USING &H00002000
#define SRCITEM_IS_NESTED_FROM &H00004000 ' Subquery belongs to a parenthesized FROM item.
#define SRCITEM_FIXED_SCHEMA &H00010000
#define SRCITEM_HAD_SCHEMA &H00020000

#ifndef EP_WinFunc
#define EP_WinFunc &H01000000
#endif

Type SqliteWalkerExprCallback As Function CDecl ( _
    ByVal pWalker As Any Ptr, _
    ByVal pExpr As Any Ptr _
) As SQLITE_C_INT
Type SqliteWalkerSelectCallback As Function CDecl ( _
    ByVal pWalker As Any Ptr, _
    ByVal pSelect As Any Ptr _
) As SQLITE_C_INT
Type SqliteWalkerSelectCallback2 As Sub CDecl ( _
    ByVal pWalker As Any Ptr, _
    ByVal pSelect As Any Ptr _
)

#ifdef SQLITE_ENABLE_CURSOR_HINTS
' Stack context passed through Walker.u while building OP_CursorHint expressions.
Type SqliteCursorHint
    iTabCur As SQLITE_C_INT
    iIdxCur As SQLITE_C_INT
    pIdx As Any Ptr
End Type
#endif

Union SqliteWalkerExtra
    p As Any Ptr
    n As SQLITE_C_INT
    iCur As SQLITE_C_INT
    sz As SQLITE_C_INT
    pSrcList As Any Ptr
    aiCol As SQLITE_C_INT Ptr
    pGroupBy As SqliteExprList Ptr
    pSelect As SqliteSelect Ptr
    pSrcItem As Any Ptr
    pCCurHint As Any Ptr
    pRefSrcList As Any Ptr
    pIdxCover As Any Ptr
    pRewrite As Any Ptr
    pConst As Any Ptr
    pNC As Any Ptr
    pRename As Any Ptr
    pTab As Any Ptr
    pCovIdxCk As Any Ptr
    pFix As Any Ptr
    aMem As Any Ptr
    pCheckOnCtx As Any Ptr
End Union

Type SqliteWalker
    pParse As SqliteParseContext Ptr
    xExprCallback As SqliteWalkerExprCallback
    xSelectCallback As SqliteWalkerSelectCallback
    xSelectCallback2 As SqliteWalkerSelectCallback2
    walkerDepth As SQLITE_C_INT
    eCode As UShort
    mWFlags As UShort
    u As SqliteWalkerExtra
End Type

' DbFixer carries the Walker state used to pin schema references in stored SQL.
Type SqliteDbFixer
    pParse As SqliteParseContext Ptr
    w As SqliteWalker
    pSchema As SqliteSchema Ptr
    bTemp As UByte
    zDb As Const ZString Ptr
    zType As Const ZString Ptr
    pName As sqlite3ParserToken Ptr
End Type

' Subquery keeps pSelect first so the walker only depends on its stable prefix.
Type SqliteWalkerSubquery
    pSelect As SqliteSelect Ptr
    addrFillSub As SQLITE_C_INT
    regReturn As SQLITE_C_INT
    regResult As SQLITE_C_INT
End Type

' CteUse lasts through code generation and is released by parser cleanup.
Type SqliteCteUse
    nUse As SQLITE_C_INT
    addrM9e As SQLITE_C_INT
    regRtn As SQLITE_C_INT
    iCur As SQLITE_C_INT
    nRowEst As Short
    eM10d As u8
End Type

Type SqliteCte
    zName As ZString Ptr
    pCols As SqliteExprList Ptr
    pSelect As SqliteSelect Ptr
    zCteErr As Const ZString Ptr
    pUse As SqliteCteUse Ptr
    eM10d As u8
End Type

' With is represented by a one-element Cte placeholder for flexible-array size
' arithmetic; SqliteSelect refers to this type through its forward alias.
Type SqliteWithRecord
    nCte As SQLITE_C_INT
    bView As SQLITE_C_INT
    pOuter As Any Ptr
    a(0 To 0) As SqliteCte
End Type

Type SqliteSrcItemFlags
    jointype As u8
    ' SQLite stores the following C bitfields in one unsigned int.
    flags As SQLITE_C_UINT
End Type

Union SqliteSrcItemUnion1
    zIndexedBy As ZString Ptr
    pFuncArg As SqliteExprList Ptr
    nRow As u32
End Union

Union SqliteSrcItemUnion2
    pIBIndex As SqliteIndex Ptr
    pCteUse As SqliteCteUse Ptr
End Union

Union SqliteSrcItemOnUsing
    pOn As SqliteExpr Ptr
    pUsing As SqliteIdList Ptr
End Union

Union SqliteSrcItemUnion4
    pSchema As SqliteSchema Ptr
    zDatabase As ZString Ptr
    pSubq As SqliteSubquery Ptr
End Union

' The other union members remain opaque because tree walking only reads the
' function-argument and subquery pointers.
Type SqliteSrcItem
    zName As ZString Ptr
    zAlias As ZString Ptr
    pSTab As SqliteTable Ptr
    fg As SqliteSrcItemFlags
    iCursor As SQLITE_C_INT
    colUsed As sqlite3_uint64
    u1 As SqliteSrcItemUnion1
    u2 As SqliteSrcItemUnion2
    u3 As SqliteSrcItemOnUsing
    u4 As SqliteSrcItemUnion4
End Type

#ifndef SQLITE_OMIT_WINDOWFUNC
Type SqliteWalkerWindow
    zName As ZString Ptr
    zBase As ZString Ptr
    pPartition As SqliteExprList Ptr
    pOrderBy As SqliteExprList Ptr
    eFrmType As u8
    eStart As u8
    eEnd As u8
    bImplicitFrame As u8
    eExclude As u8
    pStart As SqliteExpr Ptr
    pEnd As SqliteExpr Ptr
    ppThis As Any Ptr
    pNextWin As SqliteWalkerWindow Ptr
    pFilter As SqliteExpr Ptr
    pWFunc As Any Ptr
    iEphCsr As SQLITE_C_INT
    regAccum As SQLITE_C_INT
    regResult As SQLITE_C_INT
    csrApp As SQLITE_C_INT
    regApp As SQLITE_C_INT
    regPart As SQLITE_C_INT
    pOwner As SqliteExpr Ptr
    nBufferCol As SQLITE_C_INT
    iArgCol As SQLITE_C_INT
    regOne As SQLITE_C_INT
    regStartRowid As SQLITE_C_INT
    regEndRowid As SQLITE_C_INT
    bExprArgs As u8
End Type

#endif

Declare Function sqlite3WalkExpr CDecl Alias "sqlite3WalkExpr" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3WalkExprNN CDecl Alias "sqlite3WalkExprNN" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3WalkExprList CDecl Alias "sqlite3WalkExprList" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pList As SqliteExprList Ptr _
) As SQLITE_C_INT
Declare Function sqlite3WalkSelect CDecl Alias "sqlite3WalkSelect" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) As SQLITE_C_INT
Declare Function sqlite3WalkSelectExpr CDecl Alias "sqlite3WalkSelectExpr" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) As SQLITE_C_INT
Declare Function sqlite3WalkSelectFrom CDecl Alias "sqlite3WalkSelectFrom" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) As SQLITE_C_INT
Declare Function sqlite3ExprWalkNoop CDecl Alias "sqlite3ExprWalkNoop" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3SelectWalkNoop CDecl Alias "sqlite3SelectWalkNoop" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) As SQLITE_C_INT
Declare Function sqlite3SelectWalkFail CDecl Alias "sqlite3SelectWalkFail" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) As SQLITE_C_INT
Declare Function sqlite3WalkerDepthIncrease CDecl Alias "sqlite3WalkerDepthIncrease" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3WalkerDepthDecrease CDecl Alias "sqlite3WalkerDepthDecrease" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
)
Declare Sub sqlite3WalkWinDefnDummyCallback CDecl Alias "sqlite3WalkWinDefnDummyCallback" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
)
Declare Sub sqlite3SelectPopWith CDecl Alias "sqlite3SelectPopWith" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
)
Declare Function sqlite3WithDup CDecl Alias "sqlite3WithDup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pWith As Const SqliteWith Ptr _
) As SqliteWith Ptr
Declare Sub sqlite3WithDelete CDecl Alias "sqlite3WithDelete" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pWith As SqliteWith Ptr _
)
Declare Sub sqlite3WithDeleteGeneric CDecl Alias "sqlite3WithDeleteGeneric" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pWith As Any Ptr _
)
Declare Sub sqlite3CteDelete CDecl Alias "sqlite3CteDelete" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pCte As SqliteCte Ptr _
)
Declare Function sqlite3NameFromToken CDecl Alias "sqlite3NameFromToken" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pName As Const sqlite3ParserToken Ptr _
) As ZString Ptr
Declare Function sqlite3CteNew CDecl Alias "sqlite3CteNew" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pName As Const sqlite3ParserToken Ptr, _
    ByVal pColumns As SqliteExprList Ptr, _
    ByVal pQuery As SqliteSelect Ptr, _
    ByVal materialization As u8 _
) As SqliteCte Ptr
Declare Function sqlite3WithAdd CDecl Alias "sqlite3WithAdd" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pWith As SqliteWith Ptr, _
    ByVal pCte As SqliteCte Ptr _
) As SqliteWith Ptr
Declare Function sqlite3WithPush CDecl Alias "sqlite3WithPush" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pWith As SqliteWith Ptr, _
    ByVal freeWith As u8 _
) As SqliteWith Ptr
Declare Function sqlite3SelectOpName CDecl Alias "sqlite3SelectOpName" ( _
    ByVal selectOpcode As SQLITE_C_INT _
) As Const ZString Ptr
Declare Function sqlite3ProcessJoin CDecl Alias "sqlite3ProcessJoin" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) As SQLITE_C_INT
Declare Function sqlite3ExprIsSingleTableConstraint CDecl Alias "sqlite3ExprIsSingleTableConstraint" ( _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal pSourceList As Any Ptr, _
    ByVal sourceIndex As SQLITE_C_INT, _
    ByVal allowSubquery As SQLITE_C_INT _
) As SQLITE_C_INT

#endif

/' end of sqlite3_walker.bi '/
