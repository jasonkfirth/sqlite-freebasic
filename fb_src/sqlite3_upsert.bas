/'
** 2018-04-12
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
*************************************************************************
** This file contains code to implement various aspects of UPSERT
** processing and handling of the Upsert object.
'/ 
/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_upsert.bas

    Purpose:

        Release the AST and auxiliary allocations owned by ON CONFLICT clauses.

    Responsibilities:

        - Delete every Upsert node in a linked conflict-action list.
        - Release each expression list, expression, auxiliary allocation, and node.

    This file intentionally does NOT contain:

        - UPSERT parsing, name resolution, or VDBE code generation.
        - A claim that memory-layout compilation establishes runtime parity.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_expr_types.bi"

#ifndef SQLITE_OMIT_UPSERT

/' -------------------------------------------------------------------------
    Upsert list cleanup
------------------------------------------------------------------------- '/

Private Sub upsertDelete(ByVal db As sqlite3 Ptr, ByVal pUpsert As SqliteUpsert Ptr)
    While pUpsert <> 0
        Dim pNext As SqliteUpsert Ptr = pUpsert->pNextUpsert
        sqlite3ExprListDelete(db, CPtr(SqliteExprList Ptr, pUpsert->pUpsertTarget))
        sqlite3ExprDelete(db, CPtr(SqliteExpr Ptr, pUpsert->pUpsertTargetWhere))
        sqlite3ExprListDelete(db, CPtr(SqliteExprList Ptr, pUpsert->pUpsertSet))
        sqlite3ExprDelete(db, CPtr(SqliteExpr Ptr, pUpsert->pUpsertWhere))
        sqlite3DbFree(db, pUpsert->pToFree)
        sqlite3DbFree(db, pUpsert)
        pUpsert = pNext
    Wend
End Sub

Sub sqlite3UpsertDelete CDecl Alias "sqlite3UpsertDelete" ( _
    ByVal dbArgument As Any Ptr, _
    ByVal upsertArgument As Any Ptr _
)
    Dim db As sqlite3 Ptr = CPtr(sqlite3 Ptr, dbArgument)
    Dim pUpsert As SqliteUpsert Ptr = _
        CPtr(SqliteUpsert Ptr, upsertArgument)
    If db = 0 OrElse pUpsert = 0 Then Return
    upsertDelete(db, pUpsert)
End Sub

Function sqlite3UpsertNew CDecl Alias "sqlite3UpsertNew" ( _
    ByVal dbArgument As Any Ptr, _
    ByVal targetArgument As Any Ptr, _
    ByVal targetWhereArgument As Any Ptr, _
    ByVal setArgument As Any Ptr, _
    ByVal whereArgument As Any Ptr, _
    ByVal nextArgument As Any Ptr _
) As Any Ptr
    Dim db As sqlite3 Ptr = CPtr(sqlite3 Ptr, dbArgument)
    Dim pTarget As SqliteExprList Ptr = _
        CPtr(SqliteExprList Ptr, targetArgument)
    Dim pTargetWhere As SqliteExpr Ptr = _
        CPtr(SqliteExpr Ptr, targetWhereArgument)
    Dim pSetList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, setArgument)
    Dim pWhere As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, whereArgument)
    Dim pNext As SqliteUpsert Ptr = CPtr(SqliteUpsert Ptr, nextArgument)
    If db = 0 Then Return 0

    Dim pNew As SqliteUpsert Ptr = CPtr(SqliteUpsert Ptr, _
        sqlite3DbMallocZero(db, SizeOf(SqliteUpsert)))
    If pNew = 0 Then
        sqlite3ExprListDelete(db, pTarget)
        sqlite3ExprDelete(db, pTargetWhere)
        sqlite3ExprListDelete(db, pSetList)
        sqlite3ExprDelete(db, pWhere)
        sqlite3UpsertDelete(db, pNext)
        Return 0
    End If

    pNew->pUpsertTarget = pTarget
    pNew->pUpsertTargetWhere = pTargetWhere
    pNew->pUpsertSet = pSetList
    pNew->pUpsertWhere = pWhere
    pNew->pNextUpsert = pNext
    pNew->isDoUpdate = IIf(pSetList <> 0, 1, 0)
    Return pNew
End Function

#endif

/' end of sqlite3_upsert.bas '/
