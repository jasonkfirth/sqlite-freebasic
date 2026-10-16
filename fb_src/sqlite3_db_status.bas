/'
    Project: SQLite FreeBASIC port

    File: sqlite3_db_status.bas

    Purpose:

        Report connection and page-cache status through the public API.

    Responsibilities:

        - Track lookaside use, high-water, and miss counters per connection.
        - Aggregate cache hit, miss, write, spill, and memory values across databases.
        - Report deferred foreign-key state and temporary-buffer spill bytes.
        - Estimate schema-owned allocation sizes without freeing schema objects.
        - Preserve the 32-bit and 64-bit sqlite3_db_status interfaces.

    This file intentionally does NOT contain:

        - General schema construction or destruction outside status measurement.
'/

#lang "fb"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_btree.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_hash_types.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_memory_methods.bi"

Declare Function sqlite3_msize CDecl Alias "sqlite3_msize" ( _
    ByVal p As Any Ptr _
) As sqlite3_uint64
Declare Sub sqlite3DeleteTable CDecl Alias "sqlite3DeleteTable" ( _
    ByVal db As Any Ptr, _
    ByVal pTable As Any Ptr _
)
Declare Sub sqlite3DeleteTrigger CDecl Alias "sqlite3DeleteTrigger" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pTrigger As SqliteTrigger Ptr _
)

Private Const SQLITE_DB_STATUS_CONNECTION_OPEN As u8 = 1
Private Const SQLITE_DB_STATUS_CONNECTION_FAILED As u8 = 2
Private Const SQLITE_DB_STATUS_MAX_BYTES As SQLITE_C_INT = &H7FFFFFFF

Private Sub sqlite3DbStatusAddBytes( _
    ByRef currentValue As SQLITE_C_INT, _
    ByVal byteCount As sqlite3_uint64 _
)
    If currentValue < 0 OrElse _
       byteCount >= CULngInt(SQLITE_DB_STATUS_MAX_BYTES - currentValue) Then
        currentValue = SQLITE_DB_STATUS_MAX_BYTES
    Else
        currentValue += CLngInt(byteCount)
    End If
End Sub

Private Function sqlite3DbStatusConnectionIsValid(ByVal db As sqlite3 Ptr) As SQLITE_C_INT
    If db = 0 OrElse db->isZombie <> 0 Then Return 0
    If db->isOpen <> SQLITE_DB_STATUS_CONNECTION_OPEN AndAlso _
       db->isOpen <> SQLITE_DB_STATUS_CONNECTION_FAILED Then Return 0
    Return 1
End Function

Private Function sqlite3DbStatusCacheValue( _
    ByVal db As sqlite3 Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal resetFlag As SQLITE_C_INT _
) As sqlite3_int64
    If db = 0 OrElse db->nDb <= 0 Then Return 0
    Dim cacheValue As sqlite3_uint64 = 0
    Dim pagerOperation As SQLITE_C_INT = operation
    If operation = SQLITE_DBSTATUS_CACHE_SPILL Then _
        pagerOperation = SQLITE_DBSTATUS_CACHE_WRITE + 1

    sqlite3BtreeEnterAll(db)
    For databaseIndex As SQLITE_C_INT = 0 To db->nDb - 1
        Dim pBtree As Btree Ptr = _
            CPtr(Btree Ptr, db->aDb(databaseIndex).pBt)
        If pBtree = 0 OrElse pBtree->pBt = 0 Then Continue For
        Dim pBt As BtShared Ptr = pBtree->pBt
        If pBt->pPager = 0 Then Continue For

        If operation = SQLITE_DBSTATUS_CACHE_USED OrElse _
           operation = SQLITE_DBSTATUS_CACHE_USED_SHARED Then
            Dim byteCount As sqlite3_uint64 = _
                CULngInt(sqlite3PagerMemUsed(pBt->pPager))
            If operation = SQLITE_DBSTATUS_CACHE_USED_SHARED Then
                Dim connectionCount As SQLITE_C_INT = _
                    sqlite3BtreeConnectionCount(pBtree)
                If connectionCount > 0 Then _
                    byteCount \= CULngInt(connectionCount)
            End If
            cacheValue += byteCount
        Else
            sqlite3PagerCacheStat( _
                pBt->pPager, pagerOperation, resetFlag, @cacheValue)
        End If
    Next
    sqlite3BtreeLeaveAll(db)
    Return CLngInt(cacheValue)
