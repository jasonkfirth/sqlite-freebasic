/'
** 2004 April 6
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
*************************************************************************
** This file implements an external (disk-based) database using BTrees.
** See the header comment on "btreeInt.h" for additional information.
'/ 
/'
    Project: SQLite FreeBASIC port
    File: sqlite3_btree_integrity_helpers.bas

    Purpose:

        Maintain the error and progress state used by B-tree integrity checks.

    Responsibilities:

        - Record out-of-memory and interruption errors.
        - Invoke the connection progress callback at SQLite's step interval.
        - Append formatted diagnostics while respecting the configured error limit.

    This file intentionally does NOT contain:

        - B-tree traversal or the public integrity-check entry point.
        - Test-only code or a claim of runtime behavior parity.
'/ 

#lang "fb"
#include once "sqlite3_integrity_types.bi"

Declare Function sqlite3_is_interrupted CDecl Alias "sqlite3_is_interrupted" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3_str_appendf CDecl Alias "sqlite3_str_appendf" ( _
    ByVal pAccum As Any Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Sub btreeIntegrityStrVAppendf CDecl Alias "sqlite3_str_vappendf" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ByRef arguments As Cva_List _
)

/' ------------------------------------------------------------------------- '/
/' Integrity-check status '/
/' ------------------------------------------------------------------------- '/

Sub checkOom CDecl Alias "checkOom" (ByVal pCheck As SqliteIntegrityCk Ptr)
    If pCheck = 0 Then Return

    pCheck->rc = SQLITE_NOMEM
    pCheck->mxErr = 0
    If pCheck->nErr = 0 Then pCheck->nErr += 1
End Sub

Sub checkProgress CDecl Alias "checkProgress" (ByVal pCheck As SqliteIntegrityCk Ptr)
    If pCheck = 0 OrElse pCheck->db = 0 Then Return

    Dim db As sqlite3 Ptr = pCheck->db
    If sqlite3_is_interrupted(db) <> 0 Then
        pCheck->rc = SQLITE_INTERRUPT
        pCheck->nErr += 1
        pCheck->mxErr = 0
    End If

#ifndef SQLITE_OMIT_PROGRESS_CALLBACK
    If db->xProgress <> 0 Then
        ASSERT(db->nProgressOps > 0)
        pCheck->nStep += 1
        If (pCheck->nStep Mod db->nProgressOps) = 0 AndAlso _
           db->xProgress(db->pProgressArg) <> 0 Then
            pCheck->rc = SQLITE_INTERRUPT
            pCheck->nErr += 1
            pCheck->mxErr = 0
        End If
    End If
#endif
End Sub

Sub setPageReferenced CDecl Alias "setPageReferenced" ( _
    ByVal pCheck As SqliteIntegrityCk Ptr, _
    ByVal pageNumber As u32 _
)
    If pCheck = 0 OrElse pCheck->aPgRef = 0 Then Return
    ASSERT(pageNumber <= pCheck->nCkPage)
    If pageNumber > pCheck->nCkPage Then Return

    Dim byteIndex As u32 = pageNumber \ 8
    Dim bitMask As UByte = CByte(1 Shl (pageNumber And &H07))
    pCheck->aPgRef[byteIndex] = pCheck->aPgRef[byteIndex] Or bitMask
End Sub

/' ------------------------------------------------------------------------- '/
/' Formatted integrity diagnostics '/
/' ------------------------------------------------------------------------- '/

Sub checkAppendMsg CDecl Alias "checkAppendMsg" ( _
    ByVal pCheck As SqliteIntegrityCk Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
    If pCheck = 0 OrElse zFormat = 0 Then Return

    checkProgress(pCheck)
    If pCheck->mxErr = 0 Then Return
    pCheck->mxErr -= 1
    pCheck->nErr += 1

    Dim arguments As Cva_List
    Cva_Start(arguments, zFormat)

    If pCheck->errMsg.nChar <> 0 Then
        sqlite3_str_append(@pCheck->errMsg, StrPtr(!"\n"), 1)
    End If

    If pCheck->zPfx <> 0 Then
        sqlite3_str_appendf(@pCheck->errMsg, pCheck->zPfx, _
            pCheck->v0, pCheck->v1, pCheck->v2)
    End If

    btreeIntegrityStrVAppendf(@pCheck->errMsg, zFormat, arguments)
    Cva_End(arguments)

    If pCheck->errMsg.accError = SQLITE_NOMEM Then checkOom(pCheck)
End Sub

/' end of sqlite3_btree_integrity_helpers.bas '/
