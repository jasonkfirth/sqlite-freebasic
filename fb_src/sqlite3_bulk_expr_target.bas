/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_bulk_expr_target.bas

    Purpose:

        Generate VDBE code for expression targets and IN lookups.

    Responsibilities:

        - Emit bytecode for expression targets, vectors, and comparisons.
        - Find or build suitable indexes for IN expressions.
        - Keep the constant-expression callback closure beside its callers.

    This file intentionally does NOT contain:

        - SQL expression parsing or name resolution.
        - VDBE execution or general statement finalization.
        - A claim that candidate compilation establishes runtime behavior.
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
#include once "sqlite3_vdbe_compare.bi"
#include once "sqlite3_walker.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_agginfo_types.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_numeric.bi"
#include once "sqlite3_fp.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_result.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_util_numeric.bi"
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
Declare Sub sqlite3SubselectError CDecl Alias "sqlite3SubselectError" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT)

Type c2fb_callback_1 As Sub CDecl()
Type c2fb_callback_2 As Function CDecl(ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Type c2fb_callback_8 As Sub CDecl(ByVal arg0 As Any Ptr)
Type c2fb_callback_10 As Sub CDecl(ByVal arg0 As SqliteResultContext Ptr)
Type c2fb_callback_28 As Sub CDecl(ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Type c2fb_callback_86 As Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT

Private Function __c2fb_double_value(ByVal value As Double) As Double
    Return value
End Function
Declare Function binaryCompareP5 CDecl Alias "binaryCompareP5" (ByVal arg0 As Const SqliteExpr Ptr, ByVal arg1 As Const SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT) As UByte
Declare Function codeCompare CDecl Alias "codeCompare" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SqliteExpr Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As SQLITE_C_INT, ByVal arg7 As SQLITE_C_INT, ByVal arg8 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function exprCodeSubselect CDecl Alias "exprCodeSubselect" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function exprVectorRegister CDecl Alias "exprVectorRegister" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SqliteExpr Ptr, ByVal arg5 As SqliteExpr Ptr Ptr, ByVal arg6 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Sub codeVectorCompare CDecl Alias "codeVectorCompare" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As UByte, ByVal arg4 As UByte)
Declare Function exprEvalRhsFirst CDecl Alias "exprEvalRhsFirst" (ByVal arg0 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function exprComputeOperands CDecl Alias "exprComputeOperands" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT Ptr, ByVal arg3 As SQLITE_C_INT Ptr, ByVal arg4 As SQLITE_C_INT Ptr, ByVal arg5 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function exprIsConst CDecl Alias "exprIsConst" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3ExprIsConstantNotJoin CDecl Alias "sqlite3ExprIsConstantNotJoin" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function isCandidateForInOpt CDecl Alias "isCandidateForInOpt" (ByVal arg0 As Const SqliteExpr Ptr) As SqliteSelect Ptr
Declare Sub sqlite3SetHasNullFlag CDecl Alias "sqlite3SetHasNullFlag" (ByVal arg0 As SqliteVdbe Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Declare Function sqlite3InRhsIsConstant CDecl Alias "sqlite3InRhsIsConstant" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function sqlite3FindInIndex CDecl Alias "sqlite3FindInIndex" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_UINT, ByVal arg3 As SQLITE_C_INT Ptr, ByVal arg4 As SQLITE_C_INT Ptr, ByVal arg5 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function exprINAffinity CDecl Alias "exprINAffinity" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As Const SqliteExpr Ptr) As ZString Ptr
Declare Sub sqlite3ExprCodeIN CDecl Alias "sqlite3ExprCodeIN" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Declare Sub codeReal CDecl Alias "codeReal" (ByVal arg0 As SqliteVdbe Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Declare Sub codeInteger CDecl Alias "codeInteger" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Declare Function exprCodeVector CDecl Alias "exprCodeVector" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Sub setDoNotMergeFlagOnCopy CDecl Alias "setDoNotMergeFlagOnCopy" (ByVal arg0 As SqliteVdbe Ptr)
Declare Function exprCodeInlineFunction CDecl Alias "exprCodeInlineFunction" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExprList Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function sqlite3IndexedExprLookup CDecl Alias "sqlite3IndexedExprLookup" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function exprPartidxExprLookup CDecl Alias "exprPartidxExprLookup" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function exprCodeTargetAndOr CDecl Alias "exprCodeTargetAndOr" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function sqlite3ExprCodeTarget CDecl Alias "sqlite3ExprCodeTarget" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub exprCodeBetween CDecl Alias "exprCodeBetween" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As c2fb_callback_28, ByVal arg4 As SQLITE_C_INT)
Declare Function c2fb_crt_memset CDecl Alias "memset" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_SIZE_T) As Any Ptr
' c2fb skipped __bswap_16: outside the supported subset
' c2fb skipped __bswap_32: outside the supported subset
' c2fb skipped __bswap_64: outside the supported subset
' c2fb skipped __uint16_identity: outside the supported subset
' c2fb skipped __uint32_identity: outside the supported subset
' c2fb skipped __uint64_identity: outside the supported subset
' c2fb skipped sqlite3IsBinary: FreeBASIC body already exists
' c2fb skipped sqlite3TableColumnAffinity: FreeBASIC body already exists
' c2fb skipped sqlite3ExprAffinity: FreeBASIC body already exists
' c2fb skipped sqlite3ExprDataType: FreeBASIC body already exists
' c2fb skipped sqlite3ExprAddCollateToken: FreeBASIC body already exists
' c2fb skipped sqlite3ExprAddCollateString: FreeBASIC body already exists
' c2fb skipped sqlite3ExprSkipCollate: FreeBASIC body already exists
' c2fb skipped sqlite3ExprSkipCollateAndLikely: FreeBASIC body already exists
' c2fb skipped sqlite3ExprCollSeq: FreeBASIC body already exists
' c2fb skipped sqlite3ExprNNCollSeq: FreeBASIC body already exists
' c2fb skipped sqlite3ExprCollSeqMatch: FreeBASIC body already exists
' c2fb skipped sqlite3CompareAffinity: FreeBASIC body already exists
' c2fb skipped comparisonAffinity: outside the supported subset
' c2fb skipped sqlite3IndexAffinityOk: FreeBASIC body already exists

/' ------------------------------------------------------------------------- '/
/' Translated expression bytecode and IN-index procedures '/
/' ------------------------------------------------------------------------- '/
Private Function exprNodeIsConstantFunction( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SQLITE_C_INT
    If pWalker = 0 OrElse pExpr = 0 OrElse pWalker->pParse = 0 Then
        If pWalker <> 0 Then pWalker->eCode = 0
        Return WRC_ABORT
    End If

    Dim argumentCount As SQLITE_C_INT = 0
    If (pExpr->flags And EP_TokenOnly) = 0 AndAlso pExpr->x.pList <> 0 Then
        Dim pList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pExpr->x.pList)
        If pList->nExpr < 0 OrElse pList->nAlloc < pList->nExpr Then
            pWalker->eCode = 0
            Return WRC_ABORT
        End If
        argumentCount = pList->nExpr
        If sqlite3WalkExprList(pWalker, pList) <> WRC_CONTINUE OrElse _
           pWalker->eCode = 0 Then Return WRC_ABORT
    End If

    If pExpr->u.zToken = 0 Then
        pWalker->eCode = 0
        Return WRC_ABORT
    End If
    Dim pFunction As SqliteFuncDef Ptr = sqlite3FindFunction( _
        pWalker->pParse->db, CPtr(Const ZString Ptr, pExpr->u.zToken), _
        argumentCount, pWalker->pParse->db->enc, 0)
    If pFunction = 0 OrElse pFunction->xFinalize <> 0 OrElse _
       (pFunction->funcFlags And _
        (SQLITE_FUNC_CONSTANT Or SQLITE_FUNC_SLOCHNG)) = 0 OrElse _
       (pExpr->flags And EP_WinFunc) <> 0 Then
        pWalker->eCode = 0
    End If

    ' This helper has already checked the arguments. Prune the normal walker
    ' descent either way; eCode records whether the function was constant.
    Return WRC_ABORT
End Function


Private Function exprNodeIsConstant CDecl Alias "exprNodeIsConstant" ( _
    ByVal pWalkerArgument As Any Ptr, _
    ByVal pExprArgument As Any Ptr _
) As SQLITE_C_INT
    If pWalkerArgument = 0 OrElse pExprArgument = 0 Then Return WRC_ABORT
    Dim pWalker As SqliteWalker Ptr = CPtr(SqliteWalker Ptr, pWalkerArgument)
    Dim pExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pExprArgument)

    If pWalker->eCode <= 0 Then Return WRC_ABORT
    If pWalker->eCode = 2 AndAlso (pExpr->flags And EP_OuterON) <> 0 Then
        pWalker->eCode = 0
        Return WRC_ABORT
    End If

    Select Case pExpr->op
    Case TK_FUNCTION
        If (pExpr->flags And EP_WinFunc) <> 0 Then
            pWalker->eCode = 0
            Return WRC_ABORT
        ElseIf pWalker->eCode >= 4 AndAlso pWalker->eCode <= 5 Then
            If pWalker->eCode = 5 Then pExpr->flags Or= EP_FromDDL
            Return WRC_CONTINUE
        ElseIf (pExpr->flags And EP_ConstFunc) <> 0 Then
            Return WRC_CONTINUE
        ElseIf pWalker->pParse <> 0 Then
            Return exprNodeIsConstantFunction(pWalker, pExpr)
        Else
            pWalker->eCode = 0
            Return WRC_ABORT
        End If

    Case TK_ID
        If sqlite3ExprIdToTrueFalse(pExpr) <> 0 Then Return WRC_PRUNE
        ' TK_ID falls through to the column-like cases.
        If (pExpr->flags And EP_FixedCol) <> 0 AndAlso pWalker->eCode <> 2 Then _
            Return WRC_CONTINUE
        If pWalker->eCode = 3 AndAlso pExpr->iTable = pWalker->u.n Then _
            Return WRC_CONTINUE
        pWalker->eCode = 0
        Return WRC_ABORT

    Case TK_COLUMN, TK_AGG_FUNCTION, TK_AGG_COLUMN
        If (pExpr->flags And EP_FixedCol) <> 0 AndAlso pWalker->eCode <> 2 Then _
            Return WRC_CONTINUE
        If pWalker->eCode = 3 AndAlso pExpr->iTable = pWalker->u.n Then _
            Return WRC_CONTINUE
        pWalker->eCode = 0
        Return WRC_ABORT

    Case TK_IF_NULL_ROW, TK_REGISTER, TK_DOT, TK_RAISE
        pWalker->eCode = 0
        Return WRC_ABORT

    Case TK_IS, TK_ISNOT
        If pWalker->eCode = 6 Then
            pWalker->eCode = 0
            Return WRC_ABORT
        End If
        Return WRC_CONTINUE

    Case TK_VARIABLE
        If pWalker->eCode = 5 Then
            ' Legacy schema text may contain a parameter; read it as NULL.
            pExpr->op = TK_NULL
        ElseIf pWalker->eCode = 4 Then
            pWalker->eCode = 0
            Return WRC_ABORT
        End If
        Return WRC_CONTINUE
    End Select
    Return WRC_CONTINUE
End Function


Private Function binaryCompareP5 CDecl Alias "binaryCompareP5" (ByVal arg0 As Const SqliteExpr Ptr, ByVal arg1 As Const SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT) As UByte
    Dim local0 As UByte
    Dim c2fb_temp_0 As UByte

    local0 = Cast(Byte, sqlite3ExprAffinity(CPtr(Any Ptr, arg1)))
    c2fb_temp_0 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, sqlite3CompareAffinity(CPtr(Any Ptr, arg0), local0))) Or Cast(SQLITE_C_INT, Cast(UByte, arg2)))))
    local0 = c2fb_temp_0
    Return local0
End Function

' c2fb skipped sqlite3BinaryCompareCollSeq: FreeBASIC body already exists
' c2fb skipped sqlite3ExprCompareCollSeq: FreeBASIC body already exists
Private Function codeCompare CDecl Alias "codeCompare" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SqliteExpr Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As SQLITE_C_INT, ByVal arg7 As SQLITE_C_INT, ByVal arg8 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim local2 As sqlite3CollSeq Ptr
    Dim c2fb_temp_0 As sqlite3CollSeq Ptr
    Dim c2fb_temp_1 As sqlite3CollSeq Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    If arg0->nErr Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If arg8 Then
        c2fb_temp_0 = CPtr(sqlite3CollSeq Ptr, sqlite3BinaryCompareCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg2), CPtr(Any Ptr, arg1)))
        local2 = c2fb_temp_0
    Else
        c2fb_temp_1 = CPtr(sqlite3CollSeq Ptr, sqlite3BinaryCompareCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), CPtr(Any Ptr, arg2)))
        local2 = c2fb_temp_1
    End If
    c2fb_temp_2 = Cast(SQLITE_C_INT, binaryCompareP5(CPtr(Const SqliteExpr Ptr, arg1), CPtr(Const SqliteExpr Ptr, arg2), arg7))
    local0 = c2fb_temp_2
    c2fb_temp_3 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp4(CPtr(SqliteVdbe Ptr, arg0->pVdbe), arg3, arg5, arg6, arg4, CPtr(Const ZString Ptr, CPtr(Any Ptr, local2)), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 2ULL))))))
    local1 = c2fb_temp_3
    sqlite3VdbeChangeP5(CPtr(SqliteVdbe Ptr, arg0->pVdbe), Cast(UShort, local0))
    Return local1
End Function

' c2fb skipped sqlite3ExprIsVector: FreeBASIC body already exists
' c2fb skipped sqlite3ExprVectorSize: FreeBASIC body already exists
' c2fb skipped sqlite3VectorFieldSubexpr: FreeBASIC body already exists
' c2fb skipped sqlite3ExprForVectorField: FreeBASIC body already exists
Private Function exprCodeSubselect CDecl Alias "exprCodeSubselect" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 139ULL))))) Then
        c2fb_temp_0 = Cast(SQLITE_C_INT, sqlite3CodeSubselect(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1)))
        local0 = c2fb_temp_0
    End If
    Return local0
End Function

Private Function exprVectorRegister CDecl Alias "exprVectorRegister" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SqliteExpr Ptr, ByVal arg5 As SqliteExpr Ptr Ptr, ByVal arg6 As SQLITE_C_INT Ptr) As SQLITE_C_INT
    Dim local0 As UByte
    Dim c2fb_temp_0 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_1 As SqliteExpr Ptr
    Dim c2fb_temp_2 As Any Ptr
    Dim c2fb_temp_3 As u8 Ptr
    Dim c2fb_temp_4 As UByte
    Dim c2fb_temp_5 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_6 As SqliteExpr Ptr
    Dim c2fb_temp_7 As Short Ptr
    Dim c2fb_temp_8 As Short
    Dim c2fb_temp_9 As SQLITE_C_INT Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_12 As SqliteExpr Ptr
    Dim c2fb_temp_13 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_14 As SqliteExpr Ptr

    local0 = arg1->op
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0) = Cast(SQLITE_C_INT, 176ULL))))) Then
        c2fb_temp_0 = CPtr(SqliteExpr Ptr Ptr, @((*arg5)))
        c2fb_temp_1 = CPtr(SqliteExpr Ptr, sqlite3VectorFieldSubexpr(CPtr(Any Ptr, arg1), arg2))
        (*c2fb_temp_0) = c2fb_temp_1
        Return Cast(SQLITE_C_INT, (arg1->iTable + arg2))
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0) = Cast(SQLITE_C_INT, 139ULL))))) Then
        ' C unused-parameter annotation
        c2fb_temp_2 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, arg4), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteExpr))))
        c2fb_temp_3 = CPtr(u8 Ptr, @(arg4->op))
        c2fb_temp_4 = Cast(UByte, Cast(SQLITE_C_INT, 178ULL))
        (*c2fb_temp_3) = Cast(u8, c2fb_temp_4)
        c2fb_temp_4 = Cast(UByte, (*c2fb_temp_3))
        c2fb_temp_5 = CPtr(SqliteExpr Ptr Ptr, @(arg4->pLeft))
        c2fb_temp_6 = arg1
        (*c2fb_temp_5) = c2fb_temp_6
        c2fb_temp_7 = CPtr(Short Ptr, @(arg4->iColumn))
        c2fb_temp_8 = Cast(Short, arg2)
        (*c2fb_temp_7) = c2fb_temp_8
        c2fb_temp_9 = CPtr(SQLITE_C_INT Ptr, @(arg4->iTable))
        c2fb_temp_10 = Cast(SQLITE_C_INT, arg1->x.pSelect->pEList->nExpr)
        (*c2fb_temp_9) = c2fb_temp_10
        c2fb_temp_11 = CPtr(SqliteExpr Ptr Ptr, @((*arg5)))
        c2fb_temp_12 = arg4
        (*c2fb_temp_11) = c2fb_temp_12
        Return Cast(SQLITE_C_INT, (arg3 + arg2))
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0) = Cast(SQLITE_C_INT, 177ULL))))) Then
        ' C unused-parameter annotation
        c2fb_temp_13 = CPtr(SqliteExpr Ptr Ptr, @((*arg5)))
        c2fb_temp_14 = arg1->x.pList->a(arg2).pExpr
        (*c2fb_temp_13) = c2fb_temp_14
        Return sqlite3ExprCodeTemp(CPtr(Any Ptr, arg0), CPtr(Any Ptr, (*arg5)), arg6)
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Sub codeVectorCompare CDecl Alias "codeVectorCompare" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As UByte, ByVal arg4 As UByte)
    Dim local0 As SqliteVdbe Ptr
    Dim local1 As SqliteExpr Ptr
    Dim local2 As SqliteExpr Ptr
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim local6 As SQLITE_C_INT
    Dim local7 As UByte
    Dim local8 As SQLITE_C_INT
    Dim local9 As SQLITE_C_INT
    Dim local10 As SQLITE_C_INT
    Dim c2fb_temp_0 As UByte
    Dim c2fb_temp_1 As UByte
    Dim c2fb_temp_2 As UByte
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim local11 As SQLITE_C_INT
    Dim local12 As SQLITE_C_INT
    Dim local13 As SqliteExpr Ptr
    Dim local14 As SqliteExpr Ptr
    Dim local15 As SqliteExpr
    Dim local16 As SqliteExpr
    Dim local17 As SQLITE_C_INT
    Dim local18 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As UByte

    local0 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    local1 = arg1->pLeft
    local2 = arg1->pRight
    local3 = sqlite3ExprVectorSize(CPtr(Any Ptr, local1))
    ' C automatic storage declaration
    local5 = Cast(SQLITE_C_INT, &O0ULL)
    local6 = Cast(SQLITE_C_INT, &O0ULL)
    local7 = arg3
    local8 = Cast(SQLITE_C_INT, &O0ULL)
    local9 = sqlite3VdbeMakeLabel(arg0)
    local10 = ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000400ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))
    ' C unused-parameter annotation
    If arg0->nErr Then
        Return
    End If
    If (-Cast(SQLITE_C_INT, ((local3 <> sqlite3ExprVectorSize(CPtr(Any Ptr, local2)))))) Then
        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"row value misused"))
        Return
    End If
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg3) = Cast(SQLITE_C_INT, 56ULL))))) Then
        c2fb_temp_0 = Cast(UByte, Cast(SQLITE_C_INT, 57ULL))
        local7 = c2fb_temp_0
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg3) = Cast(SQLITE_C_INT, 58ULL))))) Then
        c2fb_temp_1 = Cast(UByte, Cast(SQLITE_C_INT, 55ULL))
        local7 = c2fb_temp_1
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg3) = Cast(SQLITE_C_INT, 53ULL))))) Then
        c2fb_temp_2 = Cast(UByte, Cast(SQLITE_C_INT, 54ULL))
        local7 = c2fb_temp_2
    End If
    c2fb_temp_3 = Cast(SQLITE_C_INT, exprCodeSubselect(arg0, local1))
    local5 = c2fb_temp_3
    c2fb_temp_4 = Cast(SQLITE_C_INT, exprCodeSubselect(arg0, local2))
    local6 = c2fb_temp_4
    sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, 1ULL), arg2)
    c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local4 = c2fb_temp_5
    While Cast(SQLITE_C_INT, 1ULL)
        local11 = Cast(SQLITE_C_INT, &O0ULL)
        local12 = Cast(SQLITE_C_INT, &O0ULL)
        local13 = Cast(SQLITE_C_INT, &O0ULL)
        local14 = Cast(SQLITE_C_INT, &O0ULL)
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C unused-parameter annotation
        If local8 Then
            sqlite3VdbeJumpHere(local0, local8)
        End If
        c2fb_temp_7 = Cast(SQLITE_C_INT, exprVectorRegister(arg0, local1, local4, local5, CPtr(SqliteExpr Ptr, @(local15)), CPtr(SqliteExpr Ptr Ptr, @(local13)), CPtr(SQLITE_C_INT Ptr, @(local11))))
        local17 = c2fb_temp_7
        c2fb_temp_8 = Cast(SQLITE_C_INT, exprVectorRegister(arg0, local2, local4, local6, CPtr(SqliteExpr Ptr, @(local16)), CPtr(SqliteExpr Ptr Ptr, @(local14)), CPtr(SQLITE_C_INT Ptr, @(local12))))
        local18 = c2fb_temp_8
        c2fb_temp_9 = Cast(SQLITE_C_INT, sqlite3VdbeCurrentAddr(local0))
        local8 = c2fb_temp_9
        codeCompare(arg0, local13, local14, local7, local17, local18, local9, arg4, local10)
        ' empty C statement
        ' empty C statement
        ' empty C statement
        ' empty C statement
        ' empty C statement
        ' empty C statement
        ' empty C statement
        ' empty C statement
        ' empty C statement
        ' empty C statement
        ' empty C statement
        ' empty C statement
        sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local11)
        sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local12)
        If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local7) = Cast(SQLITE_C_INT, 57ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local7) = Cast(SQLITE_C_INT, 55ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, ((local4 < Cast(SQLITE_C_INT, (local3 - Cast(SQLITE_C_INT, 1ULL))))))))))) Then
            c2fb_temp_10 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp0(local0, Cast(SQLITE_C_INT, 59ULL)))
            local8 = c2fb_temp_10
            ' empty C statement
            ' empty C statement
            ' empty C statement
            ' empty C statement
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg4) = Cast(SQLITE_C_INT, &H80ULL))))) Then
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, &O0ULL), arg2)
        Else
            sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 94ULL), local17, arg2, local18)
        End If
        If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, (local3 - Cast(SQLITE_C_INT, 1ULL))))))) Then
            Goto c2fb_flow_0
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local7) = Cast(SQLITE_C_INT, 54ULL))))) Then
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 52ULL), arg2, local9)
            ' empty C statement
        Else
            ' C unused-parameter annotation
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 9ULL), Cast(SQLITE_C_INT, &O0ULL), local9)
            If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, (local3 - Cast(SQLITE_C_INT, 2ULL))))))) Then
                c2fb_temp_11 = Cast(UByte, arg3)
                local7 = c2fb_temp_11
            End If
        End If
    c2fb_flow_1:
        c2fb_temp_6 = local4
        local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 + 1)))
    Wend
    c2fb_flow_0:
    sqlite3VdbeJumpHere(local0, local8)
    sqlite3VdbeResolveLabel(local0, local9)
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg3) = Cast(SQLITE_C_INT, 53ULL))))) Then
        sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 19ULL), arg2, arg2)
    End If
