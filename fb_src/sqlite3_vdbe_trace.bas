/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_trace.bas

    Purpose:

        Expand bound parameters in retained SQL text for diagnostics.

    Responsibilities:

        - Find host parameters without matching text inside literals or comments.
        - Render bound values as SQL literals under the connection length limit.
        - Mark each line when expansion occurs inside nested VDBE execution.
        - Dispatch legacy and version-2 statement trace callbacks.

    This file intentionally does NOT contain:

        - Trace callback registration, which lives with connection state.
        - Profile callback dispatch, SQL normalization, or EXPLAIN rendering.
'/ 

#lang "fb"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_straccum.bi"
#include once "sqlite3_vdbe_api.bi"
#include once "sqlite3_numeric.bi"
#include once "sqlite3_tokens.bi"
#include once "sqlite3_vfs.bi"

Declare Function sqlite3GetToken CDecl Alias "sqlite3GetToken" ( _
    ByVal zSql As Const UByte Ptr, _
    ByVal pTokenType As SQLITE_C_INT Ptr _
) As sqlite3_int64
Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal zText As Const ZString Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3_str_appendf CDecl Alias "sqlite3_str_appendf" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Function sqlite3MPrintf CDecl Alias "sqlite3MPrintf" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) As ZString Ptr
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)

#ifndef SQLITE_OMIT_TRACE

Private Type SqliteTraceLegacyCallback As Sub CDecl ( _
    ByVal pArgument As Any Ptr, _
    ByVal zSql As Const ZString Ptr _
)
Private Type SqliteTraceV2Callback As Function CDecl ( _
    ByVal traceEvent As SQLITE_C_UINT, _
    ByVal pArgument As Any Ptr, _
    ByVal pStatement As Any Ptr, _
    ByVal pTraceData As Any Ptr _
) As SQLITE_C_INT
Private Type SqliteProfileCallback As Sub CDecl ( _
    ByVal pArgument As Any Ptr, _
    ByVal zSql As Const ZString Ptr, _
    ByVal elapsedTime As sqlite3_uint64 _
)

/' ------------------------------------------------------------------------- '/
/' Host-parameter scanning '/
/' ------------------------------------------------------------------------- '/

Private Function findNextHostParameter( _
    ByVal zSql As Const UByte Ptr, _
    ByRef tokenLength As sqlite3_int64 _
) As sqlite3_int64
    tokenLength = 0
    If zSql = 0 Then Return -1

    Dim totalLength As sqlite3_int64 = 0
    While zSql[totalLength] <> 0
        Dim tokenType As SQLITE_C_INT = TK_ILLEGAL
        Dim currentLength As sqlite3_int64 = _
            sqlite3GetToken(zSql + totalLength, @tokenType)
        If currentLength <= 0 OrElse tokenType = TK_ILLEGAL Then Return -1
        If tokenType = TK_VARIABLE Then
            tokenLength = currentLength
            Return totalLength
        End If
        If totalLength > &H7FFFFFFF - currentLength Then Return -1
        totalLength += currentLength
    Wend
    Return totalLength
End Function

Private Sub sqlite3VdbeAppendSqlBytes( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zBytes As Const UByte Ptr, _
    ByVal byteCount As SQLITE_C_INT _
)
    If pAccum = 0 OrElse zBytes = 0 OrElse byteCount <= 0 Then Return
    sqlite3_str_append(pAccum, CPtr(Const ZString Ptr, zBytes), byteCount)
End Sub

/' ------------------------------------------------------------------------- '/
/' Bound-value rendering '/
/' ------------------------------------------------------------------------- '/

Private Sub sqlite3VdbeAppendExpandedText( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal pValue As SqliteVdbeMem Ptr _
)
    If pAccum = 0 OrElse pValue = 0 Then Return
    If pValue->n < 0 Then
        pAccum->accError = SQLITE_CORRUPT
        Return
    End If
    Dim zText As Const UByte Ptr = sqlite3_value_text(pValue)
    If zText = 0 AndAlso pValue->n > 0 Then
        pAccum->accError = SQLITE_NOMEM
        Return
    End If

    Dim outputLength As SQLITE_C_INT = pValue->n
#ifdef SQLITE_TRACE_SIZE_LIMIT
    If outputLength > SQLITE_TRACE_SIZE_LIMIT Then
        outputLength = SQLITE_TRACE_SIZE_LIMIT
        While outputLength < pValue->n AndAlso _
              (zText[outputLength] And &HC0) = &H80
            outputLength += 1
        Wend
    End If
#endif

    sqlite3_str_appendchar(pAccum, 1, Asc("'"))
    For iByte As SQLITE_C_INT = 0 To outputLength - 1
        If zText[iByte] = Asc("'") Then
            sqlite3_str_appendchar(pAccum, 2, Asc("'"))
        Else
            sqlite3VdbeAppendSqlBytes(pAccum, zText + iByte, 1)
        End If
    Next
    sqlite3_str_appendchar(pAccum, 1, Asc("'"))

