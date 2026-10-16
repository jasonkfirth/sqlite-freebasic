/'
    Project: SQLite FreeBASIC port

    File: sqlite3_bulk_resolve_core.bas

    Purpose:

        Port the expression and SELECT resolution callbacks emitted by loose C2FB.

    Responsibilities:

        - Walk expressions and SELECT trees to resolve names and function calls.
        - Track aggregate, window, subtype, and resolver error state.
        - Preserve translated private helpers beside the resolver callbacks.

    This file intentionally does NOT contain:

        - The column-name lookup algorithm, which remains an unresolved helper.
        - Runtime validation of name-resolution behavior.
'/
/'
/*
** 2008 August 18
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
*************************************************************************
**
** This file contains routines used for walking the parser tree and
** resolve all identifiers by associating them with a particular
** table and column.
*/

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
#include once "sqlite3_walker.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_fp.bi"
#include once "sqlite3_resolve_types.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_result.bi"
#include once "sqlite3_schema_types.bi"
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
Declare Function sqlite3ResolveSelfReference CDecl Alias "sqlite3ResolveSelfReference" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr) As SQLITE_C_INT
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

Declare Function incrAggDepth CDecl Alias "incrAggDepth" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function areDoubleQuotedStringsEnabled CDecl Alias "areDoubleQuotedStringsEnabled" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteNameContext Ptr) As SQLITE_C_INT
Declare Sub extendFJMatch CDecl Alias "extendFJMatch" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExprList Ptr Ptr, ByVal arg2 As SqliteSrcItem Ptr, ByVal arg3 As Short)
Declare Sub notValidImpl CDecl Alias "notValidImpl" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteNameContext Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As SqliteExpr Ptr, ByVal arg4 As SqliteExpr Ptr)
Declare Function exprProbability CDecl Alias "exprProbability" (ByVal arg0 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function resolveExprStep CDecl Alias "resolveExprStep" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function resolveAsName CDecl Alias "resolveAsName" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExprList Ptr, ByVal arg2 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function resolveOrderByTermToExprList CDecl Alias "resolveOrderByTermToExprList" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Sub resolveOutOfRangeError CDecl Alias "resolveOutOfRangeError" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SqliteExpr Ptr)
Declare Function resolveCompoundOrderBy CDecl Alias "resolveCompoundOrderBy" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr) As SQLITE_C_INT
Declare Function sqlite3ResolveOrderGroupBy CDecl Alias "sqlite3ResolveOrderGroupBy" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteExprList Ptr, ByVal arg3 As Const ZString Ptr) As SQLITE_C_INT
Declare Function resolveRemoveWindowsCb CDecl Alias "resolveRemoveWindowsCb" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function resolveOrderGroupBy CDecl Alias "resolveOrderGroupBy" (ByVal arg0 As SqliteNameContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteExprList Ptr, ByVal arg3 As Const ZString Ptr) As SQLITE_C_INT
Declare Function resolveSelectStep CDecl Alias "resolveSelectStep" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteSelect Ptr) As SQLITE_C_INT
Declare Function sqlite3ResolveExprNames CDecl Alias "sqlite3ResolveExprNames" (ByVal arg0 As SqliteNameContext Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function sqlite3ResolveExprListNames CDecl Alias "sqlite3ResolveExprListNames" (ByVal arg0 As SqliteNameContext Ptr, ByVal arg1 As SqliteExprList Ptr) As SQLITE_C_INT
Declare Sub sqlite3ResolveSelectNames CDecl Alias "sqlite3ResolveSelectNames" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteNameContext Ptr)
Declare Function c2fb_crt_memset CDecl Alias "memset" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_SIZE_T) As Any Ptr
Declare Function c2fb_crt_strcmp CDecl Alias "strcmp" ( _
    ByVal leftText As Const ZString Ptr, _
    ByVal rightText As Const ZString Ptr _
) As SQLITE_C_INT
' c2fb skipped __bswap_16: outside the supported subset
' c2fb skipped __bswap_32: outside the supported subset
' c2fb skipped __bswap_64: outside the supported subset
' c2fb skipped __uint16_identity: outside the supported subset
' c2fb skipped __uint32_identity: outside the supported subset
' c2fb skipped __uint64_identity: outside the supported subset
' c2fb skipped sqlite3IsBinary: FreeBASIC body already exists

' c2fb skipped incrAggFunctionDepth: outside the supported subset
' c2fb skipped resolveAlias: outside the supported subset
' c2fb skipped sqlite3MatchEName: FreeBASIC body already exists

' c2fb skipped sqlite3ExprColUsed: FreeBASIC body already exists

' c2fb skipped isValidSchemaTableName: FreeBASIC body already exists
' c2fb skipped lookupName: outside the supported subset
' c2fb skipped sqlite3CreateColumnExpr: FreeBASIC body already exists


' c2fb skipped resolveSetExprSubtypeArg: FreeBASIC body already exists







' c2fb skipped windowRemoveExprFromSelect: outside the supported subset





' c2fb skipped sqlite3ResolveSelfReference: outside the supported subset
/' end of sqlite_resolve_loose4.bas '/

Private Function __c2fb_double_value(ByVal value As Double) As Double
    Return value
End Function

Private Function incrAggDepth CDecl Alias "incrAggDepth" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim c2fb_temp_0 As u8 Ptr
    Dim c2fb_temp_1 As UByte

    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 169ULL))))) Then
        c2fb_temp_0 = @(arg1->op2)
        c2fb_temp_1 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_0))) + arg0->u.n)))
        (*c2fb_temp_0) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_0))) + arg0->u.n))))
        c2fb_temp_1 = Cast(UByte, (*c2fb_temp_0))
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function areDoubleQuotedStringsEnabled CDecl Alias "areDoubleQuotedStringsEnabled" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteNameContext Ptr) As SQLITE_C_INT
    If arg0->init.busy Then
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    If Cast(SQLITE_C_INT, (arg1->ncFlags And Cast(SQLITE_C_INT, &H010000ULL))) Then
        If (-Cast(SQLITE_C_INT, ((sqlite3WritableSchema(CPtr(Any Ptr, arg0)) AndAlso (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (arg0->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &H40000000ULL))))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
        Return (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (arg0->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &H20000000ULL))))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))))))
    Else
        Return (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (arg0->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &H40000000ULL))))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))))))
    End If
End Function

Private Sub extendFJMatch CDecl Alias "extendFJMatch" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExprList Ptr Ptr, ByVal arg2 As SqliteSrcItem Ptr, ByVal arg3 As Short)
    Dim local0 As SqliteExpr Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As Short Ptr
    Dim c2fb_temp_3 As Short
    Dim c2fb_temp_4 As Any Ptr Ptr
    Dim c2fb_temp_5 As SqliteTable Ptr
    Dim c2fb_temp_6 As u32 Ptr
    Dim c2fb_temp_7 As SQLITE_C_UINT
    Dim c2fb_temp_8 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_9 As SqliteExprList Ptr

    local0 = CPtr(SqliteExpr Ptr, sqlite3ExprAlloc(CPtr(Any Ptr, arg0->db), Cast(SQLITE_C_INT, 168ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)))
    If local0 Then
        c2fb_temp_0 = @(local0->iTable)
        c2fb_temp_1 = Cast(SQLITE_C_INT, arg2->iCursor)
        (*c2fb_temp_0) = c2fb_temp_1
        c2fb_temp_2 = @(local0->iColumn)
        c2fb_temp_3 = Cast(Short, arg3)
        (*c2fb_temp_2) = c2fb_temp_3
        c2fb_temp_4 = @(local0->y.pTab)
        c2fb_temp_5 = CPtr(SqliteTable Ptr, arg2->pSTab)
        (*c2fb_temp_4) = CPtr(Any Ptr, CPtr(SqliteTable Ptr, arg2->pSTab))
        c2fb_temp_5 = CPtr(SqliteTable Ptr, (*c2fb_temp_4))
        ' C unused-parameter annotation
        c2fb_temp_6 = @((local0)->flags)
        c2fb_temp_7 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_6)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H200000ULL))))))
        (*c2fb_temp_6) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_6)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H200000ULL)))))))
        c2fb_temp_7 = Cast(SQLITE_C_UINT, (*c2fb_temp_6))
        c2fb_temp_8 = @((*arg1))
        c2fb_temp_9 = CPtr(SqliteExprList Ptr, sqlite3ExprListAppend(CPtr(Any Ptr, arg0), CPtr(Any Ptr, (*arg1)), CPtr(Any Ptr, local0)))
        (*c2fb_temp_8) = c2fb_temp_9
    End If
End Sub

Private Sub notValidImpl CDecl Alias "notValidImpl" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteNameContext Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As SqliteExpr Ptr, ByVal arg4 As SqliteExpr Ptr)
    Dim local0 As Const ZString Ptr
    Dim c2fb_temp_0 As Const ZString Ptr
    Dim c2fb_temp_1 As Const ZString Ptr
    Dim c2fb_temp_2 As Const ZString Ptr
    Dim c2fb_temp_3 As u8 Ptr
    Dim c2fb_temp_4 As UByte

    local0 = StrPtr(!"partial index WHERE clauses")
    If Cast(SQLITE_C_INT, (arg1->ncFlags And Cast(SQLITE_C_INT, &H000020ULL))) Then
        c2fb_temp_0 = StrPtr(!"index expressions")
        local0 = c2fb_temp_0
    Else
        If Cast(SQLITE_C_INT, (arg1->ncFlags And Cast(SQLITE_C_INT, &H000004ULL))) Then
            c2fb_temp_1 = StrPtr(!"CHECK constraints")
            local0 = c2fb_temp_1
        Else
            If Cast(SQLITE_C_INT, (arg1->ncFlags And Cast(SQLITE_C_INT, &H000008ULL))) Then
                c2fb_temp_2 = StrPtr(!"generated columns")
                local0 = c2fb_temp_2
            End If
        End If
    End If
    sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"%s prohibited in %s"), arg2, local0)
    If arg3 Then
        c2fb_temp_3 = @(arg3->op)
        c2fb_temp_4 = Cast(UByte, Cast(SQLITE_C_INT, 122ULL))
        (*c2fb_temp_3) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 122ULL)))
        c2fb_temp_4 = Cast(UByte, (*c2fb_temp_3))
    End If
    sqlite3RecordErrorOffsetOfExpr(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, arg4))
End Sub

Private Function exprProbability CDecl Alias "exprProbability" (ByVal arg0 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim local0 As Double

    local0 = __c2fb_double_value(Cast(Double, (-1.0#)))
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->op) <> Cast(SQLITE_C_INT, 154ULL))))) Then
        Return Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))
    End If
    ' C unused-parameter annotation
    sqlite3AtoF(CPtr(Const ZString Ptr, CPtr(ZString Ptr, arg0->u.zToken)), CPtr(Double Ptr, @(local0)))
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((local0 > 1.0#)))) Then
        Return Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))
    End If
    Return Cast(SQLITE_C_INT, Fix((__c2fb_double_value(Cast(Double, (local0 * 134217728.0#))))))
End Function

Private Function resolveExprStep CDecl Alias "resolveExprStep" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim local0 As SqliteNameContext Ptr
    Dim local1 As SqliteParseContext Ptr
    Dim c2fb_temp_0 As SqliteNameContext Ptr
    Dim c2fb_temp_1 As SqliteParseContext Ptr
    Dim local2 As SqliteSrcList Ptr
    Dim local3 As SqliteSrcItem Ptr
    Dim c2fb_temp_2 As SqliteSrcItem Ptr
    Dim c2fb_temp_3 As u8 Ptr
    Dim c2fb_temp_4 As UByte
    Dim c2fb_temp_5 As Any Ptr Ptr
    Dim c2fb_temp_6 As SqliteTable Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT Ptr
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As Short Ptr
    Dim c2fb_temp_10 As Short
    Dim c2fb_temp_11 As Byte Ptr
    Dim c2fb_temp_12 As Byte
    Dim local4(0 To 7) As SQLITE_C_INT
    Dim local5 As SqliteNameContext Ptr
    Dim local6 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SqliteNameContext Ptr
    Dim c2fb_temp_15 As SqliteNameContext Ptr
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SQLITE_C_INT Ptr
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim c2fb_temp_20 As SqliteNameContext Ptr
    Dim c2fb_temp_21 As SqliteNameContext Ptr
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim c2fb_temp_23 As SQLITE_C_INT Ptr
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As u32 Ptr
    Dim c2fb_temp_26 As SQLITE_C_UINT
    Dim c2fb_temp_27 As u8 Ptr
    Dim c2fb_temp_28 As UByte
    Dim c2fb_temp_29 As SQLITE_C_INT
    Dim c2fb_temp_30 As SqliteNameContext Ptr
    Dim c2fb_temp_31 As SqliteNameContext Ptr
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As SQLITE_C_INT Ptr
    Dim c2fb_temp_34 As SQLITE_C_INT
    Dim c2fb_temp_35 As Any Ptr Ptr
    Dim c2fb_temp_36 As SqliteExpr Ptr
    Dim local7 As Const ZString Ptr
    Dim local8 As Const ZString Ptr
    Dim local9 As SqliteExpr Ptr
    Dim c2fb_temp_37 As Const ZString Ptr
    Dim c2fb_temp_38 As Const ZString Ptr
    Dim c2fb_temp_39 As SqliteExpr Ptr
    Dim local10 As SqliteExpr Ptr
    Dim c2fb_temp_40 As SqliteExpr Ptr
    Dim c2fb_temp_41 As Const ZString Ptr
    Dim c2fb_temp_42 As Const ZString Ptr
    Dim c2fb_temp_43 As SqliteExpr Ptr
    Dim c2fb_temp_44 As SqliteExpr Ptr
    Dim c2fb_temp_45 As Const ZString Ptr
    Dim local11 As SqliteExprList Ptr
    Dim local12 As SQLITE_C_INT
    Dim local13 As SQLITE_C_INT
    Dim local14 As SQLITE_C_INT
    Dim local15 As SQLITE_C_INT
    Dim local16 As Const ZString Ptr
    Dim local17 As SqliteFuncDef Ptr
    Dim local18 As UByte
    Dim local19 As SQLITE_C_INT
#ifndef SQLITE_OMIT_WINDOWFUNC
    Dim local20 As SqliteWalkerWindow Ptr
#else
    Dim local20 As Any Ptr
#endif
    Dim c2fb_temp_46 As SqliteExprList Ptr
    Dim c2fb_temp_47 As SQLITE_C_INT
    Dim c2fb_temp_48 As Const ZString Ptr
    Dim c2fb_temp_49 As SqliteFuncDef Ptr
    Dim c2fb_temp_50 As SqliteFuncDef Ptr
    Dim c2fb_temp_51 As SQLITE_C_INT
    Dim c2fb_temp_52 As SQLITE_C_INT
    Dim c2fb_temp_53 As SQLITE_C_INT
    Dim c2fb_temp_54 As u32 Ptr
    Dim c2fb_temp_55 As SQLITE_C_UINT
    Dim c2fb_temp_56 As SQLITE_C_INT Ptr
    Dim c2fb_temp_57 As SQLITE_C_INT
    Dim c2fb_temp_58 As SQLITE_C_INT Ptr
    Dim c2fb_temp_59 As SQLITE_C_INT
    Dim c2fb_temp_60 As SQLITE_C_INT Ptr
    Dim c2fb_temp_61 As SQLITE_C_INT
    Dim local21 As SQLITE_C_INT
    Dim c2fb_temp_62 As SQLITE_C_INT Ptr
    Dim c2fb_temp_63 As SQLITE_C_INT
    Dim c2fb_temp_64 As u8 Ptr
    Dim c2fb_temp_65 As UByte
    Dim c2fb_temp_66 As u32 Ptr
    Dim c2fb_temp_67 As SQLITE_C_UINT
    Dim c2fb_temp_68 As u8 Ptr
    Dim c2fb_temp_69 As UByte
    Dim c2fb_temp_70 As SQLITE_C_INT
    Dim c2fb_temp_71 As SqliteFuncDef Ptr
    Dim c2fb_temp_72 As u32 Ptr
    Dim c2fb_temp_73 As SQLITE_C_UINT
    Dim c2fb_temp_74 As SQLITE_C_INT Ptr
    Dim c2fb_temp_75 As SQLITE_C_INT
    Dim local22 As Const ZString Ptr
    Dim c2fb_temp_76 As Const ZString Ptr
    Dim c2fb_temp_77 As Const ZString Ptr
    Dim c2fb_temp_78 As SQLITE_C_INT Ptr
    Dim c2fb_temp_79 As SQLITE_C_INT
    Dim c2fb_temp_80 As SQLITE_C_INT
    Dim c2fb_temp_81 As SQLITE_C_INT Ptr
    Dim c2fb_temp_82 As SQLITE_C_INT
    Dim c2fb_temp_83 As SQLITE_C_INT Ptr
    Dim c2fb_temp_84 As SQLITE_C_INT
    Dim c2fb_temp_85 As SQLITE_C_INT Ptr
    Dim c2fb_temp_86 As SQLITE_C_INT
    Dim c2fb_temp_87 As SQLITE_C_INT Ptr
    Dim c2fb_temp_88 As SQLITE_C_INT
    Dim c2fb_temp_89 As SQLITE_C_INT Ptr
    Dim c2fb_temp_90 As SQLITE_C_INT
    Dim c2fb_temp_91 As SQLITE_C_INT
    Dim local23 As SqliteSelect Ptr
    Dim c2fb_temp_92 As SQLITE_C_INT Ptr
    Dim c2fb_temp_93 As SQLITE_C_INT
    Dim local24 As SqliteNameContext Ptr
    Dim c2fb_temp_94 As u8 Ptr
    Dim c2fb_temp_95 As UByte
    Dim c2fb_temp_96 As u8 Ptr
    Dim c2fb_temp_97 As UByte
    Dim c2fb_temp_98 As SqliteNameContext Ptr
    Dim c2fb_temp_99 As u8 Ptr
    Dim c2fb_temp_100 As UByte
    Dim c2fb_temp_101 As SqliteNameContext Ptr
    Dim c2fb_temp_102 As u8 Ptr
    Dim c2fb_temp_103 As UByte
    Dim c2fb_temp_104 As SQLITE_C_INT Ptr
    Dim c2fb_temp_105 As SQLITE_C_INT
    Dim c2fb_temp_106 As SQLITE_C_INT Ptr
    Dim c2fb_temp_107 As SQLITE_C_INT
    Dim local25 As SQLITE_C_INT
    Dim c2fb_temp_108 As u8 Ptr
    Dim c2fb_temp_109 As SQLITE_C_INT
    Dim c2fb_temp_110 As u32 Ptr
    Dim c2fb_temp_111 As SQLITE_C_UINT
    Dim c2fb_temp_112 As u32 Ptr
    Dim c2fb_temp_113 As SQLITE_C_UINT
    Dim c2fb_temp_114 As SQLITE_C_INT Ptr
    Dim c2fb_temp_115 As SQLITE_C_INT
    Dim local26 As SqliteExpr Ptr
    Dim local27 As SQLITE_C_INT
    Dim c2fb_temp_116 As u8 Ptr
    Dim c2fb_temp_117 As UByte
    Dim c2fb_temp_118 As u8 Ptr
    Dim c2fb_temp_119 As UByte
    Dim local28 As SQLITE_C_INT
    Dim local29 As SQLITE_C_INT
    Dim c2fb_temp_120 As SQLITE_C_INT
    Dim c2fb_temp_121 As SQLITE_C_INT
    Dim c2fb_temp_122 As SQLITE_C_INT
    Dim c2fb_temp_123 As SQLITE_C_INT
    Dim c2fb_switch_value_124 As sqlite3_uint64
    Dim c2fb_switch_state_125 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    c2fb_temp_0 = CPtr(SqliteNameContext Ptr, arg0->u.pNC)
    local0 = c2fb_temp_0
    ' C unused-parameter annotation
    c2fb_temp_1 = local0->pParse
    local1 = c2fb_temp_1
    ' C unused-parameter annotation
    c2fb_switch_value_124 = Cast(sqlite3_uint64, arg1->op)
    c2fb_switch_state_125 = 0
    Select Case c2fb_switch_value_124
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 76ULL))
            c2fb_switch_state_125 = 1
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 52ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 51ULL))
            c2fb_switch_state_125 = 2
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 60ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 142ULL))
            c2fb_switch_state_125 = 3
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 172ULL))
            c2fb_switch_state_125 = 4
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 20ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 139ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 50ULL))
            c2fb_switch_state_125 = 5
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 157ULL))
            c2fb_switch_state_125 = 6
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 45ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 46ULL))
            c2fb_switch_state_125 = 7
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 49ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 54ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 53ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 57ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 56ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 55ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 58ULL))
            c2fb_switch_state_125 = 8
    End Select
    Do
        Select Case c2fb_switch_state_125
        Case 0
            Exit Do
        Case 1
            local2 = local0->pSrcList
            ' C automatic storage declaration
            ' C unused-parameter annotation
            c2fb_temp_2 = CPtr(SqliteSrcItem Ptr, (@local2->a(0)))
            local3 = c2fb_temp_2
            c2fb_temp_3 = @(arg1->op)
            c2fb_temp_4 = Cast(UByte, Cast(SQLITE_C_INT, 168ULL))
            (*c2fb_temp_3) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 168ULL)))
            c2fb_temp_4 = Cast(UByte, (*c2fb_temp_3))
            ' C unused-parameter annotation
            c2fb_temp_5 = @(arg1->y.pTab)
            c2fb_temp_6 = CPtr(SqliteTable Ptr, local3->pSTab)
            (*c2fb_temp_5) = CPtr(Any Ptr, CPtr(SqliteTable Ptr, local3->pSTab))
            c2fb_temp_6 = CPtr(SqliteTable Ptr, (*c2fb_temp_5))
            c2fb_temp_7 = @(arg1->iTable)
            c2fb_temp_8 = Cast(SQLITE_C_INT, local3->iCursor)
            (*c2fb_temp_7) = c2fb_temp_8
            c2fb_temp_9 = @(arg1->iColumn)
            c2fb_temp_10 = (*c2fb_temp_9)
            (*c2fb_temp_9) = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_10) - 1)))
            c2fb_temp_11 = @(arg1->affExpr)
            c2fb_temp_12 = Cast(Byte, Cast(SQLITE_C_INT, &H44ULL))
            (*c2fb_temp_11) = c2fb_temp_12
            Goto c2fb_flow_0
            c2fb_switch_state_125 = 0
        Case 2
            ' C automatic array storage
            ' C automatic storage declaration
            ' C automatic storage declaration
            c2fb_temp_13 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local6 = c2fb_temp_13
            c2fb_temp_14 = local0
            local5 = c2fb_temp_14
            While (-Cast(SQLITE_C_INT, ((local5 AndAlso (-Cast(SQLITE_C_INT, ((local6 < (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, (8ULL * SizeOf(SQLITE_C_INT)))) \ Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SQLITE_C_INT))))))))))))))))
                c2fb_temp_17 = @(local4(local6))
                c2fb_temp_18 = Cast(SQLITE_C_INT, local5->nRef)
                (*c2fb_temp_17) = c2fb_temp_18
            c2fb_flow_2:
                c2fb_temp_15 = local5->pNext
                local5 = c2fb_temp_15
                c2fb_temp_16 = local6
                local6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_16 + 1)))
            Wend
            c2fb_flow_1:
            sqlite3WalkExpr(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg1->pLeft)))
            If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->eParseMode) >= Cast(SQLITE_C_INT, 2ULL)))))) Then
                Return Cast(SQLITE_C_INT, 1ULL)
            End If
            If sqlite3ExprCanBeNull(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg1->pLeft))) Then
                Return Cast(SQLITE_C_INT, 1ULL)
            End If
            c2fb_temp_19 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local6 = c2fb_temp_19
            c2fb_temp_20 = local0
            local5 = c2fb_temp_20
            While local5
                If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (local5->ncFlags And Cast(SQLITE_C_INT, &H100000ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    Return Cast(SQLITE_C_INT, 1ULL)
                End If
            c2fb_flow_4:
                c2fb_temp_21 = local5->pNext
                local5 = c2fb_temp_21
                c2fb_temp_22 = local6
                local6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_22 + 1)))
            Wend
            c2fb_flow_3:
            ' empty C statement
            ' C unused-parameter annotation
            c2fb_temp_23 = @(arg1->u.iValue)
            c2fb_temp_24 = Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 52ULL)))))))
            (*c2fb_temp_23) = c2fb_temp_24
            c2fb_temp_25 = @(arg1->flags)
            c2fb_temp_26 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_25)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H000800ULL)))))
            (*c2fb_temp_25) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_25)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H000800ULL))))))
            c2fb_temp_26 = Cast(SQLITE_C_UINT, (*c2fb_temp_25))
            c2fb_temp_27 = @(arg1->op)
            c2fb_temp_28 = Cast(UByte, Cast(SQLITE_C_INT, 156ULL))
            (*c2fb_temp_27) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 156ULL)))
            c2fb_temp_28 = Cast(UByte, (*c2fb_temp_27))
            c2fb_temp_29 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local6 = c2fb_temp_29
            c2fb_temp_30 = local0
            local5 = c2fb_temp_30
            While (-Cast(SQLITE_C_INT, ((local5 AndAlso (-Cast(SQLITE_C_INT, ((local6 < (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, (8ULL * SizeOf(SQLITE_C_INT)))) \ Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SQLITE_C_INT))))))))))))))))
                c2fb_temp_33 = @(local5->nRef)
                c2fb_temp_34 = Cast(SQLITE_C_INT, local4(local6))
                (*c2fb_temp_33) = c2fb_temp_34
            c2fb_flow_6:
                c2fb_temp_31 = local5->pNext
                local5 = c2fb_temp_31
                c2fb_temp_32 = local6
                local6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_32 + 1)))
            Wend
            c2fb_flow_5:
            sqlite3ExprDelete(CPtr(Any Ptr, local1->db), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg1->pLeft)))
            c2fb_temp_35 = @(arg1->pLeft)
            c2fb_temp_36 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            (*c2fb_temp_35) = CPtr(Any Ptr, CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
            c2fb_temp_36 = CPtr(SqliteExpr Ptr, (*c2fb_temp_35))
            Return Cast(SQLITE_C_INT, 1ULL)
        Case 3
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 60ULL))))) Then
                c2fb_temp_37 = CPtr(Const ZString Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                local8 = c2fb_temp_37
                c2fb_temp_38 = CPtr(Const ZString Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                local7 = c2fb_temp_38
                ' C unused-parameter annotation
                c2fb_temp_39 = arg1
                local9 = c2fb_temp_39
            Else
                local10 = CPtr(SqliteExpr Ptr, arg1->pLeft)
                ' empty C statement
                ' empty C statement
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, ((local0)->ncFlags And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000020ULL) Or Cast(SQLITE_C_INT, &H000008ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                    notValidImpl(local1, local0, StrPtr(!"the \034.\034 operator"), Cast(SQLITE_C_INT, &O0ULL), arg1)
                End If
                ' empty C statement
                c2fb_temp_40 = CPtr(SqliteExpr Ptr, arg1->pRight)
                local9 = c2fb_temp_40
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local9->op) = Cast(SQLITE_C_INT, 60ULL))))) Then
                    c2fb_temp_41 = CPtr(Const ZString Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                    local8 = c2fb_temp_41
                Else
                    ' C unused-parameter annotation
                    ' C unused-parameter annotation
                    c2fb_temp_42 = CPtr(Const ZString Ptr, CPtr(ZString Ptr, local10->u.zToken))
                    local8 = c2fb_temp_42
                    c2fb_temp_43 = CPtr(SqliteExpr Ptr, local9->pLeft)
                    local10 = c2fb_temp_43
                    c2fb_temp_44 = CPtr(SqliteExpr Ptr, local9->pRight)
                    local9 = c2fb_temp_44
                End If
                ' C unused-parameter annotation
                c2fb_temp_45 = CPtr(Const ZString Ptr, CPtr(ZString Ptr, local10->u.zToken))
                local7 = c2fb_temp_45
                ' C unused-parameter annotation
                If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->eParseMode) >= Cast(SQLITE_C_INT, 2ULL)))))) Then
                    sqlite3RenameTokenRemap(CPtr(Any Ptr, local1), CPtr(Any Ptr, arg1), CPtr(Any Ptr, local9))
                    sqlite3RenameTokenRemap(CPtr(Any Ptr, local1), CPtr(Any Ptr, CPtr(SqliteTable Ptr Ptr, @(arg1->y.pTab))), CPtr(Any Ptr, local10))
                End If
            End If
            Return lookupName(local1, local8, local7, CPtr(Const SqliteExpr Ptr, local9), local0, arg1)
        Case 4
            ' C automatic storage declaration
            ' C automatic storage declaration
            local13 = Cast(SQLITE_C_INT, &O0ULL)
            local14 = Cast(SQLITE_C_INT, &O0ULL)
            local15 = Cast(SQLITE_C_INT, &O0ULL)
            ' C automatic storage declaration
            ' C automatic storage declaration
            local18 = ((local1->db)->enc)
            local19 = (Cast(SQLITE_C_INT, (local0->ncFlags And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000001ULL) Or Cast(SQLITE_C_INT, &H004000ULL)))))))
