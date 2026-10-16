/'
    Project: SQLite FreeBASIC port

    File: sqlite3_prepare.bas

    Purpose:

        Compile the first SQL statement while holding schema and B-tree locks.

    Responsibilities:

        - Validate prepare arguments and enforce SQL length limits.
        - Hold connection and B-tree locks while checking schemas and parsing.
        - Retry transient parser and schema errors using SQLite's prepare rules.
        - Reprepare expired VDBE programs and transfer their bindings.
        - Finalize failed VDBE programs and release parser-owned state.
        - Return the tail pointer after the first compiled statement.
        - Convert UTF-16 input and map the tail pointer back to UTF-16 bytes.
        - Retain SQL text for the v2 and v3 prepare APIs.
        - Feed schema rows through sqlite3InitCallback and report malformed schemas.

    This file intentionally does NOT contain:

        - Statement execution or VDBE opcode dispatch.
        - Semantic actions outside the implemented parser subset.
'/ 

#lang "fb"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_mutex.bi"
#include once "sqlite3_api_constants.bi"
#include once "sqlite3_btree.bi"
#include once "sqlite3_global_data.bi"
#include once "sqlite3_std_types.bi"

Declare Function sqlite3MPrintf CDecl Alias "sqlite3MPrintf" ( _
    ByVal db As Any Ptr, _
    ByVal format As Const ZString Ptr, _
    ... _
) As ZString Ptr
Declare Function sqlite3CorruptError CDecl Alias "sqlite3CorruptError" ( _
    ByVal reason As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3GetUInt32 CDecl Alias "sqlite3GetUInt32" ( _
    ByVal data As Const ZString Ptr, _
    ByVal value As SQLITE_C_UINT Ptr _
) As SQLITE_C_INT
Declare Function sqlite3ConfigExtraSchemaChecksEnabled CDecl Alias "sqlite3ConfigExtraSchemaChecksEnabled" () As SQLITE_C_INT
Declare Function sqlite3_errmsg CDecl Alias "sqlite3_errmsg" ( _
    ByVal db As Any Ptr _
) As Const ZString Ptr
Declare Function sqlite3_finalize CDecl Alias "sqlite3_finalize" ( _
    ByVal statement As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3FindIndex CDecl Alias "sqlite3FindIndex" ( _
    ByVal db As Any Ptr, _
    ByVal indexName As Const ZString Ptr, _
    ByVal databaseName As Const ZString Ptr _
) As Any Ptr
Declare Function sqlite3IndexHasDuplicateRootPage CDecl Alias "sqlite3IndexHasDuplicateRootPage" ( _
    ByVal index As Any Ptr _
) As SQLITE_C_INT

#ifndef SQLITE_MAX_PREPARE_RETRY
#define SQLITE_MAX_PREPARE_RETRY 25
#endif

Declare Function sqlite3SafetyCheckOk CDecl Alias "sqlite3SafetyCheckOk" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_stmt_isexplain CDecl Alias "sqlite3_stmt_isexplain" ( _
    ByVal pStatement As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3BtreeSchemaLocked CDecl Alias "sqlite3BtreeSchemaLocked" ( _
    ByVal pBtree As Btree Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3ResetOneSchema CDecl Alias "sqlite3ResetOneSchema" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal databaseIndex As SQLITE_C_INT _
)
Declare Sub sqlite3VtabUnlockList CDecl Alias "sqlite3VtabUnlockList" ( _
    ByVal db As sqlite3 Ptr _
)
Declare Function sqlite3_sql CDecl Alias "sqlite3_sql" ( _
    ByVal pStatement As Any Ptr _
) As Const ZString Ptr
Declare Sub sqlite3VdbeSwap CDecl Alias "sqlite3VdbeSwap" ( _
    ByVal pLeft As SqliteVdbe Ptr, _
    ByVal pRight As SqliteVdbe Ptr _
)
Declare Function sqlite3TransferBindings CDecl Alias "sqlite3TransferBindings" ( _
    ByVal pFromStatement As Any Ptr, _
    ByVal pToStatement As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3ParseObjectInit CDecl Alias "sqlite3ParseObjectInit" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal db As sqlite3 Ptr _
)
Declare Sub sqlite3ParseObjectReset CDecl Alias "sqlite3ParseObjectReset" ( _
    ByVal pParse As SqliteParseContext Ptr _
)
Declare Function sqlite3Utf16to8 CDecl Alias "sqlite3Utf16to8" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zInput As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal encoding As u8 _
) As ZString Ptr
Declare Function sqlite3Utf8CharLen CDecl Alias "sqlite3Utf8CharLen" ( _
    ByVal zInput As Const UByte Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3Utf16ByteLen CDecl Alias "sqlite3Utf16ByteLen" ( _
    ByVal zInput As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal nCharacter As SQLITE_C_INT _
) As SQLITE_C_INT

Private Sub schemaIsValid CDecl Alias "schemaIsValid" ( _
    ByVal pParse As SqliteParseContext Ptr _
)
    If pParse = 0 OrElse pParse->db = 0 Then Exit Sub
    Dim db As sqlite3 Ptr = pParse->db

    For databaseIndex As SQLITE_C_INT = 0 To db->nDb - 1
        Dim pBtree As Btree Ptr = CPtr(Btree Ptr, db->aDb(databaseIndex).pBt)
        If pBtree = 0 Then Continue For

        Dim openedTransaction As SQLITE_C_INT = 0
        If sqlite3BtreeTxnState(pBtree) = SQLITE_TXN_NONE Then
            Dim resultCode As SQLITE_C_INT = _
                sqlite3BtreeBeginTrans(pBtree, 0, 0)
            If resultCode = SQLITE_NOMEM OrElse resultCode = SQLITE_IOERR_NOMEM Then
                sqlite3OomFault(db)
                pParse->rc = SQLITE_NOMEM
            End If
            If resultCode <> SQLITE_OK Then Exit Sub
            openedTransaction = 1
        End If

        Dim schemaCookie As u32 = 0
        sqlite3BtreeGetMeta(pBtree, BTREE_SCHEMA_VERSION, @schemaCookie)
        Dim pSchema As SqliteSchema Ptr = db->aDb(databaseIndex).pSchema
        If pSchema <> 0 AndAlso schemaCookie <> pSchema->schema_cookie Then
            If (pSchema->schemaFlags And DB_SchemaLoaded) <> 0 Then _
                pParse->rc = SQLITE_SCHEMA
            sqlite3ResetOneSchema(db, databaseIndex)
        End If

        If openedTransaction <> 0 Then sqlite3BtreeCommit(pBtree)
    Next
End Sub

Private Function sqlite3Prepare CDecl Alias "sqlite3Prepare" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zSql As Const ZString Ptr, _
    ByVal nBytes As SQLITE_C_INT, _
    ByVal prepFlags As SQLITE_C_UINT, _
    ByVal pReprepare As SqliteVdbe Ptr, _
    ByVal ppStatement As Any Ptr Ptr, _
    ByVal pzTail As Const ZString Ptr Ptr _
) As SQLITE_C_INT
    If db = 0 OrElse zSql = 0 OrElse ppStatement = 0 Then Return SQLITE_MISUSE

    Dim parseContext As SqliteParseContext
    Dim pParse As SqliteParseContext Ptr = @parseContext
    sqlite3ParseObjectInit(pParse, db)
    If pReprepare <> 0 Then
        pParse->pReprepare = pReprepare
        pParse->explain = CByte(sqlite3_stmt_isexplain(pReprepare))
    End If
    If ppStatement[0] <> 0 Then
        sqlite3ParseObjectReset(pParse)
        Return SQLITE_MISUSE
    End If

    Dim resultCode As SQLITE_C_INT = SQLITE_OK
    Dim tailOffset As LongInt = 0
    If db->mallocFailed <> 0 Then
        sqlite3ErrorMsg(pParse, StrPtr(!"out of memory"))
        db->errorCode = SQLITE_NOMEM
        resultCode = SQLITE_NOMEM
        GoTo end_prepare
    End If

    If (prepFlags And SQLITE_PREPARE_PERSISTENT) <> 0 Then
        pParse->disableLookaside += 1
        db->lookaside.bDisable += 1
        db->lookaside.sz = 0
    End If
    pParse->prepFlags = Cast(u8, prepFlags And &HFF)

    If db->noSharedCache = 0 Then
        For databaseIndex As SQLITE_C_INT = 0 To db->nDb - 1
            Dim pBtree As Btree Ptr = CPtr(Btree Ptr, db->aDb(databaseIndex).pBt)
            If pBtree = 0 Then Continue For
            resultCode = sqlite3BtreeSchemaLocked(pBtree)
            If resultCode <> SQLITE_OK Then
                sqlite3ErrorWithMsg(db, resultCode, _
                    StrPtr(!"database schema is locked: %s"), _
                    db->aDb(databaseIndex).zDbSName)
                GoTo end_prepare
            End If
        Next
    End If

#ifndef SQLITE_OMIT_VIRTUALTABLE
    If db->pDisconnect <> 0 Then sqlite3VtabUnlockList(db)
#endif

    If nBytes >= 0 AndAlso (nBytes = 0 OrElse _
       CPtr(Const UByte Ptr, zSql)[nBytes - 1] <> 0) Then
        Dim maximumSqlLength As SQLITE_C_INT = db->aLimit(SQLITE_LIMIT_SQL_LENGTH)
        If nBytes > maximumSqlLength Then
            sqlite3ErrorWithMsg(db, SQLITE_TOOBIG, StrPtr(!"statement too long"))
            resultCode = sqlite3ApiExit(db, SQLITE_TOOBIG)
            GoTo end_prepare
        End If

        Dim zSqlCopy As ZString Ptr = _
            sqlite3DbStrNDup(db, zSql, CULngInt(nBytes))
        If zSqlCopy <> 0 Then
            sqlite3RunParser(pParse, zSqlCopy)
            tailOffset = _
                CPtr(Const UByte Ptr, pParse->zTail) - _
                CPtr(Const UByte Ptr, zSqlCopy)
            If tailOffset < 0 OrElse tailOffset > nBytes Then
                pParse->zTail = CPtr(ZString Ptr, _
                    CPtr(Const UByte Ptr, zSql) + nBytes)
                pParse->rc = SQLITE_CORRUPT
            Else
                pParse->zTail = CPtr(ZString Ptr, _
                    CPtr(Const UByte Ptr, zSql) + tailOffset)
            End If
            sqlite3DbFree(db, zSqlCopy)
        Else
            pParse->zTail = CPtr(ZString Ptr, _
                CPtr(Const UByte Ptr, zSql) + nBytes)
        End If
    Else
        sqlite3RunParser(pParse, zSql)
    End If

    If pParse->zTail = 0 Then
        pParse->zTail = CPtr(ZString Ptr, zSql)
        pParse->rc = SQLITE_CORRUPT
    End If
    tailOffset = _
        CPtr(Const UByte Ptr, pParse->zTail) - CPtr(Const UByte Ptr, zSql)
    If tailOffset < 0 OrElse (nBytes >= 0 AndAlso tailOffset > nBytes) Then
        tailOffset = 0
        pParse->zTail = CPtr(ZString Ptr, zSql)
        pParse->rc = SQLITE_CORRUPT
    End If
    If pzTail <> 0 Then pzTail[0] = pParse->zTail
    If db->init.busy = 0 Then
        sqlite3VdbeSetSql(CPtr(SqliteVdbe Ptr, pParse->pVdbe), zSql, _
                          CInt(tailOffset), Cast(u8, prepFlags))
    End If

    If db->mallocFailed <> 0 Then
        pParse->rc = SQLITE_NOMEM
        pParse->checkSchema = 0
    End If
    If pParse->rc <> SQLITE_OK AndAlso pParse->rc <> SQLITE_DONE Then
        If pParse->checkSchema <> 0 AndAlso db->init.busy = 0 Then _
            schemaIsValid(pParse)
        If pParse->pVdbe <> 0 Then
            sqlite3VdbeFinalize(pParse->pVdbe)
            pParse->pVdbe = 0
        End If
        resultCode = pParse->rc
        If pParse->zErrMsg <> 0 Then
            sqlite3ErrorWithMsg(db, resultCode, StrPtr(!"%s"), pParse->zErrMsg)
            sqlite3DbFree(db, pParse->zErrMsg)
            pParse->zErrMsg = 0
        Else
            sqlite3Error(db, resultCode)
        End If
    Else
        ppStatement[0] = pParse->pVdbe
        resultCode = SQLITE_OK
        sqlite3ErrorClear(db)
    End If

    While pParse->pTriggerPrg <> 0
        Dim pTriggerProgram As SqliteTriggerPrg Ptr = pParse->pTriggerPrg
        pParse->pTriggerPrg = pTriggerProgram->pNext
        sqlite3DbFree(db, pTriggerProgram)
    Wend

end_prepare:
    sqlite3ParseObjectReset(pParse)
    Return resultCode
End Function

Private Function sqlite3LockAndPrepare CDecl Alias "sqlite3LockAndPrepare" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zSql As Const ZString Ptr, _
    ByVal nBytes As SQLITE_C_INT, _
    ByVal prepFlags As SQLITE_C_UINT, _
    ByVal pOld As SqliteVdbe Ptr, _
    ByVal ppStatement As Any Ptr Ptr, _
    ByVal pzTail As Const ZString Ptr Ptr _
) As SQLITE_C_INT
    If db = 0 OrElse ppStatement = 0 Then Return SQLITE_MISUSE
    ppStatement[0] = 0
    If sqlite3SafetyCheckOk(db) = 0 OrElse zSql = 0 Then Return SQLITE_MISUSE

    sqlite3_mutex_enter(db->mutex)
    sqlite3BtreeEnterAll(db)
    Dim resultCode As SQLITE_C_INT
    Dim attemptCount As SQLITE_C_INT = 0
    Do
        resultCode = sqlite3Prepare(db, zSql, nBytes, prepFlags, _
                                    pOld, ppStatement, pzTail)
        If resultCode = SQLITE_OK OrElse db->mallocFailed <> 0 Then Exit Do
        attemptCount += 1
        If resultCode = SQLITE_ERROR_RETRY AndAlso _
           attemptCount <= SQLITE_MAX_PREPARE_RETRY Then Continue Do
        If resultCode = SQLITE_SCHEMA Then
            sqlite3ResetOneSchema(db, -1)
            If attemptCount = 1 Then Continue Do
        End If
        Exit Do
    Loop

    sqlite3BtreeLeaveAll(db)
    resultCode = sqlite3ApiExit(db, resultCode)
    db->busyHandler.nBusy = 0
    sqlite3_mutex_leave(db->mutex)
    Return resultCode
End Function

#ifndef SQLITE_OMIT_UTF16
Private Function sqlite3Prepare16 CDecl Alias "sqlite3Prepare16" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zInput As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal prepFlags As SQLITE_C_UINT, _
    ByVal saveSql As SQLITE_C_INT, _
    ByVal ppStatement As Any Ptr Ptr, _
    ByVal pzTail As Any Ptr Ptr _
) As SQLITE_C_INT
    If ppStatement <> 0 Then ppStatement[0] = 0
    If db = 0 Then Return SQLITE_MISUSE
    If zInput = 0 OrElse ppStatement = 0 OrElse sqlite3SafetyCheckOk(db) = 0 Then
        db->errorCode = SQLITE_MISUSE
        Return SQLITE_MISUSE
    End If

    Dim requestedBytes As LongInt = nByte
    If requestedBytes >= 0 Then requestedBytes = requestedBytes And Not 1
    Dim maximumBytes As ULongInt = CULngInt(db->lengthLimit) And Not 1ULL
    If maximumBytes > SQLITE_MAX_ALLOCATION_SIZE - 2 Then _
        maximumBytes = (SQLITE_MAX_ALLOCATION_SIZE - 2) And Not 1ULL

    Dim scanLimit As ULongInt = maximumBytes
    If requestedBytes >= 0 AndAlso CULngInt(requestedBytes) < scanLimit Then _
        scanLimit = CULngInt(requestedBytes)
    Dim z16 As Const UByte Ptr = CPtr(Const UByte Ptr, zInput)
    Dim byteLength As ULongInt = 0
    While byteLength < scanLimit AndAlso _
          (z16[byteLength] <> 0 OrElse z16[byteLength + 1] <> 0)
        byteLength += 2
    Wend

    If requestedBytes < 0 Then
        If byteLength = scanLimit AndAlso _
           (z16[byteLength] <> 0 OrElse z16[byteLength + 1] <> 0) Then
            sqlite3Error(db, SQLITE_TOOBIG)
            Return SQLITE_TOOBIG
        End If
    ElseIf CULngInt(requestedBytes) > maximumBytes AndAlso _
           byteLength = maximumBytes AndAlso _
           (z16[byteLength] <> 0 OrElse z16[byteLength + 1] <> 0) Then
        sqlite3Error(db, SQLITE_TOOBIG)
        Return SQLITE_TOOBIG
    End If

    sqlite3_mutex_enter(db->mutex)
    Dim zSql8 As ZString Ptr = sqlite3Utf16to8( _
        db, zInput, CLng(byteLength), SQLITE_UTF16NATIVE)
    If zSql8 = 0 Then
        Dim conversionCode As SQLITE_C_INT = SQLITE_TOOBIG
        If db->mallocFailed <> 0 Then conversionCode = SQLITE_NOMEM
        sqlite3Error(db, conversionCode)
        conversionCode = sqlite3ApiExit(db, conversionCode)
        db->errorCode = conversionCode
        sqlite3_mutex_leave(db->mutex)
        Return conversionCode
    End If

    Dim zTail8 As Const ZString Ptr = 0
    Dim lockFlags As SQLITE_C_UINT = prepFlags
    If saveSql <> 0 Then lockFlags Or= SQLITE_PREPARE_SAVESQL
    Dim resultCode As SQLITE_C_INT = sqlite3LockAndPrepare( _
        db, zSql8, -1, lockFlags, 0, ppStatement, @zTail8)
    If zTail8 <> 0 AndAlso pzTail <> 0 Then
        Dim parsedUtf8Bytes As LongInt = _
            CPtr(Const UByte Ptr, zTail8) - CPtr(Const UByte Ptr, zSql8)
        If parsedUtf8Bytes < 0 OrElse parsedUtf8Bytes > &H7FFFFFFF Then
            pzTail[0] = zInput
            If resultCode = SQLITE_OK Then resultCode = SQLITE_CORRUPT
        Else
            Dim parsedCharacters As SQLITE_C_INT = sqlite3Utf8CharLen( _
                CPtr(Const UByte Ptr, zSql8), CInt(parsedUtf8Bytes))
            Dim parsedUtf16Bytes As SQLITE_C_INT = sqlite3Utf16ByteLen( _
                zInput, CInt(byteLength), parsedCharacters)
            pzTail[0] = CPtr(Any Ptr, CPtr(Const UByte Ptr, zInput) + parsedUtf16Bytes)
        End If
    End If
    sqlite3DbFree(db, zSql8)
    If db->mallocFailed <> 0 Then resultCode = SQLITE_NOMEM
    resultCode = sqlite3ApiExit(db, resultCode)
    db->errorCode = resultCode
    sqlite3_mutex_leave(db->mutex)
    Return resultCode
