/'
/*
** 2015-06-08
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
*************************************************************************
** This module contains C code that generates VDBE code used to process
** the WHERE clause of SQL statements.
**
** This file was originally part of where.c but was split out to improve
** readability and editability.  This file contains utility routines for
** analyzing Expr objects in the WHERE clause.
*/
'/

/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_bulk_whereexpr_analysis.bas

    Purpose:

        Analyze WHERE terms and derive indexable and virtual-table constraints.

    Responsibilities:

        - Implement exprAnalyze and its OR-term analysis helper.
        - Combine eligible OR disjuncts and expose the clause-wide analyzer.
        - Identify indexed operands and auxiliary virtual-table operators.
        - Keep translated local helpers with the routines that use them.

    This file intentionally does NOT contain:

        - WHERE loop scoring or VDBE loop bytecode generation.
        - The outer WhereBegin and WhereEnd orchestration.
        - Runtime parity claims for the translated analyzer code.
'/

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
#include once "sqlite3_vdbe_compare.bi"
#include once "sqlite3_walker.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_vtab_types.bi"
#include once "sqlite3_fp.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_vdbe_api.bi"
#include once "sqlite3_global_data.bi"
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
Declare Function sqlite3_complete16 CDecl Alias "sqlite3_complete16" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_incomplete CDecl Alias "sqlite3_incomplete" (ByVal arg0 As Const ZString Ptr) As sqlite3_int64
Declare Function sqlite3_busy_handler CDecl Alias "sqlite3_busy_handler" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_busy_timeout CDecl Alias "sqlite3_busy_timeout" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_setlk_timeout CDecl Alias "sqlite3_setlk_timeout" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_get_table CDecl Alias "sqlite3_get_table" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As ZString Ptr Ptr Ptr, ByVal arg3 As SQLITE_C_INT Ptr, ByVal arg4 As SQLITE_C_INT Ptr, ByVal arg5 As ZString Ptr Ptr) As SQLITE_C_INT
Declare Sub sqlite3_free_table CDecl Alias "sqlite3_free_table" (ByVal arg0 As ZString Ptr Ptr)
Declare Function sqlite3_mprintf CDecl Alias "sqlite3_mprintf" (ByVal arg0 As Const ZString Ptr, ...) As ZString Ptr
Declare Function sqlite3_vmprintf CDecl Alias "sqlite3_vmprintf" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As Any Ptr) As ZString Ptr
Declare Function sqlite3_snprintf CDecl Alias "sqlite3_snprintf" (ByVal arg0 As SQLITE_C_INT, ByVal arg1 As ZString Ptr, ByVal arg2 As Const ZString Ptr, ...) As ZString Ptr
Declare Function sqlite3_vsnprintf CDecl Alias "sqlite3_vsnprintf" (ByVal arg0 As SQLITE_C_INT, ByVal arg1 As ZString Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Any Ptr) As ZString Ptr
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
Declare Function sqlite3_open16 CDecl Alias "sqlite3_open16" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr Ptr) As SQLITE_C_INT
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
Declare Function sqlite3_errmsg16 CDecl Alias "sqlite3_errmsg16" (ByVal arg0 As Any Ptr) As Any Ptr
Declare Function sqlite3_errstr CDecl Alias "sqlite3_errstr" (ByVal arg0 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3_error_offset CDecl Alias "sqlite3_error_offset" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_set_errmsg CDecl Alias "sqlite3_set_errmsg" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3_limit CDecl Alias "sqlite3_limit" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_prepare CDecl Alias "sqlite3_prepare" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr Ptr, ByVal arg4 As Const ZString Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_prepare_v2 CDecl Alias "sqlite3_prepare_v2" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr Ptr, ByVal arg4 As Const ZString Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_prepare_v3 CDecl Alias "sqlite3_prepare_v3" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_UINT, ByVal arg4 As Any Ptr Ptr, ByVal arg5 As Const ZString Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_prepare16 CDecl Alias "sqlite3_prepare16" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr Ptr, ByVal arg4 As Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_prepare16_v2 CDecl Alias "sqlite3_prepare16_v2" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr Ptr, ByVal arg4 As Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_prepare16_v3 CDecl Alias "sqlite3_prepare16_v3" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_UINT, ByVal arg4 As Any Ptr Ptr, ByVal arg5 As Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_sql CDecl Alias "sqlite3_sql" (ByVal arg0 As Any Ptr) As Const ZString Ptr
Declare Function sqlite3_expanded_sql CDecl Alias "sqlite3_expanded_sql" (ByVal arg0 As Any Ptr) As ZString Ptr
Declare Function sqlite3_normalized_sql CDecl Alias "sqlite3_normalized_sql" (ByVal arg0 As Any Ptr) As Const ZString Ptr
Declare Function sqlite3_stmt_readonly CDecl Alias "sqlite3_stmt_readonly" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_stmt_isexplain CDecl Alias "sqlite3_stmt_isexplain" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_stmt_explain CDecl Alias "sqlite3_stmt_explain" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_stmt_busy CDecl Alias "sqlite3_stmt_busy" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_bind_blob CDecl Alias "sqlite3_bind_blob" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Any Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_bind_blob64 CDecl Alias "sqlite3_bind_blob64" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Any Ptr, ByVal arg3 As sqlite3_uint64, ByVal arg4 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_bind_double CDecl Alias "sqlite3_bind_double" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Double) As SQLITE_C_INT
Declare Function sqlite3_bind_int CDecl Alias "sqlite3_bind_int" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_bind_int64 CDecl Alias "sqlite3_bind_int64" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As sqlite3_int64) As SQLITE_C_INT
Declare Function sqlite3_bind_null CDecl Alias "sqlite3_bind_null" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_bind_text CDecl Alias "sqlite3_bind_text" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_bind_text16 CDecl Alias "sqlite3_bind_text16" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Any Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_bind_text64 CDecl Alias "sqlite3_bind_text64" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr, ByVal arg3 As sqlite3_uint64, ByVal arg4 As Any Ptr, ByVal arg5 As UByte) As SQLITE_C_INT
Declare Function sqlite3_bind_value CDecl Alias "sqlite3_bind_value" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_bind_pointer CDecl Alias "sqlite3_bind_pointer" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Any Ptr, ByVal arg3 As Const ZString Ptr, ByVal arg4 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_bind_zeroblob CDecl Alias "sqlite3_bind_zeroblob" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_bind_zeroblob64 CDecl Alias "sqlite3_bind_zeroblob64" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As sqlite3_uint64) As SQLITE_C_INT
Declare Function sqlite3_bind_parameter_count CDecl Alias "sqlite3_bind_parameter_count" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_bind_parameter_name CDecl Alias "sqlite3_bind_parameter_name" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3_bind_parameter_index CDecl Alias "sqlite3_bind_parameter_index" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3_clear_bindings CDecl Alias "sqlite3_clear_bindings" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_column_count CDecl Alias "sqlite3_column_count" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_column_name CDecl Alias "sqlite3_column_name" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3_column_name16 CDecl Alias "sqlite3_column_name16" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Any Ptr
Declare Function sqlite3_column_database_name CDecl Alias "sqlite3_column_database_name" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3_column_database_name16 CDecl Alias "sqlite3_column_database_name16" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Any Ptr
Declare Function sqlite3_column_table_name CDecl Alias "sqlite3_column_table_name" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3_column_table_name16 CDecl Alias "sqlite3_column_table_name16" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Any Ptr
Declare Function sqlite3_column_origin_name CDecl Alias "sqlite3_column_origin_name" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3_column_origin_name16 CDecl Alias "sqlite3_column_origin_name16" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Any Ptr
Declare Function sqlite3_column_decltype CDecl Alias "sqlite3_column_decltype" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3_column_decltype16 CDecl Alias "sqlite3_column_decltype16" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Any Ptr
Declare Function sqlite3_step CDecl Alias "sqlite3_step" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_data_count CDecl Alias "sqlite3_data_count" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_column_blob CDecl Alias "sqlite3_column_blob" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Any Ptr
Declare Function sqlite3_column_double CDecl Alias "sqlite3_column_double" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Double
Declare Function sqlite3_column_int CDecl Alias "sqlite3_column_int" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_column_int64 CDecl Alias "sqlite3_column_int64" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As sqlite3_int64
Declare Function sqlite3_column_text CDecl Alias "sqlite3_column_text" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Const UByte Ptr
Declare Function sqlite3_column_text16 CDecl Alias "sqlite3_column_text16" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Any Ptr
Declare Function sqlite3_column_value CDecl Alias "sqlite3_column_value" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Any Ptr
Declare Function sqlite3_column_bytes CDecl Alias "sqlite3_column_bytes" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_column_bytes16 CDecl Alias "sqlite3_column_bytes16" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_column_type CDecl Alias "sqlite3_column_type" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_finalize CDecl Alias "sqlite3_finalize" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_reset CDecl Alias "sqlite3_reset" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_create_function CDecl Alias "sqlite3_create_function" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As Any Ptr, ByVal arg5 As Any Ptr, ByVal arg6 As Any Ptr, ByVal arg7 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_create_function16 CDecl Alias "sqlite3_create_function16" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As Any Ptr, ByVal arg5 As Any Ptr, ByVal arg6 As Any Ptr, ByVal arg7 As Any Ptr) As SQLITE_C_INT
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
Declare Sub sqlite3_result_blob CDecl Alias "sqlite3_result_blob" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr)
Declare Sub sqlite3_result_blob64 CDecl Alias "sqlite3_result_blob64" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As sqlite3_uint64, ByVal arg3 As Any Ptr)
Declare Sub sqlite3_result_double CDecl Alias "sqlite3_result_double" (ByVal arg0 As Any Ptr, ByVal arg1 As Double)
Declare Sub sqlite3_result_error CDecl Alias "sqlite3_result_error" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Sub sqlite3_result_error16 CDecl Alias "sqlite3_result_error16" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Sub sqlite3_result_error_toobig CDecl Alias "sqlite3_result_error_toobig" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3_result_error_nomem CDecl Alias "sqlite3_result_error_nomem" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3_result_error_code CDecl Alias "sqlite3_result_error_code" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Sub sqlite3_result_int CDecl Alias "sqlite3_result_int" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Sub sqlite3_result_int64 CDecl Alias "sqlite3_result_int64" (ByVal arg0 As Any Ptr, ByVal arg1 As sqlite3_int64)
Declare Sub sqlite3_result_null CDecl Alias "sqlite3_result_null" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3_result_text CDecl Alias "sqlite3_result_text" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr)
Declare Sub sqlite3_result_text64 CDecl Alias "sqlite3_result_text64" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As sqlite3_uint64, ByVal arg3 As Any Ptr, ByVal arg4 As UByte)
Declare Sub sqlite3_result_text16 CDecl Alias "sqlite3_result_text16" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr)
Declare Sub sqlite3_result_text16le CDecl Alias "sqlite3_result_text16le" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr)
Declare Sub sqlite3_result_text16be CDecl Alias "sqlite3_result_text16be" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr)
Declare Sub sqlite3_result_value CDecl Alias "sqlite3_result_value" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3_result_pointer CDecl Alias "sqlite3_result_pointer" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Any Ptr)
Declare Sub sqlite3_result_zeroblob CDecl Alias "sqlite3_result_zeroblob" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Function sqlite3_result_zeroblob64 CDecl Alias "sqlite3_result_zeroblob64" (ByVal arg0 As Any Ptr, ByVal arg1 As sqlite3_uint64) As SQLITE_C_INT
Declare Sub sqlite3_result_subtype CDecl Alias "sqlite3_result_subtype" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_UINT)
Declare Function sqlite3_create_collation CDecl Alias "sqlite3_create_collation" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_create_collation_v2 CDecl Alias "sqlite3_create_collation_v2" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr, ByVal arg5 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_create_collation16 CDecl Alias "sqlite3_create_collation16" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_collation_needed CDecl Alias "sqlite3_collation_needed" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_collation_needed16 CDecl Alias "sqlite3_collation_needed16" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3_activate_cerod CDecl Alias "sqlite3_activate_cerod" (ByVal arg0 As Const ZString Ptr)
Declare Function sqlite3_sleep CDecl Alias "sqlite3_sleep" (ByVal arg0 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_win32_set_directory CDecl Alias "sqlite3_win32_set_directory" (ByVal arg0 As SQLITE_C_ULONG, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_win32_set_directory8 CDecl Alias "sqlite3_win32_set_directory8" (ByVal arg0 As SQLITE_C_ULONG, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3_win32_set_directory16 CDecl Alias "sqlite3_win32_set_directory16" (ByVal arg0 As SQLITE_C_ULONG, ByVal arg1 As Any Ptr) As SQLITE_C_INT
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
Declare Function sqlite3_create_module CDecl Alias "sqlite3_create_module" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_create_module_v2 CDecl Alias "sqlite3_create_module_v2" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_drop_modules CDecl Alias "sqlite3_drop_modules" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_declare_vtab CDecl Alias "sqlite3_declare_vtab" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3_overload_function CDecl Alias "sqlite3_overload_function" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_blob_open CDecl Alias "sqlite3_blob_open" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const ZString Ptr, ByVal arg4 As sqlite3_int64, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3_blob_reopen CDecl Alias "sqlite3_blob_reopen" (ByVal arg0 As Any Ptr, ByVal arg1 As sqlite3_int64) As SQLITE_C_INT
Declare Function sqlite3_blob_close CDecl Alias "sqlite3_blob_close" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_blob_bytes CDecl Alias "sqlite3_blob_bytes" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_blob_read CDecl Alias "sqlite3_blob_read" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_blob_write CDecl Alias "sqlite3_blob_write" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3_db_mutex CDecl Alias "sqlite3_db_mutex" (ByVal arg0 As Any Ptr) As Any Ptr
Declare Function sqlite3_file_control CDecl Alias "sqlite3_file_control" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_test_control CDecl Alias "sqlite3_test_control" (ByVal arg0 As SQLITE_C_INT, ...) As SQLITE_C_INT
Declare Function sqlite3_keyword_count CDecl Alias "sqlite3_keyword_count" () As SQLITE_C_INT
Declare Function sqlite3_keyword_name CDecl Alias "sqlite3_keyword_name" (ByVal arg0 As SQLITE_C_INT, ByVal arg1 As Const ZString Ptr Ptr, ByVal arg2 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function sqlite3_keyword_check CDecl Alias "sqlite3_keyword_check" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub sqlite3_result_str CDecl Alias "sqlite3_result_str" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Sub sqlite3_str_appendf CDecl Alias "sqlite3_str_appendf" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ...)
Declare Sub sqlite3_str_vappendf CDecl Alias "sqlite3_str_vappendf" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Any Ptr)
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
Declare Function sqlite3WindowCompare CDecl Alias "sqlite3WindowCompare" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
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
Declare Function sqlite3MallocSize CDecl Alias "sqlite3MallocSize" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3BenignMallocHooks CDecl Alias "sqlite3BenignMallocHooks" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3HeapNearlyFull CDecl Alias "sqlite3HeapNearlyFull" () As SQLITE_C_INT
Declare Function sqlite3MemGetMemsys5 CDecl Alias "sqlite3MemGetMemsys5" () As Any Ptr
Declare Function sqlite3MemGetMemsys3 CDecl Alias "sqlite3MemGetMemsys3" () As Any Ptr
Declare Function sqlite3DefaultMutex CDecl Alias "sqlite3DefaultMutex" () As Any Ptr
Declare Function sqlite3NoopMutex CDecl Alias "sqlite3NoopMutex" () As Any Ptr
Declare Function sqlite3LookasideUsed CDecl Alias "sqlite3LookasideUsed" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Sub sqlite3MutexWarnOnContention CDecl Alias "sqlite3MutexWarnOnContention" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3FpDecode CDecl Alias "sqlite3FpDecode" (ByVal arg0 As Any Ptr, ByVal arg1 As Double, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Declare Function sqlite3MPrintf CDecl Alias "sqlite3MPrintf" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ...) As ZString Ptr
Declare Function sqlite3VMPrintf CDecl Alias "sqlite3VMPrintf" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Any Ptr) As ZString Ptr
Declare Sub sqlite3DebugPrintf CDecl Alias "sqlite3DebugPrintf" (ByVal arg0 As Const ZString Ptr, ...)
Declare Function sqlite3TestTextToPtr CDecl Alias "sqlite3TestTextToPtr" (ByVal arg0 As Const ZString Ptr) As Any Ptr
Declare Function sqlite3TestPtrToText CDecl Alias "sqlite3TestPtrToText" (ByVal arg0 As Any Ptr) As Const ZString Ptr
Declare Sub sqlite3TreeViewLine CDecl Alias "sqlite3TreeViewLine" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ...)
Declare Sub sqlite3TreeViewExpr CDecl Alias "sqlite3TreeViewExpr" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As UByte)
Declare Sub sqlite3TreeViewBareExprList CDecl Alias "sqlite3TreeViewBareExprList" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Const ZString Ptr)
Declare Sub sqlite3TreeViewExprList CDecl Alias "sqlite3TreeViewExprList" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As UByte, ByVal arg3 As Const ZString Ptr)
Declare Sub sqlite3TreeViewBareIdList CDecl Alias "sqlite3TreeViewBareIdList" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Const ZString Ptr)
Declare Sub sqlite3TreeViewIdList CDecl Alias "sqlite3TreeViewIdList" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As UByte, ByVal arg3 As Const ZString Ptr)
Declare Sub sqlite3TreeViewColumnList CDecl Alias "sqlite3TreeViewColumnList" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As UByte)
Declare Sub sqlite3TreeViewSrcList CDecl Alias "sqlite3TreeViewSrcList" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3TreeViewSelect CDecl Alias "sqlite3TreeViewSelect" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As UByte)
Declare Sub sqlite3TreeViewWith CDecl Alias "sqlite3TreeViewWith" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As UByte)
Declare Sub sqlite3TreeViewUpsert CDecl Alias "sqlite3TreeViewUpsert" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As UByte)
Declare Sub sqlite3TreeViewDelete CDecl Alias "sqlite3TreeViewDelete" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr, ByVal arg5 As Any Ptr)
Declare Sub sqlite3TreeViewInsert CDecl Alias "sqlite3TreeViewInsert" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As Any Ptr, ByVal arg7 As Any Ptr)
Declare Sub sqlite3TreeViewUpdate CDecl Alias "sqlite3TreeViewUpdate" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As Any Ptr, ByVal arg6 As Any Ptr, ByVal arg7 As Any Ptr, ByVal arg8 As Any Ptr)
Declare Sub sqlite3TreeViewTriggerStep CDecl Alias "sqlite3TreeViewTriggerStep" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As UByte, ByVal arg3 As UByte)
Declare Sub sqlite3TreeViewTrigger CDecl Alias "sqlite3TreeViewTrigger" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As UByte, ByVal arg3 As UByte)
Declare Sub sqlite3TreeViewWindow CDecl Alias "sqlite3TreeViewWindow" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As UByte)
Declare Sub sqlite3TreeViewWinFunc CDecl Alias "sqlite3TreeViewWinFunc" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As UByte)
Declare Sub sqlite3ShowExpr CDecl Alias "sqlite3ShowExpr" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3ShowExprList CDecl Alias "sqlite3ShowExprList" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3ShowIdList CDecl Alias "sqlite3ShowIdList" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3ShowSrcList CDecl Alias "sqlite3ShowSrcList" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3ShowSelect CDecl Alias "sqlite3ShowSelect" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3ShowWith CDecl Alias "sqlite3ShowWith" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3ShowUpsert CDecl Alias "sqlite3ShowUpsert" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3ShowTriggerStep CDecl Alias "sqlite3ShowTriggerStep" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3ShowTriggerStepList CDecl Alias "sqlite3ShowTriggerStepList" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3ShowTrigger CDecl Alias "sqlite3ShowTrigger" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3ShowTriggerList CDecl Alias "sqlite3ShowTriggerList" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3ShowWindow CDecl Alias "sqlite3ShowWindow" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3ShowWinFunc CDecl Alias "sqlite3ShowWinFunc" (ByVal arg0 As Any Ptr)
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
Declare Function sqlite3ExprFunction CDecl Alias "sqlite3ExprFunction" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As SQLITE_C_INT) As Any Ptr
Declare Sub sqlite3ExprAddFunctionOrderBy CDecl Alias "sqlite3ExprAddFunctionOrderBy" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr)
Declare Sub sqlite3ExprOrderByAggregateError CDecl Alias "sqlite3ExprOrderByAggregateError" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3ExprFunctionUsable CDecl Alias "sqlite3ExprFunctionUsable" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr)
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
Declare Function sqlite3IndexBloomable CDecl Alias "sqlite3IndexBloomable" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
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
Declare Function sqlite3ExprImpliesExpr CDecl Alias "sqlite3ExprImpliesExpr" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
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
Declare Function sqlite3ExprIsLikeOperator CDecl Alias "sqlite3ExprIsLikeOperator" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
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
Declare Function sqlite3SrcListDup CDecl Alias "sqlite3SrcListDup" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT) As Any Ptr
Declare Function sqlite3IdListDup CDecl Alias "sqlite3IdListDup" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As Any Ptr
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
Declare Sub sqlite3FixInit CDecl Alias "sqlite3FixInit" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Const ZString Ptr, ByVal arg4 As Any Ptr)
Declare Function sqlite3FixSrcList CDecl Alias "sqlite3FixSrcList" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3FixSelect CDecl Alias "sqlite3FixSelect" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3FixExpr CDecl Alias "sqlite3FixExpr" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3FixTriggerStep CDecl Alias "sqlite3FixTriggerStep" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3Utf16ByteLen CDecl Alias "sqlite3Utf16ByteLen" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3Utf8CharLen CDecl Alias "sqlite3Utf8CharLen" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3Utf8Read CDecl Alias "sqlite3Utf8Read" (ByVal arg0 As Const UByte Ptr Ptr) As SQLITE_C_UINT
Declare Function sqlite3Utf8ReadLimited CDecl Alias "sqlite3Utf8ReadLimited" (ByVal arg0 As Const UByte Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_UINT Ptr) As SQLITE_C_INT
Declare Function sqlite3IndexAffinityStr CDecl Alias "sqlite3IndexAffinityStr" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As Const ZString Ptr
Declare Function sqlite3TableAffinityStr CDecl Alias "sqlite3TableAffinityStr" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As ZString Ptr
Declare Sub sqlite3TableAffinity CDecl Alias "sqlite3TableAffinity" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Function sqlite3CompareAffinity CDecl Alias "sqlite3CompareAffinity" (ByVal arg0 As Any Ptr, ByVal arg1 As Byte) As Byte
Declare Function sqlite3IndexAffinityOk CDecl Alias "sqlite3IndexAffinityOk" (ByVal arg0 As Any Ptr, ByVal arg1 As Byte) As SQLITE_C_INT
Declare Function sqlite3TableColumnAffinity CDecl Alias "sqlite3TableColumnAffinity" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Byte
Declare Function sqlite3ExprAffinity CDecl Alias "sqlite3ExprAffinity" (ByVal arg0 As Any Ptr) As Byte
Declare Function sqlite3ExprDataType CDecl Alias "sqlite3ExprDataType" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
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
Declare Function sqlite3Utf16to8 CDecl Alias "sqlite3Utf16to8" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As UByte) As ZString Ptr
Declare Function sqlite3ValueFromExpr CDecl Alias "sqlite3ValueFromExpr" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As UByte, ByVal arg3 As UByte, ByVal arg4 As Any Ptr Ptr) As SQLITE_C_INT
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
Declare Function sqlite3MatchEName CDecl Alias "sqlite3MatchEName" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const ZString Ptr, ByVal arg4 As SQLITE_C_INT Ptr) As SQLITE_C_INT
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
Declare Sub sqlite3AlterDropColumn CDecl Alias "sqlite3AlterDropColumn" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr)
Declare Function sqlite3RenameTokenMap CDecl Alias "sqlite3RenameTokenMap" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As Any Ptr
Declare Sub sqlite3RenameTokenRemap CDecl Alias "sqlite3RenameTokenRemap" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr)
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
Declare Sub sqlite3RecordErrorOffsetOfExpr CDecl Alias "sqlite3RecordErrorOffsetOfExpr" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Sub sqlite3BackupRestart CDecl Alias "sqlite3BackupRestart" (ByVal arg0 As Any Ptr)
Declare Sub sqlite3BackupUpdate CDecl Alias "sqlite3BackupUpdate" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const UByte Ptr)
Declare Function sqlite3ExprCheckIN CDecl Alias "sqlite3ExprCheckIN" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3Stat4ProbeSetValue CDecl Alias "sqlite3Stat4ProbeSetValue" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function sqlite3Stat4ValueFromExpr CDecl Alias "sqlite3Stat4ValueFromExpr" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As UByte, ByVal arg3 As Any Ptr Ptr) As SQLITE_C_INT
Declare Sub sqlite3Stat4ProbeFree CDecl Alias "sqlite3Stat4ProbeFree" (ByVal arg0 As Any Ptr)
Declare Function sqlite3Stat4Column CDecl Alias "sqlite3Stat4Column" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As Any Ptr Ptr) As SQLITE_C_INT
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
Declare Function sqlite3VtabCreateModule CDecl Alias "sqlite3VtabCreateModule" (ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr) As Any Ptr
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
Declare Function sqlite3TempInMemory CDecl Alias "sqlite3TempInMemory" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
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
Declare Function sqlite3MemdebugHasType CDecl Alias "sqlite3MemdebugHasType" (ByVal arg0 As Any Ptr, ByVal arg1 As UByte) As SQLITE_C_INT
Declare Function sqlite3MemdebugNoType CDecl Alias "sqlite3MemdebugNoType" (ByVal arg0 As Any Ptr, ByVal arg1 As UByte) As SQLITE_C_INT
Declare Function sqlite3ThreadCreate CDecl Alias "sqlite3ThreadCreate" (ByVal arg0 As Any Ptr Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3ThreadJoin CDecl Alias "sqlite3ThreadJoin" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr Ptr) As SQLITE_C_INT
Declare Function sqlite3DbpageRegister CDecl Alias "sqlite3DbpageRegister" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3DbstatRegister CDecl Alias "sqlite3DbstatRegister" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Sub sqlite3VectorErrorMsg CDecl Alias "sqlite3VectorErrorMsg" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
Declare Function sqlite3CompileOptions CDecl Alias "sqlite3CompileOptions" (ByVal arg0 As SQLITE_C_INT Ptr) As Const ZString Ptr Ptr
Declare Function sqlite3KvvfsInit CDecl Alias "sqlite3KvvfsInit" () As SQLITE_C_INT
Declare Function sqlite3Hwtime CDecl Alias "sqlite3Hwtime" () As sqlite3_uint64
Declare Function sqlite3StrBINARYName CDecl Alias "sqlite3StrBINARYName" () As Const ZString Ptr
Declare Sub sqlite3WhereSplit CDecl Alias "sqlite3WhereSplit" (ByVal arg0 As SqliteWhereClause Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As UByte)

