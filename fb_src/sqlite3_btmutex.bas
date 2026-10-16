/'
    Project: SQLite FreeBASIC port

    File: sqlite3_btmutex.bas

    Purpose:

        Manage recursive B-tree mutex ownership and cursor entry points.

    Responsibilities:

        - Lock shared BtShared mutexes in pointer order when later locks contend.
        - Track recursive Btree entry depth and the owning database connection.
        - Provide single-main-Btree enter-all/leave-all operations.
        - Check B-tree and schema mutex ownership in debug builds.

    This file intentionally does NOT contain:

        - Shared-cache table-lock policy or attached-database lock lists.
        - VFS or database transaction logic.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_mutex.bi"
#include once "sqlite3_btree.bi"

#ifndef SQLITE_THREADSAFE
#define SQLITE_THREADSAFE 1
#endif

/' ------------------------------------------------------------------------- '/
/' BtShared mutex acquisition '/
/' ------------------------------------------------------------------------- '/

Private Sub lockBtreeMutex CDecl Alias "lockBtreeMutex" (ByVal pBtree As Btree Ptr)
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Exit Sub
    sqlite3_mutex_enter(pBtree->pBt->mutex)
    pBtree->pBt->db = pBtree->db
    pBtree->locked = 1
End Sub

Private Sub unlockBtreeMutex CDecl Alias "unlockBtreeMutex" (ByVal pBtree As Btree Ptr)
    If pBtree = 0 OrElse pBtree->pBt = 0 OrElse pBtree->locked = 0 Then Exit Sub
    sqlite3_mutex_leave(pBtree->pBt->mutex)
    pBtree->locked = 0
End Sub

Private Sub btreeLockCarefully CDecl Alias "btreeLockCarefully" (ByVal pBtree As Btree Ptr)
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Exit Sub
    If sqlite3_mutex_try(pBtree->pBt->mutex) = SQLITE_OK Then
        pBtree->pBt->db = pBtree->db
        pBtree->locked = 1
        Exit Sub
    End If

    Dim pLater As Btree Ptr = CPtr(Btree Ptr, pBtree->pNext)
    While pLater <> 0
        If pLater->locked <> 0 Then unlockBtreeMutex(pLater)
        pLater = CPtr(Btree Ptr, pLater->pNext)
    Wend

    lockBtreeMutex(pBtree)
    pLater = CPtr(Btree Ptr, pBtree->pNext)
    While pLater <> 0
        If pLater->wantToLock > 0 Then lockBtreeMutex(pLater)
        pLater = CPtr(Btree Ptr, pLater->pNext)
    Wend
End Sub

Sub sqlite3BtreeEnter CDecl Alias "sqlite3BtreeEnter" (ByVal pBtree As Btree Ptr) Export
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return
#if SQLITE_THREADSAFE = 0
    pBtree->pBt->db = pBtree->db
#else
    If pBtree->sharable = 0 Then Return
    pBtree->wantToLock += 1
    If pBtree->locked <> 0 Then Return
    btreeLockCarefully(pBtree)
#endif
End Sub

Sub sqlite3BtreeLeave CDecl Alias "sqlite3BtreeLeave" (ByVal pBtree As Btree Ptr) Export
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return
#if SQLITE_THREADSAFE > 0
    If pBtree->sharable = 0 OrElse pBtree->wantToLock <= 0 Then Return
    pBtree->wantToLock -= 1
    If pBtree->wantToLock = 0 Then unlockBtreeMutex(pBtree)
#endif
End Sub

/' ------------------------------------------------------------------------- '/
/' Connection-wide entry points '/
/' ------------------------------------------------------------------------- '/

Private Sub btreeEnterAll CDecl Alias "btreeEnterAll" (ByVal db As sqlite3 Ptr)
    If db = 0 Then Return
    Dim noSharedCache As SQLITE_C_INT = 1
    For databaseIndex As SQLITE_C_INT = 0 To db->nDb - 1
        ' TEMP is connection-private. Other shared schemas must stay locked
        ' while prepare reads names and definitions from their catalogs.
        If databaseIndex <> 1 Then
            Dim pBtree As Btree Ptr = _
                CPtr(Btree Ptr, db->aDb(databaseIndex).pBt)
            If pBtree <> 0 AndAlso pBtree->sharable <> 0 Then
                sqlite3BtreeEnter(pBtree)
                noSharedCache = 0
            End If
        End If
    Next
    db->noSharedCache = CByte(noSharedCache)
