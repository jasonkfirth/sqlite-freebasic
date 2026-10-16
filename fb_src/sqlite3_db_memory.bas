/'
    Project: SQLite FreeBASIC port

    File: sqlite3_db_memory.bas

    Purpose:

        Port the database-aware allocation paths from src/malloc.c.

    Responsibilities:

        - Initialize the interrupt mutex used by cross-thread interrupt calls.
        - Latch allocation failure per connection until explicitly cleared.
        - Disable lookaside use and propagate OOM through active nested parses.
        - Convert API-exit OOM state into a stable per-connection result code.
        - Allocate from large or 128-byte lookaside slots when a request fits.
        - Classify each slot by its pool range for free and reallocation paths.
        - Return heap and lookaside allocations through matching free paths.
        - Count released heap and lookaside bytes while pnBytesFreed is active.
        - Preserve slot sizes when lookaside allocations grow into heap blocks.

    This file intentionally does NOT contain:

        - Connection mutexes, memory-status counters, or allocator callbacks.
        - The full private sqlite3 structure from SQLite's C implementation.
'/

#lang "fb"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_parser_types.bi"

Extern "C"
    Declare Function sqlite3SystemMemset CDecl Alias "memset" ( _
        ByVal p As Any Ptr, _
        ByVal value As SQLITE_C_INT, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
    Declare Function sqlite3SystemMemcpy CDecl Alias "memcpy" ( _
        ByVal destination As Any Ptr, _
        ByVal source As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
    Declare Function sqlite3SystemStrlen CDecl Alias "strlen" ( _
        ByVal z As Const ZString Ptr _
    ) As SQLITE_SIZE_T
End Extern

Declare Function sqlite3Malloc CDecl Alias "sqlite3Malloc" ( _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Function sqlite3Realloc CDecl Alias "sqlite3Realloc" ( _
    ByVal pOld As Any Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Function sqlite3MallocSize CDecl Alias "sqlite3MallocSize" ( _
    ByVal p As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Declare Function sqlite3ErrorToParser CDecl Alias "sqlite3ErrorToParser" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal errorCode As SQLITE_C_INT _
) As SQLITE_C_INT
/' ------------------------------------------------------------------------- '/
/' Connection and lookaside state '/
/' ------------------------------------------------------------------------- '/

Function sqlite3DbInterruptMutexInitialize CDecl Alias "sqlite3DbInterruptMutexInitialize" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT Export
    If db = 0 Then Return SQLITE_MISUSE
    If db->interruptMutex <> 0 Then Return SQLITE_OK
    ' The public mutex API returns a no-op mutex in THREADSAFE=0 builds.
    db->interruptMutex = sqlite3_mutex_alloc(SQLITE_MUTEX_FAST)
    If db->interruptMutex = 0 Then Return SQLITE_NOMEM
    Return SQLITE_OK
End Function

Function sqlite3DbContextInit CDecl Alias "sqlite3DbContextInit" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal createConnectionMutex As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If db = 0 Then Return SQLITE_MISUSE
    db->mutex = 0
    db->interruptMutex = 0
    db->isInterrupted = 0
    db->nVdbeActive = 0
    db->pVfs = 0
    db->pMainBtree = 0
    db->nDb = 2
    For databaseIndex As SQLITE_C_INT = 0 To SQLITE_MAX_ATTACHED + 1
        db->aDb(databaseIndex).zDbSName = 0
        db->aDb(databaseIndex).pBt = 0
        db->aDb(databaseIndex).safety_level = 0
        db->aDb(databaseIndex).bSyncSet = 0
        db->aDb(databaseIndex).pSchema = 0
    Next
    db->aDb(0).zDbSName = StrPtr("main")
    db->aDb(1).zDbSName = StrPtr("temp")
    db->pVdbe = 0
    db->pUserFunctions = 0
    db->pDbData = 0
    sqlite3HashInit(@db->aCollSeq)
    db->pDfltColl = 0
    db->xCollNeeded = 0
    db->xCollNeeded16 = 0
    db->pCollNeededArg = 0
    db->busyHandler.xBusyHandler = 0
    db->busyHandler.pBusyArg = 0
    db->busyHandler.nBusy = 0
    db->busyHandler.mxBusy = 0
    db->busyTimeout = 0
    db->pParse = 0
    db->schemaInitBusy = 0
    db->pSavepoint = 0
    db->nSavepoint = 0
    db->isTransactionSavepoint = 0
    db->openFlags = 0
    db->enc = SQLITE_UTF8
    db->flags = 0
    db->dbOptFlags = 0
    db->temp_store = 0
    db->mDbFlags = 0
    db->errorCode = SQLITE_OK
    db->errMask = &HFF
    db->iSysErrno = 0
    db->lastRowid = 0
    db->nChange = 0
    db->nTotalChange = 0
    db->nSpill = 0
    db->nVdbeExec = 0
    db->autoCommit = 1
    db->nextAutovac = -1
    db->nextPagesize = 0
#ifndef SQLITE_OMIT_VIRTUALTABLE
    db->vtabOnConflict = 0
#endif
    db->errByteOffset = -1
    db->isOpen = 0
    db->isZombie = 0
    db->mallocFailed = 0
    db->bBenignMalloc = 0
    db->pnBytesFreed = 0
    Dim limitInitCode As SQLITE_C_INT = sqlite3LimitInitialize(db)
    If limitInitCode <> SQLITE_OK Then Return limitInitCode
    db->nFpDigit = 17
    db->lookaside.pStart = 0
    db->lookaside.pEnd = 0
    db->lookaside.pTrueEnd = 0
    db->lookaside.pMiddle = 0
    db->lookaside.pInit = 0
    db->lookaside.pFree = 0
    db->lookaside.pSmallInit = 0
    db->lookaside.pSmallFree = 0
    db->lookaside.bDisable = 0
    db->lookaside.sz = 0
    db->lookaside.szTrue = 0
    db->lookaside.bMalloced = 0
    db->lookaside.szSmall = 0
    db->lookaside.nSlot = 0
    db->lookasideInitCount = 0
    db->lookasideFreeCount = 0
    db->lookasideOutCount = 0
    For i As Long = 0 To 2
        db->lookaside.anStat(i) = 0
    Next
    If createConnectionMutex <> 0 Then
        db->mutex = sqlite3_mutex_alloc(SQLITE_MUTEX_RECURSIVE)
        If db->mutex = 0 Then Return SQLITE_NOMEM
    End If
    Dim interruptMutexResult As SQLITE_C_INT = _
        sqlite3DbInterruptMutexInitialize(db)
    If interruptMutexResult <> SQLITE_OK Then
        sqlite3_mutex_free(db->mutex)
        db->mutex = 0
        Return interruptMutexResult
    End If
    Return SQLITE_OK
End Function

Function sqlite3DbLookasideInit CDecl Alias "sqlite3DbLookasideInit" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal slotCount As u32, _
    ByVal requestedSlotSize As u32 _
) As SQLITE_C_INT Export

    If db = 0 Then Return SQLITE_MISUSE
    If db->pnBytesFreed <> 0 Then Return SQLITE_MISUSE
    If db->lookasideOutCount <> 0 OrElse _
       db->lookasideInitCount + db->lookasideFreeCount <> db->lookaside.nSlot Then Return SQLITE_MISUSE

    Dim slotSize As sqlite3_uint64 = CULngInt(requestedSlotSize)
    If slotSize > 65528 Then slotSize = 65528
    slotSize -= slotSize Mod 8
    If slotCount = 0 OrElse slotSize <= SizeOf(Any Ptr) Then
        Dim pOldPool As Any Ptr = db->lookaside.pStart
        db->lookaside.pStart = 0
        db->lookaside.pEnd = 0
        db->lookaside.pTrueEnd = 0
        db->lookaside.pMiddle = 0
        db->lookaside.pInit = 0
        db->lookaside.pFree = 0
        db->lookaside.pSmallInit = 0
        db->lookaside.pSmallFree = 0
        db->lookaside.bDisable = 0
        db->lookaside.sz = 0
        db->lookaside.szTrue = 0
        db->lookaside.bMalloced = 0
        db->lookaside.szSmall = 0
        db->lookaside.nSlot = 0
        db->lookasideInitCount = 0
        db->lookasideFreeCount = 0
        db->lookasideOutCount = 0
        For i As Long = 0 To 2
            db->lookaside.anStat(i) = 0
        Next
        sqlite3_free(pOldPool)
        Return SQLITE_OK
    End If

    Dim maximumLookasideBytes As sqlite3_uint64 = &H7FFF0000ULL
    Dim maximumSlotCount As sqlite3_uint64 = maximumLookasideBytes \ slotSize
    Dim configuredSlotCount As sqlite3_uint64 = CULngInt(slotCount)
    If configuredSlotCount > maximumSlotCount Then _
        configuredSlotCount = maximumSlotCount
    If configuredSlotCount = 0 Then Return SQLITE_OK

    Dim totalBytes As sqlite3_uint64 = configuredSlotCount * slotSize
    If totalBytes > SQLITE_MAX_ALLOCATION_SIZE Then Return SQLITE_TOOBIG

    Dim pPool As UByte Ptr = CPtr(UByte Ptr, sqlite3Malloc(totalBytes))
    If pPool = 0 Then Return SQLITE_NOMEM

    Dim nBig As sqlite3_uint64 = configuredSlotCount
    Dim nSmall As sqlite3_uint64 = 0
#if SQLITE_LOOKASIDE_SMALL > 0
    If slotSize >= CULngInt(SQLITE_LOOKASIDE_SMALL) * 3 Then
        nBig = totalBytes \ (CULngInt(SQLITE_LOOKASIDE_SMALL) * 3 + slotSize)
        nSmall = (totalBytes - slotSize * nBig) \ SQLITE_LOOKASIDE_SMALL
    ElseIf slotSize >= CULngInt(SQLITE_LOOKASIDE_SMALL) * 2 Then
        nBig = totalBytes \ (CULngInt(SQLITE_LOOKASIDE_SMALL) + slotSize)
        nSmall = (totalBytes - slotSize * nBig) \ SQLITE_LOOKASIDE_SMALL
    End If
#endif

    Dim pMiddle As UByte Ptr = pPool + nBig * slotSize
    Dim pEnd As UByte Ptr = pMiddle
    If nSmall > 0 Then _
        pEnd += nSmall * CULngInt(SQLITE_LOOKASIDE_SMALL)

    Dim pInit As SqliteLookasideSlot Ptr = 0
    If nBig > 0 Then
        For i As sqlite3_uint64 = 0 To nBig - 1
            Dim pSlot As SqliteLookasideSlot Ptr = CPtr(SqliteLookasideSlot Ptr, _
                pPool + (i * slotSize))
            pSlot->pNext = pInit
            pInit = pSlot
        Next
    End If

    Dim pSmallInit As SqliteLookasideSlot Ptr = 0
    If nSmall > 0 Then
        For i As sqlite3_uint64 = 0 To nSmall - 1
            Dim pSlot As SqliteLookasideSlot Ptr = CPtr(SqliteLookasideSlot Ptr, _
                pMiddle + (i * CULngInt(SQLITE_LOOKASIDE_SMALL)))
            pSlot->pNext = pSmallInit
            pSmallInit = pSlot
        Next
    End If

    Dim pOldPool As Any Ptr = db->lookaside.pStart
    db->lookaside.pStart = pPool
    db->lookaside.pEnd = pEnd
    db->lookaside.pTrueEnd = pPool + totalBytes
    db->lookaside.pMiddle = pMiddle
    db->lookaside.pInit = pInit
    db->lookaside.pFree = 0
    db->lookaside.pSmallInit = pSmallInit
    db->lookaside.pSmallFree = 0
    db->lookaside.sz = CUInt(slotSize)
    db->lookaside.szTrue = CUShort(slotSize)
    db->lookaside.bDisable = 0
    db->lookaside.bMalloced = 1
    db->lookaside.szSmall = CUInt(IIf( _
        nSmall > 0, SQLITE_LOOKASIDE_SMALL, 0))
    db->lookaside.nSlot = CUInt(nBig + nSmall)
    db->lookasideInitCount = CUInt(nBig + nSmall)
    db->lookasideFreeCount = 0
    db->lookasideOutCount = 0
    For i As Long = 0 To 2
        db->lookaside.anStat(i) = 0
    Next
    sqlite3_free(pOldPool)
    Return SQLITE_OK
End Function

Private Function sqlite3LookasideSlotClass( _
    ByVal db As sqlite3 Ptr, _
    ByVal p As Any Ptr, _
    ByVal pSlotSize As u32 Ptr _
) As SQLITE_C_INT
    If pSlotSize <> 0 Then pSlotSize[0] = 0
    If db = 0 OrElse p = 0 OrElse db->lookaside.pStart = 0 OrElse _
       db->lookaside.pTrueEnd = 0 Then Return 0

    Dim pByte As UByte Ptr = CPtr(UByte Ptr, p)
    If pByte < db->lookaside.pStart OrElse pByte >= db->lookaside.pTrueEnd Then _
        Return 0

    If pByte < db->lookaside.pMiddle Then
        Dim offset As ULongInt = CULngInt(pByte - db->lookaside.pStart)
        If db->lookaside.szTrue = 0 OrElse _
           offset Mod db->lookaside.szTrue <> 0 Then Return -1
        If pSlotSize <> 0 Then pSlotSize[0] = db->lookaside.szTrue
        Return 1
    End If

    If pByte < db->lookaside.pEnd AndAlso db->lookaside.szSmall <> 0 Then
        Dim offset As ULongInt = CULngInt(pByte - db->lookaside.pMiddle)
        If offset Mod db->lookaside.szSmall <> 0 Then Return -1
        If pSlotSize <> 0 Then pSlotSize[0] = db->lookaside.szSmall
        Return 1
    End If
    Return -1
End Function

Private Function isLookaside( _
    ByVal db As sqlite3 Ptr, _
    ByVal p As Any Ptr _
) As SQLITE_C_INT
    If db = 0 OrElse p = 0 OrElse db->lookaside.pStart = 0 OrElse _
       db->lookaside.pTrueEnd = 0 Then Return 0
    Dim address As ULongInt = CULngInt(p)
    Return CInt(address >= CULngInt(db->lookaside.pStart) AndAlso _
                address < CULngInt(db->lookaside.pTrueEnd))
End Function

Function lookasideMallocSize CDecl Alias "lookasideMallocSize" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal p As Any Ptr _
) As SQLITE_C_INT Export
    If isLookaside(db, p) = 0 Then Return 0
    Dim pByte As UByte Ptr = CPtr(UByte Ptr, p)
    If pByte < db->lookaside.pMiddle Then Return CLng(db->lookaside.szTrue)
    Return CLng(db->lookaside.szSmall)
End Function

Function sqlite3DbContextDestroy CDecl Alias "sqlite3DbContextDestroy" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT Export

    If db = 0 Then Return SQLITE_MISUSE
    If db->pVdbe <> 0 Then Return SQLITE_BUSY
    If db->pnBytesFreed <> 0 Then Return SQLITE_MISUSE
    sqlite3DbFunctionDestroy(db)
    If db->lookasideOutCount <> 0 OrElse _
       db->lookasideInitCount + db->lookasideFreeCount <> db->lookaside.nSlot Then Return SQLITE_MISUSE
    While db->pSavepoint <> 0
        Dim pSavepoint As SqliteSavepoint Ptr = db->pSavepoint
        db->pSavepoint = pSavepoint->pNext
        sqlite3DbFree(db, pSavepoint)
    Wend
    db->nSavepoint = 0
    db->isTransactionSavepoint = 0
    If db->lookaside.bMalloced <> 0 Then sqlite3_free(db->lookaside.pStart)
    db->lookaside.pStart = 0
    db->lookaside.pEnd = 0
    db->lookaside.pTrueEnd = 0
    db->lookaside.pMiddle = 0
    db->lookaside.pInit = 0
    db->lookaside.pFree = 0
    db->lookaside.pSmallInit = 0
    db->lookaside.pSmallFree = 0
    db->lookaside.bDisable = 0
    db->lookaside.sz = 0
    db->lookaside.szTrue = 0
    db->lookaside.bMalloced = 0
    db->lookaside.szSmall = 0
    db->lookaside.nSlot = 0
    db->lookasideInitCount = 0
    db->lookasideFreeCount = 0
    db->lookasideOutCount = 0
    For i As Long = 0 To 2
        db->lookaside.anStat(i) = 0
    Next
    db->mallocFailed = 0
    db->bBenignMalloc = 0
    db->pnBytesFreed = 0
    sqlite3_mutex_free(db->interruptMutex)
    db->interruptMutex = 0
    sqlite3_mutex_free(db->mutex)
    db->mutex = 0
    Return SQLITE_OK
End Function

Sub sqlite3DbEnter CDecl Alias "sqlite3DbEnter" (ByVal db As sqlite3 Ptr) Export
    If db <> 0 Then sqlite3_mutex_enter(db->mutex)
End Sub

Sub sqlite3DbLeave CDecl Alias "sqlite3DbLeave" (ByVal db As sqlite3 Ptr) Export
    If db <> 0 Then sqlite3_mutex_leave(db->mutex)
End Sub

/' ------------------------------------------------------------------------- '/
/' Database allocation '/
/' ------------------------------------------------------------------------- '/

Private Function dbMallocRawFinish( _
    ByVal db As sqlite3 Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
    If db = 0 Then Return 0
    Dim p As Any Ptr = sqlite3Malloc(nByte)
    If p = 0 Then sqlite3OomFault(db)
    Return p
End Function

Function sqlite3DbMallocRawNN CDecl Alias "sqlite3DbMallocRawNN" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr Export

    If db = 0 Then Return 0
    If db->mallocFailed <> 0 OrElse db->pnBytesFreed <> 0 Then Return 0

    If db->lookaside.bDisable = 0 AndAlso db->lookaside.sz <> 0 Then
        If nByte > db->lookaside.sz Then
            db->lookaside.anStat(1) += 1
        Else
            Dim pSlot As SqliteLookasideSlot Ptr = 0
            If db->lookaside.szSmall <> 0 AndAlso _
               nByte <= db->lookaside.szSmall Then
                If db->lookaside.pSmallFree <> 0 Then
                    pSlot = db->lookaside.pSmallFree
                    db->lookaside.pSmallFree = pSlot->pNext
                    db->lookasideFreeCount -= 1
                ElseIf db->lookaside.pSmallInit <> 0 Then
                    pSlot = db->lookaside.pSmallInit
                    db->lookaside.pSmallInit = pSlot->pNext
                    db->lookasideInitCount -= 1
                End If
            End If
            If pSlot = 0 Then
                If db->lookaside.pFree <> 0 Then
                    pSlot = db->lookaside.pFree
                    db->lookaside.pFree = pSlot->pNext
                    db->lookasideFreeCount -= 1
                ElseIf db->lookaside.pInit <> 0 Then
                    pSlot = db->lookaside.pInit
                    db->lookaside.pInit = pSlot->pNext
                    db->lookasideInitCount -= 1
                End If
            End If
            If pSlot <> 0 Then
                pSlot->pNext = 0
                db->lookaside.anStat(0) += 1
                db->lookasideOutCount += 1
                Return pSlot
            End If
            db->lookaside.anStat(2) += 1
        End If
    End If

    Return dbMallocRawFinish(db, nByte)
End Function

Function sqlite3DbMallocRaw CDecl Alias "sqlite3DbMallocRaw" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr Export

    If db = 0 Then Return sqlite3Malloc(nByte)
    Return sqlite3DbMallocRawNN(db, nByte)
End Function

Function sqlite3DbMallocZero CDecl Alias "sqlite3DbMallocZero" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr Export

    Dim p As Any Ptr = sqlite3DbMallocRaw(db, nByte)
    If p <> 0 AndAlso nByte > 0 Then sqlite3SystemMemset(p, 0, nByte)
    Return p
End Function

Function sqlite3DbMallocSize CDecl Alias "sqlite3DbMallocSize" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal p As Any Ptr _
) As SQLITE_C_INT Export

    If p = 0 Then Return 0
    If isLookaside(db, p) <> 0 Then
        Return lookasideMallocSize(db, p)
    End If
    Return sqlite3MallocSize(p)
End Function

Private Sub measureAllocationSize(ByVal db As sqlite3 Ptr, ByVal p As Any Ptr)
    If db = 0 OrElse p = 0 OrElse db->pnBytesFreed = 0 Then Exit Sub
    Dim allocationSize As SQLITE_C_INT = sqlite3DbMallocSize(db, p)
    If allocationSize <= 0 Then Exit Sub
    Dim priorSize As SQLITE_C_INT = db->pnBytesFreed[0]
    If priorSize < 0 OrElse allocationSize > &H7FFFFFFF - priorSize Then
        db->pnBytesFreed[0] = &H7FFFFFFF
    Else
        db->pnBytesFreed[0] = priorSize + allocationSize
    End If
End Sub

Sub sqlite3DbFreeNN CDecl Alias "sqlite3DbFreeNN" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal p As Any Ptr _
) Export

    If p = 0 Then Exit Sub
    If db <> 0 AndAlso db->pnBytesFreed <> 0 Then
        measureAllocationSize(db, p)
        Exit Sub
    End If
    If isLookaside(db, p) <> 0 Then
        Dim slotSize As u32 = 0
        Dim slotClass As SQLITE_C_INT = sqlite3LookasideSlotClass(db, p, @slotSize)
        If slotClass <> 0 Then
            If slotClass < 0 Then Exit Sub
            If db->lookasideOutCount = 0 Then Exit Sub
            Dim pSlot As SqliteLookasideSlot Ptr = CPtr(SqliteLookasideSlot Ptr, p)
            If slotSize = db->lookaside.szSmall Then
                pSlot->pNext = db->lookaside.pSmallFree
                db->lookaside.pSmallFree = pSlot
            Else
                pSlot->pNext = db->lookaside.pFree
                db->lookaside.pFree = pSlot
            End If
            db->lookasideFreeCount += 1
            If db->lookasideOutCount <> 0 Then db->lookasideOutCount -= 1
            Exit Sub
        End If
    End If
    sqlite3_free(p)
End Sub

Sub sqlite3DbNNFreeNN CDecl Alias "sqlite3DbNNFreeNN" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal p As Any Ptr _
) Export
    If db = 0 OrElse p = 0 Then Exit Sub
    sqlite3DbFreeNN(db, p)
