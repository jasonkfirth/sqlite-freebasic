/'
    Project: SQLite FreeBASIC port
    -----------------------------

    File: sqlite3_os_win_memory.bas

    Purpose:

        Port SQLite's optional Windows heap allocator and heap controls.

    Responsibilities:

        - Own the process-wide Windows heap state used by SQLite allocations.
        - Implement the sqlite3_mem_methods callbacks with Win32 heap APIs.
        - Route overrideable heap calls through the shared Windows syscall table.
        - Create, validate, compact, reset, and destroy the selected heap.
        - Select the Windows heap methods when SQLITE_WIN32_MALLOC is enabled.

    This file intentionally does NOT contain:

        - Unix or SQLite's portable system allocator callbacks.
        - The Windows file VFS or syscall override table.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_mutex.bi"
#include once "sqlite3_memory_methods.bi"
#include once "sqlite3_vfs.bi"

#ifdef SQLITE_OS_WIN
#include once "sqlite3_os_win_types.bi"
#ifdef SQLITE_WIN32_MALLOC

Declare Function sqlite3_config CDecl Alias "sqlite3_config" ( _
    ByVal operation As SQLITE_C_INT, ... _
) As SQLITE_C_INT
Declare Function sqlite3_memory_used CDecl Alias "sqlite3_memory_used" () _
    As sqlite3_int64
Declare Sub sqlite3_log CDecl Alias "sqlite3_log" ( _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal zFormat As Const ZString Ptr, ... _
)
Declare Function winDefaultWinMemGetLastError StdCall Lib "kernel32" _
    Alias "GetLastError" () As SQLITE_C_UINT
Declare Function winDefaultWinMemGetProcessHeap StdCall Lib "kernel32" _
    Alias "GetProcessHeap" () As Any Ptr
Declare Function winDefaultWinMemHeapCreate StdCall Lib "kernel32" _
    Alias "HeapCreate" ( _
    ByVal options As SQLITE_C_UINT, _
    ByVal initialSize As SQLITE_SIZE_T, _
    ByVal maximumSize As SQLITE_SIZE_T _
) As Any Ptr
Declare Function winDefaultWinMemHeapDestroy StdCall Lib "kernel32" _
    Alias "HeapDestroy" (ByVal hHeap As Any Ptr) As SQLITE_C_INT
Declare Function winDefaultWinMemHeapAlloc StdCall Lib "kernel32" _
    Alias "HeapAlloc" ( _
    ByVal hHeap As Any Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal nByte As SQLITE_SIZE_T _
) As Any Ptr
Declare Function winDefaultWinMemHeapFree StdCall Lib "kernel32" _
    Alias "HeapFree" ( _
    ByVal hHeap As Any Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal pMemory As Any Ptr _
) As SQLITE_C_INT
Declare Function winDefaultWinMemHeapRealloc StdCall Lib "kernel32" _
    Alias "HeapReAlloc" ( _
    ByVal hHeap As Any Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal pMemory As Any Ptr, _
    ByVal nByte As SQLITE_SIZE_T _
) As Any Ptr
Declare Function winDefaultWinMemHeapSize StdCall Lib "kernel32" _
    Alias "HeapSize" ( _
    ByVal hHeap As Any Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal pMemory As Any Ptr _
) As SQLITE_SIZE_T
Declare Function winDefaultWinMemHeapValidate StdCall Lib "kernel32" _
    Alias "HeapValidate" ( _
    ByVal hHeap As Any Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal pMemory As Any Ptr _
) As SQLITE_C_INT
Declare Function winDefaultWinMemHeapCompact StdCall Lib "kernel32" _
    Alias "HeapCompact" ( _
    ByVal hHeap As Any Ptr, _
    ByVal flags As SQLITE_C_UINT _
) As SQLITE_C_UINT
#include once "sqlite3_os_win_syscall_dispatch.bi"
Declare Sub sqlite3DebugAssert CDecl Alias "sqlite3DebugAssert" ( _
    ByVal zExpression As Const ZString Ptr _
)

' SQLite's reset operation takes both allocator lifecycle mutexes before heap
' teardown. Heap API calls use the same override table as the Windows VFS.

