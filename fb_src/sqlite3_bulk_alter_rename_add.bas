/'
** 2005 February 15
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
*************************************************************************
** This file contains C code routines that used to generate VDBE code
** that implements the ALTER TABLE command.
'/

/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_bulk_alter_rename_add.bas

    Purpose:

        Port ALTER TABLE rename, ADD COLUMN, DROP COLUMN, and constraint paths.

    Responsibilities:

        - Revalidate schemas and update schema metadata after ALTER operations.
        - Check rename, drop, and constraint targets against table definitions.
        - Copy table metadata before parsing an ALTER TABLE ADD COLUMN clause.
        - Rewrite column and table names through the ALTER rename callbacks.
        - Register ALTER built-in SQL functions with the shared function registry.
        - Keep source-local helper procedures beside the callers that use them.

    This file intentionally does NOT contain:

        - ALTER TABLE parser grammar or schema parser implementation.
        - The generic variadic error formatter used elsewhere in SQLite.
        - Runtime verification of the translated behavior.
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

#include once "sqlite3_rowset.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_walker.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_resolve_types.bi"
#include once "sqlite3_vtab_types.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_fkey_types.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_result.bi"
#include once "sqlite3_straccum.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_vdbe_api.bi"
#include once "sqlite3_parser_token.bi"
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
Declare Sub sqlite3AlterBeginAddColumn CDecl Alias "sqlite3AlterBeginAddColumn" (ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr)
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

Type c2fb_callback_3 As Function CDecl(ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const ZString Ptr, ByVal arg4 As Const ZString Ptr, ByVal arg5 As Const ZString Ptr) As SQLITE_C_INT
Type c2fb_callback_6 As Function CDecl(ByVal arg0 As SQLITE_C_UINT, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, ByVal arg3 As Any Ptr) As SQLITE_C_INT
Type c2fb_callback_8 As Sub CDecl(ByVal arg0 As Any Ptr)
Type c2fb_callback_85 As Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
Type c2fb_callback_66 As Function CDecl(ByVal arg0 As SqliteVtab Ptr, ByVal arg1 As Const ZString Ptr) As SQLITE_C_INT

Declare Function isAlterableTable CDecl Alias "isAlterableTable" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteTable Ptr) As SQLITE_C_INT
Declare Sub renameTestSchema CDecl Alias "renameTestSchema" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Const ZString Ptr, ByVal arg4 As SQLITE_C_INT)
Declare Sub renameFixQuotes CDecl Alias "renameFixQuotes" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Sub renameReloadSchema CDecl Alias "renameReloadSchema" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As UShort)
Declare Sub sqlite3AlterRenameTable CDecl Alias "sqlite3AlterRenameTable" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As sqlite3ParserToken Ptr)
Declare Sub sqlite3ErrorIfNotEmpty CDecl Alias "sqlite3ErrorIfNotEmpty" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const ZString Ptr)
Declare Function isRowidAlias CDecl Alias "isRowidAlias" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteTable Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const ZString Ptr) As SQLITE_C_INT
Declare Sub sqlite3AlterFinishAddColumn CDecl Alias "sqlite3AlterFinishAddColumn" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As sqlite3ParserToken Ptr)
Declare Sub sqlite3AlterRenameColumn CDecl Alias "sqlite3AlterRenameColumn" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As sqlite3ParserToken Ptr, ByVal arg3 As sqlite3ParserToken Ptr)
Declare Sub renameTokenFree CDecl Alias "renameTokenFree" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteRenameToken Ptr)
Declare Sub renameColumnElistNames CDecl Alias "renameColumnElistNames" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Const SqliteExprList Ptr, ByVal arg3 As Const ZString Ptr)
Declare Sub renameColumnIdlistNames CDecl Alias "renameColumnIdlistNames" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Const SqliteIdList Ptr, ByVal arg3 As Const ZString Ptr)
Declare Function renameParseSql CDecl Alias "renameParseSql" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As sqlite3 Ptr, ByVal arg3 As Const ZString Ptr, ByVal arg4 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub renameParseCleanup CDecl Alias "renameParseCleanup" (ByVal arg0 As SqliteParseContext Ptr)
Declare Function renameQuotefixExprCb CDecl Alias "renameQuotefixExprCb" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function getConstraintToken CDecl Alias "getConstraintToken" (ByVal arg0 As Const UByte Ptr, ByVal arg1 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Sub dropColumnFunc CDecl Alias "dropColumnFunc" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteVdbeMem Ptr Ptr)
Declare Sub sqlite3AlterDropColumn CDecl Alias "sqlite3AlterDropColumn" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As Const sqlite3ParserToken Ptr)
Declare Function getWhitespace CDecl Alias "getWhitespace" (ByVal arg0 As Const UByte Ptr) As SQLITE_C_INT
Declare Function getConstraint CDecl Alias "getConstraint" (ByVal arg0 As Const UByte Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function quotedCompare CDecl Alias "quotedCompare" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const UByte Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As Const UByte Ptr, ByVal arg5 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function skipCreateTable CDecl Alias "skipCreateTable" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As Const UByte Ptr, ByVal arg2 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Sub dropConstraintFunc CDecl Alias "dropConstraintFunc" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteVdbeMem Ptr Ptr)
Declare Function alterFindCol CDecl Alias "alterFindCol" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteTable Ptr, ByVal arg2 As sqlite3ParserToken Ptr, ByVal arg3 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Sub sqlite3AlterDropConstraint CDecl Alias "sqlite3AlterDropConstraint" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As sqlite3ParserToken Ptr, ByVal arg3 As sqlite3ParserToken Ptr)
Declare Function alterRtrimConstraint CDecl Alias "alterRtrimConstraint" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub sqlite3AlterSetNotNull CDecl Alias "sqlite3AlterSetNotNull" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As sqlite3ParserToken Ptr, ByVal arg3 As sqlite3ParserToken Ptr)
Declare Sub sqlite3AlterAddConstraint CDecl Alias "sqlite3AlterAddConstraint" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As sqlite3ParserToken Ptr, ByVal arg3 As sqlite3ParserToken Ptr, ByVal arg4 As Const ZString Ptr, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As SqliteExpr Ptr)
Declare Function c2fb_crt_memcpy CDecl Alias "memcpy" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_SIZE_T) As Any Ptr
Declare Function c2fb_crt_memmove CDecl Alias "memmove" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_SIZE_T) As Any Ptr
Declare Function c2fb_crt_memset CDecl Alias "memset" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_SIZE_T) As Any Ptr
' c2fb skipped __bswap_16: outside the supported subset
' c2fb skipped __bswap_32: outside the supported subset
' c2fb skipped __bswap_64: outside the supported subset
' c2fb skipped __uint16_identity: outside the supported subset
' c2fb skipped __uint32_identity: outside the supported subset
' c2fb skipped __uint64_identity: outside the supported subset
' c2fb skipped sqlite3IsBinary: FreeBASIC body already exists

Declare Function renameTokenFind CDecl Alias "renameTokenFind" (ByVal pParse As SqliteParseContext Ptr, ByVal pContext As Any Ptr, ByVal pPointer As Const Any Ptr) As SqliteRenameToken Ptr
Declare Sub errorMPrintf CDecl Alias "errorMPrintf" (ByVal pContext As Any Ptr, ByVal zFormat As Const ZString Ptr, ByVal zArgument As Const ZString Ptr)

Declare Function isRealTable CDecl Alias "isRealTable" (ByVal pParse As SqliteParseContext Ptr, ByVal pTable As SqliteTable Ptr, ByVal operation As SQLITE_C_INT) As SQLITE_C_INT
Declare Function alterFindTable CDecl Alias "alterFindTable" (ByVal pParse As SqliteParseContext Ptr, ByVal pSrc As SqliteSrcList Ptr, ByVal piDb As SQLITE_C_INT Ptr, ByVal pzDb As Const ZString Ptr Ptr, ByVal bAuth As SQLITE_C_INT) As SqliteTable Ptr
Declare Sub alterErrorMessage (ByVal pContext As Any Ptr, ByVal zFormat As Const ZString Ptr, ByVal zArgument As Const ZString Ptr)

/' ------------------------------------------------------------------------- '/
/' Translated ALTER TABLE procedures                                       '/
Private Function isAlterableTable CDecl Alias "isAlterableTable" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteTable Ptr) As SQLITE_C_INT
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = sqlite3_strnicmp(CPtr(Const ZString Ptr, arg1->zName), StrPtr(!"sqlite_"), Cast(SQLITE_C_INT, 7ULL)))))) OrElse (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00008000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00001000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso sqlite3ReadOnlyShadowTables(CPtr(Any Ptr, arg0->db))))))))))) Then
        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"table %s may not be altered"), arg1->zName)
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Sub renameTestSchema CDecl Alias "renameTestSchema" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Const ZString Ptr, ByVal arg4 As SQLITE_C_INT)
    Dim c2fb_temp_0 As u8 Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT

    c2fb_temp_0 = @(arg0->colNamesSet)
    c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
    c2fb_temp_1 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_1) And Cast(SQLITE_C_UINT, &H1ULL)))
    (*c2fb_temp_0) = Cast(u8, (Cast(SQLITE_C_UINT, c2fb_temp_1) And Cast(SQLITE_C_UINT, &H1ULL)))
    c2fb_temp_1 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_1) And Cast(SQLITE_C_UINT, &H1ULL)))
    sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"SELECT 1 FROM \034%w\034.sqlite_master WHERE name NOT LIKE 'sqliteX_%%' ESCAPE 'X' AND sql NOT LIKE 'create virtual%%' AND sqlite_rename_test(%Q, sql, type, name, %d, %Q, %d)=NULL "), arg1, arg1, arg2, arg3, arg4)
    If (-Cast(SQLITE_C_INT, ((arg2 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"SELECT 1 FROM temp.sqlite_master WHERE name NOT LIKE 'sqliteX_%%' ESCAPE 'X' AND sql NOT LIKE 'create virtual%%' AND sqlite_rename_test(%Q, sql, type, name, 1, %Q, %d)=NULL "), arg1, arg3, arg4)
    End If
End Sub

Private Sub renameFixQuotes CDecl Alias "renameFixQuotes" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT)
    sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"UPDATE \034%w\034.sqlite_master SET sql = sqlite_rename_quotefix(%Q, sql)WHERE name NOT LIKE 'sqliteX_%%' ESCAPE 'X' AND sql NOT LIKE 'create virtual%%'"), arg1, arg1)
    If (-Cast(SQLITE_C_INT, ((arg2 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"UPDATE temp.sqlite_master SET sql = sqlite_rename_quotefix('temp', sql)WHERE name NOT LIKE 'sqliteX_%%' ESCAPE 'X' AND sql NOT LIKE 'create virtual%%'"))
    End If
End Sub

Private Sub renameReloadSchema CDecl Alias "renameReloadSchema" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As UShort)
    Dim local0 As SqliteVdbe Ptr

    local0 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    If local0 Then
        sqlite3ChangeCookie(CPtr(Any Ptr, arg0), arg1)
        sqlite3VdbeAddParseSchemaOp(CPtr(SqliteVdbe Ptr, arg0->pVdbe), arg1, Cast(SQLITE_C_INT, &O0ULL), arg2)
        If (-Cast(SQLITE_C_INT, ((arg1 <> Cast(SQLITE_C_INT, 1ULL))))) Then
            sqlite3VdbeAddParseSchemaOp(CPtr(SqliteVdbe Ptr, arg0->pVdbe), Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, &O0ULL), arg2)
        End If
    End If
End Sub

Sub sqlite3AlterRenameTable CDecl Alias "sqlite3AlterRenameTable" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As sqlite3ParserToken Ptr)
    Dim local0 As SQLITE_C_INT
    Dim local1 As ZString Ptr
    Dim local2 As SqliteTable Ptr
    Dim local3 As ZString Ptr
    Dim local4 As sqlite3 Ptr
    Dim local5 As SQLITE_C_INT
    Dim local6 As Const ZString Ptr
    Dim local7 As SqliteVdbe Ptr
    Dim local8 As SqliteVTable Ptr
    Dim c2fb_temp_0 As SqliteTable Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As ZString Ptr
    Dim c2fb_temp_3 As ZString Ptr
    Dim c2fb_temp_4 As SqliteVTable Ptr
    Dim c2fb_temp_5 As SqliteVTable Ptr
    Dim c2fb_temp_6 As SqliteVdbe Ptr
    Dim c2fb_temp_7 As Const ZString Ptr
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim local9 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local3 = Cast(SQLITE_C_INT, &O0ULL)
    local4 = arg0->db
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local8 = Cast(SQLITE_C_INT, &O0ULL)
    If (local4->mallocFailed) Then
        Goto c2fb_label_0
    End If
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(SqliteTable Ptr, sqlite3LocateTableItem(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, CPtr(SqliteSrcItem Ptr, @(arg1->a(Cast(SQLITE_C_INT, &O0ULL)))))))
    local2 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, (local2 = 0))) Then
        Goto c2fb_label_0
    End If
    c2fb_temp_1 = Cast(SQLITE_C_INT, sqlite3SchemaToIndex(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, CPtr(SqliteSchema Ptr, local2->pSchema))))
    local0 = c2fb_temp_1
    c2fb_temp_2 = CPtr(ZString Ptr, local4->aDb(local0).zDbSName)
    local1 = c2fb_temp_2
    c2fb_temp_3 = CPtr(ZString Ptr, sqlite3NameFromToken(CPtr(Any Ptr, local4), CPtr(Any Ptr, arg2)))
    local3 = c2fb_temp_3
    If (-Cast(SQLITE_C_INT, (local3 = 0))) Then
        Goto c2fb_label_0
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((CPtr(SqliteTable Ptr, sqlite3FindTable(CPtr(Any Ptr, local4), CPtr(Const ZString Ptr, local3), CPtr(Const ZString Ptr, local1))) OrElse CPtr(SqliteIndex Ptr, sqlite3FindIndex(CPtr(Any Ptr, local4), CPtr(Const ZString Ptr, local3), CPtr(Const ZString Ptr, local1))))))) OrElse sqlite3IsShadowTableOf(CPtr(Any Ptr, local4), CPtr(Any Ptr, local2), CPtr(Const ZString Ptr, local3)))))) Then
        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"there is already another table or index with this name: %s"), local3)
        Goto c2fb_label_0
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) <> isAlterableTable(arg0, local2))))) Then
        Goto c2fb_label_0
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) <> sqlite3CheckObjectName(CPtr(Any Ptr, arg0), CPtr(Const ZString Ptr, local3), StrPtr(!"table"), CPtr(Const ZString Ptr, local3)))))) Then
        Goto c2fb_label_0
    End If
    If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local2)->eTabType) = Cast(SQLITE_C_INT, 2ULL)))))) Then
        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"view %s may not be altered"), local2->zName)
        Goto c2fb_label_0
    End If
    If sqlite3AuthCheck(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 26ULL), CPtr(Const ZString Ptr, local1), CPtr(Const ZString Ptr, local2->zName), Cast(SQLITE_C_INT, &O0ULL)) Then
        Goto c2fb_label_0
    End If
    If sqlite3ViewGetColumnNames(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local2)) Then
        Goto c2fb_label_0
    End If
    If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local2)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))) Then
        c2fb_temp_4 = CPtr(SqliteVTable Ptr, sqlite3GetVTable(CPtr(Any Ptr, local4), CPtr(Any Ptr, local2)))
        local8 = c2fb_temp_4
        If (-Cast(SQLITE_C_INT, ((CPtr(Any Ptr, CPtr(c2fb_callback_66, local8->pVtab->pModule->xRename)) = CPtr(Any Ptr, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            c2fb_temp_5 = CPtr(SqliteVTable Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            local8 = c2fb_temp_5
        End If
    End If
    c2fb_temp_6 = CPtr(SqliteVdbe Ptr, sqlite3GetVdbe(CPtr(Any Ptr, arg0)))
    local7 = c2fb_temp_6
    If (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Goto c2fb_label_0
    End If
    sqlite3MayAbort(CPtr(Any Ptr, arg0))
    c2fb_temp_7 = CPtr(Const ZString Ptr, local2->zName)
    local6 = c2fb_temp_7
    c2fb_temp_8 = Cast(SQLITE_C_INT, sqlite3Utf8CharLen(local6, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))))
    local5 = c2fb_temp_8
    sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"UPDATE \034%w\034.sqlite_master SET sql = sqlite_rename_table(%Q, type, name, sql, %Q, %Q, %d) WHERE (type!='index' OR tbl_name=%Q COLLATE nocase)AND   name NOT LIKE 'sqliteX_%%' ESCAPE 'X'"), local1, local1, local6, local3, ((-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, 1ULL)))))), local6)
    sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"UPDATE %Q.sqlite_master SET tbl_name = %Q, name = CASE WHEN type='table' THEN %Q WHEN name LIKE 'sqliteX_autoindex%%' ESCAPE 'X'      AND type='index' THEN 'sqlite_autoindex_' || %Q || substr(name,%d+18) ELSE name END WHERE tbl_name=%Q COLLATE nocase AND (type='table' OR type='index' OR type='trigger');"), local1, local3, local3, local3, local5, local6)
    If CPtr(SqliteTable Ptr, sqlite3FindTable(CPtr(Any Ptr, local4), StrPtr(!"sqlite_sequence"), CPtr(Const ZString Ptr, local1))) Then
        sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"UPDATE \034%w\034.sqlite_sequence set name = %Q WHERE name = %Q"), local1, local3, local2->zName)
    End If
    If (-Cast(SQLITE_C_INT, ((local0 <> Cast(SQLITE_C_INT, 1ULL))))) Then
        sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"UPDATE sqlite_temp_schema SET sql = sqlite_rename_table(%Q, type, name, sql, %Q, %Q, 1), tbl_name = CASE WHEN tbl_name=%Q COLLATE nocase AND   sqlite_rename_test(%Q, sql, type, name, 1, 'after rename', 0) THEN %Q ELSE tbl_name END WHERE type IN ('view', 'trigger')"), local1, local6, local3, local6, local1, local3)
    End If
    If local8 Then
        c2fb_temp_9 = @(arg0->nMem)
        c2fb_temp_10 = (*c2fb_temp_9)
        (*c2fb_temp_9) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_10 + 1)))
        c2fb_temp_11 = (*c2fb_temp_9)
        local9 = c2fb_temp_11
        sqlite3VdbeLoadString(local7, local9, CPtr(Const ZString Ptr, local3))
        sqlite3VdbeAddOp4(local7, Cast(SQLITE_C_INT, 179ULL), local9, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), CPtr(Const ZString Ptr, local8), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 12ULL)))))
    End If
    renameReloadSchema(arg0, local0, Cast(SQLITE_C_INT, &H0001ULL))
    renameTestSchema(arg0, CPtr(Const ZString Ptr, local1), (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, 1ULL))))), StrPtr(!"after rename"), Cast(SQLITE_C_INT, &O0ULL))
    c2fb_label_0:
    sqlite3SrcListDelete(CPtr(Any Ptr, local4), CPtr(Any Ptr, arg1))
    sqlite3DbFree(CPtr(Any Ptr, local4), CPtr(Any Ptr, local3))
End Sub

Private Sub sqlite3ErrorIfNotEmpty CDecl Alias "sqlite3ErrorIfNotEmpty" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const ZString Ptr)
    sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"SELECT raise(ABORT,%Q) FROM \034%w\034.\034%w\034"), arg3, arg1, arg2)
End Sub

