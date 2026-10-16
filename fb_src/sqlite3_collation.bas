/'
    Project: SQLite FreeBASIC port

    File: sqlite3_collation.bas

    Purpose:

        Register and resolve the collation sequences used by SQL comparison.

    Responsibilities:

        - Keep one collation sequence per name and text encoding.
        - Register BINARY, NOCASE, and RTRIM for each connection.
        - Support user collation registration and collation-needed callbacks.
        - Resolve missing encodings through callbacks or an available encoding.

    This file intentionally does NOT contain:

        - Unicode-aware NOCASE rules beyond SQLite's ASCII case folding.
        - Collation registration through global sqlite3_config() callbacks.
'/

#lang "fb"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_vdbe_compare.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_vdbe_mem_text.bi"
#include once "sqlite3_collation.bi"

Private Type SqliteCollationNeededCallback As Sub CDecl ( _
    ByVal pArgument As Any Ptr, _
    ByVal db As sqlite3 Ptr, _
    ByVal eTextRep As SQLITE_C_INT, _
    ByVal zName As Const ZString Ptr _
)

Private Type SqliteCollationNeeded16Callback As Sub CDecl ( _
    ByVal pArgument As Any Ptr, _
    ByVal db As sqlite3 Ptr, _
    ByVal eTextRep As SQLITE_C_INT, _
    ByVal zName As Any Ptr _
)

Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal z As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_stricmp CDecl Alias "sqlite3_stricmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_strnicmp CDecl Alias "sqlite3_strnicmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3Utf16to8 CDecl Alias "sqlite3Utf16to8" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal z As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal enc As u8 _
) As ZString Ptr
Declare Function sqlite3SafetyCheckOk CDecl Alias "sqlite3SafetyCheckOk" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
Function rtrimCollFunc CDecl Alias "rtrimCollFunc" ( _
    ByVal pUser As Any Ptr, _
    ByVal nLeft As SQLITE_C_INT, _
    ByVal pLeft As Const Any Ptr, _
    ByVal nRight As SQLITE_C_INT, _
    ByVal pRight As Const Any Ptr _
) As SQLITE_C_INT
    If nLeft < 0 OrElse nRight < 0 Then Return 0
    Dim pLeftBytes As Const UByte Ptr = CPtr(Const UByte Ptr, pLeft)
    Dim pRightBytes As Const UByte Ptr = CPtr(Const UByte Ptr, pRight)
    While nLeft > 0 AndAlso pLeftBytes[nLeft - 1] = Asc(" ")
        nLeft -= 1
    Wend
    While nRight > 0 AndAlso pRightBytes[nRight - 1] = Asc(" ")
        nRight -= 1
    Wend
    Return sqlite3BinaryCompare(pUser, nLeft, pLeft, nRight, pRight)
End Function

Function nocaseCollatingFunc CDecl Alias "nocaseCollatingFunc" ( _
    ByVal pUser As Any Ptr, _
    ByVal nLeft As SQLITE_C_INT, _
    ByVal pLeft As Const Any Ptr, _
    ByVal nRight As SQLITE_C_INT, _
    ByVal pRight As Const Any Ptr _
) As SQLITE_C_INT
    If nLeft < 0 OrElse nRight < 0 Then Return 0
    Dim compareBytes As SQLITE_C_INT = IIf(nLeft < nRight, nLeft, nRight)
    Dim rc As SQLITE_C_INT = 0
    If compareBytes > 0 Then
        rc = sqlite3_strnicmp(CPtr(Const ZString Ptr, pLeft), _
                              CPtr(Const ZString Ptr, pRight), compareBytes)
    End If
    If rc <> 0 Then Return rc
    If nLeft < nRight Then Return -1
    If nLeft > nRight Then Return 1
    Return 0
End Function

