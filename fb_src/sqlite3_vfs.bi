/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vfs.bi

    Purpose:

        Define SQLite's public file and virtual-file-system layouts.

    Responsibilities:

        - Preserve the C ABI for sqlite3_file, sqlite3_io_methods, and sqlite3_vfs.
        - Declare file-method dispatch and VFS registration entry points.

    This file intentionally does NOT contain:

        - A host operating-system VFS implementation.
        - Library initialization or default-VFS selection policy.
'/ 

#ifndef SQLITE3_FB_VFS_BI
#define SQLITE3_FB_VFS_BI

#include once "sqlite3_types.bi"

#define SQLITE_DEFAULT_SECTOR_SIZE 4096
#define SQLITE_ACCESS_EXISTS 0
#define SQLITE_ACCESS_READWRITE 1
#define SQLITE_ACCESS_READ 2
#define SQLITE_SHM_UNLOCK 1
#define SQLITE_SHM_LOCK 2
#define SQLITE_SHM_SHARED 4
#define SQLITE_SHM_EXCLUSIVE 8
#define SQLITE_SHM_NLOCK 8

Type SqliteFileCloseProc As Function CDecl (ByVal pFile As Any Ptr) As SQLITE_C_INT
Type SqliteFileReadProc As Function CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal pBuffer As Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal offset As sqlite3_int64 _
) As SQLITE_C_INT
Type SqliteFileWriteProc As Function CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal pBuffer As Const Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal offset As sqlite3_int64 _
) As SQLITE_C_INT
Type SqliteFileTruncateProc As Function CDecl (ByVal pFile As Any Ptr, ByVal size As sqlite3_int64) As SQLITE_C_INT
Type SqliteFileSyncProc As Function CDecl (ByVal pFile As Any Ptr, ByVal flags As SQLITE_C_INT) As SQLITE_C_INT
Type SqliteFileSizeProc As Function CDecl (ByVal pFile As Any Ptr, ByVal pSize As sqlite3_int64 Ptr) As SQLITE_C_INT
Type SqliteFileLockProc As Function CDecl (ByVal pFile As Any Ptr, ByVal lockLevel As SQLITE_C_INT) As SQLITE_C_INT
Type SqliteFileCheckReservedProc As Function CDecl (ByVal pFile As Any Ptr, ByVal pResult As SQLITE_C_INT Ptr) As SQLITE_C_INT
Type SqliteFileControlProc As Function CDecl (ByVal pFile As Any Ptr, ByVal operation As SQLITE_C_INT, ByVal pArgument As Any Ptr) As SQLITE_C_INT
Type SqliteFileSectorSizeProc As Function CDecl (ByVal pFile As Any Ptr) As SQLITE_C_INT
Type SqliteFileDeviceCharacteristicsProc As Function CDecl (ByVal pFile As Any Ptr) As SQLITE_C_INT
Type SqliteFileShmMapProc As Function CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal pageNumber As SQLITE_C_INT, _
    ByVal pageSize As SQLITE_C_INT, _
    ByVal extendFlag As SQLITE_C_INT, _
    ByVal ppPage As Any Ptr Ptr _
) As SQLITE_C_INT
Type SqliteFileShmLockProc As Function CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal offset As SQLITE_C_INT, _
    ByVal count As SQLITE_C_INT, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT
Type SqliteFileShmBarrierProc As Sub CDecl (ByVal pFile As Any Ptr)
Type SqliteFileShmUnmapProc As Function CDecl (ByVal pFile As Any Ptr, ByVal deleteFlag As SQLITE_C_INT) As SQLITE_C_INT
Type SqliteFileFetchProc As Function CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal offset As sqlite3_int64, _
    ByVal amount As SQLITE_C_INT, _
    ByVal ppBuffer As Any Ptr Ptr _
) As SQLITE_C_INT
Type SqliteFileUnfetchProc As Function CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal offset As sqlite3_int64, _
    ByVal pBuffer As Any Ptr _
) As SQLITE_C_INT