Private Function isRowidAlias CDecl Alias "isRowidAlias" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteTable Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const ZString Ptr) As SQLITE_C_INT
    If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) AndAlso sqlite3IsRowid(arg2))))) Then
        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"cannot %s rowid alias: %s"), arg3, arg2)
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Sub sqlite3AlterFinishAddColumn CDecl Alias "sqlite3AlterFinishAddColumn" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As sqlite3ParserToken Ptr)
    Dim local0 As SqliteTable Ptr
    Dim local1 As SqliteTable Ptr
    Dim local2 As SQLITE_C_INT
    Dim local3 As Const ZString Ptr
    Dim local4 As Const ZString Ptr
    Dim local5 As ZString Ptr
    Dim local6 As SqliteColumn Ptr
    Dim local7 As SqliteExpr Ptr
    Dim local8 As sqlite3 Ptr
    Dim local9 As SqliteVdbe Ptr
    Dim local10 As SQLITE_C_INT
    Dim c2fb_temp_0 As sqlite3 Ptr
    Dim c2fb_temp_1 As SqliteTable Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As Const ZString Ptr
    Dim c2fb_temp_4 As Const ZString Ptr
    Dim c2fb_temp_5 As SqliteColumn Ptr
    Dim c2fb_temp_6 As SqliteExpr Ptr
    Dim c2fb_temp_7 As SqliteTable Ptr
    Dim c2fb_temp_8 As SqliteExpr Ptr
    Dim local11 As SqliteVdbeMem Ptr
    Dim local12 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As ZString Ptr
    Dim local13 As ZString Ptr
    Dim c2fb_temp_11 As ZString Ptr
    Dim c2fb_temp_12 As Byte Ptr
    Dim c2fb_temp_13 As Byte
    Dim c2fb_temp_14 As SqliteVdbe Ptr
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As u8 Ptr
    Dim c2fb_temp_17 As SQLITE_C_INT

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
    c2fb_temp_0 = arg0->db
    local8 = c2fb_temp_0
    ' C unused-parameter annotation
    If arg0->nErr Then
        Return
    End If
    ' C unused-parameter annotation
    c2fb_temp_1 = CPtr(SqliteTable Ptr, arg0->pNewTable)
    local0 = c2fb_temp_1
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_2 = Cast(SQLITE_C_INT, sqlite3SchemaToIndex(CPtr(Any Ptr, local8), CPtr(Any Ptr, CPtr(SqliteSchema Ptr, local0->pSchema))))
    local2 = c2fb_temp_2
    c2fb_temp_3 = CPtr(Const ZString Ptr, CPtr(ZString Ptr, local8->aDb(local2).zDbSName))
    local3 = c2fb_temp_3
    c2fb_temp_4 = CPtr(Const ZString Ptr, CPtr(Byte Ptr, @(CPtr(Byte Ptr, local0->zName)[Cast(SQLITE_C_INT, 16ULL)])))
    local4 = c2fb_temp_4
    c2fb_temp_5 = CPtr(SqliteColumn Ptr, @(local0->aCol[Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->nCol) - Cast(SQLITE_C_INT, 1ULL)))]))
    local6 = c2fb_temp_5
    c2fb_temp_6 = CPtr(SqliteExpr Ptr, sqlite3ColumnExpr(CPtr(Any Ptr, local0), CPtr(Any Ptr, local6)))
    local7 = c2fb_temp_6
    c2fb_temp_7 = CPtr(SqliteTable Ptr, sqlite3FindTable(CPtr(Any Ptr, local8), local4, local3))
    local1 = c2fb_temp_7
    ' C unused-parameter annotation
    If sqlite3AuthCheck(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 26ULL), local3, CPtr(Const ZString Ptr, local1->zName), Cast(SQLITE_C_INT, &O0ULL)) Then
        Return
    End If
    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local6->colFlags) And Cast(SQLITE_C_INT, &H0001ULL))) Then
        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"Cannot add a PRIMARY KEY column"))
        Return
    End If
    If CPtr(SqliteIndex Ptr, local0->pIndex) Then
        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"Cannot add a UNIQUE column"))
        Return
    End If
    If isRowidAlias(arg0, local1, CPtr(Const ZString Ptr, local6->zCnName), StrPtr(!"add")) Then
        Return
    End If
    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local6->colFlags) And Cast(SQLITE_C_INT, &H0060ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, ((local7 AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(SqliteExpr Ptr, local7->pLeft)->op) = Cast(SQLITE_C_INT, 122ULL))))))))) Then
            c2fb_temp_8 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            local7 = c2fb_temp_8
        End If
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local8->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &H00004000ULL))))) AndAlso local0->u.tab.pFKey)))) AndAlso local7)))) Then
            sqlite3ErrorIfNotEmpty(arg0, local3, local4, StrPtr(!"Cannot add a REFERENCES column with non-NULL default value"))
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local6->flags) Shr 0) And Cast(SQLITE_C_UINT, &HFULL))) AndAlso (-Cast(SQLITE_C_INT, (local7 = 0))))))) Then
            sqlite3ErrorIfNotEmpty(arg0, local3, local4, StrPtr(!"Cannot add a NOT NULL column with default value NULL"))
        End If
        If local7 Then
            local11 = Cast(SQLITE_C_INT, &O0ULL)
            ' C automatic storage declaration
            c2fb_temp_9 = Cast(SQLITE_C_INT, sqlite3ValueFromExpr(CPtr(Any Ptr, local8), CPtr(Any Ptr, local7), Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, &H41ULL), CPtr(Any Ptr Ptr, CPtr(SqliteVdbeMem Ptr Ptr, @(local11)))))
            local12 = c2fb_temp_9
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, ((local12 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                ' C unused-parameter annotation
                Return
            End If
            If (-Cast(SQLITE_C_INT, (local11 = 0))) Then
                sqlite3ErrorIfNotEmpty(arg0, local3, local4, StrPtr(!"Cannot add a column with non-constant default"))
            End If
            sqlite3ValueFree(CPtr(Any Ptr, local11))
        End If
    Else
        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local6->colFlags) And Cast(SQLITE_C_INT, &H0040ULL))) Then
            sqlite3ErrorIfNotEmpty(arg0, local3, local4, StrPtr(!"cannot add a STORED column"))
        End If
    End If
    c2fb_temp_10 = CPtr(ZString Ptr, sqlite3DbStrNDup(CPtr(Any Ptr, local8), CPtr(Const ZString Ptr, CPtr(ZString Ptr, CPtr(Const ZString Ptr, arg1->z))), arg1->n))
    local5 = c2fb_temp_10
    If local5 Then
        local13 = CPtr(Byte Ptr, @(CPtr(Byte Ptr, local5)[Cast(SQLITE_C_UINT, (arg1->n - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))]))
        While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local13 > local5)))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (*CPtr(Byte Ptr, local13))) = Cast(SQLITE_C_INT, 59))))) OrElse (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, sqlite3CtypeMap(Cast(UByte, ((*CPtr(Byte Ptr, local13)))))) And Cast(SQLITE_C_INT, &H01ULL)))))))))))))
            c2fb_temp_11 = local13
            local13 = (c2fb_temp_11 - 1)
            c2fb_temp_12 = @((*CPtr(Byte Ptr, c2fb_temp_11)))
            c2fb_temp_13 = Cast(Byte, Cast(SQLITE_C_INT, 0))
            (*c2fb_temp_12) = c2fb_temp_13
        c2fb_flow_1:
        Wend
        c2fb_flow_0:
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"UPDATE \034%w\034.sqlite_master SET sql = printf('%%.%ds, ',sql) || %Q || substr(sql,1+length(printf('%%.%ds',sql))) WHERE type = 'table' AND name = %Q"), local3, local0->u.tab.addColOffset, local5, local0->u.tab.addColOffset, local4)
        sqlite3DbFree(CPtr(Any Ptr, local8), CPtr(Any Ptr, local5))
    End If
    c2fb_temp_14 = CPtr(SqliteVdbe Ptr, sqlite3GetVdbe(CPtr(Any Ptr, arg0)))
    local9 = c2fb_temp_14
    If local9 Then
        c2fb_temp_15 = Cast(SQLITE_C_INT, sqlite3GetTempReg(CPtr(Any Ptr, arg0)))
        local10 = c2fb_temp_15
        sqlite3VdbeAddOp3(local9, Cast(SQLITE_C_INT, 101ULL), local2, local10, Cast(SQLITE_C_INT, 2ULL))
        sqlite3VdbeUsesBtree(local9, local2)
        sqlite3VdbeAddOp2(local9, Cast(SQLITE_C_INT, 88ULL), local10, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 2ULL))))
        sqlite3VdbeAddOp2(local9, Cast(SQLITE_C_INT, 61ULL), local10, Cast(SQLITE_C_INT, (sqlite3VdbeCurrentAddr(local9) + Cast(SQLITE_C_INT, 2ULL))))
        ' empty C statement
        sqlite3VdbeAddOp3(local9, Cast(SQLITE_C_INT, 102ULL), local2, Cast(SQLITE_C_INT, 2ULL), Cast(SQLITE_C_INT, 3ULL))
        sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local10)
        renameReloadSchema(arg0, local2, Cast(SQLITE_C_INT, &H0003ULL))
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((CPtr(SqliteExprList Ptr, local0->pCheck) <> Cast(SQLITE_C_INT, &O0ULL))))) OrElse ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local6->flags) Shr 0) And Cast(SQLITE_C_UINT, &HFULL))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local6->colFlags) And Cast(SQLITE_C_INT, &H0060ULL)))) <> Cast(SQLITE_C_INT, &O0ULL)))))))))))))) OrElse (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local1->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00010000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
            c2fb_temp_16 = @(arg0->colNamesSet)
            c2fb_temp_17 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
            c2fb_temp_17 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_17) And Cast(SQLITE_C_UINT, &H1ULL)))
            (*c2fb_temp_16) = Cast(u8, (Cast(SQLITE_C_UINT, c2fb_temp_17) And Cast(SQLITE_C_UINT, &H1ULL)))
            c2fb_temp_17 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_17) And Cast(SQLITE_C_UINT, &H1ULL)))
            sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"SELECT CASE WHEN quick_check GLOB 'CHECK*' THEN raise(ABORT,'CHECK constraint failed') WHEN quick_check GLOB 'non-* value in*' THEN raise(ABORT,'type mismatch on DEFAULT') ELSE raise(ABORT,'NOT NULL constraint failed') END  FROM pragma_quick_check(%Q,%Q) WHERE quick_check GLOB 'CHECK*' OR quick_check GLOB 'NULL*' OR quick_check GLOB 'non-* value in*'"), local4, local3)
        End If
    End If
End Sub

Sub sqlite3AlterRenameColumn CDecl Alias "sqlite3AlterRenameColumn" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As sqlite3ParserToken Ptr, ByVal arg3 As sqlite3ParserToken Ptr)
    Dim local0 As sqlite3 Ptr
    Dim local1 As SqliteTable Ptr
    Dim local2 As SQLITE_C_INT
    Dim local3 As ZString Ptr
    Dim local4 As ZString Ptr
    Dim local5 As Const ZString Ptr
    Dim local6 As SQLITE_C_INT
    Dim local7 As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteTable Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As Const ZString Ptr
    Dim c2fb_temp_3 As ZString Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As ZString Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT

    local0 = arg0->db
    ' C automatic storage declaration
    ' C automatic storage declaration
    local3 = Cast(SQLITE_C_INT, &O0ULL)
    local4 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    c2fb_temp_0 = CPtr(SqliteTable Ptr, sqlite3LocateTableItem(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, CPtr(SqliteSrcItem Ptr, @(arg1->a(Cast(SQLITE_C_INT, &O0ULL)))))))
    local1 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, (local1 = 0))) Then
        Goto c2fb_label_0
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) <> isAlterableTable(arg0, local1))))) Then
        Goto c2fb_label_0
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) <> isRealTable(arg0, local1, Cast(SQLITE_C_INT, &O0ULL)))))) Then
        Goto c2fb_label_0
    End If
    c2fb_temp_1 = Cast(SQLITE_C_INT, sqlite3SchemaToIndex(CPtr(Any Ptr, local0), CPtr(Any Ptr, CPtr(SqliteSchema Ptr, local1->pSchema))))
    local6 = c2fb_temp_1
    ' C unused-parameter annotation
    c2fb_temp_2 = CPtr(Const ZString Ptr, CPtr(ZString Ptr, local0->aDb(local6).zDbSName))
    local5 = c2fb_temp_2
    If sqlite3AuthCheck(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 26ULL), local5, CPtr(Const ZString Ptr, local1->zName), Cast(SQLITE_C_INT, &O0ULL)) Then
        Goto c2fb_label_0
    End If
    c2fb_temp_3 = CPtr(ZString Ptr, sqlite3NameFromToken(CPtr(Any Ptr, local0), CPtr(Any Ptr, arg2)))
    local3 = c2fb_temp_3
    If (-Cast(SQLITE_C_INT, (local3 = 0))) Then
        Goto c2fb_label_0
    End If
    c2fb_temp_4 = Cast(SQLITE_C_INT, sqlite3ColumnIndex(CPtr(Any Ptr, local1), CPtr(Const ZString Ptr, local3)))
    local2 = c2fb_temp_4
    If (-Cast(SQLITE_C_INT, ((local2 < Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"no such column: \034%T\034"), arg2)
        Goto c2fb_label_0
    End If
    renameTestSchema(arg0, local5, (-Cast(SQLITE_C_INT, ((local6 = Cast(SQLITE_C_INT, 1ULL))))), StrPtr(!""), Cast(SQLITE_C_INT, &O0ULL))
    renameFixQuotes(arg0, local5, (-Cast(SQLITE_C_INT, ((local6 = Cast(SQLITE_C_INT, 1ULL))))))
    sqlite3MayAbort(CPtr(Any Ptr, arg0))
    c2fb_temp_5 = CPtr(ZString Ptr, sqlite3NameFromToken(CPtr(Any Ptr, local0), CPtr(Any Ptr, arg3)))
    local4 = c2fb_temp_5
    If (-Cast(SQLITE_C_INT, (local4 = 0))) Then
        Goto c2fb_label_0
    End If
    If isRowidAlias(arg0, local1, CPtr(Const ZString Ptr, local3), StrPtr(!"rename from")) Then
        Goto c2fb_label_0
    End If
    If isRowidAlias(arg0, local1, CPtr(Const ZString Ptr, local4), StrPtr(!"rename to")) Then
        Goto c2fb_label_0
    End If
    ' C unused-parameter annotation
    c2fb_temp_6 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, sqlite3CtypeMap(Cast(UByte, (CPtr(Const Byte Ptr, CPtr(Const ZString Ptr, arg3->z))[Cast(SQLITE_C_INT, &O0ULL)])))) And Cast(SQLITE_C_INT, &H80ULL)))))
    local7 = c2fb_temp_6
    sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"UPDATE \034%w\034.sqlite_master SET sql = sqlite_rename_column(sql, type, name, %Q, %Q, %d, %Q, %d, %d) WHERE name NOT LIKE 'sqliteX_%%' ESCAPE 'X'  AND (type != 'index' OR tbl_name = %Q)"), local5, local5, local1->zName, local2, local4, local7, (-Cast(SQLITE_C_INT, ((local6 = Cast(SQLITE_C_INT, 1ULL))))), local1->zName)
    sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"UPDATE temp.sqlite_master SET sql = sqlite_rename_column(sql, type, name, %Q, %Q, %d, %Q, %d, 1) WHERE type IN ('trigger', 'view')"), local5, local1->zName, local2, local4, local7)
    renameReloadSchema(arg0, local6, Cast(SQLITE_C_INT, &H0001ULL))
    renameTestSchema(arg0, local5, (-Cast(SQLITE_C_INT, ((local6 = Cast(SQLITE_C_INT, 1ULL))))), StrPtr(!"after rename"), Cast(SQLITE_C_INT, 1ULL))
    c2fb_label_0:
    sqlite3SrcListDelete(CPtr(Any Ptr, local0), CPtr(Any Ptr, arg1))
    sqlite3DbFree(CPtr(Any Ptr, local0), CPtr(Any Ptr, local3))
    sqlite3DbFree(CPtr(Any Ptr, local0), CPtr(Any Ptr, local4))
    Return
End Sub

Sub sqlite3AlterDropColumn CDecl Alias "sqlite3AlterDropColumn" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As Const sqlite3ParserToken Ptr)
    Dim local0 As sqlite3 Ptr
    Dim local1 As SqliteTable Ptr
    Dim local2 As SQLITE_C_INT
    Dim local3 As Const ZString Ptr
    Dim local4 As ZString Ptr
    Dim local5 As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteTable Ptr
    Dim c2fb_temp_1 As ZString Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As Const ZString Ptr
    Dim local6 As SQLITE_C_INT
    Dim local7 As SQLITE_C_INT
    Dim local8 As SQLITE_C_INT
    Dim local9 As SQLITE_C_INT
    Dim local10 As SqliteIndex Ptr
    Dim local11 As SQLITE_C_INT
    Dim local12 As SQLITE_C_INT
    Dim local13 As SqliteVdbe Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT Ptr
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SqliteIndex Ptr
    Dim c2fb_temp_16 As SQLITE_C_INT Ptr
    Dim c2fb_temp_17 As SQLITE_C_INT
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As SQLITE_C_INT Ptr
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim c2fb_temp_23 As SQLITE_C_INT
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As SQLITE_C_INT
    Dim c2fb_temp_26 As SQLITE_C_INT
    Dim local14 As SQLITE_C_INT
    Dim local15 As SQLITE_C_INT
    Dim local16 As SQLITE_C_INT
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim c2fb_temp_28 As SQLITE_C_INT
    Dim local17 As Byte
    Dim c2fb_temp_29 As Byte Ptr
    Dim c2fb_temp_30 As Byte
    Dim c2fb_temp_31 As Byte Ptr
    Dim c2fb_temp_32 As Byte
    Dim c2fb_temp_33 As SQLITE_C_INT
    Dim c2fb_temp_34 As SQLITE_C_INT Ptr
    Dim c2fb_temp_35 As SQLITE_C_INT
    Dim c2fb_temp_36 As SQLITE_C_INT

    local0 = arg0->db
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local4 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (local0->mallocFailed) Then
        Goto c2fb_label_0
    End If
    c2fb_temp_0 = CPtr(SqliteTable Ptr, sqlite3LocateTableItem(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, CPtr(SqliteSrcItem Ptr, @(arg1->a(Cast(SQLITE_C_INT, &O0ULL)))))))
    local1 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, (local1 = 0))) Then
        Goto c2fb_label_0
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) <> isAlterableTable(arg0, local1))))) Then
        Goto c2fb_label_0
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) <> isRealTable(arg0, local1, Cast(SQLITE_C_INT, 1ULL)))))) Then
        Goto c2fb_label_0
    End If
    c2fb_temp_1 = CPtr(ZString Ptr, sqlite3NameFromToken(CPtr(Any Ptr, local0), CPtr(Any Ptr, arg2)))
    local4 = c2fb_temp_1
    If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        ' C unused-parameter annotation
        Goto c2fb_label_0
    End If
    c2fb_temp_2 = Cast(SQLITE_C_INT, sqlite3ColumnIndex(CPtr(Any Ptr, local1), CPtr(Const ZString Ptr, local4)))
    local5 = c2fb_temp_2
    If (-Cast(SQLITE_C_INT, ((local5 < Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"no such column: \034%T\034"), arg2)
        Goto c2fb_label_0
    End If
    If isRowidAlias(arg0, local1, CPtr(Const ZString Ptr, local4), StrPtr(!"drop")) Then
        Goto c2fb_label_0
    End If
    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->aCol[local5].colFlags) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0001ULL) Or Cast(SQLITE_C_INT, &H0008ULL)))))) Then
        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"cannot drop %s column: \034%s\034"), IIf((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->aCol[local5].colFlags) And Cast(SQLITE_C_INT, &H0001ULL)))), StrPtr(!"PRIMARY KEY"), StrPtr(!"UNIQUE")), local4)
        Goto c2fb_label_0
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->nCol) <= Cast(SQLITE_C_INT, 1ULL))))) Then
        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"cannot drop column \034%s\034: no other columns exist"), local4)
        Goto c2fb_label_0
    End If
    c2fb_temp_3 = Cast(SQLITE_C_INT, sqlite3SchemaToIndex(CPtr(Any Ptr, local0), CPtr(Any Ptr, CPtr(SqliteSchema Ptr, local1->pSchema))))
    local2 = c2fb_temp_3
    ' C unused-parameter annotation
    c2fb_temp_4 = CPtr(Const ZString Ptr, CPtr(ZString Ptr, local0->aDb(local2).zDbSName))
    local3 = c2fb_temp_4
    If sqlite3AuthCheck(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 26ULL), local3, CPtr(Const ZString Ptr, local1->zName), CPtr(Const ZString Ptr, local4)) Then
        Goto c2fb_label_0
    End If
    renameTestSchema(arg0, local3, (-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, 1ULL))))), StrPtr(!""), Cast(SQLITE_C_INT, &O0ULL))
    renameFixQuotes(arg0, local3, (-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, 1ULL))))))
    sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"UPDATE \034%w\034.sqlite_master SET sql = sqlite_drop_column(%d, sql, %d) WHERE (type=='table' AND tbl_name=%Q COLLATE nocase)"), local3, local2, local5, local1->zName)
    renameReloadSchema(arg0, local2, Cast(SQLITE_C_INT, &H0002ULL))
    renameTestSchema(arg0, local3, (-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, 1ULL))))), StrPtr(!"after drop column"), Cast(SQLITE_C_INT, 1ULL))
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg0->nErr = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->aCol[local5].colFlags) And Cast(SQLITE_C_INT, &H0020ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        local10 = Cast(SQLITE_C_INT, &O0ULL)
        local11 = Cast(SQLITE_C_INT, &O0ULL)
        ' C automatic storage declaration
        local13 = CPtr(SqliteVdbe Ptr, sqlite3GetVdbe(CPtr(Any Ptr, arg0)))
        c2fb_temp_5 = @(arg0->nTab)
        c2fb_temp_6 = (*c2fb_temp_5)
        (*c2fb_temp_5) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 + 1)))
        c2fb_temp_7 = Cast(SQLITE_C_INT, c2fb_temp_6)
        local12 = c2fb_temp_7
        sqlite3OpenTable(CPtr(Any Ptr, arg0), local12, local2, CPtr(Any Ptr, local1), Cast(SQLITE_C_INT, 116ULL))
        c2fb_temp_8 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(local13, Cast(SQLITE_C_INT, 36ULL), local12))
        local7 = c2fb_temp_8
        ' empty C statement
        c2fb_temp_9 = @(arg0->nMem)
        c2fb_temp_10 = (*c2fb_temp_9)
        (*c2fb_temp_9) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_10 + 1)))
        c2fb_temp_11 = (*c2fb_temp_9)
        c2fb_temp_12 = Cast(SQLITE_C_INT, c2fb_temp_11)
        local8 = c2fb_temp_12
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local1)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            sqlite3VdbeAddOp2(local13, Cast(SQLITE_C_INT, 137ULL), local12, local8)
            c2fb_temp_13 = @(arg0->nMem)
            c2fb_temp_14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_13) + Cast(SQLITE_C_INT, local1->nCol))))
            (*c2fb_temp_13) = c2fb_temp_14
        Else
            c2fb_temp_15 = CPtr(SqliteIndex Ptr, sqlite3PrimaryKeyIndex(CPtr(Any Ptr, local1)))
            local10 = c2fb_temp_15
            c2fb_temp_16 = @(arg0->nMem)
            c2fb_temp_17 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_16) + Cast(SQLITE_C_INT, local10->nColumn))))
            (*c2fb_temp_16) = c2fb_temp_17
            c2fb_temp_18 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local6 = c2fb_temp_18
            While (-Cast(SQLITE_C_INT, ((local6 < Cast(SQLITE_C_INT, local10->nKeyCol)))))
                sqlite3VdbeAddOp3(local13, Cast(SQLITE_C_INT, 96ULL), local12, local6, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local8 + local6)) + Cast(SQLITE_C_INT, 1ULL))))
            c2fb_flow_1:
                c2fb_temp_19 = local6
                local6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_19 + 1)))
            Wend
            c2fb_flow_0:
            c2fb_temp_20 = Cast(SQLITE_C_INT, local10->nKeyCol)
            local11 = c2fb_temp_20
        End If
        c2fb_temp_21 = @(arg0->nMem)
        c2fb_temp_22 = (*c2fb_temp_21)
        (*c2fb_temp_21) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_22 + 1)))
        c2fb_temp_23 = (*c2fb_temp_21)
        c2fb_temp_24 = Cast(SQLITE_C_INT, c2fb_temp_23)
        local9 = c2fb_temp_24
        c2fb_temp_25 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local6 = c2fb_temp_25
        While (-Cast(SQLITE_C_INT, ((local6 < Cast(SQLITE_C_INT, local1->nCol)))))
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local6 <> local5)))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->aCol[local6].colFlags) And Cast(SQLITE_C_INT, &H0020ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                ' C automatic storage declaration
                If local10 Then
                    local15 = sqlite3TableColumnToIndex(CPtr(Any Ptr, local10), local6)
                    local16 = sqlite3TableColumnToIndex(CPtr(Any Ptr, local10), local5)
                    If (-Cast(SQLITE_C_INT, ((local15 < Cast(SQLITE_C_INT, local10->nKeyCol))))) Then
                        Goto c2fb_flow_3
                    End If
                    c2fb_temp_27 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local8 + Cast(SQLITE_C_INT, 1ULL))) + local15)) - ((-Cast(SQLITE_C_INT, ((local15 > local16))))))))
                    local14 = c2fb_temp_27
                Else
                    c2fb_temp_28 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local8 + Cast(SQLITE_C_INT, 1ULL))) + local11)))
                    local14 = c2fb_temp_28
                End If
                If (-Cast(SQLITE_C_INT, ((local6 = Cast(SQLITE_C_INT, local1->iPKey))))) Then
                    sqlite3VdbeAddOp2(local13, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), local14)
                Else
                    local17 = local1->aCol[local6].affinity
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local17) = Cast(SQLITE_C_INT, &H45ULL))))) Then
                        c2fb_temp_29 = @(local1->aCol[local6].affinity)
                        c2fb_temp_30 = Cast(Byte, Cast(SQLITE_C_INT, &H43ULL))
                        (*c2fb_temp_29) = c2fb_temp_30
                    End If
                    sqlite3ExprCodeGetColumnOfTable(CPtr(Any Ptr, local13), CPtr(Any Ptr, local1), local12, local6, local14)
                    c2fb_temp_31 = @(local1->aCol[local6].affinity)
                    c2fb_temp_32 = Cast(Byte, local17)
                    (*c2fb_temp_31) = c2fb_temp_32
                End If
                c2fb_temp_33 = local11
                local11 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_33 + 1)))
            End If
        c2fb_flow_3:
            c2fb_temp_26 = local6
            local6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_26 + 1)))
        Wend
        c2fb_flow_2:
        If (-Cast(SQLITE_C_INT, ((local11 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_34 = @(arg0->nMem)
            c2fb_temp_35 = (*c2fb_temp_34)
            (*c2fb_temp_34) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_35 + 1)))
            sqlite3VdbeAddOp2(local13, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, (local8 + Cast(SQLITE_C_INT, 1ULL))))
            c2fb_temp_36 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
            local11 = c2fb_temp_36
        End If
        sqlite3VdbeAddOp3(local13, Cast(SQLITE_C_INT, 99ULL), Cast(SQLITE_C_INT, (local8 + Cast(SQLITE_C_INT, 1ULL))), local11, local9)
        If local10 Then
            sqlite3VdbeAddOp4Int(local13, Cast(SQLITE_C_INT, 140ULL), local12, local9, Cast(SQLITE_C_INT, (local8 + Cast(SQLITE_C_INT, 1ULL))), local10->nKeyCol)
        Else
            sqlite3VdbeAddOp3(local13, Cast(SQLITE_C_INT, 130ULL), local12, local9, local8)
        End If
        sqlite3VdbeChangeP5(local13, Cast(SQLITE_C_INT, &H02ULL))
        sqlite3VdbeAddOp2(local13, Cast(SQLITE_C_INT, 40ULL), local12, Cast(SQLITE_C_INT, (local7 + Cast(SQLITE_C_INT, 1ULL))))
        ' empty C statement
        sqlite3VdbeJumpHere(local13, local7)
    End If
    c2fb_label_0:
    sqlite3DbFree(CPtr(Any Ptr, local0), CPtr(Any Ptr, local4))
    sqlite3SrcListDelete(CPtr(Any Ptr, local0), CPtr(Any Ptr, arg1))
