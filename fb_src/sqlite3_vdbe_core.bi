/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_core.bi

    Purpose:

        Define the VDBE instruction and statement layouts and core builder calls.

    Responsibilities:

        - Preserve the common VdbeOp, VdbeOpList, and Vdbe field order.
        - Define P4 ownership tags and VDBE construction state values.
        - Declare VDBE creation, deletion, opcode append, and operand patching.
        - Declare the helper that attaches owned KeyInfo metadata to P4.
        - Preserve the heap frame fields used by nested VDBE programs.
        - Preserve normalized-SQL double-quote string tracking state.
        - Expose on-demand VDBE creation for a parser context.
        - Declare the debug check for jumps escaping a generated subroutine.

    This file intentionally does NOT contain:

        - Opcode dispatch, SQL compilation, cursor execution, or complete statement finalization.
'/

#ifndef SQLITE3_FB_VDBE_CORE_BI
#define SQLITE3_FB_VDBE_CORE_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_opcodes.bi"
#include once "sqlite3_result.bi"

#ifndef SQLITE_MAX_VARIABLE_NUMBER
#define SQLITE_MAX_VARIABLE_NUMBER 32766
#endif
#ifndef SQLITE_MAX_ATTACHED
#define SQLITE_MAX_ATTACHED 10
#endif
#ifndef SQLITE_MAX_VDBE_OP
#define SQLITE_MAX_VDBE_OP 250000000
#endif
#ifndef SQLITE_MAX_SCHEMA_RETRY
' Retry a schema invalidation a bounded number of times before returning it.
#define SQLITE_MAX_SCHEMA_RETRY 50
#endif

#define VDBE_INIT_STATE 0
#define VDBE_READY_STATE 1
#define VDBE_RUN_STATE 2
#define VDBE_HALT_STATE 3

' The C Vdbe stores these boolean fields in consecutive bft bitfields.
#define VDBE_EXPLAIN_SHIFT 2
#define VDBE_EXPLAIN_MASK &H0C
#define VDBE_EXPIRED_MASK &H03
#define VDBE_CHANGECOUNT_MASK &H10
#define VDBE_READONLY_MASK &H40
#define VDBE_USES_STMT_JOURNAL_MASK &H20
#define VDBE_BISREADER_MASK &H80
' C's bft sequence places haveEqpOps in bit 8 of the packed VDBE flags.
#define VDBE_HAVE_EQP_OPS_MASK &H100
#define OE_ROLLBACK 1
#define OE_ABORT 2
#define OE_FAIL 3
#define OE_IGNORE 4

' Internal prepare flag used to retain SQL text for statement APIs.
#define SQLITE_PREPARE_SAVESQL &H80

#define P4_NOTUSED 0
#define P4_TRANSIENT 0
#define P4_STATIC -1
#define P4_COLLSEQ -2
#define P4_INT32 -3
#define P4_SUBPROGRAM -4
#define P4_TABLE -5
#define P4_INDEX -6
#define P4_FREE_IF_LE -7
#define P4_DYNAMIC -7
#define P4_FUNCDEF -8
#define P4_KEYINFO -9
#define P4_EXPR -10
#define P4_MEM -11
#define P4_VTAB -12
#define P4_INTARRAY -13
#define P4_FUNCCTX -14
#define P4_TABLEREF -15
#define P4_SUBRTNSIG -16

#define OPFLAG_TYPEOFARG &H80
#define OPFLAG_LENGTHARG &H40
#define OPFLAG_BYTELENARG &HC0
#define OPFLAG_PERMUTE &H01
#define OPFLAG_NCHANGE &H01
#define OPFLAG_BULKCSR &H01
#define OPFLAG_SAVEPOSITION &H02
#define OPFLAG_SEEKEQ &H02
#define OPFLAG_ISUPDATE &H04
#define OPFLAG_APPEND &H08
#define OPFLAG_FORDELETE &H08
#define OPFLAG_USESEEKRESULT &H10
#define OPFLAG_P2ISREG &H10
#define OPFLAG_LASTROWID &H20
#define OPFLAG_ISNOOP &H40
#define OPFLAG_PREFORMAT &H80
#define OPFLAG_NOCHNG &H01
#define SQLITE_JUMPIFNULL &H10
#define SQLITE_NULLEQ &H80

