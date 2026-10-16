/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_serial.bi

    Purpose:

        Declare SQLite VDBE serial-type selection, field encoding, and decoding.

    Responsibilities:

        - Preserve C ABI for serial-type selection, length, and Mem decoding.
        - Keep record format primitives separate from Mem value lifecycle.

    This file intentionally does NOT contain:

        - Full multi-column record assembly, record comparison, or B-tree I/O.
'/

#ifndef SQLITE3_FB_VDBE_SERIAL_BI
#define SQLITE3_FB_VDBE_SERIAL_BI

#include once "sqlite3_types.bi"

#ifdef SQLITE_MIXED_ENDIAN_64BIT_FLOAT
Declare Function sqlite3FloatSwap CDecl Alias "sqlite3FloatSwap" ( _
    ByVal value As sqlite3_uint64 _
) As sqlite3_uint64
#endif

Declare Function sqlite3VdbeSerialTypeLen CDecl Alias "sqlite3VdbeSerialTypeLen" ( _
    ByVal serialType As u32 _
) As u32
Declare Function sqlite3VdbeOneByteSerialTypeLen CDecl Alias "sqlite3VdbeOneByteSerialTypeLen" ( _
    ByVal serialType As u8 _
) As u8
Declare Function sqlite3VdbeSerialType CDecl Alias "sqlite3VdbeSerialType" ( _
    ByVal pMem As Any Ptr, _
    ByVal fileFormat As SQLITE_C_INT, _
    ByVal pLength As SQLITE_C_UINT Ptr _
) As SQLITE_C_UINT
Declare Sub sqlite3VdbeSerialGet CDecl Alias "sqlite3VdbeSerialGet" ( _
    ByVal zData As Const UByte Ptr, _
    ByVal serialType As u32, _
    ByVal pMem As Any Ptr _
)
Declare Function sqlite3VdbeSerialPut CDecl Alias "sqlite3VdbeSerialPut" ( _
    ByVal pMem As Any Ptr, _
    ByVal serialType As u32, _
    ByVal zHeader As UByte Ptr, _
    ByVal headerCapacity As u32, _
    ByVal pHeaderBytes As u32 Ptr, _
    ByVal zData As UByte Ptr, _
    ByVal dataCapacity As u32, _
    ByVal pDataBytes As u32 Ptr _
) As SQLITE_C_INT

#endif

/' end of sqlite3_vdbe_serial.bi '/
