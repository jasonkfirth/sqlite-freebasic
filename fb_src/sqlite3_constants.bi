/'
    Project: SQLite FreeBASIC port

    File: sqlite3_constants.bi

    Purpose:

        Collect generated public constants and selected internal constants.

    Responsibilities:

        - Include numeric API constants extracted from src/sqlite.h.in.
        - Define affinity values from src/sqliteInt.h.
        - Define source-default SQL limits and internal allocation limits.
        - Set the target-based default for SQLite's mmap-size limit.
        - Define target-native UTF-16 encoding.

    This file intentionally does NOT contain:

        - Runtime state or executable code.
        - Runtime state or build switches supplied by the caller, such as SQLITE_THREADSAFE.
'/

#ifndef SQLITE3_FB_CONSTANTS_BI
#define SQLITE3_FB_CONSTANTS_BI

#include once "sqlite3_api_constants.bi"

' Match sqliteInt.h's platform default while allowing an explicit build override.
#ifndef SQLITE_MAX_MMAP_SIZE
#if defined(__FB_LINUX__) OrElse defined(__FB_WIN32__) OrElse _
    defined(__FB_DARWIN__) OrElse defined(__FB_SOLARIS__) OrElse _
    defined(__FB_ILLUMOS__) OrElse defined(__FB_FREEBSD__) OrElse _
    defined(__FB_DRAGONFLY__) OrElse defined(__FB_ANDROID__)
#define SQLITE_MAX_MMAP_SIZE &H7FFF0000
#else
#define SQLITE_MAX_MMAP_SIZE 0
#endif
#endif

#ifndef SQLITE_DEFAULT_MMAP_SIZE
#define SQLITE_DEFAULT_MMAP_SIZE 0
#endif

' Internal trace-state bits from src/sqliteInt.h.
#ifndef SQLITE_OMIT_DEPRECATED
#define SQLITE_TRACE_LEGACY &H40
#define SQLITE_TRACE_XPROFILE &H80
#else
#define SQLITE_TRACE_LEGACY 0
#define SQLITE_TRACE_XPROFILE 0
#endif
#define SQLITE_TRACE_NONLEGACY_MASK &H0F

' Connection mDbFlags bit used to suppress AUTOINCREMENT updates during VACUUM.
#define DBFLAG_Vacuum &H0004
#define DBFLAG_VacuumInto &H0008
#define DBFLAG_EncodingFixed &H0040

' Internal column affinities from src/sqliteInt.h. Their consecutive values
' allow SQLite to group numeric affinities with a single comparison.
#define SQLITE_AFF_NONE &H40
#define SQLITE_AFF_BLOB &H41
#define SQLITE_AFF_TEXT &H42
#define SQLITE_AFF_NUMERIC &H43
#define SQLITE_AFF_INTEGER &H44
#define SQLITE_AFF_REAL &H45
#define SQLITE_AFF_FLEXNUM &H46
#define SQLITE_AFF_DEFER &H58
#define SQLITE_AFF_MASK &H47

' Sort order bytes stored in index key information.
#define SQLITE_SO_ASC 0
#define SQLITE_SO_DESC 1
#define SQLITE_SO_UNDEFINED -1

' Internal scalar-function properties from src/sqliteInt.h.
#define SQLITE_FUNC_CONSTANT SQLITE_DETERMINISTIC
#define SQLITE_FUNC_EPHEM &H0010
#define SQLITE_FUNC_NEEDCOLL &H0020
#define SQLITE_FUNC_LENGTH &H0040
#define SQLITE_FUNC_TYPEOF &H0080
#define SQLITE_FUNC_BYTELEN &H00C0
#define SQLITE_FUNC_SLOCHNG &H00002000
#define SQLITE_FUNC_ENCODING_MASK &H0003
#define SQLITE_FUNC_INTERNAL &H00040000

' Conflict-action values from sqliteInt.h. These differ from result codes such as SQLITE_ABORT.
#define OE_None 0
#define OE_Rollback 1
#define OE_Abort 2
#define OE_Fail 3
#define OE_Ignore 4
#define OE_Replace 5
#define OE_Update 6
#define OE_Restrict 7
#define OE_SetNull 8
#define OE_SetDflt 9
#define OE_Cascade 10
#define OE_Default 11

' Public sqlite3_prepare_v3() option bits accepted by src/vdbe.h.
#define SQLITE_PREPARE_MASK &H3F

' Internal database-state flags from src/sqliteInt.h.
#define DBFLAG_PreferBuiltin &H0002
#define DBFLAG_InternalFunc &H0020
#define SQLITE_WriteSchema &H00000001
#define SQLITE_IgnoreChecks &H00000200
#define SQLITE_ReverseOrder &H00001000
#define SQLITE_LegacyFileFmt &H00000002
#define SQLITE_TrustedSchema &H00000080
#define SQLITE_StmtScanStatus &H00000400
#define SQLITE_NoCkptOnClose &H00000800
#define SQLITE_ForeignKeys &H00004000
#define SQLITE_LoadExtension &H00010000
#define SQLITE_EnableTrigger &H00040000
#define SQLITE_Fts3Tokenizer &H00400000
#define SQLITE_Defensive &H10000000
#define SQLITE_TriggerEQP &H01000000
#define SQLITE_ResetDatabase &H02000000
#define SQLITE_LegacyAlter &H04000000
#define SQLITE_NoSchemaError &H08000000
#define SQLITE_DqsDDL &H20000000
#define SQLITE_DqsDML &H40000000
#define SQLITE_EnableView &H80000000ULL
#define SQLITE_CountRows (Cast(sqlite3_uint64, &H00000001) Shl 32)
#define SQLITE_AttachCreate (Cast(sqlite3_uint64, &H00000010) Shl 32)
#define SQLITE_AttachWrite (Cast(sqlite3_uint64, &H00000020) Shl 32)
#define SQLITE_Comments (Cast(sqlite3_uint64, &H00000040) Shl 32)
#define SQLITE_FkNoAction (Cast(sqlite3_uint64, &H00000008ULL) Shl 32)
#define SQLITE_EnableQPSG &H00800000 ' Query Planner Stability Guarantee.
#define SQLITE_ReleaseReg &H00400000 ' Enable debug VDBE register-release validation.
#define SQLITE_DeferFKs &H00080000 ' Defer all foreign-key constraints.

