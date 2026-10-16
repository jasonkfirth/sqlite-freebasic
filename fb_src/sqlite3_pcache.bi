/'
    Project: SQLite FreeBASIC port

    File: sqlite3_pcache.bi

    Purpose:

        Declare the page-cache structures and internal C ABI.

    Responsibilities:

        - Define page headers, dirty flags, and cache lifecycle entry points.
        - Preserve the callback signatures and field order of PCACHE2 methods.
        - Keep the pager-facing page layout explicit for later B-tree work.

    This file intentionally does NOT contain:

        - Page allocation policy or dirty-list algorithms.
        - Pager, journal, or B-tree behavior.
'/ 

#ifndef SQLITE3_FB_PCACHE_BI
#define SQLITE3_FB_PCACHE_BI

#include once "sqlite3_types.bi"

Type sqlite3_pcache_page
    pBuf As Any Ptr
    pExtra As Any Ptr
End Type

Type PgHdr
    pPage As sqlite3_pcache_page Ptr
    pData As Any Ptr
    pExtra As Any Ptr
    pCache As Any Ptr
    pDirty As PgHdr Ptr
    pPager As Any Ptr
#ifdef SQLITE_CHECK_PAGES
    pageHash As u64
#endif
    pgno As u32
    flags As u16
    nRef As i64
    pDirtyNext As PgHdr Ptr
    pDirtyPrev As PgHdr Ptr
End Type

Type SqlitePcacheStressProc As Function CDecl ( _
    ByVal pArg As Any Ptr, _
    ByVal pPage As PgHdr Ptr _
) As SQLITE_C_INT

Type SqlitePcacheXInitProc As Function CDecl (ByVal pArg As Any Ptr) As SQLITE_C_INT
Type SqlitePcacheXShutdownProc As Sub CDecl (ByVal pArg As Any Ptr)
Type SqlitePcacheXCreateProc As Function CDecl ( _
    ByVal pageSize As SQLITE_C_INT, _
    ByVal extraSize As SQLITE_C_INT, _
    ByVal purgeable As SQLITE_C_INT _
) As Any Ptr
Type SqlitePcacheXCacheSizeProc As Sub CDecl ( _
    ByVal pCache As Any Ptr, _
    ByVal cacheSize As SQLITE_C_INT _
)
Type SqlitePcacheXPageCountProc As Function CDecl ( _
    ByVal pCache As Any Ptr _
) As SQLITE_C_INT
Type SqlitePcacheXFetchProc As Function CDecl ( _
    ByVal pCache As Any Ptr, _
    ByVal pageNumber As u32, _
    ByVal createFlag As SQLITE_C_INT _
) As sqlite3_pcache_page Ptr
Type SqlitePcacheXUnpinProc As Sub CDecl ( _
    ByVal pCache As Any Ptr, _
    ByVal pPage As sqlite3_pcache_page Ptr, _
    ByVal discard As SQLITE_C_INT _
)
Type SqlitePcacheXRekeyProc As Sub CDecl ( _
    ByVal pCache As Any Ptr, _
    ByVal pPage As sqlite3_pcache_page Ptr, _
    ByVal oldKey As u32, _
    ByVal newKey As u32 _
)
Type SqlitePcacheXTruncateProc As Sub CDecl ( _
    ByVal pCache As Any Ptr, _
    ByVal keyLimit As u32 _
)
Type SqlitePcacheXDestroyProc As Sub CDecl (ByVal pCache As Any Ptr)
Type SqlitePcacheXShrinkProc As Sub CDecl (ByVal pCache As Any Ptr)

/'
    This record matches sqlite3_pcache_methods2 from sqlite3.h.in. SQLite
    copies it during SQLITE_CONFIG_PCACHE2, so the supplied table can be
    temporary after sqlite3_config() returns.
'/ 
Type SqlitePcacheMethods2
    iVersion As SQLITE_C_INT
    pArg As Any Ptr
    xInit As SqlitePcacheXInitProc
    xShutdown As SqlitePcacheXShutdownProc
    xCreate As SqlitePcacheXCreateProc
    xCachesize As SqlitePcacheXCacheSizeProc
    xPagecount As SqlitePcacheXPageCountProc
    xFetch As SqlitePcacheXFetchProc
    xUnpin As SqlitePcacheXUnpinProc
    xRekey As SqlitePcacheXRekeyProc
    xTruncate As SqlitePcacheXTruncateProc
    xDestroy As SqlitePcacheXDestroyProc
    xShrink As SqlitePcacheXShrinkProc
