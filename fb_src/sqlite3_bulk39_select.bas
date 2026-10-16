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
** This file contains C code routines that are called by the parser
** to handle SELECT statements in SQLite.
'/

/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_bulk39_select.bas

    Purpose:

        Implement the SELECT C2FB batch and the compound-expansion repair path.

    Responsibilities:

        - Keep translated SELECT bodies that pass isolated FreeBASIC compilation.
        - Keep file-local helper bodies in the same module as their callers.
        - Expand SELECT source terms, resolve CTE references, and check coroutine eligibility.
        - Rewrite compound SELECTs that need an outer ORDER BY wrapper.
        - Substitute flattened SELECT columns through expression and window trees.

    This file intentionally does NOT contain:

        - Upstream tests or test-support code.
        - Functions marked out of scope in PORTING_FUNCTIONS.csv.
        - SELECT code-generation paths that have not yet been ported.
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
#include once "sqlite3_vdbe_record.bi"
#include once "sqlite3_walker.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_resolve_types.bi"
#include once "sqlite3_walk_contexts.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_schema_types.bi"
Type c2fb_callback_82 As Function CDecl( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As Any Ptr _
) As SQLITE_C_INT
Type c2fb_callback_83 As Sub CDecl( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As Any Ptr _
)
Declare Function c2fb_crt_memset CDecl Alias "memset" ( _
    ByVal destination As Any Ptr, _
    ByVal fillValue As SQLITE_C_INT, _
    ByVal byteCount As SQLITE_SIZE_T _
) As Any Ptr
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
Declare Sub sqlite3SelectPrep CDecl Alias "sqlite3SelectPrep" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pNameContext As SqliteNameContext Ptr _
)
Declare Function substExpr CDecl Alias "substExpr" ( _
    ByVal pSubst As SqliteSubstContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
) As SqliteExpr Ptr
Declare Sub substExprList CDecl Alias "substExprList" ( _
    ByVal pSubst As SqliteSubstContext Ptr, _
    ByVal pList As SqliteExprList Ptr _
)
Declare Sub substSelect CDecl Alias "substSelect" ( _
    ByVal pSubst As SqliteSubstContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal doPrior As SQLITE_C_INT _
)
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

Declare Sub clearSelect CDecl Alias "clearSelect" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Function findRightmost CDecl Alias "findRightmost" (ByVal arg0 As SqliteSelect Ptr) As SqliteSelect Ptr
Declare Function tableAndColumnIndex CDecl Alias "tableAndColumnIndex" (ByVal arg0 As SqliteSrcList Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Const ZString Ptr, ByVal arg4 As SQLITE_C_INT Ptr, ByVal arg5 As SQLITE_C_INT Ptr, ByVal arg6 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub unsetJoinExpr CDecl Alias "unsetJoinExpr" (ByVal arg0 As SqliteExpr Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT)
Declare Sub codeOffset CDecl Alias "codeOffset" (ByVal arg0 As SqliteVdbe Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT)
Declare Function codeDistinct CDecl Alias "codeDistinct" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SqliteExprList Ptr, ByVal arg5 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub fixDistinctOpenEph CDecl Alias "fixDistinctOpenEph" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Declare Function checkSubqueryNestingDepth CDecl Alias "checkSubqueryNestingDepth" (ByVal arg0 As SqliteParseContext Ptr) As SQLITE_C_INT
Declare Sub computeLimitRegisters CDecl Alias "computeLimitRegisters" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SQLITE_C_INT)
Declare Function multiSelectCollSeq CDecl Alias "multiSelectCollSeq" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SQLITE_C_INT) As sqlite3CollSeq Ptr
Declare Function hasAnchor CDecl Alias "hasAnchor" (ByVal arg0 As SqliteSelect Ptr) As SQLITE_C_INT
Declare Function unionWithLimitOne CDecl Alias "unionWithLimitOne" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteSelect Ptr) As SQLITE_C_INT
Declare Function recomputeColumnsUsedExpr CDecl Alias "recomputeColumnsUsedExpr" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Sub srclistRenumberCursors CDecl Alias "srclistRenumberCursors" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT Ptr, ByVal arg2 As SqliteSrcList Ptr, ByVal arg3 As SQLITE_C_INT)
Declare Sub renumberCursorDoMapping CDecl Alias "renumberCursorDoMapping" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SQLITE_C_INT Ptr)
Declare Function renumberCursorsCb CDecl Alias "renumberCursorsCb" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function findLeftmostExprlist CDecl Alias "findLeftmostExprlist" (ByVal arg0 As SqliteSelect Ptr) As SqliteExprList Ptr
Declare Function compoundHasDifferentAffinities CDecl Alias "compoundHasDifferentAffinities" (ByVal arg0 As SqliteSelect Ptr) As SQLITE_C_INT
Declare Function disableUnusedSubqueryResultColumns CDecl Alias "disableUnusedSubqueryResultColumns" (ByVal arg0 As SqliteSrcItem Ptr) As SQLITE_C_INT
Declare Function minMaxQuery CDecl Alias "minMaxQuery" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SqliteExprList Ptr Ptr) As UByte
Declare Function cannotBeFunction CDecl Alias "cannotBeFunction" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcItem Ptr) As SQLITE_C_INT
Declare Function searchWith CDecl Alias "searchWith" (ByVal arg0 As SqliteWith Ptr, ByVal arg1 As SqliteSrcItem Ptr, ByVal arg2 As SqliteWith Ptr Ptr) As SqliteCte Ptr
Declare Function inAnyUsingClause CDecl Alias "inAnyUsingClause" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As SqliteSrcItem Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub selectAddSubqueryTypeInfo CDecl Alias "selectAddSubqueryTypeInfo" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteSelect Ptr)
Declare Sub sqlite3SelectAddTypeInfo CDecl Alias "sqlite3SelectAddTypeInfo" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr)
Declare Function havingToWhereExprCb CDecl Alias "havingToWhereExprCb" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function isSelfJoinView CDecl Alias "isSelfJoinView" (ByVal arg0 As SqliteSrcList Ptr, ByVal arg1 As SqliteSrcItem Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT) As SqliteSrcItem Ptr
Declare Function sameSrcAlias CDecl Alias "sameSrcAlias" (ByVal arg0 As SqliteSrcItem Ptr, ByVal arg1 As SqliteSrcList Ptr) As SQLITE_C_INT
Declare Function sqlite3CopySortOrder CDecl Alias "sqlite3CopySortOrder" (ByVal arg0 As SqliteExprList Ptr, ByVal arg1 As SqliteExprList Ptr) As SQLITE_C_INT
' c2fb skipped __bswap_16: outside the supported subset
' c2fb skipped __bswap_32: outside the supported subset
' c2fb skipped __bswap_64: outside the supported subset
' c2fb skipped __uint16_identity: outside the supported subset
' c2fb skipped __uint32_identity: outside the supported subset
' c2fb skipped __uint64_identity: outside the supported subset
' c2fb skipped sqlite3IsBinary: FreeBASIC body already exists
Private Sub clearSelect CDecl Alias "clearSelect" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SQLITE_C_INT)
    Dim local0 As SqliteSelect Ptr
    Dim c2fb_temp_0 As SqliteSelect Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT

    ' C unused-parameter annotation
    While arg1
        local0 = CPtr(SqliteSelect Ptr, arg1->pPrior)
        sqlite3ExprListDelete(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, arg1->pEList)))
        sqlite3SrcListDelete(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteSrcList Ptr, arg1->pSrc)))
        sqlite3ExprDelete(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg1->pWhere)))
        sqlite3ExprListDelete(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, arg1->pGroupBy)))
        sqlite3ExprDelete(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg1->pHaving)))
        sqlite3ExprListDelete(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, arg1->pOrderBy)))
        sqlite3ExprDelete(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg1->pLimit)))
        If (CPtr(SqliteWith Ptr, arg1->pWith)) Then
            sqlite3WithDelete(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteWith Ptr, arg1->pWith)))
        End If
#ifndef SQLITE_OMIT_WINDOWFUNC
        If (arg1->pWinDefn) Then
            sqlite3WindowListDelete(CPtr(Any Ptr, arg0), arg1->pWinDefn)
        End If
        While arg1->pWin
            ' C unused-parameter annotation
            sqlite3WindowUnlinkFromSelect(arg1->pWin)
        c2fb_flow_3:
        Wend
        c2fb_flow_2:
#endif
        If arg2 Then
            sqlite3DbNNFreeNN(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1))
        End If
        c2fb_temp_0 = local0
        arg1 = c2fb_temp_0
        c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
        arg2 = c2fb_temp_1
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
End Sub

' c2fb skipped sqlite3SelectDestInit: FreeBASIC body already exists
' c2fb skipped sqlite3SelectNew: FreeBASIC body already exists
' c2fb skipped sqlite3SelectDelete: FreeBASIC body already exists
' c2fb skipped sqlite3SelectDeleteGeneric: FreeBASIC body already exists
Private Function findRightmost CDecl Alias "findRightmost" (ByVal arg0 As SqliteSelect Ptr) As SqliteSelect Ptr
    Dim c2fb_temp_0 As SqliteSelect Ptr

    While CPtr(SqliteSelect Ptr, arg0->pNext)
        c2fb_temp_0 = CPtr(SqliteSelect Ptr, arg0->pNext)
        arg0 = c2fb_temp_0
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    Return arg0
End Function

' c2fb skipped sqlite3JoinType: outside the supported subset
' c2fb skipped sqlite3ColumnIndex: FreeBASIC body already exists
' c2fb skipped sqlite3SrcItemColumnUsed: outside the supported subset
Private Function tableAndColumnIndex CDecl Alias "tableAndColumnIndex" (ByVal arg0 As SqliteSrcList Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As Const ZString Ptr, ByVal arg4 As SQLITE_C_INT Ptr, ByVal arg5 As SQLITE_C_INT Ptr, ByVal arg6 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, arg1)
    local0 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((local0 <= arg2))))
        c2fb_temp_2 = Cast(SQLITE_C_INT, sqlite3ColumnIndex(CPtr(Any Ptr, CPtr(SqliteTable Ptr, arg0->a(local0).pSTab)), arg3))
        local1 = c2fb_temp_2
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local1 >= Cast(SQLITE_C_INT, &O0ULL))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg6 = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (CPtr(SqliteColumn Ptr, @(CPtr(SqliteTable Ptr, arg0->a(local0).pSTab)->aCol[local1])))->colFlags) And Cast(SQLITE_C_INT, &H0002ULL)))) <> Cast(SQLITE_C_INT, &O0ULL)))))) = Cast(SQLITE_C_INT, &O0ULL)))))))))))))) Then
            If arg4 Then
                sqlite3SrcItemColumnUsed(CPtr(Any Ptr, CPtr(SqliteSrcItem Ptr, @(arg0->a(local0)))), local1)
                c2fb_temp_3 = @((*arg4))
                c2fb_temp_4 = Cast(SQLITE_C_INT, local0)
                (*c2fb_temp_3) = c2fb_temp_4
                c2fb_temp_5 = @((*arg5))
                c2fb_temp_6 = Cast(SQLITE_C_INT, local1)
                (*c2fb_temp_5) = c2fb_temp_6
            End If
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
    c2fb_flow_1:
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    Wend
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

' c2fb skipped sqlite3SetJoinExpr: FreeBASIC body already exists
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
            c2fb_temp_0 = @((arg0)->flags)
            c2fb_temp_1 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_0)) And Cast(SQLITE_C_UINT, (Not Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000001ULL) Or Cast(SQLITE_C_INT, &H000002ULL))))))))))
            (*c2fb_temp_0) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_0)) And Cast(SQLITE_C_UINT, (Not Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000001ULL) Or Cast(SQLITE_C_INT, &H000002ULL)))))))))))
            c2fb_temp_1 = Cast(SQLITE_C_UINT, (*c2fb_temp_0))
            If (-Cast(SQLITE_C_INT, ((arg1 >= Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_2 = @((arg0)->flags)
                c2fb_temp_3 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_2)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000002ULL))))))
                (*c2fb_temp_2) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_2)) Or Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000002ULL)))))))
                c2fb_temp_3 = Cast(SQLITE_C_UINT, (*c2fb_temp_2))
            End If
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->op) = Cast(SQLITE_C_INT, 168ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((arg0->iTable = arg1)))))))) AndAlso (-Cast(SQLITE_C_INT, (arg2 = 0))))))) Then
            c2fb_temp_4 = @((arg0)->flags)
            c2fb_temp_5 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_4)) And Cast(SQLITE_C_UINT, (Not Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H200000ULL))))))))
            (*c2fb_temp_4) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_4)) And Cast(SQLITE_C_UINT, (Not Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H200000ULL)))))))))
            c2fb_temp_5 = Cast(SQLITE_C_UINT, (*c2fb_temp_4))
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->op) = Cast(SQLITE_C_INT, 172ULL))))) Then
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            If CPtr(SqliteExprList Ptr, arg0->x.pList) Then
                ' C automatic storage declaration
                c2fb_temp_6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local0 = c2fb_temp_6
                While (-Cast(SQLITE_C_INT, ((local0 < CPtr(SqliteExprList Ptr, arg0->x.pList)->nExpr))))
                    unsetJoinExpr(CPtr(SqliteExpr Ptr, CPtr(SqliteExprList Ptr, arg0->x.pList)->a(local0).pExpr), arg1, arg2)
                c2fb_flow_3:
                    c2fb_temp_7 = local0
                    local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_7 + 1)))
                Wend
                c2fb_flow_2:
            End If
        End If
        unsetJoinExpr(CPtr(SqliteExpr Ptr, arg0->pLeft), arg1, arg2)
        c2fb_temp_8 = CPtr(SqliteExpr Ptr, arg0->pRight)
        arg0 = c2fb_temp_8
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
End Sub

' c2fb skipped sqlite3ProcessJoin: outside the supported subset
' c2fb skipped innerLoopLoadRow: outside the supported subset
' c2fb skipped makeSorterRecord: outside the supported subset
' c2fb skipped pushOntoSorter: outside the supported subset
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
            c2fb_temp_2 = @(arg0->nMem)
            c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_2) + local1)))
            (*c2fb_temp_2) = c2fb_temp_3
            c2fb_temp_4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (sqlite3VdbeCurrentAddr(local2) + local1)))
            local4 = c2fb_temp_4
            c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local3 = c2fb_temp_5
            While (-Cast(SQLITE_C_INT, ((local3 < local1))))
                local6 = CPtr(sqlite3CollSeq Ptr, sqlite3ExprCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, arg4->a(local3).pExpr))))
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
            c2fb_temp_0 = @(local1->opcode)
            c2fb_temp_1 = Cast(UByte, Cast(SQLITE_C_INT, 77ULL))
            (*c2fb_temp_0) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 77ULL)))
            c2fb_temp_1 = Cast(UByte, (*c2fb_temp_0))
            c2fb_temp_2 = @(local1->p1)
            c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
            (*c2fb_temp_2) = c2fb_temp_3
            c2fb_temp_4 = @(local1->p2)
            c2fb_temp_5 = Cast(SQLITE_C_INT, arg2)
            (*c2fb_temp_4) = c2fb_temp_5
        End If
    End If
End Sub

' c2fb skipped selectInnerLoop: outside the supported subset
Function sqlite3KeyInfoAlloc CDecl Alias "sqlite3KeyInfoAlloc" ( _
    ByVal dbArgument As Any Ptr, _
    ByVal keyColumnCount As SQLITE_C_INT, _
    ByVal extraColumnCount As SQLITE_C_INT _
) As Any Ptr
    Dim db As sqlite3 Ptr = CPtr(sqlite3 Ptr, dbArgument)
    If db = 0 OrElse keyColumnCount < 0 OrElse extraColumnCount < 0 Then Return 0

    Dim totalColumnCount As sqlite3_uint64 = _
        Cast(sqlite3_uint64, keyColumnCount) + _
        Cast(sqlite3_uint64, extraColumnCount)
    ' KeyInfo stores both column counts in 16-bit fields.
    If totalColumnCount > &HFFFF Then
        sqlite3OomFault(CPtr(Any Ptr, db))
        Return 0
    End If

    Dim keyInfoHeaderBytes As sqlite3_uint64 = _
        Cast(sqlite3_uint64, SizeOf(sqlite3VdbeKeyInfoPrefix)) - _
        Cast(sqlite3_uint64, SizeOf(Any Ptr))
    Dim extraBytes As sqlite3_uint64 = totalColumnCount * _
        Cast(sqlite3_uint64, SizeOf(Any Ptr) + SizeOf(UByte))
    If keyInfoHeaderBytes > SQLITE_MAX_ALLOCATION_SIZE OrElse _
       extraBytes > SQLITE_MAX_ALLOCATION_SIZE - keyInfoHeaderBytes Then
        sqlite3OomFault(CPtr(Any Ptr, db))
        Return 0
    End If

    Dim pKeyInfo As sqlite3VdbeKeyInfoPrefix Ptr = CPtr( _
        sqlite3VdbeKeyInfoPrefix Ptr, _
        sqlite3DbMallocRawNN(db, keyInfoHeaderBytes + extraBytes))
    If pKeyInfo = 0 Then
        sqlite3OomFault(CPtr(Any Ptr, db))
        Return 0
    End If

    pKeyInfo->nRef = 1
    pKeyInfo->enc = db->enc
    pKeyInfo->nKeyField = Cast(UShort, keyColumnCount)
    pKeyInfo->nAllField = Cast(UShort, totalColumnCount)
    pKeyInfo->db = db
    Dim pCollationBytes As UByte Ptr = _
        CPtr(UByte Ptr, @pKeyInfo->aColl(0))
    pKeyInfo->aSortFlags = pCollationBytes + _
        totalColumnCount * Cast(sqlite3_uint64, SizeOf(Any Ptr))
    c2fb_crt_memset(pCollationBytes, 0, Cast(SQLITE_SIZE_T, extraBytes))
    Return CPtr(Any Ptr, pKeyInfo)
