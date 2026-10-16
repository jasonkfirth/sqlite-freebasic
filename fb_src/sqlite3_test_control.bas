/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_test_control.bas

    Purpose:

        Implement SQLite's public test-control dispatcher without moving the
        C test programs into the FreeBASIC source tree.

    Responsibilities:

        - Decode each test-control opcode's C varargs with Cva_List.
        - Update per-connection flags and process-wide test settings.
        - Connect PRNG, fault simulation, Bitvec, VDBE, and date helpers.

    This file intentionally does NOT contain:

        - The test scripts or test-runner implementation.
        - Optional parser-coverage instrumentation that the port does not build.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_debug_assert.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_mutex.bi"
#include once "sqlite3_fault.bi"
#include once "sqlite3_bitvec.bi"
#include once "sqlite3_btree.bi"
#include once "sqlite3_util_numeric.bi"
#include once "sqlite3_fp.bi"

Declare Function sqlite3ConfigIsInitialized CDecl Alias "sqlite3ConfigIsInitialized" () As SQLITE_C_INT
Declare Sub sqlite3ConfigSetTestPrngSeed CDecl Alias "sqlite3ConfigSetTestPrngSeed" (ByVal seed As SQLITE_C_UINT)
Declare Sub sqlite3ConfigSetTestNeverCorrupt CDecl Alias "sqlite3ConfigSetTestNeverCorrupt" (ByVal enabled As SQLITE_C_INT)
Declare Sub sqlite3ConfigSetTestLocaltimeFault CDecl Alias "sqlite3ConfigSetTestLocaltimeFault" (ByVal faultMode As SQLITE_C_INT)
Declare Sub sqlite3ConfigSetTestAltLocaltime CDecl Alias "sqlite3ConfigSetTestAltLocaltime" (ByVal callback As Any Ptr)
Declare Sub sqlite3ConfigSetTestOnceResetThreshold CDecl Alias "sqlite3ConfigSetTestOnceResetThreshold" (ByVal threshold As SQLITE_C_INT)
Declare Sub sqlite3ConfigSetTestJsonSelfcheck CDecl Alias "sqlite3ConfigSetTestJsonSelfcheck" (ByVal enabled As UByte)
Declare Function sqlite3ConfigTestJsonSelfcheck CDecl Alias "sqlite3ConfigTestJsonSelfcheck" () As UByte
Declare Sub sqlite3ConfigSetExtraSchemaChecks CDecl Alias "sqlite3ConfigSetExtraSchemaChecks" (ByVal enabled As SQLITE_C_INT)
Declare Function sqlite3ConfigTestLocaltimeFault CDecl Alias "sqlite3ConfigTestLocaltimeFault" () As SQLITE_C_INT
Declare Function sqlite3ConfigTestAltLocaltime CDecl Alias "sqlite3ConfigTestAltLocaltime" () As Any Ptr
Declare Function sqlite3BitvecBuiltinTest CDecl Alias "sqlite3BitvecBuiltinTest" ( _
    ByVal size As SQLITE_C_INT, _
    ByVal pProgram As SQLITE_C_INT Ptr _
) As SQLITE_C_INT