End Sub

Sub sqlite3BtreeEnterAll CDecl Alias "sqlite3BtreeEnterAll" (ByVal db As sqlite3 Ptr) Export
    If db = 0 OrElse db->noSharedCache = 0 Then btreeEnterAll(db)
End Sub

Private Sub btreeLeaveAll CDecl Alias "btreeLeaveAll" (ByVal db As sqlite3 Ptr)
    If db = 0 Then Return
    For databaseIndex As SQLITE_C_INT = 0 To db->nDb - 1
        Dim pBtree As Btree Ptr = _
            CPtr(Btree Ptr, db->aDb(databaseIndex).pBt)
        If pBtree <> 0 Then sqlite3BtreeLeave(pBtree)
    Next
End Sub

Sub sqlite3BtreeLeaveAll CDecl Alias "sqlite3BtreeLeaveAll" (ByVal db As sqlite3 Ptr) Export
    If db = 0 OrElse db->noSharedCache = 0 Then btreeLeaveAll(db)
End Sub

#ifdef SQLITE_DEBUG
Function sqlite3BtreeHoldsMutex CDecl Alias "sqlite3BtreeHoldsMutex" ( _
    ByVal pBtree As Btree Ptr _
) As SQLITE_C_INT Export
    If pBtree = 0 Then Return 0
    Return CInt(pBtree->sharable = 0 OrElse pBtree->locked <> 0)
End Function

Function sqlite3BtreeHoldsAllMutexes CDecl Alias "sqlite3BtreeHoldsAllMutexes" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT Export
    If db = 0 OrElse sqlite3_mutex_held(db->mutex) = 0 Then Return 0
    Dim pBtree As Btree Ptr = CPtr(Btree Ptr, db->pMainBtree)
    If pBtree = 0 OrElse pBtree->sharable = 0 Then Return 1
    If pBtree->wantToLock <= 0 OrElse pBtree->locked = 0 Then Return 0
    Return sqlite3_mutex_held(pBtree->pBt->mutex)
End Function

Function sqlite3SchemaMutexHeld CDecl Alias "sqlite3SchemaMutexHeld" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal databaseIndex As SQLITE_C_INT, _
    ByVal pSchema As Any Ptr _
) As SQLITE_C_INT Export
    If db = 0 OrElse sqlite3_mutex_held(db->mutex) = 0 Then Return 0
    Dim pBtree As Btree Ptr = CPtr(Btree Ptr, db->pMainBtree)
    If pSchema <> 0 Then
        If databaseIndex <> 0 OrElse pBtree = 0 OrElse pBtree->pBt = 0 OrElse _
           pBtree->pBt->pSchema <> pSchema Then Return 0
    End If
    If databaseIndex = 1 Then Return 1
    If databaseIndex <> 0 Then Return 0
    If pBtree = 0 Then Return 1
    Return CInt(pBtree->sharable = 0 OrElse pBtree->locked <> 0)
End Function
#endif

#ifndef SQLITE_OMIT_INCRBLOB
Sub sqlite3BtreeEnterCursor CDecl Alias "sqlite3BtreeEnterCursor" (ByVal pCursor As BtCursor Ptr) Export
    If pCursor <> 0 Then sqlite3BtreeEnter(pCursor->pBtree)
End Sub

#if SQLITE_THREADSAFE > 0
Sub sqlite3BtreeLeaveCursor CDecl Alias "sqlite3BtreeLeaveCursor" (ByVal pCursor As BtCursor Ptr) Export
    If pCursor <> 0 Then sqlite3BtreeLeave(pCursor->pBtree)
End Sub
#endif
#endif

/' end of sqlite3_btmutex.bas '/
