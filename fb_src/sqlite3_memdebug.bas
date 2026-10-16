/'
** 2007 August 15
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
*************************************************************************
**
** This file contains the SQLITE_MEMDEBUG allocator and its diagnostic APIs.
'/

/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_memdebug.bas

    Purpose:

        Provide SQLite's guarded debug allocator and allocation diagnostics.

    Responsibilities:

        - Track guarded allocations and their optional backtrace frames.
        - Fill new, extended, and released allocations with SQLite's debug pattern.
        - Maintain live-allocation lists, type tags, and allocation-size counters.
        - Expose the allocator controls used by SQLite's C test harness.

    This file intentionally does NOT contain:

        - Test-runner code or Tcl command registration.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_api_constants.bi"
#include once "sqlite3_api_declarations.bi"
#include once "sqlite3_memory_methods.bi"
#include once "sqlite3_debug_assert.bi"

#ifdef SQLITE_MEMDEBUG
Private Type SqliteMemdebugBacktraceProc As Sub CDecl ( _
    ByVal frameCount As SQLITE_C_INT, _
    ByVal maximumFrames As SQLITE_C_INT, _
    ByVal frames As Any Ptr Ptr _
)

Private Type SqliteMemdebugHeader
    iSize As sqlite3_int64
    pNext As SqliteMemdebugHeader Ptr
    pPrev As SqliteMemdebugHeader Ptr
    nBacktrace As Byte
    nBacktraceSlots As Byte
    nTitle As UByte
    eType As UByte
    iForeGuard As SQLITE_C_INT
End Type

' SQLite records one counter for each of 1000 eight-byte allocation buckets.
Private Const SQLITE_MEMDEBUG_NCSIZE As SQLITE_C_INT = 1000
Private Const SQLITE_MEMDEBUG_ALIGNMENT As SQLITE_C_INT = 8
Private Const SQLITE_MEMDEBUG_PADDING_BYTE As UByte = &H65
Private Const SQLITE_MEMDEBUG_MAX_BACKTRACE_DEPTH As SQLITE_C_INT = 20
Private Const SQLITE_MEMDEBUG_BACKTRACE_BUFFER_SIZE As SQLITE_C_INT = 40
Private Const SQLITE_MEMDEBUG_TITLE_CAPACITY As SQLITE_C_INT = 100
Private Const SQLITE_MEMDEBUG_FOREGUARD As SQLITE_C_UINT = &H80F5E153
Private Const SQLITE_MEMDEBUG_REARGUARD As SQLITE_C_UINT = &HE4676B53
Private Const SQLITE_MEMDEBUG_HEAP_TYPE As UByte = &H01
' ROUND8(99) is 104; keep its four padding bytes separate from other state.
Private Const SQLITE_MEMDEBUG_TITLE_BYTES As SQLITE_C_INT = 104

Private Type SqliteMemdebugState
    pMutex As Any Ptr
    pFirst As SqliteMemdebugHeader Ptr
    pLast As SqliteMemdebugHeader Ptr
    nBacktrace As SQLITE_C_INT
    xBacktrace As SqliteMemdebugBacktraceProc
    nTitle As SQLITE_C_INT
    zTitle(0 To SQLITE_MEMDEBUG_TITLE_BYTES - 1) As UByte
    disallow As SQLITE_C_INT
    nAlloc(0 To SQLITE_MEMDEBUG_NCSIZE - 1) As SQLITE_C_INT
    nCurrent(0 To SQLITE_MEMDEBUG_NCSIZE - 1) As SQLITE_C_INT
    mxCurrent(0 To SQLITE_MEMDEBUG_NCSIZE - 1) As SQLITE_C_INT
End Type

' The allocator and its controls share this module-local state, as mem2.c does.
Private Dim Shared mem As SqliteMemdebugState

