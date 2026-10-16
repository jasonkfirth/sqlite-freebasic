/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_stmt.bas

    Purpose:

        Expose statement metadata backed by the VDBE state.

    Responsibilities:

        - Return a statement's connection and retained SQL text.
        - Report read-only, EXPLAIN, expired, and currently-running state.
        - Walk the connection's prepared-statement list under its mutex.
        - Expose bind-parameter names and bind scalar, text, blob, and pointer values.
        - Read bound values while marking parameters for statement reprepare.
        - Transfer bound Mem values between statements sharing one connection.
        - Return result-column values and names, including EXPLAIN headings.
        - Format errors owned by the VDBE before it is finalized.
        - Diagnose calls made with NULL or finalized statements.
        - Format VDBE-owned error messages and finalize statement objects.
        - Validate released register ranges in debug builds.
        - Resolve a named parameter through the statement's VList.
        - Transfer VDBE error text into the owning connection before reset.
        - Report and reset VDBE statement counters.
        - Reset and finalize prepared VDBE statements.
        - Send the optional SQLLOG callback its expanded SQL completion event.
        - Run WAL commit hooks after automatic transactions complete.

    This file intentionally does NOT contain:

        - Statement preparation, complete opcode dispatch, or full frame/auxiliary memory accounting.
'/

#lang "fb"
#include once "sqlite3_debug_assert.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_mutex.bi"
#include once "sqlite3_util_numeric.bi"
#include once "sqlite3_vdbe_mem_text.bi"
#include once "sqlite3_vdbe_affinity.bi"
#include once "sqlite3_vdbe_api.bi"
#include once "sqlite3_api_constants.bi"
#include once "sqlite3_vfs.bi"
#include once "sqlite3_pager.bi"
#include once "sqlite3_fault.bi"
#include once "sqlite3_sqllog.bi"

Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal zText As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeTransferError CDecl Alias "sqlite3VdbeTransferError" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_reset CDecl Alias "sqlite3_reset" ( _
    ByVal pStatement As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3Reprepare CDecl Alias "sqlite3Reprepare" ( _
    ByVal pVdbe As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3VdbeStmtLog CDecl Alias "sqlite3_log" ( _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Sub sqlite3ColumnSetError CDecl Alias "sqlite3Error" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal errorCode As SQLITE_C_INT _
)
Declare Function sqlite3VdbeStmtVMPrintf CDecl Alias "sqlite3VMPrintf" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ByRef sourceArgs As Cva_List _
) As ZString Ptr

Private Function vdbeSafety CDecl Alias "vdbeSafety" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT
    If pVdbe = 0 OrElse pVdbe->db = 0 Then
        sqlite3VdbeStmtLog(SQLITE_MISUSE, _
            StrPtr("API called with finalized prepared statement"))
        Return 1
    End If
    Return 0
End Function

Private Function vdbeSafetyNotNull CDecl Alias "vdbeSafetyNotNull" ( _
    ByVal pStatement As Any Ptr _
) As SQLITE_C_INT
    If pStatement = 0 Then
        sqlite3VdbeStmtLog(SQLITE_MISUSE, _
            StrPtr("API called with NULL prepared statement"))
        Return 1
    End If
    Return vdbeSafety(CPtr(SqliteVdbe Ptr, pStatement))
End Function

Sub sqlite3VdbeError CDecl Alias "sqlite3VdbeError" ( _
    ByVal pVdbeArgument As Any Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) Export
    If pVdbeArgument = 0 Then Return
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pVdbeArgument)
    If pVdbe->db = 0 Then Return

    sqlite3DbFree(pVdbe->db, pVdbe->zErrMsg)
    pVdbe->zErrMsg = 0
    If zFormat = 0 Then Return

    Dim args As Cva_List
    Cva_Start(args, zFormat)
    pVdbe->zErrMsg = sqlite3VdbeStmtVMPrintf(pVdbe->db, zFormat, args)
    Cva_End(args)
End Sub

#ifdef SQLITE_DEBUG
Dim Shared As Const SqliteVdbeMem sqlite3ColumnNullMem = _
    Type<SqliteVdbeMem>(Type<sqlite3MemValue>(0), 0, 0, MEM_NULL, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
#else
Dim Shared As Const SqliteVdbeMem sqlite3ColumnNullMem = _
    Type<SqliteVdbeMem>(Type<sqlite3MemValue>(0), 0, 0, MEM_NULL, 0, 0, 0, 0, 0, 0, 0)
#endif

/' Explain result headings share one UTF-16 table indexed by the C offsets. '/
Dim Shared As Const UShort sqlite3ExplainColumnNames16(0 To 59) = _
    {97, 100, 100, 114, 0, 111, 112, 99, 111, 100, 101, 0, _
     112, 49, 0, 112, 50, 0, 112, 51, 0, 112, 52, 0, 112, 53, 0, _
     99, 111, 109, 109, 101, 110, 116, 0, 105, 100, 0, 112, 97, _
     114, 101, 110, 116, 0, 110, 111, 116, 117, 115, 101, 100, 0, _
     100, 101, 116, 97, 105, 108, 0}
Dim Shared As Const UByte sqlite3ExplainColumnNameOffsets16(0 To 11) = _
    {0, 5, 12, 15, 18, 21, 24, 27, 35, 38, 45, 53}

Private Function sqlite3VdbeSignedIntFromBits(ByVal valueBits As ULongInt) As SQLITE_C_INT
    If valueBits > &H7FFFFFFF Then _
        Return CInt(CLngInt(valueBits) - 4294967296LL)
    Return CInt(valueBits)
End Function

Private Function sqlite3VdbeBindCheck( _
    ByVal pStatement As Any Ptr, _
    ByVal parameterIndex As SQLITE_C_INT, _
    ByRef pVdbe As SqliteVdbe Ptr, _
    ByRef zeroBasedIndex As SQLITE_C_INT _
) As SQLITE_C_INT
    pVdbe = 0
    zeroBasedIndex = -1
    If vdbeSafetyNotNull(pStatement) <> 0 Then Return SQLITE_MISUSE
    pVdbe = CPtr(SqliteVdbe Ptr, pStatement)

    sqlite3_mutex_enter(pVdbe->db->mutex)
    If pVdbe->eVdbeState <> VDBE_READY_STATE Then
        sqlite3Error(pVdbe->db, SQLITE_MISUSE)
        sqlite3_mutex_leave(pVdbe->db->mutex)
        sqlite3VdbeStmtLog(SQLITE_MISUSE, _
            StrPtr("bind on a busy prepared statement: [%s]"), pVdbe->zSql)
        Return SQLITE_MISUSE
    End If
    If parameterIndex <= 0 OrElse parameterIndex > pVdbe->nVar Then
        sqlite3Error(pVdbe->db, SQLITE_RANGE)
        sqlite3_mutex_leave(pVdbe->db->mutex)
        Return SQLITE_RANGE
    End If
    If pVdbe->aVar = 0 Then
        pVdbe->db->errorCode = SQLITE_CORRUPT
        sqlite3_mutex_leave(pVdbe->db->mutex)
        Return SQLITE_CORRUPT
    End If

    zeroBasedIndex = parameterIndex - 1
    Return SQLITE_OK
End Function

Private Sub sqlite3VdbeMarkExpired(ByVal pVdbe As SqliteVdbe Ptr)
    pVdbe->vdbeFlags = (pVdbe->vdbeFlags And Not VDBE_EXPIRED_MASK) Or 1
End Sub

Private Sub sqlite3VdbeBindMaybeExpire( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal zeroBasedIndex As SQLITE_C_INT _
)
    If pVdbe->expmask = 0 Then Return
    Dim expireMask As u32
    If zeroBasedIndex >= 31 Then
        expireMask = &H80000000
    Else
        expireMask = CULng(1) Shl zeroBasedIndex
    End If
    If (pVdbe->expmask And expireMask) <> 0 Then sqlite3VdbeMarkExpired(pVdbe)
End Sub

/' Release a bound Mem cell while retaining the statement mutex on success. '/
Private Function vdbeUnbind CDecl Alias "vdbeUnbind" ( _
    ByVal pStatement As Any Ptr, _
    ByVal variableIndex As u32 _
) As SQLITE_C_INT
    If vdbeSafetyNotNull(pStatement) <> 0 Then Return SQLITE_MISUSE
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pStatement)

    sqlite3_mutex_enter(pVdbe->db->mutex)
    If pVdbe->eVdbeState <> VDBE_READY_STATE Then
        sqlite3Error(pVdbe->db, SQLITE_MISUSE)
        sqlite3_mutex_leave(pVdbe->db->mutex)
        sqlite3VdbeStmtLog(SQLITE_MISUSE, _
            StrPtr("bind on a busy prepared statement: [%s]"), pVdbe->zSql)
        Return SQLITE_MISUSE
    End If
    If variableIndex >= CULngInt(pVdbe->nVar) Then
        sqlite3Error(pVdbe->db, SQLITE_RANGE)
        sqlite3_mutex_leave(pVdbe->db->mutex)
        Return SQLITE_RANGE
    End If
    If pVdbe->aVar = 0 Then
        sqlite3Error(pVdbe->db, SQLITE_CORRUPT)
        sqlite3_mutex_leave(pVdbe->db->mutex)
        Return SQLITE_CORRUPT
    End If

    Dim cellIndex As SQLITE_C_INT = CInt(variableIndex)
    sqlite3VdbeMemRelease(@pVdbe->aVar[cellIndex])
    pVdbe->aVar[cellIndex].flags = MEM_NULL
    pVdbe->db->errorCode = SQLITE_OK
    sqlite3VdbeBindMaybeExpire(pVdbe, cellIndex)
    Return SQLITE_OK