#define COLNAME_NAME 0
#define COLNAME_DECLTYPE 1
#define COLNAME_DATABASE 2
#define COLNAME_TABLE 3
#define COLNAME_COLUMN 4
#ifdef SQLITE_ENABLE_COLUMN_METADATA
#define COLNAME_N 5
#else
#ifdef SQLITE_OMIT_DECLTYPE
#define COLNAME_N 1
#else
#define COLNAME_N 2
#endif
#endif

Type SqliteVdbeSubProgramHeader
    aOp As Any Ptr
    nOp As SQLITE_C_INT
End Type

Union SqliteVdbeP4
    i As SQLITE_C_INT
    p As Any Ptr
    pColl As sqlite3CollSeq Ptr
    pKeyInfo As Any Ptr
    ' Used when p4type is P4_VTAB for virtual-table update operations.
    pVtab As SqliteVtab Ptr
    pProgram As SqliteVdbeSubProgramHeader Ptr
    z As ZString Ptr
End Union

Type SqliteVdbeOp
    opcode As u8
    p4type As Byte
    p5 As u16
    p1 As SQLITE_C_INT
    p2 As SQLITE_C_INT
    p3 As SQLITE_C_INT
    p4 As SqliteVdbeP4
#ifdef SQLITE_ENABLE_EXPLAIN_COMMENTS
    zComment As ZString Ptr
#endif
#ifdef SQLITE_VDBE_COVERAGE
    iSrcLine As u32
#endif
#if defined(SQLITE_ENABLE_STMT_SCANSTATUS) OrElse defined(VDBE_PROFILE)
    nExec As u64
    nCycle As u64
#endif
End Type

Type SqliteVdbeOpList
    opcode As u8
    p1 As Byte
    p2 As Byte
    p3 As Byte
End Type

Type SqliteSubroutineSignature
    selId As SQLITE_C_INT
    bComplete As u8
    zAff As ZString Ptr
    iTable As SQLITE_C_INT
    iAddr As SQLITE_C_INT
    regReturn As SQLITE_C_INT
End Type

Type SqliteVdbeSubProgram
    aOp As SqliteVdbeOp Ptr
    nOp As SQLITE_C_INT
    nMem As SQLITE_C_INT
    nCsr As SQLITE_C_INT
    aOnce As UByte Ptr
    token As Any Ptr
    pNext As Any Ptr
End Type

Type SqliteVdbeAuxData
    iAuxOp As SQLITE_C_INT
    iAuxArg As SQLITE_C_INT
    pAux As Any Ptr
    xDeleteAux As Any Ptr
    pNextAux As Any Ptr
End Type

#ifdef SQLITE_ENABLE_NORMALIZE
' C stores eight bytes after this pointer and extends the allocation as needed.
Type SqliteDblquoteStr
    pNextStr As SqliteDblquoteStr Ptr
    z(0 To 7) As UByte
End Type
#endif

Declare Sub sqlite3VdbeDeleteAuxData CDecl Alias "sqlite3VdbeDeleteAuxData" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal ppAux As SqliteVdbeAuxData Ptr Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal argumentMask As SQLITE_C_INT _
)

' Shared with VDBE auxiliary modules that release owned P4 values.
Declare Sub freeP4( _
    ByVal db As sqlite3 Ptr, _
    ByVal p4Type As SQLITE_C_INT, _
    ByVal p4 As Any Ptr _
)

#ifdef SQLITE_ENABLE_STMT_SCANSTATUS
Type SqliteScanStatus
    addrExplain As SQLITE_C_INT
    aAddrRange(0 To 5) As SQLITE_C_INT
    addrLoop As SQLITE_C_INT
    addrVisit As SQLITE_C_INT
    iSelectID As SQLITE_C_INT
    nEst As Short
    zName As ZString Ptr
End Type
#endif

Type SqliteVdbe
    db As sqlite3 Ptr
    ppVPrev As Any Ptr
    pVNext As Any Ptr
    pParse As Any Ptr
#if SQLITE_MAX_VARIABLE_NUMBER < 32767
    nVar As Short
#else
    nVar As SQLITE_C_INT
