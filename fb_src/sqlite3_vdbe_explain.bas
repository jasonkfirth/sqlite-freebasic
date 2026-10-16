/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_explain.bas

    Purpose:

        Produce the row values returned by EXPLAIN and EXPLAIN QUERY PLAN.

    Responsibilities:

        - Format opcode P4 operands and optional cursor-hint expressions.
        - Expose P4 and comment rendering helpers to the bytecode-vtab module.
        - Expand opcode synopsis text and optional explain comments.
        - Track trigger subprograms while walking the VDBE listing.
        - Populate the statement result cells for one EXPLAIN row.
        - Report interruption, allocation failure, and end-of-list states.

    This file intentionally does NOT contain:

        - Opcode dispatch, SQL compilation, or the generated opcode-name table.
'/

#lang "fb"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_vdbe_record.bi"
#include once "sqlite3_vdbe_compare.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_vtab_types.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_tokens.bi"
#include once "sqlite3_straccum.bi"
#include once "sqlite3_api_constants.bi"
#include once "sqlite3_fault.bi"
#include once "sqlite3_debug_assert.bi"

Declare Function sqlite3VdbeNextOpcode CDecl Alias "sqlite3VdbeNextOpcode" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pSubprograms As SqliteVdbeMem Ptr, _
    ByVal eqpMode As SQLITE_C_INT, _
    ByVal pProgramCounter As SQLITE_C_INT Ptr, _
    ByVal pOpcodeIndex As SQLITE_C_INT Ptr, _
    ByVal ppOpcodeArray As SqliteVdbeOp Ptr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3OpcodeName CDecl Alias "sqlite3OpcodeName" ( _
    ByVal opcode As SQLITE_C_INT _
) As Const ZString Ptr
Declare Sub sqlite3_str_appendf CDecl Alias "sqlite3_str_appendf" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Function sqlite3ErrStr CDecl Alias "sqlite3ErrStr" ( _
    ByVal errorCode As SQLITE_C_INT _
) As Const ZString Ptr
Declare Sub sqlite3VdbeExplainFree CDecl Alias "sqlite3_free" ( _
    ByVal pAllocation As Any Ptr _
)
Declare Function sqlite3VdbeExplainMemcpy CDecl Alias "memcpy" ( _
    ByVal pDestination As Any Ptr, _
    ByVal pSource As Const Any Ptr, _
    ByVal nByte As SQLITE_SIZE_T _
) As Any Ptr
Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal zText As Const ZString Ptr _
) As SQLITE_C_INT
#ifdef SQLITE_DEBUG
Declare Sub sqlite3DebugPrintf CDecl Alias "sqlite3DebugPrintf" (ByVal zFormat As Const ZString Ptr, ...)
Declare Function sqlite3VdbePrintOpFilePrintf CDecl Alias "fprintf" (ByVal pOutput As Any Ptr, ByVal zFormat As Const ZString Ptr, ...) As SQLITE_C_INT
Declare Function sqlite3VdbePrintOpFileFlush CDecl Alias "fflush" (ByVal pOutput As Any Ptr) As SQLITE_C_INT
#endif

#ifndef SQLITE_OMIT_EXPLAIN

#ifdef SQLITE_ENABLE_EXPLAIN_COMMENTS
Private Function translateP CDecl Alias "translateP" ( _
    ByVal parameter As UByte, _
    ByVal pOpcode As Const SqliteVdbeOp Ptr _
) As SQLITE_C_INT
    Select Case parameter
    Case Asc("1"): Return pOpcode->p1
    Case Asc("2"): Return pOpcode->p2
    Case Asc("3"): Return pOpcode->p3
    Case Asc("4"): Return pOpcode->p4.i
    Case Else: Return pOpcode->p5
    End Select
End Function

Private Function sqlite3VdbeInt32ToInt64( _
    ByVal lowWord As SQLITE_C_INT, _
    ByVal highWord As SQLITE_C_INT _
) As sqlite3_int64
    Dim bits As sqlite3_uint64 = _
        (CULngInt(lowWord) And &HFFFFFFFFULL) Or _
        ((CULngInt(highWord) And &HFFFFFFFFULL) Shl 32)
    Return CLngInt(bits)
End Function

