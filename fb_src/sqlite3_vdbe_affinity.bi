/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_affinity.bi

    Purpose:

        Declare VDBE affinity dispatch and numeric conversion helpers.

    Responsibilities:

        - Preserve the C ABI for numeric and public value affinity conversion.
        - Keep affinity declarations separate from Mem lifecycle routines.

    This file intentionally does NOT contain:

        - Bytecode execution or SQL column affinity selection.
'/

#ifndef SQLITE3_FB_VDBE_AFFINITY_BI
#define SQLITE3_FB_VDBE_AFFINITY_BI

#include once "sqlite3_types.bi"

Declare Sub sqlite3ApplyNumericAffinity CDecl Alias "sqlite3ApplyNumericAffinity" ( _
    ByVal pMem As Any Ptr, _
    ByVal tryForInteger As SQLITE_C_INT _
)
Declare Sub sqlite3ValueApplyAffinity CDecl Alias "sqlite3ValueApplyAffinity" ( _
    ByVal pValue As Any Ptr, _
    ByVal affinity As u8, _
    ByVal enc As u8 _
)
Declare Function sqlite3VdbeNumericType CDecl Alias "sqlite3VdbeNumericType" ( _
    ByVal pMem As Any Ptr _
) As UShort

#endif

/' end of sqlite3_vdbe_affinity.bi '/
