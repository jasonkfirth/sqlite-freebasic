/'
** 2001 September 15
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
** the WHERE clause of SQL statements.  This module is responsible for
** generating the code that loops through a table looking for applicable
** rows.  Indices are selected and used to speed the search when doing
** so is applicable.  Because this module is responsible for selecting
** indices, you might also think of this module as the "query optimizer".
'/

/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_bulk39_where.bas

    Purpose:

        Preserve compile-clean C2FB procedures from src/where.c.

    Responsibilities:

        - Implement upstream bodies accepted by the full-tree compiler check.
        - Keep file-local helper bodies in the same module as their callers.
        - Retain generated control flow for later semantic repair.

    This file intentionally does NOT contain:

        - Upstream tests or test-support code.
        - Functions marked out of scope in PORTING_FUNCTIONS.csv.
        - Bodies rejected by C2FB or the grouped compiler check.
        - A claim that compilation establishes SQLite behavior parity.
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
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_parser_types.bi"
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

Declare Sub createMask CDecl Alias "createMask" (ByVal arg0 As SqliteWhereMaskSet Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Function whereRightSubexprIsColumn CDecl Alias "whereRightSubexprIsColumn" (ByVal arg0 As SqliteExpr Ptr) As SqliteExpr Ptr
Declare Function findIndexCol CDecl Alias "findIndexCol" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExprList Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SqliteIndex Ptr, ByVal arg4 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function indexColumnNotNull CDecl Alias "indexColumnNotNull" (ByVal arg0 As SqliteIndex Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function estLog CDecl Alias "estLog" (ByVal arg0 As Short) As Short
Declare Sub translateColumnToCopy CDecl Alias "translateColumnToCopy" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT)
Declare Function constraintCompatibleWithOuterJoin CDecl Alias "constraintCompatibleWithOuterJoin" (ByVal arg0 As Const SqliteWhereTerm Ptr, ByVal arg1 As Const SqliteSrcItem Ptr) As SQLITE_C_INT
Declare Function termFromWhereClause CDecl Alias "termFromWhereClause" (ByVal arg0 As SqliteWhereClause Ptr, ByVal arg1 As SQLITE_C_INT) As SqliteWhereTerm Ptr
Declare Sub freeIdxStr CDecl Alias "freeIdxStr" (ByVal arg0 As SqliteIndexInfo Ptr)
Declare Sub freeIndexInfo CDecl Alias "freeIndexInfo" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteIndexInfo Ptr)
Declare Function vtabBestIndex CDecl Alias "vtabBestIndex" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteTable Ptr, ByVal arg2 As SqliteIndexInfo Ptr) As SQLITE_C_INT
Declare Function whereRangeAdjust CDecl Alias "whereRangeAdjust" (ByVal arg0 As SqliteWhereTerm Ptr, ByVal arg1 As Short) As Short
Declare Function whereRangeScanEst CDecl Alias "whereRangeScanEst" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteWhereLoopBuilder Ptr, ByVal arg2 As SqliteWhereTerm Ptr, ByVal arg3 As SqliteWhereTerm Ptr, ByVal arg4 As SqliteWhereLoop Ptr) As SQLITE_C_INT
Declare Sub whereLoopInit CDecl Alias "whereLoopInit" (ByVal arg0 As SqliteWhereLoop Ptr)
Declare Function whereLoopResize CDecl Alias "whereLoopResize" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteWhereLoop Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function whereLoopCheaperProperSubset CDecl Alias "whereLoopCheaperProperSubset" (ByVal arg0 As Const SqliteWhereLoop Ptr, ByVal arg1 As Const SqliteWhereLoop Ptr) As SQLITE_C_INT
Declare Sub whereLoopAdjustCost CDecl Alias "whereLoopAdjustCost" (ByVal arg0 As Const SqliteWhereLoop Ptr, ByVal arg1 As SqliteWhereLoop Ptr)
Declare Function whereLoopFindLesser CDecl Alias "whereLoopFindLesser" (ByVal arg0 As SqliteWhereLoop Ptr Ptr, ByVal arg1 As Const SqliteWhereLoop Ptr) As SqliteWhereLoop Ptr Ptr
Declare Function exprNodePatternLengthEst CDecl Alias "exprNodePatternLengthEst" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function estLikePatternLength CDecl Alias "estLikePatternLength" (ByVal arg0 As SqliteExpr Ptr, ByVal arg1 As UShort) As SQLITE_C_INT
Declare Sub whereLoopOutputAdjust CDecl Alias "whereLoopOutputAdjust" (ByVal arg0 As SqliteWhereClause Ptr, ByVal arg1 As SqliteWhereLoop Ptr, ByVal arg2 As Short)
Declare Function whereRangeVectorLen CDecl Alias "whereRangeVectorLen" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteIndex Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SqliteWhereTerm Ptr) As SQLITE_C_INT
Declare Function exprIsCoveredByIndex CDecl Alias "exprIsCoveredByIndex" (ByVal arg0 As Const SqliteExpr Ptr, ByVal arg1 As Const SqliteIndex Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function isLimitTerm CDecl Alias "isLimitTerm" (ByVal arg0 As SqliteWhereTerm Ptr) As SQLITE_C_INT
Declare Function allConstraintsUsed CDecl Alias "allConstraintsUsed" (ByVal arg0 As SqliteIndexConstraintUsage Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function whereSortingCost CDecl Alias "whereSortingCost" (ByVal arg0 As SqliteWhereInfo Ptr, ByVal arg1 As Short, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT) As Short
Declare Function exprNodeIsDeterministic CDecl Alias "exprNodeIsDeterministic" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function c2fb_crt_memcpy CDecl Alias "memcpy" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_SIZE_T) As Any Ptr
' c2fb skipped __bswap_16: outside the supported subset
' c2fb skipped __bswap_32: outside the supported subset
' c2fb skipped __bswap_64: outside the supported subset
' c2fb skipped __uint16_identity: outside the supported subset
' c2fb skipped __uint32_identity: outside the supported subset
' c2fb skipped __uint64_identity: outside the supported subset
' c2fb skipped sqlite3IsBinary: FreeBASIC body already exists
' c2fb skipped sqlite3WhereOutputRowCount: FreeBASIC body already exists
' c2fb skipped sqlite3WhereIsDistinct: FreeBASIC body already exists
' c2fb skipped sqlite3WhereIsOrdered: FreeBASIC body already exists
' c2fb skipped sqlite3WhereOrderByLimitOptLabel: FreeBASIC body already exists
' c2fb skipped sqlite3WhereMinMaxOptEarlyOut: FreeBASIC body already exists
' c2fb skipped sqlite3WhereContinueLabel: FreeBASIC body already exists
' c2fb skipped sqlite3WhereBreakLabel: FreeBASIC body already exists
' c2fb skipped sqlite3WhereOkOnePass: FreeBASIC body already exists
' c2fb skipped sqlite3WhereUsesDeferredSeek: FreeBASIC body already exists
' c2fb skipped whereOrMove: outside the supported subset
Function whereOrInsert CDecl Alias "whereOrInsert" (ByVal arg0 As SqliteWhereOrSet Ptr, ByVal arg1 As sqlite3_uint64, ByVal arg2 As Short, ByVal arg3 As Short) As SQLITE_C_INT
    Dim local0 As UShort
    Dim local1 As SqliteWhereOrCost Ptr
    Dim c2fb_temp_0 As UShort
    Dim c2fb_temp_1 As SqliteWhereOrCost Ptr
    Dim c2fb_temp_2 As UShort
    Dim c2fb_temp_3 As SqliteWhereOrCost Ptr
    Dim c2fb_temp_4 As u16 Ptr
    Dim c2fb_temp_5 As UShort
    Dim c2fb_temp_6 As SqliteWhereOrCost Ptr
    Dim c2fb_temp_7 As Short Ptr
    Dim c2fb_temp_8 As Short
    Dim c2fb_temp_9 As SqliteWhereOrCost Ptr
    Dim c2fb_temp_10 As UShort
    Dim c2fb_temp_11 As UShort
    Dim c2fb_temp_12 As SqliteWhereOrCost Ptr
    Dim c2fb_temp_13 As sqlite3_uint64 Ptr
    Dim c2fb_temp_14 As sqlite3_uint64
    Dim c2fb_temp_15 As Short Ptr
    Dim c2fb_temp_16 As Short
    Dim c2fb_temp_17 As Short Ptr
    Dim c2fb_temp_18 As Short

    ' C automatic storage declaration
    ' C automatic storage declaration
    c2fb_temp_0 = Cast(UShort, arg0->n)
    local0 = c2fb_temp_0
    c2fb_temp_1 = CPtr(SqliteWhereOrCost Ptr, (@arg0->a(0)))
    local1 = c2fb_temp_1
    While (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0) > Cast(SQLITE_C_INT, &O0ULL)))))
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg2) <= Cast(SQLITE_C_INT, local1->rRun))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (arg1 And local1->prereq))) = arg1)))))))) Then
            Goto c2fb_label_0
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->rRun) <= Cast(SQLITE_C_INT, arg2))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local1->prereq And arg1))) = local1->prereq)))))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
    c2fb_flow_1:
        c2fb_temp_2 = local0
        local0 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_2) - 1)))
        c2fb_temp_3 = local1
        local1 = (c2fb_temp_3 + 1)
    Wend
    c2fb_flow_0:
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->n) < Cast(SQLITE_C_INT, 3ULL))))) Then
        c2fb_temp_4 = @(arg0->n)
        c2fb_temp_5 = Cast(UShort, (*c2fb_temp_4))
        (*c2fb_temp_4) = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_5) + 1)))
        c2fb_temp_6 = CPtr(SqliteWhereOrCost Ptr, @(arg0->a(c2fb_temp_5)))
        local1 = c2fb_temp_6
        c2fb_temp_7 = @(local1->nOut)
        c2fb_temp_8 = Cast(Short, arg3)
        (*c2fb_temp_7) = c2fb_temp_8
    Else
        c2fb_temp_9 = CPtr(SqliteWhereOrCost Ptr, (@arg0->a(0)))
        local1 = c2fb_temp_9
        c2fb_temp_10 = Cast(UShort, Cast(SQLITE_C_INT, 1ULL))
        local0 = c2fb_temp_10
        While (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0) < Cast(SQLITE_C_INT, arg0->n)))))
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->rRun) > Cast(SQLITE_C_INT, arg0->a(local0).rRun))))) Then
                c2fb_temp_12 = CPtr(SqliteWhereOrCost Ptr, (CPtr(SqliteWhereOrCost Ptr, (@arg0->a(0))) + local0))
                local1 = c2fb_temp_12
            End If
        c2fb_flow_3:
            c2fb_temp_11 = local0
            local0 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_11) + 1)))
        Wend
        c2fb_flow_2:
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->rRun) <= Cast(SQLITE_C_INT, arg2))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
    End If
    c2fb_label_0:
    c2fb_temp_13 = @(local1->prereq)
    c2fb_temp_14 = Cast(sqlite3_uint64, arg1)
    (*c2fb_temp_13) = c2fb_temp_14
    c2fb_temp_15 = @(local1->rRun)
    c2fb_temp_16 = Cast(Short, arg2)
    (*c2fb_temp_15) = c2fb_temp_16
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->nOut) > Cast(SQLITE_C_INT, arg3))))) Then
        c2fb_temp_17 = @(local1->nOut)
        c2fb_temp_18 = Cast(Short, arg3)
        (*c2fb_temp_17) = c2fb_temp_18
    End If
    Return Cast(SQLITE_C_INT, 1ULL)
