/'
    Project: SQLite FreeBASIC port

    File: sqlite3_resolve_types.bi

    Purpose:

        Define the NameContext record used during expression resolution.

    Responsibilities:

        - Preserve the NameContext field order and union extent.
        - Reuse the parser, source-list, expression-list, upsert, and SELECT types.

    This file intentionally does NOT contain:

        - Name lookup or aggregate analysis behavior.
        - SELECT preparation or expression resolution.
'/

#ifndef SQLITE3_FB_RESOLVE_TYPES_BI
#define SQLITE3_FB_RESOLVE_TYPES_BI

#include once "sqlite3_where_types.bi"
#include once "sqlite3_agginfo_types.bi"

Union SqliteNameContextUnion
    pEList As SqliteExprList Ptr
    pAggInfo As SqliteAggInfo Ptr
    pUpsert As SqliteUpsert Ptr
    iBaseReg As SQLITE_C_INT
End Union

Type SqliteNameContext
    pParse As SqliteParseContext Ptr
    pSrcList As SqliteSrcList Ptr
    uNC As SqliteNameContextUnion
    pNext As SqliteNameContext Ptr
    nRef As SQLITE_C_INT
    nNcErr As SQLITE_C_INT
    ncFlags As SQLITE_C_INT
    nNestedSelect As u32
    pWinSelect As SqliteSelect Ptr
End Type

Declare Sub resolveSetExprSubtypeArg CDecl Alias "resolveSetExprSubtypeArg" ( _
    ByVal pExpressionList As SqliteExprList Ptr _
)
Declare Sub resolveAlias CDecl Alias "resolveAlias" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpressionList As SqliteExprList Ptr, _
    ByVal columnIndex As SQLITE_C_INT, _
    ByVal pExpression As SqliteExpr Ptr, _
    ByVal subqueryDepth As SQLITE_C_INT _
)
Declare Function lookupName CDecl Alias "lookupName" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal zDatabase As Const ZString Ptr, _
    ByVal zTable As Const ZString Ptr, _
    ByVal pRight As Const SqliteExpr Ptr, _
    ByVal pNameContext As SqliteNameContext Ptr, _
    ByVal pExpression As SqliteExpr Ptr _
) As SQLITE_C_INT
Declare Sub windowRemoveExprFromSelect CDecl Alias "windowRemoveExprFromSelect" ( _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pExpression As SqliteExpr Ptr _
)
Declare Function isValidSchemaTableName CDecl Alias "isValidSchemaTableName" ( _
    ByVal zTable As Const ZString Ptr, _
    ByVal pTable As SqliteTable Ptr, _
    ByVal zDatabase As Const ZString Ptr _
) As SQLITE_C_INT

#endif

/' end of sqlite3_resolve_types.bi '/
