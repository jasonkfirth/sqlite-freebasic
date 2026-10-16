/'
** 2004 April 6
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
*************************************************************************
** This file implements an external (disk-based) database using BTrees.
** See the header comment on "btreeInt.h" for additional information.
** Including a description of file format and an overview of operation.
'/

/'
    Project: SQLite FreeBASIC port
    File: sqlite3_bulk_btree_maintenance.bas

    Purpose:

        Build B-tree cells, maintain auto-vacuum page maps, and change roots.

    Responsibilities:

        - Serialize payloads into table and index cells.
        - Move pages and maintain pointer-map references.
        - Calculate auto-vacuum targets and remove free pages.
        - Create and drop table/index roots while saving cursor positions.

    This file intentionally does NOT contain:

        - B-tree handle lifecycle, basic page access, or transaction policy.
        - Shared-cache table locking or runtime behavior tests.
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

#include once "sqlite3_pcache.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_varint.bi"
#include once "sqlite3_pager.bi"
#include once "sqlite3_btree.bi"
#include once "sqlite3_bitvec.bi"
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

Type c2fb_callback_1 As Sub CDecl()
Type c2fb_callback_8 As Sub CDecl(ByVal arg0 As Any Ptr)
Type c2fb_callback_15 As Function CDecl(ByVal arg0 As Any Ptr, ByVal arg1 As Const ZString Ptr, ByVal arg2 As SQLITE_C_UINT, ByVal arg3 As SQLITE_C_UINT, ByVal arg4 As SQLITE_C_UINT) As SQLITE_C_UINT
Type c2fb_callback_87 As Function CDecl(ByVal arg0 As Any Ptr, ByVal arg1 As UByte Ptr) As UShort
Type c2fb_callback_88 As Sub CDecl(ByVal arg0 As Any Ptr, ByVal arg1 As UByte Ptr, ByVal arg2 As Any Ptr)

Declare Sub invalidateAllOverflowCache CDecl Alias "invalidateAllOverflowCache" (ByVal arg0 As BtShared Ptr)
Declare Function btreeSetHasContent CDecl Alias "btreeSetHasContent" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT) As SQLITE_C_INT
Declare Sub btreeReleaseAllCursorPages CDecl Alias "btreeReleaseAllCursorPages" (ByVal arg0 As BtCursor Ptr)
Declare Function saveCursorKey CDecl Alias "saveCursorKey" (ByVal arg0 As BtCursor Ptr) As SQLITE_C_INT
Declare Function saveCursorPosition CDecl Alias "saveCursorPosition" (ByVal arg0 As BtCursor Ptr) As SQLITE_C_INT
Declare Function saveAllCursors CDecl Alias "saveAllCursors" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As BtCursor Ptr) As SQLITE_C_INT
Declare Function saveCursorsOnList CDecl Alias "saveCursorsOnList" (ByVal arg0 As BtCursor Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As BtCursor Ptr) As SQLITE_C_INT
Declare Sub ptrmapPut CDecl Alias "ptrmapPut" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As UByte, ByVal arg3 As SQLITE_C_UINT, ByVal arg4 As SQLITE_C_INT Ptr)
Declare Function ptrmapGet CDecl Alias "ptrmapGet" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As UByte Ptr, ByVal arg3 As SQLITE_C_UINT Ptr) As SQLITE_C_INT
Declare Function decodeFlags CDecl Alias "decodeFlags" (ByVal arg0 As MemPage Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub zeroPage CDecl Alias "zeroPage" (ByVal arg0 As MemPage Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Function btreeGetPage CDecl Alias "btreeGetPage" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As MemPage Ptr Ptr, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function btreePageLookup CDecl Alias "btreePageLookup" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT) As MemPage Ptr
Declare Function btreeGetUnusedPage CDecl Alias "btreeGetUnusedPage" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As MemPage Ptr Ptr, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function relocatePage CDecl Alias "relocatePage" (ByVal arg0 As BtShared Ptr, ByVal arg1 As MemPage Ptr, ByVal arg2 As UByte, ByVal arg3 As SQLITE_C_UINT, ByVal arg4 As SQLITE_C_UINT, ByVal arg5 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function incrVacuumStep CDecl Alias "incrVacuumStep" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As SQLITE_C_UINT, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function finalDbSize CDecl Alias "finalDbSize" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As SQLITE_C_UINT) As SQLITE_C_UINT
Declare Function autoVacuumCommit CDecl Alias "autoVacuumCommit" (ByVal arg0 As Btree Ptr) As SQLITE_C_INT
Declare Function allocateBtreePage CDecl Alias "allocateBtreePage" (ByVal arg0 As BtShared Ptr, ByVal arg1 As MemPage Ptr Ptr, ByVal arg2 As SQLITE_C_UINT Ptr, ByVal arg3 As SQLITE_C_UINT, ByVal arg4 As UByte) As SQLITE_C_INT
Declare Function freePage2 CDecl Alias "freePage2" (ByVal arg0 As BtShared Ptr, ByVal arg1 As MemPage Ptr, ByVal arg2 As SQLITE_C_UINT) As SQLITE_C_INT
Declare Sub freePage CDecl Alias "freePage" (ByVal arg0 As MemPage Ptr, ByVal arg1 As SQLITE_C_INT Ptr)
Declare Function fillInCell CDecl Alias "fillInCell" (ByVal arg0 As MemPage Ptr, ByVal arg1 As UByte Ptr, ByVal arg2 As Const SqliteBtreePayload Ptr, ByVal arg3 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function btreeCreateTable CDecl Alias "btreeCreateTable" (ByVal arg0 As Btree Ptr, ByVal arg1 As SQLITE_C_UINT Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function btreeDropTable CDecl Alias "btreeDropTable" (ByVal arg0 As Btree Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As SQLITE_C_INT Ptr) As SQLITE_C_INT
Declare Function c2fb_crt_memcpy CDecl Alias "memcpy" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_SIZE_T) As Any Ptr
Declare Function c2fb_crt_memset CDecl Alias "memset" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_SIZE_T) As Any Ptr
' c2fb skipped __bswap_16: outside the supported subset
' c2fb skipped __bswap_32: outside the supported subset
' c2fb skipped __bswap_64: outside the supported subset
' c2fb skipped __uint16_identity: outside the supported subset
' c2fb skipped __uint32_identity: outside the supported subset
' c2fb skipped __uint64_identity: outside the supported subset
' c2fb skipped sqlite3IsBinary: FreeBASIC body already exists
' c2fb skipped sqlite3_enable_shared_cache: outside the supported subset
' c2fb skipped querySharedCacheTableLock: outside the supported subset
' c2fb skipped setSharedCacheTableLock: outside the supported subset
' c2fb skipped clearAllSharedCacheTableLocks: outside the supported subset
' c2fb skipped downgradeAllSharedCacheTableLocks: outside the supported subset

' c2fb skipped invalidateIncrblobCursors: outside the supported subset

' c2fb skipped btreeGetHasContent: outside the supported subset
' c2fb skipped btreeClearHasContent: outside the supported subset





' c2fb skipped sqlite3BtreeClearCursor: FreeBASIC body already exists
' c2fb skipped btreeMoveto: outside the supported subset
' c2fb skipped btreeRestoreCursorPosition: outside the supported subset
' c2fb skipped sqlite3BtreeCursorHasMoved: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeFakeValidCursor: outside the supported subset
' c2fb skipped sqlite3BtreeCursorRestore: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeCursorHintFlags: FreeBASIC body already exists
' c2fb skipped ptrmapPageno: FreeBASIC body already exists


' c2fb skipped btreeParseCellAdjustSizeForOverflow: outside the supported subset
' c2fb skipped btreePayloadToLocal: outside the supported subset
' c2fb skipped btreeParseCellPtrNoPayload: FreeBASIC body already exists
' c2fb skipped btreeParseCellPtr: FreeBASIC body already exists
' c2fb skipped btreeParseCellPtrIndex: FreeBASIC body already exists
' c2fb skipped btreeParseCell: outside the supported subset
' c2fb skipped cellSizePtr: FreeBASIC body already exists
' c2fb skipped cellSizePtrIdxLeaf: FreeBASIC body already exists
' c2fb skipped cellSizePtrNoPayload: FreeBASIC body already exists
' c2fb skipped cellSizePtrTableLeaf: FreeBASIC body already exists
' c2fb skipped ptrmapPutOvflPtr: outside the supported subset
' c2fb skipped defragmentPage: outside the supported subset
' c2fb skipped pageFindSlot: outside the supported subset
' c2fb skipped allocateSpace: outside the supported subset
' c2fb skipped freeSpace: outside the supported subset

' c2fb skipped btreeComputeFreeSpace: outside the supported subset
' c2fb skipped btreeCellSizeCheck: outside the supported subset
' c2fb skipped btreeInitPage: FreeBASIC body already exists

' c2fb skipped btreePageFromDbPage: FreeBASIC body already exists


' c2fb skipped btreePagecount: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeLastPage: FreeBASIC body already exists
' c2fb skipped getAndInitPage: outside the supported subset
' c2fb skipped releasePageNotNull: FreeBASIC body already exists
' c2fb skipped releasePage: FreeBASIC body already exists
' c2fb skipped releasePageOne: outside the supported subset

' c2fb skipped pageReinit: outside the supported subset
' c2fb skipped btreeInvokeBusyHandler: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeOpen: FreeBASIC body already exists
' c2fb skipped removeFromSharingList: outside the supported subset
' c2fb skipped allocateTempSpace: outside the supported subset
' c2fb skipped freeTempSpace: outside the supported subset
' c2fb skipped sqlite3BtreeClose: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeSetCacheSize: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeSetSpillSize: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeSetMmapLimit: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeSetPagerFlags: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeSetPageSize: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeGetPageSize: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeGetReserveNoMutex: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeGetRequestedReserve: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeMaxPageCount: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeSecureDelete: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeSetAutoVacuum: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeGetAutoVacuum: FreeBASIC body already exists
' c2fb skipped lockBtree: FreeBASIC body already exists
' c2fb skipped unlockBtreeIfUnused: outside the supported subset
' c2fb skipped newDatabase: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeNewDb: FreeBASIC body already exists
' c2fb skipped btreeBeginTrans: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeBeginTrans: FreeBASIC body already exists
' c2fb skipped setChildPtrmaps: FreeBASIC body already exists
' c2fb skipped modifyPagePointer: outside the supported subset



' c2fb skipped sqlite3BtreeIncrVacuum: FreeBASIC body already exists

' c2fb skipped sqlite3BtreeCommitPhaseOne: FreeBASIC body already exists
' c2fb skipped btreeEndTransaction: outside the supported subset
' c2fb skipped sqlite3BtreeCommitPhaseTwo: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeCommit: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeTripAllCursors: FreeBASIC body already exists
' c2fb skipped btreeSetNPage: outside the supported subset
' c2fb skipped sqlite3BtreeRollback: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeBeginStmt: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeSavepoint: FreeBASIC body already exists
' c2fb skipped btreeCursor: outside the supported subset
' c2fb skipped btreeCursorWithLock: outside the supported subset
' c2fb skipped sqlite3BtreeCursor: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeCursorSize: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeCursorZero: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeCloseCursor: FreeBASIC body already exists
' c2fb skipped getCellInfo: outside the supported subset
' c2fb skipped sqlite3BtreeCursorIsValidNN: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeIntegerKey: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeCursorPin: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeCursorUnpin: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeOffset: FreeBASIC body already exists
' c2fb skipped sqlite3BtreePayloadSize: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeMaxRecordSize: FreeBASIC body already exists
' c2fb skipped getOverflowPage: outside the supported subset
' c2fb skipped copyPayload: outside the supported subset
' c2fb skipped accessPayload: outside the supported subset
' c2fb skipped sqlite3BtreePayload: FreeBASIC body already exists
' c2fb skipped accessPayloadChecked: outside the supported subset
' c2fb skipped sqlite3BtreePayloadChecked: FreeBASIC body already exists
' c2fb skipped fetchPayload: outside the supported subset
' c2fb skipped sqlite3BtreePayloadFetch: FreeBASIC body already exists
' c2fb skipped moveToChild: outside the supported subset
' c2fb skipped moveToParent: outside the supported subset
' c2fb skipped moveToRoot: outside the supported subset
' c2fb skipped moveToLeftmost: outside the supported subset
' c2fb skipped moveToRightmost: outside the supported subset
' c2fb skipped sqlite3BtreeFirst: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeIsEmpty: FreeBASIC body already exists
' c2fb skipped btreeLast: outside the supported subset
' c2fb skipped sqlite3BtreeLast: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeTableMoveto: FreeBASIC body already exists
' c2fb skipped indexCellCompare: outside the supported subset
' c2fb skipped cursorOnLastPage: outside the supported subset
' c2fb skipped sqlite3BtreeIndexMoveto: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeEof: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeRowCountEst: FreeBASIC body already exists
' c2fb skipped btreeNext: outside the supported subset
' c2fb skipped sqlite3BtreeNext: FreeBASIC body already exists
' c2fb skipped btreePrevious: outside the supported subset
' c2fb skipped sqlite3BtreePrevious: FreeBASIC body already exists



' c2fb skipped clearCellOverflow: outside the supported subset

' c2fb skipped dropCell: outside the supported subset
' c2fb skipped insertCell: outside the supported subset
' c2fb skipped insertCellFast: outside the supported subset
' c2fb skipped populateCellCache: outside the supported subset
' c2fb skipped computeCellSize: outside the supported subset
' c2fb skipped cachedCellSize: outside the supported subset
' c2fb skipped rebuildPage: outside the supported subset
' c2fb skipped pageInsertArray: outside the supported subset
' c2fb skipped pageFreeArray: outside the supported subset
' c2fb skipped editPage: outside the supported subset
' c2fb skipped balance_quick: outside the supported subset
' c2fb skipped copyNodeContent: outside the supported subset
' c2fb skipped balance_nonroot: outside the supported subset
' c2fb skipped balance_deeper: outside the supported subset
' c2fb skipped anotherValidCursor: outside the supported subset
' c2fb skipped balance: outside the supported subset
' c2fb skipped btreeOverwriteContent: outside the supported subset
' c2fb skipped btreeOverwriteOverflowCell: outside the supported subset
' c2fb skipped btreeOverwriteCell: outside the supported subset
' c2fb skipped sqlite3BtreeInsert: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeTransferRow: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeDelete: FreeBASIC body already exists

' c2fb skipped sqlite3BtreeCreateTable: FreeBASIC body already exists
' c2fb skipped clearDatabasePage: outside the supported subset
' c2fb skipped sqlite3BtreeClearTable: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeClearTableOfCursor: FreeBASIC body already exists

' c2fb skipped sqlite3BtreeDropTable: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeGetMeta: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeUpdateMeta: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeCount: FreeBASIC body already exists
' c2fb skipped sqlite3BtreePager: FreeBASIC body already exists
' c2fb skipped checkOom: outside the supported subset
' c2fb skipped checkProgress: outside the supported subset
' c2fb skipped checkAppendMsg: outside the supported subset
' c2fb skipped getPageReferenced: outside the supported subset
' c2fb skipped setPageReferenced: outside the supported subset
' c2fb skipped checkRef: outside the supported subset
' c2fb skipped checkPtrmap: outside the supported subset
' c2fb skipped checkList: outside the supported subset
' c2fb skipped btreeHeapInsert: outside the supported subset
' c2fb skipped btreeHeapPull: outside the supported subset
' c2fb skipped checkTreePage: outside the supported subset
' c2fb skipped sqlite3BtreeIntegrityCheck: outside the supported subset
' c2fb skipped sqlite3BtreeGetFilename: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeGetJournalname: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeTxnState: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeCheckpoint: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeIsInBackup: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeSchema: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeSchemaLocked: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeLockTable: FreeBASIC body already exists
' c2fb skipped sqlite3BtreePutData: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeIncrblobCursor: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeSetVersion: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeCursorHasHint: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeIsReadonly: FreeBASIC body already exists
' c2fb skipped sqlite3HeaderSizeBtree: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeClearCache: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeSharable: FreeBASIC body already exists
' c2fb skipped sqlite3BtreeConnectionCount: FreeBASIC body already exists


Private Sub invalidateAllOverflowCache CDecl Alias "invalidateAllOverflowCache" (ByVal arg0 As BtShared Ptr)
    Dim local0 As BtCursor Ptr
    Dim c2fb_temp_0 As BtCursor Ptr
    Dim c2fb_temp_1 As BtCursor Ptr
    Dim c2fb_temp_2 As u8 Ptr
    Dim c2fb_temp_3 As UByte
    Dim c2fb_temp_4 As UByte

    ' C automatic storage declaration
    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(BtCursor Ptr, arg0->pCursor)
    local0 = c2fb_temp_0
    While local0
        c2fb_temp_2 = CPtr(u8 Ptr, @(local0->curFlags))
        c2fb_temp_3 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_2))) And Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, &H04ULL))))))
        (*c2fb_temp_2) = Cast(u8, c2fb_temp_3)
        c2fb_temp_3 = Cast(UByte, (*c2fb_temp_2))
        c2fb_temp_4 = (c2fb_temp_3)
    c2fb_flow_1:
        c2fb_temp_1 = local0->pNext
        local0 = c2fb_temp_1
    Wend
    c2fb_flow_0:
End Sub

Private Function btreeSetHasContent CDecl Alias "btreeSetHasContent" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As Any Ptr Ptr
    Dim c2fb_temp_1 As Any Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    If (-Cast(SQLITE_C_INT, (arg0->pHasContent = 0))) Then
        ' C unused-parameter annotation
        c2fb_temp_0 = CPtr(Any Ptr Ptr, @(arg0->pHasContent))
        c2fb_temp_1 = CPtr(Any Ptr, sqlite3BitvecCreate(arg0->nPage))
        (*c2fb_temp_0) = c2fb_temp_1
        If (-Cast(SQLITE_C_INT, (arg0->pHasContent = 0))) Then
            c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 7ULL))
            local0 = c2fb_temp_2
        End If
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((arg1 <= sqlite3BitvecSize(arg0->pHasContent))))))))) Then
        c2fb_temp_3 = Cast(SQLITE_C_INT, sqlite3BitvecSet(arg0->pHasContent, arg1))
        local0 = c2fb_temp_3
    End If
    Return local0
End Function

Private Sub btreeReleaseAllCursorPages CDecl Alias "btreeReleaseAllCursorPages" (ByVal arg0 As BtCursor Ptr)
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As Byte Ptr
    Dim c2fb_temp_3 As Byte

    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->iPage) >= Cast(SQLITE_C_INT, &O0ULL))))) Then
        c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local0 = c2fb_temp_0
        While (-Cast(SQLITE_C_INT, ((local0 < Cast(SQLITE_C_INT, arg0->iPage)))))
            releasePageNotNull(arg0->apPage(local0))
        c2fb_flow_1:
            c2fb_temp_1 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
        Wend
        c2fb_flow_0:
        releasePageNotNull(arg0->pPage)
        c2fb_temp_2 = CPtr(Byte Ptr, @(arg0->iPage))
        c2fb_temp_3 = Cast(Byte, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
        (*c2fb_temp_2) = c2fb_temp_3
    End If
End Sub

Private Function saveCursorKey CDecl Alias "saveCursorKey" (ByVal arg0 As BtCursor Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As i64 Ptr
    Dim c2fb_temp_1 As sqlite3_int64
    Dim local1 As Any Ptr
    Dim c2fb_temp_2 As i64 Ptr
    Dim c2fb_temp_3 As sqlite3_int64
    Dim c2fb_temp_4 As Any Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As Any Ptr
    Dim c2fb_temp_7 As Any Ptr Ptr
    Dim c2fb_temp_8 As Any Ptr
    Dim c2fb_temp_9 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If arg0->curIntKey Then
        c2fb_temp_0 = CPtr(i64 Ptr, @(arg0->nKey))
        c2fb_temp_1 = Cast(sqlite3_int64, sqlite3BtreeIntegerKey(arg0))
        (*c2fb_temp_0) = Cast(i64, c2fb_temp_1)
        c2fb_temp_1 = Cast(sqlite3_int64, (*c2fb_temp_0))
    Else
        ' C automatic storage declaration
        c2fb_temp_2 = CPtr(i64 Ptr, @(arg0->nKey))
        c2fb_temp_3 = Cast(sqlite3_int64, sqlite3BtreePayloadSize(arg0))
        (*c2fb_temp_2) = Cast(i64, c2fb_temp_3)
        c2fb_temp_3 = Cast(sqlite3_int64, (*c2fb_temp_2))
        c2fb_temp_4 = CPtr(Any Ptr, sqlite3Malloc(Cast(sqlite3_int64, (Cast(sqlite3_int64, ((Cast(sqlite3_int64, arg0->nKey)) + Cast(sqlite3_int64, Cast(SQLITE_C_INT, 9ULL)))) + Cast(sqlite3_int64, Cast(SQLITE_C_INT, 8ULL))))))
        local1 = c2fb_temp_4
        If local1 Then
            c2fb_temp_5 = Cast(SQLITE_C_INT, sqlite3BtreePayload(arg0, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, arg0->nKey), local1))
            local0 = c2fb_temp_5
            If (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_6 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(UByte Ptr, ((CPtr(UByte Ptr, local1)) + arg0->nKey))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 9ULL) + Cast(SQLITE_C_INT, 8ULL)))))
                c2fb_temp_7 = CPtr(Any Ptr Ptr, @(arg0->pKey))
                c2fb_temp_8 = local1
                (*c2fb_temp_7) = c2fb_temp_8
            Else
                sqlite3_free(local1)
            End If
        Else
            c2fb_temp_9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 7ULL))
            local0 = c2fb_temp_9
        End If
    End If
    ' C unused-parameter annotation
    Return local0
End Function

Private Function saveCursorPosition CDecl Alias "saveCursorPosition" (ByVal arg0 As BtCursor Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As u8 Ptr
    Dim c2fb_temp_1 As UByte
    Dim c2fb_temp_2 As SQLITE_C_INT Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As u8 Ptr
    Dim c2fb_temp_6 As UByte
    Dim c2fb_temp_7 As u8 Ptr
    Dim c2fb_temp_8 As UByte

    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->curFlags) And Cast(SQLITE_C_INT, &H40ULL))) Then
        Return (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 19ULL) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 11ULL) Shl Cast(SQLITE_C_INT, 8ULL)))))))
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->eState) = Cast(SQLITE_C_INT, 2ULL))))) Then
        c2fb_temp_0 = CPtr(u8 Ptr, @(arg0->eState))
        c2fb_temp_1 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_0) = Cast(u8, c2fb_temp_1)
        c2fb_temp_1 = Cast(UByte, (*c2fb_temp_0))
    Else
        c2fb_temp_2 = CPtr(SQLITE_C_INT Ptr, @(arg0->skipNext))
        c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_2) = c2fb_temp_3
    End If
    c2fb_temp_4 = Cast(SQLITE_C_INT, saveCursorKey(arg0))
    local0 = c2fb_temp_4
    If (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        btreeReleaseAllCursorPages(arg0)
        c2fb_temp_5 = CPtr(u8 Ptr, @(arg0->eState))
        c2fb_temp_6 = Cast(UByte, Cast(SQLITE_C_INT, 3ULL))
        (*c2fb_temp_5) = Cast(u8, c2fb_temp_6)
        c2fb_temp_6 = Cast(UByte, (*c2fb_temp_5))
    End If
    c2fb_temp_7 = CPtr(u8 Ptr, @(arg0->curFlags))
    c2fb_temp_8 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_7))) And Cast(SQLITE_C_INT, (Not (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H02ULL) Or Cast(SQLITE_C_INT, &H04ULL))) Or Cast(SQLITE_C_INT, &H08ULL)))))))))
    (*c2fb_temp_7) = Cast(u8, c2fb_temp_8)
    c2fb_temp_8 = Cast(UByte, (*c2fb_temp_7))
    Return local0
End Function

Private Function saveAllCursors CDecl Alias "saveAllCursors" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As BtCursor Ptr) As SQLITE_C_INT
    Dim local0 As BtCursor Ptr
    Dim c2fb_temp_0 As BtCursor Ptr
    Dim c2fb_temp_1 As BtCursor Ptr
    Dim c2fb_temp_2 As u8 Ptr
    Dim c2fb_temp_3 As UByte

    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(BtCursor Ptr, arg0->pCursor)
    local0 = c2fb_temp_0
    While local0
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local0 <> arg2)))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)) = arg1)))) OrElse (-Cast(SQLITE_C_INT, ((local0->pgnoRoot = arg1))))))))))))) Then
            Goto c2fb_flow_0
        End If
    c2fb_flow_1:
        c2fb_temp_1 = local0->pNext
        local0 = c2fb_temp_1
    Wend
    c2fb_flow_0:
    If local0 Then
        Return saveCursorsOnList(local0, arg1, arg2)
    End If
    If arg2 Then
        c2fb_temp_2 = CPtr(u8 Ptr, @(arg2->curFlags))
        c2fb_temp_3 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UByte, (*c2fb_temp_2))) And Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, &H20ULL))))))
        (*c2fb_temp_2) = Cast(u8, c2fb_temp_3)
        c2fb_temp_3 = Cast(UByte, (*c2fb_temp_2))
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function saveCursorsOnList CDecl Alias "saveCursorsOnList" (ByVal arg0 As BtCursor Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As BtCursor Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As BtCursor Ptr

    Do
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg0 <> arg2)))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)) = arg1)))) OrElse (-Cast(SQLITE_C_INT, ((arg0->pgnoRoot = arg1))))))))))))) Then
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->eState) = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->eState) = Cast(SQLITE_C_INT, 2ULL))))))))) Then
                local0 = saveCursorPosition(arg0)
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) <> local0)))) Then
                    Return local0
                End If
            Else
                ' empty C statement
                btreeReleaseAllCursorPages(arg0)
            End If
        End If
        c2fb_temp_0 = arg0->pNext
        arg0 = c2fb_temp_0
    c2fb_flow_1:
    Loop While arg0
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Sub ptrmapPut CDecl Alias "ptrmapPut" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As UByte, ByVal arg3 As SQLITE_C_UINT, ByVal arg4 As SQLITE_C_INT Ptr)
    Dim local0 As PgHdr Ptr
    Dim local1 As UByte Ptr
    Dim local2 As SQLITE_C_UINT
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_UINT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As UByte Ptr
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT Ptr
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As UByte Ptr
    Dim c2fb_temp_16 As UByte

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    If (*arg4) Then
        Return
    End If
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((arg1 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
        c2fb_temp_0 = CPtr(SQLITE_C_INT Ptr, @((*arg4)))
        c2fb_temp_1 = Cast(SQLITE_C_INT, sqlite3CorruptError(Cast(SQLITE_C_INT, 1102ULL)))
        (*c2fb_temp_0) = c2fb_temp_1
        Return
    End If
    c2fb_temp_2 = Cast(SQLITE_C_UINT, ptrmapPageno(arg0, arg1))
    local2 = c2fb_temp_2
    c2fb_temp_3 = Cast(SQLITE_C_INT, sqlite3PagerGet(arg0->pPager, local2, CPtr(PgHdr Ptr Ptr, @(local0)), Cast(SQLITE_C_INT, &O0ULL)))
    local4 = c2fb_temp_3
    If (-Cast(SQLITE_C_INT, ((local4 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        c2fb_temp_4 = CPtr(SQLITE_C_INT Ptr, @((*arg4)))
        c2fb_temp_5 = Cast(SQLITE_C_INT, local4)
        (*c2fb_temp_4) = c2fb_temp_5
        Return
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(Byte Ptr, (CPtr(ZString Ptr, CPtr(Any Ptr, sqlite3PagerGetExtra(local0)))))[Cast(SQLITE_C_INT, &O0ULL)]) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        c2fb_temp_6 = CPtr(SQLITE_C_INT Ptr, @((*arg4)))
        c2fb_temp_7 = Cast(SQLITE_C_INT, sqlite3CorruptError(Cast(SQLITE_C_INT, 1115ULL)))
        (*c2fb_temp_6) = c2fb_temp_7
        Goto c2fb_label_0
    End If
    c2fb_temp_8 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 5ULL)) * (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (arg1 - local2)) - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))))))
    local3 = c2fb_temp_8
    If (-Cast(SQLITE_C_INT, ((local3 < Cast(SQLITE_C_INT, &O0ULL))))) Then
        c2fb_temp_9 = CPtr(SQLITE_C_INT Ptr, @((*arg4)))
        c2fb_temp_10 = Cast(SQLITE_C_INT, sqlite3CorruptError(Cast(SQLITE_C_INT, 1120ULL)))
        (*c2fb_temp_9) = c2fb_temp_10
        Goto c2fb_label_0
    End If
    ' C unused-parameter annotation
    c2fb_temp_11 = CPtr(UByte Ptr, CPtr(Any Ptr, sqlite3PagerGetData(local0)))
    local1 = c2fb_temp_11
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg2) <> Cast(SQLITE_C_INT, local1[local3]))))) OrElse (-Cast(SQLITE_C_INT, ((sqlite3Get4byte(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local1[Cast(SQLITE_C_INT, (local3 + Cast(SQLITE_C_INT, 1ULL)))])))) <> arg3)))))))) Then
        ' empty C statement
        c2fb_temp_13 = CPtr(SQLITE_C_INT Ptr, @((*arg4)))
        c2fb_temp_12 = Cast(SQLITE_C_INT, sqlite3PagerWrite(local0))
        local4 = c2fb_temp_12
        c2fb_temp_14 = Cast(SQLITE_C_INT, c2fb_temp_12)
        (*c2fb_temp_13) = c2fb_temp_14
        If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_15 = CPtr(UByte Ptr, @(local1[local3]))
            c2fb_temp_16 = Cast(UByte, arg2)
            (*c2fb_temp_15) = c2fb_temp_16
            sqlite3Put4byte(CPtr(UByte Ptr, @(local1[Cast(SQLITE_C_INT, (local3 + Cast(SQLITE_C_INT, 1ULL)))])), arg3)
        End If
    End If
    c2fb_label_0:
    sqlite3PagerUnref(local0)
End Sub