End Function

' c2fb skipped sqlite3WhereGetMask: FreeBASIC body already exists
' c2fb skipped sqlite3WhereMalloc: outside the supported subset
' c2fb skipped sqlite3WhereRealloc: outside the supported subset
Private Sub createMask CDecl Alias "createMask" (ByVal arg0 As SqliteWhereMaskSet Ptr, ByVal arg1 As SQLITE_C_INT)
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT

    ' C unused-parameter annotation
    c2fb_temp_0 = @(arg0->n)
    c2fb_temp_1 = (*c2fb_temp_0)
    (*c2fb_temp_0) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    c2fb_temp_2 = @(arg0->ix(c2fb_temp_1))
    c2fb_temp_3 = Cast(SQLITE_C_INT, arg1)
    (*c2fb_temp_2) = c2fb_temp_3
End Sub

Private Function whereRightSubexprIsColumn CDecl Alias "whereRightSubexprIsColumn" (ByVal arg0 As SqliteExpr Ptr) As SqliteExpr Ptr
    Dim c2fb_temp_0 As SqliteExpr Ptr

    c2fb_temp_0 = CPtr(SqliteExpr Ptr, sqlite3ExprSkipCollateAndLikely(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg0->pRight))))
    arg0 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((arg0 <> Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->op) = Cast(SQLITE_C_INT, 168ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg0)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000020ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))))))) Then
        Return arg0
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

' c2fb skipped indexInAffinityOk: outside the supported subset
' c2fb skipped whereScanNext: outside the supported subset
' c2fb skipped whereScanInitIndexExpr: outside the supported subset
' c2fb skipped whereScanInit: outside the supported subset
' c2fb skipped sqlite3WhereFindTerm: outside the supported subset
Private Function findIndexCol CDecl Alias "findIndexCol" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExprList Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SqliteIndex Ptr, ByVal arg4 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As Const ZString Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local2 As SqliteExpr Ptr
    Dim local3 As sqlite3CollSeq Ptr

    ' C automatic storage declaration
    local1 = CPtr(Const ZString Ptr Ptr, arg3->azColl)[arg4]
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((local0 < arg1->nExpr))))
        local2 = CPtr(SqliteExpr Ptr, sqlite3ExprSkipCollateAndLikely(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg1->a(local0).pExpr))))
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((local2 <> Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->op) = Cast(SQLITE_C_INT, 168ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->op) = Cast(SQLITE_C_INT, 170ULL)))))))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->iColumn) = Cast(SQLITE_C_INT, arg3->aiColumn[arg4]))))))))) AndAlso (-Cast(SQLITE_C_INT, ((local2->iTable = arg2)))))))) Then
            local3 = CPtr(sqlite3CollSeq Ptr, sqlite3ExprNNCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg1->a(local0).pExpr))))
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = sqlite3StrICmp(CPtr(Const ZString Ptr, local3->zName), local1))))) Then
                Return local0
            End If
        End If
    c2fb_flow_1:
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    Wend
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))
End Function

Private Function indexColumnNotNull CDecl Alias "indexColumnNotNull" (ByVal arg0 As SqliteIndex Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, arg0->aiColumn[arg1])
    local0 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, ((local0 >= Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg0->pTable->aCol[local0].flags) Shr 0) And Cast(SQLITE_C_UINT, &HFULL)))
    Else
        If (-Cast(SQLITE_C_INT, ((local0 = (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))))))) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        Else
            ' C unused-parameter annotation
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
    End If
End Function

' c2fb skipped isDistinctRedundant: outside the supported subset
Private Function estLog CDecl Alias "estLog" (ByVal arg0 As Short) As Short
    Return IIf((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0) <= Cast(SQLITE_C_INT, 10ULL))))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, sqlite3LogEst(arg0)) - Cast(SQLITE_C_INT, 33ULL))))
End Function

Private Sub translateColumnToCopy CDecl Alias "translateColumnToCopy" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT)
    Dim local0 As SqliteVdbe Ptr
    Dim local1 As SqliteVdbeOp Ptr
    Dim local2 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SqliteVdbeOp Ptr
    Dim c2fb_temp_2 As u8 Ptr
    Dim c2fb_temp_3 As UByte
    Dim c2fb_temp_4 As SQLITE_C_INT Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT Ptr
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As u16 Ptr
    Dim c2fb_temp_11 As UShort
    Dim c2fb_temp_12 As u8 Ptr
    Dim c2fb_temp_13 As UByte
    Dim c2fb_temp_14 As SQLITE_C_INT Ptr
    Dim c2fb_temp_15 As SQLITE_C_INT

    local0 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    local1 = CPtr(SqliteVdbeOp Ptr, sqlite3VdbeGetOp(local0, arg1))
    local2 = sqlite3VdbeCurrentAddr(local0)
    If arg0->db->mallocFailed Then
        Return
    End If
    While (-Cast(SQLITE_C_INT, ((arg1 < local2))))
        If (-Cast(SQLITE_C_INT, ((local1->p1 <> arg2)))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->opcode) = Cast(SQLITE_C_INT, 96ULL))))) Then
            c2fb_temp_2 = @(local1->opcode)
            c2fb_temp_3 = Cast(UByte, Cast(SQLITE_C_INT, 82ULL))
            (*c2fb_temp_2) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 82ULL)))
            c2fb_temp_3 = Cast(UByte, (*c2fb_temp_2))
            c2fb_temp_4 = @(local1->p1)
            c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local1->p2 + arg3)))
            (*c2fb_temp_4) = c2fb_temp_5
            c2fb_temp_6 = @(local1->p2)
            c2fb_temp_7 = Cast(SQLITE_C_INT, local1->p3)
            (*c2fb_temp_6) = c2fb_temp_7
            c2fb_temp_8 = @(local1->p3)
            c2fb_temp_9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_8) = c2fb_temp_9
            c2fb_temp_10 = @(local1->p5)
            c2fb_temp_11 = Cast(UShort, Cast(SQLITE_C_INT, 2ULL))
            (*c2fb_temp_10) = Cast(u16, Cast(UShort, Cast(SQLITE_C_INT, 2ULL)))
            c2fb_temp_11 = Cast(UShort, (*c2fb_temp_10))
        Else
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->opcode) = Cast(SQLITE_C_INT, 137ULL))))) Then
                c2fb_temp_12 = @(local1->opcode)
                c2fb_temp_13 = Cast(UByte, Cast(SQLITE_C_INT, 128ULL))
                (*c2fb_temp_12) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 128ULL)))
                c2fb_temp_13 = Cast(UByte, (*c2fb_temp_12))
                c2fb_temp_14 = @(local1->p1)
                c2fb_temp_15 = Cast(SQLITE_C_INT, arg4)
                (*c2fb_temp_14) = c2fb_temp_15
            End If
        End If
    c2fb_flow_1:
        c2fb_temp_0 = arg1
        arg1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_0 + 1)))
        c2fb_temp_1 = local1
        local1 = (c2fb_temp_1 + 1)
    Wend
    c2fb_flow_0:
End Sub

Private Function constraintCompatibleWithOuterJoin CDecl Alias "constraintCompatibleWithOuterJoin" (ByVal arg0 As Const SqliteWhereTerm Ptr, ByVal arg1 As Const SqliteSrcItem Ptr) As SQLITE_C_INT
    ' C unused-parameter annotation
    ' empty C statement
    ' empty C statement
    ' empty C statement
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((CPtr(SqliteExpr Ptr, arg0->pExpr))->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000001ULL) Or Cast(SQLITE_C_INT, &H000002ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))) OrElse (-Cast(SQLITE_C_INT, ((CPtr(SqliteExpr Ptr, arg0->pExpr)->w.iJoin <> arg1->iCursor)))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H10ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((CPtr(SqliteExpr Ptr, arg0->pExpr))->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000002ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    Return Cast(SQLITE_C_INT, 1ULL)
End Function

' c2fb skipped columnIsGoodIndexCandidate: FreeBASIC body already exists
' c2fb skipped termCanDriveIndex: outside the supported subset
' c2fb skipped constructAutomaticIndex: outside the supported subset
' c2fb skipped sqlite3ConstructBloomFilter: outside the supported subset
Private Function termFromWhereClause CDecl Alias "termFromWhereClause" (ByVal arg0 As SqliteWhereClause Ptr, ByVal arg1 As SQLITE_C_INT) As SqliteWhereTerm Ptr
    Dim local0 As SqliteWhereClause Ptr
    Dim c2fb_temp_0 As SqliteWhereClause Ptr
    Dim c2fb_temp_1 As SqliteWhereClause Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT

    ' C automatic storage declaration
    c2fb_temp_0 = arg0
    local0 = c2fb_temp_0
    While local0
        If (-Cast(SQLITE_C_INT, ((arg1 < local0->nTerm)))) Then
            Return CPtr(SqliteWhereTerm Ptr, @(CPtr(SqliteWhereTerm Ptr, local0->a)[arg1]))
        End If
        c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg1 - local0->nTerm)))
        arg1 = c2fb_temp_2
    c2fb_flow_1:
        c2fb_temp_1 = CPtr(SqliteWhereClause Ptr, local0->pOuter)
        local0 = c2fb_temp_1
    Wend
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

' c2fb skipped allocateIndexInfo: outside the supported subset
Private Sub freeIdxStr CDecl Alias "freeIdxStr" (ByVal arg0 As SqliteIndexInfo Ptr)
    Dim c2fb_temp_0 As ZString Ptr Ptr
    Dim c2fb_temp_1 As ZString Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT

    If arg0->needToFreeIdxStr Then
        sqlite3_free(CPtr(Any Ptr, arg0->idxStr))
        c2fb_temp_0 = @(arg0->idxStr)
        c2fb_temp_1 = CPtr(ZString Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_0) = c2fb_temp_1
        c2fb_temp_2 = @(arg0->needToFreeIdxStr)
        c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_2) = c2fb_temp_3
    End If
End Sub

Private Sub freeIndexInfo CDecl Alias "freeIndexInfo" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteIndexInfo Ptr)
    Dim local0 As SqliteHiddenIndexInfo Ptr
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteHiddenIndexInfo Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As Any Ptr Ptr
    Dim c2fb_temp_4 As SqliteVdbeMem Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(SqliteHiddenIndexInfo Ptr, CPtr(SqliteIndexInfo Ptr, @(arg1[Cast(SQLITE_C_INT, 1ULL)])))
    local0 = c2fb_temp_0
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local1 = c2fb_temp_1
    While (-Cast(SQLITE_C_INT, ((local1 < arg1->nConstraint))))
        sqlite3ValueFree(CPtr(Any Ptr, local0->aRhs(local1)))
        c2fb_temp_3 = @(local0->aRhs(local1))
        c2fb_temp_4 = CPtr(SqliteVdbeMem Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_3) = CPtr(Any Ptr, CPtr(SqliteVdbeMem Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
        c2fb_temp_4 = CPtr(SqliteVdbeMem Ptr, (*c2fb_temp_3))
    c2fb_flow_1:
        c2fb_temp_2 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_2 + 1)))
    Wend
    c2fb_flow_0:
    freeIdxStr(arg1)
    sqlite3DbFree(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1))
End Sub

Private Function vtabBestIndex CDecl Alias "vtabBestIndex" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteTable Ptr, ByVal arg2 As SqliteIndexInfo Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SqliteVtab Ptr
    Dim c2fb_temp_0 As SqliteVtab Ptr
    Dim c2fb_temp_1 As u32 Ptr
    Dim c2fb_temp_2 As SQLITE_C_UINT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As u32 Ptr
    Dim c2fb_temp_5 As SQLITE_C_UINT
    Dim c2fb_temp_6 As Any Ptr
    Dim c2fb_temp_7 As ZString Ptr Ptr
    Dim c2fb_temp_8 As ZString Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(SqliteVTable Ptr, sqlite3GetVTable(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, arg1)))->pVtab
    local1 = c2fb_temp_0
    ' empty C statement
    c2fb_temp_1 = @(arg0->db->nSchemaLock)
    c2fb_temp_2 = Cast(SQLITE_C_UINT, (*c2fb_temp_1))
    (*c2fb_temp_1) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_2 + 1)))
    c2fb_temp_3 = Cast(SQLITE_C_INT, CPtr(Function CDecl(ByVal arg0 As SqliteVtab Ptr, ByVal arg1 As SqliteIndexInfo Ptr) As SQLITE_C_INT, local1->pModule->xBestIndex)(local1, arg2))
    local0 = c2fb_temp_3
    c2fb_temp_4 = @(arg0->db->nSchemaLock)
    c2fb_temp_5 = Cast(SQLITE_C_UINT, (*c2fb_temp_4))
    (*c2fb_temp_4) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_5 - 1)))
    ' empty C statement
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local0 <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local0 <> Cast(SQLITE_C_INT, 19ULL))))))))) Then
        If (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, 7ULL))))) Then
            c2fb_temp_6 = CPtr(Any Ptr, sqlite3OomFault(CPtr(Any Ptr, arg0->db)))
        Else
            If (-Cast(SQLITE_C_INT, (local1->zErrMsg = 0))) Then
                sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"%s"), CPtr(Const ZString Ptr, sqlite3ErrStr(local0)))
            Else
                sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"%s"), local1->zErrMsg)
            End If
        End If
    End If
    If arg1->u.vtab.p->bAllSchemas Then
        sqlite3VtabUsesAllSchemas(CPtr(Any Ptr, arg0))
    End If
    sqlite3_free(CPtr(Any Ptr, local1->zErrMsg))
    c2fb_temp_7 = @(local1->zErrMsg)
    c2fb_temp_8 = CPtr(ZString Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_7) = c2fb_temp_8
    Return local0
End Function

Private Function whereRangeAdjust CDecl Alias "whereRangeAdjust" (ByVal arg0 As SqliteWhereTerm Ptr, ByVal arg1 As Short) As Short
    Dim local0 As Short
    Dim c2fb_temp_0 As Short
    Dim c2fb_temp_1 As Short

    local0 = arg1
    If arg0 Then
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->truthProb) <= Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_0 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0) + Cast(SQLITE_C_INT, arg0->truthProb))))
            local0 = c2fb_temp_0
        Else
            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->wtFlags) And Cast(SQLITE_C_INT, &H0080ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_1 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0) - Cast(SQLITE_C_INT, 20ULL))))
                local0 = c2fb_temp_1
                ' C unused-parameter annotation
            End If
        End If
    End If
    Return local0
End Function