Type c2fb_callback_6 As Function CDecl(ByVal arg0 As SQLITE_C_UINT, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr) As SQLITE_C_INT
Type c2fb_callback_9 As Sub CDecl(ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteVdbeMem Ptr Ptr)
Type c2fb_callback_65 As Function CDecl(ByVal arg0 As SqliteVtab Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Any Ptr Ptr Ptr Ptr Ptr, ByVal arg4 As Any Ptr Ptr) As SQLITE_C_INT

Declare Function allowedOp CDecl Alias "allowedOp" (ByVal arg0 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function exprCommute CDecl Alias "exprCommute" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr) As UShort
Declare Function operatorMask CDecl Alias "operatorMask" (ByVal arg0 As SQLITE_C_INT) As UShort
Declare Function isLikeOrGlob CDecl Alias "isLikeOrGlob" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SqliteExpr Ptr Ptr, ByVal arg3 As SQLITE_C_INT Ptr, ByVal arg4 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function isAuxiliaryVtabOperator CDecl Alias "isAuxiliaryVtabOperator" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As UByte Ptr, ByVal arg3 As SqliteExpr Ptr Ptr, ByVal arg4 As SqliteExpr Ptr Ptr) As SQLITE_C_INT
Declare Sub transferJoinMarkings CDecl Alias "transferJoinMarkings" (ByVal arg0 As SqliteExpr Ptr, ByVal arg1 As SqliteExpr Ptr)
Declare Sub markTermAsChild CDecl Alias "markTermAsChild" (ByVal arg0 As SqliteWhereClauseRecord Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT)
Declare Function whereNthSubterm CDecl Alias "whereNthSubterm" (ByVal arg0 As SqliteWhereTermRecord Ptr, ByVal arg1 As SQLITE_C_INT) As SqliteWhereTermRecord Ptr
Declare Sub whereCombineDisjuncts CDecl Alias "whereCombineDisjuncts" (ByVal arg0 As SqliteSrcListRecord Ptr, ByVal arg1 As SqliteWhereClauseRecord Ptr, ByVal arg2 As SqliteWhereTermRecord Ptr, ByVal arg3 As SqliteWhereTermRecord Ptr)
Declare Sub exprAnalyzeOrTerm CDecl Alias "exprAnalyzeOrTerm" (ByVal arg0 As SqliteSrcListRecord Ptr, ByVal arg1 As SqliteWhereClauseRecord Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Function termIsEquivalence CDecl Alias "termIsEquivalence" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SqliteSrcListRecord Ptr) As SQLITE_C_INT
Declare Function exprSelectUsage CDecl Alias "exprSelectUsage" (ByVal arg0 As SqliteWhereMaskSet Ptr, ByVal arg1 As SqliteSelect Ptr) As sqlite3_uint64
Declare Function exprMightBeIndexed CDecl Alias "exprMightBeIndexed" (ByVal arg0 As SqliteSrcListRecord Ptr, ByVal arg1 As SQLITE_C_INT Ptr, ByVal arg2 As SqliteExpr Ptr, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub exprAnalyze CDecl Alias "exprAnalyze" (ByVal arg0 As SqliteSrcListRecord Ptr, ByVal arg1 As SqliteWhereClauseRecord Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Sub sqlite3WhereClauseInit CDecl Alias "sqlite3WhereClauseInit" (ByVal arg0 As SqliteWhereClauseRecord Ptr, ByVal arg1 As SqliteWhereInfoRecord Ptr)
Declare Sub sqlite3WhereExprAnalyze CDecl Alias "sqlite3WhereExprAnalyze" (ByVal arg0 As SqliteSrcListRecord Ptr, ByVal arg1 As SqliteWhereClauseRecord Ptr)
Declare Function c2fb_crt_memset CDecl Alias "memset" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_SIZE_T) As Any Ptr
' c2fb skipped __bswap_16: outside the supported subset
' c2fb skipped __bswap_32: outside the supported subset
' c2fb skipped __bswap_64: outside the supported subset
' c2fb skipped __uint16_identity: outside the supported subset
' c2fb skipped __uint32_identity: outside the supported subset
' c2fb skipped __uint64_identity: outside the supported subset
' c2fb skipped sqlite3IsBinary: FreeBASIC body already exists
' c2fb skipped whereOrInfoDelete: outside the supported subset
' c2fb skipped whereAndInfoDelete: outside the supported subset
' c2fb skipped whereClauseInsert: FreeBASIC body already exists
Private Function whereExprSelectHasNoWindow( _
    ByVal pSelect As SqliteSelect Ptr _
) As SQLITE_C_INT
#ifndef SQLITE_OMIT_WINDOWFUNC
    If pSelect = 0 Then Return 1
    Return IIf(pSelect->pWin = 0, 1, 0)
#else
    ' No SELECT carries a window definition in an OMIT_WINDOWFUNC build.
    Return 1
#endif
End Function

Private Function allowedOp CDecl Alias "allowedOp" (ByVal arg0 As SQLITE_C_INT) As SQLITE_C_INT
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((arg0 > Cast(SQLITE_C_INT, 58ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((arg0 >= Cast(SQLITE_C_INT, 54ULL))))) Then
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    Return (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg0 = Cast(SQLITE_C_INT, 50ULL))))) OrElse (-Cast(SQLITE_C_INT, ((arg0 = Cast(SQLITE_C_INT, 51ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((arg0 = Cast(SQLITE_C_INT, 45ULL)))))))))
End Function

Private Function exprCommute CDecl Alias "exprCommute" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr) As UShort
    Dim c2fb_temp_0 As u32 Ptr
    Dim c2fb_temp_1 As SQLITE_C_UINT
    Dim local0 As SqliteExpr Ptr
    Dim c2fb_temp_2 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_3 As SqliteExpr Ptr
    Dim c2fb_temp_4 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_5 As SqliteExpr Ptr
    Dim c2fb_temp_6 As u8 Ptr
    Dim c2fb_temp_7 As UByte

    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->pLeft->op) = Cast(SQLITE_C_INT, 177ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->pRight->op) = Cast(SQLITE_C_INT, 177ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((CPtr(sqlite3CollSeq Ptr, sqlite3BinaryCompareCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pLeft), CPtr(Any Ptr, arg1->pRight))) <> CPtr(sqlite3CollSeq Ptr, sqlite3BinaryCompareCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pRight), CPtr(Any Ptr, arg1->pLeft))))))))))) Then
        c2fb_temp_0 = @(arg1->flags)
        c2fb_temp_1 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_0)) Xor Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H000400ULL)))))
        (*c2fb_temp_0) = Cast(u32, c2fb_temp_1)
        c2fb_temp_1 = Cast(SQLITE_C_UINT, (*c2fb_temp_0))
    End If
    local0 = arg1->pRight
    c2fb_temp_2 = @(arg1->pRight)
    c2fb_temp_3 = arg1->pLeft
    (*c2fb_temp_2) = c2fb_temp_3
    c2fb_temp_4 = @(arg1->pLeft)
    c2fb_temp_5 = local0
    (*c2fb_temp_4) = c2fb_temp_5
    ' empty C statement
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) >= Cast(SQLITE_C_INT, 55ULL))))) Then
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        c2fb_temp_6 = @(arg1->op)
        c2fb_temp_7 = Cast(UByte, Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->op) - Cast(SQLITE_C_INT, 55ULL)))) Xor Cast(SQLITE_C_INT, 2ULL)))) + Cast(SQLITE_C_INT, 55ULL))))
        (*c2fb_temp_6) = Cast(u8, c2fb_temp_7)
        c2fb_temp_7 = Cast(UByte, (*c2fb_temp_6))
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function operatorMask CDecl Alias "operatorMask" (ByVal arg0 As SQLITE_C_INT) As UShort
    Dim local0 As UShort
    Dim c2fb_temp_0 As UShort
    Dim c2fb_temp_1 As UShort
    Dim c2fb_temp_2 As UShort
    Dim c2fb_temp_3 As UShort

    ' C automatic storage declaration
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((arg0 >= Cast(SQLITE_C_INT, 54ULL))))) Then
        ' C unused-parameter annotation
        c2fb_temp_0 = Cast(UShort, Cast(UShort, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (arg0 - Cast(SQLITE_C_INT, 54ULL)))))))))
        local0 = c2fb_temp_0
    Else
        If (-Cast(SQLITE_C_INT, ((arg0 = Cast(SQLITE_C_INT, 50ULL))))) Then
            c2fb_temp_1 = Cast(UShort, Cast(SQLITE_C_INT, &H0001ULL))
            local0 = c2fb_temp_1
        Else
            If (-Cast(SQLITE_C_INT, ((arg0 = Cast(SQLITE_C_INT, 51ULL))))) Then
                c2fb_temp_2 = Cast(UShort, Cast(SQLITE_C_INT, &H0100ULL))
                local0 = c2fb_temp_2
            Else
                ' C unused-parameter annotation
                c2fb_temp_3 = Cast(UShort, Cast(SQLITE_C_INT, &H0080ULL))
                local0 = c2fb_temp_3
            End If
        End If
    End If
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    Return local0
End Function

