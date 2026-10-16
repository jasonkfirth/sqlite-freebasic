/'
    Project: SQLite FreeBASIC port

    File: sqlite3_bulk_btree_copy_node.bas

    Purpose:

        Copy cell contents and child-page metadata between B-tree pages.

    Responsibilities:

        - Port copyNodeContent from src/btree.c.
        - Rebuild pointer-map entries for copied child pages.
        - Propagate malformed-page errors through the caller's status value.

    This file intentionally does NOT contain:

        - Page allocation, cursor balancing, or root-page replacement.
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
Declare Function btreeComputeFreeSpace CDecl Alias "btreeComputeFreeSpace" (ByVal arg0 As MemPage Ptr) As SQLITE_C_INT
Declare Sub copyNodeContent CDecl Alias "copyNodeContent" (ByVal arg0 As MemPage Ptr, ByVal arg1 As MemPage Ptr, ByVal arg2 As SQLITE_C_INT Ptr)
Declare Function c2fb_crt_memcpy CDecl Alias "memcpy" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_SIZE_T) As Any Ptr

Private Function btreeComputeFreeSpace CDecl Alias "btreeComputeFreeSpace" (ByVal arg0 As MemPage Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As UByte
    Dim local2 As UByte Ptr
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim local6 As SQLITE_C_INT
    Dim local7 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As UByte
    Dim c2fb_temp_2 As UByte Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim local8 As SQLITE_C_UINT
    Dim local9 As SQLITE_C_UINT
    Dim c2fb_temp_8 As SQLITE_C_UINT
    Dim c2fb_temp_9 As SQLITE_C_UINT
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SQLITE_C_INT Ptr
    Dim c2fb_temp_13 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, arg0->pBt->usableSize)
    local3 = c2fb_temp_0
    c2fb_temp_1 = Cast(UByte, arg0->hdrOffset)
    local1 = c2fb_temp_1
    c2fb_temp_2 = arg0->aData
    local2 = c2fb_temp_2
    c2fb_temp_3 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (CPtr(UByte Ptr, @(local2[Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1) + Cast(SQLITE_C_INT, 5ULL)))])))[Cast(SQLITE_C_INT, &O0ULL)]) Shl Cast(SQLITE_C_INT, 8ULL))) Or Cast(SQLITE_C_INT, (CPtr(UByte Ptr, @(local2[Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1) + Cast(SQLITE_C_INT, 5ULL)))])))[Cast(SQLITE_C_INT, 1ULL)])))))) - Cast(SQLITE_C_INT, 1ULL)))) And Cast(SQLITE_C_INT, &HffffULL)))) + Cast(SQLITE_C_INT, 1ULL)))))
    local5 = c2fb_temp_3
    c2fb_temp_4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1) + Cast(SQLITE_C_INT, 8ULL))) + Cast(SQLITE_C_INT, arg0->childPtrSize))) + Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 2ULL) * Cast(SQLITE_C_INT, arg0->nCell))))))
    local6 = c2fb_temp_4
    c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local3 - Cast(SQLITE_C_INT, 4ULL))))
    local7 = c2fb_temp_5
    c2fb_temp_6 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (CPtr(UByte Ptr, @(local2[Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1) + Cast(SQLITE_C_INT, 1ULL)))])))[Cast(SQLITE_C_INT, &O0ULL)]) Shl Cast(SQLITE_C_INT, 8ULL))) Or Cast(SQLITE_C_INT, (CPtr(UByte Ptr, @(local2[Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1) + Cast(SQLITE_C_INT, 1ULL)))])))[Cast(SQLITE_C_INT, 1ULL)])))))
    local0 = c2fb_temp_6
    c2fb_temp_7 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local2[Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1) + Cast(SQLITE_C_INT, 7ULL)))]) + local5)))
    local4 = c2fb_temp_7
    If (-Cast(SQLITE_C_INT, ((local0 > Cast(SQLITE_C_INT, &O0ULL))))) Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        If (-Cast(SQLITE_C_INT, ((local0 < local5)))) Then
            Return sqlite3CorruptError(Cast(SQLITE_C_INT, 2159ULL))
        End If
        While Cast(SQLITE_C_INT, 1ULL)
            If (-Cast(SQLITE_C_INT, ((local0 > local7)))) Then
                Return sqlite3CorruptError(Cast(SQLITE_C_INT, 2164ULL))
            End If
            c2fb_temp_8 = Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (CPtr(UByte Ptr, @(local2[local0])))[Cast(SQLITE_C_INT, &O0ULL)]) Shl Cast(SQLITE_C_INT, 8ULL))) Or Cast(SQLITE_C_INT, (CPtr(UByte Ptr, @(local2[local0])))[Cast(SQLITE_C_INT, 1ULL)])))))
            local8 = c2fb_temp_8
            c2fb_temp_9 = Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (CPtr(UByte Ptr, @(local2[Cast(SQLITE_C_INT, (local0 + Cast(SQLITE_C_INT, 2ULL)))])))[Cast(SQLITE_C_INT, &O0ULL)]) Shl Cast(SQLITE_C_INT, 8ULL))) Or Cast(SQLITE_C_INT, (CPtr(UByte Ptr, @(local2[Cast(SQLITE_C_INT, (local0 + Cast(SQLITE_C_INT, 2ULL)))])))[Cast(SQLITE_C_INT, 1ULL)])))))
            local9 = c2fb_temp_9
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local9 < Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL)))))) AndAlso (-Cast(SQLITE_C_INT, ((sqlite3FaultSim(Cast(SQLITE_C_INT, 422ULL)) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                Return sqlite3CorruptError(Cast(SQLITE_C_INT, 2173ULL))
            End If
            c2fb_temp_10 = Cast(SQLITE_C_INT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, local4) + local9)))
            local4 = c2fb_temp_10
            If (-Cast(SQLITE_C_INT, ((local8 < Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, local0) + local9)) + Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL)))))))) Then
                Goto c2fb_flow_0
            End If
            c2fb_temp_11 = Cast(SQLITE_C_INT, local8)
            local0 = c2fb_temp_11
        c2fb_flow_1:
        Wend
        c2fb_flow_0:
        If (-Cast(SQLITE_C_INT, ((local8 > Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            Return sqlite3CorruptError(Cast(SQLITE_C_INT, 2181ULL))
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, local0) + local9)) > Cast(SQLITE_C_UINT, local3))))) Then
            Return sqlite3CorruptError(Cast(SQLITE_C_INT, 2185ULL))
        End If
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local4 > local3)))) OrElse (-Cast(SQLITE_C_INT, ((local4 < local6)))))))) Then
        Return sqlite3CorruptError(Cast(SQLITE_C_INT, 2197ULL))
    End If
    c2fb_temp_12 = @(arg0->nFree)
    c2fb_temp_13 = Cast(SQLITE_C_INT, Cast(UShort, (Cast(SQLITE_C_INT, (local4 - local6)))))
    (*c2fb_temp_12) = c2fb_temp_13
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Sub copyNodeContent CDecl Alias "copyNodeContent" (ByVal arg0 As MemPage Ptr, ByVal arg1 As MemPage Ptr, ByVal arg2 As SQLITE_C_INT Ptr)
    Dim local0 As Const BtShared Ptr
    Dim local1 As Const UByte Ptr
    Dim local2 As Const UByte Ptr
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim local6 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As Any Ptr
    Dim c2fb_temp_2 As Any Ptr
    Dim c2fb_temp_3 As u8 Ptr
    Dim c2fb_temp_4 As UByte
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT Ptr
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT

    If (-Cast(SQLITE_C_INT, ((((*arg2)) = Cast(SQLITE_C_INT, &O0ULL))))) Then
        local0 = arg0->pBt
        local1 = arg0->aData
        local2 = arg1->aData
        local3 = arg0->hdrOffset
        local4 = (IIf(((-Cast(SQLITE_C_INT, ((arg1->pgno = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))))), Cast(SQLITE_C_INT, 100ULL), Cast(SQLITE_C_INT, &O0ULL)))
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        c2fb_temp_0 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (CPtr(UByte Ptr, @(local1[Cast(SQLITE_C_INT, (local3 + Cast(SQLITE_C_INT, 5ULL)))])))[Cast(SQLITE_C_INT, &O0ULL)]) Shl Cast(SQLITE_C_INT, 8ULL))) Or Cast(SQLITE_C_INT, (CPtr(UByte Ptr, @(local1[Cast(SQLITE_C_INT, (local3 + Cast(SQLITE_C_INT, 5ULL)))])))[Cast(SQLITE_C_INT, 1ULL)])))))
        local6 = c2fb_temp_0
        c2fb_temp_1 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, CPtr(UByte Ptr, @(local2[local6]))), CPtr(Const Any Ptr, CPtr(UByte Ptr, @(local1[local6]))), Cast(SQLITE_C_UINT, (local0->usableSize - Cast(SQLITE_C_UINT, local6)))))
        c2fb_temp_2 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, CPtr(UByte Ptr, @(local2[local4]))), CPtr(Const Any Ptr, CPtr(UByte Ptr, @(local1[local3]))), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->cellOffset) + Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 2ULL) * Cast(SQLITE_C_INT, arg0->nCell)))))))
        c2fb_temp_3 = @(arg1->isInit)
        c2fb_temp_4 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_3) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, &O0ULL)))
        c2fb_temp_4 = Cast(UByte, (*c2fb_temp_3))
        c2fb_temp_5 = Cast(SQLITE_C_INT, btreeInitPage(arg1))
        local5 = c2fb_temp_5
        If (-Cast(SQLITE_C_INT, ((local5 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_6 = Cast(SQLITE_C_INT, btreeComputeFreeSpace(arg1))
            local5 = c2fb_temp_6
        End If
        If (-Cast(SQLITE_C_INT, ((local5 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_7 = @((*arg2))
            c2fb_temp_8 = Cast(SQLITE_C_INT, local5)
            (*c2fb_temp_7) = c2fb_temp_8
            Return
        End If
        If (local0->autoVacuum) Then
            c2fb_temp_9 = @((*arg2))
            c2fb_temp_10 = Cast(SQLITE_C_INT, setChildPtrmaps(arg1))
            (*c2fb_temp_9) = c2fb_temp_10
        End If
    End If
End Sub

/' end of sqlite3_bulk_btree_copy_node.bas '/