Type sqlite3_io_methods
    iVersion As SQLITE_C_INT
    xClose As SqliteFileCloseProc
    xRead As SqliteFileReadProc
    xWrite As SqliteFileWriteProc
    xTruncate As SqliteFileTruncateProc
    xSync As SqliteFileSyncProc
    xFileSize As SqliteFileSizeProc
    xLock As SqliteFileLockProc
    xUnlock As SqliteFileLockProc
    xCheckReservedLock As SqliteFileCheckReservedProc
    xFileControl As SqliteFileControlProc
    xSectorSize As SqliteFileSectorSizeProc
    xDeviceCharacteristics As SqliteFileDeviceCharacteristicsProc
    xShmMap As SqliteFileShmMapProc
    xShmLock As SqliteFileShmLockProc
    xShmBarrier As SqliteFileShmBarrierProc
    xShmUnmap As SqliteFileShmUnmapProc
    xFetch As SqliteFileFetchProc
    xUnfetch As SqliteFileUnfetchProc
End Type

Type sqlite3_file
    pMethods As sqlite3_io_methods Ptr
End Type

Type SqliteVfsOpenProc As Function CDecl ( _
    ByVal pVfs As Any Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal pOutFlags As SQLITE_C_INT Ptr _
) As SQLITE_C_INT
Type SqliteVfsDeleteProc As Function CDecl (ByVal pVfs As Any Ptr, ByVal zName As Const ZString Ptr, ByVal syncDirectory As SQLITE_C_INT) As SQLITE_C_INT
Type SqliteVfsAccessProc As Function CDecl (ByVal pVfs As Any Ptr, ByVal zName As Const ZString Ptr, ByVal flags As SQLITE_C_INT, ByVal pResult As SQLITE_C_INT Ptr) As SQLITE_C_INT
Type SqliteVfsFullPathnameProc As Function CDecl ( _
    ByVal pVfs As Any Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal outputSize As SQLITE_C_INT, _
    ByVal zOutput As ZString Ptr _
) As SQLITE_C_INT
Type SqliteVfsDlOpenProc As Function CDecl (ByVal pVfs As Any Ptr, ByVal zName As Const ZString Ptr) As Any Ptr
Type SqliteVfsDlErrorProc As Sub CDecl (ByVal pVfs As Any Ptr, ByVal outputSize As SQLITE_C_INT, ByVal zOutput As ZString Ptr)
Type SqliteVfsDlSymProc As Function CDecl (ByVal pVfs As Any Ptr, ByVal pHandle As Any Ptr, ByVal zSymbol As Const ZString Ptr) As Any Ptr
Type SqliteVfsDlCloseProc As Sub CDecl (ByVal pVfs As Any Ptr, ByVal pHandle As Any Ptr)
Type SqliteVfsRandomnessProc As Function CDecl (ByVal pVfs As Any Ptr, ByVal amount As SQLITE_C_INT, ByVal zOutput As ZString Ptr) As SQLITE_C_INT
Type SqliteVfsSleepProc As Function CDecl (ByVal pVfs As Any Ptr, ByVal microseconds As SQLITE_C_INT) As SQLITE_C_INT
Type SqliteVfsCurrentTimeProc As Function CDecl (ByVal pVfs As Any Ptr, ByVal pJulianDay As Double Ptr) As SQLITE_C_INT
Type SqliteVfsGetLastErrorProc As Function CDecl (ByVal pVfs As Any Ptr, ByVal outputSize As SQLITE_C_INT, ByVal zOutput As ZString Ptr) As SQLITE_C_INT
Type SqliteVfsCurrentTimeInt64Proc As Function CDecl (ByVal pVfs As Any Ptr, ByVal pJulianDay As sqlite3_int64 Ptr) As SQLITE_C_INT
Type SqliteVfsSetSystemCallProc As Function CDecl (ByVal pVfs As Any Ptr, ByVal zName As Const ZString Ptr, ByVal pCall As Any Ptr) As SQLITE_C_INT
Type SqliteVfsGetSystemCallProc As Function CDecl (ByVal pVfs As Any Ptr, ByVal zName As Const ZString Ptr) As Any Ptr
Type SqliteVfsNextSystemCallProc As Function CDecl (ByVal pVfs As Any Ptr, ByVal zName As Const ZString Ptr) As Const ZString Ptr