Private Function isLikeOrGlob CDecl Alias "isLikeOrGlob" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SqliteExpr Ptr Ptr, ByVal arg3 As SQLITE_C_INT Ptr, ByVal arg4 As SQLITE_C_INT Ptr) As SQLITE_C_INT
    Dim local0 As Const UByte Ptr
    Dim local1 As SqliteExpr Ptr
    Dim local2 As SqliteExpr Ptr
    Dim local3 As SqliteExprList Ptr
    Dim local4 As UByte
    Dim local5 As SQLITE_C_INT
    Dim local6(0 To 3) As UByte
    Dim local7 As sqlite3 Ptr
    Dim local8 As SqliteVdbeMem Ptr
    Dim local9 As SQLITE_C_INT
    Dim local10 As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteExprList Ptr
    Dim c2fb_temp_1 As SqliteExpr Ptr
    Dim c2fb_temp_2 As SqliteExpr Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim local11 As SqliteVdbe Ptr
    Dim local12 As SQLITE_C_INT
    Dim c2fb_temp_4 As SqliteVdbeMem Ptr
    Dim c2fb_temp_5 As Const UByte Ptr
    Dim c2fb_temp_6 As Const UByte Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As UByte
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim local13 As Const UByte Ptr
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim local14 As SqliteExpr Ptr
    Dim c2fb_temp_13 As SQLITE_C_INT Ptr
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SqliteExpr Ptr
    Dim local15 As SQLITE_C_INT
    Dim local16 As SQLITE_C_INT
    Dim local17 As ZString Ptr
    Dim c2fb_temp_16 As ZString Ptr
    Dim c2fb_temp_17 As Byte Ptr
    Dim c2fb_temp_18 As Byte
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As SQLITE_C_INT
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim c2fb_temp_23 As SQLITE_C_INT
    Dim c2fb_temp_24 As Byte Ptr
    Dim c2fb_temp_25 As Byte
    Dim c2fb_temp_26 As Byte Ptr
    Dim c2fb_temp_27 As Byte
    Dim local18 As SQLITE_C_INT
    Dim local19 As Double
    Dim c2fb_temp_28 As SQLITE_C_INT
    Dim c2fb_temp_29 As SQLITE_C_INT
    Dim c2fb_temp_30 As Byte Ptr
    Dim c2fb_temp_31 As Byte
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As Byte Ptr
    Dim c2fb_temp_34 As Byte
    Dim c2fb_temp_35 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_36 As SqliteExpr Ptr
    Dim local20 As SqliteVdbe Ptr
    Dim local21 As SQLITE_C_INT
    Dim c2fb_temp_37 As Const UByte Ptr
    Dim c2fb_temp_38 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic array storage
    local7 = arg0->db
    local8 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, (sqlite3IsLikeFunction(CPtr(Any Ptr, local7), CPtr(Any Ptr, arg1), arg4, CPtr(ZString Ptr, CPtr(UByte Ptr, (@local6(0))))) = 0))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    ' C unused-parameter annotation
    c2fb_temp_0 = arg1->x.pList
    local3 = c2fb_temp_0
    c2fb_temp_1 = local3->a(Cast(SQLITE_C_INT, 1ULL)).pExpr
    local2 = c2fb_temp_1
    c2fb_temp_2 = CPtr(SqliteExpr Ptr, sqlite3ExprSkipCollate(CPtr(Any Ptr, local3->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr)))
    local1 = c2fb_temp_2
    c2fb_temp_3 = Cast(SQLITE_C_INT, local1->op)
    local9 = c2fb_temp_3
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local9 = Cast(SQLITE_C_INT, 157ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local7->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &H00800000ULL))))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
        local11 = CPtr(SqliteVdbe Ptr, arg0->pReprepare)
        local12 = local1->iColumn
        c2fb_temp_4 = CPtr(SqliteVdbeMem Ptr, sqlite3VdbeGetBoundValue(local11, local12, Cast(SQLITE_C_INT, &H41ULL)))
        local8 = c2fb_temp_4
        If (-Cast(SQLITE_C_INT, ((local8 AndAlso (-Cast(SQLITE_C_INT, ((sqlite3_value_type(local8) = Cast(SQLITE_C_INT, 3ULL))))))))) Then
            c2fb_temp_5 = CPtr(Const UByte Ptr, sqlite3_value_text(local8))
            local0 = c2fb_temp_5
        End If
        sqlite3VdbeReprepareOnBind(CPtr(SqliteVdbe Ptr, arg0->pVdbe), local12, Cast(SQLITE_C_INT, &O0ULL))
        ' C unused-parameter annotation
    Else
        If (-Cast(SQLITE_C_INT, ((local9 = Cast(SQLITE_C_INT, 118ULL))))) Then
            ' C unused-parameter annotation
            c2fb_temp_6 = CPtr(Const UByte Ptr, CPtr(UByte Ptr, CPtr(ZString Ptr, local1->u.zToken)))
            local0 = c2fb_temp_6
        End If
    End If
    If local0 Then
        c2fb_temp_7 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local5 = c2fb_temp_7
        Do
            c2fb_temp_8 = Cast(UByte, local0[local5])
            local4 = c2fb_temp_8
            If ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (c2fb_temp_8)) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4) <> Cast(SQLITE_C_INT, local6(Cast(SQLITE_C_INT, &O0ULL))))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4) <> Cast(SQLITE_C_INT, local6(Cast(SQLITE_C_INT, 1ULL))))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4) <> Cast(SQLITE_C_INT, local6(Cast(SQLITE_C_INT, 2ULL))))))))))) = 0) Then Goto c2fb_flow_0
            c2fb_temp_9 = local5
            local5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_9 + 1)))
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4) = Cast(SQLITE_C_INT, local6(Cast(SQLITE_C_INT, 3ULL))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0[local5]) > Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0[local5]) < Cast(SQLITE_C_INT, &H80ULL))))))))) Then
                c2fb_temp_10 = local5
                local5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_10 + 1)))
            Else
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4) >= Cast(SQLITE_C_INT, &H80ULL))))) Then
                    local13 = CPtr(Const UByte Ptr, (CPtr(Const UByte Ptr, (local0 + local5)) - Cast(SQLITE_C_INT, 1ULL)))
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4) = Cast(SQLITE_C_INT, &HffULL))))) OrElse (-Cast(SQLITE_C_INT, ((sqlite3Utf8Read(CPtr(Const UByte Ptr Ptr, @(local13))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &HfffdULL)))))))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((local7)->enc)) = Cast(SQLITE_C_INT, 2ULL))))))))) Then
                        c2fb_temp_11 = local5
                        local5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_11 - 1)))
                        Goto c2fb_flow_0
                    Else
                        c2fb_temp_12 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((local13 - local0))))
                        local5 = c2fb_temp_12
                    End If
                End If
            End If
        c2fb_flow_1:
        Loop
        c2fb_flow_0:
        If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local5 > Cast(SQLITE_C_INT, 1ULL))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local5 > Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0[Cast(SQLITE_C_INT, &O0ULL)]) <> Cast(SQLITE_C_INT, local6(Cast(SQLITE_C_INT, 3ULL))))))))))))))))) AndAlso ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, 255ULL) <> Cast(SQLITE_C_INT, Cast(UByte, local0[Cast(SQLITE_C_INT, (local5 - Cast(SQLITE_C_INT, 1ULL)))]))))))))))) Then
            ' C automatic storage declaration
            c2fb_temp_13 = @((*arg3))
            c2fb_temp_14 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4) = Cast(SQLITE_C_INT, local6(Cast(SQLITE_C_INT, &O0ULL))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0[Cast(SQLITE_C_INT, (local5 + Cast(SQLITE_C_INT, 1ULL)))]) = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((local7)->enc)) <> Cast(SQLITE_C_INT, 2ULL))))))))))
            (*c2fb_temp_13) = c2fb_temp_14
            c2fb_temp_15 = CPtr(SqliteExpr Ptr, sqlite3Expr(CPtr(Any Ptr, local7), Cast(SQLITE_C_INT, 118ULL), CPtr(Const ZString Ptr, CPtr(ZString Ptr, local0))))
            local14 = c2fb_temp_15
            If local14 Then
                ' C automatic storage declaration
                ' C automatic storage declaration
                ' C automatic storage declaration
                ' C unused-parameter annotation
                c2fb_temp_16 = CPtr(ZString Ptr, local14->u.zToken)
                local17 = c2fb_temp_16
                c2fb_temp_17 = @(CPtr(Byte Ptr, local17)[local5])
                c2fb_temp_18 = Cast(Byte, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_17) = c2fb_temp_18
                c2fb_temp_19 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local16 = c2fb_temp_19
                c2fb_temp_20 = Cast(SQLITE_C_INT, c2fb_temp_19)
                local15 = c2fb_temp_20
                While (-Cast(SQLITE_C_INT, ((local15 < local5))))
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(Byte Ptr, local17)[local15]) = Cast(SQLITE_C_INT, local6(Cast(SQLITE_C_INT, 3ULL))))))) Then
                        c2fb_temp_22 = local15
                        local15 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_22 + 1)))
                    End If
                    c2fb_temp_23 = local16
                    local16 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_23 + 1)))
                    c2fb_temp_24 = @(CPtr(Byte Ptr, local17)[c2fb_temp_23])
                    c2fb_temp_25 = Cast(Byte, CPtr(Byte Ptr, local17)[local15])
                    (*c2fb_temp_24) = c2fb_temp_25
                c2fb_flow_3:
                    c2fb_temp_21 = local15
                    local15 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_21 + 1)))
                Wend
                c2fb_flow_2:
                c2fb_temp_26 = @(CPtr(Byte Ptr, local17)[local16])
                c2fb_temp_27 = Cast(Byte, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_26) = c2fb_temp_27
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->op) <> Cast(SQLITE_C_INT, 168ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, sqlite3ExprAffinity(CPtr(Any Ptr, local2))) <> Cast(SQLITE_C_INT, &H42ULL))))))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local2)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H1000000ULL) Or Cast(SQLITE_C_INT, &H2000000ULL)))))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))) AndAlso (CPtr(SqliteTable Ptr, local2->y.pTab)))))) AndAlso ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (CPtr(SqliteTable Ptr, local2->y.pTab))->eTabType) = Cast(SQLITE_C_INT, 1ULL))))))))))))))) Then
                    ' C automatic storage declaration
                    ' C automatic storage declaration
                    ' C unused-parameter annotation
                    c2fb_temp_28 = Cast(SQLITE_C_INT, sqlite3AtoF(CPtr(Const ZString Ptr, local17), CPtr(Double Ptr, @(local19))))
                    local18 = c2fb_temp_28
                    If (-Cast(SQLITE_C_INT, ((local18 <= Cast(SQLITE_C_INT, &O0ULL))))) Then
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local16 = Cast(SQLITE_C_INT, 1ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(Byte Ptr, local17)[Cast(SQLITE_C_INT, &O0ULL)]) = Cast(SQLITE_C_INT, 45))))))))) Then
                            c2fb_temp_29 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (+Cast(SQLITE_C_INT, 1ULL))))
                            local18 = c2fb_temp_29
                        Else
                            c2fb_temp_30 = @(CPtr(Byte Ptr, local17)[Cast(SQLITE_C_INT, (local16 - Cast(SQLITE_C_INT, 1ULL)))])
                            c2fb_temp_31 = (*c2fb_temp_30)
                            (*c2fb_temp_30) = Cast(Byte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_31) + 1)))
                            c2fb_temp_32 = Cast(SQLITE_C_INT, sqlite3AtoF(CPtr(Const ZString Ptr, local17), CPtr(Double Ptr, @(local19))))
                            local18 = c2fb_temp_32
                            c2fb_temp_33 = @(CPtr(Byte Ptr, local17)[Cast(SQLITE_C_INT, (local16 - Cast(SQLITE_C_INT, 1ULL)))])
                            c2fb_temp_34 = (*c2fb_temp_33)
                            (*c2fb_temp_33) = Cast(Byte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_34) - 1)))
                        End If
                    End If
                    If (-Cast(SQLITE_C_INT, ((local18 > Cast(SQLITE_C_INT, &O0ULL))))) Then
                        sqlite3ExprDelete(CPtr(Any Ptr, local7), CPtr(Any Ptr, local14))
                        sqlite3ValueFree(CPtr(Any Ptr, local8))
                        Return Cast(SQLITE_C_INT, &O0ULL)
                    End If
                End If
            End If
            c2fb_temp_35 = @((*arg2))
            c2fb_temp_36 = local14
            (*c2fb_temp_35) = c2fb_temp_36
            If (-Cast(SQLITE_C_INT, ((local9 = Cast(SQLITE_C_INT, 157ULL))))) Then
                local20 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
                sqlite3VdbeReprepareOnBind(local20, local1->iColumn, Cast(SQLITE_C_INT, &O0ULL))
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, (((*arg3) AndAlso Cast(SQLITE_C_INT, CPtr(Byte Ptr, CPtr(ZString Ptr, local1->u.zToken))[Cast(SQLITE_C_INT, 1ULL)]))))) Then
                    local21 = sqlite3GetTempReg(CPtr(Any Ptr, arg0))
                    sqlite3ExprCodeTarget(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local1), local21)
                    sqlite3VdbeChangeP3(local20, Cast(SQLITE_C_INT, (sqlite3VdbeCurrentAddr(local20) - Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, &O0ULL))
                    sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local21)
                End If
            End If
        Else
            c2fb_temp_37 = CPtr(Const UByte Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            local0 = c2fb_temp_37
        End If
    End If
    c2fb_temp_38 = Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, ((local0 <> Cast(SQLITE_C_INT, &O0ULL)))))))
    local10 = c2fb_temp_38
    sqlite3ValueFree(CPtr(Any Ptr, local8))
    Return local10
End Function

' c2fb skipped sqlite3ExprIsLikeOperator: FreeBASIC body already exists
Private Function isAuxiliaryVtabOperator CDecl Alias "isAuxiliaryVtabOperator" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As UByte Ptr, ByVal arg3 As SqliteExpr Ptr Ptr, ByVal arg4 As SqliteExpr Ptr Ptr) As SQLITE_C_INT
    Dim local0 As SqliteExprList Ptr
    Dim local1 As SqliteExpr Ptr
    Dim local2 As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteExprList Ptr
    Dim c2fb_temp_1 As SqliteExpr Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As UByte Ptr
    Dim c2fb_temp_5 As UByte
    Dim c2fb_temp_6 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_7 As SqliteExpr Ptr
    Dim c2fb_temp_8 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_9 As SqliteExpr Ptr
    Dim c2fb_temp_10 As SqliteExpr Ptr
    Dim local3 As SqliteVtab Ptr
    Dim local4 As SqliteModuleCallbacks Ptr
    Dim local5 As c2fb_callback_9
    Dim local6 As Any Ptr
    Dim c2fb_temp_11 As SqliteVtab Ptr
    Dim c2fb_temp_12 As SqliteModuleCallbacks Ptr
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As UByte Ptr
    Dim c2fb_temp_15 As UByte
    Dim c2fb_temp_16 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_17 As SqliteExpr Ptr
    Dim c2fb_temp_18 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_19 As SqliteExpr Ptr
    Dim local7 As SQLITE_C_INT
    Dim local8 As SqliteExpr Ptr
    Dim local9 As SqliteExpr Ptr
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As SQLITE_C_INT
    Dim local10 As SqliteExpr Ptr
    Dim c2fb_temp_22 As SqliteExpr Ptr
    Dim c2fb_temp_23 As SqliteExpr Ptr
    Dim c2fb_temp_24 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_25 As SqliteExpr Ptr
    Dim c2fb_temp_26 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_27 As SqliteExpr Ptr
    Dim c2fb_temp_28 As UByte Ptr
    Dim c2fb_temp_29 As UByte
    Dim c2fb_temp_30 As UByte Ptr
    Dim c2fb_temp_31 As UByte
    Dim c2fb_temp_32 As UByte Ptr
    Dim c2fb_temp_33 As UByte

    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 172ULL))))) Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C unused-parameter annotation
        c2fb_temp_0 = arg1->x.pList
        local0 = c2fb_temp_0
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local0->nExpr <> Cast(SQLITE_C_INT, 2ULL))))))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        c2fb_temp_1 = local0->a(Cast(SQLITE_C_INT, 1ULL)).pExpr
        local1 = c2fb_temp_1
        ' C unused-parameter annotation
        c2fb_temp_3 = 0
        If ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local1)->op) = Cast(SQLITE_C_INT, 168ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(SqliteTable Ptr, (local1)->y.pTab)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))))))) Then
            c2fb_temp_2 = Cast(SQLITE_C_INT, sqlite3ExprIsLikeOperator(CPtr(Any Ptr, arg1)))
            local2 = c2fb_temp_2
            c2fb_temp_3 = (-Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, (((c2fb_temp_2) <> Cast(SQLITE_C_INT, &O0ULL))))) <> 0)))
        End If
        If c2fb_temp_3 Then
            c2fb_temp_4 = @((*arg2))
            c2fb_temp_5 = Cast(UByte, local2)
            (*c2fb_temp_4) = c2fb_temp_5
            c2fb_temp_6 = @((*arg4))
            c2fb_temp_7 = local0->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr
            (*c2fb_temp_6) = c2fb_temp_7
            c2fb_temp_8 = @((*arg3))
            c2fb_temp_9 = local1
            (*c2fb_temp_8) = c2fb_temp_9
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
        c2fb_temp_10 = local0->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr
        local1 = c2fb_temp_10
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        If ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local1)->op) = Cast(SQLITE_C_INT, 168ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(SqliteTable Ptr, (local1)->y.pTab)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))))))) Then
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic callback storage declaration
            ' C automatic storage declaration
            c2fb_temp_11 = CPtr(SqliteVTable Ptr, sqlite3GetVTable(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteTable Ptr, local1->y.pTab))))->pVtab
            local3 = c2fb_temp_11
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_12 = CPtr(SqliteModuleCallbacks Ptr, local3->pModule)
            local4 = c2fb_temp_12
            If (-Cast(SQLITE_C_INT, ((CPtr(Any Ptr, CPtr(c2fb_callback_65, local4->xFindFunction)) <> CPtr(Any Ptr, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                c2fb_temp_13 = Cast(SQLITE_C_INT, CPtr(c2fb_callback_65, local4->xFindFunction)(local3, Cast(SQLITE_C_INT, 2ULL), CPtr(Const ZString Ptr, CPtr(ZString Ptr, arg1->u.zToken)), CPtr(Any Ptr Ptr Ptr Ptr Ptr, CPtr(c2fb_callback_9 Ptr, @(local5))), CPtr(Any Ptr Ptr, @(local6))))
                local2 = c2fb_temp_13
                If (-Cast(SQLITE_C_INT, ((local2 >= Cast(SQLITE_C_INT, 150ULL))))) Then
                    c2fb_temp_14 = @((*arg2))
                    c2fb_temp_15 = Cast(UByte, local2)
                    (*c2fb_temp_14) = c2fb_temp_15
                    c2fb_temp_16 = @((*arg4))
                    c2fb_temp_17 = local0->a(Cast(SQLITE_C_INT, 1ULL)).pExpr
                    (*c2fb_temp_16) = c2fb_temp_17
                    c2fb_temp_18 = @((*arg3))
                    c2fb_temp_19 = local1
                    (*c2fb_temp_18) = c2fb_temp_19
                    Return Cast(SQLITE_C_INT, 1ULL)
                End If
            End If
        End If
    Else
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) >= Cast(SQLITE_C_INT, 54ULL))))) Then
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            Return Cast(SQLITE_C_INT, &O0ULL)
        Else
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 53ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 46ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 52ULL))))))))) Then
                local7 = Cast(SQLITE_C_INT, &O0ULL)
                local8 = arg1->pLeft
                local9 = arg1->pRight
                ' C unused-parameter annotation
                If ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local8)->op) = Cast(SQLITE_C_INT, 168ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(SqliteTable Ptr, (local8)->y.pTab)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))))))) Then
                    c2fb_temp_20 = local7
                    local7 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_20 + 1)))
                End If
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, ((local9 AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local9)->op) = Cast(SQLITE_C_INT, 168ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(SqliteTable Ptr, (local9)->y.pTab)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))))))))))) Then
                    c2fb_temp_21 = local7
                    local7 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_21 + 1)))
                    local10 = local8
                    c2fb_temp_22 = local9
                    local8 = c2fb_temp_22
                    c2fb_temp_23 = local10
                    local9 = c2fb_temp_23
                    ' empty C statement
                End If
                c2fb_temp_24 = @((*arg3))
                c2fb_temp_25 = local8
                (*c2fb_temp_24) = c2fb_temp_25
                c2fb_temp_26 = @((*arg4))
                c2fb_temp_27 = local9
                (*c2fb_temp_26) = c2fb_temp_27
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 53ULL))))) Then
                    c2fb_temp_28 = @((*arg2))
                    c2fb_temp_29 = Cast(UByte, Cast(SQLITE_C_INT, 68ULL))
                    (*c2fb_temp_28) = c2fb_temp_29
                End If
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 46ULL))))) Then
                    c2fb_temp_30 = @((*arg2))
                    c2fb_temp_31 = Cast(UByte, Cast(SQLITE_C_INT, 69ULL))
                    (*c2fb_temp_30) = c2fb_temp_31
                End If
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 52ULL))))) Then
                    c2fb_temp_32 = @((*arg2))
                    c2fb_temp_33 = Cast(UByte, Cast(SQLITE_C_INT, 70ULL))
                    (*c2fb_temp_32) = c2fb_temp_33
                End If
                Return local7
            End If
        End If
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Sub transferJoinMarkings CDecl Alias "transferJoinMarkings" (ByVal arg0 As SqliteExpr Ptr, ByVal arg1 As SqliteExpr Ptr)
    Dim c2fb_temp_0 As u32 Ptr
    Dim c2fb_temp_1 As SQLITE_C_UINT
    Dim c2fb_temp_2 As SQLITE_C_INT Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT

    If (-Cast(SQLITE_C_INT, ((arg0 AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000001ULL) Or Cast(SQLITE_C_INT, &H000002ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
        c2fb_temp_0 = @(arg0->flags)
        c2fb_temp_1 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_0)) Or Cast(SQLITE_C_UINT, (arg1->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000001ULL) Or Cast(SQLITE_C_INT, &H000002ULL))))))))))
        (*c2fb_temp_0) = Cast(u32, c2fb_temp_1)
        c2fb_temp_1 = Cast(SQLITE_C_UINT, (*c2fb_temp_0))
        c2fb_temp_2 = @(arg0->w.iJoin)
        c2fb_temp_3 = Cast(SQLITE_C_INT, arg1->w.iJoin)
        (*c2fb_temp_2) = c2fb_temp_3
    End If
