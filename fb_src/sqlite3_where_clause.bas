/'
    Project: SQLite FreeBASIC port

    File: sqlite3_where_clause.bas

    Purpose:

        Manage WhereInfo-owned scratch memory and append planner terms.

    Responsibilities:

        - Allocate temporary WHERE memory with WhereInfo-owned lifetime.
        - Grow scratch allocations without freeing earlier planner state.
        - Expand the WhereTerm array without losing existing terms.
        - Preserve expression ownership when a dynamic insertion fails.

    This file intentionally does NOT contain:

        - Expression analysis or WHERE-loop selection.
'/

#lang "fb"

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_util_numeric.bi"
#include once "sqlite3_where_types.bi"

Declare Function sqlite3WhereMemset CDecl Alias "memset" ( _
    ByVal pDestination As Any Ptr, _
    ByVal value As SQLITE_C_INT, _
    ByVal byteCount As SQLITE_SIZE_T _
) As Any Ptr
Declare Function sqlite3WhereMemcpy CDecl Alias "memcpy" ( _
    ByVal pDestination As Any Ptr, _
    ByVal pSource As Const Any Ptr, _
    ByVal byteCount As SQLITE_SIZE_T _
) As Any Ptr

Private Const WHERE_TERM_DYNAMIC As u16 = &H0001
Private Const WHERE_TERM_VIRTUAL As u16 = &H0002

/' ------------------------------------------------------------------------- '/
/' WhereInfo-owned temporary storage                                          '/
/' ------------------------------------------------------------------------- '/

Function sqlite3WhereMalloc CDecl Alias "sqlite3WhereMalloc" ( _
    ByVal pWhereInfo As SqliteWhereInfo Ptr, _
    ByVal byteCount As sqlite3_uint64 _
) As Any Ptr
    If pWhereInfo = 0 OrElse pWhereInfo->pParse = 0 Then Return 0

    Dim pParse As SqliteParseContext Ptr = _
        CPtr(SqliteParseContext Ptr, pWhereInfo->pParse)
    If pParse->db = 0 Then Return 0

    Dim headerSize As sqlite3_uint64 = CULngInt(SizeOf(SqliteWhereMemBlock))
    If byteCount > &HFFFFFFFFFFFFFFFFULL - headerSize Then Return 0
    Dim allocationSize As sqlite3_uint64 = byteCount + headerSize
    Dim pBlock As SqliteWhereMemBlock Ptr = _
        CPtr(SqliteWhereMemBlock Ptr, sqlite3DbMallocRawNN(pParse->db, allocationSize))
    If pBlock = 0 Then Return 0

    pBlock->pNext = pWhereInfo->pMemToFree
    pBlock->sz = byteCount
    pWhereInfo->pMemToFree = pBlock
    Return CPtr(Any Ptr, pBlock + 1)
End Function

' Earlier scratch blocks stay linked to WhereInfo until query cleanup.
Function sqlite3WhereRealloc CDecl Alias "sqlite3WhereRealloc" ( _
    ByVal pWhereInfo As SqliteWhereInfo Ptr, _
    ByVal pOld As Any Ptr, _
    ByVal byteCount As sqlite3_uint64 _
) As Any Ptr
    If pWhereInfo = 0 Then Return 0
    Dim pNew As Any Ptr = sqlite3WhereMalloc(pWhereInfo, byteCount)
    If pNew = 0 OrElse pOld = 0 Then Return pNew

    Dim pOldHeader As SqliteWhereMemBlock Ptr = _
        CPtr(SqliteWhereMemBlock Ptr, _
            CPtr(UByte Ptr, pOld) - SizeOf(SqliteWhereMemBlock))
    If pOldHeader->sz > byteCount Then Return 0
    sqlite3WhereMemcpy(pNew, pOld, CULngInt(pOldHeader->sz))
    Return pNew
End Function

/' ------------------------------------------------------------------------- '/
/' WhereTerm storage growth                                                   '/
/' ------------------------------------------------------------------------- '/

Private Function whereClauseInsertFailure( _
    ByVal pWhereClause As SqliteWhereClause Ptr, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal termFlags As u16 _
) As SQLITE_C_INT
    If (termFlags And WHERE_TERM_DYNAMIC) <> 0 AndAlso pWhereClause Then
        Dim pWhereInfo As SqliteWhereInfo Ptr = _
            CPtr(SqliteWhereInfo Ptr, pWhereClause->pWInfo)
        If pWhereInfo AndAlso pWhereInfo->pParse Then
            Dim pParse As SqliteParseContext Ptr = _
                CPtr(SqliteParseContext Ptr, pWhereInfo->pParse)
            If pParse->db Then sqlite3ExprDelete(pParse->db, pExpr)
        End If
    End If
    Return 0
