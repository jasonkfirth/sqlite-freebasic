/'
    Project: SQLite FreeBASIC port
    -----------------------------

    File: sqlite3_os_win_helpers.bas

    Purpose:

        Port the Windows VFS file lifecycle, shared-memory path, and Win32
        helper operations while retaining SQLite's C ABI.

    Responsibilities:

        - Store the process-wide Windows data and temporary directory paths.
        - Convert UTF-16 path overrides to UTF-8 for SQLite's directory API.
        - Convert UTF-8 and ANSI/OEM strings using SQLite-owned buffers.
        - Format Win32 error messages and pass VFS errors to SQLite's log hook.
        - Send bounded debug text to the Windows debugger.
        - Retry transient Win32 I/O errors and report retry delays.
        - Open, resolve, report errors for, and close Windows shared libraries.
        - Provide the Windows sleep and alertable wait wrappers and VFS callback.
        - Initialize the shared Win32 syscall table and provide its VFS callbacks.
        - Route overrideable Win32 calls through their typed table entries.
        - Read the Win32 system clock in Julian milliseconds.
        - Provide no-lock I/O methods and basic device characteristics.
        - Read and update WinFile mode bits and perform file size/seek/lock calls.
        - Close file handles, transfer file bytes, truncate files, and flush
          mapped views and file buffers.
        - Query file access attributes and resolve native Windows full paths.
        - Map database files for xFetch/xUnfetch and track outstanding fetches.
        - Parse Windows path prefixes and append directory separators.
        - Detect UNC paths and report temporary-directory state.
        - Convert Cygwin paths and resolve their symbolic links when targeted.
        - Open and match shared-memory nodes, initialize the DMS byte, map WAL
          regions, and provide the shared-memory lock and cleanup callbacks.
        - Populate Windows file-I/O and no-lock method tables and register the
          standard, long-path, and no-lock VFS variants.

    This file intentionally does NOT contain:

        - Optional Windows heap allocator callbacks; the memory module owns them.
        - Unix VFS callbacks and non-Windows syscall slots.
'/

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_mutex.bi"
#include once "sqlite3_process_globals.bi"
#include once "sqlite3_vfs.bi"
#include once "sqlite3_global_data.bi"
#include once "sqlite3_fault.bi"
#include once "sqlite3_os_test.bi"