Type sqlite3_vfs
    iVersion As SQLITE_C_INT
    szOsFile As SQLITE_C_INT
    mxPathname As SQLITE_C_INT
    pNext As sqlite3_vfs Ptr
    zName As Const ZString Ptr
    pAppData As Any Ptr
    xOpen As SqliteVfsOpenProc
    xDelete As SqliteVfsDeleteProc
    xAccess As SqliteVfsAccessProc
    xFullPathname As SqliteVfsFullPathnameProc
    xDlOpen As SqliteVfsDlOpenProc
    xDlError As SqliteVfsDlErrorProc
    xDlSym As SqliteVfsDlSymProc
    xDlClose As SqliteVfsDlCloseProc
    xRandomness As SqliteVfsRandomnessProc
    xSleep As SqliteVfsSleepProc
    xCurrentTime As SqliteVfsCurrentTimeProc
    xGetLastError As SqliteVfsGetLastErrorProc
    xCurrentTimeInt64 As SqliteVfsCurrentTimeInt64Proc
    xSetSystemCall As SqliteVfsSetSystemCallProc
    xGetSystemCall As SqliteVfsGetSystemCallProc
    xNextSystemCall As SqliteVfsNextSystemCallProc
End Type

Declare Sub sqlite3OsClose CDecl Alias "sqlite3OsClose" (ByVal pFile As sqlite3_file Ptr)
Declare Function sqlite3OsRead CDecl Alias "sqlite3OsRead" (ByVal pFile As sqlite3_file Ptr, ByVal pBuffer As Any Ptr, ByVal amount As SQLITE_C_INT, ByVal offset As sqlite3_int64) As SQLITE_C_INT
Declare Function sqlite3OsWrite CDecl Alias "sqlite3OsWrite" (ByVal pFile As sqlite3_file Ptr, ByVal pBuffer As Const Any Ptr, ByVal amount As SQLITE_C_INT, ByVal offset As sqlite3_int64) As SQLITE_C_INT
Declare Function sqlite3OsTruncate CDecl Alias "sqlite3OsTruncate" (ByVal pFile As sqlite3_file Ptr, ByVal size As sqlite3_int64) As SQLITE_C_INT
Declare Function sqlite3OsSync CDecl Alias "sqlite3OsSync" (ByVal pFile As sqlite3_file Ptr, ByVal flags As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3OsFileSize CDecl Alias "sqlite3OsFileSize" (ByVal pFile As sqlite3_file Ptr, ByVal pSize As sqlite3_int64 Ptr) As SQLITE_C_INT
Declare Function sqlite3OsLock CDecl Alias "sqlite3OsLock" (ByVal pFile As sqlite3_file Ptr, ByVal lockLevel As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3OsUnlock CDecl Alias "sqlite3OsUnlock" (ByVal pFile As sqlite3_file Ptr, ByVal lockLevel As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3OsCheckReservedLock CDecl Alias "sqlite3OsCheckReservedLock" (ByVal pFile As sqlite3_file Ptr, ByVal pResult As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function sqlite3OsFileControl CDecl Alias "sqlite3OsFileControl" (ByVal pFile As sqlite3_file Ptr, ByVal operation As SQLITE_C_INT, ByVal pArgument As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3OsFileControlHint CDecl Alias "sqlite3OsFileControlHint" (ByVal pFile As sqlite3_file Ptr, ByVal operation As SQLITE_C_INT, ByVal pArgument As Any Ptr)
Declare Function sqlite3OsSectorSize CDecl Alias "sqlite3OsSectorSize" (ByVal pFile As sqlite3_file Ptr) As SQLITE_C_INT
Declare Function sqlite3OsDeviceCharacteristics CDecl Alias "sqlite3OsDeviceCharacteristics" (ByVal pFile As sqlite3_file Ptr) As SQLITE_C_INT
Declare Function sqlite3OsShmMap CDecl Alias "sqlite3OsShmMap" (ByVal pFile As sqlite3_file Ptr, ByVal pageNumber As SQLITE_C_INT, ByVal pageSize As SQLITE_C_INT, ByVal extendFlag As SQLITE_C_INT, ByVal ppPage As Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3OsShmLock CDecl Alias "sqlite3OsShmLock" (ByVal pFile As sqlite3_file Ptr, ByVal offset As SQLITE_C_INT, ByVal count As SQLITE_C_INT, ByVal flags As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub sqlite3OsShmBarrier CDecl Alias "sqlite3OsShmBarrier" (ByVal pFile As sqlite3_file Ptr)
Declare Function sqlite3OsShmUnmap CDecl Alias "sqlite3OsShmUnmap" (ByVal pFile As sqlite3_file Ptr, ByVal deleteFlag As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3OsFetch CDecl Alias "sqlite3OsFetch" (ByVal pFile As sqlite3_file Ptr, ByVal offset As sqlite3_int64, ByVal amount As SQLITE_C_INT, ByVal ppBuffer As Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3OsUnfetch CDecl Alias "sqlite3OsUnfetch" (ByVal pFile As sqlite3_file Ptr, ByVal offset As sqlite3_int64, ByVal pBuffer As Any Ptr) As SQLITE_C_INT

Declare Function sqlite3OsOpen CDecl Alias "sqlite3OsOpen" (ByVal pVfs As sqlite3_vfs Ptr, ByVal zName As Const ZString Ptr, ByVal pFile As sqlite3_file Ptr, ByVal flags As SQLITE_C_INT, ByVal pOutFlags As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function sqlite3OsDelete CDecl Alias "sqlite3OsDelete" (ByVal pVfs As sqlite3_vfs Ptr, ByVal zName As Const ZString Ptr, ByVal syncDirectory As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3OsAccess CDecl Alias "sqlite3OsAccess" (ByVal pVfs As sqlite3_vfs Ptr, ByVal zName As Const ZString Ptr, ByVal flags As SQLITE_C_INT, ByVal pResult As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function sqlite3OsFullPathname CDecl Alias "sqlite3OsFullPathname" (ByVal pVfs As sqlite3_vfs Ptr, ByVal zName As Const ZString Ptr, ByVal outputSize As SQLITE_C_INT, ByVal zOutput As ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3OsDlOpen CDecl Alias "sqlite3OsDlOpen" (ByVal pVfs As sqlite3_vfs Ptr, ByVal zName As Const ZString Ptr) As Any Ptr
Declare Sub sqlite3OsDlError CDecl Alias "sqlite3OsDlError" (ByVal pVfs As sqlite3_vfs Ptr, ByVal outputSize As SQLITE_C_INT, ByVal zOutput As ZString Ptr)
Declare Function sqlite3OsDlSym CDecl Alias "sqlite3OsDlSym" (ByVal pVfs As sqlite3_vfs Ptr, ByVal pHandle As Any Ptr, ByVal zSymbol As Const ZString Ptr) As Any Ptr
Declare Sub sqlite3OsDlClose CDecl Alias "sqlite3OsDlClose" (ByVal pVfs As sqlite3_vfs Ptr, ByVal pHandle As Any Ptr)
Declare Function sqlite3OsRandomness CDecl Alias "sqlite3OsRandomness" (ByVal pVfs As sqlite3_vfs Ptr, ByVal amount As SQLITE_C_INT, ByVal zOutput As ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3OsSleep CDecl Alias "sqlite3OsSleep" (ByVal pVfs As sqlite3_vfs Ptr, ByVal microseconds As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3OsGetLastError CDecl Alias "sqlite3OsGetLastError" (ByVal pVfs As sqlite3_vfs Ptr) As SQLITE_C_INT
Declare Function sqlite3OsCurrentTimeInt64 CDecl Alias "sqlite3OsCurrentTimeInt64" (ByVal pVfs As sqlite3_vfs Ptr, ByVal pJulianDay As sqlite3_int64 Ptr) As SQLITE_C_INT
Declare Function sqlite3OsOpenMalloc CDecl Alias "sqlite3OsOpenMalloc" (ByVal pVfs As sqlite3_vfs Ptr, ByVal zName As Const ZString Ptr, ByVal ppFile As sqlite3_file Ptr Ptr, ByVal flags As SQLITE_C_INT, ByVal pOutFlags As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Sub sqlite3OsCloseFree CDecl Alias "sqlite3OsCloseFree" (ByVal pFile As sqlite3_file Ptr)
Declare Function sqlite3OsInit CDecl Alias "sqlite3OsInit" () As SQLITE_C_INT

Declare Function sqlite3_vfs_find CDecl Alias "sqlite3_vfs_find" (ByVal zName As Const ZString Ptr) As sqlite3_vfs Ptr
Declare Function sqlite3_vfs_register CDecl Alias "sqlite3_vfs_register" (ByVal pVfs As sqlite3_vfs Ptr, ByVal makeDefault As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_vfs_unregister CDecl Alias "sqlite3_vfs_unregister" (ByVal pVfs As sqlite3_vfs Ptr) As SQLITE_C_INT

#endif

/' end of sqlite3_vfs.bi '/