Private Function findCollSeqEntry( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal create As SQLITE_C_INT _
) As sqlite3CollSeq Ptr
    If db = 0 OrElse zName = 0 Then Return 0

    Dim pColl As sqlite3CollSeq Ptr = CPtr(sqlite3CollSeq Ptr, _
        sqlite3HashFind(@db->aCollSeq, zName))
    If pColl <> 0 OrElse create = 0 Then Return pColl

    Dim nName As SQLITE_C_INT = sqlite3Strlen30(zName)
    If nName < 0 OrElse nName >= SQLITE_MAX_ALLOCATION_SIZE Then Return 0
    Dim nByte As sqlite3_uint64 = _
        CULngInt(SizeOf(sqlite3CollSeq)) * 3 + CULngInt(nName) + 1
    pColl = CPtr(sqlite3CollSeq Ptr, sqlite3DbMallocZero(db, nByte))
    If pColl = 0 Then Return 0

    Dim zStoredName As ZString Ptr = CPtr(ZString Ptr, _
        CPtr(UByte Ptr, pColl) + CULngInt(SizeOf(sqlite3CollSeq)) * 3)
    For byteIndex As SQLITE_C_INT = 0 To nName
        zStoredName[byteIndex] = zName[byteIndex]
    Next
    For encodingIndex As SQLITE_C_INT = 0 To 2
        pColl[encodingIndex].zName = zStoredName
    Next
    pColl[0].enc = SQLITE_UTF8
    pColl[1].enc = SQLITE_UTF16LE
    pColl[2].enc = SQLITE_UTF16BE

    Dim pOld As Any Ptr = sqlite3HashInsert(@db->aCollSeq, zStoredName, pColl)
    If pOld <> 0 Then
        sqlite3OomFault(db)
        sqlite3DbFree(db, pColl)
        Return 0
    End If
    Return pColl
End Function

Function sqlite3FindCollSeq CDecl Alias "sqlite3FindCollSeq" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal eTextRep As u8, _
    ByVal zName As Const ZString Ptr, _
    ByVal create As SQLITE_C_INT _
) As sqlite3CollSeq Ptr Export
    If db = 0 OrElse eTextRep < SQLITE_UTF8 OrElse _
       eTextRep > SQLITE_UTF16BE Then Return 0
    If zName = 0 Then Return db->pDfltColl

    Dim pColl As sqlite3CollSeq Ptr = findCollSeqEntry(db, zName, create)
    If pColl <> 0 Then pColl += eTextRep - 1
    Return pColl
End Function

Sub sqlite3SetTextEncoding CDecl Alias "sqlite3SetTextEncoding" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal eTextRep As u8 _
) Export
    If db = 0 OrElse (eTextRep <> SQLITE_UTF8 AndAlso _
       eTextRep <> SQLITE_UTF16LE AndAlso eTextRep <> SQLITE_UTF16BE) Then Return
    db->enc = eTextRep
    db->pDfltColl = sqlite3FindCollSeq(db, eTextRep, StrPtr("BINARY"), 0)
    sqlite3ExpirePreparedStatements(db, 1)
End Sub

Private Function synthCollSeq( _
    ByVal db As sqlite3 Ptr, _
    ByVal pColl As sqlite3CollSeq Ptr _
) As SQLITE_C_INT
    If db = 0 OrElse pColl = 0 OrElse pColl->zName = 0 Then _
        Return SQLITE_ERROR

    Dim encodings(0 To 2) As u8 = _
        {SQLITE_UTF16BE, SQLITE_UTF16LE, SQLITE_UTF8}
    For index As SQLITE_C_INT = 0 To 2
        Dim pOther As sqlite3CollSeq Ptr = sqlite3FindCollSeq( _
            db, encodings(index), pColl->zName, 0)
        If pOther <> 0 AndAlso pOther->xCmp <> 0 Then
            pColl[0] = pOther[0]
            pColl->xDel = 0
            Return SQLITE_OK
        End If
    Next
    Return SQLITE_ERROR
End Function

