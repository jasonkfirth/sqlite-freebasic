/'
    Project: SQLite FreeBASIC port

    File: sqlite3_where_helpers.bas

    Purpose:

        Preserve small query-planner helpers that can be ported independently.

    Responsibilities:

        - Convert a logarithmic row estimate into an approximate base-2 log.
        - Check whether a virtual-table constraint array is fully assigned.
        - Map MATCH, GLOB, LIKE, and REGEXP calls to virtual-table operators.

    This file intentionally does NOT contain:

        - WHERE-clause planning, loop selection, or VDBE code generation.
'/

#lang "fb"
#include once "sqlite3_util_numeric.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_expr_types.bi"

Declare Function sqlite3StrICmp CDecl Alias "sqlite3StrICmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT

Private Function estLog CDecl Alias "estLog" (ByVal inputEstimate As Short) As Short
    If inputEstimate <= 10 Then Return 0
    Return sqlite3LogEst(CULngInt(inputEstimate)) - 33
End Function

Private Function allConstraintsUsed( _
    ByVal usage As SqliteIndexConstraintUsage Ptr, _
    ByVal constraintCount As SQLITE_C_INT _
) As SQLITE_C_INT
    If constraintCount <= 0 Then Return 1
    If usage = 0 Then Return 0

    For ii As Long = 0 To constraintCount - 1
        If usage[ii].argvIndex <= 0 Then Return 0
    Next

    Return 1
End Function

Function sqlite3ExprIsLikeOperator CDecl Alias "sqlite3ExprIsLikeOperator" ( _
    ByVal pExprArgument As Any Ptr _
) As SQLITE_C_INT
    Dim pExpr As Const SqliteExpr Ptr = _
        CPtr(Const SqliteExpr Ptr, pExprArgument)
    If pExpr = 0 OrElse pExpr->op <> TK_FUNCTION Then Return 0
    Dim zName As Const ZString Ptr = _
        CPtr(Const ZString Ptr, pExpr->u.zToken)
    If zName = 0 Then Return 0

    If sqlite3StrICmp(zName, StrPtr(!"match")) = 0 Then _
        Return SQLITE_INDEX_CONSTRAINT_MATCH
    If sqlite3StrICmp(zName, StrPtr(!"glob")) = 0 Then _
        Return SQLITE_INDEX_CONSTRAINT_GLOB
    If sqlite3StrICmp(zName, StrPtr(!"like")) = 0 Then _
        Return SQLITE_INDEX_CONSTRAINT_LIKE
    If sqlite3StrICmp(zName, StrPtr(!"regexp")) = 0 Then _
        Return SQLITE_INDEX_CONSTRAINT_REGEXP

    Return 0
End Function

/' end of sqlite3_where_helpers.bas '/
