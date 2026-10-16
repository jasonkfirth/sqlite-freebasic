/'
    Project: SQLite FreeBASIC port

    File: sqlite3_parser_driver.bas

    Purpose:

        Feed SQLite's tokenizer output into the Lemon syntax parser.

    Responsibilities:

        - Reset stale interrupt state when no VDBE is active.
        - Skip whitespace and comments and track SQL length limits.
        - Stop at an interrupt without replacing it with a syntax error.
        - Resolve context-sensitive WINDOW, OVER, and FILTER tokens.
        - Feed SQL tokens through Lemon's shift/reduce state machine.
        - Preserve the caller's nested-parse depth across recursive parsing.
        - Preserve the last submitted token for statement-text capture.
        - Mark parser-state allocation failures as connection OOM errors.
        - Return syntax and parser-stack errors to the parse context.
        - Free transient DDL objects and other parser-owned state after parsing.
        - Publish the active parse context for shared error handoff.

    This file intentionally does NOT contain:

        - Grammar semantic actions, parse-tree construction, or SQL codegen.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_tokens.bi"
#include once "sqlite3_parser_types.bi"

Declare Function sqlite3GetToken CDecl Alias "sqlite3GetToken" ( _
    ByVal z As Const UByte Ptr, _
    ByVal pTokenType As SQLITE_C_INT Ptr _
) As sqlite3_int64
Declare Function sqlite3Malloc CDecl Alias "sqlite3Malloc" (ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Declare Function sqlite3ParserAlloc CDecl Alias "sqlite3ParserAlloc" ( _
    ByVal mallocProc As sqlite3ParserMallocProc, _
    ByVal pParse As Any Ptr _
) As Any Ptr
Declare Sub sqlite3ParserFree CDecl Alias "sqlite3ParserFree" ( _
    ByVal pParser As Any Ptr, _
    ByVal freeProc As sqlite3ParserFreeProc _
)
Declare Sub sqlite3RecordErrorByteOffset CDecl Alias "sqlite3RecordErrorByteOffset" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zToken As Const ZString Ptr _
)
Declare Sub sqlite3DeleteTable CDecl Alias "sqlite3DeleteTable" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pTable As Any Ptr _
)
Declare Sub sqlite3DeleteTrigger CDecl Alias "sqlite3DeleteTrigger" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pTrigger As Any Ptr _
)

#ifndef SQLITE_OMIT_WINDOWFUNC
Private Function sqlite3ParserFallback(ByVal tokenType As SQLITE_C_INT) As SQLITE_C_INT
    If tokenType < 0 OrElse tokenType > UBound(sqlite3YyFallback) Then Return 0
    Return sqlite3YyFallback(tokenType)
End Function

Private Function getToken(ByRef pz As Const UByte Ptr) As SQLITE_C_INT
    If pz = 0 Then Return TK_ILLEGAL
    Dim z As Const UByte Ptr = pz
    Dim tokenType As SQLITE_C_INT = TK_ILLEGAL
    Do
        Dim tokenLength As sqlite3_int64 = sqlite3GetToken(z, @tokenType)
        If tokenLength <= 0 Then Exit Do
        z += tokenLength
    Loop While tokenType = TK_SPACE OrElse tokenType = TK_COMMENT

    If tokenType = TK_ID OrElse tokenType = TK_STRING OrElse _
       tokenType = TK_JOIN_KW OrElse tokenType = TK_WINDOW OrElse _
       tokenType = TK_OVER OrElse sqlite3ParserFallback(tokenType) = TK_ID Then
        tokenType = TK_ID
    End If
    pz = z
    Return tokenType
End Function

Private Function analyzeWindowKeyword(ByVal z As Const UByte Ptr) As SQLITE_C_INT
    Dim lookahead As Const UByte Ptr = z
    If getToken(lookahead) <> TK_ID Then Return TK_ID
    If getToken(lookahead) <> TK_AS Then Return TK_ID
    Return TK_WINDOW
End Function

Private Function analyzeOverKeyword( _
    ByVal z As Const UByte Ptr, _
    ByVal lastToken As SQLITE_C_INT _
) As SQLITE_C_INT
    If lastToken = TK_RP Then
        Dim lookahead As Const UByte Ptr = z
        Dim tokenType As SQLITE_C_INT = getToken(lookahead)
        If tokenType = TK_LP OrElse tokenType = TK_ID Then Return TK_OVER
    End If
    Return TK_ID
End Function

