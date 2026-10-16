/'
    Project: SQLite FreeBASIC port

    File: sqlite3_rowset.bas

    Purpose:

        Port the RowSet data structure from src/rowset.c.

    Responsibilities:

        - Collect rowids in insertion batches and test prior batches.
        - Sort, deduplicate, and return rowids in ascending order.
        - Allocate entries in connection-owned chunks and honor latched OOM.
        - Rely on the caller to serialize operations on each connection.

    This file intentionally does NOT contain:

        - VDBE opcodes that create and consume RowSet objects.
        - Debug output or test-fixture commands.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_rowset.bi"

Private Const ROWSET_ALLOCATION_SIZE As Long = 1024
Private Const ROWSET_SORT_BUCKETS As Long = 40
Private Const ROWSET_SORTED As UShort = &H01
Private Const ROWSET_NEXT As UShort = &H02

Private Type RowSetEntry
    v As i64
    pRight As RowSetEntry Ptr
    pLeft As RowSetEntry Ptr
End Type

Private Const ROWSET_ENTRY_PER_CHUNK As Long = _
    (ROWSET_ALLOCATION_SIZE - 8) \ SizeOf(RowSetEntry)

Private Type RowSetChunk
    pNextChunk As RowSetChunk Ptr
    aEntry(0 To ROWSET_ENTRY_PER_CHUNK - 1) As RowSetEntry
End Type

Private Type RowSet
    pChunk As RowSetChunk Ptr
    db As sqlite3 Ptr
    pEntry As RowSetEntry Ptr
    pLast As RowSetEntry Ptr
    pFresh As RowSetEntry Ptr
    pForest As RowSetEntry Ptr
    nFresh As UShort
    rsFlags As UShort
    iBatch As SQLITE_C_INT
End Type

/' ------------------------------------------------------------------------- '/
/' Chunk-backed entry storage '/
/' ------------------------------------------------------------------------- '/

Private Function rowSetEntryAlloc(ByVal p As RowSet Ptr) As RowSetEntry Ptr
    If p = 0 Then Return 0

    If p->nFresh = 0 Then
        Dim pNew As RowSetChunk Ptr = CPtr(RowSetChunk Ptr, _
            sqlite3DbMallocRawNN(p->db, SizeOf(RowSetChunk)))
        If pNew = 0 Then Return 0
        pNew->pNextChunk = p->pChunk
        p->pChunk = pNew
        p->pFresh = @pNew->aEntry(0)
        p->nFresh = CUInt(ROWSET_ENTRY_PER_CHUNK)
    End If

    p->nFresh -= 1
    Dim pEntry As RowSetEntry Ptr = p->pFresh
    p->pFresh += 1
    Return pEntry
End Function

/' ------------------------------------------------------------------------- '/
/' Sorting and balanced tree conversion '/
/' ------------------------------------------------------------------------- '/

Private Function rowSetEntryMerge( _
    ByVal pAStart As RowSetEntry Ptr, _
    ByVal pBStart As RowSetEntry Ptr _
) As RowSetEntry Ptr

    If pAStart = 0 Then Return pBStart
    If pBStart = 0 Then Return pAStart

    Dim head As RowSetEntry
    head.pRight = 0
    Dim pTail As RowSetEntry Ptr = @head
    Dim pA As RowSetEntry Ptr = pAStart
    Dim pB As RowSetEntry Ptr = pBStart

    Do
        If pA->v <= pB->v Then
            If pA->v < pB->v Then
                pTail->pRight = pA
                pTail = pA
            End If
            pA = pA->pRight
            If pA = 0 Then
                pTail->pRight = pB
                Exit Do
            End If
        Else
            pTail->pRight = pB
            pTail = pB
            pB = pB->pRight
            If pB = 0 Then
                pTail->pRight = pA
                Exit Do
            End If
        End If
    Loop

    Return head.pRight
End Function

Private Function rowSetEntrySort(ByVal pInput As RowSetEntry Ptr) As RowSetEntry Ptr
    Dim buckets(0 To ROWSET_SORT_BUCKETS - 1) As RowSetEntry Ptr
    For i As Long = 0 To ROWSET_SORT_BUCKETS - 1
        buckets(i) = 0
    Next

    While pInput <> 0
        Dim pNext As RowSetEntry Ptr = pInput->pRight
        pInput->pRight = 0
        Dim iBucket As Long = 0
        While iBucket < ROWSET_SORT_BUCKETS AndAlso buckets(iBucket) <> 0
            pInput = rowSetEntryMerge(buckets(iBucket), pInput)
            buckets(iBucket) = 0
            iBucket += 1
        Wend

        ' Fall back to pairwise merges before the fixed merge stack could
        ' overflow, preserving all entries even on unusually large systems.
        If iBucket >= ROWSET_SORT_BUCKETS Then
            While pNext <> 0
                Dim pFollowing As RowSetEntry Ptr = pNext->pRight
                pNext->pRight = 0
                pInput = rowSetEntryMerge(pInput, pNext)
                pNext = pFollowing
            Wend
            Return pInput
        End If
        buckets(iBucket) = pInput
        pInput = pNext
    Wend

    pInput = buckets(0)
    For i As Long = 1 To ROWSET_SORT_BUCKETS - 1
        If buckets(i) <> 0 Then
            If pInput = 0 Then
                pInput = buckets(i)
            Else
                pInput = rowSetEntryMerge(pInput, buckets(i))
            End If
        End If
    Next
    Return pInput