Private Function ptrmapGet CDecl Alias "ptrmapGet" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As UByte Ptr, ByVal arg3 As SQLITE_C_UINT Ptr) As SQLITE_C_INT
    Dim local0 As PgHdr Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As UByte Ptr
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As UByte Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As UByte Ptr
    Dim c2fb_temp_5 As UByte
    Dim c2fb_temp_6 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_7 As SQLITE_C_UINT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, ptrmapPageno(arg0, arg1))
    local1 = c2fb_temp_0
    c2fb_temp_1 = Cast(SQLITE_C_INT, sqlite3PagerGet(arg0->pPager, local1, CPtr(PgHdr Ptr Ptr, @(local0)), Cast(SQLITE_C_INT, &O0ULL)))
    local4 = c2fb_temp_1
    If (-Cast(SQLITE_C_INT, ((local4 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return local4
    End If
    c2fb_temp_2 = CPtr(UByte Ptr, CPtr(Any Ptr, sqlite3PagerGetData(local0)))
    local2 = c2fb_temp_2
    c2fb_temp_3 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 5ULL)) * (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (arg1 - Cast(SQLITE_C_UINT, local1))) - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))))))
    local3 = c2fb_temp_3
    If (-Cast(SQLITE_C_INT, ((local3 < Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3PagerUnref(local0)
        Return sqlite3CorruptError(Cast(SQLITE_C_INT, 1165ULL))
    End If
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_4 = CPtr(UByte Ptr, @((*arg2)))
    c2fb_temp_5 = Cast(UByte, local2[local3])
    (*c2fb_temp_4) = c2fb_temp_5
    If arg3 Then
        c2fb_temp_6 = CPtr(SQLITE_C_UINT Ptr, @((*arg3)))
        c2fb_temp_7 = Cast(SQLITE_C_UINT, sqlite3Get4byte(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local2[Cast(SQLITE_C_INT, (local3 + Cast(SQLITE_C_INT, 1ULL)))])))))
        (*c2fb_temp_6) = c2fb_temp_7
    End If
    sqlite3PagerUnref(local0)
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (*arg2)) < Cast(SQLITE_C_INT, 1ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (*arg2)) > Cast(SQLITE_C_INT, 5ULL))))))))) Then
        Return sqlite3CorruptError(Cast(SQLITE_C_INT, 1173ULL))
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

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
    Dim c2fb_temp_10 As c2fb_callback_87
    Dim c2fb_temp_11 As BtreeCellParseProc Ptr
    Dim c2fb_temp_12 As c2fb_callback_88
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
    Dim c2fb_temp_24 As c2fb_callback_87
    Dim c2fb_temp_25 As BtreeCellParseProc Ptr
    Dim c2fb_temp_26 As c2fb_callback_88
    Dim c2fb_temp_27 As u16 Ptr
    Dim c2fb_temp_28 As UShort
    Dim c2fb_temp_29 As u16 Ptr
    Dim c2fb_temp_30 As UShort
    Dim c2fb_temp_31 As u8 Ptr
    Dim c2fb_temp_32 As UByte
    Dim c2fb_temp_33 As u8 Ptr
    Dim c2fb_temp_34 As UByte
    Dim c2fb_temp_35 As BtreeCellSizeProc Ptr
    Dim c2fb_temp_36 As c2fb_callback_87
    Dim c2fb_temp_37 As BtreeCellParseProc Ptr
    Dim c2fb_temp_38 As c2fb_callback_88
    Dim c2fb_temp_39 As u8 Ptr
    Dim c2fb_temp_40 As UByte
    Dim c2fb_temp_41 As u8 Ptr
    Dim c2fb_temp_42 As UByte
    Dim c2fb_temp_43 As u8 Ptr
    Dim c2fb_temp_44 As UByte
    Dim c2fb_temp_45 As u8 Ptr
    Dim c2fb_temp_46 As UByte
    Dim c2fb_temp_47 As BtreeCellSizeProc Ptr
    Dim c2fb_temp_48 As c2fb_callback_87
    Dim c2fb_temp_49 As BtreeCellParseProc Ptr
    Dim c2fb_temp_50 As c2fb_callback_88
    Dim c2fb_temp_51 As u16 Ptr
    Dim c2fb_temp_52 As UShort
    Dim c2fb_temp_53 As u16 Ptr
    Dim c2fb_temp_54 As UShort
    Dim c2fb_temp_55 As u8 Ptr
    Dim c2fb_temp_56 As UByte
    Dim c2fb_temp_57 As BtreeCellSizeProc Ptr
    Dim c2fb_temp_58 As c2fb_callback_87
    Dim c2fb_temp_59 As BtreeCellParseProc Ptr
    Dim c2fb_temp_60 As c2fb_callback_88
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
    Dim c2fb_temp_72 As c2fb_callback_87
    Dim c2fb_temp_73 As BtreeCellParseProc Ptr
    Dim c2fb_temp_74 As c2fb_callback_88

    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = arg0->pBt
    local0 = c2fb_temp_0
    c2fb_temp_1 = CPtr(u8 Ptr, @(arg0->max1bytePayload))
    c2fb_temp_2 = Cast(UByte, local0->max1bytePayload)
    (*c2fb_temp_1) = Cast(u8, c2fb_temp_2)
    c2fb_temp_2 = Cast(UByte, (*c2fb_temp_1))
    If (-Cast(SQLITE_C_INT, ((arg1 >= (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H02ULL) Or Cast(SQLITE_C_INT, &H08ULL)))))))) Then
        c2fb_temp_3 = CPtr(u8 Ptr, @(arg0->childPtrSize))
        c2fb_temp_4 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_3) = Cast(u8, c2fb_temp_4)
        c2fb_temp_4 = Cast(UByte, (*c2fb_temp_3))
        c2fb_temp_5 = CPtr(u8 Ptr, @(arg0->leaf))
        c2fb_temp_6 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
        (*c2fb_temp_5) = Cast(u8, c2fb_temp_6)
        c2fb_temp_6 = Cast(UByte, (*c2fb_temp_5))
        If (-Cast(SQLITE_C_INT, ((arg1 = (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H04ULL) Or Cast(SQLITE_C_INT, &H01ULL))) Or Cast(SQLITE_C_INT, &H08ULL)))))))) Then
            c2fb_temp_7 = CPtr(u8 Ptr, @(arg0->intKeyLeaf))
            c2fb_temp_8 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
            (*c2fb_temp_7) = Cast(u8, c2fb_temp_8)
            c2fb_temp_8 = Cast(UByte, (*c2fb_temp_7))
            c2fb_temp_9 = CPtr(BtreeCellSizeProc Ptr, @(arg0->xCellSize))
            c2fb_temp_10 = CPtr(c2fb_callback_87, ProcPtr(cellSizePtrTableLeaf))
            (*c2fb_temp_9) = Cast(BtreeCellSizeProc, c2fb_temp_10)
            c2fb_temp_10 = CPtr(c2fb_callback_87, (*c2fb_temp_9))
            c2fb_temp_11 = CPtr(BtreeCellParseProc Ptr, @(arg0->xParseCell))
            c2fb_temp_12 = CPtr(c2fb_callback_88, ProcPtr(btreeParseCellPtr))
            (*c2fb_temp_11) = Cast(BtreeCellParseProc, c2fb_temp_12)
            c2fb_temp_12 = CPtr(c2fb_callback_88, (*c2fb_temp_11))
            c2fb_temp_13 = CPtr(u8 Ptr, @(arg0->intKey))
            c2fb_temp_14 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
            (*c2fb_temp_13) = Cast(u8, c2fb_temp_14)
            c2fb_temp_14 = Cast(UByte, (*c2fb_temp_13))
            c2fb_temp_15 = CPtr(u16 Ptr, @(arg0->maxLocal))
            c2fb_temp_16 = Cast(UShort, local0->maxLeaf)
            (*c2fb_temp_15) = Cast(u16, c2fb_temp_16)
            c2fb_temp_16 = Cast(UShort, (*c2fb_temp_15))
            c2fb_temp_17 = CPtr(u16 Ptr, @(arg0->minLocal))
            c2fb_temp_18 = Cast(UShort, local0->minLeaf)
            (*c2fb_temp_17) = Cast(u16, c2fb_temp_18)
            c2fb_temp_18 = Cast(UShort, (*c2fb_temp_17))
        Else
            If (-Cast(SQLITE_C_INT, ((arg1 = (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H02ULL) Or Cast(SQLITE_C_INT, &H08ULL)))))))) Then
                c2fb_temp_19 = CPtr(u8 Ptr, @(arg0->intKey))
                c2fb_temp_20 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_19) = Cast(u8, c2fb_temp_20)
                c2fb_temp_20 = Cast(UByte, (*c2fb_temp_19))
                c2fb_temp_21 = CPtr(u8 Ptr, @(arg0->intKeyLeaf))
                c2fb_temp_22 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_21) = Cast(u8, c2fb_temp_22)
                c2fb_temp_22 = Cast(UByte, (*c2fb_temp_21))
                c2fb_temp_23 = CPtr(BtreeCellSizeProc Ptr, @(arg0->xCellSize))
                c2fb_temp_24 = CPtr(c2fb_callback_87, ProcPtr(cellSizePtrIdxLeaf))
                (*c2fb_temp_23) = Cast(BtreeCellSizeProc, c2fb_temp_24)
                c2fb_temp_24 = CPtr(c2fb_callback_87, (*c2fb_temp_23))
                c2fb_temp_25 = CPtr(BtreeCellParseProc Ptr, @(arg0->xParseCell))
                c2fb_temp_26 = CPtr(c2fb_callback_88, ProcPtr(btreeParseCellPtrIndex))
                (*c2fb_temp_25) = Cast(BtreeCellParseProc, c2fb_temp_26)
                c2fb_temp_26 = CPtr(c2fb_callback_88, (*c2fb_temp_25))
                c2fb_temp_27 = CPtr(u16 Ptr, @(arg0->maxLocal))
                c2fb_temp_28 = Cast(UShort, local0->maxLocal)
                (*c2fb_temp_27) = Cast(u16, c2fb_temp_28)
                c2fb_temp_28 = Cast(UShort, (*c2fb_temp_27))
                c2fb_temp_29 = CPtr(u16 Ptr, @(arg0->minLocal))
                c2fb_temp_30 = Cast(UShort, local0->minLocal)
                (*c2fb_temp_29) = Cast(u16, c2fb_temp_30)
                c2fb_temp_30 = Cast(UShort, (*c2fb_temp_29))
            Else
                c2fb_temp_31 = CPtr(u8 Ptr, @(arg0->intKey))
                c2fb_temp_32 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_31) = Cast(u8, c2fb_temp_32)
                c2fb_temp_32 = Cast(UByte, (*c2fb_temp_31))
                c2fb_temp_33 = CPtr(u8 Ptr, @(arg0->intKeyLeaf))
                c2fb_temp_34 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_33) = Cast(u8, c2fb_temp_34)
                c2fb_temp_34 = Cast(UByte, (*c2fb_temp_33))
                c2fb_temp_35 = CPtr(BtreeCellSizeProc Ptr, @(arg0->xCellSize))
                c2fb_temp_36 = CPtr(c2fb_callback_87, ProcPtr(cellSizePtrIdxLeaf))
                (*c2fb_temp_35) = Cast(BtreeCellSizeProc, c2fb_temp_36)
                c2fb_temp_36 = CPtr(c2fb_callback_87, (*c2fb_temp_35))
                c2fb_temp_37 = CPtr(BtreeCellParseProc Ptr, @(arg0->xParseCell))
                c2fb_temp_38 = CPtr(c2fb_callback_88, ProcPtr(btreeParseCellPtrIndex))
                (*c2fb_temp_37) = Cast(BtreeCellParseProc, c2fb_temp_38)
                c2fb_temp_38 = CPtr(c2fb_callback_88, (*c2fb_temp_37))
                Return sqlite3CorruptError(Cast(SQLITE_C_INT, 2084ULL))
            End If
        End If
    Else
        c2fb_temp_39 = CPtr(u8 Ptr, @(arg0->childPtrSize))
        c2fb_temp_40 = Cast(UByte, Cast(SQLITE_C_INT, 4ULL))
        (*c2fb_temp_39) = Cast(u8, c2fb_temp_40)
        c2fb_temp_40 = Cast(UByte, (*c2fb_temp_39))
        c2fb_temp_41 = CPtr(u8 Ptr, @(arg0->leaf))
        c2fb_temp_42 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_41) = Cast(u8, c2fb_temp_42)
        c2fb_temp_42 = Cast(UByte, (*c2fb_temp_41))
        If (-Cast(SQLITE_C_INT, ((arg1 = (Cast(SQLITE_C_INT, &H02ULL)))))) Then
            c2fb_temp_43 = CPtr(u8 Ptr, @(arg0->intKey))
            c2fb_temp_44 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_43) = Cast(u8, c2fb_temp_44)
            c2fb_temp_44 = Cast(UByte, (*c2fb_temp_43))
            c2fb_temp_45 = CPtr(u8 Ptr, @(arg0->intKeyLeaf))
            c2fb_temp_46 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_45) = Cast(u8, c2fb_temp_46)
            c2fb_temp_46 = Cast(UByte, (*c2fb_temp_45))
            c2fb_temp_47 = CPtr(BtreeCellSizeProc Ptr, @(arg0->xCellSize))
            c2fb_temp_48 = CPtr(c2fb_callback_87, ProcPtr(cellSizePtr))
            (*c2fb_temp_47) = Cast(BtreeCellSizeProc, c2fb_temp_48)
            c2fb_temp_48 = CPtr(c2fb_callback_87, (*c2fb_temp_47))
            c2fb_temp_49 = CPtr(BtreeCellParseProc Ptr, @(arg0->xParseCell))
            c2fb_temp_50 = CPtr(c2fb_callback_88, ProcPtr(btreeParseCellPtrIndex))
            (*c2fb_temp_49) = Cast(BtreeCellParseProc, c2fb_temp_50)
            c2fb_temp_50 = CPtr(c2fb_callback_88, (*c2fb_temp_49))
            c2fb_temp_51 = CPtr(u16 Ptr, @(arg0->maxLocal))
            c2fb_temp_52 = Cast(UShort, local0->maxLocal)
            (*c2fb_temp_51) = Cast(u16, c2fb_temp_52)
            c2fb_temp_52 = Cast(UShort, (*c2fb_temp_51))
            c2fb_temp_53 = CPtr(u16 Ptr, @(arg0->minLocal))
            c2fb_temp_54 = Cast(UShort, local0->minLocal)
            (*c2fb_temp_53) = Cast(u16, c2fb_temp_54)
            c2fb_temp_54 = Cast(UShort, (*c2fb_temp_53))
        Else
            If (-Cast(SQLITE_C_INT, ((arg1 = (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H04ULL) Or Cast(SQLITE_C_INT, &H01ULL)))))))) Then
                c2fb_temp_55 = CPtr(u8 Ptr, @(arg0->intKeyLeaf))
                c2fb_temp_56 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_55) = Cast(u8, c2fb_temp_56)
                c2fb_temp_56 = Cast(UByte, (*c2fb_temp_55))
                c2fb_temp_57 = CPtr(BtreeCellSizeProc Ptr, @(arg0->xCellSize))
                c2fb_temp_58 = CPtr(c2fb_callback_87, ProcPtr(cellSizePtrNoPayload))
                (*c2fb_temp_57) = Cast(BtreeCellSizeProc, c2fb_temp_58)
                c2fb_temp_58 = CPtr(c2fb_callback_87, (*c2fb_temp_57))
                c2fb_temp_59 = CPtr(BtreeCellParseProc Ptr, @(arg0->xParseCell))
                c2fb_temp_60 = CPtr(c2fb_callback_88, ProcPtr(btreeParseCellPtrNoPayload))
                (*c2fb_temp_59) = Cast(BtreeCellParseProc, c2fb_temp_60)
                c2fb_temp_60 = CPtr(c2fb_callback_88, (*c2fb_temp_59))
                c2fb_temp_61 = CPtr(u8 Ptr, @(arg0->intKey))
                c2fb_temp_62 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
                (*c2fb_temp_61) = Cast(u8, c2fb_temp_62)
                c2fb_temp_62 = Cast(UByte, (*c2fb_temp_61))
                c2fb_temp_63 = CPtr(u16 Ptr, @(arg0->maxLocal))
                c2fb_temp_64 = Cast(UShort, local0->maxLeaf)
                (*c2fb_temp_63) = Cast(u16, c2fb_temp_64)
                c2fb_temp_64 = Cast(UShort, (*c2fb_temp_63))
                c2fb_temp_65 = CPtr(u16 Ptr, @(arg0->minLocal))
                c2fb_temp_66 = Cast(UShort, local0->minLeaf)
                (*c2fb_temp_65) = Cast(u16, c2fb_temp_66)
                c2fb_temp_66 = Cast(UShort, (*c2fb_temp_65))
            Else
                c2fb_temp_67 = CPtr(u8 Ptr, @(arg0->intKey))
                c2fb_temp_68 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_67) = Cast(u8, c2fb_temp_68)
                c2fb_temp_68 = Cast(UByte, (*c2fb_temp_67))
                c2fb_temp_69 = CPtr(u8 Ptr, @(arg0->intKeyLeaf))
                c2fb_temp_70 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_69) = Cast(u8, c2fb_temp_70)
                c2fb_temp_70 = Cast(UByte, (*c2fb_temp_69))
                c2fb_temp_71 = CPtr(BtreeCellSizeProc Ptr, @(arg0->xCellSize))
                c2fb_temp_72 = CPtr(c2fb_callback_87, ProcPtr(cellSizePtr))
                (*c2fb_temp_71) = Cast(BtreeCellSizeProc, c2fb_temp_72)
                c2fb_temp_72 = CPtr(c2fb_callback_87, (*c2fb_temp_71))
                c2fb_temp_73 = CPtr(BtreeCellParseProc Ptr, @(arg0->xParseCell))
                c2fb_temp_74 = CPtr(c2fb_callback_88, ProcPtr(btreeParseCellPtrIndex))
                (*c2fb_temp_73) = Cast(BtreeCellParseProc, c2fb_temp_74)
                c2fb_temp_74 = CPtr(c2fb_callback_88, (*c2fb_temp_73))
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
    c2fb_temp_1 = CPtr(UByte Ptr, @(local0[local2]))
    c2fb_temp_2 = Cast(UByte, Cast(Byte, arg1))
    (*c2fb_temp_1) = c2fb_temp_2
    c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local2 + (IIf((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (arg1 And Cast(SQLITE_C_INT, &H08ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))), Cast(SQLITE_C_INT, 12ULL), Cast(SQLITE_C_INT, 8ULL))))))
    local3 = c2fb_temp_3
    c2fb_temp_4 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(UByte Ptr, @(local0[Cast(SQLITE_C_INT, (local2 + Cast(SQLITE_C_INT, 1ULL)))]))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, 4ULL)))
    c2fb_temp_5 = CPtr(UByte Ptr, @(local0[Cast(SQLITE_C_INT, (local2 + Cast(SQLITE_C_INT, 7ULL)))]))
    c2fb_temp_6 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_5) = c2fb_temp_6
    c2fb_temp_7 = CPtr(UByte Ptr, @((CPtr(UByte Ptr, @(local0[Cast(SQLITE_C_INT, (local2 + Cast(SQLITE_C_INT, 5ULL)))])))[Cast(SQLITE_C_INT, &O0ULL)]))
    c2fb_temp_8 = Cast(UByte, Cast(UByte, (Cast(SQLITE_C_UINT, ((local1->usableSize) Shr Cast(SQLITE_C_INT, 8ULL))))))
    (*c2fb_temp_7) = c2fb_temp_8
    c2fb_temp_9 = CPtr(UByte Ptr, @((CPtr(UByte Ptr, @(local0[Cast(SQLITE_C_INT, (local2 + Cast(SQLITE_C_INT, 5ULL)))])))[Cast(SQLITE_C_INT, 1ULL)]))
    c2fb_temp_10 = Cast(UByte, Cast(UByte, (local1->usableSize)))
    (*c2fb_temp_9) = c2fb_temp_10
    c2fb_temp_11 = (c2fb_temp_10)
    c2fb_temp_12 = CPtr(SQLITE_C_INT Ptr, @(arg0->nFree))
    c2fb_temp_13 = Cast(SQLITE_C_INT, Cast(UShort, (Cast(SQLITE_C_UINT, (local1->usableSize - Cast(SQLITE_C_UINT, local3))))))
    (*c2fb_temp_12) = c2fb_temp_13
    decodeFlags(arg0, arg1)
    c2fb_temp_14 = CPtr(u16 Ptr, @(arg0->cellOffset))
    c2fb_temp_15 = Cast(UShort, Cast(UShort, local3))
    (*c2fb_temp_14) = Cast(u16, c2fb_temp_15)
    c2fb_temp_15 = Cast(UShort, (*c2fb_temp_14))
    c2fb_temp_16 = CPtr(UByte Ptr Ptr, @(arg0->aDataEnd))
    c2fb_temp_17 = CPtr(UByte Ptr, @(local0[local1->pageSize]))
    (*c2fb_temp_16) = c2fb_temp_17
    c2fb_temp_18 = CPtr(UByte Ptr Ptr, @(arg0->aCellIdx))
    c2fb_temp_19 = CPtr(UByte Ptr, @(local0[local3]))
    (*c2fb_temp_18) = c2fb_temp_19
    c2fb_temp_20 = CPtr(UByte Ptr Ptr, @(arg0->aDataOfst))
    c2fb_temp_21 = CPtr(UByte Ptr, @(local0[arg0->childPtrSize]))
    (*c2fb_temp_20) = c2fb_temp_21
    c2fb_temp_22 = CPtr(u8 Ptr, @(arg0->nOverflow))
    c2fb_temp_23 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_22) = Cast(u8, c2fb_temp_23)
    c2fb_temp_23 = Cast(UByte, (*c2fb_temp_22))
    ' C unused-parameter annotation
    c2fb_temp_24 = CPtr(u16 Ptr, @(arg0->maskPage))
    c2fb_temp_25 = Cast(UShort, Cast(UShort, (Cast(SQLITE_C_UINT, (local1->pageSize - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))))
    (*c2fb_temp_24) = Cast(u16, c2fb_temp_25)
    c2fb_temp_25 = Cast(UShort, (*c2fb_temp_24))
    c2fb_temp_26 = CPtr(u16 Ptr, @(arg0->nCell))
    c2fb_temp_27 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_26) = Cast(u16, c2fb_temp_27)
    c2fb_temp_27 = Cast(UShort, (*c2fb_temp_26))
    c2fb_temp_28 = CPtr(u8 Ptr, @(arg0->isInit))
    c2fb_temp_29 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
    (*c2fb_temp_28) = Cast(u8, c2fb_temp_29)
    c2fb_temp_29 = Cast(UByte, (*c2fb_temp_28))