End Sub

' c2fb skipped sqlite3ExprCheckHeight: FreeBASIC body already exists
' c2fb skipped heightOfExpr: outside the supported subset
' c2fb skipped heightOfExprList: outside the supported subset
' c2fb skipped heightOfSelect: outside the supported subset
' c2fb skipped exprSetHeight: outside the supported subset
' c2fb skipped sqlite3ExprSetHeightAndFlags: FreeBASIC body already exists
' c2fb skipped sqlite3SelectExprHeight: FreeBASIC body already exists
' c2fb skipped sqlite3ExprSetErrorOffset: FreeBASIC body already exists
' c2fb skipped sqlite3ExprAlloc: FreeBASIC body already exists
' c2fb skipped sqlite3Expr: FreeBASIC body already exists
' c2fb skipped sqlite3ExprInt32: FreeBASIC body already exists
' c2fb skipped sqlite3ExprAttachSubtrees: FreeBASIC body already exists
' c2fb skipped sqlite3PExpr: FreeBASIC body already exists
' c2fb skipped sqlite3PExprAddSelect: FreeBASIC body already exists
' c2fb skipped sqlite3ExprListToValues: FreeBASIC body already exists
' c2fb skipped sqlite3ExprAnd: FreeBASIC body already exists
' c2fb skipped sqlite3ExprFunction: FreeBASIC body already exists
' c2fb skipped sqlite3ExprOrderByAggregateError: FreeBASIC body already exists
' c2fb skipped sqlite3ExprAddFunctionOrderBy: FreeBASIC body already exists
' c2fb skipped sqlite3ExprFunctionUsable: FreeBASIC body already exists
' c2fb skipped sqlite3ExprAssignVarNumber: FreeBASIC body already exists
' c2fb skipped sqlite3ExprDeleteNN: outside the supported subset
' c2fb skipped sqlite3ExprDelete: FreeBASIC body already exists
' c2fb skipped sqlite3ExprDeleteGeneric: FreeBASIC body already exists
' c2fb skipped sqlite3ClearOnOrUsing: FreeBASIC body already exists
' c2fb skipped sqlite3ExprDeferredDelete: FreeBASIC body already exists
' c2fb skipped sqlite3ExprUnmapAndDelete: FreeBASIC body already exists
' c2fb skipped exprStructSize: outside the supported subset
' c2fb skipped dupedExprStructSize: outside the supported subset
' c2fb skipped dupedExprNodeSize: outside the supported subset
' c2fb skipped dupedExprSize: outside the supported subset
' c2fb skipped exprDup: outside the supported subset
' c2fb skipped sqlite3WithDup: FreeBASIC body already exists
' c2fb skipped gatherSelectWindowsCallback: outside the supported subset
' c2fb skipped gatherSelectWindowsSelectCallback: outside the supported subset
' c2fb skipped gatherSelectWindows: outside the supported subset
' c2fb skipped sqlite3ExprDup: FreeBASIC body already exists
' c2fb skipped sqlite3ExprListDup: FreeBASIC body already exists
' c2fb skipped sqlite3SrcListDup: FreeBASIC body already exists
' c2fb skipped sqlite3IdListDup: FreeBASIC body already exists
' c2fb skipped sqlite3SelectDup: FreeBASIC body already exists
' c2fb skipped sqlite3ExprListAppendNew: outside the supported subset
' c2fb skipped sqlite3ExprListAppendGrow: outside the supported subset
' c2fb skipped sqlite3ExprListAppend: FreeBASIC body already exists
' c2fb skipped sqlite3ExprListAppendVector: FreeBASIC body already exists
' c2fb skipped sqlite3ExprListSetSortOrder: FreeBASIC body already exists
' c2fb skipped sqlite3ExprListSetName: FreeBASIC body already exists
' c2fb skipped sqlite3ExprListSetSpan: FreeBASIC body already exists
' c2fb skipped sqlite3ExprListCheckLength: FreeBASIC body already exists
' c2fb skipped exprListDeleteNN: outside the supported subset
' c2fb skipped sqlite3ExprListDelete: FreeBASIC body already exists
' c2fb skipped sqlite3ExprListDeleteGeneric: FreeBASIC body already exists
' c2fb skipped sqlite3ExprListFlags: FreeBASIC body already exists
' c2fb skipped sqlite3SelectWalkFail: FreeBASIC body already exists
' c2fb skipped sqlite3IsTrueOrFalse: FreeBASIC body already exists
' c2fb skipped sqlite3ExprIdToTrueFalse: FreeBASIC body already exists
' c2fb skipped sqlite3ExprTruthValue: FreeBASIC body already exists
' c2fb skipped sqlite3ExprSimplifiedAndOr: FreeBASIC body already exists
Private Function exprEvalRhsFirst CDecl Alias "exprEvalRhsFirst" (ByVal arg0 As SqliteExpr Ptr) As SQLITE_C_INT
    If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg0->pLeft)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H400000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) AndAlso (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg0->pRight)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H400000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))))))) Then
        Return Cast(SQLITE_C_INT, 1ULL)
    Else
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
End Function

Private Function exprComputeOperands CDecl Alias "exprComputeOperands" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT Ptr, ByVal arg3 As SQLITE_C_INT Ptr, ByVal arg4 As SQLITE_C_INT Ptr, ByVal arg5 As SQLITE_C_INT Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As SqliteVdbe Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT Ptr
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local3 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((exprEvalRhsFirst(arg1) AndAlso sqlite3ExprCanBeNull(CPtr(Any Ptr, arg1->pRight)))))) Then
        c2fb_temp_0 = Cast(SQLITE_C_INT, sqlite3ExprCodeTemp(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pRight), arg5))
        local2 = c2fb_temp_0
        c2fb_temp_1 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(local3, Cast(SQLITE_C_INT, 51ULL), local2))
        local0 = c2fb_temp_1
        ' empty C statement
        ' empty C statement
    Else
        c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local2 = c2fb_temp_2
        c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local0 = c2fb_temp_3
    End If
    c2fb_temp_4 = Cast(SQLITE_C_INT, sqlite3ExprCodeTemp(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pLeft), arg4))
    local1 = c2fb_temp_4
    If (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1->pRight)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H400000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) AndAlso sqlite3ExprCanBeNull(CPtr(Any Ptr, arg1->pLeft)))))) Then
            c2fb_temp_5 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(local3, Cast(SQLITE_C_INT, 51ULL), local1))
            local0 = c2fb_temp_5
            ' empty C statement
            ' empty C statement
        End If
        c2fb_temp_6 = Cast(SQLITE_C_INT, sqlite3ExprCodeTemp(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pRight), arg5))
        local2 = c2fb_temp_6
    End If
    c2fb_temp_7 = CPtr(SQLITE_C_INT Ptr, @((*arg2)))
    c2fb_temp_8 = Cast(SQLITE_C_INT, local1)
    (*c2fb_temp_7) = c2fb_temp_8
    c2fb_temp_9 = CPtr(SQLITE_C_INT Ptr, @((*arg3)))
    c2fb_temp_10 = Cast(SQLITE_C_INT, local2)
    (*c2fb_temp_9) = c2fb_temp_10
    Return local0
End Function

' c2fb skipped exprNodeIsConstantFunction: outside the supported subset
' c2fb skipped exprNodeIsConstant: outside the supported subset
Private Function exprIsConst CDecl Alias "exprIsConst" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SqliteWalker
    Dim c2fb_temp_0 As UShort Ptr
    Dim c2fb_temp_1 As UShort
    Dim c2fb_temp_2 As SqliteParseContext Ptr Ptr
    Dim c2fb_temp_3 As SqliteParseContext Ptr
    Dim c2fb_temp_4 As SqliteWalkerExprCallback Ptr
    Dim c2fb_temp_5 As c2fb_callback_86
    Dim c2fb_temp_6 As SqliteWalkerSelectCallback Ptr
    Dim c2fb_temp_7 As c2fb_callback_86

    ' C automatic storage declaration
    c2fb_temp_0 = CPtr(UShort Ptr, @(local0.eCode))
    c2fb_temp_1 = Cast(UShort, arg2)
    (*c2fb_temp_0) = c2fb_temp_1
    c2fb_temp_2 = CPtr(SqliteParseContext Ptr Ptr, @(local0.pParse))
    c2fb_temp_3 = arg0
    (*c2fb_temp_2) = c2fb_temp_3
    c2fb_temp_4 = CPtr(SqliteWalkerExprCallback Ptr, @(local0.xExprCallback))
    c2fb_temp_5 = CPtr(c2fb_callback_86, ProcPtr(exprNodeIsConstant))
    (*c2fb_temp_4) = Cast(SqliteWalkerExprCallback, c2fb_temp_5)
    c2fb_temp_5 = CPtr(c2fb_callback_86, (*c2fb_temp_4))
    c2fb_temp_6 = CPtr(SqliteWalkerSelectCallback Ptr, @(local0.xSelectCallback))
    c2fb_temp_7 = CPtr(c2fb_callback_86, ProcPtr(sqlite3SelectWalkFail))
    (*c2fb_temp_6) = Cast(SqliteWalkerSelectCallback, c2fb_temp_7)
    c2fb_temp_7 = CPtr(c2fb_callback_86, (*c2fb_temp_6))
    sqlite3WalkExpr(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local0))), CPtr(Any Ptr, arg1))
    Return local0.eCode
End Function

' c2fb skipped sqlite3ExprIsConstant: FreeBASIC body already exists
' c2fb skipped sqlite3ExprListIsConstant: FreeBASIC body already exists
Private Function sqlite3ExprIsConstantNotJoin CDecl Alias "sqlite3ExprIsConstantNotJoin" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
    Return exprIsConst(arg0, arg1, Cast(SQLITE_C_INT, 2ULL))
End Function

' c2fb skipped exprSelectWalkTableConstant: outside the supported subset
' c2fb skipped sqlite3ExprIsTableConstant: outside the supported subset
' c2fb skipped sqlite3ExprIsSingleTableConstraint: FreeBASIC body already exists
' c2fb skipped exprNodeIsConstantOrGroupBy: outside the supported subset
' c2fb skipped sqlite3ExprIsConstantOrGroupBy: FreeBASIC body already exists
' c2fb skipped sqlite3ExprIsConstantOrFunction: FreeBASIC body already exists
' c2fb skipped sqlite3ExprIsInteger: FreeBASIC body already exists
' c2fb skipped sqlite3ExprCanBeNull: FreeBASIC body already exists
' c2fb skipped sqlite3ExprNeedsNoAffinityChange: FreeBASIC body already exists
' c2fb skipped sqlite3IsRowid: FreeBASIC body already exists
' c2fb skipped sqlite3RowidAlias: FreeBASIC body already exists
Private Function isCandidateForInOpt CDecl Alias "isCandidateForInOpt" (ByVal arg0 As Const SqliteExpr Ptr) As SqliteSelect Ptr
    Dim local0 As SqliteSelect Ptr
    Dim local1 As SqliteSrcList Ptr
    Dim local2 As SqliteExprList Ptr
    Dim local3 As SqliteTable Ptr
    Dim local4 As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteSelect Ptr
    Dim c2fb_temp_1 As SqliteSrcList Ptr
    Dim c2fb_temp_2 As SqliteTable Ptr
    Dim c2fb_temp_3 As SqliteExprList Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim local5 As SqliteExpr Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg0)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg0)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000040ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = arg0->x.pSelect
    local0 = c2fb_temp_0
    If local0->pPrior Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If Cast(SQLITE_C_UINT, (local0->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000008ULL)))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    ' C unused-parameter annotation
    If local0->pLimit Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If local0->pWhere Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_1 = local0->pSrc
    local1 = c2fb_temp_1
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((local1->nSrc <> Cast(SQLITE_C_INT, 1ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->a(Cast(SQLITE_C_INT, &O0ULL)).fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_2 = local1->a(Cast(SQLITE_C_INT, &O0ULL)).pSTab
    local3 = c2fb_temp_2
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local3)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_3 = local0->pEList
    local2 = c2fb_temp_3
    ' C unused-parameter annotation
    c2fb_temp_4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local4 = c2fb_temp_4
    While (-Cast(SQLITE_C_INT, ((local4 < local2->nExpr))))
        local5 = local2->a(local4).pExpr
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local5->op) <> Cast(SQLITE_C_INT, 168ULL))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        ' C unused-parameter annotation
    c2fb_flow_1:
        c2fb_temp_5 = local4
        local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_5 + 1)))
    Wend
    c2fb_flow_0:
    Return local0
End Function

Private Sub sqlite3SetHasNullFlag CDecl Alias "sqlite3SetHasNullFlag" (ByVal arg0 As SqliteVdbe Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    sqlite3VdbeAddOp2(arg0, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, &O0ULL), arg2)
    If (-Cast(SQLITE_C_INT, ((arg3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 36ULL))
        local1 = c2fb_temp_0
    Else
        c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 32ULL))
        local1 = c2fb_temp_1
    End If
    c2fb_temp_2 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(arg0, local1, arg1))
    local0 = c2fb_temp_2
    ' empty C statement
    sqlite3VdbeAddOp3(arg0, Cast(SQLITE_C_INT, 96ULL), arg1, Cast(SQLITE_C_INT, &O0ULL), arg2)
    sqlite3VdbeChangeP5(arg0, Cast(SQLITE_C_INT, &H80ULL))
    ' empty C statement
    sqlite3VdbeJumpHere(arg0, local0)
End Sub

Private Function sqlite3InRhsIsConstant CDecl Alias "sqlite3InRhsIsConstant" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim local0 As SqliteExpr Ptr
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteExpr Ptr
    Dim c2fb_temp_1 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_2 As SqliteExpr Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_5 As SqliteExpr Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    c2fb_temp_0 = arg1->pLeft
    local0 = c2fb_temp_0
    c2fb_temp_1 = CPtr(SqliteExpr Ptr Ptr, @(arg1->pLeft))
    c2fb_temp_2 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_1) = c2fb_temp_2
    c2fb_temp_3 = Cast(SQLITE_C_INT, sqlite3ExprIsConstant(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1)))
    local1 = c2fb_temp_3
    c2fb_temp_4 = CPtr(SqliteExpr Ptr Ptr, @(arg1->pLeft))
    c2fb_temp_5 = local0
    (*c2fb_temp_4) = c2fb_temp_5
    Return local1
End Function

