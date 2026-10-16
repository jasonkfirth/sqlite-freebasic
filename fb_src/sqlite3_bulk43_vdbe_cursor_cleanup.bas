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
    ---------------------------------

    File: sqlite3_bulk43_vdbe_cursor_cleanup.bas

    Purpose:

        Close VDBE cursors and release their B-tree, sorter, and virtual-table resources.

    Responsibilities:

        - Release the optional large text/blob column cache.
        - Dispatch cursor cleanup by cursor kind.
        - Clear cursor slots when returning from a VDBE frame.

    This file intentionally does NOT contain:

        - Cursor opening, seeking, or row decoding.
        - Sorter record comparison or PMA creation.
        - Upstream tests or test-support code.
        - A claim that compilation establishes runtime parity.
'/

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_btree.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_vdbe_cursor.bi"
#include once "sqlite3_vtab_types.bi"

Declare Sub sqlite3RCStrUnref CDecl Alias "sqlite3RCStrUnref" (ByVal pValue As Any Ptr)

Type SqliteVtabCloseProc As Function CDecl ( _
    ByVal pCursor As Any Ptr _
) As SQLITE_C_INT

Private Sub freeCursorWithCache CDecl Alias "freeCursorWithCache" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pCursor As SqliteVdbeCursor Ptr _
)
    If pVdbe = 0 OrElse pCursor = 0 Then Exit Sub
    Dim pCache As SqliteVdbeTextBlobCache Ptr = _
        CPtr(SqliteVdbeTextBlobCache Ptr, pCursor->pCache)

    pCursor->cursorFlags = pCursor->cursorFlags And Not VDBE_CURSOR_COLUMN_CACHE
    pCursor->pCache = 0
    If pCache <> 0 Then
        If pCache->pCValue <> 0 Then
            sqlite3RCStrUnref(pCache->pCValue)
            pCache->pCValue = 0
        End If
        sqlite3DbFree(pVdbe->db, pCache)
    End If
    sqlite3VdbeFreeCursorNN(pVdbe, pCursor)
End Sub

Sub sqlite3VdbeFreeCursorNN CDecl Alias "sqlite3VdbeFreeCursorNN" ( _
    ByVal pVdbeArgument As Any Ptr, _
    ByVal pCursor As SqliteVdbeCursor Ptr _
)
    If pVdbeArgument = 0 OrElse pCursor = 0 Then Exit Sub
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pVdbeArgument)
    If (pCursor->cursorFlags And VDBE_CURSOR_COLUMN_CACHE) <> 0 Then
        freeCursorWithCache(pVdbe, pCursor)
        Exit Sub
    End If

    Select Case pCursor->eCurType
    Case CURTYPE_SORTER
        sqlite3VdbeSorterClose(pVdbe->db, pCursor)

    Case CURTYPE_BTREE
        If pCursor->uc.pCursor <> 0 Then
            sqlite3BtreeCloseCursor(pCursor->uc.pCursor)
        End If

    Case CURTYPE_VTAB
        Dim pVtabCursor As SqliteVtabCursor Ptr = _
            CPtr(SqliteVtabCursor Ptr, pCursor->uc.pVtabCursor)
        If pVtabCursor <> 0 AndAlso pVtabCursor->pVtab <> 0 Then
            Dim pVtab As SqliteVtab Ptr = pVtabCursor->pVtab
            If pVtab->nRef > 0 Then pVtab->nRef -= 1
            If pVtab->pModule <> 0 AndAlso pVtab->pModule->xClose <> 0 Then
                Dim xClose As SqliteVtabCloseProc = _
                    CPtr(SqliteVtabCloseProc, pVtab->pModule->xClose)
                Dim closeResult As SQLITE_C_INT = xClose(pVtabCursor)
            End If
        End If
    End Select
End Sub

Sub sqlite3VdbeFreeCursor CDecl Alias "sqlite3VdbeFreeCursor" ( _
    ByVal pVdbeArgument As Any Ptr, _
    ByVal pCursor As SqliteVdbeCursor Ptr _
)
    If pCursor <> 0 Then sqlite3VdbeFreeCursorNN(pVdbeArgument, pCursor)
End Sub

Sub closeCursorsInFrame CDecl Alias "closeCursorsInFrame" ( _
    ByVal pVdbeArgument As Any Ptr _
)
    If pVdbeArgument = 0 Then Exit Sub
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pVdbeArgument)
    If pVdbe->apCsr = 0 OrElse pVdbe->nCursor <= 0 Then Exit Sub

    For cursorIndex As SQLITE_C_INT = 0 To pVdbe->nCursor - 1
        Dim pCursor As SqliteVdbeCursor Ptr = _
            CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[cursorIndex])
        If pCursor <> 0 Then
            sqlite3VdbeFreeCursorNN(pVdbe, pCursor)
            pVdbe->apCsr[cursorIndex] = 0
        End If
    Next
End Sub

/' end of sqlite3_bulk43_vdbe_cursor_cleanup.bas '/