#ifndef SQLITE_OMIT_WINDOWFUNC
            local20 = (IIf(((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (((arg1))->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H1000000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(SqliteWalkerWindow Ptr, arg1->y.pWin)->eFrmType) <> Cast(SQLITE_C_INT, 167ULL)))))))))), CPtr(SqliteWalkerWindow Ptr, arg1->y.pWin), CPtr(SqliteWalkerWindow Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))))
#else
            local20 = 0
#endif
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_46 = CPtr(SqliteExprList Ptr, arg1->x.pList)
            local11 = c2fb_temp_46
            c2fb_temp_47 = Cast(SQLITE_C_INT, IIf(local11, local11->nExpr, Cast(SQLITE_C_INT, &O0ULL)))
            local12 = c2fb_temp_47
            c2fb_temp_48 = CPtr(Const ZString Ptr, CPtr(ZString Ptr, arg1->u.zToken))
            local16 = c2fb_temp_48
            c2fb_temp_49 = CPtr(SqliteFuncDef Ptr, sqlite3FindFunction(CPtr(Any Ptr, local1->db), local16, local12, local18, Cast(SQLITE_C_INT, &O0ULL)))
            local17 = c2fb_temp_49
            If (-Cast(SQLITE_C_INT, ((local17 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_50 = CPtr(SqliteFuncDef Ptr, sqlite3FindFunction(CPtr(Any Ptr, local1->db), local16, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 2ULL))), local18, Cast(SQLITE_C_INT, &O0ULL)))
                local17 = c2fb_temp_50
                If (-Cast(SQLITE_C_INT, ((local17 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_51 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                    local13 = c2fb_temp_51
                Else
                    c2fb_temp_52 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                    local14 = c2fb_temp_52
                End If
            Else
                c2fb_temp_53 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, ((CPtr(Any Ptr, CPtr(Sub CDecl(ByVal arg0 As SqliteResultContext Ptr), local17->xFinalize)) <> CPtr(Any Ptr, Cast(SQLITE_C_INT, &O0ULL)))))))
                local15 = c2fb_temp_53
                If Cast(SQLITE_C_UINT, (local17->funcFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0400ULL)))) Then
                    c2fb_temp_54 = @((arg1)->flags)
                    c2fb_temp_55 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_54)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H080000ULL))))))
                    (*c2fb_temp_54) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_54)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H080000ULL)))))))
                    c2fb_temp_55 = Cast(SQLITE_C_UINT, (*c2fb_temp_54))
                    If (-Cast(SQLITE_C_INT, ((local12 = Cast(SQLITE_C_INT, 2ULL))))) Then
                        c2fb_temp_56 = @(arg1->iTable)
                        c2fb_temp_57 = Cast(SQLITE_C_INT, exprProbability(CPtr(SqliteExpr Ptr, local11->a(Cast(SQLITE_C_INT, 1ULL)).pExpr)))
                        (*c2fb_temp_56) = c2fb_temp_57
                        If (-Cast(SQLITE_C_INT, ((arg1->iTable < Cast(SQLITE_C_INT, &O0ULL))))) Then
                            sqlite3ErrorMsg(CPtr(Any Ptr, local1), StrPtr(!"second argument to %#T() must be a constant between 0.0 and 1.0"), arg1)
                            c2fb_temp_58 = @(local0->nNcErr)
                            c2fb_temp_59 = (*c2fb_temp_58)
                            (*c2fb_temp_58) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_59 + 1)))
                        End If
                    Else
                        c2fb_temp_60 = @(arg1->iTable)
                        c2fb_temp_61 = Cast(SQLITE_C_INT, IIf((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(Const Byte Ptr, local17->zName)[Cast(SQLITE_C_INT, &O0ULL)]) = Cast(SQLITE_C_INT, 117))))), Cast(SQLITE_C_INT, 8388608ULL), Cast(SQLITE_C_INT, 125829120ULL)))
                        (*c2fb_temp_60) = c2fb_temp_61
                    End If
                End If
                local21 = sqlite3AuthCheck(CPtr(Any Ptr, local1), Cast(SQLITE_C_INT, 31ULL), Cast(SQLITE_C_INT, &O0ULL), local17->zName, Cast(SQLITE_C_INT, &O0ULL))
                If (-Cast(SQLITE_C_INT, ((local21 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                    If (-Cast(SQLITE_C_INT, ((local21 = Cast(SQLITE_C_INT, 1ULL))))) Then
                        sqlite3ErrorMsg(CPtr(Any Ptr, local1), StrPtr(!"not authorized to use function: %#T"), arg1)
                        c2fb_temp_62 = @(local0->nNcErr)
                        c2fb_temp_63 = (*c2fb_temp_62)
                        (*c2fb_temp_62) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_63 + 1)))
                    End If
                    c2fb_temp_64 = @(arg1->op)
                    c2fb_temp_65 = Cast(UByte, Cast(SQLITE_C_INT, 122ULL))
                    (*c2fb_temp_64) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 122ULL)))
                    c2fb_temp_65 = Cast(UByte, (*c2fb_temp_64))
                    Return Cast(SQLITE_C_INT, 1ULL)
                End If
                If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local17->funcFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H000100000ULL))))) OrElse Cast(SQLITE_C_UINT, ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, &H80000000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))))) Then
                    resolveSetExprSubtypeArg(local11)
                End If
                If Cast(SQLITE_C_UINT, (local17->funcFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0800ULL) Or Cast(SQLITE_C_INT, &H2000ULL))))))) Then
                    c2fb_temp_66 = @((arg1)->flags)
                    c2fb_temp_67 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_66)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H100000ULL))))))
                    (*c2fb_temp_66) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_66)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H100000ULL)))))))
                    c2fb_temp_67 = Cast(SQLITE_C_UINT, (*c2fb_temp_66))
                End If
                If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local17->funcFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0800ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                    ' C unused-parameter annotation
                    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, ((local0)->ncFlags And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000020ULL) Or Cast(SQLITE_C_INT, &H000002ULL))) Or Cast(SQLITE_C_INT, &H000008ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                        notValidImpl(local1, local0, StrPtr(!"non-deterministic functions"), Cast(SQLITE_C_INT, &O0ULL), arg1)
                    End If
                    ' empty C statement
                Else
                    ' C unused-parameter annotation
                    c2fb_temp_68 = @(arg1->op2)
                    c2fb_temp_69 = Cast(UByte, Cast(SQLITE_C_INT, (local0->ncFlags And Cast(SQLITE_C_INT, &H00002eULL))))
                    (*c2fb_temp_68) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, (local0->ncFlags And Cast(SQLITE_C_INT, &H00002eULL)))))
                    c2fb_temp_69 = Cast(UByte, (*c2fb_temp_68))
                End If
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local17->funcFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00040000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->nested) = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local1->db->mDbFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0020ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
                    c2fb_temp_70 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 2ULL))
                    local13 = c2fb_temp_70
                    c2fb_temp_71 = CPtr(SqliteFuncDef Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                    local17 = c2fb_temp_71
                Else
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local17->funcFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00080000ULL) Or Cast(SQLITE_C_INT, &H00200000ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->eParseMode) >= Cast(SQLITE_C_INT, 2ULL)))))) = 0))))))) Then
                        If Cast(SQLITE_C_INT, (local0->ncFlags And Cast(SQLITE_C_INT, &H040000ULL))) Then
                            c2fb_temp_72 = @((arg1)->flags)
                            c2fb_temp_73 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_72)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H40000000ULL))))))
                            (*c2fb_temp_72) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_72)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H40000000ULL)))))))
                            c2fb_temp_73 = Cast(SQLITE_C_UINT, (*c2fb_temp_72))
                        End If
                        sqlite3ExprFunctionUsable(CPtr(Any Ptr, local1), CPtr(Any Ptr, arg1), CPtr(Any Ptr, local17))
                    End If
                End If
            End If
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->eParseMode) >= Cast(SQLITE_C_INT, 2ULL)))))))))) Then
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local17 AndAlso (-Cast(SQLITE_C_INT, ((CPtr(Any Ptr, CPtr(Sub CDecl(ByVal arg0 As SqliteResultContext Ptr), local17->xValue)) = CPtr(Any Ptr, Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso local20)))) Then
                    sqlite3ErrorMsg(CPtr(Any Ptr, local1), StrPtr(!"%#T() may not be used as a window function"), arg1)
                    c2fb_temp_74 = @(local0->nNcErr)
                    c2fb_temp_75 = (*c2fb_temp_74)
                    (*c2fb_temp_74) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_75 + 1)))
                Else
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((local15 AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (local0->ncFlags And Cast(SQLITE_C_INT, &H000001ULL)))) = Cast(SQLITE_C_INT, &O0ULL)))))))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local15) AndAlso (Cast(SQLITE_C_UINT, (local17->funcFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00010000ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, (local20 = 0)))))))))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local15 AndAlso local20)))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (local0->ncFlags And Cast(SQLITE_C_INT, &H004000ULL)))) = Cast(SQLITE_C_INT, &O0ULL)))))))))))))) Then
                        ' C automatic storage declaration
                        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local17->funcFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00010000ULL))))) OrElse local20)))) Then
                            c2fb_temp_76 = StrPtr(!"window")
                            local22 = c2fb_temp_76
                        Else
                            c2fb_temp_77 = StrPtr(!"aggregate")
                            local22 = c2fb_temp_77
                        End If
                        sqlite3ErrorMsg(CPtr(Any Ptr, local1), StrPtr(!"misuse of %s function %#T()"), local22, arg1)
                        c2fb_temp_78 = @(local0->nNcErr)
                        c2fb_temp_79 = (*c2fb_temp_78)
                        (*c2fb_temp_78) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_79 + 1)))
                        c2fb_temp_80 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                        local15 = c2fb_temp_80
                    Else
                        If (-Cast(SQLITE_C_INT, ((local13 AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->db->init.busy) = Cast(SQLITE_C_INT, &O0ULL))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local13 = Cast(SQLITE_C_INT, 2ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->db->init.busy) = Cast(SQLITE_C_INT, 2ULL))))))))))))))))))) Then
                            sqlite3ErrorMsg(CPtr(Any Ptr, local1), StrPtr(!"no such function: %#T"), arg1)
                            c2fb_temp_81 = @(local0->nNcErr)
                            c2fb_temp_82 = (*c2fb_temp_81)
                            (*c2fb_temp_81) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_82 + 1)))
                        Else
                            If local14 Then
                                sqlite3ErrorMsg(CPtr(Any Ptr, local1), StrPtr(!"wrong number of arguments to function %#T()"), arg1)
                                c2fb_temp_83 = @(local0->nNcErr)
                                c2fb_temp_84 = (*c2fb_temp_83)
                                (*c2fb_temp_83) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_84 + 1)))
                            Else
                                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local15 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H1000000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
                                    sqlite3ErrorMsg(CPtr(Any Ptr, local1), StrPtr(!"FILTER may not be used with non-aggregate %#T()"), arg1)
                                    c2fb_temp_85 = @(local0->nNcErr)
                                    c2fb_temp_86 = (*c2fb_temp_85)
                                    (*c2fb_temp_85) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_86 + 1)))
                                Else
                                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local15 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso CPtr(SqliteExpr Ptr, arg1->pLeft))))) Then
                                        sqlite3ExprOrderByAggregateError(CPtr(Any Ptr, local1), CPtr(Any Ptr, arg1))
                                        c2fb_temp_87 = @(local0->nNcErr)
                                        c2fb_temp_88 = (*c2fb_temp_87)
                                        (*c2fb_temp_87) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_88 + 1)))
                                    End If
                                End If
                            End If
                        End If
                    End If
                End If
                If local15 Then
                    c2fb_temp_89 = @(local0->ncFlags)
                    c2fb_temp_90 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_89) And Cast(SQLITE_C_INT, (Not (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H004000ULL) Or (IIf((-Cast(SQLITE_C_INT, (local20 = 0))), Cast(SQLITE_C_INT, &H000001ULL), Cast(SQLITE_C_INT, &O0ULL)))))))))))
                    (*c2fb_temp_89) = c2fb_temp_90
                End If
            Else
                If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H1000000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) OrElse CPtr(SqliteExpr Ptr, arg1->pLeft))))) Then
                    c2fb_temp_91 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                    local15 = c2fb_temp_91
                End If
            End If
            sqlite3WalkExprList(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local11))
            If local15 Then
                If CPtr(SqliteExpr Ptr, arg1->pLeft) Then
                    ' C unused-parameter annotation
                    ' C unused-parameter annotation
                    sqlite3WalkExprList(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, CPtr(SqliteExpr Ptr, arg1->pLeft)->x.pList)))
                End If
