/'
    Project: SQLite FreeBASIC port

    File: sqlite3_config.bas

    Purpose:

        Store process-wide configuration for URI, threading, allocation, and sorters.

    Responsibilities:

        - Apply URI, memory-status, covering-index, and threading-mode configuration.
        - Apply SQLITE_CONFIG_HEAP and select the enabled fixed-heap allocator.
        - Apply SQLITE_CONFIG_WIN32_HEAPSIZE for the Windows heap allocator.
        - Copy and return the configured sqlite3_mem_methods callback table.
        - Copy and return the configured sqlite3_pcache_methods2 callback table.
        - Copy and return mutex methods before SQLite initialization.
        - Choose whether each connection needs its own mutex.
        - Preserve an external page-cache buffer for subsystem initialization.
        - Store the default lookaside slot size and count for new connections.
        - Set the default capacity limit for the memory-database VFS.
        - Store sorter PMA sizing and small-allocation preferences.
        - Store the feature-gated sorter-reference size threshold.
        - Preserve the legacy no-op/error behavior of old page-cache options.
        - Retain the process-wide extra schema validation setting.
        - Store the default shared-cache setting for subsequently opened connections.
        - Report the page-cache header size, including after initialization.
        - Register and retrieve the process-wide log callback.
        - Store the optional SQLLOG callback and its application argument.
        - Expose the configured URI default to the file-URI parser.
        - Define the deprecated process-wide directory override pointers.
        - Define public temporary and database directory override pointers.
        - Retain PRNG seed, local-time fault, corruption, and VDBE test settings.

    This file intentionally does NOT contain:

        - Remaining global tuning options not supported by the FreeBASIC ABI.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_pcache.bi"
#include once "sqlite3_mutex.bi"
#include once "sqlite3_memory_methods.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_process_globals.bi"
#include once "sqlite3_sqllog.bi"

' These ABI variables retain application-owned storage until shutdown.
Dim Shared sqlite3_temp_directory As ZString Ptr = 0
Dim Shared sqlite3_data_directory As ZString Ptr = 0

Declare Function sqlite3ConfigIsInitialized CDecl Alias "sqlite3ConfigIsInitialized" () As SQLITE_C_INT
Declare Function sqlite3HeaderSizeBtree CDecl Alias "sqlite3HeaderSizeBtree" () As SQLITE_C_INT

#if defined(SQLITE_DEFAULT_URI)
#define SQLITE3_FB_DEFAULT_URI SQLITE_DEFAULT_URI
#else
#define SQLITE3_FB_DEFAULT_URI 0
#endif

#if defined(SQLITE_THREADSAFE) AndAlso SQLITE_THREADSAFE > 0
#define SQLITE3_FB_DEFAULT_CORE_MUTEX 1
#if SQLITE_THREADSAFE = 1
#define SQLITE3_FB_DEFAULT_FULL_MUTEX 1
#else
#define SQLITE3_FB_DEFAULT_FULL_MUTEX 0
#endif
#else
#define SQLITE3_FB_DEFAULT_CORE_MUTEX 0
#define SQLITE3_FB_DEFAULT_FULL_MUTEX 0
#endif

#if defined(SQLITE_DEFAULT_MEMSTATUS)
#define SQLITE3_FB_DEFAULT_MEMSTATUS SQLITE_DEFAULT_MEMSTATUS
#else
#define SQLITE3_FB_DEFAULT_MEMSTATUS 1
#endif

#if defined(SQLITE_DEFAULT_SORTERREF_SIZE)
#define SQLITE3_FB_DEFAULT_SORTERREF_SIZE SQLITE_DEFAULT_SORTERREF_SIZE
#else
#define SQLITE3_FB_DEFAULT_SORTERREF_SIZE &H7FFFFFFF
#endif

Private Dim Shared sqlite3UriOpenDefault As SQLITE_C_INT = _
    SQLITE3_FB_DEFAULT_URI
Private Dim Shared sqlite3ConfigCoreMutex As SQLITE_C_INT = _
    SQLITE3_FB_DEFAULT_CORE_MUTEX
