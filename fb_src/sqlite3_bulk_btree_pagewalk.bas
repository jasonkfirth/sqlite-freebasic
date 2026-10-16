/'
    Project: SQLite FreeBASIC port

    File: sqlite3_bulk_btree_pagewalk.bas

    Purpose:

        Load initialized B-tree pages and walk cursor paths through them.

    Responsibilities:

        - Port getAndInitPage and page-navigation helpers from src/btree.c.
        - Reuse the validated page initializer and shared page-release routines.
        - Preserve SQLite's cursor path and root-page traversal behavior.

    This file intentionally does NOT contain:

        - B-tree balancing, cell mutation, or transaction setup.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_hash_types.bi"
#include once "sqlite3_pager.bi"
#include once "sqlite3_btree.bi"
#include once "sqlite3_pcache.bi"
#include once "sqlite3_varint.bi"
#include once "sqlite3_fault.bi"
#include once "sqlite3_bitvec.bi"
Declare Function sqlite3CorruptError CDecl Alias "sqlite3CorruptError" (ByVal arg0 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function getAndInitPage CDecl Alias "getAndInitPage" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As MemPage Ptr Ptr, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function moveToChild CDecl Alias "moveToChild" (ByVal arg0 As BtCursor Ptr, ByVal arg1 As SQLITE_C_UINT) As SQLITE_C_INT
Declare Function moveToRoot CDecl Alias "moveToRoot" (ByVal arg0 As BtCursor Ptr) As SQLITE_C_INT
Declare Function moveToRightmost CDecl Alias "moveToRightmost" (ByVal arg0 As BtCursor Ptr) As SQLITE_C_INT
Declare Function btreeLast CDecl Alias "btreeLast" (ByVal arg0 As BtCursor Ptr, ByVal arg1 As SQLITE_C_INT Ptr) As SQLITE_C_INT

Private Function getAndInitPage CDecl Alias "getAndInitPage" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As MemPage Ptr Ptr, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As PgHdr Ptr
    Dim local2 As MemPage Ptr
    Dim c2fb_temp_0 As MemPage Ptr Ptr
    Dim c2fb_temp_1 As MemPage Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As MemPage Ptr Ptr
    Dim c2fb_temp_4 As MemPage Ptr
    Dim c2fb_temp_5 As MemPage Ptr
    Dim c2fb_temp_6 As MemPage Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As MemPage Ptr Ptr
    Dim c2fb_temp_9 As MemPage Ptr
    Dim c2fb_temp_10 As MemPage Ptr Ptr
    Dim c2fb_temp_11 As MemPage Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((arg1 > btreePagecount(arg0))))) Then
        c2fb_temp_0 = @((*arg2))
        c2fb_temp_1 = CPtr(MemPage Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_0) = c2fb_temp_1
        Return sqlite3CorruptError(Cast(SQLITE_C_INT, 2422ULL))
    End If
    c2fb_temp_2 = Cast(SQLITE_C_INT, sqlite3PagerGet(arg0->pPager, arg1, CPtr(PgHdr Ptr Ptr, CPtr(PgHdr Ptr Ptr, @(local1))), arg3))
    local0 = c2fb_temp_2
    If local0 Then
        c2fb_temp_3 = @((*arg2))
        c2fb_temp_4 = CPtr(MemPage Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_3) = c2fb_temp_4
        Return local0
    End If
    c2fb_temp_5 = CPtr(MemPage Ptr, CPtr(Any Ptr, sqlite3PagerGetExtra(local1)))
    local2 = c2fb_temp_5
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->isInit) = Cast(SQLITE_C_INT, &O0ULL))))) Then
        c2fb_temp_6 = CPtr(MemPage Ptr, btreePageFromDbPage(local1, arg1, arg0))
        c2fb_temp_7 = Cast(SQLITE_C_INT, btreeInitPage(local2))
        local0 = c2fb_temp_7
        If (-Cast(SQLITE_C_INT, ((local0 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            releasePage(local2)
            c2fb_temp_8 = @((*arg2))
            c2fb_temp_9 = CPtr(MemPage Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            (*c2fb_temp_8) = c2fb_temp_9
            Return local0
        End If
    End If
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_10 = @((*arg2))
    c2fb_temp_11 = local2
    (*c2fb_temp_10) = c2fb_temp_11
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function moveToChild CDecl Alias "moveToChild" (ByVal arg0 As BtCursor Ptr, ByVal arg1 As SQLITE_C_UINT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As u16 Ptr
    Dim c2fb_temp_1 As UShort
    Dim c2fb_temp_2 As u8 Ptr
    Dim c2fb_temp_3 As UByte
    Dim c2fb_temp_4 As u16 Ptr
    Dim c2fb_temp_5 As UShort
    Dim c2fb_temp_6 As MemPage Ptr Ptr
    Dim c2fb_temp_7 As MemPage Ptr
    Dim c2fb_temp_8 As u16 Ptr
    Dim c2fb_temp_9 As UShort
    Dim c2fb_temp_10 As Byte Ptr
    Dim c2fb_temp_11 As Byte
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As Byte Ptr
    Dim c2fb_temp_15 As Byte
    Dim c2fb_temp_16 As Byte
    Dim c2fb_temp_17 As MemPage Ptr Ptr
    Dim c2fb_temp_18 As MemPage Ptr

    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->iPage) >= (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 20ULL) - Cast(SQLITE_C_INT, 1ULL)))))))) Then
        Return sqlite3CorruptError(Cast(SQLITE_C_INT, 5493ULL))
    End If
    c2fb_temp_0 = @(arg0->info.nSize)
    c2fb_temp_1 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_0) = Cast(u16, Cast(UShort, Cast(SQLITE_C_INT, &O0ULL)))
    c2fb_temp_1 = Cast(UShort, (*c2fb_temp_0))
    c2fb_temp_2 = @(arg0->curFlags)
    c2fb_temp_3 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_2))) And Cast(SQLITE_C_INT, (Not (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H02ULL) Or Cast(SQLITE_C_INT, &H04ULL)))))))))
    (*c2fb_temp_2) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_2))) And Cast(SQLITE_C_INT, (Not (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H02ULL) Or Cast(SQLITE_C_INT, &H04ULL))))))))))
    c2fb_temp_3 = Cast(UByte, (*c2fb_temp_2))
    c2fb_temp_4 = @(arg0->aiIdx(arg0->iPage))
    c2fb_temp_5 = Cast(UShort, arg0->ix)
    (*c2fb_temp_4) = Cast(u16, Cast(UShort, arg0->ix))
    c2fb_temp_5 = Cast(UShort, (*c2fb_temp_4))
    c2fb_temp_6 = @(arg0->apPage(arg0->iPage))
    c2fb_temp_7 = arg0->pPage
    (*c2fb_temp_6) = c2fb_temp_7
    c2fb_temp_8 = @(arg0->ix)
    c2fb_temp_9 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_8) = Cast(u16, Cast(UShort, Cast(SQLITE_C_INT, &O0ULL)))
    c2fb_temp_9 = Cast(UShort, (*c2fb_temp_8))
    c2fb_temp_10 = @(arg0->iPage)
    c2fb_temp_11 = (*c2fb_temp_10)
    (*c2fb_temp_10) = Cast(Byte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_11) + 1)))
    c2fb_temp_12 = Cast(SQLITE_C_INT, getAndInitPage(arg0->pBt, arg1, CPtr(MemPage Ptr Ptr, @(arg0->pPage)), arg0->curPagerFlags))
    local0 = c2fb_temp_12
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->pPage->nCell) < Cast(SQLITE_C_INT, 1ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->pPage->intKey) <> Cast(SQLITE_C_INT, arg0->curIntKey)))))))))))))) Then
        releasePage(arg0->pPage)
        c2fb_temp_13 = Cast(SQLITE_C_INT, sqlite3CorruptError(Cast(SQLITE_C_INT, 5507ULL)))
        local0 = c2fb_temp_13
    End If
    If local0 Then
        c2fb_temp_17 = @(arg0->pPage)
        c2fb_temp_14 = @(arg0->iPage)
        c2fb_temp_15 = (*c2fb_temp_14)
        (*c2fb_temp_14) = Cast(Byte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_15) - 1)))
        c2fb_temp_16 = (*c2fb_temp_14)
        c2fb_temp_18 = arg0->apPage(c2fb_temp_16)
        (*c2fb_temp_17) = c2fb_temp_18
    End If
    Return local0