Function sqlite3FindInIndex CDecl Alias "sqlite3FindInIndex" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_UINT, ByVal arg3 As SQLITE_C_INT Ptr, ByVal arg4 As SQLITE_C_INT Ptr, ByVal arg5 As SQLITE_C_INT Ptr) As SQLITE_C_INT
    Dim local0 As SqliteSelect Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim local4 As SqliteVdbe Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim local6 As SqliteExprList Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT Ptr
    Dim c2fb_temp_7 As SqliteSelect Ptr
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim local7 As sqlite3 Ptr
    Dim local8 As SqliteTable Ptr
    Dim local9 As SQLITE_C_INT
    Dim local10 As SqliteExprList Ptr
    Dim local11 As SQLITE_C_INT
    Dim c2fb_temp_9 As SqliteTable Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim local12 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim local13 As SqliteIndex Ptr
    Dim local14 As SQLITE_C_INT
    Dim local15 As SQLITE_C_INT
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim local16 As SqliteExpr Ptr
    Dim local17 As SQLITE_C_INT
    Dim local18 As Byte
    Dim local19 As Byte
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SqliteIndex Ptr
    Dim c2fb_temp_16 As SqliteIndex Ptr
    Dim local20 As sqlite3_uint64
    Dim local21 As sqlite3_uint64
    Dim c2fb_temp_17 As sqlite3_uint64
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim local22 As SqliteExpr Ptr
    Dim local23 As SqliteExpr Ptr
    Dim local24 As sqlite3CollSeq Ptr
    Dim local25 As SQLITE_C_INT
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As SQLITE_C_INT
    Dim c2fb_temp_22 As sqlite3_uint64
    Dim c2fb_temp_23 As sqlite3_uint64
    Dim c2fb_temp_24 As SQLITE_C_INT Ptr
    Dim c2fb_temp_25 As SQLITE_C_INT
    Dim local26 As SQLITE_C_INT
    Dim c2fb_temp_26 As SQLITE_C_INT
    Dim c2fb_temp_27 As SQLITE_C_INT Ptr
    Dim c2fb_temp_28 As SQLITE_C_INT
    Dim c2fb_temp_29 As SQLITE_C_INT
    Dim c2fb_temp_30 As SQLITE_C_INT Ptr
    Dim c2fb_temp_31 As SQLITE_C_INT
    Dim c2fb_temp_32 As SQLITE_C_INT Ptr
    Dim c2fb_temp_33 As SQLITE_C_INT
    Dim c2fb_temp_34 As SQLITE_C_INT
    Dim c2fb_temp_35 As SQLITE_C_INT
    Dim local27 As SQLITE_C_UINT
    Dim local28 As SQLITE_C_INT
    Dim local29 As SQLITE_C_INT
    Dim c2fb_temp_36 As SQLITE_C_INT
    Dim c2fb_temp_37 As Short Ptr
    Dim c2fb_temp_38 As Short
    Dim c2fb_temp_39 As SQLITE_C_INT Ptr
    Dim c2fb_temp_40 As SQLITE_C_INT
    Dim c2fb_temp_41 As SQLITE_C_INT
    Dim c2fb_temp_42 As SQLITE_C_INT
    Dim c2fb_temp_43 As SQLITE_C_INT Ptr
    Dim c2fb_temp_44 As SQLITE_C_INT
    Dim c2fb_temp_45 As SQLITE_C_INT
    Dim c2fb_temp_46 As Short Ptr
    Dim c2fb_temp_47 As Short
    Dim local30 As SQLITE_C_INT
    Dim local31 As SQLITE_C_INT
    Dim c2fb_temp_48 As SQLITE_C_INT
    Dim c2fb_temp_49 As SQLITE_C_INT
    Dim c2fb_temp_50 As SQLITE_C_INT
    Dim c2fb_temp_51 As SQLITE_C_INT Ptr
    Dim c2fb_temp_52 As SQLITE_C_INT
    Dim c2fb_temp_53 As SQLITE_C_INT Ptr
    Dim c2fb_temp_54 As SQLITE_C_INT

    ' C automatic storage declaration
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    local4 = CPtr(SqliteVdbe Ptr, sqlite3GetVdbe(CPtr(Any Ptr, arg0)))
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg2 And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0004ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))
    local3 = c2fb_temp_0
    c2fb_temp_1 = CPtr(SQLITE_C_INT Ptr, @(arg0->nTab))
    c2fb_temp_2 = (*c2fb_temp_1)
    (*c2fb_temp_1) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_2 + 1)))
    c2fb_temp_3 = Cast(SQLITE_C_INT, c2fb_temp_2)
    local2 = c2fb_temp_3
    If (-Cast(SQLITE_C_INT, ((arg3 AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
        ' C automatic storage declaration
        local6 = arg1->x.pSelect->pEList
        c2fb_temp_4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local5 = c2fb_temp_4
        While (-Cast(SQLITE_C_INT, ((local5 < local6->nExpr))))
            If sqlite3ExprCanBeNull(CPtr(Any Ptr, local6->a(local5).pExpr)) Then
                Goto c2fb_flow_0
            End If
        c2fb_flow_1:
            c2fb_temp_5 = local5
            local5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_5 + 1)))
        Wend
        c2fb_flow_0:
        If (-Cast(SQLITE_C_INT, ((local5 = local6->nExpr)))) Then
            c2fb_temp_6 = CPtr(SQLITE_C_INT Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            arg3 = c2fb_temp_6
        End If
    End If
    c2fb_temp_8 = 0
    If (-Cast(SQLITE_C_INT, ((arg0->nErr = Cast(SQLITE_C_INT, &O0ULL))))) Then
        c2fb_temp_7 = CPtr(SqliteSelect Ptr, isCandidateForInOpt(CPtr(Const SqliteExpr Ptr, arg1)))
        local0 = c2fb_temp_7
        c2fb_temp_8 = (-Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, (((c2fb_temp_7) <> Cast(SQLITE_C_INT, &O0ULL))))) <> 0)))
    End If
    If c2fb_temp_8 Then
        local7 = arg0->db
        ' C automatic storage declaration
        ' C automatic storage declaration
        local10 = local0->pEList
        local11 = local10->nExpr
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        c2fb_temp_9 = local0->pSrc->a(Cast(SQLITE_C_INT, &O0ULL)).pSTab
        local8 = c2fb_temp_9
        c2fb_temp_10 = Cast(SQLITE_C_INT, sqlite3SchemaToIndex(CPtr(Any Ptr, local7), CPtr(Any Ptr, CPtr(SqliteSchema Ptr, local8->pSchema))))
        local9 = c2fb_temp_10
        ' C unused-parameter annotation
        sqlite3CodeVerifySchema(CPtr(Any Ptr, arg0), local9)
        sqlite3TableLock(CPtr(Any Ptr, arg0), local9, local8->tnum, Cast(SQLITE_C_INT, &O0ULL), CPtr(Const ZString Ptr, local8->zName))
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local11 = Cast(SQLITE_C_INT, 1ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local10->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr->iColumn) < Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            local12 = sqlite3VdbeAddOp0(local4, Cast(SQLITE_C_INT, 15ULL))
            ' empty C statement
            sqlite3OpenTable(CPtr(Any Ptr, arg0), local2, local9, CPtr(Any Ptr, local8), Cast(SQLITE_C_INT, 114ULL))
            c2fb_temp_11 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
            local1 = c2fb_temp_11
            sqlite3VdbeExplainString(arg0, Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"USING ROWID SEARCH ON TABLE %s FOR IN-OPERATOR"), CPtr(Const ZString Ptr, local8->zName))
            sqlite3VdbeJumpHere(local4, local12)
        Else
            ' C automatic storage declaration
            local14 = Cast(SQLITE_C_INT, 1ULL)
            ' C automatic storage declaration
            c2fb_temp_12 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local15 = c2fb_temp_12
            While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local15 < local11)))) AndAlso local14))))
                local16 = CPtr(SqliteExpr Ptr, sqlite3VectorFieldSubexpr(CPtr(Any Ptr, arg1->pLeft), local15))
                local17 = local10->a(local15).pExpr->iColumn
                local18 = sqlite3TableColumnAffinity(CPtr(Any Ptr, local8), local17)
                local19 = sqlite3CompareAffinity(CPtr(Any Ptr, local16), local18)
                ' empty C statement
                ' empty C statement
                Select Case local19
                    Case Cast(SQLITE_C_INT, &H41ULL)
                    Case Cast(SQLITE_C_INT, &H42ULL)
                        ' C unused-parameter annotation
                    Case Else
                        c2fb_temp_14 = Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local18)) >= Cast(SQLITE_C_INT, &H43ULL)))))))
                        local14 = c2fb_temp_14
                End Select
                c2fb_flow_4:
            c2fb_flow_3:
                c2fb_temp_13 = local15
                local15 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_13 + 1)))
            Wend
            c2fb_flow_2:
            If local14 Then
                c2fb_temp_15 = CPtr(SqliteIndex Ptr, local8->pIndex)
                local13 = c2fb_temp_15
                While (-Cast(SQLITE_C_INT, ((local13 AndAlso (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, &O0ULL)))))))))
                    ' C automatic storage declaration
                    ' C automatic storage declaration
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local13->nColumn) < local11)))) Then
                        Goto c2fb_flow_6
                    End If
                    If (-Cast(SQLITE_C_INT, ((CPtr(SqliteExpr Ptr, local13->pPartIdxWhere) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                        Goto c2fb_flow_6
                    End If
                    ' empty C statement
                    ' empty C statement
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local13->nColumn) >= Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))) - Cast(SQLITE_C_INT, 1ULL))))))) Then
                        Goto c2fb_flow_6
                    End If
                    If local3 Then
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local13->nKeyCol) > local11)))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local13->nColumn) > local11)))) AndAlso (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local13)->onError) <> Cast(SQLITE_C_INT, &O0ULL)))))) = 0)))))))))))) Then
                            Goto c2fb_flow_6
                        End If
                    End If
                    c2fb_temp_17 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))
                    local20 = c2fb_temp_17
                    c2fb_temp_18 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    local15 = c2fb_temp_18
                    While (-Cast(SQLITE_C_INT, ((local15 < local11))))
                        local22 = CPtr(SqliteExpr Ptr, sqlite3VectorFieldSubexpr(CPtr(Any Ptr, arg1->pLeft), local15))
                        local23 = local10->a(local15).pExpr
                        local24 = CPtr(sqlite3CollSeq Ptr, sqlite3BinaryCompareCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local22), CPtr(Any Ptr, local23)))
                        ' C automatic storage declaration
                        c2fb_temp_20 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                        local25 = c2fb_temp_20
                        While (-Cast(SQLITE_C_INT, ((local25 < local11))))
                            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local13->aiColumn[local25]) <> Cast(SQLITE_C_INT, local23->iColumn))))) Then
                                Goto c2fb_flow_10
                            End If
                            ' C unused-parameter annotation
                            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local24 <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((sqlite3StrICmp(CPtr(Const ZString Ptr, local24->zName), CPtr(Const ZString Ptr Ptr, local13->azColl)[local25]) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                                Goto c2fb_flow_10
                            End If
                            Goto c2fb_flow_9
                        c2fb_flow_10:
                            c2fb_temp_21 = local25
                            local25 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_21 + 1)))
                        Wend
                        c2fb_flow_9:
                        If (-Cast(SQLITE_C_INT, ((local25 = local11)))) Then
                            Goto c2fb_flow_7
                        End If
                        c2fb_temp_22 = Cast(sqlite3_uint64, (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local25)))))
                        local21 = c2fb_temp_22
                        If Cast(sqlite3_uint64, (local21 And local20)) Then
                            Goto c2fb_flow_7
                        End If
                        c2fb_temp_23 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local20 Or local21)))
                        local20 = c2fb_temp_23
                        If arg4 Then
                            c2fb_temp_24 = CPtr(SQLITE_C_INT Ptr, @(arg4[local15]))
                            c2fb_temp_25 = Cast(SQLITE_C_INT, local25)
                            (*c2fb_temp_24) = c2fb_temp_25
                        End If
                    c2fb_flow_8:
                        c2fb_temp_19 = local15
                        local15 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_19 + 1)))
                    Wend
                    c2fb_flow_7:
                    ' C unused-parameter annotation
                    ' C unused-parameter annotation
                    If (-Cast(SQLITE_C_INT, ((local20 = (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local11)))) - Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))))))))) Then
                        local26 = sqlite3VdbeAddOp0(local4, Cast(SQLITE_C_INT, 15ULL))
                        ' empty C statement
                        sqlite3VdbeExplainString(arg0, Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"USING INDEX %s FOR IN-OPERATOR"), CPtr(Const ZString Ptr, local13->zName))
                        sqlite3VdbeAddOp3(local4, Cast(SQLITE_C_INT, 114ULL), local2, local13->tnum, local9)
                        sqlite3VdbeSetP4KeyInfo(arg0, local13)
                        ' empty C statement
                        ' C unused-parameter annotation
                        c2fb_temp_26 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 3ULL) + Cast(SQLITE_C_INT, CPtr(UByte Ptr, local13->aSortOrder)[Cast(SQLITE_C_INT, &O0ULL)]))))
                        local1 = c2fb_temp_26
                        If arg3 Then
                            c2fb_temp_30 = CPtr(SQLITE_C_INT Ptr, @((*arg3)))
                            c2fb_temp_27 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
                            c2fb_temp_28 = (*c2fb_temp_27)
                            (*c2fb_temp_27) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_28 + 1)))
                            c2fb_temp_29 = (*c2fb_temp_27)
                            c2fb_temp_31 = Cast(SQLITE_C_INT, c2fb_temp_29)
                            (*c2fb_temp_30) = c2fb_temp_31
                            If (-Cast(SQLITE_C_INT, ((local11 = Cast(SQLITE_C_INT, 1ULL))))) Then
                                sqlite3SetHasNullFlag(local4, local2, (*arg3), CPtr(UByte Ptr, local13->aSortOrder)[Cast(SQLITE_C_INT, &O0ULL)])
                            End If
                        End If
                        sqlite3VdbeJumpHere(local4, local26)
                    End If
                c2fb_flow_6:
                    c2fb_temp_16 = local13->pNext
                    local13 = c2fb_temp_16
                Wend
                c2fb_flow_5:
            End If
        End If
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (Cast(SQLITE_C_UINT, (arg2 And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0001ULL))))))))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (sqlite3InRhsIsConstant(arg0, arg1) = 0))) OrElse (-Cast(SQLITE_C_INT, ((arg1->x.pList->nExpr <= Cast(SQLITE_C_INT, 2ULL)))))))))))))) Then
        c2fb_temp_32 = CPtr(SQLITE_C_INT Ptr, @(arg0->nTab))
        c2fb_temp_33 = (*c2fb_temp_32)
        (*c2fb_temp_32) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_33 - 1)))
        c2fb_temp_34 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
        local2 = c2fb_temp_34
        c2fb_temp_35 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 5ULL))
        local1 = c2fb_temp_35
    End If
    If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        local27 = arg0->nQueryLoop
        local28 = Cast(SQLITE_C_INT, &O0ULL)
        local29 = (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg2 And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0002ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))
        c2fb_temp_36 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 2ULL))
        local1 = c2fb_temp_36
        If Cast(SQLITE_C_UINT, (arg2 And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0004ULL)))) Then
            c2fb_temp_37 = CPtr(Short Ptr, @(arg0->nQueryLoop))
            c2fb_temp_38 = Cast(Short, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_37) = c2fb_temp_38
        Else
            If arg3 Then
                c2fb_temp_43 = CPtr(SQLITE_C_INT Ptr, @((*arg3)))
                c2fb_temp_39 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
                c2fb_temp_40 = (*c2fb_temp_39)
                (*c2fb_temp_39) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_40 + 1)))
                c2fb_temp_41 = (*c2fb_temp_39)
                c2fb_temp_42 = Cast(SQLITE_C_INT, c2fb_temp_41)
                local28 = c2fb_temp_42
                c2fb_temp_44 = Cast(SQLITE_C_INT, c2fb_temp_42)
                (*c2fb_temp_43) = c2fb_temp_44
            End If
        End If
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (local29 = 0))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->x.pSelect->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000020ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
            c2fb_temp_45 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
            local29 = c2fb_temp_45
        End If
        sqlite3CodeRhsOfIN(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), local2, local29)
        If local28 Then
            sqlite3SetHasNullFlag(local4, local2, local28, Cast(SQLITE_C_INT, &O0ULL))
        End If
        c2fb_temp_46 = CPtr(Short Ptr, @(arg0->nQueryLoop))
        c2fb_temp_47 = Cast(Short, local27)
        (*c2fb_temp_46) = c2fb_temp_47
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg4 AndAlso (-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, 3ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, 4ULL))))))))) Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        c2fb_temp_48 = Cast(SQLITE_C_INT, sqlite3ExprVectorSize(CPtr(Any Ptr, arg1->pLeft)))
        local31 = c2fb_temp_48
        c2fb_temp_49 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local30 = c2fb_temp_49
        While (-Cast(SQLITE_C_INT, ((local30 < local31))))
            c2fb_temp_51 = CPtr(SQLITE_C_INT Ptr, @(arg4[local30]))
            c2fb_temp_52 = Cast(SQLITE_C_INT, local30)
            (*c2fb_temp_51) = c2fb_temp_52
        c2fb_flow_12:
            c2fb_temp_50 = local30
            local30 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_50 + 1)))
        Wend
        c2fb_flow_11:
    End If
    c2fb_temp_53 = CPtr(SQLITE_C_INT Ptr, @((*arg5)))
    c2fb_temp_54 = Cast(SQLITE_C_INT, local2)
    (*c2fb_temp_53) = c2fb_temp_54
    Return local1
End Function

Private Function exprINAffinity CDecl Alias "exprINAffinity" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As Const SqliteExpr Ptr) As ZString Ptr
    Dim local0 As SqliteExpr Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SqliteSelect Ptr
    Dim local3 As ZString Ptr
    Dim c2fb_temp_0 As ZString Ptr
    Dim local4 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim local5 As SqliteExpr Ptr
    Dim local6 As Byte
    Dim c2fb_temp_3 As Byte Ptr
    Dim c2fb_temp_4 As Byte
    Dim c2fb_temp_5 As Byte Ptr
    Dim c2fb_temp_6 As Byte
    Dim c2fb_temp_7 As Byte Ptr
    Dim c2fb_temp_8 As Byte

    local0 = arg1->pLeft
    local1 = sqlite3ExprVectorSize(CPtr(Any Ptr, local0))
    local2 = IIf(((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))), arg1->x.pSelect, CPtr(SqliteSelect Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
    ' C automatic storage declaration
    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(ZString Ptr, CPtr(Any Ptr, sqlite3DbMallocRaw(CPtr(Any Ptr, arg0->db), Cast(sqlite3_int64, (Cast(sqlite3_int64, Cast(SQLITE_C_INT, 1ULL)) + Cast(sqlite3_int64, local1))))))
    local3 = c2fb_temp_0
    If local3 Then
        ' C automatic storage declaration
        c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local4 = c2fb_temp_1
        While (-Cast(SQLITE_C_INT, ((local4 < local1))))
            local5 = CPtr(SqliteExpr Ptr, sqlite3VectorFieldSubexpr(CPtr(Any Ptr, local0), local4))
            local6 = sqlite3ExprAffinity(CPtr(Any Ptr, local5))
            If local2 Then
                c2fb_temp_3 = CPtr(Byte Ptr, @(CPtr(Byte Ptr, local3)[local4]))
                c2fb_temp_4 = Cast(Byte, sqlite3CompareAffinity(CPtr(Any Ptr, local2->pEList->a(local4).pExpr), local6))
                (*c2fb_temp_3) = c2fb_temp_4
            Else
                c2fb_temp_5 = CPtr(Byte Ptr, @(CPtr(Byte Ptr, local3)[local4]))
                c2fb_temp_6 = Cast(Byte, local6)
                (*c2fb_temp_5) = c2fb_temp_6
            End If
        c2fb_flow_1:
            c2fb_temp_2 = local4
            local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_2 + 1)))
        Wend
        c2fb_flow_0:
        c2fb_temp_7 = CPtr(Byte Ptr, @(CPtr(Byte Ptr, local3)[local1]))
        c2fb_temp_8 = Cast(Byte, Cast(SQLITE_C_INT, 0))
        (*c2fb_temp_7) = c2fb_temp_8
    End If
    Return local3
End Function

