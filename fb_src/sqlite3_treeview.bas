/'
    Project: SQLite FreeBASIC port

    File: sqlite3_treeview.bas

    Purpose:

        Render parser and query structures as an indented debug tree.

    Responsibilities:

        - Maintain the fixed indentation stack used by nested tree items.
        - Format tree lines through SQLite's string accumulator and debug logger.
        - Render source lists, expressions, SELECTs, windows, triggers, DML,
          columns, expression lists, and identifier lists.

    This file intentionally does NOT contain:

        - SQL compilation, VDBE execution, or test-only coverage hooks.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_agginfo_types.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_hash_types.bi"
#include once "sqlite3_pager.bi"
#include once "sqlite3_btree.bi"

#include once "sqlite3_db_types.bi"
#include once "sqlite3_walker.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_straccum.bi"
#include once "sqlite3_wal_types.bi"
#include once "sqlite3_fkey_types.bi"
#include once "sqlite3_result.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_treeview_types.bi"
#include once "sqlite3_debug_assert.bi"

#ifdef SQLITE_DEBUG
Private Sub sqlite3TreeViewAssert( _
    ByVal condition As SQLITE_C_INT, _
    ByVal expression As Const ZString Ptr _
)
    If condition = 0 Then sqlite3DebugAssert(expression)
End Sub

Private Sub sqlite3TreeViewCheckExprAssertions(ByVal pExpr As Const SqliteExpr Ptr)
    Select Case pExpr->op
    Case TK_COLUMN
        If pExpr->iTable >= 0 Then
            sqlite3TreeViewAssert( _
                CInt((pExpr->flags And (EP_WinFunc Or EP_Subrtn)) = 0), _
                StrPtr("ExprUseYTab(pExpr)"))
        End If
    Case TK_FLOAT, TK_STRING, TK_BLOB, TK_VARIABLE, TK_ID, TK_CAST, TK_SPAN, _
         TK_COLLATE, TK_RAISE
        sqlite3TreeViewAssert( _
            CInt((pExpr->flags And EP_IntValue) = 0), _
            StrPtr("!ExprHasProperty(pExpr, EP_IntValue)"))
    Case TK_TRUTH
        sqlite3TreeViewAssert( _
            CInt(pExpr->op2 = TK_IS OrElse pExpr->op2 = TK_ISNOT), _
            StrPtr("pExpr->op2==TK_IS || pExpr->op2==TK_ISNOT"))
        sqlite3TreeViewAssert(CInt(pExpr->pRight <> 0), StrPtr("pExpr->pRight"))
        If pExpr->pRight <> 0 Then
            Dim pTruthExpr As Const SqliteExpr Ptr = _
                sqlite3ExprSkipCollateAndLikely(pExpr->pRight)
            sqlite3TreeViewAssert( _
                CInt(pTruthExpr <> 0 AndAlso pTruthExpr->op = TK_TRUEFALSE), _
                StrPtr("sqlite3ExprSkipCollateAndLikely(pExpr->pRight)->op==TK_TRUEFALSE"))
        End If
    Case TK_FUNCTION, TK_AGG_FUNCTION
        sqlite3TreeViewAssert( _
            CInt((pExpr->flags And EP_IntValue) = 0), _
            StrPtr("!ExprHasProperty(pExpr, EP_IntValue)"))
        If (pExpr->flags And EP_TokenOnly) = 0 Then
            sqlite3TreeViewAssert( _
                CInt((pExpr->flags And EP_xIsSelect) = 0), _
                StrPtr("ExprUseXList(pExpr)"))
        End If
        If pExpr->pLeft <> 0 Then
            sqlite3TreeViewAssert( _
                CInt(pExpr->pLeft->op = TK_ORDER), _
                StrPtr("pOB->op==TK_ORDER"))
            sqlite3TreeViewAssert( _
                CInt((pExpr->pLeft->flags And EP_xIsSelect) = 0), _
                StrPtr("ExprUseXList(pOB)"))
        End If
    Case TK_EXISTS, TK_SELECT
        sqlite3TreeViewAssert( _
            CInt((pExpr->flags And EP_xIsSelect) <> 0), _
            StrPtr("ExprUseXSelect(pExpr)"))
    Case TK_BETWEEN
        sqlite3TreeViewAssert( _
            CInt((pExpr->flags And EP_xIsSelect) = 0), _
            StrPtr("ExprUseXList(pExpr)"))
        If pExpr->x.pList = 0 Then
            sqlite3DebugAssert(StrPtr("pExpr->x.pList!=0"))
        Else
            sqlite3TreeViewAssert( _
                CInt(pExpr->x.pList->nExpr = 2), _
                StrPtr("pExpr->x.pList->nExpr==2"))
        End If
    Case TK_CASE, TK_VECTOR
        sqlite3TreeViewAssert( _
            CInt((pExpr->flags And EP_xIsSelect) = 0), _
            StrPtr("ExprUseXList(pExpr)"))
    Case TK_SELECT_COLUMN
        If pExpr->pLeft = 0 Then
            sqlite3DebugAssert(StrPtr("ExprUseXSelect(pExpr->pLeft)"))
        Else
            sqlite3TreeViewAssert( _
                CInt((pExpr->pLeft->flags And EP_xIsSelect) <> 0), _
                StrPtr("ExprUseXSelect(pExpr->pLeft)"))
        End If
    End Select
End Sub