End Sub

Private Function alterFindCol CDecl Alias "alterFindCol" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteTable Ptr, ByVal arg2 As sqlite3ParserToken Ptr, ByVal arg3 As SQLITE_C_INT Ptr) As SQLITE_C_INT
    Dim local0 As sqlite3 Ptr
    Dim local1 As ZString Ptr
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim local4 As Const ZString Ptr
    Dim local5 As Const ZString Ptr
    Dim c2fb_temp_3 As SqliteTable Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT

    local0 = arg0->db
    local1 = CPtr(ZString Ptr, sqlite3NameFromToken(CPtr(Any Ptr, local0), CPtr(Any Ptr, arg2)))
    local2 = Cast(SQLITE_C_INT, 7ULL)
    local3 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))
    If local1 Then
        c2fb_temp_0 = Cast(SQLITE_C_INT, sqlite3ColumnIndex(CPtr(Any Ptr, arg1), CPtr(Const ZString Ptr, local1)))
        local3 = c2fb_temp_0
        If (-Cast(SQLITE_C_INT, ((local3 < Cast(SQLITE_C_INT, &O0ULL))))) Then
            sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"no such column: %s"), local1)
            c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
            local2 = c2fb_temp_1
        Else
            c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local2 = c2fb_temp_2
        End If
    End If
    If (-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        local4 = CPtr(ZString Ptr, local0->aDb(sqlite3SchemaToIndex(CPtr(Any Ptr, local0), CPtr(Any Ptr, CPtr(SqliteSchema Ptr, arg1->pSchema)))).zDbSName)
        local5 = arg1->aCol[local3].zCnName
        If sqlite3AuthCheck(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 26ULL), local4, CPtr(Const ZString Ptr, arg1->zName), local5) Then
            c2fb_temp_3 = CPtr(SqliteTable Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            arg1 = c2fb_temp_3
        End If
    End If
    sqlite3DbFree(CPtr(Any Ptr, local0), CPtr(Any Ptr, local1))
    c2fb_temp_4 = @((*arg3))
    c2fb_temp_5 = Cast(SQLITE_C_INT, local3)
    (*c2fb_temp_4) = c2fb_temp_5
    Return local2
End Function

Sub sqlite3AlterDropConstraint CDecl Alias "sqlite3AlterDropConstraint" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As sqlite3ParserToken Ptr, ByVal arg3 As sqlite3ParserToken Ptr)
    Dim local0 As sqlite3 Ptr
    Dim local1 As SqliteTable Ptr
    Dim local2 As SQLITE_C_INT
    Dim local3 As Const ZString Ptr
    Dim local4 As ZString Ptr
    Dim c2fb_temp_0 As SqliteTable Ptr
    Dim local5 As ZString Ptr
    Dim c2fb_temp_1 As ZString Ptr
    Dim local6 As SQLITE_C_INT
    Dim c2fb_temp_2 As ZString Ptr

    local0 = arg0->db
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    local2 = Cast(SQLITE_C_INT, &O0ULL)
    local3 = Cast(SQLITE_C_INT, &O0ULL)
    local4 = Cast(SQLITE_C_INT, &O0ULL)
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(SqliteTable Ptr, alterFindTable(arg0, arg1, CPtr(SQLITE_C_INT Ptr, @(local2)), CPtr(Const ZString Ptr Ptr, @(local3)), (-Cast(SQLITE_C_INT, ((arg2 <> Cast(SQLITE_C_INT, &O0ULL)))))))
    local1 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, (local1 = 0))) Then
        Return
    End If
    If arg2 Then
        local5 = CPtr(ZString Ptr, sqlite3NameFromToken(CPtr(Any Ptr, local0), CPtr(Any Ptr, arg2)))
        c2fb_temp_1 = CPtr(ZString Ptr, sqlite3MPrintf(CPtr(Any Ptr, local0), StrPtr(!"%Q"), local5))
        local4 = c2fb_temp_1
        sqlite3DbFree(CPtr(Any Ptr, local0), CPtr(Any Ptr, local5))
    Else
        ' C automatic storage declaration
        If alterFindCol(arg0, local1, arg3, CPtr(SQLITE_C_INT Ptr, @(local6))) Then
            Return
        End If
        c2fb_temp_2 = CPtr(ZString Ptr, sqlite3MPrintf(CPtr(Any Ptr, local0), StrPtr(!"%d"), local6))
        local4 = c2fb_temp_2
    End If
    sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"UPDATE \034%w\034.sqlite_master SET sql = sqlite_drop_constraint(sql, %s) WHERE type='table' AND tbl_name=%Q COLLATE nocase"), local3, local4, local1->zName)
    sqlite3DbFree(CPtr(Any Ptr, local0), CPtr(Any Ptr, local4))
    renameReloadSchema(arg0, local2, Cast(SQLITE_C_INT, &H0004ULL))
End Sub

Private Function alterRtrimConstraint CDecl Alias "alterRtrimConstraint" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As UByte Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT

    local0 = CPtr(UByte Ptr, CPtr(ZString Ptr, sqlite3MPrintf(CPtr(Any Ptr, arg0), StrPtr(!"%.*s"), arg2, arg1)))
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    local2 = Cast(SQLITE_C_INT, &O0ULL)
    If (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    While Cast(SQLITE_C_INT, 1ULL)
        local3 = Cast(SQLITE_C_INT, &O0ULL)
        local4 = sqlite3GetToken(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0[local1]))), CPtr(SQLITE_C_INT Ptr, @(local3)))
        If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, 186ULL))))) Then
            Goto c2fb_flow_0
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, 184ULL))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, 185ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0[local1]) <> Cast(SQLITE_C_INT, 45)))))))))))))) Then
            c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local1 + local4)))
            local2 = c2fb_temp_0
        End If
        c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local1 + local4)))
        local1 = c2fb_temp_1
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    sqlite3DbFree(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local0))
    Return local2
End Function

Sub sqlite3AlterSetNotNull CDecl Alias "sqlite3AlterSetNotNull" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As sqlite3ParserToken Ptr, ByVal arg3 As sqlite3ParserToken Ptr)
    Dim local0 As SqliteTable Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As Const ZString Ptr
    Dim local4 As Const ZString Ptr
    Dim local5 As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteTable Ptr
    Dim c2fb_temp_1 As Const ZString Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    local2 = Cast(SQLITE_C_INT, &O0ULL)
    local3 = Cast(SQLITE_C_INT, &O0ULL)
    local4 = Cast(SQLITE_C_INT, &O0ULL)
    local5 = Cast(SQLITE_C_INT, &O0ULL)
    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(SqliteTable Ptr, alterFindTable(arg0, arg1, CPtr(SQLITE_C_INT Ptr, @(local2)), CPtr(Const ZString Ptr Ptr, @(local3)), Cast(SQLITE_C_INT, &O0ULL)))
    local0 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, (local0 = 0))) Then
        Return
    End If
    If alterFindCol(arg0, local0, arg2, CPtr(SQLITE_C_INT Ptr, @(local1))) Then
        Return
    End If
    c2fb_temp_1 = CPtr(Const ZString Ptr, arg3->z)
    local4 = c2fb_temp_1
    c2fb_temp_2 = Cast(SQLITE_C_INT, alterRtrimConstraint(arg0->db, local4, (CPtr(Const Byte Ptr, CPtr(Const ZString Ptr, arg0->sLastToken.z)) - CPtr(Const Byte Ptr, local4))))
    local5 = c2fb_temp_2
    sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"SELECT sqlite_fail('constraint failed', %d) FROM %Q.%Q AS x WHERE x.%.*s IS NULL"), Cast(SQLITE_C_INT, 19ULL), local3, local0->zName, Cast(SQLITE_C_INT, arg2->n), CPtr(Const ZString Ptr, arg2->z))
    sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"UPDATE \034%w\034.sqlite_master SET sql = sqlite_add_constraint(sqlite_drop_constraint(sql, %d), %.*Q, %d) WHERE type='table' AND tbl_name=%Q COLLATE nocase"), local3, local1, local5, local4, local1, local0->zName)
    renameReloadSchema(arg0, local2, Cast(SQLITE_C_INT, &H0004ULL))
End Sub

Sub sqlite3AlterAddConstraint CDecl Alias "sqlite3AlterAddConstraint" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As sqlite3ParserToken Ptr, ByVal arg3 As sqlite3ParserToken Ptr, ByVal arg4 As Const ZString Ptr, ByVal arg5 As SQLITE_C_INT, ByVal arg6 As SqliteExpr Ptr)
    Dim local0 As SqliteTable Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As Const ZString Ptr
    Dim local3 As Const ZString Ptr
    Dim local4 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteTable Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local6 As ZString Ptr
    Dim c2fb_temp_2 As Const ZString Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    local2 = Cast(SQLITE_C_INT, &O0ULL)
    local3 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(SqliteTable Ptr, alterFindTable(arg0, arg1, CPtr(SQLITE_C_INT Ptr, @(local1)), CPtr(Const ZString Ptr Ptr, @(local2)), Cast(SQLITE_C_INT, 1ULL)))
    local0 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, (local0 = 0))) Then
        sqlite3ExprDelete(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, arg6))
        Return
    End If
    c2fb_temp_1 = Cast(SQLITE_C_INT, sqlite3ResolveSelfReference(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local0), Cast(SQLITE_C_INT, &H000004ULL), CPtr(Any Ptr, arg6), Cast(SQLITE_C_INT, &O0ULL)))
    local5 = c2fb_temp_1
    sqlite3ExprDelete(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, arg6))
    If local5 Then
        Return
    End If
    If arg3 Then
        local6 = CPtr(ZString Ptr, sqlite3NameFromToken(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, arg3)))
        sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"SELECT sqlite_fail('constraint %q already exists', %d) FROM \034%w\034.sqlite_master WHERE type='table' AND tbl_name=%Q COLLATE nocase AND sqlite_find_constraint(sql, %Q)"), local6, Cast(SQLITE_C_INT, 1ULL), local2, local0->zName, local6)
        sqlite3DbFree(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, local6))
    End If
    sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"SELECT sqlite_fail('constraint failed', %d) FROM %Q.%Q WHERE (%.*s) IS FALSE"), Cast(SQLITE_C_INT, 19ULL), local2, local0->zName, arg5, arg4)
    c2fb_temp_2 = CPtr(Const ZString Ptr, arg2->z)
    local3 = c2fb_temp_2
    c2fb_temp_3 = Cast(SQLITE_C_INT, alterRtrimConstraint(arg0->db, local3, (CPtr(Const Byte Ptr, CPtr(Const ZString Ptr, arg0->sLastToken.z)) - CPtr(Const Byte Ptr, local3))))
    local4 = c2fb_temp_3
    sqlite3NestedParse(CPtr(Any Ptr, arg0), StrPtr(!"UPDATE \034%w\034.sqlite_master SET sql = sqlite_add_constraint(sql, %.*Q, -1) WHERE type='table' AND tbl_name=%Q COLLATE nocase"), local2, local4, local3, local0->zName)
    renameReloadSchema(arg0, local1, Cast(SQLITE_C_INT, &H0004ULL))
End Sub

/' ------------------------------------------------------------------------- '/
/' Local helpers for ALTER TABLE validation and constraint diagnostics '/

Private Function isRealTable CDecl Alias "isRealTable" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pTable As SqliteTable Ptr, _
    ByVal operation As SQLITE_C_INT _
) As SQLITE_C_INT
    Dim zType As Const ZString Ptr = 0
    Dim zOperation As Const ZString Ptr = 0

    If pParse = 0 OrElse pTable = 0 Then Return SQLITE_ERROR

    If pTable->eTabType = TABTYP_VIEW Then
        zType = StrPtr(!"view")
    ElseIf pTable->eTabType = TABTYP_VTAB Then
        zType = StrPtr(!"virtual table")
    End If

    If zType = 0 Then Return SQLITE_OK

    Select Case operation
    Case 0
        zOperation = StrPtr(!"rename columns of")
    Case 1
        zOperation = StrPtr(!"drop column from")
    Case 2
        zOperation = StrPtr(!"edit constraints of")
    Case Else
        Return SQLITE_ERROR
    End Select

    sqlite3ErrorMsg(pParse, StrPtr(!"cannot %s %s \034%s\034"), _
                    zOperation, zType, pTable->zName)
    Return SQLITE_ERROR
End Function

Private Function alterFindTable CDecl Alias "alterFindTable" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSrc As SqliteSrcList Ptr, _
    ByVal piDb As SQLITE_C_INT Ptr, _
    ByVal pzDb As Const ZString Ptr Ptr, _
    ByVal bAuth As SQLITE_C_INT _
) As SqliteTable Ptr
    Dim db As sqlite3 Ptr
    Dim pTable As SqliteTable Ptr = 0
    Dim dbIndex As SQLITE_C_INT

    If pParse = 0 OrElse pParse->db = 0 Then Return 0
    db = pParse->db

    If pSrc = 0 Then Return 0
    If pSrc->nSrc <= 0 OrElse piDb = 0 OrElse _
       CPtr(Any Ptr, pzDb) = 0 Then
        sqlite3SrcListDelete(db, pSrc)
        Return 0
    End If

    ' sqlite3LocateTableItem() requires the parser's normal B-tree lock context.
    pTable = CPtr(SqliteTable Ptr, _
        sqlite3LocateTableItem(pParse, 0, @pSrc->a(0)))
    If pTable Then
        dbIndex = sqlite3SchemaToIndex(db, pTable->pSchema)
        If dbIndex < 0 Then
            pTable = 0
        Else
            piDb[0] = dbIndex
            pzDb[0] = db->aDb(dbIndex).zDbSName
            If isRealTable(pParse, pTable, 2) <> SQLITE_OK OrElse _
               isAlterableTable(pParse, pTable) <> SQLITE_OK Then
                pTable = 0
            End If
        End If
    End If

#ifndef SQLITE_OMIT_AUTHORIZATION
    If pTable AndAlso bAuth <> 0 Then
        If sqlite3AuthCheck(pParse, SQLITE_ALTER_TABLE, pzDb[0], _
                            pTable->zName, 0) <> SQLITE_OK Then
            pTable = 0
        End If
    End If
#endif

    sqlite3SrcListDelete(db, pSrc)
    Return pTable
End Function

Private Sub alterErrorMessage ( _
    ByVal pContext As Any Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ByVal zArgument As Const ZString Ptr _
)
    ' Both source call sites pass one string for one %s conversion.
    ' Keep allocation and OOM reporting on SQLite's formatter path.
    Dim db As sqlite3 Ptr = _
        CPtr(sqlite3 Ptr, sqlite3_context_db_handle(pContext))
    Dim zError As ZString Ptr = sqlite3MPrintf(db, zFormat, zArgument)

    If zError Then
        sqlite3_result_error(pContext, zError, -1)
        sqlite3DbFree(db, zError)
    Else
        sqlite3_result_error_nomem(pContext)
    End If
End Sub

/' ------------------------------------------------------------------------- '/
/' ALTER TABLE ADD COLUMN setup '/

Sub sqlite3AlterBeginAddColumn CDecl Alias "sqlite3AlterBeginAddColumn" ( _
    ByVal pParseArgument As Any Ptr, _
    ByVal pSrcArgument As Any Ptr _
)
    Dim pParse As SqliteParseContext Ptr = _
        CPtr(SqliteParseContext Ptr, pParseArgument)
    Dim pSrc As SqliteSrcList Ptr = CPtr(SqliteSrcList Ptr, pSrcArgument)

    If pParse = 0 OrElse pParse->db = 0 Then Return

    Dim db As sqlite3 Ptr = pParse->db
    Dim pNew As SqliteTable Ptr = 0
    Dim pTable As SqliteTable Ptr = 0
    Dim dbIndex As SQLITE_C_INT = 0
    Dim columnCapacity As SQLITE_C_INT = 0

    If pSrc = 0 OrElse pSrc->nSrc <= 0 Then Goto add_column_cleanup
    If pParse->pNewTable <> 0 OrElse db->mallocFailed <> 0 Then _
        Goto add_column_cleanup

    ' The parser calls this while all B-tree mutexes are held.
    pTable = CPtr(SqliteTable Ptr, _
        sqlite3LocateTableItem(pParse, 0, @pSrc->a(0)))
    If pTable = 0 Then Goto add_column_cleanup

#ifndef SQLITE_OMIT_VIRTUALTABLE
    If pTable->eTabType = TABTYP_VTAB Then
        sqlite3ErrorMsg(pParse, StrPtr(!"virtual tables may not be altered"))
        Goto add_column_cleanup
    End If
#endif

#ifndef SQLITE_OMIT_VIEW
    If pTable->eTabType = TABTYP_VIEW Then
        sqlite3ErrorMsg(pParse, StrPtr(!"Cannot add a column to a view"))
        Goto add_column_cleanup
    End If
#endif

    If isAlterableTable(pParse, pTable) <> SQLITE_OK Then _
        Goto add_column_cleanup

    sqlite3MayAbort(pParse)
    dbIndex = sqlite3SchemaToIndex(db, pTable->pSchema)
    If dbIndex < 0 Then Goto add_column_cleanup

    pNew = CPtr(SqliteTable Ptr, _
        sqlite3DbMallocZero(db, SizeOf(SqliteTable)))
    If pNew = 0 Then Goto add_column_cleanup

    pParse->pNewTable = pNew
    pNew->nTabRef = 1
    pNew->nCol = pTable->nCol
    If pNew->nCol <= 0 Then Goto add_column_cleanup

    columnCapacity = (((pNew->nCol - 1) \ 8) * 8) + 8
    pNew->aCol = CPtr(SqliteColumn Ptr, sqlite3DbMallocZero( _
        db, CULngInt(SizeOf(SqliteColumn)) * CULngInt(columnCapacity)))
    pNew->zName = sqlite3MPrintf( _
        db, StrPtr(!"sqlite_altertab_%s"), pTable->zName)
    If pNew->aCol = 0 OrElse pNew->zName = 0 Then _
        Goto add_column_cleanup

    For columnIndex As SQLITE_C_INT = 0 To pNew->nCol - 1
        pNew->aCol[columnIndex] = pTable->aCol[columnIndex]
        pNew->aCol[columnIndex].zCnName = sqlite3DbStrDup( _
            db, pNew->aCol[columnIndex].zCnName)
        pNew->aCol[columnIndex].hName = sqlite3StrIHash( _
            pNew->aCol[columnIndex].zCnName)
    Next

    pNew->u.tab.pDfltList = sqlite3ExprListDup( _
        db, pTable->u.tab.pDfltList, 0)
    pNew->pSchema = pTable->pSchema
    pNew->u.tab.addColOffset = pTable->u.tab.addColOffset

add_column_cleanup:
    sqlite3SrcListDelete(db, pSrc)
End Sub



/' ------------------------------------------------------------------------- '/
/' ALTER rename and constraint callbacks '/

Private Sub renameTokenFree CDecl Alias "renameTokenFree" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteRenameToken Ptr)
    Dim local0 As SqliteRenameToken Ptr
    Dim local1 As SqliteRenameToken Ptr
    Dim c2fb_temp_0 As SqliteRenameToken Ptr
    Dim c2fb_temp_1 As SqliteRenameToken Ptr
    Dim c2fb_temp_2 As SqliteRenameToken Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    c2fb_temp_0 = arg1
    local1 = c2fb_temp_0
    While local1
        c2fb_temp_2 = local1->pNext
        local0 = c2fb_temp_2
        sqlite3DbFree(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local1))
    c2fb_flow_1:
        c2fb_temp_1 = local0
        local1 = c2fb_temp_1
    Wend
    c2fb_flow_0:
End Sub

Private Sub renameColumnElistNames CDecl Alias "renameColumnElistNames" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Const SqliteExprList Ptr, ByVal arg3 As Const ZString Ptr)
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local1 As Const ZString Ptr
    Dim c2fb_temp_2 As SqliteRenameToken Ptr

    If arg2 Then
        ' C automatic storage declaration
        c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local0 = c2fb_temp_0
        While (-Cast(SQLITE_C_INT, ((local0 < arg2->nExpr))))
            local1 = CPtr(ZString Ptr, arg2->a(local0).zEName)
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg2->a(local0).fg.flags) Shr 0) And Cast(SQLITE_C_UINT, &H3ULL))) = Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso ((-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = sqlite3_stricmp(local1, arg3))))))))) Then
                c2fb_temp_2 = CPtr(SqliteRenameToken Ptr, renameTokenFind(arg0, arg1, CPtr(Const Any Ptr, CPtr(Any Ptr, local1))))
            End If
        c2fb_flow_1:
            c2fb_temp_1 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
        Wend
        c2fb_flow_0:
    End If
End Sub

Private Sub renameColumnIdlistNames CDecl Alias "renameColumnIdlistNames" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Const SqliteIdList Ptr, ByVal arg3 As Const ZString Ptr)
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local1 As Const ZString Ptr
    Dim c2fb_temp_2 As SqliteRenameToken Ptr

    If arg2 Then
        ' C automatic storage declaration
        c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local0 = c2fb_temp_0
        While (-Cast(SQLITE_C_INT, ((local0 < arg2->nId))))
            local1 = arg2->a(local0).zName
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = sqlite3_stricmp(local1, arg3))))) Then
                c2fb_temp_2 = CPtr(SqliteRenameToken Ptr, renameTokenFind(arg0, arg1, CPtr(Const Any Ptr, CPtr(Any Ptr, local1))))
            End If
        c2fb_flow_1:
            c2fb_temp_1 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
        Wend
        c2fb_flow_0:
    End If
End Sub