#endif
    nMem As SQLITE_C_INT
    nCursor As SQLITE_C_INT
    ' Capacity of apArg for virtual-table filter and update callback arguments.
    nArg As SQLITE_C_INT
    cacheCtr As u32
    pc As SQLITE_C_INT
    rc As SQLITE_C_INT
    nChange As sqlite3_int64
    iStatement As SQLITE_C_INT
    iCurrentTime As sqlite3_int64
    nFkConstraint As sqlite3_int64
    nStmtDefCons As sqlite3_int64
    nStmtDefImmCons As sqlite3_int64
    aMem As SqliteVdbeMem Ptr
    apArg As SqliteVdbeMem Ptr Ptr
    apCsr As Any Ptr Ptr
    aVar As SqliteVdbeMem Ptr
    aOp As SqliteVdbeOp Ptr
    nOp As SQLITE_C_INT
    nOpAlloc As SQLITE_C_INT
    aColName As SqliteVdbeMem Ptr
    pResultRow As SqliteVdbeMem Ptr
    zErrMsg As ZString Ptr
    pVList As Any Ptr
#ifndef SQLITE_OMIT_TRACE
    startTime As sqlite3_int64
#endif
#ifdef SQLITE_DEBUG
    rcApp As SQLITE_C_INT
    nWrite As u32
    napArg As SQLITE_C_INT
#endif
    nResColumn As u16
    nResAlloc As u16
    errorAction As u8
    ' Database index plus one when OP_Destroy moved a root page.
    resetSchemaOnFault As u8
    minWriteFileFormat As u8
    prepFlags As u8
    eVdbeState As u8
    vdbeFlags As u32
#if SQLITE_MAX_ATTACHED > 30
    btreeMask(0 To ((SQLITE_MAX_ATTACHED + 9) \ 8) - 1) As u8
    lockMask(0 To ((SQLITE_MAX_ATTACHED + 9) \ 8) - 1) As u8
#else
    btreeMask As u32
    lockMask As u32
#endif
    aCounter(0 To 8) As u32
    zSql As ZString Ptr
#ifdef SQLITE_ENABLE_NORMALIZE
    zNormSql As ZString Ptr
    pDblStr As SqliteDblquoteStr Ptr
#endif
    pFree As Any Ptr
    pFrame As Any Ptr
    pDelFrame As Any Ptr
    nFrame As SQLITE_C_INT
    expmask As u32
    smimask As u32
    pProgram As Any Ptr
    pAuxData As SqliteVdbeAuxData Ptr
#ifdef SQLITE_ENABLE_STMT_SCANSTATUS
    nScan As SQLITE_C_INT
    aScan As SqliteScanStatus Ptr
#endif
End Type

' A child program frame borrows its arrays from a parent and owns its auxdata.
Type SqliteVdbeFrame
    v As SqliteVdbe Ptr
    pParent As SqliteVdbeFrame Ptr
    aOp As SqliteVdbeOp Ptr
    aMem As SqliteVdbeMem Ptr
    apCsr As Any Ptr Ptr
    aOnce As UByte Ptr
    token As Any Ptr
    lastRowid As sqlite3_int64
    pAuxData As SqliteVdbeAuxData Ptr
#ifdef SQLITE_DEBUG
    iFrameMagic As u32
#endif
    nCursor As SQLITE_C_INT
    pc As SQLITE_C_INT
    nOp As SQLITE_C_INT
    nMem As SQLITE_C_INT
    nChildMem As SQLITE_C_INT
    nChildCsr As SQLITE_C_INT
    nChange As sqlite3_int64
    nDbChange As sqlite3_int64
End Type

#ifdef SQLITE_ENABLE_NORMALIZE
Declare Sub sqlite3VdbeAddDblquoteStr CDecl Alias "sqlite3VdbeAddDblquoteStr" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal zText As Const ZString Ptr _
)
Declare Function sqlite3VdbeUsesDoubleQuotedString CDecl Alias "sqlite3VdbeUsesDoubleQuotedString" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal zText As Const ZString Ptr _
) As SQLITE_C_INT
#endif

#ifndef SQLITE_OMIT_TRACE
Declare Sub vdbeExecTrace CDecl ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pOp As SqliteVdbeOp Ptr _
)
Declare Sub vdbeExecProfileCallback CDecl ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
#endif

