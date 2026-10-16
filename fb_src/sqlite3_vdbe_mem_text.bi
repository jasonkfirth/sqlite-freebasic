/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_mem_text.bi

    Purpose:

        Declare VDBE value stringification, affinity casts, and text conversion.

    Responsibilities:

        - Preserve the C ABI for Mem text conversion helpers.
        - Share value-to-text and byte-count helpers with sqlite3_value APIs.
        - Declare CAST conversion over numeric, blob, and text values.

    This file intentionally does NOT contain:

        - Collation, formatting APIs, or SQL execution.
'/

#ifndef SQLITE3_FB_VDBE_MEM_TEXT_BI
#define SQLITE3_FB_VDBE_MEM_TEXT_BI

#include once "sqlite3_types.bi"

Declare Function sqlite3VdbeMemStringify CDecl Alias "sqlite3VdbeMemStringify" ( _
    ByVal pMem As Any Ptr, _
    ByVal enc As u8, _
    ByVal forceType As u8 _
) As SQLITE_C_INT
Declare Function sqlite3VdbeMemCast CDecl Alias "sqlite3VdbeMemCast" ( _
    ByVal pMem As Any Ptr, _
    ByVal affinity As u8, _
    ByVal eEncoding As u8 _
) As SQLITE_C_INT
Declare Function sqlite3VdbeChangeEncoding CDecl Alias "sqlite3VdbeChangeEncoding" ( _
    ByVal pMem As Any Ptr, _
    ByVal desiredEnc As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3VdbeMemTranslate CDecl Alias "sqlite3VdbeMemTranslate" ( _
    ByVal pMem As Any Ptr, _
    ByVal desiredEnc As u8 _
) As SQLITE_C_INT
Declare Function sqlite3ValueText CDecl Alias "sqlite3ValueText" ( _
    ByVal pValue As Any Ptr, _
    ByVal enc As u8 _
) As Any Ptr
Declare Function sqlite3ValueBytes CDecl Alias "sqlite3ValueBytes" ( _
    ByVal pValue As Any Ptr, _
    ByVal enc As u8 _
) As SQLITE_C_INT

#endif

/' end of sqlite3_vdbe_mem_text.bi '/