Private Function renameParseSql CDecl Alias "renameParseSql" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As sqlite3 Ptr, ByVal arg3 As Const ZString Ptr, ByVal arg4 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As sqlite3_uint64
    Dim c2fb_temp_0 As u8 Ptr
    Dim c2fb_temp_1 As UByte
    Dim local2 As SQLITE_C_INT
    Dim c2fb_temp_2 As u8 Ptr
    Dim c2fb_temp_3 As UByte
    Dim c2fb_temp_4 As u8 Ptr
    Dim c2fb_temp_5 As UByte
    Dim c2fb_temp_6 As sqlite3 Ptr Ptr
    Dim c2fb_temp_7 As sqlite3 Ptr
    Dim c2fb_temp_8 As Short Ptr
    Dim c2fb_temp_9 As Short
    Dim c2fb_temp_10 As sqlite3_uint64
    Dim c2fb_temp_11 As sqlite3_uint64 Ptr
    Dim c2fb_temp_12 As sqlite3_uint64
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As sqlite3_uint64 Ptr
    Dim c2fb_temp_15 As sqlite3_uint64
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SQLITE_C_INT
    Dim c2fb_temp_18 As u8 Ptr
    Dim c2fb_temp_19 As UByte

    ' C automatic storage declaration
    ' C automatic storage declaration
    sqlite3ParseObjectInit(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg2))
    If (-Cast(SQLITE_C_INT, ((arg3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, 7ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((sqlite3_strnicmp(arg3, StrPtr(!"CREATE "), Cast(SQLITE_C_INT, 7ULL)) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return sqlite3CorruptError(Cast(SQLITE_C_INT, 1196ULL))
    End If
    If arg4 Then
        c2fb_temp_0 = @(arg2->init.iDb)
        c2fb_temp_1 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
        (*c2fb_temp_0) = Cast(u8, c2fb_temp_1)
        c2fb_temp_1 = Cast(UByte, (*c2fb_temp_0))
    Else
        local2 = sqlite3FindDbName(CPtr(Any Ptr, arg2), arg1)
        ' C unused-parameter annotation
        c2fb_temp_2 = @(arg2->init.iDb)
        c2fb_temp_3 = Cast(UByte, Cast(UByte, local2))
        (*c2fb_temp_2) = Cast(u8, c2fb_temp_3)
        c2fb_temp_3 = Cast(UByte, (*c2fb_temp_2))
    End If
    c2fb_temp_4 = @(arg0->eParseMode)
    c2fb_temp_5 = Cast(UByte, Cast(SQLITE_C_INT, 2ULL))
    (*c2fb_temp_4) = Cast(u8, c2fb_temp_5)
    c2fb_temp_5 = Cast(UByte, (*c2fb_temp_4))
    c2fb_temp_6 = @(arg0->db)
    c2fb_temp_7 = arg2
    (*c2fb_temp_6) = c2fb_temp_7
    c2fb_temp_8 = @(arg0->nQueryLoop)
    c2fb_temp_9 = Cast(Short, Cast(SQLITE_C_INT, 1ULL))
    (*c2fb_temp_8) = c2fb_temp_9
    c2fb_temp_10 = Cast(sqlite3_uint64, arg2->flags)
    local1 = c2fb_temp_10
    ' empty C statement
    c2fb_temp_11 = @(arg2->flags)
    c2fb_temp_12 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, ((*c2fb_temp_11) Or (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, (Cast(SQLITE_C_INT, &H00040ULL))) Shl Cast(SQLITE_C_INT, 32ULL)))))))
    (*c2fb_temp_11) = c2fb_temp_12
    c2fb_temp_13 = Cast(SQLITE_C_INT, sqlite3RunParser(CPtr(Any Ptr, arg0), arg3))
    local0 = c2fb_temp_13
    c2fb_temp_14 = @(arg2->flags)
    c2fb_temp_15 = Cast(sqlite3_uint64, local1)
    (*c2fb_temp_14) = c2fb_temp_15
    If arg2->mallocFailed Then
        c2fb_temp_16 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 7ULL))
        local0 = c2fb_temp_16
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((CPtr(SqliteTable Ptr, arg0->pNewTable) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((CPtr(SqliteIndex Ptr, arg0->pNewIndex) = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((CPtr(SqliteTrigger Ptr, arg0->pNewTrigger) = Cast(SQLITE_C_INT, &O0ULL)))))))))))))) Then
        c2fb_temp_17 = Cast(SQLITE_C_INT, sqlite3CorruptError(Cast(SQLITE_C_INT, 1217ULL)))
        local0 = c2fb_temp_17
    End If
    c2fb_temp_18 = @(arg2->init.iDb)
    c2fb_temp_19 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_18) = Cast(u8, c2fb_temp_19)
    c2fb_temp_19 = Cast(UByte, (*c2fb_temp_18))
    Return local0
End Function

Private Sub renameParseCleanup CDecl Alias "renameParseCleanup" (ByVal arg0 As SqliteParseContext Ptr)
    Dim local0 As sqlite3 Ptr
    Dim local1 As SqliteIndex Ptr
    Dim c2fb_temp_0 As SqliteIndex Ptr
    Dim c2fb_temp_1 As Any Ptr Ptr
    Dim c2fb_temp_2 As SqliteIndex Ptr

    local0 = arg0->db
    ' C automatic storage declaration
    If CPtr(SqliteVdbe Ptr, arg0->pVdbe) Then
        sqlite3VdbeFinalize(CPtr(SqliteVdbe Ptr, arg0->pVdbe))
    End If
    sqlite3DeleteTable(CPtr(Any Ptr, local0), CPtr(Any Ptr, CPtr(SqliteTable Ptr, arg0->pNewTable)))
    Do
        c2fb_temp_0 = CPtr(SqliteIndex Ptr, arg0->pNewIndex)
        local1 = c2fb_temp_0
        If ((-Cast(SQLITE_C_INT, (((c2fb_temp_0) <> Cast(SQLITE_C_INT, &O0ULL))))) = 0) Then Goto c2fb_flow_0
        c2fb_temp_1 = @(arg0->pNewIndex)
        c2fb_temp_2 = local1->pNext
        (*c2fb_temp_1) = CPtr(Any Ptr, c2fb_temp_2)
        c2fb_temp_2 = CPtr(SqliteIndex Ptr, (*c2fb_temp_1))
        sqlite3FreeIndex(CPtr(Any Ptr, local0), CPtr(Any Ptr, local1))
    c2fb_flow_1:
    Loop
    c2fb_flow_0:
    sqlite3DeleteTrigger(CPtr(Any Ptr, local0), CPtr(Any Ptr, CPtr(SqliteTrigger Ptr, arg0->pNewTrigger)))
    sqlite3DbFree(CPtr(Any Ptr, local0), CPtr(Any Ptr, arg0->zErrMsg))
    renameTokenFree(local0, arg0->pRename)
    sqlite3ParseObjectReset(CPtr(Any Ptr, arg0))
End Sub

Private Function renameQuotefixExprCb CDecl Alias "renameQuotefixExprCb" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteRenameToken Ptr

    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 118ULL)))))) AndAlso (Cast(SQLITE_C_UINT, (arg1->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H000080ULL))))))))) Then
        c2fb_temp_0 = CPtr(SqliteRenameToken Ptr, renameTokenFind(arg0->pParse, arg0->u.pRename, CPtr(Const Any Ptr, CPtr(Any Ptr, arg1))))
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function getConstraintToken CDecl Alias "getConstraintToken" (ByVal arg0 As Const UByte Ptr, ByVal arg1 As SQLITE_C_INT Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT Ptr
    Dim c2fb_temp_8 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    Do
        c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(sqlite3_int64, (Cast(sqlite3_int64, local0) + sqlite3GetToken(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(arg0[local0]))), CPtr(SQLITE_C_INT Ptr, @(local1))))))
        local0 = c2fb_temp_0
    c2fb_flow_1:
    Loop While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 184ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 185ULL)))))))))
    c2fb_flow_0:
    c2fb_temp_1 = @((*arg1))
    c2fb_temp_2 = Cast(SQLITE_C_INT, local1)
    (*c2fb_temp_1) = c2fb_temp_2
    If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 22ULL))))) Then
        local2 = Cast(SQLITE_C_INT, 1ULL)
        While (-Cast(SQLITE_C_INT, ((local2 > Cast(SQLITE_C_INT, &O0ULL)))))
            c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(sqlite3_int64, (Cast(sqlite3_int64, local0) + sqlite3GetToken(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(arg0[local0]))), CPtr(SQLITE_C_INT Ptr, @(local1))))))
            local0 = c2fb_temp_3
            If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 22ULL))))) Then
                c2fb_temp_4 = local2
                local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_4 + 1)))
            Else
                If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 23ULL))))) Then
                    c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 22ULL))
                    local1 = c2fb_temp_5
                    c2fb_temp_6 = local2
                    local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 - 1)))
                Else
                    If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 186ULL))))) Then
                        Goto c2fb_flow_2
                    End If
                End If
            End If
        c2fb_flow_3:
        Wend
        c2fb_flow_2:
    End If
    c2fb_temp_7 = @((*arg1))
    c2fb_temp_8 = Cast(SQLITE_C_INT, local1)
    (*c2fb_temp_7) = c2fb_temp_8
    Return local0
End Function

Private Sub dropColumnFunc CDecl Alias "dropColumnFunc" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteVdbeMem Ptr Ptr)
    Dim local0 As sqlite3 Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As Const ZString Ptr
    Dim local3 As SQLITE_C_INT
    Dim local4 As Const ZString Ptr
    Dim local5 As SQLITE_C_INT
    Dim local6 As SqliteParseContext
    Dim local7 As SqliteRenameToken Ptr
    Dim local8 As SqliteTable Ptr
    Dim local9 As Const ZString Ptr
    Dim local10 As ZString Ptr
    Dim local11 As c2fb_callback_3
    Dim c2fb_temp_0 As SqliteAuthorizerCallback Ptr
    Dim c2fb_temp_1 As c2fb_callback_3
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SqliteTable Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim local12 As SqliteRenameToken Ptr
    Dim c2fb_temp_5 As SqliteRenameToken Ptr
    Dim c2fb_temp_6 As SqliteRenameToken Ptr
    Dim c2fb_temp_7 As Const ZString Ptr
    Dim local13 As SQLITE_C_INT
    Dim c2fb_temp_8 As SqliteRenameToken Ptr
    Dim c2fb_temp_9 As UByte Ptr Ptr
    Dim c2fb_temp_10 As Const ZString Ptr
    Dim c2fb_temp_11 As UByte Ptr Ptr
    Dim c2fb_temp_12 As Const ZString Ptr
    Dim c2fb_temp_13 As Const ZString Ptr
    Dim c2fb_temp_14 As ZString Ptr
    Dim c2fb_temp_15 As SqliteAuthorizerCallback Ptr
    Dim c2fb_temp_16 As c2fb_callback_3

    local0 = CPtr(sqlite3 Ptr, sqlite3_context_db_handle(CPtr(Any Ptr, arg0)))
    local1 = sqlite3_value_int(CPtr(Any Ptr, arg2[Cast(SQLITE_C_INT, &O0ULL)]))
    local2 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(CPtr(Any Ptr, arg2[Cast(SQLITE_C_INT, 1ULL)]))))
    local3 = sqlite3_value_int(CPtr(Any Ptr, arg2[Cast(SQLITE_C_INT, 2ULL)]))
    local4 = CPtr(ZString Ptr, local0->aDb(local1).zDbSName)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local10 = Cast(SQLITE_C_INT, &O0ULL)
    local11 = CPtr(c2fb_callback_3, local0->xAuth)
    c2fb_temp_0 = @(local0->xAuth)
    c2fb_temp_1 = CPtr(c2fb_callback_3, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_0) = Cast(SqliteAuthorizerCallback, c2fb_temp_1)
    c2fb_temp_1 = CPtr(c2fb_callback_3, (*c2fb_temp_0))
    ' C unused-parameter annotation
    c2fb_temp_2 = Cast(SQLITE_C_INT, renameParseSql(CPtr(SqliteParseContext Ptr, @(local6)), local4, local0, local2, (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 1ULL)))))))
    local5 = c2fb_temp_2
    If (-Cast(SQLITE_C_INT, ((local5 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        Goto c2fb_label_0
    End If
    c2fb_temp_3 = CPtr(SqliteTable Ptr, local6.pNewTable)
    local8 = c2fb_temp_3
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local8->nCol) = Cast(SQLITE_C_INT, 1ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local3 >= Cast(SQLITE_C_INT, local8->nCol))))))))) Then
        c2fb_temp_4 = Cast(SQLITE_C_INT, sqlite3CorruptError(Cast(SQLITE_C_INT, 2232ULL)))
        local5 = c2fb_temp_4
        Goto c2fb_label_0
    End If
    If (-Cast(SQLITE_C_INT, ((local3 < Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local8->nCol) - Cast(SQLITE_C_INT, 1ULL))))))) Then
        ' C automatic storage declaration
        c2fb_temp_5 = CPtr(SqliteRenameToken Ptr, renameTokenFind(CPtr(SqliteParseContext Ptr, @(local6)), Cast(SQLITE_C_INT, &O0ULL), CPtr(Const Any Ptr, CPtr(Any Ptr, local8->aCol[local3].zCnName))))
        local7 = c2fb_temp_5
        c2fb_temp_6 = CPtr(SqliteRenameToken Ptr, renameTokenFind(CPtr(SqliteParseContext Ptr, @(local6)), Cast(SQLITE_C_INT, &O0ULL), CPtr(Const Any Ptr, CPtr(Any Ptr, local8->aCol[Cast(SQLITE_C_INT, (local3 + Cast(SQLITE_C_INT, 1ULL)))].zCnName))))
        local12 = c2fb_temp_6
        c2fb_temp_7 = CPtr(Const ZString Ptr, CPtr(Const ZString Ptr, local12->t.z))
        local9 = c2fb_temp_7
    Else
        ' C automatic storage declaration
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        c2fb_temp_8 = CPtr(SqliteRenameToken Ptr, renameTokenFind(CPtr(SqliteParseContext Ptr, @(local6)), Cast(SQLITE_C_INT, &O0ULL), CPtr(Const Any Ptr, CPtr(Any Ptr, local8->aCol[Cast(SQLITE_C_INT, (local3 - Cast(SQLITE_C_INT, 1ULL)))].zCnName))))
        local7 = c2fb_temp_8
        Do
            c2fb_temp_9 = @(local7->t.z)
            c2fb_temp_10 = CPtr(Const ZString Ptr, (CPtr(Const Byte Ptr, (*c2fb_temp_9)) + getConstraintToken(CPtr(Const UByte Ptr, CPtr(Const ZString Ptr, local7->t.z)), CPtr(SQLITE_C_INT Ptr, @(local13)))))
            (*c2fb_temp_9) = CPtr(UByte Ptr, c2fb_temp_10)
            c2fb_temp_10 = CPtr(Const ZString Ptr, (*c2fb_temp_9))
        c2fb_flow_1:
        Loop While (-Cast(SQLITE_C_INT, ((local13 <> Cast(SQLITE_C_INT, 25ULL)))))
        c2fb_flow_0:
        c2fb_temp_11 = @(local7->t.z)
        c2fb_temp_12 = (*c2fb_temp_11)
        (*c2fb_temp_11) = CPtr(UByte Ptr, CULngInt(c2fb_temp_12) - 1)
        c2fb_temp_13 = CPtr(Const ZString Ptr, CPtr(Byte Ptr, @(CPtr(Const Byte Ptr, local2)[local8->u.tab.addColOffset])))
        local9 = c2fb_temp_13
    End If
    c2fb_temp_14 = CPtr(ZString Ptr, sqlite3MPrintf(CPtr(Any Ptr, local0), StrPtr(!"%.*s%s"), (CPtr(Const Byte Ptr, CPtr(Const ZString Ptr, local7->t.z)) - CPtr(Const Byte Ptr, local2)), local2, local9))
    local10 = c2fb_temp_14
    sqlite3_result_text(CPtr(Any Ptr, arg0), CPtr(Const ZString Ptr, local10), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), CPtr(Any Ptr, (CPtr(c2fb_callback_8, Cast(Integer, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))))))
    sqlite3_free(CPtr(Any Ptr, local10))
    c2fb_label_0:
    renameParseCleanup(CPtr(SqliteParseContext Ptr, @(local6)))
    c2fb_temp_15 = @(local0->xAuth)
    c2fb_temp_16 = local11
    (*c2fb_temp_15) = Cast(SqliteAuthorizerCallback, c2fb_temp_16)
    c2fb_temp_16 = CPtr(c2fb_callback_3, (*c2fb_temp_15))
    If (-Cast(SQLITE_C_INT, ((local5 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3_result_error_code(CPtr(Any Ptr, arg0), local5)
    End If
End Sub

Private Function getWhitespace CDecl Alias "getWhitespace" (ByVal arg0 As Const UByte Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    While Cast(SQLITE_C_INT, 1ULL)
        local1 = Cast(SQLITE_C_INT, &O0ULL)
        local2 = sqlite3GetToken(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(arg0[local0]))), CPtr(SQLITE_C_INT Ptr, @(local1)))
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, 184ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, 185ULL))))))))) Then
            Goto c2fb_flow_0
        End If
        c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local0 + local2)))
        local0 = c2fb_temp_0
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    Return local0
End Function

Private Function getConstraint CDecl Alias "getConstraint" (ByVal arg0 As Const UByte Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, 133ULL))))) Then
        c2fb_temp_0 = Cast(SQLITE_C_INT, getConstraint(arg0, Cast(SQLITE_C_INT, &O0ULL)))
        local0 = c2fb_temp_0
        c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local0 + getConstraintToken(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(arg0[local0]))), CPtr(SQLITE_C_INT Ptr, @(arg1))))))
        local0 = c2fb_temp_1
    End If
    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, 126ULL))))) Then
        c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local0 + getConstraintToken(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(arg0[local0]))), CPtr(SQLITE_C_INT Ptr, @(local1))))))
        local0 = c2fb_temp_2
    End If
    While Cast(SQLITE_C_INT, 1ULL)
        local2 = getConstraintToken(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(arg0[local0]))), CPtr(SQLITE_C_INT Ptr, @(local1)))
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 120ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 123ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 19ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 124ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 125ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 121ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 114ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 126ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 133ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 23ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 25ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 186ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 24ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 96ULL))))))))) Then
            Goto c2fb_flow_0
        End If
        c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local0 + local2)))
        local0 = c2fb_temp_3
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    Return local0
End Function

Private Function quotedCompare CDecl Alias "quotedCompare" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As Const UByte Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As Const UByte Ptr, ByVal arg5 As SQLITE_C_INT Ptr) As SQLITE_C_INT
    Dim local0 As ZString Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As ZString Ptr
    Dim c2fb_temp_3 As Any Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, 186ULL))))) Then
        c2fb_temp_0 = @((*arg5))
        c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
        (*c2fb_temp_0) = c2fb_temp_1
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_2 = CPtr(ZString Ptr, CPtr(Any Ptr, sqlite3MallocZero(Cast(SQLITE_C_INT, (arg3 + Cast(SQLITE_C_INT, 1ULL))))))
    local0 = c2fb_temp_2
    If (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3_result_error_nomem(CPtr(Any Ptr, arg0))
        Return Cast(SQLITE_C_INT, 7ULL)
    End If
    c2fb_temp_3 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, local0), CPtr(Const Any Ptr, arg2), arg3))
    sqlite3Dequote(local0)
    c2fb_temp_4 = @((*arg5))
    c2fb_temp_5 = Cast(SQLITE_C_INT, sqlite3_stricmp(CPtr(Const ZString Ptr, local0), CPtr(Const ZString Ptr, arg4)))
    (*c2fb_temp_4) = c2fb_temp_5
    sqlite3_free(CPtr(Any Ptr, local0))
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function skipCreateTable CDecl Alias "skipCreateTable" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As Const UByte Ptr, ByVal arg2 As SQLITE_C_INT Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    While Cast(SQLITE_C_INT, 1ULL)
        local1 = Cast(SQLITE_C_INT, &O0ULL)
        c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(sqlite3_int64, (Cast(sqlite3_int64, local0) + sqlite3GetToken(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(arg1[local0]))), CPtr(SQLITE_C_INT Ptr, @(local1))))))
        local0 = c2fb_temp_0
        If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 22ULL))))) Then
            Goto c2fb_flow_0
        End If
        If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 186ULL))))) Then
            sqlite3_result_error_code(CPtr(Any Ptr, arg0), sqlite3CorruptError(Cast(SQLITE_C_INT, 2550ULL)))
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    c2fb_temp_1 = @((*arg2))
    c2fb_temp_2 = Cast(SQLITE_C_INT, local0)
    (*c2fb_temp_1) = c2fb_temp_2
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Sub dropConstraintFunc CDecl Alias "dropConstraintFunc" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteVdbeMem Ptr Ptr)
    Dim local0 As Const UByte Ptr
    Dim local1 As Const UByte Ptr
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim local6 As SQLITE_C_INT
    Dim local7 As ZString Ptr
    Dim local8 As SQLITE_C_INT
    Dim local9 As sqlite3 Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As Const UByte Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim local10 As SQLITE_C_INT
    Dim local11 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim local12 As Const ZString Ptr
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As Const ZString Ptr
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As sqlite3 Ptr
    Dim c2fb_temp_20 As ZString Ptr

    local0 = CPtr(Const UByte Ptr, sqlite3_value_text(CPtr(Any Ptr, arg2[Cast(SQLITE_C_INT, &O0ULL)])))
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    local2 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))
    ' C automatic storage declaration
    local4 = Cast(SQLITE_C_INT, &O0ULL)
    local5 = Cast(SQLITE_C_INT, &O0ULL)
    local6 = Cast(SQLITE_C_INT, &O0ULL)
    local7 = Cast(SQLITE_C_INT, &O0ULL)
    local8 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    If skipCreateTable(arg0, local0, CPtr(SQLITE_C_INT Ptr, @(local4))) Then
        Return
    End If
    If (-Cast(SQLITE_C_INT, ((sqlite3_value_type(CPtr(Any Ptr, arg2[Cast(SQLITE_C_INT, 1ULL)])) = Cast(SQLITE_C_INT, 1ULL))))) Then
        c2fb_temp_0 = Cast(SQLITE_C_INT, sqlite3_value_int(CPtr(Any Ptr, arg2[Cast(SQLITE_C_INT, 1ULL)])))
        local2 = c2fb_temp_0
    Else
        c2fb_temp_1 = CPtr(Const UByte Ptr, sqlite3_value_text(CPtr(Any Ptr, arg2[Cast(SQLITE_C_INT, 1ULL)])))
        local1 = c2fb_temp_1
    End If
    c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local3 = c2fb_temp_2
    While (-Cast(SQLITE_C_INT, ((local6 = Cast(SQLITE_C_INT, &O0ULL)))))
        While Cast(SQLITE_C_INT, 1ULL)
            c2fb_temp_4 = Cast(SQLITE_C_INT, local4)
            local5 = c2fb_temp_4
            c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local4 + getConstraintToken(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0[local4]))), CPtr(SQLITE_C_INT Ptr, @(local8))))))
            local4 = c2fb_temp_5
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, 120ULL))))) AndAlso ((-Cast(SQLITE_C_INT, ((local1 OrElse (-Cast(SQLITE_C_INT, ((local2 = local3))))))))))))) Then
                local10 = Cast(SQLITE_C_INT, &O0ULL)
                local11 = Cast(SQLITE_C_INT, 1ULL)
                c2fb_temp_6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local4 + getWhitespace(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0[local4])))))))
                local4 = c2fb_temp_6
                c2fb_temp_7 = Cast(SQLITE_C_INT, getConstraintToken(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0[local4]))), CPtr(SQLITE_C_INT Ptr, @(local8))))
                local10 = c2fb_temp_7
                If local1 Then
                    If quotedCompare(arg0, local8, CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0[local4]))), local10, local1, CPtr(SQLITE_C_INT Ptr, @(local11))) Then
                        Return
                    End If
                End If
                c2fb_temp_8 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local4 + local10)))
                local4 = c2fb_temp_8
                c2fb_temp_9 = Cast(SQLITE_C_INT, getConstraintToken(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0[local4]))), CPtr(SQLITE_C_INT Ptr, @(local8))))
                local10 = c2fb_temp_9
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, 120ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, 121ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, 114ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, 25ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, 23ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, 96ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, 24ULL))))))))) Then
                    c2fb_temp_10 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 125ULL))
                    local8 = c2fb_temp_10
                Else
                    c2fb_temp_11 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local4 + local10)))
                    local4 = c2fb_temp_11
                    c2fb_temp_12 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local4 + getConstraint(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0[local4]))), local8))))
                    local4 = c2fb_temp_12
                End If
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local11 = Cast(SQLITE_C_INT, &O0ULL))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local2 >= Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, 19ULL)))))))))))))) Then
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local8 <> Cast(SQLITE_C_INT, 19ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local8 <> Cast(SQLITE_C_INT, 125ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((local8 <> Cast(SQLITE_C_INT, 126ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((local8 <> Cast(SQLITE_C_INT, 133ULL))))))))) Then
                        errorMPrintf(arg0, StrPtr(!"constraint may not be dropped: %s"), local1)
                        Return
                    End If
                    c2fb_temp_13 = Cast(SQLITE_C_INT, local4)
                    local6 = c2fb_temp_13
                    Goto c2fb_flow_2
                End If
            Else
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, 19ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local2 = local3)))))))) Then
                    c2fb_temp_14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local4 + getConstraint(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0[local4]))), Cast(SQLITE_C_INT, &O0ULL)))))
                    local6 = c2fb_temp_14
                    Goto c2fb_flow_2
                Else
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, 23ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, 186ULL))))))))) Then
                        c2fb_temp_15 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
                        local6 = c2fb_temp_15
                        Goto c2fb_flow_2
                    Else
                        If (-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, 25ULL))))) Then
                            Goto c2fb_flow_2
                        End If
                    End If
                End If
            End If
        c2fb_flow_3:
        Wend
        c2fb_flow_2:
    c2fb_flow_1:
        c2fb_temp_3 = local3
        local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_3 + 1)))
    Wend
    c2fb_flow_0:
    If (-Cast(SQLITE_C_INT, ((local6 <= Cast(SQLITE_C_INT, &O0ULL))))) Then
        If local1 Then
            errorMPrintf(arg0, StrPtr(!"no such constraint: %s"), local1)
        Else
            sqlite3_result_text(CPtr(Any Ptr, arg0), CPtr(Const ZString Ptr, local0), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), CPtr(Any Ptr, (CPtr(c2fb_callback_8, Cast(Integer, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))))))
        End If
    Else
        local12 = StrPtr(!" ")
        c2fb_temp_16 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local6 + getWhitespace(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0[local6])))))))
        local6 = c2fb_temp_16
        sqlite3GetToken(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0[local6]))), CPtr(SQLITE_C_INT Ptr, @(local8)))
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, 23ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, 25ULL))))))))) Then
            c2fb_temp_17 = StrPtr(!"")
            local12 = c2fb_temp_17
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0[Cast(SQLITE_C_INT, (local5 - Cast(SQLITE_C_INT, 1ULL)))]) = Cast(SQLITE_C_INT, 44))))) Then
                c2fb_temp_18 = local5
                local5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_18 - 1)))
            End If
        End If
        c2fb_temp_19 = CPtr(sqlite3 Ptr, sqlite3_context_db_handle(CPtr(Any Ptr, arg0)))
        local9 = c2fb_temp_19
        c2fb_temp_20 = CPtr(ZString Ptr, sqlite3MPrintf(CPtr(Any Ptr, local9), StrPtr(!"%.*s%s%s"), local5, local0, local12, CPtr(UByte Ptr, @(local0[local6]))))
        local7 = c2fb_temp_20
        sqlite3_result_text(CPtr(Any Ptr, arg0), CPtr(Const ZString Ptr, local7), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), CPtr(Any Ptr, (CPtr(Any Ptr, ProcPtr(sqlite3RowSetClear)))))
    End If
