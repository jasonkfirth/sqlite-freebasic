/'
** 2001 September 15
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
*************************************************************************
** This module compiles ANALYZE statements and collects sqlite_stat1 data,
** with feature-gated sqlite_stat4 table generation.
'/
/'
    Project: SQLite FreeBASIC port

    File: sqlite3_analyze.bas

    Purpose:

        Compile ANALYZE statements and collect sqlite_stat1 statistics.
        Emit sqlite_stat4 sample rows when the STAT4 profile is enabled.

    Responsibilities:

        - Rebuild sqlite_stat1 entries for tables and indexes.
        - Collect per-prefix distinct counts through internal SQL callbacks.
        - Emit OP_LoadAnalysis after the new statistics are written.
        - Attach index-column names to VDBE opcodes when explain comments are enabled.

    This file intentionally does NOT contain:

        - STAT4 sample selection and storage algorithms in the callback module.
        - The VDBE interpreter's OP_LoadAnalysis implementation.
'/ 

#lang "fb"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_debug_assert.bi"
#include once "sqlite3_straccum.bi"

Declare Function sqlite3_value_blob CDecl Alias "sqlite3_value_blob" (ByVal pValue As Any Ptr) As Any Ptr
Declare Function sqlite3_value_int CDecl Alias "sqlite3_value_int" (ByVal pValue As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_value_int64 CDecl Alias "sqlite3_value_int64" (ByVal pValue As Any Ptr) As sqlite3_int64
Declare Function sqlite3_context_db_handle CDecl Alias "sqlite3_context_db_handle" (ByVal pContext As Any Ptr) As Any Ptr
Declare Sub sqlite3_result_blob CDecl Alias "sqlite3_result_blob" (ByVal pContext As Any Ptr, ByVal pData As Any Ptr, ByVal byteCount As SQLITE_C_INT, ByVal xDestroy As Any Ptr)
Declare Sub sqlite3_result_error CDecl Alias "sqlite3_result_error" (ByVal pContext As Any Ptr, ByVal zMessage As Const ZString Ptr, ByVal byteCount As SQLITE_C_INT)
Declare Sub sqlite3_result_error_nomem CDecl Alias "sqlite3_result_error_nomem" (ByVal pContext As Any Ptr)
Declare Sub sqlite3_result_int CDecl Alias "sqlite3_result_int" (ByVal pContext As Any Ptr, ByVal value As SQLITE_C_INT)
Declare Sub sqlite3_result_str CDecl Alias "sqlite3_result_str" (ByVal pContext As Any Ptr, ByVal pAccumulator As sqlite3_str Ptr, ByVal ownership As SQLITE_C_INT)
Declare Sub sqlite3_str_appendf CDecl Alias "sqlite3_str_appendf" (ByVal pAccumulator As sqlite3_str Ptr, ByVal zFormat As Const ZString Ptr, ...)
Declare Function sqlite3FindTable CDecl Alias "sqlite3FindTable" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zTable As Const ZString Ptr, _
    ByVal zDatabase As Const ZString Ptr _
) As Any Ptr
Declare Sub sqlite3NestedParse CDecl Alias "sqlite3NestedParse" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Sub sqlite3TableLock CDecl Alias "sqlite3TableLock" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal databaseIndex As SQLITE_C_INT, _
    ByVal rootPage As SQLITE_C_INT, _
    ByVal isWriteLock As u8, _
    ByVal zTable As Const ZString Ptr _
)
Declare Function sqlite3SchemaToIndex CDecl Alias "sqlite3SchemaToIndex" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pSchema As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3AuthCheck CDecl Alias "sqlite3AuthCheck" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal actionCode As SQLITE_C_INT, _
    ByVal zArgument1 As Const ZString Ptr, _
    ByVal zArgument2 As Const ZString Ptr, _
    ByVal zDatabase As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_strlike CDecl Alias "sqlite3_strlike" ( _
    ByVal zPattern As Const ZString Ptr, _
    ByVal zText As Const ZString Ptr, _
    ByVal escapeCharacter As SQLITE_C_UINT _
) As SQLITE_C_INT
Declare Function sqlite3LocateCollSeq CDecl Alias "sqlite3LocateCollSeq" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal zName As Const ZString Ptr _
) As Any Ptr
Declare Sub sqlite3BeginWriteOperation CDecl Alias "sqlite3BeginWriteOperation" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal isStatementJournal As SQLITE_C_INT, _
    ByVal databaseIndex As SQLITE_C_INT _
)
Declare Sub sqlite3OpenTable CDecl Alias "sqlite3OpenTable" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal cursorNumber As SQLITE_C_INT, _
    ByVal databaseIndex As SQLITE_C_INT, _
    ByVal pTable As SqliteTable Ptr, _
    ByVal opcode As SQLITE_C_INT _
)
Declare Function sqlite3FirstAvailableRegister CDecl Alias "sqlite3FirstAvailableRegister" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal firstCandidate As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3ReadSchema CDecl Alias "sqlite3ReadSchema" ( _
    ByVal pParse As SqliteParseContext Ptr _
) As SQLITE_C_INT
Declare Function sqlite3FindDb CDecl Alias "sqlite3FindDb" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pDatabaseName As sqlite3ParserToken Ptr _
) As SQLITE_C_INT
Declare Function sqlite3TwoPartName CDecl Alias "sqlite3TwoPartName" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pName1 As sqlite3ParserToken Ptr, _
    ByVal pName2 As sqlite3ParserToken Ptr, _
    ByVal ppTableName As sqlite3ParserToken Ptr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3NameFromToken CDecl Alias "sqlite3NameFromToken" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pToken As sqlite3ParserToken Ptr _
) As ZString Ptr
Declare Function sqlite3FindIndex CDecl Alias "sqlite3FindIndex" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal zDatabase As Const ZString Ptr _
) As Any Ptr
Declare Function sqlite3LocateTable CDecl Alias "sqlite3LocateTable" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal zName As Const ZString Ptr, _
    ByVal zDatabase As Const ZString Ptr _
) As Any Ptr
Declare Sub sqlite3ExprCodeLoadIndexColumn CDecl Alias "sqlite3ExprCodeLoadIndexColumn" ( _
    ByVal pParse As Any Ptr, _
    ByVal pIndex As Any Ptr, _
    ByVal cursorNumber As SQLITE_C_INT, _
    ByVal columnNumber As SQLITE_C_INT, _
    ByVal targetRegister As SQLITE_C_INT _
)

