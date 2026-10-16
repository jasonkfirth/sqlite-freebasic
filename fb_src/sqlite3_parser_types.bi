/'
    Project: SQLite FreeBASIC port

    File: sqlite3_parser_types.bi

    Purpose:

        Describe Lemon's parser token, semantic value, and stack layouts.

    Responsibilities:

        - Match the default parser data layout generated from src/parse.y.
        - Keep the opaque Parse context pointer in the Lemon parser state.
        - Track parser acceptance, syntax errors, and stack overflow.
        - Distinguish unexpected tokens from semantic-action failures.
        - Store deferred cleanup callbacks owned by one parse operation.
        - Retain the parse mode used by rename and virtual-table routines.
        - Track rename-token nodes until ALTER TABLE rewriting is complete.
        - Store the fixed context shared by ALTER TABLE rename callbacks.
        - Track the top-level parse and constant-factor permission for VDBE creation.
        - Track the active WITH clause while nested SELECT walks unwind.
        - Track reusable temporary register ranges during code generation.
        - Define the transient trigger context used by RETURNING clauses.
        - Store the shared-cache table locks requested by a parse.
        - Track trigger programs while foreign-key action code is generated.
        - Track whether VDBE result-column names have been generated.
        - Retain the last submitted token for DDL source-text capture.
        - Track active and partial-index expressions used during code generation.
        - Preserve the saved authorization context used around parser checks.

    This file intentionally does NOT contain:

        - Grammar semantic actions or semantic destructors.
'/

#ifndef SQLITE3_FB_PARSER_TYPES_BI
#define SQLITE3_FB_PARSER_TYPES_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_parser_tables.bi"
#include once "sqlite3_parser_token.bi"
#include once "sqlite3_schema_types.bi"

#ifndef SQLITE_MAX_PARSER_DEPTH
#define SQLITE_MAX_PARSER_DEPTH 2500
#endif

#define PARSE_MODE_NORMAL 0
#define PARSE_MODE_DECLARE_VTAB 1
#define PARSE_MODE_RENAME 2
#define PARSE_MODE_UNMAP 3

' SQLite keeps eight reusable single-register temporaries per parse.
#define SQLITE_TEMP_REGISTER_CACHE_SIZE 8

Type sqlite3ParserTrigEvent
    a As SQLITE_C_INT
    b As Any Ptr
End Type

Type sqlite3ParserFrameBound
    eType As SQLITE_C_INT
    pExpr As Any Ptr
End Type

Type sqlite3ParserOnOrUsing
    pOn As Any Ptr
    pUsing As Any Ptr
End Type

Type sqlite3ParserValueMask
    value As SQLITE_C_INT
    mask As SQLITE_C_INT
End Type

Union sqlite3ParserMinor
    yyinit As SQLITE_C_INT
    yy0 As sqlite3ParserToken
    yy14 As Any Ptr
    yy59 As Any Ptr
    yy67 As Any Ptr
    yy122 As Any Ptr
    yy132 As Any Ptr
    yy144 As SQLITE_C_INT
    yy168 As Const UByte Ptr
    yy203 As Any Ptr
    yy211 As Any Ptr
    yy269 As sqlite3ParserOnOrUsing
    yy286 As sqlite3ParserTrigEvent
    yy383 As sqlite3ParserValueMask
    yy391 As u32
    yy427 As Any Ptr
    yy454 As Any Ptr
    yy462 As u8
    yy509 As sqlite3ParserFrameBound
    yy555 As Any Ptr
End Union

Type sqlite3ParserStackEntry
    stateno As UShort
    major As UShort
    minor As sqlite3ParserMinor
End Type

Type sqlite3ParserState
    yytos As sqlite3ParserStackEntry Ptr
    pParse As Any Ptr
    yystackEnd As sqlite3ParserStackEntry Ptr
    yystack As sqlite3ParserStackEntry Ptr
    yystk0(0 To YYSTACKDEPTH - 1) As sqlite3ParserStackEntry
    syntaxErrors As SQLITE_C_INT
    stackOverflow As u8
    accepted As u8
    syntaxFailure As u8
    semanticActionFailure As u8
End Type

' Parse-local index expressions that can be read directly from an index cursor.
Type SqliteIndexedExpr
    pExpr As Any Ptr
    iDataCur As SQLITE_C_INT
    iIdxCur As SQLITE_C_INT
    iIdxCol As SQLITE_C_INT
    bMaybeNullRow As u8
    aff As u8
    pIENext As SqliteIndexedExpr Ptr
#ifdef SQLITE_ENABLE_EXPLAIN_COMMENTS
    zIdxName As Const ZString Ptr
