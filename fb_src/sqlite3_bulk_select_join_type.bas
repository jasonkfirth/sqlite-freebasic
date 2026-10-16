/'
** 2001 September 15
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
*************************************************************************
** This module parses the join-type tokens that precede a JOIN clause.
'/

/' ------------------------------------------------------------------------- '/
/' SQLite FreeBASIC port                                                      '/
/' ------------------------------------------------------------------------- '/

/' Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_bulk_select_join_type.bas

    Purpose:

        Translate JOIN keywords into SQLite's join-type bitmask.

    Responsibilities:

        - Match the three parser tokens against SQLite's accepted join words.
        - Reject incompatible INNER, OUTER, LEFT, RIGHT, FULL, and CROSS terms.
        - Preserve SQLite's parser error text for invalid join combinations.

    This file intentionally does NOT contain:

        - Parsing or construction of the surrounding FROM clause.
'/

#lang "fb"

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_parser_token.bi"
#include once "sqlite3_walker.bi"
#include once "sqlite3_debug_assert.bi"

Declare Function sqlite3_strnicmp CDecl Alias "sqlite3_strnicmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr, _
    ByVal byteCount As SQLITE_C_INT _
) As SQLITE_C_INT

Private Function joinTypeTokenMask( _
    ByVal pToken As Const sqlite3ParserToken Ptr _
) As SQLITE_C_INT
    If pToken = 0 OrElse pToken->z = 0 Then Return JT_ERROR

    Dim zToken As Const ZString Ptr = _
        CPtr(Const ZString Ptr, pToken->z)

    Select Case pToken->n
    Case 4
        If sqlite3_strnicmp(zToken, StrPtr("LEFT"), 4) = 0 Then _
            Return JT_LEFT Or JT_OUTER
        If sqlite3_strnicmp(zToken, StrPtr("FULL"), 4) = 0 Then _
            Return JT_LEFT Or JT_RIGHT Or JT_OUTER
    Case 5
        If sqlite3_strnicmp(zToken, StrPtr("OUTER"), 5) = 0 Then _
            Return JT_OUTER
        If sqlite3_strnicmp(zToken, StrPtr("RIGHT"), 5) = 0 Then _
            Return JT_RIGHT Or JT_OUTER
        If sqlite3_strnicmp(zToken, StrPtr("INNER"), 5) = 0 Then _
            Return JT_INNER
        If sqlite3_strnicmp(zToken, StrPtr("CROSS"), 5) = 0 Then _
            Return JT_INNER Or JT_CROSS
    Case 7
        If sqlite3_strnicmp(zToken, StrPtr("NATURAL"), 7) = 0 Then _
            Return JT_NATURAL
    End Select

    Return JT_ERROR
End Function

Function sqlite3JoinType CDecl Alias "sqlite3JoinType" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pA As sqlite3ParserToken Ptr, _
    ByVal pB As sqlite3ParserToken Ptr, _
    ByVal pC As sqlite3ParserToken Ptr _
) As SQLITE_C_INT
    Dim aToken(0 To 2) As sqlite3ParserToken Ptr
    aToken(0) = pA
    aToken(1) = pB
    aToken(2) = pC

    Dim jointype As SQLITE_C_INT = 0
    For tokenIndex As SQLITE_C_INT = 0 To 2
        Dim pToken As sqlite3ParserToken Ptr = aToken(tokenIndex)
        If pToken = 0 Then Exit For
        jointype = jointype Or joinTypeTokenMask(pToken)
        If (jointype And JT_ERROR) <> 0 Then Exit For
    Next

    Dim hasInvalidCombination As SQLITE_C_INT = 0
    If (jointype And (JT_INNER Or JT_OUTER)) = (JT_INNER Or JT_OUTER) Then _
        hasInvalidCombination = 1
    If (jointype And JT_ERROR) <> 0 Then hasInvalidCombination = 1
    If (jointype And (JT_OUTER Or JT_LEFT Or JT_RIGHT)) = JT_OUTER Then _
        hasInvalidCombination = 1

    If hasInvalidCombination <> 0 Then
        If pParse = 0 Then
#ifdef SQLITE_DEBUG
            sqlite3DebugAssert(StrPtr("invalid JOIN type has a parser context"))
#endif
            Return JT_INNER
        End If

        Dim zFirstSpace As Const ZString Ptr = StrPtr(" ")
        Dim zSecondSpace As Const ZString Ptr = StrPtr(" ")
        If pB = 0 Then zFirstSpace = StrPtr("")
        If pC = 0 Then zSecondSpace = StrPtr("")
        sqlite3ErrorMsg(pParse, StrPtr("unknown join type: %T%s%T%s%T"), _
            pA, zFirstSpace, pB, zSecondSpace, pC)
        jointype = JT_INNER
    End If

    Return jointype
End Function

/' end of sqlite3_bulk_select_join_type.bas '/