End Function
#endif

Function sqlite3_prepare CDecl Alias "sqlite3_prepare" ( _
    ByVal pDatabase As Any Ptr, _
    ByVal zSql As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal ppStatement As Any Ptr Ptr, _
    ByVal pzTail As Const ZString Ptr Ptr _
) As SQLITE_C_INT Export
    Return sqlite3LockAndPrepare(CPtr(sqlite3 Ptr, pDatabase), zSql, nByte, _
        0, 0, ppStatement, pzTail)
End Function

Function sqlite3_prepare_v2 CDecl Alias "sqlite3_prepare_v2" ( _
    ByVal pDatabase As Any Ptr, _
    ByVal zSql As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal ppStatement As Any Ptr Ptr, _
    ByVal pzTail As Const ZString Ptr Ptr _
) As SQLITE_C_INT Export
    Return sqlite3LockAndPrepare(CPtr(sqlite3 Ptr, pDatabase), zSql, nByte, _
        SQLITE_PREPARE_SAVESQL, 0, ppStatement, pzTail)
End Function

Function sqlite3_prepare_v3 CDecl Alias "sqlite3_prepare_v3" ( _
    ByVal pDatabase As Any Ptr, _
    ByVal zSql As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal prepFlags As SQLITE_C_UINT, _
    ByVal ppStatement As Any Ptr Ptr, _
    ByVal pzTail As Const ZString Ptr Ptr _
) As SQLITE_C_INT Export
    Dim maskedFlags As SQLITE_C_UINT = _
        SQLITE_PREPARE_SAVESQL Or (prepFlags And SQLITE_PREPARE_MASK)
    Return sqlite3LockAndPrepare(CPtr(sqlite3 Ptr, pDatabase), zSql, nByte, _
        maskedFlags, 0, ppStatement, pzTail)
