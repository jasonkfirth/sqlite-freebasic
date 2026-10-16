/'
    Project: SQLite FreeBASIC port

    File: sqlite3_os_win_syscall_types.bi

    Purpose: Preserve typed Win32 and Cygwin procedure pointers for the VFS override table.

    Responsibilities:

        - Match each imported Win32 API signature used by the syscall table.
        - Let VFS and heap modules call an overridden pointer with its ABI signature.
        - Describe the Cygwin POSIX fallback callbacks used by path operations.

    This file intentionally does NOT contain:

        - Win32 imports, syscall table storage, or callback implementations.
        - Platform-independent SQLite APIs.
'/

#ifndef SQLITE3_OS_WIN_SYSCALL_TYPES_BI
#define SQLITE3_OS_WIN_SYSCALL_TYPES_BI

#ifdef SQLITE_OS_WIN

Type WinSyscallProc_winAreFileApisANSI As Function StdCall () As SQLITE_C_INT

Type WinSyscallProc_winCloseHandle As Function StdCall ( _
    ByVal hObject As Any Ptr _
) As SQLITE_C_INT

Type WinSyscallProc_winCreateFileW As Function StdCall ( _
    ByVal zFilename As Const UShort Ptr, _
    ByVal desiredAccess As SQLITE_C_UINT, _
    ByVal shareMode As SQLITE_C_UINT, _
    ByVal pSecurityAttributes As Any Ptr, _
    ByVal creationDisposition As SQLITE_C_UINT, _
    ByVal flagsAndAttributes As SQLITE_C_UINT, _
    ByVal hTemplateFile As Any Ptr _
) As Any Ptr

Type WinSyscallProc_winCreateFileMappingFromApp As Function StdCall ( _
    ByVal hFile As Any Ptr, _
    ByVal pSecurityAttributes As Any Ptr, _
    ByVal protect As SQLITE_C_UINT, _
    ByVal maximumSize As sqlite3_uint64, _
    ByVal zName As Const UShort Ptr _
) As Any Ptr

Type WinSyscallProc_winCreateFileMappingW As Function StdCall ( _
    ByVal hFile As Any Ptr, _
    ByVal pSecurityAttributes As Any Ptr, _
    ByVal protect As SQLITE_C_UINT, _
    ByVal maximumSizeHigh As SQLITE_C_UINT, _
    ByVal maximumSizeLow As SQLITE_C_UINT, _
    ByVal zName As Const UShort Ptr _
) As Any Ptr

Type WinSyscallProc_winDeleteFileW As Function StdCall ( _
    ByVal zFilename As Const UShort Ptr _
) As SQLITE_C_INT

Type WinSyscallProc_winFlushFileBuffers As Function StdCall ( _
    ByVal hFile As Any Ptr _
) As SQLITE_C_INT

Type WinSyscallProc_winFormatMessageW As Function StdCall ( _
    ByVal flags As SQLITE_C_UINT, _
    ByVal pSource As Any Ptr, _
    ByVal messageId As SQLITE_C_UINT, _
    ByVal languageId As SQLITE_C_UINT, _
    ByVal pBuffer As UShort Ptr Ptr, _
    ByVal bufferSize As SQLITE_C_UINT, _
    ByVal pArguments As Any Ptr _
) As SQLITE_C_UINT

Type WinSyscallProc_winFreeLibrary As Function StdCall ( _
    ByVal hModule As Any Ptr _
) As SQLITE_C_INT

Type WinSyscallProc_winGetCurrentProcessId As Function StdCall () As SQLITE_C_UINT

Type WinSyscallProc_winGetFileAttributesW As Function StdCall ( _
    ByVal zFilename As Const UShort Ptr _
) As SQLITE_C_UINT

Type WinSyscallProc_winGetFileAttributesExW As Function StdCall ( _
    ByVal zFilename As Const UShort Ptr, _
    ByVal infoLevel As SQLITE_C_INT, _
    ByVal pFileInformation As WIN32_FILE_ATTRIBUTE_DATA Ptr _
) As SQLITE_C_INT

