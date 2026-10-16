/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_bulk_insert_execution.bas

    Purpose:

        Generate INSERT operations and enforce table constraints.

    Responsibilities:

        - Select table indexes and build the INSERT source row.
        - Apply constraint, conflict, and index-transfer rules.
        - Keep translated source-local helper bodies beside their callers.

    This file intentionally does NOT contain:

        - B-tree page writes or VDBE opcode execution.
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
#include once "sqlite3_insert_helpers.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_vtab_types.bi"
#include once "sqlite3_fault.bi"
#include once "sqlite3_fkey_types.bi"
#include once "sqlite3_resolve_types.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_schema_types.bi"

#ifdef SQLITE_TEST
' The upstream TCL fixture links this counter to its sqlite3_xferopt_count
' variable so INSERT SELECT tests can confirm that the optimizer ran.
Extern sqlite3_xferopt_count Alias "sqlite3_xferopt_count" As SQLITE_C_INT
Dim Shared sqlite3_xferopt_count As SQLITE_C_INT
#endif
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

Type c2fb_callback_3 As Function CDecl(ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const ZString Ptr, ByVal arg4 As Const ZString Ptr, ByVal arg5 As Const ZString Ptr) As SQLITE_C_INT
Type c2fb_callback_8 As Sub CDecl(ByVal arg0 As Any Ptr)
Type c2fb_callback_85 As Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT

Declare Function readsTable CDecl Alias "readsTable" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteTable Ptr) As SQLITE_C_INT
Declare Sub autoIncStep CDecl Alias "autoIncStep" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT)
Declare Sub sqlite3Insert CDecl Alias "sqlite3Insert" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As SqliteSelect Ptr, ByVal arg3 As SqliteIdList Ptr, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SqliteUpsert Ptr)
Declare Function indexIteratorFirst CDecl Alias "indexIteratorFirst" (ByVal arg0 As SqliteIndexIterator Ptr, ByVal arg1 As SQLITE_C_INT Ptr) As SqliteIndex Ptr
Declare Function indexIteratorNext CDecl Alias "indexIteratorNext" (ByVal arg0 As SqliteIndexIterator Ptr, ByVal arg1 As SQLITE_C_INT Ptr) As SqliteIndex Ptr
Declare Sub sqlite3GenerateConstraintChecks CDecl Alias "sqlite3GenerateConstraintChecks" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteTable Ptr, ByVal arg2 As SQLITE_C_INT Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As SQLITE_C_INT, ByVal arg7 As UByte, ByVal arg8 As UByte, ByVal arg9 As SQLITE_C_INT, ByVal arg10 As SQLITE_C_INT Ptr, ByVal arg11 As SQLITE_C_INT Ptr, ByVal arg12 As SqliteUpsert Ptr)
Declare Function xferCompatibleIndex CDecl Alias "xferCompatibleIndex" (ByVal arg0 As SqliteIndex Ptr, ByVal arg1 As SqliteIndex Ptr) As SQLITE_C_INT
Declare Function xferCheckRowid CDecl Alias "xferCheckRowid" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function xferCompatibleCheck CDecl Alias "xferCompatibleCheck" (ByVal arg0 As SqliteTable Ptr, ByVal arg1 As SqliteTable Ptr) As SQLITE_C_INT
Declare Function xferOptimization CDecl Alias "xferOptimization" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteTable Ptr, ByVal arg2 As SqliteSelect Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT) As SQLITE_C_INT
#ifdef SQLITE_ENABLE_PREUPDATE_HOOK
Declare Sub codeWithoutRowidPreupdate CDecl Alias "codeWithoutRowidPreupdate" ( _
    ByVal arg0 As SqliteParseContext Ptr, _
    ByVal arg1 As SqliteTable Ptr, _
    ByVal arg2 As SQLITE_C_INT, _
    ByVal arg3 As SQLITE_C_INT _
)
#endif
Declare Function c2fb_crt_memset CDecl Alias "memset" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_SIZE_T) As Any Ptr
Declare Function c2fb_crt_strcmp CDecl Alias "strcmp" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT
' c2fb skipped __bswap_16: outside the supported subset
' c2fb skipped __bswap_32: outside the supported subset
' c2fb skipped __bswap_64: outside the supported subset
' c2fb skipped __uint16_identity: outside the supported subset
' c2fb skipped __uint32_identity: outside the supported subset
' c2fb skipped __uint64_identity: outside the supported subset
' c2fb skipped sqlite3IsBinary: FreeBASIC body already exists
' c2fb skipped sqlite3OpenTable: FreeBASIC body already exists
' c2fb skipped computeIndexAffStr: outside the supported subset
' c2fb skipped sqlite3IndexAffinityStr: FreeBASIC body already exists
' c2fb skipped sqlite3TableAffinityStr: FreeBASIC body already exists
' c2fb skipped sqlite3TableAffinity: FreeBASIC body already exists

/' ------------------------------------------------------------------------- '/
/' Translated INSERT and constraint procedures '/
/' ------------------------------------------------------------------------- '/
Private Function readsTable CDecl Alias "readsTable" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteTable Ptr) As SQLITE_C_INT
    Dim local0 As SqliteVdbe Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As SqliteVTable Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local4 As SqliteVdbeOp Ptr
    Dim local5 As SqliteIndex Ptr
    Dim local6 As SQLITE_C_UINT
    Dim c2fb_temp_2 As SqliteIndex Ptr
    Dim c2fb_temp_3 As SqliteIndex Ptr

    local0 = CPtr(SqliteVdbe Ptr, sqlite3GetVdbe(CPtr(Any Ptr, arg0)))
    ' C automatic storage declaration
    local2 = sqlite3VdbeCurrentAddr(local0)
    local3 = IIf(((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (arg2)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))), CPtr(SqliteVTable Ptr, sqlite3GetVTable(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, arg2))), CPtr(SqliteVTable Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
    local1 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((local1 < local2))))
        local4 = CPtr(SqliteVdbeOp Ptr, sqlite3VdbeGetOp(local0, local1))
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4->opcode) = Cast(SQLITE_C_INT, 114ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local4->p3 = arg1)))))))) Then
            ' C automatic storage declaration
            local6 = local4->p2
            If (-Cast(SQLITE_C_INT, ((local6 = arg2->tnum)))) Then
                Return Cast(SQLITE_C_INT, 1ULL)
            End If
            c2fb_temp_2 = CPtr(SqliteIndex Ptr, arg2->pIndex)
            local5 = c2fb_temp_2
            While local5
                If (-Cast(SQLITE_C_INT, ((local6 = local5->tnum)))) Then
                    Return Cast(SQLITE_C_INT, 1ULL)
                End If
            c2fb_flow_3:
                c2fb_temp_3 = local5->pNext
                local5 = c2fb_temp_3
            Wend
            c2fb_flow_2:
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4->opcode) = Cast(SQLITE_C_INT, 175ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((CPtr(SqliteVTable Ptr, local4->p4.pVtab) = local3)))))))) Then
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
    c2fb_flow_1:
        c2fb_temp_1 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    Wend
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

