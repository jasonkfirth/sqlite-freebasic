/'
    Project: SQLite FreeBASIC port

    File: sqlite3_cte.bas

    Purpose:

        Own and duplicate SQLite WITH clauses and their CTE entries.

    Responsibilities:

        - Append parsed CTE entries while checking for duplicate names.
        - Deep-copy CTE names, column lists, and supported SELECT trees with
          mapped FROM-list entries.
        - Release CTE-owned expressions, SELECTs, and names.
        - Preserve the CTE usage pointer's separate parser-cleanup ownership.

    This file intentionally does NOT contain:

        - CTE name resolution, recursive materialization, or CTE-use lifecycle.
        - CTE name resolution, recursive materialization, or full window copies.
'/ 

#lang "fb"
#include once "sqlite3_walker.bi"
#include once "sqlite3_constants.bi"

Declare Function sqlite3_stricmp CDecl Alias "sqlite3_stricmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3Dequote CDecl Alias "sqlite3Dequote" ( _
    ByVal z As ZString Ptr _
)

Private Sub cteClear CDecl Alias "cteClear" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pCte As SqliteCte Ptr _
)
    If db = 0 OrElse pCte = 0 Then Exit Sub
    sqlite3ExprListDelete(db, pCte->pCols)
    sqlite3SelectDelete(db, pCte->pSelect)
    If pCte->zName <> 0 Then sqlite3DbFree(db, pCte->zName)
    pCte->pCols = 0
    pCte->pSelect = 0
    pCte->zName = 0
End Sub

Function sqlite3NameFromToken CDecl Alias "sqlite3NameFromToken" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pName As Const sqlite3ParserToken Ptr _
) As ZString Ptr Export
    If db = 0 OrElse pName = 0 OrElse pName->n > SQLITE_MAX_ALLOCATION_SIZE OrElse _
       (pName->n > 0 AndAlso pName->z = 0) Then Return 0
    Dim zName As ZString Ptr = CPtr(ZString Ptr, _
        sqlite3DbStrNDup(db, CPtr(Const ZString Ptr, pName->z), pName->n))
    If zName <> 0 Then sqlite3Dequote(zName)
    Return zName
End Function

Sub sqlite3CteDelete CDecl Alias "sqlite3CteDelete" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pCte As SqliteCte Ptr _
) Export
    If pCte = 0 Then Exit Sub
    cteClear(db, pCte)
    sqlite3DbFree(db, pCte)
End Sub

Function sqlite3CteNew CDecl Alias "sqlite3CteNew" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pName As Const sqlite3ParserToken Ptr, _
    ByVal pColumns As SqliteExprList Ptr, _
    ByVal pQuery As SqliteSelect Ptr, _
    ByVal materialization As u8 _
) As SqliteCte Ptr Export
    If pParse = 0 OrElse pParse->db = 0 Then Return 0
    Dim db As sqlite3 Ptr = pParse->db
    Dim pCte As SqliteCte Ptr = CPtr(SqliteCte Ptr, _
        sqlite3DbMallocZero(db, SizeOf(SqliteCte)))
    If pCte = 0 Then
        sqlite3ExprListDelete(db, pColumns)
        sqlite3SelectDelete(db, pQuery)
        Return 0
    End If
    pCte->pSelect = pQuery
    pCte->pCols = pColumns
    pCte->zName = sqlite3NameFromToken(db, pName)
    pCte->eM10d = materialization
    If pCte->zName = 0 OrElse db->mallocFailed <> 0 Then
        sqlite3CteDelete(db, pCte)
        Return 0
    End If
    Return pCte
End Function

Sub sqlite3WithDelete CDecl Alias "sqlite3WithDelete" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pWith As SqliteWith Ptr _
) Export
    If pWith = 0 Then Exit Sub
    If pWith->nCte < 0 OrElse _
       CULngInt(pWith->nCte) > SQLITE_MAX_ALLOCATION_SIZE \ SizeOf(SqliteCte) Then
        sqlite3DbFree(db, pWith)
        Exit Sub
    End If
    For cteIndex As SQLITE_C_INT = 0 To pWith->nCte - 1
        cteClear(db, @pWith->a(cteIndex))
    Next
    sqlite3DbFree(db, pWith)
End Sub

Sub sqlite3WithDeleteGeneric CDecl Alias "sqlite3WithDeleteGeneric" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pWith As Any Ptr _
) Export
    sqlite3WithDelete(db, CPtr(SqliteWith Ptr, pWith))
End Sub

