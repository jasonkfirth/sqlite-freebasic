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
** This module contains code that traces WHERE-clause terms and opcode
** rewrites in debug builds.
'/

/' ------------------------------------------------------------------------- '/
/' SQLite FreeBASIC port                                                      '/
/' ------------------------------------------------------------------------- '/

/' Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_bulk_debug_where.bas

    Purpose:

        Print WHERE term details for SQLite's debug traces.

    Responsibilities:

        - Format one WhereTerm and render its expression tree.
        - Keep the null-term trace callback used during opcode rewriting.

    This file intentionally does NOT contain:

        - WHERE planning, loop selection, or test-runner code.
'/

#lang "fb"
#ifdef SQLITE_DEBUG

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_treeview_types.bi"
#include once "sqlite3_vtab_types.bi"
#include once "sqlite3_util_numeric.bi"
#include once "sqlite3_debug_assert.bi"

Declare Sub sqlite3DebugPrintf CDecl Alias "sqlite3DebugPrintf" (ByVal zFormat As Const ZString Ptr, ...)
Declare Function sqlite3_snprintf CDecl Alias "sqlite3_snprintf" (ByVal nByte As SQLITE_C_INT, ByVal zBuffer As ZString Ptr, ByVal zFormat As Const ZString Ptr, ...) As ZString Ptr
Declare Sub sqlite3TreeViewExpr CDecl Alias "sqlite3TreeViewExpr" (ByVal pView As SqliteTreeView Ptr, ByVal pExpr As Const SqliteExpr Ptr, ByVal moreToFollow As UByte)
Declare Function sqlite3WhereTraceValue CDecl Alias "sqlite3WhereTraceValue" () As u32
Declare Function sqlite3WhereVtabCollation CDecl Alias "sqlite3_vtab_collation" (ByVal pIndexInfo As Any Ptr, ByVal constraintIndex As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3WhereLoopMPrintf CDecl Alias "sqlite3_mprintf" (ByVal zFormat As Const ZString Ptr, ...) As ZString Ptr
Declare Sub sqlite3WhereLoopFree CDecl Alias "sqlite3_free" (ByVal pAllocation As Any Ptr)
Declare Function sqlite3WhereStrlen30 CDecl Alias "sqlite3Strlen30" (ByVal zText As Const ZString Ptr) As SQLITE_C_INT

Private Const SQLITE3_FB_TERM_CODED As UShort = &H0004
Private Const SQLITE3_FB_WO_OR As UShort = &H0200
Private Const SQLITE3_FB_WO_AND As UShort = &H0400
Private Const SQLITE3_FB_WO_SINGLE As UShort = &H01FF
' Bit 16 enables the extra prereq and probability fields in WHERE traces.
Private Const SQLITE3_FB_WHERETRACE_TERM_DETAIL As u32 = &H00010000
' HI(0x0800000), the database flag that enables VDBE opcode tracing.
Private Const SQLITE3_FB_VDBE_ADDOP_TRACE_MASK As sqlite3_uint64 = &H0080000000000000ULL

Sub sqlite3WhereTermPrint CDecl Alias "sqlite3WhereTermPrint" ( _
    ByVal pTerm As SqliteWhereTerm Ptr, _
    ByVal inputTermIndex As SQLITE_C_INT _
) Export
    Dim termIndex As SQLITE_C_INT = inputTermIndex
    If pTerm = 0 Then
        sqlite3DebugPrintf(StrPtr(!"TERM-%-3d NULL\n"), termIndex)
        Exit Sub
    End If

    If pTerm->pExpr = 0 Then
        sqlite3DebugAssert(StrPtr("WhereTerm has an expression"))
        Exit Sub
    End If

    Dim zType As ZString * 8 = "...."
    Dim zLeft As ZString * 50 = ""
    Dim pTypeBytes As UByte Ptr = CPtr(UByte Ptr, @zType)
    If (pTerm->wtFlags And TERM_VIRTUAL) <> 0 Then pTypeBytes[0] = Asc("V")
    If (pTerm->eOperator And WO_EQUIV) <> 0 Then pTypeBytes[1] = Asc("E")
    If (pTerm->pExpr->flags And EP_OuterON) <> 0 Then pTypeBytes[2] = Asc("L")
    If (pTerm->wtFlags And SQLITE3_FB_TERM_CODED) <> 0 Then pTypeBytes[3] = Asc("C")

    If (pTerm->eOperator And SQLITE3_FB_WO_SINGLE) <> 0 Then
        If (pTerm->eOperator And (SQLITE3_FB_WO_OR Or SQLITE3_FB_WO_AND)) <> 0 Then
            sqlite3DebugAssert(StrPtr("single WhereTerm has no compound operator"))
            Exit Sub
        End If
        sqlite3_snprintf(SizeOf(zLeft), StrPtr(zLeft), _
            StrPtr("left={%d:%d}"), pTerm->leftCursor, pTerm->u.x.leftColumn)
    ElseIf (pTerm->eOperator And SQLITE3_FB_WO_OR) <> 0 AndAlso _
           pTerm->u.pOrInfo <> 0 Then
        Dim pOrInfo As SqliteWhereOrInfo Ptr = _
            CPtr(SqliteWhereOrInfo Ptr, pTerm->u.pOrInfo)
        sqlite3_snprintf(SizeOf(zLeft), StrPtr(zLeft), _
            StrPtr("indexable=0x%llx"), pOrInfo->indexable)
    Else
        sqlite3_snprintf(SizeOf(zLeft), StrPtr(zLeft), _
            StrPtr("left=%d"), pTerm->leftCursor)
    End If

    If termIndex < pTerm->iTerm Then termIndex = pTerm->iTerm
    pTerm->iTerm = termIndex
    sqlite3DebugPrintf( _
        StrPtr("TERM-%-3d %p %s %-12s op=%03x wtFlags=%04x"), _
        termIndex, pTerm, StrPtr(zType), StrPtr(zLeft), _
        pTerm->eOperator, pTerm->wtFlags)
    If (sqlite3WhereTraceValue() And SQLITE3_FB_WHERETRACE_TERM_DETAIL) <> 0 Then
        sqlite3DebugPrintf( _
            StrPtr(" prob=%-3d prereq=%llx,%llx"), _
            pTerm->truthProb, pTerm->prereqAll, pTerm->prereqRight)
    End If
    If (pTerm->eOperator And (SQLITE3_FB_WO_OR Or SQLITE3_FB_WO_AND)) = 0 AndAlso _
       pTerm->u.x.iField <> 0 Then
        sqlite3DebugPrintf(StrPtr(" iField=%d"), pTerm->u.x.iField)
    End If
    If pTerm->iParent >= 0 Then _
        sqlite3DebugPrintf(StrPtr(" iParent=%d"), pTerm->iParent)
    sqlite3DebugPrintf(StrPtr(!"\n"))
    sqlite3TreeViewExpr(0, pTerm->pExpr, 0)
End Sub

Sub sqlite3ShowWhereTerm CDecl Alias "sqlite3ShowWhereTerm" ( _
    ByVal pTerm As SqliteWhereTerm Ptr _
) Export
    sqlite3WhereTermPrint(pTerm, 0)
End Sub

Sub sqlite3WhereOpcodeRewriteTrace CDecl Alias "sqlite3WhereOpcodeRewriteTrace" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal programCounter As SQLITE_C_INT, _
    ByVal pOpcode As SqliteVdbeOp Ptr _
) Export
    If db = 0 OrElse pOpcode = 0 Then
        sqlite3DebugAssert(StrPtr("database and opcode pointers are valid"))
        Exit Sub
    End If
    If (db->flags And SQLITE3_FB_VDBE_ADDOP_TRACE_MASK) = 0 Then Return
    sqlite3VdbePrintOp(0, programCounter, pOpcode)
    sqlite3ShowWhereTerm(0)
