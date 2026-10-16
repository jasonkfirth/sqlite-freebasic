/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_core.bas

    Purpose:

        Create a VDBE builder and manage its basic opcode array.

    Responsibilities:

        - Create and link a VDBE with its initial OP_Init instruction.
        - Allocate statement registers and variable bindings before execution.
        - Reuse opcode-array capacity for VDBE arrays with one spill allocation.
        - Grow the opcode array through the database allocator.
        - Initialize opcode operands and P4 storage tags.
        - Store result-column names and patch jump and operand values.
        - Rewind the statement and release VDBE-owned arrays on deletion.
        - Release auxiliary-data callbacks when deleting a statement.
        - Track statement expiration and change-count state.
        - Check debug-only opcode allocation, result-row, and abort invariants.
        - Link subprograms into the VDBE-owned cleanup list.
        - Attach explain comments to opcodes and print debug SQL text.
        - Reject debug subroutine jumps that escape their opcode range.

    This file intentionally does NOT contain:

        - SQL compilation, opcode dispatch, or complete statement finalization.
'/

#lang "fb"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_btree.bi"
#include once "sqlite3_vdbe_cursor.bi"
#include once "sqlite3_vdbe_record.bi"
#include once "sqlite3_expr_types.bi"
#ifdef SQLITE_DEBUG
#include once "sqlite3_debug_assert.bi"
#include once "sqlite3_global_data.bi"
#include once "sqlite3_straccum.bi"
Declare Sub sqlite3VdbeCoreStrAppendf CDecl Alias "sqlite3_str_appendf" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Sub sqlite3VdbeCoreFree CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Extern "C"
    Declare Function sqlite3VdbeDebugPrintf CDecl Alias "printf" ( _
        ByVal format As Const ZString Ptr, _
        ... _
    ) As SQLITE_C_INT
End Extern
#endif

Extern "C"
    Declare Function sqlite3VdbeCoreMemcpy CDecl Alias "memcpy" ( _
        ByVal destination As Any Ptr, _
        ByVal source As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
#ifdef SQLITE_ENABLE_EXPLAIN_COMMENTS
    Declare Function sqlite3VdbeCoreVMPrintf CDecl Alias "sqlite3VMPrintf" ( _
        ByVal db As sqlite3 Ptr, _
        ByVal zFormat As Const ZString Ptr, _
        ByRef args As Cva_List _
    ) As ZString Ptr
#endif
End Extern

' The opcode builder can keep running after OOM because callers inspect db->mallocFailed.
Dim Shared sqlite3VdbeDummyOp As SqliteVdbeOp

Private Type SqliteReusableSpace
    pSpace As UByte Ptr
    nFree As sqlite3_int64
    nNeeded As sqlite3_int64
End Type

Private Function allocSpace CDecl Alias "allocSpace" ( _
    ByVal pSpace As SqliteReusableSpace Ptr, _
    ByVal pBuffer As Any Ptr, _
    ByVal nByteRequested As sqlite3_int64 _
) As Any Ptr
    If pSpace = 0 OrElse nByteRequested < 0 Then Return 0
#ifdef SQLITE_DEBUG
    If pSpace->pSpace = 0 OrElse _
       (CULngInt(CPtr(Any Ptr, pSpace->pSpace)) And 7ULL) <> 0 Then _
        sqlite3DebugAssert(StrPtr("reusable VDBE space is eight-byte aligned"))
#endif

    If pBuffer = 0 Then
        If nByteRequested > &H7FFFFFFFFFFFFFF8LL Then
            pSpace->nNeeded = &H7FFFFFFFFFFFFFFFLL
            Return 0
        End If
        Dim nByte As sqlite3_int64 = (nByteRequested + 7LL) And Not 7LL
        If nByte <= pSpace->nFree Then
            pSpace->nFree -= nByte
            pBuffer = @pSpace->pSpace[CLngInt(pSpace->nFree)]
        ElseIf pSpace->nNeeded > &H7FFFFFFFFFFFFFFFLL - nByte Then
            pSpace->nNeeded = &H7FFFFFFFFFFFFFFFLL
        Else
            pSpace->nNeeded += nByte
        End If
    End If

#ifdef SQLITE_DEBUG
    If pBuffer <> 0 AndAlso _
       (CULngInt(pBuffer) And 7ULL) <> 0 Then _
        sqlite3DebugAssert(StrPtr("VDBE auxiliary storage is eight-byte aligned"))
#endif
    Return pBuffer
End Function

Private Sub freeEphemeralFunction( _
    ByVal db As sqlite3 Ptr, _
    ByVal pFunction As SqliteFuncDef Ptr _
)
    If db = 0 OrElse pFunction = 0 Then Exit Sub
    If (pFunction->funcFlags And SQLITE_FUNC_EPHEM) <> 0 Then _
        sqlite3DbNNFreeNN(db, pFunction)
End Sub

Private Sub freeP4Mem( _
    ByVal db As sqlite3 Ptr, _
    ByVal pMem As SqliteVdbeMem Ptr _
)
    If db = 0 OrElse pMem = 0 Then Exit Sub
    If pMem->szMalloc <> 0 Then sqlite3DbFree(db, pMem->zMalloc)
    sqlite3DbNNFreeNN(db, pMem)
End Sub

Private Sub freeP4FuncCtx( _
    ByVal db As sqlite3 Ptr, _
    ByVal pContext As SqliteResultContext Ptr _
)
    If db = 0 OrElse pContext = 0 Then Exit Sub
    freeEphemeralFunction(db, CPtr(SqliteFuncDef Ptr, pContext->pFunc))
    sqlite3DbNNFreeNN(db, pContext)
End Sub

Sub freeP4( _
    ByVal db As sqlite3 Ptr, _
    ByVal p4Type As SQLITE_C_INT, _
    ByVal p4 As Any Ptr _
)
    If db = 0 OrElse p4 = 0 Then Return
    Select Case p4Type
    Case P4_DYNAMIC, P4_INTARRAY
        sqlite3DbFree(db, p4)
    Case P4_FUNCDEF
        freeEphemeralFunction(db, CPtr(SqliteFuncDef Ptr, p4))
    Case P4_KEYINFO
        If db->pnBytesFreed = 0 Then _
            sqlite3KeyInfoUnref(CPtr(sqlite3VdbeKeyInfoPrefix Ptr, p4))
#ifdef SQLITE_ENABLE_CURSOR_HINTS
    Case P4_EXPR
        sqlite3ExprDelete(db, p4)
#endif
    Case P4_MEM
        Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, p4)
        If db->pnBytesFreed <> 0 Then
            freeP4Mem(db, pMem)
        Else
            sqlite3ValueFree(p4)
        End If
    Case P4_FUNCCTX
        freeP4FuncCtx(db, CPtr(SqliteResultContext Ptr, p4))
    Case P4_SUBRTNSIG
        Dim pSignature As SqliteSubroutineSignature Ptr = _
            CPtr(SqliteSubroutineSignature Ptr, p4)
        sqlite3DbFree(db, pSignature->zAff)
        sqlite3DbFree(db, pSignature)
    End Select
End Sub

Type SqliteAuxDataDeleteProc As Sub CDecl (ByVal pData As Any Ptr)

Sub sqlite3VdbeDeleteAuxData CDecl Alias "sqlite3VdbeDeleteAuxData" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal ppAux As SqliteVdbeAuxData Ptr Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal argumentMask As SQLITE_C_INT _
) Export
    If db = 0 OrElse ppAux = 0 Then Return
    While ppAux[0] <> 0
        Dim pAux As SqliteVdbeAuxData Ptr = ppAux[0]
        Dim deleteEntry As SQLITE_C_INT = CInt(opcode < 0)
        If deleteEntry = 0 AndAlso pAux->iAuxOp = opcode AndAlso _
           pAux->iAuxArg >= 0 Then
            If pAux->iAuxArg > 31 Then
                deleteEntry = -1
            Else
                deleteEntry = CInt((CUInt(argumentMask) And _
                    (CULng(1) Shl pAux->iAuxArg)) = 0)
            End If
        End If

        If deleteEntry <> 0 Then
            If pAux->xDeleteAux <> 0 Then
                Dim xDelete As SqliteAuxDataDeleteProc = _
                    CPtr(SqliteAuxDataDeleteProc, pAux->xDeleteAux)
                xDelete(pAux->pAux)
            End If
            ppAux[0] = CPtr(SqliteVdbeAuxData Ptr, pAux->pNextAux)
            sqlite3DbFree(db, pAux)
        Else
            ppAux = @pAux->pNextAux
        End If
    Wend
End Sub

/' ------------------------------------------------------------------------- '/
/' VDBE statement state helpers                                             '/
/' ------------------------------------------------------------------------- '/

Sub sqlite3VdbeCountChanges CDecl Alias "sqlite3VdbeCountChanges" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) Export
    If pVdbe = 0 Then Return
    pVdbe->vdbeFlags Or= VDBE_CHANGECOUNT_MASK
End Sub

Sub sqlite3ExpirePreparedStatements CDecl Alias "sqlite3ExpirePreparedStatements" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal expirationCode As SQLITE_C_INT _
) Export
    If db = 0 Then Return
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, db->pVdbe)
    While pVdbe <> 0
        Dim expiredValue As ULong = CUInt((CLngInt(expirationCode) + 1) And VDBE_EXPIRED_MASK)
        pVdbe->vdbeFlags = (pVdbe->vdbeFlags And Not VDBE_EXPIRED_MASK) Or expiredValue
        pVdbe = CPtr(SqliteVdbe Ptr, pVdbe->pVNext)
    Wend
End Sub

Function sqlite3VdbeHasSubProgram CDecl Alias "sqlite3VdbeHasSubProgram" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT Export
    If pVdbe = 0 Then Return 0
    Return CInt(pVdbe->pProgram <> 0)
End Function

Sub sqlite3VdbeResetStepResult CDecl Alias "sqlite3VdbeResetStepResult" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) Export
    If pVdbe = 0 Then Return
    pVdbe->rc = SQLITE_OK
End Sub

Function sqlite3VdbeDb CDecl Alias "sqlite3VdbeDb" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As sqlite3 Ptr Export
    If pVdbe = 0 Then Return 0
    Return pVdbe->db
End Function

Function sqlite3VdbePrepareFlags CDecl Alias "sqlite3VdbePrepareFlags" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As u8 Export
    If pVdbe = 0 Then Return 0
    Return pVdbe->prepFlags
End Function

/' ------------------------------------------------------------------------- '/
/' Main-database dependency tracking                                        '/
/' ------------------------------------------------------------------------- '/