Extern "C"
    Extern stderr Alias "stderr" As Any Ptr
    Declare Function memdebugSystemMalloc CDecl Alias "malloc" ( _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
    Declare Sub memdebugSystemFree CDecl Alias "free" (ByVal p As Any Ptr)
    Declare Function memdebugSystemMemcpy CDecl Alias "memcpy" ( _
        ByVal destination As Any Ptr, _
        ByVal source As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
    Declare Function memdebugSystemFopen CDecl Alias "fopen" ( _
        ByVal zFilename As Const ZString Ptr, _
        ByVal zMode As Const ZString Ptr _
    ) As Any Ptr
    Declare Function memdebugSystemFprintf CDecl Alias "fprintf" ( _
        ByVal pStream As Any Ptr, _
        ByVal zFormat As Const ZString Ptr, _
        ... _
    ) As SQLITE_C_INT
    Declare Function memdebugSystemFflush CDecl Alias "fflush" ( _
        ByVal pStream As Any Ptr _
    ) As SQLITE_C_INT
    Declare Function memdebugSystemFclose CDecl Alias "fclose" ( _
        ByVal pStream As Any Ptr _
    ) As SQLITE_C_INT
#ifdef SQLITE3_FB_GLIBC_BACKTRACE
    Declare Function memdebugSystemBacktrace CDecl Alias "backtrace" ( _
        ByVal aFrames As Any Ptr Ptr, _
        ByVal maximumFrames As SQLITE_C_INT _
    ) As SQLITE_C_INT
    Declare Sub memdebugSystemBacktraceSymbolsFd CDecl Alias "backtrace_symbols_fd" ( _
        ByVal aFrames As Any Ptr Ptr, _
        ByVal frameCount As SQLITE_C_INT, _
        ByVal fileDescriptor As SQLITE_C_INT _
    )
    Declare Function memdebugSystemFileno CDecl Alias "fileno" ( _
        ByVal pStream As Any Ptr _
    ) As SQLITE_C_INT
#endif
End Extern

Declare Function sqlite3ConfigMemStatusEnabled CDecl Alias "sqlite3ConfigMemStatusEnabled" () As SQLITE_C_INT
Declare Function sqlite3MutexAlloc CDecl Alias "sqlite3MutexAlloc" ( _
    ByVal mutexId As SQLITE_C_INT _
) As Any Ptr
Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal zText As Const ZString Ptr _
) As SQLITE_C_INT

/' ------------------------------------------------------------------------- '/
/' Allocator invariants and accounting '/
/' ------------------------------------------------------------------------- '/

Private Function memdebugRoundup(ByVal nByte As SQLITE_C_INT) As SQLITE_C_INT
    If nByte <= 0 OrElse _
       nByte > SQLITE_MAX_ALLOCATION_SIZE - (SQLITE_MEMDEBUG_ALIGNMENT - 1) Then Return 0
    Return (nByte + SQLITE_MEMDEBUG_ALIGNMENT - 1) And _
        Not (SQLITE_MEMDEBUG_ALIGNMENT - 1)
End Function

Private Sub memdebugAssert(ByVal condition As SQLITE_C_INT, ByVal zExpression As Const ZString Ptr)
#ifdef SQLITE_DEBUG
    If condition = 0 Then sqlite3DebugAssert(zExpression)
#endif
End Sub

Private Sub adjustStats( _
    ByVal nByte As SQLITE_C_INT, _
    ByVal increment As SQLITE_C_INT _
)
    Dim nReserve As SQLITE_C_INT = memdebugRoundup(nByte)
    Dim bucket As SQLITE_C_INT
    If nReserve <= 0 Then Exit Sub

    bucket = nReserve \ SQLITE_MEMDEBUG_ALIGNMENT
    If bucket >= SQLITE_MEMDEBUG_NCSIZE Then bucket = SQLITE_MEMDEBUG_NCSIZE - 1

    If increment > 0 Then
        mem.nAlloc(bucket) += 1
        mem.nCurrent(bucket) += 1
        If mem.nCurrent(bucket) > mem.mxCurrent(bucket) Then _
            mem.mxCurrent(bucket) = mem.nCurrent(bucket)
    Else
        mem.nCurrent(bucket) -= 1
        memdebugAssert(mem.nCurrent(bucket) >= 0, StrPtr(!"mem.nCurrent[bucket]>=0"))
    End If
End Sub

Private Function sqlite3MemsysGetHeader( _
    ByVal pAllocation As Const Any Ptr _
) As SqliteMemdebugHeader Ptr
    If pAllocation = 0 Then Return 0

    Dim pUser As UByte Ptr = CPtr(UByte Ptr, pAllocation)
    Dim pHeaderBytes As UByte Ptr = pUser - SizeOf(SqliteMemdebugHeader)
    Dim pHeader As SqliteMemdebugHeader Ptr = _
        CPtr(SqliteMemdebugHeader Ptr, pHeaderBytes)
    Dim nReserve As SQLITE_C_INT = memdebugRoundup(CLng(pHeader->iSize))
    If nReserve <= 0 Then Return 0

    memdebugAssert(pHeader->iForeGuard = Cast(SQLITE_C_INT, SQLITE_MEMDEBUG_FOREGUARD), _
                   StrPtr(!"pHeader->iForeGuard==SQLITE_MEMDEBUG_FOREGUARD"))

    Dim pTailGuard As SQLITE_C_INT Ptr = _
        CPtr(SQLITE_C_INT Ptr, pUser + nReserve)
    memdebugAssert(Cast(SQLITE_C_UINT, pTailGuard[0]) = SQLITE_MEMDEBUG_REARGUARD, _
                   StrPtr(!"pTailGuard[0]==SQLITE_MEMDEBUG_REARGUARD"))

    For byteIndex As SQLITE_C_INT = CLng(pHeader->iSize) To nReserve - 1
        memdebugAssert(pUser[byteIndex] = SQLITE_MEMDEBUG_PADDING_BYTE, _
                       StrPtr(!"pUser[byteIndex]==0x65"))
    Next
    Return pHeader
End Function

Private Function sqlite3MemSize CDecl(ByVal pAllocation As Any Ptr) As SQLITE_C_INT
    If pAllocation = 0 Then Return 0
    Dim pHeader As SqliteMemdebugHeader Ptr = sqlite3MemsysGetHeader(pAllocation)
    If pHeader = 0 Then Return 0
    Return CLng(pHeader->iSize)
End Function

Private Function sqlite3MemInit CDecl(ByVal pAppData As Any Ptr) As SQLITE_C_INT
    memdebugAssert((SizeOf(SqliteMemdebugHeader) And _
                    (SQLITE_MEMDEBUG_ALIGNMENT - 1)) = 0, _
                   StrPtr(!"(sizeof(SqliteMemdebugHeader)&7)==0"))
    If sqlite3ConfigMemStatusEnabled() = 0 Then _
        mem.pMutex = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MEM)
    Return SQLITE_OK