End Sub

#if WHERETRACE_ENABLED
Private Const SQLITE3_FB_WHERE_SKIPSCAN As u32 = &H00008000
Private Const SQLITE3_FB_WHEREINFO_STAR_USED As u32 = &H00000020
Private Const SQLITE3_FB_AUTO_INDEX_PREFIX_LENGTH As SQLITE_C_INT = 17

Private Dim Shared sqlite3WherePathNameBuffer(0 To 64) As UByte

#ifndef SQLITE_OMIT_VIRTUALTABLE
Private Sub whereTraceIndexInfoInputs CDecl Alias "whereTraceIndexInfoInputs" ( _
    ByVal pIndexInfo As SqliteIndexInfo Ptr, _
    ByVal pTable As SqliteTable Ptr _
)
    If (sqlite3WhereTraceValue() And &H10) = 0 Then Return
    If pIndexInfo = 0 OrElse pTable = 0 Then
        sqlite3DebugAssert(StrPtr("index-info input trace arguments are valid"))
        Exit Sub
    End If
    If pIndexInfo->nConstraint < 0 OrElse pIndexInfo->nOrderBy < 0 OrElse _
       (pIndexInfo->nConstraint > 0 AndAlso pIndexInfo->aConstraint = 0) OrElse _
       (pIndexInfo->nOrderBy > 0 AndAlso pIndexInfo->aOrderBy = 0) Then
        sqlite3DebugAssert(StrPtr("index-info input arrays match their counts"))
        Exit Sub
    End If

    Dim zTableName As Const ZString Ptr = pTable->zName
    If zTableName = 0 Then zTableName = StrPtr("(null)")
    sqlite3DebugPrintf(StrPtr(!"sqlite3_index_info inputs for %s:\n"), zTableName)
    For index As SQLITE_C_INT = 0 To pIndexInfo->nConstraint - 1
        Dim pConstraint As SqliteIndexConstraint Ptr = _
            @pIndexInfo->aConstraint[index]
        Dim zCollation As Const ZString Ptr = _
            sqlite3WhereVtabCollation(pIndexInfo, index)
        If zCollation = 0 Then zCollation = StrPtr("(null)")
        sqlite3DebugPrintf( _
            StrPtr(!"  constraint[%d]: col=%d termid=%d op=%d usabled=%d collseq=%s\n"), _
            index, pConstraint->iColumn, pConstraint->iTermOffset, _
            pConstraint->op, pConstraint->usable, zCollation)
    Next
    For index As SQLITE_C_INT = 0 To pIndexInfo->nOrderBy - 1
        Dim pOrder As SqliteIndexOrderBy Ptr = @pIndexInfo->aOrderBy[index]
        sqlite3DebugPrintf(StrPtr(!"  orderby[%d]: col=%d desc=%d\n"), _
            index, pOrder->iColumn, pOrder->desc)
    Next
