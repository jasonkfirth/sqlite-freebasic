/'
    Project: SQLite FreeBASIC port

    File: sqlite3_errors.bas

    Purpose:

        Port SQLite's error-state helpers and sqlite3_errstr() API.

    Responsibilities:

        - Map primary and selected extended result codes to stable messages.
        - Return pointers to process-lifetime, NUL-terminated strings.
        - Expose the current error message as UTF-16 when requested.
        - Format caller-supplied error messages through SQLite's printf layer.
        - Set or clear the active per-connection error value and code.
        - Hand an error code to the active SQL parse context when present.
        - Invoke the per-connection progress callback while parsing SQL.
        - Record the byte offset of a token in the active SQL input.
        - Capture the VFS error number for file-open and I/O failures.
        - Log low-level corruption, misuse, open, and allocation failures with source context.

    This file intentionally does NOT contain:

        - Parser grammar-specific diagnostic construction in sqlite3ErrorMsg.
        - Message localization or error-code generation.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_vfs.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_vdbe_mem_text.bi"

Private Const SQLITE_ERROR_MESSAGE_LIMIT As SQLITE_C_INT = 64

Declare Function sqlite3SafetyCheckSickOrOk CDecl Alias "sqlite3SafetyCheckSickOrOk" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT

Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" (ByVal z As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3VMPrintf CDecl Alias "sqlite3VMPrintf" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ByRef sourceArgs As Cva_List _
) As ZString Ptr
Declare Function sqlite3_sourceid CDecl Alias "sqlite3_sourceid" () As Const ZString Ptr
Declare Sub sqlite3_log CDecl Alias "sqlite3_log" ( _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Function sqlite3_snprintf CDecl Alias "sqlite3_snprintf" ( _
    ByVal bufferSize As SQLITE_C_INT, _
    ByVal zBuffer As ZString Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) As ZString Ptr

Dim Shared As ZString * SQLITE_ERROR_MESSAGE_LIMIT sqlite3ErrorMessages(0 To 28) = _
    { _
        "not an error", _
        "SQL logic error", _
        "", _
        "access permission denied", _
        "query aborted", _
        "database is locked", _
        "database table is locked", _
        "out of memory", _
        "attempt to write a readonly database", _
        "interrupted", _
        "disk I/O error", _
        "database disk image is malformed", _
        "unknown operation", _
        "database or disk is full", _
        "unable to open database file", _
        "locking protocol", _
        "", _
        "database schema has changed", _
        "string or blob too big", _
        "constraint failed", _
        "datatype mismatch", _
        "bad parameter or other API misuse", _
        "", _
        "authorization denied", _
        "", _
        "column index out of range", _
        "file is not a database", _
        "notification message", _
        "warning message" _
    }

Dim Shared As ZString * SQLITE_ERROR_MESSAGE_LIMIT sqlite3UnknownError = "unknown error"
Dim Shared As ZString * SQLITE_ERROR_MESSAGE_LIMIT sqlite3AbortRollbackError = "abort due to ROLLBACK"
Dim Shared As ZString * SQLITE_ERROR_MESSAGE_LIMIT sqlite3RowAvailableError = "another row available"
Dim Shared As ZString * SQLITE_ERROR_MESSAGE_LIMIT sqlite3DoneError = "no more rows available"
#ifndef SQLITE_OMIT_UTF16
Dim Shared As Const UShort sqlite3ErrorOutOfMemory16(0 To 13) = _
    {111, 117, 116, 32, 111, 102, 32, 109, 101, 109, 111, 114, 121, 0}
Dim Shared As Const UShort sqlite3ErrorMisuse16(0 To 33) = _
    {98, 97, 100, 32, 112, 97, 114, 97, 109, 101, 116, 101, 114, 32, _
     111, 114, 32, 111, 116, 104, 101, 114, 32, 65, 80, 73, 32, _
     109, 105, 115, 117, 115, 101, 0}
#endif

Function sqlite3ErrStr CDecl Alias "sqlite3ErrStr" ( _
    ByVal resultCode As SQLITE_C_INT _
) As Const ZString Ptr Export

    If resultCode = SQLITE_ABORT_ROLLBACK Then Return @sqlite3AbortRollbackError
    If resultCode = SQLITE_ROW Then Return @sqlite3RowAvailableError
    If resultCode = SQLITE_DONE Then Return @sqlite3DoneError

    Dim primaryCode As SQLITE_C_INT = resultCode And &HFF
    If primaryCode >= 0 AndAlso primaryCode <= 28 Then
        If sqlite3ErrorMessages(primaryCode)[0] <> 0 Then
            Return @sqlite3ErrorMessages(primaryCode)
        End If
    End If
    Return @sqlite3UnknownError
End Function

Function sqlite3_errstr CDecl Alias "sqlite3_errstr" ( _
    ByVal resultCode As SQLITE_C_INT _
) As Const ZString Ptr Export
    Return sqlite3ErrStr(resultCode)
End Function

#ifndef SQLITE_OMIT_UTF16
Function sqlite3_errmsg16 CDecl Alias "sqlite3_errmsg16" ( _
    ByVal db As sqlite3 Ptr _
) As Any Ptr Export
    If db = 0 Then Return CPtr(Any Ptr, @sqlite3ErrorOutOfMemory16(0))
    If sqlite3SafetyCheckSickOrOk(db) = 0 Then _
        Return CPtr(Any Ptr, @sqlite3ErrorMisuse16(0))

    sqlite3_mutex_enter(db->mutex)
    Dim zMessage As Any Ptr
    If db->mallocFailed <> 0 Then
        zMessage = CPtr(Any Ptr, @sqlite3ErrorOutOfMemory16(0))
    Else
        zMessage = sqlite3ValueText(db->pErr, SQLITE_UTF16NATIVE)
        If zMessage = 0 Then
            sqlite3ErrorWithMsg(db, db->errorCode, sqlite3ErrStr(db->errorCode))
            zMessage = sqlite3ValueText(db->pErr, SQLITE_UTF16NATIVE)
        End If
        sqlite3OomClear(db)
    End If
    sqlite3_mutex_leave(db->mutex)
    Return zMessage
End Function
#endif

Function sqlite3ErrorToParser CDecl Alias "sqlite3ErrorToParser" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal errorCode As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If db = 0 OrElse db->pParse = 0 Then Return errorCode
    Dim pParse As SqliteParseContext Ptr = CPtr(SqliteParseContext Ptr, db->pParse)
    pParse->rc = errorCode
    If pParse->nErr < &H7FFFFFFF Then pParse->nErr += 1
    Return errorCode
End Function

Sub sqlite3SystemError CDecl Alias "sqlite3SystemError" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal resultCode As SQLITE_C_INT _
) Export
    If db = 0 OrElse resultCode = SQLITE_IOERR_NOMEM Then Return
    Dim primaryCode As SQLITE_C_INT = resultCode And &HFF
    If primaryCode = SQLITE_CANTOPEN OrElse primaryCode = SQLITE_IOERR Then
        db->iSysErrno = sqlite3OsGetLastError(CPtr(sqlite3_vfs Ptr, db->pVfs))
    End If