End Function

Private Function countLookasideSlots CDecl Alias "countLookasideSlots" ( _
    ByVal pSlot As SqliteLookasideSlot Ptr _
) As u32
    Dim slotCount As u32 = 0
    While pSlot <> 0
        pSlot = pSlot->pNext
        slotCount += 1
    Wend
    Return slotCount
End Function

Function sqlite3LookasideUsed CDecl Alias "sqlite3LookasideUsed" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pHighwater As SQLITE_C_INT Ptr _
) As SQLITE_C_INT Export
    If db = 0 Then
        If pHighwater <> 0 Then pHighwater[0] = 0
        Return 0
    End If
    Dim initialCount As u32 = countLookasideSlots(db->lookaside.pInit)
    Dim freeCount As u32 = countLookasideSlots(db->lookaside.pFree)
#ifndef SQLITE_OMIT_TWOSIZE_LOOKASIDE
    Dim smallInitialCount As u32 = _
        countLookasideSlots(db->lookaside.pSmallInit)
    Dim smallFreeCount As u32 = _
        countLookasideSlots(db->lookaside.pSmallFree)
    If initialCount > db->lookaside.nSlot OrElse _
       smallInitialCount > db->lookaside.nSlot - initialCount Then
        If pHighwater <> 0 Then pHighwater[0] = 0
        Return 0
    End If
    initialCount += smallInitialCount
    If freeCount > db->lookaside.nSlot - initialCount OrElse _
       smallFreeCount > db->lookaside.nSlot - initialCount - freeCount Then
        If pHighwater <> 0 Then pHighwater[0] = 0
        Return 0
    End If
    freeCount += smallFreeCount
#endif
    If initialCount > db->lookaside.nSlot OrElse _
       freeCount > db->lookaside.nSlot - initialCount Then
        If pHighwater <> 0 Then pHighwater[0] = 0
        Return 0
    End If
    If pHighwater <> 0 Then _
        pHighwater[0] = CInt(db->lookaside.nSlot - initialCount)
    Return CInt(db->lookaside.nSlot - initialCount - freeCount)
End Function

Function sqlite3_db_status64 CDecl Alias "sqlite3_db_status64" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal pCurrent As sqlite3_int64 Ptr, _
    ByVal pHighwater As sqlite3_int64 Ptr, _
    ByVal resetFlag As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If sqlite3DbStatusConnectionIsValid(db) = 0 OrElse _
       pCurrent = 0 OrElse pHighwater = 0 Then Return SQLITE_MISUSE

    sqlite3DbEnter(db)
    Dim currentValue As sqlite3_int64 = 0
    Dim highwaterValue As sqlite3_int64 = 0
    Dim rc As SQLITE_C_INT = SQLITE_OK

    Select Case operation
    Case SQLITE_DBSTATUS_LOOKASIDE_USED
        Dim lookasideHighwater As SQLITE_C_INT = 0
        currentValue = sqlite3LookasideUsed(db, @lookasideHighwater)
        highwaterValue = lookasideHighwater
        If resetFlag <> 0 Then
            If db->lookaside.pFree <> 0 Then
                Dim pTail As SqliteLookasideSlot Ptr = db->lookaside.pFree
                While pTail->pNext <> 0
                    pTail = pTail->pNext
                Wend
                pTail->pNext = db->lookaside.pInit
                db->lookaside.pInit = db->lookaside.pFree
                db->lookaside.pFree = 0
            End If
#ifndef SQLITE_OMIT_TWOSIZE_LOOKASIDE
            If db->lookaside.pSmallFree <> 0 Then
                Dim pSmallTail As SqliteLookasideSlot Ptr = _
                    db->lookaside.pSmallFree
                While pSmallTail->pNext <> 0
                    pSmallTail = pSmallTail->pNext
                Wend
                pSmallTail->pNext = db->lookaside.pSmallInit
                db->lookaside.pSmallInit = db->lookaside.pSmallFree
                db->lookaside.pSmallFree = 0
            End If