End Function

Private Sub rowSetTreeToList( _
    ByVal pInput As RowSetEntry Ptr, _
    ByRef pFirst As RowSetEntry Ptr, _
    ByRef pLast As RowSetEntry Ptr _
)
    If pInput = 0 Then
        pFirst = 0
        pLast = 0
        Exit Sub
    End If

    If pInput->pLeft <> 0 Then
        Dim pLeftTail As RowSetEntry Ptr = 0
        rowSetTreeToList(pInput->pLeft, pFirst, pLeftTail)
        If pLeftTail <> 0 Then pLeftTail->pRight = pInput
    Else
        pFirst = pInput
    End If

    If pInput->pRight <> 0 Then
        Dim pRightHead As RowSetEntry Ptr = pInput->pRight
        rowSetTreeToList(pRightHead, pRightHead, pLast)
        pInput->pRight = pRightHead
    Else
        pLast = pInput
    End If
End Sub

Private Function rowSetNDeepTree( _
    ByRef pList As RowSetEntry Ptr, _
    ByVal depth As SQLITE_C_INT _
) As RowSetEntry Ptr

    If pList = 0 Then Return 0

    Dim p As RowSetEntry Ptr
    If depth > 1 Then
        Dim pLeft As RowSetEntry Ptr = rowSetNDeepTree(pList, depth - 1)
        p = pList
        If p = 0 Then Return pLeft
        p->pLeft = pLeft
        pList = p->pRight
        p->pRight = rowSetNDeepTree(pList, depth - 1)
    Else
        p = pList
        pList = p->pRight
        p->pLeft = 0
        p->pRight = 0
    End If
    Return p
End Function

Private Function rowSetListToTree(ByVal pListStart As RowSetEntry Ptr) As RowSetEntry Ptr
    If pListStart = 0 Then Return 0

    Dim p As RowSetEntry Ptr = pListStart
    Dim pList As RowSetEntry Ptr = p->pRight
    p->pLeft = 0
    p->pRight = 0
    Dim depth As SQLITE_C_INT = 1

    While pList <> 0
        Dim pLeft As RowSetEntry Ptr = p
        p = pList
        pList = p->pRight
        p->pLeft = pLeft
        p->pRight = rowSetNDeepTree(pList, depth)
        depth += 1
    Wend
    Return p
End Function

/' ------------------------------------------------------------------------- '/
/' RowSet C ABI '/
/' ------------------------------------------------------------------------- '/

Function sqlite3RowSetInit CDecl Alias "sqlite3RowSetInit" ( _
    ByVal db As sqlite3 Ptr _
) As Any Ptr Export

    If db = 0 Then Return 0
    Dim p As RowSet Ptr = CPtr(RowSet Ptr, _
        sqlite3DbMallocRawNN(db, SizeOf(RowSet)))
    If p = 0 Then Return 0

    Dim allocationSize As SQLITE_C_INT = sqlite3DbMallocSize(db, p)
    Dim firstEntryOffset As SQLITE_C_INT = _
        ((SizeOf(RowSet) + 7) \ 8) * 8
    If allocationSize < firstEntryOffset Then
        sqlite3DbFree(db, p)
        db->mallocFailed = 1
        Return 0
    End If

    p->pChunk = 0
    p->db = db
    p->pEntry = 0
    p->pLast = 0
    p->pForest = 0
    p->pFresh = CPtr(RowSetEntry Ptr, CPtr(UByte Ptr, p) + firstEntryOffset)
    p->nFresh = CUShort((allocationSize - firstEntryOffset) \ SizeOf(RowSetEntry))
    p->rsFlags = ROWSET_SORTED
    p->iBatch = 0
    Return p
End Function

Sub sqlite3RowSetClear CDecl Alias "sqlite3RowSetClear" ( _
    ByVal pArgument As Any Ptr _
) Export

    If pArgument = 0 Then Exit Sub
    Dim p As RowSet Ptr = CPtr(RowSet Ptr, pArgument)
    Dim pChunk As RowSetChunk Ptr = p->pChunk
    While pChunk <> 0
        Dim pNextChunk As RowSetChunk Ptr = pChunk->pNextChunk
        sqlite3DbFree(p->db, pChunk)
        pChunk = pNextChunk
    Wend
    p->pChunk = 0
    p->nFresh = 0
    p->pEntry = 0
    p->pLast = 0
    p->pForest = 0
    p->rsFlags = ROWSET_SORTED