End Function

Private Function moveToRoot CDecl Alias "moveToRoot" (ByVal arg0 As BtCursor Ptr) As SQLITE_C_INT
    Dim local0 As MemPage Ptr
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As Byte Ptr
    Dim c2fb_temp_1 As Byte
    Dim c2fb_temp_2 As Byte
    Dim c2fb_temp_3 As MemPage Ptr Ptr
    Dim c2fb_temp_4 As MemPage Ptr
    Dim c2fb_temp_5 As MemPage Ptr
    Dim c2fb_temp_6 As u8 Ptr
    Dim c2fb_temp_7 As UByte
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As u8 Ptr
    Dim c2fb_temp_10 As UByte
    Dim c2fb_temp_11 As Byte Ptr
    Dim c2fb_temp_12 As Byte
    Dim c2fb_temp_13 As u8 Ptr
    Dim c2fb_temp_14 As UByte
    Dim c2fb_temp_15 As MemPage Ptr
    Dim c2fb_temp_16 As u16 Ptr
    Dim c2fb_temp_17 As UShort
    Dim c2fb_temp_18 As u16 Ptr
    Dim c2fb_temp_19 As UShort
    Dim c2fb_temp_20 As u8 Ptr
    Dim c2fb_temp_21 As UByte
    Dim c2fb_temp_22 As u8 Ptr
    Dim c2fb_temp_23 As UByte
    Dim local2 As SQLITE_C_UINT
    Dim c2fb_temp_24 As SQLITE_C_UINT
    Dim c2fb_temp_25 As u8 Ptr
    Dim c2fb_temp_26 As UByte
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim c2fb_temp_28 As u8 Ptr
    Dim c2fb_temp_29 As UByte
    Dim c2fb_temp_30 As SQLITE_C_INT

    ' C automatic storage declaration
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->iPage) >= Cast(SQLITE_C_INT, &O0ULL))))) Then
        If arg0->iPage Then
            releasePageNotNull(arg0->pPage)
            Do
                c2fb_temp_0 = @(arg0->iPage)
                c2fb_temp_1 = (*c2fb_temp_0)
                (*c2fb_temp_0) = Cast(Byte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_1) - 1)))
                c2fb_temp_2 = (*c2fb_temp_0)
                If (c2fb_temp_2 = 0) Then Goto c2fb_flow_0
                releasePageNotNull(arg0->apPage(arg0->iPage))
            c2fb_flow_1:
            Loop
            c2fb_flow_0:
            c2fb_temp_3 = @(arg0->pPage)
            c2fb_temp_4 = arg0->apPage(Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_3) = c2fb_temp_4
            c2fb_temp_5 = c2fb_temp_4
            local0 = c2fb_temp_5
            Goto c2fb_label_0
        End If
    Else
        If (-Cast(SQLITE_C_INT, ((arg0->pgnoRoot = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            c2fb_temp_6 = @(arg0->eState)
            c2fb_temp_7 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
            (*c2fb_temp_6) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 1ULL)))
            c2fb_temp_7 = Cast(UByte, (*c2fb_temp_6))
            Return Cast(SQLITE_C_INT, 16ULL)
        Else
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->eState) >= Cast(SQLITE_C_INT, 3ULL))))) Then
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->eState) = Cast(SQLITE_C_INT, 4ULL))))) Then
                    ' C unused-parameter annotation
                    Return arg0->skipNext
                End If
                sqlite3BtreeClearCursor(arg0)
            End If
            c2fb_temp_8 = Cast(SQLITE_C_INT, getAndInitPage(arg0->pBt, arg0->pgnoRoot, CPtr(MemPage Ptr Ptr, @(arg0->pPage)), arg0->curPagerFlags))
            local1 = c2fb_temp_8
            If (-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_9 = @(arg0->eState)
                c2fb_temp_10 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
                (*c2fb_temp_9) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 1ULL)))
                c2fb_temp_10 = Cast(UByte, (*c2fb_temp_9))
                Return local1
            End If
            c2fb_temp_11 = @(arg0->iPage)
            c2fb_temp_12 = Cast(Byte, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_11) = c2fb_temp_12
            c2fb_temp_13 = @(arg0->curIntKey)
            c2fb_temp_14 = Cast(UByte, arg0->pPage->intKey)
            (*c2fb_temp_13) = Cast(u8, Cast(UByte, arg0->pPage->intKey))
            c2fb_temp_14 = Cast(UByte, (*c2fb_temp_13))
        End If
    End If
    c2fb_temp_15 = arg0->pPage
    local0 = c2fb_temp_15
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->isInit) = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((arg0->pKeyInfo = Cast(SQLITE_C_INT, &O0ULL)))))) <> Cast(SQLITE_C_INT, local0->intKey))))))))) Then
        Return sqlite3CorruptError(Cast(SQLITE_C_INT, 5642ULL))
    End If
    c2fb_label_0:
    c2fb_temp_16 = @(arg0->ix)
    c2fb_temp_17 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_16) = Cast(u16, Cast(UShort, Cast(SQLITE_C_INT, &O0ULL)))
    c2fb_temp_17 = Cast(UShort, (*c2fb_temp_16))
    c2fb_temp_18 = @(arg0->info.nSize)
    c2fb_temp_19 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_18) = Cast(u16, Cast(UShort, Cast(SQLITE_C_INT, &O0ULL)))
    c2fb_temp_19 = Cast(UShort, (*c2fb_temp_18))
    c2fb_temp_20 = @(arg0->curFlags)
    c2fb_temp_21 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_20))) And Cast(SQLITE_C_INT, (Not (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H02ULL))) Or Cast(SQLITE_C_INT, &H04ULL)))))))))
    (*c2fb_temp_20) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_20))) And Cast(SQLITE_C_INT, (Not (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H02ULL))) Or Cast(SQLITE_C_INT, &H04ULL))))))))))
    c2fb_temp_21 = Cast(UByte, (*c2fb_temp_20))
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->nCell) > Cast(SQLITE_C_INT, &O0ULL))))) Then
        c2fb_temp_22 = @(arg0->eState)
        c2fb_temp_23 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_22) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, &O0ULL)))
        c2fb_temp_23 = Cast(UByte, (*c2fb_temp_22))
    Else
        If (-Cast(SQLITE_C_INT, (local0->leaf = 0))) Then
            ' C automatic storage declaration
            If (-Cast(SQLITE_C_INT, ((local0->pgno <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))) Then
                Return sqlite3CorruptError(Cast(SQLITE_C_INT, 5654ULL))
            End If
            c2fb_temp_24 = Cast(SQLITE_C_UINT, sqlite3Get4byte(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0->aData[Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->hdrOffset) + Cast(SQLITE_C_INT, 8ULL)))])))))
            local2 = c2fb_temp_24
            c2fb_temp_25 = @(arg0->eState)
            c2fb_temp_26 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_25) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, &O0ULL)))
            c2fb_temp_26 = Cast(UByte, (*c2fb_temp_25))
            c2fb_temp_27 = Cast(SQLITE_C_INT, moveToChild(arg0, local2))
            local1 = c2fb_temp_27
        Else
            c2fb_temp_28 = @(arg0->eState)
            c2fb_temp_29 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
            (*c2fb_temp_28) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 1ULL)))
            c2fb_temp_29 = Cast(UByte, (*c2fb_temp_28))
            c2fb_temp_30 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 16ULL))
            local1 = c2fb_temp_30
        End If
    End If
    Return local1