Sub sqlite3VdbeUsesBtree CDecl Alias "sqlite3VdbeUsesBtree" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal databaseIndex As SQLITE_C_INT _
) Export
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse databaseIndex < 0 OrElse _
       databaseIndex >= pVdbe->db->nDb Then Return
    Dim pBtree As Btree Ptr = CPtr( _
        Btree Ptr, pVdbe->db->aDb(databaseIndex).pBt)
    If pBtree = 0 Then Return

#if SQLITE_MAX_ATTACHED > 30
    Dim maskByteIndex As SQLITE_C_INT = databaseIndex \ 8
    Dim maskBit As u8 = CByte(1 Shl (databaseIndex And 7))
    pVdbe->btreeMask(maskByteIndex) Or= maskBit
    If databaseIndex <> 1 AndAlso sqlite3BtreeSharable(pBtree) <> 0 Then _
        pVdbe->lockMask(maskByteIndex) Or= maskBit
#else
    Dim maskBit As u32 = CUInt(1) Shl databaseIndex
    pVdbe->btreeMask Or= maskBit
    If databaseIndex <> 1 AndAlso sqlite3BtreeSharable(pBtree) <> 0 Then _
        pVdbe->lockMask Or= maskBit
#endif
End Sub

#ifdef SQLITE_DEBUG
Private Function opIterNext CDecl Alias "opIterNext" ( _
    ByVal pIterator As SqliteVdbeOpIter Ptr _
) As SqliteVdbeOp Ptr
    If pIterator = 0 OrElse pIterator->pVdbe = 0 Then Return 0

    Dim pVdbe As SqliteVdbe Ptr = pIterator->pVdbe
    If pIterator->iSub > pIterator->nSub Then Return 0

    Dim pOps As SqliteVdbeOp Ptr
    Dim opCount As SQLITE_C_INT
    If pIterator->iSub = 0 Then
        pOps = pVdbe->aOp
        opCount = pVdbe->nOp
    Else
        Dim pSubProgram As SqliteVdbeSubProgram Ptr = _
            pIterator->apSub[pIterator->iSub - 1]
        If pSubProgram = 0 Then Return 0
        pOps = pSubProgram->aOp
        opCount = pSubProgram->nOp
    End If

    If pIterator->iAddr >= opCount OrElse pOps = 0 Then Return 0
    Dim pResult As SqliteVdbeOp Ptr = @pOps[pIterator->iAddr]
    pIterator->iAddr += 1
    If pIterator->iAddr = opCount Then
        pIterator->iSub += 1
        pIterator->iAddr = 0
    End If

    If pResult->p4type = P4_SUBPROGRAM Then
        Dim pProgram As SqliteVdbeSubProgram Ptr = _
            CPtr(SqliteVdbeSubProgram Ptr, pResult->p4.p)
        If pProgram = 0 Then Return 0

        Dim subIndex As SQLITE_C_INT = 0
        While subIndex < pIterator->nSub
            If pIterator->apSub[subIndex] = pProgram Then Exit While
            subIndex += 1
        Wend
        If subIndex = pIterator->nSub Then
            Dim allocationBytes As sqlite3_uint64 = _
                (CULngInt(pIterator->nSub) + 1) * _
                SizeOf(SqliteVdbeSubProgram Ptr)
            pIterator->apSub = CPtr(SqliteVdbeSubProgram Ptr Ptr, _
                sqlite3DbReallocOrFree(pVdbe->db, pIterator->apSub, allocationBytes))
            If pIterator->apSub = 0 Then Return 0
            pIterator->apSub[pIterator->nSub] = pProgram
            pIterator->nSub += 1
        End If
    End If
    Return pResult
End Function

/' Scan the main program and every distinct P4 subprogram once. '/
Function sqlite3VdbeAssertMayAbort CDecl Alias "sqlite3VdbeAssertMayAbort" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal mayAbort As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pVdbe = 0 OrElse pVdbe->db = 0 Then Return 0

    Dim iterator As SqliteVdbeOpIter
    iterator.pVdbe = pVdbe
    iterator.apSub = 0
    iterator.nSub = 0
    iterator.iAddr = 0
    iterator.iSub = 0

    Dim hasAbort As SQLITE_C_INT = 0
    Dim hasFkCounter As SQLITE_C_INT = 0
    Dim hasCreateTable As SQLITE_C_INT = 0
    Dim hasCreateIndex As SQLITE_C_INT = 0
    Dim hasInitCoroutine As SQLITE_C_INT = 0
    Dim pOp As SqliteVdbeOp Ptr = opIterNext(@iterator)

    While pOp <> 0
        Dim opcode As SQLITE_C_INT = pOp->opcode
        If opcode = OP_Destroy OrElse opcode = OP_VUpdate OrElse _
           opcode = OP_VRename OrElse opcode = OP_VDestroy OrElse _
           opcode = OP_VCreate OrElse opcode = OP_ParseSchema OrElse _
           opcode = OP_Function OrElse opcode = OP_PureFunc OrElse _
           ((opcode = OP_Halt OrElse opcode = OP_HaltIfNull) AndAlso _
            pOp->p1 <> SQLITE_OK AndAlso pOp->p2 = OE_ABORT) OrElse _
           (opcode = OP_MustBeInt AndAlso pOp->p2 = 0) Then
            hasAbort = 1
            Exit While
        End If

        If opcode = OP_CreateBtree AndAlso pOp->p3 = BTREE_INTKEY Then _
            hasCreateTable = 1
        If mayAbort <> 0 Then
            If opcode = OP_CreateBtree AndAlso pOp->p3 = BTREE_BLOBKEY Then _
                hasCreateIndex = 1
            If opcode = OP_Clear Then hasCreateIndex = 1
        End If
        If opcode = OP_InitCoroutine Then hasInitCoroutine = 1
#ifndef SQLITE_OMIT_FOREIGN_KEY
        If opcode = OP_FkCounter AndAlso pOp->p1 = 0 AndAlso pOp->p2 = 1 Then _
            hasFkCounter = 1
#endif
        pOp = opIterNext(@iterator)
    Wend

    sqlite3DbFree(pVdbe->db, iterator.apSub)
    If pVdbe->db->mallocFailed <> 0 OrElse hasAbort = mayAbort OrElse _
       hasFkCounter <> 0 OrElse (hasCreateTable <> 0 AndAlso hasInitCoroutine <> 0) OrElse _
       hasCreateIndex <> 0 Then Return 1
    Return 0
End Function

/' VDBE write operations that can abort require a statement journal. '/
Sub sqlite3VdbeAssertAbortable CDecl Alias "sqlite3VdbeAssertAbortable" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) Export
    If pVdbe = 0 Then Return
    ASSERT(pVdbe->nWrite = 0 OrElse _
           (pVdbe->vdbeFlags And VDBE_USES_STMT_JOURNAL_MASK) <> 0)
End Sub

#ifndef SQLITE_TEST_REALLOC_STRESS
/' Ensure reserved opcode space covers a fixed sequence of future appends. '/
Sub sqlite3VdbeVerifyNoMallocRequired CDecl Alias "sqlite3VdbeVerifyNoMallocRequired" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal additionalOpCount As SQLITE_C_INT _
) Export
    If pVdbe = 0 Then Return
    ASSERT(additionalOpCount >= 0 AndAlso _
           pVdbe->nOp + additionalOpCount <= pVdbe->nOpAlloc)
End Sub

/' Certain PRAGMA programs must not emit rows. '/
Sub sqlite3VdbeVerifyNoResultRow CDecl Alias "sqlite3VdbeVerifyNoResultRow" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) Export
    If pVdbe = 0 Then Return
    If pVdbe->nOp = 0 Then Return
    ASSERT(pVdbe->aOp <> 0)
    If pVdbe->aOp = 0 Then Return
    For iOp As SQLITE_C_INT = 0 To pVdbe->nOp - 1
        ASSERT(pVdbe->aOp[iOp].opcode <> OP_ResultRow)
    Next
End Sub
#endif

/' Emit OP_Abortable where compiler error handling requires an abort check. '/
Sub sqlite3VdbeVerifyAbortable CDecl Alias "sqlite3VdbeVerifyAbortable" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal errorAction As SQLITE_C_INT _
) Export
    If pVdbe = 0 Then Return
    If errorAction = OE_ABORT Then sqlite3VdbeAddOp0(pVdbe, OP_Abortable)
End Sub
#endif

Sub sqlite3MayAbort CDecl Alias "sqlite3MayAbort" (ByVal pParseArgument As Any Ptr) Export
    If pParseArgument = 0 Then Return
    Dim pParse As SqliteParseContext Ptr = _
        CPtr(SqliteParseContext Ptr, pParseArgument)
    Dim pTopLevel As SqliteParseContext Ptr = pParse
    If pParse->pToplevel <> 0 Then pTopLevel = pParse->pToplevel

    ' Trigger subprograms share the parent statement's abort journal.
    pTopLevel->mayAbort = 1
End Sub

Sub sqlite3VdbeAddParseSchemaOp CDecl Alias "sqlite3VdbeAddParseSchemaOp" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal databaseIndex As SQLITE_C_INT, _
    ByVal zWhere As ZString Ptr, _
    ByVal p5 As u16 _
) Export
    If pVdbe = 0 OrElse pVdbe->db = 0 Then Return
    If p5 <> 0 AndAlso zWhere <> 0 Then
        sqlite3DbFree(pVdbe->db, zWhere)
        Return
    End If
    If databaseIndex < 0 OrElse databaseIndex >= pVdbe->db->nDb Then
        sqlite3DbFree(pVdbe->db, zWhere)
        Return
    End If

    sqlite3VdbeAddOp4(pVdbe, OP_ParseSchema, databaseIndex, 0, 0, zWhere, P4_DYNAMIC)
    sqlite3VdbeChangeP5(pVdbe, p5)
    For usedDatabaseIndex As SQLITE_C_INT = 0 To pVdbe->db->nDb - 1
        sqlite3VdbeUsesBtree(pVdbe, usedDatabaseIndex)
    Next
    sqlite3MayAbort(pVdbe->pParse)
End Sub

Sub sqlite3VdbeEndCoroutine CDecl Alias "sqlite3VdbeEndCoroutine" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal yieldRegister As SQLITE_C_INT _
) Export
    If pVdbe = 0 Then Return
    sqlite3VdbeAddOp1(pVdbe, OP_EndCoroutine, yieldRegister)
    If pVdbe->pParse = 0 Then Return
    Dim pParse As SqliteParseContext Ptr = CPtr(SqliteParseContext Ptr, pVdbe->pParse)
    pParse->nTempReg = 0
    pParse->nRangeReg = 0