Declare Function sqlite3_libversion CDecl Alias "sqlite3_libversion" () As Const ZString Ptr
Declare Function sqlite3_sourceid CDecl Alias "sqlite3_sourceid" () As Const ZString Ptr
Declare Function sqlite3_libversion_number CDecl Alias "sqlite3_libversion_number" () As SQLITE_C_INT
Declare Function sqlite3_compileoption_used CDecl Alias "sqlite3_compileoption_used" (ByVal arg0 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3_compileoption_get CDecl Alias "sqlite3_compileoption_get" (ByVal arg0 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3_threadsafe CDecl Alias "sqlite3_threadsafe" () As SQLITE_C_INT
Declare Function sqlite3_close CDecl Alias "sqlite3_close" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_close_v2 CDecl Alias "sqlite3_close_v2" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_exec CDecl Alias "sqlite3_exec" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As ZString Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_initialize CDecl Alias "sqlite3_initialize" () As SQLITE_C_INT
Declare Function sqlite3_shutdown CDecl Alias "sqlite3_shutdown" () As SQLITE_C_INT
Declare Function sqlite3_os_init CDecl Alias "sqlite3_os_init" () As SQLITE_C_INT
Declare Function sqlite3_os_end CDecl Alias "sqlite3_os_end" () As SQLITE_C_INT
Declare Function sqlite3_config CDecl Alias "sqlite3_config" (ByVal arg0 As SQLITE_C_INT, ...) As SQLITE_C_INT
Declare Function sqlite3_db_config CDecl Alias "sqlite3_db_config" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ...) As SQLITE_C_INT
Declare Function sqlite3_extended_result_codes CDecl Alias "sqlite3_extended_result_codes" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_last_insert_rowid CDecl Alias "sqlite3_last_insert_rowid" (ByVal arg0 As Any Ptr) As sqlite3_int64
Declare Sub sqlite3_set_last_insert_rowid CDecl Alias "sqlite3_set_last_insert_rowid" (ByVal arg0 As Any Ptr, ByVal arg1 As sqlite3_int64)
Declare Function sqlite3_changes CDecl Alias "sqlite3_changes" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_changes64 CDecl Alias "sqlite3_changes64" (ByVal arg0 As Any Ptr) As sqlite3_int64
Declare Function sqlite3_total_changes CDecl Alias "sqlite3_total_changes" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_total_changes64 CDecl Alias "sqlite3_total_changes64" (ByVal arg0 As Any Ptr) As sqlite3_int64
Declare Sub sqlite3_interrupt CDecl Alias "sqlite3_interrupt" (ByVal arg0 As Any Ptr)
Declare Function sqlite3_is_interrupted CDecl Alias "sqlite3_is_interrupted" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_complete CDecl Alias "sqlite3_complete" (ByVal arg0 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3_complete16 CDecl Alias "sqlite3_complete16" (ByVal arg0 As Const Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_incomplete CDecl Alias "sqlite3_incomplete" (ByVal arg0 As Const ZString Ptr) As sqlite3_int64
Declare Function sqlite3_busy_handler CDecl Alias "sqlite3_busy_handler" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_busy_timeout CDecl Alias "sqlite3_busy_timeout" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_setlk_timeout CDecl Alias "sqlite3_setlk_timeout" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_get_table CDecl Alias "sqlite3_get_table" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As ZString Ptr Ptr Ptr, ByVal arg3 As SQLITE_C_INT Ptr, ByVal arg4 As SQLITE_C_INT Ptr, ByVal arg5 As ZString Ptr Ptr) As SQLITE_C_INT
Declare Sub sqlite3_free_table CDecl Alias "sqlite3_free_table" (ByVal arg0 As ZString Ptr Ptr)
Declare Function sqlite3_mprintf CDecl Alias "sqlite3_mprintf" (ByVal arg0 As Const ZString Ptr, ...) As ZString Ptr
Declare Function sqlite3_vmprintf CDecl Alias "sqlite3_vmprintf" (ByVal arg0 As Const ZString Ptr, ByRef arg1 As Cva_List) As ZString Ptr
Declare Function sqlite3_snprintf CDecl Alias "sqlite3_snprintf" (ByVal arg0 As SQLITE_C_INT, ByVal arg1 As ZString Ptr, ByVal arg2 As Const ZString Ptr, ...) As ZString Ptr
Declare Function sqlite3_vsnprintf CDecl Alias "sqlite3_vsnprintf" (ByVal arg0 As SQLITE_C_INT, ByVal arg1 As ZString Ptr, ByVal arg2 As Const ZString Ptr, ByRef arg3 As Cva_List) As ZString Ptr
Declare Function sqlite3_malloc CDecl Alias "sqlite3_malloc" (ByVal arg0 As SQLITE_C_INT) As Any Ptr
Declare Function sqlite3_malloc64 CDecl Alias "sqlite3_malloc64" (ByVal arg0 As sqlite3_uint64) As Any Ptr
Declare Function sqlite3_realloc CDecl Alias "sqlite3_realloc" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Any Ptr
Declare Function sqlite3_realloc64 CDecl Alias "sqlite3_realloc64" (ByVal arg0 As Any Ptr, ByVal arg1 As sqlite3_uint64) As Any Ptr
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal arg0 As Any Ptr)
Declare Function sqlite3_msize CDecl Alias "sqlite3_msize" (ByVal arg0 As Any Ptr) As sqlite3_uint64
Declare Sub sqlite3_randomness CDecl Alias "sqlite3_randomness" (ByVal arg0 As SQLITE_C_INT, ByVal arg1 As Any Ptr)
Declare Function sqlite3_set_authorizer CDecl Alias "sqlite3_set_authorizer" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_trace CDecl Alias "sqlite3_trace" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As Any Ptr
Declare Function sqlite3_profile CDecl Alias "sqlite3_profile" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As Any Ptr
Declare Function sqlite3_trace_v2 CDecl Alias "sqlite3_trace_v2" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3_progress_handler CDecl Alias "sqlite3_progress_handler" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr)
Declare Function sqlite3_open CDecl Alias "sqlite3_open" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_open16 CDecl Alias "sqlite3_open16" (ByVal arg0 As Const Any Ptr, ByVal arg1 As Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_open_v2 CDecl Alias "sqlite3_open_v2" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As Any Ptr Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3_uri_parameter CDecl Alias "sqlite3_uri_parameter" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As Const ZString Ptr) As Const ZString Ptr
Declare Function sqlite3_uri_boolean CDecl Alias "sqlite3_uri_boolean" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_uri_int64 CDecl Alias "sqlite3_uri_int64" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As sqlite3_int64) As sqlite3_int64
Declare Function sqlite3_uri_key CDecl Alias "sqlite3_uri_key" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3_filename_database CDecl Alias "sqlite3_filename_database" (ByVal arg0 As Const ZString Ptr) As Const ZString Ptr
Declare Function sqlite3_filename_journal CDecl Alias "sqlite3_filename_journal" (ByVal arg0 As Const ZString Ptr) As Const ZString Ptr
Declare Function sqlite3_filename_wal CDecl Alias "sqlite3_filename_wal" (ByVal arg0 As Const ZString Ptr) As Const ZString Ptr
Declare Function sqlite3_database_file_object CDecl Alias "sqlite3_database_file_object" (ByVal arg0 As Const ZString Ptr) As Any Ptr
Declare Function sqlite3_create_filename CDecl Alias "sqlite3_create_filename" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As Const ZString Ptr Ptr) As Const ZString Ptr
Declare Sub sqlite3_free_filename CDecl Alias "sqlite3_free_filename" (ByVal arg0 As Const ZString Ptr)
Declare Function sqlite3_errcode CDecl Alias "sqlite3_errcode" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_extended_errcode CDecl Alias "sqlite3_extended_errcode" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_errmsg CDecl Alias "sqlite3_errmsg" (ByVal arg0 As Any Ptr) As Const ZString Ptr
Declare Function sqlite3_errmsg16 CDecl Alias "sqlite3_errmsg16" (ByVal arg0 As Any Ptr) As Const Any Ptr
Declare Function sqlite3_errstr CDecl Alias "sqlite3_errstr" (ByVal arg0 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3_error_offset CDecl Alias "sqlite3_error_offset" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_set_errmsg CDecl Alias "sqlite3_set_errmsg" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3_limit CDecl Alias "sqlite3_limit" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_prepare CDecl Alias "sqlite3_prepare" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr Ptr, ByVal arg4 As Const ZString Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_prepare_v2 CDecl Alias "sqlite3_prepare_v2" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr Ptr, ByVal arg4 As Const ZString Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_prepare_v3 CDecl Alias "sqlite3_prepare_v3" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_UINT, ByVal arg4 As Any Ptr Ptr, ByVal arg5 As Const ZString Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_prepare16 CDecl Alias "sqlite3_prepare16" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr Ptr, ByVal arg4 As Const Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_prepare16_v2 CDecl Alias "sqlite3_prepare16_v2" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr Ptr, ByVal arg4 As Const Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_prepare16_v3 CDecl Alias "sqlite3_prepare16_v3" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_UINT, ByVal arg4 As Any Ptr Ptr, ByVal arg5 As Const Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_sql CDecl Alias "sqlite3_sql" (ByVal arg0 As Any Ptr) As Const ZString Ptr
Declare Function sqlite3_expanded_sql CDecl Alias "sqlite3_expanded_sql" (ByVal arg0 As Any Ptr) As ZString Ptr
Declare Function sqlite3_normalized_sql CDecl Alias "sqlite3_normalized_sql" (ByVal arg0 As Any Ptr) As Const ZString Ptr
Declare Function sqlite3_stmt_readonly CDecl Alias "sqlite3_stmt_readonly" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_stmt_isexplain CDecl Alias "sqlite3_stmt_isexplain" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_stmt_explain CDecl Alias "sqlite3_stmt_explain" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_stmt_busy CDecl Alias "sqlite3_stmt_busy" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_bind_blob CDecl Alias "sqlite3_bind_blob" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const Any Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_bind_blob64 CDecl Alias "sqlite3_bind_blob64" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const Any Ptr, ByVal arg3 As sqlite3_uint64, ByVal arg4 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_bind_double CDecl Alias "sqlite3_bind_double" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Double) As SQLITE_C_INT
Declare Function sqlite3_bind_int CDecl Alias "sqlite3_bind_int" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_bind_int64 CDecl Alias "sqlite3_bind_int64" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As sqlite3_int64) As SQLITE_C_INT
Declare Function sqlite3_bind_null CDecl Alias "sqlite3_bind_null" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_bind_text CDecl Alias "sqlite3_bind_text" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_bind_text16 CDecl Alias "sqlite3_bind_text16" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const Any Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_bind_text64 CDecl Alias "sqlite3_bind_text64" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr, ByVal arg3 As sqlite3_uint64, ByVal arg4 As Any Ptr, ByVal arg5 As UByte) As SQLITE_C_INT
Declare Function sqlite3_bind_value CDecl Alias "sqlite3_bind_value" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_bind_pointer CDecl Alias "sqlite3_bind_pointer" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Any Ptr, ByVal arg3 As Const ZString Ptr, ByVal arg4 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_bind_zeroblob CDecl Alias "sqlite3_bind_zeroblob" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_bind_zeroblob64 CDecl Alias "sqlite3_bind_zeroblob64" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As sqlite3_uint64) As SQLITE_C_INT
Declare Function sqlite3_bind_parameter_count CDecl Alias "sqlite3_bind_parameter_count" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_bind_parameter_name CDecl Alias "sqlite3_bind_parameter_name" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3_bind_parameter_index CDecl Alias "sqlite3_bind_parameter_index" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3_clear_bindings CDecl Alias "sqlite3_clear_bindings" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_column_count CDecl Alias "sqlite3_column_count" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_column_name CDecl Alias "sqlite3_column_name" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3_column_name16 CDecl Alias "sqlite3_column_name16" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const Any Ptr
Declare Function sqlite3_column_database_name CDecl Alias "sqlite3_column_database_name" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3_column_database_name16 CDecl Alias "sqlite3_column_database_name16" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const Any Ptr
Declare Function sqlite3_column_table_name CDecl Alias "sqlite3_column_table_name" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3_column_table_name16 CDecl Alias "sqlite3_column_table_name16" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const Any Ptr
Declare Function sqlite3_column_origin_name CDecl Alias "sqlite3_column_origin_name" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3_column_origin_name16 CDecl Alias "sqlite3_column_origin_name16" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const Any Ptr
Declare Function sqlite3_column_decltype CDecl Alias "sqlite3_column_decltype" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3_column_decltype16 CDecl Alias "sqlite3_column_decltype16" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const Any Ptr
Declare Function sqlite3_step CDecl Alias "sqlite3_step" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_data_count CDecl Alias "sqlite3_data_count" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_column_blob CDecl Alias "sqlite3_column_blob" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const Any Ptr
Declare Function sqlite3_column_double CDecl Alias "sqlite3_column_double" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Double
Declare Function sqlite3_column_int CDecl Alias "sqlite3_column_int" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_column_int64 CDecl Alias "sqlite3_column_int64" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As sqlite3_int64
Declare Function sqlite3_column_text CDecl Alias "sqlite3_column_text" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const UByte Ptr
Declare Function sqlite3_column_text16 CDecl Alias "sqlite3_column_text16" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const Any Ptr
Declare Function sqlite3_column_value CDecl Alias "sqlite3_column_value" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Any Ptr
Declare Function sqlite3_column_bytes CDecl Alias "sqlite3_column_bytes" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_column_bytes16 CDecl Alias "sqlite3_column_bytes16" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_column_type CDecl Alias "sqlite3_column_type" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_finalize CDecl Alias "sqlite3_finalize" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_reset CDecl Alias "sqlite3_reset" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_create_function CDecl Alias "sqlite3_create_function" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As Any Ptr, ByVal arg5 As Any Ptr, ByVal arg6 As Any Ptr, ByVal arg7 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_create_function16 CDecl Alias "sqlite3_create_function16" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As Any Ptr, ByVal arg5 As Any Ptr, ByVal arg6 As Any Ptr, ByVal arg7 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_create_function_v2 CDecl Alias "sqlite3_create_function_v2" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As Any Ptr, ByVal arg5 As Any Ptr, ByVal arg6 As Any Ptr, ByVal arg7 As Any Ptr, ByVal arg8 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_create_window_function CDecl Alias "sqlite3_create_window_function" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As Any Ptr, ByVal arg5 As Any Ptr, ByVal arg6 As Any Ptr, ByVal arg7 As Any Ptr, ByVal arg8 As Any Ptr, ByVal arg9 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_expired CDecl Alias "sqlite3_expired" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_transfer_bindings CDecl Alias "sqlite3_transfer_bindings" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_global_recover CDecl Alias "sqlite3_global_recover" () As SQLITE_C_INT
Declare Sub sqlite3_thread_cleanup CDecl Alias "sqlite3_thread_cleanup" ()
Declare Function sqlite3_memory_alarm CDecl Alias "sqlite3_memory_alarm" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As sqlite3_int64) As SQLITE_C_INT
Declare Function sqlite3_user_data CDecl Alias "sqlite3_user_data" (ByVal arg0 As Any Ptr) As Any Ptr
Declare Function sqlite3_context_db_handle CDecl Alias "sqlite3_context_db_handle" (ByVal arg0 As Any Ptr) As Any Ptr
Declare Function sqlite3_get_auxdata CDecl Alias "sqlite3_get_auxdata" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Any Ptr
Declare Sub sqlite3_set_auxdata CDecl Alias "sqlite3_set_auxdata" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr)
Declare Function sqlite3_get_clientdata CDecl Alias "sqlite3_get_clientdata" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr) As Any Ptr
Declare Function sqlite3_set_clientdata CDecl Alias "sqlite3_set_clientdata" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3_result_blob CDecl Alias "sqlite3_result_blob" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr)
Declare Sub sqlite3_result_blob64 CDecl Alias "sqlite3_result_blob64" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As sqlite3_uint64, ByVal arg3 As Any Ptr)
Declare Sub sqlite3_result_double CDecl Alias "sqlite3_result_double" (ByVal arg0 As Any Ptr, ByVal arg1 As Double)
Declare Sub sqlite3_result_error CDecl Alias "sqlite3_result_error" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Sub sqlite3_result_error16 CDecl Alias "sqlite3_result_error16" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Sub sqlite3_result_error_toobig CDecl Alias "sqlite3_result_error_toobig" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3_result_error_nomem CDecl Alias "sqlite3_result_error_nomem" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3_result_error_code CDecl Alias "sqlite3_result_error_code" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Sub sqlite3_result_int CDecl Alias "sqlite3_result_int" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Sub sqlite3_result_int64 CDecl Alias "sqlite3_result_int64" (ByVal arg0 As Any Ptr, ByVal arg1 As sqlite3_int64)
Declare Sub sqlite3_result_null CDecl Alias "sqlite3_result_null" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3_result_text CDecl Alias "sqlite3_result_text" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr)
Declare Sub sqlite3_result_text64 CDecl Alias "sqlite3_result_text64" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As sqlite3_uint64, ByVal arg3 As Any Ptr, ByVal arg4 As UByte)
Declare Sub sqlite3_result_text16 CDecl Alias "sqlite3_result_text16" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr)
Declare Sub sqlite3_result_text16le CDecl Alias "sqlite3_result_text16le" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr)
Declare Sub sqlite3_result_text16be CDecl Alias "sqlite3_result_text16be" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr)
Declare Sub sqlite3_result_value CDecl Alias "sqlite3_result_value" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3_result_pointer CDecl Alias "sqlite3_result_pointer" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Any Ptr)
Declare Sub sqlite3_result_zeroblob CDecl Alias "sqlite3_result_zeroblob" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Function sqlite3_result_zeroblob64 CDecl Alias "sqlite3_result_zeroblob64" (ByVal arg0 As Any Ptr, ByVal arg1 As sqlite3_uint64) As SQLITE_C_INT
Declare Sub sqlite3_result_subtype CDecl Alias "sqlite3_result_subtype" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_UINT)
Declare Function sqlite3_create_collation CDecl Alias "sqlite3_create_collation" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_create_collation_v2 CDecl Alias "sqlite3_create_collation_v2" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr, ByVal arg5 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_create_collation16 CDecl Alias "sqlite3_create_collation16" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_collation_needed CDecl Alias "sqlite3_collation_needed" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_collation_needed16 CDecl Alias "sqlite3_collation_needed16" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3_activate_cerod CDecl Alias "sqlite3_activate_cerod" (ByVal arg0 As Const ZString Ptr)
Declare Function sqlite3_sleep CDecl Alias "sqlite3_sleep" (ByVal arg0 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_win32_set_directory CDecl Alias "sqlite3_win32_set_directory" (ByVal arg0 As SQLITE_C_ULONG, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_win32_set_directory8 CDecl Alias "sqlite3_win32_set_directory8" (ByVal arg0 As SQLITE_C_ULONG, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3_win32_set_directory16 CDecl Alias "sqlite3_win32_set_directory16" (ByVal arg0 As SQLITE_C_ULONG, ByVal arg1 As Const Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_get_autocommit CDecl Alias "sqlite3_get_autocommit" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_db_handle CDecl Alias "sqlite3_db_handle" (ByVal arg0 As Any Ptr) As Any Ptr
Declare Function sqlite3_db_name CDecl Alias "sqlite3_db_name" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3_db_filename CDecl Alias "sqlite3_db_filename" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr) As Const ZString Ptr
Declare Function sqlite3_db_readonly CDecl Alias "sqlite3_db_readonly" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3_txn_state CDecl Alias "sqlite3_txn_state" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3_next_stmt CDecl Alias "sqlite3_next_stmt" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As Any Ptr
Declare Function sqlite3_commit_hook CDecl Alias "sqlite3_commit_hook" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As Any Ptr
Declare Function sqlite3_rollback_hook CDecl Alias "sqlite3_rollback_hook" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As Any Ptr
Declare Function sqlite3_autovacuum_pages CDecl Alias "sqlite3_autovacuum_pages" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_update_hook CDecl Alias "sqlite3_update_hook" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As Any Ptr
Declare Function sqlite3_enable_shared_cache CDecl Alias "sqlite3_enable_shared_cache" (ByVal arg0 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_release_memory CDecl Alias "sqlite3_release_memory" (ByVal arg0 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_db_release_memory CDecl Alias "sqlite3_db_release_memory" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_soft_heap_limit64 CDecl Alias "sqlite3_soft_heap_limit64" (ByVal arg0 As sqlite3_int64) As sqlite3_int64
Declare Function sqlite3_hard_heap_limit64 CDecl Alias "sqlite3_hard_heap_limit64" (ByVal arg0 As sqlite3_int64) As sqlite3_int64
Declare Sub sqlite3_soft_heap_limit CDecl Alias "sqlite3_soft_heap_limit" (ByVal arg0 As SQLITE_C_INT)
Declare Function sqlite3_table_column_metadata CDecl Alias "sqlite3_table_column_metadata" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const ZString Ptr, ByVal arg4 As Const ZString Ptr Ptr, ByVal arg5 As Const ZString Ptr Ptr, ByVal arg6 As SQLITE_C_INT Ptr, ByVal arg7 As SQLITE_C_INT Ptr, ByVal arg8 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function sqlite3_load_extension CDecl Alias "sqlite3_load_extension" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As ZString Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_enable_load_extension CDecl Alias "sqlite3_enable_load_extension" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_auto_extension CDecl Alias "sqlite3_auto_extension" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_cancel_auto_extension CDecl Alias "sqlite3_cancel_auto_extension" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3_reset_auto_extension CDecl Alias "sqlite3_reset_auto_extension" ()
Declare Function sqlite3_create_module CDecl Alias "sqlite3_create_module" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Const Any Ptr, ByVal arg3 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_create_module_v2 CDecl Alias "sqlite3_create_module_v2" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Const Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_drop_modules CDecl Alias "sqlite3_drop_modules" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_declare_vtab CDecl Alias "sqlite3_declare_vtab" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3_overload_function CDecl Alias "sqlite3_overload_function" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_blob_open CDecl Alias "sqlite3_blob_open" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const ZString Ptr, ByVal arg4 As sqlite3_int64, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_blob_reopen CDecl Alias "sqlite3_blob_reopen" (ByVal arg0 As Any Ptr, ByVal arg1 As sqlite3_int64) As SQLITE_C_INT
Declare Function sqlite3_blob_close CDecl Alias "sqlite3_blob_close" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_blob_bytes CDecl Alias "sqlite3_blob_bytes" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_blob_read CDecl Alias "sqlite3_blob_read" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_blob_write CDecl Alias "sqlite3_blob_write" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_db_mutex CDecl Alias "sqlite3_db_mutex" (ByVal arg0 As Any Ptr) As Any Ptr
Declare Function sqlite3_file_control CDecl Alias "sqlite3_file_control" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_test_control CDecl Alias "sqlite3_test_control" (ByVal arg0 As SQLITE_C_INT, ...) As SQLITE_C_INT
Declare Function sqlite3_keyword_count CDecl Alias "sqlite3_keyword_count" () As SQLITE_C_INT
Declare Function sqlite3_keyword_name CDecl Alias "sqlite3_keyword_name" (ByVal arg0 As SQLITE_C_INT, ByVal arg1 As Const ZString Ptr Ptr, ByVal arg2 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function sqlite3_keyword_check CDecl Alias "sqlite3_keyword_check" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub sqlite3_result_str CDecl Alias "sqlite3_result_str" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Sub sqlite3_str_appendf CDecl Alias "sqlite3_str_appendf" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ...)
Declare Sub sqlite3_str_vappendf CDecl Alias "sqlite3_str_vappendf" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByRef arg2 As Cva_List)
Declare Function sqlite3_db_status CDecl Alias "sqlite3_db_status" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT Ptr, ByVal arg3 As SQLITE_C_INT Ptr, ByVal arg4 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_db_status64 CDecl Alias "sqlite3_db_status64" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As sqlite3_int64 Ptr, ByVal arg3 As sqlite3_int64 Ptr, ByVal arg4 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_stmt_status CDecl Alias "sqlite3_stmt_status" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_backup_init CDecl Alias "sqlite3_backup_init" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Const ZString Ptr) As Any Ptr
Declare Function sqlite3_backup_step CDecl Alias "sqlite3_backup_step" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_backup_finish CDecl Alias "sqlite3_backup_finish" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_backup_remaining CDecl Alias "sqlite3_backup_remaining" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_backup_pagecount CDecl Alias "sqlite3_backup_pagecount" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_unlock_notify CDecl Alias "sqlite3_unlock_notify" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_stricmp CDecl Alias "sqlite3_stricmp" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3_strnicmp CDecl Alias "sqlite3_strnicmp" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_strglob CDecl Alias "sqlite3_strglob" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3_strlike CDecl Alias "sqlite3_strlike" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_UINT) As SQLITE_C_INT
Declare Sub sqlite3_log CDecl Alias "sqlite3_log" (ByVal arg0 As SQLITE_C_INT, ByVal arg1 As Const ZString Ptr, ...)
Declare Function sqlite3_wal_hook CDecl Alias "sqlite3_wal_hook" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As Any Ptr
Declare Function sqlite3_wal_autocheckpoint CDecl Alias "sqlite3_wal_autocheckpoint" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_wal_checkpoint CDecl Alias "sqlite3_wal_checkpoint" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3_wal_checkpoint_v2 CDecl Alias "sqlite3_wal_checkpoint_v2" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT Ptr, ByVal arg4 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function sqlite3_vtab_config CDecl Alias "sqlite3_vtab_config" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ...) As SQLITE_C_INT
Declare Function sqlite3_vtab_on_conflict CDecl Alias "sqlite3_vtab_on_conflict" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_vtab_nochange CDecl Alias "sqlite3_vtab_nochange" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_vtab_collation CDecl Alias "sqlite3_vtab_collation" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3_vtab_distinct CDecl Alias "sqlite3_vtab_distinct" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_vtab_in CDecl Alias "sqlite3_vtab_in" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_vtab_rhs_value CDecl Alias "sqlite3_vtab_rhs_value" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_stmt_scanstatus CDecl Alias "sqlite3_stmt_scanstatus" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_stmt_scanstatus_v2 CDecl Alias "sqlite3_stmt_scanstatus_v2" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3_stmt_scanstatus_reset CDecl Alias "sqlite3_stmt_scanstatus_reset" (ByVal arg0 As Any Ptr)
Declare Function sqlite3_db_cacheflush CDecl Alias "sqlite3_db_cacheflush" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_preupdate_hook CDecl Alias "sqlite3_preupdate_hook" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As Any Ptr
Declare Function sqlite3_preupdate_old CDecl Alias "sqlite3_preupdate_old" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_preupdate_count CDecl Alias "sqlite3_preupdate_count" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_preupdate_depth CDecl Alias "sqlite3_preupdate_depth" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_preupdate_new CDecl Alias "sqlite3_preupdate_new" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_preupdate_blobwrite CDecl Alias "sqlite3_preupdate_blobwrite" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_system_errno CDecl Alias "sqlite3_system_errno" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_snapshot_get CDecl Alias "sqlite3_snapshot_get" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_snapshot_open CDecl Alias "sqlite3_snapshot_open" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3_snapshot_free CDecl Alias "sqlite3_snapshot_free" (ByVal arg0 As Any Ptr)
Declare Function sqlite3_snapshot_cmp CDecl Alias "sqlite3_snapshot_cmp" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_snapshot_recover CDecl Alias "sqlite3_snapshot_recover" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3_serialize CDecl Alias "sqlite3_serialize" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As sqlite3_int64 Ptr, ByVal arg3 As SQLITE_C_UINT) As UByte Ptr
Declare Function sqlite3_deserialize CDecl Alias "sqlite3_deserialize" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As UByte Ptr, ByVal arg3 As sqlite3_int64, ByVal arg4 As sqlite3_int64, ByVal arg5 As SQLITE_C_UINT) As SQLITE_C_INT
Declare Function sqlite3_carray_bind_v2 CDecl Alias "sqlite3_carray_bind_v2" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Any Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As Any Ptr, ByVal arg6 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_carray_bind CDecl Alias "sqlite3_carray_bind" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Any Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_wsd_init CDecl Alias "sqlite3_wsd_init" (ByVal arg0 As SQLITE_C_INT, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_wsd_find CDecl Alias "sqlite3_wsd_find" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Any Ptr
Declare Sub sqlite3SelectWalkAssert2 CDecl Alias "sqlite3SelectWalkAssert2" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3WindowDelete CDecl Alias "sqlite3WindowDelete" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3WindowUnlinkFromSelect CDecl Alias "sqlite3WindowUnlinkFromSelect" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3WindowListDelete CDecl Alias "sqlite3WindowListDelete" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3WindowAlloc CDecl Alias "sqlite3WindowAlloc" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As Any Ptr, ByVal arg6 As UByte) As Any Ptr
Declare Sub sqlite3WindowAttach CDecl Alias "sqlite3WindowAttach" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr)
Declare Sub sqlite3WindowLink CDecl Alias "sqlite3WindowLink" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3WindowCompare CDecl Alias "sqlite3WindowCompare" (ByVal arg0 As Const Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As Const Any Ptr, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub sqlite3WindowCodeInit CDecl Alias "sqlite3WindowCodeInit" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3WindowCodeStep CDecl Alias "sqlite3WindowCodeStep" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT)
Declare Function sqlite3WindowRewrite CDecl Alias "sqlite3WindowRewrite" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3WindowUpdate CDecl Alias "sqlite3WindowUpdate" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr)
Declare Function sqlite3WindowDup CDecl Alias "sqlite3WindowDup" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As Any Ptr
Declare Function sqlite3WindowListDup CDecl Alias "sqlite3WindowListDup" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As Any Ptr
Declare Sub sqlite3WindowFunctions CDecl Alias "sqlite3WindowFunctions" ()
Declare Sub sqlite3WindowChain CDecl Alias "sqlite3WindowChain" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr)
Declare Function sqlite3WindowAssemble CDecl Alias "sqlite3WindowAssemble" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr) As Any Ptr
Declare Function sqlite3ReportError CDecl Alias "sqlite3ReportError" (ByVal arg0 As SQLITE_C_INT, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3CorruptError CDecl Alias "sqlite3CorruptError" (ByVal arg0 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3MisuseError CDecl Alias "sqlite3MisuseError" (ByVal arg0 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3CantopenError CDecl Alias "sqlite3CantopenError" (ByVal arg0 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3NomemError CDecl Alias "sqlite3NomemError" (ByVal arg0 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3IoerrnomemError CDecl Alias "sqlite3IoerrnomemError" (ByVal arg0 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3CorruptPgnoError CDecl Alias "sqlite3CorruptPgnoError" (ByVal arg0 As SQLITE_C_INT, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3IsIdChar CDecl Alias "sqlite3IsIdChar" (ByVal arg0 As UByte) As SQLITE_C_INT
Declare Function sqlite3StrICmp CDecl Alias "sqlite3StrICmp" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" (ByVal arg0 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3ColumnType CDecl Alias "sqlite3ColumnType" (ByVal arg0 As Any Ptr, ByVal arg1 As ZString Ptr) As ZString Ptr
Declare Function sqlite3MallocInit CDecl Alias "sqlite3MallocInit" () As SQLITE_C_INT
Declare Sub sqlite3MallocEnd CDecl Alias "sqlite3MallocEnd" ()
Declare Function sqlite3Malloc CDecl Alias "sqlite3Malloc" (ByVal arg0 As sqlite3_uint64) As Any Ptr
Declare Function sqlite3MallocZero CDecl Alias "sqlite3MallocZero" (ByVal arg0 As sqlite3_uint64) As Any Ptr
Declare Function sqlite3Realloc CDecl Alias "sqlite3Realloc" (ByVal arg0 As Any Ptr, ByVal arg1 As sqlite3_uint64) As Any Ptr
Declare Function sqlite3MallocSize CDecl Alias "sqlite3MallocSize" (ByVal arg0 As Const Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3BenignMallocHooks CDecl Alias "sqlite3BenignMallocHooks" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3HeapNearlyFull CDecl Alias "sqlite3HeapNearlyFull" () As SQLITE_C_INT
Declare Function sqlite3DefaultMutex CDecl Alias "sqlite3DefaultMutex" () As Const Any Ptr
Declare Function sqlite3NoopMutex CDecl Alias "sqlite3NoopMutex" () As Const Any Ptr
Declare Function sqlite3LookasideUsed CDecl Alias "sqlite3LookasideUsed" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Sub sqlite3MutexWarnOnContention CDecl Alias "sqlite3MutexWarnOnContention" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3FpDecode CDecl Alias "sqlite3FpDecode" (ByVal arg0 As Any Ptr, ByVal arg1 As Double, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Declare Function sqlite3MPrintf CDecl Alias "sqlite3MPrintf" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ...) As ZString Ptr
Declare Function sqlite3VMPrintf CDecl Alias "sqlite3VMPrintf" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByRef arg2 As Cva_List) As ZString Ptr
Declare Sub sqlite3DebugPrintf CDecl Alias "sqlite3DebugPrintf" (ByVal arg0 As Const ZString Ptr, ...)
Declare Function sqlite3TestTextToPtr CDecl Alias "sqlite3TestTextToPtr" (ByVal arg0 As Const ZString Ptr) As Any Ptr
Declare Function sqlite3TestPtrToText CDecl Alias "sqlite3TestPtrToText" (ByVal arg0 As Any Ptr) As Const ZString Ptr
Declare Sub sqlite3TreeViewLine CDecl Alias "sqlite3TreeViewLine" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ...)
Declare Sub sqlite3TreeViewExpr CDecl Alias "sqlite3TreeViewExpr" (ByVal pView As SqliteTreeView Ptr, ByVal pExpr As Const SqliteExpr Ptr, ByVal moreToFollow As UByte)
Declare Sub sqlite3TreeViewBareExprList CDecl Alias "sqlite3TreeViewBareExprList" (ByVal pView As SqliteTreeView Ptr, ByVal pList As Const SqliteExprList Ptr, ByVal zLabel As Const ZString Ptr)
Declare Sub sqlite3TreeViewBareIdList CDecl Alias "sqlite3TreeViewBareIdList" (ByVal pViewArgument As Any Ptr, ByVal listArgument As Const Any Ptr, ByVal zLabel As Const ZString Ptr)
Declare Sub sqlite3TreeViewColumnList CDecl Alias "sqlite3TreeViewColumnList" (ByVal pViewArgument As Any Ptr, ByVal columnsArgument As Const Any Ptr, ByVal columnCount As SQLITE_C_INT, ByVal moreToFollow As UByte)
Declare Sub sqlite3TreeViewSrcList CDecl Alias "sqlite3TreeViewSrcList" (ByVal pView As SqliteTreeView Ptr, ByVal pSourceList As Const SqliteSrcList Ptr)
Declare Sub sqlite3TreeViewDelete CDecl Alias "sqlite3TreeViewDelete" (ByVal pWith As Const SqliteWithRecord Ptr, ByVal pTableList As Const SqliteSrcList Ptr, ByVal pWhere As Const SqliteExpr Ptr, ByVal pOrderBy As Const SqliteExprList Ptr, ByVal pLimit As Const SqliteExpr Ptr, ByVal pTrigger As Const SqliteTrigger Ptr)
Declare Sub sqlite3TreeViewInsert CDecl Alias "sqlite3TreeViewInsert" (ByVal pWith As Const SqliteWithRecord Ptr, ByVal pTableList As Const SqliteSrcList Ptr, ByVal pColumnList As Const SqliteIdList Ptr, ByVal pSelect As Const SqliteSelect Ptr, ByVal pValues As Const SqliteExprList Ptr, ByVal onError As SQLITE_C_INT, ByVal pUpsert As Const SqliteUpsert Ptr, ByVal pTrigger As Const SqliteTrigger Ptr)
Declare Sub sqlite3TreeViewUpdate CDecl Alias "sqlite3TreeViewUpdate" (ByVal pWith As Const SqliteWithRecord Ptr, ByVal pTableList As Const SqliteSrcList Ptr, ByVal pChanges As Const SqliteExprList Ptr, ByVal pWhere As Const SqliteExpr Ptr, ByVal onError As SQLITE_C_INT, ByVal pOrderBy As Const SqliteExprList Ptr, ByVal pLimit As Const SqliteExpr Ptr, ByVal pUpsert As Const SqliteUpsert Ptr, ByVal pTrigger As Const SqliteTrigger Ptr)
Declare Sub sqlite3ShowExpr CDecl Alias "sqlite3ShowExpr" (ByVal arg0 As Const Any Ptr)
Declare Sub sqlite3ShowExprList CDecl Alias "sqlite3ShowExprList" (ByVal arg0 As Const Any Ptr)
Declare Sub sqlite3ShowIdList CDecl Alias "sqlite3ShowIdList" (ByVal arg0 As Const Any Ptr)
Declare Sub sqlite3ShowSelect CDecl Alias "sqlite3ShowSelect" (ByVal arg0 As Const Any Ptr)
Declare Sub sqlite3ShowWith CDecl Alias "sqlite3ShowWith" (ByVal arg0 As Const Any Ptr)
Declare Sub sqlite3ShowUpsert CDecl Alias "sqlite3ShowUpsert" (ByVal arg0 As Const Any Ptr)
Declare Sub sqlite3ShowTriggerStep CDecl Alias "sqlite3ShowTriggerStep" (ByVal arg0 As Const Any Ptr)
Declare Sub sqlite3ShowTriggerStepList CDecl Alias "sqlite3ShowTriggerStepList" (ByVal arg0 As Const Any Ptr)
Declare Sub sqlite3ShowTrigger CDecl Alias "sqlite3ShowTrigger" (ByVal arg0 As Const Any Ptr)
Declare Sub sqlite3ShowTriggerList CDecl Alias "sqlite3ShowTriggerList" (ByVal arg0 As Const Any Ptr)
Declare Sub sqlite3ShowWindow CDecl Alias "sqlite3ShowWindow" (ByVal arg0 As Const Any Ptr)
Declare Sub sqlite3ShowWinFunc CDecl Alias "sqlite3ShowWinFunc" (ByVal arg0 As Const Any Ptr)
Declare Sub sqlite3ShowBitvec CDecl Alias "sqlite3ShowBitvec" (ByVal arg0 As Any Ptr)
Declare Function sqlite3ErrorToParser CDecl Alias "sqlite3ErrorToParser" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub sqlite3Dequote CDecl Alias "sqlite3Dequote" (ByVal arg0 As ZString Ptr)
Declare Sub sqlite3DequoteToken CDecl Alias "sqlite3DequoteToken" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3TokenInit CDecl Alias "sqlite3TokenInit" (ByVal arg0 As Any Ptr, ByVal arg1 As ZString Ptr)
Declare Function sqlite3KeywordCode CDecl Alias "sqlite3KeywordCode" (ByVal arg0 As Const UByte Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub sqlite3FinishCoding CDecl Alias "sqlite3FinishCoding" (ByVal arg0 As Any Ptr)
Declare Function sqlite3FirstAvailableRegister CDecl Alias "sqlite3FirstAvailableRegister" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3NoTempsInRange CDecl Alias "sqlite3NoTempsInRange" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3Expr CDecl Alias "sqlite3Expr" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr) As Any Ptr
Declare Sub sqlite3ExprAttachSubtrees CDecl Alias "sqlite3ExprAttachSubtrees" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr)
Declare Sub sqlite3PExprAddSelect CDecl Alias "sqlite3PExprAddSelect" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr)
Declare Function sqlite3ExprSimplifiedAndOr CDecl Alias "sqlite3ExprSimplifiedAndOr" (ByVal arg0 As Any Ptr) As Any Ptr
Declare Function sqlite3ExprFunction CDecl Alias "sqlite3ExprFunction" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Const Any Ptr, ByVal arg3 As SQLITE_C_INT) As Any Ptr
Declare Sub sqlite3ExprAddFunctionOrderBy CDecl Alias "sqlite3ExprAddFunctionOrderBy" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr)
Declare Sub sqlite3ExprOrderByAggregateError CDecl Alias "sqlite3ExprOrderByAggregateError" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3ExprFunctionUsable CDecl Alias "sqlite3ExprFunctionUsable" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As Const Any Ptr)
Declare Sub sqlite3ExprUnmapAndDelete CDecl Alias "sqlite3ExprUnmapAndDelete" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3ExprListAppendVector CDecl Alias "sqlite3ExprListAppendVector" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr) As Any Ptr
Declare Function sqlite3ExprListToValues CDecl Alias "sqlite3ExprListToValues" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Any Ptr) As Any Ptr
Declare Sub sqlite3ExprListSetSortOrder CDecl Alias "sqlite3ExprListSetSortOrder" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT)
Declare Sub sqlite3ExprListDeleteGeneric CDecl Alias "sqlite3ExprListDeleteGeneric" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3ExprCanReturnSubtype CDecl Alias "sqlite3ExprCanReturnSubtype" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3IndexHasDuplicateRootPage CDecl Alias "sqlite3IndexHasDuplicateRootPage" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3Init CDecl Alias "sqlite3Init" (ByVal arg0 As Any Ptr, ByVal arg1 As ZString Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3InitCallback CDecl Alias "sqlite3InitCallback" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As ZString Ptr Ptr, ByVal arg3 As ZString Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3InitOne CDecl Alias "sqlite3InitOne" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As ZString Ptr Ptr, ByVal arg3 As SQLITE_C_UINT) As SQLITE_C_INT
Declare Sub sqlite3Pragma CDecl Alias "sqlite3Pragma" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As SQLITE_C_INT)
Declare Function sqlite3PragmaVtabRegister CDecl Alias "sqlite3PragmaVtabRegister" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr) As Any Ptr
Declare Sub sqlite3ResetAllSchemasOfConnection CDecl Alias "sqlite3ResetAllSchemasOfConnection" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3ResetOneSchema CDecl Alias "sqlite3ResetOneSchema" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Sub sqlite3CollapseDatabaseArray CDecl Alias "sqlite3CollapseDatabaseArray" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3CommitInternalChanges CDecl Alias "sqlite3CommitInternalChanges" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3ColumnSetExpr CDecl Alias "sqlite3ColumnSetExpr" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr)
Declare Function sqlite3ColumnExpr CDecl Alias "sqlite3ColumnExpr" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As Any Ptr
Declare Function sqlite3ColumnExprAuth CDecl Alias "sqlite3ColumnExprAuth" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As Any Ptr
Declare Sub sqlite3ColumnSetColl CDecl Alias "sqlite3ColumnSetColl" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Const ZString Ptr)
Declare Function sqlite3ColumnColl CDecl Alias "sqlite3ColumnColl" (ByVal arg0 As Any Ptr) As Const ZString Ptr
Declare Sub sqlite3DeleteColumnNames CDecl Alias "sqlite3DeleteColumnNames" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3GenerateColumnNames CDecl Alias "sqlite3GenerateColumnNames" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3ColumnsFromExprList CDecl Alias "sqlite3ColumnsFromExprList" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Short Ptr, ByVal arg3 As Any Ptr Ptr) As SQLITE_C_INT
Declare Sub sqlite3SubqueryColumnTypes CDecl Alias "sqlite3SubqueryColumnTypes" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Byte)
Declare Function sqlite3ResultSetOfSelect CDecl Alias "sqlite3ResultSetOfSelect" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Byte) As Any Ptr
Declare Sub sqlite3OpenSchemaTable CDecl Alias "sqlite3OpenSchemaTable" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Function sqlite3PrimaryKeyIndex CDecl Alias "sqlite3PrimaryKeyIndex" (ByVal arg0 As Any Ptr) As Any Ptr
Declare Function sqlite3TableColumnToIndex CDecl Alias "sqlite3TableColumnToIndex" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3TableColumnToStorage CDecl Alias "sqlite3TableColumnToStorage" (ByVal arg0 As Any Ptr, ByVal arg1 As Short) As Short
Declare Function sqlite3StorageColumnToTable CDecl Alias "sqlite3StorageColumnToTable" (ByVal arg0 As Any Ptr, ByVal arg1 As Short) As Short
Declare Sub sqlite3StartTable CDecl Alias "sqlite3StartTable" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As SQLITE_C_INT)
Declare Sub sqlite3ColumnPropertiesFromName CDecl Alias "sqlite3ColumnPropertiesFromName" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3AddColumn CDecl Alias "sqlite3AddColumn" (ByVal arg0 As Any Ptr, ByVal arg1 As sqlite3ParserToken, ByVal arg2 As sqlite3ParserToken)
Declare Sub sqlite3AddNotNull CDecl Alias "sqlite3AddNotNull" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Sub sqlite3AddPrimaryKey CDecl Alias "sqlite3AddPrimaryKey" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT)
Declare Sub sqlite3AddCheckConstraint CDecl Alias "sqlite3AddCheckConstraint" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const ZString Ptr)
Declare Sub sqlite3AddDefaultValue CDecl Alias "sqlite3AddDefaultValue" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const ZString Ptr)
Declare Sub sqlite3AddCollateType CDecl Alias "sqlite3AddCollateType" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3AddGenerated CDecl Alias "sqlite3AddGenerated" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr)
Declare Sub sqlite3EndTable CDecl Alias "sqlite3EndTable" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As SQLITE_C_UINT, ByVal arg4 As Any Ptr)
Declare Sub sqlite3AddReturning CDecl Alias "sqlite3AddReturning" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3ParseUri CDecl Alias "sqlite3ParseUri" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_UINT Ptr, ByVal arg3 As Any Ptr Ptr, ByVal arg4 As ZString Ptr Ptr, ByVal arg5 As ZString Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3DbNameToBtree CDecl Alias "sqlite3DbNameToBtree" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr) As Any Ptr
Declare Function sqlite3BitvecBuiltinTest CDecl Alias "sqlite3BitvecBuiltinTest" (ByVal arg0 As SQLITE_C_INT, ByVal arg1 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Sub sqlite3CreateView CDecl Alias "sqlite3CreateView" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr, ByVal arg5 As Any Ptr, ByVal arg6 As SQLITE_C_INT, ByVal arg7 As SQLITE_C_INT)
Declare Function sqlite3ViewGetColumnNames CDecl Alias "sqlite3ViewGetColumnNames" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3DbMaskAllZero CDecl Alias "sqlite3DbMaskAllZero" (ByVal arg0 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub sqlite3DropTable CDecl Alias "sqlite3DropTable" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Declare Sub sqlite3CodeDropTable CDecl Alias "sqlite3CodeDropTable" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Declare Sub sqlite3DeleteTable CDecl Alias "sqlite3DeleteTable" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3DeleteTableGeneric CDecl Alias "sqlite3DeleteTableGeneric" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3FreeIndex CDecl Alias "sqlite3FreeIndex" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3AutoincrementBegin CDecl Alias "sqlite3AutoincrementBegin" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3AutoincrementEnd CDecl Alias "sqlite3AutoincrementEnd" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3Insert CDecl Alias "sqlite3Insert" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As Any Ptr)
Declare Sub sqlite3ComputeGeneratedColumns CDecl Alias "sqlite3ComputeGeneratedColumns" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Any Ptr)
Declare Function sqlite3ArrayAllocate CDecl Alias "sqlite3ArrayAllocate" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT Ptr, ByVal arg4 As SQLITE_C_INT Ptr) As Any Ptr
Declare Function sqlite3IdListAppend CDecl Alias "sqlite3IdListAppend" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As Any Ptr
Declare Function sqlite3IdListIndex CDecl Alias "sqlite3IdListIndex" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3SrcListEnlarge CDecl Alias "sqlite3SrcListEnlarge" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT) As Any Ptr
Declare Function sqlite3SrcListAppendList CDecl Alias "sqlite3SrcListAppendList" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As Any Ptr
Declare Function sqlite3SrcListAppend CDecl Alias "sqlite3SrcListAppend" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr) As Any Ptr
Declare Sub sqlite3SubqueryDelete CDecl Alias "sqlite3SubqueryDelete" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3SubqueryDetach CDecl Alias "sqlite3SubqueryDetach" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As Any Ptr
Declare Function sqlite3SrcItemAttachSubquery CDecl Alias "sqlite3SrcItemAttachSubquery" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3SrcListAppendFromTerm CDecl Alias "sqlite3SrcListAppendFromTerm" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr, ByVal arg5 As Any Ptr, ByVal arg6 As Any Ptr) As Any Ptr
Declare Sub sqlite3SrcListIndexedBy CDecl Alias "sqlite3SrcListIndexedBy" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr)
Declare Sub sqlite3SrcListFuncArgs CDecl Alias "sqlite3SrcListFuncArgs" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr)
Declare Function sqlite3IndexedByLookup CDecl Alias "sqlite3IndexedByLookup" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3SrcListShiftJoinType CDecl Alias "sqlite3SrcListShiftJoinType" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3SrcListAssignCursors CDecl Alias "sqlite3SrcListAssignCursors" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3IdListDelete CDecl Alias "sqlite3IdListDelete" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3ClearOnOrUsing CDecl Alias "sqlite3ClearOnOrUsing" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3SrcListDelete CDecl Alias "sqlite3SrcListDelete" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3AllocateIndexObject CDecl Alias "sqlite3AllocateIndexObject" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As ZString Ptr Ptr) As Any Ptr
Declare Function sqlite3IndexBloomable CDecl Alias "sqlite3IndexBloomable" (ByVal arg0 As Const Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub sqlite3CreateIndex CDecl Alias "sqlite3CreateIndex" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As Any Ptr, ByVal arg7 As Any Ptr, ByVal arg8 As SQLITE_C_INT, ByVal arg9 As SQLITE_C_INT, ByVal arg10 As UByte)
Declare Sub sqlite3DropIndex CDecl Alias "sqlite3DropIndex" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Sub sqlite3SelectDeleteGeneric CDecl Alias "sqlite3SelectDeleteGeneric" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3SelectCheckOnClauses CDecl Alias "sqlite3SelectCheckOnClauses" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3SrcListLookup CDecl Alias "sqlite3SrcListLookup" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As Any Ptr
Declare Function sqlite3IsReadOnly CDecl Alias "sqlite3IsReadOnly" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3OpenTable CDecl Alias "sqlite3OpenTable" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr, ByVal arg4 As SQLITE_C_INT)
Declare Function sqlite3LimitWhere CDecl Alias "sqlite3LimitWhere" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr, ByVal arg5 As ZString Ptr) As Any Ptr
Declare Sub sqlite3CodeChangeCount CDecl Alias "sqlite3CodeChangeCount" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr)
Declare Sub sqlite3DeleteFrom CDecl Alias "sqlite3DeleteFrom" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr)
Declare Sub sqlite3Update CDecl Alias "sqlite3Update" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As Any Ptr, ByVal arg6 As Any Ptr, ByVal arg7 As Any Ptr)
Declare Function sqlite3WhereBegin CDecl Alias "sqlite3WhereBegin" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr, ByVal arg5 As Any Ptr, ByVal arg6 As UShort, ByVal arg7 As SQLITE_C_INT) As Any Ptr
Declare Sub sqlite3WhereEnd CDecl Alias "sqlite3WhereEnd" (ByVal arg0 As Any Ptr)
Declare Function sqlite3WhereOutputRowCount CDecl Alias "sqlite3WhereOutputRowCount" (ByVal arg0 As Any Ptr) As Short
Declare Function sqlite3WhereIsDistinct CDecl Alias "sqlite3WhereIsDistinct" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3WhereIsOrdered CDecl Alias "sqlite3WhereIsOrdered" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3WhereOrderByLimitOptLabel CDecl Alias "sqlite3WhereOrderByLimitOptLabel" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3WhereMinMaxOptEarlyOut CDecl Alias "sqlite3WhereMinMaxOptEarlyOut" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3WhereIsSorted CDecl Alias "sqlite3WhereIsSorted" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3WhereContinueLabel CDecl Alias "sqlite3WhereContinueLabel" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3WhereBreakLabel CDecl Alias "sqlite3WhereBreakLabel" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3WhereOkOnePass CDecl Alias "sqlite3WhereOkOnePass" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function sqlite3WhereUsesDeferredSeek CDecl Alias "sqlite3WhereUsesDeferredSeek" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3ExprCodeLoadIndexColumn CDecl Alias "sqlite3ExprCodeLoadIndexColumn" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT)
Declare Function sqlite3ExprCodeGetColumn CDecl Alias "sqlite3ExprCodeGetColumn" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As UByte) As SQLITE_C_INT
Declare Sub sqlite3ExprCodeGetColumnOfTable CDecl Alias "sqlite3ExprCodeGetColumnOfTable" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT)
Declare Sub sqlite3ExprCodeMove CDecl Alias "sqlite3ExprCodeMove" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Declare Sub sqlite3ExprToRegister CDecl Alias "sqlite3ExprToRegister" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Sub sqlite3ExprCode CDecl Alias "sqlite3ExprCode" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Sub sqlite3ExprCodeGeneratedColumn CDecl Alias "sqlite3ExprCodeGeneratedColumn" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As SQLITE_C_INT)
Declare Sub sqlite3ExprCodeCopy CDecl Alias "sqlite3ExprCodeCopy" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Sub sqlite3ExprCodeFactorable CDecl Alias "sqlite3ExprCodeFactorable" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Function sqlite3ExprCodeRunJustOnce CDecl Alias "sqlite3ExprCodeRunJustOnce" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub sqlite3ExprNullRegisterRange CDecl Alias "sqlite3ExprNullRegisterRange" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT)
Declare Function sqlite3ExprCodeTemp CDecl Alias "sqlite3ExprCodeTemp" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function sqlite3ExprCodeTarget CDecl Alias "sqlite3ExprCodeTarget" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3ExprCodeExprList CDecl Alias "sqlite3ExprCodeExprList" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As UByte) As SQLITE_C_INT
Declare Sub sqlite3ExprIfTrue CDecl Alias "sqlite3ExprIfTrue" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Declare Sub sqlite3ExprIfFalse CDecl Alias "sqlite3ExprIfFalse" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Declare Sub sqlite3ExprIfFalseDup CDecl Alias "sqlite3ExprIfFalseDup" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Declare Function sqlite3FindTable CDecl Alias "sqlite3FindTable" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Const ZString Ptr) As Any Ptr
Declare Function sqlite3LocateTable CDecl Alias "sqlite3LocateTable" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const ZString Ptr) As Any Ptr
Declare Function sqlite3PreferredTableName CDecl Alias "sqlite3PreferredTableName" (ByVal arg0 As Const ZString Ptr) As Const ZString Ptr
Declare Function sqlite3LocateTableItem CDecl Alias "sqlite3LocateTableItem" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As Any Ptr) As Any Ptr
Declare Function sqlite3FindIndex CDecl Alias "sqlite3FindIndex" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Const ZString Ptr) As Any Ptr
Declare Sub sqlite3UnlinkAndDeleteTable CDecl Alias "sqlite3UnlinkAndDeleteTable" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr)
Declare Sub sqlite3UnlinkAndDeleteIndex CDecl Alias "sqlite3UnlinkAndDeleteIndex" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr)
Declare Sub sqlite3Vacuum CDecl Alias "sqlite3Vacuum" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr)
Declare Function sqlite3RunVacuum CDecl Alias "sqlite3RunVacuum" (ByVal arg0 As ZString Ptr Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3ExprImpliesExpr CDecl Alias "sqlite3ExprImpliesExpr" (ByVal arg0 As Const Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As Const Any Ptr, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3ExprImpliesNonNullRow CDecl Alias "sqlite3ExprImpliesNonNullRow" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub sqlite3AggInfoPersistWalkerInit CDecl Alias "sqlite3AggInfoPersistWalkerInit" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3ExprAnalyzeAggregates CDecl Alias "sqlite3ExprAnalyzeAggregates" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3ExprAnalyzeAggList CDecl Alias "sqlite3ExprAnalyzeAggList" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3ExprCoveredByIndex CDecl Alias "sqlite3ExprCoveredByIndex" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3ReferencesSrcList CDecl Alias "sqlite3ReferencesSrcList" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3PrngSaveState CDecl Alias "sqlite3PrngSaveState" ()
Declare Sub sqlite3PrngRestoreState CDecl Alias "sqlite3PrngRestoreState" ()
Declare Sub sqlite3RollbackAll CDecl Alias "sqlite3RollbackAll" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Sub sqlite3CodeVerifySchema CDecl Alias "sqlite3CodeVerifySchema" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Sub sqlite3CodeVerifyNamedSchema CDecl Alias "sqlite3CodeVerifyNamedSchema" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr)
Declare Sub sqlite3BeginTransaction CDecl Alias "sqlite3BeginTransaction" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Sub sqlite3EndTransaction CDecl Alias "sqlite3EndTransaction" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Sub sqlite3Savepoint CDecl Alias "sqlite3Savepoint" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Any Ptr)
Declare Sub sqlite3CloseSavepoints CDecl Alias "sqlite3CloseSavepoints" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3LeaveMutexAndCloseZombie CDecl Alias "sqlite3LeaveMutexAndCloseZombie" (ByVal arg0 As Any Ptr)
Declare Function sqlite3ExprContainsSubquery CDecl Alias "sqlite3ExprContainsSubquery" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3ExprIsLikeOperator CDecl Alias "sqlite3ExprIsLikeOperator" (ByVal arg0 As Const Any Ptr) As SQLITE_C_INT
Declare Function sqlite3RowidAlias CDecl Alias "sqlite3RowidAlias" (ByVal arg0 As Any Ptr) As Const ZString Ptr
Declare Sub sqlite3GenerateRowDelete CDecl Alias "sqlite3GenerateRowDelete" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As Short, ByVal arg7 As UByte, ByVal arg8 As UByte, ByVal arg9 As UByte, ByVal arg10 As SQLITE_C_INT)
Declare Sub sqlite3GenerateRowIndexDelete CDecl Alias "sqlite3GenerateRowIndexDelete" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT Ptr, ByVal arg5 As SQLITE_C_INT)
Declare Function sqlite3GenerateIndexKey CDecl Alias "sqlite3GenerateIndexKey" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SQLITE_C_INT Ptr, ByVal arg6 As Any Ptr, ByVal arg7 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub sqlite3ResolvePartIdxLabel CDecl Alias "sqlite3ResolvePartIdxLabel" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Function sqlite3ExprReferencesUpdatedColumn CDecl Alias "sqlite3ExprReferencesUpdatedColumn" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub sqlite3GenerateConstraintChecks CDecl Alias "sqlite3GenerateConstraintChecks" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As SQLITE_C_INT, ByVal arg7 As UByte, ByVal arg8 As UByte, ByVal arg9 As SQLITE_C_INT, ByVal arg10 As SQLITE_C_INT Ptr, ByVal arg11 As SQLITE_C_INT Ptr, ByVal arg12 As Any Ptr)
Declare Sub sqlite3SetMakeRecordP5 CDecl Alias "sqlite3SetMakeRecordP5" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3CompleteInsertion CDecl Alias "sqlite3CompleteInsertion" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SQLITE_C_INT Ptr, ByVal arg6 As SQLITE_C_INT, ByVal arg7 As SQLITE_C_INT, ByVal arg8 As SQLITE_C_INT)
Declare Function sqlite3OpenTableAndIndices CDecl Alias "sqlite3OpenTableAndIndices" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As UByte, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As UByte Ptr, ByVal arg6 As SQLITE_C_INT Ptr, ByVal arg7 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Sub sqlite3BeginWriteOperation CDecl Alias "sqlite3BeginWriteOperation" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT)
Declare Sub sqlite3MultiWrite CDecl Alias "sqlite3MultiWrite" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3HaltConstraint CDecl Alias "sqlite3HaltConstraint" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As ZString Ptr, ByVal arg4 As Byte, ByVal arg5 As UByte)
Declare Sub sqlite3UniqueConstraint CDecl Alias "sqlite3UniqueConstraint" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Any Ptr)
Declare Sub sqlite3RowidConstraint CDecl Alias "sqlite3RowidConstraint" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Any Ptr)
Declare Function sqlite3SrcListDup CDecl Alias "sqlite3SrcListDup" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_C_INT) As Any Ptr
Declare Function sqlite3IdListDup CDecl Alias "sqlite3IdListDup" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr) As Any Ptr
Declare Function sqlite3FunctionSearch CDecl Alias "sqlite3FunctionSearch" (ByVal arg0 As SQLITE_C_INT, ByVal arg1 As Const ZString Ptr) As Any Ptr
Declare Sub sqlite3InsertBuiltinFuncs CDecl Alias "sqlite3InsertBuiltinFuncs" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Sub sqlite3QuoteValue CDecl Alias "sqlite3QuoteValue" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Function sqlite3AppendOneUtf8Character CDecl Alias "sqlite3AppendOneUtf8Character" (ByVal arg0 As ZString Ptr, ByVal arg1 As SQLITE_C_UINT) As SQLITE_C_INT
Declare Sub sqlite3RegisterBuiltinFunctions CDecl Alias "sqlite3RegisterBuiltinFunctions" ()
Declare Sub sqlite3RegisterDateTimeFunctions CDecl Alias "sqlite3RegisterDateTimeFunctions" ()
Declare Sub sqlite3RegisterJsonFunctions CDecl Alias "sqlite3RegisterJsonFunctions" ()
Declare Sub sqlite3RegisterPerConnectionBuiltinFunctions CDecl Alias "sqlite3RegisterPerConnectionBuiltinFunctions" (ByVal arg0 As Any Ptr)
Declare Function sqlite3JsonVtabRegister CDecl Alias "sqlite3JsonVtabRegister" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr) As Any Ptr
Declare Function sqlite3SafetyCheckOk CDecl Alias "sqlite3SafetyCheckOk" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3SafetyCheckSickOrOk CDecl Alias "sqlite3SafetyCheckSickOrOk" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3ChangeCookie CDecl Alias "sqlite3ChangeCookie" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Function sqlite3CarrayRegister CDecl Alias "sqlite3CarrayRegister" (ByVal arg0 As Any Ptr) As Any Ptr
Declare Sub sqlite3MaterializeView CDecl Alias "sqlite3MaterializeView" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr, ByVal arg5 As SQLITE_C_INT)
Declare Sub sqlite3BeginTrigger CDecl Alias "sqlite3BeginTrigger" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As Any Ptr, ByVal arg6 As Any Ptr, ByVal arg7 As Any Ptr, ByVal arg8 As SQLITE_C_INT, ByVal arg9 As SQLITE_C_INT)
Declare Sub sqlite3FinishTrigger CDecl Alias "sqlite3FinishTrigger" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr)
Declare Sub sqlite3DropTrigger CDecl Alias "sqlite3DropTrigger" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Sub sqlite3DropTriggerPtr CDecl Alias "sqlite3DropTriggerPtr" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3TriggersExist CDecl Alias "sqlite3TriggersExist" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr, ByVal arg4 As SQLITE_C_INT Ptr) As Any Ptr
Declare Function sqlite3TriggerList CDecl Alias "sqlite3TriggerList" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As Any Ptr
Declare Sub sqlite3CodeRowTrigger CDecl Alias "sqlite3CodeRowTrigger" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As Any Ptr, ByVal arg6 As SQLITE_C_INT, ByVal arg7 As SQLITE_C_INT, ByVal arg8 As SQLITE_C_INT)
Declare Sub sqlite3CodeRowTriggerDirect CDecl Alias "sqlite3CodeRowTriggerDirect" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SQLITE_C_INT)
Declare Sub sqlite3DeleteTriggerStep CDecl Alias "sqlite3DeleteTriggerStep" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3TriggerSelectStep CDecl Alias "sqlite3TriggerSelectStep" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const ZString Ptr) As Any Ptr
Declare Function sqlite3TriggerInsertStep CDecl Alias "sqlite3TriggerInsertStep" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As UByte, ByVal arg5 As Any Ptr, ByVal arg6 As Const ZString Ptr, ByVal arg7 As Const ZString Ptr) As Any Ptr
Declare Function sqlite3TriggerUpdateStep CDecl Alias "sqlite3TriggerUpdateStep" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr, ByVal arg5 As UByte, ByVal arg6 As Const ZString Ptr, ByVal arg7 As Const ZString Ptr) As Any Ptr
Declare Function sqlite3TriggerDeleteStep CDecl Alias "sqlite3TriggerDeleteStep" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Const ZString Ptr, ByVal arg4 As Const ZString Ptr) As Any Ptr
Declare Sub sqlite3DeleteTrigger CDecl Alias "sqlite3DeleteTrigger" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3UnlinkAndDeleteTrigger CDecl Alias "sqlite3UnlinkAndDeleteTrigger" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr)
Declare Function sqlite3TriggerColmask CDecl Alias "sqlite3TriggerColmask" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As Any Ptr, ByVal arg6 As SQLITE_C_INT) As SQLITE_C_UINT
Declare Function sqlite3JoinType CDecl Alias "sqlite3JoinType" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3ColumnIndex CDecl Alias "sqlite3ColumnIndex" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT
Declare Sub sqlite3SrcItemColumnUsed CDecl Alias "sqlite3SrcItemColumnUsed" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Sub sqlite3SetJoinExpr CDecl Alias "sqlite3SetJoinExpr" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_UINT)
Declare Sub sqlite3CreateForeignKey CDecl Alias "sqlite3CreateForeignKey" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As SQLITE_C_INT)
Declare Sub sqlite3DeferForeignKey CDecl Alias "sqlite3DeferForeignKey" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Sub sqlite3AuthRead CDecl Alias "sqlite3AuthRead" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr)
Declare Function sqlite3AuthCheck CDecl Alias "sqlite3AuthCheck" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const ZString Ptr, ByVal arg4 As Const ZString Ptr) As SQLITE_C_INT
Declare Sub sqlite3AuthContextPush CDecl Alias "sqlite3AuthContextPush" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Const ZString Ptr)
Declare Sub sqlite3AuthContextPop CDecl Alias "sqlite3AuthContextPop" (ByVal arg0 As Any Ptr)
Declare Function sqlite3AuthReadCol CDecl Alias "sqlite3AuthReadCol" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3DbIsNamed CDecl Alias "sqlite3DbIsNamed" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr) As SQLITE_C_INT
Declare Sub sqlite3Attach CDecl Alias "sqlite3Attach" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr)
Declare Sub sqlite3Detach CDecl Alias "sqlite3Detach" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3FixInit CDecl Alias "sqlite3FixInit" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Const ZString Ptr, ByVal arg4 As Const Any Ptr)
Declare Function sqlite3FixSrcList CDecl Alias "sqlite3FixSrcList" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3FixSelect CDecl Alias "sqlite3FixSelect" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3FixExpr CDecl Alias "sqlite3FixExpr" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3FixTriggerStep CDecl Alias "sqlite3FixTriggerStep" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3Utf16ByteLen CDecl Alias "sqlite3Utf16ByteLen" (ByVal arg0 As Const Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3Utf8CharLen CDecl Alias "sqlite3Utf8CharLen" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3Utf8Read CDecl Alias "sqlite3Utf8Read" (ByVal arg0 As Const UByte Ptr Ptr) As SQLITE_C_UINT
Declare Function sqlite3Utf8ReadLimited CDecl Alias "sqlite3Utf8ReadLimited" (ByVal arg0 As Const UByte Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_UINT Ptr) As SQLITE_C_INT
Declare Function sqlite3IndexAffinityStr CDecl Alias "sqlite3IndexAffinityStr" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As Const ZString Ptr
Declare Function sqlite3TableAffinityStr CDecl Alias "sqlite3TableAffinityStr" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr) As ZString Ptr
Declare Sub sqlite3TableAffinity CDecl Alias "sqlite3TableAffinity" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Function sqlite3CompareAffinity CDecl Alias "sqlite3CompareAffinity" (ByVal arg0 As Const Any Ptr, ByVal arg1 As Byte) As Byte
Declare Function sqlite3IndexAffinityOk CDecl Alias "sqlite3IndexAffinityOk" (ByVal arg0 As Const Any Ptr, ByVal arg1 As Byte) As SQLITE_C_INT
Declare Function sqlite3TableColumnAffinity CDecl Alias "sqlite3TableColumnAffinity" (ByVal arg0 As Const Any Ptr, ByVal arg1 As SQLITE_C_INT) As Byte
Declare Function sqlite3ExprAffinity CDecl Alias "sqlite3ExprAffinity" (ByVal arg0 As Const Any Ptr) As Byte
Declare Function sqlite3ExprDataType CDecl Alias "sqlite3ExprDataType" (ByVal arg0 As Const Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3SystemError CDecl Alias "sqlite3SystemError" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Function sqlite3TwoPartName CDecl Alias "sqlite3TwoPartName" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3ErrName CDecl Alias "sqlite3ErrName" (ByVal arg0 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3ErrStr CDecl Alias "sqlite3ErrStr" (ByVal arg0 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3ReadSchema CDecl Alias "sqlite3ReadSchema" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3FindCollSeq CDecl Alias "sqlite3FindCollSeq" (ByVal arg0 As Any Ptr, ByVal arg1 As UByte, ByVal arg2 As Const ZString Ptr, ByVal arg3 As SQLITE_C_INT) As Any Ptr
Declare Function sqlite3LocateCollSeq CDecl Alias "sqlite3LocateCollSeq" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr) As Any Ptr
Declare Sub sqlite3SetTextEncoding CDecl Alias "sqlite3SetTextEncoding" (ByVal arg0 As Any Ptr, ByVal arg1 As UByte)
Declare Function sqlite3WritableSchema CDecl Alias "sqlite3WritableSchema" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3CheckObjectName CDecl Alias "sqlite3CheckObjectName" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const ZString Ptr) As SQLITE_C_INT
Declare Sub sqlite3VdbeSetChanges CDecl Alias "sqlite3VdbeSetChanges" (ByVal arg0 As Any Ptr, ByVal arg1 As sqlite3_int64)
Declare Sub sqlite3FileSuffix3 CDecl Alias "sqlite3FileSuffix3" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As ZString Ptr)
Declare Function sqlite3GetBoolean CDecl Alias "sqlite3GetBoolean" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As UByte) As UByte
Declare Sub sqlite3ResultIntReal CDecl Alias "sqlite3ResultIntReal" (ByVal arg0 As Any Ptr)
Declare Function sqlite3Utf16to8 CDecl Alias "sqlite3Utf16to8" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As UByte) As ZString Ptr
Declare Function sqlite3ValueFromExpr CDecl Alias "sqlite3ValueFromExpr" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As UByte, ByVal arg3 As UByte, ByVal arg4 As Any Ptr Ptr) As SQLITE_C_INT
Declare Sub sqlite3RootPageMoved CDecl Alias "sqlite3RootPageMoved" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Declare Sub sqlite3Reindex CDecl Alias "sqlite3Reindex" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr)
Declare Sub sqlite3AlterFunctions CDecl Alias "sqlite3AlterFunctions" ()
Declare Sub sqlite3AlterRenameTable CDecl Alias "sqlite3AlterRenameTable" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr)
Declare Sub sqlite3AlterRenameColumn CDecl Alias "sqlite3AlterRenameColumn" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr)
Declare Sub sqlite3AlterDropConstraint CDecl Alias "sqlite3AlterDropConstraint" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr)
Declare Sub sqlite3AlterAddConstraint CDecl Alias "sqlite3AlterAddConstraint" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As Const ZString Ptr, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As Any Ptr)
Declare Sub sqlite3AlterSetNotNull CDecl Alias "sqlite3AlterSetNotNull" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr)
Declare Function sqlite3GetToken CDecl Alias "sqlite3GetToken" (ByVal arg0 As Const UByte Ptr, ByVal arg1 As SQLITE_C_INT Ptr) As sqlite3_int64
Declare Sub sqlite3NestedParse CDecl Alias "sqlite3NestedParse" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ...)
Declare Sub sqlite3CodeRhsOfIN CDecl Alias "sqlite3CodeRhsOfIN" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Declare Function sqlite3CodeSubselect CDecl Alias "sqlite3CodeSubselect" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3SelectPrep CDecl Alias "sqlite3SelectPrep" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr)
Declare Function sqlite3ExpandSubquery CDecl Alias "sqlite3ExpandSubquery" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3SelectWrongNumTermsError CDecl Alias "sqlite3SelectWrongNumTermsError" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3MatchEName CDecl Alias "sqlite3MatchEName" (ByVal arg0 As Const Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const ZString Ptr, ByVal arg4 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function sqlite3ExprColUsed CDecl Alias "sqlite3ExprColUsed" (ByVal arg0 As Any Ptr) As sqlite3_uint64
Declare Function sqlite3StrIHash CDecl Alias "sqlite3StrIHash" (ByVal arg0 As Const ZString Ptr) As UByte
Declare Function sqlite3ResolveExprNames CDecl Alias "sqlite3ResolveExprNames" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3ResolveExprListNames CDecl Alias "sqlite3ResolveExprListNames" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3ResolveSelectNames CDecl Alias "sqlite3ResolveSelectNames" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr)
Declare Function sqlite3ResolveSelfReference CDecl Alias "sqlite3ResolveSelfReference" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3ResolveOrderGroupBy CDecl Alias "sqlite3ResolveOrderGroupBy" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Const ZString Ptr) As SQLITE_C_INT
Declare Sub sqlite3ColumnDefault CDecl Alias "sqlite3ColumnDefault" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Declare Sub sqlite3AlterFinishAddColumn CDecl Alias "sqlite3AlterFinishAddColumn" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3AlterBeginAddColumn CDecl Alias "sqlite3AlterBeginAddColumn" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3AlterDropColumn CDecl Alias "sqlite3AlterDropColumn" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Const Any Ptr)
Declare Function sqlite3RenameTokenMap CDecl Alias "sqlite3RenameTokenMap" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As Const Any Ptr) As Const Any Ptr
Declare Sub sqlite3RenameTokenRemap CDecl Alias "sqlite3RenameTokenRemap" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As Const Any Ptr)
Declare Sub sqlite3RenameExprUnmap CDecl Alias "sqlite3RenameExprUnmap" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3RenameExprlistUnmap CDecl Alias "sqlite3RenameExprlistUnmap" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3Analyze CDecl Alias "sqlite3Analyze" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr)
Declare Function sqlite3FindDb CDecl Alias "sqlite3FindDb" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3FindDbName CDecl Alias "sqlite3FindDbName" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3AnalysisLoad CDecl Alias "sqlite3AnalysisLoad" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub sqlite3DeleteIndexSamples CDecl Alias "sqlite3DeleteIndexSamples" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3DefaultRowEst CDecl Alias "sqlite3DefaultRowEst" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3RegisterLikeFunctions CDecl Alias "sqlite3RegisterLikeFunctions" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Function sqlite3IsLikeFunction CDecl Alias "sqlite3IsLikeFunction" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT Ptr, ByVal arg3 As ZString Ptr) As SQLITE_C_INT
Declare Sub sqlite3SchemaClear CDecl Alias "sqlite3SchemaClear" (ByVal arg0 As Any Ptr)
Declare Function sqlite3SchemaGet CDecl Alias "sqlite3SchemaGet" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As Any Ptr
Declare Function sqlite3SchemaToIndex CDecl Alias "sqlite3SchemaToIndex" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3KeyInfoAlloc CDecl Alias "sqlite3KeyInfoAlloc" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As Any Ptr
Declare Function sqlite3KeyInfoOfIndex CDecl Alias "sqlite3KeyInfoOfIndex" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As Any Ptr
Declare Function sqlite3KeyInfoFromExprList CDecl Alias "sqlite3KeyInfoFromExprList" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT) As Any Ptr
Declare Function sqlite3HasExplicitNulls CDecl Alias "sqlite3HasExplicitNulls" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3KeyInfoIsWriteable CDecl Alias "sqlite3KeyInfoIsWriteable" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3CreateFunc CDecl Alias "sqlite3CreateFunc" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As Any Ptr, ByVal arg5 As Any Ptr, ByVal arg6 As Any Ptr, ByVal arg7 As Any Ptr, ByVal arg8 As Any Ptr, ByVal arg9 As Any Ptr, ByVal arg10 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3OpenTempDatabase CDecl Alias "sqlite3OpenTempDatabase" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3RCStrRef CDecl Alias "sqlite3RCStrRef" (ByVal arg0 As ZString Ptr) As ZString Ptr
Declare Sub sqlite3RCStrUnref CDecl Alias "sqlite3RCStrUnref" (ByVal arg0 As Any Ptr)
Declare Function sqlite3RCStrNew CDecl Alias "sqlite3RCStrNew" (ByVal arg0 As sqlite3_uint64) As ZString Ptr
Declare Function sqlite3RCStrResize CDecl Alias "sqlite3RCStrResize" (ByVal arg0 As ZString Ptr, ByVal arg1 As sqlite3_uint64) As ZString Ptr
Declare Sub sqlite3SelectDestInit CDecl Alias "sqlite3SelectDestInit" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT)
Declare Function sqlite3CreateColumnExpr CDecl Alias "sqlite3CreateColumnExpr" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT) As Any Ptr
Declare Sub sqlite3RecordErrorByteOffset CDecl Alias "sqlite3RecordErrorByteOffset" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr)
Declare Sub sqlite3RecordErrorOffsetOfExpr CDecl Alias "sqlite3RecordErrorOffsetOfExpr" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr)
Declare Sub sqlite3BackupRestart CDecl Alias "sqlite3BackupRestart" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3BackupUpdate CDecl Alias "sqlite3BackupUpdate" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const UByte Ptr)
Declare Function sqlite3ExprCheckIN CDecl Alias "sqlite3ExprCheckIN" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3Stat4ProbeSetValue CDecl Alias "sqlite3Stat4ProbeSetValue" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function sqlite3Stat4ValueFromExpr CDecl Alias "sqlite3Stat4ValueFromExpr" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As UByte, ByVal arg3 As Any Ptr Ptr) As SQLITE_C_INT
Declare Sub sqlite3Stat4ProbeFree CDecl Alias "sqlite3Stat4ProbeFree" (ByVal arg0 As Any Ptr)
Declare Function sqlite3Stat4Column CDecl Alias "sqlite3Stat4Column" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3IndexColumnAffinity CDecl Alias "sqlite3IndexColumnAffinity" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT) As Byte
Declare Function sqlite3ParserAlloc CDecl Alias "sqlite3ParserAlloc" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As Any Ptr
Declare Sub sqlite3ParserFree CDecl Alias "sqlite3ParserFree" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3ParserFallback CDecl Alias "sqlite3ParserFallback" (ByVal arg0 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3ParserStackPeak CDecl Alias "sqlite3ParserStackPeak" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3AutoLoadExtensions CDecl Alias "sqlite3AutoLoadExtensions" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3CloseExtensions CDecl Alias "sqlite3CloseExtensions" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3TableLock CDecl Alias "sqlite3TableLock" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As UByte, ByVal arg4 As Const ZString Ptr)
Declare Function sqlite3Utf8To8 CDecl Alias "sqlite3Utf8To8" (ByVal arg0 As UByte Ptr) As SQLITE_C_INT
Declare Sub sqlite3VtabClear CDecl Alias "sqlite3VtabClear" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3VtabDisconnect CDecl Alias "sqlite3VtabDisconnect" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3VtabSync CDecl Alias "sqlite3VtabSync" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3VtabRollback CDecl Alias "sqlite3VtabRollback" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3VtabCommit CDecl Alias "sqlite3VtabCommit" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3VtabLock CDecl Alias "sqlite3VtabLock" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3VtabUnlock CDecl Alias "sqlite3VtabUnlock" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3VtabModuleUnref CDecl Alias "sqlite3VtabModuleUnref" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3VtabUnlockList CDecl Alias "sqlite3VtabUnlockList" (ByVal arg0 As Any Ptr)
Declare Function sqlite3VtabSavepoint CDecl Alias "sqlite3VtabSavepoint" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub sqlite3VtabImportErrmsg CDecl Alias "sqlite3VtabImportErrmsg" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3GetVTable CDecl Alias "sqlite3GetVTable" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As Any Ptr
Declare Function sqlite3VtabCreateModule CDecl Alias "sqlite3VtabCreateModule" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Const Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr) As Any Ptr
Declare Function sqlite3ReadOnlyShadowTables CDecl Alias "sqlite3ReadOnlyShadowTables" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3ShadowTableName CDecl Alias "sqlite3ShadowTableName" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3IsShadowTableOf CDecl Alias "sqlite3IsShadowTableOf" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Const ZString Ptr) As SQLITE_C_INT
Declare Sub sqlite3MarkAllShadowTablesOf CDecl Alias "sqlite3MarkAllShadowTablesOf" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3VtabEponymousTableClearAll CDecl Alias "sqlite3VtabEponymousTableClearAll" (ByVal arg0 As Any Ptr)
Declare Function sqlite3VtabEponymousTableInit CDecl Alias "sqlite3VtabEponymousTableInit" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3VtabEponymousTableClear CDecl Alias "sqlite3VtabEponymousTableClear" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3VtabMakeWritable CDecl Alias "sqlite3VtabMakeWritable" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3VtabBeginParse CDecl Alias "sqlite3VtabBeginParse" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As SQLITE_C_INT)
Declare Sub sqlite3VtabFinishParse CDecl Alias "sqlite3VtabFinishParse" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3VtabArgInit CDecl Alias "sqlite3VtabArgInit" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3VtabArgExtend CDecl Alias "sqlite3VtabArgExtend" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3VtabCallCreate CDecl Alias "sqlite3VtabCallCreate" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr, ByVal arg3 As ZString Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3VtabCallConnect CDecl Alias "sqlite3VtabCallConnect" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3VtabCallDestroy CDecl Alias "sqlite3VtabCallDestroy" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3VtabBegin CDecl Alias "sqlite3VtabBegin" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3VtabOverloadFunction CDecl Alias "sqlite3VtabOverloadFunction" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr) As Any Ptr
Declare Sub sqlite3VtabUsesAllSchemas CDecl Alias "sqlite3VtabUsesAllSchemas" (ByVal arg0 As Any Ptr)
Declare Function sqlite3StmtCurrentTime CDecl Alias "sqlite3StmtCurrentTime" (ByVal arg0 As Any Ptr) As sqlite3_int64
Declare Function sqlite3TransferBindings CDecl Alias "sqlite3TransferBindings" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3ParseObjectInit CDecl Alias "sqlite3ParseObjectInit" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3ParseObjectReset CDecl Alias "sqlite3ParseObjectReset" (ByVal arg0 As Any Ptr)
Declare Function sqlite3Normalize CDecl Alias "sqlite3Normalize" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr) As ZString Ptr
Declare Function sqlite3Reprepare CDecl Alias "sqlite3Reprepare" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3ExprListCheckLength CDecl Alias "sqlite3ExprListCheckLength" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Const ZString Ptr)
Declare Function sqlite3TempInMemory CDecl Alias "sqlite3TempInMemory" (ByVal arg0 As Const Any Ptr) As SQLITE_C_INT
Declare Function sqlite3JournalModename CDecl Alias "sqlite3JournalModename" (ByVal arg0 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3Checkpoint CDecl Alias "sqlite3Checkpoint" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT Ptr, ByVal arg4 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function sqlite3WalDefaultHook CDecl Alias "sqlite3WalDefaultHook" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3UpsertNew CDecl Alias "sqlite3UpsertNew" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr, ByVal arg5 As Any Ptr) As Any Ptr
Declare Sub sqlite3UpsertDelete CDecl Alias "sqlite3UpsertDelete" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3UpsertDup CDecl Alias "sqlite3UpsertDup" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As Any Ptr
Declare Function sqlite3UpsertAnalyzeTarget CDecl Alias "sqlite3UpsertAnalyzeTarget" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3UpsertDoUpdate CDecl Alias "sqlite3UpsertDoUpdate" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As SQLITE_C_INT)
Declare Function sqlite3UpsertOfIndex CDecl Alias "sqlite3UpsertOfIndex" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As Any Ptr
Declare Function sqlite3UpsertNextIsIPK CDecl Alias "sqlite3UpsertNextIsIPK" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3FkCheck CDecl Alias "sqlite3FkCheck" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT Ptr, ByVal arg5 As SQLITE_C_INT)
Declare Sub sqlite3FkDropTable CDecl Alias "sqlite3FkDropTable" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr)
Declare Sub sqlite3FkActions CDecl Alias "sqlite3FkActions" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT Ptr, ByVal arg5 As SQLITE_C_INT)
Declare Function sqlite3FkRequired CDecl Alias "sqlite3FkRequired" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT Ptr, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3FkOldmask CDecl Alias "sqlite3FkOldmask" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_UINT
Declare Function sqlite3FkReferences CDecl Alias "sqlite3FkReferences" (ByVal arg0 As Any Ptr) As Any Ptr
Declare Sub sqlite3FkClearTriggerCache CDecl Alias "sqlite3FkClearTriggerCache" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Sub sqlite3FkDelete CDecl Alias "sqlite3FkDelete" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3FkLocateIndex CDecl Alias "sqlite3FkLocateIndex" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr Ptr, ByVal arg4 As SQLITE_C_INT Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3FindInIndex CDecl Alias "sqlite3FindInIndex" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_UINT, ByVal arg3 As SQLITE_C_INT Ptr, ByVal arg4 As SQLITE_C_INT Ptr, ByVal arg5 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Sub sqlite3ConnectionBlocked CDecl Alias "sqlite3ConnectionBlocked" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3ConnectionUnlocked CDecl Alias "sqlite3ConnectionUnlocked" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3ConnectionClosed CDecl Alias "sqlite3ConnectionClosed" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3ParserTrace CDecl Alias "sqlite3ParserTrace" (ByVal arg0 As Any Ptr, ByVal arg1 As ZString Ptr)
Declare Function sqlite3ParserCoverage CDecl Alias "sqlite3ParserCoverage" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3VdbeIOTraceSql CDecl Alias "sqlite3VdbeIOTraceSql" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3MemdebugSetType CDecl Alias "sqlite3MemdebugSetType" (ByVal arg0 As Any Ptr, ByVal arg1 As UByte)
Declare Function sqlite3MemdebugHasType CDecl Alias "sqlite3MemdebugHasType" (ByVal arg0 As Const Any Ptr, ByVal arg1 As UByte) As SQLITE_C_INT
Declare Function sqlite3MemdebugNoType CDecl Alias "sqlite3MemdebugNoType" (ByVal arg0 As Const Any Ptr, ByVal arg1 As UByte) As SQLITE_C_INT
Declare Function sqlite3ThreadCreate CDecl Alias "sqlite3ThreadCreate" (ByVal arg0 As Any Ptr Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3ThreadJoin CDecl Alias "sqlite3ThreadJoin" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3DbpageRegister CDecl Alias "sqlite3DbpageRegister" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3DbstatRegister CDecl Alias "sqlite3DbstatRegister" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3VectorErrorMsg CDecl Alias "sqlite3VectorErrorMsg" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3CompileOptions CDecl Alias "sqlite3CompileOptions" (ByVal arg0 As SQLITE_C_INT Ptr) As Const ZString Ptr Ptr
Declare Function sqlite3KvvfsInit CDecl Alias "sqlite3KvvfsInit" () As SQLITE_C_INT
Declare Function sqlite3Hwtime CDecl Alias "sqlite3Hwtime" () As sqlite3_uint64

Declare Sub sqlite3TreeViewPop CDecl Alias "sqlite3TreeViewPop" (ByVal arg0 As SqliteTreeView Ptr Ptr)
Declare Sub sqlite3TreeViewItem CDecl Alias "sqlite3TreeViewItem" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As UByte)
Declare Sub sqlite3TreeViewWith CDecl Alias "sqlite3TreeViewWith" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteWithRecord Ptr, ByVal arg2 As UByte)
Declare Sub sqlite3TreeViewSelect CDecl Alias "sqlite3TreeViewSelect" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteSelect Ptr, ByVal arg2 As UByte)
Declare Sub sqlite3TreeViewBound CDecl Alias "sqlite3TreeViewBound" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As UByte, ByVal arg2 As SqliteExpr Ptr, ByVal arg3 As UByte)
Declare Sub sqlite3TreeViewWindow CDecl Alias "sqlite3TreeViewWindow" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteWalkerWindow Ptr, ByVal arg2 As UByte)
Declare Sub sqlite3TreeViewWinFunc CDecl Alias "sqlite3TreeViewWinFunc" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteWalkerWindow Ptr, ByVal arg2 As UByte)
Declare Sub sqlite3TreeViewExprList CDecl Alias "sqlite3TreeViewExprList" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteExprList Ptr, ByVal arg2 As UByte, ByVal arg3 As Const ZString Ptr)
Declare Sub sqlite3TreeViewIdList CDecl Alias "sqlite3TreeViewIdList" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteIdList Ptr, ByVal arg2 As UByte, ByVal arg3 As Const ZString Ptr)
Declare Sub sqlite3TreeViewUpsert CDecl Alias "sqlite3TreeViewUpsert" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteUpsert Ptr, ByVal arg2 As UByte)
Declare Sub sqlite3TreeViewTriggerStep CDecl Alias "sqlite3TreeViewTriggerStep" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteTriggerStep Ptr, ByVal arg2 As UByte, ByVal arg3 As UByte)
Declare Sub sqlite3TreeViewTrigger CDecl Alias "sqlite3TreeViewTrigger" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteTrigger Ptr, ByVal arg2 As UByte, ByVal arg3 As UByte)
Declare Sub sqlite3ShowSrcList CDecl Alias "sqlite3ShowSrcList" (ByVal arg0 As Const SqliteSrcList Ptr)
' c2fb skipped __bswap_16: outside the supported subset
' c2fb skipped __bswap_32: outside the supported subset
' c2fb skipped __bswap_64: outside the supported subset
' c2fb skipped __uint16_identity: outside the supported subset
' c2fb skipped __uint32_identity: outside the supported subset
' c2fb skipped __uint64_identity: outside the supported subset
' c2fb skipped sqlite3IsBinary: FreeBASIC body already exists
Private Sub sqlite3TreeViewPush CDecl Alias "sqlite3TreeViewPush" ( _
    ByVal ppView As SqliteTreeView Ptr Ptr, _
    ByVal moreToFollow As UByte _
)
    If ppView = 0 Then Exit Sub
    If moreToFollow <> 0 Then moreToFollow = 1
    Dim pView As SqliteTreeView Ptr = ppView[0]
    If pView = 0 Then
        pView = CPtr(SqliteTreeView Ptr, sqlite3_malloc64(SizeOf(SqliteTreeView)))
        If pView = 0 Then Exit Sub
        ppView[0] = pView
        pView->iLevel = 0
        For iLine As Long = 0 To UBound(pView->bLine)
            pView->bLine(iLine) = 0
        Next
    Else
        pView->iLevel += 1
    End If
    If pView->iLevel >= 0 AndAlso pView->iLevel <= UBound(pView->bLine) Then _
        pView->bLine(pView->iLevel) = moreToFollow
