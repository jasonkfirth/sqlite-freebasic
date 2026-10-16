/'
    Project: SQLite FreeBASIC port

    File: sqlite3_build.bas

    Purpose:

        Finalize the VDBE built by a top-level parse.

    Responsibilities:

        - Check the byte-array database mask used when many databases are allowed.
        - Append the statement halt and route OP_Init to the bytecode prelude.
        - Emit schema-cookie transactions, virtual-table begins, and table locks.
        - Initialize autoincrement and factored expressions before execution.
        - Resolve the remaining builder state and allocate the ready VDBE cells.
        - Return the parse result used by the prepare layer.

    This file intentionally does NOT contain:

        - Parser semantic actions or SQL text parsing.
'/ 

#lang "fb"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_walker.bi"
#include once "sqlite3_btree.bi"

Declare Function sqlite3_stricmp CDecl Alias "sqlite3_stricmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3AutoincrementBegin CDecl Alias "sqlite3AutoincrementBegin" ( _
    ByVal pParse As SqliteParseContext Ptr _
)
Declare Sub sqlite3ExprCode CDecl Alias "sqlite3ExprCode" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal targetRegister As SQLITE_C_INT _
)
Declare Function sqlite3GetVTable CDecl Alias "sqlite3GetVTable" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pTable As Any Ptr _
) As Any Ptr

Private Function sqlite3BuildDbMaskTest( _
    ByVal maskValue As u32, _
    ByVal databaseIndex As SQLITE_C_INT _
) As SQLITE_C_INT
    If databaseIndex < 0 OrElse _
       databaseIndex >= SizeOf(maskValue) * 8 Then Return 0
    Dim bitMask As sqlite3_uint64 = &H1ULL Shl databaseIndex
    If (CULngInt(maskValue) And bitMask) <> 0 Then Return 1
    Return 0
End Function

#if SQLITE_MAX_ATTACHED > 30
Function sqlite3DbMaskAllZero CDecl Alias "sqlite3DbMaskAllZero" ( _
    ByVal pMask As UByte Ptr _
) As SQLITE_C_INT Export
    If pMask = 0 Then Return 0

    ' Main and temp use two slots; seven more bits round up to full bytes.
    Dim byteCount As SQLITE_C_INT = (SQLITE_MAX_ATTACHED + 9) \ 8
    For byteIndex As SQLITE_C_INT = 0 To byteCount - 1
        If pMask[byteIndex] <> 0 Then Return 0
    Next
    Return 1
End Function
#endif

Function sqlite3FindDbName CDecl Alias "sqlite3FindDbName" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr _
) As SQLITE_C_INT Export
    If db = 0 OrElse zName = 0 OrElse db->nDb < 0 OrElse _
       db->nDb > SQLITE_MAX_ATTACHED + 2 Then Return -1

    Dim databaseIndex As SQLITE_C_INT = db->nDb - 1
    While databaseIndex >= 0
        Dim zDatabaseName As Const ZString Ptr = _
            db->aDb(databaseIndex).zDbSName
        If zDatabaseName <> 0 AndAlso _
           sqlite3_stricmp(zName, zDatabaseName) = 0 Then Return databaseIndex
        databaseIndex -= 1
    Wend

    ' "main" remains an accepted alias even if its schema name is changed.
    If sqlite3_stricmp(zName, StrPtr("main")) = 0 AndAlso db->nDb > 0 Then _
        Return 0
    Return -1
End Function

Function sqlite3FindDb CDecl Alias "sqlite3FindDb" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pName As Const sqlite3ParserToken Ptr _
) As SQLITE_C_INT Export
    If db = 0 Then Return -1

    Dim zName As ZString Ptr = sqlite3NameFromToken(db, pName)
    Dim databaseIndex As SQLITE_C_INT = sqlite3FindDbName(db, zName)
    sqlite3DbFree(db, zName)
    Return databaseIndex
End Function

Function sqlite3DbNameToBtree CDecl Alias "sqlite3DbNameToBtree" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zDbName As Const ZString Ptr _
) As Btree Ptr Export
    If db = 0 Then Return 0

    Dim databaseIndex As SQLITE_C_INT = 0
    If zDbName <> 0 Then databaseIndex = sqlite3FindDbName(db, zDbName)
    If databaseIndex < 0 OrElse databaseIndex >= db->nDb Then Return 0
    Return CPtr(Btree Ptr, db->aDb(databaseIndex).pBt)