Private Dim Shared sqlite3ConfigFullMutex As SQLITE_C_INT = _
    SQLITE3_FB_DEFAULT_FULL_MUTEX
Private Dim Shared sqlite3ConfigPageBuffer As Any Ptr
Private Dim Shared sqlite3ConfigPageSize As SQLITE_C_INT
Private Dim Shared sqlite3ConfigPageCount As SQLITE_C_INT = 20
Private Dim Shared sqlite3ConfigHeapBuffer As Any Ptr
Private Dim Shared sqlite3ConfigHeapSize As SQLITE_C_INT
Private Dim Shared sqlite3ConfigHeapMinRequest As SQLITE_C_INT
Private Dim Shared sqlite3ConfigLookasideSize As SQLITE_C_INT = 1200
#if defined(SQLITE_OMIT_TWOSIZE_LOOKASIDE)
Private Dim Shared sqlite3ConfigLookasideCount As SQLITE_C_INT = 100
#else
Private Dim Shared sqlite3ConfigLookasideCount As SQLITE_C_INT = 40
#endif
Private Dim Shared sqlite3ConfigMemStatus As SQLITE_C_INT = _
    SQLITE3_FB_DEFAULT_MEMSTATUS
Private Dim Shared sqlite3ConfiguredStmtJournalSpill As SQLITE_C_INT = _
    SQLITE_STMTJRNL_SPILL
' src/global.c initializes bExtraSchemaChecks to 1. The test-control API can
' change this process-wide setting after it is ported.
Private Dim Shared sqlite3ConfigExtraSchemaChecks As SQLITE_C_INT = 1
' src/global.c defaults SQLITE_ALLOW_COVERING_INDEX_SCAN to enabled.
Private Dim Shared sqlite3ConfigCoveringIndexScan As SQLITE_C_INT = 1
' These fields back the process-wide controls exposed by sqlite3_test_control.
Private Dim Shared sqlite3ConfigTestPrngSeedValue As SQLITE_C_UINT
Private Dim Shared sqlite3ConfigTestNeverCorruptValue As SQLITE_C_INT
Private Dim Shared sqlite3ConfigTestLocaltimeFaultValue As SQLITE_C_INT
Private Dim Shared sqlite3ConfigTestAltLocaltimeValue As Any Ptr
Private Dim Shared sqlite3ConfigTestOnceResetThresholdValue As SQLITE_C_INT = &H7FFFFFFE
Private Dim Shared sqlite3ConfigTestJsonSelfcheckValue As UByte
Private Dim Shared sqlite3ConfigSharedCache As SQLITE_C_INT
Private Dim Shared sqlite3ConfigSmallMalloc As SQLITE_C_INT
Private Dim Shared sqlite3ConfigPmaSize As SQLITE_C_UINT = SQLITE_SORTER_PMASZ
#ifdef SQLITE_ALLOW_ROWID_IN_VIEW
' The optional compatibility mode permits rowid references in stored views
' until SQLITE_CONFIG_ROWID_IN_VIEW disables them.
Private Dim Shared sqlite3ConfigNoVisibleRowidFlags As u32 = 0
#endif
#ifdef SQLITE_ENABLE_SORTER_REFERENCES
Private Dim Shared sqlite3ConfigSorterRefSize As SQLITE_C_UINT = _
    SQLITE3_FB_DEFAULT_SORTERREF_SIZE
#endif
Private Dim Shared sqlite3ConfiguredMmapSize As sqlite3_int64 = _
    SQLITE_DEFAULT_MMAP_SIZE
Private Dim Shared sqlite3MaximumMmapSize As sqlite3_int64 = SQLITE_MAX_MMAP_SIZE
Private Dim Shared sqlite3MemdbMaxSizeDefault As sqlite3_int64 = _
    SQLITE_MEMDB_DEFAULT_MAXSIZE
Private Dim Shared sqlite3ConfigLogCallback As Any Ptr
Private Dim Shared sqlite3ConfigLogArgument As Any Ptr
Private Dim Shared sqlite3ConfigPcacheMethods As SqlitePcacheMethods2
#ifdef SQLITE_ENABLE_SQLLOG
Private Dim Shared sqlite3ConfigSqllogCallback As SqliteSqllogCallback
Private Dim Shared sqlite3ConfigSqllogArgument As Any Ptr
#endif