Private Sub callCollNeeded( _
    ByVal db As sqlite3 Ptr, _
    ByVal eTextRep As u8, _
    ByVal zName As Const ZString Ptr _
)
    If db = 0 OrElse zName = 0 Then Return
    If db->xCollNeeded <> 0 Then
        Dim zExternal As ZString Ptr = _
            CPtr(ZString Ptr, sqlite3DbStrDup(db, zName))
        If zExternal = 0 Then Return
        Dim callback As SqliteCollationNeededCallback = _
            CPtr(SqliteCollationNeededCallback, db->xCollNeeded)
        callback(db->pCollNeededArg, db, eTextRep, zExternal)
        sqlite3DbFree(db, zExternal)
    ElseIf db->xCollNeeded16 <> 0 Then
        Dim pValue As Any Ptr = sqlite3ValueNew(db)
        If pValue = 0 Then Return
        Dim staticDestructor As sqlite3MemDestructor = _
            CPtr(sqlite3MemDestructor, 0)
        sqlite3ValueSetStr(pValue, -1, zName, SQLITE_UTF8, staticDestructor)
        Dim zExternal16 As Any Ptr = _
            sqlite3ValueText(pValue, SQLITE_UTF16NATIVE)
        If zExternal16 <> 0 Then
            Dim callback16 As SqliteCollationNeeded16Callback = _
                CPtr(SqliteCollationNeeded16Callback, db->xCollNeeded16)
            callback16(db->pCollNeededArg, db, db->enc, zExternal16)
        End If
        sqlite3ValueFree(pValue)
    End If
End Sub

Function sqlite3GetCollSeq CDecl Alias "sqlite3GetCollSeq" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal eTextRep As u8, _
    ByVal pCollation As sqlite3CollSeq Ptr, _
    ByVal zName As Const ZString Ptr _
) As sqlite3CollSeq Ptr Export
    If pParse = 0 OrElse pParse->db = 0 Then Return 0
    Dim db As sqlite3 Ptr = pParse->db
    Dim pColl As sqlite3CollSeq Ptr = pCollation
    If pColl = 0 Then pColl = sqlite3FindCollSeq(db, eTextRep, zName, 0)
    If pColl = 0 OrElse pColl->xCmp = 0 Then
        callCollNeeded(db, eTextRep, zName)
        pColl = sqlite3FindCollSeq(db, eTextRep, zName, 0)
    End If
    If pColl <> 0 AndAlso pColl->xCmp = 0 Then
        If synthCollSeq(db, pColl) <> SQLITE_OK Then pColl = 0
    End If
    If pColl = 0 Then
        sqlite3ErrorMsg(pParse, StrPtr("no such collation sequence: %s"), zName)
        pParse->rc = SQLITE_ERROR_MISSING_COLLSEQ
    End If
    Return pColl
End Function

Function sqlite3LocateCollSeq CDecl Alias "sqlite3LocateCollSeq" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal zName As Const ZString Ptr _
) As sqlite3CollSeq Ptr Export
    If pParse = 0 OrElse pParse->db = 0 OrElse zName = 0 Then Return 0
    Dim db As sqlite3 Ptr = pParse->db
    Dim pColl As sqlite3CollSeq Ptr = _
        sqlite3FindCollSeq(db, db->enc, zName, db->init.busy)
    If db->init.busy = 0 AndAlso _
       (pColl = 0 OrElse pColl->xCmp = 0) Then
        pColl = sqlite3GetCollSeq(pParse, db->enc, pColl, zName)
    End If
    Return pColl
End Function

Function sqlite3CheckCollSeq CDecl Alias "sqlite3CheckCollSeq" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pCollation As sqlite3CollSeq Ptr _
) As SQLITE_C_INT Export
    If pCollation = 0 OrElse pCollation->xCmp <> 0 Then Return SQLITE_OK
    If pParse = 0 OrElse pParse->db = 0 Then Return SQLITE_MISUSE
    Dim pResolved As sqlite3CollSeq Ptr = sqlite3GetCollSeq( _
        pParse, pParse->db->enc, pCollation, pCollation->zName)
    If pResolved = 0 Then Return SQLITE_ERROR
    Return SQLITE_OK
End Function

