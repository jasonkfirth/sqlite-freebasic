/'
    Project: SQLite FreeBASIC port

    File: sqlite3_parser_tables.bas

    Purpose:

        Compile Lemon's generated parser tables into the FreeBASIC library.

    Responsibilities:

        - Provide immutable action, lookahead, shift, reduce, and rule tables.
        - Keep parser data generated from src/parse.y through Lemon.
        - Resolve shift and reduction actions with Lemon's table algorithm.
        - Initialize parser state, allocate parser objects, and grow the stack.
        - Feed tokens through shift, reduce, accept, and syntax-error states.
        - Dispatch the implemented parser semantic actions.
        - Run Lemon semantic destructors for owned values left on the stack.

    This file intentionally does NOT contain:

        - The semantic action bodies, which are in sqlite3_parser_semantics.bas.
        - SQL compilation or database operations.
'/

#lang "fb"
#include once "sqlite3_parser_tables.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_parser_semantics.bi"
#include once "sqlite3_parser_rule_ids.bi"

Declare Sub sqlite3IdListDelete CDecl Alias "sqlite3IdListDelete" ( _
    ByVal db As Any Ptr, _
    ByVal pIdList As Any Ptr _
)
Declare Sub sqlite3SrcListDelete CDecl Alias "sqlite3SrcListDelete" ( _
    ByVal db As Any Ptr, _
    ByVal pSrcList As Any Ptr _
)
Declare Sub sqlite3WithDelete CDecl Alias "sqlite3WithDelete" ( _
    ByVal db As Any Ptr, _
    ByVal pWith As Any Ptr _
)
Declare Sub sqlite3WindowDelete CDecl Alias "sqlite3WindowDelete" ( _
    ByVal db As Any Ptr, _
    ByVal pWindow As Any Ptr _
)
Declare Sub sqlite3WindowListDelete CDecl Alias "sqlite3WindowListDelete" ( _
    ByVal db As Any Ptr, _
    ByVal pWindow As Any Ptr _
)
Declare Sub sqlite3DeleteTriggerStep CDecl Alias "sqlite3DeleteTriggerStep" ( _
    ByVal db As Any Ptr, _
    ByVal pStep As Any Ptr _
)

Extern "C"
    Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
    Declare Function sqlite3_realloc64 CDecl Alias "sqlite3_realloc64" ( _
        ByVal pOld As Any Ptr, _
        ByVal nByte As sqlite3_uint64 _
    ) As Any Ptr
    Declare Function sqlite3SystemMemcpy CDecl Alias "memcpy" ( _
        ByVal pTarget As Any Ptr, _
        ByVal pSource As Const Any Ptr, _
        ByVal nByte As UInteger _
    ) As Any Ptr
End Extern

/' ------------------------------------------------------------------------- '/
/' Parser allocation and initialization '/
/' ------------------------------------------------------------------------- '/

Sub sqlite3ParserInit CDecl Alias "sqlite3ParserInit" ( _
    ByVal pRawParser As Any Ptr, _
    ByVal pParse As Any Ptr _
) Export

    If pRawParser = 0 Then Return

    Dim parser As sqlite3ParserState Ptr = CPtr(sqlite3ParserState Ptr, pRawParser)
    parser->pParse = pParse
    parser->yystack = @parser->yystk0(0)
    parser->yystackEnd = @parser->yystk0(YYSTACKDEPTH - 1)
    parser->yytos = parser->yystack
    parser->yystack[0].stateno = 0
    parser->yystack[0].major = 0
    parser->syntaxErrors = 0
    parser->stackOverflow = 0
    parser->accepted = 0
    parser->syntaxFailure = 0
    parser->semanticActionFailure = 0
End Sub