' c2fb skipped exprColumnFlagUnion: outside the supported subset
' c2fb skipped sqlite3ComputeGeneratedColumns: FreeBASIC body already exists
' c2fb skipped autoIncBegin: FreeBASIC body already exists
' c2fb skipped sqlite3AutoincrementBegin: FreeBASIC body already exists
Private Sub autoIncStep CDecl Alias "autoIncStep" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT)
    If (-Cast(SQLITE_C_INT, ((arg1 > Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3VdbeAddOp2(CPtr(SqliteVdbe Ptr, arg0->pVdbe), Cast(SQLITE_C_INT, 161ULL), arg1, arg2)
    End If
End Sub

' c2fb skipped autoIncrementEnd: outside the supported subset
' c2fb skipped sqlite3AutoincrementEnd: FreeBASIC body already exists
' c2fb skipped sqlite3MultiValuesEnd: FreeBASIC body already exists
' c2fb skipped exprListIsNoAffinity: outside the supported subset
' c2fb skipped sqlite3MultiValues: FreeBASIC body already exists
Sub sqlite3Insert CDecl Alias "sqlite3Insert" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As SqliteSelect Ptr, ByVal arg3 As SqliteIdList Ptr, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SqliteUpsert Ptr)
    Dim local0 As sqlite3 Ptr
    Dim local1 As SqliteTable Ptr
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim local4 As SqliteVdbe Ptr
    Dim local5 As SqliteIndex Ptr
    Dim local6 As SQLITE_C_INT
    Dim local7 As SQLITE_C_INT
    Dim local8 As SQLITE_C_INT
    Dim local9 As SQLITE_C_INT
    Dim local10 As SQLITE_C_INT
    Dim local11 As SQLITE_C_INT
    Dim local12 As SQLITE_C_INT
    Dim local13 As SQLITE_C_INT
    Dim local14 As SQLITE_C_INT
    Dim local15 As SqliteSelectDest
    Dim local16 As SQLITE_C_INT
    Dim local17 As UByte
    Dim local18 As UByte
    Dim local19 As UByte
    Dim local20 As UByte
    Dim local21 As SqliteExprList Ptr
    Dim local22 As SQLITE_C_INT
    Dim local23 As SQLITE_C_INT
    Dim local24 As SQLITE_C_INT
    Dim local25 As SQLITE_C_INT
    Dim local26 As SQLITE_C_INT
    Dim local27 As SQLITE_C_INT
    Dim local28 As SQLITE_C_INT
    Dim local29 As SQLITE_C_INT Ptr
    Dim local30 As SQLITE_C_INT Ptr
    Dim local31 As SQLITE_C_INT
    Dim local32 As SqliteTrigger Ptr
    Dim local33 As SQLITE_C_INT
    Dim c2fb_temp_0 As sqlite3 Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SqliteExprList Ptr
    Dim c2fb_temp_4 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_5 As SqliteExprList Ptr
    Dim c2fb_temp_6 As SqliteSelect Ptr
    Dim c2fb_temp_7 As SqliteTable Ptr
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As UByte
    Dim c2fb_temp_10 As SqliteTrigger Ptr
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SqliteVdbe Ptr
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SQLITE_C_INT Ptr
    Dim c2fb_temp_17 As SQLITE_C_INT
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As SQLITE_C_INT Ptr
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As SQLITE_C_INT
    Dim c2fb_temp_22 As UByte
    Dim c2fb_temp_23 As SQLITE_C_INT Ptr
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As SQLITE_C_INT
    Dim c2fb_temp_26 As SQLITE_C_INT
    Dim c2fb_temp_27 As SQLITE_C_INT Ptr
    Dim c2fb_temp_28 As SQLITE_C_INT
    Dim c2fb_temp_29 As UByte
    Dim c2fb_temp_30 As SQLITE_C_INT
    Dim c2fb_temp_31 As SQLITE_C_INT
    Dim c2fb_temp_32 As UByte
    Dim c2fb_temp_33 As u8 Ptr
    Dim c2fb_temp_34 As SQLITE_C_INT
    Dim local34 As SQLITE_C_INT
    Dim local35 As SqliteSrcItem Ptr
    Dim local36 As SqliteSubquery Ptr
    Dim c2fb_temp_35 As SqliteSubquery Ptr
    Dim c2fb_temp_36 As SQLITE_C_INT Ptr
    Dim c2fb_temp_37 As SQLITE_C_INT
    Dim c2fb_temp_38 As SQLITE_C_INT
    Dim c2fb_temp_39 As SQLITE_C_INT
    Dim c2fb_temp_40 As SQLITE_C_INT
    Dim c2fb_temp_41 As SQLITE_C_INT
    Dim c2fb_temp_42 As SQLITE_C_INT
    Dim local37 As SQLITE_C_INT
    Dim c2fb_temp_43 As SQLITE_C_INT Ptr
    Dim c2fb_temp_44 As SQLITE_C_INT
    Dim c2fb_temp_45 As SQLITE_C_INT
    Dim local38 As SQLITE_C_INT
    Dim c2fb_temp_46 As SQLITE_C_INT
    Dim c2fb_temp_47 As SQLITE_C_INT Ptr
    Dim c2fb_temp_48 As SQLITE_C_INT
    Dim c2fb_temp_49 As SQLITE_C_INT Ptr
    Dim c2fb_temp_50 As SQLITE_C_INT
    Dim transferOptimizationUsed As SQLITE_C_INT
    Dim c2fb_temp_51 As SQLITE_C_INT
    Dim c2fb_temp_52 As SQLITE_C_INT
    Dim c2fb_temp_53 As SQLITE_C_INT
    Dim c2fb_temp_54 As UByte
    Dim local39 As SQLITE_C_INT
    Dim local40 As SQLITE_C_INT
    Dim local41 As SQLITE_C_INT
    Dim c2fb_temp_55 As SQLITE_C_INT Ptr
    Dim c2fb_temp_56 As SQLITE_C_INT
    Dim c2fb_temp_57 As SQLITE_C_INT
    Dim c2fb_temp_58 As SQLITE_C_INT
    Dim c2fb_temp_59 As SQLITE_C_INT
    Dim c2fb_temp_60 As SQLITE_C_INT
    Dim local42 As SqliteNameContext
    Dim c2fb_temp_61 As Any Ptr
    Dim c2fb_temp_62 As SqliteParseContext Ptr Ptr
    Dim c2fb_temp_63 As SqliteParseContext Ptr
    Dim c2fb_temp_64 As SQLITE_C_INT
    Dim c2fb_temp_65 As SQLITE_C_INT
    Dim c2fb_temp_66 As SQLITE_C_INT
    Dim c2fb_temp_67 As SQLITE_C_INT
    Dim c2fb_temp_68 As SQLITE_C_INT
    Dim c2fb_temp_69 As SQLITE_C_INT
    Dim c2fb_temp_70 As SQLITE_C_INT
    Dim c2fb_temp_71 As SQLITE_C_INT
    Dim c2fb_temp_72 As SQLITE_C_INT
    Dim c2fb_temp_73 As SQLITE_C_INT
    Dim c2fb_temp_74 As SQLITE_C_INT Ptr
    Dim c2fb_temp_75 As SQLITE_C_INT
    Dim c2fb_temp_76 As SQLITE_C_INT
    Dim c2fb_temp_77 As SQLITE_C_INT
    Dim local43 As SQLITE_C_INT
    Dim c2fb_temp_78 As SQLITE_C_INT
    Dim c2fb_temp_79 As SQLITE_C_INT Ptr
    Dim c2fb_temp_80 As SQLITE_C_INT
    Dim c2fb_temp_81 As SqliteIndex Ptr
    Dim c2fb_temp_82 As SqliteIndex Ptr
    Dim c2fb_temp_83 As SQLITE_C_INT
    Dim c2fb_temp_84 As SQLITE_C_INT Ptr
    Dim c2fb_temp_85 As SQLITE_C_INT
    Dim c2fb_temp_86 As SQLITE_C_INT
    Dim c2fb_temp_87 As SQLITE_C_INT Ptr
    Dim c2fb_temp_88 As SQLITE_C_INT
    Dim c2fb_temp_89 As SQLITE_C_INT Ptr
    Dim c2fb_temp_90 As SQLITE_C_INT
    Dim c2fb_temp_91 As SQLITE_C_INT Ptr
    Dim c2fb_temp_92 As SQLITE_C_INT
    Dim c2fb_temp_93 As SQLITE_C_INT
    Dim c2fb_temp_94 As SQLITE_C_INT Ptr
    Dim c2fb_temp_95 As SQLITE_C_INT
    Dim local44 As SqliteUpsert Ptr
    Dim c2fb_temp_96 As SQLITE_C_INT Ptr
    Dim c2fb_temp_97 As SQLITE_C_INT
    Dim c2fb_temp_98 As SqliteUpsert Ptr
    Dim c2fb_temp_99 As Any Ptr Ptr
    Dim c2fb_temp_100 As SqliteSrcList Ptr
    Dim c2fb_temp_101 As SQLITE_C_INT Ptr
    Dim c2fb_temp_102 As SQLITE_C_INT
    Dim c2fb_temp_103 As SQLITE_C_INT Ptr
    Dim c2fb_temp_104 As SQLITE_C_INT
    Dim c2fb_temp_105 As SQLITE_C_INT Ptr
    Dim c2fb_temp_106 As SQLITE_C_INT
    Dim c2fb_temp_107 As SqliteUpsert Ptr
    Dim c2fb_temp_108 As SQLITE_C_INT
    Dim c2fb_temp_109 As SQLITE_C_INT
    Dim c2fb_temp_110 As SQLITE_C_INT
    Dim c2fb_temp_111 As SQLITE_C_INT
    Dim c2fb_temp_112 As SQLITE_C_INT
    Dim c2fb_temp_113 As SQLITE_C_INT
    Dim c2fb_temp_114 As SQLITE_C_INT
    Dim c2fb_temp_115 As SQLITE_C_INT
    Dim c2fb_temp_116 As SQLITE_C_INT
    Dim local45 As SQLITE_C_INT
    Dim local46 As SQLITE_C_UINT
    Dim c2fb_temp_117 As SQLITE_C_UINT
    Dim c2fb_temp_118 As SQLITE_C_INT
    Dim c2fb_temp_119 As SQLITE_C_INT
    Dim c2fb_temp_120 As SQLITE_C_INT
    Dim c2fb_temp_121 As SQLITE_C_INT
    Dim c2fb_temp_122 As SQLITE_C_INT
    Dim local47 As SqliteExpr Ptr
    Dim local48 As SQLITE_C_INT
    Dim c2fb_temp_123 As SQLITE_C_INT
    Dim local49 As SQLITE_C_INT
    Dim local50 As SQLITE_C_INT
    Dim c2fb_temp_124 As SQLITE_C_INT
    Dim local51 As SqliteExpr Ptr
    Dim c2fb_temp_125 As UByte
    Dim local52 As SQLITE_C_INT
    Dim c2fb_temp_126 As SQLITE_C_INT
    Dim c2fb_temp_127 As SQLITE_C_INT
    Dim c2fb_temp_128 As UByte
    Dim local53 As Const ZString Ptr
    Dim local54 As SQLITE_C_INT
    Dim local55 As SQLITE_C_INT
    Dim c2fb_temp_129 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local7 = Cast(SQLITE_C_INT, &O0ULL)
    local8 = Cast(SQLITE_C_INT, &O0ULL)
    local9 = Cast(SQLITE_C_INT, &O0ULL)
    local10 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))
    ' C automatic storage declaration
    local12 = Cast(SQLITE_C_INT, &O0ULL)
    local13 = Cast(SQLITE_C_INT, &O0ULL)
    local14 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    local17 = Cast(SQLITE_C_INT, &O0ULL)
    local18 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    local21 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    local23 = Cast(SQLITE_C_INT, &O0ULL)
    local24 = Cast(SQLITE_C_INT, &O0ULL)
    local25 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local29 = Cast(SQLITE_C_INT, &O0ULL)
    local30 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    c2fb_temp_0 = arg0->db
    local0 = c2fb_temp_0
    ' C unused-parameter annotation
    If arg0->nErr Then
        Goto c2fb_label_0
    End If
    ' C unused-parameter annotation
    c2fb_temp_1 = CPtr(SQLITE_C_INT Ptr, @(local15.iSDParm))
    c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_1) = c2fb_temp_2
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg2 AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg2->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000200ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, ((arg2->pPrior = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        c2fb_temp_3 = arg2->pEList
        local21 = c2fb_temp_3
        c2fb_temp_4 = CPtr(SqliteExprList Ptr Ptr, @(arg2->pEList))
        c2fb_temp_5 = CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_4) = c2fb_temp_5
        sqlite3SelectDelete(CPtr(Any Ptr, local0), CPtr(Any Ptr, arg2))
        c2fb_temp_6 = CPtr(SqliteSelect Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        arg2 = c2fb_temp_6
    End If
    ' C unused-parameter annotation
    c2fb_temp_7 = CPtr(SqliteTable Ptr, sqlite3SrcListLookup(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1)))
    local1 = c2fb_temp_7
    If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Goto c2fb_label_0
    End If
    c2fb_temp_8 = Cast(SQLITE_C_INT, sqlite3SchemaToIndex(CPtr(Any Ptr, local0), CPtr(Any Ptr, CPtr(SqliteSchema Ptr, local1->pSchema))))
    local16 = c2fb_temp_8
    ' C unused-parameter annotation
    If sqlite3AuthCheck(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 18ULL), CPtr(Const ZString Ptr, local1->zName), Cast(SQLITE_C_INT, &O0ULL), CPtr(Const ZString Ptr, CPtr(ZString Ptr, local0->aDb(local16).zDbSName))) Then
        Goto c2fb_label_0
    End If
    c2fb_temp_9 = Cast(UByte, (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local1)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))))
    local19 = c2fb_temp_9
    c2fb_temp_10 = CPtr(SqliteTrigger Ptr, sqlite3TriggersExist(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local1), Cast(SQLITE_C_INT, 128ULL), Cast(SQLITE_C_INT, &O0ULL), CPtr(SQLITE_C_INT Ptr, @(local33))))
    local32 = c2fb_temp_10
    c2fb_temp_11 = Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local1)->eTabType) = Cast(SQLITE_C_INT, 2ULL)))))))
    local31 = c2fb_temp_11
    ' C unused-parameter annotation
    If sqlite3ViewGetColumnNames(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local1)) Then
        Goto c2fb_label_0
    End If
    If sqlite3IsReadOnly(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local1), CPtr(Any Ptr, local32)) Then
        Goto c2fb_label_0
    End If
    c2fb_temp_12 = CPtr(SqliteVdbe Ptr, sqlite3GetVdbe(CPtr(Any Ptr, arg0)))
    local4 = c2fb_temp_12
    If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Goto c2fb_label_0
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->nested) = Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3VdbeCountChanges(local4)
    End If
    sqlite3BeginWriteOperation(CPtr(Any Ptr, arg0), (-Cast(SQLITE_C_INT, ((arg2 OrElse local32)))), local16)
    transferOptimizationUsed = 0
    If arg3 = 0 AndAlso arg2 <> 0 AndAlso local32 = 0 Then _
        transferOptimizationUsed = xferOptimization(arg0, local1, arg2, arg4, local16)
    If transferOptimizationUsed <> 0 Then
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        Goto c2fb_label_1
    End If
    c2fb_temp_13 = Cast(SQLITE_C_INT, autoIncBegin(arg0, local16, local1))
    local24 = c2fb_temp_13
    c2fb_temp_14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg0->nMem + Cast(SQLITE_C_INT, 1ULL))))
    local26 = c2fb_temp_14
    c2fb_temp_15 = Cast(SQLITE_C_INT, c2fb_temp_14)
    local27 = c2fb_temp_15
    c2fb_temp_16 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
    c2fb_temp_17 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_16) + Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->nCol) + Cast(SQLITE_C_INT, 1ULL))))))
    (*c2fb_temp_16) = c2fb_temp_17
    If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local1)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))) Then
        c2fb_temp_18 = local27
        local27 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_18 + 1)))
        c2fb_temp_19 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
        c2fb_temp_20 = (*c2fb_temp_19)
        (*c2fb_temp_19) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_20 + 1)))
    End If
    c2fb_temp_21 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local27 + Cast(SQLITE_C_INT, 1ULL))))
    local28 = c2fb_temp_21
    c2fb_temp_22 = Cast(UByte, (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local1->tabFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000400ULL) Or Cast(SQLITE_C_INT, &H00000040ULL)))))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))
    local20 = c2fb_temp_22
    If arg3 Then
        c2fb_temp_23 = CPtr(SQLITE_C_INT Ptr, CPtr(Any Ptr, sqlite3DbMallocZero(CPtr(Any Ptr, local0), Cast(sqlite3_uint64, (Cast(sqlite3_uint64, local1->nCol) * Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SQLITE_C_INT))))))))
        local30 = c2fb_temp_23
        If (-Cast(SQLITE_C_INT, ((local30 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_label_0
        End If
        c2fb_temp_24 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local2 = c2fb_temp_24
        While (-Cast(SQLITE_C_INT, ((local2 < arg3->nId))))
            c2fb_temp_26 = Cast(SQLITE_C_INT, sqlite3ColumnIndex(CPtr(Any Ptr, local1), CPtr(Const ZString Ptr, arg3->a(local2).zName)))
            local3 = c2fb_temp_26
            If (-Cast(SQLITE_C_INT, ((local3 >= Cast(SQLITE_C_INT, &O0ULL))))) Then
                If (-Cast(SQLITE_C_INT, ((local30[local3] = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_27 = CPtr(SQLITE_C_INT Ptr, @(local30[local3]))
                    c2fb_temp_28 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local2 + Cast(SQLITE_C_INT, 1ULL))))
                    (*c2fb_temp_27) = c2fb_temp_28
                End If
                If (-Cast(SQLITE_C_INT, ((local2 <> local3)))) Then
                    c2fb_temp_29 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                    local20 = c2fb_temp_29
                End If
                If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, local1->iPKey))))) Then
                    c2fb_temp_30 = Cast(SQLITE_C_INT, local2)
                    local10 = c2fb_temp_30
                    ' C unused-parameter annotation
                End If
                If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->aCol[local3].colFlags) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0040ULL) Or Cast(SQLITE_C_INT, &H0020ULL)))))) Then
                    sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"cannot INSERT into generated column \034%s\034"), local1->aCol[local3].zCnName)
                    Goto c2fb_label_0
                End If
            Else
                If (-Cast(SQLITE_C_INT, ((sqlite3IsRowid(CPtr(Const ZString Ptr, arg3->a(local2).zName)) AndAlso (-Cast(SQLITE_C_INT, (local19 = 0))))))) Then
                    c2fb_temp_31 = Cast(SQLITE_C_INT, local2)
                    local10 = c2fb_temp_31
                    c2fb_temp_32 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                    local20 = c2fb_temp_32
                Else
                    sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"table %S has no column named %s"), CPtr(SqliteSrcItem Ptr, (@arg1->a(0))), arg3->a(local2).zName)
                    c2fb_temp_33 = CPtr(u8 Ptr, @(arg0->checkSchema))
                    c2fb_temp_34 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                    c2fb_temp_34 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_34) And Cast(SQLITE_C_UINT, &H1ULL)))
                    (*c2fb_temp_33) = Cast(u8, (Cast(SQLITE_C_UINT, c2fb_temp_34) And Cast(SQLITE_C_UINT, &H1ULL)))
                    c2fb_temp_34 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_34) And Cast(SQLITE_C_UINT, &H1ULL)))
                    Goto c2fb_label_0
                End If
            End If
        c2fb_flow_1:
            c2fb_temp_25 = local2
            local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_25 + 1)))
        Wend
        c2fb_flow_0:
    End If
    If arg2 Then
        ' C automatic storage declaration
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg2->pSrc->nSrc = Cast(SQLITE_C_INT, 1ULL))))) AndAlso Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg2->pSrc->a(Cast(SQLITE_C_INT, &O0ULL)).fg.flags) Shr 6) And Cast(SQLITE_C_UINT, &H1ULL))))))) AndAlso (-Cast(SQLITE_C_INT, ((arg2->pPrior = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            local35 = CPtr(SqliteSrcItem Ptr, @(arg2->pSrc->a(Cast(SQLITE_C_INT, &O0ULL))))
            ' C automatic storage declaration
            ' C unused-parameter annotation
            c2fb_temp_35 = local35->u4.pSubq
            local36 = c2fb_temp_35
            c2fb_temp_36 = CPtr(SQLITE_C_INT Ptr, @(local15.iSDParm))
            c2fb_temp_37 = Cast(SQLITE_C_INT, local36->regReturn)
            (*c2fb_temp_36) = c2fb_temp_37
            c2fb_temp_38 = Cast(SQLITE_C_INT, local36->regResult)
            local23 = c2fb_temp_38
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_39 = Cast(SQLITE_C_INT, local36->pSelect->pEList->nExpr)
            local6 = c2fb_temp_39
            sqlite3VdbeExplainString(arg0, Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"SCAN %S"), CPtr(Const ZString Ptr, local35))
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local20) AndAlso (-Cast(SQLITE_C_INT, ((local6 = Cast(SQLITE_C_INT, local1->nCol))))))))) Then
                c2fb_temp_40 = Cast(SQLITE_C_INT, local23)
                local28 = c2fb_temp_40
                c2fb_temp_41 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local28 - Cast(SQLITE_C_INT, 1ULL))))
                local27 = c2fb_temp_41
                c2fb_temp_42 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local27 - (IIf(((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local1)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))), Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, &O0ULL))))))
                local26 = c2fb_temp_42
            End If
        Else
            ' C automatic storage declaration
            c2fb_temp_43 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
            c2fb_temp_44 = (*c2fb_temp_43)
            (*c2fb_temp_43) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_44 + 1)))
            c2fb_temp_45 = (*c2fb_temp_43)
            local38 = c2fb_temp_45
            c2fb_temp_46 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (sqlite3VdbeCurrentAddr(local4) + Cast(SQLITE_C_INT, 1ULL))))
            local37 = c2fb_temp_46
            sqlite3VdbeAddOp3(local4, Cast(SQLITE_C_INT, 11ULL), local38, Cast(SQLITE_C_INT, &O0ULL), local37)
            sqlite3SelectDestInit(CPtr(Any Ptr, CPtr(SqliteSelectDest Ptr, @(local15))), Cast(SQLITE_C_INT, 11ULL), local38)
            c2fb_temp_47 = CPtr(SQLITE_C_INT Ptr, @(local15.iSdst))
            c2fb_temp_48 = Cast(SQLITE_C_INT, IIf(local20, local28, Cast(SQLITE_C_INT, &O0ULL)))
            (*c2fb_temp_47) = c2fb_temp_48
            c2fb_temp_49 = CPtr(SQLITE_C_INT Ptr, @(local15.nSdst))
            c2fb_temp_50 = Cast(SQLITE_C_INT, local1->nCol)
            (*c2fb_temp_49) = c2fb_temp_50
            c2fb_temp_51 = Cast(SQLITE_C_INT, sqlite3Select(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg2), CPtr(Any Ptr, CPtr(SqliteSelectDest Ptr, @(local15)))))
            local34 = c2fb_temp_51
            c2fb_temp_52 = Cast(SQLITE_C_INT, local15.iSdst)
            local23 = c2fb_temp_52
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, ((local34 OrElse arg0->nErr)))) Then
                Goto c2fb_label_0
            End If
            ' C unused-parameter annotation
            sqlite3VdbeEndCoroutine(local4, local38)
            sqlite3VdbeJumpHere(local4, Cast(SQLITE_C_INT, (local37 - Cast(SQLITE_C_INT, 1ULL))))
            ' C unused-parameter annotation
            c2fb_temp_53 = Cast(SQLITE_C_INT, arg2->pEList->nExpr)
            local6 = c2fb_temp_53
        End If
        If (-Cast(SQLITE_C_INT, ((local32 OrElse readsTable(arg0, local16, local1))))) Then
            c2fb_temp_54 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
            local17 = c2fb_temp_54
        End If
        If local17 Then
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            c2fb_temp_55 = CPtr(SQLITE_C_INT Ptr, @(arg0->nTab))
            c2fb_temp_56 = (*c2fb_temp_55)
            (*c2fb_temp_55) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_56 + 1)))
            c2fb_temp_57 = Cast(SQLITE_C_INT, c2fb_temp_56)
            local12 = c2fb_temp_57
            c2fb_temp_58 = Cast(SQLITE_C_INT, sqlite3GetTempReg(CPtr(Any Ptr, arg0)))
            local39 = c2fb_temp_58
            c2fb_temp_59 = Cast(SQLITE_C_INT, sqlite3GetTempReg(CPtr(Any Ptr, arg0)))
            local40 = c2fb_temp_59
            sqlite3VdbeAddOp2(local4, Cast(SQLITE_C_INT, 120ULL), local12, local6)
            c2fb_temp_60 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(local4, Cast(SQLITE_C_INT, 12ULL), local15.iSDParm))
            local41 = c2fb_temp_60
            ' empty C statement
            sqlite3VdbeAddOp3(local4, Cast(SQLITE_C_INT, 99ULL), local23, local6, local39)
            sqlite3VdbeAddOp2(local4, Cast(SQLITE_C_INT, 129ULL), local12, local40)
            sqlite3VdbeAddOp3(local4, Cast(SQLITE_C_INT, 130ULL), local12, local39, local40)
            sqlite3VdbeGoto(local4, local41)
            sqlite3VdbeJumpHere(local4, local41)
            sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local39)
            sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local40)
        End If
    Else
        ' C automatic storage declaration
        c2fb_temp_61 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local42))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteNameContext))))
        c2fb_temp_62 = CPtr(SqliteParseContext Ptr Ptr, @(local42.pParse))
        c2fb_temp_63 = arg0
        (*c2fb_temp_62) = c2fb_temp_63
        c2fb_temp_64 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
        local12 = c2fb_temp_64
        ' C unused-parameter annotation
        If local21 Then
            c2fb_temp_65 = Cast(SQLITE_C_INT, local21->nExpr)
            local6 = c2fb_temp_65
            If sqlite3ResolveExprListNames(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local42))), CPtr(Any Ptr, local21)) Then
                Goto c2fb_label_0
            End If
        Else
            c2fb_temp_66 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local6 = c2fb_temp_66
        End If
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg3 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local6 > Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        c2fb_temp_67 = Cast(SQLITE_C_INT, local1->iPKey)
        local10 = c2fb_temp_67
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local10 >= Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local1->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000060ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
            ' empty C statement
            ' empty C statement
            c2fb_temp_68 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local10 - Cast(SQLITE_C_INT, 1ULL))))
            local2 = c2fb_temp_68
            While (-Cast(SQLITE_C_INT, ((local2 >= Cast(SQLITE_C_INT, &O0ULL)))))
                If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->aCol[local2].colFlags) And Cast(SQLITE_C_INT, &H0060ULL))) Then
                    ' empty C statement
                    ' empty C statement
                    c2fb_temp_70 = local10
                    local10 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_70 - 1)))
                End If
            c2fb_flow_3:
                c2fb_temp_69 = local2
                local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_69 - 1)))
            Wend
            c2fb_flow_2:
        End If
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local1->tabFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000060ULL) Or Cast(SQLITE_C_INT, &H00000002ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            c2fb_temp_71 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local2 = c2fb_temp_71
            While (-Cast(SQLITE_C_INT, ((local2 < Cast(SQLITE_C_INT, local1->nCol)))))
                If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->aCol[local2].colFlags) And Cast(SQLITE_C_INT, &H0062ULL))) Then
                    c2fb_temp_73 = local7
                    local7 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_73 + 1)))
                End If
            c2fb_flow_5:
                c2fb_temp_72 = local2
                local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_72 + 1)))
            Wend
            c2fb_flow_4:
        End If
        If (-Cast(SQLITE_C_INT, ((local6 <> (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->nCol) - local7))))))) Then
            sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"table %S has %d columns but %d values were supplied"), CPtr(SqliteSrcItem Ptr, (@arg1->a(0))), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->nCol) - local7)), local6)
            Goto c2fb_label_0
        End If
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg3 <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local6 <> arg3->nId)))))))) Then
        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"%d values for %d columns"), local6, arg3->nId)
        Goto c2fb_label_0
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local0->flags And (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, (Cast(SQLITE_C_INT, &H00001ULL))) Shl Cast(SQLITE_C_INT, 32ULL))))))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, (arg0->nested = 0))))))) AndAlso (-Cast(SQLITE_C_INT, (arg0->pTriggerTab = 0))))))) AndAlso (-Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->bReturning) = 0))))))) Then
        c2fb_temp_74 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
        c2fb_temp_75 = (*c2fb_temp_74)
        (*c2fb_temp_74) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_75 + 1)))
        c2fb_temp_76 = (*c2fb_temp_74)
        c2fb_temp_77 = Cast(SQLITE_C_INT, c2fb_temp_76)
        local25 = c2fb_temp_77
        sqlite3VdbeAddOp2(local4, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, &O0ULL), local25)
    End If
    If (-Cast(SQLITE_C_INT, (local31 = 0))) Then
        ' C automatic storage declaration
        c2fb_temp_78 = Cast(SQLITE_C_INT, sqlite3OpenTableAndIndices(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local1), Cast(SQLITE_C_INT, 116ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, &O0ULL), CPtr(SQLITE_C_INT Ptr, @(local8)), CPtr(SQLITE_C_INT Ptr, @(local9))))
        local43 = c2fb_temp_78
        c2fb_temp_79 = CPtr(SQLITE_C_INT Ptr, CPtr(Any Ptr, sqlite3DbMallocRawNN(CPtr(Any Ptr, local0), Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SQLITE_C_INT))) * Cast(sqlite3_uint64, (Cast(SQLITE_C_INT, (local43 + Cast(SQLITE_C_INT, 2ULL))))))))))
        local29 = c2fb_temp_79
        If (-Cast(SQLITE_C_INT, ((local29 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_label_0
        End If
        c2fb_temp_80 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local2 = c2fb_temp_80
        c2fb_temp_81 = CPtr(SqliteIndex Ptr, local1->pIndex)
        local5 = c2fb_temp_81
        While (-Cast(SQLITE_C_INT, ((local2 < local43))))
            ' C unused-parameter annotation
            c2fb_temp_87 = CPtr(SQLITE_C_INT Ptr, @(local29[local2]))
            c2fb_temp_84 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
            c2fb_temp_85 = (*c2fb_temp_84)
            (*c2fb_temp_84) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_85 + 1)))
            c2fb_temp_86 = (*c2fb_temp_84)
            c2fb_temp_88 = Cast(SQLITE_C_INT, c2fb_temp_86)
            (*c2fb_temp_87) = c2fb_temp_88
            c2fb_temp_89 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
            c2fb_temp_90 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_89) + Cast(SQLITE_C_INT, local5->nColumn))))
            (*c2fb_temp_89) = c2fb_temp_90
        c2fb_flow_7:
            c2fb_temp_82 = local5->pNext
            local5 = c2fb_temp_82
            c2fb_temp_83 = local2
            local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_83 + 1)))
        Wend
        c2fb_flow_6:
        c2fb_temp_94 = CPtr(SQLITE_C_INT Ptr, @(local29[local2]))
        c2fb_temp_91 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
        c2fb_temp_92 = (*c2fb_temp_91)
        (*c2fb_temp_91) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_92 + 1)))
        c2fb_temp_93 = (*c2fb_temp_91)
        c2fb_temp_95 = Cast(SQLITE_C_INT, c2fb_temp_93)
        (*c2fb_temp_94) = c2fb_temp_95
    End If
    If arg5 Then
        ' C automatic storage declaration
        If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local1)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))) Then
            sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"UPSERT not implemented for virtual table \034%s\034"), local1->zName)
            Goto c2fb_label_0
        End If
        If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local1)->eTabType) = Cast(SQLITE_C_INT, 2ULL)))))) Then
            sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"cannot UPSERT a view"))
            Goto c2fb_label_0
        End If
        If sqlite3HasExplicitNulls(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, arg5->pUpsertTarget))) Then
            Goto c2fb_label_0
        End If
        c2fb_temp_96 = CPtr(SQLITE_C_INT Ptr, @(arg1->a(Cast(SQLITE_C_INT, &O0ULL)).iCursor))
        c2fb_temp_97 = Cast(SQLITE_C_INT, local8)
        (*c2fb_temp_96) = c2fb_temp_97
        c2fb_temp_98 = arg5
        local44 = c2fb_temp_98
        Do
            c2fb_temp_99 = CPtr(Any Ptr Ptr, @(local44->pUpsertSrc))
            c2fb_temp_100 = arg1
            (*c2fb_temp_99) = CPtr(Any Ptr, c2fb_temp_100)
            c2fb_temp_100 = CPtr(SqliteSrcList Ptr, (*c2fb_temp_99))
            c2fb_temp_101 = CPtr(SQLITE_C_INT Ptr, @(local44->regData))
            c2fb_temp_102 = Cast(SQLITE_C_INT, local28)
            (*c2fb_temp_101) = c2fb_temp_102
            c2fb_temp_103 = CPtr(SQLITE_C_INT Ptr, @(local44->iDataCur))
            c2fb_temp_104 = Cast(SQLITE_C_INT, local8)
            (*c2fb_temp_103) = c2fb_temp_104
            c2fb_temp_105 = CPtr(SQLITE_C_INT Ptr, @(local44->iIdxCur))
            c2fb_temp_106 = Cast(SQLITE_C_INT, local9)
            (*c2fb_temp_105) = c2fb_temp_106
            If CPtr(SqliteExprList Ptr, local44->pUpsertTarget) Then
                If sqlite3UpsertAnalyzeTarget(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), CPtr(Any Ptr, local44), CPtr(Any Ptr, arg5)) Then
                    Goto c2fb_label_0
                End If
            End If
            c2fb_temp_107 = local44->pNextUpsert
            local44 = c2fb_temp_107
        c2fb_flow_9:
        Loop While (-Cast(SQLITE_C_INT, ((local44 <> Cast(SQLITE_C_INT, &O0ULL)))))
        c2fb_flow_8:
    End If
    If local17 Then
        c2fb_temp_108 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(local4, Cast(SQLITE_C_INT, 36ULL), local12))
        local13 = c2fb_temp_108
        ' empty C statement
        c2fb_temp_109 = Cast(SQLITE_C_INT, sqlite3VdbeCurrentAddr(local4))
        local14 = c2fb_temp_109
    Else
        If arg2 Then
            ' empty C statement
            c2fb_temp_110 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(local4, Cast(SQLITE_C_INT, 12ULL), local15.iSDParm))
            local14 = c2fb_temp_110
            c2fb_temp_111 = Cast(SQLITE_C_INT, c2fb_temp_110)
            local13 = c2fb_temp_111
            ' empty C statement
            If (-Cast(SQLITE_C_INT, ((local10 >= Cast(SQLITE_C_INT, &O0ULL))))) Then
                sqlite3VdbeAddOp2(local4, Cast(SQLITE_C_INT, 82ULL), Cast(SQLITE_C_INT, (local23 + local10)), local27)
            End If
        End If
    End If
    c2fb_temp_112 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local7 = c2fb_temp_112
    c2fb_temp_113 = Cast(SQLITE_C_INT, local28)
    local22 = c2fb_temp_113
    ' C unused-parameter annotation
    c2fb_temp_114 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local2 = c2fb_temp_114
    While (-Cast(SQLITE_C_INT, ((local2 < Cast(SQLITE_C_INT, local1->nCol)))))
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, local1->iPKey))))) Then
            sqlite3VdbeAddOp1(local4, Cast(SQLITE_C_INT, 78ULL), local22)
            Goto c2fb_flow_11
        End If
        c2fb_temp_117 = Cast(SQLITE_C_UINT, local1->aCol[local2].colFlags)
        local46 = c2fb_temp_117
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((c2fb_temp_117) And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0062ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            c2fb_temp_118 = local7
            local7 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_118 + 1)))
            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local46 And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0020ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                c2fb_temp_119 = local22
                local22 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_119 - 1)))
                Goto c2fb_flow_11
            Else
                If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local46 And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0040ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                    If Cast(SQLITE_C_INT, (local33 And Cast(SQLITE_C_INT, 1ULL))) Then
                        sqlite3VdbeAddOp1(local4, Cast(SQLITE_C_INT, 78ULL), local22)
                    End If
                    Goto c2fb_flow_11
                Else
                    If (-Cast(SQLITE_C_INT, ((arg3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        sqlite3ExprCodeFactorable(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, sqlite3ColumnExprAuth(CPtr(Any Ptr, local1), CPtr(Any Ptr, CPtr(SqliteColumn Ptr, @(local1->aCol[local2]))), CPtr(Any Ptr, arg0)))), local22)
                        Goto c2fb_flow_11
                    End If
                End If
            End If
        End If
        If arg3 Then
            c2fb_temp_120 = Cast(SQLITE_C_INT, local30[local2])
            local3 = c2fb_temp_120
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                sqlite3ExprCodeFactorable(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, sqlite3ColumnExprAuth(CPtr(Any Ptr, local1), CPtr(Any Ptr, CPtr(SqliteColumn Ptr, @(local1->aCol[local2]))), CPtr(Any Ptr, arg0)))), local22)
                Goto c2fb_flow_11
            End If
            c2fb_temp_121 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local3 - Cast(SQLITE_C_INT, 1ULL))))
            local45 = c2fb_temp_121
        Else
            If (-Cast(SQLITE_C_INT, ((local6 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                sqlite3ExprCodeFactorable(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, sqlite3ColumnExprAuth(CPtr(Any Ptr, local1), CPtr(Any Ptr, CPtr(SqliteColumn Ptr, @(local1->aCol[local2]))), CPtr(Any Ptr, arg0)))), local22)
                Goto c2fb_flow_11
            Else
                c2fb_temp_122 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local2 - local7)))
                local45 = c2fb_temp_122
            End If
        End If
        If local17 Then
            sqlite3VdbeAddOp3(local4, Cast(SQLITE_C_INT, 96ULL), local12, local45, local22)
        Else
            If arg2 Then
                If (-Cast(SQLITE_C_INT, ((local23 <> local28)))) Then
                    sqlite3VdbeAddOp2(local4, Cast(SQLITE_C_INT, 83ULL), Cast(SQLITE_C_INT, (local23 + local45)), local22)
                End If
            Else
                local47 = local21->a(local45).pExpr
                local48 = sqlite3ExprCodeTarget(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local47), local22)
                If (-Cast(SQLITE_C_INT, ((local48 <> local22)))) Then
                    sqlite3VdbeAddOp2(local4, IIf(((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local47)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H400000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))), Cast(SQLITE_C_INT, 82ULL), Cast(SQLITE_C_INT, 83ULL)), local48, local22)
                End If
            End If
        End If
    c2fb_flow_11:
        c2fb_temp_115 = local2
        local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_115 + 1)))
        c2fb_temp_116 = local22
        local22 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_116 + 1)))
    Wend
    c2fb_flow_10:
    c2fb_temp_123 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
    local11 = c2fb_temp_123
    If Cast(SQLITE_C_INT, (local33 And Cast(SQLITE_C_INT, 1ULL))) Then
        local49 = sqlite3GetTempRange(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->nCol) + Cast(SQLITE_C_INT, 1ULL))))
        If (-Cast(SQLITE_C_INT, ((local10 < Cast(SQLITE_C_INT, &O0ULL))))) Then
            sqlite3VdbeAddOp2(local4, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), local49)
        Else
            ' C automatic storage declaration
            ' C unused-parameter annotation
            If local17 Then
                sqlite3VdbeAddOp3(local4, Cast(SQLITE_C_INT, 96ULL), local12, local10, local49)
            Else
                ' C unused-parameter annotation
                sqlite3ExprCode(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local21->a(local10).pExpr), local49)
            End If
            c2fb_temp_124 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(local4, Cast(SQLITE_C_INT, 52ULL), local49))
            local50 = c2fb_temp_124
            ' empty C statement
            sqlite3VdbeAddOp2(local4, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), local49)
            sqlite3VdbeJumpHere(local4, local50)
            sqlite3VdbeAddOp1(local4, Cast(SQLITE_C_INT, 13ULL), local49)
            ' empty C statement
            sqlite3MayAbort(CPtr(Any Ptr, arg0))
        End If
        ' C unused-parameter annotation
        sqlite3VdbeAddOp3(local4, Cast(SQLITE_C_INT, 82ULL), Cast(SQLITE_C_INT, (local27 + Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, (local49 + Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->nNVCol) - Cast(SQLITE_C_INT, 1ULL))))
        If Cast(SQLITE_C_UINT, (local1->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000060ULL)))) Then
            ' empty C statement
            ' empty C statement
            sqlite3ComputeGeneratedColumns(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, (local49 + Cast(SQLITE_C_INT, 1ULL))), CPtr(Any Ptr, local1))
        End If
        If (-Cast(SQLITE_C_INT, (local31 = 0))) Then
            sqlite3TableAffinity(CPtr(Any Ptr, local4), CPtr(Any Ptr, local1), Cast(SQLITE_C_INT, (local49 + Cast(SQLITE_C_INT, 1ULL))))
        End If
        sqlite3CodeRowTrigger(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local32), Cast(SQLITE_C_INT, 128ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, 1ULL), CPtr(Any Ptr, local1), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local49 - Cast(SQLITE_C_INT, local1->nCol))) - Cast(SQLITE_C_INT, 1ULL))), arg4, local11)
        sqlite3ReleaseTempRange(CPtr(Any Ptr, arg0), local49, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->nCol) + Cast(SQLITE_C_INT, 1ULL))))
    End If
    If (-Cast(SQLITE_C_INT, (local31 = 0))) Then
        If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local1)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))) Then
            sqlite3VdbeAddOp2(local4, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), local26)
        End If
        If (-Cast(SQLITE_C_INT, ((local10 >= Cast(SQLITE_C_INT, &O0ULL))))) Then
            If local17 Then
                sqlite3VdbeAddOp3(local4, Cast(SQLITE_C_INT, 96ULL), local12, local10, local27)
            Else
                If arg2 Then
                    ' empty C block
                Else
                    local51 = local21->a(local10).pExpr
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local51->op) = Cast(SQLITE_C_INT, 122ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local1)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))) = 0))))))) Then
                        sqlite3VdbeAddOp3(local4, Cast(SQLITE_C_INT, 129ULL), local8, local27, local24)
                        c2fb_temp_125 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
                        local18 = c2fb_temp_125
                    Else
                        sqlite3ExprCode(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local21->a(local10).pExpr), local27)
                    End If
                End If
            End If
            If (-Cast(SQLITE_C_INT, (local18 = 0))) Then
                ' C automatic storage declaration
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local1)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))) = 0))) Then
                    c2fb_temp_126 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(local4, Cast(SQLITE_C_INT, 52ULL), local27))
                    local52 = c2fb_temp_126
                    ' empty C statement
                    sqlite3VdbeAddOp3(local4, Cast(SQLITE_C_INT, 129ULL), local8, local27, local24)
                    sqlite3VdbeJumpHere(local4, local52)
                Else
                    c2fb_temp_127 = Cast(SQLITE_C_INT, sqlite3VdbeCurrentAddr(local4))
                    local52 = c2fb_temp_127
                    sqlite3VdbeAddOp2(local4, Cast(SQLITE_C_INT, 51ULL), local27, Cast(SQLITE_C_INT, (local52 + Cast(SQLITE_C_INT, 2ULL))))
                    ' empty C statement
                End If
                sqlite3VdbeAddOp1(local4, Cast(SQLITE_C_INT, 13ULL), local27)
                ' empty C statement
                sqlite3MayAbort(CPtr(Any Ptr, arg0))
            End If
        Else
            If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local1)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))) OrElse Cast(SQLITE_C_INT, local19))))) Then
                sqlite3VdbeAddOp2(local4, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), local27)
            Else
                sqlite3VdbeAddOp3(local4, Cast(SQLITE_C_INT, 129ULL), local8, local27, local24)
                c2fb_temp_128 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
                local18 = c2fb_temp_128
            End If
        End If
        autoIncStep(arg0, local24, local27)
        If Cast(SQLITE_C_UINT, (local1->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000060ULL)))) Then
            sqlite3ComputeGeneratedColumns(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, (local27 + Cast(SQLITE_C_INT, 1ULL))), CPtr(Any Ptr, local1))
        End If
        If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local1)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))) Then
            local53 = CPtr(Const ZString Ptr, CPtr(SqliteVTable Ptr, sqlite3GetVTable(CPtr(Any Ptr, local0), CPtr(Any Ptr, local1))))
            sqlite3VtabMakeWritable(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local1))
            sqlite3VdbeAddOp4(local4, Cast(SQLITE_C_INT, 7ULL), Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->nCol) + Cast(SQLITE_C_INT, 2ULL))), local26, local53, (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 12ULL)))))
            sqlite3VdbeChangeP5(local4, IIf((-Cast(SQLITE_C_INT, ((arg4 = Cast(SQLITE_C_INT, 11ULL))))), Cast(SQLITE_C_INT, 2ULL), arg4))
            sqlite3MayAbort(CPtr(Any Ptr, arg0))
        Else
            local54 = Cast(SQLITE_C_INT, &O0ULL)
            ' C automatic storage declaration
            sqlite3GenerateConstraintChecks(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local1), local29, local8, local9, local26, Cast(SQLITE_C_INT, &O0ULL), (-Cast(SQLITE_C_INT, ((local10 >= Cast(SQLITE_C_INT, &O0ULL))))), arg4, local11, CPtr(SQLITE_C_INT Ptr, @(local54)), Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, arg5))
            If Cast(sqlite3_uint64, (local0->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &H00004000ULL)))) Then
                sqlite3FkCheck(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local1), Cast(SQLITE_C_INT, &O0ULL), local26, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL))
            End If
            c2fb_temp_129 = Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local54 = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, (sqlite3VdbeHasSubProgram(local4) = 0)))))))))
            local55 = c2fb_temp_129
            sqlite3CompleteInsertion(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local1), local8, local9, local26, local29, Cast(SQLITE_C_INT, &O0ULL), local18, local55)
        End If
    End If
    If local25 Then
        sqlite3VdbeAddOp2(local4, Cast(SQLITE_C_INT, 88ULL), local25, Cast(SQLITE_C_INT, 1ULL))
    End If
    If local32 Then
        sqlite3CodeRowTrigger(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local32), Cast(SQLITE_C_INT, 128ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, 2ULL), CPtr(Any Ptr, local1), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local28 - Cast(SQLITE_C_INT, 2ULL))) - Cast(SQLITE_C_INT, local1->nCol))), arg4, local11)
    End If
    sqlite3VdbeResolveLabel(local4, local11)
    If local17 Then
        sqlite3VdbeAddOp2(local4, Cast(SQLITE_C_INT, 40ULL), local12, local14)
        ' empty C statement
        sqlite3VdbeJumpHere(local4, local13)
        sqlite3VdbeAddOp1(local4, Cast(SQLITE_C_INT, 124ULL), local12)
    Else
        If arg2 Then
            sqlite3VdbeGoto(local4, local14)
            sqlite3VdbeJumpHere(local4, local13)
        End If
    End If
    c2fb_label_1:
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->nested) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((arg0->pTriggerTab = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        sqlite3AutoincrementEnd(CPtr(Any Ptr, arg0))
    End If
    If local25 Then
        sqlite3CodeChangeCount(CPtr(Any Ptr, local4), local25, StrPtr(!"rows inserted"))
    End If
    c2fb_label_0:
    sqlite3SrcListDelete(CPtr(Any Ptr, local0), CPtr(Any Ptr, arg1))
    sqlite3ExprListDelete(CPtr(Any Ptr, local0), CPtr(Any Ptr, local21))
    sqlite3UpsertDelete(CPtr(Any Ptr, local0), CPtr(Any Ptr, arg5))
    sqlite3SelectDelete(CPtr(Any Ptr, local0), CPtr(Any Ptr, arg2))
    If arg3 Then
        sqlite3IdListDelete(CPtr(Any Ptr, local0), CPtr(Any Ptr, arg3))
        sqlite3DbFree(CPtr(Any Ptr, local0), CPtr(Any Ptr, local30))
    End If
    If local29 Then
        sqlite3DbNNFreeNN(CPtr(Any Ptr, local0), CPtr(Any Ptr, local29))
    End If
End Sub

' c2fb skipped checkConstraintExprNode: outside the supported subset
' c2fb skipped sqlite3ExprReferencesUpdatedColumn: FreeBASIC body already exists
Private Function indexIteratorFirst CDecl Alias "indexIteratorFirst" (ByVal arg0 As SqliteIndexIterator Ptr, ByVal arg1 As SQLITE_C_INT Ptr) As SqliteIndex Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT

    ' C unused-parameter annotation
    If arg0->eType Then
        c2fb_temp_0 = CPtr(SQLITE_C_INT Ptr, @((*arg1)))
        c2fb_temp_1 = Cast(SQLITE_C_INT, arg0->u.ax.aIdx[Cast(SQLITE_C_INT, &O0ULL)].ix)
        (*c2fb_temp_0) = c2fb_temp_1
        Return arg0->u.ax.aIdx[Cast(SQLITE_C_INT, &O0ULL)].p
    Else
        c2fb_temp_2 = CPtr(SQLITE_C_INT Ptr, @((*arg1)))
        c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_2) = c2fb_temp_3
        Return arg0->u.lx.pIdx
    End If
End Function

Private Function indexIteratorNext CDecl Alias "indexIteratorNext" (ByVal arg0 As SqliteIndexIterator Ptr, ByVal arg1 As SQLITE_C_INT Ptr) As SqliteIndex Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT Ptr
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SqliteIndex Ptr Ptr
    Dim c2fb_temp_11 As SqliteIndex Ptr

    If arg0->eType Then
        c2fb_temp_0 = CPtr(SQLITE_C_INT Ptr, @(arg0->i))
        c2fb_temp_1 = (*c2fb_temp_0)
        (*c2fb_temp_0) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
        c2fb_temp_2 = (*c2fb_temp_0)
        local0 = c2fb_temp_2
        If (-Cast(SQLITE_C_INT, ((local0 >= arg0->u.ax.nIdx)))) Then
            c2fb_temp_3 = CPtr(SQLITE_C_INT Ptr, @((*arg1)))
            c2fb_temp_4 = Cast(SQLITE_C_INT, local0)
            (*c2fb_temp_3) = c2fb_temp_4
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        c2fb_temp_5 = CPtr(SQLITE_C_INT Ptr, @((*arg1)))
        c2fb_temp_6 = Cast(SQLITE_C_INT, arg0->u.ax.aIdx[local0].ix)
        (*c2fb_temp_5) = c2fb_temp_6
        Return arg0->u.ax.aIdx[local0].p
    Else
        c2fb_temp_7 = CPtr(SQLITE_C_INT Ptr, @(((*arg1))))
        c2fb_temp_8 = (*c2fb_temp_7)
        (*c2fb_temp_7) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_8 + 1)))
        c2fb_temp_9 = (*c2fb_temp_7)
        c2fb_temp_10 = CPtr(SqliteIndex Ptr Ptr, @(arg0->u.lx.pIdx))
        c2fb_temp_11 = arg0->u.lx.pIdx->pNext
        (*c2fb_temp_10) = c2fb_temp_11
        Return arg0->u.lx.pIdx
    End If
