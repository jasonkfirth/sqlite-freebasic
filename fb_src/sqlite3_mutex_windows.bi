/'
    Project: SQLite FreeBASIC port

    File: sqlite3_mutex_windows.bi

    Purpose:

        Provide the Win32 mutex provider selected by sqlite3_mutex.bas.

    Responsibilities:

        - Back recursive mutexes with CRITICAL_SECTION.
        - Back fast and static mutexes with exclusive SRWLOCK operations.
        - Preserve the C mutex callback table and debug ownership checks.
        - Supply no-op methods when SQLite disables core mutexes at runtime.

    This file intentionally does NOT contain:

        - Unix pthread mutexes.
        - The Windows system-call override table.
        - Optional OSTRACE formatting for mutex trace events.
'/

#ifndef SQLITE3_MUTEX_WINDOWS_BI
#define SQLITE3_MUTEX_WINDOWS_BI

Private Type SqliteWinCriticalSection
    debugInfo As Any Ptr
    lockCount As SQLITE_C_INT
    recursionCount As SQLITE_C_INT
    ownerThread As Any Ptr
    lockSemaphore As Any Ptr
    spinCount As SQLITE_SIZE_T
End Type

Private Type SqliteWinMutex
    criticalSection As SqliteWinCriticalSection
    srwLock As Any Ptr
    mutexType As SQLITE_C_INT
#ifdef SQLITE_DEBUG
    referenceCount As SQLITE_C_INT
    ownerThreadId As SQLITE_C_UINT
#endif
End Type

Private Const SQLITE_WIN_MUTEX_STATIC_COUNT As SQLITE_C_INT = 12
Private Const SQLITE_WIN_MUTEX_STATIC_STRIDE As ULongInt = 128
Private Const SQLITE_WIN_MUTEX_STORAGE_SIZE As Long = _
    SQLITE_WIN_MUTEX_STATIC_COUNT * 128 + 127

' A 128-byte stride keeps each static mutex on a separate cache line, as the
' ALIGN128 wrapper does in mutex_w32.c. The extra bytes allow runtime alignment.
Private Dim Shared sqlite3WinMutexStorage( _
    0 To SQLITE_WIN_MUTEX_STORAGE_SIZE - 1) As UByte
Private Dim Shared sqlite3WinMutexIsInitialized As SQLITE_C_INT = 0
Private Dim Shared sqlite3WinMutexInitializationLock As SQLITE_C_INT = 0

Declare Sub winMutexInitializeCriticalSection StdCall Lib "kernel32" _
    Alias "InitializeCriticalSection" (ByVal pCriticalSection As Any Ptr)
Declare Sub winMutexDeleteCriticalSection StdCall Lib "kernel32" _
    Alias "DeleteCriticalSection" (ByVal pCriticalSection As Any Ptr)
Declare Sub winMutexEnterCriticalSection StdCall Lib "kernel32" _
    Alias "EnterCriticalSection" (ByVal pCriticalSection As Any Ptr)
Declare Function winMutexTryCriticalSection StdCall Lib "kernel32" _
    Alias "TryEnterCriticalSection" (ByVal pCriticalSection As Any Ptr) _
    As SQLITE_C_INT
Declare Sub winMutexLeaveCriticalSection StdCall Lib "kernel32" _
    Alias "LeaveCriticalSection" (ByVal pCriticalSection As Any Ptr)
Declare Sub winMutexAcquireSrwExclusive StdCall Lib "kernel32" _
    Alias "AcquireSRWLockExclusive" (ByVal pLock As Any Ptr)
Declare Function winMutexTryAcquireSrwExclusive StdCall Lib "kernel32" _
    Alias "TryAcquireSRWLockExclusive" (ByVal pLock As Any Ptr) _
    As SQLITE_C_INT
Declare Sub winMutexReleaseSrwExclusive StdCall Lib "kernel32" _
    Alias "ReleaseSRWLockExclusive" (ByVal pLock As Any Ptr)