End Sub

Private Sub markTermAsChild CDecl Alias "markTermAsChild" (ByVal arg0 As SqliteWhereClauseRecord Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT)
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As Short Ptr
    Dim c2fb_temp_3 As Short
    Dim c2fb_temp_4 As u8 Ptr
    Dim c2fb_temp_5 As UByte

    c2fb_temp_0 = @(CPtr(SqliteWhereTermRecord Ptr, arg0->a)[arg1].iParent)
    c2fb_temp_1 = Cast(SQLITE_C_INT, arg2)
    (*c2fb_temp_0) = c2fb_temp_1
    c2fb_temp_2 = @(CPtr(SqliteWhereTermRecord Ptr, arg0->a)[arg1].truthProb)
    c2fb_temp_3 = Cast(Short, CPtr(SqliteWhereTermRecord Ptr, arg0->a)[arg2].truthProb)
    (*c2fb_temp_2) = c2fb_temp_3
    ' C unused-parameter annotation
    c2fb_temp_4 = @(CPtr(SqliteWhereTermRecord Ptr, arg0->a)[arg2].nChild)
    c2fb_temp_5 = Cast(UByte, (*c2fb_temp_4))
    (*c2fb_temp_4) = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_5) + 1)))
    ' empty C statement
End Sub

Private Function whereNthSubterm CDecl Alias "whereNthSubterm" (ByVal arg0 As SqliteWhereTermRecord Ptr, ByVal arg1 As SQLITE_C_INT) As SqliteWhereTermRecord Ptr
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->eOperator) <> Cast(SQLITE_C_INT, &H0400ULL))))) Then
        Return IIf((-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, &O0ULL))))), arg0, CPtr(SqliteWhereTermRecord Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
    End If
    If (-Cast(SQLITE_C_INT, ((arg1 < CPtr(SqliteWhereAndInfo Ptr, arg0->u.pAndInfo)->wc.nTerm)))) Then
        Return CPtr(SqliteWhereTermRecord Ptr, @(CPtr(SqliteWhereTermRecord Ptr, CPtr(SqliteWhereAndInfo Ptr, arg0->u.pAndInfo)->wc.a)[arg1]))
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Sub whereCombineDisjuncts CDecl Alias "whereCombineDisjuncts" (ByVal arg0 As SqliteSrcListRecord Ptr, ByVal arg1 As SqliteWhereClauseRecord Ptr, ByVal arg2 As SqliteWhereTermRecord Ptr, ByVal arg3 As SqliteWhereTermRecord Ptr)
    Dim local0 As UShort
    Dim local1 As sqlite3 Ptr
    Dim local2 As SqliteExpr Ptr
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As SqliteExpr Ptr
    Dim local6 As SqliteExpr Ptr
    Dim c2fb_temp_0 As SqliteExpr Ptr
    Dim c2fb_temp_1 As SqliteExpr Ptr
    Dim c2fb_temp_2 As UShort
    Dim c2fb_temp_3 As UShort
    Dim c2fb_temp_4 As sqlite3 Ptr
    Dim c2fb_temp_5 As SqliteExpr Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As u8 Ptr
    Dim c2fb_temp_9 As UByte
    Dim c2fb_temp_10 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2->eOperator) Or Cast(SQLITE_C_INT, arg3->eOperator)))
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2->wtFlags) Or Cast(SQLITE_C_INT, arg3->wtFlags)))) And Cast(SQLITE_C_INT, &H0080ULL))) Then
        Return
    End If
    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2->eOperator) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 57ULL) - Cast(SQLITE_C_INT, 54ULL))))))))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 56ULL) - Cast(SQLITE_C_INT, 54ULL))))))))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 55ULL) - Cast(SQLITE_C_INT, 54ULL))))))))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 58ULL) - Cast(SQLITE_C_INT, 54ULL))))))))))))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg3->eOperator) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 57ULL) - Cast(SQLITE_C_INT, 54ULL))))))))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 56ULL) - Cast(SQLITE_C_INT, 54ULL))))))))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 55ULL) - Cast(SQLITE_C_INT, 54ULL))))))))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 58ULL) - Cast(SQLITE_C_INT, 54ULL))))))))))))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 57ULL) - Cast(SQLITE_C_INT, 54ULL))))))))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 56ULL) - Cast(SQLITE_C_INT, 54ULL))))))))))))) <> Cast(SQLITE_C_INT, local0))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 55ULL) - Cast(SQLITE_C_INT, 54ULL))))))))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 58ULL) - Cast(SQLITE_C_INT, 54ULL))))))))))))) <> Cast(SQLITE_C_INT, local0))))))))) Then
        Return
    End If
    c2fb_temp_0 = arg2->pExpr
    local5 = c2fb_temp_0
    c2fb_temp_1 = arg3->pExpr
    local6 = c2fb_temp_1
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If sqlite3ExprCompare(Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, local5->pLeft), CPtr(Any Ptr, local6->pLeft), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))) Then
        Return
    End If
    If sqlite3ExprCompare(Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, local5->pRight), CPtr(Any Ptr, local6->pRight), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))) Then
        Return
    End If
    If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local5)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000400ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) <> ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local6)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000400ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
        Return
    End If
    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0) - Cast(SQLITE_C_INT, 1ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0) And (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 57ULL) - Cast(SQLITE_C_INT, 54ULL))))))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 56ULL) - Cast(SQLITE_C_INT, 54ULL)))))))))))) Then
            c2fb_temp_2 = Cast(UShort, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 56ULL) - Cast(SQLITE_C_INT, 54ULL))))))))
            local0 = c2fb_temp_2
        Else
            ' C unused-parameter annotation
            c2fb_temp_3 = Cast(UShort, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 58ULL) - Cast(SQLITE_C_INT, 54ULL))))))))
            local0 = c2fb_temp_3
        End If
    End If
    c2fb_temp_4 = CPtr(SqliteWhereInfoRecord Ptr, arg1->pWInfo)->pParse->db
    local1 = c2fb_temp_4
    c2fb_temp_5 = CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local1), CPtr(Any Ptr, local5), Cast(SQLITE_C_INT, &O0ULL)))
    local2 = c2fb_temp_5
    If (-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    c2fb_temp_6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 54ULL))
    local3 = c2fb_temp_6
    While (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0) <> (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (local3 - Cast(SQLITE_C_INT, 54ULL)))))))))))
        ' C unused-parameter annotation
    c2fb_flow_1:
        c2fb_temp_7 = local3
        local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_7 + 1)))
    Wend
    c2fb_flow_0:
    c2fb_temp_8 = @(local2->op)
    c2fb_temp_9 = Cast(UByte, local3)
    (*c2fb_temp_8) = Cast(u8, c2fb_temp_9)
    c2fb_temp_9 = Cast(UByte, (*c2fb_temp_8))
    c2fb_temp_10 = Cast(SQLITE_C_INT, whereClauseInsert(arg1, local2, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0001ULL)))))
    local4 = c2fb_temp_10
    exprAnalyze(arg0, arg1, local4)
End Sub