End Function

#ifndef SQLITE_OMIT_UTF16
Function sqlite3_prepare16 CDecl Alias "sqlite3_prepare16" ( _
    ByVal pDatabase As Any Ptr, _
    ByVal zSql As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal ppStatement As Any Ptr Ptr, _
    ByVal pzTail As Any Ptr Ptr _
) As SQLITE_C_INT Export
    Return sqlite3Prepare16(CPtr(sqlite3 Ptr, pDatabase), zSql, _
        nByte And Not 1, 0, 0, ppStatement, pzTail)
End Function

Function sqlite3_prepare16_v2 CDecl Alias "sqlite3_prepare16_v2" ( _
    ByVal pDatabase As Any Ptr, _
    ByVal zSql As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal ppStatement As Any Ptr Ptr, _
    ByVal pzTail As Any Ptr Ptr _
) As SQLITE_C_INT Export
    Return sqlite3Prepare16(CPtr(sqlite3 Ptr, pDatabase), zSql, _
        nByte And Not 1, 0, 1, ppStatement, pzTail)
End Function

Function sqlite3_prepare16_v3 CDecl Alias "sqlite3_prepare16_v3" ( _
    ByVal pDatabase As Any Ptr, _
    ByVal zSql As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal prepFlags As SQLITE_C_UINT, _
    ByVal ppStatement As Any Ptr Ptr, _
    ByVal pzTail As Any Ptr Ptr _
) As SQLITE_C_INT Export
    Dim maskedFlags As SQLITE_C_UINT = _
        (prepFlags And SQLITE_PREPARE_MASK) Or SQLITE_PREPARE_SAVESQL
    Return sqlite3Prepare16(CPtr(sqlite3 Ptr, pDatabase), zSql, _
        nByte And Not 1, maskedFlags, 1, ppStatement, pzTail)