#ifndef SQLITE_DEFAULT_CACHE_SIZE
#define SQLITE_DEFAULT_CACHE_SIZE -2000
#endif
#ifndef SQLITE_DEFAULT_PAGE_SIZE
#define SQLITE_DEFAULT_PAGE_SIZE 4096
#endif
#ifndef SQLITE_WIN32_HEAP_CREATE
#define SQLITE_WIN32_HEAP_CREATE 1
#endif
#ifndef SQLITE_WIN32_HEAP_MAX_INIT_SIZE
#define SQLITE_WIN32_HEAP_MAX_INIT_SIZE 4294967295ULL
#endif
#ifndef SQLITE_WIN32_HEAP_INIT_EXTRA
#define SQLITE_WIN32_HEAP_INIT_EXTRA 4194304
#endif
#ifndef SQLITE_WIN32_HEAP_MAX_SIZE
#define SQLITE_WIN32_HEAP_MAX_SIZE 0
#endif
#ifndef SQLITE_WIN32_HEAP_FLAGS
#define SQLITE_WIN32_HEAP_FLAGS 0
#endif
#ifndef SQLITE_WIN32_CACHE_SIZE
#if SQLITE_DEFAULT_CACHE_SIZE >= 0
#define SQLITE_WIN32_CACHE_SIZE SQLITE_DEFAULT_CACHE_SIZE
#else
#define SQLITE_WIN32_CACHE_SIZE (-SQLITE_DEFAULT_CACHE_SIZE)
#endif
#endif
#ifndef SQLITE_WIN32_MAX_CACHE_SIZE
#define SQLITE_WIN32_MAX_CACHE_SIZE ( _
    (SQLITE_WIN32_HEAP_MAX_INIT_SIZE - SQLITE_WIN32_HEAP_INIT_EXTRA) / _
    SQLITE_DEFAULT_PAGE_SIZE _
)
#endif
#if SQLITE_WIN32_CACHE_SIZE > SQLITE_WIN32_MAX_CACHE_SIZE
#undef SQLITE_WIN32_CACHE_SIZE
#define SQLITE_WIN32_CACHE_SIZE 2000
#endif
#ifndef SQLITE_WIN32_HEAP_INIT_SIZE
#define SQLITE_WIN32_HEAP_INIT_SIZE ( _
    SQLITE_WIN32_CACHE_SIZE * SQLITE_DEFAULT_PAGE_SIZE + _
    SQLITE_WIN32_HEAP_INIT_EXTRA _
)
#endif

#define SQLITE3_FB_WINMEM_MAGIC1 &H42B2830B
#define SQLITE3_FB_WINMEM_MAGIC2 &HBD4D7CF4
#define SQLITE3_FB_WINMEM_NO_ERROR 0

' -------------------------------------------------------------------------
' Windows heap state and callback declarations
' -------------------------------------------------------------------------

Private Type WinMemData
#ifndef NDEBUG
    magic1 As SQLITE_C_UINT
#endif
    hHeap As Any Ptr
    bOwned As SQLITE_C_INT
#ifndef NDEBUG
    magic2 As SQLITE_C_UINT
#endif
End Type

#ifndef NDEBUG
Private Dim Shared win_mem_data As WinMemData = Type<WinMemData>( _
    SQLITE3_FB_WINMEM_MAGIC1, 0, 0, SQLITE3_FB_WINMEM_MAGIC2 _
)
#else
Private Dim Shared win_mem_data As WinMemData = Type<WinMemData>(0, 0)
#endif

' -------------------------------------------------------------------------
' Heap invariants and callback table
' -------------------------------------------------------------------------

Private Sub winMemAssertMagic()
#if defined(SQLITE_DEBUG) AndAlso Not defined(NDEBUG)
    If win_mem_data.magic1 <> SQLITE3_FB_WINMEM_MAGIC1 Then _
        sqlite3DebugAssert("win_mem_data.magic1 == WINMEM_MAGIC1")
    If win_mem_data.magic2 <> SQLITE3_FB_WINMEM_MAGIC2 Then _
        sqlite3DebugAssert("win_mem_data.magic2 == WINMEM_MAGIC2")