#endif
End Type

Type SqliteParserCleanupCallback As Sub CDecl ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pArgument As Any Ptr _
)

Type SqliteParserCleanup
    pNext As SqliteParserCleanup Ptr
    pPtr As Any Ptr
    xCleanup As SqliteParserCleanupCallback
End Type

Type SqliteParseCreateInfo
    addrCrTab As SQLITE_C_INT
    regRowid As SQLITE_C_INT
    regRoot As SQLITE_C_INT
    constraintName As sqlite3ParserToken
End Type

Type SqliteParseDropInfo
    pReturning As Any Ptr
End Type

' One shared-cache lock request retained until VDBE code generation.
Type SqliteTableLock
    iDb As SQLITE_C_INT
    iTab As SQLITE_C_UINT
    isWriteLock As u8
    zLockName As Const ZString Ptr
End Type

Type SqliteAutoincInfo
    pNext As SqliteAutoincInfo Ptr
    pTab As SqliteTable Ptr
    iDb As SQLITE_C_INT
    regCtr As SQLITE_C_INT
End Type

Type SqliteRenameToken
    p As Any Ptr
    t As sqlite3ParserToken
    pNext As SqliteRenameToken Ptr
End Type

' Rename callbacks share this context through Walker.u.pRename.
Type SqliteRenameContext
    pList As SqliteRenameToken Ptr
    nList As SQLITE_C_INT
    iCol As SQLITE_C_INT
    pTab As SqliteTable Ptr
    zOld As Const ZString Ptr
End Type

Union SqliteParseUnion1
    cr As SqliteParseCreateInfo
    d As SqliteParseDropInfo
End Union

' Syntax-pass state shared by sqlite3RunParser and future SQL compilation.
Type SqliteParseContext
    db As sqlite3 Ptr
    pVdbe As Any Ptr
    nQueryLoop As Short
    ' Nesting depth distinguishes top-level DDL from trigger/view parsing.
    nested As u8
    prepFlags As u8
    disableLookaside As u8
    ' A non-null parent marks nested SQL compilation contexts.
    pToplevel As SqliteParseContext Ptr
    pTriggerTab As SqliteTable Ptr
    pTriggerPrg As SqliteTriggerPrg Ptr
    sNameToken As sqlite3ParserToken
    u1 As SqliteParseUnion1
    pReprepare As Any Ptr
    ' Active WITH clause while nested SELECT callbacks unwind.
    pWith As Any Ptr
    nLabel As SQLITE_C_INT
    nLabelAlloc As SQLITE_C_INT
    aLabel As SQLITE_C_INT Ptr
    pVList As Any Ptr
    nVar As SQLITE_C_INT
    nMem As SQLITE_C_INT
    nTab As SQLITE_C_INT
    nNestSel As SQLITE_C_INT
    nSelect As SQLITE_C_INT
    nHeight As SQLITE_C_INT
    nMaxArg As SQLITE_C_INT
    nProgressSteps As SQLITE_C_INT
    ' Marks parsing of a correlated EXISTS expression.
    bHasExists As u8
    ' RETURNING-trigger state used by name resolution.
    bReturning As u8
    pConstExpr As Any Ptr
    oldmask As u32
    newmask As u32
    mayAbort As u8
    isMultiWrite As u8
    bHasWith As u8
    explain As u8
    ' RIGHT JOIN subroutine nesting state shared with WHERE code generation.
    withinRJSubrtn As u8
    ' Bloom-filter bit for reusable IN-subquery materialization signatures.
    mSubrtnSig As u8
    allowAggregate As u8
    okConstFactor As u8
    hasCompound As SQLITE_C_INT
    writeMask As u32
    cookieMask As u32
    nTableLock As SQLITE_C_INT
    aTableLock As SqliteTableLock Ptr
    addrExplain As SQLITE_C_INT
    pNewTable As Any Ptr
    pNewIndex As Any Ptr
    pNewTrigger As Any Ptr
    pRename As SqliteRenameToken Ptr
    zAuthContext As Const ZString Ptr
    eParseMode As u8
    ' Default ON CONFLICT policy passed to statements inside triggers.
    eOrconf As u8
    ' Current INSERT, UPDATE, or DELETE event while resolving a trigger body.
    eTriggerOp As u8
    ' Avoid emitting duplicate result-column metadata for a prepared SELECT.
    colNamesSet As u8
    ' Suppress foreign-key mismatch diagnostics while DROP TABLE disables triggers.
    disableTriggers As u8
    iPkSortOrder As u8
    nTempReg As u8
    nRangeReg As SQLITE_C_INT
    iRangeReg As SQLITE_C_INT
    aTempReg(0 To SQLITE_TEMP_REGISTER_CACHE_SIZE - 1) As SQLITE_C_INT
    pCleanup As SqliteParserCleanup Ptr