Type WinSyscallProc_winGetFileSizeEx As Function StdCall ( _
    ByVal hFile As Any Ptr, _
    ByVal pSize As LARGE_INTEGER Ptr _
) As SQLITE_C_INT

Type WinSyscallProc_winGetFullPathNameW As Function StdCall ( _
    ByVal zFilename As Const UShort Ptr, _
    ByVal bufferLength As SQLITE_C_UINT, _
    ByVal zBuffer As UShort Ptr, _
    ByVal pFilePart As UShort Ptr Ptr _
) As SQLITE_C_UINT

Type WinSyscallProc_winGetLastErrorCode As Function StdCall () As SQLITE_C_UINT

Type WinSyscallProc_winGetProcAddress As Function StdCall ( _
    ByVal hModule As Any Ptr, _
    ByVal zSymbol As Const ZString Ptr _
) As Any Ptr

Type WinSyscallProc_winGetSystemInfo As Sub StdCall ( _
    ByVal pSystemInfo As SYSTEM_INFO Ptr _
)

Type WinSyscallProc_winGetSystemTimeAsFileTime As Sub StdCall ( _
    ByVal pFileTime As WinFileTime Ptr _
)

Type WinSyscallProc_winGetTempPathW As Function StdCall ( _
    ByVal bufferLength As SQLITE_C_UINT, _
    ByVal zBuffer As UShort Ptr _
) As SQLITE_C_UINT

Type WinSyscallProc_winGetTickCount64 As Function StdCall () As sqlite3_uint64

Type WinSyscallProc_winMemHeapAlloc As Function StdCall ( _
    ByVal hHeap As Any Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal nByte As SQLITE_SIZE_T _
) As Any Ptr

Type WinSyscallProc_winMemHeapCreate As Function StdCall ( _
    ByVal options As SQLITE_C_UINT, _
    ByVal initialSize As SQLITE_SIZE_T, _
    ByVal maximumSize As SQLITE_SIZE_T _
) As Any Ptr

Type WinSyscallProc_winMemHeapDestroy As Function StdCall ( _
    ByVal hHeap As Any Ptr _
) As SQLITE_C_INT

Type WinSyscallProc_winMemHeapFree As Function StdCall ( _
    ByVal hHeap As Any Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal pMemory As Any Ptr _
) As SQLITE_C_INT

Type WinSyscallProc_winMemHeapRealloc As Function StdCall ( _
    ByVal hHeap As Any Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal pMemory As Any Ptr, _
    ByVal nByte As SQLITE_SIZE_T _
) As Any Ptr

Type WinSyscallProc_winMemHeapSize As Function StdCall ( _
    ByVal hHeap As Any Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal pMemory As Any Ptr _
) As SQLITE_SIZE_T

Type WinSyscallProc_winMemHeapValidate As Function StdCall ( _
    ByVal hHeap As Any Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal pMemory As Any Ptr _
) As SQLITE_C_INT

Type WinSyscallProc_winMemHeapCompact As Function StdCall ( _
    ByVal hHeap As Any Ptr, _
    ByVal flags As SQLITE_C_UINT _
) As SQLITE_C_UINT

Type WinSyscallProc_winLoadLibraryW As Function StdCall ( _
    ByVal zFilename As Const UShort Ptr _
) As Any Ptr

Type WinSyscallProc_winLocalFree As Function StdCall ( _
    ByVal pMemory As Any Ptr _
) As Any Ptr

Type WinSyscallProc_winLockFileEx As Function StdCall ( _
    ByVal hFile As Any Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal reserved As SQLITE_C_UINT, _
    ByVal bytesLow As SQLITE_C_UINT, _
    ByVal bytesHigh As SQLITE_C_UINT, _
    ByVal pOverlapped As OVERLAPPED Ptr _
) As SQLITE_C_INT