End Sub

Sub sqlite3DbFree CDecl Alias "sqlite3DbFree" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal p As Any Ptr _
) Export
    If p <> 0 Then sqlite3DbFreeNN(db, p)
End Sub

/' ------------------------------------------------------------------------- '/
/' Reallocation and string ownership '/
/' ------------------------------------------------------------------------- '/

Private Function dbReallocFinish( _
    ByVal db As sqlite3 Ptr, _
    ByVal pOld As Any Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
    If db = 0 OrElse pOld = 0 OrElse db->mallocFailed <> 0 OrElse _
       db->pnBytesFreed <> 0 Then Return 0

    If isLookaside(db, pOld) <> 0 Then
        Dim slotSize As u32 = 0
        If sqlite3LookasideSlotClass(db, pOld, @slotSize) <= 0 Then Return 0
        Dim oldSize As SQLITE_C_INT = lookasideMallocSize(db, pOld)
        If oldSize <= 0 Then Return 0
        Dim pNew As Any Ptr = sqlite3DbMallocRawNN(db, nByte)
        If pNew <> 0 Then
            Dim copySize As sqlite3_uint64 = CULngInt(oldSize)
            If copySize > nByte Then copySize = nByte
            If copySize > 0 Then sqlite3SystemMemcpy(pNew, pOld, copySize)
            sqlite3DbFreeNN(db, pOld)
        End If
        Return pNew
    End If

    Dim pNew As Any Ptr = sqlite3Realloc(pOld, nByte)
    If pNew = 0 Then sqlite3OomFault(db)
    Return pNew
End Function

Function sqlite3DbRealloc CDecl Alias "sqlite3DbRealloc" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pOld As Any Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr Export

    If db = 0 Then Return sqlite3Realloc(pOld, nByte)
    If pOld = 0 Then Return sqlite3DbMallocRawNN(db, nByte)
    If db->mallocFailed <> 0 OrElse db->pnBytesFreed <> 0 Then Return 0

    If isLookaside(db, pOld) <> 0 Then
        Dim slotSize As u32 = 0
        If sqlite3LookasideSlotClass(db, pOld, @slotSize) <= 0 Then Return 0
        Dim allocationSize As SQLITE_C_INT = lookasideMallocSize(db, pOld)
        If allocationSize <= 0 Then Return 0
        If nByte <= CULngInt(allocationSize) Then Return pOld
    End If

    Return dbReallocFinish(db, pOld, nByte)
End Function

Function sqlite3DbReallocOrFree CDecl Alias "sqlite3DbReallocOrFree" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pOld As Any Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr Export

    If pOld <> 0 AndAlso nByte = 0 Then
        If db <> 0 AndAlso db->lookaside.pStart <> 0 Then
            Dim slotSize As u32 = 0
            Dim slotClass As SQLITE_C_INT = _
                sqlite3LookasideSlotClass(db, pOld, @slotSize)
            If slotClass > 0 Then Return pOld
            If slotClass < 0 Then Return 0
        End If
        sqlite3DbFree(db, pOld)
        Return 0
    End If

    Dim pNew As Any Ptr = sqlite3DbRealloc(db, pOld, nByte)
    If pNew = 0 Then sqlite3DbFree(db, pOld)
    Return pNew
End Function

Function sqlite3DbStrDup CDecl Alias "sqlite3DbStrDup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal z As Const ZString Ptr _
) As Any Ptr Export

    If z = 0 Then Return 0
    Dim nByte As ULongInt = sqlite3SystemStrlen(z) + 1
    Dim zCopy As Any Ptr = sqlite3DbMallocRaw(db, nByte)
    If zCopy <> 0 Then sqlite3SystemMemcpy(zCopy, z, nByte)
    Return zCopy
