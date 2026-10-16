/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_cursor.bas

    Purpose:

        Allocate the VDBE cursor header and its trailing type/offset arrays.

    Responsibilities:

        - Reuse the memory cell reserved for a cursor number.
        - Allocate storage for the cursor record metadata.
        - Embed and zero a B-tree cursor for B-tree cursor kinds.
        - Check VDBE register initialization for debug cursor hints.

    This file intentionally does NOT contain:

        - Cursor opening, closing, traversal, sorting, or virtual-table dispatch.
'/

#lang "fb"
#include once "sqlite3_vdbe_cursor.bi"
#include once "sqlite3_vdbe_core.bi"
#if defined(SQLITE_ENABLE_CURSOR_HINTS) AndAlso defined(SQLITE_DEBUG)
#include once "sqlite3_walker.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_debug_assert.bi"
#endif

Extern "C"
    Declare Function sqlite3VdbeCursorMemset CDecl Alias "memset" ( _
        ByVal destination As Any Ptr, _
        ByVal value As SQLITE_C_INT, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
End Extern

Private Function sqlite3VdbeCursorSize( _
    ByVal fieldCount As SQLITE_C_INT, _
    ByVal cursorType As u8 _
) As sqlite3_uint64
    If fieldCount < 0 Then Return 0
    Dim typeOffset As sqlite3_uint64 = (SizeOf(SqliteVdbeCursor) + 7) And Not 7ULL
    Dim totalBytes As sqlite3_uint64 = typeOffset + _
        (CULngInt(fieldCount) + 1) * SizeOf(sqlite3_uint64)
    If cursorType = CURTYPE_BTREE Then _
        totalBytes += CULngInt(sqlite3BtreeCursorSize())
    Return totalBytes
End Function

Function allocateCursor CDecl Alias "allocateCursor" ( _
    ByVal pVdbeArgument As Any Ptr, _
    ByVal cursorIndex As SQLITE_C_INT, _
    ByVal fieldCount As SQLITE_C_INT, _
    ByVal cursorType As u8 _
) As SqliteVdbeCursor Ptr Export
    If pVdbeArgument = 0 Then Return 0
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pVdbeArgument)
    If pVdbe->db = 0 OrElse pVdbe->aMem = 0 OrElse pVdbe->apCsr = 0 OrElse _
       cursorIndex < 0 OrElse cursorIndex >= pVdbe->nCursor OrElse _
       fieldCount < 0 OrElse cursorType > CURTYPE_PSEUDO Then Return 0

    Dim memoryIndex As SQLITE_C_INT = 0
    If cursorIndex > 0 Then memoryIndex = pVdbe->nMem - cursorIndex
    If memoryIndex < 0 OrElse memoryIndex >= pVdbe->nMem Then Return 0
    Dim pMem As SqliteVdbeMem Ptr = @pVdbe->aMem[memoryIndex]
    If pMem->flags <> MEM_UNDEFINED OrElse _
       (pMem->flags And MEM_DYN) <> 0 Then Return 0

    Dim allocationBytes As sqlite3_uint64 = sqlite3VdbeCursorSize(fieldCount, cursorType)
    If allocationBytes = 0 OrElse allocationBytes > SQLITE_MAX_ALLOCATION_SIZE Then
        sqlite3OomFault(pVdbe->db)
        Return 0
    End If

    If pVdbe->apCsr[cursorIndex] <> 0 Then
        Dim pOldCursor As SqliteVdbeCursor Ptr = _
            CPtr(SqliteVdbeCursor Ptr, pVdbe->apCsr[cursorIndex])
        ' Cursor registers reuse their VDBE memory cell for storage. Close
        ' every cursor kind before reusing the slot, including sorters.
        sqlite3VdbeFreeCursorNN(pVdbe, pOldCursor)
        pVdbe->apCsr[cursorIndex] = 0
    End If

    If pMem->szMalloc < allocationBytes OrElse pMem->zMalloc = 0 Then
        If pMem->szMalloc > 0 AndAlso pMem->zMalloc <> 0 Then _
            sqlite3DbFree(pVdbe->db, pMem->zMalloc)
        pMem->z = CPtr(UByte Ptr, sqlite3DbMallocRaw(pVdbe->db, allocationBytes))
        pMem->zMalloc = pMem->z
        If pMem->zMalloc = 0 Then
            pMem->szMalloc = 0
            Return 0
        End If
        pMem->szMalloc = CInt(allocationBytes)
    End If

    sqlite3VdbeCursorMemset(pMem->zMalloc, 0, allocationBytes)
    Dim pCursor As SqliteVdbeCursor Ptr = CPtr(SqliteVdbeCursor Ptr, pMem->zMalloc)
    pCursor->eCurType = cursorType
    pCursor->nField = CShort(fieldCount)

    Dim typeOffset As sqlite3_uint64 = (SizeOf(SqliteVdbeCursor) + 7) And Not 7ULL
    Dim pTypes As u32 Ptr = CPtr(u32 Ptr, CPtr(UByte Ptr, pCursor) + typeOffset)
    pCursor->aOffset = pTypes + fieldCount
    If cursorType = CURTYPE_BTREE Then
        pCursor->uc.pCursor = CPtr(BtCursor Ptr, _
            CPtr(UByte Ptr, pCursor) + typeOffset + _
            (CULngInt(fieldCount) + 1) * SizeOf(sqlite3_uint64))
        sqlite3BtreeCursorZero(pCursor->uc.pCursor)
    End If

    pVdbe->apCsr[cursorIndex] = pCursor
    Return pCursor
End Function

#if defined(SQLITE_ENABLE_CURSOR_HINTS) AndAlso defined(SQLITE_DEBUG)
Function sqlite3CursorRangeHintExprCheck CDecl Alias "sqlite3CursorRangeHintExprCheck" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT
    If pWalker = 0 OrElse pExpr = 0 Then Return WRC_CONTINUE
    If pExpr->op = TK_REGISTER Then
        If pWalker->u.aMem = 0 OrElse pExpr->iTable < 0 Then
            sqlite3DebugAssert(StrPtr("cursor-hint register is within the VDBE memory array"))
            Return WRC_CONTINUE
        End If
        If pWalker->pParse <> 0 AndAlso _
           pExpr->iTable > pWalker->pParse->nMem Then
            sqlite3DebugAssert(StrPtr("cursor-hint register is within the VDBE memory array"))
            Return WRC_CONTINUE
        End If
        Dim pMemory As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pWalker->u.aMem)
        If (pMemory[pExpr->iTable].flags And MEM_UNDEFINED) <> 0 Then _
            sqlite3DebugAssert(StrPtr("cursor-hint register is initialized"))
    End If
    Return WRC_CONTINUE
End Function
#endif

/' end of sqlite3_vdbe_cursor.bas '/