#if defined(SQLITE_DEBUG) OrElse defined(SQLITE_COVERAGE_TEST)
    earlyCleanup As u8
#endif
    rc As SQLITE_C_INT
    nErr As SQLITE_C_INT
    ' Owned parser diagnostic transferred to sqlite3.pErr by prepare.
    zErrMsg As ZString Ptr
    ' Borrowed SQL base pointer used for byte offsets; never written.
    zSql As ZString Ptr
    ' Borrowed input pointer; stored as mutable for C interop but never written.
    zTail As ZString Ptr
    ' Parent parse restored when a nested parse context is reset.
    pOuterParse As SqliteParseContext Ptr
    ' Table cursor currently being expanded while compiling a self-reference.
    iSelfTab As SQLITE_C_INT
    ' AUTOINCREMENT register and table state shared by one top-level parse.
    usesAinc As u8
    pAinc As SqliteAutoincInfo Ptr
#ifndef SQLITE_OMIT_VIRTUALTABLE
    nVtabLock As SQLITE_C_INT
    sArg As sqlite3ParserToken
    apVtabLock As SqliteTable Ptr Ptr
#endif
    ' Force schema-cookie verification after a failed schema operation.
    checkSchema As u8
    ' Last submitted token; DDL helpers use it to retain full CREATE text.
    sLastToken As sqlite3ParserToken
    ' Indexed expressions active during ordinary and partial-index codegen.
    pIdxEpr As SqliteIndexedExpr Ptr
    ' Expressions whose value is guaranteed by a partial-index predicate.
    pIdxPartExpr As SqliteIndexedExpr Ptr
End Type

' Returning owns the transient trigger used to execute a DML RETURNING clause.
Type SqliteReturning
    pParse As SqliteParseContext Ptr
    pReturnEL As Any Ptr
    retTrig As SqliteTrigger
    retTStep As SqliteTriggerStep
    iRetCur As SQLITE_C_INT
    nRetCol As SQLITE_C_INT
    iRetReg As SQLITE_C_INT
    ' C Returning.zName is the fixed 40-byte temporary trigger name.
    zName(0 To 39) As UByte
End Type

' Returning owns the transient trigger used to execute a DML RETURNING clause.
' Saves and restores Parse.zAuthContext around schema authorization checks.
Type SqliteAuthContext
    zAuthContext As Const ZString Ptr
    pParse As SqliteParseContext Ptr
End Type

Declare Sub sqlite3Error CDecl Alias "sqlite3Error" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal errorCode As SQLITE_C_INT _
)
Declare Sub sqlite3ErrorClear CDecl Alias "sqlite3ErrorClear" ( _
    ByVal db As sqlite3 Ptr _
)
Declare Sub sqlite3ErrorWithMsg CDecl Alias "sqlite3ErrorWithMsg" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Sub sqlite3ErrorMsg CDecl Alias "sqlite3ErrorMsg" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Sub sqlite3ProgressCheck CDecl Alias "sqlite3ProgressCheck" ( _
    ByVal pParse As SqliteParseContext Ptr _
)

Type sqlite3ParserMallocProc As Function CDecl (ByVal nByte As sqlite3_uint64) As Any Ptr
Type sqlite3ParserFreeProc As Sub CDecl (ByVal p As Any Ptr)

Declare Sub sqlite3Parser CDecl Alias "sqlite3Parser" ( _
    ByVal pParser As Any Ptr, _
    ByVal majorToken As SQLITE_C_INT, _
    ByVal minorToken As sqlite3ParserToken _
)
Declare Function sqlite3ParserHasError CDecl Alias "sqlite3ParserHasError" ( _
    ByVal pParser As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3ParserWasAccepted CDecl Alias "sqlite3ParserWasAccepted" ( _
    ByVal pParser As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3RunParser CDecl Alias "sqlite3RunParser" ( _
    ByVal pParse As Any Ptr, _
    ByVal zSql As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3ParserAddCleanup CDecl Alias "sqlite3ParserAddCleanup" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal xCleanup As SqliteParserCleanupCallback, _
    ByVal pArgument As Any Ptr _
) As Any Ptr
Declare Sub sqlite3ParserRunCleanup CDecl Alias "sqlite3ParserRunCleanup" ( _
    ByVal pParse As SqliteParseContext Ptr _
)

#endif

/' end of sqlite3_parser_types.bi '/