' -------------------------------------------------------------------------
' STAT1 and STAT4 accumulator state and SQL callbacks
' -------------------------------------------------------------------------

Private Dim Shared statFunctionDefinitions(0 To 2) As SqliteFuncDef
Private Dim Shared statFunctionDefinitionsReady As u8 = 0
' This is the SQLITE_Stat4 bit from src/sqliteInt.h, used by OP_Count.
Private Const SQLITE_ANALYZE_STAT4_OPTIMIZATION As u32 = &H00000800
' sqlite_stat1 stores the table name, index name, and statistics string.
Private Const SQLITE_ANALYZE_STAT_COLUMN_COUNT As SQLITE_C_INT = 3
Private Const SQLITE_ANALYZE_STAT_GET_STAT1 As SQLITE_C_INT = 0
#ifdef SQLITE_ENABLE_STAT4
Private Const SQLITE_ANALYZE_STAT_GET_ROWID As SQLITE_C_INT = 1
Private Const SQLITE_ANALYZE_STAT_GET_NEQ As SQLITE_C_INT = 2
Private Const SQLITE_ANALYZE_STAT_GET_NLT As SQLITE_C_INT = 3
Private Const SQLITE_ANALYZE_STAT_GET_NDLT As SQLITE_C_INT = 4
#endif
Private Const SQLITE_ANALYZE_STAT_LINE_BYTES As SQLITE_C_INT = 100
Private Const SQLITE_ANALYZE_PRIMARY_KEY_INDEX As u32 = 2
' sqlite3_strlike uses ASCII backslash as the LIKE escape character.
Private Const SQLITE_ANALYZE_LIKE_ESCAPE As SQLITE_C_UINT = 92

Declare Sub loadAnalysis CDecl Alias "loadAnalysis" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal iDb As SQLITE_C_INT _
)