Private Sub exprAnalyzeOrTerm CDecl Alias "exprAnalyzeOrTerm" (ByVal arg0 As SqliteSrcListRecord Ptr, ByVal arg1 As SqliteWhereClauseRecord Ptr, ByVal arg2 As SQLITE_C_INT)
    Dim local0 As SqliteWhereInfoRecord Ptr
    Dim local1 As SqliteParseContext Ptr
    Dim local2 As sqlite3 Ptr
    Dim local3 As SqliteWhereTermRecord Ptr
    Dim local4 As SqliteExpr Ptr
    Dim local5 As SQLITE_C_INT
    Dim local6 As SqliteWhereClauseRecord Ptr
    Dim local7 As SqliteWhereTermRecord Ptr
    Dim local8 As SqliteWhereOrInfo Ptr
    Dim local9 As sqlite3_uint64
    Dim local10 As sqlite3_uint64
    Dim c2fb_temp_0 As SqliteWhereOrInfo Ptr
    Dim c2fb_temp_1 As Any Ptr Ptr
    Dim c2fb_temp_2 As SqliteWhereOrInfo Ptr
    Dim c2fb_temp_3 As u16 Ptr
    Dim c2fb_temp_4 As UShort
    Dim c2fb_temp_5 As SqliteWhereClauseRecord Ptr
    Dim c2fb_temp_6 As Any Ptr
    Dim c2fb_temp_7 As sqlite3_uint64
    Dim c2fb_temp_8 As sqlite3_uint64
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SqliteWhereTermRecord Ptr
    Dim local11 As SqliteWhereAndInfo Ptr
    Dim c2fb_temp_13 As sqlite3_uint64
    Dim c2fb_temp_14 As SqliteWhereAndInfo Ptr
    Dim local12 As SqliteWhereClauseRecord Ptr
    Dim local13 As SqliteWhereTermRecord Ptr
    Dim local14 As SQLITE_C_INT
    Dim local15 As sqlite3_uint64
    Dim c2fb_temp_15 As Any Ptr Ptr
    Dim c2fb_temp_16 As SqliteWhereAndInfo Ptr
    Dim c2fb_temp_17 As u16 Ptr
    Dim c2fb_temp_18 As UShort
    Dim c2fb_temp_19 As u16 Ptr
    Dim c2fb_temp_20 As UShort
    Dim c2fb_temp_21 As SQLITE_C_INT Ptr
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim c2fb_temp_23 As SqliteWhereClauseRecord Ptr
    Dim c2fb_temp_24 As Any Ptr
    Dim c2fb_temp_25 As SqliteWhereClause Ptr Ptr
    Dim c2fb_temp_26 As SqliteWhereClauseRecord Ptr
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim c2fb_temp_28 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_29 As SQLITE_C_INT
    Dim c2fb_temp_30 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_31 As sqlite3_uint64
    Dim c2fb_temp_32 As sqlite3_uint64
    Dim local16 As sqlite3_uint64
    Dim c2fb_temp_33 As sqlite3_uint64
    Dim local17 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_34 As sqlite3_uint64
    Dim c2fb_temp_35 As sqlite3_uint64
    Dim c2fb_temp_36 As sqlite3_uint64
    Dim c2fb_temp_37 As sqlite3_uint64
    Dim c2fb_temp_38 As sqlite3_uint64 Ptr
    Dim c2fb_temp_39 As sqlite3_uint64
    Dim c2fb_temp_40 As u16 Ptr
    Dim c2fb_temp_41 As UShort
    Dim c2fb_temp_42 As SQLITE_C_INT Ptr
    Dim c2fb_temp_43 As SQLITE_C_INT
    Dim c2fb_temp_44 As u8 Ptr
    Dim c2fb_temp_45 As UByte
    Dim local18 As SQLITE_C_INT
    Dim local19 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_46 As SQLITE_C_INT
    Dim c2fb_temp_47 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_48 As SQLITE_C_INT
    Dim c2fb_temp_49 As SqliteWhereTermRecord Ptr
    Dim local20 As SQLITE_C_INT
    Dim local21 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_50 As SQLITE_C_INT
    Dim c2fb_temp_51 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_52 As SQLITE_C_INT
    Dim c2fb_temp_53 As SqliteWhereTermRecord Ptr
    Dim local22 As SQLITE_C_INT
    Dim local23 As SQLITE_C_INT
    Dim local24 As SQLITE_C_INT
    Dim local25 As SQLITE_C_INT
    Dim c2fb_temp_54 As SQLITE_C_INT
    Dim c2fb_temp_55 As SQLITE_C_INT
    Dim local26 As SqliteExpr Ptr
    Dim c2fb_temp_56 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_57 As SQLITE_C_INT
    Dim c2fb_temp_58 As SQLITE_C_INT
    Dim c2fb_temp_59 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_60 As u16 Ptr
    Dim c2fb_temp_61 As UShort
    Dim c2fb_temp_62 As SQLITE_C_INT
    Dim c2fb_temp_63 As SQLITE_C_INT
    Dim c2fb_temp_64 As SqliteExpr Ptr
    Dim c2fb_temp_65 As SQLITE_C_INT
    Dim c2fb_temp_66 As SQLITE_C_INT
    Dim c2fb_temp_67 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_68 As u16 Ptr
    Dim c2fb_temp_69 As UShort
    Dim c2fb_temp_70 As SQLITE_C_INT
    Dim local27 As SQLITE_C_INT
    Dim local28 As SQLITE_C_INT
    Dim c2fb_temp_71 As SQLITE_C_INT
    Dim c2fb_temp_72 As SQLITE_C_INT
    Dim c2fb_temp_73 As SQLITE_C_INT
    Dim c2fb_temp_74 As u16 Ptr
    Dim c2fb_temp_75 As UShort
    Dim local29 As SqliteExpr Ptr
    Dim local30 As SqliteExprList Ptr
    Dim local31 As SqliteExpr Ptr
    Dim local32 As sqlite3CollSeq Ptr
    Dim local33 As SqliteExpr Ptr
    Dim c2fb_temp_76 As SQLITE_C_INT
    Dim c2fb_temp_77 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_78 As SQLITE_C_INT
    Dim c2fb_temp_79 As SqliteWhereTermRecord Ptr
    Dim local34 As SqliteExpr Ptr
    Dim c2fb_temp_80 As SqliteExpr Ptr
    Dim c2fb_temp_81 As SqliteExpr Ptr
    Dim c2fb_temp_82 As SqliteExprList Ptr
    Dim c2fb_temp_83 As SqliteExpr Ptr
    Dim c2fb_temp_84 As sqlite3CollSeq Ptr
    Dim c2fb_temp_85 As SqliteExpr Ptr
    Dim c2fb_temp_86 As SqliteExpr Ptr
    Dim c2fb_temp_87 As SqliteExpr Ptr
    Dim c2fb_temp_88 As SqliteExpr Ptr
    Dim c2fb_temp_89 As SqliteExpr Ptr
    Dim local35 As SQLITE_C_INT
    Dim c2fb_temp_90 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_91 As SqliteExprList Ptr
    Dim c2fb_temp_92 As SQLITE_C_INT

    local0 = CPtr(SqliteWhereInfoRecord Ptr, arg1->pWInfo)
    local1 = local0->pParse
    local2 = local1->db
    local3 = CPtr(SqliteWhereTermRecord Ptr, @(CPtr(SqliteWhereTermRecord Ptr, arg1->a)[arg2]))
    local4 = local3->pExpr
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_1 = @(local3->u.pOrInfo)
    c2fb_temp_0 = CPtr(SqliteWhereOrInfo Ptr, CPtr(Any Ptr, sqlite3DbMallocZero(CPtr(Any Ptr, local2), Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereOrInfo)))))
    local8 = c2fb_temp_0
    c2fb_temp_2 = c2fb_temp_0
    (*c2fb_temp_1) = CPtr(Any Ptr, c2fb_temp_2)
    c2fb_temp_2 = CPtr(SqliteWhereOrInfo Ptr, (*c2fb_temp_1))
    If (-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    c2fb_temp_3 = @(local3->wtFlags)
    c2fb_temp_4 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_3))) Or Cast(SQLITE_C_INT, &H0010ULL))))
    (*c2fb_temp_3) = Cast(u16, c2fb_temp_4)
    c2fb_temp_4 = Cast(UShort, (*c2fb_temp_3))
    c2fb_temp_5 = CPtr(SqliteWhereClauseRecord Ptr, @(local8->wc))
    local6 = c2fb_temp_5
    c2fb_temp_6 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteWhereTermRecord Ptr, (@local6->aStatic(0)))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, (Cast(SQLITE_C_INT, 8ULL) * SizeOf(SqliteWhereTermRecord)))))
    sqlite3WhereClauseInit(local6, local0)
    sqlite3WhereSplit(local6, local4, Cast(SQLITE_C_INT, 43ULL))
    sqlite3WhereExprAnalyze(arg0, local6)
    If local2->mallocFailed Then
        Return
    End If
    ' C unused-parameter annotation
    c2fb_temp_7 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (Not Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))
    local10 = c2fb_temp_7
    c2fb_temp_8 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (Not Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))
    local9 = c2fb_temp_8
    c2fb_temp_9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local6->nTerm - Cast(SQLITE_C_INT, 1ULL))))
    local5 = c2fb_temp_9
    c2fb_temp_10 = CPtr(SqliteWhereTermRecord Ptr, local6->a)
    local7 = c2fb_temp_10
    While (-Cast(SQLITE_C_INT, ((Cast(sqlite3_uint64, (-Cast(SQLITE_C_INT, ((local5 >= Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso local10))))
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local7->eOperator) And Cast(SQLITE_C_INT, &H01ffULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
            ' C automatic storage declaration
            ' C unused-parameter annotation
            c2fb_temp_13 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))
            local9 = c2fb_temp_13
            c2fb_temp_14 = CPtr(SqliteWhereAndInfo Ptr, CPtr(Any Ptr, sqlite3DbMallocRawNN(CPtr(Any Ptr, local2), Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereAndInfo)))))
            local11 = c2fb_temp_14
            If local11 Then
                ' C automatic storage declaration
                ' C automatic storage declaration
                ' C automatic storage declaration
                local15 = Cast(SQLITE_C_INT, &O0ULL)
                c2fb_temp_15 = @(local7->u.pAndInfo)
                c2fb_temp_16 = local11
                (*c2fb_temp_15) = CPtr(Any Ptr, c2fb_temp_16)
                c2fb_temp_16 = CPtr(SqliteWhereAndInfo Ptr, (*c2fb_temp_15))
                c2fb_temp_17 = @(local7->wtFlags)
                c2fb_temp_18 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_17))) Or Cast(SQLITE_C_INT, &H0020ULL))))
                (*c2fb_temp_17) = Cast(u16, c2fb_temp_18)
                c2fb_temp_18 = Cast(UShort, (*c2fb_temp_17))
                c2fb_temp_19 = @(local7->eOperator)
                c2fb_temp_20 = Cast(UShort, Cast(SQLITE_C_INT, &H0400ULL))
                (*c2fb_temp_19) = Cast(u16, c2fb_temp_20)
                c2fb_temp_20 = Cast(UShort, (*c2fb_temp_19))
                c2fb_temp_21 = @(local7->leftCursor)
                c2fb_temp_22 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
                (*c2fb_temp_21) = c2fb_temp_22
                c2fb_temp_23 = CPtr(SqliteWhereClauseRecord Ptr, @(local11->wc))
                local12 = c2fb_temp_23
                c2fb_temp_24 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteWhereTermRecord Ptr, (@local12->aStatic(0)))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, (Cast(SQLITE_C_INT, 8ULL) * SizeOf(SqliteWhereTermRecord)))))
                sqlite3WhereClauseInit(local12, CPtr(SqliteWhereInfoRecord Ptr, arg1->pWInfo))
                sqlite3WhereSplit(local12, local7->pExpr, Cast(SQLITE_C_INT, 44ULL))
                sqlite3WhereExprAnalyze(arg0, local12)
                c2fb_temp_25 = @(local12->pOuter)
                c2fb_temp_26 = arg1
                (*c2fb_temp_25) = CPtr(SqliteWhereClause Ptr, c2fb_temp_26)
                c2fb_temp_26 = CPtr(SqliteWhereClauseRecord Ptr, (*c2fb_temp_25))
                If (-Cast(SQLITE_C_INT, (local2->mallocFailed = 0))) Then
                    c2fb_temp_27 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    local14 = c2fb_temp_27
                    c2fb_temp_28 = CPtr(SqliteWhereTermRecord Ptr, local12->a)
                    local13 = c2fb_temp_28
                    While (-Cast(SQLITE_C_INT, ((local14 < local12->nTerm))))
                        ' C unused-parameter annotation
                        If (-Cast(SQLITE_C_INT, ((allowedOp(local13->pExpr->op) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local13->eOperator) = Cast(SQLITE_C_INT, &H0040ULL))))))))) Then
                            c2fb_temp_31 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local15 Or sqlite3WhereGetMask(CPtr(SqliteWhereMaskSet Ptr, @(local0->sMaskSet)), local13->leftCursor))))
                            local15 = c2fb_temp_31
                        End If
                    c2fb_flow_3:
                        c2fb_temp_29 = local14
                        local14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_29 + 1)))
                        c2fb_temp_30 = local13
                        local13 = (c2fb_temp_30 + 1)
                    Wend
                    c2fb_flow_2:
                End If
                c2fb_temp_32 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local10 And local15)))
                local10 = c2fb_temp_32
            End If
        Else
            If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local7->wtFlags) And Cast(SQLITE_C_INT, &H0008ULL))) Then
                ' empty C block
            Else
                ' C automatic storage declaration
                c2fb_temp_33 = Cast(sqlite3_uint64, sqlite3WhereGetMask(CPtr(SqliteWhereMaskSet Ptr, @(local0->sMaskSet)), local7->leftCursor))
                local16 = c2fb_temp_33
                If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local7->wtFlags) And Cast(SQLITE_C_INT, &H0002ULL))) Then
                    local17 = CPtr(SqliteWhereTermRecord Ptr, @(CPtr(SqliteWhereTermRecord Ptr, local6->a)[local7->iParent]))
                    c2fb_temp_34 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local16 Or sqlite3WhereGetMask(CPtr(SqliteWhereMaskSet Ptr, @(local0->sMaskSet)), local17->leftCursor))))
                    local16 = c2fb_temp_34
                End If
                c2fb_temp_35 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local10 And local16)))
                local10 = c2fb_temp_35
                If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local7->eOperator) And Cast(SQLITE_C_INT, &H0002ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_36 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))
                    local9 = c2fb_temp_36
                Else
                    c2fb_temp_37 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local9 And local16)))
                    local9 = c2fb_temp_37
                End If
            End If
        End If
    c2fb_flow_1:
        c2fb_temp_11 = local5
        local5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_11 - 1)))
        c2fb_temp_12 = local7
        local7 = (c2fb_temp_12 + 1)
    Wend
    c2fb_flow_0:
    c2fb_temp_38 = @(local8->indexable)
    c2fb_temp_39 = Cast(sqlite3_uint64, local10)
    (*c2fb_temp_38) = c2fb_temp_39
    c2fb_temp_40 = @(local3->eOperator)
    c2fb_temp_41 = Cast(UShort, Cast(SQLITE_C_INT, &H0200ULL))
    (*c2fb_temp_40) = Cast(u16, c2fb_temp_41)
    c2fb_temp_41 = Cast(UShort, (*c2fb_temp_40))
    c2fb_temp_42 = @(local3->leftCursor)
    c2fb_temp_43 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
    (*c2fb_temp_42) = c2fb_temp_43
    If local10 Then
        c2fb_temp_44 = @(arg1->hasOr)
        c2fb_temp_45 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
        (*c2fb_temp_44) = Cast(u8, c2fb_temp_45)
        c2fb_temp_45 = Cast(UByte, (*c2fb_temp_44))
    End If
    If (-Cast(SQLITE_C_INT, ((local10 AndAlso Cast(sqlite3_uint64, (-Cast(SQLITE_C_INT, ((local6->nTerm = Cast(SQLITE_C_INT, 2ULL)))))))))) Then
        local18 = Cast(SQLITE_C_INT, &O0ULL)
        ' C automatic storage declaration
        Do
            c2fb_temp_47 = CPtr(SqliteWhereTermRecord Ptr, @(CPtr(SqliteWhereTermRecord Ptr, local6->a)[Cast(SQLITE_C_INT, &O0ULL)]))
            c2fb_temp_46 = local18
            local18 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_46 + 1)))
            c2fb_temp_48 = c2fb_temp_46
            c2fb_temp_49 = CPtr(SqliteWhereTermRecord Ptr, whereNthSubterm(c2fb_temp_47, c2fb_temp_48))
            local19 = c2fb_temp_49
            If ((-Cast(SQLITE_C_INT, (((c2fb_temp_49) <> Cast(SQLITE_C_INT, &O0ULL))))) = 0) Then Goto c2fb_flow_4
            local20 = Cast(SQLITE_C_INT, &O0ULL)
            ' C automatic storage declaration
            Do
                c2fb_temp_51 = CPtr(SqliteWhereTermRecord Ptr, @(CPtr(SqliteWhereTermRecord Ptr, local6->a)[Cast(SQLITE_C_INT, 1ULL)]))
                c2fb_temp_50 = local20
                local20 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_50 + 1)))
                c2fb_temp_52 = c2fb_temp_50
                c2fb_temp_53 = CPtr(SqliteWhereTermRecord Ptr, whereNthSubterm(c2fb_temp_51, c2fb_temp_52))
                local21 = c2fb_temp_53
                If ((-Cast(SQLITE_C_INT, (((c2fb_temp_53) <> Cast(SQLITE_C_INT, &O0ULL))))) = 0) Then Goto c2fb_flow_6
                whereCombineDisjuncts(arg0, arg1, local19, local21)
            c2fb_flow_7:
            Loop
            c2fb_flow_6:
        c2fb_flow_5:
        Loop
        c2fb_flow_4:
    End If
    If local9 Then
        local22 = Cast(SQLITE_C_INT, &O0ULL)
        local23 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))
        local24 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))
        local25 = Cast(SQLITE_C_INT, &O0ULL)
        c2fb_temp_54 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local25 = c2fb_temp_54
        While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local25 < Cast(SQLITE_C_INT, 2ULL))))) AndAlso (-Cast(SQLITE_C_INT, (local22 = 0)))))))
            local26 = Cast(SQLITE_C_INT, &O0ULL)
            c2fb_temp_56 = CPtr(SqliteWhereTermRecord Ptr, local6->a)
            local7 = c2fb_temp_56
            c2fb_temp_57 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local6->nTerm - Cast(SQLITE_C_INT, 1ULL))))
            local5 = c2fb_temp_57
            While (-Cast(SQLITE_C_INT, ((local5 >= Cast(SQLITE_C_INT, &O0ULL)))))
                ' C unused-parameter annotation
                c2fb_temp_60 = @(local7->wtFlags)
                c2fb_temp_61 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_60))) And Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, &H0040ULL))))))
                (*c2fb_temp_60) = Cast(u16, c2fb_temp_61)
                c2fb_temp_61 = Cast(UShort, (*c2fb_temp_60))
                If (-Cast(SQLITE_C_INT, ((local7->leftCursor = local24)))) Then
                    ' C unused-parameter annotation
                    Goto c2fb_flow_11
                End If
                If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local9 And sqlite3WhereGetMask(CPtr(SqliteWhereMaskSet Ptr, @(local0->sMaskSet)), local7->leftCursor)))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                    ' empty C statement
                    ' empty C statement
                    ' C unused-parameter annotation
                    Goto c2fb_flow_11
                End If
                ' C unused-parameter annotation
                c2fb_temp_62 = Cast(SQLITE_C_INT, local7->u.x.leftColumn)
                local23 = c2fb_temp_62
                c2fb_temp_63 = Cast(SQLITE_C_INT, local7->leftCursor)
                local24 = c2fb_temp_63
                c2fb_temp_64 = local7->pExpr->pLeft
                local26 = c2fb_temp_64
                Goto c2fb_flow_10
            c2fb_flow_11:
                c2fb_temp_58 = local5
                local5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_58 - 1)))
                c2fb_temp_59 = local7
                local7 = (c2fb_temp_59 + 1)
            Wend
            c2fb_flow_10:
            If (-Cast(SQLITE_C_INT, ((local5 < Cast(SQLITE_C_INT, &O0ULL))))) Then
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                Goto c2fb_flow_8
            End If
            ' empty C statement
            c2fb_temp_65 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
            local22 = c2fb_temp_65
            While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local5 >= Cast(SQLITE_C_INT, &O0ULL))))) AndAlso local22))))
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, ((local7->leftCursor <> local24)))) Then
                    c2fb_temp_68 = @(local7->wtFlags)
                    c2fb_temp_69 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_68))) And Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, &H0040ULL))))))
                    (*c2fb_temp_68) = Cast(u16, c2fb_temp_69)
                    c2fb_temp_69 = Cast(UShort, (*c2fb_temp_68))
                Else
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local7->u.x.leftColumn <> local23)))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local23 = (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 2ULL)))))))) AndAlso sqlite3ExprCompare(CPtr(Any Ptr, local1), CPtr(Any Ptr, local7->pExpr->pLeft), CPtr(Any Ptr, local26), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))))))))))) Then
                        c2fb_temp_70 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                        local22 = c2fb_temp_70
                    Else
                        ' C automatic storage declaration
                        ' C automatic storage declaration
                        c2fb_temp_71 = Cast(SQLITE_C_INT, sqlite3ExprAffinity(CPtr(Any Ptr, local7->pExpr->pRight)))
                        local28 = c2fb_temp_71
                        c2fb_temp_72 = Cast(SQLITE_C_INT, sqlite3ExprAffinity(CPtr(Any Ptr, local7->pExpr->pLeft)))
                        local27 = c2fb_temp_72
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local28 <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local28 <> local27)))))))) Then
                            c2fb_temp_73 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                            local22 = c2fb_temp_73
                        Else
                            c2fb_temp_74 = @(local7->wtFlags)
                            c2fb_temp_75 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_74))) Or Cast(SQLITE_C_INT, &H0040ULL))))
                            (*c2fb_temp_74) = Cast(u16, c2fb_temp_75)
                            c2fb_temp_75 = Cast(UShort, (*c2fb_temp_74))
                        End If
                    End If
                End If
            c2fb_flow_13:
                c2fb_temp_66 = local5
                local5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_66 - 1)))
                c2fb_temp_67 = local7
                local7 = (c2fb_temp_67 + 1)
            Wend
            c2fb_flow_12:
        c2fb_flow_9:
            c2fb_temp_55 = local25
            local25 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_55 + 1)))
        Wend
        c2fb_flow_8:
        If local22 Then
            ' C automatic storage declaration
            local30 = Cast(SQLITE_C_INT, &O0ULL)
            local31 = Cast(SQLITE_C_INT, &O0ULL)
            local32 = Cast(SQLITE_C_INT, &O0ULL)
            ' C automatic storage declaration
            c2fb_temp_76 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local6->nTerm - Cast(SQLITE_C_INT, 1ULL))))
            local5 = c2fb_temp_76
            c2fb_temp_77 = CPtr(SqliteWhereTermRecord Ptr, local6->a)
            local7 = c2fb_temp_77
            While (-Cast(SQLITE_C_INT, ((local5 >= Cast(SQLITE_C_INT, &O0ULL)))))
                ' C automatic storage declaration
                If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local7->wtFlags) And Cast(SQLITE_C_INT, &H0040ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    Goto c2fb_flow_15
                End If
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                c2fb_temp_80 = local7->pExpr
                local34 = c2fb_temp_80
                c2fb_temp_81 = CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local2), CPtr(Any Ptr, local34->pRight), Cast(SQLITE_C_INT, &O0ULL)))
                local29 = c2fb_temp_81
                c2fb_temp_82 = CPtr(SqliteExprList Ptr, sqlite3ExprListAppend(CPtr(Any Ptr, local0->pParse), CPtr(Any Ptr, local30), CPtr(Any Ptr, local29)))
                local30 = c2fb_temp_82
                If (-Cast(SQLITE_C_INT, ((local31 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_83 = local34->pLeft
                    local31 = c2fb_temp_83
                    c2fb_temp_84 = CPtr(sqlite3CollSeq Ptr, sqlite3ExprCompareCollSeq(CPtr(Any Ptr, local1), CPtr(Any Ptr, local34)))
                    local32 = c2fb_temp_84
                Else
                    ' C unused-parameter annotation
                    If (-Cast(SQLITE_C_INT, ((local32 <> CPtr(sqlite3CollSeq Ptr, sqlite3ExprCompareCollSeq(CPtr(Any Ptr, local1), CPtr(Any Ptr, local34))))))) Then
                        c2fb_temp_85 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                        local31 = c2fb_temp_85
                        Goto c2fb_flow_14
                    End If
                End If
            c2fb_flow_15:
                c2fb_temp_78 = local5
                local5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_78 - 1)))
                c2fb_temp_79 = local7
                local7 = (c2fb_temp_79 + 1)
            Wend
            c2fb_flow_14:
            If (-Cast(SQLITE_C_INT, ((local31 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_86 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                local33 = c2fb_temp_86
            Else
                c2fb_temp_87 = CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local2), CPtr(Any Ptr, local31), Cast(SQLITE_C_INT, &O0ULL)))
                local29 = c2fb_temp_87
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((CPtr(sqlite3CollSeq Ptr, sqlite3ExprCollSeq(CPtr(Any Ptr, local1), CPtr(Any Ptr, local29))) <> local32)))) AndAlso ((-Cast(SQLITE_C_INT, ((local32 <> Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
                    ' C unused-parameter annotation
                    c2fb_temp_88 = CPtr(SqliteExpr Ptr, sqlite3ExprAddCollateString(CPtr(Any Ptr, local1), CPtr(Any Ptr, local29), CPtr(Const ZString Ptr, local32->zName)))
                    local29 = c2fb_temp_88
                End If
                c2fb_temp_89 = CPtr(SqliteExpr Ptr, sqlite3PExpr(CPtr(Any Ptr, local1), Cast(SQLITE_C_INT, 50ULL), CPtr(Any Ptr, local29), Cast(SQLITE_C_INT, &O0ULL)))
                local33 = c2fb_temp_89
            End If
            If local33 Then
                ' C automatic storage declaration
                transferJoinMarkings(local33, local4)
                ' C unused-parameter annotation
                c2fb_temp_90 = @(local33->x.pList)
                c2fb_temp_91 = local30
                (*c2fb_temp_90) = c2fb_temp_91
                c2fb_temp_92 = Cast(SQLITE_C_INT, whereClauseInsert(arg1, local33, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0001ULL)))))
                local35 = c2fb_temp_92
                ' empty C statement
                exprAnalyze(arg0, arg1, local35)
                markTermAsChild(arg1, local35, arg2)
            Else
                sqlite3ExprListDelete(CPtr(Any Ptr, local2), CPtr(Any Ptr, local30))
            End If
        End If
    End If
End Sub

Private Function termIsEquivalence CDecl Alias "termIsEquivalence" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SqliteSrcListRecord Ptr) As SQLITE_C_INT
    Dim local0 As Byte
    Dim local1 As Byte
    Dim c2fb_temp_0 As Byte
    Dim c2fb_temp_1 As Byte

    ' C automatic storage declaration
    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg0->db)->dbOptFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H00000080ULL)))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) <> Cast(SQLITE_C_INT, 54ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) <> Cast(SQLITE_C_INT, 45ULL))))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000001ULL) Or Cast(SQLITE_C_INT, &H000200ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 45ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((arg2->nSrc >= Cast(SQLITE_C_INT, 2ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2->a(Cast(SQLITE_C_INT, &O0ULL)).fg.jointype) And Cast(SQLITE_C_INT, &H40ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = Cast(Byte, sqlite3ExprAffinity(CPtr(Any Ptr, arg1->pLeft)))
    local0 = c2fb_temp_0
    c2fb_temp_1 = Cast(Byte, sqlite3ExprAffinity(CPtr(Any Ptr, arg1->pRight)))
    local1 = c2fb_temp_1
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0) <> Cast(SQLITE_C_INT, local1))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local0)) >= Cast(SQLITE_C_INT, &H43ULL)))))) = 0))) OrElse (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local1)) >= Cast(SQLITE_C_INT, &H43ULL)))))) = 0)))))))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, (sqlite3ExprCollSeqMatch(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pLeft), CPtr(Any Ptr, arg1->pRight)) = 0))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    Return Cast(SQLITE_C_INT, 1ULL)
End Function

Private Function exprSelectUsage CDecl Alias "exprSelectUsage" (ByVal arg0 As SqliteWhereMaskSet Ptr, ByVal arg1 As SqliteSelect Ptr) As sqlite3_uint64
    Dim local0 As sqlite3_uint64
    Dim local1 As SqliteSrcListRecord Ptr
    Dim c2fb_temp_0 As sqlite3_uint64
    Dim c2fb_temp_1 As sqlite3_uint64
    Dim c2fb_temp_2 As sqlite3_uint64
    Dim c2fb_temp_3 As sqlite3_uint64
    Dim c2fb_temp_4 As sqlite3_uint64
    Dim local2 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As sqlite3_uint64
    Dim c2fb_temp_8 As sqlite3_uint64
    Dim c2fb_temp_9 As sqlite3_uint64
    Dim c2fb_temp_10 As SqliteSelect Ptr

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    While arg1
        local1 = CPtr(SqliteSrcListRecord Ptr, arg1->pSrc)
        c2fb_temp_0 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprListUsage(arg0, arg1->pEList))))
        local0 = c2fb_temp_0
        c2fb_temp_1 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprListUsage(arg0, arg1->pGroupBy))))
        local0 = c2fb_temp_1
        c2fb_temp_2 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprListUsage(arg0, arg1->pOrderBy))))
        local0 = c2fb_temp_2
        c2fb_temp_3 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprUsage(arg0, arg1->pWhere))))
        local0 = c2fb_temp_3
        c2fb_temp_4 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprUsage(arg0, arg1->pHaving))))
        local0 = c2fb_temp_4
        If ((-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, &O0ULL)))))) Then
            ' C automatic storage declaration
            c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local2 = c2fb_temp_5
            While (-Cast(SQLITE_C_INT, ((local2 < local1->nSrc))))
                If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->a(local2).fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                    c2fb_temp_7 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or exprSelectUsage(arg0, local1->a(local2).u4.pSubq->pSelect))))
                    local0 = c2fb_temp_7
                End If
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->a(local2).fg.flags) Shr 11) And Cast(SQLITE_C_UINT, &H1ULL))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_8 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprUsage(arg0, local1->a(local2).u3.pOn))))
                    local0 = c2fb_temp_8
                End If
                If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->a(local2).fg.flags) Shr 3) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                    c2fb_temp_9 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local0 Or sqlite3WhereExprListUsage(arg0, local1->a(local2).u1.pFuncArg))))
                    local0 = c2fb_temp_9
                End If
            c2fb_flow_3:
                c2fb_temp_6 = local2
                local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 + 1)))
            Wend
            c2fb_flow_2:
        End If
        c2fb_temp_10 = arg1->pPrior
        arg1 = c2fb_temp_10
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    Return local0
End Function