Function sqlite3VdbeDisplayComment CDecl Alias "sqlite3VdbeDisplayComment" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pOpcode As Const SqliteVdbeOp Ptr, _
    ByVal zP4 As Const ZString Ptr _
) As ZString Ptr Export
    If pOpcode = 0 Then Return 0
    Dim pAccum As sqlite3_str Ptr = sqlite3_str_new(db)
    If pAccum = 0 Then Return 0

    Dim zOpcodeName As Const ZString Ptr = sqlite3OpcodeName(pOpcode->opcode)
    Dim opcodeNameLength As SQLITE_C_INT = sqlite3Strlen30(zOpcodeName)
    Dim zOpcodeBytes As Const UByte Ptr = CPtr(Const UByte Ptr, zOpcodeName)
    Dim synopsisPosition As SQLITE_C_INT = opcodeNameLength + 1

    If zOpcodeBytes[synopsisPosition] <> 0 Then
        Dim zSynopsis As Const ZString Ptr = _
            CPtr(Const ZString Ptr, @zOpcodeBytes[synopsisPosition])
        Dim synopsis As String = *zSynopsis
        If Left(synopsis, 3) = "IF " Then
            synopsis = "if " & Mid(synopsis, 4) & " goto P2"
            If Len(synopsis) > 49 Then synopsis = Left(synopsis, 49)
        End If

        Dim seenComment As SQLITE_C_INT = 0
        Dim position As SQLITE_C_INT = 0
        While position < Len(synopsis)
            Dim character As UByte = Asc(synopsis, position + 1)
            If character = Asc("P") Then
                position += 1
                If position >= Len(synopsis) Then Exit While
                character = Asc(synopsis, position + 1)

                If character = Asc("4") Then
                    If zP4 <> 0 Then sqlite3_str_appendall(pAccum, zP4)
                ElseIf character = Asc("X") Then
                    If pOpcode->zComment <> 0 AndAlso pOpcode->zComment[0] <> 0 Then
                        sqlite3_str_appendall(pAccum, pOpcode->zComment)
                        seenComment = 1
                        Exit While
                    End If
                ElseIf Mid(synopsis, position + 1, 5) = "INT13" Then
                    sqlite3_str_appendf(pAccum, StrPtr("%lld"), _
                        sqlite3VdbeInt32ToInt64(pOpcode->p1, pOpcode->p3))
                    position += 4
#ifdef SQLITE_ENABLE_COLUMN_USED_MASK
                ElseIf Mid(synopsis, position + 1, 5) = "HEX23" Then
                    sqlite3_str_appendf(pAccum, StrPtr("0x%llx"), _
                        sqlite3VdbeInt32ToInt64(pOpcode->p2, pOpcode->p3))
                    position += 4
#endif
                ElseIf Mid(synopsis, position + 1, 5) = "DBL13" Then
                    Dim valueBits As sqlite3_int64 = _
                        sqlite3VdbeInt32ToInt64(pOpcode->p1, pOpcode->p3)
                    Dim realValue As Double
                    sqlite3VdbeExplainMemcpy(@realValue, @valueBits, SizeOf(realValue))
                    sqlite3_str_appendf(pAccum, StrPtr("%.17g"), realValue)
                    position += 4
                Else
                    Dim firstValue As SQLITE_C_INT = translateP(character, pOpcode)
                    Dim secondValue As SQLITE_C_INT
                    If Mid(synopsis, position + 2, 2) = "@P" Then
                        position += 3
                        If position >= Len(synopsis) Then Exit While
                        secondValue = translateP( _
                            Asc(synopsis, position + 1), pOpcode)
                        If Mid(synopsis, position + 2, 2) = "+1" Then
                            position += 2
                            secondValue += 1
                        End If
                        If secondValue < 2 Then
                            sqlite3_str_appendf(pAccum, StrPtr("%d"), firstValue)
                        Else
                            sqlite3_str_appendf(pAccum, StrPtr("%d..%d"), _
                                firstValue, firstValue + secondValue - 1)
                        End If
                    ElseIf Mid(synopsis, position + 2, 3) = "@NP" Then
                        Dim pContext As SqliteResultContext Ptr = _
                            CPtr(SqliteResultContext Ptr, pOpcode->p4.p)
                        If pOpcode->p4type <> P4_FUNCCTX OrElse _
                           pContext = 0 OrElse pContext->argc = 1 Then
                            sqlite3_str_appendf(pAccum, StrPtr("%d"), firstValue)
                        ElseIf pContext->argc > 1 Then
                            sqlite3_str_appendf(pAccum, StrPtr("%d..%d"), _
                                firstValue, firstValue + pContext->argc - 1)
                        ElseIf sqlite3_str_errcode(pAccum) = SQLITE_OK Then
                            If pAccum->nChar >= 2 Then pAccum->nChar -= 2
                            position += 1
                        End If
                        position += 3
                    Else
                        sqlite3_str_appendf(pAccum, StrPtr("%d"), firstValue)
                        If Mid(synopsis, position + 2, 4) = "..P3" AndAlso _
                           pOpcode->p3 = 0 Then position += 4
                    End If
                End If
            Else
                sqlite3_str_appendchar(pAccum, 1, CByte(character))
            End If
            position += 1
        Wend

        If seenComment = 0 AndAlso pOpcode->zComment <> 0 Then _
            sqlite3_str_appendf(pAccum, StrPtr("; %s"), pOpcode->zComment)
    ElseIf pOpcode->zComment <> 0 Then
        sqlite3_str_appendall(pAccum, pOpcode->zComment)
    End If

    Dim accumulatorError As SQLITE_C_INT = sqlite3_str_errcode(pAccum)
    If accumulatorError = SQLITE_NOMEM AndAlso db <> 0 Then sqlite3OomFault(db)
    Return sqlite3_str_finish(pAccum)