End Type

Declare Sub sqlite3ConfigSetPcacheMethods CDecl Alias "sqlite3ConfigSetPcacheMethods" ( _
    ByVal pMethods As Const SqlitePcacheMethods2 Ptr _
)
Declare Sub sqlite3ConfigGetPcacheMethods CDecl Alias "sqlite3ConfigGetPcacheMethods" ( _
    ByVal pMethods As SqlitePcacheMethods2 Ptr _
)

Type PCache
    pDirty As PgHdr Ptr
    pDirtyTail As PgHdr Ptr
    pSynced As PgHdr Ptr
    nRefSum As i64
    szCache As SQLITE_C_INT
    szSpill As SQLITE_C_INT
    szPage As SQLITE_C_INT
    szExtra As SQLITE_C_INT
    bPurgeable As u8
    eCreate As u8
    xStress As SqlitePcacheStressProc
    pStress As Any Ptr
    pCache As Any Ptr
End Type

#define PGHDR_CLEAN &H001
#define PGHDR_DIRTY &H002
#define PGHDR_WRITEABLE &H004
#define PGHDR_NEED_SYNC &H008
#define PGHDR_DONT_WRITE &H010
#define PGHDR_MMAP &H020
#define PGHDR_WAL_APPEND &H040

Declare Function sqlite3PcacheInitialize CDecl Alias "sqlite3PcacheInitialize" () As SQLITE_C_INT
Declare Sub sqlite3PcacheShutdown CDecl Alias "sqlite3PcacheShutdown" ()
Declare Sub sqlite3PCacheBufferSetup CDecl Alias "sqlite3PCacheBufferSetup" ( _
    ByVal pBuffer As Any Ptr, _
    ByVal slotSize As SQLITE_C_INT, _
    ByVal slotCount As SQLITE_C_INT _
)
Declare Function sqlite3PcacheOpen CDecl Alias "sqlite3PcacheOpen" ( _
    ByVal pageSize As SQLITE_C_INT, _
    ByVal extraSize As SQLITE_C_INT, _
    ByVal purgeable As SQLITE_C_INT, _
    ByVal xStress As SqlitePcacheStressProc, _
    ByVal pStress As Any Ptr, _
    ByVal pToInit As PCache Ptr _
) As SQLITE_C_INT
Declare Function sqlite3PcacheSetPageSize CDecl Alias "sqlite3PcacheSetPageSize" ( _
    ByVal pCache As PCache Ptr, _
    ByVal pageSize As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3PcacheSize CDecl Alias "sqlite3PcacheSize" () As SQLITE_C_INT
Declare Function sqlite3PcacheFetch CDecl Alias "sqlite3PcacheFetch" ( _
    ByVal pCache As PCache Ptr, _
    ByVal pageNumber As u32, _
    ByVal createFlag As SQLITE_C_INT _
) As sqlite3_pcache_page Ptr
Declare Function sqlite3PcacheFetchStress CDecl Alias "sqlite3PcacheFetchStress" ( _
    ByVal pCache As PCache Ptr, _
    ByVal pageNumber As u32, _
    ByVal ppPage As sqlite3_pcache_page Ptr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3PcacheFetchFinish CDecl Alias "sqlite3PcacheFetchFinish" ( _
    ByVal pCache As PCache Ptr, _
    ByVal pageNumber As u32, _
    ByVal pPage As sqlite3_pcache_page Ptr _
) As PgHdr Ptr
Declare Sub sqlite3PcacheRelease CDecl Alias "sqlite3PcacheRelease" (ByVal pPage As PgHdr Ptr)
Declare Sub sqlite3PcacheDrop CDecl Alias "sqlite3PcacheDrop" (ByVal pPage As PgHdr Ptr)
Declare Sub sqlite3PcacheMakeDirty CDecl Alias "sqlite3PcacheMakeDirty" (ByVal pPage As PgHdr Ptr)
Declare Sub sqlite3PcacheMakeClean CDecl Alias "sqlite3PcacheMakeClean" (ByVal pPage As PgHdr Ptr)
Declare Sub sqlite3PcacheCleanAll CDecl Alias "sqlite3PcacheCleanAll" (ByVal pCache As PCache Ptr)
Declare Sub sqlite3PcacheClearWritable CDecl Alias "sqlite3PcacheClearWritable" (ByVal pCache As PCache Ptr)
Declare Sub sqlite3PcacheClearSyncFlags CDecl Alias "sqlite3PcacheClearSyncFlags" (ByVal pCache As PCache Ptr)
Declare Sub sqlite3PcacheMove CDecl Alias "sqlite3PcacheMove" ( _
    ByVal pPage As PgHdr Ptr, _
    ByVal newPageNumber As u32 _
)
Declare Sub sqlite3PcacheTruncate CDecl Alias "sqlite3PcacheTruncate" ( _
    ByVal pCache As PCache Ptr, _
    ByVal pageNumber As u32 _
)
Declare Function sqlite3PcacheDirtyList CDecl Alias "sqlite3PcacheDirtyList" (ByVal pCache As PCache Ptr) As PgHdr Ptr
Declare Sub sqlite3PcacheClose CDecl Alias "sqlite3PcacheClose" (ByVal pCache As PCache Ptr)
Declare Sub sqlite3PcacheClear CDecl Alias "sqlite3PcacheClear" (ByVal pCache As PCache Ptr)
Declare Function sqlite3PcacheRefCount CDecl Alias "sqlite3PcacheRefCount" (ByVal pCache As PCache Ptr) As i64
Declare Sub sqlite3PcacheRef CDecl Alias "sqlite3PcacheRef" (ByVal pPage As PgHdr Ptr)
Declare Function sqlite3PcachePageRefcount CDecl Alias "sqlite3PcachePageRefcount" (ByVal pPage As PgHdr Ptr) As i64
Declare Function sqlite3PcachePagecount CDecl Alias "sqlite3PcachePagecount" (ByVal pCache As PCache Ptr) As SQLITE_C_INT
Declare Sub sqlite3PcacheSetCachesize CDecl Alias "sqlite3PcacheSetCachesize" ( _
    ByVal pCache As PCache Ptr, _
    ByVal maxPages As SQLITE_C_INT _
)
Declare Function sqlite3PcacheSetSpillsize CDecl Alias "sqlite3PcacheSetSpillsize" ( _
    ByVal pCache As PCache Ptr, _
    ByVal maxPages As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Sub sqlite3PcacheShrink CDecl Alias "sqlite3PcacheShrink" (ByVal pCache As PCache Ptr)
Declare Function sqlite3HeaderSizePcache CDecl Alias "sqlite3HeaderSizePcache" () As SQLITE_C_INT
Declare Function sqlite3HeaderSizePcache1 CDecl Alias "sqlite3HeaderSizePcache1" () As SQLITE_C_INT
Declare Function sqlite3PCachePercentDirty CDecl Alias "sqlite3PCachePercentDirty" (ByVal pCache As PCache Ptr) As SQLITE_C_INT
Declare Function sqlite3PcachePageSanity CDecl Alias "sqlite3PcachePageSanity" (ByVal pPage As PgHdr Ptr) As SQLITE_C_INT
Declare Function sqlite3PCacheIsDirty CDecl Alias "sqlite3PCacheIsDirty" (ByVal pCache As PCache Ptr) As SQLITE_C_INT
Declare Function sqlite3PcacheGetCachesize CDecl Alias "sqlite3PcacheGetCachesize" (ByVal pCache As PCache Ptr) As SQLITE_C_INT
Type SqlitePcacheIterateProc As Sub CDecl (ByVal pPage As PgHdr Ptr)
Declare Sub sqlite3PcacheIterateDirty CDecl Alias "sqlite3PcacheIterateDirty" ( _
    ByVal pCache As PCache Ptr, _
    ByVal xIter As SqlitePcacheIterateProc _
)
Declare Sub sqlite3PCacheSetDefault CDecl Alias "sqlite3PCacheSetDefault" ()
Declare Function sqlite3PageMalloc CDecl Alias "sqlite3PageMalloc" (ByVal nByte As SQLITE_C_INT) As Any Ptr
Declare Sub sqlite3PageFree CDecl Alias "sqlite3PageFree" (ByVal p As Any Ptr)

#endif

/' end of sqlite3_pcache.bi '/
