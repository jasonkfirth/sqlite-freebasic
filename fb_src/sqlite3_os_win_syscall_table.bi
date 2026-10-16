/'
    Project: SQLite FreeBASIC port

    File: sqlite3_os_win_syscall_table.bi

    Purpose: Initialize the Windows syscall table and implement its VFS callbacks.

    Responsibilities:

        - Keep the 60 C syscall names in their upstream order.
        - Initialize default pointers once before the VFS starts using them.
        - Save original API pointers only when the first override is installed.
        - Expose set, get, and next callbacks for each Windows VFS record.
        - Install Cygwin POSIX defaults for the path-related fallback slots.

    This file intentionally does NOT contain:

        - Win32 imports or per-signature pointer aliases.
        - The VFS record layout or call-through macros.
'/

#ifndef SQLITE3_OS_WIN_SYSCALL_TABLE_BI
#define SQLITE3_OS_WIN_SYSCALL_TABLE_BI

Private Function winSystemCallNamesEqual( _
    ByVal leftName As Const ZString Ptr, _
    ByVal rightName As Const ZString Ptr _
) As SQLITE_C_INT
    If leftName = 0 OrElse rightName = 0 Then Return 0
    Dim byteIndex As SQLITE_SIZE_T = 0
    While leftName[byteIndex] = rightName[byteIndex]
        If leftName[byteIndex] = 0 Then Return -1
        byteIndex += 1
    Wend
    Return 0
End Function