#ifndef SQLITE_OMIT_WINDOWFUNC
                If (-Cast(SQLITE_C_INT, ((local20 AndAlso (-Cast(SQLITE_C_INT, ((local1->nErr = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                    local23 = local0->pWinSelect
                    ' C unused-parameter annotation
                    If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->eParseMode) >= Cast(SQLITE_C_INT, 2ULL)))))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        sqlite3WindowUpdate(CPtr(Any Ptr, local1), CPtr(Any Ptr, IIf(local23, CPtr(SqliteWalkerWindow Ptr, local23->pWinDefn), CPtr(SqliteWalkerWindow Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))), CPtr(Any Ptr, local20), CPtr(Any Ptr, local17))
                        If local1->db->mallocFailed Then
                            Goto c2fb_flow_0
                        End If
                    End If
                    sqlite3WalkExprList(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local20->pPartition))
                    sqlite3WalkExprList(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local20->pOrderBy))
                    sqlite3WalkExpr(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local20->pFilter))
                    sqlite3WindowLink(CPtr(Any Ptr, local23), CPtr(Any Ptr, local20))
                    c2fb_temp_92 = @(local0->ncFlags)
                    c2fb_temp_93 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_92) Or Cast(SQLITE_C_INT, &H008000ULL))))
                    (*c2fb_temp_92) = c2fb_temp_93
                Else
#endif
                    ' C automatic storage declaration
                    c2fb_temp_94 = @(arg1->op)
                    c2fb_temp_95 = Cast(UByte, Cast(SQLITE_C_INT, 169ULL))
                    (*c2fb_temp_94) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 169ULL)))
                    c2fb_temp_95 = Cast(UByte, (*c2fb_temp_94))
                    c2fb_temp_96 = @(arg1->op2)
                    c2fb_temp_97 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                    (*c2fb_temp_96) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, &O0ULL)))
                    c2fb_temp_97 = Cast(UByte, (*c2fb_temp_96))
#ifndef SQLITE_OMIT_WINDOWFUNC
                    If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H1000000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                        sqlite3WalkExpr(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteWalkerWindow Ptr, arg1->y.pWin)->pFilter))
                    End If
#endif
                    c2fb_temp_98 = local0
                    local24 = c2fb_temp_98
                    While (-Cast(SQLITE_C_INT, ((local24 AndAlso (-Cast(SQLITE_C_INT, ((sqlite3ReferencesSrcList(CPtr(Any Ptr, local1), CPtr(Any Ptr, arg1), CPtr(Any Ptr, local24->pSrcList)) = Cast(SQLITE_C_INT, &O0ULL)))))))))
                        c2fb_temp_99 = @(arg1->op2)
                        c2fb_temp_100 = Cast(UByte, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, Cast(UByte, (*c2fb_temp_99))) + (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)) + local24->nNestedSelect))))))
                        (*c2fb_temp_99) = Cast(u8, Cast(UByte, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, Cast(UByte, (*c2fb_temp_99))) + (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)) + local24->nNestedSelect)))))))
                        c2fb_temp_100 = Cast(UByte, (*c2fb_temp_99))
                        c2fb_temp_101 = local24->pNext
                        local24 = c2fb_temp_101
                    c2fb_flow_8:
                    Wend
                    c2fb_flow_7:
                    ' C unused-parameter annotation
                    If (-Cast(SQLITE_C_INT, ((local24 AndAlso local17)))) Then
                        c2fb_temp_102 = @(arg1->op2)
                        c2fb_temp_103 = Cast(UByte, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, Cast(UByte, (*c2fb_temp_102))) + local24->nNestedSelect)))
                        (*c2fb_temp_102) = Cast(u8, Cast(UByte, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, Cast(UByte, (*c2fb_temp_102))) + local24->nNestedSelect))))
                        c2fb_temp_103 = Cast(UByte, (*c2fb_temp_102))
                        ' C unused-parameter annotation
                        ' C unused-parameter annotation
                        ' empty C statement
                        ' empty C statement
                        c2fb_temp_104 = @(local24->ncFlags)
                        c2fb_temp_105 = Cast(SQLITE_C_INT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_104)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H000010ULL)) Or (Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (local17->funcFlags Xor Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H08000000ULL))))) And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H1000ULL) Or Cast(SQLITE_C_INT, &H08000000ULL)))))))))))))
                        (*c2fb_temp_104) = c2fb_temp_105
                    End If
#ifndef SQLITE_OMIT_WINDOWFUNC
                End If
#endif
                c2fb_temp_106 = @(local0->ncFlags)
                c2fb_temp_107 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_106) Or local19)))
                (*c2fb_temp_106) = c2fb_temp_107
            End If
            Return Cast(SQLITE_C_INT, 1ULL)
        Case 5
            ' empty C statement
            ' empty C statement
            ' empty C statement
            If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                local25 = local0->nRef
                ' empty C statement
                ' empty C statement
                ' empty C statement
                ' empty C statement
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 20ULL))))) Then
                    c2fb_temp_108 = @(local1->bHasExists)
                    c2fb_temp_109 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))) And Cast(SQLITE_C_UINT, &H1ULL)))
                    (*c2fb_temp_108) = Cast(u8, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))) And Cast(SQLITE_C_UINT, &H1ULL)))
                    c2fb_temp_109 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))) And Cast(SQLITE_C_UINT, &H1ULL)))
                End If
                If Cast(SQLITE_C_INT, (local0->ncFlags And Cast(SQLITE_C_INT, &H00002eULL))) Then
                    notValidImpl(local1, local0, StrPtr(!"subqueries"), arg1, arg1)
                Else
                    sqlite3WalkSelect(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteSelect Ptr, arg1->x.pSelect)))
                End If
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, ((local25 <> local0->nRef)))) Then
                    c2fb_temp_110 = @((arg1)->flags)
                    c2fb_temp_111 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_110)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000040ULL))))))
                    (*c2fb_temp_110) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_110)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000040ULL)))))))
                    c2fb_temp_111 = Cast(SQLITE_C_UINT, (*c2fb_temp_110))
                    c2fb_temp_112 = @(CPtr(SqliteSelect Ptr, arg1->x.pSelect)->selFlags)
                    c2fb_temp_113 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_112)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H20000000ULL)))))
                    (*c2fb_temp_112) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_112)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H20000000ULL))))))
                    c2fb_temp_113 = Cast(SQLITE_C_UINT, (*c2fb_temp_112))
                End If
                c2fb_temp_114 = @(local0->ncFlags)
                c2fb_temp_115 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_114) Or Cast(SQLITE_C_INT, &H000040ULL))))
                (*c2fb_temp_114) = c2fb_temp_115
            End If
            Goto c2fb_flow_0
            c2fb_switch_state_125 = 0
        Case 6
            ' empty C statement
            ' empty C statement
            ' empty C statement
            ' empty C statement
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, ((local0)->ncFlags And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000004ULL) Or Cast(SQLITE_C_INT, &H000002ULL))) Or Cast(SQLITE_C_INT, &H000020ULL))) Or Cast(SQLITE_C_INT, &H000008ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                notValidImpl(local1, local0, StrPtr(!"parameters"), arg1, arg1)
            End If
            ' empty C statement
            Goto c2fb_flow_0
            c2fb_switch_state_125 = 0
        Case 7
            local26 = CPtr(SqliteExpr Ptr, sqlite3ExprSkipCollateAndLikely(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg1->pRight))))
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, (((local26) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local26->op) = Cast(SQLITE_C_INT, 60ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local26->op) = Cast(SQLITE_C_INT, 171ULL)))))))))))))) Then
                local27 = resolveExprStep(arg0, local26)
                If (-Cast(SQLITE_C_INT, ((local27 = Cast(SQLITE_C_INT, 2ULL))))) Then
                    Return Cast(SQLITE_C_INT, 2ULL)
                End If
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local26->op) = Cast(SQLITE_C_INT, 171ULL))))) Then
                    c2fb_temp_116 = @(arg1->op2)
                    c2fb_temp_117 = Cast(UByte, arg1->op)
                    (*c2fb_temp_116) = Cast(u8, Cast(UByte, arg1->op))
                    c2fb_temp_117 = Cast(UByte, (*c2fb_temp_116))
                    c2fb_temp_118 = @(arg1->op)
                    c2fb_temp_119 = Cast(UByte, Cast(SQLITE_C_INT, 175ULL))
                    (*c2fb_temp_118) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 175ULL)))
                    c2fb_temp_119 = Cast(UByte, (*c2fb_temp_118))
                    Return Cast(SQLITE_C_INT, &O0ULL)
                End If
            End If
            ' C switch fallthrough annotation
            c2fb_switch_state_125 = 8
        Case 8
            ' C automatic storage declaration
            ' C automatic storage declaration
            If local1->db->mallocFailed Then
                Goto c2fb_flow_0
            End If
            ' C unused-parameter annotation
            c2fb_temp_120 = Cast(SQLITE_C_INT, sqlite3ExprVectorSize(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg1->pLeft))))
            local28 = c2fb_temp_120
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 49ULL))))) Then
                ' C unused-parameter annotation
                c2fb_temp_121 = Cast(SQLITE_C_INT, sqlite3ExprVectorSize(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, CPtr(SqliteExprList Ptr, arg1->x.pList)->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr))))
                local29 = c2fb_temp_121
                If (-Cast(SQLITE_C_INT, ((local29 = local28)))) Then
                    c2fb_temp_122 = Cast(SQLITE_C_INT, sqlite3ExprVectorSize(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, CPtr(SqliteExprList Ptr, arg1->x.pList)->a(Cast(SQLITE_C_INT, 1ULL)).pExpr))))
                    local29 = c2fb_temp_122
                End If
            Else
                ' C unused-parameter annotation
                c2fb_temp_123 = Cast(SQLITE_C_INT, sqlite3ExprVectorSize(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg1->pRight))))
                local29 = c2fb_temp_123
            End If
            If (-Cast(SQLITE_C_INT, ((local28 <> local29)))) Then
                ' empty C statement
                ' empty C statement
                ' empty C statement
                ' empty C statement
                ' empty C statement
                ' empty C statement
                ' empty C statement
                ' empty C statement
                ' empty C statement
                sqlite3ErrorMsg(CPtr(Any Ptr, local1), StrPtr(!"row value misused"))
                sqlite3RecordErrorOffsetOfExpr(CPtr(Any Ptr, local1->db), CPtr(Any Ptr, arg1))
            End If
            Goto c2fb_flow_0
            c2fb_switch_state_125 = 0
        End Select
    Loop
    c2fb_flow_0:
    ' C unused-parameter annotation
    Return IIf(local1->nErr, Cast(SQLITE_C_INT, 2ULL), Cast(SQLITE_C_INT, &O0ULL))
End Function

Private Function resolveAsName CDecl Alias "resolveAsName" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExprList Ptr, ByVal arg2 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As Const ZString Ptr
    Dim c2fb_temp_0 As Const ZString Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg2->op) = Cast(SQLITE_C_INT, 60ULL))))) Then
        ' C automatic storage declaration
        ' C unused-parameter annotation
        c2fb_temp_0 = CPtr(Const ZString Ptr, CPtr(ZString Ptr, arg2->u.zToken))
        local1 = c2fb_temp_0
        c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local0 = c2fb_temp_1
        While (-Cast(SQLITE_C_INT, ((local0 < arg1->nExpr))))
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg1->a(local0).fg.flags) Shr 0) And Cast(SQLITE_C_UINT, &H3ULL))) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((sqlite3_stricmp(CPtr(Const ZString Ptr, CPtr(ZString Ptr, arg1->a(local0).zEName)), local1) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                Return Cast(SQLITE_C_INT, (local0 + Cast(SQLITE_C_INT, 1ULL)))
            End If
        c2fb_flow_1:
            c2fb_temp_2 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_2 + 1)))
        Wend
        c2fb_flow_0:
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function resolveOrderByTermToExprList CDecl Alias "resolveOrderByTermToExprList" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SqliteExprList Ptr
    Dim local2 As SqliteNameContext
    Dim local3 As sqlite3 Ptr
    Dim local4 As SQLITE_C_INT
    Dim local5 As UByte
    Dim c2fb_temp_0 As SqliteExprList Ptr
    Dim c2fb_temp_1 As Any Ptr
    Dim c2fb_temp_2 As SqliteParseContext Ptr Ptr
    Dim c2fb_temp_3 As SqliteParseContext Ptr
    Dim c2fb_temp_4 As SqliteSrcList Ptr Ptr
    Dim c2fb_temp_5 As SqliteSrcList Ptr
    Dim c2fb_temp_6 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_7 As SqliteExprList Ptr
    Dim c2fb_temp_8 As SQLITE_C_INT Ptr
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT Ptr
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As sqlite3 Ptr
    Dim c2fb_temp_13 As UByte
    Dim c2fb_temp_14 As u8 Ptr
    Dim c2fb_temp_15 As UByte
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As u8 Ptr
    Dim c2fb_temp_18 As UByte
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim c2fb_temp_20 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(SqliteExprList Ptr, arg1->pEList)
    local1 = c2fb_temp_0
    c2fb_temp_1 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local2))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteNameContext))))
    c2fb_temp_2 = @(local2.pParse)
    c2fb_temp_3 = arg0
    (*c2fb_temp_2) = c2fb_temp_3
    c2fb_temp_4 = @(local2.pSrcList)
    c2fb_temp_5 = CPtr(SqliteSrcList Ptr, arg1->pSrc)
    (*c2fb_temp_4) = c2fb_temp_5
    c2fb_temp_6 = @(local2.uNC.pEList)
    c2fb_temp_7 = local1
    (*c2fb_temp_6) = c2fb_temp_7
    c2fb_temp_8 = @(local2.ncFlags)
    c2fb_temp_9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000001ULL) Or Cast(SQLITE_C_INT, &H000080ULL))) Or Cast(SQLITE_C_INT, &H080000ULL))))
    (*c2fb_temp_8) = c2fb_temp_9
    c2fb_temp_10 = @(local2.nNcErr)
    c2fb_temp_11 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_10) = c2fb_temp_11
    c2fb_temp_12 = arg0->db
    local3 = c2fb_temp_12
    c2fb_temp_13 = Cast(UByte, local3->suppressErr)
    local5 = c2fb_temp_13
    c2fb_temp_14 = @(local3->suppressErr)
    c2fb_temp_15 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
    (*c2fb_temp_14) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 1ULL)))
    c2fb_temp_15 = Cast(UByte, (*c2fb_temp_14))
    c2fb_temp_16 = Cast(SQLITE_C_INT, sqlite3ResolveExprNames(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local2))), CPtr(Any Ptr, arg2)))
    local4 = c2fb_temp_16
    c2fb_temp_17 = @(local3->suppressErr)
    c2fb_temp_18 = Cast(UByte, local5)
    (*c2fb_temp_17) = Cast(u8, Cast(UByte, local5))
    c2fb_temp_18 = Cast(UByte, (*c2fb_temp_17))
    If local4 Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_19 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_19
    While (-Cast(SQLITE_C_INT, ((local0 < local1->nExpr))))
        If (-Cast(SQLITE_C_INT, ((sqlite3ExprCompare(Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local1->a(local0).pExpr)), CPtr(Any Ptr, arg2), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))) < Cast(SQLITE_C_INT, 2ULL))))) Then
            Return Cast(SQLITE_C_INT, (local0 + Cast(SQLITE_C_INT, 1ULL)))
        End If
    c2fb_flow_1:
        c2fb_temp_20 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_20 + 1)))
    Wend
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Sub resolveOutOfRangeError CDecl Alias "resolveOutOfRangeError" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SqliteExpr Ptr)
    sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"%r %s BY term out of range - should be between 1 and %d"), arg2, arg1, arg3)
    sqlite3RecordErrorOffsetOfExpr(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, arg4))
End Sub

