/'
    Project: SQLite FreeBASIC port

    File: sqlite3_expr.bas

    Purpose:

        Port core expression and SELECT allocation helpers from expr.c/select.c.

    Responsibilities:

        - Allocate token and integer Expr nodes with SQLite ownership rules.
        - Dequote quoted Expr tokens and preserve their quote-origin flags.
        - Store byte offsets unless the expression belongs to a join constraint.
        - Defer uncommon expression cleanup to the end of statement preparation.
        - Fold an AND expression to false when its inputs prove the result.
        - Inspect true/false and integer literals used by planner expressions.
        - Skip collation and likelihood wrappers when reading an expression value.
        - Resolve declared column collations from table schema records.
        - Classify constants and functions with the expression walker.
        - Identify GROUP BY-stable expressions when BINARY collation is known.
        - Recognize rowid aliases and affinity-preserving literal expressions.
        - Inspect vector width and retrieve child expressions from vectors.
        - Inspect vector width and retrieve a field expression safely.
        - Check whether an expression's columns are available from an index.
        - Deep-copy full and reduced/token-only Expr prefixes, ExprList, SrcList, and Select nodes.
        - Build SELECT-column vector wrappers with explicit ownership rules.
        - Duplicate window-function expressions and their Window records.
        - Compute expression/list/SELECT tree height and enforce the parse limit.
        - Provide expression-list and small VDBE, comparison, and subselect codegen helpers.
        - Materialize scalar and EXISTS subqueries through VDBE subroutines.
        - Conservatively classify expression nullability for planner checks.
        - Append, name, span, and release variable-sized ExprList objects.
        - Append identifier-list entries with parser rename-token ownership.
        - Create and delete the common Select prefix used by parser actions.
        - Reset temporary register-cache state and reserve register indices.

    This file intentionally does NOT contain:

        - Complete expression analysis, name resolution, or SELECT code generation.
'/

#lang "fb"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_numeric.bi"
#include once "sqlite3_util_numeric.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_vdbe_api.bi"
#include once "sqlite3_vdbe_affinity.bi"
#include once "sqlite3_walker.bi"
#include once "sqlite3_walk_contexts.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_schema_types.bi"

Private Type SqliteExprDupBuffer
    zAlloc As UByte Ptr
    zEnd As UByte Ptr
End Type

Declare Function sqlite3ValueFromExpr CDecl Alias "sqlite3ValueFromExpr" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pExpr As Const Any Ptr, _
    ByVal encoding As UByte, _
    ByVal affinity As UByte, _
    ByVal ppValue As Any Ptr Ptr _
) As SQLITE_C_INT

#ifndef SQLITE_OMIT_WINDOWFUNC
Declare Function sqlite3WindowListDup CDecl Alias "sqlite3WindowListDup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pWindow As SqliteWalkerWindow Ptr _
) As SqliteWalkerWindow Ptr
Declare Sub gatherSelectWindows CDecl Alias "gatherSelectWindows" ( _
    ByVal pSelect As SqliteSelect Ptr _
)
#endif

Declare Function sqlite3ColumnColl CDecl Alias "sqlite3ColumnColl" ( _
    ByVal pColumn As SqliteColumn Ptr _
) As Const ZString Ptr
Declare Function sqlite3FindCollSeq CDecl Alias "sqlite3FindCollSeq" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal encoding As UByte, _
    ByVal zName As Const ZString Ptr, _
    ByVal create As SQLITE_C_INT _
) As sqlite3CollSeq Ptr

#ifndef SQLITE_OMIT_WINDOWFUNC
Declare Function sqlite3WindowDup CDecl Alias "sqlite3WindowDup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal pWindow As SqliteWalkerWindow Ptr _
) As SqliteWalkerWindow Ptr
#endif

#ifdef SQLITE_DEBUG
Declare Sub sqlite3SelectWalkAssert2 CDecl Alias "sqlite3SelectWalkAssert2" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
)
#endif

Declare Function sqlite3TableColumnToIndex CDecl Alias "sqlite3TableColumnToIndex" ( _
    ByVal pIndex As SqliteIndex Ptr, _
    ByVal iColumn As SQLITE_C_INT _
) As SQLITE_C_INT

Declare Sub sqlite3IdListDelete CDecl Alias "sqlite3IdListDelete" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pList As SqliteIdList Ptr _
)
Declare Function sqlite3RenameTokenMap CDecl Alias "sqlite3RenameTokenMap" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pPointer As Any Ptr, _
    ByVal pToken As sqlite3ParserToken Ptr _
) As Any Ptr

Declare Function sqlite3SrcListDup CDecl Alias "sqlite3SrcListDup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pSourceList As Const SqliteSrcList Ptr, _
    ByVal duplicateFlags As SQLITE_C_INT _
) As SqliteSrcList Ptr
Declare Sub sqlite3SrcListDelete CDecl Alias "sqlite3SrcListDelete" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pSourceList As SqliteSrcList Ptr _
)

Declare Function sqlite3CodeSubselect CDecl Alias "sqlite3CodeSubselect" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT
#ifdef SQLITE_ENABLE_STMT_SCANSTATUS
Declare Sub sqlite3VdbeScanStatusCounters CDecl Alias "sqlite3VdbeScanStatusCounters" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal explainAddress As SQLITE_C_INT, _
    ByVal loopAddress As SQLITE_C_INT, _
    ByVal visitAddress As SQLITE_C_INT _
)
Declare Sub sqlite3VdbeScanStatusRange CDecl Alias "sqlite3VdbeScanStatusRange" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal explainAddress As SQLITE_C_INT, _
    ByVal startAddress As SQLITE_C_INT, _
    ByVal endAddress As SQLITE_C_INT _
)
#endif
Declare Sub sqlite3SelectDestInit CDecl Alias "sqlite3SelectDestInit" ( _
    ByVal pDestination As SqliteSelectDest Ptr, _
    ByVal destinationType As SQLITE_C_INT, _
    ByVal parameter As SQLITE_C_INT _
)
Declare Sub sqlite3ExprCode CDecl Alias "sqlite3ExprCode" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal targetRegister As SQLITE_C_INT _
)
Declare Function sqlite3ExprCodeTarget CDecl Alias "sqlite3ExprCodeTarget" ( _
    ByVal pParse As Any Ptr, _
    ByVal pExpr As Any Ptr, _
    ByVal targetRegister As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3ExprCodeRunJustOnce CDecl Alias "sqlite3ExprCodeRunJustOnce" ( _
    ByVal pParse As Any Ptr, _
    ByVal pExpr As Any Ptr, _
    ByVal targetRegister As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3ExprCodeExprList CDecl Alias "sqlite3ExprCodeExprList" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pList As SqliteExprList Ptr, _
    ByVal targetRegister As SQLITE_C_INT, _
    ByVal sourceRegister As SQLITE_C_INT, _
    ByVal codeFlags As UByte _
) As SQLITE_C_INT
Declare Function sqlite3_stricmp CDecl Alias "sqlite3_stricmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal zText As Const ZString Ptr _
) As SQLITE_C_INT

Extern "C"
    Declare Function sqlite3ExprMemcpy CDecl Alias "memcpy" ( _
        ByVal pTarget As Any Ptr, _
        ByVal pSource As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
End Extern

Declare Sub sqlite3Dequote CDecl Alias "sqlite3Dequote" (ByVal z As ZString Ptr)

#ifndef SQLITE_OMIT_WINDOWFUNC
Declare Sub sqlite3WindowDelete CDecl Alias "sqlite3WindowDelete" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pWindow As SqliteWalkerWindow Ptr _
)
#endif

#ifndef SQLITE_OMIT_ALTERTABLE
Declare Sub sqlite3RenameExprUnmap CDecl Alias "sqlite3RenameExprUnmap" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
)
#endif

Function sqlite3ExprListItemAt CDecl Alias "sqlite3ExprListItemAt" ( _
    ByVal pList As SqliteExprList Ptr, _
    ByVal itemIndex As SQLITE_C_INT _
) As SqliteExprListItem Ptr Export
    If pList = 0 OrElse itemIndex < 0 Then Return 0
    Dim itemOffset As sqlite3_uint64 = _
        SizeOf(SqliteExprList) - SizeOf(SqliteExprListItem) + _
        CULngInt(itemIndex) * SizeOf(SqliteExprListItem)
    Return CPtr(SqliteExprListItem Ptr, CPtr(UByte Ptr, pList) + itemOffset)
End Function

Private Sub sqlite3ExprDequoteToken( _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal tokenLength As SQLITE_C_INT _
)
    If pExpr = 0 OrElse pExpr->u.zToken = 0 OrElse tokenLength < 2 Then Exit Sub
    Dim zToken As UByte Ptr = pExpr->u.zToken
    Dim quoteByte As UByte = zToken[0]
    Select Case quoteByte
    Case Asc("'"), Asc(Chr(34)), Asc("`"), Asc("[")
    Case Else
        Exit Sub
    End Select
    Dim closingByte As UByte = quoteByte
    If quoteByte = Asc("[") Then closingByte = Asc("]")
    If zToken[tokenLength - 1] <> closingByte Then Exit Sub

    Dim sourceIndex As SQLITE_C_INT = 1
    Dim sourceEnd As SQLITE_C_INT = tokenLength - 1
    Dim targetIndex As SQLITE_C_INT = 0
    While sourceIndex < sourceEnd
        Dim valueByte As UByte = zToken[sourceIndex]
        sourceIndex += 1
        If valueByte = closingByte AndAlso sourceIndex < sourceEnd AndAlso _
           zToken[sourceIndex] = closingByte Then
            sourceIndex += 1
        End If
        zToken[targetIndex] = valueByte
        targetIndex += 1
    Wend
    zToken[targetIndex] = 0
    pExpr->flags Or= EP_Quoted
    If quoteByte = Asc(Chr(34)) Then pExpr->flags Or= EP_DblQuoted
End Sub

Sub sqlite3DequoteExpr CDecl Alias "sqlite3DequoteExpr" ( _
    ByVal pExpr As SqliteExpr Ptr _
) Export
    If pExpr = 0 OrElse (pExpr->flags And EP_IntValue) <> 0 OrElse _
       pExpr->u.zToken = 0 Then Return
    Dim tokenLength As SQLITE_C_INT = sqlite3Strlen30( _
        CPtr(Const ZString Ptr, pExpr->u.zToken))
    sqlite3ExprDequoteToken(pExpr, tokenLength)
End Sub

Sub sqlite3DequoteNumber CDecl Alias "sqlite3DequoteNumber" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) Export
    If pExpr = 0 Then Return
    If pParse = 0 OrElse pParse->db = 0 OrElse _
       pExpr->op <> TK_QNUMBER OrElse pExpr->u.zToken = 0 Then
        If pParse <> 0 Then pParse->rc = SQLITE_CORRUPT
        Return
    End If

    Dim zToken As UByte Ptr = pExpr->u.zToken
    Dim tokenLength As SQLITE_C_INT = sqlite3Strlen30( _
        CPtr(Const ZString Ptr, zToken))
    If tokenLength <= 0 Then
        pParse->rc = SQLITE_CORRUPT
        Return
    End If

    Dim isHex As SQLITE_C_INT = IIf( _
        tokenLength > 2 AndAlso zToken[0] = Asc("0") AndAlso _
        (zToken[1] = Asc("x") OrElse zToken[1] = Asc("X")), 1, 0)
    Dim readIndex As SQLITE_C_INT = 0
    Dim writeIndex As SQLITE_C_INT = 0
    pExpr->op = TK_INTEGER
    While readIndex < tokenLength
        Dim valueByte As UByte = zToken[readIndex]
        If valueByte <> Asc("_") Then
            zToken[writeIndex] = valueByte
            writeIndex += 1
            If valueByte = Asc("e") OrElse valueByte = Asc("E") OrElse _
               valueByte = Asc(".") Then pExpr->op = TK_FLOAT
        Else
            Dim previousByte As UByte = 0
            Dim nextByte As UByte = 0
            If readIndex > 0 Then previousByte = zToken[readIndex - 1]
            If readIndex + 1 < tokenLength Then nextByte = zToken[readIndex + 1]

            Dim previousDigit As SQLITE_C_INT = _
                CInt(previousByte >= Asc("0") AndAlso previousByte <= Asc("9"))
            Dim nextDigit As SQLITE_C_INT = _
                CInt(nextByte >= Asc("0") AndAlso nextByte <= Asc("9"))
            If isHex <> 0 Then
                previousDigit Or= CInt((previousByte >= Asc("a") AndAlso previousByte <= Asc("f")) OrElse _
                                        (previousByte >= Asc("A") AndAlso previousByte <= Asc("F")))
                nextDigit Or= CInt((nextByte >= Asc("a") AndAlso nextByte <= Asc("f")) OrElse _
                                    (nextByte >= Asc("A") AndAlso nextByte <= Asc("F")))
            End If
            If previousDigit = 0 OrElse nextDigit = 0 Then
                sqlite3ErrorMsg(pParse, StrPtr("unrecognized token: ""%s"""), _
                    CPtr(Const ZString Ptr, zToken))
            End If
        End If
        readIndex += 1
    Wend
    zToken[writeIndex] = 0
    If isHex <> 0 Then pExpr->op = TK_INTEGER

    If pExpr->op = TK_INTEGER Then
        Dim integerValue As SQLITE_C_INT = 0
        If sqlite3GetInt32(CPtr(Const ZString Ptr, zToken), @integerValue) <> 0 Then
            pExpr->u.iValue = integerValue
            pExpr->flags Or= EP_IntValue
        End If
    End If
End Sub

Function sqlite3ExprAlloc CDecl Alias "sqlite3ExprAlloc" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal pToken As sqlite3ParserToken Ptr, _
    ByVal dequote As SQLITE_C_INT _
) As SqliteExpr Ptr Export
    If db = 0 Then Return 0
    Dim tokenLength As sqlite3_uint64 = 0
    If pToken <> 0 Then
        If pToken->n > 0 AndAlso pToken->z = 0 Then Return 0
        tokenLength = CULngInt(pToken->n)
    End If
    If tokenLength > SQLITE_MAX_ALLOCATION_SIZE - SizeOf(SqliteExpr) - 1 Then
        sqlite3OomFault(db)
        Return 0
    End If

    Dim allocationBytes As sqlite3_uint64 = SizeOf(SqliteExpr)
    If pToken <> 0 Then allocationBytes += tokenLength + 1
    Dim pExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, _
        sqlite3DbMallocZero(db, allocationBytes))
    If pExpr = 0 Then Return 0
    ' Keep zeroed flags; individual constructors mark EP_Leaf where needed.
    ' SQLite uses upper opcode bits as temporary construction flags.
    pExpr->op = CByte(opcode And &HFF)
    pExpr->iAgg = -1
#if SQLITE_MAX_EXPR_DEPTH > 0
    pExpr->nHeight = 1
#endif
    If pToken <> 0 Then
        pExpr->u.zToken = CPtr(UByte Ptr, pExpr) + SizeOf(SqliteExpr)
        If tokenLength > 0 Then sqlite3ExprMemcpy( _
            pExpr->u.zToken, pToken->z, CULng(tokenLength))
        pExpr->u.zToken[tokenLength] = 0
        If dequote <> 0 Then sqlite3DequoteExpr(pExpr)
    End If
    Return pExpr
End Function

Function sqlite3ExprInt32 CDecl Alias "sqlite3ExprInt32" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal value As SQLITE_C_INT _
) As SqliteExpr Ptr Export
    If db = 0 Then Return 0
    Dim pExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, _
        sqlite3DbMallocZero(db, SizeOf(SqliteExpr)))
    If pExpr = 0 Then Return 0
    pExpr->op = TK_INTEGER
    pExpr->iAgg = -1
    pExpr->flags = EP_IntValue Or EP_Leaf
    If value <> 0 Then
        pExpr->flags Or= EP_IsTrue
    Else
        pExpr->flags Or= EP_IsFalse
    End If
    pExpr->u.iValue = value
#if SQLITE_MAX_EXPR_DEPTH > 0
    pExpr->nHeight = 1
#endif
    Return pExpr
End Function

Function sqlite3PExpr CDecl Alias "sqlite3PExpr" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal pLeft As SqliteExpr Ptr, _
    ByVal pRight As SqliteExpr Ptr _
) As SqliteExpr Ptr Export
    If pParse = 0 OrElse pParse->db = 0 Then Return 0
    Dim db As sqlite3 Ptr = pParse->db
    Dim pExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, _
        sqlite3DbMallocZero(db, SizeOf(SqliteExpr)))
    If pExpr = 0 Then
        sqlite3ExprDelete(db, pLeft)
        sqlite3ExprDelete(db, pRight)
        Return 0
    End If
    ' SQLite uses upper opcode bits as temporary construction flags.
    pExpr->op = CByte(opcode And &HFF)
    pExpr->iAgg = -1
    pExpr->pLeft = pLeft
    pExpr->pRight = pRight
    pExpr->flags = 0
#if SQLITE_MAX_EXPR_DEPTH > 0
    pExpr->nHeight = 1
#endif
    If pLeft <> 0 Then pExpr->flags Or= CPtr(SqliteExpr Ptr, pLeft)->flags And EP_Propagate
    If pRight <> 0 Then pExpr->flags Or= CPtr(SqliteExpr Ptr, pRight)->flags And EP_Propagate
    sqlite3ExprSetHeightAndFlags(pParse, pExpr)
    Return pExpr
