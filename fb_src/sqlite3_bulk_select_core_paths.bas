/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_bulk_select_core_paths.bas

    Purpose:

        Expand and transform compound SELECT query paths.

    Responsibilities:

        - Build output loops and sorter records for SELECT results.
        - Merge compound SELECTs and generate recursive-query paths.
        - Flatten eligible subqueries and push WHERE terms into them.
        - Keep the required private SELECT helpers in one module.
        - Reset aggregate accumulators for simple table-backed aggregate SELECTs.
        - Expose the translated sorter tail to simple table-backed SELECTs.

    This file intentionally does NOT contain:

        - SQL grammar parsing or general name resolution.
        - VDBE opcode dispatch or statement execution.
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
#include once "sqlite3_vdbe_record.bi"
#include once "sqlite3_agginfo_types.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_walk_contexts.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_util_numeric.bi"
#ifdef SQLITE_ALLOW_ROWID_IN_VIEW
Declare Function sqlite3ConfigNoVisibleRowidFlagsValue CDecl _
    Alias "sqlite3ConfigNoVisibleRowidFlagsValue" () As u32
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
Declare Sub sqlite3VdbeExplainPop CDecl Alias "sqlite3VdbeExplainPop" (ByVal arg0 As SqliteParseContext Ptr)

Type c2fb_callback_8 As Sub CDecl(ByVal arg0 As Any Ptr)
Type c2fb_callback_85 As Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT

Declare Sub unsetJoinExpr CDecl Alias "unsetJoinExpr" (ByVal arg0 As SqliteExpr Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT)
Declare Sub innerLoopLoadRow CDecl Alias "innerLoopLoadRow" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteRowLoadInfo Ptr)
Declare Function makeSorterRecord CDecl Alias "makeSorterRecord" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSortContext Ptr, ByVal arg2 As SqliteSelect Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub pushOntoSorter CDecl Alias "pushOntoSorter" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSortContext Ptr, ByVal arg2 As SqliteSelect Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As SQLITE_C_INT)
Declare Sub codeOffset CDecl Alias "codeOffset" (ByVal arg0 As SqliteVdbe Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT)
Declare Function codeDistinct CDecl Alias "codeDistinct" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SqliteExprList Ptr, ByVal arg5 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub fixDistinctOpenEph CDecl Alias "fixDistinctOpenEph" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Declare Sub selectInnerLoop CDecl Alias "selectInnerLoop" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SqliteSortContext Ptr, ByVal arg4 As SqliteDistinctContext Ptr, ByVal arg5 As SqliteSelectDest Ptr, ByVal arg6 As SQLITE_C_INT, ByVal arg7 As SQLITE_C_INT)
Declare Sub explainTempTable CDecl Alias "explainTempTable" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As Const ZString Ptr)
Declare Sub generateSortTail CDecl Alias "generateSortTail" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteSortContext Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SqliteSelectDest Ptr)
Declare Sub computeLimitRegisters CDecl Alias "computeLimitRegisters" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Function multiSelectCollSeq CDecl Alias "multiSelectCollSeq" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SQLITE_C_INT) As sqlite3CollSeq Ptr
Declare Function multiSelectByMergeKeyInfo CDecl Alias "multiSelectByMergeKeyInfo" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SQLITE_C_INT) As sqlite3VdbeKeyInfoPrefix Ptr
Declare Sub generateWithRecursiveQuery CDecl Alias "generateWithRecursiveQuery" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteSelectDest Ptr)
Declare Function hasAnchor CDecl Alias "hasAnchor" (ByVal arg0 As SqliteSelect Ptr) As SQLITE_C_INT
Declare Function unionWithLimitOne CDecl Alias "unionWithLimitOne" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteSelect Ptr) As SQLITE_C_INT
Declare Function multiSelect CDecl Alias "multiSelect" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteSelectDest Ptr) As SQLITE_C_INT
Declare Function generateOutputSubroutine CDecl Alias "generateOutputSubroutine" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteSelectDest Ptr, ByVal arg3 As SqliteSelectDest Ptr, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As sqlite3VdbeKeyInfoPrefix Ptr, ByVal arg7 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function multiSelectByMerge CDecl Alias "multiSelectByMerge" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteSelectDest Ptr) As SQLITE_C_INT
Declare Function substExpr CDecl Alias "substExpr" (ByVal arg0 As SqliteSubstContext Ptr, ByVal arg1 As SqliteExpr Ptr) As SqliteExpr Ptr
Declare Sub substExprList CDecl Alias "substExprList" (ByVal arg0 As SqliteSubstContext Ptr, ByVal arg1 As SqliteExprList Ptr)
Declare Sub substSelect CDecl Alias "substSelect" (ByVal arg0 As SqliteSubstContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Function recomputeColumnsUsedExpr CDecl Alias "recomputeColumnsUsedExpr" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Sub recomputeColumnsUsed CDecl Alias "recomputeColumnsUsed" (ByVal arg0 As SqliteSelect Ptr, ByVal arg1 As SqliteSrcItem Ptr)
Declare Sub srclistRenumberCursors CDecl Alias "srclistRenumberCursors" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT Ptr, ByVal arg2 As SqliteSrcList Ptr, ByVal arg3 As SQLITE_C_INT)
Declare Sub renumberCursorDoMapping CDecl Alias "renumberCursorDoMapping" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SQLITE_C_INT Ptr)
Declare Function renumberCursorsCb CDecl Alias "renumberCursorsCb" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Sub renumberCursors CDecl Alias "renumberCursors" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT Ptr)
Declare Function findLeftmostExprlist CDecl Alias "findLeftmostExprlist" (ByVal arg0 As SqliteSelect Ptr) As SqliteExprList Ptr
Declare Function compoundHasDifferentAffinities CDecl Alias "compoundHasDifferentAffinities" (ByVal arg0 As SqliteSelect Ptr) As SQLITE_C_INT
Declare Function flattenSubquery CDecl Alias "flattenSubquery" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function pushDownWindowCheck CDecl Alias "pushDownWindowCheck" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function pushDownWhereTerms CDecl Alias "pushDownWhereTerms" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteExpr Ptr, ByVal arg3 As SqliteSrcList Ptr, ByVal arg4 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub resetAccumulator CDecl Alias "resetAccumulator" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteAggInfo Ptr)
Declare Sub explainSimpleCount CDecl Alias "explainSimpleCount" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteTable Ptr, ByVal arg2 As SqliteIndex Ptr)
Declare Function countOfViewOptimization CDecl Alias "countOfViewOptimization" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr) As SQLITE_C_INT
Declare Function c2fb_crt_memset CDecl Alias "memset" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_SIZE_T) As Any Ptr
' c2fb skipped __bswap_16: outside the supported subset
' c2fb skipped __bswap_32: outside the supported subset
' c2fb skipped __bswap_64: outside the supported subset
' c2fb skipped __uint16_identity: outside the supported subset
' c2fb skipped __uint32_identity: outside the supported subset
' c2fb skipped __uint64_identity: outside the supported subset
' c2fb skipped sqlite3IsBinary: FreeBASIC body already exists
' c2fb skipped clearSelect: outside the supported subset
' c2fb skipped sqlite3SelectDestInit: FreeBASIC body already exists
' c2fb skipped sqlite3SelectNew: FreeBASIC body already exists
' c2fb skipped sqlite3SelectDelete: FreeBASIC body already exists
' c2fb skipped sqlite3SelectDeleteGeneric: FreeBASIC body already exists
' c2fb skipped findRightmost: outside the supported subset
' c2fb skipped sqlite3JoinType: outside the supported subset
' c2fb skipped sqlite3ColumnIndex: FreeBASIC body already exists
' c2fb skipped sqlite3SrcItemColumnUsed: FreeBASIC body already exists
' c2fb skipped tableAndColumnIndex: outside the supported subset
' c2fb skipped sqlite3SetJoinExpr: FreeBASIC body already exists

/' ------------------------------------------------------------------------- '/
/' Translated SELECT result and compound-query paths '/
/' ------------------------------------------------------------------------- '/
Private Sub unsetJoinExpr CDecl Alias "unsetJoinExpr" (ByVal arg0 As SqliteExpr Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT)
    Dim c2fb_temp_0 As u32 Ptr
    Dim c2fb_temp_1 As SQLITE_C_UINT
    Dim c2fb_temp_2 As u32 Ptr
    Dim c2fb_temp_3 As SQLITE_C_UINT
    Dim c2fb_temp_4 As u32 Ptr
    Dim c2fb_temp_5 As SQLITE_C_UINT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SqliteExpr Ptr

    While arg0
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg1 < Cast(SQLITE_C_INT, &O0ULL))))) OrElse ((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg0)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000001ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) AndAlso (-Cast(SQLITE_C_INT, ((arg0->w.iJoin = arg1))))))))))))) Then
            c2fb_temp_0 = CPtr(u32 Ptr, @((arg0)->flags))
            c2fb_temp_1 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_0)) And Cast(SQLITE_C_UINT, (Not Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000001ULL) Or Cast(SQLITE_C_INT, &H000002ULL))))))))))
            (*c2fb_temp_0) = Cast(u32, c2fb_temp_1)
            c2fb_temp_1 = Cast(SQLITE_C_UINT, (*c2fb_temp_0))
            If (-Cast(SQLITE_C_INT, ((arg1 >= Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_2 = CPtr(u32 Ptr, @((arg0)->flags))
                c2fb_temp_3 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_2)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000002ULL))))))
                (*c2fb_temp_2) = Cast(u32, c2fb_temp_3)
                c2fb_temp_3 = Cast(SQLITE_C_UINT, (*c2fb_temp_2))
            End If
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->op) = Cast(SQLITE_C_INT, 168ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((arg0->iTable = arg1)))))))) AndAlso (-Cast(SQLITE_C_INT, (arg2 = 0))))))) Then
            c2fb_temp_4 = CPtr(u32 Ptr, @((arg0)->flags))
            c2fb_temp_5 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_4)) And Cast(SQLITE_C_UINT, (Not Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H200000ULL))))))))
            (*c2fb_temp_4) = Cast(u32, c2fb_temp_5)
            c2fb_temp_5 = Cast(SQLITE_C_UINT, (*c2fb_temp_4))
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->op) = Cast(SQLITE_C_INT, 172ULL))))) Then
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            If arg0->x.pList Then
                ' C automatic storage declaration
                c2fb_temp_6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local0 = c2fb_temp_6
                While (-Cast(SQLITE_C_INT, ((local0 < arg0->x.pList->nExpr))))
                    unsetJoinExpr(arg0->x.pList->a(local0).pExpr, arg1, arg2)
                c2fb_flow_3:
                    c2fb_temp_7 = local0
                    local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_7 + 1)))
                Wend
                c2fb_flow_2:
            End If
        End If
        unsetJoinExpr(arg0->pLeft, arg1, arg2)
        c2fb_temp_8 = arg0->pRight
        arg0 = c2fb_temp_8
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
End Sub

Private Sub innerLoopLoadRow CDecl Alias "innerLoopLoadRow" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteRowLoadInfo Ptr)
    sqlite3ExprCodeExprList(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pEList), arg2->regResult, Cast(SQLITE_C_INT, &O0ULL), arg2->ecelFlags)
End Sub

Private Function makeSorterRecord CDecl Alias "makeSorterRecord" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSortContext Ptr, ByVal arg2 As SqliteSelect Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SqliteVdbe Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT

    local0 = arg1->nOBSat
    local1 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    c2fb_temp_0 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
    c2fb_temp_1 = (*c2fb_temp_0)
    (*c2fb_temp_0) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    c2fb_temp_2 = (*c2fb_temp_0)
    local2 = c2fb_temp_2
    If arg1->pDeferredRowLoad Then
        innerLoopLoadRow(arg0, arg2, arg1->pDeferredRowLoad)
    End If
    sqlite3VdbeAddOp3(local1, Cast(SQLITE_C_INT, 99ULL), Cast(SQLITE_C_INT, (arg3 + local0)), Cast(SQLITE_C_INT, (arg4 - local0)), local2)
    Return local2
End Function

Private Sub pushOntoSorter CDecl Alias "pushOntoSorter" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSortContext Ptr, ByVal arg2 As SqliteSelect Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As SQLITE_C_INT)
    Dim local0 As SqliteVdbe Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim local6 As SQLITE_C_INT
    Dim local7 As SQLITE_C_INT
    Dim local8 As SQLITE_C_INT
    Dim local9 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim local10 As SQLITE_C_INT
    Dim local11 As SQLITE_C_INT
    Dim local12 As SQLITE_C_INT
    Dim local13 As SqliteVdbeOp Ptr
    Dim local14 As SQLITE_C_INT
    Dim local15 As sqlite3VdbeKeyInfoPrefix Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SqliteVdbeOp Ptr
    Dim c2fb_temp_15 As SQLITE_C_INT Ptr
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As sqlite3VdbeKeyInfoPrefix Ptr
    Dim c2fb_temp_18 As Any Ptr
    Dim c2fb_temp_19 As Any Ptr Ptr
    Dim c2fb_temp_20 As sqlite3VdbeKeyInfoPrefix Ptr
    Dim c2fb_temp_21 As SqliteVdbeOp Ptr
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim c2fb_temp_23 As SQLITE_C_INT Ptr
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As SQLITE_C_INT Ptr
    Dim c2fb_temp_26 As SQLITE_C_INT
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim c2fb_temp_28 As SQLITE_C_INT Ptr
    Dim c2fb_temp_29 As SQLITE_C_INT
    Dim local16 As SQLITE_C_INT
    Dim c2fb_temp_30 As SQLITE_C_INT
    Dim c2fb_temp_31 As SQLITE_C_INT
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As SQLITE_C_INT

    local0 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    local1 = ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->sortFlags) And Cast(SQLITE_C_INT, &H01ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))))
    local2 = arg1->pOrderBy->nExpr
    local3 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local2 + local1)) + arg5))
    ' C automatic storage declaration
    local5 = Cast(SQLITE_C_INT, &O0ULL)
    local6 = arg1->nOBSat
    ' C automatic storage declaration
    ' C automatic storage declaration
    local9 = Cast(SQLITE_C_INT, &O0ULL)
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If arg6 Then
        ' C unused-parameter annotation
        c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg3 - arg6)))
        local4 = c2fb_temp_0
    Else
        c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg0->nMem + Cast(SQLITE_C_INT, 1ULL))))
        local4 = c2fb_temp_1
        c2fb_temp_2 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
        c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_2) + local3)))
        (*c2fb_temp_2) = c2fb_temp_3
    End If
    ' C unused-parameter annotation
    c2fb_temp_4 = Cast(SQLITE_C_INT, IIf(arg2->iOffset, Cast(SQLITE_C_INT, (arg2->iOffset + Cast(SQLITE_C_INT, 1ULL))), arg2->iLimit))
    local8 = c2fb_temp_4
    c2fb_temp_5 = CPtr(SQLITE_C_INT Ptr, @(arg1->labelDone))
    c2fb_temp_6 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
    (*c2fb_temp_5) = c2fb_temp_6
    sqlite3ExprCodeExprList(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pOrderBy), local4, arg4, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H01ULL) Or (IIf(arg4, Cast(SQLITE_C_INT, &H04ULL), Cast(SQLITE_C_INT, &O0ULL))))))
    If local1 Then
        sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 128ULL), arg1->iECursor, Cast(SQLITE_C_INT, (local4 + local2)))
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg6 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((arg5 > Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        sqlite3ExprCodeMove(CPtr(Any Ptr, arg0), arg3, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local4 + local2)) + local1)), arg5)
    End If
    If (-Cast(SQLITE_C_INT, ((local6 > Cast(SQLITE_C_INT, &O0ULL))))) Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        c2fb_temp_7 = Cast(SQLITE_C_INT, makeSorterRecord(arg0, arg1, arg2, local4, local3))
        local5 = c2fb_temp_7
        c2fb_temp_8 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg0->nMem + Cast(SQLITE_C_INT, 1ULL))))
        local10 = c2fb_temp_8
        c2fb_temp_9 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
        c2fb_temp_10 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_9) + arg1->nOBSat)))
        (*c2fb_temp_9) = c2fb_temp_10
        c2fb_temp_11 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local2 - arg1->nOBSat)) + local1)))
        local14 = c2fb_temp_11
        If local1 Then
            c2fb_temp_12 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 17ULL), Cast(SQLITE_C_INT, (local4 + local2))))
            local11 = c2fb_temp_12
        Else
            c2fb_temp_13 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 122ULL), arg1->iECursor))
            local11 = c2fb_temp_13
        End If
        ' empty C statement
        sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 92ULL), local10, local4, arg1->nOBSat)
        c2fb_temp_14 = CPtr(SqliteVdbeOp Ptr, sqlite3VdbeGetOp(local0, arg1->addrSortIndex))
        local13 = c2fb_temp_14
        If arg0->db->mallocFailed Then
            Return
        End If
        c2fb_temp_15 = CPtr(SQLITE_C_INT Ptr, @(local13->p2))
        c2fb_temp_16 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local14 + arg5)))
        (*c2fb_temp_15) = c2fb_temp_16
        c2fb_temp_17 = CPtr(sqlite3VdbeKeyInfoPrefix Ptr, local13->p4.pKeyInfo)
        local15 = c2fb_temp_17
        c2fb_temp_18 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, local15->aSortFlags), Cast(SQLITE_C_INT, &O0ULL), local15->nKeyField))
        sqlite3VdbeChangeP4(local0, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), CPtr(Const ZString Ptr, CPtr(ZString Ptr, local15)), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 9ULL)))))
        ' empty C statement
        c2fb_temp_19 = CPtr(Any Ptr Ptr, @(local13->p4.pKeyInfo))
        c2fb_temp_20 = CPtr(sqlite3VdbeKeyInfoPrefix Ptr, sqlite3KeyInfoFromExprList(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pOrderBy), local6, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local15->nAllField) - Cast(SQLITE_C_INT, local15->nKeyField))) - Cast(SQLITE_C_INT, 1ULL)))))
        (*c2fb_temp_19) = CPtr(Any Ptr, c2fb_temp_20)
        c2fb_temp_20 = CPtr(sqlite3VdbeKeyInfoPrefix Ptr, (*c2fb_temp_19))
        c2fb_temp_21 = CPtr(SqliteVdbeOp Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        local13 = c2fb_temp_21
        c2fb_temp_22 = Cast(SQLITE_C_INT, sqlite3VdbeCurrentAddr(local0))
        local12 = c2fb_temp_22
        sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 14ULL), Cast(SQLITE_C_INT, (local12 + Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, (local12 + Cast(SQLITE_C_INT, 1ULL))))
        ' empty C statement
        c2fb_temp_23 = CPtr(SQLITE_C_INT Ptr, @(arg1->labelBkOut))
        c2fb_temp_24 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
        (*c2fb_temp_23) = c2fb_temp_24
        c2fb_temp_28 = CPtr(SQLITE_C_INT Ptr, @(arg1->regReturn))
        c2fb_temp_25 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
        c2fb_temp_26 = (*c2fb_temp_25)
        (*c2fb_temp_25) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_26 + 1)))
        c2fb_temp_27 = (*c2fb_temp_25)
        c2fb_temp_29 = Cast(SQLITE_C_INT, c2fb_temp_27)
        (*c2fb_temp_28) = c2fb_temp_29
        sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 10ULL), arg1->regReturn, arg1->labelBkOut)
        sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 148ULL), arg1->iECursor)
        If local8 Then
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 17ULL), local8, arg1->labelDone)
            ' empty C statement
        End If
        sqlite3VdbeJumpHere(local0, local11)
        sqlite3ExprCodeMove(CPtr(Any Ptr, arg0), local4, local10, arg1->nOBSat)
        sqlite3VdbeJumpHere(local0, local12)
    End If
    If local8 Then
        local16 = arg1->iECursor
        sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 62ULL), local8, Cast(SQLITE_C_INT, (sqlite3VdbeCurrentAddr(local0) + Cast(SQLITE_C_INT, 4ULL))))
        ' empty C statement
        sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 32ULL), local16, Cast(SQLITE_C_INT, &O0ULL))
        c2fb_temp_30 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp4Int(local0, Cast(SQLITE_C_INT, 41ULL), local16, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, (local4 + local6)), Cast(SQLITE_C_INT, (local2 - local6))))
        local9 = c2fb_temp_30
        ' empty C statement
        sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 132ULL), local16)
    End If
    If (-Cast(SQLITE_C_INT, ((local5 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        c2fb_temp_31 = Cast(SQLITE_C_INT, makeSorterRecord(arg0, arg1, arg2, local4, local3))
        local5 = c2fb_temp_31
    End If
    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->sortFlags) And Cast(SQLITE_C_INT, &H01ULL))) Then
        c2fb_temp_32 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 141ULL))
        local7 = c2fb_temp_32
    Else
        c2fb_temp_33 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 140ULL))
        local7 = c2fb_temp_33
    End If
    sqlite3VdbeAddOp4Int(local0, local7, arg1->iECursor, local5, Cast(SQLITE_C_INT, (local4 + local6)), Cast(SQLITE_C_INT, (local3 - local6)))
    If local9 Then
        sqlite3VdbeChangeP2(local0, local9, IIf(arg1->labelOBLopt, arg1->labelOBLopt, sqlite3VdbeCurrentAddr(local0)))
    End If
End Sub

Private Sub codeOffset CDecl Alias "codeOffset" (ByVal arg0 As SqliteVdbe Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT)
    If (-Cast(SQLITE_C_INT, ((arg1 > Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3VdbeAddOp3(arg0, Cast(SQLITE_C_INT, 61ULL), arg1, arg2, Cast(SQLITE_C_INT, 1ULL))
        ' empty C statement
        ' empty C statement
    End If
End Sub

Private Function codeDistinct CDecl Alias "codeDistinct" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SqliteExprList Ptr, ByVal arg5 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim local2 As SqliteVdbe Ptr
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim local6 As sqlite3CollSeq Ptr
    Dim local7 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    local1 = arg4->nExpr
    local2 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    Select Case arg1
        Case Cast(SQLITE_C_INT, 2ULL)
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg0->nMem + Cast(SQLITE_C_INT, 1ULL))))
            local5 = c2fb_temp_0
            c2fb_temp_1 = Cast(SQLITE_C_INT, c2fb_temp_0)
            local0 = c2fb_temp_1
            c2fb_temp_2 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
            c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_2) + local1)))
            (*c2fb_temp_2) = c2fb_temp_3
            c2fb_temp_4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (sqlite3VdbeCurrentAddr(local2) + local1)))
            local4 = c2fb_temp_4
            c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local3 = c2fb_temp_5
            While (-Cast(SQLITE_C_INT, ((local3 < local1))))
                local6 = CPtr(sqlite3CollSeq Ptr, sqlite3ExprCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg4->a(local3).pExpr)))
                If (-Cast(SQLITE_C_INT, ((local3 < Cast(SQLITE_C_INT, (local1 - Cast(SQLITE_C_INT, 1ULL))))))) Then
                    sqlite3VdbeAddOp3(local2, Cast(SQLITE_C_INT, 53ULL), Cast(SQLITE_C_INT, (arg5 + local3)), local4, Cast(SQLITE_C_INT, (local5 + local3)))
                    ' empty C statement
                Else
                    sqlite3VdbeAddOp3(local2, Cast(SQLITE_C_INT, 54ULL), Cast(SQLITE_C_INT, (arg5 + local3)), arg3, Cast(SQLITE_C_INT, (local5 + local3)))
                    ' empty C statement
                End If
                sqlite3VdbeChangeP4(local2, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), CPtr(Const ZString Ptr, local6), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 2ULL)))))
                sqlite3VdbeChangeP5(local2, Cast(SQLITE_C_INT, &H80ULL))
            c2fb_flow_2:
                c2fb_temp_6 = local3
                local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 + 1)))
            Wend
            c2fb_flow_1:
            ' C unused-parameter annotation
            sqlite3VdbeAddOp3(local2, Cast(SQLITE_C_INT, 82ULL), arg5, local5, Cast(SQLITE_C_INT, (local1 - Cast(SQLITE_C_INT, 1ULL))))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 1ULL)
            Goto c2fb_flow_0
        Case Else
            local7 = sqlite3GetTempReg(CPtr(Any Ptr, arg0))
            sqlite3VdbeAddOp4Int(local2, Cast(SQLITE_C_INT, 29ULL), arg2, arg3, arg5, local1)
            ' empty C statement
            sqlite3VdbeAddOp3(local2, Cast(SQLITE_C_INT, 99ULL), arg5, local1, local7)
            sqlite3VdbeAddOp4Int(local2, Cast(SQLITE_C_INT, 140ULL), arg2, local7, arg5, local1)
            sqlite3VdbeChangeP5(local2, Cast(SQLITE_C_INT, &H10ULL))
            sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local7)
            c2fb_temp_7 = Cast(SQLITE_C_INT, arg2)
            local0 = c2fb_temp_7
            Goto c2fb_flow_0
    End Select
    c2fb_flow_0:
    Return local0
End Function