End Sub

Function sqlite3VdbeCreate CDecl Alias "sqlite3VdbeCreate" ( _
    ByVal pParseArgument As Any Ptr _
) As Any Ptr Export
    If pParseArgument = 0 Then Return 0
    Dim pParse As SqliteParseContext Ptr = CPtr(SqliteParseContext Ptr, pParseArgument)
    If pParse->db = 0 Then Return 0

    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, _
        sqlite3DbMallocZero(pParse->db, SizeOf(SqliteVdbe)))
    If pVdbe = 0 Then Return 0
    pVdbe->db = pParse->db
    pVdbe->pParse = pParseArgument
    pVdbe->eVdbeState = VDBE_INIT_STATE

    Dim pOldFirst As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pParse->db->pVdbe)
    If pOldFirst <> 0 Then pOldFirst->ppVPrev = @pVdbe->pVNext
    pVdbe->pVNext = pParse->db->pVdbe
    pVdbe->ppVPrev = @pParse->db->pVdbe
    pParse->db->pVdbe = pVdbe
    pParse->pVdbe = pVdbe

    sqlite3VdbeAddOp2(pVdbe, OP_Init, 0, 1)
    If pParse->db->mallocFailed <> 0 Then
        sqlite3VdbeDelete(pVdbe)
        Return 0
    End If
    Return pVdbe
End Function

/' ------------------------------------------------------------------------- '/
/' Statement metadata and literal opcodes                                    '/
/' ------------------------------------------------------------------------- '/

Function sqlite3VdbeParser CDecl Alias "sqlite3VdbeParser" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As Any Ptr Export
    If pVdbe = 0 Then Return 0
    Return pVdbe->pParse
End Function

Sub sqlite3VdbeRewind CDecl Alias "sqlite3VdbeRewind" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) Export
    If pVdbe = 0 OrElse pVdbe->nOp <= 0 Then Return
    If pVdbe->eVdbeState <> VDBE_INIT_STATE AndAlso _
       pVdbe->eVdbeState <> VDBE_READY_STATE AndAlso _
       pVdbe->eVdbeState <> VDBE_HALT_STATE Then Return

    pVdbe->eVdbeState = VDBE_READY_STATE
    pVdbe->pc = -1
    pVdbe->rc = SQLITE_OK
    pVdbe->errorAction = OE_ABORT
    pVdbe->nChange = 0
    pVdbe->cacheCtr = 1
    pVdbe->minWriteFileFormat = 255
    pVdbe->iStatement = 0
    pVdbe->nFkConstraint = 0
#if defined(VDBE_PROFILE)
    For iOp As SQLITE_C_INT = 0 To pVdbe->nOp - 1
        pVdbe->aOp[iOp].nExec = 0
        pVdbe->aOp[iOp].nCycle = 0
    Next
#endif
End Sub

Sub sqlite3VdbeMakeReady CDecl Alias "sqlite3VdbeMakeReady" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pParseArgument As Any Ptr _
) Export
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse pParseArgument = 0 Then Return
    If pVdbe->eVdbeState <> VDBE_INIT_STATE OrElse pVdbe->nOp <= 0 Then Return

    Dim pParse As SqliteParseContext Ptr = CPtr(SqliteParseContext Ptr, pParseArgument)
    If pParse->db <> pVdbe->db OrElse pParse->pVdbe <> pVdbe Then Return
    If pVdbe->aOp = 0 OrElse pVdbe->nOpAlloc < pVdbe->nOp Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("VDBE opcode allocation covers all instructions"))
#endif
        pVdbe->rc = SQLITE_CORRUPT
        pVdbe->db->errorCode = SQLITE_CORRUPT
        Return
    End If
    If pVdbe->db->mallocFailed <> 0 Then
        pVdbe->rc = SQLITE_NOMEM
        Return
    End If

    Dim nVar As SQLITE_C_INT = pParse->nVar
    Dim nMem As SQLITE_C_INT = pParse->nMem
    Dim nCursor As SQLITE_C_INT = pParse->nTab
    Dim nArg As SQLITE_C_INT = pParse->nMaxArg
#if SQLITE_MAX_VARIABLE_NUMBER < 32767
    If nVar > SQLITE_MAX_VARIABLE_NUMBER Then
        pVdbe->rc = SQLITE_TOOBIG
        pVdbe->db->errorCode = SQLITE_TOOBIG
        Return
    End If
#endif
    If nVar < 0 OrElse nMem < 0 OrElse nCursor < 0 OrElse nArg < 0 OrElse _
       nCursor > SQLITE_MAX_VDBE_OP - nMem OrElse _
       nVar > SQLITE_MAX_VDBE_OP OrElse nArg > SQLITE_MAX_VDBE_OP Then
        sqlite3OomFault(pVdbe->db)
        pVdbe->rc = SQLITE_NOMEM
        Return
    End If

    ' VFilter and VUpdate add arguments to apArg beyond SQL bind parameters.
    Dim resolveCode As SQLITE_C_INT = _
        sqlite3VdbeResolveP2Values(pVdbe, @nArg)
    If resolveCode <> SQLITE_OK Then
        If pParse->aLabel <> 0 Then sqlite3DbFree(pVdbe->db, pParse->aLabel)
        pParse->aLabel = 0
        pParse->nLabel = 0
        pParse->nLabelAlloc = 0
        pVdbe->rc = resolveCode
        pVdbe->db->errorCode = resolveCode
        Return
    End If

    nMem += nCursor
    If nCursor = 0 AndAlso nMem > 0 Then nMem += 1
    If pParse->explain <> 0 Then
        If pParse->explain < 0 OrElse pParse->explain > 2 Then
            pVdbe->rc = SQLITE_MISUSE
            Return
        End If
        If nMem < 10 Then nMem = 10
        pVdbe->vdbeFlags = (pVdbe->vdbeFlags And Not VDBE_EXPLAIN_MASK) Or _
                           (CULng(pParse->explain) Shl VDBE_EXPLAIN_SHIFT)
        pVdbe->nResColumn = CUShort(12 - 4 * pParse->explain)
    End If
    If pParse->isMultiWrite <> 0 AndAlso pParse->mayAbort <> 0 Then _
        pVdbe->vdbeFlags Or= VDBE_USES_STMT_JOURNAL_MASK
    pVdbe->vdbeFlags = pVdbe->vdbeFlags And Not VDBE_EXPIRED_MASK
    pVdbe->vdbeFlags = (pVdbe->vdbeFlags And _
        Not (VDBE_READONLY_MASK Or VDBE_BISREADER_MASK)) Or VDBE_READONLY_MASK
    For iOp As SQLITE_C_INT = 0 To pVdbe->nOp - 1
        Select Case pVdbe->aOp[iOp].opcode
        Case OP_Transaction
            pVdbe->vdbeFlags Or= VDBE_BISREADER_MASK
            If pVdbe->aOp[iOp].p2 <> 0 Then _
                pVdbe->vdbeFlags = pVdbe->vdbeFlags And Not VDBE_READONLY_MASK
        Case OP_Savepoint, OP_AutoCommit
            pVdbe->vdbeFlags Or= VDBE_BISREADER_MASK
        Case OP_Checkpoint, OP_Vacuum, OP_JournalMode
            pVdbe->vdbeFlags = pVdbe->vdbeFlags And Not VDBE_READONLY_MASK
            pVdbe->vdbeFlags Or= VDBE_BISREADER_MASK
        End Select
    Next
    pVdbe->vdbeFlags = (pVdbe->vdbeFlags And _
        Not (VDBE_READONLY_MASK Or VDBE_BISREADER_MASK)) Or VDBE_READONLY_MASK
    For iOp As SQLITE_C_INT = 0 To pVdbe->nOp - 1
        Select Case pVdbe->aOp[iOp].opcode
        Case OP_Transaction
            pVdbe->vdbeFlags Or= VDBE_BISREADER_MASK
            If pVdbe->aOp[iOp].p2 <> 0 Then _
                pVdbe->vdbeFlags = pVdbe->vdbeFlags And Not VDBE_READONLY_MASK
        Case OP_Savepoint, OP_AutoCommit
            pVdbe->vdbeFlags Or= VDBE_BISREADER_MASK
        Case OP_Checkpoint, OP_Vacuum, OP_JournalMode
            pVdbe->vdbeFlags = pVdbe->vdbeFlags And Not VDBE_READONLY_MASK
            pVdbe->vdbeFlags Or= VDBE_BISREADER_MASK
        End Select
    Next

    Dim aMemBytes As sqlite3_uint64 = CULngInt(nMem) * SizeOf(SqliteVdbeMem)
    Dim aVarBytes As sqlite3_uint64 = CULngInt(nVar) * SizeOf(SqliteVdbeMem)
    Dim apArgBytes As sqlite3_uint64 = CULngInt(nArg) * SizeOf(Any Ptr)
    Dim apCsrBytes As sqlite3_uint64 = CULngInt(nCursor) * SizeOf(Any Ptr)
    If aMemBytes > SQLITE_MAX_ALLOCATION_SIZE OrElse _
       aVarBytes > SQLITE_MAX_ALLOCATION_SIZE OrElse _
       apArgBytes > SQLITE_MAX_ALLOCATION_SIZE OrElse _
       apCsrBytes > SQLITE_MAX_ALLOCATION_SIZE Then
        sqlite3OomFault(pVdbe->db)
        pVdbe->rc = SQLITE_NOMEM
        Return
    End If

    pVdbe->pVList = pParse->pVList
    pParse->pVList = 0

    ' Reuse the unused opcode allocation tail before requesting another block.
    Dim reusable As SqliteReusableSpace
    reusable.nNeeded = 0
    reusable.pSpace = CPtr(UByte Ptr, pVdbe->aOp)
    reusable.nFree = 0
    If pVdbe->aOp <> 0 AndAlso pVdbe->nOpAlloc >= pVdbe->nOp Then
        Dim nUsedBytes As sqlite3_uint64 = _
            CULngInt(pVdbe->nOp) * SizeOf(SqliteVdbeOp)
        Dim nOpcodeBytes As sqlite3_uint64 = _
            CULngInt(pVdbe->nOpAlloc) * SizeOf(SqliteVdbeOp)
        Dim nAlignedUsedBytes As sqlite3_uint64 = _
            (nUsedBytes + 7ULL) And Not 7ULL
        If nAlignedUsedBytes <= nOpcodeBytes Then
            reusable.pSpace = CPtr(UByte Ptr, pVdbe->aOp) + nAlignedUsedBytes
            reusable.nFree = _
                (nOpcodeBytes - nAlignedUsedBytes) And Not 7ULL
        End If
    End If
    pVdbe->aMem = CPtr(SqliteVdbeMem Ptr, _
        allocSpace(@reusable, pVdbe->aMem, CLngInt(aMemBytes)))
    pVdbe->aVar = CPtr(SqliteVdbeMem Ptr, _
        allocSpace(@reusable, pVdbe->aVar, CLngInt(aVarBytes)))
    pVdbe->apArg = CPtr(SqliteVdbeMem Ptr Ptr, _
        allocSpace(@reusable, pVdbe->apArg, CLngInt(apArgBytes)))
    pVdbe->apCsr = CPtr(Any Ptr Ptr, _
        allocSpace(@reusable, pVdbe->apCsr, CLngInt(apCsrBytes)))

    ' Keep all allocations that did not fit in the opcode tail in one block.
    If reusable.nNeeded > 0 Then
        Dim nPoolBytes As sqlite3_uint64 = CULngInt(reusable.nNeeded)
        If nPoolBytes > SQLITE_MAX_ALLOCATION_SIZE Then
            sqlite3OomFault(pVdbe->db)
        Else
            Dim pPoolBlock As UByte Ptr = CPtr(UByte Ptr, _
                sqlite3DbMallocRawNN(pVdbe->db, nPoolBytes))
            If pPoolBlock <> 0 Then
                pVdbe->pFree = pPoolBlock
                reusable.pSpace = pPoolBlock
                reusable.nFree = CLngInt(nPoolBytes)
                reusable.nNeeded = 0
                pVdbe->aMem = CPtr(SqliteVdbeMem Ptr, _
                    allocSpace(@reusable, pVdbe->aMem, CLngInt(aMemBytes)))
                pVdbe->aVar = CPtr(SqliteVdbeMem Ptr, _
                    allocSpace(@reusable, pVdbe->aVar, CLngInt(aVarBytes)))
                pVdbe->apArg = CPtr(SqliteVdbeMem Ptr Ptr, _
                    allocSpace(@reusable, pVdbe->apArg, CLngInt(apArgBytes)))
                pVdbe->apCsr = CPtr(Any Ptr Ptr, _
                    allocSpace(@reusable, pVdbe->apCsr, CLngInt(apCsrBytes)))
            End If
        End If
    End If
    If pVdbe->db->mallocFailed <> 0 OrElse _
       (aMemBytes > 0 AndAlso pVdbe->aMem = 0) OrElse _
       (aVarBytes > 0 AndAlso pVdbe->aVar = 0) OrElse _
       (apArgBytes > 0 AndAlso pVdbe->apArg = 0) OrElse _
       (apCsrBytes > 0 AndAlso pVdbe->apCsr = 0) Then
        pVdbe->rc = SQLITE_NOMEM
        Return
    End If

    For iMem As SQLITE_C_INT = 0 To nMem - 1
        sqlite3VdbeMemInit(@pVdbe->aMem[iMem], pVdbe->db, MEM_UNDEFINED)
    Next
    For iVar As SQLITE_C_INT = 0 To nVar - 1
        sqlite3VdbeMemInit(@pVdbe->aVar[iVar], pVdbe->db, MEM_NULL)
    Next
    ' apCsr may occupy leftover opcode-array memory, so it must not retain
    ' the bytecode bytes that were stored there before this allocation.
    For iCursor As SQLITE_C_INT = 0 To nCursor - 1
        pVdbe->apCsr[iCursor] = 0
    Next
    pVdbe->nMem = nMem
    pVdbe->nCursor = nCursor
    pVdbe->nArg = nArg
    pVdbe->nVar = CInt(nVar)
