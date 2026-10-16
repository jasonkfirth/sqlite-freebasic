/'
    Project: SQLite FreeBASIC port

    File: sqlite3_mutex.bas

    Purpose:

        Port SQLite's default mutex API using the host-specific
        Unix pthread or Windows synchronization backend.

    Responsibilities:

        - Route mutex calls through the selected callback table.
        - Implement recursive and fast dynamic mutexes for each host backend.
        - Provide the stable static mutex set used by SQLite subsystems.
        - Select Win32 critical-section and slim-reader/writer locks on Windows.
        - Wrap the default provider to report contention on shared NOMUTEX handles.
        - Copy and return custom mutex method tables supplied by sqlite3_config().
        - Preserve no-op mutex behavior when SQLITE_THREADSAFE is disabled.
        - Expose the no-op mutex callback table for SQLITE_MUTEX_NOOP builds.
        - Check allocation and enter/leave balance in single-thread debug builds.

    This file intentionally does NOT contain:

        - sqlite3_config() option dispatch for custom mutex methods.
        - OS-level memory barrier implementation; the Windows VFS helper owns it.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_mutex.bi"

#ifndef SQLITE_THREADSAFE
#define SQLITE_THREADSAFE 1
#endif
#if SQLITE_THREADSAFE > 0
#ifndef SQLITE_MUTEX_NOOP
#if defined(SQLITE_OS_WIN)
#define SQLITE3_FB_USE_WIN32_MUTEX
#elseif defined(__FB_UNIX__) OrElse defined(__FB_DARWIN__)
#define SQLITE3_FB_USE_PTHREAD_MUTEX
#else
#error "Thread-safe SQLite mutex support is currently available only on Unix and Windows targets."
#endif
#endif
#endif

Declare Function sqlite3MallocZero CDecl Alias "sqlite3MallocZero" ( _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)

Type SqliteMutexInitCallback As Function CDecl () As SQLITE_C_INT
Type SqliteMutexAllocCallback As Function CDecl ( _
    ByVal mutexType As SQLITE_C_INT _
) As Any Ptr
Type SqliteMutexVoidCallback As Sub CDecl (ByVal pMutex As Any Ptr)
Type SqliteMutexTryCallback As Function CDecl ( _
    ByVal pMutex As Any Ptr _
) As SQLITE_C_INT
Type SqliteMutexCheckCallback As Function CDecl ( _
    ByVal pMutex As Any Ptr _
) As SQLITE_C_INT

Declare Function sqlite3ConfigCoreMutexEnabled CDecl Alias "sqlite3ConfigCoreMutexEnabled" () As SQLITE_C_INT
Declare Function sqlite3DefaultMutex CDecl Alias "sqlite3DefaultMutex" () As Any Ptr
Declare Function sqlite3NoopMutex CDecl Alias "sqlite3NoopMutex" () As Any Ptr

' sqlite3_mutex_methods is nine C callback pointers in public-header order.
Private Type SqliteMutexMethodTable
    xMutexInit As SqliteMutexInitCallback
    xMutexEnd As SqliteMutexInitCallback
    xMutexAlloc As SqliteMutexAllocCallback
    xMutexFree As SqliteMutexVoidCallback
    xMutexEnter As SqliteMutexVoidCallback
    xMutexTry As SqliteMutexTryCallback
    xMutexLeave As SqliteMutexVoidCallback
    xMutexHeld As SqliteMutexCheckCallback
    xMutexNotheld As SqliteMutexCheckCallback
End Type

Private Dim Shared sqlite3EmptyMutexMethods As SqliteMutexMethodTable = _
    Type<SqliteMutexMethodTable>( _
        Cast(SqliteMutexInitCallback, 0), _
        Cast(SqliteMutexInitCallback, 0), _
        Cast(SqliteMutexAllocCallback, 0), _
        Cast(SqliteMutexVoidCallback, 0), _
        Cast(SqliteMutexVoidCallback, 0), _
        Cast(SqliteMutexTryCallback, 0), _
        Cast(SqliteMutexVoidCallback, 0), _
        Cast(SqliteMutexCheckCallback, 0), _
        Cast(SqliteMutexCheckCallback, 0))

Private Dim Shared sqlite3ActiveMutexMethods As SqliteMutexMethodTable Ptr
Private Dim Shared sqlite3CustomMutexMethods As SqliteMutexMethodTable

Function sqlite3MutexConfigSetMethods CDecl Alias "sqlite3MutexConfigSetMethods" ( _
    ByVal pMethods As Any Ptr _
) As SQLITE_C_INT Export
    If pMethods = 0 Then
        sqlite3CustomMutexMethods = sqlite3EmptyMutexMethods
        sqlite3ActiveMutexMethods = 0
        Return SQLITE_OK
    End If

    Dim pSource As SqliteMutexMethodTable Ptr = _
        CPtr(SqliteMutexMethodTable Ptr, pMethods)
    Dim candidate As SqliteMutexMethodTable = pSource[0]
    If candidate.xMutexInit = 0 OrElse candidate.xMutexEnd = 0 OrElse _
       candidate.xMutexAlloc = 0 OrElse candidate.xMutexFree = 0 OrElse _
       candidate.xMutexEnter = 0 OrElse candidate.xMutexTry = 0 OrElse _
       candidate.xMutexLeave = 0 Then Return SQLITE_MISUSE

    sqlite3CustomMutexMethods = candidate
    sqlite3ActiveMutexMethods = @sqlite3CustomMutexMethods
    Return SQLITE_OK
End Function

Sub sqlite3MutexConfigGetMethods CDecl Alias "sqlite3MutexConfigGetMethods" ( _
    ByVal pMethods As Any Ptr _
) Export
    If pMethods = 0 Then Exit Sub
    Dim pDestination As SqliteMutexMethodTable Ptr = _
        CPtr(SqliteMutexMethodTable Ptr, pMethods)
    If sqlite3ActiveMutexMethods = 0 Then
        pDestination[0] = sqlite3EmptyMutexMethods
    Else
        pDestination[0] = sqlite3ActiveMutexMethods[0]
    End If
End Sub

#ifdef SQLITE_THREAD_MISUSE_WARNINGS
Private Const SQLITE_MUTEX_WARNONCONTENTION As SQLITE_C_INT = -1