End Sub

Sub sqlite3TreeViewLine CDecl Alias "sqlite3TreeViewLine" ( _
    ByVal pViewArgument As Any Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
    Dim buffer(0 To 999) As UByte
    Dim accumulator As sqlite3_str
    sqlite3StrAccumInit(@accumulator, 0, @buffer(0), SizeOf(buffer), 0)
    If pViewArgument <> 0 Then
        Dim pView As SqliteTreeView Ptr = CPtr(SqliteTreeView Ptr, pViewArgument)
        Dim iLine As Long = 0
        While iLine < pView->iLevel AndAlso iLine < UBound(pView->bLine)
            If pView->bLine(iLine) <> 0 Then
                sqlite3_str_append(@accumulator, StrPtr("|   "), 4)
            Else
                sqlite3_str_append(@accumulator, StrPtr("    "), 4)
            End If
            iLine += 1
        Wend
        If pView->bLine(iLine) <> 0 Then
            sqlite3_str_append(@accumulator, StrPtr("|-- "), 4)
        Else
            sqlite3_str_append(@accumulator, StrPtr("'-- "), 4)
        End If
    End If
    If zFormat <> 0 Then
        Dim args As Cva_List
        Cva_Start(args, zFormat)
        sqlite3_str_vappendf(@accumulator, zFormat, args)
        Cva_End(args)
        sqlite3_str_append(@accumulator, StrPtr(!"\n"), 1)
    End If
    sqlite3StrAccumFinish(@accumulator)
    If accumulator.zText <> 0 Then _
        sqlite3DebugPrintf(StrPtr("%s"), CPtr(Const ZString Ptr, accumulator.zText))
End Sub

' c2fb skipped sqlite3TreeViewPush: outside the supported subset
Private Sub sqlite3TreeViewPop CDecl Alias "sqlite3TreeViewPop" (ByVal arg0 As SqliteTreeView Ptr Ptr)
    Dim local0 As SqliteTreeView Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SqliteTreeView Ptr Ptr
    Dim c2fb_temp_3 As SqliteTreeView Ptr

    local0 = (*arg0)
    If (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    c2fb_temp_0 = CPtr(SQLITE_C_INT Ptr, @(local0->iLevel))
    c2fb_temp_1 = (*c2fb_temp_0)
    (*c2fb_temp_0) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 - 1)))
    If (-Cast(SQLITE_C_INT, ((local0->iLevel < Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3_free(CPtr(Any Ptr, local0))
        c2fb_temp_2 = CPtr(SqliteTreeView Ptr Ptr, @((*arg0)))
        c2fb_temp_3 = CPtr(SqliteTreeView Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_2) = c2fb_temp_3
    End If
End Sub

' c2fb skipped sqlite3TreeViewLine: outside the supported subset
Private Sub sqlite3TreeViewItem CDecl Alias "sqlite3TreeViewItem" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As UByte)
    sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(arg0)), arg2)
    sqlite3TreeViewLine(arg0, StrPtr(!"%s"), arg1)
End Sub

Sub sqlite3TreeViewColumnList CDecl Alias "sqlite3TreeViewColumnList" ( _
    ByVal pViewArgument As Any Ptr, _
    ByVal columnsArgument As Const Any Ptr, _
    ByVal columnCount As SQLITE_C_INT, _
    ByVal moreToFollow As UByte _
)
    Dim pView As SqliteTreeView Ptr = CPtr(SqliteTreeView Ptr, pViewArgument)
    Dim pColumns As Const SqliteColumn Ptr = CPtr(Const SqliteColumn Ptr, columnsArgument)
    sqlite3TreeViewPush(@pView, moreToFollow)
    sqlite3TreeViewLine(pView, StrPtr("COLUMNS"))
    If pColumns <> 0 AndAlso columnCount > 0 Then
        For iColumn As SQLITE_C_INT = 0 To columnCount - 1
            Dim pColumn As Const SqliteColumn Ptr = @pColumns[iColumn]
            Dim columnFlags As u16 = pColumn->colFlags
            Dim columnType As SQLITE_C_INT = CInt((pColumn->flags Shr 4) And &HF)
            Dim columnFollows As UByte = 0
            If iColumn < columnCount - 1 Then columnFollows = 1
            sqlite3TreeViewPush(@pView, columnFollows)
            sqlite3TreeViewLine(pView, 0)
            If pColumn->zCnName <> 0 Then
                sqlite3DebugPrintf(StrPtr(" %s"), pColumn->zCnName)
            Else
                sqlite3DebugPrintf(StrPtr(" (null)"))
            End If

            Select Case columnType
            Case COLTYPE_ANY: sqlite3DebugPrintf(StrPtr(" ANY"))
            Case COLTYPE_BLOB: sqlite3DebugPrintf(StrPtr(" BLOB"))
            Case COLTYPE_INT: sqlite3DebugPrintf(StrPtr(" INT"))
            Case COLTYPE_INTEGER: sqlite3DebugPrintf(StrPtr(" INTEGER"))
            Case COLTYPE_REAL: sqlite3DebugPrintf(StrPtr(" REAL"))
            Case COLTYPE_TEXT: sqlite3DebugPrintf(StrPtr(" TEXT"))
            Case COLTYPE_CUSTOM
                If (columnFlags And COLFLAG_HASTYPE) <> 0 AndAlso pColumn->zCnName <> 0 Then
                    Dim typeName As Const ZString Ptr = CPtr(Const ZString Ptr, _
                        CPtr(Const UByte Ptr, pColumn->zCnName) + sqlite3Strlen30(pColumn->zCnName) + 1)
                    sqlite3DebugPrintf(StrPtr(" X-%s"), typeName)
                End If
            End Select

            If (columnFlags And COLFLAG_PRIMKEY) <> 0 Then _
                sqlite3DebugPrintf(StrPtr(" PRIMARY KEY"))
            If (columnFlags And COLFLAG_HIDDEN) <> 0 Then _
                sqlite3DebugPrintf(StrPtr(" HIDDEN"))
            If (columnFlags And COLFLAG_NOEXPAND) <> 0 Then _
                sqlite3DebugPrintf(StrPtr(" NO-EXPAND"))
            If columnFlags <> 0 Then _
                sqlite3DebugPrintf(StrPtr(" flags=%04x"), CInt(columnFlags))
            sqlite3DebugPrintf(StrPtr(!"\n"))
            sqlite3TreeViewPop(@pView)
        Next
    End If
    sqlite3TreeViewPop(@pView)
End Sub

Sub sqlite3TreeViewWith CDecl Alias "sqlite3TreeViewWith" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteWithRecord Ptr, ByVal arg2 As UByte)
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local1 As sqlite3_str
    Dim local2(0 To 999) As Byte
    Dim local3 As Const SqliteCte Ptr
    Dim local4 As Byte
    Dim local5 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As Byte
    Dim c2fb_temp_5 As ZString Ptr

    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    If (-Cast(SQLITE_C_INT, ((arg1->nCte = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    If CPtr(SqliteWithRecord Ptr, arg1->pOuter) Then
        sqlite3TreeViewLine(arg0, StrPtr(!"WITH (0x%p, pOuter=0x%p)"), arg1, CPtr(SqliteWithRecord Ptr, arg1->pOuter))
    Else
        sqlite3TreeViewLine(arg0, StrPtr(!"WITH (0x%p)"), arg1)
    End If
    If (-Cast(SQLITE_C_INT, ((arg1->nCte > Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(arg0)), arg2)
        c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local0 = c2fb_temp_0
        While (-Cast(SQLITE_C_INT, ((local0 < arg1->nCte))))
            ' C automatic storage declaration
            ' C automatic array storage
            local3 = CPtr(SqliteCte Ptr, @(arg1->a(local0)))
            sqlite3StrAccumInit(CPtr(sqlite3_str Ptr, @(local1)), Cast(SQLITE_C_INT, &O0ULL), CPtr(ZString Ptr, CPtr(Byte Ptr, (@local2(0)))), Cast(SQLITE_SIZE_T, (1000ULL * SizeOf(Byte))), Cast(SQLITE_C_INT, &O0ULL))
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local1)), StrPtr(!"%s"), local3->zName)
            If (-Cast(SQLITE_C_INT, ((local3->pCols AndAlso (-Cast(SQLITE_C_INT, ((local3->pCols->nExpr > Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                local4 = Cast(SQLITE_C_INT, 40)
                ' C automatic storage declaration
                c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local5 = c2fb_temp_2
                While (-Cast(SQLITE_C_INT, ((local5 < local3->pCols->nExpr))))
                    sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local1)), StrPtr(!"%c%s"), local4, CPtr(ZString Ptr, local3->pCols->a(local5).zEName))
                    c2fb_temp_4 = Cast(Byte, Cast(SQLITE_C_INT, 44))
                    local4 = c2fb_temp_4
                c2fb_flow_3:
                    c2fb_temp_3 = local5
                    local5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_3 + 1)))
                Wend
                c2fb_flow_2:
                sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local1)), StrPtr(!")"))
            End If
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->eM10d) <> Cast(SQLITE_C_INT, 1ULL))))) Then
                sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local1)), StrPtr(!" %sMATERIALIZED"), IIf((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->eM10d) = Cast(SQLITE_C_INT, 2ULL))))), StrPtr(!"NOT "), StrPtr(!"")))
            End If
            If local3->pUse Then
                sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local1)), StrPtr(!" (pUse=0x%p, nUse=%d)"), local3->pUse, local3->pUse->nUse)
            End If
            c2fb_temp_5 = CPtr(ZString Ptr, sqlite3StrAccumFinish(CPtr(sqlite3_str Ptr, @(local1))))
            sqlite3TreeViewItem(arg0, CPtr(Const ZString Ptr, CPtr(Byte Ptr, (@local2(0)))), (-Cast(SQLITE_C_INT, ((local0 < Cast(SQLITE_C_INT, (arg1->nCte - Cast(SQLITE_C_INT, 1ULL))))))))
            sqlite3TreeViewSelect(arg0, CPtr(Const SqliteSelect Ptr, local3->pSelect), Cast(SQLITE_C_INT, &O0ULL))
            sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
        c2fb_flow_1:
            c2fb_temp_1 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
        Wend
        c2fb_flow_0:
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
    End If
