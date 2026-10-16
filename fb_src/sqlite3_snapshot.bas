/'
    Project: SQLite FreeBASIC port

    File: sqlite3_snapshot.bas

    Purpose:

        Port SQLite's optional WAL snapshot API.

    Responsibilities:

        - Obtain, open, compare, recover, and release snapshot handles.
        - Route snapshot operations through the connection's B-tree and pager.
        - Keep every public snapshot symbol behind SQLITE_ENABLE_SNAPSHOT.

    This file intentionally does NOT contain:

        - WAL-index frame selection or pager-level snapshot locks.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_api_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_btree.bi"
#include once "sqlite3_pager.bi"

Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Declare Function sqlite3FindDbName CDecl Alias "sqlite3FindDbName" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zDatabase As Const ZString Ptr _
) As SQLITE_C_INT
#ifdef SQLITE_ENABLE_API_ARMOR
Declare Function sqlite3SafetyCheckOk CDecl Alias "sqlite3SafetyCheckOk" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
Declare Function sqlite3MisuseError CDecl Alias "sqlite3MisuseError" ( _
    ByVal sourceLine As SQLITE_C_INT _
) As SQLITE_C_INT
#endif

#ifdef SQLITE_ENABLE_SNAPSHOT
/'
    The public snapshot object is 48 opaque bytes. SQLite stores a copy of
    WalIndexHdr there, so these fields keep the same order and C widths through
    aCksum. The comparison routine only reads mxFrame and aSalt[0].
'/ 
Private Type SqliteSnapshotHeader
    version As u32
    unused As u32
    changeCounter As u32
    isInitialized As u8
    bigEndianChecksum As u8
    pageSize As u16
    maxFrame As u32
    pageCount As u32
    frameChecksum(0 To 1) As u32
    salt(0 To 1) As u32
    checksum(0 To 1) As u32
End Type

Function sqlite3_snapshot_cmp CDecl Alias "sqlite3_snapshot_cmp" ( _
    ByVal pSnapshot1 As Any Ptr, _
    ByVal pSnapshot2 As Any Ptr _
) As SQLITE_C_INT Export
    Dim header1 As SqliteSnapshotHeader Ptr = CPtr(SqliteSnapshotHeader Ptr, pSnapshot1)
    Dim header2 As SqliteSnapshotHeader Ptr = CPtr(SqliteSnapshotHeader Ptr, pSnapshot2)

    If header1->salt(0) < header2->salt(0) Then Return -1
    If header1->salt(0) > header2->salt(0) Then Return 1
    If header1->maxFrame < header2->maxFrame Then Return -1
    If header1->maxFrame > header2->maxFrame Then Return 1
    Return 0
End Function

Sub sqlite3_snapshot_free CDecl Alias "sqlite3_snapshot_free" ( _
    ByVal pSnapshot As Any Ptr _
) Export
    sqlite3_free(pSnapshot)
End Sub

Function sqlite3_snapshot_get CDecl Alias "sqlite3_snapshot_get" ( _
    ByVal dbArgument As Any Ptr, _
    ByVal zDatabase As Const ZString Ptr, _
    ByVal ppSnapshot As Any Ptr Ptr _
) As SQLITE_C_INT Export
#ifndef SQLITE_OMIT_WAL
    Dim db As sqlite3 Ptr = CPtr(sqlite3 Ptr, dbArgument)
    If db = 0 OrElse zDatabase = 0 OrElse ppSnapshot = 0 Then _
        Return SQLITE_MISUSE
#ifdef SQLITE_ENABLE_API_ARMOR
    If sqlite3SafetyCheckOk(db) = 0 Then Return sqlite3MisuseError(5101)
#endif

    Dim rc As SQLITE_C_INT = SQLITE_ERROR
    sqlite3_mutex_enter(db->mutex)
    If db->autoCommit = 0 Then
        Dim databaseIndex As SQLITE_C_INT = sqlite3FindDbName(db, zDatabase)
        If databaseIndex = 0 OrElse databaseIndex > 1 Then
            If databaseIndex < db->nDb Then
                Dim pBtree As Btree Ptr = _
                    CPtr(Btree Ptr, db->aDb(databaseIndex).pBt)
                If pBtree <> 0 AndAlso _
                   sqlite3BtreeTxnState(pBtree) <> SQLITE_TXN_WRITE Then
                    Dim pPager As Pager Ptr = sqlite3BtreePager(pBtree)
                    Dim snapshotRequest As SqliteSnapshotHeader
                    snapshotRequest.version = 0
                    sqlite3PagerSnapshotOpen(pPager, @snapshotRequest)
                    rc = sqlite3BtreeBeginTrans(pBtree, 0, 0)
                    sqlite3PagerSnapshotOpen(pPager, 0)
                    If rc = SQLITE_OK Then _
                        rc = sqlite3PagerSnapshotGet(pPager, ppSnapshot)
                End If
            End If
        End If
    End If
    sqlite3_mutex_leave(db->mutex)
    Return rc