Private Sub winInitializeSystemCallTable()
    ' ready is 0 before initialization, 1 while the winner fills the table,
    ' and 2 after all names and function pointers are published.
    If winSystemCallTableReady = 2 Then Exit Sub

    ' The optional heap allocator can call Win32 before the VFS is registered.
    ' Claim one initialization pass with the imported interlocked primitive.
    If winDefaultWinMemoryBarrierCompareExchange( _
        @winSystemCallTableReady, 1, 0) <> 0 Then
        While winSystemCallTableReady <> 2
            winDefaultWinMemoryBarrierCompareExchange( _
                @winSystemCallTableReady, 2, 2)
        Wend
        Exit Sub
    End If

    winMemset(@winSystemCallTable(0), 0, SizeOf(winSystemCallTable))
    winSystemCallNames(0) = "AreFileApisANSI"
    winSystemCallTable(0).zName = CPtr(Const ZString Ptr, @winSystemCallNames(0))
    winSystemCallTable(0).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinAreFileApisANSI)
    winSystemCallNames(1) = "CloseHandle"
    winSystemCallTable(1).zName = CPtr(Const ZString Ptr, @winSystemCallNames(1))
    winSystemCallTable(1).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinCloseHandle)
    winSystemCallNames(2) = "CreateFileW"
    winSystemCallTable(2).zName = CPtr(Const ZString Ptr, @winSystemCallNames(2))
    winSystemCallTable(2).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinCreateFileW)
    winSystemCallNames(3) = "CreateFileMappingFromApp"
    winSystemCallTable(3).zName = CPtr(Const ZString Ptr, @winSystemCallNames(3))
    winSystemCallNames(4) = "CreateFileMappingW"
    winSystemCallTable(4).zName = CPtr(Const ZString Ptr, @winSystemCallNames(4))
    winSystemCallTable(4).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinCreateFileMappingW)
    winSystemCallNames(5) = "DeleteFileW"
    winSystemCallTable(5).zName = CPtr(Const ZString Ptr, @winSystemCallNames(5))
    winSystemCallTable(5).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinDeleteFileW)
    winSystemCallNames(6) = "FlushFileBuffers"
    winSystemCallTable(6).zName = CPtr(Const ZString Ptr, @winSystemCallNames(6))
    winSystemCallTable(6).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinFlushFileBuffers)
    winSystemCallNames(7) = "FormatMessageW"
    winSystemCallTable(7).zName = CPtr(Const ZString Ptr, @winSystemCallNames(7))
    winSystemCallTable(7).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinFormatMessageW)
    winSystemCallNames(8) = "FreeLibrary"
    winSystemCallTable(8).zName = CPtr(Const ZString Ptr, @winSystemCallNames(8))
    winSystemCallTable(8).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinFreeLibrary)
    winSystemCallNames(9) = "GetCurrentProcessId"
    winSystemCallTable(9).zName = CPtr(Const ZString Ptr, @winSystemCallNames(9))
    winSystemCallTable(9).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinGetCurrentProcessId)
    winSystemCallNames(10) = "GetFileAttributesW"
    winSystemCallTable(10).zName = CPtr(Const ZString Ptr, @winSystemCallNames(10))
    winSystemCallTable(10).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinGetFileAttributesW)
    winSystemCallNames(11) = "GetFileAttributesExW"
    winSystemCallTable(11).zName = CPtr(Const ZString Ptr, @winSystemCallNames(11))
    winSystemCallTable(11).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinGetFileAttributesExW)
    winSystemCallNames(12) = "GetFileSizeEx"
    winSystemCallTable(12).zName = CPtr(Const ZString Ptr, @winSystemCallNames(12))
    winSystemCallTable(12).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinGetFileSizeEx)
    winSystemCallNames(13) = "GetFullPathNameW"
    winSystemCallTable(13).zName = CPtr(Const ZString Ptr, @winSystemCallNames(13))
    winSystemCallTable(13).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinGetFullPathNameW)
    winSystemCallNames(14) = "GetLastError"
    winSystemCallTable(14).zName = CPtr(Const ZString Ptr, @winSystemCallNames(14))
    winSystemCallTable(14).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinGetLastErrorCode)
    winSystemCallNames(15) = "GetProcAddressA"
    winSystemCallTable(15).zName = CPtr(Const ZString Ptr, @winSystemCallNames(15))
    winSystemCallNames(16) = "GetSystemInfo"
    winSystemCallTable(16).zName = CPtr(Const ZString Ptr, @winSystemCallNames(16))
    winSystemCallTable(16).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinGetSystemInfo)
    winSystemCallNames(17) = "GetSystemTimeAsFileTime"
    winSystemCallTable(17).zName = CPtr(Const ZString Ptr, @winSystemCallNames(17))
    winSystemCallTable(17).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinGetSystemTimeAsFileTime)
    winSystemCallNames(18) = "GetTempPathW"
    winSystemCallTable(18).zName = CPtr(Const ZString Ptr, @winSystemCallNames(18))
    winSystemCallTable(18).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinGetTempPathW)
    winSystemCallNames(19) = "GetTickCount64"
    winSystemCallTable(19).zName = CPtr(Const ZString Ptr, @winSystemCallNames(19))
    winSystemCallTable(19).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinGetTickCount64)
    winSystemCallNames(20) = "HeapAlloc"
    winSystemCallTable(20).zName = CPtr(Const ZString Ptr, @winSystemCallNames(20))
    winSystemCallNames(21) = "HeapCreate"
    winSystemCallTable(21).zName = CPtr(Const ZString Ptr, @winSystemCallNames(21))
    winSystemCallNames(22) = "HeapDestroy"
    winSystemCallTable(22).zName = CPtr(Const ZString Ptr, @winSystemCallNames(22))
    winSystemCallNames(23) = "HeapFree"
    winSystemCallTable(23).zName = CPtr(Const ZString Ptr, @winSystemCallNames(23))
    winSystemCallNames(24) = "HeapReAlloc"
    winSystemCallTable(24).zName = CPtr(Const ZString Ptr, @winSystemCallNames(24))
    winSystemCallNames(25) = "HeapSize"
    winSystemCallTable(25).zName = CPtr(Const ZString Ptr, @winSystemCallNames(25))
    winSystemCallNames(26) = "HeapValidate"
    winSystemCallTable(26).zName = CPtr(Const ZString Ptr, @winSystemCallNames(26))
    winSystemCallNames(27) = "HeapCompact"
    winSystemCallTable(27).zName = CPtr(Const ZString Ptr, @winSystemCallNames(27))
    winSystemCallNames(28) = "LoadLibraryW"
    winSystemCallTable(28).zName = CPtr(Const ZString Ptr, @winSystemCallNames(28))
    winSystemCallNames(29) = "LocalFree"
    winSystemCallTable(29).zName = CPtr(Const ZString Ptr, @winSystemCallNames(29))
    winSystemCallTable(29).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinLocalFree)
    winSystemCallNames(30) = "LockFileEx"
    winSystemCallTable(30).zName = CPtr(Const ZString Ptr, @winSystemCallNames(30))
    winSystemCallTable(30).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinLockFileEx)
    winSystemCallNames(31) = "MapViewOfFile"
    winSystemCallTable(31).zName = CPtr(Const ZString Ptr, @winSystemCallNames(31))
    winSystemCallNames(32) = "MapViewOfFileFromApp"
    winSystemCallTable(32).zName = CPtr(Const ZString Ptr, @winSystemCallNames(32))
    winSystemCallNames(33) = "MultiByteToWideChar"
    winSystemCallTable(33).zName = CPtr(Const ZString Ptr, @winSystemCallNames(33))
    winSystemCallTable(33).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinMultiByteToWideChar)
    winSystemCallNames(34) = "QueryPerformanceCounter"
    winSystemCallTable(34).zName = CPtr(Const ZString Ptr, @winSystemCallNames(34))
    winSystemCallTable(34).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinQueryPerformanceCounter)
    winSystemCallNames(35) = "ReadFile"
    winSystemCallTable(35).zName = CPtr(Const ZString Ptr, @winSystemCallNames(35))
    winSystemCallTable(35).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinReadFile)
    winSystemCallNames(36) = "SetEndOfFile"
    winSystemCallTable(36).zName = CPtr(Const ZString Ptr, @winSystemCallNames(36))
    winSystemCallTable(36).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinSetEndOfFile)
    winSystemCallNames(37) = "SetFilePointerEx"
    winSystemCallTable(37).zName = CPtr(Const ZString Ptr, @winSystemCallNames(37))
    winSystemCallTable(37).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinSetFilePointerEx)
    winSystemCallNames(38) = "Sleep"
    winSystemCallTable(38).zName = CPtr(Const ZString Ptr, @winSystemCallNames(38))
    winSystemCallTable(38).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinSleepMilliseconds)
    winSystemCallNames(39) = "UnlockFileEx"
    winSystemCallTable(39).zName = CPtr(Const ZString Ptr, @winSystemCallNames(39))
    winSystemCallTable(39).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinUnlockFileEx)
    winSystemCallNames(40) = "UnmapViewOfFile"
    winSystemCallTable(40).zName = CPtr(Const ZString Ptr, @winSystemCallNames(40))
    winSystemCallNames(41) = "WideCharToMultiByte"
    winSystemCallTable(41).zName = CPtr(Const ZString Ptr, @winSystemCallNames(41))
    winSystemCallTable(41).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinWideCharToMultiByte)
    winSystemCallNames(42) = "WriteFile"
    winSystemCallTable(42).zName = CPtr(Const ZString Ptr, @winSystemCallNames(42))
    winSystemCallTable(42).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinWriteFile)
    winSystemCallNames(43) = "WaitForSingleObject"
    winSystemCallTable(43).zName = CPtr(Const ZString Ptr, @winSystemCallNames(43))
    winSystemCallTable(43).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinWaitForSingleObject)
    winSystemCallNames(44) = "WaitForSingleObjectEx"
    winSystemCallTable(44).zName = CPtr(Const ZString Ptr, @winSystemCallNames(44))
    winSystemCallTable(44).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinWaitForSingleObjectEx)
    winSystemCallNames(45) = "OutputDebugStringA"
    winSystemCallTable(45).zName = CPtr(Const ZString Ptr, @winSystemCallNames(45))
    winSystemCallTable(45).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinOutputDebugStringA)
    winSystemCallNames(46) = "GetProcessHeap"
    winSystemCallTable(46).zName = CPtr(Const ZString Ptr, @winSystemCallNames(46))
    winSystemCallTable(46).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinMemGetProcessHeap)
    winSystemCallNames(47) = "InterlockedCompareExchange"
    winSystemCallTable(47).zName = CPtr(Const ZString Ptr, @winSystemCallNames(47))
    winSystemCallNames(48) = "UuidCreate"
    winSystemCallTable(48).zName = CPtr(Const ZString Ptr, @winSystemCallNames(48))
    winSystemCallNames(49) = "UuidCreateSequential"
    winSystemCallTable(49).zName = CPtr(Const ZString Ptr, @winSystemCallNames(49))
    winSystemCallNames(50) = "FlushViewOfFile"
    winSystemCallTable(50).zName = CPtr(Const ZString Ptr, @winSystemCallNames(50))
    winSystemCallNames(51) = "CreateEvent"
    winSystemCallTable(51).zName = CPtr(Const ZString Ptr, @winSystemCallNames(51))
    winSystemCallNames(52) = "CancelIo"
    winSystemCallTable(52).zName = CPtr(Const ZString Ptr, @winSystemCallNames(52))
    winSystemCallNames(53) = "getenv"
    winSystemCallTable(53).zName = CPtr(Const ZString Ptr, @winSystemCallNames(53))
    winSystemCallNames(54) = "getcwd"
    winSystemCallTable(54).zName = CPtr(Const ZString Ptr, @winSystemCallNames(54))
    winSystemCallNames(55) = "readlink"
    winSystemCallTable(55).zName = CPtr(Const ZString Ptr, @winSystemCallNames(55))
    winSystemCallNames(56) = "lstat"
    winSystemCallTable(56).zName = CPtr(Const ZString Ptr, @winSystemCallNames(56))
    winSystemCallNames(57) = "__errno"
    winSystemCallTable(57).zName = CPtr(Const ZString Ptr, @winSystemCallNames(57))
    winSystemCallNames(58) = "cygwin_conv_path"
    winSystemCallTable(58).zName = CPtr(Const ZString Ptr, @winSystemCallNames(58))
    winSystemCallNames(59) = "GetDriveTypeW"
    winSystemCallTable(59).zName = CPtr(Const ZString Ptr, @winSystemCallNames(59))
    winSystemCallTable(59).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinGetDriveTypeW)