End Sub

' c2fb skipped sqlite3TreeViewSrcList: outside the supported subset
Sub sqlite3TreeViewSelect CDecl Alias "sqlite3TreeViewSelect" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteSelect Ptr, ByVal arg2 As UByte)
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim local2 As SqliteWalkerWindow Ptr
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SqliteTreeView Ptr Ptr
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SqliteWalkerWindow Ptr
    Dim c2fb_temp_17 As SqliteWalkerWindow Ptr
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As SqliteTreeView Ptr Ptr
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As SQLITE_C_INT
    Dim c2fb_temp_22 As SqliteTreeView Ptr
    Dim c2fb_temp_23 As Const ZString Ptr
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As SQLITE_C_INT
    Dim c2fb_temp_26 As SqliteTreeView Ptr
    Dim c2fb_temp_27 As SqliteExprList Ptr
    Dim c2fb_temp_28 As SQLITE_C_INT
    Dim c2fb_temp_29 As Const ZString Ptr
    Dim c2fb_temp_30 As SQLITE_C_INT
    Dim c2fb_temp_31 As SqliteTreeView Ptr
    Dim c2fb_temp_32 As Const ZString Ptr
    Dim c2fb_temp_33 As SQLITE_C_INT
    Dim local3 As SqliteWalkerWindow Ptr
    Dim c2fb_temp_34 As SQLITE_C_INT
    Dim c2fb_temp_35 As SqliteTreeView Ptr
    Dim c2fb_temp_36 As Const ZString Ptr
    Dim c2fb_temp_37 As SQLITE_C_INT
    Dim c2fb_temp_38 As SqliteWalkerWindow Ptr
    Dim c2fb_temp_39 As SqliteWalkerWindow Ptr
    Dim c2fb_temp_40 As SQLITE_C_INT
    Dim c2fb_temp_41 As SqliteTreeView Ptr
    Dim c2fb_temp_42 As SqliteExprList Ptr
    Dim c2fb_temp_43 As SQLITE_C_INT
    Dim c2fb_temp_44 As Const ZString Ptr
    Dim c2fb_temp_45 As SQLITE_C_INT
    Dim c2fb_temp_46 As SqliteTreeView Ptr
    Dim c2fb_temp_47 As Const ZString Ptr
    Dim c2fb_temp_48 As SQLITE_C_INT
    Dim local4 As Const ZString Ptr
    Dim c2fb_temp_49 As Const ZString Ptr
    Dim c2fb_temp_50 As Const ZString Ptr
    Dim c2fb_temp_51 As Const ZString Ptr
    Dim c2fb_temp_52 As Const SqliteSelect Ptr

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3TreeViewLine(arg0, StrPtr(!"nil-SELECT"))
        Return
    End If
    sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(arg0)), arg2)
    If CPtr(SqliteWithRecord Ptr, arg1->pWith) Then
        sqlite3TreeViewWith(arg0, CPtr(Const SqliteWithRecord Ptr, CPtr(SqliteWithRecord Ptr, arg1->pWith)), Cast(SQLITE_C_INT, 1ULL))
        c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
        local1 = c2fb_temp_0
        sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(arg0)), Cast(SQLITE_C_INT, 1ULL))
    End If
    Do
        If Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0080000ULL)))) Then
            sqlite3TreeViewLine(arg0, StrPtr(!"sqlite3WhereBegin()"))
        Else
            sqlite3TreeViewLine(arg0, StrPtr(!"SELECT%s%s (%u/%p) selFlags=0x%x nSelectRow=%d"), (IIf((Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000001ULL))))), StrPtr(!" DISTINCT"), StrPtr(!""))), (IIf((Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000008ULL))))), StrPtr(!" agg_flag"), StrPtr(!""))), arg1->selId, arg1, arg1->selFlags, Cast(SQLITE_C_INT, arg1->nSelectRow))
        End If
        c2fb_temp_1 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
        If c2fb_temp_1 Then
            sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
        End If
        If arg1->pPrior Then
            c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1000ULL))
            local0 = c2fb_temp_2
        Else
            c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local0 = c2fb_temp_3
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, (-Cast(SQLITE_C_INT, ((arg1->pSrc AndAlso arg1->pSrc->nSrc))))) AndAlso arg1->pSrc->nAlloc)))) Then
                c2fb_temp_4 = local0
                local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_4 + 1)))
            End If
            If arg1->pWhere Then
                c2fb_temp_5 = local0
                local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_5 + 1)))
            End If
            If arg1->pGroupBy Then
                c2fb_temp_6 = local0
                local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 + 1)))
            End If
            If arg1->pHaving Then
                c2fb_temp_7 = local0
                local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_7 + 1)))
            End If
            If arg1->pOrderBy Then
                c2fb_temp_8 = local0
                local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_8 + 1)))
            End If
            If arg1->pLimit Then
                c2fb_temp_9 = local0
                local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_9 + 1)))
            End If
            If CPtr(SqliteWalkerWindow Ptr, arg1->pWin) Then
                c2fb_temp_10 = local0
                local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_10 + 1)))
            End If
            If CPtr(SqliteWalkerWindow Ptr, arg1->pWinDefn) Then
                c2fb_temp_11 = local0
                local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_11 + 1)))
            End If
        End If
        If arg1->pEList Then
            sqlite3TreeViewExprList(arg0, CPtr(Const SqliteExprList Ptr, arg1->pEList), (-Cast(SQLITE_C_INT, ((local0 > Cast(SQLITE_C_INT, &O0ULL))))), StrPtr(!"result-set"))
        End If
        c2fb_temp_12 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_12 - 1)))
        If CPtr(SqliteWalkerWindow Ptr, arg1->pWin) Then
            ' C automatic storage declaration
            c2fb_temp_14 = CPtr(SqliteTreeView Ptr Ptr, @(arg0))
            c2fb_temp_13 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_13 - 1)))
            c2fb_temp_15 = (-Cast(SQLITE_C_INT, (((c2fb_temp_13) > Cast(SQLITE_C_INT, &O0ULL)))))
            sqlite3TreeViewPush(c2fb_temp_14, c2fb_temp_15)
            sqlite3TreeViewLine(arg0, StrPtr(!"window-functions"))
            c2fb_temp_16 = CPtr(SqliteWalkerWindow Ptr, arg1->pWin)
            local2 = c2fb_temp_16
            While local2
                sqlite3TreeViewWinFunc(arg0, CPtr(Const SqliteWalkerWindow Ptr, local2), (-Cast(SQLITE_C_INT, ((local2->pNextWin <> Cast(SQLITE_C_INT, &O0ULL))))))
            c2fb_flow_3:
                c2fb_temp_17 = local2->pNextWin
                local2 = c2fb_temp_17
            Wend
            c2fb_flow_2:
            sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, (-Cast(SQLITE_C_INT, ((arg1->pSrc AndAlso arg1->pSrc->nSrc))))) AndAlso arg1->pSrc->nAlloc)))) Then
            c2fb_temp_19 = CPtr(SqliteTreeView Ptr Ptr, @(arg0))
            c2fb_temp_18 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_18 - 1)))
            c2fb_temp_20 = (-Cast(SQLITE_C_INT, (((c2fb_temp_18) > Cast(SQLITE_C_INT, &O0ULL)))))
            sqlite3TreeViewPush(c2fb_temp_19, c2fb_temp_20)
            sqlite3TreeViewLine(arg0, StrPtr(!"FROM"))
            sqlite3TreeViewSrcList(arg0, CPtr(Const SqliteSrcList Ptr, arg1->pSrc))
            sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
        End If
        If arg1->pWhere Then
            c2fb_temp_22 = arg0
            c2fb_temp_23 = StrPtr(!"WHERE")
            c2fb_temp_21 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_21 - 1)))
            c2fb_temp_24 = (-Cast(SQLITE_C_INT, (((c2fb_temp_21) > Cast(SQLITE_C_INT, &O0ULL)))))
            sqlite3TreeViewItem(c2fb_temp_22, c2fb_temp_23, c2fb_temp_24)
            sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, arg1->pWhere), Cast(SQLITE_C_INT, &O0ULL))
            sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
        End If
        If arg1->pGroupBy Then
            c2fb_temp_26 = arg0
            c2fb_temp_27 = arg1->pGroupBy
            c2fb_temp_25 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_25 - 1)))
            c2fb_temp_28 = (-Cast(SQLITE_C_INT, (((c2fb_temp_25) > Cast(SQLITE_C_INT, &O0ULL)))))
            c2fb_temp_29 = StrPtr(!"GROUPBY")
            sqlite3TreeViewExprList(c2fb_temp_26, CPtr(Const SqliteExprList Ptr, c2fb_temp_27), c2fb_temp_28, c2fb_temp_29)
        End If
        If arg1->pHaving Then
            c2fb_temp_31 = arg0
            c2fb_temp_32 = StrPtr(!"HAVING")
            c2fb_temp_30 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_30 - 1)))
            c2fb_temp_33 = (-Cast(SQLITE_C_INT, (((c2fb_temp_30) > Cast(SQLITE_C_INT, &O0ULL)))))
            sqlite3TreeViewItem(c2fb_temp_31, c2fb_temp_32, c2fb_temp_33)
            sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, arg1->pHaving), Cast(SQLITE_C_INT, &O0ULL))
            sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
        End If
        If CPtr(SqliteWalkerWindow Ptr, arg1->pWinDefn) Then
            ' C automatic storage declaration
            c2fb_temp_35 = arg0
            c2fb_temp_36 = StrPtr(!"WINDOW")
            c2fb_temp_34 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_34 - 1)))
            c2fb_temp_37 = (-Cast(SQLITE_C_INT, (((c2fb_temp_34) > Cast(SQLITE_C_INT, &O0ULL)))))
            sqlite3TreeViewItem(c2fb_temp_35, c2fb_temp_36, c2fb_temp_37)
            c2fb_temp_38 = CPtr(SqliteWalkerWindow Ptr, arg1->pWinDefn)
            local3 = c2fb_temp_38
            While local3
                sqlite3TreeViewWindow(arg0, CPtr(Const SqliteWalkerWindow Ptr, local3), (-Cast(SQLITE_C_INT, ((local3->pNextWin <> Cast(SQLITE_C_INT, &O0ULL))))))
            c2fb_flow_5:
                c2fb_temp_39 = local3->pNextWin
                local3 = c2fb_temp_39
            Wend
            c2fb_flow_4:
            sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
        End If
        If arg1->pOrderBy Then
            c2fb_temp_41 = arg0
            c2fb_temp_42 = arg1->pOrderBy
            c2fb_temp_40 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_40 - 1)))
            c2fb_temp_43 = (-Cast(SQLITE_C_INT, (((c2fb_temp_40) > Cast(SQLITE_C_INT, &O0ULL)))))
            c2fb_temp_44 = StrPtr(!"ORDERBY")
            sqlite3TreeViewExprList(c2fb_temp_41, CPtr(Const SqliteExprList Ptr, c2fb_temp_42), c2fb_temp_43, c2fb_temp_44)
        End If
        If arg1->pLimit Then
            c2fb_temp_46 = arg0
            c2fb_temp_47 = StrPtr(!"LIMIT")
            c2fb_temp_45 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_45 - 1)))
            c2fb_temp_48 = (-Cast(SQLITE_C_INT, (((c2fb_temp_45) > Cast(SQLITE_C_INT, &O0ULL)))))
            sqlite3TreeViewItem(c2fb_temp_46, c2fb_temp_47, c2fb_temp_48)
            sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, arg1->pLimit->pLeft), (-Cast(SQLITE_C_INT, ((arg1->pLimit->pRight <> Cast(SQLITE_C_INT, &O0ULL))))))
            If arg1->pLimit->pRight Then
                sqlite3TreeViewItem(arg0, StrPtr(!"OFFSET"), Cast(SQLITE_C_INT, &O0ULL))
                sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, arg1->pLimit->pRight), Cast(SQLITE_C_INT, &O0ULL))
                sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
            End If
            sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
        End If
        If arg1->pPrior Then
            local4 = StrPtr(!"UNION")
            Select Case arg1->op
                Case Cast(SQLITE_C_INT, 136ULL)
                    c2fb_temp_49 = StrPtr(!"UNION ALL")
                    local4 = c2fb_temp_49
                Case Cast(SQLITE_C_INT, 138ULL)
                    c2fb_temp_50 = StrPtr(!"INTERSECT")
                    local4 = c2fb_temp_50
                Case Cast(SQLITE_C_INT, 137ULL)
                    c2fb_temp_51 = StrPtr(!"EXCEPT")
                    local4 = c2fb_temp_51
            End Select
            c2fb_flow_6:
            sqlite3TreeViewItem(arg0, local4, Cast(SQLITE_C_INT, 1ULL))
        End If
        c2fb_temp_52 = CPtr(Const SqliteSelect Ptr, arg1->pPrior)
        arg1 = c2fb_temp_52
    c2fb_flow_1:
    Loop While (-Cast(SQLITE_C_INT, ((arg1 <> Cast(SQLITE_C_INT, &O0ULL)))))
    c2fb_flow_0:
    sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