End Sub

Private Sub whereTraceIndexInfoOutputs CDecl Alias "whereTraceIndexInfoOutputs" ( _
    ByVal pIndexInfo As SqliteIndexInfo Ptr, _
    ByVal pTable As SqliteTable Ptr _
)
    If (sqlite3WhereTraceValue() And &H10) = 0 Then Return
    If pIndexInfo = 0 OrElse pTable = 0 Then
        sqlite3DebugAssert(StrPtr("index-info output trace arguments are valid"))
        Exit Sub
    End If
    If pIndexInfo->nConstraint < 0 OrElse _
       (pIndexInfo->nConstraint > 0 AndAlso pIndexInfo->aConstraintUsage = 0) Then
        sqlite3DebugAssert(StrPtr("index-info usage array matches its count"))
        Exit Sub
    End If

    Dim zTableName As Const ZString Ptr = pTable->zName
    If zTableName = 0 Then zTableName = StrPtr("(null)")
    sqlite3DebugPrintf(StrPtr(!"sqlite3_index_info outputs for %s:\n"), zTableName)
    For index As SQLITE_C_INT = 0 To pIndexInfo->nConstraint - 1
        Dim pUsage As SqliteIndexConstraintUsage Ptr = _
            @pIndexInfo->aConstraintUsage[index]
        sqlite3DebugPrintf(StrPtr(!"  usage[%d]: argvIdx=%d omit=%d\n"), _
            index, pUsage->argvIndex, pUsage->omit)
    Next
    Dim zIndexString As Const ZString Ptr = pIndexInfo->idxStr
    If zIndexString = 0 Then zIndexString = StrPtr("(null)")
    sqlite3DebugPrintf(StrPtr(!"  idxNum=%d\n"), pIndexInfo->idxNum)
    sqlite3DebugPrintf(StrPtr(!"  idxStr=%s\n"), zIndexString)
    sqlite3DebugPrintf(StrPtr(!"  orderByConsumed=%d\n"), _
        pIndexInfo->orderByConsumed)
    sqlite3DebugPrintf(StrPtr(!"  estimatedCost=%g\n"), _
        pIndexInfo->estimatedCost)
    sqlite3DebugPrintf(StrPtr(!"  estimatedRows=%lld\n"), _
        pIndexInfo->estimatedRows)