End Sub

Private Function btreeGetPage CDecl Alias "btreeGetPage" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As MemPage Ptr Ptr, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As PgHdr Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As MemPage Ptr Ptr
    Dim c2fb_temp_2 As MemPage Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, sqlite3PagerGet(arg0->pPager, arg1, CPtr(PgHdr Ptr Ptr, CPtr(PgHdr Ptr Ptr, @(local1))), arg3))
    local0 = c2fb_temp_0
    If local0 Then
        Return local0
    End If
    c2fb_temp_1 = CPtr(MemPage Ptr Ptr, @((*arg2)))
    c2fb_temp_2 = CPtr(MemPage Ptr, btreePageFromDbPage(local1, arg1, arg0))
    (*c2fb_temp_1) = c2fb_temp_2
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function btreePageLookup CDecl Alias "btreePageLookup" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT) As MemPage Ptr
    Dim local0 As PgHdr Ptr
    Dim c2fb_temp_0 As PgHdr Ptr

    ' C automatic storage declaration
    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(PgHdr Ptr, sqlite3PagerLookup(arg0->pPager, arg1))
    local0 = c2fb_temp_0
    If local0 Then
        Return CPtr(MemPage Ptr, btreePageFromDbPage(local0, arg1, arg0))
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function btreeGetUnusedPage CDecl Alias "btreeGetUnusedPage" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As MemPage Ptr Ptr, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As MemPage Ptr Ptr
    Dim c2fb_temp_1 As MemPage Ptr
    Dim c2fb_temp_2 As u8 Ptr
    Dim c2fb_temp_3 As UByte
    Dim c2fb_temp_4 As MemPage Ptr Ptr
    Dim c2fb_temp_5 As MemPage Ptr

    local0 = btreeGetPage(arg0, arg1, arg2, arg3)
    If (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        If (-Cast(SQLITE_C_INT, ((sqlite3PagerPageRefcount(((*arg2))->pDbPage) > Cast(SQLITE_C_INT, 1ULL))))) Then
            releasePage((*arg2))
            c2fb_temp_0 = CPtr(MemPage Ptr Ptr, @((*arg2)))
            c2fb_temp_1 = CPtr(MemPage Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            (*c2fb_temp_0) = c2fb_temp_1
            Return sqlite3CorruptError(Cast(SQLITE_C_INT, 2494ULL))
        End If
        c2fb_temp_2 = CPtr(u8 Ptr, @(((*arg2))->isInit))
        c2fb_temp_3 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_2) = Cast(u8, c2fb_temp_3)
        c2fb_temp_3 = Cast(UByte, (*c2fb_temp_2))
    Else
        c2fb_temp_4 = CPtr(MemPage Ptr Ptr, @((*arg2)))
        c2fb_temp_5 = CPtr(MemPage Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_4) = c2fb_temp_5
    End If
    Return local0
End Function

/' ------------------------------------------------------------------------- '/
/' Auto-vacuum page relocation and commit '/
/' ------------------------------------------------------------------------- '/

Private Function relocatePage CDecl Alias "relocatePage" (ByVal arg0 As BtShared Ptr, ByVal arg1 As MemPage Ptr, ByVal arg2 As UByte, ByVal arg3 As SQLITE_C_UINT, ByVal arg4 As SQLITE_C_UINT, ByVal arg5 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As MemPage Ptr
    Dim local1 As SQLITE_C_UINT
    Dim local2 As Pager Ptr
    Dim local3 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As u32 Ptr
    Dim c2fb_temp_2 As SQLITE_C_UINT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_UINT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT

    ' C automatic storage declaration
    local1 = arg1->pgno
    local2 = arg0->pPager
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((local1 < Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 3ULL)))))) Then
        Return sqlite3CorruptError(Cast(SQLITE_C_INT, 3991ULL))
    End If
    ' empty C statement
    c2fb_temp_0 = Cast(SQLITE_C_INT, sqlite3PagerMovepage(local2, arg1->pDbPage, arg4, arg5))
    local3 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return local3
    End If
    c2fb_temp_1 = CPtr(u32 Ptr, @(arg1->pgno))
    c2fb_temp_2 = Cast(SQLITE_C_UINT, arg4)
    (*c2fb_temp_1) = Cast(u32, c2fb_temp_2)
    c2fb_temp_2 = Cast(SQLITE_C_UINT, (*c2fb_temp_1))
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg2) = Cast(SQLITE_C_INT, 5ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg2) = Cast(SQLITE_C_INT, 1ULL))))))))) Then
        c2fb_temp_3 = Cast(SQLITE_C_INT, setChildPtrmaps(arg1))
        local3 = c2fb_temp_3
        If (-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return local3
        End If
    Else
        local4 = sqlite3Get4byte(CPtr(Const UByte Ptr, arg1->aData))
        If (-Cast(SQLITE_C_INT, ((local4 <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            ptrmapPut(arg0, local4, Cast(SQLITE_C_INT, 4ULL), arg4, CPtr(SQLITE_C_INT Ptr, @(local3)))
            If (-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                Return local3
            End If
        End If
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg2) <> Cast(SQLITE_C_INT, 1ULL))))) Then
        c2fb_temp_4 = Cast(SQLITE_C_INT, btreeGetPage(arg0, arg3, CPtr(MemPage Ptr Ptr, @(local0)), Cast(SQLITE_C_INT, &O0ULL)))
        local3 = c2fb_temp_4
        If (-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return local3
        End If
        c2fb_temp_5 = Cast(SQLITE_C_INT, sqlite3PagerWrite(local0->pDbPage))
        local3 = c2fb_temp_5
        If (-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            releasePage(local0)
            Return local3
        End If
        c2fb_temp_6 = Cast(SQLITE_C_INT, modifyPagePointer(local0, local1, arg4, arg2))
        local3 = c2fb_temp_6
        releasePage(local0)
        If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            ptrmapPut(arg0, arg4, arg2, arg3, CPtr(SQLITE_C_INT Ptr, @(local3)))
        End If
    End If
    Return local3
End Function

Function incrVacuumStep CDecl Alias "incrVacuumStep" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As SQLITE_C_UINT, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_UINT
    Dim local1 As SQLITE_C_INT
    Dim local2 As UByte
    Dim local3 As SQLITE_C_UINT
    Dim c2fb_temp_0 As SQLITE_C_UINT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local4 As SQLITE_C_UINT
    Dim local5 As MemPage Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim local6 As SQLITE_C_UINT
    Dim local7 As MemPage Ptr
    Dim local8 As UByte
    Dim local9 As SQLITE_C_UINT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As UByte
    Dim c2fb_temp_5 As SQLITE_C_UINT
    Dim local10 As MemPage Ptr
    Dim local11 As SQLITE_C_UINT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_UINT
    Dim c2fb_temp_9 As u8 Ptr
    Dim c2fb_temp_10 As UByte
    Dim c2fb_temp_11 As u32 Ptr
    Dim c2fb_temp_12 As SQLITE_C_UINT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((ptrmapPageno((arg0), (arg2)) = (arg2)))))) = 0))) AndAlso (-Cast(SQLITE_C_INT, ((arg2 <> (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, sqlite3PendingByte) \ ((arg0)->pageSize)))) + Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))))))))))))) Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        c2fb_temp_0 = Cast(SQLITE_C_UINT, sqlite3Get4byte(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(CPtr(MemPage Ptr, arg0->pPage1)->aData[Cast(SQLITE_C_INT, 36ULL)])))))
        local0 = c2fb_temp_0
        If (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            Return Cast(SQLITE_C_INT, 101ULL)
        End If
        c2fb_temp_1 = Cast(SQLITE_C_INT, ptrmapGet(arg0, arg2, CPtr(UByte Ptr, @(local2)), CPtr(SQLITE_C_UINT Ptr, @(local3))))
        local1 = c2fb_temp_1
        If (-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return local1
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2) = Cast(SQLITE_C_INT, 1ULL))))) Then
            Return sqlite3CorruptError(Cast(SQLITE_C_INT, 4089ULL))
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2) = Cast(SQLITE_C_INT, 2ULL))))) Then
            If (-Cast(SQLITE_C_INT, ((arg3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                ' C automatic storage declaration
                ' C automatic storage declaration
                c2fb_temp_2 = Cast(SQLITE_C_INT, allocateBtreePage(arg0, CPtr(MemPage Ptr Ptr, @(local5)), CPtr(SQLITE_C_UINT Ptr, @(local4)), arg2, Cast(SQLITE_C_INT, 1ULL)))
                local1 = c2fb_temp_2
                If (-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                    Return local1
                End If
                ' C unused-parameter annotation
                releasePage(local5)
            End If
        Else
            ' C automatic storage declaration
            ' C automatic storage declaration
            local8 = Cast(SQLITE_C_INT, &O0ULL)
            local9 = Cast(SQLITE_C_INT, &O0ULL)
            c2fb_temp_3 = Cast(SQLITE_C_INT, btreeGetPage(arg0, arg2, CPtr(MemPage Ptr Ptr, @(local7)), Cast(SQLITE_C_INT, &O0ULL)))
            local1 = c2fb_temp_3
            If (-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                Return local1
            End If
            If (-Cast(SQLITE_C_INT, ((arg3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_4 = Cast(UByte, Cast(SQLITE_C_INT, 2ULL))
                local8 = c2fb_temp_4
                c2fb_temp_5 = Cast(SQLITE_C_UINT, arg1)
                local9 = c2fb_temp_5
            End If
            Do
                ' C automatic storage declaration
                local11 = btreePagecount(arg0)
                c2fb_temp_6 = Cast(SQLITE_C_INT, allocateBtreePage(arg0, CPtr(MemPage Ptr Ptr, @(local10)), CPtr(SQLITE_C_UINT Ptr, @(local6)), local9, local8))
                local1 = c2fb_temp_6
                If (-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                    releasePage(local7)
                    Return local1
                End If
                releasePage(local10)
                If (-Cast(SQLITE_C_INT, ((local6 > local11)))) Then
                    releasePage(local7)
                    Return sqlite3CorruptError(Cast(SQLITE_C_INT, 4141ULL))
                End If
            c2fb_flow_1:
            Loop While (-Cast(SQLITE_C_INT, ((arg3 AndAlso (-Cast(SQLITE_C_INT, ((local6 > arg1))))))))
            c2fb_flow_0:
            ' C unused-parameter annotation
            c2fb_temp_7 = Cast(SQLITE_C_INT, relocatePage(arg0, local7, local2, local3, local6, arg3))
            local1 = c2fb_temp_7
            releasePage(local7)
            If (-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                Return local1
            End If
        End If
    End If
    If (-Cast(SQLITE_C_INT, ((arg3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Do
            c2fb_temp_8 = arg2
            arg2 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_8 - 1)))
        c2fb_flow_3:
        Loop While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg2 = (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, sqlite3PendingByte) \ ((arg0)->pageSize)))) + Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))))))))) OrElse ((-Cast(SQLITE_C_INT, ((ptrmapPageno((arg0), (arg2)) = (arg2))))))))))
        c2fb_flow_2:
        c2fb_temp_9 = CPtr(u8 Ptr, @(arg0->bDoTruncate))
        c2fb_temp_10 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
        (*c2fb_temp_9) = Cast(u8, c2fb_temp_10)
        c2fb_temp_10 = Cast(UByte, (*c2fb_temp_9))
        c2fb_temp_11 = CPtr(u32 Ptr, @(arg0->nPage))
        c2fb_temp_12 = Cast(SQLITE_C_UINT, arg2)
        (*c2fb_temp_11) = Cast(u32, c2fb_temp_12)
        c2fb_temp_12 = Cast(SQLITE_C_UINT, (*c2fb_temp_11))
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Function finalDbSize CDecl Alias "finalDbSize" (ByVal arg0 As BtShared Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As SQLITE_C_UINT) As SQLITE_C_UINT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_UINT
    Dim local2 As SQLITE_C_UINT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_UINT
    Dim c2fb_temp_2 As SQLITE_C_UINT
    Dim c2fb_temp_3 As SQLITE_C_UINT
    Dim c2fb_temp_4 As SQLITE_C_UINT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_UINT, (arg0->usableSize \ Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 5ULL)))))
    local0 = c2fb_temp_0
    c2fb_temp_1 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (arg2 - arg1)) + ptrmapPageno(arg0, arg1))) + Cast(SQLITE_C_UINT, local0)))) \ Cast(SQLITE_C_UINT, local0))))
    local1 = c2fb_temp_1
    c2fb_temp_2 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (arg1 - arg2)) - local1)))
    local2 = c2fb_temp_2
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg1 > (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, sqlite3PendingByte) \ ((arg0)->pageSize)))) + Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))))))))) AndAlso (-Cast(SQLITE_C_INT, ((local2 < (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, sqlite3PendingByte) \ ((arg0)->pageSize)))) + Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))))))))))))) Then
        c2fb_temp_3 = local2
        local2 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_3 - 1)))
    End If
    While (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((ptrmapPageno((arg0), (local2)) = (local2)))))) OrElse (-Cast(SQLITE_C_INT, ((local2 = (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, sqlite3PendingByte) \ ((arg0)->pageSize)))) + Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))))))))))))
        c2fb_temp_4 = local2
        local2 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_4 - 1)))
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    Return local2
End Function

