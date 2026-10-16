/'
    Project: SQLite FreeBASIC port

    File: sqlite3_preupdate_types.bi

    Purpose:

        Describe SQLite's PreUpdate state fields used by callback and inspection code.

    Responsibilities:

        - Preserve the C field order through the inline key-info storage.
        - Type the statement, cursor, key-info, unpacked-record, table, and index fields.

    This file intentionally does NOT contain:

        - Binary layout equivalence for the inline flexible-array storage.
'/

#ifndef SQLITE3_FB_PREUPDATE_TYPES_BI
#define SQLITE3_FB_PREUPDATE_TYPES_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_vdbe_cursor.bi"
#include once "sqlite3_vdbe_record.bi"
#include once "sqlite3_schema_types.bi"

Type SqlitePreUpdateApiState
    v As SqliteVdbe Ptr
    pCsr As SqliteVdbeCursor Ptr
    op As SQLITE_C_INT
    aRecord As UByte Ptr
    pKeyinfo As sqlite3VdbeKeyInfoPrefix Ptr
    pUnpacked As sqlite3VdbeUnpackedRecord Ptr
    pNewUnpacked As sqlite3VdbeUnpackedRecord Ptr
    iNewReg As SQLITE_C_INT
    iBlobWrite As SQLITE_C_INT
    iKey1 As sqlite3_int64
    iKey2 As sqlite3_int64
    oldipk As SqliteVdbeMem
    aNew As SqliteVdbeMem Ptr
    pTab As SqliteTable Ptr
    pPk As SqliteIndex Ptr
    apDflt As SqliteVdbeMem Ptr Ptr
    ' The inline C byte area is represented by the corresponding key-info prefix.
    uKey As sqlite3VdbeKeyInfoPrefix
End Type

#endif

/' end of sqlite3_preupdate_types.bi '/