Private Function resolveCompoundOrderBy CDecl Alias "resolveCompoundOrderBy" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SqliteExprList Ptr
    Dim local2 As SqliteExprList Ptr
    Dim local3 As sqlite3 Ptr
    Dim local4 As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteExprList Ptr
    Dim c2fb_temp_1 As sqlite3 Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As Any Ptr Ptr
    Dim c2fb_temp_7 As SqliteSelect Ptr
    Dim c2fb_temp_8 As Any Ptr Ptr
    Dim c2fb_temp_9 As SqliteSelect Ptr
    Dim c2fb_temp_10 As SqliteSelect Ptr
    Dim local5 As SqliteExprListItem Ptr
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SqliteExprList Ptr
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SqliteExprListItem Ptr
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SqliteExprListItem Ptr
    Dim local6 As SQLITE_C_INT
    Dim local7 As SqliteExpr Ptr
    Dim local8 As SqliteExpr Ptr
    Dim c2fb_temp_17 As SqliteExpr Ptr
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As SqliteExpr Ptr
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim local9 As SqliteExpr Ptr
    Dim c2fb_temp_21 As Any Ptr Ptr
    Dim c2fb_temp_22 As SqliteExpr Ptr
    Dim local10 As SqliteExpr Ptr
    Dim c2fb_temp_23 As SqliteExpr Ptr
    Dim c2fb_temp_24 As Any Ptr Ptr
    Dim c2fb_temp_25 As SqliteExpr Ptr
    Dim c2fb_temp_26 As UShort Ptr
    Dim c2fb_temp_27 As UShort
    Dim c2fb_temp_28 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_29 As SQLITE_C_INT
    Dim c2fb_temp_30 As SQLITE_C_INT
    Dim c2fb_temp_31 As SqliteSelect Ptr
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local4 = Cast(SQLITE_C_INT, 1ULL)
    c2fb_temp_0 = CPtr(SqliteExprList Ptr, arg1->pOrderBy)
    local1 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_1 = arg0->db
    local3 = c2fb_temp_1
    If (-Cast(SQLITE_C_INT, ((local1->nExpr > local3->aLimit(Cast(SQLITE_C_INT, 2ULL)))))) Then
        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"too many terms in ORDER BY clause"))
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_2
    While (-Cast(SQLITE_C_INT, ((local0 < local1->nExpr))))
        c2fb_temp_4 = @(local1->a(local0).fg.flags)
        c2fb_temp_5 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))) And Cast(SQLITE_C_UINT, &H1ULL)))
        (*c2fb_temp_4) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_4)) And Not(Cast(SQLITE_C_UINT, &H4ULL))) Or ((Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 2)))
        c2fb_temp_5 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))) And Cast(SQLITE_C_UINT, &H1ULL)))
    c2fb_flow_1:
        c2fb_temp_3 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_3 + 1)))
    Wend
    c2fb_flow_0:
    c2fb_temp_6 = @(arg1->pNext)
    c2fb_temp_7 = CPtr(SqliteSelect Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_6) = CPtr(Any Ptr, CPtr(SqliteSelect Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
    c2fb_temp_7 = CPtr(SqliteSelect Ptr, (*c2fb_temp_6))
    While CPtr(SqliteSelect Ptr, arg1->pPrior)
        c2fb_temp_8 = @(CPtr(SqliteSelect Ptr, arg1->pPrior)->pNext)
        c2fb_temp_9 = arg1
        (*c2fb_temp_8) = CPtr(Any Ptr, arg1)
        c2fb_temp_9 = CPtr(SqliteSelect Ptr, (*c2fb_temp_8))
        c2fb_temp_10 = CPtr(SqliteSelect Ptr, arg1->pPrior)
        arg1 = c2fb_temp_10
    c2fb_flow_3:
    Wend
    c2fb_flow_2:
    While (-Cast(SQLITE_C_INT, ((arg1 AndAlso local4))))
        ' C automatic storage declaration
        c2fb_temp_11 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local4 = c2fb_temp_11
        c2fb_temp_12 = CPtr(SqliteExprList Ptr, arg1->pEList)
        local2 = c2fb_temp_12
        ' C unused-parameter annotation
        c2fb_temp_13 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local0 = c2fb_temp_13
        c2fb_temp_14 = CPtr(SqliteExprListItem Ptr, (@local1->a(0)))
        local5 = c2fb_temp_14
        While (-Cast(SQLITE_C_INT, ((local0 < local1->nExpr))))
            local6 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))
            ' C automatic storage declaration
            ' C automatic storage declaration
            If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local5->fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                Goto c2fb_flow_7
            End If
            c2fb_temp_17 = CPtr(SqliteExpr Ptr, sqlite3ExprSkipCollateAndLikely(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local5->pExpr))))
            local7 = c2fb_temp_17
            If ((-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, &O0ULL)))))) Then
                Goto c2fb_flow_7
            End If
            If sqlite3ExprIsInteger(CPtr(Any Ptr, local7), CPtr(SQLITE_C_INT Ptr, @(local6)), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)) Then
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local6 <= Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local6 > local2->nExpr)))))))) Then
                    resolveOutOfRangeError(arg0, StrPtr(!"ORDER"), Cast(SQLITE_C_INT, (local0 + Cast(SQLITE_C_INT, 1ULL))), local2->nExpr, local7)
                    Return Cast(SQLITE_C_INT, 1ULL)
                End If
            Else
                c2fb_temp_18 = Cast(SQLITE_C_INT, resolveAsName(arg0, local2, local7))
                local6 = c2fb_temp_18
                If (-Cast(SQLITE_C_INT, ((local6 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_19 = CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local3), CPtr(Any Ptr, local7), Cast(SQLITE_C_INT, &O0ULL)))
                    local8 = c2fb_temp_19
                    If (-Cast(SQLITE_C_INT, (local3->mallocFailed = 0))) Then
                        ' C unused-parameter annotation
                        c2fb_temp_20 = Cast(SQLITE_C_INT, resolveOrderByTermToExprList(arg0, arg1, local8))
                        local6 = c2fb_temp_20
                        If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->eParseMode) >= Cast(SQLITE_C_INT, 2ULL)))))) AndAlso (-Cast(SQLITE_C_INT, ((local6 > Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                            resolveOrderByTermToExprList(arg0, arg1, local7)
                        End If
                    End If
                    sqlite3ExprDelete(CPtr(Any Ptr, local3), CPtr(Any Ptr, local8))
                End If
            End If
            If (-Cast(SQLITE_C_INT, ((local6 > Cast(SQLITE_C_INT, &O0ULL))))) Then
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->eParseMode) >= Cast(SQLITE_C_INT, 2ULL)))))) = 0))) Then
                    local9 = CPtr(SqliteExpr Ptr, sqlite3ExprInt32(CPtr(Any Ptr, local3), local6))
                    If (-Cast(SQLITE_C_INT, ((local9 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        Return Cast(SQLITE_C_INT, 1ULL)
                    End If
                    If (-Cast(SQLITE_C_INT, ((CPtr(SqliteExpr Ptr, local5->pExpr) = local7)))) Then
                        c2fb_temp_21 = @(local5->pExpr)
                        c2fb_temp_22 = local9
                        (*c2fb_temp_21) = CPtr(Any Ptr, local9)
                        c2fb_temp_22 = CPtr(SqliteExpr Ptr, (*c2fb_temp_21))
                    Else
                        local10 = CPtr(SqliteExpr Ptr, local5->pExpr)
                        ' C unused-parameter annotation
                        While (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(SqliteExpr Ptr, local10->pLeft)->op) = Cast(SQLITE_C_INT, 114ULL)))))
                            c2fb_temp_23 = CPtr(SqliteExpr Ptr, local10->pLeft)
                            local10 = c2fb_temp_23
                        c2fb_flow_9:
                        Wend
                        c2fb_flow_8:
                        ' C unused-parameter annotation
                        c2fb_temp_24 = @(local10->pLeft)
                        c2fb_temp_25 = local9
                        (*c2fb_temp_24) = CPtr(Any Ptr, local9)
                        c2fb_temp_25 = CPtr(SqliteExpr Ptr, (*c2fb_temp_24))
                    End If
                    sqlite3ExprDelete(CPtr(Any Ptr, local3), CPtr(Any Ptr, local7))
                    c2fb_temp_26 = @(local5->u.x.iOrderByCol)
                    c2fb_temp_27 = Cast(UShort, Cast(UShort, local6))
                    (*c2fb_temp_26) = c2fb_temp_27
                End If
                c2fb_temp_28 = @(local5->fg.flags)
                c2fb_temp_29 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))) And Cast(SQLITE_C_UINT, &H1ULL)))
                (*c2fb_temp_28) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_28)) And Not(Cast(SQLITE_C_UINT, &H4ULL))) Or ((Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 2)))
                c2fb_temp_29 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))) And Cast(SQLITE_C_UINT, &H1ULL)))
            Else
                c2fb_temp_30 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                local4 = c2fb_temp_30
            End If
        c2fb_flow_7:
            c2fb_temp_15 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_15 + 1)))
            c2fb_temp_16 = local5
            local5 = (c2fb_temp_16 + 1)
        Wend
        c2fb_flow_6:
        c2fb_temp_31 = CPtr(SqliteSelect Ptr, arg1->pNext)
        arg1 = c2fb_temp_31
    c2fb_flow_5:
    Wend
    c2fb_flow_4:
    c2fb_temp_32 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_32
    While (-Cast(SQLITE_C_INT, ((local0 < local1->nExpr))))
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->a(local0).fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
            sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"%r ORDER BY term does not match any column in the result set"), Cast(SQLITE_C_INT, (local0 + Cast(SQLITE_C_INT, 1ULL))))
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
    c2fb_flow_11:
        c2fb_temp_33 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_33 + 1)))
    Wend
    c2fb_flow_10:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Function sqlite3ResolveOrderGroupBy CDecl Alias "sqlite3ResolveOrderGroupBy" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteExprList Ptr, ByVal arg3 As Const ZString Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As sqlite3 Ptr
    Dim local2 As SqliteExprList Ptr
    Dim local3 As SqliteExprListItem Ptr
    Dim c2fb_temp_0 As SqliteExprList Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SqliteExprListItem Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SqliteExprListItem Ptr

    ' C automatic storage declaration
    local1 = arg0->db
    ' C automatic storage declaration
    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg2 = Cast(SQLITE_C_INT, &O0ULL))))) OrElse Cast(SQLITE_C_INT, arg0->db->mallocFailed))))) OrElse ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->eParseMode) >= Cast(SQLITE_C_INT, 2ULL)))))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((arg2->nExpr > local1->aLimit(Cast(SQLITE_C_INT, 2ULL)))))) Then
        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"too many terms in %s BY clause"), arg3)
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    c2fb_temp_0 = CPtr(SqliteExprList Ptr, arg1->pEList)
    local2 = c2fb_temp_0
    ' C unused-parameter annotation
    c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_1
    c2fb_temp_2 = CPtr(SqliteExprListItem Ptr, (@arg2->a(0)))
    local3 = c2fb_temp_2
    While (-Cast(SQLITE_C_INT, ((local0 < arg2->nExpr))))
        If local3->u.x.iOrderByCol Then
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->u.x.iOrderByCol) > local2->nExpr)))) Then
                resolveOutOfRangeError(arg0, arg3, Cast(SQLITE_C_INT, (local0 + Cast(SQLITE_C_INT, 1ULL))), local2->nExpr, Cast(SQLITE_C_INT, &O0ULL))
                Return Cast(SQLITE_C_INT, 1ULL)
            End If
            resolveAlias(arg0, local2, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local3->u.x.iOrderByCol) - Cast(SQLITE_C_INT, 1ULL))), CPtr(SqliteExpr Ptr, local3->pExpr), Cast(SQLITE_C_INT, &O0ULL))
        End If
    c2fb_flow_1:
        c2fb_temp_3 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_3 + 1)))
        c2fb_temp_4 = local3
        local3 = (c2fb_temp_4 + 1)
    Wend
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

#ifndef SQLITE_OMIT_WINDOWFUNC
Private Function resolveRemoveWindowsCb CDecl Alias "resolveRemoveWindowsCb" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim local0 As SqliteWalkerWindow Ptr

    ' C unused-parameter annotation
    If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H1000000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
        local0 = CPtr(SqliteWalkerWindow Ptr, arg1->y.pWin)
        sqlite3WindowUnlinkFromSelect(CPtr(Any Ptr, local0))
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function
#endif

Private Function resolveOrderGroupBy CDecl Alias "resolveOrderGroupBy" (ByVal arg0 As SqliteNameContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteExprList Ptr, ByVal arg3 As Const ZString Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As SqliteExprListItem Ptr
    Dim local4 As SqliteParseContext Ptr
    Dim local5 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SqliteParseContext Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SqliteExprListItem Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SqliteExprListItem Ptr
    Dim local6 As SqliteExpr Ptr
    Dim local7 As SqliteExpr Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As UShort Ptr
    Dim c2fb_temp_8 As UShort
    Dim c2fb_temp_9 As UShort Ptr
    Dim c2fb_temp_10 As UShort
    Dim c2fb_temp_11 As UShort Ptr
    Dim c2fb_temp_12 As UShort
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As UShort Ptr
    Dim c2fb_temp_16 As UShort

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, CPtr(SqliteExprList Ptr, arg1->pEList)->nExpr)
    local5 = c2fb_temp_0
    c2fb_temp_1 = arg0->pParse
    local4 = c2fb_temp_1
    c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_2
    c2fb_temp_3 = CPtr(SqliteExprListItem Ptr, (@arg2->a(0)))
    local3 = c2fb_temp_3
    While (-Cast(SQLITE_C_INT, ((local0 < arg2->nExpr))))
        local6 = CPtr(SqliteExpr Ptr, local3->pExpr)
        local7 = CPtr(SqliteExpr Ptr, sqlite3ExprSkipCollateAndLikely(CPtr(Any Ptr, local6)))
        If ((-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, &O0ULL)))))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(Const Byte Ptr, arg3)[Cast(SQLITE_C_INT, &O0ULL)]) <> Cast(SQLITE_C_INT, 71))))) Then
            c2fb_temp_6 = Cast(SQLITE_C_INT, resolveAsName(local4, CPtr(SqliteExprList Ptr, arg1->pEList), local7))
            local2 = c2fb_temp_6
            If (-Cast(SQLITE_C_INT, ((local2 > Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_7 = @(local3->u.x.iOrderByCol)
                c2fb_temp_8 = Cast(UShort, Cast(UShort, local2))
                (*c2fb_temp_7) = c2fb_temp_8
                Goto c2fb_flow_1
            End If
        End If
        If sqlite3ExprIsInteger(CPtr(Any Ptr, local7), CPtr(SQLITE_C_INT Ptr, @(local2)), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)) Then
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local2 < Cast(SQLITE_C_INT, 1ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local2 > Cast(SQLITE_C_INT, &HffffULL))))))))) Then
                resolveOutOfRangeError(local4, arg3, Cast(SQLITE_C_INT, (local0 + Cast(SQLITE_C_INT, 1ULL))), local5, local7)
                Return Cast(SQLITE_C_INT, 1ULL)
            End If
            c2fb_temp_9 = @(local3->u.x.iOrderByCol)
            c2fb_temp_10 = Cast(UShort, Cast(UShort, local2))
            (*c2fb_temp_9) = c2fb_temp_10
            Goto c2fb_flow_1
        End If
        c2fb_temp_11 = @(local3->u.x.iOrderByCol)
        c2fb_temp_12 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_11) = c2fb_temp_12
        If sqlite3ResolveExprNames(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local6)) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
        c2fb_temp_13 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local1 = c2fb_temp_13
        While (-Cast(SQLITE_C_INT, ((local1 < CPtr(SqliteExprList Ptr, arg1->pEList)->nExpr))))
            If (-Cast(SQLITE_C_INT, ((sqlite3ExprCompare(Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, local6), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, CPtr(SqliteExprList Ptr, arg1->pEList)->a(local1).pExpr)), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                windowRemoveExprFromSelect(arg1, local6)
                c2fb_temp_15 = @(local3->u.x.iOrderByCol)
                c2fb_temp_16 = Cast(UShort, Cast(SQLITE_C_INT, (local1 + Cast(SQLITE_C_INT, 1ULL))))
                (*c2fb_temp_15) = c2fb_temp_16
            End If
        c2fb_flow_3:
            c2fb_temp_14 = local1
            local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_14 + 1)))
        Wend
        c2fb_flow_2:
    c2fb_flow_1:
        c2fb_temp_4 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_4 + 1)))
        c2fb_temp_5 = local3
        local3 = (c2fb_temp_5 + 1)
    Wend
    c2fb_flow_0:
    Return sqlite3ResolveOrderGroupBy(CPtr(Any Ptr, local4), CPtr(Any Ptr, arg1), CPtr(Any Ptr, arg2), arg3)
End Function

Private Function resolveSelectStep CDecl Alias "resolveSelectStep" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteSelect Ptr) As SQLITE_C_INT
    Dim local0 As SqliteNameContext Ptr
    Dim local1 As SqliteNameContext
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim local4 As SqliteParseContext Ptr
    Dim local5 As SQLITE_C_INT
    Dim local6 As SqliteExprList Ptr
    Dim local7 As SqliteSelect Ptr
    Dim local8 As sqlite3 Ptr
    Dim c2fb_temp_0 As SqliteNameContext Ptr
    Dim c2fb_temp_1 As SqliteParseContext Ptr
    Dim c2fb_temp_2 As sqlite3 Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SqliteSelect Ptr
    Dim c2fb_temp_6 As u32 Ptr
    Dim c2fb_temp_7 As SQLITE_C_UINT
    Dim c2fb_temp_8 As Any Ptr
    Dim c2fb_temp_9 As SqliteParseContext Ptr Ptr
    Dim c2fb_temp_10 As SqliteParseContext Ptr
    Dim c2fb_temp_11 As SqliteSelect Ptr Ptr
    Dim c2fb_temp_12 As SqliteSelect Ptr
    Dim local9 As SqliteSelect Ptr
    Dim c2fb_temp_13 As SqliteSelect Ptr
    Dim c2fb_temp_14 As Any Ptr Ptr
    Dim c2fb_temp_15 As SqliteExprList Ptr
    Dim c2fb_temp_16 As Any Ptr Ptr
    Dim c2fb_temp_17 As SqliteExprList Ptr
    Dim c2fb_temp_18 As u32 Ptr
    Dim c2fb_temp_19 As SQLITE_C_UINT
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As SQLITE_C_INT
    Dim local10 As SqliteSrcItem Ptr
    Dim local11 As SQLITE_C_INT
    Dim local12 As Const ZString Ptr
    Dim c2fb_temp_22 As Const ZString Ptr Ptr
    Dim c2fb_temp_23 As Const ZString Ptr
    Dim c2fb_temp_24 As Const ZString Ptr Ptr
    Dim c2fb_temp_25 As Const ZString Ptr
    Dim c2fb_temp_26 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim c2fb_temp_28 As u32 Ptr
    Dim c2fb_temp_29 As SQLITE_C_UINT
    Dim c2fb_temp_30 As SQLITE_C_INT Ptr
    Dim c2fb_temp_31 As SQLITE_C_INT
    Dim c2fb_temp_32 As SqliteSrcList Ptr Ptr
    Dim c2fb_temp_33 As SqliteSrcList Ptr
    Dim c2fb_temp_34 As SqliteNameContext Ptr Ptr
    Dim c2fb_temp_35 As SqliteNameContext Ptr
    Dim c2fb_temp_36 As SQLITE_C_INT Ptr
    Dim c2fb_temp_37 As SQLITE_C_INT
    Dim c2fb_temp_38 As SqliteExprList Ptr
    Dim c2fb_temp_39 As u32 Ptr
    Dim c2fb_temp_40 As SQLITE_C_UINT
    Dim c2fb_temp_41 As SQLITE_C_INT Ptr
    Dim c2fb_temp_42 As SQLITE_C_INT
    Dim c2fb_temp_43 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_44 As SqliteExprList Ptr
    Dim c2fb_temp_45 As SQLITE_C_INT Ptr
    Dim c2fb_temp_46 As SQLITE_C_INT
    Dim c2fb_temp_47 As SQLITE_C_INT Ptr
    Dim c2fb_temp_48 As SQLITE_C_INT
    Dim c2fb_temp_49 As SQLITE_C_INT Ptr
    Dim c2fb_temp_50 As SQLITE_C_INT
    Dim c2fb_temp_51 As SQLITE_C_INT
    Dim c2fb_temp_52 As SQLITE_C_INT
    Dim local13 As SqliteSrcItem Ptr
#ifndef SQLITE_OMIT_WINDOWFUNC
    Dim local14 As SqliteWalkerWindow Ptr
    Dim c2fb_temp_53 As SqliteWalkerWindow Ptr
    Dim c2fb_temp_54 As SqliteWalkerWindow Ptr