' Schema-state bits from src/sqliteInt.h.
#define DB_SchemaLoaded &H0001
#define DB_UnresetViews &H0002
#define DB_ResetWanted &H0008

' Table property from src/sqliteInt.h.
#define TF_WithoutRowid &H00000080

' Index comparison flags from src/sqliteInt.h.
#define KEYINFO_ORDER_DESC &H01
#define KEYINFO_ORDER_BIGNULL &H02

' FreeBASIC implementation limits used by the allocator and connection context.
#ifndef SQLITE_MAX_ALLOCATION_SIZE
' Leave room for SQLite's size-prefix allocator metadata below signed 32-bit overflow.
#define SQLITE_MAX_ALLOCATION_SIZE 2147483391
#endif

#ifndef SQLITE_MAX_LENGTH
#define SQLITE_MAX_LENGTH 1000000000
#endif

#ifndef SQLITE_MIN_LENGTH
#define SQLITE_MIN_LENGTH 30
#endif
#ifndef SQLITE_MAX_SQL_LENGTH
#define SQLITE_MAX_SQL_LENGTH 1000000000
#endif
#ifndef SQLITE_MAX_COLUMN
#define SQLITE_MAX_COLUMN 2000
#endif
#ifndef SQLITE_MAX_EXPR_DEPTH
#define SQLITE_MAX_EXPR_DEPTH 1000
#endif
#ifndef SQLITE_MAX_PARSER_DEPTH
#define SQLITE_MAX_PARSER_DEPTH 2500
#endif
#ifndef SQLITE_MAX_COMPOUND_SELECT
#define SQLITE_MAX_COMPOUND_SELECT 500
#endif
#ifndef SQLITE_MAX_VDBE_OP
#define SQLITE_MAX_VDBE_OP 250000000
#endif
#ifndef SQLITE_MAX_FUNCTION_ARG
#define SQLITE_MAX_FUNCTION_ARG 1000
#endif
#ifndef SQLITE_MAX_ATTACHED
#define SQLITE_MAX_ATTACHED 10
#endif
' The database-slot count includes main and temp in addition to attached databases.
#ifndef SQLITE_MAX_DB
#define SQLITE_MAX_DB (SQLITE_MAX_ATTACHED + 2)
#endif
#ifndef SQLITE_MAX_LIKE_PATTERN_LENGTH
#define SQLITE_MAX_LIKE_PATTERN_LENGTH 50000
#endif
#ifndef SQLITE_MAX_VARIABLE_NUMBER
#define SQLITE_MAX_VARIABLE_NUMBER 32766
#endif
#ifndef SQLITE_MAX_TRIGGER_DEPTH
#define SQLITE_MAX_TRIGGER_DEPTH 1000
#endif
#if defined(SQLITE_TEMP_STORE)
#if SQLITE_TEMP_STORE = 3
#undef SQLITE_MAX_WORKER_THREADS
#define SQLITE_MAX_WORKER_THREADS 0
#endif
#endif
#if defined(SQLITE_THREADSAFE)
#if SQLITE_THREADSAFE = 0
#undef SQLITE_MAX_WORKER_THREADS
#define SQLITE_MAX_WORKER_THREADS 0
#endif
#endif
#ifndef SQLITE_MAX_WORKER_THREADS
#define SQLITE_MAX_WORKER_THREADS 8
#endif
' sqliteInt.h raises the maximum when the configured default is larger.
#ifndef SQLITE_DEFAULT_WORKER_THREADS
#define SQLITE_DEFAULT_WORKER_THREADS 0
#endif
#if SQLITE_DEFAULT_WORKER_THREADS > SQLITE_MAX_WORKER_THREADS
#undef SQLITE_MAX_WORKER_THREADS
#define SQLITE_MAX_WORKER_THREADS SQLITE_DEFAULT_WORKER_THREADS
#endif
#ifndef SQLITE_SORTER_PMASZ
#define SQLITE_SORTER_PMASZ 250
#endif
#ifndef SQLITE_MAX_SCHEMA
#define SQLITE_MAX_SCHEMA 10000000
#endif
#ifndef SQLITE_MAX_TRIGGER_STEPS
#define SQLITE_MAX_TRIGGER_STEPS 65000
#endif
#define SQLITE_N_LIMIT (SQLITE_LIMIT_TRIGGER_STEPS + 1)

' Default statement-journal memory threshold from src/global.c.
#ifndef SQLITE_STMTJRNL_SPILL
#define SQLITE_STMTJRNL_SPILL (64 * 1024)
#endif

#ifndef SQLITE_MEMDB_DEFAULT_MAXSIZE
#define SQLITE_MEMDB_DEFAULT_MAXSIZE 1073741824
#endif

#ifdef __FB_BIGENDIAN__
#define SQLITE_UTF16NATIVE SQLITE_UTF16BE
#else
#define SQLITE_UTF16NATIVE SQLITE_UTF16LE
#endif

#endif

/' end of sqlite3_constants.bi '/
