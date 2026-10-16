/'
    Project: SQLite FreeBASIC port

    File: sqlite3_exec.bas

    Purpose:

        Implement the public one-step SQL execution wrapper.

    Responsibilities:

        - Prepare and execute each statement in a semicolon-separated buffer.
        - Invoke the caller's row callback with column values and names.
        - Stop before callbacks if a column text conversion fails from OOM.
        - Stop on errors or callback cancellation and return an allocated error.

    This file intentionally does NOT contain:

        - SQL compilation, result formatting, or Tcl test support.
'/ 

#lang "fb"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_api_constants.bi"
#include once "sqlite3_mutex.bi"

Type SqliteExecCallback As Function CDecl ( _
    ByVal pArgument As Any Ptr, _
    ByVal columnCount As SQLITE_C_INT, _
    ByVal pValues As ZString Ptr Ptr, _
    ByVal pColumnNames As ZString Ptr Ptr _
) As SQLITE_C_INT

Declare Function sqlite3SafetyCheckOk CDecl Alias "sqlite3SafetyCheckOk" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_errmsg CDecl Alias "sqlite3_errmsg" ( _
    ByVal pDatabase As Any Ptr _
) As Const ZString Ptr
Declare Function sqlite3ErrStr CDecl Alias "sqlite3ErrStr" ( _
    ByVal resultCode As SQLITE_C_INT _
) As Const ZString Ptr
Declare Function sqlite3_prepare_v2 CDecl Alias "sqlite3_prepare_v2" ( _
    ByVal pDatabase As Any Ptr, _
    ByVal zSql As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal ppStatement As Any Ptr Ptr, _
    ByVal pzTail As Const ZString Ptr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_step CDecl Alias "sqlite3_step" ( _
    ByVal pStatement As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_finalize CDecl Alias "sqlite3_finalize" ( _
    ByVal pStatement As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_column_count CDecl Alias "sqlite3_column_count" ( _
    ByVal pStatement As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_column_name CDecl Alias "sqlite3_column_name" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As Const ZString Ptr
Declare Function sqlite3_column_text CDecl Alias "sqlite3_column_text" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As Const UByte Ptr
Declare Function sqlite3_column_type CDecl Alias "sqlite3_column_type" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3_malloc64 CDecl Alias "sqlite3_malloc64" ( _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)

Private Function sqlite3ExecErrorCopy( _
    ByVal db As sqlite3 Ptr, _
    ByVal resultCode As SQLITE_C_INT _
) As ZString Ptr
    If db = 0 Then Return 0
    Dim zMessage As Const ZString Ptr = sqlite3_errmsg(db)
    If zMessage = 0 Then zMessage = sqlite3ErrStr(resultCode)
    Return CPtr(ZString Ptr, sqlite3DbStrDup(0, zMessage))
End Function

Function sqlite3_exec CDecl Alias "sqlite3_exec" ( _
    ByVal pDatabase As Any Ptr, _
    ByVal zSql As Const ZString Ptr, _
    ByVal xCallbackArgument As Any Ptr, _
    ByVal pCallbackArgument As Any Ptr, _
    ByVal pzErrorMessage As ZString Ptr Ptr _
) As SQLITE_C_INT Export
    If CPtr(Any Ptr, pzErrorMessage) <> 0 Then pzErrorMessage[0] = 0
    If pDatabase = 0 Then Return SQLITE_MISUSE
    Dim db As sqlite3 Ptr = CPtr(sqlite3 Ptr, pDatabase)
    If sqlite3SafetyCheckOk(db) = 0 Then
        db->errorCode = SQLITE_MISUSE
        Return SQLITE_MISUSE
    End If
    If zSql = 0 Then zSql = StrPtr("")

    Dim xCallback As SqliteExecCallback = CPtr(SqliteExecCallback, xCallbackArgument)
    Dim resultCode As SQLITE_C_INT = SQLITE_OK
    Dim pStatement As Any Ptr = 0
    Dim pValues As ZString Ptr Ptr = 0
    Dim pColumnNames As ZString Ptr Ptr = 0
    Dim arrayBytes As sqlite3_uint64 = 0
    Dim stopAfterCallback As SQLITE_C_INT = 0
    Dim zCurrent As Const ZString Ptr = zSql

    sqlite3_mutex_enter(db->mutex)
    db->errorCode = SQLITE_OK

    While resultCode = SQLITE_OK AndAlso zCurrent[0] <> 0
        Dim zTail As Const ZString Ptr = zCurrent
        pStatement = 0
        resultCode = sqlite3_prepare_v2( _
            db, zCurrent, -1, @pStatement, @zTail)
        If resultCode <> SQLITE_OK Then Exit While
        If zTail = 0 OrElse CPtr(Const UByte Ptr, zTail) < _
           CPtr(Const UByte Ptr, zCurrent) Then
            resultCode = SQLITE_CORRUPT
            Exit While
        End If
        If zTail = zCurrent Then
            If pStatement <> 0 Then
                resultCode = SQLITE_CORRUPT
                Exit While
            End If
            Exit While
        End If

        If pStatement = 0 Then
            zCurrent = zTail
            Continue While
        End If

        Dim columnCount As SQLITE_C_INT = sqlite3_column_count(pStatement)
        If columnCount < 0 Then
            resultCode = SQLITE_CORRUPT
            Exit While
        End If
        If xCallback <> 0 Then
            Dim pointerCount As sqlite3_uint64 = CULngInt(columnCount) + 1
            If pointerCount > SQLITE_MAX_ALLOCATION_SIZE / SizeOf(Any Ptr) Then
                resultCode = SQLITE_TOOBIG
                Exit While
            End If
            arrayBytes = pointerCount * SizeOf(Any Ptr)
        End If

        While resultCode = SQLITE_OK
            Dim stepCode As SQLITE_C_INT = sqlite3_step(pStatement)
            If stepCode = SQLITE_ROW Then
                If xCallback <> 0 Then
                    If pValues = 0 Then
                        pValues = CPtr(ZString Ptr Ptr, sqlite3_malloc64(arrayBytes))
                        pColumnNames = CPtr(ZString Ptr Ptr, sqlite3_malloc64(arrayBytes))
                        If pValues = 0 OrElse pColumnNames = 0 Then
                            resultCode = SQLITE_NOMEM
                            Exit While
                        End If
                        For iColumn As SQLITE_C_INT = 0 To columnCount - 1
                            Dim zName As Const ZString Ptr = _
                                sqlite3_column_name(pStatement, iColumn)
                            If zName = 0 Then zName = StrPtr("")
                            pColumnNames[iColumn] = CPtr(ZString Ptr, zName)
                        Next
                        pColumnNames[columnCount] = 0
                    End If
                    For iColumn As SQLITE_C_INT = 0 To columnCount - 1
                        Dim zValue As Const UByte Ptr = _
                            sqlite3_column_text(pStatement, iColumn)
                        If zValue = 0 Then
                            Dim pVdbe As SqliteVdbe Ptr = _
                                CPtr(SqliteVdbe Ptr, pStatement)
                            ' A failed text conversion can clear the Mem cell to
                            ' NULL. Check its error state before treating NULL
                            ' as a real SQL NULL for the row callback.
                            If db->mallocFailed <> 0 OrElse _
                               (pVdbe <> 0 AndAlso _
                                (pVdbe->rc And &HFF) = SQLITE_NOMEM) Then
                                resultCode = SQLITE_NOMEM
                                Exit For
                            End If
                            If sqlite3_column_type(pStatement, iColumn) <> SQLITE_NULL Then
                                resultCode = SQLITE_NOMEM
                                Exit For
                            End If
                        End If
                        pValues[iColumn] = CPtr(ZString Ptr, zValue)
                    Next
                    If resultCode <> SQLITE_OK Then Exit While
                    pValues[columnCount] = 0
                    If xCallback(pCallbackArgument, columnCount, _
                                 pValues, pColumnNames) <> 0 Then
                        resultCode = SQLITE_ABORT
                        stopAfterCallback = 1
                        Exit While
                    End If
                End If
                Continue While
            End If

            Dim finalizeCode As SQLITE_C_INT = sqlite3_finalize(pStatement)
            pStatement = 0
            If stepCode = SQLITE_DONE Then
                If finalizeCode = SQLITE_OK Then
                    resultCode = SQLITE_OK
                Else
                    resultCode = finalizeCode
                End If
            ElseIf finalizeCode <> SQLITE_OK Then
                resultCode = finalizeCode
            Else
                resultCode = stepCode
            End If
            zCurrent = zTail
            Exit While
        Wend

        If pStatement <> 0 Then
            sqlite3_finalize(pStatement)
            pStatement = 0
        End If
        If pValues <> 0 Then sqlite3_free(pValues)
        If pColumnNames <> 0 Then sqlite3_free(pColumnNames)
        pValues = 0
        pColumnNames = 0
        If stopAfterCallback <> 0 Then Exit While
    Wend

    If pStatement <> 0 Then sqlite3_finalize(pStatement)
    If pValues <> 0 Then sqlite3_free(pValues)
    If pColumnNames <> 0 Then sqlite3_free(pColumnNames)
    db->errorCode = resultCode
    resultCode = sqlite3ApiExit(db, resultCode)
    If resultCode <> SQLITE_OK AndAlso CPtr(Any Ptr, pzErrorMessage) <> 0 Then
        pzErrorMessage[0] = sqlite3ExecErrorCopy(db, resultCode)
        If pzErrorMessage[0] = 0 Then
            resultCode = SQLITE_NOMEM
            db->errorCode = resultCode
        End If
    End If
    sqlite3_mutex_leave(db->mutex)
    Return resultCode
End Function

/' end of sqlite3_exec.bas '/
