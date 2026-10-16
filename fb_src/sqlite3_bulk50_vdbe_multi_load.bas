/'
/*
** 2001 September 15
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
*************************************************************************
** This file contains auxiliary routines used by the VDBE.
*/
'/

/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_bulk50_vdbe_multi_load.bas

    Purpose:

        Load a sequence of typed values into VDBE registers and emit a result row.

    Responsibilities:

        - Read each vararg using the character code in the format string.
        - Emit OP_String8 or OP_Null for string slots and OP_Integer for integers.
        - Omit OP_ResultRow when the format ends with an unsupported sentinel.

    This file intentionally does NOT contain:

        - VDBE execution or general opcode generation.
        - Runtime parity claims for variadic call sites.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_vdbe_core.bi"

Sub sqlite3VdbeMultiLoad CDecl Alias "sqlite3VdbeMultiLoad" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal firstRegister As SQLITE_C_INT, _
    ByVal typeCodes As Const ZString Ptr, _
    ... _
)
    If pVdbe = 0 OrElse typeCodes = 0 Then Return

    Dim arguments As Cva_List
    Cva_Start(arguments, typeCodes)

    Dim typeBytes As Const UByte Ptr = CPtr(Const UByte Ptr, typeCodes)
    Dim valueIndex As SQLITE_C_INT = 0
    While typeBytes[valueIndex] <> 0
        Select Case typeBytes[valueIndex]
        Case Asc("s")
            Dim textValue As Const ZString Ptr = _
                Cva_Arg(arguments, Const ZString Ptr)
            Dim opcode As SQLITE_C_INT = IIf(textValue = 0, OP_Null, OP_String8)
            sqlite3VdbeAddOp4(pVdbe, opcode, 0, firstRegister + valueIndex, _
                              0, textValue, 0)
        Case Asc("i")
            Dim integerValue As SQLITE_C_INT = _
                Cva_Arg(arguments, SQLITE_C_INT)
            sqlite3VdbeAddOp2(pVdbe, OP_Integer, integerValue, _
                              firstRegister + valueIndex)
        Case Else
            Cva_End(arguments)
            Return
        End Select
        valueIndex += 1
    Wend

    sqlite3VdbeAddOp2(pVdbe, OP_ResultRow, firstRegister, valueIndex)
    Cva_End(arguments)
End Sub

/' end of sqlite3_bulk50_vdbe_multi_load.bas '/