Private Function whereRangeScanEst CDecl Alias "whereRangeScanEst" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteWhereLoopBuilder Ptr, ByVal arg2 As SqliteWhereTerm Ptr, ByVal arg3 As SqliteWhereTerm Ptr, ByVal arg4 As SqliteWhereLoop Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim local2 As Short
    Dim c2fb_temp_0 As Short
    Dim c2fb_temp_1 As Short
    Dim c2fb_temp_2 As Short
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As Short
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As Short Ptr
    Dim c2fb_temp_7 As Short

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    local1 = arg4->nOut
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(Short, whereRangeAdjust(arg2, local1))
    local2 = c2fb_temp_0
    c2fb_temp_1 = Cast(Short, whereRangeAdjust(arg3, local2))
    local2 = c2fb_temp_1
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg2 AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg2->truthProb) > Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso arg3)))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg3->truthProb) > Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        c2fb_temp_2 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local2) - Cast(SQLITE_C_INT, 20ULL))))
        local2 = c2fb_temp_2
    End If
    c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local1 - Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg2 <> Cast(SQLITE_C_INT, &O0ULL)))))) + ((-Cast(SQLITE_C_INT, ((arg3 <> Cast(SQLITE_C_INT, &O0ULL)))))))))))
    local1 = c2fb_temp_3
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2) < Cast(SQLITE_C_INT, 10ULL))))) Then
        c2fb_temp_4 = Cast(Short, Cast(SQLITE_C_INT, 10ULL))
        local2 = c2fb_temp_4
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2) < local1)))) Then
        c2fb_temp_5 = Cast(SQLITE_C_INT, local2)
        local1 = c2fb_temp_5
    End If
    c2fb_temp_6 = @(arg4->nOut)
    c2fb_temp_7 = Cast(Short, Cast(Short, local1))
    (*c2fb_temp_6) = c2fb_temp_7
    Return local0
End Function

Private Sub whereLoopInit CDecl Alias "whereLoopInit" (ByVal arg0 As SqliteWhereLoop Ptr)
    Dim c2fb_temp_0 As Any Ptr Ptr
    Dim c2fb_temp_1 As SqliteWhereTerm Ptr Ptr
    Dim c2fb_temp_2 As u16 Ptr
    Dim c2fb_temp_3 As UShort
    Dim c2fb_temp_4 As u16 Ptr
    Dim c2fb_temp_5 As UShort
    Dim c2fb_temp_6 As u32 Ptr
    Dim c2fb_temp_7 As SQLITE_C_UINT

    c2fb_temp_0 = @(arg0->aLTerm)
    c2fb_temp_1 = CPtr(SqliteWhereTerm Ptr Ptr, (@arg0->aLTermSpace(0)))
    (*c2fb_temp_0) = CPtr(Any Ptr, CPtr(SqliteWhereTerm Ptr Ptr, (@arg0->aLTermSpace(0))))
    c2fb_temp_1 = CPtr(SqliteWhereTerm Ptr Ptr, (*c2fb_temp_0))
    c2fb_temp_2 = @(arg0->nLTerm)
    c2fb_temp_3 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_2) = Cast(u16, Cast(UShort, Cast(SQLITE_C_INT, &O0ULL)))
    c2fb_temp_3 = Cast(UShort, (*c2fb_temp_2))
    c2fb_temp_4 = @(arg0->nLSlot)
    c2fb_temp_5 = Cast(UShort, (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, (Cast(SQLITE_C_INT, 3ULL) * SizeOf(SqliteWhereTerm Ptr)))) \ Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereTerm Ptr)))))))))
    (*c2fb_temp_4) = Cast(u16, Cast(UShort, (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, (Cast(SQLITE_C_INT, 3ULL) * SizeOf(SqliteWhereTerm Ptr)))) \ Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereTerm Ptr))))))))))
    c2fb_temp_5 = Cast(UShort, (*c2fb_temp_4))
    c2fb_temp_6 = @(arg0->wsFlags)
    c2fb_temp_7 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_6) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))
    c2fb_temp_7 = Cast(SQLITE_C_UINT, (*c2fb_temp_6))
End Sub

' c2fb skipped whereLoopClearUnion: outside the supported subset
' c2fb skipped whereLoopClear: outside the supported subset
Private Function whereLoopResize CDecl Alias "whereLoopResize" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteWhereLoop Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SqliteWhereTerm Ptr Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SqliteWhereTerm Ptr Ptr
    Dim c2fb_temp_2 As Any Ptr
    Dim c2fb_temp_3 As Any Ptr Ptr
    Dim c2fb_temp_4 As SqliteWhereTerm Ptr Ptr
    Dim c2fb_temp_5 As u16 Ptr
    Dim c2fb_temp_6 As UShort

    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->nLSlot) >= arg2)))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (arg2 + Cast(SQLITE_C_INT, 7ULL)))) And Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, 7ULL))))))
    arg2 = c2fb_temp_0
    c2fb_temp_1 = CPtr(SqliteWhereTerm Ptr Ptr, CPtr(Any Ptr, sqlite3DbMallocRawNN(CPtr(Any Ptr, arg0), Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereTerm Ptr))) * Cast(sqlite3_uint64, arg2))))))
    local0 = c2fb_temp_1
    If (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, 7ULL)
    End If
    c2fb_temp_2 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, local0), CPtr(Const Any Ptr, CPtr(SqliteWhereTerm Ptr Ptr, arg1->aLTerm)), Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereTerm Ptr))) * Cast(sqlite3_uint64, arg1->nLSlot)))))
    If (-Cast(SQLITE_C_INT, ((CPtr(SqliteWhereTerm Ptr Ptr, arg1->aLTerm) <> CPtr(SqliteWhereTerm Ptr Ptr, (@arg1->aLTermSpace(0))))))) Then
        sqlite3DbFreeNN(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteWhereTerm Ptr Ptr, arg1->aLTerm)))
    End If
    c2fb_temp_3 = @(arg1->aLTerm)
    c2fb_temp_4 = local0
    (*c2fb_temp_3) = CPtr(Any Ptr, local0)
    c2fb_temp_4 = CPtr(SqliteWhereTerm Ptr Ptr, (*c2fb_temp_3))
    c2fb_temp_5 = @(arg1->nLSlot)
    c2fb_temp_6 = Cast(UShort, arg2)
    (*c2fb_temp_5) = Cast(u16, Cast(UShort, arg2))
    c2fb_temp_6 = Cast(UShort, (*c2fb_temp_5))
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

' c2fb skipped whereLoopXfer: outside the supported subset
' c2fb skipped whereLoopDelete: outside the supported subset
' c2fb skipped whereInfoFree: outside the supported subset
Private Function whereLoopCheaperProperSubset CDecl Alias "whereLoopCheaperProperSubset" (ByVal arg0 As Const SqliteWhereLoop Ptr, ByVal arg1 As Const SqliteWhereLoop Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->rRun) > Cast(SQLITE_C_INT, arg1->rRun))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->nOut) > Cast(SQLITE_C_INT, arg1->nOut))))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->u.btree.nEq) < Cast(SQLITE_C_INT, arg1->u.btree.nEq))))) AndAlso (-Cast(SQLITE_C_INT, ((CPtr(SqliteIndex Ptr, arg0->u.btree.pIndex) = CPtr(SqliteIndex Ptr, arg1->u.btree.pIndex))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->nSkip) = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->nSkip) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->nLTerm) - Cast(SQLITE_C_INT, arg0->nSkip))) >= Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->nLTerm) - Cast(SQLITE_C_INT, arg1->nSkip))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->nSkip) > Cast(SQLITE_C_INT, arg0->nSkip))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->nLTerm) - Cast(SQLITE_C_INT, 1ULL))))
    local0 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((local0 >= Cast(SQLITE_C_INT, &O0ULL)))))
        If (-Cast(SQLITE_C_INT, ((CPtr(SqliteWhereTerm Ptr Ptr, arg0->aLTerm)[local0] = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_1
        End If
        c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->nLTerm) - Cast(SQLITE_C_INT, 1ULL))))
        local1 = c2fb_temp_2
        While (-Cast(SQLITE_C_INT, ((local1 >= Cast(SQLITE_C_INT, &O0ULL)))))
            If (-Cast(SQLITE_C_INT, ((CPtr(SqliteWhereTerm Ptr Ptr, arg1->aLTerm)[local1] = CPtr(SqliteWhereTerm Ptr Ptr, arg0->aLTerm)[local0])))) Then
                Goto c2fb_flow_2
            End If
        c2fb_flow_3:
            c2fb_temp_3 = local1
            local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_3 - 1)))
        Wend
        c2fb_flow_2:
        If (-Cast(SQLITE_C_INT, ((local1 < Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
    c2fb_flow_1:
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 - 1)))
    Wend
    c2fb_flow_0:
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg0->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000040ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000040ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    Return Cast(SQLITE_C_INT, 1ULL)
End Function

Private Sub whereLoopAdjustCost CDecl Alias "whereLoopAdjustCost" (ByVal arg0 As Const SqliteWhereLoop Ptr, ByVal arg1 As SqliteWhereLoop Ptr)
    Dim c2fb_temp_0 As Const SqliteWhereLoop Ptr
    Dim c2fb_temp_1 As Short Ptr
    Dim c2fb_temp_2 As Short
    Dim c2fb_temp_3 As Short Ptr
    Dim c2fb_temp_4 As Short
    Dim c2fb_temp_5 As Short Ptr
    Dim c2fb_temp_6 As Short
    Dim c2fb_temp_7 As Short Ptr
    Dim c2fb_temp_8 As Short

    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000200ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
        Return
    End If
    While arg0
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->iTab) <> Cast(SQLITE_C_INT, arg1->iTab))))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg0->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000200ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            Goto c2fb_flow_1
        End If
        If whereLoopCheaperProperSubset(arg0, CPtr(Const SqliteWhereLoop Ptr, arg1)) Then
            ' empty C statement
            c2fb_temp_1 = @(arg1->rRun)
            c2fb_temp_2 = Cast(Short, (IIf((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (arg0->rRun)) < Cast(SQLITE_C_INT, (arg1->rRun)))))), (arg0->rRun), (arg1->rRun))))
            (*c2fb_temp_1) = c2fb_temp_2
            c2fb_temp_3 = @(arg1->nOut)
            c2fb_temp_4 = Cast(Short, (IIf((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->nOut) - Cast(SQLITE_C_INT, 1ULL)))) < Cast(SQLITE_C_INT, (arg1->nOut)))))), (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->nOut) - Cast(SQLITE_C_INT, 1ULL)))), Cast(SQLITE_C_INT, (arg1->nOut)))))
            (*c2fb_temp_3) = c2fb_temp_4
        Else
            If whereLoopCheaperProperSubset(CPtr(Const SqliteWhereLoop Ptr, arg1), arg0) Then
                ' empty C statement
                c2fb_temp_5 = @(arg1->rRun)
                c2fb_temp_6 = Cast(Short, (IIf((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (arg0->rRun)) > Cast(SQLITE_C_INT, (arg1->rRun)))))), (arg0->rRun), (arg1->rRun))))
                (*c2fb_temp_5) = c2fb_temp_6
                c2fb_temp_7 = @(arg1->nOut)
                c2fb_temp_8 = Cast(Short, (IIf((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->nOut) + Cast(SQLITE_C_INT, 1ULL)))) > Cast(SQLITE_C_INT, (arg1->nOut)))))), (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->nOut) + Cast(SQLITE_C_INT, 1ULL)))), Cast(SQLITE_C_INT, (arg1->nOut)))))
                (*c2fb_temp_7) = c2fb_temp_8
            End If
        End If
    c2fb_flow_1:
        c2fb_temp_0 = CPtr(Const SqliteWhereLoop Ptr, CPtr(SqliteWhereLoop Ptr, arg0->pNextLoop))
        arg0 = c2fb_temp_0
    Wend
    c2fb_flow_0:
End Sub

Private Function whereLoopFindLesser CDecl Alias "whereLoopFindLesser" (ByVal arg0 As SqliteWhereLoop Ptr Ptr, ByVal arg1 As Const SqliteWhereLoop Ptr) As SqliteWhereLoop Ptr Ptr
    Dim local0 As SqliteWhereLoop Ptr
    Dim c2fb_temp_0 As SqliteWhereLoop Ptr
    Dim c2fb_temp_1 As SqliteWhereLoop Ptr Ptr
    Dim c2fb_temp_2 As SqliteWhereLoop Ptr

    ' C automatic storage declaration
    c2fb_temp_0 = ((*arg0))
    local0 = c2fb_temp_0
    While local0
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->iTab) <> Cast(SQLITE_C_INT, arg1->iTab))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->iSortIdx) <> Cast(SQLITE_C_INT, arg1->iSortIdx))))))))) Then
            Goto c2fb_flow_1
        End If
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local0->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00004000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (arg1->nSkip)) = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000200ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000001ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local0->prereq And arg1->prereq))) = arg1->prereq)))))))) Then
            Goto c2fb_flow_0
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local0->prereq And arg1->prereq))) = local0->prereq)))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->rSetup) <= Cast(SQLITE_C_INT, arg1->rSetup))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->rRun) <= Cast(SQLITE_C_INT, arg1->rRun))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->nOut) <= Cast(SQLITE_C_INT, arg1->nOut))))))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local0->prereq And arg1->prereq))) = arg1->prereq)))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->rRun) >= Cast(SQLITE_C_INT, arg1->rRun))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->nOut) >= Cast(SQLITE_C_INT, arg1->nOut))))))))) Then
            ' C unused-parameter annotation
            Goto c2fb_flow_0
        End If
    c2fb_flow_1:
        c2fb_temp_1 = CPtr(SqliteWhereLoop Ptr Ptr, @(local0->pNextLoop))
        arg0 = c2fb_temp_1
        c2fb_temp_2 = (*arg0)
        local0 = c2fb_temp_2
    Wend
    c2fb_flow_0:
    Return arg0
End Function

' c2fb skipped whereLoopInsert: outside the supported subset
Private Function exprNodePatternLengthEst CDecl Alias "exprNodePatternLengthEst" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As UByte Ptr
    Dim local2 As UByte
    Dim local3 As UByte
    Dim local4 As UByte
    Dim local5 As UByte
    Dim c2fb_temp_0 As UByte
    Dim c2fb_temp_1 As UByte
    Dim c2fb_temp_2 As UByte
    Dim c2fb_temp_3 As UByte
    Dim c2fb_temp_4 As UByte
    Dim c2fb_temp_5 As UByte
    Dim c2fb_temp_6 As UByte Ptr
    Dim c2fb_temp_7 As UByte
    Dim c2fb_temp_8 As UByte Ptr
    Dim c2fb_temp_9 As UByte Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT Ptr
    Dim c2fb_temp_12 As SQLITE_C_INT

    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 118ULL))))) Then
        local0 = Cast(SQLITE_C_INT, &O0ULL)
        local1 = CPtr(UByte Ptr, CPtr(ZString Ptr, arg1->u.zToken))
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        If arg0->eCode Then
            c2fb_temp_0 = Cast(UByte, Cast(SQLITE_C_INT, 37))
            local3 = c2fb_temp_0
            c2fb_temp_1 = Cast(UByte, Cast(SQLITE_C_INT, 95))
            local4 = c2fb_temp_1
            c2fb_temp_2 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
            local5 = c2fb_temp_2
        Else
            c2fb_temp_3 = Cast(UByte, Cast(SQLITE_C_INT, 42))
            local3 = c2fb_temp_3
            c2fb_temp_4 = Cast(UByte, Cast(SQLITE_C_INT, 63))
            local4 = c2fb_temp_4
            c2fb_temp_5 = Cast(UByte, Cast(SQLITE_C_INT, 91))
            local5 = c2fb_temp_5
        End If
        Do
            c2fb_temp_6 = local1
            local1 = (c2fb_temp_6 + 1)
            c2fb_temp_7 = Cast(UByte, (*(c2fb_temp_6)))
            local2 = c2fb_temp_7
            If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (c2fb_temp_7)) <> Cast(SQLITE_C_INT, &O0ULL))))) = 0) Then Goto c2fb_flow_0
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2) = Cast(SQLITE_C_INT, local5))))) Then
                If (*local1) Then
                    c2fb_temp_8 = local1
                    local1 = (c2fb_temp_8 + 1)
                End If
                While (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (*local1)) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (*local1)) <> Cast(SQLITE_C_INT, 93)))))))))
                    c2fb_temp_9 = local1
                    local1 = (c2fb_temp_9 + 1)
                c2fb_flow_3:
                Wend
                c2fb_flow_2:
            Else
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2) <> Cast(SQLITE_C_INT, local3))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2) <> Cast(SQLITE_C_INT, local4))))))))) Then
                    c2fb_temp_10 = local0
                    local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_10 + 1)))
                End If
            End If
        c2fb_flow_1:
        Loop
        c2fb_flow_0:
        If (-Cast(SQLITE_C_INT, ((local0 > arg0->u.sz)))) Then
            c2fb_temp_11 = @(arg0->u.sz)
            c2fb_temp_12 = Cast(SQLITE_C_INT, local0)
            (*c2fb_temp_11) = c2fb_temp_12
        End If
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function estLikePatternLength CDecl Alias "estLikePatternLength" (ByVal arg0 As SqliteExpr Ptr, ByVal arg1 As UShort) As SQLITE_C_INT
    Dim local0 As SqliteWalker
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As UShort Ptr
    Dim c2fb_temp_3 As UShort
    Dim c2fb_temp_4 As SqliteWalkerExprCallback Ptr
    Dim c2fb_temp_5 As Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
    Dim c2fb_temp_6 As SqliteWalkerSelectCallback Ptr
    Dim c2fb_temp_7 As Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT

    ' C automatic storage declaration
    c2fb_temp_0 = @(local0.u.sz)
    c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_0) = c2fb_temp_1
    c2fb_temp_2 = @(local0.eCode)
    c2fb_temp_3 = Cast(UShort, arg1)
    (*c2fb_temp_2) = c2fb_temp_3
    c2fb_temp_4 = @(local0.xExprCallback)
    c2fb_temp_5 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, ProcPtr(exprNodePatternLengthEst))
    (*c2fb_temp_4) = Cast(SqliteWalkerExprCallback, CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, ProcPtr(exprNodePatternLengthEst)))
    c2fb_temp_5 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, (*c2fb_temp_4))
    c2fb_temp_6 = @(local0.xSelectCallback)
    c2fb_temp_7 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, ProcPtr(sqlite3SelectWalkFail))
    (*c2fb_temp_6) = Cast(SqliteWalkerSelectCallback, CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, ProcPtr(sqlite3SelectWalkFail)))
    c2fb_temp_7 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, (*c2fb_temp_6))
    sqlite3WalkExpr(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local0))), CPtr(Any Ptr, arg0))
    Return local0.u.sz