#ifdef SQLITE3_FB_CYGWIN
    ' Cygwin supplies the POSIX calls which are null in native Win32 builds.
    winSystemCallTable(53).pCurrent = _
        CPtr(WinSystemCallPointer, @winDefaultCygwinGetenv)
    winSystemCallTable(54).pCurrent = _
        CPtr(WinSystemCallPointer, @winDefaultCygwinGetcwd)
    winSystemCallTable(55).pCurrent = _
        CPtr(WinSystemCallPointer, @winDefaultCygwinReadlink)
    winSystemCallTable(56).pCurrent = _
        CPtr(WinSystemCallPointer, @winDefaultCygwinLstat)
    winSystemCallTable(57).pCurrent = _
        CPtr(WinSystemCallPointer, @winDefaultCygwinErrno)
    winSystemCallTable(58).pCurrent = _
        CPtr(WinSystemCallPointer, @winDefaultCygwinConvPath)
#endif

#ifdef SQLITE_UWP
    winSystemCallTable(3).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinCreateFileMappingFromApp)
#endif

#if Not defined(SQLITE_OMIT_LOAD_EXTENSION) AndAlso Not defined(SQLITE_UWP)
    winSystemCallTable(15).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinGetProcAddress)
#endif

#ifndef InterlockedCompareExchange
    winSystemCallTable(47).pCurrent = _
        CPtr(WinSystemCallPointer, @winDefaultWinMemoryBarrierCompareExchange)