End Sub

/' ------------------------------------------------------------------------- '/
/' ALTER token-list lookup and string-formatting adapters '/

Private Function renameTokenFind CDecl Alias "renameTokenFind" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pContextArgument As Any Ptr, _
    ByVal pPointerArgument As Const Any Ptr _
) As SqliteRenameToken Ptr
    Dim pPrevious As SqliteRenameToken Ptr = 0
    Dim pToken As SqliteRenameToken Ptr
    Dim pContext As SqliteRenameContext Ptr = 0

    If pParse = 0 OrElse pPointerArgument = 0 Then Return 0
    If pContextArgument Then _
        pContext = CPtr(SqliteRenameContext Ptr, pContextArgument)

    pToken = pParse->pRename
    While pToken
        If pToken->p = CPtr(Any Ptr, pPointerArgument) Then
            If pContext Then
                If pPrevious Then
                    pPrevious->pNext = pToken->pNext
                Else
                    pParse->pRename = pToken->pNext
                End If
                pToken->pNext = pContext->pList
                pContext->pList = pToken
                pContext->nList += 1
            End If
            Return pToken
        End If
        pPrevious = pToken
        pToken = pToken->pNext
    Wend

    Return 0
End Function

Private Sub errorMPrintf CDecl Alias "errorMPrintf" ( _
    ByVal pContext As Any Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ByVal zArgument As Const ZString Ptr _
)
    ' SQLite's two ALTER constraint call sites pass one string for one %s.
    alterErrorMessage(pContext, zFormat, zArgument)
End Sub



/' ------------------------------------------------------------------------- '/
/' ALTER rename callbacks and built-in registration '/
/' ------------------------------------------------------------------------- '/

/' Rename helper closure used by the C static callbacks '/

Private Sub renameWalkWith CDecl Alias "renameWalkWith" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteSelect Ptr)
    Dim local0 As SqliteWithRecord Ptr
    Dim local1 As SqliteParseContext Ptr
    Dim local2 As SQLITE_C_INT
    Dim local3 As SqliteWithRecord Ptr
    Dim c2fb_temp_0 As SqliteWithRecord Ptr
    Dim c2fb_temp_1 As SqliteWithRecord Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim local4 As SqliteSelect Ptr
    Dim local5 As SqliteNameContext
    Dim c2fb_temp_4 As Any Ptr
    Dim c2fb_temp_5 As SqliteParseContext Ptr Ptr
    Dim c2fb_temp_6 As SqliteParseContext Ptr
    Dim c2fb_temp_7 As Any Ptr Ptr
    Dim c2fb_temp_8 As SqliteWithRecord Ptr

    local0 = CPtr(SqliteWithRecord Ptr, arg1->pWith)
    If local0 Then
        local1 = arg0->pParse
        ' C automatic storage declaration
        local3 = Cast(SQLITE_C_INT, &O0ULL)
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local0->a(Cast(SQLITE_C_INT, &O0ULL)).pSelect->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000040ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            c2fb_temp_0 = CPtr(SqliteWithRecord Ptr, sqlite3WithDup(CPtr(Any Ptr, local1->db), CPtr(Any Ptr, local0)))
            local3 = c2fb_temp_0
            c2fb_temp_1 = CPtr(SqliteWithRecord Ptr, sqlite3WithPush(CPtr(Any Ptr, local1), CPtr(Any Ptr, local3), Cast(SQLITE_C_INT, 1ULL)))
            local3 = c2fb_temp_1
        End If
        c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local2 = c2fb_temp_2
        While (-Cast(SQLITE_C_INT, ((local2 < local0->nCte))))
            local4 = local0->a(local2).pSelect
            ' C automatic storage declaration
            c2fb_temp_4 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local5))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteNameContext))))
            c2fb_temp_5 = @(local5.pParse)
            c2fb_temp_6 = local1
            (*c2fb_temp_5) = c2fb_temp_6
            If local3 Then
                sqlite3SelectPrep(CPtr(Any Ptr, local5.pParse), CPtr(Any Ptr, local4), CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local5))))
            End If
            If local5.pParse->db->mallocFailed Then
                Return
            End If
            sqlite3WalkSelect(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local4))
            sqlite3RenameExprlistUnmap(CPtr(Any Ptr, local1), CPtr(Any Ptr, local0->a(local2).pCols))
        c2fb_flow_1:
            c2fb_temp_3 = local2
            local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_3 + 1)))
        Wend
        c2fb_flow_0:
        If (-Cast(SQLITE_C_INT, ((local3 AndAlso (-Cast(SQLITE_C_INT, ((CPtr(SqliteWithRecord Ptr, local1->pWith) = local3)))))))) Then
            c2fb_temp_7 = @(local1->pWith)
            c2fb_temp_8 = CPtr(SqliteWithRecord Ptr, local3->pOuter)
            (*c2fb_temp_7) = CPtr(Any Ptr, c2fb_temp_8)
            c2fb_temp_8 = CPtr(SqliteWithRecord Ptr, (*c2fb_temp_7))
        End If
    End If
End Sub

Private Function renameColumnSelectCb CDecl Alias "renameColumnSelectCb" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteSelect Ptr) As SQLITE_C_INT
    If Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0200000ULL) Or Cast(SQLITE_C_INT, &H4000000ULL))))))) Then
        ' empty C statement
        ' empty C statement
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    renameWalkWith(arg0, arg1)
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Sub renameColumnParseError CDecl Alias "renameColumnParseError" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SqliteVdbeMem Ptr, ByVal arg3 As SqliteVdbeMem Ptr, ByVal arg4 As SqliteParseContext Ptr)
    Dim local0 As Const ZString Ptr
    Dim local1 As Const ZString Ptr
    Dim local2 As ZString Ptr
    Dim c2fb_temp_0 As ZString Ptr

    local0 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(arg2)))
    local1 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(arg3)))
    ' C automatic storage declaration
    c2fb_temp_0 = CPtr(ZString Ptr, sqlite3MPrintf(CPtr(Any Ptr, arg4->db), StrPtr(!"error in %s %s%s%s: %s"), local0, local1, (IIf(CPtr(Const Byte Ptr, arg1)[Cast(SQLITE_C_INT, &O0ULL)], StrPtr(!" "), StrPtr(!""))), arg1, arg4->zErrMsg))
    local2 = c2fb_temp_0
    sqlite3_result_error(CPtr(Any Ptr, arg0), CPtr(Const ZString Ptr, local2), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
    sqlite3DbFree(CPtr(Any Ptr, arg4->db), CPtr(Any Ptr, local2))
End Sub

Private Sub renameSetENames CDecl Alias "renameSetENames" (ByVal arg0 As SqliteExprList Ptr, ByVal arg1 As SQLITE_C_INT)
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT

    ' C unused-parameter annotation
    If arg0 Then
        ' C automatic storage declaration
        c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local0 = c2fb_temp_0
        While (-Cast(SQLITE_C_INT, ((local0 < arg0->nExpr))))
            ' C unused-parameter annotation
            c2fb_temp_2 = @(arg0->a(local0).fg.flags)
            c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg1 And Cast(SQLITE_C_INT, &H3ULL))))
            c2fb_temp_3 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_3) And Cast(SQLITE_C_UINT, &H3ULL)))
            (*c2fb_temp_2) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_2)) And Not(Cast(SQLITE_C_UINT, &H3ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_3) And Cast(SQLITE_C_UINT, &H3ULL)) Shl 0)))
            c2fb_temp_3 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_3) And Cast(SQLITE_C_UINT, &H3ULL)))
        c2fb_flow_1:
            c2fb_temp_1 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
        Wend
        c2fb_flow_0:
    End If
End Sub

Private Sub renameWalkTrigger CDecl Alias "renameWalkTrigger" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteTrigger Ptr)
    Dim local0 As SqliteTriggerStep Ptr
    Dim c2fb_temp_0 As SqliteTriggerStep Ptr
    Dim c2fb_temp_1 As SqliteTriggerStep Ptr
    Dim local1 As SqliteUpsert Ptr
    Dim local2 As SQLITE_C_INT
    Dim local3 As SqliteSrcListRecord Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT

    ' C automatic storage declaration
    sqlite3WalkExpr(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg1->pWhen)))
    c2fb_temp_0 = arg1->step_list
    local0 = c2fb_temp_0
    While local0
        sqlite3WalkSelect(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteSelect Ptr, local0->pSelect)))
        sqlite3WalkExpr(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local0->pWhere)))
        sqlite3WalkExprList(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, local0->pExprList)))
        If CPtr(SqliteUpsert Ptr, local0->pUpsert) Then
            local1 = CPtr(SqliteUpsert Ptr, local0->pUpsert)
            sqlite3WalkExprList(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, local1->pUpsertTarget)))
            sqlite3WalkExprList(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, local1->pUpsertSet)))
            sqlite3WalkExpr(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local1->pUpsertWhere)))
            sqlite3WalkExpr(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local1->pUpsertTargetWhere)))
        End If
        If CPtr(SqliteSrcListRecord Ptr, local0->pSrc) Then
            ' C automatic storage declaration
            local3 = CPtr(SqliteSrcListRecord Ptr, local0->pSrc)
            c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local2 = c2fb_temp_2
            While (-Cast(SQLITE_C_INT, ((local2 < local3->nSrc))))
                If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local3->a(local2).fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                    ' C unused-parameter annotation
                    sqlite3WalkSelect(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local3->a(local2).u4.pSubq->pSelect))
                End If
            c2fb_flow_3:
                c2fb_temp_3 = local2
                local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_3 + 1)))
            Wend
            c2fb_flow_2:
        End If
    c2fb_flow_1:
        c2fb_temp_1 = local0->pNext
        local0 = c2fb_temp_1
    Wend
    c2fb_flow_0:
End Sub

Private Function renameResolveTrigger CDecl Alias "renameResolveTrigger" (ByVal arg0 As SqliteParseContext Ptr) As SQLITE_C_INT
    Dim local0 As sqlite3 Ptr
    Dim local1 As SqliteTrigger Ptr
    Dim local2 As SqliteTriggerStep Ptr
    Dim local3 As SqliteNameContext
    Dim local4 As SQLITE_C_INT
    Dim c2fb_temp_0 As Any Ptr
    Dim c2fb_temp_1 As SqliteParseContext Ptr Ptr
    Dim c2fb_temp_2 As SqliteParseContext Ptr
    Dim c2fb_temp_3 As SqliteTable Ptr Ptr
    Dim c2fb_temp_4 As SqliteTable Ptr
    Dim c2fb_temp_5 As u8 Ptr
    Dim c2fb_temp_6 As UByte
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SqliteTriggerStep Ptr
    Dim c2fb_temp_10 As SqliteTriggerStep Ptr
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim local5 As SqliteSrcListRecord Ptr
    Dim local6 As SqliteSelect Ptr
    Dim c2fb_temp_12 As Any Ptr Ptr
    Dim c2fb_temp_13 As SqliteExprList Ptr
    Dim c2fb_temp_14 As SqliteSrcListRecord Ptr
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_18 As SqliteExprList Ptr
    Dim c2fb_temp_19 As SqliteSrcList Ptr Ptr
    Dim c2fb_temp_20 As SqliteSrcListRecord Ptr
    Dim local7 As SQLITE_C_INT
    Dim c2fb_temp_21 As SQLITE_C_INT
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim local8 As SqliteSrcItem Ptr
    Dim c2fb_temp_23 As SQLITE_C_INT
    Dim c2fb_temp_24 As SqliteSrcList Ptr Ptr
    Dim c2fb_temp_25 As SqliteSrcListRecord Ptr
    Dim c2fb_temp_26 As SQLITE_C_INT
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim local9 As SqliteUpsert Ptr
    Dim c2fb_temp_28 As Any Ptr Ptr
    Dim c2fb_temp_29 As SqliteSrcListRecord Ptr
    Dim c2fb_temp_30 As SqliteUpsert Ptr Ptr
    Dim c2fb_temp_31 As SqliteUpsert Ptr
    Dim c2fb_temp_32 As SQLITE_C_INT Ptr
    Dim c2fb_temp_33 As SQLITE_C_INT
    Dim c2fb_temp_34 As SQLITE_C_INT
    Dim local10 As SqliteExprList Ptr
    Dim c2fb_temp_35 As SQLITE_C_INT
    Dim c2fb_temp_36 As SQLITE_C_INT
    Dim c2fb_temp_37 As SQLITE_C_INT
    Dim c2fb_temp_38 As SQLITE_C_INT Ptr
    Dim c2fb_temp_39 As SQLITE_C_INT
    Dim c2fb_temp_40 As SqliteSrcList Ptr Ptr
    Dim c2fb_temp_41 As SqliteSrcListRecord Ptr
    Dim c2fb_temp_42 As SQLITE_C_INT

    local0 = arg0->db
    local1 = CPtr(SqliteTrigger Ptr, arg0->pNewTrigger)
    ' C automatic storage declaration
    ' C automatic storage declaration
    local4 = Cast(SQLITE_C_INT, &O0ULL)
    c2fb_temp_0 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local3))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteNameContext))))
    c2fb_temp_1 = @(local3.pParse)
    c2fb_temp_2 = arg0
    (*c2fb_temp_1) = c2fb_temp_2
    ' C unused-parameter annotation
    c2fb_temp_3 = @(arg0->pTriggerTab)
    c2fb_temp_4 = CPtr(SqliteTable Ptr, sqlite3FindTable(CPtr(Any Ptr, local0), CPtr(Const ZString Ptr, local1->table), CPtr(Const ZString Ptr, CPtr(ZString Ptr, local0->aDb(sqlite3SchemaToIndex(CPtr(Any Ptr, local0), CPtr(Any Ptr, CPtr(SqliteSchema Ptr, local1->pTabSchema)))).zDbSName))))
    (*c2fb_temp_3) = c2fb_temp_4
    c2fb_temp_5 = @(arg0->eTriggerOp)
    c2fb_temp_6 = Cast(UByte, local1->op)
    (*c2fb_temp_5) = Cast(u8, c2fb_temp_6)
    c2fb_temp_6 = Cast(UByte, (*c2fb_temp_5))
    If (arg0->pTriggerTab) Then
        c2fb_temp_7 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, ((sqlite3ViewGetColumnNames(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg0->pTriggerTab)) <> Cast(SQLITE_C_INT, &O0ULL))))))
        local4 = c2fb_temp_7
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso CPtr(SqliteExpr Ptr, local1->pWhen))))) Then
        c2fb_temp_8 = Cast(SQLITE_C_INT, sqlite3ResolveExprNames(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local3))), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local1->pWhen))))
        local4 = c2fb_temp_8
    End If
    c2fb_temp_9 = local1->step_list
    local2 = c2fb_temp_9
    While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso local2))))
        If CPtr(SqliteSelect Ptr, local2->pSelect) Then
            sqlite3SelectPrep(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteSelect Ptr, local2->pSelect)), CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local3))))
            If arg0->nErr Then
                c2fb_temp_11 = Cast(SQLITE_C_INT, arg0->rc)
                local4 = c2fb_temp_11
            End If
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso CPtr(SqliteSrcListRecord Ptr, local2->pSrc))))) Then
            local5 = CPtr(SqliteSrcListRecord Ptr, sqlite3SrcListDup(CPtr(Any Ptr, local0), CPtr(Any Ptr, CPtr(SqliteSrcListRecord Ptr, local2->pSrc)), Cast(SQLITE_C_INT, &O0ULL)))
            If local5 Then
                local6 = CPtr(SqliteSelect Ptr, sqlite3SelectNew(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, local2->pExprList)), CPtr(Any Ptr, local5), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)))
                If (-Cast(SQLITE_C_INT, ((local6 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_12 = @(local2->pExprList)
                    c2fb_temp_13 = CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                    (*c2fb_temp_12) = CPtr(Any Ptr, c2fb_temp_13)
                    c2fb_temp_13 = CPtr(SqliteExprList Ptr, (*c2fb_temp_12))
                    c2fb_temp_14 = CPtr(SqliteSrcListRecord Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                    local5 = c2fb_temp_14
                    c2fb_temp_15 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 7ULL))
                    local4 = c2fb_temp_15
                Else
                    renameSetENames(CPtr(SqliteExprList Ptr, local2->pExprList), Cast(SQLITE_C_INT, 1ULL))
                    sqlite3SelectPrep(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local6), Cast(SQLITE_C_INT, &O0ULL))
                    renameSetENames(CPtr(SqliteExprList Ptr, local2->pExprList), Cast(SQLITE_C_INT, &O0ULL))
                    c2fb_temp_16 = Cast(SQLITE_C_INT, IIf(arg0->nErr, Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, &O0ULL)))
                    local4 = c2fb_temp_16
                    ' C unused-parameter annotation
                    ' C unused-parameter annotation
                    If CPtr(SqliteExprList Ptr, local2->pExprList) Then
                        c2fb_temp_17 = @(local6->pEList)
                        c2fb_temp_18 = CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                        (*c2fb_temp_17) = c2fb_temp_18
                    End If
                    c2fb_temp_19 = @(local6->pSrc)
                    c2fb_temp_20 = CPtr(SqliteSrcListRecord Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                    (*c2fb_temp_19) = CPtr(SqliteSrcList Ptr, c2fb_temp_20)
                    c2fb_temp_20 = CPtr(SqliteSrcListRecord Ptr, (*c2fb_temp_19))
                    sqlite3SelectDelete(CPtr(Any Ptr, local0), CPtr(Any Ptr, local6))
                End If
                If (CPtr(SqliteSrcListRecord Ptr, local2->pSrc)) Then
                    ' C automatic storage declaration
                    c2fb_temp_21 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    local7 = c2fb_temp_21
                    While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local7 < CPtr(SqliteSrcListRecord Ptr, local2->pSrc)->nSrc)))) AndAlso (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL)))))))))
                        local8 = CPtr(SqliteSrcItem Ptr, @(CPtr(SqliteSrcListRecord Ptr, local2->pSrc)->a(local7)))
                        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local8->fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                            ' C unused-parameter annotation
                            sqlite3SelectPrep(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local8->u4.pSubq->pSelect), Cast(SQLITE_C_INT, &O0ULL))
                        End If
                    c2fb_flow_3:
                        c2fb_temp_22 = local7
                        local7 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_22 + 1)))
                    Wend
                    c2fb_flow_2:
                End If
                If local0->mallocFailed Then
                    c2fb_temp_23 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 7ULL))
                    local4 = c2fb_temp_23
                End If
                c2fb_temp_24 = @(local3.pSrcList)
                c2fb_temp_25 = local5
                (*c2fb_temp_24) = CPtr(SqliteSrcList Ptr, c2fb_temp_25)
                c2fb_temp_25 = CPtr(SqliteSrcListRecord Ptr, (*c2fb_temp_24))
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso CPtr(SqliteExpr Ptr, local2->pWhere))))) Then
                    c2fb_temp_26 = Cast(SQLITE_C_INT, sqlite3ResolveExprNames(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local3))), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local2->pWhere))))
                    local4 = c2fb_temp_26
                End If
                If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_27 = Cast(SQLITE_C_INT, sqlite3ResolveExprListNames(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local3))), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, local2->pExprList))))
                    local4 = c2fb_temp_27
                End If
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, ((CPtr(SqliteUpsert Ptr, local2->pUpsert) AndAlso (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                    local9 = CPtr(SqliteUpsert Ptr, local2->pUpsert)
                    c2fb_temp_28 = @(local9->pUpsertSrc)
                    c2fb_temp_29 = local5
                    (*c2fb_temp_28) = CPtr(Any Ptr, c2fb_temp_29)
                    c2fb_temp_29 = CPtr(SqliteSrcListRecord Ptr, (*c2fb_temp_28))
                    c2fb_temp_30 = @(local3.uNC.pUpsert)
                    c2fb_temp_31 = local9
                    (*c2fb_temp_30) = c2fb_temp_31
                    c2fb_temp_32 = @(local3.ncFlags)
                    c2fb_temp_33 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &H000200ULL))
                    (*c2fb_temp_32) = c2fb_temp_33
                    c2fb_temp_34 = Cast(SQLITE_C_INT, sqlite3ResolveExprListNames(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local3))), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, local9->pUpsertTarget))))
                    local4 = c2fb_temp_34
                    If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        local10 = CPtr(SqliteExprList Ptr, local9->pUpsertSet)
                        c2fb_temp_35 = Cast(SQLITE_C_INT, sqlite3ResolveExprListNames(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local3))), CPtr(Any Ptr, local10)))
                        local4 = c2fb_temp_35
                    End If
                    If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        c2fb_temp_36 = Cast(SQLITE_C_INT, sqlite3ResolveExprNames(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local3))), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local9->pUpsertWhere))))
                        local4 = c2fb_temp_36
                    End If
                    If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        c2fb_temp_37 = Cast(SQLITE_C_INT, sqlite3ResolveExprNames(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local3))), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local9->pUpsertTargetWhere))))
                        local4 = c2fb_temp_37
                    End If
                    c2fb_temp_38 = @(local3.ncFlags)
                    c2fb_temp_39 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    (*c2fb_temp_38) = c2fb_temp_39
                End If
                c2fb_temp_40 = @(local3.pSrcList)
                c2fb_temp_41 = CPtr(SqliteSrcListRecord Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                (*c2fb_temp_40) = CPtr(SqliteSrcList Ptr, c2fb_temp_41)
                c2fb_temp_41 = CPtr(SqliteSrcListRecord Ptr, (*c2fb_temp_40))
                sqlite3SrcListDelete(CPtr(Any Ptr, local0), CPtr(Any Ptr, local5))
            Else
                c2fb_temp_42 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 7ULL))
                local4 = c2fb_temp_42
            End If
        End If
    c2fb_flow_1:
        c2fb_temp_10 = local2->pNext
        local2 = c2fb_temp_10
    Wend
    c2fb_flow_0:
    Return local4