Private Function sqlite3YyGrowStack(ByVal parser As sqlite3ParserState Ptr) As SQLITE_C_INT
    If parser = 0 OrElse parser->yystack = 0 OrElse parser->yystackEnd = 0 OrElse _
       parser->yytos = 0 Then
        Return 1
    End If

    Dim oldSize As SQLITE_C_INT = CLng(parser->yystackEnd - parser->yystack) + 1
    Dim stackLimit As SQLITE_C_INT = SQLITE_MAX_PARSER_DEPTH
    If parser->pParse <> 0 Then
        Dim pParse As SqliteParseContext Ptr = _
            CPtr(SqliteParseContext Ptr, parser->pParse)
        If pParse->db <> 0 Then _
            stackLimit = pParse->db->aLimit(SQLITE_LIMIT_PARSER_DEPTH)
    End If
    Dim newSize As SQLITE_C_INT = oldSize * 2 + 100
    If newSize > stackLimit Then
        newSize = stackLimit
        If newSize <= oldSize Then Return 1
    End If

    Dim topIndex As SQLITE_C_INT = CLng(parser->yytos - parser->yystack)
    Dim pOld As Any Ptr = 0
    If parser->yystack <> @parser->yystk0(0) Then pOld = parser->yystack

    Dim nByte As sqlite3_uint64 = CULngInt(newSize) * CULngInt(SizeOf(sqlite3ParserStackEntry))
    Dim pNew As Any Ptr = sqlite3_realloc64(pOld, nByte)
    If pNew = 0 Then Return 1

    If pOld = 0 Then
        sqlite3SystemMemcpy(pNew, @parser->yystk0(0), _
            CUInt(CULngInt(oldSize) * CULngInt(SizeOf(sqlite3ParserStackEntry))))
    End If

    parser->yystack = CPtr(sqlite3ParserStackEntry Ptr, pNew)
    parser->yytos = parser->yystack + topIndex
    parser->yystackEnd = parser->yystack + newSize - 1
    Return 0
End Function

Private Function sqlite3YyShift( _
    ByVal parser As sqlite3ParserState Ptr, _
    ByVal newState As UShort, _
    ByVal majorToken As UShort, _
    ByRef minorToken As sqlite3ParserToken, _
    ByVal normalizeShiftReduce As SQLITE_C_INT _
) As SQLITE_C_INT

    If parser = 0 OrElse parser->yytos = 0 Then Return 1

    parser->yytos += 1
    If parser->yytos > parser->yystackEnd Then
        If sqlite3YyGrowStack(parser) <> 0 Then
            parser->yytos -= 1
            Return 1
        End If
    End If

    ' Only terminal shift actions carry the encoded shift-reduce form. A
    ' nonterminal goto may already be a pure-reduce state and must stay intact.
    If normalizeShiftReduce <> 0 AndAlso newState > YY_MAX_SHIFT Then
        newState += YY_MIN_REDUCE - YY_MIN_SHIFTREDUCE
    End If

    parser->yytos->stateno = newState
    parser->yytos->major = majorToken
    parser->yytos->minor.yy0 = minorToken
    Return 0
End Function

Function sqlite3ParserAlloc CDecl Alias "sqlite3ParserAlloc" ( _
    ByVal mallocProc As sqlite3ParserMallocProc, _
    ByVal pParse As Any Ptr _
) As Any Ptr Export

    If mallocProc = 0 Then Return 0

    Dim parser As Any Ptr = mallocProc(CULngInt(SizeOf(sqlite3ParserState)))
    If parser <> 0 Then sqlite3ParserInit(parser, pParse)
    Return parser
End Function