End Function

Private Sub sqlite3MemShutdown CDecl(ByVal pAppData As Any Ptr)
    mem.pMutex = 0
End Sub

/' ------------------------------------------------------------------------- '/
/' Allocation callbacks '/
/' ------------------------------------------------------------------------- '/

Sub sqlite3MemdebugBacktrace CDecl Alias "sqlite3MemdebugBacktrace" ( _
    ByVal depth As SQLITE_C_INT _
) Export
    If depth < 0 Then depth = 0
    If depth > SQLITE_MEMDEBUG_MAX_BACKTRACE_DEPTH Then _
        depth = SQLITE_MEMDEBUG_MAX_BACKTRACE_DEPTH

    ' SQLite stores an even number of frames and limits the list to 20.
    depth = (depth + 1) And &HFE
    mem.nBacktrace = depth
End Sub

Sub sqlite3MemdebugBacktraceCallback CDecl Alias "sqlite3MemdebugBacktraceCallback" ( _
    ByVal xBacktrace As SqliteMemdebugBacktraceProc _
) Export
    mem.xBacktrace = xBacktrace
End Sub

Private Sub randomFill CDecl Alias "randomFill" ( _
    ByVal pBuffer As UByte Ptr, _
    ByVal byteCount As SQLITE_C_INT _
)
    If pBuffer = 0 OrElse byteCount <= 0 Then Exit Sub

    Dim pWrite As UByte Ptr = pBuffer
    Dim remainingBytes As SQLITE_C_INT = byteCount
    ' SQLite intentionally seeds this pattern from the low pointer bits.
    Dim x As SQLITE_C_UINT = _
        CUInt(CULngInt(CPtr(Any Ptr, pWrite)) And &HFFFFFFFFULL)
    Dim y As SQLITE_C_UINT = CUInt(remainingBytes) Or 1
    Dim randomWord As SQLITE_C_UINT

    ' These recurrence constants match the allocator's 32-bit debug pattern.
    While remainingBytes >= SizeOf(randomWord)
        If (x And 1) <> 0 Then
            x = (x Shr 1) Xor &HD0000001
        Else
            x = x Shr 1
        End If
        y = CUInt((CULngInt(y) * 1103515245ULL + 12345ULL) And &HFFFFFFFFULL)
        randomWord = x Xor y

        ' memcpy preserves host byte order and avoids an unaligned int store.
        memdebugSystemMemcpy(pWrite, @randomWord, SizeOf(randomWord))
        pWrite += SizeOf(randomWord)
        remainingBytes -= SizeOf(randomWord)
    Wend

    While remainingBytes > 0
        If (x And 1) <> 0 Then
            x = (x Shr 1) Xor &HD0000001
        Else
            x = x Shr 1
        End If
        y = CUInt((CULngInt(y) * 1103515245ULL + 12345ULL) And &HFFFFFFFFULL)
        randomWord = x Xor y
        pWrite[0] = CUByte(randomWord And &HFF)
        pWrite += 1
        remainingBytes -= 1
    Wend
