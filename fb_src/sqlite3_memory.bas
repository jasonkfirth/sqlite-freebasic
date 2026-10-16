/'
    Project: SQLite FreeBASIC port

    File: sqlite3_memory.bas

    Purpose:

        Provide SQLite's default system-backed allocation path and selected
        sqlite3_mem_methods dispatch.

    Responsibilities:

        - Port the size-prefix allocator from src/mem1.c.
        - Supply and initialize the default sqlite3_mem_methods table.
        - Route allocation calls through the configured memory callbacks.
        - Implement the core allocation and reallocation routines from src/malloc.c.
        - Enforce configured soft and hard heap limits under the allocator mutex.
        - Preserve the deprecated sqlite3_memory_alarm() no-op API.
        - Initialize SQLite before the public malloc/realloc entry points run.
        - Export sqlite3_malloc(), sqlite3_free(), and related memory APIs.
        - Retain the debug OOM breakpoint counter used by heap-limit checks.

    This file intentionally does NOT contain:

        - SQLITE_CONFIG_MALLOC and SQLITE_CONFIG_GETMALLOC command parsing.
        - Status counter storage.
        - Connection lookaside allocation and sqlite3_initialize().
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_mutex.bi"
#include once "sqlite3_status.bi"
#include once "sqlite3_memory_methods.bi"

#ifndef SQLITE_MAX_MEMORY
#define SQLITE_MAX_MEMORY 0
#endif

Extern "C"
    Declare Function sqlite3SystemMalloc CDecl Alias "malloc" (ByVal nByte As SQLITE_SIZE_T) As Any Ptr
    Declare Function sqlite3SystemRealloc CDecl Alias "realloc" (ByVal pOld As Any Ptr, ByVal nByte As SQLITE_SIZE_T) As Any Ptr
    Declare Sub sqlite3SystemFree CDecl Alias "free" (ByVal p As Any Ptr)
    Declare Function sqlite3SystemMemset CDecl Alias "memset" (ByVal p As Any Ptr, ByVal c As SQLITE_C_INT, ByVal nByte As SQLITE_SIZE_T) As Any Ptr
    Declare Sub sqlite3SystemAbort CDecl Alias "abort" ()
End Extern

Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Declare Function sqlite3_initialize CDecl Alias "sqlite3_initialize" () As SQLITE_C_INT
Declare Function sqlite3ConfigMemStatusEnabled CDecl Alias "sqlite3ConfigMemStatusEnabled" () As SQLITE_C_INT
Declare Function sqlite3_config CDecl Alias "sqlite3_config" ( _
    ByVal operation As SQLITE_C_INT, ... _
) As SQLITE_C_INT

#if defined(SQLITE_ENABLE_MEMORY_MANAGEMENT)
Declare Function sqlite3PcacheReleaseMemory CDecl Alias "sqlite3PcacheReleaseMemory" ( _
    ByVal requestedBytes As SQLITE_C_INT _
) As SQLITE_C_INT
#endif

Const SQLITE_MAX_ROUNDED_ALLOCATION As SQLITE_C_INT = SQLITE_MAX_ALLOCATION_SIZE + 7
Private Dim Shared sqlite3MemorySoftLimit As sqlite3_int64 = SQLITE_MAX_MEMORY
Private Dim Shared sqlite3MemoryHardLimit As sqlite3_int64 = SQLITE_MAX_MEMORY
Private Dim Shared sqlite3MemoryNearlyFull As SQLITE_C_INT = 0
#ifdef SQLITE_DEBUG
Private Dim Shared sqlite3OomFaultCount As sqlite3_uint64
#endif
Private Dim Shared sqlite3CurrentMemMethods As SqliteMemMethods
Private Dim Shared sqlite3CurrentMemMethodsReady As u8 = 0
Private Dim Shared sqlite3MemoryAllocatorInitialized As u8 = 0

Private Function sqlite3MemRoundupRequest( _
    ByVal nByte As SQLITE_C_INT _
) As SQLITE_C_INT
    If nByte <= 0 OrElse sqlite3CurrentMemMethodsReady = 0 Then Return 0
    Dim roundedSize As SQLITE_C_INT = _
        sqlite3CurrentMemMethods.xRoundup(nByte)
    If roundedSize < nByte Then Return 0
    Return roundedSize