End Function

Function whereClauseInsert CDecl Alias "whereClauseInsert" ( _
    ByVal pWhereClause As SqliteWhereClause Ptr, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal termFlags As u16 _
) As SQLITE_C_INT
    If pWhereClause = 0 OrElse pWhereClause->nTerm < 0 OrElse _
       pWhereClause->nSlot < 0 OrElse pWhereClause->nTerm > pWhereClause->nSlot Then
        Return whereClauseInsertFailure(pWhereClause, pExpr, termFlags)
    End If

    Dim tailProbe As SqliteWhereTerm
    Dim termBase As sqlite3_uint64 = CULngInt(CPtr(Any Ptr, @tailProbe))
    Dim operatorAddress As sqlite3_uint64 = CULngInt(CPtr(Any Ptr, @tailProbe.eOperator))
    If operatorAddress < termBase OrElse _
       operatorAddress - termBase > CULngInt(SizeOf(SqliteWhereTerm)) Then
        Return whereClauseInsertFailure(pWhereClause, pExpr, termFlags)
    End If
    Dim tailSize As sqlite3_uint64 = _
        CULngInt(SizeOf(SqliteWhereTerm)) - (operatorAddress - termBase)

    If pWhereClause->nTerm >= pWhereClause->nSlot Then
        Dim pOldTerms As SqliteWhereTerm Ptr = _
            CPtr(SqliteWhereTerm Ptr, pWhereClause->a)
        Dim pWhereInfo As SqliteWhereInfo Ptr = _
            CPtr(SqliteWhereInfo Ptr, pWhereClause->pWInfo)
        If pWhereInfo = 0 Then Return whereClauseInsertFailure(pWhereClause, pExpr, termFlags)

        Dim oldSlotCount As SQLITE_C_INT = pWhereClause->nSlot
        If oldSlotCount > 1073741823 Then Return whereClauseInsertFailure(pWhereClause, pExpr, termFlags)
        Dim newSlotCount As SQLITE_C_INT = IIf(oldSlotCount = 0, 8, oldSlotCount * 2)
        Dim bytesPerTerm As sqlite3_uint64 = CULngInt(SizeOf(SqliteWhereTerm))
        Dim byteCount As sqlite3_uint64 = CULngInt(newSlotCount) * bytesPerTerm
        If bytesPerTerm = 0 OrElse byteCount \ bytesPerTerm <> CULngInt(newSlotCount) Then _
            Return whereClauseInsertFailure(pWhereClause, pExpr, termFlags)

        Dim pNewTerms As SqliteWhereTerm Ptr = _
            CPtr(SqliteWhereTerm Ptr, sqlite3WhereMalloc(pWhereInfo, byteCount))
        If pNewTerms = 0 Then Return whereClauseInsertFailure(pWhereClause, pExpr, termFlags)
        If pWhereClause->nTerm > 0 Then
            If pOldTerms = 0 Then Return whereClauseInsertFailure(pWhereClause, pExpr, termFlags)
            Dim oldByteCount As sqlite3_uint64 = _
                CULngInt(pWhereClause->nTerm) * bytesPerTerm
            If oldByteCount \ bytesPerTerm <> CULngInt(pWhereClause->nTerm) Then _
                Return whereClauseInsertFailure(pWhereClause, pExpr, termFlags)
            sqlite3WhereMemcpy(pNewTerms, pOldTerms, CULngInt(oldByteCount))
        End If
        pWhereClause->a = pNewTerms
        pWhereClause->nSlot = newSlotCount
    End If

    If pWhereClause->a = 0 OrElse pWhereClause->nTerm >= pWhereClause->nSlot Then _
        Return whereClauseInsertFailure(pWhereClause, pExpr, termFlags)

    Dim termIndex As SQLITE_C_INT = pWhereClause->nTerm
    pWhereClause->nTerm += 1
    If (termFlags And WHERE_TERM_VIRTUAL) = 0 Then _
        pWhereClause->nBase = pWhereClause->nTerm

    Dim pTerm As SqliteWhereTerm Ptr = _
        CPtr(SqliteWhereTerm Ptr, pWhereClause->a) + termIndex
    If pExpr AndAlso (pExpr->flags And EP_Unlikely) <> 0 Then
        pTerm->truthProb = CShort(CLng(sqlite3LogEst(CULngInt(pExpr->iTable))) - 270)
    Else
        pTerm->truthProb = 1
    End If
    pTerm->pExpr = sqlite3ExprSkipCollateAndLikely(pExpr)
    pTerm->wtFlags = termFlags
    pTerm->pWC = pWhereClause

    sqlite3WhereMemset(@pTerm->eOperator, 0, CULngInt(tailSize))
    Return termIndex
End Function

/' end of sqlite3_where_clause.bas '/