End Function
#endif

#ifdef SQLITE_ENABLE_CURSOR_HINTS
Private Sub displayP4Expr(ByVal pAccum As sqlite3_str Ptr, ByVal pExpression As SqliteExpr Ptr)
    If pAccum = 0 Then Return
    If pExpression = 0 Then
        sqlite3_str_appendall(pAccum, StrPtr("expr"))
        Return
    End If

    Dim zOperator As Const ZString Ptr = 0
    Select Case pExpression->op
    Case TK_STRING
        Dim zToken As Const ZString Ptr = CPtr(Const ZString Ptr, pExpression->u.zToken)
        sqlite3_str_appendf(pAccum, StrPtr("%Q"), zToken)
        Return
    Case TK_INTEGER
        sqlite3_str_appendf(pAccum, StrPtr("%d"), pExpression->u.iValue)
        Return
    Case TK_NULL
        sqlite3_str_appendall(pAccum, StrPtr("NULL"))
        Return
    Case TK_REGISTER
        sqlite3_str_appendf(pAccum, StrPtr("r[%d]"), pExpression->iTable)
        Return
    Case TK_COLUMN
        If pExpression->iColumn < 0 Then
            sqlite3_str_appendall(pAccum, StrPtr("rowid"))
        Else
            sqlite3_str_appendf(pAccum, StrPtr("c%d"), CInt(pExpression->iColumn))
        End If
        Return
    Case TK_LT: zOperator = StrPtr("LT")
    Case TK_LE: zOperator = StrPtr("LE")
    Case TK_GT: zOperator = StrPtr("GT")
    Case TK_GE: zOperator = StrPtr("GE")
    Case TK_NE: zOperator = StrPtr("NE")
    Case TK_EQ: zOperator = StrPtr("EQ")
    Case TK_IS: zOperator = StrPtr("IS")
    Case TK_ISNOT: zOperator = StrPtr("ISNOT")
    Case TK_AND: zOperator = StrPtr("AND")
    Case TK_OR: zOperator = StrPtr("OR")
    Case TK_PLUS: zOperator = StrPtr("ADD")
    Case TK_STAR: zOperator = StrPtr("MUL")
    Case TK_MINUS: zOperator = StrPtr("SUB")
    Case TK_REM: zOperator = StrPtr("REM")
    Case TK_BITAND: zOperator = StrPtr("BITAND")
    Case TK_BITOR: zOperator = StrPtr("BITOR")
    Case TK_SLASH: zOperator = StrPtr("DIV")
    Case TK_LSHIFT: zOperator = StrPtr("LSHIFT")
    Case TK_RSHIFT: zOperator = StrPtr("RSHIFT")
    Case TK_CONCAT: zOperator = StrPtr("CONCAT")
    Case TK_UMINUS: zOperator = StrPtr("MINUS")
    Case TK_UPLUS: zOperator = StrPtr("PLUS")
    Case TK_BITNOT: zOperator = StrPtr("BITNOT")
    Case TK_NOT: zOperator = StrPtr("NOT")
    Case TK_ISNULL: zOperator = StrPtr("ISNULL")
    Case TK_NOTNULL: zOperator = StrPtr("NOTNULL")
    Case Else
        sqlite3_str_appendall(pAccum, StrPtr("expr"))
        Return
    End Select

    sqlite3_str_appendf(pAccum, StrPtr("%s("), zOperator)
    displayP4Expr(pAccum, pExpression->pLeft)
    If pExpression->pRight <> 0 Then
        sqlite3_str_append(pAccum, StrPtr(","), 1)
        displayP4Expr(pAccum, pExpression->pRight)
    End If
    sqlite3_str_append(pAccum, StrPtr(")"), 1)