End Function
' c2fb skipped sqlite3KeyInfoUnref: FreeBASIC body already exists
' c2fb skipped sqlite3KeyInfoRef: FreeBASIC body already exists
' c2fb skipped sqlite3KeyInfoFromExprList: outside the supported subset
' c2fb skipped sqlite3SelectOpName: FreeBASIC body already exists
' c2fb skipped explainTempTable: outside the supported subset
' c2fb skipped generateSortTail: outside the supported subset
' c2fb skipped columnTypeImpl: outside the supported subset
' c2fb skipped generateColumnTypes: outside the supported subset
' c2fb skipped sqlite3GenerateColumnNames: outside the supported subset
' c2fb skipped sqlite3ColumnsFromExprList: outside the supported subset
' c2fb skipped sqlite3SubqueryColumnTypes: outside the supported subset
Private Function checkSubqueryNestingDepth CDecl Alias "checkSubqueryNestingDepth" (ByVal arg0 As SqliteParseContext Ptr) As SQLITE_C_INT
    If (-Cast(SQLITE_C_INT, ((arg0->nNestSel >= arg0->db->aLimit(Cast(SQLITE_C_INT, 3ULL)))))) Then
        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"VIEWs and/or subqueries nested too deep"))
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

' c2fb skipped sqlite3ResultSetOfSelect: outside the supported subset
' c2fb skipped sqlite3GetVdbe: FreeBASIC body already exists
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
    local4 = CPtr(SqliteExpr Ptr, arg1->pLimit)
    If arg1->iLimit Then
        Return
    End If
    If local4 Then
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        c2fb_temp_4 = @(arg1->iLimit)
        c2fb_temp_0 = @(arg0->nMem)
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
        If sqlite3ExprIsInteger(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local4->pLeft)), CPtr(SQLITE_C_INT Ptr, @(local3)), CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, &O0ULL)) Then
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 73ULL), local3, local1)
            ' empty C statement
            If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                sqlite3VdbeGoto(local0, arg2)
            Else
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local3 >= Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->nSelectRow) > Cast(SQLITE_C_INT, sqlite3LogEst(Cast(sqlite3_uint64, local3))))))))))) Then
                    c2fb_temp_7 = @(arg1->nSelectRow)
                    c2fb_temp_8 = Cast(Short, sqlite3LogEst(Cast(sqlite3_uint64, local3)))
                    (*c2fb_temp_7) = c2fb_temp_8
                    c2fb_temp_9 = @(arg1->selFlags)
                    c2fb_temp_10 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_9)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0004000ULL)))))
                    (*c2fb_temp_9) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_9)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0004000ULL))))))
                    c2fb_temp_10 = Cast(SQLITE_C_UINT, (*c2fb_temp_9))
                End If
            End If
        Else
            sqlite3ExprCode(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local4->pLeft)), local1)
            sqlite3VdbeAddOp1(local0, Cast(SQLITE_C_INT, 13ULL), local1)
            ' empty C statement
            ' empty C statement
            sqlite3MayAbort(CPtr(Any Ptr, arg0))
            sqlite3VdbeAddOp2(local0, Cast(SQLITE_C_INT, 17ULL), local1, arg2)
            ' empty C statement
        End If
        If CPtr(SqliteExpr Ptr, local4->pRight) Then
            c2fb_temp_15 = @(arg1->iOffset)
            c2fb_temp_11 = @(arg0->nMem)
            c2fb_temp_12 = (*c2fb_temp_11)
            (*c2fb_temp_11) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_12 + 1)))
            c2fb_temp_13 = (*c2fb_temp_11)
            c2fb_temp_14 = Cast(SQLITE_C_INT, c2fb_temp_13)
            local2 = c2fb_temp_14
            c2fb_temp_16 = Cast(SQLITE_C_INT, c2fb_temp_14)
            (*c2fb_temp_15) = c2fb_temp_16
            c2fb_temp_17 = @(arg0->nMem)
            c2fb_temp_18 = (*c2fb_temp_17)
            (*c2fb_temp_17) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_18 + 1)))
            sqlite3ExprCode(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local4->pRight)), local2)
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
    If CPtr(SqliteSelect Ptr, arg1->pPrior) Then
        c2fb_temp_0 = CPtr(sqlite3CollSeq Ptr, multiSelectCollSeq(arg0, CPtr(SqliteSelect Ptr, arg1->pPrior), arg2))
        local0 = c2fb_temp_0
    Else
        c2fb_temp_1 = CPtr(sqlite3CollSeq Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        local0 = c2fb_temp_1
    End If
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local0 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso ((-Cast(SQLITE_C_INT, ((arg2 < CPtr(SqliteExprList Ptr, arg1->pEList)->nExpr))))))))) Then
        c2fb_temp_2 = CPtr(sqlite3CollSeq Ptr, sqlite3ExprCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, CPtr(SqliteExprList Ptr, arg1->pEList)->a(arg2).pExpr))))
        local0 = c2fb_temp_2
    End If
    Return local0
End Function

' c2fb skipped multiSelectByMergeKeyInfo: outside the supported subset
' c2fb skipped generateWithRecursiveQuery: outside the supported subset
' c2fb skipped multiSelectValues: outside the supported subset
Private Function hasAnchor CDecl Alias "hasAnchor" (ByVal arg0 As SqliteSelect Ptr) As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteSelect Ptr

    While (-Cast(SQLITE_C_INT, ((arg0 AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg0->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0002000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))
        c2fb_temp_0 = CPtr(SqliteSelect Ptr, arg0->pPrior)
        arg0 = c2fb_temp_0
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    Return (-Cast(SQLITE_C_INT, ((arg0 <> Cast(SQLITE_C_INT, &O0ULL)))))
End Function

Private Function unionWithLimitOne CDecl Alias "unionWithLimitOne" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteSelect Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT

    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) <> Cast(SQLITE_C_INT, 135ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((CPtr(SqliteExpr Ptr, arg1->pLimit) = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If CPtr(SqliteExpr Ptr, CPtr(SqliteExpr Ptr, arg1->pLimit)->pRight) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_0
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((sqlite3ExprIsInteger(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, CPtr(SqliteExpr Ptr, arg1->pLimit)->pLeft)), CPtr(SQLITE_C_INT Ptr, @(local0)), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)) = Cast(SQLITE_C_INT, &O0ULL))))) Then
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

' c2fb skipped multiSelect: outside the supported subset
' c2fb skipped sqlite3SelectWrongNumTermsError: FreeBASIC body already exists
' c2fb skipped generateOutputSubroutine: outside the supported subset
' c2fb skipped multiSelectByMerge: outside the supported subset
' c2fb skipped substExpr: outside the supported subset
' c2fb skipped substExprList: outside the supported subset
' c2fb skipped substSelect: outside the supported subset
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
    c2fb_temp_1 = @(local0->colUsed)
    c2fb_temp_2 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, ((*c2fb_temp_1) Or sqlite3ExprColUsed(CPtr(Any Ptr, arg1)))))
    (*c2fb_temp_1) = c2fb_temp_2
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

' c2fb skipped recomputeColumnsUsed: outside the supported subset
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
                c2fb_temp_6 = @(arg1[Cast(SQLITE_C_INT, (local1->iCursor + Cast(SQLITE_C_INT, 1ULL)))])
                c2fb_temp_4 = @(arg0->nTab)
                c2fb_temp_5 = (*c2fb_temp_4)
                (*c2fb_temp_4) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_5 + 1)))
                c2fb_temp_7 = Cast(SQLITE_C_INT, c2fb_temp_5)
                (*c2fb_temp_6) = c2fb_temp_7
            End If
            c2fb_temp_8 = @(local1->iCursor)
            c2fb_temp_9 = Cast(SQLITE_C_INT, arg1[Cast(SQLITE_C_INT, (local1->iCursor + Cast(SQLITE_C_INT, 1ULL)))])
            (*c2fb_temp_8) = c2fb_temp_9
            If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                c2fb_temp_10 = CPtr(SqliteSelect Ptr, CPtr(SqliteSubquery Ptr, local1->u4.pSubq)->pSelect)
                local2 = c2fb_temp_10
                While local2
                    srclistRenumberCursors(arg0, arg1, CPtr(SqliteSrcList Ptr, local2->pSrc), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
                c2fb_flow_3:
                    c2fb_temp_11 = CPtr(SqliteSelect Ptr, local2->pPrior)
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
        c2fb_temp_0 = @((*arg1))
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

' c2fb skipped renumberCursors: outside the supported subset
Private Function findLeftmostExprlist CDecl Alias "findLeftmostExprlist" (ByVal arg0 As SqliteSelect Ptr) As SqliteExprList Ptr
    Dim c2fb_temp_0 As SqliteSelect Ptr

    While CPtr(SqliteSelect Ptr, arg0->pPrior)
        c2fb_temp_0 = CPtr(SqliteSelect Ptr, arg0->pPrior)
        arg0 = c2fb_temp_0
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    Return CPtr(SqliteExprList Ptr, arg0->pEList)
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
    c2fb_temp_0 = CPtr(SqliteExprList Ptr, arg0->pEList)
    local1 = c2fb_temp_0
    c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_1
    While (-Cast(SQLITE_C_INT, ((local0 < local1->nExpr))))
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C unused-parameter annotation
        c2fb_temp_3 = Cast(Byte, sqlite3ExprAffinity(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local1->a(local0).pExpr))))
        local2 = c2fb_temp_3
        c2fb_temp_4 = CPtr(SqliteSelect Ptr, arg0->pPrior)
        local3 = c2fb_temp_4
        While local3
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, sqlite3ExprAffinity(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, CPtr(SqliteExprList Ptr, local3->pEList)->a(local0).pExpr)))) <> Cast(SQLITE_C_INT, local2))))) Then
                Return Cast(SQLITE_C_INT, 1ULL)
            End If
        c2fb_flow_3:
            c2fb_temp_5 = CPtr(SqliteSelect Ptr, local3->pPrior)
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

' c2fb skipped flattenSubquery: outside the supported subset
' c2fb skipped constInsert: outside the supported subset
' c2fb skipped findConstInWhere: outside the supported subset
' c2fb skipped propagateConstantExprRewriteOne: outside the supported subset
' c2fb skipped propagateConstantExprRewrite: outside the supported subset
' c2fb skipped propagateConstants: outside the supported subset
' c2fb skipped pushDownWindowCheck: outside the supported subset
' c2fb skipped pushDownWhereTerms: outside the supported subset
Function disableUnusedSubqueryResultColumns CDecl Alias "disableUnusedSubqueryResultColumns" (ByVal arg0 As SqliteSrcItem Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SqliteSelect Ptr
    Dim local2 As SqliteSelect Ptr
    Dim local3 As SqliteTable Ptr
    Dim local4 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim local6 As sqlite3_uint64
    Dim c2fb_temp_0 As SqliteTable Ptr
    Dim c2fb_temp_1 As SqliteSelect Ptr
    Dim c2fb_temp_2 As SqliteSelect Ptr
    Dim c2fb_temp_3 As SqliteSelect Ptr
    Dim c2fb_temp_4 As sqlite3_uint64
    Dim local7 As SqliteExprList Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim local8 As UShort
    Dim c2fb_temp_7 As UShort
    Dim c2fb_temp_8 As sqlite3_uint64
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim local9 As sqlite3_uint64
    Dim c2fb_temp_12 As SqliteSelect Ptr
    Dim c2fb_temp_13 As SqliteSelect Ptr
    Dim local10 As SqliteExpr Ptr
    Dim c2fb_temp_14 As u8 Ptr
    Dim c2fb_temp_15 As UByte
    Dim c2fb_temp_16 As u32 Ptr
    Dim c2fb_temp_17 As SQLITE_C_UINT
    Dim c2fb_temp_18 As u32 Ptr
    Dim c2fb_temp_19 As SQLITE_C_UINT
    Dim c2fb_temp_20 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local5 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg0->fg.flags) Shr 4) And Cast(SQLITE_C_UINT, &H1ULL))) OrElse Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg0->fg.flags) Shr 9) And Cast(SQLITE_C_UINT, &H1ULL))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(SqliteTable Ptr, arg0->pSTab)
    local3 = c2fb_temp_0
    ' C unused-parameter annotation
    c2fb_temp_1 = CPtr(SqliteSelect Ptr, CPtr(SqliteSubquery Ptr, arg0->u4.pSubq)->pSelect)
    local1 = c2fb_temp_1
    ' C unused-parameter annotation
    c2fb_temp_2 = local1
    local2 = c2fb_temp_2
    While local2
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local2->selFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0000001ULL) Or Cast(SQLITE_C_INT, &H0000008ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            ' empty C statement
            ' empty C statement
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        If (-Cast(SQLITE_C_INT, ((CPtr(SqliteSelect Ptr, local2->pPrior) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->op) <> Cast(SQLITE_C_INT, 136ULL))))))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
#ifndef SQLITE_OMIT_WINDOWFUNC
        If local2->pWin Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
#endif
    c2fb_flow_1:
        c2fb_temp_3 = CPtr(SqliteSelect Ptr, local2->pPrior)
        local2 = c2fb_temp_3
    Wend
    c2fb_flow_0:
    c2fb_temp_4 = Cast(sqlite3_uint64, arg0->colUsed)
    local6 = c2fb_temp_4
    If CPtr(SqliteExprList Ptr, local1->pOrderBy) Then
        local7 = CPtr(SqliteExprList Ptr, local1->pOrderBy)
        c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local4 = c2fb_temp_5
        While (-Cast(SQLITE_C_INT, ((local4 < local7->nExpr))))
            local8 = local7->a(local4).u.x.iOrderByCol
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local8) > Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_7 = local8
                local8 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_7) - 1)))
                c2fb_temp_8 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local6 Or Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (IIf((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local8) >= (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))))))), Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))) - Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, local8))))))))
                local6 = c2fb_temp_8
            End If
        c2fb_flow_3:
            c2fb_temp_6 = local4
            local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 + 1)))
        Wend
        c2fb_flow_2:
    End If
    c2fb_temp_9 = Cast(SQLITE_C_INT, local3->nCol)
    local0 = c2fb_temp_9
    c2fb_temp_10 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local4 = c2fb_temp_10
    While (-Cast(SQLITE_C_INT, ((local4 < local0))))
        local9 = IIf((-Cast(SQLITE_C_INT, ((local4 < Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))) - Cast(SQLITE_C_INT, 1ULL))))))), (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local4)))), (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))) - Cast(SQLITE_C_INT, 1ULL))))))))
        If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local9 And local6))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            Goto c2fb_flow_5
        End If
        c2fb_temp_12 = local1
        local2 = c2fb_temp_12
        While local2
            local10 = CPtr(SqliteExpr Ptr, CPtr(SqliteExprList Ptr, local2->pEList)->a(local4).pExpr)
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local10->op) = Cast(SQLITE_C_INT, 122ULL))))) Then
                Goto c2fb_flow_7
            End If
            c2fb_temp_14 = @(local10->op)
            c2fb_temp_15 = Cast(UByte, Cast(SQLITE_C_INT, 122ULL))
            (*c2fb_temp_14) = Cast(u8, Cast(UByte, Cast(SQLITE_C_INT, 122ULL)))
            c2fb_temp_15 = Cast(UByte, (*c2fb_temp_14))
            c2fb_temp_16 = @((local10)->flags)
            c2fb_temp_17 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_16)) And Cast(SQLITE_C_UINT, (Not Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H002000ULL) Or Cast(SQLITE_C_INT, &H080000ULL))))))))))
            (*c2fb_temp_16) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_16)) And Cast(SQLITE_C_UINT, (Not Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H002000ULL) Or Cast(SQLITE_C_INT, &H080000ULL)))))))))))
            c2fb_temp_17 = Cast(SQLITE_C_UINT, (*c2fb_temp_16))
            c2fb_temp_18 = @(local2->selFlags)
            c2fb_temp_19 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_18)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H1000000ULL)))))
            (*c2fb_temp_18) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_18)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H1000000ULL))))))
            c2fb_temp_19 = Cast(SQLITE_C_UINT, (*c2fb_temp_18))
            c2fb_temp_20 = local5
            local5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_20 + 1)))
        c2fb_flow_7:
            c2fb_temp_13 = CPtr(SqliteSelect Ptr, local2->pPrior)
            local2 = c2fb_temp_13
        Wend
        c2fb_flow_6:
    c2fb_flow_5:
        c2fb_temp_11 = local4
        local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_11 + 1)))
    Wend
    c2fb_flow_4:
    Return local5
End Function