' c2fb skipped sqlite3SubselectError: FreeBASIC body already exists
' c2fb skipped sqlite3VectorErrorMsg: FreeBASIC body already exists
' c2fb skipped findCompatibleInRhsSubrtn: outside the supported subset
' c2fb skipped sqlite3CodeRhsOfIN: outside the supported subset
' c2fb skipped sqlite3CodeSubselect: outside the supported subset
' c2fb skipped sqlite3ExprCheckIN: FreeBASIC body already exists
Private Sub sqlite3ExprCodeIN CDecl Alias "sqlite3ExprCodeIN" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As SqliteVdbe Ptr
    Dim local4 As SQLITE_C_INT Ptr
    Dim local5 As ZString Ptr
    Dim local6 As SQLITE_C_INT
    Dim local7 As SQLITE_C_INT
    Dim local8 As SqliteExpr Ptr
    Dim local9 As SQLITE_C_INT
    Dim local10 As SQLITE_C_INT
    Dim local11 As SQLITE_C_INT
    Dim local12 As SQLITE_C_INT
    Dim local13 As SQLITE_C_INT
    Dim local14 As SQLITE_C_INT
    Dim local15 As SQLITE_C_INT
    Dim local16 As UByte
    Dim c2fb_temp_0 As SqliteExpr Ptr
    Dim c2fb_temp_1 As ZString Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT Ptr
    Dim c2fb_temp_4 As SqliteVdbe Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As u8 Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As u8 Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim local17 As SqliteExprList Ptr
    Dim local18 As sqlite3CollSeq Ptr
    Dim local19 As SQLITE_C_INT
    Dim local20 As SQLITE_C_INT
    Dim local21 As SQLITE_C_INT
    Dim local22 As SQLITE_C_INT
    Dim local23 As SQLITE_C_INT
    Dim c2fb_temp_11 As SqliteExprList Ptr
    Dim c2fb_temp_12 As sqlite3CollSeq Ptr
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim local24 As SQLITE_C_INT
    Dim local25 As SQLITE_C_INT
    Dim local26 As Byte
    Dim local27 As SQLITE_C_INT
    Dim c2fb_temp_17 As SQLITE_C_INT
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim local28 As SQLITE_C_INT
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As SQLITE_C_INT
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim c2fb_temp_23 As SQLITE_C_INT
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As SQLITE_C_INT
    Dim c2fb_temp_26 As SQLITE_C_INT
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim local29 As SqliteExpr Ptr
    Dim c2fb_temp_28 As SQLITE_C_INT
    Dim local30 As Const SqliteVdbeOp Ptr
    Dim c2fb_temp_29 As SQLITE_C_INT
    Dim c2fb_temp_30 As SQLITE_C_INT
    Dim c2fb_temp_31 As SQLITE_C_INT
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As SQLITE_C_INT
    Dim c2fb_temp_34 As SQLITE_C_INT
    Dim c2fb_temp_35 As SQLITE_C_INT
    Dim local31 As SqliteExpr Ptr
    Dim local32 As sqlite3CollSeq Ptr
    Dim local33 As SQLITE_C_INT
    Dim c2fb_temp_36 As SqliteExpr Ptr
    Dim local34 As SqliteExpr Ptr
    Dim c2fb_temp_37 As sqlite3CollSeq Ptr
    Dim c2fb_temp_38 As sqlite3CollSeq Ptr

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local4 = Cast(SQLITE_C_INT, &O0ULL)
    local5 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local11 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local15 = Cast(SQLITE_C_INT, &O0ULL)
    local16 = Cast(SQLITE_C_INT, arg0->okConstFactor)
    ' C unused-parameter annotation
    c2fb_temp_0 = arg1->pLeft
    local8 = c2fb_temp_0
    If sqlite3ExprCheckIN(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1)) Then
        Return
    End If
    c2fb_temp_1 = CPtr(ZString Ptr, exprINAffinity(arg0, CPtr(Const SqliteExpr Ptr, arg1)))
    local5 = c2fb_temp_1
    c2fb_temp_2 = Cast(SQLITE_C_INT, sqlite3ExprVectorSize(CPtr(Any Ptr, arg1->pLeft)))
    local6 = c2fb_temp_2
    c2fb_temp_3 = CPtr(SQLITE_C_INT Ptr, CPtr(Any Ptr, sqlite3DbMallocZero(CPtr(Any Ptr, arg0->db), Cast(sqlite3_uint64, (Cast(sqlite3_uint64, local6) * Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SQLITE_C_INT))))))))
    local4 = c2fb_temp_3
    If arg0->db->mallocFailed Then
        Goto c2fb_label_0
    End If
    c2fb_temp_4 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    local3 = c2fb_temp_4
    ' C unused-parameter annotation
    ' empty C statement
    c2fb_temp_5 = Cast(SQLITE_C_INT, sqlite3FindInIndex(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0001ULL))), IIf((-Cast(SQLITE_C_INT, ((arg2 = arg3)))), CPtr(SQLITE_C_INT Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))), CPtr(SQLITE_C_INT Ptr, @(local0))), local4, CPtr(SQLITE_C_INT Ptr, @(local15))))
    local1 = c2fb_temp_5
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_6 = CPtr(u8 Ptr, @(arg0->okConstFactor))
    c2fb_temp_7 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    c2fb_temp_7 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_7) And Cast(SQLITE_C_UINT, &H1ULL)))
    (*c2fb_temp_6) = Cast(u8, (Cast(SQLITE_C_UINT, c2fb_temp_7) And Cast(SQLITE_C_UINT, &H1ULL)))
    c2fb_temp_7 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_7) And Cast(SQLITE_C_UINT, &H1ULL)))
    c2fb_temp_8 = Cast(SQLITE_C_INT, exprCodeVector(arg0, local8, CPtr(SQLITE_C_INT Ptr, @(local7))))
    local2 = c2fb_temp_8
    c2fb_temp_9 = CPtr(u8 Ptr, @(arg0->okConstFactor))
    c2fb_temp_10 = Cast(SQLITE_C_INT, local16)
    c2fb_temp_10 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_10) And Cast(SQLITE_C_UINT, &H1ULL)))
    (*c2fb_temp_9) = Cast(u8, (Cast(SQLITE_C_UINT, c2fb_temp_10) And Cast(SQLITE_C_UINT, &H1ULL)))
    c2fb_temp_10 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_10) And Cast(SQLITE_C_UINT, &H1ULL)))
    If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 5ULL))))) Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        local19 = sqlite3VdbeMakeLabel(arg0)
        ' C automatic storage declaration
        ' C automatic storage declaration
        local22 = Cast(SQLITE_C_INT, &O0ULL)
        ' C automatic storage declaration
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        c2fb_temp_11 = arg1->x.pList
        local17 = c2fb_temp_11
        c2fb_temp_12 = CPtr(sqlite3CollSeq Ptr, sqlite3ExprCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pLeft)))
        local18 = c2fb_temp_12
        If (-Cast(SQLITE_C_INT, ((arg3 <> arg2)))) Then
            c2fb_temp_13 = Cast(SQLITE_C_INT, sqlite3GetTempReg(CPtr(Any Ptr, arg0)))
            local22 = c2fb_temp_13
            sqlite3VdbeAddOp3(local3, Cast(SQLITE_C_INT, 103ULL), local2, local2, local22)
        End If
        c2fb_temp_14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local23 = c2fb_temp_14
        While (-Cast(SQLITE_C_INT, ((local23 < local17->nExpr))))
            c2fb_temp_16 = Cast(SQLITE_C_INT, sqlite3ExprCodeTemp(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local17->a(local23).pExpr), CPtr(SQLITE_C_INT Ptr, @(local21))))
            local20 = c2fb_temp_16
            If (-Cast(SQLITE_C_INT, ((local22 AndAlso sqlite3ExprCanBeNull(CPtr(Any Ptr, local17->a(local23).pExpr)))))) Then
                sqlite3VdbeAddOp3(local3, Cast(SQLITE_C_INT, 103ULL), local22, local20, local22)
            End If
            sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local21)
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local23 < Cast(SQLITE_C_INT, (local17->nExpr - Cast(SQLITE_C_INT, 1ULL))))))) OrElse (-Cast(SQLITE_C_INT, ((arg3 <> arg2)))))))) Then
                local24 = IIf((-Cast(SQLITE_C_INT, ((local2 <> local20)))), Cast(SQLITE_C_INT, 54ULL), Cast(SQLITE_C_INT, 52ULL))
                sqlite3VdbeAddOp4(local3, local24, local2, local19, local20, CPtr(Const ZString Ptr, CPtr(Any Ptr, local18)), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 2ULL)))))
                ' empty C statement
                ' empty C statement
                ' empty C statement
                ' empty C statement
                sqlite3VdbeChangeP5(local3, CPtr(Byte Ptr, local5)[Cast(SQLITE_C_INT, &O0ULL)])
            Else
                local25 = IIf((-Cast(SQLITE_C_INT, ((local2 <> local20)))), Cast(SQLITE_C_INT, 53ULL), Cast(SQLITE_C_INT, 51ULL))
                ' C unused-parameter annotation
                sqlite3VdbeAddOp4(local3, local25, local2, arg2, local20, CPtr(Const ZString Ptr, CPtr(Any Ptr, local18)), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 2ULL)))))
                ' empty C statement
                ' empty C statement
                sqlite3VdbeChangeP5(local3, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, CPtr(Byte Ptr, local5)[Cast(SQLITE_C_INT, &O0ULL)]) Or Cast(SQLITE_C_INT, &H10ULL))))
            End If
        c2fb_flow_1:
            c2fb_temp_15 = local23
            local23 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_15 + 1)))
        Wend
        c2fb_flow_0:
        If local22 Then
            sqlite3VdbeAddOp2(local3, Cast(SQLITE_C_INT, 51ULL), local22, arg3)
            ' empty C statement
            sqlite3VdbeGoto(local3, arg2)
        End If
        sqlite3VdbeResolveLabel(local3, local19)
        sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local22)
        Goto c2fb_label_1
    End If
    If (-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, 1ULL))))) Then
        If (-Cast(SQLITE_C_INT, ((local6 = Cast(SQLITE_C_INT, 1ULL))))) Then
            local26 = CPtr(Byte Ptr, local5)[Cast(SQLITE_C_INT, &O0ULL)]
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local26) >= Cast(SQLITE_C_INT, &H42ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local26) <> Cast(SQLITE_C_INT, sqlite3ExprAffinity(CPtr(Any Ptr, local8))))))))))) Then
                local27 = sqlite3GetTempReg(CPtr(Any Ptr, arg0))
                sqlite3VdbeAddOp3(local3, Cast(SQLITE_C_INT, 82ULL), local2, local27, Cast(SQLITE_C_INT, &O0ULL))
                c2fb_temp_17 = Cast(SQLITE_C_INT, local27)
                local2 = c2fb_temp_17
                sqlite3VdbeAddOp4(local3, Cast(SQLITE_C_INT, 98ULL), local2, Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, &O0ULL), CPtr(Const ZString Ptr, local5), Cast(SQLITE_C_INT, 1ULL))
            End If
        Else
            sqlite3VdbeAddOp4(local3, Cast(SQLITE_C_INT, 98ULL), local2, local6, Cast(SQLITE_C_INT, &O0ULL), CPtr(Const ZString Ptr, local5), local6)
        End If
        c2fb_temp_18 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local9 = c2fb_temp_18
        While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local9 < local6)))) AndAlso (-Cast(SQLITE_C_INT, ((local4[local9] = local9))))))))
            ' empty C block
        c2fb_flow_3:
            c2fb_temp_19 = local9
            local9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_19 + 1)))
        Wend
        c2fb_flow_2:
        If (-Cast(SQLITE_C_INT, ((local9 <> local6)))) Then
            local28 = local2
            c2fb_temp_20 = Cast(SQLITE_C_INT, sqlite3GetTempRange(CPtr(Any Ptr, arg0), local6))
            local2 = c2fb_temp_20
            c2fb_temp_21 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local9 = c2fb_temp_21
            While (-Cast(SQLITE_C_INT, ((local9 < local6))))
                ' empty C statement
                sqlite3VdbeAddOp3(local3, Cast(SQLITE_C_INT, 82ULL), Cast(SQLITE_C_INT, (local28 + local9)), Cast(SQLITE_C_INT, (local2 + local4[local9])), Cast(SQLITE_C_INT, &O0ULL))
            c2fb_flow_5:
                c2fb_temp_22 = local9
                local9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_22 + 1)))
            Wend
            c2fb_flow_4:
            sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local28)
        End If
    End If
    If (-Cast(SQLITE_C_INT, ((arg3 = arg2)))) Then
        c2fb_temp_23 = Cast(SQLITE_C_INT, arg2)
        local10 = c2fb_temp_23
    Else
        c2fb_temp_24 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
        local11 = c2fb_temp_24
        c2fb_temp_25 = Cast(SQLITE_C_INT, c2fb_temp_24)
        local10 = c2fb_temp_25
    End If
    c2fb_temp_26 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local9 = c2fb_temp_26
    While (-Cast(SQLITE_C_INT, ((local9 < local6))))
        local29 = CPtr(SqliteExpr Ptr, sqlite3VectorFieldSubexpr(CPtr(Any Ptr, arg1->pLeft), local9))
        If arg0->nErr Then
            Goto c2fb_label_0
        End If
        If sqlite3ExprCanBeNull(CPtr(Any Ptr, local29)) Then
            ' empty C statement
            sqlite3VdbeAddOp2(local3, Cast(SQLITE_C_INT, 51ULL), Cast(SQLITE_C_INT, (local2 + local4[local9])), local10)
            ' empty C statement
        End If
    c2fb_flow_7:
        c2fb_temp_27 = local9
        local9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_27 + 1)))
    Wend
    c2fb_flow_6:
    If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 1ULL))))) Then
        ' C unused-parameter annotation
        sqlite3VdbeAddOp3(local3, Cast(SQLITE_C_INT, 30ULL), local15, arg2, local2)
        ' empty C statement
        c2fb_temp_28 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp0(local3, Cast(SQLITE_C_INT, 9ULL)))
        local12 = c2fb_temp_28
    Else
        If (-Cast(SQLITE_C_INT, ((arg2 = arg3)))) Then
            If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H2000000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                local30 = CPtr(SqliteVdbeOp Ptr, sqlite3VdbeGetOp(local3, arg1->y.sub.iAddr))
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, ((local30->p3 > Cast(SQLITE_C_INT, &O0ULL))))) Then
                    ' C unused-parameter annotation
                    sqlite3VdbeAddOp4Int(local3, Cast(SQLITE_C_INT, 66ULL), local30->p3, arg2, local2, local6)
                    ' empty C statement
                End If
            End If
            sqlite3VdbeAddOp4Int(local3, Cast(SQLITE_C_INT, 28ULL), local15, arg2, local2, local6)
            ' empty C statement
            Goto c2fb_label_1
        End If
        c2fb_temp_29 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp4Int(local3, Cast(SQLITE_C_INT, 29ULL), local15, Cast(SQLITE_C_INT, &O0ULL), local2, local6))
        local12 = c2fb_temp_29
        ' empty C statement
    End If
    If (-Cast(SQLITE_C_INT, ((local0 AndAlso (-Cast(SQLITE_C_INT, ((local6 = Cast(SQLITE_C_INT, 1ULL))))))))) Then
        sqlite3VdbeAddOp2(local3, Cast(SQLITE_C_INT, 52ULL), local0, arg2)
        ' empty C statement
    End If
    If (-Cast(SQLITE_C_INT, ((arg2 = arg3)))) Then
        sqlite3VdbeGoto(local3, arg2)
    End If
    If local11 Then
        sqlite3VdbeResolveLabel(local3, local11)
    End If
    If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 4ULL))))) Then
        c2fb_temp_30 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp2(local3, Cast(SQLITE_C_INT, 32ULL), local15, arg2))
        local14 = c2fb_temp_30
    Else
        ' empty C statement
        ' empty C statement
        c2fb_temp_31 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp2(local3, Cast(SQLITE_C_INT, 36ULL), local15, arg2))
        local14 = c2fb_temp_31
    End If
    ' empty C statement
    If (-Cast(SQLITE_C_INT, ((local6 > Cast(SQLITE_C_INT, 1ULL))))) Then
        c2fb_temp_32 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
        local13 = c2fb_temp_32
    Else
        c2fb_temp_33 = Cast(SQLITE_C_INT, arg2)
        local13 = c2fb_temp_33
    End If
    c2fb_temp_34 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local9 = c2fb_temp_34
    While (-Cast(SQLITE_C_INT, ((local9 < local6))))
        ' C automatic storage declaration
        ' C automatic storage declaration
        local33 = sqlite3GetTempReg(CPtr(Any Ptr, arg0))
        c2fb_temp_36 = CPtr(SqliteExpr Ptr, sqlite3VectorFieldSubexpr(CPtr(Any Ptr, local8), local9))
        local31 = c2fb_temp_36
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            local34 = arg1->x.pSelect->pEList->a(local9).pExpr
            c2fb_temp_37 = CPtr(sqlite3CollSeq Ptr, sqlite3BinaryCompareCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local31), CPtr(Any Ptr, local34)))
            local32 = c2fb_temp_37
        Else
            c2fb_temp_38 = CPtr(sqlite3CollSeq Ptr, sqlite3ExprCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local31)))
            local32 = c2fb_temp_38
        End If
        ' empty C statement
        sqlite3VdbeAddOp3(local3, Cast(SQLITE_C_INT, 96ULL), local15, local4[local9], local33)
        sqlite3VdbeAddOp4(local3, Cast(SQLITE_C_INT, 53ULL), Cast(SQLITE_C_INT, (local2 + local4[local9])), local13, local33, CPtr(Const ZString Ptr, CPtr(Any Ptr, local32)), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 2ULL)))))
        ' empty C statement
        sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local33)
    c2fb_flow_9:
        c2fb_temp_35 = local9
        local9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_35 + 1)))
    Wend
    c2fb_flow_8:
    sqlite3VdbeAddOp2(local3, Cast(SQLITE_C_INT, 9ULL), Cast(SQLITE_C_INT, &O0ULL), arg3)
    If (-Cast(SQLITE_C_INT, ((local6 > Cast(SQLITE_C_INT, 1ULL))))) Then
        sqlite3VdbeResolveLabel(local3, local13)
        sqlite3VdbeAddOp2(local3, Cast(SQLITE_C_INT, 40ULL), local15, Cast(SQLITE_C_INT, (local14 + Cast(SQLITE_C_INT, 1ULL))))
        ' empty C statement
        sqlite3VdbeAddOp2(local3, Cast(SQLITE_C_INT, 9ULL), Cast(SQLITE_C_INT, &O0ULL), arg2)
    End If
    sqlite3VdbeJumpHere(local3, local12)
    c2fb_label_1:
    ' empty C statement
    c2fb_label_0:
    sqlite3DbFree(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, local4))
    sqlite3DbFree(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, local5))
End Sub

Private Sub codeReal CDecl Alias "codeReal" (ByVal arg0 As SqliteVdbe Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
    Dim local0 As Double
    Dim c2fb_temp_0 As Double

    If ((-Cast(SQLITE_C_INT, ((arg1 <> Cast(SQLITE_C_INT, &O0ULL)))))) Then
        ' C automatic storage declaration
        sqlite3AtoF(arg1, CPtr(Double Ptr, @(local0)))
        ' C unused-parameter annotation
        If arg2 Then
            c2fb_temp_0 = Cast(Double, __c2fb_double_value(Cast(Double, (-local0))))
            local0 = c2fb_temp_0
        End If
        sqlite3VdbeAddDouble(arg0, arg3, local0)
    End If
End Sub

Private Sub codeInteger CDecl Alias "codeInteger" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr, _
    ByVal negativeFlag As SQLITE_C_INT, _
    ByVal targetRegister As SQLITE_C_INT _
)
    If pParse = 0 OrElse pExpr = 0 OrElse pParse->pVdbe = 0 Then Return
    Dim pVdbe As SqliteVdbe Ptr = pParse->pVdbe

    If (pExpr->flags And EP_IntValue) <> 0 Then
        Dim value32 As SQLITE_C_INT = pExpr->u.iValue
        If negativeFlag <> 0 Then value32 = -value32
        sqlite3VdbeAddOp2(pVdbe, OP_Integer, value32, targetRegister)
        Return
    End If

    Dim zToken As Const ZString Ptr = CPtr(Const ZString Ptr, pExpr->u.zToken)
    If zToken = 0 Then
        pParse->rc = SQLITE_CORRUPT
        Return
    End If

    Dim value As sqlite3_int64 = 0
    Dim parseCode As SQLITE_C_INT = sqlite3DecOrHexToI64(zToken, @value)
    Dim smallestInteger As sqlite3_int64 = -9223372036854775807LL - 1LL
    Dim mustUseReal As SQLITE_C_INT = 0

    If parseCode = 2 OrElse _
       (parseCode = 3 AndAlso negativeFlag = 0) OrElse _
       (negativeFlag <> 0 AndAlso value = smallestInteger) Then
        mustUseReal = 1
    End If

    If mustUseReal <> 0 Then