Private Sub sqlite3ParserClearOwnedStackValues( _
    ByVal parser As sqlite3ParserState Ptr _
)
    If parser = 0 OrElse parser->pParse = 0 OrElse _
       parser->yystack = 0 OrElse parser->yytos = 0 Then Return
    Dim pParse As SqliteParseContext Ptr = CPtr(SqliteParseContext Ptr, parser->pParse)
    If pParse->db = 0 Then Return
    Dim topIndex As Long = parser->yytos - parser->yystack
    Dim stackCapacity As Long = parser->yystackEnd - parser->yystack
    If topIndex < 1 OrElse topIndex > stackCapacity Then Return

    ' These cases mirror the active %destructor declarations in src/parse.y.
    For stackIndex As Long = topIndex To 1 Step -1
        Dim pEntry As sqlite3ParserStackEntry Ptr = @parser->yystack[stackIndex]
        Select Case pEntry->major
        Case YYSYM_EXPR, YYSYM_TERM, YYSYM_WHERE_OPT, _
             YYSYM_HAVING_OPT, YYSYM_WHERE_OPT_RET, YYSYM_CASE_ELSE, _
             YYSYM_CASE_OPERAND, YYSYM_VINTO, YYSYM_WHEN_CLAUSE, _
             YYSYM_KEY_OPT, YYSYM_FILTER_CLAUSE
            Dim pExpr As SqliteExpr Ptr = _
                CPtr(SqliteExpr Ptr, pEntry->minor.yy454)
            pEntry->minor.yy454 = 0
            sqlite3ExprDelete(pParse->db, pExpr)

        Case YYSYM_SELCOLLIST, YYSYM_SCLP, YYSYM_EIDLIST_OPT, _
             YYSYM_SORTLIST, YYSYM_EIDLIST, YYSYM_GROUPBY_OPT, _
             YYSYM_ORDERBY_OPT, YYSYM_NEXPRLIST, YYSYM_EXPRLIST, _
             YYSYM_SETLIST, YYSYM_PAREN_EXPRLIST, YYSYM_CASE_EXPRLIST, _
             YYSYM_PART_OPT
            Dim pList As SqliteExprList Ptr = _
                CPtr(SqliteExprList Ptr, pEntry->minor.yy14)
            pEntry->minor.yy14 = 0
            sqlite3ExprListDelete(pParse->db, pList)

        Case YYSYM_SELECT, YYSYM_SELECTNOWITH, YYSYM_ONESELECT, _
             YYSYM_VALUES, YYSYM_MVALUES
            Dim pSelect As SqliteSelect Ptr = _
                CPtr(SqliteSelect Ptr, pEntry->minor.yy555)
            pEntry->minor.yy555 = 0
            sqlite3SelectDelete(pParse->db, pSelect)

        Case YYSYM_FULLNAME, YYSYM_FROM, YYSYM_SELTABLIST, _
             YYSYM_STL_PREFIX, YYSYM_XFULLNAME
            Dim pSrcList As Any Ptr = pEntry->minor.yy203
            pEntry->minor.yy203 = 0
            sqlite3SrcListDelete(pParse->db, pSrcList)

        Case YYSYM_WQLIST
            Dim pWith As Any Ptr = pEntry->minor.yy59
            pEntry->minor.yy59 = 0
            sqlite3WithDelete(pParse->db, pWith)

#ifndef SQLITE_OMIT_WINDOWFUNC
        Case YYSYM_WINDOW_CLAUSE, YYSYM_WINDOWDEFN_LIST
            Dim pWindowList As Any Ptr = pEntry->minor.yy211
            pEntry->minor.yy211 = 0
            sqlite3WindowListDelete(pParse->db, pWindowList)
#endif

        Case YYSYM_IDLIST, YYSYM_IDLIST_OPT
            Dim pIdList As Any Ptr = pEntry->minor.yy132
            pEntry->minor.yy132 = 0
            sqlite3IdListDelete(pParse->db, pIdList)

#ifndef SQLITE_OMIT_WINDOWFUNC
        Case YYSYM_FILTER_OVER, YYSYM_WINDOWDEFN, YYSYM_WINDOW, _
             YYSYM_FRAME_OPT, YYSYM_OVER_CLAUSE
            Dim pWindow As Any Ptr = pEntry->minor.yy211
            pEntry->minor.yy211 = 0
            sqlite3WindowDelete(pParse->db, pWindow)