End Sub

Private Sub sqlite3ErrorFinish(ByVal db As sqlite3 Ptr, ByVal errorCode As SQLITE_C_INT)
    If db->pErr <> 0 Then sqlite3ValueSetNull(db->pErr)
    sqlite3SystemError(db, errorCode)
End Sub

Sub sqlite3Error CDecl Alias "sqlite3Error" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal errorCode As SQLITE_C_INT _
) Export
    If db = 0 Then Return
    db->errorCode = errorCode
    If errorCode <> SQLITE_OK OrElse db->pErr <> 0 Then
        sqlite3ErrorFinish(db, errorCode)
    Else
        db->errByteOffset = -1
    End If
End Sub

Sub sqlite3ErrorClear CDecl Alias "sqlite3ErrorClear" ( _
    ByVal db As sqlite3 Ptr _
) Export
    If db = 0 Then Return
    db->errorCode = SQLITE_OK
    db->errByteOffset = -1
    If db->pErr <> 0 Then sqlite3ValueSetNull(db->pErr)
End Sub

Sub sqlite3ErrorWithMsg CDecl Alias "sqlite3ErrorWithMsg" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) Export
    If db = 0 Then Return
    db->errorCode = errorCode
    sqlite3SystemError(db, errorCode)
    If zFormat = 0 Then
        sqlite3Error(db, errorCode)
        Return
    End If

    If db->pErr = 0 Then db->pErr = sqlite3ValueNew(db)
    If db->pErr = 0 Then Return

    Dim args As Cva_List
    Cva_Start(args, zFormat)
    Dim zMessage As ZString Ptr = sqlite3VMPrintf(db, zFormat, args)
    Cva_End(args)

    Dim pErrorValue As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, db->pErr)
    Dim transientDestructor As sqlite3MemDestructor = _
        CPtr(sqlite3MemDestructor, -1)
    sqlite3VdbeMemSetStr(pErrorValue, zMessage, -1, SQLITE_UTF8, transientDestructor)
    sqlite3DbFree(db, zMessage)