Declare Function sqlite3_initialize CDecl Alias "sqlite3_initialize" () As SQLITE_C_INT
Declare Function sqlite3_mprintf CDecl Alias "sqlite3_mprintf" ( _
    ByVal zFormat As Const ZString Ptr, ... _
) As ZString Ptr
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Declare Function winMemcpy CDecl Alias "memcpy" ( _
    ByVal pDestination As Any Ptr, _
    ByVal pSource As Const Any Ptr, _
    ByVal byteCount As SQLITE_SIZE_T _
) As Any Ptr
Declare Function winMemmove CDecl Alias "memmove" ( _
    ByVal pDestination As Any Ptr, _
    ByVal pSource As Const Any Ptr, _
    ByVal byteCount As SQLITE_SIZE_T _
) As Any Ptr
Declare Function winMemset CDecl Alias "memset" ( _
    ByVal pDestination As Any Ptr, _
    ByVal value As SQLITE_C_INT, _
    ByVal byteCount As SQLITE_SIZE_T _
) As Any Ptr
Declare Function sqlite3MallocZero CDecl Alias "sqlite3MallocZero" ( _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Function sqlite3_realloc64 CDecl Alias "sqlite3_realloc64" ( _
    ByVal pPrior As Any Ptr, _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal z As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3CantopenError CDecl Alias "sqlite3CantopenError" ( _
    ByVal lineNumber As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3StrICmp CDecl Alias "sqlite3StrICmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3_randomness CDecl Alias "sqlite3_randomness" ( _
    ByVal amount As SQLITE_C_INT, _
    ByVal pOutput As Any Ptr _
)
Declare Function sqlite3_uri_boolean CDecl Alias "sqlite3_uri_boolean" ( _
    ByVal zFilename As Const ZString Ptr, _
    ByVal zParameter As Const ZString Ptr, _
    ByVal defaultValue As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3ConfigCoreMutexEnabled CDecl _
    Alias "sqlite3ConfigCoreMutexEnabled" () As SQLITE_C_INT
Declare Function sqlite3ConfigMmapSizeMaximum CDecl _
    Alias "sqlite3ConfigMmapSizeMaximum" () As sqlite3_int64
Declare Function sqlite3ConfigMmapSizeDefault CDecl _
    Alias "sqlite3ConfigMmapSizeDefault" () As sqlite3_int64
Declare Sub sqlite3_str_appendf CDecl Alias "sqlite3_str_appendf" ( _
    ByVal pAccumulator As Any Ptr, _
    ByVal zFormat As Const ZString Ptr, ... _
)
Declare Sub sqlite3_str_append CDecl Alias "sqlite3_str_append" ( _
    ByVal pAccumulator As Any Ptr, _
    ByVal zText As Const ZString Ptr, _
    ByVal byteCount As SQLITE_C_INT _
)
Declare Sub sqlite3_str_appendall CDecl Alias "sqlite3_str_appendall" ( _
    ByVal pAccumulator As Any Ptr, _
    ByVal zText As Const ZString Ptr _
)
#ifdef SQLITE_ENABLE_8_3_NAMES
Declare Sub sqlite3FileSuffix3 CDecl Alias "sqlite3FileSuffix3" ( _
    ByVal zBaseFilename As Const ZString Ptr, _
    ByVal zFilename As ZString Ptr _
)
#endif
Declare Function sqlite3_snprintf CDecl Alias "sqlite3_snprintf" ( _
    ByVal nByte As SQLITE_C_INT, _
    ByVal zBuffer As ZString Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) As ZString Ptr
Declare Sub sqlite3_log CDecl Alias "sqlite3_log" ( _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
#ifdef SQLITE_DEBUG
Declare Function sqlite3NomemError CDecl Alias "sqlite3NomemError" ( _
    ByVal lineNumber As SQLITE_C_INT _
) As SQLITE_C_INT
#ifdef SQLITE_ENABLE_API_ARMOR
Declare Function sqlite3MisuseError CDecl Alias "sqlite3MisuseError" ( _
    ByVal lineNumber As SQLITE_C_INT _
) As SQLITE_C_INT
#endif

Declare Sub sqlite3DebugAssert CDecl Alias "sqlite3DebugAssert" ( _
    ByVal zExpression As Const ZString Ptr _
)
#endif

#ifndef SQLITE_WIN32_IOERR_RETRY
#define SQLITE_WIN32_IOERR_RETRY 10
#endif
#ifndef SQLITE_WIN32_IOERR_RETRY_DELAY
#define SQLITE_WIN32_IOERR_RETRY_DELAY 25
#endif

' These are the transient sharing and network failures listed by WinError.h.
Private Const WIN_ERROR_ACCESS_DENIED As SQLITE_C_UINT = 5
Private Const WIN_ERROR_SHARING_VIOLATION As SQLITE_C_UINT = 32
Private Const WIN_ERROR_LOCK_VIOLATION As SQLITE_C_UINT = 33
Private Const WIN_ERROR_DEV_NOT_EXIST As SQLITE_C_UINT = 55
Private Const WIN_ERROR_NETNAME_DELETED As SQLITE_C_UINT = 64
Private Const WIN_ERROR_SEM_TIMEOUT As SQLITE_C_UINT = 121
Private Const WIN_ERROR_NETWORK_UNREACHABLE As SQLITE_C_UINT = 1231
Private Dim Shared winIoerrRetry As SQLITE_C_INT = SQLITE_WIN32_IOERR_RETRY
Private Dim Shared winIoerrRetryDelay As SQLITE_C_INT = _
    SQLITE_WIN32_IOERR_RETRY_DELAY

#ifdef SQLITE_OS_WIN

#include once "sqlite3_os_win_types.bi"
#if defined(SQLITE3_FB_CYGWIN)
Declare Function winIsDir CDecl ( _
    ByVal zFilename As Const UShort Ptr _
) As SQLITE_C_INT
#endif

#ifdef SQLITE3_FB_CYGWIN
Declare Function winDefaultCygwinGetenv CDecl Alias "getenv" ( _
    ByVal zName As Const ZString Ptr _
) As Const ZString Ptr
Declare Function winDefaultCygwinGetcwd CDecl Alias "getcwd" ( _
    ByVal zBuffer As ZString Ptr, _
    ByVal bufferBytes As SQLITE_SIZE_T _
) As ZString Ptr
Declare Function winDefaultCygwinReadlink CDecl Alias "readlink" ( _
    ByVal zPath As Const ZString Ptr, _
    ByVal zBuffer As ZString Ptr, _
    ByVal bufferBytes As SQLITE_SIZE_T _
) As Integer
Declare Function winDefaultCygwinLstat CDecl Alias "lstat" ( _
    ByVal zPath As Const ZString Ptr, _
    ByVal pStat As SqliteCygwinStat Ptr _
) As SQLITE_C_INT
Declare Function winDefaultCygwinErrno CDecl Alias "__errno" () _
    As SQLITE_C_INT Ptr
Declare Function winDefaultCygwinConvPath CDecl Alias "cygwin_conv_path" ( _
    ByVal conversionFlags As SQLITE_C_UINT, _
    ByVal pSource As Const Any Ptr, _
    ByVal pDestination As Any Ptr, _
    ByVal destinationBytes As SQLITE_SIZE_T _
) As Integer
#endif

#ifndef SQLITE_OMIT_WAL
Private Dim Shared winShmNodeList As winShmNode Ptr
#endif
Private Dim Shared winIoMethods As sqlite3_io_methods
Private Dim Shared winIoNolockMethods As sqlite3_io_methods
Private Dim Shared winAppData As winVfsAppData
Private Dim Shared winNolockAppData As winVfsAppData
Private Dim Shared winVfs As sqlite3_vfs
Private Dim Shared winLongPathVfs As sqlite3_vfs
Private Dim Shared winNolockVfs As sqlite3_vfs
Private Dim Shared winLongPathNolockVfs As sqlite3_vfs
Private Dim Shared winVfsInitialized As SQLITE_C_INT
' One process-wide table serves all four Windows VFS variants. The separate
' name array provides stable storage for xNextSystemCall return pointers.
Dim Shared winSystemCallTable(0 To SQLITE3_FB_WIN_SYSCALL_COUNT - 1) _
    As WinSystemCallEntry
Private Dim Shared winSystemCallNames( _
    0 To SQLITE3_FB_WIN_SYSCALL_COUNT - 1) As ZString * 32
Private Dim Shared winSystemCallTableReady As SQLITE_C_INT

Private Type WinEntropyGatherer
    bytes As UByte Ptr
    bufferLength As SQLITE_C_INT
    index As SQLITE_C_INT
    byteCount As SQLITE_C_INT
End Type

#ifndef __C2FB_BODY_C_ABI_TYPES__
#define __C2FB_BODY_C_ABI_TYPES__
Type c2fb_c_int As SQLITE_C_INT
Type c2fb_c_uint As SQLITE_C_UINT
Type c2fb_c_long As SQLITE_C_LONG
Type c2fb_c_ulong As SQLITE_C_ULONG
Type c2fb_int64 As sqlite3_int64
Type c2fb_uint64 As sqlite3_uint64
Type c2fb_size_t As SQLITE_SIZE_T
#endif

#define SQLITE_MUTEX_STATIC_TEMPDIR SQLITE_MUTEX_STATIC_VFS1
#ifndef SQLITE_TEMP_FILE_PREFIX
#define SQLITE_TEMP_FILE_PREFIX "etilqs_"
#endif
' sqlite3CtypeMap marks alphabetic bytes with bit 0x02.
Private Const SQLITE_CTYPE_ALPHA_MASK As UByte = &H02
Private Const WIN_PATH_SEPARATOR As UByte = 92
Private Const WINFILE_RDONLY As UByte = &H02
Private Const WINFILE_PERSIST_WAL As UByte = &H04
Private Const WINFILE_PSOW As UByte = &H10
Private Const WIN_FILE_BEGIN As SQLITE_C_UINT = 0
Private Const WIN_INVALID_FILE_ATTRIBUTES As SQLITE_C_UINT = &HFFFFFFFF
Private Const WIN_FILE_ATTRIBUTE_DIRECTORY As SQLITE_C_UINT = &H10
Private Const WIN_FILE_ATTRIBUTE_READONLY As SQLITE_C_UINT = &H1
Private Const WIN_ERROR_FILE_NOT_FOUND As SQLITE_C_UINT = 2
Private Const WIN_ERROR_PATH_NOT_FOUND As SQLITE_C_UINT = 3
Private Const WIN_ERROR_INVALID_HANDLE As SQLITE_C_UINT = 6
Private Const WIN_ERROR_NOT_LOCKED As SQLITE_C_UINT = 158
Private Const WIN_ERROR_HANDLE_EOF As SQLITE_C_UINT = 38
Private Const WIN_ERROR_HANDLE_DISK_FULL As SQLITE_C_UINT = 39
Private Const WIN_ERROR_DISK_FULL As SQLITE_C_UINT = 112
Private Const WIN_ERROR_USER_MAPPED_FILE As SQLITE_C_UINT = 1224
Private Const WIN_GET_FILEEX_INFO_STANDARD As SQLITE_C_INT = 0
Private Const WIN_ACCESS_NORETRY As SQLITE_C_UINT = &H4000
' Win32 file access, sharing, and mapping values used by the VFS callbacks.
Private Const WIN_GENERIC_READ As SQLITE_C_UINT = &H80000000
Private Const WIN_GENERIC_WRITE As SQLITE_C_UINT = &H40000000
Private Const WIN_FILE_SHARE_READ As SQLITE_C_UINT = &H1
Private Const WIN_FILE_SHARE_WRITE As SQLITE_C_UINT = &H2
Private Const WIN_OPEN_ALWAYS As SQLITE_C_UINT = 4
Private Const WIN_CREATE_NEW As SQLITE_C_UINT = 1
Private Const WIN_OPEN_EXISTING As SQLITE_C_UINT = 3
Private Const WIN_FILE_ATTRIBUTE_NORMAL As SQLITE_C_UINT = &H80
Private Const WIN_FILE_ATTRIBUTE_TEMPORARY As SQLITE_C_UINT = &H100
Private Const WIN_FILE_ATTRIBUTE_HIDDEN As SQLITE_C_UINT = &H2
Private Const WIN_FILE_FLAG_OVERLAPPED As SQLITE_C_UINT = &H40000000
Private Const WIN_FILE_FLAG_DELETE_ON_CLOSE As SQLITE_C_UINT = &H04000000
Private Const WIN_ERROR_IO_PENDING As SQLITE_C_UINT = 997
Private Const WIN_FILE_WAIT_INFINITE As SQLITE_C_UINT = &HFFFFFFFF
Private Const WIN_LOCKFILE_FAIL_IMMEDIATELY As SQLITE_C_UINT = 1
Private Const WIN_LOCKFILE_EXCLUSIVE As SQLITE_C_UINT = 2
' SQLite reserves byte 0x40000000 for pending, then one byte for reserved,
' followed by the 510-byte shared-reader range.
#ifndef SQLITE_OMIT_WSD
' sqlite3_test_control(SQLITE_TESTCTRL_PENDING_BYTE) changes this shared lock
' offset, so the VFS must read the process-wide value on each lock operation.
Extern sqlite3PendingByte Alias "sqlite3PendingByte" As SQLITE_C_INT
#define WIN_PENDING_BYTE sqlite3PendingByte
#else
#define WIN_PENDING_BYTE &H40000000
#endif
#define WIN_RESERVED_BYTE (WIN_PENDING_BYTE + 1)
#define WIN_SHARED_FIRST (WIN_PENDING_BYTE + 2)
#define WIN_SHARED_SIZE 510
' LockFileEx flags preserve SQLite's immediate exclusive/reader probes, while
' retaining the source build's supported flag overrides.
#ifndef SQLITE_LOCKFILE_FLAGS
#define SQLITE_LOCKFILE_FLAGS (WIN_LOCKFILE_FAIL_IMMEDIATELY Or WIN_LOCKFILE_EXCLUSIVE)
#endif
#ifndef SQLITE_LOCKFILEEX_FLAGS
#define SQLITE_LOCKFILEEX_FLAGS WIN_LOCKFILE_FAIL_IMMEDIATELY
#endif
Private Const WIN_DRIVE_REMOTE As SQLITE_C_UINT = 4
Private Const WIN_SHM_PAGE_READONLY As SQLITE_C_UINT = 2
Private Const WIN_SHM_PAGE_READWRITE As SQLITE_C_UINT = 4
Private Const WIN_SHM_FILE_MAP_READ As SQLITE_C_UINT = 4
Private Const WIN_SHM_FILE_MAP_WRITE As SQLITE_C_UINT = 2
' SQLite reserves 32 lock bytes before the deadman-switch byte in *-shm.
Private Const WIN_SHM_BASE As SQLITE_C_UINT = (22 + SQLITE_SHM_NLOCK) * 4
Private Const WIN_SHM_DMS As SQLITE_C_UINT = WIN_SHM_BASE + SQLITE_SHM_NLOCK
' The shared-memory file is initialized by clearing exactly its first 8 bytes.
Private Const WIN_SHM_INITIAL_BYTES As SQLITE_C_INT = 8
' Maximum positive file offset accepted by SQLite's signed 64-bit API.
Private Const WIN_SQLITE_INT64_MAX As sqlite3_int64 = 9223372036854775807LL
#ifndef SQLITE_POWERSAFE_OVERWRITE
#define SQLITE_POWERSAFE_OVERWRITE 1
#endif
#ifndef SQLITE_WIN32_MAX_PATH_CHARS
#define SQLITE_WIN32_MAX_PATH_CHARS 260
#endif
#ifndef SQLITE_WIN32_MAX_PATH_BYTES
#define SQLITE_WIN32_MAX_PATH_BYTES (SQLITE_WIN32_MAX_PATH_CHARS * 4)
#endif
#ifndef SQLITE_WINNT_MAX_PATH_CHARS
#define SQLITE_WINNT_MAX_PATH_CHARS 32767
#endif
#ifndef SQLITE_WINNT_MAX_PATH_BYTES
#define SQLITE_WINNT_MAX_PATH_BYTES (SQLITE_WINNT_MAX_PATH_CHARS * 2)
#endif
' Windows code page 65001 is the standard UTF-8 encoding.
Private Const WIN_CP_UTF8 As SQLITE_C_UINT = 65001
' The Windows API uses zero for the active ANSI code page and one for OEM.
Private Const WIN_CP_ACP As SQLITE_C_UINT = 0
Private Const WIN_CP_OEMCP As SQLITE_C_UINT = 1

Declare Function winDefaultWinWideCharToMultiByte StdCall Lib "kernel32" _
    Alias "WideCharToMultiByte" ( _
    ByVal codePage As SQLITE_C_UINT, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal zWideText As Const UShort Ptr, _
    ByVal nWideChar As SQLITE_C_INT, _
    ByVal zText As ZString Ptr, _
    ByVal nTextByte As SQLITE_C_INT, _
    ByVal zDefaultChar As Const ZString Ptr, _
    ByVal pUsedDefaultChar As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Declare Function winDefaultWinMultiByteToWideChar StdCall Lib "kernel32" _
    Alias "MultiByteToWideChar" ( _
    ByVal codePage As SQLITE_C_UINT, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal zText As Const ZString Ptr, _
    ByVal nTextByte As SQLITE_C_INT, _
    ByVal zWideText As UShort Ptr, _
    ByVal nWideChar As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function winDefaultWinAreFileApisANSI StdCall Lib "kernel32" _
    Alias "AreFileApisANSI" () As SQLITE_C_INT
Declare Sub winDefaultWinSleepMilliseconds StdCall Lib "kernel32" _
    Alias "Sleep" (ByVal milliseconds As SQLITE_C_UINT)
Declare Function winDefaultWinMemoryBarrierCompareExchange StdCall Lib "kernel32" _
    Alias "InterlockedCompareExchange" ( _
    ByVal pTarget As SQLITE_C_INT Ptr, _
    ByVal exchangeValue As SQLITE_C_INT, _
    ByVal comparand As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function winDefaultWinFormatMessageW StdCall Lib "kernel32" _
    Alias "FormatMessageW" ( _
    ByVal flags As SQLITE_C_UINT, _
    ByVal pSource As Any Ptr, _
    ByVal messageId As SQLITE_C_UINT, _
    ByVal languageId As SQLITE_C_UINT, _
    ByVal pBuffer As UShort Ptr Ptr, _
    ByVal bufferSize As SQLITE_C_UINT, _
    ByVal pArguments As Any Ptr _
) As SQLITE_C_UINT
Declare Function winDefaultWinLocalFree StdCall Lib "kernel32" _
    Alias "LocalFree" (ByVal pMemory As Any Ptr) As Any Ptr
Declare Function winDefaultWinGetLastErrorCode StdCall Lib "kernel32" _
    Alias "GetLastError" () As SQLITE_C_UINT
Declare Function winDefaultWinLoadLibraryW StdCall Lib "kernel32" _
    Alias "LoadLibraryW" (ByVal zFilename As Const UShort Ptr) As Any Ptr
Declare Function winDefaultWinGetProcAddress StdCall Lib "kernel32" _
    Alias "GetProcAddress" ( _
    ByVal hModule As Any Ptr, _
    ByVal zSymbol As Const ZString Ptr _
) As Any Ptr
Declare Function winDefaultWinFreeLibrary StdCall Lib "kernel32" _
    Alias "FreeLibrary" (ByVal hModule As Any Ptr) As SQLITE_C_INT
Declare Function winDefaultWinGetFileAttributesW StdCall Lib "kernel32" _
    Alias "GetFileAttributesW" (ByVal zFilename As Const UShort Ptr) _
    As SQLITE_C_UINT
Declare Function winDefaultWinGetFileAttributesExW StdCall Lib "kernel32" _
    Alias "GetFileAttributesExW" ( _
    ByVal zFilename As Const UShort Ptr, _
    ByVal infoLevel As SQLITE_C_INT, _
    ByVal pFileInformation As WIN32_FILE_ATTRIBUTE_DATA Ptr _
) As SQLITE_C_INT
Declare Function winDefaultWinGetFullPathNameW StdCall Lib "kernel32" _
    Alias "GetFullPathNameW" ( _
    ByVal zFilename As Const UShort Ptr, _
    ByVal bufferLength As SQLITE_C_UINT, _
    ByVal zBuffer As UShort Ptr, _
    ByVal pFilePart As UShort Ptr Ptr _
) As SQLITE_C_UINT
Declare Function winDefaultWinGetTempPathW StdCall Lib "kernel32" _
    Alias "GetTempPathW" ( _
    ByVal bufferLength As SQLITE_C_UINT, _
    ByVal zBuffer As UShort Ptr _
) As SQLITE_C_UINT
Declare Function winDefaultWinGetCurrentProcessId StdCall Lib "kernel32" _
    Alias "GetCurrentProcessId" () As SQLITE_C_UINT
Declare Function winDefaultWinGetTickCount64 StdCall Lib "kernel32" _
    Alias "GetTickCount64" () As sqlite3_uint64
Declare Function winDefaultWinQueryPerformanceCounter StdCall Lib "kernel32" _
    Alias "QueryPerformanceCounter" ( _
    ByVal pCounter As LARGE_INTEGER Ptr _
) As SQLITE_C_INT
#if SQLITE_WIN32_USE_UUID
#ifdef SQLITE_UWP
#error "SQLITE_WIN32_USE_UUID is incompatible with SQLITE_UWP"
#endif
Declare Function winDefaultWinUuidCreate StdCall Lib "rpcrt4" Alias "UuidCreate" ( _
    ByVal pUuid As WinUuid Ptr _
) As SQLITE_C_INT
Declare Function winDefaultWinUuidCreateSequential StdCall Lib "rpcrt4" _
    Alias "UuidCreateSequential" (ByVal pUuid As WinUuid Ptr) As SQLITE_C_INT
#endif
Declare Function winDefaultWinGetDriveTypeW StdCall Lib "kernel32" _
    Alias "GetDriveTypeW" (ByVal zRootPath As Const UShort Ptr) _
    As SQLITE_C_UINT
Declare Function winDefaultWinCreateFileW StdCall Lib "kernel32" _
    Alias "CreateFileW" ( _
    ByVal zFilename As Const UShort Ptr, _
    ByVal desiredAccess As SQLITE_C_UINT, _
    ByVal shareMode As SQLITE_C_UINT, _
    ByVal pSecurityAttributes As Any Ptr, _
    ByVal creationDisposition As SQLITE_C_UINT, _
    ByVal flagsAndAttributes As SQLITE_C_UINT, _
    ByVal hTemplateFile As Any Ptr _
) As Any Ptr
Declare Function winDefaultWinReadFile StdCall Lib "kernel32" _
    Alias "ReadFile" ( _
    ByVal hFile As Any Ptr, _
    ByVal pBuffer As Any Ptr, _
    ByVal bytesToRead As SQLITE_C_UINT, _
    ByVal pBytesRead As SQLITE_C_UINT Ptr, _
    ByVal pOverlapped As OVERLAPPED Ptr _
) As SQLITE_C_INT
Declare Function winDefaultWinFlushFileBuffers StdCall Lib "kernel32" _
    Alias "FlushFileBuffers" (ByVal hFile As Any Ptr) As SQLITE_C_INT
Declare Function winDefaultWinDeleteFileW StdCall Lib "kernel32" _
    Alias "DeleteFileW" (ByVal zFilename As Const UShort Ptr) As SQLITE_C_INT
Declare Function winDefaultWinLockFileEx StdCall Lib "kernel32" _
    Alias "LockFileEx" ( _
    ByVal hFile As Any Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal reserved As SQLITE_C_UINT, _
    ByVal bytesLow As SQLITE_C_UINT, _
    ByVal bytesHigh As SQLITE_C_UINT, _
    ByVal pOverlapped As OVERLAPPED Ptr _
) As SQLITE_C_INT
Declare Function winDefaultWinUnlockFileEx StdCall Lib "kernel32" _
    Alias "UnlockFileEx" ( _
    ByVal hFile As Any Ptr, _
    ByVal reserved As SQLITE_C_UINT, _
    ByVal bytesLow As SQLITE_C_UINT, _
    ByVal bytesHigh As SQLITE_C_UINT, _
    ByVal pOverlapped As OVERLAPPED Ptr _
) As SQLITE_C_INT
Declare Function winDefaultWinSetFilePointerEx StdCall Lib "kernel32" _
    Alias "SetFilePointerEx" ( _
    ByVal hFile As Any Ptr, _
    ByVal distance As LARGE_INTEGER, _
    ByVal pNewPosition As LARGE_INTEGER Ptr, _
    ByVal moveMethod As SQLITE_C_UINT _
) As SQLITE_C_INT
Declare Function winDefaultWinSetEndOfFile StdCall Lib "kernel32" _
    Alias "SetEndOfFile" (ByVal hFile As Any Ptr) As SQLITE_C_INT
Declare Function winDefaultWinGetFileSizeEx StdCall Lib "kernel32" _
    Alias "GetFileSizeEx" ( _
    ByVal hFile As Any Ptr, _
    ByVal pSize As LARGE_INTEGER Ptr _
) As SQLITE_C_INT
Declare Function winDefaultWinWriteFile StdCall Lib "kernel32" _
    Alias "WriteFile" ( _
    ByVal hFile As Any Ptr, _
    ByVal pBuffer As Const Any Ptr, _
    ByVal bytesToWrite As SQLITE_C_UINT, _
    ByVal pBytesWritten As SQLITE_C_UINT Ptr, _
    ByVal pOverlapped As OVERLAPPED Ptr _
) As SQLITE_C_INT
Declare Function winGetOverlappedResult StdCall Lib "kernel32" _
    Alias "GetOverlappedResult" ( _
    ByVal hFile As Any Ptr, _
    ByVal pOverlapped As OVERLAPPED Ptr, _
    ByVal pBytesTransferred As SQLITE_C_UINT Ptr, _
    ByVal waitForCompletion As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function winDefaultWinCloseHandle StdCall Lib "kernel32" _
    Alias "CloseHandle" (ByVal hObject As Any Ptr) As SQLITE_C_INT
Declare Sub winDefaultWinGetSystemInfo StdCall Lib "kernel32" _
    Alias "GetSystemInfo" (ByVal pSystemInfo As SYSTEM_INFO Ptr)
Declare Function winDefaultWinCreateFileMappingW StdCall Lib "kernel32" _
    Alias "CreateFileMappingW" ( _
    ByVal hFile As Any Ptr, _
    ByVal pSecurityAttributes As Any Ptr, _
    ByVal protect As SQLITE_C_UINT, _
    ByVal maximumSizeHigh As SQLITE_C_UINT, _
    ByVal maximumSizeLow As SQLITE_C_UINT, _
    ByVal zName As Const UShort Ptr _
) As Any Ptr
Declare Function winDefaultWinCreateFileMappingFromApp StdCall Lib "kernel32" _
    Alias "CreateFileMappingFromApp" ( _
    ByVal hFile As Any Ptr, _
    ByVal pSecurityAttributes As Any Ptr, _
    ByVal protect As SQLITE_C_UINT, _
    ByVal maximumSize As sqlite3_uint64, _
    ByVal zName As Const UShort Ptr _
) As Any Ptr
Declare Function winDefaultWinMapViewOfFile StdCall Lib "kernel32" _
    Alias "MapViewOfFile" ( _
    ByVal hMap As Any Ptr, _
    ByVal desiredAccess As SQLITE_C_UINT, _
    ByVal offsetHigh As SQLITE_C_UINT, _
    ByVal offsetLow As SQLITE_C_UINT, _
    ByVal bytesToMap As SQLITE_SIZE_T _
) As Any Ptr
Declare Function winDefaultWinMapViewOfFileFromApp StdCall Lib "kernel32" _
    Alias "MapViewOfFileFromApp" ( _
    ByVal hMap As Any Ptr, _
    ByVal desiredAccess As SQLITE_C_UINT, _
    ByVal offset As sqlite3_uint64, _
    ByVal bytesToMap As SQLITE_SIZE_T _
) As Any Ptr
Declare Function winDefaultWinUnmapViewOfFile StdCall Lib "kernel32" _
    Alias "UnmapViewOfFile" (ByVal pBaseAddress As Any Ptr) As SQLITE_C_INT
Declare Function winDefaultWinFlushViewOfFile StdCall Lib "kernel32" _
    Alias "FlushViewOfFile" ( _
    ByVal pBaseAddress As Const Any Ptr, _
    ByVal bytesToFlush As SQLITE_SIZE_T _
) As SQLITE_C_INT
Declare Function winDefaultWinCreateEventW StdCall Lib "kernel32" _
    Alias "CreateEventW" ( _
    ByVal pSecurityAttributes As Any Ptr, _
    ByVal manualReset As SQLITE_C_INT, _
    ByVal initialState As SQLITE_C_INT, _
    ByVal zName As Const UShort Ptr _
) As Any Ptr
Declare Function winDefaultWinWaitForSingleObject StdCall Lib "kernel32" _
    Alias "WaitForSingleObject" ( _
    ByVal hObject As Any Ptr, _
    ByVal milliseconds As SQLITE_C_UINT _
) As SQLITE_C_UINT
Declare Function winDefaultWinWaitForSingleObjectEx StdCall Lib "kernel32" _
    Alias "WaitForSingleObjectEx" ( _
    ByVal hObject As Any Ptr, _
    ByVal milliseconds As SQLITE_C_UINT, _
    ByVal alertable As SQLITE_C_INT _
) As SQLITE_C_UINT
Declare Function winDefaultWinCancelIo StdCall Lib "kernel32" _
    Alias "CancelIo" (ByVal hFile As Any Ptr) As SQLITE_C_INT
Declare Sub winDefaultWinOutputDebugStringA StdCall Lib "kernel32" _
    Alias "OutputDebugStringA" (ByVal zMessage As Const ZString Ptr)
Declare Function winDefaultWinMemGetProcessHeap StdCall Lib "kernel32" _
    Alias "GetProcessHeap" () As Any Ptr
Declare Function winDefaultWinMemHeapCreate StdCall Lib "kernel32" _
    Alias "HeapCreate" ( _
    ByVal options As SQLITE_C_UINT, _
    ByVal initialSize As SQLITE_SIZE_T, _
    ByVal maximumSize As SQLITE_SIZE_T _
) As Any Ptr
Declare Function winDefaultWinMemHeapDestroy StdCall Lib "kernel32" _
    Alias "HeapDestroy" (ByVal hHeap As Any Ptr) As SQLITE_C_INT
Declare Function winDefaultWinMemHeapAlloc StdCall Lib "kernel32" _
    Alias "HeapAlloc" ( _
    ByVal hHeap As Any Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal nByte As SQLITE_SIZE_T _
) As Any Ptr
Declare Function winDefaultWinMemHeapFree StdCall Lib "kernel32" _
    Alias "HeapFree" ( _
    ByVal hHeap As Any Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal pMemory As Any Ptr _
) As SQLITE_C_INT
Declare Function winDefaultWinMemHeapRealloc StdCall Lib "kernel32" _
    Alias "HeapReAlloc" ( _
    ByVal hHeap As Any Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal pMemory As Any Ptr, _
    ByVal nByte As SQLITE_SIZE_T _
) As Any Ptr
Declare Function winDefaultWinMemHeapSize StdCall Lib "kernel32" _
    Alias "HeapSize" ( _
    ByVal hHeap As Any Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal pMemory As Any Ptr _
) As SQLITE_SIZE_T
Declare Function winDefaultWinMemHeapValidate StdCall Lib "kernel32" _
    Alias "HeapValidate" ( _
    ByVal hHeap As Any Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal pMemory As Any Ptr _
) As SQLITE_C_INT
Declare Function winDefaultWinMemHeapCompact StdCall Lib "kernel32" _
    Alias "HeapCompact" ( _
    ByVal hHeap As Any Ptr, _
    ByVal flags As SQLITE_C_UINT _
) As SQLITE_C_UINT
Declare Sub winDefaultWinGetSystemTimeAsFileTime StdCall Lib "kernel32" _
    Alias "GetSystemTimeAsFileTime" (ByVal pFileTime As WinFileTime Ptr)

#include once "sqlite3_os_win_syscall_table.bi"
#include once "sqlite3_os_win_syscall_dispatch.bi"

Private Dim Shared winMemoryBarrierWord As SQLITE_C_INT

Sub sqlite3MemoryBarrier CDecl Alias "sqlite3MemoryBarrier" () Export
    ' An interlocked read with identical exchange and comparison values is a
    ' full memory barrier on Win32 and Win64. Upstream keeps this operation
    ' outside the override table because SDKs may expose it as an intrinsic.
    winDefaultWinMemoryBarrierCompareExchange(@winMemoryBarrierWord, 0, 0)
End Sub

#ifdef SQLITE_TEST
' src/os_win.c exposes this variable for deterministic VFS clock tests.
Extern sqlite3_current_time Alias "sqlite3_current_time" As SQLITE_C_INT
Dim Shared sqlite3_current_time As SQLITE_C_INT
#endif

#ifdef SQLITE_TEST
Extern sqlite3_win_test_unc_locking Alias "sqlite3_win_test_unc_locking" _
    As SQLITE_C_INT
Dim Shared sqlite3_win_test_unc_locking As SQLITE_C_INT = 0
#endif

/' ---------------------------------------------------------------------------
   Process-wide directory overrides
'/ 

Function sqlite3_win32_set_directory8 CDecl Alias "sqlite3_win32_set_directory8" ( _
    ByVal directoryType As SQLITE_C_ULONG, _
    ByVal zValue As Const ZString Ptr _
) As SQLITE_C_INT
    Dim rc As SQLITE_C_INT = SQLITE_OK

#ifndef SQLITE_OMIT_AUTOINIT
    rc = sqlite3_initialize()
    If rc <> SQLITE_OK Then Return rc
#endif

    sqlite3_mutex_enter(sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_TEMPDIR))
    Dim ppDirectory As ZString Ptr Ptr = 0
    If directoryType = SQLITE_WIN32_DATA_DIRECTORY_TYPE Then
        ppDirectory = @sqlite3_data_directory
    ElseIf directoryType = SQLITE_WIN32_TEMP_DIRECTORY_TYPE Then
        ppDirectory = @sqlite3_temp_directory
    End If

    If ppDirectory <> 0 Then
        Dim zCopy As ZString Ptr = 0
        If zValue <> 0 AndAlso CPtr(Const UByte Ptr, zValue)[0] <> 0 Then
            ' Preserve the current override if the replacement cannot be allocated.
            zCopy = sqlite3_mprintf(StrPtr(!"%s"), zValue)
            If zCopy = 0 Then
#ifdef SQLITE_DEBUG
                ' Match the upstream C source line used by sqlite3NomemError.
                rc = sqlite3NomemError(1382)
#else
                rc = SQLITE_NOMEM
#endif
                GoTo set_directory8_done
            End If
        End If
        sqlite3_free(ppDirectory[0])
        ppDirectory[0] = zCopy
        rc = SQLITE_OK
    Else
        rc = SQLITE_ERROR
    End If

set_directory8_done:
    sqlite3_mutex_leave(sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_TEMPDIR))
    Return rc
End Function

Private Function winUtf8ToUnicode CDecl Alias "winUtf8ToUnicode" ( _
    ByVal zText As Const ZString Ptr _
) As UShort Ptr
    Dim nChar As SQLITE_C_INT = winMultiByteToWideChar( _
        WIN_CP_UTF8, 0, zText, -1, 0, 0)
    If nChar = 0 Then Return 0

    Dim zWideText As UShort Ptr = CPtr( _
        UShort Ptr, sqlite3MallocZero( _
            CULngInt(nChar) * CULngInt(SizeOf(UShort))))
    If zWideText = 0 Then Return 0

    nChar = winMultiByteToWideChar( _
        WIN_CP_UTF8, 0, zText, -1, zWideText, nChar)
    If nChar = 0 Then
        sqlite3_free(zWideText)
        Return 0
    End If
    Return zWideText
End Function

Function sqlite3_win32_utf8_to_unicode CDecl Alias "sqlite3_win32_utf8_to_unicode" ( _
    ByVal zText As Const ZString Ptr _
) As UShort Ptr Export
#ifdef SQLITE_ENABLE_API_ARMOR
    If zText = 0 Then
#ifdef SQLITE_DEBUG
        sqlite3MisuseError(1263)
#endif
        Return 0
    End If
#endif
#ifndef SQLITE_OMIT_AUTOINIT
    If sqlite3_initialize() <> SQLITE_OK Then Return 0
#endif
    Return winUtf8ToUnicode(zText)
End Function

Private Function winUnicodeToUtf8( _
    ByVal zWideText As Const UShort Ptr _
) As ZString Ptr
    Dim nByte As SQLITE_C_INT = winWideCharToMultiByte( _
        WIN_CP_UTF8, 0, zWideText, -1, 0, 0, 0, 0)
    If nByte = 0 Then Return 0

    Dim zText As ZString Ptr = _
        CPtr(ZString Ptr, sqlite3MallocZero(CULngInt(nByte)))
    If zText = 0 Then Return 0

    nByte = winWideCharToMultiByte( _
        WIN_CP_UTF8, 0, zWideText, -1, zText, nByte, 0, 0)
    If nByte = 0 Then
        sqlite3_free(zText)
        Return 0
    End If
    Return zText
End Function

Function sqlite3_win32_unicode_to_utf8 CDecl Alias "sqlite3_win32_unicode_to_utf8" ( _
    ByVal zWideText As Const Any Ptr _
) As ZString Ptr Export
#ifdef SQLITE_ENABLE_API_ARMOR
    If zWideText = 0 Then
#ifdef SQLITE_DEBUG
        sqlite3MisuseError(1279)
#endif
        Return 0
    End If
#endif
#ifndef SQLITE_OMIT_AUTOINIT
    If sqlite3_initialize() <> SQLITE_OK Then Return 0
#endif
    Return winUnicodeToUtf8(CPtr(Const UShort Ptr, zWideText))
End Function

/' ---------------------------------------------------------------------------
   ANSI/OEM and UTF-8 conversion
'/ 

' MultiByteToWideChar and WideCharToMultiByte report the required output
' length when the destination is null. With a -1 input length, that count
' includes the terminating zero, so the returned SQLite buffer is ready for
' use as a null-terminated string after the second conversion call succeeds.
Private Function winMbcsToUnicode( _
    ByVal zText As Const ZString Ptr, _
    ByVal useAnsi As SQLITE_C_INT _
) As UShort Ptr
    If zText = 0 Then Return 0

    Dim codePage As SQLITE_C_UINT = WIN_CP_OEMCP
    If useAnsi <> 0 Then codePage = WIN_CP_ACP

    Dim nWideChar As SQLITE_C_INT = winMultiByteToWideChar( _
        codePage, 0, zText, -1, 0, 0)
    If nWideChar <= 0 Then Return 0

    Dim zWideText As UShort Ptr = CPtr( _
        UShort Ptr, sqlite3MallocZero( _
            CULngInt(nWideChar) * CULngInt(SizeOf(UShort))))
    If zWideText = 0 Then Return 0

    nWideChar = winMultiByteToWideChar( _
        codePage, 0, zText, -1, zWideText, nWideChar)
    If nWideChar <= 0 Then
        sqlite3_free(zWideText)
        Return 0
    End If
    Return zWideText
End Function

Private Function winUnicodeToMbcs( _
    ByVal zWideText As Const UShort Ptr, _
    ByVal useAnsi As SQLITE_C_INT _
) As ZString Ptr
    If zWideText = 0 Then Return 0

    Dim codePage As SQLITE_C_UINT = WIN_CP_OEMCP
    If useAnsi <> 0 Then codePage = WIN_CP_ACP

    Dim nByte As SQLITE_C_INT = winWideCharToMultiByte( _
        codePage, 0, zWideText, -1, 0, 0, 0, 0)
    If nByte <= 0 Then Return 0

    Dim zText As ZString Ptr = _
        CPtr(ZString Ptr, sqlite3MallocZero(CULngInt(nByte)))
    If zText = 0 Then Return 0

    nByte = winWideCharToMultiByte( _
        codePage, 0, zWideText, -1, zText, nByte, 0, 0)
    If nByte <= 0 Then
        sqlite3_free(zText)
        Return 0
    End If
    Return zText
End Function

Private Function winMbcsToUtf8( _
    ByVal zText As Const ZString Ptr, _
    ByVal useAnsi As SQLITE_C_INT _
) As ZString Ptr
    Dim zWideText As UShort Ptr = winMbcsToUnicode(zText, useAnsi)
    If zWideText = 0 Then Return 0

    Dim zUtf8 As ZString Ptr = winUnicodeToUtf8(zWideText)
    sqlite3_free(zWideText)
    Return zUtf8
End Function

Private Function winUtf8ToMbcs( _
    ByVal zText As Const ZString Ptr, _
    ByVal useAnsi As SQLITE_C_INT _
) As ZString Ptr
    Dim zWideText As UShort Ptr = winUtf8ToUnicode(zText)
    If zWideText = 0 Then Return 0

    Dim zMbcs As ZString Ptr = winUnicodeToMbcs(zWideText, useAnsi)
    sqlite3_free(zWideText)
    Return zMbcs
End Function

Function sqlite3_win32_mbcs_to_utf8 CDecl Alias "sqlite3_win32_mbcs_to_utf8" ( _
    ByVal zText As Const ZString Ptr _
) As ZString Ptr Export
#ifdef SQLITE_ENABLE_API_ARMOR
    If zText = 0 Then
#ifdef SQLITE_DEBUG
        sqlite3MisuseError(1295)
#endif
        Return 0
    End If
#endif
#ifndef SQLITE_OMIT_AUTOINIT
    If sqlite3_initialize() <> SQLITE_OK Then Return 0
#endif
    Return winMbcsToUtf8(zText, winAreFileApisANSI())
End Function

Function sqlite3_win32_mbcs_to_utf8_v2 CDecl Alias "sqlite3_win32_mbcs_to_utf8_v2" ( _
    ByVal zText As Const ZString Ptr, _
    ByVal useAnsi As SQLITE_C_INT _
) As ZString Ptr Export
#ifdef SQLITE_ENABLE_API_ARMOR
    If zText = 0 Then
#ifdef SQLITE_DEBUG
        sqlite3MisuseError(1311)
#endif
        Return 0
    End If
#endif
#ifndef SQLITE_OMIT_AUTOINIT
    If sqlite3_initialize() <> SQLITE_OK Then Return 0
#endif
    Return winMbcsToUtf8(zText, useAnsi)
End Function

Function sqlite3_win32_utf8_to_mbcs CDecl Alias "sqlite3_win32_utf8_to_mbcs" ( _
    ByVal zText As Const ZString Ptr _
) As ZString Ptr Export
#ifdef SQLITE_ENABLE_API_ARMOR
    If zText = 0 Then
#ifdef SQLITE_DEBUG
        sqlite3MisuseError(1327)
#endif
        Return 0
    End If
#endif
#ifndef SQLITE_OMIT_AUTOINIT
    If sqlite3_initialize() <> SQLITE_OK Then Return 0
#endif
    Return winUtf8ToMbcs(zText, winAreFileApisANSI())
End Function

Function sqlite3_win32_utf8_to_mbcs_v2 CDecl Alias "sqlite3_win32_utf8_to_mbcs_v2" ( _
    ByVal zText As Const ZString Ptr, _
    ByVal useAnsi As SQLITE_C_INT _
) As ZString Ptr Export
#ifdef SQLITE_ENABLE_API_ARMOR
    If zText = 0 Then
#ifdef SQLITE_DEBUG
        sqlite3MisuseError(1343)
#endif
        Return 0
    End If
#endif
#ifndef SQLITE_OMIT_AUTOINIT
    If sqlite3_initialize() <> SQLITE_OK Then Return 0
#endif
    Return winUtf8ToMbcs(zText, useAnsi)
End Function

/' ---------------------------------------------------------------------------
   Windows VFS error formatting
'/ 

' FormatMessageW allocates its wide result through LocalAlloc when the
' ALLOCATE_BUFFER flag is set. FROM_SYSTEM selects the Win32 message table;
' IGNORE_INSERTS avoids interpreting untrusted insert parameters.
Private Const WIN_FORMAT_MESSAGE_ALLOCATE_BUFFER As SQLITE_C_UINT = &H100
Private Const WIN_FORMAT_MESSAGE_FROM_SYSTEM As SQLITE_C_UINT = &H1000
Private Const WIN_FORMAT_MESSAGE_IGNORE_INSERTS As SQLITE_C_UINT = &H200

Private Function winGetLastErrorMsg CDecl Alias "winGetLastErrorMsg" ( _
    ByVal lastError As SQLITE_C_UINT, _
    ByVal bufferSize As SQLITE_C_INT, _
    ByVal zBuffer As ZString Ptr _
) As SQLITE_C_INT
    If bufferSize <= 0 OrElse zBuffer = 0 Then Return 0

    Dim wideMessage As UShort Ptr = 0
    Dim messageLength As SQLITE_C_UINT = winFormatMessageW( _
        WIN_FORMAT_MESSAGE_ALLOCATE_BUFFER Or _
        WIN_FORMAT_MESSAGE_FROM_SYSTEM Or _
        WIN_FORMAT_MESSAGE_IGNORE_INSERTS, _
        0, lastError, 0, @wideMessage, 0, 0)

    Dim utf8Message As ZString Ptr = 0
    If messageLength > 0 AndAlso wideMessage <> 0 Then
        sqlite3BeginBenignMalloc()
        utf8Message = winUnicodeToUtf8(wideMessage)
        sqlite3EndBenignMalloc()
        winLocalFree(wideMessage)
    End If

    If utf8Message = 0 Then
        sqlite3_snprintf( _
            bufferSize, zBuffer, StrPtr(!"OsError 0x%lx (%lu)"), _
            lastError, lastError)
    Else
        sqlite3_snprintf( _
            bufferSize, zBuffer, StrPtr(!"%s"), utf8Message)
        sqlite3_free(utf8Message)
    End If
    Return 0
End Function

Private Function winLogErrorAtLine CDecl Alias "winLogErrorAtLine" ( _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal lastError As SQLITE_C_UINT, _
    ByVal zFunction As Const ZString Ptr, _
    ByVal zPath As Const ZString Ptr, _
    ByVal sourceLine As SQLITE_C_INT _
) As SQLITE_C_INT
    If errorCode = SQLITE_OK Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("errcode!=SQLITE_OK"))
#endif
        Return errorCode
    End If

    Dim zMessage As ZString * 500
    zMessage = ""
    winGetLastErrorMsg( _
        lastError, CLng(SizeOf(zMessage)), StrPtr(zMessage))

    Dim pathText As Const ZString Ptr = zPath
    If pathText = 0 Then pathText = StrPtr(!"")
    Dim functionText As Const ZString Ptr = zFunction
    If functionText = 0 Then functionText = StrPtr(!"")

    Dim messageBytes As UByte Ptr = CPtr(UByte Ptr, StrPtr(zMessage))
    Dim index As SQLITE_C_INT = 0
    While messageBytes[index] <> 0 AndAlso _
          messageBytes[index] <> 13 AndAlso messageBytes[index] <> 10
        index += 1
    Wend
    messageBytes[index] = 0

    sqlite3_log( _
        errorCode, _
        StrPtr(!"os_win.c:%d: (%lu) %s(%s) - %s"), _
        sourceLine, lastError, functionText, pathText, StrPtr(zMessage))
    Return errorCode
End Function

Private Function winGetLastError CDecl Alias "winGetLastError" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal bufferSize As SQLITE_C_INT, _
    ByVal zBuffer As ZString Ptr _
) As SQLITE_C_INT
    Dim lastError As SQLITE_C_UINT = winGetLastErrorCode()
    If bufferSize > 0 AndAlso zBuffer <> 0 Then
        winGetLastErrorMsg(lastError, bufferSize, zBuffer)
    End If
    Return CLng(lastError)
End Function

Private Function winIoerrCanRetry(ByVal lastError As SQLITE_C_UINT) _
    As SQLITE_C_INT
    Select Case lastError
    Case WIN_ERROR_ACCESS_DENIED, WIN_ERROR_SHARING_VIOLATION, _
         WIN_ERROR_LOCK_VIOLATION, WIN_ERROR_DEV_NOT_EXIST, _
         WIN_ERROR_NETNAME_DELETED, WIN_ERROR_SEM_TIMEOUT, _
         WIN_ERROR_NETWORK_UNREACHABLE
        Return 1
    End Select
    Return 0
End Function

Private Function winRetryIoerr CDecl Alias "winRetryIoerr" ( _
    ByVal pRetryCount As SQLITE_C_INT Ptr, _
    ByVal pErrorOut As SQLITE_C_UINT Ptr _
) As SQLITE_C_INT
    If pRetryCount = 0 Then Return 0
    Dim lastError As SQLITE_C_UINT = winGetLastErrorCode()

    If pRetryCount[0] < 0 OrElse pRetryCount[0] >= winIoerrRetry Then
        If pErrorOut <> 0 Then pErrorOut[0] = lastError
        Return 0
    End If

    If winIoerrCanRetry(lastError) = 0 Then
        If pErrorOut <> 0 Then pErrorOut[0] = lastError
        Return 0
    End If

    Dim retryDelay As sqlite3_int64 = winIoerrRetryDelay
    If retryDelay < 0 Then retryDelay = 0
    retryDelay *= CLngInt(pRetryCount[0]) + 1
    If retryDelay > 4294967295 Then retryDelay = 4294967295
    winSleepMilliseconds(CULng(retryDelay))
    If pRetryCount[0] < 2147483647 Then pRetryCount[0] += 1
    Return 1
End Function

Private Sub winLogIoerr CDecl Alias "winLogIoerr" ( _
    ByVal retryCount As SQLITE_C_INT, _
    ByVal sourceLine As SQLITE_C_INT _
)
    If retryCount = 0 Then Exit Sub
    Dim retryDelay As sqlite3_int64 = winIoerrRetryDelay
    If retryDelay < 0 Then retryDelay = 0
    Dim totalDelay As sqlite3_int64 = 0
    If retryCount > 0 AndAlso retryDelay > 0 Then
        Dim factor1 As sqlite3_int64 = retryCount
        Dim factor2 As sqlite3_int64 = factor1 + 1
        If (factor1 Mod 2) = 0 Then
            factor1 \= 2
        Else
            factor2 \= 2
        End If
        If factor1 > 2147483647 \ factor2 Then
            totalDelay = 2147483647
        Else
            Dim attemptFactor As sqlite3_int64 = factor1 * factor2
            If attemptFactor > 2147483647 \ retryDelay Then
                totalDelay = 2147483647
            Else
                totalDelay = attemptFactor * retryDelay
            End If
        End If
    End If
    sqlite3_log( _
        SQLITE_NOTICE, _
        StrPtr(!"delayed %dms for lock/sharing conflict at line %d"), _
        CLngInt(totalDelay), sourceLine)
End Sub

Private Function winDelete CDecl Alias "winDelete" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal zFilename As Const ZString Ptr, _
    ByVal syncDirectory As SQLITE_C_INT _
) As SQLITE_C_INT
    If zFilename = 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then Return SQLITE_IOERR_DELETE
#endif

    Dim zWideFilename As UShort Ptr = winUtf8ToUnicode(zFilename)
    If zWideFilename = 0 Then Return SQLITE_IOERR_NOMEM

    Dim retryCount As SQLITE_C_INT = 0
    Dim lastError As SQLITE_C_UINT = 0
    Dim resultCode As SQLITE_C_INT
    Do
        Dim attributes As SQLITE_C_UINT = _
            winGetFileAttributesW(zWideFilename)
        If attributes = WIN_INVALID_FILE_ATTRIBUTES Then
            lastError = winGetLastErrorCode()
            If lastError = WIN_ERROR_FILE_NOT_FOUND OrElse _
               lastError = WIN_ERROR_PATH_NOT_FOUND Then
                resultCode = SQLITE_IOERR_DELETE_NOENT
            Else
                resultCode = SQLITE_ERROR
            End If
            Exit Do
        End If
        If (attributes And WIN_FILE_ATTRIBUTE_DIRECTORY) <> 0 Then
            resultCode = SQLITE_ERROR
            Exit Do
        End If
        If winDeleteFileW(zWideFilename) <> 0 Then
            resultCode = SQLITE_OK
            Exit Do
        End If
        If winRetryIoerr(@retryCount, @lastError) = 0 Then
            resultCode = SQLITE_ERROR
            Exit Do
        End If
    Loop

    If resultCode <> SQLITE_OK AndAlso _
       resultCode <> SQLITE_IOERR_DELETE_NOENT Then
        resultCode = winLogErrorAtLine( _
            SQLITE_IOERR_DELETE, lastError, StrPtr(!"winDelete"), _
            zFilename, 4599)
    Else
        winLogIoerr(retryCount, 4601)
    End If
    sqlite3_free(zWideFilename)
    Return resultCode
End Function

#ifndef SQLITE_WIN32_DBG_BUF_SIZE
' The upstream buffer reserves one DWORD within its 4096-byte debug block.
#define SQLITE_WIN32_DBG_BUF_SIZE 4092
#endif

Sub sqlite3_win32_write_debug CDecl Alias "sqlite3_win32_write_debug" ( _
    ByVal zBuffer As Const ZString Ptr, _
    ByVal inputSize As SQLITE_C_INT _
) Export
    Dim copySize As SQLITE_C_INT = inputSize
    If copySize > SQLITE_WIN32_DBG_BUF_SIZE - 1 Then _
        copySize = SQLITE_WIN32_DBG_BUF_SIZE - 1
    If copySize < -1 Then copySize = -1

#ifdef SQLITE_ENABLE_API_ARMOR
    If zBuffer = 0 Then
#ifdef SQLITE_DEBUG
        sqlite3MisuseError(877)
#endif
        Return
    End If
#endif
    If zBuffer = 0 Then Return

    If copySize > 0 Then
        Dim debugBuffer As ZString * SQLITE_WIN32_DBG_BUF_SIZE
        Dim debugBytes As UByte Ptr = CPtr( _
            UByte Ptr, StrPtr(debugBuffer))
        Dim inputBytes As Const UByte Ptr = CPtr(Const UByte Ptr, zBuffer)
        For i As SQLITE_C_INT = 0 To copySize - 1
            debugBytes[i] = inputBytes[i]
        Next
        debugBytes[copySize] = 0
        ' The default OutputDebugStringA import bypasses the syscall table.
        winOutputDebugStringA(StrPtr(debugBuffer))
    Else
        winOutputDebugStringA(zBuffer)
    End If
End Sub

#ifndef SQLITE_OMIT_LOAD_EXTENSION
Private Function winDlOpen CDecl Alias "winDlOpen" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal zFilename As Const ZString Ptr _
) As Any Ptr
    If zFilename = 0 Then Return 0
    Dim zWideFilename As UShort Ptr = winUtf8ToUnicode(zFilename)
    If zWideFilename = 0 Then Return 0

    Dim hModule As Any Ptr = winLoadLibraryW(zWideFilename)
    sqlite3_free(zWideFilename)
    Return hModule
End Function

Private Sub winDlError CDecl Alias "winDlError" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal bufferSize As SQLITE_C_INT, _
    ByVal zBuffer As ZString Ptr _
)
    winGetLastErrorMsg(winGetLastErrorCode(), bufferSize, zBuffer)
End Sub

Private Function winDlSym CDecl Alias "winDlSym" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal hModule As Any Ptr, _
    ByVal zSymbol As Const ZString Ptr _
) As Any Ptr
    If hModule = 0 OrElse zSymbol = 0 Then Return 0
    Return winGetProcAddress(hModule, zSymbol)