#ifdef SQLITE_ENABLE_STAT4
Declare Sub sqlite3Stat4InitCallback CDecl Alias "sqlite3Stat4InitCallback" ( _
    ByVal pContext As SqliteResultContext Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
Declare Sub sqlite3Stat4PushCallback CDecl Alias "sqlite3Stat4PushCallback" ( _
    ByVal pContext As SqliteResultContext Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
Declare Sub sqlite3Stat4GetCallback CDecl Alias "sqlite3Stat4GetCallback" ( _
    ByVal pContext As SqliteResultContext Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
#endif

#ifndef SQLITE_ENABLE_STAT4
Private Sub statAccumDestructor CDecl Alias "statAccumDestructor" ( _
    ByVal pOld As Any Ptr _
)
    If pOld = 0 Then Exit Sub
    Dim pStat As SqliteStatAccum Ptr = CPtr(SqliteStatAccum Ptr, pOld)
    If pStat->db <> 0 Then sqlite3DbFree(pStat->db, pStat)
End Sub
#endif

#ifndef SQLITE_ENABLE_STAT4
Private Sub statInit CDecl Alias "statInit" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 Then Exit Sub
    If argumentCount <> 4 OrElse pArguments = 0 Then
        sqlite3_result_error(pContext, StrPtr(!"invalid stat_init arguments"), -1)
        Exit Sub
    End If

    Dim nCol As SQLITE_C_INT = sqlite3_value_int(pArguments[0])
    Dim nKeyCol As SQLITE_C_INT = sqlite3_value_int(pArguments[1])
    Dim nEstimate As sqlite3_int64 = sqlite3_value_int64(pArguments[2])
    Dim nLimit As SQLITE_C_INT = sqlite3_value_int(pArguments[3])
    If nCol <= 0 OrElse nKeyCol <= 0 OrElse nKeyCol > nCol OrElse nLimit < 0 Then
        sqlite3_result_error(pContext, StrPtr(!"invalid stat_init dimensions"), -1)
        Exit Sub
    End If

    Dim allocationSize As sqlite3_uint64 = _
        Cast(sqlite3_uint64, SizeOf(SqliteStatAccum)) + _
        Cast(sqlite3_uint64, nCol) * SizeOf(sqlite3_uint64)
    Dim db As sqlite3 Ptr = _
        CPtr(sqlite3 Ptr, sqlite3_context_db_handle(pContext))
    If db = 0 Then
        sqlite3_result_error(pContext, StrPtr(!"stat_init has no database"), -1)
        Exit Sub
    End If

    Dim pStat As SqliteStatAccum Ptr = _
        CPtr(SqliteStatAccum Ptr, sqlite3DbMallocZero(db, allocationSize))
    If pStat = 0 Then
        sqlite3_result_error_nomem(pContext)
        Exit Sub
    End If

    pStat->db = db
    pStat->nEst = Cast(sqlite3_uint64, nEstimate)
    pStat->nLimit = nLimit
    pStat->nCol = nCol
    pStat->nKeyCol = nKeyCol
    pStat->current.anDLt = CPtr(sqlite3_uint64 Ptr, _
        CPtr(UByte Ptr, pStat) + SizeOf(SqliteStatAccum))
    sqlite3_result_blob(pContext, pStat, SizeOf(SqliteStatAccum), _
                        ProcPtr(statAccumDestructor))
End Sub
#endif

#ifndef SQLITE_ENABLE_STAT4
Private Sub statPush CDecl Alias "statPush" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 Then Exit Sub
    If argumentCount <> 2 OrElse pArguments = 0 Then
        sqlite3_result_error(pContext, StrPtr(!"invalid stat_push arguments"), -1)
        Exit Sub
    End If

    Dim pStat As SqliteStatAccum Ptr = _
        CPtr(SqliteStatAccum Ptr, sqlite3_value_blob(pArguments[0]))
    Dim changedColumn As SQLITE_C_INT = sqlite3_value_int(pArguments[1])
    If pStat = 0 OrElse pStat->current.anDLt = 0 OrElse _
       pStat->nCol <= 0 OrElse changedColumn < 0 OrElse changedColumn >= pStat->nCol Then
        sqlite3_result_error(pContext, StrPtr(!"invalid stat_push state"), -1)
        Exit Sub
    End If

    If pStat->nRow <> 0 Then
        For columnIndex As SQLITE_C_INT = changedColumn To pStat->nCol - 1
            pStat->current.anDLt[columnIndex] += 1
        Next
    End If
    pStat->nRow += 1

    If pStat->nLimit <> 0 Then
        Dim samplesPassed As sqlite3_uint64 = _
            Cast(sqlite3_uint64, pStat->nSkipAhead) + 1
        Dim rowLimit As sqlite3_uint64 = _
            Cast(sqlite3_uint64, pStat->nLimit) * samplesPassed
        If pStat->nRow > rowLimit Then
            pStat->nSkipAhead = Cast(u8, pStat->nSkipAhead + 1)
            sqlite3_result_int(pContext, CInt(pStat->current.anDLt[0] > 0))
        End If
    End If
End Sub
#endif

#ifndef SQLITE_ENABLE_STAT4
Private Sub statGet CDecl Alias "statGet" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 Then Exit Sub
    If argumentCount <> 1 OrElse pArguments = 0 Then
        sqlite3_result_error(pContext, StrPtr(!"invalid stat_get arguments"), -1)
        Exit Sub
    End If

    Dim pStat As SqliteStatAccum Ptr = _
        CPtr(SqliteStatAccum Ptr, sqlite3_value_blob(pArguments[0]))
    If pStat = 0 OrElse pStat->current.anDLt = 0 OrElse _
       pStat->nCol <= 0 OrElse pStat->nKeyCol <= 0 OrElse pStat->nKeyCol > pStat->nCol Then
        sqlite3_result_error(pContext, StrPtr(!"invalid stat_get state"), -1)
        Exit Sub
    End If

    Dim statText As sqlite3_str
    Dim maximumBytes As SQLITE_C_INT = _
        (pStat->nKeyCol + 1) * SQLITE_ANALYZE_STAT_LINE_BYTES
    sqlite3StrAccumInit(@statText, 0, 0, 0, maximumBytes)

    Dim rowCount As sqlite3_uint64 = pStat->nRow
    If pStat->nSkipAhead <> 0 Then rowCount = pStat->nEst
    sqlite3_str_appendf(@statText, StrPtr(!"%llu"), rowCount)

    For columnIndex As SQLITE_C_INT = 0 To pStat->nKeyCol - 1
        Dim distinctCount As sqlite3_uint64 = _
            pStat->current.anDLt[columnIndex] + 1
        Dim estimate As sqlite3_uint64 = _
            (pStat->nRow + distinctCount - 1) \ distinctCount
        If estimate = 2 AndAlso pStat->nRow * 10 <= distinctCount * 11 Then _
            estimate = 1
        sqlite3_str_appendf(@statText, StrPtr(!" %llu"), estimate)
    Next

    sqlite3_result_str(pContext, @statText, SQLITE_XFER)
End Sub
#endif

Private Sub initializeStatFunctionDefinitions()
    Dim pMutex As Any Ptr = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MAIN)
    sqlite3_mutex_enter(pMutex)
    If statFunctionDefinitionsReady = 0 Then
        With statFunctionDefinitions(0)
            .nArg = 4
            .funcFlags = SQLITE_UTF8
#ifdef SQLITE_ENABLE_STAT4
            .xSFunc = @sqlite3Stat4InitCallback
#else
            .xSFunc = @statInit
#endif
            .zName = StrPtr(!"stat_init")
        End With
        With statFunctionDefinitions(1)
#ifdef SQLITE_ENABLE_STAT4
            .nArg = 3
            .xSFunc = @sqlite3Stat4PushCallback
#else
            .nArg = 2
            .xSFunc = @statPush
#endif
            .funcFlags = SQLITE_UTF8
            .zName = StrPtr(!"stat_push")
        End With
        With statFunctionDefinitions(2)
#ifdef SQLITE_ENABLE_STAT4
            .nArg = 2
            .xSFunc = @sqlite3Stat4GetCallback
#else
            .nArg = 1
            .xSFunc = @statGet
#endif
            .funcFlags = SQLITE_UTF8
            .zName = StrPtr(!"stat_get")
        End With
        statFunctionDefinitionsReady = 1
    End If
    sqlite3_mutex_leave(pMutex)
End Sub

Private Sub callStatGet CDecl Alias "callStatGet" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal statRegister As SQLITE_C_INT, _
    ByVal statKind As SQLITE_C_INT, _
    ByVal outputRegister As SQLITE_C_INT _
)
    If pParse = 0 OrElse pParse->pVdbe = 0 OrElse _
       statRegister <= 0 OrElse outputRegister <= 0 OrElse _
       outputRegister = statRegister OrElse outputRegister = statRegister + 1 Then Exit Sub
#ifndef SQLITE_ENABLE_STAT4
    If statKind <> SQLITE_ANALYZE_STAT_GET_STAT1 Then Exit Sub
#else
    If statKind < SQLITE_ANALYZE_STAT_GET_STAT1 OrElse _
       statKind > SQLITE_ANALYZE_STAT_GET_NDLT Then Exit Sub
#endif
    initializeStatFunctionDefinitions()
#ifdef SQLITE_ENABLE_STAT4
    sqlite3VdbeAddOp2(pParse->pVdbe, OP_Integer, statKind, statRegister + 1)
    sqlite3VdbeAddFunctionCall(pParse, 0, statRegister, outputRegister, 2, _
                               @statFunctionDefinitions(2), 0)
#else
    sqlite3VdbeAddFunctionCall(pParse, 0, statRegister, outputRegister, 1, _
        @statFunctionDefinitions(2), 0)
#endif
End Sub

/' ------------------------------------------------------------------------- '/
/' sqlite_stat1 table setup                                                  '/
/' ------------------------------------------------------------------------- '/

Private Sub openStatTable CDecl Alias "openStatTable" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal databaseIndex As SQLITE_C_INT, _
    ByVal firstCursor As SQLITE_C_INT, _
    ByVal zWhere As Const ZString Ptr, _
    ByVal zWhereType As Const ZString Ptr _
)
    If pParse = 0 OrElse pParse->db = 0 Then Exit Sub
    Dim db As sqlite3 Ptr = pParse->db
    If databaseIndex < 0 OrElse databaseIndex >= db->nDb Then Exit Sub

    Dim pVdbe As SqliteVdbe Ptr = sqlite3GetVdbe(pParse)
    If pVdbe = 0 Then Exit Sub

    Dim pDbSlot As SqliteDbSlot Ptr = @db->aDb(databaseIndex)
    Dim pStatTable As SqliteTable Ptr = _
        CPtr(SqliteTable Ptr, sqlite3FindTable(db, StrPtr(!"sqlite_stat1"), pDbSlot->zDbSName))
    Dim rootPage As SQLITE_C_INT
    Dim createFlag As u8 = 0

    If pStatTable = 0 Then
        ' The CREATE TABLE side effect leaves its root page in regRoot; the
        ' following OpenWrite reads that register through OPFLAG_P2ISREG.
        sqlite3NestedParse(pParse, StrPtr(!"CREATE TABLE %Q.%s(%s)"), _
            pDbSlot->zDbSName, StrPtr(!"sqlite_stat1"), StrPtr(!"tbl,idx,stat"))
        rootPage = pParse->u1.cr.regRoot
        createFlag = OPFLAG_P2ISREG
    Else
        rootPage = pStatTable->tnum
        sqlite3TableLock(pParse, databaseIndex, rootPage, 1, StrPtr(!"sqlite_stat1"))
        If zWhere <> 0 Then
            If zWhereType = 0 Then Exit Sub
            sqlite3NestedParse(pParse, _
                StrPtr(!"DELETE FROM %Q.%s WHERE %s=%Q"), _
                pDbSlot->zDbSName, StrPtr(!"sqlite_stat1"), zWhereType, zWhere)
        Else
            sqlite3VdbeAddOp2(pVdbe, OP_Clear, rootPage, databaseIndex)
        End If
    End If

    sqlite3VdbeAddOp4Int(pVdbe, OP_OpenWrite, firstCursor, rootPage, databaseIndex, _
                         SQLITE_ANALYZE_STAT_COLUMN_COUNT)
    sqlite3VdbeChangeP5(pVdbe, createFlag)