End Sub

Sub sqlite3ErrorMsg CDecl Alias "sqlite3ErrorMsg" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) Export
    If pParse = 0 OrElse pParse->db = 0 OrElse zFormat = 0 Then Return
    Dim db As sqlite3 Ptr = pParse->db
    db->errByteOffset = -2

    Dim args As Cva_List
    Cva_Start(args, zFormat)
    Dim zMessage As ZString Ptr = sqlite3VMPrintf(db, zFormat, args)
    Cva_End(args)
    If db->errByteOffset < -1 Then db->errByteOffset = -1

    If db->suppressErr <> 0 Then
        sqlite3DbFree(db, zMessage)
        If db->mallocFailed <> 0 Then
            If pParse->nErr < &H7FFFFFFF Then pParse->nErr += 1
            pParse->rc = SQLITE_NOMEM
        End If
        Return
    End If

    If pParse->nErr < &H7FFFFFFF Then pParse->nErr += 1
    sqlite3DbFree(db, pParse->zErrMsg)
    pParse->zErrMsg = zMessage
    If db->mallocFailed <> 0 Then
        pParse->rc = SQLITE_NOMEM
    Else
        pParse->rc = SQLITE_ERROR
    End If
    pParse->pWith = 0
End Sub

Sub sqlite3ProgressCheck CDecl Alias "sqlite3ProgressCheck" ( _
    ByVal pParse As SqliteParseContext Ptr _
)
    If pParse = 0 OrElse pParse->db = 0 Then Return
    Dim db As sqlite3 Ptr = pParse->db
    ' sqlite3_interrupt() updates this flag under interruptMutex so it can
    ' signal a running parser without taking the connection mutex.
    If sqlite3InterruptPending(db) <> 0 Then
        If pParse->nErr < &H7FFFFFFF Then pParse->nErr += 1
        pParse->rc = SQLITE_INTERRUPT
    End If
    If pParse->rc = SQLITE_INTERRUPT Then
        pParse->nProgressSteps = 0
        Return
    End If
#ifndef SQLITE_OMIT_PROGRESS_CALLBACK
    If db->xProgress = 0 OrElse db->nProgressOps = 0 Then Return
    If pParse->nProgressSteps < &H7FFFFFFF Then pParse->nProgressSteps += 1
    If CULng(pParse->nProgressSteps) >= db->nProgressOps Then
        Dim xProgress As SqliteProgressCallback = db->xProgress
        If xProgress(db->pProgressArg) <> 0 Then
            If pParse->nErr < &H7FFFFFFF Then pParse->nErr += 1
            pParse->rc = SQLITE_INTERRUPT
        End If
        pParse->nProgressSteps = 0
    End If
