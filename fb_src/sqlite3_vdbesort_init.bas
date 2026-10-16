/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbesort_init.bas

    Purpose:

        Allocate and initialize the variable-sized VDBE sorter object.

    Responsibilities:

        - Size the sorter and trailing KeyInfo collation array.
        - Initialize worker tasks, page limits, and sorter type shortcuts.
        - Respect global PMA-size and small-allocation configuration.

    This file intentionally does NOT contain:

        - PMA I/O, merge scheduling, or sorter cursor advancement.
        - Runtime validation of sorted query results.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_vdbe_cursor.bi"
#include once "sqlite3_vdbesort_types.bi"
#include once "sqlite3_btree.bi"

Declare Function sqlite3Malloc CDecl Alias "sqlite3Malloc" ( _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Function sqlite3TempInMemory CDecl Alias "sqlite3TempInMemory" ( _
    ByVal db As Const Any Ptr _
) As SQLITE_C_INT

Declare Function c2fb_crt_memcpy CDecl Alias "memcpy" ( _
    ByVal destination As Any Ptr, _
    ByVal source As Const Any Ptr, _
    ByVal byteCount As SQLITE_SIZE_T _
) As Any Ptr

Function sqlite3VdbeSorterInit CDecl Alias "sqlite3VdbeSorterInit" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal nField As SQLITE_C_INT, _
    ByVal pCursor As SqliteVdbeCursor Ptr _
) As SQLITE_C_INT
    Dim resultCode As SQLITE_C_INT = SQLITE_OK
    Dim workerCount As SQLITE_C_INT = 0
    Dim pSorter As SqliteVdbeSorterPrefix Ptr = 0
    Dim pSourceKeyInfo As sqlite3VdbeKeyInfoPrefix Ptr
    Dim pSorterKeyInfo As sqlite3VdbeKeyInfoPrefix Ptr
    Dim keyInfoPrefixBytes As sqlite3_uint64
    Dim keyInfoArrayBytes As sqlite3_uint64
    Dim keyInfoBytes As sqlite3_uint64
    Dim sorterPrefixBytes As sqlite3_uint64
    Dim sorterTaskBytes As sqlite3_uint64
    Dim sorterBytes As sqlite3_uint64
    Dim taskCount As SQLITE_C_INT

    ASSERT(db <> 0)
    ASSERT(pCursor <> 0)
    ASSERT(pCursor->pKeyInfo <> 0)
    ASSERT((pCursor->cursorFlags And VDBE_CURSOR_EPHEMERAL) = 0)
    ASSERT(pCursor->eCurType = CURTYPE_SORTER)

#if SQLITE_MAX_WORKER_THREADS > 0
    If sqlite3TempInMemory(db) = 0 AndAlso _
       sqlite3ConfigCoreMutexEnabled() <> 0 Then
        workerCount = db->aLimit(SQLITE_LIMIT_WORKER_THREADS)
    End If
#if SQLITE_MAX_WORKER_THREADS >= 16
    If workerCount >= SQLITE_VDBESORT_MAX_MERGE_COUNT Then _
        workerCount = SQLITE_VDBESORT_MAX_MERGE_COUNT - 1