#ifdef SQLITE_ENABLE_STAT4
    Dim stat4Enabled As SQLITE_C_INT = _
        CInt((db->dbOptFlags And SQLITE_ANALYZE_STAT4_OPTIMIZATION) <> 0)
    Dim pStat4Table As SqliteTable Ptr = _
        CPtr(SqliteTable Ptr, sqlite3FindTable(db, StrPtr(!"sqlite_stat4"), pDbSlot->zDbSName))
    Dim stat4RootPage As SQLITE_C_INT = 0
    Dim stat4CreateFlag As u8 = 0

    If pStat4Table = 0 Then
        If stat4Enabled <> 0 Then
            sqlite3NestedParse(pParse, StrPtr(!"CREATE TABLE %Q.%s(%s)"), _
                pDbSlot->zDbSName, StrPtr(!"sqlite_stat4"), _
                StrPtr(!"tbl,idx,neq,nlt,ndlt,sample"))
            stat4RootPage = pParse->u1.cr.regRoot
            stat4CreateFlag = OPFLAG_P2ISREG
        End If
    Else
        stat4RootPage = pStat4Table->tnum
        sqlite3TableLock(pParse, databaseIndex, stat4RootPage, 1, _
                         StrPtr(!"sqlite_stat4"))
        If zWhere <> 0 Then
            If zWhereType = 0 Then Exit Sub
            sqlite3NestedParse(pParse, _
                StrPtr(!"DELETE FROM %Q.%s WHERE %s=%Q"), _
                pDbSlot->zDbSName, StrPtr(!"sqlite_stat4"), zWhereType, zWhere)
        Else
#ifdef SQLITE_ENABLE_PREUPDATE_HOOK
            If db->xPreUpdateCallback <> 0 Then
                sqlite3NestedParse(pParse, StrPtr(!"DELETE FROM %Q.%s"), _
                    pDbSlot->zDbSName, StrPtr(!"sqlite_stat4"))
            Else
                sqlite3VdbeAddOp2(pVdbe, OP_Clear, stat4RootPage, databaseIndex)
            End If
#else
            sqlite3VdbeAddOp2(pVdbe, OP_Clear, stat4RootPage, databaseIndex)
#endif
        End If
    End If

    If stat4Enabled <> 0 Then
        sqlite3VdbeAddOp4Int(pVdbe, OP_OpenWrite, firstCursor + 1, _
                             stat4RootPage, databaseIndex, 6)
        sqlite3VdbeChangeP5(pVdbe, stat4CreateFlag)
    End If
#endif
End Sub

#ifdef SQLITE_ENABLE_EXPLAIN_COMMENTS
Private Const SQLITE_ANALYZE_XN_ROWID As SQLITE_C_INT = -1
Private Const SQLITE_ANALYZE_XN_EXPR As SQLITE_C_INT = -2

Private Sub analyzeVdbeCommentIndexWithColumnName CDecl Alias "analyzeVdbeCommentIndexWithColumnName" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pIndex As SqliteIndex Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
)
    If pVdbe = 0 OrElse pIndex = 0 OrElse pIndex->zName = 0 Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("VDBE and index are valid for an index column comment"))
#endif
        Return
    End If
    If columnIndex < 0 OrElse columnIndex >= pIndex->nColumn OrElse _
       pIndex->aiColumn = 0 Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("index comment column is within the index"))
#endif
        Return
    End If

    Dim tableColumn As SQLITE_C_INT = pIndex->aiColumn[columnIndex]
    If tableColumn = SQLITE_ANALYZE_XN_ROWID Then
#ifdef SQLITE_DEBUG
        ' The C NEVER() macro asserts if a rowid column reaches this path.
        sqlite3DebugAssert(StrPtr("rowid is not an ordinary index column"))
#endif
        sqlite3VdbeComment(pVdbe, StrPtr("%s.rowid"), pIndex->zName)
    ElseIf tableColumn = SQLITE_ANALYZE_XN_EXPR Then
#ifdef SQLITE_DEBUG
        If (pIndex->flags And SQLITE_INDEX_HAS_EXPR) = 0 Then
            sqlite3DebugAssert(StrPtr("expression index column has an expression"))
        End If
