/'
    Project: SQLite FreeBASIC port

    File: sqlite3_os_unix_types.bi

    Purpose:

        Define the private Unix VFS records shared by the Unix backend and
        C2FB body candidates for src/os_unix.c.

    Responsibilities:

        - Describe deferred descriptors and inode lock state.
        - Describe WAL shared-memory nodes and the UnixFile VFS record.
        - Include guarded VxWorks and Apple AFP fields and records.
        - Keep the private layouts available to a separate candidate module.

    This file intentionally does NOT contain:

        - VFS callbacks, POSIX imports, or process-wide backend state.
        - Public SQLite ABI structures.
'/ 

#ifndef SQLITE3_OS_UNIX_TYPES_BI
#define SQLITE3_OS_UNIX_TYPES_BI

' Keep these type names visible to each including module: generated candidate
' prototypes need to declare the C-compatible layouts in their parameters.

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_vfs.bi"

#ifndef UNIX_PATH_MAX
#define UNIX_PATH_MAX 4096
#endif

#ifndef SQLITE3_FB_APPLE_LOCKING_STYLE
#define SQLITE3_FB_APPLE_LOCKING_STYLE 0
#ifdef __APPLE__
#ifdef SQLITE_ENABLE_LOCKING_STYLE
#if SQLITE_ENABLE_LOCKING_STYLE
#undef SQLITE3_FB_APPLE_LOCKING_STYLE
#define SQLITE3_FB_APPLE_LOCKING_STYLE 1
#endif
#endif
#endif
#endif

#ifndef SQLITE3_FB_APPLE_PROXY_MAXPATHLEN
#define SQLITE3_FB_APPLE_PROXY_MAXPATHLEN 1024
#endif

/' ------------------------------------------------------------------------- '/
/' POSIX and path records                                                    '/
/' ------------------------------------------------------------------------- '/

Type UnixFlock
    eType As Short
    eWhence As Short
    iStart As sqlite3_int64
    iLength As sqlite3_int64
    iPid As Long
End Type

Type UnixTimeval
    tvSec As sqlite3_int64
    tvUsec As sqlite3_int64
End Type

Type UnixTimespec
    tvSec As sqlite3_int64
    tvNsec As sqlite3_int64
End Type

' Linux x86-64 stat layout. sqlite3_os_init checks its size before registration.
Type UnixStat
    stDev As sqlite3_uint64
    stIno As sqlite3_uint64
    stNlink As sqlite3_uint64
    stMode As u32
    stUid As u32
    stGid As u32
    pad0 As SQLITE_C_INT
    stRdev As sqlite3_uint64
    stSize As sqlite3_int64
    stBlksize As sqlite3_int64
    stBlocks As sqlite3_int64
    atimeSec As sqlite3_int64
    atimeNsec As sqlite3_int64
    mtimeSec As sqlite3_int64
    mtimeNsec As sqlite3_int64
    ctimeSec As sqlite3_int64
    ctimeNsec As sqlite3_int64
    reserved(0 To 2) As sqlite3_int64
End Type

Type DbPath
    rc As SQLITE_C_INT
    nSymlink As SQLITE_C_INT
    zOut As UByte Ptr
    nOut As SQLITE_C_INT
    nUsed As SQLITE_C_INT
End Type

/' ------------------------------------------------------------------------- '/
/' Optional platform records                                                 '/
/' ------------------------------------------------------------------------- '/

#if SQLITE3_FB_APPLE_LOCKING_STYLE
Type AfpLockingContext
    reserved As SQLITE_C_INT
    dbPath As Const ZString Ptr
End Type

Type AfpByteRangeLockPB2
    offset As sqlite3_uint64
    length As sqlite3_uint64
    returnRangeStart As sqlite3_uint64
    unlockFlag As UByte
    startEndFlag As UByte
    fd As SQLITE_C_INT
End Type
#endif

#ifdef OS_VXWORKS
Type VxworksFileId
    pNext As VxworksFileId Ptr
    nRef As SQLITE_C_INT
    nName As SQLITE_C_INT
    zCanonicalName As ZString Ptr
End Type
#endif

/' ------------------------------------------------------------------------- '/
/' Unix descriptor and inode records                                         '/
/' ------------------------------------------------------------------------- '/

Type UnixDeferredFd
    fd As SQLITE_C_INT
    flags As SQLITE_C_INT
    pNext As UnixDeferredFd Ptr
End Type