#endif

#ifndef SQLITE_UWP
    winSystemCallTable(20).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinMemHeapAlloc)
    winSystemCallTable(21).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinMemHeapCreate)
    winSystemCallTable(22).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinMemHeapDestroy)
    winSystemCallTable(23).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinMemHeapFree)
    winSystemCallTable(24).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinMemHeapRealloc)
    winSystemCallTable(25).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinMemHeapSize)
    winSystemCallTable(26).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinMemHeapValidate)
    winSystemCallTable(27).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinMemHeapCompact)
#endif

#if Not defined(SQLITE_OMIT_LOAD_EXTENSION) AndAlso Not defined(SQLITE_UWP)
    winSystemCallTable(28).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinLoadLibraryW)
#endif

#if (Not defined(SQLITE_OMIT_WAL) OrElse SQLITE_MAX_MMAP_SIZE > 0) AndAlso Not defined(SQLITE_UWP)
    winSystemCallTable(31).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinMapViewOfFile)
#endif

#if (Not defined(SQLITE_OMIT_WAL) OrElse SQLITE_MAX_MMAP_SIZE > 0) AndAlso defined(SQLITE_UWP)
    winSystemCallTable(32).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinMapViewOfFileFromApp)
#endif

#if SQLITE_WIN32_USE_UUID
    winSystemCallTable(48).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinUuidCreate)
    winSystemCallTable(49).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinUuidCreateSequential)
#endif