End Function

Sub sqlite3GenerateConstraintChecks CDecl Alias "sqlite3GenerateConstraintChecks" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteTable Ptr, ByVal arg2 As SQLITE_C_INT Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As SQLITE_C_INT, ByVal arg7 As UByte, ByVal arg8 As UByte, ByVal arg9 As SQLITE_C_INT, ByVal arg10 As SQLITE_C_INT Ptr, ByVal arg11 As SQLITE_C_INT Ptr, ByVal arg12 As SqliteUpsert Ptr)
    Dim local0 As SqliteVdbe Ptr
    Dim local1 As SqliteIndex Ptr
    Dim local2 As SqliteIndex Ptr
    Dim local3 As sqlite3 Ptr
    Dim local4 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim local6 As SQLITE_C_INT
    Dim local7 As SQLITE_C_INT
    Dim local8 As SQLITE_C_INT
    Dim local9 As SQLITE_C_INT
    Dim local10 As SqliteUpsert Ptr
    Dim local11 As UByte
    Dim local12 As UByte
    Dim local13 As SQLITE_C_INT
    Dim local14 As SQLITE_C_INT
    Dim local15 As SQLITE_C_INT
    Dim local16 As SQLITE_C_INT
    Dim local17 As SQLITE_C_INT
    Dim local18 As SQLITE_C_INT
    Dim local19 As SQLITE_C_INT
    Dim local20 As SqliteTrigger Ptr
    Dim local21 As SQLITE_C_INT
    Dim local22 As SqliteIndexIterator
    Dim c2fb_temp_0 As UByte
    Dim c2fb_temp_1 As sqlite3 Ptr
    Dim c2fb_temp_2 As SqliteVdbe Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SqliteIndex Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SqliteIndex Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim local23 As SQLITE_C_INT
    Dim local24 As SQLITE_C_INT
    Dim local25 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim local26 As SQLITE_C_INT
    Dim local27 As SqliteColumn Ptr
    Dim local28 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim local29 As SQLITE_C_INT
    Dim c2fb_temp_17 As SQLITE_C_INT
    Dim local30 As ZString Ptr
    Dim c2fb_switch_value_18 As sqlite3_uint64
    Dim c2fb_switch_state_19 As SQLITE_C_INT
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim local31 As SqliteExprList Ptr
    Dim c2fb_temp_21 As SQLITE_C_INT Ptr
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim c2fb_temp_23 As SQLITE_C_INT
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As SQLITE_C_INT
    Dim local32 As SQLITE_C_INT
    Dim local33 As SqliteExpr Ptr
    Dim local34 As SqliteExpr Ptr
    Dim c2fb_temp_26 As UByte
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim c2fb_temp_28 As SqliteExpr Ptr
    Dim local35 As ZString Ptr
    Dim c2fb_temp_29 As SQLITE_C_INT
    Dim c2fb_temp_30 As SQLITE_C_INT Ptr
    Dim c2fb_temp_31 As SQLITE_C_INT
    Dim c2fb_temp_32 As SQLITE_C_INT Ptr
    Dim c2fb_temp_33 As SQLITE_C_INT
    Dim c2fb_temp_34 As SQLITE_C_INT Ptr
    Dim c2fb_temp_35 As SQLITE_C_INT
    Dim c2fb_temp_36 As SqliteIndexListTerm Ptr Ptr
    Dim c2fb_temp_37 As SqliteIndexListTerm Ptr
    Dim c2fb_temp_38 As SqliteIndex Ptr Ptr
    Dim c2fb_temp_39 As SqliteIndex Ptr
    Dim c2fb_temp_40 As UByte
    Dim c2fb_temp_41 As SqliteUpsert Ptr
    Dim c2fb_temp_42 As UByte
    Dim local36 As SQLITE_C_INT
    Dim local37 As SQLITE_C_INT
    Dim local38 As sqlite3_uint64
    Dim local39 As SqliteUpsert Ptr
    Dim local40 As UByte Ptr
    Dim c2fb_temp_43 As SQLITE_C_INT
    Dim c2fb_temp_44 As SqliteIndex Ptr
    Dim c2fb_temp_45 As SqliteIndex Ptr
    Dim c2fb_temp_46 As SQLITE_C_INT
    Dim c2fb_temp_47 As SQLITE_C_INT Ptr
    Dim c2fb_temp_48 As SQLITE_C_INT
    Dim c2fb_temp_49 As SQLITE_C_INT Ptr
    Dim c2fb_temp_50 As SQLITE_C_INT
    Dim c2fb_temp_51 As sqlite3_uint64
    Dim c2fb_temp_52 As SqliteIndexListTerm Ptr Ptr
    Dim c2fb_temp_53 As SqliteIndexListTerm Ptr
    Dim c2fb_temp_54 As UByte Ptr
    Dim c2fb_temp_55 As Any Ptr Ptr
    Dim c2fb_temp_56 As Any Ptr
    Dim c2fb_temp_57 As SQLITE_C_INT
    Dim c2fb_temp_58 As SqliteUpsert Ptr
    Dim c2fb_temp_59 As SqliteUpsert Ptr
    Dim c2fb_temp_60 As SQLITE_C_INT
    Dim c2fb_temp_61 As SqliteIndex Ptr
    Dim c2fb_temp_62 As SqliteIndex Ptr
    Dim c2fb_temp_63 As SQLITE_C_INT
    Dim c2fb_temp_64 As UByte Ptr
    Dim c2fb_temp_65 As UByte
    Dim c2fb_temp_66 As SqliteIndex Ptr Ptr
    Dim c2fb_temp_67 As SqliteIndex Ptr
    Dim c2fb_temp_68 As SQLITE_C_INT Ptr
    Dim c2fb_temp_69 As SQLITE_C_INT
    Dim c2fb_temp_70 As SQLITE_C_INT
    Dim c2fb_temp_71 As SQLITE_C_INT
    Dim c2fb_temp_72 As SqliteIndex Ptr
    Dim c2fb_temp_73 As SqliteIndex Ptr
    Dim c2fb_temp_74 As SQLITE_C_INT
    Dim c2fb_temp_75 As SqliteIndex Ptr Ptr
    Dim c2fb_temp_76 As SqliteIndex Ptr
    Dim c2fb_temp_77 As SQLITE_C_INT Ptr
    Dim c2fb_temp_78 As SQLITE_C_INT
    Dim c2fb_temp_79 As SQLITE_C_INT
    Dim c2fb_temp_80 As SqliteTrigger Ptr
    Dim c2fb_temp_81 As SQLITE_C_INT
    Dim c2fb_temp_82 As SqliteTrigger Ptr
    Dim c2fb_temp_83 As SQLITE_C_INT
    Dim c2fb_temp_84 As SqliteTrigger Ptr
    Dim c2fb_temp_85 As SQLITE_C_INT
    Dim c2fb_temp_86 As SQLITE_C_INT
    Dim c2fb_temp_87 As SqliteIndex Ptr
    Dim c2fb_temp_88 As SqliteIndex Ptr
    Dim c2fb_temp_89 As SQLITE_C_INT
    Dim c2fb_temp_90 As SQLITE_C_INT Ptr
    Dim c2fb_temp_91 As SQLITE_C_INT
    Dim c2fb_temp_92 As SQLITE_C_INT
    Dim c2fb_temp_93 As SQLITE_C_INT
    Dim c2fb_temp_94 As SQLITE_C_INT
    Dim c2fb_temp_95 As SQLITE_C_INT
    Dim local41 As SQLITE_C_INT
    Dim c2fb_temp_96 As SQLITE_C_INT
    Dim c2fb_temp_97 As SQLITE_C_INT
    Dim c2fb_temp_98 As SQLITE_C_INT
    Dim c2fb_temp_99 As SqliteUpsert Ptr
    Dim c2fb_temp_100 As SQLITE_C_INT
    Dim c2fb_temp_101 As SQLITE_C_INT
    Dim c2fb_temp_102 As SQLITE_C_INT
    Dim c2fb_temp_103 As SQLITE_C_INT
    Dim c2fb_temp_104 As SQLITE_C_INT
    Dim c2fb_temp_105 As SQLITE_C_INT
    Dim c2fb_temp_106 As SQLITE_C_INT
    Dim c2fb_temp_107 As SQLITE_C_INT
    Dim c2fb_temp_108 As SQLITE_C_INT
    Dim c2fb_switch_value_109 As sqlite3_uint64
    Dim c2fb_switch_state_110 As SQLITE_C_INT
    Dim c2fb_temp_111 As SQLITE_C_INT
    Dim c2fb_temp_112 As SQLITE_C_INT
    Dim c2fb_temp_113 As SqliteIndex Ptr
    Dim c2fb_temp_114 As SqliteIndex Ptr
    Dim local42 As SQLITE_C_INT
    Dim local43 As SQLITE_C_INT
    Dim local44 As SQLITE_C_INT
    Dim local45 As SQLITE_C_INT
    Dim local46 As SQLITE_C_INT
    Dim local47 As SQLITE_C_INT
    Dim c2fb_temp_115 As SqliteUpsert Ptr
    Dim c2fb_temp_116 As SQLITE_C_INT
    Dim c2fb_temp_117 As UByte
    Dim c2fb_temp_118 As SQLITE_C_INT
    Dim c2fb_temp_119 As SQLITE_C_INT Ptr
    Dim c2fb_temp_120 As SQLITE_C_INT
    Dim c2fb_temp_121 As SQLITE_C_INT Ptr
    Dim c2fb_temp_122 As SQLITE_C_INT
    Dim c2fb_temp_123 As SQLITE_C_INT
    Dim c2fb_temp_124 As SQLITE_C_INT
    Dim c2fb_temp_125 As SQLITE_C_INT
    Dim local48 As SQLITE_C_INT
    Dim local49 As SQLITE_C_INT
    Dim c2fb_temp_126 As SQLITE_C_INT Ptr
    Dim c2fb_temp_127 As SQLITE_C_INT
    Dim c2fb_temp_128 As SQLITE_C_INT Ptr
    Dim c2fb_temp_129 As SQLITE_C_INT
    Dim c2fb_temp_130 As SQLITE_C_INT
    Dim c2fb_temp_131 As SQLITE_C_INT
    Dim c2fb_temp_132 As SQLITE_C_INT
    Dim c2fb_temp_133 As SQLITE_C_INT
    Dim c2fb_temp_134 As SQLITE_C_INT
    Dim c2fb_temp_135 As SQLITE_C_INT
    Dim c2fb_temp_136 As SQLITE_C_INT
    Dim c2fb_temp_137 As SQLITE_C_INT
    Dim c2fb_temp_138 As SQLITE_C_INT
    Dim local50 As SQLITE_C_INT
    Dim c2fb_temp_139 As SQLITE_C_INT
    Dim c2fb_temp_140 As SQLITE_C_INT
    Dim c2fb_temp_141 As SQLITE_C_INT
    Dim local51 As SQLITE_C_INT
    Dim local52 As SQLITE_C_INT
    Dim local53 As SQLITE_C_INT
    Dim c2fb_temp_142 As SQLITE_C_INT
    Dim c2fb_temp_143 As SQLITE_C_INT
    Dim local54 As ZString Ptr
    Dim c2fb_temp_144 As SQLITE_C_INT
    Dim c2fb_temp_145 As SQLITE_C_INT
    Dim c2fb_temp_146 As SQLITE_C_INT
    Dim c2fb_temp_147 As SQLITE_C_INT
    Dim c2fb_temp_148 As SQLITE_C_INT
    Dim c2fb_temp_149 As SQLITE_C_INT
    Dim c2fb_temp_150 As SQLITE_C_INT
    Dim c2fb_switch_value_151 As sqlite3_uint64
    Dim c2fb_switch_state_152 As SQLITE_C_INT
    Dim local55 As SQLITE_C_INT
    Dim c2fb_temp_153 As SQLITE_C_INT
    Dim c2fb_temp_154 As SQLITE_C_INT
    Dim local56 As SqliteVdbeOp
    Dim c2fb_temp_155 As SqliteVdbeOp
    Dim local57 As SQLITE_C_INT
    Dim local58 As Const ZString Ptr
    Dim c2fb_temp_156 As SQLITE_C_INT
    Dim c2fb_temp_157 As SQLITE_C_INT
    Dim c2fb_temp_158 As Const ZString Ptr
    Dim c2fb_temp_159 As SQLITE_C_INT
    Dim c2fb_temp_160 As SQLITE_C_INT
    Dim c2fb_temp_161 As SQLITE_C_INT
    Dim local59 As SQLITE_C_INT
    Dim c2fb_temp_162 As SQLITE_C_INT Ptr
    Dim c2fb_temp_163 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    local2 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local8 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    local10 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    local12 = Cast(SQLITE_C_INT, &O0ULL)
    local13 = Cast(SQLITE_C_INT, &O0ULL)
    local14 = Cast(SQLITE_C_INT, &O0ULL)
    local15 = Cast(SQLITE_C_INT, &O0ULL)
    local16 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    local18 = Cast(SQLITE_C_INT, &O0ULL)
    local19 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    local21 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    c2fb_temp_0 = Cast(UByte, (-Cast(SQLITE_C_INT, ((arg6 <> Cast(SQLITE_C_INT, &O0ULL))))))
    local11 = c2fb_temp_0
    c2fb_temp_1 = arg0->db
    local3 = c2fb_temp_1
    c2fb_temp_2 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    local0 = c2fb_temp_2
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_3 = Cast(SQLITE_C_INT, arg1->nCol)
    local6 = c2fb_temp_3
    If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
        c2fb_temp_4 = CPtr(SqliteIndex Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        local2 = c2fb_temp_4
        c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
        local9 = c2fb_temp_5
    Else
        c2fb_temp_6 = CPtr(SqliteIndex Ptr, sqlite3PrimaryKeyIndex(CPtr(Any Ptr, arg1)))
        local2 = c2fb_temp_6
        c2fb_temp_7 = Cast(SQLITE_C_INT, local2->nKeyCol)
        local9 = c2fb_temp_7
    End If
    ' empty C statement
    If Cast(SQLITE_C_UINT, (arg1->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000800ULL)))) Then
        local23 = Cast(SQLITE_C_INT, &O0ULL)
        local24 = Cast(SQLITE_C_INT, &O0ULL)
        local25 = Cast(SQLITE_C_INT, &O0ULL)
        While Cast(SQLITE_C_INT, 1ULL)
            c2fb_temp_8 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local4 = c2fb_temp_8
            While (-Cast(SQLITE_C_INT, ((local4 < local6))))
                ' C automatic storage declaration
                local27 = CPtr(SqliteColumn Ptr, @(arg1->aCol[local4]))
                ' C automatic storage declaration
                c2fb_temp_10 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local27->flags) Shr 0) And Cast(SQLITE_C_UINT, &HFULL))))
                local7 = c2fb_temp_10
                If (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    Goto c2fb_flow_3
                End If
                If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, arg1->iPKey))))) Then
                    Goto c2fb_flow_3
                End If
                c2fb_temp_11 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local27->colFlags) And Cast(SQLITE_C_INT, &H0060ULL))))
                local28 = c2fb_temp_11
                If (-Cast(SQLITE_C_INT, ((local28 AndAlso (-Cast(SQLITE_C_INT, (local23 = 0))))))) Then
                    c2fb_temp_12 = local25
                    local25 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_12 + 1)))
                    Goto c2fb_flow_3
                End If
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg11 AndAlso (-Cast(SQLITE_C_INT, ((arg11[local4] < Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, (local28 = 0))))))) Then
                    Goto c2fb_flow_3
                End If
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg8) <> Cast(SQLITE_C_INT, 11ULL))))) Then
                    c2fb_temp_13 = Cast(SQLITE_C_INT, arg8)
                    local7 = c2fb_temp_13
                Else
                    If (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, 11ULL))))) Then
                        c2fb_temp_14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 2ULL))
                        local7 = c2fb_temp_14
                    End If
                End If
                If (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, 5ULL))))) Then
                    If (-Cast(SQLITE_C_INT, ((local23 OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local27->iDflt) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                        ' empty C statement
                        ' empty C statement
                        ' empty C statement
                        c2fb_temp_15 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 2ULL))
                        local7 = c2fb_temp_15
                    Else
                        ' C unused-parameter annotation
                    End If
                Else
                    If (-Cast(SQLITE_C_INT, ((local23 AndAlso (-Cast(SQLITE_C_INT, (local28 = 0))))))) Then
                        Goto c2fb_flow_3
                    End If
                End If
                ' C unused-parameter annotation
                ' empty C statement
                c2fb_temp_16 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, sqlite3TableColumnToStorage(CPtr(Any Ptr, arg1), local4)) + arg5)) + Cast(SQLITE_C_INT, 1ULL))))
                local26 = c2fb_temp_16
                c2fb_switch_value_18 = Cast(sqlite3_uint64, local7)
                c2fb_switch_state_19 = 0
                Select Case c2fb_switch_value_18
                    Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 5ULL))
                        c2fb_switch_state_19 = 1
                    Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 2ULL))
                        c2fb_switch_state_19 = 2
                    Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 3ULL))
                        c2fb_switch_state_19 = 3
                    Case Else
                        c2fb_switch_state_19 = 4
                End Select
                Do
                    Select Case c2fb_switch_state_19
                    Case 0
                        Exit Do
                    Case 1
                        local29 = sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 52ULL), local26)
                        ' empty C statement
                        ' C unused-parameter annotation
                        c2fb_temp_17 = local24
                        local24 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_17 + 1)))
                        sqlite3ExprCodeCopy(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, sqlite3ColumnExprAuth(CPtr(Any Ptr, arg1), CPtr(Any Ptr, local27), CPtr(Any Ptr, arg0)))), local26)
                        sqlite3VdbeJumpHere(local0, local29)
                        Goto c2fb_flow_4
                        c2fb_switch_state_19 = 0
                    Case 2
                        sqlite3MayAbort(CPtr(Any Ptr, arg0))
                        ' C switch fallthrough annotation
                        c2fb_switch_state_19 = 3
                    Case 3
                        local30 = CPtr(ZString Ptr, sqlite3MPrintf(CPtr(Any Ptr, local3), StrPtr(!"%s.%s"), arg1->zName, local27->zCnName))
                        ' empty C statement
                        sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 71ULL), (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 19ULL) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 5ULL) Shl Cast(SQLITE_C_INT, 8ULL))))))), local7, local26)
                        sqlite3VdbeAppendP4(local0, CPtr(Any Ptr, local30), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 7ULL)))))
                        sqlite3VdbeChangeP5(local0, Cast(SQLITE_C_INT, 1ULL))
                        ' empty C statement
                        Goto c2fb_flow_4
                        c2fb_switch_state_19 = 0
                    Case 4
                        ' C unused-parameter annotation
                        sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 51ULL), local26, arg9)
                        ' empty C statement
                        Goto c2fb_flow_4
                        c2fb_switch_state_19 = 0
                    End Select
                Loop
                c2fb_flow_4:
            c2fb_flow_3:
                c2fb_temp_9 = local4
                local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_9 + 1)))
            Wend
            c2fb_flow_2:
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local25 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local24 = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                Goto c2fb_flow_0
            End If
            If local23 Then
                Goto c2fb_flow_0
            End If
            c2fb_temp_20 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
            local23 = c2fb_temp_20
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local24 > Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000060ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
                sqlite3ComputeGeneratedColumns(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, (arg5 + Cast(SQLITE_C_INT, 1ULL))), CPtr(Any Ptr, arg1))
            End If
        c2fb_flow_1:
        Wend
        c2fb_flow_0:
    End If
    If (-Cast(SQLITE_C_INT, ((CPtr(SqliteExprList Ptr, arg1->pCheck) AndAlso (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local3->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &H00000200ULL))))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
        local31 = CPtr(SqliteExprList Ptr, arg1->pCheck)
        c2fb_temp_21 = CPtr(SQLITE_C_INT Ptr, @(arg0->iSelfTab))
        c2fb_temp_22 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (-(Cast(SQLITE_C_INT, (arg5 + Cast(SQLITE_C_INT, 1ULL)))))))
        (*c2fb_temp_21) = c2fb_temp_22
        c2fb_temp_23 = Cast(SQLITE_C_INT, IIf((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg8) <> Cast(SQLITE_C_INT, 11ULL))))), Cast(SQLITE_C_INT, arg8), Cast(SQLITE_C_INT, 2ULL)))
        local7 = c2fb_temp_23
        c2fb_temp_24 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local4 = c2fb_temp_24
        While (-Cast(SQLITE_C_INT, ((local4 < local31->nExpr))))
            ' C automatic storage declaration
            ' C automatic storage declaration
            local34 = local31->a(local4).pExpr
            If (-Cast(SQLITE_C_INT, ((arg11 AndAlso (-Cast(SQLITE_C_INT, (sqlite3ExprReferencesUpdatedColumn(CPtr(Any Ptr, local34), arg11, arg7) = 0))))))) Then
                Goto c2fb_flow_6
            End If
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local12) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                sqlite3TableAffinity(CPtr(Any Ptr, local0), CPtr(Any Ptr, arg1), Cast(SQLITE_C_INT, (arg5 + Cast(SQLITE_C_INT, 1ULL))))
                c2fb_temp_26 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
                local12 = c2fb_temp_26
            End If
            c2fb_temp_27 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
            local32 = c2fb_temp_27
            ' empty C statement
            c2fb_temp_28 = CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local3), CPtr(Any Ptr, local34), Cast(SQLITE_C_INT, &O0ULL)))
            local33 = c2fb_temp_28
            If (-Cast(SQLITE_C_INT, (local3->mallocFailed = 0))) Then
                sqlite3ExprIfTrue(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local33), local32, Cast(SQLITE_C_INT, &H10ULL))
            End If
            sqlite3ExprDelete(CPtr(Any Ptr, local3), CPtr(Any Ptr, local33))
            If (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, 4ULL))))) Then
                sqlite3VdbeGoto(local0, arg9)
            Else
                local35 = CPtr(ZString Ptr, local31->a(local4).zEName)
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, 5ULL))))) Then
                    c2fb_temp_29 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 2ULL))
                    local7 = c2fb_temp_29
                End If
                sqlite3HaltConstraint(CPtr(Any Ptr, arg0), (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 19ULL) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 1ULL) Shl Cast(SQLITE_C_INT, 8ULL))))))), local7, local35, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, 3ULL))
            End If
            sqlite3VdbeResolveLabel(local0, local32)
        c2fb_flow_6:
            c2fb_temp_25 = local4
            local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_25 + 1)))
        Wend
        c2fb_flow_5:
        c2fb_temp_30 = CPtr(SQLITE_C_INT Ptr, @(arg0->iSelfTab))
        c2fb_temp_31 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_30) = c2fb_temp_31
    End If
    c2fb_temp_32 = CPtr(SQLITE_C_INT Ptr, @(local22.eType))
    c2fb_temp_33 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_32) = c2fb_temp_33
    c2fb_temp_34 = CPtr(SQLITE_C_INT Ptr, @(local22.i))
    c2fb_temp_35 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_34) = c2fb_temp_35
    c2fb_temp_36 = CPtr(SqliteIndexListTerm Ptr Ptr, @(local22.u.ax.aIdx))
    c2fb_temp_37 = CPtr(SqliteIndexListTerm Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_36) = c2fb_temp_37
    c2fb_temp_38 = CPtr(SqliteIndex Ptr Ptr, @(local22.u.lx.pIdx))
    c2fb_temp_39 = CPtr(SqliteIndex Ptr, arg1->pIndex)
    (*c2fb_temp_38) = c2fb_temp_39
    If arg12 Then
        If (-Cast(SQLITE_C_INT, ((CPtr(SqliteExprList Ptr, arg12->pUpsertTarget) = Cast(SQLITE_C_INT, &O0ULL))))) Then
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg12->isDoUpdate) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_40 = Cast(UByte, Cast(SQLITE_C_INT, 4ULL))
                arg8 = c2fb_temp_40
                c2fb_temp_41 = CPtr(SqliteUpsert Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                arg12 = c2fb_temp_41
            Else
                c2fb_temp_42 = Cast(UByte, Cast(SQLITE_C_INT, 6ULL))
                arg8 = c2fb_temp_42
            End If
        Else
            If (-Cast(SQLITE_C_INT, ((CPtr(SqliteIndex Ptr, arg1->pIndex) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                ' C automatic storage declaration
                ' C automatic storage declaration
                ' C automatic storage declaration
                ' C automatic storage declaration
                ' C automatic storage declaration
                c2fb_temp_43 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local36 = c2fb_temp_43
                c2fb_temp_44 = CPtr(SqliteIndex Ptr, arg1->pIndex)
                local1 = c2fb_temp_44
                While local1
                    ' C unused-parameter annotation
                c2fb_flow_8:
                    c2fb_temp_45 = local1->pNext
                    local1 = c2fb_temp_45
                    c2fb_temp_46 = local36
                    local36 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_46 + 1)))
                Wend
                c2fb_flow_7:
                c2fb_temp_47 = CPtr(SQLITE_C_INT Ptr, @(local22.eType))
                c2fb_temp_48 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                (*c2fb_temp_47) = c2fb_temp_48
                c2fb_temp_49 = CPtr(SQLITE_C_INT Ptr, @(local22.u.ax.nIdx))
                c2fb_temp_50 = Cast(SQLITE_C_INT, local36)
                (*c2fb_temp_49) = c2fb_temp_50
                c2fb_temp_51 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteIndexListTerm))) + Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))))) * Cast(sqlite3_uint64, local36))) + Cast(sqlite3_uint64, local36))))
                local38 = c2fb_temp_51
                c2fb_temp_52 = CPtr(SqliteIndexListTerm Ptr Ptr, @(local22.u.ax.aIdx))
                c2fb_temp_53 = CPtr(SqliteIndexListTerm Ptr, CPtr(Any Ptr, sqlite3DbMallocZero(CPtr(Any Ptr, local3), local38)))
                (*c2fb_temp_52) = c2fb_temp_53
                If (-Cast(SQLITE_C_INT, ((local22.u.ax.aIdx = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    Return
                End If
                c2fb_temp_54 = CPtr(UByte Ptr, CPtr(SqliteIndexListTerm Ptr, @(local22.u.ax.aIdx[local36])))
                local40 = c2fb_temp_54
                c2fb_temp_55 = CPtr(Any Ptr Ptr, @(arg12->pToFree))
                c2fb_temp_56 = CPtr(Any Ptr, local22.u.ax.aIdx)
                (*c2fb_temp_55) = c2fb_temp_56
                c2fb_temp_57 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local4 = c2fb_temp_57
                c2fb_temp_58 = arg12
                local39 = c2fb_temp_58
                While local39
                    If (-Cast(SQLITE_C_INT, ((CPtr(SqliteExprList Ptr, local39->pUpsertTarget) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        Goto c2fb_flow_9
                    End If
                    If (-Cast(SQLITE_C_INT, ((CPtr(SqliteIndex Ptr, local39->pUpsertIdx) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        Goto c2fb_flow_10
                    End If
                    c2fb_temp_60 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    local37 = c2fb_temp_60
                    c2fb_temp_61 = CPtr(SqliteIndex Ptr, arg1->pIndex)
                    local1 = c2fb_temp_61
                    While (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, ((local1 <> CPtr(SqliteIndex Ptr, local39->pUpsertIdx)))))))))
                        c2fb_temp_62 = local1->pNext
                        local1 = c2fb_temp_62
                        c2fb_temp_63 = local37
                        local37 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_63 + 1)))
                    c2fb_flow_12:
                    Wend
                    c2fb_flow_11:
                    If local40[local37] Then
                        Goto c2fb_flow_10
                    End If
                    c2fb_temp_64 = CPtr(UByte Ptr, @(local40[local37]))
                    c2fb_temp_65 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
                    (*c2fb_temp_64) = c2fb_temp_65
                    c2fb_temp_66 = CPtr(SqliteIndex Ptr Ptr, @(local22.u.ax.aIdx[local4].p))
                    c2fb_temp_67 = local1
                    (*c2fb_temp_66) = c2fb_temp_67
                    c2fb_temp_68 = CPtr(SQLITE_C_INT Ptr, @(local22.u.ax.aIdx[local4].ix))
                    c2fb_temp_69 = Cast(SQLITE_C_INT, local37)
                    (*c2fb_temp_68) = c2fb_temp_69
                    c2fb_temp_70 = local4
                    local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_70 + 1)))
                c2fb_flow_10:
                    c2fb_temp_59 = local39->pNextUpsert
                    local39 = c2fb_temp_59
                Wend
                c2fb_flow_9:
                c2fb_temp_71 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local37 = c2fb_temp_71
                c2fb_temp_72 = CPtr(SqliteIndex Ptr, arg1->pIndex)
                local1 = c2fb_temp_72
                While local1
                    If local40[local37] Then
                        Goto c2fb_flow_14
                    End If
                    c2fb_temp_75 = CPtr(SqliteIndex Ptr Ptr, @(local22.u.ax.aIdx[local4].p))
                    c2fb_temp_76 = local1
                    (*c2fb_temp_75) = c2fb_temp_76
                    c2fb_temp_77 = CPtr(SQLITE_C_INT Ptr, @(local22.u.ax.aIdx[local4].ix))
                    c2fb_temp_78 = Cast(SQLITE_C_INT, local37)
                    (*c2fb_temp_77) = c2fb_temp_78
                    c2fb_temp_79 = local4
                    local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_79 + 1)))
                c2fb_flow_14:
                    c2fb_temp_73 = local1->pNext
                    local1 = c2fb_temp_73
                    c2fb_temp_74 = local37
                    local37 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_74 + 1)))
                Wend
                c2fb_flow_13:
                ' C unused-parameter annotation
            End If
        End If
    End If
    If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local3->flags And Cast(sqlite3_uint64, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00002000ULL) Or Cast(SQLITE_C_INT, &H00004000ULL)))))))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
        c2fb_temp_80 = CPtr(SqliteTrigger Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        local20 = c2fb_temp_80
        c2fb_temp_81 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local17 = c2fb_temp_81
    Else
        If Cast(sqlite3_uint64, (local3->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &H00002000ULL)))) Then
            c2fb_temp_82 = CPtr(SqliteTrigger Ptr, sqlite3TriggersExist(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), Cast(SQLITE_C_INT, 129ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)))
            local20 = c2fb_temp_82
            c2fb_temp_83 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local20 <> Cast(SQLITE_C_INT, &O0ULL))))) OrElse sqlite3FkRequired(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)))))))
            local17 = c2fb_temp_83
        Else
            c2fb_temp_84 = CPtr(SqliteTrigger Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            local20 = c2fb_temp_84
            c2fb_temp_85 = Cast(SQLITE_C_INT, sqlite3FkRequired(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)))
            local17 = c2fb_temp_85
        End If
        If local17 Then
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg8) <> Cast(SQLITE_C_INT, 5ULL))))) Then
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg8) <> Cast(SQLITE_C_INT, 11ULL))))) Then
                    c2fb_temp_86 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    local17 = c2fb_temp_86
                Else
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg7) = Cast(SQLITE_C_INT, &O0ULL))))) OrElse local2)))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->keyConf) <> Cast(SQLITE_C_INT, 5ULL))))))))) Then
                        c2fb_temp_87 = CPtr(SqliteIndex Ptr, arg1->pIndex)
                        local1 = c2fb_temp_87
                        While local1
                            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->onError) = Cast(SQLITE_C_INT, 5ULL))))) Then
                                Goto c2fb_flow_15
                            End If
                        c2fb_flow_16:
                            c2fb_temp_88 = local1->pNext
                            local1 = c2fb_temp_88
                        Wend
                        c2fb_flow_15:
                        If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                            c2fb_temp_89 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                            local17 = c2fb_temp_89
                        End If
                    End If
                End If
            End If
        End If
        If local17 Then
            c2fb_temp_90 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
            c2fb_temp_91 = (*c2fb_temp_90)
            (*c2fb_temp_90) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_91 + 1)))
            c2fb_temp_92 = (*c2fb_temp_90)
            c2fb_temp_93 = Cast(SQLITE_C_INT, c2fb_temp_92)
            local17 = c2fb_temp_93
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, &O0ULL), local17)
            ' empty C statement
            c2fb_temp_94 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
            local19 = c2fb_temp_94
            c2fb_temp_95 = Cast(SQLITE_C_INT, local19)
            local18 = c2fb_temp_95
        End If
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg7) AndAlso (-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        local41 = sqlite3VdbeMakeLabel(arg0)
        c2fb_temp_96 = Cast(SQLITE_C_INT, arg1->keyConf)
        local7 = c2fb_temp_96
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg8) <> Cast(SQLITE_C_INT, 11ULL))))) Then
            c2fb_temp_97 = Cast(SQLITE_C_INT, arg8)
            local7 = c2fb_temp_97
        Else
            If (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, 11ULL))))) Then
                c2fb_temp_98 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 2ULL))
                local7 = c2fb_temp_98
            End If
        End If
        If arg12 Then
            c2fb_temp_99 = CPtr(SqliteUpsert Ptr, sqlite3UpsertOfIndex(CPtr(Any Ptr, arg12), Cast(SQLITE_C_INT, &O0ULL)))
            local10 = c2fb_temp_99
            If (-Cast(SQLITE_C_INT, ((local10 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local10->isDoUpdate) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_100 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 4ULL))
                    local7 = c2fb_temp_100
                Else
                    c2fb_temp_101 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 6ULL))
                    local7 = c2fb_temp_101
                End If
            End If
            If (-Cast(SQLITE_C_INT, ((local10 <> arg12)))) Then
                c2fb_temp_102 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp0(local0, Cast(SQLITE_C_INT, 9ULL)))
                local14 = c2fb_temp_102
            End If
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, 5ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local7 <> Cast(SQLITE_C_INT, arg8))))))))) AndAlso CPtr(SqliteIndex Ptr, arg1->pIndex))))) Then
            If local14 Then
                c2fb_temp_103 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local14 + Cast(SQLITE_C_INT, 1ULL))))
                local15 = c2fb_temp_103
                c2fb_temp_104 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local14 = c2fb_temp_104
            Else
                c2fb_temp_105 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (sqlite3VdbeAddOp0(local0, Cast(SQLITE_C_INT, 9ULL)) + Cast(SQLITE_C_INT, 1ULL))))
                local15 = c2fb_temp_105
            End If
            ' empty C statement
        End If
        If local11 Then
            sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 54ULL), arg5, local41, arg6)
            sqlite3VdbeChangeP5(local0, Cast(SQLITE_C_INT, &H90ULL))
            ' empty C statement
        End If
        ' empty C statement
        ' empty C statement
        sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 31ULL), arg3, local41, arg5)
        ' empty C statement
        c2fb_switch_value_109 = Cast(sqlite3_uint64, local7)
        c2fb_switch_state_110 = 0
        Select Case c2fb_switch_value_109
            Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 2ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 3ULL))
                c2fb_switch_state_110 = 2
            Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 5ULL))
                c2fb_switch_state_110 = 3
            Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 6ULL))
                c2fb_switch_state_110 = 4
            Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 4ULL))
                c2fb_switch_state_110 = 5
            Case Else
                c2fb_switch_state_110 = 1
        End Select
        Do
            Select Case c2fb_switch_state_110
            Case 0
                Exit Do
            Case 1
                c2fb_temp_106 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 2ULL))
                local7 = c2fb_temp_106
                ' C switch fallthrough annotation
                c2fb_switch_state_110 = 2
            Case 2
                ' empty C statement
                ' empty C statement
                ' empty C statement
                sqlite3RowidConstraint(CPtr(Any Ptr, arg0), local7, CPtr(Any Ptr, arg1))
                Goto c2fb_flow_17
                c2fb_switch_state_110 = 0
            Case 3
                If local17 Then
                    sqlite3MultiWrite(CPtr(Any Ptr, arg0))
                    sqlite3GenerateRowDelete(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), CPtr(Any Ptr, local20), arg3, arg4, arg5, Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, 5ULL), Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
                    sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 88ULL), local17, Cast(SQLITE_C_INT, 1ULL))
                    c2fb_temp_107 = local21
                    local21 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_107 + 1)))
                Else