Type UnixLockInfo
    pNext As UnixLockInfo Ptr
    devId As sqlite3_uint64
    fileId As sqlite3_uint64
    ' The port serializes inode state with one process-wide mutex.
    pLockMutex As Any Ptr
    nRef As u32
    nShared As u32
    nLock As SQLITE_C_INT
    bProcessLock As u8
    pReserved As Any Ptr
    pPending As Any Ptr
    pExclusive As Any Ptr
    pDeferred As UnixDeferredFd Ptr
#if SQLITE3_FB_APPLE_LOCKING_STYLE
    eFileLock As SQLITE_C_INT
    sharedByte As sqlite3_uint64
#endif
#ifdef OS_VXWORKS
    pSem As Any Ptr
    aSemName(0 To UNIX_PATH_MAX + 1) As UByte
#endif
End Type

Type UnixShmNode
    pNext As UnixShmNode Ptr
    pLockInfo As UnixLockInfo Ptr
    fd As SQLITE_C_INT
    nRef As u32
    nRegion As SQLITE_C_INT
    szRegion As SQLITE_C_INT
    apRegion As Any Ptr Ptr
    nShared(0 To SQLITE_SHM_NLOCK - 1) As u32
    apExclusive(0 To SQLITE_SHM_NLOCK - 1) As Any Ptr
    isReadonly As u8
    isUnlocked As u8
    deletePending As u8
End Type

Type UnixFile
    base As sqlite3_file
    pVfs As sqlite3_vfs Ptr
    fd As SQLITE_C_INT
    reusableFlags As SQLITE_C_INT
    lastErrno As SQLITE_C_INT
    lockLevel As SQLITE_C_INT
    pLockInfo As UnixLockInfo Ptr
    pShmNode As UnixShmNode Ptr
    pDeferred As UnixDeferredFd Ptr
    lockingContext As Any Ptr
    deleteOnClose As u8
    readOnly As u8
    readOnlyShm As u8
    ' File identity checks apply to main databases, not temporary files.
    isMainDb As u8
    ctrlFlags As u8
    dirSync As u8
    szChunk As SQLITE_C_INT
    sectorSize As SQLITE_C_INT
    deviceCharacteristics As SQLITE_C_INT
#ifdef SQLITE_ENABLE_LOCKING_STYLE
    openFlags As SQLITE_C_INT
#endif
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    iBusyTimeout As u32
    bBlockOnConnect As SQLITE_C_INT
#endif
#if SQLITE_MAX_MMAP_SIZE > 0
    nFetchOut As SQLITE_C_INT
    mmapSize As sqlite3_int64
    mmapSizeActual As sqlite3_int64
    mmapSizeMax As sqlite3_int64
    pMapRegion As Any Ptr
#endif
#ifdef OS_VXWORKS
    pId As VxworksFileId Ptr
#endif
    zPath(0 To UNIX_PATH_MAX - 1) As UByte
    aShmLock(0 To SQLITE_SHM_NLOCK - 1) As u8
End Type

#if SQLITE3_FB_APPLE_LOCKING_STYLE
Type UnixStatFs
    fBsize As u32
    fIosize As SQLITE_C_INT
    fBlocks As sqlite3_uint64
    fBfree As sqlite3_uint64
    fBavail As sqlite3_uint64
    fFiles As sqlite3_uint64
    fFfree As sqlite3_uint64
    fFsid(0 To 1) As SQLITE_C_INT
    fOwner As SQLITE_C_UINT
    fType As u32
    fFlags As u32
    fFssubtype As u32
    fFstypename(0 To 15) As UByte
    fMntonname(0 To SQLITE3_FB_APPLE_PROXY_MAXPATHLEN - 1) As UByte
    fMntfromname(0 To SQLITE3_FB_APPLE_PROXY_MAXPATHLEN - 1) As UByte
    fFlagsExt As u32
    fReserved(0 To 6) As u32
End Type

Type ProxyLockingContext
    conchFile As UnixFile Ptr
    conchFilePath As ZString Ptr
    lockProxy As UnixFile Ptr
    lockProxyPath As ZString Ptr
    dbPath As ZString Ptr
    conchHeld As SQLITE_C_INT
    failureCount As SQLITE_C_INT
    oldLockingContext As Any Ptr
    pOldMethods As Const sqlite3_io_methods Ptr
End Type
#endif

Type UnixSystemCallEntry
    zName As Const ZString Ptr
    pCurrent As Any Ptr
    pDefault As Any Ptr
End Type

