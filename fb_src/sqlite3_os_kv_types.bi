/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_os_kv_types.bi

    Purpose:

        Describe the fixed file record used by SQLite's optional key-value VFS.

    Responsibilities:

        - Preserve the public sqlite3_file prefix and KVVfsFile field widths.
        - Describe Linux x86-64 stat and timeval records used by the file backend.
        - Make the record available to the C2FB optional-profile batch.

    This file intentionally does NOT contain:

        - Key-value record storage, VFS callbacks, or registration.
        - A claim that runtime file offsets have been compared with C.
'/

#ifndef SQLITE3_FB_OS_KV_TYPES_BI
#define SQLITE3_FB_OS_KV_TYPES_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_vfs.bi"

Type SqliteKvvfsFile
    base As sqlite3_file
    zClass As Const ZString Ptr
    isJournal As SQLITE_C_INT
    nJrnl As SQLITE_C_UINT
    aJrnl As ZString Ptr
    szPage As SQLITE_C_INT
    szDb As sqlite3_int64
    aData As ZString Ptr
End Type

' Linux x86-64 struct stat layout for the optional Unix file backend.
Type SqliteKvvfsStat
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

' Linux x86-64 timeval layout used by gettimeofday().
Type SqliteKvvfsTimeval
    tvSec As sqlite3_int64
    tvUsec As sqlite3_int64
End Type

Type SqliteKvvfsRecordReadProc As Function CDecl ( _
    ByVal zClass As Const ZString Ptr, _
    ByVal zKey As Const ZString Ptr, _
    ByVal zBuffer As ZString Ptr, _
    ByVal nBuffer As SQLITE_C_INT _
) As SQLITE_C_INT
Type SqliteKvvfsRecordWriteProc As Function CDecl ( _
    ByVal zClass As Const ZString Ptr, _
    ByVal zKey As Const ZString Ptr, _
    ByVal zData As Const ZString Ptr _
) As SQLITE_C_INT
Type SqliteKvvfsRecordDeleteProc As Function CDecl ( _
    ByVal zClass As Const ZString Ptr, _
    ByVal zKey As Const ZString Ptr _
) As SQLITE_C_INT

Type SqliteKvvfsMethods
    xRcrdRead As SqliteKvvfsRecordReadProc
    xRcrdWrite As SqliteKvvfsRecordWriteProc
    xRcrdDelete As SqliteKvvfsRecordDeleteProc
    nKeySize As SQLITE_C_INT
    nBufferSize As SQLITE_C_INT
    pVfs As sqlite3_vfs Ptr
    pIoDb As sqlite3_io_methods Ptr
    pIoJrnl As sqlite3_io_methods Ptr
End Type

Declare Function sqlite3KvvfsMethodsPtr CDecl Alias "sqlite3KvvfsMethodsPtr" () _
    As SqliteKvvfsMethods Ptr
Declare Function sqlite3KvHexValueTablePtr CDecl Alias "sqlite3KvHexValueTablePtr" () _
    As Const Byte Ptr

#endif

/' end of sqlite3_os_kv_types.bi '/