End Function
#endif

Function sqlite3Reprepare CDecl Alias "sqlite3Reprepare" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT
    If pVdbe = 0 Then Return SQLITE_MISUSE

    Dim oldStatement As SqliteVdbe Ptr = 0
    Dim sqlText As Const ZString Ptr = sqlite3_sql(pVdbe)
    Dim db As sqlite3 Ptr = sqlite3VdbeDb(pVdbe)
    Dim prepFlags As UByte = sqlite3VdbePrepareFlags(pVdbe)
    If db = 0 OrElse sqlText = 0 Then Return SQLITE_MISUSE

    Dim resultCode As SQLITE_C_INT = sqlite3LockAndPrepare( _
        db, sqlText, -1, prepFlags, pVdbe, _
        CPtr(Any Ptr Ptr, @oldStatement), 0)
    If resultCode <> SQLITE_OK Then
        If resultCode = SQLITE_NOMEM Then sqlite3OomFault(db)
        Return resultCode
    End If

    sqlite3VdbeSwap(oldStatement, pVdbe)
    sqlite3TransferBindings(oldStatement, pVdbe)
    sqlite3VdbeResetStepResult(oldStatement)
    sqlite3VdbeFinalize(oldStatement)
    Return SQLITE_OK
End Function



/' Schema initialization callback bodies translated from prepare.c '/