End Function

Private Function sqlite3VdbeBindUnbind( _
    ByVal pStatement As Any Ptr, _
    ByVal parameterIndex As SQLITE_C_INT, _
    ByRef pVdbe As SqliteVdbe Ptr, _
    ByRef zeroBasedIndex As SQLITE_C_INT _
) As SQLITE_C_INT
    pVdbe = 0
    zeroBasedIndex = -1
    If parameterIndex <= 0 Then _
        Return sqlite3VdbeBindCheck(pStatement, parameterIndex, pVdbe, zeroBasedIndex)
    Dim rc As SQLITE_C_INT = vdbeUnbind(pStatement, CUInt(parameterIndex - 1))
    If rc <> SQLITE_OK Then Return rc
    pVdbe = CPtr(SqliteVdbe Ptr, pStatement)
    zeroBasedIndex = parameterIndex - 1
    Return SQLITE_OK
End Function

Private Function sqlite3VdbeBindDestructorIsTransient( _
    ByVal xDestructor As sqlite3MemDestructor _
) As Long
    Return IIf(xDestructor = CPtr(sqlite3MemDestructor, -1), 1, 0)
End Function

Private Sub sqlite3VdbeBindInvokeDestructor( _
    ByVal xDestructor As sqlite3MemDestructor, _
    ByVal pData As Any Ptr _
)
    If xDestructor = 0 OrElse pData = 0 OrElse _
       sqlite3VdbeBindDestructorIsTransient(xDestructor) <> 0 Then Return
    xDestructor(pData)
End Sub

Private Function sqlite3VdbeBindSetDataLocked( _
    ByVal pMem As SqliteVdbeMem Ptr, _
    ByVal pData As Any Ptr, _
    ByVal nByte As sqlite3_int64, _
    ByVal xDestructor As sqlite3MemDestructor, _
    ByVal requestedEncoding As u8 _
) As SQLITE_C_INT
    If pData = 0 Then Return SQLITE_OK

    Dim textEncoding As u8 = requestedEncoding
    If textEncoding = SQLITE_UTF16 OrElse textEncoding = SQLITE_UTF16_ALIGNED Then _
        textEncoding = SQLITE_UTF16NATIVE
    If textEncoding <> 0 AndAlso textEncoding <> SQLITE_UTF8 AndAlso _
       textEncoding <> SQLITE_UTF8_ZT AndAlso textEncoding <> SQLITE_UTF16LE AndAlso _
       textEncoding <> SQLITE_UTF16BE Then
        sqlite3VdbeBindInvokeDestructor(xDestructor, pData)
        Return SQLITE_MISUSE
    End If

    Dim pText As Const ZString Ptr = CPtr(Const ZString Ptr, pData)
    Dim rc As SQLITE_C_INT
    If textEncoding = 0 Then
        rc = sqlite3VdbeMemSetStr(pMem, pText, nByte, 0, xDestructor)
    ElseIf textEncoding = SQLITE_UTF8 OrElse textEncoding = SQLITE_UTF8_ZT Then
        rc = sqlite3VdbeMemSetText(pMem, pText, nByte, xDestructor)
        If rc = SQLITE_OK AndAlso textEncoding = SQLITE_UTF8_ZT Then _
            pMem->flags Or= MEM_TERM
    Else
        rc = sqlite3VdbeMemSetStr(pMem, pText, nByte, textEncoding, xDestructor)
    End If
    If rc = SQLITE_OK AndAlso textEncoding <> 0 Then _
        rc = sqlite3VdbeChangeEncoding(pMem, pMem->db->enc)
    Return rc
End Function

Private Function bindText CDecl Alias "bindText" ( _
    ByVal pStatement As Any Ptr, _
    ByVal parameterIndex As SQLITE_C_INT, _
    ByVal pData As Any Ptr, _
    ByVal nByte As sqlite3_int64, _
    ByVal xDestructorArgument As Any Ptr, _
    ByVal encodingHint As u8 _
) As SQLITE_C_INT
    Dim xDestructor As sqlite3MemDestructor = CPtr(sqlite3MemDestructor, xDestructorArgument)
    Dim pVdbe As SqliteVdbe Ptr
    Dim zeroBasedIndex As SQLITE_C_INT
    Dim rc As SQLITE_C_INT = sqlite3VdbeBindUnbind( _
        pStatement, parameterIndex, pVdbe, zeroBasedIndex)
    If rc <> SQLITE_OK Then
        sqlite3VdbeBindInvokeDestructor(xDestructor, pData)
        Return rc
    End If

    rc = sqlite3VdbeBindSetDataLocked( _
        @pVdbe->aVar[zeroBasedIndex], pData, nByte, xDestructor, encodingHint)
    If rc <> SQLITE_OK Then pVdbe->db->errorCode = rc
    sqlite3_mutex_leave(pVdbe->db->mutex)
    Return rc
End Function

Private Function sqlite3VdbeBindData64( _
    ByVal pStatement As Any Ptr, _
    ByVal parameterIndex As SQLITE_C_INT, _
    ByVal pData As Any Ptr, _
    ByVal nByte As sqlite3_uint64, _
    ByVal xDestructorArgument As Any Ptr, _
    ByVal encodingHint As u8 _
) As SQLITE_C_INT
    Dim xDestructor As sqlite3MemDestructor = CPtr(sqlite3MemDestructor, xDestructorArgument)
    Dim pVdbe As SqliteVdbe Ptr
    Dim zeroBasedIndex As SQLITE_C_INT
    Dim rc As SQLITE_C_INT = sqlite3VdbeBindUnbind( _
        pStatement, parameterIndex, pVdbe, zeroBasedIndex)
    If rc <> SQLITE_OK Then
        sqlite3VdbeBindInvokeDestructor(xDestructor, pData)
        Return rc
    End If

    If nByte > CULngInt(pVdbe->db->lengthLimit) Then
        sqlite3VdbeBindInvokeDestructor(xDestructor, pData)
        pVdbe->db->errorCode = SQLITE_TOOBIG
        sqlite3_mutex_leave(pVdbe->db->mutex)
        Return SQLITE_TOOBIG
    End If
    rc = sqlite3VdbeBindSetDataLocked( _
        @pVdbe->aVar[zeroBasedIndex], pData, CLngInt(nByte), xDestructor, encodingHint)
    If rc <> SQLITE_OK Then pVdbe->db->errorCode = rc
    sqlite3_mutex_leave(pVdbe->db->mutex)
    Return rc
End Function

Function sqlite3_db_handle CDecl Alias "sqlite3_db_handle" ( _
    ByVal pStatement As Any Ptr _
) As Any Ptr Export
    If pStatement = 0 Then Return 0
    Return CPtr(SqliteVdbe Ptr, pStatement)->db
End Function

Function sqlite3_stmt_readonly CDecl Alias "sqlite3_stmt_readonly" ( _
    ByVal pStatement As Any Ptr _
) As SQLITE_C_INT Export
    If pStatement = 0 Then Return 1
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pStatement)
    Return IIf((pVdbe->vdbeFlags And VDBE_READONLY_MASK) <> 0, 1, 0)
End Function

Function sqlite3_stmt_isexplain CDecl Alias "sqlite3_stmt_isexplain" ( _
    ByVal pStatement As Any Ptr _
) As SQLITE_C_INT Export
    If pStatement = 0 Then Return 0
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pStatement)
    Return CInt((pVdbe->vdbeFlags And VDBE_EXPLAIN_MASK) Shr VDBE_EXPLAIN_SHIFT)
End Function

Function sqlite3_stmt_explain CDecl Alias "sqlite3_stmt_explain" ( _
    ByVal pStatement As Any Ptr, _
    ByVal requestedMode As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pStatement = 0 Then Return SQLITE_MISUSE
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pStatement)
    If pVdbe->db = 0 Then Return SQLITE_MISUSE

    sqlite3_mutex_enter(pVdbe->db->mutex)
    Dim currentMode As SQLITE_C_INT = CInt( _
        (pVdbe->vdbeFlags And VDBE_EXPLAIN_MASK) Shr VDBE_EXPLAIN_SHIFT)
    Dim rc As SQLITE_C_INT

    If currentMode = requestedMode Then
        rc = SQLITE_OK
    ElseIf requestedMode < 0 OrElse requestedMode > 2 Then
        rc = SQLITE_ERROR
    ElseIf (pVdbe->prepFlags And SQLITE_PREPARE_SAVESQL) = 0 Then
        rc = SQLITE_ERROR
    ElseIf pVdbe->eVdbeState <> VDBE_READY_STATE Then
        rc = SQLITE_BUSY
    ElseIf pVdbe->nMem >= 10 AndAlso _
           (requestedMode <> 2 OrElse _
            (pVdbe->vdbeFlags And VDBE_HAVE_EQP_OPS_MASK) <> 0) Then
        ' Reuse already-generated bytecode when the requested EXPLAIN mode fits it.
        pVdbe->vdbeFlags = (pVdbe->vdbeFlags And Not VDBE_EXPLAIN_MASK) Or _
            (CULng(requestedMode) Shl VDBE_EXPLAIN_SHIFT)
        rc = SQLITE_OK
    Else
        pVdbe->vdbeFlags = (pVdbe->vdbeFlags And Not VDBE_EXPLAIN_MASK) Or _
            (CULng(requestedMode) Shl VDBE_EXPLAIN_SHIFT)
        rc = sqlite3Reprepare(CPtr(Any Ptr, pVdbe))
        If requestedMode = 2 Then
            pVdbe->vdbeFlags = pVdbe->vdbeFlags Or VDBE_HAVE_EQP_OPS_MASK
        Else
            pVdbe->vdbeFlags = pVdbe->vdbeFlags And _
                Not VDBE_HAVE_EQP_OPS_MASK
        End If
    End If

    Dim finalMode As SQLITE_C_INT = CInt( _
        (pVdbe->vdbeFlags And VDBE_EXPLAIN_MASK) Shr VDBE_EXPLAIN_SHIFT)
    If finalMode <> 0 Then
        pVdbe->nResColumn = CUShort(12 - 4 * finalMode)
    Else
        pVdbe->nResColumn = pVdbe->nResAlloc
    End If
    sqlite3_mutex_leave(pVdbe->db->mutex)
    Return rc