#ifdef SQLITE_DEBUG
    pVdbe->napArg = nArg
#endif

    sqlite3VdbeRewind(pVdbe)
End Sub

Sub sqlite3VdbeSetSql CDecl Alias "sqlite3VdbeSetSql" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal zSql As Const ZString Ptr, _
    ByVal nSql As SQLITE_C_INT, _
    ByVal prepFlags As u8 _
) Export
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse nSql < 0 Then Return
    If pVdbe->zSql <> 0 Then Return
    If zSql = 0 AndAlso nSql <> 0 Then Return

    pVdbe->prepFlags = prepFlags
    If (prepFlags And SQLITE_PREPARE_SAVESQL) = 0 Then pVdbe->expmask = 0
    pVdbe->zSql = CPtr(ZString Ptr, sqlite3DbStrNDup( _
        pVdbe->db, zSql, CULngInt(nSql)))
End Sub

Private Function sqlite3VdbeSignedIntFromBits(ByVal valueBits As ULongInt) As SQLITE_C_INT
    If valueBits > &H7FFFFFFF Then
        Return CInt(CLngInt(valueBits) - 4294967296LL)
    End If
    Return CInt(valueBits)
End Function

Function sqlite3VdbeAddInt64 CDecl Alias "sqlite3VdbeAddInt64" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal destinationRegister As SQLITE_C_INT, _
    ByVal value As sqlite3_int64 _
) As SQLITE_C_INT Export
    Dim valueBits As ULongInt = CULngInt(value)
    Dim lowWord As SQLITE_C_INT = sqlite3VdbeSignedIntFromBits(valueBits And &HFFFFFFFFULL)
    Dim highWord As SQLITE_C_INT = sqlite3VdbeSignedIntFromBits(valueBits Shr 32)
    Return sqlite3VdbeAddOp3(pVdbe, OP_Int64, lowWord, destinationRegister, highWord)
End Function

Function sqlite3VdbeAddDouble CDecl Alias "sqlite3VdbeAddDouble" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal destinationRegister As SQLITE_C_INT, _
    ByVal value As Double _
) As SQLITE_C_INT Export
    Dim valueBits As ULongInt = 0
    sqlite3VdbeCoreMemcpy(@valueBits, @value, SizeOf(valueBits))
    Dim lowWord As SQLITE_C_INT = sqlite3VdbeSignedIntFromBits(valueBits And &HFFFFFFFFULL)
    Dim highWord As SQLITE_C_INT = sqlite3VdbeSignedIntFromBits(valueBits Shr 32)
    Return sqlite3VdbeAddOp3(pVdbe, OP_Real, lowWord, destinationRegister, highWord)
End Function

Function sqlite3VdbeGoto CDecl Alias "sqlite3VdbeGoto" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal destinationAddress As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Return sqlite3VdbeAddOp3(pVdbe, OP_Goto, 0, destinationAddress, 0)
End Function

Function sqlite3VdbeLoadString CDecl Alias "sqlite3VdbeLoadString" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal destinationRegister As SQLITE_C_INT, _
    ByVal zText As Const ZString Ptr _
) As SQLITE_C_INT Export
    Return sqlite3VdbeAddOp4(pVdbe, OP_String8, 0, destinationRegister, 0, zText, 0)
End Function

Private Sub vdbeFreeOpArray( _
    ByVal db As sqlite3 Ptr, _
    ByVal pOperations As SqliteVdbeOp Ptr, _
    ByVal operationCount As SQLITE_C_INT _
)
    If db = 0 OrElse pOperations = 0 Then Exit Sub
    If operationCount < 0 Then Exit Sub
    Dim iOperation As SQLITE_C_INT = operationCount
    While iOperation > 0
        iOperation -= 1
        If pOperations[iOperation].p4type <= P4_FREE_IF_LE Then
            freeP4( _
                db, pOperations[iOperation].p4type, pOperations[iOperation].p4.p)
        End If
#if defined(SQLITE_ENABLE_EXPLAIN_COMMENTS)
        If pOperations[iOperation].zComment <> 0 Then _
            sqlite3DbFree(db, pOperations[iOperation].zComment)
#endif
    Wend
    sqlite3DbNNFreeNN(db, pOperations)
End Sub

Private Sub releaseMemArray( _
    ByVal pMemory As SqliteVdbeMem Ptr, _
    ByVal count As SQLITE_C_INT _
)
    If pMemory = 0 OrElse count <= 0 Then Exit Sub
    Dim db As sqlite3 Ptr = pMemory->db
    If db = 0 Then Exit Sub

    If db->pnBytesFreed <> 0 Then
        For iMemory As SQLITE_C_INT = 0 To count - 1
            If pMemory[iMemory].szMalloc <> 0 Then _
                sqlite3DbFree(db, pMemory[iMemory].zMalloc)
        Next
        Exit Sub
    End If

    For iMemory As SQLITE_C_INT = 0 To count - 1
        sqlite3VdbeMemRelease(@pMemory[iMemory])
        pMemory[iMemory].flags = MEM_UNDEFINED
    Next
End Sub

Sub sqlite3VdbeDelete CDecl Alias "sqlite3VdbeDelete" ( _
    ByVal pVdbeArgument As Any Ptr _
) Export
    If pVdbeArgument = 0 Then Return
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pVdbeArgument)
    Dim db As sqlite3 Ptr = pVdbe->db
    If db = 0 Then Return

    If db->pnBytesFreed = 0 Then
        sqlite3VdbeDeleteAuxData(db, @pVdbe->pAuxData, -1, 0)
    Else
        Dim pAux As SqliteVdbeAuxData Ptr = pVdbe->pAuxData
        While pAux <> 0
            Dim pNextAux As SqliteVdbeAuxData Ptr = _
                CPtr(SqliteVdbeAuxData Ptr, pAux->pNextAux)
            sqlite3DbFree(db, pAux)
            pAux = pNextAux
        Wend
    End If

    If db->pnBytesFreed = 0 AndAlso _
       db->pParse = pVdbe->pParse AndAlso pVdbe->pParse <> 0 Then
        Dim pParse As SqliteParseContext Ptr = CPtr(SqliteParseContext Ptr, pVdbe->pParse)
        If pParse->pVdbe = pVdbe Then pParse->pVdbe = 0
    End If
    Dim pSubProgram As SqliteVdbeSubProgram Ptr = _
        CPtr(SqliteVdbeSubProgram Ptr, pVdbe->pProgram)
    While pSubProgram <> 0
        Dim pNextSubProgram As SqliteVdbeSubProgram Ptr = _
            CPtr(SqliteVdbeSubProgram Ptr, pSubProgram->pNext)
        vdbeFreeOpArray(db, pSubProgram->aOp, pSubProgram->nOp)
        sqlite3DbFree(db, pSubProgram)
        pSubProgram = pNextSubProgram
    Wend
    ' The execution arrays are slices of aOp or pFree. Release owned Mem
    ' payloads before freeing either backing block, never as separate arrays.
    If pVdbe->apCsr <> 0 AndAlso db->pnBytesFreed = 0 Then
        For iCursor As SQLITE_C_INT = 0 To pVdbe->nCursor - 1
            If pVdbe->apCsr[iCursor] <> 0 Then
                Dim pCursor As SqliteVdbeCursor Ptr = _
                    CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[iCursor])
                sqlite3VdbeFreeCursorNN(pVdbe, pCursor)
                pVdbe->apCsr[iCursor] = 0
            End If
        Next
    End If
    If pVdbe->aMem <> 0 Then
        releaseMemArray(pVdbe->aMem, pVdbe->nMem)
    End If
    If pVdbe->aVar <> 0 Then
        releaseMemArray(pVdbe->aVar, pVdbe->nVar)
    End If
    If pVdbe->aColName <> 0 Then
        Dim nColumnNames As SQLITE_C_INT = CLng(pVdbe->nResAlloc) * COLNAME_N
        releaseMemArray(pVdbe->aColName, nColumnNames)
        sqlite3DbFree(db, pVdbe->aColName)
    End If
    If pVdbe->pVList <> 0 Then sqlite3DbFree(db, pVdbe->pVList)
    If pVdbe->zErrMsg <> 0 Then sqlite3DbFree(db, pVdbe->zErrMsg)
    If pVdbe->zSql <> 0 Then sqlite3DbFree(db, pVdbe->zSql)