Sub sqlite3ConfigGetHeap CDecl Alias "sqlite3ConfigGetHeap" ( _
    ByVal ppHeap As Any Ptr Ptr, _
    ByVal pnByte As SQLITE_C_INT Ptr, _
    ByVal pMinRequest As SQLITE_C_INT Ptr _
)
    If ppHeap <> 0 Then ppHeap[0] = sqlite3ConfigHeapBuffer
    If pnByte <> 0 Then pnByte[0] = sqlite3ConfigHeapSize
    If pMinRequest <> 0 Then pMinRequest[0] = sqlite3ConfigHeapMinRequest
End Sub

#ifdef SQLITE_TEST
' The upstream sorter tests use this sentinel to force the heap-nearly-full
' branch without installing a separate allocator.
Function sqlite3_test_set_sorter_fakeheap CDecl Alias "sqlite3_test_set_sorter_fakeheap" ( _
    ByVal enabled As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If enabled <> 0 Then
        If sqlite3ConfigHeapBuffer = 0 Then _
            sqlite3ConfigHeapBuffer = CPtr(Any Ptr, CLngInt(-1))
    ElseIf sqlite3ConfigHeapBuffer = CPtr(Any Ptr, CLngInt(-1)) Then
        sqlite3ConfigHeapBuffer = 0
    End If
    Return SQLITE_OK
End Function
#endif

Function sqlite3ConfigExtraSchemaChecksEnabled CDecl Alias "sqlite3ConfigExtraSchemaChecksEnabled" () As SQLITE_C_INT
    Return sqlite3ConfigExtraSchemaChecks
End Function

Function sqlite3ConfigCoveringIndexScanEnabled CDecl Alias "sqlite3ConfigCoveringIndexScanEnabled" () As SQLITE_C_INT
    Return sqlite3ConfigCoveringIndexScan
End Function

Function sqlite3ConfigSharedCacheEnabled CDecl Alias "sqlite3ConfigSharedCacheEnabled" () As SQLITE_C_INT
    Return sqlite3ConfigSharedCache
End Function

Function sqlite3ConfigLookasideSizeValue CDecl Alias "sqlite3ConfigLookasideSizeValue" () As SQLITE_C_INT Export
    Return sqlite3ConfigLookasideSize
End Function

Function sqlite3ConfigLookasideCountValue CDecl Alias "sqlite3ConfigLookasideCountValue" () As SQLITE_C_INT Export
    Return sqlite3ConfigLookasideCount
End Function

#ifndef SQLITE_OMIT_SHARED_CACHE
Function sqlite3_enable_shared_cache CDecl Alias "sqlite3_enable_shared_cache" ( _
    ByVal enable As SQLITE_C_INT _
) As SQLITE_C_INT Export
    sqlite3ConfigSharedCache = enable
    Return SQLITE_OK
End Function
#endif

Function sqlite3ConfigFullMutexEnabled CDecl Alias "sqlite3ConfigFullMutexEnabled" () As SQLITE_C_INT
    Return sqlite3ConfigFullMutex
End Function

Function sqlite3ConfigMmapSizeDefault CDecl Alias "sqlite3ConfigMmapSizeDefault" () As sqlite3_int64
    Return sqlite3ConfiguredMmapSize
End Function

Function sqlite3ConfigMmapSizeMaximum CDecl Alias "sqlite3ConfigMmapSizeMaximum" () As sqlite3_int64
    Return sqlite3MaximumMmapSize
End Function

' sqlite3_config() freezes this process-wide threshold after initialization.
' The pager reads it through an internal accessor rather than sharing config state.
Function pagerStmtJournalSpillLimit CDecl Alias "pagerStmtJournalSpillLimit" () As SQLITE_C_INT
    Return sqlite3ConfiguredStmtJournalSpill
End Function

Sub sqlite3ConfigSetExtraSchemaChecks CDecl Alias "sqlite3ConfigSetExtraSchemaChecks" ( _
    ByVal enabled As SQLITE_C_INT _
)
    sqlite3ConfigExtraSchemaChecks = CInt(enabled <> 0)
End Sub

Function sqlite3ConfigTestPrngSeed CDecl Alias "sqlite3ConfigTestPrngSeed" () As SQLITE_C_UINT
    Return sqlite3ConfigTestPrngSeedValue
End Function

Sub sqlite3ConfigSetTestPrngSeed CDecl Alias "sqlite3ConfigSetTestPrngSeed" ( _
    ByVal seed As SQLITE_C_UINT _
)
    sqlite3ConfigTestPrngSeedValue = seed
End Sub

Sub sqlite3ConfigSetTestNeverCorrupt CDecl Alias "sqlite3ConfigSetTestNeverCorrupt" ( _
    ByVal enabled As SQLITE_C_INT _
)
    sqlite3ConfigTestNeverCorruptValue = enabled
End Sub

Function sqlite3ConfigTestNeverCorrupt CDecl Alias "sqlite3ConfigTestNeverCorrupt" () As SQLITE_C_INT
    Return sqlite3ConfigTestNeverCorruptValue
End Function

Sub sqlite3ConfigSetTestLocaltimeFault CDecl Alias "sqlite3ConfigSetTestLocaltimeFault" ( _
    ByVal faultMode As SQLITE_C_INT _
)
    sqlite3ConfigTestLocaltimeFaultValue = faultMode
End Sub

Function sqlite3ConfigTestLocaltimeFault CDecl Alias "sqlite3ConfigTestLocaltimeFault" () As SQLITE_C_INT
    Return sqlite3ConfigTestLocaltimeFaultValue
End Function

Sub sqlite3ConfigSetTestAltLocaltime CDecl Alias "sqlite3ConfigSetTestAltLocaltime" ( _
    ByVal callback As Any Ptr _
)
    sqlite3ConfigTestAltLocaltimeValue = callback
End Sub

Function sqlite3ConfigTestAltLocaltime CDecl Alias "sqlite3ConfigTestAltLocaltime" () As Any Ptr
    Return sqlite3ConfigTestAltLocaltimeValue
End Function

Sub sqlite3ConfigSetTestOnceResetThreshold CDecl Alias "sqlite3ConfigSetTestOnceResetThreshold" ( _
    ByVal threshold As SQLITE_C_INT _
)
    sqlite3ConfigTestOnceResetThresholdValue = threshold
End Sub

Function sqlite3ConfigTestOnceResetThreshold CDecl Alias "sqlite3ConfigTestOnceResetThreshold" () As SQLITE_C_INT
    Return sqlite3ConfigTestOnceResetThresholdValue
End Function

Sub sqlite3ConfigSetTestJsonSelfcheck CDecl Alias "sqlite3ConfigSetTestJsonSelfcheck" ( _
    ByVal enabled As UByte _
)
    sqlite3ConfigTestJsonSelfcheckValue = enabled
End Sub

Function sqlite3ConfigTestJsonSelfcheck CDecl Alias "sqlite3ConfigTestJsonSelfcheck" () As UByte
    Return sqlite3ConfigTestJsonSelfcheckValue
End Function

Function sqlite3UriConfigEnabled CDecl Alias "sqlite3UriConfigEnabled" () As SQLITE_C_INT Export
    Return sqlite3UriOpenDefault
End Function

Function sqlite3ConfigCoreMutexEnabled CDecl Alias "sqlite3ConfigCoreMutexEnabled" () As SQLITE_C_INT Export
    Return sqlite3ConfigCoreMutex
End Function

Function sqlite3ConfigSmallMallocEnabled CDecl Alias "sqlite3ConfigSmallMallocEnabled" () As SQLITE_C_INT Export
    Return sqlite3ConfigSmallMalloc
End Function

Function sqlite3ConfigPmaSizeValue CDecl Alias "sqlite3ConfigPmaSizeValue" () As SQLITE_C_UINT Export
    Return sqlite3ConfigPmaSize
End Function

Function sqlite3ConfigNoVisibleRowidFlagsValue CDecl _
    Alias "sqlite3ConfigNoVisibleRowidFlagsValue" () As u32
#ifdef SQLITE_ALLOW_ROWID_IN_VIEW
    Return sqlite3ConfigNoVisibleRowidFlags
#else
    Return TF_NoVisibleRowid
#endif
End Function

#ifdef SQLITE_ENABLE_SORTER_REFERENCES
Function sqlite3ConfigSorterRefSizeValue CDecl _
    Alias "sqlite3ConfigSorterRefSizeValue" () As SQLITE_C_UINT
    Return sqlite3ConfigSorterRefSize
End Function
#endif

Function sqlite3ConfigMemStatusEnabled CDecl Alias "sqlite3ConfigMemStatusEnabled" () As SQLITE_C_INT Export
    Return sqlite3ConfigMemStatus
End Function

Function sqlite3ConfigShouldUseConnectionMutex CDecl Alias "sqlite3ConfigShouldUseConnectionMutex" ( _
    ByVal openFlags As SQLITE_C_UINT _
) As SQLITE_C_INT Export
    If sqlite3ConfigCoreMutex = 0 Then Return 0
    If (openFlags And SQLITE_OPEN_NOMUTEX) <> 0 Then Return 0
    If (openFlags And SQLITE_OPEN_FULLMUTEX) <> 0 Then Return 1
    Return sqlite3ConfigFullMutex
End Function

Function sqlite3ConfigApplyPageCache CDecl Alias "sqlite3ConfigApplyPageCache" () As SQLITE_C_INT Export
    sqlite3PCacheBufferSetup(sqlite3ConfigPageBuffer, sqlite3ConfigPageSize, _
                             sqlite3ConfigPageCount)
    Return SQLITE_OK
End Function

Sub sqlite3ConfigGetPageCacheSettings CDecl Alias "sqlite3ConfigGetPageCacheSettings" ( _
    ByVal ppBuffer As Any Ptr Ptr, _
    ByVal pSlotSize As SQLITE_C_INT Ptr, _
    ByVal pSlotCount As SQLITE_C_INT Ptr _
) Export
    If ppBuffer <> 0 Then ppBuffer[0] = sqlite3ConfigPageBuffer
    If pSlotSize <> 0 Then pSlotSize[0] = sqlite3ConfigPageSize
    If pSlotCount <> 0 Then pSlotCount[0] = sqlite3ConfigPageCount
End Sub

Sub sqlite3ConfigSetPcacheMethods CDecl Alias "sqlite3ConfigSetPcacheMethods" ( _
    ByVal pMethods As Const SqlitePcacheMethods2 Ptr _
) Export
    If pMethods = 0 Then Return
    sqlite3ConfigPcacheMethods = pMethods[0]
End Sub

Sub sqlite3ConfigGetPcacheMethods CDecl Alias "sqlite3ConfigGetPcacheMethods" ( _
    ByVal pMethods As SqlitePcacheMethods2 Ptr _
) Export
    If pMethods <> 0 Then pMethods[0] = sqlite3ConfigPcacheMethods
End Sub

Sub sqlite3ConfigGetLookaside CDecl Alias "sqlite3ConfigGetLookaside" ( _
    ByVal pSlotSize As SQLITE_C_INT Ptr, _
    ByVal pSlotCount As SQLITE_C_INT Ptr _
) Export
    If pSlotSize <> 0 Then pSlotSize[0] = sqlite3ConfigLookasideSize
    If pSlotCount <> 0 Then pSlotCount[0] = sqlite3ConfigLookasideCount
End Sub

Function sqlite3ConfigMemdbMaxSize CDecl Alias "sqlite3ConfigMemdbMaxSize" () As sqlite3_int64 Export
    Return sqlite3MemdbMaxSizeDefault
End Function

Sub sqlite3ConfigGetLog CDecl Alias "sqlite3ConfigGetLog" ( _
    ByVal pCallback As Any Ptr Ptr, _
    ByVal pArgument As Any Ptr Ptr _
) Export
    If pCallback <> 0 Then pCallback[0] = sqlite3ConfigLogCallback
    sqlite3MemoryBarrier()
    If pArgument <> 0 Then pArgument[0] = sqlite3ConfigLogArgument
End Sub

#ifdef SQLITE_ENABLE_SQLLOG
Function sqlite3SqllogEnabled CDecl Alias "sqlite3SqllogEnabled" () _
    As SQLITE_C_INT
    Return CInt(sqlite3ConfigSqllogCallback <> 0)
End Function

Sub sqlite3SqllogInvoke CDecl Alias "sqlite3SqllogInvoke" ( _
    ByVal pDatabase As sqlite3 Ptr, _
    ByVal zSql As Const ZString Ptr, _
    ByVal eventType As SQLITE_C_INT _
)
    Dim callback As SqliteSqllogCallback = sqlite3ConfigSqllogCallback
    If callback = 0 Then Exit Sub
    callback(sqlite3ConfigSqllogArgument, pDatabase, zSql, eventType)
End Sub
#endif

Function sqlite3_config CDecl Alias "sqlite3_config" ( _
    ByVal operation As SQLITE_C_INT, _
    ... _
) As SQLITE_C_INT Export
    If (sqlite3ConfigIsInitialized() <> 0 OrElse _
        sqlite3MemConfigIsInitialized() <> 0) AndAlso _
       operation <> SQLITE_CONFIG_PCACHE_HDRSZ AndAlso _
       operation <> SQLITE_CONFIG_LOG Then Return SQLITE_MISUSE

    Dim args As Cva_List
    Cva_Start(args, operation)
    Dim rc As SQLITE_C_INT = SQLITE_ERROR
    Select Case operation
    Case SQLITE_CONFIG_LOG
        Dim xLog As Any Ptr = Cva_Arg(args, Any Ptr)
        Dim pLogArgument As Any Ptr = Cva_Arg(args, Any Ptr)
        sqlite3ConfigLogArgument = pLogArgument
        sqlite3MemoryBarrier()
        sqlite3ConfigLogCallback = xLog
        rc = SQLITE_OK
#ifdef SQLITE_ENABLE_SQLLOG
    Case SQLITE_CONFIG_SQLLOG
        sqlite3ConfigSqllogCallback = CPtr( _
            SqliteSqllogCallback, Cva_Arg(args, Any Ptr))
        sqlite3ConfigSqllogArgument = Cva_Arg(args, Any Ptr)
        rc = SQLITE_OK
#endif
    Case SQLITE_CONFIG_MALLOC
        Dim pMethods As Const SqliteMemMethods Ptr = CPtr( _
            Const SqliteMemMethods Ptr, Cva_Arg(args, Any Ptr))
        rc = sqlite3MemConfigSetMethods(pMethods)
    Case SQLITE_CONFIG_GETMALLOC
        Dim pMethods As SqliteMemMethods Ptr = CPtr( _
            SqliteMemMethods Ptr, Cva_Arg(args, Any Ptr))
        If pMethods = 0 Then
            rc = SQLITE_MISUSE
        Else
            If sqlite3MemConfigHasMethods() = 0 Then sqlite3MemSetDefault()
            sqlite3MemConfigGetMethods(pMethods)
            rc = SQLITE_OK
        End If
#if defined(SQLITE_THREADSAFE) AndAlso SQLITE_THREADSAFE > 0
    Case SQLITE_CONFIG_SINGLETHREAD
        sqlite3ConfigCoreMutex = 0
        sqlite3ConfigFullMutex = 0
        rc = SQLITE_OK
    Case SQLITE_CONFIG_MULTITHREAD
        sqlite3ConfigCoreMutex = 1
        sqlite3ConfigFullMutex = 0
        rc = SQLITE_OK
    Case SQLITE_CONFIG_SERIALIZED
        sqlite3ConfigCoreMutex = 1
        sqlite3ConfigFullMutex = 1
        rc = SQLITE_OK
    Case SQLITE_CONFIG_MUTEX
        rc = sqlite3MutexConfigSetMethods(Cva_Arg(args, Any Ptr))
    Case SQLITE_CONFIG_GETMUTEX
        Dim pMutexMethods As Any Ptr = Cva_Arg(args, Any Ptr)
        If pMutexMethods = 0 Then
            rc = SQLITE_MISUSE
        Else
            sqlite3MutexConfigGetMethods(pMutexMethods)
            rc = SQLITE_OK
        End If
#endif
    Case SQLITE_CONFIG_URI
        Dim enabled As SQLITE_C_INT = Cva_Arg(args, SQLITE_C_INT)
        sqlite3UriOpenDefault = CInt(enabled <> 0)
        rc = SQLITE_OK
    Case SQLITE_CONFIG_COVERING_INDEX_SCAN
        sqlite3ConfigCoveringIndexScan = Cva_Arg(args, SQLITE_C_INT)
        rc = SQLITE_OK
    Case SQLITE_CONFIG_MMAP_SIZE
        Dim requestedSize As sqlite3_int64 = Cva_Arg(args, sqlite3_int64)
        Dim maximumSize As sqlite3_int64 = Cva_Arg(args, sqlite3_int64)
        If maximumSize < 0 OrElse maximumSize > SQLITE_MAX_MMAP_SIZE Then _
            maximumSize = SQLITE_MAX_MMAP_SIZE
        If requestedSize < 0 Then requestedSize = SQLITE_DEFAULT_MMAP_SIZE
        If requestedSize > maximumSize Then requestedSize = maximumSize
        sqlite3MaximumMmapSize = maximumSize
        sqlite3ConfiguredMmapSize = requestedSize
        rc = SQLITE_OK
#ifdef SQLITE_OS_WIN
#if SQLITE_OS_WIN
#ifdef SQLITE_WIN32_MALLOC
    Case SQLITE_CONFIG_WIN32_HEAPSIZE
        sqlite3ConfigHeapSize = Cva_Arg(args, SQLITE_C_INT)
        rc = SQLITE_OK
#endif
#endif
#endif
#if defined(SQLITE_ENABLE_MEMSYS3) OrElse defined(SQLITE_ENABLE_MEMSYS5)
    Case SQLITE_CONFIG_HEAP
        sqlite3ConfigHeapBuffer = Cva_Arg(args, Any Ptr)
        sqlite3ConfigHeapSize = Cva_Arg(args, SQLITE_C_INT)
        sqlite3ConfigHeapMinRequest = Cva_Arg(args, SQLITE_C_INT)
        If sqlite3ConfigHeapMinRequest < 1 Then
            sqlite3ConfigHeapMinRequest = 1
        ElseIf sqlite3ConfigHeapMinRequest > (1 Shl 12) Then
            sqlite3ConfigHeapMinRequest = (1 Shl 12)
        End If

        If sqlite3ConfigHeapBuffer = 0 Then
            rc = sqlite3MemConfigResetMethods()
        Else
#if defined(SQLITE_ENABLE_MEMSYS5)
            rc = sqlite3MemConfigSetMethods(sqlite3MemGetMemsys5())
#elseif defined(SQLITE_ENABLE_MEMSYS3)
            rc = sqlite3MemConfigSetMethods(sqlite3MemGetMemsys3())
#endif
        End If
#endif
    Case SQLITE_CONFIG_PAGECACHE
        sqlite3ConfigPageBuffer = Cva_Arg(args, Any Ptr)
        sqlite3ConfigPageSize = Cva_Arg(args, SQLITE_C_INT)
        sqlite3ConfigPageCount = Cva_Arg(args, SQLITE_C_INT)
        rc = SQLITE_OK
    Case SQLITE_CONFIG_PCACHE2
        Dim pMethods As Const SqlitePcacheMethods2 Ptr = CPtr( _
            Const SqlitePcacheMethods2 Ptr, Cva_Arg(args, Any Ptr))
        If pMethods = 0 Then
            rc = SQLITE_MISUSE
        Else
            sqlite3ConfigSetPcacheMethods(pMethods)
            rc = SQLITE_OK
        End If
    Case SQLITE_CONFIG_GETPCACHE2
        Dim pMethods As SqlitePcacheMethods2 Ptr = _
            CPtr(SqlitePcacheMethods2 Ptr, Cva_Arg(args, Any Ptr))
        If pMethods = 0 Then
            rc = SQLITE_MISUSE
        Else
            Dim configuredMethods As SqlitePcacheMethods2
            sqlite3ConfigGetPcacheMethods(@configuredMethods)
            If configuredMethods.xInit = 0 Then sqlite3PCacheSetDefault()
            sqlite3ConfigGetPcacheMethods(pMethods)
            rc = SQLITE_OK
        End If
    Case SQLITE_CONFIG_PCACHE
        ' This deprecated option is an upstream no-op.
        rc = SQLITE_OK
    Case SQLITE_CONFIG_GETPCACHE
        ' The legacy page-cache interface is no longer available.
        rc = SQLITE_ERROR
    Case SQLITE_CONFIG_LOOKASIDE
        sqlite3ConfigLookasideSize = Cva_Arg(args, SQLITE_C_INT)
        sqlite3ConfigLookasideCount = Cva_Arg(args, SQLITE_C_INT)
        rc = SQLITE_OK
    Case SQLITE_CONFIG_MEMSTATUS
        sqlite3ConfigMemStatus = CInt(Cva_Arg(args, SQLITE_C_INT) <> 0)
        rc = SQLITE_OK
    Case SQLITE_CONFIG_SMALL_MALLOC
        sqlite3ConfigSmallMalloc = CInt(Cva_Arg(args, SQLITE_C_INT) <> 0)
        rc = SQLITE_OK
    Case SQLITE_CONFIG_PCACHE_HDRSZ
        Dim pHeaderSize As SQLITE_C_INT Ptr = _
            Cva_Arg(args, SQLITE_C_INT Ptr)
        If pHeaderSize = 0 Then
            rc = SQLITE_MISUSE
        Else
            pHeaderSize[0] = sqlite3HeaderSizeBtree() + _
                sqlite3HeaderSizePcache() + sqlite3HeaderSizePcache1()
            rc = SQLITE_OK
        End If
#ifndef SQLITE_OMIT_DESERIALIZE
    Case SQLITE_CONFIG_MEMDB_MAXSIZE
        sqlite3MemdbMaxSizeDefault = Cva_Arg(args, sqlite3_int64)
        rc = SQLITE_OK
#endif
    Case SQLITE_CONFIG_STMTJRNL_SPILL
        sqlite3ConfiguredStmtJournalSpill = Cva_Arg(args, SQLITE_C_INT)
        rc = SQLITE_OK
    Case SQLITE_CONFIG_PMASZ
        sqlite3ConfigPmaSize = Cva_Arg(args, SQLITE_C_UINT)
        rc = SQLITE_OK
#ifdef SQLITE_ENABLE_SORTER_REFERENCES
    Case SQLITE_CONFIG_SORTERREF_SIZE
        Dim requestedRefSize As SQLITE_C_INT = Cva_Arg(args, SQLITE_C_INT)
        If requestedRefSize < 0 Then _
            requestedRefSize = SQLITE3_FB_DEFAULT_SORTERREF_SIZE
        sqlite3ConfigSorterRefSize = CUInt(requestedRefSize)
        rc = SQLITE_OK
#endif
    Case SQLITE_CONFIG_ROWID_IN_VIEW
        Dim pRowidInView As SQLITE_C_INT Ptr = _
            Cva_Arg(args, SQLITE_C_INT Ptr)
        If pRowidInView = 0 Then
            rc = SQLITE_MISUSE
        Else
#ifdef SQLITE_ALLOW_ROWID_IN_VIEW
            If pRowidInView[0] = 0 Then _
                sqlite3ConfigNoVisibleRowidFlags = TF_NoVisibleRowid
            If pRowidInView[0] = 1 Then _
                sqlite3ConfigNoVisibleRowidFlags = 0
            pRowidInView[0] = CInt(sqlite3ConfigNoVisibleRowidFlags = 0)
#else
            pRowidInView[0] = 0
#endif
            rc = SQLITE_OK
        End If
    End Select
    Cva_End(args)
    Return rc
End Function

/' end of sqlite3_config.bas '/