Function autoVacuumCommit CDecl Alias "autoVacuumCommit" (ByVal arg0 As Btree Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As Pager Ptr
    Dim local2 As BtShared Ptr
    Dim local3 As sqlite3 Ptr
    Dim c2fb_temp_0 As BtShared Ptr
    Dim c2fb_temp_1 As Pager Ptr
    Dim local4 As SQLITE_C_UINT
    Dim local5 As SQLITE_C_UINT
    Dim local6 As SQLITE_C_UINT
    Dim local7 As SQLITE_C_UINT
    Dim local8 As SQLITE_C_UINT
    Dim c2fb_temp_2 As SQLITE_C_UINT
    Dim c2fb_temp_3 As SQLITE_C_UINT
    Dim c2fb_temp_4 As sqlite3 Ptr
    Dim local9 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_UINT
    Dim c2fb_temp_8 As SQLITE_C_UINT
    Dim c2fb_temp_9 As SQLITE_C_UINT
    Dim c2fb_temp_10 As SQLITE_C_UINT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SQLITE_C_UINT
    Dim c2fb_temp_13 As SQLITE_C_UINT
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As u8 Ptr
    Dim c2fb_temp_17 As UByte
    Dim c2fb_temp_18 As u32 Ptr
    Dim c2fb_temp_19 As SQLITE_C_UINT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' empty C statement
    ' C unused-parameter annotation
    c2fb_temp_0 = arg0->pBt
    local2 = c2fb_temp_0
    c2fb_temp_1 = local2->pPager
    local1 = c2fb_temp_1
    ' C unused-parameter annotation
    invalidateAllOverflowCache(local2)
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (local2->incrVacuum = 0))) Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        c2fb_temp_2 = Cast(SQLITE_C_UINT, btreePagecount(local2))
        local8 = c2fb_temp_2
        If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((ptrmapPageno((local2), (local8)) = (local8)))))) OrElse (-Cast(SQLITE_C_INT, ((local8 = (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, sqlite3PendingByte) \ ((local2)->pageSize)))) + Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))))))))))))) Then
            Return sqlite3CorruptError(Cast(SQLITE_C_INT, 4260ULL))
        End If
        c2fb_temp_3 = Cast(SQLITE_C_UINT, sqlite3Get4byte(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(CPtr(MemPage Ptr, local2->pPage1)->aData[Cast(SQLITE_C_INT, 36ULL)])))))
        local5 = c2fb_temp_3
        c2fb_temp_4 = arg0->db
        local3 = c2fb_temp_4
        If CPtr(c2fb_callback_15, local3->xAutovacPages) Then
            ' C automatic storage declaration
            c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local9 = c2fb_temp_5
            While ((-Cast(SQLITE_C_INT, ((local9 < local3->nDb)))))
                If (-Cast(SQLITE_C_INT, ((CPtr(Btree Ptr, local3->aDb(local9).pBt) = arg0)))) Then
                    Goto c2fb_flow_0
                End If
            c2fb_flow_1:
                c2fb_temp_6 = local9
                local9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 + 1)))
            Wend
            c2fb_flow_0:
            c2fb_temp_7 = Cast(SQLITE_C_UINT, CPtr(c2fb_callback_15, local3->xAutovacPages)(local3->pAutovacPagesArg, CPtr(Const ZString Ptr, CPtr(ZString Ptr, local3->aDb(local9).zDbSName)), local8, local5, local2->pageSize))
            local6 = c2fb_temp_7
            If (-Cast(SQLITE_C_INT, ((local6 > local5)))) Then
                c2fb_temp_8 = Cast(SQLITE_C_UINT, local5)
                local6 = c2fb_temp_8
            End If
            If (-Cast(SQLITE_C_INT, ((local6 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                Return Cast(SQLITE_C_INT, &O0ULL)
            End If
        Else
            c2fb_temp_9 = Cast(SQLITE_C_UINT, local5)
            local6 = c2fb_temp_9
        End If
        c2fb_temp_10 = Cast(SQLITE_C_UINT, finalDbSize(local2, local8, local6))
        local4 = c2fb_temp_10
        If (-Cast(SQLITE_C_INT, ((local4 > local8)))) Then
            Return sqlite3CorruptError(Cast(SQLITE_C_INT, 4287ULL))
        End If
        If (-Cast(SQLITE_C_INT, ((local4 < local8)))) Then
            c2fb_temp_11 = Cast(SQLITE_C_INT, saveAllCursors(local2, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)))
            local0 = c2fb_temp_11
        End If
        c2fb_temp_12 = Cast(SQLITE_C_UINT, local8)
        local7 = c2fb_temp_12
        While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local7 > local4)))) AndAlso (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL)))))))))
            c2fb_temp_14 = Cast(SQLITE_C_INT, incrVacuumStep(local2, local4, local7, (-Cast(SQLITE_C_INT, ((local6 = local5))))))
            local0 = c2fb_temp_14
        c2fb_flow_3:
            c2fb_temp_13 = local7
            local7 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_13 - 1)))
        Wend
        c2fb_flow_2:
        If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, 101ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, ((local5 > Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
            c2fb_temp_15 = Cast(SQLITE_C_INT, sqlite3PagerWrite(CPtr(MemPage Ptr, local2->pPage1)->pDbPage))
            local0 = c2fb_temp_15
            If (-Cast(SQLITE_C_INT, ((local6 = local5)))) Then
                sqlite3Put4byte(CPtr(UByte Ptr, @(CPtr(MemPage Ptr, local2->pPage1)->aData[Cast(SQLITE_C_INT, 32ULL)])), Cast(SQLITE_C_INT, &O0ULL))
                sqlite3Put4byte(CPtr(UByte Ptr, @(CPtr(MemPage Ptr, local2->pPage1)->aData[Cast(SQLITE_C_INT, 36ULL)])), Cast(SQLITE_C_INT, &O0ULL))
            End If
            sqlite3Put4byte(CPtr(UByte Ptr, @(CPtr(MemPage Ptr, local2->pPage1)->aData[Cast(SQLITE_C_INT, 28ULL)])), local4)
            c2fb_temp_16 = CPtr(u8 Ptr, @(local2->bDoTruncate))
            c2fb_temp_17 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
            (*c2fb_temp_16) = Cast(u8, c2fb_temp_17)
            c2fb_temp_17 = Cast(UByte, (*c2fb_temp_16))
            c2fb_temp_18 = CPtr(u32 Ptr, @(local2->nPage))
            c2fb_temp_19 = Cast(SQLITE_C_UINT, local4)
            (*c2fb_temp_18) = Cast(u32, c2fb_temp_19)
            c2fb_temp_19 = Cast(SQLITE_C_UINT, (*c2fb_temp_18))
        End If
        If (-Cast(SQLITE_C_INT, ((local0 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            sqlite3PagerRollback(local1)
        End If
    End If
    ' C unused-parameter annotation
    Return local0
End Function

Private Function allocateBtreePage CDecl Alias "allocateBtreePage" (ByVal arg0 As BtShared Ptr, ByVal arg1 As MemPage Ptr Ptr, ByVal arg2 As SQLITE_C_UINT Ptr, ByVal arg3 As SQLITE_C_UINT, ByVal arg4 As UByte) As SQLITE_C_INT
    Dim local0 As MemPage Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_UINT
    Dim local3 As SQLITE_C_UINT
    Dim local4 As MemPage Ptr
    Dim local5 As MemPage Ptr
    Dim local6 As SQLITE_C_UINT
    Dim c2fb_temp_0 As MemPage Ptr
    Dim c2fb_temp_1 As SQLITE_C_UINT
    Dim c2fb_temp_2 As SQLITE_C_UINT
    Dim local7 As SQLITE_C_UINT
    Dim local8 As UByte
    Dim local9 As SQLITE_C_UINT
    Dim local10 As UByte
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As UByte
    Dim c2fb_temp_5 As UByte
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As MemPage Ptr
    Dim c2fb_temp_8 As SQLITE_C_UINT
    Dim c2fb_temp_9 As SQLITE_C_UINT
    Dim c2fb_temp_10 As SQLITE_C_UINT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As MemPage Ptr
    Dim c2fb_temp_15 As SQLITE_C_UINT
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_18 As SQLITE_C_UINT
    Dim c2fb_temp_19 As Any Ptr
    Dim c2fb_temp_20 As MemPage Ptr Ptr
    Dim c2fb_temp_21 As MemPage Ptr
    Dim c2fb_temp_22 As MemPage Ptr
    Dim c2fb_temp_23 As SQLITE_C_INT
    Dim c2fb_temp_24 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_25 As SQLITE_C_UINT
    Dim c2fb_temp_26 As MemPage Ptr Ptr
    Dim c2fb_temp_27 As MemPage Ptr
    Dim c2fb_temp_28 As UByte
    Dim c2fb_temp_29 As SQLITE_C_INT
    Dim c2fb_temp_30 As Any Ptr
    Dim c2fb_temp_31 As SQLITE_C_INT
    Dim c2fb_temp_32 As Any Ptr
    Dim local11 As MemPage Ptr
    Dim local12 As SQLITE_C_UINT
    Dim c2fb_temp_33 As SQLITE_C_INT
    Dim c2fb_temp_34 As SQLITE_C_INT
    Dim c2fb_temp_35 As SQLITE_C_INT
    Dim c2fb_temp_36 As Any Ptr
    Dim c2fb_temp_37 As Any Ptr
    Dim c2fb_temp_38 As SQLITE_C_INT
    Dim c2fb_temp_39 As MemPage Ptr
    Dim local13 As SQLITE_C_UINT
    Dim local14 As SQLITE_C_UINT
    Dim local15 As UByte Ptr
    Dim local16 As SQLITE_C_UINT
    Dim c2fb_temp_40 As SQLITE_C_UINT
    Dim c2fb_temp_41 As SQLITE_C_UINT
    Dim c2fb_temp_42 As SQLITE_C_UINT
    Dim c2fb_temp_43 As SQLITE_C_UINT
    Dim c2fb_temp_44 As SQLITE_C_UINT
    Dim local17 As SQLITE_C_INT
    Dim c2fb_temp_45 As SQLITE_C_INT
    Dim c2fb_temp_46 As SQLITE_C_UINT
    Dim c2fb_temp_47 As SQLITE_C_UINT
    Dim local18 As SQLITE_C_INT
    Dim c2fb_temp_48 As SQLITE_C_UINT
    Dim c2fb_temp_49 As SQLITE_C_INT
    Dim c2fb_temp_50 As SQLITE_C_UINT
    Dim c2fb_temp_51 As SQLITE_C_UINT
    Dim c2fb_temp_52 As SQLITE_C_INT
    Dim local19 As SQLITE_C_INT
    Dim c2fb_temp_53 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_54 As SQLITE_C_UINT
    Dim c2fb_temp_55 As SQLITE_C_INT
    Dim c2fb_temp_56 As Any Ptr
    Dim c2fb_temp_57 As SQLITE_C_INT
    Dim c2fb_temp_58 As SQLITE_C_INT
    Dim c2fb_temp_59 As SQLITE_C_INT
    Dim c2fb_temp_60 As MemPage Ptr Ptr
    Dim c2fb_temp_61 As MemPage Ptr
    Dim c2fb_temp_62 As UByte
    Dim c2fb_temp_63 As MemPage Ptr
    Dim local20 As SQLITE_C_INT
    Dim c2fb_temp_64 As SQLITE_C_INT
    Dim c2fb_temp_65 As u32 Ptr
    Dim c2fb_temp_66 As SQLITE_C_UINT
    Dim c2fb_temp_67 As u32 Ptr
    Dim c2fb_temp_68 As SQLITE_C_UINT
    Dim local21 As MemPage Ptr
    Dim c2fb_temp_69 As SQLITE_C_INT
    Dim c2fb_temp_70 As SQLITE_C_INT
    Dim c2fb_temp_71 As u32 Ptr
    Dim c2fb_temp_72 As SQLITE_C_UINT
    Dim c2fb_temp_73 As u32 Ptr
    Dim c2fb_temp_74 As SQLITE_C_UINT
    Dim c2fb_temp_75 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_76 As SQLITE_C_UINT
    Dim c2fb_temp_77 As SQLITE_C_INT
    Dim c2fb_temp_78 As SQLITE_C_INT
    Dim c2fb_temp_79 As MemPage Ptr Ptr
    Dim c2fb_temp_80 As MemPage Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local4 = Cast(SQLITE_C_INT, &O0ULL)
    local5 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(MemPage Ptr, arg0->pPage1)
    local0 = c2fb_temp_0
    c2fb_temp_1 = Cast(SQLITE_C_UINT, btreePagecount(arg0))
    local6 = c2fb_temp_1
    c2fb_temp_2 = Cast(SQLITE_C_UINT, sqlite3Get4byte(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0->aData[Cast(SQLITE_C_INT, 36ULL)])))))
    local2 = c2fb_temp_2
    ' empty C statement
    If (-Cast(SQLITE_C_INT, ((local2 >= local6)))) Then
        Return sqlite3CorruptError(Cast(SQLITE_C_INT, 6570ULL))
    End If
    If (-Cast(SQLITE_C_INT, ((local2 > Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
        ' C automatic storage declaration
        local8 = Cast(SQLITE_C_INT, &O0ULL)
        local9 = Cast(SQLITE_C_INT, &O0ULL)
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg4) = Cast(SQLITE_C_INT, 1ULL))))) Then
            If (-Cast(SQLITE_C_INT, ((arg3 <= local6)))) Then
                ' C automatic storage declaration
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                c2fb_temp_3 = Cast(SQLITE_C_INT, ptrmapGet(arg0, arg3, CPtr(UByte Ptr, @(local10)), Cast(SQLITE_C_INT, &O0ULL)))
                local1 = c2fb_temp_3
                If local1 Then
                    Return local1
                End If
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local10) = Cast(SQLITE_C_INT, 2ULL))))) Then
                    c2fb_temp_4 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
                    local8 = c2fb_temp_4
                End If
            End If
        Else
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg4) = Cast(SQLITE_C_INT, 2ULL))))) Then
                c2fb_temp_5 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
                local8 = c2fb_temp_5
            End If
        End If
        c2fb_temp_6 = Cast(SQLITE_C_INT, sqlite3PagerWrite(local0->pDbPage))
        local1 = c2fb_temp_6
        If local1 Then
            Return local1
        End If
        sqlite3Put4byte(CPtr(UByte Ptr, @(local0->aData[Cast(SQLITE_C_INT, 36ULL)])), Cast(SQLITE_C_UINT, (local2 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))
        Do
            c2fb_temp_7 = local4
            local5 = c2fb_temp_7
            If local5 Then
                c2fb_temp_8 = Cast(SQLITE_C_UINT, sqlite3Get4byte(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local5->aData[Cast(SQLITE_C_INT, &O0ULL)])))))
                local7 = c2fb_temp_8
            Else
                c2fb_temp_9 = Cast(SQLITE_C_UINT, sqlite3Get4byte(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0->aData[Cast(SQLITE_C_INT, 32ULL)])))))
                local7 = c2fb_temp_9
            End If
            ' empty C statement
            c2fb_temp_11 = 1
            If ((-Cast(SQLITE_C_INT, ((local7 > local6)))) = 0) Then
                c2fb_temp_10 = local9
                local9 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_10 + 1)))
                c2fb_temp_11 = (-Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, ((c2fb_temp_10 > local2)))) <> 0)))
            End If
            If c2fb_temp_11 Then
                c2fb_temp_12 = Cast(SQLITE_C_INT, sqlite3CorruptError(Cast(SQLITE_C_INT, 6626ULL)))
                local1 = c2fb_temp_12
            Else
                c2fb_temp_13 = Cast(SQLITE_C_INT, btreeGetUnusedPage(arg0, local7, CPtr(MemPage Ptr Ptr, @(local4)), Cast(SQLITE_C_INT, &O0ULL)))
                local1 = c2fb_temp_13
            End If
            If local1 Then
                c2fb_temp_14 = CPtr(MemPage Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                local4 = c2fb_temp_14
                Goto c2fb_label_0
            End If
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_15 = Cast(SQLITE_C_UINT, sqlite3Get4byte(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local4->aData[Cast(SQLITE_C_INT, 4ULL)])))))
            local3 = c2fb_temp_15
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, (local8 = 0))))))) Then
                ' C unused-parameter annotation
                c2fb_temp_16 = Cast(SQLITE_C_INT, sqlite3PagerWrite(local4->pDbPage))
                local1 = c2fb_temp_16
                If local1 Then
                    Goto c2fb_label_0
                End If
                c2fb_temp_17 = CPtr(SQLITE_C_UINT Ptr, @((*arg2)))
                c2fb_temp_18 = Cast(SQLITE_C_UINT, local7)
                (*c2fb_temp_17) = c2fb_temp_18
                c2fb_temp_19 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, CPtr(UByte Ptr, @(local0->aData[Cast(SQLITE_C_INT, 32ULL)]))), CPtr(Const Any Ptr, CPtr(UByte Ptr, @(local4->aData[Cast(SQLITE_C_INT, &O0ULL)]))), Cast(SQLITE_C_INT, 4ULL)))
                c2fb_temp_20 = CPtr(MemPage Ptr Ptr, @((*arg1)))
                c2fb_temp_21 = local4
                (*c2fb_temp_20) = c2fb_temp_21
                c2fb_temp_22 = CPtr(MemPage Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                local4 = c2fb_temp_22
                ' empty C statement
            Else
                If (-Cast(SQLITE_C_INT, ((local3 > Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (arg0->usableSize \ Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL)))) - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 2ULL)))))))))) Then
                    c2fb_temp_23 = Cast(SQLITE_C_INT, sqlite3CorruptError(Cast(SQLITE_C_INT, 6655ULL)))
                    local1 = c2fb_temp_23
                    Goto c2fb_label_0
                Else
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local8) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg3 = local7)))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local7 < arg3)))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg4) = Cast(SQLITE_C_INT, 2ULL))))))))))))))))))) Then
                        c2fb_temp_24 = CPtr(SQLITE_C_UINT Ptr, @((*arg2)))
                        c2fb_temp_25 = Cast(SQLITE_C_UINT, local7)
                        (*c2fb_temp_24) = c2fb_temp_25
                        c2fb_temp_26 = CPtr(MemPage Ptr Ptr, @((*arg1)))
                        c2fb_temp_27 = local4
                        (*c2fb_temp_26) = c2fb_temp_27
                        c2fb_temp_28 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                        local8 = c2fb_temp_28
                        c2fb_temp_29 = Cast(SQLITE_C_INT, sqlite3PagerWrite(local4->pDbPage))
                        local1 = c2fb_temp_29
                        If local1 Then
                            Goto c2fb_label_0
                        End If
                        If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                            If (-Cast(SQLITE_C_INT, (local5 = 0))) Then
                                c2fb_temp_30 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, CPtr(UByte Ptr, @(local0->aData[Cast(SQLITE_C_INT, 32ULL)]))), CPtr(Const Any Ptr, CPtr(UByte Ptr, @(local4->aData[Cast(SQLITE_C_INT, &O0ULL)]))), Cast(SQLITE_C_INT, 4ULL)))
                            Else
                                c2fb_temp_31 = Cast(SQLITE_C_INT, sqlite3PagerWrite(local5->pDbPage))
                                local1 = c2fb_temp_31
                                If (-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                                    Goto c2fb_label_0
                                End If
                                c2fb_temp_32 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, CPtr(UByte Ptr, @(local5->aData[Cast(SQLITE_C_INT, &O0ULL)]))), CPtr(Const Any Ptr, CPtr(UByte Ptr, @(local4->aData[Cast(SQLITE_C_INT, &O0ULL)]))), Cast(SQLITE_C_INT, 4ULL)))
                            End If
                        Else
                            ' C automatic storage declaration
                            local12 = sqlite3Get4byte(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local4->aData[Cast(SQLITE_C_INT, 8ULL)]))))
                            If (-Cast(SQLITE_C_INT, ((local12 > local6)))) Then
                                c2fb_temp_33 = Cast(SQLITE_C_INT, sqlite3CorruptError(Cast(SQLITE_C_INT, 6689ULL)))
                                local1 = c2fb_temp_33
                                Goto c2fb_label_0
                            End If
                            ' empty C statement
                            c2fb_temp_34 = Cast(SQLITE_C_INT, btreeGetUnusedPage(arg0, local12, CPtr(MemPage Ptr Ptr, @(local11)), Cast(SQLITE_C_INT, &O0ULL)))
                            local1 = c2fb_temp_34
                            If (-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                                Goto c2fb_label_0
                            End If
                            c2fb_temp_35 = Cast(SQLITE_C_INT, sqlite3PagerWrite(local11->pDbPage))
                            local1 = c2fb_temp_35
                            If (-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                                releasePage(local11)
                                Goto c2fb_label_0
                            End If
                            c2fb_temp_36 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, CPtr(UByte Ptr, @(local11->aData[Cast(SQLITE_C_INT, &O0ULL)]))), CPtr(Const Any Ptr, CPtr(UByte Ptr, @(local4->aData[Cast(SQLITE_C_INT, &O0ULL)]))), Cast(SQLITE_C_INT, 4ULL)))
                            sqlite3Put4byte(CPtr(UByte Ptr, @(local11->aData[Cast(SQLITE_C_INT, 4ULL)])), Cast(SQLITE_C_UINT, (local3 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))
                            c2fb_temp_37 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, CPtr(UByte Ptr, @(local11->aData[Cast(SQLITE_C_INT, 8ULL)]))), CPtr(Const Any Ptr, CPtr(UByte Ptr, @(local4->aData[Cast(SQLITE_C_INT, 12ULL)]))), Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (local3 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))) * Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL))))))
                            releasePage(local11)
                            If (-Cast(SQLITE_C_INT, (local5 = 0))) Then
                                ' C unused-parameter annotation
                                sqlite3Put4byte(CPtr(UByte Ptr, @(local0->aData[Cast(SQLITE_C_INT, 32ULL)])), local12)
                            Else
                                c2fb_temp_38 = Cast(SQLITE_C_INT, sqlite3PagerWrite(local5->pDbPage))
                                local1 = c2fb_temp_38
                                If local1 Then
                                    Goto c2fb_label_0
                                End If
                                sqlite3Put4byte(CPtr(UByte Ptr, @(local5->aData[Cast(SQLITE_C_INT, &O0ULL)])), local12)
                            End If
                        End If
                        c2fb_temp_39 = CPtr(MemPage Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                        local4 = c2fb_temp_39
                        ' empty C statement
                    Else
                        If (-Cast(SQLITE_C_INT, ((local3 > Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                            ' C automatic storage declaration
                            ' C automatic storage declaration
                            local15 = local4->aData
                            If (-Cast(SQLITE_C_INT, ((arg3 > Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                                ' C automatic storage declaration
                                c2fb_temp_40 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))
                                local13 = c2fb_temp_40
                                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg4) = Cast(SQLITE_C_INT, 2ULL))))) Then
                                    c2fb_temp_41 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))
                                    local16 = c2fb_temp_41
                                    While (-Cast(SQLITE_C_INT, ((local16 < local3))))
                                        c2fb_temp_43 = Cast(SQLITE_C_UINT, sqlite3Get4byte(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local15[Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 8ULL)) + Cast(SQLITE_C_UINT, (local16 * Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL))))))])))))
                                        local14 = c2fb_temp_43
                                        If (-Cast(SQLITE_C_INT, ((local14 <= arg3)))) Then
                                            c2fb_temp_44 = Cast(SQLITE_C_UINT, local16)
                                            local13 = c2fb_temp_44
                                            Goto c2fb_flow_2
                                        End If
                                    c2fb_flow_3:
                                        c2fb_temp_42 = local16
                                        local16 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_42 + 1)))
                                    Wend
                                    c2fb_flow_2:
                                Else
                                    ' C automatic storage declaration
                                    c2fb_temp_45 = Cast(SQLITE_C_INT, sqlite3AbsInt32(Cast(SQLITE_C_UINT, (sqlite3Get4byte(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local15[Cast(SQLITE_C_INT, 8ULL)])))) - arg3))))
                                    local17 = c2fb_temp_45
                                    c2fb_temp_46 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))
                                    local16 = c2fb_temp_46
                                    While (-Cast(SQLITE_C_INT, ((local16 < local3))))
                                        local18 = sqlite3AbsInt32(Cast(SQLITE_C_UINT, (sqlite3Get4byte(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local15[Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 8ULL)) + Cast(SQLITE_C_UINT, (local16 * Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL))))))])))) - arg3)))
                                        If (-Cast(SQLITE_C_INT, ((local18 < local17)))) Then
                                            c2fb_temp_48 = Cast(SQLITE_C_UINT, local16)
                                            local13 = c2fb_temp_48
                                            c2fb_temp_49 = Cast(SQLITE_C_INT, local18)
                                            local17 = c2fb_temp_49
                                        End If
                                    c2fb_flow_5:
                                        c2fb_temp_47 = local16
                                        local16 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_47 + 1)))
                                    Wend
                                    c2fb_flow_4:
                                End If
                            Else
                                c2fb_temp_50 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))
                                local13 = c2fb_temp_50
                            End If
                            c2fb_temp_51 = Cast(SQLITE_C_UINT, sqlite3Get4byte(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local15[Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 8ULL)) + Cast(SQLITE_C_UINT, (local13 * Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL))))))])))))
                            local14 = c2fb_temp_51
                            ' empty C statement
                            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local14 > local6)))) OrElse (-Cast(SQLITE_C_INT, ((local14 < Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 2ULL)))))))))) Then
                                c2fb_temp_52 = Cast(SQLITE_C_INT, sqlite3CorruptError(Cast(SQLITE_C_INT, 6754ULL)))
                                local1 = c2fb_temp_52
                                Goto c2fb_label_0
                            End If
                            ' empty C statement
                            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (local8 = 0))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local14 = arg3)))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local14 < arg3)))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg4) = Cast(SQLITE_C_INT, 2ULL))))))))))))))))))) Then
                                ' C automatic storage declaration
                                c2fb_temp_53 = CPtr(SQLITE_C_UINT Ptr, @((*arg2)))
                                c2fb_temp_54 = Cast(SQLITE_C_UINT, local14)
                                (*c2fb_temp_53) = c2fb_temp_54
                                ' empty C statement
                                c2fb_temp_55 = Cast(SQLITE_C_INT, sqlite3PagerWrite(local4->pDbPage))
                                local1 = c2fb_temp_55
                                If local1 Then
                                    Goto c2fb_label_0
                                End If
                                If (-Cast(SQLITE_C_INT, ((local13 < Cast(SQLITE_C_UINT, (local3 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))))) Then
                                    c2fb_temp_56 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, CPtr(UByte Ptr, @(local15[Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 8ULL)) + Cast(SQLITE_C_UINT, (local13 * Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL))))))]))), CPtr(Const Any Ptr, CPtr(UByte Ptr, @(local15[Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL)) + Cast(SQLITE_C_UINT, (local3 * Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL))))))]))), Cast(SQLITE_C_INT, 4ULL)))
                                End If
                                sqlite3Put4byte(CPtr(UByte Ptr, @(local15[Cast(SQLITE_C_INT, 4ULL)])), Cast(SQLITE_C_UINT, (local3 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))
                                c2fb_temp_57 = Cast(SQLITE_C_INT, IIf((-Cast(SQLITE_C_INT, (btreeGetHasContent(arg0, (*arg2)) = 0))), Cast(SQLITE_C_INT, &H01ULL), Cast(SQLITE_C_INT, &O0ULL)))
                                local19 = c2fb_temp_57
                                c2fb_temp_58 = Cast(SQLITE_C_INT, btreeGetUnusedPage(arg0, (*arg2), arg1, local19))
                                local1 = c2fb_temp_58
                                If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                                    c2fb_temp_59 = Cast(SQLITE_C_INT, sqlite3PagerWrite(((*arg1))->pDbPage))
                                    local1 = c2fb_temp_59
                                    If (-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                                        releasePage((*arg1))
                                        c2fb_temp_60 = CPtr(MemPage Ptr Ptr, @((*arg1)))
                                        c2fb_temp_61 = CPtr(MemPage Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                                        (*c2fb_temp_60) = c2fb_temp_61
                                    End If
                                End If
                                c2fb_temp_62 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                                local8 = c2fb_temp_62
                            End If
                        End If
                    End If
                End If
            End If
            releasePage(local5)
            c2fb_temp_63 = CPtr(MemPage Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            local5 = c2fb_temp_63
        c2fb_flow_1:
        Loop While local8
        c2fb_flow_0:
    Else
        local20 = IIf(((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = Cast(SQLITE_C_INT, (arg0->bDoTruncate))))))), Cast(SQLITE_C_INT, &H01ULL), Cast(SQLITE_C_INT, &O0ULL))
        c2fb_temp_64 = Cast(SQLITE_C_INT, sqlite3PagerWrite(CPtr(MemPage Ptr, arg0->pPage1)->pDbPage))
        local1 = c2fb_temp_64
        If local1 Then
            Return local1
        End If
        c2fb_temp_65 = CPtr(u32 Ptr, @(arg0->nPage))
        c2fb_temp_66 = Cast(SQLITE_C_UINT, (*c2fb_temp_65))
        (*c2fb_temp_65) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_66 + 1)))
        If (-Cast(SQLITE_C_INT, ((arg0->nPage = (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, sqlite3PendingByte) \ ((arg0)->pageSize)))) + Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))))))))) Then
            c2fb_temp_67 = CPtr(u32 Ptr, @(arg0->nPage))
            c2fb_temp_68 = Cast(SQLITE_C_UINT, (*c2fb_temp_67))
            (*c2fb_temp_67) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_68 + 1)))
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->autoVacuum) AndAlso ((-Cast(SQLITE_C_INT, ((ptrmapPageno((arg0), (arg0->nPage)) = (arg0->nPage)))))))))) Then
            local21 = Cast(SQLITE_C_INT, &O0ULL)
            ' empty C statement
            ' C unused-parameter annotation
            c2fb_temp_69 = Cast(SQLITE_C_INT, btreeGetUnusedPage(arg0, arg0->nPage, CPtr(MemPage Ptr Ptr, @(local21)), local20))
            local1 = c2fb_temp_69
            If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_70 = Cast(SQLITE_C_INT, sqlite3PagerWrite(local21->pDbPage))
                local1 = c2fb_temp_70
                releasePage(local21)
            End If
            If local1 Then
                Return local1
            End If
            c2fb_temp_71 = CPtr(u32 Ptr, @(arg0->nPage))
            c2fb_temp_72 = Cast(SQLITE_C_UINT, (*c2fb_temp_71))
            (*c2fb_temp_71) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_72 + 1)))
            If (-Cast(SQLITE_C_INT, ((arg0->nPage = (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, sqlite3PendingByte) \ ((arg0)->pageSize)))) + Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))))))))) Then
                c2fb_temp_73 = CPtr(u32 Ptr, @(arg0->nPage))
                c2fb_temp_74 = Cast(SQLITE_C_UINT, (*c2fb_temp_73))
                (*c2fb_temp_73) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_74 + 1)))
            End If
        End If
        sqlite3Put4byte(CPtr(UByte Ptr, (Cast(SQLITE_C_INT, 28ULL) + CPtr(UByte Ptr, CPtr(MemPage Ptr, arg0->pPage1)->aData))), arg0->nPage)
        c2fb_temp_75 = CPtr(SQLITE_C_UINT Ptr, @((*arg2)))
        c2fb_temp_76 = Cast(SQLITE_C_UINT, arg0->nPage)
        (*c2fb_temp_75) = c2fb_temp_76
        ' C unused-parameter annotation
        c2fb_temp_77 = Cast(SQLITE_C_INT, btreeGetUnusedPage(arg0, (*arg2), arg1, local20))
        local1 = c2fb_temp_77
        If local1 Then
            Return local1
        End If
        c2fb_temp_78 = Cast(SQLITE_C_INT, sqlite3PagerWrite(((*arg1))->pDbPage))
        local1 = c2fb_temp_78
        If (-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            releasePage((*arg1))
            c2fb_temp_79 = CPtr(MemPage Ptr Ptr, @((*arg1)))
            c2fb_temp_80 = CPtr(MemPage Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            (*c2fb_temp_79) = c2fb_temp_80
        End If
        ' empty C statement
    End If
    ' C unused-parameter annotation
    c2fb_label_0:
    releasePage(local4)
    releasePage(local5)
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    Return local1
End Function

Private Function freePage2 CDecl Alias "freePage2" (ByVal arg0 As BtShared Ptr, ByVal arg1 As MemPage Ptr, ByVal arg2 As SQLITE_C_UINT) As SQLITE_C_INT
    Dim local0 As MemPage Ptr
    Dim local1 As SQLITE_C_UINT
    Dim local2 As MemPage Ptr
    Dim local3 As MemPage Ptr
    Dim local4 As SQLITE_C_INT
    Dim local5 As SQLITE_C_UINT
    Dim c2fb_temp_0 As MemPage Ptr
    Dim c2fb_temp_1 As MemPage Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_UINT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As Any Ptr
    Dim local6 As SQLITE_C_UINT
    Dim c2fb_temp_9 As SQLITE_C_UINT
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SQLITE_C_UINT
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SQLITE_C_INT
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim c2fb_temp_20 As u8 Ptr
    Dim c2fb_temp_21 As UByte

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    local2 = CPtr(MemPage Ptr, arg0->pPage1)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg2 < Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 2ULL)))))) OrElse (-Cast(SQLITE_C_INT, ((arg2 > arg0->nPage)))))))) Then
        Return sqlite3CorruptError(Cast(SQLITE_C_INT, 6881ULL))
    End If
    If arg1 Then
        c2fb_temp_0 = arg1
        local3 = c2fb_temp_0
        sqlite3PagerRef(local3->pDbPage)
    Else
        c2fb_temp_1 = CPtr(MemPage Ptr, btreePageLookup(arg0, arg2))
        local3 = c2fb_temp_1
    End If
    c2fb_temp_2 = Cast(SQLITE_C_INT, sqlite3PagerWrite(local2->pDbPage))
    local4 = c2fb_temp_2
    If local4 Then
        Goto c2fb_label_0
    End If
    c2fb_temp_3 = Cast(SQLITE_C_UINT, sqlite3Get4byte(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local2->aData[Cast(SQLITE_C_INT, 36ULL)])))))
    local5 = c2fb_temp_3
    sqlite3Put4byte(CPtr(UByte Ptr, @(local2->aData[Cast(SQLITE_C_INT, 36ULL)])), Cast(SQLITE_C_UINT, (local5 + Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))
    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->btsFlags) And Cast(SQLITE_C_INT, &H0004ULL))) Then
        c2fb_temp_5 = 0
        If (-Cast(SQLITE_C_INT, (local3 = 0))) Then
            c2fb_temp_4 = Cast(SQLITE_C_INT, btreeGetPage(arg0, arg2, CPtr(MemPage Ptr Ptr, @(local3)), Cast(SQLITE_C_INT, &O0ULL)))
            local4 = c2fb_temp_4
            c2fb_temp_5 = (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((c2fb_temp_4) <> Cast(SQLITE_C_INT, &O0ULL)))))) <> 0)))
        End If
        c2fb_temp_7 = 1
        If ((c2fb_temp_5) = 0) Then
            c2fb_temp_6 = Cast(SQLITE_C_INT, sqlite3PagerWrite(local3->pDbPage))
            local4 = c2fb_temp_6
            c2fb_temp_7 = (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((c2fb_temp_6) <> Cast(SQLITE_C_INT, &O0ULL)))))) <> 0)))
        End If
        If c2fb_temp_7 Then
            Goto c2fb_label_0
        End If
        c2fb_temp_8 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, local3->aData), Cast(SQLITE_C_INT, &O0ULL), local3->pBt->pageSize))
    End If
    If (arg0->autoVacuum) Then
        ptrmapPut(arg0, arg2, Cast(SQLITE_C_INT, 2ULL), Cast(SQLITE_C_INT, &O0ULL), CPtr(SQLITE_C_INT Ptr, @(local4)))
        If local4 Then
            Goto c2fb_label_0
        End If
    End If
    If (-Cast(SQLITE_C_INT, ((local5 <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
        ' C automatic storage declaration
        c2fb_temp_9 = Cast(SQLITE_C_UINT, sqlite3Get4byte(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local2->aData[Cast(SQLITE_C_INT, 32ULL)])))))
        local1 = c2fb_temp_9
        If (-Cast(SQLITE_C_INT, ((local1 > btreePagecount(arg0))))) Then
            c2fb_temp_10 = Cast(SQLITE_C_INT, sqlite3CorruptError(Cast(SQLITE_C_INT, 6928ULL)))
            local4 = c2fb_temp_10
            Goto c2fb_label_0
        End If
        c2fb_temp_11 = Cast(SQLITE_C_INT, btreeGetPage(arg0, local1, CPtr(MemPage Ptr Ptr, @(local0)), Cast(SQLITE_C_INT, &O0ULL)))
        local4 = c2fb_temp_11
        If (-Cast(SQLITE_C_INT, ((local4 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_label_0
        End If
        c2fb_temp_12 = Cast(SQLITE_C_UINT, sqlite3Get4byte(CPtr(Const UByte Ptr, CPtr(UByte Ptr, @(local0->aData[Cast(SQLITE_C_INT, 4ULL)])))))
        local6 = c2fb_temp_12
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, ((local6 > Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, arg0->usableSize) \ Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL)))) - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 2ULL)))))))) Then
            c2fb_temp_13 = Cast(SQLITE_C_INT, sqlite3CorruptError(Cast(SQLITE_C_INT, 6939ULL)))
            local4 = c2fb_temp_13
            Goto c2fb_label_0
        End If
        If (-Cast(SQLITE_C_INT, ((local6 < Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, arg0->usableSize) \ Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL)))) - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 8ULL)))))))) Then
            c2fb_temp_14 = Cast(SQLITE_C_INT, sqlite3PagerWrite(local0->pDbPage))
            local4 = c2fb_temp_14
            If (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                sqlite3Put4byte(CPtr(UByte Ptr, @(local0->aData[Cast(SQLITE_C_INT, 4ULL)])), Cast(SQLITE_C_UINT, (local6 + Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))
                sqlite3Put4byte(CPtr(UByte Ptr, @(local0->aData[Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 8ULL)) + Cast(SQLITE_C_UINT, (local6 * Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL))))))])), arg2)
                If (-Cast(SQLITE_C_INT, ((local3 AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->btsFlags) And Cast(SQLITE_C_INT, &H0004ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                    sqlite3PagerDontWrite(local3->pDbPage)
                End If
                c2fb_temp_15 = Cast(SQLITE_C_INT, btreeSetHasContent(arg0, arg2))
                local4 = c2fb_temp_15
            End If
            ' empty C statement
            Goto c2fb_label_0
        End If
    End If
    c2fb_temp_18 = 0
    If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        c2fb_temp_17 = Cast(SQLITE_C_INT, &O0ULL)
        c2fb_temp_16 = Cast(SQLITE_C_INT, btreeGetPage(arg0, arg2, CPtr(MemPage Ptr Ptr, @(local3)), Cast(SQLITE_C_INT, &O0ULL)))
        local4 = c2fb_temp_16
        c2fb_temp_18 = (-Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, ((c2fb_temp_17 <> (c2fb_temp_16))))) <> 0)))
    End If
    If c2fb_temp_18 Then
        Goto c2fb_label_0
    End If
    c2fb_temp_19 = Cast(SQLITE_C_INT, sqlite3PagerWrite(local3->pDbPage))
    local4 = c2fb_temp_19
    If (-Cast(SQLITE_C_INT, ((local4 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        Goto c2fb_label_0
    End If
    sqlite3Put4byte(local3->aData, local1)
    sqlite3Put4byte(CPtr(UByte Ptr, @(local3->aData[Cast(SQLITE_C_INT, 4ULL)])), Cast(SQLITE_C_INT, &O0ULL))
    sqlite3Put4byte(CPtr(UByte Ptr, @(local2->aData[Cast(SQLITE_C_INT, 32ULL)])), arg2)
    ' empty C statement
    c2fb_label_0:
    If local3 Then
        c2fb_temp_20 = CPtr(u8 Ptr, @(local3->isInit))
        c2fb_temp_21 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_20) = Cast(u8, c2fb_temp_21)
        c2fb_temp_21 = Cast(UByte, (*c2fb_temp_20))
    End If
    releasePage(local3)
    releasePage(local0)
    Return local4
End Function

Private Sub freePage CDecl Alias "freePage" (ByVal arg0 As MemPage Ptr, ByVal arg1 As SQLITE_C_INT Ptr)
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT

    If (-Cast(SQLITE_C_INT, ((((*arg1)) = Cast(SQLITE_C_INT, &O0ULL))))) Then
        c2fb_temp_0 = CPtr(SQLITE_C_INT Ptr, @((*arg1)))
        c2fb_temp_1 = Cast(SQLITE_C_INT, freePage2(arg0->pBt, arg0, arg0->pgno))
        (*c2fb_temp_0) = c2fb_temp_1
    End If
End Sub

/' ------------------------------------------------------------------------- '/
/' Cell payload construction '/
/' ------------------------------------------------------------------------- '/

Private Function fillInCell CDecl Alias "fillInCell" (ByVal arg0 As MemPage Ptr, ByVal arg1 As UByte Ptr, ByVal arg2 As Const SqliteBtreePayload Ptr, ByVal arg3 As SQLITE_C_INT Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As Const UByte Ptr
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim local6 As SQLITE_C_INT
    Dim local7 As MemPage Ptr
    Dim local8 As UByte Ptr
    Dim local9 As UByte Ptr
    Dim local10 As BtShared Ptr
    Dim local11 As SQLITE_C_UINT
    Dim local12 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As Const UByte Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As UByte Ptr
    Dim c2fb_temp_5 As UByte
    Dim c2fb_temp_6 As UByte
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As Const UByte Ptr
    Dim c2fb_temp_13 As UByte Ptr
    Dim c2fb_temp_14 As UByte
    Dim c2fb_temp_15 As UByte
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SQLITE_C_INT
    Dim c2fb_temp_18 As UByte Ptr
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As UByte Ptr
    Dim c2fb_temp_22 As UByte
    Dim c2fb_temp_23 As SQLITE_C_INT Ptr
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As Any Ptr
    Dim c2fb_temp_26 As Any Ptr
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim c2fb_temp_28 As SQLITE_C_INT
    Dim c2fb_temp_29 As SQLITE_C_INT
    Dim c2fb_temp_30 As SQLITE_C_INT
    Dim c2fb_temp_31 As SQLITE_C_INT Ptr
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As UByte Ptr
    Dim c2fb_temp_34 As MemPage Ptr
    Dim c2fb_temp_35 As SQLITE_C_UINT
    Dim c2fb_temp_36 As BtShared Ptr
    Dim c2fb_temp_37 As SQLITE_C_INT
    Dim c2fb_temp_38 As SQLITE_C_INT
    Dim c2fb_temp_39 As Any Ptr
    Dim c2fb_temp_40 As SQLITE_C_INT
    Dim c2fb_temp_41 As Any Ptr
    Dim c2fb_temp_42 As Any Ptr
    Dim c2fb_temp_43 As SQLITE_C_INT
    Dim c2fb_temp_44 As UByte Ptr
    Dim c2fb_temp_45 As Const UByte Ptr
    Dim c2fb_temp_46 As SQLITE_C_INT
    Dim c2fb_temp_47 As SQLITE_C_INT
    Dim local13 As MemPage Ptr
    Dim local14 As SQLITE_C_UINT
    Dim c2fb_temp_48 As SQLITE_C_UINT
    Dim c2fb_temp_49 As SQLITE_C_INT
    Dim local15 As UByte
    Dim c2fb_temp_50 As MemPage Ptr
    Dim c2fb_temp_51 As UByte Ptr
    Dim c2fb_temp_52 As UByte Ptr
    Dim c2fb_temp_53 As SQLITE_C_INT

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
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, arg0->childPtrSize)
    local12 = c2fb_temp_0
    If arg0->intKey Then
        c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg2->nData + arg2->nZero)))
        local0 = c2fb_temp_1
        c2fb_temp_2 = CPtr(Const UByte Ptr, arg2->pData)
        local1 = c2fb_temp_2
        c2fb_temp_3 = Cast(SQLITE_C_INT, arg2->nData)
        local2 = c2fb_temp_3
        ' C unused-parameter annotation
        If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, (local0)) < Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H80ULL))))))) Then
            c2fb_temp_4 = CPtr(UByte Ptr, @((*(CPtr(UByte Ptr, @(arg1[local12]))))))
            c2fb_temp_5 = Cast(UByte, Cast(UByte, (local0)))
            (*c2fb_temp_4) = c2fb_temp_5
            c2fb_temp_6 = (c2fb_temp_5)
            c2fb_temp_7 = Cast(SQLITE_C_INT, 1ULL)
        Else
            c2fb_temp_7 = sqlite3PutVarint((CPtr(UByte Ptr, @(arg1[local12]))), (local0))
        End If
        c2fb_temp_8 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local12 + Cast(SQLITE_C_INT, Cast(UByte, (c2fb_temp_7))))))
        local12 = c2fb_temp_8
        c2fb_temp_9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local12 + sqlite3PutVarint(CPtr(UByte Ptr, @(arg1[local12])), (*CPtr(sqlite3_uint64 Ptr, CPtr(sqlite3_int64 Ptr, @(arg2->nKey))))))))
        local12 = c2fb_temp_9
    Else
        ' C unused-parameter annotation
        c2fb_temp_10 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, arg2->nKey))
        local0 = c2fb_temp_10
        c2fb_temp_11 = Cast(SQLITE_C_INT, c2fb_temp_10)
        local2 = c2fb_temp_11
        c2fb_temp_12 = CPtr(Const UByte Ptr, arg2->pKey)
        local1 = c2fb_temp_12
        If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, (local0)) < Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H80ULL))))))) Then
            c2fb_temp_13 = CPtr(UByte Ptr, @((*(CPtr(UByte Ptr, @(arg1[local12]))))))
            c2fb_temp_14 = Cast(UByte, Cast(UByte, (local0)))
            (*c2fb_temp_13) = c2fb_temp_14
            c2fb_temp_15 = (c2fb_temp_14)
            c2fb_temp_16 = Cast(SQLITE_C_INT, 1ULL)
        Else
            c2fb_temp_16 = sqlite3PutVarint((CPtr(UByte Ptr, @(arg1[local12]))), (local0))
        End If
        c2fb_temp_17 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local12 + Cast(SQLITE_C_INT, Cast(UByte, (c2fb_temp_16))))))
        local12 = c2fb_temp_17
    End If
    c2fb_temp_18 = CPtr(UByte Ptr, @(arg1[local12]))
    local9 = c2fb_temp_18
    If (-Cast(SQLITE_C_INT, ((local0 <= Cast(SQLITE_C_INT, arg0->maxLocal))))) Then
        c2fb_temp_19 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local12 + local0)))
        local3 = c2fb_temp_19
        ' empty C statement
        ' empty C statement
        If (-Cast(SQLITE_C_INT, ((local3 < Cast(SQLITE_C_INT, 4ULL))))) Then
            c2fb_temp_20 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 4ULL))
            local3 = c2fb_temp_20
            c2fb_temp_21 = CPtr(UByte Ptr, @(local9[local0]))
            c2fb_temp_22 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_21) = c2fb_temp_22
        End If
        c2fb_temp_23 = CPtr(SQLITE_C_INT Ptr, @((*arg3)))
        c2fb_temp_24 = Cast(SQLITE_C_INT, local3)
        (*c2fb_temp_23) = c2fb_temp_24
        ' C unused-parameter annotation
        ' empty C statement
        c2fb_temp_25 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, local9), CPtr(Const Any Ptr, local1), local2))
        c2fb_temp_26 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(UByte Ptr, (local9 + local2))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, (local0 - local2))))
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_27 = Cast(SQLITE_C_INT, arg0->minLocal)
    local5 = c2fb_temp_27
    c2fb_temp_28 = Cast(SQLITE_C_INT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, local5) + Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (local0 - local5)))) Mod (Cast(SQLITE_C_UINT, (arg0->pBt->usableSize - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL))))))))))
    local3 = c2fb_temp_28
    ' empty C statement
    ' empty C statement
    If (-Cast(SQLITE_C_INT, ((local3 > Cast(SQLITE_C_INT, arg0->maxLocal))))) Then
        c2fb_temp_29 = Cast(SQLITE_C_INT, local5)
        local3 = c2fb_temp_29
    End If
    c2fb_temp_30 = Cast(SQLITE_C_INT, local3)
    local6 = c2fb_temp_30
    c2fb_temp_31 = CPtr(SQLITE_C_INT Ptr, @((*arg3)))
    c2fb_temp_32 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local3 + local12)) + Cast(SQLITE_C_INT, 4ULL))))
    (*c2fb_temp_31) = c2fb_temp_32
    c2fb_temp_33 = CPtr(UByte Ptr, @(arg1[Cast(SQLITE_C_INT, (local12 + local3))]))
    local8 = c2fb_temp_33
    c2fb_temp_34 = CPtr(MemPage Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    local7 = c2fb_temp_34
    c2fb_temp_35 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))
    local11 = c2fb_temp_35
    c2fb_temp_36 = arg0->pBt
    local10 = c2fb_temp_36
    While Cast(SQLITE_C_INT, 1ULL)
        c2fb_temp_37 = Cast(SQLITE_C_INT, local0)
        local3 = c2fb_temp_37
        If (-Cast(SQLITE_C_INT, ((local3 > local6)))) Then
            c2fb_temp_38 = Cast(SQLITE_C_INT, local6)
            local3 = c2fb_temp_38
        End If
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, ((local2 >= local3)))) Then
            c2fb_temp_39 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, local9), CPtr(Const Any Ptr, local1), local3))
        Else
            If (-Cast(SQLITE_C_INT, ((local2 > Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_40 = Cast(SQLITE_C_INT, local2)
                local3 = c2fb_temp_40
                c2fb_temp_41 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, local9), CPtr(Const Any Ptr, local1), local3))
            Else
                c2fb_temp_42 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, local9), Cast(SQLITE_C_INT, &O0ULL), local3))
            End If
        End If
        c2fb_temp_43 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local0 - local3)))
        local0 = c2fb_temp_43
        If (-Cast(SQLITE_C_INT, ((local0 <= Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_0
        End If
        c2fb_temp_44 = CPtr(UByte Ptr, (local9 + local3))
        local9 = c2fb_temp_44
        c2fb_temp_45 = CPtr(Const UByte Ptr, (local1 + local3))
        local1 = c2fb_temp_45
        c2fb_temp_46 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local2 - local3)))
        local2 = c2fb_temp_46
        c2fb_temp_47 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local6 - local3)))
        local6 = c2fb_temp_47
        If (-Cast(SQLITE_C_INT, ((local6 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            local13 = Cast(SQLITE_C_INT, &O0ULL)
            local14 = local11
            If local10->autoVacuum Then
                Do
                    c2fb_temp_48 = local11
                    local11 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_48 + 1)))
                c2fb_flow_3:
                Loop While (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((ptrmapPageno((local10), (local11)) = (local11)))))) OrElse (-Cast(SQLITE_C_INT, ((local11 = (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, sqlite3PendingByte) \ ((local10)->pageSize)))) + Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))))))))))))
                c2fb_flow_2:
            End If
            c2fb_temp_49 = Cast(SQLITE_C_INT, allocateBtreePage(local10, CPtr(MemPage Ptr Ptr, @(local13)), CPtr(SQLITE_C_UINT Ptr, @(local11)), local11, Cast(SQLITE_C_INT, &O0ULL)))
            local4 = c2fb_temp_49
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local10->autoVacuum) AndAlso (-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                local15 = (IIf(local14, Cast(SQLITE_C_INT, 4ULL), Cast(SQLITE_C_INT, 3ULL)))
                ptrmapPut(local10, local11, local15, local14, CPtr(SQLITE_C_INT Ptr, @(local4)))
                If local4 Then
                    releasePage(local13)
                End If
            End If
            If local4 Then
                releasePage(local7)
                Return local4
            End If
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            sqlite3Put4byte(local8, local11)
            releasePage(local7)
            c2fb_temp_50 = local13
            local7 = c2fb_temp_50
            c2fb_temp_51 = local13->aData
            local8 = c2fb_temp_51
            sqlite3Put4byte(local8, Cast(SQLITE_C_INT, &O0ULL))
            c2fb_temp_52 = CPtr(UByte Ptr, @(local13->aData[Cast(SQLITE_C_INT, 4ULL)]))
            local9 = c2fb_temp_52
            c2fb_temp_53 = Cast(SQLITE_C_INT, Cast(SQLITE_C_UINT, (local10->usableSize - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL)))))
            local6 = c2fb_temp_53
        End If
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    releasePage(local7)
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

