/'
    Project: SQLite FreeBASIC port

    File: sqlite3_bulk_feature_preupdate_api.bas

    Purpose:

        Provide the pre-update state producer and inspection API callbacks.

    Responsibilities:

        - Build and clean up the callback-scoped PreUpdate state.
        - Report the current row's column count and trigger depth.
        - Report the column affected by sqlite3_blob_write().
        - Compile these routines only with SQLITE_ENABLE_PREUPDATE_HOOK.

    This file intentionally does NOT contain:

        - Pre-update callback registration.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_api_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_preupdate_types.bi"

#ifdef SQLITE_ENABLE_PREUPDATE_HOOK
Type SqlitePreUpdateCallbackProc As Sub CDecl ( _
    ByVal pArgument As Any Ptr, _
    ByVal db As sqlite3 Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal zDatabase As Const ZString Ptr, _
    ByVal zTable As Const ZString Ptr, _
    ByVal oldRowid As sqlite3_int64, _
    ByVal newRowid As sqlite3_int64 _
)

Declare Function sqlite3PreupdatePrimaryKeyIndex CDecl Alias "sqlite3PrimaryKeyIndex" ( _
    ByVal pTable As SqliteTable Ptr _
) As SqliteIndex Ptr
Declare Sub vdbeFreeUnpacked CDecl Alias "vdbeFreeUnpacked" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal fieldCount As SQLITE_C_INT, _
    ByVal pRecord As sqlite3VdbeUnpackedRecord Ptr _
)
Declare Function sqlite3PreupdateMemset CDecl Alias "memset" ( _
    ByVal pTarget As Any Ptr, _
    ByVal value As SQLITE_C_INT, _
    ByVal nByte As SQLITE_SIZE_T _
) As Any Ptr

Function sqlite3_preupdate_count CDecl Alias "sqlite3_preupdate_count" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT Export
    If db = 0 OrElse db->pPreUpdate = 0 Then Return 0
    Dim pUpdate As SqlitePreUpdateApiState Ptr = _
        CPtr(SqlitePreUpdateApiState Ptr, db->pPreUpdate)
    If pUpdate->pKeyinfo = 0 Then Return 0
    Return CInt(pUpdate->pKeyinfo->nKeyField)
End Function

Function sqlite3_preupdate_depth CDecl Alias "sqlite3_preupdate_depth" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT Export
    If db = 0 OrElse db->pPreUpdate = 0 Then Return 0
    Dim pUpdate As SqlitePreUpdateApiState Ptr = _
        CPtr(SqlitePreUpdateApiState Ptr, db->pPreUpdate)
    If pUpdate->v = 0 Then Return 0
    Return pUpdate->v->nFrame
End Function

Function sqlite3_preupdate_blobwrite CDecl Alias "sqlite3_preupdate_blobwrite" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT Export
    If db = 0 OrElse db->pPreUpdate = 0 Then Return -1
    Dim pUpdate As SqlitePreUpdateApiState Ptr = _
        CPtr(SqlitePreUpdateApiState Ptr, db->pPreUpdate)
    Return pUpdate->iBlobWrite
End Function

Sub sqlite3VdbePreUpdateHook CDecl Alias "sqlite3VdbePreUpdateHook" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pCursor As SqliteVdbeCursor Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal zDatabase As Const ZString Ptr, _
    ByVal pTable As SqliteTable Ptr, _
    ByVal oldRowid As sqlite3_int64, _
    ByVal newValueRegister As SQLITE_C_INT, _
    ByVal blobWriteColumn As SQLITE_C_INT _
)
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse pCursor = 0 OrElse _
       pTable = 0 Then Return
    Dim db As sqlite3 Ptr = pVdbe->db
    If db->xPreUpdateCallback = 0 OrElse db->pPreUpdate <> 0 Then Return

    Dim key2 As sqlite3_int64 = oldRowid
    Dim pPrimaryKey As SqliteIndex Ptr = 0
    If (pTable->tabFlags And TF_WithoutRowid) <> 0 Then
        oldRowid = 0
        key2 = 0
        pPrimaryKey = sqlite3PreupdatePrimaryKeyIndex(pTable)
        If pPrimaryKey = 0 Then Return
    ElseIf operation = SQLITE_UPDATE Then
        If newValueRegister < 0 OrElse newValueRegister >= pVdbe->nMem OrElse _
           pVdbe->aMem = 0 Then Return
        key2 = pVdbe->aMem[newValueRegister].u.i
    End If

    Dim preupdate As SqlitePreUpdateApiState
    sqlite3PreupdateMemset(@preupdate, 0, SizeOf(preupdate))
    preupdate.v = pVdbe
    preupdate.pCsr = pCursor
    preupdate.op = operation
    preupdate.iNewReg = newValueRegister
    preupdate.pKeyinfo = @preupdate.uKey
    preupdate.pKeyinfo->db = db
    preupdate.pKeyinfo->enc = db->enc
    preupdate.pKeyinfo->nKeyField = CShort(pTable->nCol)
    ' A null sort-flags pointer marks the inline key-info cache as uninitialized.
    preupdate.pKeyinfo->aSortFlags = 0
    preupdate.iKey1 = oldRowid
    preupdate.iKey2 = key2
    preupdate.pTab = pTable
    preupdate.pPk = pPrimaryKey
    preupdate.iBlobWrite = blobWriteColumn

    db->pPreUpdate = @preupdate
    Dim xPreUpdate As SqlitePreUpdateCallbackProc = _
        CPtr(SqlitePreUpdateCallbackProc, db->xPreUpdateCallback)
    xPreUpdate(db->pPreUpdateArg, db, operation, zDatabase, pTable->zName, _
               oldRowid, key2)
    db->pPreUpdate = 0

    sqlite3DbFree(db, preupdate.aRecord)
    vdbeFreeUnpacked(db, preupdate.pKeyinfo->nKeyField + 1, preupdate.pUnpacked)
    vdbeFreeUnpacked(db, preupdate.pKeyinfo->nKeyField + 1, preupdate.pNewUnpacked)
    sqlite3VdbeMemRelease(@preupdate.oldipk)
    If preupdate.aNew <> 0 Then
        For fieldIndex As SQLITE_C_INT = 0 To pCursor->nField - 1
            sqlite3VdbeMemRelease(@preupdate.aNew[fieldIndex])
        Next
        sqlite3DbFree(db, preupdate.aNew)
    End If
    If preupdate.apDflt <> 0 Then
        For columnIndex As SQLITE_C_INT = 0 To pTable->nCol - 1
            sqlite3ValueFree(preupdate.apDflt[columnIndex])
        Next
        sqlite3DbFree(db, preupdate.apDflt)
    End If
End Sub
#endif

/' end of sqlite3_bulk_feature_preupdate_api.bas '/