Private Sub fixDistinctOpenEph CDecl Alias "fixDistinctOpenEph" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
    Dim local0 As SqliteVdbe Ptr
    Dim local1 As SqliteVdbeOp Ptr
    Dim c2fb_temp_0 As u8 Ptr
    Dim c2fb_temp_1 As UByte
    Dim c2fb_temp_2 As SQLITE_C_INT Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT

    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg0->nErr = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, 1ULL))))) OrElse (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, 2ULL)))))))))))))) Then
        local0 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
        sqlite3VdbeChangeToNoop(local0, arg3)
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(SqliteVdbeOp Ptr, sqlite3VdbeGetOp(local0, Cast(SQLITE_C_INT, (arg3 + Cast(SQLITE_C_INT, 1ULL)))))->opcode) = Cast(SQLITE_C_INT, 190ULL))))) Then
            sqlite3VdbeChangeToNoop(local0, Cast(SQLITE_C_INT, (arg3 + Cast(SQLITE_C_INT, 1ULL))))
        End If
        If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, 2ULL))))) Then
            local1 = CPtr(SqliteVdbeOp Ptr, sqlite3VdbeGetOp(local0, arg3))
            c2fb_temp_0 = CPtr(u8 Ptr, @(local1->opcode))
            c2fb_temp_1 = Cast(UByte, Cast(SQLITE_C_INT, 77ULL))
            (*c2fb_temp_0) = Cast(u8, c2fb_temp_1)
            c2fb_temp_1 = Cast(UByte, (*c2fb_temp_0))
            c2fb_temp_2 = CPtr(SQLITE_C_INT Ptr, @(local1->p1))
            c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
            (*c2fb_temp_2) = c2fb_temp_3
            c2fb_temp_4 = CPtr(SQLITE_C_INT Ptr, @(local1->p2))
            c2fb_temp_5 = Cast(SQLITE_C_INT, arg2)
            (*c2fb_temp_4) = c2fb_temp_5
        End If
    End If
End Sub

Private Sub selectInnerLoop CDecl Alias "selectInnerLoop" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SqliteSortContext Ptr, ByVal arg4 As SqliteDistinctContext Ptr, ByVal arg5 As SqliteSelectDest Ptr, ByVal arg6 As SQLITE_C_INT, ByVal arg7 As SQLITE_C_INT)
    Dim local0 As SqliteVdbe Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim local6 As SQLITE_C_INT
    Dim local7 As SqliteRowLoadInfo
    Dim local8 As SQLITE_C_INT
    Dim local9 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SqliteSortContext Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT Ptr
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT Ptr
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT Ptr
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SQLITE_C_INT
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim local10 As UByte
    Dim local11 As SqliteExprList Ptr
    Dim c2fb_temp_19 As UByte
    Dim c2fb_temp_20 As UByte
    Dim c2fb_temp_21 As UByte
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim c2fb_temp_23 As SQLITE_C_INT
    Dim local12 As SQLITE_C_INT
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As UShort Ptr
    Dim c2fb_temp_26 As UShort
    Dim c2fb_temp_27 As SqliteExprList Ptr
    Dim c2fb_temp_28 As SQLITE_C_INT
    Dim c2fb_temp_29 As SQLITE_C_INT
    Dim c2fb_temp_30 As SQLITE_C_INT
    Dim c2fb_temp_31 As SQLITE_C_INT
    Dim c2fb_temp_32 As SQLITE_C_INT Ptr
    Dim c2fb_temp_33 As SQLITE_C_INT
    Dim c2fb_temp_34 As u8 Ptr
    Dim c2fb_temp_35 As UByte
    Dim c2fb_temp_36 As SqliteRowLoadInfo Ptr Ptr
    Dim c2fb_temp_37 As SqliteRowLoadInfo Ptr
    Dim c2fb_temp_38 As SQLITE_C_INT
    Dim local13 As SQLITE_C_INT
    Dim local14 As SQLITE_C_INT
    Dim c2fb_temp_39 As SQLITE_C_INT
    Dim local15 As SQLITE_C_INT
    Dim local16 As SQLITE_C_INT
    Dim local17 As SQLITE_C_INT
    Dim local18 As SQLITE_C_INT
    Dim local19 As SQLITE_C_INT
    Dim c2fb_temp_40 As SQLITE_C_INT Ptr
    Dim c2fb_temp_41 As SQLITE_C_INT
    Dim local20 As SQLITE_C_INT
    Dim c2fb_temp_42 As SQLITE_C_INT Ptr
    Dim c2fb_temp_43 As SQLITE_C_INT
    Dim local21 As SQLITE_C_INT
    Dim local22 As SQLITE_C_INT
    Dim local23 As SQLITE_C_INT
    Dim local24 As SQLITE_C_INT
    Dim local25 As SQLITE_C_INT
    Dim local26 As SqliteExprList Ptr
    Dim c2fb_temp_44 As SqliteExprList Ptr
    Dim c2fb_temp_45 As SQLITE_C_INT
    Dim c2fb_temp_46 As SQLITE_C_INT
    Dim c2fb_temp_47 As SQLITE_C_INT
    Dim c2fb_temp_48 As SQLITE_C_INT
    Dim c2fb_temp_49 As SQLITE_C_INT
    Dim c2fb_temp_50 As SQLITE_C_INT
    Dim c2fb_temp_51 As SQLITE_C_INT

    local0 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    ' C automatic storage declaration
    ' C automatic storage declaration
    local3 = arg5->eDest
    local4 = arg5->iSDParm
    ' C automatic storage declaration
    local6 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, IIf(arg4, Cast(SQLITE_C_INT, arg4->eTnctType), Cast(SQLITE_C_INT, &O0ULL)))
    local2 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, ((arg3 AndAlso (-Cast(SQLITE_C_INT, ((arg3->pOrderBy = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        c2fb_temp_1 = CPtr(SqliteSortContext Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        arg3 = c2fb_temp_1
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg3 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (local2 = 0))))))) Then
        ' C unused-parameter annotation
        codeOffset(local0, arg1->iOffset, arg6)
    End If
    c2fb_temp_2 = Cast(SQLITE_C_INT, arg1->pEList->nExpr)
    local5 = c2fb_temp_2
    If (-Cast(SQLITE_C_INT, ((arg5->iSdst = Cast(SQLITE_C_INT, &O0ULL))))) Then
        If arg3 Then
            c2fb_temp_3 = Cast(SQLITE_C_INT, arg3->pOrderBy->nExpr)
            local6 = c2fb_temp_3
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg3->sortFlags) And Cast(SQLITE_C_INT, &H01ULL)))) = 0))) Then
                c2fb_temp_4 = local6
                local6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_4 + 1)))
            End If
            c2fb_temp_5 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
            c2fb_temp_6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_5) + local6)))
            (*c2fb_temp_5) = c2fb_temp_6
        End If
        c2fb_temp_7 = CPtr(SQLITE_C_INT Ptr, @(arg5->iSdst))
        c2fb_temp_8 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg0->nMem + Cast(SQLITE_C_INT, 1ULL))))
        (*c2fb_temp_7) = c2fb_temp_8
        c2fb_temp_9 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
        c2fb_temp_10 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_9) + local5)))
        (*c2fb_temp_9) = c2fb_temp_10
    Else
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (arg5->iSdst + local5)) > arg0->nMem)))) Then
            c2fb_temp_11 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
            c2fb_temp_12 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_11) + local5)))
            (*c2fb_temp_11) = c2fb_temp_12
        End If
    End If
    c2fb_temp_13 = CPtr(SQLITE_C_INT Ptr, @(arg5->nSdst))
    c2fb_temp_14 = Cast(SQLITE_C_INT, local5)
    (*c2fb_temp_13) = c2fb_temp_14
    c2fb_temp_15 = Cast(SQLITE_C_INT, arg5->iSdst)
    local8 = c2fb_temp_15
    c2fb_temp_16 = Cast(SQLITE_C_INT, c2fb_temp_15)
    local9 = c2fb_temp_16
    If (-Cast(SQLITE_C_INT, ((arg2 >= Cast(SQLITE_C_INT, &O0ULL))))) Then
        c2fb_temp_17 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local1 = c2fb_temp_17
        While (-Cast(SQLITE_C_INT, ((local1 < local5))))
            sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 96ULL), arg2, local1, Cast(SQLITE_C_INT, (local8 + local1)))
            ' empty C statement
        c2fb_flow_1:
            c2fb_temp_18 = local1
            local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_18 + 1)))
        Wend
        c2fb_flow_0:
    Else
        If (-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, 1ULL))))) Then
            ' C automatic storage declaration
            ' C automatic storage declaration
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, 8ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, 7ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, 11ULL))))))))) Then
                c2fb_temp_19 = Cast(UByte, Cast(SQLITE_C_INT, &H01ULL))
                local10 = c2fb_temp_19
            Else
                c2fb_temp_20 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                local10 = c2fb_temp_20
            End If
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg3 AndAlso (-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, 10ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, 12ULL))))))))) Then
                c2fb_temp_21 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local10) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H04ULL)))))))
                local10 = c2fb_temp_21
                c2fb_temp_22 = Cast(SQLITE_C_INT, arg3->nOBSat)
                local1 = c2fb_temp_22
                While (-Cast(SQLITE_C_INT, ((local1 < arg3->pOrderBy->nExpr))))
                    ' C automatic storage declaration
                    c2fb_temp_24 = Cast(SQLITE_C_INT, arg3->pOrderBy->a(local1).u.x.iOrderByCol)
                    local12 = c2fb_temp_24
                    If (-Cast(SQLITE_C_INT, (((c2fb_temp_24) > Cast(SQLITE_C_INT, &O0ULL))))) Then
                        c2fb_temp_25 = CPtr(UShort Ptr, @(arg1->pEList->a(Cast(SQLITE_C_INT, (local12 - Cast(SQLITE_C_INT, 1ULL)))).u.x.iOrderByCol))
                        c2fb_temp_26 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local1 + Cast(SQLITE_C_INT, 1ULL))) - arg3->nOBSat)))
                        (*c2fb_temp_25) = c2fb_temp_26
                    End If
                c2fb_flow_3:
                    c2fb_temp_23 = local1
                    local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_23 + 1)))
                Wend
                c2fb_flow_2:
                c2fb_temp_27 = arg1->pEList
                local11 = c2fb_temp_27
                c2fb_temp_28 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local1 = c2fb_temp_28
                While (-Cast(SQLITE_C_INT, ((local1 < local11->nExpr))))
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local11->a(local1).u.x.iOrderByCol) > Cast(SQLITE_C_INT, &O0ULL))))) Then
                        c2fb_temp_30 = local5
                        local5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_30 - 1)))
                        c2fb_temp_31 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                        local9 = c2fb_temp_31
                    End If
                c2fb_flow_5:
                    c2fb_temp_29 = local1
                    local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_29 + 1)))
                Wend
                c2fb_flow_4:
                ' empty C statement
                ' empty C statement
                ' empty C statement
                ' empty C statement
                ' empty C statement
                ' C unused-parameter annotation
            End If
            c2fb_temp_32 = CPtr(SQLITE_C_INT Ptr, @(local7.regResult))
            c2fb_temp_33 = Cast(SQLITE_C_INT, local8)
            (*c2fb_temp_32) = c2fb_temp_33
            c2fb_temp_34 = CPtr(u8 Ptr, @(local7.ecelFlags))
            c2fb_temp_35 = Cast(UByte, local10)
            (*c2fb_temp_34) = Cast(u8, c2fb_temp_35)
            c2fb_temp_35 = Cast(UByte, (*c2fb_temp_34))
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg1->iLimit AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local10) And Cast(SQLITE_C_INT, &H08ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((local6 > Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                c2fb_temp_36 = CPtr(SqliteRowLoadInfo Ptr Ptr, @(arg3->pDeferredRowLoad))
                c2fb_temp_37 = CPtr(SqliteRowLoadInfo Ptr, @(local7))
                (*c2fb_temp_36) = c2fb_temp_37
                c2fb_temp_38 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local9 = c2fb_temp_38
            Else
                innerLoopLoadRow(arg0, arg1, CPtr(SqliteRowLoadInfo Ptr, @(local7)))
            End If
        End If
    End If
    If local2 Then
        local13 = arg4->eTnctType
        local14 = arg4->tabTnct
        ' C unused-parameter annotation
        c2fb_temp_39 = Cast(SQLITE_C_INT, codeDistinct(arg0, local13, local14, arg6, arg1->pEList, local8))
        local14 = c2fb_temp_39
        fixDistinctOpenEph(arg0, local13, local14, arg4->addrTnct)
        If (-Cast(SQLITE_C_INT, ((arg3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            codeOffset(local0, arg1->iOffset, arg6)
        End If
    End If
    Select Case local3
        Case Cast(SQLITE_C_INT, 6ULL), Cast(SQLITE_C_INT, 3ULL), Cast(SQLITE_C_INT, 12ULL), Cast(SQLITE_C_INT, 10ULL)
            local15 = sqlite3GetTempRange(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, (local6 + Cast(SQLITE_C_INT, 1ULL))))
            ' empty C statement
            ' empty C statement
            ' empty C statement
            ' empty C statement
            sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 99ULL), local8, local5, Cast(SQLITE_C_INT, (local15 + local6)))
            If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, 3ULL))))) Then
                local16 = Cast(SQLITE_C_INT, (sqlite3VdbeCurrentAddr(local0) + Cast(SQLITE_C_INT, 4ULL)))
                sqlite3VdbeAddOp4Int(local0, Cast(SQLITE_C_INT, 29ULL), Cast(SQLITE_C_INT, (local4 + Cast(SQLITE_C_INT, 1ULL))), local16, local15, Cast(SQLITE_C_INT, &O0ULL))
                ' empty C statement
                sqlite3VdbeAddOp4Int(local0, Cast(SQLITE_C_INT, 140ULL), Cast(SQLITE_C_INT, (local4 + Cast(SQLITE_C_INT, 1ULL))), local15, local8, local5)
                ' C unused-parameter annotation
            End If
            If arg3 Then
                ' C unused-parameter annotation
                pushOntoSorter(arg0, arg3, arg1, Cast(SQLITE_C_INT, (local15 + local6)), local9, Cast(SQLITE_C_INT, 1ULL), local6)
            Else
                local17 = sqlite3GetTempReg(CPtr(Any Ptr, arg0))
                sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 129ULL), local4, local17)
                sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 130ULL), local4, local15, local17)
                sqlite3VdbeChangeP5(local0, Cast(SQLITE_C_INT, &H08ULL))
                sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local17)
            End If
            sqlite3ReleaseTempRange(CPtr(Any Ptr, arg0), local15, Cast(SQLITE_C_INT, (local6 + Cast(SQLITE_C_INT, 1ULL))))
            Goto c2fb_flow_6
        Case Cast(SQLITE_C_INT, 13ULL)
            If arg3 Then
                pushOntoSorter(arg0, arg3, arg1, local8, local9, local5, local6)
            Else
                local18 = arg5->iSDParm2
                local19 = sqlite3GetTempReg(CPtr(Any Ptr, arg0))
                sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 51ULL), local8, arg7)
                ' empty C statement
                sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 99ULL), Cast(SQLITE_C_INT, (local8 + ((-Cast(SQLITE_C_INT, ((local18 < Cast(SQLITE_C_INT, &O0ULL)))))))), Cast(SQLITE_C_INT, (local5 - ((-Cast(SQLITE_C_INT, ((local18 < Cast(SQLITE_C_INT, &O0ULL)))))))), local19)
                If (-Cast(SQLITE_C_INT, ((local18 < Cast(SQLITE_C_INT, &O0ULL))))) Then
                    sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 130ULL), local4, local19, local8)
                Else
                    sqlite3VdbeAddOp4Int(local0, Cast(SQLITE_C_INT, 140ULL), local4, local19, local8, local18)
                End If
            End If
            Goto c2fb_flow_6
        Case Cast(SQLITE_C_INT, 9ULL)
            If arg3 Then
                pushOntoSorter(arg0, arg3, arg1, local8, local9, local5, local6)
                c2fb_temp_40 = CPtr(SQLITE_C_INT Ptr, @(arg5->iSDParm2))
                c2fb_temp_41 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_40) = c2fb_temp_41
            Else
                local20 = sqlite3GetTempReg(CPtr(Any Ptr, arg0))
                ' C unused-parameter annotation
                sqlite3VdbeAddOp4(local0, Cast(SQLITE_C_INT, 99ULL), local8, local5, local20, CPtr(Const ZString Ptr, CPtr(ZString Ptr, arg5->zAffSdst)), local5)
                sqlite3VdbeAddOp4Int(local0, Cast(SQLITE_C_INT, 140ULL), local4, local20, local8, local5)
                If arg5->iSDParm2 Then
                    ' C unused-parameter annotation
                    sqlite3VdbeAddOp4Int(local0, Cast(SQLITE_C_INT, 185ULL), arg5->iSDParm2, Cast(SQLITE_C_INT, &O0ULL), local8, local5)
                    sqlite3VdbeExplainText(arg0, Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"CREATE BLOOM FILTER"))
                End If
                sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local20)
            End If
            Goto c2fb_flow_6
        Case Cast(SQLITE_C_INT, 1ULL)
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, 1ULL), local4)
            Goto c2fb_flow_6
        Case Cast(SQLITE_C_INT, 8ULL)
            If arg3 Then
                ' C unused-parameter annotation
                pushOntoSorter(arg0, arg3, arg1, local8, local9, local5, local6)
                c2fb_temp_42 = CPtr(SQLITE_C_INT Ptr, @(arg5->iSDParm))
                c2fb_temp_43 = Cast(SQLITE_C_INT, local8)
                (*c2fb_temp_42) = c2fb_temp_43
            Else
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, ((local8 <> local4)))) Then
                    sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 82ULL), local8, local4, Cast(SQLITE_C_INT, (local5 - Cast(SQLITE_C_INT, 1ULL))))
                End If
            End If
            Goto c2fb_flow_6
        Case Cast(SQLITE_C_INT, 11ULL), Cast(SQLITE_C_INT, 7ULL)
            ' empty C statement
            ' empty C statement
            If arg3 Then
                pushOntoSorter(arg0, arg3, arg1, local8, local9, local5, local6)
            Else
                If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, 11ULL))))) Then
                    sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 12ULL), arg5->iSDParm)
                Else
                    sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 86ULL), local8, local5)
                End If
            End If
            Goto c2fb_flow_6
        Case Cast(SQLITE_C_INT, 4ULL), Cast(SQLITE_C_INT, 5ULL)
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            local25 = Cast(SQLITE_C_INT, &O0ULL)
            ' C automatic storage declaration
            c2fb_temp_44 = CPtr(SqliteExprList Ptr, arg5->pOrderBy)
            local26 = c2fb_temp_44
            ' C unused-parameter annotation
            c2fb_temp_45 = Cast(SQLITE_C_INT, local26->nExpr)
            local21 = c2fb_temp_45
            c2fb_temp_46 = Cast(SQLITE_C_INT, sqlite3GetTempReg(CPtr(Any Ptr, arg0)))
            local22 = c2fb_temp_46
            c2fb_temp_47 = Cast(SQLITE_C_INT, sqlite3GetTempRange(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, (local21 + Cast(SQLITE_C_INT, 2ULL)))))
            local23 = c2fb_temp_47
            c2fb_temp_48 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local23 + local21)) + Cast(SQLITE_C_INT, 1ULL))))
            local24 = c2fb_temp_48
            If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, 4ULL))))) Then
                c2fb_temp_49 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp4Int(local0, Cast(SQLITE_C_INT, 29ULL), Cast(SQLITE_C_INT, (local4 + Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, &O0ULL), local8, local5))
                local25 = c2fb_temp_49
                ' empty C statement
            End If
            sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 99ULL), local8, local5, local24)
            If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, 4ULL))))) Then
                sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 140ULL), Cast(SQLITE_C_INT, (local4 + Cast(SQLITE_C_INT, 1ULL))), local24)
                sqlite3VdbeChangeP5(local0, Cast(SQLITE_C_INT, &H10ULL))
            End If
            c2fb_temp_50 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local1 = c2fb_temp_50
            While (-Cast(SQLITE_C_INT, ((local1 < local21))))
                sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 83ULL), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local8 + Cast(SQLITE_C_INT, local26->a(local1).u.x.iOrderByCol))) - Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, (local23 + local1)))
            c2fb_flow_8:
                c2fb_temp_51 = local1
                local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_51 + 1)))
            Wend
            c2fb_flow_7:
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 128ULL), local4, Cast(SQLITE_C_INT, (local23 + local21)))
            sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 99ULL), local23, Cast(SQLITE_C_INT, (local21 + Cast(SQLITE_C_INT, 2ULL))), local22)
            sqlite3VdbeAddOp4Int(local0, Cast(SQLITE_C_INT, 140ULL), local4, local22, local23, Cast(SQLITE_C_INT, (local21 + Cast(SQLITE_C_INT, 2ULL))))
            If local25 Then
                sqlite3VdbeJumpHere(local0, local25)
            End If
            sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local22)
            sqlite3ReleaseTempRange(CPtr(Any Ptr, arg0), local23, Cast(SQLITE_C_INT, (local21 + Cast(SQLITE_C_INT, 2ULL))))
            Goto c2fb_flow_6
        Case Else
            ' C unused-parameter annotation
            Goto c2fb_flow_6
    End Select
    c2fb_flow_6:
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg3 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso arg1->iLimit)))) Then
        sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 63ULL), arg1->iLimit, arg7)
        ' empty C statement
    End If
End Sub

Private Sub explainTempTable CDecl Alias "explainTempTable" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As Const ZString Ptr)
    sqlite3VdbeExplainString(arg0, Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"USE TEMP B-TREE FOR %s"), arg1)
End Sub