#endif

        Case YYSYM_TRIGGER_CMD_LIST, YYSYM_TRIGGER_CMD
            Dim pStep As Any Ptr = pEntry->minor.yy427
            pEntry->minor.yy427 = 0
            sqlite3DeleteTriggerStep(pParse->db, pStep)

        Case YYSYM_TRIGGER_EVENT
            Dim pEventColumns As Any Ptr = pEntry->minor.yy286.b
            pEntry->minor.yy286.b = 0
            sqlite3IdListDelete(pParse->db, pEventColumns)

        Case YYSYM_FRAME_BOUND, YYSYM_FRAME_BOUND_S, YYSYM_FRAME_BOUND_E
            Dim pBoundExpr As Any Ptr = pEntry->minor.yy509.pExpr
            pEntry->minor.yy509.pExpr = 0
            sqlite3ExprDelete(pParse->db, pBoundExpr)
        End Select
    Next
End Sub

Sub sqlite3ParserFinalize CDecl Alias "sqlite3ParserFinalize" (ByVal pRawParser As Any Ptr) Export
    If pRawParser = 0 Then Return

    Dim parser As sqlite3ParserState Ptr = CPtr(sqlite3ParserState Ptr, pRawParser)
    sqlite3ParserClearOwnedStackValues(parser)
    If parser->yystack <> @parser->yystk0(0) Then sqlite3_free(parser->yystack)
    parser->yystack = @parser->yystk0(0)
    parser->yystackEnd = @parser->yystk0(YYSTACKDEPTH - 1)
    parser->yytos = parser->yystack
End Sub

Sub sqlite3ParserFree CDecl Alias "sqlite3ParserFree" ( _
    ByVal pRawParser As Any Ptr, _
    ByVal freeProc As sqlite3ParserFreeProc _
) Export

    If pRawParser = 0 OrElse freeProc = 0 Then Return
    sqlite3ParserFinalize(pRawParser)
    freeProc(pRawParser)
End Sub

/' ------------------------------------------------------------------------- '/
/' Lemon action lookup '/
/' ------------------------------------------------------------------------- '/

Private Function sqlite3YyDefaultAction(ByVal stateNo As UShort) As UShort
    If stateNo <= UBound(sqlite3YyDefault) Then Return sqlite3YyDefault(stateNo)
    Return YY_ERROR_ACTION
End Function

Private Function sqlite3YyFindShiftAction( _
    ByVal inputToken As UShort, _
    ByVal stateNo As UShort _
) As UShort

    If stateNo > YY_MAX_SHIFT Then Return stateNo
    If stateNo > YY_SHIFT_COUNT OrElse stateNo >= YYNSTATE Then Return YY_ERROR_ACTION
    If inputToken = YYNOCODE OrElse inputToken >= YYNTOKEN Then Return YY_ERROR_ACTION

    Dim lookaheadToken As UShort = inputToken
    Dim fallbackCount As Long = 0

    Do
        Dim offset As Long = sqlite3YyShiftOfst(stateNo)
        Dim lookaheadCount As Long = UBound(sqlite3YyLookahead) + 1
        If offset + YYNTOKEN > lookaheadCount Then Return sqlite3YyDefaultAction(stateNo)

        Dim actionIndex As Long = offset + lookaheadToken
        If actionIndex < 0 OrElse actionIndex >= lookaheadCount Then
            Return sqlite3YyDefaultAction(stateNo)
        End If

        If sqlite3YyLookahead(actionIndex) = lookaheadToken Then
            If actionIndex <= UBound(sqlite3YyAction) Then Return sqlite3YyAction(actionIndex)
            Return sqlite3YyDefaultAction(stateNo)
        End If

        Dim fallbackToken As UShort = 0
        If lookaheadToken <= UBound(sqlite3YyFallback) Then
            fallbackToken = sqlite3YyFallback(lookaheadToken)
        End If
        If fallbackToken <> 0 Then
            fallbackCount += 1
            If fallbackCount >= YYNTOKEN Then Return sqlite3YyDefaultAction(stateNo)
            lookaheadToken = fallbackToken
        Else
            Dim wildcardIndex As Long = actionIndex - lookaheadToken + YYWILDCARD
            If inputToken > 0 AndAlso wildcardIndex >= 0 AndAlso _
               wildcardIndex <= UBound(sqlite3YyLookahead) AndAlso _
               wildcardIndex <= UBound(sqlite3YyAction) AndAlso _
               sqlite3YyLookahead(wildcardIndex) = YYWILDCARD Then
                Return sqlite3YyAction(wildcardIndex)
            End If
            Return sqlite3YyDefaultAction(stateNo)
        End If
    Loop