#ifdef SQLITE_ENABLE_PREUPDATE_HOOK
                    ' REPLACE reports the conflicting row before OP_Insert overwrites it.
                    sqlite3VdbeAddOp2(local0, OP_Delete, arg3, OPFLAG_ISNOOP)
            sqlite3VdbeAppendP4(local0, CPtr(Any Ptr, arg1), P4_TABLE)
#endif
                    If CPtr(SqliteIndex Ptr, arg1->pIndex) Then
                        sqlite3MultiWrite(CPtr(Any Ptr, arg0))
                        sqlite3GenerateRowIndexDelete(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), arg3, arg4, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
                    End If
                End If
                c2fb_temp_108 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                local8 = c2fb_temp_108
                Goto c2fb_flow_17
                c2fb_switch_state_110 = 0
            Case 4
                sqlite3UpsertDoUpdate(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg12), CPtr(Any Ptr, arg1), Cast(SQLITE_C_INT, &O0ULL), arg3)
                ' C switch fallthrough annotation
                c2fb_switch_state_110 = 5
            Case 5
                ' empty C statement
                sqlite3VdbeGoto(local0, arg9)
                Goto c2fb_flow_17
                c2fb_switch_state_110 = 0
            End Select
        Loop
        c2fb_flow_17:
        sqlite3VdbeResolveLabel(local0, local41)
        If local15 Then
            c2fb_temp_111 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp0(local0, Cast(SQLITE_C_INT, 9ULL)))
            local16 = c2fb_temp_111
            sqlite3VdbeJumpHere(local0, Cast(SQLITE_C_INT, (local15 - Cast(SQLITE_C_INT, 1ULL))))
        Else
            If (-Cast(SQLITE_C_INT, ((arg12 AndAlso (-Cast(SQLITE_C_INT, ((local10 <> arg12)))))))) Then
                c2fb_temp_112 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp0(local0, Cast(SQLITE_C_INT, 9ULL)))
                local13 = c2fb_temp_112
            End If
        End If
    End If
    c2fb_temp_113 = CPtr(SqliteIndex Ptr, indexIteratorFirst(CPtr(SqliteIndexIterator Ptr, @(local22)), CPtr(SQLITE_C_INT Ptr, @(local5))))
    local1 = c2fb_temp_113
    While local1
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        If (-Cast(SQLITE_C_INT, ((arg2[local5] = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_19
        End If
        If arg12 Then
            c2fb_temp_115 = CPtr(SqliteUpsert Ptr, sqlite3UpsertOfIndex(CPtr(Any Ptr, arg12), CPtr(Any Ptr, local1)))
            local10 = c2fb_temp_115
            If (-Cast(SQLITE_C_INT, ((local14 AndAlso (-Cast(SQLITE_C_INT, ((local10 = arg12)))))))) Then
                sqlite3VdbeJumpHere(local0, local14)
            End If
        End If
        c2fb_temp_116 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
        local45 = c2fb_temp_116
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local12) = Cast(SQLITE_C_INT, &O0ULL))))) Then
            sqlite3TableAffinity(CPtr(Any Ptr, local0), CPtr(Any Ptr, arg1), Cast(SQLITE_C_INT, (arg5 + Cast(SQLITE_C_INT, 1ULL))))
            c2fb_temp_117 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
            local12 = c2fb_temp_117
        End If
        ' empty C statement
        c2fb_temp_118 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg4 + local5)))
        local44 = c2fb_temp_118
        If CPtr(SqliteExpr Ptr, local1->pPartIdxWhere) Then
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), arg2[local5])
            c2fb_temp_119 = CPtr(SQLITE_C_INT Ptr, @(arg0->iSelfTab))
            c2fb_temp_120 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (-(Cast(SQLITE_C_INT, (arg5 + Cast(SQLITE_C_INT, 1ULL)))))))
            (*c2fb_temp_119) = c2fb_temp_120
            sqlite3ExprIfFalseDup(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local1->pPartIdxWhere)), local45, Cast(SQLITE_C_INT, &H10ULL))
            c2fb_temp_121 = CPtr(SQLITE_C_INT Ptr, @(arg0->iSelfTab))
            c2fb_temp_122 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_121) = c2fb_temp_122
        End If
        c2fb_temp_123 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg2[local5] + Cast(SQLITE_C_INT, 1ULL))))
        local42 = c2fb_temp_123
        c2fb_temp_124 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local4 = c2fb_temp_124
        While (-Cast(SQLITE_C_INT, ((local4 < Cast(SQLITE_C_INT, local1->nColumn)))))
            local48 = local1->aiColumn[local4]
            ' C automatic storage declaration
            If (-Cast(SQLITE_C_INT, ((local48 = (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 2ULL)))))))) Then
                c2fb_temp_126 = CPtr(SQLITE_C_INT Ptr, @(arg0->iSelfTab))
                c2fb_temp_127 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (-(Cast(SQLITE_C_INT, (arg5 + Cast(SQLITE_C_INT, 1ULL)))))))
                (*c2fb_temp_126) = c2fb_temp_127
                sqlite3ExprCodeCopy(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, local1->aColExpr)->a(local4).pExpr), Cast(SQLITE_C_INT, (local42 + local4)))
                c2fb_temp_128 = CPtr(SQLITE_C_INT Ptr, @(arg0->iSelfTab))
                c2fb_temp_129 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_128) = c2fb_temp_129
                ' empty C statement
            Else
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local48 = (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))))))) OrElse (-Cast(SQLITE_C_INT, ((local48 = Cast(SQLITE_C_INT, arg1->iPKey))))))))) Then
                    c2fb_temp_130 = Cast(SQLITE_C_INT, arg5)
                    local49 = c2fb_temp_130
                    sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 84ULL), local49, Cast(SQLITE_C_INT, (local42 + local4)))
                    ' empty C statement
                Else
                    ' empty C statement
                    c2fb_temp_131 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, sqlite3TableColumnToStorage(CPtr(Any Ptr, arg1), local48)) + arg5)) + Cast(SQLITE_C_INT, 1ULL))))
                    local49 = c2fb_temp_131
                    sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 83ULL), local49, Cast(SQLITE_C_INT, (local42 + local4)))
                    ' empty C statement
                End If
            End If
        c2fb_flow_21:
            c2fb_temp_125 = local4
            local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_125 + 1)))
        Wend
        c2fb_flow_20:
        sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 99ULL), local42, local1->nColumn, arg2[local5])
        ' empty C statement
        ' empty C statement
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local11) AndAlso (-Cast(SQLITE_C_INT, ((local2 = local1)))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg7) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            sqlite3VdbeResolveLabel(local0, local45)
            Goto c2fb_flow_19
        End If
        c2fb_temp_132 = Cast(SQLITE_C_INT, local1->onError)
        local7 = c2fb_temp_132
        If (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            sqlite3VdbeResolveLabel(local0, local45)
            Goto c2fb_flow_19
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg8) <> Cast(SQLITE_C_INT, 11ULL))))) Then
            c2fb_temp_133 = Cast(SQLITE_C_INT, arg8)
            local7 = c2fb_temp_133
        Else
            If (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, 11ULL))))) Then
                c2fb_temp_134 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 2ULL))
                local7 = c2fb_temp_134
            End If
        End If
        If local10 Then
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local10->isDoUpdate) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_135 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 4ULL))
                local7 = c2fb_temp_135
            Else
                c2fb_temp_136 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 6ULL))
                local7 = c2fb_temp_136
            End If
        End If
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local5 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local1->pNext = Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, ((local2 = local1)))))))) AndAlso (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, 5ULL))))))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)) = (Cast(sqlite3_uint64, (local3->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &H00002000ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = CPtr(SqliteTrigger Ptr, sqlite3TriggersExist(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), Cast(SQLITE_C_INT, 129ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)))))))))))))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)) = (Cast(sqlite3_uint64, (local3->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &H00004000ULL))))))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = arg1->u.tab.pFKey)))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = CPtr(SqliteFKey Ptr, sqlite3FkReferences(CPtr(Any Ptr, arg1))))))))))))))))))))) Then
            sqlite3VdbeResolveLabel(local0, local45)
            Goto c2fb_flow_19
        End If
        ' empty C statement
        c2fb_temp_137 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp4Int(local0, Cast(SQLITE_C_INT, 27ULL), local44, local45, local42, local1->nKeyCol))
        local46 = c2fb_temp_137
        ' empty C statement
        c2fb_temp_138 = Cast(SQLITE_C_INT, IIf((-Cast(SQLITE_C_INT, ((local1 = local2)))), local42, sqlite3GetTempRange(CPtr(Any Ptr, arg0), local9)))
        local43 = c2fb_temp_138
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local11) OrElse (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, 5ULL))))))))) Then
            If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 144ULL), local44, local43)
                If local11 Then
                    sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 54ULL), local43, local45, arg6)
                    sqlite3VdbeChangeP5(local0, Cast(SQLITE_C_INT, &H90ULL))
                    ' empty C statement
                End If
            Else
                ' C automatic storage declaration
                If (-Cast(SQLITE_C_INT, ((local1 <> local2)))) Then
                    c2fb_temp_139 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    local4 = c2fb_temp_139
                    While (-Cast(SQLITE_C_INT, ((local4 < Cast(SQLITE_C_INT, local2->nKeyCol)))))
                        ' C unused-parameter annotation
                        c2fb_temp_141 = Cast(SQLITE_C_INT, sqlite3TableColumnToIndex(CPtr(Any Ptr, local1), local2->aiColumn[local4]))
                        local50 = c2fb_temp_141
                        sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 96ULL), local44, local50, Cast(SQLITE_C_INT, (local43 + local4)))
                        ' empty C statement
                    c2fb_flow_23:
                        c2fb_temp_140 = local4
                        local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_140 + 1)))
                    Wend
                    c2fb_flow_22:
                End If
                If local11 Then
                    local51 = Cast(SQLITE_C_INT, (sqlite3VdbeCurrentAddr(local0) + Cast(SQLITE_C_INT, local2->nKeyCol)))
                    local52 = Cast(SQLITE_C_INT, 53ULL)
                    local53 = (IIf(((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, (local1)->flags) Shr 0) And Cast(SQLITE_C_UINT, &H3ULL))) = Cast(SQLITE_C_INT, 2ULL)))))), local42, local43))
                    c2fb_temp_142 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    local4 = c2fb_temp_142
                    While (-Cast(SQLITE_C_INT, ((local4 < Cast(SQLITE_C_INT, local2->nKeyCol)))))
                        local54 = CPtr(ZString Ptr, CPtr(sqlite3CollSeq Ptr, sqlite3LocateCollSeq(CPtr(Any Ptr, arg0), CPtr(Const ZString Ptr Ptr, local2->azColl)[local4])))
                        c2fb_temp_144 = Cast(SQLITE_C_INT, local2->aiColumn[local4])
                        local50 = c2fb_temp_144
                        ' C unused-parameter annotation
                        If (-Cast(SQLITE_C_INT, ((local4 = (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local2->nKeyCol) - Cast(SQLITE_C_INT, 1ULL)))))))) Then
                            c2fb_temp_145 = Cast(SQLITE_C_INT, local45)
                            local51 = c2fb_temp_145
                            c2fb_temp_146 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 54ULL))
                            local52 = c2fb_temp_146
                        End If
                        c2fb_temp_147 = Cast(SQLITE_C_INT, sqlite3TableColumnToStorage(CPtr(Any Ptr, arg1), local50))
                        local50 = c2fb_temp_147
                        sqlite3VdbeAddOp4(local0, local52, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (arg6 + Cast(SQLITE_C_INT, 1ULL))) + local50)), local51, Cast(SQLITE_C_INT, (local53 + local4)), CPtr(Const ZString Ptr, local54), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 2ULL)))))
                        sqlite3VdbeChangeP5(local0, Cast(SQLITE_C_INT, &H90ULL))
                        ' empty C statement
                        ' empty C statement
                    c2fb_flow_25:
                        c2fb_temp_143 = local4
                        local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_143 + 1)))
                    Wend
                    c2fb_flow_24:
                End If
            End If
        End If
        c2fb_temp_148 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (sqlite3VdbeCurrentAddr(local0) - local46)))
        local47 = c2fb_temp_148
        ' C unused-parameter annotation
        ' empty C statement
        ' empty C statement
        ' C unused-parameter annotation
        c2fb_switch_value_151 = Cast(sqlite3_uint64, local7)
        c2fb_switch_state_152 = 0
        Select Case c2fb_switch_value_151
            Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 2ULL)), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 3ULL))
                c2fb_switch_state_152 = 1
            Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 6ULL))
                c2fb_switch_state_152 = 2
            Case Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 4ULL))
                c2fb_switch_state_152 = 3
            Case Else
                c2fb_switch_state_152 = 4
        End Select
        Do
            Select Case c2fb_switch_state_152
            Case 0
                Exit Do
            Case 1
                ' empty C statement
                ' empty C statement
                ' empty C statement
                sqlite3UniqueConstraint(CPtr(Any Ptr, arg0), local7, CPtr(Any Ptr, local1))
                Goto c2fb_flow_26
                c2fb_switch_state_152 = 0
            Case 2
                sqlite3UpsertDoUpdate(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg12), CPtr(Any Ptr, arg1), CPtr(Any Ptr, local1), Cast(SQLITE_C_INT, (arg4 + local5)))
                ' C switch fallthrough annotation
                c2fb_switch_state_152 = 3
            Case 3
                ' empty C statement
                sqlite3VdbeGoto(local0, arg9)
                Goto c2fb_flow_26
                c2fb_switch_state_152 = 0
            Case 4
                ' C unused-parameter annotation
                If local17 Then
                    sqlite3MultiWrite(CPtr(Any Ptr, arg0))
                    c2fb_temp_149 = local21
                    local21 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_149 + 1)))
                End If
                If (-Cast(SQLITE_C_INT, ((local20 AndAlso local11)))) Then
                    sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 169ULL), arg3)
                End If
                sqlite3GenerateRowDelete(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), CPtr(Any Ptr, local20), arg3, arg4, local43, local9, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, 5ULL), (IIf((-Cast(SQLITE_C_INT, ((local1 = local2)))), Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, &O0ULL))), local44)
                If (-Cast(SQLITE_C_INT, ((local20 AndAlso local11)))) Then
                    sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 170ULL), arg3)
                End If
                c2fb_temp_150 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                local8 = c2fb_temp_150
                Goto c2fb_flow_26
                c2fb_switch_state_152 = 0
            End Select
        Loop
        c2fb_flow_26:
        If local17 Then
            ' C automatic storage declaration
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 88ULL), local17, Cast(SQLITE_C_INT, 1ULL))
            c2fb_temp_153 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp0(local0, Cast(SQLITE_C_INT, 9ULL)))
            local55 = c2fb_temp_153
            ' empty C statement
            sqlite3VdbeResolveLabel(local0, local19)
            c2fb_temp_154 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
            local19 = c2fb_temp_154
            If CPtr(SqliteExpr Ptr, local1->pPartIdxWhere) Then
                sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 51ULL), Cast(SQLITE_C_INT, (local42 - Cast(SQLITE_C_INT, 1ULL))), local19)
                ' empty C statement
            End If
            While (-Cast(SQLITE_C_INT, ((local47 > Cast(SQLITE_C_INT, &O0ULL)))))
                ' C automatic storage declaration
                c2fb_temp_155 = (*CPtr(SqliteVdbeOp Ptr, sqlite3VdbeGetOp(local0, local46)))
                local56 = c2fb_temp_155
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local56.opcode) <> Cast(SQLITE_C_INT, 144ULL))))) OrElse Cast(SQLITE_C_INT, local11))))) Then
                    ' C automatic storage declaration
                    ' C automatic storage declaration
                    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, sqlite3OpcodeProperty(local56.opcode)) And Cast(SQLITE_C_INT, &H01ULL))) Then
                        c2fb_temp_156 = Cast(SQLITE_C_INT, local19)
                        local57 = c2fb_temp_156
                    Else
                        c2fb_temp_157 = Cast(SQLITE_C_INT, local56.p2)
                        local57 = c2fb_temp_157
                    End If
                    c2fb_temp_158 = CPtr(Const ZString Ptr, IIf((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local56.p4type) = (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 3ULL)))))))), (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (local56.p4.i))))), CPtr(Any Ptr, local56.p4.z)))
                    local58 = c2fb_temp_158
                    sqlite3VdbeAddOp4(local0, local56.opcode, local56.p1, local57, local56.p3, local58, local56.p4type)
                    sqlite3VdbeChangeP5(local0, local56.p5)
                    ' empty C statement
                End If
                c2fb_temp_159 = local47
                local47 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_159 - 1)))
                c2fb_temp_160 = local46
                local46 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_160 + 1)))
            c2fb_flow_28:
            Wend
            c2fb_flow_27:
            sqlite3UniqueConstraint(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 2ULL), CPtr(Any Ptr, local1))
            sqlite3VdbeJumpHere(local0, local55)
        End If
        sqlite3VdbeResolveLabel(local0, local45)
        If (-Cast(SQLITE_C_INT, ((local43 <> local42)))) Then
            sqlite3ReleaseTempRange(CPtr(Any Ptr, arg0), local43, local9)
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local10 AndAlso local13)))) AndAlso sqlite3UpsertNextIsIPK(CPtr(Any Ptr, local10)))))) Then
            sqlite3VdbeGoto(local0, Cast(SQLITE_C_INT, (local14 + Cast(SQLITE_C_INT, 1ULL))))
            sqlite3VdbeJumpHere(local0, local13)
            c2fb_temp_161 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local13 = c2fb_temp_161
        End If
    c2fb_flow_19:
        c2fb_temp_114 = CPtr(SqliteIndex Ptr, indexIteratorNext(CPtr(SqliteIndexIterator Ptr, @(local22)), CPtr(SQLITE_C_INT Ptr, @(local5))))
        local1 = c2fb_temp_114
    Wend
    c2fb_flow_18:
    If local15 Then
        sqlite3VdbeGoto(local0, local15)
        ' empty C statement
        ' C unused-parameter annotation
        sqlite3VdbeJumpHere(local0, local16)
    End If
    ' empty C statement
    ' C unused-parameter annotation
    If local21 Then
        sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 17ULL), local17, local19)
        ' empty C statement
        If (-Cast(SQLITE_C_INT, (local2 = 0))) Then
            If local11 Then
                sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 54ULL), arg5, local18, arg6)
                sqlite3VdbeChangeP5(local0, Cast(SQLITE_C_INT, &H90ULL))
                ' empty C statement
            End If
            sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 31ULL), arg3, local18, arg5)
            ' empty C statement
            sqlite3RowidConstraint(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 2ULL), CPtr(Any Ptr, arg1))
        Else
            sqlite3VdbeGoto(local0, local18)
        End If
    End If
    If local17 Then
        sqlite3VdbeResolveLabel(local0, local19)
    End If
    If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
        local59 = arg2[local5]
        sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 99ULL), Cast(SQLITE_C_INT, (arg5 + Cast(SQLITE_C_INT, 1ULL))), arg1->nNVCol, local59)
        ' empty C statement
        If (-Cast(SQLITE_C_INT, (local12 = 0))) Then
            sqlite3TableAffinity(CPtr(Any Ptr, local0), CPtr(Any Ptr, arg1), Cast(SQLITE_C_INT, &O0ULL))
        End If
    End If
    c2fb_temp_162 = CPtr(SQLITE_C_INT Ptr, @((*arg10)))
    c2fb_temp_163 = Cast(SQLITE_C_INT, local8)
    (*c2fb_temp_162) = c2fb_temp_163
    ' empty C statement