#ifdef SQLITE_DEBUG
/' Cursor for visiting the main VDBE program and its P4 subprograms. '/
Type SqliteVdbeOpIter
    pVdbe As SqliteVdbe Ptr
    apSub As SqliteVdbeSubProgram Ptr Ptr
    nSub As SQLITE_C_INT
    iAddr As SQLITE_C_INT
    iSub As SQLITE_C_INT
End Type

Declare Function sqlite3VdbeAssertMayAbort CDecl Alias "sqlite3VdbeAssertMayAbort" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal mayAbort As SQLITE_C_INT _
) As SQLITE_C_INT
#endif

Declare Function sqlite3VdbeParameterIndex CDecl Alias "sqlite3VdbeParameterIndex" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal nameLength As SQLITE_C_INT _
) As SQLITE_C_INT
#ifndef SQLITE_OMIT_TRACE
Declare Function sqlite3VdbeExpandSql CDecl Alias "sqlite3VdbeExpandSql" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal zRawSql As Const ZString Ptr _
) As ZString Ptr
#endif

#ifdef SQLITE_DEBUG
Declare Sub sqlite3VdbeReleaseRegisters CDecl Alias "sqlite3VdbeReleaseRegisters" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal firstRegister As SQLITE_C_INT, _
    ByVal registerCount As SQLITE_C_INT, _
    ByVal preserveMask As u32, _
    ByVal undefineReleased As SQLITE_C_INT _
)
Declare Sub sqlite3VdbeAssertAbortable CDecl Alias "sqlite3VdbeAssertAbortable" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
Declare Sub sqlite3VdbeVerifyAbortable CDecl Alias "sqlite3VdbeVerifyAbortable" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal errorAction As SQLITE_C_INT _
)
#ifndef SQLITE_TEST_REALLOC_STRESS
Declare Sub sqlite3VdbeVerifyNoMallocRequired CDecl Alias "sqlite3VdbeVerifyNoMallocRequired" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal additionalOpCount As SQLITE_C_INT _
)
Declare Sub sqlite3VdbeVerifyNoResultRow CDecl Alias "sqlite3VdbeVerifyNoResultRow" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
#endif
#endif

Declare Function sqlite3VdbeGetBoundValue CDecl Alias "sqlite3VdbeGetBoundValue" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal variableNumber As SQLITE_C_INT, _
    ByVal affinity As u8 _
) As SqliteVdbeMem Ptr
Declare Sub sqlite3VdbeReprepareOnBind CDecl Alias "sqlite3VdbeReprepareOnBind" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal variableNumber As SQLITE_C_INT, _
    ByVal reprepareSmallInteger As SQLITE_C_INT _
)

