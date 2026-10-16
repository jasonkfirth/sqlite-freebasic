/'
    Project: SQLite FreeBASIC port

    File: sqlite3_bulk_btree_pageformat.bas

    Purpose:

        Decode B-tree page flags and initialize an empty page image.

    Responsibilities:

        - Port decodeFlags and zeroPage from src/btree.c.
        - Select the table or index cell parser for each page layout.
        - Preserve page-header and pointer-map state when zeroing a page.

    This file intentionally does NOT contain:

        - Cursor traversal, page balancing, or freelist allocation.
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
Type c2fb_callback_8 As Sub CDecl(ByVal arg0 As Any Ptr)
Type c2fb_callback_84 As Function CDecl(ByVal arg0 As Any Ptr, ByVal arg1 As UByte Ptr) As UShort
Type c2fb_callback_85 As Sub CDecl(ByVal arg0 As Any Ptr, ByVal arg1 As UByte Ptr, ByVal arg2 As Any Ptr)
Declare Function decodeFlags CDecl Alias "decodeFlags" (ByVal arg0 As MemPage Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub zeroPage CDecl Alias "zeroPage" (ByVal arg0 As MemPage Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Function c2fb_crt_memset CDecl Alias "memset" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_SIZE_T) As Any Ptr

Private Function decodeFlags CDecl Alias "decodeFlags" (ByVal arg0 As MemPage Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As BtShared Ptr
    Dim c2fb_temp_0 As BtShared Ptr
    Dim c2fb_temp_1 As u8 Ptr
    Dim c2fb_temp_2 As UByte
    Dim c2fb_temp_3 As u8 Ptr
    Dim c2fb_temp_4 As UByte
    Dim c2fb_temp_5 As u8 Ptr
    Dim c2fb_temp_6 As UByte
    Dim c2fb_temp_7 As u8 Ptr
    Dim c2fb_temp_8 As UByte
    Dim c2fb_temp_9 As BtreeCellSizeProc Ptr
    Dim c2fb_temp_10 As c2fb_callback_84
    Dim c2fb_temp_11 As BtreeCellParseProc Ptr
    Dim c2fb_temp_12 As c2fb_callback_85
    Dim c2fb_temp_13 As u8 Ptr
    Dim c2fb_temp_14 As UByte
    Dim c2fb_temp_15 As u16 Ptr
    Dim c2fb_temp_16 As UShort
    Dim c2fb_temp_17 As u16 Ptr
    Dim c2fb_temp_18 As UShort
    Dim c2fb_temp_19 As u8 Ptr
    Dim c2fb_temp_20 As UByte
    Dim c2fb_temp_21 As u8 Ptr
    Dim c2fb_temp_22 As UByte
    Dim c2fb_temp_23 As BtreeCellSizeProc Ptr
    Dim c2fb_temp_24 As c2fb_callback_84
    Dim c2fb_temp_25 As BtreeCellParseProc Ptr
    Dim c2fb_temp_26 As c2fb_callback_85
    Dim c2fb_temp_27 As u16 Ptr
    Dim c2fb_temp_28 As UShort
    Dim c2fb_temp_29 As u16 Ptr
    Dim c2fb_temp_30 As UShort
    Dim c2fb_temp_31 As u8 Ptr
    Dim c2fb_temp_32 As UByte
    Dim c2fb_temp_33 As u8 Ptr
    Dim c2fb_temp_34 As UByte
    Dim c2fb_temp_35 As BtreeCellSizeProc Ptr
    Dim c2fb_temp_36 As c2fb_callback_84
    Dim c2fb_temp_37 As BtreeCellParseProc Ptr
    Dim c2fb_temp_38 As c2fb_callback_85
    Dim c2fb_temp_39 As u8 Ptr
    Dim c2fb_temp_40 As UByte
    Dim c2fb_temp_41 As u8 Ptr
    Dim c2fb_temp_42 As UByte
    Dim c2fb_temp_43 As u8 Ptr
    Dim c2fb_temp_44 As UByte
    Dim c2fb_temp_45 As u8 Ptr
    Dim c2fb_temp_46 As UByte
    Dim c2fb_temp_47 As BtreeCellSizeProc Ptr
    Dim c2fb_temp_48 As c2fb_callback_84
    Dim c2fb_temp_49 As BtreeCellParseProc Ptr
    Dim c2fb_temp_50 As c2fb_callback_85
    Dim c2fb_temp_51 As u16 Ptr
    Dim c2fb_temp_52 As UShort
    Dim c2fb_temp_53 As u16 Ptr
    Dim c2fb_temp_54 As UShort
    Dim c2fb_temp_55 As u8 Ptr
    Dim c2fb_temp_56 As UByte
    Dim c2fb_temp_57 As BtreeCellSizeProc Ptr
    Dim c2fb_temp_58 As c2fb_callback_84
    Dim c2fb_temp_59 As BtreeCellParseProc Ptr
    Dim c2fb_temp_60 As c2fb_callback_85
    Dim c2fb_temp_61 As u8 Ptr
    Dim c2fb_temp_62 As UByte
    Dim c2fb_temp_63 As u16 Ptr
    Dim c2fb_temp_64 As UShort
    Dim c2fb_temp_65 As u16 Ptr
    Dim c2fb_temp_66 As UShort
    Dim c2fb_temp_67 As u8 Ptr
    Dim c2fb_temp_68 As UByte
    Dim c2fb_temp_69 As u8 Ptr
    Dim c2fb_temp_70 As UByte
    Dim c2fb_temp_71 As BtreeCellSizeProc Ptr
    Dim c2fb_temp_72 As c2fb_callback_84
    Dim c2fb_temp_73 As BtreeCellParseProc Ptr
    Dim c2fb_temp_74 As c2fb_callback_85

    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = arg0->pBt
    local0 = c2fb_temp_0
    c2fb_temp_1 = @(arg0->max1bytePayload)
    c2fb_temp_2 = Cast(UByte, local0->max1bytePayload)
    (*c2fb_temp_1) = Cast(u8, Cast(UByte, local0->max1bytePayload))
    c2fb_temp_2 = Cast(UByte, (*c2fb_temp_1))
    If (-Cast(SQLITE_C_INT, ((arg1 >= (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H02ULL) Or Cast(SQLITE_C_INT, &H08ULL)))))))) Then
        c2fb_temp_3 = @(arg0->childPtrSize)
        c2fb_temp_4 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_3) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, &O0ULL)))
        c2fb_temp_4 = Cast(UByte, (*c2fb_temp_3))
        c2fb_temp_5 = @(arg0->leaf)
        c2fb_temp_6 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
        (*c2fb_temp_5) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 1ULL)))
        c2fb_temp_6 = Cast(UByte, (*c2fb_temp_5))
        If (-Cast(SQLITE_C_INT, ((arg1 = (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H04ULL) Or Cast(SQLITE_C_INT, &H01ULL))) Or Cast(SQLITE_C_INT, &H08ULL)))))))) Then
            c2fb_temp_7 = @(arg0->intKeyLeaf)
            c2fb_temp_8 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
            (*c2fb_temp_7) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 1ULL)))
            c2fb_temp_8 = Cast(UByte, (*c2fb_temp_7))
            c2fb_temp_9 = @(arg0->xCellSize)
            c2fb_temp_10 = CPtr(c2fb_callback_84, ProcPtr(cellSizePtrTableLeaf))
            (*c2fb_temp_9) = Cast(BtreeCellSizeProc, CPtr(c2fb_callback_84, ProcPtr(cellSizePtrTableLeaf)))
            c2fb_temp_10 = CPtr(c2fb_callback_84, (*c2fb_temp_9))
            c2fb_temp_11 = @(arg0->xParseCell)
            c2fb_temp_12 = CPtr(c2fb_callback_85, ProcPtr(btreeParseCellPtr))
            (*c2fb_temp_11) = Cast(BtreeCellParseProc, CPtr(c2fb_callback_85, ProcPtr(btreeParseCellPtr)))
            c2fb_temp_12 = CPtr(c2fb_callback_85, (*c2fb_temp_11))
            c2fb_temp_13 = @(arg0->intKey)
            c2fb_temp_14 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
            (*c2fb_temp_13) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 1ULL)))
            c2fb_temp_14 = Cast(UByte, (*c2fb_temp_13))
            c2fb_temp_15 = @(arg0->maxLocal)
            c2fb_temp_16 = Cast(UShort, local0->maxLeaf)
            (*c2fb_temp_15) = Cast(u16, Cast(UShort, local0->maxLeaf))
            c2fb_temp_16 = Cast(UShort, (*c2fb_temp_15))
            c2fb_temp_17 = @(arg0->minLocal)
            c2fb_temp_18 = Cast(UShort, local0->minLeaf)
            (*c2fb_temp_17) = Cast(u16, Cast(UShort, local0->minLeaf))
            c2fb_temp_18 = Cast(UShort, (*c2fb_temp_17))
        Else
            If (-Cast(SQLITE_C_INT, ((arg1 = (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H02ULL) Or Cast(SQLITE_C_INT, &H08ULL)))))))) Then
                c2fb_temp_19 = @(arg0->intKey)
                c2fb_temp_20 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_19) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, &O0ULL)))
                c2fb_temp_20 = Cast(UByte, (*c2fb_temp_19))
                c2fb_temp_21 = @(arg0->intKeyLeaf)
                c2fb_temp_22 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_21) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, &O0ULL)))
                c2fb_temp_22 = Cast(UByte, (*c2fb_temp_21))
                c2fb_temp_23 = @(arg0->xCellSize)
                c2fb_temp_24 = CPtr(c2fb_callback_84, ProcPtr(cellSizePtrIdxLeaf))
                (*c2fb_temp_23) = Cast(BtreeCellSizeProc, CPtr(c2fb_callback_84, ProcPtr(cellSizePtrIdxLeaf)))
                c2fb_temp_24 = CPtr(c2fb_callback_84, (*c2fb_temp_23))
                c2fb_temp_25 = @(arg0->xParseCell)
                c2fb_temp_26 = CPtr(c2fb_callback_85, ProcPtr(btreeParseCellPtrIndex))
                (*c2fb_temp_25) = Cast(BtreeCellParseProc, CPtr(c2fb_callback_85, ProcPtr(btreeParseCellPtrIndex)))
                c2fb_temp_26 = CPtr(c2fb_callback_85, (*c2fb_temp_25))
                c2fb_temp_27 = @(arg0->maxLocal)
                c2fb_temp_28 = Cast(UShort, local0->maxLocal)
                (*c2fb_temp_27) = Cast(u16, Cast(UShort, local0->maxLocal))
                c2fb_temp_28 = Cast(UShort, (*c2fb_temp_27))
                c2fb_temp_29 = @(arg0->minLocal)
                c2fb_temp_30 = Cast(UShort, local0->minLocal)
                (*c2fb_temp_29) = Cast(u16, Cast(UShort, local0->minLocal))
                c2fb_temp_30 = Cast(UShort, (*c2fb_temp_29))
            Else
                c2fb_temp_31 = @(arg0->intKey)
                c2fb_temp_32 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_31) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, &O0ULL)))
                c2fb_temp_32 = Cast(UByte, (*c2fb_temp_31))
                c2fb_temp_33 = @(arg0->intKeyLeaf)
                c2fb_temp_34 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_33) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, &O0ULL)))
                c2fb_temp_34 = Cast(UByte, (*c2fb_temp_33))
                c2fb_temp_35 = @(arg0->xCellSize)
                c2fb_temp_36 = CPtr(c2fb_callback_84, ProcPtr(cellSizePtrIdxLeaf))
                (*c2fb_temp_35) = Cast(BtreeCellSizeProc, CPtr(c2fb_callback_84, ProcPtr(cellSizePtrIdxLeaf)))
                c2fb_temp_36 = CPtr(c2fb_callback_84, (*c2fb_temp_35))
                c2fb_temp_37 = @(arg0->xParseCell)
                c2fb_temp_38 = CPtr(c2fb_callback_85, ProcPtr(btreeParseCellPtrIndex))
                (*c2fb_temp_37) = Cast(BtreeCellParseProc, CPtr(c2fb_callback_85, ProcPtr(btreeParseCellPtrIndex)))
                c2fb_temp_38 = CPtr(c2fb_callback_85, (*c2fb_temp_37))
                Return sqlite3CorruptError(Cast(SQLITE_C_INT, 2084ULL))
            End If
        End If
    Else
        c2fb_temp_39 = @(arg0->childPtrSize)
        c2fb_temp_40 = Cast(UByte, Cast(SQLITE_C_INT, 4ULL))
        (*c2fb_temp_39) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 4ULL)))
        c2fb_temp_40 = Cast(UByte, (*c2fb_temp_39))
        c2fb_temp_41 = @(arg0->leaf)
        c2fb_temp_42 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_41) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, &O0ULL)))
        c2fb_temp_42 = Cast(UByte, (*c2fb_temp_41))
        If (-Cast(SQLITE_C_INT, ((arg1 = (Cast(SQLITE_C_INT, &H02ULL)))))) Then
            c2fb_temp_43 = @(arg0->intKey)
            c2fb_temp_44 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_43) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, &O0ULL)))
            c2fb_temp_44 = Cast(UByte, (*c2fb_temp_43))
            c2fb_temp_45 = @(arg0->intKeyLeaf)
            c2fb_temp_46 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_45) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, &O0ULL)))
            c2fb_temp_46 = Cast(UByte, (*c2fb_temp_45))
            c2fb_temp_47 = @(arg0->xCellSize)
            c2fb_temp_48 = CPtr(c2fb_callback_84, ProcPtr(cellSizePtr))
            (*c2fb_temp_47) = Cast(BtreeCellSizeProc, CPtr(c2fb_callback_84, ProcPtr(cellSizePtr)))
            c2fb_temp_48 = CPtr(c2fb_callback_84, (*c2fb_temp_47))
            c2fb_temp_49 = @(arg0->xParseCell)
            c2fb_temp_50 = CPtr(c2fb_callback_85, ProcPtr(btreeParseCellPtrIndex))
            (*c2fb_temp_49) = Cast(BtreeCellParseProc, CPtr(c2fb_callback_85, ProcPtr(btreeParseCellPtrIndex)))
            c2fb_temp_50 = CPtr(c2fb_callback_85, (*c2fb_temp_49))
            c2fb_temp_51 = @(arg0->maxLocal)
            c2fb_temp_52 = Cast(UShort, local0->maxLocal)
            (*c2fb_temp_51) = Cast(u16, Cast(UShort, local0->maxLocal))
            c2fb_temp_52 = Cast(UShort, (*c2fb_temp_51))
            c2fb_temp_53 = @(arg0->minLocal)
            c2fb_temp_54 = Cast(UShort, local0->minLocal)
            (*c2fb_temp_53) = Cast(u16, Cast(UShort, local0->minLocal))
            c2fb_temp_54 = Cast(UShort, (*c2fb_temp_53))
        Else
            If (-Cast(SQLITE_C_INT, ((arg1 = (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H04ULL) Or Cast(SQLITE_C_INT, &H01ULL)))))))) Then
                c2fb_temp_55 = @(arg0->intKeyLeaf)
                c2fb_temp_56 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_55) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, &O0ULL)))
                c2fb_temp_56 = Cast(UByte, (*c2fb_temp_55))
                c2fb_temp_57 = @(arg0->xCellSize)
                c2fb_temp_58 = CPtr(c2fb_callback_84, ProcPtr(cellSizePtrNoPayload))
                (*c2fb_temp_57) = Cast(BtreeCellSizeProc, CPtr(c2fb_callback_84, ProcPtr(cellSizePtrNoPayload)))
                c2fb_temp_58 = CPtr(c2fb_callback_84, (*c2fb_temp_57))
                c2fb_temp_59 = @(arg0->xParseCell)
                c2fb_temp_60 = CPtr(c2fb_callback_85, ProcPtr(btreeParseCellPtrNoPayload))
                (*c2fb_temp_59) = Cast(BtreeCellParseProc, CPtr(c2fb_callback_85, ProcPtr(btreeParseCellPtrNoPayload)))
                c2fb_temp_60 = CPtr(c2fb_callback_85, (*c2fb_temp_59))
                c2fb_temp_61 = @(arg0->intKey)
                c2fb_temp_62 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
                (*c2fb_temp_61) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 1ULL)))
                c2fb_temp_62 = Cast(UByte, (*c2fb_temp_61))
                c2fb_temp_63 = @(arg0->maxLocal)
                c2fb_temp_64 = Cast(UShort, local0->maxLeaf)
                (*c2fb_temp_63) = Cast(u16, Cast(UShort, local0->maxLeaf))
                c2fb_temp_64 = Cast(UShort, (*c2fb_temp_63))
                c2fb_temp_65 = @(arg0->minLocal)
                c2fb_temp_66 = Cast(UShort, local0->minLeaf)
                (*c2fb_temp_65) = Cast(u16, Cast(UShort, local0->minLeaf))
                c2fb_temp_66 = Cast(UShort, (*c2fb_temp_65))
            Else
                c2fb_temp_67 = @(arg0->intKey)
                c2fb_temp_68 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_67) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, &O0ULL)))
                c2fb_temp_68 = Cast(UByte, (*c2fb_temp_67))
                c2fb_temp_69 = @(arg0->intKeyLeaf)
                c2fb_temp_70 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_69) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, &O0ULL)))
                c2fb_temp_70 = Cast(UByte, (*c2fb_temp_69))
                c2fb_temp_71 = @(arg0->xCellSize)
                c2fb_temp_72 = CPtr(c2fb_callback_84, ProcPtr(cellSizePtr))
                (*c2fb_temp_71) = Cast(BtreeCellSizeProc, CPtr(c2fb_callback_84, ProcPtr(cellSizePtr)))
                c2fb_temp_72 = CPtr(c2fb_callback_84, (*c2fb_temp_71))
                c2fb_temp_73 = @(arg0->xParseCell)
                c2fb_temp_74 = CPtr(c2fb_callback_85, ProcPtr(btreeParseCellPtrIndex))
                (*c2fb_temp_73) = Cast(BtreeCellParseProc, CPtr(c2fb_callback_85, ProcPtr(btreeParseCellPtrIndex)))
                c2fb_temp_74 = CPtr(c2fb_callback_85, (*c2fb_temp_73))
                Return sqlite3CorruptError(Cast(SQLITE_C_INT, 2108ULL))
            End If
        End If
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Sub zeroPage CDecl Alias "zeroPage" (ByVal arg0 As MemPage Ptr, ByVal arg1 As SQLITE_C_INT)
    Dim local0 As UByte Ptr
    Dim local1 As BtShared Ptr
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim c2fb_temp_0 As Any Ptr
    Dim c2fb_temp_1 As UByte Ptr
    Dim c2fb_temp_2 As UByte
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As Any Ptr
    Dim c2fb_temp_5 As UByte Ptr
    Dim c2fb_temp_6 As UByte
    Dim c2fb_temp_7 As UByte Ptr
    Dim c2fb_temp_8 As UByte
    Dim c2fb_temp_9 As UByte Ptr
    Dim c2fb_temp_10 As UByte
    Dim c2fb_temp_11 As UByte
    Dim c2fb_temp_12 As SQLITE_C_INT Ptr
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As u16 Ptr
    Dim c2fb_temp_15 As UShort
    Dim c2fb_temp_16 As UByte Ptr Ptr
    Dim c2fb_temp_17 As UByte Ptr
    Dim c2fb_temp_18 As UByte Ptr Ptr
    Dim c2fb_temp_19 As UByte Ptr
    Dim c2fb_temp_20 As UByte Ptr Ptr
    Dim c2fb_temp_21 As UByte Ptr
    Dim c2fb_temp_22 As u8 Ptr
    Dim c2fb_temp_23 As UByte
    Dim c2fb_temp_24 As u16 Ptr
    Dim c2fb_temp_25 As UShort
    Dim c2fb_temp_26 As u16 Ptr
    Dim c2fb_temp_27 As UShort
    Dim c2fb_temp_28 As u8 Ptr
    Dim c2fb_temp_29 As UByte

    local0 = arg0->aData
    local1 = arg0->pBt
    local2 = arg0->hdrOffset
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->btsFlags) And Cast(SQLITE_C_INT, &H000cULL))) Then
        c2fb_temp_0 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(UByte Ptr, @(local0[local2]))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_UINT, (local1->usableSize - Cast(SQLITE_C_UINT, local2)))))
    End If
    c2fb_temp_1 = @(local0[local2])
    c2fb_temp_2 = Cast(UByte, Cast(Byte, arg1))
    (*c2fb_temp_1) = c2fb_temp_2
    c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local2 + (IIf((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (arg1 And Cast(SQLITE_C_INT, &H08ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))), Cast(SQLITE_C_INT, 12ULL), Cast(SQLITE_C_INT, 8ULL))))))
    local3 = c2fb_temp_3
    c2fb_temp_4 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(UByte Ptr, @(local0[Cast(SQLITE_C_INT, (local2 + Cast(SQLITE_C_INT, 1ULL)))]))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, 4ULL)))
    c2fb_temp_5 = @(local0[Cast(SQLITE_C_INT, (local2 + Cast(SQLITE_C_INT, 7ULL)))])
    c2fb_temp_6 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_5) = c2fb_temp_6
    c2fb_temp_7 = @((CPtr(UByte Ptr, @(local0[Cast(SQLITE_C_INT, (local2 + Cast(SQLITE_C_INT, 5ULL)))])))[Cast(SQLITE_C_INT, &O0ULL)])
    c2fb_temp_8 = Cast(UByte, Cast(UByte, (Cast(SQLITE_C_UINT, ((local1->usableSize) Shr Cast(SQLITE_C_INT, 8ULL))))))
    (*c2fb_temp_7) = c2fb_temp_8
    c2fb_temp_9 = @((CPtr(UByte Ptr, @(local0[Cast(SQLITE_C_INT, (local2 + Cast(SQLITE_C_INT, 5ULL)))])))[Cast(SQLITE_C_INT, 1ULL)])
    c2fb_temp_10 = Cast(UByte, Cast(UByte, (local1->usableSize)))
    (*c2fb_temp_9) = c2fb_temp_10
    c2fb_temp_11 = (c2fb_temp_10)
    c2fb_temp_12 = @(arg0->nFree)
    c2fb_temp_13 = Cast(SQLITE_C_INT, Cast(UShort, (Cast(SQLITE_C_UINT, (local1->usableSize - Cast(SQLITE_C_UINT, local3))))))
    (*c2fb_temp_12) = c2fb_temp_13
    decodeFlags(arg0, arg1)
    c2fb_temp_14 = @(arg0->cellOffset)
    c2fb_temp_15 = Cast(UShort, Cast(UShort, local3))
    (*c2fb_temp_14) = Cast(u16, Cast(UShort, Cast(UShort, local3)))
    c2fb_temp_15 = Cast(UShort, (*c2fb_temp_14))
    c2fb_temp_16 = @(arg0->aDataEnd)
    c2fb_temp_17 = CPtr(UByte Ptr, @(local0[local1->pageSize]))
    (*c2fb_temp_16) = c2fb_temp_17
    c2fb_temp_18 = @(arg0->aCellIdx)
    c2fb_temp_19 = CPtr(UByte Ptr, @(local0[local3]))
    (*c2fb_temp_18) = c2fb_temp_19
    c2fb_temp_20 = @(arg0->aDataOfst)
    c2fb_temp_21 = CPtr(UByte Ptr, @(local0[arg0->childPtrSize]))
    (*c2fb_temp_20) = c2fb_temp_21
    c2fb_temp_22 = @(arg0->nOverflow)
    c2fb_temp_23 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_22) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, &O0ULL)))
    c2fb_temp_23 = Cast(UByte, (*c2fb_temp_22))
    ' C unused-parameter annotation
    c2fb_temp_24 = @(arg0->maskPage)
    c2fb_temp_25 = Cast(UShort, Cast(UShort, (Cast(SQLITE_C_UINT, (local1->pageSize - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))))
    (*c2fb_temp_24) = Cast(u16, Cast(UShort, Cast(UShort, (Cast(SQLITE_C_UINT, (local1->pageSize - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))))))
    c2fb_temp_25 = Cast(UShort, (*c2fb_temp_24))
    c2fb_temp_26 = @(arg0->nCell)
    c2fb_temp_27 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_26) = Cast(u16, Cast(UShort, Cast(SQLITE_C_INT, &O0ULL)))
    c2fb_temp_27 = Cast(UShort, (*c2fb_temp_26))
    c2fb_temp_28 = @(arg0->isInit)
    c2fb_temp_29 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
    (*c2fb_temp_28) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 1ULL)))
    c2fb_temp_29 = Cast(UByte, (*c2fb_temp_28))
End Sub

/' end of sqlite3_bulk_btree_pageformat.bas '/