/' ------------------------------------------------------------------------- '/
/' Root-page creation and removal '/
/' ------------------------------------------------------------------------- '/

Private Function btreeCreateTable CDecl Alias "btreeCreateTable" (ByVal arg0 As Btree Ptr, ByVal arg1 As SQLITE_C_UINT Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As BtShared Ptr
    Dim local1 As MemPage Ptr
    Dim local2 As SQLITE_C_UINT
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As SQLITE_C_UINT
    Dim local6 As MemPage Ptr
    Dim c2fb_temp_0 As SQLITE_C_UINT
    Dim c2fb_temp_1 As SQLITE_C_UINT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim local7 As UByte
    Dim local8 As SQLITE_C_UINT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As MemPage Ptr
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_16 As SQLITE_C_UINT

    local0 = arg0->pBt
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If local0->autoVacuum Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        invalidateAllOverflowCache(local0)
        sqlite3BtreeGetMeta(arg0, Cast(SQLITE_C_INT, 4ULL), CPtr(SQLITE_C_UINT Ptr, @(local2)))
        If (-Cast(SQLITE_C_INT, ((local2 > btreePagecount(local0))))) Then
            Return sqlite3CorruptError(Cast(SQLITE_C_INT, 10120ULL))
        End If
        c2fb_temp_0 = local2
        local2 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_0 + 1)))
        While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local2 = ptrmapPageno(local0, local2))))) OrElse (-Cast(SQLITE_C_INT, ((local2 = (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, sqlite3PendingByte) \ ((local0)->pageSize)))) + Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))))))))))))
            c2fb_temp_1 = local2
            local2 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_1 + 1)))
        c2fb_flow_1:
        Wend
        c2fb_flow_0:
        ' C unused-parameter annotation
        c2fb_temp_2 = Cast(SQLITE_C_INT, allocateBtreePage(local0, CPtr(MemPage Ptr Ptr, @(local6)), CPtr(SQLITE_C_UINT Ptr, @(local5)), local2, Cast(SQLITE_C_INT, 1ULL)))
        local3 = c2fb_temp_2
        If (-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return local3
        End If
        If (-Cast(SQLITE_C_INT, ((local5 <> local2)))) Then
            local7 = Cast(SQLITE_C_INT, &O0ULL)
            local8 = Cast(SQLITE_C_INT, &O0ULL)
            c2fb_temp_3 = Cast(SQLITE_C_INT, saveAllCursors(local0, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)))
            local3 = c2fb_temp_3
            releasePage(local6)
            If (-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                Return local3
            End If
            c2fb_temp_4 = Cast(SQLITE_C_INT, btreeGetPage(local0, local2, CPtr(MemPage Ptr Ptr, @(local1)), Cast(SQLITE_C_INT, &O0ULL)))
            local3 = c2fb_temp_4
            If (-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                Return local3
            End If
            c2fb_temp_5 = Cast(SQLITE_C_INT, ptrmapGet(local0, local2, CPtr(UByte Ptr, @(local7)), CPtr(SQLITE_C_UINT Ptr, @(local8))))
            local3 = c2fb_temp_5
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local7) = Cast(SQLITE_C_INT, 1ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local7) = Cast(SQLITE_C_INT, 2ULL))))))))) Then
                c2fb_temp_6 = Cast(SQLITE_C_INT, sqlite3CorruptError(Cast(SQLITE_C_INT, 10168ULL)))
                local3 = c2fb_temp_6
            End If
            If (-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                releasePage(local1)
                Return local3
            End If
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_7 = Cast(SQLITE_C_INT, relocatePage(local0, local1, local7, local8, local5, Cast(SQLITE_C_INT, &O0ULL)))
            local3 = c2fb_temp_7
            releasePage(local1)
            If (-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                Return local3
            End If
            c2fb_temp_8 = Cast(SQLITE_C_INT, btreeGetPage(local0, local2, CPtr(MemPage Ptr Ptr, @(local1)), Cast(SQLITE_C_INT, &O0ULL)))
            local3 = c2fb_temp_8
            If (-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                Return local3
            End If
            c2fb_temp_9 = Cast(SQLITE_C_INT, sqlite3PagerWrite(local1->pDbPage))
            local3 = c2fb_temp_9
            If (-Cast(SQLITE_C_INT, ((local3 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                releasePage(local1)
                Return local3
            End If
        Else
            c2fb_temp_10 = local6
            local1 = c2fb_temp_10
        End If
        ptrmapPut(local0, local2, Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, &O0ULL), CPtr(SQLITE_C_INT Ptr, @(local3)))
        If local3 Then
            releasePage(local1)
            Return local3
        End If
        ' C unused-parameter annotation
        c2fb_temp_11 = Cast(SQLITE_C_INT, sqlite3BtreeUpdateMeta(arg0, Cast(SQLITE_C_INT, 4ULL), local2))
        local3 = c2fb_temp_11
        If (local3) Then
            releasePage(local1)
            Return local3
        End If
    Else
        c2fb_temp_12 = Cast(SQLITE_C_INT, allocateBtreePage(local0, CPtr(MemPage Ptr Ptr, @(local1)), CPtr(SQLITE_C_UINT Ptr, @(local2)), Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, &O0ULL)))
        local3 = c2fb_temp_12
        If local3 Then
            Return local3
        End If
    End If
    ' C unused-parameter annotation
    If Cast(SQLITE_C_INT, (arg2 And Cast(SQLITE_C_INT, 1ULL))) Then
        c2fb_temp_13 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H01ULL) Or Cast(SQLITE_C_INT, &H04ULL))) Or Cast(SQLITE_C_INT, &H08ULL))))
        local4 = c2fb_temp_13
    Else
        c2fb_temp_14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H02ULL) Or Cast(SQLITE_C_INT, &H08ULL))))
        local4 = c2fb_temp_14
    End If
    zeroPage(local1, local4)
    sqlite3PagerUnref(local1->pDbPage)
    ' C unused-parameter annotation
    c2fb_temp_15 = CPtr(SQLITE_C_UINT Ptr, @((*arg1)))
    c2fb_temp_16 = Cast(SQLITE_C_UINT, local2)
    (*c2fb_temp_15) = c2fb_temp_16
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function btreeDropTable CDecl Alias "btreeDropTable" (ByVal arg0 As Btree Ptr, ByVal arg1 As SQLITE_C_UINT, ByVal arg2 As SQLITE_C_INT Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As MemPage Ptr
    Dim local2 As BtShared Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim local3 As SQLITE_C_UINT
    Dim local4 As MemPage Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As MemPage Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_UINT
    Dim c2fb_temp_12 As SQLITE_C_UINT
    Dim c2fb_temp_13 As SQLITE_C_INT

    ' C automatic storage declaration
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    local2 = arg0->pBt
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((arg1 > btreePagecount(local2))))) Then
        Return sqlite3CorruptError(Cast(SQLITE_C_INT, 10383ULL))
    End If
    c2fb_temp_0 = Cast(SQLITE_C_INT, sqlite3BtreeClearTable(arg0, arg1, Cast(SQLITE_C_INT, &O0ULL)))
    local0 = c2fb_temp_0
    If local0 Then
        Return local0
    End If
    c2fb_temp_1 = Cast(SQLITE_C_INT, btreeGetPage(local2, Cast(SQLITE_C_UINT, arg1), CPtr(MemPage Ptr Ptr, @(local1)), Cast(SQLITE_C_INT, &O0ULL)))
    local0 = c2fb_temp_1
    If (local0) Then
        releasePage(local1)
        Return local0
    End If
    c2fb_temp_2 = CPtr(SQLITE_C_INT Ptr, @((*arg2)))
    c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_2) = c2fb_temp_3
    If local2->autoVacuum Then
        ' C automatic storage declaration
        sqlite3BtreeGetMeta(arg0, Cast(SQLITE_C_INT, 4ULL), CPtr(SQLITE_C_UINT Ptr, @(local3)))
        If (-Cast(SQLITE_C_INT, ((arg1 = local3)))) Then
            freePage(local1, CPtr(SQLITE_C_INT Ptr, @(local0)))
            releasePage(local1)
            If (-Cast(SQLITE_C_INT, ((local0 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                Return local0
            End If
        Else
            ' C automatic storage declaration
            releasePage(local1)
            c2fb_temp_4 = Cast(SQLITE_C_INT, btreeGetPage(local2, local3, CPtr(MemPage Ptr Ptr, @(local4)), Cast(SQLITE_C_INT, &O0ULL)))
            local0 = c2fb_temp_4
            If (-Cast(SQLITE_C_INT, ((local0 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                Return local0
            End If
            c2fb_temp_5 = Cast(SQLITE_C_INT, relocatePage(local2, local4, Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, &O0ULL), arg1, Cast(SQLITE_C_INT, &O0ULL)))
            local0 = c2fb_temp_5
            releasePage(local4)
            If (-Cast(SQLITE_C_INT, ((local0 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                Return local0
            End If
            c2fb_temp_6 = CPtr(MemPage Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            local4 = c2fb_temp_6
            c2fb_temp_7 = Cast(SQLITE_C_INT, btreeGetPage(local2, local3, CPtr(MemPage Ptr Ptr, @(local4)), Cast(SQLITE_C_INT, &O0ULL)))
            local0 = c2fb_temp_7
            If (-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_8 = Cast(SQLITE_C_INT, sqlite3PagerWrite(local4->pDbPage))
                local0 = c2fb_temp_8
            End If
            freePage(local4, CPtr(SQLITE_C_INT Ptr, @(local0)))
            releasePage(local4)
            If (-Cast(SQLITE_C_INT, ((local0 <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                Return local0
            End If
            c2fb_temp_9 = CPtr(SQLITE_C_INT Ptr, @((*arg2)))
            c2fb_temp_10 = Cast(SQLITE_C_INT, local3)
            (*c2fb_temp_9) = c2fb_temp_10
        End If
        c2fb_temp_11 = local3
        local3 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_11 - 1)))
        While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local3 = (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, sqlite3PendingByte) \ ((local2)->pageSize)))) + Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))))))))) OrElse ((-Cast(SQLITE_C_INT, ((ptrmapPageno((local2), (local3)) = (local3))))))))))
            c2fb_temp_12 = local3
            local3 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_12 - 1)))
        c2fb_flow_1:
        Wend
        c2fb_flow_0:
        ' C unused-parameter annotation
        c2fb_temp_13 = Cast(SQLITE_C_INT, sqlite3BtreeUpdateMeta(arg0, Cast(SQLITE_C_INT, 4ULL), local3))
        local0 = c2fb_temp_13
    Else
        freePage(local1, CPtr(SQLITE_C_INT Ptr, @(local0)))
        releasePage(local1)
    End If
    Return local0
End Function

/' end of sqlite3_bulk_btree_maintenance.bas '/