#endif
    Dim c2fb_temp_55 As SQLITE_C_INT Ptr
    Dim c2fb_temp_56 As SQLITE_C_INT
    Dim local15 As SqliteSelect Ptr
    Dim c2fb_temp_57 As SqliteSelect Ptr
    Dim c2fb_temp_58 As Any Ptr Ptr
    Dim c2fb_temp_59 As SqliteExprList Ptr
    Dim c2fb_temp_60 As Any Ptr Ptr
    Dim c2fb_temp_61 As SqliteExprList Ptr
    Dim c2fb_temp_62 As SQLITE_C_INT Ptr
    Dim c2fb_temp_63 As SQLITE_C_INT
    Dim local16 As SqliteExprListItem Ptr
    Dim c2fb_temp_64 As SQLITE_C_INT
    Dim c2fb_temp_65 As SqliteExprListItem Ptr
    Dim c2fb_temp_66 As SQLITE_C_INT
    Dim c2fb_temp_67 As SqliteExprListItem Ptr
    Dim c2fb_temp_68 As SqliteSelect Ptr
    Dim c2fb_temp_69 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    If Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000004ULL)))) Then
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    c2fb_temp_0 = CPtr(SqliteNameContext Ptr, arg0->u.pNC)
    local0 = c2fb_temp_0
    c2fb_temp_1 = arg0->pParse
    local4 = c2fb_temp_1
    c2fb_temp_2 = local4->db
    local8 = c2fb_temp_2
    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000040ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
        sqlite3SelectPrep(CPtr(Any Ptr, local4), CPtr(Any Ptr, arg1), CPtr(Any Ptr, local0))
        Return IIf(local4->nErr, Cast(SQLITE_C_INT, 2ULL), Cast(SQLITE_C_INT, 1ULL))
    End If
    c2fb_temp_3 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, ((CPtr(SqliteSelect Ptr, arg1->pPrior) <> Cast(SQLITE_C_INT, &O0ULL))))))
    local2 = c2fb_temp_3
    c2fb_temp_4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local3 = c2fb_temp_4
    c2fb_temp_5 = arg1
    local7 = c2fb_temp_5
    While arg1
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        c2fb_temp_6 = @(arg1->selFlags)
        c2fb_temp_7 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_6)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000004ULL)))))
        (*c2fb_temp_6) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_6)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000004ULL))))))
        c2fb_temp_7 = Cast(SQLITE_C_UINT, (*c2fb_temp_6))
        c2fb_temp_8 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local1))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteNameContext))))
        c2fb_temp_9 = @(local1.pParse)
        c2fb_temp_10 = local4
        (*c2fb_temp_9) = c2fb_temp_10
        c2fb_temp_11 = @(local1.pWinSelect)
        c2fb_temp_12 = arg1
        (*c2fb_temp_11) = c2fb_temp_12
        If sqlite3ResolveExprNames(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local1))), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg1->pLimit))) Then
            Return Cast(SQLITE_C_INT, 2ULL)
        End If
        If Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0010000ULL)))) Then
            ' C automatic storage declaration
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_13 = CPtr(SqliteSelect Ptr, CPtr(SqliteSubquery Ptr, CPtr(SqliteSrcList Ptr, arg1->pSrc)->a(Cast(SQLITE_C_INT, &O0ULL)).u4.pSubq)->pSelect)
            local9 = c2fb_temp_13
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_14 = @(local9->pOrderBy)
            c2fb_temp_15 = CPtr(SqliteExprList Ptr, arg1->pOrderBy)
            (*c2fb_temp_14) = CPtr(Any Ptr, CPtr(SqliteExprList Ptr, arg1->pOrderBy))
            c2fb_temp_15 = CPtr(SqliteExprList Ptr, (*c2fb_temp_14))
            c2fb_temp_16 = @(arg1->pOrderBy)
            c2fb_temp_17 = CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            (*c2fb_temp_16) = CPtr(Any Ptr, CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
            c2fb_temp_17 = CPtr(SqliteExprList Ptr, (*c2fb_temp_16))
        End If
        If local0 Then
            c2fb_temp_18 = @(local0->nNestedSelect)
            c2fb_temp_19 = Cast(SQLITE_C_UINT, (*c2fb_temp_18))
            (*c2fb_temp_18) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_19 + 1)))
        End If
        c2fb_temp_20 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local5 = c2fb_temp_20
        While (-Cast(SQLITE_C_INT, ((local5 < CPtr(SqliteSrcList Ptr, arg1->pSrc)->nSrc))))
            local10 = CPtr(SqliteSrcItem Ptr, @(CPtr(SqliteSrcList Ptr, arg1->pSrc)->a(local5)))
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local10->fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (CPtr(SqliteSelect Ptr, CPtr(SqliteSubquery Ptr, local10->u4.pSubq)->pSelect)->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000004ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
                local11 = IIf(local0, local0->nRef, Cast(SQLITE_C_INT, &O0ULL))
                local12 = local4->zAuthContext
                If local10->zName Then
                    c2fb_temp_22 = @(local4->zAuthContext)
                    c2fb_temp_23 = CPtr(Const ZString Ptr, local10->zName)
                    (*c2fb_temp_22) = c2fb_temp_23
                End If
                sqlite3ResolveSelectNames(CPtr(Any Ptr, local4), CPtr(Any Ptr, CPtr(SqliteSelect Ptr, CPtr(SqliteSubquery Ptr, local10->u4.pSubq)->pSelect)), CPtr(Any Ptr, local0))
                c2fb_temp_24 = @(local4->zAuthContext)
                c2fb_temp_25 = local12
                (*c2fb_temp_24) = c2fb_temp_25
                If local4->nErr Then
                    Return Cast(SQLITE_C_INT, 2ULL)
                End If
                ' C unused-parameter annotation
                If local0 Then
                    ' C unused-parameter annotation
                    c2fb_temp_26 = @(local10->fg.flags)
                    c2fb_temp_27 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, ((local0->nRef > local11))))))) And Cast(SQLITE_C_UINT, &H1ULL)))
                    (*c2fb_temp_26) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_26)) And Not(Cast(SQLITE_C_UINT, &H10ULL))) Or ((Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, ((local0->nRef > local11))))))) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 4)))
                    c2fb_temp_27 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, ((local0->nRef > local11))))))) And Cast(SQLITE_C_UINT, &H1ULL)))
                End If
            End If
        c2fb_flow_3:
            c2fb_temp_21 = local5
            local5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_21 + 1)))
        Wend
        c2fb_flow_2:
        If (-Cast(SQLITE_C_INT, ((local0 AndAlso ((-Cast(SQLITE_C_INT, ((local0->nNestedSelect > Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
            c2fb_temp_28 = @(local0->nNestedSelect)
            c2fb_temp_29 = Cast(SQLITE_C_UINT, (*c2fb_temp_28))
            (*c2fb_temp_28) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_29 - 1)))
        End If
        c2fb_temp_30 = @(local1.ncFlags)
        c2fb_temp_31 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000001ULL) Or Cast(SQLITE_C_INT, &H004000ULL))))
        (*c2fb_temp_30) = c2fb_temp_31
        c2fb_temp_32 = @(local1.pSrcList)
        c2fb_temp_33 = CPtr(SqliteSrcList Ptr, arg1->pSrc)
        (*c2fb_temp_32) = c2fb_temp_33
        c2fb_temp_34 = @(local1.pNext)
        c2fb_temp_35 = local0
        (*c2fb_temp_34) = c2fb_temp_35
        If sqlite3ResolveExprListNames(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local1))), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, arg1->pEList))) Then
            Return Cast(SQLITE_C_INT, 2ULL)
        End If
        c2fb_temp_36 = @(local1.ncFlags)
        c2fb_temp_37 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_36) And Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, &H004000ULL))))))
        (*c2fb_temp_36) = c2fb_temp_37
        ' C unused-parameter annotation
        c2fb_temp_38 = CPtr(SqliteExprList Ptr, arg1->pGroupBy)
        local6 = c2fb_temp_38
        If (-Cast(SQLITE_C_INT, ((local6 OrElse (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (local1.ncFlags And Cast(SQLITE_C_INT, &H000010ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_39 = @(arg1->selFlags)
            c2fb_temp_40 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_39)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0000008ULL) Or (Cast(SQLITE_C_INT, (local1.ncFlags And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H001000ULL) Or Cast(SQLITE_C_INT, &H8000000ULL)))))))))))))
            (*c2fb_temp_39) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_39)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0000008ULL) Or (Cast(SQLITE_C_INT, (local1.ncFlags And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H001000ULL) Or Cast(SQLITE_C_INT, &H8000000ULL))))))))))))))
            c2fb_temp_40 = Cast(SQLITE_C_UINT, (*c2fb_temp_39))
        Else
            c2fb_temp_41 = @(local1.ncFlags)
            c2fb_temp_42 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_41) And Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, &H000001ULL))))))
            (*c2fb_temp_41) = c2fb_temp_42
        End If
        ' C unused-parameter annotation
        c2fb_temp_43 = @(local1.uNC.pEList)
        c2fb_temp_44 = CPtr(SqliteExprList Ptr, arg1->pEList)
        (*c2fb_temp_43) = c2fb_temp_44
        c2fb_temp_45 = @(local1.ncFlags)
        c2fb_temp_46 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_45) Or Cast(SQLITE_C_INT, &H000080ULL))))
        (*c2fb_temp_45) = c2fb_temp_46
        If CPtr(SqliteExpr Ptr, arg1->pHaving) Then
            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000008ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                sqlite3ErrorMsg(CPtr(Any Ptr, local4), StrPtr(!"HAVING clause on a non-aggregate query"))
                Return Cast(SQLITE_C_INT, 2ULL)
            End If
            If sqlite3ResolveExprNames(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local1))), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg1->pHaving))) Then
                Return Cast(SQLITE_C_INT, 2ULL)
            End If
        End If
        c2fb_temp_47 = @(local1.ncFlags)
        c2fb_temp_48 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_47) Or Cast(SQLITE_C_INT, &H100000ULL))))
        (*c2fb_temp_47) = c2fb_temp_48
        If sqlite3ResolveExprNames(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local1))), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg1->pWhere))) Then
            Return Cast(SQLITE_C_INT, 2ULL)
        End If
        c2fb_temp_49 = @(local1.ncFlags)
        c2fb_temp_50 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_49) And Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, &H100000ULL))))))
        (*c2fb_temp_49) = c2fb_temp_50
        c2fb_temp_51 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local5 = c2fb_temp_51
        While (-Cast(SQLITE_C_INT, ((local5 < CPtr(SqliteSrcList Ptr, arg1->pSrc)->nSrc))))
            local13 = CPtr(SqliteSrcItem Ptr, @(CPtr(SqliteSrcList Ptr, arg1->pSrc)->a(local5)))
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local13->fg.flags) Shr 3) And Cast(SQLITE_C_UINT, &H1ULL))) AndAlso sqlite3ResolveExprListNames(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local1))), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, local13->u1.pFuncArg))))))) Then
                Return Cast(SQLITE_C_INT, 2ULL)
            End If
        c2fb_flow_5:
            c2fb_temp_52 = local5
            local5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_52 + 1)))
        Wend
        c2fb_flow_4:
#ifndef SQLITE_OMIT_WINDOWFUNC
        If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4->eParseMode) >= Cast(SQLITE_C_INT, 2ULL)))))) Then
            ' C automatic storage declaration
            c2fb_temp_53 = CPtr(SqliteWalkerWindow Ptr, arg1->pWinDefn)
            local14 = c2fb_temp_53
            While local14
                If (-Cast(SQLITE_C_INT, ((sqlite3ResolveExprListNames(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local1))), CPtr(Any Ptr, local14->pOrderBy)) OrElse sqlite3ResolveExprListNames(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local1))), CPtr(Any Ptr, local14->pPartition)))))) Then
                    Return Cast(SQLITE_C_INT, 2ULL)
                End If
            c2fb_flow_7:
                c2fb_temp_54 = local14->pNextWin
                local14 = c2fb_temp_54
            Wend
            c2fb_flow_6:
        End If
#endif
        c2fb_temp_55 = @(local1.ncFlags)
        c2fb_temp_56 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_55) Or Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000001ULL) Or Cast(SQLITE_C_INT, &H004000ULL))))))
        (*c2fb_temp_55) = c2fb_temp_56
        If Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0010000ULL)))) Then
            ' C automatic storage declaration
            ' C unused-parameter annotation
            c2fb_temp_57 = CPtr(SqliteSelect Ptr, CPtr(SqliteSubquery Ptr, CPtr(SqliteSrcList Ptr, arg1->pSrc)->a(Cast(SQLITE_C_INT, &O0ULL)).u4.pSubq)->pSelect)
            local15 = c2fb_temp_57
            ' C unused-parameter annotation
            c2fb_temp_58 = @(arg1->pOrderBy)
            c2fb_temp_59 = CPtr(SqliteExprList Ptr, local15->pOrderBy)
            (*c2fb_temp_58) = CPtr(Any Ptr, CPtr(SqliteExprList Ptr, local15->pOrderBy))
            c2fb_temp_59 = CPtr(SqliteExprList Ptr, (*c2fb_temp_58))
            c2fb_temp_60 = @(local15->pOrderBy)
            c2fb_temp_61 = CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            (*c2fb_temp_60) = CPtr(Any Ptr, CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
            c2fb_temp_61 = CPtr(SqliteExprList Ptr, (*c2fb_temp_60))
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((CPtr(SqliteExprList Ptr, arg1->pOrderBy) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local2 <= local3)))))))) AndAlso resolveOrderGroupBy(CPtr(SqliteNameContext Ptr, @(local1)), arg1, CPtr(SqliteExprList Ptr, arg1->pOrderBy), StrPtr(!"ORDER")))))) Then
            Return Cast(SQLITE_C_INT, 2ULL)
        End If
        If local8->mallocFailed Then
            Return Cast(SQLITE_C_INT, 2ULL)
        End If
        c2fb_temp_62 = @(local1.ncFlags)
        c2fb_temp_63 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_62) And Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, &H004000ULL))))))
        (*c2fb_temp_62) = c2fb_temp_63
        If local6 Then
            ' C automatic storage declaration
            If (-Cast(SQLITE_C_INT, ((resolveOrderGroupBy(CPtr(SqliteNameContext Ptr, @(local1)), arg1, local6, StrPtr(!"GROUP")) OrElse Cast(SQLITE_C_INT, local8->mallocFailed))))) Then
                Return Cast(SQLITE_C_INT, 2ULL)
            End If
            c2fb_temp_64 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local5 = c2fb_temp_64
            c2fb_temp_65 = CPtr(SqliteExprListItem Ptr, (@local6->a(0)))
            local16 = c2fb_temp_65
            While (-Cast(SQLITE_C_INT, ((local5 < local6->nExpr))))
                If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((CPtr(SqliteExpr Ptr, local16->pExpr))->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000010ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                    sqlite3ErrorMsg(CPtr(Any Ptr, local4), StrPtr(!"aggregate functions are not allowed in the GROUP BY clause"))
                    Return Cast(SQLITE_C_INT, 2ULL)
                End If
            c2fb_flow_9:
                c2fb_temp_66 = local5
                local5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_66 + 1)))
                c2fb_temp_67 = local16
                local16 = (c2fb_temp_67 + 1)
            Wend
            c2fb_flow_8:
        End If
        If (-Cast(SQLITE_C_INT, ((CPtr(SqliteSelect Ptr, arg1->pNext) AndAlso (-Cast(SQLITE_C_INT, ((CPtr(SqliteExprList Ptr, arg1->pEList)->nExpr <> CPtr(SqliteExprList Ptr, CPtr(SqliteSelect Ptr, arg1->pNext)->pEList)->nExpr)))))))) Then
            sqlite3SelectWrongNumTermsError(CPtr(Any Ptr, local4), CPtr(Any Ptr, CPtr(SqliteSelect Ptr, arg1->pNext)))
            Return Cast(SQLITE_C_INT, 2ULL)
        End If
        If (Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H40000000ULL))))) Then
            sqlite3SelectCheckOnClauses(CPtr(Any Ptr, local4), CPtr(Any Ptr, arg1))
            If local4->nErr Then
                Return Cast(SQLITE_C_INT, 2ULL)
            End If
        End If
        c2fb_temp_68 = CPtr(SqliteSelect Ptr, arg1->pPrior)
        arg1 = c2fb_temp_68
        c2fb_temp_69 = local3
        local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_69 + 1)))
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    If (-Cast(SQLITE_C_INT, ((local2 AndAlso resolveCompoundOrderBy(local4, local7))))) Then
        Return Cast(SQLITE_C_INT, 2ULL)
    End If
    Return Cast(SQLITE_C_INT, 1ULL)
End Function

Function sqlite3ResolveExprNames CDecl Alias "sqlite3ResolveExprNames" (ByVal arg0 As SqliteNameContext Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SqliteWalker
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SqliteParseContext Ptr Ptr
    Dim c2fb_temp_4 As SqliteParseContext Ptr
    Dim c2fb_temp_5 As SqliteWalkerExprCallback Ptr
    Dim c2fb_temp_6 As Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
    Dim c2fb_temp_7 As SqliteWalkerSelectCallback Ptr
    Dim c2fb_temp_8 As Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
    Dim c2fb_temp_9 As SqliteWalkerSelectCallback2 Ptr
    Dim c2fb_temp_10 As Sub CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr)
    Dim c2fb_temp_11 As Any Ptr Ptr
    Dim c2fb_temp_12 As SqliteNameContext Ptr
    Dim c2fb_temp_13 As SQLITE_C_INT Ptr
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SQLITE_C_INT Ptr
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As u32 Ptr
    Dim c2fb_temp_18 As SQLITE_C_UINT
    Dim c2fb_temp_19 As SQLITE_C_INT Ptr
    Dim c2fb_temp_20 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg0->ncFlags And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000010ULL) Or Cast(SQLITE_C_INT, &H001000ULL))) Or Cast(SQLITE_C_INT, &H008000ULL))) Or Cast(SQLITE_C_INT, &H8000000ULL)))))))
    local0 = c2fb_temp_0
    c2fb_temp_1 = @(arg0->ncFlags)
    c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_1) And Cast(SQLITE_C_INT, (Not (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000010ULL) Or Cast(SQLITE_C_INT, &H001000ULL))) Or Cast(SQLITE_C_INT, &H008000ULL))) Or Cast(SQLITE_C_INT, &H8000000ULL)))))))))
    (*c2fb_temp_1) = c2fb_temp_2
    c2fb_temp_3 = @(local1.pParse)
    c2fb_temp_4 = arg0->pParse
    (*c2fb_temp_3) = c2fb_temp_4
    c2fb_temp_5 = @(local1.xExprCallback)
    c2fb_temp_6 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, ProcPtr(resolveExprStep))
    (*c2fb_temp_5) = Cast(SqliteWalkerExprCallback, CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, ProcPtr(resolveExprStep)))
    c2fb_temp_6 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, (*c2fb_temp_5))
    c2fb_temp_7 = @(local1.xSelectCallback)
    c2fb_temp_8 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, IIf((Cast(SQLITE_C_INT, (arg0->ncFlags And Cast(SQLITE_C_INT, &H080000ULL)))), CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))), CPtr(Any Ptr, ProcPtr(resolveSelectStep))))
    (*c2fb_temp_7) = Cast(SqliteWalkerSelectCallback, CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, IIf((Cast(SQLITE_C_INT, (arg0->ncFlags And Cast(SQLITE_C_INT, &H080000ULL)))), CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))), CPtr(Any Ptr, ProcPtr(resolveSelectStep)))))
    c2fb_temp_8 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, (*c2fb_temp_7))
    c2fb_temp_9 = @(local1.xSelectCallback2)
    c2fb_temp_10 = CPtr(Sub CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr), Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_9) = Cast(SqliteWalkerSelectCallback2, CPtr(Sub CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr), Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
    c2fb_temp_10 = CPtr(Sub CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr), (*c2fb_temp_9))
    c2fb_temp_11 = @(local1.u.pNC)
    c2fb_temp_12 = arg0
    (*c2fb_temp_11) = CPtr(Any Ptr, arg0)
    c2fb_temp_12 = CPtr(SqliteNameContext Ptr, (*c2fb_temp_11))
    c2fb_temp_13 = @(local1.pParse->nHeight)
    c2fb_temp_14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_13) + arg1->nHeight)))
    (*c2fb_temp_13) = c2fb_temp_14
    If sqlite3ExprCheckHeight(CPtr(Any Ptr, local1.pParse), local1.pParse->nHeight) Then
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    ' C unused-parameter annotation
    sqlite3WalkExprNN(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local1))), CPtr(Any Ptr, arg1))
    c2fb_temp_15 = @(local1.pParse->nHeight)
    c2fb_temp_16 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_15) - arg1->nHeight)))
    (*c2fb_temp_15) = c2fb_temp_16
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' empty C statement
    ' empty C statement
    c2fb_temp_17 = @((arg1)->flags)
    c2fb_temp_18 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_17)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (arg0->ncFlags And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000010ULL) Or Cast(SQLITE_C_INT, &H008000ULL)))))))))))
    (*c2fb_temp_17) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_17)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (arg0->ncFlags And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000010ULL) Or Cast(SQLITE_C_INT, &H008000ULL))))))))))))
    c2fb_temp_18 = Cast(SQLITE_C_UINT, (*c2fb_temp_17))
    c2fb_temp_19 = @(arg0->ncFlags)
    c2fb_temp_20 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_19) Or local0)))
    (*c2fb_temp_19) = c2fb_temp_20
    Return (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg0->nNcErr > Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local1.pParse->nErr > Cast(SQLITE_C_INT, &O0ULL)))))))))