Type WinSyscallProc_winMapViewOfFile As Function StdCall ( _
    ByVal hMap As Any Ptr, _
    ByVal desiredAccess As SQLITE_C_UINT, _
    ByVal offsetHigh As SQLITE_C_UINT, _
    ByVal offsetLow As SQLITE_C_UINT, _
    ByVal bytesToMap As SQLITE_SIZE_T _
) As Any Ptr

Type WinSyscallProc_winMapViewOfFileFromApp As Function StdCall ( _
    ByVal hMap As Any Ptr, _
    ByVal desiredAccess As SQLITE_C_UINT, _
    ByVal offset As sqlite3_uint64, _
    ByVal bytesToMap As SQLITE_SIZE_T _
) As Any Ptr

Type WinSyscallProc_winMultiByteToWideChar As Function StdCall ( _
    ByVal codePage As SQLITE_C_UINT, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal zText As Const ZString Ptr, _
    ByVal nTextByte As SQLITE_C_INT, _
    ByVal zWideText As UShort Ptr, _
    ByVal nWideChar As SQLITE_C_INT _
) As SQLITE_C_INT

Type WinSyscallProc_winQueryPerformanceCounter As Function StdCall ( _
    ByVal pCounter As LARGE_INTEGER Ptr _
) As SQLITE_C_INT

Type WinSyscallProc_winReadFile As Function StdCall ( _
    ByVal hFile As Any Ptr, _
    ByVal pBuffer As Any Ptr, _
    ByVal bytesToRead As SQLITE_C_UINT, _
    ByVal pBytesRead As SQLITE_C_UINT Ptr, _
    ByVal pOverlapped As OVERLAPPED Ptr _
) As SQLITE_C_INT

Type WinSyscallProc_winSetEndOfFile As Function StdCall ( _
    ByVal hFile As Any Ptr _
) As SQLITE_C_INT

Type WinSyscallProc_winSetFilePointerEx As Function StdCall ( _
    ByVal hFile As Any Ptr, _
    ByVal distance As LARGE_INTEGER, _
    ByVal pNewPosition As LARGE_INTEGER Ptr, _
    ByVal moveMethod As SQLITE_C_UINT _
) As SQLITE_C_INT

Type WinSyscallProc_winSleepMilliseconds As Sub StdCall ( _
    ByVal milliseconds As SQLITE_C_UINT _
)

Type WinSyscallProc_winUnlockFileEx As Function StdCall ( _
    ByVal hFile As Any Ptr, _
    ByVal reserved As SQLITE_C_UINT, _
    ByVal bytesLow As SQLITE_C_UINT, _
    ByVal bytesHigh As SQLITE_C_UINT, _
    ByVal pOverlapped As OVERLAPPED Ptr _
) As SQLITE_C_INT

Type WinSyscallProc_winUnmapViewOfFile As Function StdCall ( _
    ByVal pBaseAddress As Any Ptr _
) As SQLITE_C_INT

Type WinSyscallProc_winWideCharToMultiByte As Function StdCall ( _
    ByVal codePage As SQLITE_C_UINT, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal zWideText As Const UShort Ptr, _
    ByVal nWideChar As SQLITE_C_INT, _
    ByVal zText As ZString Ptr, _
    ByVal nTextByte As SQLITE_C_INT, _
    ByVal zDefaultChar As Const ZString Ptr, _
    ByVal pUsedDefaultChar As SQLITE_C_INT Ptr _
) As SQLITE_C_INT

Type WinSyscallProc_winWriteFile As Function StdCall ( _
    ByVal hFile As Any Ptr, _
    ByVal pBuffer As Const Any Ptr, _
    ByVal bytesToWrite As SQLITE_C_UINT, _
    ByVal pBytesWritten As SQLITE_C_UINT Ptr, _
    ByVal pOverlapped As OVERLAPPED Ptr _
) As SQLITE_C_INT

Type WinSyscallProc_winWaitForSingleObject As Function StdCall ( _
    ByVal hObject As Any Ptr, _
    ByVal milliseconds As SQLITE_C_UINT _
) As SQLITE_C_UINT