#endif
        sqlite3VdbeComment(pVdbe, StrPtr("%s.expr(%d)"), pIndex->zName, columnIndex)
    Else
        If tableColumn < 0 OrElse pIndex->pTable = 0 OrElse _
           pIndex->pTable->aCol = 0 OrElse _
           tableColumn >= pIndex->pTable->nCol OrElse _
           pIndex->pTable->aCol[tableColumn].zCnName = 0 Then
#ifdef SQLITE_DEBUG
            sqlite3DebugAssert(StrPtr("ordinary index column maps to a table column"))
#endif
            Return
        End If
        sqlite3VdbeComment( _
            pVdbe, StrPtr("%s.%s"), pIndex->zName, _
            pIndex->pTable->aCol[tableColumn].zCnName)
    End If
End Sub
#endif

Private Sub analyzeOneTable CDecl Alias "analyzeOneTable" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pTable As SqliteTable Ptr, _
    ByVal pOnlyIndex As SqliteIndex Ptr, _
    ByVal statCursor As SQLITE_C_INT, _
    ByVal firstRegister As SQLITE_C_INT, _
    ByVal firstTableCursor As SQLITE_C_INT _
)
    If pParse = 0 OrElse pParse->db = 0 OrElse pTable = 0 Then Exit Sub
    Dim db As sqlite3 Ptr = pParse->db
    Dim pVdbe As SqliteVdbe Ptr = sqlite3GetVdbe(pParse)
    If pVdbe = 0 OrElse pTable->eTabType <> TABTYP_NORM Then Exit Sub
    If pTable->zName = 0 Then Exit Sub

    ' SQLite's built-in catalog tables are deliberately left out of ANALYZE.
    If sqlite3_strlike(StrPtr("sqlite\_%"), pTable->zName, _
                       SQLITE_ANALYZE_LIKE_ESCAPE) = 0 Then Exit Sub

    Dim databaseIndex As SQLITE_C_INT = _
        sqlite3SchemaToIndex(db, pTable->pSchema)
    If databaseIndex < 0 OrElse databaseIndex >= db->nDb Then Exit Sub
    If sqlite3AuthCheck(pParse, SQLITE_ANALYZE, pTable->zName, 0, _
                        db->aDb(databaseIndex).zDbSName) <> 0 Then Exit Sub

    sqlite3TableLock(pParse, databaseIndex, pTable->tnum, 0, pTable->zName)
    Dim tableCursor As SQLITE_C_INT = firstTableCursor
    Dim indexCursor As SQLITE_C_INT = firstTableCursor + 1
    If pParse->nTab < indexCursor + 1 Then pParse->nTab = indexCursor + 1
    sqlite3OpenTable(pParse, tableCursor, databaseIndex, pTable, OP_OpenRead)

    Dim newRowidRegister As SQLITE_C_INT = firstRegister
    Dim statRegister As SQLITE_C_INT = newRowidRegister + 1
    Dim changedRegister As SQLITE_C_INT = statRegister + 1
    Dim rowidRegister As SQLITE_C_INT = statRegister + 2
    Dim tempRegister As SQLITE_C_INT = statRegister + 3
    Dim temp2Register As SQLITE_C_INT = statRegister + 4
    Dim tableNameRegister As SQLITE_C_INT = statRegister + 5
    Dim indexNameRegister As SQLITE_C_INT = statRegister + 6
    Dim statValueRegister As SQLITE_C_INT = statRegister + 7
    Dim previousColumnRegister As SQLITE_C_INT = statRegister + 8
    Dim zeroRowAddress As SQLITE_C_INT = -1
    Dim countTableRows As SQLITE_C_INT = 1
#ifdef SQLITE_ENABLE_STAT4
    Dim doStat4RegisterSetup As SQLITE_C_INT = 1
#endif

    sqlite3TouchRegister(pParse, previousColumnRegister)
    sqlite3VdbeLoadString(pVdbe, tableNameRegister, pTable->zName)
    initializeStatFunctionDefinitions()

    Dim pIndex As SqliteIndex Ptr = CPtr(SqliteIndex Ptr, pTable->pIndex)
    While pIndex <> 0
        Dim pNextIndex As SqliteIndex Ptr = pIndex->pNext
        If pOnlyIndex <> 0 AndAlso pOnlyIndex <> pIndex Then
            pIndex = pNextIndex
            Continue While
        End If

        Dim nColumn As SQLITE_C_INT
        Dim nColumnTest As SQLITE_C_INT
        Dim zIndexName As Const ZString Ptr
        Dim isWithoutRowid As SQLITE_C_INT = _
            CInt((pTable->tabFlags And TF_WithoutRowid) <> 0)
        Dim isPrimaryKey As SQLITE_C_INT = _
            CInt((pIndex->flags And SQLITE_INDEX_IDXTYPE_MASK) = _
                 SQLITE_ANALYZE_PRIMARY_KEY_INDEX)

        If pIndex->pPartIdxWhere = 0 Then countTableRows = 0
        If isWithoutRowid <> 0 AndAlso isPrimaryKey <> 0 Then
            nColumn = pIndex->nKeyCol
            zIndexName = pTable->zName
            nColumnTest = nColumn - 1
        Else
            nColumn = pIndex->nColumn
            zIndexName = pIndex->zName
            If (pIndex->flags And SQLITE_INDEX_UNIQ_NOTNULL) <> 0 Then
                nColumnTest = pIndex->nKeyCol - 1
            Else
                nColumnTest = nColumn - 1
            End If
        End If

        If nColumn <= 0 OrElse nColumnTest < 0 OrElse zIndexName = 0 Then
            pIndex = pNextIndex
            Continue While
        End If

        ' Reserve the saved prefix columns and the trailing rowid register.
        sqlite3TouchRegister(pParse, previousColumnRegister + nColumnTest)
        sqlite3VdbeLoadString(pVdbe, indexNameRegister, zIndexName)
        sqlite3VdbeAddOp3(pVdbe, OP_OpenRead, indexCursor, pIndex->tnum, databaseIndex)
        sqlite3VdbeSetP4KeyInfo(pParse, pIndex)
#ifdef SQLITE_ENABLE_EXPLAIN_COMMENTS
        sqlite3VdbeComment(pVdbe, StrPtr("%s"), pIndex->zName)
