/'
    Project: SQLite FreeBASIC port

    File: sqlite3_os_win_syscall_dispatch.bi

    Purpose: Route Windows and Cygwin calls through SQLite VFS syscall overrides.

    Responsibilities:

        - Cast each current table pointer to the imported API signature.
        - Keep Windows VFS and heap callbacks on the same process-wide table.
        - Provide typed Cygwin casts for POSIX path and environment calls.

    This file intentionally does NOT contain:

        - Table initialization or VFS callback implementations.
        - Windows API imports or SQLite error handling.
'/

#ifndef SQLITE3_OS_WIN_SYSCALL_DISPATCH_BI
#define SQLITE3_OS_WIN_SYSCALL_DISPATCH_BI

#ifdef SQLITE_OS_WIN
#define winAreFileApisANSI CPtr(WinSyscallProc_winAreFileApisANSI, winSystemCallCurrent(0))
#define winCloseHandle CPtr(WinSyscallProc_winCloseHandle, winSystemCallCurrent(1))
#define winCreateFileW CPtr(WinSyscallProc_winCreateFileW, winSystemCallCurrent(2))
#define winCreateFileMappingFromApp CPtr(WinSyscallProc_winCreateFileMappingFromApp, winSystemCallCurrent(3))
#define winCreateFileMappingW CPtr(WinSyscallProc_winCreateFileMappingW, winSystemCallCurrent(4))
#define winDeleteFileW CPtr(WinSyscallProc_winDeleteFileW, winSystemCallCurrent(5))
#define winFlushFileBuffers CPtr(WinSyscallProc_winFlushFileBuffers, winSystemCallCurrent(6))
#define winFormatMessageW CPtr(WinSyscallProc_winFormatMessageW, winSystemCallCurrent(7))
#define winFreeLibrary CPtr(WinSyscallProc_winFreeLibrary, winSystemCallCurrent(8))
#define winGetCurrentProcessId CPtr(WinSyscallProc_winGetCurrentProcessId, winSystemCallCurrent(9))
#define winGetFileAttributesW CPtr(WinSyscallProc_winGetFileAttributesW, winSystemCallCurrent(10))
#define winGetFileAttributesExW CPtr(WinSyscallProc_winGetFileAttributesExW, winSystemCallCurrent(11))
#define winGetFileSizeEx CPtr(WinSyscallProc_winGetFileSizeEx, winSystemCallCurrent(12))
#define winGetFullPathNameW CPtr(WinSyscallProc_winGetFullPathNameW, winSystemCallCurrent(13))
#define winGetLastErrorCode CPtr(WinSyscallProc_winGetLastErrorCode, winSystemCallCurrent(14))
#define winGetProcAddress CPtr(WinSyscallProc_winGetProcAddress, winSystemCallCurrent(15))
#define winGetSystemInfo CPtr(WinSyscallProc_winGetSystemInfo, winSystemCallCurrent(16))
#define winGetSystemTimeAsFileTime CPtr(WinSyscallProc_winGetSystemTimeAsFileTime, winSystemCallCurrent(17))
#define winGetTempPathW CPtr(WinSyscallProc_winGetTempPathW, winSystemCallCurrent(18))
#define winGetTickCount64 CPtr(WinSyscallProc_winGetTickCount64, winSystemCallCurrent(19))
#define winMemHeapAlloc CPtr(WinSyscallProc_winMemHeapAlloc, winSystemCallCurrent(20))
#define winMemHeapCreate CPtr(WinSyscallProc_winMemHeapCreate, winSystemCallCurrent(21))
#define winMemHeapDestroy CPtr(WinSyscallProc_winMemHeapDestroy, winSystemCallCurrent(22))
#define winMemHeapFree CPtr(WinSyscallProc_winMemHeapFree, winSystemCallCurrent(23))
#define winMemHeapRealloc CPtr(WinSyscallProc_winMemHeapRealloc, winSystemCallCurrent(24))
#define winMemHeapSize CPtr(WinSyscallProc_winMemHeapSize, winSystemCallCurrent(25))
#define winMemHeapValidate CPtr(WinSyscallProc_winMemHeapValidate, winSystemCallCurrent(26))
#define winMemHeapCompact CPtr(WinSyscallProc_winMemHeapCompact, winSystemCallCurrent(27))
#define winLoadLibraryW CPtr(WinSyscallProc_winLoadLibraryW, winSystemCallCurrent(28))
#define winLocalFree CPtr(WinSyscallProc_winLocalFree, winSystemCallCurrent(29))
#define winLockFileEx CPtr(WinSyscallProc_winLockFileEx, winSystemCallCurrent(30))
#define winMapViewOfFile CPtr(WinSyscallProc_winMapViewOfFile, winSystemCallCurrent(31))
#define winMapViewOfFileFromApp CPtr(WinSyscallProc_winMapViewOfFileFromApp, winSystemCallCurrent(32))
#define winMultiByteToWideChar CPtr(WinSyscallProc_winMultiByteToWideChar, winSystemCallCurrent(33))
#define winQueryPerformanceCounter CPtr(WinSyscallProc_winQueryPerformanceCounter, winSystemCallCurrent(34))
#define winReadFile CPtr(WinSyscallProc_winReadFile, winSystemCallCurrent(35))
#define winSetEndOfFile CPtr(WinSyscallProc_winSetEndOfFile, winSystemCallCurrent(36))
#define winSetFilePointerEx CPtr(WinSyscallProc_winSetFilePointerEx, winSystemCallCurrent(37))
#define winSleepMilliseconds CPtr(WinSyscallProc_winSleepMilliseconds, winSystemCallCurrent(38))
#define winUnlockFileEx CPtr(WinSyscallProc_winUnlockFileEx, winSystemCallCurrent(39))
#define winUnmapViewOfFile CPtr(WinSyscallProc_winUnmapViewOfFile, winSystemCallCurrent(40))
#define winWideCharToMultiByte CPtr(WinSyscallProc_winWideCharToMultiByte, winSystemCallCurrent(41))
#define winWriteFile CPtr(WinSyscallProc_winWriteFile, winSystemCallCurrent(42))
#define winWaitForSingleObject CPtr(WinSyscallProc_winWaitForSingleObject, winSystemCallCurrent(43))
#define winWaitForSingleObjectEx CPtr(WinSyscallProc_winWaitForSingleObjectEx, winSystemCallCurrent(44))
#define winOutputDebugStringA CPtr(WinSyscallProc_winOutputDebugStringA, winSystemCallCurrent(45))
#define winMemGetProcessHeap CPtr(WinSyscallProc_winMemGetProcessHeap, winSystemCallCurrent(46))
#define winMemoryBarrierCompareExchange CPtr(WinSyscallProc_winMemoryBarrierCompareExchange, winSystemCallCurrent(47))
#define winUuidCreate CPtr(WinSyscallProc_winUuidCreate, winSystemCallCurrent(48))
#define winUuidCreateSequential CPtr(WinSyscallProc_winUuidCreateSequential, winSystemCallCurrent(49))
#define winFlushViewOfFile CPtr(WinSyscallProc_winFlushViewOfFile, winSystemCallCurrent(50))
#define winCreateEventW CPtr(WinSyscallProc_winCreateEventW, winSystemCallCurrent(51))
#define winCancelIo CPtr(WinSyscallProc_winCancelIo, winSystemCallCurrent(52))
#define winGetDriveTypeW CPtr(WinSyscallProc_winGetDriveTypeW, winSystemCallCurrent(59))
#define winMemGetLastError CPtr(WinSyscallProc_winMemGetLastError, winSystemCallCurrent(14))
#ifdef SQLITE3_FB_CYGWIN
#define winCygwinGetenv CPtr(WinSyscallProc_cygwinGetenv, winSystemCallCurrent(53))
#define winCygwinGetcwd CPtr(WinSyscallProc_cygwinGetcwd, winSystemCallCurrent(54))
#define winCygwinReadlink CPtr(WinSyscallProc_cygwinReadlink, winSystemCallCurrent(55))
#define winCygwinLstat CPtr(WinSyscallProc_cygwinLstat, winSystemCallCurrent(56))
#define winCygwinErrno CPtr(WinSyscallProc_cygwinErrno, winSystemCallCurrent(57))
#define winCygwinConvPath CPtr(WinSyscallProc_cygwinConvPath, winSystemCallCurrent(58))
#endif
#endif
#endif

/' end of sqlite3_os_win_syscall_dispatch.bi '/
