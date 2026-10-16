/'
    Project: SQLite FreeBASIC port

    File: sqlite3_hash.bas

    Purpose:

        Port SQLite's generic case-insensitive hash table from src/hash.c.

    Responsibilities:

        - Maintain a global element list and optional bucket chains.
        - Resize buckets opportunistically as entries are inserted.
        - Find, replace, remove, and clear keyed data entries.

    This file intentionally does NOT contain:

        - Database schema objects stored as hash values.
        - Fault injection and allocator status accounting.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_hash_types.bi"
#include once "sqlite3_fault.bi"

Declare Function sqlite3Malloc CDecl Alias "sqlite3Malloc" ( _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Function sqlite3MallocSize CDecl Alias "sqlite3MallocSize" ( _
    ByVal p As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Declare Function sqlite3StrICmp CDecl Alias "sqlite3StrICmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT

#ifndef SQLITE_MALLOC_SOFT_LIMIT
#define SQLITE_MALLOC_SOFT_LIMIT 1024
#endif

Private Const SQLITE_HASH_SOFT_LIMIT As ULongInt = SQLITE_MALLOC_SOFT_LIMIT
Private Const SQLITE_HASH_MULTIPLIER As u32 = &H9E3779B1
Dim Shared sqlite3HashNullElement As HashElem

Private Function strHash(ByVal z As Const ZString Ptr) As u32
    If z = 0 Then Return 0

    Dim bytes As Const UByte Ptr = CPtr(Const UByte Ptr, z)
    Dim h As u32 = 0
    While bytes[0] <> 0
#ifdef SQLITE_EBCDIC
        h += (bytes[0] And &HBF)
#else
        h += (bytes[0] And &HDF)
#endif
        h *= SQLITE_HASH_MULTIPLIER
        bytes += 1
    Wend
    Return h
End Function

Private Function sqlite3HashBucketAt( _
    ByVal buckets As HashBucket Ptr, _
    ByVal index As ULongInt _
) As HashBucket Ptr
    Return buckets + index
End Function

Private Sub insertElement( _
    ByVal pHash As Hash Ptr, _
    ByVal pBucket As HashBucket Ptr, _
    ByVal pNew As HashElem Ptr _
)
    Dim pHead As HashElem Ptr = 0
    If pBucket <> 0 Then
        If pBucket->count <> 0 Then pHead = pBucket->chain
        pBucket->count += 1
        pBucket->chain = pNew
    End If

    If pHead <> 0 Then
        pNew->next = pHead
        pNew->prev = pHead->prev
        If pHead->prev <> 0 Then
            pHead->prev->next = pNew
        Else
            pHash->first = pNew
        End If
        pHead->prev = pNew
    Else
        pNew->next = pHash->first
        If pHash->first <> 0 Then pHash->first->prev = pNew
        pNew->prev = 0
        pHash->first = pNew
    End If
End Sub

Private Function rehash( _
    ByVal pHash As Hash Ptr, _
    ByVal requestedSize As SQLITE_C_UINT _
) As SQLITE_C_INT

    If pHash = 0 OrElse requestedSize = 0 Then Return 0

    Dim newSize As ULongInt = requestedSize
    Dim bucketBytes As ULongInt = SizeOf(HashBucket)
#if SQLITE_MALLOC_SOFT_LIMIT > 0
    If newSize * bucketBytes > SQLITE_HASH_SOFT_LIMIT Then
        newSize = SQLITE_HASH_SOFT_LIMIT \ bucketBytes
    End If
    If newSize = pHash->htsize Then Return 0
#endif
    If newSize = 0 Then Return 0

    ' Rehashing only improves lookup speed, so allocation failure is benign.
    sqlite3BeginBenignMalloc()
    Dim pNewBuckets As HashBucket Ptr = CPtr(HashBucket Ptr, _
        sqlite3Malloc(newSize * bucketBytes))
    sqlite3EndBenignMalloc()
    If pNewBuckets = 0 Then Return 0

    sqlite3_free(pHash->ht)
    pHash->ht = pNewBuckets
    newSize = CULngInt(sqlite3MallocSize(pNewBuckets)) \ bucketBytes
    If newSize = 0 Then
        sqlite3_free(pHash->ht)
        pHash->ht = 0
        pHash->htsize = 0
        Return 0
    End If
    pHash->htsize = CUInt(newSize)

    For i As ULongInt = 0 To newSize - 1
        Dim pBucket As HashBucket Ptr = sqlite3HashBucketAt(pNewBuckets, i)
        pBucket->count = 0
        pBucket->chain = 0
    Next

    Dim pElement As HashElem Ptr = pHash->first
    pHash->first = 0
    While pElement <> 0
        Dim pNext As HashElem Ptr = pElement->next
        Dim pBucket As HashBucket Ptr = sqlite3HashBucketAt( _
            pNewBuckets, pElement->h Mod pHash->htsize)
        insertElement(pHash, pBucket, pElement)
        pElement = pNext
    Wend
    Return -1
End Function

Private Function findElementWithHash( _
    ByVal pHash As Const Hash Ptr, _
    ByVal pKey As Const ZString Ptr, _
    ByVal pHashValue As u32 Ptr _
) As HashElem Ptr

    If pHash = 0 OrElse pKey = 0 Then Return @sqlite3HashNullElement

    Dim h As u32 = strHash(pKey)
    Dim pElement As HashElem Ptr
    Dim remaining As SQLITE_C_UINT
    If pHash->ht <> 0 AndAlso pHash->htsize <> 0 Then
        Dim pBuckets As HashBucket Ptr = pHash->ht
        Dim pBucket As HashBucket Ptr = sqlite3HashBucketAt( _
            pBuckets, h Mod pHash->htsize)
        pElement = pBucket->chain
        remaining = pBucket->count
    Else
        pElement = pHash->first
        remaining = pHash->count
    End If
    If pHashValue <> 0 Then pHashValue[0] = h

    While remaining <> 0 AndAlso pElement <> 0
        If h = pElement->h AndAlso sqlite3StrICmp(pElement->pKey, pKey) = 0 Then
            Return pElement
        End If
        pElement = pElement->next
        remaining -= 1
    Wend
    Return @sqlite3HashNullElement
End Function

Private Sub removeElement( _
    ByVal pHash As Hash Ptr, _
    ByVal pElement As HashElem Ptr _
)
    If pHash = 0 OrElse pElement = 0 Then Exit Sub

    If pElement->prev <> 0 Then
        pElement->prev->next = pElement->next
    Else
        pHash->first = pElement->next
    End If
    If pElement->next <> 0 Then pElement->next->prev = pElement->prev

    If pHash->ht <> 0 AndAlso pHash->htsize <> 0 Then
        Dim pBuckets As HashBucket Ptr = pHash->ht
        Dim pBucket As HashBucket Ptr = sqlite3HashBucketAt( _
            pBuckets, pElement->h Mod pHash->htsize)
        If pBucket->chain = pElement Then pBucket->chain = pElement->next
        If pBucket->count <> 0 Then pBucket->count -= 1
    End If

    sqlite3_free(pElement)
    If pHash->count <> 0 Then pHash->count -= 1
    If pHash->count = 0 Then sqlite3HashClear(pHash)
End Sub

Sub sqlite3HashInit CDecl Alias "sqlite3HashInit" ( _
    ByVal pHash As Hash Ptr _
) Export

    If pHash = 0 Then Exit Sub
    pHash->first = 0
    pHash->count = 0
    pHash->htsize = 0
    pHash->ht = 0
End Sub

Sub sqlite3HashClear CDecl Alias "sqlite3HashClear" ( _
    ByVal pHash As Hash Ptr _
) Export

    If pHash = 0 Then Exit Sub
    Dim pElement As HashElem Ptr = pHash->first
    pHash->first = 0
    sqlite3_free(pHash->ht)
    pHash->ht = 0
    pHash->htsize = 0
    While pElement <> 0
        Dim pNext As HashElem Ptr = pElement->next
        sqlite3_free(pElement)
        pElement = pNext
    Wend
    pHash->count = 0
End Sub

Function sqlite3HashFind CDecl Alias "sqlite3HashFind" ( _
    ByVal pHash As Const Hash Ptr, _
    ByVal pKey As Const ZString Ptr _
) As Any Ptr Export

    Return findElementWithHash(pHash, pKey, 0)->data
End Function

Function sqlite3HashInsert CDecl Alias "sqlite3HashInsert" ( _
    ByVal pHash As Hash Ptr, _
    ByVal pKey As Const ZString Ptr, _
    ByVal pData As Any Ptr _
) As Any Ptr Export

    If pHash = 0 OrElse pKey = 0 Then Return pData
    Dim h As u32 = 0
    Dim pElement As HashElem Ptr = findElementWithHash(pHash, pKey, @h)
    If pElement->data <> 0 Then
        Dim pOldData As Any Ptr = pElement->data
        If pData = 0 Then
            removeElement(pHash, pElement)
        Else
            pElement->data = pData
            pElement->pKey = CPtr(ZString Ptr, pKey)
        End If
        Return pOldData
    End If
    If pData = 0 Then Return 0

    Dim pNewElement As HashElem Ptr = CPtr(HashElem Ptr, sqlite3Malloc(SizeOf(HashElem)))
    If pNewElement = 0 Then Return pData
    pNewElement->pKey = CPtr(ZString Ptr, pKey)
    pNewElement->h = h
    pNewElement->data = pData
    pHash->count += 1

    If pHash->count >= 5 AndAlso pHash->count > 2 * pHash->htsize Then
        rehash(pHash, pHash->count * 3)
    End If

    Dim pBucket As HashBucket Ptr = 0
    If pHash->ht <> 0 AndAlso pHash->htsize <> 0 Then
        pBucket = sqlite3HashBucketAt(pHash->ht, h Mod pHash->htsize)
    End If
    insertElement(pHash, pBucket, pNewElement)
    Return 0
End Function

/' end of sqlite3_hash.bas '/