#endif

        ' stat_init receives column count, key-column count, index row count,
        ' and the optional row-scan limit in four consecutive registers.
        sqlite3VdbeAddOp2(pVdbe, OP_Integer, db->nAnalysisLimit, temp2Register)
        sqlite3VdbeAddOp2(pVdbe, OP_Integer, nColumn, statRegister + 1)
        sqlite3VdbeAddOp2(pVdbe, OP_Integer, pIndex->nKeyCol, rowidRegister)
        ' The SQLITE_Stat4 optimization bit asks OP_Count for its exact count.
        Dim countMode As SQLITE_C_INT = _
            CInt((db->dbOptFlags And SQLITE_ANALYZE_STAT4_OPTIMIZATION) <> 0)
        sqlite3VdbeAddOp3(pVdbe, OP_Count, indexCursor, tempRegister, countMode)
        sqlite3VdbeAddFunctionCall(pParse, 0, statRegister + 1, statRegister, _
                                   4, @statFunctionDefinitions(0), 0)

        Dim endOfScanAddress As SQLITE_C_INT = _
            sqlite3VdbeAddOp1(pVdbe, OP_Rewind, indexCursor)
        sqlite3VdbeAddOp2(pVdbe, OP_Integer, 0, changedRegister)
        Dim nextRowAddress As SQLITE_C_INT = sqlite3VdbeCurrentAddr(pVdbe)

        If nColumnTest > 0 Then
            Dim endDistinctLabel As SQLITE_C_INT = sqlite3VdbeMakeLabel(pParse)
            Dim addressBytes As sqlite3_uint64 = _
                Cast(sqlite3_uint64, nColumnTest) * SizeOf(SQLITE_C_INT)
            Dim aChangeAddresses As SQLITE_C_INT Ptr = _
                CPtr(SQLITE_C_INT Ptr, sqlite3DbMallocRawNN(db, addressBytes))
            If aChangeAddresses = 0 Then
                pIndex = pNextIndex
                Continue While
            End If

            sqlite3VdbeAddOp0(pVdbe, OP_Goto)
            nextRowAddress = sqlite3VdbeCurrentAddr(pVdbe)
            If nColumnTest = 1 AndAlso pIndex->nKeyCol = 1 AndAlso pIndex->onError <> 0 Then
                sqlite3VdbeAddOp2(pVdbe, OP_NotNull, previousColumnRegister, endDistinctLabel)
            End If

            For columnIndex As SQLITE_C_INT = 0 To nColumnTest - 1
                Dim pCollation As Any Ptr = _
                    sqlite3LocateCollSeq(pParse, pIndex->azColl[columnIndex])
                sqlite3VdbeAddOp2(pVdbe, OP_Integer, columnIndex, changedRegister)
                sqlite3VdbeAddOp3(pVdbe, OP_Column, indexCursor, columnIndex, tempRegister)
#ifdef SQLITE_ENABLE_EXPLAIN_COMMENTS
                analyzeVdbeCommentIndexWithColumnName(pVdbe, pIndex, columnIndex)
#endif
                aChangeAddresses[columnIndex] = sqlite3VdbeAddOp4( _
                    pVdbe, OP_Ne, tempRegister, 0, previousColumnRegister + columnIndex, _
                    CPtr(Const ZString Ptr, pCollation), P4_COLLSEQ)
                sqlite3VdbeChangeP5(pVdbe, SQLITE_NULLEQ)
            Next

            sqlite3VdbeAddOp2(pVdbe, OP_Integer, nColumnTest, changedRegister)
            sqlite3VdbeGoto(pVdbe, endDistinctLabel)
            sqlite3VdbeJumpHere(pVdbe, nextRowAddress - 1)
            For columnIndex As SQLITE_C_INT = 0 To nColumnTest - 1
                sqlite3VdbeJumpHere(pVdbe, aChangeAddresses[columnIndex])
                sqlite3VdbeAddOp3(pVdbe, OP_Column, indexCursor, columnIndex, _
                                  previousColumnRegister + columnIndex)
#ifdef SQLITE_ENABLE_EXPLAIN_COMMENTS
                analyzeVdbeCommentIndexWithColumnName(pVdbe, pIndex, columnIndex)
#endif
            Next
            sqlite3VdbeResolveLabel(pVdbe, endDistinctLabel)
            sqlite3DbFree(db, aChangeAddresses)
        End If

#ifdef SQLITE_ENABLE_STAT4
        ' Supply the rightmost index field as the rowid or WITHOUT ROWID key.
        sqlite3VdbeAddOp3(pVdbe, OP_Column, indexCursor, nColumn - 1, rowidRegister)
#ifdef SQLITE_ENABLE_EXPLAIN_COMMENTS
        analyzeVdbeCommentIndexWithColumnName(pVdbe, pIndex, nColumn - 1)
#endif
        sqlite3VdbeAddFunctionCall(pParse, 1, statRegister, tempRegister, _
                                   3, @statFunctionDefinitions(1), 0)
#else
        ' The STAT1 profile stores one average-row estimate for each key prefix.
        sqlite3VdbeAddFunctionCall(pParse, 1, statRegister, tempRegister, _
                                   2, @statFunctionDefinitions(1), 0)
#endif
        If db->nAnalysisLimit <> 0 Then
            Dim nullAddress As SQLITE_C_INT = _
                sqlite3VdbeAddOp1(pVdbe, OP_IsNull, tempRegister)
            Dim limitAddress As SQLITE_C_INT = _
                sqlite3VdbeAddOp1(pVdbe, OP_If, tempRegister)
            ' The final operand counts the single-column prefix used by SeekGT.
            Dim seekAddress As SQLITE_C_INT = sqlite3VdbeAddOp4Int( _
                pVdbe, OP_SeekGT, indexCursor, 0, previousColumnRegister, 1)
            sqlite3VdbeJumpHere(pVdbe, nullAddress)
            sqlite3VdbeAddOp2(pVdbe, OP_Next, indexCursor, nextRowAddress)
            sqlite3VdbeJumpHere(pVdbe, limitAddress)
            sqlite3VdbeJumpHere(pVdbe, seekAddress)
        Else
            sqlite3VdbeAddOp2(pVdbe, OP_Next, indexCursor, nextRowAddress)
        End If

        If pIndex->pPartIdxWhere <> 0 Then
            sqlite3VdbeJumpHere(pVdbe, endOfScanAddress)
            endOfScanAddress = 0
        End If
        callStatGet(pParse, statRegister, SQLITE_ANALYZE_STAT_GET_STAT1, statValueRegister)
        ' All three sqlite_stat1 columns are stored with TEXT affinity.
        sqlite3VdbeAddOp4(pVdbe, OP_MakeRecord, tableNameRegister, _
                          SQLITE_ANALYZE_STAT_COLUMN_COUNT, _
                          tempRegister, StrPtr("BBB"), 0)
        sqlite3VdbeAddOp2(pVdbe, OP_NewRowid, statCursor, newRowidRegister)
        sqlite3VdbeAddOp3(pVdbe, OP_Insert, statCursor, tempRegister, newRowidRegister)
        sqlite3VdbeChangeP5(pVdbe, OPFLAG_APPEND)