End Function

Sub sqlite3FinishCoding CDecl Alias "sqlite3FinishCoding" ( _
    ByVal pParseArgument As Any Ptr _
)
    If pParseArgument = 0 Then Return
    Dim pParse As SqliteParseContext Ptr = CPtr(SqliteParseContext Ptr, pParseArgument)
    Dim db As sqlite3 Ptr = pParse->db
    If db = 0 Then Return
    If pParse->nested <> 0 Then Return
    If pParse->nErr <> 0 Then
        If db->mallocFailed <> 0 Then pParse->rc = SQLITE_NOMEM
        Return
    End If
    If db->mallocFailed <> 0 Then
        pParse->rc = SQLITE_NOMEM
        Return
    End If

    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pParse->pVdbe)
    If pVdbe = 0 Then
        If db->init.busy <> 0 Then
            pParse->rc = SQLITE_DONE
            Return
        End If
        pVdbe = CPtr(SqliteVdbe Ptr, sqlite3GetVdbe(pParse))
        If pVdbe = 0 Then
            pParse->rc = IIf(db->mallocFailed <> 0, SQLITE_NOMEM, SQLITE_ERROR)
            Return
        End If
    End If

    If pParse->isMultiWrite <> 0 AndAlso pParse->mayAbort <> 0 Then
#ifdef SQLITE_DEBUG
        ASSERT(sqlite3VdbeAssertMayAbort(pVdbe, pParse->mayAbort) <> 0)
#endif
    End If

    If pParse->bReturning <> 0 Then
        Dim pReturning As SqliteReturning Ptr = _
            CPtr(SqliteReturning Ptr, pParse->u1.d.pReturning)
        If pReturning = 0 Then
            pParse->rc = SQLITE_CORRUPT
            pParse->nErr += 1
            Return
        End If
        If pReturning->nRetCol > 0 Then
            sqlite3VdbeAddOp0(pVdbe, OP_FkCheck)
            Dim addressRewind As SQLITE_C_INT = _
                sqlite3VdbeAddOp1(pVdbe, OP_Rewind, pReturning->iRetCur)
            For resultColumn As SQLITE_C_INT = 0 To pReturning->nRetCol - 1
                sqlite3VdbeAddOp3( _
                    pVdbe, OP_Column, pReturning->iRetCur, resultColumn, _
                    pReturning->iRetReg + resultColumn)
            Next
            sqlite3VdbeAddOp2( _
                pVdbe, OP_ResultRow, pReturning->iRetReg, pReturning->nRetCol)
            sqlite3VdbeAddOp2( _
                pVdbe, OP_Next, pReturning->iRetCur, addressRewind + 1)
            sqlite3VdbeJumpHere(pVdbe, addressRewind)
        End If
    End If

    sqlite3VdbeAddOp0(pVdbe, OP_Halt)
    If db->mallocFailed <> 0 OrElse pVdbe->rc <> SQLITE_OK Then
        pParse->rc = IIf(db->mallocFailed <> 0, SQLITE_NOMEM, pVdbe->rc)
        pParse->nErr += 1
        Return
    End If
    If pVdbe->nOp <= 0 OrElse pVdbe->aOp = 0 Then
        pParse->rc = SQLITE_CORRUPT
        pParse->nErr += 1
        Return
    End If
#ifdef SQLITE_DEBUG
    ASSERT(pVdbe->aOp[0].opcode = OP_Init)
#endif
    sqlite3VdbeJumpHere(pVdbe, 0)

    If db->nDb <= 0 OrElse db->nDb > SQLITE_MAX_ATTACHED + 2 Then
        pParse->rc = SQLITE_CORRUPT
        pParse->nErr += 1
        Return
    End If
    For databaseIndex As SQLITE_C_INT = 0 To db->nDb - 1
        If sqlite3BuildDbMaskTest(pParse->cookieMask, databaseIndex) <> 0 Then
            Dim pSchema As SqliteSchema Ptr = db->aDb(databaseIndex).pSchema
            If pSchema = 0 Then
                pParse->rc = SQLITE_CORRUPT
                pParse->nErr += 1
                Return
            End If
            sqlite3VdbeUsesBtree(pVdbe, databaseIndex)
            sqlite3VdbeAddOp4Int( _
                pVdbe, OP_Transaction, databaseIndex, _
                sqlite3BuildDbMaskTest(pParse->writeMask, databaseIndex), _
                CInt(pSchema->schema_cookie), CInt(pSchema->iGeneration))
            If db->init.busy = 0 Then sqlite3VdbeChangeP5(pVdbe, 1)
        End If
    Next

