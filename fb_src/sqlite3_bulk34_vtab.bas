/'
    Project: SQLite FreeBASIC port

    File: sqlite3_bulk34_vtab.bas

    Purpose:

        Implement the virtual-table collation lookup from src/where.c.

    Responsibilities:

        - Find the WHERE term associated with a virtual-table constraint.
        - Resolve its comparison collation for the xBestIndex callback.

    This file intentionally does NOT contain:

        - Allocation of sqlite3_index_info or its private planner tail.
        - A claim that compile acceptance establishes behavior parity.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_vtab_types.bi"

Private Function vtabTermFromWhereClause( _
    ByVal pWhereClause As SqliteWhereClause Ptr, _
    ByVal termOffset As SQLITE_C_INT _
) As SqliteWhereTerm Ptr
    If termOffset < 0 Then Return 0

    Dim pCurrent As SqliteWhereClause Ptr = pWhereClause
    Dim offset As SQLITE_C_INT = termOffset
    While pCurrent <> 0
        If pCurrent->nTerm < 0 Then Return 0
        If offset < pCurrent->nTerm Then
            If pCurrent->a = 0 Then Return 0
            Return CPtr(SqliteWhereTerm Ptr, pCurrent->a) + offset
        End If
        offset -= pCurrent->nTerm
        pCurrent = CPtr(SqliteWhereClause Ptr, pCurrent->pOuter)
    Wend
    Return 0
End Function

Function sqlite3_vtab_collation CDecl Alias "sqlite3_vtab_collation" ( _
    ByVal pIndexInfo As SqliteIndexInfo Ptr, _
    ByVal constraintIndex As SQLITE_C_INT _
) As Const ZString Ptr Export
    If pIndexInfo = 0 OrElse constraintIndex < 0 OrElse _
       constraintIndex >= pIndexInfo->nConstraint OrElse _
       pIndexInfo->aConstraint = 0 Then Return 0

    ' SQLite appends HiddenIndexInfo immediately after the public API record.
    Dim pHidden As SqliteHiddenIndexInfo Ptr = CPtr( _
        SqliteHiddenIndexInfo Ptr, _
        CPtr(UByte Ptr, pIndexInfo) + SizeOf(SqliteIndexInfo))
    Dim termIndex As SQLITE_C_INT = _
        pIndexInfo->aConstraint[constraintIndex].iTermOffset
    Dim pTerm As SqliteWhereTerm Ptr = _
        vtabTermFromWhereClause(CPtr(SqliteWhereClause Ptr, pHidden->pWC), termIndex)
    If pTerm = 0 OrElse pTerm->pExpr = 0 Then Return 0

    Dim pExpression As Const SqliteExpr Ptr = _
        CPtr(Const SqliteExpr Ptr, pTerm->pExpr)
    If pExpression->pLeft = 0 Then Return StrPtr("BINARY")

    Dim pParse As SqliteParseContext Ptr = _
        CPtr(SqliteParseContext Ptr, pHidden->pParse)
    Dim pCollation As sqlite3CollSeq Ptr = _
        sqlite3ExprCompareCollSeq(pParse, pExpression)
    If pCollation <> 0 Then Return pCollation->zName
    Return StrPtr("BINARY")
End Function

/' end of sqlite3_bulk34_vtab.bas '/
