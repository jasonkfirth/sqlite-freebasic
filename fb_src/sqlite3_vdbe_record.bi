/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_record.bi

    Purpose:

        Declare VDBE record helpers and the KeyInfo reference-count layout.

    Responsibilities:

        - Preserve FreeBASIC record Mem and KeyInfo prefix layouts.
        - Pack already-affinitized Mem cells and unpack bounded record data.
        - Expose KeyInfo reference and release operations.
        - Hold the fixed serial-type length table used by VDBE records.

    This file intentionally does NOT contain:

        - VDBE opcode dispatch, table/page writes, or index-key comparison.
'/

#ifndef SQLITE3_FB_VDBE_RECORD_BI
#define SQLITE3_FB_VDBE_RECORD_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_vdbe_compare.bi"


' Serial payload byte counts for the compact serial-type range.
Dim Shared As Const UByte sqlite3SmallTypeSizes(0 To 127) = { _
    0, 1, 2, 3, 4, 6, 8, 8, 0, 0, 0, 0, 0, 0, 1, 1, _
    2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, _
    10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15, 16, 16, 17, 17, _
    18, 18, 19, 19, 20, 20, 21, 21, 22, 22, 23, 23, 24, 24, 25, 25, _
    26, 26, 27, 27, 28, 28, 29, 29, 30, 30, 31, 31, 32, 32, 33, 33, _
    34, 34, 35, 35, 36, 36, 37, 37, 38, 38, 39, 39, 40, 40, 41, 41, _
    42, 42, 43, 43, 44, 44, 45, 45, 46, 46, 47, 47, 48, 48, 49, 49, _
    50, 50, 51, 51, 52, 52, 53, 53, 54, 54, 55, 55, 56, 56, 57, 57 _
}

Type sqlite3VdbeKeyInfoPrefix
    nRef As u32
    enc As u8
    nKeyField As UShort
    nAllField As UShort
    db As sqlite3 Ptr
    aSortFlags As UByte Ptr
    aColl(0 To 0) As sqlite3CollSeq Ptr
End Type

Union sqlite3VdbeRecordCache
    z As ZString Ptr
    i As sqlite3_int64
End Union

Type sqlite3VdbeUnpackedRecord
    pKeyInfo As Any Ptr
    aMem As SqliteVdbeMem Ptr
    u As sqlite3VdbeRecordCache
    n As SQLITE_C_INT
    nField As UShort
    default_rc As Byte
    errCode As u8
    r1 As Byte
    r2 As Byte
    eqSeen As u8
End Type

Declare Function sqlite3VdbeRecordPack CDecl Alias "sqlite3VdbeRecordPack" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pOutput As Any Ptr, _
    ByVal pValues As Any Ptr, _
    ByVal fieldCount As SQLITE_C_INT, _
    ByVal fileFormat As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3KeyInfoRef CDecl Alias "sqlite3KeyInfoRef" ( _
    ByVal pKeyInfo As sqlite3VdbeKeyInfoPrefix Ptr _
) As sqlite3VdbeKeyInfoPrefix Ptr
Declare Sub sqlite3KeyInfoUnref CDecl Alias "sqlite3KeyInfoUnref" ( _
    ByVal pKeyInfo As sqlite3VdbeKeyInfoPrefix Ptr _
)
Declare Sub sqlite3VdbeRecordUnpack CDecl Alias "sqlite3VdbeRecordUnpack" ( _
    ByVal nKey As SQLITE_C_INT, _
    ByVal pKey As Const Any Ptr, _
    ByVal pRecord As Any Ptr _
)
Declare Function sqlite3VdbeRecordReadVarint32 ( _
    ByVal zRecord As Const UByte Ptr, _
    ByVal endOffset As Long, _
    ByRef offset As Long, _
    ByRef value As u32 _
) As Long
#endif

/' end of sqlite3_vdbe_record.bi '/