#ifdef SQLITE_ENABLE_NORMALIZE
    If pVdbe->zNormSql <> 0 Then sqlite3DbFree(db, pVdbe->zNormSql)
    Dim pDblquote As SqliteDblquoteStr Ptr = pVdbe->pDblStr
    While pDblquote <> 0
        Dim pNextDblquote As SqliteDblquoteStr Ptr = pDblquote->pNextStr
        sqlite3DbFree(db, pDblquote)
        pDblquote = pNextDblquote
    Wend
#endif
    If pVdbe->pFree <> 0 Then sqlite3DbFree(db, pVdbe->pFree)
    vdbeFreeOpArray(db, pVdbe->aOp, pVdbe->nOp)
    If db->pnBytesFreed = 0 Then
        If pVdbe->ppVPrev <> 0 Then _
            CPtr(Any Ptr Ptr, pVdbe->ppVPrev)[0] = pVdbe->pVNext
        If pVdbe->pVNext <> 0 Then _
            CPtr(SqliteVdbe Ptr, pVdbe->pVNext)->ppVPrev = pVdbe->ppVPrev
    End If
    sqlite3DbNNFreeNN(db, pVdbe)
End Sub

/' Link a subprogram so deleting its VDBE reclaims the owned bytecode. '/
Sub sqlite3VdbeLinkSubProgram CDecl Alias "sqlite3VdbeLinkSubProgram" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pSubProgram As SqliteVdbeSubProgram Ptr _
) Export
    If pVdbe = 0 OrElse pSubProgram = 0 Then Return
    pSubProgram->pNext = pVdbe->pProgram
    pVdbe->pProgram = pSubProgram
End Sub

Private Function sqlite3VdbeGrowOpArray( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal additionalOps As SQLITE_C_INT _
) As SQLITE_C_INT
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse additionalOps <= 0 Then Return SQLITE_MISUSE
    If pVdbe->nOpAlloc < pVdbe->nOp OrElse _
       pVdbe->nOp > SQLITE_MAX_VDBE_OP - additionalOps Then
        sqlite3OomFault(pVdbe->db)
        Return SQLITE_NOMEM
    End If

    Dim requiredCount As sqlite3_uint64 = CULngInt(pVdbe->nOp) + additionalOps
    Dim newCount As sqlite3_uint64
    If pVdbe->nOpAlloc = 0 Then
        newCount = 1024 \ SizeOf(SqliteVdbeOp)
    Else
        newCount = CULngInt(pVdbe->nOpAlloc) * 2
    End If
    If newCount < requiredCount Then newCount = requiredCount

    If newCount > CULngInt(pVdbe->db->aLimit(SQLITE_LIMIT_VDBE_OP)) Then
        sqlite3OomFault(pVdbe->db)
        Return SQLITE_NOMEM
    End If

    Dim allocationLimit As sqlite3_uint64 = SQLITE_MAX_ALLOCATION_SIZE \ SizeOf(SqliteVdbeOp)
    If newCount > SQLITE_MAX_VDBE_OP OrElse newCount > allocationLimit Then
        sqlite3OomFault(pVdbe->db)
        Return SQLITE_NOMEM
    End If

    Dim allocationBytes As sqlite3_uint64 = newCount * SizeOf(SqliteVdbeOp)
    Dim pNewOps As SqliteVdbeOp Ptr = CPtr(SqliteVdbeOp Ptr, _
        sqlite3DbRealloc(pVdbe->db, pVdbe->aOp, allocationBytes))
    If pNewOps = 0 Then Return SQLITE_NOMEM

    Dim allocatedBytes As SQLITE_C_INT = sqlite3DbMallocSize(pVdbe->db, pNewOps)
    Dim allocatedCount As sqlite3_uint64 = newCount
    If allocatedBytes > 0 Then allocatedCount = CULngInt(allocatedBytes) \ SizeOf(SqliteVdbeOp)
    If allocatedCount < requiredCount OrElse allocatedCount > SQLITE_MAX_VDBE_OP Then
        pVdbe->aOp = pNewOps
        pVdbe->nOpAlloc = CInt(allocatedCount)
        sqlite3OomFault(pVdbe->db)
        Return SQLITE_NOMEM
    End If

    pVdbe->aOp = pNewOps
    pVdbe->nOpAlloc = CInt(allocatedCount)
    Return SQLITE_OK
End Function

Private Function sqlite3VdbeGrowAndAddOp3( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal p1 As SQLITE_C_INT, _
    ByVal p2 As SQLITE_C_INT, _
    ByVal p3 As SQLITE_C_INT _
) As SQLITE_C_INT
    If sqlite3VdbeGrowOpArray(pVdbe, 1) <> SQLITE_OK Then Return 1
    Return sqlite3VdbeAddOp3(pVdbe, opcode, p1, p2, p3)
End Function

Function sqlite3VdbeAddOp0 CDecl Alias "sqlite3VdbeAddOp0" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal opcode As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Return sqlite3VdbeAddOp3(pVdbe, opcode, 0, 0, 0)
End Function

Function sqlite3VdbeAddOp1 CDecl Alias "sqlite3VdbeAddOp1" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal p1 As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Return sqlite3VdbeAddOp3(pVdbe, opcode, p1, 0, 0)
End Function

Function sqlite3VdbeAddOp2 CDecl Alias "sqlite3VdbeAddOp2" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal p1 As SQLITE_C_INT, _
    ByVal p2 As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Return sqlite3VdbeAddOp3(pVdbe, opcode, p1, p2, 0)
End Function

Function sqlite3VdbeAddOp3 CDecl Alias "sqlite3VdbeAddOp3" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal p1 As SQLITE_C_INT, _
    ByVal p2 As SQLITE_C_INT, _
    ByVal p3 As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pVdbe = 0 OrElse pVdbe->db = 0 Then Return 0
    If pVdbe->eVdbeState <> VDBE_INIT_STATE OrElse opcode < 0 OrElse opcode >= &HFF Then Return 0
    If pVdbe->nOp >= pVdbe->db->aLimit(SQLITE_LIMIT_VDBE_OP) Then
        sqlite3OomFault(pVdbe->db)
        Return 1
    End If
    If pVdbe->nOp < 0 OrElse pVdbe->nOp >= SQLITE_MAX_VDBE_OP Then
        sqlite3OomFault(pVdbe->db)
        Return 1
    End If

    Dim address As SQLITE_C_INT = pVdbe->nOp
    If pVdbe->nOpAlloc <= address Then
        Return sqlite3VdbeGrowAndAddOp3(pVdbe, opcode, p1, p2, p3)
    End If
    If pVdbe->aOp = 0 Then Return 0

    Dim pOp As SqliteVdbeOp Ptr = @pVdbe->aOp[address]
    pVdbe->nOp += 1
    pOp->opcode = CByte(opcode)
    pOp->p5 = 0
    pOp->p1 = p1
    pOp->p2 = p2
    pOp->p3 = p3
    pOp->p4.p = 0
    pOp->p4type = P4_NOTUSED
#ifdef SQLITE_ENABLE_EXPLAIN_COMMENTS
    pOp->zComment = 0
#endif
#if defined(SQLITE_ENABLE_STMT_SCANSTATUS) OrElse defined(VDBE_PROFILE)
    pOp->nExec = 0
    pOp->nCycle = 0
#endif
#ifdef SQLITE_VDBE_COVERAGE
    pOp->iSrcLine = 0
#endif
    Return address
End Function

Function sqlite3VdbeAddOp4Int CDecl Alias "sqlite3VdbeAddOp4Int" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal p1 As SQLITE_C_INT, _
    ByVal p2 As SQLITE_C_INT, _
    ByVal p3 As SQLITE_C_INT, _
    ByVal p4 As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pVdbe = 0 OrElse pVdbe->db = 0 Then Return 0
    Dim oldCount As SQLITE_C_INT = pVdbe->nOp
    Dim address As SQLITE_C_INT = sqlite3VdbeAddOp3(pVdbe, opcode, p1, p2, p3)
    If pVdbe->db->mallocFailed <> 0 OrElse pVdbe->nOp <> oldCount + 1 OrElse _
       address < 0 OrElse address >= pVdbe->nOp Then Return address
    pVdbe->aOp[address].p4.i = p4
    pVdbe->aOp[address].p4type = P4_INT32
    Return address
End Function