End Function

Sub sqlite3ExprSetErrorOffset CDecl Alias "sqlite3ExprSetErrorOffset" ( _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal byteOffset As SQLITE_C_INT _
) Export
    If pExpr = 0 Then Return
    If (pExpr->flags And (EP_OuterON Or EP_InnerON)) <> 0 Then Return
    pExpr->w.iOfst = byteOffset
End Sub

Sub sqlite3ExprCodeMove CDecl Alias "sqlite3ExprCodeMove" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal firstSourceRegister As SQLITE_C_INT, _
    ByVal firstTargetRegister As SQLITE_C_INT, _
    ByVal registerCount As SQLITE_C_INT _
) Export
    If pParse = 0 OrElse pParse->pVdbe = 0 Then Return
    sqlite3VdbeAddOp3(CPtr(SqliteVdbe Ptr, pParse->pVdbe), OP_Move, _
        firstSourceRegister, firstTargetRegister, registerCount)
End Sub

Function sqlite3ExprAssignVarNumber CDecl Alias "sqlite3ExprAssignVarNumber" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal tokenLength As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pParse = 0 OrElse pParse->db = 0 OrElse pExpr = 0 OrElse _
       pExpr->op <> TK_VARIABLE OrElse pExpr->u.zToken = 0 OrElse _
       tokenLength <= 0 Then Return SQLITE_MISUSE

    Dim db As sqlite3 Ptr = pParse->db
    Dim zName As Const UByte Ptr = pExpr->u.zToken
    Dim variableNumber As SQLITE_C_INT = 0
    Dim addName As SQLITE_C_INT = 0

    If zName[0] = Asc("?") Then
        If tokenLength = 1 Then
            If pParse->nVar >= db->aLimit(SQLITE_LIMIT_VARIABLE_NUMBER) Then Return SQLITE_ERROR
            pParse->nVar += 1
            variableNumber = pParse->nVar
        Else
            Dim parsedNumber As SQLITE_C_INT = 0
            For iByte As SQLITE_C_INT = 1 To tokenLength - 1
                Dim digit As SQLITE_C_INT = zName[iByte] - Asc("0")
                If digit < 0 OrElse digit > 9 Then Return SQLITE_ERROR
                If parsedNumber > (db->aLimit(SQLITE_LIMIT_VARIABLE_NUMBER) - digit) \ 10 Then _
                    Return SQLITE_ERROR
                parsedNumber = parsedNumber * 10 + digit
            Next
            If parsedNumber <= 0 OrElse _
               parsedNumber > db->aLimit(SQLITE_LIMIT_VARIABLE_NUMBER) Then _
                Return SQLITE_ERROR
            variableNumber = parsedNumber
            If variableNumber > pParse->nVar Then pParse->nVar = variableNumber
            If sqlite3VListNameToNum(pParse->pVList, _
                                     CPtr(Const ZString Ptr, zName), tokenLength) = 0 Then
                addName = 1
            End If
        End If
    Else
        variableNumber = sqlite3VListNameToNum( _
            pParse->pVList, CPtr(Const ZString Ptr, zName), tokenLength)
        If variableNumber = 0 Then
            If pParse->nVar >= db->aLimit(SQLITE_LIMIT_VARIABLE_NUMBER) Then Return SQLITE_ERROR
            pParse->nVar += 1
            variableNumber = pParse->nVar
            addName = 1
        End If
    End If

    If addName <> 0 Then
        pParse->pVList = sqlite3VListAdd(db, pParse->pVList, _
            CPtr(Const ZString Ptr, zName), tokenLength, variableNumber)
        If db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    End If

    pExpr->iColumn = variableNumber
    Return SQLITE_OK
End Function

/' ------------------------------------------------------------------------- '/
/' Expression tree deletion '/
/' ------------------------------------------------------------------------- '/

Private Sub sqlite3ExprDeleteNN CDecl Alias "sqlite3ExprDeleteNN" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
)
    If pExpr = 0 Then Return

    Dim pCurrent As SqliteExpr Ptr = pExpr
    Do
        If (pCurrent->flags And (EP_TokenOnly Or EP_Leaf)) = 0 Then
            If pCurrent->pRight <> 0 Then
                sqlite3ExprDeleteNN(db, CPtr(SqliteExpr Ptr, pCurrent->pRight))
            ElseIf (pCurrent->flags And EP_xIsSelect) <> 0 Then
                sqlite3SelectDelete(db, CPtr(SqliteSelect Ptr, pCurrent->x.pSelect))
            Else
                sqlite3ExprListDelete(db, CPtr(SqliteExprList Ptr, pCurrent->x.pList))
#ifndef SQLITE_OMIT_WINDOWFUNC
                If (pCurrent->flags And EP_WinFunc) <> 0 Then
                    sqlite3WindowDelete(db, CPtr(SqliteWalkerWindow Ptr, pCurrent->y.pWin))
                End If
#endif
            End If

            If pCurrent->pLeft <> 0 AndAlso pCurrent->op <> TK_SELECT_COLUMN Then
                Dim pLeft As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pCurrent->pLeft)
                If (pCurrent->flags And EP_Static) = 0 AndAlso _
                   (pLeft->flags And EP_Static) = 0 Then
                    ' Free left-linked operators iteratively to bound stack use.
                    sqlite3DbFreeNN(db, pCurrent)
                    pCurrent = pLeft
                    Continue Do
                Else
                    sqlite3ExprDeleteNN(db, pLeft)
                End If
            End If
        End If

        If (pCurrent->flags And EP_Static) = 0 Then _
            sqlite3DbFreeNN(db, pCurrent)
        Exit Do
    Loop
End Sub

Sub sqlite3ExprDelete CDecl Alias "sqlite3ExprDelete" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) Export
    If pExpr <> 0 Then sqlite3ExprDeleteNN(db, pExpr)
End Sub

Sub sqlite3ExprDeleteGeneric CDecl Alias "sqlite3ExprDeleteGeneric" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pExpr As Any Ptr _
) Export
    If pExpr <> 0 Then sqlite3ExprDeleteNN(db, CPtr(SqliteExpr Ptr, pExpr))
End Sub

Sub sqlite3ExprUnmapAndDelete CDecl Alias "sqlite3ExprUnmapAndDelete" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) Export
    If pExpr = 0 Then Return
#ifndef SQLITE_OMIT_ALTERTABLE
    If pParse <> 0 AndAlso pParse->eParseMode >= PARSE_MODE_RENAME Then _
        sqlite3RenameExprUnmap(pParse, pExpr)
#endif
    Dim db As sqlite3 Ptr = 0
    If pParse <> 0 Then db = pParse->db
    sqlite3ExprDeleteNN(db, pExpr)
End Sub

Function sqlite3ExprDeferredDelete CDecl Alias "sqlite3ExprDeferredDelete" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT Export
    If pExpr = 0 Then Return 0
    If pParse = 0 OrElse pParse->db = 0 Then
        sqlite3ExprDeleteGeneric(0, pExpr)
        Return 1
    End If
    Return CInt(sqlite3ParserAddCleanup( _
        pParse, @sqlite3ExprDeleteGeneric, pExpr) = 0)
End Function

Function sqlite3ExprAnd CDecl Alias "sqlite3ExprAnd" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pLeft As SqliteExpr Ptr, _
    ByVal pRight As SqliteExpr Ptr _
) As SqliteExpr Ptr Export
    If pParse = 0 OrElse pParse->db = 0 Then Return 0
    If pLeft = 0 Then Return pRight
    If pRight = 0 Then Return pLeft

    Dim combinedFlags As u32 = pLeft->flags Or pRight->flags
    Dim falseExpressionMask As u32 = _
        EP_OuterON Or EP_InnerON Or EP_IsFalse Or EP_HasFunc
    If (combinedFlags And falseExpressionMask) = EP_IsFalse AndAlso _
       pParse->eParseMode < PARSE_MODE_RENAME Then
        sqlite3ExprDeferredDelete(pParse, pLeft)
        sqlite3ExprDeferredDelete(pParse, pRight)
        Return sqlite3ExprInt32(pParse->db, 0)
    End If

    Return sqlite3PExpr(pParse, TK_AND, pLeft, pRight)
End Function

Function sqlite3ExprSkipCollateAndLikely CDecl Alias "sqlite3ExprSkipCollateAndLikely" ( _
    ByVal pExpr As SqliteExpr Ptr _
) As SqliteExpr Ptr Export
    ' These root wrappers affect comparison policy or planning, not value truth.
    While pExpr <> 0 AndAlso _
          (pExpr->flags And (EP_Skip Or EP_Unlikely)) <> 0
        If (pExpr->flags And EP_Unlikely) <> 0 Then
            If pExpr->op <> TK_FUNCTION OrElse pExpr->x.pList = 0 Then Return 0
            Dim pList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pExpr->x.pList)
            If pList->nExpr <= 0 OrElse pList->nExpr > pList->nAlloc Then Return 0
            Dim pItem As SqliteExprListItem Ptr = sqlite3ExprListItemAt(pList, 0)
            If pItem = 0 OrElse pItem->pExpr = 0 Then Return 0
            pExpr = CPtr(SqliteExpr Ptr, pItem->pExpr)
        ElseIf pExpr->op = TK_COLLATE Then
            pExpr = CPtr(SqliteExpr Ptr, pExpr->pLeft)
        Else
            Exit While
        End If
    Wend
    Return pExpr
End Function

Function sqlite3IsTrueOrFalse CDecl Alias "sqlite3IsTrueOrFalse" ( _
    ByVal zValue As Const ZString Ptr _
) As u32 Export
    If zValue = 0 Then Return 0
    If sqlite3_stricmp(zValue, StrPtr("true")) = 0 Then Return EP_IsTrue
    If sqlite3_stricmp(zValue, StrPtr("false")) = 0 Then Return EP_IsFalse
    Return 0
End Function

Function sqlite3ExprIdToTrueFalse CDecl Alias "sqlite3ExprIdToTrueFalse" ( _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT Export
    If pExpr = 0 OrElse (pExpr->op <> TK_ID AndAlso pExpr->op <> TK_STRING) Then _
        Return 0
    If (pExpr->flags And (EP_Quoted Or EP_IntValue)) <> 0 OrElse _
       pExpr->u.zToken = 0 Then Return 0

    Dim trueFalseFlag As u32 = sqlite3IsTrueOrFalse( _
        CPtr(Const ZString Ptr, pExpr->u.zToken))
    If trueFalseFlag = 0 Then Return 0
    pExpr->op = TK_TRUEFALSE
    pExpr->flags Or= trueFalseFlag
    Return 1
End Function

Function sqlite3ExprTruthValue CDecl Alias "sqlite3ExprTruthValue" ( _
    ByVal pExprArgument As Const SqliteExpr Ptr _
) As SQLITE_C_INT Export
    If pExprArgument = 0 Then Return 0
    Dim pExpr As SqliteExpr Ptr = sqlite3ExprSkipCollateAndLikely( _
        CPtr(SqliteExpr Ptr, pExprArgument))
    If pExpr = 0 OrElse pExpr->op <> TK_TRUEFALSE OrElse _
       pExpr->u.zToken = 0 Then Return 0

    Dim zValue As Const ZString Ptr = CPtr(Const ZString Ptr, pExpr->u.zToken)
    If sqlite3_stricmp(zValue, StrPtr("true")) = 0 Then Return 1
    Return 0
End Function

Function sqlite3ExprCanBeNull CDecl Alias "sqlite3ExprCanBeNull" ( _
    ByVal pExprArgument As Const SqliteExpr Ptr _
) As SQLITE_C_INT Export
    If pExprArgument = 0 Then Return 1
    Dim pExpr As Const SqliteExpr Ptr = pExprArgument
    While pExpr->op = TK_UPLUS OrElse pExpr->op = TK_UMINUS
        pExpr = CPtr(Const SqliteExpr Ptr, pExpr->pLeft)
        If pExpr = 0 Then Return 1
    Wend

    Dim opcode As SQLITE_C_INT = pExpr->op
    If opcode = TK_REGISTER Then opcode = pExpr->op2
    Select Case opcode
    Case TK_INTEGER, TK_STRING, TK_FLOAT, TK_BLOB
        Return 0
    Case Else
        ' A positive answer may cost an optimization; a false negative can alter results.
        Return 1
    End Select
End Function

Function sqlite3ExprNeedsNoAffinityChange CDecl Alias "sqlite3ExprNeedsNoAffinityChange" ( _
    ByVal pExprArgument As Const SqliteExpr Ptr, _
    ByVal affinity As Byte _
) As SQLITE_C_INT Export
    If pExprArgument = 0 Then Return 0
    If affinity = SQLITE_AFF_BLOB Then Return 1

    Dim pExpr As Const SqliteExpr Ptr = pExprArgument
    Dim unaryMinus As SQLITE_C_INT = 0
    While pExpr->op = TK_UPLUS OrElse pExpr->op = TK_UMINUS
        If pExpr->op = TK_UMINUS Then unaryMinus = 1
        If pExpr->pLeft = 0 Then Return 0
        pExpr = CPtr(Const SqliteExpr Ptr, pExpr->pLeft)
    Wend

    Dim opcode As SQLITE_C_INT = pExpr->op
    If opcode = TK_REGISTER Then opcode = pExpr->op2
    Select Case opcode
    Case TK_INTEGER, TK_FLOAT
        Return CInt(affinity >= SQLITE_AFF_NUMERIC)
    Case TK_STRING
        Return CInt(unaryMinus = 0 AndAlso affinity = SQLITE_AFF_TEXT)
    Case TK_BLOB
        Return CInt(unaryMinus = 0)
    Case TK_COLUMN
        Return CInt(affinity >= SQLITE_AFF_NUMERIC AndAlso pExpr->iColumn < 0)
    End Select
    Return 0
End Function

Function sqlite3IsRowid CDecl Alias "sqlite3IsRowid" ( _
    ByVal zName As Const ZString Ptr _
) As SQLITE_C_INT Export
    If zName = 0 Then Return 0
    If sqlite3_stricmp(zName, StrPtr("_ROWID_")) = 0 Then Return 1
    If sqlite3_stricmp(zName, StrPtr("ROWID")) = 0 Then Return 1
    If sqlite3_stricmp(zName, StrPtr("OID")) = 0 Then Return 1
    Return 0
End Function

Function sqlite3ExprIsInteger CDecl Alias "sqlite3ExprIsInteger" ( _
    ByVal pExprArgument As Const SqliteExpr Ptr, _
    ByVal pValue As SQLITE_C_INT Ptr, _
    ByVal pParseArgument As SqliteParseContext Ptr, _
    ByVal reprepareSmallInteger As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pValue = 0 Then Return 0

    Dim pExpr As Const SqliteExpr Ptr = pExprArgument
    Dim pParse As SqliteParseContext Ptr = pParseArgument
    Dim sign As SQLITE_C_INT = 1
    While pExpr <> 0
        If (pExpr->flags And EP_IntValue) <> 0 Then
            pValue[0] = pExpr->u.iValue * sign
            Return 1
        End If
        If pExpr->op = TK_UPLUS Then
            pExpr = CPtr(Const SqliteExpr Ptr, pExpr->pLeft)
            pParse = 0
            Continue While
        ElseIf pExpr->op = TK_UMINUS Then
            sign = -sign
            pExpr = CPtr(Const SqliteExpr Ptr, pExpr->pLeft)
            pParse = 0
            Continue While
        End If
        Exit While
    Wend

    If pExpr = 0 OrElse pExpr->op <> TK_VARIABLE OrElse _
       pParse = 0 OrElse pParse->db = 0 OrElse sign <> 1 OrElse _
       pParse->pVdbe = 0 OrElse _
       (pParse->db->flags And SQLITE_EnableQPSG) <> 0 Then Return 0

    Dim pBoundValue As SqliteVdbeMem Ptr = sqlite3VdbeGetBoundValue( _
        CPtr(SqliteVdbe Ptr, pParse->pReprepare), pExpr->iColumn, SQLITE_AFF_BLOB)
    Dim result As SQLITE_C_INT = 0
    Dim smallInteger As SQLITE_C_INT = 0
    If pBoundValue <> 0 Then
        If sqlite3_value_type(pBoundValue) = SQLITE_INTEGER Then
            Dim integerValue As sqlite3_int64 = sqlite3_value_int64(pBoundValue)
            ' Planner integer checks intentionally accept only signed 32-bit values.
            If integerValue >= 0 AndAlso integerValue <= &H7FFFFFFF Then
                pValue[0] = CInt(integerValue)
                result = 1
                If reprepareSmallInteger <> 0 AndAlso integerValue <= 1 Then _
                    smallInteger = 1
            End If
        End If
        sqlite3ValueFree(pBoundValue)
    End If
    sqlite3VdbeReprepareOnBind( _
        CPtr(SqliteVdbe Ptr, pParse->pVdbe), pExpr->iColumn, smallInteger)
    Return result
End Function

Function sqlite3ExprIsVector CDecl Alias "sqlite3ExprIsVector" ( _
    ByVal pExpr As Const SqliteExpr Ptr _
) As SQLITE_C_INT Export
    If pExpr = 0 Then Return 0
    Return CInt(sqlite3ExprVectorSize(pExpr) > 1)
End Function

Function sqlite3ExprVectorSize CDecl Alias "sqlite3ExprVectorSize" ( _
    ByVal pExprArgument As Const SqliteExpr Ptr _
) As SQLITE_C_INT Export
    If pExprArgument = 0 Then Return 1
    Dim pExpr As Const SqliteExpr Ptr = pExprArgument
    Dim opcode As SQLITE_C_INT = pExpr->op
    If opcode = TK_REGISTER Then opcode = pExpr->op2

    If opcode = TK_VECTOR Then
        If (pExpr->flags And EP_xIsSelect) <> 0 OrElse pExpr->x.pList = 0 Then Return 1
        Dim pList As Const SqliteExprList Ptr = _
            CPtr(Const SqliteExprList Ptr, pExpr->x.pList)
        If pList->nExpr < 0 OrElse pList->nAlloc < pList->nExpr Then Return 1
        Return pList->nExpr
    ElseIf opcode = TK_SELECT Then
        If (pExpr->flags And EP_xIsSelect) = 0 OrElse pExpr->x.pSelect = 0 Then Return 1
        Dim pSelect As Const SqliteSelect Ptr = _
            CPtr(Const SqliteSelect Ptr, pExpr->x.pSelect)
        If pSelect->pEList = 0 Then Return 1
        Dim pList As Const SqliteExprList Ptr = CPtr(Const SqliteExprList Ptr, pSelect->pEList)
        If pList->nExpr < 0 OrElse pList->nAlloc < pList->nExpr Then Return 1
        Return pList->nExpr
    End If
    Return 1
End Function

Function sqlite3VectorFieldSubexpr CDecl Alias "sqlite3VectorFieldSubexpr" ( _
    ByVal pVector As SqliteExpr Ptr, _
    ByVal fieldIndex As SQLITE_C_INT _
) As SqliteExpr Ptr Export
    If pVector = 0 Then Return 0
    Dim vectorSize As SQLITE_C_INT = sqlite3ExprVectorSize(pVector)
    If vectorSize <= 1 Then Return pVector
    If fieldIndex < 0 OrElse fieldIndex >= vectorSize Then Return 0

    Dim opcode As SQLITE_C_INT = pVector->op
    If opcode = TK_REGISTER Then opcode = pVector->op2
    If opcode = TK_SELECT Then
        If (pVector->flags And EP_xIsSelect) = 0 OrElse pVector->x.pSelect = 0 Then Return 0
        Dim pSelect As SqliteSelect Ptr = CPtr(SqliteSelect Ptr, pVector->x.pSelect)
        If pSelect->pEList = 0 Then Return 0
        Dim pList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pSelect->pEList)
        If pList->nAlloc < pList->nExpr OrElse fieldIndex >= pList->nExpr Then Return 0
        Return CPtr(SqliteExpr Ptr, pList->a(fieldIndex).pExpr)
    ElseIf opcode = TK_VECTOR Then
        If (pVector->flags And EP_xIsSelect) <> 0 OrElse pVector->x.pList = 0 Then Return 0
        Dim pList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pVector->x.pList)
        If pList->nAlloc < pList->nExpr OrElse fieldIndex >= pList->nExpr Then Return 0
        Return CPtr(SqliteExpr Ptr, pList->a(fieldIndex).pExpr)
    End If
    Return 0