' c2fb skipped exprMightBeIndexed2: FreeBASIC body already exists
Private Function exprMightBeIndexed CDecl Alias "exprMightBeIndexed" (ByVal arg0 As SqliteSrcListRecord Ptr, ByVal arg1 As SQLITE_C_INT Ptr, ByVal arg2 As SqliteExpr Ptr, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteExpr Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim local1 As SqliteIndex Ptr
    Dim c2fb_temp_7 As SqliteIndex Ptr
    Dim c2fb_temp_8 As SqliteIndex Ptr

    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg2->op) = Cast(SQLITE_C_INT, 177ULL))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg3 >= Cast(SQLITE_C_INT, 55ULL))))) AndAlso ((-Cast(SQLITE_C_INT, ((arg3 <= Cast(SQLITE_C_INT, 58ULL))))))))))))))) Then
        ' C unused-parameter annotation
        c2fb_temp_0 = arg2->x.pList->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr
        arg2 = c2fb_temp_0
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg2->op) = Cast(SQLITE_C_INT, 168ULL))))) Then
        c2fb_temp_1 = @(arg1[Cast(SQLITE_C_INT, &O0ULL)])
        c2fb_temp_2 = Cast(SQLITE_C_INT, arg2->iTable)
        (*c2fb_temp_1) = c2fb_temp_2
        c2fb_temp_3 = @(arg1[Cast(SQLITE_C_INT, 1ULL)])
        c2fb_temp_4 = Cast(SQLITE_C_INT, arg2->iColumn)
        (*c2fb_temp_3) = c2fb_temp_4
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_5
    While (-Cast(SQLITE_C_INT, ((local0 < arg0->nSrc))))
        ' C automatic storage declaration
        c2fb_temp_7 = CPtr(SqliteIndex Ptr, arg0->a(local0).pSTab->pIndex)
        local1 = c2fb_temp_7
        While local1
            If CPtr(SqliteExprList Ptr, local1->aColExpr) Then
                Return exprMightBeIndexed2(arg0, arg1, arg2, local0)
            End If
        c2fb_flow_3:
            c2fb_temp_8 = local1->pNext
            local1 = c2fb_temp_8
        Wend
        c2fb_flow_2:
    c2fb_flow_1:
        c2fb_temp_6 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 + 1)))
    Wend
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Sub exprAnalyze CDecl Alias "exprAnalyze" (ByVal arg0 As SqliteSrcListRecord Ptr, ByVal arg1 As SqliteWhereClauseRecord Ptr, ByVal arg2 As SQLITE_C_INT)
    Dim local0 As SqliteWhereInfoRecord Ptr
    Dim local1 As SqliteWhereTermRecord Ptr
    Dim local2 As SqliteWhereMaskSet Ptr
    Dim local3 As SqliteExpr Ptr
    Dim local4 As sqlite3_uint64
    Dim local5 As sqlite3_uint64
    Dim local6 As sqlite3_uint64
    Dim local7 As SqliteExpr Ptr
    Dim local8 As SQLITE_C_INT
    Dim local9 As SQLITE_C_INT
    Dim local10 As SQLITE_C_INT
    Dim local11 As SqliteParseContext Ptr
    Dim local12 As sqlite3 Ptr
    Dim local13 As UByte
    Dim local14 As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_1 As SqliteWhereMaskSet Ptr
    Dim c2fb_temp_2 As SqliteExpr Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As sqlite3_uint64
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As sqlite3_uint64 Ptr
    Dim c2fb_temp_8 As sqlite3_uint64
    Dim c2fb_temp_9 As sqlite3_uint64 Ptr
    Dim c2fb_temp_10 As sqlite3_uint64
    Dim c2fb_temp_11 As sqlite3_uint64
    Dim c2fb_temp_12 As sqlite3_uint64 Ptr
    Dim c2fb_temp_13 As sqlite3_uint64
    Dim c2fb_temp_14 As sqlite3_uint64
    Dim c2fb_temp_15 As sqlite3_uint64
    Dim c2fb_temp_16 As u16 Ptr
    Dim c2fb_temp_17 As UShort
    Dim local15 As sqlite3_uint64
    Dim c2fb_temp_18 As sqlite3_uint64
    Dim c2fb_temp_19 As sqlite3_uint64
    Dim c2fb_temp_20 As u32 Ptr
    Dim c2fb_temp_21 As SQLITE_C_UINT
    Dim c2fb_temp_22 As sqlite3_uint64 Ptr
    Dim c2fb_temp_23 As sqlite3_uint64
    Dim c2fb_temp_24 As SQLITE_C_INT Ptr
    Dim c2fb_temp_25 As SQLITE_C_INT
    Dim c2fb_temp_26 As SQLITE_C_INT Ptr
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim c2fb_temp_28 As u16 Ptr
    Dim c2fb_temp_29 As UShort
    Dim local16(0 To 1) As SQLITE_C_INT
    Dim local17 As SqliteExpr Ptr
    Dim local18 As SqliteExpr Ptr
    Dim local19 As UShort
    Dim c2fb_temp_30 As SqliteExpr Ptr
    Dim c2fb_temp_31 As SQLITE_C_INT Ptr
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As SQLITE_C_INT Ptr
    Dim c2fb_temp_34 As SQLITE_C_INT
    Dim c2fb_temp_35 As u16 Ptr
    Dim c2fb_temp_36 As UShort
    Dim c2fb_temp_37 As u16 Ptr
    Dim c2fb_temp_38 As UShort
    Dim local20 As SqliteWhereTermRecord Ptr
    Dim local21 As SqliteExpr Ptr
    Dim local22 As UShort
    Dim local23 As SQLITE_C_INT
    Dim c2fb_temp_39 As SqliteExpr Ptr
    Dim c2fb_temp_40 As SQLITE_C_INT
    Dim c2fb_temp_41 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_42 As u16 Ptr
    Dim c2fb_temp_43 As UShort
    Dim c2fb_temp_44 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_45 As u16 Ptr
    Dim c2fb_temp_46 As UShort
    Dim c2fb_temp_47 As u16 Ptr
    Dim c2fb_temp_48 As UShort
    Dim c2fb_temp_49 As UShort
    Dim c2fb_temp_50 As SqliteExpr Ptr
    Dim c2fb_temp_51 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_52 As u16 Ptr
    Dim c2fb_temp_53 As UShort
    Dim c2fb_temp_54 As SQLITE_C_INT Ptr
    Dim c2fb_temp_55 As SQLITE_C_INT
    Dim c2fb_temp_56 As SQLITE_C_INT Ptr
    Dim c2fb_temp_57 As SQLITE_C_INT
    Dim c2fb_temp_58 As sqlite3_uint64 Ptr
    Dim c2fb_temp_59 As sqlite3_uint64
    Dim c2fb_temp_60 As sqlite3_uint64 Ptr
    Dim c2fb_temp_61 As sqlite3_uint64
    Dim c2fb_temp_62 As u16 Ptr
    Dim c2fb_temp_63 As UShort
    Dim c2fb_temp_64 As u8 Ptr
    Dim c2fb_temp_65 As UByte
    Dim c2fb_temp_66 As UByte Ptr Ptr
    Dim c2fb_temp_67 As ZString Ptr
    Dim c2fb_temp_68 As u32 Ptr
    Dim c2fb_temp_69 As SQLITE_C_UINT
    Dim c2fb_temp_70 As sqlite3_uint64 Ptr
    Dim c2fb_temp_71 As sqlite3_uint64
    Dim c2fb_temp_72 As u16 Ptr
    Dim c2fb_temp_73 As UShort
    Dim local24 As SqliteExprList Ptr
    Dim local25 As SQLITE_C_INT
    Static local26(0 To 1) As UByte = {Cast(UByte, Cast(SQLITE_C_INT, 58ULL)), Cast(UByte, Cast(SQLITE_C_INT, 56ULL))}
    Dim c2fb_temp_74 As SqliteExprList Ptr
    Dim c2fb_temp_75 As SQLITE_C_INT
    Dim c2fb_temp_76 As SQLITE_C_INT
    Dim local27 As SqliteExpr Ptr
    Dim local28 As SQLITE_C_INT
    Dim c2fb_temp_77 As SqliteExpr Ptr
    Dim c2fb_temp_78 As SQLITE_C_INT
    Dim c2fb_temp_79 As SqliteWhereTermRecord Ptr
    Dim local29 As SqliteExpr Ptr
    Dim c2fb_temp_80 As SqliteExpr Ptr
    Dim c2fb_temp_81 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_82 As SqliteExpr Ptr
    Dim c2fb_temp_83 As SqliteWhereTermRecord Ptr
    Dim local30 As SqliteExpr Ptr
    Dim local31 As SqliteExpr Ptr
    Dim local32 As SQLITE_C_INT
    Dim local33 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_84 As SqliteExpr Ptr
    Dim c2fb_temp_85 As SQLITE_C_INT
    Dim c2fb_temp_86 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_87 As sqlite3_uint64 Ptr
    Dim c2fb_temp_88 As sqlite3_uint64
    Dim c2fb_temp_89 As SQLITE_C_INT Ptr
    Dim c2fb_temp_90 As SQLITE_C_INT
    Dim c2fb_temp_91 As SQLITE_C_INT Ptr
    Dim c2fb_temp_92 As SQLITE_C_INT
    Dim c2fb_temp_93 As u16 Ptr
    Dim c2fb_temp_94 As UShort
    Dim c2fb_temp_95 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_96 As u16 Ptr
    Dim c2fb_temp_97 As UShort
    Dim c2fb_temp_98 As sqlite3_uint64 Ptr
    Dim c2fb_temp_99 As sqlite3_uint64
    Dim local34 As SqliteExpr Ptr
    Dim local35 As SqliteExpr Ptr
    Dim local36 As SqliteExpr Ptr
    Dim local37 As SqliteExpr Ptr
    Dim local38 As SQLITE_C_INT
    Dim local39 As SQLITE_C_INT
    Dim local40 As Const ZString Ptr
    Dim local41 As UShort
    Dim c2fb_temp_100 As SqliteExpr Ptr
    Dim c2fb_temp_101 As SqliteExpr Ptr
    Dim local42 As SQLITE_C_INT
    Dim local43 As Byte
    Dim c2fb_temp_102 As u16 Ptr
    Dim c2fb_temp_103 As UShort
    Dim c2fb_temp_104 As SQLITE_C_INT
    Dim c2fb_temp_105 As Byte
    Dim c2fb_temp_106 As SQLITE_C_INT
    Dim c2fb_temp_107 As UByte Ptr
    Dim c2fb_temp_108 As Byte
    Dim c2fb_temp_109 As UByte Ptr
    Dim c2fb_temp_110 As Byte
    Dim local44 As UByte Ptr
    Dim c2fb_temp_111 As UByte Ptr
    Dim c2fb_temp_112 As SQLITE_C_INT
    Dim c2fb_temp_113 As UByte Ptr
    Dim c2fb_temp_114 As UByte
    Dim c2fb_temp_115 As UByte Ptr
    Dim c2fb_temp_116 As UByte
    Dim c2fb_temp_117 As UByte Ptr
    Dim c2fb_temp_118 As UByte Ptr
    Dim c2fb_temp_119 As UByte
    Dim c2fb_temp_120 As Const ZString Ptr
    Dim c2fb_temp_121 As SqliteExpr Ptr
    Dim c2fb_temp_122 As SqliteExpr Ptr
    Dim c2fb_temp_123 As SQLITE_C_INT
    Dim c2fb_temp_124 As SqliteExpr Ptr
    Dim c2fb_temp_125 As SqliteExpr Ptr
    Dim c2fb_temp_126 As SQLITE_C_INT
    Dim c2fb_temp_127 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_128 As SQLITE_C_INT
    Dim c2fb_temp_129 As SQLITE_C_INT
    Dim local45 As SQLITE_C_INT
    Dim c2fb_temp_130 As SQLITE_C_INT
    Dim c2fb_temp_131 As SQLITE_C_INT
    Dim local46 As SQLITE_C_INT
    Dim local47 As SqliteExpr Ptr
    Dim local48 As SqliteExpr Ptr
    Dim local49 As SqliteExpr Ptr
    Dim c2fb_temp_132 As SqliteExpr Ptr
    Dim c2fb_temp_133 As SQLITE_C_INT
    Dim c2fb_temp_134 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_135 As u16 Ptr
    Dim c2fb_temp_136 As UShort
    Dim c2fb_temp_137 As u16 Ptr
    Dim c2fb_temp_138 As UShort
    Dim local50 As SQLITE_C_INT
    Dim c2fb_temp_139 As SQLITE_C_INT
    Dim c2fb_temp_140 As SQLITE_C_INT
    Dim local51 As SQLITE_C_INT
    Dim c2fb_temp_141 As SQLITE_C_INT
    Dim c2fb_temp_142 As SQLITE_C_INT Ptr
    Dim c2fb_temp_143 As SQLITE_C_INT
    Dim local52 As SqliteExpr Ptr
    Dim local53 As SqliteExpr Ptr
    Dim local54 As SQLITE_C_INT
    Dim c2fb_temp_144 As SQLITE_C_INT
    Dim local55 As SQLITE_C_INT
    Dim local56 As SqliteWhereTermRecord Ptr
    Dim local57 As sqlite3_uint64
    Dim local58 As sqlite3_uint64
    Dim c2fb_temp_145 As sqlite3_uint64
    Dim c2fb_temp_146 As sqlite3_uint64
    Dim local59 As SqliteExpr Ptr
    Dim c2fb_temp_147 As SqliteExpr Ptr
    Dim c2fb_temp_148 As u32 Ptr
    Dim c2fb_temp_149 As SQLITE_C_UINT
    Dim c2fb_temp_150 As SQLITE_C_INT Ptr
    Dim c2fb_temp_151 As SQLITE_C_INT
    Dim c2fb_temp_152 As SQLITE_C_INT
    Dim c2fb_temp_153 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_154 As sqlite3_uint64 Ptr
    Dim c2fb_temp_155 As sqlite3_uint64
    Dim c2fb_temp_156 As SQLITE_C_INT Ptr
    Dim c2fb_temp_157 As SQLITE_C_INT
    Dim c2fb_temp_158 As SQLITE_C_INT Ptr
    Dim c2fb_temp_159 As SQLITE_C_INT
    Dim c2fb_temp_160 As u16 Ptr
    Dim c2fb_temp_161 As UShort
    Dim c2fb_temp_162 As u8 Ptr
    Dim c2fb_temp_163 As UByte
    Dim c2fb_temp_164 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_165 As u16 Ptr
    Dim c2fb_temp_166 As UShort
    Dim c2fb_temp_167 As sqlite3_uint64 Ptr
    Dim c2fb_temp_168 As sqlite3_uint64
    Dim local60 As SqliteExpr Ptr
    Dim c2fb_temp_169 As SqliteExpr Ptr
    Dim c2fb_temp_170 As SqliteExpr Ptr
    Dim c2fb_temp_171 As SqliteWhereTermRecord Ptr
    Dim c2fb_temp_172 As sqlite3_uint64 Ptr
    Dim c2fb_temp_173 As sqlite3_uint64

    local0 = CPtr(SqliteWhereInfoRecord Ptr, arg1->pWInfo)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local6 = Cast(SQLITE_C_INT, &O0ULL)
    local7 = Cast(SQLITE_C_INT, &O0ULL)
    local8 = Cast(SQLITE_C_INT, &O0ULL)
    local9 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    local11 = local0->pParse
    local12 = local11->db
    local13 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    If local12->mallocFailed Then
        Return
    End If
    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(SqliteWhereTermRecord Ptr, @(CPtr(SqliteWhereTermRecord Ptr, arg1->a)[arg2]))
    local1 = c2fb_temp_0
    c2fb_temp_1 = CPtr(SqliteWhereMaskSet Ptr, @(local0->sMaskSet))
    local2 = c2fb_temp_1
    c2fb_temp_2 = local1->pExpr
    local3 = c2fb_temp_2
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_label_0:
    c2fb_temp_3 = @(local2->bVarSelect)
    c2fb_temp_4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_3) = c2fb_temp_4
    c2fb_temp_5 = Cast(sqlite3_uint64, sqlite3WhereExprUsage(local2, local3->pLeft))
    local4 = c2fb_temp_5
    c2fb_temp_6 = Cast(SQLITE_C_INT, local3->op)
    local10 = c2fb_temp_6
    If (-Cast(SQLITE_C_INT, ((local10 = Cast(SQLITE_C_INT, 50ULL))))) Then
        ' C unused-parameter annotation
        If sqlite3ExprCheckIN(CPtr(Any Ptr, local11), CPtr(Any Ptr, local3)) Then
            Return
        End If
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local3)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            c2fb_temp_7 = @(local1->prereqRight)
            c2fb_temp_8 = Cast(sqlite3_uint64, exprSelectUsage(local2, local3->x.pSelect))
            (*c2fb_temp_7) = c2fb_temp_8
        Else
            c2fb_temp_9 = @(local1->prereqRight)
            c2fb_temp_10 = Cast(sqlite3_uint64, sqlite3WhereExprListUsage(local2, local3->x.pList))
            (*c2fb_temp_9) = c2fb_temp_10
        End If
        c2fb_temp_11 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local4 Or local1->prereqRight)))
        local5 = c2fb_temp_11
    Else
        c2fb_temp_12 = @(local1->prereqRight)
        c2fb_temp_13 = Cast(sqlite3_uint64, sqlite3WhereExprUsage(local2, local3->pRight))
        (*c2fb_temp_12) = c2fb_temp_13
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local3->pLeft = Cast(SQLITE_C_INT, &O0ULL))))) OrElse ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local3)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H001000ULL) Or Cast(SQLITE_C_INT, &H040000ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) OrElse (-Cast(SQLITE_C_INT, ((local3->x.pList <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            c2fb_temp_14 = Cast(sqlite3_uint64, sqlite3WhereExprUsageNN(local2, local3))
            local5 = c2fb_temp_14
        Else
            c2fb_temp_15 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local4 Or local1->prereqRight)))
            local5 = c2fb_temp_15
        End If
    End If
    If local2->bVarSelect Then
        c2fb_temp_16 = @(local1->wtFlags)
        c2fb_temp_17 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_16))) Or Cast(SQLITE_C_INT, &H1000ULL))))
        (*c2fb_temp_16) = Cast(u16, c2fb_temp_17)
        c2fb_temp_17 = Cast(UShort, (*c2fb_temp_16))
    End If
    If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local3)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000001ULL) Or Cast(SQLITE_C_INT, &H000002ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
        local15 = sqlite3WhereGetMask(local2, local3->w.iJoin)
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local3)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000001ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            c2fb_temp_18 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local5 Or local15)))
            local5 = c2fb_temp_18
            c2fb_temp_19 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local15 - Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL)))))
            local6 = c2fb_temp_19
        Else
            If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local5 Shr Cast(SQLITE_C_INT, 1ULL)))) >= local15)))) Then
                c2fb_temp_20 = @((local3)->flags)
                c2fb_temp_21 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_20)) And Cast(SQLITE_C_UINT, (Not Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000002ULL))))))))
                (*c2fb_temp_20) = Cast(u32, c2fb_temp_21)
                c2fb_temp_21 = Cast(SQLITE_C_UINT, (*c2fb_temp_20))
            End If
        End If
    End If
    c2fb_temp_22 = @(local1->prereqAll)
    c2fb_temp_23 = Cast(sqlite3_uint64, local5)
    (*c2fb_temp_22) = c2fb_temp_23
    c2fb_temp_24 = @(local1->leftCursor)
    c2fb_temp_25 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
    (*c2fb_temp_24) = c2fb_temp_25
    c2fb_temp_26 = @(local1->iParent)
    c2fb_temp_27 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
    (*c2fb_temp_26) = c2fb_temp_27
    c2fb_temp_28 = @(local1->eOperator)
    c2fb_temp_29 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_28) = Cast(u16, c2fb_temp_29)
    c2fb_temp_29 = Cast(UShort, (*c2fb_temp_28))
    If allowedOp(local10) Then
        ' C automatic array storage
        local17 = CPtr(SqliteExpr Ptr, sqlite3ExprSkipCollate(CPtr(Any Ptr, local3->pLeft)))
        local18 = CPtr(SqliteExpr Ptr, sqlite3ExprSkipCollate(CPtr(Any Ptr, local3->pRight)))
        local19 = IIf((-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local1->prereqRight And local4))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, &H3fffULL), Cast(SQLITE_C_INT, &H0800ULL))
        If (-Cast(SQLITE_C_INT, ((local1->u.x.iField > Cast(SQLITE_C_INT, &O0ULL))))) Then
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_30 = local17->x.pList->a(Cast(SQLITE_C_INT, (local1->u.x.iField - Cast(SQLITE_C_INT, 1ULL)))).pExpr
            local17 = c2fb_temp_30
        End If
        If exprMightBeIndexed(arg0, CPtr(SQLITE_C_INT Ptr, (@local16(0))), local17, local10) Then
            c2fb_temp_31 = @(local1->leftCursor)
            c2fb_temp_32 = Cast(SQLITE_C_INT, local16(Cast(SQLITE_C_INT, &O0ULL)))
            (*c2fb_temp_31) = c2fb_temp_32
            ' C unused-parameter annotation
            c2fb_temp_33 = @(local1->u.x.leftColumn)
            c2fb_temp_34 = Cast(SQLITE_C_INT, local16(Cast(SQLITE_C_INT, 1ULL)))
            (*c2fb_temp_33) = c2fb_temp_34
            c2fb_temp_35 = @(local1->eOperator)
            c2fb_temp_36 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, operatorMask(local10)) And Cast(SQLITE_C_INT, local19))))
            (*c2fb_temp_35) = Cast(u16, c2fb_temp_36)
            c2fb_temp_36 = Cast(UShort, (*c2fb_temp_35))
        End If
        If (-Cast(SQLITE_C_INT, ((local10 = Cast(SQLITE_C_INT, 45ULL))))) Then
            c2fb_temp_37 = @(local1->wtFlags)
            c2fb_temp_38 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_37))) Or Cast(SQLITE_C_INT, &H0800ULL))))
            (*c2fb_temp_37) = Cast(u16, c2fb_temp_38)
            c2fb_temp_38 = Cast(UShort, (*c2fb_temp_37))
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local18 AndAlso exprMightBeIndexed(arg0, CPtr(SQLITE_C_INT Ptr, (@local16(0))), local18, local10))))) AndAlso (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local18)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000020ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))))))) Then
            ' C automatic storage declaration
            ' C automatic storage declaration
            local22 = Cast(SQLITE_C_INT, &O0ULL)
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, ((local1->leftCursor >= Cast(SQLITE_C_INT, &O0ULL))))) Then
                ' C automatic storage declaration
                c2fb_temp_39 = CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local12), CPtr(Any Ptr, local3), Cast(SQLITE_C_INT, &O0ULL)))
                local21 = c2fb_temp_39
                If local12->mallocFailed Then
                    sqlite3ExprDelete(CPtr(Any Ptr, local12), CPtr(Any Ptr, local21))
                    Return
                End If
                c2fb_temp_40 = Cast(SQLITE_C_INT, whereClauseInsert(arg1, local21, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0001ULL)))))
                local23 = c2fb_temp_40
                If (-Cast(SQLITE_C_INT, ((local23 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    Return
                End If
                c2fb_temp_41 = CPtr(SqliteWhereTermRecord Ptr, @(CPtr(SqliteWhereTermRecord Ptr, arg1->a)[local23]))
                local20 = c2fb_temp_41
                markTermAsChild(arg1, local23, arg2)
                If (-Cast(SQLITE_C_INT, ((local10 = Cast(SQLITE_C_INT, 45ULL))))) Then
                    c2fb_temp_42 = @(local20->wtFlags)
                    c2fb_temp_43 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_42))) Or Cast(SQLITE_C_INT, &H0800ULL))))
                    (*c2fb_temp_42) = Cast(u16, c2fb_temp_43)
                    c2fb_temp_43 = Cast(UShort, (*c2fb_temp_42))
                End If
                c2fb_temp_44 = CPtr(SqliteWhereTermRecord Ptr, @(CPtr(SqliteWhereTermRecord Ptr, arg1->a)[arg2]))
                local1 = c2fb_temp_44
                c2fb_temp_45 = @(local1->wtFlags)
                c2fb_temp_46 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_45))) Or Cast(SQLITE_C_INT, &H0008ULL))))
                (*c2fb_temp_45) = Cast(u16, c2fb_temp_46)
                c2fb_temp_46 = Cast(UShort, (*c2fb_temp_45))
                ' C unused-parameter annotation
                If termIsEquivalence(local11, local21, CPtr(SqliteSrcListRecord Ptr, local0->pTabList)) Then
                    c2fb_temp_47 = @(local1->eOperator)
                    c2fb_temp_48 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_47))) Or Cast(SQLITE_C_INT, &H0800ULL))))
                    (*c2fb_temp_47) = Cast(u16, c2fb_temp_48)
                    c2fb_temp_48 = Cast(UShort, (*c2fb_temp_47))
                    c2fb_temp_49 = Cast(UShort, Cast(SQLITE_C_INT, &H0800ULL))
                    local22 = c2fb_temp_49
                End If
            Else
                c2fb_temp_50 = local3
                local21 = c2fb_temp_50
                c2fb_temp_51 = local1
                local20 = c2fb_temp_51
            End If
            c2fb_temp_52 = @(local20->wtFlags)
            c2fb_temp_53 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_52))) Or Cast(SQLITE_C_INT, exprCommute(local11, local21)))))
            (*c2fb_temp_52) = Cast(u16, c2fb_temp_53)
            c2fb_temp_53 = Cast(UShort, (*c2fb_temp_52))
            c2fb_temp_54 = @(local20->leftCursor)
            c2fb_temp_55 = Cast(SQLITE_C_INT, local16(Cast(SQLITE_C_INT, &O0ULL)))
            (*c2fb_temp_54) = c2fb_temp_55
            ' C unused-parameter annotation
            c2fb_temp_56 = @(local20->u.x.leftColumn)
            c2fb_temp_57 = Cast(SQLITE_C_INT, local16(Cast(SQLITE_C_INT, 1ULL)))
            (*c2fb_temp_56) = c2fb_temp_57
            ' empty C statement
            c2fb_temp_58 = @(local20->prereqRight)
            c2fb_temp_59 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local4 Or local6)))
            (*c2fb_temp_58) = c2fb_temp_59
            c2fb_temp_60 = @(local20->prereqAll)
            c2fb_temp_61 = Cast(sqlite3_uint64, local5)
            (*c2fb_temp_60) = c2fb_temp_61
            c2fb_temp_62 = @(local20->eOperator)
            c2fb_temp_63 = Cast(UShort, Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, operatorMask(local21->op)) + Cast(SQLITE_C_INT, local22)))) And Cast(SQLITE_C_INT, local19))))
            (*c2fb_temp_62) = Cast(u16, c2fb_temp_63)
            c2fb_temp_63 = Cast(UShort, (*c2fb_temp_62))
        Else
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local10 = Cast(SQLITE_C_INT, 51ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local3)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000001ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = sqlite3ExprCanBeNull(CPtr(Any Ptr, local17)))))))))) Then
                ' C unused-parameter annotation
                c2fb_temp_64 = @(local3->op)
                c2fb_temp_65 = Cast(UByte, Cast(SQLITE_C_INT, 171ULL))
                (*c2fb_temp_64) = Cast(u8, c2fb_temp_65)
                c2fb_temp_65 = Cast(UByte, (*c2fb_temp_64))
                c2fb_temp_66 = @(local3->u.zToken)
                c2fb_temp_67 = CPtr(ZString Ptr, StrPtr(!"false"))
                (*c2fb_temp_66) = CPtr(UByte Ptr, c2fb_temp_67)
                c2fb_temp_67 = CPtr(ZString Ptr, (*c2fb_temp_66))
                c2fb_temp_68 = @((local3)->flags)
                c2fb_temp_69 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_68)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H20000000ULL))))))
                (*c2fb_temp_68) = Cast(u32, c2fb_temp_69)
                c2fb_temp_69 = Cast(SQLITE_C_UINT, (*c2fb_temp_68))
                c2fb_temp_70 = @(local1->prereqAll)
                c2fb_temp_71 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_70) = c2fb_temp_71
                c2fb_temp_72 = @(local1->eOperator)
                c2fb_temp_73 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_72) = Cast(u16, c2fb_temp_73)
                c2fb_temp_73 = Cast(UShort, (*c2fb_temp_72))
            End If
        End If
    Else
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->op) = Cast(SQLITE_C_INT, 49ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 44ULL))))))))) Then
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C static constant array storage
            ' C unused-parameter annotation
            c2fb_temp_74 = local3->x.pList
            local24 = c2fb_temp_74
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_75 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local25 = c2fb_temp_75
            While (-Cast(SQLITE_C_INT, ((local25 < Cast(SQLITE_C_INT, 2ULL)))))
                ' C automatic storage declaration
                ' C automatic storage declaration
                c2fb_temp_77 = CPtr(SqliteExpr Ptr, sqlite3PExpr(CPtr(Any Ptr, local11), local26(local25), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local12), CPtr(Any Ptr, local3->pLeft), Cast(SQLITE_C_INT, &O0ULL)))), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local12), CPtr(Any Ptr, local24->a(local25).pExpr), Cast(SQLITE_C_INT, &O0ULL))))))
                local27 = c2fb_temp_77
                transferJoinMarkings(local27, local3)
                c2fb_temp_78 = Cast(SQLITE_C_INT, whereClauseInsert(arg1, local27, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0001ULL)))))
                local28 = c2fb_temp_78
                ' empty C statement
                exprAnalyze(arg0, arg1, local28)
                c2fb_temp_79 = CPtr(SqliteWhereTermRecord Ptr, @(CPtr(SqliteWhereTermRecord Ptr, arg1->a)[arg2]))
                local1 = c2fb_temp_79
                markTermAsChild(arg1, local28, arg2)
            c2fb_flow_1:
                c2fb_temp_76 = local25
                local25 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_76 + 1)))
            Wend
            c2fb_flow_0:
        Else
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->op) = Cast(SQLITE_C_INT, 43ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local3)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000200ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))))))) Then
                local29 = CPtr(SqliteExpr Ptr, sqlite3ExprSimplifiedAndOr(CPtr(Any Ptr, local3)))
                If (-Cast(SQLITE_C_INT, ((local29 <> local3)))) Then
                    c2fb_temp_81 = @(local1->pExpr)
                    c2fb_temp_80 = CPtr(SqliteExpr Ptr, sqlite3ExprSkipCollateAndLikely(CPtr(Any Ptr, local29)))
                    local3 = c2fb_temp_80
                    c2fb_temp_82 = c2fb_temp_80
                    (*c2fb_temp_81) = c2fb_temp_82
                    Goto c2fb_label_0
                End If
                ' C unused-parameter annotation
                exprAnalyzeOrTerm(arg0, arg1, arg2)
                c2fb_temp_83 = CPtr(SqliteWhereTermRecord Ptr, @(CPtr(SqliteWhereTermRecord Ptr, arg1->a)[arg2]))
                local1 = c2fb_temp_83
            Else
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->op) = Cast(SQLITE_C_INT, 52ULL))))) Then
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->pLeft->op) = Cast(SQLITE_C_INT, 168ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->pLeft->iColumn) >= Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local3)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000001ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))))))) Then
                        ' C automatic storage declaration
                        local31 = local3->pLeft
                        ' C automatic storage declaration
                        ' C automatic storage declaration
                        c2fb_temp_84 = CPtr(SqliteExpr Ptr, sqlite3PExpr(CPtr(Any Ptr, local11), Cast(SQLITE_C_INT, 55ULL), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local12), CPtr(Any Ptr, local31), Cast(SQLITE_C_INT, &O0ULL)))), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, sqlite3ExprAlloc(CPtr(Any Ptr, local12), Cast(SQLITE_C_INT, 122ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL))))))
                        local30 = c2fb_temp_84
                        c2fb_temp_85 = Cast(SQLITE_C_INT, whereClauseInsert(arg1, local30, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0001ULL))) Or Cast(SQLITE_C_INT, &H0080ULL)))))
                        local32 = c2fb_temp_85
                        If local32 Then
                            c2fb_temp_86 = CPtr(SqliteWhereTermRecord Ptr, @(CPtr(SqliteWhereTermRecord Ptr, arg1->a)[local32]))
                            local33 = c2fb_temp_86
                            c2fb_temp_87 = @(local33->prereqRight)
                            c2fb_temp_88 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))
                            (*c2fb_temp_87) = c2fb_temp_88
                            c2fb_temp_89 = @(local33->leftCursor)
                            c2fb_temp_90 = Cast(SQLITE_C_INT, local31->iTable)
                            (*c2fb_temp_89) = c2fb_temp_90
                            c2fb_temp_91 = @(local33->u.x.leftColumn)
                            c2fb_temp_92 = Cast(SQLITE_C_INT, local31->iColumn)
                            (*c2fb_temp_91) = c2fb_temp_92
                            c2fb_temp_93 = @(local33->eOperator)
                            c2fb_temp_94 = Cast(UShort, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 55ULL) - Cast(SQLITE_C_INT, 54ULL))))))))
                            (*c2fb_temp_93) = Cast(u16, c2fb_temp_94)
                            c2fb_temp_94 = Cast(UShort, (*c2fb_temp_93))
                            markTermAsChild(arg1, local32, arg2)
                            c2fb_temp_95 = CPtr(SqliteWhereTermRecord Ptr, @(CPtr(SqliteWhereTermRecord Ptr, arg1->a)[arg2]))
                            local1 = c2fb_temp_95
                            c2fb_temp_96 = @(local1->wtFlags)
                            c2fb_temp_97 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_96))) Or Cast(SQLITE_C_INT, &H0008ULL))))
                            (*c2fb_temp_96) = Cast(u16, c2fb_temp_97)
                            c2fb_temp_97 = Cast(UShort, (*c2fb_temp_96))
                            c2fb_temp_98 = @(local33->prereqAll)
                            c2fb_temp_99 = Cast(sqlite3_uint64, local1->prereqAll)
                            (*c2fb_temp_98) = c2fb_temp_99
                        End If
                    End If
                Else
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->op) = Cast(SQLITE_C_INT, 172ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 44ULL))))))))) AndAlso isLikeOrGlob(local11, local3, CPtr(SqliteExpr Ptr Ptr, @(local7)), CPtr(SQLITE_C_INT Ptr, @(local8)), CPtr(SQLITE_C_INT Ptr, @(local9))))))) Then
                        ' C automatic storage declaration
                        ' C automatic storage declaration
                        ' C automatic storage declaration
                        ' C automatic storage declaration
                        ' C automatic storage declaration
                        ' C automatic storage declaration
                        ' C automatic storage declaration
                        local41 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0100ULL) Or Cast(SQLITE_C_INT, &H0002ULL))) Or Cast(SQLITE_C_INT, &H0001ULL)))
                        ' C unused-parameter annotation
                        c2fb_temp_100 = local3->x.pList->a(Cast(SQLITE_C_INT, 1ULL)).pExpr
                        local34 = c2fb_temp_100
                        c2fb_temp_101 = CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local12), CPtr(Any Ptr, local7), Cast(SQLITE_C_INT, &O0ULL)))
                        local35 = c2fb_temp_101
                        ' C unused-parameter annotation
                        ' C unused-parameter annotation
                        If (-Cast(SQLITE_C_INT, ((local9 AndAlso (-Cast(SQLITE_C_INT, (local11->db->mallocFailed = 0))))))) Then
                            ' C automatic storage declaration
                            ' C automatic storage declaration
                            c2fb_temp_102 = @(local1->wtFlags)
                            c2fb_temp_103 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_102))) Or Cast(SQLITE_C_INT, &H0400ULL))))
                            (*c2fb_temp_102) = Cast(u16, c2fb_temp_103)
                            c2fb_temp_103 = Cast(UShort, (*c2fb_temp_102))
                            c2fb_temp_104 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                            local42 = c2fb_temp_104
                            Do
                                c2fb_temp_105 = Cast(Byte, CPtr(Byte Ptr, CPtr(ZString Ptr, local7->u.zToken))[local42])
                                local43 = c2fb_temp_105
                                If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (c2fb_temp_105)) <> Cast(SQLITE_C_INT, &O0ULL))))) = 0) Then Goto c2fb_flow_2
                                c2fb_temp_107 = @(CPtr(Byte Ptr, CPtr(ZString Ptr, local7->u.zToken))[local42])
                                c2fb_temp_108 = Cast(Byte, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local43)) And Cast(SQLITE_C_INT, (Not (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, sqlite3CtypeMap(Cast(UByte, (local43)))) And Cast(SQLITE_C_INT, &H20ULL))))))))))
                                (*c2fb_temp_107) = Cast(UByte, c2fb_temp_108)
                                c2fb_temp_108 = Cast(Byte, (*c2fb_temp_107))
                                c2fb_temp_109 = @(CPtr(Byte Ptr, CPtr(ZString Ptr, local35->u.zToken))[local42])
                                c2fb_temp_110 = Cast(Byte, (sqlite3UpperToLower(Cast(UByte, (local43)))))
                                (*c2fb_temp_109) = Cast(UByte, c2fb_temp_110)
                                c2fb_temp_110 = Cast(Byte, (*c2fb_temp_109))
                            c2fb_flow_3:
                                c2fb_temp_106 = local42
                                local42 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_106 + 1)))
                            Loop
                            c2fb_flow_2:
                        End If
                        If (-Cast(SQLITE_C_INT, (local12->mallocFailed = 0))) Then
                            ' C automatic storage declaration
                            c2fb_temp_111 = CPtr(UByte Ptr, CPtr(Byte Ptr, @(CPtr(Byte Ptr, CPtr(ZString Ptr, local35->u.zToken))[Cast(SQLITE_C_INT, (sqlite3Strlen30(CPtr(Const ZString Ptr, CPtr(ZString Ptr, local35->u.zToken))) - Cast(SQLITE_C_INT, 1ULL)))])))
                            local44 = c2fb_temp_111
                            If local9 Then
                                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (*local44)) = Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 65) - Cast(SQLITE_C_INT, 1ULL))))))) Then
                                    c2fb_temp_112 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                                    local8 = c2fb_temp_112
                                End If
                                c2fb_temp_113 = @((*local44))
                                c2fb_temp_114 = Cast(UByte, sqlite3UpperToLower((*local44)))
                                (*c2fb_temp_113) = c2fb_temp_114
                            End If
                            While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (*local44)) = Cast(SQLITE_C_INT, &HBFULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local44 > CPtr(UByte Ptr, CPtr(ZString Ptr, local35->u.zToken))))))))))
                                c2fb_temp_115 = @((*local44))
                                c2fb_temp_116 = Cast(UByte, Cast(SQLITE_C_INT, &H80ULL))
                                (*c2fb_temp_115) = c2fb_temp_116
                                c2fb_temp_117 = local44
                                local44 = (c2fb_temp_117 - 1)
                            c2fb_flow_5:
                            Wend
                            c2fb_flow_4:
                            ' C unused-parameter annotation
                            c2fb_temp_118 = @(((*local44)))
                            c2fb_temp_119 = (*c2fb_temp_118)
                            (*c2fb_temp_118) = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_119) + 1)))
                        End If
                        c2fb_temp_120 = IIf(local9, StrPtr(!"NOCASE"), sqlite3StrBINARYName())
                        local40 = c2fb_temp_120
                        c2fb_temp_121 = CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local12), CPtr(Any Ptr, local34), Cast(SQLITE_C_INT, &O0ULL)))
                        local36 = c2fb_temp_121
                        c2fb_temp_122 = CPtr(SqliteExpr Ptr, sqlite3PExpr(CPtr(Any Ptr, local11), Cast(SQLITE_C_INT, 58ULL), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, sqlite3ExprAddCollateString(CPtr(Any Ptr, local11), CPtr(Any Ptr, local36), local40))), CPtr(Any Ptr, local7)))
                        local36 = c2fb_temp_122
                        transferJoinMarkings(local36, local3)
                        c2fb_temp_123 = Cast(SQLITE_C_INT, whereClauseInsert(arg1, local36, local41))
                        local38 = c2fb_temp_123
                        ' empty C statement
                        c2fb_temp_124 = CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local12), CPtr(Any Ptr, local34), Cast(SQLITE_C_INT, &O0ULL)))
                        local37 = c2fb_temp_124
                        c2fb_temp_125 = CPtr(SqliteExpr Ptr, sqlite3PExpr(CPtr(Any Ptr, local11), Cast(SQLITE_C_INT, 57ULL), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, sqlite3ExprAddCollateString(CPtr(Any Ptr, local11), CPtr(Any Ptr, local37), local40))), CPtr(Any Ptr, local35)))
                        local37 = c2fb_temp_125
                        transferJoinMarkings(local37, local3)
                        c2fb_temp_126 = Cast(SQLITE_C_INT, whereClauseInsert(arg1, local37, local41))
                        local39 = c2fb_temp_126
                        ' empty C statement
                        exprAnalyze(arg0, arg1, local38)
                        exprAnalyze(arg0, arg1, local39)
                        c2fb_temp_127 = CPtr(SqliteWhereTermRecord Ptr, @(CPtr(SqliteWhereTermRecord Ptr, arg1->a)[arg2]))
                        local1 = c2fb_temp_127
                        If local8 Then
                            markTermAsChild(arg1, local38, arg2)
                            markTermAsChild(arg1, local39, arg2)
                        End If
                    End If
                End If
            End If
        End If
    End If
    c2fb_temp_129 = 0
    If ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->op) = Cast(SQLITE_C_INT, 54ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->op) = Cast(SQLITE_C_INT, 45ULL)))))))))) Then
        c2fb_temp_128 = Cast(SQLITE_C_INT, sqlite3ExprVectorSize(CPtr(Any Ptr, local3->pLeft)))
        local14 = c2fb_temp_128
        c2fb_temp_129 = (-Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, (((c2fb_temp_128) > Cast(SQLITE_C_INT, 1ULL))))) <> 0)))
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((c2fb_temp_129 AndAlso (-Cast(SQLITE_C_INT, ((sqlite3ExprVectorSize(CPtr(Any Ptr, local3->pRight)) = local14)))))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local3->pLeft->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) OrElse (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local3->pRight->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 44ULL))))))))) Then
        ' C automatic storage declaration
        c2fb_temp_130 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local45 = c2fb_temp_130
        While (-Cast(SQLITE_C_INT, ((local45 < local14))))
            ' C automatic storage declaration
            ' C automatic storage declaration
            local48 = CPtr(SqliteExpr Ptr, sqlite3ExprForVectorField(CPtr(Any Ptr, local11), CPtr(Any Ptr, local3->pLeft), local45, local14))
            local49 = CPtr(SqliteExpr Ptr, sqlite3ExprForVectorField(CPtr(Any Ptr, local11), CPtr(Any Ptr, local3->pRight), local45, local14))
            c2fb_temp_132 = CPtr(SqliteExpr Ptr, sqlite3PExpr(CPtr(Any Ptr, local11), local3->op, CPtr(Any Ptr, local48), CPtr(Any Ptr, local49)))
            local47 = c2fb_temp_132
            transferJoinMarkings(local47, local3)
            c2fb_temp_133 = Cast(SQLITE_C_INT, whereClauseInsert(arg1, local47, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0001ULL) Or Cast(SQLITE_C_INT, &H8000ULL)))))
            local46 = c2fb_temp_133
            exprAnalyze(arg0, arg1, local46)
        c2fb_flow_7:
            c2fb_temp_131 = local45
            local45 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_131 + 1)))
        Wend
        c2fb_flow_6:
        c2fb_temp_134 = CPtr(SqliteWhereTermRecord Ptr, @(CPtr(SqliteWhereTermRecord Ptr, arg1->a)[arg2]))
        local1 = c2fb_temp_134
        c2fb_temp_135 = @(local1->wtFlags)
        c2fb_temp_136 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_135))) Or Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0004ULL) Or Cast(SQLITE_C_INT, &H0002ULL))))))
        (*c2fb_temp_135) = Cast(u16, c2fb_temp_136)
        c2fb_temp_136 = Cast(UShort, (*c2fb_temp_135))
        c2fb_temp_137 = @(local1->eOperator)
        c2fb_temp_138 = Cast(UShort, Cast(SQLITE_C_INT, &H2000ULL))
        (*c2fb_temp_137) = Cast(u16, c2fb_temp_138)
        c2fb_temp_138 = Cast(UShort, (*c2fb_temp_137))
    Else
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->op) = Cast(SQLITE_C_INT, 50ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local1->u.x.iField = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->pLeft->op) = Cast(SQLITE_C_INT, 177ULL))))))))) AndAlso (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local3)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))))) AndAlso ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, (-Cast(SQLITE_C_INT, ((local3->x.pSelect->pPrior = Cast(SQLITE_C_INT, &O0ULL)))))) OrElse (Cast(SQLITE_C_UINT, (local3->x.pSelect->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000200ULL)))))))))))))) AndAlso (-Cast(SQLITE_C_INT, (whereExprSelectHasNoWindow(local3->x.pSelect)))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local3->x.pSelect->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0001000ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 44ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(sqlite3_int64, local3->x.pSelect->pEList->nExpr) <= (Cast(sqlite3_int64, ((Cast(sqlite3_int64, ((Cast(sqlite3_int64, Cast(SQLITE_C_INT, 1ULL))) Shl (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(UByte))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL)))))))) - Cast(sqlite3_int64, Cast(SQLITE_C_INT, 1ULL))))))))))))) Then
            ' C automatic storage declaration
            ' C unused-parameter annotation
            c2fb_temp_139 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local50 = c2fb_temp_139
            While (-Cast(SQLITE_C_INT, ((local50 < sqlite3ExprVectorSize(CPtr(Any Ptr, local3->pLeft))))))
                ' C automatic storage declaration
                c2fb_temp_141 = Cast(SQLITE_C_INT, whereClauseInsert(arg1, local3, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H8000ULL)))))
                local51 = c2fb_temp_141
                c2fb_temp_142 = @(CPtr(SqliteWhereTermRecord Ptr, arg1->a)[local51].u.x.iField)
                c2fb_temp_143 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local50 + Cast(SQLITE_C_INT, 1ULL))))
                (*c2fb_temp_142) = c2fb_temp_143
                exprAnalyze(arg0, arg1, local51)
                markTermAsChild(arg1, local51, arg2)
            c2fb_flow_9:
                c2fb_temp_140 = local50
                local50 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_140 + 1)))
            Wend
            c2fb_flow_8:
        Else
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 44ULL))))) Then
                local52 = Cast(SQLITE_C_INT, &O0ULL)
                local53 = Cast(SQLITE_C_INT, &O0ULL)
                local54 = isAuxiliaryVtabOperator(local12, local3, CPtr(UByte Ptr, @(local13)), CPtr(SqliteExpr Ptr Ptr, @(local53)), CPtr(SqliteExpr Ptr Ptr, @(local52)))
                Do
                    c2fb_temp_144 = local54
                    local54 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_144 - 1)))
                    If ((-Cast(SQLITE_C_INT, ((c2fb_temp_144 > Cast(SQLITE_C_INT, &O0ULL))))) = 0) Then Goto c2fb_flow_10
                    ' C automatic storage declaration
                    ' C automatic storage declaration
                    ' C automatic storage declaration
                    ' C automatic storage declaration
                    c2fb_temp_145 = Cast(sqlite3_uint64, sqlite3WhereExprUsage(local2, local52))
                    local58 = c2fb_temp_145
                    c2fb_temp_146 = Cast(sqlite3_uint64, sqlite3WhereExprUsage(local2, local53))
                    local57 = c2fb_temp_146
                    If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local58 And local57))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                        ' C automatic storage declaration
                        c2fb_temp_147 = CPtr(SqliteExpr Ptr, sqlite3PExpr(CPtr(Any Ptr, local11), Cast(SQLITE_C_INT, 47ULL), Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local12), CPtr(Any Ptr, local52), Cast(SQLITE_C_INT, &O0ULL))))))
                        local59 = c2fb_temp_147
                        If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local3)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000001ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) AndAlso local59)))) Then
                            c2fb_temp_148 = @((local59)->flags)
                            c2fb_temp_149 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_148)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000001ULL))))))
                            (*c2fb_temp_148) = Cast(u32, c2fb_temp_149)
                            c2fb_temp_149 = Cast(SQLITE_C_UINT, (*c2fb_temp_148))
                            c2fb_temp_150 = @(local59->w.iJoin)
                            c2fb_temp_151 = Cast(SQLITE_C_INT, local3->w.iJoin)
                            (*c2fb_temp_150) = c2fb_temp_151
                        End If
                        c2fb_temp_152 = Cast(SQLITE_C_INT, whereClauseInsert(arg1, local59, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0001ULL)))))
                        local55 = c2fb_temp_152
                        ' empty C statement
                        c2fb_temp_153 = CPtr(SqliteWhereTermRecord Ptr, @(CPtr(SqliteWhereTermRecord Ptr, arg1->a)[local55]))
                        local56 = c2fb_temp_153
                        c2fb_temp_154 = @(local56->prereqRight)
                        c2fb_temp_155 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local58 Or local6)))
                        (*c2fb_temp_154) = c2fb_temp_155
                        c2fb_temp_156 = @(local56->leftCursor)
                        c2fb_temp_157 = Cast(SQLITE_C_INT, local53->iTable)
                        (*c2fb_temp_156) = c2fb_temp_157
                        c2fb_temp_158 = @(local56->u.x.leftColumn)
                        c2fb_temp_159 = Cast(SQLITE_C_INT, local53->iColumn)
                        (*c2fb_temp_158) = c2fb_temp_159
                        c2fb_temp_160 = @(local56->eOperator)
                        c2fb_temp_161 = Cast(UShort, Cast(SQLITE_C_INT, &H0040ULL))
                        (*c2fb_temp_160) = Cast(u16, c2fb_temp_161)
                        c2fb_temp_161 = Cast(UShort, (*c2fb_temp_160))
                        c2fb_temp_162 = @(local56->eMatchOp)
                        c2fb_temp_163 = Cast(UByte, local13)
                        (*c2fb_temp_162) = Cast(u8, c2fb_temp_163)
                        c2fb_temp_163 = Cast(UByte, (*c2fb_temp_162))
                        markTermAsChild(arg1, local55, arg2)
                        c2fb_temp_164 = CPtr(SqliteWhereTermRecord Ptr, @(CPtr(SqliteWhereTermRecord Ptr, arg1->a)[arg2]))
                        local1 = c2fb_temp_164
                        c2fb_temp_165 = @(local1->wtFlags)
                        c2fb_temp_166 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_165))) Or Cast(SQLITE_C_INT, &H0008ULL))))
                        (*c2fb_temp_165) = Cast(u16, c2fb_temp_166)
                        c2fb_temp_166 = Cast(UShort, (*c2fb_temp_165))
                        c2fb_temp_167 = @(local56->prereqAll)
                        c2fb_temp_168 = Cast(sqlite3_uint64, local1->prereqAll)
                        (*c2fb_temp_167) = c2fb_temp_168
                    End If
                    local60 = local53
                    c2fb_temp_169 = local52
                    local53 = c2fb_temp_169
                    c2fb_temp_170 = local60
                    local52 = c2fb_temp_170
                    ' empty C statement
                c2fb_flow_11:
                Loop
                c2fb_flow_10:
            End If
        End If
    End If
    ' empty C statement
    c2fb_temp_171 = CPtr(SqliteWhereTermRecord Ptr, @(CPtr(SqliteWhereTermRecord Ptr, arg1->a)[arg2]))
    local1 = c2fb_temp_171
    c2fb_temp_172 = @(local1->prereqRight)
    c2fb_temp_173 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, ((*c2fb_temp_172) Or local6)))
    (*c2fb_temp_172) = c2fb_temp_173