#endif
End Sub

Sub sqlite3RecordErrorByteOffset CDecl Alias "sqlite3RecordErrorByteOffset" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zToken As Const ZString Ptr _
) Export

    If db = 0 OrElse zToken = 0 OrElse db->errByteOffset <> -2 OrElse db->pParse = 0 Then Return
    Dim pParse As SqliteParseContext Ptr = CPtr(SqliteParseContext Ptr, db->pParse)
    If pParse->zSql = 0 Then Return

    Dim inputLength As LongInt = sqlite3Strlen30(pParse->zSql)
    Dim byteOffset As LongInt = CPtr(Const UByte Ptr, zToken) - CPtr(Const UByte Ptr, pParse->zSql)
    If byteOffset >= 0 AndAlso byteOffset <= inputLength Then db->errByteOffset = CLng(byteOffset)
End Sub

/' ------------------------------------------------------------------------- '/
/' Low-level error-site reporters                                            '/
/' ------------------------------------------------------------------------- '/

Function sqlite3ReportError CDecl Alias "sqlite3ReportError" ( _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal lineNumber As SQLITE_C_INT, _
    ByVal errorType As Const ZString Ptr _
) As SQLITE_C_INT Export
    If errorType = 0 Then Return errorCode

    ' The source identifier stores its 40-character check-in id after 20 bytes.
    Dim sourceId As Const UByte Ptr = _
        CPtr(Const UByte Ptr, sqlite3_sourceid()) + 20
    sqlite3_log(errorCode, StrPtr("%s at line %d of [%.10s]"), _
                errorType, lineNumber, CPtr(Const ZString Ptr, sourceId))
    Return errorCode
End Function

Function sqlite3CorruptError CDecl Alias "sqlite3CorruptError" ( _
    ByVal lineNumber As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Return sqlite3ReportError(SQLITE_CORRUPT, lineNumber, StrPtr("database corruption"))
End Function

Function sqlite3MisuseError CDecl Alias "sqlite3MisuseError" ( _
    ByVal lineNumber As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Return sqlite3ReportError(SQLITE_MISUSE, lineNumber, StrPtr("misuse"))
End Function

Function sqlite3CantopenError CDecl Alias "sqlite3CantopenError" ( _
    ByVal lineNumber As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Return sqlite3ReportError(SQLITE_CANTOPEN, lineNumber, StrPtr("cannot open file"))
End Function

#if defined(SQLITE_DEBUG) OrElse defined(SQLITE_ENABLE_CORRUPT_PGNO)
Function sqlite3CorruptPgnoError CDecl Alias "sqlite3CorruptPgnoError" ( _
    ByVal lineNumber As SQLITE_C_INT, _
    ByVal pageNumber As u32 _
) As SQLITE_C_INT Export
    Dim message As ZString * 100
    sqlite3_snprintf(SizeOf(message), @message, _
                     StrPtr("database corruption page %d"), pageNumber)
    Return sqlite3ReportError(SQLITE_CORRUPT, lineNumber, @message)
End Function
#endif

#ifdef SQLITE_DEBUG
Function sqlite3NomemError CDecl Alias "sqlite3NomemError" ( _
    ByVal lineNumber As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Return sqlite3ReportError(SQLITE_NOMEM, lineNumber, StrPtr("OOM"))
End Function

Function sqlite3IoerrnomemError CDecl Alias "sqlite3IoerrnomemError" ( _
    ByVal lineNumber As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Return sqlite3ReportError(SQLITE_IOERR_NOMEM, lineNumber, StrPtr("I/O OOM error"))
End Function
#endif

/' end of sqlite3_errors.bas '/