End Function

Function sqlite3ExprForVectorField CDecl Alias "sqlite3ExprForVectorField" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pVector As SqliteExpr Ptr, _
    ByVal fieldIndex As SQLITE_C_INT, _
    ByVal fieldCount As SQLITE_C_INT _
) As SqliteExpr Ptr Export
    If pParse = 0 OrElse pParse->db = 0 OrElse pVector = 0 OrElse _
       fieldIndex < 0 OrElse fieldCount <= 0 Then Return 0
    Dim vectorSize As SQLITE_C_INT = sqlite3ExprVectorSize(pVector)
    If fieldIndex >= vectorSize Then Return 0

    If pVector->op = TK_SELECT Then
        If (pVector->flags And EP_xIsSelect) = 0 OrElse pVector->x.pSelect = 0 Then Return 0
        Dim pSelect As SqliteSelect Ptr = CPtr(SqliteSelect Ptr, pVector->x.pSelect)
        If pSelect->pEList = 0 Then Return 0
        Dim pResult As SqliteExpr Ptr = _
            sqlite3PExpr(pParse, TK_SELECT_COLUMN, 0, 0)
        If pResult <> 0 Then
            pResult->flags Or= EP_FullSize
            pResult->iTable = fieldCount
            pResult->iColumn = fieldIndex
            pResult->pLeft = pVector
        End If
        Return pResult
    End If

    If pVector->op = TK_VECTOR Then
        If (pVector->flags And EP_xIsSelect) <> 0 OrElse pVector->x.pList = 0 Then Return 0
        Dim pList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pVector->x.pList)
        If pList->nExpr < 0 OrElse pList->nAlloc < pList->nExpr OrElse _
           fieldIndex >= pList->nExpr Then Return 0
        Dim pField As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pList->a(fieldIndex).pExpr)
        If pField = 0 Then Return 0
        If pParse->eParseMode >= PARSE_MODE_RENAME Then
            pList->a(fieldIndex).pExpr = 0
            Return pField
        End If
        pVector = pField
    End If

    Return sqlite3ExprDup(pParse->db, pVector, 0)
End Function

Function sqlite3SelectDup CDecl Alias "sqlite3SelectDup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pSource As Const SqliteSelect Ptr, _
    ByVal duplicateFlags As SQLITE_C_INT _
) As SqliteSelect Ptr Export
    If db = 0 OrElse pSource = 0 OrElse _
       (duplicateFlags <> 0 AndAlso duplicateFlags <> 1) Then Return 0

    Dim pResult As SqliteSelect Ptr = 0
    Dim pPrevious As SqliteSelect Ptr = 0
    Dim pNextCopy As SqliteSelect Ptr = 0
    Dim pCurrent As Const SqliteSelect Ptr = pSource
    Dim nSelect As SQLITE_C_INT = 0
    Dim maximumSelects As SQLITE_C_INT = _
        db->aLimit(SQLITE_LIMIT_COMPOUND_SELECT)
    If maximumSelects <= 0 Then maximumSelects = SQLITE_MAX_COMPOUND_SELECT

    While pCurrent <> 0
        nSelect += 1
        If nSelect > maximumSelects Then Exit While

        Dim pNew As SqliteSelect Ptr = CPtr(SqliteSelect Ptr, _
            sqlite3DbMallocRawNN(db, SizeOf(SqliteSelect)))
        If pNew = 0 Then Exit While

        ' Allocate the Select owner first, so every partially copied child is
        ' attached to it and the normal deep-delete path can unwind OOM.
        pNew->pPrior = 0
        pNew->pNext = 0
        pNew->pWith = 0
        pNew->pEList = sqlite3ExprListDup( _
            db, CPtr(Const SqliteExprList Ptr, pCurrent->pEList), duplicateFlags)
        pNew->pSrc = CPtr(SqliteSrcList Ptr, sqlite3SrcListDup( _
            db, CPtr(Const SqliteSrcList Ptr, pCurrent->pSrc), duplicateFlags))
        pNew->pWhere = sqlite3ExprDup( _
            db, CPtr(Const SqliteExpr Ptr, pCurrent->pWhere), duplicateFlags)
        pNew->pGroupBy = sqlite3ExprListDup( _
            db, CPtr(Const SqliteExprList Ptr, pCurrent->pGroupBy), duplicateFlags)
        pNew->pHaving = sqlite3ExprDup( _
            db, CPtr(Const SqliteExpr Ptr, pCurrent->pHaving), duplicateFlags)
        pNew->pOrderBy = sqlite3ExprListDup( _
            db, CPtr(Const SqliteExprList Ptr, pCurrent->pOrderBy), duplicateFlags)
        If pCurrent->pWith <> 0 Then
            pNew->pWith = sqlite3WithDup(db, _
                CPtr(Const SqliteWith Ptr, pCurrent->pWith))
        End If
#ifndef SQLITE_OMIT_WINDOWFUNC
        pNew->pWin = 0
        pNew->pWinDefn = sqlite3WindowListDup( _
            db, CPtr(SqliteWalkerWindow Ptr, pCurrent->pWinDefn))
        If pCurrent->pWin <> 0 AndAlso db->mallocFailed = 0 Then _
            gatherSelectWindows(pNew)
#endif
        pNew->pLimit = sqlite3ExprDup( _
            db, CPtr(Const SqliteExpr Ptr, pCurrent->pLimit), duplicateFlags)
        pNew->op = pCurrent->op
        pNew->nSelectRow = pCurrent->nSelectRow
        pNew->selFlags = pCurrent->selFlags
        pNew->selId = pCurrent->selId
        pNew->iLimit = 0
        pNew->iOffset = 0
        pNew->pPrior = 0
        pNew->pNext = 0

        If (pCurrent->pEList <> 0 AndAlso pNew->pEList = 0) OrElse _
           (pCurrent->pSrc <> 0 AndAlso pNew->pSrc = 0) OrElse _
           (pCurrent->pWhere <> 0 AndAlso pNew->pWhere = 0) OrElse _
           (pCurrent->pGroupBy <> 0 AndAlso pNew->pGroupBy = 0) OrElse _
           (pCurrent->pHaving <> 0 AndAlso pNew->pHaving = 0) OrElse _
           (pCurrent->pOrderBy <> 0 AndAlso pNew->pOrderBy = 0) OrElse _
           (pCurrent->pLimit <> 0 AndAlso pNew->pLimit = 0) OrElse _
           (pCurrent->pWith <> 0 AndAlso pNew->pWith = 0) OrElse _
           db->mallocFailed <> 0 Then
            sqlite3SelectDelete(db, pNew)
            sqlite3SelectDelete(db, pResult)
            Return 0
        End If

        pNew->pNext = pNextCopy
        If pPrevious = 0 Then
            pResult = pNew
        Else
            pPrevious->pPrior = pNew
        End If
        pPrevious = pNew
        pNextCopy = pNew
        pCurrent = CPtr(Const SqliteSelect Ptr, pCurrent->pPrior)
    Wend

    If pCurrent <> 0 Then
        sqlite3SelectDelete(db, pResult)
        Return 0
    End If
    Return pResult
End Function

Private Function sqlite3ExprIsNotTrue CDecl Alias "sqlite3ExprIsNotTrue" ( _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT
    If pExpr = 0 Then Return 0
    If pExpr->op = TK_NULL Then Return 1
    If pExpr->op = TK_TRUEFALSE AndAlso sqlite3ExprTruthValue(pExpr) = 0 Then _
        Return 1
    Dim integerValue As SQLITE_C_INT = 1
    If sqlite3ExprIsInteger(pExpr, @integerValue, 0, 0) <> 0 AndAlso _
       integerValue = 0 Then Return 1
    Return 0
End Function

Function sqlite3ExprListAppendNew CDecl Alias "sqlite3ExprListAppendNew" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SqliteExprList Ptr Export
    If db = 0 Then Return 0

    Dim initialCount As SQLITE_C_INT = 4
    Dim headerBytes As sqlite3_uint64 = _
        SizeOf(SqliteExprList) - SizeOf(SqliteExprListItem)
    If headerBytes > SQLITE_MAX_ALLOCATION_SIZE OrElse _
       initialCount > (SQLITE_MAX_ALLOCATION_SIZE - headerBytes) / _
                      SizeOf(SqliteExprListItem) Then
        sqlite3OomFault(db)
        sqlite3ExprDelete(db, pExpr)
        Return 0
    End If
    Dim allocationBytes As sqlite3_uint64 = _
        headerBytes + CULngInt(initialCount) * SizeOf(SqliteExprListItem)
    Dim pList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, _
        sqlite3DbMallocRawNN(db, allocationBytes))
    If pList = 0 Then
        sqlite3ExprDelete(db, pExpr)
        Return 0
    End If

    pList->nAlloc = initialCount
    pList->nExpr = 1
    Dim pItem As SqliteExprListItem Ptr = sqlite3ExprListItemAt(pList, 0)
    If pItem = 0 Then
        sqlite3DbFree(db, pList)
        sqlite3ExprDelete(db, pExpr)
        Return 0
    End If
    Dim pItemBytes As UByte Ptr = CPtr(UByte Ptr, pItem)
    For byteIndex As SQLITE_C_INT = 0 To CInt(SizeOf(SqliteExprListItem)) - 1
        pItemBytes[byteIndex] = 0
    Next
    pItem->pExpr = pExpr
    Return pList
End Function

Function sqlite3ExprListAppendGrow CDecl Alias "sqlite3ExprListAppendGrow" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pListArgument As SqliteExprList Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SqliteExprList Ptr Export
    Dim pList As SqliteExprList Ptr = pListArgument
    If db = 0 OrElse pList = 0 OrElse pList->nExpr < 0 OrElse _
       pList->nAlloc < pList->nExpr OrElse pList->nAlloc <= 0 OrElse _
       pList->nAlloc > &H3FFFFFFF Then
        If db <> 0 Then
            sqlite3ExprDelete(db, pExpr)
            sqlite3ExprListDelete(db, pList)
        End If
        Return 0
    End If

    Dim newCount As SQLITE_C_INT = pList->nAlloc * 2
    Dim headerBytes As sqlite3_uint64 = _
        SizeOf(SqliteExprList) - SizeOf(SqliteExprListItem)
    If headerBytes > SQLITE_MAX_ALLOCATION_SIZE OrElse _
       newCount > (SQLITE_MAX_ALLOCATION_SIZE - headerBytes) / _
                  SizeOf(SqliteExprListItem) Then
        sqlite3ExprDelete(db, pExpr)
        sqlite3ExprListDelete(db, pList)
        sqlite3OomFault(db)
        Return 0
    End If

    Dim newAllocationBytes As sqlite3_uint64 = _
        headerBytes + CULngInt(newCount) * SizeOf(SqliteExprListItem)
    Dim pNewList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, _
        sqlite3DbRealloc(db, pList, newAllocationBytes))
    If pNewList = 0 Then
        sqlite3ExprDelete(db, pExpr)
        sqlite3ExprListDelete(db, pList)
        Return 0
    End If

    pList = pNewList
    pList->nAlloc = newCount
    Dim pItem As SqliteExprListItem Ptr = _
        sqlite3ExprListItemAt(pList, pList->nExpr)
    If pItem = 0 Then
        sqlite3ExprDelete(db, pExpr)
        sqlite3ExprListDelete(db, pList)
        Return 0
    End If
    Dim pItemBytes As UByte Ptr = CPtr(UByte Ptr, pItem)
    For byteIndex As SQLITE_C_INT = 0 To CInt(SizeOf(SqliteExprListItem)) - 1
        pItemBytes[byteIndex] = 0
    Next
    pItem->pExpr = pExpr
    pList->nExpr += 1
    Return pList
End Function

Function sqlite3ExprListAppend CDecl Alias "sqlite3ExprListAppend" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pListArgument As SqliteExprList Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SqliteExprList Ptr Export
    If pParse = 0 OrElse pParse->db = 0 Then Return 0
    Dim db As sqlite3 Ptr = pParse->db
    Dim pList As SqliteExprList Ptr = pListArgument
    If pList = 0 Then Return sqlite3ExprListAppendNew(db, pExpr)
    If pList->nExpr < 0 OrElse pList->nAlloc < pList->nExpr Then
        sqlite3ExprDelete(db, pExpr)
        sqlite3ExprListDelete(db, pList)
        Return 0
    End If
    If pList->nExpr >= pList->nAlloc Then _
        Return sqlite3ExprListAppendGrow(db, pList, pExpr)

    Dim pItem As SqliteExprListItem Ptr = _
        sqlite3ExprListItemAt(pList, pList->nExpr)
    If pItem = 0 Then
        sqlite3ExprDelete(db, pExpr)
        sqlite3ExprListDelete(db, pList)
        Return 0
    End If
    Dim pItemBytes As UByte Ptr = CPtr(UByte Ptr, pItem)
    For byteIndex As SQLITE_C_INT = 0 To CInt(SizeOf(SqliteExprListItem)) - 1
        pItemBytes[byteIndex] = 0
    Next
    pItem->pExpr = pExpr
    pList->nExpr += 1
    Return pList
End Function