End Function

Function sqlite3ResolveExprListNames CDecl Alias "sqlite3ResolveExprListNames" (ByVal arg0 As SqliteNameContext Ptr, ByVal arg1 As SqliteExprList Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim local2 As SqliteWalker
    Dim c2fb_temp_0 As SqliteParseContext Ptr Ptr
    Dim c2fb_temp_1 As SqliteParseContext Ptr
    Dim c2fb_temp_2 As SqliteWalkerExprCallback Ptr
    Dim c2fb_temp_3 As Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
    Dim c2fb_temp_4 As SqliteWalkerSelectCallback Ptr
    Dim c2fb_temp_5 As Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
    Dim c2fb_temp_6 As SqliteWalkerSelectCallback2 Ptr
    Dim c2fb_temp_7 As Sub CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr)
    Dim c2fb_temp_8 As Any Ptr Ptr
    Dim c2fb_temp_9 As SqliteNameContext Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT Ptr
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim local3 As SqliteExpr Ptr
    Dim c2fb_temp_15 As SQLITE_C_INT Ptr
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SQLITE_C_INT Ptr
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As u32 Ptr
    Dim c2fb_temp_20 As SQLITE_C_UINT
    Dim c2fb_temp_21 As SQLITE_C_INT
    Dim c2fb_temp_22 As SQLITE_C_INT Ptr
    Dim c2fb_temp_23 As SQLITE_C_INT
    Dim c2fb_temp_24 As SQLITE_C_INT Ptr
    Dim c2fb_temp_25 As SQLITE_C_INT

    ' C automatic storage declaration
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = @(local2.pParse)
    c2fb_temp_1 = arg0->pParse
    (*c2fb_temp_0) = c2fb_temp_1
    c2fb_temp_2 = @(local2.xExprCallback)
    c2fb_temp_3 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, ProcPtr(resolveExprStep))
    (*c2fb_temp_2) = Cast(SqliteWalkerExprCallback, CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, ProcPtr(resolveExprStep)))
    c2fb_temp_3 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, (*c2fb_temp_2))
    c2fb_temp_4 = @(local2.xSelectCallback)
    c2fb_temp_5 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, ProcPtr(resolveSelectStep))
    (*c2fb_temp_4) = Cast(SqliteWalkerSelectCallback, CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, ProcPtr(resolveSelectStep)))
    c2fb_temp_5 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, (*c2fb_temp_4))
    c2fb_temp_6 = @(local2.xSelectCallback2)
    c2fb_temp_7 = CPtr(Sub CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr), Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_6) = Cast(SqliteWalkerSelectCallback2, CPtr(Sub CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr), Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
    c2fb_temp_7 = CPtr(Sub CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr), (*c2fb_temp_6))
    c2fb_temp_8 = @(local2.u.pNC)
    c2fb_temp_9 = arg0
    (*c2fb_temp_8) = CPtr(Any Ptr, arg0)
    c2fb_temp_9 = CPtr(SqliteNameContext Ptr, (*c2fb_temp_8))
    c2fb_temp_10 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg0->ncFlags And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000010ULL) Or Cast(SQLITE_C_INT, &H001000ULL))) Or Cast(SQLITE_C_INT, &H008000ULL))) Or Cast(SQLITE_C_INT, &H8000000ULL)))))))
    local1 = c2fb_temp_10
    c2fb_temp_11 = @(arg0->ncFlags)
    c2fb_temp_12 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_11) And Cast(SQLITE_C_INT, (Not (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000010ULL) Or Cast(SQLITE_C_INT, &H001000ULL))) Or Cast(SQLITE_C_INT, &H008000ULL))) Or Cast(SQLITE_C_INT, &H8000000ULL)))))))))
    (*c2fb_temp_11) = c2fb_temp_12
    c2fb_temp_13 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_13
    While (-Cast(SQLITE_C_INT, ((local0 < arg1->nExpr))))
        local3 = CPtr(SqliteExpr Ptr, arg1->a(local0).pExpr)
        If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_1
        End If
        c2fb_temp_15 = @(local2.pParse->nHeight)
        c2fb_temp_16 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_15) + local3->nHeight)))
        (*c2fb_temp_15) = c2fb_temp_16
        If sqlite3ExprCheckHeight(CPtr(Any Ptr, local2.pParse), local2.pParse->nHeight) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
        sqlite3WalkExprNN(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local2))), CPtr(Any Ptr, local3))
        c2fb_temp_17 = @(local2.pParse->nHeight)
        c2fb_temp_18 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_17) - local3->nHeight)))
        (*c2fb_temp_17) = c2fb_temp_18
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        ' empty C statement
        ' empty C statement
        If Cast(SQLITE_C_INT, (arg0->ncFlags And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000010ULL) Or Cast(SQLITE_C_INT, &H001000ULL))) Or Cast(SQLITE_C_INT, &H008000ULL))) Or Cast(SQLITE_C_INT, &H8000000ULL)))))) Then
            c2fb_temp_19 = @((local3)->flags)
            c2fb_temp_20 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_19)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (arg0->ncFlags And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000010ULL) Or Cast(SQLITE_C_INT, &H008000ULL)))))))))))
            (*c2fb_temp_19) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_19)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (arg0->ncFlags And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000010ULL) Or Cast(SQLITE_C_INT, &H008000ULL))))))))))))
            c2fb_temp_20 = Cast(SQLITE_C_UINT, (*c2fb_temp_19))
            c2fb_temp_21 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local1 Or Cast(SQLITE_C_INT, (arg0->ncFlags And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000010ULL) Or Cast(SQLITE_C_INT, &H001000ULL))) Or Cast(SQLITE_C_INT, &H008000ULL))) Or Cast(SQLITE_C_INT, &H8000000ULL)))))))))
            local1 = c2fb_temp_21
            c2fb_temp_22 = @(arg0->ncFlags)
            c2fb_temp_23 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_22) And Cast(SQLITE_C_INT, (Not (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000010ULL) Or Cast(SQLITE_C_INT, &H001000ULL))) Or Cast(SQLITE_C_INT, &H008000ULL))) Or Cast(SQLITE_C_INT, &H8000000ULL)))))))))
            (*c2fb_temp_22) = c2fb_temp_23
        End If
        If (-Cast(SQLITE_C_INT, ((local2.pParse->nErr > Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
    c2fb_flow_1:
        c2fb_temp_14 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_14 + 1)))
    Wend
    c2fb_flow_0:
    c2fb_temp_24 = @(arg0->ncFlags)
    c2fb_temp_25 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_24) Or local1)))
    (*c2fb_temp_24) = c2fb_temp_25
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Sub sqlite3ResolveSelectNames CDecl Alias "sqlite3ResolveSelectNames" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteNameContext Ptr)
    Dim local0 As SqliteWalker
    Dim c2fb_temp_0 As SqliteWalkerExprCallback Ptr
    Dim c2fb_temp_1 As Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
    Dim c2fb_temp_2 As SqliteWalkerSelectCallback Ptr
    Dim c2fb_temp_3 As Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
    Dim c2fb_temp_4 As SqliteWalkerSelectCallback2 Ptr
    Dim c2fb_temp_5 As Sub CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr)
    Dim c2fb_temp_6 As SqliteParseContext Ptr Ptr
    Dim c2fb_temp_7 As SqliteParseContext Ptr
    Dim c2fb_temp_8 As Any Ptr Ptr
    Dim c2fb_temp_9 As SqliteNameContext Ptr

    ' C automatic storage declaration
    ' C unused-parameter annotation
    c2fb_temp_0 = @(local0.xExprCallback)
    c2fb_temp_1 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, ProcPtr(resolveExprStep))
    (*c2fb_temp_0) = Cast(SqliteWalkerExprCallback, CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, ProcPtr(resolveExprStep)))
    c2fb_temp_1 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, (*c2fb_temp_0))
    c2fb_temp_2 = @(local0.xSelectCallback)
    c2fb_temp_3 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, ProcPtr(resolveSelectStep))
    (*c2fb_temp_2) = Cast(SqliteWalkerSelectCallback, CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, ProcPtr(resolveSelectStep)))
    c2fb_temp_3 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, (*c2fb_temp_2))
    c2fb_temp_4 = @(local0.xSelectCallback2)
    c2fb_temp_5 = CPtr(Sub CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr), Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_4) = Cast(SqliteWalkerSelectCallback2, CPtr(Sub CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr), Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
    c2fb_temp_5 = CPtr(Sub CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr), (*c2fb_temp_4))
    c2fb_temp_6 = @(local0.pParse)
    c2fb_temp_7 = arg0
    (*c2fb_temp_6) = c2fb_temp_7
    c2fb_temp_8 = @(local0.u.pNC)
    c2fb_temp_9 = arg2
    (*c2fb_temp_8) = CPtr(Any Ptr, arg2)
    c2fb_temp_9 = CPtr(SqliteNameContext Ptr, (*c2fb_temp_8))
    sqlite3WalkSelect(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local0))), CPtr(Any Ptr, arg1))
End Sub

Private Sub incrAggFunctionDepth CDecl Alias "incrAggFunctionDepth" ( _
    ByVal expression As SqliteExpr Ptr, _
    ByVal depth As SQLITE_C_INT _
)
    If expression = 0 OrElse depth <= 0 Then Return

    Dim walker As SqliteWalker
    c2fb_crt_memset(@walker, 0, SizeOf(SqliteWalker))
    walker.xExprCallback = CPtr(SqliteWalkerExprCallback, ProcPtr(incrAggDepth))
    walker.u.n = depth
    sqlite3WalkExpr(@walker, expression)
End Sub

Sub resolveAlias CDecl Alias "resolveAlias" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pEList As SqliteExprList Ptr, _
    ByVal iCol As SQLITE_C_INT, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal nSubquery As SQLITE_C_INT _
)
    If pParse = 0 OrElse pEList = 0 OrElse pExpr = 0 Then Return
    If iCol < 0 OrElse iCol >= pEList->nExpr Then Return
    If pExpr->pAggInfo <> 0 Then Return

    Dim pOrig As SqliteExpr Ptr = pEList->a(iCol).pExpr
    If pOrig = 0 Then Return

    Dim db As sqlite3 Ptr = pParse->db
    Dim pDup As SqliteExpr Ptr = sqlite3ExprDup(db, pOrig, 0)
    If db->mallocFailed <> 0 Then
        sqlite3ExprDelete(db, pDup)
        pDup = 0
    Else
        incrAggFunctionDepth(pDup, nSubquery)
        If pExpr->op = TK_COLLATE Then
            pDup = CPtr(SqliteExpr Ptr, sqlite3ExprAddCollateString( _
                pParse, pDup, CPtr(Const ZString Ptr, pExpr->u.zToken)))
        End If

        Dim savedExpression As SqliteExpr
        savedExpression = *pDup
        *pDup = *pExpr
        *pExpr = savedExpression

#ifndef SQLITE_OMIT_WINDOWFUNC
        If (pExpr->flags And EP_WinFunc) <> 0 Then
            Dim pWindow As SqliteWalkerWindow Ptr = _
                CPtr(SqliteWalkerWindow Ptr, pExpr->y.pWin)
            If pWindow <> 0 Then pWindow->pOwner = pExpr
        End If
#endif
        sqlite3ExprDeferredDelete(pParse, pDup)
    End If
End Sub

#ifndef SQLITE_OMIT_WINDOWFUNC
Sub windowRemoveExprFromSelect CDecl Alias "windowRemoveExprFromSelect" ( _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
)
    If pSelect = 0 OrElse pExpr = 0 OrElse pSelect->pWin = 0 Then Return

    Dim walker As SqliteWalker
    c2fb_crt_memset(@walker, 0, SizeOf(SqliteWalker))
    walker.xExprCallback = CPtr(SqliteWalkerExprCallback, ProcPtr(resolveRemoveWindowsCb))
    walker.u.pSelect = pSelect
    sqlite3WalkExpr(@walker, pExpr)
End Sub
#else
Sub windowRemoveExprFromSelect CDecl Alias "windowRemoveExprFromSelect" ( _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
)
    ' Upstream compiles this call away when window functions are omitted.
End Sub
#endif