End Sub
#endif

Function sqlite3VdbeDisplayP4 CDecl Alias "sqlite3VdbeDisplayP4" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pOpcode As SqliteVdbeOp Ptr _
) As ZString Ptr Export
    If db = 0 OrElse pOpcode = 0 Then Return 0

    Dim pAccum As sqlite3_str Ptr = sqlite3_str_new(db)
    If pAccum = 0 Then Return 0

    Dim zP4 As Const ZString Ptr = 0
    Select Case pOpcode->p4type
    Case P4_KEYINFO
        Dim pKeyInfo As sqlite3VdbeKeyInfoPrefix Ptr = _
            CPtr(sqlite3VdbeKeyInfoPrefix Ptr, pOpcode->p4.pKeyInfo)
        If pKeyInfo = 0 Then
            sqlite3_str_appendall(pAccum, StrPtr("(null)"))
        Else
            sqlite3_str_appendf(pAccum, StrPtr("k(%d"), CInt(pKeyInfo->nKeyField))
            Dim ppCollations As sqlite3CollSeq Ptr Ptr = _
                CPtr(sqlite3CollSeq Ptr Ptr, @pKeyInfo->aColl(0))
            For iField As SQLITE_C_INT = 0 To CInt(pKeyInfo->nKeyField) - 1
                Dim pCollation As sqlite3CollSeq Ptr = ppCollations[iField]
                Dim zCollation As Const ZString Ptr = 0
                If pCollation <> 0 Then zCollation = pCollation->zName
                If zCollation = 0 Then zCollation = StrPtr("")
                If *zCollation = "BINARY" Then zCollation = StrPtr("B")

                Dim zDescending As Const ZString Ptr = StrPtr("")
                Dim zBigNull As Const ZString Ptr = StrPtr("")
                If (pKeyInfo->aSortFlags[iField] And KEYINFO_ORDER_DESC) <> 0 Then _
                    zDescending = StrPtr("-")
                If (pKeyInfo->aSortFlags[iField] And KEYINFO_ORDER_BIGNULL) <> 0 Then _
                    zBigNull = StrPtr("N.")
                sqlite3_str_appendf(pAccum, StrPtr(",%s%s%s"), _
                    zDescending, zBigNull, zCollation)
            Next
            sqlite3_str_append(pAccum, StrPtr(")"), 1)
        End If

#ifdef SQLITE_ENABLE_CURSOR_HINTS
    Case P4_EXPR
        displayP4Expr(pAccum, CPtr(SqliteExpr Ptr, pOpcode->p4.p))
