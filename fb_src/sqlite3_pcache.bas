/'
    Project: SQLite FreeBASIC port

    File: sqlite3_pcache.bas

    Purpose:

        Port the page ownership and dirty-page layer from src/pcache.c.

    Responsibilities:

        - Track page references and the dirty-page LRU list.
        - Dispatch pager-facing operations through sqlite3_pcache_methods2.
        - Install the built-in PCache1 method table when no custom table is set.
        - Apply cache sizing, spill callbacks, truncation, and page rekeying.
        - Check cache-page dirty-list membership invariants.

    This file intentionally does NOT contain:

        - Pager I/O, rollback journaling, or WAL behavior.
        - PCache1's page allocator, hash table, LRU, or global state.
        - The upstream debug trace block disabled by SQLITE_DEBUG && 0.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_pcache.bi"
#include once "sqlite3_pcache1_types.bi"


Private Const PCACHE_DIRTYLIST_REMOVE As u8 = 1
Private Const PCACHE_DIRTYLIST_ADD As u8 = 2
Private Const PCACHE_DIRTYLIST_FRONT As u8 = 3
Private Const PCACHE_SORT_BUCKETS As Long = 32
Private Const PCACHE_MAX_PAGE_SIZE As Long = 65536
Private Const PCACHE_MIN_PAGE_SIZE As Long = 512
Private Const PCACHE_MAX_EXTRA_SIZE As Long = 300

/' ------------------------------------------------------------------------- '/
/' Page sizing helpers '/
/' ------------------------------------------------------------------------- '/

Private Function pcacheRound8(ByVal value As sqlite3_uint64) As sqlite3_uint64
    Return (value + 7) And Not CULngInt(7)
End Function

Private Function numberOfCachePages(ByVal pCache As PCache Ptr) As u32
    If pCache = 0 OrElse pCache->szPage <= 0 Then Return 0
    If pCache->szCache >= 0 Then
        Return CULng(pCache->szCache)
    End If

    Dim nBytes As i64 = -1024 * CLngInt(pCache->szCache)
    Dim nPerPage As i64 = CLngInt(pCache->szPage) + pCache->szExtra
    If nPerPage <= 0 Then Return 0
    Dim nPages As i64 = nBytes \ nPerPage
    If nPages > 1000000000 Then nPages = 1000000000
    If nPages < 0 Then Return 0
    Return CULng(nPages)
End Function

/' ------------------------------------------------------------------------- '/
/' Dirty-page list and cache lifecycle '/
/' ------------------------------------------------------------------------- '/

Private Sub pcacheManageDirtyList(ByVal pPage As PgHdr Ptr, ByVal addRemove As u8)
    If pPage = 0 OrElse pPage->pCache = 0 Then Exit Sub
    Dim pCache As PCache Ptr = CPtr(PCache Ptr, pPage->pCache)

    If (addRemove And PCACHE_DIRTYLIST_REMOVE) <> 0 Then
        If pPage->pDirtyNext <> 0 Then pPage->pDirtyNext->pDirtyPrev = pPage->pDirtyPrev
        If pPage->pDirtyPrev <> 0 Then pPage->pDirtyPrev->pDirtyNext = pPage->pDirtyNext
        If pCache->pDirty = pPage Then pCache->pDirty = pPage->pDirtyNext
        If pCache->pDirtyTail = pPage Then pCache->pDirtyTail = pPage->pDirtyPrev
        If pCache->pSynced = pPage Then pCache->pSynced = pPage->pDirtyPrev
        pPage->pDirtyNext = 0
        pPage->pDirtyPrev = 0
        If pCache->pDirty = 0 AndAlso pCache->bPurgeable <> 0 Then pCache->eCreate = 2
    End If

    If (addRemove And PCACHE_DIRTYLIST_ADD) <> 0 Then
        pPage->pDirtyPrev = 0
        pPage->pDirtyNext = pCache->pDirty
        If pCache->pDirty <> 0 Then
            pCache->pDirty->pDirtyPrev = pPage
        Else
            pCache->pDirtyTail = pPage
        End If
        pCache->pDirty = pPage
        If pCache->bPurgeable <> 0 Then pCache->eCreate = 1
        If pCache->pSynced = 0 AndAlso (pPage->flags And PGHDR_NEED_SYNC) = 0 Then
            pCache->pSynced = pPage
        End If
    End If
End Sub