End Sub

Private Function sqlite3MemMalloc CDecl(ByVal nByte As SQLITE_C_INT) As Any Ptr
    If nByte <= 0 Then Return 0
    If mem.disallow <> 0 Then
        memdebugAssert(0, StrPtr(!"mem.disallow==0"))
        Return 0
    End If

    Dim nReserve As SQLITE_C_INT = memdebugRoundup(nByte)
    If nReserve <= 0 Then Return 0

    Dim nBacktraceSlots As SQLITE_C_INT = mem.nBacktrace
    If nBacktraceSlots < 0 OrElse _
       nBacktraceSlots > SQLITE_MEMDEBUG_MAX_BACKTRACE_DEPTH Then Return 0
    Dim nBacktraceBytes As ULongInt = _
        CULngInt(nBacktraceSlots) * CULngInt(SizeOf(Any Ptr))
    Dim nTotal As ULongInt = CULngInt(nReserve) + _
        CULngInt(SizeOf(SqliteMemdebugHeader)) + _
        CULngInt(SizeOf(SQLITE_C_INT)) + nBacktraceBytes + _
        CULngInt(mem.nTitle)

    ' mem2.c uses an int for totalSize; reject a request before its metadata can overflow it.
    If nTotal > &H7FFFFFFFULL Then Return 0

    sqlite3_mutex_enter(mem.pMutex)
    Dim pBase As Any Ptr = memdebugSystemMalloc(CUInt(nTotal))
    If pBase = 0 Then
        sqlite3_mutex_leave(mem.pMutex)
        Return 0
    End If

    Dim pBaseBytes As UByte Ptr = CPtr(UByte Ptr, pBase)
    Dim pBacktrace As Any Ptr Ptr = _
        CPtr(Any Ptr Ptr, pBaseBytes + mem.nTitle)
    Dim pHeaderBytes As UByte Ptr = _
        CPtr(UByte Ptr, pBacktrace) + nBacktraceBytes
    Dim pHeader As SqliteMemdebugHeader Ptr = _
        CPtr(SqliteMemdebugHeader Ptr, pHeaderBytes)

    pHeader->pNext = 0
    pHeader->pPrev = mem.pLast
    If mem.pLast <> 0 Then
        mem.pLast->pNext = pHeader
    Else
        mem.pFirst = pHeader
    End If
    mem.pLast = pHeader

    pHeader->iForeGuard = Cast(SQLITE_C_INT, SQLITE_MEMDEBUG_FOREGUARD)
    pHeader->eType = SQLITE_MEMDEBUG_HEAP_TYPE
    pHeader->nBacktraceSlots = CByte(nBacktraceSlots)
    pHeader->nTitle = CByte(mem.nTitle)
    pHeader->iSize = nByte

    If nBacktraceSlots > 0 Then
        Dim frames(0 To SQLITE_MEMDEBUG_BACKTRACE_BUFFER_SIZE - 1) As Any Ptr
        Dim nFrames As SQLITE_C_INT
#ifdef SQLITE3_FB_GLIBC_BACKTRACE
        nFrames = memdebugSystemBacktrace(@frames(0), nBacktraceSlots + 1)
#else
        nFrames = 1