Function createCollation CDecl Alias "createCollation" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal eTextRep As u8, _
    ByVal pContext As Any Ptr, _
    ByVal xCompare As sqlite3CollationCompare, _
    ByVal xDestroy As Sub CDecl (ByVal p As Any Ptr) _
) As SQLITE_C_INT
    If db = 0 OrElse zName = 0 Then Return SQLITE_MISUSE

    Dim normalizedEncoding As SQLITE_C_INT = eTextRep
    If normalizedEncoding = SQLITE_UTF16 OrElse _
       normalizedEncoding = SQLITE_UTF16_ALIGNED Then _
        normalizedEncoding = SQLITE_UTF16NATIVE
    If normalizedEncoding < SQLITE_UTF8 OrElse _
       normalizedEncoding > SQLITE_UTF16BE Then Return SQLITE_MISUSE

    Dim pColl As sqlite3CollSeq Ptr = sqlite3FindCollSeq( _
        db, normalizedEncoding, zName, 0)
    If pColl <> 0 AndAlso pColl->xCmp <> 0 Then
        If db->nVdbeActive <> 0 Then
            sqlite3ErrorWithMsg(db, SQLITE_BUSY, _
                StrPtr("unable to delete/modify collation sequence due to active statements"))
            Return SQLITE_BUSY
        End If
        sqlite3ExpirePreparedStatements(db, 0)
        If (pColl->enc And Not SQLITE_UTF16_ALIGNED) = normalizedEncoding Then
            Dim pArray As sqlite3CollSeq Ptr = CPtr(sqlite3CollSeq Ptr, _
                sqlite3HashFind(@db->aCollSeq, zName))
            If pArray <> 0 Then
                For index As SQLITE_C_INT = 0 To 2
                    If pArray[index].enc = pColl->enc Then
                        If pArray[index].xDel <> 0 Then _
                            pArray[index].xDel(pArray[index].pUser)
                        pArray[index].xCmp = 0
                    End If
                Next
            End If
        End If
    End If

    pColl = sqlite3FindCollSeq(db, normalizedEncoding, zName, 1)
    If pColl = 0 Then Return SQLITE_NOMEM
    pColl->xCmp = xCompare
    pColl->pUser = pContext
    pColl->xDel = xDestroy
    pColl->enc = normalizedEncoding Or (eTextRep And SQLITE_UTF16_ALIGNED)
    sqlite3Error(db, SQLITE_OK)
    Return SQLITE_OK
End Function

Function sqlite3_create_collation_v2 CDecl Alias "sqlite3_create_collation_v2" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal eTextRep As SQLITE_C_INT, _
    ByVal pContext As Any Ptr, _
    ByVal xCompare As sqlite3CollationCompare, _
    ByVal xDestroy As Sub CDecl (ByVal p As Any Ptr) _
) As SQLITE_C_INT Export
    If sqlite3SafetyCheckOk(db) = 0 OrElse zName = 0 Then Return SQLITE_MISUSE
    sqlite3_mutex_enter(db->mutex)
    Dim rc As SQLITE_C_INT = createCollation(db, zName, CByte(eTextRep), _
        pContext, xCompare, xDestroy)
    rc = sqlite3ApiExit(db, rc)
    sqlite3_mutex_leave(db->mutex)
    Return rc
End Function

Function sqlite3_create_collation CDecl Alias "sqlite3_create_collation" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal eTextRep As SQLITE_C_INT, _
    ByVal pContext As Any Ptr, _
    ByVal xCompare As sqlite3CollationCompare _
) As SQLITE_C_INT Export
    Return sqlite3_create_collation_v2(db, zName, eTextRep, pContext, _
                                       xCompare, 0)
End Function

