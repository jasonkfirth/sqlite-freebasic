/'
** 2003 September 6
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
*************************************************************************
** This file contains code used for creating, destroying, and populating
** a VDBE (or an "sqlite3_stmt" as it is known to the outside world.)
'/ 
/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_normalize.bas

    Purpose:

        Track double-quoted strings for normalized SQL statements.

    Responsibilities:

        - Store dequoted identifier bytes on the owning VDBE.
        - Check identifiers against the VDBE's double-quoted string list.
        - Free every variable-sized string node when the VDBE is deleted.

    This file intentionally does NOT contain:

        - SQL normalization or statement text generation.
        - Behavior outside SQLITE_ENABLE_NORMALIZE.
'/ 

#lang "fb"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_db_types.bi"

#ifdef SQLITE_ENABLE_NORMALIZE
Declare Function vdbeNormalizeStrlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal zText As Const ZString Ptr _
) As SQLITE_C_INT

Sub sqlite3VdbeAddDblquoteStr CDecl Alias "sqlite3VdbeAddDblquoteStr" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal zText As Const ZString Ptr _
)
    If db = 0 OrElse pVdbe = 0 OrElse zText = 0 Then Exit Sub

    Dim textLength As SQLITE_C_INT = vdbeNormalizeStrlen30(zText)
    If textLength < 0 Then Exit Sub

    Dim allocationSize As sqlite3_uint64 = _
        Cast(sqlite3_uint64, SizeOf(SqliteDblquoteStr)) + _
        Cast(sqlite3_uint64, textLength) + 1 - _
        Cast(sqlite3_uint64, SizeOf(pVdbe->pDblStr->z))
    Dim pEntry As SqliteDblquoteStr Ptr = _
        CPtr(SqliteDblquoteStr Ptr, sqlite3DbMallocRawNN(db, allocationSize))
    If pEntry = 0 Then Exit Sub

    Dim pDestination As UByte Ptr = @pEntry->z(0)
    Dim pSource As Const UByte Ptr = CPtr(Const UByte Ptr, zText)
    For byteIndex As SQLITE_C_INT = 0 To textLength
        pDestination[byteIndex] = pSource[byteIndex]
    Next

    pEntry->pNextStr = pVdbe->pDblStr
    pVdbe->pDblStr = pEntry
End Sub

Function sqlite3VdbeUsesDoubleQuotedString CDecl Alias "sqlite3VdbeUsesDoubleQuotedString" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal zIdentifier As Const ZString Ptr _
) As SQLITE_C_INT
    If pVdbe = 0 OrElse zIdentifier = 0 Then Return 0

    Dim pNeedle As Const UByte Ptr = CPtr(Const UByte Ptr, zIdentifier)
    Dim pEntry As SqliteDblquoteStr Ptr = pVdbe->pDblStr
    While pEntry <> 0
        Dim pText As Const UByte Ptr = CPtr(Const UByte Ptr, @pEntry->z(0))
        Dim byteIndex As SQLITE_C_INT = 0
        While pText[byteIndex] = pNeedle[byteIndex]
            If pText[byteIndex] = 0 Then Return 1
            byteIndex += 1
        Wend
        pEntry = pEntry->pNextStr
    Wend

    Return 0
End Function
#endif

/' end of sqlite3_vdbe_normalize.bas '/
