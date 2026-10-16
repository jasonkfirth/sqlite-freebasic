/'
    Project: SQLite FreeBASIC port

    File: sqlite3_schema.bas

    Purpose:

        Own the initial schema hash state and schema safety flags.

    Responsibilities:

        - Allocate a schema object for a B-tree and initialize its hashes.
        - Clear schema hash state when its B-tree or temp slot is released.
        - Map schema pointers back to their database slot.
        - Clear DBFLAG_SchemaChange after schema updates become durable.
        - Report whether writable_schema is enabled without defensive mode.
        - Normalize quoted string expressions used as schema identifiers.

    This file intentionally does NOT contain:

        - Schema parsing, object creation, or B-tree commit logic.
'/

#lang "fb"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_btree.bi"

Extern "C"
    Declare Function sqlite3SchemaMemset CDecl Alias "memset" ( _
        ByVal destination As Any Ptr, _
        ByVal value As SQLITE_C_INT, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
End Extern

Declare Sub sqlite3DeleteTable CDecl Alias "sqlite3DeleteTable" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pTable As Any Ptr _
)
Declare Sub sqlite3DeleteTrigger CDecl Alias "sqlite3DeleteTrigger" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pTrigger As Any Ptr _
)

Private Const DBFLAG_SchemaChange As u32 = &H0001

Sub sqlite3SchemaClear CDecl Alias "sqlite3SchemaClear" ( _
    ByVal pSchemaArgument As Any Ptr _
) Export
    If pSchemaArgument = 0 Then Return
    Dim pSchema As SqliteSchema Ptr = _
        CPtr(SqliteSchema Ptr, pSchemaArgument)

    ' B-tree schema callbacks do not receive sqlite3*. The schema-owned table
    ' and trigger objects use ordinary heap storage because CREATE parsing
    ' disables per-connection lookaside allocation.
    Dim emptyDb As sqlite3
    sqlite3SchemaMemset(@emptyDb, 0, SizeOf(emptyDb))

    Dim oldTables As Hash = pSchema->tblHash
    Dim oldTriggers As Hash = pSchema->trigHash
    sqlite3HashInit(@pSchema->trigHash)
    sqlite3HashClear(@pSchema->idxHash)

    Dim pElement As HashElem Ptr = oldTriggers.first
    Dim pNextElement As HashElem Ptr
    While pElement <> 0
        pNextElement = pElement->next
        sqlite3DeleteTrigger(@emptyDb, pElement->data)
        pElement = pNextElement
    Wend
    sqlite3HashClear(@oldTriggers)

    sqlite3HashInit(@pSchema->tblHash)
    pElement = oldTables.first
    While pElement <> 0
        pNextElement = pElement->next
        sqlite3DeleteTable(@emptyDb, pElement->data)
        pElement = pNextElement
    Wend
    sqlite3HashClear(@oldTables)
    sqlite3HashClear(@pSchema->fkeyHash)
    pSchema->pSeqTab = 0
    If (pSchema->schemaFlags And DB_SchemaLoaded) <> 0 Then _
        pSchema->iGeneration += 1
    pSchema->schemaFlags And= Not (DB_SchemaLoaded Or DB_ResetWanted)
End Sub

Function sqlite3SchemaGet CDecl Alias "sqlite3SchemaGet" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pBtree As Btree Ptr _
) As SqliteSchema Ptr Export
    Dim pSchema As SqliteSchema Ptr
    If pBtree <> 0 Then
        pSchema = CPtr(SqliteSchema Ptr, sqlite3BtreeSchema( _
            pBtree, SizeOf(SqliteSchema), @sqlite3SchemaClear))
    Else
        pSchema = CPtr(SqliteSchema Ptr, sqlite3DbMallocZero( _
            0, SizeOf(SqliteSchema)))
    End If

    If pSchema = 0 Then
        sqlite3OomFault(db)
    ElseIf pSchema->file_format = 0 Then
        sqlite3HashInit(@pSchema->tblHash)
        sqlite3HashInit(@pSchema->idxHash)
        sqlite3HashInit(@pSchema->trigHash)
        sqlite3HashInit(@pSchema->fkeyHash)
        pSchema->enc = SQLITE_UTF8
    End If
    Return pSchema
End Function

Function sqlite3SchemaToIndex CDecl Alias "sqlite3SchemaToIndex" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pSchema As SqliteSchema Ptr _
) As SQLITE_C_INT Export
    Const invalidIndex As SQLITE_C_INT = -32768
    If db = 0 OrElse pSchema = 0 OrElse db->nDb < 0 OrElse _
       db->nDb > SQLITE_MAX_ATTACHED + 2 Then Return invalidIndex

    For databaseIndex As SQLITE_C_INT = 0 To db->nDb - 1
        If db->aDb(databaseIndex).pSchema = pSchema Then Return databaseIndex
    Next
    Return invalidIndex
End Function

Sub sqlite3CommitInternalChanges CDecl Alias "sqlite3CommitInternalChanges" ( _
    ByVal db As sqlite3 Ptr _
)
    If db = 0 Then Return
    db->mDbFlags = db->mDbFlags And Not DBFLAG_SchemaChange
End Sub

Function sqlite3WritableSchema CDecl Alias "sqlite3WritableSchema" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT Export
    If db = 0 Then Return 0
    Return CInt((db->flags And (SQLITE_WriteSchema Or SQLITE_Defensive)) = _
                SQLITE_WriteSchema)
End Function

Private Sub sqlite3StringToId CDecl Alias "sqlite3StringToId" ( _
    ByVal pExpr As SqliteExpr Ptr _
)
    If pExpr = 0 Then Return
    If pExpr->op = TK_STRING Then
        pExpr->op = TK_ID
    ElseIf pExpr->op = TK_COLLATE AndAlso pExpr->pLeft <> 0 AndAlso _
           CPtr(SqliteExpr Ptr, pExpr->pLeft)->op = TK_STRING Then
        CPtr(SqliteExpr Ptr, pExpr->pLeft)->op = TK_ID
    End If
End Sub

/' end of sqlite3_schema.bas '/