Function sqlite3IdListAppend CDecl Alias "sqlite3IdListAppend" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pListArgument As SqliteIdList Ptr, _
    ByVal pToken As sqlite3ParserToken Ptr _
) As SqliteIdList Ptr Export
    If pParse = 0 OrElse pParse->db = 0 Then Return 0
    Dim db As sqlite3 Ptr = pParse->db
    Dim pList As SqliteIdList Ptr = pListArgument
    Dim oldCount As SQLITE_C_INT = 0
    If pList <> 0 Then
        oldCount = pList->nId
        If oldCount < 0 OrElse oldCount = &H7FFFFFFF Then
            sqlite3OomFault(db)
            Return 0
        End If
    End If

    Dim newCount As sqlite3_uint64 = CULngInt(oldCount) + 1
    Dim headerBytes As sqlite3_uint64 = _
        SizeOf(SqliteIdList) - SizeOf(SqliteIdListItem)
    If newCount > (SQLITE_MAX_ALLOCATION_SIZE - headerBytes) / _
                  SizeOf(SqliteIdListItem) Then
        sqlite3OomFault(db)
        If pList <> 0 Then sqlite3IdListDelete(db, pList)
        Return 0
    End If
    Dim allocationBytes As sqlite3_uint64 = _
        headerBytes + newCount * SizeOf(SqliteIdListItem)

    If pList = 0 Then
        pList = CPtr(SqliteIdList Ptr, sqlite3DbMallocZero(db, allocationBytes))
    Else
        Dim pResized As SqliteIdList Ptr = CPtr(SqliteIdList Ptr, _
            sqlite3DbRealloc(db, pList, allocationBytes))
        If pResized = 0 Then
            sqlite3IdListDelete(db, pList)
            Return 0
        End If
        pList = pResized
    End If
    If pList = 0 Then Return 0

    Dim itemIndex As SQLITE_C_INT = pList->nId
    pList->nId += 1
    pList->a(itemIndex).zName = sqlite3NameFromToken(db, pToken)
    If pParse->eParseMode >= PARSE_MODE_RENAME AndAlso _
       pList->a(itemIndex).zName <> 0 AndAlso pToken <> 0 Then
        sqlite3RenameTokenMap(pParse, pList->a(itemIndex).zName, pToken)
    End If
    Return pList
End Function

Sub sqlite3ExprListDelete CDecl Alias "sqlite3ExprListDelete" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pList As SqliteExprList Ptr _
) Export
    If pList = 0 Then Return
    If pList->nExpr > 0 AndAlso pList->nExpr <= pList->nAlloc Then
        For iExpr As SQLITE_C_INT = 0 To pList->nExpr - 1
            Dim pItem As SqliteExprListItem Ptr = sqlite3ExprListItemAt(pList, iExpr)
            If pItem <> 0 Then
                sqlite3ExprDelete(db, CPtr(SqliteExpr Ptr, pItem->pExpr))
                If pItem->zEName <> 0 Then sqlite3DbFree(db, pItem->zEName)
            End If
        Next
    End If
    sqlite3DbFree(db, pList)
End Sub

Private Function exprStructSize CDecl Alias "exprStructSize" ( _
    ByVal pExpr As Const SqliteExpr Ptr _
) As SQLITE_C_INT
    If pExpr = 0 Then Return 0
    If (pExpr->flags And EP_TokenOnly) <> 0 Then
        Dim sample As SqliteExpr
        Dim baseAddress As sqlite3_uint64 = _
            CULngInt(CPtr(Any Ptr, @sample))
        Dim tokenOnlyAddress As sqlite3_uint64 = _
            CULngInt(CPtr(Any Ptr, @sample.pLeft))
        If tokenOnlyAddress < baseAddress Then Return 0
        Dim tokenOnlySize As sqlite3_uint64 = tokenOnlyAddress - baseAddress
        If tokenOnlySize = 0 OrElse tokenOnlySize > SizeOf(SqliteExpr) Then Return 0
        Return CInt(tokenOnlySize)
    End If
    If (pExpr->flags And EP_Reduced) <> 0 Then
        Dim sample As SqliteExpr
        Dim baseAddress As sqlite3_uint64 = _
            CULngInt(CPtr(Any Ptr, @sample))
        Dim reducedAddress As sqlite3_uint64 = _
            CULngInt(CPtr(Any Ptr, @sample.iTable))
        If reducedAddress < baseAddress Then Return 0
        Dim reducedSize As sqlite3_uint64 = reducedAddress - baseAddress
        If reducedSize = 0 OrElse reducedSize > SizeOf(SqliteExpr) Then Return 0
        Return CInt(reducedSize)
    End If
    If SizeOf(SqliteExpr) > &H7FFFFFFF Then Return 0
    Return CInt(SizeOf(SqliteExpr))
End Function

Private Const EXPR_DUP_REDUCE As SQLITE_C_INT = 1
Private Const EXPR_DUP_SIZE_MASK As SQLITE_C_INT = &H0FFF

Private Function exprDupAlign8( _
    ByVal byteCount As sqlite3_uint64 _
) As sqlite3_uint64
    If byteCount > SQLITE_MAX_ALLOCATION_SIZE - 7 Then Return 0
    Return (byteCount + 7) And Not Cast(sqlite3_uint64, 7)
End Function

Private Function exprDupAddSize( _
    ByRef totalBytes As sqlite3_uint64, _
    ByVal addition As sqlite3_uint64 _
) As SQLITE_C_INT
    If addition > SQLITE_MAX_ALLOCATION_SIZE OrElse _
       totalBytes > SQLITE_MAX_ALLOCATION_SIZE - addition Then Return 0
    totalBytes += addition
    Return 1
End Function

Private Function exprDupStructSize( _
    ByVal pExpr As Const SqliteExpr Ptr, _
    ByVal duplicateFlags As SQLITE_C_INT _
) As SQLITE_C_INT
    If pExpr = 0 OrElse _
       (duplicateFlags <> 0 AndAlso duplicateFlags <> EXPR_DUP_REDUCE) Then _
        Return 0

    Dim fullSize As sqlite3_uint64 = SizeOf(SqliteExpr)
    If fullSize = 0 OrElse fullSize > EXPR_DUP_SIZE_MASK Then Return 0
    ' FreeBASIC readers currently use tail Expr fields without consistently
    ' checking EP_Reduced. Keep each record full-sized while sharing its tree buffer.
    Return CInt(fullSize)
End Function

Private Function exprDupNodeSize( _
    ByVal pExpr As Const SqliteExpr Ptr, _
    ByVal duplicateFlags As SQLITE_C_INT _
) As sqlite3_uint64
    Dim sizeAndFlags As SQLITE_C_INT = _
        exprDupStructSize(pExpr, duplicateFlags)
    If sizeAndFlags = 0 Then Return 0

    Dim byteCount As sqlite3_uint64 = _
        CULngInt(sizeAndFlags And EXPR_DUP_SIZE_MASK)
    If (pExpr->flags And EP_IntValue) = 0 AndAlso pExpr->u.zToken <> 0 Then
        Dim tokenLength As SQLITE_C_INT = sqlite3Strlen30( _
            CPtr(Const ZString Ptr, pExpr->u.zToken))
        If tokenLength < 0 OrElse _
           CULngInt(tokenLength) + 1 > SQLITE_MAX_ALLOCATION_SIZE - byteCount Then _
            Return 0
        byteCount += CULngInt(tokenLength) + 1
    End If
    Return exprDupAlign8(byteCount)
End Function

Private Function exprDupTreeSize( _
    ByVal pExpr As Const SqliteExpr Ptr, _
    ByVal depth As SQLITE_C_INT _
) As sqlite3_uint64
    If pExpr = 0 OrElse depth <= 0 Then Return 0
#if SQLITE_MAX_EXPR_DEPTH > 0
    If depth > SQLITE_MAX_EXPR_DEPTH Then Return 0
#endif

    Dim totalBytes As sqlite3_uint64 = _
        exprDupNodeSize(pExpr, EXPR_DUP_REDUCE)
    If totalBytes = 0 Then Return 0

    If pExpr->pLeft <> 0 Then
        Dim leftBytes As sqlite3_uint64 = exprDupTreeSize( _
            CPtr(Const SqliteExpr Ptr, pExpr->pLeft), depth + 1)
        If leftBytes = 0 OrElse exprDupAddSize(totalBytes, leftBytes) = 0 Then _
            Return 0
    End If
    If pExpr->pRight <> 0 Then
        Dim rightBytes As sqlite3_uint64 = exprDupTreeSize( _
            CPtr(Const SqliteExpr Ptr, pExpr->pRight), depth + 1)
        If rightBytes = 0 OrElse exprDupAddSize(totalBytes, rightBytes) = 0 Then _
            Return 0
    End If
    Return totalBytes
End Function

Private Function exprDup CDecl Alias "exprDup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pSource As Const SqliteExpr Ptr, _
    ByVal duplicateFlags As SQLITE_C_INT, _
    ByVal pEdupBuffer As SqliteExprDupBuffer Ptr _
) As SqliteExpr Ptr
    If db = 0 OrElse pSource = 0 OrElse _
       (duplicateFlags <> 0 AndAlso duplicateFlags <> 1) OrElse _
       (pEdupBuffer <> 0 AndAlso duplicateFlags <> EXPR_DUP_REDUCE) Then Return 0

    Dim sourceStructSize As SQLITE_C_INT = exprStructSize(pSource)
    If sourceStructSize <= 0 OrElse sourceStructSize > SizeOf(SqliteExpr) Then Return 0

    Dim hasToken As SQLITE_C_INT = _
        CInt((pSource->flags And EP_IntValue) = 0 AndAlso pSource->u.zToken <> 0)
    Dim tokenLength As SQLITE_C_INT = 0
    Dim tokenBytes As sqlite3_uint64 = 0
    If hasToken <> 0 Then
        tokenLength = sqlite3Strlen30(CPtr(Const ZString Ptr, pSource->u.zToken))
        If tokenLength < 0 OrElse tokenLength > db->lengthLimit Then Return 0
        tokenBytes = CULngInt(tokenLength) + 1
    End If

    Dim structSizeAndFlags As SQLITE_C_INT = _
        exprDupStructSize(pSource, duplicateFlags)
    If structSizeAndFlags = 0 Then Return 0
    Dim newStructSize As SQLITE_C_INT = _
        structSizeAndFlags And EXPR_DUP_SIZE_MASK
    If newStructSize <= 0 OrElse newStructSize > SizeOf(SqliteExpr) Then Return 0
    If duplicateFlags = EXPR_DUP_REDUCE AndAlso _
       sourceStructSize <> SizeOf(SqliteExpr) Then Return 0

    Dim copySize As SQLITE_C_INT = newStructSize
    If duplicateFlags = 0 Then copySize = sourceStructSize
    If copySize <= 0 OrElse copySize > newStructSize Then Return 0

    Dim nodeBytes As sqlite3_uint64 = exprDupAlign8( _
        CULngInt(newStructSize) + tokenBytes)
    If nodeBytes = 0 Then Return 0

    Dim buffer As SqliteExprDupBuffer
    Dim allocationBytes As sqlite3_uint64 = 0
    Dim pAllocation As Any Ptr = 0
    Dim staticFlag As u32 = 0
    If pEdupBuffer <> 0 Then
        buffer = pEdupBuffer[0]
        staticFlag = EP_Static
    Else
        If duplicateFlags = EXPR_DUP_REDUCE Then
            allocationBytes = exprDupTreeSize(pSource, 1)
        Else
            allocationBytes = exprDupAlign8( _
                CULngInt(SizeOf(SqliteExpr)) + tokenBytes)
        End If
        If allocationBytes = 0 OrElse allocationBytes < nodeBytes Then Return 0

        pAllocation = sqlite3DbMallocRawNN(db, allocationBytes)
        If pAllocation = 0 Then Return 0
        buffer.zAlloc = CPtr(UByte Ptr, pAllocation)
        buffer.zEnd = buffer.zAlloc + allocationBytes
    End If

    If buffer.zAlloc = 0 OrElse buffer.zEnd = 0 Then
        If pAllocation <> 0 Then sqlite3DbFree(db, pAllocation)
        Return 0
    End If
    Dim allocationStart As sqlite3_uint64 = _
        CULngInt(CPtr(Any Ptr, buffer.zAlloc))
    Dim allocationEnd As sqlite3_uint64 = _
        CULngInt(CPtr(Any Ptr, buffer.zEnd))
    If allocationEnd < allocationStart OrElse _
       nodeBytes > allocationEnd - allocationStart OrElse _
       (allocationStart And 7) <> 0 Then
        If pAllocation <> 0 Then sqlite3DbFree(db, pAllocation)
        Return 0
    End If

    Dim pNew As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, buffer.zAlloc)
    sqlite3ExprMemcpy(pNew, pSource, CULngInt(copySize))
    If duplicateFlags = 0 AndAlso copySize < SizeOf(SqliteExpr) Then
        Dim pUnusedFields As UByte Ptr = CPtr(UByte Ptr, pNew) + copySize
        For byteIndex As SQLITE_C_INT = copySize To _
            CInt(SizeOf(SqliteExpr)) - 1
            pUnusedFields[byteIndex - copySize] = 0
        Next
    End If

    pNew->flags = pNew->flags And _
        Not (EP_Reduced Or EP_TokenOnly Or EP_Static)
    pNew->flags Or= structSizeAndFlags And (EP_Reduced Or EP_TokenOnly)
    pNew->flags Or= staticFlag
#ifdef SQLITE_DEBUG
    pNew->vvaFlags = 0
    If duplicateFlags = EXPR_DUP_REDUCE Then _
        pNew->vvaFlags Or= EP_Immutable
#endif

    If hasToken <> 0 Then
        pNew->u.zToken = buffer.zAlloc + newStructSize
        If tokenBytes > 0 Then sqlite3ExprMemcpy( _
            pNew->u.zToken, pSource->u.zToken, tokenBytes)
    End If
    buffer.zAlloc += nodeBytes

    ' Clear owned pointers before rebuilding them so failure cleanup cannot
    ' release storage still owned by the source expression.
    pNew->pLeft = 0
    pNew->pRight = 0
#ifndef SQLITE_OMIT_WINDOWFUNC
    If (pSource->flags And EP_WinFunc) <> 0 AndAlso _
       newStructSize >= SizeOf(SqliteExpr) Then pNew->y.pWin = 0
#endif
    If (pSource->flags And EP_xIsSelect) <> 0 Then
        pNew->x.pSelect = 0
    Else
        pNew->x.pList = 0
    End If

    If (pSource->flags And (EP_TokenOnly Or EP_Leaf)) = 0 Then
        If (pSource->flags And EP_xIsSelect) <> 0 Then
            If pSource->x.pSelect <> 0 Then
                pNew->x.pSelect = sqlite3SelectDup( _
                    db, CPtr(Const SqliteSelect Ptr, pSource->x.pSelect), duplicateFlags)
                If pNew->x.pSelect = 0 Then
                    sqlite3ExprDelete(db, pNew)
                    Return 0
                End If
            End If
        ElseIf pSource->x.pList <> 0 Then
            pNew->x.pList = sqlite3ExprListDup( _
                db, CPtr(Const SqliteExprList Ptr, pSource->x.pList), duplicateFlags)
            If pNew->x.pList = 0 Then
                sqlite3ExprDelete(db, pNew)
                Return 0
            End If
        End If
#ifndef SQLITE_OMIT_WINDOWFUNC
        If (pSource->flags And EP_WinFunc) <> 0 Then
            pNew->y.pWin = sqlite3WindowDup( _
                db, pNew, CPtr(SqliteWalkerWindow Ptr, pSource->y.pWin))
            If pNew->y.pWin = 0 Then
                sqlite3ExprDelete(db, pNew)
                Return 0
            End If
        End If
#endif
        If pSource->op = TK_SELECT_COLUMN Then
            pNew->pLeft = pSource->pLeft
        ElseIf pSource->pLeft <> 0 Then
            If duplicateFlags = EXPR_DUP_REDUCE Then
                pNew->pLeft = exprDup( _
                    db, CPtr(Const SqliteExpr Ptr, pSource->pLeft), _
                    duplicateFlags, @buffer)
            Else
                pNew->pLeft = exprDup( _
                    db, CPtr(Const SqliteExpr Ptr, pSource->pLeft), _
                    duplicateFlags, 0)
            End If
            If pNew->pLeft = 0 Then
                sqlite3ExprDelete(db, pNew)
                Return 0
            End If
        End If
        If pSource->pRight <> 0 Then
            If duplicateFlags = EXPR_DUP_REDUCE Then
                pNew->pRight = exprDup( _
                    db, CPtr(Const SqliteExpr Ptr, pSource->pRight), _
                    duplicateFlags, @buffer)
            Else
                pNew->pRight = exprDup( _
                    db, CPtr(Const SqliteExpr Ptr, pSource->pRight), _
                    duplicateFlags, 0)
            End If
            If pNew->pRight = 0 Then
                sqlite3ExprDelete(db, pNew)
                Return 0
            End If
        End If
    End If

    If pEdupBuffer <> 0 Then pEdupBuffer[0] = buffer
    Return pNew
End Function

Function sqlite3ExprDup CDecl Alias "sqlite3ExprDup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pExpr As Const SqliteExpr Ptr, _
    ByVal duplicateFlags As SQLITE_C_INT _
) As SqliteExpr Ptr Export
    If pExpr = 0 Then Return 0
    Return exprDup(db, pExpr, duplicateFlags, 0)
End Function