End Sub
#endif

Sub sqlite3WhereClausePrint CDecl Alias "sqlite3WhereClausePrint" ( _
    ByVal pWhereClause As SqliteWhereClause Ptr _
) Export
    If pWhereClause = 0 OrElse pWhereClause->nTerm < 0 OrElse _
       (pWhereClause->nTerm > 0 AndAlso pWhereClause->a = 0) Then
        sqlite3DebugAssert(StrPtr("WhereClause term array matches its count"))
        Exit Sub
    End If
    For index As SQLITE_C_INT = 0 To pWhereClause->nTerm - 1
        sqlite3WhereTermPrint(@pWhereClause->a[index], index)
    Next
End Sub

Sub sqlite3WhereLoopPrint CDecl Alias "sqlite3WhereLoopPrint" ( _
    ByVal pLoop As Const SqliteWhereLoop Ptr, _
    ByVal pWhereClause As Const SqliteWhereClause Ptr _
) Export
    If pLoop = 0 Then
        sqlite3DebugAssert(StrPtr("WhereLoop is valid"))
        Exit Sub
    End If

    Dim pWhereInfo As SqliteWhereInfo Ptr = 0
    If pWhereClause <> 0 Then
        pWhereInfo = pWhereClause->pWInfo
        If pWhereInfo = 0 OrElse pWhereInfo->pTabList = 0 Then
            sqlite3DebugAssert(StrPtr("WhereClause belongs to a planner context"))
            Exit Sub
        End If
        Dim sourceCount As SQLITE_C_INT = pWhereInfo->pTabList->nSrc
        If sourceCount <= 0 OrElse pLoop->iTab >= sourceCount Then
            sqlite3DebugAssert(StrPtr("WhereLoop table index is in range"))
            Exit Sub
        End If

        Dim outputWidth As SQLITE_C_INT = 1 + (sourceCount + 3) \ 4
        Dim bitWidth As SQLITE_C_INT = outputWidth * 4
        Dim allMasks As sqlite3_uint64
        If bitWidth >= 64 Then
            allMasks = &HFFFFFFFFFFFFFFFFULL
        Else
            allMasks = (1ULL Shl bitWidth) - 1
        End If

        Dim pItem As SqliteSrcItem Ptr = _
            @pWhereInfo->pTabList->a(pLoop->iTab)
        Dim pTable As SqliteTable Ptr = pItem->pSTab
        If pTable = 0 Then
            sqlite3DebugAssert(StrPtr("WhereLoop source table is valid"))
            Exit Sub
        End If
        Dim zTableName As Const ZString Ptr = pItem->zAlias
        If zTableName = 0 Then zTableName = pTable->zName
        If zTableName = 0 Then zTableName = StrPtr("(null)")

        sqlite3DebugPrintf( _
            StrPtr("%c%2d.%0*llx.%0*llx"), CInt(pLoop->cId), _
            pLoop->iTab, outputWidth, pLoop->maskSelf, outputWidth, _
            pLoop->prereq And allMasks)
        sqlite3DebugPrintf(StrPtr(" %12s"), zTableName)
    Else
        sqlite3DebugPrintf( _
            StrPtr("%c%2d.%03llx.%03llx %c%d"), CInt(pLoop->cId), _
            pLoop->iTab, pLoop->maskSelf, pLoop->prereq And &HFFFULL, _
            CInt(pLoop->cId), pLoop->iTab)
    End If

    If (pLoop->wsFlags And WHERE_VIRTUALTABLE) = 0 Then
        Dim zIndexName As Const ZString Ptr = 0
        If pLoop->u.btree.pIndex <> 0 Then
            Dim pIndex As SqliteIndex Ptr = _
                CPtr(SqliteIndex Ptr, pLoop->u.btree.pIndex)
            zIndexName = pIndex->zName
        End If
        If zIndexName <> 0 Then
            Dim isAutoIndex As SQLITE_C_INT = 1
            Dim zAutoPrefix As Const ZString Ptr = StrPtr("sqlite_autoindex_")
            For prefixIndex As SQLITE_C_INT = 0 To _
                SQLITE3_FB_AUTO_INDEX_PREFIX_LENGTH - 1
                If CPtr(Const UByte Ptr, zIndexName)[prefixIndex] = 0 OrElse _
                   CPtr(Const UByte Ptr, zIndexName)[prefixIndex] <> _
                   CPtr(Const UByte Ptr, zAutoPrefix)[prefixIndex] Then
                    isAutoIndex = 0
                    Exit For
                End If
            Next
            If isAutoIndex <> 0 Then
                Dim indexNameLength As SQLITE_C_INT = sqlite3WhereStrlen30(zIndexName)
                Dim suffixIndex As SQLITE_C_INT = indexNameLength - 1
                While suffixIndex >= 0 AndAlso _
                      CPtr(Const UByte Ptr, zIndexName)[suffixIndex] <> Asc("_")
                    suffixIndex -= 1
                Wend
                If suffixIndex >= 0 Then
                    zIndexName = CPtr(Const ZString Ptr, _
                        CPtr(Const UByte Ptr, zIndexName) + suffixIndex)
                End If
            End If
            sqlite3DebugPrintf(StrPtr(".%-16s %2d"), zIndexName, _
                pLoop->u.btree.nEq)
        Else
            sqlite3DebugPrintf(StrPtr("%20s"), StrPtr(""))
        End If
    Else
        Dim zVirtualIndex As ZString Ptr
        Dim freeVirtualIndex As SQLITE_C_INT = 1
        Dim pVirtualIndex As Const ZString Ptr = _
            CPtr(Const ZString Ptr, pLoop->u.vtab.idxStr)
        If pVirtualIndex <> 0 Then
            zVirtualIndex = sqlite3WhereLoopMPrintf( _
                StrPtr(!"(%d,\"%s\",%#x)"), pLoop->u.vtab.idxNum, _
                pVirtualIndex, pLoop->u.vtab.omitMask)
        Else
            zVirtualIndex = sqlite3WhereLoopMPrintf( _
                StrPtr("(%d,%x)"), pLoop->u.vtab.idxNum, _
                pLoop->u.vtab.omitMask)
        End If
        If zVirtualIndex = 0 Then
            zVirtualIndex = StrPtr("(OOM)")
            freeVirtualIndex = 0
        End If
        sqlite3DebugPrintf(StrPtr(" %-19s"), zVirtualIndex)
        If freeVirtualIndex <> 0 Then sqlite3WhereLoopFree(zVirtualIndex)
    End If

    If (pLoop->wsFlags And SQLITE3_FB_WHERE_SKIPSCAN) <> 0 Then
        sqlite3DebugPrintf(StrPtr(" f %06x %d-%d"), _
            pLoop->wsFlags, pLoop->nLTerm, pLoop->nSkip)
    Else
        sqlite3DebugPrintf(StrPtr(" f %06x N %d"), _
            pLoop->wsFlags, pLoop->nLTerm)
    End If

    If pWhereInfo <> 0 AndAlso _
       (pWhereInfo->flags And SQLITE3_FB_WHEREINFO_STAR_USED) <> 0 AndAlso _
       pLoop->rStarDelta <> 0 Then
        sqlite3DebugPrintf(StrPtr(" cost %d,%d,%d delta=%d\n"), _
            pLoop->rSetup, pLoop->rRun, pLoop->nOut, pLoop->rStarDelta)
    Else
        sqlite3DebugPrintf(StrPtr(" cost %d,%d,%d\n"), _
            pLoop->rSetup, pLoop->rRun, pLoop->nOut)
    End If

    If pLoop->nLTerm > 0 AndAlso _
       (sqlite3WhereTraceValue() And &H4000) <> 0 Then
        If pLoop->aLTerm = 0 Then
            sqlite3DebugAssert(StrPtr("WhereLoop has its term array"))
            Exit Sub
        End If
        For termIndex As SQLITE_C_INT = 0 To pLoop->nLTerm - 1
            sqlite3WhereTermPrint(pLoop->aLTerm[termIndex], termIndex)
        Next
    End If