Private Sub pcacheGetMethods(ByRef methods As SqlitePcacheMethods2)
    sqlite3ConfigGetPcacheMethods(@methods)
End Sub

Private Sub pcacheUnpin(ByVal pPage As PgHdr Ptr)
    If pPage = 0 OrElse pPage->pCache = 0 Then Exit Sub
    Dim pCache As PCache Ptr = CPtr(PCache Ptr, pPage->pCache)
    If pCache->bPurgeable <> 0 AndAlso pCache->pCache <> 0 Then
        Dim methods As SqlitePcacheMethods2
        pcacheGetMethods(methods)
        If methods.xUnpin <> 0 Then methods.xUnpin(pCache->pCache, pPage->pPage, 0)
    End If
End Sub

Function sqlite3PcacheInitialize CDecl Alias "sqlite3PcacheInitialize" () As SQLITE_C_INT Export
    Dim methods As SqlitePcacheMethods2
    pcacheGetMethods(methods)
    If methods.xInit = 0 Then
        sqlite3PCacheSetDefault()
        pcacheGetMethods(methods)
    End If
    If methods.xInit = 0 Then Return SQLITE_ERROR
    Return methods.xInit(methods.pArg)
End Function

Sub sqlite3PcacheShutdown CDecl Alias "sqlite3PcacheShutdown" () Export
    Dim methods As SqlitePcacheMethods2
    pcacheGetMethods(methods)
    If methods.xShutdown <> 0 Then methods.xShutdown(methods.pArg)
End Sub

Sub sqlite3PCacheBufferSetup CDecl Alias "sqlite3PCacheBufferSetup" ( _
    ByVal pBuffer As Any Ptr, _
    ByVal slotSize As SQLITE_C_INT, _
    ByVal slotCount As SQLITE_C_INT _
) Export
    sqlite3Pcache1BufferSetup(pBuffer, slotSize, slotCount)
End Sub

Sub sqlite3PCacheSetDefault CDecl Alias "sqlite3PCacheSetDefault" () Export
    Dim defaultMethods As SqlitePcacheMethods2
    defaultMethods.iVersion = 1
    defaultMethods.pArg = 0
    defaultMethods.xInit = @pcache1Init
    defaultMethods.xShutdown = @pcache1Shutdown
    defaultMethods.xCreate = @pcache1Create
    defaultMethods.xCachesize = @pcache1Cachesize
    defaultMethods.xPagecount = @pcache1Pagecount
    defaultMethods.xFetch = @pcache1Fetch
    defaultMethods.xUnpin = @pcache1Unpin
    defaultMethods.xRekey = @pcache1Rekey
    defaultMethods.xTruncate = @pcache1Truncate
    defaultMethods.xDestroy = @pcache1Destroy
    defaultMethods.xShrink = @pcache1Shrink
    sqlite3ConfigSetPcacheMethods(@defaultMethods)
End Sub

Function sqlite3PcacheSize CDecl Alias "sqlite3PcacheSize" () As SQLITE_C_INT Export
    Return SizeOf(PCache)
End Function

Function sqlite3PcacheOpen CDecl Alias "sqlite3PcacheOpen" ( _
    ByVal pageSize As SQLITE_C_INT, _
    ByVal extraSize As SQLITE_C_INT, _
    ByVal purgeable As SQLITE_C_INT, _
    ByVal xStress As SqlitePcacheStressProc, _
    ByVal pStress As Any Ptr, _
    ByVal pToInit As PCache Ptr _
) As SQLITE_C_INT Export

    If pToInit = 0 OrElse pageSize < PCACHE_MIN_PAGE_SIZE OrElse _
       pageSize > PCACHE_MAX_PAGE_SIZE OrElse (pageSize And (pageSize - 1)) <> 0 OrElse _
       extraSize < 8 OrElse extraSize >= PCACHE_MAX_EXTRA_SIZE Then Return SQLITE_MISUSE

    pToInit->pDirty = 0
    pToInit->pDirtyTail = 0
    pToInit->pSynced = 0
    pToInit->nRefSum = 0
    pToInit->szCache = 100
    pToInit->szSpill = 1
    pToInit->szPage = 1
    pToInit->szExtra = extraSize
    pToInit->bPurgeable = IIf(purgeable <> 0, 1, 0)
    pToInit->eCreate = 2
    pToInit->xStress = xStress
    pToInit->pStress = pStress
    pToInit->pCache = 0

    Return sqlite3PcacheSetPageSize(pToInit, pageSize)
