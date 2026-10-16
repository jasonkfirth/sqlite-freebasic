/'
    Project: SQLite FreeBASIC port

    File: sqlite3_wal_types.bi

    Purpose:

        Define the internal WAL records shared by WAL implementation and
        translated helper modules.

    Responsibilities:

        - Match the fixed WAL handle and WAL-index records used by src/wal.c.
        - Keep optional record fields under the same feature guards as C.
        - Expose the flexible iterator element and write-state records.

    This file intentionally does NOT contain:

        - WAL locking, recovery, frame, checkpoint, or snapshot behavior.
        - Public SQLite API declarations.
'/

#ifndef SQLITE3_FB_WAL_TYPES_BI
#define SQLITE3_FB_WAL_TYPES_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_vfs.bi"
#include once "sqlite3_db_types.bi"

' These fields match WalIndexHdr in src/wal.c. The header follows the stable
' prefix of Wal and supplies the committed page count returned by sqlite3WalDbsize.
Type SqliteWalIndexHeader
    version As u32
    unused As u32
    changeCounter As u32
    isInitialized As u8
    bigEndianChecksum As u8
    pageSize As u16
    maxFrame As u32
    pageCount As u32
    frameChecksum(0 To 1) As u32
    salt(0 To 1) As u32
    checksum(0 To 1) As u32
End Type

Type SqliteWalCheckpointInfo
    nBackfill As u32
    readMark(0 To 4) As u32
    lockBytes(0 To 7) As u8
    nBackfillAttempted As u32
    unused As u32
End Type

Type SqliteWalHashLocation
    aPgno As u32 Ptr
    aHash As UShort Ptr
    iZero As u32
End Type

' Iterator segments point into one allocation containing the segment array and
' either sorted hash-slot indices or a page-number map.
Type SqliteWalSegment
    iNext As SQLITE_C_INT
    aIndex As UShort Ptr
    aPgno As u32 Ptr
    nEntry As SQLITE_C_INT
    iZero As u32
End Type

Type SqliteWalIterator
    iPrior As u32
    nSegment As SQLITE_C_INT
    nPagemap As u32
    aSegment(0 To 0) As SqliteWalSegment
End Type

' This layout matches struct Wal in src/wal.c. Option-gated tail fields use
' the same feature guards so field offsets remain aligned in each profile.
Type SqliteWal
    pVfs As sqlite3_vfs Ptr
    pDbFile As sqlite3_file Ptr
    pWalFile As sqlite3_file Ptr
    callbackValue As u32
    maxWalSize As i64
    walIndexDataCount As SQLITE_C_INT
    firstBlockSize As SQLITE_C_INT
    walIndexData As u32 Ptr Ptr
    pageSize As u32
    readLock As Short
    syncFlags As u8
    exclusiveMode As u8
    writeLock As u8
    checkpointLock As u8
    readOnly As u8
    truncateOnCommit As u8
    syncHeader As u8
    padToSectorBoundary As u8
    sharedMemoryUnreliable As u8
    header As SqliteWalIndexHeader
    minFrame As u32
    recalculateChecksumFrame As u32
    walName As Const ZString Ptr
    checkpointSequence As u32
#ifdef SQLITE_USE_SEH
    lockMask As u32
    pFree As Any Ptr
    pWalIndexValue As u32 Ptr
    walIndexPage As SQLITE_C_INT
    systemErrorNumber As SQLITE_C_INT
#endif
#ifdef SQLITE_DEBUG
    sehTryCount As SQLITE_C_INT
    lockError As u8
#endif
#ifdef SQLITE_ENABLE_SNAPSHOT
    pSnapshot As SqliteWalIndexHeader Ptr
    getSnapshot As SQLITE_C_INT
#endif
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    db As sqlite3 Ptr
#endif
End Type

' Per-batch write state carries the VFS file and sector boundary across frame writes.
Type SqliteWalWriter
    pWal As SqliteWal Ptr
    pFile As sqlite3_file Ptr
    syncPoint As sqlite3_int64
    syncFlags As SQLITE_C_INT
    pageSize As SQLITE_C_INT
End Type


Type SqliteWalBusyCallback As Function CDecl ( _
    ByVal pBusyArg As Any Ptr _
) As SQLITE_C_INT


#endif

/' end of sqlite3_wal_types.bi '/