#ifdef SQLITE_ENABLE_STAT4
        If (db->dbOptFlags And SQLITE_ANALYZE_STAT4_OPTIMIZATION) <> 0 AndAlso _
           db->nAnalysisLimit = 0 Then
            Dim eqRegister As SQLITE_C_INT = statValueRegister
            Dim lessRegister As SQLITE_C_INT = statValueRegister + 1
            Dim distinctLessRegister As SQLITE_C_INT = statValueRegister + 2
            Dim sampleRegister As SQLITE_C_INT = statValueRegister + 3
            Dim columnRegister As SQLITE_C_INT = statValueRegister + 4
            Dim sampleRowidRegister As SQLITE_C_INT = columnRegister + nColumn

            If endOfScanAddress = 0 Then
                sqlite3VdbeAddOp2(pVdbe, OP_Cast, statValueRegister, SQLITE_AFF_INTEGER)
                endOfScanAddress = sqlite3VdbeAddOp1(pVdbe, OP_IfNot, statValueRegister)
            End If

            If doStat4RegisterSetup <> 0 Then
                Dim maximumIndexColumns As SQLITE_C_INT = nColumn
                Dim pOtherIndex As SqliteIndex Ptr = _
                    CPtr(SqliteIndex Ptr, pTable->pIndex)
                While pOtherIndex <> 0
                    Dim otherIndexColumns As SQLITE_C_INT
                    If isWithoutRowid <> 0 AndAlso _
                       (pOtherIndex->flags And SQLITE_INDEX_IDXTYPE_MASK) = _
                           SQLITE_ANALYZE_PRIMARY_KEY_INDEX Then
                        otherIndexColumns = pOtherIndex->nKeyCol
                    Else
                        otherIndexColumns = pOtherIndex->nColumn
                    End If
                    If otherIndexColumns > maximumIndexColumns Then _
                        maximumIndexColumns = otherIndexColumns
                    pOtherIndex = pOtherIndex->pNext
                Wend
                sqlite3TouchRegister(pParse, columnRegister + maximumIndexColumns)
                doStat4RegisterSetup = 0
                sqlite3ClearTempRegCache(pParse)
            End If

            Dim sampleLoopAddress As SQLITE_C_INT = sqlite3VdbeCurrentAddr(pVdbe)
            callStatGet(pParse, statRegister, SQLITE_ANALYZE_STAT_GET_ROWID, _
                        sampleRowidRegister)
            Dim noMoreSamplesAddress As SQLITE_C_INT = _
                sqlite3VdbeAddOp1(pVdbe, OP_IsNull, sampleRowidRegister)
            Dim noRowid As SQLITE_C_INT
            If isWithoutRowid <> 0 Then
                noRowid = OP_NotFound
            Else
                noRowid = OP_NotExists
            End If
            callStatGet(pParse, statRegister, SQLITE_ANALYZE_STAT_GET_NEQ, eqRegister)
            callStatGet(pParse, statRegister, SQLITE_ANALYZE_STAT_GET_NLT, lessRegister)
            callStatGet(pParse, statRegister, SQLITE_ANALYZE_STAT_GET_NDLT, distinctLessRegister)
            sqlite3VdbeAddOp4Int(pVdbe, noRowid, tableCursor, sampleLoopAddress, _
                                 sampleRowidRegister, 0)

            For columnIndex As SQLITE_C_INT = 0 To nColumn - 1
                sqlite3ExprCodeLoadIndexColumn(pParse, pIndex, tableCursor, _
                                                columnIndex, columnRegister + columnIndex)
            Next
            sqlite3VdbeAddOp3(pVdbe, OP_MakeRecord, columnRegister, nColumn, sampleRegister)
            sqlite3VdbeAddOp3(pVdbe, OP_MakeRecord, tableNameRegister, 6, tempRegister)
            sqlite3VdbeAddOp2(pVdbe, OP_NewRowid, statCursor + 1, newRowidRegister)
            sqlite3VdbeAddOp3(pVdbe, OP_Insert, statCursor + 1, tempRegister, newRowidRegister)
            sqlite3VdbeAddOp2(pVdbe, OP_Goto, 1, sampleLoopAddress)
            sqlite3VdbeJumpHere(pVdbe, noMoreSamplesAddress)
        End If
#endif
        If endOfScanAddress <> 0 Then sqlite3VdbeJumpHere(pVdbe, endOfScanAddress)
        pIndex = pNextIndex
    Wend

    If pOnlyIndex = 0 AndAlso countTableRows <> 0 Then
        sqlite3VdbeAddOp2(pVdbe, OP_Count, tableCursor, statValueRegister)
        zeroRowAddress = sqlite3VdbeAddOp1(pVdbe, OP_IfNot, statValueRegister)
        sqlite3VdbeAddOp2(pVdbe, OP_Null, 0, indexNameRegister)
        ' Keep the table summary's column affinities aligned with sqlite_stat1.
        sqlite3VdbeAddOp4(pVdbe, OP_MakeRecord, tableNameRegister, _
                          SQLITE_ANALYZE_STAT_COLUMN_COUNT, _
                          tempRegister, StrPtr("BBB"), 0)
        sqlite3VdbeAddOp2(pVdbe, OP_NewRowid, statCursor, newRowidRegister)
        sqlite3VdbeAddOp3(pVdbe, OP_Insert, statCursor, tempRegister, newRowidRegister)
        sqlite3VdbeChangeP5(pVdbe, OPFLAG_APPEND)
        sqlite3VdbeJumpHere(pVdbe, zeroRowAddress)
    End If