End Function

Private Sub renameTableTest CDecl Alias "renameTableTest" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteVdbeMem Ptr Ptr)
    Dim local0 As sqlite3 Ptr
    Dim local1 As Const ZString Ptr
    Dim local2 As Const ZString Ptr
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As Const ZString Ptr
    Dim local6 As SQLITE_C_INT
    Dim local7 As c2fb_callback_3
    Dim c2fb_temp_0 As SqliteAuthorizerCallback Ptr
    Dim c2fb_temp_1 As c2fb_callback_3
    Dim local8 As SQLITE_C_INT
    Dim local9 As SqliteParseContext
    Dim local10 As sqlite3_uint64
    Dim c2fb_temp_2 As sqlite3_uint64 Ptr
    Dim c2fb_temp_3 As sqlite3_uint64
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As sqlite3_uint64 Ptr
    Dim c2fb_temp_6 As sqlite3_uint64
    Dim local11 As SqliteNameContext
    Dim c2fb_temp_7 As Any Ptr
    Dim c2fb_temp_8 As SqliteParseContext Ptr Ptr
    Dim c2fb_temp_9 As SqliteParseContext Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim local12 As SQLITE_C_INT
    Dim local13 As SQLITE_C_INT
    Dim c2fb_temp_12 As SqliteAuthorizerCallback Ptr
    Dim c2fb_temp_13 As c2fb_callback_3

    local0 = CPtr(sqlite3 Ptr, sqlite3_context_db_handle(CPtr(Any Ptr, arg0)))
    local1 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, &O0ULL)])))
    local2 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, 1ULL)])))
    local3 = sqlite3_value_int(arg2[Cast(SQLITE_C_INT, 4ULL)])
    local4 = (Cast(sqlite3_uint64, (local0->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &H04000000ULL)))))
    local5 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, 5ULL)])))
    local6 = sqlite3_value_int(arg2[Cast(SQLITE_C_INT, 6ULL)])
    local7 = CPtr(c2fb_callback_3, local0->xAuth)
    c2fb_temp_0 = @(local0->xAuth)
    c2fb_temp_1 = CPtr(c2fb_callback_3, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_0) = Cast(SqliteAuthorizerCallback, c2fb_temp_1)
    c2fb_temp_1 = CPtr(c2fb_callback_3, (*c2fb_temp_0))
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((local1 AndAlso local2)))) Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        local10 = local0->flags
        If local6 Then
            c2fb_temp_2 = @(local0->flags)
            c2fb_temp_3 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, ((*c2fb_temp_2) And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, (Not (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H40000000ULL) Or Cast(SQLITE_C_INT, &H20000000ULL))))))))))
            (*c2fb_temp_2) = c2fb_temp_3
        End If
        c2fb_temp_4 = Cast(SQLITE_C_INT, renameParseSql(CPtr(SqliteParseContext Ptr, @(local9)), local1, local0, local2, local3))
        local8 = c2fb_temp_4
        c2fb_temp_5 = @(local0->flags)
        c2fb_temp_6 = Cast(sqlite3_uint64, local10)
        (*c2fb_temp_5) = c2fb_temp_6
        If (-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso CPtr(SqliteTable Ptr, local9.pNewTable))))) AndAlso ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (CPtr(SqliteTable Ptr, local9.pNewTable))->eTabType) = Cast(SQLITE_C_INT, 2ULL)))))))))) Then
                ' C automatic storage declaration
                c2fb_temp_7 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local11))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteNameContext))))
                c2fb_temp_8 = @(local11.pParse)
                c2fb_temp_9 = CPtr(SqliteParseContext Ptr, @(local9))
                (*c2fb_temp_8) = c2fb_temp_9
                sqlite3SelectPrep(CPtr(Any Ptr, CPtr(SqliteParseContext Ptr, @(local9))), CPtr(Any Ptr, CPtr(SqliteSelect Ptr, CPtr(SqliteTable Ptr, local9.pNewTable)->u.view.pSelect)), CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local11))))
                If local9.nErr Then
                    c2fb_temp_10 = Cast(SQLITE_C_INT, local9.rc)
                    local8 = c2fb_temp_10
                End If
            Else
                If CPtr(SqliteTrigger Ptr, local9.pNewTrigger) Then
                    If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        c2fb_temp_11 = Cast(SQLITE_C_INT, renameResolveTrigger(CPtr(SqliteParseContext Ptr, @(local9))))
                        local8 = c2fb_temp_11
                    End If
                    If (-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        local12 = sqlite3SchemaToIndex(CPtr(Any Ptr, local0), CPtr(Any Ptr, CPtr(SqliteSchema Ptr, CPtr(SqliteTrigger Ptr, local9.pNewTrigger)->pTabSchema)))
                        local13 = sqlite3FindDbName(CPtr(Any Ptr, local0), local1)
                        If (-Cast(SQLITE_C_INT, ((local12 = local13)))) Then
                            sqlite3_result_int(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 1ULL))
                        End If
                    End If
                End If
            End If
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local8 <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso local5)))) AndAlso (-Cast(SQLITE_C_INT, (sqlite3WritableSchema(CPtr(Any Ptr, local0)) = 0))))))) Then
            renameColumnParseError(arg0, local5, arg2[Cast(SQLITE_C_INT, 2ULL)], arg2[Cast(SQLITE_C_INT, 3ULL)], CPtr(SqliteParseContext Ptr, @(local9)))
        End If
        renameParseCleanup(CPtr(SqliteParseContext Ptr, @(local9)))
    End If
    c2fb_temp_12 = @(local0->xAuth)
    c2fb_temp_13 = local7
    (*c2fb_temp_12) = Cast(SqliteAuthorizerCallback, c2fb_temp_13)
    c2fb_temp_13 = CPtr(c2fb_callback_3, (*c2fb_temp_12))
End Sub

Private Function renameColumnExprCb CDecl Alias "renameColumnExprCb" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim local0 As SqliteRenameContext Ptr
    Dim c2fb_temp_0 As SqliteRenameToken Ptr
    Dim c2fb_temp_1 As SqliteRenameToken Ptr

    local0 = CPtr(SqliteRenameContext Ptr, arg0->u.pRename)
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 78ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->iColumn) = local0->iCol)))))))) AndAlso (-Cast(SQLITE_C_INT, ((arg0->pParse->pTriggerTab = local0->pTab)))))))) Then
        c2fb_temp_0 = CPtr(SqliteRenameToken Ptr, renameTokenFind(arg0->pParse, local0, CPtr(Const Any Ptr, CPtr(Any Ptr, arg1))))
    Else
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 168ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->iColumn) = local0->iCol)))))))) AndAlso (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H1000000ULL) Or Cast(SQLITE_C_INT, &H2000000ULL)))))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))))) AndAlso (-Cast(SQLITE_C_INT, ((local0->pTab = CPtr(SqliteTable Ptr, arg1->y.pTab))))))))) Then
            c2fb_temp_1 = CPtr(SqliteRenameToken Ptr, renameTokenFind(arg0->pParse, local0, CPtr(Const Any Ptr, CPtr(Any Ptr, arg1))))
        End If
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function renameColumnTokenNext CDecl Alias "renameColumnTokenNext" (ByVal arg0 As SqliteRenameContext Ptr) As SqliteRenameToken Ptr
    Dim local0 As SqliteRenameToken Ptr
    Dim local1 As SqliteRenameToken Ptr
    Dim local2 As SqliteRenameToken Ptr Ptr
    Dim c2fb_temp_0 As SqliteRenameToken Ptr
    Dim c2fb_temp_1 As SqliteRenameToken Ptr
    Dim c2fb_temp_2 As SqliteRenameToken Ptr
    Dim c2fb_temp_3 As SqliteRenameToken Ptr Ptr
    Dim c2fb_temp_4 As SqliteRenameToken Ptr Ptr
    Dim c2fb_temp_5 As SqliteRenameToken Ptr Ptr
    Dim c2fb_temp_6 As SqliteRenameToken Ptr

    local0 = arg0->pList
    ' C automatic storage declaration
    ' C automatic storage declaration
    c2fb_temp_0 = local0->pNext
    local1 = c2fb_temp_0
    While local1
        If (-Cast(SQLITE_C_INT, ((CPtr(Const ZString Ptr, local1->t.z) > CPtr(Const ZString Ptr, local0->t.z))))) Then
            c2fb_temp_2 = local1
            local0 = c2fb_temp_2
        End If
    c2fb_flow_1:
        c2fb_temp_1 = local1->pNext
        local1 = c2fb_temp_1
    Wend
    c2fb_flow_0:
    c2fb_temp_3 = CPtr(SqliteRenameToken Ptr Ptr, @(arg0->pList))
    local2 = c2fb_temp_3
    While (-Cast(SQLITE_C_INT, (((*local2) <> local0))))
        ' empty C statement
    c2fb_flow_3:
        c2fb_temp_4 = CPtr(SqliteRenameToken Ptr Ptr, @(((*local2))->pNext))
        local2 = c2fb_temp_4
    Wend
    c2fb_flow_2:
    c2fb_temp_5 = @((*local2))
    c2fb_temp_6 = local0->pNext
    (*c2fb_temp_5) = c2fb_temp_6
    Return local0
End Function

Private Function renameEditSql CDecl Alias "renameEditSql" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SqliteRenameContext Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As Const ZString Ptr, ByVal arg4 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As sqlite3_int64
    Dim local1 As sqlite3_int64
    Dim local2 As sqlite3 Ptr
    Dim local3 As SQLITE_C_INT
    Dim local4 As ZString Ptr
    Dim local5 As ZString Ptr
    Dim local6 As sqlite3_int64
    Dim local7 As ZString Ptr
    Dim local8 As ZString Ptr
    Dim c2fb_temp_0 As ZString Ptr
    Dim c2fb_temp_1 As sqlite3_int64
    Dim c2fb_temp_2 As ZString Ptr
    Dim c2fb_temp_3 As ZString Ptr
    Dim c2fb_temp_4 As ZString Ptr
    Dim c2fb_temp_5 As ZString Ptr
    Dim local9 As sqlite3_int64
    Dim c2fb_temp_6 As Any Ptr
    Dim local10 As SQLITE_C_INT
    Dim local11 As sqlite3_int64
    Dim local12 As Const ZString Ptr
    Dim local13 As SqliteRenameToken Ptr
    Dim c2fb_temp_7 As sqlite3_int64
    Dim c2fb_temp_8 As Const ZString Ptr
    Dim c2fb_temp_9 As sqlite3_int64
    Dim c2fb_temp_10 As Const ZString Ptr
    Dim c2fb_temp_11 As sqlite3_int64
    Dim c2fb_temp_12 As Any Ptr
    Dim c2fb_temp_13 As Byte Ptr
    Dim c2fb_temp_14 As Byte
    Dim c2fb_temp_15 As ZString Ptr
    Dim c2fb_temp_16 As Const ZString Ptr
    Dim c2fb_temp_17 As sqlite3_int64
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As Any Ptr
    Dim c2fb_temp_20 As sqlite3_int64
    Dim c2fb_temp_21 As Byte Ptr
    Dim c2fb_temp_22 As Byte
    Dim c2fb_temp_23 As Any Ptr
    Dim c2fb_temp_24 As SQLITE_C_INT

    local0 = sqlite3Strlen30(arg3)
    local1 = sqlite3Strlen30(arg2)
    local2 = CPtr(sqlite3 Ptr, sqlite3_context_db_handle(CPtr(Any Ptr, arg0)))
    local3 = Cast(SQLITE_C_INT, &O0ULL)
    local4 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    local6 = Cast(SQLITE_C_INT, &O0ULL)
    local7 = Cast(SQLITE_C_INT, &O0ULL)
    local8 = Cast(SQLITE_C_INT, &O0ULL)
    If arg3 Then
        c2fb_temp_0 = CPtr(ZString Ptr, sqlite3MPrintf(CPtr(Any Ptr, local2), StrPtr(!"\034%w\034 "), arg3))
        local4 = c2fb_temp_0
        If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return Cast(SQLITE_C_INT, 7ULL)
        Else
            c2fb_temp_1 = Cast(sqlite3_int64, Cast(SQLITE_C_INT, (sqlite3Strlen30(CPtr(Const ZString Ptr, local4)) - Cast(SQLITE_C_INT, 1ULL))))
            local6 = c2fb_temp_1
        End If
        ' C unused-parameter annotation
        c2fb_temp_2 = CPtr(ZString Ptr, CPtr(Any Ptr, sqlite3DbMallocZero(CPtr(Any Ptr, local2), Cast(sqlite3_uint64, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, local1) + Cast(sqlite3_uint64, (Cast(sqlite3_uint64, arg1->nList) * Cast(sqlite3_uint64, local6))))) + Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL)))))))
        local5 = c2fb_temp_2
    Else
        ' C unused-parameter annotation
        c2fb_temp_3 = CPtr(ZString Ptr, CPtr(Any Ptr, sqlite3DbMallocZero(CPtr(Any Ptr, local2), Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 2ULL)) * Cast(sqlite3_uint64, local1))) + Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 3ULL)))))))
        local5 = c2fb_temp_3
        If local5 Then
            c2fb_temp_4 = CPtr(ZString Ptr, CPtr(Byte Ptr, @(CPtr(Byte Ptr, local5)[Cast(sqlite3_int64, (Cast(sqlite3_int64, (local1 * Cast(sqlite3_int64, Cast(SQLITE_C_INT, 2ULL)))) + Cast(sqlite3_int64, Cast(SQLITE_C_INT, 1ULL))))])))
            local7 = c2fb_temp_4
            c2fb_temp_5 = CPtr(ZString Ptr, CPtr(Byte Ptr, @(CPtr(Byte Ptr, local5)[Cast(sqlite3_int64, (Cast(sqlite3_int64, (local1 * Cast(sqlite3_int64, Cast(SQLITE_C_INT, 4ULL)))) + Cast(sqlite3_int64, Cast(SQLITE_C_INT, 2ULL))))])))
            local8 = c2fb_temp_5
        End If
    End If
    If local5 Then
        local9 = local1
        ' C unused-parameter annotation
        c2fb_temp_6 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, local5), CPtr(Const Any Ptr, arg2), Cast(SQLITE_SIZE_T, local1)))
        While arg1->pList
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C automatic storage declaration
            local13 = CPtr(SqliteRenameToken Ptr, renameColumnTokenNext(arg1))
            If arg3 Then
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg4 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso sqlite3IsIdChar((*CPtr(UByte Ptr, CPtr(Const ZString Ptr, local13->t.z)))))))) Then
                    c2fb_temp_7 = Cast(sqlite3_int64, local0)
                    local11 = c2fb_temp_7
                    c2fb_temp_8 = arg3
                    local12 = c2fb_temp_8
                Else
                    c2fb_temp_9 = Cast(sqlite3_int64, local6)
                    local11 = c2fb_temp_9
                    c2fb_temp_10 = CPtr(Const ZString Ptr, local4)
                    local12 = c2fb_temp_10
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(Const Byte Ptr, CPtr(Const ZString Ptr, local13->t.z))[local13->t.n]) = Cast(SQLITE_C_INT, 34))))) Then
                        c2fb_temp_11 = local11
                        local11 = Cast(sqlite3_int64, Cast(sqlite3_int64, (c2fb_temp_11 + 1)))
                    End If
                End If
            Else
                c2fb_temp_12 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, local7), CPtr(Const Any Ptr, CPtr(Const ZString Ptr, local13->t.z)), local13->t.n))
                c2fb_temp_13 = @(CPtr(Byte Ptr, local7)[local13->t.n])
                c2fb_temp_14 = Cast(Byte, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_13) = c2fb_temp_14
                sqlite3Dequote(local7)
                ' C unused-parameter annotation
                c2fb_temp_15 = CPtr(ZString Ptr, sqlite3_snprintf(Cast(SQLITE_C_INT, (Cast(sqlite3_int64, (local1 * Cast(sqlite3_int64, Cast(SQLITE_C_INT, 2ULL)))))), local8, StrPtr(!"%Q%s"), local7, IIf((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(Const Byte Ptr, CPtr(Const ZString Ptr, local13->t.z))[local13->t.n]) = Cast(SQLITE_C_INT, 39))))), StrPtr(!" "), StrPtr(!""))))
                c2fb_temp_16 = CPtr(Const ZString Ptr, local8)
                local12 = c2fb_temp_16
                c2fb_temp_17 = Cast(sqlite3_int64, sqlite3Strlen30(local12))
                local11 = c2fb_temp_17
            End If
            c2fb_temp_18 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((CPtr(Const Byte Ptr, CPtr(Const ZString Ptr, local13->t.z)) - CPtr(Const Byte Ptr, arg2)))))
            local10 = c2fb_temp_18
            If (-Cast(SQLITE_C_INT, ((Cast(sqlite3_int64, local13->t.n) <> local11)))) Then
                c2fb_temp_19 = CPtr(Any Ptr, c2fb_crt_memmove(CPtr(Any Ptr, CPtr(Byte Ptr, @(CPtr(Byte Ptr, local5)[Cast(sqlite3_int64, (Cast(sqlite3_int64, local10) + local11))]))), CPtr(Const Any Ptr, CPtr(Byte Ptr, @(CPtr(Byte Ptr, local5)[Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, local10) + local13->t.n))]))), Cast(sqlite3_int64, (local9 - Cast(sqlite3_int64, (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, local10) + local13->t.n))))))))
                c2fb_temp_20 = Cast(sqlite3_int64, Cast(sqlite3_int64, (local9 + Cast(sqlite3_int64, (local11 - Cast(sqlite3_int64, local13->t.n))))))
                local9 = c2fb_temp_20
                c2fb_temp_21 = @(CPtr(Byte Ptr, local5)[local9])
                c2fb_temp_22 = Cast(Byte, Cast(SQLITE_C_INT, 0))
                (*c2fb_temp_21) = c2fb_temp_22
            End If
            c2fb_temp_23 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, CPtr(Byte Ptr, @(CPtr(Byte Ptr, local5)[local10]))), CPtr(Const Any Ptr, local12), local11))
            sqlite3DbFree(CPtr(Any Ptr, local2), CPtr(Any Ptr, local13))
        c2fb_flow_1:
        Wend
        c2fb_flow_0:
        sqlite3_result_text(CPtr(Any Ptr, arg0), CPtr(Const ZString Ptr, local5), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), CPtr(Any Ptr, (CPtr(c2fb_callback_8, Cast(Integer, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))))))
        sqlite3DbFree(CPtr(Any Ptr, local2), CPtr(Any Ptr, local5))
    Else
        c2fb_temp_24 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 7ULL))
        local3 = c2fb_temp_24
    End If
    sqlite3_free(CPtr(Any Ptr, local4))
    Return local3
End Function