End Sub

Sub sqlite3TreeViewBound CDecl Alias "sqlite3TreeViewBound" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As UByte, ByVal arg2 As SqliteExpr Ptr, ByVal arg3 As UByte)
    Select Case arg1
        Case Cast(SQLITE_C_INT, 91ULL)
            sqlite3TreeViewItem(arg0, StrPtr(!"UNBOUNDED"), arg3)
            sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 86ULL)
            sqlite3TreeViewItem(arg0, StrPtr(!"CURRENT"), arg3)
            sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 89ULL)
            sqlite3TreeViewItem(arg0, StrPtr(!"PRECEDING"), arg3)
            sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, arg2), Cast(SQLITE_C_INT, &O0ULL))
            sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 87ULL)
            sqlite3TreeViewItem(arg0, StrPtr(!"FOLLOWING"), arg3)
            sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, arg2), Cast(SQLITE_C_INT, &O0ULL))
            sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
            Goto c2fb_flow_0
    End Select
    c2fb_flow_0:
End Sub

Sub sqlite3TreeViewWindow CDecl Alias "sqlite3TreeViewWindow" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteWalkerWindow Ptr, ByVal arg2 As UByte)
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SqliteTreeView Ptr Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SqliteTreeView Ptr
    Dim c2fb_temp_11 As SqliteExprList Ptr
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As Const ZString Ptr
    Dim local1(0 To 29) As Byte
    Dim local2 As Const ZString Ptr
    Dim c2fb_temp_14 As Const ZString Ptr
    Dim c2fb_temp_15 As Const ZString Ptr
    Dim c2fb_temp_16 As ZString Ptr
    Dim c2fb_temp_17 As SQLITE_C_INT
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As SqliteTreeView Ptr
    Dim c2fb_temp_20 As Byte Ptr
    Dim c2fb_temp_21 As SQLITE_C_INT
    Dim local3(0 To 29) As Byte
    Dim local4 As Const ZString Ptr
    Dim c2fb_temp_22 As Const ZString Ptr
    Dim c2fb_temp_23 As Const ZString Ptr
    Dim c2fb_temp_24 As Const ZString Ptr
    Dim c2fb_temp_25 As Const ZString Ptr
    Dim c2fb_temp_26 As ZString Ptr
    Dim c2fb_temp_27 As Const ZString Ptr

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    If arg1->pFilter Then
        sqlite3TreeViewItem(arg0, StrPtr(!"FILTER"), Cast(SQLITE_C_INT, 1ULL))
        sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, arg1->pFilter), Cast(SQLITE_C_INT, &O0ULL))
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->eFrmType) = Cast(SQLITE_C_INT, 167ULL))))) Then
            Return
        End If
    End If
    sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(arg0)), arg2)
    If arg1->zName Then
        sqlite3TreeViewLine(arg0, StrPtr(!"OVER %s (%p)"), arg1->zName, arg1)
    Else
        sqlite3TreeViewLine(arg0, StrPtr(!"OVER (%p)"), arg1)
    End If
    If arg1->zBase Then
        c2fb_temp_0 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_0 + 1)))
    End If
    If arg1->pOrderBy Then
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->eFrmType) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->eFrmType) <> Cast(SQLITE_C_INT, 167ULL))))))))) Then
        c2fb_temp_2 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_2 + 1)))
    End If
    If arg1->eExclude Then
        c2fb_temp_3 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_3 + 1)))
    End If
    If arg1->zBase Then
        c2fb_temp_6 = CPtr(SqliteTreeView Ptr Ptr, @(arg0))
        c2fb_temp_4 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_4 - 1)))
        c2fb_temp_5 = local0
        c2fb_temp_7 = (-Cast(SQLITE_C_INT, (((c2fb_temp_5) > Cast(SQLITE_C_INT, &O0ULL)))))
        sqlite3TreeViewPush(c2fb_temp_6, c2fb_temp_7)
        sqlite3TreeViewLine(arg0, StrPtr(!"window: %s"), arg1->zBase)
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
    End If
    If arg1->pPartition Then
        sqlite3TreeViewExprList(arg0, CPtr(Const SqliteExprList Ptr, arg1->pPartition), (-Cast(SQLITE_C_INT, ((local0 > Cast(SQLITE_C_INT, &O0ULL))))), StrPtr(!"PARTITION-BY"))
    End If
    If arg1->pOrderBy Then
        c2fb_temp_10 = arg0
        c2fb_temp_11 = arg1->pOrderBy
        c2fb_temp_8 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_8 - 1)))
        c2fb_temp_9 = local0
        c2fb_temp_12 = (-Cast(SQLITE_C_INT, (((c2fb_temp_9) > Cast(SQLITE_C_INT, &O0ULL)))))
        c2fb_temp_13 = StrPtr(!"ORDER-BY")
        sqlite3TreeViewExprList(c2fb_temp_10, CPtr(Const SqliteExprList Ptr, c2fb_temp_11), c2fb_temp_12, c2fb_temp_13)
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->eFrmType) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->eFrmType) <> Cast(SQLITE_C_INT, 167ULL))))))))) Then
        ' C automatic array storage
        local2 = StrPtr(!"ROWS")
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->eFrmType) = Cast(SQLITE_C_INT, 90ULL))))) Then
            c2fb_temp_14 = StrPtr(!"RANGE")
            local2 = c2fb_temp_14
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->eFrmType) = Cast(SQLITE_C_INT, 93ULL))))) Then
            c2fb_temp_15 = StrPtr(!"GROUPS")
            local2 = c2fb_temp_15
        End If
        c2fb_temp_16 = CPtr(ZString Ptr, sqlite3_snprintf(Cast(SQLITE_SIZE_T, (30ULL * SizeOf(Byte))), CPtr(ZString Ptr, CPtr(Byte Ptr, (@local1(0)))), StrPtr(!"%s%s"), local2, IIf(arg1->bImplicitFrame, StrPtr(!" (implied)"), StrPtr(!""))))
        c2fb_temp_19 = arg0
        c2fb_temp_20 = CPtr(Byte Ptr, (@local1(0)))
        c2fb_temp_17 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_17 - 1)))
        c2fb_temp_18 = local0
        c2fb_temp_21 = (-Cast(SQLITE_C_INT, (((c2fb_temp_18) > Cast(SQLITE_C_INT, &O0ULL)))))
        sqlite3TreeViewItem(c2fb_temp_19, CPtr(Const ZString Ptr, c2fb_temp_20), c2fb_temp_21)
        sqlite3TreeViewBound(arg0, arg1->eStart, arg1->pStart, Cast(SQLITE_C_INT, 1ULL))
        sqlite3TreeViewBound(arg0, arg1->eEnd, arg1->pEnd, Cast(SQLITE_C_INT, &O0ULL))
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
    End If
    If arg1->eExclude Then
        ' C automatic array storage
        ' C automatic storage declaration
        Select Case arg1->eExclude
            Case Cast(SQLITE_C_INT, 67ULL)
                c2fb_temp_22 = StrPtr(!"NO OTHERS")
                local4 = c2fb_temp_22
            Case Cast(SQLITE_C_INT, 86ULL)
                c2fb_temp_23 = StrPtr(!"CURRENT ROW")
                local4 = c2fb_temp_23
            Case Cast(SQLITE_C_INT, 147ULL)
                c2fb_temp_24 = StrPtr(!"GROUP")
                local4 = c2fb_temp_24
            Case Cast(SQLITE_C_INT, 95ULL)
                c2fb_temp_25 = StrPtr(!"TIES")
                local4 = c2fb_temp_25
            Case Else
                c2fb_temp_26 = CPtr(ZString Ptr, sqlite3_snprintf(Cast(SQLITE_SIZE_T, (30ULL * SizeOf(Byte))), CPtr(ZString Ptr, CPtr(Byte Ptr, (@local3(0)))), StrPtr(!"invalid(%d)"), arg1->eExclude))
                c2fb_temp_27 = CPtr(Const ZString Ptr, CPtr(Byte Ptr, (@local3(0))))
                local4 = c2fb_temp_27
        End Select
        c2fb_flow_0:
        sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(arg0)), Cast(SQLITE_C_INT, &O0ULL))
        sqlite3TreeViewLine(arg0, StrPtr(!"EXCLUDE %s"), local4)
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
    End If
    sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