End Sub

' c2fb skipped sqlite3CompleteInsertion: FreeBASIC body already exists
' c2fb skipped sqlite3OpenTableAndIndices: FreeBASIC body already exists
Private Function xferCompatibleIndex CDecl Alias "xferCompatibleIndex" (ByVal arg0 As SqliteIndex Ptr, ByVal arg1 As SqliteIndex Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->nKeyCol) <> Cast(SQLITE_C_INT, arg1->nKeyCol))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->nColumn) <> Cast(SQLITE_C_INT, arg1->nColumn))))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->onError) <> Cast(SQLITE_C_INT, arg1->onError))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((local0 < Cast(SQLITE_C_INT, arg1->nKeyCol)))))
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->aiColumn[local0]) <> Cast(SQLITE_C_INT, arg0->aiColumn[local0]))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->aiColumn[local0]) = (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 2ULL)))))))) Then
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, ((sqlite3ExprCompare(Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, arg1->aColExpr)->a(local0).pExpr), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, arg0->aColExpr)->a(local0).pExpr), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                Return Cast(SQLITE_C_INT, &O0ULL)
            End If
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(UByte Ptr, arg1->aSortOrder)[local0]) <> Cast(SQLITE_C_INT, CPtr(UByte Ptr, arg0->aSortOrder)[local0]))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        If (-Cast(SQLITE_C_INT, ((sqlite3_stricmp(CPtr(Const ZString Ptr Ptr, arg1->azColl)[local0], CPtr(Const ZString Ptr Ptr, arg0->azColl)[local0]) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
    c2fb_flow_1:
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    Wend
    c2fb_flow_0:
    If sqlite3ExprCompare(Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg1->pPartIdxWhere)), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg0->pPartIdxWhere)), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    Return Cast(SQLITE_C_INT, 1ULL)
End Function

Private Function xferCheckRowid CDecl Alias "xferCheckRowid" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim c2fb_temp_0 As UShort Ptr
    Dim c2fb_temp_1 As UShort

    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 168ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->iColumn) < Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        c2fb_temp_0 = CPtr(UShort Ptr, @(arg0->eCode))
        c2fb_temp_1 = Cast(UShort, Cast(SQLITE_C_INT, 1ULL))
        (*c2fb_temp_0) = c2fb_temp_1
        Return Cast(SQLITE_C_INT, 2ULL)
    Else
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
End Function

