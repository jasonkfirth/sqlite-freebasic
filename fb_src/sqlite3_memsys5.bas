/'
    Project: SQLite FreeBASIC port

    File: sqlite3_memsys5.bas

    Purpose:

        Provide SQLite's fixed-heap buddy allocator when SQLITE_ENABLE_MEMSYS5 is set.

    Responsibilities:

        - Divide the configured heap into power-of-two allocation blocks.
        - Split free blocks on allocation and merge buddies on release.
        - Serialize allocator operations with SQLite's static memory mutex.
        - Expose the allocator callback table selected by SQLITE_CONFIG_HEAP.

    This file intentionally does NOT contain:

        - Heap ownership, the system allocator, or sqlite3_malloc() dispatch.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_mutex.bi"
#include once "sqlite3_memory_methods.bi"

#ifdef SQLITE_ENABLE_MEMSYS5

#define MEMSYS5_LOGMAX 30
#define MEMSYS5_CTRL_LOGSIZE &H1F
#define MEMSYS5_CTRL_FREE &H20

Type SqliteMem5Link
    nextBlock As SQLITE_C_INT
    previousBlock As SQLITE_C_INT
End Type

Type SqliteMem5Global
    atomSize As SQLITE_C_INT
    blockCount As SQLITE_C_INT
    pool As UByte Ptr
    mutex As Any Ptr
#if defined(SQLITE_DEBUG) OrElse defined(SQLITE_TEST)
    allocationCount As u64
    totalAllocated As u64
    totalExcess As u64
    currentBytesOut As u32
    currentAllocationCount As u32
    maximumBytesOut As u32
    maximumAllocationCount As u32
    maximumRequest As u32
#endif
    freeList(0 To MEMSYS5_LOGMAX) As SQLITE_C_INT
    control As UByte Ptr
End Type

Private Dim Shared memsys5State As SqliteMem5Global