#ifndef SQLITE_OMIT_UTF16
Function sqlite3_create_collation16 CDecl Alias "sqlite3_create_collation16" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Any Ptr, _
    ByVal eTextRep As SQLITE_C_INT, _
    ByVal pContext As Any Ptr, _
    ByVal xCompare As sqlite3CollationCompare _
) As SQLITE_C_INT Export
    If sqlite3SafetyCheckOk(db) = 0 OrElse zName = 0 Then Return SQLITE_MISUSE
    sqlite3_mutex_enter(db->mutex)
    Dim zName8 As ZString Ptr = sqlite3Utf16to8( _
        db, zName, -1, SQLITE_UTF16NATIVE)
    Dim rc As SQLITE_C_INT = SQLITE_NOMEM
    If zName8 <> 0 Then
        rc = createCollation(db, zName8, CByte(eTextRep), pContext, xCompare, 0)
        sqlite3DbFree(db, zName8)
    End If
    rc = sqlite3ApiExit(db, rc)
    sqlite3_mutex_leave(db->mutex)
    Return rc
End Function
#endif

Function sqlite3_collation_needed CDecl Alias "sqlite3_collation_needed" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pContext As Any Ptr, _
    ByVal xCallback As Any Ptr _
) As SQLITE_C_INT Export
    If sqlite3SafetyCheckOk(db) = 0 Then Return SQLITE_MISUSE
    sqlite3_mutex_enter(db->mutex)
    db->xCollNeeded = xCallback
    db->xCollNeeded16 = 0
    db->pCollNeededArg = pContext
    sqlite3_mutex_leave(db->mutex)
    Return SQLITE_OK
End Function

#ifndef SQLITE_OMIT_UTF16
Function sqlite3_collation_needed16 CDecl Alias "sqlite3_collation_needed16" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pContext As Any Ptr, _
    ByVal xCallback As Any Ptr _
) As SQLITE_C_INT Export
    If sqlite3SafetyCheckOk(db) = 0 Then Return SQLITE_MISUSE
    sqlite3_mutex_enter(db->mutex)
    db->xCollNeeded = 0
    db->xCollNeeded16 = xCallback
    db->pCollNeededArg = pContext
    sqlite3_mutex_leave(db->mutex)
    Return SQLITE_OK
End Function
#endif

Function sqlite3CollationInitialize CDecl Alias "sqlite3CollationInitialize" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT Export
    If db = 0 Then Return SQLITE_MISUSE
    sqlite3_mutex_enter(db->mutex)
    Dim rc As SQLITE_C_INT = createCollation(db, StrPtr("BINARY"), _
        SQLITE_UTF8, 0, @sqlite3BinaryCompare, 0)
    If rc = SQLITE_OK Then rc = createCollation(db, StrPtr("BINARY"), _
        SQLITE_UTF16LE, 0, @sqlite3BinaryCompare, 0)
    If rc = SQLITE_OK Then rc = createCollation(db, StrPtr("BINARY"), _
        SQLITE_UTF16BE, 0, @sqlite3BinaryCompare, 0)
    If rc = SQLITE_OK Then rc = createCollation(db, StrPtr("NOCASE"), _
        SQLITE_UTF8, 0, @nocaseCollatingFunc, 0)
    If rc = SQLITE_OK Then rc = createCollation(db, StrPtr("RTRIM"), _
        SQLITE_UTF8, 0, @rtrimCollFunc, 0)
    If rc = SQLITE_OK Then sqlite3SetTextEncoding(db, SQLITE_UTF8)
    sqlite3_mutex_leave(db->mutex)
    Return rc
End Function

Sub sqlite3CollationClear CDecl Alias "sqlite3CollationClear" ( _
    ByVal db As sqlite3 Ptr _
) Export
    If db = 0 Then Return
    Dim pElement As HashElem Ptr = db->aCollSeq.first
    While pElement <> 0
        Dim pNext As HashElem Ptr = pElement->next
        Dim pColl As sqlite3CollSeq Ptr = _
            CPtr(sqlite3CollSeq Ptr, pElement->data)
        If pColl <> 0 Then
            For index As SQLITE_C_INT = 0 To 2
                If pColl[index].xDel <> 0 Then
                    pColl[index].xDel(pColl[index].pUser)
                    pColl[index].xDel = 0
                End If
            Next
            sqlite3DbFree(db, pColl)
        End If
        pElement = pNext
    Wend
    sqlite3HashClear(@db->aCollSeq)
    db->pDfltColl = 0
End Sub

/' end of sqlite3_collation.bas '/
