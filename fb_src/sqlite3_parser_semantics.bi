/'
    Project: SQLite FreeBASIC port

    File: sqlite3_parser_semantics.bi

    Purpose:

        Declare the Lemon reduction-action interface.

    Responsibilities:

        - Pass parser-rule reductions to FreeBASIC semantic handlers.
        - Return the semantic value for the reduced nonterminal.

    This file intentionally does NOT contain:

        - The grammar tables or the individual reduction implementations.
'/ 

#ifndef SQLITE3_FB_PARSER_SEMANTICS_BI
#define SQLITE3_FB_PARSER_SEMANTICS_BI

#include once "sqlite3_expr_types.bi"

Declare Function sqlite3ParserSemanticReduce CDecl Alias "sqlite3ParserSemanticReduce" ( _
    ByVal pParser As sqlite3ParserState Ptr, _
    ByVal ruleNumber As SQLITE_C_INT, _
    ByVal rhsCount As SQLITE_C_INT, _
    ByVal lookahead As sqlite3ParserToken, _
    ByVal pResult As sqlite3ParserMinor Ptr _
) As SQLITE_C_INT

#endif

/' end of sqlite3_parser_semantics.bi '/