Type UnixOpenProc As Function CDecl (ByVal zPath As Const ZString Ptr, ByVal flags As SQLITE_C_INT, ByVal mode As SQLITE_C_UINT) As SQLITE_C_INT
Type UnixCloseProc As Function CDecl (ByVal fd As SQLITE_C_INT) As SQLITE_C_INT
Type UnixAccessProc As Function CDecl (ByVal zPath As Const ZString Ptr, ByVal mode As SQLITE_C_INT) As SQLITE_C_INT
Type UnixGetcwdProc As Function CDecl (ByVal zBuffer As ZString Ptr, ByVal size As SQLITE_SIZE_T) As ZString Ptr
Type UnixStatProc As Function CDecl (ByVal zPath As Const ZString Ptr, ByVal pStat As UnixStat Ptr) As SQLITE_C_INT
Type UnixFstatProc As Function CDecl (ByVal fd As SQLITE_C_INT, ByVal pStat As UnixStat Ptr) As SQLITE_C_INT
Type UnixFtruncateProc As Function CDecl (ByVal fd As SQLITE_C_INT, ByVal size As sqlite3_int64) As SQLITE_C_INT
Type UnixFcntlProc As Function CDecl (ByVal fd As SQLITE_C_INT, ByVal fcntlCommand As SQLITE_C_INT, ByVal pArgument As Any Ptr) As SQLITE_C_INT
Type UnixReadProc As Function CDecl (ByVal fd As SQLITE_C_INT, ByVal pBuffer As Any Ptr, ByVal amount As SQLITE_SIZE_T) As sqlite3_int64
Type UnixPreadProc As Function CDecl (ByVal fd As SQLITE_C_INT, ByVal pBuffer As Any Ptr, ByVal amount As SQLITE_SIZE_T, ByVal offset As sqlite3_int64) As sqlite3_int64
Type UnixWriteProc As Function CDecl (ByVal fd As SQLITE_C_INT, ByVal pBuffer As Const Any Ptr, ByVal amount As SQLITE_SIZE_T) As sqlite3_int64
Type UnixPwriteProc As Function CDecl (ByVal fd As SQLITE_C_INT, ByVal pBuffer As Const Any Ptr, ByVal amount As SQLITE_SIZE_T, ByVal offset As sqlite3_int64) As sqlite3_int64
Type UnixFchmodProc As Function CDecl (ByVal fd As SQLITE_C_INT, ByVal mode As SQLITE_C_UINT) As SQLITE_C_INT
Type UnixUnlinkProc As Function CDecl (ByVal zPath As Const ZString Ptr) As SQLITE_C_INT
Type UnixOpenDirectoryProc As Function CDecl (ByVal zPath As Const ZString Ptr, ByVal pFd As SQLITE_C_INT Ptr) As SQLITE_C_INT
Type UnixMkdirProc As Function CDecl (ByVal zPath As Const ZString Ptr, ByVal mode As SQLITE_C_UINT) As SQLITE_C_INT
Type UnixRmdirProc As Function CDecl (ByVal zPath As Const ZString Ptr) As SQLITE_C_INT
Type UnixFchownProc As Function CDecl (ByVal fd As SQLITE_C_INT, ByVal uid As SQLITE_C_UINT, ByVal gid As SQLITE_C_UINT) As SQLITE_C_INT
Type UnixGeteuidProc As Function CDecl () As SQLITE_C_UINT
Type UnixMmapProc As Function CDecl (ByVal pAddress As Any Ptr, ByVal nByte As SQLITE_SIZE_T, ByVal protection As SQLITE_C_INT, ByVal mapFlags As SQLITE_C_INT, ByVal fd As SQLITE_C_INT, ByVal offset As sqlite3_int64) As Any Ptr
Type UnixMunmapProc As Function CDecl (ByVal pAddress As Any Ptr, ByVal nByte As SQLITE_SIZE_T) As SQLITE_C_INT
Type UnixGetpagesizeProc As Function CDecl () As SQLITE_C_INT
Type UnixReadlinkProc As Function CDecl (ByVal zPath As Const ZString Ptr, ByVal zBuffer As UByte Ptr, ByVal bufferSize As SQLITE_SIZE_T) As sqlite3_int64
Type UnixLstatProc As Function CDecl (ByVal zPath As Const ZString Ptr, ByVal pStat As UnixStat Ptr) As SQLITE_C_INT
Type UnixIoctlProc As Function CDecl (ByVal fd As SQLITE_C_INT, ByVal request As SQLITE_C_ULONG, ByVal pArgument As Any Ptr) As SQLITE_C_INT

#endif

/' end of sqlite3_os_unix_types.bi '/