#endif

    Case P4_COLLSEQ
        Dim pCollation As sqlite3CollSeq Ptr = pOpcode->p4.pColl
        If pCollation = 0 Then
            sqlite3_str_appendall(pAccum, StrPtr("(null)"))
        Else
            Dim encodingName As String
            Select Case pCollation->enc
            Case 1: encodingName = "8"
            Case 2: encodingName = "16LE"
            Case 3: encodingName = "16BE"
            Case Else: encodingName = "?"
            End Select
            Dim zCollation As Const ZString Ptr = pCollation->zName
            If zCollation = 0 Then zCollation = StrPtr("")
            sqlite3_str_appendf(pAccum, StrPtr("%.18s-%s"), zCollation, StrPtr(encodingName))
        End If

    Case P4_FUNCDEF
        Dim pFunction As SqliteFuncDef Ptr = CPtr(SqliteFuncDef Ptr, pOpcode->p4.p)
        If pFunction = 0 Then
            sqlite3_str_appendall(pAccum, StrPtr("(null)"))
        Else
            Dim zName As Const ZString Ptr = pFunction->zName
            If zName = 0 Then zName = StrPtr("")
            sqlite3_str_appendf(pAccum, StrPtr("%s(%d)"), zName, CInt(pFunction->nArg))
        End If

    Case P4_FUNCCTX
        Dim pContext As SqliteResultContext Ptr = CPtr(SqliteResultContext Ptr, pOpcode->p4.p)
        Dim pFunction As SqliteFuncDef Ptr
        If pContext <> 0 Then pFunction = CPtr(SqliteFuncDef Ptr, pContext->pFunc)
        If pFunction = 0 Then
            sqlite3_str_appendall(pAccum, StrPtr("(null)"))
        Else
            Dim zName As Const ZString Ptr = pFunction->zName
            If zName = 0 Then zName = StrPtr("")
            sqlite3_str_appendf(pAccum, StrPtr("%s(%d)"), zName, CInt(pFunction->nArg))
        End If

    Case P4_INT32
        sqlite3_str_appendf(pAccum, StrPtr("%d"), pOpcode->p4.i)

    Case P4_MEM
        Dim pValue As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pOpcode->p4.p)
        If pValue = 0 Then
            sqlite3_str_appendall(pAccum, StrPtr("(null)"))
        ElseIf (pValue->flags And MEM_STR) <> 0 Then
            zP4 = CPtr(Const ZString Ptr, pValue->z)
        ElseIf (pValue->flags And (MEM_INT Or MEM_INTREAL)) <> 0 Then
            sqlite3_str_appendf(pAccum, StrPtr("%lld"), pValue->u.i)
        ElseIf (pValue->flags And MEM_REAL) <> 0 Then
            sqlite3_str_appendf(pAccum, StrPtr("%.16g"), pValue->u.r)
        ElseIf (pValue->flags And MEM_NULL) <> 0 Then
            zP4 = StrPtr("NULL")
        Else
            zP4 = StrPtr("(blob)")
        End If

#ifndef SQLITE_OMIT_VIRTUALTABLE
    Case P4_VTAB
        Dim pVTable As SqliteVTable Ptr = CPtr(SqliteVTable Ptr, pOpcode->p4.p)
        Dim pVirtualTable As SqliteVtab Ptr
        If pVTable <> 0 Then pVirtualTable = pVTable->pVtab
        sqlite3_str_appendf(pAccum, StrPtr("vtab:%p"), pVirtualTable)
#endif

    Case P4_INTARRAY
        Dim pValues As u32 Ptr = CPtr(u32 Ptr, pOpcode->p4.p)
        If pValues = 0 Then
            sqlite3_str_appendall(pAccum, StrPtr("(null)"))
        Else
            Dim valueCount As u32 = pValues[0]
            If valueCount > 1000000 Then
                sqlite3_str_appendall(pAccum, StrPtr("(invalid intarray)"))
            Else
                For iValue As u32 = 1 To valueCount
                    Dim separator As Byte = Asc(",")
                    If iValue = 1 Then separator = Asc("[")
                    sqlite3_str_appendf(pAccum, StrPtr("%c%u"), separator, pValues[iValue])
                Next
                sqlite3_str_append(pAccum, StrPtr("]"), 1)
            End If
        End If

    Case P4_SUBPROGRAM
        zP4 = StrPtr("program")

    Case P4_TABLE
        Dim pTable As SqliteTable Ptr = CPtr(SqliteTable Ptr, pOpcode->p4.p)
        If pTable <> 0 Then zP4 = pTable->zName

    Case P4_INDEX
        Dim pIndex As SqliteIndex Ptr = CPtr(SqliteIndex Ptr, pOpcode->p4.p)
        If pIndex <> 0 Then zP4 = pIndex->zName

    Case P4_SUBRTNSIG
        Dim pSignature As SqliteSubroutineSignature Ptr = _
            CPtr(SqliteSubroutineSignature Ptr, pOpcode->p4.p)
        If pSignature = 0 Then
            sqlite3_str_appendall(pAccum, StrPtr("(null)"))
        Else
            Dim zAffinity As Const ZString Ptr = pSignature->zAff
            If zAffinity = 0 Then zAffinity = StrPtr("")
            sqlite3_str_appendf(pAccum, StrPtr("subrtnsig:%d,%s"), _
                pSignature->selId, zAffinity)
        End If

    Case Else
        zP4 = pOpcode->p4.z
    End Select

    If zP4 <> 0 Then sqlite3_str_appendall(pAccum, zP4)
    Dim accumulatorError As SQLITE_C_INT = sqlite3_str_errcode(pAccum)
    Dim result As ZString Ptr = sqlite3_str_finish(pAccum)
    If accumulatorError = SQLITE_NOMEM Then sqlite3OomFault(db)
    Return result