End Sub

/' ------------------------------------------------------------------------- '/
/' ANALYZE statement code generation                                        '/
/' ------------------------------------------------------------------------- '/

Private Sub analyzeDatabase CDecl Alias "analyzeDatabase" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal databaseIndex As SQLITE_C_INT _
)
    If pParse = 0 OrElse pParse->db = 0 Then Exit Sub
    Dim db As sqlite3 Ptr = pParse->db
    If databaseIndex < 0 OrElse databaseIndex >= db->nDb Then Exit Sub
    Dim pSchema As SqliteSchema Ptr = db->aDb(databaseIndex).pSchema
    If pSchema = 0 Then Exit Sub

    sqlite3BeginWriteOperation(pParse, 0, databaseIndex)
    Dim firstStatCursor As SQLITE_C_INT = pParse->nTab
    pParse->nTab += 3
    openStatTable(pParse, databaseIndex, firstStatCursor, 0, 0)

    Dim firstRegister As SQLITE_C_INT = pParse->nMem + 1
    Dim firstTableCursor As SQLITE_C_INT = pParse->nTab
    Dim pElement As HashElem Ptr = pSchema->tblHash.first
    While pElement <> 0
        Dim pTable As SqliteTable Ptr = CPtr(SqliteTable Ptr, pElement->data)
        analyzeOneTable(pParse, pTable, 0, firstStatCursor, _
                        firstRegister, firstTableCursor)
        pElement = pElement->next
    Wend
    loadAnalysis(pParse, databaseIndex)
End Sub

Private Sub analyzeTable CDecl Alias "analyzeTable" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pTable As SqliteTable Ptr, _
    ByVal pOnlyIndex As SqliteIndex Ptr _
)
    If pParse = 0 OrElse pParse->db = 0 OrElse pTable = 0 Then Exit Sub
    Dim db As sqlite3 Ptr = pParse->db
    Dim databaseIndex As SQLITE_C_INT = _
        sqlite3SchemaToIndex(db, pTable->pSchema)
    If databaseIndex < 0 OrElse databaseIndex >= db->nDb Then Exit Sub

    sqlite3BeginWriteOperation(pParse, 0, databaseIndex)
    Dim firstStatCursor As SQLITE_C_INT = pParse->nTab
    pParse->nTab += 3
    If pOnlyIndex <> 0 Then
        openStatTable(pParse, databaseIndex, firstStatCursor, _
                      pOnlyIndex->zName, StrPtr(!"idx"))
    Else
        openStatTable(pParse, databaseIndex, firstStatCursor, _
                      pTable->zName, StrPtr(!"tbl"))
    End If
    analyzeOneTable(pParse, pTable, pOnlyIndex, firstStatCursor, _
                    pParse->nMem + 1, pParse->nTab)
    loadAnalysis(pParse, databaseIndex)
End Sub

Sub sqlite3Analyze CDecl Alias "sqlite3Analyze" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pName1 As sqlite3ParserToken Ptr, _
    ByVal pName2 As sqlite3ParserToken Ptr _
)
    If pParse = 0 OrElse pParse->db = 0 Then Exit Sub
    Dim db As sqlite3 Ptr = pParse->db
    If sqlite3ReadSchema(pParse) <> SQLITE_OK Then Exit Sub

    If pName1 = 0 Then
        ' ANALYZE with no names visits every attached schema except TEMP.
        For databaseIndex As SQLITE_C_INT = 0 To db->nDb - 1
            If databaseIndex <> 1 Then analyzeDatabase(pParse, databaseIndex)
        Next
    Else
        Dim databaseIndex As SQLITE_C_INT = -1
        If pName2 <> 0 AndAlso pName2->n = 0 Then _
            databaseIndex = sqlite3FindDb(db, pName1)

        If databaseIndex >= 0 Then
            analyzeDatabase(pParse, databaseIndex)
        ElseIf pName2 <> 0 Then
            Dim pTableName As sqlite3ParserToken Ptr = 0
            databaseIndex = sqlite3TwoPartName( _
                pParse, pName1, pName2, @pTableName)
            If databaseIndex >= 0 AndAlso databaseIndex < db->nDb AndAlso _
               pTableName <> 0 Then
                Dim zDatabase As Const ZString Ptr = 0
                If pName2->n <> 0 Then _
                    zDatabase = db->aDb(databaseIndex).zDbSName
                Dim zObjectName As ZString Ptr = _
                    sqlite3NameFromToken(db, pTableName)
                If zObjectName <> 0 Then
                    Dim pIndex As SqliteIndex Ptr = _
                        CPtr(SqliteIndex Ptr, _
                             sqlite3FindIndex(db, zObjectName, zDatabase))
                    If pIndex <> 0 Then
                        analyzeTable(pParse, pIndex->pTable, pIndex)
                    Else
                        Dim pTable As SqliteTable Ptr = CPtr(SqliteTable Ptr, _
                            sqlite3LocateTable(pParse, 0, zObjectName, zDatabase))
                        If pTable <> 0 Then analyzeTable(pParse, pTable, 0)
                    End If
                    sqlite3DbFree(db, zObjectName)
                End If
            End If
        End If
    End If

    If db->nSqlExec = 0 Then
        Dim pVdbe As SqliteVdbe Ptr = sqlite3GetVdbe(pParse)
        If pVdbe <> 0 Then sqlite3VdbeAddOp0(pVdbe, OP_Expire)
    End If
End Sub

/' ------------------------------------------------------------------------- '/
/' OP_LoadAnalysis builder                                                   '/
/' ------------------------------------------------------------------------- '/

Sub loadAnalysis CDecl Alias "loadAnalysis" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal iDb As SQLITE_C_INT _
)
    If pParse = 0 Then Exit Sub
    Dim pVdbe As SqliteVdbe Ptr = sqlite3GetVdbe(pParse)
    If pVdbe <> 0 Then sqlite3VdbeAddOp1(pVdbe, OP_LoadAnalysis, iDb)
End Sub

/' end of sqlite3_analyze.bas '/