Private Function minMaxQuery CDecl Alias "minMaxQuery" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SqliteExprList Ptr Ptr) As UByte
    Dim local0 As SQLITE_C_INT
    Dim local1 As SqliteExprList Ptr
    Dim local2 As Const ZString Ptr
    Dim local3 As SqliteExprList Ptr
    Dim local4 As UByte
    Dim c2fb_temp_0 As SqliteExprList Ptr
    Dim c2fb_temp_1 As Const ZString Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As UByte
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As UByte
    Dim c2fb_temp_6 As SqliteExprList Ptr
    Dim c2fb_temp_7 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_8 As SqliteExprList Ptr
    Dim c2fb_temp_9 As u8 Ptr
    Dim c2fb_temp_10 As UByte

    local0 = Cast(SQLITE_C_INT, &H0000ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local4 = Cast(SQLITE_C_INT, &O0ULL)
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(SqliteExprList Ptr, arg1->x.pList)
    local1 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local1->nExpr <> Cast(SQLITE_C_INT, 1ULL))))))))) OrElse ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H1000000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) OrElse ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg0)->dbOptFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H00010000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
        Return local0
    End If
    ' C unused-parameter annotation
    c2fb_temp_1 = CPtr(Const ZString Ptr, CPtr(ZString Ptr, arg1->u.zToken))
    local2 = c2fb_temp_1
    If (-Cast(SQLITE_C_INT, ((sqlite3StrICmp(local2, StrPtr(!"min")) = Cast(SQLITE_C_INT, &O0ULL))))) Then
        c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &H0001ULL))
        local0 = c2fb_temp_2
        If sqlite3ExprCanBeNull(CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local1->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr))) Then
            c2fb_temp_3 = Cast(UByte, Cast(SQLITE_C_INT, &H02ULL))
            local4 = c2fb_temp_3
        End If
    Else
        If (-Cast(SQLITE_C_INT, ((sqlite3StrICmp(local2, StrPtr(!"max")) = Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &H0002ULL))
            local0 = c2fb_temp_4
            c2fb_temp_5 = Cast(UByte, Cast(SQLITE_C_INT, &H01ULL))
            local4 = c2fb_temp_5
        Else
            Return local0
        End If
    End If
    c2fb_temp_7 = @((*arg2))
    c2fb_temp_6 = CPtr(SqliteExprList Ptr, sqlite3ExprListDup(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local1), Cast(SQLITE_C_INT, &O0ULL)))
    local3 = c2fb_temp_6
    c2fb_temp_8 = c2fb_temp_6
    (*c2fb_temp_7) = c2fb_temp_8
    ' C unused-parameter annotation
    If local3 Then
        c2fb_temp_9 = @(local3->a(Cast(SQLITE_C_INT, &O0ULL)).fg.sortFlags)
        c2fb_temp_10 = Cast(UByte, local4)
        (*c2fb_temp_9) = Cast(u8, Cast(UByte, local4))
        c2fb_temp_10 = Cast(UByte, (*c2fb_temp_9))
    End If
    Return local0
End Function

' c2fb skipped isSimpleCount: outside the supported subset
' c2fb skipped sqlite3IndexedByLookup: outside the supported subset
' c2fb skipped convertCompoundSelectToSubquery: outside the supported subset
Private Function cannotBeFunction CDecl Alias "cannotBeFunction" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcItem Ptr) As SQLITE_C_INT
    If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg1->fg.flags) Shr 3) And Cast(SQLITE_C_UINT, &H1ULL))) Then
        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"'%s' is not a function"), arg1->zName)
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function searchWith CDecl Alias "searchWith" (ByVal arg0 As SqliteWith Ptr, ByVal arg1 As SqliteSrcItem Ptr, ByVal arg2 As SqliteWith Ptr Ptr) As SqliteCte Ptr
    Dim local0 As Const ZString Ptr
    Dim local1 As SqliteWith Ptr
    Dim c2fb_temp_0 As SqliteWith Ptr
    Dim c2fb_temp_1 As SqliteWith Ptr
    Dim local2 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SqliteWith Ptr Ptr
    Dim c2fb_temp_5 As SqliteWith Ptr

    local0 = arg1->zName
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = arg0
    local1 = c2fb_temp_0
    While local1
        ' C automatic storage declaration
        c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local2 = c2fb_temp_2
        While (-Cast(SQLITE_C_INT, ((local2 < local1->nCte))))
            If (-Cast(SQLITE_C_INT, ((sqlite3StrICmp(local0, CPtr(Const ZString Ptr, local1->a(local2).zName)) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_4 = @((*arg2))
                c2fb_temp_5 = local1
                (*c2fb_temp_4) = c2fb_temp_5
                Return CPtr(SqliteCte Ptr, @(local1->a(local2)))
            End If
        c2fb_flow_3:
            c2fb_temp_3 = local2
            local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_3 + 1)))
        Wend
        c2fb_flow_2:
        If local1->bView Then
            Goto c2fb_flow_0
        End If
    c2fb_flow_1:
        c2fb_temp_1 = CPtr(SqliteWith Ptr, local1->pOuter)
        local1 = c2fb_temp_1
    Wend
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

' c2fb skipped sqlite3WithPush: FreeBASIC body already exists
' c2fb skipped resolveFromTermToCte: outside the supported subset
' c2fb skipped sqlite3SelectPopWith: FreeBASIC body already exists
' c2fb skipped sqlite3ExpandSubquery: outside the supported subset
Private Function inAnyUsingClause CDecl Alias "inAnyUsingClause" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As SqliteSrcItem Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SqliteSrcItem Ptr

    While (-Cast(SQLITE_C_INT, ((arg2 > Cast(SQLITE_C_INT, &O0ULL)))))
        c2fb_temp_0 = arg2
        arg2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_0 - 1)))
        c2fb_temp_1 = arg1
        arg1 = (c2fb_temp_1 + 1)
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg1->fg.flags) Shr 11) And Cast(SQLITE_C_UINT, &H1ULL))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_1
        End If
        If ((-Cast(SQLITE_C_INT, ((CPtr(SqliteIdList Ptr, arg1->u3.pUsing) = Cast(SQLITE_C_INT, &O0ULL)))))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, ((sqlite3IdListIndex(CPtr(Any Ptr, CPtr(SqliteIdList Ptr, arg1->u3.pUsing)), arg0) >= Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

' c2fb skipped selectExpander: outside the supported subset
' c2fb skipped sqlite3SelectExpand: outside the supported subset
Private Sub selectAddSubqueryTypeInfo CDecl Alias "selectAddSubqueryTypeInfo" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteSelect Ptr)
    Dim local0 As SqliteParseContext Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SqliteSrcList Ptr
    Dim local3 As SqliteSrcItem Ptr
    Dim c2fb_temp_0 As u32 Ptr
    Dim c2fb_temp_1 As SQLITE_C_UINT
    Dim c2fb_temp_2 As SqliteParseContext Ptr
    Dim c2fb_temp_3 As SqliteSrcList Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SqliteSrcItem Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SqliteSrcItem Ptr
    Dim local4 As SqliteTable Ptr
    Dim local5 As SqliteSelect Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    If Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000080ULL)))) Then
        Return
    End If
    c2fb_temp_0 = @(arg1->selFlags)
    c2fb_temp_1 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_0)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000080ULL)))))
    (*c2fb_temp_0) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_0)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000080ULL))))))
    c2fb_temp_1 = Cast(SQLITE_C_UINT, (*c2fb_temp_0))
    c2fb_temp_2 = arg0->pParse
    local0 = c2fb_temp_2
    ' C unused-parameter annotation
    c2fb_temp_3 = CPtr(SqliteSrcList Ptr, arg1->pSrc)
    local2 = c2fb_temp_3
    c2fb_temp_4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local1 = c2fb_temp_4
    c2fb_temp_5 = CPtr(SqliteSrcItem Ptr, (@local2->a(0)))
    local3 = c2fb_temp_5
    While (-Cast(SQLITE_C_INT, ((local1 < local2->nSrc))))
        local4 = CPtr(SqliteTable Ptr, local3->pSTab)
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local4->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00004000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local3->fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))))))) Then
            local5 = CPtr(SqliteSelect Ptr, CPtr(SqliteSubquery Ptr, local3->u4.pSubq)->pSelect)
            sqlite3SubqueryColumnTypes(CPtr(Any Ptr, local0), CPtr(Any Ptr, local4), CPtr(Any Ptr, local5), Cast(SQLITE_C_INT, &H40ULL))
        End If
    c2fb_flow_1:
        c2fb_temp_6 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 + 1)))
        c2fb_temp_7 = local3
        local3 = (c2fb_temp_7 + 1)
    Wend
    c2fb_flow_0:
End Sub

Private Sub sqlite3SelectAddTypeInfo CDecl Alias "sqlite3SelectAddTypeInfo" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr)
    Dim local0 As SqliteWalker
    Dim c2fb_temp_0 As SqliteWalkerSelectCallback Ptr
    Dim c2fb_temp_1 As Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
    Dim c2fb_temp_2 As SqliteWalkerSelectCallback2 Ptr
    Dim c2fb_temp_3 As Sub CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr)
    Dim c2fb_temp_4 As SqliteWalkerExprCallback Ptr
    Dim c2fb_temp_5 As Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT
    Dim c2fb_temp_6 As SqliteParseContext Ptr Ptr
    Dim c2fb_temp_7 As SqliteParseContext Ptr

    ' C automatic storage declaration
    c2fb_temp_0 = @(local0.xSelectCallback)
    c2fb_temp_1 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, ProcPtr(sqlite3SelectWalkNoop))
    (*c2fb_temp_0) = Cast(SqliteWalkerSelectCallback, CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, ProcPtr(sqlite3SelectWalkNoop)))
    c2fb_temp_1 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, (*c2fb_temp_0))
    c2fb_temp_2 = @(local0.xSelectCallback2)
    c2fb_temp_3 = CPtr(Sub CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr), ProcPtr(selectAddSubqueryTypeInfo))
    (*c2fb_temp_2) = Cast(SqliteWalkerSelectCallback2, CPtr(Sub CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr), ProcPtr(selectAddSubqueryTypeInfo)))
    c2fb_temp_3 = CPtr(Sub CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr), (*c2fb_temp_2))
    c2fb_temp_4 = @(local0.xExprCallback)
    c2fb_temp_5 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, ProcPtr(sqlite3ExprWalkNoop))
    (*c2fb_temp_4) = Cast(SqliteWalkerExprCallback, CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, ProcPtr(sqlite3ExprWalkNoop)))
    c2fb_temp_5 = CPtr(Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT, (*c2fb_temp_4))
    c2fb_temp_6 = @(local0.pParse)
    c2fb_temp_7 = arg0
    (*c2fb_temp_6) = c2fb_temp_7
    sqlite3WalkSelect(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local0))), CPtr(Any Ptr, arg1))
End Sub

' c2fb skipped sqlite3SelectPrep: outside the supported subset
' c2fb skipped analyzeAggFuncArgs: outside the supported subset
' c2fb skipped optimizeAggregateUseOfIndexedExpr: outside the supported subset
' c2fb skipped aggregateIdxEprRefToColCallback: outside the supported subset
' c2fb skipped aggregateConvertIndexedExprRefToColumn: outside the supported subset
' c2fb skipped assignAggregateRegisters: outside the supported subset
' c2fb skipped resetAccumulator: outside the supported subset
' c2fb skipped finalizeAggFunctions: outside the supported subset
' c2fb skipped updateAccumulator: outside the supported subset
' c2fb skipped explainSimpleCount: outside the supported subset
Private Function havingToWhereExprCb CDecl Alias "havingToWhereExprCb" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim local0 As SqliteSelect Ptr
    Dim local1 As sqlite3 Ptr
    Dim local2 As SqliteExpr Ptr
    Dim local3 As SqliteExpr Ptr
    Dim local4 As SqliteExpr
    Dim c2fb_temp_0 As SqliteExpr Ptr
    Dim c2fb_temp_1 As SqliteExpr
    Dim c2fb_temp_2 As SqliteExpr Ptr
    Dim c2fb_temp_3 As SqliteExpr
    Dim c2fb_temp_4 As SqliteExpr Ptr
    Dim c2fb_temp_5 As Any Ptr Ptr
    Dim c2fb_temp_6 As SqliteExpr Ptr
    Dim c2fb_temp_7 As UShort Ptr
    Dim c2fb_temp_8 As UShort

    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) <> Cast(SQLITE_C_INT, 44ULL))))) Then
        local0 = arg0->u.pSelect
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((sqlite3ExprIsConstantOrGroupBy(CPtr(Any Ptr, arg0->pParse), CPtr(Any Ptr, arg1), CPtr(Any Ptr, CPtr(SqliteExprList Ptr, local0->pGroupBy))) AndAlso (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000001ULL) Or Cast(SQLITE_C_INT, &H20000000ULL)))))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H20000000ULL))))))) = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((arg1->pAggInfo = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            local1 = arg0->pParse->db
            local2 = CPtr(SqliteExpr Ptr, sqlite3ExprInt32(CPtr(Any Ptr, local1), Cast(SQLITE_C_INT, 1ULL)))
            If local2 Then
                local3 = CPtr(SqliteExpr Ptr, local0->pWhere)
                local4 = (*local2)
                c2fb_temp_0 = @((*local2))
                c2fb_temp_1 = (*arg1)
                (*c2fb_temp_0) = c2fb_temp_1
                c2fb_temp_2 = @((*arg1))
                c2fb_temp_3 = local4
                (*c2fb_temp_2) = c2fb_temp_3
                ' empty C statement
                c2fb_temp_4 = CPtr(SqliteExpr Ptr, sqlite3ExprAnd(CPtr(Any Ptr, arg0->pParse), CPtr(Any Ptr, local3), CPtr(Any Ptr, local2)))
                local2 = c2fb_temp_4
                c2fb_temp_5 = @(local0->pWhere)
                c2fb_temp_6 = local2
                (*c2fb_temp_5) = CPtr(Any Ptr, local2)
                c2fb_temp_6 = CPtr(SqliteExpr Ptr, (*c2fb_temp_5))
                c2fb_temp_7 = @(arg0->eCode)
                c2fb_temp_8 = Cast(UShort, Cast(SQLITE_C_INT, 1ULL))
                (*c2fb_temp_7) = c2fb_temp_8
            End If
        End If
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

' c2fb skipped havingToWhere: outside the supported subset
Private Function isSelfJoinView CDecl Alias "isSelfJoinView" (ByVal arg0 As SqliteSrcList Ptr, ByVal arg1 As SqliteSrcItem Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT) As SqliteSrcItem Ptr
    Dim local0 As SqliteSrcItem Ptr
    Dim local1 As SqliteSelect Ptr
    Dim c2fb_temp_0 As SqliteSelect Ptr
    Dim local2 As SqliteSelect Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SqliteSrcItem Ptr
    Dim c2fb_temp_3 As SqliteSelect Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(SqliteSelect Ptr, CPtr(SqliteSubquery Ptr, arg1->u4.pSubq)->pSelect)
    local1 = c2fb_temp_0
    ' C unused-parameter annotation
    If Cast(SQLITE_C_UINT, (local1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H1000000ULL)))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    While (-Cast(SQLITE_C_INT, ((arg2 < arg3))))
        ' C automatic storage declaration
        c2fb_temp_1 = arg2
        arg2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
        c2fb_temp_2 = CPtr(SqliteSrcItem Ptr, @(arg0->a(c2fb_temp_1)))
        local0 = c2fb_temp_2
        If (-Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local0->fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) = 0))) Then
            Goto c2fb_flow_1
        End If
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local0->fg.flags) Shr 6) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, ((local0->zName = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_1
        End If
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, ((CPtr(SqliteSchema Ptr, CPtr(SqliteTable Ptr, local0->pSTab)->pSchema) <> CPtr(SqliteSchema Ptr, CPtr(SqliteTable Ptr, arg1->pSTab)->pSchema))))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, ((sqlite3_stricmp(CPtr(Const ZString Ptr, local0->zName), CPtr(Const ZString Ptr, arg1->zName)) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_1
        End If
        c2fb_temp_3 = CPtr(SqliteSelect Ptr, CPtr(SqliteSubquery Ptr, local0->u4.pSubq)->pSelect)
        local2 = c2fb_temp_3
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((CPtr(SqliteSchema Ptr, CPtr(SqliteTable Ptr, local0->pSTab)->pSchema) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local1->selId <> local2->selId)))))))) Then
            Goto c2fb_flow_1
        End If
        If Cast(SQLITE_C_UINT, (local2->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H1000000ULL)))) Then
            Goto c2fb_flow_1
        End If
        Return local0
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

' c2fb skipped agginfoFree: outside the supported subset
' c2fb skipped countOfViewOptimization: outside the supported subset
Private Function sameSrcAlias CDecl Alias "sameSrcAlias" (ByVal arg0 As SqliteSrcItem Ptr, ByVal arg1 As SqliteSrcList Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local1 As SqliteSrcItem Ptr

    ' C automatic storage declaration
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((local0 < arg1->nSrc))))
        local1 = CPtr(SqliteSrcItem Ptr, @(arg1->a(local0)))
        If (-Cast(SQLITE_C_INT, ((local1 = arg0)))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((CPtr(SqliteTable Ptr, arg0->pSTab) = CPtr(SqliteTable Ptr, local1->pSTab))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = sqlite3_stricmp(CPtr(Const ZString Ptr, arg0->zAlias), CPtr(Const ZString Ptr, local1->zAlias)))))))))) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (CPtr(SqliteSelect Ptr, CPtr(SqliteSubquery Ptr, local1->u4.pSubq)->pSelect)->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000800ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso sameSrcAlias(arg0, CPtr(SqliteSrcList Ptr, CPtr(SqliteSelect Ptr, CPtr(SqliteSubquery Ptr, local1->u4.pSubq)->pSelect)->pSrc)))))) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
    c2fb_flow_1:
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    Wend
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

' c2fb skipped fromClauseTermCanBeCoroutine: outside the supported subset
' c2fb skipped existsToJoin: outside the supported subset
' c2fb skipped selectCheckOnClausesExpr: outside the supported subset
' c2fb skipped selectCheckOnClausesSelect: outside the supported subset
' c2fb skipped sqlite3SelectCheckOnClauses: outside the supported subset
Private Function sqlite3CopySortOrder CDecl Alias "sqlite3CopySortOrder" (ByVal arg0 As SqliteExprList Ptr, ByVal arg1 As SqliteExprList Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local1 As UByte
    Dim c2fb_temp_2 As UByte
    Dim c2fb_temp_3 As u8 Ptr
    Dim c2fb_temp_4 As UByte

    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((arg1 AndAlso (-Cast(SQLITE_C_INT, ((arg0->nExpr = arg1->nExpr)))))))) Then
        ' C automatic storage declaration
        c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local0 = c2fb_temp_0
        While (-Cast(SQLITE_C_INT, ((local0 < arg0->nExpr))))
            ' C automatic storage declaration
            c2fb_temp_2 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->a(local0).fg.sortFlags) And Cast(SQLITE_C_INT, &H01ULL))))
            local1 = c2fb_temp_2
            c2fb_temp_3 = @(arg0->a(local0).fg.sortFlags)
            c2fb_temp_4 = Cast(UByte, local1)
            (*c2fb_temp_3) = Cast(u8, Cast(UByte, local1))
            c2fb_temp_4 = Cast(UByte, (*c2fb_temp_3))
        c2fb_flow_1:
            c2fb_temp_1 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
        Wend
        c2fb_flow_0:
        Return Cast(SQLITE_C_INT, 1ULL)
    Else
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
End Function