End Sub

' c2fb skipped sqlite3WhereSplit: FreeBASIC body already exists
' c2fb skipped whereAddLimitExpr: outside the supported subset
' c2fb skipped sqlite3WhereAddLimit: FreeBASIC body already exists
Sub sqlite3WhereClauseInit CDecl Alias "sqlite3WhereClauseInit" (ByVal arg0 As SqliteWhereClauseRecord Ptr, ByVal arg1 As SqliteWhereInfoRecord Ptr)
    Dim c2fb_temp_0 As SqliteWhereInfo Ptr Ptr
    Dim c2fb_temp_1 As SqliteWhereInfoRecord Ptr
    Dim c2fb_temp_2 As u8 Ptr
    Dim c2fb_temp_3 As UByte
    Dim c2fb_temp_4 As SqliteWhereClause Ptr Ptr
    Dim c2fb_temp_5 As SqliteWhereClauseRecord Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT Ptr
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT Ptr
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SqliteWhereTerm Ptr Ptr
    Dim c2fb_temp_13 As SqliteWhereTermRecord Ptr

    c2fb_temp_0 = @(arg0->pWInfo)
    c2fb_temp_1 = arg1
    (*c2fb_temp_0) = CPtr(SqliteWhereInfo Ptr, c2fb_temp_1)
    c2fb_temp_1 = CPtr(SqliteWhereInfoRecord Ptr, (*c2fb_temp_0))
    c2fb_temp_2 = @(arg0->hasOr)
    c2fb_temp_3 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_2) = Cast(u8, c2fb_temp_3)
    c2fb_temp_3 = Cast(UByte, (*c2fb_temp_2))
    c2fb_temp_4 = @(arg0->pOuter)
    c2fb_temp_5 = CPtr(SqliteWhereClauseRecord Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_4) = CPtr(SqliteWhereClause Ptr, c2fb_temp_5)
    c2fb_temp_5 = CPtr(SqliteWhereClauseRecord Ptr, (*c2fb_temp_4))
    c2fb_temp_6 = @(arg0->nTerm)
    c2fb_temp_7 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_6) = c2fb_temp_7
    c2fb_temp_8 = @(arg0->nBase)
    c2fb_temp_9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_8) = c2fb_temp_9
    c2fb_temp_10 = @(arg0->nSlot)
    c2fb_temp_11 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, (Cast(SQLITE_C_INT, 8ULL) * SizeOf(SqliteWhereTermRecord)))) \ Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereTermRecord)))))))))
    (*c2fb_temp_10) = c2fb_temp_11
    c2fb_temp_12 = @(arg0->a)
    c2fb_temp_13 = CPtr(SqliteWhereTermRecord Ptr, (@arg0->aStatic(0)))
    (*c2fb_temp_12) = CPtr(SqliteWhereTerm Ptr, c2fb_temp_13)
    c2fb_temp_13 = CPtr(SqliteWhereTermRecord Ptr, (*c2fb_temp_12))
