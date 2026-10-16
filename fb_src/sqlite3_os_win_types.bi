/'
    Project: SQLite FreeBASIC port

    File: sqlite3_os_win_types.bi

    Purpose:

        Define the Win32 VFS records shared by Windows callback bodies.

    Responsibilities:

        - Preserve the leading sqlite3_file method pointer in winFile.
        - Match file, shared-memory, mapping, and timeout record fields.
        - Describe Win32 system-call entries for translated VFS callbacks.
        - Provide Windows SDK records used by file, time, and path APIs.
        - Match the Cygwin stat record used to identify symbolic links.

    This file intentionally does NOT contain:

        - VFS callbacks, API imports, or process-wide Windows state.
        - Syscall table storage, initialization, or callback registration.
'/

#ifndef SQLITE3_OS_WIN_TYPES_BI
#define SQLITE3_OS_WIN_TYPES_BI

#ifdef SQLITE_OS_WIN

#ifdef __FB_CYGWIN__
#define SQLITE3_FB_CYGWIN 1
#endif

#ifdef SQLITE3_FB_CYGWIN
#include once "crt/sys/cygwin/types.bi"
#include once "crt/time.bi"
#include once "crt/errno.bi"

Type SqliteCygwinStat
    st_dev As dev_t
    st_ino As ino_t
    st_mode As mode_t
    st_nlink As nlink_t
    st_uid As uid_t
    st_gid As gid_t
    st_rdev As dev_t
    st_size As off_t
    st_atim As timespec
    st_mtim As timespec
    st_ctim As timespec
    st_blksize As blksize_t
    st_blocks As blkcnt_t
    st_birthtim As timespec
    ' Reserve enough tail space for the complete target stat record.
    reserved(0 To 511) As UByte
End Type
#endif

#ifndef SQLITE_WIN32_USE_UUID
#define SQLITE_WIN32_USE_UUID 0
#endif
#ifndef SQLITE3_FB_WIN_SYSCALL_COUNT
' os_win.c defines 60 ordered names in its xNextSystemCall interface.
#define SQLITE3_FB_WIN_SYSCALL_COUNT 60
#endif

Type FILETIME
    dwLowDateTime As SQLITE_C_UINT
    dwHighDateTime As SQLITE_C_UINT
End Type

Type WinFileTime
    lowDateTime As SQLITE_C_UINT
    highDateTime As SQLITE_C_UINT
End Type

Type LARGE_INTEGER
    QuadPart As sqlite3_int64
End Type

Type OVERLAPPED
    internalValue As SQLITE_SIZE_T
    internalHighValue As SQLITE_SIZE_T
    offset As SQLITE_C_UINT
    offsetHigh As SQLITE_C_UINT
    hEvent As Any Ptr
End Type

Type WIN32_FILE_ATTRIBUTE_DATA
    dwFileAttributes As SQLITE_C_UINT
    ftCreationTime As FILETIME
    ftLastAccessTime As FILETIME
    ftLastWriteTime As FILETIME
    nFileSizeHigh As SQLITE_C_UINT
    nFileSizeLow As SQLITE_C_UINT
End Type

Type SYSTEM_INFO
    dwOemId As SQLITE_C_UINT
    dwPageSize As SQLITE_C_UINT
    lpMinimumApplicationAddress As Any Ptr
    lpMaximumApplicationAddress As Any Ptr
    dwActiveProcessorMask As SQLITE_SIZE_T
    dwNumberOfProcessors As SQLITE_C_UINT
    dwProcessorType As SQLITE_C_UINT
    dwAllocationGranularity As SQLITE_C_UINT
    wProcessorLevel As UShort
    wProcessorRevision As UShort
End Type

#if SQLITE_WIN32_USE_UUID
Type WinUuid
    data1 As SQLITE_C_UINT
    data2 As UShort
    data3 As UShort
    data4(0 To 7) As UByte
End Type
#endif

Type WIN32_FIND_DATAW
    dwFileAttributes As SQLITE_C_UINT
    ftCreationTime As FILETIME
    ftLastAccessTime As FILETIME
    ftLastWriteTime As FILETIME
    nFileSizeHigh As SQLITE_C_UINT
    nFileSizeLow As SQLITE_C_UINT
    dwReserved0 As SQLITE_C_UINT
    dwReserved1 As SQLITE_C_UINT
    cFileName(0 To 259) As UShort
    cAlternateFileName(0 To 13) As UShort
End Type

#ifndef SQLITE_OMIT_WAL
Type winShm As WinShmRecord
Type winShmNode As WinShmNodeRecord

Type ShmRegion
    hMap As Any Ptr
    pMap As Any Ptr
End Type

Type WinShmRecord
    pShmNode As winShmNode Ptr
    sharedMask As UShort
    exclMask As UShort
    hShm As Any Ptr
    bReadonly As SQLITE_C_INT
#if defined(SQLITE_DEBUG) OrElse defined(SQLITE_HAVE_OS_TRACE)
    id As UByte
#endif
    pWinShmNext As winShm Ptr
End Type

Type WinShmNodeRecord
    mutex As Any Ptr
    zFilename As ZString Ptr
    hSharedShm As Any Ptr
    bUseSharedLockHandle As SQLITE_C_INT
    isUnlocked As SQLITE_C_INT
    isReadonly As SQLITE_C_INT
    szRegion As SQLITE_C_INT
    nRegion As SQLITE_C_INT
    aRegion As ShmRegion Ptr
    lastErrno As SQLITE_C_UINT
    pWinShmList As winShm Ptr
    pNext As winShmNode Ptr
#if defined(SQLITE_DEBUG) OrElse defined(SQLITE_HAVE_OS_TRACE)
    nextShmId As UByte
#endif
End Type
#endif

Type winFile
    pMethod As sqlite3_io_methods Ptr
    pVfs As sqlite3_vfs Ptr
    h As Any Ptr
    locktype As UByte
    sharedLockByte As Short
    ctrlFlags As UByte
    lastErrno As SQLITE_C_UINT
#ifndef SQLITE_OMIT_WAL
    pShm As winShm Ptr
#endif
    zPath As Const ZString Ptr
    szChunk As SQLITE_C_INT
#if SQLITE_MAX_MMAP_SIZE > 0
    nFetchOut As SQLITE_C_INT
    hMap As Any Ptr
    pMapRegion As Any Ptr
    mmapSize As sqlite3_int64
    mmapSizeMax As sqlite3_int64
#endif
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    iBusyTimeout As SQLITE_C_UINT
    bBlockOnConnect As SQLITE_C_INT
#endif
End Type

Type winVfsAppData
    pMethod As sqlite3_io_methods Ptr
    pAppData As Any Ptr
    bNoLock As SQLITE_C_INT
End Type

' The syscall table keeps the configured entry point separate from the
' original Windows import so VFS callers can restore the default after an
' override. FreeBASIC stores both pointers opaquely and casts at each call site.
Type WinSystemCallPointer As Any Ptr
Type WinSystemCallEntry
    zName As Const ZString Ptr
    pCurrent As WinSystemCallPointer
    pDefault As WinSystemCallPointer
End Type

#include once "sqlite3_os_win_syscall_types.bi"

#endif

#endif

/' end of sqlite3_os_win_types.bi '/