End Sub

Sub sqlite3ShowWhereLoop CDecl Alias "sqlite3ShowWhereLoop" ( _
    ByVal pLoop As Const SqliteWhereLoop Ptr _
) Export
    If pLoop <> 0 Then sqlite3WhereLoopPrint(pLoop, 0)
End Sub

Sub sqlite3ShowWhereLoopList CDecl Alias "sqlite3ShowWhereLoopList" ( _
    ByVal firstLoop As Const SqliteWhereLoop Ptr _
) Export
    Dim pLoop As Const SqliteWhereLoop Ptr = firstLoop
    Dim loopCount As ULongInt = 0
    While pLoop <> 0
        If loopCount >= 1000000 Then
            sqlite3DebugAssert(StrPtr("WhereLoop list is finite"))
            Exit Sub
        End If
        sqlite3ShowWhereLoop(pLoop)
        pLoop = CPtr(Const SqliteWhereLoop Ptr, pLoop->pNextLoop)
        loopCount += 1
    Wend
End Sub

Private Function wherePathName CDecl Alias "wherePathName" ( _
    ByVal pPath As Const SqliteWherePath Ptr, _
    ByVal loopCount As SQLITE_C_INT, _
    ByVal pLastLoop As Const SqliteWhereLoop Ptr _
) As Const ZString Ptr
    If pPath = 0 OrElse loopCount < 0 OrElse loopCount > 64 OrElse _
       (loopCount > 0 AndAlso pPath->aLoop = 0) OrElse _
       (pLastLoop <> 0 AndAlso loopCount >= 64) Then
        sqlite3DebugAssert(StrPtr("WherePath loop count fits its debug name buffer"))
        Return StrPtr("")
    End If

    Dim ppLoop As Const SqliteWhereLoop Ptr Ptr = _
        CPtr(Const SqliteWhereLoop Ptr Ptr, pPath->aLoop)
    For index As SQLITE_C_INT = 0 To loopCount - 1
        If ppLoop[index] = 0 Then
            sqlite3DebugAssert(StrPtr("WherePath loop entry is valid"))
            Return StrPtr("")
        End If
        sqlite3WherePathNameBuffer(index) = CByte(ppLoop[index]->cId)
    Next
    Dim nameLength As SQLITE_C_INT = loopCount
    If pLastLoop <> 0 Then
        sqlite3WherePathNameBuffer(nameLength) = CByte(pLastLoop->cId)
        nameLength += 1
    End If
    sqlite3WherePathNameBuffer(nameLength) = 0
    Return CPtr(Const ZString Ptr, @sqlite3WherePathNameBuffer(0))