Private Sub generateSortTail CDecl Alias "generateSortTail" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteSortContext Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SqliteSelectDest Ptr)
    Dim local0 As SqliteVdbe Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim local6 As SqliteExprList Ptr
    Dim local7 As SQLITE_C_INT
    Dim local8 As SQLITE_C_INT
    Dim local9 As SQLITE_C_INT
    Dim local10 As SQLITE_C_INT
    Dim local11 As SQLITE_C_INT
    Dim local12 As SQLITE_C_INT
    Dim local13 As SQLITE_C_INT
    Dim local14 As SQLITE_C_INT
    Dim local15 As SQLITE_C_INT
    Dim local16 As SQLITE_C_INT
    Dim local17 As SqliteExprListItem Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT Ptr
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim local18 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT Ptr
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SQLITE_C_INT
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As SQLITE_C_INT
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim c2fb_temp_23 As SQLITE_C_INT
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As SQLITE_C_INT
    Dim local19 As SQLITE_C_INT
    Dim c2fb_temp_26 As SQLITE_C_INT
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim c2fb_temp_28 As SQLITE_C_INT
    Dim local20 As SQLITE_C_INT
    Dim local21 As SQLITE_C_INT

    local0 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    local1 = arg2->labelDone
    local2 = sqlite3VdbeMakeLabel(arg0)
    ' C automatic storage declaration
    local4 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    local6 = arg2->pOrderBy
    local7 = arg4->eDest
    local8 = arg4->iSDParm
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local16 = Cast(SQLITE_C_INT, &O0ULL)
    local17 = CPtr(SqliteExprListItem Ptr, (@arg1->pEList->a(0)))
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local6->nExpr - arg2->nOBSat)))
    local12 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg2->nOBSat = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local12 = Cast(SQLITE_C_INT, 1ULL))))))))) Then
        sqlite3VdbeExplainString(arg0, Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"USE TEMP B-TREE FOR %sORDER BY"), IIf(arg2->nOBSat, StrPtr(!"LAST TERM OF "), StrPtr(!"")))
    Else
        sqlite3VdbeExplainInteger(arg0, Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"USE TEMP B-TREE FOR LAST %d TERMS OF ORDER BY"), local12)
    End If
    ' empty C statement
    ' empty C statement
    ' C unused-parameter annotation
    If arg2->labelBkOut Then
        sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 10ULL), arg2->regReturn, arg2->labelBkOut)
        sqlite3VdbeGoto(local0, local1)
        sqlite3VdbeResolveLabel(local0, arg2->labelBkOut)
    End If
    c2fb_temp_1 = Cast(SQLITE_C_INT, arg2->iECursor)
    local5 = c2fb_temp_1
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, 7ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, 11ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, 8ULL))))))))) Then
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, 8ULL))))) AndAlso arg1->iOffset)))) Then
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), arg4->iSdst)
        End If
        c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local10 = c2fb_temp_2
        c2fb_temp_3 = Cast(SQLITE_C_INT, arg4->iSdst)
        local9 = c2fb_temp_3
    Else
        c2fb_temp_4 = Cast(SQLITE_C_INT, sqlite3GetTempReg(CPtr(Any Ptr, arg0)))
        local10 = c2fb_temp_4
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, 10ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, 12ULL))))))))) Then
            c2fb_temp_5 = Cast(SQLITE_C_INT, sqlite3GetTempReg(CPtr(Any Ptr, arg0)))
            local9 = c2fb_temp_5
            c2fb_temp_6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            arg3 = c2fb_temp_6
        Else
            c2fb_temp_7 = Cast(SQLITE_C_INT, sqlite3GetTempRange(CPtr(Any Ptr, arg0), arg3))
            local9 = c2fb_temp_7
        End If
    End If
    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2->sortFlags) And Cast(SQLITE_C_INT, &H01ULL))) Then
        c2fb_temp_8 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
        c2fb_temp_9 = (*c2fb_temp_8)
        (*c2fb_temp_8) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_9 + 1)))
        c2fb_temp_10 = (*c2fb_temp_8)
        local18 = c2fb_temp_10
        c2fb_temp_11 = CPtr(SQLITE_C_INT Ptr, @(arg0->nTab))
        c2fb_temp_12 = (*c2fb_temp_11)
        (*c2fb_temp_11) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_12 + 1)))
        c2fb_temp_13 = Cast(SQLITE_C_INT, c2fb_temp_12)
        local13 = c2fb_temp_13
        If arg2->labelBkOut Then
            c2fb_temp_14 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp0(local0, Cast(SQLITE_C_INT, 15ULL)))
            local4 = c2fb_temp_14
            ' empty C statement
        End If
        sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 123ULL), local13, local18, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local12 + Cast(SQLITE_C_INT, 1ULL))) + arg3)) + local16)))
        If local4 Then
            sqlite3VdbeJumpHere(local0, local4)
        End If
        c2fb_temp_15 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 1ULL) + sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 34ULL), local5, local1))))
        local3 = c2fb_temp_15
        ' empty C statement
        ' C unused-parameter annotation
        sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 135ULL), local5, local18, local13)
        c2fb_temp_16 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local15 = c2fb_temp_16
    Else
        c2fb_temp_17 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 1ULL) + sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 35ULL), local5, local1))))
        local3 = c2fb_temp_17
        ' empty C statement
        codeOffset(local0, arg1->iOffset, local2)
        c2fb_temp_18 = Cast(SQLITE_C_INT, local5)
        local13 = c2fb_temp_18
        c2fb_temp_19 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
        local15 = c2fb_temp_19
        If (-Cast(SQLITE_C_INT, ((arg1->iOffset > Cast(SQLITE_C_INT, &O0ULL))))) Then
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 88ULL), arg1->iLimit, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
        End If
    End If
    c2fb_temp_20 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local14 = c2fb_temp_20
    c2fb_temp_21 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local12 + local15)) - Cast(SQLITE_C_INT, 1ULL))))
    local11 = c2fb_temp_21
    While (-Cast(SQLITE_C_INT, ((local14 < arg3))))
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local17[local14].u.x.iOrderByCol) = Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_23 = local11
            local11 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_23 + 1)))
        End If
    c2fb_flow_1:
        c2fb_temp_22 = local14
        local14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_22 + 1)))
    Wend
    c2fb_flow_0:
    c2fb_temp_24 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg3 - Cast(SQLITE_C_INT, 1ULL))))
    local14 = c2fb_temp_24
    While (-Cast(SQLITE_C_INT, ((local14 >= Cast(SQLITE_C_INT, &O0ULL)))))
        ' C automatic storage declaration
        If local17[local14].u.x.iOrderByCol Then
            c2fb_temp_26 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local17[local14].u.x.iOrderByCol) - Cast(SQLITE_C_INT, 1ULL))))
            local19 = c2fb_temp_26
        Else
            c2fb_temp_27 = local11
            local11 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_27 - 1)))
            c2fb_temp_28 = Cast(SQLITE_C_INT, c2fb_temp_27)
            local19 = c2fb_temp_28
        End If
        sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 96ULL), local13, local19, Cast(SQLITE_C_INT, (local9 + local14)))
        ' empty C statement
    c2fb_flow_3:
        c2fb_temp_25 = local14
        local14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_25 - 1)))
    Wend
    c2fb_flow_2:
    ' empty C statement
    Select Case local7
        Case Cast(SQLITE_C_INT, 12ULL), Cast(SQLITE_C_INT, 10ULL)
            sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 96ULL), local13, Cast(SQLITE_C_INT, (local12 + local15)), local9)
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 129ULL), local8, local10)
            sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 130ULL), local8, local9, local10)
            sqlite3VdbeChangeP5(local0, Cast(SQLITE_C_INT, &H08ULL))
            Goto c2fb_flow_4
        Case Cast(SQLITE_C_INT, 9ULL)
            ' C unused-parameter annotation
            sqlite3VdbeAddOp4(local0, Cast(SQLITE_C_INT, 99ULL), local9, arg3, local10, CPtr(Const ZString Ptr, CPtr(ZString Ptr, arg4->zAffSdst)), arg3)
            sqlite3VdbeAddOp4Int(local0, Cast(SQLITE_C_INT, 140ULL), local8, local10, local9, arg3)
            Goto c2fb_flow_4
        Case Cast(SQLITE_C_INT, 8ULL)
            Goto c2fb_flow_4
        Case Cast(SQLITE_C_INT, 13ULL)
            local20 = arg4->iSDParm2
            local21 = sqlite3GetTempReg(CPtr(Any Ptr, arg0))
            sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 99ULL), Cast(SQLITE_C_INT, (local9 + ((-Cast(SQLITE_C_INT, ((local20 < Cast(SQLITE_C_INT, &O0ULL)))))))), Cast(SQLITE_C_INT, (arg3 - ((-Cast(SQLITE_C_INT, ((local20 < Cast(SQLITE_C_INT, &O0ULL)))))))), local21)
            If (-Cast(SQLITE_C_INT, ((local20 < Cast(SQLITE_C_INT, &O0ULL))))) Then
                sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 130ULL), local8, local21, local9)
            Else
                sqlite3VdbeAddOp4Int(local0, Cast(SQLITE_C_INT, 140ULL), local8, local21, local9, local20)
            End If
            Goto c2fb_flow_4
        Case Else
            ' C unused-parameter annotation
            ' empty C statement
            ' empty C statement
            If (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, 7ULL))))) Then
                sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 86ULL), arg4->iSdst, arg3)
            Else
                sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 12ULL), arg4->iSDParm)
            End If
            Goto c2fb_flow_4
    End Select
    c2fb_flow_4:
    If local10 Then
        If (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, 9ULL))))) Then
            sqlite3ReleaseTempRange(CPtr(Any Ptr, arg0), local9, arg3)
        Else
            sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local9)
        End If
        sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local10)
    End If
    sqlite3VdbeResolveLabel(local0, local2)
    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2->sortFlags) And Cast(SQLITE_C_INT, &H01ULL))) Then
        sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 38ULL), local5, local3)
        ' empty C statement
    Else
        sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 40ULL), local5, local3)
        ' empty C statement
    End If
    ' empty C statement
    If arg2->regReturn Then
        sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 69ULL), arg2->regReturn)
    End If
    sqlite3VdbeResolveLabel(local0, local1)
End Sub

Sub sqlite3SelectGenerateSortTail CDecl Alias "sqlite3SelectGenerateSortTail" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pSort As SqliteSortContext Ptr, _
    ByVal nColumn As SQLITE_C_INT, _
    ByVal pDestination As SqliteSelectDest Ptr _
)
    If pParse = 0 OrElse pSelect = 0 OrElse pSort = 0 OrElse _
       pDestination = 0 OrElse pSort->pOrderBy = 0 Then Exit Sub
    generateSortTail(pParse, pSelect, pSort, nColumn, pDestination)
End Sub

Private Sub computeLimitRegisters CDecl Alias "computeLimitRegisters" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SQLITE_C_INT)
    Dim local0 As SqliteVdbe Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim local4 As SqliteExpr Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SqliteVdbe Ptr
    Dim c2fb_temp_7 As Short Ptr
    Dim c2fb_temp_8 As Short
    Dim c2fb_temp_9 As u32 Ptr
    Dim c2fb_temp_10 As SQLITE_C_UINT
    Dim c2fb_temp_11 As SQLITE_C_INT Ptr
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SQLITE_C_INT Ptr
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SQLITE_C_INT Ptr
    Dim c2fb_temp_18 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    local4 = arg1->pLimit
    If arg1->iLimit Then
        Return
    End If
    If local4 Then
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        c2fb_temp_4 = CPtr(SQLITE_C_INT Ptr, @(arg1->iLimit))
        c2fb_temp_0 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
        c2fb_temp_1 = (*c2fb_temp_0)
        (*c2fb_temp_0) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
        c2fb_temp_2 = (*c2fb_temp_0)
        c2fb_temp_3 = Cast(SQLITE_C_INT, c2fb_temp_2)
        local1 = c2fb_temp_3
        c2fb_temp_5 = Cast(SQLITE_C_INT, c2fb_temp_3)
        (*c2fb_temp_4) = c2fb_temp_5
        c2fb_temp_6 = CPtr(SqliteVdbe Ptr, sqlite3GetVdbe(CPtr(Any Ptr, arg0)))
        local0 = c2fb_temp_6
        ' C unused-parameter annotation
        If sqlite3ExprIsInteger(CPtr(Any Ptr, local4->pLeft), CPtr(SQLITE_C_INT Ptr, @(local3)), CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, &O0ULL)) Then
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 73ULL), local3, local1)
            ' empty C statement
            If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                sqlite3VdbeGoto(local0, arg2)
            Else
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local3 >= Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->nSelectRow) > Cast(SQLITE_C_INT, sqlite3LogEst(Cast(sqlite3_uint64, local3))))))))))) Then
                    c2fb_temp_7 = CPtr(Short Ptr, @(arg1->nSelectRow))
                    c2fb_temp_8 = Cast(Short, sqlite3LogEst(Cast(sqlite3_uint64, local3)))
                    (*c2fb_temp_7) = c2fb_temp_8
                    c2fb_temp_9 = CPtr(u32 Ptr, @(arg1->selFlags))
                    c2fb_temp_10 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_9)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0004000ULL)))))
                    (*c2fb_temp_9) = Cast(u32, c2fb_temp_10)
                    c2fb_temp_10 = Cast(SQLITE_C_UINT, (*c2fb_temp_9))
                End If
            End If
        Else
            sqlite3ExprCode(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local4->pLeft), local1)
            sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 13ULL), local1)
            ' empty C statement
            ' empty C statement
            sqlite3MayAbort(CPtr(Any Ptr, arg0))
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 17ULL), local1, arg2)
            ' empty C statement
        End If
        If local4->pRight Then
            c2fb_temp_15 = CPtr(SQLITE_C_INT Ptr, @(arg1->iOffset))
            c2fb_temp_11 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
            c2fb_temp_12 = (*c2fb_temp_11)
            (*c2fb_temp_11) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_12 + 1)))
            c2fb_temp_13 = (*c2fb_temp_11)
            c2fb_temp_14 = Cast(SQLITE_C_INT, c2fb_temp_13)
            local2 = c2fb_temp_14
            c2fb_temp_16 = Cast(SQLITE_C_INT, c2fb_temp_14)
            (*c2fb_temp_15) = c2fb_temp_16
            c2fb_temp_17 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
            c2fb_temp_18 = (*c2fb_temp_17)
            (*c2fb_temp_17) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_18 + 1)))
            sqlite3ExprCode(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local4->pRight), local2)
            sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 13ULL), local2)
            ' empty C statement
            sqlite3MayAbort(CPtr(Any Ptr, arg0))
            ' empty C statement
            sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 162ULL), local1, Cast(SQLITE_C_INT, (local2 + Cast(SQLITE_C_INT, 1ULL))), local2)
            ' empty C statement
        End If
    End If
End Sub

Private Function multiSelectCollSeq CDecl Alias "multiSelectCollSeq" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SQLITE_C_INT) As sqlite3CollSeq Ptr
    Dim local0 As sqlite3CollSeq Ptr
    Dim c2fb_temp_0 As sqlite3CollSeq Ptr
    Dim c2fb_temp_1 As sqlite3CollSeq Ptr
    Dim c2fb_temp_2 As sqlite3CollSeq Ptr

    ' C automatic storage declaration
    If arg1->pPrior Then
        c2fb_temp_0 = CPtr(sqlite3CollSeq Ptr, multiSelectCollSeq(arg0, arg1->pPrior, arg2))
        local0 = c2fb_temp_0
    Else
        c2fb_temp_1 = CPtr(sqlite3CollSeq Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        local0 = c2fb_temp_1
    End If
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso ((-Cast(SQLITE_C_INT, ((arg2 < arg1->pEList->nExpr))))))))) Then
        c2fb_temp_2 = CPtr(sqlite3CollSeq Ptr, sqlite3ExprCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pEList->a(arg2).pExpr)))
        local0 = c2fb_temp_2
    End If
    Return local0
End Function

Private Function multiSelectByMergeKeyInfo CDecl Alias "multiSelectByMergeKeyInfo" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SQLITE_C_INT) As sqlite3VdbeKeyInfoPrefix Ptr
    Dim local0 As SqliteExprList Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As sqlite3 Ptr
    Dim local3 As sqlite3VdbeKeyInfoPrefix Ptr
    Dim local4 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local5 As SqliteExprListItem Ptr
    Dim local6 As SqliteExpr Ptr
    Dim local7 As sqlite3CollSeq Ptr
    Dim c2fb_temp_2 As sqlite3CollSeq Ptr
    Dim c2fb_temp_3 As sqlite3CollSeq Ptr
    Dim c2fb_temp_4 As sqlite3CollSeq Ptr
    Dim c2fb_temp_5 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_6 As SqliteExpr Ptr
    Dim c2fb_temp_7 As Any Ptr Ptr
    Dim c2fb_temp_8 As sqlite3CollSeq Ptr
    Dim c2fb_temp_9 As UByte Ptr
    Dim c2fb_temp_10 As UByte

    local0 = arg1->pOrderBy
    local1 = IIf(((-Cast(SQLITE_C_INT, ((local0 <> Cast(SQLITE_C_INT, &O0ULL)))))), local0->nExpr, Cast(SQLITE_C_INT, &O0ULL))
    local2 = arg0->db
    local3 = CPtr(sqlite3VdbeKeyInfoPrefix Ptr, sqlite3KeyInfoAlloc(CPtr(Any Ptr, local2), Cast(SQLITE_C_INT, (local1 + arg2)), Cast(SQLITE_C_INT, 1ULL)))
    If local3 Then
        ' C automatic storage declaration
        c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local4 = c2fb_temp_0
        While (-Cast(SQLITE_C_INT, ((local4 < local1))))
            local5 = CPtr(SqliteExprListItem Ptr, @(local0->a(local4)))
            local6 = local5->pExpr
            ' C automatic storage declaration
            If Cast(SQLITE_C_UINT, (local6->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H000200ULL)))) Then
                c2fb_temp_2 = CPtr(sqlite3CollSeq Ptr, sqlite3ExprCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local6)))
                local7 = c2fb_temp_2
            Else
                c2fb_temp_3 = CPtr(sqlite3CollSeq Ptr, multiSelectCollSeq(arg0, arg1, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local5->u.x.iOrderByCol) - Cast(SQLITE_C_INT, 1ULL)))))
                local7 = c2fb_temp_3
                If (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_4 = local2->pDfltColl
                    local7 = c2fb_temp_4
                End If
                c2fb_temp_5 = CPtr(SqliteExpr Ptr Ptr, @(local0->a(local4).pExpr))
                c2fb_temp_6 = CPtr(SqliteExpr Ptr, sqlite3ExprAddCollateString(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local6), CPtr(Const ZString Ptr, local7->zName)))
                (*c2fb_temp_5) = c2fb_temp_6
            End If
            ' C unused-parameter annotation
            c2fb_temp_7 = CPtr(Any Ptr Ptr, @(local3->aColl(local4)))
            c2fb_temp_8 = local7
            (*c2fb_temp_7) = CPtr(Any Ptr, c2fb_temp_8)
            c2fb_temp_8 = CPtr(sqlite3CollSeq Ptr, (*c2fb_temp_7))
            c2fb_temp_9 = CPtr(UByte Ptr, @(local3->aSortFlags[local4]))
            c2fb_temp_10 = Cast(UByte, local0->a(local4).fg.sortFlags)
            (*c2fb_temp_9) = c2fb_temp_10
        c2fb_flow_1:
            c2fb_temp_1 = local4
            local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
        Wend
        c2fb_flow_0:
    End If
    Return local3
End Function

Private Sub generateWithRecursiveQuery CDecl Alias "generateWithRecursiveQuery" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteSelectDest Ptr)
    Dim local0 As SqliteSrcList Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SqliteVdbe Ptr
    Dim local3 As SqliteSelect Ptr
    Dim local4 As SqliteSelect Ptr
    Dim local5 As SQLITE_C_INT
    Dim local6 As SQLITE_C_INT
    Dim local7 As SQLITE_C_INT
    Dim local8 As SQLITE_C_INT
    Dim local9 As SQLITE_C_INT
    Dim local10 As SQLITE_C_INT
    Dim local11 As SQLITE_C_INT
    Dim local12 As SQLITE_C_INT
    Dim local13 As SqliteSelectDest
    Dim local14 As SQLITE_C_INT
    Dim local15 As SQLITE_C_INT
    Dim local16 As SqliteExprList Ptr
    Dim local17 As SqliteExpr Ptr
    Dim local18 As SQLITE_C_INT
    Dim local19 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As Short Ptr
    Dim c2fb_temp_2 As Short
    Dim c2fb_temp_3 As SqliteExpr Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_7 As SqliteExpr Ptr
    Dim c2fb_temp_8 As SQLITE_C_INT Ptr
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT Ptr
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SqliteExprList Ptr
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SQLITE_C_INT Ptr
    Dim c2fb_temp_17 As SQLITE_C_INT
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim c2fb_temp_20 As SQLITE_C_INT Ptr
    Dim c2fb_temp_21 As SQLITE_C_INT
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim c2fb_temp_23 As SQLITE_C_INT
    Dim c2fb_temp_24 As SQLITE_C_INT Ptr
    Dim c2fb_temp_25 As SQLITE_C_INT
    Dim c2fb_temp_26 As SQLITE_C_INT
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim local20 As sqlite3VdbeKeyInfoPrefix Ptr
    Dim c2fb_temp_28 As Any Ptr Ptr
    Dim c2fb_temp_29 As SqliteExprList Ptr
    Dim local21 As sqlite3VdbeKeyInfoPrefix Ptr
    Dim local22 As sqlite3CollSeq Ptr Ptr
    Dim c2fb_temp_30 As SQLITE_C_INT
    Dim c2fb_temp_31 As sqlite3VdbeKeyInfoPrefix Ptr
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As sqlite3CollSeq Ptr Ptr
    Dim c2fb_temp_34 As SQLITE_C_INT
    Dim c2fb_temp_35 As sqlite3CollSeq Ptr Ptr
    Dim c2fb_temp_36 As sqlite3CollSeq Ptr Ptr
    Dim c2fb_temp_37 As sqlite3CollSeq Ptr
    Dim c2fb_temp_38 As sqlite3CollSeq Ptr Ptr
    Dim c2fb_temp_39 As sqlite3CollSeq Ptr
    Dim c2fb_temp_40 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_41 As SqliteExprList Ptr
    Dim c2fb_temp_42 As SqliteSelect Ptr
    Dim c2fb_temp_43 As SqliteSelect Ptr
    Dim c2fb_temp_44 As u8 Ptr
    Dim c2fb_temp_45 As UByte
    Dim c2fb_temp_46 As SqliteSelect Ptr
    Dim c2fb_temp_47 As SqliteSelect Ptr Ptr
    Dim c2fb_temp_48 As SqliteSelect Ptr
    Dim c2fb_temp_49 As SQLITE_C_INT
    Dim c2fb_temp_50 As SqliteSelect Ptr Ptr
    Dim c2fb_temp_51 As SqliteSelect Ptr
    Dim c2fb_temp_52 As SQLITE_C_INT
    Dim c2fb_temp_53 As SQLITE_C_INT
    Dim c2fb_temp_54 As SqliteSelect Ptr Ptr
    Dim c2fb_temp_55 As SqliteSelect Ptr
    Dim c2fb_temp_56 As SqliteSelect Ptr Ptr
    Dim c2fb_temp_57 As SqliteSelect Ptr
    Dim c2fb_temp_58 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_59 As SqliteExprList Ptr
    Dim c2fb_temp_60 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_61 As SqliteExpr Ptr

    local0 = arg1->pSrc
    local1 = arg1->pEList->nExpr
    local2 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local8 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    local11 = Cast(SQLITE_C_INT, &O0ULL)
    local12 = Cast(SQLITE_C_INT, 6ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
#ifndef SQLITE_OMIT_WINDOWFUNC
    If arg1->pWin <> 0 Then
        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"cannot use window functions in recursive queries"))
        Return
    End If
#endif
    If sqlite3AuthCheck(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 33ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)) Then
        Return
    End If
    c2fb_temp_0 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
    local7 = c2fb_temp_0
    c2fb_temp_1 = CPtr(Short Ptr, @(arg1->nSelectRow))
    c2fb_temp_2 = Cast(Short, Cast(SQLITE_C_INT, 320ULL))
    (*c2fb_temp_1) = c2fb_temp_2
    computeLimitRegisters(arg0, arg1, local7)
    c2fb_temp_3 = arg1->pLimit
    local17 = c2fb_temp_3
    c2fb_temp_4 = Cast(SQLITE_C_INT, arg1->iLimit)
    local18 = c2fb_temp_4
    c2fb_temp_5 = Cast(SQLITE_C_INT, arg1->iOffset)
    local19 = c2fb_temp_5
    c2fb_temp_6 = CPtr(SqliteExpr Ptr Ptr, @(arg1->pLimit))
    c2fb_temp_7 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_6) = c2fb_temp_7
    c2fb_temp_10 = CPtr(SQLITE_C_INT Ptr, @(arg1->iLimit))
    c2fb_temp_8 = CPtr(SQLITE_C_INT Ptr, @(arg1->iOffset))
    c2fb_temp_9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_8) = c2fb_temp_9
    c2fb_temp_11 = Cast(SQLITE_C_INT, c2fb_temp_9)
    (*c2fb_temp_10) = c2fb_temp_11
    c2fb_temp_12 = arg1->pOrderBy
    local16 = c2fb_temp_12
    c2fb_temp_13 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local14 = c2fb_temp_13
    While ((-Cast(SQLITE_C_INT, ((local14 < local0->nSrc)))))
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local0->a(local14).fg.flags) Shr 7) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            c2fb_temp_15 = Cast(SQLITE_C_INT, local0->a(local14).iCursor)
            local8 = c2fb_temp_15
            Goto c2fb_flow_0
        End If
    c2fb_flow_1:
        c2fb_temp_14 = local14
        local14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_14 + 1)))
    Wend
    c2fb_flow_0:
    c2fb_temp_16 = CPtr(SQLITE_C_INT Ptr, @(arg0->nTab))
    c2fb_temp_17 = (*c2fb_temp_16)
    (*c2fb_temp_16) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_17 + 1)))
    c2fb_temp_18 = Cast(SQLITE_C_INT, c2fb_temp_17)
    local10 = c2fb_temp_18
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 135ULL))))) Then
        c2fb_temp_19 = Cast(SQLITE_C_INT, IIf(local16, Cast(SQLITE_C_INT, 4ULL), Cast(SQLITE_C_INT, 3ULL)))
        local12 = c2fb_temp_19
        c2fb_temp_20 = CPtr(SQLITE_C_INT Ptr, @(arg0->nTab))
        c2fb_temp_21 = (*c2fb_temp_20)
        (*c2fb_temp_20) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_21 + 1)))
        c2fb_temp_22 = Cast(SQLITE_C_INT, c2fb_temp_21)
        local11 = c2fb_temp_22
    Else
        c2fb_temp_23 = Cast(SQLITE_C_INT, IIf(local16, Cast(SQLITE_C_INT, 5ULL), Cast(SQLITE_C_INT, 6ULL)))
        local12 = c2fb_temp_23
    End If
    sqlite3SelectDestInit(CPtr(Any Ptr, CPtr(SqliteSelectDest Ptr, @(local13))), local12, local10)
    c2fb_temp_24 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
    c2fb_temp_25 = (*c2fb_temp_24)
    (*c2fb_temp_24) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_25 + 1)))
    c2fb_temp_26 = (*c2fb_temp_24)
    c2fb_temp_27 = Cast(SQLITE_C_INT, c2fb_temp_26)
    local9 = c2fb_temp_27
    sqlite3VdbeAddOp3(local2, Cast(SQLITE_C_INT, 123ULL), local8, local9, local1)
    If local16 Then
        local20 = CPtr(sqlite3VdbeKeyInfoPrefix Ptr, multiSelectByMergeKeyInfo(arg0, arg1, Cast(SQLITE_C_INT, 1ULL)))
        sqlite3VdbeAddOp4(local2, Cast(SQLITE_C_INT, 120ULL), local10, Cast(SQLITE_C_INT, (local16->nExpr + Cast(SQLITE_C_INT, 2ULL))), Cast(SQLITE_C_INT, &O0ULL), CPtr(Const ZString Ptr, CPtr(ZString Ptr, local20)), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 9ULL)))))
        c2fb_temp_28 = CPtr(Any Ptr Ptr, @(local13.pOrderBy))
        c2fb_temp_29 = local16
        (*c2fb_temp_28) = CPtr(Any Ptr, c2fb_temp_29)
        c2fb_temp_29 = CPtr(SqliteExprList Ptr, (*c2fb_temp_28))
    Else
        sqlite3VdbeAddOp2(local2, Cast(SQLITE_C_INT, 120ULL), local10, local1)
    End If
    ' empty C statement
    If local11 Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        c2fb_temp_30 = Cast(SQLITE_C_INT, arg1->pEList->nExpr)
        local1 = c2fb_temp_30
        c2fb_temp_31 = CPtr(sqlite3VdbeKeyInfoPrefix Ptr, sqlite3KeyInfoAlloc(CPtr(Any Ptr, arg0->db), local1, Cast(SQLITE_C_INT, 1ULL)))
        local21 = c2fb_temp_31
        If local21 Then
            c2fb_temp_32 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local14 = c2fb_temp_32
            c2fb_temp_33 = CPtr(sqlite3CollSeq Ptr Ptr, (@local21->aColl(0)))
            local22 = c2fb_temp_33
            While (-Cast(SQLITE_C_INT, ((local14 < local1))))
                c2fb_temp_36 = CPtr(sqlite3CollSeq Ptr Ptr, @((*local22)))
                c2fb_temp_37 = CPtr(sqlite3CollSeq Ptr, multiSelectCollSeq(arg0, arg1, local14))
                (*c2fb_temp_36) = c2fb_temp_37
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = (*local22))))) Then
                    c2fb_temp_38 = CPtr(sqlite3CollSeq Ptr Ptr, @((*local22)))
                    c2fb_temp_39 = arg0->db->pDfltColl
                    (*c2fb_temp_38) = c2fb_temp_39
                End If
            c2fb_flow_3:
                c2fb_temp_34 = local14
                local14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_34 + 1)))
                c2fb_temp_35 = local22
                local22 = (c2fb_temp_35 + 1)
            Wend
            c2fb_flow_2:
            sqlite3VdbeAddOp4(local2, Cast(SQLITE_C_INT, 120ULL), local11, local1, Cast(SQLITE_C_INT, &O0ULL), CPtr(Const ZString Ptr, CPtr(Any Ptr, local21)), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 9ULL)))))
        Else
            ' C unused-parameter annotation
        End If
    End If
    c2fb_temp_40 = CPtr(SqliteExprList Ptr Ptr, @(arg1->pOrderBy))
    c2fb_temp_41 = CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_40) = c2fb_temp_41
    c2fb_temp_42 = arg1
    local4 = c2fb_temp_42
    While ((-Cast(SQLITE_C_INT, ((local4 <> Cast(SQLITE_C_INT, &O0ULL))))))
        If Cast(SQLITE_C_UINT, (local4->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000008ULL)))) Then
            sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"recursive aggregate queries not supported"))
            Goto c2fb_label_0
        End If
        c2fb_temp_44 = CPtr(u8 Ptr, @(local4->op))
        c2fb_temp_45 = Cast(UByte, Cast(SQLITE_C_INT, 136ULL))
        (*c2fb_temp_44) = Cast(u8, c2fb_temp_45)
        c2fb_temp_45 = Cast(UByte, (*c2fb_temp_44))
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local4->pPrior->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0002000ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            Goto c2fb_flow_4
        End If
    c2fb_flow_5:
        c2fb_temp_43 = local4->pPrior
        local4 = c2fb_temp_43
    Wend
    c2fb_flow_4:
    c2fb_temp_46 = local4->pPrior
    local3 = c2fb_temp_46
    c2fb_temp_47 = CPtr(SqliteSelect Ptr Ptr, @(local3->pNext))
    c2fb_temp_48 = CPtr(SqliteSelect Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_47) = c2fb_temp_48
    sqlite3VdbeExplainText(arg0, Cast(SQLITE_C_INT, 1ULL), StrPtr(!"SETUP"))
    c2fb_temp_49 = Cast(SQLITE_C_INT, sqlite3Select(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local3), CPtr(Any Ptr, CPtr(SqliteSelectDest Ptr, @(local13)))))
    local15 = c2fb_temp_49
    c2fb_temp_50 = CPtr(SqliteSelect Ptr Ptr, @(local3->pNext))
    c2fb_temp_51 = arg1
    (*c2fb_temp_50) = c2fb_temp_51
    If local15 Then
        Goto c2fb_label_0
    End If
    c2fb_temp_52 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp2(local2, Cast(SQLITE_C_INT, 36ULL), local10, local7))
    local5 = c2fb_temp_52
    ' empty C statement
    sqlite3VdbeAddOp1(local2, Cast(SQLITE_C_INT, 138ULL), local8)
    If local16 Then
        sqlite3VdbeAddOp3(local2, Cast(SQLITE_C_INT, 96ULL), local10, Cast(SQLITE_C_INT, (local16->nExpr + Cast(SQLITE_C_INT, 1ULL))), local9)
    Else
        sqlite3VdbeAddOp2(local2, Cast(SQLITE_C_INT, 136ULL), local10, local9)
    End If
    sqlite3VdbeAddOp1(local2, Cast(SQLITE_C_INT, 132ULL), local10)
    c2fb_temp_53 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
    local6 = c2fb_temp_53
    codeOffset(local2, local19, local6)
    selectInnerLoop(arg0, arg1, local8, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), arg2, local6, local7)
    If local18 Then
        sqlite3VdbeAddOp2(local2, Cast(SQLITE_C_INT, 63ULL), local18, local7)
        ' empty C statement
    End If
    sqlite3VdbeResolveLabel(local2, local6)
    c2fb_temp_54 = CPtr(SqliteSelect Ptr Ptr, @(local4->pPrior))
    c2fb_temp_55 = CPtr(SqliteSelect Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_54) = c2fb_temp_55
    sqlite3VdbeExplainText(arg0, Cast(SQLITE_C_INT, 1ULL), StrPtr(!"RECURSIVE STEP"))
    sqlite3Select(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), CPtr(Any Ptr, CPtr(SqliteSelectDest Ptr, @(local13))))
    ' C unused-parameter annotation
    c2fb_temp_56 = CPtr(SqliteSelect Ptr Ptr, @(local4->pPrior))
    c2fb_temp_57 = local3
    (*c2fb_temp_56) = c2fb_temp_57
    sqlite3VdbeGoto(local2, local5)
    sqlite3VdbeResolveLabel(local2, local7)
    c2fb_label_0:
    sqlite3ExprListDelete(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, arg1->pOrderBy))
    c2fb_temp_58 = CPtr(SqliteExprList Ptr Ptr, @(arg1->pOrderBy))
    c2fb_temp_59 = local16
    (*c2fb_temp_58) = c2fb_temp_59
    c2fb_temp_60 = CPtr(SqliteExpr Ptr Ptr, @(arg1->pLimit))
    c2fb_temp_61 = local17
    (*c2fb_temp_60) = c2fb_temp_61
    Return
