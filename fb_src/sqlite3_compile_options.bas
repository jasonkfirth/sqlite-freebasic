/'
    Project: SQLite FreeBASIC port

    File: sqlite3_compile_options.bas

    Purpose:

        Report the compile-time options used by this FreeBASIC library.

    Responsibilities:

        - Preserve a stable, alphabetically ordered compile-option list.
        - Match option names case-insensitively with the optional SQLITE_ prefix.
        - Report the active thread-safety and temporary-store profiles.

    This file intentionally does NOT contain:

        - Runtime PRAGMA values or options selected through sqlite3_config().
        - Compiler-specific C options that do not apply to the FreeBASIC build.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"

#ifndef SQLITE_THREADSAFE
#define SQLITE_THREADSAFE 1
#endif
#ifndef SQLITE_TEMP_STORE
#define SQLITE_TEMP_STORE 1
#endif

#ifdef SQLITE_ENABLE_URI_00_ERROR
#define SQLITE_COMPILEOPTION_COUNT 38
#define SQLITE_COMPILEOPTION_URI_EXTRA @sqlite3CompileOptionNames(43),
#else
#define SQLITE_COMPILEOPTION_COUNT 37
#define SQLITE_COMPILEOPTION_URI_EXTRA
#endif

' Keep the text separate from the pointer table so every returned name is stable.
Dim Shared As Const ZString * 40 sqlite3CompileOptionNames(0 To 43) = _
    { _
        "COMPILER=FreeBASIC", _
        "DEFAULT_AUTOVACUUM", _
        "DEFAULT_CACHE_SIZE=-2000", _
        "DEFAULT_FILE_FORMAT=4", _
        "DEFAULT_JOURNAL_SIZE_LIMIT=-1", _
        "DEFAULT_MMAP_SIZE=0", _
        "DEFAULT_PAGE_SIZE=4096", _
        "DEFAULT_PCACHE_INITSZ=20", _
        "DEFAULT_RECURSIVE_TRIGGERS", _
        "DEFAULT_SECTOR_SIZE=4096", _
        "DEFAULT_SYNCHRONOUS=2", _
        "DEFAULT_WAL_AUTOCHECKPOINT=1000", _
        "DEFAULT_WAL_SYNCHRONOUS=2", _
        "DEFAULT_WORKER_THREADS=0", _
        "DIRECT_OVERFLOW_READ", _
        "MALLOC_SOFT_LIMIT=1024", _
        "MAX_ATTACHED=10", _
        "MAX_COLUMN=2000", _
        "MAX_COMPOUND_SELECT=500", _
        "MAX_DEFAULT_PAGE_SIZE=8192", _
        "MAX_EXPR_DEPTH=1000", _
        "MAX_FUNCTION_ARG=1000", _
        "MAX_LENGTH=1000000000", _
        "MAX_LIKE_PATTERN_LENGTH=50000", _
        "MAX_MMAP_SIZE=0x7fff0000", _
        "MAX_PAGE_COUNT=0xfffffffe", _
        "MAX_PAGE_SIZE=65536", _
        "MAX_SCHEMA=10000000", _
        "MAX_SQL_LENGTH=1000000000", _
        "MAX_TRIGGER_DEPTH=1000", _
        "MAX_VARIABLE_NUMBER=32766", _
        "MAX_VDBE_OP=250000000", _
        "MAX_WORKER_THREADS=8", _
        "MUTEX_NOOP", _
        "MUTEX_PTHREADS", _
        "SYSTEM_MALLOC", _
        "TEMP_STORE=0", _
        "TEMP_STORE=1", _
        "TEMP_STORE=2", _
        "TEMP_STORE=3", _
        "THREADSAFE=0", _
        "THREADSAFE=1", _
        "THREADSAFE=2", _
        "ENABLE_URI_00_ERROR" _
    }

#if SQLITE_THREADSAFE = 0
#define SQLITE_COMPILEOPTION_MUTEX @sqlite3CompileOptionNames(33)
#define SQLITE_COMPILEOPTION_THREADSAFE @sqlite3CompileOptionNames(40)
#elseif SQLITE_THREADSAFE = 2
#define SQLITE_COMPILEOPTION_MUTEX @sqlite3CompileOptionNames(34)
#define SQLITE_COMPILEOPTION_THREADSAFE @sqlite3CompileOptionNames(42)
#else
#define SQLITE_COMPILEOPTION_MUTEX @sqlite3CompileOptionNames(34)
#define SQLITE_COMPILEOPTION_THREADSAFE @sqlite3CompileOptionNames(41)
#endif

#if SQLITE_TEMP_STORE = 0
#define SQLITE_COMPILEOPTION_TEMP_STORE @sqlite3CompileOptionNames(36)
#elseif SQLITE_TEMP_STORE = 2
#define SQLITE_COMPILEOPTION_TEMP_STORE @sqlite3CompileOptionNames(38)
#elseif SQLITE_TEMP_STORE = 3
#define SQLITE_COMPILEOPTION_TEMP_STORE @sqlite3CompileOptionNames(39)
#else
#define SQLITE_COMPILEOPTION_TEMP_STORE @sqlite3CompileOptionNames(37)
#endif