#ifdef SQLITE_OMIT_FLOATING_POINT
        sqlite3ErrorMsg(pParse, StrPtr(!"oversized integer: %s%#T"), _
                        IIf(negativeFlag <> 0, StrPtr("-"), StrPtr("")), pExpr)
#else
#ifndef SQLITE_OMIT_HEX_INTEGER
        If sqlite3_strnicmp(zToken, StrPtr("0x"), 2) = 0 Then
            sqlite3ErrorMsg(pParse, StrPtr(!"hex literal too big: %s%#T"), _
                            IIf(negativeFlag <> 0, StrPtr("-"), StrPtr("")), pExpr)
        Else
            codeReal(pVdbe, zToken, negativeFlag, targetRegister)
        End If
#else
        codeReal(pVdbe, zToken, negativeFlag, targetRegister)
#endif
#endif
        Return
    End If

    If negativeFlag <> 0 Then
        If parseCode = 3 Then
            ' The positive 2^63 token is valid only when prefixed by unary minus.
            value = smallestInteger
        Else
            value = -value
        End If
    End If
    sqlite3VdbeAddInt64(pVdbe, targetRegister, value)
End Sub

' c2fb skipped sqlite3ExprCodeLoadIndexColumn: FreeBASIC body already exists
' c2fb skipped sqlite3ExprCodeGeneratedColumn: FreeBASIC body already exists
' c2fb skipped sqlite3ExprCodeGetColumnOfTable: FreeBASIC body already exists
' c2fb skipped sqlite3ExprCodeGetColumn: FreeBASIC body already exists
' c2fb skipped sqlite3ExprCodeMove: FreeBASIC body already exists
' c2fb skipped sqlite3ExprToRegister: FreeBASIC body already exists
Private Function exprCodeVector CDecl Alias "exprCodeVector" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT

    ' C automatic storage declaration
    local1 = sqlite3ExprVectorSize(CPtr(Any Ptr, arg1))
    If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 1ULL))))) Then
        c2fb_temp_0 = Cast(SQLITE_C_INT, sqlite3ExprCodeTemp(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), arg2))
        local0 = c2fb_temp_0
    Else
        c2fb_temp_1 = CPtr(SQLITE_C_INT Ptr, @((*arg2)))
        c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_1) = c2fb_temp_2
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 139ULL))))) Then
            c2fb_temp_3 = Cast(SQLITE_C_INT, sqlite3CodeSubselect(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1)))
            local0 = c2fb_temp_3
        Else
            ' C automatic storage declaration
            c2fb_temp_4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg0->nMem + Cast(SQLITE_C_INT, 1ULL))))
            local0 = c2fb_temp_4
            c2fb_temp_5 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
            c2fb_temp_6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_5) + local1)))
            (*c2fb_temp_5) = c2fb_temp_6
            ' C unused-parameter annotation
            c2fb_temp_7 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local2 = c2fb_temp_7
            While (-Cast(SQLITE_C_INT, ((local2 < local1))))
                sqlite3ExprCodeFactorable(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->x.pList->a(local2).pExpr), Cast(SQLITE_C_INT, (local2 + local0)))
            c2fb_flow_1:
                c2fb_temp_8 = local2
                local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_8 + 1)))
            Wend
            c2fb_flow_0:
        End If
    End If
    Return local0
End Function

Private Sub setDoNotMergeFlagOnCopy CDecl Alias "setDoNotMergeFlagOnCopy" (ByVal arg0 As SqliteVdbe Ptr)
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(SqliteVdbeOp Ptr, sqlite3VdbeGetLastOp(arg0))->opcode) = Cast(SQLITE_C_INT, 82ULL))))) Then
        sqlite3VdbeChangeP5(arg0, Cast(SQLITE_C_INT, 1ULL))
    End If
End Sub

Private Function exprCodeInlineFunction CDecl Alias "exprCodeInlineFunction" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExprList Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SqliteVdbe Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim local4 As SqliteExpr
    Dim c2fb_temp_3 As Any Ptr
    Dim c2fb_temp_4 As u8 Ptr
    Dim c2fb_temp_5 As UByte
    Dim c2fb_temp_6 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_7 As SqliteExprList Ptr
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim local5 As SqliteExpr Ptr
    Dim c2fb_temp_9 As SqliteExpr Ptr
    Dim local6(0 To 5) As Const ZString Ptr
    Dim local7 As Byte
    Dim c2fb_temp_10 As Byte

    ' C automatic storage declaration
    local1 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, arg1->nExpr)
    local0 = c2fb_temp_0
    ' C unused-parameter annotation
    Select Case arg2
        Case Cast(SQLITE_C_INT, &O0ULL)
            local2 = sqlite3VdbeMakeLabel(arg0)
            ' C automatic storage declaration
            ' C unused-parameter annotation
            sqlite3ExprCode(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr), arg3)
            c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
            local3 = c2fb_temp_1
            While (-Cast(SQLITE_C_INT, ((local3 < local0))))
                sqlite3VdbeAddOp2(local1, Cast(SQLITE_C_INT, 52ULL), arg3, local2)
                ' empty C statement
                sqlite3ExprCode(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->a(local3).pExpr), arg3)
            c2fb_flow_2:
                c2fb_temp_2 = local3
                local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_2 + 1)))
            Wend
            c2fb_flow_1:
            setDoNotMergeFlagOnCopy(local1)
            sqlite3VdbeResolveLabel(local1, local2)
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 5ULL)
            ' C automatic storage declaration
            c2fb_temp_3 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, @(local4))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteExpr))))
            c2fb_temp_4 = CPtr(u8 Ptr, @(local4.op))
            c2fb_temp_5 = Cast(UByte, Cast(SQLITE_C_INT, 158ULL))
            (*c2fb_temp_4) = Cast(u8, c2fb_temp_5)
            c2fb_temp_5 = Cast(UByte, (*c2fb_temp_4))
            c2fb_temp_6 = CPtr(SqliteExprList Ptr Ptr, @(local4.x.pList))
            c2fb_temp_7 = arg1
            (*c2fb_temp_6) = c2fb_temp_7
            Return sqlite3ExprCodeTarget(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, @(local4))), arg3)
        Case Cast(SQLITE_C_INT, 3ULL)
            ' C unused-parameter annotation
            sqlite3VdbeAddOp2(local1, Cast(SQLITE_C_INT, 73ULL), sqlite3ExprCompare(Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, arg1->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr), CPtr(Any Ptr, arg1->a(Cast(SQLITE_C_INT, 1ULL)).pExpr), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))), arg3)
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 2ULL)
            ' C unused-parameter annotation
            sqlite3VdbeAddOp2(local1, Cast(SQLITE_C_INT, 73ULL), sqlite3ExprImpliesExpr(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr), CPtr(Any Ptr, arg1->a(Cast(SQLITE_C_INT, 1ULL)).pExpr), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))), arg3)
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 1ULL)
            ' C automatic storage declaration
            ' C unused-parameter annotation
            c2fb_temp_9 = arg1->a(Cast(SQLITE_C_INT, 1ULL)).pExpr
            local5 = c2fb_temp_9
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local5->op) = Cast(SQLITE_C_INT, 168ULL))))) Then
                sqlite3VdbeAddOp2(local1, Cast(SQLITE_C_INT, 73ULL), sqlite3ExprImpliesNonNullRow(CPtr(Any Ptr, arg1->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr), local5->iTable, Cast(SQLITE_C_INT, 1ULL)), arg3)
            Else
                sqlite3VdbeAddOp2(local1, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), arg3)
            End If
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 4ULL)
            Erase local6
            local6(0) = StrPtr(!"blob")
            local6(1) = StrPtr(!"text")
            local6(2) = StrPtr(!"numeric")
            local6(3) = StrPtr(!"integer")
            local6(4) = StrPtr(!"real")
            local6(5) = StrPtr(!"flexnum")
            ' C automatic storage declaration
            ' C unused-parameter annotation
            c2fb_temp_10 = Cast(Byte, sqlite3ExprAffinity(CPtr(Any Ptr, arg1->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr)))
            local7 = c2fb_temp_10
            ' C unused-parameter annotation
            sqlite3VdbeLoadString(local1, arg3, IIf(((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local7) <= Cast(SQLITE_C_INT, &H40ULL)))))), StrPtr(!"none"), local6(Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local7) - Cast(SQLITE_C_INT, &H41ULL))))))
            Goto c2fb_flow_0
        Case Else
            ' C unused-parameter annotation
            c2fb_temp_8 = Cast(SQLITE_C_INT, sqlite3ExprCodeTarget(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr), arg3))
            arg3 = c2fb_temp_8
            Goto c2fb_flow_0
    End Select
    c2fb_flow_0:
    Return arg3
End Function

' c2fb skipped exprNodeCanReturnSubtype: outside the supported subset
' c2fb skipped sqlite3ExprCanReturnSubtype: FreeBASIC body already exists
Private Function sqlite3IndexedExprLookup CDecl Alias "sqlite3IndexedExprLookup" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SqliteIndexedExpr Ptr
    Dim local1 As SqliteVdbe Ptr
    Dim c2fb_temp_0 As SqliteIndexedExpr Ptr
    Dim c2fb_temp_1 As SqliteIndexedExpr Ptr
    Dim local2 As UByte
    Dim local3 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As UByte
    Dim c2fb_temp_4 As SqliteVdbe Ptr
    Dim local4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SqliteIndexedExpr Ptr
    Dim c2fb_temp_6 As SqliteIndexedExpr Ptr Ptr
    Dim c2fb_temp_7 As SqliteIndexedExpr Ptr
    Dim c2fb_temp_8 As SqliteIndexedExpr Ptr Ptr
    Dim c2fb_temp_9 As SqliteIndexedExpr Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    c2fb_temp_0 = arg0->pIdxEpr
    local0 = c2fb_temp_0
    While local0
        ' C automatic storage declaration
        local3 = local0->iDataCur
        If (-Cast(SQLITE_C_INT, ((local3 < Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_1
        End If
        If arg0->iSelfTab Then
            If (-Cast(SQLITE_C_INT, ((local0->iDataCur <> Cast(SQLITE_C_INT, (arg0->iSelfTab - Cast(SQLITE_C_INT, 1ULL))))))) Then
                Goto c2fb_flow_1
            End If
            c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
            local3 = c2fb_temp_2
        End If
        If (-Cast(SQLITE_C_INT, ((sqlite3ExprCompare(Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, arg1), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local0->pExpr)), local3) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_1
        End If
        ' C unused-parameter annotation
        c2fb_temp_3 = Cast(UByte, sqlite3ExprAffinity(CPtr(Any Ptr, arg1)))
        local2 = c2fb_temp_3
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2) <= Cast(SQLITE_C_INT, &H41ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->aff) <> Cast(SQLITE_C_INT, &H41ULL)))))))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2) = Cast(SQLITE_C_INT, &H42ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->aff) <> Cast(SQLITE_C_INT, &H42ULL)))))))))))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2) >= Cast(SQLITE_C_INT, &H43ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->aff) <> Cast(SQLITE_C_INT, &H43ULL)))))))))))))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, &H80000000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) AndAlso sqlite3ExprCanReturnSubtype(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1)))))) Then
            Goto c2fb_flow_1
        End If
        c2fb_temp_4 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
        local1 = c2fb_temp_4
        ' C unused-parameter annotation
        If local0->bMaybeNullRow Then
            local4 = sqlite3VdbeCurrentAddr(local1)
            sqlite3VdbeAddOp3(local1, Cast(SQLITE_C_INT, 20ULL), local0->iIdxCur, Cast(SQLITE_C_INT, (local4 + Cast(SQLITE_C_INT, 3ULL))), arg2)
            ' empty C statement
            sqlite3VdbeAddOp3(local1, Cast(SQLITE_C_INT, 96ULL), local0->iIdxCur, local0->iIdxCol, arg2)
            ' empty C statement
            sqlite3VdbeGoto(local1, Cast(SQLITE_C_INT, &O0ULL))
            c2fb_temp_5 = arg0->pIdxEpr
            local0 = c2fb_temp_5
            c2fb_temp_6 = CPtr(SqliteIndexedExpr Ptr Ptr, @(arg0->pIdxEpr))
            c2fb_temp_7 = CPtr(SqliteIndexedExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            (*c2fb_temp_6) = c2fb_temp_7
            sqlite3ExprCode(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), arg2)
            c2fb_temp_8 = CPtr(SqliteIndexedExpr Ptr Ptr, @(arg0->pIdxEpr))
            c2fb_temp_9 = local0
            (*c2fb_temp_8) = c2fb_temp_9
            sqlite3VdbeJumpHere(local1, Cast(SQLITE_C_INT, (local4 + Cast(SQLITE_C_INT, 2ULL))))
        Else
            sqlite3VdbeAddOp3(local1, Cast(SQLITE_C_INT, 96ULL), local0->iIdxCur, local0->iIdxCol, arg2)
            ' empty C statement
        End If
        Return arg2
    c2fb_flow_1:
        c2fb_temp_1 = local0->pIENext
        local0 = c2fb_temp_1
    Wend
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))
End Function

Private Function exprPartidxExprLookup CDecl Alias "exprPartidxExprLookup" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SqliteIndexedExpr Ptr
    Dim c2fb_temp_0 As SqliteIndexedExpr Ptr
    Dim c2fb_temp_1 As SqliteIndexedExpr Ptr
    Dim local1 As SqliteVdbe Ptr
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT

    ' C automatic storage declaration
    c2fb_temp_0 = arg0->pIdxPartExpr
    local0 = c2fb_temp_0
    While local0
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->iColumn) = local0->iIdxCol)))) AndAlso (-Cast(SQLITE_C_INT, ((arg1->iTable = local0->iDataCur)))))))) Then
            local1 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
            local2 = Cast(SQLITE_C_INT, &O0ULL)
            ' C automatic storage declaration
            If local0->bMaybeNullRow Then
                c2fb_temp_2 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(local1, Cast(SQLITE_C_INT, 20ULL), local0->iIdxCur))
                local2 = c2fb_temp_2
            End If
            c2fb_temp_3 = Cast(SQLITE_C_INT, sqlite3ExprCodeTarget(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local0->pExpr)), arg2))
            local3 = c2fb_temp_3
            sqlite3VdbeAddOp4(CPtr(SqliteVdbe Ptr, arg0->pVdbe), Cast(SQLITE_C_INT, 98ULL), local3, Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, &O0ULL), CPtr(Const ZString Ptr, CPtr(UByte Ptr, @(local0->aff))), Cast(SQLITE_C_INT, 1ULL))
            If sqlite3ExprCanReturnSubtype(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local0->pExpr))) Then
                sqlite3VdbeAddOp1(CPtr(SqliteVdbe Ptr, arg0->pVdbe), Cast(SQLITE_C_INT, 182ULL), local3)
            End If
            If local2 Then
                sqlite3VdbeJumpHere(local1, local2)
                sqlite3VdbeChangeP3(local1, local2, local3)
            End If
            Return local3
        End If
    c2fb_flow_1:
        c2fb_temp_1 = local0->pIENext
        local0 = c2fb_temp_1
    Wend
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function exprCodeTargetAndOr CDecl Alias "exprCodeTargetAndOr" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim local6 As SqliteExpr Ptr
    Dim local7 As SqliteVdbe Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SqliteVdbe Ptr
    Dim c2fb_temp_2 As SqliteExpr Ptr
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
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local3 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, arg1->op)
    local0 = c2fb_temp_0
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' empty C statement
    ' C unused-parameter annotation
    ' empty C statement
    ' C unused-parameter annotation
    c2fb_temp_1 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    local7 = c2fb_temp_1
    c2fb_temp_2 = CPtr(SqliteExpr Ptr, sqlite3ExprSimplifiedAndOr(CPtr(Any Ptr, arg1)))
    local6 = c2fb_temp_2
    If (-Cast(SQLITE_C_INT, ((local6 <> arg1)))) Then
        c2fb_temp_3 = Cast(SQLITE_C_INT, sqlite3ExprCodeTarget(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local6), arg2))
        local4 = c2fb_temp_3
        sqlite3VdbeAddOp3(local7, Cast(SQLITE_C_INT, 44ULL), local4, local4, arg2)
        Return arg2
    End If
    c2fb_temp_4 = Cast(SQLITE_C_INT, IIf((-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, 44ULL))))), Cast(SQLITE_C_INT, 17ULL), Cast(SQLITE_C_INT, 16ULL)))
    local1 = c2fb_temp_4
    If exprEvalRhsFirst(arg1) Then
        c2fb_temp_5 = Cast(SQLITE_C_INT, sqlite3ExprCodeTarget(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pRight), arg2))
        local3 = c2fb_temp_5
        c2fb_temp_6 = Cast(SQLITE_C_INT, c2fb_temp_5)
        local5 = c2fb_temp_6
        c2fb_temp_7 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(local7, local1, local5))
        local2 = c2fb_temp_7
        ' empty C statement
        ' empty C statement
        c2fb_temp_8 = Cast(SQLITE_C_INT, sqlite3ExprCodeTemp(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pLeft), arg3))
        local4 = c2fb_temp_8
    Else
        c2fb_temp_9 = Cast(SQLITE_C_INT, sqlite3ExprCodeTarget(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pLeft), arg2))
        local4 = c2fb_temp_9
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1->pRight)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H400000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            c2fb_temp_10 = Cast(SQLITE_C_INT, local4)
            local3 = c2fb_temp_10
            c2fb_temp_11 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(local7, local1, local4))
            local2 = c2fb_temp_11
            ' empty C statement
            ' empty C statement
        Else
            c2fb_temp_12 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local3 = c2fb_temp_12
            c2fb_temp_13 = Cast(SQLITE_C_INT, c2fb_temp_12)
            local2 = c2fb_temp_13
        End If
        c2fb_temp_14 = Cast(SQLITE_C_INT, sqlite3ExprCodeTemp(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pRight), arg3))
        local5 = c2fb_temp_14
    End If
    sqlite3VdbeAddOp3(local7, local0, local5, local4, arg2)
    ' empty C statement
    If local2 Then
        sqlite3VdbeAddOp2(local7, Cast(SQLITE_C_INT, 9ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, (sqlite3VdbeCurrentAddr(local7) + Cast(SQLITE_C_INT, 2ULL))))
        sqlite3VdbeJumpHere(local7, local2)
        sqlite3VdbeAddOp3(local7, Cast(SQLITE_C_INT, 43ULL), local3, local3, arg2)
        ' empty C statement
    End If
    Return arg2
End Function