Function sqlite3ColumnsFromExprList CDecl Alias "sqlite3ColumnsFromExprList" ( _
    ByVal parseArgument As Any Ptr, _
    ByVal listArgument As Any Ptr, _
    ByVal columnCountArgument As Short Ptr, _
    ByVal columnsArgument As Any Ptr Ptr _
) As SQLITE_C_INT
    Dim pParse As SqliteParseContext Ptr = _
        CPtr(SqliteParseContext Ptr, parseArgument)
    Dim pEList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, listArgument)
    Dim pnCol As Short Ptr = CPtr(Short Ptr, columnCountArgument)
    Dim paCol As SqliteColumn Ptr Ptr = _
        CPtr(SqliteColumn Ptr Ptr, columnsArgument)
    If pParse = 0 OrElse pParse->db = 0 OrElse pnCol = 0 OrElse paCol = 0 Then _
        Return SQLITE_MISUSE

    Dim db As sqlite3 Ptr = pParse->db
    Dim requestedColumns As SQLITE_C_INT = 0
    If pEList <> 0 Then requestedColumns = pEList->nExpr
    If requestedColumns < 0 Then Return SQLITE_CORRUPT
    If requestedColumns > 32767 Then Return SQLITE_TOOBIG

    Dim aCol As SqliteColumn Ptr = 0
    If requestedColumns > 0 Then
        aCol = CPtr(SqliteColumn Ptr, _
            sqlite3DbMallocZero(db, _
                Cast(sqlite3_uint64, SizeOf(SqliteColumn)) * _
                Cast(sqlite3_uint64, requestedColumns)))
        If aCol = 0 Then
            pnCol[0] = 0
            paCol[0] = 0
            Return SQLITE_NOMEM
        End If
    End If

    pnCol[0] = Cast(Short, requestedColumns)
    paCol[0] = aCol

    Dim nameHash As Hash
    sqlite3HashInit(@nameHash)
    Dim columnIndex As SQLITE_C_INT
    For columnIndex = 0 To requestedColumns - 1
        If pParse->nErr <> 0 Then Exit For

        Dim pX As SqliteExprListItem Ptr = @pEList->a(columnIndex)
        Dim pColumn As SqliteColumn Ptr = @aCol[columnIndex]
        Dim zName As ZString Ptr = 0
        Dim eEName As SQLITE_C_UINT = pX->fg.flags And SQLITE_EXPRLIST_EENAME_MASK

        If pX->zEName <> 0 AndAlso eEName = ENAME_NAME Then
            zName = CPtr(ZString Ptr, pX->zEName)
        Else
            Dim pColumnExpr As SqliteExpr Ptr = _
                sqlite3ExprSkipCollateAndLikely(CPtr(SqliteExpr Ptr, pX->pExpr))
            While pColumnExpr <> 0 AndAlso pColumnExpr->op = TK_DOT
                pColumnExpr = CPtr(SqliteExpr Ptr, pColumnExpr->pRight)
            Wend

            If pColumnExpr <> 0 AndAlso pColumnExpr->op = TK_COLUMN AndAlso _
               pColumnExpr->y.pTab <> 0 Then
                Dim pSourceTable As SqliteTable Ptr = _
                    CPtr(SqliteTable Ptr, pColumnExpr->y.pTab)
                Dim sourceColumnIndex As SQLITE_C_INT = pColumnExpr->iColumn
                If sourceColumnIndex < 0 Then sourceColumnIndex = pSourceTable->iPKey
                If sourceColumnIndex >= 0 AndAlso _
                   sourceColumnIndex < pSourceTable->nCol AndAlso _
                   pSourceTable->aCol <> 0 Then
                    zName = pSourceTable->aCol[sourceColumnIndex].zCnName
                ElseIf sourceColumnIndex < 0 Then
                    zName = StrPtr(!"rowid")
                End If
            ElseIf pColumnExpr <> 0 AndAlso pColumnExpr->op = TK_ID AndAlso _
                   (pColumnExpr->flags And EP_IntValue) = 0 Then
                zName = CPtr(ZString Ptr, pColumnExpr->u.zToken)
            ElseIf pX->zEName <> 0 Then
                zName = CPtr(ZString Ptr, pX->zEName)
            End If
        End If

        If zName <> 0 AndAlso sqlite3IsTrueOrFalse(zName) = 0 Then
            zName = CPtr(ZString Ptr, sqlite3DbStrDup(db, zName))
        Else
            zName = sqlite3MPrintf(db, StrPtr(!"column%d"), columnIndex + 1)
        End If

        Dim duplicateCount As u32 = 0
        While zName <> 0
            Dim pCollide As SqliteExprListItem Ptr = _
                CPtr(SqliteExprListItem Ptr, sqlite3HashFind(@nameHash, zName))
            If pCollide = 0 Then Exit While

            If (pCollide->fg.flags And SQLITE_EXPRLIST_BUSINGTERM) <> 0 Then
                pColumn->colFlags = pColumn->colFlags Or COLFLAG_NOEXPAND
            End If

            Dim nameLength As SQLITE_C_INT = sqlite3Strlen30(zName)
            If nameLength > 0 Then
                Dim suffixIndex As SQLITE_C_INT = nameLength - 1
                Dim zNameBytes As Const UByte Ptr = CPtr(Const UByte Ptr, zName)
                While suffixIndex > 0 AndAlso _
                      zNameBytes[suffixIndex] >= Asc("0") AndAlso _
                      zNameBytes[suffixIndex] <= Asc("9")
                    suffixIndex -= 1
                Wend
                If zNameBytes[suffixIndex] = Asc(":") Then nameLength = suffixIndex
            End If

            duplicateCount += 1
            zName = sqlite3MPrintf(db, StrPtr(!"%.*z:%u"), _
                nameLength, zName, duplicateCount)
            sqlite3ProgressCheck(pParse)
            If duplicateCount > 3 Then
                sqlite3_randomness(SizeOf(duplicateCount), @duplicateCount)
            End If
        Wend

        pColumn->zCnName = zName
        If zName <> 0 Then pColumn->hName = sqlite3StrIHash(zName)
        If (pX->fg.flags And SQLITE_EXPRLIST_BNOEXPAND) <> 0 Then
            pColumn->colFlags = pColumn->colFlags Or COLFLAG_NOEXPAND
        End If
#ifdef SQLITE_ENABLE_HIDDEN_COLUMNS
        sqlite3ColumnPropertiesFromName(0, pColumn)
#endif
        If zName <> 0 Then
            Dim pOldData As Any Ptr = sqlite3HashInsert(@nameHash, zName, pX)
            If pOldData = CPtr(Any Ptr, pX) Then sqlite3OomFault(db)
        End If
    Next

    sqlite3HashClear(@nameHash)
    If pParse->nErr <> 0 OrElse db->mallocFailed <> 0 Then
        Dim cleanupIndex As SQLITE_C_INT
        For cleanupIndex = 0 To columnIndex - 1
            sqlite3DbFree(db, CPtr(Any Ptr, aCol[cleanupIndex].zCnName))
        Next
        sqlite3DbFree(db, aCol)
        paCol[0] = 0
        pnCol[0] = 0
        If pParse->nErr <> 0 Then Return pParse->rc
        Return SQLITE_NOMEM
    End If
    Return SQLITE_OK
End Function

' c2fb skipped sqlite3Select: FreeBASIC body already exists

#ifdef SQLITE_DEBUG
Function sqlite3KeyInfoIsWriteable CDecl Alias "sqlite3KeyInfoIsWriteable" ( _
    ByVal keyInfoArgument As Any Ptr _
) As SQLITE_C_INT
    If keyInfoArgument = 0 Then Return 0

    ' KeyInfo.nRef is the first field in the C record and in its mapped prefix.
    Dim pReferenceCount As u32 Ptr = CPtr(u32 Ptr, keyInfoArgument)
    Return IIf(pReferenceCount[0] = 1, 1, 0)
End Function
#endif



/' ------------------------------------------------------------------------- '/
/' SELECT expansion, CTE resolution, and coroutine eligibility                 '/
/' ------------------------------------------------------------------------- '/

