/'
    Project: SQLite FreeBASIC port

    File: sqlite3_os_unix.bas

    Purpose:

        Provide SQLite's Unix VFS callbacks and guarded locking-style variants.

    Responsibilities:

        - Implement file creation, positioned I/O, synchronization, and deletion.
        - Retry interrupted positioned reads and writes while preserving short-I/O results.
        - Generate collision-checked temporary paths for file control and open requests.
        - Release deferred descriptors when the last inode reference closes.
        - Check main-database path identity and expose SQLITE_FCNTL_HAS_MOVED.
        - Implement SQLite's pending, reserved, shared, and exclusive byte locks.
        - Apply optional per-file blocking-lock timeouts and connect-time hints.
        - Register the Apple NFS method table with split-range unlock behavior.
        - Inject configured test I/O failures into Unix VFS operations under SQLITE_TEST.
        - Expose runtime POSIX call overrides through the Unix VFS v3 callbacks.
        - Provide optional dot-file and flock locking styles when SQLITE_ENABLE_LOCKING_STYLE is set.
        - Map database reads on demand when a non-zero mmap limit is configured.
        - Align WAL shared-memory mappings to the host page size.
        - Check shared-memory lock accounting in SQLITE_DEBUG builds.
        - Keep C-named unlock and close adapters for translated Unix VFS callers.
        - Serialize shared inode and SHM bookkeeping through one Unix mutex.
        - Preserve the C-named inode-mutex query helpers for debug call sites.
        - Normalize database path elements and resolve symbolic links.
        - Select database, journal, and WAL creation permissions.
        - Keep journal directory entries durable after file synchronization.
        - Implement Unix shared-library open, symbol lookup, error, and close callbacks.
        - Implement Apple proxy conch acquisition, lock-path switching, file controls, and lock callbacks.
        - Implement the Apple AFP VFS and its byte-range lock callbacks.
        - Implement VxWorks canonical file IDs and named-semaphore locking.
        - Register the Unix VFS or optional K/V VFS according to the selected profile.

    This file intentionally does NOT contain:

        - WAL log and checkpoint processing.
        - Key/value VFS callbacks; sqlite3_os_kv_optional.bas owns that module.
        - Automatic filesystem-based proxy-locking selection.
        - Windows VFS behavior or optional syscall interception.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_mutex.bi"
#include once "sqlite3_vfs.bi"
#include once "sqlite3_pager.bi"
#include once "sqlite3_straccum.bi"
#include once "sqlite3_process_globals.bi"
#include once "sqlite3_os_test.bi"

Declare Function sqlite3ConfigCoreMutexEnabled CDecl _
    Alias "sqlite3ConfigCoreMutexEnabled" () As SQLITE_C_INT

#define SQLITE3_FB_APPLE_LOCKING_STYLE 0
#ifdef __APPLE__
#ifdef SQLITE_ENABLE_LOCKING_STYLE
#if SQLITE_ENABLE_LOCKING_STYLE
#undef SQLITE3_FB_APPLE_LOCKING_STYLE
#define SQLITE3_FB_APPLE_LOCKING_STYLE 1
#endif
#endif
#endif
#include once "sqlite3_debug_assert.bi"

#if defined(SQLITE3_FB_OS_KV_OPTIONAL) OrElse defined(SQLITE3_FB_OS_KV_DEFAULT)
Declare Function sqlite3KvvfsInit CDecl Alias "sqlite3KvvfsInit" () As SQLITE_C_INT
#endif

#ifndef SQLITE_OMIT_LOAD_EXTENSION
#inclib "dl"
#endif

#ifndef SQLITE_TEMP_FILE_PREFIX
#define SQLITE_TEMP_FILE_PREFIX "etilqs_"
#endif
#ifndef SQLITE_POWERSAFE_OVERWRITE
#define SQLITE_POWERSAFE_OVERWRITE 1
#endif
#define UNIXFILE_PERSIST_WAL &H04
#ifndef SQLITE_DISABLE_DIRSYNC
#ifndef _AIX
#define UNIXFILE_DIRSYNC &H08
#else
#define UNIXFILE_DIRSYNC &H00
#endif
#else
#define UNIXFILE_DIRSYNC &H00
#endif
#define UNIXFILE_PSOW &H10
#define UNIXFILE_EXCL &H01      ' Single-process VFS uses one OS lock for its lifetime.
#define UNIXFILE_RDONLY &H02    ' Prevents exclusive mode from taking a write lock.
#define UNIXFILE_DELETE &H20
#define UNIXFILE_URI &H40
#define UNIXFILE_NOLOCK &H80
#if defined(__FB_LINUX__) AndAlso defined(SQLITE_ENABLE_BATCH_ATOMIC_WRITE)
' Linux _IOR encoding for F2FS_IOC_GET_FEATURES, which reads one u32.
#define F2FS_IOC_GET_FEATURES &H8004F50C
#define F2FS_FEATURE_ATOMIC_WRITE &H0004
#endif