Function sqlite3ExprCodeTarget CDecl Alias "sqlite3ExprCodeTarget" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SqliteVdbe Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim local6 As SQLITE_C_INT
    Dim local7 As SqliteExpr
    Dim local8 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim local9 As SqliteAggInfo Ptr
    Dim local10 As SqliteAggInfoColumn Ptr
    Dim c2fb_temp_4 As SqliteAggInfoColumn Ptr
    Dim local11 As SqliteTable Ptr
    Dim local12 As SQLITE_C_INT
    Dim local13 As SQLITE_C_INT
    Dim local14 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Static local15(0 To 9) As Byte = {66, 0, 67, 0, 68, 0, 69, 0, 70, 0}
    Dim local16 As SqliteColumn Ptr
    Dim local17 As SqliteTable Ptr
    Dim local18 As SQLITE_C_INT
    Dim local19 As SQLITE_C_INT
    Dim c2fb_temp_7 As SqliteTable Ptr
    Dim c2fb_temp_8 As SqliteColumn Ptr
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As u16 Ptr
    Dim c2fb_temp_11 As UShort
    Dim c2fb_temp_12 As u16 Ptr
    Dim c2fb_temp_13 As UShort
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SQLITE_C_INT
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim local20 As SQLITE_C_INT
    Dim local21 As Const ZString Ptr
    Dim local22 As ZString Ptr
    Dim c2fb_temp_19 As Const ZString Ptr
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As ZString Ptr
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim c2fb_temp_23 As SQLITE_C_INT
    Dim local23 As SqliteExpr Ptr
    Dim local24 As SQLITE_C_INT
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As SQLITE_C_INT
    Dim c2fb_temp_26 As SQLITE_C_INT
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim local25 As SQLITE_C_INT
    Dim c2fb_temp_28 As SQLITE_C_INT
    Dim c2fb_temp_29 As SQLITE_C_INT
    Dim c2fb_temp_30 As SQLITE_C_INT
    Dim c2fb_temp_31 As SQLITE_C_INT
    Dim local26 As SqliteExpr Ptr
    Dim c2fb_temp_32 As u8 Ptr
    Dim c2fb_temp_33 As UByte
    Dim c2fb_temp_34 As u32 Ptr
    Dim c2fb_temp_35 As SQLITE_C_UINT
    Dim c2fb_temp_36 As SQLITE_C_INT Ptr
    Dim c2fb_temp_37 As SQLITE_C_INT
    Dim c2fb_temp_38 As SQLITE_C_INT
    Dim c2fb_temp_39 As SQLITE_C_INT
    Dim c2fb_temp_40 As SQLITE_C_INT
    Dim local27 As SQLITE_C_INT
    Dim local28 As SQLITE_C_INT
    Dim c2fb_temp_41 As SQLITE_C_INT
    Dim c2fb_temp_42 As SQLITE_C_INT
    Dim c2fb_temp_43 As SQLITE_C_INT
    Dim local29 As SQLITE_C_INT
    Dim c2fb_temp_44 As SQLITE_C_INT
    Dim c2fb_temp_45 As SQLITE_C_INT
    Dim local30 As SqliteAggInfo Ptr
    Dim local31 As SqliteExprList Ptr
    Dim local32 As SQLITE_C_INT
    Dim local33 As SqliteFuncDef Ptr
    Dim local34 As Const ZString Ptr
    Dim local35 As SQLITE_C_UINT
    Dim local36 As SQLITE_C_INT
    Dim local37 As sqlite3 Ptr
    Dim local38 As UByte
    Dim local39 As sqlite3CollSeq Ptr
    Dim c2fb_temp_46 As SqliteExprList Ptr
    Dim c2fb_temp_47 As SQLITE_C_INT
    Dim c2fb_temp_48 As Const ZString Ptr
    Dim c2fb_temp_49 As SqliteFuncDef Ptr
    Dim c2fb_temp_50 As SQLITE_C_INT
    Dim c2fb_temp_51 As SQLITE_C_INT
    Dim c2fb_temp_52 As SQLITE_C_UINT
    Dim c2fb_temp_53 As sqlite3CollSeq Ptr
    Dim c2fb_temp_54 As SQLITE_C_INT
    Dim c2fb_temp_55 As SQLITE_C_INT Ptr
    Dim c2fb_temp_56 As SQLITE_C_INT
    Dim c2fb_temp_57 As SQLITE_C_INT
    Dim local40 As UByte
    Dim c2fb_temp_58 As UByte
    Dim c2fb_temp_59 As u8 Ptr
    Dim c2fb_temp_60 As UByte
    Dim c2fb_temp_61 As SQLITE_C_INT
    Dim c2fb_temp_62 As SqliteFuncDef Ptr
    Dim c2fb_temp_63 As SqliteFuncDef Ptr
    Dim c2fb_temp_64 As sqlite3CollSeq Ptr
    Dim local41 As SQLITE_C_INT
    Dim c2fb_temp_65 As SQLITE_C_INT
    Dim c2fb_temp_66 As SQLITE_C_INT
    Dim local42 As SQLITE_C_INT
    Dim local43 As SqliteExpr Ptr
    Dim c2fb_temp_67 As SQLITE_C_INT Ptr
    Dim c2fb_temp_68 As SQLITE_C_INT
    Dim c2fb_temp_69 As u8 Ptr
    Dim c2fb_temp_70 As UByte
    Dim c2fb_temp_71 As SQLITE_C_INT
    Dim local44 As SQLITE_C_INT
    Dim local45 As SQLITE_C_INT
    Dim c2fb_temp_72 As SqliteExpr Ptr
    Dim c2fb_temp_73 As SqliteExpr Ptr
    Dim local46 As SqliteTable Ptr
    Dim local47 As SQLITE_C_INT
    Dim local48 As SQLITE_C_INT
    Dim c2fb_temp_74 As SqliteTable Ptr
    Dim c2fb_temp_75 As SQLITE_C_INT
    Dim c2fb_temp_76 As SQLITE_C_INT
    Dim local49 As SQLITE_C_INT
    Dim local50 As UByte
    Dim local51 As SqliteAggInfo Ptr
    Dim c2fb_temp_77 As SQLITE_C_INT
    Dim c2fb_temp_78 As SQLITE_C_INT
    Dim c2fb_temp_79 As SQLITE_C_INT
    Dim c2fb_temp_80 As u8 Ptr
    Dim c2fb_temp_81 As SQLITE_C_INT
    Dim c2fb_temp_82 As u8 Ptr
    Dim c2fb_temp_83 As SQLITE_C_INT
    Dim local52 As SQLITE_C_INT
    Dim local53 As SQLITE_C_INT
    Dim local54 As SQLITE_C_INT
    Dim local55 As SQLITE_C_INT
    Dim local56 As SqliteExprList Ptr
    Dim local57 As SqliteExprListItem Ptr
    Dim local58 As SqliteExpr
    Dim local59 As SqliteExpr Ptr
    Dim local60 As SqliteExpr Ptr
    Dim local61 As SqliteExpr Ptr
    Dim local62 As sqlite3 Ptr
    Dim c2fb_temp_84 As SqliteExprList Ptr
    Dim c2fb_temp_85 As SqliteExprListItem Ptr
    Dim c2fb_temp_86 As SQLITE_C_INT
    Dim c2fb_temp_87 As SQLITE_C_INT
    Dim c2fb_temp_88 As SqliteExpr Ptr
    Dim c2fb_temp_89 As SqliteExpr Ptr
    Dim c2fb_temp_90 As Any Ptr
    Dim c2fb_temp_91 As u8 Ptr
    Dim c2fb_temp_92 As UByte
    Dim c2fb_temp_93 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_94 As SqliteExpr Ptr
    Dim c2fb_temp_95 As SqliteExpr Ptr
    Dim c2fb_temp_96 As SQLITE_C_INT
    Dim c2fb_temp_97 As SQLITE_C_INT
    Dim c2fb_temp_98 As SQLITE_C_INT
    Dim c2fb_temp_99 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_100 As SqliteExpr Ptr
    Dim c2fb_temp_101 As SqliteExpr Ptr
    Dim c2fb_temp_102 As SQLITE_C_INT
    Dim c2fb_temp_103 As SQLITE_C_INT
    Dim c2fb_switch_value_104 As sqlite3_uint64
    Dim c2fb_switch_state_105 As SQLITE_C_INT

    local0 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    ' C automatic storage declaration
    local2 = arg2
    local3 = Cast(SQLITE_C_INT, &O0ULL)
    local4 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local8 = Cast(SQLITE_C_INT, &O0ULL)
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_label_0:
    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 122ULL))
        local1 = c2fb_temp_0
    Else
        c2fb_temp_2 = 0
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg0->pIdxEpr <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H800000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))))))) Then
            c2fb_temp_1 = Cast(SQLITE_C_INT, sqlite3IndexedExprLookup(arg0, arg1, arg2))
            local5 = c2fb_temp_1
            c2fb_temp_2 = (-Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, (((c2fb_temp_1) >= Cast(SQLITE_C_INT, &O0ULL))))) <> 0)))
        End If
        If c2fb_temp_2 Then
            Return local5
        Else
            ' C unused-parameter annotation
            c2fb_temp_3 = Cast(SQLITE_C_INT, arg1->op)
            local1 = c2fb_temp_3
        End If
    End If
    ' C unused-parameter annotation
    c2fb_switch_value_104 = Cast(sqlite3_uint64, local1)
    c2fb_switch_state_105 = 0
    Select Case c2fb_switch_value_104
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 170ULL))
            c2fb_switch_state_105 = 1
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 168ULL))
            c2fb_switch_state_105 = 2
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 156ULL))
            c2fb_switch_state_105 = 3
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 171ULL))
            c2fb_switch_state_105 = 4
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 154ULL))
            c2fb_switch_state_105 = 5
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 118ULL))
            c2fb_switch_state_105 = 6
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 83ULL))
            c2fb_switch_state_105 = 7
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 155ULL))
            c2fb_switch_state_105 = 9
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 157ULL))
            c2fb_switch_state_105 = 10
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 176ULL))
            c2fb_switch_state_105 = 11
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 36ULL))
            c2fb_switch_state_105 = 12
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 45ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 46ULL))
            c2fb_switch_state_105 = 13
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 57ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 56ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 55ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 58ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 53ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 54ULL))
            c2fb_switch_state_105 = 14
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 44ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 43ULL))
            c2fb_switch_state_105 = 15
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 107ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 109ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 108ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 111ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 103ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 104ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 110ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 105ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 106ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 112ULL))
            c2fb_switch_state_105 = 16
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 174ULL))
            c2fb_switch_state_105 = 17
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 115ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 19ULL))
            c2fb_switch_state_105 = 18
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 175ULL))
            c2fb_switch_state_105 = 19
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 51ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 52ULL))
            c2fb_switch_state_105 = 20
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 169ULL))
            c2fb_switch_state_105 = 21
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 172ULL))
            c2fb_switch_state_105 = 22
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 20ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 139ULL))
            c2fb_switch_state_105 = 23
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 178ULL))
            c2fb_switch_state_105 = 24
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 50ULL))
            c2fb_switch_state_105 = 25
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 49ULL))
            c2fb_switch_state_105 = 26
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 114ULL))
            c2fb_switch_state_105 = 27
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 181ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 173ULL))
            c2fb_switch_state_105 = 28
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 78ULL))
            c2fb_switch_state_105 = 29
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 177ULL))
            c2fb_switch_state_105 = 30
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 179ULL))
            c2fb_switch_state_105 = 31
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 158ULL))
            c2fb_switch_state_105 = 32
        Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 72ULL))
            c2fb_switch_state_105 = 33
        Case Else
            c2fb_switch_state_105 = 8
    End Select
    Do
        Select Case c2fb_switch_state_105
        Case 0
            Exit Do
        Case 1
            local9 = CPtr(SqliteAggInfo Ptr, arg1->pAggInfo)
            ' C automatic storage declaration
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->iAgg) >= local9->nColumn)))) Then
                sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), arg2)
                Goto c2fb_flow_0
            End If
            c2fb_temp_4 = CPtr(SqliteAggInfoColumn Ptr, @(local9->aCol[arg1->iAgg]))
            local10 = c2fb_temp_4
            If (-Cast(SQLITE_C_INT, (local9->directMode = 0))) Then
                Return (Cast(SQLITE_C_INT, ((local9)->iFirstReg + Cast(SQLITE_C_INT, (arg1->iAgg)))))
            Else
                If local9->useSortingIdx Then
                    local11 = local10->pTab
                    sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 96ULL), local9->sortingIdxPTab, local10->iSorterColumn, arg2)
                    If (-Cast(SQLITE_C_INT, ((local11 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        ' empty C block
                    Else
                        If (-Cast(SQLITE_C_INT, ((local10->iColumn < Cast(SQLITE_C_INT, &O0ULL))))) Then
                            ' empty C statement
                        Else
                            ' empty C statement
                            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local11->aCol[local10->iColumn].affinity) = Cast(SQLITE_C_INT, &H45ULL))))) Then
                                sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 89ULL), arg2)
                            End If
                        End If
                    End If
                    Return arg2
                Else
                    If (-Cast(SQLITE_C_INT, ((CPtr(SqliteTable Ptr, arg1->y.pTab) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 96ULL), arg1->iTable, arg1->iColumn, arg2)
                        Return arg2
                    End If
                End If
            End If
            ' C switch fallthrough annotation
            c2fb_switch_state_105 = 2
        Case 2
            local12 = arg1->iTable
            ' C automatic storage declaration
            If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000020ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                ' C automatic storage declaration
                c2fb_temp_5 = Cast(SQLITE_C_INT, sqlite3ExprCodeTarget(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pLeft), arg2))
                local13 = c2fb_temp_5
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                c2fb_temp_6 = Cast(SQLITE_C_INT, sqlite3TableColumnAffinity(CPtr(Any Ptr, CPtr(SqliteTable Ptr, arg1->y.pTab)), arg1->iColumn))
                local14 = c2fb_temp_6
                If (-Cast(SQLITE_C_INT, ((local14 > Cast(SQLITE_C_INT, &H41ULL))))) Then
                    ' C static array storage
                    ' C unused-parameter annotation
                    ' C unused-parameter annotation
                    sqlite3VdbeAddOp4(local0, Cast(SQLITE_C_INT, 98ULL), local13, Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, &O0ULL), CPtr(Const ZString Ptr, CPtr(Byte Ptr, @(local15(Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local14 - Cast(SQLITE_C_INT, 66)))) * Cast(SQLITE_C_INT, 2ULL))))))), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))))
                End If
                Return local13
            End If
            If (-Cast(SQLITE_C_INT, ((local12 < Cast(SQLITE_C_INT, &O0ULL))))) Then
                If (-Cast(SQLITE_C_INT, ((arg0->iSelfTab < Cast(SQLITE_C_INT, &O0ULL))))) Then
                    ' C automatic storage declaration
                    ' C automatic storage declaration
                    ' C automatic storage declaration
                    local19 = arg1->iColumn
                    ' C unused-parameter annotation
                    c2fb_temp_7 = CPtr(SqliteTable Ptr, arg1->y.pTab)
                    local17 = c2fb_temp_7
                    ' C unused-parameter annotation
                    ' C unused-parameter annotation
                    ' C unused-parameter annotation
                    If (-Cast(SQLITE_C_INT, ((local19 < Cast(SQLITE_C_INT, &O0ULL))))) Then
                        Return Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))) - arg0->iSelfTab))
                    End If
                    c2fb_temp_8 = CPtr(SqliteColumn Ptr, (local17->aCol + local19))
                    local16 = c2fb_temp_8
                    ' empty C statement
                    c2fb_temp_9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, sqlite3TableColumnToStorage(CPtr(Any Ptr, local17), local19)) - arg0->iSelfTab)))
                    local18 = c2fb_temp_9
                    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local16->colFlags) And Cast(SQLITE_C_INT, &H0060ULL))) Then
                        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local16->colFlags) And Cast(SQLITE_C_INT, &H0100ULL))) Then
                            sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"generated column loop on \034%s\034"), local16->zCnName)
                            Return Cast(SQLITE_C_INT, &O0ULL)
                        End If
                        c2fb_temp_10 = CPtr(u16 Ptr, @(local16->colFlags))
                        c2fb_temp_11 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_10))) Or Cast(SQLITE_C_INT, &H0100ULL))))
                        (*c2fb_temp_10) = Cast(u16, c2fb_temp_11)
                        c2fb_temp_11 = Cast(UShort, (*c2fb_temp_10))
                        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local16->colFlags) And Cast(SQLITE_C_INT, &H0080ULL))) Then
                            sqlite3ExprCodeGeneratedColumn(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local17), CPtr(Any Ptr, local16), local18)
                        End If
                        c2fb_temp_12 = CPtr(u16 Ptr, @(local16->colFlags))
                        c2fb_temp_13 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_12))) And Cast(SQLITE_C_INT, (Not (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0100ULL) Or Cast(SQLITE_C_INT, &H0080ULL)))))))))
                        (*c2fb_temp_12) = Cast(u16, c2fb_temp_13)
                        c2fb_temp_13 = Cast(UShort, (*c2fb_temp_12))
                        Return local18
                    Else
                        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local16->affinity) = Cast(SQLITE_C_INT, &H45ULL))))) Then
                            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 83ULL), local18, arg2)
                            sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 89ULL), arg2)
                            Return arg2
                        Else
                            Return local18
                        End If
                    End If
                Else
                    c2fb_temp_14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg0->iSelfTab - Cast(SQLITE_C_INT, 1ULL))))
                    local12 = c2fb_temp_14
                End If
            Else
                c2fb_temp_17 = 0
                If arg0->pIdxPartExpr Then
                    c2fb_temp_16 = Cast(SQLITE_C_INT, &O0ULL)
                    c2fb_temp_15 = Cast(SQLITE_C_INT, exprPartidxExprLookup(arg0, arg1, arg2))
                    local5 = c2fb_temp_15
                    c2fb_temp_17 = (-Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, ((c2fb_temp_16 <> (c2fb_temp_15))))) <> 0)))
                End If
                If c2fb_temp_17 Then
                    Return local5
                End If
            End If
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_18 = Cast(SQLITE_C_INT, sqlite3ExprCodeGetColumn(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteTable Ptr, arg1->y.pTab)), arg1->iColumn, local12, arg2, arg1->op2))
            local13 = c2fb_temp_18
            Return local13
        Case 3
            codeInteger(arg0, arg1, Cast(SQLITE_C_INT, &O0ULL), arg2)
            Return arg2
        Case 4
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 73ULL), sqlite3ExprTruthValue(CPtr(Any Ptr, arg1)), arg2)
            Return arg2
        Case 5
            ' C unused-parameter annotation
            codeReal(local0, CPtr(Const ZString Ptr, CPtr(ZString Ptr, arg1->u.zToken)), Cast(SQLITE_C_INT, &O0ULL), arg2)
            Return arg2
        Case 6
            ' C unused-parameter annotation
            sqlite3VdbeLoadString(local0, arg2, CPtr(Const ZString Ptr, CPtr(ZString Ptr, arg1->u.zToken)))
            Return arg2
        Case 7
            sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), arg2, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (arg2 + arg1->y.nReg)) - Cast(SQLITE_C_INT, 1ULL))))
            Return arg2
        Case 8
            ' C unused-parameter annotation
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), arg2)
            Return arg2
        Case 9
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_19 = CPtr(Const ZString Ptr, CPtr(Byte Ptr, @(CPtr(Byte Ptr, CPtr(ZString Ptr, arg1->u.zToken))[Cast(SQLITE_C_INT, 2ULL)])))
            local21 = c2fb_temp_19
            c2fb_temp_20 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (sqlite3Strlen30(local21) - Cast(SQLITE_C_INT, 1ULL))))
            local20 = c2fb_temp_20
            ' C unused-parameter annotation
            c2fb_temp_21 = CPtr(ZString Ptr, CPtr(Any Ptr, sqlite3HexToBlob(CPtr(Any Ptr, CPtr(sqlite3 Ptr, sqlite3VdbeDb(local0))), local21, local20)))
            local22 = c2fb_temp_21
            sqlite3VdbeAddOp4(local0, Cast(SQLITE_C_INT, 79ULL), Cast(SQLITE_C_INT, (local20 \ Cast(SQLITE_C_INT, 2ULL))), arg2, Cast(SQLITE_C_INT, &O0ULL), CPtr(Const ZString Ptr, local22), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 7ULL)))))
            Return arg2
        Case 10
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 80ULL), arg1->iColumn, arg2)
            Return arg2
        Case 11
            Return arg1->iTable
        Case 12
            sqlite3ExprCode(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pLeft), arg2)
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 90ULL), arg2, sqlite3AffinityType(CPtr(Const ZString Ptr, CPtr(ZString Ptr, arg1->u.zToken)), Cast(SQLITE_C_INT, &O0ULL)))
            Return local2
        Case 13
            c2fb_temp_22 = Cast(SQLITE_C_INT, IIf(((-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 45ULL)))))), Cast(SQLITE_C_INT, 54ULL), Cast(SQLITE_C_INT, 53ULL)))
            local1 = c2fb_temp_22
            c2fb_temp_23 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &H80ULL))
            local8 = c2fb_temp_23
            ' C switch fallthrough annotation
            c2fb_switch_state_105 = 14
        Case 14
            local23 = arg1->pLeft
            local24 = Cast(SQLITE_C_INT, &O0ULL)
            If sqlite3ExprIsVector(CPtr(Any Ptr, local23)) Then
                codeVectorCompare(arg0, arg1, arg2, local1, local8)
            Else
                If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H400000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) AndAlso (-Cast(SQLITE_C_INT, ((local8 <> Cast(SQLITE_C_INT, &H80ULL))))))))) Then
                    c2fb_temp_24 = Cast(SQLITE_C_INT, exprComputeOperands(arg0, arg1, CPtr(SQLITE_C_INT Ptr, @(local5)), CPtr(SQLITE_C_INT Ptr, @(local6)), CPtr(SQLITE_C_INT Ptr, @(local3)), CPtr(SQLITE_C_INT Ptr, @(local4))))
                    local24 = c2fb_temp_24
                Else
                    c2fb_temp_25 = Cast(SQLITE_C_INT, sqlite3ExprCodeTemp(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pLeft), CPtr(SQLITE_C_INT Ptr, @(local3))))
                    local5 = c2fb_temp_25
                    c2fb_temp_26 = Cast(SQLITE_C_INT, sqlite3ExprCodeTemp(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pRight), CPtr(SQLITE_C_INT Ptr, @(local4))))
                    local6 = c2fb_temp_26
                End If
                sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, 1ULL), local2)
                codeCompare(arg0, local23, arg1->pRight, local1, local5, local6, Cast(SQLITE_C_INT, (sqlite3VdbeCurrentAddr(local0) + Cast(SQLITE_C_INT, 2ULL))), local8, ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000400ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))
                ' C unused-parameter annotation
                ' empty C statement
                ' empty C statement
                ' C unused-parameter annotation
                ' empty C statement
                ' empty C statement
                ' C unused-parameter annotation
                ' empty C statement
                ' empty C statement
                ' C unused-parameter annotation
                ' empty C statement
                ' empty C statement
                ' C unused-parameter annotation
                ' empty C statement
                ' empty C statement
                ' C unused-parameter annotation
                ' empty C statement
                ' empty C statement
                If (-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, &H80ULL))))) Then
                    sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, &O0ULL), local2)
                Else
                    sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 94ULL), local5, local2, local6)
                    If local24 Then
                        sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 9ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, (sqlite3VdbeCurrentAddr(local0) + Cast(SQLITE_C_INT, 2ULL))))
                        sqlite3VdbeJumpHere(local0, local24)
                        sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), local2)
                    End If
                End If
                ' empty C statement
                ' empty C statement
            End If
            Goto c2fb_flow_0
            c2fb_switch_state_105 = 0
        Case 15
            c2fb_temp_27 = Cast(SQLITE_C_INT, exprCodeTargetAndOr(arg0, arg1, arg2, CPtr(SQLITE_C_INT Ptr, @(local3))))
            local2 = c2fb_temp_27
            Goto c2fb_flow_0
            c2fb_switch_state_105 = 0
        Case 16
            ' C automatic storage declaration
            ' C unused-parameter annotation
            ' empty C statement
            ' C unused-parameter annotation
            ' empty C statement
            ' C unused-parameter annotation
            ' empty C statement
            ' C unused-parameter annotation
            ' empty C statement
            ' C unused-parameter annotation
            ' empty C statement
            ' C unused-parameter annotation
            ' empty C statement
            ' C unused-parameter annotation
            ' empty C statement
            ' C unused-parameter annotation
            ' empty C statement
            ' C unused-parameter annotation
            ' empty C statement
            If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H400000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                c2fb_temp_28 = Cast(SQLITE_C_INT, exprComputeOperands(arg0, arg1, CPtr(SQLITE_C_INT Ptr, @(local5)), CPtr(SQLITE_C_INT Ptr, @(local6)), CPtr(SQLITE_C_INT Ptr, @(local3)), CPtr(SQLITE_C_INT Ptr, @(local4))))
                local25 = c2fb_temp_28
            Else
                c2fb_temp_29 = Cast(SQLITE_C_INT, sqlite3ExprCodeTemp(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pLeft), CPtr(SQLITE_C_INT Ptr, @(local3))))
                local5 = c2fb_temp_29
                c2fb_temp_30 = Cast(SQLITE_C_INT, sqlite3ExprCodeTemp(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pRight), CPtr(SQLITE_C_INT Ptr, @(local4))))
                local6 = c2fb_temp_30
                c2fb_temp_31 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local25 = c2fb_temp_31
            End If
            sqlite3VdbeAddOp3(local0, local1, local6, local5, arg2)
            ' empty C statement
            ' empty C statement
            If local25 Then
                sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 9ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, (sqlite3VdbeCurrentAddr(local0) + Cast(SQLITE_C_INT, 2ULL))))
                sqlite3VdbeJumpHere(local0, local25)
                sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), arg2)
                ' empty C statement
            End If
            Goto c2fb_flow_0
            c2fb_switch_state_105 = 0
        Case 17
            local26 = arg1->pLeft
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local26->op) = Cast(SQLITE_C_INT, 156ULL))))) Then
                codeInteger(arg0, local26, Cast(SQLITE_C_INT, 1ULL), arg2)
                Return arg2
            Else
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local26->op) = Cast(SQLITE_C_INT, 154ULL))))) Then
                    ' C unused-parameter annotation
                    codeReal(local0, CPtr(Const ZString Ptr, CPtr(ZString Ptr, local26->u.zToken)), Cast(SQLITE_C_INT, 1ULL), arg2)
                    Return arg2
                Else
                    c2fb_temp_32 = CPtr(u8 Ptr, @(local7.op))
                    c2fb_temp_33 = Cast(UByte, Cast(SQLITE_C_INT, 156ULL))
                    (*c2fb_temp_32) = Cast(u8, c2fb_temp_33)
                    c2fb_temp_33 = Cast(UByte, (*c2fb_temp_32))
                    c2fb_temp_34 = CPtr(u32 Ptr, @(local7.flags))
                    c2fb_temp_35 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000800ULL) Or Cast(SQLITE_C_INT, &H010000ULL))))
                    (*c2fb_temp_34) = Cast(u32, c2fb_temp_35)
                    c2fb_temp_35 = Cast(SQLITE_C_UINT, (*c2fb_temp_34))
                    c2fb_temp_36 = CPtr(SQLITE_C_INT Ptr, @(local7.u.iValue))
                    c2fb_temp_37 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    (*c2fb_temp_36) = c2fb_temp_37
                    ' empty C statement
                    c2fb_temp_38 = Cast(SQLITE_C_INT, sqlite3ExprCodeTemp(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, @(local7))), CPtr(SQLITE_C_INT Ptr, @(local3))))
                    local5 = c2fb_temp_38
                    c2fb_temp_39 = Cast(SQLITE_C_INT, sqlite3ExprCodeTemp(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pLeft), CPtr(SQLITE_C_INT Ptr, @(local4))))
                    local6 = c2fb_temp_39
                    sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 108ULL), local6, local5, arg2)
                    ' empty C statement
                End If
            End If
            Goto c2fb_flow_0
            c2fb_switch_state_105 = 0
        Case 18
            ' C unused-parameter annotation
            ' empty C statement
            ' C unused-parameter annotation
            ' empty C statement
            c2fb_temp_40 = Cast(SQLITE_C_INT, sqlite3ExprCodeTemp(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pLeft), CPtr(SQLITE_C_INT Ptr, @(local3))))
            local5 = c2fb_temp_40
            ' empty C statement
            sqlite3VdbeAddOp2(local0, local1, local5, local2)
            Goto c2fb_flow_0
            c2fb_switch_state_105 = 0
        Case 19
            ' C automatic storage declaration
            ' C automatic storage declaration
            c2fb_temp_41 = Cast(SQLITE_C_INT, sqlite3ExprCodeTemp(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pLeft), CPtr(SQLITE_C_INT Ptr, @(local3))))
            local5 = c2fb_temp_41
            ' empty C statement
            c2fb_temp_42 = Cast(SQLITE_C_INT, sqlite3ExprTruthValue(CPtr(Any Ptr, arg1->pRight)))
            local27 = c2fb_temp_42
            c2fb_temp_43 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op2) = Cast(SQLITE_C_INT, 45ULL))))))
            local28 = c2fb_temp_43
            ' empty C statement
            ' empty C statement
            sqlite3VdbeAddOp4Int(local0, Cast(SQLITE_C_INT, 93ULL), local5, local2, (-Cast(SQLITE_C_INT, (local27 = 0))), Cast(SQLITE_C_INT, (local27 Xor local28)))
            Goto c2fb_flow_0
            c2fb_switch_state_105 = 0
        Case 20
            ' C automatic storage declaration
            ' C unused-parameter annotation
            ' empty C statement
            ' C unused-parameter annotation
            ' empty C statement
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, 1ULL), arg2)
            c2fb_temp_44 = Cast(SQLITE_C_INT, sqlite3ExprCodeTemp(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pLeft), CPtr(SQLITE_C_INT Ptr, @(local3))))
            local5 = c2fb_temp_44
            ' empty C statement
            c2fb_temp_45 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(local0, local1, local5))
            local29 = c2fb_temp_45
            ' empty C statement
            ' empty C statement
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, &O0ULL), arg2)
            sqlite3VdbeJumpHere(local0, local29)
            Goto c2fb_flow_0
            c2fb_switch_state_105 = 0
        Case 21
            local30 = CPtr(SqliteAggInfo Ptr, arg1->pAggInfo)
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local30 = Cast(SQLITE_C_INT, &O0ULL))))) OrElse ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->iAgg) < Cast(SQLITE_C_INT, &O0ULL)))))))))) OrElse ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->iAgg) >= local30->nFunc))))))))) Then
                ' C unused-parameter annotation
                sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"misuse of aggregate: %#T()"), arg1)
            Else
                Return (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, ((local30)->iFirstReg + (local30)->nColumn)) + Cast(SQLITE_C_INT, (arg1->iAgg)))))
            End If
            Goto c2fb_flow_0
            c2fb_switch_state_105 = 0
        Case 22
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            local35 = Cast(SQLITE_C_INT, &O0ULL)
            ' C automatic storage declaration
            local37 = arg0->db
            local38 = ((local37)->enc)
            local39 = Cast(SQLITE_C_INT, &O0ULL)
