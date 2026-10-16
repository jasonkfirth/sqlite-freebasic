/'
    Project: SQLite FreeBASIC port

    File: sqlite3_builtin_extensions.bas

    Purpose:

        Supply built-in initializer callbacks for default and optional profiles.

    Responsibilities:

        - Preserve main.c's fault-simulation initializer callback.
        - Add DBPAGE, DBSTAT, and bytecode-vtab initializers when enabled.
        - Provide stable callback-array storage and its active entry count.

    This file intentionally does NOT contain:

        - The implementations of FTS, R-tree, or other unported extensions.
        - SQLite test cases or test-runner code.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_fault.bi"

#ifdef SQLITE_ENABLE_DBPAGE_VTAB
Declare Function sqlite3DbpageRegister CDecl Alias "sqlite3DbpageRegister" ( _
    ByVal pDatabase As Any Ptr _
) As SQLITE_C_INT
#endif

Private Function sqlite3TestExtInit CDecl Alias "sqlite3TestExtInit" ( _
    ByVal pDatabase As Any Ptr _
) As SQLITE_C_INT
    ' Fault-injection site 500 exercises initialization of built-in extensions.
    Return sqlite3FaultSim(500)
End Function

#ifdef SQLITE_ENABLE_DBSTAT_VTAB
Declare Function sqlite3DbstatRegister CDecl Alias "sqlite3DbstatRegister" ( _
    ByVal pDatabase As Any Ptr _
) As SQLITE_C_INT
#endif
#ifdef SQLITE_ENABLE_BYTECODE_VTAB
Declare Function sqlite3VdbeBytecodeVtabInit CDecl Alias "sqlite3VdbeBytecodeVtabInit" ( _
    ByVal pDatabase As Any Ptr _
) As SQLITE_C_INT
#endif

#ifdef SQLITE_ENABLE_DBPAGE_VTAB
#if defined(SQLITE_ENABLE_DBSTAT_VTAB) AndAlso defined(SQLITE_ENABLE_BYTECODE_VTAB)
Private Dim Shared sqlite3BuiltinExtensionEntries(0 To 3) As _
    SqliteBuiltinExtensionInitProc = { _
        ProcPtr(sqlite3DbpageRegister), _
        ProcPtr(sqlite3DbstatRegister), _
        ProcPtr(sqlite3TestExtInit), _
        ProcPtr(sqlite3VdbeBytecodeVtabInit) _
    }
#elseif defined(SQLITE_ENABLE_DBSTAT_VTAB)
Private Dim Shared sqlite3BuiltinExtensionEntries(0 To 2) As _
    SqliteBuiltinExtensionInitProc = { _
        ProcPtr(sqlite3DbpageRegister), _
        ProcPtr(sqlite3DbstatRegister), _
        ProcPtr(sqlite3TestExtInit) _
    }
#elseif defined(SQLITE_ENABLE_BYTECODE_VTAB)
Private Dim Shared sqlite3BuiltinExtensionEntries(0 To 2) As _
    SqliteBuiltinExtensionInitProc = { _
        ProcPtr(sqlite3DbpageRegister), _
        ProcPtr(sqlite3TestExtInit), _
        ProcPtr(sqlite3VdbeBytecodeVtabInit) _
    }
#else
Private Dim Shared sqlite3BuiltinExtensionEntries(0 To 1) As _
    SqliteBuiltinExtensionInitProc = { _
        ProcPtr(sqlite3DbpageRegister), _
        ProcPtr(sqlite3TestExtInit) _
    }
#endif
#else
#if defined(SQLITE_ENABLE_DBSTAT_VTAB) AndAlso defined(SQLITE_ENABLE_BYTECODE_VTAB)
Private Dim Shared sqlite3BuiltinExtensionEntries(0 To 2) As _
    SqliteBuiltinExtensionInitProc = { _
        ProcPtr(sqlite3DbstatRegister), _
        ProcPtr(sqlite3TestExtInit), _
        ProcPtr(sqlite3VdbeBytecodeVtabInit) _
    }
#elseif defined(SQLITE_ENABLE_DBSTAT_VTAB)
Private Dim Shared sqlite3BuiltinExtensionEntries(0 To 1) As _
    SqliteBuiltinExtensionInitProc = { _
        ProcPtr(sqlite3DbstatRegister), _
        ProcPtr(sqlite3TestExtInit) _
    }
#elseif defined(SQLITE_ENABLE_BYTECODE_VTAB)
Private Dim Shared sqlite3BuiltinExtensionEntries(0 To 1) As _
    SqliteBuiltinExtensionInitProc = { _
        ProcPtr(sqlite3TestExtInit), _
        ProcPtr(sqlite3VdbeBytecodeVtabInit) _
    }
#else
Private Dim Shared sqlite3BuiltinExtensionEntries(0 To 0) As _
    SqliteBuiltinExtensionInitProc = {ProcPtr(sqlite3TestExtInit)}
#endif
#endif

Function c2fbBuiltinExtensionArray CDecl Alias "c2fbBuiltinExtensionArray" () _
    As SqliteBuiltinExtensionInitProc Ptr
    Return @sqlite3BuiltinExtensionEntries(0)
End Function

Function c2fbBuiltinExtensionCount CDecl Alias "c2fbBuiltinExtensionCount" () _
    As SQLITE_SIZE_T
#ifdef SQLITE_ENABLE_DBPAGE_VTAB
#if defined(SQLITE_ENABLE_DBSTAT_VTAB) AndAlso defined(SQLITE_ENABLE_BYTECODE_VTAB)
    Return 4
#elseif defined(SQLITE_ENABLE_DBSTAT_VTAB) OrElse defined(SQLITE_ENABLE_BYTECODE_VTAB)
    Return 3
#else
    Return 2
#endif
#else
#if defined(SQLITE_ENABLE_DBSTAT_VTAB) AndAlso defined(SQLITE_ENABLE_BYTECODE_VTAB)
    Return 3
#elseif defined(SQLITE_ENABLE_DBSTAT_VTAB) OrElse defined(SQLITE_ENABLE_BYTECODE_VTAB)
    Return 2
#else
    Return 1
#endif
#endif
End Function

/' end of sqlite3_builtin_extensions.bas '/