Function sqlite3ExprListDup CDecl Alias "sqlite3ExprListDup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pSource As Const SqliteExprList Ptr, _
    ByVal duplicateFlags As SQLITE_C_INT _
) As SqliteExprList Ptr Export
    If db = 0 OrElse pSource = 0 OrElse pSource->nExpr < 0 OrElse _
       pSource->nAlloc < pSource->nExpr OrElse pSource->nAlloc < 0 Then Return 0
    If duplicateFlags <> 0 AndAlso duplicateFlags <> 1 Then Return 0

    Dim allocationBytes As sqlite3_uint64 = _
        SizeOf(SqliteExprList) - SizeOf(SqliteExprListItem) + _
        CULngInt(pSource->nAlloc) * SizeOf(SqliteExprListItem)
    If allocationBytes > SQLITE_MAX_ALLOCATION_SIZE Then Return 0
    Dim pNewExprList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, _
        sqlite3DbMallocZero(db, allocationBytes))
    If pNewExprList = 0 Then Return 0
    pNewExprList->nExpr = pSource->nExpr
    pNewExprList->nAlloc = pSource->nAlloc

    Dim pPriorSelectColumnSource As SqliteExpr Ptr = 0
    Dim pPriorSelectColumnCopy As SqliteExpr Ptr = 0
    For itemIndex As SQLITE_C_INT = 0 To pSource->nExpr - 1
        Dim pSourceItem As Const SqliteExprListItem Ptr = @pSource->a(itemIndex)
        Dim pNewItem As SqliteExprListItem Ptr = @pNewExprList->a(itemIndex)
        Dim pOldExpr As Const SqliteExpr Ptr = _
            CPtr(Const SqliteExpr Ptr, pSourceItem->pExpr)
        If pSourceItem->pExpr <> 0 Then
            pNewItem->pExpr = sqlite3ExprDup( _
                db, CPtr(Const SqliteExpr Ptr, pSourceItem->pExpr), duplicateFlags)
            If pNewItem->pExpr = 0 Then
                sqlite3ExprListDelete(db, pNewExprList)
                Return 0
            End If
        End If
        Dim pNewExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pNewItem->pExpr)
        If pOldExpr <> 0 AndAlso pOldExpr->op = TK_SELECT_COLUMN AndAlso _
           pNewExpr <> 0 Then
            If pNewExpr->pRight <> 0 Then
                pPriorSelectColumnSource = CPtr(SqliteExpr Ptr, pOldExpr->pRight)
                pPriorSelectColumnCopy = CPtr(SqliteExpr Ptr, pNewExpr->pRight)
                pNewExpr->pLeft = pNewExpr->pRight
            Else
                If pOldExpr->pLeft <> pPriorSelectColumnSource Then
                    pPriorSelectColumnSource = CPtr(SqliteExpr Ptr, pOldExpr->pLeft)
                    pPriorSelectColumnCopy = sqlite3ExprDup( _
                        db, CPtr(Const SqliteExpr Ptr, pPriorSelectColumnSource), duplicateFlags)
                    If pPriorSelectColumnSource <> 0 AndAlso _
                       pPriorSelectColumnCopy = 0 Then
                        sqlite3ExprListDelete(db, pNewExprList)
                        Return 0
                    End If
                    pNewExpr->pRight = pPriorSelectColumnCopy
                End If
                pNewExpr->pLeft = pPriorSelectColumnCopy
            End If
        End If
        If pSourceItem->zEName <> 0 Then
            pNewItem->zEName = CPtr(UByte Ptr, sqlite3DbStrDup( _
                db, CPtr(Const ZString Ptr, pSourceItem->zEName)))
            If pNewItem->zEName = 0 Then
                sqlite3ExprListDelete(db, pNewExprList)
                Return 0
            End If
        End If
        pNewItem->fg.sortFlags = pSourceItem->fg.sortFlags
        pNewItem->fg.flags = pSourceItem->fg.flags
        pNewItem->u = pSourceItem->u
    Next
    Return pNewExprList
End Function

Sub sqlite3ExprListSetName CDecl Alias "sqlite3ExprListSetName" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pList As SqliteExprList Ptr, _
    ByVal pName As sqlite3ParserToken Ptr, _
    ByVal dequote As SQLITE_C_INT _
) Export
    If pParse = 0 OrElse pParse->db = 0 OrElse pList = 0 OrElse _
       pName = 0 OrElse pList->nExpr <= 0 OrElse pName->n = 0 OrElse _
       pName->z = 0 Then Return
    Dim pItem As SqliteExprListItem Ptr = sqlite3ExprListItemAt( _
        pList, pList->nExpr - 1)
    If pItem = 0 OrElse pItem->zEName <> 0 Then Return
    pItem->zEName = CPtr(UByte Ptr, sqlite3DbStrNDup( _
        pParse->db, CPtr(Const ZString Ptr, pName->z), CULngInt(pName->n)))
    If pItem->zEName <> 0 AndAlso dequote <> 0 Then
        sqlite3Dequote(CPtr(ZString Ptr, pItem->zEName))
#ifndef SQLITE_OMIT_ALTERTABLE
        ' Preserve the DDL token so ALTER RENAME COLUMN can edit this name.
        If pParse->eParseMode >= PARSE_MODE_RENAME Then _
            sqlite3RenameTokenMap(pParse, pItem->zEName, pName)
#endif
    End If
End Sub

Sub sqlite3ExprListSetSpan CDecl Alias "sqlite3ExprListSetSpan" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pList As SqliteExprList Ptr, _
    ByVal zStart As Const UByte Ptr, _
    ByVal zEnd As Const UByte Ptr _
) Export
    If pParse = 0 OrElse pParse->db = 0 OrElse pList = 0 OrElse _
       pList->nExpr <= 0 OrElse zStart = 0 OrElse zEnd = 0 OrElse zEnd < zStart Then Return
    Dim pItem As SqliteExprListItem Ptr = sqlite3ExprListItemAt( _
        pList, pList->nExpr - 1)
    If pItem = 0 OrElse pItem->zEName <> 0 Then Return
    pItem->zEName = CPtr(UByte Ptr, sqlite3DbSpanDup( _
        pParse->db, CPtr(Const ZString Ptr, zStart), CPtr(Const ZString Ptr, zEnd)))
    If pItem->zEName <> 0 Then pItem->fg.flags = _
        (pItem->fg.flags And Not 3) Or ENAME_SPAN
End Sub

Function sqlite3ExprListFlags CDecl Alias "sqlite3ExprListFlags" ( _
    ByVal pList As Const SqliteExprList Ptr _
) As u32 Export
    If pList = 0 OrElse pList->nExpr < 0 OrElse _
       pList->nAlloc < pList->nExpr Then Return 0
    Dim flags As u32 = 0
    For iExpr As SQLITE_C_INT = 0 To pList->nExpr - 1
        Dim pExpr As Const SqliteExpr Ptr = _
            CPtr(Const SqliteExpr Ptr, pList->a(iExpr).pExpr)
        If pExpr = 0 Then Return 0
        flags Or= pExpr->flags
    Next
    Return flags
End Function

#if SQLITE_MAX_EXPR_DEPTH > 0
Private Sub heightOfExpr CDecl Alias "heightOfExpr" ( _
    ByVal pExpr As Const SqliteExpr Ptr, _
    ByVal pHeight As SQLITE_C_INT Ptr _
)
    If pExpr = 0 OrElse pHeight = 0 Then Exit Sub
    If pExpr->nHeight > pHeight[0] Then pHeight[0] = pExpr->nHeight
End Sub

Private Sub heightOfExprList CDecl Alias "heightOfExprList" ( _
    ByVal pList As Const SqliteExprList Ptr, _
    ByVal pHeight As SQLITE_C_INT Ptr _
)
    If pList = 0 OrElse pHeight = 0 OrElse pList->nExpr < 0 OrElse _
       pList->nAlloc < pList->nExpr Then Exit Sub
    For iExpr As SQLITE_C_INT = 0 To pList->nExpr - 1
        heightOfExpr(CPtr(Const SqliteExpr Ptr, pList->a(iExpr).pExpr), pHeight)
    Next
End Sub

Private Sub heightOfSelect CDecl Alias "heightOfSelect" ( _
    ByVal pSelectArgument As Const SqliteSelect Ptr, _
    ByVal pHeight As SQLITE_C_INT Ptr _
)
    Dim pSelect As Const SqliteSelect Ptr = pSelectArgument
    While pSelect <> 0
        heightOfExpr(CPtr(Const SqliteExpr Ptr, pSelect->pWhere), pHeight)
        heightOfExpr(CPtr(Const SqliteExpr Ptr, pSelect->pHaving), pHeight)
        heightOfExpr(CPtr(Const SqliteExpr Ptr, pSelect->pLimit), pHeight)
        heightOfExprList(CPtr(Const SqliteExprList Ptr, pSelect->pEList), pHeight)
        heightOfExprList(CPtr(Const SqliteExprList Ptr, pSelect->pGroupBy), pHeight)
        heightOfExprList(CPtr(Const SqliteExprList Ptr, pSelect->pOrderBy), pHeight)
        pSelect = CPtr(Const SqliteSelect Ptr, pSelect->pPrior)
    Wend
End Sub

Private Sub exprSetHeight CDecl Alias "exprSetHeight" ( _
    ByVal pExpr As SqliteExpr Ptr _
)
    If pExpr = 0 Then Exit Sub
    Dim nHeight As SQLITE_C_INT = 0
    heightOfExpr(CPtr(Const SqliteExpr Ptr, pExpr->pLeft), @nHeight)
    heightOfExpr(CPtr(Const SqliteExpr Ptr, pExpr->pRight), @nHeight)
    If (pExpr->flags And EP_xIsSelect) <> 0 Then
        heightOfSelect(CPtr(Const SqliteSelect Ptr, pExpr->x.pSelect), @nHeight)
    ElseIf pExpr->x.pList <> 0 Then
        Dim pList As Const SqliteExprList Ptr = _
            CPtr(Const SqliteExprList Ptr, pExpr->x.pList)
        heightOfExprList(pList, @nHeight)
        pExpr->flags Or= EP_Propagate And sqlite3ExprListFlags(pList)
    End If
    pExpr->nHeight = nHeight + 1
End Sub
#endif

Function sqlite3ExprCheckHeight CDecl Alias "sqlite3ExprCheckHeight" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal height As SQLITE_C_INT _
) As SQLITE_C_INT Export
#if SQLITE_MAX_EXPR_DEPTH > 0
    If pParse = 0 OrElse pParse->db = 0 Then Return SQLITE_OK
    Dim maximumHeight As SQLITE_C_INT = _
        pParse->db->aLimit(SQLITE_LIMIT_EXPR_DEPTH)
    If height > maximumHeight Then
        sqlite3ErrorMsg(pParse, _
            StrPtr("Expression tree is too large (maximum depth %d)"), maximumHeight)
        Return SQLITE_ERROR
    End If
#endif
    Return SQLITE_OK
End Function

Sub sqlite3ExprSetHeightAndFlags CDecl Alias "sqlite3ExprSetHeightAndFlags" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) Export
    If pExpr = 0 OrElse (pParse <> 0 AndAlso pParse->nErr <> 0) Then Return
    If (pExpr->flags And EP_xIsSelect) = 0 AndAlso pExpr->x.pList <> 0 Then
        pExpr->flags Or= EP_Propagate And _
            sqlite3ExprListFlags(CPtr(Const SqliteExprList Ptr, pExpr->x.pList))
    End If
#if SQLITE_MAX_EXPR_DEPTH > 0
    exprSetHeight(pExpr)
    sqlite3ExprCheckHeight(pParse, pExpr->nHeight)
#endif
End Sub

Function sqlite3SelectExprHeight CDecl Alias "sqlite3SelectExprHeight" ( _
    ByVal pSelect As Const SqliteSelect Ptr _
) As SQLITE_C_INT Export
#if SQLITE_MAX_EXPR_DEPTH > 0
    Dim height As SQLITE_C_INT = 0
    heightOfSelect(pSelect, @height)
    Return height
#else
    Return 0
#endif
End Function

Function sqlite3SelectNew CDecl Alias "sqlite3SelectNew" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pEList As SqliteExprList Ptr, _
    ByVal pSrc As Any Ptr, _
    ByVal pWhere As SqliteExpr Ptr, _
    ByVal pGroupBy As SqliteExprList Ptr, _
    ByVal pHaving As SqliteExpr Ptr, _
    ByVal pOrderBy As SqliteExprList Ptr, _
    ByVal flags As u32, _
    ByVal pLimit As SqliteExpr Ptr _
) As SqliteSelect Ptr Export
    If pParse = 0 OrElse pParse->db = 0 Then Return 0
    Dim db As sqlite3 Ptr = pParse->db
    Dim pAllocated As SqliteSelect Ptr = CPtr(SqliteSelect Ptr, _
        sqlite3DbMallocRawNN(db, SizeOf(SqliteSelect)))
    Dim standin As SqliteSelect
    Dim pSelect As SqliteSelect Ptr = pAllocated
    If pSelect = 0 Then
        Dim pStandinByte As UByte Ptr = CPtr(UByte Ptr, @standin)
        For byteIndex As ULongInt = 0 To SizeOf(SqliteSelect) - 1
            pStandinByte[byteIndex] = 0
        Next
        pSelect = @standin
    End If

    If pEList = 0 Then
        Dim pStar As SqliteExpr Ptr = sqlite3ExprAlloc(db, TK_ASTERISK, 0, 0)
        pEList = sqlite3ExprListAppend(pParse, 0, pStar)
    End If
    If pSrc = 0 Then
        ' SQLite's SZ_SRCLIST_1 includes space for one trailing SrcItem.
        ' VALUES coroutines populate that first item after SelectNew returns.
        pSrc = sqlite3DbMallocZero( _
            db, SizeOf(SqliteSrcListHeader) + SizeOf(SqliteSrcItem))
    End If

    pSelect->op = TK_SELECT
    pSelect->nSelectRow = 0
    pSelect->selFlags = flags
    pSelect->iLimit = 0
    pSelect->iOffset = 0
    pParse->nSelect += 1
    pSelect->selId = CUInt(pParse->nSelect)
    pSelect->pEList = pEList
    pSelect->pSrc = CPtr(SqliteSrcList Ptr, pSrc)
    pSelect->pWhere = pWhere
    pSelect->pGroupBy = pGroupBy
    pSelect->pHaving = pHaving
    pSelect->pOrderBy = pOrderBy
    pSelect->pPrior = 0
    pSelect->pNext = 0
    pSelect->pLimit = pLimit
    pSelect->pWith = 0
#ifndef SQLITE_OMIT_WINDOWFUNC
    pSelect->pWin = 0
    pSelect->pWinDefn = 0
#endif

    If db->mallocFailed <> 0 Then
        sqlite3ExprListDelete(db, pEList)
        ' pSrc owns its table and schema names; freeing only the outer list
        ' leaves both names allocated after an OOM during schema parsing.
        sqlite3SrcListDelete(db, CPtr(SqliteSrcList Ptr, pSrc))
        sqlite3ExprDelete(db, pWhere)
        sqlite3ExprListDelete(db, pGroupBy)
        sqlite3ExprDelete(db, pHaving)
        sqlite3ExprListDelete(db, pOrderBy)
        sqlite3ExprDelete(db, pLimit)
        If pAllocated <> 0 Then sqlite3DbNNFreeNN(db, pAllocated)
        Return 0
    End If
    Return pAllocated
End Function

Declare Sub sqlite3SelectDeleteGeneric CDecl Alias "sqlite3SelectDeleteGeneric" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pSelect As Any Ptr _
)

Sub sqlite3SelectDelete CDecl Alias "sqlite3SelectDelete" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) Export
    If db = 0 OrElse pSelect = 0 Then Return
    sqlite3SelectDeleteGeneric(db, pSelect)
End Sub

/' ------------------------------------------------------------------------- '/
/' Temporary register bookkeeping                                          '/
/' ------------------------------------------------------------------------- '/

Sub sqlite3ClearTempRegCache CDecl Alias "sqlite3ClearTempRegCache" ( _
    ByVal pParse As SqliteParseContext Ptr _
) Export
    If pParse = 0 Then Return
    pParse->nTempReg = 0
    pParse->nRangeReg = 0
End Sub

Function sqlite3GetTempReg CDecl Alias "sqlite3GetTempReg" ( _
    ByVal pParse As SqliteParseContext Ptr _
) As SQLITE_C_INT Export
    If pParse = 0 Then Return 0
    If pParse->nTempReg > 0 Then
        pParse->nTempReg -= 1
        Return pParse->aTempReg(pParse->nTempReg)
    End If
    If pParse->nMem < 0 OrElse pParse->nMem >= SQLITE_MAX_VDBE_OP - 1 Then Return 0
    pParse->nMem += 1
    Return pParse->nMem
End Function

Sub sqlite3ReleaseTempReg CDecl Alias "sqlite3ReleaseTempReg" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal registerNumber As SQLITE_C_INT _
) Export
    If pParse = 0 OrElse registerNumber = 0 Then Return
#ifdef SQLITE_DEBUG
    sqlite3VdbeReleaseRegisters(pParse, registerNumber, 1, 0, 0)
#endif
    If pParse->nTempReg < SQLITE_TEMP_REGISTER_CACHE_SIZE Then
        pParse->aTempReg(pParse->nTempReg) = registerNumber
        pParse->nTempReg += 1
    End If
End Sub

Function sqlite3GetTempRange CDecl Alias "sqlite3GetTempRange" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal registerCount As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pParse = 0 OrElse registerCount <= 0 Then Return 0
    If registerCount = 1 Then Return sqlite3GetTempReg(pParse)

    If registerCount <= pParse->nRangeReg Then
        Dim firstRegister As SQLITE_C_INT = pParse->iRangeReg
        pParse->iRangeReg += registerCount
        pParse->nRangeReg -= registerCount
        Return firstRegister
    End If

    If pParse->nMem < 0 OrElse _
       registerCount > SQLITE_MAX_VDBE_OP - pParse->nMem Then Return 0
    Dim firstRegister As SQLITE_C_INT = pParse->nMem + 1
    pParse->nMem += registerCount
    Return firstRegister