Private Function renameTableExprCb CDecl Alias "renameTableExprCb" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim local0 As SqliteRenameContext Ptr
    Dim c2fb_temp_0 As SqliteRenameToken Ptr

    local0 = CPtr(SqliteRenameContext Ptr, arg0->u.pRename)
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 168ULL))))) AndAlso (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H1000000ULL) Or Cast(SQLITE_C_INT, &H2000000ULL)))))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))))) AndAlso (-Cast(SQLITE_C_INT, ((local0->pTab = CPtr(SqliteTable Ptr, arg1->y.pTab))))))))) Then
        c2fb_temp_0 = CPtr(SqliteRenameToken Ptr, renameTokenFind(arg0->pParse, local0, CPtr(Const Any Ptr, CPtr(Any Ptr, CPtr(SqliteTable Ptr Ptr, @(arg1->y.pTab))))))
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function renameTableSelectCb CDecl Alias "renameTableSelectCb" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteSelect Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SqliteRenameContext Ptr
    Dim local2 As SqliteSrcListRecord Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local3 As SqliteSrcItem Ptr
    Dim c2fb_temp_2 As SqliteRenameToken Ptr

    ' C automatic storage declaration
    local1 = CPtr(SqliteRenameContext Ptr, arg0->u.pRename)
    local2 = CPtr(SqliteSrcListRecord Ptr, arg1->pSrc)
    If Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0200000ULL) Or Cast(SQLITE_C_INT, &H4000000ULL))))))) Then
        ' empty C statement
        ' empty C statement
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    If ((-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, &O0ULL)))))) Then
        ' C unused-parameter annotation
        Return Cast(SQLITE_C_INT, 2ULL)
    End If
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((local0 < local2->nSrc))))
        local3 = CPtr(SqliteSrcItem Ptr, @(local2->a(local0)))
        If (-Cast(SQLITE_C_INT, ((local3->pSTab = local1->pTab)))) Then
            c2fb_temp_2 = CPtr(SqliteRenameToken Ptr, renameTokenFind(arg0->pParse, local1, CPtr(Const Any Ptr, local3->zName)))
        End If
    c2fb_flow_1:
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    Wend
    c2fb_flow_0:
    renameWalkWith(arg0, arg1)
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Sub renameColumnFunc CDecl Alias "renameColumnFunc" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteVdbeMem Ptr Ptr)
    Dim local0 As sqlite3 Ptr
    Dim local1 As SqliteRenameContext
    Dim local2 As Const ZString Ptr
    Dim local3 As Const ZString Ptr
    Dim local4 As Const ZString Ptr
    Dim local5 As SQLITE_C_INT
    Dim local6 As Const ZString Ptr
    Dim local7 As SQLITE_C_INT
    Dim local8 As SQLITE_C_INT
    Dim local9 As Const ZString Ptr
    Dim local10 As SQLITE_C_INT
    Dim local11 As SqliteParseContext
    Dim local12 As SqliteWalker
    Dim local13 As SqliteIndex Ptr
    Dim local14 As SQLITE_C_INT
    Dim local15 As SqliteTable Ptr
    Dim local16 As c2fb_callback_3
    Dim c2fb_temp_0 As SqliteTable Ptr
    Dim c2fb_temp_1 As Const ZString Ptr
    Dim c2fb_temp_2 As Any Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SqliteAuthorizerCallback Ptr
    Dim c2fb_temp_6 As c2fb_callback_3
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As Any Ptr
    Dim c2fb_temp_9 As SqliteParseContext Ptr Ptr
    Dim c2fb_temp_10 As SqliteParseContext Ptr
    Dim c2fb_temp_11 As SqliteWalkerExprCallback Ptr
    Dim c2fb_temp_12 As c2fb_callback_85
    Dim c2fb_temp_13 As SqliteWalkerSelectCallback Ptr
    Dim c2fb_temp_14 As c2fb_callback_85
    Dim c2fb_temp_15 As Any Ptr Ptr
    Dim c2fb_temp_16 As SqliteRenameContext Ptr
    Dim c2fb_temp_17 As SqliteTable Ptr Ptr
    Dim c2fb_temp_18 As SqliteTable Ptr
    Dim local17 As SqliteSelect Ptr
    Dim c2fb_temp_19 As u32 Ptr
    Dim c2fb_temp_20 As SQLITE_C_UINT
    Dim c2fb_temp_21 As SQLITE_C_INT Ptr
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim c2fb_temp_23 As SQLITE_C_INT
    Dim local18 As SQLITE_C_INT
    Dim local19 As SqliteFKey Ptr
    Dim c2fb_temp_24 As SqliteTable Ptr Ptr
    Dim c2fb_temp_25 As SqliteTable Ptr
    Dim c2fb_temp_26 As SqliteRenameToken Ptr
    Dim c2fb_temp_27 As SqliteRenameToken Ptr
    Dim c2fb_temp_28 As SqliteIndex Ptr
    Dim c2fb_temp_29 As SqliteIndex Ptr
    Dim c2fb_temp_30 As SqliteIndex Ptr
    Dim c2fb_temp_31 As SqliteIndex Ptr
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As SQLITE_C_INT
    Dim local20 As SqliteExpr Ptr
    Dim c2fb_temp_34 As SqliteFKey Ptr
    Dim c2fb_temp_35 As SqliteFKey Ptr
    Dim c2fb_temp_36 As SQLITE_C_INT
    Dim c2fb_temp_37 As SQLITE_C_INT
    Dim c2fb_temp_38 As SqliteRenameToken Ptr
    Dim c2fb_temp_39 As SqliteRenameToken Ptr
    Dim local21 As SqliteTriggerStep Ptr
    Dim c2fb_temp_40 As SQLITE_C_INT
    Dim c2fb_temp_41 As SqliteTriggerStep Ptr
    Dim c2fb_temp_42 As SqliteTriggerStep Ptr
    Dim local22 As SqliteTable Ptr
    Dim local23 As SqliteExprList Ptr
    Dim c2fb_temp_43 As SQLITE_C_INT
    Dim c2fb_temp_44 As SqliteAuthorizerCallback Ptr
    Dim c2fb_temp_45 As c2fb_callback_3

    local0 = CPtr(sqlite3 Ptr, sqlite3_context_db_handle(CPtr(Any Ptr, arg0)))
    ' C automatic storage declaration
    local2 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, &O0ULL)])))
    local3 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, 3ULL)])))
    local4 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, 4ULL)])))
    local5 = sqlite3_value_int(arg2[Cast(SQLITE_C_INT, 5ULL)])
    local6 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, 6ULL)])))
    local7 = sqlite3_value_int(arg2[Cast(SQLITE_C_INT, 7ULL)])
    local8 = sqlite3_value_int(arg2[Cast(SQLITE_C_INT, 8ULL)])
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local16 = CPtr(c2fb_callback_3, local0->xAuth)
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    If (-Cast(SQLITE_C_INT, ((local6 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    If (-Cast(SQLITE_C_INT, ((local5 < Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    sqlite3BtreeEnterAll(local0)
    c2fb_temp_0 = CPtr(SqliteTable Ptr, sqlite3FindTable(CPtr(Any Ptr, local0), local4, local3))
    local15 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local15 = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local5 >= Cast(SQLITE_C_INT, local15->nCol))))))))) Then
        sqlite3BtreeLeaveAll(local0)
        Return
    End If
    c2fb_temp_1 = CPtr(Const ZString Ptr, local15->aCol[local5].zCnName)
    local9 = c2fb_temp_1
    c2fb_temp_2 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteRenameContext Ptr, @(local1))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteRenameContext))))
    c2fb_temp_3 = @(local1.iCol)
    c2fb_temp_4 = Cast(SQLITE_C_INT, (IIf(((-Cast(SQLITE_C_INT, ((local5 = Cast(SQLITE_C_INT, local15->iPKey)))))), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), local5)))
    (*c2fb_temp_3) = c2fb_temp_4
    c2fb_temp_5 = @(local0->xAuth)
    c2fb_temp_6 = CPtr(c2fb_callback_3, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_5) = Cast(SqliteAuthorizerCallback, c2fb_temp_6)
    c2fb_temp_6 = CPtr(c2fb_callback_3, (*c2fb_temp_5))
    c2fb_temp_7 = Cast(SQLITE_C_INT, renameParseSql(CPtr(SqliteParseContext Ptr, @(local11)), local3, local0, local2, local8))
    local10 = c2fb_temp_7
    c2fb_temp_8 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local12))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteWalker))))
    c2fb_temp_9 = @(local12.pParse)
    c2fb_temp_10 = CPtr(SqliteParseContext Ptr, @(local11))
    (*c2fb_temp_9) = c2fb_temp_10
    c2fb_temp_11 = @(local12.xExprCallback)
    c2fb_temp_12 = CPtr(c2fb_callback_85, ProcPtr(renameColumnExprCb))
    (*c2fb_temp_11) = Cast(SqliteWalkerExprCallback, c2fb_temp_12)
    c2fb_temp_12 = CPtr(c2fb_callback_85, (*c2fb_temp_11))
    c2fb_temp_13 = @(local12.xSelectCallback)
    c2fb_temp_14 = CPtr(c2fb_callback_85, ProcPtr(renameColumnSelectCb))
    (*c2fb_temp_13) = Cast(SqliteWalkerSelectCallback, c2fb_temp_14)
    c2fb_temp_14 = CPtr(c2fb_callback_85, (*c2fb_temp_13))
    c2fb_temp_15 = @(local12.u.pRename)
    c2fb_temp_16 = CPtr(SqliteRenameContext Ptr, @(local1))
    (*c2fb_temp_15) = CPtr(Any Ptr, c2fb_temp_16)
    c2fb_temp_16 = CPtr(SqliteRenameContext Ptr, (*c2fb_temp_15))
    c2fb_temp_17 = @(local1.pTab)
    c2fb_temp_18 = local15
    (*c2fb_temp_17) = c2fb_temp_18
    If (-Cast(SQLITE_C_INT, ((local10 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        Goto c2fb_label_0
    End If
    If CPtr(SqliteTable Ptr, local11.pNewTable) Then
        If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (CPtr(SqliteTable Ptr, local11.pNewTable))->eTabType) = Cast(SQLITE_C_INT, 2ULL)))))) Then
            local17 = CPtr(SqliteSelect Ptr, CPtr(SqliteTable Ptr, local11.pNewTable)->u.view.pSelect)
            c2fb_temp_19 = @(local17->selFlags)
            c2fb_temp_20 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_19)) And Cast(SQLITE_C_UINT, (Not Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0200000ULL)))))))
            (*c2fb_temp_19) = Cast(u32, c2fb_temp_20)
            c2fb_temp_20 = Cast(SQLITE_C_UINT, (*c2fb_temp_19))
            c2fb_temp_21 = @(local11.rc)
            c2fb_temp_22 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_21) = c2fb_temp_22
            sqlite3SelectPrep(CPtr(Any Ptr, CPtr(SqliteParseContext Ptr, @(local11))), CPtr(Any Ptr, local17), Cast(SQLITE_C_INT, &O0ULL))
            c2fb_temp_23 = Cast(SQLITE_C_INT, (IIf(local0->mallocFailed, Cast(SQLITE_C_INT, 7ULL), local11.rc)))
            local10 = c2fb_temp_23
            If (-Cast(SQLITE_C_INT, ((local10 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                sqlite3WalkSelect(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local12))), CPtr(Any Ptr, local17))
            End If
            If (-Cast(SQLITE_C_INT, ((local10 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                Goto c2fb_label_0
            End If
        Else
            If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (CPtr(SqliteTable Ptr, local11.pNewTable))->eTabType) = Cast(SQLITE_C_INT, &O0ULL)))))) Then
                local18 = sqlite3_stricmp(local4, CPtr(Const ZString Ptr, CPtr(SqliteTable Ptr, local11.pNewTable)->zName))
                ' C automatic storage declaration
                c2fb_temp_24 = @(local1.pTab)
                c2fb_temp_25 = CPtr(SqliteTable Ptr, local11.pNewTable)
                (*c2fb_temp_24) = c2fb_temp_25
                If (-Cast(SQLITE_C_INT, ((local18 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    If (-Cast(SQLITE_C_INT, ((local5 < Cast(SQLITE_C_INT, CPtr(SqliteTable Ptr, local11.pNewTable)->nCol))))) Then
                        c2fb_temp_26 = CPtr(SqliteRenameToken Ptr, renameTokenFind(CPtr(SqliteParseContext Ptr, @(local11)), CPtr(SqliteRenameContext Ptr, @(local1)), CPtr(Const Any Ptr, CPtr(Any Ptr, CPtr(SqliteTable Ptr, local11.pNewTable)->aCol[local5].zCnName))))
                    End If
                    If (-Cast(SQLITE_C_INT, ((local1.iCol < Cast(SQLITE_C_INT, &O0ULL))))) Then
                        c2fb_temp_27 = CPtr(SqliteRenameToken Ptr, renameTokenFind(CPtr(SqliteParseContext Ptr, @(local11)), CPtr(SqliteRenameContext Ptr, @(local1)), CPtr(Const Any Ptr, CPtr(Any Ptr, CPtr(Short Ptr, @(CPtr(SqliteTable Ptr, local11.pNewTable)->iPKey))))))
                    End If
                    sqlite3WalkExprList(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local12))), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, CPtr(SqliteTable Ptr, local11.pNewTable)->pCheck)))
                    c2fb_temp_28 = CPtr(SqliteIndex Ptr, CPtr(SqliteTable Ptr, local11.pNewTable)->pIndex)
                    local13 = c2fb_temp_28
                    While local13
                        sqlite3WalkExprList(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local12))), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, local13->aColExpr)))
                    c2fb_flow_1:
                        c2fb_temp_29 = local13->pNext
                        local13 = c2fb_temp_29
                    Wend
                    c2fb_flow_0:
                    c2fb_temp_30 = CPtr(SqliteIndex Ptr, local11.pNewIndex)
                    local13 = c2fb_temp_30
                    While local13
                        sqlite3WalkExprList(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local12))), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, local13->aColExpr)))
                    c2fb_flow_3:
                        c2fb_temp_31 = local13->pNext
                        local13 = c2fb_temp_31
                    Wend
                    c2fb_flow_2:
                    c2fb_temp_32 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    local14 = c2fb_temp_32
                    While (-Cast(SQLITE_C_INT, ((local14 < Cast(SQLITE_C_INT, CPtr(SqliteTable Ptr, local11.pNewTable)->nCol)))))
                        local20 = CPtr(SqliteExpr Ptr, sqlite3ColumnExpr(CPtr(Any Ptr, CPtr(SqliteTable Ptr, local11.pNewTable)), CPtr(Any Ptr, CPtr(SqliteColumn Ptr, @(CPtr(SqliteTable Ptr, local11.pNewTable)->aCol[local14])))))
                        sqlite3WalkExpr(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local12))), CPtr(Any Ptr, local20))
                    c2fb_flow_5:
                        c2fb_temp_33 = local14
                        local14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_33 + 1)))
                    Wend
                    c2fb_flow_4:
                End If
                ' C unused-parameter annotation
                c2fb_temp_34 = CPtr(SqliteTable Ptr, local11.pNewTable)->u.tab.pFKey
                local19 = c2fb_temp_34
                While local19
                    c2fb_temp_36 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    local14 = c2fb_temp_36
                    While (-Cast(SQLITE_C_INT, ((local14 < local19->nCol))))
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local18 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local19->aCol(local14).iFrom = local5)))))))) Then
                            c2fb_temp_38 = CPtr(SqliteRenameToken Ptr, renameTokenFind(CPtr(SqliteParseContext Ptr, @(local11)), CPtr(SqliteRenameContext Ptr, @(local1)), CPtr(Const Any Ptr, CPtr(Any Ptr, CPtr(SqliteFKeyColumn Ptr, @(local19->aCol(local14)))))))
                        End If
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = sqlite3_stricmp(CPtr(Const ZString Ptr, local19->zTo), local4))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = sqlite3_stricmp(CPtr(Const ZString Ptr, local19->aCol(local14).zCol), local9))))))))) Then
                            c2fb_temp_39 = CPtr(SqliteRenameToken Ptr, renameTokenFind(CPtr(SqliteParseContext Ptr, @(local11)), CPtr(SqliteRenameContext Ptr, @(local1)), CPtr(Const Any Ptr, CPtr(Any Ptr, local19->aCol(local14).zCol))))
                        End If
                    c2fb_flow_9:
                        c2fb_temp_37 = local14
                        local14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_37 + 1)))
                    Wend
                    c2fb_flow_8:
                c2fb_flow_7:
                    c2fb_temp_35 = local19->pNextFrom
                    local19 = c2fb_temp_35
                Wend
                c2fb_flow_6:
            End If
        End If
    Else
        If CPtr(SqliteIndex Ptr, local11.pNewIndex) Then
            sqlite3WalkExprList(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local12))), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, CPtr(SqliteIndex Ptr, local11.pNewIndex)->aColExpr)))
            sqlite3WalkExpr(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local12))), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, CPtr(SqliteIndex Ptr, local11.pNewIndex)->pPartIdxWhere)))
        Else
            ' C automatic storage declaration
            c2fb_temp_40 = Cast(SQLITE_C_INT, renameResolveTrigger(CPtr(SqliteParseContext Ptr, @(local11))))
            local10 = c2fb_temp_40
            If (-Cast(SQLITE_C_INT, ((local10 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                Goto c2fb_label_0
            End If
            c2fb_temp_41 = CPtr(SqliteTrigger Ptr, local11.pNewTrigger)->step_list
            local21 = c2fb_temp_41
            While local21
                If CPtr(SqliteSrcListRecord Ptr, local21->pSrc) Then
                    local22 = CPtr(SqliteTable Ptr, sqlite3LocateTableItem(CPtr(Any Ptr, CPtr(SqliteParseContext Ptr, @(local11))), Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, CPtr(SqliteSrcItem Ptr, @(CPtr(SqliteSrcListRecord Ptr, local21->pSrc)->a(Cast(SQLITE_C_INT, &O0ULL)))))))
                    If (-Cast(SQLITE_C_INT, ((local22 = local15)))) Then
                        If CPtr(SqliteUpsert Ptr, local21->pUpsert) Then
                            local23 = CPtr(SqliteExprList Ptr, CPtr(SqliteUpsert Ptr, local21->pUpsert)->pUpsertSet)
                            renameColumnElistNames(CPtr(SqliteParseContext Ptr, @(local11)), CPtr(SqliteRenameContext Ptr, @(local1)), CPtr(Const SqliteExprList Ptr, local23), local9)
                        End If
                        renameColumnIdlistNames(CPtr(SqliteParseContext Ptr, @(local11)), CPtr(SqliteRenameContext Ptr, @(local1)), CPtr(Const SqliteIdList Ptr, CPtr(SqliteIdList Ptr, local21->pIdList)), local9)
                        renameColumnElistNames(CPtr(SqliteParseContext Ptr, @(local11)), CPtr(SqliteRenameContext Ptr, @(local1)), CPtr(Const SqliteExprList Ptr, CPtr(SqliteExprList Ptr, local21->pExprList)), local9)
                    End If
                End If
            c2fb_flow_11:
                c2fb_temp_42 = local21->pNext
                local21 = c2fb_temp_42
            Wend
            c2fb_flow_10:
            If (-Cast(SQLITE_C_INT, ((local11.pTriggerTab = local15)))) Then
                renameColumnIdlistNames(CPtr(SqliteParseContext Ptr, @(local11)), CPtr(SqliteRenameContext Ptr, @(local1)), CPtr(Const SqliteIdList Ptr, CPtr(SqliteIdList Ptr, CPtr(SqliteTrigger Ptr, local11.pNewTrigger)->pColumns)), local9)
            End If
            renameWalkTrigger(CPtr(SqliteWalker Ptr, @(local12)), CPtr(SqliteTrigger Ptr, local11.pNewTrigger))
        End If
    End If
    ' C unused-parameter annotation
    c2fb_temp_43 = Cast(SQLITE_C_INT, renameEditSql(arg0, CPtr(SqliteRenameContext Ptr, @(local1)), local2, local6, local7))
    local10 = c2fb_temp_43
    c2fb_label_0:
    If (-Cast(SQLITE_C_INT, ((local10 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local10 = Cast(SQLITE_C_INT, 1ULL))))) AndAlso sqlite3WritableSchema(CPtr(Any Ptr, local0)))))) Then
            sqlite3_result_value(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg2[Cast(SQLITE_C_INT, &O0ULL)]))
        Else
            If local11.zErrMsg Then
                renameColumnParseError(arg0, StrPtr(!""), arg2[Cast(SQLITE_C_INT, 1ULL)], arg2[Cast(SQLITE_C_INT, 2ULL)], CPtr(SqliteParseContext Ptr, @(local11)))
            Else
                sqlite3_result_error_code(CPtr(Any Ptr, arg0), local10)
            End If
        End If
    End If
    renameParseCleanup(CPtr(SqliteParseContext Ptr, @(local11)))
    renameTokenFree(local0, local1.pList)
    c2fb_temp_44 = @(local0->xAuth)
    c2fb_temp_45 = local16
    (*c2fb_temp_44) = Cast(SqliteAuthorizerCallback, c2fb_temp_45)
    c2fb_temp_45 = CPtr(c2fb_callback_3, (*c2fb_temp_44))
    sqlite3BtreeLeaveAll(local0)
End Sub