Function isValidSchemaTableName CDecl Alias "isValidSchemaTableName" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As SqliteTable Ptr, ByVal arg2 As Const ZString Ptr) As SQLITE_C_INT
    Dim local0 As Const ZString Ptr
    Dim c2fb_temp_0 As Const ZString Ptr

    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((sqlite3_strnicmp(arg0, StrPtr(!"sqlite_"), Cast(SQLITE_C_INT, 7ULL)) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = CPtr(Const ZString Ptr, arg1->zName)
    local0 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, ((c2fb_crt_strcmp(CPtr(Const ZString Ptr, (CPtr(Const Byte Ptr, local0) + Cast(SQLITE_C_INT, 7ULL))), CPtr(Const ZString Ptr, CPtr(Byte Ptr, @(CPtr(Const Byte Ptr, StrPtr(!"sqlite_temp_master"))[Cast(SQLITE_C_INT, 7ULL)])))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
        If (-Cast(SQLITE_C_INT, ((sqlite3StrICmp(CPtr(Const ZString Ptr, (CPtr(Const Byte Ptr, arg0) + Cast(SQLITE_C_INT, 7ULL))), CPtr(Const ZString Ptr, CPtr(Byte Ptr, @(CPtr(Const Byte Ptr, StrPtr(!"sqlite_temp_schema"))[Cast(SQLITE_C_INT, 7ULL)])))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
        If (-Cast(SQLITE_C_INT, ((arg2 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        If (-Cast(SQLITE_C_INT, ((sqlite3StrICmp(CPtr(Const ZString Ptr, (CPtr(Const Byte Ptr, arg0) + Cast(SQLITE_C_INT, 7ULL))), CPtr(Const ZString Ptr, CPtr(Byte Ptr, @(CPtr(Const Byte Ptr, StrPtr(!"sqlite_master"))[Cast(SQLITE_C_INT, 7ULL)])))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
        If (-Cast(SQLITE_C_INT, ((sqlite3StrICmp(CPtr(Const ZString Ptr, (CPtr(Const Byte Ptr, arg0) + Cast(SQLITE_C_INT, 7ULL))), CPtr(Const ZString Ptr, CPtr(Byte Ptr, @(CPtr(Const Byte Ptr, StrPtr(!"sqlite_schema"))[Cast(SQLITE_C_INT, 7ULL)])))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
    Else
        If (-Cast(SQLITE_C_INT, ((sqlite3StrICmp(CPtr(Const ZString Ptr, (CPtr(Const Byte Ptr, arg0) + Cast(SQLITE_C_INT, 7ULL))), CPtr(Const ZString Ptr, CPtr(Byte Ptr, @(CPtr(Const Byte Ptr, StrPtr(!"sqlite_schema"))[Cast(SQLITE_C_INT, 7ULL)])))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Function lookupName CDecl Alias "lookupName" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const SqliteExpr Ptr, ByVal arg4 As SqliteNameContext Ptr, ByVal arg5 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As sqlite3 Ptr
    Dim local6 As SqliteSrcItem Ptr
    Dim local7 As SqliteSrcItem Ptr
    Dim local8 As SqliteNameContext Ptr
    Dim local9 As SqliteSchema Ptr
    Dim local10 As SQLITE_C_INT
    Dim local11 As SqliteTable Ptr
    Dim local12 As SqliteExprList Ptr
    Dim local13 As Const ZString Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As Const ZString Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SqliteSchema Ptr
    Dim c2fb_temp_6 As SqliteSchema Ptr
    Dim c2fb_temp_7 As Const ZString Ptr
    Dim local14 As SqliteExprList Ptr
    Dim local15 As SqliteSrcList Ptr
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SqliteSrcItem Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SqliteSrcItem Ptr
    Dim c2fb_temp_12 As SqliteTable Ptr
    Dim local16 As SQLITE_C_INT
    Dim local17 As SqliteSelect Ptr
    Dim c2fb_temp_13 As SqliteSelect Ptr
    Dim c2fb_temp_14 As SqliteExprList Ptr
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim local18 As SQLITE_C_INT
    Dim c2fb_temp_17 As SqliteExprList Ptr
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As SqliteExprList Ptr
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As SQLITE_C_INT
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim c2fb_temp_23 As SqliteSrcItem Ptr
    Dim c2fb_temp_24 As Short Ptr
    Dim c2fb_temp_25 As Short
    Dim c2fb_temp_26 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim c2fb_temp_28 As SQLITE_C_INT
    Dim c2fb_temp_29 As SqliteExprList Ptr
    Dim c2fb_temp_30 As SQLITE_C_INT
    Dim c2fb_temp_31 As SqliteExprList Ptr
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As SqliteSrcItem Ptr
    Dim c2fb_temp_34 As Short Ptr
    Dim c2fb_temp_35 As Short
    Dim c2fb_temp_36 As SQLITE_C_INT
    Dim c2fb_temp_37 As SqliteSrcItem Ptr
    Dim c2fb_temp_38 As SQLITE_C_INT Ptr
    Dim c2fb_temp_39 As SQLITE_C_INT
    Dim c2fb_temp_40 As Any Ptr Ptr
    Dim c2fb_temp_41 As SqliteTable Ptr
    Dim c2fb_temp_42 As u32 Ptr
    Dim c2fb_temp_43 As SQLITE_C_UINT
    Dim c2fb_temp_44 As SqliteSchema Ptr
    Dim c2fb_temp_45 As SqliteTable Ptr
    Dim local19 As SQLITE_C_INT
    Dim c2fb_temp_46 As SQLITE_C_INT Ptr
    Dim c2fb_temp_47 As SQLITE_C_INT
    Dim c2fb_temp_48 As SqliteTable Ptr
    Dim c2fb_temp_49 As SQLITE_C_INT Ptr
    Dim c2fb_temp_50 As SQLITE_C_INT
    Dim c2fb_temp_51 As SqliteTable Ptr
    Dim c2fb_temp_52 As SQLITE_C_INT Ptr
    Dim c2fb_temp_53 As SQLITE_C_INT
    Dim c2fb_temp_54 As SqliteTable Ptr
    Dim local20 As SqliteUpsert Ptr
    Dim c2fb_temp_55 As SqliteTable Ptr
    Dim c2fb_temp_56 As SQLITE_C_INT Ptr
    Dim c2fb_temp_57 As SQLITE_C_INT
    Dim local21 As SQLITE_C_INT
    Dim c2fb_temp_58 As SqliteSchema Ptr
    Dim c2fb_temp_59 As SQLITE_C_INT
    Dim c2fb_temp_60 As SQLITE_C_INT
    Dim c2fb_temp_61 As SQLITE_C_INT
    Dim c2fb_temp_62 As SQLITE_C_INT
    Dim c2fb_temp_63 As SQLITE_C_INT
    Dim c2fb_temp_64 As SQLITE_C_INT
    Dim c2fb_temp_65 As SqliteSrcItem Ptr
    Dim c2fb_temp_66 As Short Ptr
    Dim c2fb_temp_67 As Short
    Dim c2fb_temp_68 As Any Ptr Ptr
    Dim c2fb_temp_69 As SqliteTable Ptr
    Dim c2fb_temp_70 As SQLITE_C_INT
    Dim c2fb_temp_71 As SQLITE_C_INT Ptr
    Dim c2fb_temp_72 As SQLITE_C_INT
    Dim c2fb_temp_73 As SQLITE_C_INT
    Dim c2fb_temp_74 As Any Ptr Ptr
    Dim c2fb_temp_75 As SqliteTable Ptr
    Dim c2fb_temp_76 As SQLITE_C_INT
    Dim c2fb_temp_77 As u8 Ptr
    Dim c2fb_temp_78 As UByte
    Dim c2fb_temp_79 As Short Ptr
    Dim c2fb_temp_80 As Short
    Dim c2fb_temp_81 As SQLITE_C_INT Ptr
    Dim c2fb_temp_82 As SQLITE_C_INT
    Dim c2fb_temp_83 As Short Ptr
    Dim c2fb_temp_84 As Short
    Dim c2fb_temp_85 As SQLITE_C_INT
    Dim c2fb_temp_86 As Byte Ptr
    Dim c2fb_temp_87 As Byte
    Dim c2fb_temp_88 As u32 Ptr
    Dim c2fb_temp_89 As SQLITE_C_UINT
    Dim c2fb_temp_90 As u32 Ptr
    Dim c2fb_temp_91 As SQLITE_C_UINT
    Dim c2fb_temp_92 As SQLITE_C_INT
    Dim c2fb_temp_93 As Short Ptr
    Dim c2fb_temp_94 As Short
    Dim c2fb_temp_95 As Byte Ptr
    Dim c2fb_temp_96 As Byte
    Dim c2fb_temp_97 As SqliteExprList Ptr
    Dim c2fb_temp_98 As SQLITE_C_INT
    Dim c2fb_temp_99 As SQLITE_C_INT
    Dim local22 As ZString Ptr
    Dim local23 As SqliteExpr Ptr
    Dim c2fb_temp_100 As SqliteExpr Ptr
    Dim c2fb_temp_101 As SQLITE_C_INT
    Dim c2fb_temp_102 As SqliteSrcItem Ptr
    Dim c2fb_temp_103 As SqliteNameContext Ptr
    Dim c2fb_temp_104 As SQLITE_C_INT
    Dim c2fb_temp_105 As u8 Ptr
    Dim c2fb_temp_106 As UByte
    Dim c2fb_temp_107 As Any Ptr
    Dim local24 As Const ZString Ptr
    Dim c2fb_temp_108 As u32 Ptr
    Dim c2fb_temp_109 As SQLITE_C_UINT
    Dim c2fb_temp_110 As Any Ptr Ptr
    Dim c2fb_temp_111 As SqliteExpr Ptr
    Dim c2fb_temp_112 As Any Ptr Ptr
    Dim c2fb_temp_113 As SqliteExpr Ptr
    Dim c2fb_temp_114 As u8 Ptr
    Dim c2fb_temp_115 As UByte
    Dim c2fb_temp_116 As UByte Ptr Ptr
    Dim c2fb_temp_117 As ZString Ptr
    Dim c2fb_temp_118 As Any Ptr Ptr
    Dim c2fb_temp_119 As SqliteExprList Ptr
    Dim c2fb_temp_120 As Byte Ptr
    Dim c2fb_temp_121 As Byte
    Dim c2fb_temp_122 As SQLITE_C_INT
    Dim c2fb_temp_123 As SqliteExprList Ptr
    Dim c2fb_temp_124 As Const ZString Ptr
    Dim c2fb_temp_125 As u8 Ptr
    Dim c2fb_temp_126 As SQLITE_C_INT
    Dim c2fb_temp_127 As SQLITE_C_INT Ptr
    Dim c2fb_temp_128 As SQLITE_C_INT
    Dim c2fb_temp_129 As SQLITE_C_INT
    Dim c2fb_temp_130 As Any Ptr Ptr
    Dim c2fb_temp_131 As SqliteExpr Ptr
    Dim c2fb_temp_132 As Any Ptr Ptr
    Dim c2fb_temp_133 As SqliteExpr Ptr
    Dim c2fb_temp_134 As u32 Ptr
    Dim c2fb_temp_135 As SQLITE_C_UINT
    Dim c2fb_temp_136 As sqlite3_uint64 Ptr
    Dim c2fb_temp_137 As sqlite3_uint64
    Dim c2fb_temp_138 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_139 As SQLITE_C_INT
    Dim c2fb_temp_140 As u8 Ptr
    Dim c2fb_temp_141 As UByte
    Dim c2fb_temp_142 As SQLITE_C_INT
    Dim c2fb_temp_143 As SQLITE_C_INT
    Dim c2fb_temp_144 As SQLITE_C_INT Ptr
    Dim c2fb_temp_145 As SQLITE_C_INT
    Dim c2fb_temp_146 As SqliteNameContext Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    local2 = Cast(SQLITE_C_INT, &O0ULL)
    local3 = Cast(SQLITE_C_INT, &O0ULL)
    local4 = Cast(SQLITE_C_INT, &O0ULL)
    local5 = arg0->db
    ' C automatic storage declaration
    local7 = Cast(SQLITE_C_INT, &O0ULL)
    local8 = arg4
    local9 = Cast(SQLITE_C_INT, &O0ULL)
    local10 = Cast(SQLITE_C_INT, 168ULL)
    local11 = Cast(SQLITE_C_INT, &O0ULL)
    local12 = Cast(SQLITE_C_INT, &O0ULL)
    local13 = CPtr(ZString Ptr, arg3->u.zToken)
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = @(arg5->iTable)
    c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
    (*c2fb_temp_0) = c2fb_temp_1
    ' empty C statement
    If arg1 Then
        ' empty C statement
        ' empty C statement
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (arg4->ncFlags And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000002ULL) Or Cast(SQLITE_C_INT, &H000004ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_2 = CPtr(Const ZString Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            arg1 = c2fb_temp_2
        Else
            c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local0 = c2fb_temp_3
            While (-Cast(SQLITE_C_INT, ((local0 < local5->nDb))))
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, ((sqlite3StrICmp(CPtr(Const ZString Ptr, CPtr(ZString Ptr, local5->aDb(local0).zDbSName)), arg1) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_5 = local5->aDb(local0).pSchema
                    local9 = c2fb_temp_5
                    Goto c2fb_flow_0
                End If
            c2fb_flow_1:
                c2fb_temp_4 = local0
                local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_4 + 1)))
            Wend
            c2fb_flow_0:
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local0 = local5->nDb)))) AndAlso (-Cast(SQLITE_C_INT, ((sqlite3StrICmp(StrPtr(!"main"), arg1) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                c2fb_temp_6 = local5->aDb(Cast(SQLITE_C_INT, &O0ULL)).pSchema
                local9 = c2fb_temp_6
                c2fb_temp_7 = CPtr(Const ZString Ptr, CPtr(ZString Ptr, local5->aDb(Cast(SQLITE_C_INT, &O0ULL)).zDbSName))
                arg1 = c2fb_temp_7
            End If
        End If
    End If
    ' C unused-parameter annotation
    Do
        ' C automatic storage declaration
        local15 = arg4->pSrcList
        If local15 Then
            c2fb_temp_8 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local0 = c2fb_temp_8
            c2fb_temp_9 = CPtr(SqliteSrcItem Ptr, (@local15->a(0)))
            local6 = c2fb_temp_9
            While (-Cast(SQLITE_C_INT, ((local0 < local15->nSrc))))
                c2fb_temp_12 = CPtr(SqliteTable Ptr, local6->pSTab)
                local11 = c2fb_temp_12
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local6->fg.flags) Shr 14) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                    local16 = Cast(SQLITE_C_INT, &O0ULL)
                    ' C automatic storage declaration
                    ' C unused-parameter annotation
                    ' C unused-parameter annotation
                    c2fb_temp_13 = CPtr(SqliteSelect Ptr, CPtr(SqliteSubquery Ptr, local6->u4.pSubq)->pSelect)
                    local17 = c2fb_temp_13
                    ' C unused-parameter annotation
                    c2fb_temp_14 = CPtr(SqliteExprList Ptr, local17->pEList)
                    local14 = c2fb_temp_14
                    ' C unused-parameter annotation
                    ' C unused-parameter annotation
                    c2fb_temp_15 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    local1 = c2fb_temp_15
                    While (-Cast(SQLITE_C_INT, ((local1 < local14->nExpr))))
                        local18 = Cast(SQLITE_C_INT, &O0ULL)
                        If (-Cast(SQLITE_C_INT, (sqlite3MatchEName(CPtr(Any Ptr, CPtr(SqliteExprListItem Ptr, @(local14->a(local1)))), local13, arg2, arg1, CPtr(SQLITE_C_INT Ptr, @(local18))) = 0))) Then
                            Goto c2fb_flow_7
                        End If
                        If (-Cast(SQLITE_C_INT, ((local18 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                            If (-Cast(SQLITE_C_INT, ((local2 > Cast(SQLITE_C_INT, &O0ULL))))) Then
                                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local6->fg.flags) Shr 11) And Cast(SQLITE_C_UINT, &H1ULL))) = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((sqlite3IdListIndex(CPtr(Any Ptr, CPtr(SqliteIdList Ptr, local6->u3.pUsing)), local13) < Cast(SQLITE_C_INT, &O0ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local7 = local6)))))))) Then
                                    sqlite3ExprListDelete(CPtr(Any Ptr, local5), CPtr(Any Ptr, local12))
                                    c2fb_temp_17 = CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                                    local12 = c2fb_temp_17
                                Else
                                    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local6->fg.jointype) And Cast(SQLITE_C_INT, &H10ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                                        Goto c2fb_flow_7
                                    Else
                                        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local6->fg.jointype) And Cast(SQLITE_C_INT, &H08ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                                            c2fb_temp_18 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                                            local2 = c2fb_temp_18
                                            sqlite3ExprListDelete(CPtr(Any Ptr, local5), CPtr(Any Ptr, local12))
                                            c2fb_temp_19 = CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                                            local12 = c2fb_temp_19
                                        Else
                                            extendFJMatch(arg0, CPtr(SqliteExprList Ptr Ptr, @(local12)), local7, arg5->iColumn)
                                        End If
                                    End If
                                End If
                            End If
                            c2fb_temp_20 = local2
                            local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_20 + 1)))
                            c2fb_temp_21 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                            local16 = c2fb_temp_21
                        Else
                            If (-Cast(SQLITE_C_INT, ((local2 > Cast(SQLITE_C_INT, &O0ULL))))) Then
                                Goto c2fb_flow_7
                            End If
                        End If
                        c2fb_temp_22 = local3
                        local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_22 + 1)))
                        c2fb_temp_23 = local6
                        local7 = c2fb_temp_23
                        c2fb_temp_24 = @(arg5->iColumn)
                        c2fb_temp_25 = Cast(Short, local1)
                        (*c2fb_temp_24) = c2fb_temp_25
                        c2fb_temp_26 = @(local14->a(local1).fg.flags)
                        c2fb_temp_27 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))) And Cast(SQLITE_C_UINT, &H1ULL)))
                        (*c2fb_temp_26) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_26)) And Not(Cast(SQLITE_C_UINT, &H40ULL))) Or ((Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 6)))
                        c2fb_temp_27 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))) And Cast(SQLITE_C_UINT, &H1ULL)))
                        ' C unused-parameter annotation
                        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local14->a(local1).fg.flags) Shr 7) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                            Goto c2fb_flow_6
                        End If
                    c2fb_flow_7:
                        c2fb_temp_16 = local1
                        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_16 + 1)))
                    Wend
                    c2fb_flow_6:
                    If (-Cast(SQLITE_C_INT, ((local16 OrElse (-Cast(SQLITE_C_INT, ((arg2 = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                        Goto c2fb_flow_5
                    End If
                End If
                ' C unused-parameter annotation
                If arg2 Then
                    If arg1 Then
                        If (-Cast(SQLITE_C_INT, ((CPtr(SqliteSchema Ptr, local11->pSchema) <> local9)))) Then
                            Goto c2fb_flow_5
                        End If
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local9 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((c2fb_crt_strcmp(arg1, StrPtr(!"*")) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                            Goto c2fb_flow_5
                        End If
                    End If
                    If (-Cast(SQLITE_C_INT, ((local6->zAlias <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                        If (-Cast(SQLITE_C_INT, ((sqlite3StrICmp(arg2, CPtr(Const ZString Ptr, local6->zAlias)) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                            Goto c2fb_flow_5
                        End If
                    Else
                        If (-Cast(SQLITE_C_INT, ((sqlite3StrICmp(arg2, CPtr(Const ZString Ptr, local11->zName)) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                            If (-Cast(SQLITE_C_INT, ((local11->tnum <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))) Then
                                Goto c2fb_flow_5
                            End If
                            If (-Cast(SQLITE_C_INT, (isValidSchemaTableName(arg2, local11, arg1) = 0))) Then
                                Goto c2fb_flow_5
                            End If
                        End If
                    End If
                    ' C unused-parameter annotation
                    If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->eParseMode) >= Cast(SQLITE_C_INT, 2ULL)))))) AndAlso local6->zAlias)))) Then
                        sqlite3RenameTokenRemap(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, CPtr(SqliteTable Ptr Ptr, @(arg5->y.pTab))))
                    End If
                End If
                c2fb_temp_28 = Cast(SQLITE_C_INT, sqlite3ColumnIndex(CPtr(Any Ptr, local11), local13))
                local1 = c2fb_temp_28
                If (-Cast(SQLITE_C_INT, ((local1 >= Cast(SQLITE_C_INT, &O0ULL))))) Then
                    If (-Cast(SQLITE_C_INT, ((local2 > Cast(SQLITE_C_INT, &O0ULL))))) Then
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local6->fg.flags) Shr 11) And Cast(SQLITE_C_UINT, &H1ULL))) = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((sqlite3IdListIndex(CPtr(Any Ptr, CPtr(SqliteIdList Ptr, local6->u3.pUsing)), local13) < Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                            sqlite3ExprListDelete(CPtr(Any Ptr, local5), CPtr(Any Ptr, local12))
                            c2fb_temp_29 = CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                            local12 = c2fb_temp_29
                        Else
                            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local6->fg.jointype) And Cast(SQLITE_C_INT, &H10ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                                Goto c2fb_flow_5
                            Else
                                If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local6->fg.jointype) And Cast(SQLITE_C_INT, &H08ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                                    c2fb_temp_30 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                                    local2 = c2fb_temp_30
                                    sqlite3ExprListDelete(CPtr(Any Ptr, local5), CPtr(Any Ptr, local12))
                                    c2fb_temp_31 = CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                                    local12 = c2fb_temp_31
                                Else
                                    extendFJMatch(arg0, CPtr(SqliteExprList Ptr Ptr, @(local12)), local7, arg5->iColumn)
                                End If
                            End If
                        End If
                    End If
                    c2fb_temp_32 = local2
                    local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_32 + 1)))
                    c2fb_temp_33 = local6
                    local7 = c2fb_temp_33
                    c2fb_temp_34 = @(arg5->iColumn)
                    c2fb_temp_35 = Cast(Short, IIf((-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, local11->iPKey))))), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, Cast(Short, local1))))
                    (*c2fb_temp_34) = c2fb_temp_35
                    If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local6->fg.flags) Shr 14) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                        sqlite3SrcItemColumnUsed(CPtr(Any Ptr, local6), local1)
                    End If
                End If
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = local2)))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local11)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000200ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
#ifdef SQLITE_ALLOW_ROWID_IN_VIEW
                    If local3 = 0 OrElse (local3 = 1 AndAlso local7 <> 0 AndAlso _
                       local7->pSTab <> 0 AndAlso _
                       (local7->pSTab->tabFlags And TF_Ephemeral) <> 0 AndAlso _
                       (local11->tabFlags And TF_Ephemeral) = 0) Then
                        local3 = 1
                        local7 = local6
                    Else
                        local3 += 1
                    End If
#else
                    c2fb_temp_36 = local3
                    local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_36 + 1)))
                    c2fb_temp_37 = local6
                    local7 = c2fb_temp_37