End Function

Sub sqlite3ReleaseTempRange CDecl Alias "sqlite3ReleaseTempRange" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal firstRegister As SQLITE_C_INT, _
    ByVal registerCount As SQLITE_C_INT _
) Export
    If pParse = 0 OrElse firstRegister <= 0 OrElse registerCount <= 0 Then Return
    If registerCount = 1 Then
        sqlite3ReleaseTempReg(pParse, firstRegister)
        Return
    End If
#ifdef SQLITE_DEBUG
    sqlite3VdbeReleaseRegisters(pParse, firstRegister, registerCount, 0, 0)
#endif
    If registerCount > pParse->nRangeReg Then
        pParse->nRangeReg = registerCount
        pParse->iRangeReg = firstRegister
    End If
End Sub

Sub sqlite3TouchRegister CDecl Alias "sqlite3TouchRegister" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal registerIndex As SQLITE_C_INT _
) Export
    If pParse = 0 OrElse registerIndex < 0 Then Return
    If pParse->nMem < registerIndex Then pParse->nMem = registerIndex
End Sub

Private Function exprCodeSubselect CDecl Alias "exprCodeSubselect" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT
    If pParse = 0 OrElse pExpr = 0 Then Return 0
    If pExpr->op = TK_SELECT Then Return sqlite3CodeSubselect(pParse, pExpr)
    Return 0
End Function

Private Sub sqlite3SetHasNullFlag CDecl Alias "sqlite3SetHasNullFlag" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal cursorNumber As SQLITE_C_INT, _
    ByVal registerNumber As SQLITE_C_INT, _
    ByVal sortOrder As SQLITE_C_INT _
)
    If pVdbe = 0 Then Exit Sub

    sqlite3VdbeAddOp2(pVdbe, OP_Integer, 0, registerNumber)
    Dim seekOpcode As SQLITE_C_INT = OP_Last
    If sortOrder = SQLITE_SO_ASC Then seekOpcode = OP_Rewind
    Dim address As SQLITE_C_INT = sqlite3VdbeAddOp1(pVdbe, seekOpcode, cursorNumber)
    ' Column zero determines whether the single-column index contains NULL.
    sqlite3VdbeAddOp3(pVdbe, OP_Column, cursorNumber, 0, registerNumber)
    sqlite3VdbeChangeP5(pVdbe, OPFLAG_TYPEOFARG)
    sqlite3VdbeJumpHere(pVdbe, address)
End Sub

Private Sub setDoNotMergeFlagOnCopy CDecl Alias "setDoNotMergeFlagOnCopy" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
    If pVdbe = 0 Then Exit Sub
    Dim pLastOp As SqliteVdbeOp Ptr = sqlite3VdbeGetLastOp(pVdbe)
    If pLastOp <> 0 AndAlso pLastOp->opcode = OP_Copy Then
        sqlite3VdbeChangeP5(pVdbe, 1)
    End If
End Sub

Sub sqlite3ExprCodeCopy CDecl Alias "sqlite3ExprCodeCopy" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExprArgument As SqliteExpr Ptr, _
    ByVal targetRegister As SQLITE_C_INT _
)
    If pParse = 0 OrElse pParse->db = 0 Then Exit Sub
    Dim db As sqlite3 Ptr = pParse->db
    Dim pExpr As SqliteExpr Ptr = sqlite3ExprDup(db, pExprArgument, 0)
    If db->mallocFailed = 0 Then sqlite3ExprCode(pParse, pExpr, targetRegister)
    sqlite3ExprDelete(db, pExpr)
End Sub

Private Function exprTokenTextEqual( _
    ByVal pLeft As Const UByte Ptr, _
    ByVal pRight As Const UByte Ptr _
) As SQLITE_C_INT
    If pLeft = 0 OrElse pRight = 0 Then Return 0
    For iByte As SQLITE_C_INT = 0 To SQLITE_MAX_LENGTH
        If pLeft[iByte] <> pRight[iByte] Then Return 0
        If pLeft[iByte] = 0 Then Return 1
    Next
    Return 0
End Function

Function sqlite3ExprSkipCollate CDecl Alias "sqlite3ExprSkipCollate" ( _
    ByVal pExprArgument As SqliteExpr Ptr _
) As SqliteExpr Ptr Export
    Dim pExpr As SqliteExpr Ptr = pExprArgument
    While pExpr <> 0 AndAlso (pExpr->flags And EP_Skip) <> 0
        If pExpr->op <> TK_COLLATE Then Exit While
        pExpr = CPtr(SqliteExpr Ptr, pExpr->pLeft)
    Wend
    Return pExpr
End Function

Function sqlite3ExprAddCollateToken CDecl Alias "sqlite3ExprAddCollateToken" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal pCollationName As Const sqlite3ParserToken Ptr, _
    ByVal dequote As SQLITE_C_INT _
) As SqliteExpr Ptr Export
    If pParse = 0 OrElse pParse->db = 0 OrElse pExpr = 0 OrElse _
       pCollationName = 0 Then Return pExpr
    If pCollationName->n = 0 OrElse pParse->nErr <> 0 Then Return pExpr

    Dim pNew As SqliteExpr Ptr = sqlite3ExprAlloc( _
        pParse->db, TK_COLLATE, CPtr(sqlite3ParserToken Ptr, pCollationName), dequote)
    If pNew = 0 Then Return pExpr
    pNew->pLeft = pExpr
    pNew->flags = (pNew->flags And Not EP_Leaf) Or EP_Collate Or EP_Skip
#if SQLITE_MAX_EXPR_DEPTH > 0
    sqlite3ExprSetHeightAndFlags(pParse, pNew)
#endif
    Return pNew
End Function

Function sqlite3ExprAddCollateString CDecl Alias "sqlite3ExprAddCollateString" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal zCollationName As Const ZString Ptr _
) As SqliteExpr Ptr Export
    If pParse = 0 OrElse pParse->db = 0 OrElse pExpr = 0 OrElse _
       zCollationName = 0 Then Return pExpr
    Dim token As sqlite3ParserToken
    token.z = CPtr(UByte Ptr, zCollationName)
    Dim tokenLength As SQLITE_C_INT = sqlite3Strlen30(zCollationName)
    If tokenLength < 0 Then Return pExpr
    token.n = CUInt(tokenLength)
    Return sqlite3ExprAddCollateToken(pParse, pExpr, @token, 0)
End Function

Function sqlite3ExprCollSeq CDecl Alias "sqlite3ExprCollSeq" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExprArgument As Const SqliteExpr Ptr _
) As sqlite3CollSeq Ptr Export
    If pParse = 0 OrElse pParse->db = 0 Then Return 0
    Dim db As sqlite3 Ptr = pParse->db
    Dim pExpr As Const SqliteExpr Ptr = pExprArgument
    Dim pCollation As sqlite3CollSeq Ptr = 0

    While pExpr <> 0
        Dim opcode As SQLITE_C_INT = pExpr->op
        If opcode = TK_REGISTER Then opcode = pExpr->op2

        If opcode = TK_COLUMN OrElse opcode = TK_TRIGGER OrElse _
           (opcode = TK_AGG_COLUMN AndAlso pExpr->y.pTab <> 0) Then
            Dim pTable As SqliteTable Ptr = _
                CPtr(SqliteTable Ptr, pExpr->y.pTab)
            Dim columnIndex As SQLITE_C_INT = pExpr->iColumn
            If pTable <> 0 AndAlso pTable->aCol <> 0 AndAlso _
               columnIndex >= 0 AndAlso columnIndex < pTable->nCol Then
                Dim zColumnCollation As Const ZString Ptr = _
                    sqlite3ColumnColl(@pTable->aCol[columnIndex])
                ' A column without an explicit COLLATE uses the database default.
                pCollation = sqlite3FindCollSeq( _
                    db, db->enc, zColumnCollation, 0)
            End If
            Exit While
        End If

        If opcode = TK_CAST OrElse opcode = TK_UPLUS Then
            pExpr = CPtr(Const SqliteExpr Ptr, pExpr->pLeft)
            Continue While
        End If
        If opcode = TK_VECTOR OrElse _
           (opcode = TK_FUNCTION AndAlso pExpr->affExpr = SQLITE_AFF_DEFER) Then
            If pExpr->x.pList = 0 Then Exit While
            Dim pList As SqliteExprList Ptr = _
                CPtr(SqliteExprList Ptr, pExpr->x.pList)
            Dim pFirst As SqliteExprListItem Ptr = sqlite3ExprListItemAt(pList, 0)
            If pFirst = 0 Then Exit While
            pExpr = CPtr(Const SqliteExpr Ptr, pFirst->pExpr)
            Continue While
        End If
        If opcode = TK_COLLATE Then
            If pExpr->u.zToken <> 0 Then
                pCollation = sqlite3GetCollSeq(pParse, db->enc, 0, _
                    CPtr(Const ZString Ptr, pExpr->u.zToken))
            End If
            Exit While
        End If

        If (pExpr->flags And EP_Collate) = 0 Then Exit While
        Dim pLeft As Const SqliteExpr Ptr = _
            CPtr(Const SqliteExpr Ptr, pExpr->pLeft)
        If pLeft <> 0 AndAlso (pLeft->flags And EP_Collate) <> 0 Then
            pExpr = pLeft
            Continue While
        End If

        Dim pNext As Const SqliteExpr Ptr = _
            CPtr(Const SqliteExpr Ptr, pExpr->pRight)
        If (pExpr->flags And EP_xIsSelect) = 0 AndAlso pExpr->x.pList <> 0 AndAlso _
           db->mallocFailed = 0 Then
            Dim pList As SqliteExprList Ptr = _
                CPtr(SqliteExprList Ptr, pExpr->x.pList)
            If pList->nExpr > 0 AndAlso pList->nAlloc >= pList->nExpr Then
                For itemIndex As SQLITE_C_INT = 0 To pList->nExpr - 1
                    Dim pItem As SqliteExprListItem Ptr = _
                        sqlite3ExprListItemAt(pList, itemIndex)
                    If pItem <> 0 AndAlso pItem->pExpr <> 0 AndAlso _
                       (CPtr(SqliteExpr Ptr, pItem->pExpr)->flags And EP_Collate) <> 0 Then
                        pNext = CPtr(Const SqliteExpr Ptr, pItem->pExpr)
                        Exit For
                    End If
                Next
            End If
        End If
        pExpr = pNext
    Wend

    If sqlite3CheckCollSeq(pParse, pCollation) <> SQLITE_OK Then _
        pCollation = 0
    Return pCollation
End Function

Function sqlite3ExprNNCollSeq CDecl Alias "sqlite3ExprNNCollSeq" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As Const SqliteExpr Ptr _
) As sqlite3CollSeq Ptr Export
    If pParse = 0 OrElse pParse->db = 0 Then Return 0
    Dim pCollation As sqlite3CollSeq Ptr = sqlite3ExprCollSeq(pParse, pExpr)
    If pCollation = 0 Then pCollation = pParse->db->pDfltColl
    Return pCollation
End Function

Function sqlite3ExprCollSeqMatch CDecl Alias "sqlite3ExprCollSeqMatch" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pLeft As Const SqliteExpr Ptr, _
    ByVal pRight As Const SqliteExpr Ptr _
) As SQLITE_C_INT Export
    Dim pLeftCollation As sqlite3CollSeq Ptr = _
        sqlite3ExprNNCollSeq(pParse, pLeft)
    Dim pRightCollation As sqlite3CollSeq Ptr = _
        sqlite3ExprNNCollSeq(pParse, pRight)
    If pLeftCollation = 0 OrElse pRightCollation = 0 Then Return 0
    Return CInt(pLeftCollation = pRightCollation)
End Function

Function sqlite3BinaryCompareCollSeq CDecl Alias "sqlite3BinaryCompareCollSeq" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pLeft As Const SqliteExpr Ptr, _
    ByVal pRight As Const SqliteExpr Ptr _
) As sqlite3CollSeq Ptr Export
    If pParse = 0 OrElse pLeft = 0 Then Return 0
    If (pLeft->flags And EP_Collate) <> 0 Then _
        Return sqlite3ExprCollSeq(pParse, pLeft)
    If pRight <> 0 AndAlso (pRight->flags And EP_Collate) <> 0 Then _
        Return sqlite3ExprCollSeq(pParse, pRight)

    Dim pCollation As sqlite3CollSeq Ptr = sqlite3ExprCollSeq(pParse, pLeft)
    If pCollation = 0 AndAlso pRight <> 0 Then _
        pCollation = sqlite3ExprCollSeq(pParse, pRight)
    Return pCollation
End Function

Function sqlite3ExprCompareCollSeq CDecl Alias "sqlite3ExprCompareCollSeq" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As Const SqliteExpr Ptr _
) As sqlite3CollSeq Ptr Export
    If pExpr = 0 Then Return 0
    If (pExpr->flags And EP_Commuted) <> 0 Then
        Return sqlite3BinaryCompareCollSeq(pParse, _
            CPtr(Const SqliteExpr Ptr, pExpr->pRight), _
            CPtr(Const SqliteExpr Ptr, pExpr->pLeft))
    End If
    Return sqlite3BinaryCompareCollSeq(pParse, _
        CPtr(Const SqliteExpr Ptr, pExpr->pLeft), _
        CPtr(Const SqliteExpr Ptr, pExpr->pRight))
End Function

Private Function exprCompareVariable( _
    ByVal pParse As Const SqliteParseContext Ptr, _
    ByVal pVariable As Const SqliteExpr Ptr, _
    ByVal pExpression As Const SqliteExpr Ptr _
) As SQLITE_C_INT

    ' Partial-index implication may compare a bound parameter with a literal.
    ' Track that binding so a later value change can reprepare the statement.

    If pParse = 0 OrElse pParse->db = 0 OrElse _
       pVariable = 0 OrElse pExpression = 0 Then Return 2

    If pExpression->op = TK_VARIABLE AndAlso _
       pVariable->iColumn = pExpression->iColumn Then Return 0
    If (pParse->db->flags And SQLITE_EnableQPSG) <> 0 Then Return 2

    Dim pExpressionValue As SqliteVdbeMem Ptr = 0
    sqlite3ValueFromExpr( _
        pParse->db, pExpression, SQLITE_UTF8, SQLITE_AFF_BLOB, _
        @pExpressionValue)

    Dim resultCode As SQLITE_C_INT = 2
    If pExpressionValue <> 0 Then
        Dim variableNumber As SQLITE_C_INT = pVariable->iColumn
        If pParse->pVdbe <> 0 Then
            sqlite3VdbeReprepareOnBind( _
                CPtr(SqliteVdbe Ptr, pParse->pVdbe), variableNumber, 0)
        End If

        Dim pBoundValue As SqliteVdbeMem Ptr = 0
        If pParse->pReprepare <> 0 Then
            pBoundValue = sqlite3VdbeGetBoundValue( _
                CPtr(SqliteVdbe Ptr, pParse->pReprepare), _
                variableNumber, SQLITE_AFF_BLOB)
        End If
        If pBoundValue <> 0 Then
            If sqlite3_value_type(pBoundValue) = SQLITE_TEXT Then
                Dim pBoundText As Const UByte Ptr = _
                    sqlite3_value_text(pBoundValue)
            End If
            If sqlite3MemCompare(pBoundValue, pExpressionValue, 0) = 0 Then
                resultCode = 0
            End If
            sqlite3ValueFree(pBoundValue)
        End If
        sqlite3ValueFree(pExpressionValue)
    End If
    Return resultCode
End Function

