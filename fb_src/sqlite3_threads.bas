/'
    Project: SQLite FreeBASIC port

    File: sqlite3_threads.bas

    Purpose:

        Implement the worker-thread interface from src/threads.c.

    Responsibilities:

        - Allocate per-task state through SQLite's allocator.
        - Run worker callbacks on pthreads or Windows threads when enabled.
        - Use the Win32 thread procedure and wait handle on Windows.
        - Run callbacks synchronously when workers are disabled or creation fails.
        - Join workers, return their result, and release task state.

    This file intentionally does NOT contain:

        - Test-only thread scheduling controls.
        - SQLite query-planner or VDBE worker task implementations.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_api_declarations.bi"
#include once "sqlite3_internal_api_declarations.bi"

#ifndef SQLITE_THREADSAFE
#define SQLITE_THREADSAFE 1
#endif

#if SQLITE_THREADSAFE > 0 AndAlso SQLITE_MAX_WORKER_THREADS > 0 AndAlso _
    defined(__FB_WIN32__)
#define SQLITE3_FB_WINDOWS_THREADS
#include once "crt/win32/process.bi"
#include once "win/winbase.bi"
#elseif SQLITE_THREADSAFE > 0 AndAlso SQLITE_MAX_WORKER_THREADS > 0 AndAlso _
       (defined(__FB_UNIX__) OrElse defined(__FB_DARWIN__)) AndAlso _
       Not defined(SQLITE_MUTEX_NOOP)
#define SQLITE3_FB_PTHREAD_THREADS
#endif

Declare Function sqlite3ConfigCoreMutexEnabled CDecl Alias "sqlite3ConfigCoreMutexEnabled" () As SQLITE_C_INT

Type SqliteThreadTask As Function CDecl (ByVal pInput As Any Ptr) As Any Ptr

Private Type SqliteThreadState
#ifdef SQLITE3_FB_WINDOWS_THREADS
    threadHandle As HANDLE
    threadId As ULong
    xTask As SqliteThreadTask
    pInput As Any Ptr
    pOutput As Any Ptr
#else
    threadId As SQLITE_C_ULONG
    done As SQLITE_C_INT
    pOutput As Any Ptr
    xTask As SqliteThreadTask
    pInput As Any Ptr
#endif
End Type

#ifdef SQLITE3_FB_PTHREAD_THREADS
Extern "C"
    Declare Function sqlite3PthreadCreate CDecl Alias "pthread_create" ( _
        ByVal pThreadId As SQLITE_C_ULONG Ptr, _
        ByVal pAttributes As Any Ptr, _
        ByVal xStart As SqliteThreadTask, _
        ByVal pArgument As Any Ptr _
    ) As SQLITE_C_INT
    Declare Function sqlite3PthreadJoin CDecl Alias "pthread_join" ( _
        ByVal threadId As SQLITE_C_ULONG, _
        ByVal ppOutput As Any Ptr Ptr _
    ) As SQLITE_C_INT
End Extern

Private Function sqlite3ThreadTrampoline CDecl ( _
    ByVal pArgument As Any Ptr _
) As Any Ptr
    If pArgument = 0 Then Return 0
    Dim pThread As SqliteThreadState Ptr = CPtr(SqliteThreadState Ptr, pArgument)
    If pThread->xTask = 0 Then Return 0
    pThread->pOutput = pThread->xTask(pThread->pInput)
    Return pThread->pOutput
End Function
#endif

#ifdef SQLITE3_FB_WINDOWS_THREADS
' Share os_win.c's alertable wait so APC handling stays consistent.
Declare Function sqlite3Win32Wait CDecl Alias "sqlite3Win32Wait" ( _
    ByVal hObject As HANDLE _
) As DWORD

Private Function sqlite3ThreadProc StdCall Alias "sqlite3ThreadProc" ( _
    ByVal pArgument As Any Ptr _
) As ULong
    If pArgument = 0 Then Return 0
    Dim pThread As SqliteThreadState Ptr = _
        CPtr(SqliteThreadState Ptr, pArgument)
    If pThread->xTask = 0 Then Return 0
    pThread->pOutput = pThread->xTask(pThread->pInput)
    _endthreadex(0)
    Return 0
End Function
#endif