#endif
            Dim initialSlotCount As u32 = _
                countLookasideSlots(db->lookaside.pInit)
#ifndef SQLITE_OMIT_TWOSIZE_LOOKASIDE
            initialSlotCount += countLookasideSlots(db->lookaside.pSmallInit)
#endif
            If initialSlotCount <= db->lookaside.nSlot Then
                db->lookasideInitCount = initialSlotCount
                db->lookasideFreeCount = 0
                db->lookasideOutCount = _
                    db->lookaside.nSlot - initialSlotCount
            End If
        End If

    Case SQLITE_DBSTATUS_LOOKASIDE_HIT To SQLITE_DBSTATUS_LOOKASIDE_MISS_FULL
        Dim statIndex As Long = operation - SQLITE_DBSTATUS_LOOKASIDE_HIT
        currentValue = 0
        highwaterValue = db->lookaside.anStat(statIndex)
        If resetFlag <> 0 Then db->lookaside.anStat(statIndex) = 0

    Case SQLITE_DBSTATUS_CACHE_USED, SQLITE_DBSTATUS_CACHE_USED_SHARED, _
         SQLITE_DBSTATUS_CACHE_HIT, SQLITE_DBSTATUS_CACHE_MISS, _
         SQLITE_DBSTATUS_CACHE_WRITE, SQLITE_DBSTATUS_CACHE_SPILL
        currentValue = sqlite3DbStatusCacheValue(db, operation, resetFlag)

    Case SQLITE_DBSTATUS_STMT_USED
        Dim bytesFreed As SQLITE_C_INT = 0
        db->pnBytesFreed = @bytesFreed
        ' Match SQLite's sizing walk: do not serve lookaside allocations while
        ' VDBE deletion routines inspect statement-owned objects.
        db->lookaside.pEnd = db->lookaside.pStart
        Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, db->pVdbe)
        While pVdbe <> 0
            Dim pNext As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pVdbe->pVNext)
            sqlite3VdbeDelete(pVdbe)
            pVdbe = pNext
        Wend
        db->lookaside.pEnd = db->lookaside.pTrueEnd
        db->pnBytesFreed = 0
        currentValue = bytesFreed
        highwaterValue = 0

    Case SQLITE_DBSTATUS_DEFERRED_FKS
        currentValue = IIf( _
            db->nDeferredImmCons > 0 OrElse db->nDeferredCons > 0, 1, 0)
        highwaterValue = 0

    Case SQLITE_DBSTATUS_TEMPBUF_SPILL
        Dim spilledBytes As sqlite3_uint64 = db->nSpill
        If db->nDb > 1 AndAlso db->aDb(1).pBt <> 0 Then
            Dim pTempBtree As Btree Ptr = _
                CPtr(Btree Ptr, db->aDb(1).pBt)
            If pTempBtree->pBt <> 0 AndAlso pTempBtree->pBt->pPager <> 0 Then
                Dim tempPagesWritten As sqlite3_uint64 = 0
                sqlite3PagerCacheStat( _
                    pTempBtree->pBt->pPager, SQLITE_DBSTATUS_CACHE_WRITE, _
                    resetFlag, @tempPagesWritten)
                spilledBytes += tempPagesWritten * _
                    CULngInt(sqlite3BtreeGetPageSize(pTempBtree))
            End If
        End If
        If resetFlag <> 0 Then db->nSpill = 0
        currentValue = CLngInt(spilledBytes)
        highwaterValue = 0

    Case SQLITE_DBSTATUS_SCHEMA_USED
        If db->nDb < 0 OrElse db->nDb > SQLITE_MAX_ATTACHED + 2 Then
            rc = SQLITE_CORRUPT
        Else
            Dim bytesFreed As SQLITE_C_INT = 0
            Dim memoryMethods As SqliteMemMethods
            sqlite3MemConfigGetMethods(@memoryMethods)
            If memoryMethods.xRoundup = 0 Then
                rc = SQLITE_MISUSE
            Else
                sqlite3BtreeEnterAll(db)
                db->pnBytesFreed = @bytesFreed
                ' Redirect lookaside allocation to an empty range while delete
                ' routines walk objects. Their frees are counted, not applied.
                db->lookaside.pEnd = db->lookaside.pStart

                For databaseIndex As SQLITE_C_INT = 0 To db->nDb - 1
                    Dim pSchema As SqliteSchema Ptr = db->aDb(databaseIndex).pSchema
                    If pSchema = 0 Then Continue For

                    Dim elementCount As sqlite3_uint64 = _
                        CULngInt(pSchema->tblHash.count) + _
                        CULngInt(pSchema->trigHash.count) + _
                        CULngInt(pSchema->idxHash.count) + _
                        CULngInt(pSchema->fkeyHash.count)
                    Dim elementSize As SQLITE_C_INT = _
                        memoryMethods.xRoundup(SizeOf(HashElem))
                    If elementSize > 0 Then
                        If elementCount > _
                           CULngInt(SQLITE_DB_STATUS_MAX_BYTES) \ _
                               CULngInt(elementSize) Then
                            sqlite3DbStatusAddBytes( _
                                bytesFreed, CULngInt(SQLITE_DB_STATUS_MAX_BYTES))
                        Else
                            sqlite3DbStatusAddBytes( _
                                bytesFreed, elementCount * CULngInt(elementSize))
                        End If
                    End If

                    sqlite3DbStatusAddBytes( _
                        bytesFreed, sqlite3_msize(pSchema->tblHash.ht))
                    sqlite3DbStatusAddBytes( _
                        bytesFreed, sqlite3_msize(pSchema->trigHash.ht))
                    sqlite3DbStatusAddBytes( _
                        bytesFreed, sqlite3_msize(pSchema->idxHash.ht))
                    sqlite3DbStatusAddBytes( _
                        bytesFreed, sqlite3_msize(pSchema->fkeyHash.ht))

                    Dim pElement As HashElem Ptr = pSchema->trigHash.first
                    While pElement <> 0
                        Dim pNext As HashElem Ptr = pElement->next
                        sqlite3DeleteTrigger( _
                            db, CPtr(SqliteTrigger Ptr, pElement->data))
                        pElement = pNext
                    Wend

                    pElement = pSchema->tblHash.first
                    While pElement <> 0
                        Dim pNext As HashElem Ptr = pElement->next
                        sqlite3DeleteTable(db, pElement->data)
                        pElement = pNext
                    Wend
                Next

                db->pnBytesFreed = 0
                db->lookaside.pEnd = db->lookaside.pTrueEnd
                sqlite3BtreeLeaveAll(db)
                currentValue = bytesFreed
                highwaterValue = 0
            End If
        End If

    Case Else
        rc = SQLITE_ERROR
    End Select

    If rc = SQLITE_OK Then
        pCurrent[0] = currentValue
        pHighwater[0] = highwaterValue
    End If
    sqlite3DbLeave(db)
    Return rc
End Function

Function sqlite3_db_status CDecl Alias "sqlite3_db_status" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal pCurrent As SQLITE_C_INT Ptr, _
    ByVal pHighwater As SQLITE_C_INT Ptr, _
    ByVal resetFlag As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pCurrent = 0 OrElse pHighwater = 0 Then Return SQLITE_MISUSE
    Dim currentValue As sqlite3_int64 = 0
    Dim highwaterValue As sqlite3_int64 = 0
    Dim rc As SQLITE_C_INT = sqlite3_db_status64( _
        db, operation, @currentValue, @highwaterValue, resetFlag)
    If rc = SQLITE_OK Then
        pCurrent[0] = CInt(currentValue And &H7FFFFFFF)
        pHighwater[0] = CInt(highwaterValue And &H7FFFFFFF)
    End If
    Return rc
End Function

/' end of sqlite3_db_status.bas '/
