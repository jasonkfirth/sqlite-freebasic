/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_memdb_types.bi

    Purpose:

        Share the internal record layouts used by the memory database VFS.

    Responsibilities:

        - Define the backing store, file handle, and shared-store registry.
        - Make the VFS-owned record fields available to C2FB-generated helpers.

    This file intentionally does NOT contain:

        - Public SQLite VFS declarations or file-operation implementations.
'/

#ifndef SQLITE3_FB_MEMDB_TYPES_BI
#define SQLITE3_FB_MEMDB_TYPES_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_vfs.bi"

Type MemdbStore
    sz As sqlite3_int64
    szAlloc As sqlite3_int64
    szMax As sqlite3_int64
    aData As UByte Ptr
    pMutex As Any Ptr
    nMmap As SQLITE_C_INT
    mFlags As SQLITE_C_UINT
    nRdLock As SQLITE_C_INT
    nWrLock As SQLITE_C_INT
    nRef As SQLITE_C_INT
    zFName As ZString Ptr
End Type

Type MemdbFile
    base As sqlite3_file
    pStore As MemdbStore Ptr
    eLock As SQLITE_C_INT
End Type

Type MemdbFileSystem
    nMemStore As SQLITE_C_INT
    apMemStore As MemdbStore Ptr Ptr
End Type

#endif

/' end of sqlite3_memdb_types.bi '/
