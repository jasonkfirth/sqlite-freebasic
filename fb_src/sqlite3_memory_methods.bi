/'
    Project: SQLite FreeBASIC port

    File: sqlite3_memory_methods.bi

    Purpose:

        Define the allocator callback table accepted by sqlite3_config().

    Responsibilities:

        - Match the C field order and calling convention of sqlite3_mem_methods.
        - Declare the internal accessors for the selected allocator table.

    This file intentionally does NOT contain:

        - Allocation policy or heap accounting.
        - The system allocator callback implementations.
'/ 

#ifndef SQLITE3_FB_MEMORY_METHODS_BI
#define SQLITE3_FB_MEMORY_METHODS_BI

#include once "sqlite3_types.bi"

Type SqliteMemMallocProc As Function CDecl ( _
    ByVal nByte As SQLITE_C_INT _
) As Any Ptr
Type SqliteMemFreeProc As Sub CDecl (ByVal pPrior As Any Ptr)
Type SqliteMemReallocProc As Function CDecl ( _
    ByVal pPrior As Any Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As Any Ptr
Type SqliteMemSizeProc As Function CDecl (ByVal pPrior As Any Ptr) As SQLITE_C_INT
Type SqliteMemRoundupProc As Function CDecl (ByVal nByte As SQLITE_C_INT) As SQLITE_C_INT
Type SqliteMemInitProc As Function CDecl (ByVal pAppData As Any Ptr) As SQLITE_C_INT
Type SqliteMemShutdownProc As Sub CDecl (ByVal pAppData As Any Ptr)

Type SqliteMemMethods
    xMalloc As SqliteMemMallocProc
    xFree As SqliteMemFreeProc
    xRealloc As SqliteMemReallocProc
    xSize As SqliteMemSizeProc
    xRoundup As SqliteMemRoundupProc
    xInit As SqliteMemInitProc
    xShutdown As SqliteMemShutdownProc
    pAppData As Any Ptr
End Type

Declare Function sqlite3MemConfigSetMethods CDecl Alias "sqlite3MemConfigSetMethods" ( _
    ByVal pMethods As Const SqliteMemMethods Ptr _
) As SQLITE_C_INT
Declare Function sqlite3MemConfigResetMethods CDecl Alias "sqlite3MemConfigResetMethods" () As SQLITE_C_INT
Declare Sub sqlite3MemConfigGetMethods CDecl Alias "sqlite3MemConfigGetMethods" ( _
    ByVal pMethods As SqliteMemMethods Ptr _
)
Declare Function sqlite3MemConfigHasMethods CDecl Alias "sqlite3MemConfigHasMethods" () As SQLITE_C_INT
Declare Function sqlite3MemConfigIsInitialized CDecl Alias "sqlite3MemConfigIsInitialized" () As SQLITE_C_INT
Declare Sub sqlite3MemSetDefault CDecl Alias "sqlite3MemSetDefault" ()
#if defined(SQLITE_OS_WIN) AndAlso defined(SQLITE_WIN32_MALLOC)
Declare Function sqlite3MemGetWin32 CDecl Alias "sqlite3MemGetWin32" () _
    As Const SqliteMemMethods Ptr
#endif
#ifdef SQLITE_ENABLE_MEMSYS3
Declare Function sqlite3MemGetMemsys3 CDecl Alias "sqlite3MemGetMemsys3" () As Const SqliteMemMethods Ptr
#endif
#ifdef SQLITE_ENABLE_MEMSYS5
Declare Function sqlite3MemGetMemsys5 CDecl Alias "sqlite3MemGetMemsys5" () As Const SqliteMemMethods Ptr
#endif
Declare Sub sqlite3ConfigGetHeap CDecl Alias "sqlite3ConfigGetHeap" ( _
    ByVal ppHeap As Any Ptr Ptr, _
    ByVal pnByte As SQLITE_C_INT Ptr, _
    ByVal pMinRequest As SQLITE_C_INT Ptr _
)

#endif

/' end of sqlite3_memory_methods.bi '/