#endif
End Sub

Private Sub winMemAssertHeapValid( _
    ByVal hHeap As Any Ptr, _
    ByVal pMemory As Any Ptr _
)
#if defined(SQLITE_DEBUG) AndAlso defined(SQLITE_WIN32_MALLOC_VALIDATE)
    If hHeap = 0 OrElse winMemHeapValidate( _
        hHeap, SQLITE_WIN32_HEAP_FLAGS, pMemory) = 0 Then _
        sqlite3DebugAssert("HeapValidate(hHeap, SQLITE_WIN32_HEAP_FLAGS, p)")
#endif
End Sub

' -------------------------------------------------------------------------
' Win32 heap allocator callbacks
' -------------------------------------------------------------------------

Private Function winMemMalloc CDecl Alias "winMemMalloc" ( _
    ByVal nBytes As SQLITE_C_INT _
) As Any Ptr
    winMemAssertMagic()
    If win_mem_data.hHeap = 0 OrElse nBytes < 0 Then Return 0
    winMemAssertHeapValid(win_mem_data.hHeap, 0)

    Dim pMemory As Any Ptr = winMemHeapAlloc( _
        win_mem_data.hHeap, SQLITE_WIN32_HEAP_FLAGS, _
        CULngInt(nBytes))
    If pMemory = 0 Then
        sqlite3_log(SQLITE_NOMEM, _
            "failed to HeapAlloc %u bytes (%lu), heap=%p", _
            nBytes, winMemGetLastError(), win_mem_data.hHeap)
    End If
    Return pMemory
End Function

Private Sub winMemFree CDecl Alias "winMemFree" ( _
    ByVal pPrior As Any Ptr _
)
    winMemAssertMagic()
    If win_mem_data.hHeap = 0 Then Exit Sub
    winMemAssertHeapValid(win_mem_data.hHeap, pPrior)
    ' HeapFree(NULL) is undefined on Windows. SQLite permits a null input.
    If pPrior = 0 Then Exit Sub

    If winMemHeapFree( _
        win_mem_data.hHeap, SQLITE_WIN32_HEAP_FLAGS, pPrior) = 0 Then
        sqlite3_log(SQLITE_NOMEM, _
            "failed to HeapFree block %p (%lu), heap=%p", _
            pPrior, winMemGetLastError(), win_mem_data.hHeap)
    End If
End Sub

Private Function winMemRealloc CDecl Alias "winMemRealloc" ( _
    ByVal pPrior As Any Ptr, _
    ByVal nBytes As SQLITE_C_INT _
) As Any Ptr
    winMemAssertMagic()
    If win_mem_data.hHeap = 0 OrElse nBytes < 0 Then Return 0
    winMemAssertHeapValid(win_mem_data.hHeap, pPrior)

    Dim pMemory As Any Ptr
    If pPrior = 0 Then
        pMemory = winMemHeapAlloc( _
            win_mem_data.hHeap, SQLITE_WIN32_HEAP_FLAGS, _
            CULngInt(nBytes))
    Else
        pMemory = winMemHeapRealloc( _
            win_mem_data.hHeap, SQLITE_WIN32_HEAP_FLAGS, pPrior, _
            CULngInt(nBytes))
    End If
    If pMemory = 0 Then
        Dim operation As Const ZString Ptr = IIf( _
            pPrior = 0, StrPtr("HeapAlloc"), StrPtr("HeapReAlloc"))
        sqlite3_log(SQLITE_NOMEM, _
            "failed to %s %u bytes (%lu), heap=%p", _
            operation, nBytes, winMemGetLastError(), win_mem_data.hHeap)
    End If
    Return pMemory
End Function