Private Function analyzeFilterKeyword( _
    ByVal z As Const UByte Ptr, _
    ByVal lastToken As SQLITE_C_INT _
) As SQLITE_C_INT
    If lastToken <> TK_RP Then Return TK_ID
    Dim lookahead As Const UByte Ptr = z
    If getToken(lookahead) = TK_LP Then Return TK_FILTER
    Return TK_ID
End Function
#endif

Private Function sqlite3ParserAnalyzeKeyword( _
    ByVal tokenType As SQLITE_C_INT, _
    ByVal pSql As Const UByte Ptr, _
    ByVal tokenLength As sqlite3_int64, _
    ByVal previousToken As SQLITE_C_INT _
) As SQLITE_C_INT
#ifndef SQLITE_OMIT_WINDOWFUNC
    Select Case tokenType
    Case TK_WINDOW
        Return analyzeWindowKeyword(pSql + tokenLength)
    Case TK_OVER
        Return analyzeOverKeyword(pSql + tokenLength, previousToken)
    Case TK_FILTER
        Return analyzeFilterKeyword(pSql + tokenLength, previousToken)
    End Select
#endif
    Return tokenType
End Function

Function sqlite3RunParser CDecl Alias "sqlite3RunParser" ( _
    ByVal pParseArgument As Any Ptr, _
    ByVal zSql As Const ZString Ptr _
) As SQLITE_C_INT Export

    If pParseArgument = 0 OrElse zSql = 0 Then Return SQLITE_MISUSE
    Dim pParse As SqliteParseContext Ptr = CPtr(SqliteParseContext Ptr, pParseArgument)
    If pParse->db = 0 Then Return SQLITE_MISUSE
    ' C clears a stale interrupt before parsing when no VDBE is active.
    If pParse->db->nVdbeActive = 0 AndAlso _
       pParse->db->interruptMutex <> 0 Then
        sqlite3_mutex_enter(pParse->db->interruptMutex)
        If pParse->db->nVdbeActive = 0 Then pParse->db->isInterrupted = 0
        sqlite3_mutex_leave(pParse->db->interruptMutex)
    End If
    pParse->rc = SQLITE_OK
    pParse->zTail = CPtr(ZString Ptr, zSql)
    Dim previousParse As Any Ptr = pParse->db->pParse
    pParse->db->pParse = pParseArgument
    pParse->db->errByteOffset = -2

    Dim parserRaw As Any Ptr = sqlite3ParserAlloc(@sqlite3Malloc, pParseArgument)
    If parserRaw = 0 Then
        Dim previousErrorCount As SQLITE_C_INT = pParse->nErr
        sqlite3OomFault(pParse->db)
        pParse->rc = SQLITE_NOMEM
        If pParse->nErr = previousErrorCount AndAlso _
           pParse->nErr < &H7FFFFFFF Then pParse->nErr += 1
        pParse->db->errByteOffset = -1
        pParse->db->errorCode = SQLITE_NOMEM
        pParse->db->pParse = previousParse
        Return pParse->rc
    End If
    Dim parser As sqlite3ParserState Ptr = CPtr(sqlite3ParserState Ptr, parserRaw)
    Dim pSql As Const UByte Ptr = CPtr(Const UByte Ptr, zSql)
    Dim remainingSqlBytes As sqlite3_int64 = _
        pParse->db->aLimit(SQLITE_LIMIT_SQL_LENGTH)
    Dim previousToken As SQLITE_C_INT = -1

    Do
        Dim tokenType As SQLITE_C_INT = TK_ILLEGAL
        Dim tokenLength As sqlite3_int64 = sqlite3GetToken(pSql, @tokenType)
        If tokenLength < 0 OrElse tokenLength > remainingSqlBytes Then
            pParse->rc = SQLITE_TOOBIG
            pParse->nErr += 1
            Exit Do
        End If
        remainingSqlBytes -= tokenLength
        If tokenType >= TK_SPACE AndAlso _
           sqlite3InterruptPending(pParse->db) <> 0 Then
            pParse->rc = SQLITE_INTERRUPT
            pParse->nErr += 1
            Exit Do
        End If

        If tokenType = TK_SPACE OrElse tokenType = TK_COMMENT Then
            If tokenLength <= 0 Then
                pParse->rc = SQLITE_ERROR
                pParse->nErr += 1
                Exit Do
            End If
            pSql += tokenLength
            pParse->zTail = CPtr(ZString Ptr, pSql)
            Continue Do
        End If

        If pSql[0] = 0 Then
            If previousToken = 0 Then Exit Do
            If previousToken <> TK_SEMI Then
                tokenType = TK_SEMI
            Else
                tokenType = 0
            End If
            tokenLength = 0
        Else
            tokenType = sqlite3ParserAnalyzeKeyword(tokenType, pSql, tokenLength, previousToken)
            If tokenType = TK_ILLEGAL Then
                Dim errorToken As sqlite3ParserToken
                errorToken.z = CPtr(UByte Ptr, pSql)
                errorToken.n = CULng(tokenLength)
                sqlite3ErrorMsg(pParse, StrPtr("unrecognized token: ""%T"""), @errorToken)
                pParse->db->errByteOffset = -2
                sqlite3RecordErrorByteOffset(pParse->db, CPtr(Const ZString Ptr, pSql))
                Exit Do
            End If
        End If

        Dim token As sqlite3ParserToken
        token.z = CPtr(UByte Ptr, pSql)
        token.n = CULng(tokenLength)
        pParse->sLastToken = token
        sqlite3Parser(parserRaw, tokenType, token)
        previousToken = tokenType
        pParse->zTail = CPtr(ZString Ptr, pSql)
        If tokenLength > 0 Then
            pSql += tokenLength
            pParse->zTail = CPtr(ZString Ptr, pSql)
        End If
        ' A semantic failure or completed statement normally stops input.
        ' Resolve a parser error on the current lookahead first because the
        ' final reduction may set SQLITE_DONE before that lookahead is checked.
        If sqlite3ParserHasError(parserRaw) <> 0 Then
            ' Lemon's syntax-error action replaces earlier semantic diagnostics
            ' when the token stream itself is malformed. Preserve messages from
            ' semantic-action failures, which do not set syntaxFailure.
            If parser->syntaxFailure <> 0 OrElse _
               (parser->semanticActionFailure = 0 AndAlso pParse->zErrMsg = 0) Then
                If token.z = 0 OrElse token.n = 0 OrElse token.z[0] = 0 Then
                    sqlite3ErrorMsg(pParse, StrPtr("incomplete input"))
                Else
                    sqlite3ErrorMsg(pParse, StrPtr("near ""%T"": syntax error"), @token)
                End If
                pParse->db->errByteOffset = -2
                sqlite3RecordErrorByteOffset(pParse->db, CPtr(Const ZString Ptr, token.z))
            End If
            Exit Do
        End If
        ' Interrupt and allocation errors are already recorded on Parse.
        ' Do not replace those errors or a completed statement result.
        If pParse->rc <> SQLITE_OK Then Exit Do
    Loop

    If pParse->rc = SQLITE_OK AndAlso sqlite3ParserWasAccepted(parserRaw) = 0 Then
        sqlite3ErrorMsg(pParse, StrPtr("incomplete input"))
    End If
    If pParse->db->errByteOffset < -1 Then pParse->db->errByteOffset = -1
    pParse->db->errorCode = pParse->rc
    sqlite3ParserFree(parserRaw, @sqlite3_free)
    ' The parser no longer owns these transient schema objects after reduction.