#endif
        pHeader->nBacktrace = CByte(nFrames - 1)
        If pHeader->nBacktrace > 0 Then
            memdebugSystemMemcpy(pBacktrace, @frames(1), _
                CULngInt(CInt(pHeader->nBacktrace)) * CULngInt(SizeOf(Any Ptr)))
        End If
        If mem.xBacktrace <> 0 Then _
            mem.xBacktrace(nByte, CInt(pHeader->nBacktrace) - 1, @frames(1))
    Else
        pHeader->nBacktrace = 0
    End If

    If mem.nTitle > 0 Then _
        memdebugSystemMemcpy(pBase, @mem.zTitle(0), CUInt(mem.nTitle))

    adjustStats(nByte, 1)
    Dim pUser As UByte Ptr = _
        CPtr(UByte Ptr, pHeaderBytes + SizeOf(SqliteMemdebugHeader))
    Dim pTailGuard As SQLITE_C_INT Ptr = _
        CPtr(SQLITE_C_INT Ptr, pUser + nReserve)
    pTailGuard[0] = Cast(SQLITE_C_INT, SQLITE_MEMDEBUG_REARGUARD)
    randomFill(pUser, nByte)
    For byteIndex As SQLITE_C_INT = nByte To nReserve - 1
        pUser[byteIndex] = SQLITE_MEMDEBUG_PADDING_BYTE
    Next

    sqlite3_mutex_leave(mem.pMutex)
    Return pUser
End Function

Private Sub sqlite3MemFree CDecl(ByVal pPrior As Any Ptr)
    If pPrior = 0 Then Exit Sub

    Dim pHeader As SqliteMemdebugHeader Ptr = sqlite3MemsysGetHeader(pPrior)
    If pHeader = 0 Then Exit Sub
    Dim pBacktrace As Any Ptr Ptr = CPtr(Any Ptr Ptr, pHeader) - pHeader->nBacktraceSlots
    Dim pBase As UByte Ptr = CPtr(UByte Ptr, pBacktrace) - pHeader->nTitle
    Dim nFreedBytes As ULongInt = _
        CULngInt(CInt(pHeader->nBacktraceSlots)) * CULngInt(SizeOf(Any Ptr)) + _
        CULngInt(SizeOf(SqliteMemdebugHeader)) + _
        CULngInt(pHeader->iSize) + CULngInt(SizeOf(SQLITE_C_INT)) + _
        CULngInt(pHeader->nTitle)

    sqlite3_mutex_enter(mem.pMutex)
    If pHeader->pPrev <> 0 Then
        memdebugAssert(pHeader->pPrev->pNext = pHeader, _
                       StrPtr(!"pHeader->pPrev->pNext==pHeader"))
        pHeader->pPrev->pNext = pHeader->pNext
    Else
        memdebugAssert(mem.pFirst = pHeader, StrPtr(!"mem.pFirst==pHeader"))
        mem.pFirst = pHeader->pNext
    End If
    If pHeader->pNext <> 0 Then
        memdebugAssert(pHeader->pNext->pPrev = pHeader, _
                       StrPtr(!"pHeader->pNext->pPrev==pHeader"))
        pHeader->pNext->pPrev = pHeader->pPrev
    Else
        memdebugAssert(mem.pLast = pHeader, StrPtr(!"mem.pLast==pHeader"))
        mem.pLast = pHeader->pPrev
    End If

    adjustStats(CLng(pHeader->iSize), -1)
    If nFreedBytes <= &H7FFFFFFFULL Then _
        randomFill(pBase, CLng(nFreedBytes))
    memdebugSystemFree(pBase)
    sqlite3_mutex_leave(mem.pMutex)
End Sub