#endif
#endif

    If workerCount < 0 Then workerCount = 0
    If workerCount > SQLITE_MAX_WORKER_THREADS Then _
        workerCount = SQLITE_MAX_WORKER_THREADS
    taskCount = workerCount + 1

    pSourceKeyInfo = CPtr(sqlite3VdbeKeyInfoPrefix Ptr, pCursor->pKeyInfo)
    keyInfoPrefixBytes = SizeOf(sqlite3VdbeKeyInfoPrefix) - _
        SizeOf(sqlite3CollSeq Ptr)
    keyInfoArrayBytes = Cast(sqlite3_uint64, pSourceKeyInfo->nAllField) * _
        SizeOf(sqlite3CollSeq Ptr)
    keyInfoBytes = keyInfoPrefixBytes + keyInfoArrayBytes

    sorterPrefixBytes = SizeOf(SqliteVdbeSorterPrefix) - _
        SizeOf(SqliteSortSubtaskPrefix)
    sorterTaskBytes = Cast(sqlite3_uint64, taskCount) * _
        SizeOf(SqliteSortSubtaskPrefix)
    sorterBytes = sorterPrefixBytes + sorterTaskBytes

    If keyInfoBytes > &H7FFFFFFFULL OrElse _
       sorterBytes > &H7FFFFFFFFFFFFFFFULL - keyInfoBytes Then _
        Return SQLITE_TOOBIG

    pSorter = CPtr(SqliteVdbeSorterPrefix Ptr, _
        sqlite3DbMallocZero(db, sorterBytes + keyInfoBytes))
    pCursor->uc.pSorter = pSorter
    If pSorter = 0 Then Return SQLITE_NOMEM

    pSorterKeyInfo = CPtr(sqlite3VdbeKeyInfoPrefix Ptr, _
        CPtr(UByte Ptr, pSorter) + sorterBytes)
    pSorter->pKeyInfo = pSorterKeyInfo
    c2fb_crt_memcpy(pSorterKeyInfo, pSourceKeyInfo, _
                    Cast(SQLITE_SIZE_T, keyInfoBytes))
    pSorterKeyInfo->db = 0

    If nField <> 0 AndAlso workerCount = 0 Then
        pSorterKeyInfo->nKeyField = Cast(UShort, nField)
        ASSERT(nField <= pSourceKeyInfo->nAllField)
    End If
    ASSERT(pSorterKeyInfo->aSortFlags = pSourceKeyInfo->aSortFlags)

    Dim pMainBtree As Btree Ptr = CPtr(Btree Ptr, db->aDb(0).pBt)
    ASSERT(pMainBtree <> 0)
    sqlite3BtreeEnter(pMainBtree)
    Dim pageSize As SQLITE_C_INT = sqlite3BtreeGetPageSize(pMainBtree)
    sqlite3BtreeLeave(pMainBtree)
    pSorter->pgsz = pageSize

    pSorter->nTask = Cast(u8, taskCount)
    pSorter->iPrev = Cast(u8, workerCount - 1)
    pSorter->bUseThreads = Cast(u8, IIf(taskCount > 1, 1, 0))
    pSorter->db = db

    For taskIndex As SQLITE_C_INT = 0 To taskCount - 1
        pSorter->aTask(taskIndex).pSorter = pSorter
    Next

    If sqlite3TempInMemory(db) = 0 Then
        Dim pmaSizeBytes As sqlite3_uint64 = _
            (Cast(sqlite3_uint64, sqlite3ConfigPmaSizeValue()) * _
             Cast(sqlite3_uint64, pageSize)) And &HFFFFFFFFULL
        pSorter->mnPmaSize = Cast(SQLITE_C_INT, pmaSizeBytes)

        Dim pMainSchema As SqliteSchema Ptr = db->aDb(0).pSchema
        Dim cacheSize As sqlite3_int64 = pMainSchema->cache_size
        If cacheSize < 0 Then
            cacheSize *= -1024
        Else
            cacheSize *= pageSize
        End If
        If cacheSize > SQLITE_VDBESORT_MAX_PMASZ Then _
            cacheSize = SQLITE_VDBESORT_MAX_PMASZ

        pSorter->mxPmaSize = Cast(SQLITE_C_INT, cacheSize)
        If pSorter->mxPmaSize < pSorter->mnPmaSize Then _
            pSorter->mxPmaSize = pSorter->mnPmaSize

        If sqlite3ConfigSmallMallocEnabled() = 0 Then
            pSorter->nMemory = pageSize
            pSorter->list.aMemory = CPtr(UByte Ptr, sqlite3Malloc(pageSize))
            If pSorter->list.aMemory = 0 Then resultCode = SQLITE_NOMEM
        End If
    End If

    If pSorterKeyInfo->nAllField < 13 AndAlso _
       (pSorterKeyInfo->aColl(0) = 0 OrElse _
        pSorterKeyInfo->aColl(0) = db->pDfltColl) AndAlso _
       (pSorterKeyInfo->aSortFlags[0] And KEYINFO_ORDER_BIGNULL) = 0 Then
        pSorter->typeMask = SQLITE_VDBESORT_TYPE_INTEGER Or _
                            SQLITE_VDBESORT_TYPE_TEXT Or _
                            SQLITE_VDBESORT_TYPE_REAL
    End If

    Return resultCode
End Function

/' end of sqlite3_vdbesort_init.bas '/
