/'
    Project: SQLite FreeBASIC port

    File: sqlite3_parser_token.bi

    Purpose:

        Define the token value passed between SQLite's tokenizer and parser.

    Responsibilities:

        - Preserve the C layout of Token for parser ABI declarations.
        - Keep token data as a borrowed byte span into the SQL input.

    This file intentionally does NOT contain:

        - Parser stack state or grammar semantic values.
        - Ownership of the input SQL string.
'/ 

#ifndef SQLITE3_FB_PARSER_TOKEN_BI
#define SQLITE3_FB_PARSER_TOKEN_BI

#include once "sqlite3_types.bi"

Type sqlite3ParserToken
    ' Borrowed span into SQL text. Parser code must treat it as read-only.
    z As UByte Ptr
    n As u32
End Type

#endif

/' end of sqlite3_parser_token.bi '/