Declare Function sqlite3MallocZero CDecl Alias "sqlite3MallocZero" (ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Declare Sub sqlite3_randomness CDecl Alias "sqlite3_randomness" ( _
    ByVal nByte As SQLITE_C_INT, _
    ByVal pBuffer As Any Ptr _
)
Declare Function sqlite3_snprintf CDecl Alias "sqlite3_snprintf" ( _
    ByVal nByte As SQLITE_C_INT, _
    ByVal zBuffer As ZString Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) As ZString Ptr
Declare Function unixGetPid CDecl Alias "getpid" () As SQLITE_C_INT
Declare Function unixDefaultRead CDecl Alias "read" ( _
    ByVal fd As SQLITE_C_INT, _
    ByVal pBuffer As Any Ptr, _
    ByVal amount As SQLITE_SIZE_T _
) As sqlite3_int64
Declare Function unixDefaultWrite CDecl Alias "write" ( _
    ByVal fd As SQLITE_C_INT, _
    ByVal pBuffer As Const Any Ptr, _
    ByVal amount As SQLITE_SIZE_T _
) As sqlite3_int64
Declare Sub unixStrAppendf CDecl Alias "sqlite3_str_appendf" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Sub unixVfsLog CDecl Alias "sqlite3_log" ( _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)

Declare Function unixDefaultOpen CDecl Alias "open" ( _
    ByVal zPath As Const ZString Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal mode As SQLITE_C_UINT _
) As SQLITE_C_INT
Declare Function unixDefaultClose CDecl Alias "close" (ByVal fd As SQLITE_C_INT) As SQLITE_C_INT
Declare Function unixDefaultUnlink CDecl Alias "unlink" (ByVal zPath As Const ZString Ptr) As SQLITE_C_INT
Declare Function unixDefaultAccess CDecl Alias "access" (ByVal zPath As Const ZString Ptr, ByVal mode As SQLITE_C_INT) As SQLITE_C_INT
Declare Function unixDefaultMkdir CDecl Alias "mkdir" (ByVal zPath As Const ZString Ptr, ByVal mode As SQLITE_C_UINT) As SQLITE_C_INT
Declare Function unixDefaultRmdir CDecl Alias "rmdir" (ByVal zPath As Const ZString Ptr) As SQLITE_C_INT
Declare Function unixUtimes CDecl Alias "utimes" (ByVal zPath As Const ZString Ptr, ByVal pTimes As Any Ptr) As SQLITE_C_INT
Declare Function unixDefaultGetcwd CDecl Alias "getcwd" (ByVal zBuffer As ZString Ptr, ByVal size As SQLITE_SIZE_T) As ZString Ptr
Declare Function unixGetenv CDecl Alias "getenv" (ByVal zName As Const ZString Ptr) As Const ZString Ptr
Declare Function unixRealpath CDecl Alias "realpath" (ByVal zPath As Const ZString Ptr, ByVal zResolved As ZString Ptr) As ZString Ptr
#ifndef SQLITE_OMIT_LOAD_EXTENSION
Declare Function unixSystemDlOpen CDecl Alias "dlopen" ( _
    ByVal zFilename As Const ZString Ptr, _
    ByVal flags As SQLITE_C_INT _
) As Any Ptr
Declare Function unixSystemDlSym CDecl Alias "dlsym" ( _
    ByVal pHandle As Any Ptr, _
    ByVal zSymbol As Const ZString Ptr _
) As Any Ptr
Declare Function unixSystemDlError CDecl Alias "dlerror" () As Const ZString Ptr
Declare Function unixSystemDlClose CDecl Alias "dlclose" (ByVal pHandle As Any Ptr) As SQLITE_C_INT
#endif
Declare Function unixDefaultPread CDecl Alias "pread" ( _
    ByVal fd As SQLITE_C_INT, _
    ByVal pBuffer As Any Ptr, _
    ByVal amount As SQLITE_SIZE_T, _
    ByVal offset As sqlite3_int64 _
) As sqlite3_int64
Declare Function unixDefaultPwrite CDecl Alias "pwrite" ( _
    ByVal fd As SQLITE_C_INT, _
    ByVal pBuffer As Const Any Ptr, _
    ByVal amount As SQLITE_SIZE_T, _
    ByVal offset As sqlite3_int64 _
) As sqlite3_int64
Declare Function unixDefaultFtruncate CDecl Alias "ftruncate" (ByVal fd As SQLITE_C_INT, ByVal size As sqlite3_int64) As SQLITE_C_INT
Declare Function unixFsync CDecl Alias "fsync" (ByVal fd As SQLITE_C_INT) As SQLITE_C_INT
Declare Function unixFdatasync CDecl Alias "fdatasync" (ByVal fd As SQLITE_C_INT) As SQLITE_C_INT
Declare Function unixLseek CDecl Alias "lseek" (ByVal fd As SQLITE_C_INT, ByVal offset As sqlite3_int64, ByVal whence As SQLITE_C_INT) As sqlite3_int64
Declare Function unixDefaultFcntl CDecl Alias "fcntl" (ByVal fd As SQLITE_C_INT, ByVal fcntlCommand As SQLITE_C_INT, ByVal pArgument As Any Ptr) As SQLITE_C_INT
Declare Function unixDefaultIoctl CDecl Alias "ioctl" ( _
    ByVal fd As SQLITE_C_INT, _
    ByVal request As SQLITE_C_ULONG, _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT
#if SQLITE3_FB_APPLE_LOCKING_STYLE
Declare Function unixFsctl CDecl Alias "fsctl" ( _
    ByVal zPath As Const ZString Ptr, _
    ByVal request As SQLITE_C_ULONG, _
    ByVal pArgument As Any Ptr, _
    ByVal options As SQLITE_C_UINT _
) As SQLITE_C_INT
Declare Function unixRandom CDecl Alias "random" () As sqlite3_int64
Declare Sub unixSrandomdev CDecl Alias "srandomdev" ()
#endif
Declare Function unixFlock CDecl Alias "flock" (ByVal fd As SQLITE_C_INT, ByVal operation As SQLITE_C_INT) As SQLITE_C_INT
Declare Function unixDefaultFstat CDecl Alias "fstat" (ByVal fd As SQLITE_C_INT, ByVal pStat As Any Ptr) As SQLITE_C_INT
#ifdef OS_VXWORKS
Declare Function unixSemOpen CDecl Alias "sem_open" ( _
    ByVal zName As Const ZString Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal mode As SQLITE_C_UINT, _
    ByVal initialValue As SQLITE_C_UINT _
) As Any Ptr
Declare Function unixSemTryWait CDecl Alias "sem_trywait" (ByVal pSemaphore As Any Ptr) As SQLITE_C_INT
Declare Function unixSemPost CDecl Alias "sem_post" (ByVal pSemaphore As Any Ptr) As SQLITE_C_INT
#endif
Declare Function unixDefaultMmap CDecl Alias "mmap" (ByVal pAddress As Any Ptr, ByVal nByte As SQLITE_SIZE_T, ByVal protection As SQLITE_C_INT, ByVal mapFlags As SQLITE_C_INT, ByVal fd As SQLITE_C_INT, ByVal offset As sqlite3_int64) As Any Ptr
Declare Function unixDefaultMunmap CDecl Alias "munmap" (ByVal pAddress As Any Ptr, ByVal nByte As SQLITE_SIZE_T) As SQLITE_C_INT
Declare Function unixSysconf CDecl Alias "sysconf" (ByVal name As SQLITE_C_INT) As sqlite3_int64
Declare Function unixGetrandom CDecl Alias "getrandom" (ByVal pBuffer As Any Ptr, ByVal amount As SQLITE_SIZE_T, ByVal flags As SQLITE_C_UINT) As sqlite3_int64
Declare Function unixNanosleep CDecl Alias "nanosleep" (ByVal pRequest As Any Ptr, ByVal pRemain As Any Ptr) As SQLITE_C_INT
Declare Function unixGettimeofday CDecl Alias "gettimeofday" (ByVal pTime As Any Ptr, ByVal pZone As Any Ptr) As SQLITE_C_INT
#ifdef __APPLE__
' Darwin exposes its thread-local errno slot through __error().
Declare Function unixErrnoLocation CDecl Alias "__error" () As SQLITE_C_INT Ptr
#else
Declare Function unixErrnoLocation CDecl Alias "__errno_location" () As SQLITE_C_INT Ptr
#endif
Declare Function sqlite3Realloc CDecl Alias "sqlite3Realloc" (ByVal pOld As Any Ptr, ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Function sqlite3ConfigMmapSizeDefault CDecl Alias "sqlite3ConfigMmapSizeDefault" () As sqlite3_int64
Declare Function sqlite3ConfigMmapSizeMaximum CDecl Alias "sqlite3ConfigMmapSizeMaximum" () As sqlite3_int64

Private Const UNIX_S_IFMT As u32 = &HF000
Private Const UNIX_S_IFDIR As u32 = &H4000
Private Const UNIX_S_IFLNK As u32 = &HA000
#ifndef SQLITE_MAX_SYMLINK
#define SQLITE_MAX_SYMLINK 200
#endif
#ifndef SQLITE_DEFAULT_FILE_PERMISSIONS
#define SQLITE_DEFAULT_FILE_PERMISSIONS &H1A4
#endif
#ifndef SQLITE_MINIMUM_FILE_DESCRIPTOR
#define SQLITE_MINIMUM_FILE_DESCRIPTOR 3
#endif
Private Const UNIX_OPEN_READONLY As Long = 0
Private Const UNIX_OPEN_RDWR As Long = 2
Private Const UNIX_OPEN_CREAT As Long = 64
Private Const UNIX_OPEN_EXCL As Long = 128
Private Const UNIX_OPEN_CLOEXEC As Long = 524288
Private Const UNIX_OPEN_NOFOLLOW As Long = 131072
Private Const UNIX_OPEN_DIRECTORY As Long = 65536
#ifndef SQLITE_OMIT_LOAD_EXTENSION
' glibc dlfcn flags used by SQLite's Unix VFS extension loader.
Private Const UNIX_RTLD_NOW As SQLITE_C_INT = 2
Private Const UNIX_RTLD_GLOBAL As SQLITE_C_INT = &H100
#endif
Private Const UNIX_MODE_PRIVATE As ULong = &H180
Private Const UNIX_FILE_MODE_MASK As u32 = &H1FF
Private Const UNIX_F_SETLK As Long = 6
Private Const UNIX_F_GETLK As Long = 5
' Linux fcntl command for a blocking lock, used only for block-on-connect.
Private Const UNIX_F_SETLKW As Long = 7
Private Const UNIX_F_RDLCK As Short = 0
Private Const UNIX_F_WRLCK As Short = 1
Private Const UNIX_F_UNLCK As Short = 2
Private Const UNIX_SEEK_SET As Long = 0
Private Const UNIX_EINTR As Long = 4
Private Const UNIX_EACCES As Long = 13
#ifdef __APPLE__
' Darwin's EAGAIN, ETIMEDOUT, and ENOLCK values differ from Linux.
Private Const UNIX_EAGAIN As Long = 35
#else
Private Const UNIX_EAGAIN As Long = 11
#endif
Private Const UNIX_EPERM As Long = 1
Private Const UNIX_EBUSY As Long = 16
' Linux errno values SQLite treats as filesystem corruption during reads.
Private Const UNIX_EIO As Long = 5
Private Const UNIX_ENXIO As Long = 6
Private Const UNIX_ERANGE As Long = 34
#ifdef __APPLE__
Private Const UNIX_ENOLCK As Long = 77
Private Const UNIX_ETIMEDOUT As Long = 60
#else
Private Const UNIX_ENOLCK As Long = 37
Private Const UNIX_ETIMEDOUT As Long = 110
#endif
Private Const UNIX_ENOENT As Long = 2
Private Const UNIX_ENOSPC As Long = 28
Private Const UNIX_EEXIST As Long = 17
' Linux flock operation values from sys/file.h.
Private Const UNIX_LOCK_EXCLUSIVE As SQLITE_C_INT = 2
Private Const UNIX_LOCK_NONBLOCKING As SQLITE_C_INT = 4
Private Const UNIX_LOCK_RELEASE As SQLITE_C_INT = 8
Private Const UNIX_ACCESS_EXISTS As Long = 0
Private Const UNIX_ACCESS_READ As Long = 4
Private Const UNIX_ACCESS_WRITE As Long = 2
' POSIX file-type fields used by stat()'s S_IFMT and S_IFREG masks.
Private Const UNIX_STAT_TYPE_MASK As u32 = &O170000
Private Const UNIX_STAT_REGULAR As u32 = &O100000
' SQLite reserves consecutive database-file bytes for pending, reserved,
' and shared locks; use the same pending offset as B-tree page allocation.
#define UNIX_PENDING_BYTE PENDING_BYTE
#define UNIX_RESERVED_BYTE (UNIX_PENDING_BYTE + 1)
#define UNIX_SHARED_FIRST (UNIX_PENDING_BYTE + 2)
Private Const UNIX_SHARED_SIZE As sqlite3_int64 = 510
Private Const UNIX_SHM_REGION_SIZE As SQLITE_C_INT = 32 * 1024
' Populate every 4 KiB page in a newly extended WAL shared-memory file.
Private Const UNIX_SHM_FAULT_PAGE_SIZE As SQLITE_C_INT = 4096
Private Const UNIX_SHM_BASE_BYTE As sqlite3_int64 = 120
Private Const UNIX_SHM_DMS_BYTE As sqlite3_int64 = 128
Private Const UNIX_PROT_READ As Long = 1
Private Const UNIX_PROT_WRITE As Long = 2
Private Const UNIX_MAP_SHARED As Long = 1
Private Const UNIX_SC_PAGESIZE As Long = 30
Private Const UNIX_MAP_FAILED As ULongInt = &HFFFFFFFFFFFFFFFF

#include once "sqlite3_os_unix_types.bi"

Declare Function unixDefaultStat CDecl Alias "stat" ( _
    ByVal zPath As Const ZString Ptr, _
    ByVal pStat As UnixStat Ptr _
) As SQLITE_C_INT
Declare Function unixDefaultFchmod CDecl Alias "fchmod" ( _
    ByVal fd As SQLITE_C_INT, _
    ByVal mode As SQLITE_C_UINT _
) As SQLITE_C_INT
Declare Function unixDefaultFchown CDecl Alias "fchown" ( _
    ByVal fd As SQLITE_C_INT, _
    ByVal uid As SQLITE_C_UINT, _
    ByVal gid As SQLITE_C_UINT _
) As SQLITE_C_INT
Declare Function unixDefaultGeteuid CDecl Alias "geteuid" () As SQLITE_C_UINT
Declare Function unixUriParameter CDecl Alias "sqlite3_uri_parameter" ( _
    ByVal zFilename As Const ZString Ptr, _
    ByVal zParameter As Const ZString Ptr _
) As Const ZString Ptr
Declare Function unixUriBoolean CDecl Alias "sqlite3_uri_boolean" ( _
    ByVal zFilename As Const ZString Ptr, _
    ByVal zParameter As Const ZString Ptr, _
    ByVal defaultValue As SQLITE_C_INT _
) As SQLITE_C_INT

Declare Function unixDefaultLstat CDecl Alias "lstat" ( _
    ByVal zPath As Const ZString Ptr, _
    ByVal pStat As UnixStat Ptr _
) As SQLITE_C_INT
Declare Function unixDefaultReadlink CDecl Alias "readlink" ( _
    ByVal zPath As Const ZString Ptr, _
    ByVal zBuffer As UByte Ptr, _
    ByVal bufferSize As SQLITE_SIZE_T _
) As sqlite3_int64
Declare Sub appendAllPathElements CDecl Alias "appendAllPathElements" ( _
    ByVal pPath As DbPath Ptr, _
    ByVal zPath As Const UByte Ptr _
)

Private Const UNIX_SYSCALL_OPEN As Long = 0
Private Const UNIX_SYSCALL_CLOSE As Long = 1
Private Const UNIX_SYSCALL_ACCESS As Long = 2
Private Const UNIX_SYSCALL_GETCWD As Long = 3
Private Const UNIX_SYSCALL_STAT As Long = 4
Private Const UNIX_SYSCALL_FSTAT As Long = 5
Private Const UNIX_SYSCALL_FTRUNCATE As Long = 6
Private Const UNIX_SYSCALL_FCNTL As Long = 7
Private Const UNIX_SYSCALL_READ As Long = 8
Private Const UNIX_SYSCALL_PREAD As Long = 9
Private Const UNIX_SYSCALL_PREAD64 As Long = 10
Private Const UNIX_SYSCALL_WRITE As Long = 11
Private Const UNIX_SYSCALL_PWRITE As Long = 12
Private Const UNIX_SYSCALL_PWRITE64 As Long = 13
Private Const UNIX_SYSCALL_FCHMOD As Long = 14
Private Const UNIX_SYSCALL_FALLOCATE As Long = 15
Private Const UNIX_SYSCALL_UNLINK As Long = 16
Private Const UNIX_SYSCALL_OPENDIRECTORY As Long = 17
Private Const UNIX_SYSCALL_MKDIR As Long = 18
Private Const UNIX_SYSCALL_RMDIR As Long = 19
Private Const UNIX_SYSCALL_FCHOWN As Long = 20
Private Const UNIX_SYSCALL_GETEUID As Long = 21
Private Const UNIX_SYSCALL_MMAP As Long = 22
Private Const UNIX_SYSCALL_MUNMAP As Long = 23
Private Const UNIX_SYSCALL_MREMAP As Long = 24
Private Const UNIX_SYSCALL_GETPAGESIZE As Long = 25
Private Const UNIX_SYSCALL_READLINK As Long = 26
Private Const UNIX_SYSCALL_LSTAT As Long = 27
Private Const UNIX_SYSCALL_IOCTL As Long = 28
Private Const UNIX_SYSCALL_COUNT As Long = 29

' Like upstream, changes to this table are not synchronized with concurrent I/O.
' Configure overrides before database operations begin.
Private Dim Shared unixSystemCallTable(0 To UNIX_SYSCALL_COUNT - 1) As UnixSystemCallEntry
Private Dim Shared unixSystemCallTableReady As SQLITE_C_INT

Private Dim Shared unixLockList As UnixLockInfo Ptr
Private Dim Shared unixShmList As UnixShmNode Ptr
Private Dim Shared unixIoMethods As sqlite3_io_methods
Private Dim Shared nolockIoMethods As sqlite3_io_methods
#ifdef OS_VXWORKS
Private Dim Shared vxworksFileList As VxworksFileId Ptr
Private Dim Shared vxworksMutex As Any Ptr
Private Dim Shared semIoMethods As sqlite3_io_methods
#endif
#ifdef SQLITE_ENABLE_LOCKING_STYLE
Private Dim Shared dotlockIoMethods As sqlite3_io_methods
Private Dim Shared dotlockVfs As sqlite3_vfs
Private Dim Shared flockIoMethods As sqlite3_io_methods
Private Dim Shared flockVfs As sqlite3_vfs
#endif
#if SQLITE3_FB_APPLE_LOCKING_STYLE
Private Dim Shared afpIoMethods As sqlite3_io_methods
Private Dim Shared afpVfs As sqlite3_vfs
Private Dim Shared nfsIoMethods As sqlite3_io_methods
Private Dim Shared nfsVfs As sqlite3_vfs
Private Dim Shared proxyIoMethods As sqlite3_io_methods
#endif
Private Dim Shared unixVfs As sqlite3_vfs
Private Dim Shared unixNoneVfs As sqlite3_vfs
Private Dim Shared unixVfsInitialized As u8
Private Dim Shared unixBigLock As Any Ptr

/' ------------------------------------------------------------------------- '/
/' Overrideable POSIX call wrappers                                           '/
/' ------------------------------------------------------------------------- '/

Private Function unixOpen(ByVal zPath As Const ZString Ptr, ByVal flags As SQLITE_C_INT, ByVal mode As SQLITE_C_UINT) As SQLITE_C_INT
    If unixSystemCallTableReady = 0 Then Return unixDefaultOpen(zPath, flags, mode)
    Dim xCall As UnixOpenProc = CPtr(UnixOpenProc, unixSystemCallTable(UNIX_SYSCALL_OPEN).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(zPath, flags, mode)
End Function

Private Function unixCloseFd(ByVal fd As SQLITE_C_INT) As SQLITE_C_INT
    If unixSystemCallTableReady = 0 Then Return unixDefaultClose(fd)
    Dim xCall As UnixCloseProc = CPtr(UnixCloseProc, unixSystemCallTable(UNIX_SYSCALL_CLOSE).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(fd)
End Function

Private Function unixAccess(ByVal zPath As Const ZString Ptr, ByVal mode As SQLITE_C_INT) As SQLITE_C_INT
    If unixSystemCallTableReady = 0 Then Return unixDefaultAccess(zPath, mode)
    Dim xCall As UnixAccessProc = CPtr(UnixAccessProc, unixSystemCallTable(UNIX_SYSCALL_ACCESS).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(zPath, mode)
End Function

Private Function unixGetcwd(ByVal zBuffer As ZString Ptr, ByVal size As SQLITE_SIZE_T) As ZString Ptr
    If unixSystemCallTableReady = 0 Then Return unixDefaultGetcwd(zBuffer, size)
    Dim xCall As UnixGetcwdProc = CPtr(UnixGetcwdProc, unixSystemCallTable(UNIX_SYSCALL_GETCWD).pCurrent)
    If xCall = 0 Then Return 0
    Return xCall(zBuffer, size)
End Function

Private Function unixStat(ByVal zPath As Const ZString Ptr, ByVal pStat As UnixStat Ptr) As SQLITE_C_INT
    If unixSystemCallTableReady = 0 Then Return unixDefaultStat(zPath, pStat)
    Dim xCall As UnixStatProc = CPtr(UnixStatProc, unixSystemCallTable(UNIX_SYSCALL_STAT).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(zPath, pStat)
End Function

Private Function unixFstat(ByVal fd As SQLITE_C_INT, ByVal pStat As UnixStat Ptr) As SQLITE_C_INT
    If unixSystemCallTableReady = 0 Then Return unixDefaultFstat(fd, pStat)
    Dim xCall As UnixFstatProc = CPtr(UnixFstatProc, unixSystemCallTable(UNIX_SYSCALL_FSTAT).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(fd, pStat)
End Function

Private Function unixFtruncate(ByVal fd As SQLITE_C_INT, ByVal size As sqlite3_int64) As SQLITE_C_INT
    If unixSystemCallTableReady = 0 Then Return unixDefaultFtruncate(fd, size)
    Dim xCall As UnixFtruncateProc = CPtr(UnixFtruncateProc, unixSystemCallTable(UNIX_SYSCALL_FTRUNCATE).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(fd, size)
End Function

Declare Function unixErrno() As SQLITE_C_INT

Private Function unixFcntlRaw(ByVal fd As SQLITE_C_INT, ByVal fcntlCommand As SQLITE_C_INT, ByVal pArgument As Any Ptr) As SQLITE_C_INT
    If unixSystemCallTableReady = 0 Then Return unixDefaultFcntl(fd, fcntlCommand, pArgument)
    Dim xCall As UnixFcntlProc = CPtr(UnixFcntlProc, unixSystemCallTable(UNIX_SYSCALL_FCNTL).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(fd, fcntlCommand, pArgument)
End Function

#ifdef SQLITE_LOCK_TRACE
Declare Sub sqlite3DebugPrintf CDecl Alias "sqlite3DebugPrintf" ( _
    ByVal zFormat As Const ZString Ptr, ... _
)
#if defined(SQLITE_THREADSAFE) AndAlso SQLITE_THREADSAFE > 0
Declare Function unixPthreadSelf CDecl Alias "pthread_self" () As SQLITE_C_ULONG
#endif

Private Function unixLockTraceThreadId() As sqlite3_uint64
#if defined(SQLITE_THREADSAFE) AndAlso SQLITE_THREADSAFE > 0
    Return CULngInt(unixPthreadSelf())
#else
    Return 0
#endif
End Function

Private Function lockTrace( _
    ByVal fd As SQLITE_C_INT, _
    ByVal fcntlCommand As SQLITE_C_INT, _
    ByVal pLock As UnixFlock Ptr _
) As SQLITE_C_INT
    Dim operationName As Const ZString Ptr
    If fcntlCommand = UNIX_F_GETLK Then
        operationName = StrPtr(!"GETLK")
    ElseIf fcntlCommand = UNIX_F_SETLK Then
        operationName = StrPtr(!"SETLK")
    Else
        Dim unknownResult As SQLITE_C_INT = _
            unixFcntlRaw(fd, fcntlCommand, pLock)
        sqlite3DebugPrintf( _
            StrPtr(!"fcntl unknown %d %d %d\n"), _
            fd, fcntlCommand, unknownResult)
        Return unknownResult
    End If
    If pLock = 0 Then Return unixFcntlRaw(fd, fcntlCommand, pLock)

    Dim lockTypeName As Const ZString Ptr
    Select Case pLock->eType
    Case UNIX_F_RDLCK
        lockTypeName = StrPtr(!"RDLCK")
    Case UNIX_F_WRLCK
        lockTypeName = StrPtr(!"WRLCK")
    Case UNIX_F_UNLCK
        lockTypeName = StrPtr(!"UNLCK")
    Case Else
        lockTypeName = StrPtr(!"ERROR")
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("pLock type is a supported fcntl lock"))
#endif
    End Select

#ifdef SQLITE_DEBUG
    If pLock->eWhence <> UNIX_SEEK_SET Then _
        sqlite3DebugAssert(StrPtr("fcntl lock origin is SEEK_SET"))
#endif

    Dim result As SQLITE_C_INT = unixFcntlRaw(fd, fcntlCommand, pLock)
    Dim savedErrno As SQLITE_C_INT = unixErrno()
    sqlite3DebugPrintf( _
        StrPtr(!"fcntl %llu %d %s %s %d %d %d %d\n"), _
        unixLockTraceThreadId(), fd, operationName, lockTypeName, _
        CInt(pLock->iStart), CInt(pLock->iLength), pLock->iPid, result)

    If result = -1 AndAlso fcntlCommand = UNIX_F_SETLK AndAlso _
       (pLock->eType = UNIX_F_RDLCK OrElse pLock->eType = UNIX_F_WRLCK) Then
        Dim conflictingLock As UnixFlock = pLock[0]
        unixFcntlRaw(fd, UNIX_F_GETLK, @conflictingLock)
        Select Case conflictingLock.eType
        Case UNIX_F_RDLCK
            lockTypeName = StrPtr(!"RDLCK")
        Case UNIX_F_WRLCK
            lockTypeName = StrPtr(!"WRLCK")
        Case UNIX_F_UNLCK
            lockTypeName = StrPtr(!"UNLCK")
        Case Else
            lockTypeName = StrPtr(!"ERROR")
        End Select
        sqlite3DebugPrintf( _
            StrPtr(!"fcntl-failure-reason: %s %d %d %d\n"), _
            lockTypeName, CInt(conflictingLock.iStart), _
            CInt(conflictingLock.iLength), conflictingLock.iPid)
    End If

    Dim pErrno As SQLITE_C_INT Ptr = unixErrnoLocation()
    If pErrno <> 0 Then pErrno[0] = savedErrno
    Return result
End Function
#endif

Private Function unixFcntl(ByVal fd As SQLITE_C_INT, ByVal fcntlCommand As SQLITE_C_INT, ByVal pArgument As Any Ptr) As SQLITE_C_INT
#ifdef SQLITE_LOCK_TRACE
    Return lockTrace(fd, fcntlCommand, CPtr(UnixFlock Ptr, pArgument))
#else
    Return unixFcntlRaw(fd, fcntlCommand, pArgument)
#endif
End Function

Private Function unixSystemRead(ByVal fd As SQLITE_C_INT, ByVal pBuffer As Any Ptr, ByVal amount As SQLITE_SIZE_T) As sqlite3_int64
    If unixSystemCallTableReady = 0 Then Return unixDefaultRead(fd, pBuffer, amount)
    Dim xCall As UnixReadProc = CPtr(UnixReadProc, unixSystemCallTable(UNIX_SYSCALL_READ).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(fd, pBuffer, amount)
End Function

Private Function unixPread(ByVal fd As SQLITE_C_INT, ByVal pBuffer As Any Ptr, ByVal amount As SQLITE_SIZE_T, ByVal offset As sqlite3_int64) As sqlite3_int64
    If unixSystemCallTableReady = 0 Then Return unixDefaultPread(fd, pBuffer, amount, offset)
    Dim xCall As UnixPreadProc = CPtr(UnixPreadProc, unixSystemCallTable(UNIX_SYSCALL_PREAD).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(fd, pBuffer, amount, offset)
End Function

Private Function unixWrite(ByVal fd As SQLITE_C_INT, ByVal pBuffer As Const Any Ptr, ByVal amount As SQLITE_SIZE_T) As sqlite3_int64
    If unixSystemCallTableReady = 0 Then Return unixDefaultWrite(fd, pBuffer, amount)
    Dim xCall As UnixWriteProc = CPtr(UnixWriteProc, unixSystemCallTable(UNIX_SYSCALL_WRITE).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(fd, pBuffer, amount)
End Function

Private Function unixPwrite(ByVal fd As SQLITE_C_INT, ByVal pBuffer As Const Any Ptr, ByVal amount As SQLITE_SIZE_T, ByVal offset As sqlite3_int64) As sqlite3_int64
    If unixSystemCallTableReady = 0 Then Return unixDefaultPwrite(fd, pBuffer, amount, offset)
    Dim xCall As UnixPwriteProc = CPtr(UnixPwriteProc, unixSystemCallTable(UNIX_SYSCALL_PWRITE).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(fd, pBuffer, amount, offset)
End Function

Private Function unixFchmod(ByVal fd As SQLITE_C_INT, ByVal mode As SQLITE_C_UINT) As SQLITE_C_INT
    If unixSystemCallTableReady = 0 Then Return unixDefaultFchmod(fd, mode)
    Dim xCall As UnixFchmodProc = CPtr(UnixFchmodProc, unixSystemCallTable(UNIX_SYSCALL_FCHMOD).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(fd, mode)
End Function

Private Function unixUnlink(ByVal zPath As Const ZString Ptr) As SQLITE_C_INT
    If unixSystemCallTableReady = 0 Then Return unixDefaultUnlink(zPath)
    Dim xCall As UnixUnlinkProc = CPtr(UnixUnlinkProc, unixSystemCallTable(UNIX_SYSCALL_UNLINK).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(zPath)
End Function

Private Function unixMkdir(ByVal zPath As Const ZString Ptr, ByVal mode As SQLITE_C_UINT) As SQLITE_C_INT
    If unixSystemCallTableReady = 0 Then Return unixDefaultMkdir(zPath, mode)
    Dim xCall As UnixMkdirProc = CPtr(UnixMkdirProc, unixSystemCallTable(UNIX_SYSCALL_MKDIR).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(zPath, mode)
End Function

Private Function unixRmdir(ByVal zPath As Const ZString Ptr) As SQLITE_C_INT
    If unixSystemCallTableReady = 0 Then Return unixDefaultRmdir(zPath)
    Dim xCall As UnixRmdirProc = CPtr(UnixRmdirProc, unixSystemCallTable(UNIX_SYSCALL_RMDIR).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(zPath)
End Function

Private Function unixFchown(ByVal fd As SQLITE_C_INT, ByVal uid As SQLITE_C_UINT, ByVal gid As SQLITE_C_UINT) As SQLITE_C_INT
    If unixSystemCallTableReady = 0 Then Return unixDefaultFchown(fd, uid, gid)
    Dim xCall As UnixFchownProc = CPtr(UnixFchownProc, unixSystemCallTable(UNIX_SYSCALL_FCHOWN).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(fd, uid, gid)
End Function

Private Function unixGeteuid() As SQLITE_C_UINT
    If unixSystemCallTableReady = 0 Then Return unixDefaultGeteuid()
    Dim xCall As UnixGeteuidProc = CPtr(UnixGeteuidProc, unixSystemCallTable(UNIX_SYSCALL_GETEUID).pCurrent)
    If xCall = 0 Then Return 0
    Return xCall()
End Function

Private Function unixMmap(ByVal pAddress As Any Ptr, ByVal nByte As SQLITE_SIZE_T, ByVal protection As SQLITE_C_INT, ByVal mapFlags As SQLITE_C_INT, ByVal fd As SQLITE_C_INT, ByVal offset As sqlite3_int64) As Any Ptr
    If unixSystemCallTableReady = 0 Then Return unixDefaultMmap(pAddress, nByte, protection, mapFlags, fd, offset)
    Dim xCall As UnixMmapProc = CPtr(UnixMmapProc, unixSystemCallTable(UNIX_SYSCALL_MMAP).pCurrent)
    If xCall = 0 Then Return 0
    Return xCall(pAddress, nByte, protection, mapFlags, fd, offset)
End Function

Private Function unixMunmap(ByVal pAddress As Any Ptr, ByVal nByte As SQLITE_SIZE_T) As SQLITE_C_INT
    If unixSystemCallTableReady = 0 Then Return unixDefaultMunmap(pAddress, nByte)
    Dim xCall As UnixMunmapProc = CPtr(UnixMunmapProc, unixSystemCallTable(UNIX_SYSCALL_MUNMAP).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(pAddress, nByte)
End Function

Private Function unixReadlink(ByVal zPath As Const ZString Ptr, ByVal zBuffer As UByte Ptr, ByVal bufferSize As SQLITE_SIZE_T) As sqlite3_int64
    If unixSystemCallTableReady = 0 Then Return unixDefaultReadlink(zPath, zBuffer, bufferSize)
    Dim xCall As UnixReadlinkProc = CPtr(UnixReadlinkProc, unixSystemCallTable(UNIX_SYSCALL_READLINK).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(zPath, zBuffer, bufferSize)
End Function

Private Function unixLstat(ByVal zPath As Const ZString Ptr, ByVal pStat As UnixStat Ptr) As SQLITE_C_INT
    If unixSystemCallTableReady = 0 Then Return unixDefaultLstat(zPath, pStat)
    Dim xCall As UnixLstatProc = CPtr(UnixLstatProc, unixSystemCallTable(UNIX_SYSCALL_LSTAT).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(zPath, pStat)
End Function

Private Function unixIoctl(ByVal fd As SQLITE_C_INT, ByVal request As SQLITE_C_ULONG, ByVal pArgument As Any Ptr) As SQLITE_C_INT
    If unixSystemCallTableReady = 0 Then Return unixDefaultIoctl(fd, request, pArgument)
    Dim xCall As UnixIoctlProc = CPtr(UnixIoctlProc, unixSystemCallTable(UNIX_SYSCALL_IOCTL).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall(fd, request, pArgument)
End Function

/' ------------------------------------------------------------------------- '/
/' Unix memory-mapped read state                                               '/
/' ------------------------------------------------------------------------- '/

#if SQLITE_MAX_MMAP_SIZE > 0
Private Sub unixUnmapfile CDecl Alias "unixUnmapfile" (ByVal pUnix As UnixFile Ptr)
    If pUnix = 0 OrElse pUnix->pMapRegion = 0 Then Return
    If pUnix->nFetchOut <> 0 Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("no mapped-page references remain before unmap"))
#endif
        Return
    End If

    unixMunmap(pUnix->pMapRegion, CULngInt(pUnix->mmapSizeActual))
    pUnix->pMapRegion = 0
    pUnix->mmapSize = 0
    pUnix->mmapSizeActual = 0
End Sub

Private Sub unixRemapfile CDecl Alias "unixRemapfile" ( _
    ByVal pUnix As UnixFile Ptr, _
    ByVal requestedSize As sqlite3_int64 _
)
    If pUnix = 0 OrElse requestedSize <= 0 OrElse _
       requestedSize > pUnix->mmapSizeMax OrElse pUnix->nFetchOut <> 0 Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("mapped file size and reference count are valid"))
#endif
        Return
    End If

    If pUnix->pMapRegion <> 0 Then
        unixMunmap(pUnix->pMapRegion, CULngInt(pUnix->mmapSizeActual))
        pUnix->pMapRegion = 0
        pUnix->mmapSize = 0
        pUnix->mmapSizeActual = 0
    End If

    Dim protection As SQLITE_C_INT = UNIX_PROT_READ
#ifdef SQLITE_MMAP_READWRITE
    If pUnix->readOnly = 0 Then protection = protection Or UNIX_PROT_WRITE
#endif

    Dim pRegion As Any Ptr = unixMmap( _
        0, CULngInt(requestedSize), protection, UNIX_MAP_SHARED, pUnix->fd, 0)
    If pRegion = 0 OrElse CULngInt(pRegion) = UNIX_MAP_FAILED Then
        Dim pError As SQLITE_C_INT Ptr = unixErrnoLocation()
        Dim errorNumber As SQLITE_C_INT = 0
        If pError <> 0 Then errorNumber = pError[0]
        unixVfsLog(SQLITE_OK, StrPtr(!"os_unix.c: mmap(%s) failed, errno=%d"), _
            CPtr(Const ZString Ptr, @pUnix->zPath(0)), errorNumber)
        pUnix->mmapSizeMax = 0
        Return
    End If

    pUnix->pMapRegion = pRegion
    pUnix->mmapSize = requestedSize
    pUnix->mmapSizeActual = requestedSize
End Sub

Private Function unixMapfile CDecl Alias "unixMapfile" ( _
    ByVal pUnix As UnixFile Ptr, _
    ByVal requestedSize As sqlite3_int64 _
) As SQLITE_C_INT
    If pUnix = 0 Then Return SQLITE_MISUSE
    If pUnix->nFetchOut > 0 Then Return SQLITE_OK

    Dim newSize As sqlite3_int64 = requestedSize
    If newSize < 0 Then
        Dim fileStatus As UnixStat
        If unixFstat(pUnix->fd, @fileStatus) <> 0 Then Return SQLITE_IOERR_FSTAT
        newSize = fileStatus.stSize
    End If
    If newSize < 0 Then Return SQLITE_IOERR_FSTAT
    If newSize > pUnix->mmapSizeMax Then newSize = pUnix->mmapSizeMax

    If newSize = 0 Then
        unixUnmapfile(pUnix)
        Return SQLITE_OK
    End If
    If newSize <> pUnix->mmapSize Then unixRemapfile(pUnix, newSize)
    Return SQLITE_OK
End Function
#endif

Private Function unixFetch CDecl Alias "unixFetch" ( _
    ByVal pFile As Any Ptr, _
    ByVal offset As sqlite3_int64, _
    ByVal amount As SQLITE_C_INT, _
    ByVal ppBuffer As Any Ptr Ptr _
) As SQLITE_C_INT
    If pFile = 0 OrElse ppBuffer = 0 OrElse offset < 0 OrElse amount < 0 Then _
        Return SQLITE_MISUSE
    ppBuffer[0] = 0
#if SQLITE_MAX_MMAP_SIZE > 0
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    If pUnix->mmapSizeMax > 0 Then
        If pUnix->pMapRegion = 0 Then
            Dim rc As SQLITE_C_INT = unixMapfile(pUnix, -1)
            If rc <> SQLITE_OK Then Return rc
        End If

        ' Keep a guard after the requested slice for bounded parser overreads.
        Dim guardSize As sqlite3_int64 = Cast(sqlite3_int64, amount) + 256
        If pUnix->pMapRegion <> 0 AndAlso pUnix->mmapSize >= guardSize AndAlso _
           offset <= pUnix->mmapSize - guardSize AndAlso _
           pUnix->nFetchOut < &H7FFFFFFF Then
            ppBuffer[0] = CPtr(UByte Ptr, pUnix->pMapRegion) + CULngInt(offset)
            pUnix->nFetchOut += 1
        End If
    End If
#endif
    Return SQLITE_OK
End Function

Private Function unixUnfetch CDecl Alias "unixUnfetch" ( _
    ByVal pFile As Any Ptr, _
    ByVal offset As sqlite3_int64, _
    ByVal pBuffer As Any Ptr _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
#if SQLITE_MAX_MMAP_SIZE > 0
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    If pBuffer = 0 Then
        If pUnix->nFetchOut <> 0 Then
#ifdef SQLITE_DEBUG
            sqlite3DebugAssert(StrPtr("all mapped-page references are released before unmap"))
#endif
            Return SQLITE_MISUSE
        End If
        unixUnmapfile(pUnix)
    Else
        If pUnix->nFetchOut <= 0 OrElse pUnix->pMapRegion = 0 OrElse _
           offset < 0 OrElse offset >= pUnix->mmapSize OrElse _
           CPtr(UByte Ptr, pUnix->pMapRegion) + CULngInt(offset) <> pBuffer Then
#ifdef SQLITE_DEBUG
            sqlite3DebugAssert(StrPtr("mapped-page release matches an outstanding fetch"))
#endif
            Return SQLITE_MISUSE
        End If
        pUnix->nFetchOut -= 1
    End If
#else
    If pBuffer <> 0 OrElse offset < 0 Then Return SQLITE_MISUSE
#endif
    Return SQLITE_OK
End Function

Private Sub unixEnterMutex CDecl Alias "unixEnterMutex" ()
    If unixBigLock = 0 Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("unixBigLock != 0"))
#endif
        Exit Sub
    End If
#ifdef SQLITE_DEBUG
    If sqlite3_mutex_notheld(unixBigLock) = 0 Then _
        sqlite3DebugAssert(StrPtr("unixBigLock is not recursively held"))
#endif
    sqlite3_mutex_enter(unixBigLock)
End Sub

Private Sub unixLeaveMutex CDecl Alias "unixLeaveMutex" ()
    If unixBigLock = 0 Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("unixBigLock != 0"))
#endif
        Exit Sub
    End If
#ifdef SQLITE_DEBUG
    If sqlite3_mutex_held(unixBigLock) = 0 Then _
        sqlite3DebugAssert(StrPtr("unixBigLock is held before leave"))
#endif
    sqlite3_mutex_leave(unixBigLock)
End Sub

' The port uses one process-wide mutex for inode and SHM bookkeeping rather
' than the upstream per-inode mutex. Keep the C-named checks tied to that lock.
Private Function unixFileMutexHeld CDecl Alias "unixFileMutexHeld" ( _
    ByVal pFile As UnixFile Ptr _
) As SQLITE_C_INT
    If pFile = 0 OrElse unixBigLock = 0 Then Return 0
    Return sqlite3_mutex_held(unixBigLock)
End Function

Private Function unixFileMutexNotheld CDecl Alias "unixFileMutexNotheld" ( _
    ByVal pFile As UnixFile Ptr _
) As SQLITE_C_INT
    If pFile = 0 OrElse unixBigLock = 0 Then Return 1
    Return sqlite3_mutex_notheld(unixBigLock)
End Function

#ifdef SQLITE_DEBUG
Private Function unixMutexHeld CDecl Alias "unixMutexHeld" () As SQLITE_C_INT
    If unixBigLock = 0 Then Return 0
    Return sqlite3_mutex_held(unixBigLock)
End Function

' This port stores aggregate readers and one exclusive owner instead of a
' linked list of per-client masks. Check the invariant available in that layout.
Private Function assertLockingArrayOk(ByVal pNode As UnixShmNode Ptr) As SQLITE_C_INT
    If pNode = 0 Then Return 0
    For lockIndex As Long = 0 To SQLITE_SHM_NLOCK - 1
        If pNode->apExclusive(lockIndex) <> 0 Then
            If pNode->nShared(lockIndex) <> 0 Then Return 0
            Dim pOwner As UnixFile Ptr = CPtr(UnixFile Ptr, pNode->apExclusive(lockIndex))
            If pOwner->pShmNode <> pNode OrElse _
               pOwner->aShmLock(lockIndex) <> SQLITE_SHM_EXCLUSIVE Then Return 0
        End If
    Next
    Return 1
End Function
#endif

#if defined(SQLITE_TEST) OrElse defined(SQLITE_FORCE_OS_TRACE)
' Keep the lock labels used by SQLite's VFS trace output.
Private Function azFileLock CDecl Alias "azFileLock" (ByVal lockLevel As SQLITE_C_INT) As Const ZString Ptr
    Select Case lockLevel
        Case SQLITE_LOCK_NONE
            Return StrPtr(!"NONE")
        Case SQLITE_LOCK_SHARED
            Return StrPtr(!"SHARED")
        Case SQLITE_LOCK_RESERVED
            Return StrPtr(!"RESERVED")
        Case SQLITE_LOCK_PENDING
            Return StrPtr(!"PENDING")
        Case SQLITE_LOCK_EXCLUSIVE
            Return StrPtr(!"EXCLUSIVE")
    End Select
    Return StrPtr(!"ERROR")
End Function
#endif

Declare Function unixShmUnmapLocked ( _
    ByVal pUnix As UnixFile Ptr, _
    ByVal deleteFlag As SQLITE_C_INT _
) As SQLITE_C_INT

Private Function unixErrno() As SQLITE_C_INT
    Dim pError As SQLITE_C_INT Ptr = unixErrnoLocation()
    If pError = 0 Then Return 0
    Return pError[0]
End Function

Private Function unixErrIsBusy(ByVal errorNumber As SQLITE_C_INT) As SQLITE_C_INT
    Select Case errorNumber
    Case UNIX_EACCES, UNIX_EAGAIN, UNIX_ETIMEDOUT, UNIX_EBUSY, _
         UNIX_EINTR, UNIX_ENOLCK
        Return 1
    Case Else
        Return 0
    End Select
End Function

Private Function unixLockBusyResult(ByVal pFile As UnixFile Ptr) As SQLITE_C_INT
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
#if SQLITE_ENABLE_SETLK_TIMEOUT = 1
    If pFile <> 0 AndAlso pFile->iBusyTimeout <> 0 Then Return SQLITE_BUSY_TIMEOUT
#endif
#endif
    Return SQLITE_BUSY
End Function

Declare Function unixSleep CDecl Alias "unixSleep" ( _
    ByVal pVfs As Any Ptr, _
    ByVal microseconds As SQLITE_C_INT _
) As SQLITE_C_INT

#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
Private Function osSetPosixAdvisoryLock CDecl Alias "osSetPosixAdvisoryLock" ( _
    ByVal fd As SQLITE_C_INT, _
    ByVal pLock As UnixFlock Ptr, _
    ByVal pFile As UnixFile Ptr _
) As SQLITE_C_INT
    If pLock = 0 Then Return -1
    If pFile = 0 OrElse pFile->iBusyTimeout = 0 Then _
        Return unixFcntl(fd, UNIX_F_SETLK, pLock)

#ifdef SQLITE_TEST
    Dim millisecondsRemaining As u32 = pFile->iBusyTimeout
    Dim rc As SQLITE_C_INT = -1
    While millisecondsRemaining > 0
        rc = unixFcntl(fd, UNIX_F_SETLK, pLock)
        If rc = 0 Then Exit While
        ' The upstream test path polls once per millisecond.
        unixSleep(0, 1000)
        millisecondsRemaining -= 1
    Wend
    Return rc
#else
    Dim rc As SQLITE_C_INT = unixFcntl(fd, UNIX_F_SETLK, pLock)
    pFile->iBusyTimeout = 0
    Return rc
#endif
End Function
#endif

Private Function unixSetByteLock( _
    ByVal fd As SQLITE_C_INT, _
    ByVal lockType As Short, _
    ByVal offset As sqlite3_int64, _
    ByVal length As sqlite3_int64, _
    ByVal pFile As UnixFile Ptr = 0 _
) As SQLITE_C_INT

    Dim lockInfo As UnixFlock
    lockInfo.eType = lockType
    lockInfo.eWhence = UNIX_SEEK_SET
    lockInfo.iStart = offset
    lockInfo.iLength = length
    lockInfo.iPid = 0
    Dim rc As SQLITE_C_INT
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    If pFile <> 0 AndAlso pFile->bBlockOnConnect <> 0 AndAlso _
       lockType = UNIX_F_RDLCK AndAlso offset = UNIX_SHARED_FIRST AndAlso _
       length = UNIX_SHARED_SIZE Then
        rc = unixFcntl(fd, UNIX_F_SETLKW, @lockInfo)
    Else
        rc = osSetPosixAdvisoryLock(fd, @lockInfo, pFile)
    End If
#else
    Do
        rc = unixFcntl(fd, UNIX_F_SETLK, @lockInfo)
    Loop While rc < 0 AndAlso unixErrno() = UNIX_EINTR
#endif
    Return rc
End Function

Private Function unixOtherProcessHasWriteLock( _
    ByVal fd As SQLITE_C_INT, _
    ByVal offset As sqlite3_int64, _
    ByVal length As sqlite3_int64 _
) As SQLITE_C_INT

    Dim lockInfo As UnixFlock
    lockInfo.eType = UNIX_F_WRLCK
    lockInfo.eWhence = UNIX_SEEK_SET
    lockInfo.iStart = offset
    lockInfo.iLength = length
    lockInfo.iPid = 0
    Dim rc As SQLITE_C_INT
    Do
        rc = unixFcntl(fd, UNIX_F_GETLK, @lockInfo)
    Loop While rc < 0 AndAlso unixErrno() = UNIX_EINTR
    If rc < 0 Then Return -1
    Return IIf(lockInfo.eType <> UNIX_F_UNLCK, 1, 0)
End Function

Private Sub storeLastErrno( _
    ByVal pUnix As UnixFile Ptr, _
    ByVal errorNumber As SQLITE_C_INT _
)
    If pUnix <> 0 Then pUnix->lastErrno = errorNumber
End Sub

Private Function unixLockInfoFind( _
    ByVal devId As sqlite3_uint64, _
    ByVal fileId As sqlite3_uint64 _
) As UnixLockInfo Ptr
    Dim pInfo As UnixLockInfo Ptr = unixLockList
    While pInfo <> 0
        If pInfo->devId = devId AndAlso pInfo->fileId = fileId Then Return pInfo
        pInfo = pInfo->pNext
    Wend
    Return 0
End Function

Private Function unixLockInfoAcquire( _
    ByVal devId As sqlite3_uint64, _
    ByVal fileId As sqlite3_uint64 _
) As UnixLockInfo Ptr

    unixEnterMutex()
    Dim pInfo As UnixLockInfo Ptr = unixLockInfoFind(devId, fileId)
    If pInfo = 0 Then
        pInfo = CPtr(UnixLockInfo Ptr, sqlite3MallocZero(SizeOf(UnixLockInfo)))
        If pInfo <> 0 Then
            pInfo->devId = devId
            pInfo->fileId = fileId
            pInfo->pLockMutex = unixBigLock
            pInfo->pNext = unixLockList
            unixLockList = pInfo
        End If
    End If
    If pInfo <> 0 Then pInfo->nRef += 1
    unixLeaveMutex()
    Return pInfo
End Function

#ifdef OS_VXWORKS
Private Function vxworksSimplifyName CDecl Alias "vxworksSimplifyName" ( _
    ByVal zName As UByte Ptr, _
    ByVal nameLength As SQLITE_C_INT _
) As SQLITE_C_INT
    If zName = 0 OrElse nameLength < 0 OrElse _
       nameLength >= UNIX_PATH_MAX Then Return -1

    Dim n As SQLITE_C_INT = nameLength
    While n > 1 AndAlso zName[n - 1] = Asc("/")
        n -= 1
    Wend
    Dim i As SQLITE_C_INT = 0
    Dim j As SQLITE_C_INT = 0
    While i < n
        If zName[i] = Asc("/") Then
            If i + 1 < n AndAlso zName[i + 1] = Asc("/") Then
                i += 1
                Continue While
            End If
            If i + 2 < n AndAlso zName[i + 1] = Asc(".") AndAlso _
               zName[i + 2] = Asc("/") Then
                i += 2
                Continue While
            End If
            If i + 3 < n AndAlso zName[i + 1] = Asc(".") AndAlso _
               zName[i + 2] = Asc(".") AndAlso zName[i + 3] = Asc("/") Then
                While j > 0 AndAlso zName[j - 1] <> Asc("/")
                    j -= 1
                Wend
                If j > 0 Then j -= 1
                i += 3
                Continue While
            End If
        End If
        zName[j] = zName[i]
        j += 1
        i += 1
    Wend
    zName[j] = 0
    Return j
End Function

Private Function vxworksFindFileId CDecl Alias "vxworksFindFileId" ( _
    ByVal zAbsoluteName As Const ZString Ptr _
) As VxworksFileId Ptr
    If zAbsoluteName = 0 OrElse zAbsoluteName[0] <> Asc("/") OrElse _
       vxworksMutex = 0 Then Return 0

    Dim pName As Const UByte Ptr = CPtr(Const UByte Ptr, zAbsoluteName)
    Dim nameLength As SQLITE_C_INT = 0
    While nameLength < UNIX_PATH_MAX AndAlso pName[nameLength] <> 0
        nameLength += 1
    Wend
    If nameLength = 0 OrElse nameLength >= UNIX_PATH_MAX Then Return 0

    Dim allocationSize As sqlite3_uint64 = _
        CULngInt(SizeOf(VxworksFileId)) + CULngInt(nameLength) + 1
    If allocationSize > SQLITE_MAX_ALLOCATION_SIZE Then Return 0
    Dim pNew As VxworksFileId Ptr = CPtr( _
        VxworksFileId Ptr, sqlite3MallocZero(allocationSize))
    If pNew = 0 Then Return 0

    Dim pCanonical As UByte Ptr = _
        CPtr(UByte Ptr, pNew) + SizeOf(VxworksFileId)
    pNew->zCanonicalName = CPtr(ZString Ptr, pCanonical)
    For i As SQLITE_C_INT = 0 To nameLength
        pCanonical[i] = pName[i]
    Next
    nameLength = vxworksSimplifyName(pCanonical, nameLength)
    If nameLength < 0 Then
        sqlite3_free(pNew)
        Return 0
    End If

    sqlite3_mutex_enter(vxworksMutex)
    Dim pCandidate As VxworksFileId Ptr = vxworksFileList
    While pCandidate <> 0
        If pCandidate->nName = nameLength Then
            Dim pCandidateName As Const UByte Ptr = _
                CPtr(Const UByte Ptr, pCandidate->zCanonicalName)
            Dim namesMatch As SQLITE_C_INT = -1
            For i As SQLITE_C_INT = 0 To nameLength - 1
                If pCandidateName[i] <> pCanonical[i] Then
                    namesMatch = 0
                    Exit For
                End If
            Next
            If namesMatch <> 0 Then
                If pCandidate->nRef >= &H7FFFFFFF Then
                    sqlite3_mutex_leave(vxworksMutex)
                    sqlite3_free(pNew)
                    Return 0
                End If
                pCandidate->nRef += 1
                sqlite3_mutex_leave(vxworksMutex)
                sqlite3_free(pNew)
                Return pCandidate
            End If
        End If
        pCandidate = pCandidate->pNext
    Wend

    pNew->nRef = 1
    pNew->nName = nameLength
    pNew->pNext = vxworksFileList
    vxworksFileList = pNew
    sqlite3_mutex_leave(vxworksMutex)
    Return pNew
End Function

Private Sub vxworksReleaseFileId CDecl Alias "vxworksReleaseFileId" ( _
    ByVal pId As VxworksFileId Ptr _
)
    If pId = 0 OrElse vxworksMutex = 0 Then Return
    sqlite3_mutex_enter(vxworksMutex)
    If pId->nRef <= 0 Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("VxWorks file ID refcount is positive"))
#endif
        sqlite3_mutex_leave(vxworksMutex)
        Return
    End If
    pId->nRef -= 1
    If pId->nRef = 0 Then
        Dim ppId As VxworksFileId Ptr Ptr = @vxworksFileList
        While ppId[0] <> 0 AndAlso ppId[0] <> pId
            ppId = @ppId[0]->pNext
        Wend
        If ppId[0] = pId Then
            ppId[0] = pId->pNext
            sqlite3_free(pId)
#ifdef SQLITE_DEBUG
        Else
            sqlite3DebugAssert(StrPtr("unreferenced VxWorks file ID remains linked"))
#endif
        End If
    End If
    sqlite3_mutex_leave(vxworksMutex)
End Sub
#endif

Private Function findInodeInfo( _
    ByVal pUnix As UnixFile Ptr, _
    ByVal fd As SQLITE_C_INT, _
    ByVal ppInfo As UnixLockInfo Ptr Ptr _
) As SQLITE_C_INT
    If pUnix = 0 OrElse fd < 0 OrElse ppInfo = 0 Then Return SQLITE_MISUSE
    ppInfo[0] = 0

#ifdef OS_VXWORKS
    If pUnix->pId = 0 Then Return SQLITE_MISUSE
    ppInfo[0] = unixLockInfoAcquire( _
        &HFFFFFFFFFFFFFFFFULL, CULngInt(pUnix->pId))
#else
    Dim statInfo As UnixStat
    If unixFstat(fd, @statInfo) <> 0 Then
        storeLastErrno(pUnix, unixErrno())
        Return SQLITE_IOERR
    End If
    ppInfo[0] = unixLockInfoAcquire(statInfo.stDev, statInfo.stIno)
#endif
    If ppInfo[0] = 0 Then Return SQLITE_NOMEM
    Return SQLITE_OK
End Function

Private Function unixIsSharingShmNode CDecl Alias "unixIsSharingShmNode" ( _
    ByVal pUnix As UnixFile Ptr _
) As SQLITE_C_INT
    If pUnix = 0 OrElse pUnix->pShmNode = 0 Then Return 0
    Dim lockInfo As UnixFlock
    lockInfo.eType = UNIX_F_WRLCK
    lockInfo.eWhence = UNIX_SEEK_SET
    lockInfo.iStart = UNIX_SHM_DMS_BYTE
    lockInfo.iLength = 1
    If unixFcntl(pUnix->pShmNode->fd, UNIX_F_GETLK, @lockInfo) <> 0 Then Return 1
    Return IIf(lockInfo.eType <> UNIX_F_UNLCK, 1, 0)
End Function

/' Apply a POSIX byte-range request after the high-level lock state machine
   has selected the required transition. '/
Private Function unixFileLock CDecl Alias "unixFileLock" ( _
    ByVal pFile As UnixFile Ptr, _
    ByVal pLock As UnixFlock Ptr _
) As SQLITE_C_INT
    If pFile = 0 OrElse pLock = 0 OrElse _
       pFile->pLockInfo = 0 OrElse pFile->fd < 0 Then Return -1

    Dim pInfo As UnixLockInfo Ptr = pFile->pLockInfo
    If (pFile->ctrlFlags And (UNIXFILE_EXCL Or UNIXFILE_RDONLY)) = _
       UNIXFILE_EXCL Then
        If pInfo->bProcessLock = 0 Then
            Dim processLock As UnixFlock
            processLock.eType = UNIX_F_WRLCK
            processLock.eWhence = UNIX_SEEK_SET
            processLock.iStart = UNIX_SHARED_FIRST
            processLock.iLength = UNIX_SHARED_SIZE
            Dim rc As SQLITE_C_INT = unixSetByteLock( _
                pFile->fd, processLock.eType, processLock.iStart, _
                processLock.iLength, pFile)
            If rc < 0 Then Return rc
            pInfo->bProcessLock = 1
            pInfo->nLock += 1
        End If
        Return 0
    End If

    Return unixSetByteLock( _
        pFile->fd, pLock->eType, pLock->iStart, pLock->iLength, pFile)
End Function

Private Function unixApplyFileLock( _
    ByVal pFile As UnixFile Ptr, _
    ByVal lockType As Short, _
    ByVal offset As sqlite3_int64, _
    ByVal length As sqlite3_int64 _
) As SQLITE_C_INT
    Dim lockInfo As UnixFlock
    lockInfo.eType = lockType
    lockInfo.eWhence = UNIX_SEEK_SET
    lockInfo.iStart = offset
    lockInfo.iLength = length
    lockInfo.iPid = 0
    Return unixFileLock(pFile, @lockInfo)
End Function

Private Function unixFileLockInternal(ByVal pFile As UnixFile Ptr, ByVal requested As SQLITE_C_INT) As SQLITE_C_INT
    Dim pInfo As UnixLockInfo Ptr = pFile->pLockInfo
    If pInfo = 0 OrElse pFile->fd < 0 Then Return SQLITE_IOERR_LOCK
    If requested < SQLITE_LOCK_SHARED OrElse requested > SQLITE_LOCK_EXCLUSIVE Then Return SQLITE_MISUSE
    If requested <= pFile->lockLevel Then Return SQLITE_OK

    If pFile->lockLevel < SQLITE_LOCK_SHARED Then
        If (pInfo->pPending <> 0 AndAlso pInfo->pPending <> pFile) OrElse _
           (pInfo->pExclusive <> 0 AndAlso pInfo->pExclusive <> pFile) Then Return SQLITE_BUSY
        If pInfo->nShared = 0 Then
            If unixApplyFileLock(pFile, UNIX_F_RDLCK, UNIX_SHARED_FIRST, UNIX_SHARED_SIZE) < 0 Then
                If unixErrIsBusy(unixErrno()) <> 0 Then Return unixLockBusyResult(pFile)
                Return SQLITE_IOERR_LOCK
            End If
        End If
        Dim hasPending As SQLITE_C_INT = unixOtherProcessHasWriteLock(pFile->fd, UNIX_PENDING_BYTE, 1)
        If hasPending < 0 Then
            If pInfo->nShared = 0 Then unixApplyFileLock(pFile, UNIX_F_UNLCK, UNIX_SHARED_FIRST, UNIX_SHARED_SIZE)
            Return SQLITE_IOERR_LOCK
        ElseIf hasPending <> 0 Then
            If pInfo->nShared = 0 Then unixApplyFileLock(pFile, UNIX_F_UNLCK, UNIX_SHARED_FIRST, UNIX_SHARED_SIZE)
            Return SQLITE_BUSY
        End If
        pInfo->nShared += 1
        pFile->lockLevel = SQLITE_LOCK_SHARED
    End If

    If requested >= SQLITE_LOCK_RESERVED AndAlso pFile->lockLevel < SQLITE_LOCK_RESERVED Then
        If pInfo->pReserved <> 0 AndAlso pInfo->pReserved <> pFile Then Return SQLITE_BUSY
        If unixApplyFileLock(pFile, UNIX_F_WRLCK, UNIX_RESERVED_BYTE, 1) < 0 Then
            If unixErrIsBusy(unixErrno()) <> 0 Then Return unixLockBusyResult(pFile)
            Return SQLITE_IOERR_LOCK
        End If
        pInfo->pReserved = pFile
        pFile->lockLevel = SQLITE_LOCK_RESERVED
    End If

    If requested >= SQLITE_LOCK_PENDING AndAlso pFile->lockLevel < SQLITE_LOCK_PENDING Then
        If pInfo->pPending <> 0 AndAlso pInfo->pPending <> pFile Then Return SQLITE_BUSY
        If unixApplyFileLock(pFile, UNIX_F_WRLCK, UNIX_PENDING_BYTE, 1) < 0 Then
            If unixErrIsBusy(unixErrno()) <> 0 Then Return unixLockBusyResult(pFile)
            Return SQLITE_IOERR_LOCK
        End If
        pInfo->pPending = pFile
        pFile->lockLevel = SQLITE_LOCK_PENDING
    End If

    If requested >= SQLITE_LOCK_EXCLUSIVE AndAlso pFile->lockLevel < SQLITE_LOCK_EXCLUSIVE Then
        If pInfo->nShared > 1 Then Return SQLITE_BUSY
        If unixIsSharingShmNode(pFile) <> 0 Then Return SQLITE_BUSY
        If unixApplyFileLock(pFile, UNIX_F_WRLCK, UNIX_SHARED_FIRST, UNIX_SHARED_SIZE) < 0 Then
            If unixErrIsBusy(unixErrno()) <> 0 Then Return unixLockBusyResult(pFile)
            Return SQLITE_IOERR_LOCK
        End If
        pInfo->pExclusive = pFile
        pFile->lockLevel = SQLITE_LOCK_EXCLUSIVE
    End If

    Return SQLITE_OK
End Function

Private Function unixFileUnlockInternal(ByVal pFile As UnixFile Ptr, ByVal requested As SQLITE_C_INT) As SQLITE_C_INT
    Dim pInfo As UnixLockInfo Ptr = pFile->pLockInfo
    If pInfo = 0 OrElse pFile->fd < 0 Then Return SQLITE_IOERR_UNLOCK
    If requested <> SQLITE_LOCK_NONE AndAlso requested <> SQLITE_LOCK_SHARED Then Return SQLITE_MISUSE
    If requested >= pFile->lockLevel Then Return SQLITE_OK

    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pInfo->pPending = pFile Then
        If unixApplyFileLock(pFile, UNIX_F_UNLCK, UNIX_PENDING_BYTE, 1) < 0 Then rc = SQLITE_IOERR_UNLOCK
        pInfo->pPending = 0
    End If
    If pInfo->pReserved = pFile Then
        If unixApplyFileLock(pFile, UNIX_F_UNLCK, UNIX_RESERVED_BYTE, 1) < 0 Then rc = SQLITE_IOERR_UNLOCK
        pInfo->pReserved = 0
    End If
    If pInfo->pExclusive = pFile Then pInfo->pExclusive = 0

    If requested = SQLITE_LOCK_SHARED Then
        If pFile->lockLevel = SQLITE_LOCK_EXCLUSIVE Then
            If unixApplyFileLock(pFile, UNIX_F_RDLCK, UNIX_SHARED_FIRST, UNIX_SHARED_SIZE) < 0 Then rc = SQLITE_IOERR_UNLOCK
        End If
        pFile->lockLevel = SQLITE_LOCK_SHARED
        Return rc
    End If

    If pInfo->nShared > 1 Then
        If pFile->lockLevel = SQLITE_LOCK_EXCLUSIVE Then
            If unixApplyFileLock(pFile, UNIX_F_RDLCK, UNIX_SHARED_FIRST, UNIX_SHARED_SIZE) < 0 Then rc = SQLITE_IOERR_UNLOCK
        End If
    ElseIf pInfo->nShared = 1 Then
        If unixApplyFileLock(pFile, UNIX_F_UNLCK, UNIX_SHARED_FIRST, UNIX_SHARED_SIZE) < 0 Then rc = SQLITE_IOERR_UNLOCK
    End If
    If pInfo->nShared > 0 Then pInfo->nShared -= 1
    pFile->lockLevel = SQLITE_LOCK_NONE
    Return rc
End Function

Private Function unixPathToZString(ByVal pPath As UByte Ptr) As Const ZString Ptr
    Return CPtr(Const ZString Ptr, pPath)
End Function

Private Function unixPathLogError( _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal zOperation As Const ZString Ptr, _
    ByVal zPath As Const ZString Ptr _
) As SQLITE_C_INT
    unixVfsLog(errorCode, StrPtr(!"os_unix.c: %s(%s) failed, errno=%d"), _
               zOperation, zPath, unixErrno())
    Return errorCode
End Function

Private Function fileHasMoved(ByVal pUnix As UnixFile Ptr) As SQLITE_C_INT
    If pUnix = 0 OrElse pUnix->pLockInfo = 0 Then Return 0
    Dim statInfo As UnixStat
    Dim zPath As Const ZString Ptr = unixPathToZString(@pUnix->zPath(0))
    If unixStat(zPath, @statInfo) <> 0 Then Return 1
    Return IIf(statInfo.stIno <> pUnix->pLockInfo->fileId, 1, 0)
End Function

Private Sub verifyDbFile(ByVal pUnix As UnixFile Ptr)
    If pUnix = 0 OrElse pUnix->isMainDb = 0 Then Return
    Dim statInfo As UnixStat
    Dim zPath As Const ZString Ptr = unixPathToZString(@pUnix->zPath(0))
    If unixFstat(pUnix->fd, @statInfo) <> 0 Then
        unixVfsLog(SQLITE_WARNING, _
            StrPtr("cannot fstat db file %s"), zPath)
        Return
    End If
    If statInfo.stNlink = 0 Then
        unixVfsLog(SQLITE_WARNING, _
            StrPtr("file unlinked while open: %s"), zPath)
        Return
    End If
    If statInfo.stNlink > 1 Then
        unixVfsLog(SQLITE_WARNING, _
            StrPtr("multiple links to file: %s"), zPath)
        Return
    End If
    If fileHasMoved(pUnix) <> 0 Then
        unixVfsLog(SQLITE_WARNING, _
            StrPtr("file renamed while open: %s"), zPath)
    End If
End Sub

Private Sub robust_close( _
    ByVal pUnix As UnixFile Ptr, _
    ByVal fd As SQLITE_C_INT, _
    ByVal lineNumber As SQLITE_C_INT _
)
    ' Do not retry close after EINTR; the descriptor may already be reused.
    If unixCloseFd(fd) = 0 Then Return
    Dim zPath As Const ZString Ptr = StrPtr("")
    If pUnix <> 0 Then zPath = unixPathToZString(@pUnix->zPath(0))
    unixVfsLog(SQLITE_IOERR_CLOSE, _
        StrPtr(!"os_unix.c:%d: (%d) close(%s)"), _
        lineNumber, unixErrno(), zPath)
End Sub

Private Sub closePendingFds(ByVal pUnix As UnixFile Ptr)
    If pUnix = 0 OrElse pUnix->pLockInfo = 0 Then Return
    Dim pInfo As UnixLockInfo Ptr = pUnix->pLockInfo
    Dim pDeferred As UnixDeferredFd Ptr = pInfo->pDeferred
    pInfo->pDeferred = 0
    While pDeferred <> 0
        Dim pNext As UnixDeferredFd Ptr = pDeferred->pNext
        robust_close(pUnix, pDeferred->fd, __LINE__)
        sqlite3_free(pDeferred)
        pDeferred = pNext
    Wend
End Sub

Private Sub setPendingFd CDecl Alias "setPendingFd" ( _
    ByVal pUnix As UnixFile Ptr _
)
    If pUnix = 0 OrElse pUnix->pLockInfo = 0 OrElse pUnix->pDeferred = 0 Then Return
    Dim pInfo As UnixLockInfo Ptr = pUnix->pLockInfo
    pUnix->pDeferred->fd = pUnix->fd
    pUnix->pDeferred->flags = pUnix->reusableFlags
    pUnix->pDeferred->pNext = pInfo->pDeferred
    pInfo->pDeferred = pUnix->pDeferred
    pUnix->fd = -1
    pUnix->pDeferred = 0
End Sub

Private Sub releaseInodeInfo(ByVal pUnix As UnixFile Ptr)
    If pUnix = 0 OrElse pUnix->pLockInfo = 0 Then Return
    Dim pInfo As UnixLockInfo Ptr = pUnix->pLockInfo
    If pInfo->nRef = 0 Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("inode reference count is positive"))
#endif
        Return
    End If

    pInfo->nRef -= 1
    If pInfo->nRef = 0 Then
        Dim ppInfo As UnixLockInfo Ptr Ptr = @unixLockList
        While ppInfo[0] <> 0 AndAlso ppInfo[0] <> pInfo
            ppInfo = @ppInfo[0]->pNext
        Wend
        If ppInfo[0] <> pInfo Then
#ifdef SQLITE_DEBUG
            sqlite3DebugAssert(StrPtr("inode record is linked in the Unix list"))
#endif
            Return
        End If
        ppInfo[0] = pInfo->pNext
        closePendingFds(pUnix)
        sqlite3_free(pInfo)
    End If
    pUnix->pLockInfo = 0
End Sub

Private Sub appendOnePathElement CDecl Alias "appendOnePathElement" ( _
    ByVal pPath As DbPath Ptr, _
    ByVal zName As Const UByte Ptr, _
    ByVal nName As SQLITE_C_INT _
)
    If pPath = 0 Then Exit Sub
    If pPath->rc <> SQLITE_OK Then Exit Sub
    If pPath->zOut = 0 OrElse zName = 0 OrElse nName <= 0 Then
        pPath->rc = SQLITE_ERROR
        Exit Sub
    End If

    If zName[0] = Asc(".") Then
        If nName = 1 Then Exit Sub
        If nName = 2 AndAlso zName[1] = Asc(".") Then
            If pPath->nUsed > 1 Then
                If pPath->zOut[0] <> Asc("/") Then
                    pPath->rc = SQLITE_ERROR
                    Exit Sub
                End If
                Do
                    If pPath->nUsed <= 0 Then
                        pPath->rc = SQLITE_ERROR
                        Exit Sub
                    End If
                    pPath->nUsed -= 1
                Loop While pPath->zOut[pPath->nUsed] <> Asc("/")
            End If
            Exit Sub
        End If
    End If

    If pPath->nUsed < 0 OrElse pPath->nOut <= 0 OrElse _
       CULngInt(pPath->nUsed) + CULngInt(nName) + 2 >= CULngInt(pPath->nOut) Then
        pPath->rc = SQLITE_ERROR
        Exit Sub
    End If

    pPath->zOut[pPath->nUsed] = Asc("/")
    pPath->nUsed += 1
    For i As SQLITE_C_INT = 0 To nName - 1
        pPath->zOut[pPath->nUsed + i] = zName[i]
    Next
    pPath->nUsed += nName
    pPath->zOut[pPath->nUsed] = 0

    Dim zIn As Const ZString Ptr = CPtr(Const ZString Ptr, pPath->zOut)
    Dim statInfo As UnixStat
    If unixLstat(zIn, @statInfo) <> 0 Then
        If unixErrno() <> UNIX_ENOENT Then
            pPath->rc = unixPathLogError(SQLITE_CANTOPEN, StrPtr("lstat"), zIn)
        End If
        Exit Sub
    End If
    If (statInfo.stMode And UNIX_S_IFMT) <> UNIX_S_IFLNK Then Exit Sub

    Dim previousSymlinkCount As SQLITE_C_INT = pPath->nSymlink
    pPath->nSymlink += 1
    If previousSymlinkCount > SQLITE_MAX_SYMLINK Then
        pPath->rc = SQLITE_CANTOPEN
        Exit Sub
    End If

    Dim zLink As ZString * (UNIX_PATH_MAX + 2)
    Dim linkBuffer As UByte Ptr = CPtr(UByte Ptr, @zLink)
    Dim bytesRead As sqlite3_int64 = unixReadlink( _
        zIn, linkBuffer, CULng(SizeOf(zLink) - 2))
    If bytesRead <= 0 OrElse bytesRead >= SizeOf(zLink) - 2 Then
        pPath->rc = unixPathLogError(SQLITE_CANTOPEN, StrPtr("readlink"), zIn)
        Exit Sub
    End If
    linkBuffer[bytesRead] = 0

    If linkBuffer[0] = Asc("/") Then
        pPath->nUsed = 0
    Else
        pPath->nUsed -= nName + 1
    End If
    appendAllPathElements(pPath, linkBuffer)
End Sub

Private Sub appendAllPathElements CDecl Alias "appendAllPathElements" ( _
    ByVal pPath As DbPath Ptr, _
    ByVal zPath As Const UByte Ptr _
)
    If pPath = 0 Then Exit Sub
    If zPath = 0 Then
        pPath->rc = SQLITE_ERROR
        Exit Sub
    End If

    Dim i As SQLITE_C_INT = 0
    Dim j As SQLITE_C_INT = 0
    Do
        While zPath[i] <> 0 AndAlso zPath[i] <> Asc("/")
            i += 1
        Wend
        If i > j Then appendOnePathElement(pPath, zPath + j, i - j)
        If pPath->rc <> SQLITE_OK OrElse zPath[i] = 0 Then Exit Do
        j = i + 1
        i += 1
    Loop
End Sub

Private Function unixBuildFullPath( _
    ByVal zName As Const ZString Ptr, _
    ByVal outputSize As SQLITE_C_INT, _
    ByVal zOutput As ZString Ptr _
) As SQLITE_C_INT
    If zName = 0 OrElse outputSize <= 0 OrElse zOutput = 0 Then Return SQLITE_MISUSE

    Dim path As DbPath
    path.rc = SQLITE_OK
    path.nSymlink = 0
    path.zOut = CPtr(UByte Ptr, zOutput)
    path.nOut = outputSize
    path.nUsed = 0

    If zName[0] <> Asc("/") Then
        Dim zPwd As ZString * (UNIX_PATH_MAX + 2)
        If unixGetcwd(@zPwd, CULng(SizeOf(zPwd) - 2)) = 0 Then
            Return unixPathLogError(SQLITE_CANTOPEN, StrPtr("getcwd"), zName)
        End If
        appendAllPathElements(@path, CPtr(Const UByte Ptr, @zPwd))
    End If
    appendAllPathElements(@path, CPtr(Const UByte Ptr, zName))

    If path.nUsed < 0 OrElse path.nUsed >= path.nOut Then Return SQLITE_CANTOPEN
    path.zOut[path.nUsed] = 0
    If path.rc <> SQLITE_OK OrElse path.nUsed < 2 Then Return SQLITE_CANTOPEN
    If path.nSymlink <> 0 Then Return SQLITE_OK_SYMLINK
    Return SQLITE_OK
End Function

Private Function robustFchown CDecl Alias "robustFchown" ( _
    ByVal fd As SQLITE_C_INT, _
    ByVal uid As SQLITE_C_UINT, _
    ByVal gid As SQLITE_C_UINT _
) As SQLITE_C_INT
    If unixGeteuid() <> 0 Then Return SQLITE_OK
    Return unixFchown(fd, uid, gid)
End Function

Private Function robust_open CDecl Alias "robust_open" ( _
    ByVal zName As Const ZString Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal mode As SQLITE_C_UINT _
) As SQLITE_C_INT
    If zName = 0 Then Return -1
    Dim adjustedMode As SQLITE_C_UINT = _
        IIf(mode <> 0, mode, SQLITE_DEFAULT_FILE_PERMISSIONS)
    Dim fd As SQLITE_C_INT

    Do
        fd = unixOpen(zName, flags Or UNIX_OPEN_CLOEXEC, adjustedMode)
        If fd < 0 Then
            If unixErrno() = UNIX_EINTR Then Continue Do
            Exit Do
        End If
        If fd >= SQLITE_MINIMUM_FILE_DESCRIPTOR Then Exit Do

        If (flags And (UNIX_OPEN_EXCL Or UNIX_OPEN_CREAT)) = _
           (UNIX_OPEN_EXCL Or UNIX_OPEN_CREAT) Then
            unixUnlink(zName)
        End If
        unixCloseFd(fd)
        unixVfsLog(SQLITE_WARNING, _
            StrPtr(!"attempt to open \"%s\" as file descriptor %d"), zName, fd)
        fd = -1

        ' Reserve the low descriptor so the next target open can use a safe one.
        If unixOpen(StrPtr("/dev/null"), UNIX_OPEN_READONLY, mode) < 0 Then Exit Do
    Loop

    If fd >= 0 AndAlso mode <> 0 Then
        Dim statInfo As UnixStat
        If unixFstat(fd, @statInfo) = 0 AndAlso statInfo.stSize = 0 AndAlso _
           (statInfo.stMode And UNIX_FILE_MODE_MASK) <> mode Then
            unixFchmod(fd, mode)
        End If
    End If
    Return fd
End Function

Private Function getFileMode CDecl Alias "getFileMode" ( _
    ByVal zPath As Const ZString Ptr, _
    ByVal pMode As SQLITE_C_UINT Ptr, _
    ByVal pUid As SQLITE_C_UINT Ptr, _
    ByVal pGid As SQLITE_C_UINT Ptr _
) As SQLITE_C_INT
    If zPath = 0 OrElse pMode = 0 OrElse pUid = 0 OrElse pGid = 0 Then _
        Return SQLITE_MISUSE
    Dim statInfo As UnixStat
    If unixStat(zPath, @statInfo) <> 0 Then Return SQLITE_IOERR_FSTAT
    pMode[0] = statInfo.stMode And UNIX_FILE_MODE_MASK
    pUid[0] = statInfo.stUid
    pGid[0] = statInfo.stGid
    Return SQLITE_OK
End Function

Private Function findCreateFileMode CDecl Alias "findCreateFileMode" ( _
    ByVal zPath As Const ZString Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal pMode As SQLITE_C_UINT Ptr, _
    ByVal pUid As SQLITE_C_UINT Ptr, _
    ByVal pGid As SQLITE_C_UINT Ptr _
) As SQLITE_C_INT
    If zPath = 0 OrElse pMode = 0 OrElse pUid = 0 OrElse pGid = 0 Then _
        Return SQLITE_MISUSE
    pMode[0] = 0
    pUid[0] = 0
    pGid[0] = 0

    If (flags And (SQLITE_OPEN_WAL Or SQLITE_OPEN_MAIN_JOURNAL)) <> 0 Then
        Dim pathLength As SQLITE_C_INT = 0
        While pathLength < UNIX_PATH_MAX AndAlso zPath[pathLength] <> 0
            pathLength += 1
        Wend
        If pathLength >= UNIX_PATH_MAX Then Return SQLITE_CANTOPEN

        Dim databasePath As ZString * UNIX_PATH_MAX
        Dim databaseIndex As SQLITE_C_INT = pathLength - 1
        While databaseIndex > 0 AndAlso zPath[databaseIndex] <> Asc(".")
            If zPath[databaseIndex] = Asc("-") Then
                For i As SQLITE_C_INT = 0 To databaseIndex - 1
                    databasePath[i] = zPath[i]
                Next
                databasePath[databaseIndex] = 0
                Return getFileMode(@databasePath, pMode, pUid, pGid)
            End If
            databaseIndex -= 1
        Wend
    ElseIf (flags And SQLITE_OPEN_DELETEONCLOSE) <> 0 Then
        pMode[0] = UNIX_MODE_PRIVATE
    ElseIf (flags And SQLITE_OPEN_URI) <> 0 Then
        Dim zModeOf As Const ZString Ptr = _
            unixUriParameter(zPath, StrPtr("modeof"))
        If zModeOf <> 0 Then Return getFileMode(zModeOf, pMode, pUid, pGid)
    End If
    Return SQLITE_OK
End Function

' The caller holds SQLITE_MUTEX_STATIC_VFS1 while using the returned path.
Private Function unixTempFileDir CDecl Alias "unixTempFileDir" () As Const ZString Ptr
    For directoryIndex As SQLITE_C_INT = 0 To 6
        Dim zDirectory As Const ZString Ptr
        Select Case directoryIndex
        Case 0
            zDirectory = sqlite3_temp_directory
        Case 1
            zDirectory = unixGetenv(StrPtr("SQLITE_TMPDIR"))
        Case 2
            zDirectory = unixGetenv(StrPtr("TMPDIR"))
        Case 3
            zDirectory = StrPtr("/var/tmp")
        Case 4
            zDirectory = StrPtr("/usr/tmp")
        Case 5
            zDirectory = StrPtr("/tmp")
        Case Else
            zDirectory = StrPtr(".")
        End Select

        If zDirectory <> 0 Then
            Dim statInfo As UnixStat
            If unixStat(zDirectory, @statInfo) = 0 AndAlso _
               (statInfo.stMode And UNIX_S_IFMT) = UNIX_S_IFDIR AndAlso _
               unixAccess(zDirectory, UNIX_ACCESS_READ Or UNIX_ACCESS_WRITE) = 0 Then
                Return zDirectory
            End If
        End If
    Next
    Return 0
End Function

Private Function unixGetTempname CDecl Alias "unixGetTempname" ( _
    ByVal nBuffer As SQLITE_C_INT, _
    ByVal zBuffer As ZString Ptr _
) As SQLITE_C_INT
    If zBuffer = 0 Then Return SQLITE_MISUSE
    zBuffer[0] = 0
    If nBuffer <= 2 Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then Return SQLITE_IOERR
#endif

    Dim pTempDirectoryMutex As Any Ptr = _
        sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_VFS1)
    If pTempDirectoryMutex <> 0 Then _
        sqlite3_mutex_enter(pTempDirectoryMutex)

    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim zDirectory As Const ZString Ptr = unixTempFileDir()
    If zDirectory = 0 Then
        rc = SQLITE_IOERR_GETTEMPPATH
    Else
        Dim attemptCount As SQLITE_C_INT = 0
        Dim randomValue As sqlite3_uint64 = 0
        Dim zFormat As String = _
            "%s/" & SQLITE_TEMP_FILE_PREFIX & "%llx%c"
        Do
            sqlite3_randomness(SizeOf(randomValue), @randomValue)
            zBuffer[nBuffer - 2] = 0
            sqlite3_snprintf(nBuffer, zBuffer, StrPtr(zFormat), _
                zDirectory, randomValue, 0)
            Dim pathTruncated As SQLITE_C_INT = _
                IIf(zBuffer[nBuffer - 2] <> 0, 1, 0)
            Dim tooManyAttempts As SQLITE_C_INT = _
                IIf(attemptCount > 10, 1, 0)
            attemptCount += 1
            If pathTruncated <> 0 OrElse tooManyAttempts <> 0 Then
                rc = SQLITE_ERROR
                Exit Do
            End If
            If unixAccess(zBuffer, 0) <> 0 Then Exit Do
        Loop
    End If

    If pTempDirectoryMutex <> 0 Then _
        sqlite3_mutex_leave(pTempDirectoryMutex)
    Return rc
End Function

Private Function unixDefaultOpenDirectory CDecl ( _
    ByVal zFilename As Const ZString Ptr, _
    ByVal pFd As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If zFilename = 0 OrElse pFd = 0 Then Return SQLITE_MISUSE

    Dim zDirectory As ZString * UNIX_PATH_MAX
    Dim pathLength As SQLITE_C_INT = 0
    While pathLength < UNIX_PATH_MAX - 1 AndAlso zFilename[pathLength] <> 0
        zDirectory[pathLength] = zFilename[pathLength]
        pathLength += 1
    Wend
    zDirectory[pathLength] = 0
    Dim directoryIndex As SQLITE_C_INT = pathLength
    While directoryIndex > 0 AndAlso zDirectory[directoryIndex] <> Asc("/")
        directoryIndex -= 1
    Wend
    If directoryIndex > 0 Then
        zDirectory[directoryIndex] = 0
    Else
        If zDirectory[0] <> Asc("/") Then zDirectory[0] = Asc(".")
        zDirectory[1] = 0
    End If

    Dim fd As SQLITE_C_INT = robust_open(@zDirectory, UNIX_OPEN_READONLY, 0)
    pFd[0] = fd
    If fd >= 0 Then Return SQLITE_OK
    Return unixPathLogError(SQLITE_CANTOPEN, StrPtr("openDirectory"), @zDirectory)
End Function

Private Function openDirectory(ByVal zPath As Const ZString Ptr, ByVal pFd As SQLITE_C_INT Ptr) As SQLITE_C_INT
    If unixSystemCallTableReady = 0 Then Return unixDefaultOpenDirectory(zPath, pFd)
    Dim xCall As UnixOpenDirectoryProc = CPtr(UnixOpenDirectoryProc, unixSystemCallTable(UNIX_SYSCALL_OPENDIRECTORY).pCurrent)
    If xCall = 0 Then Return SQLITE_NOTFOUND
    Return xCall(zPath, pFd)
End Function

Private Function robust_ftruncate CDecl Alias "robust_ftruncate" ( _
    ByVal fd As SQLITE_C_INT, _
    ByVal size As sqlite3_int64 _
) As SQLITE_C_INT
#ifdef __FB_ANDROID__
    ' Android ftruncate() uses 32-bit file offsets in this SQLite profile.
    If size > &H7FFFFFFF Then Return SQLITE_OK
#endif
    Dim rc As SQLITE_C_INT
    Do
        rc = unixFtruncate(fd, size)
    Loop While rc < 0 AndAlso unixErrno() = UNIX_EINTR
    Return rc
End Function

Private Function unixDefaultGetpagesize CDecl () As SQLITE_C_INT
    Dim pageSize As sqlite3_int64 = unixSysconf(UNIX_SC_PAGESIZE)
    If pageSize < 0 OrElse pageSize > &H7FFFFFFF Then Return -1
    Return Cast(SQLITE_C_INT, pageSize)
End Function

Private Function unixGetpagesize() As SQLITE_C_INT
    If unixSystemCallTableReady = 0 Then Return unixDefaultGetpagesize()
    Dim xCall As UnixGetpagesizeProc = CPtr(UnixGetpagesizeProc, unixSystemCallTable(UNIX_SYSCALL_GETPAGESIZE).pCurrent)
    If xCall = 0 Then Return -1
    Return xCall()
End Function

Private Function unixSystemOpenFlags(ByVal flags As SQLITE_C_INT, ByVal readOnly As SQLITE_C_INT) As SQLITE_C_INT
    Dim result As SQLITE_C_INT = UNIX_OPEN_CLOEXEC
    If readOnly <> 0 Then
        result = result Or UNIX_OPEN_READONLY
    Else
        result = result Or UNIX_OPEN_RDWR
    End If
    If (flags And SQLITE_OPEN_CREATE) <> 0 AndAlso readOnly = 0 Then result = result Or UNIX_OPEN_CREAT
    If (flags And SQLITE_OPEN_EXCLUSIVE) <> 0 AndAlso (flags And SQLITE_OPEN_CREATE) <> 0 Then result = result Or UNIX_OPEN_EXCL
    If (flags And SQLITE_OPEN_NOFOLLOW) <> 0 Then result = result Or UNIX_OPEN_NOFOLLOW
    Return result
End Function

Private Function findReusableFd CDecl Alias "findReusableFd" ( _
    ByVal zPath As Const ZString Ptr, _
    ByVal flags As SQLITE_C_INT _
) As UnixDeferredFd Ptr
    If zPath = 0 Then Return 0
    Dim pUnused As UnixDeferredFd Ptr = 0
    Dim statInfo As UnixStat

    unixEnterMutex()
    If unixLockList <> 0 AndAlso unixStat(zPath, @statInfo) = 0 Then
        Dim pInfo As UnixLockInfo Ptr = unixLockList
        While pInfo <> 0 AndAlso _
              (pInfo->devId <> statInfo.stDev OrElse pInfo->fileId <> statInfo.stIno)
            pInfo = pInfo->pNext
        Wend
        If pInfo <> 0 Then
            Dim matchingFlags As SQLITE_C_INT = flags And _
                (SQLITE_OPEN_READONLY Or SQLITE_OPEN_READWRITE)
            Dim ppDeferred As UnixDeferredFd Ptr Ptr = @pInfo->pDeferred
            While ppDeferred[0] <> 0 AndAlso _
                  ppDeferred[0]->flags <> matchingFlags
                ppDeferred = @ppDeferred[0]->pNext
            Wend
            If ppDeferred[0] <> 0 Then
                pUnused = ppDeferred[0]
                ppDeferred[0] = pUnused->pNext
                pUnused->pNext = 0
            End If
        End If
    End If
    unixLeaveMutex()
    Return pUnused
End Function

#ifdef SQLITE_ENABLE_LOCKING_STYLE
Private Function dotlockCreatePath(ByVal pUnix As UnixFile Ptr) As Any Ptr
    If pUnix = 0 Then Return 0
    Dim pathLength As sqlite3_uint64 = 0
    While pathLength < UNIX_PATH_MAX AndAlso pUnix->zPath(pathLength) <> 0
        pathLength += 1
    Wend
    If pathLength = 0 OrElse pathLength >= UNIX_PATH_MAX Then Return 0
    If pathLength > SQLITE_MAX_ALLOCATION_SIZE - 6 Then Return 0

    Dim nByte As sqlite3_uint64 = pathLength + 6
    Dim pLockPath As UByte Ptr = CPtr(UByte Ptr, sqlite3MallocZero(nByte))
    If pLockPath = 0 Then Return 0
    For i As sqlite3_uint64 = 0 To pathLength - 1
        pLockPath[i] = pUnix->zPath(i)
    Next
    pLockPath[pathLength] = Asc(".")
    pLockPath[pathLength + 1] = Asc("l")
    pLockPath[pathLength + 2] = Asc("o")
    pLockPath[pathLength + 3] = Asc("c")
    pLockPath[pathLength + 4] = Asc("k")
    Return pLockPath
End Function
#endif

#ifdef OS_VXWORKS
Private Function vxworksIoFinderImpl CDecl Alias "vxworksIoFinderImpl" ( _
    ByVal zFilename As Const ZString Ptr, _
    ByVal pFile As UnixFile Ptr _
) As sqlite3_io_methods Ptr
    If zFilename = 0 OrElse pFile = 0 Then Return @nolockIoMethods

    Dim lockInfo As UnixFlock
    lockInfo.iLength = 1
    lockInfo.iStart = 0
    lockInfo.eWhence = UNIX_SEEK_SET
    lockInfo.eType = UNIX_F_RDLCK
    If unixFcntl(pFile->fd, UNIX_F_GETLK, @lockInfo) <> -1 Then _
        Return @unixIoMethods
    Return @semIoMethods
End Function
#endif

/' Initialize the UnixFile methods and inode state after its descriptor opens. '/
Private Function fillInUnixFile CDecl Alias "fillInUnixFile" ( _
    ByVal pVfs As Any Ptr, _
    ByVal fd As SQLITE_C_INT, _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal zFilename As Const ZString Ptr, _
    ByVal ctrlFlags As SQLITE_C_INT _
) As SQLITE_C_INT
    If pVfs = 0 OrElse pFile = 0 OrElse fd < 0 Then Return SQLITE_MISUSE
    If zFilename = 0 AndAlso (ctrlFlags And UNIXFILE_NOLOCK) = 0 Then _
        Return SQLITE_MISUSE

    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    pUnix->pVfs = CPtr(sqlite3_vfs Ptr, pVfs)
    pUnix->fd = fd
    pUnix->ctrlFlags = CByte(ctrlFlags And &HFF)
#ifdef OS_VXWORKS
    pUnix->pId = 0
    If zFilename <> 0 Then
        pUnix->pId = vxworksFindFileId(zFilename)
        If pUnix->pId = 0 Then Return SQLITE_NOMEM
    End If
#endif

    Dim pLockingStyle As sqlite3_io_methods Ptr = 0
    If (ctrlFlags And UNIXFILE_NOLOCK) <> 0 Then
        pUnix->lockingContext = 0
        pUnix->pLockInfo = 0
        pLockingStyle = @nolockIoMethods
    Else
#ifdef SQLITE_ENABLE_LOCKING_STYLE
        If pVfs = @dotlockVfs Then
            pUnix->lockingContext = dotlockCreatePath(pUnix)
            If pUnix->lockingContext = 0 Then Return SQLITE_NOMEM
#if SQLITE3_FB_APPLE_LOCKING_STYLE
        ElseIf pVfs = @afpVfs Then
            Dim pContext As AfpLockingContext Ptr = CPtr( _
                AfpLockingContext Ptr, _
                sqlite3MallocZero(SizeOf(AfpLockingContext)))
            If pContext = 0 Then Return SQLITE_NOMEM
            pContext->dbPath = CPtr(ZString Ptr, zFilename)
            pContext->reserved = 0
            pUnix->lockingContext = pContext
            unixSrandomdev()
#endif
        Else
            pUnix->lockingContext = 0
        End If
#else
        pUnix->lockingContext = 0
#endif

#ifdef OS_VXWORKS
        pLockingStyle = vxworksIoFinderImpl(zFilename, pUnix)
#else
#ifdef SQLITE_ENABLE_LOCKING_STYLE
        If pVfs = @dotlockVfs Then
            pLockingStyle = @dotlockIoMethods
        ElseIf pVfs = @flockVfs Then
            pLockingStyle = @flockIoMethods
#if SQLITE3_FB_APPLE_LOCKING_STYLE
        ElseIf pVfs = @nfsVfs Then
            pLockingStyle = @nfsIoMethods
        ElseIf pVfs = @afpVfs Then
            pLockingStyle = @afpIoMethods
#endif
        Else
            pLockingStyle = @unixIoMethods
        End If
#else
        pLockingStyle = @unixIoMethods
#endif
#endif
        If pLockingStyle = 0 Then Return SQLITE_ERROR

        Dim pInfo As UnixLockInfo Ptr = 0
        Dim rc As SQLITE_C_INT = findInodeInfo(pUnix, fd, @pInfo)
        If rc <> SQLITE_OK Then
#ifdef SQLITE_ENABLE_LOCKING_STYLE
            If pUnix->lockingContext <> 0 Then
                sqlite3_free(pUnix->lockingContext)
                pUnix->lockingContext = 0
            End If
#endif
#ifdef OS_VXWORKS
            If pUnix->pId <> 0 Then
                vxworksReleaseFileId(pUnix->pId)
                pUnix->pId = 0
            End If
#endif
            Return rc
        End If
        pUnix->pLockInfo = pInfo

#ifdef OS_VXWORKS
        If pLockingStyle = @semIoMethods AndAlso pInfo->pSem = 0 Then
            unixEnterMutex()
            Dim zSemaphoreName As ZString Ptr = _
                CPtr(ZString Ptr, @pInfo->aSemName(0))
            sqlite3_snprintf( _
                SizeOf(pInfo->aSemName), zSemaphoreName, _
                StrPtr("/%s.sem"), pUnix->pId->zCanonicalName)
            Dim semaphoreIndex As SQLITE_C_INT = 1
            Dim pSemaphoreName As UByte Ptr = @pInfo->aSemName(0)
            While pSemaphoreName[semaphoreIndex] <> 0
                If pSemaphoreName[semaphoreIndex] = Asc("/") Then _
                    pSemaphoreName[semaphoreIndex] = Asc("_")
                semaphoreIndex += 1
            Wend
            Dim pSemaphore As Any Ptr = unixSemOpen( _
                zSemaphoreName, UNIX_OPEN_CREAT, &O666, 1)
            If pSemaphore = CPtr(Any Ptr, -1) Then
                pInfo->aSemName(0) = 0
                rc = SQLITE_NOMEM
            Else
                pInfo->pSem = pSemaphore
            End If
            unixLeaveMutex()
            If rc <> SQLITE_OK Then
                unixEnterMutex()
                releaseInodeInfo(pUnix)
                unixLeaveMutex()
                If pUnix->pId <> 0 Then
                    vxworksReleaseFileId(pUnix->pId)
                    pUnix->pId = 0
                End If
                Return rc
            End If
        End If
#endif
    End If
    pUnix->base.pMethods = pLockingStyle

    verifyDbFile(pUnix)
#ifdef SQLITE_TEST
    sqlite3_open_file_count += 1
#endif
    Return SQLITE_OK
End Function

Private Function unixOpenFileInternal ( _
    ByVal pVfs As Any Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal pOutFlags As SQLITE_C_INT Ptr, _
    ByVal allowReusableDescriptor As SQLITE_C_INT _
) As SQLITE_C_INT

    If pFile = 0 Then Return SQLITE_MISUSE
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    pUnix->pVfs = CPtr(sqlite3_vfs Ptr, pVfs)
    pUnix->fd = -1
    pUnix->reusableFlags = 0
    pUnix->lastErrno = 0
    pUnix->lockLevel = SQLITE_LOCK_NONE
    pUnix->pLockInfo = 0
    pUnix->pShmNode = 0
    pUnix->pDeferred = 0
#ifdef OS_VXWORKS
    pUnix->pId = 0
#endif
    pUnix->lockingContext = 0
    pUnix->deleteOnClose = 0
    pUnix->readOnly = 0
    pUnix->readOnlyShm = 0
    pUnix->isMainDb = 0
    pUnix->ctrlFlags = 0
    pUnix->dirSync = 0
    pUnix->szChunk = 0
    pUnix->sectorSize = 0
    pUnix->deviceCharacteristics = 0
#ifdef SQLITE_ENABLE_LOCKING_STYLE
    pUnix->openFlags = 0
#endif
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    pUnix->iBusyTimeout = 0
    pUnix->bBlockOnConnect = 0
#endif
#if SQLITE_MAX_MMAP_SIZE > 0
    pUnix->nFetchOut = 0
    pUnix->mmapSize = 0
    pUnix->mmapSizeActual = 0
    pUnix->mmapSizeMax = sqlite3ConfigMmapSizeDefault()
    If pUnix->mmapSizeMax > SQLITE_MAX_MMAP_SIZE Then _
        pUnix->mmapSizeMax = SQLITE_MAX_MMAP_SIZE
    pUnix->pMapRegion = 0
#endif

    Dim zNameBuffer As ZString * UNIX_PATH_MAX
    Dim fd As SQLITE_C_INT = -1
    Dim pDeferred As UnixDeferredFd Ptr = 0
    Dim tempFile As SQLITE_C_INT = 0
    Dim openedReadOnly As SQLITE_C_INT = 0
    Dim createMode As SQLITE_C_UINT = 0
    Dim fileUid As SQLITE_C_UINT = 0
    Dim fileGid As SQLITE_C_UINT = 0
    If zName = 0 Then
        Dim tempNameRc As SQLITE_C_INT = unixGetTempname( _
            UNIX_PATH_MAX - 1, @zNameBuffer)
        If tempNameRc <> SQLITE_OK Then Return tempNameRc
        zName = @zNameBuffer
        tempFile = 1
    End If

    openedReadOnly = IIf((flags And SQLITE_OPEN_READWRITE) = 0, 1, 0)

    If zName <> 0 AndAlso _
       ((flags And SQLITE_OPEN_MAIN_DB) <> 0 OrElse _
        allowReusableDescriptor <> 0) Then
        pDeferred = findReusableFd(zName, flags)
        If pDeferred <> 0 Then
            fd = pDeferred->fd
        Else
            pDeferred = CPtr(UnixDeferredFd Ptr, _
                sqlite3MallocZero(SizeOf(UnixDeferredFd)))
            If pDeferred = 0 Then Return SQLITE_NOMEM
            pDeferred->fd = -1
        End If
    End If

    If fd < 0 Then
        Dim modeRc As SQLITE_C_INT = findCreateFileMode( _
            zName, flags, @createMode, @fileUid, @fileGid)
        If modeRc <> SQLITE_OK Then
            If pDeferred <> 0 Then sqlite3_free(pDeferred)
            Return modeRc
        End If

        fd = robust_open(zName, unixSystemOpenFlags(flags, openedReadOnly), createMode)
        If fd < 0 AndAlso openedReadOnly = 0 Then
            flags = (flags And Not (SQLITE_OPEN_READWRITE Or SQLITE_OPEN_CREATE)) Or _
                    SQLITE_OPEN_READONLY
            openedReadOnly = 1
            Dim pReadOnly As UnixDeferredFd Ptr = findReusableFd(zName, flags)
            If pReadOnly <> 0 Then
                fd = pReadOnly->fd
                If pDeferred = 0 Then
                    pDeferred = pReadOnly
                Else
                    sqlite3_free(pReadOnly)
                End If
            Else
                fd = robust_open(zName, unixSystemOpenFlags(flags, 1), createMode)
            End If
        End If
    End If
    If fd < 0 Then
        If pDeferred <> 0 Then sqlite3_free(pDeferred)
        Return SQLITE_CANTOPEN
    End If

    If pDeferred = 0 Then
        pDeferred = CPtr(UnixDeferredFd Ptr, _
            sqlite3MallocZero(SizeOf(UnixDeferredFd)))
        If pDeferred = 0 Then
            unixCloseFd(fd)
            If tempFile <> 0 Then unixUnlink(@zNameBuffer)
            Return SQLITE_NOMEM
        End If
        pDeferred->fd = -1
    End If
    pDeferred->flags = flags And _
        (SQLITE_OPEN_READONLY Or SQLITE_OPEN_READWRITE)

    If createMode <> 0 AndAlso _
       (flags And (SQLITE_OPEN_WAL Or SQLITE_OPEN_MAIN_JOURNAL)) <> 0 Then
        robustFchown(fd, fileUid, fileGid)
    End If

#ifndef SQLITE_DISABLE_DIRSYNC
    If (flags And SQLITE_OPEN_CREATE) <> 0 AndAlso _
       (flags And (SQLITE_OPEN_SUPER_JOURNAL Or SQLITE_OPEN_MAIN_JOURNAL Or SQLITE_OPEN_WAL)) <> 0 Then
        pUnix->dirSync = 1
    End If
#endif

    Dim zStoredPath As Const ZString Ptr = IIf(tempFile <> 0, @zNameBuffer, zName)
    Dim rc As SQLITE_C_INT = unixBuildFullPath(zStoredPath, UNIX_PATH_MAX, CPtr(ZString Ptr, @pUnix->zPath(0)))
    If rc <> SQLITE_OK AndAlso rc <> SQLITE_OK_SYMLINK Then
        sqlite3_free(pDeferred)
        unixCloseFd(fd)
        If tempFile <> 0 Then unixUnlink(@zNameBuffer)
        Return rc
    End If

    pUnix->fd = fd
    pUnix->reusableFlags = flags And _
        (SQLITE_OPEN_READONLY Or SQLITE_OPEN_READWRITE)
#ifdef SQLITE_ENABLE_LOCKING_STYLE
    pUnix->openFlags = unixSystemOpenFlags(flags, openedReadOnly)
#endif
    pUnix->pDeferred = pDeferred
    pUnix->deleteOnClose = IIf(tempFile <> 0 OrElse (flags And SQLITE_OPEN_DELETEONCLOSE) <> 0, 1, 0)
    pUnix->readOnly = openedReadOnly
    pUnix->isMainDb = CByte(IIf( _
        tempFile = 0 AndAlso (flags And SQLITE_OPEN_MAIN_DB) <> 0, 1, 0))
    Dim ctrlFlags As SQLITE_C_INT = 0
    If pUnix->deleteOnClose <> 0 Then ctrlFlags Or= UNIXFILE_DELETE
    If pUnix->readOnly <> 0 Then ctrlFlags Or= UNIXFILE_RDONLY
    If pUnix->dirSync <> 0 Then ctrlFlags Or= UNIXFILE_DIRSYNC
    If (flags And SQLITE_OPEN_URI) <> 0 Then ctrlFlags Or= UNIXFILE_URI
    If pVfs = @unixNoneVfs Then ctrlFlags Or= UNIXFILE_NOLOCK
    If allowReusableDescriptor = 0 AndAlso _
       (flags And SQLITE_OPEN_MAIN_DB) = 0 Then _
        ctrlFlags Or= UNIXFILE_NOLOCK
    Dim zUriFilename As Const ZString Ptr = 0
    If (flags And SQLITE_OPEN_URI) <> 0 Then zUriFilename = zName
    pUnix->readOnlyShm = IIf( _
        unixUriBoolean(zUriFilename, StrPtr("readonly_shm"), 0) <> 0, 1, 0)
    If unixUriBoolean(zUriFilename, StrPtr("psow"), _
                      SQLITE_POWERSAFE_OVERWRITE) <> 0 Then ctrlFlags Or= UNIXFILE_PSOW
    Dim zFillPath As Const ZString Ptr = _
        unixPathToZString(@pUnix->zPath(0))
    rc = fillInUnixFile(pVfs, fd, pFile, zFillPath, ctrlFlags)
    If rc <> SQLITE_OK Then
        sqlite3_free(pDeferred)
        pUnix->pDeferred = 0
        unixCloseFd(fd)
        pUnix->fd = -1
        If tempFile <> 0 Then unixUnlink(@zNameBuffer)
        Return rc
    End If
    If pOutFlags <> 0 Then
        pOutFlags[0] = IIf(pUnix->readOnly <> 0, SQLITE_OPEN_READONLY, SQLITE_OPEN_READWRITE)
    End If
    Return SQLITE_OK
End Function

Private Function unixOpenFile CDecl Alias "unixOpen" ( _
    ByVal pVfs As Any Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal pOutFlags As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    Return unixOpenFileInternal( _
        pVfs, zName, pFile, flags, pOutFlags, 0)
End Function

/' C-named callback aliases let the existing Linux VFS bodies satisfy the
   corresponding POSIX callback names without duplicating UnixFile state. '/
Private Function unixCloseFile CDecl Alias "unixClose" (ByVal pFile As Any Ptr) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_OK
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    verifyDbFile(pUnix)
#if SQLITE_MAX_MMAP_SIZE > 0
    If pUnix->nFetchOut <> 0 Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("mapped page references are released before file close"))
#endif
        Return SQLITE_BUSY
    End If
    unixUnmapfile(pUnix)
#endif
    If pUnix->lockingContext <> 0 Then
        sqlite3_free(pUnix->lockingContext)
        pUnix->lockingContext = 0
    End If
    Dim rc As SQLITE_C_INT = SQLITE_OK
#ifdef OS_VXWORKS
    If pUnix->pId <> 0 Then
        If pUnix->deleteOnClose <> 0 AndAlso _
           unixUnlink(pUnix->pId->zCanonicalName) <> 0 AndAlso _
           unixErrno() <> UNIX_ENOENT Then rc = SQLITE_IOERR_DELETE
        Dim pFileId As VxworksFileId Ptr = pUnix->pId
        pUnix->pId = 0
        pUnix->deleteOnClose = 0
        vxworksReleaseFileId(pFileId)
    End If
#endif
    unixEnterMutex()
    Dim pInfo As UnixLockInfo Ptr = pUnix->pLockInfo
    If pUnix->pShmNode <> 0 Then
        Dim shmRc As SQLITE_C_INT = unixShmUnmapLocked(pUnix, 0)
        If rc = SQLITE_OK Then rc = shmRc
    End If
    Dim usesAfpLocks As SQLITE_C_INT = 0
#if SQLITE3_FB_APPLE_LOCKING_STYLE
    usesAfpLocks = CInt(pUnix->base.pMethods = @afpIoMethods)
#endif
    If pInfo <> 0 AndAlso pUnix->lockLevel <> SQLITE_LOCK_NONE AndAlso _
       usesAfpLocks = 0 Then
        rc = unixFileUnlockInternal(pUnix, SQLITE_LOCK_NONE)
    End If
    If pUnix->deleteOnClose <> 0 Then
        If unixUnlink(unixPathToZString(@pUnix->zPath(0))) < 0 AndAlso unixErrno() <> UNIX_ENOENT Then rc = SQLITE_IOERR_DELETE
    End If

    If pInfo <> 0 AndAlso pInfo->nRef > 1 Then
        Dim pDeferred As UnixDeferredFd Ptr = pUnix->pDeferred
        If pDeferred = 0 Then
            robust_close(pUnix, pUnix->fd, __LINE__)
        Else
            setPendingFd(pUnix)
        End If
        releaseInodeInfo(pUnix)
    Else
        If pInfo <> 0 Then
            If usesAfpLocks = 0 Then
                unixSetByteLock(pUnix->fd, UNIX_F_UNLCK, UNIX_PENDING_BYTE, 1, pUnix)
                unixSetByteLock(pUnix->fd, UNIX_F_UNLCK, UNIX_RESERVED_BYTE, 1, pUnix)
                unixSetByteLock(pUnix->fd, UNIX_F_UNLCK, UNIX_SHARED_FIRST, UNIX_SHARED_SIZE, pUnix)
            End If
            releaseInodeInfo(pUnix)
        End If
        If pUnix->fd >= 0 Then robust_close(pUnix, pUnix->fd, __LINE__)
        If pUnix->pDeferred <> 0 Then sqlite3_free(pUnix->pDeferred)
    End If
    pUnix->fd = -1
    pUnix->pLockInfo = 0
    pUnix->base.pMethods = 0
    unixLeaveMutex()
#ifdef SQLITE_TEST
    sqlite3_open_file_count -= 1
#endif
    Return rc
End Function

#if SQLITE3_FB_APPLE_LOCKING_STYLE
/' ------------------------------------------------------------------------- '/
/' Apple AFP byte-range locking                                              '/
/' ------------------------------------------------------------------------- '/
/' AFP exposes file locks through fsctl. The lock bytes follow SQLite's
   pending/reserved/shared layout, while one randomly selected byte represents
   this process's shared lock. This port serializes inode updates with the
   existing Unix mutex while each filesystem request is in flight. '/
Private Function afpFsctlRequest() As SQLITE_C_ULONG
    ' Darwin _IOWR('z', 23, ByteRangeLockPB2), using its 32-byte packet layout.
    If SizeOf(AfpByteRangeLockPB2) <> 32 Then Return 0
    Return CULngInt(&HC0000000ULL Or _
        (CULngInt(SizeOf(AfpByteRangeLockPB2)) Shl 16) Or _
        (&H7A00ULL Or 23))
End Function

Private Function afpLockErrorFromPosix( _
    ByVal errorNumber As SQLITE_C_INT, _
    ByVal ioError As SQLITE_C_INT _
) As SQLITE_C_INT
    ' Network filesystems may report transient lock contention with these errno values.
    Select Case errorNumber
    Case UNIX_EACCES, UNIX_EAGAIN, UNIX_ETIMEDOUT, UNIX_EBUSY, _
         UNIX_EINTR, UNIX_ENOLCK
        Return SQLITE_BUSY
    Case UNIX_EPERM
        Return SQLITE_PERM
    Case Else
        Return ioError
    End Select
End Function

Private Function afpSetLock( _
    ByVal zPath As Const ZString Ptr, _
    ByVal pFile As UnixFile Ptr, _
    ByVal offset As sqlite3_uint64, _
    ByVal length As sqlite3_uint64, _
    ByVal setLockFlag As SQLITE_C_INT _
) As SQLITE_C_INT
    If zPath = 0 OrElse pFile = 0 OrElse pFile->fd < 0 OrElse _
       length = 0 Then Return SQLITE_MISUSE

    Dim lockRequest As AfpByteRangeLockPB2
    lockRequest.unlockFlag = CByte(IIf(setLockFlag <> 0, 0, 1))
    lockRequest.startEndFlag = 0
    lockRequest.offset = offset
    lockRequest.length = length
    lockRequest.returnRangeStart = 0
    lockRequest.fd = pFile->fd

    If unixFsctl(zPath, afpFsctlRequest(), @lockRequest, 0) <> -1 Then _
        Return SQLITE_OK

    Dim errorNumber As SQLITE_C_INT = unixErrno()
    Dim rc As SQLITE_C_INT
#ifdef SQLITE_IGNORE_AFP_LOCK_ERRORS
    rc = SQLITE_BUSY
#else
    Dim ioError As SQLITE_C_INT = _
        IIf(setLockFlag <> 0, SQLITE_IOERR_LOCK, SQLITE_IOERR_UNLOCK)
    rc = afpLockErrorFromPosix(errorNumber, ioError)
#endif
    If rc <> SQLITE_BUSY Then storeLastErrno(pFile, errorNumber)
    Return rc
End Function

Private Function afpCheckReservedLock CDecl Alias "afpCheckReservedLock" ( _
    ByVal pFile As Any Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pFile = 0 OrElse pResult = 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then _
        Return SQLITE_IOERR_CHECKRESERVEDLOCK
#endif

    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    Dim pContext As AfpLockingContext Ptr = _
        CPtr(AfpLockingContext Ptr, pUnix->lockingContext)
    Dim pInfo As UnixLockInfo Ptr = pUnix->pLockInfo
    If pContext = 0 OrElse pInfo = 0 Then _
        Return SQLITE_IOERR_CHECKRESERVEDLOCK
    If pContext->reserved <> 0 Then
        pResult[0] = 1
        Return SQLITE_OK
    End If

    Dim reserved As SQLITE_C_INT = 0
    Dim rc As SQLITE_C_INT = SQLITE_OK
    unixEnterMutex()
    If pInfo->eFileLock > SQLITE_LOCK_SHARED Then
        reserved = 1
    Else
        Dim lockRc As SQLITE_C_INT = afpSetLock( _
            pContext->dbPath, pUnix, CULngInt(UNIX_RESERVED_BYTE), 1, 1)
        If lockRc = SQLITE_OK Then
            lockRc = afpSetLock( _
                pContext->dbPath, pUnix, CULngInt(UNIX_RESERVED_BYTE), 1, 0)
        Else
            reserved = 1
        End If
        If lockRc <> SQLITE_OK AndAlso lockRc <> SQLITE_BUSY Then rc = lockRc
    End If
    unixLeaveMutex()

    pResult[0] = reserved
    Return rc
End Function

Private Function afpLock CDecl Alias "afpLock" ( _
    ByVal pFile As Any Ptr, _
    ByVal requestedLevel As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFile = 0 OrElse requestedLevel < SQLITE_LOCK_SHARED OrElse _
       requestedLevel > SQLITE_LOCK_EXCLUSIVE OrElse _
       requestedLevel = SQLITE_LOCK_PENDING Then Return SQLITE_MISUSE

    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    Dim pInfo As UnixLockInfo Ptr = pUnix->pLockInfo
    Dim pContext As AfpLockingContext Ptr = _
        CPtr(AfpLockingContext Ptr, pUnix->lockingContext)
    If pInfo = 0 OrElse pContext = 0 OrElse pUnix->fd < 0 Then _
        Return SQLITE_IOERR_LOCK
    If pUnix->lockLevel >= requestedLevel Then Return SQLITE_OK

    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim stateUpdateAllowed As SQLITE_C_INT = 1
    unixEnterMutex()

    If pUnix->lockLevel <> pInfo->eFileLock AndAlso _
       (pInfo->eFileLock >= SQLITE_LOCK_PENDING OrElse _
        requestedLevel > SQLITE_LOCK_SHARED) Then
        rc = SQLITE_BUSY
        stateUpdateAllowed = 0
    ElseIf requestedLevel = SQLITE_LOCK_SHARED AndAlso _
           (pInfo->eFileLock = SQLITE_LOCK_SHARED OrElse _
            pInfo->eFileLock = SQLITE_LOCK_RESERVED) Then
        pUnix->lockLevel = SQLITE_LOCK_SHARED
        pInfo->nShared += 1
        pInfo->nLock += 1
        stateUpdateAllowed = 0
    Else
        If requestedLevel = SQLITE_LOCK_SHARED OrElse _
           (requestedLevel = SQLITE_LOCK_EXCLUSIVE AndAlso _
            pUnix->lockLevel < SQLITE_LOCK_PENDING) Then
            rc = afpSetLock( _
                pContext->dbPath, pUnix, CULngInt(UNIX_PENDING_BYTE), 1, 1)
            If rc <> SQLITE_OK Then stateUpdateAllowed = 0
        End If

        If rc = SQLITE_OK Then
            If requestedLevel = SQLITE_LOCK_SHARED Then
                If pInfo->nShared <> 0 OrElse _
                   pInfo->eFileLock <> SQLITE_LOCK_NONE Then
#ifdef SQLITE_DEBUG
                    sqlite3DebugAssert(StrPtr("new AFP shared lock has no local owner"))
#endif
                    rc = SQLITE_BUSY
                    stateUpdateAllowed = 0
                Else
                    Dim randomValue As sqlite3_int64 = unixRandom()
                    If randomValue < 0 Then randomValue = Not randomValue
                    pInfo->sharedByte = CULngInt( _
                        randomValue Mod (UNIX_SHARED_SIZE - 1))

                    Dim sharedLockByte As sqlite3_uint64 = _
                        CULngInt(UNIX_SHARED_FIRST) + pInfo->sharedByte
                    Dim sharedRc As SQLITE_C_INT = afpSetLock( _
                        pContext->dbPath, pUnix, sharedLockByte, 1, 1)
                    Dim sharedErrno As SQLITE_C_INT = 0
                    If sharedRc <> SQLITE_OK AndAlso _
                       sharedRc <> SQLITE_BUSY Then
                        sharedErrno = pUnix->lastErrno
                    End If
                    Dim pendingRc As SQLITE_C_INT = afpSetLock( _
                        pContext->dbPath, pUnix, _
                        CULngInt(UNIX_PENDING_BYTE), 1, 0)

                    If sharedRc <> SQLITE_OK AndAlso _
                       sharedRc <> SQLITE_BUSY Then
                        storeLastErrno(pUnix, sharedErrno)
                        rc = sharedRc
                        stateUpdateAllowed = 0
                    ElseIf pendingRc <> SQLITE_OK AndAlso _
                           pendingRc <> SQLITE_BUSY Then
                        rc = pendingRc
                        stateUpdateAllowed = 0
                    ElseIf sharedRc <> SQLITE_OK Then
                        rc = sharedRc
                        stateUpdateAllowed = 0
                    Else
                        pUnix->lockLevel = SQLITE_LOCK_SHARED
                        pInfo->nLock += 1
                        pInfo->nShared = 1
                    End If
                End If
            ElseIf requestedLevel = SQLITE_LOCK_EXCLUSIVE AndAlso _
                   pInfo->nShared > 1 Then
                rc = SQLITE_BUSY
            Else
                If requestedLevel >= SQLITE_LOCK_RESERVED AndAlso _
                   pUnix->lockLevel < SQLITE_LOCK_RESERVED Then
                    rc = afpSetLock( _
                        pContext->dbPath, pUnix, _
                        CULngInt(UNIX_RESERVED_BYTE), 1, 1)
                    If rc = SQLITE_OK Then pContext->reserved = 1
                End If

                If rc = SQLITE_OK AndAlso _
                   requestedLevel = SQLITE_LOCK_EXCLUSIVE Then
                    Dim sharedLockByte As sqlite3_uint64 = _
                        CULngInt(UNIX_SHARED_FIRST) + pInfo->sharedByte
                    rc = afpSetLock( _
                        pContext->dbPath, pUnix, sharedLockByte, 1, 0)
                    If rc = SQLITE_OK Then
                        Dim exclusiveRc As SQLITE_C_INT = afpSetLock( _
                            pContext->dbPath, pUnix, _
                            CULngInt(UNIX_SHARED_FIRST), _
                            CULngInt(UNIX_SHARED_SIZE), 1)
                        If exclusiveRc <> SQLITE_OK Then
                            Dim restoreRc As SQLITE_C_INT = afpSetLock( _
                                pContext->dbPath, pUnix, sharedLockByte, 1, 1)
                            If restoreRc <> SQLITE_OK Then
                                If (exclusiveRc And &HFF) = SQLITE_IOERR Then
                                    rc = restoreRc
                                Else
                                    rc = SQLITE_IOERR_LOCK
                                End If
                                stateUpdateAllowed = 0
                            Else
                                rc = exclusiveRc
                            End If
                        End If
                    End If
                End If
            End If
        End If
    End If

    If stateUpdateAllowed <> 0 Then
        If rc = SQLITE_OK Then
            pUnix->lockLevel = requestedLevel
            pInfo->eFileLock = requestedLevel
        ElseIf requestedLevel = SQLITE_LOCK_EXCLUSIVE Then
            pUnix->lockLevel = SQLITE_LOCK_PENDING
            pInfo->eFileLock = SQLITE_LOCK_PENDING
        End If
    End If

    unixLeaveMutex()
    Return rc
End Function

Private Function afpUnlock CDecl Alias "afpUnlock" ( _
    ByVal pFile As Any Ptr, _
    ByVal requestedLevel As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFile = 0 OrElse requestedLevel < SQLITE_LOCK_NONE OrElse _
       requestedLevel > SQLITE_LOCK_SHARED Then Return SQLITE_MISUSE

    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    Dim pInfo As UnixLockInfo Ptr = pUnix->pLockInfo
    Dim pContext As AfpLockingContext Ptr = _
        CPtr(AfpLockingContext Ptr, pUnix->lockingContext)
    If pInfo = 0 OrElse pContext = 0 Then Return SQLITE_IOERR_UNLOCK
    If pUnix->lockLevel <= requestedLevel Then Return SQLITE_OK

    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim skipShared As SQLITE_C_INT = 0
    unixEnterMutex()

    If pUnix->lockLevel > SQLITE_LOCK_SHARED AndAlso _
       pUnix->lockLevel = SQLITE_LOCK_EXCLUSIVE Then
        rc = afpSetLock( _
            pContext->dbPath, pUnix, CULngInt(UNIX_SHARED_FIRST), _
            CULngInt(UNIX_SHARED_SIZE), 0)
        If rc = SQLITE_OK AndAlso _
           (requestedLevel = SQLITE_LOCK_SHARED OrElse pInfo->nShared > 1) Then
            Dim sharedLockByte As sqlite3_uint64 = _
                CULngInt(UNIX_SHARED_FIRST) + pInfo->sharedByte
            rc = afpSetLock( _
                pContext->dbPath, pUnix, sharedLockByte, 1, 1)
        ElseIf rc <> SQLITE_OK Then
            skipShared = 1
        Else
            skipShared = 1
        End If
    End If

    If rc = SQLITE_OK AndAlso pUnix->lockLevel >= SQLITE_LOCK_PENDING Then
        rc = afpSetLock( _
            pContext->dbPath, pUnix, CULngInt(UNIX_PENDING_BYTE), 1, 0)
    End If
    If rc = SQLITE_OK AndAlso pUnix->lockLevel >= SQLITE_LOCK_RESERVED AndAlso _
       pContext->reserved <> 0 Then
        rc = afpSetLock( _
            pContext->dbPath, pUnix, CULngInt(UNIX_RESERVED_BYTE), 1, 0)
        If rc = SQLITE_OK Then pContext->reserved = 0
    End If
    If rc = SQLITE_OK AndAlso _
       (requestedLevel = SQLITE_LOCK_SHARED OrElse pInfo->nShared > 1) Then
        pInfo->eFileLock = SQLITE_LOCK_SHARED
    End If

    If rc = SQLITE_OK AndAlso requestedLevel = SQLITE_LOCK_NONE Then
        If pInfo->nShared = 0 OrElse pInfo->nLock <= 0 Then
            rc = SQLITE_IOERR_UNLOCK
        Else
            Dim sharedLockByte As sqlite3_uint64 = _
                CULngInt(UNIX_SHARED_FIRST) + pInfo->sharedByte
            pInfo->nShared -= 1
            If pInfo->nShared = 0 Then
                If skipShared = 0 Then
                    rc = afpSetLock( _
                        pContext->dbPath, pUnix, sharedLockByte, 1, 0)
                End If
                If rc = SQLITE_OK Then
                    pInfo->eFileLock = SQLITE_LOCK_NONE
                    pUnix->lockLevel = SQLITE_LOCK_NONE
                End If
            End If
            If rc = SQLITE_OK Then
                pInfo->nLock -= 1
                If pInfo->nLock = 0 Then closePendingFds(pUnix)
            End If
        End If
    End If

    unixLeaveMutex()
    If rc = SQLITE_OK Then pUnix->lockLevel = requestedLevel
    Return rc
End Function

Private Function afpClose CDecl Alias "afpClose" ( _
    ByVal pFile As Any Ptr _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
    afpUnlock(pFile, SQLITE_LOCK_NONE)
    Return unixCloseFile(pFile)
End Function
#endif

/' ------------------------------------------------------------------------- '/
/' Positioned file I/O helpers                                               '/
/' ------------------------------------------------------------------------- '/

Private Function seekAndRead( _
    ByVal pUnix As UnixFile Ptr, _
    ByVal offset As sqlite3_int64, _
    ByVal pBuffer As Any Ptr, _
    ByVal amount As SQLITE_C_INT _
) As SQLITE_C_INT
    If pUnix = 0 OrElse pBuffer = 0 OrElse _
       offset < 0 OrElse amount < 0 OrElse amount > &H1FFFF Then Return -1

    Dim pOut As UByte Ptr = CPtr(UByte Ptr, pBuffer)
    Dim remaining As SQLITE_C_INT = amount
    Dim totalRead As SQLITE_C_INT = 0
    Dim bytesRead As sqlite3_int64 = 0
    Do
        bytesRead = unixPread( _
            pUnix->fd, pOut, CULng(remaining), offset)
#ifdef SQLITE_TEST
        If fbTestSimulateIoError() <> 0 Then bytesRead = -1
#endif
        If bytesRead = remaining Then Exit Do
        If bytesRead < 0 Then
            Dim errorNumber As SQLITE_C_INT = unixErrno()
            If errorNumber = UNIX_EINTR Then Continue Do
            storeLastErrno(pUnix, errorNumber)
            totalRead = 0
            Exit Do
        End If
        If bytesRead = 0 Then Exit Do
        If bytesRead > remaining Then
            storeLastErrno(pUnix, 0)
            Return -1
        End If

        remaining -= CInt(bytesRead)
        offset += bytesRead
        totalRead += CInt(bytesRead)
        pOut += CInt(bytesRead)
    Loop While bytesRead > 0

    Return CInt(bytesRead) + totalRead
End Function

Private Function seekAndWriteFd( _
    ByVal fd As SQLITE_C_INT, _
    ByVal offset As sqlite3_int64, _
    ByVal pBuffer As Const Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal pErrorNumber As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pBuffer = 0 OrElse offset < 0 OrElse _
       amount < 0 OrElse amount > &H1FFFF OrElse pErrorNumber = 0 Then Return -1

    Dim bytesWritten As sqlite3_int64
    Do
        bytesWritten = unixPwrite( _
            fd, pBuffer, CULng(amount), offset)
    Loop While bytesWritten < 0 AndAlso unixErrno() = UNIX_EINTR
    If bytesWritten < 0 Then pErrorNumber[0] = unixErrno()
    If bytesWritten > amount Then Return -1
    Return CInt(bytesWritten)
End Function

Private Function seekAndWrite( _
    ByVal pUnix As UnixFile Ptr, _
    ByVal offset As sqlite3_int64, _
    ByVal pBuffer As Const Any Ptr, _
    ByVal amount As SQLITE_C_INT _
) As SQLITE_C_INT
    If pUnix = 0 Then Return -1
    Return seekAndWriteFd( _
        pUnix->fd, offset, pBuffer, amount, @pUnix->lastErrno)
End Function

Private Function unixReadFile CDecl Alias "unixRead" ( _
    ByVal pFile As Any Ptr, _
    ByVal pBuffer As Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal offset As sqlite3_int64 _
) As SQLITE_C_INT

    If pFile = 0 OrElse pBuffer = 0 OrElse amount < 0 OrElse _
       amount > &H1FFFF OrElse offset < 0 Then Return SQLITE_MISUSE
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    Dim pOut As UByte Ptr = CPtr(UByte Ptr, pBuffer)
    Dim bytesRead As SQLITE_C_INT = seekAndRead( _
        pUnix, offset, pBuffer, amount)
    If bytesRead = amount Then Return SQLITE_OK
    If bytesRead < 0 Then
        If pUnix->lastErrno = UNIX_ERANGE OrElse _
           pUnix->lastErrno = UNIX_EIO OrElse _
           pUnix->lastErrno = UNIX_ENXIO Then Return SQLITE_IOERR_CORRUPTFS
        Return SQLITE_IOERR_READ
    End If

    storeLastErrno(pUnix, 0)
    For i As SQLITE_C_INT = bytesRead To amount - 1
        pOut[i] = 0
    Next
    Return SQLITE_IOERR_SHORT_READ
End Function

Private Function unixWriteFile CDecl Alias "unixWrite" ( _
    ByVal pFile As Any Ptr, _
    ByVal pBuffer As Const Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal offset As sqlite3_int64 _
) As SQLITE_C_INT

    If pFile = 0 OrElse pBuffer = 0 OrElse amount < 0 OrElse _
       amount > &H1FFFF OrElse offset < 0 Then Return SQLITE_MISUSE
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    Dim pIn As Const UByte Ptr = CPtr(Const UByte Ptr, pBuffer)
    If amount = 0 Then Return SQLITE_OK
    Dim remaining As SQLITE_C_INT = amount
    Dim currentOffset As sqlite3_int64 = offset
    Dim currentBuffer As Const UByte Ptr = pIn
    Dim bytesWritten As SQLITE_C_INT = 0
    Do
        bytesWritten = seekAndWrite( _
            pUnix, currentOffset, currentBuffer, remaining)
        If bytesWritten >= remaining OrElse bytesWritten <= 0 Then Exit Do
        remaining -= bytesWritten
        currentOffset += bytesWritten
        currentBuffer += bytesWritten
    Loop While bytesWritten > 0
#ifdef SQLITE_TEST
    Dim simulatedIoError As SQLITE_C_INT = fbTestSimulateIoError()
    Dim simulatedDiskfull As SQLITE_C_INT = fbTestSimulateDiskfull()
    If simulatedIoError <> 0 Then
        bytesWritten = -1
        remaining = 1
    End If
    If simulatedDiskfull <> 0 Then
        pUnix->lastErrno = 0
        bytesWritten = 0
        remaining = 1
    End If
#endif
    If remaining > bytesWritten Then
        If bytesWritten < 0 AndAlso pUnix->lastErrno <> UNIX_ENOSPC Then _
            Return SQLITE_IOERR_WRITE
        pUnix->lastErrno = 0
        Return SQLITE_FULL
    End If
    Return SQLITE_OK
End Function

Private Function unixTruncateFile CDecl Alias "unixTruncate" ( _
    ByVal pFile As Any Ptr, ByVal size As sqlite3_int64 _
) As SQLITE_C_INT
    If pFile = 0 OrElse size < 0 Then Return SQLITE_MISUSE
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then Return SQLITE_IOERR_TRUNCATE
#endif
    If unixFtruncate(pUnix->fd, size) = 0 Then
#if SQLITE_MAX_MMAP_SIZE > 0
        If pUnix->mmapSizeMax > 0 AndAlso size > pUnix->mmapSize Then _
            Return unixMapfile(pUnix, size)
#endif
        Return SQLITE_OK
    End If
    pUnix->lastErrno = unixErrno()
    Return SQLITE_IOERR_TRUNCATE
End Function

Private Function unixSyncFile CDecl Alias "unixSync" ( _
    ByVal pFile As Any Ptr, ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then Return SQLITE_IOERR_LOCK
#endif
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
#ifdef SQLITE_TEST
    If fbTestSimulateDiskfull() <> 0 Then Return SQLITE_FULL
    sqlite3_sync_count += 1
    ' SQLITE_SYNC_FULL is identified by the low four sync-mode bits.
    If (flags And &HF) = SQLITE_SYNC_FULL Then sqlite3_fullsync_count += 1
#endif
    Dim rc As SQLITE_C_INT
    If (flags And SQLITE_SYNC_DATAONLY) <> 0 Then
        rc = unixFdatasync(pUnix->fd)
    Else
        rc = unixFsync(pUnix->fd)
    End If
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then rc = 1
#endif
    If rc <> 0 Then
        pUnix->lastErrno = unixErrno()
        Return SQLITE_IOERR_FSYNC
    End If

    If pUnix->dirSync <> 0 Then
        Dim directoryFd As SQLITE_C_INT = -1
        If openDirectory(unixPathToZString(@pUnix->zPath(0)), @directoryFd) = SQLITE_OK AndAlso _
           directoryFd >= 0 Then
            ' Some filesystems do not support syncing a directory; SQLite ignores that error.
            unixFsync(directoryFd)
            unixCloseFd(directoryFd)
        End If
        pUnix->dirSync = 0
    End If
    Return SQLITE_OK
End Function

Private Function unixFileSize(ByVal pFile As Any Ptr, ByVal pSize As sqlite3_int64 Ptr) As SQLITE_C_INT
    If pFile = 0 OrElse pSize = 0 Then Return SQLITE_MISUSE
    Dim nSize As sqlite3_int64 = unixLseek(CPtr(UnixFile Ptr, pFile)->fd, 0, 2)
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then
        CPtr(UnixFile Ptr, pFile)->lastErrno = unixErrno()
        Return SQLITE_IOERR_FSTAT
    End If
#endif
    If nSize < 0 Then
        CPtr(UnixFile Ptr, pFile)->lastErrno = unixErrno()
        Return SQLITE_IOERR_FSTAT
    End If
    pSize[0] = nSize
    Return SQLITE_OK
End Function

/' The no-lock VFS callbacks are used only when an application explicitly
   chooses a VFS that delegates file safety to an external mechanism. '/
Private Function nolockCheckReservedLock CDecl Alias "nolockCheckReservedLock" ( _
    ByVal pFile As Any Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pResult = 0 Then Return SQLITE_MISUSE
    pResult[0] = 0
    Return SQLITE_OK
End Function

Private Function nolockLock CDecl Alias "nolockLock" ( _
    ByVal pFile As Any Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT
    Return SQLITE_OK
End Function

Private Function nolockUnlock CDecl Alias "nolockUnlock" ( _
    ByVal pFile As Any Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT
    Return SQLITE_OK
End Function

#ifdef OS_VXWORKS
Private Function semXCheckReservedLock CDecl Alias "semXCheckReservedLock" ( _
    ByVal pFile As Any Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pFile = 0 OrElse pResult = 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then _
        Return SQLITE_IOERR_CHECKRESERVEDLOCK
#endif
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    If pUnix->pLockInfo = 0 OrElse pUnix->pLockInfo->pSem = 0 Then _
        Return SQLITE_IOERR_CHECKRESERVEDLOCK
    Dim reserved As SQLITE_C_INT = 0
    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pUnix->lockLevel > SQLITE_LOCK_SHARED Then
        reserved = 1
    ElseIf unixSemTryWait(pUnix->pLockInfo->pSem) = -1 Then
        Dim errorNumber As SQLITE_C_INT = unixErrno()
        If errorNumber = UNIX_EAGAIN Then
            reserved = CInt(pUnix->lockLevel < SQLITE_LOCK_SHARED)
        ElseIf errorNumber = UNIX_EACCES Then
            rc = SQLITE_BUSY
        Else
            storeLastErrno(pUnix, errorNumber)
            rc = SQLITE_IOERR_CHECKRESERVEDLOCK
        End If
    Else
        unixSemPost(pUnix->pLockInfo->pSem)
    End If
    pResult[0] = reserved
    Return rc
End Function

Private Function semXLock CDecl Alias "semXLock" ( _
    ByVal pFile As Any Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    If pUnix->pLockInfo = 0 OrElse pUnix->pLockInfo->pSem = 0 Then _
        Return SQLITE_IOERR_LOCK
    If lockLevel < SQLITE_LOCK_SHARED OrElse _
       lockLevel > SQLITE_LOCK_EXCLUSIVE Then Return SQLITE_MISUSE
    If pUnix->lockLevel > SQLITE_LOCK_NONE Then
        pUnix->lockLevel = lockLevel
        Return SQLITE_OK
    End If
    If unixSemTryWait(pUnix->pLockInfo->pSem) = -1 Then Return SQLITE_BUSY
    pUnix->lockLevel = lockLevel
    Return SQLITE_OK
End Function

Private Function semXUnlock CDecl Alias "semXUnlock" ( _
    ByVal pFile As Any Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    If pUnix->pLockInfo = 0 OrElse pUnix->pLockInfo->pSem = 0 Then _
        Return SQLITE_IOERR_UNLOCK
    If lockLevel < SQLITE_LOCK_NONE OrElse lockLevel > SQLITE_LOCK_SHARED Then _
        Return SQLITE_MISUSE
    If pUnix->lockLevel = lockLevel Then Return SQLITE_OK
    If lockLevel = SQLITE_LOCK_SHARED Then
        pUnix->lockLevel = lockLevel
        Return SQLITE_OK
    End If
    If unixSemPost(pUnix->pLockInfo->pSem) = -1 Then
        storeLastErrno(pUnix, unixErrno())
        Return SQLITE_IOERR_UNLOCK
    End If
    pUnix->lockLevel = SQLITE_LOCK_NONE
    Return SQLITE_OK
End Function

Private Function semXClose CDecl Alias "semXClose" ( _
    ByVal pFile As Any Ptr _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_OK
    semXUnlock(pFile, SQLITE_LOCK_NONE)
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    If pUnix->pLockInfo <> 0 Then
        unixEnterMutex()
        releaseInodeInfo(pUnix)
        unixLeaveMutex()
    End If
    unixCloseFile(pFile)
    Return SQLITE_OK
End Function
#endif

Private Function unixLockFile CDecl Alias "unixLock" ( _
    ByVal pFile As Any Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    unixEnterMutex()
    Dim rc As SQLITE_C_INT = unixFileLockInternal(pUnix, lockLevel)
    unixLeaveMutex()
    Return rc
End Function

Private Function unixUnlockFile(ByVal pFile As Any Ptr, ByVal lockLevel As SQLITE_C_INT) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    unixEnterMutex()
    Dim rc As SQLITE_C_INT = unixFileUnlockInternal(pUnix, lockLevel)
    unixLeaveMutex()
    Return rc
End Function

#if SQLITE3_FB_APPLE_LOCKING_STYLE
Private Function unixFileUnlockNfs( _
    ByVal pFile As Any Ptr, _
    ByVal requested As SQLITE_C_INT _
) As SQLITE_C_INT
    If requested <> SQLITE_LOCK_SHARED Then _
        Return unixUnlockFile(pFile, requested)
    If pFile = 0 Then Return SQLITE_MISUSE

    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    unixEnterMutex()
    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim pInfo As UnixLockInfo Ptr = pUnix->pLockInfo
    If pInfo = 0 OrElse pUnix->fd < 0 Then
        rc = SQLITE_IOERR_UNLOCK
    ElseIf pUnix->lockLevel > SQLITE_LOCK_SHARED Then
        If pInfo->nShared = 0 Then
            rc = SQLITE_IOERR_UNLOCK
        Else
            ' NFS lock managers can retain part of a write range when it is
            ' changed directly to a read range. Keep a write lock on the tail
            ' until the read lock covers the first 509 bytes.
            Dim firstRangeLength As sqlite3_int64 = UNIX_SHARED_SIZE - 1
            If unixApplyFileLock( _
                pUnix, UNIX_F_UNLCK, UNIX_SHARED_FIRST, _
                firstRangeLength) < 0 Then
                storeLastErrno(pUnix, unixErrno())
                rc = SQLITE_IOERR_UNLOCK
            ElseIf unixApplyFileLock( _
                pUnix, UNIX_F_RDLCK, UNIX_SHARED_FIRST, _
                firstRangeLength) < 0 Then
                Dim errorNumber As SQLITE_C_INT = unixErrno()
                If unixErrIsBusy(errorNumber) <> 0 Then
                    rc = SQLITE_BUSY
                Else
                    storeLastErrno(pUnix, errorNumber)
                    rc = SQLITE_IOERR_RDLOCK
                End If
            ElseIf unixApplyFileLock( _
                pUnix, UNIX_F_UNLCK, _
                UNIX_SHARED_FIRST + firstRangeLength, _
                UNIX_SHARED_SIZE - firstRangeLength) < 0 Then
                storeLastErrno(pUnix, unixErrno())
                rc = SQLITE_IOERR_UNLOCK
            End If

            If rc = SQLITE_OK AndAlso pInfo->pPending = pFile Then
                If unixApplyFileLock( _
                    pUnix, UNIX_F_UNLCK, UNIX_PENDING_BYTE, 1) < 0 Then
                    storeLastErrno(pUnix, unixErrno())
                    rc = SQLITE_IOERR_UNLOCK
                Else
                    pInfo->pPending = 0
                End If
            End If
            If rc = SQLITE_OK AndAlso pInfo->pReserved = pFile Then
                If unixApplyFileLock( _
                    pUnix, UNIX_F_UNLCK, UNIX_RESERVED_BYTE, 1) < 0 Then
                    storeLastErrno(pUnix, unixErrno())
                    rc = SQLITE_IOERR_UNLOCK
                Else
                    pInfo->pReserved = 0
                End If
            End If
            If rc = SQLITE_OK Then
                If pInfo->pExclusive = pFile Then pInfo->pExclusive = 0
                pUnix->lockLevel = SQLITE_LOCK_SHARED
            End If
        End If
    End If
    unixLeaveMutex()
    Return rc
End Function
#endif

' The Linux VFS uses unixUnlockFile for the POSIX lock transition. The NFS
' two-range downgrade is specific to the Apple locking-style build.
Private Function posixUnlock CDecl Alias "posixUnlock" ( _
    ByVal pFile As Any Ptr, _
    ByVal lockLevel As SQLITE_C_INT, _
    ByVal handleNFSUnlock As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
#if SQLITE3_FB_APPLE_LOCKING_STYLE
    If handleNFSUnlock <> 0 Then Return unixFileUnlockNfs(pFile, lockLevel)
#else
    If handleNFSUnlock <> 0 Then Return SQLITE_MISUSE
#endif
    Return unixUnlockFile(pFile, lockLevel)
End Function

#if SQLITE3_FB_APPLE_LOCKING_STYLE
Private Function nfsUnlock CDecl Alias "nfsUnlock" ( _
    ByVal pFile As Any Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT
    Return posixUnlock(pFile, lockLevel, 1)
End Function
#endif

#if SQLITE3_FB_APPLE_LOCKING_STYLE
#ifndef HAVE_GETHOSTUUID
' Apple target profiles should set this when the SDK deployment target exposes
' gethostuuid(); otherwise the upstream zero-host-ID fallback is used.
#define HAVE_GETHOSTUUID 0
#endif
#if HAVE_GETHOSTUUID
Declare Function unixGetHostUuid CDecl Alias "gethostuuid" ( _
    ByVal pHostId As UByte Ptr, _
    ByVal pTimeout As UnixTimespec Ptr _
) As SQLITE_C_INT
#endif
Declare Function unixConfstr CDecl Alias "confstr" ( _
    ByVal name As SQLITE_C_INT, _
    ByVal zBuffer As ZString Ptr, _
    ByVal bufferSize As SQLITE_SIZE_T _
) As SQLITE_SIZE_T
Declare Function unixDefaultRename CDecl Alias "rename" ( _
    ByVal zOldPath As Const ZString Ptr, _
    ByVal zNewPath As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function unixFutimes CDecl Alias "futimes" ( _
    ByVal fd As SQLITE_C_INT, _
    ByVal pTimes As Any Ptr _
) As SQLITE_C_INT
Declare Function unixStatfs CDecl Alias "statfs" ( _
    ByVal zPath As Const ZString Ptr, _
    ByVal pStat As Any Ptr _
) As SQLITE_C_INT
#ifndef SQLITE_DEFAULT_PROXYDIR_PERMISSIONS
#define SQLITE_DEFAULT_PROXYDIR_PERMISSIONS &O755
#endif
#ifndef SQLITE3_FB_CS_DARWIN_USER_TEMP_DIR
' Darwin's confstr selector for the per-user temporary directory.
#define SQLITE3_FB_CS_DARWIN_USER_TEMP_DIR 65537
#endif
#ifndef SQLITE3_FB_APPLE_PROXY_MAXPATHLEN
#define SQLITE3_FB_APPLE_PROXY_MAXPATHLEN 1024
#endif
Private Const UNIX_MNT_RDONLY As u32 = 1
Private Const UNIX_PROXY_HOSTID_LENGTH As SQLITE_C_INT = 16
Private Const UNIX_PROXY_CONCH_VERSION As UByte = 2
Private Const UNIX_PROXY_HEADER_LENGTH As SQLITE_C_INT = 1
Private Const UNIX_PROXY_PATH_INDEX As SQLITE_C_INT = _
    UNIX_PROXY_HEADER_LENGTH + UNIX_PROXY_HOSTID_LENGTH
Private Const UNIX_PROXY_MAX_CONCH_LENGTH As SQLITE_C_INT = _
    UNIX_PROXY_PATH_INDEX + SQLITE3_FB_APPLE_PROXY_MAXPATHLEN

#ifdef SQLITE_TEST
Extern sqlite3_hostid_num Alias "sqlite3_hostid_num" As SQLITE_C_INT
Dim Shared sqlite3_hostid_num As SQLITE_C_INT
#endif

Private Function proxyGetHostID CDecl Alias "proxyGetHostID" ( _
    ByVal pHostId As UByte Ptr, _
    ByVal pError As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pHostId = 0 Then Return SQLITE_MISUSE
    For byteIndex As SQLITE_C_INT = 0 To 15
        pHostId[byteIndex] = 0
    Next

#if HAVE_GETHOSTUUID
    Dim timeout As UnixTimespec
    timeout.tvSec = 1
    timeout.tvNsec = 0
    If unixGetHostUuid(pHostId, @timeout) <> 0 Then
        Dim errorNumber As SQLITE_C_INT = unixErrno()
        If pError <> 0 Then pError[0] = errorNumber
        Return SQLITE_IOERR
    End If
#else
    ' Without gethostuuid, SQLite uses a zero host ID unless SQLITE_TEST
    ' requests distinct simulated hosts.
#endif

#ifdef SQLITE_TEST
    If sqlite3_hostid_num <> 0 Then
        pHostId[0] = CUByte( _
            (CULng(pHostId[0]) + (sqlite3_hostid_num And &HFF)) And &HFF)
    End If
#endif
    Return SQLITE_OK
End Function

Private Function proxyCreateConchPathname CDecl Alias "proxyCreateConchPathname" ( _
    ByVal zDatabasePath As Const ZString Ptr, _
    ByVal ppConchPath As ZString Ptr Ptr _
) As SQLITE_C_INT
    If ppConchPath = 0 Then Return SQLITE_MISUSE
    ppConchPath[0] = 0
    If zDatabasePath = 0 Then Return SQLITE_MISUSE

    Dim pInput As Const UByte Ptr = CPtr(Const UByte Ptr, zDatabasePath)
    Dim pathLength As SQLITE_C_INT = 0
    While pathLength < UNIX_PATH_MAX AndAlso pInput[pathLength] <> 0
        pathLength += 1
    Wend
    If pathLength >= UNIX_PATH_MAX Then Return SQLITE_CANTOPEN

    Dim allocationSize As sqlite3_uint64 = CULngInt(pathLength) + 8
    Dim pConchPath As UByte Ptr = CPtr( _
        UByte Ptr, sqlite3MallocZero(allocationSize))
    If pConchPath = 0 Then Return SQLITE_NOMEM

    For byteIndex As SQLITE_C_INT = 0 To pathLength
        pConchPath[byteIndex] = pInput[byteIndex]
    Next

    ' Place a dot immediately after the final slash, or at the start for a
    ' relative path. The caller normally supplies a full path.
    Dim insertIndex As SQLITE_C_INT = pathLength - 1
    While insertIndex >= 0
        If pInput[insertIndex] = Asc("/") Then
            insertIndex += 1
            Exit While
        End If
        insertIndex -= 1
    Wend
    If insertIndex < 0 Then insertIndex = 0
    pConchPath[insertIndex] = Asc(".")

    For byteIndex As SQLITE_C_INT = insertIndex To pathLength
        pConchPath[byteIndex + 1] = pInput[byteIndex]
    Next
    pConchPath[pathLength + 1] = Asc("-")
    pConchPath[pathLength + 2] = Asc("c")
    pConchPath[pathLength + 3] = Asc("o")
    pConchPath[pathLength + 4] = Asc("n")
    pConchPath[pathLength + 5] = Asc("c")
    pConchPath[pathLength + 6] = Asc("h")
    pConchPath[pathLength + 7] = 0
    ppConchPath[0] = CPtr(ZString Ptr, pConchPath)
    Return SQLITE_OK
End Function

Private Function proxyAppendText( _
    ByVal pOutput As UByte Ptr, _
    ByVal maximumLength As SQLITE_SIZE_T, _
    ByRef usedLength As sqlite3_uint64, _
    ByVal zText As Const ZString Ptr _
) As SQLITE_C_INT
    If pOutput = 0 OrElse zText = 0 OrElse usedLength >= maximumLength Then Return 0
    Dim pText As Const UByte Ptr = CPtr(Const UByte Ptr, zText)
    Dim textIndex As sqlite3_uint64 = 0
    While pText[textIndex] <> 0
        If usedLength + 1 >= maximumLength Then Return 0
        pOutput[usedLength] = pText[textIndex]
        usedLength += 1
        textIndex += 1
    Wend
    pOutput[usedLength] = 0
    Return -1
End Function

Private Function proxyGetLockPath CDecl Alias "proxyGetLockPath" ( _
    ByVal zDatabasePath As Const ZString Ptr, _
    ByVal zLockPath As ZString Ptr, _
    ByVal maximumLength As SQLITE_SIZE_T _
) As SQLITE_C_INT
    If zDatabasePath = 0 OrElse zLockPath = 0 OrElse maximumLength = 0 Then _
        Return SQLITE_MISUSE
    If maximumLength > UNIX_PATH_MAX Then Return SQLITE_CANTOPEN

    Dim pOutput As UByte Ptr = CPtr(UByte Ptr, zLockPath)
    pOutput[0] = 0
    Dim usedLength As sqlite3_uint64 = 0
#ifdef LOCKPROXYDIR
    If proxyAppendText(pOutput, maximumLength, usedLength, _
                       StrPtr(LOCKPROXYDIR)) = 0 Then Return SQLITE_CANTOPEN
#else
    Dim requiredLength As SQLITE_SIZE_T = unixConfstr( _
        SQLITE3_FB_CS_DARWIN_USER_TEMP_DIR, zLockPath, maximumLength)
    If requiredLength = 0 Then Return SQLITE_IOERR_LOCK
    While usedLength < maximumLength AndAlso pOutput[usedLength] <> 0
        usedLength += 1
    Wend
    If usedLength >= maximumLength Then Return SQLITE_CANTOPEN
    If proxyAppendText(pOutput, maximumLength, usedLength, _
                       StrPtr("sqliteplocks")) = 0 Then Return SQLITE_CANTOPEN
#endif

    If usedLength = 0 Then Return SQLITE_CANTOPEN
    If pOutput[usedLength - 1] <> Asc("/") Then
        If usedLength + 1 >= maximumLength Then Return SQLITE_CANTOPEN
        pOutput[usedLength] = Asc("/")
        usedLength += 1
        pOutput[usedLength] = 0
    End If

    Dim pDatabase As Const UByte Ptr = _
        CPtr(Const UByte Ptr, zDatabasePath)
    Dim databaseLength As sqlite3_uint64 = 0
    While databaseLength < UNIX_PATH_MAX AndAlso _
          pDatabase[databaseLength] <> 0
        databaseLength += 1
    Wend
    If databaseLength >= UNIX_PATH_MAX Then Return SQLITE_CANTOPEN

    Dim copyLength As sqlite3_uint64 = 0
    While copyLength < databaseLength AndAlso _
          usedLength + copyLength + 7 < maximumLength
        Dim pathByte As UByte = pDatabase[copyLength]
        If pathByte = Asc("/") Then pathByte = Asc("_")
        pOutput[usedLength + copyLength] = pathByte
        copyLength += 1
    Wend
    usedLength += copyLength
    pOutput[usedLength] = 0
    If proxyAppendText(pOutput, maximumLength, usedLength, _
                       StrPtr(":auto:")) = 0 Then Return SQLITE_CANTOPEN
    Return SQLITE_OK
End Function

Private Function proxyCreateLockPath CDecl Alias "proxyCreateLockPath" ( _
    ByVal zLockPath As Const ZString Ptr _
) As SQLITE_C_INT
    If zLockPath = 0 Then Return SQLITE_MISUSE
    Dim pLockPath As Const UByte Ptr = CPtr(Const UByte Ptr, zLockPath)
    Dim pathLength As SQLITE_C_INT = 0
    While pathLength < UNIX_PATH_MAX AndAlso pLockPath[pathLength] <> 0
        pathLength += 1
    Wend
    If pathLength = 0 OrElse pathLength >= UNIX_PATH_MAX Then _
        Return SQLITE_CANTOPEN

    Dim directoryBuffer As ZString * UNIX_PATH_MAX
    Dim pDirectoryBytes As UByte Ptr = @directoryBuffer
    For byteIndex As SQLITE_C_INT = 0 To pathLength - 1
        pDirectoryBytes[byteIndex] = pLockPath[byteIndex]
    Next
    pDirectoryBytes[pathLength] = 0

    Dim startIndex As SQLITE_C_INT = 0
    For pathIndex As SQLITE_C_INT = 1 To pathLength - 1
        If pLockPath[pathIndex] = Asc("/") AndAlso _
           pathIndex - startIndex > 0 Then
            Dim componentLength As SQLITE_C_INT = pathIndex - startIndex
            Dim createDirectory As SQLITE_C_INT = CInt( _
                componentLength > 2 OrElse _
                (componentLength = 1 AndAlso _
                 pDirectoryBytes[startIndex] <> Asc(".") AndAlso _
                 pDirectoryBytes[startIndex] <> Asc("/")) OrElse _
                (componentLength = 2 AndAlso _
                 pDirectoryBytes[startIndex] <> Asc(".") AndAlso _
                 pDirectoryBytes[startIndex + 1] <> Asc(".")))
            If createDirectory <> 0 Then
                pDirectoryBytes[pathIndex] = 0
                If unixMkdir( _
                    CPtr(Const ZString Ptr, pDirectoryBytes), _
                    SQLITE_DEFAULT_PROXYDIR_PERMISSIONS) <> 0 Then
                    Dim errorNumber As SQLITE_C_INT = unixErrno()
                    If errorNumber <> UNIX_EEXIST Then Return errorNumber
                End If
            End If
            startIndex = pathIndex + 1
        End If
        pDirectoryBytes[pathIndex] = pLockPath[pathIndex]
    Next
    Return 0
End Function

Private Function proxyGetDbPathForUnixFile CDecl Alias "proxyGetDbPathForUnixFile" ( _
    ByVal pFile As Any Ptr, _
    ByVal zDatabasePath As ZString Ptr _
) As SQLITE_C_INT
    If pFile = 0 OrElse zDatabasePath = 0 Then Return SQLITE_MISUSE
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    Dim zSource As Const ZString Ptr = 0
    Dim sourceLength As SQLITE_C_INT = 0
#if SQLITE3_FB_APPLE_LOCKING_STYLE
    If pUnix->base.pMethods = @afpIoMethods Then
        Dim pAfpContext As AfpLockingContext Ptr = _
            CPtr(AfpLockingContext Ptr, pUnix->lockingContext)
        If pAfpContext = 0 OrElse pAfpContext->dbPath = 0 Then _
            Return SQLITE_CANTOPEN
        zSource = pAfpContext->dbPath
        Dim pAfpPath As Const UByte Ptr = CPtr(Const UByte Ptr, zSource)
        While sourceLength < UNIX_PATH_MAX AndAlso pAfpPath[sourceLength] <> 0
            sourceLength += 1
        Wend
        If sourceLength >= UNIX_PATH_MAX Then Return SQLITE_CANTOPEN
    ElseIf pUnix->base.pMethods = @dotlockIoMethods Then
#else
    If pUnix->base.pMethods = @dotlockIoMethods Then
#endif
        zSource = CPtr(Const ZString Ptr, pUnix->lockingContext)
        If zSource = 0 Then Return SQLITE_CANTOPEN
        Dim pSource As Const UByte Ptr = CPtr(Const UByte Ptr, zSource)
        While sourceLength < UNIX_PATH_MAX AndAlso pSource[sourceLength] <> 0
            sourceLength += 1
        Wend
        If sourceLength < 5 OrElse sourceLength >= UNIX_PATH_MAX Then _
            Return SQLITE_CANTOPEN
        sourceLength -= 5
    ElseIf pUnix->lockingContext <> 0 Then
        zSource = CPtr(Const ZString Ptr, pUnix->lockingContext)
        Dim pSource As Const UByte Ptr = CPtr(Const UByte Ptr, zSource)
        While sourceLength < UNIX_PATH_MAX AndAlso pSource[sourceLength] <> 0
            sourceLength += 1
        Wend
        If sourceLength >= UNIX_PATH_MAX Then Return SQLITE_CANTOPEN
    Else
        zSource = unixPathToZString(@pUnix->zPath(0))
        Dim pSource As Const UByte Ptr = CPtr(Const UByte Ptr, zSource)
        While sourceLength < UNIX_PATH_MAX AndAlso pSource[sourceLength] <> 0
            sourceLength += 1
        Wend
        If sourceLength >= UNIX_PATH_MAX Then Return SQLITE_CANTOPEN
    End If

    Dim pDestination As UByte Ptr = CPtr(UByte Ptr, zDatabasePath)
    Dim pSourceBytes As Const UByte Ptr = CPtr(Const UByte Ptr, zSource)
    For byteIndex As SQLITE_C_INT = 0 To sourceLength - 1
        pDestination[byteIndex] = pSourceBytes[byteIndex]
    Next
    pDestination[sourceLength] = 0
    Return SQLITE_OK
End Function

Private Function proxyCreateUnixFile CDecl Alias "proxyCreateUnixFile" ( _
    ByVal zPath As Const ZString Ptr, _
    ByVal ppFile As UnixFile Ptr Ptr, _
    ByVal isLockFile As SQLITE_C_INT _
) As SQLITE_C_INT
    If zPath = 0 OrElse ppFile = 0 Then Return SQLITE_MISUSE
    ppFile[0] = 0

    Dim pNew As UnixFile Ptr = CPtr( _
        UnixFile Ptr, sqlite3MallocZero(SizeOf(UnixFile)))
    If pNew = 0 Then Return SQLITE_NOMEM

    Dim outFlags As SQLITE_C_INT = 0
    Dim openFlags As SQLITE_C_INT = _
        SQLITE_OPEN_READWRITE Or SQLITE_OPEN_CREATE Or SQLITE_OPEN_NOFOLLOW
    Dim rc As SQLITE_C_INT = unixOpenFileInternal( _
        @unixVfs, zPath, CPtr(sqlite3_file Ptr, pNew), openFlags, @outFlags, 1)

    If rc <> SQLITE_OK AndAlso rc <> SQLITE_NOMEM AndAlso _
       isLockFile <> 0 AndAlso unixErrno() = UNIX_ENOENT Then
        If proxyCreateLockPath(zPath) = SQLITE_OK Then
            rc = unixOpenFileInternal( _
                @unixVfs, zPath, CPtr(sqlite3_file Ptr, pNew), _
                openFlags, @outFlags, 1)
        End If
    End If

    If rc <> SQLITE_OK Then
        sqlite3_free(pNew)
        If rc = SQLITE_NOMEM Then Return rc
        If isLockFile <> 0 Then Return SQLITE_BUSY

        Select Case unixErrno()
        Case UNIX_EACCES
            Return SQLITE_PERM
        Case UNIX_EIO
            Return SQLITE_IOERR_LOCK
        Case Else
            Return SQLITE_CANTOPEN
        End Select
    End If

    pNew->isMainDb = 0
#ifdef SQLITE_ENABLE_LOCKING_STYLE
    pNew->openFlags = unixSystemOpenFlags( _
        openFlags, CInt(pNew->readOnly <> 0))
#endif
    ppFile[0] = pNew
    Return SQLITE_OK
End Function

Private Function proxyBreakConchLock CDecl Alias "proxyBreakConchLock" ( _
    ByVal pFile As UnixFile Ptr, _
    ByVal pHostId As Const UByte Ptr _
) As SQLITE_C_INT
    If pFile = 0 OrElse pHostId = 0 OrElse pFile->lockingContext = 0 Then _
        Return -1
    Dim pContext As ProxyLockingContext Ptr = _
        CPtr(ProxyLockingContext Ptr, pFile->lockingContext)
    Dim pConch As UnixFile Ptr = pContext->conchFile
    If pConch = 0 OrElse pContext->conchFilePath = 0 Then Return -1

    Dim zBreakPath As ZString * SQLITE3_FB_APPLE_PROXY_MAXPATHLEN
    Dim pConchPath As Const UByte Ptr = _
        CPtr(Const UByte Ptr, pContext->conchFilePath)
    Dim pathLength As SQLITE_C_INT = 0
    While pathLength < SQLITE3_FB_APPLE_PROXY_MAXPATHLEN AndAlso _
          pConchPath[pathLength] <> 0
        pathLength += 1
    Wend
    If pathLength < 6 OrElse pathLength >= SQLITE3_FB_APPLE_PROXY_MAXPATHLEN Then _
        Return -1
    Dim pBreakBytes As UByte Ptr = @zBreakPath
    For byteIndex As SQLITE_C_INT = 0 To pathLength
        pBreakBytes[byteIndex] = pConchPath[byteIndex]
    Next
    pBreakBytes[pathLength - 5] = Asc("b")
    pBreakBytes[pathLength - 4] = Asc("r")
    pBreakBytes[pathLength - 3] = Asc("e")
    pBreakBytes[pathLength - 2] = Asc("a")
    pBreakBytes[pathLength - 1] = Asc("k")
    pBreakBytes[pathLength] = 0

    Dim dataBuffer(0 To UNIX_PROXY_MAX_CONCH_LENGTH - 1) As UByte
    Dim bytesRead As sqlite3_int64 = unixPread( _
        pConch->fd, @dataBuffer(0), _
        UNIX_PROXY_MAX_CONCH_LENGTH, 0)
    If bytesRead < UNIX_PROXY_PATH_INDEX Then Return -1

    Dim fd As SQLITE_C_INT = robust_open( _
        @zBreakPath, _
        UNIX_OPEN_RDWR Or UNIX_OPEN_CREAT Or UNIX_OPEN_EXCL Or UNIX_OPEN_NOFOLLOW, _
        0)
    If fd < 0 Then Return -1
    If unixPwrite(fd, @dataBuffer(0), CULngInt(bytesRead), 0) <> bytesRead Then
        unixUnlink(@zBreakPath)
        robust_close(pFile, fd, __LINE__)
        Return -1
    End If
    If unixDefaultRename(@zBreakPath, pContext->conchFilePath) <> 0 Then
        unixUnlink(@zBreakPath)
        robust_close(pFile, fd, __LINE__)
        Return -1
    End If

    robust_close(pFile, pConch->fd, __LINE__)
    pConch->fd = fd
    pConch->openFlags = UNIX_OPEN_RDWR Or UNIX_OPEN_CREAT
    Return 0
End Function

Private Function proxyConchLock CDecl Alias "proxyConchLock" ( _
    ByVal pFile As UnixFile Ptr, _
    ByVal pHostId As Const UByte Ptr, _
    ByVal lockType As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFile = 0 OrElse pHostId = 0 OrElse pFile->lockingContext = 0 Then _
        Return SQLITE_MISUSE
    Dim pContext As ProxyLockingContext Ptr = _
        CPtr(ProxyLockingContext Ptr, pFile->lockingContext)
    Dim pConch As UnixFile Ptr = pContext->conchFile
    If pConch = 0 OrElse pConch->base.pMethods = 0 Then Return SQLITE_IOERR_LOCK

    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim tries As SQLITE_C_INT = 0
    Dim conchModificationTime As UnixTimespec
    conchModificationTime.tvSec = 0
    conchModificationTime.tvNsec = 0
    Do
        rc = pConch->base.pMethods->xLock( _
            CPtr(Any Ptr, pConch), lockType)
        tries += 1
        If rc <> SQLITE_BUSY Then Exit Do

        Dim statInfo As UnixStat
        If unixFstat(pConch->fd, @statInfo) <> 0 Then
            storeLastErrno(pFile, unixErrno())
            Return SQLITE_IOERR_LOCK
        End If
        If tries = 1 Then
            conchModificationTime.tvSec = statInfo.mtimeSec
            conchModificationTime.tvNsec = statInfo.mtimeNsec
            unixSleep(0, 500000)
            Continue Do
        End If
        If conchModificationTime.tvSec <> statInfo.mtimeSec OrElse _
           conchModificationTime.tvNsec <> statInfo.mtimeNsec Then _
            Return SQLITE_BUSY

        If tries = 2 Then
            Dim conchBuffer(0 To UNIX_PROXY_MAX_CONCH_LENGTH - 1) As UByte
            Dim bytesRead As sqlite3_int64 = unixPread( _
                pConch->fd, @conchBuffer(0), _
                UNIX_PROXY_MAX_CONCH_LENGTH, 0)
            If bytesRead < 0 Then
                storeLastErrno(pFile, unixErrno())
                Return SQLITE_IOERR_LOCK
            End If
            If bytesRead <= UNIX_PROXY_PATH_INDEX OrElse _
               conchBuffer(0) <> UNIX_PROXY_CONCH_VERSION Then Return SQLITE_BUSY
            For byteIndex As SQLITE_C_INT = 0 To UNIX_PROXY_HOSTID_LENGTH - 1
                If conchBuffer(UNIX_PROXY_HEADER_LENGTH + byteIndex) <> _
                   pHostId[byteIndex] Then Return SQLITE_BUSY
            Next
            unixSleep(0, 10000000)
            Continue Do
        End If

        If tries = 3 AndAlso proxyBreakConchLock(pFile, pHostId) = 0 Then
            rc = SQLITE_OK
            If lockType = SQLITE_LOCK_EXCLUSIVE Then
                rc = pConch->base.pMethods->xLock( _
                    CPtr(Any Ptr, pConch), SQLITE_LOCK_SHARED)
            End If
            If rc = SQLITE_OK Then
                rc = pConch->base.pMethods->xLock( _
                    CPtr(Any Ptr, pConch), lockType)
            End If
        End If
    Loop While rc = SQLITE_BUSY AndAlso tries < 3
    Return rc
End Function

Private Function proxyTakeConch CDecl Alias "proxyTakeConch" ( _
    ByVal pFile As UnixFile Ptr _
) As SQLITE_C_INT
    If pFile = 0 OrElse pFile->lockingContext = 0 Then Return SQLITE_MISUSE
    Dim pContext As ProxyLockingContext Ptr = _
        CPtr(ProxyLockingContext Ptr, pFile->lockingContext)
    If pContext->conchHeld <> 0 Then Return SQLITE_OK
    Dim pConch As UnixFile Ptr = pContext->conchFile
    If pConch = 0 OrElse pConch->base.pMethods = 0 Then Return SQLITE_IOERR_LOCK

    Dim hostId(0 To UNIX_PROXY_HOSTID_LENGTH - 1) As UByte
    Dim hostIdError As SQLITE_C_INT = 0
    Dim rc As SQLITE_C_INT = proxyGetHostID(@hostId(0), @hostIdError)
    If (rc And &HFF) = SQLITE_IOERR Then
        storeLastErrno(pFile, hostIdError)
    End If
    If rc = SQLITE_OK Then _
        rc = proxyConchLock(pFile, @hostId(0), SQLITE_LOCK_SHARED)
    If rc <> SQLITE_OK Then
        pConch->base.pMethods->xUnlock( _
            CPtr(Any Ptr, pConch), SQLITE_LOCK_NONE)
        Return rc
    End If

    Dim conchBuffer(0 To UNIX_PROXY_MAX_CONCH_LENGTH - 1) As UByte
    Dim bytesRead As sqlite3_int64 = unixPread( _
        pConch->fd, @conchBuffer(0), UNIX_PROXY_MAX_CONCH_LENGTH, 0)
    If bytesRead < 0 Then
        storeLastErrno(pFile, unixErrno())
        pConch->base.pMethods->xUnlock( _
            CPtr(Any Ptr, pConch), SQLITE_LOCK_NONE)
        Return SQLITE_IOERR_READ
    End If

    Dim createConch As SQLITE_C_INT = CInt( _
        bytesRead <= UNIX_PROXY_PATH_INDEX OrElse _
        conchBuffer(0) <> UNIX_PROXY_CONCH_VERSION)
    Dim forceNewLockPath As SQLITE_C_INT = 0
    Dim tryOldLockPath As SQLITE_C_INT = 0
    Dim lockPathBuffer As ZString * SQLITE3_FB_APPLE_PROXY_MAXPATHLEN
    Dim tempLockPath As ZString Ptr = 0

    Do
        Dim hostIdMatches As SQLITE_C_INT = 0
        Dim skipConchUpdate As SQLITE_C_INT = 0
        If createConch = 0 AndAlso forceNewLockPath = 0 Then
            hostIdMatches = -1
            For byteIndex As SQLITE_C_INT = 0 To UNIX_PROXY_HOSTID_LENGTH - 1
                If conchBuffer(UNIX_PROXY_HEADER_LENGTH + byteIndex) <> _
                   hostId(byteIndex) Then
                    hostIdMatches = 0
                    Exit For
                End If
            Next

            Dim conchPathLength As SQLITE_C_INT = _
                CInt(bytesRead - UNIX_PROXY_PATH_INDEX)
            If pContext->lockProxyPath = 0 Then
                If hostIdMatches <> 0 Then
                    If conchPathLength >= SQLITE3_FB_APPLE_PROXY_MAXPATHLEN Then _
                        conchPathLength = SQLITE3_FB_APPLE_PROXY_MAXPATHLEN - 1
                    For byteIndex As SQLITE_C_INT = 0 To conchPathLength - 1
                        CPtr(UByte Ptr, @lockPathBuffer)[byteIndex] = _
                            conchBuffer(UNIX_PROXY_PATH_INDEX + byteIndex)
                    Next
                    CPtr(UByte Ptr, @lockPathBuffer)[conchPathLength] = 0
                    tempLockPath = StrPtr(lockPathBuffer)
                    tryOldLockPath = 1
                    skipConchUpdate = -1
                End If
            ElseIf hostIdMatches <> 0 Then
                Dim pSavedPath As Const UByte Ptr = _
                    CPtr(Const UByte Ptr, pContext->lockProxyPath)
                Dim pConchPath As Const UByte Ptr = _
                    @conchBuffer(UNIX_PROXY_PATH_INDEX)
                Dim savedPathLength As SQLITE_C_INT = 0
                While savedPathLength < SQLITE3_FB_APPLE_PROXY_MAXPATHLEN AndAlso _
                      pSavedPath[savedPathLength] <> 0
                    savedPathLength += 1
                Wend
                If savedPathLength >= conchPathLength Then
                    Dim pathsMatch As SQLITE_C_INT = -1
                    For byteIndex As SQLITE_C_INT = 0 To conchPathLength - 1
                        If pSavedPath[byteIndex] <> pConchPath[byteIndex] Then
                            pathsMatch = 0
                            Exit For
                        End If
                    Next
                    If pathsMatch <> 0 Then skipConchUpdate = -1
                End If
            End If
        End If

        If skipConchUpdate = 0 Then
            If (pConch->openFlags And UNIX_OPEN_RDWR) = 0 Then
                rc = SQLITE_BUSY
                Exit Do
            End If
            If pContext->lockProxyPath = 0 Then
                rc = proxyGetLockPath( _
                    pContext->dbPath, @lockPathBuffer, _
                    SQLITE3_FB_APPLE_PROXY_MAXPATHLEN)
                If rc <> SQLITE_OK Then Exit Do
                tempLockPath = StrPtr(lockPathBuffer)
            End If

            unixFutimes(pConch->fd, 0)
            If hostIdMatches <> 0 AndAlso createConch = 0 AndAlso _
               pFile->pLockInfo <> 0 AndAlso pFile->pLockInfo->nShared > 1 Then
                rc = SQLITE_BUSY
            Else
                rc = proxyConchLock( _
                    pFile, @hostId(0), SQLITE_LOCK_EXCLUSIVE)
            End If

            If rc = SQLITE_OK Then
                Dim writeBuffer(0 To UNIX_PROXY_MAX_CONCH_LENGTH - 1) As UByte
                writeBuffer(0) = UNIX_PROXY_CONCH_VERSION
                For byteIndex As SQLITE_C_INT = 0 To UNIX_PROXY_HOSTID_LENGTH - 1
                    writeBuffer(UNIX_PROXY_HEADER_LENGTH + byteIndex) = _
                        hostId(byteIndex)
                Next
                Dim zPathToStore As Const ZString Ptr = pContext->lockProxyPath
                If zPathToStore = 0 Then zPathToStore = tempLockPath
                If zPathToStore = 0 Then
                    rc = SQLITE_CANTOPEN
                Else
                    Dim pPathBytes As Const UByte Ptr = _
                        CPtr(Const UByte Ptr, zPathToStore)
                    Dim storedPathLength As SQLITE_C_INT = 0
                    While storedPathLength < SQLITE3_FB_APPLE_PROXY_MAXPATHLEN - 1 AndAlso _
                          pPathBytes[storedPathLength] <> 0
                        storedPathLength += 1
                    Wend
                    For byteIndex As SQLITE_C_INT = 0 To storedPathLength - 1
                        writeBuffer(UNIX_PROXY_PATH_INDEX + byteIndex) = _
                            pPathBytes[byteIndex]
                    Next
                    writeBuffer(UNIX_PROXY_PATH_INDEX + storedPathLength) = 0
                    Dim writeLength As SQLITE_C_INT = _
                        UNIX_PROXY_PATH_INDEX + storedPathLength
                    unixFtruncate(pConch->fd, writeLength)
                    rc = unixWriteFile( _
                        CPtr(Any Ptr, pConch), @writeBuffer(0), writeLength, 0)
                    unixFsync(pConch->fd)

                    If rc = SQLITE_OK AndAlso createConch <> 0 Then
                        Dim databaseStatus As UnixStat
                        If unixFstat(pFile->fd, @databaseStatus) = 0 Then
                            unixFchmod( _
                                pConch->fd, CUInt(databaseStatus.stMode And &O666))
                        End If
                    End If
                End If
            End If
            pConch->base.pMethods->xUnlock( _
                CPtr(Any Ptr, pConch), SQLITE_LOCK_SHARED)
        End If
        If rc <> SQLITE_OK Then Exit Do

        If pFile->openFlags <> 0 Then
            If pFile->fd >= 0 Then robust_close(pFile, pFile->fd, __LINE__)
            pFile->fd = -1
            Dim replacementFd As SQLITE_C_INT = robust_open( _
                pContext->dbPath, pFile->openFlags, 0)
            If replacementFd >= 0 Then
                pFile->fd = replacementFd
            Else
                rc = SQLITE_CANTOPEN
                Exit Do
            End If
        End If

        If pContext->lockProxy = 0 Then
            Dim zProxyPath As Const ZString Ptr = tempLockPath
            If zProxyPath = 0 Then zProxyPath = pContext->lockProxyPath
            If zProxyPath = 0 Then
                rc = SQLITE_CANTOPEN
            Else
                rc = proxyCreateUnixFile( _
                    zProxyPath, @pContext->lockProxy, 1)
            End If
            If rc <> SQLITE_OK AndAlso rc <> SQLITE_NOMEM AndAlso _
               tryOldLockPath <> 0 Then
                forceNewLockPath = 1
                tryOldLockPath = 0
                Continue Do
            End If
        End If
        If rc <> SQLITE_OK Then Exit Do

        If tempLockPath <> 0 Then
            Dim pathLength As SQLITE_C_INT = 0
            While pathLength < SQLITE3_FB_APPLE_PROXY_MAXPATHLEN AndAlso _
                  tempLockPath[pathLength] <> 0
                pathLength += 1
            Wend
            If pathLength >= SQLITE3_FB_APPLE_PROXY_MAXPATHLEN Then
                rc = SQLITE_CANTOPEN
            Else
                Dim pSavedPath As ZString Ptr = CPtr( _
                    ZString Ptr, sqlite3MallocZero(CULngInt(pathLength) + 1))
                If pSavedPath = 0 Then
                    rc = SQLITE_NOMEM
                Else
                    For byteIndex As SQLITE_C_INT = 0 To pathLength
                        CPtr(UByte Ptr, pSavedPath)[byteIndex] = _
                            CPtr(Const UByte Ptr, tempLockPath)[byteIndex]
                    Next
                    pContext->lockProxyPath = pSavedPath
                End If
            End If
        End If
        Exit Do
    Loop

    If rc = SQLITE_OK Then
        pContext->conchHeld = 1
    Else
        pConch->base.pMethods->xUnlock( _
            CPtr(Any Ptr, pConch), SQLITE_LOCK_NONE)
    End If
    Return rc
End Function

Private Function proxyPathIsAuto(ByVal zPath As Const ZString Ptr) As SQLITE_C_INT
    If zPath = 0 Then Return -1
    Dim pPath As Const UByte Ptr = CPtr(Const UByte Ptr, zPath)
    If pPath[0] = 0 Then Return -1
    If pPath[0] = Asc(":") AndAlso pPath[1] = Asc("a") AndAlso _
       pPath[2] = Asc("u") AndAlso pPath[3] = Asc("t") AndAlso _
       pPath[4] = Asc("o") AndAlso pPath[5] = Asc(":") AndAlso _
       pPath[6] = 0 Then Return -1
    Return 0
End Function

Private Function proxyPathsMatch( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT
    If zLeft = 0 OrElse zRight = 0 Then Return 0
    Dim pLeft As Const UByte Ptr = CPtr(Const UByte Ptr, zLeft)
    Dim pRight As Const UByte Ptr = CPtr(Const UByte Ptr, zRight)
    For pathIndex As SQLITE_C_INT = 0 To SQLITE3_FB_APPLE_PROXY_MAXPATHLEN - 1
        If pLeft[pathIndex] <> pRight[pathIndex] Then Return 0
        If pLeft[pathIndex] = 0 Then Return -1
    Next
    Return -1
End Function

Private Function switchLockProxyPath CDecl Alias "switchLockProxyPath" ( _
    ByVal pFile As UnixFile Ptr, _
    ByVal zPath As Const ZString Ptr _
) As SQLITE_C_INT
    If pFile = 0 OrElse pFile->lockingContext = 0 Then Return SQLITE_MISUSE
    If pFile->lockLevel <> SQLITE_LOCK_NONE Then Return SQLITE_BUSY

    Dim pContext As ProxyLockingContext Ptr = _
        CPtr(ProxyLockingContext Ptr, pFile->lockingContext)
    Dim zOldPath As Const ZString Ptr = pContext->lockProxyPath
    If proxyPathIsAuto(zPath) <> 0 OrElse _
       proxyPathsMatch(zOldPath, zPath) <> 0 Then Return SQLITE_OK

    Dim zNewPath As ZString Ptr = sqlite3DbStrDup(0, zPath)
    If zNewPath = 0 Then Return SQLITE_NOMEM

    Dim pLockProxy As UnixFile Ptr = pContext->lockProxy
    If pLockProxy <> 0 Then
        If pLockProxy->base.pMethods = 0 Then
            sqlite3DbFree(0, zNewPath)
            Return SQLITE_MISUSE
        End If
        Dim rc As SQLITE_C_INT = pLockProxy->base.pMethods->xClose( _
            CPtr(Any Ptr, pLockProxy))
        If rc <> SQLITE_OK Then
            sqlite3DbFree(0, zNewPath)
            Return rc
        End If
        sqlite3_free(pLockProxy)
    End If

    pContext->lockProxy = 0
    pContext->conchHeld = 0
    sqlite3DbFree(0, pContext->lockProxyPath)
    pContext->lockProxyPath = zNewPath
    Return SQLITE_OK
End Function

Private Function proxyTransformUnixFile CDecl Alias "proxyTransformUnixFile" ( _
    ByVal pFile As UnixFile Ptr, _
    ByVal zPath As Const ZString Ptr _
) As SQLITE_C_INT
    If pFile = 0 OrElse pFile->base.pMethods = 0 Then Return SQLITE_MISUSE
    If pFile->lockLevel <> SQLITE_LOCK_NONE Then Return SQLITE_BUSY

    Dim databasePath As ZString * SQLITE3_FB_APPLE_PROXY_MAXPATHLEN
    Dim rc As SQLITE_C_INT = proxyGetDbPathForUnixFile( _
        CPtr(Any Ptr, pFile), StrPtr(databasePath))
    If rc <> SQLITE_OK Then Return rc

    Dim zLockPath As Const ZString Ptr = zPath
    If proxyPathIsAuto(zPath) <> 0 Then zLockPath = 0

    Dim pContext As ProxyLockingContext Ptr = CPtr( _
        ProxyLockingContext Ptr, sqlite3MallocZero(SizeOf(ProxyLockingContext)))
    If pContext = 0 Then Return SQLITE_NOMEM

    rc = proxyCreateConchPathname( _
        StrPtr(databasePath), @pContext->conchFilePath)
    If rc = SQLITE_OK Then
        rc = proxyCreateUnixFile( _
            pContext->conchFilePath, @pContext->conchFile, 0)
        If rc = SQLITE_CANTOPEN AndAlso _
           (pFile->openFlags And UNIX_OPEN_RDWR) = 0 Then
            Dim conchStatus As UnixStat
            If unixStat(pContext->conchFilePath, @conchStatus) = -1 Then
                Dim errorNumber As SQLITE_C_INT = unixErrno()
                If errorNumber = UNIX_ENOENT Then
                    Dim fileSystemStatus As UnixStatFs
                    If unixStatfs( _
                        StrPtr(databasePath), @fileSystemStatus) <> -1 AndAlso _
                       (fileSystemStatus.fFlags And UNIX_MNT_RDONLY) <> 0 Then
                        pContext->conchHeld = -1
                        rc = SQLITE_OK
                    End If
                End If
            End If
        End If
    End If

    If rc = SQLITE_OK AndAlso zLockPath <> 0 Then
        pContext->lockProxyPath = sqlite3DbStrDup(0, zLockPath)
        If pContext->lockProxyPath = 0 Then rc = SQLITE_NOMEM
    End If
    If rc = SQLITE_OK Then
        pContext->dbPath = sqlite3DbStrDup(0, StrPtr(databasePath))
        If pContext->dbPath = 0 Then rc = SQLITE_NOMEM
    End If

    If rc = SQLITE_OK Then
        pContext->oldLockingContext = pFile->lockingContext
        pContext->pOldMethods = pFile->base.pMethods
        pFile->lockingContext = pContext
        pFile->base.pMethods = @proxyIoMethods
        Return SQLITE_OK
    End If

    If pContext->conchFile <> 0 Then
        If pContext->conchFile->base.pMethods <> 0 Then _
            pContext->conchFile->base.pMethods->xClose( _
                CPtr(Any Ptr, pContext->conchFile))
        sqlite3_free(pContext->conchFile)
    End If
    sqlite3DbFree(0, pContext->lockProxyPath)
    sqlite3DbFree(0, pContext->dbPath)
    sqlite3_free(pContext->conchFilePath)
    sqlite3_free(pContext)
    Return rc
End Function

Private Function proxyFileControl CDecl Alias "proxyFileControl" ( _
    ByVal pFile As Any Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE

    Select Case operation
    Case SQLITE_FCNTL_GET_LOCKPROXYFILE
        If pArgument = 0 Then Return SQLITE_MISUSE
        Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
        Dim pPathOutput As ZString Ptr Ptr = _
            CPtr(ZString Ptr Ptr, pArgument)
        If pUnix->base.pMethods = @proxyIoMethods Then
            Dim pContext As ProxyLockingContext Ptr = _
                CPtr(ProxyLockingContext Ptr, pUnix->lockingContext)
            If pContext = 0 Then Return SQLITE_MISUSE
            proxyTakeConch(pUnix)
            If pContext->lockProxyPath <> 0 Then
                pPathOutput[0] = pContext->lockProxyPath
            Else
                pPathOutput[0] = StrPtr(":auto: (not held)")
            End If
        Else
            pPathOutput[0] = 0
        End If
        Return SQLITE_OK

    Case SQLITE_FCNTL_SET_LOCKPROXYFILE
        Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
        Dim isProxyStyle As SQLITE_C_INT = CInt( _
            pUnix->base.pMethods = @proxyIoMethods)
        If pArgument = 0 Then
            If isProxyStyle <> 0 Then Return SQLITE_ERROR
            Return SQLITE_OK
        End If

        Dim zProxyPath As Const ZString Ptr = _
            CPtr(Const ZString Ptr, pArgument)
        If isProxyStyle <> 0 Then
            Dim pContext As ProxyLockingContext Ptr = _
                CPtr(ProxyLockingContext Ptr, pUnix->lockingContext)
            If pContext = 0 Then Return SQLITE_MISUSE
            If proxyPathIsAuto(zProxyPath) <> 0 OrElse _
               proxyPathsMatch(pContext->lockProxyPath, zProxyPath) <> 0 Then _
                Return SQLITE_OK
            Return switchLockProxyPath(pUnix, zProxyPath)
        End If
        Return proxyTransformUnixFile(pUnix, zProxyPath)
    End Select

    Return SQLITE_NOTFOUND
End Function

Private Function proxyCheckReservedLock CDecl Alias "proxyCheckReservedLock" ( _
    ByVal pFile As Any Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pFile = 0 OrElse pResult = 0 Then Return SQLITE_MISUSE
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    Dim rc As SQLITE_C_INT = proxyTakeConch(pUnix)
    If rc <> SQLITE_OK Then Return rc

    Dim pContext As ProxyLockingContext Ptr = _
        CPtr(ProxyLockingContext Ptr, pUnix->lockingContext)
    If pContext->conchHeld > 0 Then
        Dim pLockProxy As UnixFile Ptr = pContext->lockProxy
        If pLockProxy = 0 OrElse pLockProxy->base.pMethods = 0 Then _
            Return SQLITE_IOERR_CHECKRESERVEDLOCK
        Return pLockProxy->base.pMethods->xCheckReservedLock( _
            CPtr(Any Ptr, pLockProxy), pResult)
    End If

    ' Upstream assigns pResOut itself in lockless mode; retain that behavior.
    pResult = 0
    Return SQLITE_OK
End Function

Private Function proxyLock CDecl Alias "proxyLock" ( _
    ByVal pFile As Any Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    Dim rc As SQLITE_C_INT = proxyTakeConch(pUnix)
    If rc <> SQLITE_OK Then Return rc

    Dim pContext As ProxyLockingContext Ptr = _
        CPtr(ProxyLockingContext Ptr, pUnix->lockingContext)
    If pContext->conchHeld > 0 Then
        Dim pLockProxy As UnixFile Ptr = pContext->lockProxy
        If pLockProxy = 0 OrElse pLockProxy->base.pMethods = 0 Then _
            Return SQLITE_IOERR_LOCK
        rc = pLockProxy->base.pMethods->xLock( _
            CPtr(Any Ptr, pLockProxy), lockLevel)
        pUnix->lockLevel = pLockProxy->lockLevel
    End If
    Return rc
End Function

Private Function proxyUnlock CDecl Alias "proxyUnlock" ( _
    ByVal pFile As Any Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    Dim rc As SQLITE_C_INT = proxyTakeConch(pUnix)
    If rc <> SQLITE_OK Then Return rc

    Dim pContext As ProxyLockingContext Ptr = _
        CPtr(ProxyLockingContext Ptr, pUnix->lockingContext)
    If pContext->conchHeld > 0 Then
        Dim pLockProxy As UnixFile Ptr = pContext->lockProxy
        If pLockProxy = 0 OrElse pLockProxy->base.pMethods = 0 Then _
            Return SQLITE_IOERR_UNLOCK
        rc = pLockProxy->base.pMethods->xUnlock( _
            CPtr(Any Ptr, pLockProxy), lockLevel)
        pUnix->lockLevel = pLockProxy->lockLevel
    End If
    Return rc
End Function

Private Function proxyReleaseConch CDecl Alias "proxyReleaseConch" ( _
    ByVal pFile As UnixFile Ptr _
) As SQLITE_C_INT
    If pFile = 0 OrElse pFile->lockingContext = 0 Then Return SQLITE_MISUSE
    Dim pContext As ProxyLockingContext Ptr = _
        CPtr(ProxyLockingContext Ptr, pFile->lockingContext)
    Dim pConch As UnixFile Ptr = pContext->conchFile
    If pConch = 0 OrElse pConch->base.pMethods = 0 Then Return SQLITE_IOERR_UNLOCK

    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pContext->conchHeld > 0 Then
        rc = pConch->base.pMethods->xUnlock( _
            CPtr(Any Ptr, pConch), SQLITE_LOCK_NONE)
    End If
    pContext->conchHeld = 0
    Return rc
End Function

Private Function proxyClose CDecl Alias "proxyClose" ( _
    ByVal pFile As Any Ptr _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_OK
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    If pUnix->lockingContext = 0 Then Return SQLITE_MISUSE
    Dim pContext As ProxyLockingContext Ptr = _
        CPtr(ProxyLockingContext Ptr, pUnix->lockingContext)
    Dim pLockProxy As UnixFile Ptr = pContext->lockProxy
    Dim pConch As UnixFile Ptr = pContext->conchFile
    Dim rc As SQLITE_C_INT = SQLITE_OK

    If pLockProxy <> 0 Then
        If pLockProxy->base.pMethods = 0 Then Return SQLITE_MISUSE
        rc = pLockProxy->base.pMethods->xUnlock( _
            CPtr(Any Ptr, pLockProxy), SQLITE_LOCK_NONE)
        If rc <> SQLITE_OK Then Return rc
        rc = pLockProxy->base.pMethods->xClose(CPtr(Any Ptr, pLockProxy))
        If rc <> SQLITE_OK Then Return rc
        sqlite3_free(pLockProxy)
        pContext->lockProxy = 0
    End If

    If pConch <> 0 Then
        If pContext->conchHeld <> 0 Then
            rc = proxyReleaseConch(pUnix)
            If rc <> SQLITE_OK Then Return rc
        End If
        If pConch->base.pMethods = 0 Then Return SQLITE_MISUSE
        rc = pConch->base.pMethods->xClose(CPtr(Any Ptr, pConch))
        If rc <> SQLITE_OK Then Return rc
        sqlite3_free(pConch)
        pContext->conchFile = 0
    End If

    sqlite3_free(pContext->lockProxyPath)
    sqlite3_free(pContext->conchFilePath)
    sqlite3_free(pContext->dbPath)
    Dim pOldMethods As Const sqlite3_io_methods Ptr = pContext->pOldMethods
    If pOldMethods = 0 Then Return SQLITE_MISUSE
    pUnix->lockingContext = pContext->oldLockingContext
    pUnix->base.pMethods = CPtr(sqlite3_io_methods Ptr, pOldMethods)
    sqlite3_free(pContext)
    Return pUnix->base.pMethods->xClose(pFile)
End Function
#endif

Private Function unixUnlock CDecl Alias "unixUnlock" ( _
    ByVal pFile As Any Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT
    Return posixUnlock(pFile, lockLevel, 0)
End Function

Private Function closeUnixFile CDecl Alias "closeUnixFile" ( _
    ByVal pFile As Any Ptr _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
    Return unixCloseFile(pFile)
End Function

' Dot-file locks serialize all access through one sibling lock directory.
Private Function dotlockCheckReservedLock CDecl Alias "dotlockCheckReservedLock" ( _
    ByVal pFile As Any Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pFile = 0 OrElse pResult = 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then Return SQLITE_IOERR_CHECKRESERVEDLOCK
#endif

    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    If pUnix->lockLevel >= SQLITE_LOCK_SHARED Then
        pResult[0] = 0
    ElseIf pUnix->lockingContext = 0 Then
        Return SQLITE_MISUSE
    Else
        pResult[0] = IIf( _
            unixAccess(CPtr(Const ZString Ptr, pUnix->lockingContext), _
                       UNIX_ACCESS_EXISTS) = 0, 1, 0)
    End If
    Return SQLITE_OK
End Function

Private Function dotlockLock CDecl Alias "dotlockLock" ( _
    ByVal pFile As Any Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFile = 0 OrElse lockLevel < SQLITE_LOCK_SHARED OrElse _
       lockLevel > SQLITE_LOCK_EXCLUSIVE Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then Return SQLITE_IOERR_LOCK
#endif

    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    If pUnix->lockingContext = 0 Then Return SQLITE_MISUSE
    Dim zLockPath As Const ZString Ptr = _
        CPtr(Const ZString Ptr, pUnix->lockingContext)
    If pUnix->lockLevel > SQLITE_LOCK_NONE Then
        pUnix->lockLevel = lockLevel
        unixUtimes(zLockPath, 0)
        Return SQLITE_OK
    End If

    If unixMkdir(zLockPath, &O777) = 0 Then
        pUnix->lockLevel = lockLevel
        Return SQLITE_OK
    End If

    Dim errorNumber As SQLITE_C_INT = unixErrno()
    If errorNumber = UNIX_EEXIST Then Return SQLITE_BUSY
    Dim rc As SQLITE_C_INT
    Select Case errorNumber
    Case UNIX_EACCES, UNIX_EAGAIN, UNIX_ETIMEDOUT, UNIX_EBUSY, _
         UNIX_EINTR, UNIX_ENOLCK
        rc = SQLITE_BUSY
    Case UNIX_EPERM
        rc = SQLITE_PERM
    Case Else
        rc = SQLITE_IOERR_LOCK
    End Select
    If rc <> SQLITE_BUSY Then pUnix->lastErrno = errorNumber
    Return rc
End Function

Private Function dotlockUnlock CDecl Alias "dotlockUnlock" ( _
    ByVal pFile As Any Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFile = 0 OrElse lockLevel < SQLITE_LOCK_NONE OrElse _
       lockLevel > SQLITE_LOCK_SHARED Then Return SQLITE_MISUSE
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    If pUnix->lockLevel = lockLevel Then Return SQLITE_OK
    If lockLevel = SQLITE_LOCK_SHARED Then
        pUnix->lockLevel = lockLevel
        Return SQLITE_OK
    End If
    If pUnix->lockingContext = 0 Then Return SQLITE_MISUSE

    If unixRmdir(CPtr(Const ZString Ptr, pUnix->lockingContext)) <> 0 Then
        Dim errorNumber As SQLITE_C_INT = unixErrno()
        If errorNumber = UNIX_ENOENT Then Return SQLITE_OK
        pUnix->lastErrno = errorNumber
        Return SQLITE_IOERR_UNLOCK
    End If
    pUnix->lockLevel = SQLITE_LOCK_NONE
    Return SQLITE_OK
End Function

Private Function dotlockClose CDecl Alias "dotlockClose" ( _
    ByVal pFile As Any Ptr _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    dotlockUnlock(pFile, SQLITE_LOCK_NONE)
    ' The common close path owns inode and descriptor cleanup for this port.
    pUnix->lockLevel = SQLITE_LOCK_NONE
    Return unixCloseFile(pFile)
End Function

#ifdef SQLITE_ENABLE_LOCKING_STYLE
' flock() operations apply to the Linux file descriptor, not SQLite byte ranges.
Private Function robust_flock CDecl Alias "robust_flock" ( _
    ByVal fd As SQLITE_C_INT, _
    ByVal operation As SQLITE_C_INT _
) As SQLITE_C_INT
    Dim result As SQLITE_C_INT
    Do
        result = unixFlock(fd, operation)
    Loop While result < 0 AndAlso unixErrno() = UNIX_EINTR
    Return result
End Function

Private Function flockCheckReservedLock CDecl Alias "flockCheckReservedLock" ( _
    ByVal pFile As Any Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pResult = 0 OrElse pFile = 0 Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("flock reserved-lock arguments are valid"))
#endif
        Return SQLITE_MISUSE
    End If

    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    If pUnix->lockLevel > SQLITE_LOCK_SHARED Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("flock holds only an exclusive OS lock"))
#endif
        Return SQLITE_IOERR_CHECKRESERVEDLOCK
    End If
    ' This VFS promotes every non-NO_LOCK state to an OS-level exclusive lock.
    pResult[0] = 0
    Return SQLITE_OK
End Function

Private Function flockLock CDecl Alias "flockLock" ( _
    ByVal pFile As Any Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFile = 0 OrElse lockLevel < SQLITE_LOCK_NONE OrElse _
       lockLevel > SQLITE_LOCK_EXCLUSIVE Then Return SQLITE_MISUSE

    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    If pUnix->lockLevel > SQLITE_LOCK_NONE Then
        pUnix->lockLevel = lockLevel
        Return SQLITE_OK
    End If
    If pUnix->fd < 0 Then Return SQLITE_IOERR_LOCK

    Dim rc As SQLITE_C_INT = SQLITE_OK
    If robust_flock(pUnix->fd, UNIX_LOCK_EXCLUSIVE Or UNIX_LOCK_NONBLOCKING) <> 0 Then
        Dim errorNumber As SQLITE_C_INT = unixErrno()
        Select Case errorNumber
        Case UNIX_EACCES, UNIX_EAGAIN, UNIX_EBUSY, UNIX_EINTR, _
             UNIX_ENOLCK, UNIX_ETIMEDOUT
            rc = SQLITE_BUSY
        Case UNIX_EPERM
            rc = SQLITE_PERM
        Case Else
            rc = SQLITE_IOERR_LOCK
        End Select
        If rc <> SQLITE_OK AndAlso rc <> SQLITE_BUSY Then _
            pUnix->lastErrno = errorNumber
    Else
        pUnix->lockLevel = lockLevel
    End If

#ifdef SQLITE_IGNORE_FLOCK_LOCK_ERRORS
    If (rc And &HFF) = SQLITE_IOERR Then rc = SQLITE_BUSY
#endif
    Return rc
End Function

Private Function flockUnlock CDecl Alias "flockUnlock" ( _
    ByVal pFile As Any Ptr, _
    ByVal lockLevel As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFile = 0 OrElse lockLevel < SQLITE_LOCK_NONE OrElse _
       lockLevel > SQLITE_LOCK_SHARED Then Return SQLITE_MISUSE

    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    If pUnix->lockLevel = lockLevel Then Return SQLITE_OK

    If lockLevel = SQLITE_LOCK_SHARED Then
        pUnix->lockLevel = lockLevel
        Return SQLITE_OK
    End If

    If robust_flock(pUnix->fd, UNIX_LOCK_RELEASE) <> 0 Then
#ifdef SQLITE_IGNORE_FLOCK_LOCK_ERRORS
        Return SQLITE_OK
#else
        Return SQLITE_IOERR_UNLOCK
#endif
    End If
    pUnix->lockLevel = SQLITE_LOCK_NONE
    Return SQLITE_OK
End Function

Private Function flockClose CDecl Alias "flockClose" (ByVal pFile As Any Ptr) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
    flockUnlock(pFile, SQLITE_LOCK_NONE)
    Return closeUnixFile(pFile)
End Function
#endif

Private Function nolockClose CDecl Alias "nolockClose" ( _
    ByVal pFile As Any Ptr _
) As SQLITE_C_INT
    Return closeUnixFile(pFile)
End Function

Private Function unixCheckReservedLock(ByVal pFile As Any Ptr, ByVal pResult As SQLITE_C_INT Ptr) As SQLITE_C_INT
    If pFile = 0 OrElse pResult = 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then Return SQLITE_IOERR_CHECKRESERVEDLOCK
#endif
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    Dim pInfo As UnixLockInfo Ptr = pUnix->pLockInfo
    If pInfo = 0 Then Return SQLITE_IOERR_CHECKRESERVEDLOCK
    unixEnterMutex()
    Dim result As SQLITE_C_INT = IIf(pInfo->pReserved <> 0 OrElse pInfo->pPending <> 0 OrElse pInfo->pExclusive <> 0, 1, 0)
    If result = 0 Then
        Dim reserved As SQLITE_C_INT = unixOtherProcessHasWriteLock(pUnix->fd, UNIX_RESERVED_BYTE, 1)
        Dim pending As SQLITE_C_INT = unixOtherProcessHasWriteLock(pUnix->fd, UNIX_PENDING_BYTE, 1)
        If reserved < 0 OrElse pending < 0 Then
            unixLeaveMutex()
            Return SQLITE_IOERR_CHECKRESERVEDLOCK
        End If
        result = IIf(reserved <> 0 OrElse pending <> 0, 1, 0)
    End If
    pResult[0] = result
    unixLeaveMutex()
    Return SQLITE_OK
End Function

Private Function fcntlSizeHint( _
    ByVal pUnix As UnixFile Ptr, _
    ByVal requestedBytes As sqlite3_int64 _
) As SQLITE_C_INT
    If pUnix = 0 OrElse requestedBytes < 0 Then Return SQLITE_MISUSE

    If pUnix->szChunk > 0 Then
        Dim statInfo As UnixStat
        If unixFstat(pUnix->fd, @statInfo) <> 0 Then Return SQLITE_IOERR_FSTAT
        Dim chunkSize As sqlite3_int64 = pUnix->szChunk
        If requestedBytes > &H7FFFFFFFFFFFFFFFLL - (chunkSize - 1) Then _
            Return SQLITE_TOOBIG
        Dim requiredBytes As sqlite3_int64 = _
            ((requestedBytes + chunkSize - 1) \ chunkSize) * chunkSize

        If requiredBytes > statInfo.stSize Then
            ' Match the fallback when posix_fallocate() is unavailable by
            ' touching the last byte in each fully extended filesystem block.
            Dim blockSize As sqlite3_int64 = statInfo.stBlksize
            If blockSize <= 0 Then blockSize = SQLITE_DEFAULT_SECTOR_SIZE
            If requiredBytes > &H7FFFFFFFFFFFFFFFLL - (blockSize - 1) Then _
                Return SQLITE_TOOBIG
            Dim writeOffset As sqlite3_int64 = _
                (statInfo.stSize \ blockSize) * blockSize + blockSize - 1
            Dim endOffset As sqlite3_int64 = requiredBytes + blockSize - 1
            While writeOffset < endOffset
                If writeOffset >= requiredBytes Then _
                    writeOffset = requiredBytes - 1
                If seekAndWrite(pUnix, writeOffset, StrPtr(""), 1) <> 1 Then _
                    Return SQLITE_IOERR_WRITE
                If writeOffset = requiredBytes - 1 Then Exit While
                writeOffset += blockSize
            Wend
        End If
    End If

#if SQLITE_MAX_MMAP_SIZE > 0
    If pUnix->mmapSizeMax > 0 AndAlso requestedBytes > pUnix->mmapSize Then
        If pUnix->szChunk <= 0 Then
            If robust_ftruncate(pUnix->fd, requestedBytes) <> 0 Then
                storeLastErrno(pUnix, unixErrno())
                Return unixPathLogError( _
                    SQLITE_IOERR_TRUNCATE, StrPtr("ftruncate"), _
                    unixPathToZString(@pUnix->zPath(0)))
            End If
        End If
        Return unixMapfile(pUnix, requestedBytes)
    End If
#endif
    Return SQLITE_OK
End Function

Private Sub unixModeBit( _
    ByVal pUnix As UnixFile Ptr, _
    ByVal mask As UByte, _
    ByVal pArgument As SQLITE_C_INT Ptr _
)
    If pUnix = 0 OrElse pArgument = 0 Then Return
    If pArgument[0] < 0 Then
        pArgument[0] = IIf((pUnix->ctrlFlags And mask) <> 0, 1, 0)
    ElseIf pArgument[0] = 0 Then
        pUnix->ctrlFlags = pUnix->ctrlFlags And Not mask
    Else
        pUnix->ctrlFlags = pUnix->ctrlFlags Or mask
    End If
End Sub

#ifndef SQLITE_OMIT_WAL
Private Function unixFcntlExternalReader( _
    ByVal pUnix As UnixFile Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pUnix = 0 OrElse pResult = 0 Then Return SQLITE_MISUSE
    pResult[0] = 0

    unixEnterMutex()
    Dim pNode As UnixShmNode Ptr = pUnix->pShmNode
    If pNode <> 0 Then
        Dim hasReader As SQLITE_C_INT = unixOtherProcessHasWriteLock( _
            pNode->fd, UNIX_SHM_BASE_BYTE + 3, SQLITE_SHM_NLOCK - 3)
        If hasReader < 0 Then
            unixLeaveMutex()
            Return SQLITE_IOERR_LOCK
        End If
        pResult[0] = hasReader
    End If
    unixLeaveMutex()
    Return SQLITE_OK
End Function
#endif

#if defined(SQLITE_DEBUG) OrElse defined(SQLITE_ENABLE_FILESTAT)
Private Function unixFindText( _
    ByVal pText As Const UByte Ptr, _
    ByVal firstByte As SQLITE_C_INT, _
    ByVal endByte As SQLITE_C_INT, _
    ByVal zNeedle As Const ZString Ptr _
) As SQLITE_C_INT
    If pText = 0 OrElse zNeedle = 0 OrElse firstByte < 0 OrElse _
       endByte < firstByte Then Return -1
    Dim needleLength As SQLITE_C_INT = 0
    While zNeedle[needleLength] <> 0
        needleLength += 1
    Wend
    If needleLength = 0 OrElse needleLength > endByte - firstByte Then Return -1

    For iByte As SQLITE_C_INT = firstByte To endByte - needleLength
        Dim matched As SQLITE_C_INT = 1
        For iNeedle As SQLITE_C_INT = 0 To needleLength - 1
            If pText[iByte + iNeedle] <> CByte(zNeedle[iNeedle]) Then
                matched = 0
                Exit For
            End If
        Next
        If matched <> 0 Then Return iByte
    Next
    Return -1
End Function

Private Function unixParseLockOffset( _
    ByVal pText As Const UByte Ptr, _
    ByVal firstByte As SQLITE_C_INT, _
    ByVal endByte As SQLITE_C_INT _
) As sqlite3_int64
    If pText = 0 OrElse firstByte < 0 OrElse endByte <= firstByte Then Return 0
    Dim value As sqlite3_int64 = 0
    For iByte As SQLITE_C_INT = firstByte To endByte - 1
        Dim c As UByte = pText[iByte]
        If c < Asc("0") OrElse c > Asc("9") Then Return 0
        Dim digit As SQLITE_C_INT = c - Asc("0")
        If value > (&H7FFFFFFFFFFFFFFFLL - digit) \ 10 Then _
            Return &H7FFFFFFFFFFFFFFFLL
        value = value * 10 + digit
    Next
    Return value
End Function

Private Function unixPosixAdvisoryLocks CDecl Alias "unixPosixAdvisoryLocks" ( _
    ByVal fd As SQLITE_C_INT, _
    ByVal aLock As UByte Ptr _
) As SQLITE_C_INT
    If fd < 0 OrElse aLock = 0 Then Return SQLITE_ERROR_UNABLE

    Dim zInitial As ZString * 16 = "---/-.---.-----"
    For iByte As SQLITE_C_INT = 0 To 15
        aLock[iByte] = CByte(zInitial[iByte])
    Next

    Dim zPath As ZString * 2000
    sqlite3_snprintf(SizeOf(zPath), @zPath, _
        StrPtr("/proc/%d/fdinfo/%d"), unixGetPid(), fd)
    Dim fdInfo As SQLITE_C_INT = unixOpen(@zPath, UNIX_OPEN_READONLY, 0)
    If fdInfo < 0 Then Return SQLITE_ERROR_UNABLE

    Dim zText(0 To 1999) As UByte
    Dim nByte As sqlite3_int64 = unixSystemRead( _
        fdInfo, @zText(0), SizeOf(zText) - 1)
    unixCloseFd(fdInfo)
    If nByte <= 0 OrElse nByte >= SizeOf(zText) Then Return SQLITE_ERROR_UNABLE
    zText(CLngInt(nByte)) = 0

    Dim zLockPrefix As ZString * 7 = "lock:" & Chr(9)
    Dim zReadToken As ZString * 7 = " READ "
    Dim zWriteToken As ZString * 8 = " WRITE "
    Dim pNext As SQLITE_C_INT = unixFindText( _
        @zText(0), 0, CLngInt(nByte), @zLockPrefix)
    While pNext >= 0
        Dim p As SQLITE_C_INT = pNext + 6
        Dim pNextLine As SQLITE_C_INT = unixFindText( _
            @zText(0), p, CLngInt(nByte), @zLockPrefix)
        Dim lineEnd As SQLITE_C_INT = CLngInt(nByte)
        If pNextLine >= 0 Then lineEnd = pNextLine - 1

        If lineEnd > p Then
            Dim pKind As SQLITE_C_INT = unixFindText( _
                @zText(0), p, lineEnd, @zReadToken)
            Dim pOffsetText As SQLITE_C_INT = -1
            Dim lockType As UByte = 0
            If pKind >= 0 Then
                lockType = Asc("r")
                pOffsetText = pKind + 6
            Else
                pKind = unixFindText(@zText(0), p, lineEnd, @zWriteToken)
                If pKind >= 0 Then
                    lockType = Asc("w")
                    pOffsetText = pKind + 7
                End If
            End If

            If pOffsetText >= 0 Then
                Dim lastSpace As SQLITE_C_INT = -1
                For iByte As SQLITE_C_INT = pOffsetText To lineEnd - 1
                    If zText(iByte) = Asc(" ") Then lastSpace = iByte
                Next
                If lastSpace >= 0 AndAlso lastSpace + 1 < lineEnd Then
                    Dim firstSpace As SQLITE_C_INT = -1
                    For iByte As SQLITE_C_INT = pOffsetText To lastSpace - 1
                        If zText(iByte) = Asc(" ") Then firstSpace = iByte
                    Next
                    If firstSpace >= 0 AndAlso firstSpace + 1 < lastSpace Then
                        Dim iFirst As sqlite3_int64 = unixParseLockOffset( _
                            @zText(0), firstSpace + 1, lastSpace)
                        Dim iLast As sqlite3_int64 = unixParseLockOffset( _
                            @zText(0), lastSpace + 1, lineEnd)

                        If iLast >= UNIX_PENDING_BYTE Then
                            If iFirst <= UNIX_PENDING_BYTE AndAlso _
                               iLast >= UNIX_PENDING_BYTE Then aLock[0] = lockType
                            If iFirst <= UNIX_RESERVED_BYTE AndAlso _
                               iLast >= UNIX_RESERVED_BYTE Then aLock[1] = lockType
                            If iFirst <= UNIX_SHARED_FIRST AndAlso _
                               iLast >= UNIX_PENDING_BYTE + UNIX_SHARED_SIZE Then _
                                aLock[2] = lockType
                        ElseIf iLast <= UNIX_SHM_BASE_BYTE + SQLITE_SHM_NLOCK Then
                            If iFirst <= UNIX_SHM_BASE_BYTE + SQLITE_SHM_NLOCK AndAlso _
                               iLast >= UNIX_SHM_BASE_BYTE + SQLITE_SHM_NLOCK Then _
                                aLock[4] = lockType
                            If iFirst <= UNIX_SHM_BASE_BYTE AndAlso _
                               iLast >= UNIX_SHM_BASE_BYTE Then aLock[6] = lockType
                            If iFirst <= UNIX_SHM_BASE_BYTE + 1 AndAlso _
                               iLast >= UNIX_SHM_BASE_BYTE + 1 Then aLock[7] = lockType
                            If iFirst <= UNIX_SHM_BASE_BYTE + 2 AndAlso _
                               iLast >= UNIX_SHM_BASE_BYTE + 2 Then aLock[8] = lockType
                            For iReadLock As SQLITE_C_INT = 0 To 4
                                Dim lockOffset As sqlite3_int64 = _
                                    UNIX_SHM_BASE_BYTE + 3 + iReadLock
                                If iFirst <= lockOffset AndAlso iLast >= lockOffset Then _
                                    aLock[10 + iReadLock] = lockType
                            Next
                        End If
                    End If
                End If
            End If
        End If
        pNext = pNextLine
    Wend
    Return SQLITE_OK
End Function

Private Sub unixDescribeShm( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal pUnix As UnixFile Ptr _
)
    If pAccum = 0 OrElse pUnix = 0 OrElse pUnix->pShmNode = 0 Then Exit Sub
    Dim pNode As UnixShmNode Ptr = pUnix->pShmNode
    Dim sharedMask As SQLITE_C_INT = 0
    Dim exclusiveMask As SQLITE_C_INT = 0
    For iLock As SQLITE_C_INT = 0 To SQLITE_SHM_NLOCK - 1
        If pUnix->aShmLock(iLock) = SQLITE_SHM_SHARED Then _
            sharedMask Or= (1 Shl iLock)
        If pUnix->aShmLock(iLock) = SQLITE_SHM_EXCLUSIVE Then _
            exclusiveMask Or= (1 Shl iLock)
    Next
    unixStrAppendf(pAccum, StrPtr( _
        !"{\034h\034:%d,\034nRef\034:%u,\034sharedMask\034:%d,\034exclMask\034:%d"), _
        pNode->fd, pNode->nRef, sharedMask, exclusiveMask)
    Dim aLock(0 To 15) As UByte
    If unixPosixAdvisoryLocks(pNode->fd, @aLock(0)) = SQLITE_OK Then _
        unixStrAppendf(pAccum, StrPtr(!",\034pal\034:\034%s\034"), _
            CPtr(Const ZString Ptr, @aLock(0)))
    sqlite3_str_append(pAccum, StrPtr("}"), 1)
End Sub

Private Function unixFileStat( _
    ByVal pUnix As UnixFile Ptr, _
    ByVal pAccum As sqlite3_str Ptr _
) As SQLITE_C_INT
    If pUnix = 0 OrElse pAccum = 0 Then Return SQLITE_MISUSE

    Dim zVfsName As Const ZString Ptr = StrPtr("")
    If pUnix->pVfs <> 0 AndAlso pUnix->pVfs->zName <> 0 Then _
        zVfsName = pUnix->pVfs->zName
    unixStrAppendf(pAccum, StrPtr( _
        !"{\034h\034:%d,\034vfs\034:\034%s\034"), pUnix->fd, zVfsName)

    Dim zLockName As Const ZString Ptr = 0
    Select Case pUnix->lockLevel
    Case 1: zLockName = StrPtr("SHARED")
    Case 2: zLockName = StrPtr("RESERVED")
    Case 3: zLockName = StrPtr("PENDING")
    Case 4: zLockName = StrPtr("EXCLUSIVE")
    End Select
    If zLockName <> 0 Then
        unixStrAppendf(pAccum, StrPtr(!",\034eFileLock\034:\034%s\034"), zLockName)
        Dim aLock(0 To 15) As UByte
        If unixPosixAdvisoryLocks(pUnix->fd, @aLock(0)) = SQLITE_OK Then _
            unixStrAppendf(pAccum, StrPtr(!",\034pal\034:\034%s\034"), _
                CPtr(Const ZString Ptr, @aLock(0)))
    End If

    unixEnterMutex()
    If pUnix->pShmNode <> 0 Then
        sqlite3_str_appendall(pAccum, StrPtr(!",\034shm\034:"))
        unixDescribeShm(pAccum, pUnix)
    End If
    If pUnix->pLockInfo <> 0 Then
        Dim pInfo As UnixLockInfo Ptr = pUnix->pLockInfo
        unixStrAppendf(pAccum, StrPtr( _
            !",\034inode\034:{\034nRef\034:%u,\034nShared\034:%u"), _
            pInfo->nRef, pInfo->nShared)
        Dim inodeLockName As Const ZString Ptr = 0
        If pInfo->pExclusive <> 0 Then
            inodeLockName = StrPtr("EXCLUSIVE")
        ElseIf pInfo->pPending <> 0 Then
            inodeLockName = StrPtr("PENDING")
        ElseIf pInfo->pReserved <> 0 Then
            inodeLockName = StrPtr("RESERVED")
        ElseIf pInfo->nShared <> 0 Then
            inodeLockName = StrPtr("SHARED")
        End If
        If inodeLockName <> 0 Then _
            unixStrAppendf(pAccum, StrPtr(!",\034eFileLock\034:\034%s\034"), inodeLockName)
        If pInfo->pDeferred <> 0 Then
            sqlite3_str_appendall(pAccum, StrPtr(!",\034unusedFd\034:["))
            Dim pDeferred As UnixDeferredFd Ptr = pInfo->pDeferred
            Dim separator As UByte = Asc("[")
            While pDeferred <> 0
                unixStrAppendf(pAccum, StrPtr(!"%c{\034fd\034:%d"), _
                    CInt(separator), pDeferred->fd)
                separator = Asc(",")
                Dim aLock(0 To 15) As UByte
                If unixPosixAdvisoryLocks(pDeferred->fd, @aLock(0)) = SQLITE_OK Then _
                    unixStrAppendf(pAccum, StrPtr(!",\034pal\034:\034%s\034"), _
                        CPtr(Const ZString Ptr, @aLock(0)))
                sqlite3_str_append(pAccum, StrPtr("}"), 1)
                pDeferred = pDeferred->pNext
            Wend
            sqlite3_str_append(pAccum, StrPtr("]"), 1)
        End If
        sqlite3_str_append(pAccum, StrPtr("}"), 1)
    End If
    unixLeaveMutex()
    sqlite3_str_append(pAccum, StrPtr("}"), 1)
    Return SQLITE_OK
End Function
#endif

Private Function unixFileControl(ByVal pFile As Any Ptr, ByVal operation As SQLITE_C_INT, ByVal pArgument As Any Ptr) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
#if SQLITE3_FB_APPLE_LOCKING_STYLE
    If operation = SQLITE_FCNTL_GET_LOCKPROXYFILE OrElse _
       operation = SQLITE_FCNTL_SET_LOCKPROXYFILE Then _
        Return proxyFileControl(pFile, operation, pArgument)
#endif
#if defined(SQLITE_DEBUG) OrElse defined(SQLITE_ENABLE_FILESTAT)
    If operation = SQLITE_FCNTL_FILESTAT Then
        If pArgument = 0 Then Return SQLITE_MISUSE
        Return unixFileStat(pUnix, CPtr(sqlite3_str Ptr, pArgument))
    End If
#endif
    If operation = SQLITE_FCNTL_LAST_ERRNO Then
        If pArgument = 0 Then Return SQLITE_MISUSE
        CPtr(SQLITE_C_INT Ptr, pArgument)[0] = pUnix->lastErrno
        Return SQLITE_OK
    End If
    If operation = SQLITE_FCNTL_NULL_IO Then
        If pUnix->fd >= 0 Then unixCloseFd(pUnix->fd)
        pUnix->fd = -1
        Return SQLITE_OK
    End If
    If operation = SQLITE_FCNTL_FILE_POINTER Then
        If pArgument = 0 Then Return SQLITE_MISUSE
        CPtr(sqlite3_file Ptr Ptr, pArgument)[0] = CPtr(sqlite3_file Ptr, pFile)
        Return SQLITE_OK
    End If
    If operation = SQLITE_FCNTL_VFS_POINTER Then
        If pArgument = 0 Then Return SQLITE_MISUSE
        CPtr(sqlite3_vfs Ptr Ptr, pArgument)[0] = pUnix->pVfs
        Return SQLITE_OK
    End If
    If operation = SQLITE_FCNTL_VFSNAME Then
        If pArgument = 0 Then Return SQLITE_MISUSE
        Dim zVfsName As Const ZString Ptr = 0
        If pUnix->pVfs <> 0 Then zVfsName = pUnix->pVfs->zName
        Dim nameLength As SQLITE_C_INT = 0
        If zVfsName <> 0 Then
            While nameLength < UNIX_PATH_MAX - 1 AndAlso zVfsName[nameLength] <> 0
                nameLength += 1
            Wend
        End If
        Dim zCopy As ZString Ptr = CPtr(ZString Ptr, _
            sqlite3MallocZero(CULngInt(nameLength) + 1))
        If zCopy <> 0 AndAlso zVfsName <> 0 Then
            For nameIndex As SQLITE_C_INT = 0 To nameLength - 1
                zCopy[nameIndex] = zVfsName[nameIndex]
            Next
        End If
        CPtr(ZString Ptr Ptr, pArgument)[0] = zCopy
        Return SQLITE_OK
    End If
    If operation = 1 AndAlso pArgument <> 0 Then
        CPtr(SQLITE_C_INT Ptr, pArgument)[0] = pUnix->lockLevel
        Return SQLITE_OK
    End If
    If operation = SQLITE_FCNTL_HAS_MOVED Then
        If pArgument = 0 Then Return SQLITE_MISUSE
        CPtr(SQLITE_C_INT Ptr, pArgument)[0] = _
            fileHasMoved(CPtr(UnixFile Ptr, pFile))
        Return SQLITE_OK
    End If
    If operation = SQLITE_FCNTL_TEMPFILENAME Then
        If pArgument = 0 Then Return SQLITE_MISUSE
        Dim zTempFilename As ZString Ptr = CPtr( _
            ZString Ptr, sqlite3MallocZero(UNIX_PATH_MAX))
        If zTempFilename <> 0 Then
            unixGetTempname(UNIX_PATH_MAX - 1, zTempFilename)
            CPtr(ZString Ptr Ptr, pArgument)[0] = zTempFilename
        End If
        Return SQLITE_OK
    End If
    If operation = SQLITE_FCNTL_CHUNK_SIZE Then
        If pArgument = 0 Then Return SQLITE_MISUSE
        CPtr(UnixFile Ptr, pFile)->szChunk = _
            CPtr(SQLITE_C_INT Ptr, pArgument)[0]
        Return SQLITE_OK
    End If
    If operation = SQLITE_FCNTL_SIZE_HINT Then
        If pArgument = 0 Then Return SQLITE_MISUSE
        Return fcntlSizeHint(CPtr(UnixFile Ptr, pFile), _
            CPtr(sqlite3_int64 Ptr, pArgument)[0])
    End If
    If operation = SQLITE_FCNTL_EXTERNAL_READER Then
        If pArgument = 0 Then Return SQLITE_MISUSE
#ifndef SQLITE_OMIT_WAL
        Return unixFcntlExternalReader( _
            CPtr(UnixFile Ptr, pFile), CPtr(SQLITE_C_INT Ptr, pArgument))
#else
        CPtr(SQLITE_C_INT Ptr, pArgument)[0] = 0
        Return SQLITE_OK
#endif
    End If
    If operation = SQLITE_FCNTL_PERSIST_WAL Then
        If pArgument = 0 Then Return SQLITE_MISUSE
        unixModeBit(CPtr(UnixFile Ptr, pFile), _
                    UNIXFILE_PERSIST_WAL, CPtr(SQLITE_C_INT Ptr, pArgument))
        Return SQLITE_OK
    End If
    If operation = SQLITE_FCNTL_POWERSAFE_OVERWRITE Then
        If pArgument = 0 Then Return SQLITE_MISUSE
        unixModeBit(CPtr(UnixFile Ptr, pFile), _
                    UNIXFILE_PSOW, CPtr(SQLITE_C_INT Ptr, pArgument))
        Return SQLITE_OK
    End If
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    If operation = SQLITE_FCNTL_LOCK_TIMEOUT Then
        If pArgument = 0 Then Return SQLITE_MISUSE
        Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
        Dim previousTimeout As SQLITE_C_INT = Cast(SQLITE_C_INT, pUnix->iBusyTimeout)
        Dim newTimeout As SQLITE_C_INT = CPtr(SQLITE_C_INT Ptr, pArgument)[0]
#if SQLITE_ENABLE_SETLK_TIMEOUT = 1
        If newTimeout < 0 Then
            ' C uses the largest signed int to represent an infinite wait.
            pUnix->iBusyTimeout = &H7FFFFFFF
        Else
            pUnix->iBusyTimeout = CUInt(newTimeout)
        End If
#elseif SQLITE_ENABLE_SETLK_TIMEOUT = 2
        pUnix->iBusyTimeout = IIf(newTimeout <> 0, 1, 0)
#else
#error "SQLITE_ENABLE_SETLK_TIMEOUT must be set to 1 or 2"
#endif
        CPtr(SQLITE_C_INT Ptr, pArgument)[0] = previousTimeout
        Return SQLITE_OK
    ElseIf operation = SQLITE_FCNTL_BLOCK_ON_CONNECT Then
        If pArgument = 0 Then Return SQLITE_MISUSE
        CPtr(UnixFile Ptr, pFile)->bBlockOnConnect = _
            IIf(CPtr(SQLITE_C_INT Ptr, pArgument)[0] <> 0, 1, 0)
        Return SQLITE_OK
    End If
#endif
#if SQLITE_MAX_MMAP_SIZE > 0
    If operation = SQLITE_FCNTL_MMAP_SIZE Then
        If pArgument = 0 Then Return SQLITE_MISUSE
        Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
        Dim newLimit As sqlite3_int64 = CPtr(sqlite3_int64 Ptr, pArgument)[0]
        Dim maximumLimit As sqlite3_int64 = sqlite3ConfigMmapSizeMaximum()
        If maximumLimit > SQLITE_MAX_MMAP_SIZE Then maximumLimit = SQLITE_MAX_MMAP_SIZE
        If newLimit > maximumLimit Then newLimit = maximumLimit
        If newLimit > 0 AndAlso SizeOf(Any Ptr) < 8 Then _
            newLimit = newLimit And &H7FFFFFFF

        CPtr(sqlite3_int64 Ptr, pArgument)[0] = pUnix->mmapSizeMax
        If newLimit >= 0 AndAlso newLimit <> pUnix->mmapSizeMax AndAlso _
           pUnix->nFetchOut = 0 Then
            pUnix->mmapSizeMax = newLimit
            If pUnix->mmapSize > 0 Then
                unixUnmapfile(pUnix)
                Return unixMapfile(pUnix, -1)
            End If
        End If
        Return SQLITE_OK
    End If
#endif
    Return SQLITE_NOTFOUND
End Function

Private Sub setDeviceCharacteristics(ByVal pUnix As UnixFile Ptr)
    If pUnix = 0 OrElse pUnix->sectorSize <> 0 Then Return
#if defined(__FB_LINUX__) AndAlso defined(SQLITE_ENABLE_BATCH_ATOMIC_WRITE)
    Dim features As SQLITE_C_UINT = 0
    If unixIoctl(pUnix->fd, F2FS_IOC_GET_FEATURES, @features) = 0 AndAlso _
       (features And F2FS_FEATURE_ATOMIC_WRITE) <> 0 Then
        pUnix->deviceCharacteristics Or= SQLITE_IOCAP_BATCH_ATOMIC
    End If
#endif
    If (pUnix->ctrlFlags And UNIXFILE_PSOW) <> 0 Then _
        pUnix->deviceCharacteristics Or= SQLITE_IOCAP_POWERSAFE_OVERWRITE
    pUnix->deviceCharacteristics Or= SQLITE_IOCAP_SUBPAGE_READ
    pUnix->sectorSize = SQLITE_DEFAULT_SECTOR_SIZE
End Sub

Private Function unixSectorSize(ByVal pFile As Any Ptr) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_DEFAULT_SECTOR_SIZE
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    setDeviceCharacteristics(pUnix)
    Return pUnix->sectorSize
End Function

Private Function unixDeviceCharacteristics(ByVal pFile As Any Ptr) As SQLITE_C_INT
    If pFile = 0 Then Return 0
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    setDeviceCharacteristics(pUnix)
    Return pUnix->deviceCharacteristics
End Function

Private Function unixDelete(ByVal pVfs As Any Ptr, ByVal zName As Const ZString Ptr, ByVal syncDirectory As SQLITE_C_INT) As SQLITE_C_INT
    If zName = 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then Return SQLITE_IOERR_DELETE
#endif
    Dim unlinkResult As SQLITE_C_INT = unixUnlink(zName)
    If unlinkResult < 0 Then
        ' A missing rollback journal means commit could not make the journal
        ' deletion durable. Keep this distinct from other unlink failures.
        If unixErrno() = UNIX_ENOENT Then Return SQLITE_IOERR_DELETE_NOENT
        Return SQLITE_IOERR_DELETE
    End If
    If syncDirectory = 0 Then Return SQLITE_OK

    Dim zDirectory As ZString * UNIX_PATH_MAX
    Dim n As Long = 0
    While n < UNIX_PATH_MAX - 1 AndAlso zName[n] <> 0
        zDirectory[n] = zName[n]
        n += 1
    Wend
    While n > 0 AndAlso zDirectory[n - 1] <> Asc("/")
        n -= 1
    Wend
    If n = 0 Then
        zDirectory = "."
    ElseIf n = 1 Then
        zDirectory[1] = 0
    Else
        zDirectory[n - 1] = 0
    End If
    Dim fd As SQLITE_C_INT = unixOpen(@zDirectory, UNIX_OPEN_READONLY Or UNIX_OPEN_DIRECTORY Or UNIX_OPEN_CLOEXEC, 0)
    If fd < 0 Then Return SQLITE_IOERR_DIR_FSYNC
    Dim rc As SQLITE_C_INT = unixFsync(fd)
    unixCloseFd(fd)
    If rc <> 0 Then Return SQLITE_IOERR_DIR_FSYNC
    Return SQLITE_OK
End Function

Private Function unixAccessVfs CDecl Alias "unixAccess" ( _
    ByVal pVfs As Any Ptr, ByVal zName As Const ZString Ptr, _
    ByVal flags As SQLITE_C_INT, ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If zName = 0 OrElse pResult = 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then Return SQLITE_IOERR_ACCESS
#endif
    If flags = SQLITE_ACCESS_EXISTS Then
        Dim fileStatus As UnixStat
        pResult[0] = 0
        If unixStat(zName, @fileStatus) = 0 AndAlso _
           ((fileStatus.stMode And UNIX_STAT_TYPE_MASK) <> UNIX_STAT_REGULAR OrElse _
            fileStatus.stSize > 0) Then pResult[0] = 1
    Else
        Dim mode As SQLITE_C_INT = UNIX_ACCESS_READ Or UNIX_ACCESS_WRITE
        pResult[0] = IIf(unixAccess(zName, mode) = 0, 1, 0)
    End If
    Return SQLITE_OK
End Function

Private Function unixFullPathname(ByVal pVfs As Any Ptr, ByVal zName As Const ZString Ptr, ByVal outputSize As SQLITE_C_INT, ByVal zOutput As ZString Ptr) As SQLITE_C_INT
    Return unixBuildFullPath(zName, outputSize, zOutput)
End Function

Private Function unixShmRegionPerMap CDecl Alias "unixShmRegionPerMap" () As SQLITE_C_INT
    Dim pageSize As SQLITE_C_INT = unixGetpagesize()
    If pageSize <= 0 OrElse (pageSize And (pageSize - 1)) <> 0 Then Return 1
    If pageSize < UNIX_SHM_REGION_SIZE Then Return 1
    Return pageSize \ UNIX_SHM_REGION_SIZE
End Function

Private Function unixShmNodeFind(ByVal pLockInfo As UnixLockInfo Ptr) As UnixShmNode Ptr
    Dim pNode As UnixShmNode Ptr = unixShmList
    While pNode <> 0
        If pNode->pLockInfo = pLockInfo Then Return pNode
        pNode = pNode->pNext
    Wend
    Return 0
End Function

Private Function unixShmSystemLock CDecl Alias "unixShmSystemLock" ( _
    ByVal pUnix As UnixFile Ptr, _
    ByVal pNode As UnixShmNode Ptr, _
    ByVal lockType As SQLITE_C_INT, _
    ByVal offset As SQLITE_C_INT, _
    ByVal lockCount As SQLITE_C_INT _
) As SQLITE_C_INT
    If pUnix = 0 OrElse pNode = 0 OrElse lockCount < 1 OrElse _
       lockCount > SQLITE_SHM_NLOCK Then Return SQLITE_MISUSE
    If Not ((offset = UNIX_SHM_DMS_BYTE AndAlso lockCount = 1) OrElse _
            (offset >= UNIX_SHM_BASE_BYTE AndAlso _
             offset + lockCount <= UNIX_SHM_DMS_BYTE)) Then Return SQLITE_MISUSE
    If lockType <> UNIX_F_UNLCK AndAlso lockType <> UNIX_F_RDLCK AndAlso _
       lockType <> UNIX_F_WRLCK Then Return SQLITE_MISUSE
    If lockType = UNIX_F_RDLCK AndAlso lockCount <> 1 Then Return SQLITE_MISUSE

    If unixSetByteLock(pNode->fd, lockType, offset, lockCount, pUnix) < 0 Then
        Return unixLockBusyResult(pUnix)
    End If
    Return SQLITE_OK
End Function

Private Function unixLockSharedMemory CDecl Alias "unixLockSharedMemory" ( _
    ByVal pUnix As UnixFile Ptr, _
    ByVal pNode As UnixShmNode Ptr _
) As SQLITE_C_INT
    If pUnix = 0 OrElse pNode = 0 Then Return SQLITE_MISUSE
    Dim lockInfo As UnixFlock
    lockInfo.eType = UNIX_F_WRLCK
    lockInfo.eWhence = UNIX_SEEK_SET
    lockInfo.iStart = UNIX_SHM_DMS_BYTE
    lockInfo.iLength = 1
    If unixFcntl(pNode->fd, UNIX_F_GETLK, @lockInfo) <> 0 Then
        pUnix->lastErrno = unixErrno()
        Return SQLITE_IOERR_LOCK
    End If

    If lockInfo.eType = UNIX_F_UNLCK Then
        If pNode->isReadonly <> 0 Then
            pNode->isUnlocked = 1
            Return SQLITE_READONLY_CANTINIT
        End If
        Dim rc As SQLITE_C_INT = unixShmSystemLock( _
            pUnix, pNode, UNIX_F_WRLCK, UNIX_SHM_DMS_BYTE, 1)
        If rc <> SQLITE_OK Then Return rc
        If robust_ftruncate(pNode->fd, 3) <> 0 Then
            pUnix->lastErrno = unixErrno()
            Return SQLITE_IOERR_SHMOPEN
        End If
    ElseIf lockInfo.eType = UNIX_F_WRLCK Then
        Return SQLITE_BUSY
    End If

    Return unixShmSystemLock( _
        pUnix, pNode, UNIX_F_RDLCK, UNIX_SHM_DMS_BYTE, 1)
End Function

Private Function unixOpenSharedMemory CDecl Alias "unixOpenSharedMemory" ( _
    ByVal pUnix As UnixFile Ptr _
) As SQLITE_C_INT
    If pUnix = 0 OrElse pUnix->pLockInfo = 0 Then Return SQLITE_MISUSE
    If pUnix->pShmNode <> 0 Then Return SQLITE_OK

    Dim pNode As UnixShmNode Ptr = unixShmNodeFind(pUnix->pLockInfo)
    Dim rc As SQLITE_C_INT = SQLITE_OK
    If pNode = 0 Then
        Dim databaseStatus As UnixStat
        If unixFstat(pUnix->fd, @databaseStatus) <> 0 Then
            pUnix->lastErrno = unixErrno()
            Return SQLITE_IOERR_FSTAT
        End If
        Dim zShmPath As ZString * UNIX_PATH_MAX
        Dim pathLength As SQLITE_C_INT = 0
        While pathLength < UNIX_PATH_MAX - 5 AndAlso _
              pUnix->zPath(pathLength) <> 0
            zShmPath[pathLength] = pUnix->zPath(pathLength)
            pathLength += 1
        Wend
        If pathLength >= UNIX_PATH_MAX - 5 Then Return SQLITE_CANTOPEN
        zShmPath[pathLength] = Asc("-")
        zShmPath[pathLength + 1] = Asc("s")
        zShmPath[pathLength + 2] = Asc("h")
        zShmPath[pathLength + 3] = Asc("m")
        zShmPath[pathLength + 4] = 0

        Dim fd As SQLITE_C_INT = -1
        Dim isReadonly As SQLITE_C_INT = 0
        If pUnix->readOnlyShm = 0 Then
            fd = robust_open(@zShmPath, _
                UNIX_OPEN_RDWR Or UNIX_OPEN_CREAT Or UNIX_OPEN_CLOEXEC Or UNIX_OPEN_NOFOLLOW, _
                databaseStatus.stMode And UNIX_FILE_MODE_MASK)
        End If
        If fd < 0 Then
            fd = robust_open(@zShmPath, _
                UNIX_OPEN_READONLY Or UNIX_OPEN_CLOEXEC Or UNIX_OPEN_NOFOLLOW, _
                databaseStatus.stMode And UNIX_FILE_MODE_MASK)
            isReadonly = 1
        End If
        If fd < 0 Then
            pUnix->lastErrno = unixErrno()
            Return unixPathLogError( _
                SQLITE_CANTOPEN, StrPtr("open"), @zShmPath)
        End If

        robustFchown(fd, databaseStatus.stUid, databaseStatus.stGid)
        pNode = CPtr(UnixShmNode Ptr, sqlite3MallocZero(SizeOf(UnixShmNode)))
        If pNode = 0 Then
            unixCloseFd(fd)
            Return SQLITE_NOMEM
        End If
        pNode->fd = fd
        pNode->pLockInfo = pUnix->pLockInfo
        pNode->isReadonly = isReadonly
        rc = unixLockSharedMemory(pUnix, pNode)
        If rc <> SQLITE_OK AndAlso rc <> SQLITE_READONLY_CANTINIT Then
            unixCloseFd(fd)
            sqlite3_free(pNode)
            Return rc
        End If
        pNode->pNext = unixShmList
        unixShmList = pNode
    End If

    pNode->nRef += 1
    pUnix->pShmNode = pNode
    For i As Long = 0 To SQLITE_SHM_NLOCK - 1
        pUnix->aShmLock(i) = 0
    Next
    Return rc
End Function

Private Function unixShmLockOne( _
    ByVal pUnix As UnixFile Ptr, _
    ByVal pNode As UnixShmNode Ptr, _
    ByVal lockIndex As SQLITE_C_INT, _
    ByVal lockMode As SQLITE_C_INT, _
    ByVal operation As SQLITE_C_INT _
) As SQLITE_C_INT

    If pUnix = 0 OrElse pNode = 0 OrElse lockIndex < 0 OrElse lockIndex >= SQLITE_SHM_NLOCK Then Return SQLITE_IOERR_SHMLOCK
    If lockMode <> SQLITE_SHM_SHARED AndAlso lockMode <> SQLITE_SHM_EXCLUSIVE Then Return SQLITE_IOERR_SHMLOCK
    If operation = SQLITE_SHM_LOCK Then
        If pUnix->aShmLock(lockIndex) <> 0 Then Return SQLITE_IOERR_SHMLOCK
        If lockMode = SQLITE_SHM_SHARED Then
            If pNode->apExclusive(lockIndex) <> 0 Then Return SQLITE_BUSY
            If pNode->nShared(lockIndex) = 0 Then
                Dim sharedLockResult As SQLITE_C_INT = unixShmSystemLock( _
                    pUnix, pNode, UNIX_F_RDLCK, _
                    UNIX_SHM_BASE_BYTE + lockIndex, 1)
                If sharedLockResult <> SQLITE_OK Then Return sharedLockResult
            End If
            pNode->nShared(lockIndex) += 1
            pUnix->aShmLock(lockIndex) = SQLITE_SHM_SHARED
            Return SQLITE_OK
        End If

        If pNode->apExclusive(lockIndex) <> 0 OrElse pNode->nShared(lockIndex) <> 0 Then Return SQLITE_BUSY
        Dim exclusiveLockResult As SQLITE_C_INT = unixShmSystemLock( _
            pUnix, pNode, UNIX_F_WRLCK, UNIX_SHM_BASE_BYTE + lockIndex, 1)
        If exclusiveLockResult <> SQLITE_OK Then Return exclusiveLockResult
        pNode->apExclusive(lockIndex) = pUnix
        pUnix->aShmLock(lockIndex) = SQLITE_SHM_EXCLUSIVE
        Return SQLITE_OK
    End If

    If operation <> SQLITE_SHM_UNLOCK OrElse pUnix->aShmLock(lockIndex) <> lockMode Then Return SQLITE_IOERR_SHMLOCK
    If lockMode = SQLITE_SHM_SHARED Then
        If pNode->nShared(lockIndex) = 0 Then Return SQLITE_IOERR_SHMLOCK
        pNode->nShared(lockIndex) -= 1
        If pNode->nShared(lockIndex) = 0 Then
            Dim sharedUnlockResult As SQLITE_C_INT = unixShmSystemLock( _
                pUnix, pNode, UNIX_F_UNLCK, UNIX_SHM_BASE_BYTE + lockIndex, 1)
            If sharedUnlockResult <> SQLITE_OK Then Return sharedUnlockResult
        End If
    Else
        If pNode->apExclusive(lockIndex) <> pUnix Then Return SQLITE_IOERR_SHMLOCK
        Dim exclusiveUnlockResult As SQLITE_C_INT = unixShmSystemLock( _
            pUnix, pNode, UNIX_F_UNLCK, UNIX_SHM_BASE_BYTE + lockIndex, 1)
        If exclusiveUnlockResult <> SQLITE_OK Then Return exclusiveUnlockResult
        pNode->apExclusive(lockIndex) = 0
    End If
    pUnix->aShmLock(lockIndex) = 0
    Return SQLITE_OK
End Function

/' Release the shared-memory node after its last connection drops the refcount.
   The caller holds the global Unix bookkeeping mutex. '/
Private Function unixShmPurge CDecl Alias "unixShmPurge" ( _
    ByVal pUnix As UnixFile Ptr _
) As SQLITE_C_INT
    If pUnix = 0 OrElse pUnix->pShmNode = 0 Then Return SQLITE_OK
    Dim pNode As UnixShmNode Ptr = pUnix->pShmNode
    If pNode->nRef <> 0 Then Return SQLITE_OK
#ifdef SQLITE_DEBUG
    If unixMutexHeld() = 0 Then _
        sqlite3DebugAssert(StrPtr("shared-memory purge holds the Unix mutex"))
#endif
    If pNode->pLockInfo <> pUnix->pLockInfo Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("shared-memory node belongs to this inode"))
#endif
        Return SQLITE_IOERR_SHMOPEN
    End If

    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim regionsPerMap As SQLITE_C_INT = unixShmRegionPerMap()
    If regionsPerMap <= 0 Then Return SQLITE_IOERR_SHMMAP
    Dim bytesPerMap As SQLITE_SIZE_T = _
        CULngInt(pNode->szRegion) * CULngInt(regionsPerMap)
    For regionIndex As SQLITE_C_INT = 0 To pNode->nRegion - 1 Step regionsPerMap
        If pNode->apRegion[regionIndex] <> 0 Then
            If pNode->fd >= 0 Then
                If unixMunmap(pNode->apRegion[regionIndex], bytesPerMap) <> 0 Then _
                    rc = SQLITE_IOERR_SHMMAP
            Else
                sqlite3_free(pNode->apRegion[regionIndex])
            End If
        End If
    Next
    If pNode->fd >= 0 Then
        If unixCloseFd(pNode->fd) <> 0 Then rc = SQLITE_IOERR_SHMOPEN
        pNode->fd = -1
    End If

    pUnix->pShmNode = 0
    Dim ppNode As UnixShmNode Ptr Ptr = @unixShmList
    While ppNode[0] <> 0 AndAlso ppNode[0] <> pNode
        ppNode = @ppNode[0]->pNext
    Wend
    If ppNode[0] = pNode Then
        ppNode[0] = pNode->pNext
    Else
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("purged shared-memory node is linked"))
#endif
        If rc = SQLITE_OK Then rc = SQLITE_IOERR_SHMOPEN
    End If
    If pNode->apRegion <> 0 Then sqlite3_free(pNode->apRegion)
    sqlite3_free(pNode)
    Return rc
End Function

Private Function unixShmUnmapLocked(ByVal pUnix As UnixFile Ptr, ByVal deleteFlag As SQLITE_C_INT) As SQLITE_C_INT
    If pUnix = 0 OrElse pUnix->pShmNode = 0 Then Return SQLITE_OK
    Dim pNode As UnixShmNode Ptr = pUnix->pShmNode
    Dim rc As SQLITE_C_INT = SQLITE_OK
    For i As Long = 0 To SQLITE_SHM_NLOCK - 1
        If pUnix->aShmLock(i) <> 0 Then
            Dim lockMode As SQLITE_C_INT = pUnix->aShmLock(i)
            Dim lockRc As SQLITE_C_INT = unixShmLockOne(pUnix, pNode, i, lockMode, SQLITE_SHM_UNLOCK)
            If lockRc <> SQLITE_OK Then rc = lockRc
        End If
    Next
    If deleteFlag <> 0 Then pNode->deletePending = 1
    If pNode->nRef > 0 Then pNode->nRef -= 1
    If pNode->nRef <> 0 Then
        pUnix->pShmNode = 0
        Return rc
    End If
    If pNode->deletePending <> 0 Then
        Dim zShmPath As ZString * UNIX_PATH_MAX
        Dim nPath As Long = 0
        While nPath < UNIX_PATH_MAX - 5 AndAlso pUnix->zPath(nPath) <> 0
            zShmPath[nPath] = pUnix->zPath(nPath)
            nPath += 1
        Wend
        If nPath < UNIX_PATH_MAX - 5 Then
            zShmPath[nPath] = Asc("-")
            zShmPath[nPath + 1] = Asc("s")
            zShmPath[nPath + 2] = Asc("h")
            zShmPath[nPath + 3] = Asc("m")
            zShmPath[nPath + 4] = 0
            If unixUnlink(@zShmPath) <> 0 AndAlso unixErrno() <> UNIX_ENOENT Then rc = SQLITE_IOERR_SHMOPEN
        End If
    End If
    Dim purgeRc As SQLITE_C_INT = unixShmPurge(pUnix)
    If purgeRc <> SQLITE_OK Then rc = purgeRc
    Return rc
End Function

Private Function unixShmMap( _
    ByVal pFile As Any Ptr, _
    ByVal pageNumber As SQLITE_C_INT, _
    ByVal pageSize As SQLITE_C_INT, _
    ByVal extendFlag As SQLITE_C_INT, _
    ByVal ppPage As Any Ptr Ptr _
) As SQLITE_C_INT

    If pFile = 0 OrElse ppPage = 0 OrElse pageNumber < 0 OrElse pageSize <= 0 Then Return SQLITE_MISUSE
    ppPage[0] = 0
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    unixEnterMutex()
    If pUnix->pShmNode = 0 Then
        Dim openSharedMemoryResult As SQLITE_C_INT = unixOpenSharedMemory(pUnix)
        If openSharedMemoryResult <> SQLITE_OK Then
            unixLeaveMutex()
            Return openSharedMemoryResult
        End If
    End If
    Dim pNode As UnixShmNode Ptr = pUnix->pShmNode
    If pNode = 0 Then
        unixLeaveMutex()
        Return SQLITE_IOERR_SHMOPEN
    End If
    If pNode->isUnlocked <> 0 Then
        Dim sharedMemoryLockResult As SQLITE_C_INT = _
            unixLockSharedMemory(pUnix, pNode)
        If sharedMemoryLockResult <> SQLITE_OK Then
            unixLeaveMutex()
            Return sharedMemoryLockResult
        End If
        pNode->isUnlocked = 0
    End If
    If pNode->szRegion = 0 Then
        pNode->szRegion = pageSize
    ElseIf pNode->szRegion <> pageSize Then
        unixLeaveMutex()
        Return SQLITE_IOERR_SHMSIZE
    End If

    Dim regionsPerMap As SQLITE_C_INT = unixShmRegionPerMap()
    If regionsPerMap <= 0 OrElse pageNumber > &H7FFFFFFF - regionsPerMap Then
        unixLeaveMutex()
        Return SQLITE_IOERR_SHMMAP
    End If
    ' Map enough whole SQLite regions to keep each mmap offset page-aligned.
    Dim requiredCount As SQLITE_C_INT = _
        ((pageNumber + regionsPerMap) \ regionsPerMap) * regionsPerMap
    Dim requiredBytes As sqlite3_int64 = _
        CLngInt(requiredCount) * CLngInt(pageSize)

    If pNode->nRegion < requiredCount Then
        pNode->szRegion = pageSize
        If pNode->fd >= 0 Then
            Dim shmStatus As UnixStat
            If unixFstat(pNode->fd, @shmStatus) <> 0 Then
                pUnix->lastErrno = unixErrno()
                unixLeaveMutex()
                Return SQLITE_IOERR_SHMSIZE
            End If

            If shmStatus.stSize < requiredBytes Then
                If extendFlag = 0 Then
                    Dim noExtendCode As SQLITE_C_INT = SQLITE_OK
                    If pNode->isReadonly <> 0 Then noExtendCode = SQLITE_READONLY
                    unixLeaveMutex()
                    Return noExtendCode
                End If

                Dim pageIndex As sqlite3_int64 = _
                    shmStatus.stSize \ UNIX_SHM_FAULT_PAGE_SIZE
                While pageIndex < requiredBytes \ UNIX_SHM_FAULT_PAGE_SIZE
                    Dim writeError As SQLITE_C_INT = 0
                    Dim fileOffset As sqlite3_int64 = _
                        pageIndex * UNIX_SHM_FAULT_PAGE_SIZE + _
                        UNIX_SHM_FAULT_PAGE_SIZE - 1
                    If seekAndWriteFd( _
                        pNode->fd, fileOffset, StrPtr(!""), 1, @writeError) <> 1 Then
                        pUnix->lastErrno = writeError
                        unixLeaveMutex()
                        Return SQLITE_IOERR_SHMSIZE
                    End If
                    pageIndex += 1
                Wend
            End If
        End If

        Dim nByte As sqlite3_uint64 = _
            CULngInt(requiredCount) * SizeOf(Any Ptr)
        If nByte > SQLITE_MAX_ALLOCATION_SIZE Then
            unixLeaveMutex()
            Return SQLITE_NOMEM
        End If
        Dim apNew As Any Ptr Ptr = CPtr(Any Ptr Ptr, sqlite3Realloc(pNode->apRegion, nByte))
        If apNew = 0 Then
            unixLeaveMutex()
            Return SQLITE_NOMEM
        End If
        pNode->apRegion = apNew
        While pNode->nRegion < requiredCount
            Dim mapSize As sqlite3_int64 = _
                CLngInt(pageSize) * CLngInt(regionsPerMap)
            Dim mapOffset As sqlite3_int64 = _
                CLngInt(pNode->szRegion) * CLngInt(pNode->nRegion)
            Dim mapProtection As SQLITE_C_INT = UNIX_PROT_READ
            If pNode->isReadonly = 0 Then mapProtection Or= UNIX_PROT_WRITE
            Dim pRegion As Any Ptr = unixMmap( _
                0, Cast(SQLITE_SIZE_T, mapSize), _
                mapProtection, UNIX_MAP_SHARED, _
                pNode->fd, mapOffset)
            If CULngInt(pRegion) = UNIX_MAP_FAILED OrElse pRegion = 0 Then
                pUnix->lastErrno = unixErrno()
                unixLeaveMutex()
                Return SQLITE_IOERR_SHMMAP
            End If

            Dim pRegionBytes As UByte Ptr = CPtr(UByte Ptr, pRegion)
            For regionOffset As SQLITE_C_INT = 0 To regionsPerMap - 1
                pNode->apRegion[pNode->nRegion + regionOffset] = _
                    pRegionBytes + CULng(pageSize) * CULng(regionOffset)
            Next
            pNode->nRegion += regionsPerMap
        Wend
    End If
    If pNode->nRegion > pageNumber Then _
        ppPage[0] = pNode->apRegion[pageNumber]
    Dim resultCode As SQLITE_C_INT = SQLITE_OK
    If pNode->isReadonly <> 0 Then resultCode = SQLITE_READONLY
    unixLeaveMutex()
    Return resultCode
End Function

Private Function unixShmLock( _
    ByVal pFile As Any Ptr, _
    ByVal offset As SQLITE_C_INT, _
    ByVal count As SQLITE_C_INT, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT

    If pFile = 0 OrElse offset < 0 OrElse count <= 0 OrElse _
       offset > SQLITE_SHM_NLOCK - count Then Return SQLITE_IOERR_SHMLOCK
    Dim operation As SQLITE_C_INT = flags And (SQLITE_SHM_LOCK Or SQLITE_SHM_UNLOCK)
    Dim lockMode As SQLITE_C_INT = flags And (SQLITE_SHM_SHARED Or SQLITE_SHM_EXCLUSIVE)
    If (operation <> SQLITE_SHM_LOCK AndAlso operation <> SQLITE_SHM_UNLOCK) OrElse _
       (lockMode <> SQLITE_SHM_SHARED AndAlso lockMode <> SQLITE_SHM_EXCLUSIVE) Then Return SQLITE_IOERR_SHMLOCK

    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    Dim pNode As UnixShmNode Ptr = pUnix->pShmNode
    If pNode = 0 Then Return SQLITE_IOERR_SHMLOCK
    unixEnterMutex()
    Dim rc As SQLITE_C_INT = SQLITE_OK
    For i As Long = offset To offset + count - 1
        rc = unixShmLockOne(pUnix, pNode, i, lockMode, operation)
        If rc <> SQLITE_OK Then
            If operation = SQLITE_SHM_LOCK Then
                For j As Long = offset To i - 1
                    unixShmLockOne(pUnix, pNode, j, lockMode, SQLITE_SHM_UNLOCK)
                Next
            End If
            Exit For
        End If
    Next
#ifdef SQLITE_DEBUG
    If assertLockingArrayOk(pNode) = 0 Then _
        sqlite3DebugAssert(StrPtr("shared-memory lock owners match lock counts"))
#endif
    unixLeaveMutex()
    Return rc
End Function

Private Sub unixShmBarrier(ByVal pFile As Any Ptr)
    sqlite3MemoryBarrier()
End Sub

Private Function unixShmUnmap(ByVal pFile As Any Ptr, ByVal deleteFlag As SQLITE_C_INT) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
    Dim pUnix As UnixFile Ptr = CPtr(UnixFile Ptr, pFile)
    unixEnterMutex()
    Dim rc As SQLITE_C_INT = unixShmUnmapLocked(pUnix, deleteFlag)
    unixLeaveMutex()
    Return rc
End Function

#ifndef SQLITE_OMIT_LOAD_EXTENSION
Private Function unixDlOpen CDecl Alias "unixDlOpen" ( _
    ByVal pVfs As Any Ptr, _
    ByVal zFilename As Const ZString Ptr _
) As Any Ptr
    If zFilename = 0 Then Return 0
    Return unixSystemDlOpen(zFilename, UNIX_RTLD_NOW Or UNIX_RTLD_GLOBAL)
End Function

Private Sub unixDlError CDecl Alias "unixDlError" ( _
    ByVal pVfs As Any Ptr, _
    ByVal outputSize As SQLITE_C_INT, _
    ByVal zOutput As ZString Ptr _
)
    If outputSize <= 0 OrElse zOutput = 0 Then Exit Sub
    Dim zError As Const ZString Ptr = unixSystemDlError()
    If zError = 0 Then Exit Sub
    Dim i As SQLITE_C_INT = 0
    While i < outputSize - 1 AndAlso zError[i] <> 0
        zOutput[i] = zError[i]
        i += 1
    Wend
    zOutput[i] = 0
End Sub

Private Function unixDlSym CDecl Alias "unixDlSym" ( _
    ByVal pVfs As Any Ptr, _
    ByVal pHandle As Any Ptr, _
    ByVal zSymbol As Const ZString Ptr _
) As Any Ptr
    If pHandle = 0 OrElse zSymbol = 0 Then Return 0
    Return unixSystemDlSym(pHandle, zSymbol)
End Function

Private Sub unixDlClose CDecl Alias "unixDlClose" ( _
    ByVal pVfs As Any Ptr, _
    ByVal pHandle As Any Ptr _
)
    If pHandle <> 0 Then unixSystemDlClose(pHandle)
End Sub
#endif

Private Function unixRandomness(ByVal pVfs As Any Ptr, ByVal amount As SQLITE_C_INT, ByVal zOutput As ZString Ptr) As SQLITE_C_INT
    If amount <= 0 OrElse zOutput = 0 Then Return 0
    Dim pOutput As UByte Ptr = CPtr(UByte Ptr, zOutput)
    Dim nDone As SQLITE_C_INT = 0
    While nDone < amount
        Dim n As sqlite3_int64 = unixGetrandom(pOutput + nDone, CULng(amount - nDone), 0)
        If n < 0 AndAlso unixErrno() = UNIX_EINTR Then Continue While
        If n <= 0 Then Exit While
        nDone += CLng(n)
    Wend
    If nDone = amount Then Return amount

    Dim fd As SQLITE_C_INT = unixOpen(StrPtr("/dev/urandom"), UNIX_OPEN_READONLY Or UNIX_OPEN_CLOEXEC, 0)
    If fd < 0 Then Return nDone
    While nDone < amount
        Dim n As sqlite3_int64 = unixPread(fd, pOutput + nDone, CULng(amount - nDone), nDone)
        If n < 0 AndAlso unixErrno() = UNIX_EINTR Then Continue While
        If n <= 0 Then Exit While
        nDone += CLng(n)
    Wend
    unixCloseFd(fd)
    Return nDone
End Function

Private Function unixSleepVfs(ByVal pVfs As Any Ptr, ByVal microseconds As SQLITE_C_INT) As SQLITE_C_INT
    If microseconds <= 0 Then Return 0
    Dim request As UnixTimespec
    Dim remain As UnixTimespec
    request.tvSec = microseconds \ 1000000
    request.tvNsec = (microseconds Mod 1000000) * 1000
    If unixNanosleep(@request, @remain) = 0 Then Return microseconds
    If unixErrno() <> UNIX_EINTR Then Return 0
    Dim slept As sqlite3_int64 = CLngInt(microseconds) - remain.tvSec * 1000000 - remain.tvNsec \ 1000
    If slept < 0 Then slept = 0
    If slept > microseconds Then slept = microseconds
    Return CLng(slept)
End Function

Private Function unixSleep CDecl Alias "unixSleep" ( _
    ByVal pVfs As Any Ptr, _
    ByVal microseconds As SQLITE_C_INT _
) As SQLITE_C_INT
    If microseconds <= 0 Then Return microseconds
    Dim request As UnixTimespec
    request.tvSec = microseconds \ 1000000
    request.tvNsec = (microseconds Mod 1000000) * 1000
    ' src/os_unix.c returns the request size even if nanosleep is interrupted.
    unixNanosleep(@request, 0)
    Return microseconds
End Function

Private Function unixCurrentTimeInt64(ByVal pVfs As Any Ptr, ByVal pJulianDay As sqlite3_int64 Ptr) As SQLITE_C_INT
    If pJulianDay = 0 Then Return SQLITE_MISUSE
    Dim timeValue As UnixTimeval
    If unixGettimeofday(@timeValue, 0) <> 0 Then Return SQLITE_ERROR
    pJulianDay[0] = 210866760000000 + timeValue.tvSec * 1000 + timeValue.tvUsec \ 1000
    Return SQLITE_OK
End Function

Private Function unixCurrentTime(ByVal pVfs As Any Ptr, ByVal pJulianDay As Double Ptr) As SQLITE_C_INT
    If pJulianDay = 0 Then Return SQLITE_MISUSE
    Dim timeValue As sqlite3_int64 = 0
    Dim rc As SQLITE_C_INT = unixCurrentTimeInt64(pVfs, @timeValue)
    If rc = SQLITE_OK Then pJulianDay[0] = CDbl(timeValue) / 86400000.0
    Return rc
End Function

Private Function unixGetLastError(ByVal pVfs As Any Ptr, ByVal outputSize As SQLITE_C_INT, ByVal zOutput As ZString Ptr) As SQLITE_C_INT
    Return unixErrno()
End Function

Private Function unixSystemCallNameEqual( _
    ByVal firstName As Const ZString Ptr, _
    ByVal secondName As Const ZString Ptr _
) As SQLITE_C_INT
    If firstName = 0 OrElse secondName = 0 Then Return 0
    Dim index As SQLITE_C_INT = 0
    While firstName[index] = secondName[index]
        If firstName[index] = 0 Then Return -1
        index += 1
    Wend
    Return 0
End Function

Private Sub unixInitializeSystemCallTable()
    If unixSystemCallTableReady <> 0 Then Exit Sub

    For i As Long = 0 To UNIX_SYSCALL_COUNT - 1
        unixSystemCallTable(i).zName = 0
        unixSystemCallTable(i).pCurrent = 0
        unixSystemCallTable(i).pDefault = 0
    Next

    unixSystemCallTable(UNIX_SYSCALL_OPEN).zName = StrPtr("open")
    unixSystemCallTable(UNIX_SYSCALL_OPEN).pCurrent = ProcPtr(unixDefaultOpen)
    unixSystemCallTable(UNIX_SYSCALL_CLOSE).zName = StrPtr("close")
    unixSystemCallTable(UNIX_SYSCALL_CLOSE).pCurrent = ProcPtr(unixDefaultClose)
    unixSystemCallTable(UNIX_SYSCALL_ACCESS).zName = StrPtr("access")
    unixSystemCallTable(UNIX_SYSCALL_ACCESS).pCurrent = ProcPtr(unixDefaultAccess)
    unixSystemCallTable(UNIX_SYSCALL_GETCWD).zName = StrPtr("getcwd")
    unixSystemCallTable(UNIX_SYSCALL_GETCWD).pCurrent = ProcPtr(unixDefaultGetcwd)
    unixSystemCallTable(UNIX_SYSCALL_STAT).zName = StrPtr("stat")
    unixSystemCallTable(UNIX_SYSCALL_STAT).pCurrent = ProcPtr(unixDefaultStat)
    unixSystemCallTable(UNIX_SYSCALL_FSTAT).zName = StrPtr("fstat")
    unixSystemCallTable(UNIX_SYSCALL_FSTAT).pCurrent = ProcPtr(unixDefaultFstat)
    unixSystemCallTable(UNIX_SYSCALL_FTRUNCATE).zName = StrPtr("ftruncate")
    unixSystemCallTable(UNIX_SYSCALL_FTRUNCATE).pCurrent = ProcPtr(unixDefaultFtruncate)
    unixSystemCallTable(UNIX_SYSCALL_FCNTL).zName = StrPtr("fcntl")
    unixSystemCallTable(UNIX_SYSCALL_FCNTL).pCurrent = ProcPtr(unixDefaultFcntl)
    unixSystemCallTable(UNIX_SYSCALL_READ).zName = StrPtr("read")
    unixSystemCallTable(UNIX_SYSCALL_READ).pCurrent = ProcPtr(unixDefaultRead)
    unixSystemCallTable(UNIX_SYSCALL_PREAD).zName = StrPtr("pread")
    unixSystemCallTable(UNIX_SYSCALL_PREAD).pCurrent = ProcPtr(unixDefaultPread)
    unixSystemCallTable(UNIX_SYSCALL_PREAD64).zName = StrPtr("pread64")
    unixSystemCallTable(UNIX_SYSCALL_WRITE).zName = StrPtr("write")
    unixSystemCallTable(UNIX_SYSCALL_WRITE).pCurrent = ProcPtr(unixDefaultWrite)
    unixSystemCallTable(UNIX_SYSCALL_PWRITE).zName = StrPtr("pwrite")
    unixSystemCallTable(UNIX_SYSCALL_PWRITE).pCurrent = ProcPtr(unixDefaultPwrite)
    unixSystemCallTable(UNIX_SYSCALL_PWRITE64).zName = StrPtr("pwrite64")
    unixSystemCallTable(UNIX_SYSCALL_FCHMOD).zName = StrPtr("fchmod")
    unixSystemCallTable(UNIX_SYSCALL_FCHMOD).pCurrent = ProcPtr(unixDefaultFchmod)
    unixSystemCallTable(UNIX_SYSCALL_FALLOCATE).zName = StrPtr("fallocate")
    unixSystemCallTable(UNIX_SYSCALL_UNLINK).zName = StrPtr("unlink")
    unixSystemCallTable(UNIX_SYSCALL_UNLINK).pCurrent = ProcPtr(unixDefaultUnlink)
    unixSystemCallTable(UNIX_SYSCALL_OPENDIRECTORY).zName = StrPtr("openDirectory")
    unixSystemCallTable(UNIX_SYSCALL_OPENDIRECTORY).pCurrent = ProcPtr(unixDefaultOpenDirectory)
    unixSystemCallTable(UNIX_SYSCALL_MKDIR).zName = StrPtr("mkdir")
    unixSystemCallTable(UNIX_SYSCALL_MKDIR).pCurrent = ProcPtr(unixDefaultMkdir)
    unixSystemCallTable(UNIX_SYSCALL_RMDIR).zName = StrPtr("rmdir")
    unixSystemCallTable(UNIX_SYSCALL_RMDIR).pCurrent = ProcPtr(unixDefaultRmdir)
    unixSystemCallTable(UNIX_SYSCALL_FCHOWN).zName = StrPtr("fchown")
    unixSystemCallTable(UNIX_SYSCALL_FCHOWN).pCurrent = ProcPtr(unixDefaultFchown)
    unixSystemCallTable(UNIX_SYSCALL_GETEUID).zName = StrPtr("geteuid")
    unixSystemCallTable(UNIX_SYSCALL_GETEUID).pCurrent = ProcPtr(unixDefaultGeteuid)
    unixSystemCallTable(UNIX_SYSCALL_MMAP).zName = StrPtr("mmap")
    unixSystemCallTable(UNIX_SYSCALL_MMAP).pCurrent = ProcPtr(unixDefaultMmap)
    unixSystemCallTable(UNIX_SYSCALL_MUNMAP).zName = StrPtr("munmap")
    unixSystemCallTable(UNIX_SYSCALL_MUNMAP).pCurrent = ProcPtr(unixDefaultMunmap)
    unixSystemCallTable(UNIX_SYSCALL_MREMAP).zName = StrPtr("mremap")
    unixSystemCallTable(UNIX_SYSCALL_GETPAGESIZE).zName = StrPtr("getpagesize")
    unixSystemCallTable(UNIX_SYSCALL_GETPAGESIZE).pCurrent = ProcPtr(unixDefaultGetpagesize)
    unixSystemCallTable(UNIX_SYSCALL_READLINK).zName = StrPtr("readlink")
    unixSystemCallTable(UNIX_SYSCALL_READLINK).pCurrent = ProcPtr(unixDefaultReadlink)
    unixSystemCallTable(UNIX_SYSCALL_LSTAT).zName = StrPtr("lstat")
    unixSystemCallTable(UNIX_SYSCALL_LSTAT).pCurrent = ProcPtr(unixDefaultLstat)
    unixSystemCallTable(UNIX_SYSCALL_IOCTL).zName = StrPtr("ioctl")
#if defined(__FB_LINUX__) AndAlso defined(SQLITE_ENABLE_BATCH_ATOMIC_WRITE)
    unixSystemCallTable(UNIX_SYSCALL_IOCTL).pCurrent = ProcPtr(unixDefaultIoctl)
#endif

    unixSystemCallTableReady = -1
End Sub

Private Function unixSetSystemCall CDecl Alias "unixSetSystemCall" ( _
    ByVal pVfs As Any Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal pNewFunction As Any Ptr _
) As SQLITE_C_INT
    unixInitializeSystemCallTable()
    If zName = 0 Then
        For i As Long = 0 To UNIX_SYSCALL_COUNT - 1
            If unixSystemCallTable(i).pDefault <> 0 Then _
                unixSystemCallTable(i).pCurrent = unixSystemCallTable(i).pDefault
        Next
        Return SQLITE_OK
    End If

    For i As Long = 0 To UNIX_SYSCALL_COUNT - 1
        If unixSystemCallNameEqual(zName, unixSystemCallTable(i).zName) <> 0 Then
            If unixSystemCallTable(i).pDefault = 0 Then _
                unixSystemCallTable(i).pDefault = unixSystemCallTable(i).pCurrent
            If pNewFunction = 0 Then _
                pNewFunction = unixSystemCallTable(i).pDefault
            unixSystemCallTable(i).pCurrent = pNewFunction
            Return SQLITE_OK
        End If
    Next
    Return SQLITE_NOTFOUND
End Function

Private Function unixGetSystemCall CDecl Alias "unixGetSystemCall" ( _
    ByVal pVfs As Any Ptr, _
    ByVal zName As Const ZString Ptr _
) As Any Ptr
    unixInitializeSystemCallTable()
    If zName = 0 Then Return 0
    For i As Long = 0 To UNIX_SYSCALL_COUNT - 1
        If unixSystemCallNameEqual(zName, unixSystemCallTable(i).zName) <> 0 Then _
            Return unixSystemCallTable(i).pCurrent
    Next
    Return 0
End Function

Private Function unixNextSystemCall CDecl Alias "unixNextSystemCall" ( _
    ByVal pVfs As Any Ptr, _
    ByVal zName As Const ZString Ptr _
) As Const ZString Ptr
    unixInitializeSystemCallTable()
    Dim firstIndex As Long = 0
    If zName <> 0 Then
        Dim foundIndex As Long = -1
        For i As Long = 0 To UNIX_SYSCALL_COUNT - 1
            If unixSystemCallNameEqual(zName, unixSystemCallTable(i).zName) <> 0 Then
                foundIndex = i
                Exit For
            End If
        Next
        If foundIndex < 0 Then Return 0
        firstIndex = foundIndex + 1
    End If
    For i As Long = firstIndex To UNIX_SYSCALL_COUNT - 1
        If unixSystemCallTable(i).pCurrent <> 0 Then _
            Return unixSystemCallTable(i).zName
    Next
    Return 0
End Function

Function sqlite3_os_init CDecl Alias "sqlite3_os_init" () As SQLITE_C_INT Export
    If unixVfsInitialized <> 0 Then Return SQLITE_OK
#ifdef SQLITE3_FB_OS_KV_DEFAULT
    Dim kvVfsRc As SQLITE_C_INT = sqlite3KvvfsInit()
    If kvVfsRc = SQLITE_OK Then unixVfsInitialized = 1
    Return kvVfsRc
#else
    unixInitializeSystemCallTable()
    If SizeOf(UnixFlock) <> 32 OrElse SizeOf(UnixStat) <> 144 Then Return SQLITE_ERROR
#if SQLITE3_FB_APPLE_LOCKING_STYLE
    If SizeOf(UnixStatFs) <> 2168 OrElse _
       SizeOf(AfpByteRangeLockPB2) <> 32 Then Return SQLITE_ERROR
#endif
    unixBigLock = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MAIN)
    ' A null static lock is valid when core mutexes are disabled.
    If unixBigLock = 0 AndAlso sqlite3ConfigCoreMutexEnabled() <> 0 Then _
        Return SQLITE_ERROR
#ifdef OS_VXWORKS
    If vxworksFileList <> 0 Then Return SQLITE_ERROR
    vxworksMutex = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_VFS2)
    If vxworksMutex = 0 AndAlso sqlite3ConfigCoreMutexEnabled() <> 0 Then _
        Return SQLITE_ERROR
#endif

    unixIoMethods.iVersion = 3
    unixIoMethods.xClose = @unixCloseFile
    unixIoMethods.xRead = @unixReadFile
    unixIoMethods.xWrite = @unixWriteFile
    unixIoMethods.xTruncate = @unixTruncateFile
    unixIoMethods.xSync = @unixSyncFile
    unixIoMethods.xFileSize = @unixFileSize
    unixIoMethods.xLock = @unixLockFile
    unixIoMethods.xUnlock = @unixUnlockFile
    unixIoMethods.xCheckReservedLock = @unixCheckReservedLock
    unixIoMethods.xFileControl = @unixFileControl
    unixIoMethods.xSectorSize = @unixSectorSize
    unixIoMethods.xDeviceCharacteristics = @unixDeviceCharacteristics
    unixIoMethods.xShmMap = @unixShmMap
    unixIoMethods.xShmLock = @unixShmLock
    unixIoMethods.xShmBarrier = @unixShmBarrier
    unixIoMethods.xShmUnmap = @unixShmUnmap
    unixIoMethods.xFetch = @unixFetch
    unixIoMethods.xUnfetch = @unixUnfetch

    nolockIoMethods = unixIoMethods
    nolockIoMethods.xClose = @nolockClose
    nolockIoMethods.xLock = @nolockLock
    nolockIoMethods.xUnlock = @nolockUnlock
    nolockIoMethods.xCheckReservedLock = @nolockCheckReservedLock
    nolockIoMethods.xShmMap = 0

#ifdef OS_VXWORKS
    semIoMethods = unixIoMethods
    semIoMethods.iVersion = 1
    semIoMethods.xClose = @semXClose
    semIoMethods.xLock = @semXLock
    semIoMethods.xUnlock = @semXUnlock
    semIoMethods.xCheckReservedLock = @semXCheckReservedLock
    semIoMethods.xShmMap = 0
#endif

#ifdef SQLITE_ENABLE_LOCKING_STYLE
    dotlockIoMethods = unixIoMethods
    dotlockIoMethods.iVersion = 1
    dotlockIoMethods.xClose = @dotlockClose
    dotlockIoMethods.xLock = @dotlockLock
    dotlockIoMethods.xUnlock = @dotlockUnlock
    dotlockIoMethods.xCheckReservedLock = @dotlockCheckReservedLock
    dotlockIoMethods.xShmMap = 0
    dotlockIoMethods.xShmLock = 0
    dotlockIoMethods.xShmBarrier = 0
    dotlockIoMethods.xShmUnmap = 0
    dotlockIoMethods.xFetch = 0
    dotlockIoMethods.xUnfetch = 0

    flockIoMethods.iVersion = 1
    flockIoMethods.xClose = @flockClose
    flockIoMethods.xRead = @unixReadFile
    flockIoMethods.xWrite = @unixWriteFile
    flockIoMethods.xTruncate = @unixTruncateFile
    flockIoMethods.xSync = @unixSyncFile
    flockIoMethods.xFileSize = @unixFileSize
    flockIoMethods.xLock = @flockLock
    flockIoMethods.xUnlock = @flockUnlock
    flockIoMethods.xCheckReservedLock = @flockCheckReservedLock
    flockIoMethods.xFileControl = @unixFileControl
    flockIoMethods.xSectorSize = @unixSectorSize
    flockIoMethods.xDeviceCharacteristics = @unixDeviceCharacteristics
    flockIoMethods.xShmMap = 0
    flockIoMethods.xShmLock = @unixShmLock
    flockIoMethods.xShmBarrier = @unixShmBarrier
    flockIoMethods.xShmUnmap = @unixShmUnmap
#endif

#if SQLITE3_FB_APPLE_LOCKING_STYLE
    afpIoMethods = unixIoMethods
    afpIoMethods.iVersion = 1
    afpIoMethods.xClose = @afpClose
    afpIoMethods.xLock = @afpLock
    afpIoMethods.xUnlock = @afpUnlock
    afpIoMethods.xCheckReservedLock = @afpCheckReservedLock
    afpIoMethods.xShmMap = 0
    afpIoMethods.xShmLock = 0
    afpIoMethods.xShmBarrier = 0
    afpIoMethods.xShmUnmap = 0
    afpIoMethods.xFetch = 0
    afpIoMethods.xUnfetch = 0

    ' The NFS profile keeps the ordinary POSIX methods but uses the split
    ' exclusive-to-shared unlock and disables WAL shared-memory callbacks.
    nfsIoMethods = unixIoMethods
    nfsIoMethods.iVersion = 1
    nfsIoMethods.xClose = @unixCloseFile
    nfsIoMethods.xLock = @unixLockFile
    nfsIoMethods.xUnlock = @nfsUnlock
    nfsIoMethods.xCheckReservedLock = @unixCheckReservedLock
    nfsIoMethods.xShmMap = 0
    nfsIoMethods.xShmLock = 0
    nfsIoMethods.xShmBarrier = 0
    nfsIoMethods.xShmUnmap = 0
    nfsIoMethods.xFetch = 0
    nfsIoMethods.xUnfetch = 0

    proxyIoMethods = unixIoMethods
    proxyIoMethods.iVersion = 1
    proxyIoMethods.xClose = @proxyClose
    proxyIoMethods.xLock = @proxyLock
    proxyIoMethods.xUnlock = @proxyUnlock
    proxyIoMethods.xCheckReservedLock = @proxyCheckReservedLock
    proxyIoMethods.xShmMap = 0
#endif

    unixVfs.iVersion = 3
    unixVfs.szOsFile = SizeOf(UnixFile)
    unixVfs.mxPathname = UNIX_PATH_MAX - 1
    unixVfs.pNext = 0
    unixVfs.zName = StrPtr("unix")
    unixVfs.pAppData = 0
    unixVfs.xOpen = @unixOpenFile
    unixVfs.xDelete = @unixDelete
    unixVfs.xAccess = @unixAccessVfs
    unixVfs.xFullPathname = @unixFullPathname
#ifdef SQLITE_OMIT_LOAD_EXTENSION
    unixVfs.xDlOpen = 0
    unixVfs.xDlError = 0
    unixVfs.xDlSym = 0
    unixVfs.xDlClose = 0
#else
    unixVfs.xDlOpen = @unixDlOpen
    unixVfs.xDlError = @unixDlError
    unixVfs.xDlSym = @unixDlSym
    unixVfs.xDlClose = @unixDlClose
#endif
    unixVfs.xRandomness = @unixRandomness
    unixVfs.xSleep = @unixSleepVfs
    unixVfs.xCurrentTime = @unixCurrentTime
    unixVfs.xGetLastError = @unixGetLastError
    unixVfs.xCurrentTimeInt64 = @unixCurrentTimeInt64
    unixVfs.xSetSystemCall = @unixSetSystemCall
    unixVfs.xGetSystemCall = @unixGetSystemCall
    unixVfs.xNextSystemCall = @unixNextSystemCall

    ' The unix-none VFS shares Unix file handling but deliberately omits
    ' filesystem locks, matching SQLite's built-in test and utility VFS.
    unixNoneVfs = unixVfs
    unixNoneVfs.pNext = 0
    unixNoneVfs.zName = StrPtr("unix-none")

#if SQLITE3_FB_APPLE_LOCKING_STYLE
    afpVfs = unixVfs
    afpVfs.pNext = 0
    afpVfs.zName = StrPtr("unix-afp")
    nfsVfs = unixVfs
    nfsVfs.pNext = 0
    nfsVfs.zName = StrPtr("unix-nfs")
#endif

    Dim rc As SQLITE_C_INT = sqlite3_vfs_register(@unixVfs, 1)
    If rc = SQLITE_OK Then rc = sqlite3_vfs_register(@unixNoneVfs, 0)
#ifdef SQLITE_ENABLE_LOCKING_STYLE
    If rc = SQLITE_OK Then
        dotlockVfs = unixVfs
        dotlockVfs.pNext = 0
        dotlockVfs.zName = StrPtr("unix-dotfile")
        rc = sqlite3_vfs_register(@dotlockVfs, 0)
    End If
    If rc = SQLITE_OK Then
        flockVfs = unixVfs
        flockVfs.pNext = 0
        flockVfs.zName = StrPtr("unix-flock")
        rc = sqlite3_vfs_register(@flockVfs, 0)
    End If
#endif
#if SQLITE3_FB_APPLE_LOCKING_STYLE
    If rc = SQLITE_OK Then rc = sqlite3_vfs_register(@nfsVfs, 0)
    If rc = SQLITE_OK Then rc = sqlite3_vfs_register(@afpVfs, 0)
#endif
    If rc = SQLITE_OK Then unixVfsInitialized = 1
#ifdef SQLITE3_FB_OS_KV_OPTIONAL
    If rc = SQLITE_OK Then rc = sqlite3KvvfsInit()
#endif
    Return rc
#endif
End Function

Function sqlite3_os_end CDecl Alias "sqlite3_os_end" () As SQLITE_C_INT Export
#ifdef OS_VXWORKS
    vxworksMutex = 0
#endif
    Return SQLITE_OK
End Function

/' end of sqlite3_os_unix.bas '/