#ifndef SQLITE_OMIT_WINDOWFUNC
            If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H1000000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                Return CPtr(SqliteWalkerWindow Ptr, arg1->y.pWin)->regResult
            End If
#endif
            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (arg0)->okConstFactor)) AndAlso sqlite3ExprIsConstantNotJoin(arg0, arg1))))) Then
                Return sqlite3ExprCodeRunJustOnce(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
            End If
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_46 = arg1->x.pList
            local31 = c2fb_temp_46
            c2fb_temp_47 = Cast(SQLITE_C_INT, IIf(local31, local31->nExpr, Cast(SQLITE_C_INT, &O0ULL)))
            local32 = c2fb_temp_47
            ' C unused-parameter annotation
            c2fb_temp_48 = CPtr(Const ZString Ptr, CPtr(ZString Ptr, arg1->u.zToken))
            local34 = c2fb_temp_48
            c2fb_temp_49 = CPtr(SqliteFuncDef Ptr, sqlite3FindFunction(CPtr(Any Ptr, local37), local34, local32, local38, Cast(SQLITE_C_INT, &O0ULL)))
            local33 = c2fb_temp_49
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local33 = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((CPtr(Any Ptr, CPtr(c2fb_callback_10, local33->xFinalize)) <> CPtr(Any Ptr, Cast(SQLITE_C_INT, &O0ULL)))))))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local33->funcFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00040000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, (arg0->nested = 0))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local37->mDbFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0020ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))))))) Then
                sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"unknown function: %#T()"), arg1)
                Goto c2fb_flow_0
            End If
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local33->funcFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00400000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso ((-Cast(SQLITE_C_INT, ((local31 <> Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                Return exprCodeInlineFunction(arg0, local31, (Cast(SQLITE_C_INT, Cast(SQLITE_C_LONG, Cast(Integer, (local33->pUserData))))), arg2)
            Else
                If Cast(SQLITE_C_UINT, (local33->funcFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00080000ULL) Or Cast(SQLITE_C_INT, &H00200000ULL))))))) Then
                    sqlite3ExprFunctionUsable(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), CPtr(Any Ptr, local33))
                End If
            End If
            c2fb_temp_50 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local36 = c2fb_temp_50
            While (-Cast(SQLITE_C_INT, ((local36 < local32))))
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local36 < Cast(SQLITE_C_INT, 32ULL))))) AndAlso sqlite3ExprIsConstant(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local31->a(local36).pExpr)))))) Then
                    ' empty C statement
                    c2fb_temp_52 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (local35 Or (Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))) Shl (local36)))))))
                    local35 = c2fb_temp_52
                End If
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local33->funcFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0020ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, (local39 = 0))))))) Then
                    c2fb_temp_53 = CPtr(sqlite3CollSeq Ptr, sqlite3ExprCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local31->a(local36).pExpr)))
                    local39 = c2fb_temp_53
                End If
            c2fb_flow_2:
                c2fb_temp_51 = local36
                local36 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_51 + 1)))
            Wend
            c2fb_flow_1:
            If local31 Then
                If local35 Then
                    c2fb_temp_54 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg0->nMem + Cast(SQLITE_C_INT, 1ULL))))
                    local5 = c2fb_temp_54
                    c2fb_temp_55 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
                    c2fb_temp_56 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_55) + local32)))
                    (*c2fb_temp_55) = c2fb_temp_56
                Else
                    c2fb_temp_57 = Cast(SQLITE_C_INT, sqlite3GetTempRange(CPtr(Any Ptr, arg0), local32))
                    local5 = c2fb_temp_57
                End If
                If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local33->funcFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0040ULL) Or Cast(SQLITE_C_INT, &H0080ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                    ' C automatic storage declaration
                    ' C unused-parameter annotation
                    ' C unused-parameter annotation
                    c2fb_temp_58 = Cast(UByte, local31->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr->op)
                    local40 = c2fb_temp_58
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local40) = Cast(SQLITE_C_INT, 168ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local40) = Cast(SQLITE_C_INT, 170ULL))))))))) Then
                        ' C unused-parameter annotation
                        ' C unused-parameter annotation
                        ' C unused-parameter annotation
                        ' C unused-parameter annotation
                        ' empty C statement
                        ' empty C statement
                        ' empty C statement
                        c2fb_temp_59 = CPtr(u8 Ptr, @(local31->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr->op2))
                        c2fb_temp_60 = Cast(UByte, Cast(SQLITE_C_UINT, (local33->funcFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &Hc0ULL)))))
                        (*c2fb_temp_59) = Cast(u8, c2fb_temp_60)
                        c2fb_temp_60 = Cast(UByte, (*c2fb_temp_59))
                    End If
                End If
                sqlite3ExprCodeExprList(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local31), local5, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &H02ULL))
            Else
                c2fb_temp_61 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local5 = c2fb_temp_61
            End If
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local32 >= Cast(SQLITE_C_INT, 2ULL))))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000100ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
                c2fb_temp_62 = CPtr(SqliteFuncDef Ptr, sqlite3VtabOverloadFunction(CPtr(Any Ptr, local37), CPtr(Any Ptr, local33), local32, CPtr(Any Ptr, local31->a(Cast(SQLITE_C_INT, 1ULL)).pExpr)))
                local33 = c2fb_temp_62
            Else
                If (-Cast(SQLITE_C_INT, ((local32 > Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_63 = CPtr(SqliteFuncDef Ptr, sqlite3VtabOverloadFunction(CPtr(Any Ptr, local37), CPtr(Any Ptr, local33), local32, CPtr(Any Ptr, local31->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr)))
                    local33 = c2fb_temp_63
                End If
            End If
            If Cast(SQLITE_C_UINT, (local33->funcFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0020ULL)))) Then
                If (-Cast(SQLITE_C_INT, (local39 = 0))) Then
                    c2fb_temp_64 = local37->pDfltColl
                    local39 = c2fb_temp_64
                End If
                sqlite3VdbeAddOp4(local0, Cast(SQLITE_C_INT, 87ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), CPtr(Const ZString Ptr, CPtr(ZString Ptr, local39)), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 2ULL)))))
            End If
            sqlite3VdbeAddFunctionCall(arg0, local35, local5, arg2, local32, CPtr(Const SqliteFuncDef Ptr, local33), arg1->op2)
            If local32 Then
                If (-Cast(SQLITE_C_INT, ((local35 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                    sqlite3ReleaseTempRange(CPtr(Any Ptr, arg0), local5, local32)
                Else
                    ' empty C statement
                End If
            End If
            Return arg2
        Case 23
            ' C automatic storage declaration
            ' empty C statement
            ' empty C statement
            If arg0->db->mallocFailed Then
                Return Cast(SQLITE_C_INT, &O0ULL)
            Else
                c2fb_temp_66 = 0
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 139ULL))))) AndAlso (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))))) Then
                    c2fb_temp_65 = Cast(SQLITE_C_INT, arg1->x.pSelect->pEList->nExpr)
                    local41 = c2fb_temp_65
                    c2fb_temp_66 = (-Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, (((c2fb_temp_65) <> Cast(SQLITE_C_INT, 1ULL))))) <> 0)))
                End If
                If c2fb_temp_66 Then
                    sqlite3SubselectError(arg0, local41, Cast(SQLITE_C_INT, 1ULL))
                Else
                    Return sqlite3CodeSubselect(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1))
                End If
            End If
            Goto c2fb_flow_0
            c2fb_switch_state_105 = 0
        Case 24
            ' C automatic storage declaration
            local43 = arg1->pLeft
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local43->iTable = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->withinRJSubrtn) > Cast(SQLITE_C_INT, local43->op2))))))))) Then
                c2fb_temp_67 = CPtr(SQLITE_C_INT Ptr, @(local43->iTable))
                c2fb_temp_68 = Cast(SQLITE_C_INT, sqlite3CodeSubselect(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local43)))
                (*c2fb_temp_67) = c2fb_temp_68
                c2fb_temp_69 = CPtr(u8 Ptr, @(local43->op2))
                c2fb_temp_70 = Cast(UByte, arg0->withinRJSubrtn)
                (*c2fb_temp_69) = Cast(u8, c2fb_temp_70)
                c2fb_temp_70 = Cast(UByte, (*c2fb_temp_69))
            End If
            ' C unused-parameter annotation
            c2fb_temp_71 = Cast(SQLITE_C_INT, sqlite3ExprVectorSize(CPtr(Any Ptr, local43)))
            local42 = c2fb_temp_71
            If (-Cast(SQLITE_C_INT, ((arg1->iTable <> local42)))) Then
                sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"%d columns assigned %d values"), arg1->iTable, local42)
            End If
            Return Cast(SQLITE_C_INT, (local43->iTable + Cast(SQLITE_C_INT, arg1->iColumn)))
        Case 25
            local44 = sqlite3VdbeMakeLabel(arg0)
            local45 = sqlite3VdbeMakeLabel(arg0)
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), arg2)
            sqlite3ExprCodeIN(arg0, arg1, local44, local45)
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, 1ULL), arg2)
            sqlite3VdbeResolveLabel(local0, local44)
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 88ULL), arg2, Cast(SQLITE_C_INT, &O0ULL))
            sqlite3VdbeResolveLabel(local0, local45)
            Return arg2
        Case 26
            exprCodeBetween(arg0, arg1, arg2, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL))
            Return arg2
        Case 27
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000200ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))) Then
                ' C unused-parameter annotation
                sqlite3ExprCode(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pLeft), arg2)
                sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 182ULL), arg2)
                Return arg2
            Else
                c2fb_temp_72 = arg1->pLeft
                arg1 = c2fb_temp_72
                Goto c2fb_label_0
            End If
            c2fb_switch_state_105 = 28
        Case 28
            c2fb_temp_73 = arg1->pLeft
            arg1 = c2fb_temp_73
            Goto c2fb_label_0
            c2fb_switch_state_105 = 0
        Case 29
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C unused-parameter annotation
            c2fb_temp_74 = CPtr(SqliteTable Ptr, arg1->y.pTab)
            local46 = c2fb_temp_74
            c2fb_temp_75 = Cast(SQLITE_C_INT, arg1->iColumn)
            local47 = c2fb_temp_75
            c2fb_temp_76 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (arg1->iTable * (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local46->nCol) + Cast(SQLITE_C_INT, 1ULL)))))) + Cast(SQLITE_C_INT, 1ULL))) + Cast(SQLITE_C_INT, sqlite3TableColumnToStorage(CPtr(Any Ptr, local46), local47)))))
            local48 = c2fb_temp_76
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 159ULL), local48, arg2)
            ' empty C statement
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local47 >= Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local46->aCol[local47].affinity) = Cast(SQLITE_C_INT, &H45ULL))))))))) Then
                sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 89ULL), arg2)
            End If
            Goto c2fb_flow_0
            c2fb_switch_state_105 = 0
        Case 30
            sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"row value misused"))
            Goto c2fb_flow_0
            c2fb_switch_state_105 = 0
        Case 31
            ' C automatic storage declaration
            local50 = Cast(SQLITE_C_INT, arg0->okConstFactor)
            local51 = CPtr(SqliteAggInfo Ptr, arg1->pAggInfo)
            If local51 Then
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, (local51->directMode = 0))) Then
                    c2fb_temp_77 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, ((local51)->iFirstReg + Cast(SQLITE_C_INT, (arg1->iAgg))))))
                    local2 = c2fb_temp_77
                    Goto c2fb_flow_0
                End If
                If CPtr(SqliteAggInfo Ptr, arg1->pAggInfo)->useSortingIdx Then
                    sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 96ULL), local51->sortingIdxPTab, local51->aCol[arg1->iAgg].iSorterColumn, arg2)
                    c2fb_temp_78 = Cast(SQLITE_C_INT, arg2)
                    local2 = c2fb_temp_78
                    Goto c2fb_flow_0
                End If
            End If
            c2fb_temp_79 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 20ULL), arg1->iTable, Cast(SQLITE_C_INT, &O0ULL), arg2))
            local49 = c2fb_temp_79
            c2fb_temp_80 = CPtr(u8 Ptr, @(arg0->okConstFactor))
            c2fb_temp_81 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            c2fb_temp_81 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_81) And Cast(SQLITE_C_UINT, &H1ULL)))
            (*c2fb_temp_80) = Cast(u8, (Cast(SQLITE_C_UINT, c2fb_temp_81) And Cast(SQLITE_C_UINT, &H1ULL)))
            c2fb_temp_81 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_81) And Cast(SQLITE_C_UINT, &H1ULL)))
            sqlite3ExprCode(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pLeft), arg2)
            ' C unused-parameter annotation
            c2fb_temp_82 = CPtr(u8 Ptr, @(arg0->okConstFactor))
            c2fb_temp_83 = Cast(SQLITE_C_INT, local50)
            c2fb_temp_83 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_83) And Cast(SQLITE_C_UINT, &H1ULL)))
            (*c2fb_temp_82) = Cast(u8, (Cast(SQLITE_C_UINT, c2fb_temp_83) And Cast(SQLITE_C_UINT, &H1ULL)))
            c2fb_temp_83 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_83) And Cast(SQLITE_C_UINT, &H1ULL)))
            sqlite3VdbeJumpHere(local0, local49)
            Goto c2fb_flow_0
            c2fb_switch_state_105 = 0
        Case 32
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            local60 = Cast(SQLITE_C_INT, &O0ULL)
            local61 = Cast(SQLITE_C_INT, &O0ULL)
            local62 = arg0->db
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_84 = arg1->x.pList
            local56 = c2fb_temp_84
            c2fb_temp_85 = CPtr(SqliteExprListItem Ptr, (@local56->a(0)))
            local57 = c2fb_temp_85
            c2fb_temp_86 = Cast(SQLITE_C_INT, local56->nExpr)
            local54 = c2fb_temp_86
            c2fb_temp_87 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
            local52 = c2fb_temp_87
            c2fb_temp_88 = arg1->pLeft
            local59 = c2fb_temp_88
            If (-Cast(SQLITE_C_INT, (((c2fb_temp_88) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_89 = CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local62), CPtr(Any Ptr, local59), Cast(SQLITE_C_INT, &O0ULL)))
                local61 = c2fb_temp_89
                If local62->mallocFailed Then
                    sqlite3ExprDelete(CPtr(Any Ptr, local62), CPtr(Any Ptr, local61))
                    Goto c2fb_flow_0
                End If
                ' empty C statement
                sqlite3ExprToRegister(CPtr(Any Ptr, local61), exprCodeVector(arg0, local61, CPtr(SQLITE_C_INT Ptr, @(local3))))
                ' empty C statement
                c2fb_temp_90 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, @(local58))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteExpr))))
                c2fb_temp_91 = CPtr(u8 Ptr, @(local58.op))
                c2fb_temp_92 = Cast(UByte, Cast(SQLITE_C_INT, 54ULL))
                (*c2fb_temp_91) = Cast(u8, c2fb_temp_92)
                c2fb_temp_92 = Cast(UByte, (*c2fb_temp_91))
                c2fb_temp_93 = CPtr(SqliteExpr Ptr Ptr, @(local58.pLeft))
                c2fb_temp_94 = local61
                (*c2fb_temp_93) = c2fb_temp_94
                c2fb_temp_95 = CPtr(SqliteExpr Ptr, @(local58))
                local60 = c2fb_temp_95
                c2fb_temp_96 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local3 = c2fb_temp_96
            End If
            c2fb_temp_97 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local55 = c2fb_temp_97
            While (-Cast(SQLITE_C_INT, ((local55 < Cast(SQLITE_C_INT, (local54 - Cast(SQLITE_C_INT, 1ULL)))))))
                If local59 Then
                    ' C unused-parameter annotation
                    c2fb_temp_99 = CPtr(SqliteExpr Ptr Ptr, @(local58.pRight))
                    c2fb_temp_100 = local57[local55].pExpr
                    (*c2fb_temp_99) = c2fb_temp_100
                Else
                    c2fb_temp_101 = local57[local55].pExpr
                    local60 = c2fb_temp_101
                End If
                c2fb_temp_102 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
                local53 = c2fb_temp_102
                ' empty C statement
                sqlite3ExprIfFalse(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local60), local53, Cast(SQLITE_C_INT, &H10ULL))
                ' empty C statement
                sqlite3ExprCode(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local57[Cast(SQLITE_C_INT, (local55 + Cast(SQLITE_C_INT, 1ULL)))].pExpr), arg2)
                sqlite3VdbeGoto(local0, local52)
                sqlite3VdbeResolveLabel(local0, local53)
            c2fb_flow_4:
                c2fb_temp_98 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local55 + Cast(SQLITE_C_INT, 2ULL))))
                local55 = c2fb_temp_98
            Wend
            c2fb_flow_3:
            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (local54 And Cast(SQLITE_C_INT, 1ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                sqlite3ExprCode(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local56->a(Cast(SQLITE_C_INT, (local54 - Cast(SQLITE_C_INT, 1ULL)))).pExpr), arg2)
            Else
                sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), arg2)
            End If
            sqlite3ExprDelete(CPtr(Any Ptr, local62), CPtr(Any Ptr, local61))
            setDoNotMergeFlagOnCopy(local0)
            sqlite3VdbeResolveLabel(local0, local52)
            Goto c2fb_flow_0
            c2fb_switch_state_105 = 0
        Case 33
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (arg0->pTriggerTab = 0))) AndAlso (-Cast(SQLITE_C_INT, (arg0->nested = 0))))))) Then
                sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"RAISE() may only be used within a trigger-program"))
                Return Cast(SQLITE_C_INT, &O0ULL)
            End If
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->affExpr) = Cast(SQLITE_C_INT, 2ULL))))) Then
                sqlite3MayAbort(CPtr(Any Ptr, arg0))
            End If
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->affExpr) = Cast(SQLITE_C_INT, 4ULL))))) Then
                sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 72ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, 4ULL))
                ' empty C statement
            Else
                c2fb_temp_103 = Cast(SQLITE_C_INT, sqlite3ExprCodeTemp(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pLeft), CPtr(SQLITE_C_INT Ptr, @(local3))))
                local5 = c2fb_temp_103
                sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 72ULL), IIf(arg0->pTriggerTab, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 19ULL) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 7ULL) Shl Cast(SQLITE_C_INT, 8ULL))))))), Cast(SQLITE_C_INT, 1ULL)), arg1->affExpr, local5)
            End If
            Goto c2fb_flow_0
            c2fb_switch_state_105 = 0
        End Select
    Loop
    c2fb_flow_0:
    sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local3)
    sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local4)
    Return local2