Private Function xferCompatibleCheck CDecl Alias "xferCompatibleCheck" (ByVal arg0 As SqliteTable Ptr, ByVal arg1 As SqliteTable Ptr) As SQLITE_C_INT
    Dim local0 As SqliteWalker
    Dim c2fb_temp_0 As Any Ptr
    Dim c2fb_temp_1 As SqliteWalkerExprCallback Ptr
    Dim c2fb_temp_2 As c2fb_callback_85

    If sqlite3ExprListCompare(CPtr(Any Ptr, CPtr(SqliteExprList Ptr, arg1->pCheck)), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, arg0->pCheck)), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->iPKey) < Cast(SQLITE_C_INT, &O0ULL))))) Then
        ' C automatic storage declaration
        c2fb_temp_0 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local0))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteWalker))))
        c2fb_temp_1 = CPtr(SqliteWalkerExprCallback Ptr, @(local0.xExprCallback))
        c2fb_temp_2 = CPtr(c2fb_callback_85, ProcPtr(xferCheckRowid))
        (*c2fb_temp_1) = Cast(SqliteWalkerExprCallback, c2fb_temp_2)
        c2fb_temp_2 = CPtr(c2fb_callback_85, (*c2fb_temp_1))
        sqlite3WalkExprList(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local0))), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, arg0->pCheck)))
        If local0.eCode Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
    End If
    Return Cast(SQLITE_C_INT, 1ULL)