End Sub

Private Function unionWithLimitOne CDecl Alias "unionWithLimitOne" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteSelect Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT

    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) <> Cast(SQLITE_C_INT, 135ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((arg1->pLimit = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If arg1->pLimit->pRight Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_0
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((sqlite3ExprIsInteger(CPtr(Any Ptr, arg1->pLimit->pLeft), CPtr(SQLITE_C_INT Ptr, @(local0)), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)) = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((local0 <> Cast(SQLITE_C_INT, 1ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg0)->dbOptFlags And (Cast(SQLITE_C_UINT, &H80000000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    Return Cast(SQLITE_C_INT, 1ULL)
End Function

Private Function generateOutputSubroutine CDecl Alias "generateOutputSubroutine" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteSelectDest Ptr, ByVal arg3 As SqliteSelectDest Ptr, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As sqlite3VdbeKeyInfoPrefix Ptr, ByVal arg7 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SqliteVdbe Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim local6 As SQLITE_C_INT
    Dim local7 As SQLITE_C_INT
    Dim local8 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT Ptr
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim local9 As SQLITE_C_INT
    Dim local10 As SQLITE_C_INT
    Dim local11 As SQLITE_C_INT
    Dim local12 As SQLITE_C_INT
    Dim local13 As SQLITE_C_INT
    Dim local14 As SqliteExprList Ptr
    Dim local15 As SQLITE_C_INT
    Dim c2fb_temp_9 As SqliteExprList Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SQLITE_C_INT

    local0 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, sqlite3VdbeCurrentAddr(local0))
    local2 = c2fb_temp_0
    c2fb_temp_1 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
    local1 = c2fb_temp_1
    If arg5 Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        c2fb_temp_2 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 17ULL), arg5))
        local3 = c2fb_temp_2
        ' empty C statement
        c2fb_temp_3 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp4(local0, Cast(SQLITE_C_INT, 92ULL), arg2->iSdst, Cast(SQLITE_C_INT, (arg5 + Cast(SQLITE_C_INT, 1ULL))), arg2->nSdst, CPtr(Const ZString Ptr, CPtr(ZString Ptr, CPtr(sqlite3VdbeKeyInfoPrefix Ptr, sqlite3KeyInfoRef(CPtr(Any Ptr, arg6))))), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 9ULL))))))
        local4 = c2fb_temp_3
        sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 14ULL), Cast(SQLITE_C_INT, (local4 + Cast(SQLITE_C_INT, 2ULL))), local1, Cast(SQLITE_C_INT, (local4 + Cast(SQLITE_C_INT, 2ULL))))
        ' empty C statement
        sqlite3VdbeJumpHere(local0, local3)
        sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 82ULL), arg2->iSdst, Cast(SQLITE_C_INT, (arg5 + Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, (arg2->nSdst - Cast(SQLITE_C_INT, 1ULL))))
        sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, 1ULL), arg5)
    End If
    If arg0->db->mallocFailed Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    codeOffset(local0, arg1->iOffset, local1)
    Select Case arg3->eDest
        Case Cast(SQLITE_C_INT, 6ULL), Cast(SQLITE_C_INT, 3ULL), Cast(SQLITE_C_INT, 12ULL), Cast(SQLITE_C_INT, 10ULL)
            local5 = sqlite3GetTempReg(CPtr(Any Ptr, arg0))
            local6 = sqlite3GetTempReg(CPtr(Any Ptr, arg0))
            local7 = arg3->iSDParm
            ' empty C statement
            ' empty C statement
            ' empty C statement
            ' empty C statement
            sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 99ULL), arg2->iSdst, arg2->nSdst, local5)
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg3->eDest) = Cast(SQLITE_C_INT, 3ULL))))) Then
                sqlite3VdbeAddOp4Int(local0, Cast(SQLITE_C_INT, 140ULL), Cast(SQLITE_C_INT, (local7 + Cast(SQLITE_C_INT, 1ULL))), local5, arg2->iSdst, arg2->nSdst)
            End If
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 129ULL), local7, local6)
            sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 130ULL), local7, local5, local6)
            sqlite3VdbeChangeP5(local0, Cast(SQLITE_C_INT, &H08ULL))
            sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local6)
            sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local5)
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 1ULL)
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, 1ULL), arg3->iSDParm)
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 9ULL)
            ' C automatic storage declaration
            ' empty C statement
            c2fb_temp_4 = Cast(SQLITE_C_INT, sqlite3GetTempReg(CPtr(Any Ptr, arg0)))
            local8 = c2fb_temp_4
            sqlite3VdbeAddOp4(local0, Cast(SQLITE_C_INT, 99ULL), arg2->iSdst, arg2->nSdst, local8, CPtr(Const ZString Ptr, CPtr(ZString Ptr, arg3->zAffSdst)), arg2->nSdst)
            sqlite3VdbeAddOp4Int(local0, Cast(SQLITE_C_INT, 140ULL), arg3->iSDParm, local8, arg2->iSdst, arg2->nSdst)
            If (-Cast(SQLITE_C_INT, ((arg3->iSDParm2 > Cast(SQLITE_C_INT, &O0ULL))))) Then
                ' C unused-parameter annotation
                sqlite3VdbeAddOp4Int(local0, Cast(SQLITE_C_INT, 185ULL), arg3->iSDParm2, Cast(SQLITE_C_INT, &O0ULL), arg2->iSdst, arg2->nSdst)
                sqlite3VdbeExplainText(arg0, Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"CREATE BLOOM FILTER"))
            End If
            sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local8)
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 8ULL)
            ' empty C statement
            sqlite3ExprCodeMove(CPtr(Any Ptr, arg0), arg2->iSdst, arg3->iSDParm, arg2->nSdst)
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 11ULL)
            If (-Cast(SQLITE_C_INT, ((arg3->iSdst = Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_5 = CPtr(SQLITE_C_INT Ptr, @(arg3->iSdst))
                c2fb_temp_6 = Cast(SQLITE_C_INT, sqlite3GetTempRange(CPtr(Any Ptr, arg0), arg2->nSdst))
                (*c2fb_temp_5) = c2fb_temp_6
                c2fb_temp_7 = CPtr(SQLITE_C_INT Ptr, @(arg3->nSdst))
                c2fb_temp_8 = Cast(SQLITE_C_INT, arg2->nSdst)
                (*c2fb_temp_7) = c2fb_temp_8
            End If
            sqlite3ExprCodeMove(CPtr(Any Ptr, arg0), arg2->iSdst, arg3->iSdst, arg2->nSdst)
            sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 12ULL), arg3->iSDParm)
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 4ULL), Cast(SQLITE_C_INT, 5ULL)
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            local15 = arg3->iSDParm
            c2fb_temp_9 = CPtr(SqliteExprList Ptr, arg3->pOrderBy)
            local14 = c2fb_temp_9
            ' C unused-parameter annotation
            c2fb_temp_10 = Cast(SQLITE_C_INT, local14->nExpr)
            local9 = c2fb_temp_10
            c2fb_temp_11 = Cast(SQLITE_C_INT, sqlite3GetTempReg(CPtr(Any Ptr, arg0)))
            local10 = c2fb_temp_11
            c2fb_temp_12 = Cast(SQLITE_C_INT, sqlite3GetTempRange(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, (local9 + Cast(SQLITE_C_INT, 2ULL)))))
            local11 = c2fb_temp_12
            c2fb_temp_13 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local11 + local9)) + Cast(SQLITE_C_INT, 1ULL))))
            local12 = c2fb_temp_13
            sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 99ULL), arg2->iSdst, arg2->nSdst, local12)
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg3->eDest) = Cast(SQLITE_C_INT, 4ULL))))) Then
                sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 140ULL), Cast(SQLITE_C_INT, (local15 + Cast(SQLITE_C_INT, 1ULL))), local12)
            End If
            c2fb_temp_14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local13 = c2fb_temp_14
            While (-Cast(SQLITE_C_INT, ((local13 < local9))))
                sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 83ULL), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (arg2->iSdst + Cast(SQLITE_C_INT, local14->a(local13).u.x.iOrderByCol))) - Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, (local11 + local13)))
            c2fb_flow_2:
                c2fb_temp_15 = local13
                local13 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_15 + 1)))
            Wend
            c2fb_flow_1:
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 128ULL), local15, Cast(SQLITE_C_INT, (local11 + local9)))
            sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 99ULL), local11, Cast(SQLITE_C_INT, (local9 + Cast(SQLITE_C_INT, 2ULL))), local10)
            sqlite3VdbeAddOp4Int(local0, Cast(SQLITE_C_INT, 140ULL), local15, local10, local11, Cast(SQLITE_C_INT, (local9 + Cast(SQLITE_C_INT, 2ULL))))
            sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local10)
            sqlite3ReleaseTempRange(CPtr(Any Ptr, arg0), local11, Cast(SQLITE_C_INT, (local9 + Cast(SQLITE_C_INT, 2ULL))))
            Goto c2fb_flow_0
        Case Cast(SQLITE_C_INT, 2ULL)
            Goto c2fb_flow_0
        Case Else
            ' C unused-parameter annotation
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 86ULL), arg2->iSdst, arg2->nSdst)
            Goto c2fb_flow_0
    End Select
    c2fb_flow_0:
    If arg1->iLimit Then
        sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 63ULL), arg1->iLimit, arg7)
        ' empty C statement
    End If
    sqlite3VdbeResolveLabel(local0, local1)
    sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 69ULL), arg4)
    Return local2
End Function