Function sqlite3ExprCompare CDecl Alias "sqlite3ExprCompare" ( _
    ByVal pParse As Any Ptr, _
    ByVal pLeft As Const SqliteExpr Ptr, _
    ByVal pRight As Const SqliteExpr Ptr, _
    ByVal tableCursor As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pLeft = 0 OrElse pRight = 0 Then Return IIf(pLeft = pRight, 0, 2)
    If pParse <> 0 AndAlso pLeft->op = TK_VARIABLE Then _
        Return exprCompareVariable(pParse, pLeft, pRight)

    Dim pA As Const SqliteExpr Ptr = pLeft
    Dim pB As Const SqliteExpr Ptr = pRight
    Dim combinedFlags As u32 = pA->flags Or pB->flags
    If (combinedFlags And EP_IntValue) <> 0 Then
        If (pA->flags And pB->flags And EP_IntValue) <> 0 AndAlso _
           pA->u.iValue = pB->u.iValue Then Return 0
        Return 2
    End If

    If pA->op <> pB->op OrElse pA->op = TK_RAISE Then
        If pA->op = TK_COLLATE AndAlso _
           sqlite3ExprCompare(pParse, CPtr(Const SqliteExpr Ptr, pA->pLeft), _
                               pB, tableCursor) < 2 Then Return 1
        If pB->op = TK_COLLATE AndAlso _
           sqlite3ExprCompare(pParse, pA, _
                               CPtr(Const SqliteExpr Ptr, pB->pLeft), _
                               tableCursor) < 2 Then Return 1
        If pA->op <> TK_AGG_COLUMN OrElse pB->op <> TK_COLUMN OrElse _
           pB->iTable >= 0 OrElse pA->iTable <> tableCursor Then Return 2
    End If

    If pA->op = TK_FUNCTION OrElse pA->op = TK_AGG_FUNCTION Then
        If pA->u.zToken = 0 OrElse pB->u.zToken = 0 OrElse _
           sqlite3_stricmp(CPtr(Const ZString Ptr, pA->u.zToken), _
                           CPtr(Const ZString Ptr, pB->u.zToken)) <> 0 Then Return 2
        If ((pA->flags Xor pB->flags) And EP_WinFunc) <> 0 Then Return 2
        If (pA->flags And EP_WinFunc) <> 0 Then Return 2
    ElseIf pA->op = TK_COLLATE Then
        If pA->u.zToken = 0 OrElse pB->u.zToken = 0 OrElse _
           sqlite3_stricmp(CPtr(Const ZString Ptr, pA->u.zToken), _
                           CPtr(Const ZString Ptr, pB->u.zToken)) <> 0 Then Return 2
    ElseIf pA->op <> TK_COLUMN AndAlso pA->op <> TK_AGG_COLUMN Then
        If pA->u.zToken <> 0 OrElse pB->u.zToken <> 0 Then
            If exprTokenTextEqual(pA->u.zToken, pB->u.zToken) = 0 Then Return 2
        End If
    End If

    If ((pA->flags Xor pB->flags) And (EP_Distinct Or EP_Commuted)) <> 0 Then Return 2
    If (combinedFlags And EP_TokenOnly) = 0 Then
        If (combinedFlags And EP_xIsSelect) <> 0 Then Return 2
        If (combinedFlags And EP_FixedCol) = 0 Then
            If sqlite3ExprCompare(pParse, _
                CPtr(Const SqliteExpr Ptr, pA->pLeft), _
                CPtr(Const SqliteExpr Ptr, pB->pLeft), tableCursor) <> 0 Then Return 2
        End If
        If sqlite3ExprCompare(pParse, _
            CPtr(Const SqliteExpr Ptr, pA->pRight), _
            CPtr(Const SqliteExpr Ptr, pB->pRight), tableCursor) <> 0 Then Return 2
        If sqlite3ExprListCompare( _
            CPtr(Const SqliteExprList Ptr, pA->x.pList), _
            CPtr(Const SqliteExprList Ptr, pB->x.pList), tableCursor) <> 0 Then Return 2
        If pA->op <> TK_STRING AndAlso pA->op <> TK_TRUEFALSE AndAlso _
           (combinedFlags And EP_Reduced) = 0 Then
            If pA->iColumn <> pB->iColumn Then Return 2
            If pA->op = TK_TRUTH AndAlso pA->op2 <> pB->op2 Then Return 2
            If pA->op <> TK_IN AndAlso pA->iTable <> pB->iTable AndAlso _
               pA->iTable <> tableCursor Then Return 2
        End If
    End If
    Return 0
End Function

Function sqlite3ExprListCompare CDecl Alias "sqlite3ExprListCompare" ( _
    ByVal pLeft As Const SqliteExprList Ptr, _
    ByVal pRight As Const SqliteExprList Ptr, _
    ByVal tableCursor As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pLeft = 0 AndAlso pRight = 0 Then Return 0
    If pLeft = 0 OrElse pRight = 0 Then Return 1
    If pLeft->nExpr <> pRight->nExpr OrElse pLeft->nExpr < 0 OrElse _
       pLeft->nAlloc < pLeft->nExpr OrElse pRight->nAlloc < pRight->nExpr Then Return 1
    For itemIndex As SQLITE_C_INT = 0 To pLeft->nExpr - 1
        If pLeft->a(itemIndex).fg.sortFlags <> _
           pRight->a(itemIndex).fg.sortFlags Then Return 1
        Dim pExprLeft As Const SqliteExpr Ptr = _
            CPtr(Const SqliteExpr Ptr, pLeft->a(itemIndex).pExpr)
        Dim pExprRight As Const SqliteExpr Ptr = _
            CPtr(Const SqliteExpr Ptr, pRight->a(itemIndex).pExpr)
        Dim resultCode As SQLITE_C_INT = _
            sqlite3ExprCompare(0, pExprLeft, pExprRight, tableCursor)
        If resultCode <> 0 Then Return resultCode
    Next
    Return 0
End Function

Function sqlite3ExprCompareSkip CDecl Alias "sqlite3ExprCompareSkip" ( _
    ByVal pLeft As SqliteExpr Ptr, _
    ByVal pRight As SqliteExpr Ptr, _
    ByVal tableCursor As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Return sqlite3ExprCompare(0, sqlite3ExprSkipCollate(pLeft), _
                              sqlite3ExprSkipCollate(pRight), tableCursor)
End Function

Private Function exprNodeIsConstantFunction( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT
    If pWalker = 0 OrElse pExpr = 0 OrElse pWalker->pParse = 0 Then
        If pWalker <> 0 Then pWalker->eCode = 0
        Return WRC_ABORT
    End If

    Dim argumentCount As SQLITE_C_INT = 0
    If (pExpr->flags And EP_TokenOnly) = 0 AndAlso pExpr->x.pList <> 0 Then
        Dim pList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pExpr->x.pList)
        If pList->nExpr < 0 OrElse pList->nAlloc < pList->nExpr Then
            pWalker->eCode = 0
            Return WRC_ABORT
        End If
        argumentCount = pList->nExpr
        If sqlite3WalkExprList(pWalker, pList) <> WRC_CONTINUE OrElse _
           pWalker->eCode = 0 Then Return WRC_ABORT
    End If

    If pExpr->u.zToken = 0 Then
        pWalker->eCode = 0
        Return WRC_ABORT
    End If
    Dim pFunction As SqliteFuncDef Ptr = sqlite3FindFunction( _
        pWalker->pParse->db, CPtr(Const ZString Ptr, pExpr->u.zToken), _
        argumentCount, pWalker->pParse->db->enc, 0)
    If pFunction = 0 OrElse pFunction->xFinalize <> 0 OrElse _
       (pFunction->funcFlags And _
        (SQLITE_FUNC_CONSTANT Or SQLITE_FUNC_SLOCHNG)) = 0 OrElse _
       (pExpr->flags And EP_WinFunc) <> 0 Then
        pWalker->eCode = 0
    End If

    ' This helper has already checked the arguments. Prune the normal walker
    ' descent either way; eCode records whether the function was constant.
    Return WRC_ABORT
End Function

Private Function exprNodeIsConstant CDecl Alias "exprNodeIsConstant" ( _
    ByVal pWalkerArgument As Any Ptr, _
    ByVal pExprArgument As Any Ptr _
) As SQLITE_C_INT
    If pWalkerArgument = 0 OrElse pExprArgument = 0 Then Return WRC_ABORT
    Dim pWalker As SqliteWalker Ptr = CPtr(SqliteWalker Ptr, pWalkerArgument)
    Dim pExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pExprArgument)

    If pWalker->eCode <= 0 Then Return WRC_ABORT
    If pWalker->eCode = 2 AndAlso (pExpr->flags And EP_OuterON) <> 0 Then
        pWalker->eCode = 0
        Return WRC_ABORT
    End If

    Select Case pExpr->op
    Case TK_FUNCTION
        If (pExpr->flags And EP_WinFunc) <> 0 Then
            pWalker->eCode = 0
            Return WRC_ABORT
        ElseIf pWalker->eCode >= 4 AndAlso pWalker->eCode <= 5 Then
            If pWalker->eCode = 5 Then pExpr->flags Or= EP_FromDDL
            Return WRC_CONTINUE
        ElseIf (pExpr->flags And EP_ConstFunc) <> 0 Then
            Return WRC_CONTINUE
        ElseIf pWalker->pParse <> 0 Then
            Return exprNodeIsConstantFunction(pWalker, pExpr)
        Else
            pWalker->eCode = 0
            Return WRC_ABORT
        End If

    Case TK_ID
        If sqlite3ExprIdToTrueFalse(pExpr) <> 0 Then Return WRC_PRUNE
        ' TK_ID falls through to the column-like cases.
        If (pExpr->flags And EP_FixedCol) <> 0 AndAlso pWalker->eCode <> 2 Then _
            Return WRC_CONTINUE
        If pWalker->eCode = 3 AndAlso pExpr->iTable = pWalker->u.n Then _
            Return WRC_CONTINUE
        pWalker->eCode = 0
        Return WRC_ABORT

    Case TK_COLUMN, TK_AGG_FUNCTION, TK_AGG_COLUMN
        If (pExpr->flags And EP_FixedCol) <> 0 AndAlso pWalker->eCode <> 2 Then _
            Return WRC_CONTINUE
        If pWalker->eCode = 3 AndAlso pExpr->iTable = pWalker->u.n Then _
            Return WRC_CONTINUE
        pWalker->eCode = 0
        Return WRC_ABORT

    Case TK_IF_NULL_ROW, TK_REGISTER, TK_DOT, TK_RAISE
        pWalker->eCode = 0
        Return WRC_ABORT

    Case TK_IS, TK_ISNOT
        If pWalker->eCode = 6 Then
            pWalker->eCode = 0
            Return WRC_ABORT
        End If
        Return WRC_CONTINUE

    Case TK_VARIABLE
        If pWalker->eCode = 5 Then
            ' Legacy schema text may contain a parameter; read it as NULL.
            pExpr->op = TK_NULL
        ElseIf pWalker->eCode = 4 Then
            pWalker->eCode = 0
            Return WRC_ABORT
        End If
        Return WRC_CONTINUE
    End Select
    Return WRC_CONTINUE
End Function

Private Function exprIsConst( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal initialCode As SQLITE_C_INT _
) As SQLITE_C_INT
    If initialCode <= 0 OrElse initialCode > &HFFFF Then Return 0
    Dim walker As SqliteWalker
    walker.pParse = pParse
    walker.xExprCallback = CPtr(SqliteWalkerExprCallback, @exprNodeIsConstant)
    walker.xSelectCallback = CPtr(SqliteWalkerSelectCallback, @sqlite3SelectWalkFail)
    walker.xSelectCallback2 = 0
    walker.walkerDepth = 0
    walker.eCode = CUShort(initialCode)
    walker.mWFlags = 0
    walker.u.n = 0
    sqlite3WalkExpr(@walker, pExpr)
    Return walker.eCode
End Function

Function sqlite3ExprIsConstant CDecl Alias "sqlite3ExprIsConstant" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT Export
    Return exprIsConst(pParse, pExpr, 1)
End Function

Private Function sqlite3ExprIsConstantNotJoin CDecl Alias "sqlite3ExprIsConstantNotJoin" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT
    Return exprIsConst(pParse, pExpr, 2)
End Function

Function sqlite3ExprListIsConstant CDecl Alias "sqlite3ExprListIsConstant" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pList As SqliteExprList Ptr, _
    ByVal noIsOperators As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pList = 0 Then Return 1
    If pList->nExpr < 0 OrElse pList->nAlloc < pList->nExpr Then Return 0
    Dim initialCode As SQLITE_C_INT = IIf(noIsOperators <> 0, 6, 1)
    For itemIndex As SQLITE_C_INT = 0 To pList->nExpr - 1
        Dim pExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pList->a(itemIndex).pExpr)
        If exprIsConst(pParse, pExpr, initialCode) = 0 Then Return 0
    Next
    Return 1
End Function

Private Function exprSelectWalkTableConstant CDecl Alias "exprSelectWalkTableConstant" ( _
    ByVal pWalkerArgument As Any Ptr, _
    ByVal pSelectArgument As Any Ptr _
) As SQLITE_C_INT
    If pWalkerArgument = 0 OrElse pSelectArgument = 0 Then Return WRC_ABORT
    Dim pWalker As SqliteWalker Ptr = CPtr(SqliteWalker Ptr, pWalkerArgument)
    Dim pSelect As SqliteSelect Ptr = CPtr(SqliteSelect Ptr, pSelectArgument)
    If (pSelect->selFlags And SF_Correlated) <> 0 Then
        pWalker->eCode = 0
        Return WRC_ABORT
    End If
    Return WRC_PRUNE
End Function

Private Function sqlite3ExprIsTableConstant CDecl Alias "sqlite3ExprIsTableConstant" ( _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal cursorNumber As SQLITE_C_INT, _
    ByVal allowSubquery As SQLITE_C_INT _
) As SQLITE_C_INT
    Dim walker As SqliteWalker
    walker.pParse = 0
    walker.xExprCallback = CPtr(SqliteWalkerExprCallback, @exprNodeIsConstant)
    If allowSubquery <> 0 Then
        walker.xSelectCallback = CPtr(SqliteWalkerSelectCallback, @exprSelectWalkTableConstant)
    Else
        walker.xSelectCallback = CPtr(SqliteWalkerSelectCallback, @sqlite3SelectWalkFail)
    End If
    walker.xSelectCallback2 = 0
    walker.walkerDepth = 0
    walker.eCode = 3
    walker.mWFlags = 0
    walker.u.n = cursorNumber
    sqlite3WalkExpr(@walker, pExpr)
    Return walker.eCode
End Function

Function sqlite3ExprIsSingleTableConstraint CDecl Alias "sqlite3ExprIsSingleTableConstraint" ( _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal pSourceListArgument As Any Ptr, _
    ByVal sourceIndex As SQLITE_C_INT, _
    ByVal allowSubquery As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pExpr = 0 OrElse pSourceListArgument = 0 OrElse sourceIndex < 0 Then Return 0
    Dim pSourceList As SqliteSrcListHeader Ptr = _
        CPtr(SqliteSrcListHeader Ptr, pSourceListArgument)
    If pSourceList->nSrc <= 0 OrElse pSourceList->nAlloc < pSourceList->nSrc OrElse _
       sourceIndex >= pSourceList->nSrc Then Return 0

    Dim pFirstItem As SqliteSrcItem Ptr = CPtr(SqliteSrcItem Ptr, _
        CPtr(UByte Ptr, pSourceList) + SizeOf(SqliteSrcListHeader))
    Dim pSource As SqliteSrcItem Ptr = @pFirstItem[sourceIndex]
    If (pSource->fg.jointype And JT_LTORJ) <> 0 Then Return 0

    If (pSource->fg.jointype And JT_LEFT) <> 0 Then
        If (pExpr->flags And EP_OuterON) = 0 OrElse _
           pExpr->w.iJoin <> pSource->iCursor Then Return 0
    ElseIf (pExpr->flags And EP_OuterON) <> 0 Then
        Return 0
    End If

    If (pExpr->flags And (EP_OuterON Or EP_InnerON)) <> 0 AndAlso _
       (pFirstItem->fg.jointype And JT_LTORJ) <> 0 Then
        For priorIndex As SQLITE_C_INT = 0 To sourceIndex - 1
            Dim pPriorSource As SqliteSrcItem Ptr = @pFirstItem[priorIndex]
            If pExpr->w.iJoin = pPriorSource->iCursor Then
                If (pPriorSource->fg.jointype And JT_LTORJ) <> 0 Then Return 0
                Exit For
            End If
        Next
    End If

    Return sqlite3ExprIsTableConstant(pExpr, pSource->iCursor, allowSubquery)
End Function

Function sqlite3ExprIsConstantOrFunction CDecl Alias "sqlite3ExprIsConstantOrFunction" ( _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal isInit As u8 _
) As SQLITE_C_INT Export
    If isInit > 1 Then Return 0
    Return exprIsConst(0, pExpr, 4 + isInit)
End Function

Private Function exprHasKnownBinaryCollation( _
    ByVal pExpr As Const SqliteExpr Ptr _
) As SQLITE_C_INT
    If pExpr = 0 Then Return 1
    If (pExpr->flags And (EP_Collate Or EP_xIsSelect Or EP_WinFunc)) <> 0 OrElse _
       pExpr->op = TK_COLLATE OrElse pExpr->op = TK_COLUMN OrElse _
       pExpr->op = TK_AGG_COLUMN Then Return 0
    If (pExpr->flags And EP_TokenOnly) <> 0 Then Return 1
    If exprHasKnownBinaryCollation( _
        CPtr(Const SqliteExpr Ptr, pExpr->pLeft)) = 0 Then Return 0
    If exprHasKnownBinaryCollation( _
        CPtr(Const SqliteExpr Ptr, pExpr->pRight)) = 0 Then Return 0
    If (pExpr->flags And EP_xIsSelect) = 0 AndAlso pExpr->x.pList <> 0 Then
        Dim pList As Const SqliteExprList Ptr = _
            CPtr(Const SqliteExprList Ptr, pExpr->x.pList)
        If pList->nExpr < 0 OrElse pList->nAlloc < pList->nExpr Then Return 0
        For itemIndex As SQLITE_C_INT = 0 To pList->nExpr - 1
            If exprHasKnownBinaryCollation( _
                CPtr(Const SqliteExpr Ptr, pList->a(itemIndex).pExpr)) = 0 Then Return 0
        Next
    End If
    Return 1
End Function

Private Function exprNodeIsConstantOrGroupBy CDecl Alias "exprNodeIsConstantOrGroupBy" ( _
    ByVal pWalkerArgument As Any Ptr, _
    ByVal pExprArgument As Any Ptr _
) As SQLITE_C_INT
    If pWalkerArgument = 0 OrElse pExprArgument = 0 Then Return WRC_ABORT
    Dim pWalker As SqliteWalker Ptr = CPtr(SqliteWalker Ptr, pWalkerArgument)
    Dim pExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pExprArgument)
    Dim pGroupBy As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pWalker->u.p)

    If pGroupBy <> 0 Then
        If pGroupBy->nExpr < 0 OrElse pGroupBy->nAlloc < pGroupBy->nExpr Then
            pWalker->eCode = 0
            Return WRC_ABORT
        End If
        For itemIndex As SQLITE_C_INT = 0 To pGroupBy->nExpr - 1
            Dim pGroupExpr As Const SqliteExpr Ptr = _
                CPtr(Const SqliteExpr Ptr, pGroupBy->a(itemIndex).pExpr)
            If sqlite3ExprCompare(0, pExpr, pGroupExpr, -1) < 2 AndAlso _
               exprHasKnownBinaryCollation(pGroupExpr) <> 0 Then Return WRC_PRUNE
        Next
    End If

    If (pExpr->flags And EP_xIsSelect) <> 0 Then
        pWalker->eCode = 0
        Return WRC_ABORT
    End If
    Return exprNodeIsConstant(pWalker, pExpr)