Private Function resolveFromTermToCte CDecl Alias "resolveFromTermToCte" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteWalker Ptr, ByVal arg2 As SqliteSrcItem Ptr) As SQLITE_C_INT
    Dim local0 As SqliteCte Ptr
    Dim local1 As SqliteWithRecord Ptr
    Dim c2fb_temp_0 As SqliteCte Ptr
    Dim local2 As sqlite3 Ptr
    Dim local3 As SqliteTable Ptr
    Dim local4 As SqliteExprList Ptr
    Dim local5 As SqliteSelect Ptr
    Dim local6 As SqliteSelect Ptr
    Dim local7 As SqliteSelect Ptr
    Dim local8 As SQLITE_C_INT
    Dim local9 As SqliteWithRecord Ptr
    Dim local10 As SQLITE_C_INT
    Dim local11 As SqliteCteUse Ptr
    Dim c2fb_temp_1 As SqliteTable Ptr
    Dim c2fb_temp_2 As SqliteCteUse Ptr
    Dim c2fb_temp_3 As SqliteCteUse Ptr
    Dim c2fb_temp_4 As SqliteCteUse Ptr Ptr
    Dim c2fb_temp_5 As SqliteCteUse Ptr
    Dim c2fb_temp_6 As u8 Ptr
    Dim c2fb_temp_7 As UByte
    Dim c2fb_temp_8 As SqliteTable Ptr Ptr
    Dim c2fb_temp_9 As SqliteTable Ptr
    Dim c2fb_temp_10 As u32 Ptr
    Dim c2fb_temp_11 As SQLITE_C_UINT
    Dim c2fb_temp_12 As ZString Ptr Ptr
    Dim c2fb_temp_13 As ZString Ptr
    Dim c2fb_temp_14 As Short Ptr
    Dim c2fb_temp_15 As Short
    Dim c2fb_temp_16 As Short Ptr
    Dim c2fb_temp_17 As Short
    Dim c2fb_temp_18 As u32 Ptr
    Dim c2fb_temp_19 As SQLITE_C_UINT
    Dim c2fb_temp_20 As SqliteSelect Ptr
    Dim c2fb_temp_21 As u32 Ptr
    Dim c2fb_temp_22 As SQLITE_C_UINT
    Dim c2fb_temp_23 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As SqliteCteUse Ptr Ptr
    Dim c2fb_temp_26 As SqliteCteUse Ptr
    Dim c2fb_temp_27 As SQLITE_C_INT Ptr
    Dim c2fb_temp_28 As SQLITE_C_INT
    Dim c2fb_temp_29 As SqliteSelect Ptr
    Dim c2fb_temp_30 As SQLITE_C_INT
    Dim local12 As SQLITE_C_INT
    Dim local13 As SqliteSrcList Ptr
    Dim c2fb_temp_31 As SQLITE_C_INT
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim local14 As SqliteSrcItem Ptr
    Dim c2fb_temp_33 As SqliteTable Ptr Ptr
    Dim c2fb_temp_34 As SqliteTable Ptr
    Dim c2fb_temp_35 As u32 Ptr
    Dim c2fb_temp_36 As SQLITE_C_UINT
    Dim c2fb_temp_37 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_38 As SQLITE_C_INT
    Dim c2fb_temp_39 As u32 Ptr
    Dim c2fb_temp_40 As SQLITE_C_UINT
    Dim c2fb_temp_41 As SQLITE_C_INT Ptr
    Dim c2fb_temp_42 As SQLITE_C_INT
    Dim c2fb_temp_43 As SQLITE_C_INT
    Dim c2fb_temp_44 As SQLITE_C_INT Ptr
    Dim c2fb_temp_45 As SQLITE_C_INT
    Dim c2fb_temp_46 As SqliteSelect Ptr
    Dim c2fb_temp_47 As SQLITE_C_INT Ptr
    Dim c2fb_temp_48 As SQLITE_C_INT
    Dim c2fb_temp_49 As SQLITE_C_INT Ptr
    Dim c2fb_temp_50 As SQLITE_C_INT
    Dim c2fb_temp_51 As Const ZString Ptr Ptr
    Dim c2fb_temp_52 As Const ZString Ptr
    Dim c2fb_temp_53 As SqliteWithRecord Ptr
    Dim c2fb_temp_54 As Any Ptr Ptr
    Dim c2fb_temp_55 As SqliteWithRecord Ptr
    Dim local15 As SQLITE_C_INT
    Dim c2fb_temp_56 As SqliteWith Ptr Ptr
    Dim c2fb_temp_57 As SqliteWithRecord Ptr
    Dim c2fb_temp_58 As SQLITE_C_INT
    Dim c2fb_temp_59 As SqliteWith Ptr Ptr
    Dim c2fb_temp_60 As SqliteWithRecord Ptr
    Dim c2fb_temp_61 As Any Ptr Ptr
    Dim c2fb_temp_62 As SqliteWithRecord Ptr
    Dim c2fb_temp_63 As Any Ptr Ptr
    Dim c2fb_temp_64 As SqliteWithRecord Ptr
    Dim c2fb_temp_65 As Any Ptr Ptr
    Dim c2fb_temp_66 As SqliteWithRecord Ptr
    Dim c2fb_temp_67 As SQLITE_C_INT Ptr
    Dim c2fb_temp_68 As SQLITE_C_INT
    Dim c2fb_temp_69 As SqliteSelect Ptr
    Dim c2fb_temp_70 As SqliteSelect Ptr
    Dim c2fb_temp_71 As SqliteExprList Ptr
    Dim c2fb_temp_72 As Any Ptr Ptr
    Dim c2fb_temp_73 As SqliteWithRecord Ptr
    Dim c2fb_temp_74 As SqliteExprList Ptr
    Dim c2fb_temp_75 As Const ZString Ptr Ptr
    Dim c2fb_temp_76 As Const ZString Ptr
    Dim c2fb_temp_77 As Const ZString Ptr Ptr
    Dim c2fb_temp_78 As Const ZString Ptr
    Dim c2fb_temp_79 As Const ZString Ptr Ptr
    Dim c2fb_temp_80 As Const ZString Ptr
    Dim c2fb_temp_81 As Any Ptr Ptr
    Dim c2fb_temp_82 As SqliteWithRecord Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((arg0->pWith = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If arg0->nErr Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg2->fg.flags) Shr 16) And Cast(SQLITE_C_UINT, &H1ULL))) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((arg2->u4.zDatabase <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg2->fg.flags) Shr 10) And Cast(SQLITE_C_UINT, &H1ULL))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = CPtr(SqliteCte Ptr, searchWith(arg0->pWith, arg2, CPtr(SqliteWithRecord Ptr Ptr, @(local1))))
    local0 = c2fb_temp_0
    If local0 Then
        local2 = arg0->db
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        local10 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))
        ' C automatic storage declaration
        If local0->zCteErr Then
            sqlite3ErrorMsg(CPtr(Any Ptr, arg0), local0->zCteErr, local0->zName)
            Return Cast(SQLITE_C_INT, 2ULL)
        End If
        If cannotBeFunction(arg0, arg2) Then
            Return Cast(SQLITE_C_INT, 2ULL)
        End If
        ' C unused-parameter annotation
        c2fb_temp_1 = CPtr(SqliteTable Ptr, CPtr(Any Ptr, sqlite3DbMallocZero(CPtr(Any Ptr, local2), Cast(SQLITE_SIZE_T, SizeOf(SqliteTable)))))
        local3 = c2fb_temp_1
        If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return Cast(SQLITE_C_INT, 2ULL)
        End If
        c2fb_temp_2 = local0->pUse
        local11 = c2fb_temp_2
        If (-Cast(SQLITE_C_INT, ((local11 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_4 = @(local0->pUse)
            c2fb_temp_3 = CPtr(SqliteCteUse Ptr, CPtr(Any Ptr, sqlite3DbMallocZero(CPtr(Any Ptr, local2), Cast(SQLITE_SIZE_T, SizeOf(SqliteCteUse)))))
            local11 = c2fb_temp_3
            c2fb_temp_5 = c2fb_temp_3
            (*c2fb_temp_4) = c2fb_temp_5
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local11 = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((CPtr(Any Ptr, sqlite3ParserAddCleanup(CPtr(Any Ptr, arg0), ProcPtr(sqlite3DbFree), CPtr(Any Ptr, local11))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                sqlite3DbFree(CPtr(Any Ptr, local2), CPtr(Any Ptr, local3))
                Return Cast(SQLITE_C_INT, 2ULL)
            End If
            c2fb_temp_6 = @(local11->eM10d)
            c2fb_temp_7 = Cast(UByte, local0->eM10d)
            (*c2fb_temp_6) = Cast(u8, c2fb_temp_7)
            c2fb_temp_7 = Cast(UByte, (*c2fb_temp_6))
        End If
        c2fb_temp_8 = @(arg2->pSTab)
        c2fb_temp_9 = local3
        (*c2fb_temp_8) = c2fb_temp_9
        c2fb_temp_10 = @(local3->nTabRef)
        c2fb_temp_11 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))
        (*c2fb_temp_10) = Cast(u32, c2fb_temp_11)
        c2fb_temp_11 = Cast(SQLITE_C_UINT, (*c2fb_temp_10))
        c2fb_temp_12 = @(local3->zName)
        c2fb_temp_13 = CPtr(ZString Ptr, sqlite3DbStrDup(CPtr(Any Ptr, local2), CPtr(Const ZString Ptr, local0->zName)))
        (*c2fb_temp_12) = c2fb_temp_13
        c2fb_temp_14 = @(local3->iPKey)
        c2fb_temp_15 = Cast(Short, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
        (*c2fb_temp_14) = c2fb_temp_15
        c2fb_temp_16 = @(local3->nRowLogEst)
        c2fb_temp_17 = Cast(Short, Cast(SQLITE_C_INT, 200ULL))
        (*c2fb_temp_16) = c2fb_temp_17
        ' C unused-parameter annotation
        c2fb_temp_18 = @(local3->tabFlags)
        c2fb_temp_19 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_18)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00004000ULL) Or Cast(SQLITE_C_INT, &H00000200ULL)))))))
        (*c2fb_temp_18) = Cast(u32, c2fb_temp_19)
        c2fb_temp_19 = Cast(SQLITE_C_UINT, (*c2fb_temp_18))
        sqlite3SrcItemAttachSubquery(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg2), CPtr(Any Ptr, local0->pSelect), Cast(SQLITE_C_INT, 1ULL))
        If local2->mallocFailed Then
            Return Cast(SQLITE_C_INT, 2ULL)
        End If
        ' C unused-parameter annotation
        c2fb_temp_20 = arg2->u4.pSubq->pSelect
        local5 = c2fb_temp_20
        ' C unused-parameter annotation
        c2fb_temp_21 = @(local5->selFlags)
        c2fb_temp_22 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_21)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H4000000ULL)))))
        (*c2fb_temp_21) = Cast(u32, c2fb_temp_22)
        c2fb_temp_22 = Cast(SQLITE_C_UINT, (*c2fb_temp_21))
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg2->fg.flags) Shr 1) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"no such index: \034%s\034"), arg2->u1.zIndexedBy)
            Return Cast(SQLITE_C_INT, 2ULL)
        End If
        ' C unused-parameter annotation
        c2fb_temp_23 = @(arg2->fg.flags)
        c2fb_temp_24 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
        c2fb_temp_24 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_24) And Cast(SQLITE_C_UINT, &H1ULL)))
        (*c2fb_temp_23) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_23)) And Not(Cast(SQLITE_C_UINT, &H200ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_24) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 9)))
        c2fb_temp_24 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_24) And Cast(SQLITE_C_UINT, &H1ULL)))
        c2fb_temp_25 = @(arg2->u2.pCteUse)
        c2fb_temp_26 = local11
        (*c2fb_temp_25) = c2fb_temp_26
        c2fb_temp_27 = @(local11->nUse)
        c2fb_temp_28 = (*c2fb_temp_27)
        (*c2fb_temp_27) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_28 + 1)))
        c2fb_temp_29 = local5
        local7 = c2fb_temp_29
        c2fb_temp_30 = Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local5->op) = Cast(SQLITE_C_INT, 136ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local5->op) = Cast(SQLITE_C_INT, 135ULL)))))))))))
        local8 = c2fb_temp_30
        While (-Cast(SQLITE_C_INT, ((local8 AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local7->op) = Cast(SQLITE_C_INT, local5->op)))))))))
            ' C automatic storage declaration
            local13 = local7->pSrc
            ' C unused-parameter annotation
            c2fb_temp_31 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local12 = c2fb_temp_31
            While (-Cast(SQLITE_C_INT, ((local12 < local13->nSrc))))
                local14 = CPtr(SqliteSrcItem Ptr, @(local13->a(local12)))
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local14->zName <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local14->fg.flags) Shr 17) And Cast(SQLITE_C_UINT, &H1ULL))) = 0))))))) AndAlso ((-Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local14->fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) = 0)))))))) AndAlso ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local14->fg.flags) Shr 16) And Cast(SQLITE_C_UINT, &H1ULL))) OrElse (-Cast(SQLITE_C_INT, ((local14->u4.zDatabase = Cast(SQLITE_C_INT, &O0ULL)))))))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = sqlite3StrICmp(CPtr(Const ZString Ptr, local14->zName), CPtr(Const ZString Ptr, local0->zName)))))))))) Then
                    c2fb_temp_33 = @(local14->pSTab)
                    c2fb_temp_34 = local3
                    (*c2fb_temp_33) = c2fb_temp_34
                    c2fb_temp_35 = @(local3->nTabRef)
                    c2fb_temp_36 = Cast(SQLITE_C_UINT, (*c2fb_temp_35))
                    (*c2fb_temp_35) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_36 + 1)))
                    c2fb_temp_37 = @(local14->fg.flags)
                    c2fb_temp_38 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                    c2fb_temp_38 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_38) And Cast(SQLITE_C_UINT, &H1ULL)))
                    (*c2fb_temp_37) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_37)) And Not(Cast(SQLITE_C_UINT, &H80ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_38) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 7)))
                    c2fb_temp_38 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_38) And Cast(SQLITE_C_UINT, &H1ULL)))
                    If Cast(SQLITE_C_UINT, (local7->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0002000ULL)))) Then
                        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"multiple references to recursive table: %s"), local0->zName)
                        Return Cast(SQLITE_C_INT, 2ULL)
                    End If
                    c2fb_temp_39 = @(local7->selFlags)
                    c2fb_temp_40 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_39)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0002000ULL)))))
                    (*c2fb_temp_39) = Cast(u32, c2fb_temp_40)
                    c2fb_temp_40 = Cast(SQLITE_C_UINT, (*c2fb_temp_39))
                    If (-Cast(SQLITE_C_INT, ((local10 < Cast(SQLITE_C_INT, &O0ULL))))) Then
                        c2fb_temp_41 = @(arg0->nTab)
                        c2fb_temp_42 = (*c2fb_temp_41)
                        (*c2fb_temp_41) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_42 + 1)))
                        c2fb_temp_43 = Cast(SQLITE_C_INT, c2fb_temp_42)
                        local10 = c2fb_temp_43
                    End If
                    c2fb_temp_44 = @(local14->iCursor)
                    c2fb_temp_45 = Cast(SQLITE_C_INT, local10)
                    (*c2fb_temp_44) = c2fb_temp_45
                End If
            c2fb_flow_3:
                c2fb_temp_32 = local12
                local12 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_32 + 1)))
            Wend
            c2fb_flow_2:
            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local7->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0002000ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                Goto c2fb_flow_0
            End If
            c2fb_temp_46 = local7->pPrior
            local7 = c2fb_temp_46
        c2fb_flow_1:
        Wend
        c2fb_flow_0:
        If (-Cast(SQLITE_C_INT, ((arg0->nTab >= local2->aLimit(Cast(SQLITE_C_INT, 3ULL)))))) Then
            c2fb_temp_47 = @(arg0->nNestSel)
            c2fb_temp_48 = Cast(SQLITE_C_INT, arg0->nTab)
            (*c2fb_temp_47) = c2fb_temp_48
        End If
        c2fb_temp_49 = @(arg0->nNestSel)
        c2fb_temp_50 = (*c2fb_temp_49)
        (*c2fb_temp_49) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_50 + 1)))
        If checkSubqueryNestingDepth(arg0) Then
            Return Cast(SQLITE_C_INT, 2ULL)
        End If
        c2fb_temp_51 = @(local0->zCteErr)
        c2fb_temp_52 = StrPtr(!"circular reference: %s")
        (*c2fb_temp_51) = c2fb_temp_52
        c2fb_temp_53 = arg0->pWith
        local9 = c2fb_temp_53
        c2fb_temp_54 = @(arg0->pWith)
        c2fb_temp_55 = local1
        (*c2fb_temp_54) = CPtr(Any Ptr, c2fb_temp_55)
        c2fb_temp_55 = CPtr(SqliteWithRecord Ptr, (*c2fb_temp_54))
        If Cast(SQLITE_C_UINT, (local5->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0002000ULL)))) Then
            ' C automatic storage declaration
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_56 = @(local7->pWith)
            c2fb_temp_57 = local5->pWith
            (*c2fb_temp_56) = CPtr(SqliteWith Ptr, c2fb_temp_57)
            c2fb_temp_57 = CPtr(SqliteWithRecord Ptr, (*c2fb_temp_56))
            c2fb_temp_58 = Cast(SQLITE_C_INT, sqlite3WalkSelect(CPtr(Any Ptr, arg1), CPtr(Any Ptr, local7)))
            local15 = c2fb_temp_58
            c2fb_temp_59 = @(local7->pWith)
            c2fb_temp_60 = CPtr(SqliteWithRecord Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
            (*c2fb_temp_59) = CPtr(SqliteWith Ptr, c2fb_temp_60)
            c2fb_temp_60 = CPtr(SqliteWithRecord Ptr, (*c2fb_temp_59))
            If local15 Then
                c2fb_temp_61 = @(arg0->pWith)
                c2fb_temp_62 = local9
                (*c2fb_temp_61) = CPtr(Any Ptr, c2fb_temp_62)
                c2fb_temp_62 = CPtr(SqliteWithRecord Ptr, (*c2fb_temp_61))
                Return Cast(SQLITE_C_INT, 2ULL)
            End If
        Else
            If sqlite3WalkSelect(CPtr(Any Ptr, arg1), CPtr(Any Ptr, local5)) Then
                c2fb_temp_63 = @(arg0->pWith)
                c2fb_temp_64 = local9
                (*c2fb_temp_63) = CPtr(Any Ptr, c2fb_temp_64)
                c2fb_temp_64 = CPtr(SqliteWithRecord Ptr, (*c2fb_temp_63))
                Return Cast(SQLITE_C_INT, 2ULL)
            End If
        End If
        c2fb_temp_65 = @(arg0->pWith)
        c2fb_temp_66 = local1
        (*c2fb_temp_65) = CPtr(Any Ptr, c2fb_temp_66)
        c2fb_temp_66 = CPtr(SqliteWithRecord Ptr, (*c2fb_temp_65))
        c2fb_temp_67 = @(arg0->nNestSel)
        c2fb_temp_68 = (*c2fb_temp_67)
        (*c2fb_temp_67) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_68 - 1)))
        ' C unused-parameter annotation
        c2fb_temp_69 = local5
        local6 = c2fb_temp_69
        While local6->pPrior
            ' empty C statement
        c2fb_flow_5:
            c2fb_temp_70 = local6->pPrior
            local6 = c2fb_temp_70
        Wend
        c2fb_flow_4:
        c2fb_temp_71 = local6->pEList
        local4 = c2fb_temp_71
        If local0->pCols Then
            If (-Cast(SQLITE_C_INT, ((local4 AndAlso (-Cast(SQLITE_C_INT, ((local4->nExpr <> local0->pCols->nExpr)))))))) Then
                sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"table %s has %d values for %d columns"), local0->zName, local4->nExpr, local0->pCols->nExpr)
                c2fb_temp_72 = @(arg0->pWith)
                c2fb_temp_73 = local9
                (*c2fb_temp_72) = CPtr(Any Ptr, c2fb_temp_73)
                c2fb_temp_73 = CPtr(SqliteWithRecord Ptr, (*c2fb_temp_72))
                Return Cast(SQLITE_C_INT, 2ULL)
            End If
            c2fb_temp_74 = local0->pCols
            local4 = c2fb_temp_74
        End If
        sqlite3ColumnsFromExprList(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local4), CPtr(Short Ptr, @(local3->nCol)), CPtr(Any Ptr Ptr, CPtr(SqliteColumn Ptr Ptr, @(local3->aCol))))
        If local8 Then
            If Cast(SQLITE_C_UINT, (local5->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0002000ULL)))) Then
                c2fb_temp_75 = @(local0->zCteErr)
                c2fb_temp_76 = StrPtr(!"multiple recursive references: %s")
                (*c2fb_temp_75) = c2fb_temp_76
            Else
                c2fb_temp_77 = @(local0->zCteErr)
                c2fb_temp_78 = StrPtr(!"recursive reference in a subquery: %s")
                (*c2fb_temp_77) = c2fb_temp_78
            End If
            sqlite3WalkSelect(CPtr(Any Ptr, arg1), CPtr(Any Ptr, local5))
        End If
        c2fb_temp_79 = @(local0->zCteErr)
        c2fb_temp_80 = CPtr(Const ZString Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_79) = c2fb_temp_80
        c2fb_temp_81 = @(arg0->pWith)
        c2fb_temp_82 = local9
        (*c2fb_temp_81) = CPtr(Any Ptr, c2fb_temp_82)
        c2fb_temp_82 = CPtr(SqliteWithRecord Ptr, (*c2fb_temp_81))
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function selectExpander CDecl Alias "selectExpander" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteSelect Ptr) As SQLITE_C_INT
    Dim local0 As SqliteParseContext Ptr
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As SqliteSrcList Ptr
    Dim local6 As SqliteExprList Ptr
    Dim local7 As SqliteSrcItem Ptr
    Dim local8 As sqlite3 Ptr
    Dim local9 As SqliteExpr Ptr
    Dim local10 As SqliteExpr Ptr
    Dim local11 As SqliteExpr Ptr
    Dim local12 As UShort
    Dim local13 As SQLITE_C_UINT
    Dim c2fb_temp_0 As u32 Ptr
    Dim c2fb_temp_1 As SQLITE_C_UINT
    Dim c2fb_temp_2 As SQLITE_C_INT Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As u32 Ptr
    Dim c2fb_temp_6 As SQLITE_C_UINT
    Dim c2fb_temp_7 As SqliteSrcList Ptr
    Dim c2fb_temp_8 As SqliteExprList Ptr
    Dim c2fb_temp_9 As SqliteWith Ptr Ptr
    Dim c2fb_temp_10 As SqliteWithRecord Ptr
    Dim c2fb_temp_11 As SQLITE_C_INT Ptr
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SqliteWithRecord Ptr
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SqliteSrcItem Ptr
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SqliteSrcItem Ptr
    Dim local14 As SqliteTable Ptr
    Dim local15 As SqliteSelect Ptr
    Dim c2fb_temp_18 As SqliteSelect Ptr
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim c2fb_temp_20 As SqliteTable Ptr
    Dim c2fb_temp_21 As SqliteTable Ptr
    Dim c2fb_temp_22 As SqliteTable Ptr Ptr
    Dim c2fb_temp_23 As SqliteTable Ptr
    Dim c2fb_temp_24 As SqliteTable Ptr Ptr
    Dim c2fb_temp_25 As SqliteTable Ptr
    Dim c2fb_temp_26 As u32 Ptr
    Dim c2fb_temp_27 As SQLITE_C_UINT
    Dim local16 As Short
    Dim local17 As UByte
    Dim c2fb_temp_28 As Short
    Dim c2fb_temp_29 As Short Ptr
    Dim c2fb_temp_30 As Short
    Dim c2fb_temp_31 As UShort Ptr
    Dim c2fb_temp_32 As UShort
    Dim c2fb_temp_33 As UShort Ptr
    Dim c2fb_temp_34 As UShort
    Dim c2fb_temp_35 As Short Ptr
    Dim c2fb_temp_36 As Short
    Dim c2fb_temp_37 As SQLITE_C_INT
    Dim c2fb_temp_38 As SQLITE_C_INT
    Dim c2fb_temp_39 As SqliteExpr Ptr
    Dim c2fb_temp_40 As SQLITE_C_UINT
    Dim local18 As SqliteExprListItem Ptr
    Dim local19 As SqliteExprList Ptr
    Dim local20 As SQLITE_C_INT
    Dim local21 As SQLITE_C_INT
    Dim c2fb_temp_41 As SQLITE_C_INT
    Dim c2fb_temp_42 As SQLITE_C_INT
    Dim c2fb_temp_43 As SqliteExpr Ptr
    Dim c2fb_temp_44 As SQLITE_C_UINT
    Dim c2fb_temp_45 As SqliteExpr Ptr
    Dim c2fb_temp_46 As SqliteExprList Ptr
    Dim c2fb_temp_47 As UByte Ptr Ptr
    Dim c2fb_temp_48 As ZString Ptr
    Dim c2fb_temp_49 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_50 As SQLITE_C_INT
    Dim c2fb_temp_51 As UByte Ptr Ptr
    Dim c2fb_temp_52 As ZString Ptr
    Dim c2fb_temp_53 As Any Ptr Ptr
    Dim c2fb_temp_54 As SqliteExpr Ptr
    Dim local22 As SQLITE_C_INT
    Dim local23 As ZString Ptr
    Dim local24 As SQLITE_C_INT
    Dim c2fb_temp_55 As ZString Ptr
    Dim c2fb_temp_56 As SQLITE_C_INT
    Dim c2fb_temp_57 As SQLITE_C_INT
    Dim c2fb_temp_58 As SQLITE_C_INT
    Dim c2fb_temp_59 As SqliteSrcItem Ptr
    Dim c2fb_temp_60 As SQLITE_C_INT
    Dim c2fb_temp_61 As SqliteSrcItem Ptr
    Dim local25 As SQLITE_C_INT
    Dim local26 As SqliteTable Ptr
    Dim local27 As SqliteExprList Ptr
    Dim local28 As ZString Ptr
    Dim local29 As Const ZString Ptr
    Dim local30 As SQLITE_C_INT
    Dim local31 As SqliteIdList Ptr
    Dim c2fb_temp_62 As ZString Ptr
    Dim c2fb_temp_63 As ZString Ptr
    Dim c2fb_temp_64 As SqliteExprList Ptr
    Dim c2fb_temp_65 As SqliteExprList Ptr
    Dim c2fb_temp_66 As SQLITE_C_INT
    Dim c2fb_temp_67 As Const ZString Ptr
    Dim local32 As SQLITE_C_INT
    Dim c2fb_temp_68 As SqliteIdList Ptr
    Dim c2fb_temp_69 As SQLITE_C_INT
    Dim c2fb_temp_70 As SQLITE_C_INT
    Dim local33 As Const ZString Ptr
    Dim c2fb_temp_71 As SqliteExpr Ptr
    Dim c2fb_temp_72 As SqliteExprList Ptr
    Dim local34 As SqliteExprListItem Ptr
    Dim c2fb_temp_73 As UByte Ptr Ptr
    Dim c2fb_temp_74 As ZString Ptr
    Dim c2fb_temp_75 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_76 As SQLITE_C_INT
    Dim c2fb_temp_77 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_78 As SQLITE_C_INT
    Dim c2fb_temp_79 As SqliteIdList Ptr
    Dim c2fb_temp_80 As SQLITE_C_INT
    Dim c2fb_temp_81 As SQLITE_C_INT
    Dim c2fb_temp_82 As SQLITE_C_INT
    Dim c2fb_temp_83 As SQLITE_C_INT
    Dim local35 As Const ZString Ptr
    Dim local36 As SqliteExprListItem Ptr
    Dim c2fb_temp_84 As Const ZString Ptr
    Dim c2fb_temp_85 As Const ZString Ptr
    Dim c2fb_temp_86 As SQLITE_C_INT
    Dim c2fb_temp_87 As SqliteExpr Ptr
    Dim local37 As SqliteExpr Ptr
    Dim c2fb_temp_88 As SqliteExpr Ptr
    Dim c2fb_temp_89 As SqliteExpr Ptr
    Dim c2fb_temp_90 As SqliteExpr Ptr
    Dim c2fb_temp_91 As SqliteExpr Ptr
    Dim c2fb_temp_92 As SqliteExpr Ptr
    Dim c2fb_temp_93 As SqliteExprList Ptr
    Dim c2fb_temp_94 As SqliteExprListItem Ptr
    Dim c2fb_temp_95 As UByte Ptr Ptr
    Dim c2fb_temp_96 As ZString Ptr
    Dim c2fb_temp_97 As UByte Ptr Ptr
    Dim c2fb_temp_98 As ZString Ptr
    Dim c2fb_temp_99 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_100 As SQLITE_C_INT
    Dim c2fb_temp_101 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_102 As SQLITE_C_INT
    Dim c2fb_temp_103 As UByte Ptr Ptr
    Dim c2fb_temp_104 As ZString Ptr
    Dim c2fb_temp_105 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_106 As SQLITE_C_INT
    Dim c2fb_temp_107 As UByte Ptr Ptr
    Dim c2fb_temp_108 As ZString Ptr
    Dim c2fb_temp_109 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_110 As SQLITE_C_INT
    Dim c2fb_temp_111 As Any Ptr Ptr
    Dim c2fb_temp_112 As SqliteExprList Ptr
    Dim c2fb_temp_113 As u32 Ptr
    Dim c2fb_temp_114 As SQLITE_C_UINT

    local0 = arg0->pParse
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local8 = local0->db
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local12 = arg1->selFlags
    local13 = Cast(SQLITE_C_INT, &O0ULL)
    c2fb_temp_0 = @(arg1->selFlags)
    c2fb_temp_1 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_0)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000040ULL)))))
    (*c2fb_temp_0) = Cast(u32, c2fb_temp_1)
    c2fb_temp_1 = Cast(SQLITE_C_UINT, (*c2fb_temp_0))
    If local8->mallocFailed Then
        Return Cast(SQLITE_C_INT, 2ULL)
    End If
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local12) And Cast(SQLITE_C_INT, &H0000040ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    If arg0->eCode Then
        c2fb_temp_5 = @(arg1->selId)
        c2fb_temp_2 = @(local0->nSelect)
        c2fb_temp_3 = (*c2fb_temp_2)
        (*c2fb_temp_2) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_3 + 1)))
        c2fb_temp_4 = (*c2fb_temp_2)
        c2fb_temp_6 = Cast(SQLITE_C_UINT, c2fb_temp_4)
        (*c2fb_temp_5) = Cast(u32, c2fb_temp_6)
        c2fb_temp_6 = Cast(SQLITE_C_UINT, (*c2fb_temp_5))
    End If
    c2fb_temp_7 = arg1->pSrc
    local5 = c2fb_temp_7
    c2fb_temp_8 = arg1->pEList
    local6 = c2fb_temp_8
    If (-Cast(SQLITE_C_INT, ((local0->pWith AndAlso (Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0200000ULL))))))))) Then
        If (-Cast(SQLITE_C_INT, ((arg1->pWith = Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_9 = @(arg1->pWith)
            c2fb_temp_10 = CPtr(SqliteWithRecord Ptr, CPtr(Any Ptr, sqlite3DbMallocZero(CPtr(Any Ptr, local8), (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, (SizeOf(SqliteWithRecord) - SizeOf(SqliteCte)))) + Cast(sqlite3_uint64, (Cast(sqlite3_uint64, (Cast(SQLITE_C_INT, 1ULL))) * Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteCte)))))))))))
            (*c2fb_temp_9) = CPtr(SqliteWith Ptr, c2fb_temp_10)
            c2fb_temp_10 = CPtr(SqliteWithRecord Ptr, (*c2fb_temp_9))
            If (-Cast(SQLITE_C_INT, ((arg1->pWith = Cast(SQLITE_C_INT, &O0ULL))))) Then
                Return Cast(SQLITE_C_INT, 2ULL)
            End If
        End If
        c2fb_temp_11 = @(arg1->pWith->bView)
        c2fb_temp_12 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
        (*c2fb_temp_11) = c2fb_temp_12
    End If
    c2fb_temp_13 = CPtr(SqliteWithRecord Ptr, sqlite3WithPush(CPtr(Any Ptr, local0), CPtr(Any Ptr, arg1->pWith), Cast(SQLITE_C_INT, &O0ULL)))
    sqlite3SrcListAssignCursors(CPtr(Any Ptr, local0), CPtr(Any Ptr, local5))
    c2fb_temp_14 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local1 = c2fb_temp_14
    c2fb_temp_15 = CPtr(SqliteSrcItem Ptr, (@local5->a(0)))
    local7 = c2fb_temp_15
    While (-Cast(SQLITE_C_INT, ((local1 < local5->nSrc))))
        ' C automatic storage declaration
        ' C unused-parameter annotation
        If local7->pSTab Then
            Goto c2fb_flow_1
        End If
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, ((local7->zName = Cast(SQLITE_C_INT, &O0ULL))))) Then
            ' C automatic storage declaration
            ' C unused-parameter annotation
            c2fb_temp_18 = local7->u4.pSubq->pSelect
            local15 = c2fb_temp_18
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            If sqlite3WalkSelect(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local15)) Then
                Return Cast(SQLITE_C_INT, 2ULL)
            End If
            If sqlite3ExpandSubquery(CPtr(Any Ptr, local0), CPtr(Any Ptr, local7)) Then
                Return Cast(SQLITE_C_INT, 2ULL)
            End If
        Else
            c2fb_temp_19 = Cast(SQLITE_C_INT, resolveFromTermToCte(local0, arg0, local7))
            local4 = c2fb_temp_19
            If (-Cast(SQLITE_C_INT, (((c2fb_temp_19) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                If (-Cast(SQLITE_C_INT, ((local4 > Cast(SQLITE_C_INT, 1ULL))))) Then
                    Return Cast(SQLITE_C_INT, 2ULL)
                End If
                c2fb_temp_20 = local7->pSTab
                local14 = c2fb_temp_20
                ' C unused-parameter annotation
            Else
                ' C unused-parameter annotation
                c2fb_temp_22 = @(local7->pSTab)
                c2fb_temp_21 = CPtr(SqliteTable Ptr, sqlite3LocateTableItem(CPtr(Any Ptr, local0), Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, local7)))
                local14 = c2fb_temp_21
                c2fb_temp_23 = c2fb_temp_21
                (*c2fb_temp_22) = c2fb_temp_23
                If (-Cast(SQLITE_C_INT, ((local14 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    Return Cast(SQLITE_C_INT, 2ULL)
                End If
                If (-Cast(SQLITE_C_INT, ((local14->nTabRef >= Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &HffffULL)))))) Then
                    sqlite3ErrorMsg(CPtr(Any Ptr, local0), StrPtr(!"too many references to \034%s\034: max 65535"), local14->zName)
                    c2fb_temp_24 = @(local7->pSTab)
                    c2fb_temp_25 = CPtr(SqliteTable Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                    (*c2fb_temp_24) = c2fb_temp_25
                    Return Cast(SQLITE_C_INT, 2ULL)
                End If
                c2fb_temp_26 = @(local14->nTabRef)
                c2fb_temp_27 = Cast(SQLITE_C_UINT, (*c2fb_temp_26))
                (*c2fb_temp_26) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_27 + 1)))
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local14)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))) = 0))) AndAlso cannotBeFunction(local0, local7))))) Then
                    Return Cast(SQLITE_C_INT, 2ULL)
                End If
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local14)->eTabType) = Cast(SQLITE_C_INT, &O0ULL)))))) = 0))) Then
                    ' C automatic storage declaration
                    local17 = arg0->eCode
                    If sqlite3ViewGetColumnNames(CPtr(Any Ptr, local0), CPtr(Any Ptr, local14)) Then
                        Return Cast(SQLITE_C_INT, 2ULL)
                    End If
                    ' C unused-parameter annotation
                    If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local14)->eTabType) = Cast(SQLITE_C_INT, 2ULL)))))) Then
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local8->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_UINT, &H80000000ULL))))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, ((local14->pSchema <> local8->aDb(Cast(SQLITE_C_INT, 1ULL)).pSchema)))))))) Then
                            sqlite3ErrorMsg(CPtr(Any Ptr, local0), StrPtr(!"access to view \034%s\034 prohibited"), local14->zName)
                        End If
                        sqlite3SrcItemAttachSubquery(CPtr(Any Ptr, local0), CPtr(Any Ptr, local7), CPtr(Any Ptr, local14->u.view.pSelect), Cast(SQLITE_C_INT, 1ULL))
                    Else
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local14)->eTabType) = Cast(SQLITE_C_INT, 1ULL))))))) AndAlso ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local7->fg.flags) Shr 8) And Cast(SQLITE_C_UINT, &H1ULL))) OrElse (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->prepFlags) And Cast(SQLITE_C_INT, &H20ULL))))))))))))) AndAlso ((-Cast(SQLITE_C_INT, ((local14->u.vtab.p <> Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local14->u.vtab.p->eVtabRisk) > ((-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local8->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &H00000080ULL))))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))))))))))))))) Then
                            sqlite3ErrorMsg(CPtr(Any Ptr, local0), StrPtr(!"unsafe use of virtual table \034%s\034"), local14->zName)
                        End If
                    End If
                    ' C unused-parameter annotation
                    c2fb_temp_28 = Cast(Short, local14->nCol)
                    local16 = c2fb_temp_28
                    c2fb_temp_29 = @(local14->nCol)
                    c2fb_temp_30 = Cast(Short, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
                    (*c2fb_temp_29) = c2fb_temp_30
                    c2fb_temp_31 = @(arg0->eCode)
                    c2fb_temp_32 = Cast(UShort, Cast(SQLITE_C_INT, 1ULL))
                    (*c2fb_temp_31) = c2fb_temp_32
                    If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local7->fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                        sqlite3WalkSelect(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local7->u4.pSubq->pSelect))
                    End If
                    c2fb_temp_33 = @(arg0->eCode)
                    c2fb_temp_34 = Cast(UShort, local17)
                    (*c2fb_temp_33) = c2fb_temp_34
                    c2fb_temp_35 = @(local14->nCol)
                    c2fb_temp_36 = Cast(Short, local16)
                    (*c2fb_temp_35) = c2fb_temp_36
                End If
            End If
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local7->fg.flags) Shr 1) And Cast(SQLITE_C_UINT, &H1ULL))) AndAlso sqlite3IndexedByLookup(CPtr(Any Ptr, local0), CPtr(Any Ptr, local7)))))) Then
            Return Cast(SQLITE_C_INT, 2ULL)
        End If
    c2fb_flow_1:
        c2fb_temp_16 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_16 + 1)))
        c2fb_temp_17 = local7
        local7 = (c2fb_temp_17 + 1)
    Wend
    c2fb_flow_0:
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((local0->nErr OrElse sqlite3ProcessJoin(local0, arg1))))) Then
        Return Cast(SQLITE_C_INT, 2ULL)
    End If
    c2fb_temp_37 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local3 = c2fb_temp_37
    While (-Cast(SQLITE_C_INT, ((local3 < local6->nExpr))))
        c2fb_temp_39 = local6->a(local3).pExpr
        local9 = c2fb_temp_39
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local9->op) = Cast(SQLITE_C_INT, 180ULL))))) Then
            Goto c2fb_flow_2
        End If
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local9->op) = Cast(SQLITE_C_INT, 142ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local9->pRight->op) = Cast(SQLITE_C_INT, 180ULL))))))))) Then
            Goto c2fb_flow_2
        End If
        c2fb_temp_40 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (local13 Or local9->flags)))
        local13 = c2fb_temp_40
    c2fb_flow_3:
        c2fb_temp_38 = local3
        local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_38 + 1)))
    Wend
    c2fb_flow_2:
    If (-Cast(SQLITE_C_INT, ((local3 < local6->nExpr)))) Then
        local18 = CPtr(SqliteExprListItem Ptr, (@local6->a(0)))
        local19 = Cast(SQLITE_C_INT, &O0ULL)
        local20 = local0->db->flags
        local21 = (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (local20 And Cast(SQLITE_C_INT, &H00000004ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (local20 And Cast(SQLITE_C_INT, &H00000040ULL)))) = Cast(SQLITE_C_INT, &O0ULL)))))))))
        c2fb_temp_41 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local3 = c2fb_temp_41
        While (-Cast(SQLITE_C_INT, ((local3 < local6->nExpr))))
            c2fb_temp_43 = local18[local3].pExpr
            local9 = c2fb_temp_43
            c2fb_temp_44 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (local13 Or local9->flags)))
            local13 = c2fb_temp_44
            c2fb_temp_45 = local9->pRight
            local10 = c2fb_temp_45
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local9->op) <> Cast(SQLITE_C_INT, 180ULL))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local9->op) <> Cast(SQLITE_C_INT, 142ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local10->op) <> Cast(SQLITE_C_INT, 180ULL)))))))))))))) Then
                c2fb_temp_46 = CPtr(SqliteExprList Ptr, sqlite3ExprListAppend(CPtr(Any Ptr, local0), CPtr(Any Ptr, local19), CPtr(Any Ptr, local18[local3].pExpr)))
                local19 = c2fb_temp_46
                If local19 Then
                    c2fb_temp_47 = @(local19->a(Cast(SQLITE_C_INT, (local19->nExpr - Cast(SQLITE_C_INT, 1ULL)))).zEName)
                    c2fb_temp_48 = CPtr(ZString Ptr, local18[local3].zEName)
                    (*c2fb_temp_47) = CPtr(UByte Ptr, c2fb_temp_48)
                    c2fb_temp_48 = CPtr(ZString Ptr, (*c2fb_temp_47))
                    c2fb_temp_49 = @(local19->a(Cast(SQLITE_C_INT, (local19->nExpr - Cast(SQLITE_C_INT, 1ULL)))).fg.flags)
                    c2fb_temp_50 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local18[local3].fg.flags) Shr 0) And Cast(SQLITE_C_UINT, &H3ULL))))
                    c2fb_temp_50 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_50) And Cast(SQLITE_C_UINT, &H3ULL)))
                    (*c2fb_temp_49) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_49)) And Not(Cast(SQLITE_C_UINT, &H3ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_50) And Cast(SQLITE_C_UINT, &H3ULL)) Shl 0)))
                    c2fb_temp_50 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_50) And Cast(SQLITE_C_UINT, &H3ULL)))
                    c2fb_temp_51 = @(local18[local3].zEName)
                    c2fb_temp_52 = CPtr(ZString Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                    (*c2fb_temp_51) = CPtr(UByte Ptr, c2fb_temp_52)
                    c2fb_temp_52 = CPtr(ZString Ptr, (*c2fb_temp_51))
                End If
                c2fb_temp_53 = @(local18[local3].pExpr)
                c2fb_temp_54 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                (*c2fb_temp_53) = CPtr(Any Ptr, c2fb_temp_54)
                c2fb_temp_54 = CPtr(SqliteExpr Ptr, (*c2fb_temp_53))
            Else
                local22 = Cast(SQLITE_C_INT, &O0ULL)
                local23 = Cast(SQLITE_C_INT, &O0ULL)
                ' C automatic storage declaration
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local9->op) = Cast(SQLITE_C_INT, 142ULL))))) Then
                    ' C unused-parameter annotation
                    ' C unused-parameter annotation
                    ' C unused-parameter annotation
                    c2fb_temp_55 = CPtr(ZString Ptr, local9->pLeft->u.zToken)
                    local23 = c2fb_temp_55
                    ' C unused-parameter annotation
                    c2fb_temp_56 = Cast(SQLITE_C_INT, local9->pRight->w.iOfst)
                    local24 = c2fb_temp_56
                Else
                    ' C unused-parameter annotation
                    c2fb_temp_57 = Cast(SQLITE_C_INT, local9->w.iOfst)
                    local24 = c2fb_temp_57
                End If
                c2fb_temp_58 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local1 = c2fb_temp_58
                c2fb_temp_59 = CPtr(SqliteSrcItem Ptr, (@local5->a(0)))
                local7 = c2fb_temp_59
                While (-Cast(SQLITE_C_INT, ((local1 < local5->nSrc))))
                    ' C automatic storage declaration
                    local26 = local7->pSTab
                    ' C automatic storage declaration
                    ' C automatic storage declaration
                    local29 = Cast(SQLITE_C_INT, &O0ULL)
                    ' C automatic storage declaration
                    ' C automatic storage declaration
                    c2fb_temp_62 = local7->zAlias
                    local28 = c2fb_temp_62
                    If (-Cast(SQLITE_C_INT, (((c2fb_temp_62) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        c2fb_temp_63 = local26->zName
                        local28 = c2fb_temp_63
                    End If
                    If local8->mallocFailed Then
                        Goto c2fb_flow_6
                    End If
                    ' C unused-parameter annotation
                    If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local7->fg.flags) Shr 14) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                        ' C unused-parameter annotation
                        ' C unused-parameter annotation
                        c2fb_temp_64 = local7->u4.pSubq->pSelect->pEList
                        local27 = c2fb_temp_64
                        ' C unused-parameter annotation
                        ' C unused-parameter annotation
                        ' C unused-parameter annotation
                    Else
                        If (-Cast(SQLITE_C_INT, ((local23 AndAlso (-Cast(SQLITE_C_INT, ((sqlite3StrICmp(CPtr(Const ZString Ptr, local23), CPtr(Const ZString Ptr, local28)) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                            Goto c2fb_flow_7
                        End If
                        c2fb_temp_65 = CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                        local27 = c2fb_temp_65
                        c2fb_temp_66 = Cast(SQLITE_C_INT, sqlite3SchemaToIndex(CPtr(Any Ptr, local8), CPtr(Any Ptr, local26->pSchema)))
                        local30 = c2fb_temp_66
                        c2fb_temp_67 = IIf((-Cast(SQLITE_C_INT, ((local30 >= Cast(SQLITE_C_INT, &O0ULL))))), CPtr(Const ZString Ptr, CPtr(ZString Ptr, local8->aDb(local30).zDbSName)), StrPtr(!"*"))
                        local29 = c2fb_temp_67
                    End If
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local1 + Cast(SQLITE_C_INT, 1ULL))) < local5->nSrc)))) AndAlso Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local7[Cast(SQLITE_C_INT, 1ULL)].fg.flags) Shr 11) And Cast(SQLITE_C_UINT, &H1ULL))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local12) And Cast(SQLITE_C_INT, &H0000800ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                        ' C automatic storage declaration
                        c2fb_temp_68 = local7[Cast(SQLITE_C_INT, 1ULL)].u3.pUsing
                        local31 = c2fb_temp_68
                        c2fb_temp_69 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                        local32 = c2fb_temp_69
                        While (-Cast(SQLITE_C_INT, ((local32 < local31->nId))))
                            local33 = local31->a(local32).zName
                            c2fb_temp_71 = CPtr(SqliteExpr Ptr, sqlite3Expr(CPtr(Any Ptr, local8), Cast(SQLITE_C_INT, 60ULL), local33))
                            local10 = c2fb_temp_71
                            sqlite3ExprSetErrorOffset(CPtr(Any Ptr, local10), local24)
                            c2fb_temp_72 = CPtr(SqliteExprList Ptr, sqlite3ExprListAppend(CPtr(Any Ptr, local0), CPtr(Any Ptr, local19), CPtr(Any Ptr, local10)))
                            local19 = c2fb_temp_72
                            If local19 Then
                                local34 = CPtr(SqliteExprListItem Ptr, @(local19->a(Cast(SQLITE_C_INT, (local19->nExpr - Cast(SQLITE_C_INT, 1ULL))))))
                                ' C unused-parameter annotation
                                c2fb_temp_73 = @(local34->zEName)
                                c2fb_temp_74 = CPtr(ZString Ptr, sqlite3MPrintf(CPtr(Any Ptr, local8), StrPtr(!"..%s"), local33))
                                (*c2fb_temp_73) = CPtr(UByte Ptr, c2fb_temp_74)
                                c2fb_temp_74 = CPtr(ZString Ptr, (*c2fb_temp_73))
                                c2fb_temp_75 = @(local34->fg.flags)
                                c2fb_temp_76 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 2ULL))
                                c2fb_temp_76 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_76) And Cast(SQLITE_C_UINT, &H3ULL)))
                                (*c2fb_temp_75) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_75)) And Not(Cast(SQLITE_C_UINT, &H3ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_76) And Cast(SQLITE_C_UINT, &H3ULL)) Shl 0)))
                                c2fb_temp_76 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_76) And Cast(SQLITE_C_UINT, &H3ULL)))
                                c2fb_temp_77 = @(local34->fg.flags)
                                c2fb_temp_78 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                                c2fb_temp_78 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_78) And Cast(SQLITE_C_UINT, &H1ULL)))
                                (*c2fb_temp_77) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_77)) And Not(Cast(SQLITE_C_UINT, &H80ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_78) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 7)))
                                c2fb_temp_78 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_78) And Cast(SQLITE_C_UINT, &H1ULL)))
                            End If
                        c2fb_flow_9:
                            c2fb_temp_70 = local32
                            local32 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_70 + 1)))
                        Wend
                        c2fb_flow_8:
                    Else
                        c2fb_temp_79 = CPtr(SqliteIdList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                        local31 = c2fb_temp_79
                    End If
                    c2fb_temp_80 = Cast(SQLITE_C_INT, local26->nCol)
                    local25 = c2fb_temp_80
                    If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local26)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000200ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local12) And Cast(SQLITE_C_INT, &H0000800ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                        c2fb_temp_81 = local25
                        local25 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_81 + 1)))
                    End If
                    c2fb_temp_82 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    local2 = c2fb_temp_82
                    While (-Cast(SQLITE_C_INT, ((local2 < local25))))
                        ' C automatic storage declaration
                        ' C automatic storage declaration
                        If (-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, local26->nCol))))) Then
                            c2fb_temp_84 = CPtr(Const ZString Ptr, sqlite3RowidAlias(CPtr(Any Ptr, local26)))
                            local35 = c2fb_temp_84
                            If (-Cast(SQLITE_C_INT, ((local35 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                                Goto c2fb_flow_11
                            End If
                        Else
                            c2fb_temp_85 = CPtr(Const ZString Ptr, local26->aCol[local2].zCnName)
                            local35 = c2fb_temp_85
                            If (-Cast(SQLITE_C_INT, ((local27 AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local27->a(local2).fg.flags) Shr 0) And Cast(SQLITE_C_UINT, &H3ULL))) = Cast(SQLITE_C_INT, 3ULL))))))))) Then
                                Goto c2fb_flow_11
                            End If
                            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local23 AndAlso local27)))) AndAlso (-Cast(SQLITE_C_INT, ((sqlite3MatchEName(CPtr(Any Ptr, CPtr(SqliteExprListItem Ptr, @(local27->a(local2)))), Cast(SQLITE_C_INT, &O0ULL), CPtr(Const ZString Ptr, local23), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                                Goto c2fb_flow_11
                            End If
                            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0020000ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (CPtr(SqliteColumn Ptr, @(local26->aCol[local2])))->colFlags) And Cast(SQLITE_C_INT, &H0002ULL)))) <> Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
                                Goto c2fb_flow_11
                            End If
                            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local26->aCol[local2].colFlags) And Cast(SQLITE_C_INT, &H0400ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local23 = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local12) And (Cast(SQLITE_C_INT, &H0000800ULL))))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                                Goto c2fb_flow_11
                            End If
                        End If
                        ' C unused-parameter annotation
                        c2fb_temp_86 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                        local22 = c2fb_temp_86
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local1 > Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local23 = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local12) And Cast(SQLITE_C_INT, &H0000800ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local7->fg.flags) Shr 11) And Cast(SQLITE_C_UINT, &H1ULL))) AndAlso (-Cast(SQLITE_C_INT, ((sqlite3IdListIndex(CPtr(Any Ptr, local7->u3.pUsing), local35) >= Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                                Goto c2fb_flow_11
                            End If
                        End If
                        c2fb_temp_87 = CPtr(SqliteExpr Ptr, sqlite3Expr(CPtr(Any Ptr, local8), Cast(SQLITE_C_INT, 60ULL), local35))
                        local10 = c2fb_temp_87
                        If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local5->nSrc > Cast(SQLITE_C_INT, 1ULL))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local7->fg.jointype) And Cast(SQLITE_C_INT, &H40ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local23 <> Cast(SQLITE_C_INT, &O0ULL))))))))) OrElse (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local12) And Cast(SQLITE_C_INT, &H0000800ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) OrElse (-Cast(SQLITE_C_INT, (inAnyUsingClause(local35, local7, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local5->nSrc - local1)) - Cast(SQLITE_C_INT, 1ULL)))) = 0))))))))))))) OrElse ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->eParseMode) >= Cast(SQLITE_C_INT, 2ULL)))))))))) Then
                            ' C automatic storage declaration
                            c2fb_temp_88 = CPtr(SqliteExpr Ptr, sqlite3Expr(CPtr(Any Ptr, local8), Cast(SQLITE_C_INT, 60ULL), CPtr(Const ZString Ptr, local28)))
                            local37 = c2fb_temp_88
                            c2fb_temp_89 = CPtr(SqliteExpr Ptr, sqlite3PExpr(CPtr(Any Ptr, local0), Cast(SQLITE_C_INT, 142ULL), CPtr(Any Ptr, local37), CPtr(Any Ptr, local10)))
                            local11 = c2fb_temp_89
                            If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->eParseMode) >= Cast(SQLITE_C_INT, 2ULL)))))) AndAlso local9->pLeft)))) Then
                                sqlite3RenameTokenRemap(CPtr(Any Ptr, local0), CPtr(Any Ptr, local37), CPtr(Any Ptr, local9->pLeft))
                            End If
                            If local29 Then
                                c2fb_temp_90 = CPtr(SqliteExpr Ptr, sqlite3Expr(CPtr(Any Ptr, local8), Cast(SQLITE_C_INT, 60ULL), local29))
                                local37 = c2fb_temp_90
                                c2fb_temp_91 = CPtr(SqliteExpr Ptr, sqlite3PExpr(CPtr(Any Ptr, local0), Cast(SQLITE_C_INT, 142ULL), CPtr(Any Ptr, local37), CPtr(Any Ptr, local11)))
                                local11 = c2fb_temp_91
                            End If
                        Else
                            c2fb_temp_92 = local10
                            local11 = c2fb_temp_92
                        End If
                        sqlite3ExprSetErrorOffset(CPtr(Any Ptr, local11), local24)
                        c2fb_temp_93 = CPtr(SqliteExprList Ptr, sqlite3ExprListAppend(CPtr(Any Ptr, local0), CPtr(Any Ptr, local19), CPtr(Any Ptr, local11)))
                        local19 = c2fb_temp_93
                        If (-Cast(SQLITE_C_INT, ((local19 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                            Goto c2fb_flow_10
                        End If
                        c2fb_temp_94 = CPtr(SqliteExprListItem Ptr, @(local19->a(Cast(SQLITE_C_INT, (local19->nExpr - Cast(SQLITE_C_INT, 1ULL))))))
                        local36 = c2fb_temp_94
                        ' C unused-parameter annotation
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local12) And Cast(SQLITE_C_INT, &H0000800ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->eParseMode) >= Cast(SQLITE_C_INT, 2ULL)))))) = 0))))))) Then
                            If (-Cast(SQLITE_C_INT, ((local27 AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &O0ULL) = 0))) OrElse (-Cast(SQLITE_C_INT, ((local2 < local27->nExpr))))))))))))) Then
                                ' C unused-parameter annotation
                                c2fb_temp_95 = @(local36->zEName)
                                c2fb_temp_96 = CPtr(ZString Ptr, sqlite3DbStrDup(CPtr(Any Ptr, local8), CPtr(Const ZString Ptr, CPtr(ZString Ptr, local27->a(local2).zEName))))
                                (*c2fb_temp_95) = CPtr(UByte Ptr, c2fb_temp_96)
                                c2fb_temp_96 = CPtr(ZString Ptr, (*c2fb_temp_95))
                                ' empty C statement
                            Else
                                c2fb_temp_97 = @(local36->zEName)
                                c2fb_temp_98 = CPtr(ZString Ptr, sqlite3MPrintf(CPtr(Any Ptr, local8), StrPtr(!"%s.%s.%s"), local29, local28, local35))
                                (*c2fb_temp_97) = CPtr(UByte Ptr, c2fb_temp_98)
                                c2fb_temp_98 = CPtr(ZString Ptr, (*c2fb_temp_97))
                                ' empty C statement
                            End If
                            c2fb_temp_99 = @(local36->fg.flags)
                            c2fb_temp_100 = Cast(SQLITE_C_INT, (IIf((-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, local26->nCol))))), Cast(SQLITE_C_INT, 3ULL), Cast(SQLITE_C_INT, 2ULL))))
                            c2fb_temp_100 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_100) And Cast(SQLITE_C_UINT, &H3ULL)))
                            (*c2fb_temp_99) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_99)) And Not(Cast(SQLITE_C_UINT, &H3ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_100) And Cast(SQLITE_C_UINT, &H3ULL)) Shl 0)))
                            c2fb_temp_100 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_100) And Cast(SQLITE_C_UINT, &H3ULL)))
                            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local7->fg.flags) Shr 11) And Cast(SQLITE_C_UINT, &H1ULL))) AndAlso (-Cast(SQLITE_C_INT, ((sqlite3IdListIndex(CPtr(Any Ptr, local7->u3.pUsing), local35) >= Cast(SQLITE_C_INT, &O0ULL)))))))))) OrElse ((-Cast(SQLITE_C_INT, ((local31 AndAlso (-Cast(SQLITE_C_INT, ((sqlite3IdListIndex(CPtr(Any Ptr, local31), local35) >= Cast(SQLITE_C_INT, &O0ULL)))))))))))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local2 < Cast(SQLITE_C_INT, local26->nCol))))) AndAlso (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local26->aCol[local2].colFlags) And Cast(SQLITE_C_INT, &H0400ULL))))))))))))) Then
                                c2fb_temp_101 = @(local36->fg.flags)
                                c2fb_temp_102 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                                c2fb_temp_102 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_102) And Cast(SQLITE_C_UINT, &H1ULL)))
                                (*c2fb_temp_101) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_101)) And Not(Cast(SQLITE_C_UINT, &H100ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_102) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 8)))
                                c2fb_temp_102 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_102) And Cast(SQLITE_C_UINT, &H1ULL)))
                            End If
                        Else
                            If local21 Then
                                c2fb_temp_103 = @(local36->zEName)
                                c2fb_temp_104 = CPtr(ZString Ptr, sqlite3MPrintf(CPtr(Any Ptr, local8), StrPtr(!"%s.%s"), local28, local35))
                                (*c2fb_temp_103) = CPtr(UByte Ptr, c2fb_temp_104)
                                c2fb_temp_104 = CPtr(ZString Ptr, (*c2fb_temp_103))
                                c2fb_temp_105 = @(local36->fg.flags)
                                c2fb_temp_106 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                                c2fb_temp_106 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_106) And Cast(SQLITE_C_UINT, &H3ULL)))
                                (*c2fb_temp_105) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_105)) And Not(Cast(SQLITE_C_UINT, &H3ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_106) And Cast(SQLITE_C_UINT, &H3ULL)) Shl 0)))
                                c2fb_temp_106 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_106) And Cast(SQLITE_C_UINT, &H3ULL)))
                            Else
                                c2fb_temp_107 = @(local36->zEName)
                                c2fb_temp_108 = CPtr(ZString Ptr, sqlite3DbStrDup(CPtr(Any Ptr, local8), local35))
                                (*c2fb_temp_107) = CPtr(UByte Ptr, c2fb_temp_108)
                                c2fb_temp_108 = CPtr(ZString Ptr, (*c2fb_temp_107))
                                c2fb_temp_109 = @(local36->fg.flags)
                                c2fb_temp_110 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                                c2fb_temp_110 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_110) And Cast(SQLITE_C_UINT, &H3ULL)))
                                (*c2fb_temp_109) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_109)) And Not(Cast(SQLITE_C_UINT, &H3ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_110) And Cast(SQLITE_C_UINT, &H3ULL)) Shl 0)))
                                c2fb_temp_110 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_110) And Cast(SQLITE_C_UINT, &H3ULL)))
                            End If
                        End If
                    c2fb_flow_11:
                        c2fb_temp_83 = local2
                        local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_83 + 1)))
                    Wend
                    c2fb_flow_10:
                c2fb_flow_7:
                    c2fb_temp_60 = local1
                    local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_60 + 1)))
                    c2fb_temp_61 = local7
                    local7 = (c2fb_temp_61 + 1)
                Wend
                c2fb_flow_6:
                If (-Cast(SQLITE_C_INT, (local22 = 0))) Then
                    If local23 Then
                        sqlite3ErrorMsg(CPtr(Any Ptr, local0), StrPtr(!"no such table: %s"), local23)
                    Else
                        sqlite3ErrorMsg(CPtr(Any Ptr, local0), StrPtr(!"no tables specified"))
                    End If
                End If
            End If
        c2fb_flow_5:
            c2fb_temp_42 = local3
            local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_42 + 1)))
        Wend
        c2fb_flow_4:
        sqlite3ExprListDelete(CPtr(Any Ptr, local8), CPtr(Any Ptr, local6))
        c2fb_temp_111 = @(arg1->pEList)
        c2fb_temp_112 = local19
        (*c2fb_temp_111) = CPtr(Any Ptr, c2fb_temp_112)
        c2fb_temp_112 = CPtr(SqliteExprList Ptr, (*c2fb_temp_111))
    End If
    If arg1->pEList Then
        If (-Cast(SQLITE_C_INT, ((arg1->pEList->nExpr > local8->aLimit(Cast(SQLITE_C_INT, 2ULL)))))) Then
            sqlite3ErrorMsg(CPtr(Any Ptr, local0), StrPtr(!"too many columns in result set"))
            Return Cast(SQLITE_C_INT, 2ULL)
        End If
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local13 And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000008ULL) Or Cast(SQLITE_C_INT, &H400000ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            c2fb_temp_113 = @(arg1->selFlags)
            c2fb_temp_114 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_113)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0040000ULL)))))
            (*c2fb_temp_113) = Cast(u32, c2fb_temp_114)
            c2fb_temp_114 = Cast(SQLITE_C_UINT, (*c2fb_temp_113))
        End If
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Function fromClauseTermCanBeCoroutine CDecl Alias "fromClauseTermCanBeCoroutine" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SqliteSrcItem Ptr
    Dim local1 As Const SqliteCteUse Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SqliteSrcItem Ptr

    local0 = CPtr(SqliteSrcItem Ptr, @(arg1->a(arg2)))
    If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local0->fg.flags) Shr 9) And Cast(SQLITE_C_UINT, &H1ULL))) Then
        local1 = local0->u2.pCteUse
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->eM10d) = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local1->nUse >= Cast(SQLITE_C_INT, 2ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->eM10d) <> Cast(SQLITE_C_INT, 2ULL))))))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
    End If
    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->a(Cast(SQLITE_C_INT, &O0ULL)).fg.jointype) And Cast(SQLITE_C_INT, &H40ULL))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg0->db)->dbOptFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H02000000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((CPtr(SqliteSrcItem Ptr, isSelfJoinView(arg1, local0, Cast(SQLITE_C_INT, (arg2 + Cast(SQLITE_C_INT, 1ULL))), arg1->nSrc)) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((arg2 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        If (-Cast(SQLITE_C_INT, ((arg1->nSrc = Cast(SQLITE_C_INT, 1ULL))))) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->a(Cast(SQLITE_C_INT, 1ULL)).fg.jointype) And Cast(SQLITE_C_INT, &H02ULL))) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
        If Cast(SQLITE_C_INT, (arg3 And Cast(SQLITE_C_INT, &H10000000ULL))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    If Cast(SQLITE_C_INT, (arg3 And Cast(SQLITE_C_INT, &H10000000ULL))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    While Cast(SQLITE_C_INT, 1ULL)
        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H20ULL) Or Cast(SQLITE_C_INT, &H02ULL)))))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
        If (-Cast(SQLITE_C_INT, ((arg2 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_0
        End If
        c2fb_temp_0 = arg2
        arg2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_0 - 1)))
        c2fb_temp_1 = local0
        local0 = (c2fb_temp_1 - 1)
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local0->fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        End If
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    Return Cast(SQLITE_C_INT, 1ULL)
End Function

Private Function convertCompoundSelectToSubquery CDecl Alias "convertCompoundSelectToSubquery" ( _
    ByVal pWalker As SqliteWalker Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
) As SQLITE_C_INT
    If pWalker = 0 OrElse pWalker->pParse = 0 OrElse pSelect = 0 Then _
        Return WRC_ABORT
    If pSelect->pPrior = 0 OrElse pSelect->pOrderBy = 0 Then _
        Return WRC_CONTINUE

    Dim pTerm As SqliteSelect Ptr = pSelect
    While pTerm <> 0 AndAlso (pTerm->op = TK_ALL OrElse pTerm->op = TK_SELECT)
        pTerm = pTerm->pPrior
    Wend
    If pTerm = 0 Then Return WRC_CONTINUE

    Dim pOrderBy As SqliteExprList Ptr = pSelect->pOrderBy
    If pOrderBy->nExpr <= 0 OrElse pOrderBy->nAlloc < pOrderBy->nExpr Then _
        Return WRC_ABORT
#ifndef SQLITE_OMIT_WINDOWFUNC
    If pOrderBy->a(0).u.x.iOrderByCol <> 0 Then Return WRC_CONTINUE
#endif

    Dim orderIndex As SQLITE_C_INT = pOrderBy->nExpr - 1
    While orderIndex >= 0
        Dim pOrderItem As SqliteExprListItem Ptr = @pOrderBy->a(orderIndex)
        If pOrderItem->pExpr <> 0 AndAlso _
           (pOrderItem->pExpr->flags And EP_Collate) <> 0 Then Exit While
        orderIndex -= 1
    Wend
    If orderIndex < 0 Then Return WRC_CONTINUE

    Dim pParse As SqliteParseContext Ptr = pWalker->pParse
    Dim db As sqlite3 Ptr = pParse->db
    If db = 0 Then Return WRC_ABORT
    Dim pNew As SqliteSelect Ptr = CPtr(SqliteSelect Ptr, _
        sqlite3DbMallocZero(db, SizeOf(SqliteSelect)))
    If pNew = 0 Then Return WRC_ABORT

    Dim dummyToken As sqlite3ParserToken = Type<sqlite3ParserToken>(0)
    Dim pNewSource As SqliteSrcList Ptr = CPtr(SqliteSrcList Ptr, _
        sqlite3SrcListAppendFromTerm(pParse, 0, 0, 0, @dummyToken, pNew, 0))
    If pNewSource = 0 OrElse pParse->nErr <> 0 Then
        If pNewSource <> 0 Then
            sqlite3SrcListDelete(db, pNewSource)
        Else
            sqlite3DbFree(db, pNew)
        End If
        Return WRC_ABORT
    End If

    pNew[0] = pSelect[0]
    If pNew->pPrior = 0 Then
        sqlite3SrcListDelete(db, pNewSource)
        Return WRC_ABORT
    End If
    pSelect->pSrc = pNewSource
    Dim pAsterisk As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, _
        sqlite3Expr(db, TK_ASTERISK, 0))
    pSelect->pEList = CPtr(SqliteExprList Ptr, _
        sqlite3ExprListAppend(pParse, 0, pAsterisk))
    pSelect->op = TK_SELECT
    pSelect->pWhere = 0
    pNew->pGroupBy = 0
    pNew->pHaving = 0
    pNew->pOrderBy = 0
    pSelect->pPrior = 0
    pSelect->pNext = 0
    pSelect->pWith = 0
