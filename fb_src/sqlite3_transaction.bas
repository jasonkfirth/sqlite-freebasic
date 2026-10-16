/'
    Project: SQLite FreeBASIC port

    File: sqlite3_transaction.bas

    Purpose:

        Generate VDBE instructions for SQL transaction and savepoint commands.

    Responsibilities:

        - Lower BEGIN, COMMIT, and ROLLBACK to transaction opcodes.
        - Lower SAVEPOINT, RELEASE, and ROLLBACK TO to savepoint opcodes.
        - Authorize transaction statements before emitting VDBE operations.
    - Preserve transaction mode and read-only state for each database.

    This file intentionally does NOT contain:

        - VDBE transaction execution.
        - The authorizer callback implementation in src/auth.c.
'/ 

#lang "fb"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_btree.bi"
#include once "sqlite3_pager.bi"
#include once "sqlite3_walker.bi"
#include once "sqlite3_tokens.bi"
#include once "sqlite3_api_constants.bi"

Declare Function sqlite3AuthCheck CDecl Alias "sqlite3AuthCheck" ( _
    ByVal pParse As Any Ptr, _
    ByVal action As SQLITE_C_INT, _
    ByVal zArg1 As Const ZString Ptr, _
    ByVal zArg2 As Const ZString Ptr, _
    ByVal zArg3 As Const ZString Ptr _
) As SQLITE_C_INT

Sub sqlite3BeginTransaction CDecl Alias "sqlite3BeginTransaction" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal transactionType As SQLITE_C_INT _
) Export
    If pParse = 0 OrElse pParse->db = 0 Then Exit Sub
    If transactionType <> TK_DEFERRED AndAlso _
       transactionType <> TK_IMMEDIATE AndAlso _
       transactionType <> TK_EXCLUSIVE Then Exit Sub

    Dim db As sqlite3 Ptr = pParse->db
    If sqlite3AuthCheck( _
        pParse, SQLITE_TRANSACTION, StrPtr("BEGIN"), 0, 0) <> SQLITE_OK Then _
        Exit Sub
    Dim pVdbe As SqliteVdbe Ptr = sqlite3GetVdbe(pParse)
    If pVdbe = 0 Then Exit Sub

    If transactionType <> TK_DEFERRED Then
        For databaseIndex As SQLITE_C_INT = 0 To db->nDb - 1
            Dim pBtree As Btree Ptr = CPtr( _
                Btree Ptr, db->aDb(databaseIndex).pBt)
            If pBtree <> 0 Then
            Dim transactionMode As SQLITE_C_INT = 1
            If sqlite3BtreeIsReadonly(pBtree) <> 0 Then
                transactionMode = 0
            ElseIf transactionType = TK_EXCLUSIVE Then
                transactionMode = 2
            End If
                sqlite3VdbeAddOp2( _
                    pVdbe, OP_Transaction, databaseIndex, transactionMode)
                sqlite3VdbeUsesBtree(pVdbe, databaseIndex)
            End If
        Next
    End If

    sqlite3VdbeAddOp0(pVdbe, OP_AutoCommit)
End Sub

Sub sqlite3EndTransaction CDecl Alias "sqlite3EndTransaction" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal endType As SQLITE_C_INT _
) Export
    If pParse = 0 OrElse pParse->db = 0 Then Exit Sub
    If endType <> TK_COMMIT AndAlso endType <> TK_END AndAlso _
       endType <> TK_ROLLBACK Then Exit Sub

    Dim zAuthorizationOperation As Const ZString Ptr = StrPtr("COMMIT")
    If endType = TK_ROLLBACK Then _
        zAuthorizationOperation = StrPtr("ROLLBACK")
    If sqlite3AuthCheck( _
        pParse, SQLITE_TRANSACTION, zAuthorizationOperation, 0, 0) <> SQLITE_OK Then _
        Exit Sub

    Dim pVdbe As SqliteVdbe Ptr = sqlite3GetVdbe(pParse)
    If pVdbe = 0 Then Exit Sub
    Dim isRollback As SQLITE_C_INT = 0
    If endType = TK_ROLLBACK Then isRollback = 1
    sqlite3VdbeAddOp2(pVdbe, OP_AutoCommit, 1, isRollback)
End Sub

Sub sqlite3Savepoint CDecl Alias "sqlite3Savepoint" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal pName As sqlite3ParserToken Ptr _
) Export
    If pParse = 0 OrElse pParse->db = 0 OrElse pName = 0 Then Exit Sub
    If operation <> SAVEPOINT_BEGIN AndAlso _
       operation <> SAVEPOINT_RELEASE AndAlso _
       operation <> SAVEPOINT_ROLLBACK Then Exit Sub

    Dim db As sqlite3 Ptr = pParse->db
    Dim zName As ZString Ptr = sqlite3NameFromToken(db, pName)
    If zName = 0 Then Exit Sub

    Dim pVdbe As SqliteVdbe Ptr = sqlite3GetVdbe(pParse)
    Dim zAuthorizationOperation As Const ZString Ptr
    Select Case operation
        Case SAVEPOINT_BEGIN
            zAuthorizationOperation = StrPtr("BEGIN")
        Case SAVEPOINT_RELEASE
            zAuthorizationOperation = StrPtr("RELEASE")
        Case SAVEPOINT_ROLLBACK
            zAuthorizationOperation = StrPtr("ROLLBACK")
        Case Else
            sqlite3DbFree(db, zName)
            Exit Sub
    End Select
    If pVdbe = 0 OrElse sqlite3AuthCheck( _
        pParse, SQLITE_SAVEPOINT, zAuthorizationOperation, zName, 0) <> SQLITE_OK Then
        sqlite3DbFree(db, zName)
        Exit Sub
    End If
    sqlite3VdbeAddOp4(pVdbe, OP_Savepoint, operation, 0, 0, zName, P4_DYNAMIC)
End Sub

/' end of sqlite3_transaction.bas '/