End Function

Private Function moveToRightmost CDecl Alias "moveToRightmost" (ByVal arg0 As BtCursor Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_UINT
    Dim local1 As SQLITE_C_INT
    Dim local2 As MemPage Ptr
    Dim c2fb_temp_0 As MemPage Ptr
    Dim c2fb_temp_1 As SQLITE_C_UINT
    Dim c2fb_temp_2 As u16 Ptr
    Dim c2fb_temp_3 As UShort
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As u16 Ptr
    Dim c2fb_temp_6 As UShort

    ' C automatic storage declaration
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    local2 = Cast(SQLITE_C_INT, &O0ULL)
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    Do
        c2fb_temp_0 = arg0->pPage
        local2 = c2fb_temp_0
        If ((-Cast(SQLITE_C_INT, ((c2fb_temp_0)->leaf = 0))) = 0) Then Goto c2fb_flow_0
        c2fb_temp_1 = Cast(SQLITE_C_UINT, sqlite3Get4byte(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local2->aData[Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local2->hdrOffset) + Cast(SQLITE_C_INT, 8ULL)))])))))
        local0 = c2fb_temp_1
        c2fb_temp_2 = @(arg0->ix)
        c2fb_temp_3 = Cast(UShort, local2->nCell)
        (*c2fb_temp_2) = Cast(u16, Cast(UShort, local2->nCell))
        c2fb_temp_3 = Cast(UShort, (*c2fb_temp_2))
        c2fb_temp_4 = Cast(SQLITE_C_INT, moveToChild(arg0, local0))
        local1 = c2fb_temp_4
        If local1 Then
            Return local1
        End If
    c2fb_flow_1:
    Loop
    c2fb_flow_0:
    c2fb_temp_5 = @(arg0->ix)
    c2fb_temp_6 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local2->nCell) - Cast(SQLITE_C_INT, 1ULL))))
    (*c2fb_temp_5) = Cast(u16, Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local2->nCell) - Cast(SQLITE_C_INT, 1ULL)))))
    c2fb_temp_6 = Cast(UShort, (*c2fb_temp_5))
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function btreeLast CDecl Alias "btreeLast" (ByVal arg0 As BtCursor Ptr, ByVal arg1 As SQLITE_C_INT Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As u8 Ptr
    Dim c2fb_temp_4 As UByte
    Dim c2fb_temp_5 As u8 Ptr
    Dim c2fb_temp_6 As UByte
    Dim c2fb_temp_7 As SQLITE_C_INT Ptr
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT

    local0 = moveToRoot(arg0)
    If (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        ' C unused-parameter annotation
        c2fb_temp_0 = @((*arg1))
        c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_0) = c2fb_temp_1
        c2fb_temp_2 = Cast(SQLITE_C_INT, moveToRightmost(arg0))
        local0 = c2fb_temp_2
        If (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_3 = @(arg0->curFlags)
            c2fb_temp_4 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_3))) Or Cast(SQLITE_C_INT, &H08ULL))))
            (*c2fb_temp_3) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_3))) Or Cast(SQLITE_C_INT, &H08ULL)))))
            c2fb_temp_4 = Cast(UByte, (*c2fb_temp_3))
        Else
            c2fb_temp_5 = @(arg0->curFlags)
            c2fb_temp_6 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_5))) And Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, &H08ULL))))))
            (*c2fb_temp_5) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_5))) And Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, &H08ULL)))))))
            c2fb_temp_6 = Cast(UByte, (*c2fb_temp_5))
        End If
    Else
        If (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, 16ULL))))) Then
            ' C unused-parameter annotation
            c2fb_temp_7 = @((*arg1))
            c2fb_temp_8 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
            (*c2fb_temp_7) = c2fb_temp_8
            c2fb_temp_9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local0 = c2fb_temp_9
        End If
    End If
    Return local0
End Function

/' end of sqlite3_bulk_btree_pagewalk.bas '/