End Function

Private Sub whereLoopOutputAdjust CDecl Alias "whereLoopOutputAdjust" (ByVal arg0 As SqliteWhereClause Ptr, ByVal arg1 As SqliteWhereLoop Ptr, ByVal arg2 As Short)
    Dim local0 As SqliteWhereTerm Ptr
    Dim local1 As SqliteWhereTerm Ptr
    Dim local2 As sqlite3_uint64
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As Short
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SqliteWhereTerm Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SqliteWhereTerm Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SqliteWhereTerm Ptr
    Dim c2fb_temp_7 As u32 Ptr
    Dim c2fb_temp_8 As SQLITE_C_UINT
    Dim c2fb_temp_9 As Short Ptr
    Dim c2fb_temp_10 As Short
    Dim local6 As SqliteExpr Ptr
    Dim c2fb_temp_11 As Short Ptr
    Dim c2fb_temp_12 As Short
    Dim local7 As SqliteExpr Ptr
    Dim local8 As SqliteParseContext Ptr
    Dim local9 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As u16 Ptr
    Dim c2fb_temp_16 As UShort
    Dim c2fb_temp_17 As Short
    Dim local10 As SQLITE_C_INT
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim local11 As SQLITE_C_INT
    Dim local12 As SqliteExpr Ptr
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As Short Ptr
    Dim c2fb_temp_22 As Short
    Dim c2fb_temp_23 As Short Ptr
    Dim c2fb_temp_24 As Short

    ' C automatic storage declaration
    ' C automatic storage declaration
    local2 = Cast(sqlite3_uint64, (Not (Cast(sqlite3_uint64, (arg1->prereq Or arg1->maskSelf)))))
    ' C automatic storage declaration
    ' C automatic storage declaration
    local5 = Cast(SQLITE_C_INT, &O0ULL)
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((CPtr(SqliteSrcList Ptr, CPtr(SqliteWhereInfo Ptr, arg0->pWInfo)->pTabList)->nSrc <= Cast(SQLITE_C_INT, 1ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((CPtr(SqliteExprList Ptr, CPtr(SqliteWhereInfo Ptr, arg0->pWInfo)->pOrderBy) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        Return
    End If
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, arg0->nBase)
    local3 = c2fb_temp_0
    c2fb_temp_1 = CPtr(SqliteWhereTerm Ptr, arg0->a)
    local0 = c2fb_temp_1
    While (-Cast(SQLITE_C_INT, ((local3 > Cast(SQLITE_C_INT, &O0ULL)))))
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local0->prereqAll And local2))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local0->prereqAll And arg1->maskSelf))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->wtFlags) And Cast(SQLITE_C_INT, &H0002ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_1
        End If
        c2fb_temp_4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->nLTerm) - Cast(SQLITE_C_INT, 1ULL))))
        local4 = c2fb_temp_4
        While (-Cast(SQLITE_C_INT, ((local4 >= Cast(SQLITE_C_INT, &O0ULL)))))
            c2fb_temp_6 = CPtr(SqliteWhereTerm Ptr Ptr, arg1->aLTerm)[local4]
            local1 = c2fb_temp_6
            If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                Goto c2fb_flow_3
            End If
            If (-Cast(SQLITE_C_INT, ((local1 = local0)))) Then
                Goto c2fb_flow_2
            End If
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local1->iParent >= Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((CPtr(SqliteWhereTerm Ptr, @(CPtr(SqliteWhereTerm Ptr, arg0->a)[local1->iParent]))) = local0)))))))) Then
                Goto c2fb_flow_2
            End If
        c2fb_flow_3:
            c2fb_temp_5 = local4
            local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_5 - 1)))
        Wend
        c2fb_flow_2:
        If (-Cast(SQLITE_C_INT, ((local4 < Cast(SQLITE_C_INT, &O0ULL))))) Then
            sqlite3ProgressCheck(CPtr(Any Ptr, CPtr(SqliteParseContext Ptr, CPtr(SqliteWhereInfo Ptr, arg0->pWInfo)->pParse)))
            If (-Cast(SQLITE_C_INT, ((arg1->maskSelf = local0->prereqAll)))) Then
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->eOperator) And Cast(SQLITE_C_INT, &H3fULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, CPtr(SqliteSrcList Ptr, CPtr(SqliteWhereInfo Ptr, arg0->pWInfo)->pTabList)->a(arg1->iTab).fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H40ULL))))))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                    c2fb_temp_7 = @(arg1->wsFlags)
                    c2fb_temp_8 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_7)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00800000ULL)))))
                    (*c2fb_temp_7) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_7)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00800000ULL))))))
                    c2fb_temp_8 = Cast(SQLITE_C_UINT, (*c2fb_temp_7))
                End If
            End If
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->truthProb) <= Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_9 = @(arg1->nOut)
                c2fb_temp_10 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (*c2fb_temp_9)) + Cast(SQLITE_C_INT, local0->truthProb))))
                (*c2fb_temp_9) = c2fb_temp_10
            Else
                local6 = CPtr(SqliteExpr Ptr, local0->pExpr)
                c2fb_temp_11 = @(arg1->nOut)
                c2fb_temp_12 = (*c2fb_temp_11)
                (*c2fb_temp_11) = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_12) - 1)))
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->eOperator) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0080ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->wtFlags) And Cast(SQLITE_C_INT, &O0ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                    local7 = CPtr(SqliteExpr Ptr, local6->pRight)
                    local8 = CPtr(SqliteParseContext Ptr, CPtr(SqliteWhereInfo Ptr, arg0->pWInfo)->pParse)
                    local9 = Cast(SQLITE_C_INT, &O0ULL)
                    ' empty C statement
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((sqlite3ExprIsInteger(CPtr(Any Ptr, local7), CPtr(SQLITE_C_INT Ptr, @(local9)), CPtr(Any Ptr, local8), Cast(SQLITE_C_INT, 1ULL)) AndAlso (-Cast(SQLITE_C_INT, ((local9 >= (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))))))))))) AndAlso (-Cast(SQLITE_C_INT, ((local9 <= Cast(SQLITE_C_INT, 1ULL))))))))) Then
                        c2fb_temp_13 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 10ULL))
                        local9 = c2fb_temp_13
                    Else
                        c2fb_temp_14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 20ULL))
                        local9 = c2fb_temp_14
                    End If
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local5) < local9)))) Then
                        c2fb_temp_15 = @(local0->wtFlags)
                        c2fb_temp_16 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_15))) Or Cast(SQLITE_C_INT, &H2000ULL))))
                        (*c2fb_temp_15) = Cast(u16, Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_15))) Or Cast(SQLITE_C_INT, &H2000ULL)))))
                        c2fb_temp_16 = Cast(UShort, (*c2fb_temp_15))
                        c2fb_temp_17 = Cast(Short, local9)
                        local5 = c2fb_temp_17
                    End If
                Else
                    If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local6)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000100ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local6->op) = Cast(SQLITE_C_INT, 172ULL))))))))) Then
                        ' C automatic storage declaration
                        ' C unused-parameter annotation
                        ' C unused-parameter annotation
                        c2fb_temp_18 = Cast(SQLITE_C_INT, sqlite3ExprIsLikeOperator(CPtr(Any Ptr, local6)))
                        local10 = c2fb_temp_18
                        If ((-Cast(SQLITE_C_INT, ((local10 > Cast(SQLITE_C_INT, &O0ULL)))))) Then
                            ' C automatic storage declaration
                            local12 = CPtr(SqliteExpr Ptr, CPtr(SqliteExprList Ptr, local6->x.pList)->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr)
                            c2fb_temp_19 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, ((local10 = Cast(SQLITE_C_INT, 65ULL))))))
                            local10 = c2fb_temp_19
                            c2fb_temp_20 = Cast(SQLITE_C_INT, estLikePatternLength(local12, local10))
                            local11 = c2fb_temp_20
                            If (-Cast(SQLITE_C_INT, ((local11 > Cast(SQLITE_C_INT, &O0ULL))))) Then
                                c2fb_temp_21 = @(arg1->nOut)
                                c2fb_temp_22 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (*c2fb_temp_21)) - Cast(SQLITE_C_INT, (local11 * Cast(SQLITE_C_INT, 2ULL))))))
                                (*c2fb_temp_21) = c2fb_temp_22
                            End If
                        End If
                    End If
                End If
            End If
        End If
    c2fb_flow_1:
        c2fb_temp_2 = local3
        local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_2 - 1)))
        c2fb_temp_3 = local0
        local0 = (c2fb_temp_3 + 1)
    Wend
    c2fb_flow_0:
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->nOut) > Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2) - Cast(SQLITE_C_INT, local5))))))) Then
        c2fb_temp_23 = @(arg1->nOut)
        c2fb_temp_24 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2) - Cast(SQLITE_C_INT, local5))))
        (*c2fb_temp_23) = c2fb_temp_24
    End If