#ifdef SQLITE_TRACE_SIZE_LIMIT
    If outputLength < pValue->n Then
        sqlite3_str_appendf(pAccum, StrPtr("/*+%d bytes*/"), _
                            pValue->n - outputLength)
    End If
#endif
End Sub

Private Sub sqlite3VdbeAppendExpandedValue( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal pValue As SqliteVdbeMem Ptr _
)
    If pAccum = 0 OrElse pValue = 0 Then Return
    If (pValue->flags And MEM_NULL) <> 0 Then
        sqlite3VdbeAppendSqlBytes(pAccum, CPtr(Const UByte Ptr, StrPtr("NULL")), 4)
    ElseIf (pValue->flags And (MEM_INT Or MEM_INTREAL)) <> 0 Then
        sqlite3_str_appendf(pAccum, StrPtr("%lld"), pValue->u.i)
    ElseIf (pValue->flags And MEM_REAL) <> 0 Then
        sqlite3_str_appendf(pAccum, StrPtr("%!.15g"), pValue->u.r)
    ElseIf (pValue->flags And MEM_STR) <> 0 Then
        sqlite3VdbeAppendExpandedText(pAccum, pValue)
    ElseIf (pValue->flags And MEM_ZERO) <> 0 Then
        If pValue->u.nZero < 0 Then
            pAccum->accError = SQLITE_CORRUPT
            Return
        End If
        sqlite3_str_appendf(pAccum, StrPtr("zeroblob(%d)"), pValue->u.nZero)
    ElseIf (pValue->flags And MEM_BLOB) <> 0 Then
        If pValue->n < 0 OrElse (pValue->n > 0 AndAlso pValue->z = 0) Then
            pAccum->accError = SQLITE_CORRUPT
            Return
        End If
        sqlite3_str_appendchar(pAccum, 1, Asc("x"))
        sqlite3_str_appendchar(pAccum, 1, Asc("'"))
        Dim outputLength As SQLITE_C_INT = pValue->n
#ifdef SQLITE_TRACE_SIZE_LIMIT
        If outputLength > SQLITE_TRACE_SIZE_LIMIT Then outputLength = SQLITE_TRACE_SIZE_LIMIT
#endif
        For iByte As SQLITE_C_INT = 0 To outputLength - 1
            sqlite3_str_appendf(pAccum, StrPtr("%02x"), CULng(pValue->z[iByte]))
        Next
        sqlite3_str_appendchar(pAccum, 1, Asc("'"))
#ifdef SQLITE_TRACE_SIZE_LIMIT
        If outputLength < pValue->n Then
            sqlite3_str_appendf(pAccum, StrPtr("/*+%d bytes*/"), _
                                pValue->n - outputLength)
        End If
#endif
    Else
        pAccum->accError = SQLITE_CORRUPT
    End If
End Sub

/' ------------------------------------------------------------------------- '/
/' SQL expansion '/
/' ------------------------------------------------------------------------- '/

Function sqlite3VdbeExpandSql CDecl Alias "sqlite3VdbeExpandSql" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal zRawSql As Const ZString Ptr _
) As ZString Ptr Export
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse zRawSql = 0 Then Return 0
    Dim db As sqlite3 Ptr = pVdbe->db
    Dim accum As sqlite3_str
    sqlite3StrAccumInit(@accum, 0, 0, 0, _
                        db->aLimit(SQLITE_LIMIT_LENGTH))

    Dim zSql As Const UByte Ptr = CPtr(Const UByte Ptr, zRawSql)
    If db->nVdbeExec > 1 Then
        While zSql[0] <> 0
            Dim lineLength As SQLITE_C_INT = 0
            While zSql[lineLength] <> 0 AndAlso zSql[lineLength] <> 10
                lineLength += 1
            Wend
            If zSql[lineLength] = 10 Then lineLength += 1
            sqlite3VdbeAppendSqlBytes(@accum, CPtr(Const UByte Ptr, StrPtr("-- ")), 3)
            sqlite3VdbeAppendSqlBytes(@accum, zSql, lineLength)
            zSql += lineLength
        Wend
    ElseIf pVdbe->nVar = 0 Then
        sqlite3_str_append(@accum, zRawSql, sqlite3Strlen30(zRawSql))
    Else
        Dim nextIndex As SQLITE_C_INT = 1
        While zSql[0] <> 0
            Dim parameterLength As sqlite3_int64 = 0
            Dim prefixLength As sqlite3_int64 = _
                findNextHostParameter(zSql, parameterLength)
            If prefixLength < 0 OrElse prefixLength > &H7FFFFFFF Then
                accum.accError = SQLITE_CORRUPT
                Exit While
            End If
            sqlite3VdbeAppendSqlBytes(@accum, zSql, CLng(prefixLength))
            zSql += prefixLength
            If parameterLength = 0 Then Exit While
            If parameterLength > &H7FFFFFFF Then
                accum.accError = SQLITE_CORRUPT
                Exit While
            End If

            Dim variableNumber As SQLITE_C_INT = 0
            If zSql[0] = Asc("?") Then
                If parameterLength > 1 Then
                    If sqlite3GetInt32(CPtr(Const ZString Ptr, zSql + 1), _
                                       @variableNumber) = 0 Then
                        accum.accError = SQLITE_CORRUPT
                        Exit While
                    End If
                Else
                    variableNumber = nextIndex
                End If
            Else
                variableNumber = sqlite3VdbeParameterIndex( _
                    pVdbe, CPtr(Const ZString Ptr, zSql), CLng(parameterLength))
            End If
            If variableNumber <= 0 OrElse variableNumber > pVdbe->nVar OrElse _
               pVdbe->aVar = 0 Then
                accum.accError = SQLITE_CORRUPT
                Exit While
            End If
            zSql += parameterLength
            If variableNumber >= nextIndex Then nextIndex = variableNumber + 1
            sqlite3VdbeAppendExpandedValue(@accum, @pVdbe->aVar[variableNumber - 1])
            If accum.accError <> 0 Then Exit While
        Wend
    End If

    If accum.accError <> 0 Then
        sqlite3_str_reset(@accum)
        Return 0
    End If
    Return sqlite3StrAccumFinish(@accum)
