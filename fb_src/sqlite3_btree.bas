/'
    Project: SQLite FreeBASIC port

    File: sqlite3_btree.bas

    Purpose:

        Decode SQLite B-tree pages and write leaf cells and their payloads.

    Responsibilities:

        - Bind a pager page to its auxiliary MemPage structure.
        - Validate B-tree page headers and cell-pointer ranges.
        - Decode table and index cell headers, including overflow layout.
        - Validate freeblock chains and calculate available page space.
        - Release pager references through the B-tree page interface.
        - Open and close a single B-tree handle backed by the pager.
        - Close a transient BTREE_SINGLE handle when its last cursor closes.
        - Begin, commit, and roll back one handle's pager transaction.
        - Configure cache sizing, pager flags, page size, and reserve bytes.
        - Allocate and release one shared-schema object per BtShared handle.
        - Create table and index roots with auto-vacuum pointer-map maintenance.
        - Clear trees after saving cursor positions and invalidating blob cursors.
        - Drop roots and compact the root-page range under auto-vacuum.
        - Allocate and reuse non-auto-vacuum pages from the database freelist.
        - Release bounded overflow chains back to the non-auto-vacuum freelist.
        - Overwrite local and overflow payload bytes without changing cell layout.
        - Read checked payload ranges and write incremental-blob payload ranges.
        - Traverse table and index cursors and read row payload bytes.
        - Search integer-key tables and follow overflow payload chains.
        - Search unpacked index keys through the VDBE record comparator.
        - Return the associated table cursor for debug cursor-hint assertions.
        - Format table/index cells and insert into leaves or replace index separators.
        - Queue leaf cells that need balancing and split an appended table leaf.
        - Insert table/index payloads and rebalance pages while preserving cursors.
        - Delete table/index entries, replace internal separators, and rebalance.
        - Report cursor state, tree emptiness, and page-size policy.
        - Provide the persistent fake cursor used by cursor-state assertions.
        - Rebuild a page from an ordered array of cell pointers.
        - Insert and release ordered cell-array ranges during page edits.
        - Edit a page against a balanced cell-array slice.
        - Plan sibling-page cell distribution for balancing.
        - Apply non-auto-vacuum sibling plans and collapse empty roots.
        - Size promoted divider cells within sibling and scratch buffer bounds.
        - Select sibling pages and detach their parent divider cells.
        - Assemble sibling cells into a balance array and initial page plan.
        - Copy initialized B-tree page contents to a writable sibling.
        - Expand a full root page into a child for later balancing.
        - Compute pointer-map page/entry locations and read or write map records.
        - Update the pointer-map record for a moved overflow cell.
        - Relocate an auto-vacuum page and repair its incoming/outgoing maps.
        - Track freed-page content so same-transaction reuse preserves rollback data.
        - Clear content tracking at transaction end and expose the B-tree pager.
        - Open WAL mode from the page-one format and forward checkpoint requests.
        - Check cursor mutex ownership and parent-child page invariants in debug builds.

    This file intentionally does NOT contain:

        - Shared-cache table locks or complete pointer-map maintenance.
        - Clearing a B-tree while one of its cursors remains open.
        - Auto-vacuum page relocation/commit policy or SQL cursor insertion.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_varint.bi"
#include once "sqlite3_walker.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_vdbe_record.bi"
#include once "sqlite3_vdbe_compare.bi"
#include once "sqlite3_pager.bi"
#include once "sqlite3_pcache.bi"
#include once "sqlite3_btree.bi"
#include once "sqlite3_bitvec.bi"
#include once "sqlite3_fault.bi"
#include once "sqlite3_debug_assert.bi"

Declare Function sqlite3MallocZero CDecl Alias "sqlite3MallocZero" (ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Function sqlite3Malloc CDecl Alias "sqlite3Malloc" (ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Declare Function sqlite3_close_v2 CDecl Alias "sqlite3_close_v2" (ByVal db As sqlite3 Ptr) As SQLITE_C_INT
Declare Function sqlite3CorruptError CDecl Alias "sqlite3CorruptError" (ByVal sourceLine As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3ConfigTestNeverCorrupt CDecl Alias "sqlite3ConfigTestNeverCorrupt" () As SQLITE_C_INT
Declare Function sqlite3TempInMemory CDecl Alias "sqlite3TempInMemory" (ByVal db As Const sqlite3 Ptr) As SQLITE_C_INT
Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal zText As Const ZString Ptr _
) As SQLITE_C_INT
#ifndef SQLITE_OMIT_SHARED_CACHE
' BtShared entries remain here while a shared-cache B-tree has references.
Private Dim Shared sqlite3SharedCacheList As BtShared Ptr
#endif
Declare Function incrVacuumStep CDecl Alias "incrVacuumStep" ( _
    ByVal pBt As BtShared Ptr, _
    ByVal finalPageCount As SQLITE_C_UINT, _
    ByVal lastPage As SQLITE_C_UINT, _
    ByVal isCommit As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function finalDbSize CDecl Alias "finalDbSize" ( _
    ByVal pBt As BtShared Ptr, _
    ByVal originalPageCount As SQLITE_C_UINT, _
    ByVal freePageCount As SQLITE_C_UINT _
) As SQLITE_C_UINT
Declare Function autoVacuumCommit CDecl Alias "autoVacuumCommit" ( _
    ByVal pBtree As Btree Ptr _
) As SQLITE_C_INT
Declare Function btreeSystemMemcpy CDecl Alias "memcpy" ( _
    ByVal pDestination As Any Ptr, _
    ByVal pSource As Const Any Ptr, _
    ByVal nByte As SQLITE_SIZE_T _
) As Any Ptr
Declare Function btreeSystemMemmove CDecl Alias "memmove" ( _
    ByVal pDestination As Any Ptr, _
    ByVal pSource As Const Any Ptr, _
    ByVal nByte As SQLITE_SIZE_T _
) As Any Ptr
#if defined(SQLITE_ENABLE_CURSOR_HINTS) AndAlso defined(SQLITE_DEBUG)
Declare Function sqlite3CursorRangeHintExprCheck CDecl Alias "sqlite3CursorRangeHintExprCheck" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT
#endif

Private Type BtreeSchemaFreeCallback As Sub CDecl ( _
    ByVal pSchema As Any Ptr _
)

Private Type BtreeBalancePlan
    pageCount As SQLITE_C_INT
    usedBytes(0 To 4) As SQLITE_C_INT
    cellEnd(0 To 4) As SQLITE_C_INT
End Type
Private Type BtreeBalanceSiblingSet
    nOld As SQLITE_C_INT
    nxDiv As SQLITE_C_INT
    targetIndex As SQLITE_C_INT
    nMaxCells As SQLITE_C_INT
    leafCorrection As u16
    leafData As SQLITE_C_INT
    usableSpace As SQLITE_C_INT
    pRightChild As UByte Ptr
    pDividerCopy As UByte Ptr
    apOld(0 To 2) As MemPage Ptr
    cellEndOld(0 To 2) As SQLITE_C_INT
    apDivider(0 To 1) As UByte Ptr
    dividerSize(0 To 1) As u16
End Type

Private Const BTALLOC_ANY As u8 = 0
Private Const BTALLOC_EXACT As u8 = 1
Private Const BTALLOC_LE As u8 = 2

Declare Function btreeAccessPayload ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal offset As u32, _
    ByVal amount As u32, _
    ByVal pBuffer As Any Ptr _
) As SQLITE_C_INT
Declare Function btreeAllocatePageMode ( _
    ByVal pBt As BtShared Ptr, _
    ByVal ppPage As MemPage Ptr Ptr, _
    ByVal pPageNumber As u32 Ptr, _
    ByVal mapType As u8, _
    ByVal parentPage As u32, _
    ByVal nearby As u32, _
    ByVal allocationMode As u8 _
) As SQLITE_C_INT
Declare Function btreeAllocatePageAny ( _
    ByVal pBt As BtShared Ptr, _
    ByVal ppPage As MemPage Ptr Ptr, _
    ByVal pPageNumber As u32 Ptr, _
    ByVal mapType As u8, _
    ByVal parentPage As u32 _
) As SQLITE_C_INT
Declare Function btreeFreePageNumber ( _
    ByVal pBt As BtShared Ptr, _
    ByVal pPageToFree As MemPage Ptr, _
    ByVal pageNumber As u32 _
) As SQLITE_C_INT
Declare Function getOverflowPage CDecl Alias "getOverflowPage" ( _
    ByVal pBt As BtShared Ptr, _
    ByVal overflowPage As u32, _
    ByVal ppPage As MemPage Ptr Ptr, _
    ByVal pNextPage As u32 Ptr _
) As SQLITE_C_INT
Declare Sub ptrmapPutOvflPtr ( _
    ByVal pPage As MemPage Ptr, _
    ByVal pSourcePage As MemPage Ptr, _
    ByVal pCell As UByte Ptr, _
    ByVal pRc As SQLITE_C_INT Ptr _
)
Declare Function btreeParseCell CDecl Alias "btreeParseCell" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal cellIndex As SQLITE_C_INT, _
    ByVal pInfo As CellInfo Ptr _
) As SQLITE_C_INT
Declare Function btreeReadU32 (ByVal pData As Const UByte Ptr) As u32
Declare Sub btreeWriteU32 (ByVal pData As UByte Ptr, ByVal value As u32)
Declare Function btreeCursorCell ( _
    ByVal pPage As MemPage Ptr, _
    ByVal cellIndex As SQLITE_C_INT _
) As UByte Ptr
Declare Function btreeComputeBalanceDistribution ( _
    ByVal pCellArray As BtreeCellArray Ptr, _
    ByVal totalCellCount As SQLITE_C_INT, _
    ByVal oldPageCount As SQLITE_C_INT, _
    ByVal leafData As SQLITE_C_INT, _
    ByVal bulkLoad As SQLITE_C_INT, _
    ByVal usableSpace As SQLITE_C_INT, _
    ByVal pPlan As BtreeBalancePlan Ptr _
) As SQLITE_C_INT
Declare Function btreeEditPage ( _
    ByVal pPage As MemPage Ptr, _
    ByVal oldFirstCell As SQLITE_C_INT, _
    ByVal newFirstCell As SQLITE_C_INT, _
    ByVal newCellCount As SQLITE_C_INT, _
    ByVal pCellArray As BtreeCellArray Ptr _
) As SQLITE_C_INT
Declare Sub btreeCursorClearCellInfo(ByVal pCursor As BtCursor Ptr)
Declare Sub btreeSetPayloadLimits(ByVal pBt As BtShared Ptr)
Declare Function btreeSaveCursorPosition CDecl Alias "saveCursorPosition" ( _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT
Declare Function btreeSaveCursorsOnList CDecl Alias "saveCursorsOnList" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal rootPage As u32, _
    ByVal pExcept As BtCursor Ptr _
) As SQLITE_C_INT
Declare Function btreeSaveAllCursors CDecl Alias "saveAllCursors" ( _
    ByVal pBt As BtShared Ptr, _
    ByVal rootPage As u32, _
    ByVal pExcept As BtCursor Ptr _
) As SQLITE_C_INT
Declare Function btreeBeginTrans CDecl Alias "btreeBeginTrans" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal writeFlag As SQLITE_C_INT, _
    ByVal pSchemaVersion As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Function btreeCursorRestoreInternal ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT

' Keep the file-format lock byte at SQLite's default offset unless a caller
' changes the exported test-control global.
Dim Shared sqlite3PendingByte As SQLITE_C_INT = &H40000000

Private Dim Shared As Const UByte btreeFileMagic(0 To 15) = _
    {83, 81, 76, 105, 116, 101, 32, 102, 111, 114, 109, 97, 116, 32, 51, 0}

Private Function btreeFilenameIsMemory(ByVal zFilename As Const ZString Ptr) As SQLITE_C_INT
    If zFilename = 0 Then Return 0
    Dim memoryName As Const ZString Ptr = StrPtr(":memory:")
    Dim i As Long = 0
    While memoryName[i] <> 0
        If zFilename[i] <> memoryName[i] Then Return 0
        i += 1
    Wend
    Return IIf(zFilename[i] = 0, 1, 0)
End Function

Private Sub pageReinit CDecl Alias "pageReinit" (ByVal pDbPage As PgHdr Ptr)
    If pDbPage = 0 Then Exit Sub
    Dim pPage As MemPage Ptr = CPtr(MemPage Ptr, sqlite3PagerGetExtra(pDbPage))
    If pPage = 0 OrElse pPage->isInit = 0 Then Exit Sub
    pPage->isInit = 0
    If sqlite3PagerPageRefcount(pDbPage) > 1 Then sqlite3BtreeInitPage(pPage)
End Sub

Private Sub btreeOpenCleanup(ByVal pBtree As Btree Ptr, ByVal pBt As BtShared Ptr)
    If pBt <> 0 Then
        If pBt->pPager <> 0 Then sqlite3PagerClose(pBt->pPager, pBt->db)
        If pBt->mutex <> 0 Then sqlite3_mutex_free(pBt->mutex)
        sqlite3_free(pBt)
    End If
    If pBtree <> 0 Then sqlite3_free(pBtree)
End Sub

#ifndef SQLITE_OMIT_SHARED_CACHE
Private Function btreeFilenameEqual( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT
    If zLeft = 0 OrElse zRight = 0 Then Return 0
    Dim iByte As SQLITE_C_INT = 0
    While zLeft[iByte] <> 0 AndAlso zRight[iByte] <> 0
        If zLeft[iByte] <> zRight[iByte] Then Return 0
        If iByte = SQLITE_MAX_ALLOCATION_SIZE - 1 Then Return 0
        iByte += 1
    Wend
    Return CInt(zLeft[iByte] = 0 AndAlso zRight[iByte] = 0)
End Function

Private Sub btreeLinkSharedCache(ByVal pBtree As Btree Ptr)
    If pBtree = 0 OrElse pBtree->db = 0 OrElse pBtree->pBt = 0 OrElse _
       pBtree->sharable = 0 Then Exit Sub

    Dim pSibling As Btree Ptr = 0
    For iDb As SQLITE_C_INT = 0 To pBtree->db->nDb - 1
        Dim pExisting As Btree Ptr = _
            CPtr(Btree Ptr, pBtree->db->aDb(iDb).pBt)
        If pExisting <> 0 AndAlso pExisting <> pBtree AndAlso _
           pExisting->sharable <> 0 Then
            While pExisting->pPrev <> 0
                pExisting = CPtr(Btree Ptr, pExisting->pPrev)
            Wend
            pSibling = pExisting
            Exit For
        End If
    Next
    If pSibling = 0 Then Exit Sub

    If CULngInt(pBtree->pBt) < CULngInt(pSibling->pBt) Then
        pBtree->pNext = pSibling
        pSibling->pPrev = pBtree
        Exit Sub
    End If

    While pSibling->pNext <> 0 AndAlso _
          CULngInt(CPtr(Btree Ptr, pSibling->pNext)->pBt) < _
          CULngInt(pBtree->pBt)
        pSibling = CPtr(Btree Ptr, pSibling->pNext)
    Wend
    pBtree->pNext = pSibling->pNext
    pBtree->pPrev = pSibling
    If pBtree->pNext <> 0 Then _
        CPtr(Btree Ptr, pBtree->pNext)->pPrev = pBtree
    pSibling->pNext = pBtree
End Sub

Private Sub btreeUnlinkSharedCache(ByVal pBtree As Btree Ptr)
    If pBtree = 0 OrElse pBtree->sharable = 0 Then Exit Sub
    If pBtree->pPrev <> 0 Then _
        CPtr(Btree Ptr, pBtree->pPrev)->pNext = pBtree->pNext
    If pBtree->pNext <> 0 Then _
        CPtr(Btree Ptr, pBtree->pNext)->pPrev = pBtree->pPrev
    pBtree->pNext = 0
    pBtree->pPrev = 0
End Sub
#endif

Private Sub invalidateIncrblobCursors CDecl Alias "invalidateIncrblobCursors" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal rootPage As u32, _
    ByVal rowId As i64, _
    ByVal clearTable As SQLITE_C_INT _
)
    If pBtree = 0 OrElse pBtree->pBt = 0 OrElse pBtree->hasIncrblobCur = 0 Then Exit Sub
    pBtree->hasIncrblobCur = 0
    Dim pCursor As BtCursor Ptr = CPtr(BtCursor Ptr, pBtree->pBt->pCursor)
    While pCursor <> 0
        If (pCursor->curFlags And BTCF_INCRBLOB) <> 0 Then
            pBtree->hasIncrblobCur = 1
            If pCursor->pgnoRoot = rootPage AndAlso _
               (clearTable <> 0 OrElse pCursor->info.nKey = rowId) Then
                pCursor->eState = CURSOR_INVALID
            End If
        End If
        pCursor = pCursor->pNext
    Wend
End Sub

Private Sub invalidateAllOverflowCache CDecl Alias "invalidateAllOverflowCache" (ByVal pBt As BtShared Ptr)
    If pBt = 0 Then Exit Sub
    Dim pCursor As BtCursor Ptr = CPtr(BtCursor Ptr, pBt->pCursor)
    While pCursor <> 0
        pCursor->curFlags = pCursor->curFlags And Not BTCF_VALID_OVFL
        pCursor = pCursor->pNext
    Wend
End Sub

#ifdef SQLITE_DEBUG
Private Function cursorHoldsMutex CDecl Alias "cursorHoldsMutex" ( _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT
    If pCursor = 0 OrElse pCursor->pBt = 0 Then Return 0
    Return sqlite3_mutex_held(pCursor->pBt->mutex)
End Function

Private Function cursorOwnsBtShared CDecl Alias "cursorOwnsBtShared" ( _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT
    If pCursor = 0 OrElse pCursor->pBtree = 0 OrElse pCursor->pBt = 0 Then Return 0
    If cursorHoldsMutex(pCursor) = 0 Then Return 0
    Return CInt(pCursor->pBtree->db = pCursor->pBt->db)
End Function
#endif

Private Sub btreeClearHasContent CDecl Alias "btreeClearHasContent" ( _
    ByVal pBt As BtShared Ptr _
)
    If pBt = 0 Then Exit Sub
    sqlite3BitvecDestroy(pBt->pHasContent)
    pBt->pHasContent = 0
End Sub

Private Function btreeSetHasContent CDecl Alias "btreeSetHasContent" ( _
    ByVal pBt As BtShared Ptr, _
    ByVal pageNumber As u32 _
) As SQLITE_C_INT
    If pBt = 0 OrElse pageNumber = 0 OrElse pageNumber > pBt->nPage Then Return SQLITE_CORRUPT
    If pBt->pHasContent = 0 Then
        pBt->pHasContent = sqlite3BitvecCreate(pBt->nPage)
        If pBt->pHasContent = 0 Then Return SQLITE_NOMEM
    End If
    If pageNumber <= sqlite3BitvecSize(pBt->pHasContent) Then
        Return sqlite3BitvecSet(pBt->pHasContent, pageNumber)
    End If
    Return SQLITE_OK
End Function

Function btreeGetHasContent CDecl Alias "btreeGetHasContent" ( _
    ByVal pBt As BtShared Ptr, _
    ByVal pageNumber As u32 _
) As SQLITE_C_INT
    If pBt = 0 OrElse pBt->pHasContent = 0 Then Return 0
    If pageNumber > sqlite3BitvecSize(pBt->pHasContent) Then Return 1
    Return sqlite3BitvecTestNotNull(pBt->pHasContent, pageNumber)
End Function

Private Sub freeTempSpace CDecl Alias "freeTempSpace" (ByVal pBt As BtShared Ptr)
    If pBt = 0 OrElse pBt->pTmpSpace = 0 Then Exit Sub
    sqlite3PageFree(pBt->pTmpSpace - 4)
    pBt->pTmpSpace = 0
End Sub

/' ------------------------------------------------------------------------- '/
/' Page-safe integer access '/
/' ------------------------------------------------------------------------- '/

Private Function btreeGetU16(ByVal pData As Const UByte Ptr) As u16
    If pData = 0 Then Return 0
    Return (CUShort(pData[0]) Shl 8) Or CUShort(pData[1])
End Function

Private Sub btreeWriteU16(ByVal pData As UByte Ptr, ByVal value As u16)
    If pData = 0 Then Exit Sub
    pData[0] = CByte((value Shr 8) And &HFF)
    pData[1] = CByte(value And &HFF)
End Sub

Private Function btreeGetU16NotZero(ByVal pData As Const UByte Ptr) As u32
    Dim value As u16 = btreeGetU16(pData)
    If value = 0 Then Return 65536
    Return value
End Function

Private Function btreePageHasRange( _
    ByVal pPage As MemPage Ptr, _
    ByVal pData As Const UByte Ptr, _
    ByVal amount As sqlite3_int64 _
) As SQLITE_C_INT

    If pPage = 0 OrElse pPage->aData = 0 OrElse pPage->pBt = 0 OrElse pData = 0 OrElse amount < 0 Then Return 0
    Dim baseAddress As sqlite3_uint64 = CULngInt(pPage->aData)
    Dim dataAddress As sqlite3_uint64 = CULngInt(pData)
    Dim usableEnd As sqlite3_uint64 = baseAddress + pPage->pBt->usableSize
    If dataAddress < baseAddress OrElse dataAddress > usableEnd Then Return 0
    If CULngInt(amount) > usableEnd - dataAddress Then Return 0
    Return 1
End Function

Private Function btreeCellHasRange( _
    ByVal pPage As MemPage Ptr, _
    ByVal pData As Const UByte Ptr, _
    ByVal amount As sqlite3_int64 _
) As SQLITE_C_INT

    If pPage = 0 OrElse pPage->pBt = 0 OrElse pData = 0 OrElse amount < 0 Then Return 0
    If btreePageHasRange(pPage, pData, amount) <> 0 Then Return 1

    ' Cell-size callbacks also inspect cells in the shared preformat buffer.
    ' MX_CELL_SIZE leaves four bytes before the cell and four bytes after it.
    Dim pBt As BtShared Ptr = pPage->pBt
    If pBt->pTmpSpace = 0 OrElse pBt->pageSize <= 8 Then Return 0
    Dim bufferAddress As sqlite3_uint64 = CULngInt(pBt->pTmpSpace)
    Dim dataAddress As sqlite3_uint64 = CULngInt(pData)
    Dim bufferBytes As sqlite3_uint64 = CULngInt(pBt->pageSize) - 8
    If bufferBytes > &HFFFFFFFFFFFFFFFF - bufferAddress Then Return 0
    Dim bufferEnd As sqlite3_uint64 = bufferAddress + bufferBytes
    If dataAddress < bufferAddress OrElse dataAddress > bufferEnd Then Return 0
    If CULngInt(amount) > bufferEnd - dataAddress Then Return 0
    Return 1
End Function

Private Function btreeReadVarint( _
    ByVal pPage As MemPage Ptr, _
    ByVal pInput As Const UByte Ptr, _
    ByVal pValue As sqlite3_uint64 Ptr, _
    ByVal pLength As SQLITE_C_INT Ptr _
) As SQLITE_C_INT

    If pValue = 0 OrElse pLength = 0 OrElse btreePageHasRange(pPage, pInput, 1) = 0 Then Return SQLITE_CORRUPT
    Dim value As sqlite3_uint64 = 0
    For i As SQLITE_C_INT = 0 To 8
        If btreePageHasRange(pPage, pInput + i, 1) = 0 Then Return SQLITE_CORRUPT
        Dim byteValue As UByte = pInput[i]
        If i = 8 Then
            value = (value Shl 8) Or byteValue
            pValue[0] = value
            pLength[0] = 9
            Return SQLITE_OK
        End If
        value = (value Shl 7) Or (byteValue And &H7F)
        If (byteValue And &H80) = 0 Then
            pValue[0] = value
            pLength[0] = i + 1
            Return SQLITE_OK
        End If
    Next
    Return SQLITE_CORRUPT
End Function

Private Function btreeReadCellVarint( _
    ByVal pPage As MemPage Ptr, _
    ByVal pInput As Const UByte Ptr, _
    ByVal pValue As sqlite3_uint64 Ptr, _
    ByVal pLength As SQLITE_C_INT Ptr _
) As SQLITE_C_INT

    If pValue = 0 OrElse pLength = 0 OrElse btreeCellHasRange(pPage, pInput, 1) = 0 Then Return SQLITE_CORRUPT
    Dim value As sqlite3_uint64 = 0
    For i As SQLITE_C_INT = 0 To 8
        If btreeCellHasRange(pPage, pInput + i, 1) = 0 Then Return SQLITE_CORRUPT
        Dim byteValue As UByte = pInput[i]
        If i = 8 Then
            value = (value Shl 8) Or byteValue
            pValue[0] = value
            pLength[0] = 9
            Return SQLITE_OK
        End If
        value = (value Shl 7) Or (byteValue And &H7F)
        If (byteValue And &H80) = 0 Then
            pValue[0] = value
            pLength[0] = i + 1
            Return SQLITE_OK
        End If
    Next
    Return SQLITE_CORRUPT
End Function

Private Function btreePayloadToLocal CDecl Alias "btreePayloadToLocal" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal payloadSize As sqlite3_int64 _
) As SQLITE_C_INT
    If pPage = 0 OrElse pPage->pBt = 0 OrElse payloadSize < 0 Then Return 0
    If payloadSize <= pPage->maxLocal Then Return CLng(payloadSize)
    If pPage->pBt->usableSize <= 4 OrElse pPage->minLocal > pPage->maxLocal Then Return 0

    Dim minLocal As sqlite3_int64 = pPage->minLocal
    Dim usablePayload As sqlite3_int64 = pPage->pBt->usableSize - 4
    Dim localSize As sqlite3_int64 = minLocal + (payloadSize - minLocal) Mod usablePayload
    If localSize > pPage->maxLocal Then localSize = minLocal
    Return CLng(localSize)
End Function

Private Sub btreeParseCellAdjustSizeForOverflow CDecl Alias "btreeParseCellAdjustSizeForOverflow" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As UByte Ptr, _
    ByVal pInfo As CellInfo Ptr _
)
    If pPage = 0 OrElse pPage->pBt = 0 OrElse pCell = 0 OrElse _
       pInfo = 0 OrElse pInfo->pPayload = 0 Then Exit Sub
    Dim localSize As SQLITE_C_INT = btreePayloadToLocal(pPage, CLngInt(pInfo->nPayload))
    If localSize < 0 OrElse localSize > &HFFFF Then
        pInfo->nSize = 0
        Return
    End If
    pInfo->nLocal = CUShort(localSize)

    Dim payloadEnd As ULongInt = CULngInt(pInfo->pPayload) + CULngInt(localSize)
    Dim cellAddress As ULongInt = CULngInt(pCell)
    If payloadEnd < CULngInt(pInfo->pPayload) OrElse payloadEnd < cellAddress Then
        pInfo->nSize = 0
        Return
    End If
    Dim totalSize As ULongInt = payloadEnd - cellAddress + 4
    If totalSize > &HFFFF Then
        pInfo->nSize = 0
    Else
        pInfo->nSize = CUShort(totalSize)
    End If
End Sub

Private Function btreeComputeCellSize( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As UByte Ptr, _
    ByVal prefixSize As SQLITE_C_INT, _
    ByVal isTableLeaf As SQLITE_C_INT _
) As u16

    If pPage = 0 OrElse pCell = 0 OrElse pPage->pBt = 0 OrElse prefixSize < 0 Then Return 0
    Dim pVarint As Const UByte Ptr = CPtr(Const UByte Ptr, pCell) + prefixSize
    Dim payloadValue As sqlite3_uint64 = 0
    Dim payloadLength As SQLITE_C_INT = 0
    If btreeReadCellVarint(pPage, pVarint, @payloadValue, @payloadLength) <> SQLITE_OK Then Return 0
    If payloadValue > &HFFFFFFFF Then Return 0

    Dim headerBytes As sqlite3_uint64 = CULngInt(prefixSize) + payloadLength
    If isTableLeaf <> 0 Then
        Dim keyValue As sqlite3_uint64 = 0
        Dim keyLength As SQLITE_C_INT = 0
        Dim pKey As Const UByte Ptr = pVarint + payloadLength
        If btreeReadCellVarint(pPage, pKey, @keyValue, @keyLength) <> SQLITE_OK Then Return 0
        headerBytes += keyLength
    End If

    Dim localSize As u16 = CUShort(btreePayloadToLocal(pPage, CLngInt(payloadValue)))
    If payloadValue > pPage->maxLocal AndAlso localSize = 0 Then Return 0
    Dim totalSize As sqlite3_uint64 = headerBytes + localSize
    If payloadValue > localSize Then totalSize += 4
    If totalSize < 4 Then totalSize = 4
    If totalSize > pPage->pBt->usableSize OrElse totalSize > 65535 Then Return 0
    If btreeCellHasRange(pPage, pCell, CLngInt(totalSize)) = 0 Then Return 0
    Return CUShort(totalSize)
End Function

/' ------------------------------------------------------------------------- '/
/' Cell-size and cell-parse callbacks '/
/' ------------------------------------------------------------------------- '/

Function cellSizePtr CDecl Alias "cellSizePtr" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As UByte Ptr _
) As u16
    If pPage = 0 OrElse pPage->childPtrSize <> 4 Then Return 0
    Return btreeComputeCellSize(pPage, pCell, 4, 0)
End Function

Function cellSizePtrIdxLeaf CDecl Alias "cellSizePtrIdxLeaf" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As UByte Ptr _
) As u16
    If pPage = 0 OrElse pPage->childPtrSize <> 0 Then Return 0
    Return btreeComputeCellSize(pPage, pCell, 0, 0)
End Function

Function cellSizePtrNoPayload CDecl Alias "cellSizePtrNoPayload" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As UByte Ptr _
) As u16
    If pPage = 0 OrElse pPage->childPtrSize <> 4 Then Return 0
    Dim pKey As Const UByte Ptr = CPtr(Const UByte Ptr, pCell) + 4
    Dim keyValue As sqlite3_uint64 = 0
    Dim keyLength As SQLITE_C_INT = 0
    If btreeReadCellVarint(pPage, pKey, @keyValue, @keyLength) <> SQLITE_OK Then Return 0
    If keyLength + 4 > pPage->pBt->usableSize Then Return 0
    If btreeCellHasRange(pPage, pCell, keyLength + 4) = 0 Then Return 0
    Return CUShort(keyLength + 4)
End Function

Function cellSizePtrTableLeaf CDecl Alias "cellSizePtrTableLeaf" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As UByte Ptr _
) As u16
    If pPage = 0 OrElse pPage->childPtrSize <> 0 Then Return 0
    Return btreeComputeCellSize(pPage, pCell, 0, 1)
End Function

Sub btreeParseCellPtrNoPayload CDecl Alias "btreeParseCellPtrNoPayload" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As UByte Ptr, _
    ByVal pInfo As CellInfo Ptr _
)
    If pInfo = 0 Then Exit Sub
    pInfo->nKey = 0
    pInfo->pPayload = 0
    pInfo->nPayload = 0
    pInfo->nLocal = 0
    pInfo->nSize = 0
    If pPage = 0 OrElse pCell = 0 Then Exit Sub
    Dim keyValue As sqlite3_uint64 = 0
    Dim keyLength As SQLITE_C_INT = 0
    If btreeReadCellVarint(pPage, CPtr(Const UByte Ptr, pCell) + 4, @keyValue, @keyLength) <> SQLITE_OK Then Exit Sub
    pInfo->nKey = CPtr(i64 Ptr, @keyValue)[0]
    pInfo->nSize = CUShort(keyLength + 4)
    If btreeCellHasRange(pPage, pCell, pInfo->nSize) = 0 Then pInfo->nSize = 0
End Sub

Sub btreeParseCellPtr CDecl Alias "btreeParseCellPtr" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As UByte Ptr, _
    ByVal pInfo As CellInfo Ptr _
)
    If pInfo = 0 Then Exit Sub
    pInfo->nKey = 0
    pInfo->pPayload = 0
    pInfo->nPayload = 0
    pInfo->nLocal = 0
    pInfo->nSize = 0
    If pPage = 0 OrElse pCell = 0 Then Exit Sub

    Dim payloadValue As sqlite3_uint64 = 0
    Dim payloadLength As SQLITE_C_INT = 0
    If btreeReadCellVarint(pPage, pCell, @payloadValue, @payloadLength) <> SQLITE_OK OrElse _
       payloadValue > &HFFFFFFFF Then Exit Sub
    Dim keyValue As sqlite3_uint64 = 0
    Dim keyLength As SQLITE_C_INT = 0
    Dim pKey As Const UByte Ptr = CPtr(Const UByte Ptr, pCell) + payloadLength
    If btreeReadCellVarint(pPage, pKey, @keyValue, @keyLength) <> SQLITE_OK Then Exit Sub

    pInfo->nKey = CPtr(i64 Ptr, @keyValue)[0]
    pInfo->nPayload = CULng(payloadValue)
    pInfo->pPayload = CPtr(UByte Ptr, pKey) + keyLength
    If pInfo->nPayload <= pPage->maxLocal Then
        pInfo->nLocal = CUShort(pInfo->nPayload)
        Dim totalSize As sqlite3_uint64 = CULngInt(payloadLength) + keyLength + pInfo->nLocal
        If totalSize < 4 Then totalSize = 4
        If totalSize <= pPage->pBt->usableSize AndAlso totalSize <= 65535 Then pInfo->nSize = CUShort(totalSize)
    Else
        btreeParseCellAdjustSizeForOverflow(pPage, pCell, pInfo)
    End If
    If pInfo->nSize <> 0 AndAlso btreeCellHasRange(pPage, pCell, pInfo->nSize) = 0 Then pInfo->nSize = 0
End Sub

Sub btreeParseCellPtrIndex CDecl Alias "btreeParseCellPtrIndex" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As UByte Ptr, _
    ByVal pInfo As CellInfo Ptr _
)
    If pInfo = 0 Then Exit Sub
    pInfo->nKey = 0
    pInfo->pPayload = 0
    pInfo->nPayload = 0
    pInfo->nLocal = 0
    pInfo->nSize = 0
    If pPage = 0 OrElse pCell = 0 Then Exit Sub

    Dim payloadValue As sqlite3_uint64 = 0
    Dim payloadLength As SQLITE_C_INT = 0
    Dim pVarint As Const UByte Ptr = CPtr(Const UByte Ptr, pCell) + pPage->childPtrSize
    If btreeReadCellVarint(pPage, pVarint, @payloadValue, @payloadLength) <> SQLITE_OK OrElse _
       payloadValue > &HFFFFFFFF Then Exit Sub
    pInfo->nKey = CPtr(i64 Ptr, @payloadValue)[0]
    pInfo->nPayload = CULng(payloadValue)
    pInfo->pPayload = CPtr(UByte Ptr, pVarint) + payloadLength
    If pInfo->nPayload <= pPage->maxLocal Then
        pInfo->nLocal = CUShort(pInfo->nPayload)
        Dim totalSize As sqlite3_uint64 = CULngInt(pPage->childPtrSize) + payloadLength + pInfo->nLocal
        If totalSize < 4 Then totalSize = 4
        If totalSize <= pPage->pBt->usableSize AndAlso totalSize <= 65535 Then pInfo->nSize = CUShort(totalSize)
    Else
        btreeParseCellAdjustSizeForOverflow(pPage, pCell, pInfo)
    End If
    If pInfo->nSize <> 0 AndAlso btreeCellHasRange(pPage, pCell, pInfo->nSize) = 0 Then pInfo->nSize = 0
End Sub

/' ------------------------------------------------------------------------- '/
/' Page type and pager integration '/
/' ------------------------------------------------------------------------- '/

' The caller must hold pBt->mutex while changing MemPage state or using its
' page data. The B-tree layer owns this lock; the pager only serializes cache
' access and does not protect the decoded page fields.

Private Function btreeDecodeFlags(ByVal pPage As MemPage Ptr, ByVal flags As UByte) As SQLITE_C_INT
    If pPage = 0 OrElse pPage->pBt = 0 Then Return SQLITE_MISUSE
    Dim pBt As BtShared Ptr = pPage->pBt
    pPage->max1bytePayload = pBt->max1bytePayload
    If flags >= (PTF_ZERODATA Or PTF_LEAF) Then
        pPage->childPtrSize = 0
        pPage->leaf = 1
        If flags = (PTF_LEAFDATA Or PTF_INTKEY Or PTF_LEAF) Then
            pPage->intKeyLeaf = 1
            pPage->xCellSize = CPtr(BtreeCellSizeProc, @cellSizePtrTableLeaf)
            pPage->xParseCell = CPtr(BtreeCellParseProc, @btreeParseCellPtr)
            pPage->intKey = 1
            pPage->maxLocal = pBt->maxLeaf
            pPage->minLocal = pBt->minLeaf
        ElseIf flags = (PTF_ZERODATA Or PTF_LEAF) Then
            pPage->intKey = 0
            pPage->intKeyLeaf = 0
            pPage->xCellSize = CPtr(BtreeCellSizeProc, @cellSizePtrIdxLeaf)
            pPage->xParseCell = CPtr(BtreeCellParseProc, @btreeParseCellPtrIndex)
            pPage->maxLocal = pBt->maxLocal
            pPage->minLocal = pBt->minLocal
        Else
            Return SQLITE_CORRUPT
        End If
    Else
        pPage->childPtrSize = 4
        pPage->leaf = 0
        If flags = PTF_ZERODATA Then
            pPage->intKey = 0
            pPage->intKeyLeaf = 0
            pPage->xCellSize = CPtr(BtreeCellSizeProc, @cellSizePtr)
            pPage->xParseCell = CPtr(BtreeCellParseProc, @btreeParseCellPtrIndex)
            pPage->maxLocal = pBt->maxLocal
            pPage->minLocal = pBt->minLocal
        ElseIf flags = (PTF_LEAFDATA Or PTF_INTKEY) Then
            pPage->intKey = 1
            pPage->intKeyLeaf = 0
            pPage->xCellSize = CPtr(BtreeCellSizeProc, @cellSizePtrNoPayload)
            pPage->xParseCell = CPtr(BtreeCellParseProc, @btreeParseCellPtrNoPayload)
            pPage->maxLocal = pBt->maxLeaf
            pPage->minLocal = pBt->minLeaf
        Else
            Return SQLITE_CORRUPT
        End If
    End If
    Return SQLITE_OK
End Function

Function btreePageFromDbPage CDecl Alias "btreePageFromDbPage" ( _
    ByVal pDbPage As PgHdr Ptr, _
    ByVal pageNumber As u32, _
    ByVal pBt As BtShared Ptr _
) As MemPage Ptr

    If pDbPage = 0 OrElse pBt = 0 OrElse pageNumber = 0 Then Return 0
    Dim pPage As MemPage Ptr = CPtr(MemPage Ptr, sqlite3PagerGetExtra(pDbPage))
    If pPage = 0 Then Return 0
    If pPage->pgno <> pageNumber OrElse pPage->pBt <> pBt Then
        pPage->isInit = 0
        pPage->aData = CPtr(UByte Ptr, sqlite3PagerGetData(pDbPage))
        pPage->pDbPage = pDbPage
        pPage->pBt = pBt
        pPage->pgno = pageNumber
        pPage->hdrOffset = IIf(pageNumber = 1, 100, 0)
    End If
    Return pPage
End Function

Private Function btreeGetPage CDecl Alias "btreeGetPage" ( _
    ByVal pBt As BtShared Ptr, _
    ByVal pageNumber As u32, _
    ByVal ppPage As MemPage Ptr Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT

    If ppPage = 0 Then Return SQLITE_MISUSE
    ppPage[0] = 0
    If pBt = 0 OrElse pBt->pPager = 0 OrElse pageNumber = 0 Then Return SQLITE_MISUSE
    Dim pDbPage As PgHdr Ptr = 0
    Dim rc As SQLITE_C_INT = sqlite3PagerGet(pBt->pPager, pageNumber, @pDbPage, flags)
    If rc <> SQLITE_OK Then Return rc
    ppPage[0] = btreePageFromDbPage(pDbPage, pageNumber, pBt)
    If ppPage[0] = 0 Then
        sqlite3PagerUnrefNotNull(pDbPage)
        Return SQLITE_CORRUPT
    End If
    Return SQLITE_OK
End Function

Private Function btreePageLookup CDecl Alias "btreePageLookup" ( _
    ByVal pBt As BtShared Ptr, _
    ByVal pageNumber As u32 _
) As MemPage Ptr
    ' This cache-only path avoids a file read when the caller does not need page contents.
    If pBt = 0 OrElse pBt->pPager = 0 OrElse pageNumber = 0 Then Return 0
    Dim pDbPage As PgHdr Ptr = sqlite3PagerLookup(pBt->pPager, pageNumber)
    If pDbPage = 0 Then Return 0
    Dim pPage As MemPage Ptr = btreePageFromDbPage(pDbPage, pageNumber, pBt)
    If pPage = 0 Then sqlite3PagerUnrefNotNull(pDbPage)
    Return pPage
End Function

Private Function btreeInitPageCore( _
    ByVal pPage As MemPage Ptr, _
    ByVal validateCellLayout As SQLITE_C_INT _
) As SQLITE_C_INT
    If pPage = 0 OrElse pPage->pBt = 0 OrElse pPage->aData = 0 OrElse pPage->pDbPage = 0 Then Return SQLITE_MISUSE
    If pPage->isInit <> 0 Then Return SQLITE_OK
    Dim pBt As BtShared Ptr = pPage->pBt
    If pBt->pageSize < 512 OrElse pBt->pageSize > SQLITE_MAX_PAGE_SIZE OrElse _
       (pBt->pageSize And (pBt->pageSize - 1)) <> 0 OrElse _
       pBt->usableSize < 480 OrElse pBt->usableSize > pBt->pageSize OrElse _
       pPage->hdrOffset <> IIf(pPage->pgno = 1, 100, 0) Then Return SQLITE_CORRUPT
    If pPage->hdrOffset + 8 > pBt->usableSize Then Return SQLITE_CORRUPT

    Dim pHeader As UByte Ptr = pPage->aData + pPage->hdrOffset
    Dim rc As SQLITE_C_INT = btreeDecodeFlags(pPage, pHeader[0])
    If rc <> SQLITE_OK Then Return rc
    If pPage->hdrOffset + 8 + pPage->childPtrSize > pBt->usableSize Then Return SQLITE_CORRUPT

    pPage->maskPage = CUShort(pBt->pageSize - 1)
    pPage->nOverflow = 0
    For iOverflow As SQLITE_C_INT = 0 To 3
        pPage->aiOvflSize(iOverflow) = 0
    Next
    pPage->cellOffset = CUShort(pPage->hdrOffset + 8 + pPage->childPtrSize)
    pPage->aCellIdx = pPage->aData + pPage->cellOffset
    pPage->aDataEnd = pPage->aData + pBt->pageSize
    pPage->aDataOfst = pPage->aData + pPage->childPtrSize
    pPage->nCell = btreeGetU16(pHeader + 3)

    Dim maxCells As u32 = (pBt->usableSize - 8) \ 6
    If pPage->nCell > maxCells Then Return SQLITE_CORRUPT
    pPage->nFree = -1
    If validateCellLayout <> 0 Then
        Dim pointerBytes As u32 = CULng(pPage->nCell) * 2
        Dim contentIndexEnd As u32 = CULng(pPage->cellOffset) + pointerBytes
        If contentIndexEnd > pBt->usableSize Then Return SQLITE_CORRUPT

        Dim contentOffset As u32 = btreeGetU16NotZero(pHeader + 5)
        If contentOffset > pBt->usableSize OrElse _
           contentOffset < contentIndexEnd Then Return SQLITE_CORRUPT
        If pPage->nCell = 0 AndAlso _
           contentOffset <> pBt->usableSize Then Return SQLITE_CORRUPT

        For iCell As Long = 0 To CLng(pPage->nCell) - 1
            Dim pCellIndex As Const UByte Ptr = _
                CPtr(Const UByte Ptr, pPage->aCellIdx) + (iCell * 2)
            Dim cellOffset As u32 = btreeGetU16(pCellIndex) And pPage->maskPage
            If cellOffset < contentOffset OrElse _
               cellOffset >= pBt->usableSize Then Return SQLITE_CORRUPT
            Dim xCellSize As BtreeCellSizeProc = _
                CPtr(BtreeCellSizeProc, pPage->xCellSize)
            If xCellSize = 0 Then Return SQLITE_CORRUPT
            Dim cellSize As u16 = xCellSize(pPage, pPage->aData + cellOffset)
            If cellSize = 0 OrElse _
               CULng(cellSize) > pBt->usableSize - cellOffset Then _
                Return SQLITE_CORRUPT
        Next
    End If
    pPage->isInit = 1
    Return SQLITE_OK
End Function

Function sqlite3BtreeInitPage CDecl Alias "sqlite3BtreeInitPage" ( _
    ByVal pPage As MemPage Ptr _
) As SQLITE_C_INT Export
    Return btreeInitPageCore(pPage, 1)
End Function

Function sqlite3BtreeInitPageForIntegrity CDecl _
    Alias "sqlite3BtreeInitPageForIntegrity" ( _
    ByVal pPage As MemPage Ptr _
) As SQLITE_C_INT Export
    ' Let the integrity walk report cell-layout errors instead of aborting
    ' page initialization before it can produce diagnostic rows.
    Return btreeInitPageCore(pPage, 0)
End Function

' C's private helper and public entry point share the same guarded page setup.
Function btreeInitPage(ByVal pPage As MemPage Ptr) As SQLITE_C_INT
    Return sqlite3BtreeInitPage(pPage)
End Function

Function sqlite3BtreeComputeFreeSpace CDecl Alias "sqlite3BtreeComputeFreeSpace" ( _
    ByVal pPage As MemPage Ptr _
) As SQLITE_C_INT Export

    If pPage = 0 OrElse pPage->pBt = 0 OrElse pPage->aData = 0 OrElse pPage->isInit = 0 Then Return SQLITE_MISUSE
    If pPage->nFree >= 0 Then Return SQLITE_OK
    Dim usableSize As Long = CLng(pPage->pBt->usableSize)
    Dim headerOffset As Long = pPage->hdrOffset
    Dim pPageData As UByte Ptr = pPage->aData
    Dim top As Long = CLng(btreeGetU16NotZero(pPageData + headerOffset + 5))
    Dim firstCellByte As Long = headerOffset + 8 + pPage->childPtrSize + 2 * pPage->nCell
    If top < firstCellByte OrElse top > usableSize Then Return SQLITE_CORRUPT

    Dim freeBytes As Long = top + pPageData[headerOffset + 7]
    Dim freeBlock As Long = btreeGetU16(pPageData + headerOffset + 1)
    If freeBlock <> 0 AndAlso freeBlock < top Then Return SQLITE_CORRUPT
    Dim nBlock As Long = 0
    Dim lastBlock As Long = 0
    Dim blockSize As Long = 0
    Dim nextBlock As Long = freeBlock

    While freeBlock <> 0
        nBlock += 1
        If nBlock > usableSize \ 4 OrElse freeBlock > usableSize - 4 Then Return SQLITE_CORRUPT
        nextBlock = btreeGetU16(pPageData + freeBlock)
        blockSize = btreeGetU16(pPageData + freeBlock + 2)
        If blockSize < 4 OrElse freeBlock + blockSize > usableSize Then Return SQLITE_CORRUPT
        If lastBlock <> 0 AndAlso lastBlock >= freeBlock Then Return SQLITE_CORRUPT
        freeBytes += blockSize
        If freeBytes > usableSize Then Return SQLITE_CORRUPT
        If nextBlock < freeBlock + blockSize + 4 Then
            If nextBlock <> 0 Then Return SQLITE_CORRUPT
            Exit While
        End If
        lastBlock = freeBlock
        freeBlock = nextBlock
    Wend

    If freeBlock = 0 Then
        blockSize = 0
    ElseIf nextBlock <> 0 Then
        Return SQLITE_CORRUPT
    End If
    If nextBlock <> 0 OrElse freeBlock + blockSize > usableSize Then Return SQLITE_CORRUPT
    If freeBytes < firstCellByte Then Return SQLITE_CORRUPT
    pPage->nFree = freeBytes - firstCellByte
    Return SQLITE_OK
End Function

Private Function btreePageFindSlot( _
    ByVal pPage As MemPage Ptr, _
    ByVal byteCount As Long, _
    ByVal pResultCode As SQLITE_C_INT Ptr _
) As UByte Ptr

    If pPage = 0 OrElse pPage->pBt = 0 OrElse pResultCode = 0 OrElse byteCount < 0 Then Return 0
    Dim headerOffset As Long = pPage->hdrOffset
    Dim pData As UByte Ptr = pPage->aData
    Dim pointerOffset As Long = headerOffset + 1
    Dim freeBlock As Long = btreeGetU16(pData + pointerOffset)
    Dim maximumStart As Long = CLng(pPage->pBt->usableSize) - byteCount
    Dim nStep As Long = 0
    If freeBlock = 0 Then Return 0

    While freeBlock <= maximumStart
        nStep += 1
        If nStep > pPage->pBt->usableSize \ 4 OrElse freeBlock > pPage->pBt->usableSize - 4 Then
            pResultCode[0] = SQLITE_CORRUPT
            Return 0
        End If
        Dim freeSize As Long = btreeGetU16(pData + freeBlock + 2)
        If freeSize < 4 OrElse freeBlock + freeSize > pPage->pBt->usableSize Then
            pResultCode[0] = SQLITE_CORRUPT
            Return 0
        End If
        Dim excess As Long = freeSize - byteCount
        If excess >= 0 Then
            If excess < 4 Then
                If pData[headerOffset + 7] > 57 Then Return 0
                Dim pNextLink As Const UByte Ptr = pData + freeBlock
                pData[pointerOffset] = pNextLink[0]
                pData[pointerOffset + 1] = pNextLink[1]
                pData[headerOffset + 7] += CByte(excess)
                Return pData + freeBlock
            End If
            If excess + freeBlock > maximumStart Then
                pResultCode[0] = SQLITE_CORRUPT
                Return 0
            End If
            btreeWriteU16(pData + freeBlock + 2, CUShort(excess))
            Return pData + freeBlock + excess
        End If

        pointerOffset = freeBlock
        Dim nextBlock As Long = btreeGetU16(pData + freeBlock)
        If nextBlock <= pointerOffset Then
            If nextBlock <> 0 Then pResultCode[0] = SQLITE_CORRUPT
            Return 0
        End If
        freeBlock = nextBlock
    Wend

    If freeBlock > maximumStart + byteCount - 4 Then pResultCode[0] = SQLITE_CORRUPT
    Return 0
End Function

Private Function btreeDefragmentPage(ByVal pPage As MemPage Ptr) As SQLITE_C_INT
    If pPage = 0 OrElse pPage->pBt = 0 OrElse pPage->pDbPage = 0 OrElse pPage->isInit = 0 Then Return SQLITE_MISUSE
    If pPage->nOverflow <> 0 OrElse sqlite3PagerIswriteable(pPage->pDbPage) = 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = sqlite3BtreeComputeFreeSpace(pPage)
    If rc <> SQLITE_OK Then Return rc
    Dim pData As UByte Ptr = pPage->aData
    Dim pTemp As UByte Ptr = CPtr(UByte Ptr, sqlite3PagerTempSpace(pPage->pBt->pPager))
    Dim usableSize As Long = CLng(pPage->pBt->usableSize)
    If pTemp = 0 OrElse usableSize <= 0 Then Return SQLITE_NOMEM
    btreeSystemMemcpy(pTemp, pData, CULngInt(usableSize))

    Dim firstCellByte As Long = pPage->cellOffset + 2 * pPage->nCell
    Dim oldContentStart As Long = CLng(btreeGetU16NotZero(pTemp + pPage->hdrOffset + 5))
    Dim packedTop As Long = usableSize
    pPage->aData = pTemp
    Dim pageRc As SQLITE_C_INT = SQLITE_OK
    For iCell As Long = 0 To CLng(pPage->nCell) - 1
        Dim pCellIndex As UByte Ptr = pData + pPage->cellOffset + 2 * iCell
        Dim oldCellOffset As Long = btreeGetU16(pTemp + pPage->cellOffset + 2 * iCell)
        If oldCellOffset < firstCellByte OrElse oldCellOffset > usableSize - 4 Then
            pageRc = SQLITE_CORRUPT
            Exit For
        End If
        Dim cellSize As u16 = sqlite3BtreeCellSize(pPage, pTemp + oldCellOffset)
        If cellSize = 0 OrElse oldCellOffset + cellSize > usableSize Then
            pageRc = SQLITE_CORRUPT
            Exit For
        End If
        packedTop -= cellSize
        If packedTop < oldContentStart OrElse packedTop < firstCellByte Then
            pageRc = SQLITE_CORRUPT
            Exit For
        End If
        btreeWriteU16(pCellIndex, CUShort(packedTop))
        btreeSystemMemcpy(pData + packedTop, pTemp + oldCellOffset, cellSize)
    Next
    pPage->aData = pData
    If pageRc <> SQLITE_OK Then Return pageRc

    If packedTop - firstCellByte <> pPage->nFree Then Return SQLITE_CORRUPT
    pData[pPage->hdrOffset + 7] = 0
    btreeWriteU16(pData + pPage->hdrOffset + 5, CUShort(packedTop And &HFFFF))
    If packedTop = 65536 Then
        pData[pPage->hdrOffset + 5] = 0
        pData[pPage->hdrOffset + 6] = 0
    End If
    pData[pPage->hdrOffset + 1] = 0
    pData[pPage->hdrOffset + 2] = 0
    For iByte As Long = firstCellByte To packedTop - 1
        pData[iByte] = 0
    Next
    Return SQLITE_OK
End Function

Private Function btreeAllocateSpace( _
    ByVal pPage As MemPage Ptr, _
    ByVal byteCount As SQLITE_C_INT, _
    ByVal pCellOffset As SQLITE_C_INT Ptr _
) As SQLITE_C_INT

    If pPage = 0 OrElse pPage->pBt = 0 OrElse pPage->pDbPage = 0 OrElse pCellOffset = 0 OrElse byteCount < 0 Then Return SQLITE_MISUSE
    If sqlite3PagerIswriteable(pPage->pDbPage) = 0 Then Return SQLITE_READONLY
    If pPage->nOverflow <> 0 Then Return SQLITE_MISUSE
    If pPage->nFree < 0 Then
        Dim rcCompute As SQLITE_C_INT = sqlite3BtreeComputeFreeSpace(pPage)
        If rcCompute <> SQLITE_OK Then Return rcCompute
    End If
    If pPage->nFree < byteCount + 2 Then Return SQLITE_FULL
    If byteCount >= pPage->pBt->usableSize - 8 Then Return SQLITE_FULL

    Dim headerOffset As Long = pPage->hdrOffset
    Dim pData As UByte Ptr = pPage->aData
    Dim gap As Long = pPage->cellOffset + 2 * pPage->nCell
    Dim top As Long = btreeGetU16(pData + headerOffset + 5)
    If gap > top Then
        If top = 0 AndAlso pPage->pBt->usableSize = 65536 Then
            top = 65536
        Else
            Return SQLITE_CORRUPT
        End If
    ElseIf top > pPage->pBt->usableSize Then
        Return SQLITE_CORRUPT
    End If

    If (pData[headerOffset + 1] <> 0 OrElse pData[headerOffset + 2] <> 0) AndAlso gap + 2 <= top Then
        Dim rcSlot As SQLITE_C_INT = SQLITE_OK
        Dim pSlot As UByte Ptr = btreePageFindSlot(pPage, byteCount, @rcSlot)
        If pSlot <> 0 Then
            Dim slotOffset As Long = CLng(pSlot - pData)
            If slotOffset <= gap OrElse slotOffset + byteCount > pPage->pBt->usableSize Then Return SQLITE_CORRUPT
            pCellOffset[0] = slotOffset
            Return SQLITE_OK
        End If
        If rcSlot <> SQLITE_OK Then Return rcSlot
    End If

    If gap + 2 + byteCount > top Then
        Dim rcDefrag As SQLITE_C_INT = btreeDefragmentPage(pPage)
        If rcDefrag <> SQLITE_OK Then Return rcDefrag
        top = CLng(btreeGetU16NotZero(pData + headerOffset + 5))
        If gap + 2 + byteCount > top Then Return SQLITE_CORRUPT
    End If

    top -= byteCount
    If top < 0 OrElse top + byteCount > pPage->pBt->usableSize Then Return SQLITE_CORRUPT
    btreeWriteU16(pData + headerOffset + 5, CUShort(top And &HFFFF))
    If top = 65536 Then
        pData[headerOffset + 5] = 0
        pData[headerOffset + 6] = 0
    End If
    pCellOffset[0] = top
    Return SQLITE_OK
End Function

/' ------------------------------------------------------------------------- '/
/' Leaf-cell construction and insertion '/
/' ------------------------------------------------------------------------- '/

Private Function btreeRowidVarintLen(ByVal rowidBits As sqlite3_uint64) As SQLITE_C_INT
    ' SQLite's ninth varint byte carries all eight remaining bits.
    If (rowidBits And &HFF00000000000000ULL) <> 0 Then Return 9
    Return sqlite3VarintLen(rowidBits)
End Function

Private Function btreeBuildCell( _
    ByVal pPage As MemPage Ptr, _
    ByVal pPayload As SqliteBtreePayload Ptr, _
    ByVal pCell As UByte Ptr, _
    ByVal cellCapacity As SQLITE_C_INT, _
    ByVal pCellSize As SQLITE_C_INT Ptr _
) As SQLITE_C_INT

    If pCellSize <> 0 Then pCellSize[0] = 0
    If pPage = 0 OrElse pPayload = 0 OrElse pCell = 0 OrElse pCellSize = 0 OrElse _
       pPage->pBt = 0 OrElse pPage->isInit = 0 OrElse cellCapacity < 0 OrElse _
       (pPage->leaf <> 0 AndAlso pPage->childPtrSize <> 0) OrElse _
       (pPage->leaf = 0 AndAlso pPage->childPtrSize <> 4) Then Return SQLITE_MISUSE

    Dim pPayloadFields As SqliteBtreePayload Ptr = pPayload

    Dim payloadSize As sqlite3_uint64 = 0
    Dim sourceSize As sqlite3_uint64 = 0
    Dim pSource As Const UByte Ptr = 0
    If pPage->intKey <> 0 Then
        If pPage->leaf = 0 OrElse pPage->intKeyLeaf = 0 OrElse _
           pPayloadFields->nData < 0 OrElse pPayloadFields->nZero < 0 Then Return SQLITE_MISUSE
        If pPayloadFields->nData > 0 AndAlso pPayloadFields->pData = 0 Then Return SQLITE_MISUSE
        sourceSize = CULngInt(pPayloadFields->nData)
        payloadSize = sourceSize + CULngInt(pPayloadFields->nZero)
        pSource = CPtr(Const UByte Ptr, pPayloadFields->pData)
    Else
        If pPage->intKeyLeaf <> 0 OrElse pPayloadFields->nKey < 0 OrElse _
           pPayloadFields->nKey > &H7FFFFFFF OrElse pPayloadFields->pKey = 0 Then Return SQLITE_MISUSE
        payloadSize = CULngInt(pPayloadFields->nKey)
        sourceSize = payloadSize
        pSource = CPtr(Const UByte Ptr, pPayloadFields->pKey)
    End If

    If payloadSize > &H7FFFFFFF OrElse pPage->maxLocal = 0 OrElse _
       pPage->maxLocal > pPage->pBt->usableSize Then Return SQLITE_TOOBIG

    Dim localPayload As sqlite3_uint64 = payloadSize
    If localPayload > pPage->maxLocal Then
        If pPage->minLocal = 0 OrElse pPage->pBt->usableSize <= 4 Then Return SQLITE_CORRUPT
        Dim overflowPagePayload As sqlite3_uint64 = pPage->pBt->usableSize - 4
        localPayload = pPage->minLocal + ((payloadSize - pPage->minLocal) Mod overflowPagePayload)
        If localPayload > pPage->maxLocal Then localPayload = pPage->minLocal
    End If

    Dim payloadHeaderSize As SQLITE_C_INT = sqlite3VarintLen(payloadSize)
    Dim keyHeaderSize As SQLITE_C_INT = 0
    Dim keyValue As sqlite3_uint64 = 0
    If pPage->intKey <> 0 Then
        keyValue = CULngInt(pPayloadFields->nKey)
        keyHeaderSize = btreeRowidVarintLen(keyValue)
    End If
    Dim headerSize As Long = pPage->childPtrSize + payloadHeaderSize + keyHeaderSize
    Dim cellSize As Long = headerSize + CLng(localPayload)
    If localPayload < payloadSize Then cellSize += 4
    If cellSize < 4 Then cellSize = 4
    If cellSize > cellCapacity OrElse cellSize > 65535 Then Return SQLITE_TOOBIG

    If pPage->childPtrSize = 4 Then btreeWriteU32(pCell, 0)
    Dim written As SQLITE_C_INT = sqlite3PutVarint(pCell + pPage->childPtrSize, payloadSize)
    If written <> payloadHeaderSize Then Return SQLITE_CORRUPT
    Dim payloadOffset As Long = pPage->childPtrSize + written
    If pPage->intKey <> 0 Then
        written = sqlite3PutVarint(pCell + payloadOffset, keyValue)
        If written <> keyHeaderSize Then Return SQLITE_CORRUPT
        payloadOffset += written
    End If
    If payloadOffset <> headerSize Then Return SQLITE_CORRUPT

    Dim localSourceSize As sqlite3_uint64 = sourceSize
    If localSourceSize > localPayload Then localSourceSize = localPayload
    If localSourceSize > 0 Then
        btreeSystemMemcpy(pCell + payloadOffset, pSource, CULngInt(localSourceSize))
    End If
    For iByte As Long = CLng(localSourceSize) To CLng(localPayload) - 1
        pCell[payloadOffset + iByte] = 0
    Next
    For iByte As Long = headerSize + CLng(localPayload) To cellSize - 1
        pCell[iByte] = 0
    Next

    If localPayload < payloadSize Then
        Dim pPrior As UByte Ptr = pCell + headerSize + CLng(localPayload)
        Dim pToRelease As MemPage Ptr = 0
        Dim remainingPayload As sqlite3_uint64 = payloadSize - localPayload
        Dim remainingSource As sqlite3_uint64 = sourceSize - localSourceSize
        Dim sourceOffset As sqlite3_uint64 = localSourceSize
        Dim overflowCapacity As u32 = pPage->pBt->usableSize - 4
        While remainingPayload > 0
            Dim pOverflow As MemPage Ptr = 0
            Dim overflowPageNumber As u32 = 0
            Dim overflowMapType As u8 = PTRMAP_OVERFLOW1
            Dim overflowParent As u32 = pPage->pgno
            If pToRelease <> 0 Then
                overflowMapType = PTRMAP_OVERFLOW2
                overflowParent = pToRelease->pgno
            End If
            Dim nearbyPage As u32 = 0
            If pToRelease <> 0 Then nearbyPage = pToRelease->pgno
            Dim rcAllocate As SQLITE_C_INT = btreeAllocatePageMode( _
                pPage->pBt, @pOverflow, @overflowPageNumber, overflowMapType, _
                overflowParent, nearbyPage, BTALLOC_ANY)
            If rcAllocate <> SQLITE_OK Then
                sqlite3BtreeReleasePage(pToRelease)
                Return rcAllocate
            End If
            If pOverflow = 0 OrElse pOverflow->aData = 0 Then
                If pOverflow <> 0 Then sqlite3BtreeReleasePage(pOverflow)
                sqlite3BtreeReleasePage(pToRelease)
                Return SQLITE_CORRUPT
            End If

            btreeWriteU32(pPrior, overflowPageNumber)
            btreeWriteU32(pOverflow->aData, 0)
            sqlite3BtreeReleasePage(pToRelease)
            pToRelease = pOverflow
            pPrior = pOverflow->aData

            Dim pagePayloadSize As sqlite3_uint64 = remainingPayload
            If pagePayloadSize > overflowCapacity Then pagePayloadSize = overflowCapacity
            Dim pageSourceSize As sqlite3_uint64 = remainingSource
            If pageSourceSize > pagePayloadSize Then pageSourceSize = pagePayloadSize
            If pageSourceSize > 0 Then
                btreeSystemMemcpy(pOverflow->aData + 4, pSource + sourceOffset, CULngInt(pageSourceSize))
            End If
            For iByte As Long = CLng(pageSourceSize) To CLng(pagePayloadSize) - 1
                pOverflow->aData[4 + iByte] = 0
            Next

            sourceOffset += pageSourceSize
            remainingSource -= pageSourceSize
            remainingPayload -= pagePayloadSize
        Wend
        sqlite3BtreeReleasePage(pToRelease)
    End If

    pCellSize[0] = cellSize
    Return SQLITE_OK
End Function

Private Function btreeReadCellVarintBounded( _
    ByVal pInput As Const UByte Ptr, _
    ByVal availableBytes As SQLITE_C_INT, _
    ByVal pValue As sqlite3_uint64 Ptr, _
    ByVal pLength As SQLITE_C_INT Ptr _
) As SQLITE_C_INT

    If pInput = 0 OrElse pValue = 0 OrElse pLength = 0 OrElse availableBytes <= 0 Then Return SQLITE_CORRUPT
    Dim value As sqlite3_uint64 = 0
    For iByte As SQLITE_C_INT = 0 To 8
        If iByte >= availableBytes Then Return SQLITE_CORRUPT
        Dim byteValue As UByte = pInput[iByte]
        If iByte = 8 Then
            pValue[0] = (value Shl 8) Or byteValue
            pLength[0] = 9
            Return SQLITE_OK
        End If
        value = (value Shl 7) Or (byteValue And &H7F)
        If (byteValue And &H80) = 0 Then
            pValue[0] = value
            pLength[0] = iByte + 1
            Return SQLITE_OK
        End If
    Next
    Return SQLITE_CORRUPT
End Function

Private Function btreeCellSizeFromBuffer( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As Const UByte Ptr, _
    ByVal availableBytes As SQLITE_C_INT _
) As u16
    If pPage = 0 OrElse pPage->pBt = 0 OrElse pCell = 0 OrElse _
       pPage->childPtrSize <> 4 OrElse availableBytes < 4 Then Return 0

    Dim expectedSize As sqlite3_uint64
    If pPage->intKey <> 0 Then
        Dim rowIdValue As sqlite3_uint64 = 0
        Dim rowIdLength As SQLITE_C_INT = 0
        If btreeReadCellVarintBounded( _
            pCell + 4, availableBytes - 4, @rowIdValue, @rowIdLength) <> SQLITE_OK Then _
            Return 0
        expectedSize = CULngInt(4 + rowIdLength)
    Else
        Dim payloadSize As sqlite3_uint64 = 0
        Dim payloadLength As SQLITE_C_INT = 0
        If btreeReadCellVarintBounded( _
            pCell + 4, availableBytes - 4, @payloadSize, @payloadLength) <> SQLITE_OK OrElse _
           payloadSize > &H7FFFFFFF Then Return 0
        Dim localPayload As u16 = CUShort( _
            btreePayloadToLocal(pPage, CLngInt(payloadSize)))
        expectedSize = CULngInt(4 + payloadLength + localPayload)
        If payloadSize > localPayload Then expectedSize += 4
    End If

    If expectedSize < 4 Then expectedSize = 4
    If expectedSize > CULngInt(availableBytes) OrElse _
       expectedSize > CULngInt(pPage->pBt->usableSize) OrElse _
       expectedSize > 65535 Then Return 0
    Return CUShort(expectedSize)
End Function

Private Function btreeValidateCellBuffer( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As Const UByte Ptr, _
    ByVal cellSize As SQLITE_C_INT _
) As SQLITE_C_INT

    If pPage = 0 OrElse pPage->pBt = 0 OrElse pCell = 0 OrElse _
       pPage->childPtrSize <> 4 OrElse pPage->leaf <> 0 OrElse cellSize < 4 Then Return SQLITE_MISUSE
    Dim expectedSize As sqlite3_uint64 = 0
    Dim hasOverflow As SQLITE_C_INT = 0
    If pPage->intKey <> 0 Then
        Dim rowIdValue As sqlite3_uint64 = 0
        Dim rowIdLength As SQLITE_C_INT = 0
        Dim rc As SQLITE_C_INT = btreeReadCellVarintBounded(pCell + 4, cellSize - 4, @rowIdValue, @rowIdLength)
        If rc <> SQLITE_OK Then Return SQLITE_CORRUPT
        expectedSize = 4 + rowIdLength
    Else
        Dim payloadSize As sqlite3_uint64 = 0
        Dim payloadLength As SQLITE_C_INT = 0
        Dim rc As SQLITE_C_INT = btreeReadCellVarintBounded(pCell + 4, cellSize - 4, @payloadSize, @payloadLength)
        If rc <> SQLITE_OK OrElse payloadSize > &HFFFFFFFF Then Return SQLITE_CORRUPT
        Dim localPayload As u16 = CUShort(btreePayloadToLocal(pPage, CLngInt(payloadSize)))
        expectedSize = 4 + payloadLength + localPayload
        hasOverflow = IIf(payloadSize > localPayload, 1, 0)
        If hasOverflow <> 0 Then expectedSize += 4
    End If
    If expectedSize < 4 Then expectedSize = 4
    If expectedSize <> cellSize OrElse expectedSize > pPage->pBt->usableSize Then Return SQLITE_CORRUPT
    If pPage->intKey = 0 AndAlso hasOverflow <> 0 Then
        Dim overflowPage As u32 = btreeReadU32(pCell + cellSize - 4)
        If overflowPage < 2 OrElse overflowPage > pPage->pBt->nPage Then Return SQLITE_CORRUPT
    End If
    Return SQLITE_OK
End Function

Private Function btreeInsertCellFast( _
    ByVal pPage As MemPage Ptr, _
    ByVal cellIndex As SQLITE_C_INT, _
    ByVal pCell As Const UByte Ptr, _
    ByVal cellSize As SQLITE_C_INT _
) As SQLITE_C_INT

    If pPage = 0 OrElse pCell = 0 OrElse pPage->pBt = 0 OrElse _
       pPage->pDbPage = 0 OrElse pPage->isInit = 0 OrElse pPage->leaf = 0 OrElse _
       pPage->nOverflow > 3 OrElse cellIndex < 0 OrElse _
       cellIndex > pPage->nCell + pPage->nOverflow OrElse _
       cellSize < 4 OrElse cellSize > 65535 Then Return SQLITE_MISUSE
    If pPage->nFree < 0 Then
        Dim rcFree As SQLITE_C_INT = sqlite3BtreeComputeFreeSpace(pPage)
        If rcFree <> SQLITE_OK Then Return rcFree
    End If
    If CULng(pPage->nCell) + pPage->nOverflow >= _
       (pPage->pBt->usableSize - pPage->cellOffset) \ 2 Then Return SQLITE_FULL

    Dim payloadSize As sqlite3_uint64 = 0
    Dim varintBytes As SQLITE_C_INT = 0
    Dim rc As SQLITE_C_INT = btreeReadCellVarintBounded(pCell, cellSize, @payloadSize, @varintBytes)
    If rc <> SQLITE_OK OrElse payloadSize > &H7FFFFFFF OrElse pPage->maxLocal = 0 Then Return SQLITE_CORRUPT
    Dim headerBytes As Long = varintBytes
    If pPage->intKey <> 0 Then
        Dim ignoredRowId As sqlite3_uint64 = 0
        rc = btreeReadCellVarintBounded(pCell + headerBytes, cellSize - headerBytes, @ignoredRowId, @varintBytes)
        If rc <> SQLITE_OK Then Return SQLITE_CORRUPT
        headerBytes += varintBytes
    End If
    Dim localPayload As sqlite3_uint64 = payloadSize
    If localPayload > pPage->maxLocal Then
        If pPage->minLocal = 0 OrElse pPage->pBt->usableSize <= 4 Then Return SQLITE_CORRUPT
        Dim overflowCapacity As sqlite3_uint64 = pPage->pBt->usableSize - 4
        localPayload = pPage->minLocal + ((payloadSize - pPage->minLocal) Mod overflowCapacity)
        If localPayload > pPage->maxLocal Then localPayload = pPage->minLocal
    End If
    Dim expectedSize As sqlite3_uint64 = CULngInt(headerBytes) + localPayload
    If localPayload < payloadSize Then expectedSize += 4
    If expectedSize < 4 Then expectedSize = 4
    If expectedSize <> cellSize Then Return SQLITE_CORRUPT
    If localPayload < payloadSize Then
        Dim overflowPageNumber As u32 = btreeReadU32(pCell + cellSize - 4)
        If overflowPageNumber < 2 OrElse overflowPageNumber > pPage->pBt->nPage Then Return SQLITE_CORRUPT
    End If

    If pPage->nOverflow <> 0 OrElse cellSize + 2 > pPage->nFree Then
        Dim overflowIndex As Long = pPage->nOverflow
        If overflowIndex >= 3 Then Return SQLITE_CORRUPT
        If overflowIndex > 0 Then
            Dim previousIndex As u16 = pPage->aiOvfl(overflowIndex - 1)
            If cellIndex <= previousIndex OrElse cellIndex <> previousIndex + 1 Then Return SQLITE_MISUSE
        End If
        pPage->apOvfl(overflowIndex) = CPtr(UByte Ptr, pCell)
        pPage->aiOvfl(overflowIndex) = CUShort(cellIndex)
        pPage->aiOvflSize(overflowIndex) = CUShort(cellSize)
        pPage->nOverflow += 1
        Return SQLITE_OK
    End If

    rc = sqlite3PagerWrite(pPage->pDbPage)
    If rc <> SQLITE_OK Then Return rc
    Dim cellOffset As SQLITE_C_INT = 0
    rc = btreeAllocateSpace(pPage, cellSize, @cellOffset)
    If rc <> SQLITE_OK Then Return rc

    Dim minimumCellOffset As Long = pPage->cellOffset + (2 * pPage->nCell) + 2
    If cellOffset < minimumCellOffset OrElse _
       cellOffset > pPage->pBt->usableSize OrElse _
       cellSize > pPage->pBt->usableSize - cellOffset Then Return SQLITE_CORRUPT
    pPage->nFree -= (cellSize + 2)
    btreeSystemMemcpy(pPage->aData + cellOffset, pCell, CULngInt(cellSize))
    For iCell As Long = pPage->nCell To cellIndex + 1 Step -1
        Dim pDestination As UByte Ptr = pPage->aCellIdx + (2 * iCell)
        pDestination[0] = pDestination[-2]
        pDestination[1] = pDestination[-1]
    Next
    btreeWriteU16(pPage->aCellIdx + (2 * cellIndex), CUShort(cellOffset))
    pPage->nCell += 1
    btreeWriteU16(pPage->aData + pPage->hdrOffset + 3, pPage->nCell)
#ifndef SQLITE_OMIT_AUTOVACUUM
    If pPage->pBt->autoVacuum <> 0 Then
        Dim pointerMapRc As SQLITE_C_INT = SQLITE_OK
        ptrmapPutOvflPtr(pPage, pPage, pPage->aData + cellOffset, @pointerMapRc)
        If pointerMapRc <> SQLITE_OK Then Return pointerMapRc
    End If
#endif
    Return SQLITE_OK
End Function

Private Function btreeClearCellOverflow CDecl Alias "clearCellOverflow" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As Const UByte Ptr, _
    ByVal pInfo As CellInfo Ptr _
) As SQLITE_C_INT

    ' The payload length bounds the walk. Requiring one page reference here
    ' prevents freeing a page that another cursor is still using.
    If pPage = 0 OrElse pPage->pBt = 0 OrElse pInfo = 0 OrElse pCell = 0 Then Return SQLITE_MISUSE
    If pInfo->nLocal = pInfo->nPayload Then Return SQLITE_OK
    If pInfo->nLocal > pInfo->nPayload OrElse pInfo->nSize < 4 OrElse _
       pPage->pBt->nPage < 2 OrElse pPage->pBt->usableSize <= 4 OrElse _
       btreePageHasRange(pPage, pCell, pInfo->nSize) = 0 Then Return SQLITE_CORRUPT

    Dim overflowCapacity As u32 = pPage->pBt->usableSize - 4
    Dim overflowBytes As sqlite3_uint64 = pInfo->nPayload - pInfo->nLocal
    Dim overflowPageCount As sqlite3_uint64 = (overflowBytes + overflowCapacity - 1) \ overflowCapacity
    If overflowPageCount = 0 OrElse overflowPageCount > pPage->pBt->nPage - 1 Then Return SQLITE_CORRUPT

    Dim overflowPageNumber As u32 = btreeReadU32(pCell + pInfo->nSize - 4)
    For pageIndex As sqlite3_uint64 = 0 To overflowPageCount - 1
        If overflowPageNumber < 2 OrElse overflowPageNumber > pPage->pBt->nPage Then Return SQLITE_CORRUPT
        Dim pOverflow As MemPage Ptr = 0
        Dim nextOverflowPage As u32 = 0
        If pageIndex + 1 < overflowPageCount Then
            Dim rcNext As SQLITE_C_INT = getOverflowPage(pPage->pBt, overflowPageNumber, _
                @pOverflow, @nextOverflowPage)
            If rcNext <> SQLITE_OK Then Return rcNext
        End If

        If pOverflow = 0 Then pOverflow = btreePageLookup(pPage->pBt, overflowPageNumber)
        If pOverflow <> 0 Then
            If pOverflow->aData = 0 OrElse pOverflow->pDbPage = 0 OrElse _
               pOverflow->pgno <> overflowPageNumber Then
                sqlite3BtreeReleasePage(pOverflow)
                Return SQLITE_CORRUPT
            End If
            If sqlite3PagerPageRefcount(pOverflow->pDbPage) <> 1 Then
                sqlite3BtreeReleasePage(pOverflow)
                Return SQLITE_CORRUPT
            End If
        End If

        Dim rc As SQLITE_C_INT = btreeFreePageNumber(pPage->pBt, pOverflow, overflowPageNumber)
        If pOverflow <> 0 Then sqlite3BtreeReleasePage(pOverflow)
        If rc <> SQLITE_OK Then Return rc
        overflowPageNumber = nextOverflowPage
    Next
    Return SQLITE_OK
End Function

Private Function btreeOverwriteContent( _
    ByVal pPage As MemPage Ptr, _
    ByVal pDestination As UByte Ptr, _
    ByVal pPayload As SqliteBtreePayload Ptr, _
    ByVal offset As SQLITE_C_INT, _
    ByVal amount As SQLITE_C_INT _
) As SQLITE_C_INT

    If pPage = 0 OrElse pPayload = 0 OrElse offset < 0 OrElse amount < 0 Then Return SQLITE_MISUSE
    If pPage->pBt = 0 OrElse pPage->pDbPage = 0 OrElse _
       pPayload->nData < 0 OrElse pPayload->nZero < 0 Then Return SQLITE_CORRUPT
    Dim totalPayload As sqlite3_uint64 = CULngInt(pPayload->nData) + CULngInt(pPayload->nZero)
    If totalPayload > &H7FFFFFFF OrElse CULngInt(offset) > totalPayload OrElse _
       CULngInt(amount) > totalPayload - CULngInt(offset) Then Return SQLITE_CORRUPT
    If amount = 0 Then Return SQLITE_OK
    If pDestination = 0 OrElse btreePageHasRange(pPage, pDestination, amount) = 0 Then Return SQLITE_CORRUPT

    Dim sourceCount As Long = 0
    If offset < pPayload->nData Then
        sourceCount = pPayload->nData - offset
        If sourceCount > amount Then sourceCount = amount
        If pPayload->pData = 0 Then Return SQLITE_MISUSE
    End If
    Dim pSource As Const UByte Ptr = CPtr(Const UByte Ptr, pPayload->pData)
    Dim bChanged As SQLITE_C_INT = 0
    For iByte As Long = 0 To sourceCount - 1
        If pDestination[iByte] <> pSource[offset + iByte] Then
            bChanged = 1
            Exit For
        End If
    Next
    If bChanged = 0 Then
        For iByte As Long = sourceCount To amount - 1
            If pDestination[iByte] <> 0 Then
                bChanged = 1
                Exit For
            End If
        Next
    End If
    If bChanged = 0 Then Return SQLITE_OK

    Dim rc As SQLITE_C_INT = sqlite3PagerWrite(pPage->pDbPage)
    If rc <> SQLITE_OK Then Return rc
    For iByte As Long = sourceCount To amount - 1
        pDestination[iByte] = 0
    Next
    If sourceCount > 0 Then
        btreeSystemMemmove(pDestination, pSource + offset, CULngInt(sourceCount))
    End If
    Return SQLITE_OK
End Function

Private Function btreeOverwriteOverflowCell( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pPayload As SqliteBtreePayload Ptr _
) As SQLITE_C_INT

    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pCursor->pPage = 0 OrElse pPayload = 0 Then Return SQLITE_MISUSE
    Dim pPage As MemPage Ptr = pCursor->pPage
    Dim pBt As BtShared Ptr = pCursor->pBt
    Dim totalPayload As sqlite3_uint64 = 0
    If pPayload->nData < 0 OrElse pPayload->nZero < 0 Then Return SQLITE_MISUSE
    totalPayload = CULngInt(pPayload->nData) + CULngInt(pPayload->nZero)
    If totalPayload > &H7FFFFFFF OrElse totalPayload <> pCursor->info.nPayload OrElse _
       pCursor->info.nLocal >= pCursor->info.nPayload Then Return SQLITE_CORRUPT
    If pBt->usableSize <= 4 OrElse pCursor->info.nSize < 4 OrElse _
       btreePageHasRange(pPage, pCursor->info.pPayload, CULngInt(pCursor->info.nLocal) + 4) = 0 Then Return SQLITE_CORRUPT

    Dim rc As SQLITE_C_INT = btreeOverwriteContent(pPage, pCursor->info.pPayload, pPayload, 0, pCursor->info.nLocal)
    If rc <> SQLITE_OK Then Return rc

    Dim overflowCapacity As u32 = pBt->usableSize - 4
    Dim offset As u32 = pCursor->info.nLocal
    Dim pageNumber As u32 = btreeReadU32(pCursor->info.pPayload + offset)
    While CULngInt(offset) < totalPayload
        If pageNumber < 2 OrElse pageNumber > pBt->nPage Then Return SQLITE_CORRUPT
        Dim pOverflow As MemPage Ptr = 0
        rc = btreeGetPage(pBt, pageNumber, @pOverflow, 0)
        If rc <> SQLITE_OK Then Return rc
        If pOverflow = 0 OrElse pOverflow->aData = 0 OrElse pOverflow->pDbPage = 0 Then
            sqlite3BtreeReleasePage(pOverflow)
            Return SQLITE_CORRUPT
        End If
        If sqlite3PagerPageRefcount(pOverflow->pDbPage) <> 1 OrElse pOverflow->isInit <> 0 Then
            sqlite3BtreeReleasePage(pOverflow)
            Return SQLITE_CORRUPT
        End If

        Dim amount As u32 = CULng(totalPayload - offset)
        If amount > overflowCapacity Then amount = overflowCapacity
        Dim nextPage As u32 = 0
        If CULngInt(offset) + amount < totalPayload Then
            nextPage = btreeReadU32(pOverflow->aData)
            If nextPage < 2 OrElse nextPage > pBt->nPage Then
                sqlite3BtreeReleasePage(pOverflow)
                Return SQLITE_CORRUPT
            End If
        End If
        rc = btreeOverwriteContent(pOverflow, pOverflow->aData + 4, pPayload, offset, amount)
        sqlite3BtreeReleasePage(pOverflow)
        If rc <> SQLITE_OK Then Return rc
        offset += amount
        pageNumber = nextPage
    Wend
    Return SQLITE_OK
End Function

Private Function btreeOverwriteCell( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pPayload As SqliteBtreePayload Ptr _
) As SQLITE_C_INT

    If pCursor = 0 OrElse pCursor->pPage = 0 OrElse pPayload = 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = sqlite3BtreeGetCellInfo(pCursor->pPage, pCursor->ix, @pCursor->info)
    If rc <> SQLITE_OK Then Return rc
    Dim totalPayload As sqlite3_uint64 = 0
    If pCursor->pPage->intKey <> 0 Then
        If pPayload->nData < 0 OrElse pPayload->nZero < 0 Then Return SQLITE_MISUSE
        totalPayload = CULngInt(pPayload->nData) + CULngInt(pPayload->nZero)
    Else
        totalPayload = CULngInt(pPayload->nData)
    End If
    If totalPayload > &H7FFFFFFF OrElse totalPayload <> pCursor->info.nPayload Then Return SQLITE_CORRUPT
    If pCursor->info.nLocal = pCursor->info.nPayload Then
        Return btreeOverwriteContent(pCursor->pPage, pCursor->info.pPayload, pPayload, 0, pCursor->info.nLocal)
    End If
    Return btreeOverwriteOverflowCell(pCursor, pPayload)
End Function

Private Function btreeFreeSpace( _
    ByVal pPage As MemPage Ptr, _
    ByVal startOffset As SQLITE_C_INT, _
    ByVal byteCount As SQLITE_C_INT _
) As SQLITE_C_INT

    If pPage = 0 OrElse pPage->pBt = 0 OrElse pPage->pDbPage = 0 OrElse _
       startOffset < 0 OrElse byteCount < 4 Then Return SQLITE_MISUSE
    If sqlite3PagerIswriteable(pPage->pDbPage) = 0 Then Return SQLITE_READONLY
    Dim usableSize As Long = CLng(pPage->pBt->usableSize)
    Dim headerOffset As Long = pPage->hdrOffset
    Dim pData As UByte Ptr = pPage->aData
    Dim endOffset As Long = startOffset + byteCount
    If startOffset < headerOffset + 6 + pPage->childPtrSize OrElse _
       endOffset > usableSize OrElse startOffset > usableSize - 4 Then Return SQLITE_CORRUPT

    Dim pointerOffset As Long = headerOffset + 1
    Dim nextFree As Long = btreeGetU16(pData + pointerOffset)
    Dim fragmentDelta As Long = 0
    Dim insertOffset As Long = startOffset
    Dim insertSize As Long = byteCount
    Dim boundedSteps As Long = 0
    If nextFree = 0 Then
        ' The new block becomes the first freeblock.
    Else
        While nextFree < startOffset
            boundedSteps += 1
            If boundedSteps > usableSize \ 4 OrElse nextFree <= pointerOffset OrElse nextFree > usableSize - 4 Then Return SQLITE_CORRUPT
            pointerOffset = nextFree
            nextFree = btreeGetU16(pData + pointerOffset)
            If nextFree = 0 Then Exit While
        Wend
        If nextFree > usableSize - 4 Then Return SQLITE_CORRUPT

        If nextFree <> 0 AndAlso endOffset + 3 >= nextFree Then
            If endOffset > nextFree Then Return SQLITE_CORRUPT
            fragmentDelta = nextFree - endOffset
            Dim following As Long = btreeGetU16(pData + nextFree)
            Dim followingSize As Long = btreeGetU16(pData + nextFree + 2)
            If followingSize < 4 OrElse nextFree + followingSize > usableSize Then Return SQLITE_CORRUPT
            endOffset = nextFree + followingSize
            insertSize = endOffset - insertOffset
            nextFree = following
        End If

        If pointerOffset > headerOffset + 1 Then
            Dim previousSize As Long = btreeGetU16(pData + pointerOffset + 2)
            Dim previousEnd As Long = pointerOffset + previousSize
            If previousSize < 4 OrElse previousEnd > usableSize Then Return SQLITE_CORRUPT
            If previousEnd + 3 >= insertOffset Then
                If previousEnd > insertOffset Then Return SQLITE_CORRUPT
                fragmentDelta += insertOffset - previousEnd
                insertSize = endOffset - pointerOffset
                insertOffset = pointerOffset
            End If
        End If
        If fragmentDelta > pData[headerOffset + 7] Then Return SQLITE_CORRUPT
        pData[headerOffset + 7] -= CByte(fragmentDelta)
    End If

    Dim top As Long = btreeGetU16(pData + headerOffset + 5)
    If (pPage->pBt->btsFlags And BTS_FAST_SECURE) <> 0 Then
        For iByte As Long = insertOffset To endOffset - 1
            pData[iByte] = 0
        Next
    End If
    If insertOffset <= top Then
        If insertOffset < top OrElse pointerOffset <> headerOffset + 1 Then Return SQLITE_CORRUPT
        btreeWriteU16(pData + pointerOffset, CUShort(nextFree))
        btreeWriteU16(pData + headerOffset + 5, CUShort(endOffset And &HFFFF))
        If endOffset = 65536 Then
            pData[headerOffset + 5] = 0
            pData[headerOffset + 6] = 0
        End If
    Else
        btreeWriteU16(pData + pointerOffset, CUShort(insertOffset))
        btreeWriteU16(pData + insertOffset, CUShort(nextFree))
        btreeWriteU16(pData + insertOffset + 2, CUShort(insertSize))
    End If
    pPage->nFree += byteCount
    Return SQLITE_OK
End Function

Function sqlite3BtreeDropCell CDecl Alias "sqlite3BtreeDropCell" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal cellIndex As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pPage = 0 OrElse pPage->pBt = 0 OrElse pPage->pDbPage = 0 OrElse _
       pPage->isInit = 0 OrElse pPage->nOverflow > 3 OrElse _
       cellIndex < 0 OrElse cellIndex >= pPage->nCell Then Return SQLITE_MISUSE
    If pPage->nFree < 0 Then
        Dim rcFree As SQLITE_C_INT = sqlite3BtreeComputeFreeSpace(pPage)
        If rcFree <> SQLITE_OK Then Return rcFree
    End If
    Dim pCellIndex As Const UByte Ptr = CPtr(Const UByte Ptr, pPage->aCellIdx) + (cellIndex * 2)
    Dim storedOffset As u32 = btreeGetU16(pCellIndex) And pPage->maskPage
    If storedOffset >= pPage->pBt->usableSize Then Return SQLITE_CORRUPT
    Dim pCell As UByte Ptr = pPage->aData + storedOffset
    Dim cellSize As u16 = sqlite3BtreeCellSize(pPage, pCell)
    If cellSize < 4 Then Return SQLITE_CORRUPT
    Dim cellOffset As Long = CLng(pCell - pPage->aData)
    If cellOffset + cellSize > pPage->pBt->usableSize Then Return SQLITE_CORRUPT

    Dim rc As SQLITE_C_INT = sqlite3PagerWrite(pPage->pDbPage)
    If rc <> SQLITE_OK Then Return rc
    rc = btreeFreeSpace(pPage, cellOffset, cellSize)
    If rc <> SQLITE_OK Then Return rc

    pPage->nCell -= 1
    If pPage->nCell = 0 Then
        For i As Long = 1 To 4
            pPage->aData[pPage->hdrOffset + i] = 0
        Next
        pPage->aData[pPage->hdrOffset + 7] = 0
        If pPage->pBt->usableSize = 65536 Then
            pPage->aData[pPage->hdrOffset + 5] = 0
            pPage->aData[pPage->hdrOffset + 6] = 0
        Else
            btreeWriteU16(pPage->aData + pPage->hdrOffset + 5, CUShort(pPage->pBt->usableSize))
        End If
        pPage->nFree = CLng(pPage->pBt->usableSize) - pPage->hdrOffset - pPage->childPtrSize - 8
    Else
        For i As Long = cellIndex To CLng(pPage->nCell) - 1
            Dim pDestination As UByte Ptr = pPage->aCellIdx + 2 * i
            Dim pSource As Const UByte Ptr = CPtr(Const UByte Ptr, pDestination) + 2
            pDestination[0] = pSource[0]
            pDestination[1] = pSource[1]
        Next
        btreeWriteU16(pPage->aData + pPage->hdrOffset + 3, pPage->nCell)
        pPage->nFree += 2
    End If
    For iOverflow As SQLITE_C_INT = 0 To pPage->nOverflow - 1
        If cellIndex < pPage->aiOvfl(iOverflow) Then pPage->aiOvfl(iOverflow) -= 1
    Next
    Return SQLITE_OK
End Function

/' ------------------------------------------------------------------------- '/
/' B-tree handle open and close '/
/' ------------------------------------------------------------------------- '/

Function btreeInvokeBusyHandler CDecl Alias "btreeInvokeBusyHandler" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT
    If pArgument = 0 Then Return 0
    Dim pBt As BtShared Ptr = CPtr(BtShared Ptr, pArgument)
    If pBt->db = 0 Then Return 0
    Return sqlite3InvokeBusyHandler(@pBt->db->busyHandler)
End Function

Private Sub btreeOpenReleaseMutex(ByRef pOpenMutex As Any Ptr)
    If pOpenMutex <> 0 Then
        sqlite3_mutex_leave(pOpenMutex)
        pOpenMutex = 0
    End If
End Sub

Function sqlite3BtreeOpen CDecl Alias "sqlite3BtreeOpen" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal zFilename As Const ZString Ptr, _
    ByVal db As sqlite3 Ptr, _
    ByVal ppBtree As Btree Ptr Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal vfsFlags As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If ppBtree = 0 Then Return SQLITE_MISUSE
    ppBtree[0] = 0
    If pVfs = 0 OrElse db = 0 OrElse (flags And Not &HFF) <> 0 Then Return SQLITE_MISUSE
    If (flags And BTREE_UNORDERED) <> 0 AndAlso (flags And BTREE_SINGLE) = 0 Then Return SQLITE_MISUSE

    Dim pOpenMutex As Any Ptr = 0

    Dim isTempDb As SQLITE_C_INT = IIf(zFilename = 0 OrElse zFilename[0] = 0, 1, 0)
    If (flags And BTREE_SINGLE) <> 0 AndAlso isTempDb = 0 Then Return SQLITE_MISUSE
#ifndef SQLITE_OMIT_MEMORYDB
    ' A TEMP database follows the compile-time and per-connection temp_store policy.
    Dim isMemoryDb As SQLITE_C_INT = IIf(btreeFilenameIsMemory(zFilename) <> 0 OrElse _
        (isTempDb <> 0 AndAlso sqlite3TempInMemory(db) <> 0) OrElse _
        (vfsFlags And SQLITE_OPEN_MEMORY) <> 0, 1, 0)
#else
    Dim isMemoryDb As SQLITE_C_INT = 0
#endif
    If isMemoryDb <> 0 Then flags = flags Or BTREE_MEMORY
    If (vfsFlags And SQLITE_OPEN_MAIN_DB) <> 0 AndAlso (isMemoryDb <> 0 OrElse isTempDb <> 0) Then
        vfsFlags = (vfsFlags And Not SQLITE_OPEN_MAIN_DB) Or SQLITE_OPEN_TEMP_DB
    End If

    Dim pBtree As Btree Ptr = CPtr(Btree Ptr, sqlite3MallocZero(SizeOf(Btree)))
    If pBtree = 0 Then Return SQLITE_NOMEM
    pBtree->db = db
    pBtree->inTrans = TRANS_NONE
    Dim pBt As BtShared Ptr = 0
#ifndef SQLITE_OMIT_SHARED_CACHE
    pBtree->lock.pBtree = pBtree
    pBtree->lock.iTable = 1
    Dim shareCache As SQLITE_C_INT = 0
    If isTempDb = 0 AndAlso (isMemoryDb = 0 OrElse _
       (vfsFlags And SQLITE_OPEN_URI) <> 0) Then
        If (vfsFlags And SQLITE_OPEN_SHAREDCACHE) <> 0 Then
            shareCache = 1
        End If
#ifdef SQLITE_DEBUG
        If shareCache = 0 Then pBtree->sharable = 1
#endif
    End If
    If shareCache <> 0 Then
        pBtree->sharable = 1
        Dim nFilename As SQLITE_C_INT = sqlite3Strlen30(zFilename) + 1
        Dim nMaxPathname As SQLITE_C_INT = pVfs->mxPathname + 1
        Dim nFullPath As SQLITE_C_INT = nMaxPathname
        If nFilename > nFullPath Then nFullPath = nFilename
        If nFullPath <= 0 OrElse _
           CULngInt(nFullPath) > SQLITE_MAX_ALLOCATION_SIZE Then
            sqlite3_free(pBtree)
            Return SQLITE_TOOBIG
        End If
        Dim zFullPath As ZString Ptr = CPtr(ZString Ptr, _
            sqlite3MallocZero(CULngInt(nFullPath)))
        If zFullPath = 0 Then
            sqlite3_free(pBtree)
            Return SQLITE_NOMEM
        End If

        Dim rcPath As SQLITE_C_INT = SQLITE_OK
        If isMemoryDb <> 0 Then
            For iByte As SQLITE_C_INT = 0 To nFilename - 1
                zFullPath[iByte] = zFilename[iByte]
            Next
        Else
            rcPath = sqlite3OsFullPathname(pVfs, zFilename, nMaxPathname, zFullPath)
            If rcPath = SQLITE_OK_SYMLINK Then rcPath = SQLITE_OK
        End If
        If rcPath <> SQLITE_OK Then
            sqlite3_free(zFullPath)
            sqlite3_free(pBtree)
            Return rcPath
        End If

        pOpenMutex = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_OPEN)
        Dim pSharedMutex As Any Ptr = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MAIN)
        sqlite3_mutex_enter(pOpenMutex)
        sqlite3_mutex_enter(pSharedMutex)
        Dim pBtExisting As BtShared Ptr = sqlite3SharedCacheList
        While pBtExisting <> 0
            If pBtExisting->nRef <= 0 Then
#ifdef SQLITE_DEBUG
                sqlite3DebugAssert(StrPtr("shared BtShared references are positive"))
#endif
            End If
        If pBtExisting->pPager <> 0 AndAlso _
               sqlite3PagerVfs(pBtExisting->pPager) = pVfs AndAlso _
               btreeFilenameEqual(zFullPath, _
                   sqlite3PagerFilename(pBtExisting->pPager, 0)) <> 0 Then
                For iDb As SQLITE_C_INT = db->nDb - 1 To 0 Step -1
                    Dim pExistingBtree As Btree Ptr = _
                        CPtr(Btree Ptr, db->aDb(iDb).pBt)
                    If pExistingBtree <> 0 AndAlso _
                       pExistingBtree->pBt = pBtExisting Then
                        sqlite3_mutex_leave(pSharedMutex)
                        btreeOpenReleaseMutex(pOpenMutex)
                        sqlite3_free(zFullPath)
                        sqlite3_free(pBtree)
                        Return SQLITE_CONSTRAINT
                    End If
                Next
                If pBtExisting->nRef = 2147483647 Then
                    sqlite3_mutex_leave(pSharedMutex)
                    btreeOpenReleaseMutex(pOpenMutex)
                    sqlite3_free(zFullPath)
                    sqlite3_free(pBtree)
                    Return SQLITE_FULL
                End If
                pBt = pBtExisting
                pBt->nRef += 1
                pBtree->pBt = pBt
                Exit While
            End If
            pBtExisting = CPtr(BtShared Ptr, pBtExisting->pNext)
        Wend
        sqlite3_mutex_leave(pSharedMutex)
        sqlite3_free(zFullPath)
        If pBt <> 0 Then
            btreeLinkSharedCache(pBtree)
            ppBtree[0] = pBtree
            btreeOpenReleaseMutex(pOpenMutex)
            Return SQLITE_OK
        End If
    End If
#endif

    pBt = CPtr(BtShared Ptr, sqlite3MallocZero(SizeOf(BtShared)))
    If pBt = 0 Then
        btreeOpenReleaseMutex(pOpenMutex)
        sqlite3_free(pBtree)
        Return SQLITE_NOMEM
    End If
    pBtree->pBt = pBt
    pBt->db = db
#ifndef SQLITE_OMIT_SHARED_CACHE
    pBt->nRef = 1
#endif
    pBt->openFlags = CByte(flags)
    pBt->mutex = sqlite3_mutex_alloc(SQLITE_MUTEX_FAST)
    If pBt->mutex = 0 Then
        btreeOpenReleaseMutex(pOpenMutex)
        btreeOpenCleanup(pBtree, pBt)
        Return SQLITE_NOMEM
    End If

    Dim pagerFlags As SQLITE_C_INT = flags And (BTREE_OMIT_JOURNAL Or BTREE_MEMORY)
    Dim rc As SQLITE_C_INT = sqlite3PagerOpen(pVfs, @pBt->pPager, zFilename, _
        SizeOf(MemPage), pagerFlags, vfsFlags, @pageReinit)
    If rc <> SQLITE_OK Then
        btreeOpenReleaseMutex(pOpenMutex)
        btreeOpenCleanup(pBtree, pBt)
        Return rc
    End If

    Dim dbHeader(0 To 99) As UByte
    rc = sqlite3PagerReadFileheader(pBt->pPager, 100, @dbHeader(0))
    If rc <> SQLITE_OK Then
        btreeOpenReleaseMutex(pOpenMutex)
        btreeOpenCleanup(pBtree, pBt)
        Return rc
    End If
    sqlite3PagerSetBusyHandler( _
        pBt->pPager, @btreeInvokeBusyHandler, pBt)

    Dim pageSize As u32 = (CULng(dbHeader(16)) Shl 8) Or (CULng(dbHeader(17)) Shl 16)
    Dim nReserve As SQLITE_C_INT = 0
    If pageSize < 512 OrElse pageSize > SQLITE_MAX_PAGE_SIZE OrElse _
       (pageSize And (pageSize - 1)) <> 0 Then
        pageSize = 0
    Else
        nReserve = dbHeader(20)
        pBt->btsFlags = pBt->btsFlags Or BTS_PAGESIZE_FIXED
    End If

    rc = sqlite3PagerSetPagesize(pBt->pPager, @pageSize, nReserve)
    If rc <> SQLITE_OK Then
        btreeOpenReleaseMutex(pOpenMutex)
        btreeOpenCleanup(pBtree, pBt)
        Return rc
    End If
    If nReserve < 0 OrElse nReserve >= pageSize OrElse pageSize - nReserve < 480 Then
        btreeOpenReleaseMutex(pOpenMutex)
        btreeOpenCleanup(pBtree, pBt)
        Return SQLITE_CORRUPT
    End If

    pBt->pageSize = pageSize
    pBt->usableSize = pageSize - nReserve
    pBt->nReserveWanted = CByte(nReserve)
    pBt->nPage = 0
    pBt->pPage1 = 0
    pBt->pCursor = 0
    If sqlite3PagerIsreadonly(pBt->pPager) <> 0 Then pBt->btsFlags = pBt->btsFlags Or BTS_READ_ONLY

    ' Payload fractions are fixed by the on-disk format and reserve room for
    ' cell headers, child pointers, and overflow-page references.
    pBt->maxLocal = CUShort(((pBt->usableSize - 12) * 64) \ 255 - 23)
    pBt->minLocal = CUShort(((pBt->usableSize - 12) * 32) \ 255 - 23)
    pBt->maxLeaf = CUShort(pBt->usableSize - 35)
    pBt->minLeaf = pBt->minLocal
    pBt->max1bytePayload = CByte(IIf(pBt->maxLocal > 127, 127, pBt->maxLocal))

    Dim pageCount As SQLITE_C_INT = 0
    sqlite3PagerPagecount(pBt->pPager, @pageCount)
    If pageCount < 0 Then
        btreeOpenReleaseMutex(pOpenMutex)
        btreeOpenCleanup(pBtree, pBt)
        Return SQLITE_CORRUPT
    End If
    pBt->nPage = CULng(pageCount)
#ifndef SQLITE_OMIT_SHARED_CACHE
    If pBtree->sharable <> 0 Then
        Dim pSharedMutex As Any Ptr = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MAIN)
        sqlite3_mutex_enter(pSharedMutex)
        pBt->pNext = sqlite3SharedCacheList
        sqlite3SharedCacheList = pBt
        btreeLinkSharedCache(pBtree)
        sqlite3_mutex_leave(pSharedMutex)
    End If
#endif
    ppBtree[0] = pBtree
    btreeOpenReleaseMutex(pOpenMutex)
    Return SQLITE_OK
End Function

Private Function removeFromSharingList CDecl Alias "removeFromSharingList" ( _
    ByVal pBt As BtShared Ptr _
) As SQLITE_C_INT
#ifndef SQLITE_OMIT_SHARED_CACHE
    If pBt = 0 Then Return 0
#ifdef SQLITE_DEBUG
    If sqlite3_mutex_held(pBt->mutex) <> 0 Then _
        sqlite3DebugAssert(StrPtr("BtShared mutex is not held while changing nRef"))
#endif
    If pBt->nRef <= 0 Then Return 0

    Dim pMainMutex As Any Ptr = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MAIN)
    sqlite3_mutex_enter(pMainMutex)
    pBt->nRef -= 1
    If pBt->nRef > 0 Then
        sqlite3_mutex_leave(pMainMutex)
        Return 0
    End If

    If sqlite3SharedCacheList = pBt Then
        sqlite3SharedCacheList = CPtr(BtShared Ptr, pBt->pNext)
    Else
        Dim pList As BtShared Ptr = sqlite3SharedCacheList
        While pList <> 0 AndAlso pList->pNext <> pBt
            pList = CPtr(BtShared Ptr, pList->pNext)
        Wend
        If pList = 0 Then
            pBt->nRef = 1
            sqlite3_mutex_leave(pMainMutex)
#ifdef SQLITE_DEBUG
            sqlite3DebugAssert(StrPtr("zero-reference BtShared is in the global list"))
#endif
            Return 0
        End If
        pList->pNext = pBt->pNext
    End If
    pBt->pNext = 0
    sqlite3_mutex_leave(pMainMutex)
    Return 1
#else
    Return 1
#endif
End Function

Function sqlite3BtreeClose CDecl Alias "sqlite3BtreeClose" (ByVal pBtree As Btree Ptr) As SQLITE_C_INT Export
    If pBtree = 0 Then Return SQLITE_OK
    Dim pBt As BtShared Ptr = pBtree->pBt
    If pBt = 0 Then
        sqlite3_free(pBtree)
        Return SQLITE_OK
    End If
    Dim pCursor As BtCursor Ptr = CPtr(BtCursor Ptr, pBt->pCursor)
    While pCursor <> 0
        If pCursor->pBtree = pBtree Then Return SQLITE_BUSY
        pCursor = pCursor->pNext
    Wend

    sqlite3BtreeEnter(pBtree)
    sqlite3BtreeRollback(pBtree, SQLITE_OK, 0)
    sqlite3BtreeLeave(pBtree)

    Dim deleteShared As SQLITE_C_INT = 1
#ifndef SQLITE_OMIT_SHARED_CACHE
    If pBtree->sharable <> 0 Then deleteShared = removeFromSharingList(pBt)
#endif
    If deleteShared = 0 Then
#ifndef SQLITE_OMIT_SHARED_CACHE
        btreeUnlinkSharedCache(pBtree)
#endif
        pBtree->pBt = 0
        sqlite3_free(pBtree)
        Return SQLITE_OK
    End If

    If pBt->pPage1 <> 0 Then
        sqlite3BtreeReleasePage(CPtr(MemPage Ptr, pBt->pPage1))
        pBt->pPage1 = 0
    End If
    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pBt->pPager <> 0 Then rc = sqlite3PagerClose(pBt->pPager, pBtree->db)
    If rc = SQLITE_BUSY Then
#ifndef SQLITE_OMIT_SHARED_CACHE
        If pBtree->sharable <> 0 Then
            Dim pMainMutex As Any Ptr = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MAIN)
            sqlite3_mutex_enter(pMainMutex)
            pBt->nRef = 1
            pBt->pNext = sqlite3SharedCacheList
            sqlite3SharedCacheList = pBt
            sqlite3_mutex_leave(pMainMutex)
        End If
#endif
        Return rc
    End If
    If pBt->xFreeSchema <> 0 AndAlso pBt->pSchema <> 0 Then
        Dim xFreeSchema As BtreeSchemaFreeCallback = _
            CPtr(BtreeSchemaFreeCallback, pBt->xFreeSchema)
        xFreeSchema(pBt->pSchema)
    End If
    sqlite3_free(pBt->pSchema)
    pBt->pSchema = 0
    freeTempSpace(pBt)
    If pBt->mutex <> 0 Then sqlite3_mutex_free(pBt->mutex)
#ifndef SQLITE_OMIT_SHARED_CACHE
    btreeUnlinkSharedCache(pBtree)
#endif
    sqlite3_free(pBt)
    pBtree->pBt = 0
    sqlite3_free(pBtree)
    Return rc
End Function

Function sqlite3BtreeGetPageSize CDecl Alias "sqlite3BtreeGetPageSize" (ByVal pBtree As Btree Ptr) As SQLITE_C_INT Export
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return 0
    Return CLng(pBtree->pBt->pageSize)
End Function

Function sqlite3BtreeGetFilename CDecl Alias "sqlite3BtreeGetFilename" (ByVal pBtree As Btree Ptr) As Const ZString Ptr Export
    If pBtree = 0 OrElse pBtree->pBt = 0 OrElse pBtree->pBt->pPager = 0 Then Return 0
    Return sqlite3PagerFilename(pBtree->pBt->pPager, 1)
End Function

Function sqlite3BtreeGetJournalname CDecl Alias "sqlite3BtreeGetJournalname" (ByVal pBtree As Btree Ptr) As Const ZString Ptr Export
    If pBtree = 0 OrElse pBtree->pBt = 0 OrElse pBtree->pBt->pPager = 0 Then Return 0
    Return sqlite3PagerJournalname(pBtree->pBt->pPager)
End Function

Function sqlite3BtreePager CDecl Alias "sqlite3BtreePager" ( _
    ByVal pBtree As Btree Ptr _
) As Pager Ptr Export
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return 0
    Return pBtree->pBt->pPager
End Function

Function sqlite3BtreeSchema CDecl Alias "sqlite3BtreeSchema" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal xFreeSchema As Any Ptr _
) As Any Ptr Export
    If pBtree = 0 OrElse pBtree->pBt = 0 OrElse nByte < 0 Then Return 0
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    If pBt->pSchema = 0 AndAlso nByte <> 0 Then
        pBt->pSchema = sqlite3DbMallocZero(0, CULngInt(nByte))
        pBt->xFreeSchema = xFreeSchema
    End If
    Dim pSchema As Any Ptr = pBt->pSchema
    sqlite3BtreeLeave(pBtree)
    Return pSchema
End Function

Function btreePagecount CDecl Alias "btreePagecount" ( _
    ByVal pBt As BtShared Ptr _
) As u32
    If pBt = 0 Then Return 0
    Return pBt->nPage
End Function

Function sqlite3BtreeLastPage CDecl Alias "sqlite3BtreeLastPage" (ByVal pBtree As Btree Ptr) As u32 Export
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return 0
    Return btreePagecount(pBtree->pBt)
End Function

Function sqlite3BtreeSharable CDecl Alias "sqlite3BtreeSharable" (ByVal pBtree As Btree Ptr) As SQLITE_C_INT Export
    If pBtree = 0 Then Return 0
    Return IIf(pBtree->sharable <> 0, 1, 0)
End Function

Function sqlite3BtreeConnectionCount CDecl Alias "sqlite3BtreeConnectionCount" (ByVal pBtree As Btree Ptr) As SQLITE_C_INT Export
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return 0
#ifndef SQLITE_OMIT_SHARED_CACHE
    Return pBtree->pBt->nRef
#else
    Return 1
#endif
End Function

Function sqlite3BtreeSetCacheSize CDecl Alias "sqlite3BtreeSetCacheSize" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal maxPages As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return SQLITE_MISUSE
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    sqlite3PagerSetCachesize(pBt->pPager, maxPages)
    sqlite3BtreeLeave(pBtree)
    Return SQLITE_OK
End Function

Function sqlite3BtreeSetSpillSize CDecl Alias "sqlite3BtreeSetSpillSize" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal maxPages As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return SQLITE_MISUSE
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    Dim result As SQLITE_C_INT = sqlite3PagerSetSpillsize(pBt->pPager, maxPages)
    sqlite3BtreeLeave(pBtree)
    Return result
End Function

Function sqlite3BtreeSetPagerFlags CDecl Alias "sqlite3BtreeSetPagerFlags" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal flags As SQLITE_C_UINT _
) As SQLITE_C_INT Export

    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return SQLITE_MISUSE
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    sqlite3PagerSetFlags(pBt->pPager, flags)
    sqlite3BtreeLeave(pBtree)
    Return SQLITE_OK
End Function

Function sqlite3BtreeSetPageSize CDecl Alias "sqlite3BtreeSetPageSize" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal requestedPageSize As SQLITE_C_INT, _
    ByVal requestedReserve As SQLITE_C_INT, _
    ByVal fixPageSize As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pBtree = 0 OrElse pBtree->pBt = 0 OrElse requestedPageSize < 0 OrElse _
       requestedReserve < 0 OrElse requestedReserve > 255 OrElse _
       (fixPageSize <> 0 AndAlso fixPageSize <> 1) Then Return SQLITE_MISUSE
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    pBt->nReserveWanted = CByte(requestedReserve)
    Dim oldReserve As SQLITE_C_INT = CLng(pBt->pageSize - pBt->usableSize)
    If oldReserve = requestedReserve AndAlso _
       (requestedPageSize = 0 OrElse CULng(requestedPageSize) = pBt->pageSize) Then
        sqlite3BtreeLeave(pBtree)
        Return SQLITE_OK
    End If

    Dim reserveSize As SQLITE_C_INT = requestedReserve
    If reserveSize < oldReserve Then reserveSize = oldReserve
    If (pBt->btsFlags And BTS_PAGESIZE_FIXED) <> 0 Then
        sqlite3BtreeLeave(pBtree)
        Return SQLITE_READONLY
    End If

    Dim selectedPageSize As u32 = pBt->pageSize
    If requestedPageSize >= 512 AndAlso requestedPageSize <= SQLITE_MAX_PAGE_SIZE AndAlso _
       (requestedPageSize And (requestedPageSize - 1)) = 0 Then
        selectedPageSize = CULng(requestedPageSize)
        If reserveSize > 32 AndAlso selectedPageSize = 512 Then selectedPageSize = 1024
        If selectedPageSize <> pBt->pageSize Then
            If pBt->pCursor <> 0 Then
                sqlite3BtreeLeave(pBtree)
                Return SQLITE_BUSY
            End If
            freeTempSpace(pBt)
            pBt->pageSize = selectedPageSize
        End If
    End If

    If selectedPageSize < 512 OrElse reserveSize >= selectedPageSize OrElse _
       selectedPageSize - reserveSize < 480 Then
        sqlite3BtreeLeave(pBtree)
        Return SQLITE_MISUSE
    End If
    Dim rc As SQLITE_C_INT = sqlite3PagerSetPagesize(pBt->pPager, @pBt->pageSize, reserveSize)
    If rc = SQLITE_OK Then
        pBt->usableSize = pBt->pageSize - reserveSize
        btreeSetPayloadLimits(pBt)
        If fixPageSize <> 0 Then pBt->btsFlags = pBt->btsFlags Or BTS_PAGESIZE_FIXED
    End If
    sqlite3BtreeLeave(pBtree)
    Return rc
End Function

Function sqlite3BtreeGetReserveNoMutex CDecl Alias "sqlite3BtreeGetReserveNoMutex" ( _
    ByVal pBtree As Btree Ptr _
) As SQLITE_C_INT Export
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return 0
    Return CLng(pBtree->pBt->pageSize - pBtree->pBt->usableSize)
End Function

Function sqlite3BtreeGetRequestedReserve CDecl Alias "sqlite3BtreeGetRequestedReserve" ( _
    ByVal pBtree As Btree Ptr _
) As SQLITE_C_INT Export
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return 0
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    Dim currentReserve As SQLITE_C_INT = CLng(pBt->pageSize - pBt->usableSize)
    Dim requestedReserve As SQLITE_C_INT = pBt->nReserveWanted
    sqlite3BtreeLeave(pBtree)
    Return IIf(requestedReserve > currentReserve, requestedReserve, currentReserve)
End Function

Function sqlite3BtreeMaxPageCount CDecl Alias "sqlite3BtreeMaxPageCount" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal maxPage As u32 _
) As u32 Export
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return 0
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    Dim result As u32 = sqlite3PagerMaxPageCount(pBt->pPager, maxPage)
    sqlite3BtreeLeave(pBtree)
    Return result
End Function

Function sqlite3BtreeSecureDelete CDecl Alias "sqlite3BtreeSecureDelete" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal newFlag As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return 0
    If newFlag > 2 Then Return SQLITE_MISUSE
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    If newFlag >= 0 Then
        pBt->btsFlags = pBt->btsFlags And Not BTS_FAST_SECURE
        pBt->btsFlags = pBt->btsFlags Or CUShort(BTS_SECURE_DELETE * newFlag)
    End If
    Dim result As SQLITE_C_INT = (pBt->btsFlags And BTS_FAST_SECURE) \ BTS_SECURE_DELETE
    sqlite3BtreeLeave(pBtree)
    Return result
End Function

Function sqlite3BtreeSetAutoVacuum CDecl Alias "sqlite3BtreeSetAutoVacuum" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal autoVacuum As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pBtree = 0 OrElse pBtree->pBt = 0 OrElse autoVacuum < 0 OrElse autoVacuum > 2 Then Return SQLITE_MISUSE
#ifdef SQLITE_OMIT_AUTOVACUUM
    Return SQLITE_READONLY
#else
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    Dim requestedMode As SQLITE_C_INT = IIf(autoVacuum <> 0, 1, 0)
    Dim rc As SQLITE_C_INT = SQLITE_OK
    If (pBt->btsFlags And BTS_PAGESIZE_FIXED) <> 0 AndAlso requestedMode <> pBt->autoVacuum Then
        rc = SQLITE_READONLY
    Else
        pBt->autoVacuum = CByte(requestedMode)
        pBt->incrVacuum = CByte(IIf(autoVacuum = 2, 1, 0))
    End If
    sqlite3BtreeLeave(pBtree)
    Return rc
#endif
End Function

Function sqlite3BtreeGetAutoVacuum CDecl Alias "sqlite3BtreeGetAutoVacuum" ( _
    ByVal pBtree As Btree Ptr _
) As SQLITE_C_INT Export
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return BTREE_AUTOVACUUM_NONE
#ifdef SQLITE_OMIT_AUTOVACUUM
    Return BTREE_AUTOVACUUM_NONE
#else
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    Dim result As SQLITE_C_INT = BTREE_AUTOVACUUM_NONE
    If pBt->autoVacuum <> 0 Then
        result = IIf(pBt->incrVacuum <> 0, BTREE_AUTOVACUUM_INCR, BTREE_AUTOVACUUM_FULL)
    End If
    sqlite3BtreeLeave(pBtree)
    Return result
#endif
End Function

Function sqlite3BtreeIsReadonly CDecl Alias "sqlite3BtreeIsReadonly" ( _
    ByVal pBtree As Btree Ptr _
) As SQLITE_C_INT Export
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return 1
    Return IIf((pBtree->pBt->btsFlags And BTS_READ_ONLY) <> 0, 1, 0)
End Function

Function sqlite3HeaderSizeBtree CDecl Alias "sqlite3HeaderSizeBtree" () As SQLITE_C_INT Export
    Return (SizeOf(MemPage) + 7) And Not 7
End Function

Sub sqlite3BtreeClearCache CDecl Alias "sqlite3BtreeClearCache" (ByVal pBtree As Btree Ptr) Export
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Exit Sub
    Dim pBt As BtShared Ptr = pBtree->pBt
    If pBt->inTransaction = TRANS_NONE Then sqlite3PagerClearCache(pBt->pPager)
End Sub

Function sqlite3BtreeGetAndInitPage CDecl Alias "sqlite3BtreeGetAndInitPage" ( _
    ByVal pBt As BtShared Ptr, _
    ByVal pageNumber As u32, _
    ByVal ppPage As MemPage Ptr Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If ppPage = 0 Then Return SQLITE_MISUSE
    ppPage[0] = 0
    If pBt = 0 OrElse pBt->pPager = 0 OrElse pageNumber = 0 Then Return SQLITE_MISUSE
    If pageNumber > pBt->nPage Then Return SQLITE_CORRUPT

    Dim pDbPage As PgHdr Ptr = 0
    Dim rc As SQLITE_C_INT = sqlite3PagerGet(pBt->pPager, pageNumber, @pDbPage, flags)
    If rc <> SQLITE_OK Then Return rc
    Dim pPage As MemPage Ptr = btreePageFromDbPage(pDbPage, pageNumber, pBt)
    If pPage = 0 Then
        sqlite3PagerUnrefNotNull(pDbPage)
        Return SQLITE_CORRUPT
    End If
    If pPage->isInit = 0 Then
        rc = sqlite3BtreeInitPage(pPage)
        If rc <> SQLITE_OK Then
            sqlite3PagerUnrefNotNull(pDbPage)
            Return rc
        End If
    End If
    ppPage[0] = pPage
    Return SQLITE_OK
End Function

Sub releasePageNotNull CDecl Alias "releasePageNotNull" ( _
    ByVal pPage As MemPage Ptr _
)
    If pPage = 0 OrElse pPage->aData = 0 OrElse pPage->pBt = 0 OrElse _
       pPage->pDbPage = 0 Then Return
    sqlite3PagerUnrefNotNull(pPage->pDbPage)
End Sub

Sub releasePage CDecl Alias "releasePage" (ByVal pPage As MemPage Ptr)
    If pPage <> 0 Then releasePageNotNull(pPage)
End Sub

Private Sub releasePageOne CDecl Alias "releasePageOne" (ByVal pPage As MemPage Ptr)
    If pPage = 0 OrElse pPage->aData = 0 OrElse pPage->pBt = 0 OrElse _
       pPage->pDbPage = 0 OrElse pPage->pgno <> 1 Then Return
    sqlite3PagerUnrefPageOne(pPage->pDbPage)
End Sub

Sub sqlite3BtreeReleasePage CDecl Alias "sqlite3BtreeReleasePage" (ByVal pPage As MemPage Ptr) Export
    If pPage = 0 Then Return
    If pPage->pgno = 1 Then
        releasePageOne(pPage)
    Else
        releasePage(pPage)
    End If
End Sub

Function sqlite3BtreeGetCellInfo CDecl Alias "sqlite3BtreeGetCellInfo" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal cellIndex As SQLITE_C_INT, _
    ByVal pInfo As CellInfo Ptr _
) As SQLITE_C_INT Export
    Return btreeParseCell(pPage, cellIndex, pInfo)
End Function

Private Function btreeParseCell CDecl Alias "btreeParseCell" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal cellIndex As SQLITE_C_INT, _
    ByVal pInfo As CellInfo Ptr _
) As SQLITE_C_INT
    If pPage = 0 OrElse pInfo = 0 OrElse pPage->isInit = 0 OrElse _
       cellIndex < 0 OrElse cellIndex >= pPage->nCell Then Return SQLITE_MISUSE
    Dim pCellIndex As Const UByte Ptr = CPtr(Const UByte Ptr, pPage->aCellIdx) + (cellIndex * 2)
    Dim cellOffset As u32 = btreeGetU16(pCellIndex) And pPage->maskPage
    If cellOffset >= pPage->pBt->usableSize Then Return SQLITE_CORRUPT
    Dim xParseCell As BtreeCellParseProc = CPtr(BtreeCellParseProc, pPage->xParseCell)
    If xParseCell = 0 Then Return SQLITE_CORRUPT
    xParseCell(pPage, pPage->aData + cellOffset, pInfo)
    If pInfo->nSize = 0 Then Return SQLITE_CORRUPT
    Return SQLITE_OK
End Function

Function sqlite3BtreeCellSize CDecl Alias "sqlite3BtreeCellSize" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal pCell As UByte Ptr _
) As u16 Export
    If pPage = 0 OrElse pPage->xCellSize = 0 Then Return 0
    Dim xCellSize As BtreeCellSizeProc = CPtr(BtreeCellSizeProc, pPage->xCellSize)
    Return xCellSize(pPage, pCell)
End Function

#ifdef SQLITE_DEBUG
Private Function cellSizeDebug CDecl Alias "cellSize" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal cellIndex As SQLITE_C_INT _
) As u16
    If pPage = 0 OrElse pPage->aCellIdx = 0 OrElse _
       cellIndex < 0 OrElse cellIndex >= pPage->nCell Then Return 0
    Dim pCellIndex As Const UByte Ptr = CPtr(Const UByte Ptr, pPage->aCellIdx) + (cellIndex * 2)
    Dim cellOffset As u32 = btreeGetU16(pCellIndex) And pPage->maskPage
    If cellOffset >= pPage->pBt->usableSize Then Return 0
    Return sqlite3BtreeCellSize(pPage, pPage->aData + cellOffset)
End Function
#endif

/' ------------------------------------------------------------------------- '/
/' Page-one locking and database initialization '/
/' ------------------------------------------------------------------------- '/

Private Function btreeReadU32(ByVal pData As Const UByte Ptr) As u32
    If pData = 0 Then Return 0
    Return (CULng(pData[0]) Shl 24) Or (CULng(pData[1]) Shl 16) Or _
           (CULng(pData[2]) Shl 8) Or CULng(pData[3])
End Function

Private Sub btreeWriteU32(ByVal pData As UByte Ptr, ByVal value As u32)
    If pData = 0 Then Exit Sub
    pData[0] = CByte((value Shr 24) And &HFF)
    pData[1] = CByte((value Shr 16) And &HFF)
    pData[2] = CByte((value Shr 8) And &HFF)
    pData[3] = CByte(value And &HFF)
End Sub

Private Function btreeGetUnusedPage( _
    ByVal pBt As BtShared Ptr, _
    ByVal pageNumber As u32, _
    ByVal ppPage As MemPage Ptr Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT

    If ppPage = 0 Then Return SQLITE_MISUSE
    ppPage[0] = 0
    If pBt = 0 OrElse pageNumber < 2 OrElse pageNumber > pBt->nPage Then Return SQLITE_CORRUPT

    Dim rc As SQLITE_C_INT = btreeGetPage(pBt, pageNumber, ppPage, flags)
    If rc <> SQLITE_OK Then Return rc
    If ppPage[0] = 0 OrElse ppPage[0]->pDbPage = 0 Then
        If ppPage[0] <> 0 Then sqlite3BtreeReleasePage(ppPage[0])
        ppPage[0] = 0
        Return SQLITE_CORRUPT
    End If
    If sqlite3PagerPageRefcount(ppPage[0]->pDbPage) > 1 Then
        sqlite3BtreeReleasePage(ppPage[0])
        ppPage[0] = 0
        Return SQLITE_CORRUPT
    End If
    ppPage[0]->isInit = 0
    Return SQLITE_OK
End Function

#ifndef SQLITE_OMIT_AUTOVACUUM
Function ptrmapPageno( _
    ByVal pBt As BtShared Ptr, _
    ByVal pageNumber As u32 _
) As u32
    If pBt = 0 OrElse pageNumber < 2 OrElse pBt->usableSize < 5 OrElse pBt->pageSize = 0 Then Return 0
    Dim pagesPerMap As ULongInt = CULngInt(pBt->usableSize) \ 5 + 1
    Dim mapIndex As ULongInt = (CULngInt(pageNumber) - 2) \ pagesPerMap
    Dim mapPage As ULongInt = mapIndex * pagesPerMap + 2
    Dim pendingPage As u32 = (PENDING_BYTE \ pBt->pageSize) + 1
    If mapPage = pendingPage Then mapPage += 1
    If mapPage > &HFFFFFFFF Then Return 0
    Return CUInt(mapPage)
End Function

Private Function ptrmapIsPage(ByVal pBt As BtShared Ptr, ByVal pageNumber As u32) As Long
    Dim mapPage As u32 = ptrmapPageno(pBt, pageNumber)
    Return IIf(mapPage <> 0 AndAlso mapPage = pageNumber, -1, 0)
End Function

Private Function ptrmapEntryOffset( _
    ByVal pBt As BtShared Ptr, _
    ByVal mapPage As u32, _
    ByVal pageNumber As u32 _
) As SQLITE_C_INT
    If pBt = 0 OrElse mapPage = 0 OrElse pageNumber <= mapPage Then Return -1
    Dim offset As ULongInt = 5 * (CULngInt(pageNumber) - mapPage - 1)
    If offset + 5 > pBt->usableSize OrElse offset > &H7FFFFFFF Then Return -1
    Return CLng(offset)
End Function

Private Sub ptrmapPut( _
    ByVal pBt As BtShared Ptr, _
    ByVal key As u32, _
    ByVal entryType As u8, _
    ByVal parentPage As u32, _
    ByVal pRc As SQLITE_C_INT Ptr _
)
    If pRc = 0 OrElse pRc[0] <> SQLITE_OK Then Return
    If pBt = 0 OrElse pBt->pPager = 0 OrElse pBt->autoVacuum = 0 Then
        pRc[0] = SQLITE_MISUSE
        Return
    End If
    If key = 0 OrElse entryType < PTRMAP_ROOTPAGE OrElse entryType > PTRMAP_BTREE Then
        pRc[0] = SQLITE_CORRUPT
        Return
    End If

    Dim mapPage As u32 = ptrmapPageno(pBt, key)
    Dim offset As SQLITE_C_INT = ptrmapEntryOffset(pBt, mapPage, key)
    If mapPage = 0 OrElse offset < 0 Then
        pRc[0] = SQLITE_CORRUPT
        Return
    End If

    Dim pDbPage As PgHdr Ptr = 0
    Dim rc As SQLITE_C_INT = sqlite3PagerGet(pBt->pPager, mapPage, @pDbPage, 0)
    If rc <> SQLITE_OK Then
        pRc[0] = rc
        Return
    End If

    Dim pExtra As UByte Ptr = CPtr(UByte Ptr, sqlite3PagerGetExtra(pDbPage))
    If pExtra = 0 OrElse pExtra[0] <> 0 Then
        pRc[0] = SQLITE_CORRUPT
    Else
        Dim pMapData As UByte Ptr = CPtr(UByte Ptr, sqlite3PagerGetData(pDbPage))
        If pMapData = 0 Then
            pRc[0] = SQLITE_CORRUPT
        ElseIf pMapData[offset] <> entryType OrElse sqlite3Get4byte(pMapData + offset + 1) <> parentPage Then
            rc = sqlite3PagerWrite(pDbPage)
            If rc <> SQLITE_OK Then
                pRc[0] = rc
            Else
                pMapData[offset] = entryType
                sqlite3Put4byte(pMapData + offset + 1, parentPage)
            End If
        End If
    End If
    sqlite3PagerUnref(pDbPage)
End Sub

Private Function ptrmapGet( _
    ByVal pBt As BtShared Ptr, _
    ByVal key As u32, _
    ByVal pEntryType As u8 Ptr, _
    ByVal pParentPage As u32 Ptr _
) As SQLITE_C_INT
    If pBt = 0 OrElse pBt->pPager = 0 OrElse pBt->autoVacuum = 0 OrElse _
       key = 0 OrElse pEntryType = 0 Then Return SQLITE_CORRUPT

    Dim mapPage As u32 = ptrmapPageno(pBt, key)
    Dim offset As SQLITE_C_INT = ptrmapEntryOffset(pBt, mapPage, key)
    If mapPage = 0 OrElse offset < 0 Then Return SQLITE_CORRUPT

    Dim pDbPage As PgHdr Ptr = 0
    Dim rc As SQLITE_C_INT = sqlite3PagerGet(pBt->pPager, mapPage, @pDbPage, 0)
    If rc <> SQLITE_OK Then Return rc
    Dim pMapData As UByte Ptr = CPtr(UByte Ptr, sqlite3PagerGetData(pDbPage))
    If pMapData = 0 Then
        sqlite3PagerUnref(pDbPage)
        Return SQLITE_CORRUPT
    End If
    pEntryType[0] = pMapData[offset]
    If pParentPage <> 0 Then pParentPage[0] = sqlite3Get4byte(pMapData + offset + 1)
    sqlite3PagerUnref(pDbPage)
    If pEntryType[0] < PTRMAP_ROOTPAGE OrElse pEntryType[0] > PTRMAP_BTREE Then Return SQLITE_CORRUPT
    Return SQLITE_OK
End Function

Private Function getOverflowPage CDecl Alias "getOverflowPage" ( _
    ByVal pBt As BtShared Ptr, _
    ByVal overflowPage As u32, _
    ByVal ppPage As MemPage Ptr Ptr, _
    ByVal pNextPage As u32 Ptr _
) As SQLITE_C_INT

    ' Caller holds pBt->mutex. A non-null page output transfers one page
    ' reference to the caller, which must release it after use.
    If pNextPage = 0 Then Return SQLITE_MISUSE
    pNextPage[0] = 0
    If ppPage <> 0 Then ppPage[0] = 0
    If pBt = 0 OrElse pBt->pPager = 0 OrElse pBt->pageSize = 0 OrElse _
       overflowPage < 2 OrElse overflowPage > btreePagecount(pBt) Then Return SQLITE_CORRUPT

    Dim nextPage As u32 = 0
    Dim pPage As MemPage Ptr = 0
    Dim rc As SQLITE_C_INT = SQLITE_OK
#ifndef SQLITE_OMIT_AUTOVACUUM
    If pBt->autoVacuum <> 0 AndAlso overflowPage < &HFFFFFFFF Then
        ' Pointer-map ownership can identify the next overflow page without
        ' loading this page, but only when the next eligible page points back.
        Dim guess As u32 = overflowPage + 1
        Dim pendingPage As u32 = (PENDING_BYTE \ pBt->pageSize) + 1
        While guess <= btreePagecount(pBt) AndAlso _
              (ptrmapIsPage(pBt, guess) <> 0 OrElse guess = pendingPage)
            If guess = &HFFFFFFFF Then Exit While
            guess += 1
        Wend
        If guess <= btreePagecount(pBt) Then
            Dim entryType As u8 = 0
            Dim parentPage As u32 = 0
            rc = ptrmapGet(pBt, guess, @entryType, @parentPage)
            If rc = SQLITE_OK AndAlso entryType = PTRMAP_OVERFLOW2 AndAlso _
               parentPage = overflowPage Then
                nextPage = guess
                rc = SQLITE_DONE
            End If
        End If
    End If
#endif

    If rc = SQLITE_OK Then
        Dim readFlags As SQLITE_C_INT = IIf(ppPage = 0, PAGER_GET_READONLY, 0)
        rc = btreeGetPage(pBt, overflowPage, @pPage, readFlags)
        If rc = SQLITE_OK Then
            If pPage = 0 OrElse pPage->aData = 0 Then
                rc = SQLITE_CORRUPT
            Else
                nextPage = btreeReadU32(pPage->aData)
            End If
        End If
    End If

    pNextPage[0] = nextPage
    If ppPage <> 0 Then
        ppPage[0] = pPage
    ElseIf pPage <> 0 Then
        sqlite3BtreeReleasePage(pPage)
    End If
    If rc = SQLITE_DONE Then Return SQLITE_OK
    Return rc
End Function

Private Sub ptrmapPutOvflPtr( _
    ByVal pPage As MemPage Ptr, _
    ByVal pSourcePage As MemPage Ptr, _
    ByVal pCell As UByte Ptr, _
    ByVal pRc As SQLITE_C_INT Ptr _
)
    If pRc = 0 OrElse pRc[0] <> SQLITE_OK Then Return
    If pPage = 0 OrElse pSourcePage = 0 OrElse pCell = 0 OrElse pPage->pBt = 0 Then
        pRc[0] = SQLITE_MISUSE
        Return
    End If
    Dim parseCell As BtreeCellParseProc = CPtr(BtreeCellParseProc, pPage->xParseCell)
    If parseCell = 0 Then
        pRc[0] = SQLITE_CORRUPT
        Return
    End If
    Dim info As CellInfo
    parseCell(pPage, pCell, @info)
    If info.nLocal >= info.nPayload Then Return

    If pSourcePage->aData = 0 OrElse pSourcePage->pBt = 0 OrElse info.nSize < 4 Then
        pRc[0] = SQLITE_CORRUPT
        Return
    End If
    Dim cellOffset As LongInt = pCell - pSourcePage->aData
    If cellOffset < 0 OrElse _
       CULngInt(cellOffset) + CULngInt(info.nLocal) + 4 > pSourcePage->pBt->usableSize OrElse _
       CULngInt(cellOffset) + info.nSize > pSourcePage->pBt->usableSize Then
        pRc[0] = SQLITE_CORRUPT
        Return
    End If
    Dim overflowPage As u32 = sqlite3Get4byte(pCell + info.nSize - 4)
    ptrmapPut(pPage->pBt, overflowPage, PTRMAP_OVERFLOW1, pPage->pgno, pRc)
End Sub

Function setChildPtrmaps CDecl Alias "setChildPtrmaps" (ByVal pPage As MemPage Ptr) As SQLITE_C_INT
    If pPage = 0 OrElse pPage->pBt = 0 OrElse pPage->aData = 0 Then Return SQLITE_MISUSE
    Dim pBt As BtShared Ptr = pPage->pBt
    If pBt->autoVacuum = 0 Then Return SQLITE_OK
    If pPage->isInit = 0 Then
        Dim initRc As SQLITE_C_INT = sqlite3BtreeInitPage(pPage)
        If initRc <> SQLITE_OK Then Return initRc
    End If

    Dim rc As SQLITE_C_INT = SQLITE_OK
    For cellIndex As SQLITE_C_INT = 0 To pPage->nCell - 1
        Dim pCellIndex As Const UByte Ptr = pPage->aCellIdx + (cellIndex * 2)
        Dim cellOffset As u32 = btreeGetU16(pCellIndex) And pPage->maskPage
        If cellOffset >= pBt->usableSize Then Return SQLITE_CORRUPT
        Dim pCell As UByte Ptr = pPage->aData + cellOffset
        ptrmapPutOvflPtr(pPage, pPage, pCell, @rc)
        If rc <> SQLITE_OK Then Return rc

        If pPage->leaf = 0 Then
            If cellOffset + 4 > pBt->usableSize Then Return SQLITE_CORRUPT
            Dim childPage As u32 = sqlite3Get4byte(pCell)
            ptrmapPut(pBt, childPage, PTRMAP_BTREE, pPage->pgno, @rc)
            If rc <> SQLITE_OK Then Return rc
        End If
    Next

    If pPage->leaf = 0 Then
        Dim rightChildOffset As Long = pPage->hdrOffset + 8
        If rightChildOffset < 0 OrElse rightChildOffset + 4 > pBt->usableSize Then Return SQLITE_CORRUPT
        Dim rightChildPage As u32 = sqlite3Get4byte(pPage->aData + rightChildOffset)
        ptrmapPut(pBt, rightChildPage, PTRMAP_BTREE, pPage->pgno, @rc)
    End If
    Return rc
End Function

Function modifyPagePointer CDecl Alias "modifyPagePointer" ( _
    ByVal pPage As MemPage Ptr, _
    ByVal fromPage As u32, _
    ByVal toPage As u32, _
    ByVal pointerType As u8 _
) As SQLITE_C_INT
    If pPage = 0 OrElse pPage->pBt = 0 OrElse pPage->aData = 0 OrElse _
       pPage->pDbPage = 0 OrElse fromPage = 0 OrElse toPage = 0 Then Return SQLITE_MISUSE
    If sqlite3PagerIswriteable(pPage->pDbPage) = 0 Then Return SQLITE_READONLY

    If pointerType = PTRMAP_OVERFLOW2 Then
        If pPage->pBt->usableSize < 4 OrElse sqlite3Get4byte(pPage->aData) <> fromPage Then
            Return SQLITE_CORRUPT
        End If
        sqlite3Put4byte(pPage->aData, toPage)
        Return SQLITE_OK
    End If
    If pointerType <> PTRMAP_BTREE AndAlso pointerType <> PTRMAP_OVERFLOW1 Then Return SQLITE_MISUSE

    If pPage->isInit = 0 Then
        Dim rcInit As SQLITE_C_INT = sqlite3BtreeInitPage(pPage)
        If rcInit <> SQLITE_OK Then Return rcInit
    End If
    For cellIndex As SQLITE_C_INT = 0 To pPage->nCell - 1
        Dim pCellIndex As Const UByte Ptr = pPage->aCellIdx + (cellIndex * 2)
        Dim cellOffset As u32 = btreeGetU16(pCellIndex) And pPage->maskPage
        If cellOffset >= pPage->pBt->usableSize Then Return SQLITE_CORRUPT
        Dim pCell As UByte Ptr = pPage->aData + cellOffset
        If pointerType = PTRMAP_OVERFLOW1 Then
            Dim info As CellInfo
            Dim rcInfo As SQLITE_C_INT = sqlite3BtreeGetCellInfo(pPage, cellIndex, @info)
            If rcInfo <> SQLITE_OK Then Return rcInfo
            If info.nLocal < info.nPayload Then
                If info.nSize < 4 OrElse CULngInt(cellOffset) + info.nSize > pPage->pBt->usableSize Then Return SQLITE_CORRUPT
                Dim pOverflowPointer As UByte Ptr = pCell + info.nSize - 4
                If sqlite3Get4byte(pOverflowPointer) = fromPage Then
                    sqlite3Put4byte(pOverflowPointer, toPage)
                    Return SQLITE_OK
                End If
            End If
        Else
            If CULngInt(cellOffset) + 4 > pPage->pBt->usableSize Then Return SQLITE_CORRUPT
            If sqlite3Get4byte(pCell) = fromPage Then
                sqlite3Put4byte(pCell, toPage)
                Return SQLITE_OK
            End If
        End If
    Next

    If pointerType <> PTRMAP_BTREE Then Return SQLITE_CORRUPT
    Dim rightChildOffset As Long = pPage->hdrOffset + 8
    If rightChildOffset < 0 OrElse rightChildOffset + 4 > pPage->pBt->usableSize Then Return SQLITE_CORRUPT
    Dim pRightChild As UByte Ptr = pPage->aData + rightChildOffset
    If sqlite3Get4byte(pRightChild) <> fromPage Then Return SQLITE_CORRUPT
    sqlite3Put4byte(pRightChild, toPage)
    Return SQLITE_OK
End Function

Private Function relocatePage( _
    ByVal pBt As BtShared Ptr, _
    ByVal pPage As MemPage Ptr, _
    ByVal pointerType As u8, _
    ByVal parentPage As u32, _
    ByVal newPageNumber As u32, _
    ByVal isCommit As SQLITE_C_INT _
) As SQLITE_C_INT
    If pBt = 0 OrElse pPage = 0 OrElse pPage->pBt <> pBt OrElse _
       pPage->pDbPage = 0 OrElse pPage->aData = 0 OrElse pPage->pgno < 3 OrElse _
       newPageNumber = 0 Then Return SQLITE_CORRUPT
    If pointerType <> PTRMAP_OVERFLOW2 AndAlso pointerType <> PTRMAP_OVERFLOW1 AndAlso _
       pointerType <> PTRMAP_BTREE AndAlso pointerType <> PTRMAP_ROOTPAGE Then Return SQLITE_CORRUPT

    Dim oldPageNumber As u32 = pPage->pgno
    Dim rc As SQLITE_C_INT = sqlite3PagerMovepage(pBt->pPager, pPage->pDbPage, newPageNumber, isCommit)
    If rc <> SQLITE_OK Then Return rc
    pPage->pgno = newPageNumber

    If pointerType = PTRMAP_BTREE OrElse pointerType = PTRMAP_ROOTPAGE Then
        rc = setChildPtrmaps(pPage)
        If rc <> SQLITE_OK Then Return rc
    Else
        If pBt->usableSize < 4 Then Return SQLITE_CORRUPT
        Dim nextOverflowPage As u32 = sqlite3Get4byte(pPage->aData)
        If nextOverflowPage <> 0 Then ptrmapPut(pBt, nextOverflowPage, PTRMAP_OVERFLOW2, newPageNumber, @rc)
        If rc <> SQLITE_OK Then Return rc
    End If

    If pointerType <> PTRMAP_ROOTPAGE Then
        Dim pParent As MemPage Ptr = 0
        rc = btreeGetPage(pBt, parentPage, @pParent, 0)
        If rc <> SQLITE_OK Then Return rc
        rc = sqlite3PagerWrite(pParent->pDbPage)
        If rc = SQLITE_OK Then rc = modifyPagePointer(pParent, oldPageNumber, newPageNumber, pointerType)
        sqlite3BtreeReleasePage(pParent)
        If rc <> SQLITE_OK Then Return rc
        ptrmapPut(pBt, newPageNumber, pointerType, parentPage, @rc)
    End If
    Return rc
End Function

Private Function btreeMarkAllocatedPage( _
    ByVal pBt As BtShared Ptr, _
    ByVal pageNumber As u32, _
    ByVal mapType As u8, _
    ByVal parentPage As u32 _
) As SQLITE_C_INT
    If pBt = 0 Then Return SQLITE_MISUSE
    If pBt->autoVacuum = 0 Then Return SQLITE_OK
    Dim rc As SQLITE_C_INT = SQLITE_OK
    ptrmapPut(pBt, pageNumber, mapType, parentPage, @rc)
    Return rc
End Function

Private Function btreeInitializePointerMapPage( _
    ByVal pBt As BtShared Ptr, _
    ByVal pageNumber As u32, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT
    Dim pMapPage As MemPage Ptr = 0
    Dim rc As SQLITE_C_INT = btreeGetUnusedPage(pBt, pageNumber, @pMapPage, flags)
    If rc <> SQLITE_OK Then Return rc
    If pMapPage = 0 OrElse pMapPage->aData = 0 OrElse pMapPage->pDbPage = 0 Then
        sqlite3BtreeReleasePage(pMapPage)
        Return SQLITE_CORRUPT
    End If
    rc = sqlite3PagerWrite(pMapPage->pDbPage)
    If rc = SQLITE_OK Then
        For iByte As u32 = 0 To pBt->usableSize - 1
            pMapPage->aData[iByte] = 0
        Next
        pMapPage->isInit = 0
    End If
    sqlite3BtreeReleasePage(pMapPage)
    Return rc
End Function
#endif

#ifdef SQLITE_OMIT_AUTOVACUUM
Private Function btreeMarkAllocatedPage( _
    ByVal pBt As BtShared Ptr, _
    ByVal pageNumber As u32, _
    ByVal mapType As u8, _
    ByVal parentPage As u32 _
) As SQLITE_C_INT
    If pBt = 0 Then Return SQLITE_MISUSE
    Return SQLITE_OK
End Function
#endif

Private Function allocateBtreePage CDecl Alias "allocateBtreePage" ( _
    ByVal pBt As BtShared Ptr, _
    ByVal ppPage As MemPage Ptr Ptr, _
    ByVal pPageNumber As u32 Ptr, _
    ByVal nearby As u32, _
    ByVal eMode As u8 _
) As SQLITE_C_INT
    If ppPage = 0 OrElse pPageNumber = 0 Then Return SQLITE_MISUSE
    ppPage[0] = 0
    pPageNumber[0] = 0
    If pBt = 0 OrElse pBt->pPager = 0 OrElse pBt->pPage1 = 0 Then Return SQLITE_MISUSE
    If eMode > BTALLOC_LE Then Return SQLITE_MISUSE
    If (pBt->btsFlags And BTS_READ_ONLY) <> 0 Then Return SQLITE_READONLY

    Dim pPage1 As MemPage Ptr = CPtr(MemPage Ptr, pBt->pPage1)
    If pPage1->aData = 0 OrElse pPage1->pDbPage = 0 Then Return SQLITE_CORRUPT
    Dim maximumPage As u32 = btreePagecount(pBt)
    Dim freePageCount As u32 = btreeReadU32(pPage1->aData + 36)
    If maximumPage = 0 OrElse freePageCount >= maximumPage Then _
        Return sqlite3CorruptError(6570)

    Dim pTrunk As MemPage Ptr = 0
    Dim pPreviousTrunk As MemPage Ptr = 0
    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim pendingBytePage As u32 = 0
    Dim pageFlags As SQLITE_C_INT = 0
    If freePageCount > 0 Then
        Dim searchList As SQLITE_C_INT = 0
        Dim searchCount As u32 = 0
#ifndef SQLITE_OMIT_AUTOVACUUM
        If pBt->autoVacuum <> 0 AndAlso eMode = BTALLOC_EXACT AndAlso _
           nearby > 0 AndAlso nearby <= maximumPage Then
            Dim entryType As u8 = 0
            rc = ptrmapGet(pBt, nearby, @entryType, 0)
            If rc <> SQLITE_OK Then Return rc
            If entryType = PTRMAP_FREEPAGE Then searchList = 1
        ElseIf pBt->autoVacuum <> 0 AndAlso eMode = BTALLOC_LE Then
            searchList = 1
        End If
#endif

        rc = sqlite3PagerWrite(pPage1->pDbPage)
        If rc <> SQLITE_OK Then Return rc
        btreeWriteU32(pPage1->aData + 36, freePageCount - 1)

        Do
            ' Transfer the prior trunk reference before loading the next trunk.
            pPreviousTrunk = pTrunk
            pTrunk = 0
            Dim trunkNumber As u32
            If pPreviousTrunk <> 0 Then
                If pPreviousTrunk->aData = 0 Then
                    rc = sqlite3CorruptError(6617)
                    GoTo allocate_page_cleanup
                End If
                trunkNumber = btreeReadU32(pPreviousTrunk->aData)
            Else
                trunkNumber = btreeReadU32(pPage1->aData + 32)
            End If

            If trunkNumber > maximumPage OrElse searchCount > freePageCount Then
                rc = sqlite3CorruptError(6626)
                GoTo allocate_page_cleanup
            End If
            searchCount += 1
            rc = btreeGetUnusedPage(pBt, trunkNumber, @pTrunk, 0)
            If rc <> SQLITE_OK Then GoTo allocate_page_cleanup
            If pTrunk = 0 OrElse pTrunk->aData = 0 OrElse pTrunk->pDbPage = 0 Then
                rc = sqlite3CorruptError(6630)
                GoTo allocate_page_cleanup
            End If

            Dim leafCount As u32 = btreeReadU32(pTrunk->aData + 4)
            Dim maximumLeafCount As u32 = pBt->usableSize \ 4 - 2
            If leafCount = 0 AndAlso searchList = 0 Then
                If pPreviousTrunk <> 0 Then
                    rc = sqlite3CorruptError(6643)
                    GoTo allocate_page_cleanup
                End If
                rc = sqlite3PagerWrite(pTrunk->pDbPage)
                If rc <> SQLITE_OK Then GoTo allocate_page_cleanup
                pPageNumber[0] = trunkNumber
                btreeWriteU32(pPage1->aData + 32, btreeReadU32(pTrunk->aData))
                ppPage[0] = pTrunk
                pTrunk = 0
            ElseIf leafCount > maximumLeafCount Then
                rc = sqlite3CorruptError(6655)
                GoTo allocate_page_cleanup
#ifndef SQLITE_OMIT_AUTOVACUUM
            ElseIf searchList <> 0 AndAlso _
                   (nearby = trunkNumber OrElse _
                    (trunkNumber < nearby AndAlso eMode = BTALLOC_LE)) Then
                rc = sqlite3PagerWrite(pTrunk->pDbPage)
                If rc <> SQLITE_OK Then GoTo allocate_page_cleanup
                If leafCount = 0 Then
                    If pPreviousTrunk = 0 Then
                        btreeWriteU32(pPage1->aData + 32, btreeReadU32(pTrunk->aData))
                    Else
                        rc = sqlite3PagerWrite(pPreviousTrunk->pDbPage)
                        If rc <> SQLITE_OK Then GoTo allocate_page_cleanup
                        btreeWriteU32(pPreviousTrunk->aData, btreeReadU32(pTrunk->aData))
                    End If
                Else
                    Dim newTrunkNumber As u32 = btreeReadU32(pTrunk->aData + 8)
                    If newTrunkNumber > maximumPage Then
                        rc = sqlite3CorruptError(6689)
                        GoTo allocate_page_cleanup
                    End If
                    Dim pNewTrunk As MemPage Ptr = 0
                    rc = btreeGetUnusedPage(pBt, newTrunkNumber, @pNewTrunk, 0)
                    If rc <> SQLITE_OK Then GoTo allocate_page_cleanup
                    If pNewTrunk = 0 OrElse pNewTrunk->aData = 0 Then
                        rc = sqlite3CorruptError(6693)
                        GoTo allocate_page_cleanup
                    End If
                    rc = sqlite3PagerWrite(pNewTrunk->pDbPage)
                    If rc = SQLITE_OK Then
                        btreeWriteU32(pNewTrunk->aData, btreeReadU32(pTrunk->aData))
                        btreeWriteU32(pNewTrunk->aData + 4, leafCount - 1)
                        For byteIndex As u32 = 0 To (leafCount - 1) * 4 - 1
                            pNewTrunk->aData[8 + byteIndex] = pTrunk->aData[12 + byteIndex]
                        Next
                    End If
                    sqlite3BtreeReleasePage(pNewTrunk)
                    If rc <> SQLITE_OK Then GoTo allocate_page_cleanup
                    If pPreviousTrunk = 0 Then
                        btreeWriteU32(pPage1->aData + 32, newTrunkNumber)
                    Else
                        rc = sqlite3PagerWrite(pPreviousTrunk->pDbPage)
                        If rc <> SQLITE_OK Then GoTo allocate_page_cleanup
                        btreeWriteU32(pPreviousTrunk->aData, newTrunkNumber)
                    End If
                End If
                pPageNumber[0] = trunkNumber
                ppPage[0] = pTrunk
                pTrunk = 0
                searchList = 0
#endif
            ElseIf leafCount > 0 Then
                Dim closest As u32 = 0
                Dim pLeafData As UByte Ptr = pTrunk->aData
                If nearby > 0 Then
                    If eMode = BTALLOC_LE Then
                        For leafIndex As u32 = 0 To leafCount - 1
                            If btreeReadU32(pLeafData + 8 + leafIndex * 4) <= nearby Then
                                closest = leafIndex
                                Exit For
                            End If
                        Next
                    Else
                        Dim closestPage As u32 = btreeReadU32(pLeafData + 8)
                        Dim firstDifference As sqlite3_int64 = CLngInt(closestPage) - CLngInt(nearby)
                        If firstDifference < 0 Then firstDifference = -firstDifference
                        Dim closestDistance As sqlite3_uint64 = CULngInt(firstDifference)
                        For leafIndex As u32 = 1 To leafCount - 1
                            Dim candidatePage As u32 = btreeReadU32(pLeafData + 8 + leafIndex * 4)
                            Dim difference As sqlite3_int64 = CLngInt(candidatePage) - CLngInt(nearby)
                            If difference < 0 Then difference = -difference
                            If CULngInt(difference) < closestDistance Then
                                closest = leafIndex
                                closestDistance = CULngInt(difference)
                            End If
                        Next
                    End If
                End If

                Dim leafPageNumber As u32 = _
                    btreeReadU32(pLeafData + 8 + closest * 4)
                If leafPageNumber > maximumPage OrElse leafPageNumber < 2 Then
                    rc = sqlite3CorruptError(6754)
                    GoTo allocate_page_cleanup
                End If
                If searchList = 0 OrElse leafPageNumber = nearby OrElse _
                   (leafPageNumber < nearby AndAlso eMode = BTALLOC_LE) Then
                    pPageNumber[0] = leafPageNumber
                    rc = sqlite3PagerWrite(pTrunk->pDbPage)
                    If rc <> SQLITE_OK Then GoTo allocate_page_cleanup
                    If closest < leafCount - 1 Then
                        ' The leaf array starts at byte 8. Its last entry is at
                        ' byte 4 + 4*leafCount because leafCount is one-based.
                        btreeWriteU32(pLeafData + 8 + closest * 4, _
                            btreeReadU32(pLeafData + 4 + leafCount * 4))
                    End If
                    btreeWriteU32(pLeafData + 4, leafCount - 1)
                    Dim pageFlags As SQLITE_C_INT = 0
                    If btreeGetHasContent(pBt, leafPageNumber) = 0 Then _
                        pageFlags = PAGER_GET_NOCONTENT
                    rc = btreeGetUnusedPage(pBt, leafPageNumber, ppPage, pageFlags)
                    If rc <> SQLITE_OK Then GoTo allocate_page_cleanup
                    If ppPage[0] = 0 OrElse ppPage[0]->pDbPage = 0 Then
                        rc = sqlite3CorruptError(6773)
                        GoTo allocate_page_cleanup
                    End If
                    rc = sqlite3PagerWrite(ppPage[0]->pDbPage)
                    If rc <> SQLITE_OK Then GoTo allocate_page_cleanup
                    searchList = 0
                End If
            End If

            releasePage(pPreviousTrunk)
            pPreviousTrunk = 0
        Loop While searchList <> 0
        GoTo allocate_page_cleanup
    End If

    If pBt->nPage >= SQLITE_MAX_PAGE_COUNT Then Return SQLITE_FULL
    rc = sqlite3PagerWrite(pPage1->pDbPage)
    If rc <> SQLITE_OK Then Return rc
    pendingBytePage = (PENDING_BYTE \ pBt->pageSize) + 1
    pageFlags = PAGER_GET_NOCONTENT
#ifndef SQLITE_OMIT_AUTOVACUUM
    If pBt->autoVacuum <> 0 AndAlso pBt->bDoTruncate <> 0 Then pageFlags = 0
#endif
    pBt->nPage += 1
    If pBt->nPage = pendingBytePage Then pBt->nPage += 1
#ifndef SQLITE_OMIT_AUTOVACUUM
    If pBt->autoVacuum <> 0 AndAlso ptrmapIsPage(pBt, pBt->nPage) <> 0 Then
        If pBt->nPage >= SQLITE_MAX_PAGE_COUNT Then Return SQLITE_FULL
        Dim pMapPage As MemPage Ptr = 0
        rc = btreeGetUnusedPage(pBt, pBt->nPage, @pMapPage, pageFlags)
        If rc <> SQLITE_OK Then Return rc
        If pMapPage = 0 OrElse pMapPage->pDbPage = 0 Then
            sqlite3BtreeReleasePage(pMapPage)
            Return sqlite3CorruptError(6822)
        End If
        rc = sqlite3PagerWrite(pMapPage->pDbPage)
        sqlite3BtreeReleasePage(pMapPage)
        If rc <> SQLITE_OK Then Return rc
        pBt->nPage += 1
        If pBt->nPage = pendingBytePage Then pBt->nPage += 1
    End If
#endif
    If pBt->nPage >= SQLITE_MAX_PAGE_COUNT Then Return SQLITE_FULL
    btreeWriteU32(pPage1->aData + 28, pBt->nPage)
    pPageNumber[0] = pBt->nPage
    If pPageNumber[0] = pendingBytePage Then Return sqlite3CorruptError(6835)
    rc = btreeGetUnusedPage(pBt, pPageNumber[0], ppPage, pageFlags)
    If rc = SQLITE_OK Then
        If ppPage[0] = 0 OrElse ppPage[0]->pDbPage = 0 Then
            rc = sqlite3CorruptError(6836)
        Else
            rc = sqlite3PagerWrite(ppPage[0]->pDbPage)
        End If
    End If
    If rc <> SQLITE_OK AndAlso ppPage[0] <> 0 Then
        sqlite3BtreeReleasePage(ppPage[0])
        ppPage[0] = 0
    End If
    If rc <> SQLITE_OK Then pPageNumber[0] = 0
    Return rc

allocate_page_cleanup:
    releasePage(pTrunk)
    releasePage(pPreviousTrunk)
    If rc <> SQLITE_OK Then
        If ppPage[0] <> 0 Then sqlite3BtreeReleasePage(ppPage[0])
        ppPage[0] = 0
        pPageNumber[0] = 0
    ElseIf ppPage[0] = 0 OrElse pPageNumber[0] = 0 Then
        ppPage[0] = 0
        pPageNumber[0] = 0
        Return sqlite3CorruptError(6851)
    End If
    Return rc
End Function

Private Function btreeAllocatePageMode( _
    ByVal pBt As BtShared Ptr, _
    ByVal ppPage As MemPage Ptr Ptr, _
    ByVal pPageNumber As u32 Ptr, _
    ByVal mapType As u8, _
    ByVal parentPage As u32, _
    ByVal nearby As u32, _
    ByVal allocationMode As u8 _
) As SQLITE_C_INT
    If ppPage = 0 OrElse pPageNumber = 0 Then Return SQLITE_MISUSE
    ppPage[0] = 0
    pPageNumber[0] = 0
    Dim rc As SQLITE_C_INT = _
        allocateBtreePage(pBt, ppPage, pPageNumber, nearby, allocationMode)
    If rc <> SQLITE_OK Then Return rc
    rc = btreeMarkAllocatedPage(pBt, pPageNumber[0], mapType, parentPage)
    If rc <> SQLITE_OK Then
        sqlite3BtreeReleasePage(ppPage[0])
        ppPage[0] = 0
        pPageNumber[0] = 0
    End If
    Return rc
End Function

Private Function btreeAllocatePageAny( _
    ByVal pBt As BtShared Ptr, _
    ByVal ppPage As MemPage Ptr Ptr, _
    ByVal pPageNumber As u32 Ptr, _
    ByVal mapType As u8, _
    ByVal parentPage As u32 _
) As SQLITE_C_INT
    Return btreeAllocatePageMode( _
        pBt, ppPage, pPageNumber, mapType, parentPage, 0, BTALLOC_ANY)
End Function

' The optional page pointer is borrowed. A temporary page reference is released on every exit.
Private Function freePage2 CDecl Alias "freePage2" ( _
    ByVal pBt As BtShared Ptr, _
    ByVal pMemPage As MemPage Ptr, _
    ByVal pageNumber As u32 _
) As SQLITE_C_INT
    If pBt = 0 OrElse pBt->pPager = 0 OrElse pBt->pPage1 = 0 Then Return SQLITE_MISUSE
    If (pBt->btsFlags And BTS_READ_ONLY) <> 0 Then Return SQLITE_READONLY
    If pageNumber < 2 OrElse pageNumber > pBt->nPage OrElse _
       pBt->usableSize < 480 OrElse pBt->pageSize < 512 Then Return SQLITE_CORRUPT
    Dim pPage As MemPage Ptr = pMemPage
    Dim ownsPageReference As Long = 0
    Dim pTrunk As MemPage Ptr = 0
    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim freePageCount As u32 = 0
    Dim trunkNumber As u32 = 0
    Dim leafCount As u32 = 0
    Dim maximumLeafCount As u32 = 0
    If pPage <> 0 Then
        If pPage->pBt <> pBt OrElse pPage->pDbPage = 0 OrElse _
           pPage->aData = 0 OrElse pPage->pgno <> pageNumber Then Return SQLITE_CORRUPT
        sqlite3PagerRef(pPage->pDbPage)
        ownsPageReference = -1
    Else
        pPage = btreePageLookup(pBt, pageNumber)
        If pPage <> 0 Then ownsPageReference = -1
    End If

    Dim pPage1 As MemPage Ptr = CPtr(MemPage Ptr, pBt->pPage1)
    If pPage1 = 0 OrElse pPage1->aData = 0 OrElse pPage1->pDbPage = 0 Then
        rc = SQLITE_CORRUPT
        GoTo freePage2_finish
    End If

    rc = sqlite3PagerWrite(pPage1->pDbPage)
    If rc <> SQLITE_OK Then GoTo freePage2_finish
    freePageCount = btreeReadU32(pPage1->aData + 36)
    If freePageCount >= pBt->nPage Then
        rc = SQLITE_CORRUPT
        GoTo freePage2_finish
    End If
    btreeWriteU32(pPage1->aData + 36, freePageCount + 1)

    If (pBt->btsFlags And BTS_SECURE_DELETE) <> 0 Then
        If pPage = 0 Then
            rc = btreeGetPage(pBt, pageNumber, @pPage, 0)
            If rc <> SQLITE_OK Then GoTo freePage2_finish
            ownsPageReference = -1
        End If
        rc = sqlite3PagerWrite(pPage->pDbPage)
        If rc <> SQLITE_OK Then GoTo freePage2_finish
        For iByte As Long = 0 To CLng(pBt->pageSize) - 1
            pPage->aData[iByte] = 0
        Next
    End If
    rc = btreeMarkAllocatedPage(pBt, pageNumber, PTRMAP_FREEPAGE, 0)
    If rc <> SQLITE_OK Then GoTo freePage2_finish

    trunkNumber = btreeReadU32(pPage1->aData + 32)
    maximumLeafCount = pBt->usableSize \ 4 - 8
    If freePageCount > 0 Then
        If trunkNumber < 2 OrElse trunkNumber > pBt->nPage OrElse trunkNumber = pageNumber Then
            rc = SQLITE_CORRUPT
            GoTo freePage2_finish
        End If
        rc = btreeGetPage(pBt, trunkNumber, @pTrunk, 0)
        If rc <> SQLITE_OK Then GoTo freePage2_finish
        If pTrunk = 0 OrElse pTrunk->aData = 0 Then
            rc = SQLITE_CORRUPT
            GoTo freePage2_finish
        End If
        leafCount = btreeReadU32(pTrunk->aData + 4)
        If leafCount > pBt->usableSize \ 4 - 2 Then
            rc = SQLITE_CORRUPT
            GoTo freePage2_finish
        End If
    Else
        trunkNumber = 0
    End If

    If freePageCount > 0 AndAlso leafCount < maximumLeafCount Then
        rc = sqlite3PagerWrite(pTrunk->pDbPage)
        If rc <> SQLITE_OK Then GoTo freePage2_finish
        btreeWriteU32(pTrunk->aData + 4, leafCount + 1)
        btreeWriteU32(pTrunk->aData + 8 + (4 * leafCount), pageNumber)
        If pPage <> 0 AndAlso (pBt->btsFlags And BTS_SECURE_DELETE) = 0 Then _
            sqlite3PagerDontWrite(pPage->pDbPage)
        rc = btreeSetHasContent(pBt, pageNumber)
        GoTo freePage2_finish
    End If

    If pPage = 0 Then
        rc = btreeGetPage(pBt, pageNumber, @pPage, 0)
        If rc <> SQLITE_OK Then GoTo freePage2_finish
        ownsPageReference = -1
    End If
    rc = sqlite3PagerWrite(pPage->pDbPage)
    If rc <> SQLITE_OK Then GoTo freePage2_finish
    btreeWriteU32(pPage->aData, trunkNumber)
    btreeWriteU32(pPage->aData + 4, 0)
    btreeWriteU32(pPage1->aData + 32, pageNumber)

freePage2_finish:
    If pPage <> 0 Then
        pPage->isInit = 0
        If ownsPageReference <> 0 Then sqlite3BtreeReleasePage(pPage)
    End If
    sqlite3BtreeReleasePage(pTrunk)
    Return rc
End Function

Private Function btreeFreePageNumber( _
    ByVal pBt As BtShared Ptr, _
    ByVal pPageToFree As MemPage Ptr, _
    ByVal pageNumber As u32 _
) As SQLITE_C_INT
    Return freePage2(pBt, pPageToFree, pageNumber)
End Function

Private Sub freePage CDecl Alias "freePage" ( _
    ByVal pPage As MemPage Ptr, _
    ByRef resultCode As SQLITE_C_INT _
)
    If resultCode <> SQLITE_OK OrElse pPage = 0 OrElse pPage->pBt = 0 Then Exit Sub
    resultCode = freePage2(pPage->pBt, pPage, pPage->pgno)
End Sub

Private Function btreeFindFreelistPageLE( _
    ByVal pBt As BtShared Ptr, _
    ByVal pageLimit As u32, _
    ByVal pResultPage As u32 Ptr _
) As SQLITE_C_INT
    If pResultPage = 0 Then Return SQLITE_MISUSE
    pResultPage[0] = 0
    If pBt = 0 OrElse pBt->pPage1 = 0 Then Return SQLITE_MISUSE
    Dim pPage1 As MemPage Ptr = CPtr(MemPage Ptr, pBt->pPage1)
    If pPage1->aData = 0 Then Return SQLITE_CORRUPT
    Dim freeCount As u32 = btreeReadU32(pPage1->aData + 36)
    Dim trunkNumber As u32 = btreeReadU32(pPage1->aData + 32)
    Dim nTrunk As u32 = 0

    While trunkNumber <> 0
        nTrunk += 1
        If nTrunk > freeCount OrElse trunkNumber < 2 OrElse trunkNumber > pBt->nPage Then Return SQLITE_CORRUPT
        Dim pTrunk As MemPage Ptr = 0
        Dim rc As SQLITE_C_INT = btreeGetUnusedPage(pBt, trunkNumber, @pTrunk, 0)
        If rc <> SQLITE_OK Then Return rc
        If pTrunk = 0 OrElse pTrunk->aData = 0 Then
            sqlite3BtreeReleasePage(pTrunk)
            Return SQLITE_CORRUPT
        End If
        Dim nextTrunk As u32 = btreeReadU32(pTrunk->aData)
        Dim leafCount As u32 = btreeReadU32(pTrunk->aData + 4)
        If leafCount > pBt->usableSize \ 4 - 2 OrElse 8 + CULngInt(leafCount) * 4 > pBt->usableSize Then
            sqlite3BtreeReleasePage(pTrunk)
            Return SQLITE_CORRUPT
        End If
        If trunkNumber <= pageLimit Then
            pResultPage[0] = trunkNumber
            sqlite3BtreeReleasePage(pTrunk)
            Exit While
        End If
        For iLeaf As u32 = 0 To leafCount - 1
            Dim leafNumber As u32 = btreeReadU32(pTrunk->aData + 8 + (4 * iLeaf))
            If leafNumber < 2 OrElse leafNumber > pBt->nPage Then
                sqlite3BtreeReleasePage(pTrunk)
                Return SQLITE_CORRUPT
            End If
            If leafNumber <= pageLimit Then
                pResultPage[0] = leafNumber
                Exit For
            End If
        Next
        sqlite3BtreeReleasePage(pTrunk)
        If pResultPage[0] <> 0 Then Exit While
        trunkNumber = nextTrunk
    Wend

    If pResultPage[0] = 0 Then Return SQLITE_DONE
#ifndef SQLITE_OMIT_AUTOVACUUM
    If pBt->autoVacuum <> 0 Then
        Dim entryType As u8 = 0
        Dim rc As SQLITE_C_INT = ptrmapGet(pBt, pResultPage[0], @entryType, 0)
        If rc <> SQLITE_OK Then Return rc
        If entryType <> PTRMAP_FREEPAGE Then
            pResultPage[0] = 0
            Return SQLITE_CORRUPT
        End If
    End If
#endif
    Return SQLITE_OK
End Function

Private Function btreeRemoveFreelistPage( _
    ByVal pBt As BtShared Ptr, _
    ByVal pageNumber As u32, _
    ByVal ppPage As MemPage Ptr Ptr _
) As SQLITE_C_INT
    If ppPage = 0 Then Return SQLITE_MISUSE
    ppPage[0] = 0
    If pBt = 0 OrElse pBt->pPage1 = 0 OrElse pageNumber < 2 OrElse pageNumber > pBt->nPage Then Return SQLITE_CORRUPT
    Dim pPage1 As MemPage Ptr = CPtr(MemPage Ptr, pBt->pPage1)
    If pPage1->aData = 0 OrElse pPage1->pDbPage = 0 Then Return SQLITE_CORRUPT
    Dim freeCount As u32 = btreeReadU32(pPage1->aData + 36)
    If freeCount = 0 OrElse freeCount >= pBt->nPage Then Return SQLITE_CORRUPT
    Dim rc As SQLITE_C_INT = sqlite3PagerWrite(pPage1->pDbPage)
    If rc <> SQLITE_OK Then Return rc

    Dim pPreviousTrunk As MemPage Ptr = 0
    Dim trunkNumber As u32 = btreeReadU32(pPage1->aData + 32)
    Dim nSearch As u32 = 0
    While trunkNumber <> 0
        nSearch += 1
        If nSearch > freeCount OrElse trunkNumber < 2 OrElse trunkNumber > pBt->nPage Then
            sqlite3BtreeReleasePage(pPreviousTrunk)
            Return SQLITE_CORRUPT
        End If
        Dim pTrunk As MemPage Ptr = 0
        rc = btreeGetUnusedPage(pBt, trunkNumber, @pTrunk, 0)
        If rc <> SQLITE_OK Then
            sqlite3BtreeReleasePage(pPreviousTrunk)
            Return rc
        End If
        If pTrunk = 0 OrElse pTrunk->aData = 0 Then
            sqlite3BtreeReleasePage(pTrunk)
            sqlite3BtreeReleasePage(pPreviousTrunk)
            Return SQLITE_CORRUPT
        End If
        Dim nextTrunk As u32 = btreeReadU32(pTrunk->aData)
        Dim leafCount As u32 = btreeReadU32(pTrunk->aData + 4)
        If leafCount > pBt->usableSize \ 4 - 2 OrElse 8 + CULngInt(leafCount) * 4 > pBt->usableSize Then
            sqlite3BtreeReleasePage(pTrunk)
            sqlite3BtreeReleasePage(pPreviousTrunk)
            Return SQLITE_CORRUPT
        End If

        If trunkNumber = pageNumber Then
            rc = sqlite3PagerWrite(pTrunk->pDbPage)
            If rc = SQLITE_OK Then
                If leafCount = 0 Then
                    If pPreviousTrunk = 0 Then
                        btreeWriteU32(pPage1->aData + 32, nextTrunk)
                    Else
                        rc = sqlite3PagerWrite(pPreviousTrunk->pDbPage)
                        If rc = SQLITE_OK Then btreeWriteU32(pPreviousTrunk->aData, nextTrunk)
                    End If
                Else
                    Dim newTrunkNumber As u32 = btreeReadU32(pTrunk->aData + 8)
                    If newTrunkNumber < 2 OrElse newTrunkNumber > pBt->nPage Then
                        rc = SQLITE_CORRUPT
                    Else
                        Dim pNewTrunk As MemPage Ptr = 0
                        rc = btreeGetUnusedPage(pBt, newTrunkNumber, @pNewTrunk, 0)
                        If rc = SQLITE_OK Then
                            If pNewTrunk = 0 OrElse pNewTrunk->aData = 0 Then
                                rc = SQLITE_CORRUPT
                            Else
                                rc = sqlite3PagerWrite(pNewTrunk->pDbPage)
                            End If
                        End If
                        If rc = SQLITE_OK Then
                            btreeWriteU32(pNewTrunk->aData, nextTrunk)
                            btreeWriteU32(pNewTrunk->aData + 4, leafCount - 1)
                            If leafCount > 1 Then
                                btreeSystemMemcpy(pNewTrunk->aData + 8, pTrunk->aData + 12, CULngInt(leafCount - 1) * 4)
                            End If
                            If pPreviousTrunk = 0 Then
                                btreeWriteU32(pPage1->aData + 32, newTrunkNumber)
                            Else
                                rc = sqlite3PagerWrite(pPreviousTrunk->pDbPage)
                                If rc = SQLITE_OK Then btreeWriteU32(pPreviousTrunk->aData, newTrunkNumber)
                            End If
                        End If
                        sqlite3BtreeReleasePage(pNewTrunk)
                    End If
                End If
            End If
            If rc = SQLITE_OK Then rc = sqlite3PagerWrite(pTrunk->pDbPage)
            If rc = SQLITE_OK Then
                btreeWriteU32(pPage1->aData + 36, freeCount - 1)
                pTrunk->isInit = 0
                ppPage[0] = pTrunk
                pTrunk = 0
            End If
            sqlite3BtreeReleasePage(pTrunk)
            sqlite3BtreeReleasePage(pPreviousTrunk)
            Return rc
        End If

        Dim leafIndex As Long = -1
        For iLeaf As Long = 0 To CLng(leafCount) - 1
            If btreeReadU32(pTrunk->aData + 8 + (4 * iLeaf)) = pageNumber Then
                leafIndex = iLeaf
                Exit For
            End If
        Next
        If leafIndex >= 0 Then
            Dim pLeafPage As MemPage Ptr = 0
            rc = btreeGetUnusedPage(pBt, pageNumber, @pLeafPage, 0)
            If rc = SQLITE_OK Then
                If pLeafPage = 0 OrElse pLeafPage->pDbPage = 0 Then
                    rc = SQLITE_CORRUPT
                Else
                    rc = sqlite3PagerWrite(pLeafPage->pDbPage)
                End If
            End If
            If rc = SQLITE_OK Then rc = sqlite3PagerWrite(pTrunk->pDbPage)
            If rc = SQLITE_OK Then
                If leafIndex < leafCount - 1 Then
                    btreeWriteU32(pTrunk->aData + 8 + (4 * leafIndex), _
                                  btreeReadU32(pTrunk->aData + 8 + (4 * (leafCount - 1))))
                End If
                btreeWriteU32(pTrunk->aData + 4, leafCount - 1)
                btreeWriteU32(pPage1->aData + 36, freeCount - 1)
                pLeafPage->isInit = 0
                ppPage[0] = pLeafPage
                pLeafPage = 0
            End If
            sqlite3BtreeReleasePage(pLeafPage)
            sqlite3BtreeReleasePage(pTrunk)
            sqlite3BtreeReleasePage(pPreviousTrunk)
            Return rc
        End If

        sqlite3BtreeReleasePage(pPreviousTrunk)
        pPreviousTrunk = pTrunk
        pTrunk = 0
        trunkNumber = nextTrunk
    Wend
    sqlite3BtreeReleasePage(pPreviousTrunk)
    Return SQLITE_CORRUPT
End Function

#ifndef SQLITE_OMIT_AUTOVACUUM
Function sqlite3BtreeIncrVacuum CDecl Alias "sqlite3BtreeIncrVacuum" ( _
    ByVal pBtree As Btree Ptr _
) As SQLITE_C_INT Export
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return SQLITE_MISUSE
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    If pBtree->inTrans <> TRANS_WRITE OrElse pBt->inTransaction <> TRANS_WRITE OrElse pBt->pPage1 = 0 Then
        sqlite3BtreeLeave(pBtree)
        Return SQLITE_MISUSE
    End If
    If pBt->autoVacuum = 0 Then
        sqlite3BtreeLeave(pBtree)
        Return SQLITE_DONE
    End If

    Dim originalPageCount As u32 = pBt->nPage
    Dim freePageCount As u32 = btreeReadU32(CPtr(MemPage Ptr, pBt->pPage1)->aData + 36)
    Dim finalPageCount As u32 = finalDbSize(pBt, originalPageCount, freePageCount)
    Dim rc As SQLITE_C_INT
    If originalPageCount < finalPageCount OrElse freePageCount >= originalPageCount Then
        rc = SQLITE_CORRUPT
    ElseIf freePageCount = 0 Then
        rc = SQLITE_DONE
    Else
        rc = btreeSaveAllCursors(pBt, 0, 0)
        If rc = SQLITE_OK Then
            invalidateAllOverflowCache(pBt)
            rc = incrVacuumStep(pBt, finalPageCount, originalPageCount, 0)
        End If
        If rc = SQLITE_OK Then
            Dim pPage1 As MemPage Ptr = CPtr(MemPage Ptr, pBt->pPage1)
            rc = sqlite3PagerWrite(pPage1->pDbPage)
            If rc = SQLITE_OK Then btreeWriteU32(pPage1->aData + 28, pBt->nPage)
        End If
    End If
    sqlite3BtreeLeave(pBtree)
    Return rc
End Function
#endif

Private Function btreeHeaderHasMagic(ByVal pData As Const UByte Ptr) As SQLITE_C_INT
    If pData = 0 Then Return 0
    For i As Long = 0 To 15
        If pData[i] <> btreeFileMagic(i) Then Return 0
    Next
    Return 1
End Function

Private Sub btreeSetPayloadLimits(ByVal pBt As BtShared Ptr)
    If pBt = 0 OrElse pBt->usableSize < 480 Then Exit Sub
    pBt->maxLocal = CUShort(((pBt->usableSize - 12) * 64) \ 255 - 23)
    pBt->minLocal = CUShort(((pBt->usableSize - 12) * 32) \ 255 - 23)
    pBt->maxLeaf = CUShort(pBt->usableSize - 35)
    pBt->minLeaf = pBt->minLocal
    pBt->max1bytePayload = CByte(IIf(pBt->maxLocal > 127, 127, pBt->maxLocal))
End Sub

Private Sub btreeUnlockPageOne(ByVal pBt As BtShared Ptr)
    If pBt = 0 OrElse pBt->pPage1 = 0 Then Exit Sub
    Dim pPage1 As MemPage Ptr = CPtr(MemPage Ptr, pBt->pPage1)
    pBt->pPage1 = 0
    sqlite3BtreeReleasePage(pPage1)
End Sub

' Apply the selected journal mode's default durability to its attached database.
Private Sub setDefaultSyncFlag CDecl Alias "setDefaultSyncFlag" ( _
    ByVal pBt As BtShared Ptr, _
    ByVal safetyLevel As UByte _
)
    If pBt = 0 OrElse pBt->db = 0 OrElse _
       SQLITE_DEFAULT_SYNCHRONOUS = SQLITE_DEFAULT_WAL_SYNCHRONOUS Then Exit Sub

    Dim db As sqlite3 Ptr = pBt->db
    If db->nDb <= 0 OrElse db->nDb > SQLITE_MAX_DB Then Exit Sub
    For iDb As SQLITE_C_INT = 0 To db->nDb - 1
        Dim pDatabaseBtree As Btree Ptr = _
            CPtr(Btree Ptr, db->aDb(iDb).pBt)
        If pDatabaseBtree = 0 OrElse pDatabaseBtree->pBt <> pBt Then Continue For

        ' Database slot 1 belongs to TEMP and keeps its own synchronous setting.
        If iDb <> 1 AndAlso db->aDb(iDb).bSyncSet = 0 AndAlso _
           db->aDb(iDb).safety_level <> safetyLevel Then
            db->aDb(iDb).safety_level = safetyLevel
            Dim flags As SQLITE_C_UINT = _
                CUInt(safetyLevel) Or CUInt(db->flags And PAGER_FLAGS_MASK)
            sqlite3PagerSetFlags(pBt->pPager, flags)
        End If
        Exit For
    Next
End Sub

Function btreeLockPageOne CDecl Alias "lockBtree" ( _
    ByVal pBt As BtShared Ptr _
) As SQLITE_C_INT
    If pBt = 0 OrElse pBt->pPager = 0 Then Return SQLITE_MISUSE
    If pBt->pPage1 <> 0 Then Return SQLITE_OK

    Dim rc As SQLITE_C_INT = sqlite3PagerSharedLock(pBt->pPager)
    If rc <> SQLITE_OK Then Return rc
    Dim pPage1 As MemPage Ptr = 0
    rc = btreeGetPage(pBt, 1, @pPage1, 0)
    If rc <> SQLITE_OK Then Return rc

    Dim pPageData As UByte Ptr = pPage1->aData
    If pPageData = 0 Then
        sqlite3BtreeReleasePage(pPage1)
        Return SQLITE_CORRUPT
    End If

    Dim filePageCount As SQLITE_C_INT = 0
    sqlite3PagerPagecount(pBt->pPager, @filePageCount)
    If filePageCount < 0 Then
        sqlite3BtreeReleasePage(pPage1)
        Return SQLITE_CORRUPT
    End If
    Dim pageCount As u32 = btreeReadU32(pPageData + 28)
    If pageCount = 0 OrElse btreeReadU32(pPageData + 24) <> btreeReadU32(pPageData + 92) Then
        pageCount = CULng(filePageCount)
    End If

    If pageCount > 0 Then
        If btreeHeaderHasMagic(pPageData) = 0 Then
            sqlite3BtreeReleasePage(pPage1)
            Return SQLITE_NOTADB
        End If
#ifdef SQLITE_OMIT_WAL
        If pPageData[19] > 1 Then
            sqlite3BtreeReleasePage(pPage1)
            Return SQLITE_NOTADB
        End If
        If pPageData[18] > 1 Then pBt->btsFlags = pBt->btsFlags Or BTS_READ_ONLY
#else
        If pPageData[18] > 2 Then pBt->btsFlags = pBt->btsFlags Or BTS_READ_ONLY
        If pPageData[19] > 2 Then
            sqlite3BtreeReleasePage(pPage1)
            Return SQLITE_NOTADB
        End If
        If pPageData[19] = 2 AndAlso (pBt->btsFlags And BTS_NO_WAL) = 0 Then
            ' Opening WAL may replace page one; release and retry after the first open.
            Dim alreadyOpen As SQLITE_C_INT = 0
            rc = sqlite3PagerOpenWal(pBt->pPager, @alreadyOpen)
            If rc <> SQLITE_OK Then
                sqlite3BtreeReleasePage(pPage1)
                Return rc
            End If
            setDefaultSyncFlag(pBt, CByte(SQLITE_DEFAULT_WAL_SYNCHRONOUS + 1))
            If alreadyOpen = 0 Then
                sqlite3BtreeReleasePage(pPage1)
                Return SQLITE_OK
            End If
        Else
            setDefaultSyncFlag(pBt, CByte(SQLITE_DEFAULT_SYNCHRONOUS + 1))
        End If
#endif
        If pPageData[21] <> 64 OrElse pPageData[22] <> 32 OrElse pPageData[23] <> 32 Then
            sqlite3BtreeReleasePage(pPage1)
            Return SQLITE_NOTADB
        End If

        Dim filePageSize As u32 = (CULng(pPageData[16]) Shl 8) Or (CULng(pPageData[17]) Shl 16)
        If filePageSize = 1 Then filePageSize = 65536
        If filePageSize < 512 OrElse filePageSize > SQLITE_MAX_PAGE_SIZE OrElse _
           (filePageSize And (filePageSize - 1)) <> 0 Then
            sqlite3BtreeReleasePage(pPage1)
            Return SQLITE_NOTADB
        End If
        Dim nReserve As SQLITE_C_INT = pPageData[20]
        If nReserve >= filePageSize OrElse filePageSize - nReserve < 480 Then
            sqlite3BtreeReleasePage(pPage1)
            Return SQLITE_NOTADB
        End If
        Dim usableSize As u32 = filePageSize - nReserve
        If filePageSize <> pBt->pageSize Then
            sqlite3BtreeReleasePage(pPage1)
            pBt->pageSize = filePageSize
            pBt->usableSize = usableSize
            pBt->nReserveWanted = CByte(nReserve)
            pBt->btsFlags = pBt->btsFlags Or BTS_PAGESIZE_FIXED
            rc = sqlite3PagerSetPagesize(pBt->pPager, @pBt->pageSize, nReserve)
            If rc = SQLITE_OK Then btreeSetPayloadLimits(pBt)
            Return rc
        End If
        pBt->usableSize = usableSize
        pBt->nReserveWanted = CByte(nReserve)
        pBt->btsFlags = pBt->btsFlags Or BTS_PAGESIZE_FIXED
#ifndef SQLITE_OMIT_AUTOVACUUM
        pBt->autoVacuum = IIf(btreeReadU32(pPageData + 52) <> 0, 1, 0)
        pBt->incrVacuum = IIf(btreeReadU32(pPageData + 64) <> 0, 1, 0)
#endif
        If pageCount > CULng(filePageCount) Then
            sqlite3BtreeReleasePage(pPage1)
            Return SQLITE_CORRUPT
        End If
    Else
        pageCount = 0
    End If

    btreeSetPayloadLimits(pBt)
    pBt->pPage1 = pPage1
    pBt->nPage = pageCount
    Return SQLITE_OK
End Function

Function btreeCreateNewDatabase CDecl Alias "newDatabase" ( _
    ByVal pBt As BtShared Ptr _
) As SQLITE_C_INT
    If pBt = 0 OrElse pBt->pPage1 = 0 Then Return SQLITE_MISUSE
    If pBt->nPage > 0 Then Return SQLITE_OK
    Dim pPage1 As MemPage Ptr = CPtr(MemPage Ptr, pBt->pPage1)
    Dim rc As SQLITE_C_INT = sqlite3PagerWrite(pPage1->pDbPage)
    If rc <> SQLITE_OK Then Return rc

    Dim pPageData As UByte Ptr = pPage1->aData
    For i As Long = 0 To 15
        pPageData[i] = btreeFileMagic(i)
    Next
    pPageData[16] = CByte((pBt->pageSize Shr 8) And &HFF)
    pPageData[17] = CByte((pBt->pageSize Shr 16) And &HFF)
    pPageData[18] = 1
    pPageData[19] = 1
    pPageData[20] = CByte(pBt->pageSize - pBt->usableSize)
    pPageData[21] = 64
    pPageData[22] = 32
    pPageData[23] = 32
    For i As Long = 24 To 99
        pPageData[i] = 0
    Next
#ifndef SQLITE_OMIT_AUTOVACUUM
    btreeWriteU32(pPageData + 52, pBt->autoVacuum)
    btreeWriteU32(pPageData + 64, pBt->incrVacuum)
#endif
    pPageData[100] = PTF_INTKEY Or PTF_LEAF Or PTF_LEAFDATA
    For i As Long = 101 To 104
        pPageData[i] = 0
    Next
    If pBt->usableSize = 65536 Then
        pPageData[105] = 0
        pPageData[106] = 0
    Else
        pPageData[105] = CByte((pBt->usableSize Shr 8) And &HFF)
        pPageData[106] = CByte(pBt->usableSize And &HFF)
    End If
    pPageData[107] = 0
    pPageData[31] = 1
    pBt->btsFlags = pBt->btsFlags Or BTS_PAGESIZE_FIXED
    pBt->nPage = 1
    pPage1->isInit = 0
    Return sqlite3BtreeInitPage(pPage1)
End Function

Private Function btreeZeroPage(ByVal pPage As MemPage Ptr, ByVal flags As UByte) As SQLITE_C_INT
    If pPage = 0 OrElse pPage->pBt = 0 OrElse pPage->pDbPage = 0 OrElse pPage->aData = 0 Then Return SQLITE_MISUSE
    If sqlite3PagerIswriteable(pPage->pDbPage) = 0 Then Return SQLITE_READONLY
    If flags <> (PTF_INTKEY Or PTF_LEAFDATA Or PTF_LEAF) AndAlso _
       flags <> (PTF_ZERODATA Or PTF_LEAF) AndAlso _
       flags <> (PTF_INTKEY Or PTF_LEAFDATA) AndAlso flags <> PTF_ZERODATA Then Return SQLITE_MISUSE

    Dim pBt As BtShared Ptr = pPage->pBt
    Dim headerOffset As Long = pPage->hdrOffset
    Dim childPointerSize As Long = IIf((flags And PTF_LEAF) <> 0, 0, 4)
    Dim firstCellOffset As Long = headerOffset + 8 + childPointerSize
    If firstCellOffset > pBt->usableSize Then Return SQLITE_CORRUPT
    If (pBt->btsFlags And BTS_FAST_SECURE) <> 0 Then
        For iByte As Long = headerOffset To CLng(pBt->usableSize) - 1
            pPage->aData[iByte] = 0
        Next
    End If

    pPage->aData[headerOffset] = flags
    For iByte As Long = 1 To 4
        pPage->aData[headerOffset + iByte] = 0
    Next
    If pBt->usableSize = 65536 Then
        pPage->aData[headerOffset + 5] = 0
        pPage->aData[headerOffset + 6] = 0
    Else
        btreeWriteU16(pPage->aData + headerOffset + 5, CUShort(pBt->usableSize))
    End If
    pPage->aData[headerOffset + 7] = 0
    If childPointerSize <> 0 Then btreeWriteU32(pPage->aData + headerOffset + 8, 0)
    pPage->isInit = 0
    Return sqlite3BtreeInitPage(pPage)
End Function

' Copy a page image, rebuild its auxiliary layout, and repair child/overflow
' pointer-map entries when the database uses auto-vacuum.
Private Function btreeCopyNodeContent CDecl Alias "copyNodeContent" ( _
    ByVal pFrom As MemPage Ptr, _
    ByVal pTo As MemPage Ptr _
) As SQLITE_C_INT

    If pFrom = 0 OrElse pTo = 0 OrElse pFrom = pTo OrElse _
       pFrom->pBt = 0 OrElse pFrom->pBt <> pTo->pBt OrElse _
       pFrom->aData = 0 OrElse pTo->aData = 0 OrElse _
       pFrom->pDbPage = 0 OrElse pTo->pDbPage = 0 OrElse pFrom->isInit = 0 Then Return SQLITE_MISUSE
    If sqlite3PagerIswriteable(pTo->pDbPage) = 0 Then Return SQLITE_READONLY

    Dim pBt As BtShared Ptr = pFrom->pBt
    Dim fromHeader As Long = pFrom->hdrOffset
    Dim toHeader As Long = pTo->hdrOffset
    Dim oldContentOffset As Long = btreeGetU16(pFrom->aData + fromHeader + 5)
    If oldContentOffset > pBt->usableSize Then oldContentOffset = 0
    Dim headerBytes As sqlite3_uint64 = CULngInt(pFrom->cellOffset) + (2 * pFrom->nCell)
    If headerBytes > pBt->usableSize OrElse _
       CULngInt(toHeader) + headerBytes > pBt->usableSize OrElse _
       CULngInt(pBt->usableSize) - oldContentOffset > pBt->pageSize Then Return SQLITE_CORRUPT

    btreeSystemMemcpy(pTo->aData + oldContentOffset, pFrom->aData + oldContentOffset, _
                      CULngInt(pBt->usableSize) - oldContentOffset)
    btreeSystemMemcpy(pTo->aData + toHeader, pFrom->aData + fromHeader, CULngInt(headerBytes))
    pTo->isInit = 0
    Dim rc As SQLITE_C_INT = sqlite3BtreeInitPage(pTo)
    If rc <> SQLITE_OK Then Return rc
    rc = sqlite3BtreeComputeFreeSpace(pTo)
#ifndef SQLITE_OMIT_AUTOVACUUM
    If rc = SQLITE_OK AndAlso pFrom->pBt->autoVacuum <> 0 Then rc = setChildPtrmaps(pTo)
#endif
    Return rc
End Function

Private Function btreeBalanceDeeper CDecl Alias "balance_deeper" ( _
    ByVal pRoot As MemPage Ptr, _
    ByVal ppChild As MemPage Ptr Ptr _
) As SQLITE_C_INT

    If ppChild = 0 Then Return SQLITE_MISUSE
    ppChild[0] = 0
    If pRoot = 0 OrElse pRoot->pBt = 0 OrElse pRoot->pDbPage = 0 OrElse _
       pRoot->isInit = 0 OrElse pRoot->nOverflow = 0 Then Return SQLITE_MISUSE
    If pRoot->nOverflow > 3 Then Return SQLITE_CORRUPT

    Dim rc As SQLITE_C_INT = sqlite3PagerWrite(pRoot->pDbPage)
    If rc <> SQLITE_OK Then Return rc
    Dim childPageNumber As u32 = 0
    rc = btreeAllocatePageMode(pRoot->pBt, ppChild, @childPageNumber, _
        PTRMAP_BTREE, pRoot->pgno, pRoot->pgno, BTALLOC_ANY)
    If rc <> SQLITE_OK Then Return rc
    If ppChild[0] = 0 OrElse ppChild[0]->aData = 0 Then
        sqlite3BtreeReleasePage(ppChild[0])
        ppChild[0] = 0
        Return SQLITE_CORRUPT
    End If

    rc = btreeCopyNodeContent(pRoot, ppChild[0])
    If rc <> SQLITE_OK Then
        sqlite3BtreeReleasePage(ppChild[0])
        ppChild[0] = 0
        Return rc
    End If
    For iCell As SQLITE_C_INT = 0 To pRoot->nOverflow - 1
        ppChild[0]->aiOvfl(iCell) = pRoot->aiOvfl(iCell)
        ppChild[0]->apOvfl(iCell) = pRoot->apOvfl(iCell)
        ppChild[0]->aiOvflSize(iCell) = pRoot->aiOvflSize(iCell)
    Next
    ppChild[0]->nOverflow = pRoot->nOverflow

    Dim rootFlags As UByte = ppChild[0]->aData[0] And Not PTF_LEAF
    rc = btreeZeroPage(pRoot, rootFlags)
    If rc <> SQLITE_OK Then
        sqlite3BtreeReleasePage(ppChild[0])
        ppChild[0] = 0
        Return rc
    End If
    btreeWriteU32(pRoot->aData + pRoot->hdrOffset + 8, childPageNumber)
    Return SQLITE_OK
End Function

Private Sub btreeFinishTransaction(ByVal pBtree As Btree Ptr)
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Exit Sub
    Dim pBt As BtShared Ptr = pBtree->pBt
#ifndef SQLITE_OMIT_AUTOVACUUM
    pBt->bDoTruncate = 0
#endif

    If pBtree->inTrans > TRANS_NONE AndAlso pBtree->db->nVdbeRead > 1 Then
        ' Another active statement still needs its read transaction. Drop this
        ' handle's writer status and keep its locks at read strength.
        If pBt->pWriter = pBtree Then
            pBt->pWriter = 0
            pBt->btsFlags = pBt->btsFlags And Not (BTS_EXCLUSIVE Or BTS_PENDING)
        End If
#ifndef SQLITE_OMIT_SHARED_CACHE
        Dim pLock As BtLock Ptr = CPtr(BtLock Ptr, pBt->pLock)
        While pLock <> 0
            If pLock->pBtree = pBtree Then pLock->eLock = READ_LOCK
            pLock = CPtr(BtLock Ptr, pLock->pNext)
        Wend
#endif
        pBtree->inTrans = TRANS_READ
        Exit Sub
    End If

    If pBtree->inTrans <> TRANS_NONE Then
#ifndef SQLITE_OMIT_SHARED_CACHE
        ' The schema lock is embedded in Btree; table locks are heap allocated.
        Dim ppLock As BtLock Ptr Ptr = CPtr(BtLock Ptr Ptr, @pBt->pLock)
        While ppLock[0] <> 0
            Dim pLock As BtLock Ptr = ppLock[0]
            If pLock->pBtree = pBtree Then
                ppLock[0] = CPtr(BtLock Ptr, pLock->pNext)
                If pLock->iTable <> 1 Then sqlite3_free(pLock)
            Else
                ppLock = @pLock->pNext
            End If
        Wend
#endif
        If pBt->pWriter = pBtree Then
            pBt->pWriter = 0
            pBt->btsFlags = pBt->btsFlags And Not (BTS_EXCLUSIVE Or BTS_PENDING)
        ElseIf pBt->nTransaction = 2 Then
            pBt->btsFlags = pBt->btsFlags And Not BTS_PENDING
        End If
        If pBt->nTransaction > 0 Then
            pBt->nTransaction -= 1
        Else
#ifdef SQLITE_DEBUG
            sqlite3DebugAssert(StrPtr("active B-tree transaction count is positive"))
#endif
            pBt->nTransaction = 0
        End If
        If pBt->nTransaction = 0 Then pBt->inTransaction = TRANS_NONE
    End If

    pBtree->inTrans = TRANS_NONE
    If pBt->inTransaction = TRANS_NONE Then
        ' Faulted cursors may remain linked after rollback, but no longer hold
        ' the page-one read reference once the shared transaction has ended.
        btreeUnlockPageOne(pBt)
    End If
End Sub

/' ------------------------------------------------------------------------- '/
/' B-tree transaction interface '/
/' ------------------------------------------------------------------------- '/

Function sqlite3BtreeNewDb CDecl Alias "sqlite3BtreeNewDb" (ByVal pBtree As Btree Ptr) As SQLITE_C_INT Export
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return SQLITE_MISUSE
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    pBt->nPage = 0
    Dim rc As SQLITE_C_INT = btreeCreateNewDatabase(pBt)
    sqlite3BtreeLeave(pBtree)
    Return rc
End Function

Function sqlite3BtreeCreateTable CDecl Alias "sqlite3BtreeCreateTable" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal pRootPage As u32 Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pRootPage <> 0 Then pRootPage[0] = 0
    If pBtree = 0 OrElse pBtree->pBt = 0 OrElse pRootPage = 0 Then Return SQLITE_MISUSE
    Dim tableKind As SQLITE_C_INT = flags And (BTREE_INTKEY Or BTREE_BLOBKEY)
    If (flags And Not (BTREE_INTKEY Or BTREE_BLOBKEY Or BTREE_UNORDERED)) <> 0 OrElse _
       (tableKind <> BTREE_INTKEY AndAlso tableKind <> BTREE_BLOBKEY) OrElse _
       ((flags And BTREE_UNORDERED) <> 0 AndAlso _
        (pBtree->pBt->openFlags And BTREE_SINGLE) = 0) Then Return SQLITE_MISUSE
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    If pBtree->inTrans <> TRANS_WRITE OrElse pBt->inTransaction <> TRANS_WRITE OrElse pBt->pPage1 = 0 Then
        sqlite3BtreeLeave(pBtree)
        Return SQLITE_MISUSE
    End If

    Dim pRoot As MemPage Ptr = 0
    Dim rootPageNumber As u32 = 0
    Dim rc As SQLITE_C_INT = SQLITE_OK
#ifndef SQLITE_OMIT_AUTOVACUUM
    If pBt->autoVacuum <> 0 Then
        invalidateAllOverflowCache(pBt)
        Dim requestedRoot As u32 = btreeReadU32(CPtr(MemPage Ptr, pBt->pPage1)->aData + 52)
        If requestedRoot > pBt->nPage Then
            rc = SQLITE_CORRUPT
        ElseIf requestedRoot >= SQLITE_MAX_PAGE_COUNT Then
            rc = SQLITE_FULL
        Else
            requestedRoot += 1
            Dim pendingBytePage As u32 = (PENDING_BYTE \ pBt->pageSize) + 1
            While ptrmapIsPage(pBt, requestedRoot) <> 0 OrElse requestedRoot = pendingBytePage
                If requestedRoot >= SQLITE_MAX_PAGE_COUNT Then
                    rc = SQLITE_FULL
                    Exit While
                End If
                requestedRoot += 1
            Wend
            If rc = SQLITE_OK AndAlso requestedRoot < 3 Then rc = SQLITE_CORRUPT
        End If

        If rc = SQLITE_OK Then
            If requestedRoot <= pBt->nPage Then
                Dim entryType As u8 = 0
                rc = ptrmapGet(pBt, requestedRoot, @entryType, 0)
                If rc = SQLITE_OK AndAlso entryType = PTRMAP_FREEPAGE Then
                    rc = btreeRemoveFreelistPage(pBt, requestedRoot, @pRoot)
                    If rc = SQLITE_OK Then
                        rootPageNumber = requestedRoot
                        rc = sqlite3PagerWrite(pRoot->pDbPage)
                        If rc = SQLITE_OK Then rc = btreeMarkAllocatedPage(pBt, requestedRoot, PTRMAP_ROOTPAGE, 0)
                    End If
                    If rc <> SQLITE_OK Then
                        sqlite3BtreeReleasePage(pRoot)
                        pRoot = 0
                    End If
                ElseIf rc = SQLITE_OK Then
                    rc = btreeAllocatePageMode(pBt, @pRoot, @rootPageNumber, _
                        PTRMAP_ROOTPAGE, 0, requestedRoot, BTALLOC_EXACT)
                End If
            Else
                rc = btreeAllocatePageMode(pBt, @pRoot, @rootPageNumber, _
                    PTRMAP_ROOTPAGE, 0, requestedRoot, BTALLOC_EXACT)
            End If
        End If

        If rc = SQLITE_OK AndAlso rootPageNumber <> requestedRoot Then
            rc = btreeSaveAllCursors(pBt, 0, 0)
            sqlite3BtreeReleasePage(pRoot)
            pRoot = 0
            If rc = SQLITE_OK Then rc = btreeGetPage(pBt, requestedRoot, @pRoot, 0)

            If rc = SQLITE_OK Then
                Dim oldPageType As u8 = 0
                Dim oldParentPage As u32 = 0
                rc = ptrmapGet(pBt, requestedRoot, @oldPageType, @oldParentPage)
                If rc = SQLITE_OK AndAlso _
                   (oldPageType = PTRMAP_ROOTPAGE OrElse oldPageType = PTRMAP_FREEPAGE) Then
                    rc = SQLITE_CORRUPT
                End If
                If rc = SQLITE_OK Then
                    rc = relocatePage(pBt, pRoot, oldPageType, oldParentPage, rootPageNumber, 0)
                End If
                sqlite3BtreeReleasePage(pRoot)
                pRoot = 0
            End If

            If rc = SQLITE_OK Then rc = btreeGetPage(pBt, requestedRoot, @pRoot, 0)
            If rc = SQLITE_OK Then rc = sqlite3PagerWrite(pRoot->pDbPage)
            If rc = SQLITE_OK Then rootPageNumber = requestedRoot
        End If

        If rc = SQLITE_OK Then
            ptrmapPut(pBt, rootPageNumber, PTRMAP_ROOTPAGE, 0, @rc)
            If rc = SQLITE_OK Then rc = sqlite3BtreeUpdateMeta(pBtree, 4, rootPageNumber)
        End If
    Else
        rc = btreeAllocatePageMode(pBt, @pRoot, @rootPageNumber, _
            PTRMAP_ROOTPAGE, 0, 1, BTALLOC_ANY)
    End If
#else
    rc = btreeAllocatePageMode(pBt, @pRoot, @rootPageNumber, _
        PTRMAP_ROOTPAGE, 0, 1, BTALLOC_ANY)
#endif
    If rc = SQLITE_OK Then
        Dim pageFlags As UByte = PTF_ZERODATA Or PTF_LEAF
        If flags = BTREE_INTKEY Then pageFlags = PTF_INTKEY Or PTF_LEAFDATA Or PTF_LEAF
        rc = btreeZeroPage(pRoot, pageFlags)
    End If
    If pRoot <> 0 Then sqlite3BtreeReleasePage(pRoot)
    If rc = SQLITE_OK Then pRootPage[0] = rootPageNumber
    sqlite3BtreeLeave(pBtree)
    Return rc
End Function

Private Function btreeInsertCellWithChild( _
    ByVal pPage As MemPage Ptr, _
    ByVal cellIndex As SQLITE_C_INT, _
    ByVal pCell As UByte Ptr, _
    ByVal cellSize As SQLITE_C_INT, _
    ByVal childPage As u32 _
) As SQLITE_C_INT

    If pPage = 0 OrElse pPage->pBt = 0 OrElse pPage->pDbPage = 0 OrElse _
       pPage->isInit = 0 OrElse pPage->leaf <> 0 OrElse pPage->childPtrSize <> 4 OrElse _
       pCell = 0 OrElse childPage = 0 OrElse cellSize < 4 OrElse _
       cellSize > 65535 OrElse pPage->nOverflow > 3 Then Return SQLITE_MISUSE
    If cellIndex < 0 OrElse cellIndex > pPage->nCell + pPage->nOverflow Then Return SQLITE_MISUSE
    If pPage->nFree < 0 Then
        Dim rcFree As SQLITE_C_INT = sqlite3BtreeComputeFreeSpace(pPage)
        If rcFree <> SQLITE_OK Then Return rcFree
    End If
    If CULng(pPage->nCell) + pPage->nOverflow >= _
       (pPage->pBt->usableSize - pPage->cellOffset) \ 2 Then Return SQLITE_FULL
    If btreeValidateCellBuffer(pPage, pCell, cellSize) <> SQLITE_OK Then Return SQLITE_CORRUPT

    If pPage->nOverflow <> 0 OrElse cellSize + 2 > pPage->nFree Then
        Dim overflowIndex As Long = pPage->nOverflow
        If overflowIndex >= 3 Then Return SQLITE_CORRUPT
        If overflowIndex > 0 Then
            Dim previousIndex As u16 = pPage->aiOvfl(overflowIndex - 1)
            If cellIndex <= previousIndex OrElse cellIndex <> previousIndex + 1 Then Return SQLITE_MISUSE
        End If
        btreeWriteU32(pCell, childPage)
#ifndef SQLITE_OMIT_AUTOVACUUM
        If pPage->pBt->autoVacuum <> 0 Then
            Dim pointerMapRc As SQLITE_C_INT = SQLITE_OK
            ptrmapPut(pPage->pBt, childPage, PTRMAP_BTREE, pPage->pgno, @pointerMapRc)
            If pointerMapRc <> SQLITE_OK Then Return pointerMapRc
        End If
#endif
        pPage->apOvfl(overflowIndex) = pCell
        pPage->aiOvfl(overflowIndex) = CUShort(cellIndex)
        pPage->aiOvflSize(overflowIndex) = CUShort(cellSize)
        pPage->nOverflow += 1
        Return SQLITE_OK
    End If

    Dim rc As SQLITE_C_INT = sqlite3PagerWrite(pPage->pDbPage)
    If rc <> SQLITE_OK Then Return rc
    Dim cellOffset As SQLITE_C_INT = 0
    rc = btreeAllocateSpace(pPage, cellSize, @cellOffset)
    If rc <> SQLITE_OK Then Return rc
    Dim minimumCellOffset As Long = pPage->cellOffset + (2 * pPage->nCell) + 2
    If cellOffset < minimumCellOffset OrElse _
       cellOffset > pPage->pBt->usableSize OrElse _
       cellSize > pPage->pBt->usableSize - cellOffset Then Return SQLITE_CORRUPT

    pPage->nFree -= (cellSize + 2)
    btreeSystemMemcpy(pPage->aData + cellOffset, pCell, CULngInt(cellSize))
    btreeWriteU32(pPage->aData + cellOffset, childPage)
    For iCell As Long = pPage->nCell To cellIndex + 1 Step -1
        Dim pDestination As UByte Ptr = pPage->aCellIdx + (2 * iCell)
        pDestination[0] = pDestination[-2]
        pDestination[1] = pDestination[-1]
    Next
    btreeWriteU16(pPage->aCellIdx + (2 * cellIndex), CUShort(cellOffset))
    pPage->nCell += 1
    btreeWriteU16(pPage->aData + pPage->hdrOffset + 3, pPage->nCell)
#ifndef SQLITE_OMIT_AUTOVACUUM
    If pPage->pBt->autoVacuum <> 0 Then
        Dim pointerMapRc As SQLITE_C_INT = SQLITE_OK
        ptrmapPut(pPage->pBt, childPage, PTRMAP_BTREE, pPage->pgno, @pointerMapRc)
        If pointerMapRc = SQLITE_OK Then _
            ptrmapPutOvflPtr(pPage, pPage, pPage->aData + cellOffset, @pointerMapRc)
        If pointerMapRc <> SQLITE_OK Then Return pointerMapRc
    End If
#endif
    Return SQLITE_OK
End Function

Private Function btreeBalanceQuick CDecl Alias "balance_quick" ( _
    ByVal pParent As MemPage Ptr, _
    ByVal pPage As MemPage Ptr, _
    ByVal pSpace As UByte Ptr _
) As SQLITE_C_INT

    If pParent = 0 OrElse pPage = 0 OrElse pParent->pBt = 0 OrElse _
       pParent->pBt <> pPage->pBt OrElse pSpace = 0 OrElse _
       pPage->intKeyLeaf = 0 OrElse pPage->nOverflow <> 1 OrElse _
       pPage->aiOvfl(0) <> pPage->nCell OrElse pPage->nCell = 0 OrElse _
       pParent->intKey = 0 OrElse pParent->leaf <> 0 OrElse _
       pParent->childPtrSize <> 4 OrElse pParent->pgno = 1 Then Return SQLITE_MISUSE
    If btreeReadU32(pParent->aData + pParent->hdrOffset + 8) <> pPage->pgno Then Return SQLITE_CORRUPT
    If pPage->nFree < 0 Then
        Dim rcFree As SQLITE_C_INT = sqlite3BtreeComputeFreeSpace(pPage)
        If rcFree <> SQLITE_OK Then Return rcFree
    End If
    If pParent->nFree < 0 Then
        Dim rcParentFree As SQLITE_C_INT = sqlite3BtreeComputeFreeSpace(pParent)
        If rcParentFree <> SQLITE_OK Then Return rcParentFree
    End If

    Dim rc As SQLITE_C_INT = sqlite3PagerWrite(pParent->pDbPage)
    If rc <> SQLITE_OK Then Return rc
    Dim pNew As MemPage Ptr = 0
    Dim newPageNumber As u32 = 0
    rc = btreeAllocatePageAny(pPage->pBt, @pNew, @newPageNumber, PTRMAP_BTREE, pParent->pgno)
    If rc <> SQLITE_OK Then Return rc
    If pNew = 0 OrElse pNew->aData = 0 Then
        sqlite3BtreeReleasePage(pNew)
        Return SQLITE_CORRUPT
    End If

    rc = btreeZeroPage(pNew, PTF_INTKEY Or PTF_LEAFDATA Or PTF_LEAF)
    If rc = SQLITE_OK Then
        Dim pOverflowCell As UByte Ptr = pPage->apOvfl(0)
        ' Queued cells live in scratch memory, outside the source page range.
        ' Use the validated size saved when the cell was queued.
        Dim overflowCellSize As u16 = pPage->aiOvflSize(0)
        If pOverflowCell = 0 OrElse overflowCellSize < 4 Then
            rc = SQLITE_CORRUPT
        Else
            rc = btreeInsertCellFast(pNew, 0, pOverflowCell, overflowCellSize)
        End If
    End If

#ifndef SQLITE_OMIT_AUTOVACUUM
    If rc = SQLITE_OK AndAlso pPage->pBt->autoVacuum <> 0 AndAlso _
       pPage->aiOvflSize(0) > pNew->minLocal Then
        Dim overflowInfo As CellInfo
        Dim parseCell As BtreeCellParseProc = CPtr(BtreeCellParseProc, pPage->xParseCell)
        Dim pOverflowCell As UByte Ptr = pPage->apOvfl(0)
        If pOverflowCell = 0 OrElse parseCell = 0 Then
            rc = SQLITE_CORRUPT
        Else
            parseCell(pPage, pOverflowCell, @overflowInfo)
            If overflowInfo.nSize < 4 OrElse overflowInfo.nSize > pPage->aiOvflSize(0) Then
                rc = SQLITE_CORRUPT
            ElseIf overflowInfo.nLocal < overflowInfo.nPayload Then
                Dim overflowPage As u32 = btreeReadU32(pOverflowCell + overflowInfo.nSize - 4)
                If overflowPage < 2 OrElse overflowPage > pPage->pBt->nPage Then
                    rc = SQLITE_CORRUPT
                Else
                    ptrmapPut(pPage->pBt, overflowPage, PTRMAP_OVERFLOW1, pNew->pgno, @rc)
                End If
            End If
        End If
    End If
#endif

    If rc = SQLITE_OK Then
        Dim pRightmostCell As UByte Ptr = btreeCursorCell(pPage, pPage->nCell - 1)
        If pRightmostCell = 0 Then
            rc = SQLITE_CORRUPT
        Else
            Dim payloadLength As SQLITE_C_INT = 0
            Dim payloadSize As sqlite3_uint64 = 0
            rc = btreeReadVarint(pPage, pRightmostCell, @payloadSize, @payloadLength)
            If rc = SQLITE_OK Then
                Dim keyLength As SQLITE_C_INT = 0
                Dim rowIdValue As sqlite3_uint64 = 0
                rc = btreeReadVarint(pPage, pRightmostCell + payloadLength, @rowIdValue, @keyLength)
                If rc = SQLITE_OK AndAlso _
                   btreePageHasRange(pPage, pRightmostCell + payloadLength, keyLength) = 0 Then rc = SQLITE_CORRUPT
                If rc = SQLITE_OK Then
                    Dim pDivider As UByte Ptr = pSpace
                    If keyLength > 9 Then
                        rc = SQLITE_CORRUPT
                    Else
                        btreeWriteU32(pDivider, pPage->pgno)
                        btreeSystemMemcpy(pDivider + 4, pRightmostCell + payloadLength, CULngInt(keyLength))
                        rc = btreeInsertCellWithChild(pParent, pParent->nCell, pDivider, keyLength + 4, pPage->pgno)
                        If rc = SQLITE_OK Then
                            btreeWriteU32(pParent->aData + pParent->hdrOffset + 8, newPageNumber)
                        End If
                    End If
                End If
            End If
        End If
    End If

    sqlite3BtreeReleasePage(pNew)
    Return rc
End Function

Private Sub btreeReleaseBalanceSiblingSet(ByVal pState As BtreeBalanceSiblingSet Ptr)
    If pState = 0 Then Exit Sub
    For iPage As SQLITE_C_INT = 0 To 2
        sqlite3BtreeReleasePage(pState->apOld(iPage))
        pState->apOld(iPage) = 0
    Next
    If pState->pDividerCopy <> 0 Then
        sqlite3PageFree(pState->pDividerCopy)
        pState->pDividerCopy = 0
    End If
    pState->pRightChild = 0
    For iDivider As SQLITE_C_INT = 0 To 1
        pState->apDivider(iDivider) = 0
        pState->dividerSize(iDivider) = 0
    Next
    pState->nOld = 0
    pState->targetIndex = -1
    pState->nMaxCells = 0
    pState->leafCorrection = 0
    pState->leafData = 0
    pState->usableSpace = 0
End Sub

Private Function btreeCollectBalanceSiblings( _
    ByVal pParent As MemPage Ptr, _
    ByVal parentChildIndex As SQLITE_C_INT, _
    ByVal bulkLoad As SQLITE_C_INT, _
    ByVal pState As BtreeBalanceSiblingSet Ptr _
) As SQLITE_C_INT

    If pState = 0 Then Return SQLITE_MISUSE
    pState->nOld = 0
    pState->nxDiv = 0
    pState->targetIndex = -1
    pState->nMaxCells = 0
    pState->pRightChild = 0
    pState->pDividerCopy = 0
    For iPage As SQLITE_C_INT = 0 To 2
        pState->apOld(iPage) = 0
        pState->cellEndOld(iPage) = 0
    Next
    For iDivider As SQLITE_C_INT = 0 To 1
        pState->apDivider(iDivider) = 0
        pState->dividerSize(iDivider) = 0
    Next

    If pParent = 0 OrElse pParent->pBt = 0 OrElse pParent->pDbPage = 0 OrElse _
       pParent->aData = 0 OrElse pParent->isInit = 0 OrElse _
       (bulkLoad <> 0 AndAlso bulkLoad <> 1) OrElse pParent->nOverflow > 1 Then Return SQLITE_MISUSE
    If sqlite3PagerIswriteable(pParent->pDbPage) = 0 Then Return SQLITE_READONLY
    If pParent->nFree < 0 Then
        Dim rcFree As SQLITE_C_INT = sqlite3BtreeComputeFreeSpace(pParent)
        If rcFree <> SQLITE_OK Then Return rcFree
    End If

    Dim dividerCount As SQLITE_C_INT = pParent->nCell + pParent->nOverflow
    If parentChildIndex < 0 OrElse parentChildIndex > dividerCount Then Return SQLITE_CORRUPT
    If pParent->nOverflow = 1 AndAlso pParent->aiOvfl(0) <> parentChildIndex Then Return SQLITE_CORRUPT

    Dim leftmostIndex As SQLITE_C_INT = dividerCount
    If dividerCount >= 2 Then
        If parentChildIndex = 0 Then
            pState->nxDiv = 0
        ElseIf parentChildIndex = dividerCount Then
            pState->nxDiv = dividerCount - 2 + bulkLoad
        Else
            pState->nxDiv = parentChildIndex - 1
        End If
        leftmostIndex = 2 - bulkLoad
    End If
    pState->nOld = leftmostIndex + 1
    If pState->nOld < 1 OrElse pState->nOld > 3 Then Return SQLITE_CORRUPT
    pState->targetIndex = parentChildIndex - pState->nxDiv
    If pState->targetIndex < 0 OrElse pState->targetIndex >= pState->nOld Then Return SQLITE_CORRUPT

    Dim rightSlot As SQLITE_C_INT = leftmostIndex + pState->nxDiv - pParent->nOverflow
    If rightSlot < 0 OrElse rightSlot > pParent->nCell Then Return SQLITE_CORRUPT
    If rightSlot = pParent->nCell Then
        pState->pRightChild = pParent->aData + pParent->hdrOffset + 8
    Else
        pState->pRightChild = btreeCursorCell(pParent, rightSlot)
    End If
    If pState->pRightChild = 0 OrElse btreePageHasRange(pParent, pState->pRightChild, 4) = 0 Then Return SQLITE_CORRUPT

    Dim pageNumber As u32 = btreeReadU32(pState->pRightChild)
    Dim firstPageFlags As UByte = 0
    For pageIndex As SQLITE_C_INT = leftmostIndex To 0 Step -1
        If pageNumber < 2 OrElse pageNumber > pParent->pBt->nPage Then
            btreeReleaseBalanceSiblingSet(pState)
            Return SQLITE_CORRUPT
        End If
        Dim pOld As MemPage Ptr = 0
        Dim rc As SQLITE_C_INT = sqlite3BtreeGetAndInitPage(pParent->pBt, pageNumber, @pOld, 0)
        If rc <> SQLITE_OK Then
            btreeReleaseBalanceSiblingSet(pState)
            Return rc
        End If
        If pOld = 0 OrElse pOld->aData = 0 OrElse pOld->pDbPage = 0 Then
            sqlite3BtreeReleasePage(pOld)
            btreeReleaseBalanceSiblingSet(pState)
            Return SQLITE_CORRUPT
        End If
        If pOld->nFree < 0 Then
            rc = sqlite3BtreeComputeFreeSpace(pOld)
            If rc <> SQLITE_OK Then
                sqlite3BtreeReleasePage(pOld)
                btreeReleaseBalanceSiblingSet(pState)
                Return rc
            End If
        End If
        If pageIndex = leftmostIndex Then
            firstPageFlags = pOld->aData[pOld->hdrOffset]
        ElseIf pOld->aData[pOld->hdrOffset] <> firstPageFlags Then
            sqlite3BtreeReleasePage(pOld)
            btreeReleaseBalanceSiblingSet(pState)
            Return SQLITE_CORRUPT
        End If
        pState->apOld(pageIndex) = pOld
        pState->nMaxCells += pOld->nCell + 4

        If pageIndex = 0 Then Exit For
        Dim dividerSlot As SQLITE_C_INT = (pageIndex - 1) + pState->nxDiv
        If pParent->nOverflow = 1 AndAlso dividerSlot = pParent->aiOvfl(0) Then
            Dim pDivider As UByte Ptr = pParent->apOvfl(0)
            Dim dividerSize As u16 = pParent->aiOvflSize(0)
            If pDivider = 0 OrElse dividerSize < 4 Then
                btreeReleaseBalanceSiblingSet(pState)
                Return SQLITE_CORRUPT
            End If
            pState->apDivider(pageIndex - 1) = pDivider
            pState->dividerSize(pageIndex - 1) = dividerSize
            pageNumber = btreeReadU32(pDivider)
            pParent->nOverflow = 0
        Else
            Dim cellIndex As SQLITE_C_INT = dividerSlot - pParent->nOverflow
            If cellIndex < 0 OrElse cellIndex >= pParent->nCell Then
                btreeReleaseBalanceSiblingSet(pState)
                Return SQLITE_CORRUPT
            End If
            Dim pDivider As UByte Ptr = btreeCursorCell(pParent, cellIndex)
            If pDivider = 0 OrElse btreePageHasRange(pParent, pDivider, 4) = 0 Then
                btreeReleaseBalanceSiblingSet(pState)
                Return SQLITE_CORRUPT
            End If
            Dim dividerSize As u16 = sqlite3BtreeCellSize(pParent, pDivider)
            If dividerSize < 4 OrElse btreePageHasRange(pParent, pDivider, dividerSize) = 0 Then
                btreeReleaseBalanceSiblingSet(pState)
                Return SQLITE_CORRUPT
            End If
            pageNumber = btreeReadU32(pDivider)
            If (pParent->pBt->btsFlags And BTS_FAST_SECURE) <> 0 Then
                If pState->pDividerCopy = 0 Then
                    pState->pDividerCopy = CPtr(UByte Ptr, sqlite3PageMalloc(CLng(pParent->pBt->pageSize)))
                    If pState->pDividerCopy = 0 Then
                        btreeReleaseBalanceSiblingSet(pState)
                        Return SQLITE_NOMEM
                    End If
                End If
                Dim copyOffset As Long = CLng(pDivider - pParent->aData)
                If copyOffset < 0 OrElse copyOffset > pParent->pBt->usableSize OrElse _
                   dividerSize > pParent->pBt->usableSize - copyOffset Then
                    btreeReleaseBalanceSiblingSet(pState)
                    Return SQLITE_CORRUPT
                End If
                btreeSystemMemcpy(pState->pDividerCopy + copyOffset, pDivider, dividerSize)
                pDivider = pState->pDividerCopy + copyOffset
            End If
            pState->apDivider(pageIndex - 1) = pDivider
            pState->dividerSize(pageIndex - 1) = dividerSize
            Dim rcDrop As SQLITE_C_INT = sqlite3BtreeDropCell(pParent, cellIndex)
            If rcDrop <> SQLITE_OK Then
                btreeReleaseBalanceSiblingSet(pState)
                Return rcDrop
            End If
        End If
    Next

    If pParent->nOverflow <> 0 Then
        btreeReleaseBalanceSiblingSet(pState)
        Return SQLITE_CORRUPT
    End If
    pState->leafCorrection = CUShort(pState->apOld(0)->leaf * 4)
    pState->leafData = pState->apOld(0)->intKeyLeaf
    pState->usableSpace = CLng(pParent->pBt->usableSize) - 12 + pState->leafCorrection
    If pState->usableSpace <= 0 Then
        btreeReleaseBalanceSiblingSet(pState)
        Return SQLITE_CORRUPT
    End If
    Return SQLITE_OK
End Function

Private Function btreeBuildBalanceCellArray( _
    ByVal pParent As MemPage Ptr, _
    ByVal pState As BtreeBalanceSiblingSet Ptr, _
    ByVal pCellArray As BtreeCellArray Ptr, _
    ByVal pDividerScratch As UByte Ptr, _
    ByVal scratchSize As SQLITE_C_INT _
) As SQLITE_C_INT

    If pParent = 0 OrElse pState = 0 OrElse pCellArray = 0 OrElse _
       pCellArray->apCell = 0 OrElse pCellArray->szCell = 0 OrElse _
       pState->nOld < 1 OrElse pState->nOld > 3 OrElse scratchSize < 0 Then Return SQLITE_MISUSE
    If pState->leafData = 0 AndAlso (pDividerScratch = 0 OrElse scratchSize < pParent->pBt->pageSize) Then Return SQLITE_MISUSE
    Dim cellCapacity As SQLITE_C_INT = pCellArray->nCell
    If cellCapacity < pState->nMaxCells Then Return SQLITE_FULL
    pCellArray->nCell = 0
    pCellArray->pRef = pState->apOld(0)
    If pCellArray->pRef = 0 Then Return SQLITE_CORRUPT
    For iStage As SQLITE_C_INT = 0 To BTREE_BALANCE_STAGE_COUNT - 1
        pCellArray->apEnd(iStage) = 0
        pCellArray->ixNx(iStage) = 0
    Next
    pCellArray->ixNx(BTREE_BALANCE_STAGE_COUNT - 1) = &H7FFFFFFF

    Dim scratchOffset As SQLITE_C_INT = 0
    Dim expectedFlags As UByte = pCellArray->pRef->aData[pCellArray->pRef->hdrOffset]
    For pageIndex As SQLITE_C_INT = 0 To pState->nOld - 1
        Dim pOld As MemPage Ptr = pState->apOld(pageIndex)
        If pOld = 0 OrElse pOld->aData = 0 OrElse pOld->isInit = 0 OrElse _
           pOld->aData[pOld->hdrOffset] <> expectedFlags Then Return SQLITE_CORRUPT

        Dim physicalIndex As SQLITE_C_INT = 0
        Dim overflowIndex As SQLITE_C_INT = 0
        Dim combinedIndex As SQLITE_C_INT = 0
        While physicalIndex < pOld->nCell OrElse overflowIndex < pOld->nOverflow
            If pCellArray->nCell >= cellCapacity Then Return SQLITE_FULL
            If overflowIndex < pOld->nOverflow AndAlso pOld->aiOvfl(overflowIndex) < combinedIndex Then Return SQLITE_CORRUPT
            If overflowIndex < pOld->nOverflow AndAlso pOld->aiOvfl(overflowIndex) = combinedIndex Then
                Dim pOverflowCell As UByte Ptr = pOld->apOvfl(overflowIndex)
                Dim overflowCellSize As u16 = pOld->aiOvflSize(overflowIndex)
                If pOverflowCell = 0 OrElse overflowCellSize < 4 Then Return SQLITE_CORRUPT
                pCellArray->apCell[pCellArray->nCell] = pOverflowCell
                pCellArray->szCell[pCellArray->nCell] = overflowCellSize
                overflowIndex += 1
            Else
                If physicalIndex >= pOld->nCell Then Return SQLITE_CORRUPT
                Dim pCell As UByte Ptr = btreeCursorCell(pOld, physicalIndex)
                If pCell = 0 Then Return SQLITE_CORRUPT
                pCellArray->apCell[pCellArray->nCell] = pCell
                pCellArray->szCell[pCellArray->nCell] = 0
                physicalIndex += 1
            End If
            pCellArray->nCell += 1
            combinedIndex += 1
        Wend
        pState->cellEndOld(pageIndex) = pCellArray->nCell

        If pageIndex < pState->nOld - 1 AndAlso pState->leafData = 0 Then
            Dim dividerSize As u16 = pState->dividerSize(pageIndex)
            Dim pDivider As UByte Ptr = pState->apDivider(pageIndex)
            If pDivider = 0 OrElse dividerSize < pState->leafCorrection OrElse _
               scratchOffset > scratchSize OrElse dividerSize > scratchSize - scratchOffset Then Return SQLITE_CORRUPT
            Dim pCellCopy As UByte Ptr = pDividerScratch + scratchOffset
            btreeSystemMemcpy(pCellCopy, pDivider, dividerSize)
            scratchOffset += dividerSize
            Dim cellSize As Long = dividerSize - pState->leafCorrection
            If pState->leafCorrection <> 0 Then
                If pState->leafCorrection <> 4 OrElse pOld->leaf = 0 Then Return SQLITE_CORRUPT
            ElseIf pOld->leaf = 0 Then
                If btreePageHasRange(pOld, pOld->aData + 8, 4) = 0 Then Return SQLITE_CORRUPT
                btreeSystemMemcpy(pCellCopy, pOld->aData + 8, 4)
            Else
                Return SQLITE_CORRUPT
            End If
            If cellSize < 4 Then
                If cellSize <> 3 OrElse scratchOffset >= scratchSize Then Return SQLITE_CORRUPT
                pDividerScratch[scratchOffset] = 0
                scratchOffset += 1
                cellSize += 1
            End If
            If pCellArray->nCell >= cellCapacity Then Return SQLITE_FULL
            pCellArray->apCell[pCellArray->nCell] = pCellCopy + pState->leafCorrection
            pCellArray->szCell[pCellArray->nCell] = CUShort(cellSize)
            pCellArray->nCell += 1
        End If
    Next

    Dim stageIndex As SQLITE_C_INT = 0
    For pageIndex As SQLITE_C_INT = 0 To pState->nOld - 1
        If stageIndex >= BTREE_BALANCE_STAGE_COUNT Then Return SQLITE_CORRUPT
        Dim pOld As MemPage Ptr = pState->apOld(pageIndex)
        pCellArray->apEnd(stageIndex) = pOld->aDataEnd
        pCellArray->ixNx(stageIndex) = pState->cellEndOld(pageIndex)
        If stageIndex > 0 AndAlso pCellArray->ixNx(stageIndex) = pCellArray->ixNx(stageIndex - 1) Then
            stageIndex -= 1
        End If
        If pState->leafData = 0 Then
            stageIndex += 1
            If stageIndex >= BTREE_BALANCE_STAGE_COUNT Then Return SQLITE_CORRUPT
            pCellArray->apEnd(stageIndex) = pParent->aDataEnd
            pCellArray->ixNx(stageIndex) = pState->cellEndOld(pageIndex) + 1
        End If
        stageIndex += 1
    Next
    Return SQLITE_OK
End Function

Private Function btreePlanBalancePages( _
    ByVal pCellArray As BtreeCellArray Ptr, _
    ByVal pState As BtreeBalanceSiblingSet Ptr, _
    ByVal bulkLoad As SQLITE_C_INT, _
    ByVal pPlan As BtreeBalancePlan Ptr _
) As SQLITE_C_INT

    If pCellArray = 0 OrElse pState = 0 OrElse pPlan = 0 OrElse _
       pState->nOld < 1 OrElse pState->nOld > 3 OrElse pState->usableSpace <= 0 Then Return SQLITE_MISUSE
    If pCellArray->nCell = 0 AndAlso pState->nOld <> 1 Then Return SQLITE_CORRUPT
    pPlan->pageCount = pState->nOld
    For pageIndex As SQLITE_C_INT = 0 To 4
        pPlan->usedBytes(pageIndex) = 0
        pPlan->cellEnd(pageIndex) = pCellArray->nCell
    Next
    For pageIndex As SQLITE_C_INT = 0 To pState->nOld - 1
        Dim pOld As MemPage Ptr = pState->apOld(pageIndex)
        If pOld = 0 OrElse pOld->nFree < 0 Then Return SQLITE_CORRUPT
        pPlan->cellEnd(pageIndex) = pState->cellEndOld(pageIndex)
        pPlan->usedBytes(pageIndex) = pState->usableSpace - pOld->nFree
        For overflowIndex As SQLITE_C_INT = 0 To pOld->nOverflow - 1
            Dim cellSize As u16 = pOld->aiOvflSize(overflowIndex)
            If cellSize < 4 Then Return SQLITE_CORRUPT
            pPlan->usedBytes(pageIndex) += cellSize + 2
        Next
    Next
    Return btreeComputeBalanceDistribution(pCellArray, pCellArray->nCell, _
        pState->nOld, pState->leafData, bulkLoad, pState->usableSpace, pPlan)
End Function

Private Function btreeCellArrayCellSize( _
    ByVal pCellArray As BtreeCellArray Ptr, _
    ByVal cellIndex As SQLITE_C_INT, _
    ByVal pCellSize As u16 Ptr _
) As SQLITE_C_INT

    If pCellSize = 0 Then Return SQLITE_MISUSE
    pCellSize[0] = 0
    If pCellArray = 0 OrElse pCellArray->pRef = 0 OrElse pCellArray->apCell = 0 OrElse _
       pCellArray->szCell = 0 OrElse cellIndex < 0 OrElse cellIndex >= pCellArray->nCell Then Return SQLITE_MISUSE
    Dim pRef As MemPage Ptr = pCellArray->pRef
    If pRef->pBt = 0 OrElse pCellArray->apCell[cellIndex] = 0 Then Return SQLITE_CORRUPT

    Dim stageIndex As SQLITE_C_INT = 0
    While stageIndex < BTREE_BALANCE_STAGE_COUNT AndAlso pCellArray->ixNx(stageIndex) <= cellIndex
        stageIndex += 1
    Wend
    If stageIndex >= BTREE_BALANCE_STAGE_COUNT OrElse pCellArray->apEnd(stageIndex) = 0 Then Return SQLITE_CORRUPT
    Dim pCell As UByte Ptr = pCellArray->apCell[cellIndex]
    Dim cellAddress As sqlite3_uint64 = CULngInt(pCell)
    Dim sourceEnd As sqlite3_uint64 = CULngInt(pCellArray->apEnd(stageIndex))
    If sourceEnd < pRef->pBt->pageSize Then Return SQLITE_CORRUPT
    Dim sourceStart As sqlite3_uint64 = sourceEnd - pRef->pBt->pageSize
    If cellAddress < sourceStart OrElse cellAddress >= sourceEnd Then
        If pCellArray->szCell[cellIndex] <> 0 Then
            pCellSize[0] = pCellArray->szCell[cellIndex]
            Return SQLITE_OK
        End If
        Return SQLITE_CORRUPT
    End If
    Dim availableBytes As Long = CLng(sourceEnd - cellAddress)
    Dim headerBytes As Long = pRef->childPtrSize
    If headerBytes > availableBytes OrElse (headerBytes <> 0 AndAlso headerBytes <> 4) Then Return SQLITE_CORRUPT

    Dim totalSize As sqlite3_uint64 = 0
    If pRef->intKey <> 0 AndAlso pRef->intKeyLeaf = 0 Then
        Dim keyValue As sqlite3_uint64 = 0
        Dim keyLength As SQLITE_C_INT = 0
        Dim rcKey As SQLITE_C_INT = btreeReadCellVarintBounded(pCell + headerBytes, _
            availableBytes - headerBytes, @keyValue, @keyLength)
        If rcKey <> SQLITE_OK Then Return rcKey
        totalSize = CULngInt(headerBytes) + keyLength
        If totalSize < 4 Then totalSize = 4
    Else
        Dim payloadSize As sqlite3_uint64 = 0
        Dim payloadLength As SQLITE_C_INT = 0
        Dim rcPayload As SQLITE_C_INT = btreeReadCellVarintBounded(pCell + headerBytes, _
            availableBytes - headerBytes, @payloadSize, @payloadLength)
        If rcPayload <> SQLITE_OK OrElse payloadSize > &HFFFFFFFF Then Return SQLITE_CORRUPT
        totalSize = CULngInt(headerBytes) + payloadLength
        If pRef->intKey <> 0 Then
            Dim rowIdValue As sqlite3_uint64 = 0
            Dim rowIdLength As SQLITE_C_INT = 0
            Dim keyOffset As Long = headerBytes + payloadLength
            If keyOffset > availableBytes Then Return SQLITE_CORRUPT
            Dim rcRowId As SQLITE_C_INT = btreeReadCellVarintBounded(pCell + keyOffset, _
                availableBytes - keyOffset, @rowIdValue, @rowIdLength)
            If rcRowId <> SQLITE_OK Then Return rcRowId
            totalSize += rowIdLength
        End If
        Dim localPayload As u16 = CUShort(btreePayloadToLocal(pRef, CLngInt(payloadSize)))
        totalSize += localPayload
        If payloadSize > localPayload Then totalSize += 4
        If totalSize < 4 Then totalSize = 4
    End If

    If totalSize > pRef->pBt->usableSize OrElse totalSize > 65535 Then Return SQLITE_CORRUPT
    pCellSize[0] = CUShort(totalSize)
    Return SQLITE_OK
End Function

Private Function btreePopulateCellCache( _
    ByVal pCellArray As BtreeCellArray Ptr, _
    ByVal firstCell As SQLITE_C_INT, _
    ByVal cellCount As SQLITE_C_INT _
) As SQLITE_C_INT

    If pCellArray = 0 OrElse pCellArray->szCell = 0 OrElse firstCell < 0 OrElse _
       cellCount < 0 OrElse CULngInt(firstCell) + cellCount > pCellArray->nCell Then Return SQLITE_MISUSE
    For cellIndex As SQLITE_C_INT = firstCell To firstCell + cellCount - 1
        Dim computedSize As u16 = 0
        Dim rc As SQLITE_C_INT = btreeCellArrayCellSize(pCellArray, cellIndex, @computedSize)
        If rc <> SQLITE_OK Then Return rc
        If pCellArray->szCell[cellIndex] <> 0 AndAlso pCellArray->szCell[cellIndex] <> computedSize Then Return SQLITE_CORRUPT
        pCellArray->szCell[cellIndex] = computedSize
    Next
    Return SQLITE_OK
End Function

Private Function btreeCellArraySize( _
    ByVal pCellArray As BtreeCellArray Ptr, _
    ByVal cellIndex As SQLITE_C_INT, _
    ByVal pCellSize As u16 Ptr _
) As SQLITE_C_INT

    If pCellArray = 0 OrElse pCellArray->szCell = 0 OrElse pCellSize = 0 OrElse _
       cellIndex < 0 OrElse cellIndex >= pCellArray->nCell Then Return SQLITE_MISUSE
    If pCellArray->szCell[cellIndex] <> 0 Then
        pCellSize[0] = pCellArray->szCell[cellIndex]
        Return SQLITE_OK
    End If
    Dim rc As SQLITE_C_INT = btreeCellArrayCellSize(pCellArray, cellIndex, pCellSize)
    If rc = SQLITE_OK Then pCellArray->szCell[cellIndex] = pCellSize[0]
    Return rc
End Function

Private Function btreeComputeBalanceDistribution( _
    ByVal pCellArray As BtreeCellArray Ptr, _
    ByVal totalCellCount As SQLITE_C_INT, _
    ByVal oldPageCount As SQLITE_C_INT, _
    ByVal leafData As SQLITE_C_INT, _
    ByVal bulkLoad As SQLITE_C_INT, _
    ByVal usableSpace As SQLITE_C_INT, _
    ByVal pPlan As BtreeBalancePlan Ptr _
) As SQLITE_C_INT

    If pCellArray = 0 OrElse pPlan = 0 OrElse pCellArray->szCell = 0 OrElse _
       totalCellCount < 0 OrElse totalCellCount > pCellArray->nCell OrElse _
       oldPageCount < 1 OrElse oldPageCount > 3 OrElse _
       (leafData <> 0 AndAlso leafData <> 1) OrElse _
       (bulkLoad <> 0 AndAlso bulkLoad <> 1) OrElse usableSpace <= 0 Then Return SQLITE_MISUSE
    If totalCellCount = 0 AndAlso oldPageCount <> 1 Then Return SQLITE_CORRUPT

    Dim previousBoundary As SQLITE_C_INT = 0
    For iPage As SQLITE_C_INT = 0 To oldPageCount - 1
        If pPlan->cellEnd(iPage) < previousBoundary OrElse _
           pPlan->cellEnd(iPage) > totalCellCount OrElse pPlan->usedBytes(iPage) < 0 Then Return SQLITE_CORRUPT
        previousBoundary = pPlan->cellEnd(iPage)
    Next
    If previousBoundary <> totalCellCount Then Return SQLITE_CORRUPT

    Dim pageCount As SQLITE_C_INT = oldPageCount
    For iPage As SQLITE_C_INT = oldPageCount To 4
        pPlan->usedBytes(iPage) = 0
        pPlan->cellEnd(iPage) = totalCellCount
    Next

    Dim iPage As SQLITE_C_INT = 0
    While iPage < pageCount
        While pPlan->usedBytes(iPage) > usableSpace
            If iPage + 1 >= pageCount Then
                pageCount = iPage + 2
                If pageCount > 5 Then Return SQLITE_CORRUPT
                pPlan->usedBytes(pageCount - 1) = 0
                pPlan->cellEnd(pageCount - 1) = totalCellCount
            End If
            If iPage + 1 >= 5 Then Return SQLITE_CORRUPT
            If pPlan->cellEnd(iPage) <= 0 Then Return SQLITE_CORRUPT
            Dim sizeRightmost As u16 = 0
            Dim rc As SQLITE_C_INT = btreeCellArraySize(pCellArray, pPlan->cellEnd(iPage) - 1, @sizeRightmost)
            If rc <> SQLITE_OK Then Return rc
            pPlan->usedBytes(iPage) -= (2 + sizeRightmost)

            Dim sizeToNextPage As SQLITE_C_INT = 0
            If leafData <> 0 Then
                ' Table-leaf records remain in the sibling page when balanced.
                sizeToNextPage = 2 + sizeRightmost
            Else
                If pPlan->cellEnd(iPage) < totalCellCount Then
                    If iPage + 1 >= 5 Then Return SQLITE_CORRUPT
                    Dim sizeDivider As u16 = 0
                    rc = btreeCellArraySize(pCellArray, pPlan->cellEnd(iPage), @sizeDivider)
                    If rc <> SQLITE_OK Then Return rc
                    sizeToNextPage = 2 + sizeDivider
                End If
            End If
            pPlan->usedBytes(iPage + 1) += sizeToNextPage
            pPlan->cellEnd(iPage) -= 1
        Wend

        While pPlan->cellEnd(iPage) < totalCellCount
            If iPage + 1 >= 5 Then Return SQLITE_CORRUPT
            Dim nextSize As u16 = 0
            Dim rc As SQLITE_C_INT = btreeCellArraySize(pCellArray, pPlan->cellEnd(iPage), @nextSize)
            If rc <> SQLITE_OK Then Return rc
            Dim currentCellSize As SQLITE_C_INT = 2 + nextSize
            If pPlan->usedBytes(iPage) + currentCellSize > usableSpace Then Exit While
            pPlan->usedBytes(iPage) += currentCellSize
            pPlan->cellEnd(iPage) += 1

            Dim sizeToSubtract As SQLITE_C_INT = currentCellSize
            If leafData = 0 AndAlso pPlan->cellEnd(iPage) < totalCellCount Then
                If iPage + 1 >= 5 Then Return SQLITE_CORRUPT
                Dim sizeDivider As u16 = 0
                rc = btreeCellArraySize(pCellArray, pPlan->cellEnd(iPage), @sizeDivider)
                If rc <> SQLITE_OK Then Return rc
                sizeToSubtract = 2 + sizeDivider
            ElseIf leafData = 0 Then
                sizeToSubtract = 0
            End If
            pPlan->usedBytes(iPage + 1) -= sizeToSubtract
        Wend

        If pPlan->cellEnd(iPage) >= totalCellCount Then
            pageCount = iPage + 1
        Else
            Dim previousPageBoundary As SQLITE_C_INT
            previousPageBoundary = 0
            If iPage > 0 Then previousPageBoundary = pPlan->cellEnd(iPage - 1)
            If pPlan->cellEnd(iPage) <= previousPageBoundary Then Return SQLITE_CORRUPT
        End If
        iPage += 1
    Wend

    For iPage As SQLITE_C_INT = pageCount - 1 To 1 Step -1
        Dim sizeRight As SQLITE_C_INT = pPlan->usedBytes(iPage)
        Dim sizeLeft As SQLITE_C_INT = pPlan->usedBytes(iPage - 1)
        Dim rightCell As SQLITE_C_INT = pPlan->cellEnd(iPage - 1) - 1
        Dim dividerCell As SQLITE_C_INT = rightCell + 1 - leafData
        If rightCell < 0 OrElse dividerCell < 0 OrElse dividerCell >= totalCellCount Then Return SQLITE_CORRUPT
        Dim ignoredSize As u16 = 0
        Dim rc As SQLITE_C_INT = btreeCellArraySize(pCellArray, dividerCell, @ignoredSize)
        If rc <> SQLITE_OK Then Return rc
        Do
            If rightCell < 0 OrElse dividerCell < 0 Then Exit Do
            Dim sizeLeftCell As u16 = 0
            rc = btreeCellArraySize(pCellArray, rightCell, @sizeLeftCell)
            If rc <> SQLITE_OK Then Return rc
            Dim sizeDividerCell As u16 = 0
            rc = btreeCellArraySize(pCellArray, dividerCell, @sizeDividerCell)
            If rc <> SQLITE_OK Then Return rc
            If sizeRight <> 0 AndAlso (bulkLoad <> 0 OrElse _
               sizeRight + sizeDividerCell + 2 > sizeLeft - _
               (sizeLeftCell + IIf(iPage = pageCount - 1, 0, 2))) Then Exit Do
            sizeRight += sizeDividerCell + 2
            sizeLeft -= sizeLeftCell + 2
            pPlan->cellEnd(iPage - 1) = rightCell
            rightCell -= 1
            dividerCell -= 1
        Loop
        pPlan->usedBytes(iPage) = sizeRight
        pPlan->usedBytes(iPage - 1) = sizeLeft
        Dim previousLeftBoundary As SQLITE_C_INT = 0
        If iPage > 1 Then previousLeftBoundary = pPlan->cellEnd(iPage - 2)
        If pPlan->cellEnd(iPage - 1) <= previousLeftBoundary Then Return SQLITE_CORRUPT
    Next

    pPlan->pageCount = pageCount
    Return SQLITE_OK
End Function

/' ------------------------------------------------------------------------- '/
/' Apply a sibling balance plan '/
/' ------------------------------------------------------------------------- '/

/'
    The caller owns pDividerScratch and keeps it alive until any overflow
    cells queued on pParent have been consumed by a later parent balance.
    This mirrors SQLite's stack scratch lifetime across recursive balancing.
'/ 
Private Function btreeApplyBalancePlan( _
    ByVal pParent As MemPage Ptr, _
    ByVal pState As BtreeBalanceSiblingSet Ptr, _
    ByVal pCellArray As BtreeCellArray Ptr, _
    ByVal pPlan As BtreeBalancePlan Ptr, _
    ByVal pDividerScratch As UByte Ptr, _
    ByVal scratchSize As SQLITE_C_INT, _
    ByVal bulkLoad As SQLITE_C_INT, _
    ByVal isRoot As SQLITE_C_INT _
) As SQLITE_C_INT

    If pParent = 0 OrElse pState = 0 OrElse pCellArray = 0 OrElse _
       pPlan = 0 OrElse pDividerScratch = 0 OrElse scratchSize <= 0 Then Return SQLITE_MISUSE
    If pParent->pBt = 0 OrElse pParent->pDbPage = 0 OrElse pParent->aData = 0 OrElse _
       pParent->isInit = 0 OrElse pState->nOld < 1 OrElse pState->nOld > 3 OrElse _
       pPlan->pageCount < 1 OrElse pPlan->pageCount > 5 OrElse _
       pCellArray->nCell < 0 OrElse pCellArray->apCell = 0 OrElse _
       pCellArray->szCell = 0 OrElse pCellArray->nCell > pState->nMaxCells Then Return SQLITE_MISUSE
    If pState->targetIndex < 0 OrElse pState->targetIndex >= pState->nOld OrElse _
       pState->pRightChild = 0 OrElse pParent->nOverflow <> 0 Then Return SQLITE_CORRUPT
    If (isRoot <> 0 AndAlso isRoot <> 1) OrElse _
       (bulkLoad <> 0 AndAlso bulkLoad <> 1) Then Return SQLITE_MISUSE
    If pCellArray->nCell = 0 AndAlso (isRoot = 0 OrElse pState->nOld <> 1 OrElse _
       pPlan->pageCount <> 1) Then Return SQLITE_CORRUPT
    If sqlite3PagerIswriteable(pParent->pDbPage) = 0 Then Return SQLITE_READONLY

    Dim newPageCount As SQLITE_C_INT = pPlan->pageCount
    Dim oldBoundary(0 To 4) As SQLITE_C_INT
    Dim pNew(0 To 4) As MemPage Ptr
    Dim pageDone(0 To 4) As SQLITE_C_INT
    Dim scratchOffset As SQLITE_C_INT = 0
    For iPage As SQLITE_C_INT = 0 To 4
        oldBoundary(iPage) = pCellArray->nCell
        pNew(iPage) = 0
        pageDone(iPage) = 0
    Next
    Dim previousBoundary As SQLITE_C_INT = 0
    For iPage As SQLITE_C_INT = 0 To newPageCount - 1
        Dim allowEmptyRootPage As SQLITE_C_INT = IIf(pCellArray->nCell = 0 AndAlso _
            isRoot <> 0 AndAlso newPageCount = 1 AndAlso iPage = 0, 1, 0)
        If (allowEmptyRootPage = 0 AndAlso pPlan->cellEnd(iPage) <= previousBoundary) OrElse _
           (allowEmptyRootPage <> 0 AndAlso pPlan->cellEnd(iPage) <> 0) OrElse _
           pPlan->cellEnd(iPage) > pCellArray->nCell OrElse _
           pPlan->usedBytes(iPage) < 0 OrElse pPlan->usedBytes(iPage) > pState->usableSpace Then Return SQLITE_CORRUPT
        previousBoundary = pPlan->cellEnd(iPage)
    Next
    If previousBoundary <> pCellArray->nCell Then Return SQLITE_CORRUPT
    For iPage As SQLITE_C_INT = 0 To pState->nOld - 1
        If pState->apOld(iPage) = 0 Then Return SQLITE_CORRUPT
        oldBoundary(iPage) = pState->cellEndOld(iPage)
    Next

    Dim rc As SQLITE_C_INT = sqlite3PagerWrite(pParent->pDbPage)
    If rc <> SQLITE_OK Then Return rc
    Dim pageFlags As UByte = pState->apOld(0)->aData[pState->apOld(0)->hdrOffset]

    For iPage As SQLITE_C_INT = 0 To newPageCount - 1
        If iPage < pState->nOld Then
            pNew(iPage) = pState->apOld(iPage)
            pState->apOld(iPage) = 0
            If pNew(iPage)->pDbPage = 0 OrElse pNew(iPage)->hdrOffset <> 0 Then
                rc = SQLITE_CORRUPT
                GoTo balance_apply_cleanup
            End If
            rc = sqlite3PagerWrite(pNew(iPage)->pDbPage)
            If rc <> SQLITE_OK Then GoTo balance_apply_cleanup
            Dim expectedReferences As SQLITE_C_INT = 1 + IIf(iPage = pState->targetIndex, 1, 0)
            If sqlite3PagerPageRefcount(pNew(iPage)->pDbPage) <> expectedReferences Then
                rc = SQLITE_CORRUPT
                GoTo balance_apply_cleanup
            End If
        Else
            Dim newPageNumber As u32 = 0
            If pNew(0) = 0 Then
                rc = SQLITE_CORRUPT
                GoTo balance_apply_cleanup
            End If
            ' The old page pointer was transferred to pNew(0) above.
            Dim nearbyPage As u32 = pNew(0)->pgno
            If bulkLoad <> 0 Then nearbyPage = 1
            rc = btreeAllocatePageMode(pParent->pBt, @pNew(iPage), @newPageNumber, _
                PTRMAP_BTREE, pParent->pgno, nearbyPage, BTALLOC_ANY)
            If rc <> SQLITE_OK Then GoTo balance_apply_cleanup
            If pNew(iPage) = 0 OrElse pNew(iPage)->pgno <> newPageNumber Then
                rc = SQLITE_CORRUPT
                GoTo balance_apply_cleanup
            End If
            rc = btreeZeroPage(pNew(iPage), pageFlags)
            If rc <> SQLITE_OK Then GoTo balance_apply_cleanup
        End If
    Next

    If btreePageHasRange(pParent, pState->pRightChild, 4) = 0 Then
        rc = SQLITE_CORRUPT
        GoTo balance_apply_cleanup
    End If
    btreeWriteU32(pState->pRightChild, pNew(newPageCount - 1)->pgno)

    If (pageFlags And PTF_LEAF) = 0 AndAlso pState->nOld <> newPageCount Then
        Dim pOldRightmost As MemPage Ptr = 0
        If newPageCount > pState->nOld Then
            pOldRightmost = pNew(pState->nOld - 1)
        Else
            pOldRightmost = pState->apOld(pState->nOld - 1)
        End If
        If pOldRightmost = 0 OrElse pOldRightmost->aData = 0 OrElse _
           pNew(newPageCount - 1)->aData = 0 Then
            rc = SQLITE_CORRUPT
            GoTo balance_apply_cleanup
        End If
        btreeSystemMemcpy(pNew(newPageCount - 1)->aData + 8, pOldRightmost->aData + 8, 4)
    End If

    For iPage As SQLITE_C_INT = 0 To newPageCount - 2
        Dim boundary As SQLITE_C_INT = pPlan->cellEnd(iPage)
        If boundary < 0 OrElse boundary > pCellArray->nCell Then
            rc = SQLITE_CORRUPT
            GoTo balance_apply_cleanup
        End If

        Dim pDividerCell As UByte Ptr = 0
        Dim dividerSize As SQLITE_C_INT = 0
        If pState->leafData <> 0 Then
            If boundary < 1 Then
                rc = SQLITE_CORRUPT
                GoTo balance_apply_cleanup
            End If
            Dim lastCellIndex As SQLITE_C_INT = boundary - 1
            Dim lastCellSize As u16 = 0
            rc = btreeCellArrayCellSize(pCellArray, lastCellIndex, @lastCellSize)
            If rc <> SQLITE_OK Then GoTo balance_apply_cleanup
            Dim pLastCell As UByte Ptr = pCellArray->apCell[lastCellIndex]
            If pLastCell = 0 OrElse lastCellSize < 2 Then
                rc = SQLITE_CORRUPT
                GoTo balance_apply_cleanup
            End If
            Dim payloadSize As sqlite3_uint64 = 0
            Dim payloadLength As SQLITE_C_INT = 0
            rc = btreeReadCellVarintBounded(pLastCell, lastCellSize, @payloadSize, @payloadLength)
            If rc <> SQLITE_OK OrElse payloadSize > &HFFFFFFFF OrElse payloadLength >= lastCellSize Then
                rc = SQLITE_CORRUPT
                GoTo balance_apply_cleanup
            End If
            Dim rowIdValue As sqlite3_uint64 = 0
            Dim rowIdLength As SQLITE_C_INT = 0
            rc = btreeReadCellVarintBounded(pLastCell + payloadLength, _
                lastCellSize - payloadLength, @rowIdValue, @rowIdLength)
            If rc <> SQLITE_OK OrElse payloadLength + rowIdLength > lastCellSize Then
                rc = SQLITE_CORRUPT
                GoTo balance_apply_cleanup
            End If
            If scratchOffset > scratchSize - 13 Then
                rc = SQLITE_FULL
                GoTo balance_apply_cleanup
            End If
            pDividerCell = pDividerScratch + scratchOffset
            btreeWriteU32(pDividerCell, 0)
            Dim written As SQLITE_C_INT = sqlite3PutVarint(pDividerCell + 4, rowIdValue)
            If written < 1 OrElse written > 9 Then
                rc = SQLITE_CORRUPT
                GoTo balance_apply_cleanup
            End If
            dividerSize = 4 + written
        Else
            If boundary >= pCellArray->nCell Then
                rc = SQLITE_CORRUPT
                GoTo balance_apply_cleanup
            End If
            Dim pArrayCell As UByte Ptr = pCellArray->apCell[boundary]
            If pArrayCell = 0 Then
                rc = SQLITE_CORRUPT
                GoTo balance_apply_cleanup
            End If
            dividerSize = pCellArray->szCell[boundary] + pState->leafCorrection
            If pState->leafCorrection <> 0 Then
                If pState->leafCorrection <> 4 Then
                    rc = SQLITE_CORRUPT
                    GoTo balance_apply_cleanup
                End If
                pArrayCell -= 4
                If pCellArray->szCell[boundary] = 4 Then
                    ' This promoted key still points into a sibling page or
                    ' divider scratch, not pParent->aData. Reparse it with the
                    ' known cell-buffer bound instead of the page-local helper.
                    dividerSize = btreeCellSizeFromBuffer( _
                        pParent, pArrayCell, _
                        CLng(pCellArray->szCell[boundary]) + pState->leafCorrection)
                End If
            End If
            If dividerSize < 4 OrElse dividerSize > pParent->pBt->pageSize Then
                rc = SQLITE_CORRUPT
                GoTo balance_apply_cleanup
            End If
            If scratchOffset > scratchSize - dividerSize Then
                rc = SQLITE_FULL
                GoTo balance_apply_cleanup
            End If
            pDividerCell = pDividerScratch + scratchOffset
            btreeSystemMemcpy(pDividerCell, pArrayCell, CULngInt(dividerSize))
            If pNew(iPage)->leaf = 0 Then
                Dim rightChild As u32 = btreeReadU32(pDividerCell)
                If rightChild < 2 OrElse rightChild > pParent->pBt->nPage Then
                    rc = SQLITE_CORRUPT
                    GoTo balance_apply_cleanup
                End If
                btreeWriteU32(pNew(iPage)->aData + 8, rightChild)
            End If
        End If

        If dividerSize < 4 OrElse dividerSize > 65535 OrElse _
           scratchOffset > scratchSize - dividerSize Then
            rc = SQLITE_FULL
            GoTo balance_apply_cleanup
        End If
        rc = btreeInsertCellWithChild(pParent, pState->nxDiv + iPage, _
            pDividerCell, dividerSize, pNew(iPage)->pgno)
        If rc <> SQLITE_OK Then GoTo balance_apply_cleanup
        scratchOffset += dividerSize
    Next

    For passIndex As SQLITE_C_INT = 1 - newPageCount To newPageCount - 1
        Dim pageIndex As SQLITE_C_INT = passIndex
        If pageIndex < 0 Then pageIndex = -pageIndex
        If pageIndex < 0 OrElse pageIndex >= newPageCount Then
            rc = SQLITE_CORRUPT
            GoTo balance_apply_cleanup
        End If
        If pageDone(pageIndex) <> 0 Then Continue For
        If passIndex < 0 Then
            Dim oldLeftBoundary As SQLITE_C_INT = 0
            Dim newLeftBoundary As SQLITE_C_INT = 0
            If pageIndex > 0 Then
                oldLeftBoundary = oldBoundary(pageIndex - 1)
                newLeftBoundary = pPlan->cellEnd(pageIndex - 1)
            End If
            If oldLeftBoundary >= newLeftBoundary Then
                Dim oldFirstCell As SQLITE_C_INT = 0
                Dim newFirstCell As SQLITE_C_INT = 0
                If pageIndex > 0 Then
                    If pageIndex < pState->nOld Then
                        oldFirstCell = oldBoundary(pageIndex - 1) + IIf(pState->leafData = 0, 1, 0)
                    Else
                        ' A newly allocated sibling has no old cells to remove.
                        oldFirstCell = pCellArray->nCell
                    End If
                    newFirstCell = pPlan->cellEnd(pageIndex - 1) + IIf(pState->leafData = 0, 1, 0)
                End If
                Dim newCellCount As SQLITE_C_INT = pPlan->cellEnd(pageIndex) - newFirstCell
                If newCellCount < 0 OrElse (newCellCount = 0 AndAlso pCellArray->nCell <> 0) Then
                    rc = SQLITE_CORRUPT
                    GoTo balance_apply_cleanup
                End If
                rc = btreeEditPage(pNew(pageIndex), oldFirstCell, newFirstCell, _
                                   newCellCount, pCellArray)
                If rc <> SQLITE_OK Then GoTo balance_apply_cleanup
#ifndef SQLITE_OMIT_AUTOVACUUM
                If pParent->pBt->autoVacuum <> 0 Then
                    rc = setChildPtrmaps(pNew(pageIndex))
                    If rc <> SQLITE_OK Then GoTo balance_apply_cleanup
                End If
#endif
                pNew(pageIndex)->nFree = pState->usableSpace - pPlan->usedBytes(pageIndex)
                pageDone(pageIndex) = 1
            End If
        Else
            Dim oldFirstCell As SQLITE_C_INT = 0
            Dim newFirstCell As SQLITE_C_INT = 0
            If pageIndex > 0 Then
                If pageIndex < pState->nOld Then
                    oldFirstCell = oldBoundary(pageIndex - 1) + IIf(pState->leafData = 0, 1, 0)
                Else
                    oldFirstCell = pCellArray->nCell
                End If
                newFirstCell = pPlan->cellEnd(pageIndex - 1) + IIf(pState->leafData = 0, 1, 0)
            End If
            Dim newCellCount As SQLITE_C_INT = pPlan->cellEnd(pageIndex) - newFirstCell
            If newCellCount < 0 OrElse (newCellCount = 0 AndAlso pCellArray->nCell <> 0) Then
                rc = SQLITE_CORRUPT
                GoTo balance_apply_cleanup
            End If
            rc = btreeEditPage(pNew(pageIndex), oldFirstCell, newFirstCell, _
                               newCellCount, pCellArray)
            If rc <> SQLITE_OK Then GoTo balance_apply_cleanup
#ifndef SQLITE_OMIT_AUTOVACUUM
            If pParent->pBt->autoVacuum <> 0 Then
                rc = setChildPtrmaps(pNew(pageIndex))
                If rc <> SQLITE_OK Then GoTo balance_apply_cleanup
            End If
#endif
            pNew(pageIndex)->nFree = pState->usableSpace - pPlan->usedBytes(pageIndex)
            pageDone(pageIndex) = 1
        End If
    Next

    If isRoot <> 0 AndAlso pParent->nCell = 0 AndAlso _
       pParent->nOverflow = 0 AndAlso pParent->hdrOffset <= pNew(0)->nFree Then
        rc = btreeDefragmentPage(pNew(0))
        If rc <> SQLITE_OK Then GoTo balance_apply_cleanup
        rc = btreeCopyNodeContent(pNew(0), pParent)
        If rc <> SQLITE_OK Then GoTo balance_apply_cleanup
        freePage(pNew(0), rc)
        If rc <> SQLITE_OK Then GoTo balance_apply_cleanup
        sqlite3BtreeReleasePage(pNew(0))
        pNew(0) = 0
    End If

    For iPage As SQLITE_C_INT = newPageCount To pState->nOld - 1
        Dim pOld As MemPage Ptr = pState->apOld(iPage)
        If pOld = 0 Then
            rc = SQLITE_CORRUPT
            GoTo balance_apply_cleanup
        End If
        freePage(pOld, rc)
        If rc <> SQLITE_OK Then GoTo balance_apply_cleanup
        sqlite3BtreeReleasePage(pOld)
        pState->apOld(iPage) = 0
    Next
    rc = SQLITE_OK

balance_apply_cleanup:
    For iPage As SQLITE_C_INT = 0 To 4
        sqlite3BtreeReleasePage(pNew(iPage))
        pNew(iPage) = 0
    Next
    Return rc
End Function

/'
    Assemble and redistribute a sibling set while the caller holds the
    BtShared mutex and a write transaction. The caller retains the one-page
    overflow buffer until any queued parent cells have been rebalanced.
'/ 
Private Function btreeBalanceNonroot CDecl Alias "balance_nonroot" ( _
    ByVal pParent As MemPage Ptr, _
    ByVal parentChildIndex As SQLITE_C_INT, _
    ByVal pOverflowScratch As UByte Ptr, _
    ByVal isRoot As SQLITE_C_INT, _
    ByVal bulkLoad As SQLITE_C_INT _
) As SQLITE_C_INT

    If pParent = 0 OrElse pParent->pBt = 0 Then Return SQLITE_MISUSE
    If pOverflowScratch = 0 Then Return SQLITE_NOMEM
    If (isRoot <> 0 AndAlso isRoot <> 1) OrElse _
       (bulkLoad <> 0 AndAlso bulkLoad <> 1) Then Return SQLITE_MISUSE

    Dim siblingSet As BtreeBalanceSiblingSet
    Dim rc As SQLITE_C_INT = btreeCollectBalanceSiblings(pParent, parentChildIndex, _
                                                         bulkLoad, @siblingSet)
    If rc <> SQLITE_OK Then
        btreeReleaseBalanceSiblingSet(@siblingSet)
        Return rc
    End If

    Dim maxCells As SQLITE_C_INT = siblingSet.nMaxCells
    If maxCells < siblingSet.nOld OrElse maxCells > &H7FFFFFFB Then
        btreeReleaseBalanceSiblingSet(@siblingSet)
        Return SQLITE_CORRUPT
    End If
    maxCells = (maxCells + 3) And &H7FFFFFFC
    Dim pointerBytes As sqlite3_uint64 = CULngInt(maxCells) * SizeOf(UByte Ptr)
    Dim cellSizeBytes As sqlite3_uint64 = CULngInt(maxCells) * SizeOf(u16)
    If pointerBytes > SQLITE_MAX_ALLOCATION_SIZE OrElse _
       cellSizeBytes > SQLITE_MAX_ALLOCATION_SIZE - pointerBytes OrElse _
       pParent->pBt->pageSize > SQLITE_MAX_ALLOCATION_SIZE - pointerBytes - cellSizeBytes Then
        btreeReleaseBalanceSiblingSet(@siblingSet)
        Return SQLITE_NOMEM
    End If
    Dim scratchBytes As sqlite3_uint64 = pointerBytes + cellSizeBytes + pParent->pBt->pageSize
    Dim pScratch As UByte Ptr = CPtr(UByte Ptr, sqlite3Malloc(scratchBytes))
    If pScratch = 0 Then
        btreeReleaseBalanceSiblingSet(@siblingSet)
        Return SQLITE_NOMEM
    End If

    Dim cellArray As BtreeCellArray
    cellArray.nCell = maxCells
    cellArray.pRef = 0
    cellArray.apCell = CPtr(UByte Ptr Ptr, pScratch)
    cellArray.szCell = CPtr(u16 Ptr, pScratch + pointerBytes)
    Dim pCellCopyScratch As UByte Ptr = pScratch + pointerBytes + cellSizeBytes

    rc = btreeBuildBalanceCellArray(pParent, @siblingSet, @cellArray, _
                                    pCellCopyScratch, CLng(pParent->pBt->pageSize))
    Dim balancePlan As BtreeBalancePlan
    If rc = SQLITE_OK Then rc = btreePlanBalancePages(@cellArray, @siblingSet, bulkLoad, @balancePlan)
    If rc = SQLITE_OK Then
        rc = btreeApplyBalancePlan(pParent, @siblingSet, @cellArray, @balancePlan, _
                                   pOverflowScratch, CLng(pParent->pBt->pageSize), _
                                   bulkLoad, isRoot)
    End If

    sqlite3_free(pScratch)
    btreeReleaseBalanceSiblingSet(@siblingSet)
    Return rc
End Function

Private Function anotherValidCursor CDecl Alias "anotherValidCursor" ( _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT
    If pCursor = 0 OrElse pCursor->pBt = 0 Then Return SQLITE_MISUSE
    Dim pOther As BtCursor Ptr = CPtr(BtCursor Ptr, pCursor->pBt->pCursor)
    While pOther <> 0
        If pOther <> pCursor AndAlso pOther->eState = CURSOR_VALID AndAlso _
           pOther->pPage = pCursor->pPage Then Return SQLITE_CORRUPT
        pOther = pOther->pNext
    Wend
    Return SQLITE_OK
End Function

/'
    Rebalance the modified cursor page and walk toward the root while parent
    pages acquire overflow cells. The caller holds BtShared.mutex and has an
    active write transaction. Scratch pages remain live until the next
    parent balance has copied any queued divider cells.
'/ 
Private Function btreeBalanceCursor CDecl Alias "balance" ( _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT
    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pCursor->pBtree = 0 OrElse _
       pCursor->pBtree->inTrans <> TRANS_WRITE OrElse pCursor->pPage = 0 OrElse _
       pCursor->iPage < 0 OrElse pCursor->iPage >= BTCURSOR_MAX_DEPTH Then Return SQLITE_MISUSE
    If (pCursor->curFlags And BTCF_WRITE_FLAG) = 0 OrElse _
       (pCursor->pBt->btsFlags And BTS_READ_ONLY) <> 0 Then Return SQLITE_READONLY

    Dim pPreviousScratch As UByte Ptr = 0
    Dim quickBalanceScratch(0 To 12) As UByte
    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim balanceDepth As SQLITE_C_INT = 0

    Do While rc = SQLITE_OK
        If balanceDepth >= BTCURSOR_MAX_DEPTH * 2 OrElse _
           pCursor->iPage < 0 OrElse pCursor->iPage >= BTCURSOR_MAX_DEPTH OrElse _
           pCursor->pPage = 0 Then
            rc = SQLITE_CORRUPT
            Exit Do
        End If
        balanceDepth += 1

        Dim pPage As MemPage Ptr = pCursor->pPage
        If pPage->pBt <> pCursor->pBt OrElse pPage->isInit = 0 Then
            rc = SQLITE_CORRUPT
            Exit Do
        End If
        If pPage->nFree < 0 Then
            rc = sqlite3BtreeComputeFreeSpace(pPage)
            If rc <> SQLITE_OK Then Exit Do
        End If
        If pPage->nOverflow = 0 AndAlso _
           CULng(pPage->nFree) * 3 <= CULng(pCursor->pBt->usableSize) * 2 Then Exit Do

        If pCursor->iPage = 0 Then
            If pPage->nOverflow = 0 Then Exit Do
            rc = anotherValidCursor(pCursor)
            If rc <> SQLITE_OK Then Exit Do
            If pCursor->iPage + 1 >= BTCURSOR_MAX_DEPTH - 1 Then
                rc = SQLITE_CORRUPT
                Exit Do
            End If
            rc = btreeBalanceDeeper(pPage, @pCursor->apPage(1))
            If rc = SQLITE_OK Then
                pCursor->iPage = 1
                pCursor->ix = 0
                pCursor->aiIdx(0) = 0
                pCursor->apPage(0) = pPage
                pCursor->pPage = pCursor->apPage(1)
            End If
            Continue Do
        End If

        If sqlite3PagerPageRefcount(pPage->pDbPage) > 1 Then
            rc = SQLITE_CORRUPT
            Exit Do
        End If
        Dim parentIndex As SQLITE_C_INT = pCursor->iPage - 1
        Dim pParent As MemPage Ptr = pCursor->apPage(parentIndex)
        Dim childIndex As SQLITE_C_INT = pCursor->aiIdx(parentIndex)
        If pParent = 0 OrElse pParent->isInit = 0 OrElse _
           pParent->pBt <> pCursor->pBt OrElse childIndex < 0 OrElse _
           childIndex > pParent->nCell + pParent->nOverflow Then
            rc = SQLITE_CORRUPT
            Exit Do
        End If

        rc = sqlite3PagerWrite(pParent->pDbPage)
        If rc = SQLITE_OK AndAlso pParent->nFree < 0 Then
            rc = sqlite3BtreeComputeFreeSpace(pParent)
        End If
        If rc <> SQLITE_OK Then Exit Do

        If pPage->intKeyLeaf <> 0 AndAlso pPage->nOverflow = 1 AndAlso _
           pPage->aiOvfl(0) = pPage->nCell AndAlso pParent->pgno <> 1 AndAlso _
           pParent->nCell = childIndex Then
            rc = btreeBalanceQuick(pParent, pPage, @quickBalanceScratch(0))
        Else
            Dim pCurrentScratch As UByte Ptr = CPtr(UByte Ptr, sqlite3PageMalloc(CLng(pCursor->pBt->pageSize)))
            If pCurrentScratch = 0 Then
                rc = SQLITE_NOMEM
            Else
                rc = btreeBalanceNonroot(pParent, childIndex, pCurrentScratch, _
                    IIf(pCursor->iPage = 1, 1, 0), _
                    IIf((pCursor->hints And BTREE_BULKLOAD) <> 0, 1, 0))
            End If
            If pPreviousScratch <> 0 Then sqlite3PageFree(pPreviousScratch)
            pPreviousScratch = pCurrentScratch
        End If

        pPage->nOverflow = 0
        sqlite3BtreeReleasePage(pPage)
        pCursor->iPage -= 1
        If pCursor->iPage < 0 Then
            rc = SQLITE_CORRUPT
            Exit Do
        End If
        pCursor->pPage = pCursor->apPage(pCursor->iPage)
        pCursor->ix = pCursor->aiIdx(pCursor->iPage)
        btreeCursorClearCellInfo(pCursor)
    Loop

    If pPreviousScratch <> 0 Then sqlite3PageFree(pPreviousScratch)
    Return rc
End Function

Private Function btreeRebuildPage( _
    ByVal pCellArray As BtreeCellArray Ptr, _
    ByVal firstCell As SQLITE_C_INT, _
    ByVal cellCount As SQLITE_C_INT, _
    ByVal pPage As MemPage Ptr _
) As SQLITE_C_INT

    If pCellArray = 0 OrElse pPage = 0 OrElse pPage->pBt = 0 OrElse _
       pPage->pDbPage = 0 OrElse pPage->aData = 0 OrElse pCellArray->pRef = 0 OrElse _
       pCellArray->apCell = 0 OrElse pCellArray->szCell = 0 OrElse _
       pCellArray->nCell < 0 OrElse firstCell < 0 OrElse cellCount < 0 OrElse _
       CULngInt(firstCell) + cellCount > pCellArray->nCell OrElse cellCount >= 10922 Then Return SQLITE_MISUSE
    If sqlite3PagerIswriteable(pPage->pDbPage) = 0 Then Return SQLITE_READONLY

    Dim pData As UByte Ptr = pPage->aData
    Dim pageBase As sqlite3_uint64 = CULngInt(pData)
    Dim usableSize As sqlite3_uint64 = pPage->pBt->usableSize
    Dim pageEnd As sqlite3_uint64 = pageBase + usableSize
    Dim oldContentOffset As sqlite3_uint64 = btreeGetU16(pData + pPage->hdrOffset + 5)
    If oldContentOffset > usableSize Then oldContentOffset = 0
    Dim pTemporary As UByte Ptr = CPtr(UByte Ptr, sqlite3PagerTempSpace(pPage->pBt->pPager))
    If pTemporary = 0 Then Return SQLITE_NOMEM
    btreeSystemMemcpy(pTemporary + oldContentOffset, pData + oldContentOffset, _
                      CULngInt(usableSize - oldContentOffset))

    Dim stageIndex As SQLITE_C_INT = 0
    Dim sourceEnd As sqlite3_uint64 = 0
    If cellCount > 0 Then
        While stageIndex < BTREE_BALANCE_STAGE_COUNT AndAlso _
              pCellArray->ixNx(stageIndex) <= firstCell
            stageIndex += 1
        Wend
        If stageIndex >= BTREE_BALANCE_STAGE_COUNT OrElse _
           pCellArray->ixNx(BTREE_BALANCE_STAGE_COUNT - 1) < firstCell + cellCount Then Return SQLITE_CORRUPT
        If pCellArray->apEnd(stageIndex) = 0 Then Return SQLITE_CORRUPT
        sourceEnd = CULngInt(pCellArray->apEnd(stageIndex))
    End If
    Dim destinationAddress As sqlite3_uint64 = pageEnd
    Dim pointerAddress As sqlite3_uint64 = CULngInt(pPage->aCellIdx)

    For cellOffset As SQLITE_C_INT = 0 To cellCount - 1
        Dim sourceIndex As SQLITE_C_INT = firstCell + cellOffset
        Dim pCell As UByte Ptr = pCellArray->apCell[sourceIndex]
        If pCell = 0 Then Return SQLITE_CORRUPT
        ' Cell data may be overwritten as earlier cells are copied into place.
        ' The cache was populated before editing, so its size remains authoritative.
        Dim cellSize As u16 = pCellArray->szCell[sourceIndex]
        If cellSize < 4 OrElse cellSize > pPage->pBt->usableSize Then Return SQLITE_CORRUPT

        Dim cellAddress As sqlite3_uint64 = CULngInt(pCell)
        Dim cellEnd As sqlite3_uint64 = cellAddress + cellSize
        If cellEnd < cellAddress Then Return SQLITE_CORRUPT
        If cellAddress >= pageBase + oldContentOffset AndAlso cellAddress < pageEnd Then
            If cellEnd > pageEnd Then Return SQLITE_CORRUPT
            pCell = pTemporary + (cellAddress - pageBase)
        ElseIf cellAddress < sourceEnd AndAlso cellEnd > sourceEnd Then
            Return SQLITE_CORRUPT
        End If

        If CULngInt(cellSize) > destinationAddress - pageBase Then Return SQLITE_CORRUPT
        destinationAddress -= cellSize
        If destinationAddress < pointerAddress + (2 * cellOffset) + 2 Then Return SQLITE_CORRUPT
        btreeWriteU16(pPage->aCellIdx + (2 * cellOffset), CUShort(destinationAddress - pageBase))
        btreeSystemMemmove(CPtr(Any Ptr, destinationAddress), pCell, CULngInt(cellSize))

        Dim nextCellIndex As SQLITE_C_INT = sourceIndex + 1
        If nextCellIndex < firstCell + cellCount AndAlso pCellArray->ixNx(stageIndex) <= nextCellIndex Then
            stageIndex += 1
            If stageIndex >= BTREE_BALANCE_STAGE_COUNT OrElse pCellArray->apEnd(stageIndex) = 0 Then Return SQLITE_CORRUPT
            sourceEnd = CULngInt(pCellArray->apEnd(stageIndex))
        End If
    Next

    pPage->nCell = CUShort(cellCount)
    pPage->nOverflow = 0
    btreeWriteU16(pData + pPage->hdrOffset + 1, 0)
    btreeWriteU16(pData + pPage->hdrOffset + 3, pPage->nCell)
    btreeWriteU16(pData + pPage->hdrOffset + 5, CUShort(destinationAddress - pageBase))
    pData[pPage->hdrOffset + 7] = 0
    pPage->nFree = -1
#ifndef SQLITE_OMIT_AUTOVACUUM
    If pPage->pBt->autoVacuum <> 0 Then Return setChildPtrmaps(pPage)
#endif
    Return SQLITE_OK
End Function

Private Function btreePageInsertArray( _
    ByVal pPage As MemPage Ptr, _
    ByVal pBegin As UByte Ptr, _
    ByVal ppData As UByte Ptr Ptr, _
    ByVal pCellPointers As UByte Ptr, _
    ByVal firstCell As SQLITE_C_INT, _
    ByVal cellCount As SQLITE_C_INT, _
    ByVal pCellArray As BtreeCellArray Ptr _
) As SQLITE_C_INT

    If pPage = 0 OrElse pPage->pBt = 0 OrElse pPage->aData = 0 OrElse _
       pBegin = 0 OrElse ppData = 0 OrElse ppData[0] = 0 OrElse _
       pCellPointers = 0 OrElse pCellArray = 0 OrElse pCellArray->apCell = 0 OrElse _
       pCellArray->szCell = 0 OrElse pPage->hdrOffset <> 0 OrElse _
       firstCell < 0 OrElse cellCount < 0 OrElse _
       CULngInt(firstCell) + cellCount > pCellArray->nCell Then Return SQLITE_MISUSE
    If cellCount = 0 Then Return SQLITE_OK

    Dim stageIndex As SQLITE_C_INT = 0
    While stageIndex < BTREE_BALANCE_STAGE_COUNT AndAlso _
          pCellArray->ixNx(stageIndex) <= firstCell
        stageIndex += 1
    Wend
    If stageIndex >= BTREE_BALANCE_STAGE_COUNT OrElse _
       pCellArray->ixNx(BTREE_BALANCE_STAGE_COUNT - 1) < firstCell + cellCount OrElse _
       pCellArray->apEnd(stageIndex) = 0 Then Return SQLITE_CORRUPT

    Dim pData As UByte Ptr = ppData[0]
    Dim pageBase As sqlite3_uint64 = CULngInt(pPage->aData)
    Dim pageEnd As sqlite3_uint64 = pageBase + pPage->pBt->usableSize
    Dim beginAddress As sqlite3_uint64 = CULngInt(pBegin)
    Dim dataAddress As sqlite3_uint64 = CULngInt(pData)
    Dim pointerAddress As sqlite3_uint64 = CULngInt(pCellPointers)
    If pPage->pBt->usableSize = 0 OrElse beginAddress < pageBase OrElse beginAddress > pageEnd OrElse _
       pointerAddress < pageBase OrElse pointerAddress > pageEnd OrElse _
       CULngInt(cellCount) * 2 > pageEnd - pointerAddress OrElse _
       dataAddress < pageBase OrElse dataAddress > pageEnd Then Return SQLITE_CORRUPT
    Dim sourceEnd As sqlite3_uint64 = CULngInt(pCellArray->apEnd(stageIndex))
    If sourceEnd = 0 Then Return SQLITE_CORRUPT

    For cellOffset As SQLITE_C_INT = 0 To cellCount - 1
        Dim sourceIndex As SQLITE_C_INT = firstCell + cellOffset
        Dim pCell As UByte Ptr = pCellArray->apCell[sourceIndex]
        Dim cellSize As u16 = pCellArray->szCell[sourceIndex]
        If pCell = 0 OrElse cellSize < 4 OrElse cellSize > pPage->pBt->usableSize Then Return SQLITE_CORRUPT

        Dim pSlot As UByte Ptr = 0
        Dim rcSlot As SQLITE_C_INT = SQLITE_OK
        If pPage->aData[pPage->hdrOffset + 1] <> 0 OrElse pPage->aData[pPage->hdrOffset + 2] <> 0 Then
            pSlot = btreePageFindSlot(pPage, cellSize, @rcSlot)
            If pSlot = 0 AndAlso rcSlot <> SQLITE_OK Then Return rcSlot
        End If
        If pSlot = 0 Then
            If dataAddress < beginAddress OrElse CULngInt(cellSize) > dataAddress - beginAddress Then Return SQLITE_FULL
            dataAddress -= cellSize
            pSlot = CPtr(UByte Ptr, dataAddress)
        End If

        Dim slotAddress As sqlite3_uint64 = CULngInt(pSlot)
        Dim cellAddress As sqlite3_uint64 = CULngInt(pCell)
        Dim cellEnd As sqlite3_uint64 = cellAddress + cellSize
        If slotAddress < beginAddress OrElse slotAddress < pageBase OrElse slotAddress > pageEnd OrElse _
           CULngInt(cellSize) > pageEnd - slotAddress OrElse cellEnd < cellAddress Then Return SQLITE_CORRUPT
        If cellAddress < sourceEnd AndAlso cellEnd > sourceEnd Then Return SQLITE_CORRUPT

        btreeSystemMemmove(pSlot, pCell, CULngInt(cellSize))
        Dim cellPointerOffset As sqlite3_uint64 = slotAddress - pageBase
        If cellPointerOffset > 65535 Then Return SQLITE_CORRUPT
        btreeWriteU16(pCellPointers, CUShort(cellPointerOffset))
        pCellPointers += 2

        Dim nextCellIndex As SQLITE_C_INT = sourceIndex + 1
        If nextCellIndex < firstCell + cellCount AndAlso pCellArray->ixNx(stageIndex) <= nextCellIndex Then
            stageIndex += 1
            If stageIndex >= BTREE_BALANCE_STAGE_COUNT OrElse pCellArray->apEnd(stageIndex) = 0 Then Return SQLITE_CORRUPT
            sourceEnd = CULngInt(pCellArray->apEnd(stageIndex))
        End If
    Next

    ppData[0] = CPtr(UByte Ptr, dataAddress)
    Return SQLITE_OK
End Function

Private Function btreePageFreeArray( _
    ByVal pPage As MemPage Ptr, _
    ByVal firstCell As SQLITE_C_INT, _
    ByVal cellCount As SQLITE_C_INT, _
    ByVal pCellArray As BtreeCellArray Ptr, _
    ByVal pFreedCount As SQLITE_C_INT Ptr _
) As SQLITE_C_INT

    If pFreedCount <> 0 Then pFreedCount[0] = 0
    If pPage = 0 OrElse pPage->pBt = 0 OrElse pPage->aData = 0 OrElse _
       pCellArray = 0 OrElse pCellArray->apCell = 0 OrElse pCellArray->szCell = 0 OrElse _
       pFreedCount = 0 OrElse firstCell < 0 OrElse cellCount < 0 OrElse _
       CULngInt(firstCell) + cellCount > pCellArray->nCell Then Return SQLITE_MISUSE
    If cellCount = 0 Then Return SQLITE_OK

    Dim pageBase As sqlite3_uint64 = CULngInt(pPage->aData)
    Dim pageEnd As sqlite3_uint64 = pageBase + pPage->pBt->usableSize
    Dim firstCellAddress As sqlite3_uint64 = pageBase + pPage->hdrOffset + 8 + pPage->childPtrSize
    Dim blockStart(0 To 9) As SQLITE_C_INT
    Dim blockEnd(0 To 9) As SQLITE_C_INT
    Dim freeBlockCount As SQLITE_C_INT = 0
    Dim freedCount As SQLITE_C_INT = 0

    For cellIndex As SQLITE_C_INT = firstCell To firstCell + cellCount - 1
        Dim pCell As UByte Ptr = pCellArray->apCell[cellIndex]
        Dim cellSize As u16 = pCellArray->szCell[cellIndex]
        If pCell = 0 Then Return SQLITE_CORRUPT
        Dim cellAddress As sqlite3_uint64 = CULngInt(pCell)
        If cellAddress >= firstCellAddress AndAlso cellAddress < pageEnd Then
            If cellSize < 4 Then Return SQLITE_CORRUPT
            Dim cellEnd As sqlite3_uint64 = cellAddress + cellSize
            If cellEnd < cellAddress OrElse cellEnd > pageEnd OrElse _
               cellAddress - pageBase > &H7FFFFFFF Then Return SQLITE_CORRUPT
            Dim startOffset As SQLITE_C_INT = CLng(cellAddress - pageBase)
            Dim endOffset As SQLITE_C_INT = startOffset + cellSize
            Dim merged As SQLITE_C_INT = 0
            For blockIndex As SQLITE_C_INT = 0 To freeBlockCount - 1
                If blockStart(blockIndex) = endOffset Then
                    blockStart(blockIndex) = startOffset
                    merged = 1
                    Exit For
                ElseIf blockEnd(blockIndex) = startOffset Then
                    blockEnd(blockIndex) = endOffset
                    merged = 1
                    Exit For
                End If
            Next
            If merged = 0 Then
                If freeBlockCount = 10 Then
                    For blockIndex As SQLITE_C_INT = 0 To freeBlockCount - 1
                        Dim rcFree As SQLITE_C_INT = btreeFreeSpace(pPage, blockStart(blockIndex), _
                                                                    blockEnd(blockIndex) - blockStart(blockIndex))
                        If rcFree <> SQLITE_OK Then Return rcFree
                    Next
                    freeBlockCount = 0
                End If
                blockStart(freeBlockCount) = startOffset
                blockEnd(freeBlockCount) = endOffset
                freeBlockCount += 1
            End If
            freedCount += 1
        End If
    Next

    For blockIndex As SQLITE_C_INT = 0 To freeBlockCount - 1
        Dim rcFree As SQLITE_C_INT = btreeFreeSpace(pPage, blockStart(blockIndex), _
                                                    blockEnd(blockIndex) - blockStart(blockIndex))
        If rcFree <> SQLITE_OK Then Return rcFree
    Next
    pFreedCount[0] = freedCount
    Return SQLITE_OK
End Function

Private Function btreeEditPage( _
    ByVal pPage As MemPage Ptr, _
    ByVal oldFirstCell As SQLITE_C_INT, _
    ByVal newFirstCell As SQLITE_C_INT, _
    ByVal newCellCount As SQLITE_C_INT, _
    ByVal pCellArray As BtreeCellArray Ptr _
) As SQLITE_C_INT

    If pPage = 0 OrElse pPage->pBt = 0 OrElse pPage->aData = 0 OrElse _
       pPage->pDbPage = 0 OrElse pPage->isInit = 0 OrElse pPage->hdrOffset <> 0 OrElse _
       pCellArray = 0 OrElse oldFirstCell < 0 OrElse newFirstCell < 0 OrElse _
       newCellCount < 0 OrElse newCellCount >= 10922 OrElse pPage->nOverflow > 3 Then Return SQLITE_MISUSE
    If sqlite3PagerIswriteable(pPage->pDbPage) = 0 Then Return SQLITE_READONLY
    If pPage->nFree < 0 Then
        Dim rcCompute As SQLITE_C_INT = sqlite3BtreeComputeFreeSpace(pPage)
        If rcCompute <> SQLITE_OK Then Return rcCompute
    End If

    Dim oldCellCount As SQLITE_C_INT = pPage->nCell + pPage->nOverflow
    Dim oldEnd As sqlite3_uint64 = CULngInt(oldFirstCell) + oldCellCount
    Dim newEnd As sqlite3_uint64 = CULngInt(newFirstCell) + newCellCount
    If oldEnd > pCellArray->nCell OrElse newEnd > pCellArray->nCell Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = btreePopulateCellCache(pCellArray, oldFirstCell, oldCellCount)
    If rc <> SQLITE_OK Then Return rc
    rc = btreePopulateCellCache(pCellArray, newFirstCell, newCellCount)
    If rc <> SQLITE_OK Then Return rc

    Dim pPageData As UByte Ptr = pPage->aData
    Dim pBegin As UByte Ptr = pPage->aCellIdx + (2 * newCellCount)
    Dim pageBase As sqlite3_uint64 = CULngInt(pPageData)
    Dim usableEnd As sqlite3_uint64 = pageBase + pPage->pBt->usableSize
    If CULngInt(pBegin) < pageBase OrElse CULngInt(pBegin) > usableEnd Then Return SQLITE_CORRUPT

    Dim physicalCellCount As SQLITE_C_INT = pPage->nCell
    If oldFirstCell < newFirstCell Then
        Dim nShift As SQLITE_C_INT = 0
        rc = btreePageFreeArray(pPage, oldFirstCell, newFirstCell - oldFirstCell, pCellArray, @nShift)
        If rc <> SQLITE_OK Then Return rc
        If nShift > physicalCellCount Then Return SQLITE_CORRUPT
        For iByte As Long = 0 To (physicalCellCount - nShift) * 2 - 1
            pPage->aCellIdx[iByte] = pPage->aCellIdx[iByte + (nShift * 2)]
        Next
        physicalCellCount -= nShift
    End If

    If newEnd < oldEnd Then
        Dim nTail As SQLITE_C_INT = 0
        rc = btreePageFreeArray(pPage, CInt(newEnd), CInt(oldEnd - newEnd), pCellArray, @nTail)
        If rc <> SQLITE_OK Then Return rc
        If nTail > physicalCellCount Then Return SQLITE_CORRUPT
        physicalCellCount -= nTail
    End If

    Dim topOffset As Long = btreeGetU16(pPageData + pPage->hdrOffset + 5)
    Dim dataAddress As sqlite3_uint64 = pageBase + topOffset
    Dim beginAddress As sqlite3_uint64 = CULngInt(pBegin)
    Dim pContentData As UByte Ptr = 0
    If topOffset > pPage->pBt->usableSize Then Return SQLITE_CORRUPT
    If dataAddress < beginAddress OrElse dataAddress > usableEnd Then GoTo edit_page_rebuild
    pContentData = pPageData + topOffset

    If newFirstCell < oldFirstCell Then
        Dim nAdd As SQLITE_C_INT = newCellCount
        If nAdd > oldFirstCell - newFirstCell Then nAdd = oldFirstCell - newFirstCell
        If oldFirstCell - newFirstCell >= newCellCount AndAlso physicalCellCount <> 0 Then Return SQLITE_CORRUPT
        For iByte As Long = physicalCellCount * 2 - 1 To 0 Step -1
            pPage->aCellIdx[iByte + (nAdd * 2)] = pPage->aCellIdx[iByte]
        Next
        rc = btreePageInsertArray(pPage, pBegin, @pContentData, pPage->aCellIdx, _
                                  newFirstCell, nAdd, pCellArray)
        If rc = SQLITE_FULL Then GoTo edit_page_rebuild
        If rc <> SQLITE_OK Then Return rc
        physicalCellCount += nAdd
    End If

    For overflowIndex As SQLITE_C_INT = 0 To pPage->nOverflow - 1
        Dim newIndex As SQLITE_C_INT = (oldFirstCell + pPage->aiOvfl(overflowIndex)) - newFirstCell
        If newIndex >= 0 AndAlso newIndex < newCellCount Then
            Dim pCellPointer As UByte Ptr = pPage->aCellIdx + (2 * newIndex)
            If physicalCellCount > newIndex Then
                For iCell As Long = physicalCellCount To newIndex + 1 Step -1
                    Dim pDestination As UByte Ptr = pPage->aCellIdx + (2 * iCell)
                    pDestination[0] = pDestination[-2]
                    pDestination[1] = pDestination[-1]
                Next
            End If
            physicalCellCount += 1
            rc = btreePageInsertArray(pPage, pBegin, @pContentData, pCellPointer, _
                                      newIndex + newFirstCell, 1, pCellArray)
            If rc = SQLITE_FULL Then GoTo edit_page_rebuild
            If rc <> SQLITE_OK Then Return rc
        End If
    Next

    If physicalCellCount > newCellCount Then Return SQLITE_CORRUPT
    rc = btreePageInsertArray(pPage, pBegin, @pContentData, _
        pPage->aCellIdx + (physicalCellCount * 2), _
        newFirstCell + physicalCellCount, newCellCount - physicalCellCount, pCellArray)
    If rc = SQLITE_FULL Then GoTo edit_page_rebuild
    If rc <> SQLITE_OK Then Return rc

    pPage->nCell = CUShort(newCellCount)
    pPage->nOverflow = 0
    btreeWriteU16(pPageData + pPage->hdrOffset + 3, pPage->nCell)
    btreeWriteU16(pPageData + pPage->hdrOffset + 5, CUShort(CULngInt(pContentData) - pageBase))
    pPage->nFree = -1
    Return SQLITE_OK

edit_page_rebuild:
    Return btreeRebuildPage(pCellArray, newFirstCell, newCellCount, pPage)
End Function

Private Function btreeClearDatabasePage( _
    ByVal pBt As BtShared Ptr, _
    ByVal pageNumber As u32, _
    ByVal shouldFreePage As SQLITE_C_INT, _
    ByVal pChangeCount As sqlite3_int64 Ptr, _
    ByVal depth As SQLITE_C_INT _
) As SQLITE_C_INT

    If pBt = 0 OrElse depth < 0 OrElse depth > BTCURSOR_MAX_DEPTH OrElse _
       pageNumber = 0 OrElse pageNumber > pBt->nPage Then Return SQLITE_CORRUPT
    Dim pPage As MemPage Ptr = 0
    Dim rc As SQLITE_C_INT = sqlite3BtreeGetAndInitPage(pBt, pageNumber, @pPage, 0)
    If rc <> SQLITE_OK Then Return rc
    If pPage = 0 OrElse pPage->aData = 0 OrElse pPage->pDbPage = 0 Then
        sqlite3BtreeReleasePage(pPage)
        Return SQLITE_CORRUPT
    End If

    If (pBt->openFlags And BTREE_SINGLE) = 0 Then
        Dim expectedReferences As SQLITE_C_INT = 1
        If pageNumber = 1 AndAlso pBt->pPage1 <> 0 Then expectedReferences += 1
        If sqlite3PagerPageRefcount(pPage->pDbPage) <> expectedReferences Then
            sqlite3BtreeReleasePage(pPage)
            Return SQLITE_LOCKED
        End If
    End If

    Dim cellCount As SQLITE_C_INT = pPage->nCell
    For cellIndex As SQLITE_C_INT = 0 To cellCount - 1
        Dim pCell As UByte Ptr = btreeCursorCell(pPage, cellIndex)
        If pCell = 0 Then
            rc = SQLITE_CORRUPT
            Exit For
        End If
        Dim cellInfo As CellInfo
        rc = sqlite3BtreeGetCellInfo(pPage, cellIndex, @cellInfo)
        If rc <> SQLITE_OK OrElse cellInfo.nSize = 0 OrElse _
           btreePageHasRange(pPage, pCell, cellInfo.nSize) = 0 Then
            If rc = SQLITE_OK Then rc = SQLITE_CORRUPT
            Exit For
        End If

        If pPage->leaf = 0 Then
            If btreePageHasRange(pPage, pCell, 4) = 0 Then
                rc = SQLITE_CORRUPT
                Exit For
            End If
            Dim childPage As u32 = btreeReadU32(pCell)
            rc = btreeClearDatabasePage(pBt, childPage, 1, pChangeCount, depth + 1)
            If rc <> SQLITE_OK Then Exit For
        End If

        rc = btreeClearCellOverflow(pPage, pCell, @cellInfo)
        If rc <> SQLITE_OK Then Exit For
    Next

    If rc = SQLITE_OK AndAlso pPage->leaf = 0 Then
        Dim rightChildOffset As Long = pPage->hdrOffset + 8
        If btreePageHasRange(pPage, pPage->aData + rightChildOffset, 4) = 0 Then
            rc = SQLITE_CORRUPT
        Else
            Dim rightChild As u32 = btreeReadU32(pPage->aData + rightChildOffset)
            rc = btreeClearDatabasePage(pBt, rightChild, 1, pChangeCount, depth + 1)
        End If
    End If

    If rc = SQLITE_OK AndAlso pChangeCount <> 0 AndAlso _
       (pPage->intKey = 0 OrElse pPage->leaf <> 0) Then
        pChangeCount[0] += cellCount
    End If

    If rc = SQLITE_OK Then
        If shouldFreePage <> 0 Then
            freePage(pPage, rc)
        Else
            Dim pageFlags As UByte = pPage->aData[pPage->hdrOffset] Or PTF_LEAF
            rc = sqlite3PagerWrite(pPage->pDbPage)
            If rc = SQLITE_OK Then rc = btreeZeroPage(pPage, pageFlags)
        End If
    End If
    sqlite3BtreeReleasePage(pPage)
    Return rc
End Function

Private Function btreeClearTableLocked( _
    ByVal pBtree As Btree Ptr, _
    ByVal rootPage As SQLITE_C_INT, _
    ByVal pChangeCount As sqlite3_int64 Ptr _
) As SQLITE_C_INT

    If pBtree = 0 OrElse pBtree->pBt = 0 OrElse rootPage < 1 Then Return SQLITE_MISUSE
    Dim pBt As BtShared Ptr = pBtree->pBt
    If pBt->pPage1 = 0 Then Return SQLITE_MISUSE
    If (pBt->btsFlags And BTS_READ_ONLY) <> 0 Then
        Return SQLITE_READONLY
    End If
    If CULng(rootPage) > pBt->nPage Then
        Return SQLITE_CORRUPT
    End If

    Dim rc As SQLITE_C_INT = btreeSaveAllCursors(pBt, CULng(rootPage), 0)
    If rc = SQLITE_OK Then
        invalidateIncrblobCursors(pBtree, CULng(rootPage), 0, 1)
        rc = btreeClearDatabasePage(pBt, CULng(rootPage), 0, pChangeCount, 0)
    End If
    Return rc
End Function

Function sqlite3BtreeClearTable CDecl Alias "sqlite3BtreeClearTable" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal rootPage As SQLITE_C_INT, _
    ByVal pChangeCount As sqlite3_int64 Ptr _
) As SQLITE_C_INT Export

    If pBtree = 0 OrElse pBtree->pBt = 0 OrElse rootPage < 1 Then Return SQLITE_MISUSE
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    If pBtree->inTrans <> TRANS_WRITE OrElse pBt->inTransaction <> TRANS_WRITE Then
        sqlite3BtreeLeave(pBtree)
        Return SQLITE_MISUSE
    End If
    If (pBt->btsFlags And BTS_READ_ONLY) <> 0 Then
        sqlite3BtreeLeave(pBtree)
        Return SQLITE_READONLY
    End If

    Dim rc As SQLITE_C_INT = btreeClearTableLocked(pBtree, rootPage, pChangeCount)
    sqlite3BtreeLeave(pBtree)
    Return rc
End Function

Function sqlite3BtreeClearTableOfCursor CDecl Alias "sqlite3BtreeClearTableOfCursor" ( _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT Export

    If pCursor = 0 OrElse pCursor->pBtree = 0 OrElse pCursor->pgnoRoot = 0 Then _
        Return SQLITE_MISUSE
    Return sqlite3BtreeClearTable(pCursor->pBtree, CLng(pCursor->pgnoRoot), 0)
End Function

Function sqlite3BtreeDropTable CDecl Alias "sqlite3BtreeDropTable" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal rootPage As SQLITE_C_INT, _
    ByVal pMovedPage As SQLITE_C_INT Ptr _
) As SQLITE_C_INT Export

    If pMovedPage <> 0 Then pMovedPage[0] = 0
    If pBtree = 0 OrElse pBtree->pBt = 0 OrElse pMovedPage = 0 OrElse rootPage < 2 Then Return SQLITE_MISUSE
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    If pBtree->inTrans <> TRANS_WRITE OrElse pBt->inTransaction <> TRANS_WRITE OrElse pBt->pPage1 = 0 Then
        sqlite3BtreeLeave(pBtree)
        Return SQLITE_MISUSE
    End If
    If (pBt->btsFlags And BTS_READ_ONLY) <> 0 Then
        sqlite3BtreeLeave(pBtree)
        Return SQLITE_READONLY
    End If
    If CULng(rootPage) > pBt->nPage Then
        sqlite3BtreeLeave(pBtree)
        Return SQLITE_CORRUPT
    End If

    Dim rc As SQLITE_C_INT = btreeClearTableLocked(pBtree, rootPage, 0)
    If rc = SQLITE_OK Then
        Dim pRoot As MemPage Ptr = 0
        rc = btreeGetPage(pBt, CULng(rootPage), @pRoot, 0)
        If rc = SQLITE_OK Then
#ifndef SQLITE_OMIT_AUTOVACUUM
            If pBt->autoVacuum <> 0 Then
                Dim largestRoot As u32 = btreeReadU32(CPtr(MemPage Ptr, pBt->pPage1)->aData + 52)
                If largestRoot < CULng(rootPage) OrElse largestRoot > pBt->nPage Then
                    rc = SQLITE_CORRUPT
                ElseIf largestRoot = CULng(rootPage) Then
                    freePage(pRoot, rc)
                Else
                    sqlite3BtreeReleasePage(pRoot)
                    pRoot = 0

                    Dim pMove As MemPage Ptr = 0
                    rc = btreeGetPage(pBt, largestRoot, @pMove, 0)
                    If rc = SQLITE_OK Then
                        Dim moveType As u8 = 0
                        Dim moveParent As u32 = 0
                        rc = ptrmapGet(pBt, largestRoot, @moveType, @moveParent)
                        If rc = SQLITE_OK AndAlso (moveType <> PTRMAP_ROOTPAGE OrElse moveParent <> 0) Then
                            rc = SQLITE_CORRUPT
                        End If
                        If rc = SQLITE_OK Then
                            rc = relocatePage(pBt, pMove, PTRMAP_ROOTPAGE, 0, CULng(rootPage), 0)
                        End If
                        sqlite3BtreeReleasePage(pMove)
                        pMove = 0
                    End If

                    If rc = SQLITE_OK Then rc = btreeGetPage(pBt, largestRoot, @pRoot, 0)
                    If rc = SQLITE_OK Then rc = sqlite3PagerWrite(pRoot->pDbPage)
                    If rc = SQLITE_OK Then freePage(pRoot, rc)
                    If rc = SQLITE_OK Then pMovedPage[0] = CInt(largestRoot)
                End If

                If rc = SQLITE_OK Then
                    If largestRoot = 0 Then
                        rc = SQLITE_CORRUPT
                    Else
                        largestRoot -= 1
                        Dim pendingBytePage As u32 = (PENDING_BYTE \ pBt->pageSize) + 1
                        While largestRoot = pendingBytePage OrElse ptrmapIsPage(pBt, largestRoot) <> 0
                            If largestRoot = 0 Then
                                rc = SQLITE_CORRUPT
                                Exit While
                            End If
                            largestRoot -= 1
                        Wend
                        If rc = SQLITE_OK Then rc = sqlite3BtreeUpdateMeta(pBtree, 4, largestRoot)
                    End If
                End If
            Else
                freePage(pRoot, rc)
            End If
#else
            freePage(pRoot, rc)
#endif
            sqlite3BtreeReleasePage(pRoot)
        End If
    End If
    sqlite3BtreeLeave(pBtree)
    Return rc
End Function

Function sqlite3BtreeBeginTrans CDecl Alias "sqlite3BtreeBeginTrans" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal writeFlag As SQLITE_C_INT, _
    ByVal pSchemaVersion As SQLITE_C_INT Ptr _
) As SQLITE_C_INT Export

    If pBtree = 0 OrElse pBtree->pBt = 0 OrElse writeFlag < 0 OrElse writeFlag > 2 Then Return SQLITE_MISUSE
    Dim pBt As BtShared Ptr = pBtree->pBt
    If pBtree->sharable <> 0 OrElse pBtree->inTrans = TRANS_NONE OrElse _
       (pBtree->inTrans = TRANS_READ AndAlso writeFlag <> 0) Then
        Return btreeBeginTrans(pBtree, writeFlag, pSchemaVersion)
    End If

    If pSchemaVersion <> 0 Then
        If pBt->pPage1 = 0 Then Return SQLITE_CORRUPT
        Dim pPage1 As MemPage Ptr = CPtr(MemPage Ptr, pBt->pPage1)
        If pPage1->aData = 0 Then Return SQLITE_CORRUPT
        pSchemaVersion[0] = btreeReadU32(pPage1->aData + 40)
    End If
    If writeFlag <> 0 Then
        Return sqlite3PagerOpenSavepoint(pBt->pPager, pBt->db->nSavepoint)
    End If
    Return SQLITE_OK
End Function

Function sqlite3BtreeTxnState CDecl Alias "sqlite3BtreeTxnState" (ByVal pBtree As Btree Ptr) As SQLITE_C_INT Export
    If pBtree = 0 Then Return TRANS_NONE
    Return pBtree->inTrans
End Function

Function sqlite3BtreeIsInBackup CDecl Alias "sqlite3BtreeIsInBackup" (ByVal pBtree As Btree Ptr) As SQLITE_C_INT Export
    If pBtree = 0 Then Return 0
    Return IIf(pBtree->nBackup <> 0, 1, 0)
End Function

Function sqlite3BtreeSetVersion CDecl Alias "sqlite3BtreeSetVersion" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal version As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pBtree = 0 OrElse pBtree->pBt = 0 OrElse (version <> 1 AndAlso version <> 2) Then Return SQLITE_MISUSE
    Dim pBt As BtShared Ptr = pBtree->pBt
    pBt->btsFlags = pBt->btsFlags And Not BTS_NO_WAL
    If version = 1 Then pBt->btsFlags = pBt->btsFlags Or BTS_NO_WAL
    Dim rc As SQLITE_C_INT = sqlite3BtreeBeginTrans(pBtree, 0, 0)
    Dim needWrite As SQLITE_C_INT = 0
    If rc = SQLITE_OK Then
        If pBt->pPage1 = 0 Then
            rc = SQLITE_CORRUPT
        Else
            Dim pPage1 As MemPage Ptr = CPtr(MemPage Ptr, pBt->pPage1)
            needWrite = IIf(pPage1->aData[18] <> version OrElse pPage1->aData[19] <> version, 1, 0)
        End If
    End If
    If rc = SQLITE_OK AndAlso needWrite <> 0 Then rc = sqlite3BtreeBeginTrans(pBtree, 2, 0)
    If rc = SQLITE_OK AndAlso needWrite <> 0 Then
        If pBt->pPage1 = 0 Then
            rc = SQLITE_CORRUPT
        Else
            Dim pPage1 As MemPage Ptr = CPtr(MemPage Ptr, pBt->pPage1)
            rc = sqlite3PagerWrite(pPage1->pDbPage)
            If rc = SQLITE_OK Then
                pPage1->aData[18] = CByte(version)
                pPage1->aData[19] = CByte(version)
            End If
        End If
    End If
    pBt->btsFlags = pBt->btsFlags And Not BTS_NO_WAL
    Return rc
End Function

Function sqlite3BtreeCommitPhaseOne CDecl Alias "sqlite3BtreeCommitPhaseOne" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal zSuperJournal As Const ZString Ptr _
) As SQLITE_C_INT Export
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return SQLITE_MISUSE
    If pBtree->inTrans <> TRANS_WRITE Then Return SQLITE_OK
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
#ifndef SQLITE_OMIT_AUTOVACUUM
    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pBt->autoVacuum <> 0 Then rc = autoVacuumCommit(pBtree)
    If rc = SQLITE_OK AndAlso pBt->bDoTruncate <> 0 Then
        sqlite3PagerTruncateImage(pBt->pPager, pBt->nPage)
    End If
    If rc <> SQLITE_OK Then
        sqlite3BtreeLeave(pBtree)
        Return rc
    End If
#else
    Dim rc As SQLITE_C_INT = SQLITE_OK
#endif
    rc = sqlite3PagerCommitPhaseOne(pBt->pPager, zSuperJournal, 0)
    sqlite3BtreeLeave(pBtree)
    Return rc
End Function

Function sqlite3BtreeCommitPhaseTwo CDecl Alias "sqlite3BtreeCommitPhaseTwo" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal cleanupFlag As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return SQLITE_MISUSE
    If pBtree->inTrans = TRANS_NONE Then Return SQLITE_OK
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pBtree->inTrans = TRANS_WRITE Then rc = sqlite3PagerCommitPhaseTwo(pBt->pPager)
    If rc = SQLITE_OK OrElse cleanupFlag <> 0 Then
        If pBtree->inTrans = TRANS_WRITE Then
            pBtree->iBDataVersion -= 1
            pBt->inTransaction = TRANS_READ
            btreeClearHasContent(pBt)
        End If
        btreeFinishTransaction(pBtree)
        If cleanupFlag <> 0 Then rc = SQLITE_OK
    End If
    sqlite3BtreeLeave(pBtree)
    Return rc
End Function

Function sqlite3BtreeCommit CDecl Alias "sqlite3BtreeCommit" (ByVal pBtree As Btree Ptr) As SQLITE_C_INT Export
    Dim rc As SQLITE_C_INT = sqlite3BtreeCommitPhaseOne(pBtree, 0)
    If rc = SQLITE_OK Then rc = sqlite3BtreeCommitPhaseTwo(pBtree, 0)
    Return rc
End Function

Function sqlite3BtreeRollback CDecl Alias "sqlite3BtreeRollback" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal tripCode As SQLITE_C_INT, _
    ByVal writeOnly As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return SQLITE_MISUSE
    If (tripCode <> SQLITE_OK AndAlso tripCode <> SQLITE_ABORT_ROLLBACK) OrElse _
       writeOnly < 0 OrElse writeOnly > 1 Then Return SQLITE_MISUSE
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    Dim rc As SQLITE_C_INT = SQLITE_OK
    If tripCode = SQLITE_OK Then
        rc = btreeSaveAllCursors(pBt, 0, 0)
        tripCode = rc
        If rc <> SQLITE_OK Then writeOnly = 0
    End If
    If tripCode <> SQLITE_OK Then
        Dim tripCodeResult As SQLITE_C_INT = _
            sqlite3BtreeTripAllCursors(pBtree, tripCode, writeOnly)
        If tripCodeResult <> SQLITE_OK Then rc = tripCodeResult
    End If

    If pBtree->inTrans = TRANS_WRITE Then
        Dim rollbackCode As SQLITE_C_INT = sqlite3PagerRollback(pBt->pPager)
        If rollbackCode <> SQLITE_OK Then rc = rollbackCode
        ' Pager rollback may discard the old page-one cache entry. Reacquire it
        ' before reading the restored page count, as btree.c does.
        Dim pPage1 As MemPage Ptr = 0
        If btreeGetPage(pBt, 1, @pPage1, 0) = SQLITE_OK Then
            Dim pageCount As SQLITE_C_INT = CInt(btreeReadU32(pPage1->aData + 28))
            If pageCount = 0 Then sqlite3PagerPagecount(pBt->pPager, @pageCount)
            pBt->nPage = CUInt(pageCount)
            releasePageOne(pPage1)
        End If
        ' Other shared-cache handles may still hold read transactions after
        ' this writer rolls back.
        pBt->inTransaction = TRANS_READ
        btreeClearHasContent(pBt)
    End If
    btreeFinishTransaction(pBtree)
    sqlite3BtreeLeave(pBtree)
    Return rc
End Function

Function sqlite3BtreeBeginStmt CDecl Alias "sqlite3BtreeBeginStmt" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal statementIndex As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pBtree = 0 OrElse pBtree->pBt = 0 OrElse statementIndex < 0 Then Return SQLITE_MISUSE
    If pBtree->inTrans <> TRANS_WRITE Then Return SQLITE_MISUSE
    Return sqlite3PagerOpenSavepoint(pBtree->pBt->pPager, statementIndex)
End Function

Function sqlite3BtreeSavepoint CDecl Alias "sqlite3BtreeSavepoint" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal savepointIndex As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return SQLITE_MISUSE
    If pBtree->inTrans <> TRANS_WRITE Then Return SQLITE_OK
    If (operation <> SAVEPOINT_RELEASE AndAlso operation <> SAVEPOINT_ROLLBACK) OrElse _
       savepointIndex < -1 Then Return SQLITE_MISUSE
    If savepointIndex = -1 AndAlso operation <> SAVEPOINT_ROLLBACK Then Return SQLITE_MISUSE
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    Dim rc As SQLITE_C_INT = SQLITE_OK
    If operation = SAVEPOINT_ROLLBACK Then _
        rc = btreeSaveAllCursors(pBt, 0, 0)
    If rc = SQLITE_OK Then _
        rc = sqlite3PagerSavepoint(pBt->pPager, operation, savepointIndex)
    If rc = SQLITE_OK AndAlso pBt->pPage1 <> 0 Then
        Dim pPage1 As MemPage Ptr = CPtr(MemPage Ptr, pBt->pPage1)
        pBt->nPage = btreeReadU32(pPage1->aData + 28)
        If pBt->nPage = 0 AndAlso (pBt->btsFlags And BTS_INITIALLY_EMPTY) <> 0 Then
            rc = btreeCreateNewDatabase(pBt)
        End If
    End If
    sqlite3BtreeLeave(pBtree)
    Return rc
End Function

Sub sqlite3BtreeGetMeta CDecl Alias "sqlite3BtreeGetMeta" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal index As SQLITE_C_INT, _
    ByVal pMeta As u32 Ptr _
) Export
    If pMeta = 0 Then Return
    pMeta[0] = 0
    If pBtree = 0 OrElse pBtree->pBt = 0 OrElse index < 0 OrElse index > 15 Then Return
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    If pBt->pPage1 <> 0 Then
        If index = BTREE_DATA_VERSION Then
            pMeta[0] = sqlite3PagerDataVersion(pBt->pPager) + pBtree->iBDataVersion
        Else
            pMeta[0] = btreeReadU32(CPtr(MemPage Ptr, pBt->pPage1)->aData + 36 + index * 4)
        End If
    End If
    sqlite3BtreeLeave(pBtree)
End Sub

Function sqlite3BtreeUpdateMeta CDecl Alias "sqlite3BtreeUpdateMeta" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal index As SQLITE_C_INT, _
    ByVal value As u32 _
) As SQLITE_C_INT Export
    If pBtree = 0 OrElse pBtree->pBt = 0 OrElse index < 1 OrElse index > 15 Then Return SQLITE_MISUSE
    If pBtree->inTrans <> TRANS_WRITE OrElse pBtree->pBt->pPage1 = 0 Then Return SQLITE_READONLY
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    Dim pPage1 As MemPage Ptr = CPtr(MemPage Ptr, pBt->pPage1)
    Dim rc As SQLITE_C_INT = sqlite3PagerWrite(pPage1->pDbPage)
    If rc = SQLITE_OK Then btreeWriteU32(pPage1->aData + 36 + index * 4, value)
    sqlite3BtreeLeave(pBtree)
    Return rc
End Function

/' ------------------------------------------------------------------------- '/
/' Cursor storage and lifecycle '/
/' ------------------------------------------------------------------------- '/

Private Sub btreeCursorClearCellInfo(ByVal pCursor As BtCursor Ptr)
    If pCursor = 0 Then Exit Sub
    pCursor->info.nSize = 0
    pCursor->curFlags = pCursor->curFlags And Not (BTCF_VALID_NKEY Or BTCF_VALID_OVFL Or BTCF_AT_LAST)
End Sub

Private Sub btreeReleaseAllCursorPages CDecl Alias "btreeReleaseAllCursorPages" ( _
    ByVal pCursor As BtCursor Ptr _
)
    If pCursor = 0 OrElse pCursor->iPage < 0 Then Exit Sub
    If pCursor->pPage <> 0 Then sqlite3BtreeReleasePage(pCursor->pPage)
    Dim stackIndex As Long = CLng(pCursor->iPage) - 1
    While stackIndex >= 0
        If pCursor->apPage(stackIndex) <> 0 Then sqlite3BtreeReleasePage(pCursor->apPage(stackIndex))
        stackIndex -= 1
    Wend
    pCursor->pPage = 0
    pCursor->iPage = -1
    pCursor->eState = CURSOR_INVALID
    btreeCursorClearCellInfo(pCursor)
End Sub

Private Function btreeCursorCell(ByVal pPage As MemPage Ptr, ByVal cellIndex As SQLITE_C_INT) As UByte Ptr
    If pPage = 0 OrElse pPage->isInit = 0 OrElse pPage->aCellIdx = 0 OrElse _
       cellIndex < 0 OrElse cellIndex >= pPage->nCell Then Return 0
    Dim pCellIndex As Const UByte Ptr = CPtr(Const UByte Ptr, pPage->aCellIdx) + (cellIndex * 2)
    Dim cellOffset As u32 = btreeGetU16(pCellIndex) And pPage->maskPage
    If cellOffset >= pPage->pBt->usableSize Then Return 0
    Return pPage->aData + cellOffset
End Function

#ifdef SQLITE_DEBUG
Private Function btreeCellInfoEqual( _
    ByVal pLeft As Const CellInfo Ptr, _
    ByVal pRight As Const CellInfo Ptr _
) As SQLITE_C_INT
    If pLeft->nKey <> pRight->nKey Then Return 0
    If pLeft->pPayload <> pRight->pPayload Then Return 0
    If pLeft->nPayload <> pRight->nPayload Then Return 0
    If pLeft->nLocal <> pRight->nLocal Then Return 0
    If pLeft->nSize <> pRight->nSize Then Return 0
    Return 1
End Function

Private Sub assertCellInfo CDecl Alias "assertCellInfo" ( _
    ByVal pCursor As BtCursor Ptr _
)
    If pCursor = 0 OrElse pCursor->pPage = 0 Then
        sqlite3DebugAssert(StrPtr("pCur and pCur->pPage are valid"))
        Exit Sub
    End If

    Dim parsedInfo As CellInfo = Type<CellInfo>(0)
    Dim rc As SQLITE_C_INT = btreeParseCell(pCursor->pPage, pCursor->ix, @parsedInfo)
    If rc <> SQLITE_OK Then
        sqlite3DebugAssert(StrPtr("btreeParseCell succeeds for cached cursor info"))
        Exit Sub
    End If

    ' CORRUPT_DB permits cell bytes to be malformed during normal operation.
    If sqlite3ConfigTestNeverCorrupt() <> 0 Then
        If btreeCellInfoEqual(@parsedInfo, @pCursor->info) = 0 Then _
            sqlite3DebugAssert(StrPtr("cached cell information matches a fresh parse"))
    End If
End Sub
#endif

Private Function getCellInfo CDecl Alias "getCellInfo" (ByVal pCursor As BtCursor Ptr) As SQLITE_C_INT
    If pCursor = 0 OrElse pCursor->pPage = 0 OrElse pCursor->eState <> CURSOR_VALID Then Return SQLITE_MISUSE
    If pCursor->info.nSize <> 0 Then
#ifdef SQLITE_DEBUG
        assertCellInfo(pCursor)
#endif
        Return SQLITE_OK
    End If
    Dim rc As SQLITE_C_INT = sqlite3BtreeGetCellInfo(pCursor->pPage, pCursor->ix, @pCursor->info)
    If rc = SQLITE_OK Then pCursor->curFlags = pCursor->curFlags Or BTCF_VALID_NKEY
    Return rc
End Function

Private Function btreeMoveToChild(ByVal pCursor As BtCursor Ptr, ByVal childPage As u32) As SQLITE_C_INT
    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pCursor->pPage = 0 OrElse _
       pCursor->iPage < 0 Then Return SQLITE_MISUSE
    If pCursor->iPage >= BTCURSOR_MAX_DEPTH - 1 Then Return SQLITE_CORRUPT
    If childPage = 0 OrElse childPage > pCursor->pBt->nPage Then Return SQLITE_CORRUPT

    btreeCursorClearCellInfo(pCursor)
    pCursor->aiIdx(pCursor->iPage) = pCursor->ix
    pCursor->apPage(pCursor->iPage) = pCursor->pPage
    pCursor->ix = 0
    pCursor->iPage += 1
    Dim rc As SQLITE_C_INT = sqlite3BtreeGetAndInitPage(pCursor->pBt, childPage, @pCursor->pPage, pCursor->curPagerFlags)
    If rc = SQLITE_OK AndAlso (pCursor->pPage->nCell = 0 OrElse pCursor->pPage->intKey <> pCursor->curIntKey) Then
        sqlite3BtreeReleasePage(pCursor->pPage)
        pCursor->pPage = 0
        rc = SQLITE_CORRUPT
    End If
    If rc <> SQLITE_OK Then
        pCursor->iPage -= 1
        pCursor->pPage = pCursor->apPage(pCursor->iPage)
    End If
    Return rc
End Function

#ifdef SQLITE_DEBUG
Private Sub assertParentIndex CDecl Alias "assertParentIndex" ( _
    ByVal pParent As MemPage Ptr, _
    ByVal cellIndex As SQLITE_C_INT, _
    ByVal childPage As u32 _
)
    If sqlite3ConfigTestNeverCorrupt() = 0 Then Exit Sub
    If pParent = 0 OrElse pParent->aData = 0 Then
        sqlite3DebugAssert(StrPtr("parent page and data are valid"))
        Exit Sub
    End If
    If cellIndex < 0 OrElse cellIndex > pParent->nCell Then
        sqlite3DebugAssert(StrPtr("child index is within the parent cell range"))
        Exit Sub
    End If

    Dim storedChild As u32
    If cellIndex = pParent->nCell Then
        storedChild = btreeReadU32(pParent->aData + pParent->hdrOffset + 8)
    Else
        Dim pCell As UByte Ptr = btreeCursorCell(pParent, cellIndex)
        If pCell = 0 Then
            sqlite3DebugAssert(StrPtr("parent cell pointer is valid"))
            Exit Sub
        End If
        storedChild = btreeReadU32(pCell)
    End If
    If storedChild <> childPage Then _
        sqlite3DebugAssert(StrPtr("parent cell points to the current child page"))
End Sub
#endif

Private Sub btreeMoveToParent(ByVal pCursor As BtCursor Ptr)
    If pCursor = 0 OrElse pCursor->iPage <= 0 OrElse pCursor->pPage = 0 Then Exit Sub
    Dim pChild As MemPage Ptr = pCursor->pPage
    Dim parentIndex As Long = CLng(pCursor->iPage) - 1
#ifdef SQLITE_DEBUG
    assertParentIndex( _
        pCursor->apPage(parentIndex), pCursor->aiIdx(parentIndex), pChild->pgno)
#endif
    pCursor->pPage = pCursor->apPage(parentIndex)
    pCursor->ix = pCursor->aiIdx(parentIndex)
    pCursor->iPage = CByte(parentIndex)
    btreeCursorClearCellInfo(pCursor)
    sqlite3BtreeReleasePage(pChild)
End Sub

Private Function btreeMoveToRoot(ByVal pCursor As BtCursor Ptr) As SQLITE_C_INT
    If pCursor = 0 OrElse pCursor->pBt = 0 Then Return SQLITE_MISUSE
    If pCursor->eState = CURSOR_FAULT Then Return pCursor->skipNext
    If pCursor->iPage >= 0 Then
        If pCursor->iPage > 0 Then
            If pCursor->pPage <> 0 Then sqlite3BtreeReleasePage(pCursor->pPage)
            Dim stackIndex As Long = CLng(pCursor->iPage) - 1
            While stackIndex > 0
                If pCursor->apPage(stackIndex) <> 0 Then sqlite3BtreeReleasePage(pCursor->apPage(stackIndex))
                stackIndex -= 1
            Wend
            pCursor->pPage = pCursor->apPage(0)
            pCursor->iPage = 0
        End If
    Else
        If pCursor->pgnoRoot = 0 Then
            pCursor->eState = CURSOR_INVALID
            Return SQLITE_EMPTY
        End If
        If pCursor->eState >= CURSOR_REQUIRESEEK Then _
            sqlite3BtreeClearCursor(pCursor)
        Dim rc As SQLITE_C_INT = sqlite3BtreeGetAndInitPage(pCursor->pBt, pCursor->pgnoRoot, _
            @pCursor->pPage, pCursor->curPagerFlags)
        If rc <> SQLITE_OK Then
            pCursor->eState = CURSOR_INVALID
            Return rc
        End If
        pCursor->iPage = 0
        pCursor->curIntKey = pCursor->pPage->intKey
    End If

    If pCursor->pPage = 0 Then Return SQLITE_CORRUPT
    ' A cached root may have been invalidated after raw-page writes or
    ' corruption. Do not trust its prior page metadata in that state.
    If pCursor->pPage->isInit = 0 OrElse _
       (pCursor->pKeyInfo = 0) <> (pCursor->pPage->intKey <> 0) Then _
        Return SQLITE_CORRUPT
    pCursor->ix = 0
    btreeCursorClearCellInfo(pCursor)
    If pCursor->pPage->nCell > 0 Then
        pCursor->eState = CURSOR_VALID
        Return SQLITE_OK
    End If
    If pCursor->pPage->leaf <> 0 Then
        pCursor->eState = CURSOR_INVALID
        Return SQLITE_EMPTY
    End If
    If pCursor->pPage->pgno <> pCursor->pgnoRoot Then Return SQLITE_CORRUPT
    Dim childPage As u32 = btreeReadU32(pCursor->pPage->aData + pCursor->pPage->hdrOffset + 8)
    pCursor->eState = CURSOR_VALID
    Return btreeMoveToChild(pCursor, childPage)
End Function

Private Function btreeMoveToLeftmost CDecl Alias "moveToLeftmost" ( _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT
    If pCursor = 0 OrElse pCursor->eState <> CURSOR_VALID Then Return SQLITE_MISUSE
    While pCursor->pPage <> 0 AndAlso pCursor->pPage->leaf = 0
        If pCursor->pPage->nCell = 0 Then Return SQLITE_CORRUPT
        If pCursor->ix >= pCursor->pPage->nCell Then Return SQLITE_CORRUPT
        Dim pCell As UByte Ptr = btreeCursorCell(pCursor->pPage, pCursor->ix)
        If pCell = 0 Then Return SQLITE_CORRUPT
        Dim childPage As u32 = btreeReadU32(pCell)
        Dim rc As SQLITE_C_INT = btreeMoveToChild(pCursor, childPage)
        If rc <> SQLITE_OK Then Return rc
    Wend
    Return IIf(pCursor->pPage = 0 OrElse pCursor->pPage->nCell = 0, SQLITE_CORRUPT, SQLITE_OK)
End Function

Private Function btreeMoveToRightmost(ByVal pCursor As BtCursor Ptr) As SQLITE_C_INT
    If pCursor = 0 OrElse pCursor->eState <> CURSOR_VALID Then Return SQLITE_MISUSE
    While pCursor->pPage <> 0 AndAlso pCursor->pPage->leaf = 0
        Dim parentPage As MemPage Ptr = pCursor->pPage
        Dim childPage As u32 = btreeReadU32(parentPage->aData + parentPage->hdrOffset + 8)
        pCursor->ix = parentPage->nCell
        Dim rc As SQLITE_C_INT = btreeMoveToChild(pCursor, childPage)
        If rc <> SQLITE_OK Then Return rc
    Wend
    If pCursor->pPage = 0 OrElse pCursor->pPage->nCell = 0 Then Return SQLITE_CORRUPT
    pCursor->ix = pCursor->pPage->nCell - 1
    btreeCursorClearCellInfo(pCursor)
    Return SQLITE_OK
End Function

Private Sub btreeMoveToOverflowStart(ByVal pCursor As BtCursor Ptr)
    pCursor->info.nSize = 0
    pCursor->curFlags = pCursor->curFlags And Not (BTCF_VALID_NKEY Or BTCF_VALID_OVFL)
End Sub

/' ------------------------------------------------------------------------- '/
/' Cursor API '/
/' ------------------------------------------------------------------------- '/

Function sqlite3BtreeCursorSize CDecl Alias "sqlite3BtreeCursorSize" () As SQLITE_C_INT Export
    Return (SizeOf(BtCursor) + 7) And Not 7
End Function

Sub sqlite3BtreeCursorZero CDecl Alias "sqlite3BtreeCursorZero" (ByVal pCursor As BtCursor Ptr) Export
    If pCursor = 0 Then Exit Sub
    Dim pBytes As UByte Ptr = CPtr(UByte Ptr, pCursor)
    For i As Long = 0 To SizeOf(BtCursor) - 1
        pBytes[i] = 0
    Next
    pCursor->iPage = -1
    pCursor->eState = CURSOR_INVALID
End Sub

Sub sqlite3BtreeClearCursor CDecl Alias "sqlite3BtreeClearCursor" (ByVal pCursor As BtCursor Ptr) Export
    If pCursor = 0 Then Exit Sub
    If pCursor->pKey <> 0 Then sqlite3_free(pCursor->pKey)
    pCursor->pKey = 0
    pCursor->eState = CURSOR_INVALID
    btreeCursorClearCellInfo(pCursor)
End Sub

Sub sqlite3BtreeCursorHintFlags CDecl Alias "sqlite3BtreeCursorHintFlags" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal hints As SQLITE_C_UINT _
) Export
    If pCursor = 0 OrElse _
       (hints And Not (BTREE_SEEK_EQ Or BTREE_BULKLOAD)) <> 0 Then Exit Sub
    pCursor->hints = CByte(hints)
End Sub

#if defined(SQLITE_ENABLE_CURSOR_HINTS) AndAlso defined(SQLITE_DEBUG)
Function sqlite3BtreeCursorHintTblCsr CDecl Alias "sqlite3BtreeCursorHintTblCsr" ( _
    ByVal pCursor As BtCursor Ptr _
) As BtCursor Ptr Export
    Return pCursor->pCursorHintTableCursor
End Function
#endif

Function sqlite3BtreeCursorHasHint CDecl Alias "sqlite3BtreeCursorHasHint" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal mask As SQLITE_C_UINT _
) As SQLITE_C_INT Export
    If pCursor = 0 Then Return 0
    Return IIf((CULng(pCursor->hints) And mask) <> 0, 1, 0)
End Function

Sub sqlite3BtreeCursorPin CDecl Alias "sqlite3BtreeCursorPin" (ByVal pCursor As BtCursor Ptr) Export
    If pCursor = 0 Then Exit Sub
    pCursor->curFlags = pCursor->curFlags Or BTCF_PINNED
End Sub

Sub sqlite3BtreeCursorUnpin CDecl Alias "sqlite3BtreeCursorUnpin" (ByVal pCursor As BtCursor Ptr) Export
    If pCursor = 0 Then Exit Sub
    pCursor->curFlags = pCursor->curFlags And Not BTCF_PINNED
End Sub

#ifdef SQLITE_ENABLE_CURSOR_HINTS
Sub sqlite3BtreeCursorHint CDecl Alias "sqlite3BtreeCursorHint" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal hintType As SQLITE_C_INT, _
    ... _
) Export
#ifdef SQLITE_DEBUG
    Dim arguments As Cva_List
    Cva_Start(arguments, hintType)
    If pCursor = 0 Then
        sqlite3DebugAssert(StrPtr("cursor-hint target is valid"))
        Cva_End(arguments)
        Exit Sub
    End If

    Select Case hintType
    Case BTREE_HINT_RANGE
        Dim pExpression As SqliteExpr Ptr = Cva_Arg(arguments, SqliteExpr Ptr)
        Dim pMemory As SqliteVdbeMem Ptr = Cva_Arg(arguments, SqliteVdbeMem Ptr)
        If pExpression = 0 OrElse pMemory = 0 Then
            sqlite3DebugAssert(StrPtr("range hint expression and registers are valid"))
        Else
            Dim walker As SqliteWalker
            walker.pParse = 0
            walker.xExprCallback = @sqlite3CursorRangeHintExprCheck
            walker.xSelectCallback = 0
            walker.xSelectCallback2 = 0
            walker.walkerDepth = 0
            walker.eCode = 0
            walker.mWFlags = 0
            walker.u.aMem = pMemory
            sqlite3WalkExpr(@walker, pExpression)
        End If
    Case BTREE_HINT_TABLECURSOR
        Dim pTableCursor As BtCursor Ptr = Cva_Arg(arguments, BtCursor Ptr)
        If pTableCursor = 0 Then
            sqlite3DebugAssert(StrPtr("table-cursor hint is valid"))
        Else
            If pCursor->pCursorHintTableCursor <> 0 AndAlso _
               pCursor->pCursorHintTableCursor <> pTableCursor Then _
                sqlite3DebugAssert(StrPtr("table-cursor hint is stable"))
            If sqlite3ConfigTestNeverCorrupt() <> 0 AndAlso _
               pTableCursor->pKeyInfo <> 0 Then _
                sqlite3DebugAssert(StrPtr("table cursor has no index KeyInfo"))
            pCursor->pCursorHintTableCursor = pTableCursor
        End If
    Case Else
        sqlite3DebugAssert(StrPtr("cursor hint type is known"))
    End Select
    Cva_End(arguments)
#endif
End Sub
#endif

' A writable cursor needs a shared buffer with a four-byte child-pointer prefix.
Private Function allocateTempSpace CDecl Alias "allocateTempSpace" ( _
    ByVal pBt As BtShared Ptr _
) As SQLITE_C_INT
    If pBt = 0 OrElse pBt->pTmpSpace <> 0 Then Return SQLITE_MISUSE
    If pBt->pCursor = 0 Then Return SQLITE_CORRUPT

    Dim pCursor As BtCursor Ptr = CPtr(BtCursor Ptr, pBt->pCursor)
    If (pCursor->curFlags And BTCF_WRITE_FLAG) = 0 Then Return SQLITE_CORRUPT
    Dim pTemporary As UByte Ptr = _
        CPtr(UByte Ptr, sqlite3PageMalloc(CLng(pBt->pageSize)))
    If pTemporary = 0 Then
        pBt->pCursor = pCursor->pNext
        Dim pCursorBytes As UByte Ptr = CPtr(UByte Ptr, pCursor)
        For byteIndex As Long = 0 To SizeOf(BtCursor) - 1
            pCursorBytes[byteIndex] = 0
        Next
        Return SQLITE_NOMEM
    End If

    ' Cell insertions may write four bytes before the cell and copy eight bytes.
    For iByte As SQLITE_C_INT = 0 To 7
        pTemporary[iByte] = 0
    Next
    pBt->pTmpSpace = pTemporary + 4
    Return SQLITE_OK
End Function

' When the B-tree is shared, the caller must hold pBt->mutex while this
' routine updates the cursor list and allocates shared temporary space.
Private Function btreeCursor CDecl Alias "btreeCursor" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal rootPage As u32, _
    ByVal writeFlags As SQLITE_C_INT, _
    ByVal pKeyInfo As Any Ptr, _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT

    If pBtree = 0 OrElse pBtree->pBt = 0 OrElse pCursor = 0 Then Return SQLITE_MISUSE
    If writeFlags <> 0 AndAlso writeFlags <> BTREE_WRCSR AndAlso _
       writeFlags <> (BTREE_WRCSR Or BTREE_FORDELETE) Then Return SQLITE_MISUSE
    If pBtree->inTrans = TRANS_NONE Then Return SQLITE_MISUSE
    Dim pBt As BtShared Ptr = pBtree->pBt
    If writeFlags <> 0 AndAlso (pBtree->inTrans <> TRANS_WRITE OrElse (pBt->btsFlags And BTS_READ_ONLY) <> 0) Then
        Return SQLITE_READONLY
    End If

    sqlite3BtreeCursorZero(pCursor)
    If rootPage > pBt->nPage AndAlso pBt->nPage <> 0 Then Return SQLITE_CORRUPT
    If rootPage = 0 Then Return SQLITE_CORRUPT
    If rootPage = 1 AndAlso pBt->nPage = 0 Then rootPage = 0

    pCursor->pgnoRoot = rootPage
    pCursor->pBtree = pBtree
    pCursor->pBt = pBt
    pCursor->pKeyInfo = pKeyInfo
    pCursor->curPagerFlags = IIf(writeFlags = 0, PAGER_GET_READONLY, 0)
    If writeFlags <> 0 Then pCursor->curFlags = pCursor->curFlags Or BTCF_WRITE_FLAG
    Dim pExisting As BtCursor Ptr = CPtr(BtCursor Ptr, pBt->pCursor)
    While pExisting <> 0
        If pExisting->pgnoRoot = rootPage Then
            pExisting->curFlags = pExisting->curFlags Or BTCF_MULTIPLE
            pCursor->curFlags = pCursor->curFlags Or BTCF_MULTIPLE
        End If
        pExisting = pExisting->pNext
    Wend
    pCursor->pNext = CPtr(BtCursor Ptr, pBt->pCursor)
    pBt->pCursor = pCursor
    If writeFlags <> 0 AndAlso pBt->pTmpSpace = 0 Then _
        Return allocateTempSpace(pBt)
    Return SQLITE_OK
End Function

' Shared-cache cursor creation enters the shared B-tree mutex for the whole
' initialization path, matching sqlite3BtreeEnter/sqlite3BtreeLeave.
Private Function btreeCursorWithLock CDecl Alias "btreeCursorWithLock" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal rootPage As u32, _
    ByVal writeFlags As SQLITE_C_INT, _
    ByVal pKeyInfo As Any Ptr, _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT

    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return SQLITE_MISUSE
    sqlite3BtreeEnter(pBtree)
    Dim rc As SQLITE_C_INT = btreeCursor(pBtree, rootPage, writeFlags, pKeyInfo, pCursor)
    sqlite3BtreeLeave(pBtree)
    Return rc
End Function

Function sqlite3BtreeCursor CDecl Alias "sqlite3BtreeCursor" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal rootPage As u32, _
    ByVal writeFlags As SQLITE_C_INT, _
    ByVal pKeyInfo As Any Ptr, _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT Export

    If pBtree = 0 OrElse pBtree->pBt = 0 OrElse pCursor = 0 Then Return SQLITE_MISUSE
    If pBtree->sharable <> 0 Then
        Return btreeCursorWithLock(pBtree, rootPage, writeFlags, pKeyInfo, pCursor)
    End If
    Return btreeCursor(pBtree, rootPage, writeFlags, pKeyInfo, pCursor)
End Function

Function sqlite3BtreeCloseCursor CDecl Alias "sqlite3BtreeCloseCursor" (ByVal pCursor As BtCursor Ptr) As SQLITE_C_INT Export
    If pCursor = 0 Then Return SQLITE_MISUSE
    Dim pBtree As Btree Ptr = pCursor->pBtree
    If pBtree = 0 OrElse pBtree->pBt = 0 Then
        sqlite3BtreeCursorZero(pCursor)
        Return SQLITE_OK
    End If
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    Dim ppCursor As BtCursor Ptr Ptr = CPtr(BtCursor Ptr Ptr, @pBt->pCursor)
    While ppCursor[0] <> 0 AndAlso ppCursor[0] <> pCursor
        ppCursor = @ppCursor[0]->pNext
    Wend
    If ppCursor[0] <> pCursor Then
        sqlite3BtreeLeave(pBtree)
        Return SQLITE_CORRUPT
    End If
    ppCursor[0] = pCursor->pNext
    If (pCursor->curFlags And BTCF_INCRBLOB) <> 0 Then
        pBtree->hasIncrblobCur = 0
        Dim pOther As BtCursor Ptr = CPtr(BtCursor Ptr, pBt->pCursor)
        While pOther <> 0
            If (pOther->curFlags And BTCF_INCRBLOB) <> 0 Then pBtree->hasIncrblobCur = 1
            pOther = pOther->pNext
        Wend
    End If
    btreeReleaseAllCursorPages(pCursor)
    If pCursor->aOverflow <> 0 Then sqlite3_free(pCursor->aOverflow)
    If pCursor->pKey <> 0 Then sqlite3_free(pCursor->pKey)
    sqlite3BtreeCursorZero(pCursor)
    ' BTREE_SINGLE gives its sole cursor ownership of the transient B-tree.
    If (pBt->openFlags And BTREE_SINGLE) <> 0 AndAlso pBt->pCursor = 0 Then _
        Return sqlite3BtreeClose(pBtree)
    If pBt->pCursor = 0 AndAlso pBtree->inTrans = TRANS_NONE Then btreeUnlockPageOne(pBt)
    Dim pDb As sqlite3 Ptr = pBtree->db
    Dim finalizeZombie As SQLITE_C_INT = IIf(pDb <> 0 AndAlso pDb->isZombie <> 0 AndAlso pBt->pCursor = 0, 1, 0)
    sqlite3BtreeLeave(pBtree)
    If finalizeZombie <> 0 Then Return sqlite3_close_v2(pDb)
    Return SQLITE_OK
End Function

/' ------------------------------------------------------------------------- '/
/' Cursor positioning '/
/' ------------------------------------------------------------------------- '/

Function sqlite3BtreeFirst CDecl Alias "sqlite3BtreeFirst" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT Export
    If pCursor = 0 OrElse pResult = 0 OrElse pCursor->pBt = 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = btreeMoveToRoot(pCursor)
    If rc = SQLITE_EMPTY Then
        pResult[0] = 1
        rc = SQLITE_OK
    ElseIf rc = SQLITE_OK Then
        pResult[0] = 0
        rc = btreeMoveToLeftmost(pCursor)
    End If
    Return rc
End Function

Function sqlite3BtreeIsEmpty CDecl Alias "sqlite3BtreeIsEmpty" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT Export
    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pResult = 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pCursor->eState = CURSOR_VALID Then
        pResult[0] = 0
    Else
        rc = btreeMoveToRoot(pCursor)
        If rc = SQLITE_EMPTY Then
            pResult[0] = 1
            rc = SQLITE_OK
        Else
            pResult[0] = 0
        End If
    End If
    Return rc
End Function

Function sqlite3BtreeLast CDecl Alias "sqlite3BtreeLast" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT Export
    If pCursor = 0 OrElse pResult = 0 OrElse pCursor->pBt = 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = btreeMoveToRoot(pCursor)
    If rc = SQLITE_EMPTY Then
        pResult[0] = 1
        rc = SQLITE_OK
    ElseIf rc = SQLITE_OK Then
        pResult[0] = 0
        rc = btreeMoveToRightmost(pCursor)
        If rc = SQLITE_OK Then pCursor->curFlags = pCursor->curFlags Or BTCF_AT_LAST
    End If
    Return rc
End Function

Function sqlite3BtreeEof CDecl Alias "sqlite3BtreeEof" (ByVal pCursor As BtCursor Ptr) As SQLITE_C_INT Export
    If pCursor = 0 Then Return 1
    Return IIf(pCursor->eState = CURSOR_VALID, 0, 1)
End Function

Function sqlite3BtreeFakeValidCursor CDecl Alias "sqlite3BtreeFakeValidCursor" () As BtCursor Ptr
    ' C returns a persistent one-byte cursor whose first field is CURSOR_VALID.
    Static fakeCursor As UByte = CURSOR_VALID
    Return CPtr(BtCursor Ptr, @fakeCursor)
End Function

Function sqlite3BtreeCursorHasMoved CDecl Alias "sqlite3BtreeCursorHasMoved" ( _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT Export
    If pCursor = 0 Then Return 1
    Return IIf(pCursor->eState = CURSOR_VALID, 0, 1)
End Function

Function sqlite3BtreeCursorIsValidNN CDecl Alias "sqlite3BtreeCursorIsValidNN" ( _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT Export
    If pCursor = 0 Then Return 0
    Return IIf(pCursor->eState = CURSOR_VALID, 1, 0)
End Function

Function sqlite3BtreeCursorIsValid CDecl Alias "sqlite3BtreeCursorIsValid" ( _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT
    If pCursor = 0 Then Return 0
    Return sqlite3BtreeCursorIsValidNN(pCursor)
End Function

Private Function btreeCursorNextInternal CDecl Alias "btreeNext" ( _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT
    If pCursor->eState <> CURSOR_VALID OrElse pCursor->pPage = 0 Then Return SQLITE_DONE
    Dim pPage As MemPage Ptr = pCursor->pPage
    If sqlite3FaultSim(412) <> 0 Then pPage->isInit = 0
    If pPage->isInit = 0 Then Return SQLITE_CORRUPT
    If pPage->leaf = 0 Then
        Dim childIndex As Long = CLng(pCursor->ix) + 1
        Dim childPage As u32
        If childIndex < pPage->nCell Then
            Dim pCell As UByte Ptr = btreeCursorCell(pPage, childIndex)
            If pCell = 0 Then Return SQLITE_CORRUPT
            childPage = btreeReadU32(pCell)
        Else
            childPage = btreeReadU32(pPage->aData + pPage->hdrOffset + 8)
        End If
        pCursor->ix = CUShort(childIndex)
        Dim rc As SQLITE_C_INT = btreeMoveToChild(pCursor, childPage)
        If rc <> SQLITE_OK Then Return rc
        Return btreeMoveToLeftmost(pCursor)
    End If

    If pCursor->ix + 1 < pPage->nCell Then
        pCursor->ix += 1
        btreeCursorClearCellInfo(pCursor)
        Return SQLITE_OK
    End If

    While pCursor->iPage > 0
        btreeMoveToParent(pCursor)
        pPage = pCursor->pPage
        If pCursor->ix < pPage->nCell Then
            If pPage->intKey <> 0 Then
                Dim childIndex As Long = CLng(pCursor->ix) + 1
                Dim childPage As u32
                If childIndex < pPage->nCell Then
                    Dim pCell As UByte Ptr = btreeCursorCell(pPage, childIndex)
                    If pCell = 0 Then Return SQLITE_CORRUPT
                    childPage = btreeReadU32(pCell)
                Else
                    childPage = btreeReadU32(pPage->aData + pPage->hdrOffset + 8)
                End If
                pCursor->ix = CUShort(childIndex)
                Dim rc As SQLITE_C_INT = btreeMoveToChild(pCursor, childPage)
                If rc <> SQLITE_OK Then Return rc
                Return btreeMoveToLeftmost(pCursor)
            End If
            btreeCursorClearCellInfo(pCursor)
            Return SQLITE_OK
        End If
    Wend
    pCursor->eState = CURSOR_INVALID
    Return SQLITE_DONE
End Function

Function sqlite3BtreeNext CDecl Alias "sqlite3BtreeNext" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pCursor = 0 OrElse pCursor->pBt = 0 Then Return SQLITE_MISUSE
    If flags < 0 OrElse flags > 1 Then Return SQLITE_MISUSE
    pCursor->curFlags = pCursor->curFlags And Not BTCF_AT_LAST
    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim restoreResult As SQLITE_C_INT = 0
    Dim didRestore As SQLITE_C_INT = 0
    Dim alreadyAtNext As SQLITE_C_INT = 0
    ' A rollback can trip a cursor with an error code. Restore every
    ' non-valid state so the error is returned instead of looking like EOF.
    If pCursor->eState <> CURSOR_VALID Then
        rc = btreeCursorRestoreInternal(pCursor, @restoreResult)
        didRestore = 1
    End If
    If rc = SQLITE_OK Then
        If pCursor->eState = CURSOR_SKIPNEXT Then
            pCursor->eState = CURSOR_VALID
            alreadyAtNext = IIf(pCursor->skipNext > 0, 1, 0)
            pCursor->skipNext = 0
        ElseIf didRestore <> 0 AndAlso pCursor->eState = CURSOR_VALID AndAlso restoreResult > 0 Then
            alreadyAtNext = 1
        End If
        If alreadyAtNext = 0 Then rc = btreeCursorNextInternal(pCursor)
    End If
    Return rc
End Function

Private Function btreeCursorPreviousInternal(ByVal pCursor As BtCursor Ptr) As SQLITE_C_INT
    If pCursor->eState <> CURSOR_VALID OrElse pCursor->pPage = 0 Then Return SQLITE_DONE
    Dim pPage As MemPage Ptr = pCursor->pPage
    If pPage->leaf = 0 Then
        Dim pCell As UByte Ptr = btreeCursorCell(pPage, pCursor->ix)
        If pCell = 0 Then Return SQLITE_CORRUPT
        Dim rc As SQLITE_C_INT = btreeMoveToChild(pCursor, btreeReadU32(pCell))
        If rc <> SQLITE_OK Then Return rc
        Return btreeMoveToRightmost(pCursor)
    End If
    If pCursor->ix > 0 Then
        pCursor->ix -= 1
        btreeCursorClearCellInfo(pCursor)
        Return SQLITE_OK
    End If

    While pCursor->iPage > 0
        btreeMoveToParent(pCursor)
        pPage = pCursor->pPage
        If pCursor->ix > 0 Then
            If pPage->intKey <> 0 Then
                Dim childIndex As Long = CLng(pCursor->ix) - 1
                Dim pCell As UByte Ptr = btreeCursorCell(pPage, childIndex)
                If pCell = 0 Then Return SQLITE_CORRUPT
                pCursor->ix = CUShort(childIndex)
                Dim rc As SQLITE_C_INT = btreeMoveToChild(pCursor, btreeReadU32(pCell))
                If rc <> SQLITE_OK Then Return rc
                Return btreeMoveToRightmost(pCursor)
            End If
            pCursor->ix -= 1
            btreeCursorClearCellInfo(pCursor)
            Return SQLITE_OK
        End If
    Wend
    pCursor->eState = CURSOR_INVALID
    Return SQLITE_DONE
End Function

Function sqlite3BtreePrevious CDecl Alias "sqlite3BtreePrevious" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If pCursor = 0 OrElse pCursor->pBt = 0 Then Return SQLITE_MISUSE
    If flags < 0 OrElse flags > 1 Then Return SQLITE_MISUSE
    pCursor->curFlags = pCursor->curFlags And Not BTCF_AT_LAST
    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim restoreResult As SQLITE_C_INT = 0
    Dim didRestore As SQLITE_C_INT = 0
    Dim alreadyAtPrevious As SQLITE_C_INT = 0
    ' Match sqlite3BtreeNext: tripped cursors must surface their stored error.
    If pCursor->eState <> CURSOR_VALID Then
        rc = btreeCursorRestoreInternal(pCursor, @restoreResult)
        didRestore = 1
    End If
    If rc = SQLITE_OK Then
        If pCursor->eState = CURSOR_SKIPNEXT Then
            pCursor->eState = CURSOR_VALID
            alreadyAtPrevious = IIf(pCursor->skipNext < 0, 1, 0)
            pCursor->skipNext = 0
        ElseIf didRestore <> 0 AndAlso pCursor->eState = CURSOR_VALID AndAlso restoreResult < 0 Then
            alreadyAtPrevious = 1
        End If
        If alreadyAtPrevious = 0 Then rc = btreeCursorPreviousInternal(pCursor)
    End If
    Return rc
End Function

/' ------------------------------------------------------------------------- '/
/' Table cursor lookup and payload reads '/
/' ------------------------------------------------------------------------- '/

Private Function btreeTableMovetoInternal( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal rowId As i64, _
    ByVal biasRight As SQLITE_C_INT, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT

    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pResult = 0 OrElse pCursor->pKeyInfo <> 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = btreeMoveToRoot(pCursor)
    If rc = SQLITE_EMPTY Then
        pResult[0] = -1
        Return SQLITE_OK
    End If
    If rc <> SQLITE_OK Then Return rc
    If pCursor->curIntKey = 0 Then Return SQLITE_CORRUPT

    Do
        Dim pPage As MemPage Ptr = pCursor->pPage
        If pPage = 0 OrElse pPage->nCell = 0 Then Return SQLITE_CORRUPT
        Dim lower As Long = 0
        Dim upper As Long = pPage->nCell
        While lower < upper
            Dim middle As Long = (lower + upper) \ 2
            Dim rcCell As SQLITE_C_INT = sqlite3BtreeGetCellInfo(pPage, middle, @pCursor->info)
            If rcCell <> SQLITE_OK Then Return rcCell
            pCursor->curFlags = pCursor->curFlags Or BTCF_VALID_NKEY
            If pCursor->info.nKey < rowId Then
                lower = middle + 1
            Else
                upper = middle
            End If
        Wend

        If pPage->leaf <> 0 Then
            Dim cellIndex As Long
            If lower >= pPage->nCell Then
                cellIndex = pPage->nCell - 1
            Else
                cellIndex = lower
            End If
            pCursor->ix = CUShort(cellIndex)
            btreeCursorClearCellInfo(pCursor)
            rc = getCellInfo(pCursor)
            If rc = SQLITE_OK Then
                If pCursor->info.nKey = rowId Then
                    pResult[0] = 0
                ElseIf pCursor->info.nKey < rowId Then
                    pResult[0] = -1
                Else
                    pResult[0] = 1
                End If
            End If
            Return rc
        End If

        Dim childIndex As Long = lower
        Dim childPage As u32
        If childIndex >= pPage->nCell Then
            childPage = btreeReadU32(pPage->aData + pPage->hdrOffset + 8)
        Else
            Dim pCell As UByte Ptr = btreeCursorCell(pPage, childIndex)
            If pCell = 0 Then Return SQLITE_CORRUPT
            childPage = btreeReadU32(pCell)
        End If
        pCursor->ix = CUShort(childIndex)
        rc = btreeMoveToChild(pCursor, childPage)
        If rc <> SQLITE_OK Then Return rc
    Loop
End Function

Function sqlite3BtreeTableMoveto CDecl Alias "sqlite3BtreeTableMoveto" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal rowId As i64, _
    ByVal biasRight As SQLITE_C_INT, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT Export

    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pResult = 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = btreeTableMovetoInternal(pCursor, rowId, biasRight, pResult)
    Return rc
End Function

Private Function btreeCompareIndexCell( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal cellIndex As SQLITE_C_INT, _
    ByVal pIndexKey As sqlite3VdbeUnpackedRecord Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT

    If pCursor = 0 OrElse pCursor->pPage = 0 OrElse pIndexKey = 0 OrElse pResult = 0 Then Return SQLITE_MISUSE
    pCursor->ix = CUShort(cellIndex)
    Dim rc As SQLITE_C_INT = sqlite3BtreeGetCellInfo(pCursor->pPage, cellIndex, @pCursor->info)
    If rc <> SQLITE_OK Then Return rc
    pCursor->curFlags = pCursor->curFlags Or BTCF_VALID_NKEY
    Dim pInfo As CellInfo Ptr = @pCursor->info
    If pInfo->nPayload < 2 OrElse pInfo->nPayload > &H7FFFFFFF Then Return SQLITE_CORRUPT

    If pInfo->nLocal = pInfo->nPayload Then
        If pInfo->pPayload = 0 Then Return SQLITE_CORRUPT
        pResult[0] = sqlite3VdbeRecordCompare(CLng(pInfo->nPayload), pInfo->pPayload, pIndexKey)
    Else
        Dim maxPayload As sqlite3_uint64 = CULngInt(pCursor->pBt->nPage) * pCursor->pBt->usableSize
        If CULngInt(pInfo->nPayload) > maxPayload OrElse _
           CULngInt(pInfo->nPayload) > SQLITE_MAX_ALLOCATION_SIZE - 18 Then Return SQLITE_CORRUPT
        Dim nAllocation As sqlite3_uint64 = CULngInt(pInfo->nPayload) + 18
        Dim pKeyBytes As UByte Ptr = CPtr(UByte Ptr, sqlite3Malloc(nAllocation))
        If pKeyBytes = 0 Then Return SQLITE_NOMEM
        rc = btreeAccessPayload(pCursor, 0, pInfo->nPayload, pKeyBytes)
        If rc = SQLITE_OK Then
            For i As Long = pInfo->nPayload To pInfo->nPayload + 17
                pKeyBytes[i] = 0
            Next
            pResult[0] = sqlite3VdbeRecordCompare(CLng(pInfo->nPayload), pKeyBytes, pIndexKey)
        End If
        sqlite3_free(pKeyBytes)
        If rc <> SQLITE_OK Then Return rc
    End If

    If pIndexKey->errCode = SQLITE_NOMEM Then Return SQLITE_NOMEM
    If pIndexKey->errCode <> SQLITE_OK Then Return SQLITE_CORRUPT
    Return SQLITE_OK
End Function

Private Function btreeIndexMovetoInternal( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pIndexKey As sqlite3VdbeUnpackedRecord Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT

    If pCursor = 0 OrElse pCursor->pKeyInfo = 0 OrElse pIndexKey = 0 OrElse _
       pIndexKey->pKeyInfo <> pCursor->pKeyInfo Then Return SQLITE_MISUSE
    pIndexKey->errCode = SQLITE_OK
    pIndexKey->eqSeen = 0
    Dim rc As SQLITE_C_INT = btreeMoveToRoot(pCursor)
    If rc = SQLITE_EMPTY Then
        pResult[0] = -1
        Return SQLITE_OK
    End If
    If rc <> SQLITE_OK Then Return rc
    If pCursor->curIntKey <> 0 Then Return SQLITE_CORRUPT

    Do
        Dim pPage As MemPage Ptr = pCursor->pPage
        If pPage = 0 OrElse pPage->nCell = 0 Then Return SQLITE_CORRUPT
        Dim lower As Long = 0
        Dim upper As Long = pPage->nCell
        While lower < upper
            Dim middle As Long = (lower + upper) \ 2
            Dim comparison As SQLITE_C_INT = 0
            rc = btreeCompareIndexCell(pCursor, middle, pIndexKey, @comparison)
            If rc <> SQLITE_OK Then Return rc
            If comparison < 0 Then
                lower = middle + 1
            ElseIf comparison = 0 Then
                ' Interior index cells are searchable records too. Keep an
                ' exact separator match on this page for OP_Found callers.
                pCursor->ix = CUShort(middle)
                pResult[0] = 0
                Return SQLITE_OK
            Else
                upper = middle
            End If
        Wend

        If pPage->leaf <> 0 Then
            Dim cellIndex As Long = lower
            If cellIndex >= pPage->nCell Then cellIndex = pPage->nCell - 1
            pCursor->ix = CUShort(cellIndex)
            btreeCursorClearCellInfo(pCursor)
            rc = btreeCompareIndexCell(pCursor, cellIndex, pIndexKey, pResult)
            btreeCursorClearCellInfo(pCursor)
            Return rc
        End If

        Dim childIndex As Long = lower
        Dim childPage As u32
        If childIndex >= pPage->nCell Then
            childPage = btreeReadU32(pPage->aData + pPage->hdrOffset + 8)
        Else
            Dim pCell As UByte Ptr = btreeCursorCell(pPage, childIndex)
            If pCell = 0 Then Return SQLITE_CORRUPT
            childPage = btreeReadU32(pCell)
        End If
        pCursor->ix = CUShort(childIndex)
        rc = btreeMoveToChild(pCursor, childPage)
        If rc <> SQLITE_OK Then Return rc
    Loop
End Function

Function sqlite3BtreeIndexMoveto CDecl Alias "sqlite3BtreeIndexMoveto" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pIndexKey As Any Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT Export
    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pResult = 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = btreeIndexMovetoInternal(pCursor, _
        CPtr(sqlite3VdbeUnpackedRecord Ptr, pIndexKey), pResult)
    Return rc
End Function

Private Function btreeIndexMovetoPayload( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pPayload As SqliteBtreePayload Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT

    If pCursor = 0 OrElse pCursor->pKeyInfo = 0 OrElse _
       pPayload = 0 OrElse pResult = 0 Then Return SQLITE_MISUSE
    Dim pKeyInfo As sqlite3VdbeKeyInfoPrefix Ptr = _
        CPtr(sqlite3VdbeKeyInfoPrefix Ptr, pCursor->pKeyInfo)

    If pPayload->nMem <> 0 Then
        If pPayload->aMem = 0 OrElse pPayload->nMem > pKeyInfo->nAllField Then Return SQLITE_MISUSE
        Dim unpacked As sqlite3VdbeUnpackedRecord
        unpacked.pKeyInfo = pCursor->pKeyInfo
        unpacked.aMem = CPtr(SqliteVdbeMem Ptr, pPayload->aMem)
        unpacked.u.i = 0
        unpacked.n = 0
        unpacked.nField = pPayload->nMem
        unpacked.default_rc = 0
        unpacked.errCode = SQLITE_OK
        unpacked.r1 = 0
        unpacked.r2 = 0
        unpacked.eqSeen = 0
        Return btreeIndexMovetoInternal(pCursor, @unpacked, pResult)
    End If

    If pPayload->pKey = 0 OrElse pPayload->nKey <= 0 OrElse _
       pPayload->nKey > SQLITE_MAX_ALLOCATION_SIZE OrElse pKeyInfo->nKeyField = 0 Then Return SQLITE_MISUSE
    ' Match sqlite3VdbeAllocUnpackedRecord: compare the key plus its tie-break field.
    Dim fieldCount As SQLITE_C_INT = CInt(pKeyInfo->nKeyField) + 1
    Dim memoryBytes As sqlite3_uint64 = CULngInt(fieldCount) * SizeOf(SqliteVdbeMem)
    If memoryBytes > SQLITE_MAX_ALLOCATION_SIZE Then Return SQLITE_TOOBIG
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, sqlite3MallocZero(memoryBytes))
    If pMem = 0 Then Return SQLITE_NOMEM

    Dim unpacked As sqlite3VdbeUnpackedRecord
    unpacked.pKeyInfo = pCursor->pKeyInfo
    unpacked.aMem = pMem
    unpacked.u.i = 0
    unpacked.n = 0
    unpacked.nField = CUShort(fieldCount)
    unpacked.default_rc = 0
    unpacked.errCode = SQLITE_OK
    unpacked.r1 = 0
    unpacked.r2 = 0
    unpacked.eqSeen = 0
    sqlite3VdbeRecordUnpack(CLng(pPayload->nKey), pPayload->pKey, @unpacked)

    Dim rc As SQLITE_C_INT = SQLITE_OK
    If unpacked.errCode <> SQLITE_OK Then
        rc = unpacked.errCode
    Else
        rc = btreeIndexMovetoInternal(pCursor, @unpacked, pResult)
    End If
    For iField As SQLITE_C_INT = 0 To unpacked.nField - 1
        sqlite3VdbeMemRelease(@pMem[iField])
    Next
    sqlite3_free(pMem)
    Return rc
End Function

' Table cursors carry the rowid directly. Index cursors carry a packed record;
' the bounded payload path unpacks and validates it before descending the tree.
Function btreeMoveto CDecl Alias "btreeMoveto" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pKey As Const Any Ptr, _
    ByVal keySize As i64, _
    ByVal biasRight As SQLITE_C_INT, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT

    If pResult <> 0 Then pResult[0] = 0
    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pResult = 0 OrElse _
       biasRight < 0 OrElse biasRight > 1 Then Return SQLITE_MISUSE

    If pKey = 0 Then
        If pCursor->pKeyInfo <> 0 Then Return SQLITE_CORRUPT
        Return btreeTableMovetoInternal(pCursor, keySize, biasRight, pResult)
    End If

    If pCursor->pKeyInfo = 0 OrElse keySize <= 0 OrElse _
       keySize > SQLITE_MAX_ALLOCATION_SIZE Then Return SQLITE_CORRUPT
    Dim packedKey As SqliteBtreePayload
    ' The record decoder reads packed key bytes without modifying them.
    Dim packedKeyBytes As Any Ptr = CPtr(Any Ptr, pKey)
    packedKey.pKey = packedKeyBytes
    packedKey.nKey = keySize
    packedKey.pData = 0
    packedKey.aMem = 0
    packedKey.nMem = 0
    packedKey.nData = 0
    packedKey.nZero = 0
    Return btreeIndexMovetoPayload(pCursor, @packedKey, pResult)
End Function

' Cursor save operations run with the shared B-tree mutex held so the current
' page and its payload cannot change between reading the key and releasing it.
Private Function btreeSaveCursorKey CDecl Alias "saveCursorKey" ( _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT
    If pCursor = 0 OrElse pCursor->pBt = 0 Then Return SQLITE_MISUSE
    If pCursor->eState <> CURSOR_VALID OrElse pCursor->pKey <> 0 Then Return SQLITE_MISUSE
    If pCursor->pPage = 0 Then Return SQLITE_CORRUPT
    Dim rc As SQLITE_C_INT = getCellInfo(pCursor)
    If rc <> SQLITE_OK Then Return rc

    Dim pSavedKey As UByte Ptr = 0
    Dim savedKeySize As sqlite3_uint64 = 0
    If pCursor->pKeyInfo <> 0 Then
        savedKeySize = pCursor->info.nPayload
        If savedKeySize = 0 Then Return SQLITE_CORRUPT
        If savedKeySize > SQLITE_MAX_ALLOCATION_SIZE - 17 Then Return SQLITE_NOMEM
        pSavedKey = CPtr(UByte Ptr, sqlite3Malloc(savedKeySize + 17))
        If pSavedKey = 0 Then Return SQLITE_NOMEM
        rc = btreeAccessPayload(pCursor, 0, CULng(savedKeySize), pSavedKey)
        If rc <> SQLITE_OK Then
            sqlite3_free(pSavedKey)
            Return rc
        End If
        ' Record-unpack may inspect 17 bytes beyond a malformed key payload.
        For paddingIndex As SQLITE_C_INT = 0 To 16
            pSavedKey[CULngInt(savedKeySize) + paddingIndex] = 0
        Next
    End If

    If pCursor->pKey <> 0 Then sqlite3_free(pCursor->pKey)
    pCursor->pKey = pSavedKey
    If pCursor->pKeyInfo <> 0 Then
        pCursor->nKey = CULngInt(savedKeySize)
    Else
        pCursor->nKey = pCursor->info.nKey
    End If
    Return SQLITE_OK
End Function

Private Function btreeSaveCursorPosition CDecl Alias "saveCursorPosition" ( _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT
    If pCursor = 0 OrElse pCursor->pBt = 0 Then Return SQLITE_MISUSE
    If pCursor->eState <> CURSOR_VALID AndAlso pCursor->eState <> CURSOR_SKIPNEXT Then Return SQLITE_OK
    If (pCursor->curFlags And BTCF_PINNED) <> 0 Then Return SQLITE_CONSTRAINT_PINNED
    If pCursor->eState = CURSOR_SKIPNEXT Then
        pCursor->eState = CURSOR_VALID
    Else
        pCursor->skipNext = 0
    End If
    Dim rc As SQLITE_C_INT = btreeSaveCursorKey(pCursor)
    If rc = SQLITE_OK Then
        btreeReleaseAllCursorPages(pCursor)
        pCursor->eState = CURSOR_REQUIRESEEK
    End If
    pCursor->curFlags = pCursor->curFlags And Not _
        (BTCF_VALID_NKEY Or BTCF_VALID_OVFL Or BTCF_AT_LAST)
    Return rc
End Function

Private Function btreeSaveCursorsOnList CDecl Alias "saveCursorsOnList" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal rootPage As u32, _
    ByVal pExcept As BtCursor Ptr _
) As SQLITE_C_INT

    While pCursor <> 0
        If pCursor <> pExcept AndAlso _
           (rootPage = 0 OrElse pCursor->pgnoRoot = rootPage) Then
            If pCursor->eState = CURSOR_VALID OrElse pCursor->eState = CURSOR_SKIPNEXT Then
                Dim rc As SQLITE_C_INT = btreeSaveCursorPosition(pCursor)
                If rc <> SQLITE_OK Then Return rc
            Else
                btreeReleaseAllCursorPages(pCursor)
            End If
        End If
        pCursor = pCursor->pNext
    Wend
    Return SQLITE_OK
End Function

Private Function btreeSaveAllCursors CDecl Alias "saveAllCursors" ( _
    ByVal pBt As BtShared Ptr, _
    ByVal rootPage As u32, _
    ByVal pExcept As BtCursor Ptr _
) As SQLITE_C_INT

    If pBt = 0 Then Return SQLITE_MISUSE
    Dim pCursor As BtCursor Ptr = CPtr(BtCursor Ptr, pBt->pCursor)
    While pCursor <> 0
        If pCursor <> pExcept AndAlso _
           (rootPage = 0 OrElse pCursor->pgnoRoot = rootPage) Then
            Return btreeSaveCursorsOnList(pCursor, rootPage, pExcept)
        End If
        pCursor = pCursor->pNext
    Wend
    If pExcept <> 0 Then pExcept->curFlags = pExcept->curFlags And Not BTCF_MULTIPLE
    Return SQLITE_OK
End Function

Function sqlite3BtreeTripAllCursors CDecl Alias "sqlite3BtreeTripAllCursors" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal writeOnly As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If writeOnly <> 0 AndAlso writeOnly <> 1 Then Return SQLITE_MISUSE
    If pBtree = 0 OrElse pBtree->pBt = 0 Then Return SQLITE_OK
    Dim pBt As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim pCursor As BtCursor Ptr = CPtr(BtCursor Ptr, pBt->pCursor)

    While pCursor <> 0
        If writeOnly <> 0 AndAlso (pCursor->curFlags And BTCF_WRITE_FLAG) = 0 Then
            If pCursor->eState = CURSOR_VALID OrElse pCursor->eState = CURSOR_SKIPNEXT Then
                rc = btreeSaveCursorPosition(pCursor)
            Else
                Dim savedState As UByte = pCursor->eState
                btreeReleaseAllCursorPages(pCursor)
                pCursor->eState = savedState
            End If
            If rc <> SQLITE_OK Then Exit While
        Else
            sqlite3BtreeClearCursor(pCursor)
            btreeReleaseAllCursorPages(pCursor)
            pCursor->eState = CURSOR_FAULT
            pCursor->skipNext = errorCode
        End If
        pCursor = pCursor->pNext
    Wend

    If rc <> SQLITE_OK Then
        pCursor = CPtr(BtCursor Ptr, pBt->pCursor)
        While pCursor <> 0
            sqlite3BtreeClearCursor(pCursor)
            btreeReleaseAllCursorPages(pCursor)
            pCursor->eState = CURSOR_FAULT
            pCursor->skipNext = rc
            pCursor = pCursor->pNext
        Wend
    End If

    sqlite3BtreeLeave(pBtree)
    Return rc
End Function

Private Function btreeCursorRestoreInternal( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT

    If pResult <> 0 Then pResult[0] = 0
    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pResult = 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pCursor->eState = CURSOR_FAULT Then
        rc = pCursor->skipNext
    ElseIf pCursor->eState = CURSOR_REQUIRESEEK Then
        pCursor->eState = CURSOR_INVALID
        If sqlite3FaultSim(410) <> 0 Then
            rc = SQLITE_IOERR
        Else
            rc = btreeMoveto(pCursor, pCursor->pKey, pCursor->nKey, 0, pResult)
        End If
        If rc = SQLITE_OK Then
            If pCursor->pKey <> 0 Then sqlite3_free(pCursor->pKey)
            pCursor->pKey = 0
            If pResult[0] <> 0 Then pCursor->skipNext = pResult[0]
            If pCursor->skipNext <> 0 AndAlso pCursor->eState = CURSOR_VALID Then
                pCursor->eState = CURSOR_SKIPNEXT
            End If
        Else
            btreeReleaseAllCursorPages(pCursor)
            pCursor->eState = CURSOR_REQUIRESEEK
        End If
    End If
    Return rc
End Function

Private Function btreeRestoreCursorPosition CDecl Alias "btreeRestoreCursorPosition" ( _
    ByVal pCursor As BtCursor Ptr _
) As SQLITE_C_INT

    If pCursor = 0 OrElse pCursor->pBt = 0 Then Return SQLITE_MISUSE
    If pCursor->eState = CURSOR_FAULT Then Return pCursor->skipNext
    If pCursor->eState < CURSOR_REQUIRESEEK Then Return SQLITE_OK
    Dim ignoredLocation As SQLITE_C_INT = 0
    Return btreeCursorRestoreInternal(pCursor, @ignoredLocation)
End Function

Function sqlite3BtreeCursorRestore CDecl Alias "sqlite3BtreeCursorRestore" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT Export

    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pResult = 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = btreeCursorRestoreInternal(pCursor, pResult)
    Return rc
End Function

Private Function btreeSetCursorRequireSeek( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pPayload As SqliteBtreePayload Ptr _
) As SQLITE_C_INT

    If pCursor = 0 OrElse pPayload = 0 Then Return SQLITE_MISUSE
    Dim pSavedKey As UByte Ptr = 0
    If pCursor->pKeyInfo <> 0 Then
        If pPayload->pKey = 0 OrElse pPayload->nKey <= 0 OrElse _
           pPayload->nKey > SQLITE_MAX_ALLOCATION_SIZE Then Return SQLITE_MISUSE
        pSavedKey = CPtr(UByte Ptr, sqlite3Malloc(CULngInt(pPayload->nKey)))
        If pSavedKey = 0 Then Return SQLITE_NOMEM
        btreeSystemMemcpy(pSavedKey, pPayload->pKey, CULngInt(pPayload->nKey))
    End If
    btreeReleaseAllCursorPages(pCursor)
    If pCursor->pKey <> 0 Then sqlite3_free(pCursor->pKey)
    pCursor->pKey = pSavedKey
    pCursor->nKey = pPayload->nKey
    pCursor->eState = CURSOR_REQUIRESEEK
    pCursor->skipNext = 0
    Return SQLITE_OK
End Function

Function sqlite3BtreeInsert CDecl Alias "sqlite3BtreeInsert" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pPayload As SqliteBtreePayload Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal seekResult As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pCursor->pBtree = 0 OrElse _
       pPayload = 0 OrElse _
       (flags And Not (BTREE_SAVEPOSITION Or BTREE_APPEND Or BTREE_PREFORMAT)) <> 0 Then _
        Return SQLITE_MISUSE
    ' WITHOUT ROWID updates preserve the matched index cursor while replacing
    ' its row. A zero seek result means that the cursor is on that exact key.
    If (flags And BTREE_SAVEPOSITION) <> 0 AndAlso _
       pCursor->pKeyInfo <> 0 AndAlso seekResult <> 0 Then Return SQLITE_MISUSE
    If (flags And BTREE_PREFORMAT) <> 0 AndAlso pCursor->pKeyInfo <> 0 AndAlso seekResult = 0 Then Return SQLITE_MISUSE

    Dim pBt As BtShared Ptr = pCursor->pBt
    Dim pBtree As Btree Ptr = pCursor->pBtree
    Dim rc As SQLITE_C_INT = SQLITE_OK
    ' Index comparisons may return any signed difference. Insertion uses only
    ' the sign to identify which side of the current cell holds the new key.
    Dim location As SQLITE_C_INT = seekResult
    Dim pPage As MemPage Ptr = 0
    Dim pNewCell As UByte Ptr = 0
    Dim newCellSize As SQLITE_C_INT = 0
    Dim cellIndex As SQLITE_C_INT = 0
    Dim oldChildPage As u32 = 0
    Dim didOverwrite As SQLITE_C_INT = 0
    Dim didBalance As SQLITE_C_INT = 0
    Dim isPreformat As SQLITE_C_INT = IIf((flags And BTREE_PREFORMAT) <> 0, 1, 0)
    Dim payloadSize As sqlite3_uint64 = 0

    If pBtree->pBt <> pBt OrElse pBtree->inTrans <> TRANS_WRITE OrElse _
       (pBt->btsFlags And BTS_READ_ONLY) <> 0 OrElse _
       (pCursor->curFlags And BTCF_WRITE_FLAG) = 0 Then
        rc = SQLITE_READONLY
    End If
    If rc = SQLITE_OK AndAlso pCursor->pgnoRoot = 0 Then rc = SQLITE_CORRUPT
    If rc = SQLITE_OK AndAlso isPreformat = 0 Then
        If pCursor->pKeyInfo = 0 Then
            If pPayload->pKey <> 0 OrElse pPayload->nData < 0 OrElse pPayload->nZero < 0 OrElse _
               (pPayload->nData > 0 AndAlso pPayload->pData = 0) Then
                rc = SQLITE_MISUSE
            Else
                payloadSize = CULngInt(pPayload->nData) + CULngInt(pPayload->nZero)
            End If
        Else
            If pPayload->pKey = 0 OrElse pPayload->nKey < 0 OrElse _
               pPayload->nKey > &H7FFFFFFF OrElse _
               (pPayload->nMem > 0 AndAlso pPayload->aMem = 0) Then
                rc = SQLITE_MISUSE
            Else
                payloadSize = CULngInt(pPayload->nKey)
            End If
        End If
    End If
    If rc = SQLITE_OK AndAlso payloadSize > &H7FFFFFFF Then rc = SQLITE_TOOBIG

    If rc = SQLITE_OK AndAlso (pCursor->curFlags And BTCF_MULTIPLE) <> 0 Then
        rc = btreeSaveAllCursors(pBt, pCursor->pgnoRoot, pCursor)
    End If
    If rc = SQLITE_OK AndAlso pCursor->eState = CURSOR_FAULT Then rc = pCursor->skipNext
    If rc = SQLITE_OK AndAlso pCursor->eState = CURSOR_REQUIRESEEK Then
        Dim ignoredLocation As SQLITE_C_INT = 0
        rc = btreeCursorRestoreInternal(pCursor, @ignoredLocation)
    End If
    If rc = SQLITE_OK AndAlso pCursor->pKeyInfo = 0 AndAlso pBtree->hasIncrblobCur <> 0 Then
        invalidateIncrblobCursors(pBtree, pCursor->pgnoRoot, pPayload->nKey, 0)
    End If

    ' BTREE_SAVEPOSITION means the caller already positioned the cursor on this
    ' key. Re-seeking here can disturb the cursor while rewriting a WITHOUT
    ' ROWID record in place.
    If rc = SQLITE_OK AndAlso location = 0 AndAlso _
       (flags And BTREE_SAVEPOSITION) = 0 Then
        If pCursor->pKeyInfo = 0 Then
            rc = btreeTableMovetoInternal(pCursor, pPayload->nKey, _
                IIf((flags And BTREE_APPEND) <> 0, 1, 0), @location)
        Else
            rc = btreeIndexMovetoPayload(pCursor, pPayload, @location)
        End If
    End If

    If rc = SQLITE_OK AndAlso location = 0 AndAlso isPreformat = 0 Then
        rc = getCellInfo(pCursor)
        If rc = SQLITE_OK AndAlso pCursor->pKeyInfo = 0 AndAlso _
           pCursor->info.nKey = pPayload->nKey AndAlso _
           pCursor->info.nPayload = payloadSize Then
            rc = btreeOverwriteCell(pCursor, pPayload)
            If rc = SQLITE_OK Then didOverwrite = 1
        ElseIf rc = SQLITE_OK AndAlso pCursor->pKeyInfo <> 0 AndAlso _
               pCursor->info.nPayload = pPayload->nKey Then
            Dim overwritePayload As SqliteBtreePayload
            overwritePayload.pKey = 0
            overwritePayload.nKey = 0
            overwritePayload.pData = pPayload->pKey
            overwritePayload.aMem = 0
            overwritePayload.nMem = 0
            overwritePayload.nData = CLng(pPayload->nKey)
            overwritePayload.nZero = 0
            rc = btreeOverwriteCell(pCursor, @overwritePayload)
            If rc = SQLITE_OK Then didOverwrite = 1
        End If
    End If

    If rc = SQLITE_OK AndAlso didOverwrite = 0 Then
        If pCursor->pPage = 0 OrElse pCursor->iPage < 0 OrElse _
           pCursor->pPage->isInit = 0 OrElse pCursor->pPage->nFree < -1 Then
            rc = SQLITE_CORRUPT
        Else
            pPage = pCursor->pPage
        End If
    End If
    If rc = SQLITE_OK AndAlso didOverwrite = 0 Then
        If pPage->nFree < 0 Then rc = sqlite3BtreeComputeFreeSpace(pPage)
        If pPage->isInit = 0 OrElse pPage->intKey <> IIf(pCursor->pKeyInfo = 0, 1, 0) Then rc = SQLITE_CORRUPT
    End If
    If rc = SQLITE_OK AndAlso didOverwrite = 0 Then
        If pBt->pTmpSpace = 0 Then
            rc = SQLITE_NOMEM
        ElseIf (flags And BTREE_PREFORMAT) <> 0 Then
            newCellSize = pBt->nPreformatSize
            pNewCell = pBt->pTmpSpace
            If newCellSize < 0 OrElse newCellSize > pBt->pageSize Then
                rc = SQLITE_CORRUPT
            ElseIf newCellSize < 4 Then
                newCellSize = 4
                pNewCell[3] = 0
            End If
            If rc = SQLITE_OK AndAlso sqlite3BtreeCellSize(pPage, pNewCell) <> newCellSize Then rc = SQLITE_CORRUPT
#ifndef SQLITE_OMIT_AUTOVACUUM
            If rc = SQLITE_OK AndAlso pBt->autoVacuum <> 0 AndAlso _
               newCellSize > pPage->maxLocal Then
                Dim parseCell As BtreeCellParseProc = _
                    CPtr(BtreeCellParseProc, pPage->xParseCell)
                Dim preformattedInfo As CellInfo
                If parseCell = 0 Then
                    rc = SQLITE_CORRUPT
                Else
                    parseCell(pPage, pNewCell, @preformattedInfo)
                    If preformattedInfo.nPayload <> preformattedInfo.nLocal Then
                        If newCellSize < 4 Then
                            rc = SQLITE_CORRUPT
                        Else
                            Dim firstOverflowPage As u32 = _
                                btreeReadU32(pNewCell + newCellSize - 4)
                            ptrmapPut(pBt, firstOverflowPage, _
                                PTRMAP_OVERFLOW1, pPage->pgno, @rc)
                        End If
                    End If
                End If
            End If
#endif
        Else
            pNewCell = pBt->pTmpSpace
            rc = btreeBuildCell(pPage, pPayload, pNewCell, CLng(pBt->pageSize), @newCellSize)
        End If
    End If

    If rc = SQLITE_OK AndAlso didOverwrite = 0 Then
        cellIndex = pCursor->ix
        If location = 0 Then
            If cellIndex < 0 OrElse cellIndex >= pPage->nCell Then
                rc = SQLITE_CORRUPT
            Else
                rc = getCellInfo(pCursor)
                If rc = SQLITE_OK Then
                    Dim pOldCell As UByte Ptr = btreeCursorCell(pPage, cellIndex)
                    If pOldCell = 0 Then
                        rc = SQLITE_CORRUPT
                    Else
                        If pPage->leaf = 0 Then oldChildPage = btreeReadU32(pOldCell)
                        rc = btreeClearCellOverflow(pPage, pOldCell, @pCursor->info)
                        If rc = SQLITE_OK Then rc = sqlite3BtreeDropCell(pPage, cellIndex)
                    End If
                End If
            End If
            btreeMoveToOverflowStart(pCursor)
        ElseIf location < 0 AndAlso pPage->nCell > 0 Then
            If pPage->leaf = 0 Then
                rc = SQLITE_CORRUPT
            Else
                cellIndex += 1
                pCursor->ix += 1
                btreeMoveToOverflowStart(pCursor)
            End If
        ElseIf pPage->leaf = 0 Then
            rc = SQLITE_CORRUPT
        End If
    End If

    If rc = SQLITE_OK AndAlso didOverwrite = 0 Then
        If pPage->leaf <> 0 Then
            rc = btreeInsertCellFast(pPage, cellIndex, pNewCell, newCellSize)
        ElseIf oldChildPage <> 0 Then
            rc = btreeInsertCellWithChild(pPage, cellIndex, pNewCell, newCellSize, oldChildPage)
        Else
            rc = SQLITE_CORRUPT
        End If
    End If

    If rc = SQLITE_OK AndAlso didOverwrite = 0 AndAlso pPage->nOverflow <> 0 Then
        pCursor->curFlags = pCursor->curFlags And Not (BTCF_VALID_NKEY Or BTCF_VALID_OVFL)
        rc = btreeBalanceCursor(pCursor)
        didBalance = 1
        If pCursor->pPage <> 0 Then pCursor->pPage->nOverflow = 0
        btreeReleaseAllCursorPages(pCursor)
    End If

    If rc = SQLITE_OK AndAlso didOverwrite = 0 AndAlso didBalance = 0 Then
        btreeCursorClearCellInfo(pCursor)
        pCursor->eState = CURSOR_VALID
    End If
    ' Only balance invalidates the saved position. Without balancing, keep the
    ' cursor on the replaced key so the next OP_Next can advance normally.
    If rc = SQLITE_OK AndAlso didBalance <> 0 AndAlso _
       (flags And BTREE_SAVEPOSITION) <> 0 Then
        rc = btreeSetCursorRequireSeek(pCursor, pPayload)
    End If
    Return rc
End Function

Function sqlite3BtreeTransferRow CDecl Alias "sqlite3BtreeTransferRow" ( _
    ByVal pDestination As BtCursor Ptr, _
    ByVal pSource As BtCursor Ptr, _
    ByVal destinationRowId As i64 _
) As SQLITE_C_INT Export

    If pDestination = 0 OrElse pSource = 0 OrElse _
       pDestination->pBt = 0 OrElse pSource->pBt = 0 OrElse _
       pDestination->pPage = 0 OrElse pDestination->pBtree = 0 OrElse pSource->pBtree = 0 OrElse _
       pDestination->pBtree->inTrans <> TRANS_WRITE OrElse _
       (pDestination->curFlags And BTCF_WRITE_FLAG) = 0 Then Return SQLITE_MISUSE
    Dim pDestinationBt As BtShared Ptr = pDestination->pBt
    Dim pSourceBt As BtShared Ptr = pSource->pBt
    Dim pFirstLock As BtShared Ptr = pDestinationBt
    Dim pSecondLock As BtShared Ptr = 0
    If pDestinationBt <> pSourceBt Then
        If CULngInt(pSourceBt) < CULngInt(pDestinationBt) Then
            pFirstLock = pSourceBt
            pSecondLock = pDestinationBt
        Else
            pSecondLock = pSourceBt
        End If
    End If
    If pSecondLock <> 0 Then sqlite3_mutex_enter(pSecondLock->mutex)

    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim pOverflow As MemPage Ptr = 0
    Do
        If (pDestinationBt->btsFlags And BTS_READ_ONLY) <> 0 Then
            rc = SQLITE_READONLY
            Exit Do
        End If
        If pDestinationBt->pTmpSpace = 0 OrElse pDestination->pPage->isInit = 0 OrElse _
           pDestination->pPage->pBt <> pDestinationBt Then
            rc = SQLITE_MISUSE
            Exit Do
        End If
        If pSource->eState = CURSOR_FAULT Then
            rc = pSource->skipNext
            Exit Do
        ElseIf pSource->eState = CURSOR_REQUIRESEEK Then
            Dim ignoredLocation As SQLITE_C_INT = 0
            rc = btreeCursorRestoreInternal(pSource, @ignoredLocation)
            If rc <> SQLITE_OK Then Exit Do
        ElseIf pSource->eState = CURSOR_SKIPNEXT Then
            pSource->eState = CURSOR_VALID
            pSource->skipNext = 0
        End If
        If pSource->eState <> CURSOR_VALID OrElse pSource->pPage = 0 OrElse _
           pSource->pPage->intKey <> pDestination->pPage->intKey OrElse _
           (pSource->pKeyInfo = 0) <> (pSource->pPage->intKey <> 0) OrElse _
           (pDestination->pKeyInfo = 0) <> (pDestination->pPage->intKey <> 0) Then
            rc = SQLITE_MISUSE
            Exit Do
        End If
        rc = getCellInfo(pSource)
        If rc <> SQLITE_OK Then Exit Do

        Dim payloadSize As sqlite3_uint64 = pSource->info.nPayload
        If payloadSize > &H7FFFFFFF OrElse pDestinationBt->usableSize <= 4 Then
            rc = SQLITE_TOOBIG
            Exit Do
        End If
        Dim localPayload As u16 = CUShort(btreePayloadToLocal(pDestination->pPage, CLngInt(payloadSize)))
        Dim prefixSize As SQLITE_C_INT = pDestination->pPage->childPtrSize
        If (pDestination->pPage->leaf <> 0 AndAlso prefixSize <> 0) OrElse _
           (pDestination->pPage->leaf = 0 AndAlso prefixSize <> 4) OrElse _
           (pDestination->pPage->intKey <> 0 AndAlso pDestination->pPage->leaf = 0) Then
            rc = SQLITE_CORRUPT
            Exit Do
        End If
        Dim payloadHeaderSize As SQLITE_C_INT = sqlite3VarintLen(payloadSize)
        Dim rowIdHeaderSize As SQLITE_C_INT = 0
        If pDestination->pPage->intKey <> 0 Then _
            rowIdHeaderSize = btreeRowidVarintLen(CULngInt(destinationRowId))
        Dim cellHeaderSize As SQLITE_C_INT = prefixSize + payloadHeaderSize + rowIdHeaderSize
        Dim cellSize As sqlite3_uint64 = CULngInt(cellHeaderSize) + localPayload
        If localPayload < payloadSize Then cellSize += 4
        If cellSize < 4 Then cellSize = 4
        If cellSize > pDestinationBt->pageSize OrElse cellSize > 65535 Then
            rc = SQLITE_TOOBIG
            Exit Do
        End If

        Dim pCell As UByte Ptr = pDestinationBt->pTmpSpace
        For iByte As SQLITE_C_INT = 0 To CLng(cellSize) - 1
            pCell[iByte] = 0
        Next
        If prefixSize <> 0 Then btreeWriteU32(pCell, 0)
        Dim written As SQLITE_C_INT = sqlite3PutVarint(pCell + prefixSize, payloadSize)
        If written <> payloadHeaderSize Then
            rc = SQLITE_CORRUPT
            Exit Do
        End If
        Dim payloadOffset As SQLITE_C_INT = prefixSize + written
        If pDestination->pPage->intKey <> 0 Then
            written = sqlite3PutVarint(pCell + payloadOffset, CULngInt(destinationRowId))
            If written <> rowIdHeaderSize Then
                rc = SQLITE_CORRUPT
                Exit Do
            End If
            payloadOffset += written
        End If
        If localPayload > 0 Then
            rc = btreeAccessPayload(pSource, 0, localPayload, pCell + payloadOffset)
            If rc <> SQLITE_OK Then Exit Do
        End If
        pDestinationBt->nPreformatSize = CLng(cellSize)

        If localPayload < payloadSize Then
            Dim overflowCapacity As u32 = pDestinationBt->usableSize - 4
            If overflowCapacity = 0 Then
                rc = SQLITE_CORRUPT
                Exit Do
            End If
            Dim remaining As sqlite3_uint64 = payloadSize - localPayload
            Dim sourceOffset As u32 = localPayload
            Dim firstOverflowPage As u32 = 0
            Dim priorOverflow As MemPage Ptr = 0
            While remaining > 0 AndAlso rc = SQLITE_OK
                Dim overflowPageNumber As u32 = 0
                Dim overflowMapType As u8 = PTRMAP_OVERFLOW1
                Dim overflowParent As u32 = pDestination->pPage->pgno
                If priorOverflow <> 0 Then
                    overflowMapType = PTRMAP_OVERFLOW2
                    overflowParent = priorOverflow->pgno
                End If
                rc = btreeAllocatePageAny(pDestinationBt, @pOverflow, @overflowPageNumber, _
                                          overflowMapType, overflowParent)
                If rc <> SQLITE_OK Then Exit While
                If pOverflow = 0 OrElse pOverflow->aData = 0 Then
                    sqlite3BtreeReleasePage(pOverflow)
                    pOverflow = 0
                    rc = SQLITE_CORRUPT
                    Exit While
                End If
                If overflowPageNumber < 2 OrElse overflowPageNumber > pDestinationBt->nPage Then
                    rc = SQLITE_CORRUPT
                    Exit While
                End If
                If firstOverflowPage = 0 Then
                    firstOverflowPage = overflowPageNumber
                Else
                    btreeWriteU32(priorOverflow->aData, overflowPageNumber)
                End If
                btreeWriteU32(pOverflow->aData, 0)

                Dim pageAmount As u32 = CULng(remaining)
                If pageAmount > overflowCapacity Then pageAmount = overflowCapacity
                rc = btreeAccessPayload(pSource, sourceOffset, pageAmount, pOverflow->aData + 4)
                If rc <> SQLITE_OK Then Exit While
                remaining -= pageAmount
                sourceOffset += pageAmount
                If remaining > 0 Then
                    If priorOverflow <> 0 Then sqlite3BtreeReleasePage(priorOverflow)
                    priorOverflow = pOverflow
                    pOverflow = 0
                Else
                    sqlite3BtreeReleasePage(pOverflow)
                    pOverflow = 0
                End If
            Wend
            If priorOverflow <> 0 Then
                sqlite3BtreeReleasePage(priorOverflow)
                priorOverflow = 0
            End If
            If rc = SQLITE_OK AndAlso firstOverflowPage = 0 Then rc = SQLITE_CORRUPT
            If rc = SQLITE_OK Then btreeWriteU32(pCell + cellHeaderSize + localPayload, firstOverflowPage)
        End If
    Loop While 0

    sqlite3BtreeReleasePage(pOverflow)
    If rc <> SQLITE_OK Then pDestinationBt->nPreformatSize = 0
    If pSecondLock <> 0 Then sqlite3_mutex_leave(pSecondLock->mutex)
    Return rc
End Function

Function sqlite3BtreeDelete CDecl Alias "sqlite3BtreeDelete" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal flags As u8 _
) As SQLITE_C_INT Export

    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pCursor->pBtree = 0 OrElse _
       (flags And Not (BTREE_SAVEPOSITION Or BTREE_AUXDELETE)) <> 0 Then Return SQLITE_MISUSE
    Dim pBt As BtShared Ptr = pCursor->pBt
    Dim pBtree As Btree Ptr = pCursor->pBtree
    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim pPage As MemPage Ptr = 0
    Dim pCell As UByte Ptr = 0
    Dim originalDepth As SQLITE_C_INT = pCursor->iPage
    Dim originalCellIndex As SQLITE_C_INT = pCursor->ix
    Dim savedCellInfo As CellInfo
    Dim preservePosition As SQLITE_C_INT = IIf((flags And BTREE_SAVEPOSITION) <> 0, 1, 0)
    Dim changed As SQLITE_C_INT = 0

    If pBtree->pBt <> pBt OrElse pBtree->inTrans <> TRANS_WRITE OrElse _
       (pBt->btsFlags And BTS_READ_ONLY) <> 0 OrElse _
       (pCursor->curFlags And BTCF_WRITE_FLAG) = 0 Then
        rc = SQLITE_READONLY
    End If
    If rc = SQLITE_OK AndAlso pCursor->eState = CURSOR_FAULT Then rc = pCursor->skipNext
    If rc = SQLITE_OK AndAlso pCursor->eState >= CURSOR_REQUIRESEEK Then
        Dim ignoredLocation As SQLITE_C_INT = 0
        rc = btreeCursorRestoreInternal(pCursor, @ignoredLocation)
    End If
    If rc = SQLITE_OK AndAlso (pCursor->eState <> CURSOR_VALID OrElse _
       pCursor->pPage = 0 OrElse pCursor->iPage < 0) Then rc = SQLITE_CORRUPT

    If rc = SQLITE_OK Then
        originalDepth = pCursor->iPage
        originalCellIndex = pCursor->ix
        pPage = pCursor->pPage
        If pPage->nCell <= originalCellIndex Then
            rc = SQLITE_CORRUPT
        Else
            pCell = btreeCursorCell(pPage, originalCellIndex)
            If pCell = 0 Then
                rc = SQLITE_CORRUPT
            Else
                rc = sqlite3BtreeGetCellInfo(pPage, originalCellIndex, @savedCellInfo)
            End If
        End If
    End If
    If rc = SQLITE_OK AndAlso pPage->nFree < 0 Then rc = sqlite3BtreeComputeFreeSpace(pPage)
    If rc = SQLITE_OK AndAlso btreePageHasRange(pPage, pCell, savedCellInfo.nSize) = 0 Then rc = SQLITE_CORRUPT

    If rc = SQLITE_OK AndAlso preservePosition <> 0 Then
        Dim willRebalance As SQLITE_C_INT = 0
        If pPage->leaf = 0 OrElse pPage->nCell = 1 OrElse _
           CULng(pPage->nFree) + savedCellInfo.nSize + 2 > _
               (CULng(pBt->usableSize) * 2) \ 3 Then
            willRebalance = 1
        End If
        If willRebalance <> 0 Then
            rc = btreeSaveCursorKey(pCursor)
        Else
            preservePosition = 2
        End If
    End If

    If rc = SQLITE_OK AndAlso pPage->leaf = 0 Then
        rc = btreeCursorPreviousInternal(pCursor)
        If rc = SQLITE_DONE Then rc = SQLITE_CORRUPT
    End If
    If rc = SQLITE_OK AndAlso (pCursor->curFlags And BTCF_MULTIPLE) <> 0 Then
        rc = btreeSaveAllCursors(pBt, pCursor->pgnoRoot, pCursor)
    End If
    If rc = SQLITE_OK AndAlso pCursor->pKeyInfo = 0 AndAlso pBtree->hasIncrblobCur <> 0 Then
        invalidateIncrblobCursors(pBtree, pCursor->pgnoRoot, savedCellInfo.nKey, 0)
    End If

    If rc = SQLITE_OK Then rc = sqlite3PagerWrite(pPage->pDbPage)
    If rc = SQLITE_OK Then
        rc = btreeClearCellOverflow(pPage, pCell, @savedCellInfo)
        If rc = SQLITE_OK Then changed = 1
    End If
    If rc = SQLITE_OK Then
        rc = sqlite3BtreeDropCell(pPage, originalCellIndex)
        If rc = SQLITE_OK Then changed = 1
    End If

    If rc = SQLITE_OK AndAlso pPage->leaf = 0 Then
        Dim pLeaf As MemPage Ptr = pCursor->pPage
        Dim childPage As u32 = 0
        If pLeaf = 0 OrElse pLeaf->leaf = 0 OrElse pLeaf->nCell = 0 OrElse _
           pCursor->iPage <= originalDepth Then
            rc = SQLITE_CORRUPT
        ElseIf originalDepth < pCursor->iPage - 1 Then
            Dim pChild As MemPage Ptr = pCursor->apPage(originalDepth + 1)
            If pChild = 0 Then
                rc = SQLITE_CORRUPT
            Else
                childPage = pChild->pgno
            End If
        Else
            childPage = pLeaf->pgno
        End If

        If rc = SQLITE_OK AndAlso (pPage->intKey <> 0 OrElse pLeaf->intKey <> 0 OrElse _
           pBt->pTmpSpace = 0) Then rc = SQLITE_CORRUPT
        If rc = SQLITE_OK AndAlso pLeaf->nFree < 0 Then rc = sqlite3BtreeComputeFreeSpace(pLeaf)
        If rc = SQLITE_OK Then
            Dim leafCellIndex As SQLITE_C_INT = pLeaf->nCell - 1
            Dim pLeafCell As UByte Ptr = btreeCursorCell(pLeaf, leafCellIndex)
            If pLeafCell = 0 Then
                rc = SQLITE_CORRUPT
            Else
                Dim leafCellSize As u16 = sqlite3BtreeCellSize(pLeaf, pLeafCell)
                Dim padCorrection As SQLITE_C_INT = IIf(pLeafCell[0] = 2, 1, 0)
                If leafCellSize < padCorrection OrElse leafCellSize < 4 Then
                    rc = SQLITE_CORRUPT
                Else
                    Dim dividerSize As SQLITE_C_INT = 4 + leafCellSize - padCorrection
                    If dividerSize > pBt->pageSize OrElse dividerSize > 65535 Then
                        rc = SQLITE_CORRUPT
                    Else
                        Dim pDivider As UByte Ptr = pBt->pTmpSpace
                        btreeWriteU32(pDivider, 0)
                        btreeSystemMemcpy(pDivider + 4, pLeafCell, CULngInt(leafCellSize - padCorrection))
                        rc = btreeInsertCellWithChild(pPage, originalCellIndex, pDivider, _
                                                      dividerSize, childPage)
                        If rc = SQLITE_OK Then
                            changed = 1
                            rc = sqlite3BtreeDropCell(pLeaf, leafCellIndex)
                            If rc = SQLITE_OK Then changed = 1
                        End If
                    End If
                End If
            End If
        End If
    End If

    If rc = SQLITE_OK Then
        Dim pBalancePage As MemPage Ptr = pCursor->pPage
        If pBalancePage = 0 Then
            rc = SQLITE_CORRUPT
        ElseIf pBalancePage->nFree < 0 Then
            rc = sqlite3BtreeComputeFreeSpace(pBalancePage)
        End If
        If rc = SQLITE_OK AndAlso (pBalancePage->nOverflow <> 0 OrElse _
           CULng(pBalancePage->nFree) * 3 > CULng(pBt->usableSize) * 2) Then
            rc = btreeBalanceCursor(pCursor)
        End If

        If rc = SQLITE_OK AndAlso pCursor->iPage > originalDepth Then
            sqlite3BtreeReleasePage(pCursor->pPage)
            pCursor->iPage -= 1
            While pCursor->iPage > originalDepth
                sqlite3BtreeReleasePage(pCursor->apPage(pCursor->iPage))
                pCursor->iPage -= 1
            Wend
            pCursor->pPage = pCursor->apPage(pCursor->iPage)
            pCursor->ix = pCursor->aiIdx(pCursor->iPage)
            If pCursor->pPage = 0 Then
                rc = SQLITE_CORRUPT
            ElseIf pCursor->pPage->nFree < 0 Then
                rc = sqlite3BtreeComputeFreeSpace(pCursor->pPage)
            End If
            If rc = SQLITE_OK AndAlso (pCursor->pPage->nOverflow <> 0 OrElse _
               CULng(pCursor->pPage->nFree) * 3 > CULng(pBt->usableSize) * 2) Then
                rc = btreeBalanceCursor(pCursor)
            End If
        End If
    End If

    If rc = SQLITE_OK Then
        If preservePosition = 2 Then
            If pCursor->iPage <> originalDepth OrElse pCursor->pPage <> pPage OrElse _
               pPage->nCell = 0 OrElse originalCellIndex > pPage->nCell Then
                rc = SQLITE_CORRUPT
            Else
                btreeCursorClearCellInfo(pCursor)
                pCursor->eState = CURSOR_SKIPNEXT
                If originalCellIndex >= pPage->nCell Then
                    pCursor->skipNext = -1
                    pCursor->ix = pPage->nCell - 1
                Else
                    pCursor->skipNext = 1
                    pCursor->ix = originalCellIndex
                End If
            End If
        ElseIf preservePosition = 1 Then
            btreeReleaseAllCursorPages(pCursor)
            pCursor->eState = CURSOR_REQUIRESEEK
        Else
            Dim rootResult As SQLITE_C_INT = btreeMoveToRoot(pCursor)
            If rootResult = SQLITE_EMPTY Then rootResult = SQLITE_OK
            If rootResult <> SQLITE_OK Then rc = rootResult
        End If
    End If

    If rc <> SQLITE_OK AndAlso changed <> 0 Then
        btreeReleaseAllCursorPages(pCursor)
        pCursor->eState = CURSOR_INVALID
    End If
    If rc <> SQLITE_OK AndAlso pCursor->pKey <> 0 Then
        If pCursor->eState = CURSOR_VALID Then btreeReleaseAllCursorPages(pCursor)
        If pCursor->eState <> CURSOR_REQUIRESEEK Then sqlite3_free(pCursor->pKey)
        If pCursor->eState <> CURSOR_REQUIRESEEK Then pCursor->pKey = 0
    End If
    Return rc
End Function

Function sqlite3BtreeIntegerKey CDecl Alias "sqlite3BtreeIntegerKey" (ByVal pCursor As BtCursor Ptr) As i64 Export
    If pCursor = 0 OrElse pCursor->pBt = 0 Then Return 0
    Dim rc As SQLITE_C_INT = getCellInfo(pCursor)
    Dim keyValue As i64 = 0
    If rc = SQLITE_OK Then keyValue = pCursor->info.nKey
    Return keyValue
End Function

Function sqlite3BtreePayloadSize CDecl Alias "sqlite3BtreePayloadSize" (ByVal pCursor As BtCursor Ptr) As u32 Export
    If pCursor = 0 OrElse pCursor->pBt = 0 Then Return 0
    Dim rc As SQLITE_C_INT = getCellInfo(pCursor)
    Dim payloadSize As u32 = 0
    If rc = SQLITE_OK Then payloadSize = pCursor->info.nPayload
    Return payloadSize
End Function

Private Function btreeAccessPayload( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal offset As u32, _
    ByVal amount As u32, _
    ByVal pBuffer As Any Ptr _
) As SQLITE_C_INT

    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pBuffer = 0 AndAlso amount > 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = getCellInfo(pCursor)
    If rc <> SQLITE_OK Then Return rc
    Dim pInfo As CellInfo Ptr = @pCursor->info
    If CULngInt(offset) + amount > pInfo->nPayload Then Return SQLITE_CORRUPT
    If amount = 0 Then Return SQLITE_OK

    Dim pOutput As UByte Ptr = CPtr(UByte Ptr, pBuffer)
    Dim remaining As u32 = amount
    Dim currentOffset As u32 = offset
    If currentOffset < pInfo->nLocal Then
        Dim localAmount As u32 = pInfo->nLocal - currentOffset
        If localAmount > remaining Then localAmount = remaining
        If pInfo->pPayload = 0 Then Return SQLITE_CORRUPT
        btreeSystemMemcpy(pOutput, pInfo->pPayload + currentOffset, CULngInt(localAmount))
        pOutput += localAmount
        currentOffset += localAmount
        remaining -= localAmount
    End If
    If remaining = 0 Then Return SQLITE_OK

    Dim pCell As UByte Ptr = btreeCursorCell(pCursor->pPage, pCursor->ix)
    If pCell = 0 OrElse pInfo->nSize < 4 OrElse pInfo->nLocal >= pInfo->nPayload Then Return SQLITE_CORRUPT
    Dim overflowPage As u32 = btreeReadU32(pCell + pInfo->nSize - 4)
    Dim overflowPayloadSize As u32 = pCursor->pBt->usableSize - 4
    If overflowPayloadSize = 0 Then Return SQLITE_CORRUPT
    Dim overflowOffset As sqlite3_uint64 = CULngInt(currentOffset - pInfo->nLocal)
    Dim pageIndex As sqlite3_uint64 = overflowOffset \ overflowPayloadSize
    Dim pageOffset As u32 = CULng(overflowOffset Mod overflowPayloadSize)
    If pageIndex >= pCursor->pBt->nPage Then Return SQLITE_CORRUPT
    Dim pagesVisited As sqlite3_uint64 = 0

    For iPage As sqlite3_uint64 = 0 To pageIndex
        If overflowPage = 0 OrElse overflowPage > pCursor->pBt->nPage Then Return SQLITE_CORRUPT
        Dim pOverflow As MemPage Ptr = 0
        rc = btreeGetPage(pCursor->pBt, overflowPage, @pOverflow, pCursor->curPagerFlags)
        If rc <> SQLITE_OK Then Return rc
        If pOverflow = 0 OrElse pOverflow->aData = 0 Then
            If pOverflow <> 0 Then sqlite3BtreeReleasePage(pOverflow)
            Return SQLITE_CORRUPT
        End If
        pagesVisited += 1
        Dim nextPage As u32 = btreeReadU32(pOverflow->aData)
        If iPage < pageIndex Then
            ' Keep pageOffset for the target page while walking the chain.
            sqlite3BtreeReleasePage(pOverflow)
            overflowPage = nextPage
            Continue For
        End If

        While remaining > 0
            If pageOffset >= overflowPayloadSize Then
                sqlite3BtreeReleasePage(pOverflow)
                overflowPage = nextPage
                pageOffset = 0
                If pagesVisited >= pCursor->pBt->nPage Then Return SQLITE_CORRUPT
                If overflowPage = 0 OrElse overflowPage > pCursor->pBt->nPage Then Return SQLITE_CORRUPT
                rc = btreeGetPage(pCursor->pBt, overflowPage, @pOverflow, pCursor->curPagerFlags)
                If rc <> SQLITE_OK Then Return rc
                If pOverflow = 0 OrElse pOverflow->aData = 0 Then
                    If pOverflow <> 0 Then sqlite3BtreeReleasePage(pOverflow)
                    Return SQLITE_CORRUPT
                End If
                pagesVisited += 1
                nextPage = btreeReadU32(pOverflow->aData)
            End If
            Dim copyAmount As u32 = overflowPayloadSize - pageOffset
            If copyAmount > remaining Then copyAmount = remaining
            btreeSystemMemcpy(pOutput, pOverflow->aData + 4 + pageOffset, CULngInt(copyAmount))
            pOutput += copyAmount
            remaining -= copyAmount
            pageOffset += copyAmount
        Wend
        sqlite3BtreeReleasePage(pOverflow)
        Return SQLITE_OK
    Next
    Return SQLITE_CORRUPT
End Function

Private Function btreeWritePayloadRange( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal offset As u32, _
    ByVal amount As u32, _
    ByVal pBuffer As Any Ptr _
) As SQLITE_C_INT

    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pBuffer = 0 AndAlso amount <> 0 Then Return SQLITE_MISUSE
    If amount = 0 Then Return SQLITE_OK
    If amount > &H7FFFFFFF Then Return SQLITE_TOOBIG
    Dim rc As SQLITE_C_INT = getCellInfo(pCursor)
    If rc <> SQLITE_OK Then Return rc
    Dim pInfo As CellInfo Ptr = @pCursor->info
    If CULngInt(offset) + amount > pInfo->nPayload OrElse _
       pInfo->nLocal > pInfo->nPayload Then Return SQLITE_CORRUPT

    Dim writePayload As SqliteBtreePayload
    writePayload.pKey = 0
    writePayload.nKey = 0
    writePayload.pData = pBuffer
    writePayload.aMem = 0
    writePayload.nMem = 0
    writePayload.nData = CLng(amount)
    writePayload.nZero = 0

    Dim sourceOffset As SQLITE_C_INT = 0
    Dim remaining As u32 = amount
    Dim currentOffset As sqlite3_uint64 = offset
    If currentOffset < pInfo->nLocal Then
        Dim localAmount As u32 = pInfo->nLocal - CULng(currentOffset)
        If localAmount > remaining Then localAmount = remaining
        rc = btreeOverwriteContent(pCursor->pPage, pInfo->pPayload + currentOffset, _
                                   @writePayload, sourceOffset, localAmount)
        If rc <> SQLITE_OK Then Return rc
        sourceOffset += localAmount
        remaining -= localAmount
        currentOffset += localAmount
    End If
    If remaining = 0 Then Return SQLITE_OK
    If pInfo->nSize < 4 OrElse pInfo->nLocal >= pInfo->nPayload OrElse _
       pCursor->pBt->usableSize <= 4 Then Return SQLITE_CORRUPT

    Dim overflowCapacity As u32 = pCursor->pBt->usableSize - 4
    Dim overflowBytes As sqlite3_uint64 = pInfo->nPayload - pInfo->nLocal
    Dim overflowPageCount As sqlite3_uint64 = (overflowBytes + overflowCapacity - 1) \ overflowCapacity
    Dim overflowOffset As sqlite3_uint64 = currentOffset - pInfo->nLocal
    Dim pagesToSkip As sqlite3_uint64 = overflowOffset \ overflowCapacity
    Dim pageOffset As u32 = CULng(overflowOffset Mod overflowCapacity)
    If overflowPageCount = 0 OrElse pagesToSkip >= overflowPageCount Then Return SQLITE_CORRUPT

    Dim pCell As UByte Ptr = btreeCursorCell(pCursor->pPage, pCursor->ix)
    If pCell = 0 OrElse btreePageHasRange(pCursor->pPage, pCell, pInfo->nSize) = 0 Then Return SQLITE_CORRUPT
    Dim pageNumber As u32 = btreeReadU32(pCell + pInfo->nSize - 4)
    While pagesToSkip > 0
        If pageNumber < 2 OrElse pageNumber > pCursor->pBt->nPage Then Return SQLITE_CORRUPT
        Dim pOverflow As MemPage Ptr = 0
        rc = btreeGetPage(pCursor->pBt, pageNumber, @pOverflow, 0)
        If rc <> SQLITE_OK Then Return rc
        If pOverflow = 0 OrElse pOverflow->aData = 0 Then
            sqlite3BtreeReleasePage(pOverflow)
            Return SQLITE_CORRUPT
        End If
        Dim nextPage As u32 = btreeReadU32(pOverflow->aData)
        sqlite3BtreeReleasePage(pOverflow)
        If nextPage < 2 OrElse nextPage > pCursor->pBt->nPage Then Return SQLITE_CORRUPT
        pageNumber = nextPage
        pagesToSkip -= 1
    Wend

    Dim pageIndex As sqlite3_uint64 = overflowOffset \ overflowCapacity
    While remaining > 0
        If pageNumber < 2 OrElse pageNumber > pCursor->pBt->nPage OrElse _
           pageIndex >= overflowPageCount Then Return SQLITE_CORRUPT
        Dim pOverflow As MemPage Ptr = 0
        rc = btreeGetPage(pCursor->pBt, pageNumber, @pOverflow, 0)
        If rc <> SQLITE_OK Then Return rc
        If pOverflow = 0 OrElse pOverflow->aData = 0 OrElse pOverflow->pDbPage = 0 Then
            sqlite3BtreeReleasePage(pOverflow)
            Return SQLITE_CORRUPT
        End If
        Dim copyAmount As u32 = overflowCapacity - pageOffset
        If copyAmount > remaining Then copyAmount = remaining
        rc = btreeOverwriteContent(pOverflow, pOverflow->aData + 4 + pageOffset, _
                                   @writePayload, sourceOffset, copyAmount)
        Dim nextPage As u32 = 0
        If rc = SQLITE_OK AndAlso remaining > copyAmount Then
            nextPage = btreeReadU32(pOverflow->aData)
            If nextPage < 2 OrElse nextPage > pCursor->pBt->nPage Then rc = SQLITE_CORRUPT
        End If
        sqlite3BtreeReleasePage(pOverflow)
        If rc <> SQLITE_OK Then Return rc
        remaining -= copyAmount
        sourceOffset += copyAmount
        pageIndex += 1
        pageOffset = 0
        pageNumber = nextPage
    Wend
    Return SQLITE_OK
End Function

' The caller holds pBt->mutex while restoring cursor state and reading bytes.
Private Function accessPayloadChecked CDecl Alias "accessPayloadChecked" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal offset As u32, _
    ByVal amount As u32, _
    ByVal pBuffer As Any Ptr _
) As SQLITE_C_INT

    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pBuffer = 0 AndAlso amount <> 0 Then Return SQLITE_MISUSE
    If pCursor->eState = CURSOR_INVALID Then Return SQLITE_ABORT
    If pCursor->eState = CURSOR_FAULT Then Return pCursor->skipNext

    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pCursor->eState = CURSOR_REQUIRESEEK Then
        rc = btreeRestoreCursorPosition(pCursor)
    ElseIf pCursor->eState = CURSOR_SKIPNEXT Then
        pCursor->eState = CURSOR_VALID
        pCursor->skipNext = 0
    End If
    If rc = SQLITE_OK AndAlso pCursor->eState <> CURSOR_VALID Then rc = SQLITE_ABORT
    If rc = SQLITE_OK Then rc = btreeAccessPayload(pCursor, offset, amount, pBuffer)
    Return rc
End Function

Function sqlite3BtreePayloadChecked CDecl Alias "sqlite3BtreePayloadChecked" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal offset As u32, _
    ByVal amount As u32, _
    ByVal pBuffer As Any Ptr _
) As SQLITE_C_INT Export
    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pBuffer = 0 AndAlso amount <> 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT
    If pCursor->eState = CURSOR_VALID Then
        rc = btreeAccessPayload(pCursor, offset, amount, pBuffer)
    Else
        rc = accessPayloadChecked(pCursor, offset, amount, pBuffer)
    End If
    Return rc
End Function

Function sqlite3BtreePutData CDecl Alias "sqlite3BtreePutData" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal offset As u32, _
    ByVal amount As u32, _
    ByVal pBuffer As Any Ptr _
) As SQLITE_C_INT Export
    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pCursor->pBtree = 0 OrElse _
       pBuffer = 0 AndAlso amount <> 0 Then Return SQLITE_MISUSE
    If amount > &H7FFFFFFF Then Return SQLITE_TOOBIG
    Dim pBt As BtShared Ptr = pCursor->pBt
    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pCursor->eState = CURSOR_INVALID Then
        rc = SQLITE_ABORT
    ElseIf pCursor->eState = CURSOR_FAULT Then
        rc = pCursor->skipNext
    ElseIf pCursor->eState = CURSOR_REQUIRESEEK Then
        Dim ignoredLocation As SQLITE_C_INT = 0
        rc = btreeCursorRestoreInternal(pCursor, @ignoredLocation)
    ElseIf pCursor->eState = CURSOR_SKIPNEXT Then
        pCursor->eState = CURSOR_VALID
        pCursor->skipNext = 0
    End If
    If rc = SQLITE_OK AndAlso pCursor->eState <> CURSOR_VALID Then rc = SQLITE_ABORT
    If rc = SQLITE_OK AndAlso (pCursor->pKeyInfo <> 0 OrElse pCursor->pPage = 0 OrElse _
       pCursor->pPage->intKey = 0 OrElse (pCursor->curFlags And BTCF_WRITE_FLAG) = 0 OrElse _
       pCursor->pBtree->inTrans <> TRANS_WRITE) Then rc = SQLITE_READONLY
    If rc = SQLITE_OK AndAlso (pCursor->curFlags And BTCF_INCRBLOB) = 0 Then rc = SQLITE_MISUSE
    If rc = SQLITE_OK AndAlso (pCursor->curFlags And BTCF_MULTIPLE) <> 0 Then
        rc = btreeSaveAllCursors(pBt, pCursor->pgnoRoot, pCursor)
    End If
    If rc = SQLITE_OK Then rc = btreeWritePayloadRange(pCursor, offset, amount, pBuffer)
    Return rc
End Function

Sub sqlite3BtreeIncrblobCursor CDecl Alias "sqlite3BtreeIncrblobCursor" (ByVal pCursor As BtCursor Ptr) Export
    If pCursor = 0 OrElse pCursor->pBtree = 0 Then Exit Sub
    pCursor->curFlags = pCursor->curFlags Or BTCF_INCRBLOB
    pCursor->pBtree->hasIncrblobCur = 1
End Sub

Function sqlite3BtreePayload CDecl Alias "sqlite3BtreePayload" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal offset As u32, _
    ByVal amount As u32, _
    ByVal pBuffer As Any Ptr _
) As SQLITE_C_INT Export
    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pCursor->eState <> CURSOR_VALID Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = btreeAccessPayload(pCursor, offset, amount, pBuffer)
    Return rc
End Function

Function sqlite3BtreePayloadFetch CDecl Alias "sqlite3BtreePayloadFetch" ( _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pAmount As u32 Ptr _
) As Const Any Ptr Export
    If pAmount <> 0 Then pAmount[0] = 0
    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pAmount = 0 OrElse _
       pCursor->eState <> CURSOR_VALID Then Return 0
    Dim rc As SQLITE_C_INT = getCellInfo(pCursor)
    Dim pResult As Const Any Ptr = 0
    If rc = SQLITE_OK AndAlso pCursor->pPage <> 0 AndAlso pCursor->info.pPayload <> 0 Then
        Dim pageStart As sqlite3_uint64 = CULngInt(pCursor->pPage->aData)
        Dim pageEnd As sqlite3_uint64 = pageStart + pCursor->pBt->usableSize
        Dim payloadStart As sqlite3_uint64 = CULngInt(pCursor->info.pPayload)
        If payloadStart >= pageStart AndAlso payloadStart <= pageEnd Then
            Dim available As sqlite3_uint64 = pageEnd - payloadStart
            If available > pCursor->info.nLocal Then available = pCursor->info.nLocal
            pAmount[0] = CULng(available)
            If available > 0 Then pResult = pCursor->info.pPayload
        End If
    End If
    Return pResult
End Function

Function sqlite3BtreeOffset CDecl Alias "sqlite3BtreeOffset" (ByVal pCursor As BtCursor Ptr) As i64 Export
    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pCursor->eState <> CURSOR_VALID Then Return 0
    Dim result As i64 = 0
    If getCellInfo(pCursor) = SQLITE_OK AndAlso pCursor->pPage <> 0 AndAlso _
       pCursor->info.pPayload <> 0 Then
        Dim pageNumberOffset As i64 = (CLngInt(pCursor->pPage->pgno) - 1) * pCursor->pBt->pageSize
        result = pageNumberOffset + (pCursor->info.pPayload - pCursor->pPage->aData)
    End If
    Return result
End Function

Function sqlite3BtreeMaxRecordSize CDecl Alias "sqlite3BtreeMaxRecordSize" (ByVal pCursor As BtCursor Ptr) As i64 Export
    If pCursor = 0 OrElse pCursor->pBt = 0 Then Return 0
    Dim result As i64 = CLngInt(pCursor->pBt->pageSize) * pCursor->pBt->nPage
    Return result
End Function

Function sqlite3BtreeCount CDecl Alias "sqlite3BtreeCount" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pCursor As BtCursor Ptr, _
    ByVal pEntryCount As i64 Ptr _
) As SQLITE_C_INT Export

    If pCursor = 0 OrElse pCursor->pBt = 0 OrElse pCursor->pBtree = 0 OrElse _
       pEntryCount = 0 OrElse (db <> 0 AndAlso pCursor->pBtree->db <> db) Then Return SQLITE_MISUSE
    pEntryCount[0] = 0
    Dim pBt As BtShared Ptr = pCursor->pBt
    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim entryCount As i64 = 0
    Dim emptyTree As SQLITE_C_INT = 0
    If pCursor->eState = CURSOR_FAULT Then
        rc = pCursor->skipNext
    ElseIf pCursor->eState = CURSOR_REQUIRESEEK Then
        Dim ignoredLocation As SQLITE_C_INT = 0
        rc = btreeCursorRestoreInternal(pCursor, @ignoredLocation)
    End If
    If rc = SQLITE_OK Then rc = btreeMoveToRoot(pCursor)
    If rc = SQLITE_EMPTY Then
        pEntryCount[0] = 0
        rc = SQLITE_OK
        emptyTree = 1
    End If

    Do While rc = SQLITE_OK AndAlso emptyTree = 0
        Dim pPage As MemPage Ptr = pCursor->pPage
        If pPage = 0 OrElse pPage->nCell = 0 Then
            rc = SQLITE_CORRUPT
            Exit Do
        End If
        If pPage->leaf <> 0 OrElse pPage->intKey = 0 Then
            entryCount += pPage->nCell
        End If

        If pPage->leaf <> 0 Then
            Dim finished As SQLITE_C_INT = 0
            Do
                If pCursor->iPage = 0 Then
                    pEntryCount[0] = entryCount
                    rc = btreeMoveToRoot(pCursor)
                    If rc = SQLITE_EMPTY Then rc = SQLITE_OK
                    finished = 1
                    Exit Do
                End If
                btreeMoveToParent(pCursor)
                If pCursor->pPage = 0 Then
                    rc = SQLITE_CORRUPT
                    Exit Do
                End If
            Loop While pCursor->ix >= pCursor->pPage->nCell
            If rc <> SQLITE_OK OrElse finished <> 0 Then Exit Do
            pCursor->ix += 1
            pPage = pCursor->pPage
        End If

        Dim childIndex As SQLITE_C_INT = pCursor->ix
        Dim childPage As u32 = 0
        If childIndex = pPage->nCell Then
            childPage = btreeReadU32(pPage->aData + pPage->hdrOffset + 8)
        ElseIf childIndex < pPage->nCell Then
            Dim pCell As UByte Ptr = btreeCursorCell(pPage, childIndex)
            If pCell = 0 Then
                rc = SQLITE_CORRUPT
                Exit Do
            End If
            childPage = btreeReadU32(pCell)
        Else
            rc = SQLITE_CORRUPT
            Exit Do
        End If
        rc = btreeMoveToChild(pCursor, childPage)
    Loop
    Return rc
End Function

Function sqlite3BtreeRowCountEst CDecl Alias "sqlite3BtreeRowCountEst" (ByVal pCursor As BtCursor Ptr) As i64 Export
    If pCursor = 0 OrElse pCursor->eState <> CURSOR_VALID OrElse pCursor->pPage = 0 Then Return 0
    If pCursor->pPage->leaf = 0 Then Return -1
    Dim estimate As i64 = pCursor->pPage->nCell
    For pageIndex As SQLITE_C_INT = 0 To pCursor->iPage - 1
        Dim pParent As MemPage Ptr = pCursor->apPage(pageIndex)
        If pParent = 0 Then Return 0
        Dim branchCount As i64 = pParent->nCell + 1
        If estimate > &H7FFFFFFFFFFFFFFF \ branchCount Then Return &H7FFFFFFFFFFFFFFF
        estimate *= branchCount
    Next
    Return estimate
End Function

#ifndef SQLITE_OMIT_WAL
' Keep B-tree transaction ownership visible while the pager performs a checkpoint.
Function sqlite3BtreeCheckpoint CDecl Alias "sqlite3BtreeCheckpoint" ( _
    ByVal pBtree As Btree Ptr, _
    ByVal mode As SQLITE_C_INT, _
    ByVal pLogFrames As SQLITE_C_INT Ptr, _
    ByVal pCheckpointedFrames As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    Dim resultCode As SQLITE_C_INT = SQLITE_OK
    If pBtree = 0 Then Return resultCode

    Dim pShared As BtShared Ptr = pBtree->pBt
    sqlite3BtreeEnter(pBtree)
    If pShared->inTransaction <> TRANS_NONE Then
        resultCode = SQLITE_LOCKED
    Else
        resultCode = sqlite3PagerCheckpoint( _
            pShared->pPager, pBtree->db, mode, pLogFrames, pCheckpointedFrames)
    End If
    sqlite3BtreeLeave(pBtree)
    Return resultCode
End Function
#endif

Function sqlite3BtreeSeekCount CDecl Alias "sqlite3BtreeSeekCount" ( _
    ByVal pBtree As Btree Ptr _
) As sqlite3_uint64
#ifdef SQLITE_DEBUG
    If pBtree = 0 Then Return 0
    Dim seekCount As sqlite3_uint64 = pBtree->nSeek
    pBtree->nSeek = 0
    Return seekCount
#else
    Return 0
#endif
End Function

/' end of sqlite3_btree.bas '/