Function sqlite3VdbeAddFunctionCall CDecl Alias "sqlite3VdbeAddFunctionCall" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal constantMask As SQLITE_C_INT, _
    ByVal firstArgumentRegister As SQLITE_C_INT, _
    ByVal outputRegister As SQLITE_C_INT, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pFunction As Const SqliteFuncDef Ptr, _
    ByVal callContext As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pParse = 0 OrElse pParse->db = 0 OrElse pParse->pVdbe = 0 OrElse _
       pFunction = 0 OrElse pFunction->xSFunc = 0 OrElse _
       argumentCount < 0 OrElse argumentCount > &HFFFF OrElse _
       outputRegister <= 0 OrElse outputRegister > pParse->nMem Then Return 0
    If argumentCount = 0 Then
        If firstArgumentRegister <> 0 Then Return 0
    ElseIf firstArgumentRegister <= 0 OrElse _
           firstArgumentRegister > pParse->nMem - argumentCount + 1 Then
        Return 0
    End If

    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pParse->pVdbe)
    Dim fixedBytes As sqlite3_uint64 = _
        SizeOf(SqliteResultContext) - SizeOf(SqliteVdbeMem Ptr)
    Dim allocatedArgumentCount As SQLITE_C_INT = argumentCount
    If allocatedArgumentCount = 0 Then allocatedArgumentCount = 1
    Dim argumentBytes As sqlite3_uint64 = _
        CULngInt(allocatedArgumentCount) * SizeOf(SqliteVdbeMem Ptr)
    If argumentBytes > SQLITE_MAX_ALLOCATION_SIZE - fixedBytes Then
        sqlite3OomFault(pParse->db)
        Return 0
    End If
    Dim pContext As SqliteResultContext Ptr = _
        CPtr(SqliteResultContext Ptr, sqlite3DbMallocZero( _
            pParse->db, fixedBytes + argumentBytes))
    If pContext = 0 Then Return 0
    pContext->pFunc = CPtr(Any Ptr, pFunction)
    pContext->iOp = pVdbe->nOp
    pContext->argc = CUShort(argumentCount)
    pContext->enc = SQLITE_UTF8

    Dim functionOpcode As SQLITE_C_INT = _
        IIf(callContext <> 0, OP_PureFunc, OP_Function)
    Dim address As SQLITE_C_INT = sqlite3VdbeAddOp4( _
        pVdbe, functionOpcode, constantMask, firstArgumentRegister, outputRegister, _
        CPtr(Const ZString Ptr, pContext), P4_FUNCCTX)
    If callContext <> 0 Then sqlite3VdbeChangeP5(pVdbe, CUShort(callContext And 1))
    sqlite3MayAbort(pParse)
    Return address
End Function

Function sqlite3VdbeAddOpList CDecl Alias "sqlite3VdbeAddOpList" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal opCount As SQLITE_C_INT, _
    ByVal pOpList As Const SqliteVdbeOpList Ptr, _
    ByVal firstLine As SQLITE_C_INT _
) As SqliteVdbeOp Ptr Export
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse pOpList = 0 OrElse opCount <= 0 Then Return 0
    If pVdbe->eVdbeState <> VDBE_INIT_STATE OrElse pVdbe->nOp < 0 OrElse _
       pVdbe->nOpAlloc < pVdbe->nOp Then Return 0
    Dim runtimeLimit As SQLITE_C_INT = pVdbe->db->aLimit(SQLITE_LIMIT_VDBE_OP)
    If pVdbe->nOp > runtimeLimit OrElse _
       opCount > runtimeLimit - pVdbe->nOp OrElse _
       opCount > SQLITE_MAX_VDBE_OP - pVdbe->nOp Then
        sqlite3OomFault(pVdbe->db)
        Return 0
    End If

    For iOp As SQLITE_C_INT = 0 To opCount - 1
        Dim opcode As SQLITE_C_INT = pOpList[iOp].opcode
        If opcode < 0 OrElse opcode >= SQLITE_OPCODE_COUNT Then Return 0
        If sqlite3OpcodeProperty(opcode) <> 0 AndAlso pOpList[iOp].p2 > 0 AndAlso _
           pOpList[iOp].p2 > SQLITE_MAX_VDBE_OP - pVdbe->nOp Then Return 0
    Next

#ifdef SQLITE_VDBE_COVERAGE
    If firstLine < 0 OrElse firstLine > &H7FFFFFFF - opCount Then Return 0
#endif

    If pVdbe->nOpAlloc - pVdbe->nOp < opCount Then
        If sqlite3VdbeGrowOpArray(pVdbe, opCount) <> SQLITE_OK Then Return 0
    End If
    If pVdbe->aOp = 0 Then Return 0

    Dim firstAddress As SQLITE_C_INT = pVdbe->nOp
    Dim pFirst As SqliteVdbeOp Ptr = @pVdbe->aOp[firstAddress]
    For iOp As SQLITE_C_INT = 0 To opCount - 1
        Dim pOut As SqliteVdbeOp Ptr = @pVdbe->aOp[firstAddress + iOp]
        pOut->opcode = pOpList[iOp].opcode
        pOut->p1 = pOpList[iOp].p1
        pOut->p2 = pOpList[iOp].p2
        If sqlite3OpcodeProperty(pOut->opcode) <> 0 AndAlso pOut->p2 > 0 Then _
            pOut->p2 += firstAddress
        pOut->p3 = pOpList[iOp].p3
        pOut->p4type = P4_NOTUSED
        pOut->p4.p = 0
        pOut->p5 = 0
#ifdef SQLITE_ENABLE_EXPLAIN_COMMENTS
        pOut->zComment = 0
#endif
#ifdef SQLITE_VDBE_COVERAGE
        pOut->iSrcLine = CUInt(firstLine + iOp)
#endif
#if defined(SQLITE_ENABLE_STMT_SCANSTATUS) OrElse defined(VDBE_PROFILE)
        pOut->nExec = 0
        pOut->nCycle = 0
#endif
    Next
    pVdbe->nOp = firstAddress + opCount
    Return pFirst
End Function

Function sqlite3VdbeAddOp4 CDecl Alias "sqlite3VdbeAddOp4" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal p1 As SQLITE_C_INT, _
    ByVal p2 As SQLITE_C_INT, _
    ByVal p3 As SQLITE_C_INT, _
    ByVal zP4 As Const ZString Ptr, _
    ByVal p4Type As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Dim address As SQLITE_C_INT = sqlite3VdbeAddOp3(pVdbe, opcode, p1, p2, p3)
    sqlite3VdbeChangeP4(pVdbe, address, zP4, p4Type)
    Return address
End Function

Sub sqlite3VdbeChangeP4 CDecl Alias "sqlite3VdbeChangeP4" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal address As SQLITE_C_INT, _
    ByVal zP4 As Const ZString Ptr, _
    ByVal p4Type As SQLITE_C_INT _
) Export
    If pVdbe = 0 OrElse pVdbe->db = 0 Then Return
    If pVdbe->db->mallocFailed <> 0 Then
        If p4Type < P4_FREE_IF_LE Then _
            freeP4(pVdbe->db, CByte(p4Type), CPtr(Any Ptr, zP4))
        Return
    End If
    If address < 0 Then address = pVdbe->nOp - 1
    If address < 0 OrElse address >= pVdbe->nOp OrElse pVdbe->aOp = 0 Then Return

    Dim pOp As SqliteVdbeOp Ptr = @pVdbe->aOp[address]
    If pOp->p4type <> P4_NOTUSED Then
        freeP4(pVdbe->db, pOp->p4type, pOp->p4.p)
        pOp->p4type = P4_NOTUSED
        pOp->p4.p = 0
    End If

    If p4Type >= 0 Then
        If p4Type = 0 Then
            pOp->p4.z = CPtr(ZString Ptr, sqlite3DbStrDup(pVdbe->db, zP4))
        Else
            pOp->p4.z = CPtr(ZString Ptr, sqlite3DbStrNDup( _
                pVdbe->db, zP4, CULngInt(p4Type)))
        End If
        pOp->p4type = P4_DYNAMIC
    ElseIf p4Type = P4_INT32 Then
        pOp->p4.i = CInt(CULngInt(zP4) And &HFFFFFFFF)
        pOp->p4type = P4_INT32
    ElseIf zP4 <> 0 OrElse p4Type = P4_DYNAMIC Then
        pOp->p4.p = CPtr(Any Ptr, zP4)
        pOp->p4type = CByte(p4Type)
    End If
End Sub

Sub sqlite3VdbeAppendP4 CDecl Alias "sqlite3VdbeAppendP4" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pP4 As Any Ptr, _
    ByVal p4Type As SQLITE_C_INT _
) Export
    If pVdbe = 0 OrElse pVdbe->db = 0 Then Return
    If pVdbe->db->mallocFailed <> 0 OrElse pVdbe->nOp <= 0 OrElse pVdbe->aOp = 0 Then
        freeP4(pVdbe->db, CByte(p4Type), pP4)
        Return
    End If
    If p4Type = P4_INT32 OrElse p4Type = P4_VTAB OrElse p4Type > P4_NOTUSED OrElse _
       pVdbe->aOp[pVdbe->nOp - 1].p4type <> P4_NOTUSED Then
        freeP4(pVdbe->db, CByte(p4Type), pP4)
        Return
    End If
    If pP4 = 0 AndAlso p4Type <> P4_DYNAMIC Then Return
    pVdbe->aOp[pVdbe->nOp - 1].p4.p = pP4
    pVdbe->aOp[pVdbe->nOp - 1].p4type = CByte(p4Type)
End Sub

Function sqlite3VdbeCurrentAddr CDecl Alias "sqlite3VdbeCurrentAddr" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT Export
    If pVdbe = 0 Then Return 0
    Return pVdbe->nOp
End Function

Function sqlite3VdbeGetOp CDecl Alias "sqlite3VdbeGetOp" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal address As SQLITE_C_INT _
) As SqliteVdbeOp Ptr Export
    If pVdbe = 0 OrElse pVdbe->db = 0 Then Return @sqlite3VdbeDummyOp
    If pVdbe->db->mallocFailed <> 0 Then Return @sqlite3VdbeDummyOp
    If pVdbe->aOp = 0 OrElse address < 0 OrElse address >= pVdbe->nOp Then
        Return @sqlite3VdbeDummyOp
    End If
    Return @pVdbe->aOp[address]
End Function

Function sqlite3VdbeGetLastOp CDecl Alias "sqlite3VdbeGetLastOp" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SqliteVdbeOp Ptr Export
    If pVdbe = 0 Then Return @sqlite3VdbeDummyOp
    Return sqlite3VdbeGetOp(pVdbe, pVdbe->nOp - 1)
End Function

Sub sqlite3VdbeChangeOpcode CDecl Alias "sqlite3VdbeChangeOpcode" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal address As SQLITE_C_INT, _
    ByVal opcode As u8 _
) Export
    If pVdbe = 0 OrElse pVdbe->aOp = 0 OrElse address < 0 OrElse _
       address >= pVdbe->nOp OrElse pVdbe->db = 0 Then Return
    If pVdbe->db->mallocFailed <> 0 Then Return
    pVdbe->aOp[address].opcode = opcode
End Sub

Private Function sqlite3VdbeAddressIsValid( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal address As SQLITE_C_INT _
) As SQLITE_C_INT
    If pVdbe = 0 OrElse pVdbe->aOp = 0 OrElse address < 0 OrElse address >= pVdbe->nOp Then Return 0
    Return 1