End Function

Private Sub showAllWhereLoops CDecl Alias "showAllWhereLoops" ( _
    ByVal pWhereInfo As SqliteWhereInfo Ptr, _
    ByVal pWhereClause As SqliteWhereClause Ptr _
)
    If pWhereInfo = 0 OrElse pWhereInfo->pLoops = 0 OrElse _
       sqlite3WhereTraceValue() = 0 Then Return

    Dim zLabel As Const ZString Ptr = _
        StrPtr("0123456789abcdefghijklmnopqrstuvwyxzABCDEFGHIJKLMNOPQRSTUVWYXZ")
    Dim labelCount As SQLITE_C_INT = sqlite3WhereStrlen30(zLabel)
    If labelCount <= 0 Then Return
    Dim pLoop As SqliteWhereLoop Ptr = _
        CPtr(SqliteWhereLoop Ptr, pWhereInfo->pLoops)
    Dim loopIndex As ULongInt = 0
    While pLoop <> 0
        If loopIndex >= 1000000 Then
            sqlite3DebugAssert(StrPtr("WhereLoop list is finite"))
            Exit Sub
        End If
        Dim labelIndex As SQLITE_C_INT = CInt(loopIndex Mod CULngInt(labelCount))
        pLoop->cId = CByte(CPtr(Const UByte Ptr, zLabel)[labelIndex])
        sqlite3WhereLoopPrint(pLoop, pWhereClause)
        pLoop = CPtr(SqliteWhereLoop Ptr, pLoop->pNextLoop)
        loopIndex += 1
    Wend
End Sub
#endif

#endif

/' end of sqlite3_bulk_debug_where.bas '/