Type WinSyscallProc_winWaitForSingleObjectEx As Function StdCall ( _
    ByVal hObject As Any Ptr, _
    ByVal milliseconds As SQLITE_C_UINT, _
    ByVal alertable As SQLITE_C_INT _
) As SQLITE_C_UINT

Type WinSyscallProc_winOutputDebugStringA As Sub StdCall ( _
    ByVal zMessage As Const ZString Ptr _
)

Type WinSyscallProc_winMemGetProcessHeap As Function StdCall () As Any Ptr

Type WinSyscallProc_winMemoryBarrierCompareExchange As Function StdCall ( _
    ByVal pTarget As SQLITE_C_INT Ptr, _
    ByVal exchangeValue As SQLITE_C_INT, _
    ByVal comparand As SQLITE_C_INT _
) As SQLITE_C_INT

#if SQLITE_WIN32_USE_UUID
Type WinSyscallProc_winUuidCreate As Function StdCall ( _
    ByVal pUuid As WinUuid Ptr _
) As SQLITE_C_INT
#endif

#if SQLITE_WIN32_USE_UUID
Type WinSyscallProc_winUuidCreateSequential As Function StdCall ( _
    ByVal pUuid As WinUuid Ptr _
) As SQLITE_C_INT
#endif

Type WinSyscallProc_winFlushViewOfFile As Function StdCall ( _
    ByVal pBaseAddress As Const Any Ptr, _
    ByVal bytesToFlush As SQLITE_SIZE_T _
) As SQLITE_C_INT

Type WinSyscallProc_winCreateEventW As Function StdCall ( _
    ByVal pSecurityAttributes As Any Ptr, _
    ByVal manualReset As SQLITE_C_INT, _
    ByVal initialState As SQLITE_C_INT, _
    ByVal zName As Const UShort Ptr _
) As Any Ptr

Type WinSyscallProc_winCancelIo As Function StdCall ( _
    ByVal hFile As Any Ptr _
) As SQLITE_C_INT

Type WinSyscallProc_winGetDriveTypeW As Function StdCall ( _
    ByVal zRootPath As Const UShort Ptr _
) As SQLITE_C_UINT

Type WinSyscallProc_winMemGetLastError As Function StdCall () As SQLITE_C_UINT

#ifdef SQLITE3_FB_CYGWIN
Type WinSyscallProc_cygwinGetenv As Function CDecl ( _
    ByVal zName As Const ZString Ptr _
) As Const ZString Ptr

Type WinSyscallProc_cygwinGetcwd As Function CDecl ( _
    ByVal zBuffer As ZString Ptr, _
    ByVal bufferBytes As SQLITE_SIZE_T _
) As ZString Ptr

Type WinSyscallProc_cygwinReadlink As Function CDecl ( _
    ByVal zPath As Const ZString Ptr, _
    ByVal zBuffer As ZString Ptr, _
    ByVal bufferBytes As SQLITE_SIZE_T _
) As Integer

Type WinSyscallProc_cygwinLstat As Function CDecl ( _
    ByVal zPath As Const ZString Ptr, _
    ByVal pStat As SqliteCygwinStat Ptr _
) As SQLITE_C_INT

Type WinSyscallProc_cygwinErrno As Function CDecl () As SQLITE_C_INT Ptr

Type WinSyscallProc_cygwinConvPath As Function CDecl ( _
    ByVal conversionFlags As SQLITE_C_UINT, _
    ByVal pSource As Const Any Ptr, _
    ByVal pDestination As Any Ptr, _
    ByVal destinationBytes As SQLITE_SIZE_T _
) As Integer
#endif

Declare Function winSystemCallCurrent CDecl Alias "winSystemCallCurrent" ( _
    ByVal syscallIndex As SQLITE_C_INT _
) As WinSystemCallPointer

#endif
#endif

/' end of sqlite3_os_win_syscall_types.bi '/