#else
    Return SQLITE_ERROR
#endif
End Function

Function sqlite3_snapshot_open CDecl Alias "sqlite3_snapshot_open" ( _
    ByVal dbArgument As Any Ptr, _
    ByVal zDatabase As Const ZString Ptr, _
    ByVal pSnapshot As Any Ptr _
) As SQLITE_C_INT Export
#ifndef SQLITE_OMIT_WAL
    Dim db As sqlite3 Ptr = CPtr(sqlite3 Ptr, dbArgument)
    If db = 0 OrElse zDatabase = 0 OrElse pSnapshot = 0 Then _
        Return SQLITE_MISUSE
#ifdef SQLITE_ENABLE_API_ARMOR
    If sqlite3SafetyCheckOk(db) = 0 Then Return sqlite3MisuseError(5141)
#endif

    Dim rc As SQLITE_C_INT = SQLITE_ERROR
    sqlite3_mutex_enter(db->mutex)
    If db->autoCommit = 0 Then
        Dim databaseIndex As SQLITE_C_INT = sqlite3FindDbName(db, zDatabase)
        If databaseIndex = 0 OrElse databaseIndex > 1 Then
            If databaseIndex < db->nDb Then
                Dim pBtree As Btree Ptr = _
                    CPtr(Btree Ptr, db->aDb(databaseIndex).pBt)
                If pBtree <> 0 AndAlso _
                   sqlite3BtreeTxnState(pBtree) <> SQLITE_TXN_WRITE Then
                    Dim pPager As Pager Ptr = sqlite3BtreePager(pBtree)
                    Dim bUnlock As SQLITE_C_INT = 0
                    If sqlite3BtreeTxnState(pBtree) <> SQLITE_TXN_NONE Then
                        If db->nVdbeActive = 0 Then
                            rc = sqlite3PagerSnapshotCheck(pPager, pSnapshot)
                            If rc = SQLITE_OK Then
                                bUnlock = 1
                                rc = sqlite3BtreeCommit(pBtree)
                            End If
                        End If
                    Else
                        rc = SQLITE_OK
                    End If
                    If rc = SQLITE_OK Then _
                        rc = sqlite3PagerSnapshotOpen(pPager, pSnapshot)
                    If rc = SQLITE_OK Then
                        rc = sqlite3BtreeBeginTrans(pBtree, 0, 0)
                        sqlite3PagerSnapshotOpen(pPager, 0)
                    End If
                    If bUnlock <> 0 Then sqlite3PagerSnapshotUnlock(pPager)
                End If
            End If
        End If
    End If
    sqlite3_mutex_leave(db->mutex)
    Return rc
#else
    Return SQLITE_ERROR
#endif
End Function

Function sqlite3_snapshot_recover CDecl Alias "sqlite3_snapshot_recover" ( _
    ByVal dbArgument As Any Ptr, _
    ByVal zDatabase As Const ZString Ptr _
) As SQLITE_C_INT Export
#ifndef SQLITE_OMIT_WAL
    Dim db As sqlite3 Ptr = CPtr(sqlite3 Ptr, dbArgument)
    If db = 0 OrElse zDatabase = 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_ENABLE_API_ARMOR
    If sqlite3SafetyCheckOk(db) = 0 Then Return sqlite3MisuseError(5194)
#endif

    Dim rc As SQLITE_C_INT = SQLITE_ERROR
    sqlite3_mutex_enter(db->mutex)
    Dim databaseIndex As SQLITE_C_INT = sqlite3FindDbName(db, zDatabase)
    If databaseIndex = 0 OrElse databaseIndex > 1 Then
        If databaseIndex < db->nDb Then
            Dim pBtree As Btree Ptr = _
                CPtr(Btree Ptr, db->aDb(databaseIndex).pBt)
            If pBtree <> 0 AndAlso _
               sqlite3BtreeTxnState(pBtree) = SQLITE_TXN_NONE Then
                rc = sqlite3BtreeBeginTrans(pBtree, 0, 0)
                If rc = SQLITE_OK Then
                    rc = sqlite3PagerSnapshotRecover(sqlite3BtreePager(pBtree))
                    sqlite3BtreeCommit(pBtree)
                End If
            End If
        End If
    End If
    sqlite3_mutex_leave(db->mutex)
    Return rc
#else
    Return SQLITE_ERROR
#endif
End Function
#endif

/' end of sqlite3_snapshot.bas '/
