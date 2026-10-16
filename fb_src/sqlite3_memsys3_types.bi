/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_memsys3_types.bi

    Purpose:

        Define the block and allocator-state records used by SQLite's
        optional MEMSYS3 allocator.

    Responsibilities:

        - Preserve the eight-byte block header and free-list union.
        - Store the allocator's pool pointer, mutex, and free-list indexes.
        - Give C2FB the field types needed to translate MEMSYS3 routines.

    This file intentionally does NOT contain:

        - Allocation policy or mutex operations.
        - The allocator callback table.
'/

#ifndef SQLITE3_FB_MEMSYS3_TYPES_BI
#define SQLITE3_FB_MEMSYS3_TYPES_BI

#include once "sqlite3_types.bi"

Type SqliteMem3BlockHeader
    prevSize As u32
    size4x As u32
End Type

Type SqliteMem3BlockList
    nextBlock As u32
    previousBlock As u32
End Type

Type SqliteMem3BlockUnion
    Union
        hdr As SqliteMem3BlockHeader
        list As SqliteMem3BlockList
    End Union
End Type

Type SqliteMem3Block
    u As SqliteMem3BlockUnion
End Type

Type SqliteMem3Global
    nPool As u32
    aPool As SqliteMem3Block Ptr
    alarmBusy As SQLITE_C_INT
    mutex As Any Ptr
    mnKeyBlk As u32
    iKeyBlk As u32
    szKeyBlk As u32
    aiSmall(0 To 8) As u32
    aiHash(0 To 60) As u32
End Type

#ifdef SQLITE_ENABLE_MEMSYS3
Extern mem3 As SqliteMem3Global
#endif

#endif

/' end of sqlite3_memsys3_types.bi '/