End Function

Private Function sqlite3YyFindReduceAction( _
    ByVal stateNo As UShort, _
    ByVal inputToken As UShort _
) As UShort

    If stateNo > YY_REDUCE_COUNT OrElse stateNo > UBound(sqlite3YyReduceOfst) Then
        Return sqlite3YyDefaultAction(stateNo)
    End If
    ' Reduce-table lookups receive nonterminal IDs as well as terminals.
    If inputToken >= YYNOCODE Then
        Return sqlite3YyDefaultAction(stateNo)
    End If

    Dim actionIndex As Long = sqlite3YyReduceOfst(stateNo) + inputToken
    If actionIndex < 0 OrElse actionIndex >= YY_ACTTAB_COUNT OrElse _
       actionIndex > UBound(sqlite3YyAction) OrElse _
       actionIndex > UBound(sqlite3YyLookahead) Then
        Return sqlite3YyDefaultAction(stateNo)
    End If
    If sqlite3YyLookahead(actionIndex) <> inputToken Then
        Return sqlite3YyDefaultAction(stateNo)
    End If
    Return sqlite3YyAction(actionIndex)
End Function

Private Sub sqlite3YyMarkError(ByVal parser As sqlite3ParserState Ptr, ByVal stackOverflow As SQLITE_C_INT)
    If parser = 0 Then Exit Sub
    If parser->syntaxErrors < &H7FFFFFFF Then parser->syntaxErrors += 1
    If stackOverflow <> 0 Then parser->stackOverflow = 1
End Sub

Private Sub sqlite3YyClearMinor(ByVal pMinor As sqlite3ParserMinor Ptr)
    If pMinor = 0 Then Exit Sub
    Dim pBytes As UByte Ptr = CPtr(UByte Ptr, pMinor)
    For i As Long = 0 To SizeOf(sqlite3ParserMinor) - 1
        pBytes[i] = 0
    Next
End Sub