End Function

Function sqlite3DbStrNDup CDecl Alias "sqlite3DbStrNDup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal z As Const ZString Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr Export

    If z = 0 Then Return 0
    If nByte > &H7FFFFFFF Then
        If db <> 0 AndAlso db->bBenignMalloc = 0 Then db->mallocFailed = 1
        Return 0
    End If
    Dim zCopy As Any Ptr = sqlite3DbMallocRawNN(db, nByte + 1)
    If zCopy = 0 Then Return 0
    If nByte <> 0 Then sqlite3SystemMemcpy(zCopy, z, nByte)
    CPtr(UByte Ptr, zCopy)[nByte] = 0
    Return zCopy
End Function

Private Function sqlite3DbIsSpace(ByVal value As UByte) As Long
    If value = 32 OrElse (value >= 9 AndAlso value <= 13) Then Return -1
    Return 0
End Function

Function sqlite3DbSpanDup CDecl Alias "sqlite3DbSpanDup" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zStartArgument As Const ZString Ptr, _
    ByVal zEndArgument As Const ZString Ptr _
) As Any Ptr Export

    If zStartArgument = 0 OrElse zEndArgument = 0 Then Return 0
    Dim zStart As Const UByte Ptr = CPtr(Const UByte Ptr, zStartArgument)
    Dim zEnd As Const UByte Ptr = CPtr(Const UByte Ptr, zEndArgument)
    If zEnd < zStart Then Return 0

    While zStart < zEnd AndAlso sqlite3DbIsSpace(zStart[0])
        zStart += 1
    Wend
    Dim nByte As ULongInt = CULngInt(zEnd - zStart)
    While nByte > 0 AndAlso sqlite3DbIsSpace(zStart[nByte - 1])
        nByte -= 1
    Wend
    Return sqlite3DbStrNDup(db, CPtr(Const ZString Ptr, zStart), nByte)