Private Function multiSelectByMerge CDecl Alias "multiSelectByMerge" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteSelectDest Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim local2 As SqliteSelect Ptr
    Dim local3 As SqliteSelect Ptr
    Dim local4 As SQLITE_C_INT
    Dim local5 As SqliteVdbe Ptr
    Dim local6 As SqliteSelectDest
    Dim local7 As SqliteSelectDest
    Dim local8 As SQLITE_C_INT
    Dim local9 As SQLITE_C_INT
    Dim local10 As SQLITE_C_INT
    Dim local11 As SQLITE_C_INT
    Dim local12 As SQLITE_C_INT
    Dim local13 As SQLITE_C_INT
    Dim local14 As SQLITE_C_INT
    Dim local15 As SQLITE_C_INT
    Dim local16 As SQLITE_C_INT
    Dim local17 As SQLITE_C_INT
    Dim local18 As SQLITE_C_INT
    Dim local19 As SQLITE_C_INT
    Dim local20 As SQLITE_C_INT
    Dim local21 As SQLITE_C_INT
    Dim local22 As SQLITE_C_INT
    Dim local23 As SQLITE_C_INT
    Dim local24 As SQLITE_C_INT
    Dim local25 As SQLITE_C_INT
    Dim local26 As SQLITE_C_INT
    Dim local27 As SQLITE_C_INT
    Dim local28 As SQLITE_C_INT
    Dim local29 As SQLITE_C_INT
    Dim local30 As SQLITE_C_INT
    Dim local31 As sqlite3VdbeKeyInfoPrefix Ptr
    Dim local32 As sqlite3VdbeKeyInfoPrefix Ptr
    Dim local33 As sqlite3 Ptr
    Dim local34 As SqliteExprList Ptr
    Dim local35 As SQLITE_C_INT
    Dim local36 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_0 As sqlite3 Ptr
    Dim c2fb_temp_1 As SqliteVdbe Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SqliteExprList Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim local37 As SqliteExprListItem Ptr
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SqliteExprListItem Ptr
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SqliteExprListItem Ptr
    Dim local38 As SqliteExpr Ptr
    Dim c2fb_temp_13 As SqliteExprList Ptr
    Dim c2fb_temp_14 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_15 As SqliteExprList Ptr
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As UShort Ptr
    Dim c2fb_temp_18 As UShort
    Dim c2fb_temp_19 As SQLITE_C_UINT Ptr
    Dim local39 As SqliteExprListItem Ptr
    Dim local40 As SQLITE_C_INT
    Dim c2fb_temp_20 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_21 As SQLITE_C_UINT
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim c2fb_temp_23 As SqliteExprListItem Ptr
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As SqliteExprListItem Ptr
    Dim c2fb_temp_26 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_27 As SQLITE_C_UINT
    Dim c2fb_temp_28 As SQLITE_C_INT
    Dim c2fb_temp_29 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_30 As sqlite3VdbeKeyInfoPrefix Ptr
    Dim c2fb_temp_31 As SQLITE_C_INT
    Dim local41 As SQLITE_C_INT
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As SQLITE_C_INT Ptr
    Dim c2fb_temp_34 As SQLITE_C_INT
    Dim c2fb_temp_35 As sqlite3VdbeKeyInfoPrefix Ptr
    Dim c2fb_temp_36 As SQLITE_C_INT
    Dim c2fb_temp_37 As SQLITE_C_INT
    Dim c2fb_temp_38 As Any Ptr Ptr
    Dim c2fb_temp_39 As sqlite3CollSeq Ptr
    Dim c2fb_temp_40 As UByte Ptr
    Dim c2fb_temp_41 As UByte
    Dim c2fb_temp_42 As SQLITE_C_INT
    Dim c2fb_temp_43 As SqliteSelect Ptr
    Dim c2fb_temp_44 As SqliteSelect Ptr
    Dim c2fb_temp_45 As SQLITE_C_INT
    Dim c2fb_temp_46 As SqliteSelect Ptr
    Dim c2fb_temp_47 As SqliteSelect Ptr
    Dim c2fb_temp_48 As SQLITE_C_INT
    Dim c2fb_temp_49 As SQLITE_C_INT
    Dim c2fb_temp_50 As SqliteSelect Ptr
    Dim c2fb_temp_51 As SqliteSelect Ptr
    Dim c2fb_temp_52 As SqliteSelect Ptr Ptr
    Dim c2fb_temp_53 As SqliteSelect Ptr
    Dim c2fb_temp_54 As SqliteSelect Ptr Ptr
    Dim c2fb_temp_55 As SqliteSelect Ptr
    Dim c2fb_temp_56 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_57 As SqliteExprList Ptr
    Dim c2fb_temp_58 As SQLITE_C_INT Ptr
    Dim c2fb_temp_59 As SQLITE_C_INT
    Dim c2fb_temp_60 As SQLITE_C_INT
    Dim c2fb_temp_61 As SQLITE_C_INT
    Dim c2fb_temp_62 As SQLITE_C_INT Ptr
    Dim c2fb_temp_63 As SQLITE_C_INT
    Dim c2fb_temp_64 As SQLITE_C_INT
    Dim c2fb_temp_65 As SQLITE_C_INT
    Dim c2fb_temp_66 As SQLITE_C_INT
    Dim c2fb_temp_67 As SQLITE_C_INT
    Dim c2fb_temp_68 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_69 As SqliteExpr Ptr
    Dim c2fb_temp_70 As SQLITE_C_INT Ptr
    Dim c2fb_temp_71 As SQLITE_C_INT
    Dim c2fb_temp_72 As SQLITE_C_INT
    Dim c2fb_temp_73 As SQLITE_C_INT
    Dim c2fb_temp_74 As SQLITE_C_INT Ptr
    Dim c2fb_temp_75 As SQLITE_C_INT
    Dim c2fb_temp_76 As SQLITE_C_INT
    Dim c2fb_temp_77 As SQLITE_C_INT
    Dim c2fb_temp_78 As SQLITE_C_INT Ptr
    Dim c2fb_temp_79 As SQLITE_C_INT
    Dim c2fb_temp_80 As SQLITE_C_INT
    Dim c2fb_temp_81 As SQLITE_C_INT
    Dim c2fb_temp_82 As SQLITE_C_INT Ptr
    Dim c2fb_temp_83 As SQLITE_C_INT
    Dim c2fb_temp_84 As SQLITE_C_INT
    Dim c2fb_temp_85 As SQLITE_C_INT
    Dim c2fb_temp_86 As SQLITE_C_INT
    Dim c2fb_temp_87 As SQLITE_C_INT
    Dim c2fb_temp_88 As SQLITE_C_INT Ptr
    Dim c2fb_temp_89 As SQLITE_C_INT
    Dim c2fb_temp_90 As SQLITE_C_INT
    Dim c2fb_temp_91 As SQLITE_C_INT
    Dim c2fb_temp_92 As SQLITE_C_INT
    Dim c2fb_temp_93 As SQLITE_C_INT
    Dim c2fb_temp_94 As SQLITE_C_INT Ptr
    Dim c2fb_temp_95 As SQLITE_C_INT
    Dim c2fb_temp_96 As SQLITE_C_INT Ptr
    Dim c2fb_temp_97 As SQLITE_C_INT
    Dim c2fb_temp_98 As SQLITE_C_INT Ptr
    Dim c2fb_temp_99 As SQLITE_C_INT
    Dim c2fb_temp_100 As SQLITE_C_INT Ptr
    Dim c2fb_temp_101 As SQLITE_C_INT
    Dim c2fb_temp_102 As SQLITE_C_INT
    Dim c2fb_temp_103 As SQLITE_C_INT
    Dim c2fb_temp_104 As SQLITE_C_INT
    Dim c2fb_temp_105 As SQLITE_C_INT
    Dim c2fb_temp_106 As SQLITE_C_INT
    Dim c2fb_temp_107 As SQLITE_C_INT
    Dim c2fb_temp_108 As Short Ptr
    Dim c2fb_temp_109 As Short
    Dim c2fb_temp_110 As SQLITE_C_INT
    Dim c2fb_temp_111 As Short Ptr
    Dim c2fb_temp_112 As Short
    Dim c2fb_temp_113 As SQLITE_C_INT
    Dim c2fb_temp_114 As SQLITE_C_INT
    Dim c2fb_temp_115 As SQLITE_C_INT
    Dim c2fb_temp_116 As SQLITE_C_INT
    Dim c2fb_temp_117 As SQLITE_C_INT
    Dim c2fb_temp_118 As SQLITE_C_INT
    Dim c2fb_temp_119 As SQLITE_C_INT
    Dim c2fb_temp_120 As SQLITE_C_INT
    Dim c2fb_temp_121 As Any Ptr
    Dim c2fb_temp_122 As SqliteSelect Ptr Ptr
    Dim c2fb_temp_123 As SqliteSelect Ptr
    Dim c2fb_temp_124 As SqliteSelect Ptr Ptr
    Dim c2fb_temp_125 As SqliteSelect Ptr
    Dim c2fb_temp_126 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_127 As SqliteExprList Ptr

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
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local15 = Cast(SQLITE_C_INT, &O0ULL)
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
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local31 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = arg0->db
    local33 = c2fb_temp_0
    c2fb_temp_1 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    local5 = c2fb_temp_1
    ' C unused-parameter annotation
    c2fb_temp_2 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
    local28 = c2fb_temp_2
    c2fb_temp_3 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
    local27 = c2fb_temp_3
    c2fb_temp_4 = Cast(SQLITE_C_INT, arg1->op)
    local30 = c2fb_temp_4
    ' C unused-parameter annotation
    c2fb_temp_5 = arg1->pOrderBy
    local34 = c2fb_temp_5
    ' C unused-parameter annotation
    c2fb_temp_6 = Cast(SQLITE_C_INT, local34->nExpr)
    local35 = c2fb_temp_6
    If (-Cast(SQLITE_C_INT, ((local30 <> Cast(SQLITE_C_INT, 136ULL))))) Then
        c2fb_temp_7 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
        local0 = c2fb_temp_7
        While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local33->mallocFailed) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local0 <= arg1->pEList->nExpr))))))))
            ' C automatic storage declaration
            c2fb_temp_9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local1 = c2fb_temp_9
            c2fb_temp_10 = CPtr(SqliteExprListItem Ptr, (@local34->a(0)))
            local37 = c2fb_temp_10
            While (-Cast(SQLITE_C_INT, ((local1 < local35))))
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local37->u.x.iOrderByCol) = local0)))) Then
                    Goto c2fb_flow_2
                End If
            c2fb_flow_3:
                c2fb_temp_11 = local1
                local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_11 + 1)))
                c2fb_temp_12 = local37
                local37 = (c2fb_temp_12 + 1)
            Wend
            c2fb_flow_2:
            If (-Cast(SQLITE_C_INT, ((local1 = local35)))) Then
                local38 = CPtr(SqliteExpr Ptr, sqlite3ExprInt32(CPtr(Any Ptr, local33), local0))
                If (-Cast(SQLITE_C_INT, ((local38 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    Return Cast(SQLITE_C_INT, 7ULL)
                End If
                c2fb_temp_14 = CPtr(SqliteExprList Ptr Ptr, @(arg1->pOrderBy))
                c2fb_temp_13 = CPtr(SqliteExprList Ptr, sqlite3ExprListAppend(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local34), CPtr(Any Ptr, local38)))
                local34 = c2fb_temp_13
                c2fb_temp_15 = c2fb_temp_13
                (*c2fb_temp_14) = c2fb_temp_15
                If local34 Then
                    c2fb_temp_16 = local35
                    local35 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_16 + 1)))
                    c2fb_temp_17 = CPtr(UShort Ptr, @(local34->a(c2fb_temp_16).u.x.iOrderByCol))
                    c2fb_temp_18 = Cast(UShort, Cast(UShort, local0))
                    (*c2fb_temp_17) = c2fb_temp_18
                End If
            End If
        c2fb_flow_1:
            c2fb_temp_8 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_8 + 1)))
        Wend
        c2fb_flow_0:
    End If
    c2fb_temp_19 = CPtr(SQLITE_C_UINT Ptr, CPtr(Any Ptr, sqlite3DbMallocRawNN(CPtr(Any Ptr, local33), Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SQLITE_C_UINT))) * Cast(sqlite3_uint64, (Cast(SQLITE_C_INT, (local35 + Cast(SQLITE_C_INT, 1ULL))))))))))
    local36 = c2fb_temp_19
    If local36 Then
        ' C automatic storage declaration
        local40 = Cast(SQLITE_C_INT, &O0ULL)
        c2fb_temp_20 = CPtr(SQLITE_C_UINT Ptr, @(local36[Cast(SQLITE_C_INT, &O0ULL)]))
        c2fb_temp_21 = Cast(SQLITE_C_UINT, local35)
        (*c2fb_temp_20) = c2fb_temp_21
        c2fb_temp_22 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
        local0 = c2fb_temp_22
        c2fb_temp_23 = CPtr(SqliteExprListItem Ptr, (@local34->a(0)))
        local39 = c2fb_temp_23
        While (-Cast(SQLITE_C_INT, ((local0 <= local35))))
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_26 = CPtr(SQLITE_C_UINT Ptr, @(local36[local0]))
            c2fb_temp_27 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local39->u.x.iOrderByCol) - Cast(SQLITE_C_INT, 1ULL))))
            (*c2fb_temp_26) = c2fb_temp_27
            If (-Cast(SQLITE_C_INT, ((local36[local0] <> Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, local0) - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))))) Then
                c2fb_temp_28 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                local40 = c2fb_temp_28
            End If
        c2fb_flow_5:
            c2fb_temp_24 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_24 + 1)))
            c2fb_temp_25 = local39
            local39 = (c2fb_temp_25 + 1)
        Wend
        c2fb_flow_4:
        If (-Cast(SQLITE_C_INT, ((local40 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            sqlite3DbFreeNN(CPtr(Any Ptr, local33), CPtr(Any Ptr, local36))
            c2fb_temp_29 = CPtr(SQLITE_C_UINT Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            local36 = c2fb_temp_29
        End If
    End If
    c2fb_temp_30 = CPtr(sqlite3VdbeKeyInfoPrefix Ptr, multiSelectByMergeKeyInfo(arg0, arg1, Cast(SQLITE_C_INT, 1ULL)))
    local32 = c2fb_temp_30
    If (-Cast(SQLITE_C_INT, ((local30 = Cast(SQLITE_C_INT, 136ULL))))) Then
        c2fb_temp_31 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local24 = c2fb_temp_31
    Else
        local41 = arg1->pEList->nExpr
        ' C unused-parameter annotation
        c2fb_temp_32 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg0->nMem + Cast(SQLITE_C_INT, 1ULL))))
        local24 = c2fb_temp_32
        c2fb_temp_33 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
        c2fb_temp_34 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_33) + Cast(SQLITE_C_INT, (local41 + Cast(SQLITE_C_INT, 1ULL))))))
        (*c2fb_temp_33) = c2fb_temp_34
        sqlite3VdbeAddOp2(local5, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, &O0ULL), local24)
        c2fb_temp_35 = CPtr(sqlite3VdbeKeyInfoPrefix Ptr, sqlite3KeyInfoAlloc(CPtr(Any Ptr, local33), local41, Cast(SQLITE_C_INT, 1ULL)))
        local31 = c2fb_temp_35
        If local31 Then
            ' C unused-parameter annotation
            c2fb_temp_36 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local0 = c2fb_temp_36
            While (-Cast(SQLITE_C_INT, ((local0 < local41))))
                c2fb_temp_38 = CPtr(Any Ptr Ptr, @(local31->aColl(local0)))
                c2fb_temp_39 = CPtr(sqlite3CollSeq Ptr, multiSelectCollSeq(arg0, arg1, local0))
                (*c2fb_temp_38) = CPtr(Any Ptr, c2fb_temp_39)
                c2fb_temp_39 = CPtr(sqlite3CollSeq Ptr, (*c2fb_temp_38))
                c2fb_temp_40 = CPtr(UByte Ptr, @(local31->aSortFlags[local0]))
                c2fb_temp_41 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_40) = c2fb_temp_41
            c2fb_flow_7:
                c2fb_temp_37 = local0
                local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_37 + 1)))
            Wend
            c2fb_flow_6:
        End If
    End If
    c2fb_temp_42 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
    local4 = c2fb_temp_42
    If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local30 = Cast(SQLITE_C_INT, 136ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local30 = Cast(SQLITE_C_INT, 135ULL)))))))))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local33)->dbOptFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H00200000ULL)))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
        c2fb_temp_43 = arg1
        local3 = c2fb_temp_43
        While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local3->pPrior <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->op) = local30))))))))
            c2fb_temp_45 = local4
            local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_45 + 1)))
            ' C unused-parameter annotation
        c2fb_flow_9:
            c2fb_temp_44 = local3->pPrior
            local3 = c2fb_temp_44
        Wend
        c2fb_flow_8:
    End If
    If (-Cast(SQLITE_C_INT, ((local4 <= Cast(SQLITE_C_INT, 3ULL))))) Then
        c2fb_temp_46 = arg1
        local3 = c2fb_temp_46
    Else
        c2fb_temp_47 = arg1
        local3 = c2fb_temp_47
        c2fb_temp_48 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 2ULL))
        local0 = c2fb_temp_48
        While (-Cast(SQLITE_C_INT, ((local0 < local4))))
            c2fb_temp_50 = local3->pPrior
            local3 = c2fb_temp_50
        c2fb_flow_11:
            c2fb_temp_49 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local0 + Cast(SQLITE_C_INT, 2ULL))))
            local0 = c2fb_temp_49
        Wend
        c2fb_flow_10:
    End If
    c2fb_temp_51 = local3->pPrior
    local2 = c2fb_temp_51
    ' C unused-parameter annotation
    c2fb_temp_52 = CPtr(SqliteSelect Ptr Ptr, @(local3->pPrior))
    c2fb_temp_53 = CPtr(SqliteSelect Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_52) = c2fb_temp_53
    c2fb_temp_54 = CPtr(SqliteSelect Ptr Ptr, @(local2->pNext))
    c2fb_temp_55 = CPtr(SqliteSelect Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_54) = c2fb_temp_55
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_56 = CPtr(SqliteExprList Ptr Ptr, @(local2->pOrderBy))
    c2fb_temp_57 = CPtr(SqliteExprList Ptr, sqlite3ExprListDup(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, local34), Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_56) = c2fb_temp_57
    sqlite3ResolveOrderGroupBy(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), CPtr(Any Ptr, arg1->pOrderBy), StrPtr(!"ORDER"))
    sqlite3ResolveOrderGroupBy(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local2), CPtr(Any Ptr, local2->pOrderBy), StrPtr(!"ORDER"))
    computeLimitRegisters(arg0, arg1, local28)
    If (-Cast(SQLITE_C_INT, ((arg1->iLimit AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local30 = Cast(SQLITE_C_INT, 136ULL))))) OrElse unionWithLimitOne(local33, arg1)))))))))) Then
        c2fb_temp_58 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
        c2fb_temp_59 = (*c2fb_temp_58)
        (*c2fb_temp_58) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_59 + 1)))
        c2fb_temp_60 = (*c2fb_temp_58)
        c2fb_temp_61 = Cast(SQLITE_C_INT, c2fb_temp_60)
        local22 = c2fb_temp_61
        c2fb_temp_62 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
        c2fb_temp_63 = (*c2fb_temp_62)
        (*c2fb_temp_62) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_63 + 1)))
        c2fb_temp_64 = (*c2fb_temp_62)
        c2fb_temp_65 = Cast(SQLITE_C_INT, c2fb_temp_64)
        local23 = c2fb_temp_65
        sqlite3VdbeAddOp2(local5, Cast(SQLITE_C_INT, 82ULL), IIf(arg1->iOffset, Cast(SQLITE_C_INT, (arg1->iOffset + Cast(SQLITE_C_INT, 1ULL))), arg1->iLimit), local22)
        sqlite3VdbeAddOp2(local5, Cast(SQLITE_C_INT, 82ULL), local22, local23)
    Else
        c2fb_temp_66 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local23 = c2fb_temp_66
        c2fb_temp_67 = Cast(SQLITE_C_INT, c2fb_temp_66)
        local22 = c2fb_temp_67
    End If
    sqlite3ExprDelete(CPtr(Any Ptr, local33), CPtr(Any Ptr, arg1->pLimit))
    c2fb_temp_68 = CPtr(SqliteExpr Ptr Ptr, @(arg1->pLimit))
    c2fb_temp_69 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_68) = c2fb_temp_69
    c2fb_temp_70 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
    c2fb_temp_71 = (*c2fb_temp_70)
    (*c2fb_temp_70) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_71 + 1)))
    c2fb_temp_72 = (*c2fb_temp_70)
    c2fb_temp_73 = Cast(SQLITE_C_INT, c2fb_temp_72)
    local8 = c2fb_temp_73
    c2fb_temp_74 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
    c2fb_temp_75 = (*c2fb_temp_74)
    (*c2fb_temp_74) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_75 + 1)))
    c2fb_temp_76 = (*c2fb_temp_74)
    c2fb_temp_77 = Cast(SQLITE_C_INT, c2fb_temp_76)
    local9 = c2fb_temp_77
    c2fb_temp_78 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
    c2fb_temp_79 = (*c2fb_temp_78)
    (*c2fb_temp_78) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_79 + 1)))
    c2fb_temp_80 = (*c2fb_temp_78)
    c2fb_temp_81 = Cast(SQLITE_C_INT, c2fb_temp_80)
    local12 = c2fb_temp_81
    c2fb_temp_82 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
    c2fb_temp_83 = (*c2fb_temp_82)
    (*c2fb_temp_82) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_83 + 1)))
    c2fb_temp_84 = (*c2fb_temp_82)
    c2fb_temp_85 = Cast(SQLITE_C_INT, c2fb_temp_84)
    local13 = c2fb_temp_85
    sqlite3SelectDestInit(CPtr(Any Ptr, CPtr(SqliteSelectDest Ptr, @(local6))), Cast(SQLITE_C_INT, 11ULL), local8)
    sqlite3SelectDestInit(CPtr(Any Ptr, CPtr(SqliteSelectDest Ptr, @(local7))), Cast(SQLITE_C_INT, 11ULL), local9)
    sqlite3VdbeExplainString(arg0, Cast(SQLITE_C_INT, 1ULL), StrPtr(!"MERGE (%s)"), CPtr(Const ZString Ptr, sqlite3SelectOpName(arg1->op)))
    c2fb_temp_86 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (sqlite3VdbeCurrentAddr(local5) + Cast(SQLITE_C_INT, 1ULL))))
    local10 = c2fb_temp_86
    c2fb_temp_87 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp3(local5, Cast(SQLITE_C_INT, 11ULL), local8, Cast(SQLITE_C_INT, &O0ULL), local10))
    local29 = c2fb_temp_87
    ' empty C statement
    c2fb_temp_88 = CPtr(SQLITE_C_INT Ptr, @(local2->iLimit))
    c2fb_temp_89 = Cast(SQLITE_C_INT, local22)
    (*c2fb_temp_88) = c2fb_temp_89
    sqlite3VdbeExplainText(arg0, Cast(SQLITE_C_INT, 1ULL), StrPtr(!"LEFT"))
    sqlite3Select(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local2), CPtr(Any Ptr, CPtr(SqliteSelectDest Ptr, @(local6))))
    sqlite3VdbeEndCoroutine(local5, local8)
    sqlite3VdbeJumpHere(local5, local29)
    c2fb_temp_90 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (sqlite3VdbeCurrentAddr(local5) + Cast(SQLITE_C_INT, 1ULL))))
    local11 = c2fb_temp_90
    c2fb_temp_91 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp3(local5, Cast(SQLITE_C_INT, 11ULL), local9, Cast(SQLITE_C_INT, &O0ULL), local11))
    local29 = c2fb_temp_91
    ' empty C statement
    c2fb_temp_92 = Cast(SQLITE_C_INT, arg1->iLimit)
    local25 = c2fb_temp_92
    c2fb_temp_93 = Cast(SQLITE_C_INT, arg1->iOffset)
    local26 = c2fb_temp_93
    c2fb_temp_94 = CPtr(SQLITE_C_INT Ptr, @(arg1->iLimit))
    c2fb_temp_95 = Cast(SQLITE_C_INT, local23)
    (*c2fb_temp_94) = c2fb_temp_95
    c2fb_temp_96 = CPtr(SQLITE_C_INT Ptr, @(arg1->iOffset))
    c2fb_temp_97 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_96) = c2fb_temp_97
    sqlite3VdbeExplainText(arg0, Cast(SQLITE_C_INT, 1ULL), StrPtr(!"RIGHT"))
    sqlite3Select(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), CPtr(Any Ptr, CPtr(SqliteSelectDest Ptr, @(local7))))
    c2fb_temp_98 = CPtr(SQLITE_C_INT Ptr, @(arg1->iLimit))
    c2fb_temp_99 = Cast(SQLITE_C_INT, local25)
    (*c2fb_temp_98) = c2fb_temp_99
    c2fb_temp_100 = CPtr(SQLITE_C_INT Ptr, @(arg1->iOffset))
    c2fb_temp_101 = Cast(SQLITE_C_INT, local26)
    (*c2fb_temp_100) = c2fb_temp_101
    sqlite3VdbeEndCoroutine(local5, local9)
    ' empty C statement
    c2fb_temp_102 = Cast(SQLITE_C_INT, generateOutputSubroutine(arg0, arg1, CPtr(SqliteSelectDest Ptr, @(local6)), arg2, local12, local24, local31, local28))
    local14 = c2fb_temp_102
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local30 = Cast(SQLITE_C_INT, 136ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local30 = Cast(SQLITE_C_INT, 135ULL))))))))) Then
        ' empty C statement
        c2fb_temp_103 = Cast(SQLITE_C_INT, generateOutputSubroutine(arg0, arg1, CPtr(SqliteSelectDest Ptr, @(local7)), arg2, local13, local24, local31, local28))
        local15 = c2fb_temp_103
    End If
    sqlite3KeyInfoUnref(CPtr(Any Ptr, local31))
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local30 = Cast(SQLITE_C_INT, 137ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local30 = Cast(SQLITE_C_INT, 138ULL))))))))) Then
        c2fb_temp_104 = Cast(SQLITE_C_INT, local28)
        local16 = c2fb_temp_104
        c2fb_temp_105 = Cast(SQLITE_C_INT, c2fb_temp_104)
        local17 = c2fb_temp_105
    Else
        ' empty C statement
        c2fb_temp_106 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp2(local5, Cast(SQLITE_C_INT, 10ULL), local13, local15))
        local16 = c2fb_temp_106
        ' empty C statement
        c2fb_temp_107 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp2(local5, Cast(SQLITE_C_INT, 12ULL), local9, local28))
        local17 = c2fb_temp_107
        ' empty C statement
        ' empty C statement
        sqlite3VdbeGoto(local5, local16)
        c2fb_temp_108 = CPtr(Short Ptr, @(arg1->nSelectRow))
        c2fb_temp_109 = Cast(Short, sqlite3LogEstAdd(arg1->nSelectRow, local2->nSelectRow))
        (*c2fb_temp_108) = c2fb_temp_109
    End If
    If (-Cast(SQLITE_C_INT, ((local30 = Cast(SQLITE_C_INT, 138ULL))))) Then
        c2fb_temp_110 = Cast(SQLITE_C_INT, local16)
        local18 = c2fb_temp_110
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->nSelectRow) > Cast(SQLITE_C_INT, local2->nSelectRow))))) Then
            c2fb_temp_111 = CPtr(Short Ptr, @(arg1->nSelectRow))
            c2fb_temp_112 = Cast(Short, local2->nSelectRow)
            (*c2fb_temp_111) = c2fb_temp_112
        End If
    Else
        ' empty C statement
        c2fb_temp_113 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp2(local5, Cast(SQLITE_C_INT, 10ULL), local12, local14))
        local18 = c2fb_temp_113
        ' empty C statement
        sqlite3VdbeAddOp2(local5, Cast(SQLITE_C_INT, 12ULL), local8, local28)
        ' empty C statement
        ' empty C statement
        sqlite3VdbeGoto(local5, local18)
    End If
    c2fb_temp_114 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp2(local5, Cast(SQLITE_C_INT, 10ULL), local12, local14))
    local19 = c2fb_temp_114
    ' empty C statement
    sqlite3VdbeAddOp2(local5, Cast(SQLITE_C_INT, 12ULL), local8, local16)
    ' empty C statement
    ' empty C statement
    sqlite3VdbeGoto(local5, local27)
    If (-Cast(SQLITE_C_INT, ((local30 = Cast(SQLITE_C_INT, 136ULL))))) Then
        c2fb_temp_115 = Cast(SQLITE_C_INT, local19)
        local20 = c2fb_temp_115
    Else
        If (-Cast(SQLITE_C_INT, ((local30 = Cast(SQLITE_C_INT, 138ULL))))) Then
            c2fb_temp_116 = Cast(SQLITE_C_INT, local19)
            local20 = c2fb_temp_116
            c2fb_temp_117 = local19
            local19 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_117 + 1)))
        Else
            c2fb_temp_118 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local19 + Cast(SQLITE_C_INT, 1ULL))))
            local20 = c2fb_temp_118
        End If
    End If
    c2fb_temp_119 = Cast(SQLITE_C_INT, sqlite3VdbeCurrentAddr(local5))
    local21 = c2fb_temp_119
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local30 = Cast(SQLITE_C_INT, 136ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local30 = Cast(SQLITE_C_INT, 135ULL))))))))) Then
        sqlite3VdbeAddOp2(local5, Cast(SQLITE_C_INT, 10ULL), local13, local15)
        ' empty C statement
        sqlite3VdbeAddOp2(local5, Cast(SQLITE_C_INT, 12ULL), local9, local18)
        ' empty C statement
        ' empty C statement
        sqlite3VdbeGoto(local5, local27)
    Else
        c2fb_temp_120 = local21
        local21 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_120 + 1)))
    End If
    sqlite3VdbeJumpHere(local5, local29)
    sqlite3VdbeAddOp2(local5, Cast(SQLITE_C_INT, 12ULL), local8, local17)
    ' empty C statement
    ' empty C statement
    sqlite3VdbeAddOp2(local5, Cast(SQLITE_C_INT, 12ULL), local9, local18)
    ' empty C statement
    ' empty C statement
    If (-Cast(SQLITE_C_INT, ((local36 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3VdbeAddOp4(local5, Cast(SQLITE_C_INT, 91ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), CPtr(Const ZString Ptr, CPtr(ZString Ptr, local36)), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 13ULL)))))
    End If
    sqlite3VdbeResolveLabel(local5, local27)
    sqlite3VdbeAddOp4(local5, Cast(SQLITE_C_INT, 92ULL), local6.iSdst, local7.iSdst, local35, CPtr(Const ZString Ptr, CPtr(ZString Ptr, local32)), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 9ULL)))))
    If (-Cast(SQLITE_C_INT, ((local36 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3VdbeChangeP5(local5, Cast(SQLITE_C_INT, &H01ULL))
    End If
    sqlite3VdbeAddOp3(local5, Cast(SQLITE_C_INT, 14ULL), local19, local20, local21)
    ' empty C statement
    ' empty C statement
    ' empty C statement
    ' empty C statement
    sqlite3VdbeResolveLabel(local5, local28)
    If local3->pPrior Then
        c2fb_temp_121 = CPtr(Any Ptr, sqlite3ParserAddCleanup(CPtr(Any Ptr, arg0), ProcPtr(sqlite3SelectDeleteGeneric), CPtr(Any Ptr, local3->pPrior)))
    End If
    c2fb_temp_122 = CPtr(SqliteSelect Ptr Ptr, @(local3->pPrior))
    c2fb_temp_123 = local2
    (*c2fb_temp_122) = c2fb_temp_123
    c2fb_temp_124 = CPtr(SqliteSelect Ptr Ptr, @(local2->pNext))
    c2fb_temp_125 = local3
    (*c2fb_temp_124) = c2fb_temp_125
    sqlite3ExprListDelete(CPtr(Any Ptr, local33), CPtr(Any Ptr, local2->pOrderBy))
    c2fb_temp_126 = CPtr(SqliteExprList Ptr Ptr, @(local2->pOrderBy))
    c2fb_temp_127 = CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_126) = c2fb_temp_127
    sqlite3VdbeExplainPop(arg0)
    Return (-Cast(SQLITE_C_INT, ((arg0->nErr <> Cast(SQLITE_C_INT, &O0ULL)))))
End Function

Private Function substExpr CDecl Alias "substExpr" (ByVal arg0 As SqliteSubstContext Ptr, ByVal arg1 As SqliteExpr Ptr) As SqliteExpr Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local0 As SqliteExpr Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SqliteExpr Ptr
    Dim local3 As SqliteExpr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SqliteExpr Ptr
    Dim local4 As sqlite3 Ptr
    Dim c2fb_temp_4 As Any Ptr
    Dim c2fb_temp_5 As u8 Ptr
    Dim c2fb_temp_6 As UByte
    Dim c2fb_temp_7 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_8 As SqliteExpr Ptr
    Dim c2fb_temp_9 As SQLITE_C_INT Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As Short Ptr
    Dim c2fb_temp_12 As Short
    Dim c2fb_temp_13 As u32 Ptr
    Dim c2fb_temp_14 As SQLITE_C_UINT
    Dim c2fb_temp_15 As SqliteExpr Ptr
    Dim c2fb_temp_16 As SqliteExpr Ptr
    Dim c2fb_temp_17 As u32 Ptr
    Dim c2fb_temp_18 As SQLITE_C_UINT
    Dim c2fb_temp_19 As SQLITE_C_INT Ptr
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As u8 Ptr
    Dim c2fb_temp_22 As UByte
    Dim c2fb_temp_23 As u32 Ptr
    Dim c2fb_temp_24 As SQLITE_C_UINT
    Dim local5 As sqlite3CollSeq Ptr
    Dim local6 As sqlite3CollSeq Ptr
    Dim c2fb_temp_25 As SqliteExpr Ptr
    Dim c2fb_temp_26 As u32 Ptr
    Dim c2fb_temp_27 As SQLITE_C_UINT
    Dim c2fb_temp_28 As SqliteExpr Ptr
    Dim c2fb_temp_29 As SQLITE_C_INT Ptr
    Dim c2fb_temp_30 As SQLITE_C_INT
    Dim c2fb_temp_31 As u8 Ptr
    Dim c2fb_temp_32 As UByte
    Dim c2fb_temp_33 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_34 As SqliteExpr Ptr
    Dim c2fb_temp_35 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_36 As SqliteExpr Ptr
#ifndef SQLITE_OMIT_WINDOWFUNC
    Dim local7 As SqliteWalkerWindow Ptr
#endif
    Dim c2fb_temp_37 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_38 As SqliteExpr Ptr

    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000001ULL) Or Cast(SQLITE_C_INT, &H000002ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) AndAlso (-Cast(SQLITE_C_INT, ((arg1->w.iJoin = arg0->iTable)))))))) Then
        ' empty C statement
        c2fb_temp_0 = CPtr(SQLITE_C_INT Ptr, @(arg1->w.iJoin))
        c2fb_temp_1 = Cast(SQLITE_C_INT, arg0->iNewTable)
        (*c2fb_temp_0) = c2fb_temp_1
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 168ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((arg1->iTable = arg0->iTable)))))))) AndAlso (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000020ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))))))) Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        c2fb_temp_2 = Cast(SQLITE_C_INT, arg1->iColumn)
        local1 = c2fb_temp_2
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        c2fb_temp_3 = arg0->pEList->a(local1).pExpr
        local2 = c2fb_temp_3
        If sqlite3ExprIsVector(CPtr(Any Ptr, local2)) Then
            sqlite3VectorErrorMsg(CPtr(Any Ptr, arg0->pParse), CPtr(Any Ptr, local2))
        Else
            local4 = arg0->pParse->db
            If (-Cast(SQLITE_C_INT, ((arg0->isOuterJoin AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->op) <> Cast(SQLITE_C_INT, 168ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local2->iTable <> arg0->iNewTable))))))))))))) Then
                c2fb_temp_4 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, @(local3))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteExpr))))
                c2fb_temp_5 = CPtr(u8 Ptr, @(local3.op))
                c2fb_temp_6 = Cast(UByte, Cast(SQLITE_C_INT, 179ULL))
                (*c2fb_temp_5) = Cast(u8, c2fb_temp_6)
                c2fb_temp_6 = Cast(UByte, (*c2fb_temp_5))
                c2fb_temp_7 = CPtr(SqliteExpr Ptr Ptr, @(local3.pLeft))
                c2fb_temp_8 = local2
                (*c2fb_temp_7) = c2fb_temp_8
                c2fb_temp_9 = CPtr(SQLITE_C_INT Ptr, @(local3.iTable))
                c2fb_temp_10 = Cast(SQLITE_C_INT, arg0->iNewTable)
                (*c2fb_temp_9) = c2fb_temp_10
                c2fb_temp_11 = CPtr(Short Ptr, @(local3.iColumn))
                c2fb_temp_12 = Cast(Short, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 99ULL))))
                (*c2fb_temp_11) = c2fb_temp_12
                c2fb_temp_13 = CPtr(u32 Ptr, @(local3.flags))
                c2fb_temp_14 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H040000ULL))
                (*c2fb_temp_13) = Cast(u32, c2fb_temp_14)
                c2fb_temp_14 = Cast(SQLITE_C_UINT, (*c2fb_temp_13))
                c2fb_temp_15 = CPtr(SqliteExpr Ptr, @(local3))
                local2 = c2fb_temp_15
            End If
            ' empty C statement
            c2fb_temp_16 = CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local4), CPtr(Any Ptr, local2), Cast(SQLITE_C_INT, &O0ULL)))
            local0 = c2fb_temp_16
            If local4->mallocFailed Then
                sqlite3ExprDelete(CPtr(Any Ptr, local4), CPtr(Any Ptr, local0))
                Return arg1
            End If
            If arg0->isOuterJoin Then
                c2fb_temp_17 = CPtr(u32 Ptr, @((local0)->flags))
                c2fb_temp_18 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_17)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H200000ULL))))))
                (*c2fb_temp_17) = Cast(u32, c2fb_temp_18)
                c2fb_temp_18 = Cast(SQLITE_C_UINT, (*c2fb_temp_17))
            End If
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->op) = Cast(SQLITE_C_INT, 171ULL))))) Then
                c2fb_temp_19 = CPtr(SQLITE_C_INT Ptr, @(local0->u.iValue))
                c2fb_temp_20 = Cast(SQLITE_C_INT, sqlite3ExprTruthValue(CPtr(Any Ptr, local0)))
                (*c2fb_temp_19) = c2fb_temp_20
                c2fb_temp_21 = CPtr(u8 Ptr, @(local0->op))
                c2fb_temp_22 = Cast(UByte, Cast(SQLITE_C_INT, 156ULL))
                (*c2fb_temp_21) = Cast(u8, c2fb_temp_22)
                c2fb_temp_22 = Cast(UByte, (*c2fb_temp_21))
                c2fb_temp_23 = CPtr(u32 Ptr, @((local0)->flags))
                c2fb_temp_24 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_23)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000800ULL))))))
                (*c2fb_temp_23) = Cast(u32, c2fb_temp_24)
                c2fb_temp_24 = Cast(SQLITE_C_UINT, (*c2fb_temp_23))
            End If
            local5 = CPtr(sqlite3CollSeq Ptr, sqlite3ExprCollSeq(CPtr(Any Ptr, arg0->pParse), CPtr(Any Ptr, local0)))
            local6 = CPtr(sqlite3CollSeq Ptr, sqlite3ExprCollSeq(CPtr(Any Ptr, arg0->pParse), CPtr(Any Ptr, arg0->pCList->a(local1).pExpr)))
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local5 <> local6)))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->op) <> Cast(SQLITE_C_INT, 168ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->op) <> Cast(SQLITE_C_INT, 114ULL)))))))))))))) Then
                c2fb_temp_25 = CPtr(SqliteExpr Ptr, sqlite3ExprAddCollateString(CPtr(Any Ptr, arg0->pParse), CPtr(Any Ptr, local0), (IIf(local6, CPtr(Const ZString Ptr, local6->zName), StrPtr(!"BINARY")))))
                local0 = c2fb_temp_25
            End If
            c2fb_temp_26 = CPtr(u32 Ptr, @((local0)->flags))
            c2fb_temp_27 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_26)) And Cast(SQLITE_C_UINT, (Not Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000200ULL))))))))
            (*c2fb_temp_26) = Cast(u32, c2fb_temp_27)
            c2fb_temp_27 = Cast(SQLITE_C_UINT, (*c2fb_temp_26))
            If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000001ULL) Or Cast(SQLITE_C_INT, &H000002ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                sqlite3SetJoinExpr(CPtr(Any Ptr, local0), arg1->w.iJoin, Cast(SQLITE_C_UINT, (arg1->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000001ULL) Or Cast(SQLITE_C_INT, &H000002ULL))))))))
            End If
            sqlite3ExprDelete(CPtr(Any Ptr, local4), CPtr(Any Ptr, arg1))
            c2fb_temp_28 = local0
            arg1 = c2fb_temp_28
        End If
    Else
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 179ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((arg1->iTable = arg0->iTable)))))))) Then
            c2fb_temp_29 = CPtr(SQLITE_C_INT Ptr, @(arg1->iTable))
            c2fb_temp_30 = Cast(SQLITE_C_INT, arg0->iNewTable)
            (*c2fb_temp_29) = c2fb_temp_30
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 169ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op2) >= arg0->nSelDepth)))))))) Then
            c2fb_temp_31 = CPtr(u8 Ptr, @(arg1->op2))
            c2fb_temp_32 = Cast(UByte, (*c2fb_temp_31))
            (*c2fb_temp_31) = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_32) - 1)))
        End If
        c2fb_temp_33 = CPtr(SqliteExpr Ptr Ptr, @(arg1->pLeft))
        c2fb_temp_34 = CPtr(SqliteExpr Ptr, substExpr(arg0, arg1->pLeft))
        (*c2fb_temp_33) = c2fb_temp_34
        c2fb_temp_35 = CPtr(SqliteExpr Ptr Ptr, @(arg1->pRight))
        c2fb_temp_36 = CPtr(SqliteExpr Ptr, substExpr(arg0, arg1->pRight))
        (*c2fb_temp_35) = c2fb_temp_36
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            substSelect(arg0, arg1->x.pSelect, Cast(SQLITE_C_INT, 1ULL))
        Else
            substExprList(arg0, arg1->x.pList)
        End If