End Function

Function sqlite3PcacheSetPageSize CDecl Alias "sqlite3PcacheSetPageSize" ( _
    ByVal pCache As PCache Ptr, _
    ByVal pageSize As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pCache = 0 OrElse pCache->nRefSum <> 0 OrElse pCache->pDirty <> 0 Then Return SQLITE_MISUSE
    If pageSize < PCACHE_MIN_PAGE_SIZE OrElse pageSize > PCACHE_MAX_PAGE_SIZE OrElse _
       (pageSize And (pageSize - 1)) <> 0 Then Return SQLITE_MISUSE

    Dim extraSize As SQLITE_C_INT = _
        CLng(pcacheRound8(SizeOf(PgHdr))) + pCache->szExtra
    Dim methods As SqlitePcacheMethods2
    pcacheGetMethods(methods)
    If methods.xCreate = 0 OrElse methods.xCachesize = 0 OrElse _
       methods.xDestroy = 0 Then Return SQLITE_MISUSE
    Dim pNew As Any Ptr = methods.xCreate( _
        pageSize, extraSize, CInt(pCache->bPurgeable <> 0))
    If pNew = 0 Then Return SQLITE_NOMEM
    methods.xCachesize(pNew, CInt(numberOfCachePages(pCache)))

    Dim pOld As Any Ptr = pCache->pCache
    If pOld <> 0 Then methods.xDestroy(pOld)
    pCache->pCache = pNew
    pCache->szPage = pageSize
    Return SQLITE_OK
End Function

Function sqlite3PcacheFetch CDecl Alias "sqlite3PcacheFetch" ( _
    ByVal pCache As PCache Ptr, _
    ByVal pageNumber As u32, _
    ByVal createFlag As SQLITE_C_INT _
) As sqlite3_pcache_page Ptr Export

    If pCache = 0 OrElse pCache->pCache = 0 OrElse pageNumber = 0 Then Return 0
    If createFlag <> 0 AndAlso createFlag <> 3 Then Return 0
    Dim eCreate As SQLITE_C_INT = createFlag And pCache->eCreate
    If eCreate < 0 OrElse eCreate > 2 Then Return 0
    Dim methods As SqlitePcacheMethods2
    pcacheGetMethods(methods)
    If methods.xFetch = 0 Then Return 0
    Return methods.xFetch(pCache->pCache, pageNumber, eCreate)
End Function

Function sqlite3PcacheFetchStress CDecl Alias "sqlite3PcacheFetchStress" ( _
    ByVal pCache As PCache Ptr, _
    ByVal pageNumber As u32, _
    ByVal ppPage As sqlite3_pcache_page Ptr Ptr _
) As SQLITE_C_INT Export

    If pCache = 0 OrElse pCache->pCache = 0 OrElse ppPage = 0 Then Return SQLITE_MISUSE
    ppPage[0] = 0
    If pCache->eCreate = 2 Then Return 0

    Dim methods As SqlitePcacheMethods2
    pcacheGetMethods(methods)
    If methods.xPagecount = 0 OrElse methods.xFetch = 0 Then Return SQLITE_MISUSE
    If methods.xPagecount(pCache->pCache) > pCache->szSpill Then
        Dim pPage As PgHdr Ptr = pCache->pSynced
        While pPage <> 0 AndAlso (pPage->nRef <> 0 OrElse (pPage->flags And PGHDR_NEED_SYNC) <> 0)
            pPage = pPage->pDirtyPrev
        Wend
        pCache->pSynced = pPage
        If pPage = 0 Then
            pPage = pCache->pDirtyTail
            While pPage <> 0 AndAlso pPage->nRef <> 0
                pPage = pPage->pDirtyPrev
            Wend
        End If

        If pPage <> 0 AndAlso pCache->xStress <> 0 Then
            Dim rc As SQLITE_C_INT = pCache->xStress(pCache->pStress, pPage)
            If rc <> SQLITE_OK AndAlso rc <> SQLITE_BUSY Then Return rc
        End If
    End If

    ppPage[0] = methods.xFetch(pCache->pCache, pageNumber, 2)
    If ppPage[0] = 0 Then Return SQLITE_NOMEM
    Return SQLITE_OK
End Function

Private Function pcacheFetchFinishWithInit( _
    ByVal pCache As PCache Ptr, _
    ByVal pageNumber As u32, _
    ByVal pPage As sqlite3_pcache_page Ptr _
) As PgHdr Ptr

    If pPage = 0 OrElse pPage->pExtra = 0 Then Return 0
    Dim pHdr As PgHdr Ptr = CPtr(PgHdr Ptr, pPage->pExtra)
    If pHdr->pPage <> 0 Then Return 0

    pHdr->pPage = pPage
    pHdr->pData = pPage->pBuf
    pHdr->pExtra = CPtr(UByte Ptr, pHdr) + SizeOf(PgHdr)
    pHdr->pCache = pCache
    pHdr->pDirty = 0
    pHdr->pPager = 0
#ifdef SQLITE_CHECK_PAGES
    pHdr->pageHash = 0
#endif
    pHdr->pgno = pageNumber
    pHdr->flags = PGHDR_CLEAN
    pHdr->nRef = 0
    pHdr->pDirtyNext = 0
    pHdr->pDirtyPrev = 0

    Dim pExtraBytes As UByte Ptr = CPtr(UByte Ptr, pHdr->pExtra)
    For i As Long = 0 To 7
        pExtraBytes[i] = 0
    Next
    Return sqlite3PcacheFetchFinish(pCache, pageNumber, pPage)
End Function

Function sqlite3PcacheFetchFinish CDecl Alias "sqlite3PcacheFetchFinish" ( _
    ByVal pCache As PCache Ptr, _
    ByVal pageNumber As u32, _
    ByVal pPage As sqlite3_pcache_page Ptr _
) As PgHdr Ptr Export

    If pCache = 0 OrElse pPage = 0 OrElse pPage->pExtra = 0 Then Return 0
    Dim pHdr As PgHdr Ptr = CPtr(PgHdr Ptr, pPage->pExtra)
    If pHdr->pPage = 0 Then Return pcacheFetchFinishWithInit(pCache, pageNumber, pPage)
    If pHdr->pPage <> pPage OrElse pHdr->pCache <> pCache Then Return 0
    pCache->nRefSum += 1
    pHdr->nRef += 1
    Return pHdr
End Function

Sub sqlite3PcacheRelease CDecl Alias "sqlite3PcacheRelease" (ByVal pPage As PgHdr Ptr) Export
    If pPage = 0 OrElse pPage->pCache = 0 OrElse pPage->nRef <= 0 Then Exit Sub
    Dim pCache As PCache Ptr = CPtr(PCache Ptr, pPage->pCache)
    If pCache->nRefSum > 0 Then pCache->nRefSum -= 1
    pPage->nRef -= 1
    If pPage->nRef = 0 Then
        If (pPage->flags And PGHDR_CLEAN) <> 0 Then
            pcacheUnpin(pPage)
        Else
            pcacheManageDirtyList(pPage, PCACHE_DIRTYLIST_FRONT)
        End If
    End If
End Sub

Sub sqlite3PcacheRef CDecl Alias "sqlite3PcacheRef" (ByVal pPage As PgHdr Ptr) Export
    If pPage = 0 OrElse pPage->pCache = 0 OrElse pPage->nRef <= 0 Then Exit Sub
    Dim pCache As PCache Ptr = CPtr(PCache Ptr, pPage->pCache)
    pPage->nRef += 1
    pCache->nRefSum += 1
End Sub

Sub sqlite3PcacheDrop CDecl Alias "sqlite3PcacheDrop" (ByVal pPage As PgHdr Ptr) Export
    If pPage = 0 OrElse pPage->pCache = 0 OrElse pPage->pPage = 0 OrElse pPage->nRef <> 1 Then Exit Sub
    Dim pCache As PCache Ptr = CPtr(PCache Ptr, pPage->pCache)
    If (pPage->flags And PGHDR_DIRTY) <> 0 Then
        pcacheManageDirtyList(pPage, PCACHE_DIRTYLIST_REMOVE)
    End If
    If pCache->nRefSum > 0 Then pCache->nRefSum -= 1
    Dim methods As SqlitePcacheMethods2
    pcacheGetMethods(methods)
    If methods.xUnpin <> 0 Then methods.xUnpin(pCache->pCache, pPage->pPage, 1)
End Sub

Sub sqlite3PcacheMakeDirty CDecl Alias "sqlite3PcacheMakeDirty" (ByVal pPage As PgHdr Ptr) Export
    If pPage = 0 OrElse pPage->nRef <= 0 Then Exit Sub
    If (pPage->flags And (PGHDR_CLEAN Or PGHDR_DONT_WRITE)) <> 0 Then
        pPage->flags = pPage->flags And Not PGHDR_DONT_WRITE
        If (pPage->flags And PGHDR_CLEAN) <> 0 Then
            pPage->flags = (pPage->flags Or PGHDR_DIRTY) And Not PGHDR_CLEAN
            pcacheManageDirtyList(pPage, PCACHE_DIRTYLIST_ADD)
        End If
    End If
End Sub

Sub sqlite3PcacheMakeClean CDecl Alias "sqlite3PcacheMakeClean" (ByVal pPage As PgHdr Ptr) Export
    If pPage = 0 OrElse (pPage->flags And PGHDR_DIRTY) = 0 Then Exit Sub
    pcacheManageDirtyList(pPage, PCACHE_DIRTYLIST_REMOVE)
    pPage->flags = pPage->flags And Not (PGHDR_DIRTY Or PGHDR_NEED_SYNC Or PGHDR_WRITEABLE)
    pPage->flags = pPage->flags Or PGHDR_CLEAN
    If pPage->nRef = 0 Then pcacheUnpin(pPage)
End Sub

Sub sqlite3PcacheCleanAll CDecl Alias "sqlite3PcacheCleanAll" (ByVal pCache As PCache Ptr) Export
    If pCache = 0 Then Exit Sub
    While pCache->pDirty <> 0
        sqlite3PcacheMakeClean(pCache->pDirty)
    Wend
End Sub

Sub sqlite3PcacheClearWritable CDecl Alias "sqlite3PcacheClearWritable" (ByVal pCache As PCache Ptr) Export
    If pCache = 0 Then Exit Sub
    Dim pPage As PgHdr Ptr = pCache->pDirty
    While pPage <> 0
        pPage->flags = pPage->flags And Not (PGHDR_NEED_SYNC Or PGHDR_WRITEABLE)
        pPage = pPage->pDirtyNext
    Wend
    pCache->pSynced = pCache->pDirtyTail
End Sub

Sub sqlite3PcacheClearSyncFlags CDecl Alias "sqlite3PcacheClearSyncFlags" (ByVal pCache As PCache Ptr) Export
    If pCache = 0 Then Exit Sub
    Dim pPage As PgHdr Ptr = pCache->pDirty
    While pPage <> 0
        pPage->flags = pPage->flags And Not PGHDR_NEED_SYNC
        pPage = pPage->pDirtyNext
    Wend
    pCache->pSynced = pCache->pDirtyTail
End Sub

Sub sqlite3PcacheMove CDecl Alias "sqlite3PcacheMove" ( _
    ByVal pPage As PgHdr Ptr, _
    ByVal newPageNumber As u32 _
) Export

    If pPage = 0 OrElse pPage->pCache = 0 OrElse pPage->pPage = 0 OrElse _
       pPage->nRef <= 0 OrElse newPageNumber = 0 Then Exit Sub
    Dim pCache As PCache Ptr = CPtr(PCache Ptr, pPage->pCache)
    If pPage->pgno = newPageNumber Then Exit Sub

    Dim methods As SqlitePcacheMethods2
    pcacheGetMethods(methods)
    If methods.xFetch = 0 OrElse methods.xRekey = 0 Then Exit Sub
    Dim pOtherPage As sqlite3_pcache_page Ptr = _
        methods.xFetch(pCache->pCache, newPageNumber, 0)
    If pOtherPage <> 0 Then
        Dim pOtherHdr As PgHdr Ptr = CPtr(PgHdr Ptr, pOtherPage->pExtra)
        If pOtherHdr = 0 OrElse pOtherHdr->nRef <> 0 Then Exit Sub
        pOtherHdr->nRef = 1
        pCache->nRefSum += 1
        sqlite3PcacheDrop(pOtherHdr)
    End If

    methods.xRekey(pCache->pCache, pPage->pPage, pPage->pgno, newPageNumber)
    pPage->pgno = newPageNumber
    If (pPage->flags And (PGHDR_DIRTY Or PGHDR_NEED_SYNC)) = (PGHDR_DIRTY Or PGHDR_NEED_SYNC) Then
        pcacheManageDirtyList(pPage, PCACHE_DIRTYLIST_FRONT)
    End If
End Sub

Sub sqlite3PcacheTruncate CDecl Alias "sqlite3PcacheTruncate" ( _
    ByVal pCache As PCache Ptr, _
    ByVal pageNumber As u32 _
) Export

    If pCache = 0 OrElse pCache->pCache = 0 Then Exit Sub
    Dim methods As SqlitePcacheMethods2
    pcacheGetMethods(methods)
    If methods.xFetch = 0 OrElse methods.xTruncate = 0 Then Exit Sub
    Dim pPage As PgHdr Ptr = pCache->pDirty
    While pPage <> 0
        Dim pNext As PgHdr Ptr = pPage->pDirtyNext
        If pPage->pgno > pageNumber Then sqlite3PcacheMakeClean(pPage)
        pPage = pNext
    Wend

    Dim iLimit As u32 = pageNumber
    If pageNumber = 0 AndAlso pCache->nRefSum <> 0 Then
        Dim pPage1 As sqlite3_pcache_page Ptr = _
            methods.xFetch(pCache->pCache, 1, 0)
        If pPage1 <> 0 Then
            Dim pData As UByte Ptr = CPtr(UByte Ptr, pPage1->pBuf)
            For i As Long = 0 To pCache->szPage - 1
                pData[i] = 0
            Next
            iLimit = 1
        End If
    End If
    If iLimit < &HFFFFFFFF Then methods.xTruncate(pCache->pCache, iLimit + 1)
End Sub

Sub sqlite3PcacheClose CDecl Alias "sqlite3PcacheClose" (ByVal pCache As PCache Ptr) Export
    If pCache = 0 OrElse pCache->pCache = 0 Then Exit Sub
    Dim methods As SqlitePcacheMethods2
    pcacheGetMethods(methods)
    If methods.xDestroy <> 0 Then methods.xDestroy(pCache->pCache)
    pCache->pCache = 0
End Sub

Sub sqlite3PcacheClear CDecl Alias "sqlite3PcacheClear" (ByVal pCache As PCache Ptr) Export
    sqlite3PcacheTruncate(pCache, 0)
End Sub

Private Function pcacheMergeDirtyList( _
    ByVal pA As PgHdr Ptr, _
    ByVal pB As PgHdr Ptr _
) As PgHdr Ptr

    If pA = 0 Then Return pB
    If pB = 0 Then Return pA
    Dim pHead As PgHdr Ptr = 0
    Dim pTail As PgHdr Ptr = 0
    While pA <> 0 AndAlso pB <> 0
        Dim pTake As PgHdr Ptr
        If pA->pgno < pB->pgno Then
            pTake = pA
            pA = pA->pDirty
        Else
            pTake = pB
            pB = pB->pDirty
        End If
        If pHead = 0 Then
            pHead = pTake
        Else
            pTail->pDirty = pTake
        End If
        pTail = pTake
    Wend
    If pTail <> 0 Then pTail->pDirty = IIf(pA <> 0, pA, pB)
    Return pHead
End Function

Private Function pcacheSortDirtyList(ByVal pInput As PgHdr Ptr) As PgHdr Ptr
    Dim buckets(0 To PCACHE_SORT_BUCKETS - 1) As PgHdr Ptr
    For i As Long = 0 To PCACHE_SORT_BUCKETS - 1
        buckets(i) = 0
    Next

    While pInput <> 0
        Dim pRun As PgHdr Ptr = pInput
        pInput = pInput->pDirty
        pRun->pDirty = 0
        Dim iBucket As Long = 0
        While iBucket < PCACHE_SORT_BUCKETS - 1 AndAlso buckets(iBucket) <> 0
            pRun = pcacheMergeDirtyList(buckets(iBucket), pRun)
            buckets(iBucket) = 0
            iBucket += 1
        Wend
        If iBucket = PCACHE_SORT_BUCKETS - 1 AndAlso buckets(iBucket) <> 0 Then
            pRun = pcacheMergeDirtyList(buckets(iBucket), pRun)
        End If
        buckets(iBucket) = pRun
    Wend

    Dim pSorted As PgHdr Ptr = 0
    For i As Long = 0 To PCACHE_SORT_BUCKETS - 1
        If buckets(i) <> 0 Then pSorted = pcacheMergeDirtyList(pSorted, buckets(i))
    Next
    Return pSorted
End Function

Function sqlite3PcacheDirtyList CDecl Alias "sqlite3PcacheDirtyList" (ByVal pCache As PCache Ptr) As PgHdr Ptr Export
    If pCache = 0 Then Return 0
    Dim pPage As PgHdr Ptr = pCache->pDirty
    While pPage <> 0
        pPage->pDirty = pPage->pDirtyNext
        pPage = pPage->pDirtyNext
    Wend
    Return pcacheSortDirtyList(pCache->pDirty)
End Function

Function sqlite3PcacheRefCount CDecl Alias "sqlite3PcacheRefCount" (ByVal pCache As PCache Ptr) As i64 Export
    If pCache = 0 Then Return 0
    Return pCache->nRefSum
End Function

Function sqlite3PcachePageRefcount CDecl Alias "sqlite3PcachePageRefcount" (ByVal pPage As PgHdr Ptr) As i64 Export
    If pPage = 0 Then Return 0
    Return pPage->nRef
End Function

Function sqlite3PcachePagecount CDecl Alias "sqlite3PcachePagecount" (ByVal pCache As PCache Ptr) As SQLITE_C_INT Export
    If pCache = 0 OrElse pCache->pCache = 0 Then Return 0
    Dim methods As SqlitePcacheMethods2
    pcacheGetMethods(methods)
    If methods.xPagecount = 0 Then Return 0
    Return methods.xPagecount(pCache->pCache)
End Function

Function sqlite3PcacheGetCachesize CDecl Alias "sqlite3PcacheGetCachesize" (ByVal pCache As PCache Ptr) As SQLITE_C_INT Export
    If pCache = 0 Then Return 0
    Dim nPages As u32 = numberOfCachePages(pCache)
    If nPages > &H7FFFFFFF Then Return &H7FFFFFFF
    Return CLng(nPages)
End Function

Sub sqlite3PcacheSetCachesize CDecl Alias "sqlite3PcacheSetCachesize" ( _
    ByVal pCache As PCache Ptr, _
    ByVal maxPages As SQLITE_C_INT _
) Export

    If pCache = 0 Then Exit Sub
    pCache->szCache = maxPages
    If pCache->pCache = 0 Then Exit Sub
    Dim methods As SqlitePcacheMethods2
    pcacheGetMethods(methods)
    If methods.xCachesize <> 0 Then methods.xCachesize(pCache->pCache, maxPages)
End Sub

Function sqlite3PcacheSetSpillsize CDecl Alias "sqlite3PcacheSetSpillsize" ( _
    ByVal pCache As PCache Ptr, _
    ByVal maxPages As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pCache = 0 Then Return 0
    If maxPages <> 0 Then
        If maxPages < 0 Then
            Dim nPerPage As i64 = CLngInt(pCache->szPage) + pCache->szExtra
            If nPerPage <= 0 Then Return 0
            Dim nPages As i64 = (-1024 * CLngInt(maxPages)) \ nPerPage
            If nPages > &H7FFFFFFF Then nPages = &H7FFFFFFF
            maxPages = CLng(nPages)
        End If
        pCache->szSpill = maxPages
    End If
    Dim result As u32 = numberOfCachePages(pCache)
    If result < CULng(pCache->szSpill) Then Return pCache->szSpill
    If result > &H7FFFFFFF Then Return &H7FFFFFFF
    Return CLng(result)
End Function

Sub sqlite3PcacheShrink CDecl Alias "sqlite3PcacheShrink" (ByVal pCache As PCache Ptr) Export
    If pCache = 0 OrElse pCache->pCache = 0 Then Exit Sub
    Dim methods As SqlitePcacheMethods2
    pcacheGetMethods(methods)
    If methods.xShrink <> 0 Then methods.xShrink(pCache->pCache)
End Sub

Function sqlite3HeaderSizePcache CDecl Alias "sqlite3HeaderSizePcache" () As SQLITE_C_INT Export
    Return CLng(pcacheRound8(SizeOf(PgHdr)))
End Function

Function sqlite3HeaderSizePcache1 CDecl Alias "sqlite3HeaderSizePcache1" () As SQLITE_C_INT Export
    Return CLng(pcacheRound8(SizeOf(SqlitePcache1Page)))
End Function

Function sqlite3PCachePercentDirty CDecl Alias "sqlite3PCachePercentDirty" (ByVal pCache As PCache Ptr) As SQLITE_C_INT Export
    If pCache = 0 Then Return 0
    Dim nCache As u32 = numberOfCachePages(pCache)
    If nCache = 0 Then Return 0
    Dim nDirty As i64 = 0
    Dim pPage As PgHdr Ptr = pCache->pDirty
    While pPage <> 0
        nDirty += 1
        pPage = pPage->pDirtyNext
    Wend
    Return CLng((nDirty * 100) \ nCache)
End Function

Function sqlite3PCacheIsDirty CDecl Alias "sqlite3PCacheIsDirty" (ByVal pCache As PCache Ptr) As SQLITE_C_INT Export
    If pCache = 0 Then Return 0
    Return IIf(pCache->pDirty <> 0, 1, 0)
End Function

Sub sqlite3PcacheIterateDirty CDecl Alias "sqlite3PcacheIterateDirty" ( _
    ByVal pCache As PCache Ptr, _
    ByVal xIter As SqlitePcacheIterateProc _
) Export

    If pCache = 0 OrElse xIter = 0 Then Exit Sub
    Dim pPage As PgHdr Ptr = pCache->pDirty
    While pPage <> 0
        xIter(pPage)
        pPage = pPage->pDirtyNext
    Wend
End Sub

Private Function pageOnDirtyList( _
    ByVal pCache As PCache Ptr, _
    ByVal pPage As PgHdr Ptr _
) As SQLITE_C_INT
    If pCache = 0 OrElse pPage = 0 Then Return 0

    Dim pScan As PgHdr Ptr = pCache->pDirty
    Dim pSlow As PgHdr Ptr = pCache->pDirty
    Dim pFast As PgHdr Ptr = pCache->pDirty
    While pScan <> 0
        If pScan = pPage Then Return 1
        pScan = pScan->pDirtyNext

        If pSlow <> 0 Then pSlow = pSlow->pDirtyNext
        If pFast <> 0 Then pFast = pFast->pDirtyNext
        If pFast <> 0 Then pFast = pFast->pDirtyNext
        If pFast <> 0 AndAlso pFast = pSlow Then Return -1
    Wend
    Return 0
End Function

Private Function pageNotOnDirtyList( _
    ByVal pCache As PCache Ptr, _
    ByVal pPage As PgHdr Ptr _
) As SQLITE_C_INT
    Dim membership As SQLITE_C_INT = pageOnDirtyList(pCache, pPage)
    If membership < 0 Then Return 0
    Return IIf(membership <> 0, 0, 1)
End Function

Function sqlite3PcachePageSanity CDecl Alias "sqlite3PcachePageSanity" (ByVal pPage As PgHdr Ptr) As SQLITE_C_INT Export
    If pPage = 0 OrElse pPage->pCache = 0 OrElse pPage->pPage = 0 Then Return 0
    Dim pCache As PCache Ptr = CPtr(PCache Ptr, pPage->pCache)
    If pPage->pgno = 0 AndAlso pPage->pPager <> 0 Then Return 0
    If (pPage->flags And PGHDR_CLEAN) <> 0 Then
        If (pPage->flags And PGHDR_DIRTY) <> 0 Then Return 0
        If pageNotOnDirtyList(pCache, pPage) = 0 Then Return 0
    ElseIf (pPage->flags And PGHDR_DIRTY) = 0 Then
        Return 0
    Else
        If pPage->pDirtyNext <> 0 AndAlso _
           pPage->pDirtyNext->pDirtyPrev <> pPage Then Return 0
        If pPage->pDirtyPrev <> 0 AndAlso _
           pPage->pDirtyPrev->pDirtyNext <> pPage Then Return 0
        If pPage->pDirtyPrev = 0 AndAlso pCache->pDirty <> pPage Then Return 0
        If pageOnDirtyList(pCache, pPage) <> 1 Then Return 0
    End If
    If (pPage->flags And PGHDR_WRITEABLE) <> 0 AndAlso _
       (pPage->flags And PGHDR_DIRTY) = 0 Then Return 0
    Return 1
End Function

Function sqlite3PageMalloc CDecl Alias "sqlite3PageMalloc" ( _
    ByVal nByte As SQLITE_C_INT _
) As Any Ptr Export

    If nByte <= 0 OrElse nByte > PCACHE_MAX_PAGE_SIZE + 8 Then Return 0
    Return pcache1Alloc(nByte)
End Function

Sub sqlite3PageFree CDecl Alias "sqlite3PageFree" (ByVal p As Any Ptr) Export
    pcache1Free(p)
End Sub

/' end of sqlite3_pcache.bas '/