#ifndef SQLITE_OMIT_VIRTUALTABLE
    If pParse->apVtabLock <> 0 Then sqlite3_free(pParse->apVtabLock)
#endif
    If pParse->pNewTable <> 0 AndAlso _
       pParse->eParseMode = PARSE_MODE_NORMAL Then
        sqlite3DeleteTable(pParse->db, pParse->pNewTable)
        pParse->pNewTable = 0
    End If
    If pParse->pNewTrigger <> 0 AndAlso _
       pParse->eParseMode < PARSE_MODE_RENAME Then
        sqlite3DeleteTrigger(pParse->db, pParse->pNewTrigger)
        pParse->pNewTrigger = 0
    End If
    If pParse->pVList <> 0 Then
        sqlite3DbNNFreeNN(pParse->db, pParse->pVList)
        pParse->pVList = 0
    End If
    pParse->db->pParse = previousParse
    ' sqlite3RunParser returns an error count. SQLITE_DONE is a successful
    ' parse state for statements that emitted a VDBE and must return zero.
    Dim parserErrorCount As SQLITE_C_INT = pParse->nErr
    If parserErrorCount = 0 AndAlso _
       (pParse->zErrMsg <> 0 OrElse _
        (pParse->rc <> SQLITE_OK AndAlso pParse->rc <> SQLITE_DONE)) Then _
        parserErrorCount = 1
    Return parserErrorCount
End Function

/' end of sqlite3_parser_driver.bas '/