#ifndef SQLITE_OMIT_WINDOWFUNC
    pSelect->pWinDefn = 0
#endif
    pSelect->selFlags = pSelect->selFlags And Not CUInt(SF_Compound)
    pSelect->selFlags Or= SF_Converted
    pNew->pPrior->pNext = pNew
    pNew->pLimit = 0
    Return WRC_CONTINUE
End Function


/' SELECT expansion and preparation entry points '/

Private Sub sqlite3SelectExpand CDecl Alias "sqlite3SelectExpand" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr)
    Dim local0 As SqliteWalker
    Dim c2fb_temp_0 As SqliteWalkerExprCallback Ptr
    Dim c2fb_temp_1 As c2fb_callback_82
    Dim c2fb_temp_2 As SqliteParseContext Ptr Ptr
    Dim c2fb_temp_3 As SqliteParseContext Ptr
    Dim c2fb_temp_4 As SqliteWalkerSelectCallback Ptr
    Dim c2fb_temp_5 As c2fb_callback_82
    Dim c2fb_temp_6 As SqliteWalkerSelectCallback2 Ptr
    Dim c2fb_temp_7 As c2fb_callback_83
    Dim c2fb_temp_8 As SqliteWalkerSelectCallback Ptr
    Dim c2fb_temp_9 As c2fb_callback_82
    Dim c2fb_temp_10 As SqliteWalkerSelectCallback2 Ptr
    Dim c2fb_temp_11 As c2fb_callback_83
    Dim c2fb_temp_12 As UShort Ptr
    Dim c2fb_temp_13 As UShort

    ' C automatic storage declaration
    c2fb_temp_0 = @(local0.xExprCallback)
    c2fb_temp_1 = CPtr(c2fb_callback_82, ProcPtr(sqlite3ExprWalkNoop))
    (*c2fb_temp_0) = Cast(SqliteWalkerExprCallback, c2fb_temp_1)
    c2fb_temp_1 = CPtr(c2fb_callback_82, (*c2fb_temp_0))
    c2fb_temp_2 = @(local0.pParse)
    c2fb_temp_3 = arg0
    (*c2fb_temp_2) = c2fb_temp_3
    If (arg0->hasCompound) Then
        c2fb_temp_4 = @(local0.xSelectCallback)
        c2fb_temp_5 = CPtr(c2fb_callback_82, ProcPtr(convertCompoundSelectToSubquery))
        (*c2fb_temp_4) = Cast(SqliteWalkerSelectCallback, c2fb_temp_5)
        c2fb_temp_5 = CPtr(c2fb_callback_82, (*c2fb_temp_4))
        c2fb_temp_6 = @(local0.xSelectCallback2)
        c2fb_temp_7 = CPtr(c2fb_callback_83, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_6) = Cast(SqliteWalkerSelectCallback2, c2fb_temp_7)
        c2fb_temp_7 = CPtr(c2fb_callback_83, (*c2fb_temp_6))
        sqlite3WalkSelect(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local0))), CPtr(Any Ptr, arg1))
    End If
    c2fb_temp_8 = @(local0.xSelectCallback)
    c2fb_temp_9 = CPtr(c2fb_callback_82, ProcPtr(selectExpander))
    (*c2fb_temp_8) = Cast(SqliteWalkerSelectCallback, c2fb_temp_9)
    c2fb_temp_9 = CPtr(c2fb_callback_82, (*c2fb_temp_8))
    c2fb_temp_10 = @(local0.xSelectCallback2)
    c2fb_temp_11 = CPtr(c2fb_callback_83, ProcPtr(sqlite3SelectPopWith))
    (*c2fb_temp_10) = Cast(SqliteWalkerSelectCallback2, c2fb_temp_11)
    c2fb_temp_11 = CPtr(c2fb_callback_83, (*c2fb_temp_10))
    c2fb_temp_12 = @(local0.eCode)
    c2fb_temp_13 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_12) = c2fb_temp_13
    sqlite3WalkSelect(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local0))), CPtr(Any Ptr, arg1))