Private Type SqliteCheckMutex
    mutexType As SQLITE_C_INT
    pMutex As Any Ptr
End Type

Private Dim Shared sqlite3CheckMutexStatic(0 To 11) As SqliteCheckMutex
Private Dim Shared sqlite3CheckMutexBaseMethods As SqliteMutexMethodTable Ptr

Declare Function checkMutexHeld CDecl Alias "checkMutexHeld" ( _
    ByVal pMutex As Any Ptr _
) As SQLITE_C_INT
Declare Function checkMutexNotheld CDecl Alias "checkMutexNotheld" ( _
    ByVal pMutex As Any Ptr _
) As SQLITE_C_INT
Declare Function checkMutexInit CDecl Alias "checkMutexInit" () As SQLITE_C_INT
Declare Function checkMutexEnd CDecl Alias "checkMutexEnd" () As SQLITE_C_INT
Declare Function checkMutexAlloc CDecl Alias "checkMutexAlloc" ( _
    ByVal mutexType As SQLITE_C_INT _
) As Any Ptr
Declare Sub checkMutexFree CDecl Alias "checkMutexFree" (ByVal pMutex As Any Ptr)
Declare Sub checkMutexEnter CDecl Alias "checkMutexEnter" (ByVal pMutex As Any Ptr)
Declare Function checkMutexTry CDecl Alias "checkMutexTry" ( _
    ByVal pMutex As Any Ptr _
) As SQLITE_C_INT
Declare Sub checkMutexLeave CDecl Alias "checkMutexLeave" (ByVal pMutex As Any Ptr)
Declare Function multiThreadedCheckMutex CDecl Alias "multiThreadedCheckMutex" () As Any Ptr
Declare Sub sqlite3MutexWarnOnContention CDecl Alias "sqlite3MutexWarnOnContention" ( _
    ByVal pMutex As Any Ptr _
)
Declare Function sqlite3MisuseError CDecl Alias "sqlite3MisuseError" ( _
    ByVal lineNumber As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Sub sqlite3_log CDecl Alias "sqlite3_log" ( _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
#ifdef SQLITE_THREAD_MISUSE_ABORT
#if SQLITE_THREAD_MISUSE_ABORT
Extern "C"
    Declare Sub sqlite3MutexAbort CDecl Alias "abort" ()
End Extern
#endif
#endif
#endif

#ifdef SQLITE3_FB_USE_WIN32_MUTEX
#include once "sqlite3_mutex_windows.bi"
#else
#ifdef SQLITE3_FB_USE_PTHREAD_MUTEX
#if defined(__FB_UNIX__) OrElse defined(__FB_DARWIN__)
#include once "crt/pthread.bi"

Private Function pthreadMutexEnd CDecl Alias "pthreadMutexEnd" () As SQLITE_C_INT
    Return SQLITE_OK
End Function

Private Type SqliteMutex
    native As pthread_mutex_t
    mutexType As SQLITE_C_INT
    refCount As SQLITE_C_INT
    owner As pthread_t
End Type

Private Const SQLITE_MUTEX_STATIC_COUNT As Long = 12
Dim Shared sqlite3StaticMutexes(0 To SQLITE_MUTEX_STATIC_COUNT - 1) As SqliteMutex
Dim Shared sqlite3BarrierMutex As pthread_mutex_t
Dim Shared sqlite3MutexOnceControl As pthread_once_t
Dim Shared sqlite3MutexInitResult As SQLITE_C_INT = SQLITE_OK

Private Sub sqlite3InitializeStaticMutexes CDecl ()
    Dim initializedCount As Long = 0
    For i As Long = 0 To SQLITE_MUTEX_STATIC_COUNT - 1
        Dim rc As SQLITE_C_INT = pthread_mutex_init(@sqlite3StaticMutexes(i).native, 0)
        If rc <> 0 Then
            sqlite3MutexInitResult = SQLITE_ERROR
            For j As Long = 0 To initializedCount - 1
                pthread_mutex_destroy(@sqlite3StaticMutexes(j).native)
            Next
            Exit Sub
        End If
        sqlite3StaticMutexes(i).mutexType = SQLITE_MUTEX_STATIC_MAIN + i
        initializedCount += 1
    Next

    If pthread_mutex_init(@sqlite3BarrierMutex, 0) <> 0 Then
        sqlite3MutexInitResult = SQLITE_ERROR
        For j As Long = 0 To SQLITE_MUTEX_STATIC_COUNT - 1
            pthread_mutex_destroy(@sqlite3StaticMutexes(j).native)
        Next
        Exit Sub
    End If
    sqlite3MutexInitResult = SQLITE_OK
End Sub

Private Function pthreadMutexInit CDecl Alias "pthreadMutexInit" () As SQLITE_C_INT
    If pthread_once(@sqlite3MutexOnceControl, @sqlite3InitializeStaticMutexes) <> 0 Then _
        Return SQLITE_ERROR
    Return sqlite3MutexInitResult
End Function

Function sqlite3MutexInit CDecl Alias "sqlite3MutexInit" () As SQLITE_C_INT Export
    If sqlite3ActiveMutexMethods = 0 Then
        If sqlite3ConfigCoreMutexEnabled() = 0 Then
            sqlite3ActiveMutexMethods = CPtr(SqliteMutexMethodTable Ptr, _
                sqlite3NoopMutex())
        Else
#ifdef SQLITE_THREAD_MISUSE_WARNINGS
            sqlite3ActiveMutexMethods = CPtr(SqliteMutexMethodTable Ptr, _
                multiThreadedCheckMutex())
#else
            sqlite3ActiveMutexMethods = CPtr(SqliteMutexMethodTable Ptr, _
                sqlite3DefaultMutex())
#endif
        End If
    End If
    If sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexInit = 0 Then Return SQLITE_MISUSE
    Return sqlite3ActiveMutexMethods->xMutexInit()
End Function

Function sqlite3MutexEnd CDecl Alias "sqlite3MutexEnd" () As SQLITE_C_INT Export
    If sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexEnd = 0 Then Return SQLITE_OK
    Return sqlite3ActiveMutexMethods->xMutexEnd()
End Function

Function sqlite3_mutex_alloc CDecl Alias "sqlite3_mutex_alloc" ( _
    ByVal mutexType As SQLITE_C_INT _
) As Any Ptr Export
    If sqlite3MutexInit() <> SQLITE_OK Then Return 0
    If sqlite3ActiveMutexMethods->xMutexAlloc = 0 Then Return 0
    Return sqlite3ActiveMutexMethods->xMutexAlloc(mutexType)
End Function

Function sqlite3MutexAlloc CDecl Alias "sqlite3MutexAlloc" ( _
    ByVal mutexType As SQLITE_C_INT _
) As Any Ptr Export
    If sqlite3ConfigCoreMutexEnabled() = 0 Then Return 0
    If sqlite3MutexInit() <> SQLITE_OK OrElse _
       sqlite3ActiveMutexMethods->xMutexAlloc = 0 Then Return 0
    Return sqlite3ActiveMutexMethods->xMutexAlloc(mutexType)
End Function

Sub sqlite3_mutex_free CDecl Alias "sqlite3_mutex_free" ( _
    ByVal pArgument As Any Ptr _
) Export
    If pArgument = 0 OrElse sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexFree = 0 Then Exit Sub
    sqlite3ActiveMutexMethods->xMutexFree(pArgument)
End Sub

Sub sqlite3_mutex_enter CDecl Alias "sqlite3_mutex_enter" ( _
    ByVal pArgument As Any Ptr _
) Export
    If pArgument = 0 OrElse sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexEnter = 0 Then Exit Sub
    sqlite3ActiveMutexMethods->xMutexEnter(pArgument)
End Sub

Function sqlite3_mutex_try CDecl Alias "sqlite3_mutex_try" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export
    If pArgument = 0 Then Return SQLITE_OK
    If sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexTry = 0 Then Return SQLITE_MISUSE
    Return sqlite3ActiveMutexMethods->xMutexTry(pArgument)
End Function

Sub sqlite3_mutex_leave CDecl Alias "sqlite3_mutex_leave" ( _
    ByVal pArgument As Any Ptr _
) Export
    If pArgument = 0 OrElse sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexLeave = 0 Then Exit Sub
    sqlite3ActiveMutexMethods->xMutexLeave(pArgument)
End Sub

Function sqlite3_mutex_held CDecl Alias "sqlite3_mutex_held" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export
    If pArgument = 0 OrElse sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexHeld = 0 Then Return 1
    Return sqlite3ActiveMutexMethods->xMutexHeld(pArgument)
End Function

Function sqlite3_mutex_notheld CDecl Alias "sqlite3_mutex_notheld" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export
    If pArgument = 0 OrElse sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexNotheld = 0 Then Return 1
    Return sqlite3ActiveMutexMethods->xMutexNotheld(pArgument)
End Function

Private Function pthreadMutexAlloc CDecl Alias "pthreadMutexAlloc" ( _
    ByVal mutexType As SQLITE_C_INT _
) As Any Ptr
    If pthread_once(@sqlite3MutexOnceControl, @sqlite3InitializeStaticMutexes) <> 0 OrElse _
       sqlite3MutexInitResult <> SQLITE_OK Then Return 0
    If mutexType >= SQLITE_MUTEX_STATIC_MAIN AndAlso _
       mutexType <= SQLITE_MUTEX_STATIC_VFS3 Then
        Return @sqlite3StaticMutexes(mutexType - SQLITE_MUTEX_STATIC_MAIN)
    End If
    If mutexType <> SQLITE_MUTEX_FAST AndAlso mutexType <> SQLITE_MUTEX_RECURSIVE Then Return 0

    Dim pMutex As SqliteMutex Ptr = CPtr(SqliteMutex Ptr, _
        sqlite3MallocZero(SizeOf(SqliteMutex)))
    If pMutex = 0 Then Return 0
    pMutex->mutexType = mutexType

    Dim rc As SQLITE_C_INT
    If mutexType = SQLITE_MUTEX_RECURSIVE Then
        Dim attributes As pthread_mutexattr_t
        rc = pthread_mutexattr_init(@attributes)
        If rc = 0 Then
            rc = pthread_mutexattr_settype(@attributes, PTHREAD_MUTEX_RECURSIVE)
            If rc = 0 Then rc = pthread_mutex_init(@pMutex->native, @attributes)
            pthread_mutexattr_destroy(@attributes)
        End If
    Else
        rc = pthread_mutex_init(@pMutex->native, 0)
    End If
    If rc <> 0 Then
        sqlite3_free(pMutex)
        Return 0
    End If
    Return pMutex
End Function

Private Sub pthreadMutexFree CDecl Alias "pthreadMutexFree" ( _
    ByVal pMutex As Any Ptr _
)
    If pMutex = 0 Then Exit Sub
    Dim pMutexRecord As SqliteMutex Ptr = CPtr(SqliteMutex Ptr, pMutex)
    If pMutexRecord->mutexType >= SQLITE_MUTEX_STATIC_MAIN Then Exit Sub
    If pMutexRecord->refCount <> 0 Then Exit Sub
    pthread_mutex_destroy(@pMutexRecord->native)
    sqlite3_free(pMutexRecord)
End Sub

Private Sub pthreadMutexEnter CDecl Alias "pthreadMutexEnter" ( _
    ByVal pMutex As Any Ptr _
)
    If pMutex = 0 Then Exit Sub
    Dim pMutexRecord As SqliteMutex Ptr = CPtr(SqliteMutex Ptr, pMutex)
    If pthread_mutex_lock(@pMutexRecord->native) <> 0 Then Exit Sub
    If pMutexRecord->refCount = 0 Then pMutexRecord->owner = pthread_self()
    pMutexRecord->refCount += 1
End Sub

Private Function pthreadMutexTry CDecl Alias "pthreadMutexTry" ( _
    ByVal pMutex As Any Ptr _
) As SQLITE_C_INT
    If pMutex = 0 Then Return SQLITE_OK
    Dim pMutexRecord As SqliteMutex Ptr = CPtr(SqliteMutex Ptr, pMutex)
    If pthread_mutex_trylock(@pMutexRecord->native) <> 0 Then Return SQLITE_BUSY
    If pMutexRecord->refCount = 0 Then pMutexRecord->owner = pthread_self()
    pMutexRecord->refCount += 1
    Return SQLITE_OK
End Function

Private Sub pthreadMutexLeave CDecl Alias "pthreadMutexLeave" ( _
    ByVal pMutex As Any Ptr _
)
    If pMutex = 0 Then Exit Sub
    Dim pMutexRecord As SqliteMutex Ptr = CPtr(SqliteMutex Ptr, pMutex)
    If pMutexRecord->refCount <= 0 Then Exit Sub
    If pthread_equal(pMutexRecord->owner, pthread_self()) = 0 Then Exit Sub
    pMutexRecord->refCount -= 1
    If pMutexRecord->refCount = 0 Then pMutexRecord->owner = 0
    pthread_mutex_unlock(@pMutexRecord->native)
End Sub

Private Function pthreadMutexHeld CDecl Alias "pthreadMutexHeld" ( _
    ByVal pMutex As Any Ptr _
) As SQLITE_C_INT
    If pMutex = 0 Then Return 1
    Dim pMutexRecord As SqliteMutex Ptr = CPtr(SqliteMutex Ptr, pMutex)
    If pMutexRecord->refCount = 0 Then Return 0
    Return IIf(pthread_equal(pMutexRecord->owner, pthread_self()) <> 0, 1, 0)
End Function

Private Function pthreadMutexNotheld CDecl Alias "pthreadMutexNotheld" ( _
    ByVal pMutex As Any Ptr _
) As SQLITE_C_INT
    If pMutex = 0 Then Return 1
    Dim pMutexRecord As SqliteMutex Ptr = CPtr(SqliteMutex Ptr, pMutex)
    If pMutexRecord->refCount = 0 Then Return 1
    Return IIf(pthread_equal(pMutexRecord->owner, pthread_self()) = 0, 1, 0)
End Function

' SQLite's default mutex provider returns this static callback table.
#ifdef SQLITE_DEBUG
Private Dim Shared sqlite3PthreadMutexMethods As SqliteMutexMethodTable = _
    Type<SqliteMutexMethodTable>( _
        ProcPtr(pthreadMutexInit), _
        ProcPtr(pthreadMutexEnd), _
        ProcPtr(pthreadMutexAlloc), _
        ProcPtr(pthreadMutexFree), _
        ProcPtr(pthreadMutexEnter), _
        ProcPtr(pthreadMutexTry), _
        ProcPtr(pthreadMutexLeave), _
        ProcPtr(pthreadMutexHeld), _
        ProcPtr(pthreadMutexNotheld))
#else
Private Dim Shared sqlite3PthreadMutexMethods As SqliteMutexMethodTable = _
    Type<SqliteMutexMethodTable>( _
        ProcPtr(pthreadMutexInit), _
        ProcPtr(pthreadMutexEnd), _
        ProcPtr(pthreadMutexAlloc), _
        ProcPtr(pthreadMutexFree), _
        ProcPtr(pthreadMutexEnter), _
        ProcPtr(pthreadMutexTry), _
        ProcPtr(pthreadMutexLeave), _
        Cast(SqliteMutexCheckCallback, 0), _
        Cast(SqliteMutexCheckCallback, 0))
#endif

Function sqlite3DefaultMutex CDecl Alias "sqlite3DefaultMutex" () As Any Ptr
    Return @sqlite3PthreadMutexMethods
End Function

Private Function noopMutexInit CDecl Alias "noopMutexInit" () As SQLITE_C_INT
    Return SQLITE_OK
End Function

Private Function noopMutexEnd CDecl Alias "noopMutexEnd" () As SQLITE_C_INT
    Return SQLITE_OK
End Function

Private Function noopMutexAlloc CDecl Alias "noopMutexAlloc" ( _
    ByVal mutexType As SQLITE_C_INT _
) As Any Ptr
    If mutexType < SQLITE_MUTEX_FAST OrElse _
       mutexType > SQLITE_MUTEX_STATIC_VFS3 Then Return 0
    Return CPtr(Any Ptr, 8)
End Function

Private Sub noopMutexFree CDecl Alias "noopMutexFree" (ByVal pMutex As Any Ptr)
End Sub

Private Sub noopMutexEnter CDecl Alias "noopMutexEnter" (ByVal pMutex As Any Ptr)
End Sub

Private Function noopMutexTry CDecl Alias "noopMutexTry" ( _
    ByVal pMutex As Any Ptr _
) As SQLITE_C_INT
    Return SQLITE_OK
End Function

Private Sub noopMutexLeave CDecl Alias "noopMutexLeave" (ByVal pMutex As Any Ptr)
End Sub

Private Function noopMutexHeld CDecl Alias "noopMutexHeld" ( _
    ByVal pMutex As Any Ptr _
) As SQLITE_C_INT
    Return 1
End Function

Private Function noopMutexNotheld CDecl Alias "noopMutexNotheld" ( _
    ByVal pMutex As Any Ptr _
) As SQLITE_C_INT
    Return 1
End Function

Private Dim Shared sqlite3NoopMutexMethods As SqliteMutexMethodTable = _
    Type<SqliteMutexMethodTable>( _
        ProcPtr(noopMutexInit), _
        ProcPtr(noopMutexEnd), _
        ProcPtr(noopMutexAlloc), _
        ProcPtr(noopMutexFree), _
        ProcPtr(noopMutexEnter), _
        ProcPtr(noopMutexTry), _
        ProcPtr(noopMutexLeave), _
        ProcPtr(noopMutexHeld), _
        ProcPtr(noopMutexNotheld))

Function sqlite3NoopMutex CDecl Alias "sqlite3NoopMutex" () As Any Ptr
    Return @sqlite3NoopMutexMethods
End Function

#ifdef SQLITE_THREAD_MISUSE_WARNINGS
Private Function checkMutexInit CDecl Alias "checkMutexInit" () As SQLITE_C_INT
    sqlite3CheckMutexBaseMethods = CPtr(SqliteMutexMethodTable Ptr, _
        sqlite3DefaultMutex())
    If sqlite3CheckMutexBaseMethods = 0 OrElse _
       sqlite3CheckMutexBaseMethods->xMutexInit = 0 Then Return SQLITE_MISUSE
    Return sqlite3CheckMutexBaseMethods->xMutexInit()
End Function

Private Function checkMutexEnd CDecl Alias "checkMutexEnd" () As SQLITE_C_INT
    If sqlite3CheckMutexBaseMethods = 0 OrElse _
       sqlite3CheckMutexBaseMethods->xMutexEnd = 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = sqlite3CheckMutexBaseMethods->xMutexEnd()
    sqlite3CheckMutexBaseMethods = 0
    Return rc
End Function

Private Function checkMutexAlloc CDecl Alias "checkMutexAlloc" ( _
    ByVal mutexType As SQLITE_C_INT _
) As Any Ptr
    If sqlite3CheckMutexBaseMethods = 0 Then
        If checkMutexInit() <> SQLITE_OK Then Return 0
    End If
    If sqlite3CheckMutexBaseMethods->xMutexAlloc = 0 Then Return 0

    Dim pCheck As SqliteCheckMutex Ptr
    If mutexType < SQLITE_MUTEX_STATIC_MAIN Then
        pCheck = CPtr(SqliteCheckMutex Ptr, _
            sqlite3MallocZero(SizeOf(SqliteCheckMutex)))
        If pCheck = 0 Then Return 0
        pCheck->mutexType = mutexType
    Else
        Dim staticIndex As SQLITE_C_INT = mutexType - SQLITE_MUTEX_STATIC_MAIN
        If staticIndex < 0 OrElse staticIndex >= SizeOf(sqlite3CheckMutexStatic) / _
           SizeOf(SqliteCheckMutex) Then
#ifdef SQLITE_ENABLE_API_ARMOR
            sqlite3MisuseError(__LINE__)
#endif
            Return 0
        End If
        pCheck = @sqlite3CheckMutexStatic(staticIndex)
        pCheck->mutexType = mutexType
    End If

    If pCheck->pMutex = 0 Then
        pCheck->pMutex = sqlite3CheckMutexBaseMethods->xMutexAlloc(mutexType)
        If pCheck->pMutex = 0 Then
            If mutexType < SQLITE_MUTEX_STATIC_MAIN Then sqlite3_free(pCheck)
            Return 0
        End If
    End If
    Return pCheck
End Function

Private Sub checkMutexFree CDecl Alias "checkMutexFree" ( _
    ByVal pArgument As Any Ptr _
)
    If pArgument = 0 Then Exit Sub
    Dim pCheck As SqliteCheckMutex Ptr = CPtr(SqliteCheckMutex Ptr, pArgument)
    If pCheck->mutexType >= SQLITE_MUTEX_STATIC_MAIN Then
#ifdef SQLITE_ENABLE_API_ARMOR
        sqlite3MisuseError(__LINE__)
#endif
        Exit Sub
    End If
    If sqlite3CheckMutexBaseMethods = 0 OrElse _
       sqlite3CheckMutexBaseMethods->xMutexFree = 0 Then Exit Sub
    sqlite3CheckMutexBaseMethods->xMutexFree(pCheck->pMutex)
    sqlite3_free(pCheck)
End Sub

Private Sub checkMutexEnter CDecl Alias "checkMutexEnter" ( _
    ByVal pArgument As Any Ptr _
)
    If pArgument = 0 OrElse sqlite3CheckMutexBaseMethods = 0 Then Exit Sub
    Dim pCheck As SqliteCheckMutex Ptr = CPtr(SqliteCheckMutex Ptr, pArgument)
    If pCheck->mutexType = SQLITE_MUTEX_WARNONCONTENTION Then
        If sqlite3CheckMutexBaseMethods->xMutexTry(pCheck->pMutex) = SQLITE_OK Then Exit Sub
        sqlite3_log(SQLITE_MISUSE, StrPtr( _
            "illegal multi-threaded access to database connection"))
#ifdef SQLITE_THREAD_MISUSE_ABORT
#if SQLITE_THREAD_MISUSE_ABORT
        sqlite3MutexAbort()
#endif
#endif
    End If
    If sqlite3CheckMutexBaseMethods->xMutexEnter <> 0 Then _
        sqlite3CheckMutexBaseMethods->xMutexEnter(pCheck->pMutex)
End Sub

Private Function checkMutexTry CDecl Alias "checkMutexTry" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT
    If pArgument = 0 OrElse sqlite3CheckMutexBaseMethods = 0 OrElse _
       sqlite3CheckMutexBaseMethods->xMutexTry = 0 Then Return SQLITE_MISUSE
    Dim pCheck As SqliteCheckMutex Ptr = CPtr(SqliteCheckMutex Ptr, pArgument)
    Return sqlite3CheckMutexBaseMethods->xMutexTry(pCheck->pMutex)
End Function

Private Sub checkMutexLeave CDecl Alias "checkMutexLeave" ( _
    ByVal pArgument As Any Ptr _
)
    If pArgument = 0 OrElse sqlite3CheckMutexBaseMethods = 0 OrElse _
       sqlite3CheckMutexBaseMethods->xMutexLeave = 0 Then Exit Sub
    Dim pCheck As SqliteCheckMutex Ptr = CPtr(SqliteCheckMutex Ptr, pArgument)
    sqlite3CheckMutexBaseMethods->xMutexLeave(pCheck->pMutex)
End Sub

#ifdef SQLITE_DEBUG
Private Function checkMutexHeld CDecl Alias "checkMutexHeld" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT
    If pArgument = 0 Then Return 1
    If sqlite3CheckMutexBaseMethods = 0 OrElse _
       sqlite3CheckMutexBaseMethods->xMutexHeld = 0 Then Return 1
    Dim pCheck As SqliteCheckMutex Ptr = CPtr(SqliteCheckMutex Ptr, pArgument)
    Return sqlite3CheckMutexBaseMethods->xMutexHeld(pCheck->pMutex)
End Function

Private Function checkMutexNotheld CDecl Alias "checkMutexNotheld" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT
    If pArgument = 0 Then Return 1
    If sqlite3CheckMutexBaseMethods = 0 OrElse _
       sqlite3CheckMutexBaseMethods->xMutexNotheld = 0 Then Return 1
    Dim pCheck As SqliteCheckMutex Ptr = CPtr(SqliteCheckMutex Ptr, pArgument)
    Return sqlite3CheckMutexBaseMethods->xMutexNotheld(pCheck->pMutex)
End Function
#endif

#ifdef SQLITE_DEBUG
Private Dim Shared sqlite3CheckMutexMethods As SqliteMutexMethodTable = _
    Type<SqliteMutexMethodTable>( _
        ProcPtr(checkMutexInit), _
        ProcPtr(checkMutexEnd), _
        ProcPtr(checkMutexAlloc), _
        ProcPtr(checkMutexFree), _
        ProcPtr(checkMutexEnter), _
        ProcPtr(checkMutexTry), _
        ProcPtr(checkMutexLeave), _
        ProcPtr(checkMutexHeld), _
        ProcPtr(checkMutexNotheld))
#else
Private Dim Shared sqlite3CheckMutexMethods As SqliteMutexMethodTable = _
    Type<SqliteMutexMethodTable>( _
        ProcPtr(checkMutexInit), _
        ProcPtr(checkMutexEnd), _
        ProcPtr(checkMutexAlloc), _
        ProcPtr(checkMutexFree), _
        ProcPtr(checkMutexEnter), _
        ProcPtr(checkMutexTry), _
        ProcPtr(checkMutexLeave), _
        Cast(SqliteMutexCheckCallback, 0), _
        Cast(SqliteMutexCheckCallback, 0))
#endif

Function multiThreadedCheckMutex CDecl Alias "multiThreadedCheckMutex" () As Any Ptr Export
    Return @sqlite3CheckMutexMethods
End Function

Sub sqlite3MutexWarnOnContention CDecl Alias "sqlite3MutexWarnOnContention" ( _
    ByVal pArgument As Any Ptr _
) Export
    If sqlite3ConfigCoreMutexEnabled() = 0 OrElse pArgument = 0 OrElse _
       sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexAlloc <> ProcPtr(checkMutexAlloc) Then Return
    Dim pCheck As SqliteCheckMutex Ptr = CPtr(SqliteCheckMutex Ptr, pArgument)
    If pCheck->mutexType = SQLITE_MUTEX_RECURSIVE Then _
        pCheck->mutexType = SQLITE_MUTEX_WARNONCONTENTION
End Sub
#endif

Sub sqlite3MemoryBarrier CDecl Alias "sqlite3MemoryBarrier" () Export
    If pthread_once(@sqlite3MutexOnceControl, @sqlite3InitializeStaticMutexes) <> 0 OrElse _
       sqlite3MutexInitResult <> SQLITE_OK Then Exit Sub
    pthread_mutex_lock(@sqlite3BarrierMutex)
    pthread_mutex_unlock(@sqlite3BarrierMutex)
End Sub

#else
#error "Thread-safe SQLite mutex support is currently available only on Unix targets."
#endif
#else

#ifdef SQLITE_DEBUG

' This backend tracks ownership counts in debug builds while remaining single-threaded.
Private Type SqliteDebugMutex
    mutexType As SQLITE_C_INT
    entryCount As SQLITE_C_INT
End Type

Private Const SQLITE_MUTEX_STATIC_COUNT As Long = SQLITE_MUTEX_STATIC_VFS3 - 1
Dim Shared sqlite3DebugStaticMutexes(0 To SQLITE_MUTEX_STATIC_COUNT - 1) As SqliteDebugMutex

Private Function debugMutexHeld CDecl Alias "debugMutexHeld" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT
    If pArgument = 0 Then Return 1
    Dim pMutex As SqliteDebugMutex Ptr = CPtr(SqliteDebugMutex Ptr, pArgument)
    Return IIf(pMutex->entryCount > 0, 1, 0)
End Function

Private Function debugMutexNotheld CDecl Alias "debugMutexNotheld" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT
    If pArgument = 0 Then Return 1
    Dim pMutex As SqliteDebugMutex Ptr = CPtr(SqliteDebugMutex Ptr, pArgument)
    Return IIf(pMutex->entryCount = 0, 1, 0)
End Function

Private Function debugMutexInit CDecl Alias "debugMutexInit" () As SQLITE_C_INT
    Return SQLITE_OK
End Function

Private Function debugMutexEnd CDecl Alias "debugMutexEnd" () As SQLITE_C_INT
    Return SQLITE_OK
End Function

Private Function debugMutexAlloc CDecl Alias "debugMutexAlloc" ( _
    ByVal mutexType As SQLITE_C_INT _
) As Any Ptr
    If mutexType = SQLITE_MUTEX_FAST OrElse mutexType = SQLITE_MUTEX_RECURSIVE Then
        Dim pMutex As SqliteDebugMutex Ptr = _
            CPtr(SqliteDebugMutex Ptr, sqlite3MallocZero(SizeOf(SqliteDebugMutex)))
        If pMutex = 0 Then Return 0
        pMutex->mutexType = mutexType
        Return pMutex
    End If

    If mutexType < SQLITE_MUTEX_STATIC_MAIN OrElse _
       mutexType > SQLITE_MUTEX_STATIC_VFS3 Then Return 0
    Dim staticIndex As Long = mutexType - SQLITE_MUTEX_STATIC_MAIN
    ' Repeated allocation returns the same lock and must preserve its count.
    Dim pMutex As SqliteDebugMutex Ptr = @sqlite3DebugStaticMutexes(staticIndex)
    pMutex->mutexType = mutexType
    Return pMutex
End Function

Private Sub debugMutexFree CDecl Alias "debugMutexFree" ( _
    ByVal pArgument As Any Ptr _
)
    If pArgument = 0 Then Exit Sub
    Dim pMutex As SqliteDebugMutex Ptr = CPtr(SqliteDebugMutex Ptr, pArgument)
    If pMutex->entryCount <> 0 Then Exit Sub
    If pMutex->mutexType = SQLITE_MUTEX_FAST OrElse _
       pMutex->mutexType = SQLITE_MUTEX_RECURSIVE Then
        sqlite3_free(pMutex)
    End If
End Sub

Private Sub debugMutexEnter CDecl Alias "debugMutexEnter" ( _
    ByVal pArgument As Any Ptr _
)
    If pArgument = 0 Then Exit Sub
    Dim pMutex As SqliteDebugMutex Ptr = CPtr(SqliteDebugMutex Ptr, pArgument)
    If pMutex->mutexType <> SQLITE_MUTEX_RECURSIVE AndAlso _
       debugMutexNotheld(pArgument) = 0 Then Exit Sub
    If pMutex->entryCount < 2147483647 Then pMutex->entryCount += 1
End Sub

Private Function debugMutexTry CDecl Alias "debugMutexTry" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT
    If pArgument = 0 Then Return SQLITE_MISUSE
    Dim pMutex As SqliteDebugMutex Ptr = CPtr(SqliteDebugMutex Ptr, pArgument)
    If pMutex->mutexType <> SQLITE_MUTEX_RECURSIVE AndAlso _
       debugMutexNotheld(pArgument) = 0 Then Return SQLITE_BUSY
    If pMutex->entryCount = 2147483647 Then Return SQLITE_FULL
    pMutex->entryCount += 1
    Return SQLITE_OK
End Function

Private Sub debugMutexLeave CDecl Alias "debugMutexLeave" ( _
    ByVal pArgument As Any Ptr _
)
    If pArgument = 0 Then Exit Sub
    Dim pMutex As SqliteDebugMutex Ptr = CPtr(SqliteDebugMutex Ptr, pArgument)
    If pMutex->entryCount <= 0 Then Exit Sub
    pMutex->entryCount -= 1
    If pMutex->mutexType <> SQLITE_MUTEX_RECURSIVE AndAlso _
       pMutex->entryCount <> 0 Then pMutex->entryCount = 0
End Sub

Function sqlite3MutexInit CDecl Alias "sqlite3MutexInit" () As SQLITE_C_INT Export
    If sqlite3ActiveMutexMethods = 0 Then _
        sqlite3ActiveMutexMethods = CPtr(SqliteMutexMethodTable Ptr, sqlite3NoopMutex())
    If sqlite3ActiveMutexMethods->xMutexInit = 0 Then Return SQLITE_MISUSE
    Return sqlite3ActiveMutexMethods->xMutexInit()
End Function

Function sqlite3MutexEnd CDecl Alias "sqlite3MutexEnd" () As SQLITE_C_INT Export
    If sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexEnd = 0 Then Return SQLITE_OK
    Return sqlite3ActiveMutexMethods->xMutexEnd()
End Function

Function sqlite3_mutex_alloc CDecl Alias "sqlite3_mutex_alloc" ( _
    ByVal mutexType As SQLITE_C_INT _
) As Any Ptr Export
    If sqlite3MutexInit() <> SQLITE_OK OrElse _
       sqlite3ActiveMutexMethods->xMutexAlloc = 0 Then Return 0
    Return sqlite3ActiveMutexMethods->xMutexAlloc(mutexType)
End Function

Function sqlite3MutexAlloc CDecl Alias "sqlite3MutexAlloc" ( _
    ByVal mutexType As SQLITE_C_INT _
) As Any Ptr Export
    If sqlite3ConfigCoreMutexEnabled() = 0 Then Return 0
    If sqlite3MutexInit() <> SQLITE_OK OrElse _
       sqlite3ActiveMutexMethods->xMutexAlloc = 0 Then Return 0
    Return sqlite3ActiveMutexMethods->xMutexAlloc(mutexType)
End Function

Sub sqlite3_mutex_free CDecl Alias "sqlite3_mutex_free" ( _
    ByVal pArgument As Any Ptr _
) Export
    If pArgument = 0 OrElse sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexFree = 0 Then Exit Sub
    sqlite3ActiveMutexMethods->xMutexFree(pArgument)
End Sub

Sub sqlite3_mutex_enter CDecl Alias "sqlite3_mutex_enter" ( _
    ByVal pArgument As Any Ptr _
) Export
    If pArgument = 0 OrElse sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexEnter = 0 Then Exit Sub
    sqlite3ActiveMutexMethods->xMutexEnter(pArgument)
End Sub

Function sqlite3_mutex_try CDecl Alias "sqlite3_mutex_try" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export
    If pArgument = 0 Then Return SQLITE_OK
    If sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexTry = 0 Then Return SQLITE_MISUSE
    Return sqlite3ActiveMutexMethods->xMutexTry(pArgument)
End Function

Sub sqlite3_mutex_leave CDecl Alias "sqlite3_mutex_leave" ( _
    ByVal pArgument As Any Ptr _
) Export
    If pArgument = 0 OrElse sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexLeave = 0 Then Exit Sub
    sqlite3ActiveMutexMethods->xMutexLeave(pArgument)
End Sub

Function sqlite3_mutex_held CDecl Alias "sqlite3_mutex_held" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export
    If pArgument = 0 OrElse sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexHeld = 0 Then Return 1
    Return sqlite3ActiveMutexMethods->xMutexHeld(pArgument)
End Function

Function sqlite3_mutex_notheld CDecl Alias "sqlite3_mutex_notheld" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export
    If pArgument = 0 OrElse sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexNotheld = 0 Then Return 1
    Return sqlite3ActiveMutexMethods->xMutexNotheld(pArgument)
End Function

#ifndef SQLITE_OS_WIN
Sub sqlite3MemoryBarrier CDecl Alias "sqlite3MemoryBarrier" () Export
End Sub
#endif

Private Dim Shared sqlite3NoopMutexMethods As SqliteMutexMethodTable = _
    Type<SqliteMutexMethodTable>( _
        ProcPtr(debugMutexInit), _
        ProcPtr(debugMutexEnd), _
        ProcPtr(debugMutexAlloc), _
        ProcPtr(debugMutexFree), _
        ProcPtr(debugMutexEnter), _
        ProcPtr(debugMutexTry), _
        ProcPtr(debugMutexLeave), _
        ProcPtr(debugMutexHeld), _
        ProcPtr(debugMutexNotheld))

Function sqlite3NoopMutex CDecl Alias "sqlite3NoopMutex" () As Any Ptr
    Return @sqlite3NoopMutexMethods
End Function

#else

Private Function noopMutexInit CDecl Alias "noopMutexInit" () As SQLITE_C_INT
    Return SQLITE_OK
End Function

Private Function noopMutexEnd CDecl Alias "noopMutexEnd" () As SQLITE_C_INT
    Return SQLITE_OK
End Function

Private Sub noopMutexFree CDecl Alias "noopMutexFree" (ByVal pMutex As Any Ptr)
End Sub

Private Sub noopMutexEnter CDecl Alias "noopMutexEnter" (ByVal pMutex As Any Ptr)
End Sub

Private Function noopMutexTry CDecl Alias "noopMutexTry" (ByVal pMutex As Any Ptr) As SQLITE_C_INT
    Return SQLITE_OK
End Function

Private Sub noopMutexLeave CDecl Alias "noopMutexLeave" (ByVal pMutex As Any Ptr)
End Sub

Private Function noopMutexAlloc CDecl Alias "noopMutexAlloc" ( _
    ByVal mutexType As SQLITE_C_INT _
) As Any Ptr
    Return CPtr(Any Ptr, 8)
End Function

Private Dim Shared sqlite3NoopMutexMethods As SqliteMutexMethodTable = _
    Type<SqliteMutexMethodTable>( _
        ProcPtr(noopMutexInit), _
        ProcPtr(noopMutexEnd), _
        ProcPtr(noopMutexAlloc), _
        ProcPtr(noopMutexFree), _
        ProcPtr(noopMutexEnter), _
        ProcPtr(noopMutexTry), _
        ProcPtr(noopMutexLeave), _
        Cast(SqliteMutexCheckCallback, 0), _
        Cast(SqliteMutexCheckCallback, 0))

Function sqlite3NoopMutex CDecl Alias "sqlite3NoopMutex" () As Any Ptr
    Return @sqlite3NoopMutexMethods
End Function

Function sqlite3MutexInit CDecl Alias "sqlite3MutexInit" () As SQLITE_C_INT Export
    If sqlite3ActiveMutexMethods = 0 Then _
        sqlite3ActiveMutexMethods = CPtr(SqliteMutexMethodTable Ptr, sqlite3NoopMutex())
    If sqlite3ActiveMutexMethods->xMutexInit = 0 Then Return SQLITE_MISUSE
    Return sqlite3ActiveMutexMethods->xMutexInit()
End Function

Function sqlite3MutexEnd CDecl Alias "sqlite3MutexEnd" () As SQLITE_C_INT Export
    If sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexEnd = 0 Then Return SQLITE_OK
    Return sqlite3ActiveMutexMethods->xMutexEnd()
End Function

Function sqlite3_mutex_alloc CDecl Alias "sqlite3_mutex_alloc" ( _
    ByVal mutexType As SQLITE_C_INT _
) As Any Ptr Export
    If sqlite3MutexInit() <> SQLITE_OK OrElse _
       sqlite3ActiveMutexMethods->xMutexAlloc = 0 Then Return 0
    Return sqlite3ActiveMutexMethods->xMutexAlloc(mutexType)
End Function

Function sqlite3MutexAlloc CDecl Alias "sqlite3MutexAlloc" ( _
    ByVal mutexType As SQLITE_C_INT _
) As Any Ptr Export
    If sqlite3ConfigCoreMutexEnabled() = 0 Then Return 0
    If sqlite3MutexInit() <> SQLITE_OK OrElse _
       sqlite3ActiveMutexMethods->xMutexAlloc = 0 Then Return 0
    Return sqlite3ActiveMutexMethods->xMutexAlloc(mutexType)
End Function

Sub sqlite3_mutex_free CDecl Alias "sqlite3_mutex_free" (ByVal pMutex As Any Ptr) Export
    If pMutex = 0 OrElse sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexFree = 0 Then Exit Sub
    sqlite3ActiveMutexMethods->xMutexFree(pMutex)
End Sub

Sub sqlite3_mutex_enter CDecl Alias "sqlite3_mutex_enter" (ByVal pMutex As Any Ptr) Export
    If pMutex = 0 OrElse sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexEnter = 0 Then Exit Sub
    sqlite3ActiveMutexMethods->xMutexEnter(pMutex)
End Sub

Function sqlite3_mutex_try CDecl Alias "sqlite3_mutex_try" (ByVal pMutex As Any Ptr) As SQLITE_C_INT Export
    If pMutex = 0 Then Return SQLITE_OK
    If sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexTry = 0 Then Return SQLITE_MISUSE
    Return sqlite3ActiveMutexMethods->xMutexTry(pMutex)
End Function

Sub sqlite3_mutex_leave CDecl Alias "sqlite3_mutex_leave" (ByVal pMutex As Any Ptr) Export
    If pMutex = 0 OrElse sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexLeave = 0 Then Exit Sub
    sqlite3ActiveMutexMethods->xMutexLeave(pMutex)
End Sub

Function sqlite3_mutex_held CDecl Alias "sqlite3_mutex_held" (ByVal pMutex As Any Ptr) As SQLITE_C_INT Export
    If pMutex = 0 OrElse sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexHeld = 0 Then Return 1
    Return sqlite3ActiveMutexMethods->xMutexHeld(pMutex)
End Function

Function sqlite3_mutex_notheld CDecl Alias "sqlite3_mutex_notheld" (ByVal pMutex As Any Ptr) As SQLITE_C_INT Export
    If pMutex = 0 OrElse sqlite3ActiveMutexMethods = 0 OrElse _
       sqlite3ActiveMutexMethods->xMutexNotheld = 0 Then Return 1
    Return sqlite3ActiveMutexMethods->xMutexNotheld(pMutex)
End Function

#ifndef SQLITE_OS_WIN
Sub sqlite3MemoryBarrier CDecl Alias "sqlite3MemoryBarrier" () Export
End Sub
#endif

#endif

#ifdef SQLITE_THREAD_MISUSE_WARNINGS
Function multiThreadedCheckMutex CDecl Alias "multiThreadedCheckMutex" () As Any Ptr Export
    Return sqlite3NoopMutex()
End Function

Sub sqlite3MutexWarnOnContention CDecl Alias "sqlite3MutexWarnOnContention" ( _
    ByVal pMutex As Any Ptr _
) Export
End Sub
#endif

#ifdef SQLITE_MUTEX_NOOP
Function sqlite3DefaultMutex CDecl Alias "sqlite3DefaultMutex" () As Any Ptr
    Return sqlite3NoopMutex()
End Function
#endif

#endif
#endif

#undef SQLITE3_FB_USE_PTHREAD_MUTEX
#undef SQLITE3_FB_USE_WIN32_MUTEX

/' end of sqlite3_mutex.bas '/