Private Sub renameTableFunc CDecl Alias "renameTableFunc" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteVdbeMem Ptr Ptr)
    Dim local0 As sqlite3 Ptr
    Dim local1 As Const ZString Ptr
    Dim local2 As Const ZString Ptr
    Dim local3 As Const ZString Ptr
    Dim local4 As Const ZString Ptr
    Dim local5 As SQLITE_C_INT
    Dim local6 As SqliteParseContext
    Dim local7 As SQLITE_C_INT
    Dim local8 As SQLITE_C_INT
    Dim local9 As SqliteRenameContext
    Dim local10 As SqliteWalker
    Dim local11 As c2fb_callback_3
    Dim c2fb_temp_0 As SqliteAuthorizerCallback Ptr
    Dim c2fb_temp_1 As c2fb_callback_3
    Dim c2fb_temp_2 As Any Ptr
    Dim c2fb_temp_3 As SqliteTable Ptr Ptr
    Dim c2fb_temp_4 As SqliteTable Ptr
    Dim c2fb_temp_5 As Any Ptr
    Dim c2fb_temp_6 As SqliteParseContext Ptr Ptr
    Dim c2fb_temp_7 As SqliteParseContext Ptr
    Dim c2fb_temp_8 As SqliteWalkerExprCallback Ptr
    Dim c2fb_temp_9 As c2fb_callback_85
    Dim c2fb_temp_10 As SqliteWalkerSelectCallback Ptr
    Dim c2fb_temp_11 As c2fb_callback_85
    Dim c2fb_temp_12 As Any Ptr Ptr
    Dim c2fb_temp_13 As SqliteRenameContext Ptr
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim local12 As SQLITE_C_INT
    Dim local13 As SqliteTable Ptr
    Dim local14 As SqliteSelect Ptr
    Dim local15 As SqliteNameContext
    Dim c2fb_temp_15 As Any Ptr
    Dim c2fb_temp_16 As SqliteParseContext Ptr Ptr
    Dim c2fb_temp_17 As SqliteParseContext Ptr
    Dim c2fb_temp_18 As u32 Ptr
    Dim c2fb_temp_19 As SQLITE_C_UINT
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim local16 As SqliteFKey Ptr
    Dim c2fb_temp_21 As SqliteFKey Ptr
    Dim c2fb_temp_22 As SqliteFKey Ptr
    Dim c2fb_temp_23 As SqliteRenameToken Ptr
    Dim c2fb_temp_24 As SqliteTable Ptr Ptr
    Dim c2fb_temp_25 As SqliteTable Ptr
    Dim c2fb_temp_26 As SqliteRenameToken Ptr
    Dim c2fb_temp_27 As SqliteRenameToken Ptr
    Dim local17 As SqliteTrigger Ptr
    Dim local18 As SqliteTriggerStep Ptr
    Dim c2fb_temp_28 As SqliteRenameToken Ptr
    Dim c2fb_temp_29 As SQLITE_C_INT
    Dim c2fb_temp_30 As SqliteTriggerStep Ptr
    Dim c2fb_temp_31 As SqliteTriggerStep Ptr
    Dim local19 As SQLITE_C_INT
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As SQLITE_C_INT
    Dim local20 As SqliteSrcItem Ptr
    Dim c2fb_temp_34 As SqliteRenameToken Ptr
    Dim c2fb_temp_35 As SQLITE_C_INT
    Dim c2fb_temp_36 As SqliteAuthorizerCallback Ptr
    Dim c2fb_temp_37 As c2fb_callback_3

    local0 = CPtr(sqlite3 Ptr, sqlite3_context_db_handle(CPtr(Any Ptr, arg0)))
    local1 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, &O0ULL)])))
    local2 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, 3ULL)])))
    local3 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, 4ULL)])))
    local4 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, 5ULL)])))
    local5 = sqlite3_value_int(arg2[Cast(SQLITE_C_INT, 6ULL)])
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local2 AndAlso local3)))) AndAlso local4)))) Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        local8 = Cast(SQLITE_C_INT, 1ULL)
        ' C automatic storage declaration
        ' C automatic storage declaration
        local11 = CPtr(c2fb_callback_3, local0->xAuth)
        c2fb_temp_0 = @(local0->xAuth)
        c2fb_temp_1 = CPtr(c2fb_callback_3, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_0) = Cast(SqliteAuthorizerCallback, c2fb_temp_1)
        c2fb_temp_1 = CPtr(c2fb_callback_3, (*c2fb_temp_0))
        sqlite3BtreeEnterAll(local0)
        c2fb_temp_2 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteRenameContext Ptr, @(local9))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteRenameContext))))
        c2fb_temp_3 = @(local9.pTab)
        c2fb_temp_4 = CPtr(SqliteTable Ptr, sqlite3FindTable(CPtr(Any Ptr, local0), local3, local1))
        (*c2fb_temp_3) = c2fb_temp_4
        c2fb_temp_5 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local10))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteWalker))))
        c2fb_temp_6 = @(local10.pParse)
        c2fb_temp_7 = CPtr(SqliteParseContext Ptr, @(local6))
        (*c2fb_temp_6) = c2fb_temp_7
        c2fb_temp_8 = @(local10.xExprCallback)
        c2fb_temp_9 = CPtr(c2fb_callback_85, ProcPtr(renameTableExprCb))
        (*c2fb_temp_8) = Cast(SqliteWalkerExprCallback, c2fb_temp_9)
        c2fb_temp_9 = CPtr(c2fb_callback_85, (*c2fb_temp_8))
        c2fb_temp_10 = @(local10.xSelectCallback)
        c2fb_temp_11 = CPtr(c2fb_callback_85, ProcPtr(renameTableSelectCb))
        (*c2fb_temp_10) = Cast(SqliteWalkerSelectCallback, c2fb_temp_11)
        c2fb_temp_11 = CPtr(c2fb_callback_85, (*c2fb_temp_10))
        c2fb_temp_12 = @(local10.u.pRename)
        c2fb_temp_13 = CPtr(SqliteRenameContext Ptr, @(local9))
        (*c2fb_temp_12) = CPtr(Any Ptr, c2fb_temp_13)
        c2fb_temp_13 = CPtr(SqliteRenameContext Ptr, (*c2fb_temp_12))
        c2fb_temp_14 = Cast(SQLITE_C_INT, renameParseSql(CPtr(SqliteParseContext Ptr, @(local6)), local1, local0, local2, local5))
        local7 = c2fb_temp_14
        If (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            local12 = (Cast(sqlite3_uint64, (local0->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &H04000000ULL)))))
            If CPtr(SqliteTable Ptr, local6.pNewTable) Then
                local13 = CPtr(SqliteTable Ptr, local6.pNewTable)
                If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local13)->eTabType) = Cast(SQLITE_C_INT, 2ULL)))))) Then
                    If (-Cast(SQLITE_C_INT, ((local12 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        local14 = CPtr(SqliteSelect Ptr, local13->u.view.pSelect)
                        ' C automatic storage declaration
                        c2fb_temp_15 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local15))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteNameContext))))
                        c2fb_temp_16 = @(local15.pParse)
                        c2fb_temp_17 = CPtr(SqliteParseContext Ptr, @(local6))
                        (*c2fb_temp_16) = c2fb_temp_17
                        ' C unused-parameter annotation
                        c2fb_temp_18 = @(local14->selFlags)
                        c2fb_temp_19 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_18)) And Cast(SQLITE_C_UINT, (Not Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0200000ULL)))))))
                        (*c2fb_temp_18) = Cast(u32, c2fb_temp_19)
                        c2fb_temp_19 = Cast(SQLITE_C_UINT, (*c2fb_temp_18))
                        sqlite3SelectPrep(CPtr(Any Ptr, CPtr(SqliteParseContext Ptr, @(local6))), CPtr(Any Ptr, CPtr(SqliteSelect Ptr, local13->u.view.pSelect)), CPtr(Any Ptr, CPtr(SqliteNameContext Ptr, @(local15))))
                        If local6.nErr Then
                            c2fb_temp_20 = Cast(SQLITE_C_INT, local6.rc)
                            local7 = c2fb_temp_20
                        Else
                            sqlite3WalkSelect(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local10))), CPtr(Any Ptr, CPtr(SqliteSelect Ptr, local13->u.view.pSelect)))
                        End If
                    End If
                Else
                    If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((Cast(sqlite3_uint64, (-Cast(SQLITE_C_INT, ((local12 = Cast(SQLITE_C_INT, &O0ULL)))))) OrElse (Cast(sqlite3_uint64, (local0->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &H00004000ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local13)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))) = 0))))))) Then
                        ' C automatic storage declaration
                        ' C unused-parameter annotation
                        c2fb_temp_21 = local13->u.tab.pFKey
                        local16 = c2fb_temp_21
                        While local16
                            If (-Cast(SQLITE_C_INT, ((sqlite3_stricmp(CPtr(Const ZString Ptr, local16->zTo), local3) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                                c2fb_temp_23 = CPtr(SqliteRenameToken Ptr, renameTokenFind(CPtr(SqliteParseContext Ptr, @(local6)), CPtr(SqliteRenameContext Ptr, @(local9)), CPtr(Const Any Ptr, CPtr(Any Ptr, local16->zTo))))
                            End If
                        c2fb_flow_1:
                            c2fb_temp_22 = local16->pNextFrom
                            local16 = c2fb_temp_22
                        Wend
                        c2fb_flow_0:
                    End If
                    If (-Cast(SQLITE_C_INT, ((sqlite3_stricmp(local3, CPtr(Const ZString Ptr, local13->zName)) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        c2fb_temp_24 = @(local9.pTab)
                        c2fb_temp_25 = local13
                        (*c2fb_temp_24) = c2fb_temp_25
                        If (-Cast(SQLITE_C_INT, ((local12 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                            sqlite3WalkExprList(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local10))), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, local13->pCheck)))
                        End If
                        c2fb_temp_26 = CPtr(SqliteRenameToken Ptr, renameTokenFind(CPtr(SqliteParseContext Ptr, @(local6)), CPtr(SqliteRenameContext Ptr, @(local9)), CPtr(Const Any Ptr, local13->zName)))
                    End If
                End If
            Else
                If CPtr(SqliteIndex Ptr, local6.pNewIndex) Then
                    c2fb_temp_27 = CPtr(SqliteRenameToken Ptr, renameTokenFind(CPtr(SqliteParseContext Ptr, @(local6)), CPtr(SqliteRenameContext Ptr, @(local9)), CPtr(Const Any Ptr, CPtr(SqliteIndex Ptr, local6.pNewIndex)->zName)))
                    If (-Cast(SQLITE_C_INT, ((local12 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        sqlite3WalkExpr(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local10))), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, CPtr(SqliteIndex Ptr, local6.pNewIndex)->pPartIdxWhere)))
                    End If
                Else
                    local17 = CPtr(SqliteTrigger Ptr, local6.pNewTrigger)
                    ' C automatic storage declaration
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = sqlite3_stricmp(CPtr(Const ZString Ptr, CPtr(SqliteTrigger Ptr, local6.pNewTrigger)->table), local3))))) AndAlso (-Cast(SQLITE_C_INT, ((CPtr(SqliteSchema Ptr, local9.pTab->pSchema) = CPtr(SqliteSchema Ptr, local17->pTabSchema))))))))) Then
                        c2fb_temp_28 = CPtr(SqliteRenameToken Ptr, renameTokenFind(CPtr(SqliteParseContext Ptr, @(local6)), CPtr(SqliteRenameContext Ptr, @(local9)), CPtr(Const Any Ptr, CPtr(SqliteTrigger Ptr, local6.pNewTrigger)->table)))
                    End If
                    If (-Cast(SQLITE_C_INT, ((local12 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        c2fb_temp_29 = Cast(SQLITE_C_INT, renameResolveTrigger(CPtr(SqliteParseContext Ptr, @(local6))))
                        local7 = c2fb_temp_29
                        If (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                            renameWalkTrigger(CPtr(SqliteWalker Ptr, @(local10)), local17)
                            c2fb_temp_30 = local17->step_list
                            local18 = c2fb_temp_30
                            While local18
                                If CPtr(SqliteSrcListRecord Ptr, local18->pSrc) Then
                                    ' C automatic storage declaration
                                    c2fb_temp_32 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                                    local19 = c2fb_temp_32
                                    While (-Cast(SQLITE_C_INT, ((local19 < CPtr(SqliteSrcListRecord Ptr, local18->pSrc)->nSrc))))
                                        local20 = CPtr(SqliteSrcItem Ptr, @(CPtr(SqliteSrcListRecord Ptr, local18->pSrc)->a(local19)))
                                        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = sqlite3_stricmp(CPtr(Const ZString Ptr, local20->zName), local3))))) Then
                                            c2fb_temp_34 = CPtr(SqliteRenameToken Ptr, renameTokenFind(CPtr(SqliteParseContext Ptr, @(local6)), CPtr(SqliteRenameContext Ptr, @(local9)), CPtr(Const Any Ptr, local20->zName)))
                                        End If
                                    c2fb_flow_5:
                                        c2fb_temp_33 = local19
                                        local19 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_33 + 1)))
                                    Wend
                                    c2fb_flow_4:
                                End If
                            c2fb_flow_3:
                                c2fb_temp_31 = local18->pNext
                                local18 = c2fb_temp_31
                            Wend
                            c2fb_flow_2:
                        End If
                    End If
                End If
            End If
        End If
        If (-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_35 = Cast(SQLITE_C_INT, renameEditSql(arg0, CPtr(SqliteRenameContext Ptr, @(local9)), local2, local4, local8))
            local7 = c2fb_temp_35
        End If
        If (-Cast(SQLITE_C_INT, ((local7 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, 1ULL))))) AndAlso sqlite3WritableSchema(CPtr(Any Ptr, local0)))))) Then
                sqlite3_result_value(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg2[Cast(SQLITE_C_INT, 3ULL)]))
            Else
                If local6.zErrMsg Then
                    renameColumnParseError(arg0, StrPtr(!""), arg2[Cast(SQLITE_C_INT, 1ULL)], arg2[Cast(SQLITE_C_INT, 2ULL)], CPtr(SqliteParseContext Ptr, @(local6)))
                Else
                    sqlite3_result_error_code(CPtr(Any Ptr, arg0), local7)
                End If
            End If
        End If
        renameParseCleanup(CPtr(SqliteParseContext Ptr, @(local6)))
        renameTokenFree(local0, local9.pList)
        sqlite3BtreeLeaveAll(local0)
        c2fb_temp_36 = @(local0->xAuth)
        c2fb_temp_37 = local11
        (*c2fb_temp_36) = Cast(SqliteAuthorizerCallback, c2fb_temp_37)
        c2fb_temp_37 = CPtr(c2fb_callback_3, (*c2fb_temp_36))
    End If
    Return
End Sub

Private Sub renameQuotefixFunc CDecl Alias "renameQuotefixFunc" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteVdbeMem Ptr Ptr)
    Dim local0 As sqlite3 Ptr
    Dim local1 As Const ZString Ptr
    Dim local2 As Const ZString Ptr
    Dim local3 As c2fb_callback_3
    Dim c2fb_temp_0 As SqliteAuthorizerCallback Ptr
    Dim c2fb_temp_1 As c2fb_callback_3
    Dim local4 As SQLITE_C_INT
    Dim local5 As SqliteParseContext
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim local6 As SqliteRenameContext
    Dim local7 As SqliteWalker
    Dim c2fb_temp_3 As Any Ptr
    Dim c2fb_temp_4 As Any Ptr
    Dim c2fb_temp_5 As SqliteParseContext Ptr Ptr
    Dim c2fb_temp_6 As SqliteParseContext Ptr
    Dim c2fb_temp_7 As SqliteWalkerExprCallback Ptr
    Dim c2fb_temp_8 As c2fb_callback_85
    Dim c2fb_temp_9 As SqliteWalkerSelectCallback Ptr
    Dim c2fb_temp_10 As c2fb_callback_85
    Dim c2fb_temp_11 As Any Ptr Ptr
    Dim c2fb_temp_12 As SqliteRenameContext Ptr
    Dim local8 As SqliteSelect Ptr
    Dim c2fb_temp_13 As u32 Ptr
    Dim c2fb_temp_14 As SQLITE_C_UINT
    Dim c2fb_temp_15 As SQLITE_C_INT Ptr
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SQLITE_C_INT
    Dim local9 As SQLITE_C_INT
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As SQLITE_C_INT
    Dim c2fb_temp_22 As SqliteAuthorizerCallback Ptr
    Dim c2fb_temp_23 As c2fb_callback_3

    local0 = CPtr(sqlite3 Ptr, sqlite3_context_db_handle(CPtr(Any Ptr, arg0)))
    local1 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, &O0ULL)])))
    local2 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, 1ULL)])))
    local3 = CPtr(c2fb_callback_3, local0->xAuth)
    c2fb_temp_0 = @(local0->xAuth)
    c2fb_temp_1 = CPtr(c2fb_callback_3, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_0) = Cast(SqliteAuthorizerCallback, c2fb_temp_1)
    c2fb_temp_1 = CPtr(c2fb_callback_3, (*c2fb_temp_0))
    sqlite3BtreeEnterAll(local0)
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((local1 AndAlso local2)))) Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        c2fb_temp_2 = Cast(SQLITE_C_INT, renameParseSql(CPtr(SqliteParseContext Ptr, @(local5)), local1, local0, local2, Cast(SQLITE_C_INT, &O0ULL)))
        local4 = c2fb_temp_2
        If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            ' C automatic storage declaration
            ' C automatic storage declaration
            c2fb_temp_3 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteRenameContext Ptr, @(local6))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteRenameContext))))
            c2fb_temp_4 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local7))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteWalker))))
            c2fb_temp_5 = @(local7.pParse)
            c2fb_temp_6 = CPtr(SqliteParseContext Ptr, @(local5))
            (*c2fb_temp_5) = c2fb_temp_6
            c2fb_temp_7 = @(local7.xExprCallback)
            c2fb_temp_8 = CPtr(c2fb_callback_85, ProcPtr(renameQuotefixExprCb))
            (*c2fb_temp_7) = Cast(SqliteWalkerExprCallback, c2fb_temp_8)
            c2fb_temp_8 = CPtr(c2fb_callback_85, (*c2fb_temp_7))
            c2fb_temp_9 = @(local7.xSelectCallback)
            c2fb_temp_10 = CPtr(c2fb_callback_85, ProcPtr(renameColumnSelectCb))
            (*c2fb_temp_9) = Cast(SqliteWalkerSelectCallback, c2fb_temp_10)
            c2fb_temp_10 = CPtr(c2fb_callback_85, (*c2fb_temp_9))
            c2fb_temp_11 = @(local7.u.pRename)
            c2fb_temp_12 = CPtr(SqliteRenameContext Ptr, @(local6))
            (*c2fb_temp_11) = CPtr(Any Ptr, c2fb_temp_12)
            c2fb_temp_12 = CPtr(SqliteRenameContext Ptr, (*c2fb_temp_11))
            If CPtr(SqliteTable Ptr, local5.pNewTable) Then
                If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (CPtr(SqliteTable Ptr, local5.pNewTable))->eTabType) = Cast(SQLITE_C_INT, 2ULL)))))) Then
                    local8 = CPtr(SqliteSelect Ptr, CPtr(SqliteTable Ptr, local5.pNewTable)->u.view.pSelect)
                    c2fb_temp_13 = @(local8->selFlags)
                    c2fb_temp_14 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_13)) And Cast(SQLITE_C_UINT, (Not Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0200000ULL)))))))
                    (*c2fb_temp_13) = Cast(u32, c2fb_temp_14)
                    c2fb_temp_14 = Cast(SQLITE_C_UINT, (*c2fb_temp_13))
                    c2fb_temp_15 = @(local5.rc)
                    c2fb_temp_16 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    (*c2fb_temp_15) = c2fb_temp_16
                    sqlite3SelectPrep(CPtr(Any Ptr, CPtr(SqliteParseContext Ptr, @(local5))), CPtr(Any Ptr, local8), Cast(SQLITE_C_INT, &O0ULL))
                    c2fb_temp_17 = Cast(SQLITE_C_INT, (IIf(local0->mallocFailed, Cast(SQLITE_C_INT, 7ULL), local5.rc)))
                    local4 = c2fb_temp_17
                    If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        sqlite3WalkSelect(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local7))), CPtr(Any Ptr, local8))
                    End If
                Else
                    ' C automatic storage declaration
                    sqlite3WalkExprList(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local7))), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, CPtr(SqliteTable Ptr, local5.pNewTable)->pCheck)))
                    c2fb_temp_18 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    local9 = c2fb_temp_18
                    While (-Cast(SQLITE_C_INT, ((local9 < Cast(SQLITE_C_INT, CPtr(SqliteTable Ptr, local5.pNewTable)->nCol)))))
                        sqlite3WalkExpr(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local7))), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, sqlite3ColumnExpr(CPtr(Any Ptr, CPtr(SqliteTable Ptr, local5.pNewTable)), CPtr(Any Ptr, CPtr(SqliteColumn Ptr, @(CPtr(SqliteTable Ptr, local5.pNewTable)->aCol[local9])))))))
                    c2fb_flow_1:
                        c2fb_temp_19 = local9
                        local9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_19 + 1)))
                    Wend
                    c2fb_flow_0:
                End If
            Else
                If CPtr(SqliteIndex Ptr, local5.pNewIndex) Then
                    sqlite3WalkExprList(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local7))), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, CPtr(SqliteIndex Ptr, local5.pNewIndex)->aColExpr)))
                    sqlite3WalkExpr(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local7))), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, CPtr(SqliteIndex Ptr, local5.pNewIndex)->pPartIdxWhere)))
                Else
                    c2fb_temp_20 = Cast(SQLITE_C_INT, renameResolveTrigger(CPtr(SqliteParseContext Ptr, @(local5))))
                    local4 = c2fb_temp_20
                    If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        renameWalkTrigger(CPtr(SqliteWalker Ptr, @(local7)), CPtr(SqliteTrigger Ptr, local5.pNewTrigger))
                    End If
                End If
            End If
            If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_21 = Cast(SQLITE_C_INT, renameEditSql(arg0, CPtr(SqliteRenameContext Ptr, @(local6)), local2, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)))
                local4 = c2fb_temp_21
            End If
            renameTokenFree(local0, local6.pList)
        End If
        If (-Cast(SQLITE_C_INT, ((local4 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            If (-Cast(SQLITE_C_INT, ((sqlite3WritableSchema(CPtr(Any Ptr, local0)) AndAlso (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, 1ULL))))))))) Then
                sqlite3_result_value(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg2[Cast(SQLITE_C_INT, 1ULL)]))
            Else
                sqlite3_result_error_code(CPtr(Any Ptr, arg0), local4)
            End If
        End If
        renameParseCleanup(CPtr(SqliteParseContext Ptr, @(local5)))
    End If
    c2fb_temp_22 = @(local0->xAuth)
    c2fb_temp_23 = local3
    (*c2fb_temp_22) = Cast(SqliteAuthorizerCallback, c2fb_temp_23)
    c2fb_temp_23 = CPtr(c2fb_callback_3, (*c2fb_temp_22))
    sqlite3BtreeLeaveAll(local0)
End Sub

/' Constraint callback bodies referenced by the static FuncDef table '/

Private Sub addConstraintFunc CDecl Alias "addConstraintFunc" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteVdbeMem Ptr Ptr)
    Dim local0 As Const UByte Ptr
    Dim local1 As Const ZString Ptr
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As sqlite3_str Ptr
    Dim local6 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim local7 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As sqlite3_str Ptr

    local0 = CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, &O0ULL)]))
    local1 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, 1ULL)])))
    local2 = sqlite3_value_int(arg2[Cast(SQLITE_C_INT, 2ULL)])
    local3 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    local6 = Cast(SQLITE_C_INT, &O0ULL)
    ' C unused-parameter annotation
    If skipCreateTable(arg0, local0, CPtr(SQLITE_C_INT Ptr, @(local3))) Then
        Return
    End If
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local4 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local4 <= local2)))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local2 < Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local6 <> Cast(SQLITE_C_INT, 23ULL))))))))))))))
        c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local3 + getConstraintToken(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0[local3]))), CPtr(SQLITE_C_INT Ptr, @(local6))))))
        local3 = c2fb_temp_2
        While Cast(SQLITE_C_INT, 1ULL)
            local7 = getConstraintToken(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0[local3]))), CPtr(SQLITE_C_INT Ptr, @(local6)))
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local6 = Cast(SQLITE_C_INT, 25ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local6 = Cast(SQLITE_C_INT, 23ULL))))))))) Then
                Goto c2fb_flow_2
            End If
            If (-Cast(SQLITE_C_INT, ((local6 = Cast(SQLITE_C_INT, 186ULL))))) Then
                sqlite3_result_error_code(CPtr(Any Ptr, arg0), sqlite3CorruptError(Cast(SQLITE_C_INT, 2727ULL)))
                Return
            End If
            c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local3 + local7)))
            local3 = c2fb_temp_3
        c2fb_flow_3:
        Wend
        c2fb_flow_2:
    c2fb_flow_1:
        c2fb_temp_1 = local4
        local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    Wend
    c2fb_flow_0:
    c2fb_temp_4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local3 + getWhitespace(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0[local3])))))))
    local3 = c2fb_temp_4
    c2fb_temp_5 = CPtr(sqlite3_str Ptr, sqlite3_str_new(CPtr(sqlite3 Ptr, sqlite3_context_db_handle(CPtr(Any Ptr, arg0)))))
    local5 = c2fb_temp_5
    sqlite3_str_append(local5, CPtr(Const ZString Ptr, local0), local3)
    If (-Cast(SQLITE_C_INT, ((local2 < Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3_str_append(local5, StrPtr(!","), Cast(SQLITE_C_INT, 1ULL))
    End If
    sqlite3_str_appendf(CPtr(Any Ptr, local5), StrPtr(!" %s%s"), local1, CPtr(UByte Ptr, @(local0[local3])))
    sqlite3_result_str(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local5), Cast(SQLITE_C_INT, 2ULL))
End Sub

Private Sub failConstraintFunc CDecl Alias "failConstraintFunc" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteVdbeMem Ptr Ptr)
    Dim local0 As Const ZString Ptr
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT

    local0 = CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, &O0ULL)])))
    local1 = sqlite3_value_int(arg2[Cast(SQLITE_C_INT, 1ULL)])
    c2fb_temp_0 = arg1
    sqlite3_result_error(CPtr(Any Ptr, arg0), local0, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
    sqlite3_result_error_code(CPtr(Any Ptr, arg0), local1)
End Sub

Private Sub findConstraintFunc CDecl Alias "findConstraintFunc" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteVdbeMem Ptr Ptr)
    Dim local0 As Const UByte Ptr
    Dim local1 As Const UByte Ptr
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As Const UByte Ptr
    Dim c2fb_temp_2 As Const UByte Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    local2 = Cast(SQLITE_C_INT, &O0ULL)
    local3 = Cast(SQLITE_C_INT, &O0ULL)
    c2fb_temp_0 = arg1
    c2fb_temp_1 = CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, &O0ULL)]))
    local0 = c2fb_temp_1
    c2fb_temp_2 = CPtr(Const UByte Ptr, sqlite3_value_text(arg2[Cast(SQLITE_C_INT, 1ULL)]))
    local1 = c2fb_temp_2
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        Return
    End If
    While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, 22ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, 186ULL)))))))))
        c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(sqlite3_int64, (Cast(sqlite3_int64, local2) + sqlite3GetToken(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0[local2]))), CPtr(SQLITE_C_INT Ptr, @(local3))))))
        local2 = c2fb_temp_3
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    While Cast(SQLITE_C_INT, 1ULL)
        c2fb_temp_4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local2 + getConstraintToken(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0[local2]))), CPtr(SQLITE_C_INT Ptr, @(local3))))))
        local2 = c2fb_temp_4
        If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, 120ULL))))) Then
            local4 = Cast(SQLITE_C_INT, &O0ULL)
            local5 = Cast(SQLITE_C_INT, &O0ULL)
            c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local2 + getWhitespace(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0[local2])))))))
            local2 = c2fb_temp_5
            c2fb_temp_6 = Cast(SQLITE_C_INT, getConstraintToken(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0[local2]))), CPtr(SQLITE_C_INT Ptr, @(local3))))
            local4 = c2fb_temp_6
            If quotedCompare(arg0, local3, CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0[local2]))), local4, local1, CPtr(SQLITE_C_INT Ptr, @(local5))) Then
                Return
            End If
            If (-Cast(SQLITE_C_INT, ((local5 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                sqlite3_result_int(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 1ULL))
                Return
            End If
        Else
            If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, 186ULL))))) Then
                Goto c2fb_flow_2
            End If
        End If
    c2fb_flow_3:
    Wend
    c2fb_flow_2:
    sqlite3_result_int(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, &O0ULL))
End Sub

Sub sqlite3AlterFunctions CDecl Alias "sqlite3AlterFunctions" ()
    Static local0(0 To 8) As SqliteFuncDef = { _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 9ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H00040000ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(renameColumnFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"sqlite_rename_column"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 7ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H00040000ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(renameTableFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"sqlite_rename_table"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 7ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H00040000ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(renameTableTest), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"sqlite_rename_test"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 3ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H00040000ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(dropColumnFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"sqlite_drop_column"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H00040000ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(renameQuotefixFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"sqlite_rename_quotefix"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H00040000ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(dropConstraintFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"sqlite_drop_constraint"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H00040000ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(failConstraintFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"sqlite_fail"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 3ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H00040000ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(addConstraintFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"sqlite_add_constraint"), Cast(Any Ptr, 0) ), _
        Type<SqliteFuncDef>( Cast(SQLITE_C_INT, 2ULL), Cast(u16, 0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H00040000ULL))) Or Cast(SQLITE_C_INT, 1ULL))) Or Cast(SQLITE_C_INT, &H0800ULL))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), ProcPtr(findConstraintFunc), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"sqlite_find_constraint"), Cast(Any Ptr, 0) )}

    ' C static array storage
    sqlite3InsertBuiltinFuncs(CPtr(Any Ptr, CPtr(SqliteFuncDef Ptr, (@local0(0)))), (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, (9ULL * SizeOf(SqliteFuncDef)))) \ Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteFuncDef)))))))))
End Sub

/' end of sqlite3_bulk_alter_rename_add.bas '/