End Function

Sub sqlite3VdbeChangeP1 CDecl Alias "sqlite3VdbeChangeP1" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal address As SQLITE_C_INT, _
    ByVal value As SQLITE_C_INT _
) Export
    If sqlite3VdbeAddressIsValid(pVdbe, address) = 0 Then Return
    pVdbe->aOp[address].p1 = value
End Sub

Sub sqlite3VdbeChangeP2 CDecl Alias "sqlite3VdbeChangeP2" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal address As SQLITE_C_INT, _
    ByVal value As SQLITE_C_INT _
) Export
    If sqlite3VdbeAddressIsValid(pVdbe, address) = 0 Then Return
    pVdbe->aOp[address].p2 = value
End Sub

Sub sqlite3VdbeChangeP3 CDecl Alias "sqlite3VdbeChangeP3" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal address As SQLITE_C_INT, _
    ByVal value As SQLITE_C_INT _
) Export
    If sqlite3VdbeAddressIsValid(pVdbe, address) = 0 Then Return
    pVdbe->aOp[address].p3 = value
End Sub

Sub sqlite3VdbeChangeP5 CDecl Alias "sqlite3VdbeChangeP5" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal value As u16 _
) Export
    If pVdbe = 0 OrElse pVdbe->nOp <= 0 OrElse pVdbe->aOp = 0 Then Return
    pVdbe->aOp[pVdbe->nOp - 1].p5 = value
End Sub

Sub sqlite3VdbeSetNumCols CDecl Alias "sqlite3VdbeSetNumCols" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal resultColumnCount As SQLITE_C_INT _
) Export
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse resultColumnCount < 0 Then Return
    If resultColumnCount > 65535 OrElse _
       resultColumnCount > SQLITE_MAX_ALLOCATION_SIZE / _
           (SizeOf(SqliteVdbeMem) * COLNAME_N) Then
        sqlite3OomFault(pVdbe->db)
        Return
    End If

    If pVdbe->aColName <> 0 Then
        Dim oldNameCount As SQLITE_C_INT = CLng(pVdbe->nResAlloc) * COLNAME_N
        For iName As SQLITE_C_INT = 0 To oldNameCount - 1
            sqlite3VdbeMemRelease(@pVdbe->aColName[iName])
        Next
        sqlite3DbFree(pVdbe->db, pVdbe->aColName)
        pVdbe->aColName = 0
    End If

    pVdbe->nResColumn = CUShort(resultColumnCount)
    pVdbe->nResAlloc = CUShort(resultColumnCount)
    If resultColumnCount = 0 Then Return

    Dim nNameCells As SQLITE_C_INT = resultColumnCount * COLNAME_N
    Dim allocationBytes As sqlite3_uint64 = _
        CULngInt(nNameCells) * SizeOf(SqliteVdbeMem)
    pVdbe->aColName = CPtr(SqliteVdbeMem Ptr, _
        sqlite3DbMallocRawNN(pVdbe->db, allocationBytes))
    If pVdbe->aColName = 0 Then Return
    For iName As SQLITE_C_INT = 0 To nNameCells - 1
        sqlite3VdbeMemInit(@pVdbe->aColName[iName], pVdbe->db, MEM_NULL)
    Next
End Sub

Function sqlite3VdbeSetColName CDecl Alias "sqlite3VdbeSetColName" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal columnIndex As SQLITE_C_INT, _
    ByVal nameType As SQLITE_C_INT, _
    ByVal zName As Const ZString Ptr, _
    ByVal xDestructor As Any Ptr _
) As SQLITE_C_INT Export
    If pVdbe = 0 OrElse pVdbe->db = 0 Then Return SQLITE_MISUSE
    If columnIndex < 0 OrElse columnIndex >= pVdbe->nResAlloc OrElse _
       nameType < 0 OrElse nameType >= COLNAME_N Then Return SQLITE_RANGE
    If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pVdbe->aColName = 0 Then Return SQLITE_MISUSE

    Dim nameCellIndex As SQLITE_C_INT = _
        columnIndex + nameType * pVdbe->nResAlloc
    Dim xDelete As sqlite3MemDestructor = CPtr(sqlite3MemDestructor, xDestructor)
    Return sqlite3VdbeMemSetText( _
        @pVdbe->aColName[nameCellIndex], zName, -1, xDelete)
End Function

Sub sqlite3VdbeTypeofColumn CDecl Alias "sqlite3VdbeTypeofColumn" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal destinationRegister As SQLITE_C_INT _
) Export
    If pVdbe = 0 OrElse pVdbe->nOp <= 0 OrElse pVdbe->aOp = 0 Then Return
    Dim opIndex As SQLITE_C_INT = pVdbe->nOp - 1
#ifdef SQLITE_DEBUG
    While opIndex > 0 AndAlso pVdbe->aOp[opIndex].opcode = OP_ReleaseReg
        opIndex -= 1
    Wend
#endif
    If pVdbe->aOp[opIndex].p3 = destinationRegister AndAlso _
       pVdbe->aOp[opIndex].opcode = OP_Column Then
        pVdbe->aOp[opIndex].p5 Or= OPFLAG_TYPEOFARG
    End If
End Sub

Sub sqlite3VdbeJumpHere CDecl Alias "sqlite3VdbeJumpHere" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal address As SQLITE_C_INT _
) Export
    If pVdbe = 0 Then Return
    sqlite3VdbeChangeP2(pVdbe, address, pVdbe->nOp)
End Sub

Function sqlite3VdbeMakeLabel CDecl Alias "sqlite3VdbeMakeLabel" ( _
    ByVal pParseArgument As Any Ptr _
) As SQLITE_C_INT
    If pParseArgument = 0 Then Return 0
    Dim pParse As SqliteParseContext Ptr = CPtr(SqliteParseContext Ptr, pParseArgument)
    If pParse->db = 0 Then Return 0
    If pParse->nLabel <= -SQLITE_MAX_VDBE_OP Then
        sqlite3OomFault(pParse->db)
        Return 0
    End If
    pParse->nLabel -= 1
    Return pParse->nLabel
End Function

Private Sub sqlite3VdbeGrowLabelArray(ByVal pParse As SqliteParseContext Ptr)
    If pParse = 0 OrElse pParse->db = 0 Then Return
    Dim newSize As SQLITE_C_INT = 25 - pParse->nLabel
    If newSize <= pParse->nLabelAlloc OrElse newSize > SQLITE_MAX_VDBE_OP Then
        sqlite3OomFault(pParse->db)
        Return
    End If
    Dim oldSize As SQLITE_C_INT = pParse->nLabelAlloc
    Dim allocationBytes As sqlite3_uint64 = CULngInt(newSize) * SizeOf(SQLITE_C_INT)
    Dim pNewLabels As SQLITE_C_INT Ptr = CPtr(SQLITE_C_INT Ptr, _
        sqlite3DbRealloc(pParse->db, pParse->aLabel, allocationBytes))
    If pNewLabels = 0 Then Return
    pParse->aLabel = pNewLabels
    For iLabel As Long = oldSize To newSize - 1
        pParse->aLabel[iLabel] = -1
    Next
    pParse->nLabelAlloc = newSize
End Sub

Sub sqlite3VdbeResolveLabel CDecl Alias "sqlite3VdbeResolveLabel" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal labelValue As SQLITE_C_INT _
)
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse pVdbe->pParse = 0 OrElse _
       pVdbe->eVdbeState <> VDBE_INIT_STATE OrElse labelValue >= 0 Then Return
    Dim pParse As SqliteParseContext Ptr = CPtr(SqliteParseContext Ptr, pVdbe->pParse)
    Dim labelIndex As SQLITE_C_INT = Not labelValue
    If labelIndex < 0 OrElse labelIndex >= -pParse->nLabel Then Return

    If pParse->nLabelAlloc + pParse->nLabel < 0 Then sqlite3VdbeGrowLabelArray(pParse)
    If pParse->db->mallocFailed <> 0 OrElse pParse->aLabel = 0 OrElse _
       labelIndex >= pParse->nLabelAlloc Then Return
    If pParse->aLabel[labelIndex] <> -1 Then Return
    pParse->aLabel[labelIndex] = pVdbe->nOp
End Sub

Function sqlite3VdbeResolveP2Labels( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse pVdbe->aOp = 0 OrElse pVdbe->nOp <= 0 Then
        Return SQLITE_MISUSE
    End If
    If pVdbe->db->mallocFailed <> 0 Then Return SQLITE_NOMEM
    If pVdbe->pParse = 0 Then Return SQLITE_OK

    Dim pParse As SqliteParseContext Ptr = CPtr(SqliteParseContext Ptr, pVdbe->pParse)
    Dim labelCount As SQLITE_C_INT = -pParse->nLabel
    ' Code generation may issue labels that no jump references. A missing
    ' label array is only an error when a negative jump operand needs it.
    If pParse->nLabel > 0 OrElse _
       pParse->nLabel < -SQLITE_MAX_VDBE_OP OrElse _
       pParse->nLabelAlloc < 0 OrElse _
       pParse->nLabelAlloc > SQLITE_MAX_VDBE_OP Then
        Return SQLITE_CORRUPT
    End If

    For iOp As SQLITE_C_INT = 0 To pVdbe->nOp - 1
        If pVdbe->aOp[iOp].p2 < 0 Then
            Dim opcode As SQLITE_C_INT = pVdbe->aOp[iOp].opcode
            If opcode < 0 OrElse opcode >= SQLITE_OPCODE_COUNT Then _
                Return SQLITE_CORRUPT
            ' Negative P2 is also a valid immediate operand for non-jump opcodes.
            If (sqlite3OpcodeProperty(opcode) And OPFLG_JUMP) <> 0 Then
                Dim labelIndex As SQLITE_C_INT = Not pVdbe->aOp[iOp].p2
                If labelIndex < 0 OrElse labelIndex >= labelCount OrElse _
                   labelIndex >= pParse->nLabelAlloc OrElse _
                   pParse->aLabel = 0 Then Return SQLITE_CORRUPT
                Dim resolvedAddress As SQLITE_C_INT = pParse->aLabel[labelIndex]
                If resolvedAddress < 0 OrElse _
                   resolvedAddress > pVdbe->nOp Then Return SQLITE_CORRUPT
                pVdbe->aOp[iOp].p2 = resolvedAddress
            End If
        End If
    Next

    If pParse->aLabel <> 0 Then sqlite3DbFree(pVdbe->db, pParse->aLabel)
    pParse->aLabel = 0
    pParse->nLabel = 0
    pParse->nLabelAlloc = 0
    Return SQLITE_OK
End Function

Sub sqlite3VdbeRunOnlyOnce CDecl Alias "sqlite3VdbeRunOnlyOnce" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
    If pVdbe = 0 Then Return
    sqlite3VdbeAddOp2(pVdbe, OP_Expire, 1, 1)
End Sub

Sub sqlite3VdbeReusable CDecl Alias "sqlite3VdbeReusable" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
    If pVdbe = 0 OrElse pVdbe->aOp = 0 Then Return
    For iOp As SQLITE_C_INT = 1 To pVdbe->nOp - 1
        If pVdbe->aOp[iOp].opcode = OP_Expire Then
            pVdbe->aOp[1].opcode = OP_Noop
            Exit For
        End If
    Next
End Sub

Function sqlite3VdbeChangeToNoop CDecl Alias "sqlite3VdbeChangeToNoop" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal address As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse pVdbe->db->mallocFailed <> 0 OrElse _
       sqlite3VdbeAddressIsValid(pVdbe, address) = 0 Then Return 0
    Dim pOp As SqliteVdbeOp Ptr = @pVdbe->aOp[address]
    freeP4(pVdbe->db, pOp->p4type, pOp->p4.p)
    pOp->p4type = P4_NOTUSED
    pOp->p4.p = 0
    pOp->opcode = OP_Noop
    Return 1
End Function

Function sqlite3VdbeDeletePriorOpcode CDecl Alias "sqlite3VdbeDeletePriorOpcode" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal opcode As u8 _
) As SQLITE_C_INT Export
    If pVdbe = 0 OrElse pVdbe->nOp <= 0 OrElse pVdbe->aOp = 0 Then Return 0
    Dim lastAddress As SQLITE_C_INT = pVdbe->nOp - 1
    If pVdbe->aOp[lastAddress].opcode <> opcode Then Return 0
    Return sqlite3VdbeChangeToNoop(pVdbe, lastAddress)