#endif
                End If
            c2fb_flow_5:
                c2fb_temp_10 = local0
                local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_10 + 1)))
                c2fb_temp_11 = local6
                local6 = (c2fb_temp_11 + 1)
            Wend
            c2fb_flow_4:
            If local7 Then
                c2fb_temp_38 = @(arg5->iTable)
                c2fb_temp_39 = Cast(SQLITE_C_INT, local7->iCursor)
                (*c2fb_temp_38) = c2fb_temp_39
                ' C unused-parameter annotation
                c2fb_temp_40 = @(arg5->y.pTab)
                c2fb_temp_41 = CPtr(SqliteTable Ptr, local7->pSTab)
                (*c2fb_temp_40) = CPtr(Any Ptr, CPtr(SqliteTable Ptr, local7->pSTab))
                c2fb_temp_41 = CPtr(SqliteTable Ptr, (*c2fb_temp_40))
                If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local7->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H40ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_42 = @((arg5)->flags)
                    c2fb_temp_43 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_42)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H200000ULL))))))
                    (*c2fb_temp_42) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_42)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H200000ULL)))))))
                    c2fb_temp_43 = Cast(SQLITE_C_UINT, (*c2fb_temp_42))
                End If
                c2fb_temp_44 = CPtr(SqliteSchema Ptr, CPtr(SqliteTable Ptr, arg5->y.pTab)->pSchema)
                local9 = c2fb_temp_44
            End If
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            c2fb_temp_45 = CPtr(SqliteTable Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            local11 = c2fb_temp_45
            If (-Cast(SQLITE_C_INT, ((arg0->pTriggerTab <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                local19 = arg0->eTriggerOp
                ' C unused-parameter annotation
                If Cast(SQLITE_C_INT, arg0->bReturning) Then
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (arg4->ncFlags And Cast(SQLITE_C_INT, &H000400ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg2 = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((sqlite3StrICmp(arg2, CPtr(Const ZString Ptr, arg0->pTriggerTab->zName)) = Cast(SQLITE_C_INT, &O0ULL))))))))) OrElse isValidSchemaTableName(arg2, arg0->pTriggerTab, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
                        c2fb_temp_46 = @(arg5->iTable)
                        c2fb_temp_47 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, ((local19 <> Cast(SQLITE_C_INT, 129ULL))))))
                        (*c2fb_temp_46) = c2fb_temp_47
                        c2fb_temp_48 = arg0->pTriggerTab
                        local11 = c2fb_temp_48
                    End If
                Else
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local19 <> Cast(SQLITE_C_INT, 129ULL))))) AndAlso arg2)))) AndAlso (-Cast(SQLITE_C_INT, ((sqlite3StrICmp(StrPtr(!"new"), arg2) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                        c2fb_temp_49 = @(arg5->iTable)
                        c2fb_temp_50 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                        (*c2fb_temp_49) = c2fb_temp_50
                        c2fb_temp_51 = arg0->pTriggerTab
                        local11 = c2fb_temp_51
                    Else
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local19 <> Cast(SQLITE_C_INT, 128ULL))))) AndAlso arg2)))) AndAlso (-Cast(SQLITE_C_INT, ((sqlite3StrICmp(StrPtr(!"old"), arg2) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                            c2fb_temp_52 = @(arg5->iTable)
                            c2fb_temp_53 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                            (*c2fb_temp_52) = c2fb_temp_53
                            c2fb_temp_54 = arg0->pTriggerTab
                            local11 = c2fb_temp_54
                        End If
                    End If
                End If
            End If
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (arg4->ncFlags And Cast(SQLITE_C_INT, &H000200ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((arg2 <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                local20 = arg4->uNC.pUpsert
                If (-Cast(SQLITE_C_INT, ((local20 AndAlso (-Cast(SQLITE_C_INT, ((sqlite3StrICmp(StrPtr(!"excluded"), arg2) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                    c2fb_temp_55 = CPtr(SqliteTable Ptr, CPtr(SqliteSrcList Ptr, local20->pUpsertSrc)->a(Cast(SQLITE_C_INT, &O0ULL)).pSTab)
                    local11 = c2fb_temp_55
                    c2fb_temp_56 = @(arg5->iTable)
                    c2fb_temp_57 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 2ULL))
                    (*c2fb_temp_56) = c2fb_temp_57
                End If
            End If
            If local11 Then
                ' C automatic storage declaration
                c2fb_temp_58 = CPtr(SqliteSchema Ptr, local11->pSchema)
                local9 = c2fb_temp_58
                c2fb_temp_59 = local3
                local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_59 + 1)))
                c2fb_temp_60 = Cast(SQLITE_C_INT, sqlite3ColumnIndex(CPtr(Any Ptr, local11), local13))
                local21 = c2fb_temp_60
                If (-Cast(SQLITE_C_INT, ((local21 >= Cast(SQLITE_C_INT, &O0ULL))))) Then
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local11->iPKey) = local21)))) Then
                        c2fb_temp_61 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
                        local21 = c2fb_temp_61
                    End If
                Else
                    If (-Cast(SQLITE_C_INT, ((sqlite3IsRowid(local13) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local11)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000200ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
                        c2fb_temp_62 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
                        local21 = c2fb_temp_62
                    Else
                        c2fb_temp_63 = Cast(SQLITE_C_INT, local11->nCol)
                        local21 = c2fb_temp_63
                    End If
                End If
                If (-Cast(SQLITE_C_INT, ((local21 < Cast(SQLITE_C_INT, local11->nCol))))) Then
                    c2fb_temp_64 = local2
                    local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_64 + 1)))
                    c2fb_temp_65 = CPtr(SqliteSrcItem Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                    local7 = c2fb_temp_65
                    If (-Cast(SQLITE_C_INT, ((arg5->iTable = Cast(SQLITE_C_INT, 2ULL))))) Then
                        ' empty C statement
                        ' C unused-parameter annotation
                        If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->eParseMode) >= Cast(SQLITE_C_INT, 2ULL)))))) Then
                            c2fb_temp_66 = @(arg5->iColumn)
                            c2fb_temp_67 = Cast(Short, local21)
                            (*c2fb_temp_66) = c2fb_temp_67
                            c2fb_temp_68 = @(arg5->y.pTab)
                            c2fb_temp_69 = local11
                            (*c2fb_temp_68) = CPtr(Any Ptr, local11)
                            c2fb_temp_69 = CPtr(SqliteTable Ptr, (*c2fb_temp_68))
                            c2fb_temp_70 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 168ULL))
                            local10 = c2fb_temp_70
                        Else
                            c2fb_temp_71 = @(arg5->iTable)
                            c2fb_temp_72 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg4->uNC.pUpsert->regData + Cast(SQLITE_C_INT, sqlite3TableColumnToStorage(CPtr(Any Ptr, local11), local21)))))
                            (*c2fb_temp_71) = c2fb_temp_72
                            c2fb_temp_73 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 176ULL))
                            local10 = c2fb_temp_73
                        End If
                    Else
                        ' C unused-parameter annotation
                        c2fb_temp_74 = @(arg5->y.pTab)
                        c2fb_temp_75 = local11
                        (*c2fb_temp_74) = CPtr(Any Ptr, local11)
                        c2fb_temp_75 = CPtr(SqliteTable Ptr, (*c2fb_temp_74))
                        If Cast(SQLITE_C_INT, arg0->bReturning) Then
                            c2fb_temp_76 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 176ULL))
                            local10 = c2fb_temp_76
                            c2fb_temp_77 = @(arg5->op2)
                            c2fb_temp_78 = Cast(UByte, Cast(SQLITE_C_INT, 168ULL))
                            (*c2fb_temp_77) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 168ULL)))
                            c2fb_temp_78 = Cast(UByte, (*c2fb_temp_77))
                            c2fb_temp_79 = @(arg5->iColumn)
                            c2fb_temp_80 = Cast(Short, local21)
                            (*c2fb_temp_79) = c2fb_temp_80
                            c2fb_temp_81 = @(arg5->iTable)
                            c2fb_temp_82 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (arg4->uNC.iBaseReg + Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local11->nCol) + Cast(SQLITE_C_INT, 1ULL)))) * arg5->iTable)))) + Cast(SQLITE_C_INT, sqlite3TableColumnToStorage(CPtr(Any Ptr, local11), local21)))) + Cast(SQLITE_C_INT, 1ULL))))
                            (*c2fb_temp_81) = c2fb_temp_82
                        Else
                            c2fb_temp_83 = @(arg5->iColumn)
                            c2fb_temp_84 = Cast(Short, Cast(Short, local21))
                            (*c2fb_temp_83) = c2fb_temp_84
                            c2fb_temp_85 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 78ULL))
                            local10 = c2fb_temp_85
                            If (-Cast(SQLITE_C_INT, ((local21 < Cast(SQLITE_C_INT, &O0ULL))))) Then
                                c2fb_temp_86 = @(arg5->affExpr)
                                c2fb_temp_87 = Cast(Byte, Cast(SQLITE_C_INT, &H44ULL))
                                (*c2fb_temp_86) = c2fb_temp_87
                            Else
                                If (-Cast(SQLITE_C_INT, ((arg5->iTable = Cast(SQLITE_C_INT, &O0ULL))))) Then
                                    ' empty C statement
                                    ' empty C statement
                                    c2fb_temp_88 = @(arg0->oldmask)
                                    c2fb_temp_89 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_88)) Or (IIf((-Cast(SQLITE_C_INT, ((local21 >= Cast(SQLITE_C_INT, 32ULL))))), Cast(SQLITE_C_UINT, &HffffffffULL), (Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))) Shl local21))))))))
                                    (*c2fb_temp_88) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_88)) Or (IIf((-Cast(SQLITE_C_INT, ((local21 >= Cast(SQLITE_C_INT, 32ULL))))), Cast(SQLITE_C_UINT, &HffffffffULL), (Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))) Shl local21)))))))))
                                    c2fb_temp_89 = Cast(SQLITE_C_UINT, (*c2fb_temp_88))
                                Else
                                    ' empty C statement
                                    ' empty C statement
                                    c2fb_temp_90 = @(arg0->newmask)
                                    c2fb_temp_91 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_90)) Or (IIf((-Cast(SQLITE_C_INT, ((local21 >= Cast(SQLITE_C_INT, 32ULL))))), Cast(SQLITE_C_UINT, &HffffffffULL), (Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))) Shl local21))))))))
                                    (*c2fb_temp_90) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_90)) Or (IIf((-Cast(SQLITE_C_INT, ((local21 >= Cast(SQLITE_C_INT, 32ULL))))), Cast(SQLITE_C_UINT, &HffffffffULL), (Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))) Shl local21)))))))))
                                    c2fb_temp_91 = Cast(SQLITE_C_UINT, (*c2fb_temp_90))
                                End If
                            End If
                        End If
                    End If
                End If
            End If
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local3 >= Cast(SQLITE_C_INT, 1ULL))))))))) AndAlso local7)))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (arg4->ncFlags And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000020ULL) Or Cast(SQLITE_C_INT, &H000008ULL))))))) = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso sqlite3IsRowid(local13))))) AndAlso ((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((CPtr(SqliteTable Ptr, local7->pSTab))->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000200ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) OrElse Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local7->fg.flags) Shr 14) And Cast(SQLITE_C_UINT, &H1ULL)))))))))))) Then
            c2fb_temp_92 = Cast(SQLITE_C_INT, local3)
            local2 = c2fb_temp_92
#if defined(SQLITE_ALLOW_ROWID_IN_VIEW)
#if SQLITE_ALLOW_ROWID_IN_VIEW = 2
            If local7->pSTab <> 0 AndAlso _
               local7->pSTab->eTabType = TABTYP_VIEW Then
                local10 = TK_NULL
            End If
#endif
#endif
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local7->fg.flags) Shr 14) And Cast(SQLITE_C_UINT, &H1ULL))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_93 = @(arg5->iColumn)
                c2fb_temp_94 = Cast(Short, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
                (*c2fb_temp_93) = c2fb_temp_94
            End If
            c2fb_temp_95 = @(arg5->affExpr)
            c2fb_temp_96 = Cast(Byte, Cast(SQLITE_C_INT, &H44ULL))
            (*c2fb_temp_95) = c2fb_temp_96
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (arg4->ncFlags And Cast(SQLITE_C_INT, &H000080ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((arg2 = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            c2fb_temp_97 = arg4->uNC.pEList
            local14 = c2fb_temp_97
            ' C unused-parameter annotation
            c2fb_temp_98 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local1 = c2fb_temp_98
            While (-Cast(SQLITE_C_INT, ((local1 < local14->nExpr))))
                local22 = CPtr(ZString Ptr, local14->a(local1).zEName)
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local14->a(local1).fg.flags) Shr 0) And Cast(SQLITE_C_UINT, &H3ULL))) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((sqlite3_stricmp(CPtr(Const ZString Ptr, local22), local13) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                    ' C automatic storage declaration
                    ' C unused-parameter annotation
                    ' C unused-parameter annotation
                    ' C unused-parameter annotation
                    c2fb_temp_100 = CPtr(SqliteExpr Ptr, local14->a(local1).pExpr)
                    local23 = c2fb_temp_100
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (arg4->ncFlags And Cast(SQLITE_C_INT, &H000001ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local23)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000010ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
                        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"misuse of aliased aggregate %s"), local22)
                        Return Cast(SQLITE_C_INT, 2ULL)
                    End If
                    If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local23)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H008000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (arg4->ncFlags And Cast(SQLITE_C_INT, &H004000ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((arg4 <> local8))))))))))))) Then
                        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"misuse of aliased window function %s"), local22)
                        Return Cast(SQLITE_C_INT, 2ULL)
                    End If
                    If (-Cast(SQLITE_C_INT, ((sqlite3ExprVectorSize(CPtr(Any Ptr, local23)) <> Cast(SQLITE_C_INT, 1ULL))))) Then
                        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"row value misused"))
                        Return Cast(SQLITE_C_INT, 2ULL)
                    End If
                    resolveAlias(arg0, local14, local1, arg5, local4)
                    c2fb_temp_101 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                    local2 = c2fb_temp_101
                    c2fb_temp_102 = CPtr(SqliteSrcItem Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                    local7 = c2fb_temp_102
                    ' C unused-parameter annotation
                    If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->eParseMode) >= Cast(SQLITE_C_INT, 2ULL)))))) Then
                        sqlite3RenameTokenRemap(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, arg5))
                    End If
                    Goto c2fb_label_0
                End If
            c2fb_flow_9:
                c2fb_temp_99 = local1
                local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_99 + 1)))
            Wend
            c2fb_flow_8:
        End If
        If local2 Then
            Goto c2fb_flow_2
        End If
        c2fb_temp_103 = arg4->pNext
        arg4 = c2fb_temp_103
        c2fb_temp_104 = local4
        local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_104 + 1)))
    c2fb_flow_3:
    Loop While arg4
    c2fb_flow_2:
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((arg2 = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg5)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000080ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) AndAlso areDoubleQuotedStringsEnabled(local5, local8))))) Then
            sqlite3_log(Cast(SQLITE_C_INT, 28ULL), StrPtr(!"double-quoted string literal: \034%w\034"), local13)
            c2fb_temp_105 = @(arg5->op)
            c2fb_temp_106 = Cast(UByte, Cast(SQLITE_C_INT, 118ULL))
            (*c2fb_temp_105) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 118ULL)))
            c2fb_temp_106 = Cast(UByte, (*c2fb_temp_105))
            c2fb_temp_107 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteExprYValue Ptr, @(arg5->y))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteExprYValue))))
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
        If sqlite3ExprIdToTrueFalse(CPtr(Any Ptr, arg5)) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
    End If
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((local2 <> Cast(SQLITE_C_INT, 1ULL))))) Then
        ' C automatic storage declaration
        If local12 Then
            If (-Cast(SQLITE_C_INT, ((local12->nExpr = Cast(SQLITE_C_INT, (local2 - Cast(SQLITE_C_INT, 1ULL))))))) Then
                If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg5)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H800000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                    c2fb_temp_108 = @((arg5)->flags)
                    c2fb_temp_109 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_108)) And Cast(SQLITE_C_UINT, (Not Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H800000ULL))))))))
                    (*c2fb_temp_108) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_108)) And Cast(SQLITE_C_UINT, (Not Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H800000ULL)))))))))
                    c2fb_temp_109 = Cast(SQLITE_C_UINT, (*c2fb_temp_108))
                Else
                    sqlite3ExprDelete(CPtr(Any Ptr, local5), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg5->pLeft)))
                    c2fb_temp_110 = @(arg5->pLeft)
                    c2fb_temp_111 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                    (*c2fb_temp_110) = CPtr(Any Ptr, CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
                    c2fb_temp_111 = CPtr(SqliteExpr Ptr, (*c2fb_temp_110))
                    sqlite3ExprDelete(CPtr(Any Ptr, local5), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg5->pRight)))
                    c2fb_temp_112 = @(arg5->pRight)
                    c2fb_temp_113 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                    (*c2fb_temp_112) = CPtr(Any Ptr, CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
                    c2fb_temp_113 = CPtr(SqliteExpr Ptr, (*c2fb_temp_112))
                End If
                extendFJMatch(arg0, CPtr(SqliteExprList Ptr Ptr, @(local12)), local7, arg5->iColumn)
                c2fb_temp_114 = @(arg5->op)
                c2fb_temp_115 = Cast(UByte, Cast(SQLITE_C_INT, 172ULL))
                (*c2fb_temp_114) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 172ULL)))
                c2fb_temp_115 = Cast(UByte, (*c2fb_temp_114))
                c2fb_temp_116 = @(arg5->u.zToken)
                c2fb_temp_117 = CPtr(ZString Ptr, StrPtr(!"coalesce"))
                (*c2fb_temp_116) = CPtr(UByte Ptr, CPtr(ZString Ptr, StrPtr(!"coalesce")))
                c2fb_temp_117 = CPtr(ZString Ptr, (*c2fb_temp_116))
                c2fb_temp_118 = @(arg5->x.pList)
                c2fb_temp_119 = local12
                (*c2fb_temp_118) = CPtr(Any Ptr, local12)
                c2fb_temp_119 = CPtr(SqliteExprList Ptr, (*c2fb_temp_118))
                c2fb_temp_120 = @(arg5->affExpr)
                c2fb_temp_121 = Cast(Byte, Cast(SQLITE_C_INT, &H58ULL))
                (*c2fb_temp_120) = c2fb_temp_121
                c2fb_temp_122 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                local2 = c2fb_temp_122
                Goto c2fb_label_0
            Else
                sqlite3ExprListDelete(CPtr(Any Ptr, local5), CPtr(Any Ptr, local12))
                c2fb_temp_123 = CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                local12 = c2fb_temp_123
            End If
        End If
        c2fb_temp_124 = IIf((-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, &O0ULL))))), StrPtr(!"no such column"), StrPtr(!"ambiguous column name"))
        local24 = c2fb_temp_124
        If arg1 Then
            sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"%s: %s.%s.%s"), local24, arg1, arg2, local13)
        Else
            If arg2 Then
                sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"%s: %s.%s"), local24, arg2, local13)
            Else
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg3)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000080ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
                    sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"%s: \034%s\034 - should this be a string literal in single-quotes?"), local24, local13)
                Else
                    sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"%s: %s"), local24, local13)
                End If
            End If
        End If
        sqlite3RecordErrorOffsetOfExpr(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, arg5))
        c2fb_temp_125 = @(arg0->checkSchema)
        c2fb_temp_126 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))) And Cast(SQLITE_C_UINT, &H1ULL)))
        (*c2fb_temp_125) = Cast(u8, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))) And Cast(SQLITE_C_UINT, &H1ULL)))
        c2fb_temp_126 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))) And Cast(SQLITE_C_UINT, &H1ULL)))
        c2fb_temp_127 = @(local8->nNcErr)
        c2fb_temp_128 = (*c2fb_temp_127)
        (*c2fb_temp_127) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_128 + 1)))
        c2fb_temp_129 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 122ULL))
        local10 = c2fb_temp_129
    End If
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg5)->flags And Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H010000ULL) Or Cast(SQLITE_C_INT, &H800000ULL))))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))) Then
        sqlite3ExprDelete(CPtr(Any Ptr, local5), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg5->pLeft)))
        c2fb_temp_130 = @(arg5->pLeft)
        c2fb_temp_131 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_130) = CPtr(Any Ptr, CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
        c2fb_temp_131 = CPtr(SqliteExpr Ptr, (*c2fb_temp_130))
        sqlite3ExprDelete(CPtr(Any Ptr, local5), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg5->pRight)))
        c2fb_temp_132 = @(arg5->pRight)
        c2fb_temp_133 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_132) = CPtr(Any Ptr, CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
        c2fb_temp_133 = CPtr(SqliteExpr Ptr, (*c2fb_temp_132))
        c2fb_temp_134 = @((arg5)->flags)
        c2fb_temp_135 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_134)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H800000ULL))))))
        (*c2fb_temp_134) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_134)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H800000ULL)))))))
        c2fb_temp_135 = Cast(SQLITE_C_UINT, (*c2fb_temp_134))
    End If
    If local7 Then
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg5->iColumn) >= Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_136 = @(local7->colUsed)
            c2fb_temp_137 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, ((*c2fb_temp_136) Or sqlite3ExprColUsed(CPtr(Any Ptr, arg5)))))
            (*c2fb_temp_136) = c2fb_temp_137
        Else
            c2fb_temp_138 = @(local7->fg.flags)
            c2fb_temp_139 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))) And Cast(SQLITE_C_UINT, &H1ULL)))
            (*c2fb_temp_138) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_138)) And Not(Cast(SQLITE_C_UINT, &H8000ULL))) Or ((Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 15)))
            c2fb_temp_139 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))) And Cast(SQLITE_C_UINT, &H1ULL)))
        End If
    End If
    c2fb_temp_140 = @(arg5->op)
    c2fb_temp_141 = Cast(UByte, local10)
    (*c2fb_temp_140) = Cast(u8, Cast(UByte, local10))
    c2fb_temp_141 = Cast(UByte, (*c2fb_temp_140))
    c2fb_label_0:
    If (-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, 1ULL))))) Then
        ' C unused-parameter annotation
        If CPtr(Function CDecl(ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const ZString Ptr, ByVal arg4 As Const ZString Ptr, ByVal arg5 As Const ZString Ptr) As SQLITE_C_INT, local5->xAuth) Then
            If local12 Then
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                c2fb_temp_142 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local0 = c2fb_temp_142
                While (-Cast(SQLITE_C_INT, ((local0 < local12->nExpr))))
                    ' C unused-parameter annotation
                    sqlite3AuthRead(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local12->a(local0).pExpr)), CPtr(Any Ptr, local9), CPtr(Any Ptr, arg4->pSrcList))
                c2fb_flow_11:
                    c2fb_temp_143 = local0
                    local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_143 + 1)))
                Wend
                c2fb_flow_10:
            Else
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg5->op) = Cast(SQLITE_C_INT, 168ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg5->op) = Cast(SQLITE_C_INT, 78ULL))))))))) Then
                    sqlite3AuthRead(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg5), CPtr(Any Ptr, local9), CPtr(Any Ptr, arg4->pSrcList))
                End If
            End If
        End If
        While True
            ' C unused-parameter annotation
            c2fb_temp_144 = @(local8->nRef)
            c2fb_temp_145 = (*c2fb_temp_144)
            (*c2fb_temp_144) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_145 + 1)))
            If (-Cast(SQLITE_C_INT, ((local8 = arg4)))) Then
                Goto c2fb_flow_12
            End If
            c2fb_temp_146 = local8->pNext
            local8 = c2fb_temp_146
        c2fb_flow_13:
        Wend
        c2fb_flow_12:
        Return Cast(SQLITE_C_INT, 1ULL)
    Else
        Return Cast(SQLITE_C_INT, 2ULL)
    End If
End Function

/' end of sqlite3_bulk_resolve_core.bas '/