End Function

#ifndef SQLITE_OMIT_DEPRECATED
Function sqlite3_expired CDecl Alias "sqlite3_expired" ( _
    ByVal pStatement As Any Ptr _
) As SQLITE_C_INT Export
    If pStatement = 0 Then Return 1
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pStatement)
    If pVdbe->db = 0 Then Return 1
    sqlite3_mutex_enter(pVdbe->db->mutex)
    Dim isExpired As SQLITE_C_INT = _
        IIf((pVdbe->vdbeFlags And VDBE_EXPIRED_MASK) <> 0, 1, 0)
    sqlite3_mutex_leave(pVdbe->db->mutex)
    Return isExpired
End Function
#endif

Function sqlite3_stmt_busy CDecl Alias "sqlite3_stmt_busy" ( _
    ByVal pStatement As Any Ptr _
) As SQLITE_C_INT Export
    If pStatement = 0 Then Return 0
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pStatement)
    Return IIf(pVdbe->eVdbeState = VDBE_RUN_STATE, 1, 0)
End Function

Private Sub sqlite3VdbeCountAllocation( _
    ByVal db As sqlite3 Ptr, _
    ByVal pAllocation As Any Ptr, _
    ByRef totalBytes As sqlite3_uint64 _
)
    If db = 0 OrElse pAllocation = 0 Then Return
    Dim allocationSize As SQLITE_C_INT = sqlite3DbMallocSize(db, pAllocation)
    If allocationSize > 0 Then totalBytes += CULngInt(allocationSize)
End Sub

Private Sub sqlite3VdbeCountMemArray( _
    ByVal db As sqlite3 Ptr, _
    ByVal pMem As SqliteVdbeMem Ptr, _
    ByVal cellCount As SQLITE_C_INT, _
    ByRef totalBytes As sqlite3_uint64 _
)
    If pMem = 0 OrElse cellCount <= 0 Then Return
    sqlite3VdbeCountAllocation(db, pMem, totalBytes)
    For iMem As SQLITE_C_INT = 0 To cellCount - 1
        sqlite3VdbeCountAllocation(db, pMem[iMem].zMalloc, totalBytes)
    Next
End Sub

Private Function sqlite3VdbeStatementMemoryUsed(ByVal pVdbe As SqliteVdbe Ptr) As SQLITE_C_INT
    If pVdbe = 0 OrElse pVdbe->db = 0 Then Return 0
    Dim totalBytes As sqlite3_uint64 = 0
    sqlite3VdbeCountAllocation(pVdbe->db, pVdbe, totalBytes)
    sqlite3VdbeCountAllocation(pVdbe->db, pVdbe->aOp, totalBytes)
    sqlite3VdbeCountMemArray(pVdbe->db, pVdbe->aMem, pVdbe->nMem, totalBytes)
    sqlite3VdbeCountMemArray(pVdbe->db, pVdbe->aVar, pVdbe->nVar, totalBytes)
    sqlite3VdbeCountMemArray(pVdbe->db, pVdbe->aColName, _
                             CLng(pVdbe->nResAlloc) * COLNAME_N, totalBytes)
    sqlite3VdbeCountAllocation(pVdbe->db, pVdbe->apArg, totalBytes)
    sqlite3VdbeCountAllocation(pVdbe->db, pVdbe->apCsr, totalBytes)
    sqlite3VdbeCountAllocation(pVdbe->db, pVdbe->pVList, totalBytes)
    sqlite3VdbeCountAllocation(pVdbe->db, pVdbe->zErrMsg, totalBytes)
    sqlite3VdbeCountAllocation(pVdbe->db, pVdbe->zSql, totalBytes)
#ifdef SQLITE_ENABLE_NORMALIZE
    sqlite3VdbeCountAllocation(pVdbe->db, pVdbe->zNormSql, totalBytes)
#endif
    If pVdbe->aOp <> 0 AndAlso pVdbe->nOp > 0 AndAlso _
       pVdbe->nOp <= SQLITE_MAX_VDBE_OP Then
        For iOp As SQLITE_C_INT = 0 To pVdbe->nOp - 1
            If pVdbe->aOp[iOp].p4type = P4_DYNAMIC OrElse _
               pVdbe->aOp[iOp].p4type = P4_INTARRAY Then
                sqlite3VdbeCountAllocation( _
                    pVdbe->db, pVdbe->aOp[iOp].p4.p, totalBytes)
            End If
        Next
    End If

    If totalBytes > &H7FFFFFFF Then _
        Return CInt(CLngInt(totalBytes) - 4294967296LL)
    Return CInt(totalBytes)
End Function

/' Return stable NULL storage for calls with no usable result-column index. '/
Function columnNullValue() As SqliteVdbeMem Ptr
    Return CPtr(SqliteVdbeMem Ptr, @sqlite3ColumnNullMem)
End Function

Private Function columnMem( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT, _
    ByRef pVdbe As SqliteVdbe Ptr _
) As SqliteVdbeMem Ptr
    pVdbe = 0
    If pStatement = 0 Then Return columnNullValue()
    pVdbe = CPtr(SqliteVdbe Ptr, pStatement)
    If pVdbe->db = 0 Then
        pVdbe = 0
        Return columnNullValue()
    End If
    sqlite3_mutex_enter(pVdbe->db->mutex)
    If pVdbe->pResultRow = 0 OrElse columnIndex < 0 OrElse _
       columnIndex >= pVdbe->nResColumn Then
        sqlite3ColumnSetError(pVdbe->db, SQLITE_RANGE)
        Return columnNullValue()
    End If
    Return @pVdbe->pResultRow[columnIndex]
End Function

Private Sub columnMallocFailure(ByVal pVdbe As SqliteVdbe Ptr)
    If pVdbe = 0 OrElse pVdbe->db = 0 Then Return
    pVdbe->rc = sqlite3ApiExit(pVdbe->db, pVdbe->rc)
    sqlite3_mutex_leave(pVdbe->db->mutex)
End Sub

Private Function columnName( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT, _
    ByVal nameType As SQLITE_C_INT, _
    ByVal desiredEncoding As u8 _
) As Any Ptr
    If pStatement = 0 OrElse columnIndex < 0 Then Return 0
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pStatement)
    If pVdbe->db = 0 Then Return 0

    Dim result As Any Ptr = 0
    Dim explainMode As SQLITE_C_INT = CInt( _
        (pVdbe->vdbeFlags And VDBE_EXPLAIN_MASK) Shr VDBE_EXPLAIN_SHIFT)
    sqlite3_mutex_enter(pVdbe->db->mutex)
    If explainMode <> 0 Then
        If nameType = COLNAME_NAME Then
            Dim nameCount As SQLITE_C_INT = IIf(explainMode = 1, 8, 4)
            If columnIndex < nameCount Then
                Dim nameIndex As SQLITE_C_INT = columnIndex + 8 * (explainMode - 1)
                If desiredEncoding = SQLITE_UTF8 Then
                    Select Case nameIndex
                    Case 0: result = CPtr(Any Ptr, StrPtr("addr"))
                    Case 1: result = CPtr(Any Ptr, StrPtr("opcode"))
                    Case 2: result = CPtr(Any Ptr, StrPtr("p1"))
                    Case 3: result = CPtr(Any Ptr, StrPtr("p2"))
                    Case 4: result = CPtr(Any Ptr, StrPtr("p3"))
                    Case 5: result = CPtr(Any Ptr, StrPtr("p4"))
                    Case 6: result = CPtr(Any Ptr, StrPtr("p5"))
                    Case 7: result = CPtr(Any Ptr, StrPtr("comment"))
                    Case 8: result = CPtr(Any Ptr, StrPtr("id"))
                    Case 9: result = CPtr(Any Ptr, StrPtr("parent"))
                    Case 10: result = CPtr(Any Ptr, StrPtr("notused"))
                    Case 11: result = CPtr(Any Ptr, StrPtr("detail"))
                    End Select
                Else
                    Dim nameOffset As UByte = sqlite3ExplainColumnNameOffsets16(nameIndex)
                    result = CPtr(Any Ptr, @sqlite3ExplainColumnNames16(nameOffset))
                End If
            End If
        End If
    ElseIf columnIndex < pVdbe->nResColumn AndAlso nameType >= 0 AndAlso _
           nameType < COLNAME_N AndAlso pVdbe->aColName <> 0 Then
        Dim priorMallocFailed As u8 = pVdbe->db->mallocFailed
        Dim cellIndex As SQLITE_C_INT = _
            columnIndex + nameType * pVdbe->nResColumn
        Dim pName As SqliteVdbeMem Ptr = @pVdbe->aColName[cellIndex]
        If desiredEncoding = SQLITE_UTF8 Then
            result = CPtr(Any Ptr, sqlite3_value_text(pName))
        Else
            result = sqlite3_value_text16(pName)
        End If
        If pVdbe->db->mallocFailed > priorMallocFailed Then
            sqlite3OomClear(pVdbe->db)
            result = 0
        End If
    End If
    sqlite3_mutex_leave(pVdbe->db->mutex)
    Return result