End Sub

Sub sqlite3SelectPrep CDecl Alias "sqlite3SelectPrep" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSelect Ptr, ByVal arg2 As SqliteNameContext Ptr)
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If arg0->db->mallocFailed Then
        Return
    End If
    If Cast(SQLITE_C_UINT, (arg1->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000080ULL)))) Then
        Return
    End If
    sqlite3SelectExpand(arg0, arg1)
    If arg0->nErr Then
        Return
    End If
    sqlite3ResolveSelectNames(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), CPtr(Any Ptr, arg2))
    If arg0->nErr Then
        Return
    End If
    sqlite3SelectAddTypeInfo(arg0, arg1)
End Sub

/' ------------------------------------------------------------------------- '/
/' Substitute flattened SELECT expressions                                  '/
/' ------------------------------------------------------------------------- '/

Private Function substExpr CDecl Alias "substExpr" ( _
    ByVal pSubst As SqliteSubstContext Ptr, _
    ByVal pExpression As SqliteExpr Ptr _
) As SqliteExpr Ptr
    If pSubst = 0 OrElse pSubst->pParse = 0 OrElse _
       pSubst->pParse->db = 0 OrElse pExpression = 0 Then Return pExpression

    Dim outerOnFlags As u32 = EP_OuterON Or EP_InnerON
    If (pExpression->flags And outerOnFlags) <> 0 AndAlso _
       pExpression->w.iJoin = pSubst->iTable Then
        pExpression->w.iJoin = pSubst->iNewTable
    End If

    If pExpression->op = TK_COLUMN AndAlso _
       pExpression->iTable = pSubst->iTable AndAlso _
       (pExpression->flags And EP_FixedCol) = 0 Then
