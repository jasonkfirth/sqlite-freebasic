/'
** 2003 September 6
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
*************************************************************************
** This file contains code used for creating, destroying, and populating
** a VDBE (or an "sqlite3_stmt" as it is known to the outside world.)
'/
/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_bulk42_vdbeaux_finalize.bas

    Purpose:

        Resolve VDBE jump labels and transfer a completed opcode array.

    Responsibilities:

        - Finalize jump destinations and reader/write classification.
        - Track the largest virtual-table argument count.
        - Transfer opcode-array ownership to subprogram callers.

    This file intentionally does NOT contain:

        - VDBE execution or opcode generation.
        - The complete prepared-statement finalization path.
'/

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_opcodes.bi"

Private Function resolveP2Values( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pMaxVtabArgs As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse pVdbe->pParse = 0 OrElse _
       pVdbe->aOp = 0 OrElse pVdbe->nOp <= 0 OrElse pMaxVtabArgs = 0 Then _
        Return SQLITE_MISUSE

    Dim pParse As SqliteParseContext Ptr = _
        CPtr(SqliteParseContext Ptr, pVdbe->pParse)
    Dim maximumVtabArgs As SQLITE_C_INT = pMaxVtabArgs[0]

    pVdbe->vdbeFlags = (pVdbe->vdbeFlags And _
        Not (VDBE_READONLY_MASK Or VDBE_BISREADER_MASK)) Or VDBE_READONLY_MASK

    Dim foundInit As SQLITE_C_INT = 0
    For opIndex As SQLITE_C_INT = pVdbe->nOp - 1 To 0 Step -1
        Dim pOp As SqliteVdbeOp Ptr = @pVdbe->aOp[opIndex]
        Dim opcode As SQLITE_C_INT = pOp->opcode

        If opcode = OP_Init Then
            foundInit = 1
            Exit For
        End If

        If opcode >= 0 AndAlso opcode <= UBound(sqlite3OpcodeProperty) Then
            If (sqlite3OpcodeProperty(opcode) And OPFLG_JUMP) <> 0 AndAlso _
               pOp->p2 < 0 Then
                If pParse->aLabel = 0 OrElse pParse->nLabel >= 0 Then _
                    Return SQLITE_CORRUPT
                Dim labelIndex As SQLITE_C_INT = Not pOp->p2
                If labelIndex < 0 OrElse labelIndex >= -pParse->nLabel Then _
                    Return SQLITE_CORRUPT
                pOp->p2 = pParse->aLabel[labelIndex]
            End If
        End If

        Select Case opcode
        Case OP_Transaction
            pVdbe->vdbeFlags Or= VDBE_BISREADER_MASK
            If pOp->p2 <> 0 Then _
                pVdbe->vdbeFlags = pVdbe->vdbeFlags And Not VDBE_READONLY_MASK

        Case OP_AutoCommit, OP_Savepoint
            pVdbe->vdbeFlags Or= VDBE_BISREADER_MASK

        Case OP_Checkpoint, OP_Vacuum, OP_JournalMode
            pVdbe->vdbeFlags = pVdbe->vdbeFlags And Not VDBE_READONLY_MASK
            pVdbe->vdbeFlags Or= VDBE_BISREADER_MASK

#ifndef SQLITE_OMIT_VIRTUALTABLE
        Case OP_VUpdate
            If pOp->p2 < 0 Then Return SQLITE_CORRUPT
            If pOp->p2 > maximumVtabArgs Then maximumVtabArgs = pOp->p2

        Case OP_VFilter
            If opIndex < 1 OrElse pVdbe->aOp[opIndex - 1].opcode <> OP_Integer Then _
                Return SQLITE_CORRUPT
            Dim argumentCount As SQLITE_C_INT = pVdbe->aOp[opIndex - 1].p1
            If argumentCount < 0 OrElse argumentCount > SQLITE_MAX_VDBE_OP Then _
                Return SQLITE_CORRUPT
            If argumentCount > maximumVtabArgs Then maximumVtabArgs = argumentCount
#endif
        End Select
    Next

    If foundInit = 0 Then Return SQLITE_CORRUPT

    If pParse->aLabel Then
        sqlite3DbNNFreeNN(pVdbe->db, pParse->aLabel)
        pParse->aLabel = 0
    End If
    pParse->nLabel = 0
    pMaxVtabArgs[0] = maximumVtabArgs
    Return SQLITE_OK
End Function

Function sqlite3VdbeResolveP2Values CDecl Alias "sqlite3VdbeResolveP2Values" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pMaxVtabArgs As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    Return resolveP2Values(pVdbe, pMaxVtabArgs)
End Function

Function sqlite3VdbeTakeOpArray CDecl Alias "sqlite3VdbeTakeOpArray" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pnOp As SQLITE_C_INT Ptr, _
    ByVal pnMaxVtabArgs As SQLITE_C_INT Ptr _
) As SqliteVdbeOp Ptr
    If pVdbe = 0 OrElse pnOp = 0 OrElse pnMaxVtabArgs = 0 OrElse _
       pVdbe->db = 0 OrElse pVdbe->db->mallocFailed <> 0 OrElse _
       pVdbe->aOp = 0 Then Return 0

    If resolveP2Values(pVdbe, pnMaxVtabArgs) <> SQLITE_OK Then Return 0

    Dim pOpArray As SqliteVdbeOp Ptr = pVdbe->aOp
    pnOp[0] = pVdbe->nOp
    pVdbe->aOp = 0
    Return pOpArray
End Function

/' end of sqlite3_bulk42_vdbeaux_finalize.bas '/