End Function

Function sqlite3_stmt_status CDecl Alias "sqlite3_stmt_status" ( _
    ByVal pStatement As Any Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal resetFlag As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pStatement = 0 Then Return 0
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pStatement)
    If pVdbe->db = 0 Then Return 0
    If operation = SQLITE_STMTSTATUS_MEMUSED Then
        sqlite3_mutex_enter(pVdbe->db->mutex)
        Dim bytesUsed As SQLITE_C_INT = sqlite3VdbeStatementMemoryUsed(pVdbe)
        sqlite3_mutex_leave(pVdbe->db->mutex)
        Return bytesUsed
    End If
    If operation < 0 OrElse operation >= 9 Then Return 0
    Dim counterValue As u32 = pVdbe->aCounter(operation)
    If resetFlag <> 0 Then pVdbe->aCounter(operation) = 0
    If counterValue > &H7FFFFFFF Then _
        Return CInt(CLngInt(counterValue) - 4294967296LL)
    Return CInt(counterValue)
End Function

Function sqlite3_sql CDecl Alias "sqlite3_sql" ( _
    ByVal pStatement As Any Ptr _
) As Const ZString Ptr Export
    If pStatement = 0 Then Return 0
    Return CPtr(SqliteVdbe Ptr, pStatement)->zSql
End Function

Function sqlite3_expanded_sql CDecl Alias "sqlite3_expanded_sql" ( _
    ByVal pStatement As Any Ptr _
) As ZString Ptr Export
#ifdef SQLITE_OMIT_TRACE
    Return 0
#else
    If pStatement = 0 Then Return 0
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pStatement)
    If pVdbe->db = 0 OrElse pVdbe->zSql = 0 Then Return 0
    sqlite3_mutex_enter(pVdbe->db->mutex)
    Dim zExpanded As ZString Ptr = sqlite3VdbeExpandSql(pVdbe, pVdbe->zSql)
    sqlite3_mutex_leave(pVdbe->db->mutex)
    Return zExpanded
#endif
End Function

' The caller holds the connection mutex after a successful automatic commit.
Private Function doWalCallbacks CDecl Alias "doWalCallbacks" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
#ifndef SQLITE_OMIT_WAL
    If db = 0 Then Return SQLITE_MISUSE
    If db->nDb < 0 OrElse db->nDb > UBound(db->aDb) + 1 Then Return SQLITE_CORRUPT

    Dim resultCode As SQLITE_C_INT = SQLITE_OK
    For databaseIndex As SQLITE_C_INT = 0 To db->nDb - 1
        Dim pBtree As Btree Ptr = CPtr(Btree Ptr, db->aDb(databaseIndex).pBt)
        If pBtree = 0 Then Continue For

        sqlite3BtreeEnter(pBtree)
        Dim committedFrames As SQLITE_C_INT = sqlite3PagerWalCallback( _
            sqlite3BtreePager(pBtree))
        sqlite3BtreeLeave(pBtree)

        If committedFrames > 0 AndAlso db->xWalCallback <> 0 AndAlso _
           resultCode = SQLITE_OK Then
            Dim xWalCallback As SqliteWalHookCallback = _
                CPtr(SqliteWalHookCallback, db->xWalCallback)
            resultCode = xWalCallback( _
                db->pWalArg, db, db->aDb(databaseIndex).zDbSName, committedFrames)
        End If
    Next
    Return resultCode
#else
    Return SQLITE_OK
#endif
End Function

Private Function sqlite3Step CDecl Alias "sqlite3Step" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT
    If pVdbe = 0 OrElse pVdbe->db = 0 Then Return SQLITE_MISUSE

    Dim db As sqlite3 Ptr = pVdbe->db
    Dim rc As SQLITE_C_INT = SQLITE_OK

    If pVdbe->eVdbeState <> VDBE_RUN_STATE Then
        If pVdbe->eVdbeState = VDBE_READY_STATE Then
            If (pVdbe->vdbeFlags And VDBE_EXPIRED_MASK) <> 0 Then
                pVdbe->rc = SQLITE_SCHEMA
                rc = SQLITE_ERROR
                If (pVdbe->prepFlags And SQLITE_PREPARE_SAVESQL) <> 0 Then _
                    rc = sqlite3VdbeTransferError(pVdbe)
                Return rc And db->errMask
            End If

            ' Interrupt state and active-statement count share this lock with sqlite3_interrupt.
            sqlite3_mutex_enter(db->interruptMutex)
            If db->nVdbeActive = 0 Then db->isInterrupted = 0
            db->nVdbeActive += 1
            sqlite3_mutex_leave(db->interruptMutex)

#ifdef SQLITE_DEBUG
            If Not (db->nVdbeWrite > 0 OrElse db->autoCommit = 0 OrElse _
                    (db->nDeferredCons + db->nDeferredImmCons) = 0) Then _
                sqlite3DebugAssert(StrPtr("VDBE write counters are consistent"))
#endif

#ifndef SQLITE_OMIT_TRACE
            Dim profileTimerNeeded As SQLITE_C_INT = CInt( _
                (db->mTrace And (SQLITE_TRACE_PROFILE Or SQLITE_TRACE_XPROFILE)) <> 0)
#ifndef SQLITE_OMIT_DEPRECATED
            If db->xProfile <> 0 Then profileTimerNeeded = 1
#endif
            If profileTimerNeeded <> 0 AndAlso db->init.busy = 0 AndAlso _
               pVdbe->zSql <> 0 AndAlso db->pVfs <> 0 Then
                pVdbe->startTime = 0
                Dim clockRc As SQLITE_C_INT = sqlite3OsCurrentTimeInt64( _
                    CPtr(sqlite3_vfs Ptr, db->pVfs), @pVdbe->startTime)
                If clockRc <> SQLITE_OK Then pVdbe->startTime = 0
            Else
                pVdbe->startTime = 0
            End If
#endif

            If (pVdbe->vdbeFlags And VDBE_READONLY_MASK) = 0 Then db->nVdbeWrite += 1
            If (pVdbe->vdbeFlags And VDBE_BISREADER_MASK) <> 0 Then db->nVdbeRead += 1
            pVdbe->pc = 0
            pVdbe->eVdbeState = VDBE_RUN_STATE
        ElseIf pVdbe->eVdbeState = VDBE_HALT_STATE Then
#ifdef SQLITE_OMIT_AUTORESET
            Dim previousCode As SQLITE_C_INT = pVdbe->rc And &HFF
            If previousCode = SQLITE_BUSY OrElse previousCode = SQLITE_LOCKED Then
                sqlite3_reset(CPtr(Any Ptr, pVdbe))
            Else
                Return SQLITE_MISUSE
            End If
#else
            sqlite3_reset(CPtr(Any Ptr, pVdbe))
#endif
            If pVdbe->eVdbeState <> VDBE_READY_STATE Then Return SQLITE_MISUSE
            Return sqlite3Step(pVdbe)
        Else
            Return SQLITE_MISUSE
        End If
    End If

#ifdef SQLITE_DEBUG
    pVdbe->rcApp = SQLITE_OK
#endif
#ifndef SQLITE_OMIT_EXPLAIN
    If (pVdbe->vdbeFlags And VDBE_EXPLAIN_MASK) <> 0 Then
        rc = sqlite3VdbeList(pVdbe)
    Else
#endif
        db->nVdbeExec += 1
        rc = sqlite3VdbeExec(pVdbe)
        db->nVdbeExec -= 1
#ifndef SQLITE_OMIT_EXPLAIN
    End If
#endif

    If rc = SQLITE_ROW Then
#ifdef SQLITE_DEBUG
        If pVdbe->rc <> SQLITE_OK Then _
            sqlite3DebugAssert(StrPtr("pVdbe->rc == SQLITE_OK"))
        If db->mallocFailed <> 0 Then _
            sqlite3DebugAssert(StrPtr("db->mallocFailed == 0"))
#endif
        db->errorCode = SQLITE_ROW
        Return SQLITE_ROW
    End If

#ifndef SQLITE_OMIT_TRACE
    vdbeExecProfileCallback(pVdbe)
#endif
    pVdbe->pResultRow = 0
    If rc = SQLITE_DONE AndAlso db->autoCommit <> 0 Then
#ifdef SQLITE_DEBUG
        If pVdbe->rc <> SQLITE_OK Then _
            sqlite3DebugAssert(StrPtr("pVdbe->rc == SQLITE_OK"))
#endif
        pVdbe->rc = doWalCallbacks(db)
        If pVdbe->rc <> SQLITE_OK Then
            rc = SQLITE_ERROR
        End If
    ElseIf rc <> SQLITE_DONE AndAlso _
           (pVdbe->prepFlags And SQLITE_PREPARE_SAVESQL) <> 0 Then
        rc = sqlite3VdbeTransferError(pVdbe)
    End If

    db->errorCode = rc
    If sqlite3ApiExit(db, pVdbe->rc) = SQLITE_NOMEM Then
        pVdbe->rc = SQLITE_NOMEM
        If (pVdbe->prepFlags And SQLITE_PREPARE_SAVESQL) <> 0 Then rc = pVdbe->rc
    End If
    Return rc And db->errMask
End Function