#ifndef SQLITE_OMIT_VIRTUALTABLE
    For tableLockIndex As SQLITE_C_INT = 0 To pParse->nVtabLock - 1
        If pParse->apVtabLock = 0 Then
            pParse->rc = SQLITE_CORRUPT
            pParse->nErr += 1
            Return
        End If
        Dim pVtab As Any Ptr = sqlite3GetVTable( _
            db, pParse->apVtabLock[tableLockIndex])
        If pVtab = 0 Then
            pParse->rc = SQLITE_CORRUPT
            pParse->nErr += 1
            Return
        End If
        sqlite3VdbeAddOp4( _
            pVdbe, OP_VBegin, 0, 0, 0, CPtr(Const ZString Ptr, pVtab), P4_VTAB)
    Next
    pParse->nVtabLock = 0
#endif

#ifndef SQLITE_OMIT_SHARED_CACHE
    If pParse->nTableLock > 0 Then
        If pParse->aTableLock = 0 Then
            pParse->rc = SQLITE_CORRUPT
            pParse->nErr += 1
            Return
        End If
        For tableLockIndex As SQLITE_C_INT = 0 To pParse->nTableLock - 1
            Dim pTableLock As SqliteTableLock Ptr = _
                @pParse->aTableLock[tableLockIndex]
            sqlite3VdbeAddOp4( _
                pVdbe, OP_TableLock, pTableLock->iDb, _
                CInt(pTableLock->iTab), CInt(pTableLock->isWriteLock), _
                pTableLock->zLockName, P4_STATIC)
        Next
    End If
#endif

#ifndef SQLITE_OMIT_AUTOINCREMENT
    If pParse->usesAinc <> 0 Then sqlite3AutoincrementBegin(pParse)
#endif

    If pParse->pConstExpr <> 0 Then
        Dim pConstExpr As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pParse->pConstExpr)
        If pConstExpr->nExpr < 0 Then
            pParse->rc = SQLITE_CORRUPT
            pParse->nErr += 1
            Return
        End If
        pParse->okConstFactor = 0
        For expressionIndex As SQLITE_C_INT = 0 To pConstExpr->nExpr - 1
            Dim targetRegister As SQLITE_C_INT = _
            pConstExpr->a(expressionIndex).u.iConstExprReg
            If targetRegister <= 0 Then
                pParse->rc = SQLITE_CORRUPT
                pParse->nErr += 1
                Return
            End If
            ' A NULL expression deliberately initializes this cached register.
            sqlite3ExprCode( _
                pParse, pConstExpr->a(expressionIndex).pExpr, targetRegister)
        Next
    End If

    If pParse->bReturning <> 0 Then
        Dim pReturning As SqliteReturning Ptr = _
            CPtr(SqliteReturning Ptr, pParse->u1.d.pReturning)
        If pReturning <> 0 AndAlso pReturning->nRetCol > 0 Then
            sqlite3VdbeAddOp2( _
                pVdbe, OP_OpenEphemeral, pReturning->iRetCur, pReturning->nRetCol)
        End If
    End If

    sqlite3VdbeGoto(pVdbe, 1)
    If db->mallocFailed <> 0 OrElse pVdbe->rc <> SQLITE_OK Then
        pParse->rc = IIf(db->mallocFailed <> 0, SQLITE_NOMEM, pVdbe->rc)
        pParse->nErr += 1
        Return
    End If

    sqlite3VdbeMakeReady(pVdbe, pParse)
    If db->mallocFailed <> 0 OrElse pVdbe->rc <> SQLITE_OK OrElse _
       pVdbe->eVdbeState <> VDBE_READY_STATE Then
        pParse->rc = IIf(db->mallocFailed <> 0, SQLITE_NOMEM, _
                         IIf(pVdbe->rc <> SQLITE_OK, pVdbe->rc, SQLITE_ERROR))
        pParse->nErr += 1
        Return
    End If
    pParse->rc = SQLITE_DONE
End Sub

/' end of sqlite3_build.bas '/