End Function

' c2fb skipped sqlite3ExprCodeRunJustOnce: FreeBASIC body already exists
' c2fb skipped sqlite3ExprNullRegisterRange: FreeBASIC body already exists
' c2fb skipped sqlite3ExprCodeTemp: FreeBASIC body already exists
' c2fb skipped sqlite3ExprCode: FreeBASIC body already exists
' c2fb skipped sqlite3ExprCodeCopy: FreeBASIC body already exists
' c2fb skipped sqlite3ExprCodeFactorable: FreeBASIC body already exists
' c2fb skipped sqlite3ExprCodeExprList: FreeBASIC body already exists
Private Sub exprCodeBetween CDecl Alias "exprCodeBetween" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As c2fb_callback_28, ByVal arg4 As SQLITE_C_INT)
    Dim local0 As SqliteExpr
    Dim local1 As SqliteExpr
    Dim local2 As SqliteExpr
    Dim local3 As SQLITE_C_INT
    Dim local4 As SqliteExpr Ptr
    Dim local5 As sqlite3 Ptr
    Dim c2fb_temp_0 As Any Ptr
    Dim c2fb_temp_1 As Any Ptr
    Dim c2fb_temp_2 As Any Ptr
    Dim c2fb_temp_3 As SqliteExpr Ptr
    Dim c2fb_temp_4 As u8 Ptr
    Dim c2fb_temp_5 As UByte
    Dim c2fb_temp_6 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_7 As SqliteExpr Ptr
    Dim c2fb_temp_8 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_9 As SqliteExpr Ptr
    Dim c2fb_temp_10 As u8 Ptr
    Dim c2fb_temp_11 As UByte
    Dim c2fb_temp_12 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_13 As SqliteExpr Ptr
    Dim c2fb_temp_14 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_15 As SqliteExpr Ptr
    Dim c2fb_temp_16 As u8 Ptr
    Dim c2fb_temp_17 As UByte
    Dim c2fb_temp_18 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_19 As SqliteExpr Ptr
    Dim c2fb_temp_20 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_21 As SqliteExpr Ptr
    Dim c2fb_temp_22 As u32 Ptr
    Dim c2fb_temp_23 As SQLITE_C_UINT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local3 = Cast(SQLITE_C_INT, &O0ULL)
    local4 = Cast(SQLITE_C_INT, &O0ULL)
    local5 = arg0->db
    c2fb_temp_0 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, @(local1))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteExpr))))
    c2fb_temp_1 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, @(local2))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteExpr))))
    c2fb_temp_2 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, @(local0))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteExpr))))
    ' C unused-parameter annotation
    c2fb_temp_3 = CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local5), CPtr(Any Ptr, arg1->pLeft), Cast(SQLITE_C_INT, &O0ULL)))
    local4 = c2fb_temp_3
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local5->mallocFailed) = Cast(SQLITE_C_INT, &O0ULL))))) Then
        c2fb_temp_4 = CPtr(u8 Ptr, @(local0.op))
        c2fb_temp_5 = Cast(UByte, Cast(SQLITE_C_INT, 44ULL))
        (*c2fb_temp_4) = Cast(u8, c2fb_temp_5)
        c2fb_temp_5 = Cast(UByte, (*c2fb_temp_4))
        c2fb_temp_6 = CPtr(SqliteExpr Ptr Ptr, @(local0.pLeft))
        c2fb_temp_7 = CPtr(SqliteExpr Ptr, @(local1))
        (*c2fb_temp_6) = c2fb_temp_7
        c2fb_temp_8 = CPtr(SqliteExpr Ptr Ptr, @(local0.pRight))
        c2fb_temp_9 = CPtr(SqliteExpr Ptr, @(local2))
        (*c2fb_temp_8) = c2fb_temp_9
        c2fb_temp_10 = CPtr(u8 Ptr, @(local1.op))
        c2fb_temp_11 = Cast(UByte, Cast(SQLITE_C_INT, 58ULL))
        (*c2fb_temp_10) = Cast(u8, c2fb_temp_11)
        c2fb_temp_11 = Cast(UByte, (*c2fb_temp_10))
        c2fb_temp_12 = CPtr(SqliteExpr Ptr Ptr, @(local1.pLeft))
        c2fb_temp_13 = local4
        (*c2fb_temp_12) = c2fb_temp_13
        c2fb_temp_14 = CPtr(SqliteExpr Ptr Ptr, @(local1.pRight))
        c2fb_temp_15 = arg1->x.pList->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr
        (*c2fb_temp_14) = c2fb_temp_15
        c2fb_temp_16 = CPtr(u8 Ptr, @(local2.op))
        c2fb_temp_17 = Cast(UByte, Cast(SQLITE_C_INT, 56ULL))
        (*c2fb_temp_16) = Cast(u8, c2fb_temp_17)
        c2fb_temp_17 = Cast(UByte, (*c2fb_temp_16))
        c2fb_temp_18 = CPtr(SqliteExpr Ptr Ptr, @(local2.pLeft))
        c2fb_temp_19 = local4
        (*c2fb_temp_18) = c2fb_temp_19
        c2fb_temp_20 = CPtr(SqliteExpr Ptr Ptr, @(local2.pRight))
        c2fb_temp_21 = arg1->x.pList->a(Cast(SQLITE_C_INT, 1ULL)).pExpr
        (*c2fb_temp_20) = c2fb_temp_21
        sqlite3ExprToRegister(CPtr(Any Ptr, local4), exprCodeVector(arg0, local4, CPtr(SQLITE_C_INT Ptr, @(local3))))
        If arg3 Then
            arg3(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, @(local0))), arg2, arg4)
        Else
            c2fb_temp_22 = CPtr(u32 Ptr, @(local4->flags))
            c2fb_temp_23 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_22)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H000001ULL)))))
            (*c2fb_temp_22) = Cast(u32, c2fb_temp_23)
            c2fb_temp_23 = Cast(SQLITE_C_UINT, (*c2fb_temp_22))
            sqlite3ExprCodeTarget(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, @(local0))), arg2)
        End If
        sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local3)
    End If
    sqlite3ExprDelete(CPtr(Any Ptr, local5), CPtr(Any Ptr, local4))
    ' empty C statement
    ' empty C statement
    ' empty C statement
    ' empty C statement
    ' empty C statement
    ' empty C statement
    ' empty C statement
    ' empty C statement
    ' empty C statement
End Sub

' c2fb skipped sqlite3ExprIfTrue: FreeBASIC body already exists
' c2fb skipped sqlite3ExprIfFalse: FreeBASIC body already exists
' c2fb skipped sqlite3ExprIfFalseDup: FreeBASIC body already exists
' c2fb skipped exprCompareVariable: outside the supported subset
' c2fb skipped sqlite3ExprCompare: FreeBASIC body already exists
' c2fb skipped sqlite3ExprListCompare: FreeBASIC body already exists
' c2fb skipped sqlite3ExprCompareSkip: FreeBASIC body already exists
' c2fb skipped exprImpliesNotNull: FreeBASIC body already exists
' c2fb skipped sqlite3ExprIsNotTrue: outside the supported subset
' c2fb skipped sqlite3ExprIsIIF: outside the supported subset
' c2fb skipped sqlite3ExprImpliesExpr: FreeBASIC body already exists
' c2fb skipped bothImplyNotNullRow: outside the supported subset
' c2fb skipped impliesNotNullRow: outside the supported subset
' c2fb skipped sqlite3ExprImpliesNonNullRow: FreeBASIC body already exists
' c2fb skipped exprIdxCover: outside the supported subset
' c2fb skipped sqlite3ExprCoveredByIndex: outside the supported subset
' c2fb skipped selectRefEnter: outside the supported subset
' c2fb skipped selectRefLeave: outside the supported subset
' c2fb skipped exprRefToSrcList: outside the supported subset
' c2fb skipped sqlite3ReferencesSrcList: FreeBASIC body already exists
' c2fb skipped agginfoPersistExprCb: outside the supported subset
' c2fb skipped sqlite3AggInfoPersistWalkerInit: FreeBASIC body already exists
' c2fb skipped addAggInfoColumn: outside the supported subset
' c2fb skipped addAggInfoFunc: outside the supported subset
' c2fb skipped findOrCreateAggInfoColumn: outside the supported subset
' c2fb skipped analyzeAggregate: outside the supported subset
' c2fb skipped sqlite3ExprAnalyzeAggregates: FreeBASIC body already exists
' c2fb skipped sqlite3ExprAnalyzeAggList: FreeBASIC body already exists
' c2fb skipped sqlite3GetTempReg: FreeBASIC body already exists
' c2fb skipped sqlite3ReleaseTempReg: FreeBASIC body already exists
' c2fb skipped sqlite3GetTempRange: FreeBASIC body already exists
' c2fb skipped sqlite3ReleaseTempRange: FreeBASIC body already exists
' c2fb skipped sqlite3ClearTempRegCache: FreeBASIC body already exists
' c2fb skipped sqlite3TouchRegister: FreeBASIC body already exists
/' end of sqlite3_bulk_expr_target.bas '/