Function sqlite3_step CDecl Alias "sqlite3_step" ( _
    ByVal pStatement As Any Ptr _
) As SQLITE_C_INT Export
    If vdbeSafetyNotNull(pStatement) <> 0 Then Return SQLITE_MISUSE
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pStatement)
    Dim db As sqlite3 Ptr = pVdbe->db
    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim retryCount As SQLITE_C_INT = 0

    sqlite3_mutex_enter(db->mutex)
    Do
        rc = sqlite3Step(pVdbe)
        If rc = SQLITE_SCHEMA AndAlso _
           (pVdbe->prepFlags And SQLITE_PREPARE_SAVESQL) = 0 Then
            ' Legacy statements do not recompile after a schema change.
            ' Keep SQLITE_SCHEMA in the VDBE for reset/finalize, but expose
            ' SQLITE_ERROR from sqlite3_step().
            rc = SQLITE_ERROR
            Exit Do
        End If
        If rc <> SQLITE_SCHEMA OrElse retryCount >= SQLITE_MAX_SCHEMA_RETRY Then Exit Do
        retryCount += 1

        Dim savedProgramCounter As SQLITE_C_INT = pVdbe->pc
        rc = sqlite3Reprepare(CPtr(Any Ptr, pVdbe))
        If rc <> SQLITE_OK Then
            Dim zError As Const UByte Ptr = sqlite3_value_text(db->pErr)
            sqlite3DbFree(db, pVdbe->zErrMsg)
            If db->mallocFailed = 0 Then
                pVdbe->zErrMsg = CPtr(ZString Ptr, sqlite3DbStrDup( _
                    db, CPtr(Const ZString Ptr, zError)))
                rc = sqlite3ApiExit(db, rc)
                pVdbe->rc = rc
            Else
                pVdbe->zErrMsg = 0
                pVdbe->rc = SQLITE_NOMEM
                rc = pVdbe->rc
            End If
            Exit Do
        End If

        sqlite3_reset(pStatement)
        If savedProgramCounter >= 0 Then pVdbe->minWriteFileFormat = 254
    Loop
    sqlite3_mutex_leave(db->mutex)
    Return rc
End Function

Function sqlite3VdbeTransferError CDecl Alias "sqlite3VdbeTransferError" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT Export
    If pVdbe = 0 OrElse pVdbe->db = 0 Then Return SQLITE_MISUSE
    Dim db As sqlite3 Ptr = pVdbe->db
    Dim resultCode As SQLITE_C_INT = pVdbe->rc
    If pVdbe->zErrMsg <> 0 Then
        db->bBenignMalloc += 1
        sqlite3BeginBenignMalloc()
        If db->pErr = 0 Then db->pErr = sqlite3ValueNew(db)
        sqlite3ValueSetStr(db->pErr, -1, CPtr(Const Any Ptr, pVdbe->zErrMsg), _
                           SQLITE_UTF8, CPtr(sqlite3MemDestructor, -1))
        sqlite3EndBenignMalloc()
        db->bBenignMalloc -= 1
    ElseIf db->pErr <> 0 Then
        sqlite3ValueSetNull(db->pErr)
    End If
    db->errorCode = resultCode
    db->errByteOffset = -1
    Return resultCode
End Function

#ifdef SQLITE_ENABLE_SQLLOG
Private Sub vdbeInvokeSqllog CDecl Alias "vdbeInvokeSqllog" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse _
       pVdbe->rc <> SQLITE_OK OrElse pVdbe->zSql = 0 OrElse _
       pVdbe->pc < 0 OrElse sqlite3SqllogEnabled() = 0 Then Exit Sub

    Dim zExpanded As ZString Ptr = sqlite3VdbeExpandSql(pVdbe, pVdbe->zSql)
    If zExpanded = 0 Then Exit Sub
    sqlite3SqllogInvoke(pVdbe->db, zExpanded, 1)
    sqlite3DbFree(pVdbe->db, zExpanded)
End Sub
#endif

Function sqlite3VdbeReset CDecl Alias "sqlite3VdbeReset" ( _
    ByVal pVdbeArgument As Any Ptr _
) As SQLITE_C_INT
    If pVdbeArgument = 0 Then Return SQLITE_MISUSE
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pVdbeArgument)
    If pVdbe->db = 0 Then Return SQLITE_MISUSE

    If pVdbe->eVdbeState = VDBE_RUN_STATE Then
        Dim haltCode As SQLITE_C_INT = sqlite3VdbeHalt(pVdbe)
        If haltCode <> SQLITE_OK Then pVdbe->rc = haltCode
    End If
    If pVdbe->pc >= 0 Then
#ifdef SQLITE_ENABLE_SQLLOG
        vdbeInvokeSqllog(pVdbe)
#endif
        If pVdbe->db->pErr <> 0 OrElse pVdbe->zErrMsg <> 0 Then
            sqlite3VdbeTransferError(pVdbe)
        Else
            pVdbe->db->errorCode = pVdbe->rc
        End If
    End If
    sqlite3VdbeExecResetCleanup(pVdbe)
    If pVdbe->zErrMsg <> 0 Then
        sqlite3DbFree(pVdbe->db, pVdbe->zErrMsg)
        pVdbe->zErrMsg = 0
    End If
    pVdbe->pResultRow = 0
    Dim resultCode As SQLITE_C_INT = pVdbe->rc
    Return resultCode
End Function

Function sqlite3_reset CDecl Alias "sqlite3_reset" ( _
    ByVal pStatement As Any Ptr _
) As SQLITE_C_INT Export
    If pStatement = 0 Then Return SQLITE_OK
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pStatement)
    If pVdbe->db = 0 Then Return SQLITE_MISUSE
    Dim db As sqlite3 Ptr = pVdbe->db
    sqlite3_mutex_enter(db->mutex)
#ifndef SQLITE_OMIT_TRACE
    vdbeExecProfileCallback(pVdbe)
#endif
    Dim resultCode As SQLITE_C_INT = sqlite3VdbeReset(pVdbe)
    sqlite3VdbeRewind(pVdbe)
    db->errorCode = resultCode
    resultCode = sqlite3ApiExit(db, resultCode)
    sqlite3_mutex_leave(db->mutex)
    Return resultCode
End Function

/' Reset a completed VDBE if needed, then release the statement object. '/
Function sqlite3VdbeFinalize CDecl Alias "sqlite3VdbeFinalize" ( _
    ByVal pVdbeArgument As Any Ptr _
) As SQLITE_C_INT Export
    If pVdbeArgument = 0 Then Return SQLITE_MISUSE
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pVdbeArgument)
    If pVdbe->db = 0 Then Return SQLITE_MISUSE

    Dim resultCode As SQLITE_C_INT = SQLITE_OK
    If pVdbe->eVdbeState >= VDBE_READY_STATE Then _
        resultCode = sqlite3VdbeReset(pVdbe)
    sqlite3VdbeDelete(pVdbe)
    Return resultCode
End Function

Function sqlite3_finalize CDecl Alias "sqlite3_finalize" ( _
    ByVal pStatement As Any Ptr _
) As SQLITE_C_INT Export
    If pStatement = 0 Then Return SQLITE_OK
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pStatement)
    If pVdbe->db = 0 Then Return SQLITE_MISUSE
    Dim db As sqlite3 Ptr = pVdbe->db
    sqlite3_mutex_enter(db->mutex)
#ifndef SQLITE_OMIT_TRACE
    vdbeExecProfileCallback(pVdbe)
#endif
    Dim resultCode As SQLITE_C_INT = sqlite3VdbeFinalize(pVdbe)
    resultCode = sqlite3ApiExit(db, resultCode)
    sqlite3_mutex_leave(db->mutex)
    sqlite3ConnectionFinishZombie(db)
    Return resultCode
End Function

Function sqlite3_column_count CDecl Alias "sqlite3_column_count" ( _
    ByVal pStatement As Any Ptr _
) As SQLITE_C_INT Export
    If pStatement = 0 Then Return 0
    Return CPtr(SqliteVdbe Ptr, pStatement)->nResColumn
End Function

Function sqlite3_data_count CDecl Alias "sqlite3_data_count" ( _
    ByVal pStatement As Any Ptr _
) As SQLITE_C_INT Export
    If pStatement = 0 Then Return 0
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pStatement)
    If pVdbe->pResultRow = 0 Then Return 0
    Return pVdbe->nResColumn
End Function

Function sqlite3_column_value CDecl Alias "sqlite3_column_value" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As Any Ptr Export
    Dim pVdbe As SqliteVdbe Ptr
    Dim pMem As SqliteVdbeMem Ptr = columnMem( _
        pStatement, columnIndex, pVdbe)
    If pMem = 0 Then
        columnMallocFailure(pVdbe)
        Return 0
    End If
    If (pMem->flags And MEM_STATIC) <> 0 Then
        pMem->flags = (pMem->flags And Not MEM_STATIC) Or MEM_EPHEM
    End If
    columnMallocFailure(pVdbe)
    Return pMem
End Function

Function sqlite3_column_type CDecl Alias "sqlite3_column_type" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Dim pVdbe As SqliteVdbe Ptr
    Dim pMem As SqliteVdbeMem Ptr = columnMem( _
        pStatement, columnIndex, pVdbe)
    Dim result As SQLITE_C_INT = sqlite3_value_type(pMem)
    columnMallocFailure(pVdbe)
    Return result
End Function

Function sqlite3_column_int CDecl Alias "sqlite3_column_int" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Dim pVdbe As SqliteVdbe Ptr
    Dim pMem As SqliteVdbeMem Ptr = columnMem( _
        pStatement, columnIndex, pVdbe)
    Dim result As SQLITE_C_INT = sqlite3_value_int(pMem)
    columnMallocFailure(pVdbe)
    Return result
End Function

Function sqlite3_column_int64 CDecl Alias "sqlite3_column_int64" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As sqlite3_int64 Export
    Dim pVdbe As SqliteVdbe Ptr
    Dim pMem As SqliteVdbeMem Ptr = columnMem( _
        pStatement, columnIndex, pVdbe)
    Dim result As sqlite3_int64 = sqlite3_value_int64(pMem)
    columnMallocFailure(pVdbe)
    Return result