#ifdef SQLITE_ALLOW_ROWID_IN_VIEW
        If pExpression->iColumn < 0 Then
            pExpression->op = TK_NULL
            Return pExpression
        End If
#endif
        Dim columnIndex As SQLITE_C_INT = pExpression->iColumn
        If columnIndex < 0 OrElse pSubst->pEList = 0 OrElse _
           pSubst->pCList = 0 OrElse columnIndex >= pSubst->pEList->nExpr OrElse _
           columnIndex >= pSubst->pCList->nExpr Then Return pExpression
        If pExpression->pRight <> 0 Then Return pExpression

        Dim pReplacement As SqliteExpr Ptr = _
            pSubst->pEList->a(columnIndex).pExpr
        If pReplacement = 0 Then Return pExpression
        If sqlite3ExprIsVector(pReplacement) <> 0 Then
            sqlite3VectorErrorMsg(pSubst->pParse, pReplacement)
            Return pExpression
        End If

        Dim db As sqlite3 Ptr = pSubst->pParse->db
        Dim ifNullRow As SqliteExpr = Type<SqliteExpr>(0)
        If pSubst->isOuterJoin <> 0 AndAlso _
           (pReplacement->op <> TK_COLUMN OrElse _
            pReplacement->iTable <> pSubst->iNewTable) Then
            ifNullRow.op = TK_IF_NULL_ROW
            ifNullRow.pLeft = pReplacement
            ifNullRow.iTable = pSubst->iNewTable
            ifNullRow.iColumn = -99
            ifNullRow.flags = EP_IfNullRow
            pReplacement = @ifNullRow
        End If

        Dim pNew As SqliteExpr Ptr = sqlite3ExprDup(db, pReplacement, 0)
        If pNew = 0 OrElse db->mallocFailed <> 0 Then
            sqlite3ExprDelete(db, pNew)
            Return pExpression
        End If
        If pSubst->isOuterJoin <> 0 Then pNew->flags Or= EP_CanBeNull

        If pNew->op = TK_TRUEFALSE Then
            pNew->u.iValue = sqlite3ExprTruthValue(pNew)
            pNew->op = TK_INTEGER
            pNew->flags Or= EP_IntValue
        End If

        Dim pNaturalCollation As sqlite3CollSeq Ptr = _
            sqlite3ExprCollSeq(pSubst->pParse, pNew)
        Dim pReplacementCollation As sqlite3CollSeq Ptr = _
            sqlite3ExprCollSeq(pSubst->pParse, _
                pSubst->pCList->a(columnIndex).pExpr)
        If pNaturalCollation <> pReplacementCollation OrElse _
           (pNew->op <> TK_COLUMN AndAlso pNew->op <> TK_COLLATE) Then
            Dim zCollation As Const ZString Ptr = StrPtr(!"BINARY")
            If pReplacementCollation <> 0 AndAlso _
               pReplacementCollation->zName <> 0 Then _
                zCollation = pReplacementCollation->zName
            pNew = sqlite3ExprAddCollateString( _
                pSubst->pParse, pNew, zCollation)
        End If
        If pNew = 0 Then
            sqlite3ExprDelete(db, pExpression)
            Return 0
        End If
        pNew->flags And= Not CUInt(EP_Collate)
        If (pExpression->flags And outerOnFlags) <> 0 Then
            sqlite3SetJoinExpr(pNew, pExpression->w.iJoin, _
                pExpression->flags And outerOnFlags)
        End If
        sqlite3ExprDelete(db, pExpression)
        Return pNew
    End If

    If pExpression->op = TK_IF_NULL_ROW AndAlso _
       pExpression->iTable = pSubst->iTable Then
        pExpression->iTable = pSubst->iNewTable
    End If
    If pExpression->op = TK_AGG_FUNCTION AndAlso _
       pExpression->op2 >= pSubst->nSelDepth Then
        pExpression->op2 -= 1
    End If

    pExpression->pLeft = substExpr(pSubst, pExpression->pLeft)
    pExpression->pRight = substExpr(pSubst, pExpression->pRight)
    If (pExpression->flags And EP_xIsSelect) <> 0 Then
        substSelect(pSubst, pExpression->x.pSelect, 1)
    Else
        substExprList(pSubst, pExpression->x.pList)
    End If
#ifndef SQLITE_OMIT_WINDOWFUNC
    If (pExpression->flags And EP_WinFunc) <> 0 AndAlso _
       pExpression->y.pWin <> 0 Then
        Dim pWindow As SqliteWalkerWindow Ptr = _
            CPtr(SqliteWalkerWindow Ptr, pExpression->y.pWin)
        pWindow->pFilter = substExpr(pSubst, pWindow->pFilter)
        substExprList(pSubst, pWindow->pPartition)
        substExprList(pSubst, pWindow->pOrderBy)
    End If
#endif
    Return pExpression
End Function

Private Sub substExprList CDecl Alias "substExprList" ( _
    ByVal pSubst As SqliteSubstContext Ptr, _
    ByVal pList As SqliteExprList Ptr _
)
    If pSubst = 0 OrElse pList = 0 OrElse pList->nExpr < 0 OrElse _
       pList->nExpr > pList->nAlloc Then Return
    For itemIndex As SQLITE_C_INT = 0 To pList->nExpr - 1
        pList->a(itemIndex).pExpr = _
            substExpr(pSubst, pList->a(itemIndex).pExpr)
    Next
End Sub

Private Sub substSelect CDecl Alias "substSelect" ( _
    ByVal pSubst As SqliteSubstContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal doPrior As SQLITE_C_INT _
)
    If pSubst = 0 OrElse pSelect = 0 Then Return
    pSubst->nSelDepth += 1
    Dim pCurrent As SqliteSelect Ptr = pSelect
    While pCurrent <> 0
        substExprList(pSubst, pCurrent->pEList)
        substExprList(pSubst, pCurrent->pGroupBy)
        substExprList(pSubst, pCurrent->pOrderBy)
        pCurrent->pHaving = substExpr(pSubst, pCurrent->pHaving)
        pCurrent->pWhere = substExpr(pSubst, pCurrent->pWhere)

        Dim pSourceList As SqliteSrcList Ptr = pCurrent->pSrc
        If pSourceList <> 0 AndAlso pSourceList->nSrc >= 0 AndAlso _
           pSourceList->nSrc <= pSourceList->nAlloc Then
            For sourceIndex As SQLITE_C_INT = 0 To pSourceList->nSrc - 1
                Dim pItem As SqliteSrcItem Ptr = @pSourceList->a(sourceIndex)
                If (pItem->fg.flags And SRCITEM_IS_SUBQUERY) <> 0 AndAlso _
                   pItem->u4.pSubq <> 0 Then
                    substSelect(pSubst, pItem->u4.pSubq->pSelect, 1)
                End If
                If (pItem->fg.flags And SRCITEM_IS_TABFUNC) <> 0 Then _
                    substExprList(pSubst, pItem->u1.pFuncArg)
            Next
        End If

        If doPrior = 0 OrElse pCurrent->pPrior = 0 Then Exit While
        pCurrent = pCurrent->pPrior
    Wend
    pSubst->nSelDepth -= 1
End Sub

/' end of sqlite3_bulk39_select.bas '/