End Function

Private Sub winDlClose CDecl Alias "winDlClose" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal hModule As Any Ptr _
)
    If hModule <> 0 Then winFreeLibrary(hModule)
End Sub
#endif

Sub sqlite3_win32_sleep CDecl Alias "sqlite3_win32_sleep" ( _
    ByVal milliseconds As SQLITE_C_UINT _
) Export
    ' Sleep is part of the shared table so fault-injection clients can replace it.
    winSleepMilliseconds(milliseconds)
End Sub

#if SQLITE_MAX_WORKER_THREADS > 0 AndAlso SQLITE_THREADSAFE > 0
Function sqlite3Win32Wait CDecl Alias "sqlite3Win32Wait" ( _
    ByVal hObject As Any Ptr _
) As SQLITE_C_UINT Export
    Dim waitResult As SQLITE_C_UINT
    Do
        ' Alertable waits may return after an APC without signaling the handle.
        waitResult = winWaitForSingleObjectEx(hObject, &HFFFFFFFF, 1)
    Loop While waitResult = &HC0
    Return waitResult
End Function
#endif

Private Function winSleep CDecl Alias "winSleep" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal microseconds As SQLITE_C_INT _
) As SQLITE_C_INT
    Dim milliseconds As sqlite3_int64 = _
        (CLngInt(microseconds) + 999) \ 1000
    If milliseconds < 0 Then milliseconds = 0
    winSleepMilliseconds(CULng(milliseconds))

    Dim sleptMicroseconds As sqlite3_int64 = milliseconds * 1000
    If sleptMicroseconds > 2147483647 Then Return 2147483647
    Return CLngInt(sleptMicroseconds)
End Function

#if Not defined(SQLITE_TEST) AndAlso Not defined(SQLITE_OMIT_RANDOMNESS)
Private Sub xorMemory CDecl Alias "xorMemory" ( _
    ByVal pGatherer As WinEntropyGatherer Ptr, _
    ByVal pSource As Const UByte Ptr, _
    ByVal byteCount As SQLITE_C_INT _
)
    If pGatherer = 0 OrElse pGatherer->bytes = 0 OrElse _
       pSource = 0 OrElse pGatherer->bufferLength <= 0 OrElse byteCount <= 0 Then _
        Exit Sub

    Dim targetIndex As SQLITE_C_INT = pGatherer->index
    For sourceIndex As SQLITE_C_INT = 0 To byteCount - 1
        pGatherer->bytes[targetIndex] = _
            pGatherer->bytes[targetIndex] Xor pSource[sourceIndex]
        targetIndex += 1
        If targetIndex >= pGatherer->bufferLength Then targetIndex = 0
    Next
    pGatherer->index = targetIndex
    pGatherer->byteCount += byteCount
End Sub
#endif

Private Function winRandomness CDecl Alias "winRandomness" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal outputBytes As SQLITE_C_INT, _
    ByVal zOutput As ZString Ptr _
) As SQLITE_C_INT
    If outputBytes < 0 OrElse (outputBytes > 0 AndAlso zOutput = 0) Then _
        Return SQLITE_MISUSE
    If outputBytes = 0 Then Return 0

#if defined(SQLITE_TEST) OrElse defined(SQLITE_OMIT_RANDOMNESS)
    winMemset(zOutput, 0, CULngInt(outputBytes))
    Return outputBytes
#else
    Dim entropy As WinEntropyGatherer
    entropy.bytes = CPtr(UByte Ptr, zOutput)
    entropy.bufferLength = outputBytes
    entropy.index = 0
    entropy.byteCount = 0
    winMemset(zOutput, 0, CULngInt(outputBytes))

    Dim fileTime As WinFileTime
    winGetSystemTimeAsFileTime(@fileTime)
    xorMemory(@entropy, CPtr(Const UByte Ptr, @fileTime), SizeOf(WinFileTime))

    Dim processId As SQLITE_C_UINT = winGetCurrentProcessId()
    xorMemory(@entropy, CPtr(Const UByte Ptr, @processId), SizeOf(processId))

    Dim tickCount As sqlite3_uint64 = winGetTickCount64()
    xorMemory(@entropy, CPtr(Const UByte Ptr, @tickCount), SizeOf(tickCount))

    Dim performanceCounter As LARGE_INTEGER
    performanceCounter.QuadPart = 0
    winQueryPerformanceCounter(@performanceCounter)
    xorMemory( _
        @entropy, CPtr(Const UByte Ptr, @performanceCounter), _
        SizeOf(performanceCounter))

#if SQLITE_WIN32_USE_UUID
    Dim uuid As WinUuid
    winMemset(@uuid, 0, SizeOf(uuid))
    winUuidCreate(@uuid)
    xorMemory(@entropy, CPtr(Const UByte Ptr, @uuid), SizeOf(uuid))
    winMemset(@uuid, 0, SizeOf(uuid))
    winUuidCreateSequential(@uuid)
    xorMemory(@entropy, CPtr(Const UByte Ptr, @uuid), SizeOf(uuid))
#endif

    If entropy.byteCount > outputBytes Then Return outputBytes
    Return entropy.byteCount
#endif
End Function

/' ---------------------------------------------------------------------------
   Windows VFS clock callbacks
'/ 

Private Function winCurrentTimeInt64 CDecl Alias "winCurrentTimeInt64" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal pJulianDay As sqlite3_int64 Ptr _
) As SQLITE_C_INT
    If pJulianDay = 0 Then Return SQLITE_MISUSE

    Dim fileTime As WinFileTime
    ' Keep clock reads on the same override path as file and lock calls.
    winGetSystemTimeAsFileTime(@fileTime)

    ' FILETIME counts 100 ns intervals from 1601-01-01 UTC.
    Const WIN_FILETIME_EPOCH_MS As sqlite3_int64 = 199222286400000
    Const FILETIME_TICKS_PER_MILLISECOND As sqlite3_int64 = 10000
    Const UINT32_RANGE As sqlite3_int64 = 4294967296

    Dim fileTimeTicks As sqlite3_int64 = _
        CLngInt(fileTime.highDateTime) * UINT32_RANGE + _
        CLngInt(fileTime.lowDateTime)
    pJulianDay[0] = WIN_FILETIME_EPOCH_MS + _
        fileTimeTicks \ FILETIME_TICKS_PER_MILLISECOND

#ifdef SQLITE_TEST
    Const WIN_UNIX_EPOCH_MS As sqlite3_int64 = 210866760000000
    If sqlite3_current_time <> 0 Then
        pJulianDay[0] = _
            CLngInt(sqlite3_current_time) * 1000 + WIN_UNIX_EPOCH_MS
    End If
#endif

    Return SQLITE_OK
End Function

Private Function winCurrentTime CDecl Alias "winCurrentTime" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal pJulianDay As Double Ptr _
) As SQLITE_C_INT
    If pJulianDay = 0 Then Return SQLITE_MISUSE

    Dim timeValue As sqlite3_int64 = 0
    Dim rc As SQLITE_C_INT = winCurrentTimeInt64(pVfs, @timeValue)
    If rc <> SQLITE_OK Then Return rc

    pJulianDay[0] = CDbl(timeValue) / 86400000.0
    Return SQLITE_OK
End Function

Function sqlite3_win32_set_directory16 CDecl Alias "sqlite3_win32_set_directory16" ( _
    ByVal directoryType As SQLITE_C_ULONG, _
    ByVal zValue As Const Any Ptr _
) As SQLITE_C_INT Export
    Dim zUtf8 As ZString Ptr = 0
    If zValue <> 0 Then
        zUtf8 = sqlite3_win32_unicode_to_utf8(zValue)
        If zUtf8 = 0 Then
#ifdef SQLITE_DEBUG
            Return sqlite3NomemError(1409)
#else
            Return SQLITE_NOMEM
#endif
        End If
    End If

    Dim rc As SQLITE_C_INT = sqlite3_win32_set_directory8( _
        directoryType, zUtf8)
    If zUtf8 <> 0 Then sqlite3_free(zUtf8)
    Return rc
End Function

Function sqlite3_win32_set_directory CDecl Alias "sqlite3_win32_set_directory" ( _
    ByVal directoryType As SQLITE_C_ULONG, _
    ByVal zValue As Any Ptr _
) As SQLITE_C_INT Export
    Return sqlite3_win32_set_directory16( _
        directoryType, CPtr(Const Any Ptr, zValue))
End Function