End Function

Function sqlite3_column_double CDecl Alias "sqlite3_column_double" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As Double Export
    Dim pVdbe As SqliteVdbe Ptr
    Dim pMem As SqliteVdbeMem Ptr = columnMem( _
        pStatement, columnIndex, pVdbe)
    Dim result As Double = sqlite3_value_double(pMem)
    columnMallocFailure(pVdbe)
    Return result
End Function

Function sqlite3_column_text CDecl Alias "sqlite3_column_text" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As Const UByte Ptr Export
    Dim pVdbe As SqliteVdbe Ptr
    Dim pMem As SqliteVdbeMem Ptr = columnMem( _
        pStatement, columnIndex, pVdbe)
    Dim result As Const UByte Ptr = sqlite3_value_text(pMem)
    columnMallocFailure(pVdbe)
    Return result
End Function

Function sqlite3_column_blob CDecl Alias "sqlite3_column_blob" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As Any Ptr Export
    Dim pVdbe As SqliteVdbe Ptr
    Dim pMem As SqliteVdbeMem Ptr = columnMem( _
        pStatement, columnIndex, pVdbe)
    Dim result As Any Ptr = sqlite3_value_blob(pMem)
    columnMallocFailure(pVdbe)
    Return result
End Function

Function sqlite3_column_bytes CDecl Alias "sqlite3_column_bytes" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Dim pVdbe As SqliteVdbe Ptr
    Dim pMem As SqliteVdbeMem Ptr = columnMem( _
        pStatement, columnIndex, pVdbe)
    Dim result As SQLITE_C_INT = sqlite3_value_bytes(pMem)
    columnMallocFailure(pVdbe)
    Return result
End Function

Function sqlite3_column_bytes16 CDecl Alias "sqlite3_column_bytes16" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Dim pVdbe As SqliteVdbe Ptr
    Dim pMem As SqliteVdbeMem Ptr = columnMem( _
        pStatement, columnIndex, pVdbe)
    Dim result As SQLITE_C_INT = sqlite3_value_bytes16(pMem)
    columnMallocFailure(pVdbe)
    Return result
End Function

Function sqlite3_column_text16 CDecl Alias "sqlite3_column_text16" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As Any Ptr Export
    Dim pVdbe As SqliteVdbe Ptr
    Dim pMem As SqliteVdbeMem Ptr = columnMem( _
        pStatement, columnIndex, pVdbe)
    Dim result As Any Ptr = sqlite3_value_text16(pMem)
    columnMallocFailure(pVdbe)
    Return result
End Function

Function sqlite3_column_name CDecl Alias "sqlite3_column_name" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As Const ZString Ptr Export
    Return CPtr(Const ZString Ptr, columnName( _
        pStatement, columnIndex, COLNAME_NAME, SQLITE_UTF8))
End Function

Function sqlite3_column_name16 CDecl Alias "sqlite3_column_name16" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As Any Ptr Export
    Return columnName( _
        pStatement, columnIndex, COLNAME_NAME, SQLITE_UTF16NATIVE)
End Function

#ifndef SQLITE_OMIT_DECLTYPE
Function sqlite3_column_decltype CDecl Alias "sqlite3_column_decltype" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As Const ZString Ptr Export
    Return CPtr(Const ZString Ptr, columnName( _
        pStatement, columnIndex, COLNAME_DECLTYPE, SQLITE_UTF8))
End Function

Function sqlite3_column_decltype16 CDecl Alias "sqlite3_column_decltype16" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As Any Ptr Export
    Return columnName( _
        pStatement, columnIndex, COLNAME_DECLTYPE, SQLITE_UTF16NATIVE)
End Function
#endif

#ifdef SQLITE_ENABLE_COLUMN_METADATA
Function sqlite3_column_database_name CDecl Alias "sqlite3_column_database_name" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As Const ZString Ptr Export
    Return CPtr(Const ZString Ptr, columnName( _
        pStatement, columnIndex, COLNAME_DATABASE, SQLITE_UTF8))
End Function

Function sqlite3_column_database_name16 CDecl Alias "sqlite3_column_database_name16" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As Any Ptr Export
    Return columnName( _
        pStatement, columnIndex, COLNAME_DATABASE, SQLITE_UTF16NATIVE)
End Function

Function sqlite3_column_table_name CDecl Alias "sqlite3_column_table_name" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As Const ZString Ptr Export
    Return CPtr(Const ZString Ptr, columnName( _
        pStatement, columnIndex, COLNAME_TABLE, SQLITE_UTF8))
End Function

Function sqlite3_column_table_name16 CDecl Alias "sqlite3_column_table_name16" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As Any Ptr Export
    Return columnName( _
        pStatement, columnIndex, COLNAME_TABLE, SQLITE_UTF16NATIVE)
End Function

Function sqlite3_column_origin_name CDecl Alias "sqlite3_column_origin_name" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As Const ZString Ptr Export
    Return CPtr(Const ZString Ptr, columnName( _
        pStatement, columnIndex, COLNAME_COLUMN, SQLITE_UTF8))
End Function

Function sqlite3_column_origin_name16 CDecl Alias "sqlite3_column_origin_name16" ( _
    ByVal pStatement As Any Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As Any Ptr Export
    Return columnName( _
        pStatement, columnIndex, COLNAME_COLUMN, SQLITE_UTF16NATIVE)
End Function
#endif

Function sqlite3_next_stmt CDecl Alias "sqlite3_next_stmt" ( _
    ByVal pDatabase As Any Ptr, _
    ByVal pStatement As Any Ptr _
) As Any Ptr Export
    If pDatabase = 0 Then Return 0
    Dim db As sqlite3 Ptr = CPtr(sqlite3 Ptr, pDatabase)
    sqlite3_mutex_enter(db->mutex)
    Dim pNext As Any Ptr
    If pStatement = 0 Then
        pNext = db->pVdbe
    Else
        pNext = CPtr(SqliteVdbe Ptr, pStatement)->pVNext
    End If
    sqlite3_mutex_leave(db->mutex)
    Return pNext
End Function

Function sqlite3_last_insert_rowid CDecl Alias "sqlite3_last_insert_rowid" ( _
    ByVal pDatabase As Any Ptr _
) As sqlite3_int64 Export
    If pDatabase = 0 Then Return 0
    Dim db As sqlite3 Ptr = CPtr(sqlite3 Ptr, pDatabase)
    sqlite3_mutex_enter(db->mutex)
    Dim rowId As sqlite3_int64 = db->lastRowid
    sqlite3_mutex_leave(db->mutex)
    Return rowId
End Function

Sub sqlite3_set_last_insert_rowid CDecl Alias "sqlite3_set_last_insert_rowid" ( _
    ByVal pDatabase As Any Ptr, _
    ByVal rowId As sqlite3_int64 _
) Export
    If pDatabase = 0 Then Return
    Dim db As sqlite3 Ptr = CPtr(sqlite3 Ptr, pDatabase)
    sqlite3_mutex_enter(db->mutex)
    db->lastRowid = rowId
    sqlite3_mutex_leave(db->mutex)
End Sub

Function sqlite3_changes64 CDecl Alias "sqlite3_changes64" ( _
    ByVal pDatabase As Any Ptr _
) As sqlite3_int64 Export
    If pDatabase = 0 Then Return 0
    Dim db As sqlite3 Ptr = CPtr(sqlite3 Ptr, pDatabase)
    sqlite3_mutex_enter(db->mutex)
    Dim changeCount As sqlite3_int64 = db->nChange
    sqlite3_mutex_leave(db->mutex)
    Return changeCount
End Function

Function sqlite3_changes CDecl Alias "sqlite3_changes" ( _
    ByVal pDatabase As Any Ptr _
) As SQLITE_C_INT Export
    Return sqlite3VdbeSignedIntFromBits( _
        CULngInt(sqlite3_changes64(pDatabase)) And &HFFFFFFFFULL)
End Function

Function sqlite3_total_changes64 CDecl Alias "sqlite3_total_changes64" ( _
    ByVal pDatabase As Any Ptr _
) As sqlite3_int64 Export
    If pDatabase = 0 Then Return 0
    Dim db As sqlite3 Ptr = CPtr(sqlite3 Ptr, pDatabase)
    sqlite3_mutex_enter(db->mutex)
    Dim changeCount As sqlite3_int64 = db->nTotalChange
    sqlite3_mutex_leave(db->mutex)
    Return changeCount
End Function

Function sqlite3_total_changes CDecl Alias "sqlite3_total_changes" ( _
    ByVal pDatabase As Any Ptr _
) As SQLITE_C_INT Export
    Return sqlite3VdbeSignedIntFromBits( _
        CULngInt(sqlite3_total_changes64(pDatabase)) And &HFFFFFFFFULL)
End Function

Function sqlite3VdbeGetBoundValue CDecl Alias "sqlite3VdbeGetBoundValue" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal variableNumber As SQLITE_C_INT, _
    ByVal affinity As u8 _
) As SqliteVdbeMem Ptr Export
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse pVdbe->aVar = 0 OrElse _
       variableNumber <= 0 OrElse variableNumber > pVdbe->nVar Then Return 0

    Dim pSource As SqliteVdbeMem Ptr = @pVdbe->aVar[variableNumber - 1]
    If (pSource->flags And MEM_NULL) <> 0 Then Return 0

    Dim pValue As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, _
        sqlite3ValueNew(pVdbe->db))
    If pValue = 0 Then Return 0
    If sqlite3VdbeMemCopy(pValue, pSource) <> SQLITE_OK Then
        sqlite3ValueFree(pValue)
        Return 0
    End If
    sqlite3ValueApplyAffinity(pValue, affinity, SQLITE_UTF8)
    Return pValue