Private Function winMemSize CDecl Alias "winMemSize" ( _
    ByVal pMemory As Any Ptr _
) As SQLITE_C_INT
    winMemAssertMagic()
    If pMemory = 0 OrElse win_mem_data.hHeap = 0 Then Return 0
    winMemAssertHeapValid(win_mem_data.hHeap, pMemory)

    Dim byteCount As SQLITE_SIZE_T = winMemHeapSize( _
        win_mem_data.hHeap, SQLITE_WIN32_HEAP_FLAGS, pMemory)
    ' HeapSize reports failure with SIZE_T(-1).
    If byteCount = CULngInt(-1) Then
        sqlite3_log(SQLITE_NOMEM, _
            "failed to HeapSize block %p (%lu), heap=%p", _
            pMemory, winMemGetLastError(), win_mem_data.hHeap)
        Return 0
    End If
    ' xSize returns a signed C int, so reject sizes it cannot represent.
    If byteCount > &H7FFFFFFF Then Return 0
    Return CInt(byteCount)
End Function

Private Function winMemRoundup CDecl Alias "winMemRoundup" ( _
    ByVal nBytes As SQLITE_C_INT _
) As SQLITE_C_INT
    Return nBytes
End Function

' -------------------------------------------------------------------------
' Heap lifecycle and optional controls
' -------------------------------------------------------------------------

Private Function winMemInit CDecl Alias "winMemInit" ( _
    ByVal pAppData As Any Ptr _
) As SQLITE_C_INT
    If pAppData = 0 Then Return SQLITE_ERROR
    Dim pWinMemData As WinMemData Ptr = CPtr(WinMemData Ptr, pAppData)
#if defined(SQLITE_DEBUG) AndAlso Not defined(NDEBUG)
    If pWinMemData->magic1 <> SQLITE3_FB_WINMEM_MAGIC1 Then _
        sqlite3DebugAssert("pWinMemData->magic1 == WINMEM_MAGIC1")
    If pWinMemData->magic2 <> SQLITE3_FB_WINMEM_MAGIC2 Then _
        sqlite3DebugAssert("pWinMemData->magic2 == WINMEM_MAGIC2")
#endif

#if SQLITE_WIN32_HEAP_CREATE
    If pWinMemData->hHeap = 0 Then
        Dim initialSize As SQLITE_SIZE_T = SQLITE_WIN32_HEAP_INIT_SIZE
        Dim maximumSize As SQLITE_SIZE_T = SQLITE_WIN32_HEAP_MAX_SIZE
        Dim configuredHeapSize As SQLITE_C_INT = 0
        sqlite3ConfigGetHeap(0, @configuredHeapSize, 0)
        If configuredHeapSize <> 0 Then _
            maximumSize = CULngInt(CUInt(configuredHeapSize))
        If maximumSize <> 0 AndAlso initialSize > maximumSize Then _
            initialSize = maximumSize

        pWinMemData->hHeap = winMemHeapCreate( _
            SQLITE_WIN32_HEAP_FLAGS, initialSize, maximumSize)
        If pWinMemData->hHeap = 0 Then
            sqlite3_log(SQLITE_NOMEM, _
                "failed to HeapCreate (%lu), flags=%u, initSize=%lu, maxSize=%lu", _
                winMemGetLastError(), SQLITE_WIN32_HEAP_FLAGS, _
                initialSize, maximumSize)
            Return SQLITE_NOMEM
        End If
        pWinMemData->bOwned = 1
    End If
#else
    pWinMemData->hHeap = winMemGetProcessHeap()
    If pWinMemData->hHeap = 0 Then
        sqlite3_log(SQLITE_NOMEM, "failed to GetProcessHeap (%lu)", _
            winMemGetLastError())
        Return SQLITE_NOMEM
    End If
    pWinMemData->bOwned = 0
#endif

    If pWinMemData->hHeap = 0 Then Return SQLITE_NOMEM
    winMemAssertHeapValid(pWinMemData->hHeap, 0)
    Return SQLITE_OK
End Function

Private Sub winMemShutdown CDecl Alias "winMemShutdown" ( _
    ByVal pAppData As Any Ptr _
)
    If pAppData = 0 Then Exit Sub
    Dim pWinMemData As WinMemData Ptr = CPtr(WinMemData Ptr, pAppData)