End Function

/' ------------------------------------------------------------------------- '/
/' Explain comments and debug SQL output                                    '/
/' ------------------------------------------------------------------------- '/

#ifdef SQLITE_ENABLE_EXPLAIN_COMMENTS
Private Sub vdbeVComment CDecl Alias "vdbeVComment" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ByRef args As Cva_List _
)
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse zFormat = 0 OrElse _
       pVdbe->nOp <= 0 OrElse pVdbe->aOp = 0 Then Exit Sub

    Dim pOp As SqliteVdbeOp Ptr = @pVdbe->aOp[pVdbe->nOp - 1]
    If pOp = 0 Then Exit Sub
    If pOp->zComment <> 0 Then sqlite3DbFree(pVdbe->db, pOp->zComment)
    pOp->zComment = sqlite3VdbeCoreVMPrintf(pVdbe->db, zFormat, args)
End Sub

Sub sqlite3VdbeComment CDecl Alias "sqlite3VdbeComment" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
    If pVdbe = 0 Then Exit Sub
    Dim args As Cva_List
    Cva_Start(args, zFormat)
    vdbeVComment(pVdbe, zFormat, args)
    Cva_End(args)
End Sub

Sub sqlite3VdbeNoopComment CDecl Alias "sqlite3VdbeNoopComment" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
    If pVdbe = 0 Then Exit Sub
    sqlite3VdbeAddOp0(pVdbe, OP_Noop)
    Dim args As Cva_List
    Cva_Start(args, zFormat)
    vdbeVComment(pVdbe, zFormat, args)
    Cva_End(args)
End Sub
#endif

#ifdef SQLITE_DEBUG
Sub sqlite3VdbePrintSql CDecl Alias "sqlite3VdbePrintSql" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
    If pVdbe = 0 Then Exit Sub

    Dim zSql As Const ZString Ptr = pVdbe->zSql
    If zSql = 0 AndAlso pVdbe->nOp > 0 AndAlso pVdbe->aOp <> 0 Then
        Dim pOp As SqliteVdbeOp Ptr = @pVdbe->aOp[0]
        If pOp->opcode = OP_Init AndAlso pOp->p4.z <> 0 Then
            zSql = pOp->p4.z
            Dim pByte As Const UByte Ptr = CPtr(Const UByte Ptr, zSql)
            While (sqlite3CtypeMap(pByte[0]) And &H01) <> 0
                pByte += 1
            Wend
            zSql = CPtr(Const ZString Ptr, pByte)
        End If
    End If
    If zSql <> 0 Then _
        sqlite3VdbeDebugPrintf(StrPtr(!"SQL: [%s]\n"), zSql)
End Sub
#endif


#ifdef SQLITE_DEBUG
/' This debug guard detects branches that leave a VDBE subroutine. '/
Sub sqlite3VdbeNoJumpsOutsideSubrtn CDecl Alias "sqlite3VdbeNoJumpsOutsideSubrtn" (ByVal arg0 As SqliteVdbe Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
    Dim local0 As SqliteVdbeOp Ptr
    Dim local1 As SqliteParseContext Ptr
    Dim local2 As SQLITE_C_INT
    Dim local3 As sqlite3_str Ptr
    Dim c2fb_temp_0 As SqliteParseContext Ptr
    Dim c2fb_temp_1 As SqliteVdbeOp Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SqliteVdbeOp Ptr
    Dim local4 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim local6 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim local7 As SqliteVdbeOp Ptr
    Dim c2fb_temp_7 As sqlite3_str Ptr
    Dim local8 As ZString Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local3 = Cast(SQLITE_C_INT, &O0ULL)
    ' C unused-parameter annotation
    If arg0 = 0 Then
        sqlite3DebugAssert(StrPtr("v != 0"))
        Exit Sub
    End If
    c2fb_temp_0 = CPtr(SqliteParseContext Ptr, arg0->pParse)
    local1 = c2fb_temp_0
    ' C unused-parameter annotation
    If local1 = 0 Then
        sqlite3DebugAssert(StrPtr("pParse != 0"))
        Exit Sub
    End If
    If local1->nErr Then
        Return
    End If
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If arg1 < 0 Then
        sqlite3DebugAssert(StrPtr("iFirst >= 0"))
        Exit Sub
    End If
    If arg2 < arg1 Then
        sqlite3DebugAssert(StrPtr("iLast >= iFirst"))
        Exit Sub
    End If
    If arg2 >= arg0->nOp Then
        sqlite3DebugAssert(StrPtr("iLast < v->nOp"))
        Exit Sub
    End If
    c2fb_temp_1 = CPtr(SqliteVdbeOp Ptr, @(arg0->aOp[arg1]))
    local0 = c2fb_temp_1
    c2fb_temp_2 = Cast(SQLITE_C_INT, arg1)
    local2 = c2fb_temp_2
    While (-Cast(SQLITE_C_INT, ((local2 <= arg2))))
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, sqlite3OpcodeProperty(local0->opcode)) And Cast(SQLITE_C_INT, &H01ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            local4 = local0->p2
            If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                Goto c2fb_flow_1
            End If
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->opcode) = Cast(SQLITE_C_INT, 10ULL))))) Then
                Goto c2fb_flow_1
            End If
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local0->p3 = Cast(SQLITE_C_INT, 20230325ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->opcode) = Cast(SQLITE_C_INT, 52ULL))))))))) Then
                Goto c2fb_flow_1
            End If
            If (-Cast(SQLITE_C_INT, ((local4 < Cast(SQLITE_C_INT, &O0ULL))))) Then
                local5 = (Cast(SQLITE_C_INT, (Not (local4))))
                If local5 < 0 Then
                    sqlite3DebugAssert(StrPtr("ADDR(iDest) >= 0"))
                    Goto c2fb_flow_1
                End If
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local5 >= Cast(SQLITE_C_INT, (-local1->nLabel)))))) OrElse (-Cast(SQLITE_C_INT, ((local1->aLabel[local5] < Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                    Goto c2fb_flow_1
                End If
                c2fb_temp_5 = Cast(SQLITE_C_INT, local1->aLabel[local5])
                local4 = c2fb_temp_5
            End If
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local4 < arg1)))) OrElse (-Cast(SQLITE_C_INT, ((local4 > arg2)))))))) Then
                local6 = local4
                While (-Cast(SQLITE_C_INT, ((local6 < arg0->nOp))))
                    local7 = CPtr(SqliteVdbeOp Ptr, @(arg0->aOp[local6]))
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local7->opcode) = Cast(SQLITE_C_INT, 69ULL))))) Then
                        If (-Cast(SQLITE_C_INT, ((local7->p1 = arg3)))) Then
                            Goto c2fb_flow_2
                        End If
                        Goto c2fb_flow_3
                    End If
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local7->opcode) = Cast(SQLITE_C_INT, 189ULL))))) Then
                        Goto c2fb_flow_3
                    End If
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local7->opcode) = Cast(SQLITE_C_INT, 190ULL))))) Then
                        Goto c2fb_flow_3
                    End If
                    If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        c2fb_temp_7 = CPtr(sqlite3_str Ptr, sqlite3_str_new(Cast(SQLITE_C_INT, &O0ULL)))
                        local3 = c2fb_temp_7
                    Else
                        sqlite3_str_appendchar(local3, Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, 10))
                    End If
                    sqlite3VdbeCoreStrAppendf(local3, StrPtr(!"Opcode at %d jumps to %d which is outside the subroutine at %d..%d"), local2, local4, arg1, arg2)
                    Goto c2fb_flow_2
                c2fb_flow_3:
                    c2fb_temp_6 = local6
                    local6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 + 1)))
                Wend
                c2fb_flow_2:
            End If
        End If
    c2fb_flow_1:
        c2fb_temp_3 = local2
        local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_3 + 1)))
        c2fb_temp_4 = local0
        local0 = (c2fb_temp_4 + 1)
    Wend
    c2fb_flow_0:
    If local3 Then
        local8 = CPtr(ZString Ptr, sqlite3_str_finish(local3))
        sqlite3VdbeAddOp4(arg0, Cast(SQLITE_C_INT, 72ULL), Cast(SQLITE_C_INT, 2ULL), Cast(SQLITE_C_INT, 2ULL), Cast(SQLITE_C_INT, &O0ULL), CPtr(Const ZString Ptr, local8), Cast(SQLITE_C_INT, &O0ULL))
        sqlite3VdbeCoreFree(CPtr(Any Ptr, local8))
        sqlite3MayAbort(local1)
    End If
End Sub

#endif

/' end of sqlite3_vdbe_core.bas '/