Declare Function sqlite3VdbeAddOp0 CDecl Alias "sqlite3VdbeAddOp0" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal opcode As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3VdbeAddOp1 CDecl Alias "sqlite3VdbeAddOp1" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal p1 As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3VdbeAddOp2 CDecl Alias "sqlite3VdbeAddOp2" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal p1 As SQLITE_C_INT, _
    ByVal p2 As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3VdbeAddOp3 CDecl Alias "sqlite3VdbeAddOp3" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal p1 As SQLITE_C_INT, _
    ByVal p2 As SQLITE_C_INT, _
    ByVal p3 As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3VdbeAddOp4 CDecl Alias "sqlite3VdbeAddOp4" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal p1 As SQLITE_C_INT, _
    ByVal p2 As SQLITE_C_INT, _
    ByVal p3 As SQLITE_C_INT, _
    ByVal zP4 As Const ZString Ptr, _
    ByVal p4Type As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Sub sqlite3VdbeMultiLoad CDecl Alias "sqlite3VdbeMultiLoad" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal firstRegister As SQLITE_C_INT, _
    ByVal typeCodes As Const ZString Ptr, _
    ... _
)
Declare Function sqlite3VdbeAddOp4Int CDecl Alias "sqlite3VdbeAddOp4Int" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal p1 As SQLITE_C_INT, _
    ByVal p2 As SQLITE_C_INT, _
    ByVal p3 As SQLITE_C_INT, _
    ByVal p4 As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3VdbeAddFunctionCall CDecl Alias "sqlite3VdbeAddFunctionCall" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal constantMask As SQLITE_C_INT, _
    ByVal firstArgumentRegister As SQLITE_C_INT, _
    ByVal outputRegister As SQLITE_C_INT, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pFunction As Const SqliteFuncDef Ptr, _
    ByVal callContext As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3VdbeAddOpList CDecl Alias "sqlite3VdbeAddOpList" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal opCount As SQLITE_C_INT, _
    ByVal pOpList As Const SqliteVdbeOpList Ptr, _
    ByVal firstLine As SQLITE_C_INT _
) As SqliteVdbeOp Ptr
Declare Sub sqlite3VdbeUsesBtree CDecl Alias "sqlite3VdbeUsesBtree" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal databaseIndex As SQLITE_C_INT _
)
Declare Sub sqlite3VdbeJumpHereOrPopInst CDecl Alias "sqlite3VdbeJumpHereOrPopInst" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal address As SQLITE_C_INT _
)
Declare Sub sqlite3VdbeCountChanges CDecl Alias "sqlite3VdbeCountChanges" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
Declare Sub sqlite3ExpirePreparedStatements CDecl Alias "sqlite3ExpirePreparedStatements" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal expirationCode As SQLITE_C_INT _
)
Declare Function sqlite3VdbeHasSubProgram CDecl Alias "sqlite3VdbeHasSubProgram" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3VdbeResetStepResult CDecl Alias "sqlite3VdbeResetStepResult" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
Declare Function sqlite3VdbeDb CDecl Alias "sqlite3VdbeDb" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As sqlite3 Ptr
Declare Function sqlite3VdbePrepareFlags CDecl Alias "sqlite3VdbePrepareFlags" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As u8
Declare Sub sqlite3VdbeAddParseSchemaOp CDecl Alias "sqlite3VdbeAddParseSchemaOp" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal databaseIndex As SQLITE_C_INT, _
    ByVal zWhere As ZString Ptr, _
    ByVal p5 As u16 _
)
Declare Sub sqlite3VdbeEndCoroutine CDecl Alias "sqlite3VdbeEndCoroutine" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal yieldRegister As SQLITE_C_INT _
)
Declare Sub sqlite3MayAbort CDecl Alias "sqlite3MayAbort" ( _
    ByVal pParse As Any Ptr _
)
Declare Function sqlite3VdbeCreate CDecl Alias "sqlite3VdbeCreate" ( _
    ByVal pParse As Any Ptr _
) As Any Ptr
Declare Function sqlite3GetVdbe CDecl Alias "sqlite3GetVdbe" ( _
    ByVal pParse As SqliteParseContext Ptr _
) As SqliteVdbe Ptr
Declare Sub sqlite3VdbeRewind CDecl Alias "sqlite3VdbeRewind" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
Declare Sub sqlite3VdbeMakeReady CDecl Alias "sqlite3VdbeMakeReady" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pParse As Any Ptr _
)
Declare Function sqlite3VdbeExec CDecl Alias "sqlite3VdbeExec" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT
#ifndef SQLITE_OMIT_EXPLAIN
Declare Function sqlite3VdbeList CDecl Alias "sqlite3VdbeList" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT
#endif
Declare Function sqlite3VdbeHalt CDecl Alias "sqlite3VdbeHalt" ( _
    ByVal pVdbe As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3VdbeExecResetCleanup CDecl Alias "sqlite3VdbeExecResetCleanup" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
Declare Function sqlite3VdbeReset CDecl Alias "sqlite3VdbeReset" ( _
    ByVal pVdbe As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3VdbeError CDecl Alias "sqlite3VdbeError" ( _
    ByVal pVdbe As Any Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Function sqlite3VdbeFinalize CDecl Alias "sqlite3VdbeFinalize" ( _
    ByVal pVdbe As Any Ptr _
) As SQLITE_C_INT
#ifndef SQLITE_OMIT_FOREIGN_KEY
Declare Function sqlite3VdbeCheckFkImmediate CDecl Alias "sqlite3VdbeCheckFkImmediate" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeCheckFkDeferred CDecl Alias "sqlite3VdbeCheckFkDeferred" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT
#endif
Declare Function sqlite3VdbeParser CDecl Alias "sqlite3VdbeParser" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As Any Ptr
Declare Sub sqlite3VdbeSetSql CDecl Alias "sqlite3VdbeSetSql" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal zSql As Const ZString Ptr, _
    ByVal nSql As SQLITE_C_INT, _
    ByVal prepFlags As u8 _
)
#ifdef SQLITE_ENABLE_EXPLAIN_COMMENTS
Declare Sub sqlite3VdbeComment CDecl Alias "sqlite3VdbeComment" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Sub sqlite3VdbeNoopComment CDecl Alias "sqlite3VdbeNoopComment" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
#endif
#ifdef SQLITE_DEBUG
Declare Sub sqlite3VdbeNoJumpsOutsideSubrtn CDecl Alias "sqlite3VdbeNoJumpsOutsideSubrtn" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal firstOpcode As SQLITE_C_INT, _
    ByVal lastOpcode As SQLITE_C_INT, _
    ByVal returnRegister As SQLITE_C_INT _
)
Declare Sub sqlite3VdbePrintSql CDecl Alias "sqlite3VdbePrintSql" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
Declare Sub sqlite3VdbeRegisterDump CDecl Alias "sqlite3VdbeRegisterDump" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
Declare Sub sqlite3PrintMem CDecl Alias "sqlite3PrintMem" ( _
    ByVal pMem As SqliteVdbeMem Ptr _
)
#endif
Declare Function sqlite3VdbeAddInt64 CDecl Alias "sqlite3VdbeAddInt64" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal destinationRegister As SQLITE_C_INT, _
    ByVal value As sqlite3_int64 _
) As SQLITE_C_INT
Declare Function sqlite3VdbeAddDouble CDecl Alias "sqlite3VdbeAddDouble" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal destinationRegister As SQLITE_C_INT, _
    ByVal value As Double _
) As SQLITE_C_INT
Declare Function sqlite3VdbeGoto CDecl Alias "sqlite3VdbeGoto" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal destinationAddress As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3VdbeLoadString CDecl Alias "sqlite3VdbeLoadString" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal destinationRegister As SQLITE_C_INT, _
    ByVal zText As Const ZString Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3VdbeDelete CDecl Alias "sqlite3VdbeDelete" ( _
    ByVal pVdbe As Any Ptr _
)
Declare Sub sqlite3VdbeLinkSubProgram CDecl Alias "sqlite3VdbeLinkSubProgram" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pSubProgram As SqliteVdbeSubProgram Ptr _
)
Declare Function sqlite3VdbeTakeOpArray CDecl Alias "sqlite3VdbeTakeOpArray" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pnOp As SQLITE_C_INT Ptr, _
    ByVal pnMaxVtabArgs As SQLITE_C_INT Ptr _
) As SqliteVdbeOp Ptr
Declare Function sqlite3VdbeCurrentAddr CDecl Alias "sqlite3VdbeCurrentAddr" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT
#ifdef SQLITE_DEBUG
Declare Sub sqlite3VdbePrintOp CDecl Alias "sqlite3VdbePrintOp" ( _
    ByVal pOutput As Any Ptr, _
    ByVal programCounter As SQLITE_C_INT, _
    ByVal pOpcode As SqliteVdbeOp Ptr _
)
#endif
Declare Function sqlite3VdbeGetOp CDecl Alias "sqlite3VdbeGetOp" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal address As SQLITE_C_INT _
) As SqliteVdbeOp Ptr
Declare Function sqlite3VdbeGetLastOp CDecl Alias "sqlite3VdbeGetLastOp" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SqliteVdbeOp Ptr
Declare Function sqlite3VdbeExplainText CDecl Alias "sqlite3VdbeExplainText" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal bPush As UByte, _
    ByVal zFormat As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeExplainInteger CDecl Alias "sqlite3VdbeExplainInteger" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal bPush As UByte, _
    ByVal zFormat As Const ZString Ptr, _
    ByVal value As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3VdbeExplainString CDecl Alias "sqlite3VdbeExplainString" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal bPush As UByte, _
    ByVal zFormat As Const ZString Ptr, _
    ByVal value As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeExplainStringInteger CDecl Alias "sqlite3VdbeExplainStringInteger" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal bPush As UByte, _
    ByVal zFormat As Const ZString Ptr, _
    ByVal stringValue As Const ZString Ptr, _
    ByVal integerValue As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3VdbeExplainIntegerString CDecl Alias "sqlite3VdbeExplainIntegerString" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal bPush As UByte, _
    ByVal zFormat As Const ZString Ptr, _
    ByVal integerValue As SQLITE_C_INT, _
    ByVal stringValue As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeExplainStrings2 CDecl Alias "sqlite3VdbeExplainStrings2" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal bPush As UByte, _
    ByVal zFormat As Const ZString Ptr, _
    ByVal value0 As Const ZString Ptr, _
    ByVal value1 As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeExplainStrings3 CDecl Alias "sqlite3VdbeExplainStrings3" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal bPush As UByte, _
    ByVal zFormat As Const ZString Ptr, _
    ByVal value0 As Const ZString Ptr, _
    ByVal value1 As Const ZString Ptr, _
    ByVal value2 As Const ZString Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3VdbeChangeOpcode CDecl Alias "sqlite3VdbeChangeOpcode" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal address As SQLITE_C_INT, _
    ByVal opcode As u8 _
)
Declare Sub sqlite3VdbeChangeP1 CDecl Alias "sqlite3VdbeChangeP1" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal address As SQLITE_C_INT, _
    ByVal value As SQLITE_C_INT _
)
Declare Sub sqlite3VdbeChangeP2 CDecl Alias "sqlite3VdbeChangeP2" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal address As SQLITE_C_INT, _
    ByVal value As SQLITE_C_INT _
)
Declare Sub sqlite3VdbeChangeP3 CDecl Alias "sqlite3VdbeChangeP3" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal address As SQLITE_C_INT, _
    ByVal value As SQLITE_C_INT _
)
Declare Sub sqlite3VdbeChangeP4 CDecl Alias "sqlite3VdbeChangeP4" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal address As SQLITE_C_INT, _
    ByVal zP4 As Const ZString Ptr, _
    ByVal p4Type As SQLITE_C_INT _
)
Declare Sub sqlite3VdbeAppendP4 CDecl Alias "sqlite3VdbeAppendP4" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pP4 As Any Ptr, _
    ByVal p4Type As SQLITE_C_INT _
)
' Attach Index-derived KeyInfo to the most recently added opcode's P4 field.
Declare Sub sqlite3VdbeSetP4KeyInfo CDecl Alias "sqlite3VdbeSetP4KeyInfo" ( _
    ByVal parseArgument As Any Ptr, _
    ByVal indexArgument As Any Ptr _
)
Declare Sub sqlite3VdbeChangeP5 CDecl Alias "sqlite3VdbeChangeP5" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal value As u16 _
)
Declare Sub sqlite3VdbeSetNumCols CDecl Alias "sqlite3VdbeSetNumCols" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal resultColumnCount As SQLITE_C_INT _
)
Declare Function sqlite3VdbeSetColName CDecl Alias "sqlite3VdbeSetColName" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal columnIndex As SQLITE_C_INT, _
    ByVal nameType As SQLITE_C_INT, _
    ByVal zName As Const ZString Ptr, _
    ByVal xDestructor As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3VdbeTypeofColumn CDecl Alias "sqlite3VdbeTypeofColumn" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal destinationRegister As SQLITE_C_INT _
)
Declare Function sqlite3VdbeDeletePriorOpcode CDecl Alias "sqlite3VdbeDeletePriorOpcode" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal opcode As u8 _
) As SQLITE_C_INT
Declare Sub sqlite3VdbeJumpHere CDecl Alias "sqlite3VdbeJumpHere" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal address As SQLITE_C_INT _
)
Declare Function sqlite3VdbeMakeLabel CDecl Alias "sqlite3VdbeMakeLabel" ( _
    ByVal pParse As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3VdbeResolveLabel CDecl Alias "sqlite3VdbeResolveLabel" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal label As SQLITE_C_INT _
)
Declare Function sqlite3VdbeResolveP2Labels ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeResolveP2Values CDecl Alias "sqlite3VdbeResolveP2Values" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pMaxVtabArgs As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3VdbeRunOnlyOnce CDecl Alias "sqlite3VdbeRunOnlyOnce" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
Declare Sub sqlite3VdbeReusable CDecl Alias "sqlite3VdbeReusable" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
)
Declare Function sqlite3VdbeChangeToNoop CDecl Alias "sqlite3VdbeChangeToNoop" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal address As SQLITE_C_INT _
) As SQLITE_C_INT

#endif

/' end of sqlite3_vdbe_core.bi '/