End Function

Function sqlite3ExprIsConstantOrGroupBy CDecl Alias "sqlite3ExprIsConstantOrGroupBy" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal pGroupBy As SqliteExprList Ptr _
) As SQLITE_C_INT Export
    Dim walker As SqliteWalker
    walker.pParse = pParse
    walker.xExprCallback = CPtr(SqliteWalkerExprCallback, @exprNodeIsConstantOrGroupBy)
    walker.xSelectCallback = 0
    walker.xSelectCallback2 = 0
    walker.walkerDepth = 0
    walker.eCode = 1
    walker.mWFlags = 0
    walker.u.p = pGroupBy
    sqlite3WalkExpr(@walker, pExpr)
    Return walker.eCode
End Function

Function sqlite3SelectWalkFail CDecl Alias "sqlite3SelectWalkFail" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) As SQLITE_C_INT Export
    If pWalker = 0 Then Return WRC_ABORT
    pWalker->eCode = 0
    Return WRC_ABORT
End Function

#ifdef SQLITE_ENABLE_CURSOR_HINTS
Function sqlite3ExprContainsSubquery CDecl Alias "sqlite3ExprContainsSubquery" ( _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT Export
    Dim walker As SqliteWalker = Type<SqliteWalker>(0)
    walker.eCode = 1
    walker.xExprCallback = @sqlite3ExprWalkNoop
    walker.xSelectCallback = @sqlite3SelectWalkFail
#ifdef SQLITE_DEBUG
    walker.xSelectCallback2 = @sqlite3SelectWalkAssert2
#endif
    sqlite3WalkExpr(@walker, pExpr)
    Return CInt(walker.eCode = 0)
End Function
#endif

/' ------------------------------------------------------------------------- '/
/' Expression index coverage                                                  '/
/' ------------------------------------------------------------------------- '/

Private Function exprIdxCover CDecl Alias "exprIdxCover" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT
    If pWalker = 0 OrElse pExpr = 0 Then Return WRC_ABORT

    Dim pCover As SqliteIdxCover Ptr = _
        Cast(SqliteIdxCover Ptr, pWalker->u.pIdxCover)
    ASSERT(pCover <> 0)
    If pCover = 0 OrElse pCover->pIdx = 0 Then
        pWalker->eCode = 1
        Return WRC_ABORT
    End If

    If pExpr->op = TK_COLUMN AndAlso _
       pExpr->iTable = pCover->iCur AndAlso _
       sqlite3TableColumnToIndex(pCover->pIdx, pExpr->iColumn) < 0 Then
        pWalker->eCode = 1
        Return WRC_ABORT
    End If

    Return WRC_CONTINUE
End Function

Function sqlite3ExprCoveredByIndex CDecl Alias "sqlite3ExprCoveredByIndex" ( _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal iCur As SQLITE_C_INT, _
    ByVal pIdx As SqliteIndex Ptr _
) As SQLITE_C_INT
    Dim walker As SqliteWalker = Type<SqliteWalker>(0)
    Dim cover As SqliteIdxCover = Type<SqliteIdxCover>(0)

    cover.iCur = iCur
    cover.pIdx = pIdx
    walker.xExprCallback = CPtr(SqliteWalkerExprCallback, @exprIdxCover)
    walker.u.pIdxCover = @cover

    sqlite3WalkExpr(@walker, pExpr)
    Return CInt(walker.eCode = 0)
End Function

/' ------------------------------------------------------------------------- '/
/' Expression register allocation and constant factoring                     '/
/' ------------------------------------------------------------------------- '/

Function sqlite3ExprCodeTemp CDecl Alias "sqlite3ExprCodeTemp" ( _
    ByVal pParseArgument As Any Ptr, _
    ByVal pExprArgument As Any Ptr, _
    ByVal pRegister As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pParseArgument = 0 OrElse pRegister = 0 Then Return 0

    Dim pParse As SqliteParseContext Ptr = _
        CPtr(SqliteParseContext Ptr, pParseArgument)
    Dim pExpr As SqliteExpr Ptr = _
        sqlite3ExprSkipCollateAndLikely(CPtr(SqliteExpr Ptr, pExprArgument))

    If pParse->okConstFactor <> 0 AndAlso pExpr <> 0 AndAlso _
       pExpr->op <> TK_REGISTER AndAlso _
       sqlite3ExprIsConstantNotJoin(pParse, pExpr) <> 0 Then
        pRegister[0] = 0
        Return sqlite3ExprCodeRunJustOnce(pParseArgument, pExpr, -1)
    End If

    Dim temporaryRegister As SQLITE_C_INT = sqlite3GetTempReg(pParse)
    Dim resultRegister As SQLITE_C_INT = sqlite3ExprCodeTarget( _
        pParseArgument, pExpr, temporaryRegister)
    If resultRegister = temporaryRegister Then
        pRegister[0] = temporaryRegister
    Else
        sqlite3ReleaseTempReg(pParse, temporaryRegister)
        pRegister[0] = 0
    End If
    Return resultRegister
End Function

Function sqlite3CodeSubselect CDecl Alias "sqlite3CodeSubselect" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT
    If pParse = 0 OrElse pExpr = 0 OrElse pParse->nErr <> 0 Then Return 0
    Dim pVdbe As SqliteVdbe Ptr = pParse->pVdbe
    If pVdbe = 0 OrElse (pExpr->flags And EP_xIsSelect) = 0 Then Return 0
    If pExpr->op <> TK_EXISTS AndAlso pExpr->op <> TK_SELECT Then Return 0

    Dim pSelect As SqliteSelect Ptr = CPtr(SqliteSelect Ptr, pExpr->x.pSelect)
    If pSelect = 0 OrElse pSelect->pEList = 0 Then Return 0

    ' A previously coded scalar subquery shares the same result register and
    ' jumps into its existing VDBE subroutine.
    If (pExpr->flags And EP_Subrtn) <> 0 Then
#ifndef SQLITE_OMIT_EXPLAIN
        sqlite3VdbeExplainInteger( _
            pParse, 0, StrPtr(!"REUSE SUBQUERY %d"), pExpr->x.pSelect->selId)
#endif
        sqlite3VdbeAddOp2(pVdbe, OP_Gosub, pExpr->y.sub.regReturn, pExpr->y.sub.iAddr)
        Return pExpr->iTable
    End If

    pExpr->flags Or= EP_Subrtn
    pParse->nMem += 1
    pExpr->y.sub.regReturn = pParse->nMem
    pExpr->y.sub.iAddr = _
        sqlite3VdbeAddOp2(pVdbe, OP_BeginSubrtn, 0, pExpr->y.sub.regReturn) + 1

    Dim onceAddress As SQLITE_C_INT = 0
    If (pExpr->flags And EP_VarSelect) = 0 Then _
        onceAddress = sqlite3VdbeAddOp0(pVdbe, OP_Once)

    Dim explainAddress As SQLITE_C_INT = 0
#ifndef SQLITE_OMIT_EXPLAIN
    ' Establish the scalar-subquery parent before SELECT adds its plan nodes.
    Dim correlationPrefix As Const ZString Ptr = StrPtr(!"CORRELATED ")
    If onceAddress <> 0 Then correlationPrefix = StrPtr(!"")
    explainAddress = sqlite3VdbeExplainStringInteger( _
        pParse, 1, StrPtr(!"%sSCALAR SUBQUERY %d"), _
        correlationPrefix, pSelect->selId)
#endif
#ifdef SQLITE_ENABLE_STMT_SCANSTATUS
#ifndef SQLITE_OMIT_EXPLAIN
    sqlite3VdbeScanStatusCounters( _
        pVdbe, explainAddress, explainAddress, -1)
#endif
#endif

    Dim destination As SqliteSelectDest
    Dim registerCount As SQLITE_C_INT = 1
    If pExpr->op = TK_SELECT Then registerCount = pSelect->pEList->nExpr
    If registerCount <= 0 OrElse registerCount > SQLITE_MAX_VDBE_OP Then Return 0

    sqlite3SelectDestInit(@destination, 0, pParse->nMem + 1)
    pParse->nMem += registerCount

    If pExpr->op = TK_SELECT Then
        destination.eDest = SRT_Mem
        If (pSelect->selFlags And SF_Distinct) <> 0 AndAlso _
           pSelect->pLimit <> 0 AndAlso _
           CPtr(SqliteExpr Ptr, pSelect->pLimit)->pRight <> 0 Then
            destination.iSdst = pParse->nMem + 1
            pParse->nMem += registerCount
        Else
            destination.iSdst = destination.iSDParm
        End If
        destination.nSdst = registerCount
        sqlite3VdbeAddOp3(pVdbe, OP_Null, 0, destination.iSDParm, pParse->nMem)
    Else
        destination.eDest = SRT_Exists
        sqlite3VdbeAddOp2(pVdbe, OP_Integer, 0, destination.iSDParm)
    End If

    If pSelect->pLimit <> 0 Then
        Dim pLimit As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pSelect->pLimit)
        Dim pLeft As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pLimit->pLeft)
        If pLeft = 0 Then Return 0
        If (pLeft->flags And EP_IntValue) = 0 OrElse _
           (pLeft->u.iValue <> 1 AndAlso pLeft->u.iValue <> 0) Then
            Dim pNewLimit As SqliteExpr Ptr = sqlite3ExprInt32(pParse->db, 0)
            If pNewLimit <> 0 Then
                pNewLimit->affExpr = SQLITE_AFF_NUMERIC
                pNewLimit = sqlite3PExpr(pParse, TK_NE, _
                    sqlite3ExprDup(pParse->db, pLeft, 0), pNewLimit)
            End If
            sqlite3ExprDeferredDelete(pParse, pLeft)
            pLimit->pLeft = pNewLimit
        End If
    Else
        Dim pOne As SqliteExpr Ptr = sqlite3ExprInt32(pParse->db, 1)
        pSelect->pLimit = sqlite3PExpr(pParse, TK_LIMIT, pOne, 0)
    End If

    pSelect->iLimit = 0
    Dim subquerySelectCode As SQLITE_C_INT = _
        sqlite3Select(pParse, pSelect, @destination)
    If subquerySelectCode <> SQLITE_OK Then
        pExpr->op2 = pExpr->op
        pExpr->op = TK_ERROR
        Return 0
    End If

    pExpr->iTable = destination.iSDParm
#ifdef SQLITE_DEBUG
    pExpr->vvaFlags Or= EP_NoReduce
#endif
    If onceAddress <> 0 Then sqlite3VdbeJumpHere(pVdbe, onceAddress)
#ifdef SQLITE_ENABLE_STMT_SCANSTATUS
#ifndef SQLITE_OMIT_EXPLAIN
    sqlite3VdbeScanStatusRange( _
        pVdbe, explainAddress, explainAddress, -1)
#endif
#endif
    sqlite3VdbeAddOp3(pVdbe, OP_Return, pExpr->y.sub.regReturn, pExpr->y.sub.iAddr, 1)
    sqlite3ClearTempRegCache(pParse)
    Return destination.iSDParm
End Function

Sub sqlite3ExprCodeFactorable CDecl Alias "sqlite3ExprCodeFactorable" ( _
    ByVal pParseArgument As Any Ptr, _
    ByVal pExprArgument As Any Ptr, _
    ByVal targetRegister As SQLITE_C_INT _
)
    If pParseArgument = 0 Then Exit Sub
    Dim pParse As SqliteParseContext Ptr = _
        CPtr(SqliteParseContext Ptr, pParseArgument)
    Dim pExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pExprArgument)

    If pParse->okConstFactor <> 0 AndAlso _
       sqlite3ExprIsConstantNotJoin(pParse, pExpr) <> 0 Then
        sqlite3ExprCodeRunJustOnce(pParseArgument, pExprArgument, targetRegister)
    Else
        sqlite3ExprCodeCopy(pParse, pExpr, targetRegister)
    End If
End Sub

Function sqlite3ExprCodeExprList CDecl Alias "sqlite3ExprCodeExprList" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExprList Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As UByte) As SQLITE_C_INT
    Dim local0 As SqliteExprListItem Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim local4 As UByte
    Dim local5 As SqliteVdbe Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As UByte
    Dim c2fb_temp_2 As SqliteExprListItem Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SqliteExprListItem Ptr
    Dim local6 As SqliteExpr Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim local7 As SQLITE_C_INT
    Dim local8 As SqliteVdbeOp Ptr
    Dim c2fb_temp_10 As SqliteVdbeOp Ptr
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SQLITE_C_INT Ptr
    Dim c2fb_temp_13 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local4 = IIf((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg4) And Cast(SQLITE_C_INT, &H01ULL)))), Cast(SQLITE_C_INT, 82ULL), Cast(SQLITE_C_INT, 83ULL))
    local5 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, arg1->nExpr)
    local3 = Cast(SQLITE_C_INT, arg1->nExpr)
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (arg0)->okConstFactor)) = 0))) Then
        c2fb_temp_1 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg4) And Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, &H02ULL))))))
        arg4 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg4) And Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, &H02ULL))))))
    End If
    c2fb_temp_2 = CPtr(SqliteExprListItem Ptr, (@arg1->a(0)))
    local0 = CPtr(SqliteExprListItem Ptr, (@arg1->a(0)))
    c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    While (-Cast(SQLITE_C_INT, ((local1 < local3))))
        local6 = CPtr(SqliteExpr Ptr, local0->pExpr)
        c2fb_temp_7 = 0
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg4) And Cast(SQLITE_C_INT, &H04ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_6 = Cast(SQLITE_C_INT, local0->u.x.iOrderByCol)
            local2 = Cast(SQLITE_C_INT, local0->u.x.iOrderByCol)
            c2fb_temp_7 = (-Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, (((c2fb_temp_6) > Cast(SQLITE_C_INT, &O0ULL))))) <> 0)))
        End If
        If c2fb_temp_7 Then
            If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg4) And Cast(SQLITE_C_INT, &H08ULL))) Then
                c2fb_temp_8 = local1
                local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_8 - 1)))
                c2fb_temp_9 = local3
                local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_9 - 1)))
            Else
                sqlite3VdbeAddOp2(local5, local4, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local2 + arg3)) - Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, (arg2 + local1)))
            End If
        Else
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg4) And Cast(SQLITE_C_INT, &H02ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso sqlite3ExprIsConstantNotJoin(arg0, local6))))) Then
                sqlite3ExprCodeRunJustOnce(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local6), Cast(SQLITE_C_INT, (arg2 + local1)))
            Else
                local7 = sqlite3ExprCodeTarget(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local6), Cast(SQLITE_C_INT, (arg2 + local1)))
                If (-Cast(SQLITE_C_INT, ((local7 <> Cast(SQLITE_C_INT, (arg2 + local1)))))) Then
                    ' C automatic storage declaration
                    c2fb_temp_11 = 0
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4) = Cast(SQLITE_C_INT, 82ULL))))) Then
                        c2fb_temp_10 = CPtr(SqliteVdbeOp Ptr, sqlite3VdbeGetLastOp(local5))
                        local8 = CPtr(SqliteVdbeOp Ptr, sqlite3VdbeGetLastOp(local5))
                        c2fb_temp_11 = (-Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (c2fb_temp_10)->opcode) = Cast(SQLITE_C_INT, 82ULL))))) <> 0)))
                    End If
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((c2fb_temp_11 AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local8->p1 + local8->p3)) + Cast(SQLITE_C_INT, 1ULL))) = local7)))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local8->p2 + local8->p3)) + Cast(SQLITE_C_INT, 1ULL))) = Cast(SQLITE_C_INT, (arg2 + local1)))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local8->p5) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                        c2fb_temp_12 = @(local8->p3)
                        c2fb_temp_13 = (*c2fb_temp_12)
                        (*c2fb_temp_12) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_13 + 1)))
                    Else
                        sqlite3VdbeAddOp2(local5, local4, local7, Cast(SQLITE_C_INT, (arg2 + local1)))
                    End If
                End If
            End If
        End If
    c2fb_flow_1:
        c2fb_temp_4 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_4 + 1)))
        c2fb_temp_5 = local0
        local0 = (c2fb_temp_5 + 1)
    Wend
    c2fb_flow_0:
    Return local3
End Function

/' end of sqlite3_expr.bas '/