Function sqlite3ThreadCreate CDecl Alias "sqlite3ThreadCreate" ( _
    ByVal ppThread As Any Ptr Ptr, _
    ByVal pTask As Any Ptr, _
    ByVal pInput As Any Ptr _
) As SQLITE_C_INT

    If ppThread = 0 OrElse pTask = 0 Then Return SQLITE_MISUSE
    ppThread[0] = 0
    Dim pThread As SqliteThreadState Ptr = CPtr(SqliteThreadState Ptr, _
        sqlite3Malloc(SizeOf(SqliteThreadState)))
    If pThread = 0 Then Return SQLITE_NOMEM

#ifdef SQLITE3_FB_WINDOWS_THREADS
    pThread->threadHandle = 0
    pThread->threadId = 0
    pThread->xTask = 0
    pThread->pInput = 0
    pThread->pOutput = 0
    If sqlite3ConfigCoreMutexEnabled() <> 0 AndAlso _
       sqlite3FaultSim(200) = 0 Then
        pThread->xTask = CPtr(SqliteThreadTask, pTask)
        pThread->pInput = pInput
        pThread->threadHandle = CPtr(Any Ptr, _
            _beginthreadex(0, 0, ProcPtr(sqlite3ThreadProc), _
                            pThread, 0, @pThread->threadId))
        If pThread->threadHandle = 0 Then
            pThread->xTask = 0
            pThread->pInput = 0
        End If
    End If
    If pThread->xTask = 0 Then
        pThread->threadId = GetCurrentThreadId()
        Dim xTask As SqliteThreadTask = CPtr(SqliteThreadTask, pTask)
        pThread->pOutput = xTask(pInput)
    End If
#elseif defined(SQLITE3_FB_PTHREAD_THREADS)
    pThread->threadId = 0
    pThread->done = 0
    pThread->pOutput = 0
    pThread->xTask = CPtr(SqliteThreadTask, pTask)
    pThread->pInput = pInput
    Dim createResult As SQLITE_C_INT
    If sqlite3FaultSim(200) <> 0 Then
        createResult = 1
    Else
        createResult = sqlite3PthreadCreate( _
            @pThread->threadId, 0, @sqlite3ThreadTrampoline, pThread)
    End If
    If createResult <> 0 Then
        pThread->done = 1
        pThread->pOutput = pThread->xTask(pThread->pInput)
    End If
#else
    pThread->threadId = 0
    pThread->done = 1
    pThread->pOutput = 0
    pThread->xTask = CPtr(SqliteThreadTask, pTask)
    pThread->pInput = pInput
    pThread->pOutput = pThread->xTask(pThread->pInput)
#endif

    ppThread[0] = pThread
    Return SQLITE_OK
End Function

Function sqlite3ThreadJoin CDecl Alias "sqlite3ThreadJoin" ( _
    ByVal pThreadArgument As Any Ptr, _
    ByVal ppOutput As Any Ptr Ptr _
) As SQLITE_C_INT

    If pThreadArgument = 0 OrElse ppOutput = 0 Then Return SQLITE_MISUSE
    Dim pThread As SqliteThreadState Ptr = _
        CPtr(SqliteThreadState Ptr, pThreadArgument)
    Dim rc As SQLITE_C_INT = SQLITE_OK
#ifdef SQLITE3_FB_WINDOWS_THREADS
    Dim waitResult As DWORD = WAIT_OBJECT_0
    If pThread->xTask = 0 Then
        ppOutput[0] = pThread->pOutput
    Else
        If pThread->threadHandle = 0 Then
            waitResult = &HFFFFFFFF
        Else
            waitResult = sqlite3Win32Wait(pThread->threadHandle)
            CloseHandle(pThread->threadHandle)
            pThread->threadHandle = 0
        End If
        If waitResult = WAIT_OBJECT_0 Then ppOutput[0] = pThread->pOutput
    End If
    If waitResult <> WAIT_OBJECT_0 Then rc = SQLITE_ERROR
#elseif defined(SQLITE3_FB_PTHREAD_THREADS)
    If pThread->done <> 0 Then
        ppOutput[0] = pThread->pOutput
    Else
        rc = sqlite3PthreadJoin(pThread->threadId, ppOutput)
    End If
#else
    If pThread->done <> 0 Then ppOutput[0] = pThread->pOutput
#endif
    sqlite3_free(pThread)
    If rc <> 0 Then Return SQLITE_ERROR
    Return SQLITE_OK
End Function

/' end of sqlite3_threads.bas '/