Private Function sqlite3MemRealloc CDecl( _
    ByVal pPrior As Any Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As Any Ptr
    If pPrior = 0 Then Return sqlite3MemMalloc(nByte)
    If nByte <= 0 OrElse mem.disallow <> 0 Then Return 0
    memdebugAssert((nByte And 7) = 0, StrPtr(!"(nByte&7)==0"))

    Dim pOldHeader As SqliteMemdebugHeader Ptr = sqlite3MemsysGetHeader(pPrior)
    If pOldHeader = 0 Then Return 0
    Dim oldSize As SQLITE_C_INT = CLng(pOldHeader->iSize)
    Dim pNew As Any Ptr = sqlite3MemMalloc(nByte)
    If pNew = 0 Then Return 0

    Dim nCopy As SQLITE_C_INT = nByte
    If oldSize < nCopy Then nCopy = oldSize
    memdebugSystemMemcpy(pNew, pPrior, CUInt(nCopy))
    If nByte > oldSize Then
        randomFill(CPtr(UByte Ptr, pNew) + oldSize, nByte - oldSize)
    End If
    sqlite3MemFree(pPrior)
    Return pNew
End Function

Private Function sqlite3MemRoundup CDecl(ByVal nByte As SQLITE_C_INT) As SQLITE_C_INT
    Return memdebugRoundup(nByte)
End Function

Sub sqlite3MemSetDefault CDecl Alias "sqlite3MemSetDefault" () Export
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
End Sub

Private Function memdebugActiveAllocator() As SQLITE_C_INT
    Dim currentMethods As SqliteMemMethods
    sqlite3MemConfigGetMethods(@currentMethods)
    Return CInt(currentMethods.xFree = @sqlite3MemFree)
End Function

/' ------------------------------------------------------------------------- '/
/' Public allocation diagnostics '/
/' ------------------------------------------------------------------------- '/

Sub sqlite3MemdebugSetType CDecl Alias "sqlite3MemdebugSetType" ( _
    ByVal pAllocation As Any Ptr, _
    ByVal eType As UByte _
) Export
    If pAllocation = 0 OrElse memdebugActiveAllocator() = 0 Then Exit Sub
    Dim pHeader As SqliteMemdebugHeader Ptr = sqlite3MemsysGetHeader(pAllocation)
    If pHeader = 0 Then Exit Sub
    memdebugAssert(pHeader->iForeGuard = Cast(SQLITE_C_INT, SQLITE_MEMDEBUG_FOREGUARD), _
                   StrPtr(!"pHeader->iForeGuard==SQLITE_MEMDEBUG_FOREGUARD"))
    pHeader->eType = eType
End Sub

Function sqlite3MemdebugHasType CDecl Alias "sqlite3MemdebugHasType" ( _
    ByVal pAllocation As Const Any Ptr, _
    ByVal eType As UByte _
) As SQLITE_C_INT Export
    If pAllocation = 0 OrElse memdebugActiveAllocator() = 0 Then Return 1
    Dim pHeader As SqliteMemdebugHeader Ptr = sqlite3MemsysGetHeader(pAllocation)
    If pHeader = 0 Then Return 0
    memdebugAssert(pHeader->iForeGuard = Cast(SQLITE_C_INT, SQLITE_MEMDEBUG_FOREGUARD), _
                   StrPtr(!"pHeader->iForeGuard==SQLITE_MEMDEBUG_FOREGUARD"))
    Return CInt((pHeader->eType And eType) <> 0)
End Function

Function sqlite3MemdebugNoType CDecl Alias "sqlite3MemdebugNoType" ( _
    ByVal pAllocation As Const Any Ptr, _
    ByVal eType As UByte _
) As SQLITE_C_INT Export
    If pAllocation = 0 OrElse memdebugActiveAllocator() = 0 Then Return 1
    Dim pHeader As SqliteMemdebugHeader Ptr = sqlite3MemsysGetHeader(pAllocation)
    If pHeader = 0 Then Return 0
    memdebugAssert(pHeader->iForeGuard = Cast(SQLITE_C_INT, SQLITE_MEMDEBUG_FOREGUARD), _
                   StrPtr(!"pHeader->iForeGuard==SQLITE_MEMDEBUG_FOREGUARD"))
    Return CInt((pHeader->eType And eType) = 0)
End Function

Sub sqlite3MemdebugSettitle CDecl Alias "sqlite3MemdebugSettitle" ( _
    ByVal zTitle As Const ZString Ptr _
) Export
    If zTitle = 0 Then Exit Sub
    Dim nTitle As SQLITE_C_INT = sqlite3Strlen30(zTitle) + 1
    sqlite3_mutex_enter(mem.pMutex)
    If nTitle >= SQLITE_MEMDEBUG_TITLE_CAPACITY Then _
        nTitle = SQLITE_MEMDEBUG_TITLE_CAPACITY - 1
    memdebugSystemMemcpy(@mem.zTitle(0), zTitle, CUInt(nTitle))
    mem.zTitle(nTitle) = 0
    mem.nTitle = (nTitle + 7) And Not 7
    sqlite3_mutex_leave(mem.pMutex)
End Sub

Sub sqlite3MemdebugSync CDecl Alias "sqlite3MemdebugSync" () Export
    If mem.xBacktrace = 0 Then Exit Sub
    Dim pHeader As SqliteMemdebugHeader Ptr = mem.pFirst
    While pHeader <> 0
        Dim pBacktrace As Any Ptr Ptr = _
            CPtr(Any Ptr Ptr, pHeader) - pHeader->nBacktraceSlots
        mem.xBacktrace(CLng(pHeader->iSize), _
                       CInt(pHeader->nBacktrace) - 1, @pBacktrace[1])
        pHeader = pHeader->pNext
    Wend
End Sub

Sub sqlite3MemdebugDump CDecl Alias "sqlite3MemdebugDump" ( _
    ByVal zFilename As Const ZString Ptr _
) Export
    If zFilename = 0 Then Exit Sub
    Dim pStream As Any Ptr = memdebugSystemFopen(zFilename, StrPtr(!"w"))
    If pStream = 0 Then
        memdebugSystemFprintf(stderr, _
            StrPtr(!"** Unable to output memory debug output log: %s **\n"), _
            zFilename)
        Exit Sub
    End If

    Dim pHeader As SqliteMemdebugHeader Ptr = mem.pFirst
    While pHeader <> 0
        Dim pBacktrace As Any Ptr Ptr = _
            CPtr(Any Ptr Ptr, pHeader) - pHeader->nBacktraceSlots
        Dim pTitle As Const ZString Ptr = StrPtr(!"???")
        Dim pHeaderBytes As UByte Ptr = CPtr(UByte Ptr, pHeader)
        If pHeader->nTitle <> 0 Then _
            pTitle = CPtr(Const ZString Ptr, pHeaderBytes - _
                CInt(pHeader->nBacktraceSlots) * SizeOf(Any Ptr) - pHeader->nTitle)
        memdebugSystemFprintf(pStream, _
            StrPtr(!"**** %lld bytes at %p from %s ****\n"), _
            pHeader->iSize, _
            CPtr(Any Ptr, pHeaderBytes + SizeOf(SqliteMemdebugHeader)), _
            pTitle)
        If pHeader->nBacktrace > 0 Then
            memdebugSystemFflush(pStream)
#ifdef SQLITE3_FB_GLIBC_BACKTRACE
            memdebugSystemBacktraceSymbolsFd( _
                pBacktrace, pHeader->nBacktrace, memdebugSystemFileno(pStream))
#endif
            memdebugSystemFprintf(pStream, StrPtr(!"\n"))
        End If
        pHeader = pHeader->pNext
    Wend

    memdebugSystemFprintf(pStream, StrPtr(!"COUNTS:\n"))
    For bucket As SQLITE_C_INT = 0 To SQLITE_MEMDEBUG_NCSIZE - 2
        If mem.nAlloc(bucket) <> 0 Then
            memdebugSystemFprintf(pStream, _
                StrPtr(!"   %5d: %10d %10d %10d\n"), _
                bucket * 8, mem.nAlloc(bucket), _
                mem.nCurrent(bucket), mem.mxCurrent(bucket))
        End If
    Next
    If mem.nAlloc(SQLITE_MEMDEBUG_NCSIZE - 1) <> 0 Then
        memdebugSystemFprintf(pStream, _
            StrPtr(!"   %5d: %10d %10d %10d\n"), _
            SQLITE_MEMDEBUG_NCSIZE * 8 - 8, _
            mem.nAlloc(SQLITE_MEMDEBUG_NCSIZE - 1), _
            mem.nCurrent(SQLITE_MEMDEBUG_NCSIZE - 1), _
            mem.mxCurrent(SQLITE_MEMDEBUG_NCSIZE - 1))
    End If
    memdebugSystemFclose(pStream)
End Sub

Function sqlite3MemdebugMallocCount CDecl Alias "sqlite3MemdebugMallocCount" () As SQLITE_C_INT Export
    Dim totalCount As SQLITE_C_INT = 0
    For bucket As SQLITE_C_INT = 0 To SQLITE_MEMDEBUG_NCSIZE - 1
        totalCount += mem.nAlloc(bucket)
    Next
    Return totalCount
End Function
#endif

/' end of sqlite3_memdebug.bas '/