Declare Function winMutexInterlockedCompareExchange StdCall Lib "kernel32" _
    Alias "InterlockedCompareExchange" ( _
    ByVal pTarget As SQLITE_C_INT Ptr, _
    ByVal exchangeValue As SQLITE_C_INT, _
    ByVal comparand As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function winMutexGetCurrentThreadId StdCall Lib "kernel32" _
    Alias "GetCurrentThreadId" () As SQLITE_C_UINT
Declare Sub winMutexSleep StdCall Lib "kernel32" _
    Alias "Sleep" (ByVal milliseconds As SQLITE_C_UINT)

#ifdef SQLITE_DEBUG
Declare Sub sqlite3DebugAssert CDecl Alias "sqlite3DebugAssert" ( _
    ByVal zExpression As Const ZString Ptr _
)
#endif

#if defined(SQLITE_ENABLE_API_ARMOR) AndAlso defined(SQLITE_DEBUG)
#ifndef SQLITE_THREAD_MISUSE_WARNINGS
Declare Function sqlite3MisuseError CDecl Alias "sqlite3MisuseError" ( _
    ByVal lineNumber As SQLITE_C_INT _
) As SQLITE_C_INT
#endif
#endif

Private Function winMutexStaticPointer( _
    ByVal index As SQLITE_C_INT _
) As SqliteWinMutex Ptr
    If index < 0 OrElse index >= SQLITE_WIN_MUTEX_STATIC_COUNT Then Return 0

    Dim addressValue As ULongInt = CULngInt( _
        CPtr(Any Ptr, @sqlite3WinMutexStorage(0)))
    addressValue = (addressValue + 127ULL) And Not 127ULL
    addressValue += CULngInt(index) * SQLITE_WIN_MUTEX_STATIC_STRIDE
    Return CPtr(SqliteWinMutex Ptr, addressValue)
End Function

Private Function winMutexInitializationReady() As SQLITE_C_INT
    Return winMutexInterlockedCompareExchange( _
        @sqlite3WinMutexIsInitialized, 0, 0)
End Function

Private Function winMutexInit CDecl Alias "winMutexInit" () As SQLITE_C_INT
    If winMutexInterlockedCompareExchange( _
        @sqlite3WinMutexInitializationLock, 1, 0) = 0 Then

        For i As SQLITE_C_INT = 0 To SQLITE_WIN_MUTEX_STATIC_COUNT - 1
            Dim pMutex As SqliteWinMutex Ptr = winMutexStaticPointer(i)
            If pMutex = 0 Then Return SQLITE_ERROR
            pMutex->mutexType = SQLITE_MUTEX_STATIC_MAIN + i
            pMutex->srwLock = 0
#ifdef SQLITE_DEBUG
            pMutex->referenceCount = 0
            pMutex->ownerThreadId = 0
#endif
        Next

        winMutexInterlockedCompareExchange( _
            @sqlite3WinMutexIsInitialized, 1, 0)
    Else
        ' InterlockedCompareExchange publishes the static-lock initialization.
        While winMutexInitializationReady() = 0
            winMutexSleep(1)
        Wend
    End If
    Return SQLITE_OK
End Function

Private Function winMutexEnd CDecl Alias "winMutexEnd" () As SQLITE_C_INT
    If winMutexInterlockedCompareExchange( _
        @sqlite3WinMutexInitializationLock, 0, 1) = 1 Then
        If sqlite3WinMutexIsInitialized = 1 Then
            sqlite3WinMutexIsInitialized = 0
        End If
    End If
    Return SQLITE_OK
End Function

Private Function winMutexAlloc CDecl Alias "winMutexAlloc" ( _
    ByVal mutexType As SQLITE_C_INT _
) As Any Ptr
    If mutexType = SQLITE_MUTEX_FAST OrElse _
       mutexType = SQLITE_MUTEX_RECURSIVE Then
        Dim pMutex As SqliteWinMutex Ptr = CPtr( _
            SqliteWinMutex Ptr, sqlite3MallocZero(SizeOf(SqliteWinMutex)))
        If pMutex = 0 Then Return 0
        pMutex->mutexType = mutexType
        If mutexType = SQLITE_MUTEX_RECURSIVE Then
            winMutexInitializeCriticalSection(@pMutex->criticalSection)
        Else
            pMutex->srwLock = 0
        End If
        Return pMutex
    End If

    Dim staticIndex As SQLITE_C_INT = mutexType - SQLITE_MUTEX_STATIC_MAIN
    If staticIndex < 0 OrElse _
       staticIndex >= SQLITE_WIN_MUTEX_STATIC_COUNT Then
#ifdef SQLITE_ENABLE_API_ARMOR
#ifdef SQLITE_DEBUG
        sqlite3MisuseError(235)
#endif
#endif
        Return 0
    End If

    If winMutexInitializationReady() = 0 Then
        If winMutexInit() <> SQLITE_OK Then Return 0
    End If
    Dim pStaticMutex As SqliteWinMutex Ptr = winMutexStaticPointer(staticIndex)
    If pStaticMutex = 0 OrElse pStaticMutex->mutexType <> mutexType Then Return 0
    Return pStaticMutex
End Function

Private Sub winMutexFree CDecl Alias "winMutexFree" ( _
    ByVal pArgument As Any Ptr _
)
    If pArgument = 0 Then Exit Sub
    Dim pMutex As SqliteWinMutex Ptr = CPtr(SqliteWinMutex Ptr, pArgument)

    If pMutex->mutexType = SQLITE_MUTEX_FAST OrElse _
       pMutex->mutexType = SQLITE_MUTEX_RECURSIVE Then
#ifdef SQLITE_DEBUG
        If pMutex->referenceCount <> 0 OrElse pMutex->ownerThreadId <> 0 Then
            sqlite3DebugAssert(StrPtr("p->nRef==0 && p->owner==0"))
            Exit Sub
        End If
#endif
        If pMutex->mutexType = SQLITE_MUTEX_RECURSIVE Then
            winMutexDeleteCriticalSection(@pMutex->criticalSection)
        End If
        sqlite3_free(pMutex)
        Exit Sub
    End If

#ifdef SQLITE_ENABLE_API_ARMOR
#ifdef SQLITE_DEBUG
    sqlite3MisuseError(268)
#endif
#endif
End Sub

Private Sub winMutexEnter CDecl Alias "winMutexEnter" ( _
    ByVal pArgument As Any Ptr _
)
    If pArgument = 0 Then Exit Sub
    Dim pMutex As SqliteWinMutex Ptr = CPtr(SqliteWinMutex Ptr, pArgument)
    If winMutexInitializationReady() = 0 Then
        If winMutexInit() <> SQLITE_OK Then Exit Sub
    End If

#ifdef SQLITE_DEBUG
    If pMutex->mutexType <> SQLITE_MUTEX_RECURSIVE AndAlso _
       pMutex->referenceCount > 0 AndAlso _
       pMutex->ownerThreadId = winMutexGetCurrentThreadId() Then
        sqlite3DebugAssert(StrPtr( _
            "p->id==SQLITE_MUTEX_RECURSIVE || winMutexNotheld(p)"))
        Exit Sub
    End If
#endif
    If pMutex->mutexType = SQLITE_MUTEX_RECURSIVE Then
        winMutexEnterCriticalSection(@pMutex->criticalSection)
    Else
        winMutexAcquireSrwExclusive(@pMutex->srwLock)
    End If
#ifdef SQLITE_DEBUG
    pMutex->ownerThreadId = winMutexGetCurrentThreadId()
    pMutex->referenceCount += 1
#endif
End Sub

Private Function winMutexTry CDecl Alias "winMutexTry" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT
    If pArgument = 0 Then Return SQLITE_MISUSE
    Dim pMutex As SqliteWinMutex Ptr = CPtr(SqliteWinMutex Ptr, pArgument)
    Dim acquired As SQLITE_C_INT

    If pMutex->mutexType = SQLITE_MUTEX_RECURSIVE Then
        acquired = winMutexTryCriticalSection(@pMutex->criticalSection)
    Else
        acquired = winMutexTryAcquireSrwExclusive(@pMutex->srwLock)
    End If

    If acquired = 0 Then Return SQLITE_BUSY
#ifdef SQLITE_DEBUG
    pMutex->ownerThreadId = winMutexGetCurrentThreadId()
    pMutex->referenceCount += 1
#endif
    Return SQLITE_OK
End Function

Private Sub winMutexLeave CDecl Alias "winMutexLeave" ( _
    ByVal pArgument As Any Ptr _
)
    If pArgument = 0 Then Exit Sub
    Dim pMutex As SqliteWinMutex Ptr = CPtr(SqliteWinMutex Ptr, pArgument)
#ifdef SQLITE_DEBUG
    If pMutex->referenceCount <= 0 OrElse _
       pMutex->ownerThreadId <> winMutexGetCurrentThreadId() Then
        sqlite3DebugAssert(StrPtr( _
            "p->nRef>0 && p->owner==GetCurrentThreadId()"))
        Exit Sub
    End If
    pMutex->referenceCount -= 1
    If pMutex->referenceCount = 0 Then pMutex->ownerThreadId = 0
#endif
    If pMutex->mutexType = SQLITE_MUTEX_RECURSIVE Then
        winMutexLeaveCriticalSection(@pMutex->criticalSection)
    Else
        winMutexReleaseSrwExclusive(@pMutex->srwLock)
    End If
End Sub

#ifdef SQLITE_DEBUG
Private Function winMutexHeld CDecl Alias "winMutexHeld" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT
    If pArgument = 0 Then Return 1
    Dim pMutex As SqliteWinMutex Ptr = CPtr(SqliteWinMutex Ptr, pArgument)
    Return IIf(pMutex->referenceCount <> 0 AndAlso _
        pMutex->ownerThreadId = winMutexGetCurrentThreadId(), 1, 0)
End Function

Private Function winMutexNotheld CDecl Alias "winMutexNotheld" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT
    If pArgument = 0 Then Return 1
    Dim pMutex As SqliteWinMutex Ptr = CPtr(SqliteWinMutex Ptr, pArgument)
    Return IIf(pMutex->referenceCount = 0 OrElse _
        pMutex->ownerThreadId <> winMutexGetCurrentThreadId(), 1, 0)
End Function

Private Dim Shared sqlite3WinMutexMethods As SqliteMutexMethodTable = _
    Type<SqliteMutexMethodTable>( _
        ProcPtr(winMutexInit), _
        ProcPtr(winMutexEnd), _
        ProcPtr(winMutexAlloc), _
        ProcPtr(winMutexFree), _
        ProcPtr(winMutexEnter), _
        ProcPtr(winMutexTry), _
        ProcPtr(winMutexLeave), _
        ProcPtr(winMutexHeld), _
        ProcPtr(winMutexNotheld))
#else
Private Dim Shared sqlite3WinMutexMethods As SqliteMutexMethodTable = _
    Type<SqliteMutexMethodTable>( _
        ProcPtr(winMutexInit), _
        ProcPtr(winMutexEnd), _
        ProcPtr(winMutexAlloc), _
        ProcPtr(winMutexFree), _
        ProcPtr(winMutexEnter), _
        ProcPtr(winMutexTry), _
        ProcPtr(winMutexLeave), _
        Cast(SqliteMutexCheckCallback, 0), _
        Cast(SqliteMutexCheckCallback, 0))
#endif

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

Private Sub noopMutexFree CDecl Alias "noopMutexFree" ( _
    ByVal pArgument As Any Ptr _
)
End Sub

Private Sub noopMutexEnter CDecl Alias "noopMutexEnter" ( _
    ByVal pArgument As Any Ptr _
)
End Sub

Private Function noopMutexTry CDecl Alias "noopMutexTry" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT
    Return SQLITE_OK
End Function

Private Sub noopMutexLeave CDecl Alias "noopMutexLeave" ( _
    ByVal pArgument As Any Ptr _
)
End Sub

Private Function noopMutexHeld CDecl Alias "noopMutexHeld" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT
    Return 1
End Function

Private Function noopMutexNotheld CDecl Alias "noopMutexNotheld" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT
    Return 1
End Function

Private Dim Shared sqlite3WinNoopMutexMethods As SqliteMutexMethodTable = _
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
    Return @sqlite3WinNoopMutexMethods
End Function

Function sqlite3DefaultMutex CDecl Alias "sqlite3DefaultMutex" () As Any Ptr
    Return @sqlite3WinMutexMethods
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
        If staticIndex < 0 OrElse staticIndex >= _
           SizeOf(sqlite3CheckMutexStatic) / SizeOf(SqliteCheckMutex) Then
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
    If pArgument = 0 OrElse sqlite3CheckMutexBaseMethods = 0 OrElse _
       sqlite3CheckMutexBaseMethods->xMutexHeld = 0 Then Return 1
    Dim pCheck As SqliteCheckMutex Ptr = CPtr(SqliteCheckMutex Ptr, pArgument)
    Return sqlite3CheckMutexBaseMethods->xMutexHeld(pCheck->pMutex)
End Function

Private Function checkMutexNotheld CDecl Alias "checkMutexNotheld" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT
    If pArgument = 0 OrElse sqlite3CheckMutexBaseMethods = 0 OrElse _
       sqlite3CheckMutexBaseMethods->xMutexNotheld = 0 Then Return 1
    Dim pCheck As SqliteCheckMutex Ptr = CPtr(SqliteCheckMutex Ptr, pArgument)
    Return sqlite3CheckMutexBaseMethods->xMutexNotheld(pCheck->pMutex)
End Function
#endif

#ifdef SQLITE_DEBUG
Private Dim Shared sqlite3WinCheckMutexMethods As SqliteMutexMethodTable = _
    Type<SqliteMutexMethodTable>( _
        ProcPtr(checkMutexInit), ProcPtr(checkMutexEnd), ProcPtr(checkMutexAlloc), _
        ProcPtr(checkMutexFree), ProcPtr(checkMutexEnter), ProcPtr(checkMutexTry), _
        ProcPtr(checkMutexLeave), ProcPtr(checkMutexHeld), ProcPtr(checkMutexNotheld))
#else
Private Dim Shared sqlite3WinCheckMutexMethods As SqliteMutexMethodTable = _
    Type<SqliteMutexMethodTable>( _
        ProcPtr(checkMutexInit), ProcPtr(checkMutexEnd), ProcPtr(checkMutexAlloc), _
        ProcPtr(checkMutexFree), ProcPtr(checkMutexEnter), ProcPtr(checkMutexTry), _
        ProcPtr(checkMutexLeave), Cast(SqliteMutexCheckCallback, 0), _
        Cast(SqliteMutexCheckCallback, 0))
#endif

Function multiThreadedCheckMutex CDecl Alias "multiThreadedCheckMutex" () _
    As Any Ptr Export
    Return @sqlite3WinCheckMutexMethods
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

#endif

/' end of sqlite3_mutex_windows.bi '/
