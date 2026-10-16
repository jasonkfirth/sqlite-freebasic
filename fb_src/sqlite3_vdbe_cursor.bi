/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_cursor.bi

    Purpose:

        Define the VDBE cursor prefix and its variable-sized storage layout.

    Responsibilities:

        - Match VdbeCursor fields that precede the flexible record-type array.
        - Describe the embedded B-tree cursor allocation and cursor kinds.
        - Define the large TEXT/BLOB value cache owned by a cursor.
        - Declare the allocator used by VDBE cursor-open opcodes.
        - Declare the cursor release and frame cleanup entry points.

    This file intentionally does NOT contain:

        - Sorter, virtual-table, cursor-cache, or row decoding algorithms.
'/

#ifndef SQLITE3_FB_VDBE_CURSOR_BI
#define SQLITE3_FB_VDBE_CURSOR_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_btree.bi"

#define CURTYPE_BTREE 0
#define CURTYPE_SORTER 1
#define CURTYPE_VTAB 2
#define CURTYPE_PSEUDO 3
#define CACHE_STALE 0

#define VDBE_CURSOR_EPHEMERAL &H01
#define VDBE_CURSOR_RANDOM_ROWID &H02
#define VDBE_CURSOR_ORDERED &H04
#define VDBE_CURSOR_NO_REUSE &H08
#define VDBE_CURSOR_COLUMN_CACHE &H10

Union SqliteVdbeCursorBtreeUnion
    pBtx As Btree Ptr
    aAltMap As u32 Ptr
End Union

Union SqliteVdbeCursorObjectUnion
    pCursor As BtCursor Ptr
    pVtabCursor As Any Ptr
    pSorter As Any Ptr
End Union

Type SqliteVdbeTextBlobCache
    pCValue As ZString Ptr
    iOffset As sqlite3_int64
    iCol As SQLITE_C_INT
    cacheStatus As u32
    colCacheCtr As u32
End Type

Type SqliteVdbeCursor
    eCurType As u8
    iDb As Byte
    nullRow As u8
    deferredMoveto As u8
    isTable As u8
#ifdef SQLITE_DEBUG
    seekOp As u8
    wrFlag As u8
#endif
    cursorFlags As u32
    seekHit As u16
    ub As SqliteVdbeCursorBtreeUnion
    seqCount As sqlite3_int64
    cacheStatus As u32
    seekResult As SQLITE_C_INT
    pAltCursor As SqliteVdbeCursor Ptr
    uc As SqliteVdbeCursorObjectUnion
    pKeyInfo As Any Ptr
    iHdrOffset As u32
    pgnoRoot As u32
    nField As Short
    nHdrParsed As u16
    movetoTarget As sqlite3_int64
    aOffset As u32 Ptr
    aRow As Const UByte Ptr
    payloadSize As u32
    szRow As u32
#ifdef SQLITE_ENABLE_COLUMN_USED_MASK
    maskUsed As u64
#endif
    pCache As Any Ptr
End Type

Declare Function allocateCursor CDecl Alias "allocateCursor" ( _
    ByVal pVdbe As Any Ptr, _
    ByVal cursorIndex As SQLITE_C_INT, _
    ByVal fieldCount As SQLITE_C_INT, _
    ByVal cursorType As u8 _
) As SqliteVdbeCursor Ptr
Declare Function sqlite3VdbeHandleMovedCursor CDecl Alias "sqlite3VdbeHandleMovedCursor" ( _
    ByVal pCursor As SqliteVdbeCursor Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3VdbeFreeCursor CDecl Alias "sqlite3VdbeFreeCursor" ( _
    ByVal pVdbe As Any Ptr, _
    ByVal pCursor As SqliteVdbeCursor Ptr _
)
Declare Sub sqlite3VdbeFreeCursorNN CDecl Alias "sqlite3VdbeFreeCursorNN" ( _
    ByVal pVdbe As Any Ptr, _
    ByVal pCursor As SqliteVdbeCursor Ptr _
)
Declare Sub closeCursorsInFrame CDecl Alias "closeCursorsInFrame" ( _
    ByVal pVdbe As Any Ptr _
)
Declare Sub sqlite3VdbeSorterClose CDecl Alias "sqlite3VdbeSorterClose" ( _
    ByVal pDb As Any Ptr, _
    ByVal pCursor As SqliteVdbeCursor Ptr _
)
Declare Function sqlite3VdbeSorterInit CDecl Alias "sqlite3VdbeSorterInit" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal nField As SQLITE_C_INT, _
    ByVal pCursor As SqliteVdbeCursor Ptr _
) As SQLITE_C_INT

#endif

/' end of sqlite3_vdbe_cursor.bi '/