#ifndef SQLITE_OMIT_WINDOWFUNC
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H1000000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            local7 = CPtr(SqliteWalkerWindow Ptr, arg1->y.pWin)
            c2fb_temp_37 = CPtr(SqliteExpr Ptr Ptr, @(local7->pFilter))
            c2fb_temp_38 = CPtr(SqliteExpr Ptr, substExpr(arg0, local7->pFilter))
            (*c2fb_temp_37) = c2fb_temp_38
            substExprList(arg0, local7->pPartition)
            substExprList(arg0, local7->pOrderBy)
        End If
#endif
    End If
    Return arg1
End Function

Private Sub substExprList CDecl Alias "substExprList" (ByVal arg0 As SqliteSubstContext Ptr, ByVal arg1 As SqliteExprList Ptr)
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_3 As SqliteExpr Ptr

    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((local0 < arg1->nExpr))))
        c2fb_temp_2 = CPtr(SqliteExpr Ptr Ptr, @(arg1->a(local0).pExpr))
        c2fb_temp_3 = CPtr(SqliteExpr Ptr, substExpr(arg0, arg1->a(local0).pExpr))
        (*c2fb_temp_2) = c2fb_temp_3
    c2fb_flow_1:
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    Wend
    c2fb_flow_0:
End Sub

Private Sub substSelect CDecl Alias "substSelect" (ByVal arg0 As SqliteSubstContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SQLITE_C_INT)
    Dim local0 As SqliteSrcList Ptr
    Dim local1 As SqliteSrcItem Ptr
    Dim local2 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_3 As SqliteExpr Ptr
    Dim c2fb_temp_4 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_5 As SqliteExpr Ptr
    Dim c2fb_temp_6 As SqliteSrcList Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SqliteSrcItem Ptr
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SqliteSrcItem Ptr
    Dim c2fb_temp_11 As SqliteSelect Ptr
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT Ptr
    Dim c2fb_temp_14 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, (arg1 = 0))) Then
        Return
    End If
    c2fb_temp_0 = CPtr(SQLITE_C_INT Ptr, @(arg0->nSelDepth))
    c2fb_temp_1 = (*c2fb_temp_0)
    (*c2fb_temp_0) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    Do
        substExprList(arg0, arg1->pEList)
        substExprList(arg0, arg1->pGroupBy)
        substExprList(arg0, arg1->pOrderBy)
        c2fb_temp_2 = CPtr(SqliteExpr Ptr Ptr, @(arg1->pHaving))
        c2fb_temp_3 = CPtr(SqliteExpr Ptr, substExpr(arg0, arg1->pHaving))
        (*c2fb_temp_2) = c2fb_temp_3
        c2fb_temp_4 = CPtr(SqliteExpr Ptr Ptr, @(arg1->pWhere))
        c2fb_temp_5 = CPtr(SqliteExpr Ptr, substExpr(arg0, arg1->pWhere))
        (*c2fb_temp_4) = c2fb_temp_5
        c2fb_temp_6 = arg1->pSrc
        local0 = c2fb_temp_6
        ' C unused-parameter annotation
        c2fb_temp_7 = Cast(SQLITE_C_INT, local0->nSrc)
        local2 = c2fb_temp_7
        c2fb_temp_8 = CPtr(SqliteSrcItem Ptr, (@local0->a(0)))
        local1 = c2fb_temp_8
        While (-Cast(SQLITE_C_INT, ((local2 > Cast(SQLITE_C_INT, &O0ULL)))))
            If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                substSelect(arg0, local1->u4.pSubq->pSelect, Cast(SQLITE_C_INT, 1ULL))
            End If
            If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 3) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                substExprList(arg0, local1->u1.pFuncArg)
            End If
        c2fb_flow_3:
            c2fb_temp_9 = local2
            local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_9 - 1)))
            c2fb_temp_10 = local1
            local1 = (c2fb_temp_10 + 1)
        Wend
        c2fb_flow_2:
    c2fb_flow_1:
        c2fb_temp_12 = 0
        If arg2 Then
            c2fb_temp_11 = arg1->pPrior
            arg1 = c2fb_temp_11
            c2fb_temp_12 = (-Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, (((c2fb_temp_11) <> Cast(SQLITE_C_INT, &O0ULL))))) <> 0)))
        End If
    Loop While c2fb_temp_12
    c2fb_flow_0:
    c2fb_temp_13 = CPtr(SQLITE_C_INT Ptr, @(arg0->nSelDepth))
    c2fb_temp_14 = (*c2fb_temp_13)
    (*c2fb_temp_13) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_14 - 1)))
End Sub

Private Function recomputeColumnsUsedExpr CDecl Alias "recomputeColumnsUsedExpr" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim local0 As SqliteSrcItem Ptr
    Dim c2fb_temp_0 As SqliteSrcItem Ptr
    Dim c2fb_temp_1 As sqlite3_uint64 Ptr
    Dim c2fb_temp_2 As sqlite3_uint64

    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) <> Cast(SQLITE_C_INT, 168ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = CPtr(SqliteSrcItem Ptr, arg0->u.pSrcItem)
    local0 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, ((local0->iCursor <> arg1->iTable)))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->iColumn) < Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_1 = CPtr(sqlite3_uint64 Ptr, @(local0->colUsed))
    c2fb_temp_2 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, ((*c2fb_temp_1) Or sqlite3ExprColUsed(CPtr(Any Ptr, arg1)))))
    (*c2fb_temp_1) = c2fb_temp_2
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Sub recomputeColumnsUsed CDecl Alias "recomputeColumnsUsed" (ByVal arg0 As SqliteSelect Ptr, ByVal arg1 As SqliteSrcItem Ptr)
    Dim local0 As SqliteWalker
    Dim c2fb_temp_0 As Any Ptr
    Dim c2fb_temp_1 As SqliteWalkerExprCallback Ptr
    Dim c2fb_temp_2 As c2fb_callback_85
    Dim c2fb_temp_3 As SqliteWalkerSelectCallback Ptr
    Dim c2fb_temp_4 As c2fb_callback_85
    Dim c2fb_temp_5 As Any Ptr Ptr
    Dim c2fb_temp_6 As SqliteSrcItem Ptr
    Dim c2fb_temp_7 As sqlite3_uint64 Ptr
    Dim c2fb_temp_8 As sqlite3_uint64

    ' C automatic storage declaration
    If ((-Cast(SQLITE_C_INT, ((arg1->pSTab = Cast(SQLITE_C_INT, &O0ULL)))))) Then
        Return
    End If
    c2fb_temp_0 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local0))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteWalker))))
    c2fb_temp_1 = CPtr(SqliteWalkerExprCallback Ptr, @(local0.xExprCallback))
    c2fb_temp_2 = CPtr(c2fb_callback_85, ProcPtr(recomputeColumnsUsedExpr))
    (*c2fb_temp_1) = Cast(SqliteWalkerExprCallback, c2fb_temp_2)
    c2fb_temp_2 = CPtr(c2fb_callback_85, (*c2fb_temp_1))
    c2fb_temp_3 = CPtr(SqliteWalkerSelectCallback Ptr, @(local0.xSelectCallback))
    c2fb_temp_4 = CPtr(c2fb_callback_85, ProcPtr(sqlite3SelectWalkNoop))
    (*c2fb_temp_3) = Cast(SqliteWalkerSelectCallback, c2fb_temp_4)
    c2fb_temp_4 = CPtr(c2fb_callback_85, (*c2fb_temp_3))
    c2fb_temp_5 = CPtr(Any Ptr Ptr, @(local0.u.pSrcItem))
    c2fb_temp_6 = arg1
    (*c2fb_temp_5) = CPtr(Any Ptr, c2fb_temp_6)
    c2fb_temp_6 = CPtr(SqliteSrcItem Ptr, (*c2fb_temp_5))
    c2fb_temp_7 = CPtr(sqlite3_uint64 Ptr, @(arg1->colUsed))
    c2fb_temp_8 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_7) = c2fb_temp_8
    sqlite3WalkSelect(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local0))), CPtr(Any Ptr, arg0))
End Sub

Private Sub srclistRenumberCursors CDecl Alias "srclistRenumberCursors" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT Ptr, ByVal arg2 As SqliteSrcList Ptr, ByVal arg3 As SQLITE_C_INT)
    Dim local0 As SQLITE_C_INT
    Dim local1 As SqliteSrcItem Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SqliteSrcItem Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SqliteSrcItem Ptr
    Dim local2 As SqliteSelect Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT Ptr
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SqliteSelect Ptr
    Dim c2fb_temp_11 As SqliteSelect Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_0
    c2fb_temp_1 = CPtr(SqliteSrcItem Ptr, (@arg2->a(0)))
    local1 = c2fb_temp_1
    While (-Cast(SQLITE_C_INT, ((local0 < arg2->nSrc))))
        If (-Cast(SQLITE_C_INT, ((local0 <> arg3)))) Then
            ' C automatic storage declaration
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 7) And Cast(SQLITE_C_UINT, &H1ULL))) = 0))) OrElse (-Cast(SQLITE_C_INT, ((arg1[Cast(SQLITE_C_INT, (local1->iCursor + Cast(SQLITE_C_INT, 1ULL)))] = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                c2fb_temp_6 = CPtr(SQLITE_C_INT Ptr, @(arg1[Cast(SQLITE_C_INT, (local1->iCursor + Cast(SQLITE_C_INT, 1ULL)))]))
                c2fb_temp_4 = CPtr(SQLITE_C_INT Ptr, @(arg0->nTab))
                c2fb_temp_5 = (*c2fb_temp_4)
                (*c2fb_temp_4) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_5 + 1)))
                c2fb_temp_7 = Cast(SQLITE_C_INT, c2fb_temp_5)
                (*c2fb_temp_6) = c2fb_temp_7
            End If
            c2fb_temp_8 = CPtr(SQLITE_C_INT Ptr, @(local1->iCursor))
            c2fb_temp_9 = Cast(SQLITE_C_INT, arg1[Cast(SQLITE_C_INT, (local1->iCursor + Cast(SQLITE_C_INT, 1ULL)))])
            (*c2fb_temp_8) = c2fb_temp_9
            If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                c2fb_temp_10 = local1->u4.pSubq->pSelect
                local2 = c2fb_temp_10
                While local2
                    srclistRenumberCursors(arg0, arg1, local2->pSrc, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
                c2fb_flow_3:
                    c2fb_temp_11 = local2->pPrior
                    local2 = c2fb_temp_11
                Wend
                c2fb_flow_2:
            End If
        End If
    c2fb_flow_1:
        c2fb_temp_2 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_2 + 1)))
        c2fb_temp_3 = local1
        local1 = (c2fb_temp_3 + 1)
    Wend
    c2fb_flow_0:
End Sub

Private Sub renumberCursorDoMapping CDecl Alias "renumberCursorDoMapping" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SQLITE_C_INT Ptr)
    Dim local0 As SQLITE_C_INT Ptr
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT

    local0 = arg0->u.aiCol
    local1 = (*arg1)
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local1 < local0[Cast(SQLITE_C_INT, &O0ULL)])))) AndAlso (-Cast(SQLITE_C_INT, ((local0[Cast(SQLITE_C_INT, (local1 + Cast(SQLITE_C_INT, 1ULL)))] > Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        c2fb_temp_0 = CPtr(SQLITE_C_INT Ptr, @((*arg1)))
        c2fb_temp_1 = Cast(SQLITE_C_INT, local0[Cast(SQLITE_C_INT, (local1 + Cast(SQLITE_C_INT, 1ULL)))])
        (*c2fb_temp_0) = c2fb_temp_1
    End If
End Sub

Private Function renumberCursorsCb CDecl Alias "renumberCursorsCb" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT

    local0 = arg1->op
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, 168ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, 179ULL))))))))) Then
        renumberCursorDoMapping(arg0, CPtr(SQLITE_C_INT Ptr, @(arg1->iTable)))
    End If
    If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000001ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
        renumberCursorDoMapping(arg0, CPtr(SQLITE_C_INT Ptr, @(arg1->w.iJoin)))
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Sub renumberCursors CDecl Alias "renumberCursors" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT Ptr)
    Dim local0 As SqliteWalker
    Dim c2fb_temp_0 As Any Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT Ptr Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT Ptr
    Dim c2fb_temp_3 As SqliteWalkerExprCallback Ptr
    Dim c2fb_temp_4 As c2fb_callback_85
    Dim c2fb_temp_5 As SqliteWalkerSelectCallback Ptr
    Dim c2fb_temp_6 As c2fb_callback_85

    ' C automatic storage declaration
    srclistRenumberCursors(arg0, arg3, arg1->pSrc, arg2)
    c2fb_temp_0 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local0))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteWalker))))
    c2fb_temp_1 = CPtr(SQLITE_C_INT Ptr Ptr, @(local0.u.aiCol))
    c2fb_temp_2 = arg3
    (*c2fb_temp_1) = c2fb_temp_2
    c2fb_temp_3 = CPtr(SqliteWalkerExprCallback Ptr, @(local0.xExprCallback))
    c2fb_temp_4 = CPtr(c2fb_callback_85, ProcPtr(renumberCursorsCb))
    (*c2fb_temp_3) = Cast(SqliteWalkerExprCallback, c2fb_temp_4)
    c2fb_temp_4 = CPtr(c2fb_callback_85, (*c2fb_temp_3))
    c2fb_temp_5 = CPtr(SqliteWalkerSelectCallback Ptr, @(local0.xSelectCallback))
    c2fb_temp_6 = CPtr(c2fb_callback_85, ProcPtr(sqlite3SelectWalkNoop))
    (*c2fb_temp_5) = Cast(SqliteWalkerSelectCallback, c2fb_temp_6)
    c2fb_temp_6 = CPtr(c2fb_callback_85, (*c2fb_temp_5))
    sqlite3WalkSelect(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local0))), CPtr(Any Ptr, arg1))
End Sub

Private Function findLeftmostExprlist CDecl Alias "findLeftmostExprlist" (ByVal arg0 As SqliteSelect Ptr) As SqliteExprList Ptr
    Dim c2fb_temp_0 As SqliteSelect Ptr

    While arg0->pPrior
        c2fb_temp_0 = arg0->pPrior
        arg0 = c2fb_temp_0
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    Return arg0->pEList
End Function

Private Function compoundHasDifferentAffinities CDecl Alias "compoundHasDifferentAffinities" (ByVal arg0 As SqliteSelect Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SqliteExprList Ptr
    Dim c2fb_temp_0 As SqliteExprList Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim local2 As Byte
    Dim local3 As SqliteSelect Ptr
    Dim c2fb_temp_3 As Byte
    Dim c2fb_temp_4 As SqliteSelect Ptr
    Dim c2fb_temp_5 As SqliteSelect Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = arg0->pEList
    local1 = c2fb_temp_0
    c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_1
    While (-Cast(SQLITE_C_INT, ((local0 < local1->nExpr))))
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C unused-parameter annotation
        c2fb_temp_3 = Cast(Byte, sqlite3ExprAffinity(CPtr(Any Ptr, local1->a(local0).pExpr)))
        local2 = c2fb_temp_3
        c2fb_temp_4 = arg0->pPrior
        local3 = c2fb_temp_4
        While local3
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, sqlite3ExprAffinity(CPtr(Any Ptr, local3->pEList->a(local0).pExpr))) <> Cast(SQLITE_C_INT, local2))))) Then
                Return Cast(SQLITE_C_INT, 1ULL)
            End If
        c2fb_flow_3:
            c2fb_temp_5 = local3->pPrior
            local3 = c2fb_temp_5
        Wend
        c2fb_flow_2:
    c2fb_flow_1:
        c2fb_temp_2 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_2 + 1)))
    Wend
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function flattenSubquery CDecl Alias "flattenSubquery" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As Const ZString Ptr
    Dim local1 As SqliteSelect Ptr
    Dim local2 As SqliteSelect Ptr
    Dim local3 As SqliteSelect Ptr
    Dim local4 As SqliteSrcList Ptr
    Dim local5 As SqliteSrcList Ptr
    Dim local6 As SQLITE_C_INT
    Dim local7 As SQLITE_C_INT
    Dim local8 As SQLITE_C_INT
    Dim local9 As SQLITE_C_INT
    Dim local10 As SqliteExpr Ptr
    Dim local11 As SqliteSrcItem Ptr
    Dim local12 As sqlite3 Ptr
    Dim local13 As SqliteWalker
    Dim local14 As SQLITE_C_INT Ptr
    Dim c2fb_temp_0 As SqliteSrcList Ptr
    Dim c2fb_temp_1 As SqliteSrcItem Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SqliteSelect Ptr
    Dim c2fb_temp_4 As SqliteSrcList Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim local15 As SQLITE_C_INT
    Dim c2fb_temp_6 As SqliteSelect Ptr
    Dim c2fb_temp_7 As SqliteSelect Ptr
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT Ptr
    Dim c2fb_temp_11 As SQLITE_C_INT Ptr
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As Const ZString Ptr Ptr
    Dim c2fb_temp_14 As Const ZString Ptr
    Dim c2fb_temp_15 As Const ZString Ptr Ptr
    Dim c2fb_temp_16 As Const ZString Ptr
    Dim c2fb_temp_17 As SqliteSelect Ptr
    Dim c2fb_temp_18 As SqliteSelect Ptr
    Dim c2fb_temp_19 As ZString Ptr Ptr
    Dim c2fb_temp_20 As ZString Ptr
    Dim c2fb_temp_21 As ZString Ptr Ptr
    Dim c2fb_temp_22 As ZString Ptr
    Dim c2fb_temp_23 As SqliteSelect Ptr
    Dim c2fb_temp_24 As SqliteSelect Ptr
    Dim local16 As SqliteSelect Ptr
    Dim local17 As SqliteExprList Ptr
    Dim local18 As SqliteExpr Ptr
    Dim local19 As SqliteSelect Ptr
    Dim local20 As SqliteTable Ptr
    Dim c2fb_temp_25 As SqliteTable Ptr Ptr
    Dim c2fb_temp_26 As SqliteTable Ptr
    Dim c2fb_temp_27 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_28 As SqliteExprList Ptr
    Dim c2fb_temp_29 As SqliteSelect Ptr Ptr
    Dim c2fb_temp_30 As SqliteSelect Ptr
    Dim c2fb_temp_31 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_32 As SqliteExpr Ptr
    Dim c2fb_temp_33 As SqliteSelect Ptr
    Dim c2fb_temp_34 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_35 As SqliteExpr Ptr
    Dim c2fb_temp_36 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_37 As SqliteExprList Ptr
    Dim c2fb_temp_38 As u8 Ptr
    Dim c2fb_temp_39 As UByte
    Dim c2fb_temp_40 As SqliteTable Ptr Ptr
    Dim c2fb_temp_41 As SqliteTable Ptr
    Dim c2fb_temp_42 As SqliteSelect Ptr Ptr
    Dim c2fb_temp_43 As SqliteSelect Ptr
    Dim c2fb_temp_44 As SQLITE_C_INT Ptr
    Dim c2fb_temp_45 As SQLITE_C_INT
    Dim c2fb_temp_46 As SQLITE_C_INT
    Dim c2fb_temp_47 As u32 Ptr
    Dim c2fb_temp_48 As SQLITE_C_UINT
    Dim c2fb_temp_49 As SqliteSelect Ptr Ptr
    Dim c2fb_temp_50 As SqliteSelect Ptr
    Dim c2fb_temp_51 As SqliteSelect Ptr Ptr
    Dim c2fb_temp_52 As SqliteSelect Ptr
    Dim c2fb_temp_53 As SqliteSelect Ptr Ptr
    Dim c2fb_temp_54 As SqliteSelect Ptr
    Dim c2fb_temp_55 As SqliteSelect Ptr Ptr
    Dim c2fb_temp_56 As SqliteSelect Ptr
    Dim local21 As SqliteTable Ptr
    Dim local22 As SqliteParseContext Ptr
    Dim windowTermPresent As SQLITE_C_INT
    Dim c2fb_temp_57 As Any Ptr
    Dim c2fb_temp_58 As u32 Ptr
    Dim c2fb_temp_59 As SQLITE_C_UINT
    Dim c2fb_temp_60 As SqliteTable Ptr Ptr
    Dim c2fb_temp_61 As SqliteTable Ptr
    Dim c2fb_temp_62 As SqliteSelect Ptr
    Dim c2fb_temp_63 As SqliteSelect Ptr
    Dim c2fb_temp_64 As SqliteSelect Ptr
    Dim c2fb_temp_65 As SqliteSelect Ptr
    Dim local23 As SQLITE_C_INT
    Dim local24 As UByte
    Dim c2fb_temp_66 As SqliteSrcList Ptr
    Dim c2fb_temp_67 As SQLITE_C_INT
    Dim c2fb_temp_68 As SqliteSrcList Ptr
    Dim c2fb_temp_69 As SqliteSrcList Ptr
    Dim c2fb_temp_70 As SqliteSrcList Ptr Ptr
    Dim c2fb_temp_71 As SqliteSrcList Ptr
    Dim c2fb_temp_72 As SqliteSrcItem Ptr
    Dim c2fb_temp_73 As SQLITE_C_INT
    Dim c2fb_temp_74 As SQLITE_C_INT
    Dim c2fb_temp_75 As SQLITE_C_INT
    Dim local25 As SqliteSrcItem Ptr
    Dim c2fb_temp_76 As SqliteSrcItem Ptr
    Dim c2fb_temp_77 As SqliteSrcItem
    Dim c2fb_temp_78 As u8 Ptr
    Dim c2fb_temp_79 As UByte
    Dim c2fb_temp_80 As Any Ptr
    Dim c2fb_temp_81 As u8 Ptr
    Dim c2fb_temp_82 As UByte
    Dim local26 As SqliteExprList Ptr
    Dim c2fb_temp_83 As SQLITE_C_INT
    Dim c2fb_temp_84 As SQLITE_C_INT
    Dim c2fb_temp_85 As UShort Ptr
    Dim c2fb_temp_86 As UShort
    Dim c2fb_temp_87 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_88 As SqliteExprList Ptr
    Dim c2fb_temp_89 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_90 As SqliteExprList Ptr
    Dim c2fb_temp_91 As SqliteExpr Ptr
    Dim c2fb_temp_92 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_93 As SqliteExpr Ptr
    Dim c2fb_temp_94 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_95 As SqliteExpr Ptr
    Dim c2fb_temp_96 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_97 As SqliteExpr Ptr
    Dim local27 As SqliteSubstContext
    Dim c2fb_temp_98 As SqliteParseContext Ptr Ptr
    Dim c2fb_temp_99 As SqliteParseContext Ptr
    Dim c2fb_temp_100 As SQLITE_C_INT Ptr
    Dim c2fb_temp_101 As SQLITE_C_INT
    Dim c2fb_temp_102 As SQLITE_C_INT Ptr
    Dim c2fb_temp_103 As SQLITE_C_INT
    Dim c2fb_temp_104 As SQLITE_C_INT Ptr
    Dim c2fb_temp_105 As SQLITE_C_INT
    Dim c2fb_temp_106 As SQLITE_C_INT Ptr
    Dim c2fb_temp_107 As SQLITE_C_INT
    Dim c2fb_temp_108 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_109 As SqliteExprList Ptr
    Dim c2fb_temp_110 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_111 As SqliteExprList Ptr
    Dim c2fb_temp_112 As u32 Ptr
    Dim c2fb_temp_113 As SQLITE_C_UINT
    Dim c2fb_temp_114 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_115 As SqliteExpr Ptr
    Dim c2fb_temp_116 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_117 As SqliteExpr Ptr
    Dim c2fb_temp_118 As SQLITE_C_INT
    Dim c2fb_temp_119 As SQLITE_C_INT

    local0 = arg0->zAuthContext
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local7 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))
    local8 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local12 = arg0->db
    ' C automatic storage declaration
    local14 = Cast(SQLITE_C_INT, &O0ULL)
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local12)->dbOptFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H00000001ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = arg1->pSrc
    local4 = c2fb_temp_0
    ' C unused-parameter annotation
    c2fb_temp_1 = CPtr(SqliteSrcItem Ptr, @(local4->a(arg2)))
    local11 = c2fb_temp_1
    c2fb_temp_2 = Cast(SQLITE_C_INT, local11->iCursor)
    local6 = c2fb_temp_2
    ' C unused-parameter annotation
    c2fb_temp_3 = local11->u4.pSubq->pSelect
    local2 = c2fb_temp_3
    ' C unused-parameter annotation
