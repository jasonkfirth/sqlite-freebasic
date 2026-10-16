/'
    Project: SQLite FreeBASIC port

    File: sqlite3_table.bas

    Purpose:

        Implement the legacy sqlite3_get_table() result-table API.

    Responsibilities:

        - Accumulate callback rows and column names into a flat array.
        - Preserve NULL cells and the header sentinel used by free_table().
        - Release every string and the result array through SQLite's allocator.

    This file intentionally does NOT contain:

        - SQL execution, which is delegated to sqlite3_exec().
'/ 

#lang "fb"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_mutex.bi"

Type SqliteGetTableCallback As Function CDecl ( _
    ByVal pArgument As Any Ptr, _
    ByVal columnCount As SQLITE_C_INT, _
    ByVal pValues As ZString Ptr Ptr, _
    ByVal pColumnNames As ZString Ptr Ptr _
) As SQLITE_C_INT

Type SqliteGetTableState
    pResult As ZString Ptr Ptr
    zError As ZString Ptr
    nAlloc As sqlite3_uint64
    nRow As sqlite3_uint64
    nColumn As SQLITE_C_INT
    nData As sqlite3_uint64
    rc As SQLITE_C_INT
End Type

Declare Function sqlite3SafetyCheckOk CDecl Alias "sqlite3SafetyCheckOk" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_exec CDecl Alias "sqlite3_exec" ( _
    ByVal pDatabase As Any Ptr, _
    ByVal zSql As Const ZString Ptr, _
    ByVal xCallback As Any Ptr, _
    ByVal pArgument As Any Ptr, _
    ByVal pzErrorMessage As ZString Ptr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_malloc64 CDecl Alias "sqlite3_malloc64" ( _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Function sqlite3_realloc64 CDecl Alias "sqlite3_realloc64" ( _
    ByVal pOld As Any Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)

Private Function sqlite3GetTableCopyText( _
    ByVal zText As Const ZString Ptr _
) As ZString Ptr
    If zText = 0 Then Return 0
    Return CPtr(ZString Ptr, sqlite3DbStrDup(0, zText))
End Function

Private Function sqlite3_get_table_cb CDecl ( _
    ByVal pArgument As Any Ptr, _
    ByVal columnCount As SQLITE_C_INT, _
    ByVal pValues As ZString Ptr Ptr, _
    ByVal pColumnNames As ZString Ptr Ptr _
) As SQLITE_C_INT
    If pArgument = 0 Then Return 1
    Dim pState As SqliteGetTableState Ptr = _
        CPtr(SqliteGetTableState Ptr, pArgument)
    If columnCount < 0 Then
        pState->rc = SQLITE_CORRUPT
        Return 1
    End If
    If pState->nRow > 0 AndAlso pState->nColumn <> columnCount Then
        pState->zError = sqlite3GetTableCopyText(StrPtr( _
            "sqlite3_get_table() called with incompatible result columns"))
        pState->rc = IIf(pState->zError = 0, SQLITE_NOMEM, SQLITE_ERROR)
        Return 1
    End If

    Dim slotsNeeded As sqlite3_uint64 = CULngInt(columnCount)
    If pState->nRow = 0 AndAlso pValues <> 0 Then
        If slotsNeeded > SQLITE_MAX_ALLOCATION_SIZE \ SizeOf(Any Ptr) \ 2 Then
            pState->rc = SQLITE_TOOBIG
            Return 1
        End If
        slotsNeeded *= 2
    End If
    If slotsNeeded > SQLITE_MAX_ALLOCATION_SIZE \ SizeOf(Any Ptr) OrElse _
       pState->nData > SQLITE_MAX_ALLOCATION_SIZE \ SizeOf(Any Ptr) - slotsNeeded Then
        pState->rc = SQLITE_TOOBIG
        Return 1
    End If
    Dim slotsRequired As sqlite3_uint64 = pState->nData + slotsNeeded
    If slotsRequired > pState->nAlloc Then
        Dim newAllocation As sqlite3_uint64 = pState->nAlloc * 2 + slotsNeeded
        If newAllocation < slotsRequired OrElse _
           newAllocation > SQLITE_MAX_ALLOCATION_SIZE \ SizeOf(Any Ptr) Then
            pState->rc = SQLITE_TOOBIG
            Return 1
        End If
        Dim pNew As ZString Ptr Ptr = CPtr(ZString Ptr Ptr, _
            sqlite3_realloc64(pState->pResult, _
                newAllocation * SizeOf(Any Ptr)))
        If pNew = 0 Then
            pState->rc = SQLITE_NOMEM
            Return 1
        End If
        pState->pResult = pNew
        pState->nAlloc = newAllocation
    End If

    If pState->nRow = 0 AndAlso pValues <> 0 Then
        pState->nColumn = columnCount
        For iColumn As SQLITE_C_INT = 0 To columnCount - 1
            Dim zName As Const ZString Ptr = pColumnNames[iColumn]
            Dim zCopy As ZString Ptr = sqlite3GetTableCopyText(zName)
            If zName <> 0 AndAlso zCopy = 0 Then
                pState->rc = SQLITE_NOMEM
                Return 1
            End If
            pState->pResult[pState->nData] = zCopy
            pState->nData += 1
        Next
    End If

    If pValues <> 0 Then
        For iColumn As SQLITE_C_INT = 0 To columnCount - 1
            Dim zCopy As ZString Ptr = sqlite3GetTableCopyText(pValues[iColumn])
            If pValues[iColumn] <> 0 AndAlso zCopy = 0 Then
                pState->rc = SQLITE_NOMEM
                Return 1
            End If
            pState->pResult[pState->nData] = zCopy
            pState->nData += 1
        Next
        If pState->nRow >= &H7FFFFFFF Then
            pState->rc = SQLITE_TOOBIG
            Return 1
        End If
        pState->nRow += 1
    End If
    Return 0
End Function

Sub sqlite3_free_table CDecl Alias "sqlite3_free_table" ( _
    ByVal pResultArgument As ZString Ptr Ptr _
) Export
    If pResultArgument = 0 Then Return
    Dim pBase As ZString Ptr Ptr = pResultArgument - 1
    Dim nData As sqlite3_uint64 = CULngInt(CPtr(Any Ptr, pBase[0]))
    If nData < 1 OrElse _
       nData > SQLITE_MAX_ALLOCATION_SIZE \ SizeOf(Any Ptr) Then Return
    For iData As sqlite3_uint64 = 1 To nData - 1
        If pBase[iData] <> 0 Then sqlite3_free(pBase[iData])
    Next
    sqlite3_free(pBase)
End Sub

Function sqlite3_get_table CDecl Alias "sqlite3_get_table" ( _
    ByVal pDatabase As Any Ptr, _
    ByVal zSql As Const ZString Ptr, _
    ByVal ppResult As ZString Ptr Ptr Ptr, _
    ByVal pRowCount As SQLITE_C_INT Ptr, _
    ByVal pColumnCount As SQLITE_C_INT Ptr, _
    ByVal pzErrorMessage As ZString Ptr Ptr _
) As SQLITE_C_INT Export
    If CPtr(Any Ptr, pzErrorMessage) <> 0 Then pzErrorMessage[0] = 0
    If CPtr(Any Ptr, pRowCount) <> 0 Then pRowCount[0] = 0
    If CPtr(Any Ptr, pColumnCount) <> 0 Then pColumnCount[0] = 0
    If CPtr(Any Ptr, ppResult) <> 0 Then ppResult[0] = 0
    If pDatabase = 0 OrElse ppResult = 0 Then Return SQLITE_MISUSE

    Dim db As sqlite3 Ptr = CPtr(sqlite3 Ptr, pDatabase)
    If sqlite3SafetyCheckOk(db) = 0 Then
        db->errorCode = SQLITE_MISUSE
        Return SQLITE_MISUSE
    End If

    Dim state As SqliteGetTableState
    state.pResult = CPtr(ZString Ptr Ptr, sqlite3_malloc64( _
        20 * SizeOf(Any Ptr)))
    state.zError = 0
    state.nAlloc = 20
    state.nRow = 0
    state.nColumn = 0
    state.nData = 1
    state.rc = SQLITE_OK
    If state.pResult = 0 Then
        db->errorCode = SQLITE_NOMEM
        Return SQLITE_NOMEM
    End If
    state.pResult[0] = 0

    Dim resultCode As SQLITE_C_INT = sqlite3_exec( _
        db, zSql, @sqlite3_get_table_cb, @state, pzErrorMessage)
    state.pResult[0] = CPtr(ZString Ptr, state.nData)

    If (resultCode And &HFF) = SQLITE_ABORT Then
        sqlite3_free_table(@state.pResult[1])
        Dim errorCopyFailed As SQLITE_C_INT = 0
        If state.zError <> 0 Then
            If CPtr(Any Ptr, pzErrorMessage) <> 0 AndAlso pzErrorMessage[0] <> 0 Then _
                sqlite3_free(pzErrorMessage[0])
            If CPtr(Any Ptr, pzErrorMessage) <> 0 Then
                pzErrorMessage[0] = sqlite3GetTableCopyText(state.zError)
                If pzErrorMessage[0] = 0 Then errorCopyFailed = 1
            End If
            sqlite3_free(state.zError)
            state.zError = 0
        End If
        resultCode = IIf(state.rc = SQLITE_OK, SQLITE_ABORT, state.rc)
        If errorCopyFailed <> 0 Then resultCode = SQLITE_NOMEM
        db->errorCode = resultCode
        Return resultCode
    End If

    If state.zError <> 0 Then sqlite3_free(state.zError)
    If resultCode <> SQLITE_OK Then
        sqlite3_free_table(@state.pResult[1])
        Return resultCode
    End If

    If state.nAlloc > state.nData Then
        Dim pNew As ZString Ptr Ptr = CPtr(ZString Ptr Ptr, _
            sqlite3_realloc64(state.pResult, state.nData * SizeOf(Any Ptr)))
        If pNew = 0 Then
            sqlite3_free_table(@state.pResult[1])
            db->errorCode = SQLITE_NOMEM
            Return SQLITE_NOMEM
        End If
        state.pResult = pNew
    End If
    state.pResult[0] = CPtr(ZString Ptr, state.nData)
    ppResult[0] = @state.pResult[1]
    If pRowCount <> 0 Then pRowCount[0] = CInt(state.nRow)
    If pColumnCount <> 0 Then pColumnCount[0] = state.nColumn
    db->errorCode = SQLITE_OK
    Return SQLITE_OK
End Function

/' end of sqlite3_table.bas '/
