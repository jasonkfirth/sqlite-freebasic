/'
    Project: SQLite FreeBASIC port

    File: sqlite3_parser_cleanup.bas

    Purpose:

        Defer uncommon parser-owned destructors until statement preparation ends.

    Responsibilities:

        - Store cleanup callbacks in a per-parse LIFO list.
        - Run callbacks exactly once before the parse context is released.
        - Perform cleanup immediately and mark OOM when list allocation fails.

    This file intentionally does NOT contain:

        - Lemon stack destructors for grammar semantic values.
        - Cleanup of the VDBE or its expression tree after ownership transfer.
'/

#lang "fb"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_fault.bi"

Function sqlite3ParserAddCleanup CDecl Alias "sqlite3ParserAddCleanup" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal xCleanup As SqliteParserCleanupCallback, _
    ByVal pArgument As Any Ptr _
) As Any Ptr Export
    If xCleanup = 0 Then Return pArgument
    If pParse = 0 OrElse pParse->db = 0 Then
        xCleanup(0, pArgument)
        Return 0
    End If

    Dim db As sqlite3 Ptr = pParse->db
    Dim pCleanup As SqliteParserCleanup Ptr = 0
    If sqlite3FaultSim(300) <> 0 Then
        sqlite3OomFault(db)
    Else
        pCleanup = CPtr(SqliteParserCleanup Ptr, _
            sqlite3DbMallocRaw(db, SizeOf(SqliteParserCleanup)))
    End If

    If pCleanup <> 0 Then
        pCleanup->pNext = pParse->pCleanup
        pCleanup->pPtr = pArgument
        pCleanup->xCleanup = xCleanup
        pParse->pCleanup = pCleanup
        Return pArgument
    End If

    xCleanup(db, pArgument)
#if defined(SQLITE_DEBUG) OrElse defined(SQLITE_COVERAGE_TEST)
    pParse->earlyCleanup = 1
#endif
    Return 0
End Function

Sub sqlite3ParserRunCleanup CDecl Alias "sqlite3ParserRunCleanup" ( _
    ByVal pParse As SqliteParseContext Ptr _
)
    If pParse = 0 OrElse pParse->db = 0 Then Return

    Dim db As sqlite3 Ptr = pParse->db
    While pParse->pCleanup <> 0
        Dim pCleanup As SqliteParserCleanup Ptr = pParse->pCleanup
        pParse->pCleanup = pCleanup->pNext
        pCleanup->xCleanup(db, pCleanup->pPtr)
        sqlite3DbFree(db, pCleanup)
    Wend
End Sub

/' end of sqlite3_parser_cleanup.bas '/