#ifndef SQLITE_OMIT_WINDOWFUNC
    If (-Cast(SQLITE_C_INT, (((arg1->pWin <> 0) OrElse (local2->pWin <> 0))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
#endif
    c2fb_temp_4 = local2->pSrc
    local5 = c2fb_temp_4
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((local2->pLimit AndAlso arg1->pLimit)))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((local2->pLimit AndAlso local2->pLimit->pRight)))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000100ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso local2->pLimit)))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((local5->nSrc = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If Cast(SQLITE_C_UINT, (local2->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000001ULL)))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((local2->pLimit AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local4->nSrc > Cast(SQLITE_C_INT, 1ULL))))) OrElse arg3))))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((arg1->pOrderBy AndAlso local2->pOrderBy)))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((arg3 AndAlso local2->pOrderBy)))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((local2->pLimit AndAlso arg1->pWhere)))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((local2->pLimit AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000001ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If Cast(SQLITE_C_UINT, (local2->selFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H0002000ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local11->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H20ULL) Or Cast(SQLITE_C_INT, &H40ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local5->nSrc > Cast(SQLITE_C_INT, 1ULL))))) OrElse (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000001ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) OrElse (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local11->fg.jointype) And Cast(SQLITE_C_INT, &H10ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
        local8 = c2fb_temp_5
    End If
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg2 > Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local5->a(Cast(SQLITE_C_INT, &O0ULL)).fg.jointype) And Cast(SQLITE_C_INT, &H40ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    ' C unused-parameter annotation
    If local2->pPrior Then
        ' C automatic storage declaration
        If local2->pOrderBy Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg3 OrElse (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000001ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) OrElse (-Cast(SQLITE_C_INT, ((local8 > Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        c2fb_temp_6 = local2
        local3 = c2fb_temp_6
        While local3
            ' empty C statement
            ' empty C statement
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            windowTermPresent = 0
#ifndef SQLITE_OMIT_WINDOWFUNC
            If local3->pWin <> 0 Then windowTermPresent = 1
#endif
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local3->selFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0000001ULL) Or Cast(SQLITE_C_INT, &H0000008ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) OrElse ((-Cast(SQLITE_C_INT, ((local3->pPrior AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->op) <> Cast(SQLITE_C_INT, 136ULL)))))))))))))) OrElse (-Cast(SQLITE_C_INT, ((local3->pSrc->nSrc < Cast(SQLITE_C_INT, 1ULL))))))))) OrElse (windowTermPresent <> 0))))) Then
                Return Cast(SQLITE_C_INT, &O0ULL)
            End If
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg2 > Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local3->pSrc->a(Cast(SQLITE_C_INT, &O0ULL)).fg.jointype) And Cast(SQLITE_C_INT, &H40ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                Return Cast(SQLITE_C_INT, &O0ULL)
            End If
            ' empty C statement
        c2fb_flow_1:
            c2fb_temp_7 = local3->pPrior
            local3 = c2fb_temp_7
        Wend
        c2fb_flow_0:
        If arg1->pOrderBy Then
            c2fb_temp_8 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local15 = c2fb_temp_8
            While (-Cast(SQLITE_C_INT, ((local15 < arg1->pOrderBy->nExpr))))
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->pOrderBy->a(local15).u.x.iOrderByCol) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    Return Cast(SQLITE_C_INT, &O0ULL)
                End If
            c2fb_flow_3:
                c2fb_temp_9 = local15
                local15 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_9 + 1)))
            Wend
            c2fb_flow_2:
        End If
        If (Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0002000ULL))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        If compoundHasDifferentAffinities(local2) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        If (-Cast(SQLITE_C_INT, ((local4->nSrc > Cast(SQLITE_C_INT, 1ULL))))) Then
            If (-Cast(SQLITE_C_INT, ((arg0->nSelect > Cast(SQLITE_C_INT, 500ULL))))) Then
                Return Cast(SQLITE_C_INT, &O0ULL)
            End If
            If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local12)->dbOptFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H00800000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                Return Cast(SQLITE_C_INT, &O0ULL)
            End If
            c2fb_temp_10 = CPtr(SQLITE_C_INT Ptr, CPtr(Any Ptr, sqlite3DbMallocZero(CPtr(Any Ptr, local12), Cast(sqlite3_uint64, (Cast(sqlite3_uint64, (Cast(sqlite3_int64, (Cast(sqlite3_int64, arg0->nTab) + Cast(sqlite3_int64, Cast(SQLITE_C_INT, 1ULL)))))) * Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SQLITE_C_INT))))))))
            local14 = c2fb_temp_10
            If local14 Then
                c2fb_temp_11 = CPtr(SQLITE_C_INT Ptr, @(local14[Cast(SQLITE_C_INT, &O0ULL)]))
                c2fb_temp_12 = Cast(SQLITE_C_INT, arg0->nTab)
                (*c2fb_temp_11) = c2fb_temp_12
            End If
        End If
    End If
    ' empty C statement
    c2fb_temp_13 = CPtr(Const ZString Ptr Ptr, @(arg0->zAuthContext))
    c2fb_temp_14 = CPtr(Const ZString Ptr, local11->zName)
    (*c2fb_temp_13) = c2fb_temp_14
    sqlite3AuthCheck(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 21ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL))
    ' empty C statement
    c2fb_temp_15 = CPtr(Const ZString Ptr Ptr, @(arg0->zAuthContext))
    c2fb_temp_16 = local0
    (*c2fb_temp_15) = c2fb_temp_16
    If (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local11->fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL)))) Then
        c2fb_temp_17 = CPtr(SqliteSelect Ptr, sqlite3SubqueryDetach(CPtr(Any Ptr, local12), CPtr(Any Ptr, local11)))
        local3 = c2fb_temp_17
    Else
        c2fb_temp_18 = CPtr(SqliteSelect Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        local3 = c2fb_temp_18
    End If
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    sqlite3DbFree(CPtr(Any Ptr, local12), CPtr(Any Ptr, local11->zName))
    sqlite3DbFree(CPtr(Any Ptr, local12), CPtr(Any Ptr, local11->zAlias))
    c2fb_temp_19 = CPtr(ZString Ptr Ptr, @(local11->zName))
    c2fb_temp_20 = CPtr(ZString Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_19) = c2fb_temp_20
    c2fb_temp_21 = CPtr(ZString Ptr Ptr, @(local11->zAlias))
    c2fb_temp_22 = CPtr(ZString Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_21) = c2fb_temp_22
    ' C unused-parameter annotation
    c2fb_temp_23 = local2->pPrior
    local2 = c2fb_temp_23
    While local2
        ' C automatic storage declaration
        local17 = arg1->pOrderBy
        local18 = arg1->pLimit
        local19 = arg1->pPrior
        local20 = local11->pSTab
        c2fb_temp_25 = CPtr(SqliteTable Ptr Ptr, @(local11->pSTab))
        c2fb_temp_26 = CPtr(SqliteTable Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_25) = c2fb_temp_26
        c2fb_temp_27 = CPtr(SqliteExprList Ptr Ptr, @(arg1->pOrderBy))
        c2fb_temp_28 = CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_27) = c2fb_temp_28
        c2fb_temp_29 = CPtr(SqliteSelect Ptr Ptr, @(arg1->pPrior))
        c2fb_temp_30 = CPtr(SqliteSelect Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_29) = c2fb_temp_30
        c2fb_temp_31 = CPtr(SqliteExpr Ptr Ptr, @(arg1->pLimit))
        c2fb_temp_32 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_31) = c2fb_temp_32
        c2fb_temp_33 = CPtr(SqliteSelect Ptr, sqlite3SelectDup(CPtr(Any Ptr, local12), CPtr(Any Ptr, arg1), Cast(SQLITE_C_INT, &O0ULL)))
        local16 = c2fb_temp_33
        c2fb_temp_34 = CPtr(SqliteExpr Ptr Ptr, @(arg1->pLimit))
        c2fb_temp_35 = local18
        (*c2fb_temp_34) = c2fb_temp_35
        c2fb_temp_36 = CPtr(SqliteExprList Ptr Ptr, @(arg1->pOrderBy))
        c2fb_temp_37 = local17
        (*c2fb_temp_36) = c2fb_temp_37
        c2fb_temp_38 = CPtr(u8 Ptr, @(arg1->op))
        c2fb_temp_39 = Cast(UByte, Cast(SQLITE_C_INT, 136ULL))
        (*c2fb_temp_38) = Cast(u8, c2fb_temp_39)
        c2fb_temp_39 = Cast(UByte, (*c2fb_temp_38))
        c2fb_temp_40 = CPtr(SqliteTable Ptr Ptr, @(local11->pSTab))
        c2fb_temp_41 = local20
        (*c2fb_temp_40) = c2fb_temp_41
        If (-Cast(SQLITE_C_INT, ((local16 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_42 = CPtr(SqliteSelect Ptr Ptr, @(arg1->pPrior))
            c2fb_temp_43 = local19
            (*c2fb_temp_42) = c2fb_temp_43
        Else
            c2fb_temp_47 = CPtr(u32 Ptr, @(local16->selId))
            c2fb_temp_44 = CPtr(SQLITE_C_INT Ptr, @(arg0->nSelect))
            c2fb_temp_45 = (*c2fb_temp_44)
            (*c2fb_temp_44) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_45 + 1)))
            c2fb_temp_46 = (*c2fb_temp_44)
            c2fb_temp_48 = Cast(SQLITE_C_UINT, c2fb_temp_46)
            (*c2fb_temp_47) = Cast(u32, c2fb_temp_48)
            c2fb_temp_48 = Cast(SQLITE_C_UINT, (*c2fb_temp_47))
            If (-Cast(SQLITE_C_INT, ((local14 AndAlso ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local12->mallocFailed) = Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
                renumberCursors(arg0, local16, arg2, local14)
            End If
            c2fb_temp_49 = CPtr(SqliteSelect Ptr Ptr, @(local16->pPrior))
            c2fb_temp_50 = local19
            (*c2fb_temp_49) = c2fb_temp_50
            If local19 Then
                c2fb_temp_51 = CPtr(SqliteSelect Ptr Ptr, @(local19->pNext))
                c2fb_temp_52 = local16
                (*c2fb_temp_51) = c2fb_temp_52
            End If
            c2fb_temp_53 = CPtr(SqliteSelect Ptr Ptr, @(local16->pNext))
            c2fb_temp_54 = arg1
            (*c2fb_temp_53) = c2fb_temp_54
            c2fb_temp_55 = CPtr(SqliteSelect Ptr Ptr, @(arg1->pPrior))
            c2fb_temp_56 = local16
            (*c2fb_temp_55) = c2fb_temp_56
            ' empty C statement
        End If
        ' C unused-parameter annotation
    c2fb_flow_5:
        c2fb_temp_24 = local2->pPrior
        local2 = c2fb_temp_24
    Wend
    c2fb_flow_4:
    sqlite3DbFree(CPtr(Any Ptr, local12), CPtr(Any Ptr, local14))
    If local12->mallocFailed Then
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        sqlite3SrcItemAttachSubquery(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local11), CPtr(Any Ptr, local3), Cast(SQLITE_C_INT, &O0ULL))
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    If ((-Cast(SQLITE_C_INT, ((local11->pSTab <> Cast(SQLITE_C_INT, &O0ULL)))))) Then
        local21 = local11->pSTab
        If (-Cast(SQLITE_C_INT, ((local21->nTabRef = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))) Then
            local22 = (IIf((arg0)->pToplevel, (arg0)->pToplevel, (arg0)))
            c2fb_temp_57 = CPtr(Any Ptr, sqlite3ParserAddCleanup(CPtr(Any Ptr, local22), ProcPtr(sqlite3DeleteTableGeneric), CPtr(Any Ptr, local21)))
            ' empty C statement
        Else
            c2fb_temp_58 = CPtr(u32 Ptr, @(local21->nTabRef))
            c2fb_temp_59 = Cast(SQLITE_C_UINT, (*c2fb_temp_58))
            (*c2fb_temp_58) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_59 - 1)))
        End If
        c2fb_temp_60 = CPtr(SqliteTable Ptr Ptr, @(local11->pSTab))
        c2fb_temp_61 = CPtr(SqliteTable Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_60) = c2fb_temp_61
    End If
    c2fb_temp_62 = local3
    local2 = c2fb_temp_62
    c2fb_temp_63 = arg1
    local1 = c2fb_temp_63
    While local1
        ' C automatic storage declaration
        local24 = local11->fg.jointype
        ' C unused-parameter annotation
        c2fb_temp_66 = local2->pSrc
        local5 = c2fb_temp_66
        c2fb_temp_67 = Cast(SQLITE_C_INT, local5->nSrc)
        local23 = c2fb_temp_67
        c2fb_temp_68 = local1->pSrc
        local4 = c2fb_temp_68
        If (-Cast(SQLITE_C_INT, ((local23 > Cast(SQLITE_C_INT, 1ULL))))) Then
            c2fb_temp_69 = CPtr(SqliteSrcList Ptr, sqlite3SrcListEnlarge(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local4), Cast(SQLITE_C_INT, (local23 - Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, (arg2 + Cast(SQLITE_C_INT, 1ULL)))))
            local4 = c2fb_temp_69
            If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                Goto c2fb_flow_6
            End If
            c2fb_temp_70 = CPtr(SqliteSrcList Ptr Ptr, @(local1->pSrc))
            c2fb_temp_71 = local4
            (*c2fb_temp_70) = c2fb_temp_71
            c2fb_temp_72 = CPtr(SqliteSrcItem Ptr, @(local4->a(arg2)))
            local11 = c2fb_temp_72
        End If
        c2fb_temp_73 = Cast(SQLITE_C_INT, local5->a(Cast(SQLITE_C_INT, &O0ULL)).iCursor)
        local7 = c2fb_temp_73
        c2fb_temp_74 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local9 = c2fb_temp_74
        While (-Cast(SQLITE_C_INT, ((local9 < local23))))
            local25 = CPtr(SqliteSrcItem Ptr, @(local4->a(Cast(SQLITE_C_INT, (local9 + arg2)))))
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local25->fg.flags) Shr 11) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                sqlite3IdListDelete(CPtr(Any Ptr, local12), CPtr(Any Ptr, local25->u3.pUsing))
            End If
            c2fb_temp_76 = CPtr(SqliteSrcItem Ptr, @((*local25)))
            c2fb_temp_77 = local5->a(local9)
            (*c2fb_temp_76) = c2fb_temp_77
            c2fb_temp_78 = CPtr(u8 Ptr, @(local25->fg.jointype))
            c2fb_temp_79 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_78))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local24) And Cast(SQLITE_C_INT, &H40ULL)))))))
            (*c2fb_temp_78) = Cast(u8, c2fb_temp_79)
            c2fb_temp_79 = Cast(UByte, (*c2fb_temp_78))
            c2fb_temp_80 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteSrcItem Ptr, @(local5->a(local9)))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteSrcItem))))
        c2fb_flow_9:
            c2fb_temp_75 = local9
            local9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_75 + 1)))
        Wend
        c2fb_flow_8:
        c2fb_temp_81 = CPtr(u8 Ptr, @(local11->fg.jointype))
        c2fb_temp_82 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_81))) Or Cast(SQLITE_C_INT, local24))))
        (*c2fb_temp_81) = Cast(u8, c2fb_temp_82)
        c2fb_temp_82 = Cast(UByte, (*c2fb_temp_81))
        If local2->pOrderBy Then
            local26 = local2->pOrderBy
            c2fb_temp_83 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local9 = c2fb_temp_83
            While (-Cast(SQLITE_C_INT, ((local9 < local26->nExpr))))
                c2fb_temp_85 = CPtr(UShort Ptr, @(local26->a(local9).u.x.iOrderByCol))
                c2fb_temp_86 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_85) = c2fb_temp_86
            c2fb_flow_11:
                c2fb_temp_84 = local9
                local9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_84 + 1)))
            Wend
            c2fb_flow_10:
            ' C unused-parameter annotation
            c2fb_temp_87 = CPtr(SqliteExprList Ptr Ptr, @(local1->pOrderBy))
            c2fb_temp_88 = local26
            (*c2fb_temp_87) = c2fb_temp_88
            c2fb_temp_89 = CPtr(SqliteExprList Ptr Ptr, @(local2->pOrderBy))
            c2fb_temp_90 = CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            (*c2fb_temp_89) = c2fb_temp_90
        End If
        c2fb_temp_91 = local2->pWhere
        local10 = c2fb_temp_91
        c2fb_temp_92 = CPtr(SqliteExpr Ptr Ptr, @(local2->pWhere))
        c2fb_temp_93 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_92) = c2fb_temp_93
        If (-Cast(SQLITE_C_INT, ((local8 > Cast(SQLITE_C_INT, &O0ULL))))) Then
            ' C unused-parameter annotation
            sqlite3SetJoinExpr(CPtr(Any Ptr, local10), local7, Cast(SQLITE_C_INT, &H000001ULL))
        End If
        If local10 Then
            If local1->pWhere Then
                c2fb_temp_94 = CPtr(SqliteExpr Ptr Ptr, @(local1->pWhere))
                c2fb_temp_95 = CPtr(SqliteExpr Ptr, sqlite3PExpr(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 44ULL), CPtr(Any Ptr, local10), CPtr(Any Ptr, local1->pWhere)))
                (*c2fb_temp_94) = c2fb_temp_95
            Else
                c2fb_temp_96 = CPtr(SqliteExpr Ptr Ptr, @(local1->pWhere))
                c2fb_temp_97 = local10
                (*c2fb_temp_96) = c2fb_temp_97
            End If
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local12->mallocFailed) = Cast(SQLITE_C_INT, &O0ULL))))) Then
            ' C automatic storage declaration
            c2fb_temp_98 = CPtr(SqliteParseContext Ptr Ptr, @(local27.pParse))
            c2fb_temp_99 = arg0
            (*c2fb_temp_98) = c2fb_temp_99
            c2fb_temp_100 = CPtr(SQLITE_C_INT Ptr, @(local27.iTable))
            c2fb_temp_101 = Cast(SQLITE_C_INT, local6)
            (*c2fb_temp_100) = c2fb_temp_101
            c2fb_temp_102 = CPtr(SQLITE_C_INT Ptr, @(local27.iNewTable))
            c2fb_temp_103 = Cast(SQLITE_C_INT, local7)
            (*c2fb_temp_102) = c2fb_temp_103
            c2fb_temp_104 = CPtr(SQLITE_C_INT Ptr, @(local27.isOuterJoin))
            c2fb_temp_105 = Cast(SQLITE_C_INT, local8)
            (*c2fb_temp_104) = c2fb_temp_105
            c2fb_temp_106 = CPtr(SQLITE_C_INT Ptr, @(local27.nSelDepth))
            c2fb_temp_107 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_106) = c2fb_temp_107
            c2fb_temp_108 = CPtr(SqliteExprList Ptr Ptr, @(local27.pEList))
            c2fb_temp_109 = local2->pEList
            (*c2fb_temp_108) = c2fb_temp_109
            c2fb_temp_110 = CPtr(SqliteExprList Ptr Ptr, @(local27.pCList))
            c2fb_temp_111 = CPtr(SqliteExprList Ptr, findLeftmostExprlist(local2))
            (*c2fb_temp_110) = c2fb_temp_111
            substSelect(CPtr(SqliteSubstContext Ptr, @(local27)), local1, Cast(SQLITE_C_INT, &O0ULL))
        End If
        c2fb_temp_112 = CPtr(u32 Ptr, @(local1->selFlags))
        c2fb_temp_113 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_112)) Or Cast(SQLITE_C_UINT, (local2->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000100ULL)))))))
        (*c2fb_temp_112) = Cast(u32, c2fb_temp_113)
        c2fb_temp_113 = Cast(SQLITE_C_UINT, (*c2fb_temp_112))
        ' C unused-parameter annotation
        If local2->pLimit Then
            c2fb_temp_114 = CPtr(SqliteExpr Ptr Ptr, @(local1->pLimit))
            c2fb_temp_115 = local2->pLimit
            (*c2fb_temp_114) = c2fb_temp_115
            c2fb_temp_116 = CPtr(SqliteExpr Ptr Ptr, @(local2->pLimit))
            c2fb_temp_117 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            (*c2fb_temp_116) = c2fb_temp_117
        End If
        c2fb_temp_118 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local9 = c2fb_temp_118
        While (-Cast(SQLITE_C_INT, ((local9 < local23))))
            recomputeColumnsUsed(local1, CPtr(SqliteSrcItem Ptr, @(local4->a(Cast(SQLITE_C_INT, (local9 + arg2))))))
        c2fb_flow_13:
            c2fb_temp_119 = local9
            local9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_119 + 1)))
        Wend
        c2fb_flow_12:
    c2fb_flow_7:
        c2fb_temp_64 = local1->pPrior
        local1 = c2fb_temp_64
        c2fb_temp_65 = local2->pPrior
        local2 = c2fb_temp_65
    Wend
    c2fb_flow_6:
    sqlite3AggInfoPersistWalkerInit(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local13))), CPtr(Any Ptr, arg0))
    sqlite3WalkSelect(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local13))), CPtr(Any Ptr, local3))
    sqlite3SelectDelete(CPtr(Any Ptr, local12), CPtr(Any Ptr, local3))
    Return Cast(SQLITE_C_INT, 1ULL)
End Function

Function sqlite3SelectTryFlatten CDecl Alias "sqlite3SelectTryFlatten" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal sourceIndex As SQLITE_C_INT, _
    ByVal isAggregate As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Return flattenSubquery(pParse, pSelect, sourceIndex, isAggregate)
End Function

