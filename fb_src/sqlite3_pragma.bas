/'
    Project: SQLite FreeBASIC port

    File: sqlite3_pragma.bas

    Purpose:

        Hold small VDBE result helpers used by PRAGMA implementations.

    Responsibilities:

        - Emit a one-column integer result row.
        - Emit a one-column text result row.
        - Emit an integrity-check row and its maximum-row limit branch.

    This file intentionally does NOT contain:

        - PRAGMA lookup, table scans, or database property changes.
'/ 

#lang "fb"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_numeric.bi"

Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal z As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_stricmp CDecl Alias "sqlite3_stricmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT

Private Function getSafetyLevel CDecl Alias "getSafetyLevel" ( _
    ByVal z As Const ZString Ptr, _
    ByVal omitFull As SQLITE_C_INT, _
    ByVal defaultValue As u8 _
) As u8
    If z = 0 Then Return defaultValue

    Dim firstByte As UByte = CPtr(Const UByte Ptr, z)[0]
    If firstByte >= Asc("0") AndAlso firstByte <= Asc("9") Then _
        Return CByte(sqlite3Atoi(z) <> 0)

    Select Case sqlite3Strlen30(z)
    Case 2
        If sqlite3_stricmp(z, StrPtr("on")) = 0 Then Return 1
        If sqlite3_stricmp(z, StrPtr("no")) = 0 Then Return 0
    Case 3
        If sqlite3_stricmp(z, StrPtr("off")) = 0 Then Return 0
        If sqlite3_stricmp(z, StrPtr("yes")) = 0 Then Return 1
    Case 4
        If sqlite3_stricmp(z, StrPtr("true")) = 0 Then Return 1
        If omitFull = 0 AndAlso sqlite3_stricmp(z, StrPtr("full")) = 0 Then _
            Return 2
    Case 5
        If sqlite3_stricmp(z, StrPtr("false")) = 0 Then Return 0
        If omitFull = 0 AndAlso sqlite3_stricmp(z, StrPtr("extra")) = 0 Then _
            Return 3
    End Select

    Return defaultValue
End Function

Function sqlite3GetBoolean CDecl Alias "sqlite3GetBoolean" ( _
    ByVal z As Const ZString Ptr, _
    ByVal defaultValue As u8 _
) As u8 Export
    Return CByte(getSafetyLevel(z, 1, defaultValue) <> 0)
End Function

Private Sub returnSingleInt CDecl Alias "returnSingleInt" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal value As sqlite3_int64 _
)
    If pVdbe = 0 Then Exit Sub
    ' PRAGMA scalar results use VDBE register 1 as their single output cell.
    sqlite3VdbeAddInt64(pVdbe, 1, value)
    sqlite3VdbeAddOp2(pVdbe, OP_ResultRow, 1, 1)
End Sub

Private Sub returnSingleText CDecl Alias "returnSingleText" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal zValue As Const ZString Ptr _
)
    If pVdbe = 0 OrElse zValue = 0 Then Exit Sub
    sqlite3VdbeLoadString(pVdbe, 1, zValue)
    sqlite3VdbeAddOp2(pVdbe, OP_ResultRow, 1, 1)
End Sub

Private Function integrityCheckResultRow CDecl Alias "integrityCheckResultRow" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) As SQLITE_C_INT
    If pVdbe = 0 Then Return -1
    ' Register 3 carries the diagnostic text; register 1 limits result rows.
    sqlite3VdbeAddOp2(pVdbe, OP_ResultRow, 3, 1)
    Dim address As SQLITE_C_INT = sqlite3VdbeAddOp3( _
        pVdbe, OP_IfPos, 1, sqlite3VdbeCurrentAddr(pVdbe) + 2, 1)
    sqlite3VdbeAddOp0(pVdbe, OP_Halt)
    Return address
End Function

/' end of sqlite3_pragma.bas '/