End Function

Private Function xferOptimization CDecl Alias "xferOptimization" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteTable Ptr, ByVal arg2 As SqliteSelect Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As sqlite3 Ptr
    Dim local1 As SqliteExprList Ptr
    Dim local2 As SqliteTable Ptr
    Dim local3 As SqliteIndex Ptr
    Dim local4 As SqliteIndex Ptr
    Dim local5 As SqliteSrcItem Ptr
    Dim local6 As SQLITE_C_INT
    Dim local7 As SQLITE_C_INT
    Dim local8 As SQLITE_C_INT
    Dim local9 As SQLITE_C_INT
    Dim local10 As SQLITE_C_INT
    Dim local11 As SQLITE_C_INT
    Dim local12 As SQLITE_C_INT
    Dim local13 As SQLITE_C_INT
    Dim local14 As SqliteVdbe Ptr
    Dim local15 As SQLITE_C_INT
    Dim local16 As SQLITE_C_INT
    Dim local17 As SQLITE_C_INT
    Dim local18 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SqliteExprList Ptr
    Dim c2fb_temp_3 As SqliteSrcItem Ptr
    Dim c2fb_temp_4 As SqliteTable Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim local19 As SQLITE_C_UINT
    Dim local20 As SQLITE_C_UINT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim local21 As SqliteColumn Ptr
    Dim local22 As SqliteColumn Ptr
    Dim local23 As SqliteExpr Ptr
    Dim local24 As SqliteExpr Ptr
    Dim c2fb_temp_9 As SqliteIndex Ptr
    Dim c2fb_temp_10 As SqliteIndex Ptr
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SqliteIndex Ptr
    Dim c2fb_temp_13 As SqliteIndex Ptr
    Dim local25 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim local26 As SqliteColumn Ptr
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SqliteVdbe Ptr
    Dim c2fb_temp_18 As SQLITE_C_INT Ptr
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As SQLITE_C_INT Ptr
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim c2fb_temp_23 As SQLITE_C_INT
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As SQLITE_C_INT
    Dim c2fb_temp_26 As SQLITE_C_INT
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim c2fb_temp_28 As SQLITE_C_INT
    Dim local27 As UByte
    Dim c2fb_temp_29 As SQLITE_C_INT
    Dim c2fb_temp_30 As SQLITE_C_INT
    Dim c2fb_temp_31 As SQLITE_C_INT
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As SQLITE_C_INT
    Dim c2fb_temp_34 As UByte
    Dim c2fb_temp_35 As UByte
    Dim c2fb_temp_36 As SqliteIndex Ptr
    Dim c2fb_temp_37 As SqliteIndex Ptr
    Dim local28 As UByte
    Dim c2fb_temp_38 As SqliteIndex Ptr
    Dim c2fb_temp_39 As SqliteIndex Ptr
    Dim c2fb_temp_40 As SQLITE_C_INT
    Dim c2fb_temp_41 As SQLITE_C_INT
    Dim c2fb_temp_42 As SQLITE_C_INT
    Dim local29 As Const ZString Ptr
    Dim c2fb_temp_43 As UByte
    Dim c2fb_temp_44 As UByte

    local0 = arg0->db
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local12 = Cast(SQLITE_C_INT, &O0ULL)
    local13 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    local16 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((CPtr(SqliteWithRecord Ptr, arg0->pWith) OrElse CPtr(SqliteWithRecord Ptr, arg2->pWith))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (arg1)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((arg3 = Cast(SQLITE_C_INT, 11ULL))))) Then
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->iPKey) >= Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_0 = Cast(SQLITE_C_INT, arg1->keyConf)
            arg3 = c2fb_temp_0
        End If
        If (-Cast(SQLITE_C_INT, ((arg3 = Cast(SQLITE_C_INT, 11ULL))))) Then
            c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 2ULL))
            arg3 = c2fb_temp_1
        End If
    End If
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((arg2->pSrc->nSrc <> Cast(SQLITE_C_INT, 1ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg2->pSrc->a(Cast(SQLITE_C_INT, &O0ULL)).fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If arg2->pWhere Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If arg2->pOrderBy Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If arg2->pGroupBy Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If arg2->pLimit Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If arg2->pPrior Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If Cast(SQLITE_C_UINT, (arg2->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000001ULL)))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_2 = arg2->pEList
    local1 = c2fb_temp_2
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((local1->nExpr <> Cast(SQLITE_C_INT, 1ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr->op) <> Cast(SQLITE_C_INT, 180ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_3 = CPtr(SqliteSrcItem Ptr, (@arg2->pSrc->a(0)))
    local5 = c2fb_temp_3
    c2fb_temp_4 = CPtr(SqliteTable Ptr, sqlite3LocateTableItem(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, local5)))
    local2 = c2fb_temp_4
    If (-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local2->tnum = arg1->tnum)))) AndAlso (-Cast(SQLITE_C_INT, ((CPtr(SqliteSchema Ptr, local2->pSchema) = CPtr(SqliteSchema Ptr, arg1->pSchema))))))))) Then
        ' empty C statement
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) <> ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local2)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local2)->eTabType) = Cast(SQLITE_C_INT, &O0ULL)))))) = 0))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->nCol) <> Cast(SQLITE_C_INT, local2->nCol))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->iPKey) <> Cast(SQLITE_C_INT, local2->iPKey))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00010000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local2->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00010000ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local6 = c2fb_temp_5
        While (-Cast(SQLITE_C_INT, ((local6 < Cast(SQLITE_C_INT, arg1->nCol)))))
            local19 = Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg1->aCol[local6].flags) Shr 4) And Cast(SQLITE_C_UINT, &HFULL)))
            local20 = Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local2->aCol[local6].flags) Shr 4) And Cast(SQLITE_C_UINT, &HFULL)))
            If (-Cast(SQLITE_C_INT, ((local19 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))) Then
                Goto c2fb_flow_1
            End If
            If (-Cast(SQLITE_C_INT, ((local19 = local20)))) Then
                Goto c2fb_flow_1
            End If
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local19 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 3ULL)))))) AndAlso (-Cast(SQLITE_C_INT, ((local20 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL)))))))))) Then
                Goto c2fb_flow_1
            End If
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local19 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL)))))) AndAlso (-Cast(SQLITE_C_INT, ((local20 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 3ULL)))))))))) Then
                Goto c2fb_flow_1
            End If
            Return Cast(SQLITE_C_INT, &O0ULL)
        c2fb_flow_1:
            c2fb_temp_6 = local6
            local6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 + 1)))
        Wend
        c2fb_flow_0:
    End If
    c2fb_temp_7 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local6 = c2fb_temp_7
    While (-Cast(SQLITE_C_INT, ((local6 < Cast(SQLITE_C_INT, arg1->nCol)))))
        local21 = CPtr(SqliteColumn Ptr, @(arg1->aCol[local6]))
        local22 = CPtr(SqliteColumn Ptr, @(local2->aCol[local6]))
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local21->colFlags) And Cast(SQLITE_C_INT, &H0060ULL)))) <> (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local22->colFlags) And Cast(SQLITE_C_INT, &H0060ULL)))))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local21->colFlags) And Cast(SQLITE_C_INT, &H0060ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            If (-Cast(SQLITE_C_INT, ((sqlite3ExprCompare(Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, sqlite3ColumnExpr(CPtr(Any Ptr, local2), CPtr(Any Ptr, local22)))), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, sqlite3ColumnExpr(CPtr(Any Ptr, arg1), CPtr(Any Ptr, local21)))), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                ' empty C statement
                ' empty C statement
                Return Cast(SQLITE_C_INT, &O0ULL)
            End If
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local21->affinity) <> Cast(SQLITE_C_INT, local22->affinity))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        If (-Cast(SQLITE_C_INT, ((sqlite3_stricmp(CPtr(Const ZString Ptr, sqlite3ColumnColl(CPtr(Any Ptr, local21))), CPtr(Const ZString Ptr, sqlite3ColumnColl(CPtr(Any Ptr, local22)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local21->flags) Shr 0) And Cast(SQLITE_C_UINT, &HFULL))) AndAlso (-Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local22->flags) Shr 0) And Cast(SQLITE_C_UINT, &HFULL))) = 0))))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local21->colFlags) And Cast(SQLITE_C_INT, &H0060ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local6 > Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            local23 = CPtr(SqliteExpr Ptr, sqlite3ColumnExpr(CPtr(Any Ptr, arg1), CPtr(Any Ptr, local21)))
            local24 = CPtr(SqliteExpr Ptr, sqlite3ColumnExpr(CPtr(Any Ptr, local2), CPtr(Any Ptr, local22)))
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((local23 = Cast(SQLITE_C_INT, &O0ULL)))))) <> ((-Cast(SQLITE_C_INT, ((local24 = Cast(SQLITE_C_INT, &O0ULL)))))))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local23 <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((c2fb_crt_strcmp(CPtr(Const ZString Ptr, CPtr(ZString Ptr, local23->u.zToken)), CPtr(Const ZString Ptr, CPtr(ZString Ptr, local24->u.zToken))) <> Cast(SQLITE_C_INT, &O0ULL)))))))))))))) Then
                Return Cast(SQLITE_C_INT, &O0ULL)
            End If
        End If
    c2fb_flow_3:
        c2fb_temp_8 = local6
        local6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_8 + 1)))
    Wend
    c2fb_flow_2:
    c2fb_temp_9 = CPtr(SqliteIndex Ptr, arg1->pIndex)
    local4 = c2fb_temp_9
    While local4
        If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local4)->onError) <> Cast(SQLITE_C_INT, &O0ULL)))))) Then
            c2fb_temp_11 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
            local16 = c2fb_temp_11
        End If
        c2fb_temp_12 = CPtr(SqliteIndex Ptr, local2->pIndex)
        local3 = c2fb_temp_12
        While local3
            If xferCompatibleIndex(local4, local3) Then
                Goto c2fb_flow_6
            End If
        c2fb_flow_7:
            c2fb_temp_13 = local3->pNext
            local3 = c2fb_temp_13
        Wend
        c2fb_flow_6:
        If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local3->tnum = local4->tnum)))) AndAlso (-Cast(SQLITE_C_INT, ((CPtr(SqliteSchema Ptr, local2->pSchema) = CPtr(SqliteSchema Ptr, arg1->pSchema))))))))) AndAlso (-Cast(SQLITE_C_INT, ((sqlite3FaultSim(Cast(SQLITE_C_INT, 411ULL)) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
    c2fb_flow_5:
        c2fb_temp_10 = local4->pNext
        local4 = c2fb_temp_10
    Wend
    c2fb_flow_4:
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((CPtr(SqliteExprList Ptr, arg1->pCheck) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local0->mDbFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0004ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, (xferCompatibleCheck(arg1, local2) = 0))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local0->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &H00004000ULL))))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, ((arg1->u.tab.pFKey <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local0->flags And (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, (Cast(SQLITE_C_INT, &H00001ULL))) Shl Cast(SQLITE_C_INT, 32ULL))))))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If CPtr(c2fb_callback_3, local0->xAuth) Then
        local25 = sqlite3SchemaToIndex(CPtr(Any Ptr, local0), CPtr(Any Ptr, CPtr(SqliteSchema Ptr, local2->pSchema)))
        If sqlite3AuthCheck(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 21ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        c2fb_temp_14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local6 = c2fb_temp_14
        While (-Cast(SQLITE_C_INT, ((local6 < Cast(SQLITE_C_INT, local2->nCol)))))
            local26 = CPtr(SqliteColumn Ptr, @(local2->aCol[local6]))
            If sqlite3AuthReadCol(CPtr(Any Ptr, arg0), CPtr(Const ZString Ptr, local2->zName), CPtr(Const ZString Ptr, local26->zCnName), local25) Then
                Return Cast(SQLITE_C_INT, &O0ULL)
            End If
        c2fb_flow_9:
            c2fb_temp_15 = local6
            local6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_15 + 1)))
        Wend
        c2fb_flow_8:
    End If