End Function

Sub sqlite3VdbeReprepareOnBind CDecl Alias "sqlite3VdbeReprepareOnBind" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal variableNumber As SQLITE_C_INT, _
    ByVal reprepareSmallInteger As SQLITE_C_INT _
) Export
    If pVdbe = 0 OrElse variableNumber <= 0 Then Return

    Dim variableMask As u32
    If variableNumber >= 32 Then
        ' The reprepare masks track variables 1-31 separately and all later ones together.
        variableMask = &H80000000
    Else
        variableMask = CULng(1) Shl (variableNumber - 1)
    End If
    pVdbe->expmask Or= variableMask
    If reprepareSmallInteger <> 0 Then pVdbe->smimask Or= variableMask
End Sub

#ifdef SQLITE_DEBUG
Sub sqlite3VdbeReleaseRegisters CDecl Alias "sqlite3VdbeReleaseRegisters" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal firstRegister As SQLITE_C_INT, _
    ByVal registerCount As SQLITE_C_INT, _
    ByVal preserveMask As u32, _
    ByVal undefineReleased As SQLITE_C_INT _
) Export
    If pParse = 0 OrElse pParse->db = 0 OrElse pParse->pVdbe = 0 OrElse _
       registerCount <= 0 OrElse firstRegister <= 0 OrElse _
       firstRegister > pParse->nMem OrElse _
       registerCount > pParse->nMem - firstRegister + 1 OrElse _
       (pParse->db->dbOptFlags And SQLITE_ReleaseReg) <> 0 Then Return

    If registerCount <= 31 AndAlso preserveMask <> 0 Then
        While registerCount > 0 AndAlso (preserveMask And 1) <> 0
            preserveMask Shr= 1
            firstRegister += 1
            registerCount -= 1
        Wend
        While registerCount > 0 AndAlso registerCount <= 32
            Dim topRegisterBit As u32 = CULng(1) Shl (registerCount - 1)
            If (preserveMask And topRegisterBit) = 0 Then Exit While
            preserveMask = preserveMask And Not topRegisterBit
            registerCount -= 1
        Wend
    End If

    If registerCount > 0 Then
        Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pParse->pVdbe)
        Dim address As SQLITE_C_INT = sqlite3VdbeAddOp3( _
            pVdbe, OP_ReleaseReg, firstRegister, registerCount, _
            sqlite3VdbeSignedIntFromBits(CULngInt(preserveMask)))
        If address >= 0 AndAlso undefineReleased <> 0 Then _
            sqlite3VdbeChangeP5(pVdbe, 1)
    End If
End Sub
#endif

Function sqlite3_bind_parameter_count CDecl Alias "sqlite3_bind_parameter_count" ( _
    ByVal pStatement As Any Ptr _
) As SQLITE_C_INT Export
    If pStatement = 0 Then Return 0
    Return CPtr(SqliteVdbe Ptr, pStatement)->nVar
End Function

Function sqlite3_bind_parameter_name CDecl Alias "sqlite3_bind_parameter_name" ( _
    ByVal pStatement As Any Ptr, _
    ByVal parameterIndex As SQLITE_C_INT _
) As Const ZString Ptr Export
    If pStatement = 0 Then Return 0
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pStatement)
    Return sqlite3VListNumToName(pVdbe->pVList, parameterIndex)
End Function

Function sqlite3VdbeParameterIndex CDecl Alias "sqlite3VdbeParameterIndex" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal nameLength As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pVdbe = 0 OrElse zName = 0 Then Return 0
    Return sqlite3VListNameToNum(pVdbe->pVList, zName, nameLength)
End Function

/' Move each binding value while holding the shared connection mutex. '/
Function sqlite3TransferBindings CDecl Alias "sqlite3TransferBindings" ( _
    ByVal pFromStatement As Any Ptr, _
    ByVal pToStatement As Any Ptr _
) As SQLITE_C_INT Export
    If pFromStatement = 0 OrElse pToStatement = 0 Then Return SQLITE_MISUSE

    Dim pFrom As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pFromStatement)
    Dim pTo As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pToStatement)
    If pFrom->db = 0 OrElse pTo->db = 0 OrElse pFrom->db <> pTo->db OrElse _
       pFrom->nVar <> pTo->nVar Then Return SQLITE_MISUSE
    If pFrom->nVar > 0 AndAlso (pFrom->aVar = 0 OrElse pTo->aVar = 0) Then _
        Return SQLITE_CORRUPT

    sqlite3_mutex_enter(pTo->db->mutex)
    For iVariable As SQLITE_C_INT = 0 To pFrom->nVar - 1
        sqlite3VdbeMemMove(@pTo->aVar[iVariable], @pFrom->aVar[iVariable])
    Next
    sqlite3_mutex_leave(pTo->db->mutex)
    Return SQLITE_OK
End Function

#ifndef SQLITE_OMIT_DEPRECATED
/' Deprecated public wrapper; transferring bindings also expires masked statements. '/
Function sqlite3_transfer_bindings CDecl Alias "sqlite3_transfer_bindings" ( _
    ByVal pFromStatement As Any Ptr, _
    ByVal pToStatement As Any Ptr _
) As SQLITE_C_INT Export
    If pFromStatement = 0 OrElse pToStatement = 0 Then Return SQLITE_MISUSE

    Dim pFrom As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pFromStatement)
    Dim pTo As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pToStatement)
    If pFrom->nVar <> pTo->nVar Then Return SQLITE_ERROR
    If pTo->db = 0 OrElse pFrom->db <> pTo->db Then Return SQLITE_MISUSE

    If pTo->expmask <> 0 Then sqlite3VdbeMarkExpired(pTo)
    If pFrom->expmask <> 0 Then sqlite3VdbeMarkExpired(pFrom)
    Return sqlite3TransferBindings(pFrom, pTo)
End Function
#endif

Function sqlite3_bind_parameter_index CDecl Alias "sqlite3_bind_parameter_index" ( _
    ByVal pStatement As Any Ptr, _
    ByVal zName As Const ZString Ptr _
) As SQLITE_C_INT Export
    If pStatement = 0 OrElse zName = 0 Then Return 0
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pStatement)
    Return sqlite3VdbeParameterIndex(pVdbe, zName, sqlite3Strlen30(zName))
End Function

Function sqlite3_clear_bindings CDecl Alias "sqlite3_clear_bindings" ( _
    ByVal pStatement As Any Ptr _
) As SQLITE_C_INT Export
    If pStatement = 0 Then Return SQLITE_MISUSE
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pStatement)
    If pVdbe->db = 0 Then Return SQLITE_MISUSE

    sqlite3_mutex_enter(pVdbe->db->mutex)
    If pVdbe->nVar > 0 AndAlso pVdbe->aVar = 0 Then
        pVdbe->db->errorCode = SQLITE_CORRUPT
        sqlite3_mutex_leave(pVdbe->db->mutex)
        Return SQLITE_CORRUPT
    End If
    For iVar As SQLITE_C_INT = 0 To pVdbe->nVar - 1
        sqlite3VdbeMemRelease(@pVdbe->aVar[iVar])
        pVdbe->aVar[iVar].flags = MEM_NULL
    Next
    If pVdbe->expmask <> 0 Then sqlite3VdbeMarkExpired(pVdbe)
    sqlite3_mutex_leave(pVdbe->db->mutex)
    Return SQLITE_OK
End Function

Private Function sqlite3VdbeBindInt64( _
    ByVal pStatement As Any Ptr, _
    ByVal parameterIndex As SQLITE_C_INT, _
    ByVal value As sqlite3_int64 _
) As SQLITE_C_INT
    Dim pVdbe As SqliteVdbe Ptr
    Dim zeroBasedIndex As SQLITE_C_INT
    Dim rc As SQLITE_C_INT = sqlite3VdbeBindCheck( _
        pStatement, parameterIndex, pVdbe, zeroBasedIndex)
    If rc <> SQLITE_OK Then Return rc

    If pVdbe->expmask <> 0 Then
        Dim expireMask As u32
        If zeroBasedIndex >= 31 Then
            expireMask = &H80000000
        Else
            expireMask = CULng(1) Shl zeroBasedIndex
        End If
        If (pVdbe->expmask And expireMask) <> 0 Then
            If (pVdbe->smimask And expireMask) <> 0 Then
                Dim wasSmallInteger As Long = IIf( _
                    (pVdbe->aVar[zeroBasedIndex].flags And MEM_INT) <> 0 AndAlso _
                    pVdbe->aVar[zeroBasedIndex].u.i >= 0 AndAlso _
                    pVdbe->aVar[zeroBasedIndex].u.i <= 1, 1, 0)
                Dim willBeSmallInteger As Long = IIf(value >= 0 AndAlso value <= 1, 1, 0)
                If wasSmallInteger <> willBeSmallInteger Then sqlite3VdbeMarkExpired(pVdbe)
            ElseIf (pVdbe->aVar[zeroBasedIndex].flags And MEM_INT) = 0 OrElse _
                   pVdbe->aVar[zeroBasedIndex].u.i <> value Then
                sqlite3VdbeMarkExpired(pVdbe)
            End If
        End If
    End If

    sqlite3VdbeMemSetInt64(@pVdbe->aVar[zeroBasedIndex], value)
    sqlite3_mutex_leave(pVdbe->db->mutex)
    Return SQLITE_OK
End Function