End Sub

Private Function whereRangeVectorLen CDecl Alias "whereRangeVectorLen" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteIndex Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SqliteWhereTerm Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim local2 As Byte
    Dim local3 As Byte
    Dim local4 As sqlite3CollSeq Ptr
    Dim local5 As SqliteExpr Ptr
    Dim local6 As SqliteExpr Ptr
    Dim c2fb_temp_3 As SqliteExpr Ptr
    Dim c2fb_temp_4 As SqliteExpr Ptr
    Dim c2fb_temp_5 As SqliteExpr Ptr
    Dim c2fb_temp_6 As SqliteExpr Ptr
    Dim c2fb_temp_7 As Byte
    Dim c2fb_temp_8 As Byte
    Dim local7 As SqliteExpr Ptr
    Dim c2fb_temp_9 As SqliteExpr Ptr
    Dim c2fb_temp_10 As SqliteExpr Ptr
    Dim c2fb_temp_11 As sqlite3CollSeq Ptr

    local0 = sqlite3ExprVectorSize(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, CPtr(SqliteExpr Ptr, arg4->pExpr)->pLeft)))
    ' C automatic storage declaration
    c2fb_temp_0 = Cast(SQLITE_C_INT, (IIf((-Cast(SQLITE_C_INT, (((local0) < ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2->nColumn) - arg3)))))))), (local0), ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2->nColumn) - arg3)))))))
    local0 = c2fb_temp_0
    c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
    local1 = c2fb_temp_1
    While (-Cast(SQLITE_C_INT, ((local1 < local0))))
        ' C automatic storage declaration
        local3 = Cast(SQLITE_C_INT, &O0ULL)
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C unused-parameter annotation
        c2fb_temp_3 = CPtr(SqliteExpr Ptr, CPtr(SqliteExprList Ptr, CPtr(SqliteExpr Ptr, CPtr(SqliteExpr Ptr, arg4->pExpr)->pLeft)->x.pList)->a(local1).pExpr)
        local5 = c2fb_temp_3
        c2fb_temp_4 = CPtr(SqliteExpr Ptr, CPtr(SqliteExpr Ptr, arg4->pExpr)->pRight)
        local6 = c2fb_temp_4
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local6)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            c2fb_temp_5 = CPtr(SqliteExpr Ptr, CPtr(SqliteExprList Ptr, CPtr(SqliteSelect Ptr, local6->x.pSelect)->pEList)->a(local1).pExpr)
            local6 = c2fb_temp_5
        Else
            c2fb_temp_6 = CPtr(SqliteExpr Ptr, CPtr(SqliteExprList Ptr, local6->x.pList)->a(local1).pExpr)
            local6 = c2fb_temp_6
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local5->op) <> Cast(SQLITE_C_INT, 168ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local5->iTable <> arg1)))))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local5->iColumn) <> Cast(SQLITE_C_INT, arg2->aiColumn[Cast(SQLITE_C_INT, (local1 + arg3))]))))))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(UByte Ptr, arg2->aSortOrder)[Cast(SQLITE_C_INT, (local1 + arg3))]) <> Cast(SQLITE_C_INT, CPtr(UByte Ptr, arg2->aSortOrder)[arg3]))))))))) Then
            Goto c2fb_flow_0
        End If
        ' empty C statement
        c2fb_temp_7 = Cast(Byte, sqlite3CompareAffinity(CPtr(Any Ptr, local6), sqlite3ExprAffinity(CPtr(Any Ptr, local5))))
        local2 = c2fb_temp_7
        c2fb_temp_8 = Cast(Byte, sqlite3TableColumnAffinity(CPtr(Any Ptr, arg2->pTable), local5->iColumn))
        local3 = c2fb_temp_8
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2) <> Cast(SQLITE_C_INT, local3))))) Then
            Goto c2fb_flow_0
        End If
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((CPtr(SqliteExpr Ptr, arg4->pExpr))->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000400ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            local7 = local6
            c2fb_temp_9 = local5
            local6 = c2fb_temp_9
            c2fb_temp_10 = local7
            local5 = c2fb_temp_10
        End If
        ' empty C statement
        c2fb_temp_11 = CPtr(sqlite3CollSeq Ptr, sqlite3BinaryCompareCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local5), CPtr(Any Ptr, local6)))
        local4 = c2fb_temp_11
        If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_0
        End If
        If sqlite3StrICmp(CPtr(Const ZString Ptr, local4->zName), CPtr(Const ZString Ptr, CPtr(Const ZString Ptr Ptr, arg2->azColl)[Cast(SQLITE_C_INT, (local1 + arg3))])) Then
            Goto c2fb_flow_0
        End If
    c2fb_flow_1:
        c2fb_temp_2 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_2 + 1)))
    Wend
    c2fb_flow_0:
    Return local1
End Function