#ifndef SQLITE_OMIT_COMPILEOPTION_DIAGS
Dim Shared As Const ZString Ptr sqlite3CompileOptionPointers(0 To SQLITE_COMPILEOPTION_COUNT - 1) = _
    { _
        @sqlite3CompileOptionNames(0), @sqlite3CompileOptionNames(1), _
        @sqlite3CompileOptionNames(2), @sqlite3CompileOptionNames(3), _
        @sqlite3CompileOptionNames(4), @sqlite3CompileOptionNames(5), _
        @sqlite3CompileOptionNames(6), @sqlite3CompileOptionNames(7), _
        @sqlite3CompileOptionNames(8), @sqlite3CompileOptionNames(9), _
        @sqlite3CompileOptionNames(10), @sqlite3CompileOptionNames(11), _
        @sqlite3CompileOptionNames(12), @sqlite3CompileOptionNames(13), _
        @sqlite3CompileOptionNames(14), _
        SQLITE_COMPILEOPTION_URI_EXTRA _
        @sqlite3CompileOptionNames(15), @sqlite3CompileOptionNames(16), _
        @sqlite3CompileOptionNames(17), _
        @sqlite3CompileOptionNames(18), @sqlite3CompileOptionNames(19), _
        @sqlite3CompileOptionNames(20), @sqlite3CompileOptionNames(21), _
        @sqlite3CompileOptionNames(22), @sqlite3CompileOptionNames(23), _
        @sqlite3CompileOptionNames(24), @sqlite3CompileOptionNames(25), _
        @sqlite3CompileOptionNames(26), @sqlite3CompileOptionNames(27), _
        @sqlite3CompileOptionNames(28), @sqlite3CompileOptionNames(29), _
        @sqlite3CompileOptionNames(30), @sqlite3CompileOptionNames(31), _
        @sqlite3CompileOptionNames(32), SQLITE_COMPILEOPTION_MUTEX, _
        @sqlite3CompileOptionNames(35), SQLITE_COMPILEOPTION_TEMP_STORE, _
        SQLITE_COMPILEOPTION_THREADSAFE _
    }

Function sqlite3CompileOptions CDecl Alias "sqlite3CompileOptions" ( _
    ByVal pOptionCount As SQLITE_C_INT Ptr _
) As Const ZString Ptr Ptr Export
    If pOptionCount = 0 Then Return 0
    pOptionCount[0] = SQLITE_COMPILEOPTION_COUNT
    Return @sqlite3CompileOptionPointers(0)
End Function

Private Function sqlite3CompileOptionFold(ByVal value As UByte) As UByte
    If value >= Asc("A") AndAlso value <= Asc("Z") Then Return value + 32
    Return value
End Function

Private Function sqlite3CompileOptionPrefixEquals( _
    ByVal zLeft As Const UByte Ptr, _
    ByVal zRight As Const UByte Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As SQLITE_C_INT
    For iByte As SQLITE_C_INT = 0 To nByte - 1
        If sqlite3CompileOptionFold(zLeft[iByte]) <> _
           sqlite3CompileOptionFold(zRight[iByte]) Then Return 0
    Next
    Return 1
End Function

Private Function sqlite3CompileOptionIsIdentifier(ByVal value As UByte) As SQLITE_C_INT
    If value >= Asc("A") AndAlso value <= Asc("Z") Then Return 1
    If value >= Asc("a") AndAlso value <= Asc("z") Then Return 1
    If value >= Asc("0") AndAlso value <= Asc("9") Then Return 1
    If value = Asc("_") Then Return 1
    Return 0
End Function

Function sqlite3_compileoption_used CDecl Alias "sqlite3_compileoption_used" ( _
    ByVal zOptionName As Const ZString Ptr _
) As SQLITE_C_INT Export
    If zOptionName = 0 Then Return 0

    Dim zQuery As Const UByte Ptr = CPtr(Const UByte Ptr, zOptionName)
    If sqlite3CompileOptionPrefixEquals(zQuery, CPtr(Const UByte Ptr, StrPtr("SQLITE_")), 7) <> 0 Then _
        zQuery += 7

    Dim nameLength As SQLITE_C_INT = 0
    While nameLength < 30 AndAlso zQuery[nameLength] <> 0
        nameLength += 1
    Wend

    Dim optionCount As SQLITE_C_INT = 0
    Dim pOptions As Const ZString Ptr Ptr = sqlite3CompileOptions(@optionCount)
    For iOption As SQLITE_C_INT = 0 To optionCount - 1
        Dim zOption As Const UByte Ptr = CPtr(Const UByte Ptr, pOptions[iOption])
        If sqlite3CompileOptionPrefixEquals(zQuery, zOption, nameLength) <> 0 AndAlso _
           sqlite3CompileOptionIsIdentifier(zOption[nameLength]) = 0 Then Return 1
    Next
    Return 0
End Function

Function sqlite3_compileoption_get CDecl Alias "sqlite3_compileoption_get" ( _
    ByVal optionIndex As SQLITE_C_INT _
) As Const ZString Ptr Export
    Dim optionCount As SQLITE_C_INT = 0
    Dim pOptions As Const ZString Ptr Ptr = sqlite3CompileOptions(@optionCount)
    If optionIndex < 0 OrElse optionIndex >= optionCount Then Return 0
    Return pOptions[optionIndex]
End Function
#endif

/' end of sqlite3_compile_options.bas '/