End Sub

' c2fb skipped sqlite3WhereClauseClear: FreeBASIC body already exists
' c2fb skipped sqlite3WhereExprUsageFull: FreeBASIC body already exists
' c2fb skipped sqlite3WhereExprUsageNN: FreeBASIC body already exists
' c2fb skipped sqlite3WhereExprUsage: FreeBASIC body already exists
' c2fb skipped sqlite3WhereExprListUsage: FreeBASIC body already exists
Sub sqlite3WhereExprAnalyze CDecl Alias "sqlite3WhereExprAnalyze" (ByVal arg0 As SqliteSrcListRecord Ptr, ByVal arg1 As SqliteWhereClauseRecord Ptr)
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT

    ' C automatic storage declaration
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg1->nTerm - Cast(SQLITE_C_INT, 1ULL))))
    local0 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((local0 >= Cast(SQLITE_C_INT, &O0ULL)))))
        exprAnalyze(arg0, arg1, local0)
    c2fb_flow_1:
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 - 1)))
    Wend
    c2fb_flow_0:
End Sub

' c2fb skipped sqlite3WhereTabFuncArgs: FreeBASIC body already exists
' c2fb skipped sqlite3WhereLoopBloomable: FreeBASIC body already exists
/' end of sqlite3_bulk_whereexpr_analysis.bas '/