End Sub

Sub sqlite3TreeViewWinFunc CDecl Alias "sqlite3TreeViewWinFunc" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteWalkerWindow Ptr, ByVal arg2 As UByte)
    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(arg0)), arg2)
    sqlite3TreeViewLine(arg0, StrPtr(!"WINFUNC %s(%d)"), CPtr(SqliteFuncDef Ptr, arg1->pWFunc)->zName, CPtr(SqliteFuncDef Ptr, arg1->pWFunc)->nArg)
    sqlite3TreeViewWindow(arg0, arg1, Cast(SQLITE_C_INT, &O0ULL))
    sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
End Sub

' c2fb skipped sqlite3TreeViewExpr: outside the supported subset
' c2fb skipped sqlite3TreeViewBareExprList: outside the supported subset
Sub sqlite3TreeViewExprList CDecl Alias "sqlite3TreeViewExprList" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteExprList Ptr, ByVal arg2 As UByte, ByVal arg3 As Const ZString Ptr)
    sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(arg0)), arg2)
    sqlite3TreeViewBareExprList(arg0, arg1, arg3)
    sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
End Sub

Sub sqlite3TreeViewBareExprList CDecl Alias "sqlite3TreeViewBareExprList" ( _
    ByVal pView As SqliteTreeView Ptr, _
    ByVal pList As Const SqliteExprList Ptr, _
    ByVal zLabel As Const ZString Ptr _
)
    If zLabel = 0 OrElse sqlite3Strlen30(zLabel) = 0 Then zLabel = StrPtr("LIST")
    If pList = 0 Then
        sqlite3TreeViewLine(pView, StrPtr("%s (empty)"), zLabel)
        Exit Sub
    End If

    sqlite3TreeViewLine(pView, StrPtr("%s"), zLabel)
    For iEntry As SQLITE_C_INT = 0 To pList->nExpr - 1
        Dim pItem As Const SqliteExprListItem Ptr = @pList->a(iEntry)
        Dim orderByColumn As UShort = pItem->u.x.iOrderByCol
        Dim sortFlags As UByte = pItem->fg.sortFlags
        Dim zName As Const ZString Ptr = CPtr(Const ZString Ptr, pItem->zEName)
        Dim moreToFollow As UByte = 0
        If iEntry < pList->nExpr - 1 Then moreToFollow = 1

        If orderByColumn <> 0 OrElse zName <> 0 OrElse sortFlags <> 0 Then
            sqlite3TreeViewPush(@pView, moreToFollow)
            moreToFollow = 0
            sqlite3TreeViewLine(pView, 0)
            If zName <> 0 Then
                Select Case pItem->fg.flags And SQLITE_EXPRLIST_EENAME_MASK
                Case ENAME_TAB
                    sqlite3DebugPrintf(StrPtr(!"TABLE-ALIAS-NAME(\"%s\") "), zName)
                    If (pItem->fg.flags And SQLITE_EXPRLIST_BUSED) <> 0 Then _
                        sqlite3DebugPrintf(StrPtr("(used) "))
                    If (pItem->fg.flags And SQLITE_EXPRLIST_BUSINGTERM) <> 0 Then _
                        sqlite3DebugPrintf(StrPtr("(USING-term) "))
                    If (pItem->fg.flags And SQLITE_EXPRLIST_BNOEXPAND) <> 0 Then _
                        sqlite3DebugPrintf(StrPtr("(NoExpand) "))
                Case ENAME_SPAN
                    sqlite3DebugPrintf(StrPtr(!"SPAN(\"%s\") "), zName)
                Case Else
                    sqlite3DebugPrintf(StrPtr("AS %s "), zName)
                End Select
            End If
            If orderByColumn <> 0 Then _
                sqlite3DebugPrintf(StrPtr("iOrderByCol=%d "), CInt(orderByColumn))
            If (sortFlags And KEYINFO_ORDER_DESC) <> 0 Then
                sqlite3DebugPrintf(StrPtr("DESC "))
            ElseIf (sortFlags And KEYINFO_ORDER_BIGNULL) <> 0 Then
                sqlite3DebugPrintf(StrPtr("NULLS-LAST"))
            End If
            sqlite3DebugPrintf(StrPtr(!"\n"))
        End If

        sqlite3TreeViewExpr(pView, pItem->pExpr, moreToFollow)
        If orderByColumn <> 0 OrElse zName <> 0 OrElse sortFlags <> 0 Then _
            sqlite3TreeViewPop(@pView)
    Next
End Sub

Sub sqlite3TreeViewBareIdList CDecl Alias "sqlite3TreeViewBareIdList" ( _
    ByVal pViewArgument As Any Ptr, _
    ByVal listArgument As Const Any Ptr, _
    ByVal label As Const ZString Ptr _
)
    Dim pView As SqliteTreeView Ptr = CPtr(SqliteTreeView Ptr, pViewArgument)
    Dim pList As Const SqliteIdList Ptr = CPtr(Const SqliteIdList Ptr, listArgument)
    Dim labelText As Const ZString Ptr = label
    If labelText = 0 OrElse sqlite3Strlen30(labelText) = 0 Then labelText = StrPtr("LIST")
    If pList = 0 Then
        sqlite3TreeViewLine(pView, StrPtr("%s (empty)"), labelText)
        Exit Sub
    End If

    sqlite3TreeViewLine(pView, StrPtr("%s"), labelText)
    If pList->nId > 0 Then
        For iEntry As SQLITE_C_INT = 0 To pList->nId - 1
            Dim zName As Const ZString Ptr = pList->a(iEntry).zName
            Dim moreToFollow As UByte = 0
            If iEntry < pList->nId - 1 Then moreToFollow = 1
            If zName = 0 Then zName = StrPtr("(null)")
            sqlite3TreeViewPush(@pView, moreToFollow)
            sqlite3TreeViewLine(pView, 0)
            sqlite3DebugPrintf(StrPtr(!"%s\n"), zName)
            sqlite3TreeViewPop(@pView)
        Next
    End If
End Sub

Sub sqlite3TreeViewIdList CDecl Alias "sqlite3TreeViewIdList" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteIdList Ptr, ByVal arg2 As UByte, ByVal arg3 As Const ZString Ptr)
    sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(arg0)), arg2)
    sqlite3TreeViewBareIdList(arg0, arg1, arg3)
    sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
End Sub

Sub sqlite3TreeViewUpsert CDecl Alias "sqlite3TreeViewUpsert" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteUpsert Ptr, ByVal arg2 As UByte)
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SqliteTreeView Ptr
    Dim c2fb_temp_3 As SqliteExprList Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As Const ZString Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SqliteTreeView Ptr
    Dim c2fb_temp_8 As SqliteExprList Ptr
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As Const ZString Ptr
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SqliteTreeView Ptr
    Dim c2fb_temp_13 As Const ZString Ptr
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As Const SqliteUpsert Ptr

    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(arg0)), arg2)
    While arg1
        ' C automatic storage declaration
        sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(arg0)), (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg1->pNextUpsert <> Cast(SQLITE_C_INT, &O0ULL))))) OrElse Cast(SQLITE_C_INT, arg2))))))
        sqlite3TreeViewLine(arg0, StrPtr(!"ON CONFLICT DO %s"), IIf(arg1->isDoUpdate, StrPtr(!"UPDATE"), StrPtr(!"NOTHING")))
        c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((CPtr(SqliteExprList Ptr, arg1->pUpsertSet) <> Cast(SQLITE_C_INT, &O0ULL)))))) + ((-Cast(SQLITE_C_INT, ((CPtr(SqliteExpr Ptr, arg1->pUpsertWhere) <> Cast(SQLITE_C_INT, &O0ULL)))))))))
        local0 = c2fb_temp_0
        c2fb_temp_2 = arg0
        c2fb_temp_3 = CPtr(SqliteExprList Ptr, arg1->pUpsertTarget)
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 - 1)))
        c2fb_temp_4 = (-Cast(SQLITE_C_INT, (((c2fb_temp_1) > Cast(SQLITE_C_INT, &O0ULL)))))
        c2fb_temp_5 = StrPtr(!"TARGET")
        sqlite3TreeViewExprList(c2fb_temp_2, CPtr(Const SqliteExprList Ptr, c2fb_temp_3), c2fb_temp_4, c2fb_temp_5)
        c2fb_temp_7 = arg0
        c2fb_temp_8 = CPtr(SqliteExprList Ptr, arg1->pUpsertSet)
        c2fb_temp_6 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 - 1)))
        c2fb_temp_9 = (-Cast(SQLITE_C_INT, (((c2fb_temp_6) > Cast(SQLITE_C_INT, &O0ULL)))))
        c2fb_temp_10 = StrPtr(!"SET")
        sqlite3TreeViewExprList(c2fb_temp_7, CPtr(Const SqliteExprList Ptr, c2fb_temp_8), c2fb_temp_9, c2fb_temp_10)
        If CPtr(SqliteExpr Ptr, arg1->pUpsertWhere) Then
            c2fb_temp_12 = arg0
            c2fb_temp_13 = StrPtr(!"WHERE")
            c2fb_temp_11 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_11 - 1)))
            c2fb_temp_14 = (-Cast(SQLITE_C_INT, (((c2fb_temp_11) > Cast(SQLITE_C_INT, &O0ULL)))))
            sqlite3TreeViewItem(c2fb_temp_12, c2fb_temp_13, c2fb_temp_14)
            sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, CPtr(SqliteExpr Ptr, arg1->pUpsertWhere)), Cast(SQLITE_C_INT, &O0ULL))
            sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
        End If
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
        c2fb_temp_15 = CPtr(Const SqliteUpsert Ptr, arg1->pNextUpsert)
        arg1 = c2fb_temp_15
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
End Sub

Sub sqlite3TreeViewTriggerStep CDecl Alias "sqlite3TreeViewTriggerStep" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteTriggerStep Ptr, ByVal arg2 As UByte, ByVal arg3 As UByte)
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As Const SqliteTriggerStep Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(arg0)), (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg2) OrElse ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg3) AndAlso (-Cast(SQLITE_C_INT, ((arg1->pNext <> Cast(SQLITE_C_INT, &O0ULL)))))))))))))))
    Do
        c2fb_temp_0 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_0 + 1)))
        If (-Cast(SQLITE_C_INT, ((c2fb_temp_0 AndAlso (-Cast(SQLITE_C_INT, ((arg1->pNext = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
            sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(arg0)), Cast(SQLITE_C_INT, &O0ULL))
        End If
        sqlite3TreeViewLine(arg0, StrPtr(!"%s"), IIf(arg1->zSpan, CPtr(Const ZString Ptr, arg1->zSpan), StrPtr(!"RETURNING")))
    c2fb_flow_1:
        c2fb_temp_2 = 0
        If arg3 Then
            c2fb_temp_1 = CPtr(Const SqliteTriggerStep Ptr, arg1->pNext)
            arg1 = c2fb_temp_1
            c2fb_temp_2 = (-Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, (((c2fb_temp_1) <> Cast(SQLITE_C_INT, &O0ULL))))) <> 0)))
        End If
    Loop While c2fb_temp_2
    c2fb_flow_0:
    sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
End Sub

Sub sqlite3TreeViewTrigger CDecl Alias "sqlite3TreeViewTrigger" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteTrigger Ptr, ByVal arg2 As UByte, ByVal arg3 As UByte)
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As Const SqliteTrigger Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(arg0)), (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg2) OrElse ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg3) AndAlso (-Cast(SQLITE_C_INT, ((arg1->pNext <> Cast(SQLITE_C_INT, &O0ULL)))))))))))))))
    Do
        c2fb_temp_0 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_0 + 1)))
        If (-Cast(SQLITE_C_INT, ((c2fb_temp_0 AndAlso (-Cast(SQLITE_C_INT, ((arg1->pNext = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
            sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(arg0)), Cast(SQLITE_C_INT, &O0ULL))
        End If
        sqlite3TreeViewLine(arg0, StrPtr(!"TRIGGER %s"), arg1->zName)
        sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(arg0)), Cast(SQLITE_C_INT, &O0ULL))
        sqlite3TreeViewTriggerStep(arg0, CPtr(Const SqliteTriggerStep Ptr, arg1->step_list), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, 1ULL))
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
    c2fb_flow_1:
        c2fb_temp_2 = 0
        If arg3 Then
            c2fb_temp_1 = CPtr(Const SqliteTrigger Ptr, arg1->pNext)
            arg1 = c2fb_temp_1
            c2fb_temp_2 = (-Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, (((c2fb_temp_1) <> Cast(SQLITE_C_INT, &O0ULL))))) <> 0)))
        End If
    Loop While c2fb_temp_2
    c2fb_flow_0:
    sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
End Sub

' c2fb skipped sqlite3ShowExpr: FreeBASIC body already exists
' c2fb skipped sqlite3ShowExprList: FreeBASIC body already exists
' c2fb skipped sqlite3ShowIdList: FreeBASIC body already exists
Sub sqlite3ShowSrcList CDecl Alias "sqlite3ShowSrcList" (ByVal arg0 As Const SqliteSrcList Ptr)
    Dim local0 As SqliteTreeView Ptr

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(local0)), Cast(SQLITE_C_INT, &O0ULL))
    sqlite3TreeViewLine(local0, StrPtr(!"SRCLIST"))
    sqlite3TreeViewSrcList(local0, arg0)
    sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(local0)))
End Sub

' c2fb skipped sqlite3ShowSelect: FreeBASIC body already exists
' c2fb skipped sqlite3ShowWith: FreeBASIC body already exists
' c2fb skipped sqlite3ShowUpsert: FreeBASIC body already exists
' c2fb skipped sqlite3ShowTriggerStep: FreeBASIC body already exists
' c2fb skipped sqlite3ShowTriggerStepList: FreeBASIC body already exists
' c2fb skipped sqlite3ShowTrigger: FreeBASIC body already exists
' c2fb skipped sqlite3ShowTriggerList: FreeBASIC body already exists
' c2fb skipped sqlite3ShowWindow: FreeBASIC body already exists
' c2fb skipped sqlite3ShowWinFunc: FreeBASIC body already exists

/' ------------------------------------------------------------------------- '/
/' Translated TreeView source-list and expression renderers '/
/' ------------------------------------------------------------------------- '/

Sub sqlite3TreeViewSrcList CDecl Alias "sqlite3TreeViewSrcList" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteSrcList Ptr)
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local1 As Const SqliteSrcItem Ptr
    Dim local2 As sqlite3_str
    Dim local3 As SQLITE_C_INT
    Dim local4(0 To 999) As Byte
    Dim c2fb_temp_2 As u8 Ptr
    Dim c2fb_temp_3 As UByte
    Static local5(0 To 2) As Const ZString Ptr = {Cast(Const ZString Ptr, StrPtr(!",MAT")), Cast(Const ZString Ptr, StrPtr(!"")), Cast(Const ZString Ptr, StrPtr(!",NO-MAT"))}
    Dim c2fb_temp_4 As ZString Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SqliteTreeView Ptr
    Dim c2fb_temp_12 As SqliteIdList Ptr
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As Const ZString Ptr
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SqliteTreeView Ptr
    Dim c2fb_temp_18 As Const ZString Ptr
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim local6 As SqliteTable Ptr

    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((local0 < arg1->nSrc))))
        local1 = CPtr(SqliteSrcItem Ptr, @(arg1->a(local0)))
        ' C automatic storage declaration
        local3 = Cast(SQLITE_C_INT, &O0ULL)
        ' C automatic array storage
        sqlite3StrAccumInit(CPtr(sqlite3_str Ptr, @(local2)), Cast(SQLITE_C_INT, &O0ULL), CPtr(ZString Ptr, CPtr(Byte Ptr, (@local4(0)))), Cast(SQLITE_SIZE_T, (1000ULL * SizeOf(Byte))), Cast(SQLITE_C_INT, &O0ULL))
        c2fb_temp_2 = CPtr(u8 Ptr, @(local2.printfFlags))
        c2fb_temp_3 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_2))) Or Cast(SQLITE_C_INT, &H01ULL))))
        (*c2fb_temp_2) = Cast(u8, c2fb_temp_3)
        c2fb_temp_3 = Cast(UByte, (*c2fb_temp_2))
        sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local2)), StrPtr(!"{%d:*} %!S"), local1->iCursor, local1)
        If local1->pSTab Then
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local2)), StrPtr(!" tab=%Q nCol=%d ptr=%p used=%llx%s"), local1->pSTab->zName, local1->pSTab->nCol, local1->pSTab, local1->colUsed, IIf(Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 15) And Cast(SQLITE_C_UINT, &H1ULL))), StrPtr(!"+rowid"), StrPtr(!"")))
        End If
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H10ULL))))))) = (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H10ULL)))))))) Then
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local2)), StrPtr(!" FULL-OUTER-JOIN"))
        Else
            If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->fg.jointype) And Cast(SQLITE_C_INT, &H08ULL))) Then
                sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local2)), StrPtr(!" LEFT-JOIN"))
            Else
                If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->fg.jointype) And Cast(SQLITE_C_INT, &H10ULL))) Then
                    sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local2)), StrPtr(!" RIGHT-JOIN"))
                Else
                    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->fg.jointype) And Cast(SQLITE_C_INT, &H02ULL))) Then
                        sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local2)), StrPtr(!" CROSS-JOIN"))
                    End If
                End If
            End If
        End If
        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->fg.jointype) And Cast(SQLITE_C_INT, &H40ULL))) Then
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local2)), StrPtr(!" LTORJ"))
        End If
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 8) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local2)), StrPtr(!" DDL"))
        End If
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 9) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            ' C static array storage
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local2)), StrPtr(!" CteUse=%d%s"), local1->u2.pCteUse->nUse, local5(local1->u2.pCteUse->eM10d))
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 12) And Cast(SQLITE_C_UINT, &H1ULL))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 11) And Cast(SQLITE_C_UINT, &H1ULL))) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local1->u3.pOn <> Cast(SQLITE_C_INT, &O0ULL)))))))))))))) Then
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local2)), StrPtr(!" isOn"))
        End If
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 3) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local2)), StrPtr(!" isTabFunc"))
        End If
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 4) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local2)), StrPtr(!" isCorrelated"))
        End If
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 5) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local2)), StrPtr(!" isMaterialized"))
        End If
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 6) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local2)), StrPtr(!" viaCoroutine"))
        End If
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 10) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local2)), StrPtr(!" notCte"))
        End If
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 14) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local2)), StrPtr(!" isNestedFrom"))
        End If
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 16) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local2)), StrPtr(!" fixedSchema"))
        End If
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 17) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local2)), StrPtr(!" hadSchema"))
        End If
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local2)), StrPtr(!" isSubquery"))
        End If
        c2fb_temp_4 = CPtr(ZString Ptr, sqlite3StrAccumFinish(CPtr(sqlite3_str Ptr, @(local2))))
        sqlite3TreeViewItem(arg0, CPtr(Const ZString Ptr, CPtr(Byte Ptr, (@local4(0)))), (-Cast(SQLITE_C_INT, ((local0 < Cast(SQLITE_C_INT, (arg1->nSrc - Cast(SQLITE_C_INT, 1ULL))))))))
        c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local3 = c2fb_temp_5
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            c2fb_temp_6 = local3
            local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 + 1)))
        End If
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 3) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            c2fb_temp_7 = local3
            local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_7 + 1)))
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 11) And Cast(SQLITE_C_UINT, &H1ULL))) OrElse (-Cast(SQLITE_C_INT, ((local1->u3.pOn <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            c2fb_temp_8 = local3
            local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_8 + 1)))
        End If
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 11) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            c2fb_temp_11 = arg0
            c2fb_temp_12 = local1->u3.pUsing
            c2fb_temp_9 = local3
            local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_9 - 1)))
            c2fb_temp_10 = local3
            c2fb_temp_13 = (-Cast(SQLITE_C_INT, (((c2fb_temp_10) > Cast(SQLITE_C_INT, &O0ULL)))))
            c2fb_temp_14 = StrPtr(!"USING")
            sqlite3TreeViewIdList(c2fb_temp_11, CPtr(Const SqliteIdList Ptr, c2fb_temp_12), c2fb_temp_13, c2fb_temp_14)
        Else
            If (-Cast(SQLITE_C_INT, ((local1->u3.pOn <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_17 = arg0
                c2fb_temp_18 = StrPtr(!"ON")
                c2fb_temp_15 = local3
                local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_15 - 1)))
                c2fb_temp_16 = local3
                c2fb_temp_19 = (-Cast(SQLITE_C_INT, (((c2fb_temp_16) > Cast(SQLITE_C_INT, &O0ULL)))))
                sqlite3TreeViewItem(c2fb_temp_17, c2fb_temp_18, c2fb_temp_19)
                sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, local1->u3.pOn), Cast(SQLITE_C_INT, &O0ULL))
                sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
            End If
        End If
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            ' C unused-parameter annotation
            sqlite3TreeViewAssert(local3 = 1, StrPtr("n == 1"))
            If local1->pSTab Then
                local6 = local1->pSTab
                sqlite3TreeViewColumnList(arg0, CPtr(Const SqliteColumn Ptr, local6->aCol), local6->nCol, Cast(SQLITE_C_INT, 1ULL))
            End If
            ' C unused-parameter annotation
            If local1->u4.pSubq = 0 Then
                sqlite3DebugAssert(StrPtr("subquery SrcItem has pSubq"))
            ElseIf local1->u4.pSubq->pSelect = 0 Then
                sqlite3DebugAssert(StrPtr("subquery record has pSelect"))
            Else
                Dim isNestedFrom As SQLITE_C_INT = CInt( _
                    (local1->u4.pSubq->pSelect->selFlags And SF_NestedFrom) <> 0)
                Dim nestedFromFlag As SQLITE_C_INT = CInt( _
                    (local1->fg.flags And SRCITEM_IS_NESTED_FROM) <> 0)
                sqlite3TreeViewAssert( _
                    nestedFromFlag = isNestedFrom, _
                    StrPtr("pItem->fg.isNestedFrom == IsNestedFrom(pItem)"))
                sqlite3TreeViewSelect(arg0, CPtr(Const SqliteSelect Ptr, local1->u4.pSubq->pSelect), Cast(SQLITE_C_INT, &O0ULL))
            End If
        End If
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 3) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            sqlite3TreeViewExprList(arg0, CPtr(Const SqliteExprList Ptr, local1->u1.pFuncArg), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"func-args:"))
        End If
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
    c2fb_flow_1:
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    Wend
    c2fb_flow_0:
End Sub