End Function

Private Function sqlite3MemConfiguredSize(ByVal p As Any Ptr) As SQLITE_C_INT
    If p = 0 OrElse sqlite3CurrentMemMethodsReady = 0 Then Return 0
    Dim nByte As SQLITE_C_INT = sqlite3CurrentMemMethods.xSize(p)
    If nByte <= 0 Then Return 0
    Return nByte
End Function

#ifndef SQLITE_OMIT_DEPRECATED
Function sqlite3_memory_alarm CDecl Alias "sqlite3_memory_alarm" ( _
    ByVal xCallback As Any Ptr, _
    ByVal pArgument As Any Ptr, _
    ByVal threshold As sqlite3_int64 _
) As SQLITE_C_INT Export
    ' The alarm callback was retired; retain its ABI and historical no-op result.
    Return SQLITE_OK
End Function
#endif

/' ------------------------------------------------------------------------- '/
/' System allocator '/
/' ------------------------------------------------------------------------- '/

#if defined(SQLITE_ZERO_MALLOC)
Private Function sqlite3MemRoundup CDecl (ByVal nByte As SQLITE_C_INT) As SQLITE_C_INT
    Return nByte
End Function

Private Function sqlite3MemMalloc CDecl (ByVal nByte As SQLITE_C_INT) As Any Ptr
    Return 0
End Function

Private Sub sqlite3MemFree CDecl (ByVal pUser As Any Ptr)
End Sub

Private Function sqlite3MemSize CDecl (ByVal pUser As Any Ptr) As SQLITE_C_INT
    Return 0
End Function

