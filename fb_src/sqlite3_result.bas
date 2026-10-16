/'
    Project: SQLite FreeBASIC port

    File: sqlite3_result.bas

    Purpose:

        Store SQL function results and expose SQL-function context APIs.

    Responsibilities:

        - Preserve result value, text/blob ownership, subtype, and error state.
        - Apply the output encoding and connection length limit.
        - Invoke caller destructors when result data cannot be retained.
        - Cache per-opcode auxiliary data with its caller-supplied destructor.
        - Expose aggregate, virtual-table, and statement-time context state.
        - Return the active SQL function name in percentile-enabled builds.

    This file intentionally does NOT contain:

        - SQL function registration or invocation.
        - Statement execution or VDBE opcode dispatch.
'/

#lang "fb"
#include once "sqlite3_result.bi"
#include once "sqlite3_vdbe_api.bi"
#include once "sqlite3_vdbe_mem_text.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_rowset.bi"
#include once "sqlite3_straccum.bi"
#include once "sqlite3_vfs.bi"
#include once "sqlite3_constants.bi"

Declare Function sqlite3ResultErrStr CDecl Alias "sqlite3ErrStr" ( _
    ByVal resultCode As SQLITE_C_INT _
) As Const ZString Ptr
Declare Sub sqlite3_result_error_toobig CDecl Alias "sqlite3_result_error_toobig" ( _
    ByVal pContext As Any Ptr _
)
Declare Sub sqlite3_result_error_nomem CDecl Alias "sqlite3_result_error_nomem" ( _
    ByVal pContext As Any Ptr _
)
Declare Function sqlite3_result_zeroblob64 CDecl Alias "sqlite3_result_zeroblob64" ( _
    ByVal pContext As Any Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As SQLITE_C_INT

/' ------------------------------------------------------------------------- '/
/' Destructor values used by SQLite result APIs '/

Private Function sqlite3ResultTransientDestructor() As sqlite3MemDestructor
    Return CPtr(sqlite3MemDestructor, -1)
End Function

Private Function sqlite3ResultDynamicDestructor() As sqlite3MemDestructor
    Return @sqlite3RowSetClear
End Function

Private Function sqlite3ResultDestructor(ByVal pDestructor As Any Ptr) As sqlite3MemDestructor
    Return CPtr(sqlite3MemDestructor, pDestructor)
End Function

Private Sub sqlite3ResultInvokeDestructor( _
    ByVal zValue As Any Ptr, _
    ByVal xDestructor As sqlite3MemDestructor, _
    ByVal pContext As SqliteResultContext Ptr _
)
    If xDestructor = 0 OrElse xDestructor = sqlite3ResultTransientDestructor() Then Return
    If xDestructor = sqlite3ResultDynamicDestructor() Then
        If pContext <> 0 AndAlso pContext->pOut <> 0 Then
            sqlite3DbFree(pContext->pOut->db, zValue)
        End If
    Else
        xDestructor(zValue)
    End If
    If pContext <> 0 Then sqlite3_result_error_toobig(pContext)
End Sub

Private Function sqlite3ResultContext(ByVal pContext As Any Ptr) As SqliteResultContext Ptr
    If pContext = 0 Then Return 0
    Dim pResult As SqliteResultContext Ptr = CPtr(SqliteResultContext Ptr, pContext)
    If pResult->pOut = 0 Then Return 0
    Return pResult
End Function

Private Function sqlite3ResultMemTooBig(ByVal pMem As SqliteVdbeMem Ptr) As SQLITE_C_INT
    If pMem = 0 OrElse pMem->db = 0 Then Return 0
    Dim totalBytes As sqlite3_int64 = pMem->n
    If (pMem->flags And MEM_ZERO) <> 0 Then totalBytes += pMem->u.nZero
    If totalBytes > pMem->db->lengthLimit Then Return 1
    Return 0
End Function

Private Function sqlite3ResultSetStringOrError( _
    ByVal pContext As Any Ptr, _
    ByVal zValue As Const ZString Ptr, _
    ByVal nByte As sqlite3_int64, _
    ByVal textEncoding As u8, _
    ByVal xDestructor As sqlite3MemDestructor _
) As SQLITE_C_INT
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then Return SQLITE_MISUSE

    Dim rc As SQLITE_C_INT
    If textEncoding = SQLITE_UTF8 Then
        rc = sqlite3VdbeMemSetText(pResult->pOut, zValue, nByte, xDestructor)
    Else
        rc = sqlite3VdbeMemSetStr(pResult->pOut, zValue, nByte, textEncoding, xDestructor)
    End If

    If rc = SQLITE_TOOBIG Then
        sqlite3_result_error_toobig(pResult)
        Return rc
    ElseIf rc = SQLITE_NOMEM Then
        sqlite3_result_error_nomem(pResult)
        Return rc
    ElseIf rc <> SQLITE_OK Then
        pResult->isError = rc
        Return rc
    End If

    Dim outputEncoding As u8 = pResult->enc
    If outputEncoding = SQLITE_UTF16 Then outputEncoding = SQLITE_UTF16NATIVE
    If outputEncoding = SQLITE_UTF8 OrElse outputEncoding = SQLITE_UTF16LE OrElse _
       outputEncoding = SQLITE_UTF16BE Then
        rc = sqlite3VdbeChangeEncoding(pResult->pOut, outputEncoding)
        If rc <> SQLITE_OK Then
            sqlite3_result_error_nomem(pResult)
            Return rc
        End If
    End If

    If sqlite3ResultMemTooBig(pResult->pOut) <> 0 Then
        sqlite3_result_error_toobig(pResult)
        Return SQLITE_TOOBIG
    End If
    Return SQLITE_OK
End Function

/' ------------------------------------------------------------------------- '/
/' Result error state '/

Sub sqlite3_result_error_toobig CDecl Alias "sqlite3_result_error_toobig" ( _
    ByVal pContext As Any Ptr _
) Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then Return
    pResult->isError = SQLITE_TOOBIG
    sqlite3VdbeMemSetStr(pResult->pOut, StrPtr("string or blob too big"), -1, _
                         SQLITE_UTF8, 0)
End Sub

Sub sqlite3_result_error_nomem CDecl Alias "sqlite3_result_error_nomem" ( _
    ByVal pContext As Any Ptr _
) Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then Return
    sqlite3VdbeMemSetNull(pResult->pOut)
    pResult->isError = SQLITE_NOMEM
    sqlite3OomFault(pResult->pOut->db)
End Sub

Sub sqlite3_result_error_code CDecl Alias "sqlite3_result_error_code" ( _
    ByVal pContext As Any Ptr, _
    ByVal errorCode As SQLITE_C_INT _
) Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then Return
    pResult->isError = IIf(errorCode <> SQLITE_OK, errorCode, -1)
    If (pResult->pOut->flags And MEM_NULL) <> 0 Then
        sqlite3ResultSetStringOrError(pResult, sqlite3ResultErrStr(errorCode), -1, _
                                      SQLITE_UTF8, 0)
    End If
End Sub

Sub sqlite3_result_error CDecl Alias "sqlite3_result_error" ( _
    ByVal pContext As Any Ptr, _
    ByVal zError As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT _
) Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then Return
    pResult->isError = SQLITE_ERROR
    sqlite3ResultSetStringOrError(pResult, zError, nByte, SQLITE_UTF8, _
                                  sqlite3ResultTransientDestructor())
End Sub

#ifndef SQLITE_OMIT_UTF16
Sub sqlite3_result_error16 CDecl Alias "sqlite3_result_error16" ( _
    ByVal pContext As Any Ptr, _
    ByVal zError As Any Ptr, _
    ByVal nByte As SQLITE_C_INT _
) Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then Return
    pResult->isError = SQLITE_ERROR
    sqlite3ResultSetStringOrError(pResult, CPtr(Const ZString Ptr, zError), _
                                  nByte, SQLITE_UTF16NATIVE, _
                                  sqlite3ResultTransientDestructor())
End Sub
#endif

/' ------------------------------------------------------------------------- '/
/' Scalar result values '/

Sub sqlite3_result_double CDecl Alias "sqlite3_result_double" ( _
    ByVal pContext As Any Ptr, _
    ByVal value As Double _
) Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then Return
    sqlite3VdbeMemSetDouble(pResult->pOut, value)
End Sub

Sub sqlite3_result_int CDecl Alias "sqlite3_result_int" ( _
    ByVal pContext As Any Ptr, _
    ByVal value As SQLITE_C_INT _
) Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then Return
    sqlite3VdbeMemSetInt64(pResult->pOut, value)
End Sub

Sub sqlite3_result_int64 CDecl Alias "sqlite3_result_int64" ( _
    ByVal pContext As Any Ptr, _
    ByVal value As sqlite3_int64 _
) Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then Return
    sqlite3VdbeMemSetInt64(pResult->pOut, value)
End Sub

Sub sqlite3_result_null CDecl Alias "sqlite3_result_null" ( _
    ByVal pContext As Any Ptr _
) Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then Return
    sqlite3VdbeMemSetNull(pResult->pOut)
End Sub

Sub sqlite3_result_pointer CDecl Alias "sqlite3_result_pointer" ( _
    ByVal pContext As Any Ptr, _
    ByVal value As Any Ptr, _
    ByVal zType As Const ZString Ptr, _
    ByVal pDestructor As Any Ptr _
) Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then
        sqlite3ResultInvokeDestructor(value, sqlite3ResultDestructor(pDestructor), 0)
        Return
    End If
    sqlite3VdbeMemRelease(pResult->pOut)
    pResult->pOut->flags = MEM_NULL
    sqlite3VdbeMemSetPointer(pResult->pOut, value, zType, _
                             sqlite3ResultDestructor(pDestructor))
End Sub

Sub sqlite3_result_subtype CDecl Alias "sqlite3_result_subtype" ( _
    ByVal pContext As Any Ptr, _
    ByVal subtype As SQLITE_C_UINT _
) Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then Return
    pResult->pOut->eSubtype = CByte(subtype And &HFF)
    pResult->pOut->flags = pResult->pOut->flags Or MEM_SUBTYPE
End Sub

Sub sqlite3_result_value CDecl Alias "sqlite3_result_value" ( _
    ByVal pContext As Any Ptr, _
    ByVal pValue As Any Ptr _
) Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then Return
    If pValue = 0 Then
        sqlite3_result_null(pResult)
        Return
    End If

    Dim rc As SQLITE_C_INT = sqlite3VdbeMemCopy(pResult->pOut, pValue)
    If rc = SQLITE_OK Then
        Dim outputEncoding As u8 = pResult->enc
        If outputEncoding = SQLITE_UTF16 Then outputEncoding = SQLITE_UTF16NATIVE
        If outputEncoding = SQLITE_UTF8 OrElse outputEncoding = SQLITE_UTF16LE OrElse _
           outputEncoding = SQLITE_UTF16BE Then
            rc = sqlite3VdbeChangeEncoding(pResult->pOut, outputEncoding)
        End If
    End If
    If rc = SQLITE_NOMEM Then
        sqlite3_result_error_nomem(pResult)
    ElseIf rc <> SQLITE_OK Then
        pResult->isError = rc
    ElseIf sqlite3ResultMemTooBig(pResult->pOut) <> 0 Then
        sqlite3_result_error_toobig(pResult)
    End If
End Sub

/' ------------------------------------------------------------------------- '/
/' Text and blob result values '/

Sub sqlite3_result_blob CDecl Alias "sqlite3_result_blob" ( _
    ByVal pContext As Any Ptr, _
    ByVal zBlob As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal pDestructor As Any Ptr _
) Export
    Dim xDestructor As sqlite3MemDestructor = sqlite3ResultDestructor(pDestructor)
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then
        sqlite3ResultInvokeDestructor(zBlob, xDestructor, 0)
        Return
    End If
    If zBlob = 0 Then
        sqlite3VdbeMemSetNull(pResult->pOut)
    ElseIf nByte < 0 Then
        pResult->isError = SQLITE_MISUSE
        sqlite3ResultInvokeDestructor(zBlob, xDestructor, pResult)
    Else
        sqlite3ResultSetStringOrError(pResult, CPtr(Const ZString Ptr, zBlob), _
                                      nByte, 0, xDestructor)
    End If
End Sub

Sub sqlite3_result_blob64 CDecl Alias "sqlite3_result_blob64" ( _
    ByVal pContext As Any Ptr, _
    ByVal zBlob As Any Ptr, _
    ByVal nByte As sqlite3_uint64, _
    ByVal pDestructor As Any Ptr _
) Export
    Dim xDestructor As sqlite3MemDestructor = sqlite3ResultDestructor(pDestructor)
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then
        sqlite3ResultInvokeDestructor(zBlob, xDestructor, 0)
        Return
    End If
    If zBlob = 0 Then
        sqlite3VdbeMemSetNull(pResult->pOut)
    ElseIf nByte > SQLITE_MAX_LENGTH OrElse nByte > &H7FFFFFFF Then
        sqlite3ResultInvokeDestructor(zBlob, xDestructor, pResult)
    Else
        sqlite3ResultSetStringOrError(pResult, CPtr(Const ZString Ptr, zBlob), _
                                      CLngInt(nByte), 0, xDestructor)
    End If
End Sub

Sub sqlite3_result_text CDecl Alias "sqlite3_result_text" ( _
    ByVal pContext As Any Ptr, _
    ByVal zText As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal pDestructor As Any Ptr _
) Export
    Dim xDestructor As sqlite3MemDestructor = sqlite3ResultDestructor(pDestructor)
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then
        sqlite3ResultInvokeDestructor(CPtr(Any Ptr, zText), xDestructor, 0)
        Return
    End If
    sqlite3ResultSetStringOrError(pResult, zText, nByte, SQLITE_UTF8, xDestructor)
End Sub

Sub sqlite3_result_text64 CDecl Alias "sqlite3_result_text64" ( _
    ByVal pContext As Any Ptr, _
    ByVal zText As Const ZString Ptr, _
    ByVal nByte As sqlite3_uint64, _
    ByVal pDestructor As Any Ptr, _
    ByVal textEncoding As UByte _
) Export
    Dim xDestructor As sqlite3MemDestructor = sqlite3ResultDestructor(pDestructor)
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then
        sqlite3ResultInvokeDestructor(CPtr(Any Ptr, zText), xDestructor, 0)
        Return
    End If

    If textEncoding = SQLITE_UTF16 Then textEncoding = SQLITE_UTF16NATIVE
    If textEncoding <> SQLITE_UTF8 AndAlso textEncoding <> SQLITE_UTF16LE AndAlso _
       textEncoding <> SQLITE_UTF16BE Then
        pResult->isError = SQLITE_MISUSE
        sqlite3ResultInvokeDestructor(CPtr(Any Ptr, zText), xDestructor, pResult)
        Return
    End If
    If textEncoding <> SQLITE_UTF8 Then nByte = nByte And Not CULngInt(1)
    If nByte > SQLITE_MAX_LENGTH OrElse nByte > &H7FFFFFFF Then
        sqlite3ResultInvokeDestructor(CPtr(Any Ptr, zText), xDestructor, pResult)
        Return
    End If
    sqlite3ResultSetStringOrError(pResult, zText, CLngInt(nByte), textEncoding, xDestructor)
End Sub

#ifndef SQLITE_OMIT_UTF16
Sub sqlite3_result_text16 CDecl Alias "sqlite3_result_text16" ( _
    ByVal pContext As Any Ptr, _
    ByVal zText As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal pDestructor As Any Ptr _
) Export
    Dim byteCount As sqlite3_int64 = nByte
    If byteCount >= 0 Then byteCount = byteCount And Not 1
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    Dim xDestructor As sqlite3MemDestructor = sqlite3ResultDestructor(pDestructor)
    If pResult = 0 Then
        sqlite3ResultInvokeDestructor(zText, xDestructor, 0)
        Return
    End If
    sqlite3ResultSetStringOrError(pResult, CPtr(Const ZString Ptr, zText), _
                                  byteCount, SQLITE_UTF16NATIVE, xDestructor)
End Sub

Sub sqlite3_result_text16le CDecl Alias "sqlite3_result_text16le" ( _
    ByVal pContext As Any Ptr, _
    ByVal zText As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal pDestructor As Any Ptr _
) Export
    Dim byteCount As sqlite3_int64 = nByte
    If byteCount >= 0 Then byteCount = byteCount And Not 1
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    Dim xDestructor As sqlite3MemDestructor = sqlite3ResultDestructor(pDestructor)
    If pResult = 0 Then
        sqlite3ResultInvokeDestructor(zText, xDestructor, 0)
        Return
    End If
    sqlite3ResultSetStringOrError(pResult, CPtr(Const ZString Ptr, zText), _
                                  byteCount, SQLITE_UTF16LE, xDestructor)
End Sub

Sub sqlite3_result_text16be CDecl Alias "sqlite3_result_text16be" ( _
    ByVal pContext As Any Ptr, _
    ByVal zText As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal pDestructor As Any Ptr _
) Export
    Dim byteCount As sqlite3_int64 = nByte
    If byteCount >= 0 Then byteCount = byteCount And Not 1
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    Dim xDestructor As sqlite3MemDestructor = sqlite3ResultDestructor(pDestructor)
    If pResult = 0 Then
        sqlite3ResultInvokeDestructor(zText, xDestructor, 0)
        Return
    End If
    sqlite3ResultSetStringOrError(pResult, CPtr(Const ZString Ptr, zText), _
                                  byteCount, SQLITE_UTF16BE, xDestructor)
End Sub
#endif

Sub sqlite3_result_zeroblob CDecl Alias "sqlite3_result_zeroblob" ( _
    ByVal pContext As Any Ptr, _
    ByVal nByte As SQLITE_C_INT _
) Export
    Dim zeroCount As SQLITE_C_INT = nByte
    If zeroCount < 0 Then zeroCount = 0
    sqlite3_result_zeroblob64(pContext, CULngInt(zeroCount))
End Sub

Function sqlite3_result_zeroblob64 CDecl Alias "sqlite3_result_zeroblob64" ( _
    ByVal pContext As Any Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As SQLITE_C_INT Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then Return SQLITE_MISUSE
    Dim lengthLimit As SQLITE_C_INT = SQLITE_MAX_LENGTH
    If pResult->pOut->db <> 0 Then lengthLimit = pResult->pOut->db->lengthLimit
    If nByte > SQLITE_MAX_LENGTH OrElse nByte > CULngInt(lengthLimit) OrElse _
       nByte > &H7FFFFFFF Then
        sqlite3_result_error_toobig(pResult)
        Return SQLITE_TOOBIG
    End If
    sqlite3VdbeMemSetZeroBlob(pResult->pOut, CInt(nByte))
    Return SQLITE_OK
End Function

Sub sqlite3_result_str CDecl Alias "sqlite3_result_str" ( _
    ByVal pContext As Any Ptr, _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal ownership As SQLITE_C_INT _
) Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 OrElse pAccum = 0 Then Return

    If pAccum->accError = SQLITE_OK Then
        If pAccum->nChar = 0 Then
            sqlite3ResultSetStringOrError(pResult, StrPtr(""), 0, SQLITE_UTF8, 0)
            sqlite3_str_reset(pAccum)
        Else
            Dim zText As Const ZString Ptr = sqlite3_str_value(pAccum)
            If ownership = SQLITE_COPY Then
                sqlite3ResultSetStringOrError(pResult, zText, pAccum->nChar, _
                                              SQLITE_UTF8, sqlite3ResultTransientDestructor())
            Else
                Dim rc As SQLITE_C_INT = sqlite3ResultSetStringOrError( _
                    pResult, zText, pAccum->nChar, SQLITE_UTF8, sqlite3ResultDynamicDestructor())
                If rc = SQLITE_OK Then pResult->pOut->flags = pResult->pOut->flags Or MEM_TERM
                sqlite3StrAccumInit(pAccum, pAccum->db, 0, 0, pAccum->mxAlloc)
            End If
        End If
    ElseIf pAccum->accError = SQLITE_NOMEM Then
        sqlite3_result_error_nomem(pResult)
    Else
        sqlite3_result_error_toobig(pResult)
    End If

    If ownership = SQLITE_FINISH Then sqlite3_str_free(pAccum)
End Sub

#ifndef SQLITE_UNTESTABLE
/' Convert an integer result to MEM_IntReal for the result-intreal test control. '/
Sub sqlite3ResultIntReal CDecl Alias "sqlite3ResultIntReal" ( _
    ByVal pContext As Any Ptr _
) Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then Return
    If (pResult->pOut->flags And MEM_INT) <> 0 Then
        pResult->pOut->flags = pResult->pOut->flags And Not MEM_INT
        pResult->pOut->flags = pResult->pOut->flags Or MEM_INTREAL
    End If
End Sub
#endif

/' Return whether a virtual-table xColumn call represents an unchanged column. '/
Function sqlite3_vtab_nochange CDecl Alias "sqlite3_vtab_nochange" ( _
    ByVal pContext As Any Ptr _
) As SQLITE_C_INT Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then Return 0
    Return sqlite3_value_nochange(pResult->pOut)
End Function

/' Keep statement time stable for every request made during one execution. '/
Function sqlite3StmtCurrentTime CDecl Alias "sqlite3StmtCurrentTime" ( _
    ByVal pContext As Any Ptr _
) As sqlite3_int64 Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 OrElse pResult->pOut->db = 0 Then Return 0

    Dim localTime As sqlite3_int64 = 0
    Dim pTime As sqlite3_int64 Ptr = @localTime
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pResult->pVdbe)
#ifndef SQLITE_ENABLE_STAT4
    If pVdbe = 0 Then Return 0
    pTime = @pVdbe->iCurrentTime
#else
    If pVdbe <> 0 Then pTime = @pVdbe->iCurrentTime
#endif

    If pTime[0] = 0 Then
        Dim pVfs As sqlite3_vfs Ptr = CPtr(sqlite3_vfs Ptr, pResult->pOut->db->pVfs)
        If pVfs = 0 OrElse sqlite3OsCurrentTimeInt64(pVfs, pTime) <> SQLITE_OK Then _
            pTime[0] = 0
    End If
    Return pTime[0]
End Function

/' ------------------------------------------------------------------------- '/
/' Context access '/

Function sqlite3_user_data CDecl Alias "sqlite3_user_data" ( _
    ByVal pContext As Any Ptr _
) As Any Ptr Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 OrElse pResult->pFunc = 0 Then Return 0
    Dim pFunction As SqliteFuncDefPrefix Ptr = CPtr(SqliteFuncDefPrefix Ptr, pResult->pFunc)
    Return pFunction->pUserData
End Function

Function sqlite3_context_db_handle CDecl Alias "sqlite3_context_db_handle" ( _
    ByVal pContext As Any Ptr _
) As Any Ptr Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then Return 0
    Return pResult->pOut->db
End Function

Type SqliteAuxDataDeleteProc As Sub CDecl (ByVal pData As Any Ptr)

Private Function sqlite3ResultFindAuxData( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal argumentIndex As SQLITE_C_INT, _
    ByVal opcode As SQLITE_C_INT _
) As SqliteVdbeAuxData Ptr
    If pVdbe = 0 Then Return 0
    Dim pAux As SqliteVdbeAuxData Ptr = pVdbe->pAuxData
    While pAux <> 0
        If pAux->iAuxArg = argumentIndex AndAlso _
           (pAux->iAuxOp = opcode OrElse argumentIndex < 0) Then Return pAux
        pAux = CPtr(SqliteVdbeAuxData Ptr, pAux->pNextAux)
    Wend
    Return 0
End Function

Function sqlite3_get_auxdata CDecl Alias "sqlite3_get_auxdata" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentIndex As SQLITE_C_INT _
) As Any Ptr Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 OrElse pResult->pVdbe = 0 Then Return 0
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pResult->pVdbe)
    Dim pAux As SqliteVdbeAuxData Ptr = _
        sqlite3ResultFindAuxData(pVdbe, argumentIndex, pResult->iOp)
    If pAux = 0 Then Return 0
    Return pAux->pAux