#ifdef SQLITE_TEST
    sqlite3_xferopt_count += 1
#endif
    c2fb_temp_16 = Cast(SQLITE_C_INT, sqlite3SchemaToIndex(CPtr(Any Ptr, local0), CPtr(Any Ptr, CPtr(SqliteSchema Ptr, local2->pSchema))))
    local7 = c2fb_temp_16
    c2fb_temp_17 = CPtr(SqliteVdbe Ptr, sqlite3GetVdbe(CPtr(Any Ptr, arg0)))
    local14 = c2fb_temp_17
    sqlite3CodeVerifySchema(CPtr(Any Ptr, arg0), local7)
    c2fb_temp_18 = CPtr(SQLITE_C_INT Ptr, @(arg0->nTab))
    c2fb_temp_19 = (*c2fb_temp_18)
    (*c2fb_temp_18) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_19 + 1)))
    c2fb_temp_20 = Cast(SQLITE_C_INT, c2fb_temp_19)
    local8 = c2fb_temp_20
    c2fb_temp_21 = CPtr(SQLITE_C_INT Ptr, @(arg0->nTab))
    c2fb_temp_22 = (*c2fb_temp_21)
    (*c2fb_temp_21) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_22 + 1)))
    c2fb_temp_23 = Cast(SQLITE_C_INT, c2fb_temp_22)
    local9 = c2fb_temp_23
    c2fb_temp_24 = Cast(SQLITE_C_INT, autoIncBegin(arg0, arg4, arg1))
    local15 = c2fb_temp_24
    c2fb_temp_25 = Cast(SQLITE_C_INT, sqlite3GetTempReg(CPtr(Any Ptr, arg0)))
    local17 = c2fb_temp_25
    sqlite3VdbeAddOp2(local14, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), local17)
    c2fb_temp_26 = Cast(SQLITE_C_INT, sqlite3GetTempReg(CPtr(Any Ptr, arg0)))
    local18 = c2fb_temp_26
    sqlite3OpenTable(CPtr(Any Ptr, arg0), local9, arg4, CPtr(Any Ptr, arg1), Cast(SQLITE_C_INT, 116ULL))
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local0->mDbFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0004ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->iPKey) < Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((CPtr(SqliteIndex Ptr, arg1->pIndex) <> Cast(SQLITE_C_INT, &O0ULL)))))))))) OrElse local16)))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg3 <> Cast(SQLITE_C_INT, 2ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((arg3 <> Cast(SQLITE_C_INT, 1ULL))))))))))))))))))) Then
        c2fb_temp_27 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp2(local14, Cast(SQLITE_C_INT, 36ULL), local9, Cast(SQLITE_C_INT, &O0ULL)))
        local10 = c2fb_temp_27
        ' empty C statement
        c2fb_temp_28 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp0(local14, Cast(SQLITE_C_INT, 9ULL)))
        local12 = c2fb_temp_28
        sqlite3VdbeJumpHere(local14, local10)
    End If
    If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local2)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
        ' C automatic storage declaration
        sqlite3OpenTable(CPtr(Any Ptr, arg0), local8, local7, CPtr(Any Ptr, local2), Cast(SQLITE_C_INT, 114ULL))
        c2fb_temp_29 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp2(local14, Cast(SQLITE_C_INT, 36ULL), local8, Cast(SQLITE_C_INT, &O0ULL)))
        local13 = c2fb_temp_29
        ' empty C statement
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->iPKey) >= Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_30 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp2(local14, Cast(SQLITE_C_INT, 137ULL), local8, local18))
            local10 = c2fb_temp_30
            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local0->mDbFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0004ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                ' empty C statement
                c2fb_temp_31 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp3(local14, Cast(SQLITE_C_INT, 31ULL), local9, Cast(SQLITE_C_INT, &O0ULL), local18))
                local11 = c2fb_temp_31
                ' empty C statement
                sqlite3RowidConstraint(CPtr(Any Ptr, arg0), arg3, CPtr(Any Ptr, arg1))
                sqlite3VdbeJumpHere(local14, local11)
            End If
            autoIncStep(arg0, local15, local18)
        Else
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((CPtr(SqliteIndex Ptr, arg1->pIndex) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, (local0->mDbFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0008ULL))))) = 0))))))) Then
                c2fb_temp_32 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp2(local14, Cast(SQLITE_C_INT, 129ULL), local9, local18))
                local10 = c2fb_temp_32
            Else
                c2fb_temp_33 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp2(local14, Cast(SQLITE_C_INT, 137ULL), local8, local18))
                local10 = c2fb_temp_33
                ' C unused-parameter annotation
            End If
        End If
        If Cast(SQLITE_C_UINT, (local0->mDbFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0004ULL)))) Then
            sqlite3VdbeAddOp1(local14, Cast(SQLITE_C_INT, 139ULL), local9)
            c2fb_temp_34 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H10ULL))) Or Cast(SQLITE_C_INT, &H80ULL))))
            local27 = c2fb_temp_34
        Else
            c2fb_temp_35 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H01ULL) Or Cast(SQLITE_C_INT, &H20ULL))) Or Cast(SQLITE_C_INT, &H08ULL))) Or Cast(SQLITE_C_INT, &H80ULL))))
            local27 = c2fb_temp_35
        End If
#ifdef SQLITE_ENABLE_PREUPDATE_HOOK
        If (local0->mDbFlags And DBFLAG_Vacuum) = 0 Then
            sqlite3VdbeAddOp3(local14, Cast(SQLITE_C_INT, 136ULL), _
                              local8, local17, 1)
            local27 = Cast(UByte, _
                Cast(SQLITE_C_INT, local27) And _
                Not Cast(SQLITE_C_INT, OPFLAG_PREFORMAT))
        Else
            sqlite3VdbeAddOp3(local14, Cast(SQLITE_C_INT, 131ULL), _
                              local9, local8, local18)
        End If
#else
        sqlite3VdbeAddOp3(local14, Cast(SQLITE_C_INT, 131ULL), local9, local8, local18)
#endif
        sqlite3VdbeAddOp3(local14, Cast(SQLITE_C_INT, 130ULL), local9, local17, local18)
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local0->mDbFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0004ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            sqlite3VdbeChangeP4(local14, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), CPtr(Const ZString Ptr, CPtr(ZString Ptr, arg1)), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 5ULL)))))
        End If
        sqlite3VdbeChangeP5(local14, local27)
        sqlite3VdbeAddOp2(local14, Cast(SQLITE_C_INT, 40ULL), local8, local10)
        ' empty C statement
        sqlite3VdbeAddOp2(local14, Cast(SQLITE_C_INT, 124ULL), local8, Cast(SQLITE_C_INT, &O0ULL))
        sqlite3VdbeAddOp2(local14, Cast(SQLITE_C_INT, 124ULL), local9, Cast(SQLITE_C_INT, &O0ULL))
    Else
        sqlite3TableLock(CPtr(Any Ptr, arg0), arg4, arg1->tnum, Cast(SQLITE_C_INT, 1ULL), CPtr(Const ZString Ptr, arg1->zName))
        sqlite3TableLock(CPtr(Any Ptr, arg0), local7, local2->tnum, Cast(SQLITE_C_INT, &O0ULL), CPtr(Const ZString Ptr, local2->zName))
    End If
    c2fb_temp_36 = CPtr(SqliteIndex Ptr, arg1->pIndex)
    local4 = c2fb_temp_36
    While local4
        local28 = Cast(SQLITE_C_INT, &O0ULL)
        c2fb_temp_38 = CPtr(SqliteIndex Ptr, local2->pIndex)
        local3 = c2fb_temp_38
        While (local3)
            If xferCompatibleIndex(local4, local3) Then
                Goto c2fb_flow_12
            End If
        c2fb_flow_13:
            c2fb_temp_39 = local3->pNext
            local3 = c2fb_temp_39
        Wend
        c2fb_flow_12:
        ' C unused-parameter annotation
        sqlite3VdbeAddOp3(local14, Cast(SQLITE_C_INT, 114ULL), local8, local3->tnum, local7)
        sqlite3VdbeSetP4KeyInfo(arg0, local3)
        ' empty C statement
        sqlite3VdbeAddOp3(local14, Cast(SQLITE_C_INT, 116ULL), local9, local4->tnum, arg4)
        sqlite3VdbeSetP4KeyInfo(arg0, local4)
        sqlite3VdbeChangeP5(local14, Cast(SQLITE_C_INT, &H01ULL))
        ' empty C statement
        c2fb_temp_40 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp2(local14, Cast(SQLITE_C_INT, 36ULL), local8, Cast(SQLITE_C_INT, &O0ULL)))
        local10 = c2fb_temp_40
        ' empty C statement
        If Cast(SQLITE_C_UINT, (local0->mDbFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0004ULL)))) Then
            c2fb_temp_41 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local6 = c2fb_temp_41
            While (-Cast(SQLITE_C_INT, ((local6 < Cast(SQLITE_C_INT, local3->nColumn)))))
                local29 = CPtr(Const ZString Ptr Ptr, local3->azColl)[local6]
                If sqlite3_stricmp(sqlite3StrBINARYName(), local29) Then
                    Goto c2fb_flow_14
                End If
            c2fb_flow_15:
                c2fb_temp_42 = local6
                local6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_42 + 1)))
            Wend
            c2fb_flow_14:
            If (-Cast(SQLITE_C_INT, ((local6 = Cast(SQLITE_C_INT, local3->nColumn))))) Then
                c2fb_temp_43 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H10ULL) Or Cast(SQLITE_C_INT, &H80ULL))))
                local28 = c2fb_temp_43
                sqlite3VdbeAddOp1(local14, Cast(SQLITE_C_INT, 139ULL), local9)
                sqlite3VdbeAddOp2(local14, Cast(SQLITE_C_INT, 131ULL), local9, local8)
            End If
        Else
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local2)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local4->flags) Shr 0) And Cast(SQLITE_C_UINT, &H3ULL))) = Cast(SQLITE_C_INT, 2ULL))))))))) Then
                c2fb_temp_44 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local28) Or Cast(SQLITE_C_INT, &H01ULL))))
                local28 = c2fb_temp_44
            End If
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local28) <> (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H10ULL) Or Cast(SQLITE_C_INT, &H80ULL)))))))) Then
            sqlite3VdbeAddOp3(local14, Cast(SQLITE_C_INT, 136ULL), local8, local17, Cast(SQLITE_C_INT, 1ULL))
            ' Index.flags stores SQLITE_IDXTYPE_PRIMARYKEY as 2 in its low bits.
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local0->mDbFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0004ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))))))) AndAlso ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, (local4)->flags) Shr 0) And Cast(SQLITE_C_UINT, &H3ULL))) = Cast(SQLITE_C_INT, 2ULL)))))))))) Then
#ifdef SQLITE_ENABLE_PREUPDATE_HOOK
                codeWithoutRowidPreupdate(arg0, arg1, local9, local17)
#endif
            End If
        End If
        sqlite3VdbeAddOp2(local14, Cast(SQLITE_C_INT, 140ULL), local9, local17)
        sqlite3VdbeChangeP5(local14, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local28) Or Cast(SQLITE_C_INT, &H08ULL))))
        sqlite3VdbeAddOp2(local14, Cast(SQLITE_C_INT, 40ULL), local8, Cast(SQLITE_C_INT, (local10 + Cast(SQLITE_C_INT, 1ULL))))
        ' empty C statement
        sqlite3VdbeJumpHere(local14, local10)
        sqlite3VdbeAddOp2(local14, Cast(SQLITE_C_INT, 124ULL), local8, Cast(SQLITE_C_INT, &O0ULL))
        sqlite3VdbeAddOp2(local14, Cast(SQLITE_C_INT, 124ULL), local9, Cast(SQLITE_C_INT, &O0ULL))
    c2fb_flow_11:
        c2fb_temp_37 = local4->pNext
        local4 = c2fb_temp_37
    Wend
    c2fb_flow_10:
    If local13 Then
        sqlite3VdbeJumpHere(local14, local13)
    End If
    sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local18)
    sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local17)
    If local12 Then
        sqlite3AutoincrementEnd(CPtr(Any Ptr, arg0))
        sqlite3VdbeAddOp2(local14, Cast(SQLITE_C_INT, 72ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL))
        sqlite3VdbeJumpHere(local14, local12)
        sqlite3VdbeAddOp2(local14, Cast(SQLITE_C_INT, 124ULL), local9, Cast(SQLITE_C_INT, &O0ULL))
        Return Cast(SQLITE_C_INT, &O0ULL)
    Else
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
End Function

/' end of sqlite3_bulk_insert_execution.bas '/