' c2fb skipped whereLoopAddBtreeIndex: outside the supported subset
Function indexMightHelpWithOrderBy CDecl Alias "indexMightHelpWithOrderBy" (ByVal arg0 As SqliteWhereLoopBuilder Ptr, ByVal arg1 As SqliteIndex Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SqliteExprList Ptr
    Dim local1 As SqliteExprList Ptr
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteExprList Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim local4 As SqliteExpr Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SqliteExprList Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg1->flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = CPtr(SqliteExprList Ptr, CPtr(SqliteWhereInfo Ptr, arg0->pWInfo)->pOrderBy)
    local0 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, (((c2fb_temp_0) = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local2 = c2fb_temp_1
    While (-Cast(SQLITE_C_INT, ((local2 < local0->nExpr))))
        local4 = CPtr(SqliteExpr Ptr, sqlite3ExprSkipCollateAndLikely(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local0->a(local2).pExpr))))
        If ((-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL)))))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4->op) = Cast(SQLITE_C_INT, 168ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4->op) = Cast(SQLITE_C_INT, 170ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, ((local4->iTable = arg2)))))))) Then
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4->iColumn) < Cast(SQLITE_C_INT, &O0ULL))))) Then
                Return Cast(SQLITE_C_INT, 1ULL)
            End If
            c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local3 = c2fb_temp_3
            While (-Cast(SQLITE_C_INT, ((local3 < Cast(SQLITE_C_INT, arg1->nKeyCol)))))
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4->iColumn) = Cast(SQLITE_C_INT, arg1->aiColumn[local3]))))) Then
                    Return Cast(SQLITE_C_INT, 1ULL)
                End If
            c2fb_flow_3:
                c2fb_temp_4 = local3
                local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_4 + 1)))
            Wend
            c2fb_flow_2:
        Else
            c2fb_temp_5 = CPtr(SqliteExprList Ptr, arg1->aColExpr)
            local1 = c2fb_temp_5
            If (-Cast(SQLITE_C_INT, (((c2fb_temp_5) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local3 = c2fb_temp_6
                While (-Cast(SQLITE_C_INT, ((local3 < Cast(SQLITE_C_INT, arg1->nKeyCol)))))
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->aiColumn[local3]) <> (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 2ULL)))))))) Then
                        Goto c2fb_flow_5
                    End If
                    If (-Cast(SQLITE_C_INT, ((sqlite3ExprCompareSkip(CPtr(Any Ptr, local4), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local1->a(local3).pExpr)), arg2) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        Return Cast(SQLITE_C_INT, 1ULL)
                    End If
                c2fb_flow_5:
                    c2fb_temp_7 = local3
                    local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_7 + 1)))
                Wend
                c2fb_flow_4:
            End If
        End If
    c2fb_flow_1:
        c2fb_temp_2 = local2
        local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_2 + 1)))
    Wend
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Function whereUsablePartialIndex CDecl Alias "whereUsablePartialIndex" (ByVal arg0 As SQLITE_C_INT, ByVal arg1 As UByte, ByVal arg2 As SqliteWhereClause Ptr, ByVal arg3 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SqliteWhereTerm Ptr
    Dim local2 As SqliteParseContext Ptr
    Dim c2fb_temp_0 As SqliteParseContext Ptr
    Dim c2fb_temp_1 As SqliteExpr Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SqliteWhereTerm Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SqliteWhereTerm Ptr
    Dim local3 As SqliteExpr Ptr
    Dim c2fb_temp_6 As SqliteExpr Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1) And Cast(SQLITE_C_INT, &H40ULL))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = CPtr(SqliteParseContext Ptr, CPtr(SqliteWhereInfo Ptr, arg2->pWInfo)->pParse)
    local2 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg3->op) = Cast(SQLITE_C_INT, 44ULL)))))
        If (-Cast(SQLITE_C_INT, (whereUsablePartialIndex(arg0, arg1, arg2, CPtr(SqliteExpr Ptr, arg3->pLeft)) = 0))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        c2fb_temp_1 = CPtr(SqliteExpr Ptr, arg3->pRight)
        arg3 = c2fb_temp_1
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_2
    c2fb_temp_3 = CPtr(SqliteWhereTerm Ptr, arg2->a)
    local1 = c2fb_temp_3
    While (-Cast(SQLITE_C_INT, ((local0 < arg2->nTerm))))
        ' C automatic storage declaration
        c2fb_temp_6 = CPtr(SqliteExpr Ptr, local1->pExpr)
        local3 = c2fb_temp_6
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local3)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000001ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))) OrElse (-Cast(SQLITE_C_INT, ((local3->w.iJoin = arg0))))))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1) And Cast(SQLITE_C_INT, &H20ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) OrElse ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local3)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000001ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))))))))) AndAlso sqlite3ExprImpliesExpr(CPtr(Any Ptr, local2), CPtr(Any Ptr, local3), CPtr(Any Ptr, arg3), arg0))))) AndAlso (-Cast(SQLITE_C_INT, (sqlite3ExprImpliesExpr(CPtr(Any Ptr, local2), CPtr(Any Ptr, local3), CPtr(Any Ptr, arg3), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))) = 0))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->wtFlags) And Cast(SQLITE_C_INT, &H0080ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
    c2fb_flow_3:
        c2fb_temp_4 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_4 + 1)))
        c2fb_temp_5 = local1
        local1 = (c2fb_temp_5 + 1)
    Wend
    c2fb_flow_2:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function exprIsCoveredByIndex CDecl Alias "exprIsCoveredByIndex" (ByVal arg0 As Const SqliteExpr Ptr, ByVal arg1 As Const SqliteIndex Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT

    ' C automatic storage declaration
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((local0 < Cast(SQLITE_C_INT, arg1->nColumn)))))
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->aiColumn[local0]) = (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 2ULL)))))))) AndAlso (-Cast(SQLITE_C_INT, ((sqlite3ExprCompare(Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, CPtr(SqliteExprList Ptr, arg1->aColExpr)->a(local0).pExpr)), arg2) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
    c2fb_flow_1:
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    Wend
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

' c2fb skipped whereIsCoveringIndexWalkCallback: outside the supported subset
' c2fb skipped whereIsCoveringIndex: outside the supported subset
' c2fb skipped whereIndexedExprCleanup: outside the supported subset
' c2fb skipped wherePartIdxExpr: outside the supported subset
' c2fb skipped whereLoopAddBtree: outside the supported subset
Private Function isLimitTerm CDecl Alias "isLimitTerm" (ByVal arg0 As SqliteWhereTerm Ptr) As SQLITE_C_INT
    ' C unused-parameter annotation
    Return (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->eMatchOp) >= Cast(SQLITE_C_INT, 73ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->eMatchOp) <= Cast(SQLITE_C_INT, 74ULL)))))))))
End Function

Private Function allConstraintsUsed CDecl Alias "allConstraintsUsed" (ByVal arg0 As SqliteIndexConstraintUsage Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT

    ' C automatic storage declaration
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((local0 < arg1))))
        If (-Cast(SQLITE_C_INT, ((arg0[local0].argvIndex <= Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
    c2fb_flow_1:
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    Wend
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, 1ULL)
End Function

' c2fb skipped whereLoopAddVirtualOne: outside the supported subset
' c2fb skipped sqlite3_vtab_collation: FreeBASIC body already exists
' c2fb skipped sqlite3_vtab_in: FreeBASIC body already exists
' c2fb skipped sqlite3_vtab_rhs_value: FreeBASIC body already exists
' c2fb skipped sqlite3_vtab_distinct: FreeBASIC body already exists
' c2fb skipped sqlite3VtabUsesAllSchemas: FreeBASIC body already exists
' c2fb skipped whereLoopAddVirtual: outside the supported subset
' c2fb skipped whereLoopAddOr: outside the supported subset
' c2fb skipped whereLoopAddAll: outside the supported subset
' c2fb skipped wherePathMatchSubqueryOB: FreeBASIC body already exists
' c2fb skipped wherePathSatisfiesOrderBy: outside the supported subset
' c2fb skipped sqlite3WhereIsSorted: FreeBASIC body already exists
Private Function whereSortingCost CDecl Alias "whereSortingCost" (ByVal arg0 As SqliteWhereInfo Ptr, ByVal arg1 As Short, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT) As Short
    Dim local0 As Short
    Dim local1 As Short
    Dim c2fb_temp_0 As Short
    Dim c2fb_temp_1 As Short
    Dim c2fb_temp_2 As Short
    Dim c2fb_temp_3 As Short
    Dim c2fb_temp_4 As Short
    Dim c2fb_temp_5 As Short
    Dim c2fb_temp_6 As Short
    Dim c2fb_temp_7 As Short

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(Short, sqlite3LogEst(Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (CPtr(SqliteExprList Ptr, CPtr(SqliteSelect Ptr, arg0->pSelect)->pEList)->nExpr + Cast(SQLITE_C_INT, 59ULL)))) \ Cast(SQLITE_C_INT, 30ULL)))))
    local1 = c2fb_temp_0
    c2fb_temp_1 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1) + Cast(SQLITE_C_INT, local1))))
    local0 = c2fb_temp_1
    If (-Cast(SQLITE_C_INT, ((arg3 > Cast(SQLITE_C_INT, &O0ULL))))) Then
        c2fb_temp_2 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0) + Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, sqlite3LogEst(Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (arg2 - arg3))) * Cast(SQLITE_C_INT, 100ULL))) \ arg2)))) - Cast(SQLITE_C_INT, 66ULL))))))
        local0 = c2fb_temp_2
    End If
    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->wctrlFlags) And Cast(SQLITE_C_INT, &H4000ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        c2fb_temp_3 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0) + Cast(SQLITE_C_INT, 10ULL))))
        local0 = c2fb_temp_3
        If (-Cast(SQLITE_C_INT, ((arg3 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_4 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0) + Cast(SQLITE_C_INT, 6ULL))))
            local0 = c2fb_temp_4
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->iLimit) < Cast(SQLITE_C_INT, arg1))))) Then
            c2fb_temp_5 = Cast(Short, arg0->iLimit)
            arg1 = c2fb_temp_5
        End If
    Else
        If (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->wctrlFlags) And Cast(SQLITE_C_INT, &H0100ULL)))) Then
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1) > Cast(SQLITE_C_INT, 10ULL))))) Then
                c2fb_temp_6 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1) - Cast(SQLITE_C_INT, 10ULL))))
                arg1 = c2fb_temp_6
                ' C unused-parameter annotation
            End If
        End If
    End If
    c2fb_temp_7 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0) + Cast(SQLITE_C_INT, estLog(arg1)))))
    local0 = c2fb_temp_7
    Return local0
End Function

' c2fb skipped computeMxChoice: outside the supported subset
' c2fb skipped whereLoopIsNoBetter: FreeBASIC body already exists
' c2fb skipped wherePathSolver: outside the supported subset
' c2fb skipped whereInterstageHeuristic: FreeBASIC body already exists
' c2fb skipped whereShortCut: outside the supported subset
Private Function exprNodeIsDeterministic CDecl Alias "exprNodeIsDeterministic" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim c2fb_temp_0 As UShort Ptr
    Dim c2fb_temp_1 As UShort

    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 172ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H100000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        c2fb_temp_0 = @(arg0->eCode)
        c2fb_temp_1 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_0) = c2fb_temp_1
        Return Cast(SQLITE_C_INT, 2ULL)
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

' c2fb skipped exprIsDeterministic: outside the supported subset
' c2fb skipped whereOmitNoopJoin: outside the supported subset
' c2fb skipped whereCheckIfBloomFilterIsUseful: FreeBASIC body already exists
' c2fb skipped whereAddIndexedExpr: outside the supported subset
' c2fb skipped whereReverseScanOrder: outside the supported subset
' c2fb skipped sqlite3WhereBegin: outside the supported subset
' c2fb skipped sqlite3WhereEnd: outside the supported subset
/' end of sqlite3_bulk39_where.bas '/