End Function

Private Sub sqlite3VdbeListReleaseMemArray( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pMem As SqliteVdbeMem Ptr, _
    ByVal cellCount As SQLITE_C_INT _
)
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse pMem = 0 OrElse cellCount <= 0 Then Return
    Dim db As sqlite3 Ptr = pVdbe->db

    If db->pnBytesFreed <> 0 Then
        For iCell As SQLITE_C_INT = 0 To cellCount - 1
            If pMem[iCell].szMalloc <> 0 Then _
                sqlite3DbFree(db, pMem[iCell].zMalloc)
        Next
        Return
    End If

    For iCell As SQLITE_C_INT = 0 To cellCount - 1
        If (pMem[iCell].flags And (MEM_AGG Or MEM_DYN)) <> 0 Then
            sqlite3VdbeMemRelease(@pMem[iCell])
            pMem[iCell].flags = MEM_UNDEFINED
        ElseIf pMem[iCell].szMalloc <> 0 Then
            sqlite3DbNNFreeNN(db, pMem[iCell].zMalloc)
            pMem[iCell].szMalloc = 0
            pMem[iCell].flags = MEM_UNDEFINED
        End If
    Next
End Sub

Function sqlite3VdbeList CDecl Alias "sqlite3VdbeList" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT Export
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse pVdbe->aMem = 0 OrElse _
       pVdbe->nMem < 8 Then Return SQLITE_CORRUPT

    Dim db As sqlite3 Ptr = pVdbe->db
    Dim pResult As SqliteVdbeMem Ptr = @pVdbe->aMem[1]
    Dim explainMode As SQLITE_C_INT = _
        CInt((pVdbe->vdbeFlags And VDBE_EXPLAIN_MASK) Shr VDBE_EXPLAIN_SHIFT)
    Dim listSubprograms As SQLITE_C_INT = CInt( _
        explainMode = 1 OrElse (db->flags And SQLITE_TriggerEQP) <> 0)
    Dim pSubprograms As SqliteVdbeMem Ptr

    If pVdbe->eVdbeState <> VDBE_RUN_STATE OrElse explainMode = 0 Then Return SQLITE_MISUSE
    sqlite3VdbeListReleaseMemArray(pVdbe, pResult, 8)

    If pVdbe->rc = SQLITE_NOMEM Then
        sqlite3OomFault(db)
        Return SQLITE_ERROR
    End If

    If listSubprograms <> 0 Then
        If pVdbe->nMem <= 9 Then Return SQLITE_CORRUPT
        pSubprograms = @pVdbe->aMem[9]
    End If

    Dim opcodeIndex As SQLITE_C_INT = 0
    Dim pOpcodeArray As SqliteVdbeOp Ptr
    Dim rc As SQLITE_C_INT = sqlite3VdbeNextOpcode( _
        pVdbe, pSubprograms, CInt(explainMode = 2), @pVdbe->pc, _
        @opcodeIndex, @pOpcodeArray)

    If rc = SQLITE_OK Then
        If pOpcodeArray = 0 OrElse opcodeIndex < 0 Then Return SQLITE_CORRUPT
        Dim pOpcode As SqliteVdbeOp Ptr = @pOpcodeArray[opcodeIndex]
        If sqlite3InterruptPending(db) <> 0 Then
            pVdbe->rc = SQLITE_INTERRUPT
            sqlite3VdbeError(pVdbe, sqlite3ErrStr(pVdbe->rc))
            Return SQLITE_ERROR
        End If

        Dim zP4 As ZString Ptr = sqlite3VdbeDisplayP4(db, pOpcode)
        If explainMode = 2 Then
            sqlite3VdbeMemSetInt64(@pResult[0], pOpcode->p1)
            sqlite3VdbeMemSetInt64(@pResult[1], pOpcode->p2)
            sqlite3VdbeMemSetInt64(@pResult[2], pOpcode->p3)
            sqlite3VdbeMemSetStr(@pResult[3], zP4, -1, SQLITE_UTF8, _
                CPtr(sqlite3MemDestructor, ProcPtr(sqlite3VdbeExplainFree)))
            If pVdbe->nResColumn <> 4 Then Return SQLITE_CORRUPT
        Else
            sqlite3VdbeMemSetInt64(@pResult[0], opcodeIndex)
            sqlite3VdbeMemSetText(@pResult[1], sqlite3OpcodeName(pOpcode->opcode), -1, _
                CPtr(sqlite3MemDestructor, -1))
            sqlite3VdbeMemSetInt64(@pResult[2], pOpcode->p1)
            sqlite3VdbeMemSetInt64(@pResult[3], pOpcode->p2)
            sqlite3VdbeMemSetInt64(@pResult[4], pOpcode->p3)
            sqlite3VdbeMemSetInt64(@pResult[6], pOpcode->p5)