Private Function sqlite3MemRealloc CDecl ( _
    ByVal pOld As Any Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As Any Ptr
    Return 0
End Function
#else
Private Function sqlite3MemRoundup CDecl (ByVal nByte As SQLITE_C_INT) As SQLITE_C_INT
    If nByte <= 0 Then Return 0
    ' Keep allocations on the eight-byte boundaries required by SQLite.
    Dim remainder As SQLITE_C_INT = nByte Mod 8
    If remainder = 0 Then Return nByte
    Return nByte + (8 - remainder)
End Function

Private Function sqlite3MemMalloc CDecl (ByVal nByte As SQLITE_C_INT) As Any Ptr
    If nByte <= 0 OrElse nByte > SQLITE_MAX_ROUNDED_ALLOCATION Then Return 0

    ' The eight-byte prefix stores the rounded payload size, as in mem1.c.
    Dim nTotal As ULongInt = CULngInt(nByte) + 8
    Dim pBase As Any Ptr = sqlite3SystemMalloc(CUInt(nTotal))
    If pBase = 0 Then Return 0

    Dim pSize As sqlite3_int64 Ptr = CPtr(sqlite3_int64 Ptr, pBase)
    pSize[0] = nByte

    Dim pUser As UByte Ptr = CPtr(UByte Ptr, pBase)
    Return pUser + 8
End Function

Private Sub sqlite3MemFree CDecl (ByVal pUser As Any Ptr)
    If pUser = 0 Then Return

    Dim pBase As UByte Ptr = CPtr(UByte Ptr, pUser) - 8
    sqlite3SystemFree(pBase)
End Sub

Private Function sqlite3MemSize CDecl (ByVal pUser As Any Ptr) As SQLITE_C_INT
    If pUser = 0 Then Return 0

    Dim pBase As UByte Ptr = CPtr(UByte Ptr, pUser) - 8
    Dim pSize As sqlite3_int64 Ptr = CPtr(sqlite3_int64 Ptr, pBase)
    Return CLng(pSize[0])
End Function

Private Function sqlite3MemRealloc CDecl ( _
    ByVal pOld As Any Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As Any Ptr

    If pOld = 0 OrElse nByte <= 0 OrElse nByte > SQLITE_MAX_ROUNDED_ALLOCATION Then Return 0

    Dim pOldBase As UByte Ptr = CPtr(UByte Ptr, pOld) - 8
    Dim nTotal As ULongInt = CULngInt(nByte) + 8
    Dim pNewBase As Any Ptr = sqlite3SystemRealloc(pOldBase, CUInt(nTotal))
    If pNewBase = 0 Then Return 0

    Dim pSize As sqlite3_int64 Ptr = CPtr(sqlite3_int64 Ptr, pNewBase)
    pSize[0] = nByte

    Dim pNewUser As UByte Ptr = CPtr(UByte Ptr, pNewBase)
    Return pNewUser + 8
End Function
#endif

Private Function sqlite3MemInit CDecl (ByVal pAppData As Any Ptr) As SQLITE_C_INT
    Return SQLITE_OK
End Function

Private Sub sqlite3MemShutdown CDecl (ByVal pAppData As Any Ptr)
End Sub

Function sqlite3MemConfigSetMethods CDecl Alias "sqlite3MemConfigSetMethods" ( _
    ByVal pMethods As Const SqliteMemMethods Ptr _
) As SQLITE_C_INT Export
    If sqlite3MemoryAllocatorInitialized <> 0 OrElse _
       pMethods = 0 OrElse pMethods->xMalloc = 0 OrElse _
       pMethods->xFree = 0 OrElse pMethods->xRealloc = 0 OrElse _
       pMethods->xSize = 0 OrElse pMethods->xRoundup = 0 Then
        Return SQLITE_MISUSE
    End If

    sqlite3CurrentMemMethods.xMalloc = pMethods->xMalloc
    sqlite3CurrentMemMethods.xFree = pMethods->xFree
    sqlite3CurrentMemMethods.xRealloc = pMethods->xRealloc
    sqlite3CurrentMemMethods.xSize = pMethods->xSize
    sqlite3CurrentMemMethods.xRoundup = pMethods->xRoundup
    sqlite3CurrentMemMethods.xInit = pMethods->xInit
    sqlite3CurrentMemMethods.xShutdown = pMethods->xShutdown
    sqlite3CurrentMemMethods.pAppData = pMethods->pAppData
    sqlite3CurrentMemMethodsReady = 1
    Return SQLITE_OK
End Function

Function sqlite3MemConfigResetMethods CDecl Alias "sqlite3MemConfigResetMethods" () As SQLITE_C_INT Export
    If sqlite3MemoryAllocatorInitialized <> 0 Then Return SQLITE_MISUSE
    Dim emptyMethods As SqliteMemMethods
    sqlite3CurrentMemMethods = emptyMethods
    sqlite3CurrentMemMethodsReady = 0
    Return SQLITE_OK
End Function

Sub sqlite3MemConfigGetMethods CDecl Alias "sqlite3MemConfigGetMethods" ( _
    ByVal pMethods As SqliteMemMethods Ptr _
) Export
    If pMethods = 0 Then Exit Sub
    pMethods->xMalloc = sqlite3CurrentMemMethods.xMalloc
    pMethods->xFree = sqlite3CurrentMemMethods.xFree
    pMethods->xRealloc = sqlite3CurrentMemMethods.xRealloc
    pMethods->xSize = sqlite3CurrentMemMethods.xSize
    pMethods->xRoundup = sqlite3CurrentMemMethods.xRoundup
    pMethods->xInit = sqlite3CurrentMemMethods.xInit
    pMethods->xShutdown = sqlite3CurrentMemMethods.xShutdown
    pMethods->pAppData = sqlite3CurrentMemMethods.pAppData
End Sub

Function sqlite3MemConfigHasMethods CDecl Alias "sqlite3MemConfigHasMethods" () As SQLITE_C_INT Export
    Return CInt(sqlite3CurrentMemMethodsReady <> 0)
End Function

Function sqlite3MemConfigIsInitialized CDecl Alias "sqlite3MemConfigIsInitialized" () As SQLITE_C_INT Export
    Return CInt(sqlite3MemoryAllocatorInitialized <> 0)
End Function

#ifndef SQLITE_MEMDEBUG
Sub sqlite3MemSetDefault CDecl Alias "sqlite3MemSetDefault" () Export
#if defined(SQLITE_OS_WIN) AndAlso defined(SQLITE_WIN32_MALLOC)
    sqlite3_config(SQLITE_CONFIG_MALLOC, sqlite3MemGetWin32())
#else
    Dim defaultMethods As SqliteMemMethods
    defaultMethods.xMalloc = @sqlite3MemMalloc
    defaultMethods.xFree = @sqlite3MemFree
    defaultMethods.xRealloc = @sqlite3MemRealloc
    defaultMethods.xSize = @sqlite3MemSize
    defaultMethods.xRoundup = @sqlite3MemRoundup
    defaultMethods.xInit = @sqlite3MemInit
    defaultMethods.xShutdown = @sqlite3MemShutdown
    defaultMethods.pAppData = 0
    sqlite3_config(SQLITE_CONFIG_MALLOC, @defaultMethods)
#endif
End Sub
#endif

Function sqlite3_release_memory CDecl Alias "sqlite3_release_memory" ( _
    ByVal requestedBytes As SQLITE_C_INT _
) As SQLITE_C_INT Export
#if defined(SQLITE_ENABLE_MEMORY_MANAGEMENT)
    ' A negative request means release all eligible cached pages.
    Return sqlite3PcacheReleaseMemory(requestedBytes)
#else
    Return 0
#endif
End Function

Function sqlite3MallocInit CDecl Alias "sqlite3MallocInit" () As SQLITE_C_INT Export
    Dim rc As SQLITE_C_INT = sqlite3MutexInit()
    If rc <> SQLITE_OK Then Return rc

    ' The public allocator supplies a no-op lock when core mutexes are off.
    Dim pMainMutex As Any Ptr = sqlite3_mutex_alloc(SQLITE_MUTEX_STATIC_MAIN)
    If pMainMutex = 0 Then Return SQLITE_NOMEM
    sqlite3_mutex_enter(pMainMutex)
    If sqlite3MemoryAllocatorInitialized <> 0 Then
        sqlite3_mutex_leave(pMainMutex)
        Return SQLITE_OK
    End If

    If sqlite3MemConfigHasMethods() = 0 Then sqlite3MemSetDefault()
    If sqlite3CurrentMemMethodsReady = 0 OrElse sqlite3MallocMutex() = 0 Then
        sqlite3_mutex_leave(pMainMutex)
        Return SQLITE_NOMEM
    End If

    sqlite3MemoryAllocatorInitialized = 1
    If sqlite3CurrentMemMethods.xInit <> 0 Then _
        rc = sqlite3CurrentMemMethods.xInit(sqlite3CurrentMemMethods.pAppData)
    If rc <> SQLITE_OK Then sqlite3MemoryAllocatorInitialized = 0
    sqlite3_mutex_leave(pMainMutex)
    Return rc
End Function

Private Sub sqlite3MallocAlarm(ByVal pMutex As Any Ptr, ByVal requestedBytes As SQLITE_C_INT)
    If pMutex = 0 OrElse requestedBytes <= 0 OrElse sqlite3MemorySoftLimit <= 0 Then Return
    sqlite3_mutex_leave(pMutex)
    sqlite3_release_memory(requestedBytes)
    sqlite3_mutex_enter(pMutex)
End Sub

#ifdef SQLITE_DEBUG
Private Sub test_oom_breakpoint(ByVal increment As sqlite3_uint64)
    sqlite3OomFaultCount += increment
    If (sqlite3OomFaultCount Shr 32) >= &HFFFFFFFFULL Then _
        sqlite3SystemAbort()
End Sub
#endif

Private Function mallocWithAlarm( _
    ByVal requestedBytes As SQLITE_C_INT, _
    ByVal pMutex As Any Ptr _
) As Any Ptr
    If requestedBytes <= 0 OrElse pMutex = 0 Then Return 0
    Dim fullSize As SQLITE_C_INT = sqlite3MemRoundupRequest(requestedBytes)
    If fullSize <= 0 Then Return 0

    sqlite3StatusHighwater(SQLITE_STATUS_MALLOC_SIZE, requestedBytes)
    If sqlite3MemorySoftLimit > 0 Then
        Dim memoryUsed As sqlite3_int64 = _
            sqlite3StatusValue(SQLITE_STATUS_MEMORY_USED)
        If memoryUsed >= sqlite3MemorySoftLimit - fullSize Then
            sqlite3MemoryNearlyFull = 1
            sqlite3MallocAlarm(pMutex, fullSize)
            If sqlite3MemoryHardLimit > 0 Then
                memoryUsed = sqlite3StatusValue(SQLITE_STATUS_MEMORY_USED)
                If memoryUsed >= sqlite3MemoryHardLimit - fullSize Then
#ifdef SQLITE_DEBUG
                    test_oom_breakpoint(1)
#endif
                    Return 0
                End If
            End If
        Else
            sqlite3MemoryNearlyFull = 0
        End If
    End If

    Dim pAllocation As Any Ptr = _
        sqlite3CurrentMemMethods.xMalloc(fullSize)
#if defined(SQLITE_ENABLE_MEMORY_MANAGEMENT)
    If pAllocation = 0 AndAlso sqlite3MemorySoftLimit > 0 Then
        sqlite3MallocAlarm(pMutex, fullSize)
        pAllocation = sqlite3CurrentMemMethods.xMalloc(fullSize)
    End If
#endif
    If pAllocation = 0 Then Return 0

    Dim actualSize As SQLITE_C_INT = sqlite3MemConfiguredSize(pAllocation)
    If actualSize <= 0 Then
        sqlite3CurrentMemMethods.xFree(pAllocation)
        Return 0
    End If
    sqlite3StatusUp(SQLITE_STATUS_MEMORY_USED, actualSize)
    sqlite3StatusUp(SQLITE_STATUS_MALLOC_COUNT, 1)
    Return pAllocation
End Function

Function sqlite3_soft_heap_limit64 CDecl Alias "sqlite3_soft_heap_limit64" ( _
    ByVal newLimit As sqlite3_int64 _
) As sqlite3_int64 Export
#ifndef SQLITE_OMIT_AUTOINIT
    If sqlite3_initialize() <> SQLITE_OK Then Return -1
#endif
    Dim pMutex As Any Ptr = sqlite3MallocMutex()
    If pMutex = 0 Then Return -1
    sqlite3_mutex_enter(pMutex)
    Dim priorLimit As sqlite3_int64 = sqlite3MemorySoftLimit
    If newLimit < 0 Then
        sqlite3_mutex_leave(pMutex)
        Return priorLimit
    End If
    If sqlite3MemoryHardLimit > 0 AndAlso _
       (newLimit > sqlite3MemoryHardLimit OrElse newLimit = 0) Then
        newLimit = sqlite3MemoryHardLimit
    End If
    sqlite3MemorySoftLimit = newLimit
    Dim memoryUsed As sqlite3_int64 = _
        sqlite3StatusValue(SQLITE_STATUS_MEMORY_USED)
    sqlite3MemoryNearlyFull = CInt(newLimit > 0 AndAlso newLimit <= memoryUsed)
    sqlite3_mutex_leave(pMutex)

    Dim excessBytes As sqlite3_int64 = sqlite3_memory_used() - newLimit
    If excessBytes > 0 Then
        sqlite3_release_memory(CLng(CULngInt(excessBytes) And &H7FFFFFFF))
    End If
    Return priorLimit
End Function

Function sqlite3_hard_heap_limit64 CDecl Alias "sqlite3_hard_heap_limit64" ( _
    ByVal newLimit As sqlite3_int64 _
) As sqlite3_int64 Export
#ifndef SQLITE_OMIT_AUTOINIT
    If sqlite3_initialize() <> SQLITE_OK Then Return -1
#endif
    Dim pMutex As Any Ptr = sqlite3MallocMutex()
    If pMutex = 0 Then Return -1
    sqlite3_mutex_enter(pMutex)
    Dim priorLimit As sqlite3_int64 = sqlite3MemoryHardLimit
    If newLimit >= 0 Then
        sqlite3MemoryHardLimit = newLimit
        If newLimit < sqlite3MemorySoftLimit OrElse sqlite3MemorySoftLimit = 0 Then _
            sqlite3MemorySoftLimit = newLimit
    End If
    sqlite3_mutex_leave(pMutex)
    Return priorLimit
End Function

Sub sqlite3_soft_heap_limit CDecl Alias "sqlite3_soft_heap_limit" ( _
    ByVal newLimit As SQLITE_C_INT _
) Export
    If newLimit < 0 Then newLimit = 0
    sqlite3_soft_heap_limit64(newLimit)
End Sub

Function sqlite3HeapNearlyFull CDecl Alias "sqlite3HeapNearlyFull" () As SQLITE_C_INT Export
    Dim pMutex As Any Ptr = sqlite3MallocMutex()
    If pMutex = 0 Then Return CInt(sqlite3MemoryNearlyFull <> 0)
    sqlite3_mutex_enter(pMutex)
    Dim result As SQLITE_C_INT = IIf(sqlite3MemoryNearlyFull <> 0, 1, 0)
    sqlite3_mutex_leave(pMutex)
    Return result
End Function

Sub sqlite3MallocEnd CDecl Alias "sqlite3MallocEnd" () Export
    Dim pMainMutex As Any Ptr = sqlite3_mutex_alloc(SQLITE_MUTEX_STATIC_MAIN)
    If pMainMutex <> 0 Then sqlite3_mutex_enter(pMainMutex)
    If sqlite3MemoryAllocatorInitialized <> 0 AndAlso _
       sqlite3CurrentMemMethods.xShutdown <> 0 Then
        sqlite3CurrentMemMethods.xShutdown(sqlite3CurrentMemMethods.pAppData)
    End If
    sqlite3MemoryAllocatorInitialized = 0
    Dim pMutex As Any Ptr = sqlite3MallocMutex()
    If pMutex = 0 Then
        sqlite3MemorySoftLimit = 0
        sqlite3MemoryHardLimit = 0
        sqlite3MemoryNearlyFull = 0
        If pMainMutex <> 0 Then sqlite3_mutex_leave(pMainMutex)
        Return
    End If
    sqlite3_mutex_enter(pMutex)
    sqlite3MemorySoftLimit = 0
    sqlite3MemoryHardLimit = 0
    sqlite3MemoryNearlyFull = 0
    sqlite3_mutex_leave(pMutex)
    If pMainMutex <> 0 Then sqlite3_mutex_leave(pMainMutex)
End Sub

/' ------------------------------------------------------------------------- '/
/' SQLite allocation interface '/
/' ------------------------------------------------------------------------- '/

Function sqlite3Malloc CDecl Alias "sqlite3Malloc" (ByVal nByte As sqlite3_uint64) As Any Ptr Export
    If nByte = 0 OrElse nByte > SQLITE_MAX_ALLOCATION_SIZE OrElse _
       sqlite3CurrentMemMethodsReady = 0 Then Return 0

    If sqlite3ConfigMemStatusEnabled() = 0 Then
        Return sqlite3CurrentMemMethods.xMalloc(CLng(nByte))
    End If

    Dim pMutex As Any Ptr = sqlite3MallocMutex()
    If pMutex = 0 Then Return 0
    sqlite3_mutex_enter(pMutex)
    Dim p As Any Ptr = mallocWithAlarm(CLng(nByte), pMutex)
    sqlite3_mutex_leave(pMutex)
    Return p
End Function

Function sqlite3MallocZero CDecl Alias "sqlite3MallocZero" (ByVal nByte As sqlite3_uint64) As Any Ptr Export
    Dim p As Any Ptr = sqlite3Malloc(nByte)
    If p = 0 Then Return 0

    If nByte > 0 Then sqlite3SystemMemset(p, 0, CUInt(nByte))
    Return p
End Function

Function sqlite3MallocSize CDecl Alias "sqlite3MallocSize" (ByVal p As Any Ptr) As SQLITE_C_INT Export
    Return sqlite3MemConfiguredSize(p)
End Function

Function sqlite3Realloc CDecl Alias "sqlite3Realloc" ( _
    ByVal pOld As Any Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr Export

    If pOld = 0 Then Return sqlite3Malloc(nByte)
    If nByte = 0 Then
        sqlite3_free(pOld)
        Return 0
    End If
    If nByte > SQLITE_MAX_ALLOCATION_SIZE Then Return 0

    If sqlite3ConfigMemStatusEnabled() = 0 Then
        Dim nRounded As SQLITE_C_INT = sqlite3MemRoundupRequest(CLng(nByte))
        If nRounded <= 0 Then Return 0
        Return sqlite3CurrentMemMethods.xRealloc(pOld, nRounded)
    End If

    Dim pMutex As Any Ptr = sqlite3MallocMutex()
    If pMutex = 0 Then Return 0
    sqlite3_mutex_enter(pMutex)
    Dim nOld As SQLITE_C_INT = sqlite3MemConfiguredSize(pOld)
    If nOld <= 0 Then
        sqlite3_mutex_leave(pMutex)
        Return 0
    End If
    Dim nRounded As SQLITE_C_INT = sqlite3MemRoundupRequest(CLng(nByte))
    If nRounded <= 0 Then
        sqlite3_mutex_leave(pMutex)
        Return 0
    End If
    If nOld = nRounded Then
        sqlite3_mutex_leave(pMutex)
        Return pOld
    End If
    sqlite3StatusHighwater(SQLITE_STATUS_MALLOC_SIZE, CLng(nByte))

    Dim allocationDifference As SQLITE_C_INT = nRounded - nOld
    If allocationDifference > 0 AndAlso sqlite3MemorySoftLimit > 0 Then
        Dim memoryUsed As sqlite3_int64 = _
            sqlite3StatusValue(SQLITE_STATUS_MEMORY_USED)
        If memoryUsed >= sqlite3MemorySoftLimit - allocationDifference Then
            sqlite3MallocAlarm(pMutex, allocationDifference)
            If sqlite3MemoryHardLimit > 0 Then
                memoryUsed = sqlite3StatusValue(SQLITE_STATUS_MEMORY_USED)
                If memoryUsed >= sqlite3MemoryHardLimit - allocationDifference Then
                    sqlite3_mutex_leave(pMutex)
                    Return 0
                End If
            End If
        End If
    End If

    Dim pNew As Any Ptr = sqlite3CurrentMemMethods.xRealloc(pOld, nRounded)
    If pNew <> 0 Then
        Dim nNew As SQLITE_C_INT = sqlite3MemConfiguredSize(pNew)
        If nNew > 0 Then sqlite3StatusUp(SQLITE_STATUS_MEMORY_USED, nNew - nOld)
    End If
    sqlite3_mutex_leave(pMutex)
    Return pNew
End Function

Function sqlite3_malloc CDecl Alias "sqlite3_malloc" (ByVal nByte As SQLITE_C_INT) As Any Ptr Export
#ifndef SQLITE_OMIT_AUTOINIT
    ' Initialization tolerates recursive entry while subsystems are starting.
    If sqlite3_initialize() <> SQLITE_OK Then Return 0
#endif
    If nByte <= 0 Then Return 0
    Return sqlite3Malloc(CULngInt(nByte))
End Function

Function sqlite3_malloc64 CDecl Alias "sqlite3_malloc64" (ByVal nByte As sqlite3_uint64) As Any Ptr Export
#ifndef SQLITE_OMIT_AUTOINIT
    If sqlite3_initialize() <> SQLITE_OK Then Return 0
#endif
    Return sqlite3Malloc(nByte)
End Function

Function sqlite3_realloc CDecl Alias "sqlite3_realloc" ( _
    ByVal pOld As Any Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As Any Ptr Export

#ifndef SQLITE_OMIT_AUTOINIT
    If sqlite3_initialize() <> SQLITE_OK Then Return 0
#endif
    If nByte <= 0 Then
        If pOld <> 0 Then sqlite3_free(pOld)
        Return 0
    End If
    Return sqlite3Realloc(pOld, CULngInt(nByte))
End Function

Function sqlite3_realloc64 CDecl Alias "sqlite3_realloc64" ( _
    ByVal pOld As Any Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr Export

#ifndef SQLITE_OMIT_AUTOINIT
    If sqlite3_initialize() <> SQLITE_OK Then Return 0
#endif
    Return sqlite3Realloc(pOld, nByte)
End Function

Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr) Export
    If p = 0 Then Return
    If sqlite3CurrentMemMethodsReady = 0 Then Return
    If sqlite3ConfigMemStatusEnabled() = 0 Then
        sqlite3CurrentMemMethods.xFree(p)
        Return
    End If
    Dim pMutex As Any Ptr = sqlite3MallocMutex()
    sqlite3_mutex_enter(pMutex)
    Dim nByte As SQLITE_C_INT = sqlite3MemConfiguredSize(p)
    If nByte > 0 Then
        sqlite3StatusDown(SQLITE_STATUS_MEMORY_USED, nByte)
        sqlite3StatusDown(SQLITE_STATUS_MALLOC_COUNT, 1)
    End If
    sqlite3CurrentMemMethods.xFree(p)
    sqlite3_mutex_leave(pMutex)
End Sub

Function sqlite3_msize CDecl Alias "sqlite3_msize" (ByVal p As Any Ptr) As sqlite3_uint64 Export
    Return CULngInt(sqlite3MemConfiguredSize(p))
End Function

/' end of sqlite3_memory.bas '/