#if defined(SQLITE_DEBUG) AndAlso Not defined(NDEBUG)
    If pWinMemData->magic1 <> SQLITE3_FB_WINMEM_MAGIC1 Then _
        sqlite3DebugAssert("pWinMemData->magic1 == WINMEM_MAGIC1")
    If pWinMemData->magic2 <> SQLITE3_FB_WINMEM_MAGIC2 Then _
        sqlite3DebugAssert("pWinMemData->magic2 == WINMEM_MAGIC2")
#endif

    If pWinMemData->hHeap <> 0 Then
        winMemAssertHeapValid(pWinMemData->hHeap, 0)
        If pWinMemData->bOwned <> 0 Then
            ' SQLite requires private-heap allocations to be gone at shutdown.
            If winMemHeapDestroy(pWinMemData->hHeap) = 0 Then
                sqlite3_log(SQLITE_NOMEM, _
                    "failed to HeapDestroy (%lu), heap=%p", _
                    winMemGetLastError(), pWinMemData->hHeap)
            End If
            pWinMemData->bOwned = 0
        End If
        pWinMemData->hHeap = 0
    End If
End Sub

Private Dim Shared As Const SqliteMemMethods winMemMethods = _
    Type<SqliteMemMethods>( _
        ProcPtr(winMemMalloc), _
        ProcPtr(winMemFree), _
        ProcPtr(winMemRealloc), _
        ProcPtr(winMemSize), _
        ProcPtr(winMemRoundup), _
        ProcPtr(winMemInit), _
        ProcPtr(winMemShutdown), _
        @win_mem_data _
    )

Function sqlite3MemGetWin32 CDecl Alias "sqlite3MemGetWin32" () _
    As Const SqliteMemMethods Ptr Export
    Return @winMemMethods
End Function

Function sqlite3_win32_compact_heap CDecl Alias "sqlite3_win32_compact_heap" ( _
    ByVal pnLargest As SQLITE_C_UINT Ptr _
) As SQLITE_C_INT Export
    If pnLargest <> 0 Then pnLargest[0] = 0
    winMemAssertMagic()
    If win_mem_data.hHeap = 0 Then Return SQLITE_ERROR
    winMemAssertHeapValid(win_mem_data.hHeap, 0)

    Dim largestBlock As SQLITE_C_UINT = winMemHeapCompact( _
        win_mem_data.hHeap, SQLITE_WIN32_HEAP_FLAGS)
    Dim rc As SQLITE_C_INT = SQLITE_OK
    If largestBlock = 0 Then
        Dim lastError As SQLITE_C_UINT = winMemGetLastError()
        If lastError = SQLITE3_FB_WINMEM_NO_ERROR Then
            sqlite3_log(SQLITE_NOMEM, _
                "failed to HeapCompact (no space), heap=%p", _
                win_mem_data.hHeap)
            rc = SQLITE_NOMEM
        Else
            sqlite3_log(SQLITE_ERROR, _
                "failed to HeapCompact (%lu), heap=%p", _
                lastError, win_mem_data.hHeap)
            rc = SQLITE_ERROR
        End If
    End If
    If pnLargest <> 0 Then
        ' The C source narrows this value to UINT before storing it.
        pnLargest[0] = CUInt(largestBlock)
    End If
    Return rc
End Function

Function sqlite3_win32_reset_heap CDecl Alias "sqlite3_win32_reset_heap" () _
    As SQLITE_C_INT Export
    Dim pMainMutex As Any Ptr = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MAIN)
    Dim pMemoryMutex As Any Ptr = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MEM)
    sqlite3_mutex_enter(pMainMutex)
    sqlite3_mutex_enter(pMemoryMutex)

    winMemAssertMagic()
    Dim rc As SQLITE_C_INT = SQLITE_BUSY
    If win_mem_data.hHeap <> 0 AndAlso win_mem_data.bOwned <> 0 AndAlso _
       sqlite3_memory_used() = 0 Then
        winMemShutdown(@win_mem_data)
        rc = winMemInit(@win_mem_data)
    End If

    sqlite3_mutex_leave(pMemoryMutex)
    sqlite3_mutex_leave(pMainMutex)
    Return rc
End Function

#endif
#endif

/' end of sqlite3_os_win_memory.bas '/