End Function

Sub sqlite3SetString CDecl Alias "sqlite3SetString" ( _
    ByVal pzArgument As Any Ptr, _
    ByVal db As sqlite3 Ptr, _
    ByVal zNew As Const ZString Ptr _
) Export

    If pzArgument = 0 Then Exit Sub
    Dim pz As ZString Ptr Ptr = CPtr(ZString Ptr Ptr, pzArgument)
    Dim zCopy As Any Ptr = sqlite3DbStrDup(db, zNew)
    sqlite3DbFree(db, pz[0])
    pz[0] = CPtr(ZString Ptr, zCopy)
End Sub

/' ------------------------------------------------------------------------- '/
/' Per-connection allocation status '/
/' ------------------------------------------------------------------------- '/

Function sqlite3DbMallocFailed CDecl Alias "sqlite3DbMallocFailed" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT Export

    If db = 0 Then Return 0
    Return IIf(db->mallocFailed <> 0, 1, 0)
End Function

Function sqlite3OomFault CDecl Alias "sqlite3OomFault" ( _
    ByVal db As sqlite3 Ptr _
) As Any Ptr Export

    If db = 0 Then Return 0
    If db->mallocFailed = 0 AndAlso db->bBenignMalloc = 0 Then
        db->mallocFailed = 1
        If db->nVdbeExec > 0 Then db->isInterrupted = 1
        db->lookaside.bDisable += 1
        db->lookaside.sz = 0

        Dim pParse As SqliteParseContext Ptr = _
            CPtr(SqliteParseContext Ptr, db->pParse)
        If pParse <> 0 Then
            sqlite3ErrorToParser(db, SQLITE_NOMEM)
            Dim pOuterParse As SqliteParseContext Ptr = pParse->pOuterParse
            While pOuterParse <> 0
                If pOuterParse->nErr < &H7FFFFFFF Then pOuterParse->nErr += 1
                pOuterParse->rc = SQLITE_NOMEM
                pOuterParse = pOuterParse->pOuterParse
            Wend
        End If
    End If
    Return 0