Declare Sub sqlite3MemSys5Log CDecl Alias "sqlite3_log" ( _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Function sqlite3MemSys5Memset CDecl Alias "memset" ( _
    ByVal pDestination As Any Ptr, _
    ByVal fillValue As SQLITE_C_INT, _
    ByVal nByte As SQLITE_SIZE_T _
) As Any Ptr
Declare Function sqlite3MemSys5Memcpy CDecl Alias "memcpy" ( _
    ByVal pDestination As Any Ptr, _
    ByVal pSource As Const Any Ptr, _
    ByVal nByte As SQLITE_SIZE_T _
) As Any Ptr
Declare Function sqlite3ConfigMemStatusEnabled CDecl Alias "sqlite3ConfigMemStatusEnabled" () As SQLITE_C_INT

Private Function memsys5LinkAt(ByVal blockIndex As SQLITE_C_INT) As SqliteMem5Link Ptr
    If memsys5State.pool = 0 OrElse memsys5State.atomSize <= 0 OrElse _
       blockIndex < 0 OrElse blockIndex >= memsys5State.blockCount Then Return 0
    Dim byteOffset As sqlite3_uint64 = _
        CULngInt(blockIndex) * CULngInt(memsys5State.atomSize)
    Return CPtr(SqliteMem5Link Ptr, _
        CPtr(UByte Ptr, memsys5State.pool) + byteOffset)
End Function

Private Sub memsys5Unlink(ByVal blockIndex As SQLITE_C_INT, ByVal logSize As SQLITE_C_INT)
    If blockIndex < 0 OrElse blockIndex >= memsys5State.blockCount OrElse _
       logSize < 0 OrElse logSize > MEMSYS5_LOGMAX OrElse _
       memsys5State.control = 0 Then Return
    If (memsys5State.control[blockIndex] And MEMSYS5_CTRL_LOGSIZE) <> logSize Then Return

    Dim pLink As SqliteMem5Link Ptr = memsys5LinkAt(blockIndex)
    If pLink = 0 Then Return
    Dim nextBlock As SQLITE_C_INT = pLink->nextBlock
    Dim previousBlock As SQLITE_C_INT = pLink->previousBlock
    If previousBlock < 0 Then
        memsys5State.freeList(logSize) = nextBlock
    Else
        Dim pPrevious As SqliteMem5Link Ptr = memsys5LinkAt(previousBlock)
        If pPrevious = 0 Then Return
        pPrevious->nextBlock = nextBlock
    End If
    If nextBlock >= 0 Then
        Dim pNext As SqliteMem5Link Ptr = memsys5LinkAt(nextBlock)
        If pNext <> 0 Then pNext->previousBlock = previousBlock
    End If
End Sub

Private Sub memsys5Link(ByVal blockIndex As SQLITE_C_INT, ByVal logSize As SQLITE_C_INT)
    If blockIndex < 0 OrElse blockIndex >= memsys5State.blockCount OrElse _
       logSize < 0 OrElse logSize > MEMSYS5_LOGMAX OrElse _
       memsys5State.control = 0 Then Return
    If (memsys5State.control[blockIndex] And MEMSYS5_CTRL_LOGSIZE) <> logSize Then Return
    Dim pLink As SqliteMem5Link Ptr = memsys5LinkAt(blockIndex)
    If pLink = 0 Then Return

    Dim oldHead As SQLITE_C_INT = memsys5State.freeList(logSize)
    pLink->nextBlock = oldHead
    pLink->previousBlock = -1
    If oldHead >= 0 Then
        Dim pOldHead As SqliteMem5Link Ptr = memsys5LinkAt(oldHead)
        If pOldHead <> 0 Then pOldHead->previousBlock = blockIndex
    End If
    memsys5State.freeList(logSize) = blockIndex
End Sub

Private Sub memsys5Enter()
    sqlite3_mutex_enter(memsys5State.mutex)
End Sub

Private Sub memsys5Leave()
    sqlite3_mutex_leave(memsys5State.mutex)
End Sub

Private Function memsys5Size CDecl (ByVal pAllocation As Any Ptr) As SQLITE_C_INT
    If pAllocation = 0 OrElse memsys5State.pool = 0 OrElse _
       memsys5State.control = 0 OrElse memsys5State.atomSize <= 0 Then Return 0
    Dim offset As sqlite3_int64 = _
        CPtr(UByte Ptr, pAllocation) - memsys5State.pool
    If offset < 0 OrElse offset Mod memsys5State.atomSize <> 0 Then Return 0
    Dim blockIndex As sqlite3_int64 = offset \ memsys5State.atomSize
    If blockIndex < 0 OrElse blockIndex >= memsys5State.blockCount Then Return 0
    Dim logSize As SQLITE_C_INT = _
        memsys5State.control[blockIndex] And MEMSYS5_CTRL_LOGSIZE
    If (memsys5State.control[blockIndex] And MEMSYS5_CTRL_FREE) <> 0 Then Return 0
    If logSize < 0 OrElse logSize > MEMSYS5_LOGMAX Then Return 0
    Return memsys5State.atomSize * CInt(CUInt(1) Shl logSize)
End Function

Private Function memsys5MallocUnsafe(ByVal nByte As SQLITE_C_INT) As Any Ptr
    If nByte <= 0 OrElse nByte > &H40000000 OrElse _
       memsys5State.control = 0 OrElse memsys5State.atomSize <= 0 Then Return 0

    Dim fullSize As sqlite3_int64 = memsys5State.atomSize
    Dim logSize As SQLITE_C_INT = 0
    While fullSize < nByte
        If fullSize >= &H40000000 Then Return 0
        fullSize *= 2
        logSize += 1
    Wend
    If logSize > MEMSYS5_LOGMAX Then Return 0

#if defined(SQLITE_DEBUG) OrElse defined(SQLITE_TEST)
    If CULngInt(nByte) > memsys5State.maximumRequest Then _
        memsys5State.maximumRequest = CUInt(nByte)
#endif

    Dim listIndex As SQLITE_C_INT = logSize
    While listIndex <= MEMSYS5_LOGMAX AndAlso _
          memsys5State.freeList(listIndex) < 0
        listIndex += 1
    Wend
    If listIndex > MEMSYS5_LOGMAX Then
        sqlite3MemSys5Log(SQLITE_NOMEM, StrPtr("failed to allocate %u bytes"), _
                          CUInt(nByte))
        Return 0
    End If

    Dim blockIndex As SQLITE_C_INT = memsys5State.freeList(listIndex)
    memsys5Unlink(blockIndex, listIndex)
    While listIndex > logSize
        listIndex -= 1
        Dim rightBlock As SQLITE_C_INT = blockIndex + CInt(CUInt(1) Shl listIndex)
        memsys5State.control[rightBlock] = CByte(MEMSYS5_CTRL_FREE Or listIndex)
        memsys5Link(rightBlock, listIndex)
    Wend
    memsys5State.control[blockIndex] = CByte(logSize)

#if defined(SQLITE_DEBUG) OrElse defined(SQLITE_TEST)
    Dim allocationBytes As u32 = CUInt(fullSize)
    memsys5State.allocationCount += 1
    memsys5State.totalAllocated += CULngInt(allocationBytes)
    memsys5State.totalExcess += CULngInt(allocationBytes - CUInt(nByte))
    memsys5State.currentAllocationCount += 1
    memsys5State.currentBytesOut += allocationBytes
    If memsys5State.maximumAllocationCount < memsys5State.currentAllocationCount Then _
        memsys5State.maximumAllocationCount = memsys5State.currentAllocationCount
    If memsys5State.maximumBytesOut < memsys5State.currentBytesOut Then _
        memsys5State.maximumBytesOut = memsys5State.currentBytesOut
#endif

#ifdef SQLITE_DEBUG
    sqlite3MemSys5Memset( _
        CPtr(UByte Ptr, memsys5State.pool) + _
            CULngInt(blockIndex) * CULngInt(memsys5State.atomSize), _
        &HAA, CULngInt(fullSize))
#endif
    Return CPtr(UByte Ptr, memsys5State.pool) + _
        CULngInt(blockIndex) * CULngInt(memsys5State.atomSize)
End Function

Private Sub memsys5FreeUnsafe(ByVal pAllocation As Any Ptr)
    If pAllocation = 0 OrElse memsys5State.pool = 0 OrElse _
       memsys5State.control = 0 OrElse memsys5State.atomSize <= 0 Then Return
    Dim offset As sqlite3_int64 = _
        CPtr(UByte Ptr, pAllocation) - memsys5State.pool
    If offset < 0 OrElse offset Mod memsys5State.atomSize <> 0 Then Return
    Dim blockValue As sqlite3_int64 = offset \ memsys5State.atomSize
    If blockValue < 0 OrElse blockValue >= memsys5State.blockCount Then Return
    Dim blockIndex As SQLITE_C_INT = CInt(blockValue)
    If (memsys5State.control[blockIndex] And MEMSYS5_CTRL_FREE) <> 0 Then Return

    Dim logSize As SQLITE_C_INT = _
        memsys5State.control[blockIndex] And MEMSYS5_CTRL_LOGSIZE
    If logSize < 0 OrElse logSize > MEMSYS5_LOGMAX Then Return
    Dim blockCount As u32 = CUInt(1) Shl logSize
    If CULngInt(blockIndex) + CULngInt(blockCount) > _
       CULngInt(memsys5State.blockCount) Then Return

    memsys5State.control[blockIndex] Or= MEMSYS5_CTRL_FREE
    memsys5State.control[blockIndex + blockCount - 1] Or= MEMSYS5_CTRL_FREE
#if defined(SQLITE_DEBUG) OrElse defined(SQLITE_TEST)
    If memsys5State.currentAllocationCount > 0 Then _
        memsys5State.currentAllocationCount -= 1
    Dim allocatedBytes As u32 = blockCount * CUInt(memsys5State.atomSize)
    If memsys5State.currentBytesOut >= allocatedBytes Then _
        memsys5State.currentBytesOut -= allocatedBytes
#endif
    memsys5State.control[blockIndex] = CByte(MEMSYS5_CTRL_FREE Or logSize)

    While logSize < MEMSYS5_LOGMAX
        Dim buddyIndex As SQLITE_C_INT
        If (blockIndex And CInt(blockCount)) <> 0 Then
            buddyIndex = blockIndex - CInt(blockCount)
            If buddyIndex < 0 Then Exit While
        Else
            buddyIndex = blockIndex + CInt(blockCount)
            If buddyIndex >= memsys5State.blockCount Then Exit While
        End If
        If memsys5State.control[buddyIndex] <> _
           CByte(MEMSYS5_CTRL_FREE Or logSize) Then Exit While

        memsys5Unlink(buddyIndex, logSize)
        logSize += 1
        If buddyIndex < blockIndex Then
            memsys5State.control[buddyIndex] = _
                CByte(MEMSYS5_CTRL_FREE Or logSize)
            memsys5State.control[blockIndex] = 0
            blockIndex = buddyIndex
        Else
            memsys5State.control[blockIndex] = _
                CByte(MEMSYS5_CTRL_FREE Or logSize)
            memsys5State.control[buddyIndex] = 0
        End If
        blockCount *= 2
    Wend

#ifdef SQLITE_DEBUG
    sqlite3MemSys5Memset( _
        CPtr(UByte Ptr, memsys5State.pool) + _
            CULngInt(blockIndex) * CULngInt(memsys5State.atomSize), _
        &H55, CULngInt(blockCount) * CULngInt(memsys5State.atomSize))
#endif
    memsys5Link(blockIndex, logSize)
End Sub

Private Function memsys5Malloc CDecl (ByVal nByte As SQLITE_C_INT) As Any Ptr
    If nByte <= 0 Then Return 0
    memsys5Enter()
    Dim pAllocation As Any Ptr = memsys5MallocUnsafe(nByte)
    memsys5Leave()
    Return pAllocation
End Function

Private Sub memsys5Free CDecl (ByVal pAllocation As Any Ptr)
    If pAllocation = 0 Then Return
    memsys5Enter()
    memsys5FreeUnsafe(pAllocation)
    memsys5Leave()
End Sub

Private Function memsys5Realloc CDecl ( _
    ByVal pAllocation As Any Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As Any Ptr
    If pAllocation = 0 OrElse nByte < 0 OrElse _
       (nByte And (nByte - 1)) <> 0 Then Return 0
    If nByte = 0 Then Return 0
    Dim oldSize As SQLITE_C_INT = memsys5Size(pAllocation)
    If oldSize <= 0 Then Return 0
    If nByte <= oldSize Then Return pAllocation
    Dim pNew As Any Ptr = memsys5Malloc(nByte)
    If pNew <> 0 Then
        sqlite3MemSys5Memcpy(pNew, pAllocation, CULngInt(oldSize))
        memsys5Free(pAllocation)
    End If
    Return pNew
End Function

Private Function memsys5Roundup CDecl (ByVal nByte As SQLITE_C_INT) As SQLITE_C_INT
    If nByte < 0 OrElse memsys5State.atomSize <= 0 Then Return 0
    If nByte <= memsys5State.atomSize Then Return memsys5State.atomSize
    If nByte <= memsys5State.atomSize * 2 Then Return memsys5State.atomSize * 2
    If nByte > &H40000000 Then Return 0
    If nByte > &H20000000 Then Return &H40000000
    If nByte > &H10000000 Then Return &H20000000

    Dim fullSize As sqlite3_int64 = memsys5State.atomSize * 8
    While fullSize < nByte
        fullSize *= 4
    Wend
    If fullSize \ 2 >= nByte Then Return CInt(fullSize \ 2)
    Return CInt(fullSize)
End Function

Private Function memsys5Log(ByVal value As SQLITE_C_INT) As SQLITE_C_INT
    Dim logSize As SQLITE_C_INT = 0
    While logSize < SizeOf(SQLITE_C_INT) * 8 - 1 AndAlso _
          (CLngInt(1) Shl logSize) < value
        logSize += 1
    Wend
    Return logSize
End Function

Private Function memsys5Init CDecl (ByVal pUnused As Any Ptr) As SQLITE_C_INT
    Dim pHeap As Any Ptr = 0
    Dim heapSize As SQLITE_C_INT = 0
    Dim minimumRequest As SQLITE_C_INT = 0
    sqlite3ConfigGetHeap(@pHeap, @heapSize, @minimumRequest)
    memsys5State.mutex = 0
    If SizeOf(SqliteMem5Link) <= 0 OrElse _
       (SizeOf(SqliteMem5Link) And (SizeOf(SqliteMem5Link) - 1)) <> 0 OrElse _
       pHeap = 0 OrElse heapSize <= 0 Then Return SQLITE_ERROR

    Dim minimumLog As SQLITE_C_INT = memsys5Log(minimumRequest)
    memsys5State.atomSize = CInt(CLngInt(1) Shl minimumLog)
    While SizeOf(SqliteMem5Link) > memsys5State.atomSize
        memsys5State.atomSize *= 2
    Wend
    memsys5State.blockCount = heapSize \ (memsys5State.atomSize + SizeOf(UByte))
    memsys5State.pool = CPtr(UByte Ptr, pHeap)
    memsys5State.control = memsys5State.pool + _
        CULngInt(memsys5State.blockCount) * CULngInt(memsys5State.atomSize)

#if defined(SQLITE_DEBUG) OrElse defined(SQLITE_TEST)
    memsys5State.allocationCount = 0
    memsys5State.totalAllocated = 0
    memsys5State.totalExcess = 0
    memsys5State.currentBytesOut = 0
    memsys5State.currentAllocationCount = 0
    memsys5State.maximumBytesOut = 0
    memsys5State.maximumAllocationCount = 0
    memsys5State.maximumRequest = 0
#endif
    For iList As SQLITE_C_INT = 0 To MEMSYS5_LOGMAX
        memsys5State.freeList(iList) = -1
    Next

    Dim blockOffset As SQLITE_C_INT = 0
    For logSize As SQLITE_C_INT = MEMSYS5_LOGMAX To 0 Step -1
        Dim newBlockCount As SQLITE_C_INT = CInt(CUInt(1) Shl logSize)
        If CULngInt(blockOffset) + CULngInt(newBlockCount) <= _
           CULngInt(memsys5State.blockCount) Then
            memsys5State.control[blockOffset] = _
                CByte(MEMSYS5_CTRL_FREE Or logSize)
            memsys5Link(blockOffset, logSize)
            blockOffset += newBlockCount
        End If
    Next

    If sqlite3ConfigMemStatusEnabled() = 0 Then _
        memsys5State.mutex = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MEM)
    Return SQLITE_OK
End Function

Private Sub memsys5Shutdown CDecl (ByVal pUnused As Any Ptr)
    memsys5State.mutex = 0
End Sub

Private Dim Shared As Const SqliteMemMethods memsys5Methods = _
    Type<SqliteMemMethods>( _
        ProcPtr(memsys5Malloc), _
        ProcPtr(memsys5Free), _
        ProcPtr(memsys5Realloc), _
        ProcPtr(memsys5Size), _
        ProcPtr(memsys5Roundup), _
        ProcPtr(memsys5Init), _
        ProcPtr(memsys5Shutdown), _
        0 _
    )

Function sqlite3MemGetMemsys5 CDecl Alias "sqlite3MemGetMemsys5" () _
    As Const SqliteMemMethods Ptr Export
    Return @memsys5Methods
End Function

#endif

/' end of sqlite3_memsys5.bas '/