Sub sqlite3TreeViewExpr CDecl Alias "sqlite3TreeViewExpr" (ByVal arg0 As SqliteTreeView Ptr, ByVal arg1 As Const SqliteExpr Ptr, ByVal arg2 As UByte)
    Dim local0 As Const ZString Ptr
    Dim local1 As Const ZString Ptr
    Dim local2(0 To 199) As Byte
    Dim local3 As sqlite3_str
    Dim c2fb_temp_0 As ZString Ptr
    Dim c2fb_temp_1 As Byte Ptr
    Dim c2fb_temp_2 As Byte
    Dim local4(0 To 15) As Byte
    Dim c2fb_temp_3 As ZString Ptr
    Dim c2fb_temp_4 As Byte Ptr
    Dim c2fb_temp_5 As Byte
    Dim c2fb_temp_6 As Const ZString Ptr
    Dim c2fb_temp_7 As Const ZString Ptr
    Dim c2fb_temp_8 As Const ZString Ptr
    Dim c2fb_temp_9 As Const ZString Ptr
    Dim c2fb_temp_10 As Const ZString Ptr
    Dim c2fb_temp_11 As Const ZString Ptr
    Dim c2fb_temp_12 As Const ZString Ptr
    Dim c2fb_temp_13 As Const ZString Ptr
    Dim c2fb_temp_14 As Const ZString Ptr
    Dim c2fb_temp_15 As Const ZString Ptr
    Dim c2fb_temp_16 As Const ZString Ptr
    Dim c2fb_temp_17 As Const ZString Ptr
    Dim c2fb_temp_18 As Const ZString Ptr
    Dim c2fb_temp_19 As Const ZString Ptr
    Dim c2fb_temp_20 As Const ZString Ptr
    Dim c2fb_temp_21 As Const ZString Ptr
    Dim c2fb_temp_22 As Const ZString Ptr
    Dim c2fb_temp_23 As Const ZString Ptr
    Dim c2fb_temp_24 As Const ZString Ptr
    Dim c2fb_temp_25 As Const ZString Ptr
    Dim c2fb_temp_26 As Const ZString Ptr
    Dim c2fb_temp_27 As Const ZString Ptr
    Dim c2fb_temp_28 As Const ZString Ptr
    Dim c2fb_temp_29 As Const ZString Ptr
    Dim c2fb_temp_30 As Const ZString Ptr
    Dim c2fb_temp_31 As Const ZString Ptr
    Dim c2fb_temp_32 As Const ZString Ptr
    Dim c2fb_temp_33 As Const ZString Ptr
    Dim local5 As SQLITE_C_INT
    Dim local6(0 To 3) As Const ZString Ptr
    Dim c2fb_temp_34 As SQLITE_C_INT
    Dim c2fb_temp_35 As Const ZString Ptr
    Dim local7 As SqliteExprList Ptr
    Dim local8 As SqliteWalkerWindow Ptr
    Dim c2fb_temp_36 As SqliteExprList Ptr
    Dim c2fb_temp_37 As SqliteWalkerWindow Ptr
    Dim c2fb_temp_38 As SqliteExprList Ptr
    Dim c2fb_temp_39 As SqliteWalkerWindow Ptr
    Dim local9 As Const ZString Ptr
    Dim local10(0 To 7) As Byte
    Dim c2fb_temp_40 As ZString Ptr
    Dim c2fb_temp_41 As Const ZString Ptr
    Dim c2fb_temp_42 As Const ZString Ptr
    Dim c2fb_temp_43 As Const ZString Ptr
    Dim c2fb_temp_44 As Const ZString Ptr
    Dim c2fb_temp_45 As Const ZString Ptr
    Dim local11 As SqliteExpr Ptr
    Dim local12 As sqlite3_str Ptr
    Dim local13 As ZString Ptr
    Dim c2fb_temp_46 As ZString Ptr
    Dim local14 As Const SqliteExpr Ptr
    Dim local15 As Const SqliteExpr Ptr
    Dim local16 As Const SqliteExpr Ptr
    Dim c2fb_temp_47 As Const SqliteExpr Ptr
    Dim c2fb_temp_48 As Const SqliteExpr Ptr
    Dim c2fb_temp_49 As Const SqliteExpr Ptr
    Dim local17 As Const ZString Ptr
    Dim c2fb_temp_50 As Const ZString Ptr
    Dim c2fb_temp_51 As Const ZString Ptr
    Dim c2fb_temp_52 As Const ZString Ptr
    Dim c2fb_temp_53 As Const ZString Ptr
    Dim local18 As ZString Ptr
    Dim local19 As SqliteExpr
    Dim c2fb_temp_54 As SqliteExpr
    Dim c2fb_temp_55 As u8 Ptr
    Dim c2fb_temp_56 As UByte

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic array storage
    sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(arg0)), arg2)
    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3TreeViewLine(arg0, StrPtr(!"nil"))
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
        Return
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg1->flags OrElse Cast(SQLITE_C_UINT, arg1->affExpr))))) OrElse Cast(SQLITE_C_INT, arg1->vvaFlags))))) OrElse CPtr(SqliteAggInfo Ptr, arg1->pAggInfo))))) Then
        ' C automatic storage declaration
        sqlite3StrAccumInit(CPtr(sqlite3_str Ptr, @(local3)), Cast(SQLITE_C_INT, &O0ULL), CPtr(ZString Ptr, CPtr(Byte Ptr, (@local2(0)))), Cast(SQLITE_SIZE_T, (200ULL * SizeOf(Byte))), Cast(SQLITE_C_INT, &O0ULL))
        sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local3)), StrPtr(!" fg.af=%x.%c"), arg1->flags, IIf(arg1->affExpr, Cast(SQLITE_C_INT, arg1->affExpr), Cast(SQLITE_C_INT, 110)))
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000001ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local3)), StrPtr(!" outer.iJoin=%d"), arg1->w.iJoin)
        End If
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000002ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local3)), StrPtr(!" inner.iJoin=%d"), arg1->w.iJoin)
        End If
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H40000000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local3)), StrPtr(!" DDL"))
        End If
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (arg1)->vvaFlags) And (Cast(SQLITE_C_INT, &H02ULL))))) <> Cast(SQLITE_C_INT, &O0ULL)))))) Then
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local3)), StrPtr(!" IMMUTABLE"))
        End If
        If (-Cast(SQLITE_C_INT, ((CPtr(SqliteAggInfo Ptr, arg1->pAggInfo) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            sqlite3_str_appendf(CPtr(sqlite3_str Ptr, @(local3)), StrPtr(!" agg-column[%d]"), arg1->iAgg)
        End If
        c2fb_temp_0 = CPtr(ZString Ptr, sqlite3StrAccumFinish(CPtr(sqlite3_str Ptr, @(local3))))
    Else
        c2fb_temp_1 = CPtr(Byte Ptr, @(local2(Cast(SQLITE_C_INT, &O0ULL))))
        c2fb_temp_2 = Cast(Byte, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_1) = c2fb_temp_2
    End If
    sqlite3TreeViewCheckExprAssertions(arg1)
    Select Case arg1->op
        Case Cast(SQLITE_C_INT, 170ULL)
            sqlite3TreeViewLine(arg0, StrPtr(!"AGG{%d:%d}%s"), arg1->iTable, arg1->iColumn, CPtr(Byte Ptr, (@local2(0))))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 168ULL)
            If (-Cast(SQLITE_C_INT, ((arg1->iTable < Cast(SQLITE_C_INT, &O0ULL))))) Then
                ' C automatic array storage
                If arg1->op2 Then
                    c2fb_temp_3 = CPtr(ZString Ptr, sqlite3_snprintf(Cast(SQLITE_SIZE_T, (16ULL * SizeOf(Byte))), CPtr(ZString Ptr, CPtr(Byte Ptr, (@local4(0)))), StrPtr(!" op2=0x%02x"), arg1->op2))
                Else
                    c2fb_temp_4 = CPtr(Byte Ptr, @(local4(Cast(SQLITE_C_INT, &O0ULL))))
                    c2fb_temp_5 = Cast(Byte, Cast(SQLITE_C_INT, &O0ULL))
                    (*c2fb_temp_4) = c2fb_temp_5
                End If
                sqlite3TreeViewLine(arg0, StrPtr(!"COLUMN(%d)%s%s"), arg1->iColumn, CPtr(Byte Ptr, (@local2(0))), CPtr(Byte Ptr, (@local4(0))))
            Else
                ' C unused-parameter annotation
                sqlite3TreeViewLine(arg0, StrPtr(!"{%d:%d} pTab=%p%s"), arg1->iTable, arg1->iColumn, CPtr(SqliteTable Ptr, arg1->y.pTab), CPtr(Byte Ptr, (@local2(0))))
            End If
            If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000020ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, arg1->pLeft), Cast(SQLITE_C_INT, &O0ULL))
            End If
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 156ULL)
            If Cast(SQLITE_C_UINT, (arg1->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H000800ULL)))) Then
                sqlite3TreeViewLine(arg0, StrPtr(!"%d"), arg1->u.iValue)
            Else
                sqlite3TreeViewLine(arg0, StrPtr(!"%s"), CPtr(ZString Ptr, arg1->u.zToken))
            End If
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 154ULL)
            ' C unused-parameter annotation
            sqlite3TreeViewLine(arg0, StrPtr(!"%s"), CPtr(ZString Ptr, arg1->u.zToken))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 118ULL)
            ' C unused-parameter annotation
            sqlite3TreeViewLine(arg0, StrPtr(!"%Q"), CPtr(ZString Ptr, arg1->u.zToken))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 122ULL)
            sqlite3TreeViewLine(arg0, StrPtr(!"NULL"))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 171ULL)
            sqlite3TreeViewLine(arg0, StrPtr(!"%s%s"), IIf(sqlite3ExprTruthValue(arg1), StrPtr(!"TRUE"), StrPtr(!"FALSE")), CPtr(Byte Ptr, (@local2(0))))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 155ULL)
            ' C unused-parameter annotation
            sqlite3TreeViewLine(arg0, StrPtr(!"%s"), CPtr(ZString Ptr, arg1->u.zToken))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 157ULL)
            ' C unused-parameter annotation
            sqlite3TreeViewLine(arg0, StrPtr(!"VARIABLE(%s,%d)"), CPtr(ZString Ptr, arg1->u.zToken), arg1->iColumn)
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 176ULL)
            sqlite3TreeViewLine(arg0, StrPtr(!"REGISTER(%d)"), arg1->iTable)
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 60ULL)
            ' C unused-parameter annotation
            sqlite3TreeViewLine(arg0, StrPtr(!"ID \034%w\034"), CPtr(ZString Ptr, arg1->u.zToken))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 180ULL)
            sqlite3TreeViewLine(arg0, StrPtr(!"ASKTERISK"))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 36ULL)
            ' C unused-parameter annotation
            sqlite3TreeViewLine(arg0, StrPtr(!"CAST %Q"), CPtr(ZString Ptr, arg1->u.zToken))
            sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, arg1->pLeft), Cast(SQLITE_C_INT, &O0ULL))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 57ULL)
            c2fb_temp_6 = StrPtr(!"LT")
            local0 = c2fb_temp_6
        Case Cast(SQLITE_C_INT, 56ULL)
            c2fb_temp_7 = StrPtr(!"LE")
            local0 = c2fb_temp_7
        Case Cast(SQLITE_C_INT, 55ULL)
            c2fb_temp_8 = StrPtr(!"GT")
            local0 = c2fb_temp_8
        Case Cast(SQLITE_C_INT, 58ULL)
            c2fb_temp_9 = StrPtr(!"GE")
            local0 = c2fb_temp_9
        Case Cast(SQLITE_C_INT, 53ULL)
            c2fb_temp_10 = StrPtr(!"NE")
            local0 = c2fb_temp_10
        Case Cast(SQLITE_C_INT, 54ULL)
            c2fb_temp_11 = StrPtr(!"EQ")
            local0 = c2fb_temp_11
        Case Cast(SQLITE_C_INT, 45ULL)
            c2fb_temp_12 = StrPtr(!"IS")
            local0 = c2fb_temp_12
        Case Cast(SQLITE_C_INT, 46ULL)
            c2fb_temp_13 = StrPtr(!"ISNOT")
            local0 = c2fb_temp_13
        Case Cast(SQLITE_C_INT, 44ULL)
            c2fb_temp_14 = StrPtr(!"AND")
            local0 = c2fb_temp_14
        Case Cast(SQLITE_C_INT, 43ULL)
            c2fb_temp_15 = StrPtr(!"OR")
            local0 = c2fb_temp_15
        Case Cast(SQLITE_C_INT, 107ULL)
            c2fb_temp_16 = StrPtr(!"ADD")
            local0 = c2fb_temp_16
        Case Cast(SQLITE_C_INT, 109ULL)
            c2fb_temp_17 = StrPtr(!"MUL")
            local0 = c2fb_temp_17
        Case Cast(SQLITE_C_INT, 108ULL)
            c2fb_temp_18 = StrPtr(!"SUB")
            local0 = c2fb_temp_18
        Case Cast(SQLITE_C_INT, 111ULL)
            c2fb_temp_19 = StrPtr(!"REM")
            local0 = c2fb_temp_19
        Case Cast(SQLITE_C_INT, 103ULL)
            c2fb_temp_20 = StrPtr(!"BITAND")
            local0 = c2fb_temp_20
        Case Cast(SQLITE_C_INT, 104ULL)
            c2fb_temp_21 = StrPtr(!"BITOR")
            local0 = c2fb_temp_21
        Case Cast(SQLITE_C_INT, 110ULL)
            c2fb_temp_22 = StrPtr(!"DIV")
            local0 = c2fb_temp_22
        Case Cast(SQLITE_C_INT, 105ULL)
            c2fb_temp_23 = StrPtr(!"LSHIFT")
            local0 = c2fb_temp_23
        Case Cast(SQLITE_C_INT, 106ULL)
            c2fb_temp_24 = StrPtr(!"RSHIFT")
            local0 = c2fb_temp_24
        Case Cast(SQLITE_C_INT, 112ULL)
            c2fb_temp_25 = StrPtr(!"CONCAT")
            local0 = c2fb_temp_25
        Case Cast(SQLITE_C_INT, 142ULL)
            c2fb_temp_26 = StrPtr(!"DOT")
            local0 = c2fb_temp_26
        Case Cast(SQLITE_C_INT, 149ULL)
            c2fb_temp_27 = StrPtr(!"LIMIT")
            local0 = c2fb_temp_27
        Case Cast(SQLITE_C_INT, 174ULL)
            c2fb_temp_28 = StrPtr(!"UMINUS")
            local1 = c2fb_temp_28
        Case Cast(SQLITE_C_INT, 173ULL)
            c2fb_temp_29 = StrPtr(!"UPLUS")
            local1 = c2fb_temp_29
        Case Cast(SQLITE_C_INT, 115ULL)
            c2fb_temp_30 = StrPtr(!"BITNOT")
            local1 = c2fb_temp_30
        Case Cast(SQLITE_C_INT, 19ULL)
            c2fb_temp_31 = StrPtr(!"NOT")
            local1 = c2fb_temp_31
        Case Cast(SQLITE_C_INT, 51ULL)
            c2fb_temp_32 = StrPtr(!"ISNULL")
            local1 = c2fb_temp_32
        Case Cast(SQLITE_C_INT, 52ULL)
            c2fb_temp_33 = StrPtr(!"NOTNULL")
            local1 = c2fb_temp_33
        Case Cast(SQLITE_C_INT, 175ULL)
            ' C automatic storage declaration
            Erase local6
            local6(0) = StrPtr(!"IS-FALSE")
            local6(1) = StrPtr(!"IS-TRUE")
            local6(2) = StrPtr(!"IS-NOT-FALSE")
            local6(3) = StrPtr(!"IS-NOT-TRUE")
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_34 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op2) = Cast(SQLITE_C_INT, 46ULL)))))) * Cast(SQLITE_C_INT, 2ULL))) + sqlite3ExprTruthValue(CPtr(Const SqliteExpr Ptr, arg1->pRight)))))
            local5 = c2fb_temp_34
            c2fb_temp_35 = local6(local5)
            local1 = c2fb_temp_35
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 181ULL)
            ' C unused-parameter annotation
            sqlite3TreeViewLine(arg0, StrPtr(!"SPAN %Q"), CPtr(ZString Ptr, arg1->u.zToken))
            sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, arg1->pLeft), Cast(SQLITE_C_INT, &O0ULL))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 114ULL)
            ' C unused-parameter annotation
            sqlite3TreeViewLine(arg0, StrPtr(!"%sCOLLATE %Q%s"), IIf((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000200ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))), StrPtr(!"SOFT-"), StrPtr(!"")), CPtr(ZString Ptr, arg1->u.zToken), CPtr(Byte Ptr, (@local2(0))))
            sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, arg1->pLeft), Cast(SQLITE_C_INT, &O0ULL))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 169ULL), Cast(SQLITE_C_INT, 172ULL)
            ' C automatic storage declaration
            ' C automatic storage declaration
            If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H010000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                c2fb_temp_36 = CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                local7 = c2fb_temp_36
                c2fb_temp_37 = CPtr(SqliteWalkerWindow Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                local8 = c2fb_temp_37
            Else
                ' C unused-parameter annotation
                c2fb_temp_38 = arg1->x.pList
                local7 = c2fb_temp_38
                c2fb_temp_39 = IIf(((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (((arg1))->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H1000000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(SqliteWalkerWindow Ptr, arg1->y.pWin)->eFrmType) <> Cast(SQLITE_C_INT, 167ULL)))))))))), CPtr(SqliteWalkerWindow Ptr, arg1->y.pWin), CPtr(SqliteWalkerWindow Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
                local8 = c2fb_temp_39
            End If
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 169ULL))))) Then
                sqlite3TreeViewLine(arg0, StrPtr(!"AGG_FUNCTION%d %Q%s agg=%d[%d]/%p"), arg1->op2, CPtr(ZString Ptr, arg1->u.zToken), CPtr(Byte Ptr, (@local2(0))), IIf(CPtr(SqliteAggInfo Ptr, arg1->pAggInfo), CPtr(SqliteAggInfo Ptr, arg1->pAggInfo)->selId, Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))), arg1->iAgg, CPtr(SqliteAggInfo Ptr, arg1->pAggInfo))
            Else
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op2) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                    ' C automatic storage declaration
                    ' C automatic array storage
                    c2fb_temp_40 = CPtr(ZString Ptr, sqlite3_snprintf(Cast(SQLITE_SIZE_T, (8ULL * SizeOf(Byte))), CPtr(ZString Ptr, CPtr(Byte Ptr, (@local10(0)))), StrPtr(!"0x%02x"), arg1->op2))
                    c2fb_temp_41 = CPtr(Const ZString Ptr, CPtr(Byte Ptr, (@local10(0))))
                    local9 = c2fb_temp_41
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op2) = Cast(SQLITE_C_INT, &H000004ULL))))) Then
                        c2fb_temp_42 = StrPtr(!"NC_IsCheck")
                        local9 = c2fb_temp_42
                    End If
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op2) = Cast(SQLITE_C_INT, &H000020ULL))))) Then
                        c2fb_temp_43 = StrPtr(!"NC_IdxExpr")
                        local9 = c2fb_temp_43
                    End If
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op2) = Cast(SQLITE_C_INT, &H000002ULL))))) Then
                        c2fb_temp_44 = StrPtr(!"NC_PartIdx")
                        local9 = c2fb_temp_44
                    End If
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op2) = Cast(SQLITE_C_INT, &H000008ULL))))) Then
                        c2fb_temp_45 = StrPtr(!"NC_GenCol")
                        local9 = c2fb_temp_45
                    End If
                    sqlite3TreeViewLine(arg0, StrPtr(!"FUNCTION %Q%s op2=%s"), CPtr(ZString Ptr, arg1->u.zToken), CPtr(Byte Ptr, (@local2(0))), local9)
                Else
                    sqlite3TreeViewLine(arg0, StrPtr(!"FUNCTION %Q%s"), CPtr(ZString Ptr, arg1->u.zToken), CPtr(Byte Ptr, (@local2(0))))
                End If
            End If
            If local7 Then
                sqlite3TreeViewExprList(arg0, CPtr(Const SqliteExprList Ptr, local7), (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local8 <> Cast(SQLITE_C_INT, &O0ULL))))) OrElse arg1->pLeft)))), Cast(SQLITE_C_INT, &O0ULL))
                If arg1->pLeft Then
                    local11 = arg1->pLeft
                    ' C unused-parameter annotation
                    ' C unused-parameter annotation
                    sqlite3TreeViewExprList(arg0, CPtr(Const SqliteExprList Ptr, local11->x.pList), (-Cast(SQLITE_C_INT, ((local8 <> Cast(SQLITE_C_INT, &O0ULL))))), StrPtr(!"ORDERBY"))
                End If
            End If
            If local8 Then
                sqlite3TreeViewWindow(arg0, CPtr(Const SqliteWalkerWindow Ptr, local8), Cast(SQLITE_C_INT, &O0ULL))
            End If
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 146ULL)
            sqlite3TreeViewExprList(arg0, CPtr(Const SqliteExprList Ptr, arg1->x.pList), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"ORDERBY"))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 20ULL)
            ' C unused-parameter annotation
            sqlite3TreeViewLine(arg0, StrPtr(!"EXISTS-expr flags=0x%x"), arg1->flags)
            sqlite3TreeViewSelect(arg0, CPtr(Const SqliteSelect Ptr, arg1->x.pSelect), Cast(SQLITE_C_INT, &O0ULL))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 139ULL)
            ' C unused-parameter annotation
            sqlite3TreeViewLine(arg0, StrPtr(!"subquery-expr flags=0x%x"), arg1->flags)
            sqlite3TreeViewSelect(arg0, CPtr(Const SqliteSelect Ptr, arg1->x.pSelect), Cast(SQLITE_C_INT, &O0ULL))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 50ULL)
            local12 = CPtr(sqlite3_str Ptr, sqlite3_str_new(Cast(SQLITE_C_INT, &O0ULL)))
            ' C automatic storage declaration
            sqlite3_str_appendf(local12, StrPtr(!"IN flags=0x%x"), arg1->flags)
            If arg1->iTable Then
                sqlite3_str_appendf(local12, StrPtr(!" iTable=%d"), arg1->iTable)
            End If
            If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H2000000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                sqlite3_str_appendf(local12, StrPtr(!" subrtn(%d,%d)"), arg1->y.sub.regReturn, arg1->y.sub.iAddr)
            End If
            c2fb_temp_46 = CPtr(ZString Ptr, sqlite3_str_finish(local12))
            local13 = c2fb_temp_46
            sqlite3TreeViewLine(arg0, CPtr(Const ZString Ptr, local13))
            sqlite3_free(CPtr(Any Ptr, local13))
            sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, arg1->pLeft), Cast(SQLITE_C_INT, 1ULL))
            If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                sqlite3TreeViewSelect(arg0, CPtr(Const SqliteSelect Ptr, arg1->x.pSelect), Cast(SQLITE_C_INT, &O0ULL))
            Else
                sqlite3TreeViewExprList(arg0, CPtr(Const SqliteExprList Ptr, arg1->x.pList), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL))
            End If
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 49ULL)
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            c2fb_temp_47 = CPtr(Const SqliteExpr Ptr, arg1->pLeft)
            local14 = c2fb_temp_47
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_48 = CPtr(Const SqliteExpr Ptr, arg1->x.pList->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr)
            local15 = c2fb_temp_48
            c2fb_temp_49 = CPtr(Const SqliteExpr Ptr, arg1->x.pList->a(Cast(SQLITE_C_INT, 1ULL)).pExpr)
            local16 = c2fb_temp_49
            sqlite3TreeViewLine(arg0, StrPtr(!"BETWEEN%s"), CPtr(Byte Ptr, (@local2(0))))
            sqlite3TreeViewExpr(arg0, local14, Cast(SQLITE_C_INT, 1ULL))
            sqlite3TreeViewExpr(arg0, local15, Cast(SQLITE_C_INT, 1ULL))
            sqlite3TreeViewExpr(arg0, local16, Cast(SQLITE_C_INT, &O0ULL))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 78ULL)
            sqlite3TreeViewLine(arg0, StrPtr(!"%s(%d)"), IIf(arg1->iTable, StrPtr(!"NEW"), StrPtr(!"OLD")), arg1->iColumn)
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 158ULL)
            sqlite3TreeViewLine(arg0, StrPtr(!"CASE"))
            sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, arg1->pLeft), Cast(SQLITE_C_INT, 1ULL))
            ' C unused-parameter annotation
            sqlite3TreeViewExprList(arg0, CPtr(Const SqliteExprList Ptr, arg1->x.pList), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 72ULL)
            local17 = StrPtr(!"unk")
            Select Case arg1->affExpr
                Case Cast(SQLITE_C_INT, 1ULL)
                    c2fb_temp_50 = StrPtr(!"rollback")
                    local17 = c2fb_temp_50
                Case Cast(SQLITE_C_INT, 2ULL)
                    c2fb_temp_51 = StrPtr(!"abort")
                    local17 = c2fb_temp_51
                Case Cast(SQLITE_C_INT, 3ULL)
                    c2fb_temp_52 = StrPtr(!"fail")
                    local17 = c2fb_temp_52
                Case Cast(SQLITE_C_INT, 4ULL)
                    c2fb_temp_53 = StrPtr(!"ignore")
                    local17 = c2fb_temp_53
            End Select
            c2fb_flow_1:
            ' C unused-parameter annotation
            sqlite3TreeViewLine(arg0, StrPtr(!"RAISE %s"), local17)
            sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, arg1->pLeft), Cast(SQLITE_C_INT, &O0ULL))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 47ULL)
            sqlite3TreeViewLine(arg0, StrPtr(!"MATCH {%d:%d}%s"), arg1->iTable, arg1->iColumn, CPtr(Byte Ptr, (@local2(0))))
            sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, arg1->pRight), Cast(SQLITE_C_INT, &O0ULL))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 177ULL)
            local18 = CPtr(ZString Ptr, sqlite3_mprintf(StrPtr(!"VECTOR%s"), CPtr(Byte Ptr, (@local2(0)))))
            ' C unused-parameter annotation
            sqlite3TreeViewBareExprList(arg0, CPtr(Const SqliteExprList Ptr, arg1->x.pList), CPtr(Const ZString Ptr, local18))
            sqlite3_free(CPtr(Any Ptr, local18))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 178ULL)
            sqlite3TreeViewLine(arg0, StrPtr(!"SELECT-COLUMN %d of [0..%d]%s"), arg1->iColumn, Cast(SQLITE_C_INT, (arg1->iTable - Cast(SQLITE_C_INT, 1ULL))), IIf((-Cast(SQLITE_C_INT, ((arg1->pRight = arg1->pLeft)))), StrPtr(!" (SELECT-owner)"), StrPtr(!"")))
            ' C unused-parameter annotation
            sqlite3TreeViewSelect(arg0, CPtr(Const SqliteSelect Ptr, arg1->pLeft->x.pSelect), Cast(SQLITE_C_INT, &O0ULL))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 179ULL)
            sqlite3TreeViewLine(arg0, StrPtr(!"IF-NULL-ROW %d"), arg1->iTable)
            sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, arg1->pLeft), Cast(SQLITE_C_INT, &O0ULL))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 182ULL)
            ' C automatic storage declaration
            sqlite3TreeViewLine(arg0, StrPtr(!"ERROR"))
            c2fb_temp_54 = (*arg1)
            local19 = c2fb_temp_54
            c2fb_temp_55 = CPtr(u8 Ptr, @(local19.op))
            c2fb_temp_56 = Cast(UByte, arg1->op2)
            (*c2fb_temp_55) = Cast(u8, c2fb_temp_56)
            c2fb_temp_56 = Cast(UByte, (*c2fb_temp_55))
            sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, CPtr(SqliteExpr Ptr, @(local19))), Cast(SQLITE_C_INT, &O0ULL))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 76ULL)
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->iColumn) <= Cast(SQLITE_C_INT, &O0ULL))))) Then
                sqlite3TreeViewLine(arg0, StrPtr(!"First FROM table rowid"))
            Else
                sqlite3TreeViewLine(arg0, StrPtr(!"First FROM table column %d"), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->iColumn) - Cast(SQLITE_C_INT, 1ULL))))
            End If
            Goto c2fb_flow_0
        Case Else
            sqlite3TreeViewLine(arg0, StrPtr(!"op=%d"), arg1->op)
            Goto c2fb_flow_0
    End Select
    c2fb_flow_0:
    If local0 Then
        sqlite3TreeViewLine(arg0, StrPtr(!"%s%s"), local0, CPtr(Byte Ptr, (@local2(0))))
        sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, arg1->pLeft), Cast(SQLITE_C_INT, 1ULL))
        sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, arg1->pRight), Cast(SQLITE_C_INT, &O0ULL))
    Else
        If local1 Then
            sqlite3TreeViewLine(arg0, StrPtr(!"%s%s"), local1, CPtr(Byte Ptr, (@local2(0))))
            sqlite3TreeViewExpr(arg0, CPtr(Const SqliteExpr Ptr, arg1->pLeft), Cast(SQLITE_C_INT, &O0ULL))
        End If
    End If
    sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(arg0)))