End Sub

Sub sqlite3RowSetDelete CDecl Alias "sqlite3RowSetDelete" ( _
    ByVal pArgument As Any Ptr _
) Export

    If pArgument = 0 Then Exit Sub
    Dim p As RowSet Ptr = CPtr(RowSet Ptr, pArgument)
    Dim db As sqlite3 Ptr = p->db
    sqlite3RowSetClear(p)
    sqlite3DbFree(db, p)
End Sub

Sub sqlite3RowSetInsert CDecl Alias "sqlite3RowSetInsert" ( _
    ByVal pArgument As Any Ptr, _
    ByVal rowid As i64 _
) Export

    If pArgument = 0 Then Exit Sub
    Dim p As RowSet Ptr = CPtr(RowSet Ptr, pArgument)
    If (p->rsFlags And ROWSET_NEXT) <> 0 Then Exit Sub

    Dim pEntry As RowSetEntry Ptr = rowSetEntryAlloc(p)
    If pEntry = 0 Then Exit Sub
    pEntry->v = rowid
    pEntry->pRight = 0
    Dim pLast As RowSetEntry Ptr = p->pLast
    If pLast <> 0 Then
        If rowid <= pLast->v Then p->rsFlags = p->rsFlags And Not ROWSET_SORTED
        pLast->pRight = pEntry
    Else
        p->pEntry = pEntry
    End If
    p->pLast = pEntry
End Sub

Function sqlite3RowSetNext CDecl Alias "sqlite3RowSetNext" ( _
    ByVal pArgument As Any Ptr, _
    ByVal pRowid As i64 Ptr _
) As SQLITE_C_INT Export

    If pArgument = 0 OrElse pRowid = 0 Then Return 0
    Dim p As RowSet Ptr = CPtr(RowSet Ptr, pArgument)
    If p->pForest <> 0 Then Return 0

    If (p->rsFlags And ROWSET_NEXT) = 0 Then
        If (p->rsFlags And ROWSET_SORTED) = 0 Then p->pEntry = rowSetEntrySort(p->pEntry)
        p->rsFlags = p->rsFlags Or ROWSET_SORTED Or ROWSET_NEXT
    End If

    If p->pEntry = 0 Then Return 0
    pRowid[0] = p->pEntry->v
    p->pEntry = p->pEntry->pRight
    If p->pEntry = 0 Then sqlite3RowSetClear(p)
    Return 1
End Function

Function sqlite3RowSetTest CDecl Alias "sqlite3RowSetTest" ( _
    ByVal pArgument As Any Ptr, _
    ByVal batchNumber As SQLITE_C_INT, _
    ByVal rowid As i64 _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return 0
    Dim pRowSet As RowSet Ptr = CPtr(RowSet Ptr, pArgument)
    If (pRowSet->rsFlags And ROWSET_NEXT) <> 0 Then Return 0

    If batchNumber <> pRowSet->iBatch Then
        Dim p As RowSetEntry Ptr = pRowSet->pEntry
        If p <> 0 Then
            Dim pPrevTree As RowSetEntry Ptr Ptr = @pRowSet->pForest
            Dim pTree As RowSetEntry Ptr = pRowSet->pForest

            If (pRowSet->rsFlags And ROWSET_SORTED) = 0 Then p = rowSetEntrySort(p)
            While pTree <> 0
                pPrevTree = @pTree->pRight
                If pTree->pLeft = 0 Then
                    pTree->pLeft = rowSetListToTree(p)
                    Exit While
                Else
                    Dim pAux As RowSetEntry Ptr = 0
                    Dim pTail As RowSetEntry Ptr = 0
                    rowSetTreeToList(pTree->pLeft, pAux, pTail)
                    pTree->pLeft = 0
                    p = rowSetEntryMerge(pAux, p)
                End If
                pTree = pTree->pRight
            Wend

            If pTree = 0 Then
                pTree = rowSetEntryAlloc(pRowSet)
                If pTree <> 0 Then
                    pTree->v = 0
                    pTree->pRight = 0
                    pTree->pLeft = rowSetListToTree(p)
                    pPrevTree[0] = pTree
                End If
            End If
            pRowSet->pEntry = 0
            pRowSet->pLast = 0
            pRowSet->rsFlags = pRowSet->rsFlags Or ROWSET_SORTED
        End If
        pRowSet->iBatch = batchNumber
    End If

    Dim pTree As RowSetEntry Ptr = pRowSet->pForest
    While pTree <> 0
        Dim p As RowSetEntry Ptr = pTree->pLeft
        While p <> 0
            If p->v < rowid Then
                p = p->pRight
            ElseIf p->v > rowid Then
                p = p->pLeft
            Else
                Return 1
            End If
        Wend
        pTree = pTree->pRight
    Wend
    Return 0
End Function

/' end of sqlite3_rowset.bas '/