End Function

Sub sqlite3_set_auxdata CDecl Alias "sqlite3_set_auxdata" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentIndex As SQLITE_C_INT, _
    ByVal pAuxDataValue As Any Ptr, _
    ByVal pDeleteArgument As Any Ptr _
) Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 Then Return
    Dim xDelete As SqliteAuxDataDeleteProc = _
        CPtr(SqliteAuxDataDeleteProc, pDeleteArgument)
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pResult->pVdbe)
    Dim pAux As SqliteVdbeAuxData Ptr = 0
    If pVdbe = 0 OrElse pVdbe->db = 0 Then GoTo auxdata_failed

    pAux = sqlite3ResultFindAuxData(pVdbe, argumentIndex, pResult->iOp)
    If pAux = 0 Then
        pAux = CPtr(SqliteVdbeAuxData Ptr, _
            sqlite3DbMallocZero(pVdbe->db, SizeOf(SqliteVdbeAuxData)))
        If pAux = 0 Then GoTo auxdata_failed
        pAux->iAuxOp = pResult->iOp
        pAux->iAuxArg = argumentIndex
        pAux->pNextAux = pVdbe->pAuxData
        pVdbe->pAuxData = pAux
        If pResult->isError = 0 Then pResult->isError = -1
    ElseIf pAux->xDeleteAux <> 0 Then
        Dim xOldDelete As SqliteAuxDataDeleteProc = _
            CPtr(SqliteAuxDataDeleteProc, pAux->xDeleteAux)
        xOldDelete(pAux->pAux)
    End If

    pAux->pAux = pAuxDataValue
    pAux->xDeleteAux = pDeleteArgument
    Return