Private Sub corruptSchema CDecl Alias "corruptSchema" (ByVal arg0 As SqliteInitData Ptr, ByVal arg1 As ZString Ptr Ptr, ByVal arg2 As Const ZString Ptr)
    Dim local0 As sqlite3 Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Static local1(0 To 3) As Const ZString Ptr = {Cast(Const ZString Ptr, StrPtr(!"rename")), Cast(Const ZString Ptr, StrPtr(!"drop column")), Cast(Const ZString Ptr, StrPtr(!"add column")), Cast(Const ZString Ptr, StrPtr(!"drop constraint"))}
    Dim c2fb_temp_2 As ZString Ptr Ptr
    Dim c2fb_temp_3 As ZString Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim local2 As ZString Ptr
    Dim local3 As Const ZString Ptr
    Dim c2fb_temp_8 As ZString Ptr
    Dim c2fb_temp_9 As ZString Ptr
    Dim c2fb_temp_10 As ZString Ptr Ptr
    Dim c2fb_temp_11 As ZString Ptr
    Dim c2fb_temp_12 As SQLITE_C_INT Ptr
    Dim c2fb_temp_13 As SQLITE_C_INT

    local0 = arg0->db
    If local0->mallocFailed Then
        c2fb_temp_0 = @(arg0->rc)
        c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 7ULL))
        (*c2fb_temp_0) = c2fb_temp_1
    Else
        If (-Cast(SQLITE_C_INT, ((arg0->pzErrMsg[Cast(SQLITE_C_INT, &O0ULL)] <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            ' empty C block
        Else
            If Cast(SQLITE_C_UINT, (arg0->mInitFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H0007ULL))))) Then
                ' C static array storage
                c2fb_temp_2 = @((*arg0->pzErrMsg))
                c2fb_temp_3 = CPtr(ZString Ptr, sqlite3MPrintf(CPtr(Any Ptr, local0), StrPtr(!"error in %s %s after %s: %s"), arg1[Cast(SQLITE_C_INT, &O0ULL)], arg1[Cast(SQLITE_C_INT, 1ULL)], local1(Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (arg0->mInitFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0007ULL))))) - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))), arg2))
                (*c2fb_temp_2) = c2fb_temp_3
                c2fb_temp_4 = @(arg0->rc)
                c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                (*c2fb_temp_4) = c2fb_temp_5
            Else
                If Cast(sqlite3_uint64, (local0->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &H00000001ULL)))) Then
                    c2fb_temp_6 = @(arg0->rc)
                    c2fb_temp_7 = Cast(SQLITE_C_INT, sqlite3CorruptError(Cast(SQLITE_C_INT, 46ULL)))
                    (*c2fb_temp_6) = c2fb_temp_7
                Else
                    ' C automatic storage declaration
                    local3 = IIf(arg1[Cast(SQLITE_C_INT, 1ULL)], CPtr(Const ZString Ptr, arg1[Cast(SQLITE_C_INT, 1ULL)]), StrPtr(!"?"))
                    c2fb_temp_8 = CPtr(ZString Ptr, sqlite3MPrintf(CPtr(Any Ptr, local0), StrPtr(!"malformed database schema (%s)"), local3))
                    local2 = c2fb_temp_8
                    If (-Cast(SQLITE_C_INT, ((arg2 AndAlso CPtr(Const Byte Ptr, arg2)[Cast(SQLITE_C_INT, &O0ULL)])))) Then
                        c2fb_temp_9 = CPtr(ZString Ptr, sqlite3MPrintf(CPtr(Any Ptr, local0), StrPtr(!"%z - %s"), local2, arg2))
                        local2 = c2fb_temp_9
                    End If
                    c2fb_temp_10 = @((*arg0->pzErrMsg))
                    c2fb_temp_11 = local2
                    (*c2fb_temp_10) = c2fb_temp_11
                    c2fb_temp_12 = @(arg0->rc)
                    c2fb_temp_13 = Cast(SQLITE_C_INT, sqlite3CorruptError(Cast(SQLITE_C_INT, 53ULL)))
                    (*c2fb_temp_12) = c2fb_temp_13
                End If
            End If
        End If
    End If