Private Function winConvertFromUtf8Filename CDecl Alias "winConvertFromUtf8Filename" ( _
    ByVal zFilename As Const ZString Ptr _
) As UShort Ptr
#ifdef SQLITE3_FB_CYGWIN
    If zFilename = 0 Then Return 0

    Dim filenameBytes As Const UByte Ptr = CPtr(Const UByte Ptr, zFilename)
    Dim filenameLength As SQLITE_C_INT = sqlite3Strlen30(zFilename)
    Dim isDriveAbsolute As SQLITE_C_INT = 0
    If filenameLength >= 3 Then
        Dim firstByte As UByte = filenameBytes[0]
        Dim isDriveLetter As SQLITE_C_INT = _
            CInt((firstByte >= Asc("A") AndAlso firstByte <= Asc("Z")) OrElse _
                 (firstByte >= Asc("a") AndAlso firstByte <= Asc("z")))
        isDriveAbsolute = CInt( _
            isDriveLetter <> 0 AndAlso filenameBytes[1] = Asc(":") AndAlso _
            (filenameBytes[2] = Asc("/") OrElse filenameBytes[2] = Asc("\")))
    End If

    If isDriveAbsolute = 0 AndAlso winSystemCallCurrent(58) <> 0 Then
        Dim containsSlash As SQLITE_C_INT = 0
        For byteIndex As SQLITE_C_INT = 0 To filenameLength - 1
            If filenameBytes[byteIndex] = Asc("/") Then
                containsSlash = 1
                Exit For
            End If
        Next

        ' Cygwin's conversion API returns the required byte count when the
        ' destination is null and the size argument is zero.
        Dim conversionFlags As SQLITE_C_UINT = 1
        If containsSlash = 0 Then conversionFlags Or= &H100
        Dim requiredBytes As Integer = winCygwinConvPath( _
            conversionFlags, zFilename, 0, 0)
        If requiredBytes > 0 Then
            Dim allocationBytes As sqlite3_uint64 = _
                CULngInt(requiredBytes) + 12
            Dim zConverted As UShort Ptr = CPtr( _
                UShort Ptr, sqlite3MallocZero(allocationBytes))
            If zConverted = 0 Then Return 0

            If winCygwinConvPath( _
                conversionFlags, zFilename, zConverted + 4, _
                CULngInt(requiredBytes)) = 0 Then
                If (conversionFlags And &H100) <> 0 Then
                    winMemmove(zConverted, zConverted + 4, _
                        CULngInt(requiredBytes))
                ElseIf zConverted[4] <> Asc("\") OrElse _
                       zConverted[5] <> Asc("\") Then
                    zConverted[0] = Asc("\")
                    zConverted[1] = Asc("\")
                    zConverted[2] = Asc("?")
                    zConverted[3] = Asc("\")
                ElseIf zConverted[6] <> Asc("?") Then
                    winMemmove(zConverted + 6, zConverted + 4, _
                        CULngInt(requiredBytes))
                    zConverted[0] = Asc("\")
                    zConverted[1] = Asc("\")
                    zConverted[2] = Asc("?")
                    zConverted[3] = Asc("\")
                    zConverted[4] = Asc("U")
                    zConverted[5] = Asc("N")
                    zConverted[6] = Asc("C")
                Else
                    winMemmove(zConverted, zConverted + 4, _
                        CULngInt(requiredBytes))
                End If
                Return zConverted
            End If
            sqlite3_free(zConverted)
        End If

    End If

    ' Keep the upstream fallback for drive paths and failed Cygwin conversion.
    Dim nChar As SQLITE_C_INT = winMultiByteToWideChar( _
        WIN_CP_UTF8, 0, zFilename, -1, 0, 0)
    If nChar = 0 Then Return 0

    Dim zConverted As UShort Ptr = CPtr( _
        UShort Ptr, sqlite3MallocZero( _
            CULngInt(nChar + 6) * CULngInt(SizeOf(UShort))))
    If zConverted = 0 Then Return 0

    nChar = winMultiByteToWideChar( _
        WIN_CP_UTF8, 0, zFilename, -1, zConverted, nChar)
    If nChar = 0 Then
        sqlite3_free(zConverted)
        Return 0
    End If

    If nChar > SQLITE_WIN32_MAX_PATH_CHARS AndAlso isDriveAbsolute <> 0 Then
        winMemmove(zConverted + 4, zConverted, _
            CULngInt(nChar) * CULngInt(SizeOf(UShort)))
        zConverted[0] = Asc("\")
        zConverted[1] = Asc("\")
        zConverted[2] = Asc("?")
        zConverted[3] = Asc("\")
    ElseIf nChar > SQLITE_WIN32_MAX_PATH_CHARS AndAlso _
           filenameLength >= 3 AndAlso _
           (filenameBytes[0] = Asc("/") OrElse filenameBytes[0] = Asc("\")) AndAlso _
           (filenameBytes[1] = Asc("/") OrElse filenameBytes[1] = Asc("\")) AndAlso _
           filenameBytes[2] <> Asc("?") Then
        winMemmove(zConverted + 6, zConverted, _
            CULngInt(nChar) * CULngInt(SizeOf(UShort)))
        zConverted[0] = Asc("\")
        zConverted[1] = Asc("\")
        zConverted[2] = Asc("?")
        zConverted[3] = Asc("\")
        zConverted[4] = Asc("U")
        zConverted[5] = Asc("N")
        zConverted[6] = Asc("C")
    End If
    Return zConverted
#else
    Return winUtf8ToUnicode(zFilename)
#endif
End Function

/' ---------------------------------------------------------------------------
   No-lock I/O methods
'/ 

Private Function winNolockLock CDecl Alias "winNolockLock" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal lockType As SQLITE_C_INT _
) As SQLITE_C_INT
    ' This method is safe only when the application prevents concurrent access.
    Return SQLITE_OK
End Function

Private Function winNolockCheckReservedLock CDecl Alias "winNolockCheckReservedLock" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal pReservedOut As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    Return SQLITE_OK
End Function

Private Function winNolockUnlock CDecl Alias "winNolockUnlock" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal lockType As SQLITE_C_INT _
) As SQLITE_C_INT
    Return SQLITE_OK
End Function

Private Function winSectorSize CDecl Alias "winSectorSize" ( _
    ByVal pFile As sqlite3_file Ptr _
) As SQLITE_C_INT
    Return SQLITE_DEFAULT_SECTOR_SIZE
End Function

Private Sub winModeBit CDecl Alias "winModeBit" ( _
    ByVal pArgument As winFile Ptr, _
    ByVal mask As UByte, _
    ByVal pValue As SQLITE_C_INT Ptr _
)
    If pArgument = 0 OrElse pValue = 0 Then Exit Sub
    If pValue[0] < 0 Then
        pValue[0] = IIf((pArgument->ctrlFlags And mask) <> 0, 1, 0)
    ElseIf pValue[0] = 0 Then
        pArgument->ctrlFlags = pArgument->ctrlFlags And Not mask
    Else
        pArgument->ctrlFlags = pArgument->ctrlFlags Or mask
    End If
End Sub

Private Function winDeviceCharacteristics CDecl Alias "winDeviceCharacteristics" ( _
    ByVal pArgument As sqlite3_file Ptr _
) As SQLITE_C_INT
    If pArgument = 0 Then Return 0
    Dim pFile As winFile Ptr = CPtr(winFile Ptr, pArgument)
    Dim characteristics As SQLITE_C_INT = _
        SQLITE_IOCAP_UNDELETABLE_WHEN_OPEN Or SQLITE_IOCAP_SUBPAGE_READ
    If (pFile->ctrlFlags And WINFILE_PSOW) <> 0 Then _
        characteristics = characteristics Or SQLITE_IOCAP_POWERSAFE_OVERWRITE
    Return characteristics
End Function



Private Function winLockFile CDecl Alias "winLockFile" ( _
    ByVal pFileHandle As Any Ptr Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal offsetLow As SQLITE_C_UINT, _
    ByVal offsetHigh As SQLITE_C_UINT, _
    ByVal bytesLow As SQLITE_C_UINT, _
    ByVal bytesHigh As SQLITE_C_UINT _
) As SQLITE_C_INT
    If pFileHandle = 0 Then Return 0
    Dim overlapped As OVERLAPPED = Type<OVERLAPPED>(0, 0, 0, 0, 0)
    overlapped.offset = offsetLow
    overlapped.offsetHigh = offsetHigh
    Return winLockFileEx( _
        pFileHandle[0], flags, 0, bytesLow, bytesHigh, @overlapped)
End Function

Private Function winUnlockFile CDecl Alias "winUnlockFile" ( _
    ByVal pFileHandle As Any Ptr Ptr, _
    ByVal offsetLow As SQLITE_C_UINT, _
    ByVal offsetHigh As SQLITE_C_UINT, _
    ByVal bytesLow As SQLITE_C_UINT, _
    ByVal bytesHigh As SQLITE_C_UINT _
) As SQLITE_C_INT
    If pFileHandle = 0 Then Return 0
    Dim overlapped As OVERLAPPED = Type<OVERLAPPED>(0, 0, 0, 0, 0)
    overlapped.offset = offsetLow
    overlapped.offsetHigh = offsetHigh
    Return winUnlockFileEx( _
        pFileHandle[0], 0, bytesLow, bytesHigh, @overlapped)
End Function

#ifndef SQLITE_OMIT_WAL
Private Function winHandleUnlock CDecl Alias "winHandleUnlock" ( _
    ByVal hFile As Any Ptr, _
    ByVal offset As SQLITE_C_INT, _
    ByVal bytes As SQLITE_C_INT _
) As SQLITE_C_INT
    Dim fileHandle As Any Ptr = hFile
    If winUnlockFile( _
        @fileHandle, CULng(offset), 0, CULng(bytes), 0) <> 0 Then
        Return SQLITE_OK
    End If
    Return SQLITE_IOERR_UNLOCK
End Function

' WinError.h values used for lock flags and asynchronous lock completion.
Private Const WIN_LOCKFILE_FAIL_IMMEDIATELY As SQLITE_C_UINT = 1
Private Const WIN_LOCKFILE_EXCLUSIVE_LOCK As SQLITE_C_UINT = 2
Private Const WIN_WAIT_OBJECT_0 As SQLITE_C_UINT = 0
Private Const WIN_WAIT_TIMEOUT As SQLITE_C_UINT = 258
Private Const WIN_WAIT_INFINITE As SQLITE_C_UINT = &HFFFFFFFF

Private Function winHandleLockTimeout CDecl Alias "winHandleLockTimeout" ( _
    ByVal hFile As Any Ptr, _
    ByVal offset As SQLITE_C_UINT, _
    ByVal bytes As SQLITE_C_UINT, _
    ByVal exclusive As SQLITE_C_INT, _
    ByVal waitMilliseconds As SQLITE_C_UINT _
) As SQLITE_C_INT
    Dim lockFlags As SQLITE_C_UINT = WIN_LOCKFILE_FAIL_IMMEDIATELY
    If exclusive <> 0 Then lockFlags = lockFlags Or WIN_LOCKFILE_EXCLUSIVE_LOCK

    Dim resultCode As SQLITE_C_INT = SQLITE_OK
    Dim overlapped As OVERLAPPED = Type<OVERLAPPED>(0, 0, 0, 0, 0)
    overlapped.offset = offset

#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    If waitMilliseconds <> 0 Then _
        lockFlags = lockFlags And Not WIN_LOCKFILE_FAIL_IMMEDIATELY
    overlapped.hEvent = winCreateEventW(0, 1, 0, 0)
    If overlapped.hEvent = 0 Then Return SQLITE_IOERR_LOCK
#endif

    Dim locked As SQLITE_C_INT = winLockFileEx( _
        hFile, lockFlags, 0, bytes, 0, @overlapped)

#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    If locked = 0 AndAlso winGetLastErrorCode() = WIN_ERROR_IO_PENDING Then
        Dim timeout As SQLITE_C_UINT = waitMilliseconds
        If timeout = 0 Then timeout = WIN_WAIT_INFINITE
        Dim waitResult As SQLITE_C_UINT = _
            winWaitForSingleObject(overlapped.hEvent, timeout)
        If waitResult = WIN_WAIT_OBJECT_0 Then
            locked = 1
        ElseIf waitResult = WIN_WAIT_TIMEOUT Then
#if SQLITE_ENABLE_SETLK_TIMEOUT = 1
            resultCode = SQLITE_BUSY_TIMEOUT
#else
            resultCode = SQLITE_BUSY
#endif
        Else
            resultCode = SQLITE_IOERR_LOCK
        End If
        winCancelIo(hFile)
    End If
    winCloseHandle(overlapped.hEvent)
#endif

    If resultCode = SQLITE_OK AndAlso locked = 0 Then _
        resultCode = SQLITE_BUSY
    Return resultCode
End Function
#endif

Private Function winHandleSeek CDecl Alias "winHandleSeek" ( _
    ByVal hFile As Any Ptr, _
    ByVal offset As sqlite3_int64 _
) As SQLITE_C_INT
    Dim filePosition As LARGE_INTEGER
    filePosition.QuadPart = offset
    If winSetFilePointerEx(hFile, filePosition, 0, WIN_FILE_BEGIN) = 0 Then _
        Return SQLITE_IOERR_SEEK
    Return SQLITE_OK
End Function

Private Function winSeekFile CDecl Alias "winSeekFile" ( _
    ByVal pFileArgument As winFile Ptr, _
    ByVal offset As sqlite3_int64 _
) As SQLITE_C_INT
    If pFileArgument = 0 Then Return SQLITE_MISUSE
    Dim rc As SQLITE_C_INT = winHandleSeek(pFileArgument->h, offset)
    If rc <> SQLITE_OK Then
        pFileArgument->lastErrno = winGetLastErrorCode()
        winLogErrorAtLine( _
            rc, pFileArgument->lastErrno, StrPtr(!"winSeekFile"), _
            pFileArgument->zPath, 1761)
    End If
    Return rc
End Function

#ifndef SQLITE_OMIT_WAL
Private Function winHandleTruncate CDecl Alias "winHandleTruncate" ( _
    ByVal hFile As Any Ptr, _
    ByVal nByte As sqlite3_int64 _
) As SQLITE_C_INT
    Dim rc As SQLITE_C_INT = winHandleSeek(hFile, nByte)
    If rc <> SQLITE_OK Then Return rc
    If winSetEndOfFile(hFile) = 0 Then Return SQLITE_IOERR_TRUNCATE
    Return SQLITE_OK
End Function

Private Function winHandleSize CDecl Alias "winHandleSize" ( _
    ByVal hFile As Any Ptr, _
    ByVal pByteCount As sqlite3_int64 Ptr _
) As SQLITE_C_INT
    If pByteCount = 0 Then Return SQLITE_MISUSE
    Dim fileSize As LARGE_INTEGER
    If winGetFileSizeEx(hFile, @fileSize) = 0 Then
        pByteCount[0] = 0
        Return SQLITE_IOERR_FSTAT
    End If
    pByteCount[0] = fileSize.QuadPart
    Return SQLITE_OK
End Function

Private Sub winHandleClose CDecl Alias "winHandleClose" ( _
    ByVal hFile As Any Ptr _
)
    If hFile <> CPtr(Any Ptr, -1) Then winCloseHandle(hFile)
End Sub
#endif

Private Function winFileSize CDecl Alias "winFileSize" ( _
    ByVal pFileArgument As sqlite3_file Ptr, _
    ByVal pSize As sqlite3_int64 Ptr _
) As SQLITE_C_INT
    If pFileArgument = 0 OrElse pSize = 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then Return SQLITE_IOERR_FSTAT
#endif
    Dim pFile As winFile Ptr = CPtr(winFile Ptr, pFileArgument)
    Dim fileSize As LARGE_INTEGER
    If winGetFileSizeEx(pFile->h, @fileSize) = 0 Then
        pSize[0] = 0
        pFile->lastErrno = winGetLastErrorCode()
        Return winLogErrorAtLine( _
            SQLITE_IOERR_FSTAT, pFile->lastErrno, StrPtr(!"winFileSize"), _
            pFile->zPath, 2238)
    End If
    pSize[0] = fileSize.QuadPart
    Return SQLITE_OK
End Function

#if SQLITE_MAX_MMAP_SIZE > 0
Private Const WIN_PAGE_READONLY As SQLITE_C_UINT = 2
Private Const WIN_PAGE_READWRITE As SQLITE_C_UINT = 4
Private Const WIN_FILE_MAP_READ As SQLITE_C_UINT = 4
Private Const WIN_FILE_MAP_WRITE As SQLITE_C_UINT = 2

Private Function winUnmapfile CDecl Alias "winUnmapfile" ( _
    ByVal pFile As winFile Ptr _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE

    If pFile->pMapRegion <> 0 Then
        If winUnmapViewOfFile(pFile->pMapRegion) = 0 Then
            pFile->lastErrno = winGetLastErrorCode()
            Return winLogErrorAtLine( _
                SQLITE_IOERR_MMAP, pFile->lastErrno, _
                StrPtr(!"winUnmapfile1"), pFile->zPath, 3772)
        End If
        pFile->pMapRegion = 0
        pFile->mmapSize = 0
    End If

    If pFile->hMap <> 0 Then
        If winCloseHandle(pFile->hMap) = 0 Then
            pFile->lastErrno = winGetLastErrorCode()
            Return winLogErrorAtLine( _
                SQLITE_IOERR_MMAP, pFile->lastErrno, _
                StrPtr(!"winUnmapfile2"), pFile->zPath, 3783)
        End If
        pFile->hMap = 0
    End If
    Return SQLITE_OK
End Function

Private Function winMapfile CDecl Alias "winMapfile" ( _
    ByVal pFile As winFile Ptr, _
    ByVal requestedSize As sqlite3_int64 _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
    If pFile->nFetchOut > 0 Then Return SQLITE_OK

    Dim mapSize As sqlite3_int64 = requestedSize
    If mapSize < 0 Then
        Dim rc As SQLITE_C_INT = winFileSize( _
            CPtr(sqlite3_file Ptr, pFile), @mapSize)
        If rc <> SQLITE_OK Then Return SQLITE_IOERR_FSTAT
    End If
    If pFile->mmapSizeMax < 0 Then pFile->mmapSizeMax = 0
    If mapSize > pFile->mmapSizeMax Then mapSize = pFile->mmapSizeMax

    Dim systemInfo As SYSTEM_INFO
    winGetSystemInfo(@systemInfo)
    If systemInfo.dwPageSize = 0 Then Return SQLITE_ERROR
    Dim pageMask As sqlite3_int64 = _
        CLngInt(systemInfo.dwPageSize) - 1
    mapSize = mapSize And Not pageMask

    If mapSize = 0 AndAlso pFile->mmapSize > 0 Then
        Dim unmapRc As SQLITE_C_INT = winUnmapfile(pFile)
        If unmapRc <> SQLITE_OK Then Return unmapRc
    End If

    If mapSize <> pFile->mmapSize Then
        Dim protect As SQLITE_C_UINT = WIN_PAGE_READONLY
        Dim flags As SQLITE_C_UINT = WIN_FILE_MAP_READ

        Dim unmapRc As SQLITE_C_INT = winUnmapfile(pFile)
        If unmapRc <> SQLITE_OK Then Return unmapRc

#ifdef SQLITE_MMAP_READWRITE
        If (pFile->ctrlFlags And WINFILE_RDONLY) = 0 Then
            protect = WIN_PAGE_READWRITE
            flags = flags Or WIN_FILE_MAP_WRITE
        End If
#endif

        Dim mapSizeUnsigned As ULongInt = CULngInt(mapSize)
        Dim sizeHigh As SQLITE_C_UINT = _
            CUInt((mapSizeUnsigned Shr 32) And &HFFFFFFFFULL)
        Dim sizeLow As SQLITE_C_UINT = CUInt(mapSizeUnsigned And &HFFFFFFFFULL)

        pFile->hMap = winCreateFileMappingW( _
            pFile->h, 0, protect, sizeHigh, sizeLow, 0)
        If pFile->hMap = 0 Then
            pFile->lastErrno = winGetLastErrorCode()
            winLogErrorAtLine( _
                SQLITE_IOERR_MMAP, pFile->lastErrno, _
                StrPtr(!"winMapfile1"), pFile->zPath, 3856)
            Return SQLITE_OK
        End If

        If SizeOf(SQLITE_SIZE_T) < SizeOf(sqlite3_int64) AndAlso _
           mapSizeUnsigned > &HFFFFFFFFULL Then
            winCloseHandle(pFile->hMap)
            pFile->hMap = 0
            Return SQLITE_OK
        End If

        Dim newRegion As Any Ptr = winMapViewOfFile( _
            pFile->hMap, flags, 0, 0, CULngInt(mapSizeUnsigned))
        If newRegion = 0 Then
            winCloseHandle(pFile->hMap)
            pFile->hMap = 0
            pFile->lastErrno = winGetLastErrorCode()
            winLogErrorAtLine( _
                SQLITE_IOERR_MMAP, pFile->lastErrno, _
                StrPtr(!"winMapfile2"), pFile->zPath, 3874)
            Return SQLITE_OK
        End If

        pFile->pMapRegion = newRegion
        pFile->mmapSize = mapSize
    End If
    Return SQLITE_OK
End Function
#endif

/' ---------------------------------------------------------------------------
   Windows file read, write, truncate, and sync callbacks
'/ 

Private Function winRead CDecl Alias "winRead" ( _
    ByVal pFileArgument As sqlite3_file Ptr, _
    ByVal pBuffer As Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal fileOffset As sqlite3_int64 _
) As SQLITE_C_INT
    If pFileArgument = 0 OrElse pBuffer = 0 OrElse amount <= 0 OrElse _
       fileOffset < 0 Then Return SQLITE_MISUSE
    If fileOffset > WIN_SQLITE_INT64_MAX - amount Then _
        Return SQLITE_IOERR_READ

    Dim pFile As winFile Ptr = CPtr(winFile Ptr, pFileArgument)
    If pFile->h = 0 OrElse pFile->h = CPtr(Any Ptr, -1) Then _
        Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then Return SQLITE_IOERR_READ
#endif

    Dim destination As Any Ptr = pBuffer
    Dim bytesRemaining As SQLITE_C_INT = amount
    Dim readOffset As sqlite3_int64 = fileOffset
#if SQLITE_MAX_MMAP_SIZE > 0
    If readOffset < pFile->mmapSize AndAlso pFile->pMapRegion <> 0 Then
        Dim mappedBytes As UByte Ptr = CPtr(UByte Ptr, pFile->pMapRegion)
        If readOffset + bytesRemaining <= pFile->mmapSize Then
            winMemcpy(destination, @mappedBytes[CULngInt(readOffset)], _
                     CULngInt(bytesRemaining))
            Return SQLITE_OK
        End If

        Dim copyBytes As SQLITE_C_INT = CInt(pFile->mmapSize - readOffset)
        If copyBytes > 0 Then
            winMemcpy(destination, @mappedBytes[CULngInt(readOffset)], _
                     CULngInt(copyBytes))
            destination = CPtr(UByte Ptr, destination) + copyBytes
            bytesRemaining -= copyBytes
            readOffset += copyBytes
        End If
    End If
#endif

    Dim retryCount As SQLITE_C_INT = 0
    Dim lastError As SQLITE_C_UINT = 0
    Dim bytesRead As SQLITE_C_UINT = 0
    Dim overlapped As OVERLAPPED = Type<OVERLAPPED>(0, 0, 0, 0, 0)
    Dim overlappedPointer As OVERLAPPED Ptr = 0
#ifdef SQLITE_WIN32_NO_OVERLAPPED
    If winSeekFile(pFile, readOffset) <> SQLITE_OK Then Return SQLITE_FULL
#else
    Dim unsignedOffset As sqlite3_uint64 = CULngInt(readOffset)
    overlapped.offset = CUInt(unsignedOffset And &HFFFFFFFFULL)
    overlapped.offsetHigh = CUInt((unsignedOffset Shr 32) And &H7FFFFFFFULL)
    overlappedPointer = @overlapped
#endif

    Do
        bytesRead = 0
        If winReadFile( _
            pFile->h, destination, CUInt(bytesRemaining), @bytesRead, _
            overlappedPointer) <> 0 Then Exit Do
        lastError = winGetLastErrorCode()
        If lastError = WIN_ERROR_HANDLE_EOF Then Exit Do
        If winRetryIoerr(@retryCount, @lastError) <> 0 Then Continue Do

        pFile->lastErrno = lastError
        Return winLogErrorAtLine( _
            SQLITE_IOERR_READ, pFile->lastErrno, StrPtr(!"winRead"), _
            pFile->zPath, 1879)
    Loop
    winLogIoerr(retryCount, 1882)

    If bytesRead > CUInt(bytesRemaining) Then
        Return SQLITE_IOERR_READ
    End If
    If bytesRead < CUInt(bytesRemaining) Then
        winMemset( _
            CPtr(UByte Ptr, destination) + bytesRead, 0, _
            CULngInt(bytesRemaining - CInt(bytesRead)))
        Return SQLITE_IOERR_SHORT_READ
    End If
    Return SQLITE_OK
End Function

Private Function winWrite CDecl Alias "winWrite" ( _
    ByVal pFileArgument As sqlite3_file Ptr, _
    ByVal pBuffer As Const Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal fileOffset As sqlite3_int64 _
) As SQLITE_C_INT
    If pFileArgument = 0 OrElse pBuffer = 0 OrElse amount <= 0 OrElse _
       fileOffset < 0 Then Return SQLITE_MISUSE
    If fileOffset > WIN_SQLITE_INT64_MAX - amount Then _
        Return SQLITE_IOERR_WRITE

    Dim pFile As winFile Ptr = CPtr(winFile Ptr, pFileArgument)
    If pFile->h = 0 OrElse pFile->h = CPtr(Any Ptr, -1) Then _
        Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then Return SQLITE_IOERR_WRITE
    If fbTestSimulateDiskfull() <> 0 Then Return SQLITE_FULL
#endif

    Dim source As Const UByte Ptr = CPtr(Const UByte Ptr, pBuffer)
    Dim bytesRemaining As SQLITE_C_INT = amount
    Dim writeOffset As sqlite3_int64 = fileOffset
#if defined(SQLITE_MMAP_READWRITE) AndAlso SQLITE_MAX_MMAP_SIZE > 0
    If writeOffset < pFile->mmapSize AndAlso pFile->pMapRegion <> 0 Then
        Dim mappedBytes As UByte Ptr = CPtr(UByte Ptr, pFile->pMapRegion)
        If writeOffset + bytesRemaining <= pFile->mmapSize Then
            winMemcpy( _
                @mappedBytes[CULngInt(writeOffset)], source, _
                CULngInt(bytesRemaining))
            Return SQLITE_OK
        End If

        Dim copyBytes As SQLITE_C_INT = CInt(pFile->mmapSize - writeOffset)
        If copyBytes > 0 Then
            winMemcpy( _
                @mappedBytes[CULngInt(writeOffset)], source, _
                CULngInt(copyBytes))
            source += copyBytes
            bytesRemaining -= copyBytes
            writeOffset += copyBytes
        End If
    End If
#endif

    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim retryCount As SQLITE_C_INT = 0
    Dim lastError As SQLITE_C_UINT = 0
    Dim bytesWritten As SQLITE_C_UINT = 0
    Dim overlapped As OVERLAPPED = Type<OVERLAPPED>(0, 0, 0, 0, 0)
    Dim overlappedPointer As OVERLAPPED Ptr = 0
#ifdef SQLITE_WIN32_NO_OVERLAPPED
    rc = winSeekFile(pFile, writeOffset)
#else
    Dim unsignedOffset As sqlite3_uint64 = CULngInt(writeOffset)
    overlapped.offset = CUInt(unsignedOffset And &HFFFFFFFFULL)
    overlapped.offsetHigh = CUInt((unsignedOffset Shr 32) And &H7FFFFFFFULL)
    overlappedPointer = @overlapped
#endif

    If rc = SQLITE_OK Then
        Do While bytesRemaining > 0
            bytesWritten = 0
            If winWriteFile( _
                pFile->h, source, CUInt(bytesRemaining), @bytesWritten, _
                overlappedPointer) = 0 Then
                If winRetryIoerr(@retryCount, @lastError) <> 0 Then _
                    Continue Do
                Exit Do
            End If

            If bytesWritten = 0 OrElse _
               bytesWritten > CUInt(bytesRemaining) Then
                lastError = winGetLastErrorCode()
                Exit Do
            End If

#ifndef SQLITE_WIN32_NO_OVERLAPPED
            writeOffset += CInt(bytesWritten)
            unsignedOffset = CULngInt(writeOffset)
            overlapped.offset = CUInt(unsignedOffset And &HFFFFFFFFULL)
            overlapped.offsetHigh = CUInt((unsignedOffset Shr 32) And &H7FFFFFFFULL)
#endif
            source += bytesWritten
            bytesRemaining -= CInt(bytesWritten)
        Loop
    End If

    If bytesRemaining > 0 Then
        If rc <> SQLITE_OK Then lastError = pFile->lastErrno
        pFile->lastErrno = lastError
        If pFile->lastErrno = WIN_ERROR_HANDLE_DISK_FULL OrElse _
           pFile->lastErrno = WIN_ERROR_DISK_FULL Then
            Return winLogErrorAtLine( _
                SQLITE_FULL, pFile->lastErrno, StrPtr(!"winWrite1"), _
                pFile->zPath, 1991)
        End If
        Return winLogErrorAtLine( _
            SQLITE_IOERR_WRITE, pFile->lastErrno, StrPtr(!"winWrite2"), _
            pFile->zPath, 1996)
    End If

    winLogIoerr(retryCount, 1999)
    Return SQLITE_OK
End Function

Private Function winTruncate CDecl Alias "winTruncate" ( _
    ByVal pFileArgument As sqlite3_file Ptr, _
    ByVal requestedBytes As sqlite3_int64 _
) As SQLITE_C_INT
    If pFileArgument = 0 OrElse requestedBytes < 0 Then Return SQLITE_MISUSE

    Dim pFile As winFile Ptr = CPtr(winFile Ptr, pFileArgument)
    If pFile->h = 0 OrElse pFile->h = CPtr(Any Ptr, -1) Then _
        Return SQLITE_MISUSE
#if SQLITE_MAX_MMAP_SIZE > 0
    If pFile->nFetchOut > 0 Then Return SQLITE_OK
#endif
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then Return SQLITE_IOERR_TRUNCATE
#endif

    Dim newSize As sqlite3_int64 = requestedBytes
    If pFile->szChunk > 0 Then
        Dim chunkSize As sqlite3_int64 = pFile->szChunk
        If newSize > WIN_SQLITE_INT64_MAX - (chunkSize - 1) Then _
            Return SQLITE_IOERR_TRUNCATE
        newSize = ((newSize + chunkSize - 1) \ chunkSize) * chunkSize
    End If

    Dim oldMappedSize As sqlite3_int64 = 0
#if SQLITE_MAX_MMAP_SIZE > 0
    If pFile->pMapRegion <> 0 Then oldMappedSize = pFile->mmapSize
    winUnmapfile(pFile)
#endif

    Dim rc As SQLITE_C_INT = winSeekFile(pFile, newSize)
    If rc <> SQLITE_OK Then
        rc = winLogErrorAtLine( _
            SQLITE_IOERR_TRUNCATE, pFile->lastErrno, _
            StrPtr(!"winTruncate1"), pFile->zPath, 2104)
    ElseIf winSetEndOfFile(pFile->h) = 0 Then
        Dim lastError As SQLITE_C_UINT = winGetLastErrorCode()
        If lastError <> WIN_ERROR_USER_MAPPED_FILE Then
            pFile->lastErrno = lastError
            rc = winLogErrorAtLine( _
                SQLITE_IOERR_TRUNCATE, pFile->lastErrno, _
                StrPtr(!"winTruncate2"), pFile->zPath, 2109)
        End If
    End If

#if SQLITE_MAX_MMAP_SIZE > 0
    If rc = SQLITE_OK AndAlso oldMappedSize > 0 Then
        If oldMappedSize > newSize Then
            winMapfile(pFile, -1)
        Else
            winMapfile(pFile, oldMappedSize)
        End If
    End If
#endif
    Return rc
End Function

Private Function winSync CDecl Alias "winSync" ( _
    ByVal pFileArgument As sqlite3_file Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFileArgument = 0 Then Return SQLITE_MISUSE
    If (flags And &HF) <> SQLITE_SYNC_NORMAL AndAlso _
       (flags And &HF) <> SQLITE_SYNC_FULL Then Return SQLITE_MISUSE

    Dim pFile As winFile Ptr = CPtr(winFile Ptr, pFileArgument)
    If pFile->h = 0 OrElse pFile->h = CPtr(Any Ptr, -1) Then _
        Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    If (flags And &HF) = SQLITE_SYNC_FULL Then sqlite3_fullsync_count += 1
    sqlite3_sync_count += 1
    If fbTestSimulateDiskfull() <> 0 Then Return SQLITE_FULL
#endif

#ifdef SQLITE_NO_SYNC
    Return SQLITE_OK
#else
#if SQLITE_MAX_MMAP_SIZE > 0
    If pFile->pMapRegion <> 0 AndAlso _
       winFlushViewOfFile(pFile->pMapRegion, 0) = 0 Then
        pFile->lastErrno = winGetLastErrorCode()
        Return winLogErrorAtLine( _
            SQLITE_IOERR_MMAP, pFile->lastErrno, StrPtr(!"winSync1"), _
            pFile->zPath, 2201)
    End If
#endif
    Dim flushSucceeded As SQLITE_C_INT = winFlushFileBuffers(pFile->h)
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then flushSucceeded = 0
#endif
    If flushSucceeded <> 0 Then Return SQLITE_OK
    pFile->lastErrno = winGetLastErrorCode()
    Return winLogErrorAtLine( _
        SQLITE_IOERR_FSYNC, pFile->lastErrno, StrPtr(!"winSync2"), _
        pFile->zPath, 2216)
#endif
End Function

Private Function winClose CDecl Alias "winClose" ( _
    ByVal pFileArgument As sqlite3_file Ptr _
) As SQLITE_C_INT
    If pFileArgument = 0 Then Return SQLITE_MISUSE
    Dim pFile As winFile Ptr = CPtr(winFile Ptr, pFileArgument)
    If pFile->h = 0 OrElse pFile->h = CPtr(Any Ptr, -1) Then _
        Return SQLITE_MISUSE
#ifndef SQLITE_OMIT_WAL
    If pFile->pShm <> 0 Then Return SQLITE_MISUSE
#endif

#if SQLITE_MAX_MMAP_SIZE > 0
    winUnmapfile(pFile)
#endif

    Dim closeSucceeded As SQLITE_C_INT = 0
    Dim lastError As SQLITE_C_UINT = 0
    For attempt As SQLITE_C_INT = 0 To 2
        If winCloseHandle(pFile->h) <> 0 Then
            closeSucceeded = 1
            Exit For
        End If
        lastError = winGetLastErrorCode()
        If attempt < 2 Then winSleepMilliseconds(100)
    Next

#ifdef SQLITE_TEST
    sqlite3_open_file_count -= 1
#endif
    If closeSucceeded = 0 Then
        pFile->lastErrno = lastError
        Return winLogErrorAtLine( _
            SQLITE_IOERR_CLOSE, pFile->lastErrno, StrPtr(!"winClose"), _
            pFile->zPath, 1811)
    End If

    pFile->h = 0
    Return SQLITE_OK
End Function

/' ---------------------------------------------------------------------------
   Windows byte-range locking callbacks
'/ 

Private Function winGetReadLock( _
    ByVal pFile As winFile Ptr, _
    ByVal blockUntilAvailable As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFile = 0 OrElse pFile->h = 0 OrElse _
       pFile->h = CPtr(Any Ptr, -1) Then Return 0
    Dim lockFlags As SQLITE_C_UINT = SQLITE_LOCKFILEEX_FLAGS
    If blockUntilAvailable <> 0 Then _
        lockFlags = lockFlags And Not WIN_LOCKFILE_FAIL_IMMEDIATELY
    Dim result As SQLITE_C_INT = winLockFile( _
        @pFile->h, lockFlags, WIN_SHARED_FIRST, 0, WIN_SHARED_SIZE, 0)
    If result = 0 Then pFile->lastErrno = winGetLastErrorCode()
    Return result
End Function

Private Function winUnlockReadLock( _
    ByVal pFile As winFile Ptr _
) As SQLITE_C_INT
    If pFile = 0 OrElse pFile->h = 0 OrElse _
       pFile->h = CPtr(Any Ptr, -1) Then Return 0
    Dim result As SQLITE_C_INT = winUnlockFile( _
        @pFile->h, WIN_SHARED_FIRST, 0, WIN_SHARED_SIZE, 0)
    If result = 0 Then
        Dim lastError As SQLITE_C_UINT = winGetLastErrorCode()
        If lastError <> WIN_ERROR_NOT_LOCKED Then
            pFile->lastErrno = lastError
            winLogErrorAtLine( _
                SQLITE_IOERR_UNLOCK, lastError, _
                StrPtr(!"winUnlockReadLock"), pFile->zPath, 2309)
        End If
    End If
    Return result
End Function

Private Function winLock CDecl Alias "winLock" ( _
    ByVal pFileArgument As sqlite3_file Ptr, _
    ByVal requestedLock As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFileArgument = 0 Then Return SQLITE_MISUSE
    Dim pFile As winFile Ptr = CPtr(winFile Ptr, pFileArgument)
    If pFile->h = 0 OrElse pFile->h = CPtr(Any Ptr, -1) Then _
        Return SQLITE_MISUSE
    If requestedLock < SQLITE_LOCK_SHARED OrElse _
       requestedLock > SQLITE_LOCK_EXCLUSIVE OrElse _
       requestedLock = SQLITE_LOCK_PENDING Then Return SQLITE_MISUSE

    If pFile->locktype >= requestedLock Then Return SQLITE_OK
    If (pFile->ctrlFlags And WINFILE_RDONLY) <> 0 AndAlso _
       requestedLock >= SQLITE_LOCK_RESERVED Then Return SQLITE_IOERR_LOCK
    If (pFile->locktype = SQLITE_LOCK_NONE AndAlso _
        requestedLock <> SQLITE_LOCK_SHARED) OrElse _
       (requestedLock = SQLITE_LOCK_RESERVED AndAlso _
        pFile->locktype <> SQLITE_LOCK_SHARED) Then Return SQLITE_MISUSE

    Dim result As SQLITE_C_INT = 1
    Dim newLockType As SQLITE_C_INT = pFile->locktype
    Dim gotPendingLock As SQLITE_C_INT = 0
    Dim lastError As SQLITE_C_UINT = 0

    If requestedLock = SQLITE_LOCK_SHARED OrElse _
       (requestedLock = SQLITE_LOCK_EXCLUSIVE AndAlso _
        pFile->locktype = SQLITE_LOCK_RESERVED) Then
        Dim retry As SQLITE_C_INT = 3
        Dim flags As SQLITE_C_UINT = WIN_LOCKFILE_FAIL_IMMEDIATELY
        If requestedLock = SQLITE_LOCK_EXCLUSIVE Then _
            flags = flags Or WIN_LOCKFILE_EXCLUSIVE

        While retry > 0
            result = winLockFile( _
                @pFile->h, flags, WIN_PENDING_BYTE, 0, 1, 0)
            If result <> 0 Then Exit While
            lastError = winGetLastErrorCode()
            If lastError = WIN_ERROR_INVALID_HANDLE Then
                pFile->lastErrno = lastError
                Return SQLITE_IOERR_LOCK
            End If
            retry -= 1
            If retry > 0 Then winSleepMilliseconds(1)
        Wend
        gotPendingLock = result
    End If

    If requestedLock = SQLITE_LOCK_SHARED AndAlso result <> 0 Then
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
        result = winGetReadLock(pFile, pFile->bBlockOnConnect)
#else
        result = winGetReadLock(pFile, 0)
#endif
        If result <> 0 Then
            newLockType = SQLITE_LOCK_SHARED
        Else
            lastError = winGetLastErrorCode()
        End If
    End If

    If requestedLock = SQLITE_LOCK_RESERVED AndAlso result <> 0 Then
        result = winLockFile( _
            @pFile->h, SQLITE_LOCKFILE_FLAGS, WIN_RESERVED_BYTE, 0, 1, 0)
        If result <> 0 Then
            newLockType = SQLITE_LOCK_RESERVED
        Else
            lastError = winGetLastErrorCode()
        End If
    End If

    If requestedLock = SQLITE_LOCK_EXCLUSIVE AndAlso result <> 0 Then
        newLockType = SQLITE_LOCK_PENDING
        gotPendingLock = 0
        winUnlockReadLock(pFile)

        result = winLockFile( _
            @pFile->h, SQLITE_LOCKFILE_FLAGS, _
            WIN_SHARED_FIRST, 0, WIN_SHARED_SIZE, 0)
        If result <> 0 Then
            newLockType = SQLITE_LOCK_EXCLUSIVE
        Else
            lastError = winGetLastErrorCode()
            winGetReadLock(pFile, 0)
        End If
    End If

    If gotPendingLock <> 0 AndAlso requestedLock = SQLITE_LOCK_SHARED Then
        winUnlockFile(@pFile->h, WIN_PENDING_BYTE, 0, 1, 0)
    End If

    Dim rc As SQLITE_C_INT = SQLITE_OK
    If result = 0 Then
        pFile->lastErrno = lastError
        rc = SQLITE_BUSY
    End If
    pFile->locktype = CUInt(newLockType)
    Return rc
End Function

Private Function winCheckReservedLock CDecl Alias "winCheckReservedLock" ( _
    ByVal pFileArgument As sqlite3_file Ptr, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pFileArgument = 0 OrElse pResult = 0 Then Return SQLITE_MISUSE
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then _
        Return SQLITE_IOERR_CHECKRESERVEDLOCK
#endif

    Dim pFile As winFile Ptr = CPtr(winFile Ptr, pFileArgument)
    If pFile->h = 0 OrElse pFile->h = CPtr(Any Ptr, -1) Then _
        Return SQLITE_MISUSE
    If pFile->locktype >= SQLITE_LOCK_RESERVED Then
        pResult[0] = 1
    Else
        Dim result As SQLITE_C_INT = winLockFile( _
            @pFile->h, SQLITE_LOCKFILEEX_FLAGS, _
            WIN_RESERVED_BYTE, 0, 1, 0)
        If result <> 0 Then
            winUnlockFile(@pFile->h, WIN_RESERVED_BYTE, 0, 1, 0)
        End If
        pResult[0] = CInt(result = 0)
    End If
    Return SQLITE_OK
End Function

Private Function winUnlock CDecl Alias "winUnlock" ( _
    ByVal pFileArgument As sqlite3_file Ptr, _
    ByVal requestedLock As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFileArgument = 0 OrElse _
       (requestedLock <> SQLITE_LOCK_NONE AndAlso _
        requestedLock <> SQLITE_LOCK_SHARED) Then Return SQLITE_MISUSE
    Dim pFile As winFile Ptr = CPtr(winFile Ptr, pFileArgument)
    If pFile->h = 0 OrElse pFile->h = CPtr(Any Ptr, -1) Then _
        Return SQLITE_MISUSE
    Dim oldLockType As SQLITE_C_INT = pFile->locktype
    Dim rc As SQLITE_C_INT = SQLITE_OK

    If oldLockType >= SQLITE_LOCK_EXCLUSIVE Then
        winUnlockFile( _
            @pFile->h, WIN_SHARED_FIRST, 0, WIN_SHARED_SIZE, 0)
        If requestedLock = SQLITE_LOCK_SHARED AndAlso _
           winGetReadLock(pFile, 0) = 0 Then
            rc = winLogErrorAtLine( _
                SQLITE_IOERR_UNLOCK, winGetLastErrorCode(), _
                StrPtr(!"winUnlock"), pFile->zPath, 2551)
        End If
    End If
    If oldLockType >= SQLITE_LOCK_RESERVED Then
        winUnlockFile(@pFile->h, WIN_RESERVED_BYTE, 0, 1, 0)
    End If
    If requestedLock = SQLITE_LOCK_NONE AndAlso _
       oldLockType >= SQLITE_LOCK_SHARED Then
        winUnlockReadLock(pFile)
    End If
    If oldLockType >= SQLITE_LOCK_PENDING Then
        winUnlockFile(@pFile->h, WIN_PENDING_BYTE, 0, 1, 0)
    End If

    pFile->locktype = CUInt(requestedLock)
    Return rc
End Function

Private Function winFetch CDecl Alias "winFetch" ( _
    ByVal pFileArgument As sqlite3_file Ptr, _
    ByVal offset As sqlite3_int64, _
    ByVal amount As SQLITE_C_INT, _
    ByVal pOutput As Any Ptr Ptr _
) As SQLITE_C_INT
    If pOutput = 0 Then Return SQLITE_MISUSE
    pOutput[0] = 0
#if SQLITE_MAX_MMAP_SIZE > 0
    If pFileArgument = 0 Then Return SQLITE_MISUSE
    Dim pFile As winFile Ptr = CPtr(winFile Ptr, pFileArgument)
    If pFile->mmapSizeMax <= 0 OrElse offset < 0 OrElse amount < 0 Then _
        Return SQLITE_OK

    If pFile->pMapRegion = 0 Then
        Dim rc As SQLITE_C_INT = winMapfile(pFile, -1)
        If rc <> SQLITE_OK Then Return rc
    End If

    ' Keep a readable guard after a returned page for SQLite's bounded
    ' overread tolerance when it examines a page from a corrupt database.
    Const WIN_MMAP_FETCH_EOF_GUARD As sqlite3_int64 = 256
    Const SQLITE_INT64_MAX As sqlite3_int64 = 9223372036854775807
    Dim amount64 As sqlite3_int64 = amount
    If pFile->pMapRegion = 0 OrElse _
       offset > SQLITE_INT64_MAX - amount64 - WIN_MMAP_FETCH_EOF_GUARD Then _
        Return SQLITE_OK

    Dim requiredBytes As sqlite3_int64 = _
        offset + amount64 + WIN_MMAP_FETCH_EOF_GUARD
    If pFile->mmapSize >= requiredBytes AndAlso _
       pFile->nFetchOut < 2147483647 Then
        Dim mappedBytes As UByte Ptr = CPtr(UByte Ptr, pFile->pMapRegion)
        pOutput[0] = @mappedBytes[CULngInt(offset)]
        pFile->nFetchOut += 1
    End If
#endif
    Return SQLITE_OK
End Function

Private Function winUnfetch CDecl Alias "winUnfetch" ( _
    ByVal pFileArgument As sqlite3_file Ptr, _
    ByVal offset As sqlite3_int64, _
    ByVal pFetch As Any Ptr _
) As SQLITE_C_INT
#if SQLITE_MAX_MMAP_SIZE > 0
    If pFileArgument = 0 Then Return SQLITE_MISUSE
    Dim pFile As winFile Ptr = CPtr(winFile Ptr, pFileArgument)
    If pFetch <> 0 Then
        If pFile->nFetchOut <= 0 OrElse pFile->pMapRegion = 0 Then _
            Return SQLITE_MISUSE
#ifdef SQLITE_DEBUG
        If offset < 0 Then
            sqlite3DebugAssert(StrPtr("p==0 || p==&pMapRegion[iOff]"))
            Return SQLITE_MISUSE
        End If
        Dim mappedBytes As UByte Ptr = CPtr(UByte Ptr, pFile->pMapRegion)
        If pFetch <> @mappedBytes[CULngInt(offset)] Then
            sqlite3DebugAssert(StrPtr("p==0 || p==&pMapRegion[iOff]"))
            Return SQLITE_MISUSE
        End If
#endif
        pFile->nFetchOut -= 1
    Else
        If pFile->nFetchOut <> 0 Then Return SQLITE_MISUSE
        ' The VFS contract requires the mapping to be invalidated on a null
        ' release. Upstream ignores the unmap error after winUnmapfile logs it.
        winUnmapfile(pFile)
    End If
#endif
    Return SQLITE_OK
End Function

/' ---------------------------------------------------------------------------
   Windows path and temporary-directory helpers
'/ 

Private Function winTestUncLocking() As SQLITE_C_INT
#ifdef SQLITE_TEST
    Return sqlite3_win_test_unc_locking
#else
    Return 0
#endif
End Function

Private Function winIsLongPathPrefix CDecl Alias "winIsLongPathPrefix" ( _
    ByVal zPathname As Const ZString Ptr _
) As SQLITE_C_INT
    If zPathname = 0 OrElse sqlite3Strlen30(zPathname) < 4 Then Return 0
    Dim pathBytes As Const UByte Ptr = CPtr(Const UByte Ptr, zPathname)
    If pathBytes[0] = WIN_PATH_SEPARATOR AndAlso _
       pathBytes[1] = WIN_PATH_SEPARATOR AndAlso _
       pathBytes[2] = Asc("?") AndAlso _
       pathBytes[3] = WIN_PATH_SEPARATOR Then Return 1
    Return 0
End Function

Private Function winIsDriveLetterAndColon CDecl Alias "winIsDriveLetterAndColon" ( _
    ByVal zPathname As Const ZString Ptr _
) As SQLITE_C_INT
    If zPathname = 0 OrElse sqlite3Strlen30(zPathname) < 2 Then Return 0
    Dim pathBytes As Const UByte Ptr = CPtr(Const UByte Ptr, zPathname)
    If (sqlite3CtypeMap(pathBytes[0]) And SQLITE_CTYPE_ALPHA_MASK) = 0 Then Return 0
    Return CInt(pathBytes[1] = Asc(":"))
End Function

Private Function winIsVerbatimPathname CDecl Alias "winIsVerbatimPathname" ( _
    ByVal zPathname As Const ZString Ptr _
) As SQLITE_C_INT
    If zPathname = 0 Then Return 0
    Dim firstByte As UByte = CPtr(Const UByte Ptr, zPathname)[0]
    If firstByte = Asc("/") OrElse firstByte = WIN_PATH_SEPARATOR Then Return 1
    Return winIsDriveLetterAndColon(zPathname)
End Function

#ifdef SQLITE3_FB_CYGWIN
' Cygwin's POSIX file-type bits occupy the upper mode_t nibble.
Private Const WIN_CYGWIN_STAT_TYPE_MASK As SQLITE_C_UINT = &HF000
Private Const WIN_CYGWIN_STAT_TYPE_SYMLINK As SQLITE_C_UINT = &HA000
' Values from sys/cygwin.h: POSIX-to-wide-Windows conversion and relative paths.
Private Const WIN_CYGWIN_POSIX_TO_WIN_W As SQLITE_C_UINT = 1
Private Const WIN_CYGWIN_RELATIVE As SQLITE_C_UINT = &H100
Private Const WIN_CYGWIN_MAX_SYMLINKS As SQLITE_C_INT = 100

Private Function winCygwinIsDirSep(ByVal value As UByte) As SQLITE_C_INT
    Return CInt(value = Asc("/") OrElse value = Asc("\"))
End Function

Private Sub winSimplifyName CDecl Alias "winSimplifyName" ( _
    ByVal zName As ZString Ptr _
)
    If zName = 0 Then Exit Sub
    Dim pathBytes As UByte Ptr = CPtr(UByte Ptr, zName)
    Dim sourceIndex As SQLITE_C_INT = 0
    Dim destinationIndex As SQLITE_C_INT = 0
    Dim usePosixSeparators As SQLITE_C_INT = _
        CInt(winSystemCallCurrent(53) <> 0)

    While pathBytes[sourceIndex] <> 0
        If winCygwinIsDirSep(pathBytes[sourceIndex]) <> 0 Then
#ifndef SQLITE_TEST
            ' Keep Cygwin's ./ distinction in test builds, as upstream does.
            If pathBytes[sourceIndex + 1] = Asc(".") AndAlso _
               winCygwinIsDirSep(pathBytes[sourceIndex + 2]) <> 0 Then
                sourceIndex += 2
                Continue While
            End If
#endif
            If pathBytes[sourceIndex + 1] = 0 OrElse _
               (winCygwinIsDirSep(pathBytes[sourceIndex + 1]) <> 0 AndAlso _
                sourceIndex <> 0) Then
                sourceIndex += 1
                Continue While
            End If
            If usePosixSeparators <> 0 Then
                pathBytes[destinationIndex] = Asc("/")
            Else
                pathBytes[destinationIndex] = Asc("\")
            End If
            destinationIndex += 1
        Else
            pathBytes[destinationIndex] = pathBytes[sourceIndex]
            destinationIndex += 1
        End If
        sourceIndex += 1
    Wend

    While destinationIndex < sourceIndex
        pathBytes[destinationIndex] = 0
        destinationIndex += 1
    Wend
End Sub

Private Function mkFullPathname CDecl Alias "mkFullPathname" ( _
    ByVal zPath As Const ZString Ptr, _
    ByVal zOutput As ZString Ptr, _
    ByVal outputBytes As SQLITE_C_INT _
) As SQLITE_C_INT
    If zPath = 0 OrElse zOutput = 0 OrElse outputBytes <= 0 Then _
        Return SQLITE_MISUSE
    zOutput[0] = 0

    Dim pathBytes As SQLITE_C_INT = sqlite3Strlen30(zPath)
    Dim outputOffset As SQLITE_C_INT = 0
    If CPtr(Const UByte Ptr, zPath)[0] <> Asc("/") Then
        If outputBytes < 3 OrElse winSystemCallCurrent(54) = 0 Then _
            Return SQLITE_CANTOPEN_FULLPATH
        If winCygwinGetcwd(zOutput, CULngInt(outputBytes - 2)) = 0 Then
            Dim systemError As SQLITE_C_INT = 0
            If winSystemCallCurrent(57) <> 0 Then
                Dim pErrno As SQLITE_C_INT Ptr = winCygwinErrno()
                If pErrno <> 0 Then systemError = pErrno[0]
            End If
            Return winLogErrorAtLine( _
                sqlite3CantopenError(4802), CUInt(systemError), _
                StrPtr("getcwd"), zPath, 4802)
        End If
        outputOffset = sqlite3Strlen30(zOutput)
        If outputOffset >= outputBytes - 1 Then _
            Return sqlite3CantopenError(4811)
        CPtr(UByte Ptr, zOutput)[outputOffset] = Asc("/")
        outputOffset += 1
    End If

    If CLngInt(outputOffset) + CLngInt(pathBytes) + 1 > outputBytes Then
        zOutput[outputOffset] = 0
        Return sqlite3CantopenError(4811)
    End If
    sqlite3_snprintf( _
        outputBytes - outputOffset, _
        CPtr(ZString Ptr, CPtr(UByte Ptr, zOutput) + outputOffset), _
        StrPtr("%s"), zPath)
    Return SQLITE_OK
End Function
#endif

Private Function winMakeEndInDirSep CDecl Alias "winMakeEndInDirSep" ( _
    ByVal bufferCapacity As SQLITE_C_INT, _
    ByVal zBuffer As ZString Ptr _
) As SQLITE_C_INT
    If zBuffer = 0 OrElse bufferCapacity <= 0 Then Return 0
    Dim nLength As SQLITE_C_INT = sqlite3Strlen30(zBuffer)
    If nLength = 0 Then Return 0
    Dim pathBytes As UByte Ptr = CPtr(UByte Ptr, zBuffer)
        If pathBytes[nLength - 1] = Asc("/") OrElse _
           pathBytes[nLength - 1] = WIN_PATH_SEPARATOR Then Return 1
        If nLength + 1 >= bufferCapacity Then Return 0

#ifdef SQLITE3_FB_CYGWIN
        If winSystemCallCurrent(53) <> 0 Then
            If winIsDriveLetterAndColon(zBuffer) <> 0 AndAlso _
               winCygwinIsDirSep(pathBytes[2]) <> 0 Then
                pathBytes[nLength] = Asc("\")
                pathBytes[2] = Asc("\")
            Else
                pathBytes[nLength] = Asc("/")
            End If
        Else
            pathBytes[nLength] = WIN_PATH_SEPARATOR
        End If
#else
        pathBytes[nLength] = WIN_PATH_SEPARATOR
#endif
        pathBytes[nLength + 1] = 0
        Return 1
End Function

Private Function winIsUNCPath CDecl Alias "winIsUNCPath" ( _
    ByVal zFile As Const ZString Ptr _
) As SQLITE_C_INT
    If zFile = 0 Then Return 0

    Dim pathBytes As Const UByte Ptr = CPtr(Const UByte Ptr, zFile)
    Dim pathLength As SQLITE_C_INT = sqlite3Strlen30(zFile)
    If pathBytes[0] = Asc("\") AndAlso pathBytes[1] = Asc("\") Then
        If pathLength >= 7 AndAlso pathBytes[2] = Asc("?") AndAlso _
           pathBytes[3] = Asc("\") AndAlso _
           (sqlite3CtypeMap(pathBytes[4]) And &H02) <> 0 AndAlso _
           pathBytes[5] = Asc(":") AndAlso _
           (pathBytes[6] = Asc("/") OrElse pathBytes[6] = Asc("\")) Then
            Return winTestUncLocking()
        End If
        Return 1
    End If
    Return winTestUncLocking()
End Function

Private Function winTempDirDefined CDecl Alias "winTempDirDefined" () As SQLITE_C_INT
    sqlite3_mutex_enter(sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_TEMPDIR))
    If sqlite3_temp_directory <> 0 Then
        ' A true result keeps this mutex held while the caller reads the path.
        Return 1
    End If
    sqlite3_mutex_leave(sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_TEMPDIR))
    Return 0
End Function

Private Function winGetTempname CDecl Alias "winGetTempname" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal pOutput As ZString Ptr Ptr _
) As SQLITE_C_INT
    If pVfs = 0 OrElse pOutput = 0 Then Return SQLITE_MISUSE
    pOutput[0] = 0
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then Return SQLITE_IOERR
#endif

    Dim maximumBytes As SQLITE_C_INT = pVfs->mxPathname
    Dim prefixBytes As SQLITE_C_INT = Len(SQLITE_TEMP_FILE_PREFIX)
    If maximumBytes <= 0 OrElse _
       prefixBytes > maximumBytes - 16 Then Return SQLITE_ERROR

    Dim bufferBytes As SQLITE_C_INT = maximumBytes + 2
    Dim directoryCapacity As SQLITE_C_INT = _
        maximumBytes - (prefixBytes + 15)
    If directoryCapacity <= 0 Then Return SQLITE_ERROR

    Dim zBuffer As ZString Ptr = CPtr( _
        ZString Ptr, sqlite3MallocZero(CULngInt(bufferBytes)))
    If zBuffer = 0 Then Return SQLITE_IOERR_NOMEM

    If winTempDirDefined() <> 0 Then
        Dim directoryLength As SQLITE_C_INT = _
            sqlite3Strlen30(sqlite3_temp_directory)
        Dim requiredDirectoryBytes As SQLITE_C_INT = directoryLength
        If directoryLength > 0 Then
            Dim directory As Const UByte Ptr = _
                CPtr(Const UByte Ptr, sqlite3_temp_directory)
            If directory[directoryLength - 1] <> Asc("/") AndAlso _
               directory[directoryLength - 1] <> WIN_PATH_SEPARATOR Then
                requiredDirectoryBytes += 1
            End If
        End If
        If requiredDirectoryBytes > directoryCapacity Then
            sqlite3_mutex_leave(sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_TEMPDIR))
            sqlite3_free(zBuffer)
            Return winLogErrorAtLine( _
                SQLITE_ERROR, 0, StrPtr(!"winGetTempname1"), 0, 4196)
        End If
        If directoryLength > 0 Then
            sqlite3_snprintf( _
                maximumBytes, zBuffer, StrPtr(!"%s"), sqlite3_temp_directory)
        End If
        sqlite3_mutex_leave(sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_TEMPDIR))
#ifdef SQLITE3_FB_CYGWIN
    ElseIf winSystemCallCurrent(53) <> 0 Then
        Dim tempDirectories(0 To 9) As Const ZString Ptr
        tempDirectories(0) = winCygwinGetenv(StrPtr("SQLITE_TMPDIR"))
        tempDirectories(1) = winCygwinGetenv(StrPtr("TMPDIR"))
        tempDirectories(2) = winCygwinGetenv(StrPtr("TMP"))
        tempDirectories(3) = winCygwinGetenv(StrPtr("TEMP"))
        tempDirectories(4) = winCygwinGetenv(StrPtr("USERPROFILE"))
        tempDirectories(5) = StrPtr("/var/tmp")
        tempDirectories(6) = StrPtr("/usr/tmp")
        tempDirectories(7) = StrPtr("/tmp")
        tempDirectories(8) = StrPtr(".")

        For directoryIndex As SQLITE_C_INT = 0 To 8
            Dim zDirectory As Const ZString Ptr = _
                tempDirectories(directoryIndex)
            If zDirectory = 0 Then Continue For

            Dim zConvertedDirectory As UShort Ptr = _
                winConvertFromUtf8Filename(zDirectory)
            If zConvertedDirectory = 0 Then
                sqlite3_free(zBuffer)
                Return SQLITE_IOERR_NOMEM
            End If
            If winIsDir(zConvertedDirectory) <> 0 Then
                sqlite3_snprintf( _
                    maximumBytes, zBuffer, StrPtr(!"%s"), zDirectory)
                sqlite3_free(zConvertedDirectory)
                Exit For
            End If
            sqlite3_free(zConvertedDirectory)
        Next
#endif
    Else
        Dim widePathBytes As sqlite3_uint64 = _
            CULngInt(maximumBytes) * CULngInt(SizeOf(UShort))
        Dim zWidePath As UShort Ptr = CPtr( _
            UShort Ptr, sqlite3MallocZero(widePathBytes))
        If zWidePath = 0 Then
            sqlite3_free(zBuffer)
            Return SQLITE_IOERR_NOMEM
        End If

        Dim widePathLength As SQLITE_C_UINT = winGetTempPathW( _
            CUInt(maximumBytes), zWidePath)
        If widePathLength = 0 OrElse widePathLength >= CUInt(maximumBytes) Then
            Dim lastError As SQLITE_C_UINT = winGetLastErrorCode()
            sqlite3_free(zWidePath)
            sqlite3_free(zBuffer)
            Return winLogErrorAtLine( _
                SQLITE_IOERR_GETTEMPPATH, lastError, _
                StrPtr(!"winGetTempname2"), 0, 4233)
        End If

        Dim zUtf8Path As ZString Ptr = winUnicodeToUtf8(zWidePath)
        sqlite3_free(zWidePath)
        If zUtf8Path = 0 Then
            sqlite3_free(zBuffer)
            Return SQLITE_IOERR_NOMEM
        End If
        sqlite3_snprintf( _
            maximumBytes, zBuffer, StrPtr(!"%s"), zUtf8Path)
        sqlite3_free(zUtf8Path)
    End If

    If winMakeEndInDirSep(directoryCapacity + 1, zBuffer) = 0 Then
        sqlite3_free(zBuffer)
        Return winLogErrorAtLine( _
            SQLITE_ERROR, 0, StrPtr(!"winGetTempname4"), 0, 4249)
    End If

    Dim nameLength As SQLITE_C_INT = sqlite3Strlen30(zBuffer)
    If nameLength > bufferBytes - prefixBytes - 17 Then
        sqlite3_free(zBuffer)
        Return winLogErrorAtLine( _
            SQLITE_ERROR, 0, StrPtr(!"winGetTempname5"), 0, 4263)
    End If

    Dim zNameTail As ZString Ptr = _
        CPtr(ZString Ptr, CPtr(UByte Ptr, zBuffer) + nameLength)
    Dim tailCapacity As SQLITE_C_INT = _
        CInt(bufferBytes - 16 - nameLength)
    sqlite3_snprintf( _
        tailCapacity, zNameTail, StrPtr(!"%s"), StrPtr(SQLITE_TEMP_FILE_PREFIX))

    Dim randomPosition As SQLITE_C_INT = sqlite3Strlen30(zBuffer)
    Dim randomBytes As UByte Ptr = _
        CPtr(UByte Ptr, zBuffer) + randomPosition
    sqlite3_randomness(15, randomBytes)
    Dim processId As SQLITE_C_UINT = winGetCurrentProcessId()
    Dim zCharacters As Const ZString Ptr = StrPtr( _
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    Const WIN_TEMP_NAME_ALPHABET_SIZE As SQLITE_C_UINT = 62
    For index As SQLITE_C_INT = 0 To 14
        Dim byteValue As SQLITE_C_UINT = _
            (CUInt(randomBytes[index]) + (processId And &HFF)) And &HFF
        processId = processId Shr 8
        randomBytes[index] = CUInt(zCharacters[byteValue Mod _
                                               WIN_TEMP_NAME_ALPHABET_SIZE])
    Next
    randomBytes[15] = 0
    randomBytes[16] = 0
    pOutput[0] = zBuffer
    Return SQLITE_OK
End Function

Private Function winAccess CDecl Alias "winAccess" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal zFilename As Const ZString Ptr, _
    ByVal requestedFlags As SQLITE_C_INT, _
    ByVal pResult As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pResult = 0 Then Return SQLITE_MISUSE

    Dim flags As SQLITE_C_INT = requestedFlags
    Dim noRetry As SQLITE_C_INT = 0
    If (flags And WIN_ACCESS_NORETRY) <> 0 Then
        noRetry = 1
        flags = flags And Not WIN_ACCESS_NORETRY
    End If
#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then Return SQLITE_IOERR_ACCESS
#endif

    If zFilename = 0 Then
        pResult[0] = 0
        Return SQLITE_OK
    End If

    Dim zConverted As UShort Ptr = winConvertFromUtf8Filename(zFilename)
    If zConverted = 0 Then Return SQLITE_IOERR_NOMEM

    Dim attributes As WIN32_FILE_ATTRIBUTE_DATA
    winMemset(@attributes, 0, SizeOf(attributes))
    Dim retryCount As SQLITE_C_INT = 0
    Dim lastError As SQLITE_C_UINT = 0
    Dim querySucceeded As SQLITE_C_INT = 0

    Do
        If winGetFileAttributesExW( _
            zConverted, WIN_GET_FILEEX_INFO_STANDARD, @attributes) <> 0 Then
            querySucceeded = 1
            Exit Do
        End If
        If noRetry <> 0 Then
            lastError = winGetLastErrorCode()
            Exit Do
        End If
        If winRetryIoerr(@retryCount, @lastError) = 0 Then Exit Do
    Loop

    Dim fileAttributes As SQLITE_C_UINT = WIN_INVALID_FILE_ATTRIBUTES
    If querySucceeded <> 0 Then
        If flags = SQLITE_ACCESS_EXISTS AndAlso _
           attributes.nFileSizeHigh = 0 AndAlso _
           attributes.nFileSizeLow = 0 Then
            fileAttributes = WIN_INVALID_FILE_ATTRIBUTES
        Else
            fileAttributes = attributes.dwFileAttributes
        End If
    Else
        If lastError = 0 Then lastError = winGetLastErrorCode()
        winLogIoerr(retryCount, 4674)
        If lastError <> WIN_ERROR_FILE_NOT_FOUND AndAlso _
           lastError <> WIN_ERROR_PATH_NOT_FOUND Then
            sqlite3_free(zConverted)
            Return winLogErrorAtLine( _
                SQLITE_IOERR_ACCESS, lastError, StrPtr(!"winAccess"), _
                zFilename, 4677)
        End If
    End If
    sqlite3_free(zConverted)

    Select Case flags
    Case SQLITE_ACCESS_READ, SQLITE_ACCESS_EXISTS
        pResult[0] = CInt(fileAttributes <> WIN_INVALID_FILE_ATTRIBUTES)
    Case SQLITE_ACCESS_READWRITE
        pResult[0] = CInt( _
            fileAttributes <> WIN_INVALID_FILE_ATTRIBUTES AndAlso _
            (fileAttributes And WIN_FILE_ATTRIBUTE_READONLY) = 0)
    Case Else
        Return SQLITE_MISUSE
    End Select
    Return SQLITE_OK
End Function

Private Function winFullPathnameNoMutex CDecl Alias "winFullPathnameNoMutex" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal zRelativeArgument As Const ZString Ptr, _
    ByVal outputBytes As SQLITE_C_INT, _
    ByVal zOutput As ZString Ptr _
) As SQLITE_C_INT
    If pVfs = 0 OrElse zRelativeArgument = 0 OrElse _
       zOutput = 0 OrElse outputBytes <= 0 Then Return SQLITE_MISUSE
    zOutput[0] = 0
    Dim outputCapacity As SQLITE_C_INT = outputBytes
    If pVfs->mxPathname < outputCapacity Then _
        outputCapacity = pVfs->mxPathname
    If outputCapacity <= 0 Then Return SQLITE_CANTOPEN_FULLPATH

    Dim zRelative As Const ZString Ptr = zRelativeArgument
    Dim relativeLength As SQLITE_C_INT = sqlite3Strlen30(zRelative)
    If relativeLength > 0 AndAlso CPtr(Const UByte Ptr, zRelative)[0] = Asc("/") Then
        Dim pathAfterSlash As Const ZString Ptr = _
            CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, zRelative) + 1)
        If winIsDriveLetterAndColon(pathAfterSlash) <> 0 OrElse _
           (relativeLength >= 5 AndAlso _
            winIsLongPathPrefix(pathAfterSlash) <> 0) Then
            zRelative = pathAfterSlash
            relativeLength -= 1
        End If
    End If

#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then Return SQLITE_ERROR
#endif

#ifdef SQLITE3_FB_CYGWIN
    If outputCapacity < 3 Then Return SQLITE_CANTOPEN_FULLPATH
    If winSystemCallCurrent(54) <> 0 Then
        zOutput[outputCapacity - 1] = 0
        Dim isDriveAbsolute As SQLITE_C_INT = _
            winIsDriveLetterAndColon(zRelative)
        If isDriveAbsolute = 0 OrElse _
           winCygwinIsDirSep(CPtr(Const UByte Ptr, zRelative)[2]) = 0 Then
            Dim rc As SQLITE_C_INT = SQLITE_OK
            Dim linkCount As SQLITE_C_INT = 1
            Dim zInput As Const ZString Ptr = zRelative
            Dim zDelete As ZString Ptr = 0
            Dim statBuffer As SqliteCygwinStat

            Do
                Dim isLink As SQLITE_C_INT = 0
                If winSystemCallCurrent(56) <> 0 AndAlso _
                   winSystemCallCurrent(55) <> 0 Then
                    If winCygwinLstat(zInput, @statBuffer) <> 0 Then
                        Dim systemError As SQLITE_C_INT = 0
                        If winSystemCallCurrent(57) <> 0 Then
                            Dim pErrno As SQLITE_C_INT Ptr = winCygwinErrno()
                            If pErrno <> 0 Then systemError = pErrno[0]
                        End If
                        If systemError <> ENOENT Then
                            rc = winLogErrorAtLine( _
                                sqlite3CantopenError(4863), _
                                CUInt(systemError), StrPtr("lstat"), _
                                zInput, 4863)
                        End If
                    ElseIf (statBuffer.st_mode And _
                            WIN_CYGWIN_STAT_TYPE_MASK) = _
                           WIN_CYGWIN_STAT_TYPE_SYMLINK Then
                        isLink = 1
                    End If

                    If isLink <> 0 Then
                        If zDelete = 0 Then
                            zDelete = CPtr( _
                                ZString Ptr, sqlite3MallocZero( _
                                    CULngInt(outputCapacity)))
                            If zDelete = 0 Then rc = SQLITE_NOMEM
                        Else
                            linkCount += 1
                            If linkCount > WIN_CYGWIN_MAX_SYMLINKS Then _
                                rc = sqlite3CantopenError(4875)
                        End If

                        If rc = SQLITE_OK Then
                            Dim bytesRead As Integer = winCygwinReadlink( _
                                zInput, zDelete, CULngInt(outputCapacity - 1))
                            If bytesRead = -1 Then
                                Dim systemError As SQLITE_C_INT = 0
                                If winSystemCallCurrent(57) <> 0 Then
                                    Dim pErrno As SQLITE_C_INT Ptr = _
                                        winCygwinErrno()
                                    If pErrno <> 0 Then systemError = pErrno[0]
                                End If
                                rc = winLogErrorAtLine( _
                                    sqlite3CantopenError(4881), _
                                    CUInt(systemError), StrPtr("readlink"), _
                                    zInput, 4881)
                            Else
                                If CPtr(Const UByte Ptr, zDelete)[0] <> Asc("/") Then
                                    Dim inputBytes As Const UByte Ptr = _
                                        CPtr(Const UByte Ptr, zInput)
                                    Dim directoryBytes As SQLITE_C_INT = _
                                        sqlite3Strlen30(zInput)
                                    While directoryBytes > 0 AndAlso _
                                          inputBytes[directoryBytes - 1] <> Asc("/")
                                        directoryBytes -= 1
                                    Wend

                                    If CLngInt(bytesRead) + _
                                       CLngInt(directoryBytes) + 1 > _
                                       outputCapacity Then
                                        rc = sqlite3CantopenError(4888)
                                    Else
                                        winMemmove( _
                                            CPtr(UByte Ptr, zDelete) + directoryBytes, _
                                            zDelete, CULngInt(bytesRead) + 1)
                                        winMemcpy(zDelete, zInput, _
                                            CULngInt(directoryBytes))
                                        bytesRead += directoryBytes
                                    End If
                                End If
                                If rc = SQLITE_OK Then _
                                    CPtr(UByte Ptr, zDelete)[bytesRead] = 0
                            End If
                        End If
                        zInput = zDelete
                    End If
                End If

#ifdef SQLITE_DEBUG
                If rc = SQLITE_OK AndAlso zInput = zOutput AndAlso _
                   CPtr(Const UByte Ptr, zInput)[0] <> Asc("/") Then
                    sqlite3DebugAssert(StrPtr( _
                        "rc!=SQLITE_OK || zIn!=zFull || zIn[0]=='/'"))
                End If
#endif
                If rc = SQLITE_OK AndAlso zInput <> zOutput Then _
                    rc = mkFullPathname(zInput, zOutput, outputCapacity)
                If isLink = 0 Then Exit Do
                zInput = zOutput
            Loop While rc = SQLITE_OK

            sqlite3_free(zDelete)
            winSimplifyName(zOutput)
            Return rc
        End If
    End If
#endif

#ifdef SQLITE_TEST
    If fbTestSimulateIoError() <> 0 Then Return SQLITE_ERROR
#endif

    If sqlite3_data_directory <> 0 AndAlso _
       winIsVerbatimPathname(zRelative) = 0 Then
        Dim directoryBytes As SQLITE_C_INT = _
            sqlite3Strlen30(sqlite3_data_directory)
        If directoryBytes > outputCapacity - relativeLength - 2 Then _
            Return SQLITE_CANTOPEN_FULLPATH
        sqlite3_snprintf( _
            outputCapacity, zOutput, StrPtr(!"%s%c%s"), _
            sqlite3_data_directory, WIN_PATH_SEPARATOR, zRelative)
        Return SQLITE_OK
    End If

    Dim zConverted As UShort Ptr = winConvertFromUtf8Filename(zRelative)
    If zConverted = 0 Then Return SQLITE_IOERR_NOMEM

    Dim requiredChars As SQLITE_C_UINT = _
        winGetFullPathNameW(zConverted, 0, 0, 0)
    If requiredChars = 0 Then
        Dim lastError As SQLITE_C_UINT = winGetLastErrorCode()
        sqlite3_free(zConverted)
        Return winLogErrorAtLine( _
            SQLITE_CANTOPEN_FULLPATH, lastError, _
            StrPtr(!"winFullPathname1"), zRelative, 4938)
    End If
    If requiredChars > &H7FFFFFFC Then
        sqlite3_free(zConverted)
        Return SQLITE_CANTOPEN_FULLPATH
    End If

    Dim wideCapacity As SQLITE_C_UINT = requiredChars + 3
    Dim wideBytes As sqlite3_uint64 = _
        CULngInt(wideCapacity) * CULngInt(SizeOf(UShort))
    Dim zWideOutput As UShort Ptr = CPtr( _
        UShort Ptr, sqlite3MallocZero(wideBytes))
    If zWideOutput = 0 Then
        sqlite3_free(zConverted)
        Return SQLITE_IOERR_NOMEM
    End If

    Dim writtenChars As SQLITE_C_UINT = winGetFullPathNameW( _
        zConverted, wideCapacity, zWideOutput, 0)
    If writtenChars = 0 OrElse writtenChars >= wideCapacity Then
        Dim lastError As SQLITE_C_UINT = winGetLastErrorCode()
        sqlite3_free(zConverted)
        sqlite3_free(zWideOutput)
        Return winLogErrorAtLine( _
            SQLITE_CANTOPEN_FULLPATH, lastError, _
            StrPtr(!"winFullPathname2"), zRelative, 4955)
    End If

    sqlite3_free(zConverted)
    Dim zUtf8Output As ZString Ptr = winUnicodeToUtf8(zWideOutput)
    sqlite3_free(zWideOutput)
    If zUtf8Output = 0 Then Return SQLITE_IOERR_NOMEM

    sqlite3_snprintf( _
        outputCapacity, zOutput, StrPtr(!"%s"), zUtf8Output)
    sqlite3_free(zUtf8Output)
    Return SQLITE_OK
End Function

Private Function winFullPathname CDecl Alias "winFullPathname" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal zRelative As Const ZString Ptr, _
    ByVal outputBytes As SQLITE_C_INT, _
    ByVal zOutput As ZString Ptr _
) As SQLITE_C_INT
    Dim pMutex As Any Ptr = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_TEMPDIR)
    sqlite3_mutex_enter(pMutex)
    Dim rc As SQLITE_C_INT = winFullPathnameNoMutex( _
        pVfs, zRelative, outputBytes, zOutput)
    sqlite3_mutex_leave(pMutex)
    Return rc
End Function

Private Function winIsDir( _
    ByVal zFilename As Const UShort Ptr _
) As SQLITE_C_INT
    If zFilename = 0 Then Return 0

    Dim attributes As WIN32_FILE_ATTRIBUTE_DATA
    Dim retryCount As SQLITE_C_INT = 0
    Dim lastError As SQLITE_C_UINT = 0
    Dim result As SQLITE_C_INT

    Do
        result = winGetFileAttributesExW( _
            zFilename, WIN_GET_FILEEX_INFO_STANDARD, @attributes)
        If result <> 0 Then Exit Do
        If winRetryIoerr(@retryCount, @lastError) = 0 Then Return 0
    Loop

    Return CInt((attributes.dwFileAttributes And _
                 WIN_FILE_ATTRIBUTE_DIRECTORY) <> 0)
End Function

Private Function winOpen CDecl Alias "winOpen" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal pFileArgument As sqlite3_file Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal pOutputFlags As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
    If pVfs = 0 OrElse pFileArgument = 0 Then Return SQLITE_MISUSE

    Dim pFile As winFile Ptr = CPtr(winFile Ptr, pFileArgument)
    winMemset(pFile, 0, SizeOf(winFile))
    pFile->h = CPtr(Any Ptr, -1)

    Dim fileType As SQLITE_C_INT = flags And &H0FFF00
    Dim isExclusive As SQLITE_C_INT = CInt((flags And SQLITE_OPEN_EXCLUSIVE) <> 0)
    Dim isDelete As SQLITE_C_INT = CInt((flags And SQLITE_OPEN_DELETEONCLOSE) <> 0)
    Dim isCreate As SQLITE_C_INT = CInt((flags And SQLITE_OPEN_CREATE) <> 0)
    Dim isReadonly As SQLITE_C_INT = CInt((flags And SQLITE_OPEN_READONLY) <> 0)
    Dim isReadWrite As SQLITE_C_INT = CInt((flags And SQLITE_OPEN_READWRITE) <> 0)
    Dim isOpenJournal As SQLITE_C_INT = CInt( _
        isCreate <> 0 AndAlso _
        (fileType = SQLITE_OPEN_SUPER_JOURNAL OrElse _
         fileType = SQLITE_OPEN_MAIN_JOURNAL OrElse _
         fileType = SQLITE_OPEN_WAL))

    If (isReadonly = isReadWrite) OrElse _
       (isCreate <> 0 AndAlso isReadWrite = 0) OrElse _
       (isExclusive <> 0 AndAlso isCreate = 0) OrElse _
       (isDelete <> 0 AndAlso isCreate = 0) Then Return SQLITE_MISUSE
    Select Case fileType
    Case SQLITE_OPEN_MAIN_DB, SQLITE_OPEN_TEMP_DB, _
         SQLITE_OPEN_TRANSIENT_DB, SQLITE_OPEN_MAIN_JOURNAL, _
         SQLITE_OPEN_TEMP_JOURNAL, SQLITE_OPEN_SUBJOURNAL, _
         SQLITE_OPEN_SUPER_JOURNAL, SQLITE_OPEN_WAL
        ' These are the file classes accepted by the Windows VFS.
    Case Else
        Return SQLITE_MISUSE
    End Select
    If zName = 0 AndAlso (isDelete = 0 OrElse isOpenJournal <> 0) Then _
        Return SQLITE_MISUSE
    If isDelete <> 0 AndAlso _
       (fileType = SQLITE_OPEN_MAIN_DB OrElse _
        fileType = SQLITE_OPEN_MAIN_JOURNAL OrElse _
        fileType = SQLITE_OPEN_SUPER_JOURNAL OrElse _
        fileType = SQLITE_OPEN_WAL) Then Return SQLITE_MISUSE

    Dim zTemporaryName As ZString Ptr = 0
    Dim zUtf8Name As Const ZString Ptr = zName
    If zUtf8Name = 0 Then
        Dim tempNameRc As SQLITE_C_INT = _
            winGetTempname(pVfs, @zTemporaryName)
        If tempNameRc <> SQLITE_OK Then Return tempNameRc
        zUtf8Name = zTemporaryName
    End If

    Dim zConverted As UShort Ptr = winConvertFromUtf8Filename(zUtf8Name)
    If zConverted = 0 Then
        If zTemporaryName <> 0 Then sqlite3_free(zTemporaryName)
        Return SQLITE_IOERR_NOMEM
    End If
    If winIsDir(zConverted) <> 0 Then
        sqlite3_free(zConverted)
        If zTemporaryName <> 0 Then sqlite3_free(zTemporaryName)
        Return SQLITE_CANTOPEN_ISDIR
    End If

    Dim desiredAccess As SQLITE_C_UINT = WIN_GENERIC_READ
    If isReadWrite <> 0 Then desiredAccess = _
        desiredAccess Or WIN_GENERIC_WRITE
    Dim creationDisposition As SQLITE_C_UINT
    If isExclusive <> 0 Then
        creationDisposition = WIN_CREATE_NEW
    ElseIf isCreate <> 0 Then
        creationDisposition = WIN_OPEN_ALWAYS
    Else
        creationDisposition = WIN_OPEN_EXISTING
    End If

    Dim shareMode As SQLITE_C_UINT = 0
    If sqlite3_uri_boolean(zName, StrPtr(!"exclusive"), 0) = 0 Then _
        shareMode = WIN_FILE_SHARE_READ Or WIN_FILE_SHARE_WRITE
    Dim flagsAndAttributes As SQLITE_C_UINT = WIN_FILE_ATTRIBUTE_NORMAL
    If isDelete <> 0 Then
        flagsAndAttributes = WIN_FILE_ATTRIBUTE_TEMPORARY Or _
                             WIN_FILE_ATTRIBUTE_HIDDEN Or _
                             WIN_FILE_FLAG_DELETE_ON_CLOSE
    End If

    Dim handle As Any Ptr = CPtr(Any Ptr, -1)
    Dim retryCount As SQLITE_C_INT = 0
    Dim lastError As SQLITE_C_UINT = 0
    Dim isKnownReadonly As SQLITE_C_INT = 0
    Do
        handle = winCreateFileW( _
            zConverted, desiredAccess, shareMode, 0, _
            creationDisposition, flagsAndAttributes, 0)
        If handle <> CPtr(Any Ptr, -1) Then Exit Do

        If isReadWrite <> 0 Then
            Dim accessResult As SQLITE_C_INT
            sqlite3BeginBenignMalloc()
            accessResult = winAccess( _
                pVfs, zUtf8Name, SQLITE_ACCESS_READ Or WIN_ACCESS_NORETRY, _
                @isKnownReadonly)
            sqlite3EndBenignMalloc()
            If accessResult = SQLITE_OK AndAlso isKnownReadonly <> 0 Then _
                Exit Do
        End If
        If winRetryIoerr(@retryCount, @lastError) = 0 Then Exit Do
    Loop
    winLogIoerr(retryCount, 4479)

    If handle = CPtr(Any Ptr, -1) Then
        sqlite3_free(zConverted)
        If zTemporaryName <> 0 Then sqlite3_free(zTemporaryName)
        If isReadWrite <> 0 AndAlso isKnownReadonly <> 0 AndAlso _
           isExclusive = 0 Then
            Dim readonlyFlags As SQLITE_C_INT = _
                (flags Or SQLITE_OPEN_READONLY) And _
                Not (SQLITE_OPEN_CREATE Or SQLITE_OPEN_READWRITE)
            Return winOpen( _
                pVfs, zName, pFileArgument, readonlyFlags, pOutputFlags)
        End If

        pFile->lastErrno = lastError
        Return winLogErrorAtLine( _
            SQLITE_CANTOPEN, lastError, StrPtr(!"winOpen"), _
            zUtf8Name, 4495)
    End If

    If pOutputFlags <> 0 Then
        If isReadWrite <> 0 Then
            pOutputFlags[0] = SQLITE_OPEN_READWRITE
        Else
            pOutputFlags[0] = SQLITE_OPEN_READONLY
        End If
    End If

    Dim pAppData As winVfsAppData Ptr = _
        CPtr(winVfsAppData Ptr, pVfs->pAppData)
    If pAppData <> 0 AndAlso pAppData->pMethod <> 0 Then
        pFile->pMethod = pAppData->pMethod
    Else
        pFile->pMethod = @winIoMethods
    End If
    pFile->pVfs = pVfs
    pFile->h = handle
    If isReadonly <> 0 Then pFile->ctrlFlags = pFile->ctrlFlags Or WINFILE_RDONLY
    If (flags And SQLITE_OPEN_MAIN_DB) <> 0 AndAlso _
       sqlite3_uri_boolean( _
           zName, StrPtr(!"psow"), SQLITE_POWERSAFE_OVERWRITE) <> 0 Then
        pFile->ctrlFlags = pFile->ctrlFlags Or WINFILE_PSOW
    End If
    pFile->lastErrno = 0
    pFile->zPath = CPtr(ZString Ptr, zName)
#if SQLITE_MAX_MMAP_SIZE > 0
    pFile->hMap = 0
    pFile->pMapRegion = 0
    pFile->mmapSize = 0
    pFile->mmapSizeMax = sqlite3ConfigMmapSizeDefault()
#endif

#ifdef SQLITE_TEST
    sqlite3_open_file_count += 1
#endif
    sqlite3_free(zConverted)
    If zTemporaryName <> 0 Then sqlite3_free(zTemporaryName)
    Return SQLITE_OK
End Function

Private Function winFileControl CDecl Alias "winFileControl" ( _
    ByVal pFileArgument As sqlite3_file Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT
    If pFileArgument = 0 Then Return SQLITE_MISUSE
    Dim pFile As winFile Ptr = CPtr(winFile Ptr, pFileArgument)
    If (pFile->h = 0 OrElse pFile->h = CPtr(Any Ptr, -1)) AndAlso _
       operation <> SQLITE_FCNTL_NULL_IO Then _
        Return SQLITE_MISUSE

    Select Case operation
    Case SQLITE_FCNTL_LOCKSTATE
        If pArgument = 0 Then Return SQLITE_MISUSE
        CPtr(SQLITE_C_INT Ptr, pArgument)[0] = pFile->locktype
        Return SQLITE_OK

    Case SQLITE_FCNTL_LAST_ERRNO
        If pArgument = 0 Then Return SQLITE_MISUSE
        CPtr(SQLITE_C_INT Ptr, pArgument)[0] = CInt(pFile->lastErrno)
        Return SQLITE_OK

    Case SQLITE_FCNTL_CHUNK_SIZE
        If pArgument = 0 Then Return SQLITE_MISUSE
        pFile->szChunk = CPtr(SQLITE_C_INT Ptr, pArgument)[0]
        Return SQLITE_OK

    Case SQLITE_FCNTL_SIZE_HINT
        If pArgument = 0 Then Return SQLITE_MISUSE
        If pFile->szChunk <= 0 Then Return SQLITE_OK
        Dim oldSize As sqlite3_int64 = 0
        Dim rc As SQLITE_C_INT = winFileSize( _
            CPtr(sqlite3_file Ptr, pFile), @oldSize)
        If rc <> SQLITE_OK Then Return rc
        Dim newSize As sqlite3_int64 = _
            CPtr(sqlite3_int64 Ptr, pArgument)[0]
        If newSize <= oldSize Then Return SQLITE_OK
#ifdef SQLITE_TEST
        fbTestSetIoErrorBenign(1)
#endif
        rc = winTruncate(CPtr(sqlite3_file Ptr, pFile), newSize)
#ifdef SQLITE_TEST
        fbTestSetIoErrorBenign(0)
#endif
        Return rc

    Case SQLITE_FCNTL_PERSIST_WAL
        If pArgument = 0 Then Return SQLITE_MISUSE
        winModeBit(pFile, WINFILE_PERSIST_WAL, _
                   CPtr(SQLITE_C_INT Ptr, pArgument))
        Return SQLITE_OK

    Case SQLITE_FCNTL_POWERSAFE_OVERWRITE
        If pArgument = 0 Then Return SQLITE_MISUSE
        winModeBit(pFile, WINFILE_PSOW, CPtr(SQLITE_C_INT Ptr, pArgument))
        Return SQLITE_OK

    Case SQLITE_FCNTL_VFSNAME
        If pArgument = 0 Then Return SQLITE_MISUSE
        Dim zVfsName As Const ZString Ptr = StrPtr(!"")
        If pFile->pVfs <> 0 AndAlso pFile->pVfs->zName <> 0 Then _
            zVfsName = pFile->pVfs->zName
        CPtr(ZString Ptr Ptr, pArgument)[0] = _
            sqlite3_mprintf(StrPtr(!"%s"), zVfsName)
        Return SQLITE_OK

    Case SQLITE_FCNTL_WIN32_AV_RETRY
        If pArgument = 0 Then Return SQLITE_MISUSE
        Dim retryValues As SQLITE_C_INT Ptr = _
            CPtr(SQLITE_C_INT Ptr, pArgument)
        If retryValues[0] > 0 Then
            winIoerrRetry = retryValues[0]
        Else
            retryValues[0] = winIoerrRetry
        End If
        If retryValues[1] > 0 Then
            winIoerrRetryDelay = retryValues[1]
        Else
            retryValues[1] = winIoerrRetryDelay
        End If
        Return SQLITE_OK

    Case SQLITE_FCNTL_WIN32_GET_HANDLE
        If pArgument = 0 Then Return SQLITE_MISUSE
        CPtr(Any Ptr Ptr, pArgument)[0] = pFile->h
        Return SQLITE_OK

#ifdef SQLITE_TEST
    Case SQLITE_FCNTL_WIN32_SET_HANDLE
        If pArgument = 0 Then Return SQLITE_MISUSE
        Dim pHandle As Any Ptr Ptr = CPtr(Any Ptr Ptr, pArgument)
        Dim oldHandle As Any Ptr = pFile->h
        pFile->h = pHandle[0]
        pHandle[0] = oldHandle
        Return SQLITE_OK
#endif

    Case SQLITE_FCNTL_NULL_IO
        If pFile->h <> 0 AndAlso pFile->h <> CPtr(Any Ptr, -1) Then _
            winCloseHandle(pFile->h)
        pFile->h = 0
        Return SQLITE_OK

    Case SQLITE_FCNTL_TEMPFILENAME
        If pArgument = 0 Then Return SQLITE_MISUSE
        Dim zTempFilename As ZString Ptr = 0
        Dim rc As SQLITE_C_INT = winGetTempname(pFile->pVfs, @zTempFilename)
        If rc = SQLITE_OK Then _
            CPtr(ZString Ptr Ptr, pArgument)[0] = zTempFilename
        Return rc

#if SQLITE_MAX_MMAP_SIZE > 0
    Case SQLITE_FCNTL_MMAP_SIZE
        If pArgument = 0 Then Return SQLITE_MISUSE
        Dim pSize As sqlite3_int64 Ptr = CPtr(sqlite3_int64 Ptr, pArgument)
        Dim newLimit As sqlite3_int64 = pSize[0]
        Dim maxLimit As sqlite3_int64 = sqlite3ConfigMmapSizeMaximum()
        If newLimit > maxLimit Then newLimit = maxLimit
        If newLimit > 0 AndAlso SizeOf(SQLITE_SIZE_T) < 8 Then _
            newLimit = newLimit And &H7FFFFFFF

        pSize[0] = pFile->mmapSizeMax
        If newLimit >= 0 AndAlso newLimit <> pFile->mmapSizeMax AndAlso _
           pFile->nFetchOut = 0 Then
            pFile->mmapSizeMax = newLimit
            If pFile->mmapSize > 0 Then
                winUnmapfile(pFile)
                Return winMapfile(pFile, -1)
            End If
        End If
        Return SQLITE_OK
#endif

#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    Case SQLITE_FCNTL_LOCK_TIMEOUT
        If pArgument = 0 Then Return SQLITE_MISUSE
        Dim timeoutArgument As SQLITE_C_INT Ptr = _
            CPtr(SQLITE_C_INT Ptr, pArgument)
        Dim oldTimeout As SQLITE_C_UINT = pFile->iBusyTimeout
#if SQLITE_ENABLE_SETLK_TIMEOUT = 1
        If timeoutArgument[0] < 0 Then
            pFile->iBusyTimeout = WIN_FILE_WAIT_INFINITE
        Else
            pFile->iBusyTimeout = CUInt(timeoutArgument[0])
        End If
#elseif SQLITE_ENABLE_SETLK_TIMEOUT = 2
        pFile->iBusyTimeout = CUInt(timeoutArgument[0] <> 0)
#else
#error "SQLITE_ENABLE_SETLK_TIMEOUT must be set to 1 or 2"
#endif
        timeoutArgument[0] = CInt(oldTimeout)
        Return SQLITE_OK

    Case SQLITE_FCNTL_BLOCK_ON_CONNECT
        If pArgument = 0 Then Return SQLITE_MISUSE
        pFile->bBlockOnConnect = CPtr(SQLITE_C_INT Ptr, pArgument)[0]
        Return SQLITE_OK
#endif

#if defined(SQLITE_DEBUG) OrElse defined(SQLITE_ENABLE_FILESTAT)
    Case SQLITE_FCNTL_FILESTAT
        If pArgument = 0 Then Return SQLITE_MISUSE
        Dim pAccum As Any Ptr = pArgument
        sqlite3_str_appendf( _
            pAccum, StrPtr(!"{\"h\":%llu"), _
            Cast(sqlite3_uint64, pFile->h))
        Dim vfsName As Const ZString Ptr = StrPtr(!"")
        If pFile->pVfs <> 0 AndAlso pFile->pVfs->zName <> 0 Then _
            vfsName = pFile->pVfs->zName
        sqlite3_str_appendf( _
            pAccum, StrPtr(!",\"vfs\":\"%s\""), vfsName)
        Select Case pFile->locktype
        Case SQLITE_LOCK_SHARED
            sqlite3_str_appendall(pAccum, StrPtr(!",\"locktype\":\"SHARED\""))
        Case SQLITE_LOCK_RESERVED
            sqlite3_str_appendall(pAccum, StrPtr(!",\"locktype\":\"RESERVED\""))
        Case SQLITE_LOCK_PENDING
            sqlite3_str_appendall(pAccum, StrPtr(!",\"locktype\":\"PENDING\""))
        Case SQLITE_LOCK_EXCLUSIVE
            sqlite3_str_appendall(pAccum, StrPtr(!",\"locktype\":\"EXCLUSIVE\""))
        End Select
#if SQLITE_MAX_MMAP_SIZE > 0
        If pFile->mmapSize <> 0 Then
            sqlite3_str_appendf( _
                pAccum, StrPtr(!",\"mmapSize\":%lld"), pFile->mmapSize)
            sqlite3_str_appendf( _
                pAccum, StrPtr(!",\"nFetchOut\":%d"), pFile->nFetchOut)
        End If
#endif
        sqlite3_str_append(pAccum, StrPtr("}"), 1)
        Return SQLITE_OK
#endif
    End Select
    Return SQLITE_NOTFOUND
End Function

/' ---------------------------------------------------------------------------
   Windows shared-memory synchronization
'/ 

Private Function winShmMutexHeld CDecl Alias "winShmMutexHeld" () As SQLITE_C_INT
    Dim pMutex As Any Ptr = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_VFS1)
    If pMutex = 0 Then Return 0
    Return sqlite3_mutex_held(pMutex)
End Function

Private Sub winShmEnterMutex CDecl Alias "winShmEnterMutex" ()
    sqlite3_mutex_enter(sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_VFS1))
End Sub

Private Sub winShmLeaveMutex CDecl Alias "winShmLeaveMutex" ()
    sqlite3_mutex_leave(sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_VFS1))
End Sub

#ifndef SQLITE_OMIT_WAL
/' ---------------------------------------------------------------------------
   Shared-memory file helpers
'/ 



Private Function winZeroSharedMemory( _
    ByVal hFile As Any Ptr _
) As SQLITE_C_INT
    Dim zeroBytes(0 To WIN_SHM_INITIAL_BYTES - 1) As UByte
    For index As SQLITE_C_INT = 0 To WIN_SHM_INITIAL_BYTES - 1
        zeroBytes(index) = 0
    Next

    Dim bytesWritten As SQLITE_C_UINT = 0
    Dim overlapped As OVERLAPPED = Type<OVERLAPPED>(0, 0, 0, 0, 0)
    If winWriteFile( _
        hFile, @zeroBytes(0), WIN_SHM_INITIAL_BYTES, _
        @bytesWritten, @overlapped) = 0 Then
        If winGetLastErrorCode() <> WIN_ERROR_IO_PENDING OrElse _
           winGetOverlappedResult( _
               hFile, @overlapped, @bytesWritten, 1) = 0 Then
            bytesWritten = 0
        End If
    End If

    If bytesWritten = WIN_SHM_INITIAL_BYTES Then Return SQLITE_OK
    Return SQLITE_IOERR_WRITE
End Function

Private Function winLockSharedMemory( _
    ByVal pShmNode As winShmNode Ptr, _
    ByVal waitMilliseconds As SQLITE_C_UINT _
) As SQLITE_C_INT
    If pShmNode = 0 Then Return SQLITE_MISUSE

    Dim hFile As Any Ptr = pShmNode->hSharedShm
    Dim rc As SQLITE_C_INT = winHandleLockTimeout( _
        hFile, WIN_SHM_DMS, 1, 1, 0)

    If rc = SQLITE_OK Then
        If pShmNode->isReadonly <> 0 Then
            rc = SQLITE_READONLY_CANTINIT
        ElseIf winHandleTruncate(hFile, 0) <> SQLITE_OK Then
            ' An existing mapping can prevent truncation; SQLite falls back
            ' to clearing the DMS and header bytes in place in that case.
            rc = winZeroSharedMemory(hFile)
        End If

        Dim sharedHandle As Any Ptr = hFile
        winUnlockFile(@sharedHandle, WIN_SHM_DMS, 0, 1, 0)
    ElseIf (rc And &HFF) = SQLITE_BUSY Then
        rc = SQLITE_OK
    End If

    If rc = SQLITE_OK Then
        rc = winHandleLockTimeout( _
            hFile, WIN_SHM_DMS, 1, 0, waitMilliseconds)
        If rc = SQLITE_OK Then pShmNode->isUnlocked = 0
    End If
    Return rc
End Function

Private Function winHandleOpen( _
    ByVal zUtf8 As Const ZString Ptr, _
    ByVal pReadonly As SQLITE_C_INT Ptr, _
    ByVal pHandle As Any Ptr Ptr _
) As SQLITE_C_INT
    If zUtf8 = 0 OrElse pReadonly = 0 OrElse pHandle = 0 Then _
        Return SQLITE_MISUSE

    pHandle[0] = CPtr(Any Ptr, -1)
    Dim isReadonly As SQLITE_C_INT = CInt(pReadonly[0] <> 0)
    Dim zConverted As UShort Ptr = winConvertFromUtf8Filename(zUtf8)
    If zConverted = 0 Then Return SQLITE_IOERR_NOMEM

    If winIsDir(zConverted) <> 0 Then
        sqlite3_free(zConverted)
        pReadonly[0] = isReadonly
        Return SQLITE_CANTOPEN_ISDIR
    End If

    Dim openFlags As SQLITE_C_UINT = WIN_FILE_ATTRIBUTE_NORMAL
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    openFlags = openFlags Or WIN_FILE_FLAG_OVERLAPPED
#endif
    Dim desiredAccess As SQLITE_C_UINT = WIN_GENERIC_READ
    If isReadonly = 0 Then desiredAccess = desiredAccess Or WIN_GENERIC_WRITE
    Dim shareMode As SQLITE_C_UINT = _
        WIN_FILE_SHARE_READ Or WIN_FILE_SHARE_WRITE
    Dim hFile As Any Ptr = winCreateFileW( _
        zConverted, desiredAccess, shareMode, 0, WIN_OPEN_ALWAYS, _
        openFlags, 0)

    If hFile = CPtr(Any Ptr, -1) AndAlso isReadonly = 0 Then
        isReadonly = 1
        hFile = winCreateFileW( _
            zConverted, WIN_GENERIC_READ, shareMode, 0, WIN_OPEN_ALWAYS, _
            openFlags, 0)
    End If

    sqlite3_free(zConverted)
    pReadonly[0] = isReadonly
    pHandle[0] = hFile
    If hFile = CPtr(Any Ptr, -1) Then Return SQLITE_CANTOPEN
    Return SQLITE_OK
End Function

Private Function winIsRemoteVolume( _
    ByVal zFilename As Const ZString Ptr _
) As SQLITE_C_INT
    If zFilename = 0 Then Return 0

    Dim pathBytes As Const UByte Ptr = CPtr(Const UByte Ptr, zFilename)
    Dim pathLength As SQLITE_C_INT = sqlite3Strlen30(zFilename)
    Dim pathOffset As SQLITE_C_INT = 0
    If pathLength >= 4 AndAlso pathBytes[0] = WIN_PATH_SEPARATOR AndAlso _
       pathBytes[1] = WIN_PATH_SEPARATOR AndAlso pathBytes[2] = Asc("?") AndAlso _
       pathBytes[3] = WIN_PATH_SEPARATOR Then
        pathOffset = 4
    End If
    If pathLength - pathOffset < 3 Then Return 0

    Dim driveLetter As UByte = pathBytes[pathOffset]
    If (sqlite3CtypeMap(driveLetter) And SQLITE_CTYPE_ALPHA_MASK) = 0 Then _
        Return 0
    If pathBytes[pathOffset + 1] <> Asc(":") Then Return 0
    If pathBytes[pathOffset + 2] <> Asc("/") AndAlso _
       pathBytes[pathOffset + 2] <> WIN_PATH_SEPARATOR Then Return 0

    Dim root(0 To 3) As UShort
    root(0) = driveLetter
    root(1) = Asc(":")
    root(2) = WIN_PATH_SEPARATOR
    root(3) = 0
    Return CInt(winGetDriveTypeW(@root(0)) = WIN_DRIVE_REMOTE)
End Function

Private Function winShmLock CDecl Alias "winShmLock" (ByVal arg0 As sqlite3_file Ptr, ByVal arg1 As c2fb_c_int, ByVal arg2 As c2fb_c_int, ByVal arg3 As c2fb_c_int) As c2fb_c_int
    Dim local0 As winFile Ptr
    Dim local1 As winShm Ptr
    Dim local2 As winShmNode Ptr
    Dim local3 As c2fb_c_int
    Dim local4 As UShort
    Dim c2fb_temp_0 As winShmNode Ptr
    Dim local5 As Any Ptr
    Dim c2fb_temp_1 As Any Ptr
    Dim local6 As winShm Ptr
    Dim c2fb_temp_2 As winShm Ptr
    Dim c2fb_temp_3 As winShm Ptr
    Dim c2fb_temp_4 As Any Ptr
    Dim c2fb_temp_5 As c2fb_c_int
    Dim c2fb_temp_6 As UShort Ptr
    Dim c2fb_temp_7 As UShort
    Dim c2fb_temp_8 As UShort Ptr
    Dim c2fb_temp_9 As UShort
    Dim local7 As c2fb_c_int
    Dim local8 As ULong
    Dim local9 As winShm Ptr
    Dim c2fb_temp_10 As Any Ptr
    Dim c2fb_temp_11 As winShm Ptr
    Dim c2fb_temp_12 As winShm Ptr
    Dim c2fb_temp_13 As c2fb_c_int
    Dim c2fb_temp_14 As Any Ptr
    Dim c2fb_temp_15 As Any Ptr
    Dim c2fb_temp_16 As c2fb_c_int
    Dim c2fb_temp_17 As Any Ptr
    Dim c2fb_temp_18 As c2fb_c_int
    Dim c2fb_temp_19 As UShort Ptr
    Dim c2fb_temp_20 As UShort
    Dim c2fb_temp_21 As UShort Ptr
    Dim c2fb_temp_22 As UShort

    If arg0 = 0 Then Return SQLITE_MISUSE
    If arg1 < 0 OrElse arg2 < 1 OrElse _
       CLngInt(arg1) + CLngInt(arg2) > SQLITE_SHM_NLOCK Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr( _
            "ofst>=0 && ofst+n<=SQLITE_SHM_NLOCK && n>=1"))
#endif
        Return SQLITE_MISUSE
    End If
    If arg3 <> (SQLITE_SHM_LOCK Or SQLITE_SHM_SHARED) AndAlso _
       arg3 <> (SQLITE_SHM_LOCK Or SQLITE_SHM_EXCLUSIVE) AndAlso _
       arg3 <> (SQLITE_SHM_UNLOCK Or SQLITE_SHM_SHARED) AndAlso _
       arg3 <> (SQLITE_SHM_UNLOCK Or SQLITE_SHM_EXCLUSIVE) Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("flags is a supported shared-memory lock mode"))
#endif
        Return SQLITE_MISUSE
    End If
    If arg2 > 1 AndAlso (arg3 And SQLITE_SHM_EXCLUSIVE) = 0 Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("n==1 || (flags & SQLITE_SHM_EXCLUSIVE)!=0"))
#endif
        Return SQLITE_MISUSE
    End If

    local0 = CPtr(winFile Ptr, arg0)
    local1 = CPtr(winShm Ptr, local0->pShm)
    ' C automatic storage declaration
    local3 = Cast(c2fb_c_int, &O0ULL)
    local4 = Cast(UShort, (Cast(c2fb_c_uint, ((Cast(c2fb_c_uint, (Cast(c2fb_c_uint, 1ULL) Shl (Cast(c2fb_c_int, (arg1 + arg2)))))) - (Cast(c2fb_c_uint, (Cast(c2fb_c_uint, 1ULL) Shl arg1)))))))
    If (-Cast(c2fb_c_int, ((local1 = Cast(c2fb_c_int, &O0ULL))))) Then
        Return (Cast(c2fb_c_int, (Cast(c2fb_c_int, 10ULL) Or (Cast(c2fb_c_int, (Cast(c2fb_c_int, 20ULL) Shl Cast(c2fb_c_int, 8ULL)))))))
    End If
    c2fb_temp_0 = CPtr(winShmNode Ptr, local1->pShmNode)
    local2 = c2fb_temp_0
    If ((-Cast(c2fb_c_int, ((local2 = Cast(c2fb_c_int, &O0ULL)))))) Then
        Return (Cast(c2fb_c_int, (Cast(c2fb_c_int, 10ULL) Or (Cast(c2fb_c_int, (Cast(c2fb_c_int, 20ULL) Shl Cast(c2fb_c_int, 8ULL)))))))
    End If
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(c2fb_c_int, (((-Cast(c2fb_c_int, ((((-Cast(c2fb_c_int, (((Cast(c2fb_c_int, (arg3 And Cast(c2fb_c_int, 1ULL)))) AndAlso (Cast(c2fb_c_int, ((Cast(c2fb_c_int, (Cast(c2fb_c_int, local1->exclMask) Or Cast(c2fb_c_int, local1->sharedMask)))) And Cast(c2fb_c_int, local4))))))))) OrElse ((-Cast(c2fb_c_int, (((-Cast(c2fb_c_int, ((arg3 = (Cast(c2fb_c_int, (Cast(c2fb_c_int, 4ULL) Or Cast(c2fb_c_int, 2ULL)))))))) AndAlso (-Cast(c2fb_c_int, ((Cast(c2fb_c_int, &O0ULL) = (Cast(c2fb_c_int, (Cast(c2fb_c_int, local1->sharedMask) And Cast(c2fb_c_int, local4))))))))))))))))) OrElse ((-Cast(c2fb_c_int, ((arg3 = (Cast(c2fb_c_int, (Cast(c2fb_c_int, 8ULL) Or Cast(c2fb_c_int, 2ULL))))))))))))) Then
        local5 = local1->hShm
        If Cast(c2fb_c_int, (arg3 And Cast(c2fb_c_int, 1ULL))) Then
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            If local2->bUseSharedLockHandle Then
                c2fb_temp_1 = local2->hSharedShm
                local5 = c2fb_temp_1
                If Cast(c2fb_c_int, (arg3 And Cast(c2fb_c_int, 4ULL))) Then
                    ' C automatic storage declaration
                    sqlite3_mutex_enter(local2->mutex)
                    c2fb_temp_2 = CPtr(winShm Ptr, local2->pWinShmList)
                    local6 = c2fb_temp_2
                    While local6
                        If (-Cast(c2fb_c_int, (((-Cast(c2fb_c_int, ((local6 <> local1)))) AndAlso (Cast(c2fb_c_int, (Cast(c2fb_c_int, local6->sharedMask) And Cast(c2fb_c_int, local4)))))))) Then
                            c2fb_temp_4 = (CPtr(Any Ptr, Cast(Integer, Cast(c2fb_c_int, (-Cast(c2fb_c_int, 1ULL))))))
                            local5 = c2fb_temp_4
                            Goto c2fb_flow_0
                        End If
                    c2fb_flow_1:
                        c2fb_temp_3 = CPtr(winShm Ptr, local6->pWinShmNext)
                        local6 = c2fb_temp_3
                    Wend
                    c2fb_flow_0:
                    sqlite3_mutex_leave(local2->mutex)
                End If
            End If
            If (-Cast(c2fb_c_int, ((local5 <> (CPtr(Any Ptr, Cast(Integer, Cast(c2fb_c_int, (-Cast(c2fb_c_int, 1ULL)))))))))) Then
                c2fb_temp_5 = Cast(c2fb_c_int, winHandleUnlock(local5, Cast(c2fb_c_int, (arg1 + (Cast(c2fb_c_int, ((Cast(c2fb_c_int, (Cast(c2fb_c_int, 22ULL) + Cast(c2fb_c_int, 8ULL)))) * Cast(c2fb_c_int, 4ULL)))))), arg2))
                local3 = c2fb_temp_5
            End If
            If (-Cast(c2fb_c_int, ((local3 = Cast(c2fb_c_int, &O0ULL))))) Then
                c2fb_temp_6 = CPtr(UShort Ptr, @(local1->exclMask))
                c2fb_temp_7 = Cast(UShort, (Cast(c2fb_c_int, (Cast(c2fb_c_int, local1->exclMask) And Cast(c2fb_c_int, (Not Cast(c2fb_c_int, local4)))))))
                (*c2fb_temp_6) = c2fb_temp_7
                c2fb_temp_8 = CPtr(UShort Ptr, @(local1->sharedMask))
                c2fb_temp_9 = Cast(UShort, (Cast(c2fb_c_int, (Cast(c2fb_c_int, local1->sharedMask) And Cast(c2fb_c_int, (Not Cast(c2fb_c_int, local4)))))))
                (*c2fb_temp_8) = c2fb_temp_9
            End If
        Else
            local7 = (IIf((Cast(c2fb_c_int, (arg3 And Cast(c2fb_c_int, 8ULL)))), Cast(c2fb_c_int, 1ULL), Cast(c2fb_c_int, &O0ULL)))
            local8 = Cast(c2fb_c_int, &O0ULL)
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
            local8 = local0->iBusyTimeout
#endif
            If local2->bUseSharedLockHandle Then
                ' C automatic storage declaration
                c2fb_temp_10 = local2->hSharedShm
                local5 = c2fb_temp_10
                sqlite3_mutex_enter(local2->mutex)
                c2fb_temp_11 = CPtr(winShm Ptr, local2->pWinShmList)
                local9 = c2fb_temp_11
                While local9
                    If local7 Then
                        If Cast(c2fb_c_int, ((Cast(c2fb_c_int, (Cast(c2fb_c_int, local9->sharedMask) Or Cast(c2fb_c_int, local9->exclMask)))) And Cast(c2fb_c_int, local4))) Then
                            c2fb_temp_13 = Cast(c2fb_c_int, Cast(c2fb_c_int, 5ULL))
                            local3 = c2fb_temp_13
                            c2fb_temp_14 = (CPtr(Any Ptr, Cast(Integer, Cast(c2fb_c_int, (-Cast(c2fb_c_int, 1ULL))))))
                            local5 = c2fb_temp_14
                        End If
                    Else
                        If Cast(c2fb_c_int, (Cast(c2fb_c_int, local9->sharedMask) And Cast(c2fb_c_int, local4))) Then
                            c2fb_temp_15 = (CPtr(Any Ptr, Cast(Integer, Cast(c2fb_c_int, (-Cast(c2fb_c_int, 1ULL))))))
                            local5 = c2fb_temp_15
                        Else
                            If Cast(c2fb_c_int, (Cast(c2fb_c_int, local9->exclMask) And Cast(c2fb_c_int, local4))) Then
                                c2fb_temp_16 = Cast(c2fb_c_int, Cast(c2fb_c_int, 5ULL))
                                local3 = c2fb_temp_16
                                c2fb_temp_17 = (CPtr(Any Ptr, Cast(Integer, Cast(c2fb_c_int, (-Cast(c2fb_c_int, 1ULL))))))
                                local5 = c2fb_temp_17
                            End If
                        End If
                    End If
                c2fb_flow_3:
                    c2fb_temp_12 = CPtr(winShm Ptr, local9->pWinShmNext)
                    local9 = c2fb_temp_12
                Wend
                c2fb_flow_2:
                sqlite3_mutex_leave(local2->mutex)
            End If
            If (-Cast(c2fb_c_int, ((local5 <> (CPtr(Any Ptr, Cast(Integer, Cast(c2fb_c_int, (-Cast(c2fb_c_int, 1ULL)))))))))) Then
                c2fb_temp_18 = Cast(c2fb_c_int, winHandleLockTimeout(local5, Cast(c2fb_c_int, (arg1 + (Cast(c2fb_c_int, ((Cast(c2fb_c_int, (Cast(c2fb_c_int, 22ULL) + Cast(c2fb_c_int, 8ULL)))) * Cast(c2fb_c_int, 4ULL)))))), arg2, local7, local8))
                local3 = c2fb_temp_18
            End If
            If (-Cast(c2fb_c_int, ((local3 = Cast(c2fb_c_int, &O0ULL))))) Then
                If local7 Then
                    c2fb_temp_19 = CPtr(UShort Ptr, @(local1->exclMask))
                    c2fb_temp_20 = Cast(UShort, (Cast(c2fb_c_int, (Cast(c2fb_c_int, local1->exclMask) Or Cast(c2fb_c_int, local4)))))
                    (*c2fb_temp_19) = c2fb_temp_20
                Else
                    c2fb_temp_21 = CPtr(UShort Ptr, @(local1->sharedMask))
                    c2fb_temp_22 = Cast(UShort, (Cast(c2fb_c_int, (Cast(c2fb_c_int, local1->sharedMask) Or Cast(c2fb_c_int, local4)))))
                    (*c2fb_temp_21) = c2fb_temp_22
                End If
            End If
        End If
    End If
    ' empty C statement
    Return local3
End Function
#endif

#ifndef SQLITE_OMIT_WAL
Private Sub winShmPurge CDecl Alias "winShmPurge" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal deleteFlag As SQLITE_C_INT _
)
#ifdef SQLITE_DEBUG
    If winShmMutexHeld() = 0 Then
        sqlite3DebugAssert(StrPtr("winShmMutexHeld()"))
        Exit Sub
    End If
#endif

    Dim pLink As winShmNode Ptr Ptr = @winShmNodeList
    While pLink <> 0 AndAlso pLink[0] <> 0
        Dim pNode As winShmNode Ptr = pLink[0]
        If pNode->pWinShmList = 0 Then
            If pNode->mutex <> 0 Then sqlite3_mutex_free(pNode->mutex)
            If pNode->aRegion <> 0 Then
                For i As SQLITE_C_INT = 0 To pNode->nRegion - 1
                    If pNode->aRegion[i].pMap <> 0 Then _
                        winUnmapViewOfFile(pNode->aRegion[i].pMap)
                    If pNode->aRegion[i].hMap <> 0 Then _
                        winCloseHandle(pNode->aRegion[i].hMap)
                Next
            End If
            winHandleClose(pNode->hSharedShm)

            If deleteFlag <> 0 Then
#ifdef SQLITE_TEST
                fbTestSetIoErrorBenign(1)
#endif
                sqlite3BeginBenignMalloc()
                winDelete(pVfs, pNode->zFilename, 0)
                sqlite3EndBenignMalloc()
#ifdef SQLITE_TEST
                fbTestSetIoErrorBenign(0)
#endif
            End If

            pLink[0] = pNode->pNext
            sqlite3_free(pNode->aRegion)
            sqlite3_free(pNode)
        Else
            pLink = @pNode->pNext
        End If
    Wend
End Sub

Private Function winCloseSharedMemory CDecl Alias "winCloseSharedMemory" ( _
    ByVal pDbFile As winFile Ptr, _
    ByVal deleteFlag As SQLITE_C_INT _
) As SQLITE_C_INT
    If pDbFile = 0 Then Return SQLITE_MISUSE
    Dim pConnection As winShm Ptr = pDbFile->pShm
    If pConnection = 0 Then Return SQLITE_OK

    winHandleClose(pConnection->hShm)
    winShmEnterMutex()
    Dim pNode As winShmNode Ptr = pConnection->pShmNode
    If pNode = 0 Then
        winShmLeaveMutex()
        Return SQLITE_MISUSE
    End If

    sqlite3_mutex_enter(pNode->mutex)
    Dim pLink As winShm Ptr Ptr = @pNode->pWinShmList
    While pLink <> 0 AndAlso pLink[0] <> 0 AndAlso _
          pLink[0] <> pConnection
        Dim pCurrent As winShm Ptr = pLink[0]
        pLink = @pCurrent->pWinShmNext
    Wend
    If pLink = 0 OrElse pLink[0] <> pConnection Then
        sqlite3_mutex_leave(pNode->mutex)
        winShmLeaveMutex()
        Return SQLITE_MISUSE
    End If
    pLink[0] = pConnection->pWinShmNext
    sqlite3_mutex_leave(pNode->mutex)

    winShmPurge(pDbFile->pVfs, deleteFlag)
    winShmLeaveMutex()

    sqlite3_free(pConnection)
    pDbFile->pShm = 0
    Return SQLITE_OK
End Function

Private Function winOpenSharedMemory( _
    ByVal pDbFile As winFile Ptr _
) As SQLITE_C_INT
    If pDbFile = 0 OrElse pDbFile->zPath = 0 OrElse _
       pDbFile->pShm <> 0 Then Return SQLITE_MISUSE

    Dim nameLength As SQLITE_C_INT = sqlite3Strlen30(pDbFile->zPath)
    If nameLength <= 0 OrElse nameLength > 2147483600 Then _
        Return SQLITE_CANTOPEN

    Dim pConnection As winShm Ptr = _
        CPtr(winShm Ptr, sqlite3MallocZero(SizeOf(winShm)))
    If pConnection = 0 Then Return SQLITE_IOERR_NOMEM

    Dim nodeBytes As sqlite3_uint64 = _
        CULngInt(SizeOf(winShmNode)) + CULngInt(nameLength) + 17ULL
    Dim pNewNode As winShmNode Ptr = CPtr( _
        winShmNode Ptr, sqlite3MallocZero(nodeBytes))
    If pNewNode = 0 Then
        sqlite3_free(pConnection)
        Return SQLITE_IOERR_NOMEM
    End If

    pConnection->hShm = CPtr(Any Ptr, -1)
    pNewNode->zFilename = CPtr( _
        ZString Ptr, CPtr(UByte Ptr, pNewNode) + SizeOf(winShmNode))
    pNewNode->hSharedShm = CPtr(Any Ptr, -1)
    pNewNode->isUnlocked = 1
    If winIsUNCPath(pDbFile->zPath) <> 0 OrElse _
       winIsRemoteVolume(pDbFile->zPath) <> 0 Then
        pNewNode->bUseSharedLockHandle = 1
    End If

    sqlite3_snprintf( _
        nameLength + 15, pNewNode->zFilename, StrPtr(!"%s-shm"), _
        pDbFile->zPath)
#ifdef SQLITE_ENABLE_8_3_NAMES
    sqlite3FileSuffix3(pDbFile->zPath, pNewNode->zFilename)
#endif

    Dim pNode As winShmNode Ptr = winShmNodeList
    Dim rc As SQLITE_C_INT = SQLITE_OK
    winShmEnterMutex()
    While pNode <> 0
        If sqlite3StrICmp(pNode->zFilename, pNewNode->zFilename) = 0 Then _
            Exit While
        pNode = pNode->pNext
    Wend

    If pNode = 0 Then
        pNode = pNewNode
        If sqlite3ConfigCoreMutexEnabled() <> 0 Then
            pNode->mutex = sqlite3_mutex_alloc(SQLITE_MUTEX_FAST)
            If pNode->mutex = 0 Then rc = SQLITE_IOERR_NOMEM
        End If

        If rc = SQLITE_OK Then
            pNode->isReadonly = sqlite3_uri_boolean( _
                pDbFile->zPath, StrPtr(!"readonly_shm"), 0)
            rc = winHandleOpen( _
                pNewNode->zFilename, @pNode->isReadonly, _
                @pNode->hSharedShm)
        End If

        If rc = SQLITE_OK Then
            pNode->pNext = winShmNodeList
            winShmNodeList = pNode
            pNewNode = 0
        Else
            If pNode->mutex <> 0 Then sqlite3_mutex_free(pNode->mutex)
            If pNode->hSharedShm <> 0 AndAlso _
               pNode->hSharedShm <> CPtr(Any Ptr, -1) Then
                winHandleClose(pNode->hSharedShm)
            End If
        End If
    End If

    If rc = SQLITE_OK Then
        sqlite3_mutex_enter(pNode->mutex)
        pConnection->pShmNode = pNode
        pConnection->pWinShmNext = pNode->pWinShmList
        pNode->pWinShmList = pConnection
#if defined(SQLITE_DEBUG) OrElse defined(SQLITE_HAVE_OS_TRACE)
        pConnection->id = pNode->nextShmId
        pNode->nextShmId += 1
#endif
        pDbFile->pShm = pConnection
        sqlite3_mutex_leave(pNode->mutex)
    Else
        sqlite3_free(pConnection)
        pConnection = 0
    End If
    winShmLeaveMutex()
    If pNewNode <> 0 Then sqlite3_free(pNewNode)
    If rc <> SQLITE_OK Then Return rc

    If pNode->bUseSharedLockHandle = 0 Then
        pConnection->bReadonly = sqlite3_uri_boolean( _
            pDbFile->zPath, StrPtr(!"readonly_shm"), 0)
        rc = winHandleOpen( _
            pNode->zFilename, @pConnection->bReadonly, _
            @pConnection->hShm)
        If rc <> SQLITE_OK Then
            winCloseSharedMemory(pDbFile, 0)
            Return rc
        End If
    End If
    Return SQLITE_OK
End Function

Private Function winShmMap( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal regionIndex As SQLITE_C_INT, _
    ByVal regionBytes As SQLITE_C_INT, _
    ByVal isWrite As SQLITE_C_INT, _
    ByVal pMappedRegion As Any Ptr Ptr _
) As SQLITE_C_INT
    If pMappedRegion = 0 Then Return SQLITE_MISUSE
    pMappedRegion[0] = 0
    If pFile = 0 OrElse regionIndex < 0 OrElse regionBytes <= 0 Then _
        Return SQLITE_MISUSE

    Dim pDbFile As winFile Ptr = CPtr(winFile Ptr, pFile)
    Dim pConnection As winShm Ptr = pDbFile->pShm
    Dim pNode As winShmNode Ptr
    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim busyTimeout As SQLITE_C_UINT = 0
    Dim systemInfo As SYSTEM_INFO
    Dim sharedHandle As Any Ptr
    Dim regionCount As sqlite3_uint64
    Dim minimumBytes As sqlite3_uint64
    Dim minimumFileSize As sqlite3_int64
    Dim fileSize As sqlite3_int64 = 0
    Dim requiredArrayBytes As sqlite3_uint64
    Dim newRegions As ShmRegion Ptr
    Dim mappingProtect As SQLITE_C_UINT = WIN_SHM_PAGE_READWRITE
    Dim mappingFlags As SQLITE_C_UINT = _
        WIN_SHM_FILE_MAP_WRITE Or WIN_SHM_FILE_MAP_READ
    Dim regionOffset As sqlite3_int64
    Dim regionOffsetUnsigned As sqlite3_uint64
    Dim alignmentOffset As SQLITE_C_UINT
    Dim alignedOffset As sqlite3_uint64
    Dim mapLength As sqlite3_uint64
    Dim mapHandle As Any Ptr
    Dim mapBase As Any Ptr
    Dim regionCursor As SQLITE_C_INT
    Dim highSize As SQLITE_C_UINT
    Dim lowSize As SQLITE_C_UINT
    Dim highOffset As SQLITE_C_UINT
    Dim lowOffset As SQLITE_C_UINT

    If pConnection = 0 Then
        rc = winOpenSharedMemory(pDbFile)
        If rc <> SQLITE_OK Then Return rc
        pConnection = pDbFile->pShm
    End If
    If pConnection = 0 OrElse pConnection->pShmNode = 0 Then _
        Return SQLITE_IOERR_SHMLOCK
    pNode = pConnection->pShmNode

#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    busyTimeout = pDbFile->iBusyTimeout
#endif
    winGetSystemInfo(@systemInfo)
    If systemInfo.dwAllocationGranularity = 0 Then Return SQLITE_ERROR

    sqlite3_mutex_enter(pNode->mutex)
    If pNode->isUnlocked <> 0 Then
        If pNode->nRegion <> 0 Then
            rc = SQLITE_IOERR_SHMMAP
            GoTo shm_map_cleanup
        End If
        rc = winLockSharedMemory(pNode, busyTimeout)
        If rc <> SQLITE_OK Then GoTo shm_map_cleanup
    End If

    If pNode->nRegion < 0 OrElse _
       (pNode->nRegion > 0 AndAlso pNode->szRegion <> regionBytes) Then
        rc = SQLITE_IOERR_SHMMAP
        GoTo shm_map_cleanup
    End If

    If pNode->nRegion <= regionIndex Then
        sharedHandle = pNode->hSharedShm
        regionCount = CULngInt(regionIndex) + 1ULL
        minimumBytes = regionCount * CULngInt(regionBytes)
        minimumFileSize = CLngInt(minimumBytes)
        pNode->szRegion = regionBytes

        rc = winHandleSize(sharedHandle, @fileSize)
        If rc <> SQLITE_OK Then
            pNode->lastErrno = winGetLastErrorCode()
            rc = winLogErrorAtLine( _
                rc, pNode->lastErrno, StrPtr(!"winShmMap1"), _
                pDbFile->zPath, 3660)
            GoTo shm_map_cleanup
        End If

        If fileSize < minimumFileSize Then
            If isWrite = 0 Then GoTo shm_map_cleanup
            rc = winHandleTruncate(sharedHandle, minimumFileSize)
            If rc <> SQLITE_OK Then
                pNode->lastErrno = winGetLastErrorCode()
                rc = winLogErrorAtLine( _
                    rc, pNode->lastErrno, StrPtr(!"winShmMap2"), _
                    pDbFile->zPath, 3672)
                GoTo shm_map_cleanup
            End If
        End If

        requiredArrayBytes = regionCount * SizeOf(ShmRegion)
        newRegions = CPtr(ShmRegion Ptr, sqlite3_realloc64( _
            pNode->aRegion, requiredArrayBytes))
        If newRegions = 0 Then
            rc = SQLITE_IOERR_NOMEM
            GoTo shm_map_cleanup
        End If
        pNode->aRegion = newRegions

        If pNode->isReadonly <> 0 Then
            mappingProtect = WIN_SHM_PAGE_READONLY
            mappingFlags = WIN_SHM_FILE_MAP_READ
        End If

        While pNode->nRegion <= regionIndex
            regionCursor = pNode->nRegion
            minimumBytes = regionCount * CULngInt(regionBytes)
#ifdef SQLITE_UWP
            mapHandle = winCreateFileMappingFromApp( _
                sharedHandle, 0, mappingProtect, minimumBytes, 0)
#else
            highSize = CUInt((minimumBytes Shr 32) And &HFFFFFFFFULL)
            lowSize = CUInt(minimumBytes And &HFFFFFFFFULL)
            mapHandle = winCreateFileMappingW( _
                sharedHandle, 0, mappingProtect, highSize, lowSize, 0)
#endif
            regionOffset = CLngInt(regionCursor) * CLngInt(regionBytes)
            regionOffsetUnsigned = CULngInt(regionOffset)
            alignmentOffset = CUInt( _
                regionOffsetUnsigned Mod _
                CULngInt(systemInfo.dwAllocationGranularity))
            alignedOffset = regionOffsetUnsigned - alignmentOffset
            mapLength = CULngInt(regionBytes) + CULngInt(alignmentOffset)
            If SizeOf(SQLITE_SIZE_T) = 4 AndAlso mapLength > &HFFFFFFFFULL Then
                If mapHandle <> 0 Then winCloseHandle(mapHandle)
                rc = SQLITE_IOERR_SHMMAP
                GoTo shm_map_cleanup
            End If
            highOffset = CUInt((alignedOffset Shr 32) And &HFFFFFFFFULL)
            lowOffset = CUInt(alignedOffset And &HFFFFFFFFULL)
            If mapHandle <> 0 Then
#ifdef SQLITE_UWP
                mapBase = winMapViewOfFileFromApp( _
                    mapHandle, mappingFlags, alignedOffset, CULngInt(mapLength))
#else
                mapBase = winMapViewOfFile( _
                    mapHandle, mappingFlags, highOffset, lowOffset, _
                    CULngInt(mapLength))
#endif
            Else
                mapBase = 0
            End If

            If mapBase = 0 Then
                pNode->lastErrno = winGetLastErrorCode()
                rc = winLogErrorAtLine( _
                    SQLITE_IOERR_SHMMAP, pNode->lastErrno, _
                    StrPtr(!"winShmMap3"), pDbFile->zPath, 3722)
                If mapHandle <> 0 Then winCloseHandle(mapHandle)
                GoTo shm_map_cleanup
            End If

            pNode->aRegion[regionCursor].pMap = mapBase
            pNode->aRegion[regionCursor].hMap = mapHandle
            pNode->nRegion += 1
        Wend
    End If

shm_map_cleanup:
    If pNode->nRegion > regionIndex Then
        If pNode->aRegion = 0 OrElse _
           pNode->aRegion[regionIndex].pMap = 0 Then
            rc = SQLITE_IOERR_SHMMAP
        Else
            regionOffset = CLngInt(regionIndex) * CLngInt(regionBytes)
            regionOffsetUnsigned = CULngInt(regionOffset)
            alignmentOffset = CUInt( _
                regionOffsetUnsigned Mod _
                CULngInt(systemInfo.dwAllocationGranularity))
            mapBase = pNode->aRegion[regionIndex].pMap
            pMappedRegion[0] = CPtr( _
                Any Ptr, CPtr(UByte Ptr, mapBase) + alignmentOffset)
        End If
    End If
    If pNode->isReadonly <> 0 AndAlso rc = SQLITE_OK Then _
        rc = SQLITE_READONLY
    sqlite3_mutex_leave(pNode->mutex)
    Return rc
End Function

Private Function winShmUnmap CDecl Alias "winShmUnmap" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal deleteFlag As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
    Return winCloseSharedMemory(CPtr(winFile Ptr, pFile), deleteFlag)
End Function
#endif

Private Sub winShmBarrier CDecl Alias "winShmBarrier" ( _
    ByVal pFile As sqlite3_file Ptr _
)
    sqlite3MemoryBarrier()
    winShmEnterMutex()
    winShmLeaveMutex()
End Sub

Private Sub winInitializeVfsRecord( _
    ByRef vfs As sqlite3_vfs, _
    ByVal zName As Const ZString Ptr, _
    ByVal maximumPathBytes As SQLITE_C_INT, _
    ByVal pApplicationData As Any Ptr _
)
    winMemset(@vfs, 0, SizeOf(sqlite3_vfs))
    vfs.iVersion = 3
    vfs.szOsFile = SizeOf(winFile)
    vfs.mxPathname = maximumPathBytes
    vfs.zName = CPtr(ZString Ptr, zName)
    vfs.pAppData = pApplicationData
    vfs.xOpen = CPtr(SqliteVfsOpenProc, @winOpen)
    vfs.xDelete = CPtr(SqliteVfsDeleteProc, @winDelete)
    vfs.xAccess = CPtr(SqliteVfsAccessProc, @winAccess)
    vfs.xFullPathname = CPtr(SqliteVfsFullPathnameProc, @winFullPathname)
#ifdef SQLITE_OMIT_LOAD_EXTENSION
    vfs.xDlOpen = 0
    vfs.xDlError = 0
    vfs.xDlSym = 0
    vfs.xDlClose = 0
#else
    vfs.xDlOpen = CPtr(SqliteVfsDlOpenProc, @winDlOpen)
    vfs.xDlError = CPtr(SqliteVfsDlErrorProc, @winDlError)
    vfs.xDlSym = CPtr(SqliteVfsDlSymProc, @winDlSym)
    vfs.xDlClose = CPtr(SqliteVfsDlCloseProc, @winDlClose)
#endif
    vfs.xRandomness = CPtr(SqliteVfsRandomnessProc, @winRandomness)
    vfs.xSleep = CPtr(SqliteVfsSleepProc, @winSleep)
    vfs.xCurrentTime = CPtr(SqliteVfsCurrentTimeProc, @winCurrentTime)
    vfs.xGetLastError = CPtr(SqliteVfsGetLastErrorProc, @winGetLastError)
    vfs.xCurrentTimeInt64 = _
        CPtr(SqliteVfsCurrentTimeInt64Proc, @winCurrentTimeInt64)

    vfs.xSetSystemCall = _
        CPtr(SqliteVfsSetSystemCallProc, @winSetSystemCall)
    vfs.xGetSystemCall = _
        CPtr(SqliteVfsGetSystemCallProc, @winGetSystemCall)
    vfs.xNextSystemCall = _
        CPtr(SqliteVfsNextSystemCallProc, @winNextSystemCall)
End Sub

Function sqlite3_os_init CDecl Alias "sqlite3_os_init" () As SQLITE_C_INT Export
    If winVfsInitialized <> 0 Then Return SQLITE_OK

    winInitializeSystemCallTable()

    winMemset(@winIoMethods, 0, SizeOf(sqlite3_io_methods))
    winIoMethods.iVersion = 3
    winIoMethods.xClose = CPtr(SqliteFileCloseProc, @winClose)
    winIoMethods.xRead = CPtr(SqliteFileReadProc, @winRead)
    winIoMethods.xWrite = CPtr(SqliteFileWriteProc, @winWrite)
    winIoMethods.xTruncate = CPtr(SqliteFileTruncateProc, @winTruncate)
    winIoMethods.xSync = CPtr(SqliteFileSyncProc, @winSync)
    winIoMethods.xFileSize = CPtr(SqliteFileSizeProc, @winFileSize)
    winIoMethods.xLock = CPtr(SqliteFileLockProc, @winLock)
    winIoMethods.xUnlock = CPtr(SqliteFileLockProc, @winUnlock)
    winIoMethods.xCheckReservedLock = _
        CPtr(SqliteFileCheckReservedProc, @winCheckReservedLock)
    winIoMethods.xFileControl = CPtr(SqliteFileControlProc, @winFileControl)
    winIoMethods.xSectorSize = CPtr(SqliteFileSectorSizeProc, @winSectorSize)
    winIoMethods.xDeviceCharacteristics = _
        CPtr(SqliteFileDeviceCharacteristicsProc, @winDeviceCharacteristics)
#ifndef SQLITE_OMIT_WAL
    winIoMethods.xShmMap = CPtr(SqliteFileShmMapProc, @winShmMap)
    winIoMethods.xShmLock = CPtr(SqliteFileShmLockProc, @winShmLock)
    winIoMethods.xShmBarrier = CPtr(SqliteFileShmBarrierProc, @winShmBarrier)
    winIoMethods.xShmUnmap = CPtr(SqliteFileShmUnmapProc, @winShmUnmap)
#endif
#if SQLITE_MAX_MMAP_SIZE > 0
    winIoMethods.xFetch = CPtr(SqliteFileFetchProc, @winFetch)
    winIoMethods.xUnfetch = CPtr(SqliteFileUnfetchProc, @winUnfetch)
#endif

    winIoNolockMethods = winIoMethods
    winIoNolockMethods.xLock = CPtr(SqliteFileLockProc, @winNolockLock)
    winIoNolockMethods.xUnlock = CPtr(SqliteFileLockProc, @winNolockUnlock)
    winIoNolockMethods.xCheckReservedLock = _
        CPtr(SqliteFileCheckReservedProc, @winNolockCheckReservedLock)
    winAppData.pMethod = @winIoMethods
    winAppData.pAppData = 0
    winAppData.bNoLock = 0
    winNolockAppData.pMethod = @winIoNolockMethods
    winNolockAppData.pAppData = 0
    winNolockAppData.bNoLock = 1

    winInitializeVfsRecord( _
        winVfs, StrPtr("win32"), SQLITE_WIN32_MAX_PATH_BYTES, @winAppData)
    winInitializeVfsRecord( _
        winLongPathVfs, StrPtr("win32-longpath"), _
        SQLITE_WINNT_MAX_PATH_BYTES, @winAppData)
    winInitializeVfsRecord( _
        winNolockVfs, StrPtr("win32-none"), _
        SQLITE_WIN32_MAX_PATH_BYTES, @winNolockAppData)
    winInitializeVfsRecord( _
        winLongPathNolockVfs, StrPtr("win32-longpath-none"), _
        SQLITE_WINNT_MAX_PATH_BYTES, @winNolockAppData)

    Dim rc As SQLITE_C_INT = sqlite3_vfs_register(@winVfs, 1)
    If rc = SQLITE_OK Then rc = sqlite3_vfs_register(@winLongPathVfs, 0)
    If rc = SQLITE_OK Then rc = sqlite3_vfs_register(@winNolockVfs, 0)
    If rc = SQLITE_OK Then rc = sqlite3_vfs_register(@winLongPathNolockVfs, 0)
    If rc = SQLITE_OK Then winVfsInitialized = 1
    Return rc
End Function

Function sqlite3_os_end CDecl Alias "sqlite3_os_end" () As SQLITE_C_INT Export
    winVfsInitialized = 0
    Return SQLITE_OK
End Function

#endif

/' end of sqlite3_os_win_helpers.bas '/