Sub sqlite3Parser CDecl Alias "sqlite3Parser" ( _
    ByVal pRawParser As Any Ptr, _
    ByVal majorToken As SQLITE_C_INT, _
    ByVal minorToken As sqlite3ParserToken _
) Export

    If pRawParser = 0 Then Return
    Dim parser As sqlite3ParserState Ptr = CPtr(sqlite3ParserState Ptr, pRawParser)
    If parser->yytos = 0 OrElse parser->yystack = 0 OrElse parser->yystackEnd = 0 Then
        sqlite3YyMarkError(parser, 0)
        Return
    End If
    If parser->accepted <> 0 Then Return
    If majorToken < 0 OrElse majorToken >= YYNTOKEN Then
        sqlite3YyMarkError(parser, 0)
        Return
    End If

    Dim tokenCode As UShort = CUShort(majorToken)
    Dim action As UShort = parser->yytos->stateno
    Dim nTransition As Long = 0
    Dim maxTransitions As Long = YYNSTATE + YYNRULE + 1

    Do
        nTransition += 1
        If nTransition > maxTransitions Then
            sqlite3YyMarkError(parser, 0)
            Return
        End If

        action = sqlite3YyFindShiftAction(tokenCode, action)
        If action >= YY_MIN_REDUCE AndAlso action <= YY_MAX_REDUCE Then
            Dim ruleNumber As Long = action - YY_MIN_REDUCE
            If ruleNumber < 0 OrElse ruleNumber > UBound(sqlite3YyRuleInfoLhs) OrElse _
               ruleNumber > UBound(sqlite3YyRuleInfoNRhs) Then
                sqlite3YyMarkError(parser, 0)
                Return
            End If

            Dim rhsOffset As Long = sqlite3YyRuleInfoNRhs(ruleNumber)
            If rhsOffset > 0 Then
                sqlite3YyMarkError(parser, 0)
                Return
            End If
            Dim rhsCount As Long = -rhsOffset
            Dim oldTopIndex As Long = CLng(parser->yytos - parser->yystack)
            If rhsCount > oldTopIndex Then
                sqlite3YyMarkError(parser, 0)
                Return
            End If

            Dim lhsToken As UShort = sqlite3YyRuleInfoLhs(ruleNumber)
            Dim baseIndex As Long = oldTopIndex - rhsCount
            Dim nextState As UShort = sqlite3YyFindReduceAction(parser->yystack[baseIndex].stateno, lhsToken)
            ' Lemon uses pure-reduce actions as parser states after a goto.
            ' Only shift-reduce actions and the error action are invalid here.
            If (nextState > YY_MAX_SHIFT AndAlso _
                nextState <= YY_MAX_SHIFTREDUCE) OrElse _
               nextState = YY_ERROR_ACTION Then
                sqlite3YyMarkError(parser, 0)
                Return
            End If

            Dim lhsMinor As sqlite3ParserMinor
            sqlite3YyClearMinor(@lhsMinor)
            Dim semanticCode As SQLITE_C_INT = sqlite3ParserSemanticReduce( _
                parser, CInt(ruleNumber), CInt(rhsCount), minorToken, @lhsMinor)
            If semanticCode <> SQLITE_OK Then
                parser->semanticActionFailure = 1
                Dim pParse As SqliteParseContext Ptr = CPtr(SqliteParseContext Ptr, parser->pParse)
                If pParse <> 0 Then
                    pParse->rc = semanticCode
                    If pParse->nErr < &H7FFFFFFF Then pParse->nErr += 1
                End If
                sqlite3YyMarkError(parser, 0)
                Return
            End If

            If rhsCount = 0 Then
                Dim emptyToken As sqlite3ParserToken
                emptyToken.z = 0
                emptyToken.n = 0
                If sqlite3YyShift(parser, nextState, lhsToken, emptyToken, 0) <> 0 Then
                    sqlite3YyMarkError(parser, 1)
                    Return
                End If
                parser->yytos->minor = lhsMinor
            Else
                Dim newTopIndex As Long = oldTopIndex - rhsCount + 1
                parser->yytos = parser->yystack + newTopIndex
                parser->yytos->stateno = nextState
                parser->yytos->major = lhsToken
                parser->yytos->minor = lhsMinor
            End If

            action = parser->yytos->stateno
        ElseIf action <= YY_MAX_SHIFTREDUCE Then
            If sqlite3YyShift(parser, action, tokenCode, minorToken, 1) <> 0 Then
                sqlite3YyMarkError(parser, 1)
            End If
            Return
        ElseIf action = YY_ACCEPT_ACTION Then
            If parser->yytos > parser->yystack Then parser->yytos -= 1
            parser->accepted = 1
            Return
        Else
            parser->syntaxFailure = 1
            sqlite3YyMarkError(parser, 0)
            Return
        End If
    Loop
End Sub

Function sqlite3ParserHasError CDecl Alias "sqlite3ParserHasError" (ByVal pRawParser As Any Ptr) As SQLITE_C_INT Export
    If pRawParser = 0 Then Return 1
    Dim parser As sqlite3ParserState Ptr = CPtr(sqlite3ParserState Ptr, pRawParser)
    Return IIf(parser->syntaxErrors <> 0 OrElse parser->stackOverflow <> 0, 1, 0)
End Function

Function sqlite3ParserWasAccepted CDecl Alias "sqlite3ParserWasAccepted" (ByVal pRawParser As Any Ptr) As SQLITE_C_INT Export
    If pRawParser = 0 Then Return 0
    Dim parser As sqlite3ParserState Ptr = CPtr(sqlite3ParserState Ptr, pRawParser)
    Return IIf(parser->accepted <> 0, 1, 0)
End Function

/' end of sqlite3_parser_tables.bas '/