End Sub

Function sqlite3InitCallback CDecl Alias "sqlite3InitCallback" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As ZString Ptr Ptr, ByVal arg3 As ZString Ptr Ptr) As SQLITE_C_INT
    Dim local0 As SqliteInitData Ptr
    Dim local1 As sqlite3 Ptr
    Dim local2 As SQLITE_C_INT
    Dim c2fb_temp_0 As u32 Ptr
    Dim c2fb_temp_1 As SQLITE_C_UINT
    Dim c2fb_temp_2 As u32 Ptr
    Dim c2fb_temp_3 As SQLITE_C_UINT
    Dim local3 As SQLITE_C_INT
    Dim local4 As UByte
    Dim local5 As SqliteVdbe Ptr
    Dim local6 As Const ZString Ptr
    Dim c2fb_temp_4 As u8 Ptr
    Dim c2fb_temp_5 As UByte
    Dim c2fb_temp_6 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As Const ZString Ptr Ptr Ptr
    Dim c2fb_temp_9 As Const ZString Ptr Ptr
    Dim c2fb_temp_10 As SqliteVdbe Ptr
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As u8 Ptr
    Dim c2fb_temp_13 As UByte
    Dim c2fb_temp_14 As SQLITE_C_INT Ptr
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As Any Ptr
    Dim c2fb_temp_17 As Const ZString Ptr Ptr Ptr
    Dim c2fb_temp_18 As Const ZString Ptr Ptr
    Dim local7 As SqliteIndex Ptr
    Dim c2fb_temp_19 As SqliteIndex Ptr
    Dim local8 As SqliteSchema Ptr
    Dim c2fb_temp_20 As ZString Ptr Ptr
    Dim c2fb_temp_21 As ZString Ptr
    Dim c2fb_temp_22 As SQLITE_C_INT Ptr
    Dim c2fb_temp_23 As SQLITE_C_INT

    local0 = CPtr(SqliteInitData Ptr, arg0)
    local1 = local0->db
    local2 = local0->iDb
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = @(local1->mDbFlags)
    c2fb_temp_1 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_0)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0040ULL)))))
    (*c2fb_temp_0) = Cast(u32, c2fb_temp_1)
    c2fb_temp_1 = Cast(SQLITE_C_UINT, (*c2fb_temp_0))
    If (-Cast(SQLITE_C_INT, ((arg2 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_2 = @(local0->nInitRow)
    c2fb_temp_3 = Cast(SQLITE_C_UINT, (*c2fb_temp_2))
    (*c2fb_temp_2) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_3 + 1)))
    If local1->mallocFailed Then
        corruptSchema(local0, arg2, Cast(SQLITE_C_INT, &O0ULL))
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((arg2[Cast(SQLITE_C_INT, 3ULL)] = Cast(SQLITE_C_INT, &O0ULL))))) Then
        corruptSchema(local0, arg2, Cast(SQLITE_C_INT, &O0ULL))
    Else
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg2[Cast(SQLITE_C_INT, 4ULL)] AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, 99) = Cast(SQLITE_C_INT, sqlite3UpperToLower(Cast(UByte, CPtr(Byte Ptr, arg2[Cast(SQLITE_C_INT, 4ULL)])[Cast(SQLITE_C_INT, &O0ULL)]))))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, 114) = Cast(SQLITE_C_INT, sqlite3UpperToLower(Cast(UByte, CPtr(Byte Ptr, arg2[Cast(SQLITE_C_INT, 4ULL)])[Cast(SQLITE_C_INT, 1ULL)]))))))))))) Then
            ' C automatic storage declaration
            local4 = local1->init.iDb
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' empty C statement
            ' C unused-parameter annotation
            c2fb_temp_4 = @(local1->init.iDb)
            c2fb_temp_5 = Cast(UByte, local2)
            (*c2fb_temp_4) = Cast(u8, c2fb_temp_5)
            c2fb_temp_5 = Cast(UByte, (*c2fb_temp_4))
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((sqlite3GetUInt32(CPtr(Const ZString Ptr, arg2[Cast(SQLITE_C_INT, 3ULL)]), CPtr(SQLITE_C_UINT Ptr, @(local1->init.newTnum))) = Cast(SQLITE_C_INT, &O0ULL))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local1->init.newTnum > local0->mxPage)))) AndAlso (-Cast(SQLITE_C_INT, ((local0->mxPage > Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))))))) Then
                If sqlite3ConfigExtraSchemaChecksEnabled() Then
                    corruptSchema(local0, arg2, StrPtr(!"invalid rootpage"))
                End If
            End If
            c2fb_temp_6 = @(local1->init.flags)
            c2fb_temp_7 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            c2fb_temp_7 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_7) And Cast(SQLITE_C_UINT, &H1ULL)))
            (*c2fb_temp_6) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_6)) And Not(Cast(SQLITE_C_UINT, &H1ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_7) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 0)))
            c2fb_temp_7 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_7) And Cast(SQLITE_C_UINT, &H1ULL)))
            c2fb_temp_8 = @(local1->init.azInit)
            c2fb_temp_9 = CPtr(Const ZString Ptr Ptr, arg2)
            (*c2fb_temp_8) = c2fb_temp_9
            c2fb_temp_10 = CPtr(SqliteVdbe Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            local5 = c2fb_temp_10
            sqlite3Prepare(local1, CPtr(Const ZString Ptr, arg2[Cast(SQLITE_C_INT, 4ULL)]), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), CPtr(SqliteVdbe Ptr Ptr, @(local5)), CPtr(Const ZString Ptr Ptr, @(local6)))
            c2fb_temp_11 = Cast(SQLITE_C_INT, local1->errorCode)
            local3 = c2fb_temp_11
            ' C unused-parameter annotation
            c2fb_temp_12 = @(local1->init.iDb)
            c2fb_temp_13 = Cast(UByte, local4)
            (*c2fb_temp_12) = Cast(u8, c2fb_temp_13)
            c2fb_temp_13 = Cast(UByte, (*c2fb_temp_12))
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) <> local3)))) Then
                If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->init.flags) Shr 0) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                    ' C unused-parameter annotation
                Else
                    If (-Cast(SQLITE_C_INT, ((local3 > local0->rc)))) Then
                        c2fb_temp_14 = @(local0->rc)
                        c2fb_temp_15 = Cast(SQLITE_C_INT, local3)
                        (*c2fb_temp_14) = c2fb_temp_15
                    End If
                    If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, 7ULL))))) Then
                        c2fb_temp_16 = CPtr(Any Ptr, sqlite3OomFault(CPtr(Any Ptr, local1)))
                    Else
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, 9ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (local3 And Cast(SQLITE_C_INT, &HFFULL)))) <> Cast(SQLITE_C_INT, 6ULL))))))))) Then
                            corruptSchema(local0, arg2, CPtr(Const ZString Ptr, sqlite3_errmsg(CPtr(Any Ptr, local1))))
                        End If
                    End If
                End If
            Else
                If CPtr(Const Byte Ptr, local6)[Cast(SQLITE_C_INT, &O0ULL)] Then
                    corruptSchema(local0, arg2, Cast(SQLITE_C_INT, &O0ULL))
                End If
            End If
            c2fb_temp_17 = @(local1->init.azInit)
            c2fb_temp_18 = sqlite3StdTypeTable()
            (*c2fb_temp_17) = c2fb_temp_18
            sqlite3_finalize(CPtr(Any Ptr, local5))
        Else
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg2[Cast(SQLITE_C_INT, 1ULL)] = Cast(SQLITE_C_INT, &O0ULL))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg2[Cast(SQLITE_C_INT, 4ULL)] <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(Byte Ptr, arg2[Cast(SQLITE_C_INT, 4ULL)])[Cast(SQLITE_C_INT, &O0ULL)]) <> Cast(SQLITE_C_INT, &O0ULL)))))))))))))) Then
                corruptSchema(local0, arg2, Cast(SQLITE_C_INT, &O0ULL))
            Else
                ' C automatic storage declaration
                c2fb_temp_19 = CPtr(SqliteIndex Ptr, sqlite3FindIndex(CPtr(Any Ptr, local1), CPtr(Const ZString Ptr, arg2[Cast(SQLITE_C_INT, 1ULL)]), CPtr(Const ZString Ptr, CPtr(ZString Ptr, local1->aDb(local2).zDbSName))))
                local7 = c2fb_temp_19
                If (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    corruptSchema(local0, arg2, StrPtr(!"orphan index"))
                Else
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((sqlite3GetUInt32(CPtr(Const ZString Ptr, arg2[Cast(SQLITE_C_INT, 3ULL)]), CPtr(SQLITE_C_UINT Ptr, @(local7->tnum))) = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local7->tnum < Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 2ULL)))))))))) OrElse (-Cast(SQLITE_C_INT, ((local7->tnum > local0->mxPage)))))))) OrElse sqlite3IndexHasDuplicateRootPage(CPtr(Any Ptr, local7)))))) Then
                        If sqlite3ConfigExtraSchemaChecksEnabled() Then
                            corruptSchema(local0, arg2, StrPtr(!"invalid rootpage"))
                        End If
                    End If
                End If
            End If
        End If
    End If
    If (-Cast(SQLITE_C_INT, ((local0->pzErrMsg[Cast(SQLITE_C_INT, &O0ULL)] = Cast(SQLITE_C_INT, &O0ULL))))) Then
        local8 = local1->aDb(local2).pSchema
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (local8->tblHash.count + local8->idxHash.count)) + local8->trigHash.count)) > Cast(SQLITE_C_UINT, local1->aLimit(Cast(SQLITE_C_INT, 13ULL))))))) Then
            c2fb_temp_20 = @((*local0->pzErrMsg))
            c2fb_temp_21 = CPtr(ZString Ptr, sqlite3MPrintf(CPtr(Any Ptr, local1), StrPtr(!"too many schema objects")))
            (*c2fb_temp_20) = c2fb_temp_21
            c2fb_temp_22 = @(local0->rc)
            c2fb_temp_23 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
            (*c2fb_temp_22) = c2fb_temp_23
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

/' end of sqlite3_prepare.bas '/