End Function

Sub sqlite3OomClear CDecl Alias "sqlite3OomClear" ( _
    ByVal db As sqlite3 Ptr _
) Export
    If db = 0 OrElse db->mallocFailed = 0 OrElse db->nVdbeExec <> 0 Then Return
    db->mallocFailed = 0
End Sub

Private Function apiHandleError CDecl ( _
    ByVal db As sqlite3 Ptr, _
    ByVal resultCode As SQLITE_C_INT _
) As SQLITE_C_INT
    If db = 0 Then Return SQLITE_MISUSE
    If db->mallocFailed <> 0 OrElse resultCode = SQLITE_IOERR_NOMEM Then
        sqlite3OomClear(db)
        sqlite3Error(db, SQLITE_NOMEM)
        Return SQLITE_NOMEM
    End If
    Return resultCode And db->errMask
End Function

Function sqlite3ApiExit CDecl Alias "sqlite3ApiExit" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal resultCode As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If db = 0 Then Return SQLITE_MISUSE
    If db->mallocFailed <> 0 OrElse resultCode <> SQLITE_OK Then _
        Return apiHandleError(db, resultCode)
    Return SQLITE_OK
End Function

Sub sqlite3DbClearMallocFailed CDecl Alias "sqlite3DbClearMallocFailed" ( _
    ByVal db As sqlite3 Ptr _
) Export
    If db <> 0 Then db->mallocFailed = 0
End Sub

Sub sqlite3DbSetBenignMalloc CDecl Alias "sqlite3DbSetBenignMalloc" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal benign As SQLITE_C_INT _
) Export
    If db <> 0 Then db->bBenignMalloc = IIf(benign <> 0, 1, 0)
End Sub

/' end of sqlite3_db_memory.bas '/