auxdata_failed:
    If xDelete <> 0 Then xDelete(pAuxDataValue)
End Sub

/' Allocate and clear the aggregate state buffer on its first request. '/
Private Function createAggContext( _
    ByVal pMem As SqliteVdbeMem Ptr, _
    ByVal pFunction As SqliteFuncDef Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As Any Ptr
    If pMem = 0 Then Return 0
    If nByte <= 0 Then
        sqlite3VdbeMemSetNull(pMem)
        pMem->z = 0
        Return 0
    End If

    sqlite3VdbeMemClearAndResize(pMem, nByte)
    pMem->flags = MEM_AGG
    pMem->u.pDef = pFunction
    If pMem->z <> 0 Then
        For iByte As SQLITE_C_INT = 0 To nByte - 1
            pMem->z[iByte] = 0
        Next
    End If
    Return pMem->z
End Function

Function sqlite3_aggregate_context CDecl Alias "sqlite3_aggregate_context" ( _
    ByVal pContext As Any Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As Any Ptr Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 OrElse pResult->pFunc = 0 OrElse pResult->pMem = 0 Then Return 0
    Dim pFunction As SqliteFuncDef Ptr = CPtr(SqliteFuncDef Ptr, pResult->pFunc)
    If pFunction->xFinalize = 0 Then Return 0
    Dim pMem As SqliteVdbeMem Ptr = pResult->pMem
    If (pMem->flags And MEM_AGG) = 0 Then Return createAggContext(pMem, pFunction, nByte)
    Return pMem->z
End Function

Function sqlite3_aggregate_count CDecl Alias "sqlite3_aggregate_count" ( _
    ByVal pContext As Any Ptr _
) As SQLITE_C_INT Export
    Dim pResult As SqliteResultContext Ptr = sqlite3ResultContext(pContext)
    If pResult = 0 OrElse pResult->pMem = 0 Then Return 0
    Return pResult->pMem->n
End Function

#ifdef SQLITE_ENABLE_PERCENTILE
Function sqlite3VdbeFuncName CDecl Alias "sqlite3VdbeFuncName" ( _
    ByVal pContext As SqliteResultContext Ptr _
) As Const ZString Ptr
    If pContext = 0 OrElse pContext->pFunc = 0 Then Return 0
    Dim pFunction As SqliteFuncDef Ptr = CPtr(SqliteFuncDef Ptr, pContext->pFunc)
    Return pFunction->zName
End Function
#endif

/' end of sqlite3_result.bas '/