Function sqlite3_bind_int64 CDecl Alias "sqlite3_bind_int64" ( _
    ByVal pStatement As Any Ptr, _
    ByVal parameterIndex As SQLITE_C_INT, _
    ByVal value As sqlite3_int64 _
) As SQLITE_C_INT Export
    Return sqlite3VdbeBindInt64(pStatement, parameterIndex, value)
End Function

Function sqlite3_bind_int CDecl Alias "sqlite3_bind_int" ( _
    ByVal pStatement As Any Ptr, _
    ByVal parameterIndex As SQLITE_C_INT, _
    ByVal value As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Return sqlite3VdbeBindInt64(pStatement, parameterIndex, value)
End Function

Function sqlite3_bind_double CDecl Alias "sqlite3_bind_double" ( _
    ByVal pStatement As Any Ptr, _
    ByVal parameterIndex As SQLITE_C_INT, _
    ByVal value As Double _
) As SQLITE_C_INT Export
    Dim pVdbe As SqliteVdbe Ptr
    Dim zeroBasedIndex As SQLITE_C_INT
    Dim rc As SQLITE_C_INT = sqlite3VdbeBindUnbind( _
        pStatement, parameterIndex, pVdbe, zeroBasedIndex)
    If rc <> SQLITE_OK Then Return rc
    sqlite3VdbeMemSetDouble(@pVdbe->aVar[zeroBasedIndex], value)
    sqlite3_mutex_leave(pVdbe->db->mutex)
    Return SQLITE_OK
End Function

Function sqlite3_bind_null CDecl Alias "sqlite3_bind_null" ( _
    ByVal pStatement As Any Ptr, _
    ByVal parameterIndex As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Dim pVdbe As SqliteVdbe Ptr
    Dim zeroBasedIndex As SQLITE_C_INT
    Dim rc As SQLITE_C_INT = sqlite3VdbeBindUnbind( _
        pStatement, parameterIndex, pVdbe, zeroBasedIndex)
    If rc <> SQLITE_OK Then Return rc
    sqlite3_mutex_leave(pVdbe->db->mutex)
    Return SQLITE_OK
End Function

Function sqlite3_bind_text CDecl Alias "sqlite3_bind_text" ( _
    ByVal pStatement As Any Ptr, _
    ByVal parameterIndex As SQLITE_C_INT, _
    ByVal zText As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal xDestructor As Any Ptr _
) As SQLITE_C_INT Export
    Return bindText(pStatement, parameterIndex, CPtr(Any Ptr, zText), _
        nByte, xDestructor, SQLITE_UTF8)
End Function

Function sqlite3_bind_text16 CDecl Alias "sqlite3_bind_text16" ( _
    ByVal pStatement As Any Ptr, _
    ByVal parameterIndex As SQLITE_C_INT, _
    ByVal zText As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal xDestructor As Any Ptr _
) As SQLITE_C_INT Export
    Dim evenLength As sqlite3_int64 = CLngInt(nByte) And Not 1LL
    Return bindText(pStatement, parameterIndex, zText, _
        evenLength, xDestructor, SQLITE_UTF16NATIVE)
End Function

Function sqlite3_bind_text64 CDecl Alias "sqlite3_bind_text64" ( _
    ByVal pStatement As Any Ptr, _
    ByVal parameterIndex As SQLITE_C_INT, _
    ByVal zText As Const ZString Ptr, _
    ByVal nByte As sqlite3_uint64, _
    ByVal xDestructor As Any Ptr, _
    ByVal encodingHint As u8 _
) As SQLITE_C_INT Export
    Dim selectedEncoding As u8 = encodingHint
    Dim selectedLength As sqlite3_uint64 = nByte
    If selectedEncoding <> SQLITE_UTF8 AndAlso selectedEncoding <> SQLITE_UTF8_ZT Then
        If selectedEncoding = SQLITE_UTF16 OrElse _
           selectedEncoding = SQLITE_UTF16_ALIGNED Then selectedEncoding = SQLITE_UTF16NATIVE
        selectedLength = selectedLength And Not 1ULL
    End If
    Return sqlite3VdbeBindData64(pStatement, parameterIndex, CPtr(Any Ptr, zText), _
        selectedLength, xDestructor, selectedEncoding)
End Function

Function sqlite3_bind_blob CDecl Alias "sqlite3_bind_blob" ( _
    ByVal pStatement As Any Ptr, _
    ByVal parameterIndex As SQLITE_C_INT, _
    ByVal pBlob As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal xDestructor As Any Ptr _
) As SQLITE_C_INT Export
    Return bindText(pStatement, parameterIndex, pBlob, _
        nByte, xDestructor, 0)
End Function

Function sqlite3_bind_blob64 CDecl Alias "sqlite3_bind_blob64" ( _
    ByVal pStatement As Any Ptr, _
    ByVal parameterIndex As SQLITE_C_INT, _
    ByVal pBlob As Any Ptr, _
    ByVal nByte As sqlite3_uint64, _
    ByVal xDestructor As Any Ptr _
) As SQLITE_C_INT Export
    Return sqlite3VdbeBindData64(pStatement, parameterIndex, pBlob, _
        nByte, xDestructor, 0)
End Function

Function sqlite3_bind_pointer CDecl Alias "sqlite3_bind_pointer" ( _
    ByVal pStatement As Any Ptr, _
    ByVal parameterIndex As SQLITE_C_INT, _
    ByVal pPointer As Any Ptr, _
    ByVal zPointerType As Const ZString Ptr, _
    ByVal xDestructor As Any Ptr _
) As SQLITE_C_INT Export
    Dim xDelete As sqlite3MemDestructor = CPtr(sqlite3MemDestructor, xDestructor)
    Dim pVdbe As SqliteVdbe Ptr
    Dim zeroBasedIndex As SQLITE_C_INT
    Dim rc As SQLITE_C_INT = sqlite3VdbeBindUnbind( _
        pStatement, parameterIndex, pVdbe, zeroBasedIndex)
    If rc <> SQLITE_OK Then
        If xDelete <> 0 Then xDelete(pPointer)
        Return rc
    End If
    sqlite3VdbeMemSetPointer( _
        @pVdbe->aVar[zeroBasedIndex], pPointer, zPointerType, xDelete)
    sqlite3_mutex_leave(pVdbe->db->mutex)
    Return SQLITE_OK
End Function

Function sqlite3_bind_zeroblob CDecl Alias "sqlite3_bind_zeroblob" ( _
    ByVal pStatement As Any Ptr, _
    ByVal parameterIndex As SQLITE_C_INT, _
    ByVal nByte As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Dim pVdbe As SqliteVdbe Ptr
    Dim zeroBasedIndex As SQLITE_C_INT
    Dim rc As SQLITE_C_INT = sqlite3VdbeBindUnbind( _
        pStatement, parameterIndex, pVdbe, zeroBasedIndex)
    If rc <> SQLITE_OK Then Return rc
    sqlite3VdbeMemSetZeroBlob(@pVdbe->aVar[zeroBasedIndex], nByte)
    sqlite3_mutex_leave(pVdbe->db->mutex)
    Return SQLITE_OK
End Function

Function sqlite3_bind_zeroblob64 CDecl Alias "sqlite3_bind_zeroblob64" ( _
    ByVal pStatement As Any Ptr, _
    ByVal parameterIndex As SQLITE_C_INT, _
    ByVal nByte As sqlite3_uint64 _
) As SQLITE_C_INT Export
    If pStatement = 0 Then Return SQLITE_MISUSE
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pStatement)
    If pVdbe->db = 0 Then Return SQLITE_MISUSE
    sqlite3_mutex_enter(pVdbe->db->mutex)
    If nByte > CULngInt(pVdbe->db->lengthLimit) Then
        pVdbe->db->errorCode = SQLITE_TOOBIG
        sqlite3_mutex_leave(pVdbe->db->mutex)
        Return SQLITE_TOOBIG
    End If
    Dim rc As SQLITE_C_INT = sqlite3_bind_zeroblob( _
        pStatement, parameterIndex, CInt(nByte))
    sqlite3_mutex_leave(pVdbe->db->mutex)
    Return rc
End Function

Function sqlite3_bind_value CDecl Alias "sqlite3_bind_value" ( _
    ByVal pStatement As Any Ptr, _
    ByVal parameterIndex As SQLITE_C_INT, _
    ByVal pValue As Any Ptr _
) As SQLITE_C_INT Export
    If pValue = 0 Then Return sqlite3_bind_null(pStatement, parameterIndex)
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pValue)
    Dim valueFlags As UShort = pMem->flags

    If (valueFlags And MEM_NULL) <> 0 Then
        Return sqlite3_bind_null(pStatement, parameterIndex)
    ElseIf (valueFlags And (MEM_REAL Or MEM_INTREAL)) <> 0 Then
        Dim value As Double
        If (valueFlags And MEM_REAL) <> 0 Then
            value = pMem->u.r
        Else
            value = CDbl(pMem->u.i)
        End If
        Return sqlite3_bind_double(pStatement, parameterIndex, value)
    ElseIf (valueFlags And MEM_INT) <> 0 Then
        Return sqlite3_bind_int64(pStatement, parameterIndex, pMem->u.i)
    ElseIf (valueFlags And MEM_STR) <> 0 Then
        Return bindText(pStatement, parameterIndex, pMem->z, pMem->n, _
            CPtr(Any Ptr, -1), pMem->enc)
    ElseIf (valueFlags And MEM_ZERO) <> 0 Then
        Return sqlite3_bind_zeroblob(pStatement, parameterIndex, pMem->u.nZero)
    Else
        Return bindText(pStatement, parameterIndex, pMem->z, pMem->n, _
            CPtr(Any Ptr, -1), 0)
    End If
End Function

/' end of sqlite3_vdbe_stmt.bas '/