End Function

Sub vdbeExecTrace CDecl ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pOp As SqliteVdbeOp Ptr _
)
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse pOp = 0 Then Return

    Dim db As sqlite3 Ptr = pVdbe->db
    If (db->mTrace And _
        (SQLITE_TRACE_STMT Or SQLITE_TRACE_LEGACY)) = 0 Then Return
    If pVdbe->minWriteFileFormat = 254 Then Return

    Dim zTrace As Const ZString Ptr = pOp->p4.z
    If zTrace = 0 Then zTrace = pVdbe->zSql
    If zTrace = 0 Then Return

#ifndef SQLITE_OMIT_DEPRECATED
    If (db->mTrace And SQLITE_TRACE_LEGACY) <> 0 Then
        If db->trace.xLegacy = 0 Then Return
        Dim expandedSql As ZString Ptr = sqlite3VdbeExpandSql(pVdbe, zTrace)
        Dim legacyCallback As SqliteTraceLegacyCallback = _
            CPtr(SqliteTraceLegacyCallback, db->trace.xLegacy)
        legacyCallback(db->pTraceArg, expandedSql)
        sqlite3_free(expandedSql)
        Return
    End If
#endif

    If db->trace.xV2 = 0 Then Return
    Dim traceData As Any Ptr = CPtr(Any Ptr, zTrace)
    Dim nestedTrace As ZString Ptr = 0
    If db->nVdbeExec > 1 Then
        nestedTrace = sqlite3MPrintf(db, StrPtr("-- %s"), zTrace)
        traceData = nestedTrace
    End If

    Dim traceCallback As SqliteTraceV2Callback = _
        CPtr(SqliteTraceV2Callback, db->trace.xV2)
    traceCallback(SQLITE_TRACE_STMT, db->pTraceArg, pVdbe, traceData)
    If db->nVdbeExec > 1 Then sqlite3DbFree(db, nestedTrace)
End Sub

Sub vdbeExecProfileCallback CDecl ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
    If pVdbe = 0 OrElse pVdbe->db = 0 OrElse pVdbe->startTime <= 0 Then Return
    If pVdbe->zSql = 0 Then
        pVdbe->startTime = 0
        Return
    End If

    Dim db As sqlite3 Ptr = pVdbe->db
    Dim currentTime As sqlite3_int64 = 0
    If db->pVfs = 0 OrElse _
       sqlite3OsCurrentTimeInt64(CPtr(sqlite3_vfs Ptr, db->pVfs), @currentTime) <> SQLITE_OK Then
        pVdbe->startTime = 0
        Return
    End If

    Dim elapsedTime As sqlite3_int64 = _
        (currentTime - pVdbe->startTime) * 1000000
#ifndef SQLITE_OMIT_DEPRECATED
    If db->xProfile <> 0 Then
        Dim profileCallback As SqliteProfileCallback = _
            CPtr(SqliteProfileCallback, db->xProfile)
        profileCallback(db->pProfileArg, pVdbe->zSql, CULngInt(elapsedTime))
    End If
#endif
    If (db->mTrace And SQLITE_TRACE_PROFILE) <> 0 AndAlso db->trace.xV2 <> 0 Then
        Dim traceCallback As SqliteTraceV2Callback = _
            CPtr(SqliteTraceV2Callback, db->trace.xV2)
        traceCallback(SQLITE_TRACE_PROFILE, db->pTraceArg, pVdbe, @elapsedTime)
    End If
    pVdbe->startTime = 0
End Sub

#endif

/' end of sqlite3_vdbe_trace.bas '/
