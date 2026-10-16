/'
    Project: SQLite FreeBASIC port

    File: sqlite3_pcache1_types.bi

    Purpose:

        Define the default pcache1 page, cache, and shared-group records.

    Responsibilities:

        - Preserve the C field order used by src/pcache1.c.
        - Provide typed record paths for translated cache helpers.
        - Represent pointer links without embedding compiler-specific C bitfields.

    This file intentionally does NOT contain:

        - Page allocation, hash-table, LRU, or cache-policy algorithms.
        - A claim that the records have been verified against every ABI profile.
'/ 

#ifndef SQLITE3_FB_PCACHE1_TYPES_BI
#define SQLITE3_FB_PCACHE1_TYPES_BI

#include once "sqlite3_pcache.bi"

/'
    These records mirror src/pcache1.c. PgHdr1 starts with the public cache
    page so callers can use the base pointer at the same address. pNext links
    hash buckets; pLruNext and pLruPrev link unpinned pages. PGroup.lru is the
    sentinel for that circular LRU list.
'/ 
Type SqlitePcache1Page
    page As sqlite3_pcache_page
    iKey As u32
    isBulkLocal As u16
    isAnchor As u16
    pNext As Any Ptr
    pCache As Any Ptr
    pLruNext As Any Ptr
    pLruPrev As Any Ptr
End Type

/' PGroup tracks aggregate limits and owns the circular unpinned-page sentinel. '/
Type SqlitePcache1Group
    mutex As Any Ptr
    nMaxPage As u32
    nMinPage As u32
    mxPinned As u32
    nPurgeable As u32
    lru As SqlitePcache1Page
End Type

/'
    PCache1 owns its page hash and freelist. Its PGroup shares page limits and
    the recycle list with other caches; pGroup.mutex protects those shared
    links when the group is configured for cross-cache recycling.
'/ 
Type SqlitePcache1
    pGroup As Any Ptr
    pnPurgeable As u32 Ptr
    szPage As SQLITE_C_INT
    szExtra As SQLITE_C_INT
    szAlloc As SQLITE_C_INT
    bPurgeable As SQLITE_C_INT
    nMin As u32
    nMax As u32
    n90pct As u32
    iMaxKey As u32
    nPurgeableDummy As u32
    nRecyclable As u32
    nPage As u32
    nHash As u32
    apHash As Any Ptr
    pFree As Any Ptr
    pBulk As Any Ptr
End Type

Type SqlitePcache1FreeSlot
    pNext As Any Ptr
End Type

/'
    pcache1_g stores the global page-cache buffer pool and the shared PGroup.
    The allocator mutex protects pFree, nFreeSlot, and bUnderPressure.
'/ 
Type SqlitePcache1Global
    grp As SqlitePcache1Group
    isInit As SQLITE_C_INT
    separateCache As SQLITE_C_INT
    nInitPage As SQLITE_C_INT
    szSlot As SQLITE_C_INT
    nSlot As SQLITE_C_INT
    nReserve As SQLITE_C_INT
    pStart As Any Ptr
    pEnd As Any Ptr
    mutex As Any Ptr
    pFree As Any Ptr
    nFreeSlot As SQLITE_C_INT
    bUnderPressure As SQLITE_C_INT
End Type

/' Internal pcache1 method entry points used by the PCache wrapper. '/
Declare Function pcache1Init CDecl Alias "pcache1Init" ( _
    ByVal pUnused As Any Ptr _
) As SQLITE_C_INT
Declare Function pcache1Alloc CDecl Alias "pcache1Alloc" ( _
    ByVal byteCount As SQLITE_C_INT _
) As Any Ptr
Declare Sub pcache1Free CDecl Alias "pcache1Free" (ByVal pMemory As Any Ptr)
Declare Sub pcache1Shutdown CDecl Alias "pcache1Shutdown" ( _
    ByVal pUnused As Any Ptr _
)
Declare Sub sqlite3Pcache1BufferSetup CDecl Alias "sqlite3Pcache1BufferSetup" ( _
    ByVal pBuffer As Any Ptr, _
    ByVal slotSize As SQLITE_C_INT, _
    ByVal slotCount As SQLITE_C_INT _
)
Declare Function pcache1Create CDecl Alias "pcache1Create" ( _
    ByVal pageSize As SQLITE_C_INT, _
    ByVal extraSize As SQLITE_C_INT, _
    ByVal purgeable As SQLITE_C_INT _
) As Any Ptr
Declare Function pcache1Fetch CDecl Alias "pcache1Fetch" ( _
    ByVal pCache As Any Ptr, _
    ByVal pageNumber As u32, _
    ByVal createFlag As SQLITE_C_INT _
) As sqlite3_pcache_page Ptr
Declare Sub pcache1Unpin CDecl Alias "pcache1Unpin" ( _
    ByVal pCache As Any Ptr, _
    ByVal pPage As sqlite3_pcache_page Ptr, _
    ByVal reuseUnlikely As SQLITE_C_INT _
)
Declare Sub pcache1Rekey CDecl Alias "pcache1Rekey" ( _
    ByVal pCache As Any Ptr, _
    ByVal pPage As sqlite3_pcache_page Ptr, _
    ByVal oldKey As u32, _
    ByVal newKey As u32 _
)
Declare Sub pcache1Truncate CDecl Alias "pcache1Truncate" ( _
    ByVal pCache As Any Ptr, _
    ByVal keyLimit As u32 _
)
Declare Sub pcache1Destroy CDecl Alias "pcache1Destroy" (ByVal pCache As Any Ptr)
Declare Sub pcache1Cachesize CDecl Alias "pcache1Cachesize" ( _
    ByVal pCache As Any Ptr, _
    ByVal maxPages As SQLITE_C_INT _
)
Declare Function pcache1Pagecount CDecl Alias "pcache1Pagecount" (ByVal pCache As Any Ptr) As SQLITE_C_INT
Declare Sub pcache1Shrink CDecl Alias "pcache1Shrink" (ByVal pCache As Any Ptr)

#endif

/' end of sqlite3_pcache1_types.bi '/