Declare Sub sqlite3PrngSaveState CDecl Alias "sqlite3PrngSaveState" ()
Declare Sub sqlite3PrngRestoreState CDecl Alias "sqlite3PrngRestoreState" ()
Declare Function sqlite3_randomness CDecl Alias "sqlite3_randomness" ( _
    ByVal amount As SQLITE_C_INT, _
    ByVal pBuffer As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3BenignMallocHooks CDecl Alias "sqlite3BenignMallocHooks" ( _
    ByVal pBeginCallback As Any Ptr, _
    ByVal pEndCallback As Any Ptr _
)
Declare Function sqlite3FindDbName CDecl Alias "sqlite3FindDbName" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3ResetAllSchemasOfConnection CDecl Alias "sqlite3ResetAllSchemasOfConnection" ( _
    ByVal db As sqlite3 Ptr _
)
Declare Sub sqlite3ResultIntReal CDecl Alias "sqlite3ResultIntReal" ( _
    ByVal pContext As Any Ptr _
)

Private Dim Shared sqlite3TestTreeTrace As SQLITE_C_UINT
Private Dim Shared sqlite3TestWhereTrace As SQLITE_C_UINT
Private Dim Shared sqlite3TestVdbeCoverageCallback As Any Ptr
Private Dim Shared sqlite3TestVdbeCoverageArgument As Any Ptr

#ifdef SQLITE_DEBUG
Function sqlite3WhereTraceValue CDecl Alias "sqlite3WhereTraceValue" () As u32 Export
    ' Keep the debug printers on the same value controlled by TRACEFLAGS.
    Return sqlite3TestWhereTrace
End Function
#endif

#if defined(SQLITE_DEBUG)
Private Dim Shared sqlite3TestTuningValues(0 To 5) As sqlite3_int64
#endif

#if defined(__FB_BIGENDIAN__)
#define SQLITE3_TEST_BYTEORDER 4321
#define SQLITE3_TEST_LITTLE_ENDIAN 0
#define SQLITE3_TEST_BIG_ENDIAN 1
#else
#define SQLITE3_TEST_BYTEORDER 1234
#define SQLITE3_TEST_LITTLE_ENDIAN 1
#define SQLITE3_TEST_BIG_ENDIAN 0
#endif

Function sqlite3_test_control CDecl Alias "sqlite3_test_control" ( _
    ByVal op As SQLITE_C_INT, _
    ... _
) As SQLITE_C_INT Export
    Dim rc As SQLITE_C_INT = SQLITE_OK

#ifdef SQLITE_UNTESTABLE
    ' The untestable profile intentionally exposes a no-op API entry point.
    Return rc
#else
    Dim args As Cva_List
    Cva_Start(args, op)

    Select Case op
    Case SQLITE_TESTCTRL_PRNG_SAVE
        sqlite3PrngSaveState()

    Case SQLITE_TESTCTRL_PRNG_RESTORE
        sqlite3PrngRestoreState()

#ifndef SQLITE_OMIT_WSD
    Case SQLITE_TESTCTRL_PRNG_SEED
        Dim seed As SQLITE_C_INT = Cva_Arg(args, SQLITE_C_INT)
        Dim db As sqlite3 Ptr = Cva_Arg(args, sqlite3 Ptr)
        If db <> 0 Then
            If db->aDb(0).pSchema = 0 Then
                rc = SQLITE_MISUSE
            ElseIf db->aDb(0).pSchema->schema_cookie <> 0 Then
                seed = db->aDb(0).pSchema->schema_cookie
            End If
        End If
        If rc = SQLITE_OK Then
            sqlite3ConfigSetTestPrngSeed(CUInt(seed))
            sqlite3_randomness(0, 0)
        End If
#endif

    Case SQLITE_TESTCTRL_FK_NO_ACTION
        Dim db As sqlite3 Ptr = Cva_Arg(args, sqlite3 Ptr)
        Dim enabled As SQLITE_C_INT = Cva_Arg(args, SQLITE_C_INT)
        If db = 0 Then
            rc = SQLITE_MISUSE
        ElseIf enabled <> 0 Then
            db->flags = db->flags Or SQLITE_FkNoAction
        Else
            db->flags = db->flags And Not SQLITE_FkNoAction
        End If

    Case SQLITE_TESTCTRL_BITVEC_TEST
        Dim size As SQLITE_C_INT = Cva_Arg(args, SQLITE_C_INT)
        Dim pProgram As SQLITE_C_INT Ptr = Cva_Arg(args, SQLITE_C_INT Ptr)
        rc = sqlite3BitvecBuiltinTest(size, pProgram)

    Case SQLITE_TESTCTRL_FAULT_INSTALL
        sqlite3FaultSimSetCallback(Cva_Arg(args, Any Ptr))
        rc = sqlite3FaultSim(0)

    Case SQLITE_TESTCTRL_BENIGN_MALLOC_HOOKS
        Dim pBegin As Any Ptr = Cva_Arg(args, Any Ptr)
        Dim pEnd As Any Ptr = Cva_Arg(args, Any Ptr)
        sqlite3BenignMallocHooks(pBegin, pEnd)

    Case SQLITE_TESTCTRL_PENDING_BYTE
        rc = sqlite3PendingByte
#ifndef SQLITE_OMIT_WSD
        Dim newPendingByte As SQLITE_C_UINT = Cva_Arg(args, SQLITE_C_UINT)
        If newPendingByte <> 0 Then sqlite3PendingByte = CInt(newPendingByte)
#endif

    Case SQLITE_TESTCTRL_ASSERT
#ifdef SQLITE_DEBUG
        Dim assertionValue As SQLITE_C_INT = Cva_Arg(args, SQLITE_C_INT)
        If assertionValue = 0 Then _
            sqlite3DebugAssert(StrPtr("SQLITE_TESTCTRL_ASSERT argument is non-zero"))
        rc = assertionValue
#endif

    Case SQLITE_TESTCTRL_ALWAYS
        Dim value As SQLITE_C_INT = Cva_Arg(args, SQLITE_C_INT)
#ifdef SQLITE_DEBUG
        If value = 0 Then _
            sqlite3DebugAssert(StrPtr("SQLITE_TESTCTRL_ALWAYS argument is non-zero"))
#endif
        If value <> 0 Then rc = value

    Case SQLITE_TESTCTRL_BYTEORDER
        rc = SQLITE3_TEST_BYTEORDER * 100 + _
             SQLITE3_TEST_LITTLE_ENDIAN * 10 + SQLITE3_TEST_BIG_ENDIAN

    Case SQLITE_TESTCTRL_OPTIMIZATIONS
        Dim db As sqlite3 Ptr = Cva_Arg(args, sqlite3 Ptr)
        Dim disabledMask As u32 = Cva_Arg(args, u32)
        If db = 0 Then
            rc = SQLITE_MISUSE
        Else
            db->dbOptFlags = disabledMask
        End If

    Case SQLITE_TESTCTRL_GETOPT
        Dim db As sqlite3 Ptr = Cva_Arg(args, sqlite3 Ptr)
        Dim pDisabledMask As SQLITE_C_INT Ptr = Cva_Arg(args, SQLITE_C_INT Ptr)
        If db = 0 OrElse pDisabledMask = 0 Then
            rc = SQLITE_MISUSE
        Else
            pDisabledMask[0] = CInt(db->dbOptFlags)
        End If

    Case SQLITE_TESTCTRL_LOCALTIME_FAULT
        Dim faultMode As SQLITE_C_INT = Cva_Arg(args, SQLITE_C_INT)
        sqlite3ConfigSetTestLocaltimeFault(faultMode)
        If faultMode = 2 Then
            sqlite3ConfigSetTestAltLocaltime(Cva_Arg(args, Any Ptr))
        Else
            sqlite3ConfigSetTestAltLocaltime(0)
        End If

    Case SQLITE_TESTCTRL_INTERNAL_FUNCTIONS
        Dim db As sqlite3 Ptr = Cva_Arg(args, sqlite3 Ptr)
        If db = 0 Then
            rc = SQLITE_MISUSE
        Else
            db->mDbFlags = db->mDbFlags Xor DBFLAG_InternalFunc
        End If

    Case SQLITE_TESTCTRL_NEVER_CORRUPT
        sqlite3ConfigSetTestNeverCorrupt(Cva_Arg(args, SQLITE_C_INT))

    Case SQLITE_TESTCTRL_EXTRA_SCHEMA_CHECKS
        sqlite3ConfigSetExtraSchemaChecks(Cva_Arg(args, SQLITE_C_INT))

    Case SQLITE_TESTCTRL_ONCE_RESET_THRESHOLD
        sqlite3ConfigSetTestOnceResetThreshold(Cva_Arg(args, SQLITE_C_INT))

    Case SQLITE_TESTCTRL_VDBE_COVERAGE
#ifdef SQLITE_VDBE_COVERAGE
        sqlite3TestVdbeCoverageCallback = Cva_Arg(args, Any Ptr)
        sqlite3TestVdbeCoverageArgument = Cva_Arg(args, Any Ptr)
#endif

    Case SQLITE_TESTCTRL_SORTER_MMAP
        Dim db As sqlite3 Ptr = Cva_Arg(args, sqlite3 Ptr)
        Dim maximumBytes As SQLITE_C_INT = Cva_Arg(args, SQLITE_C_INT)
        If db = 0 Then
            rc = SQLITE_MISUSE
        Else
            db->nMaxSorterMmap = maximumBytes
        End If

    Case SQLITE_TESTCTRL_ISINIT
        If sqlite3ConfigIsInitialized() = 0 Then rc = SQLITE_ERROR

    Case SQLITE_TESTCTRL_IMPOSTER
        Dim db As sqlite3 Ptr = Cva_Arg(args, sqlite3 Ptr)
        If db = 0 Then
            rc = SQLITE_MISUSE
        Else
            sqlite3_mutex_enter(db->mutex)
            Dim databaseIndex As SQLITE_C_INT = _
                sqlite3FindDbName(db, Cva_Arg(args, Const ZString Ptr))
            If databaseIndex >= 0 Then
                Dim mode As SQLITE_C_INT = Cva_Arg(args, SQLITE_C_INT)
                db->init.iDb = CByte(databaseIndex)
                db->init.busy = CByte(mode)
                db->init.flags = (db->init.flags And Not &H06) Or _
                                 ((CUInt(mode) And &H03) Shl 1)
                db->init.newTnum = CUInt(Cva_Arg(args, SQLITE_C_INT))
                If db->init.busy = 0 AndAlso db->init.newTnum > 0 Then _
                    sqlite3ResetAllSchemasOfConnection(db)
            End If
            sqlite3_mutex_leave(db->mutex)
        End If

#ifdef YYCOVERAGE
    Case SQLITE_TESTCTRL_PARSER_COVERAGE
        ' The FreeBASIC parser currently has no Lemon state-coverage table.
        Dim pReport As Any Ptr = Cva_Arg(args, Any Ptr)
        If pReport <> 0 Then rc = SQLITE_ERROR
#endif

    Case SQLITE_TESTCTRL_RESULT_INTREAL
        sqlite3ResultIntReal(Cva_Arg(args, Any Ptr))

    Case SQLITE_TESTCTRL_SEEK_COUNT
        Dim db As sqlite3 Ptr = Cva_Arg(args, sqlite3 Ptr)
        Dim pCount As sqlite3_uint64 Ptr = Cva_Arg(args, sqlite3_uint64 Ptr)
        If db = 0 OrElse pCount = 0 Then
            rc = SQLITE_MISUSE
        Else
            pCount[0] = sqlite3BtreeSeekCount(CPtr(Btree Ptr, db->aDb(0).pBt))
        End If

    Case SQLITE_TESTCTRL_TRACEFLAGS
        Dim traceOperation As SQLITE_C_INT = Cva_Arg(args, SQLITE_C_INT)
        Dim pTraceValue As u32 Ptr = Cva_Arg(args, u32 Ptr)
        If pTraceValue = 0 Then
            rc = SQLITE_MISUSE
        Else
            Select Case traceOperation
            Case 0: pTraceValue[0] = sqlite3TestTreeTrace
            Case 1: sqlite3TestTreeTrace = pTraceValue[0]
            Case 2: pTraceValue[0] = sqlite3TestWhereTrace
            Case 3: sqlite3TestWhereTrace = pTraceValue[0]
            End Select
        End If

    Case SQLITE_TESTCTRL_LOGEST
        Dim inputValue As Double = Cva_Arg(args, Double)
        Dim logEstimate As Short = sqlite3LogEstFromDouble(inputValue)
        Dim pLogEstimate As SQLITE_C_INT Ptr = Cva_Arg(args, SQLITE_C_INT Ptr)
        Dim pIntegerValue As sqlite3_uint64 Ptr = Cva_Arg(args, sqlite3_uint64 Ptr)
        Dim pSecondEstimate As SQLITE_C_INT Ptr = Cva_Arg(args, SQLITE_C_INT Ptr)
        If pLogEstimate = 0 OrElse pIntegerValue = 0 OrElse pSecondEstimate = 0 Then
            rc = SQLITE_MISUSE
        Else
            pLogEstimate[0] = logEstimate
            pIntegerValue[0] = sqlite3LogEstToInt(logEstimate)
            pSecondEstimate[0] = sqlite3LogEst(pIntegerValue[0])
        End If

    Case SQLITE_TESTCTRL_ATOF
        Dim zInput As Const ZString Ptr = Cva_Arg(args, Const ZString Ptr)
        Dim pResult As Double Ptr = Cva_Arg(args, Double Ptr)
        rc = sqlite3AtoF(zInput, pResult)

#if defined(SQLITE_DEBUG) AndAlso Not defined(SQLITE_OMIT_WSD)
    Case SQLITE_TESTCTRL_TUNE
        Dim tuneId As SQLITE_C_INT = Cva_Arg(args, SQLITE_C_INT)
        Dim pTuneValue As SQLITE_C_INT Ptr = Cva_Arg(args, SQLITE_C_INT Ptr)
        If pTuneValue = 0 Then
            rc = SQLITE_MISUSE
        ElseIf tuneId > 0 AndAlso tuneId <= UBound(sqlite3TestTuningValues) + 1 Then
            sqlite3TestTuningValues(tuneId - 1) = pTuneValue[0]
        ElseIf tuneId < 0 AndAlso tuneId >= -(UBound(sqlite3TestTuningValues) + 1) Then
            pTuneValue[0] = CInt(sqlite3TestTuningValues(-tuneId - 1))
        Else
            rc = SQLITE_NOTFOUND
        End If

    Case SQLITE_TESTCTRL_JSON_SELFCHECK
        Dim pEnabled As SQLITE_C_INT Ptr = Cva_Arg(args, SQLITE_C_INT Ptr)
        If pEnabled = 0 Then
            rc = SQLITE_MISUSE
        ElseIf pEnabled[0] < 0 Then
            pEnabled[0] = sqlite3ConfigTestJsonSelfcheck()
        Else
            sqlite3ConfigSetTestJsonSelfcheck(CByte(pEnabled[0] And &HFF))
        End If
#endif
    End Select

    Cva_End(args)
    Return rc
#endif
End Function

/' end of sqlite3_test_control.bas '/