#if Not defined(SQLITE_NO_SYNC) AndAlso SQLITE_MAX_MMAP_SIZE > 0
    winSystemCallTable(50).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinFlushViewOfFile)
#endif

#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    winSystemCallTable(51).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinCreateEventW)
    winSystemCallTable(52).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinCancelIo)
#endif

#if Not defined(SQLITE_OMIT_WAL) OrElse SQLITE_MAX_MMAP_SIZE > 0
    winSystemCallTable(40).pCurrent = CPtr(WinSystemCallPointer, @winDefaultWinUnmapViewOfFile)
#endif

    winDefaultWinMemoryBarrierCompareExchange( _
        @winSystemCallTableReady, 2, 1)
End Sub

Function winSystemCallCurrent CDecl Alias "winSystemCallCurrent" ( _
    ByVal syscallIndex As SQLITE_C_INT _
) As WinSystemCallPointer
    If syscallIndex < 0 OrElse _
       syscallIndex >= SQLITE3_FB_WIN_SYSCALL_COUNT Then Return 0
    winInitializeSystemCallTable()
    Return winSystemCallTable(syscallIndex).pCurrent
End Function

Private Function winSetSystemCall CDecl Alias "winSetSystemCall" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal pNewFunc As WinSystemCallPointer _
) As SQLITE_C_INT
    ' Like SQLite's aSyscall table, overrides are not locked against I/O.
    ' Configure them before concurrent database operations begin.
    winInitializeSystemCallTable()
    Dim result As SQLITE_C_INT = SQLITE_NOTFOUND
    If zName = 0 Then
        result = SQLITE_OK
        For entryIndex As SQLITE_C_INT = 0 To SQLITE3_FB_WIN_SYSCALL_COUNT - 1
            If winSystemCallTable(entryIndex).pDefault <> 0 Then _
                winSystemCallTable(entryIndex).pCurrent = _
                    winSystemCallTable(entryIndex).pDefault
        Next
        Return result
    End If

    For entryIndex As SQLITE_C_INT = 0 To SQLITE3_FB_WIN_SYSCALL_COUNT - 1
        If winSystemCallNamesEqual(zName, winSystemCallTable(entryIndex).zName) <> 0 Then
            If winSystemCallTable(entryIndex).pDefault = 0 Then _
                winSystemCallTable(entryIndex).pDefault = _
                    winSystemCallTable(entryIndex).pCurrent
            result = SQLITE_OK
            If pNewFunc = 0 Then _
                pNewFunc = winSystemCallTable(entryIndex).pDefault
            winSystemCallTable(entryIndex).pCurrent = pNewFunc
            Exit For
        End If
    Next
    Return result
End Function

Private Function winGetSystemCall CDecl Alias "winGetSystemCall" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal zName As Const ZString Ptr _
) As WinSystemCallPointer
    winInitializeSystemCallTable()
    If zName = 0 Then Return 0
    For entryIndex As SQLITE_C_INT = 0 To SQLITE3_FB_WIN_SYSCALL_COUNT - 1
        If winSystemCallNamesEqual(zName, winSystemCallTable(entryIndex).zName) <> 0 Then _
            Return winSystemCallTable(entryIndex).pCurrent
    Next
    Return 0
End Function

Private Function winNextSystemCall CDecl Alias "winNextSystemCall" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal zName As Const ZString Ptr _
) As Const ZString Ptr
    winInitializeSystemCallTable()
    Dim firstIndex As SQLITE_C_INT = 0
    If zName <> 0 Then
        Dim foundName As SQLITE_C_INT = 0
        For entryIndex As SQLITE_C_INT = 0 To SQLITE3_FB_WIN_SYSCALL_COUNT - 2
            If winSystemCallNamesEqual(zName, winSystemCallTable(entryIndex).zName) <> 0 Then
                firstIndex = entryIndex + 1
                foundName = 1
                Exit For
            End If
        Next
        If foundName = 0 Then Return 0
    End If
    For entryIndex As SQLITE_C_INT = firstIndex To SQLITE3_FB_WIN_SYSCALL_COUNT - 1
        If winSystemCallTable(entryIndex).pCurrent <> 0 Then _
            Return winSystemCallTable(entryIndex).zName
    Next
    Return 0
End Function

#endif

/' end of sqlite3_os_win_syscall_table.bi '/