Function sqlite3WithDup CDecl Alias "sqlite3WithDup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pSource As Const SqliteWith Ptr _
) As SqliteWith Ptr Export
    If db = 0 OrElse pSource = 0 OrElse pSource->nCte < 0 Then Return 0
    Dim nCte As sqlite3_uint64 = CULngInt(pSource->nCte)
    If nCte > (SQLITE_MAX_ALLOCATION_SIZE - _
        (SizeOf(SqliteWith) - SizeOf(SqliteCte))) \ SizeOf(SqliteCte) Then Return 0

    Dim allocationBytes As sqlite3_uint64 = _
        SizeOf(SqliteWith) - SizeOf(SqliteCte) + nCte * SizeOf(SqliteCte)
    Dim pNewWith As SqliteWith Ptr = CPtr(SqliteWith Ptr, _
        sqlite3DbMallocZero(db, allocationBytes))
    If pNewWith = 0 Then Return 0
    pNewWith->nCte = pSource->nCte

    For cteIndex As SQLITE_C_INT = 0 To pSource->nCte - 1
        Dim pOld As Const SqliteCte Ptr = @pSource->a(cteIndex)
        Dim pNew As SqliteCte Ptr = @pNewWith->a(cteIndex)
        If pOld->pSelect <> 0 Then pNew->pSelect = _
            sqlite3SelectDup(db, pOld->pSelect, 0)
        If pOld->pCols <> 0 Then pNew->pCols = _
            sqlite3ExprListDup(db, pOld->pCols, 0)
        If pOld->zName <> 0 Then pNew->zName = CPtr(ZString Ptr, _
            sqlite3DbStrDup(db, pOld->zName))
        pNew->eM10d = pOld->eM10d

        If (pOld->pSelect <> 0 AndAlso pNew->pSelect = 0) OrElse _
           (pOld->pCols <> 0 AndAlso pNew->pCols = 0) OrElse _
           (pOld->zName <> 0 AndAlso pNew->zName = 0) OrElse _
           db->mallocFailed <> 0 Then
            sqlite3WithDelete(db, pNewWith)
            Return 0
        End If
    Next
    Return pNewWith
End Function

Function sqlite3WithAdd CDecl Alias "sqlite3WithAdd" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pWith As SqliteWith Ptr, _
    ByVal pCte As SqliteCte Ptr _
) As SqliteWith Ptr Export
    If pCte = 0 Then Return pWith
    If pParse = 0 OrElse pParse->db = 0 Then Return pWith
    Dim db As sqlite3 Ptr = pParse->db
    If pCte->zName = 0 Then
        sqlite3CteDelete(db, pCte)
        Return pWith
    End If

    Dim existingCount As SQLITE_C_INT = 0
    If pWith <> 0 Then
        If pWith->nCte < 0 OrElse _
           CULngInt(pWith->nCte) >= SQLITE_MAX_ALLOCATION_SIZE \ SizeOf(SqliteCte) Then
            sqlite3CteDelete(db, pCte)
            Return pWith
        End If
        existingCount = pWith->nCte
        For cteIndex As SQLITE_C_INT = 0 To existingCount - 1
            If pWith->a(cteIndex).zName <> 0 AndAlso _
               sqlite3_stricmp(pCte->zName, pWith->a(cteIndex).zName) = 0 Then
                sqlite3ErrorMsg(pParse, StrPtr("duplicate WITH table name: %s"), pCte->zName)
            End If
        Next
    End If

    Dim baseBytes As sqlite3_uint64 = SizeOf(SqliteWith) - SizeOf(SqliteCte)
    Dim newCount As sqlite3_uint64 = CULngInt(existingCount) + 1
    If newCount > (SQLITE_MAX_ALLOCATION_SIZE - baseBytes) \ SizeOf(SqliteCte) Then
        sqlite3CteDelete(db, pCte)
        Return pWith
    End If
    Dim newBytes As sqlite3_uint64 = baseBytes + newCount * SizeOf(SqliteCte)
    Dim pNewWith As SqliteWith Ptr
    If pWith = 0 Then
        pNewWith = CPtr(SqliteWith Ptr, sqlite3DbMallocZero(db, newBytes))
    Else
        pNewWith = CPtr(SqliteWith Ptr, sqlite3DbRealloc(db, pWith, newBytes))
    End If
    If pNewWith = 0 Then
        sqlite3CteDelete(db, pCte)
        Return pWith
    End If

    Dim pNewCte As SqliteCte Ptr = @pNewWith->a(existingCount)
    pNewCte[0] = pCte[0]
    pNewWith->nCte = existingCount + 1
    sqlite3DbFree(db, pCte)
    Return pNewWith
End Function

Function sqlite3WithPush CDecl Alias "sqlite3WithPush" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pWithArgument As SqliteWith Ptr, _
    ByVal freeWith As u8 _
) As SqliteWith Ptr Export
    If pWithArgument = 0 Then Return 0
    If pParse = 0 OrElse pParse->db = 0 Then Return 0

    Dim pWith As SqliteWith Ptr = pWithArgument
    If freeWith <> 0 Then
        pWith = CPtr(SqliteWith Ptr, sqlite3ParserAddCleanup( _
            pParse, @sqlite3WithDeleteGeneric, pWith))
        If pWith = 0 Then Return 0
    End If
    If pParse->nErr = 0 Then
        pWith->pOuter = pParse->pWith
        pParse->pWith = pWith
    End If
    Return pWith
End Function

/' end of sqlite3_cte.bas '/