End Sub


#if defined(SQLITE_TEST) OrElse defined(SQLITE_ENABLE_SELECTTRACE) OrElse defined(SQLITE_ENABLE_TREETRACE)
/' DML renderers are enabled only for TreeView trace builds. '/
Sub sqlite3TreeViewDelete CDecl Alias "sqlite3TreeViewDelete" (ByVal arg0 As Const SqliteWithRecord Ptr, ByVal arg1 As Const SqliteSrcList Ptr, ByVal arg2 As Const SqliteExpr Ptr, ByVal arg3 As Const SqliteExprList Ptr, ByVal arg4 As Const SqliteExpr Ptr, ByVal arg5 As Const SqliteTrigger Ptr)
    Dim local0 As SQLITE_C_INT
    Dim local1 As SqliteTreeView Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SqliteTreeView Ptr Ptr
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SqliteTreeView Ptr Ptr
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SqliteTreeView Ptr Ptr
    Dim c2fb_temp_17 As SQLITE_C_INT
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim c2fb_temp_20 As SqliteTreeView Ptr
    Dim c2fb_temp_21 As Const SqliteExprList Ptr
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim c2fb_temp_23 As Const ZString Ptr
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As SQLITE_C_INT
    Dim c2fb_temp_26 As SqliteTreeView Ptr Ptr
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim c2fb_temp_28 As SQLITE_C_INT
    Dim c2fb_temp_29 As SQLITE_C_INT
    Dim c2fb_temp_30 As SqliteTreeView Ptr
    Dim c2fb_temp_31 As Const SqliteTrigger Ptr
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(local1)), Cast(SQLITE_C_INT, &O0ULL))
    sqlite3TreeViewLine(local1, StrPtr(!"DELETE"))
    If arg0 Then
        c2fb_temp_0 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_0 + 1)))
    End If
    If arg1 Then
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    End If
    If arg2 Then
        c2fb_temp_2 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_2 + 1)))
    End If
    If arg3 Then
        c2fb_temp_3 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_3 + 1)))
    End If
    If arg4 Then
        c2fb_temp_4 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_4 + 1)))
    End If
    If arg5 Then
        c2fb_temp_5 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_5 + 1)))
    End If
    If arg0 Then
        c2fb_temp_8 = CPtr(SqliteTreeView Ptr Ptr, @(local1))
        c2fb_temp_6 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 - 1)))
        c2fb_temp_7 = local0
        c2fb_temp_9 = (-Cast(SQLITE_C_INT, (((c2fb_temp_7) > Cast(SQLITE_C_INT, &O0ULL)))))
        sqlite3TreeViewPush(c2fb_temp_8, c2fb_temp_9)
        sqlite3TreeViewWith(local1, arg0, Cast(SQLITE_C_INT, &O0ULL))
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(local1)))
    End If
    If arg1 Then
        c2fb_temp_12 = CPtr(SqliteTreeView Ptr Ptr, @(local1))
        c2fb_temp_10 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_10 - 1)))
        c2fb_temp_11 = local0
        c2fb_temp_13 = (-Cast(SQLITE_C_INT, (((c2fb_temp_11) > Cast(SQLITE_C_INT, &O0ULL)))))
        sqlite3TreeViewPush(c2fb_temp_12, c2fb_temp_13)
        sqlite3TreeViewLine(local1, StrPtr(!"FROM"))
        sqlite3TreeViewSrcList(local1, arg1)
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(local1)))
    End If
    If arg2 Then
        c2fb_temp_16 = CPtr(SqliteTreeView Ptr Ptr, @(local1))
        c2fb_temp_14 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_14 - 1)))
        c2fb_temp_15 = local0
        c2fb_temp_17 = (-Cast(SQLITE_C_INT, (((c2fb_temp_15) > Cast(SQLITE_C_INT, &O0ULL)))))
        sqlite3TreeViewPush(c2fb_temp_16, c2fb_temp_17)
        sqlite3TreeViewLine(local1, StrPtr(!"WHERE"))
        sqlite3TreeViewExpr(local1, arg2, Cast(SQLITE_C_INT, &O0ULL))
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(local1)))
    End If
    If arg3 Then
        c2fb_temp_20 = local1
        c2fb_temp_21 = arg3
        c2fb_temp_18 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_18 - 1)))
        c2fb_temp_19 = local0
        c2fb_temp_22 = (-Cast(SQLITE_C_INT, (((c2fb_temp_19) > Cast(SQLITE_C_INT, &O0ULL)))))
        c2fb_temp_23 = StrPtr(!"ORDER-BY")
        sqlite3TreeViewExprList(c2fb_temp_20, c2fb_temp_21, c2fb_temp_22, c2fb_temp_23)
    End If
    If arg4 Then
        c2fb_temp_26 = CPtr(SqliteTreeView Ptr Ptr, @(local1))
        c2fb_temp_24 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_24 - 1)))
        c2fb_temp_25 = local0
        c2fb_temp_27 = (-Cast(SQLITE_C_INT, (((c2fb_temp_25) > Cast(SQLITE_C_INT, &O0ULL)))))
        sqlite3TreeViewPush(c2fb_temp_26, c2fb_temp_27)
        sqlite3TreeViewLine(local1, StrPtr(!"LIMIT"))
        sqlite3TreeViewExpr(local1, arg4, Cast(SQLITE_C_INT, &O0ULL))
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(local1)))
    End If
    If arg5 Then
        c2fb_temp_30 = local1
        c2fb_temp_31 = arg5
        c2fb_temp_28 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_28 - 1)))
        c2fb_temp_29 = local0
        c2fb_temp_32 = (-Cast(SQLITE_C_INT, (((c2fb_temp_29) > Cast(SQLITE_C_INT, &O0ULL)))))
        c2fb_temp_33 = Cast(SQLITE_C_INT, 1ULL)
        sqlite3TreeViewTrigger(c2fb_temp_30, c2fb_temp_31, c2fb_temp_32, c2fb_temp_33)
    End If
    sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(local1)))
End Sub


Sub sqlite3TreeViewInsert CDecl Alias "sqlite3TreeViewInsert" (ByVal arg0 As Const SqliteWithRecord Ptr, ByVal arg1 As Const SqliteSrcList Ptr, ByVal arg2 As Const SqliteIdList Ptr, ByVal arg3 As Const SqliteSelect Ptr, ByVal arg4 As Const SqliteExprList Ptr, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As Const SqliteUpsert Ptr, ByVal arg7 As Const SqliteTrigger Ptr)
    Dim local0 As SqliteTreeView Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As Const ZString Ptr
    Dim c2fb_temp_0 As Const ZString Ptr
    Dim c2fb_temp_1 As Const ZString Ptr
    Dim c2fb_temp_2 As Const ZString Ptr
    Dim c2fb_temp_3 As Const ZString Ptr
    Dim c2fb_temp_4 As Const ZString Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SqliteTreeView Ptr Ptr
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SQLITE_C_INT
    Dim c2fb_temp_18 As SqliteTreeView Ptr Ptr
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As SQLITE_C_INT
    Dim c2fb_temp_22 As SqliteTreeView Ptr
    Dim c2fb_temp_23 As Const SqliteIdList Ptr
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As Const ZString Ptr
    Dim c2fb_temp_26 As SQLITE_C_INT
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim c2fb_temp_28 As SqliteTreeView Ptr Ptr
    Dim c2fb_temp_29 As SQLITE_C_INT
    Dim c2fb_temp_30 As SQLITE_C_INT
    Dim c2fb_temp_31 As SQLITE_C_INT
    Dim c2fb_temp_32 As SqliteTreeView Ptr
    Dim c2fb_temp_33 As Const SqliteExprList Ptr
    Dim c2fb_temp_34 As SQLITE_C_INT
    Dim c2fb_temp_35 As Const ZString Ptr
    Dim c2fb_temp_36 As SQLITE_C_INT
    Dim c2fb_temp_37 As SQLITE_C_INT
    Dim c2fb_temp_38 As SqliteTreeView Ptr Ptr
    Dim c2fb_temp_39 As SQLITE_C_INT
    Dim c2fb_temp_40 As SQLITE_C_INT
    Dim c2fb_temp_41 As SQLITE_C_INT
    Dim c2fb_temp_42 As SqliteTreeView Ptr
    Dim c2fb_temp_43 As Const SqliteTrigger Ptr
    Dim c2fb_temp_44 As SQLITE_C_INT
    Dim c2fb_temp_45 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    local2 = StrPtr(!"INSERT")
    Select Case arg5
        Case Cast(SQLITE_C_INT, 5ULL)
            c2fb_temp_0 = StrPtr(!"REPLACE")
            local2 = c2fb_temp_0
        Case Cast(SQLITE_C_INT, 4ULL)
            c2fb_temp_1 = StrPtr(!"INSERT OR IGNORE")
            local2 = c2fb_temp_1
        Case Cast(SQLITE_C_INT, 1ULL)
            c2fb_temp_2 = StrPtr(!"INSERT OR ROLLBACK")
            local2 = c2fb_temp_2
        Case Cast(SQLITE_C_INT, 2ULL)
            c2fb_temp_3 = StrPtr(!"INSERT OR ABORT")
            local2 = c2fb_temp_3
        Case Cast(SQLITE_C_INT, 3ULL)
            c2fb_temp_4 = StrPtr(!"INSERT OR FAIL")
            local2 = c2fb_temp_4
    End Select
    c2fb_flow_0:
    sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(local0)), Cast(SQLITE_C_INT, &O0ULL))
    sqlite3TreeViewLine(local0, local2)
    If arg0 Then
        c2fb_temp_5 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_5 + 1)))
    End If
    If arg1 Then
        c2fb_temp_6 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 + 1)))
    End If
    If arg2 Then
        c2fb_temp_7 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_7 + 1)))
    End If
    If arg3 Then
        c2fb_temp_8 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_8 + 1)))
    End If
    If arg4 Then
        c2fb_temp_9 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_9 + 1)))
    End If
    If arg6 Then
        c2fb_temp_10 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_10 + 1)))
    End If
    If arg7 Then
        c2fb_temp_11 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_11 + 1)))
    End If
    If arg0 Then
        c2fb_temp_14 = CPtr(SqliteTreeView Ptr Ptr, @(local0))
        c2fb_temp_12 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_12 - 1)))
        c2fb_temp_13 = local1
        c2fb_temp_15 = (-Cast(SQLITE_C_INT, (((c2fb_temp_13) > Cast(SQLITE_C_INT, &O0ULL)))))
        sqlite3TreeViewPush(c2fb_temp_14, c2fb_temp_15)
        sqlite3TreeViewWith(local0, arg0, Cast(SQLITE_C_INT, &O0ULL))
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(local0)))
    End If
    If arg1 Then
        c2fb_temp_18 = CPtr(SqliteTreeView Ptr Ptr, @(local0))
        c2fb_temp_16 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_16 - 1)))
        c2fb_temp_17 = local1
        c2fb_temp_19 = (-Cast(SQLITE_C_INT, (((c2fb_temp_17) > Cast(SQLITE_C_INT, &O0ULL)))))
        sqlite3TreeViewPush(c2fb_temp_18, c2fb_temp_19)
        sqlite3TreeViewLine(local0, StrPtr(!"INTO"))
        sqlite3TreeViewSrcList(local0, arg1)
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(local0)))
    End If
    If arg2 Then
        c2fb_temp_22 = local0
        c2fb_temp_23 = arg2
        c2fb_temp_20 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_20 - 1)))
        c2fb_temp_21 = local1
        c2fb_temp_24 = (-Cast(SQLITE_C_INT, (((c2fb_temp_21) > Cast(SQLITE_C_INT, &O0ULL)))))
        c2fb_temp_25 = StrPtr(!"COLUMNS")
        sqlite3TreeViewIdList(c2fb_temp_22, c2fb_temp_23, c2fb_temp_24, c2fb_temp_25)
    End If
    If arg3 Then
        c2fb_temp_28 = CPtr(SqliteTreeView Ptr Ptr, @(local0))
        c2fb_temp_26 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_26 - 1)))
        c2fb_temp_27 = local1
        c2fb_temp_29 = (-Cast(SQLITE_C_INT, (((c2fb_temp_27) > Cast(SQLITE_C_INT, &O0ULL)))))
        sqlite3TreeViewPush(c2fb_temp_28, c2fb_temp_29)
        sqlite3TreeViewLine(local0, StrPtr(!"DATA-SOURCE"))
        sqlite3TreeViewSelect(local0, arg3, Cast(SQLITE_C_INT, &O0ULL))
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(local0)))
    End If
    If arg4 Then
        c2fb_temp_32 = local0
        c2fb_temp_33 = arg4
        c2fb_temp_30 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_30 - 1)))
        c2fb_temp_31 = local1
        c2fb_temp_34 = (-Cast(SQLITE_C_INT, (((c2fb_temp_31) > Cast(SQLITE_C_INT, &O0ULL)))))
        c2fb_temp_35 = StrPtr(!"VALUES")
        sqlite3TreeViewExprList(c2fb_temp_32, c2fb_temp_33, c2fb_temp_34, c2fb_temp_35)
    End If
    If arg6 Then
        c2fb_temp_38 = CPtr(SqliteTreeView Ptr Ptr, @(local0))
        c2fb_temp_36 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_36 - 1)))
        c2fb_temp_37 = local1
        c2fb_temp_39 = (-Cast(SQLITE_C_INT, (((c2fb_temp_37) > Cast(SQLITE_C_INT, &O0ULL)))))
        sqlite3TreeViewPush(c2fb_temp_38, c2fb_temp_39)
        sqlite3TreeViewLine(local0, StrPtr(!"UPSERT"))
        sqlite3TreeViewUpsert(local0, arg6, Cast(SQLITE_C_INT, &O0ULL))
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(local0)))
    End If
    If arg7 Then
        c2fb_temp_42 = local0
        c2fb_temp_43 = arg7
        c2fb_temp_40 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_40 - 1)))
        c2fb_temp_41 = local1
        c2fb_temp_44 = (-Cast(SQLITE_C_INT, (((c2fb_temp_41) > Cast(SQLITE_C_INT, &O0ULL)))))
        c2fb_temp_45 = Cast(SQLITE_C_INT, 1ULL)
        sqlite3TreeViewTrigger(c2fb_temp_42, c2fb_temp_43, c2fb_temp_44, c2fb_temp_45)
    End If
    sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(local0)))
End Sub


Sub sqlite3TreeViewUpdate CDecl Alias "sqlite3TreeViewUpdate" (ByVal arg0 As Const SqliteWithRecord Ptr, ByVal arg1 As Const SqliteSrcList Ptr, ByVal arg2 As Const SqliteExprList Ptr, ByVal arg3 As Const SqliteExpr Ptr, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As Const SqliteExprList Ptr, ByVal arg6 As Const SqliteExpr Ptr, ByVal arg7 As Const SqliteUpsert Ptr, ByVal arg8 As Const SqliteTrigger Ptr)
    Dim local0 As SQLITE_C_INT
    Dim local1 As SqliteTreeView Ptr
    Dim local2 As Const ZString Ptr
    Dim c2fb_temp_0 As Const ZString Ptr
    Dim c2fb_temp_1 As Const ZString Ptr
    Dim c2fb_temp_2 As Const ZString Ptr
    Dim c2fb_temp_3 As Const ZString Ptr
    Dim c2fb_temp_4 As Const ZString Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SqliteTreeView Ptr Ptr
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SQLITE_C_INT
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As SqliteTreeView Ptr Ptr
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As SQLITE_C_INT
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim c2fb_temp_23 As SqliteTreeView Ptr
    Dim c2fb_temp_24 As Const SqliteExprList Ptr
    Dim c2fb_temp_25 As SQLITE_C_INT
    Dim c2fb_temp_26 As Const ZString Ptr
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim c2fb_temp_28 As SQLITE_C_INT
    Dim c2fb_temp_29 As SqliteTreeView Ptr Ptr
    Dim c2fb_temp_30 As SQLITE_C_INT
    Dim c2fb_temp_31 As SQLITE_C_INT
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As SqliteTreeView Ptr
    Dim c2fb_temp_34 As Const SqliteExprList Ptr
    Dim c2fb_temp_35 As SQLITE_C_INT
    Dim c2fb_temp_36 As Const ZString Ptr
    Dim c2fb_temp_37 As SQLITE_C_INT
    Dim c2fb_temp_38 As SQLITE_C_INT
    Dim c2fb_temp_39 As SqliteTreeView Ptr Ptr
    Dim c2fb_temp_40 As SQLITE_C_INT
    Dim c2fb_temp_41 As SQLITE_C_INT
    Dim c2fb_temp_42 As SQLITE_C_INT
    Dim c2fb_temp_43 As SqliteTreeView Ptr Ptr
    Dim c2fb_temp_44 As SQLITE_C_INT
    Dim c2fb_temp_45 As SQLITE_C_INT
    Dim c2fb_temp_46 As SQLITE_C_INT
    Dim c2fb_temp_47 As SqliteTreeView Ptr
    Dim c2fb_temp_48 As Const SqliteTrigger Ptr
    Dim c2fb_temp_49 As SQLITE_C_INT
    Dim c2fb_temp_50 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    local2 = StrPtr(!"UPDATE")
    Select Case arg4
        Case Cast(SQLITE_C_INT, 5ULL)
            c2fb_temp_0 = StrPtr(!"UPDATE OR REPLACE")
            local2 = c2fb_temp_0
        Case Cast(SQLITE_C_INT, 4ULL)
            c2fb_temp_1 = StrPtr(!"UPDATE OR IGNORE")
            local2 = c2fb_temp_1
        Case Cast(SQLITE_C_INT, 1ULL)
            c2fb_temp_2 = StrPtr(!"UPDATE OR ROLLBACK")
            local2 = c2fb_temp_2
        Case Cast(SQLITE_C_INT, 2ULL)
            c2fb_temp_3 = StrPtr(!"UPDATE OR ABORT")
            local2 = c2fb_temp_3
        Case Cast(SQLITE_C_INT, 3ULL)
            c2fb_temp_4 = StrPtr(!"UPDATE OR FAIL")
            local2 = c2fb_temp_4
    End Select
    c2fb_flow_0:
    sqlite3TreeViewPush(CPtr(SqliteTreeView Ptr Ptr, @(local1)), Cast(SQLITE_C_INT, &O0ULL))
    sqlite3TreeViewLine(local1, local2)
    If arg0 Then
        c2fb_temp_5 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_5 + 1)))
    End If
    If arg1 Then
        c2fb_temp_6 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 + 1)))
    End If
    If arg2 Then
        c2fb_temp_7 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_7 + 1)))
    End If
    If arg3 Then
        c2fb_temp_8 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_8 + 1)))
    End If
    If arg5 Then
        c2fb_temp_9 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_9 + 1)))
    End If
    If arg6 Then
        c2fb_temp_10 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_10 + 1)))
    End If
    If arg7 Then
        c2fb_temp_11 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_11 + 1)))
    End If
    If arg8 Then
        c2fb_temp_12 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_12 + 1)))
    End If
    If arg0 Then
        c2fb_temp_15 = CPtr(SqliteTreeView Ptr Ptr, @(local1))
        c2fb_temp_13 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_13 - 1)))
        c2fb_temp_14 = local0
        c2fb_temp_16 = (-Cast(SQLITE_C_INT, (((c2fb_temp_14) > Cast(SQLITE_C_INT, &O0ULL)))))
        sqlite3TreeViewPush(c2fb_temp_15, c2fb_temp_16)
        sqlite3TreeViewWith(local1, arg0, Cast(SQLITE_C_INT, &O0ULL))
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(local1)))
    End If
    If arg1 Then
        c2fb_temp_19 = CPtr(SqliteTreeView Ptr Ptr, @(local1))
        c2fb_temp_17 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_17 - 1)))
        c2fb_temp_18 = local0
        c2fb_temp_20 = (-Cast(SQLITE_C_INT, (((c2fb_temp_18) > Cast(SQLITE_C_INT, &O0ULL)))))
        sqlite3TreeViewPush(c2fb_temp_19, c2fb_temp_20)
        sqlite3TreeViewLine(local1, StrPtr(!"FROM"))
        sqlite3TreeViewSrcList(local1, arg1)
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(local1)))
    End If
    If arg2 Then
        c2fb_temp_23 = local1
        c2fb_temp_24 = arg2
        c2fb_temp_21 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_21 - 1)))
        c2fb_temp_22 = local0
        c2fb_temp_25 = (-Cast(SQLITE_C_INT, (((c2fb_temp_22) > Cast(SQLITE_C_INT, &O0ULL)))))
        c2fb_temp_26 = StrPtr(!"SET")
        sqlite3TreeViewExprList(c2fb_temp_23, c2fb_temp_24, c2fb_temp_25, c2fb_temp_26)
    End If
    If arg3 Then
        c2fb_temp_29 = CPtr(SqliteTreeView Ptr Ptr, @(local1))
        c2fb_temp_27 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_27 - 1)))
        c2fb_temp_28 = local0
        c2fb_temp_30 = (-Cast(SQLITE_C_INT, (((c2fb_temp_28) > Cast(SQLITE_C_INT, &O0ULL)))))
        sqlite3TreeViewPush(c2fb_temp_29, c2fb_temp_30)
        sqlite3TreeViewLine(local1, StrPtr(!"WHERE"))
        sqlite3TreeViewExpr(local1, arg3, Cast(SQLITE_C_INT, &O0ULL))
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(local1)))
    End If
    If arg5 Then
        c2fb_temp_33 = local1
        c2fb_temp_34 = arg5
        c2fb_temp_31 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_31 - 1)))
        c2fb_temp_32 = local0
        c2fb_temp_35 = (-Cast(SQLITE_C_INT, (((c2fb_temp_32) > Cast(SQLITE_C_INT, &O0ULL)))))
        c2fb_temp_36 = StrPtr(!"ORDER-BY")
        sqlite3TreeViewExprList(c2fb_temp_33, c2fb_temp_34, c2fb_temp_35, c2fb_temp_36)
    End If
    If arg6 Then
        c2fb_temp_39 = CPtr(SqliteTreeView Ptr Ptr, @(local1))
        c2fb_temp_37 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_37 - 1)))
        c2fb_temp_38 = local0
        c2fb_temp_40 = (-Cast(SQLITE_C_INT, (((c2fb_temp_38) > Cast(SQLITE_C_INT, &O0ULL)))))
        sqlite3TreeViewPush(c2fb_temp_39, c2fb_temp_40)
        sqlite3TreeViewLine(local1, StrPtr(!"LIMIT"))
        sqlite3TreeViewExpr(local1, arg6, Cast(SQLITE_C_INT, &O0ULL))
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(local1)))
    End If
    If arg7 Then
        c2fb_temp_43 = CPtr(SqliteTreeView Ptr Ptr, @(local1))
        c2fb_temp_41 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_41 - 1)))
        c2fb_temp_42 = local0
        c2fb_temp_44 = (-Cast(SQLITE_C_INT, (((c2fb_temp_42) > Cast(SQLITE_C_INT, &O0ULL)))))
        sqlite3TreeViewPush(c2fb_temp_43, c2fb_temp_44)
        sqlite3TreeViewLine(local1, StrPtr(!"UPSERT"))
        sqlite3TreeViewUpsert(local1, arg7, Cast(SQLITE_C_INT, &O0ULL))
        sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(local1)))
    End If
    If arg8 Then
        c2fb_temp_47 = local1
        c2fb_temp_48 = arg8
        c2fb_temp_45 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_45 - 1)))
        c2fb_temp_46 = local0
        c2fb_temp_49 = (-Cast(SQLITE_C_INT, (((c2fb_temp_46) > Cast(SQLITE_C_INT, &O0ULL)))))
        c2fb_temp_50 = Cast(SQLITE_C_INT, 1ULL)
        sqlite3TreeViewTrigger(c2fb_temp_47, c2fb_temp_48, c2fb_temp_49, c2fb_temp_50)
    End If
    sqlite3TreeViewPop(CPtr(SqliteTreeView Ptr Ptr, @(local1)))
End Sub

#endif

#endif

/' end of sqlite3_treeview.bas '/
