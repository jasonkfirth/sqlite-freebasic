/'
    Project: SQLite FreeBASIC port

    File: sqlite3_bulk_vdbeaux_clearobject.bas

    Purpose:

        Release owned column-name, variable, subprogram, and opcode storage
        when a VDBE is cleared.

    Responsibilities:

        - Port sqlite3VdbeClearObject from src/vdbeaux.c.
        - Include its procedure-local memory and opcode release helpers.
        - Route P4 cleanup through the shared freeP4 implementation.

    This file intentionally does NOT contain:

        - Statement execution, reset policy, or general VDBE allocation.
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
#include once "sqlite3_db_types.bi"
#include once "sqlite3_varint.bi"
#include once "sqlite3_vfs.bi"
#include once "sqlite3_fault.bi"
#include once "sqlite3_pager.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_vdbe_cursor.bi"
#include once "sqlite3_result.bi"
#include once "sqlite3_btree.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_schema_types.bi"
Declare Sub vdbeFreeOpArray CDecl Alias "vdbeFreeOpArray" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteVdbeOp Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Sub releaseMemArray CDecl Alias "releaseMemArray" (ByVal arg0 As SqliteVdbeMem Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Sub sqlite3VdbeClearObject CDecl Alias "sqlite3VdbeClearObject" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteVdbe Ptr)

Private Sub vdbeFreeOpArray CDecl Alias "vdbeFreeOpArray" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteVdbeOp Ptr, ByVal arg2 As SQLITE_C_INT)
    Dim local0 As SqliteVdbeOp Ptr
    Dim c2fb_temp_0 As SqliteVdbeOp Ptr

    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If arg1 Then
        local0 = CPtr(SqliteVdbeOp Ptr, @(arg1[Cast(SQLITE_C_INT, (arg2 - Cast(SQLITE_C_INT, 1ULL)))]))
        While Cast(SQLITE_C_INT, 1ULL)
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->p4type) <= (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 7ULL)))))))) Then
                freeP4(arg0, local0->p4type, local0->p4.p)
            End If
            If (-Cast(SQLITE_C_INT, ((local0 = arg1)))) Then
                Goto c2fb_flow_0
            End If
            c2fb_temp_0 = local0
            local0 = (c2fb_temp_0 - 1)
        c2fb_flow_1:
        Wend
        c2fb_flow_0:
        sqlite3DbNNFreeNN(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1))
    End If
End Sub

Private Sub releaseMemArray CDecl Alias "releaseMemArray" (ByVal arg0 As SqliteVdbeMem Ptr, ByVal arg1 As SQLITE_C_INT)
    Dim local0 As SqliteVdbeMem Ptr
    Dim local1 As sqlite3 Ptr
    Dim c2fb_temp_0 As SqliteVdbeMem Ptr
    Dim c2fb_temp_1 As SqliteVdbeMem Ptr
    Dim c2fb_temp_2 As UShort Ptr
    Dim c2fb_temp_3 As UShort
    Dim c2fb_temp_4 As SQLITE_C_INT Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As UShort Ptr
    Dim c2fb_temp_7 As UShort
    Dim c2fb_temp_8 As SqliteVdbeMem Ptr
    Dim c2fb_temp_9 As SqliteVdbeMem Ptr

    If (-Cast(SQLITE_C_INT, ((arg0 AndAlso arg1)))) Then
        local0 = CPtr(SqliteVdbeMem Ptr, @(arg0[arg1]))
        local1 = arg0->db
        ' C unused-parameter annotation
        If local1->pnBytesFreed Then
            Do
                If arg0->szMalloc Then
                    sqlite3DbFree(CPtr(Any Ptr, local1), CPtr(Any Ptr, CPtr(ZString Ptr, arg0->zMalloc)))
                End If
            c2fb_flow_1:
                c2fb_temp_0 = arg0
                arg0 = (c2fb_temp_0 + 1)
                c2fb_temp_1 = arg0
            Loop While (-Cast(SQLITE_C_INT, (((c2fb_temp_1) < local0))))
            c2fb_flow_0:
            Return
        End If
        Do
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' empty C statement
            ' empty C statement
            If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->flags) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H8000ULL) Or Cast(SQLITE_C_INT, &H1000ULL)))))) Then
                ' empty C statement
                sqlite3VdbeMemRelease(CPtr(Any Ptr, arg0))
                c2fb_temp_2 = @(arg0->flags)
                c2fb_temp_3 = Cast(UShort, Cast(SQLITE_C_INT, &H0000ULL))
                (*c2fb_temp_2) = c2fb_temp_3
            Else
                If arg0->szMalloc Then
                    sqlite3DbNNFreeNN(CPtr(Any Ptr, local1), CPtr(Any Ptr, CPtr(ZString Ptr, arg0->zMalloc)))
                    c2fb_temp_4 = @(arg0->szMalloc)
                    c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    (*c2fb_temp_4) = c2fb_temp_5
                    c2fb_temp_6 = @(arg0->flags)
                    c2fb_temp_7 = Cast(UShort, Cast(SQLITE_C_INT, &H0000ULL))
                    (*c2fb_temp_6) = c2fb_temp_7
                End If
            End If
        c2fb_flow_3:
            c2fb_temp_8 = arg0
            arg0 = (c2fb_temp_8 + 1)
            c2fb_temp_9 = arg0
        Loop While (-Cast(SQLITE_C_INT, (((c2fb_temp_9) < local0))))
        c2fb_flow_2:
    End If
End Sub

Private Sub sqlite3VdbeClearObject CDecl Alias "sqlite3VdbeClearObject" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteVdbe Ptr)
    Dim local0 As SqliteVdbeSubProgram Ptr
    Dim local1 As SqliteVdbeSubProgram Ptr
    Dim c2fb_temp_0 As SqliteVdbeSubProgram Ptr
    Dim c2fb_temp_1 As SqliteVdbeSubProgram Ptr
    Dim c2fb_temp_2 As SqliteVdbeSubProgram Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If arg1->aColName Then
        releaseMemArray(arg1->aColName, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->nResAlloc) * Cast(SQLITE_C_INT, 2ULL))))
        sqlite3DbNNFreeNN(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->aColName))
    End If
    c2fb_temp_0 = CPtr(SqliteVdbeSubProgram Ptr, arg1->pProgram)
    local0 = c2fb_temp_0
    While local0
        c2fb_temp_2 = CPtr(SqliteVdbeSubProgram Ptr, local0->pNext)
        local1 = c2fb_temp_2
        vdbeFreeOpArray(arg0, local0->aOp, local0->nOp)
        sqlite3DbFree(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local0))
    c2fb_flow_1:
        c2fb_temp_1 = local1
        local0 = c2fb_temp_1
    Wend
    c2fb_flow_0:
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->eVdbeState) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        releaseMemArray(arg1->aVar, arg1->nVar)
        If CPtr(SQLITE_C_INT Ptr, arg1->pVList) Then
            sqlite3DbNNFreeNN(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SQLITE_C_INT Ptr, arg1->pVList)))
        End If
        If arg1->pFree Then
            sqlite3DbNNFreeNN(CPtr(Any Ptr, arg0), arg1->pFree)
        End If
    End If
    vdbeFreeOpArray(arg0, arg1->aOp, arg1->nOp)
    If arg1->zSql Then
        sqlite3DbNNFreeNN(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->zSql))
    End If
End Sub

/' end of sqlite3_bulk_vdbeaux_clearobject.bas '/