#ifndef SQLITE_OMIT_WINDOWFUNC
Private Function pushDownWindowCheck CDecl Alias "pushDownWindowCheck" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteExpr Ptr) As SQLITE_C_INT
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    Return sqlite3ExprIsConstantOrGroupBy(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg2), CPtr(Any Ptr, CPtr(SqliteWalkerWindow Ptr, arg1->pWin)->pPartition))
End Function
#endif

Private Function pushDownWhereTerms CDecl Alias "pushDownWhereTerms" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteExpr Ptr, ByVal arg3 As SqliteSrcList Ptr, ByVal arg4 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SqliteExpr Ptr
    Dim local1 As SqliteSrcItem Ptr
    Dim local2 As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteSrcItem Ptr
    Dim local3 As SqliteSelect Ptr
    Dim local4 As SQLITE_C_INT
    Dim c2fb_temp_1 As SqliteSelect Ptr
    Dim c2fb_temp_2 As SqliteSelect Ptr
    Dim local5 As UByte
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SqliteSelect Ptr
    Dim c2fb_temp_5 As SqliteSelect Ptr
    Dim local6 As SQLITE_C_INT
    Dim local7 As Const SqliteExprList Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim local8 As sqlite3CollSeq Ptr
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SqliteExpr Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As u32 Ptr
    Dim c2fb_temp_12 As SQLITE_C_UINT
    Dim local9 As SqliteSubstContext
    Dim c2fb_temp_13 As SqliteExpr Ptr
    Dim c2fb_temp_14 As SqliteParseContext Ptr Ptr
    Dim c2fb_temp_15 As SqliteParseContext Ptr
    Dim c2fb_temp_16 As SQLITE_C_INT Ptr
    Dim c2fb_temp_17 As SQLITE_C_INT
    Dim c2fb_temp_18 As SQLITE_C_INT Ptr
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim c2fb_temp_20 As SQLITE_C_INT Ptr
    Dim c2fb_temp_21 As SQLITE_C_INT
    Dim c2fb_temp_22 As SQLITE_C_INT Ptr
    Dim c2fb_temp_23 As SQLITE_C_INT
    Dim c2fb_temp_24 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_25 As SqliteExprList Ptr
    Dim c2fb_temp_26 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_27 As SqliteExprList Ptr
    Dim c2fb_temp_28 As SqliteExpr Ptr
    Dim c2fb_temp_29 As u32 Ptr
    Dim c2fb_temp_30 As SQLITE_C_UINT
    Dim c2fb_temp_31 As u32 Ptr
    Dim c2fb_temp_32 As SQLITE_C_UINT
    Dim c2fb_temp_33 As SQLITE_C_INT
    Dim c2fb_temp_34 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_35 As SqliteExpr Ptr
    Dim c2fb_temp_36 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_37 As SqliteExpr Ptr
    Dim c2fb_temp_38 As SqliteSelect Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    local2 = Cast(SQLITE_C_INT, &O0ULL)
    c2fb_temp_0 = CPtr(SqliteSrcItem Ptr, @(arg3->a(arg4)))
    local1 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, ((arg2 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002000ULL) Or Cast(SQLITE_C_INT, &H2000000ULL))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H40ULL) Or Cast(SQLITE_C_INT, &H10ULL)))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If arg1->pPrior Then
        ' C automatic storage declaration
        local4 = Cast(SQLITE_C_INT, &O0ULL)
        c2fb_temp_1 = arg1
        local3 = c2fb_temp_1
        While local3
            local5 = local3->op
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local5) <> Cast(SQLITE_C_INT, 136ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local5) <> Cast(SQLITE_C_INT, 139ULL))))))))) Then
                c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                local4 = c2fb_temp_3
            End If
#ifndef SQLITE_OMIT_WINDOWFUNC
            If local3->pWin <> 0 Then
                Return Cast(SQLITE_C_INT, &O0ULL)
            End If
#endif
        c2fb_flow_1:
            c2fb_temp_2 = local3->pPrior
            local3 = c2fb_temp_2
        Wend
        c2fb_flow_0:
        If local4 Then
            c2fb_temp_4 = arg1
            local3 = c2fb_temp_4
            While local3
                ' C automatic storage declaration
                local7 = local3->pEList
                ' C unused-parameter annotation
                c2fb_temp_6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local6 = c2fb_temp_6
                While (-Cast(SQLITE_C_INT, ((local6 < local7->nExpr))))
                    local8 = CPtr(sqlite3CollSeq Ptr, sqlite3ExprCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local7->a(local6).pExpr)))
                    If (-Cast(SQLITE_C_INT, (sqlite3IsBinary(CPtr(Any Ptr, local8)) = 0))) Then
                        Return Cast(SQLITE_C_INT, &O0ULL)
                    End If
                c2fb_flow_5:
                    c2fb_temp_7 = local6
                    local6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_7 + 1)))
                Wend
                c2fb_flow_4:
            c2fb_flow_3:
                c2fb_temp_5 = local3->pPrior
                local3 = c2fb_temp_5
            Wend
            c2fb_flow_2:
        End If
    Else
#ifndef SQLITE_OMIT_WINDOWFUNC
        If (-Cast(SQLITE_C_INT, ((CPtr(SqliteWalkerWindow Ptr, arg1->pWin) AndAlso (-Cast(SQLITE_C_INT, ((CPtr(SqliteWalkerWindow Ptr, arg1->pWin)->pPartition = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
#endif
    End If
    If (-Cast(SQLITE_C_INT, ((arg1->pLimit <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    While (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg2->op) = Cast(SQLITE_C_INT, 44ULL)))))
        c2fb_temp_8 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local2 + pushDownWhereTerms(arg0, arg1, arg2->pRight, arg3, arg4))))
        local2 = c2fb_temp_8
        c2fb_temp_9 = arg2->pLeft
        arg2 = c2fb_temp_9
    c2fb_flow_7:
    Wend
    c2fb_flow_6:
#ifdef SQLITE_ALLOW_ROWID_IN_VIEW
    If sqlite3ConfigNoVisibleRowidFlagsValue() = 0 AndAlso _
       (arg2->op = TK_ISNULL OrElse arg2->op = TK_NOTNULL) AndAlso _
       arg2->pLeft <> 0 AndAlso arg2->pLeft->op = TK_COLUMN AndAlso _
       arg2->pLeft->iColumn < 0 Then
        Return 0
    End If
#endif
    If sqlite3ExprIsSingleTableConstraint(CPtr(Any Ptr, arg2), CPtr(Any Ptr, arg3), arg4, Cast(SQLITE_C_INT, 1ULL)) Then
        c2fb_temp_10 = local2
        local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_10 + 1)))
        c2fb_temp_11 = CPtr(u32 Ptr, @(arg1->selFlags))
        c2fb_temp_12 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_11)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H1000000ULL)))))
        (*c2fb_temp_11) = Cast(u32, c2fb_temp_12)
        c2fb_temp_12 = Cast(SQLITE_C_UINT, (*c2fb_temp_11))
        While arg1
            ' C automatic storage declaration
            c2fb_temp_13 = CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, arg2), Cast(SQLITE_C_INT, &O0ULL)))
            local0 = c2fb_temp_13
            unsetJoinExpr(local0, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, 1ULL))
            c2fb_temp_14 = CPtr(SqliteParseContext Ptr Ptr, @(local9.pParse))
            c2fb_temp_15 = arg0
            (*c2fb_temp_14) = c2fb_temp_15
            c2fb_temp_16 = CPtr(SQLITE_C_INT Ptr, @(local9.iTable))
            c2fb_temp_17 = Cast(SQLITE_C_INT, local1->iCursor)
            (*c2fb_temp_16) = c2fb_temp_17
            c2fb_temp_18 = CPtr(SQLITE_C_INT Ptr, @(local9.iNewTable))
            c2fb_temp_19 = Cast(SQLITE_C_INT, local1->iCursor)
            (*c2fb_temp_18) = c2fb_temp_19
            c2fb_temp_20 = CPtr(SQLITE_C_INT Ptr, @(local9.isOuterJoin))
            c2fb_temp_21 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_20) = c2fb_temp_21
            c2fb_temp_22 = CPtr(SQLITE_C_INT Ptr, @(local9.nSelDepth))
            c2fb_temp_23 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_22) = c2fb_temp_23
            c2fb_temp_24 = CPtr(SqliteExprList Ptr Ptr, @(local9.pEList))
            c2fb_temp_25 = arg1->pEList
            (*c2fb_temp_24) = c2fb_temp_25
            c2fb_temp_26 = CPtr(SqliteExprList Ptr Ptr, @(local9.pCList))
            c2fb_temp_27 = CPtr(SqliteExprList Ptr, findLeftmostExprlist(arg1))
            (*c2fb_temp_26) = c2fb_temp_27
            c2fb_temp_28 = CPtr(SqliteExpr Ptr, substExpr(CPtr(SqliteSubstContext Ptr, @(local9)), local0))
            local0 = c2fb_temp_28
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg0->nErr = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->op) = Cast(SQLITE_C_INT, 50ULL))))))))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local0)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
                ' C unused-parameter annotation
                c2fb_temp_29 = CPtr(u32 Ptr, @(local0->x.pSelect->selFlags))
                c2fb_temp_30 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_29)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000020ULL)))))
                (*c2fb_temp_29) = Cast(u32, c2fb_temp_30)
                c2fb_temp_30 = Cast(SQLITE_C_UINT, (*c2fb_temp_29))
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                c2fb_temp_31 = CPtr(u32 Ptr, @(arg2->x.pSelect->selFlags))
                c2fb_temp_32 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_31)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000020ULL)))))
                (*c2fb_temp_31) = Cast(u32, c2fb_temp_32)
                c2fb_temp_32 = Cast(SQLITE_C_UINT, (*c2fb_temp_31))
            End If
#ifndef SQLITE_OMIT_WINDOWFUNC
            If (-Cast(SQLITE_C_INT, ((CPtr(SqliteWalkerWindow Ptr, arg1->pWin) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = pushDownWindowCheck(arg0, arg1, local0))))))))) Then
                sqlite3ExprDelete(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, local0))
                c2fb_temp_33 = local2
                local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_33 - 1)))
                Goto c2fb_flow_8
            End If
#endif
            If Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000008ULL)))) Then
                c2fb_temp_34 = CPtr(SqliteExpr Ptr Ptr, @(arg1->pHaving))
                c2fb_temp_35 = CPtr(SqliteExpr Ptr, sqlite3ExprAnd(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pHaving), CPtr(Any Ptr, local0)))
                (*c2fb_temp_34) = c2fb_temp_35
            Else
                c2fb_temp_36 = CPtr(SqliteExpr Ptr Ptr, @(arg1->pWhere))
                c2fb_temp_37 = CPtr(SqliteExpr Ptr, sqlite3ExprAnd(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->pWhere), CPtr(Any Ptr, local0)))
                (*c2fb_temp_36) = c2fb_temp_37
            End If
            c2fb_temp_38 = arg1->pPrior
            arg1 = c2fb_temp_38
        c2fb_flow_9:
        Wend
        c2fb_flow_8:
    End If
    Return local2
End Function

Private Sub resetAccumulator CDecl Alias "resetAccumulator" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteAggInfo Ptr)
    Dim local0 As SqliteVdbe Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SqliteAggInfoFunction Ptr
    Dim local3 As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteAggInfoFunction Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SqliteAggInfoFunction Ptr
    Dim local4 As SqliteExpr Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim local5 As sqlite3VdbeKeyInfoPrefix Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim local6 As SqliteExprList Ptr
    Dim local7 As sqlite3VdbeKeyInfoPrefix Ptr
    Dim local8 As SQLITE_C_INT
    Dim c2fb_temp_8 As SqliteExprList Ptr
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As sqlite3VdbeKeyInfoPrefix Ptr
    Dim c2fb_temp_13 As UShort Ptr
    Dim c2fb_temp_14 As UShort

    local0 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    ' C automatic storage declaration
    ' C automatic storage declaration
    local3 = Cast(SQLITE_C_INT, (arg1->nFunc + arg1->nColumn))
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    If arg0->nErr Then
        Return
    End If
    sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), arg1->iFirstReg, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (arg1->iFirstReg + local3)) - Cast(SQLITE_C_INT, 1ULL))))
    c2fb_temp_0 = arg1->aFunc
    local2 = c2fb_temp_0
    c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local1 = c2fb_temp_1
    While (-Cast(SQLITE_C_INT, ((local1 < arg1->nFunc))))
        If (-Cast(SQLITE_C_INT, ((local2->iDistinct >= Cast(SQLITE_C_INT, &O0ULL))))) Then
            local4 = local2->pFExpr
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local4->x.pList = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local4->x.pList->nExpr <> Cast(SQLITE_C_INT, 1ULL))))))))) Then
                sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"DISTINCT aggregates must have exactly one argument"))
                c2fb_temp_4 = CPtr(SQLITE_C_INT Ptr, @(local2->iDistinct))
                c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
                (*c2fb_temp_4) = c2fb_temp_5
            Else
                local5 = CPtr(sqlite3VdbeKeyInfoPrefix Ptr, sqlite3KeyInfoFromExprList(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local4->x.pList), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)))
                c2fb_temp_6 = CPtr(SQLITE_C_INT Ptr, @(local2->iDistAddr))
                c2fb_temp_7 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp4(local0, Cast(SQLITE_C_INT, 120ULL), local2->iDistinct, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), CPtr(Const ZString Ptr, CPtr(ZString Ptr, local5)), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 9ULL))))))
                (*c2fb_temp_6) = c2fb_temp_7
                sqlite3VdbeExplainString(arg0, Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"USE TEMP B-TREE FOR %s(DISTINCT)"), local2->pFunc->zName)
            End If
        End If
        If (-Cast(SQLITE_C_INT, ((local2->iOBTab >= Cast(SQLITE_C_INT, &O0ULL))))) Then
            ' C automatic storage declaration
            ' C automatic storage declaration
            local8 = Cast(SQLITE_C_INT, &O0ULL)
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_8 = local2->pFExpr->pLeft->x.pList
            local6 = c2fb_temp_8
            If (-Cast(SQLITE_C_INT, (local2->bOBUnique = 0))) Then
                c2fb_temp_9 = local8
                local8 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_9 + 1)))
            End If
            If local2->bOBPayload Then
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                c2fb_temp_10 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local8 + local2->pFExpr->x.pList->nExpr)))
                local8 = c2fb_temp_10
            End If
            If local2->bUseSubtype Then
                c2fb_temp_11 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local8 + local2->pFExpr->x.pList->nExpr)))
                local8 = c2fb_temp_11
            End If
            c2fb_temp_12 = CPtr(sqlite3VdbeKeyInfoPrefix Ptr, sqlite3KeyInfoFromExprList(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local6), Cast(SQLITE_C_INT, &O0ULL), local8))
            local7 = c2fb_temp_12
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (local2->bOBUnique = 0))) AndAlso (-Cast(SQLITE_C_INT, ((arg0->nErr = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                c2fb_temp_13 = CPtr(UShort Ptr, @(local7->nKeyField))
                c2fb_temp_14 = (*c2fb_temp_13)
                (*c2fb_temp_13) = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_14) + 1)))
            End If
            sqlite3VdbeAddOp4(local0, Cast(SQLITE_C_INT, 120ULL), local2->iOBTab, Cast(SQLITE_C_INT, (local6->nExpr + local8)), Cast(SQLITE_C_INT, &O0ULL), CPtr(Const ZString Ptr, CPtr(ZString Ptr, local7)), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 9ULL)))))
            sqlite3VdbeExplainString(arg0, Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"USE TEMP B-TREE FOR %s(ORDER BY)"), local2->pFunc->zName)
        End If
    c2fb_flow_1:
        c2fb_temp_2 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_2 + 1)))
        c2fb_temp_3 = local2
        local2 = (c2fb_temp_3 + 1)
    Wend
    c2fb_flow_0:
End Sub

Sub sqlite3SelectAggregateReset CDecl Alias "sqlite3SelectAggregateReset" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pAggregateInfo As SqliteAggInfo Ptr _
) Export
    If pParse = 0 OrElse pAggregateInfo = 0 Then Return
    resetAccumulator(pParse, pAggregateInfo)
End Sub

Private Sub explainSimpleCount CDecl Alias "explainSimpleCount" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteTable Ptr, ByVal arg2 As SqliteIndex Ptr)
    Dim local0 As SQLITE_C_INT

    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->explain) = Cast(SQLITE_C_INT, 2ULL))))) Then
        local0 = ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg2 <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso ((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) OrElse (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, (arg2)->flags) Shr 0) And Cast(SQLITE_C_UINT, &H3ULL))) = Cast(SQLITE_C_INT, 2ULL)))))) = 0)))))))))))))
        sqlite3VdbeExplainStrings3(arg0, Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"SCAN %s%s%s"), CPtr(Const ZString Ptr, arg1->zName), IIf(local0, StrPtr(!" USING COVERING INDEX "), StrPtr(!"")), IIf(local0, CPtr(Const ZString Ptr, arg2->zName), StrPtr(!"")))
    End If
End Sub

Private Function countOfViewOptimization CDecl Alias "countOfViewOptimization" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr) As SQLITE_C_INT
    Dim local0 As SqliteSelect Ptr
    Dim local1 As SqliteSelect Ptr
    Dim local2 As SqliteExpr Ptr
    Dim local3 As SqliteExpr Ptr
    Dim local4 As sqlite3 Ptr
    Dim local5 As SqliteSrcItem Ptr
    Dim c2fb_temp_0 As SqliteExpr Ptr
    Dim c2fb_temp_1 As SqliteSrcItem Ptr
    Dim c2fb_temp_2 As SqliteSelect Ptr
    Dim c2fb_temp_3 As SqliteSelect Ptr
    Dim c2fb_temp_4 As sqlite3 Ptr
    Dim c2fb_temp_5 As SqliteExpr Ptr
    Dim c2fb_temp_6 As SqliteExpr Ptr
    Dim c2fb_temp_7 As SqliteSelect Ptr
    Dim c2fb_temp_8 As SqliteSrcList Ptr Ptr
    Dim c2fb_temp_9 As SqliteSrcList Ptr
    Dim local6 As SqliteExpr Ptr
    Dim c2fb_temp_10 As SqliteSelect Ptr
    Dim c2fb_temp_11 As SqliteSelect Ptr Ptr
    Dim c2fb_temp_12 As SqliteSelect Ptr
    Dim c2fb_temp_13 As SqliteSelect Ptr Ptr
    Dim c2fb_temp_14 As SqliteSelect Ptr
    Dim c2fb_temp_15 As u32 Ptr
    Dim c2fb_temp_16 As SQLITE_C_UINT
    Dim c2fb_temp_17 As u32 Ptr
    Dim c2fb_temp_18 As SQLITE_C_UINT
    Dim c2fb_temp_19 As Short Ptr
    Dim c2fb_temp_20 As Short
    Dim c2fb_temp_21 As Any Ptr
    Dim c2fb_temp_22 As SqliteExpr Ptr
    Dim c2fb_temp_23 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_24 As SqliteExprList Ptr
    Dim c2fb_temp_25 As SqliteExpr Ptr
    Dim c2fb_temp_26 As SqliteExpr Ptr
    Dim c2fb_temp_27 As SqliteExpr Ptr
    Dim c2fb_temp_28 As SqliteExpr Ptr
    Dim c2fb_temp_29 As SqliteSelect Ptr
    Dim c2fb_temp_30 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_31 As SqliteExpr Ptr
    Dim c2fb_temp_32 As u32 Ptr
    Dim c2fb_temp_33 As SQLITE_C_UINT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000008ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((arg1->pEList->nExpr <> Cast(SQLITE_C_INT, 1ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If arg1->pWhere Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If arg1->pHaving Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If arg1->pGroupBy Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If arg1->pOrderBy Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = arg1->pEList->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr
    local2 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->op) <> Cast(SQLITE_C_INT, 169ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    ' C unused-parameter annotation
    If sqlite3_stricmp(CPtr(Const ZString Ptr, CPtr(ZString Ptr, local2->u.zToken)), StrPtr(!"count")) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((local2->x.pList <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((arg1->pSrc->nSrc <> Cast(SQLITE_C_INT, 1ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local2)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H1000000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_1 = CPtr(SqliteSrcItem Ptr, (@arg1->pSrc->a(0)))
    local5 = c2fb_temp_1
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local5->fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H20000000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_2 = local5->u4.pSubq->pSelect
    local0 = c2fb_temp_2
    If (-Cast(SQLITE_C_INT, ((local0->pPrior = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If Cast(SQLITE_C_UINT, (local0->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H4000000ULL)))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    Do
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->op) <> Cast(SQLITE_C_INT, 136ULL))))) AndAlso local0->pPrior)))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        If local0->pWhere Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        If local0->pLimit Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        If Cast(SQLITE_C_UINT, (local0->selFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0000008ULL) Or Cast(SQLITE_C_INT, &H0000001ULL))))))) Then
            ' empty C statement
            ' empty C statement
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        ' C unused-parameter annotation
        c2fb_temp_3 = local0->pPrior
        local0 = c2fb_temp_3
    c2fb_flow_1:
    Loop While local0
    c2fb_flow_0:
    c2fb_temp_4 = arg0->db
    local4 = c2fb_temp_4
    c2fb_temp_5 = local2
    local3 = c2fb_temp_5
    c2fb_temp_6 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    local2 = c2fb_temp_6
    c2fb_temp_7 = CPtr(SqliteSelect Ptr, sqlite3SubqueryDetach(CPtr(Any Ptr, local4), CPtr(Any Ptr, local5)))
    local0 = c2fb_temp_7
    sqlite3SrcListDelete(CPtr(Any Ptr, local4), CPtr(Any Ptr, arg1->pSrc))
    c2fb_temp_8 = CPtr(SqliteSrcList Ptr Ptr, @(arg1->pSrc))
    c2fb_temp_9 = CPtr(SqliteSrcList Ptr, CPtr(Any Ptr, sqlite3DbMallocZero(CPtr(Any Ptr, arg0->db), (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, (SizeOf(SqliteSrcList) - SizeOf(SqliteSrcItem)))) + Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteSrcItem)))))))))
    (*c2fb_temp_8) = c2fb_temp_9
    While local0
        ' C automatic storage declaration
        c2fb_temp_10 = local0->pPrior
        local1 = c2fb_temp_10
        c2fb_temp_11 = CPtr(SqliteSelect Ptr Ptr, @(local0->pPrior))
        c2fb_temp_12 = CPtr(SqliteSelect Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_11) = c2fb_temp_12
        c2fb_temp_13 = CPtr(SqliteSelect Ptr Ptr, @(local0->pNext))
        c2fb_temp_14 = CPtr(SqliteSelect Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_13) = c2fb_temp_14
        c2fb_temp_15 = CPtr(u32 Ptr, @(local0->selFlags))
        c2fb_temp_16 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_15)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000008ULL)))))
        (*c2fb_temp_15) = Cast(u32, c2fb_temp_16)
        c2fb_temp_16 = Cast(SQLITE_C_UINT, (*c2fb_temp_15))
        c2fb_temp_17 = CPtr(u32 Ptr, @(local0->selFlags))
        c2fb_temp_18 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_17)) And Cast(SQLITE_C_UINT, (Not Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000100ULL)))))))
        (*c2fb_temp_17) = Cast(u32, c2fb_temp_18)
        c2fb_temp_18 = Cast(SQLITE_C_UINT, (*c2fb_temp_17))
        c2fb_temp_19 = CPtr(Short Ptr, @(local0->nSelectRow))
        c2fb_temp_20 = Cast(Short, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_19) = c2fb_temp_20
        c2fb_temp_21 = CPtr(Any Ptr, sqlite3ParserAddCleanup(CPtr(Any Ptr, arg0), ProcPtr(sqlite3ExprListDeleteGeneric), CPtr(Any Ptr, local0->pEList)))
        c2fb_temp_22 = IIf(local1, CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local4), CPtr(Any Ptr, local3), Cast(SQLITE_C_INT, &O0ULL))), local3)
        local6 = c2fb_temp_22
        c2fb_temp_23 = CPtr(SqliteExprList Ptr Ptr, @(local0->pEList))
        c2fb_temp_24 = CPtr(SqliteExprList Ptr, sqlite3ExprListAppend(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, local6)))
        (*c2fb_temp_23) = c2fb_temp_24
        c2fb_temp_25 = CPtr(SqliteExpr Ptr, sqlite3PExpr(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 139ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)))
        local6 = c2fb_temp_25
        sqlite3PExprAddSelect(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local6), CPtr(Any Ptr, local0))
        If (-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_26 = local6
            local2 = c2fb_temp_26
        Else
            c2fb_temp_27 = CPtr(SqliteExpr Ptr, sqlite3PExpr(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 107ULL), CPtr(Any Ptr, local6), CPtr(Any Ptr, local2)))
            local2 = c2fb_temp_27
        End If
        If arg0->nErr Then
            sqlite3ExprDelete(CPtr(Any Ptr, local4), CPtr(Any Ptr, local2))
            c2fb_temp_28 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            local2 = c2fb_temp_28
        End If
        c2fb_temp_29 = local1
        local0 = c2fb_temp_29
    c2fb_flow_3:
    Wend
    c2fb_flow_2:
    c2fb_temp_30 = CPtr(SqliteExpr Ptr Ptr, @(arg1->pEList->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr))
    c2fb_temp_31 = local2
    (*c2fb_temp_30) = c2fb_temp_31
    c2fb_temp_32 = CPtr(u32 Ptr, @(arg1->selFlags))
    c2fb_temp_33 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_32)) And Cast(SQLITE_C_UINT, (Not Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000008ULL)))))))
    (*c2fb_temp_32) = Cast(u32, c2fb_temp_33)
    c2fb_temp_33 = Cast(SQLITE_C_UINT, (*c2fb_temp_32))
    Return Cast(SQLITE_C_INT, 1ULL)
End Function


/' end of sqlite3_bulk_select_core_paths.bas '/