#ifdef SQLITE_ENABLE_EXPLAIN_COMMENTS
            Dim zComment As ZString Ptr = _
                sqlite3VdbeDisplayComment(db, pOpcode, zP4)
            sqlite3VdbeMemSetStr(@pResult[7], zComment, -1, SQLITE_UTF8, _
                CPtr(sqlite3MemDestructor, ProcPtr(sqlite3VdbeExplainFree)))
#else
            sqlite3VdbeMemSetNull(@pResult[7])
#endif
            sqlite3VdbeMemSetStr(@pResult[5], zP4, -1, SQLITE_UTF8, _
                CPtr(sqlite3MemDestructor, ProcPtr(sqlite3VdbeExplainFree)))
            If pVdbe->nResColumn <> 8 Then Return SQLITE_CORRUPT
        End If

        pVdbe->pResultRow = pResult
        If db->mallocFailed <> 0 Then
            pVdbe->rc = SQLITE_NOMEM
            Return SQLITE_ERROR
        End If
        pVdbe->rc = SQLITE_OK
        Return SQLITE_ROW
    End If
    Return rc
End Function

#ifdef SQLITE_DEBUG
Sub sqlite3VdbePrintOp CDecl Alias "sqlite3VdbePrintOp" ( _
    ByVal pOutput As Any Ptr, _
    ByVal programCounter As SQLITE_C_INT, _
    ByVal pOpcode As SqliteVdbeOp Ptr _
) Export
    If pOpcode = 0 Then
        sqlite3DebugAssert(StrPtr("pOp is valid"))
        Exit Sub
    End If

    Dim dummyDatabase As sqlite3 = Type<sqlite3>(0)
    dummyDatabase.mallocFailed = 1
    sqlite3BeginBenignMalloc()
    Dim zP4 As ZString Ptr = sqlite3VdbeDisplayP4(@dummyDatabase, pOpcode)
    Dim zComment As ZString Ptr = 0
#ifdef SQLITE_ENABLE_EXPLAIN_COMMENTS
    zComment = sqlite3VdbeDisplayComment(0, pOpcode, zP4)
#endif

    Dim zOpcode As Const ZString Ptr = sqlite3OpcodeName(pOpcode->opcode)
    If zOpcode = 0 Then zOpcode = StrPtr("(unknown)")
    Dim zP4Text As Const ZString Ptr = zP4
    If zP4Text = 0 Then zP4Text = StrPtr("")
    Dim zCommentText As Const ZString Ptr = zComment
    If zCommentText = 0 Then zCommentText = StrPtr("")
    Dim zFormat As Const ZString Ptr = _
        StrPtr(!"%4d %-13s %4d %4d %4d %-13s %.2X %s\n")

    If pOutput = 0 Then
        sqlite3DebugPrintf(zFormat, programCounter, zOpcode, _
            pOpcode->p1, pOpcode->p2, pOpcode->p3, zP4Text, _
            pOpcode->p5, zCommentText)
    Else
        sqlite3VdbePrintOpFilePrintf(pOutput, zFormat, programCounter, _
            zOpcode, pOpcode->p1, pOpcode->p2, pOpcode->p3, zP4Text, _
            pOpcode->p5, zCommentText)
        sqlite3VdbePrintOpFileFlush(pOutput)
    End If

    sqlite3VdbeExplainFree(zP4)
    sqlite3VdbeExplainFree(zComment)
    sqlite3EndBenignMalloc()
End Sub
#endif

#endif

/' end of sqlite3_vdbe_explain.bas '/
