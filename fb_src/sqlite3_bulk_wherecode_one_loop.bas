/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_bulk_wherecode_one_loop.bas

    Purpose:

        Generate VDBE instructions for one selected WHERE loop.

    Responsibilities:

        - Emit loop setup, equality-term, and IN-index operations.
        - Handle deferred seeks, affinity, and expression code for one loop.
        - Insert optional cursor hints at range and full-scan loop sites.
        - Record statement scan status for OR subloops when enabled.
        - Keep local code-generation helpers in the same module.

    This file intentionally does NOT contain:

        - Choose the order of nested WHERE loops.
        - A claim that body coverage establishes runtime parity.
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
#include once "sqlite3_walker.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_schema_types.bi"
#ifdef SQLITE_ENABLE_CURSOR_HINTS
Declare Sub codeCursorHint CDecl Alias "codeCursorHint" ( _
    ByVal pTabItem As SqliteSrcItem Ptr, _
    ByVal pWhereInfo As SqliteWhereInfo Ptr, _
    ByVal pLevel As SqliteWhereLevel Ptr, _
    ByVal pEndRange As SqliteWhereTerm Ptr _
)
#endif
#ifdef SQLITE_ENABLE_STMT_SCANSTATUS
Declare Sub sqlite3WhereAddScanStatus CDecl Alias "sqlite3WhereAddScanStatus" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pSrcList As SqliteSrcList Ptr, _
    ByVal pLevel As SqliteWhereLevel Ptr, _
    ByVal addrExplain As SQLITE_C_INT _
)
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
Declare Function sqlite3WhereExplainOneScan CDecl Alias "sqlite3WhereExplainOneScan" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As SqliteWhereLevel Ptr, ByVal arg3 As UShort) As SQLITE_C_INT
Declare Sub sqlite3VdbeExplainPop CDecl Alias "sqlite3VdbeExplainPop" (ByVal arg0 As SqliteParseContext Ptr)

Declare Sub disableTerm CDecl Alias "disableTerm" (ByVal arg0 As SqliteWhereLevel Ptr, ByVal arg1 As SqliteWhereTerm Ptr)
Declare Sub codeApplyAffinity CDecl Alias "codeApplyAffinity" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As ZString Ptr)
Declare Sub updateRangeAffinityStr CDecl Alias "updateRangeAffinityStr" (ByVal arg0 As SqliteExpr Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As ZString Ptr)
Declare Function codeEqualityTerm CDecl Alias "codeEqualityTerm" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteWhereTerm Ptr, ByVal arg2 As SqliteWhereLevel Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function codeAllEqualityTerms CDecl Alias "codeAllEqualityTerms" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteWhereLevel Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As ZString Ptr Ptr) As SQLITE_C_INT
Declare Sub whereLikeOptimizationStringFixup CDecl Alias "whereLikeOptimizationStringFixup" (ByVal arg0 As SqliteVdbe Ptr, ByVal arg1 As SqliteWhereLevel Ptr, ByVal arg2 As SqliteWhereTerm Ptr)
Declare Sub codeDeferredSeek CDecl Alias "codeDeferredSeek" (ByVal arg0 As SqliteWhereInfo Ptr, ByVal arg1 As SqliteIndex Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Declare Sub codeExprOrVector CDecl Alias "codeExprOrVector" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
Declare Sub whereApplyPartialIndexConstraints CDecl Alias "whereApplyPartialIndexConstraints" (ByVal arg0 As SqliteExpr Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteWhereClause Ptr)
Declare Sub filterPullDown CDecl Alias "filterPullDown" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteWhereInfo Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As sqlite3_uint64)
Declare Function whereLoopIsOneRow CDecl Alias "whereLoopIsOneRow" (ByVal arg0 As SqliteWhereLoop Ptr) As SQLITE_C_INT
Declare Function whereExprIsReady CDecl Alias "whereExprIsReady" (ByVal arg0 As SqliteWhereInfo Ptr, ByVal arg1 As SqliteWhereLevel Ptr, ByVal arg2 As SqliteSrcItem Ptr, ByVal arg3 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function c2fb_crt_memcpy CDecl Alias "memcpy" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_SIZE_T) As Any Ptr
' c2fb skipped __bswap_16: outside the supported subset
' c2fb skipped __bswap_32: outside the supported subset
' c2fb skipped __bswap_64: outside the supported subset
' c2fb skipped __uint16_identity: outside the supported subset
' c2fb skipped __uint32_identity: outside the supported subset
' c2fb skipped __uint64_identity: outside the supported subset
' c2fb skipped sqlite3IsBinary: FreeBASIC body already exists
' c2fb skipped explainIndexColumnName: outside the supported subset
' c2fb skipped explainAppendTerm: outside the supported subset
' c2fb skipped explainIndexRange: outside the supported subset
' c2fb skipped sqlite3WhereAddExplainText: FreeBASIC body already exists
' c2fb skipped sqlite3WhereExplainOneScan: FreeBASIC body already exists
' c2fb skipped sqlite3WhereExplainBloomFilter: FreeBASIC body already exists
Declare Sub adjustOrderByCol CDecl Alias "adjustOrderByCol" (ByVal arg0 As SqliteExprList Ptr, ByVal arg1 As SqliteExprList Ptr)
Declare Function removeUnindexableInClauseTerms CDecl Alias "removeUnindexableInClauseTerms" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal equalityIndex As SQLITE_C_INT, _
    ByVal pLoop As SqliteWhereLoop Ptr, _
    ByVal pExpression As SqliteExpr Ptr _
) As SqliteExpr Ptr
Declare Sub codeINTerm CDecl Alias "codeINTerm" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pTerm As SqliteWhereTerm Ptr, _
    ByVal pLevel As SqliteWhereLevel Ptr, _
    ByVal equalityIndex As SQLITE_C_INT, _
    ByVal reverseOrder As SQLITE_C_INT, _
    ByVal targetRegister As SQLITE_C_INT _
)


/' ------------------------------------------------------------------------- '/
/' Translated one-loop VDBE code generation '/
/' ------------------------------------------------------------------------- '/
Private Sub disableTerm CDecl Alias "disableTerm" (ByVal arg0 As SqliteWhereLevel Ptr, ByVal arg1 As SqliteWhereTerm Ptr)
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As u16 Ptr
    Dim c2fb_temp_1 As UShort
    Dim c2fb_temp_2 As u16 Ptr
    Dim c2fb_temp_3 As UShort
    Dim c2fb_temp_4 As SqliteWhereTerm Ptr
    Dim c2fb_temp_5 As u8 Ptr
    Dim c2fb_temp_6 As UByte
    Dim c2fb_temp_7 As SQLITE_C_INT

    local0 = Cast(SQLITE_C_INT, &O0ULL)
    ' C unused-parameter annotation
    While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->wtFlags) And Cast(SQLITE_C_INT, &H0004ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg0->iLeftJoin = Cast(SQLITE_C_INT, &O0ULL))))) OrElse ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1->pExpr)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000001ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (arg0->notReady And arg1->prereqAll))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))))))))))
        If (-Cast(SQLITE_C_INT, ((local0 AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->wtFlags) And Cast(SQLITE_C_INT, &H0400ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            c2fb_temp_0 = CPtr(u16 Ptr, @(arg1->wtFlags))
            c2fb_temp_1 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_0))) Or Cast(SQLITE_C_INT, &H0200ULL))))
            (*c2fb_temp_0) = Cast(u16, c2fb_temp_1)
            c2fb_temp_1 = Cast(UShort, (*c2fb_temp_0))
        Else
            c2fb_temp_2 = CPtr(u16 Ptr, @(arg1->wtFlags))
            c2fb_temp_3 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_2))) Or Cast(SQLITE_C_INT, &H0004ULL))))
            (*c2fb_temp_2) = Cast(u16, c2fb_temp_3)
            c2fb_temp_3 = Cast(UShort, (*c2fb_temp_2))
        End If
        If (-Cast(SQLITE_C_INT, ((arg1->iParent < Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_0
        End If
        c2fb_temp_4 = CPtr(SqliteWhereTerm Ptr, @(arg1->pWC->a[arg1->iParent]))
        arg1 = c2fb_temp_4
        ' C unused-parameter annotation
        c2fb_temp_5 = CPtr(u8 Ptr, @(arg1->nChild))
        c2fb_temp_6 = Cast(UByte, (*c2fb_temp_5))
        (*c2fb_temp_5) = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_6) - 1)))
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->nChild) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_0
        End If
        c2fb_temp_7 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_7 + 1)))
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
End Sub

Private Sub codeApplyAffinity CDecl Alias "codeApplyAffinity" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As ZString Ptr)
    Dim local0 As SqliteVdbe Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As ZString Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT

    local0 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    If (-Cast(SQLITE_C_INT, ((arg3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        ' C unused-parameter annotation
        Return
    End If
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg2 > Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(Byte Ptr, arg3)[Cast(SQLITE_C_INT, &O0ULL)]) <= Cast(SQLITE_C_INT, &H41ULL)))))))))
        c2fb_temp_0 = arg2
        arg2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_0 - 1)))
        c2fb_temp_1 = arg1
        arg1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
        c2fb_temp_2 = arg3
        arg3 = (c2fb_temp_2 + 1)
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg2 > Cast(SQLITE_C_INT, 1ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(Byte Ptr, arg3)[Cast(SQLITE_C_INT, (arg2 - Cast(SQLITE_C_INT, 1ULL)))]) <= Cast(SQLITE_C_INT, &H41ULL)))))))))
        c2fb_temp_3 = arg2
        arg2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_3 - 1)))
    c2fb_flow_3:
    Wend
    c2fb_flow_2:
    If (-Cast(SQLITE_C_INT, ((arg2 > Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3VdbeAddOp4(local0, Cast(SQLITE_C_INT, 98ULL), arg1, arg2, Cast(SQLITE_C_INT, &O0ULL), CPtr(Const ZString Ptr, arg3), arg2)
    End If
End Sub

Private Sub updateRangeAffinityStr CDecl Alias "updateRangeAffinityStr" (ByVal arg0 As SqliteExpr Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As ZString Ptr)
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local1 As SqliteExpr Ptr
    Dim c2fb_temp_2 As Byte Ptr
    Dim c2fb_temp_3 As Byte

    ' C automatic storage declaration
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((local0 < arg1))))
        local1 = CPtr(SqliteExpr Ptr, sqlite3VectorFieldSubexpr(CPtr(Any Ptr, arg0), local0))
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, sqlite3CompareAffinity(CPtr(Any Ptr, local1), CPtr(Byte Ptr, arg2)[local0])) = Cast(SQLITE_C_INT, &H41ULL))))) OrElse sqlite3ExprNeedsNoAffinityChange(CPtr(Any Ptr, local1), CPtr(Byte Ptr, arg2)[local0]))))) Then
            c2fb_temp_2 = CPtr(Byte Ptr, @(CPtr(Byte Ptr, arg2)[local0]))
            c2fb_temp_3 = Cast(Byte, Cast(SQLITE_C_INT, &H41ULL))
            (*c2fb_temp_2) = c2fb_temp_3
        End If
    c2fb_flow_1:
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    Wend
    c2fb_flow_0:
End Sub

' c2fb skipped adjustOrderByCol: outside the supported subset
' c2fb skipped removeUnindexableInClauseTerms: outside the supported subset
' c2fb skipped codeINTerm: outside the supported subset
Private Function codeEqualityTerm CDecl Alias "codeEqualityTerm" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteWhereTerm Ptr, ByVal arg2 As SqliteWhereLevel Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT, ByVal arg5 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SqliteExpr Ptr
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT

    local0 = arg1->pExpr
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->op) = Cast(SQLITE_C_INT, 54ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->op) = Cast(SQLITE_C_INT, 45ULL))))))))) Then
        c2fb_temp_0 = Cast(SQLITE_C_INT, sqlite3ExprCodeTarget(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local0->pRight), arg5))
        local1 = c2fb_temp_0
    Else
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->op) = Cast(SQLITE_C_INT, 51ULL))))) Then
            c2fb_temp_1 = Cast(SQLITE_C_INT, arg5)
            local1 = c2fb_temp_1
            sqlite3VdbeAddOp2(CPtr(SqliteVdbe Ptr, arg0->pVdbe), Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), local1)
        Else
            ' C unused-parameter annotation
            c2fb_temp_2 = Cast(SQLITE_C_INT, arg5)
            local1 = c2fb_temp_2
            codeINTerm(arg0, arg1, arg2, arg3, arg4, arg5)
        End If
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg2->pWLoop->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00200000ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) OrElse (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->eOperator) And Cast(SQLITE_C_INT, &H0800ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        disableTerm(arg2, arg1)
    End If
    Return local1
End Function

Private Function codeAllEqualityTerms CDecl Alias "codeAllEqualityTerms" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteWhereLevel Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As ZString Ptr Ptr) As SQLITE_C_INT
    Dim local0 As UShort
    Dim local1 As UShort
    Dim local2 As SqliteVdbe Ptr
    Dim local3 As SqliteIndex Ptr
    Dim local4 As SqliteWhereTerm Ptr
    Dim local5 As SqliteWhereLoop Ptr
    Dim local6 As SQLITE_C_INT
    Dim local7 As SQLITE_C_INT
    Dim local8 As SQLITE_C_INT
    Dim local9 As ZString Ptr
    Dim c2fb_temp_0 As SqliteWhereLoop Ptr
    Dim c2fb_temp_1 As UShort
    Dim c2fb_temp_2 As UShort
    Dim c2fb_temp_3 As SqliteIndex Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As ZString Ptr
    Dim local10 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT Ptr
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim local11 As SQLITE_C_INT
    Dim c2fb_temp_16 As SqliteWhereTerm Ptr
    Dim c2fb_temp_17 As SQLITE_C_INT
    Dim c2fb_temp_18 As Byte Ptr
    Dim c2fb_temp_19 As Byte
    Dim local12 As SqliteExpr Ptr
    Dim c2fb_temp_20 As Byte Ptr
    Dim c2fb_temp_21 As Byte
    Dim c2fb_temp_22 As Byte Ptr
    Dim c2fb_temp_23 As Byte
    Dim c2fb_temp_24 As ZString Ptr Ptr
    Dim c2fb_temp_25 As ZString Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    local2 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    c2fb_temp_0 = arg1->pWLoop
    local5 = c2fb_temp_0
    ' C unused-parameter annotation
    c2fb_temp_1 = Cast(UShort, local5->u.btree.nEq)
    local0 = c2fb_temp_1
    c2fb_temp_2 = Cast(UShort, local5->nSkip)
    local1 = c2fb_temp_2
    c2fb_temp_3 = CPtr(SqliteIndex Ptr, local5->u.btree.pIndex)
    local3 = c2fb_temp_3
    ' C unused-parameter annotation
    c2fb_temp_4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (arg0->nMem + Cast(SQLITE_C_INT, 1ULL))))
    local7 = c2fb_temp_4
    c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0) + arg3)))
    local8 = c2fb_temp_5
    c2fb_temp_6 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
    c2fb_temp_7 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((*c2fb_temp_6) + local8)))
    (*c2fb_temp_6) = c2fb_temp_7
    c2fb_temp_8 = CPtr(ZString Ptr, sqlite3DbStrDup(CPtr(Any Ptr, arg0->db), CPtr(Const ZString Ptr, sqlite3IndexAffinityStr(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, local3)))))
    local9 = c2fb_temp_8
    ' C unused-parameter annotation
    If local1 Then
        local10 = arg1->iIdxCur
        sqlite3VdbeAddOp3(local2, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), local7, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local7 + Cast(SQLITE_C_INT, local1))) - Cast(SQLITE_C_INT, 1ULL))))
        sqlite3VdbeAddOp1(local2, (IIf(arg2, Cast(SQLITE_C_INT, 32ULL), Cast(SQLITE_C_INT, 36ULL))), local10)
        ' empty C statement
        ' empty C statement
        ' empty C statement
        c2fb_temp_9 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp0(local2, Cast(SQLITE_C_INT, 9ULL)))
        local6 = c2fb_temp_9
        ' C unused-parameter annotation
        c2fb_temp_10 = CPtr(SQLITE_C_INT Ptr, @(arg1->addrSkip))
        c2fb_temp_11 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp4Int(local2, (IIf(arg2, Cast(SQLITE_C_INT, 21ULL), Cast(SQLITE_C_INT, 24ULL))), local10, Cast(SQLITE_C_INT, &O0ULL), local7, local1))
        (*c2fb_temp_10) = c2fb_temp_11
        ' empty C statement
        ' empty C statement
        sqlite3VdbeJumpHere(local2, local6)
        c2fb_temp_12 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local6 = c2fb_temp_12
        While (-Cast(SQLITE_C_INT, ((local6 < Cast(SQLITE_C_INT, local1)))))
            sqlite3VdbeAddOp3(local2, Cast(SQLITE_C_INT, 96ULL), local10, local6, Cast(SQLITE_C_INT, (local7 + local6)))
            ' empty C statement
            ' empty C statement
        c2fb_flow_1:
            c2fb_temp_13 = local6
            local6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_13 + 1)))
        Wend
        c2fb_flow_0:
    End If
    ' C unused-parameter annotation
    c2fb_temp_14 = Cast(SQLITE_C_INT, local1)
    local6 = c2fb_temp_14
    While (-Cast(SQLITE_C_INT, ((local6 < Cast(SQLITE_C_INT, local0)))))
        ' C automatic storage declaration
        c2fb_temp_16 = local5->aLTerm[local6]
        local4 = c2fb_temp_16
        ' C unused-parameter annotation
        ' empty C statement
        ' empty C statement
        c2fb_temp_17 = Cast(SQLITE_C_INT, codeEqualityTerm(arg0, local4, arg1, local6, arg2, Cast(SQLITE_C_INT, (local7 + local6))))
        local11 = c2fb_temp_17
        If (-Cast(SQLITE_C_INT, ((local11 <> Cast(SQLITE_C_INT, (local7 + local6)))))) Then
            sqlite3VdbeAddOp2(local2, Cast(SQLITE_C_INT, 82ULL), local11, Cast(SQLITE_C_INT, (local7 + local6)))
        End If
        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local4->eOperator) And Cast(SQLITE_C_INT, &H0001ULL))) Then
            If Cast(SQLITE_C_UINT, (local4->pExpr->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL)))) Then
                If local9 Then
                    c2fb_temp_18 = CPtr(Byte Ptr, @(CPtr(Byte Ptr, local9)[local6]))
                    c2fb_temp_19 = Cast(Byte, Cast(SQLITE_C_INT, &H41ULL))
                    (*c2fb_temp_18) = c2fb_temp_19
                End If
            End If
        Else
            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local4->eOperator) And Cast(SQLITE_C_INT, &H0100ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                local12 = local4->pExpr->pRight
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local4->wtFlags) And Cast(SQLITE_C_INT, &H0800ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso sqlite3ExprCanBeNull(CPtr(Any Ptr, local12)))))) Then
                    sqlite3VdbeAddOp2(local2, Cast(SQLITE_C_INT, 51ULL), Cast(SQLITE_C_INT, (local7 + local6)), arg1->addrBrk)
                    ' empty C statement
                End If
                If (-Cast(SQLITE_C_INT, ((arg0->nErr = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    ' C unused-parameter annotation
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, sqlite3CompareAffinity(CPtr(Any Ptr, local12), CPtr(Byte Ptr, local9)[local6])) = Cast(SQLITE_C_INT, &H41ULL))))) Then
                        c2fb_temp_20 = CPtr(Byte Ptr, @(CPtr(Byte Ptr, local9)[local6]))
                        c2fb_temp_21 = Cast(Byte, Cast(SQLITE_C_INT, &H41ULL))
                        (*c2fb_temp_20) = c2fb_temp_21
                    End If
                    If sqlite3ExprNeedsNoAffinityChange(CPtr(Any Ptr, local12), CPtr(Byte Ptr, local9)[local6]) Then
                        c2fb_temp_22 = CPtr(Byte Ptr, @(CPtr(Byte Ptr, local9)[local6]))
                        c2fb_temp_23 = Cast(Byte, Cast(SQLITE_C_INT, &H41ULL))
                        (*c2fb_temp_22) = c2fb_temp_23
                    End If
                End If
            End If
        End If
    c2fb_flow_3:
        c2fb_temp_15 = local6
        local6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_15 + 1)))
    Wend
    c2fb_flow_2:
    c2fb_temp_24 = CPtr(ZString Ptr Ptr, @((*arg4)))
    c2fb_temp_25 = local9
    (*c2fb_temp_24) = c2fb_temp_25
    Return local7
End Function

Private Sub whereLikeOptimizationStringFixup CDecl Alias "whereLikeOptimizationStringFixup" (ByVal arg0 As SqliteVdbe Ptr, ByVal arg1 As SqliteWhereLevel Ptr, ByVal arg2 As SqliteWhereTerm Ptr)
    Dim local0 As SqliteVdbeOp Ptr
    Dim c2fb_temp_0 As SqliteVdbeOp Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As u16 Ptr
    Dim c2fb_temp_4 As UShort

    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2->wtFlags) And Cast(SQLITE_C_INT, &H0100ULL))) Then
        ' C automatic storage declaration
        ' C unused-parameter annotation
        c2fb_temp_0 = CPtr(SqliteVdbeOp Ptr, sqlite3VdbeGetLastOp(arg0))
        local0 = c2fb_temp_0
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        c2fb_temp_1 = CPtr(SQLITE_C_INT Ptr, @(local0->p3))
        c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, (arg1->iLikeRepCntr Shr Cast(SQLITE_C_INT, 1ULL))))))
        (*c2fb_temp_1) = c2fb_temp_2
        c2fb_temp_3 = CPtr(u16 Ptr, @(local0->p5))
        c2fb_temp_4 = Cast(UShort, Cast(UByte, (Cast(SQLITE_C_UINT, (arg1->iLikeRepCntr And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))))
        (*c2fb_temp_3) = Cast(u16, c2fb_temp_4)
        c2fb_temp_4 = Cast(UShort, (*c2fb_temp_3))
    End If
End Sub

Private Sub codeDeferredSeek CDecl Alias "codeDeferredSeek" (ByVal arg0 As SqliteWhereInfo Ptr, ByVal arg1 As SqliteIndex Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
    Dim local0 As SqliteParseContext Ptr
    Dim local1 As SqliteVdbe Ptr
    Dim c2fb_temp_0 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As SqliteTable Ptr
    Dim local4 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_2 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_3 As SQLITE_C_UINT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim local6 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_9 As SQLITE_C_UINT

    local0 = arg0->pParse
    local1 = CPtr(SqliteVdbe Ptr, local0->pVdbe)
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(SQLITE_C_UINT Ptr, @(arg0->flags))
    c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
    c2fb_temp_1 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_1) And Cast(SQLITE_C_UINT, &H1ULL)))
    (*c2fb_temp_0) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_0)) And Not(Cast(SQLITE_C_UINT, &H1ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_1) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 0)))
    c2fb_temp_1 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_1) And Cast(SQLITE_C_UINT, &H1ULL)))
    sqlite3VdbeAddOp3(local1, Cast(SQLITE_C_INT, 143ULL), arg3, Cast(SQLITE_C_INT, &O0ULL), arg2)
    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->wctrlFlags) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0020ULL) Or Cast(SQLITE_C_INT, &H1000ULL))))))) AndAlso ((-Cast(SQLITE_C_INT, ((((IIf((local0)->pToplevel, (local0)->pToplevel, (local0)))->writeMask) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
        ' C automatic storage declaration
        local3 = arg1->pTable
        local4 = CPtr(SQLITE_C_UINT Ptr, CPtr(Any Ptr, sqlite3DbMallocZero(CPtr(Any Ptr, local0->db), Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SQLITE_C_UINT))) * Cast(sqlite3_uint64, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local3->nCol) + Cast(SQLITE_C_INT, 1ULL))))))))))
        If local4 Then
            c2fb_temp_2 = CPtr(SQLITE_C_UINT Ptr, @(local4[Cast(SQLITE_C_INT, &O0ULL)]))
            c2fb_temp_3 = Cast(SQLITE_C_UINT, local3->nCol)
            (*c2fb_temp_2) = c2fb_temp_3
            c2fb_temp_4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local2 = c2fb_temp_4
            While (-Cast(SQLITE_C_INT, ((local2 < Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->nColumn) - Cast(SQLITE_C_INT, 1ULL)))))))
                ' C automatic storage declaration
                ' C automatic storage declaration
                ' C unused-parameter annotation
                c2fb_temp_6 = Cast(SQLITE_C_INT, arg1->aiColumn[local2])
                local5 = c2fb_temp_6
                c2fb_temp_7 = Cast(SQLITE_C_INT, sqlite3TableColumnToStorage(CPtr(Any Ptr, local3), local5))
                local6 = c2fb_temp_7
                ' empty C statement
                If (-Cast(SQLITE_C_INT, ((local5 >= Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_8 = CPtr(SQLITE_C_UINT Ptr, @(local4[Cast(SQLITE_C_INT, (local6 + Cast(SQLITE_C_INT, 1ULL)))]))
                    c2fb_temp_9 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (local2 + Cast(SQLITE_C_INT, 1ULL))))
                    (*c2fb_temp_8) = c2fb_temp_9
                End If
            c2fb_flow_1:
                c2fb_temp_5 = local2
                local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_5 + 1)))
            Wend
            c2fb_flow_0:
            sqlite3VdbeChangeP4(local1, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), CPtr(Const ZString Ptr, CPtr(ZString Ptr, local4)), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 13ULL)))))
        End If
    End If
End Sub

Private Sub codeExprOrVector CDecl Alias "codeExprOrVector" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT)
    Dim local0 As SqliteVdbe Ptr
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As Const SqliteExprList Ptr
    Dim c2fb_temp_1 As Const SqliteExprList Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT

    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((arg1 AndAlso sqlite3ExprIsVector(CPtr(Any Ptr, arg1)))))) Then
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            local0 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
            ' C automatic storage declaration
            ' C unused-parameter annotation
            c2fb_temp_0 = Cast(SQLITE_C_INT, sqlite3CodeSubselect(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1)))
            local1 = c2fb_temp_0
            sqlite3VdbeAddOp3(local0, Cast(SQLITE_C_INT, 82ULL), local1, arg2, Cast(SQLITE_C_INT, (arg3 - Cast(SQLITE_C_INT, 1ULL))))
        Else
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C unused-parameter annotation
            c2fb_temp_1 = CPtr(Const SqliteExprList Ptr, arg1->x.pList)
            local3 = c2fb_temp_1
            ' C unused-parameter annotation
            c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local2 = c2fb_temp_2
            While (-Cast(SQLITE_C_INT, ((local2 < arg3))))
                sqlite3ExprCode(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local3->a(local2).pExpr), Cast(SQLITE_C_INT, (arg2 + local2)))
            c2fb_flow_1:
                c2fb_temp_3 = local2
                local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_3 + 1)))
            Wend
            c2fb_flow_0:
        End If
    Else
        ' C unused-parameter annotation
        sqlite3ExprCode(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1), arg2)
    End If
End Sub

Private Sub whereApplyPartialIndexConstraints CDecl Alias "whereApplyPartialIndexConstraints" (ByVal arg0 As SqliteExpr Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteWhereClause Ptr)
    Dim local0 As SQLITE_C_INT
    Dim local1 As SqliteWhereTerm Ptr
    Dim c2fb_temp_0 As SqliteExpr Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SqliteWhereTerm Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SqliteWhereTerm Ptr
    Dim local2 As SqliteExpr Ptr
    Dim c2fb_temp_5 As SqliteExpr Ptr
    Dim c2fb_temp_6 As u16 Ptr
    Dim c2fb_temp_7 As UShort

    ' C automatic storage declaration
    ' C automatic storage declaration
    While (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->op) = Cast(SQLITE_C_INT, 44ULL)))))
        whereApplyPartialIndexConstraints(arg0->pLeft, arg1, arg2)
        c2fb_temp_0 = arg0->pRight
        arg0 = c2fb_temp_0
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_1
    c2fb_temp_2 = arg2->a
    local1 = c2fb_temp_2
    While (-Cast(SQLITE_C_INT, ((local0 < arg2->nTerm))))
        ' C automatic storage declaration
        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->wtFlags) And Cast(SQLITE_C_INT, &H0004ULL))) Then
            Goto c2fb_flow_3
        End If
        c2fb_temp_5 = local1->pExpr
        local2 = c2fb_temp_5
        If (-Cast(SQLITE_C_INT, ((sqlite3ExprCompare(Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, local2), CPtr(Any Ptr, arg0), arg1) = Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_6 = CPtr(u16 Ptr, @(local1->wtFlags))
            c2fb_temp_7 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_6))) Or Cast(SQLITE_C_INT, &H0004ULL))))
            (*c2fb_temp_6) = Cast(u16, c2fb_temp_7)
            c2fb_temp_7 = Cast(UShort, (*c2fb_temp_6))
        End If
    c2fb_flow_3:
        c2fb_temp_3 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_3 + 1)))
        c2fb_temp_4 = local1
        local1 = (c2fb_temp_4 + 1)
    Wend
    c2fb_flow_2:
End Sub

Private Sub filterPullDown CDecl Alias "filterPullDown" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteWhereInfo Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As sqlite3_uint64)
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local1 As SqliteWhereLevel Ptr
    Dim local2 As SqliteWhereLoop Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim local3 As SqliteWhereTerm Ptr
    Dim local4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim local5 As UShort
    Dim local6 As SQLITE_C_INT
    Dim local7 As ZString Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT Ptr
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT Ptr
    Dim c2fb_temp_11 As SQLITE_C_INT

    ' C automatic storage declaration
    Do
        c2fb_temp_0 = arg2
        arg2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_0 + 1)))
        c2fb_temp_1 = arg2
        If ((-Cast(SQLITE_C_INT, ((c2fb_temp_1 < Cast(SQLITE_C_INT, arg1->nLevel))))) = 0) Then Goto c2fb_flow_0
        local1 = CPtr(SqliteWhereLevel Ptr, @(arg1->a(arg2)))
        local2 = local1->pWLoop
        If (-Cast(SQLITE_C_INT, ((local1->regFilter = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_1
        End If
        If local1->pWLoop->nSkip Then
            Goto c2fb_flow_1
        End If
        If (Cast(sqlite3_uint64, (local2->prereq And arg4))) Then
            Goto c2fb_flow_1
        End If
        c2fb_temp_2 = Cast(SQLITE_C_INT, local1->addrBrk)
        local0 = c2fb_temp_2
        c2fb_temp_3 = CPtr(SQLITE_C_INT Ptr, @(local1->addrBrk))
        c2fb_temp_4 = Cast(SQLITE_C_INT, arg3)
        (*c2fb_temp_3) = c2fb_temp_4
        If Cast(SQLITE_C_UINT, (local2->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000100ULL)))) Then
            local3 = local2->aLTerm[Cast(SQLITE_C_INT, &O0ULL)]
            ' C automatic storage declaration
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' empty C statement
            c2fb_temp_5 = Cast(SQLITE_C_INT, sqlite3GetTempReg(CPtr(Any Ptr, arg0)))
            local4 = c2fb_temp_5
            c2fb_temp_6 = Cast(SQLITE_C_INT, codeEqualityTerm(arg0, local3, local1, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), local4))
            local4 = c2fb_temp_6
            sqlite3VdbeAddOp2(CPtr(SqliteVdbe Ptr, arg0->pVdbe), Cast(SQLITE_C_INT, 13ULL), local4, arg3)
            ' empty C statement
            ' C unused-parameter annotation
            sqlite3VdbeAddOp4Int(CPtr(SqliteVdbe Ptr, arg0->pVdbe), Cast(SQLITE_C_INT, 66ULL), local1->regFilter, arg3, local4, Cast(SQLITE_C_INT, 1ULL))
            ' empty C statement
        Else
            local5 = local2->u.btree.nEq
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            c2fb_temp_7 = Cast(SQLITE_C_INT, codeAllEqualityTerms(arg0, local1, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), CPtr(ZString Ptr Ptr, @(local7))))
            local6 = c2fb_temp_7
            codeApplyAffinity(arg0, local6, local5, local7)
            sqlite3DbFree(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, local7))
            ' C unused-parameter annotation
            sqlite3VdbeAddOp4Int(CPtr(SqliteVdbe Ptr, arg0->pVdbe), Cast(SQLITE_C_INT, 66ULL), local1->regFilter, arg3, local6, local5)
            ' empty C statement
        End If
        c2fb_temp_8 = CPtr(SQLITE_C_INT Ptr, @(local1->regFilter))
        c2fb_temp_9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_8) = c2fb_temp_9
        c2fb_temp_10 = CPtr(SQLITE_C_INT Ptr, @(local1->addrBrk))
        c2fb_temp_11 = Cast(SQLITE_C_INT, local0)
        (*c2fb_temp_10) = c2fb_temp_11
    c2fb_flow_1:
    Loop
    c2fb_flow_0:
End Sub

Private Function whereLoopIsOneRow CDecl Alias "whereLoopIsOneRow" (ByVal arg0 As SqliteWhereLoop Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT

    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(SqliteIndex Ptr, arg0->u.btree.pIndex)->onError) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->nSkip) = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->u.btree.nEq) = Cast(SQLITE_C_INT, CPtr(SqliteIndex Ptr, arg0->u.btree.pIndex)->nKeyCol))))))))) Then
        ' C automatic storage declaration
        c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local0 = c2fb_temp_0
        While (-Cast(SQLITE_C_INT, ((local0 < Cast(SQLITE_C_INT, arg0->u.btree.nEq)))))
            If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->aLTerm[local0]->eOperator) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0080ULL) Or Cast(SQLITE_C_INT, &H0100ULL)))))) Then
                Return Cast(SQLITE_C_INT, &O0ULL)
            End If
        c2fb_flow_1:
            c2fb_temp_1 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
        Wend
        c2fb_flow_0:
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function whereExprIsReady CDecl Alias "whereExprIsReady" (ByVal arg0 As SqliteWhereInfo Ptr, ByVal arg1 As SqliteWhereLevel Ptr, ByVal arg2 As SqliteSrcItem Ptr, ByVal arg3 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim local0 As UByte
    Dim local1 As sqlite3_uint64

    local0 = arg2->fg.jointype
    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H40ULL))) Or Cast(SQLITE_C_INT, &H10ULL)))))) Then
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg3)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000001ULL) Or Cast(SQLITE_C_INT, &H000002ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))) Then
            Return Cast(SQLITE_C_INT, &O0ULL)
        Else
            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0) And Cast(SQLITE_C_INT, &H08ULL)))) AndAlso (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg3)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000001ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))))))) Then
                Return Cast(SQLITE_C_INT, &O0ULL)
            Else
                local1 = sqlite3WhereGetMask(CPtr(SqliteWhereMaskSet Ptr, @(arg0->sMaskSet)), arg3->w.iJoin)
                If Cast(sqlite3_uint64, (local1 And arg1->notReady)) Then
                    Return Cast(SQLITE_C_INT, &O0ULL)
                End If
            End If
        End If
    End If
    Return Cast(SQLITE_C_INT, 1ULL)
End Function

Private Sub adjustOrderByCol CDecl Alias "adjustOrderByCol" (ByVal arg0 As SqliteExprList Ptr, ByVal arg1 As SqliteExprList Ptr)
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As UShort Ptr
    Dim c2fb_temp_5 As UShort
    Dim c2fb_temp_6 As UShort Ptr
    Dim c2fb_temp_7 As UShort

    ' C automatic storage declaration
    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, ((arg0 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return
    End If
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((local0 < arg0->nExpr))))
        local2 = arg0->a(local0).u.x.iOrderByCol
        If (-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_1
        End If
        c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local1 = c2fb_temp_2
        While (-Cast(SQLITE_C_INT, ((local1 < arg1->nExpr))))
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->a(local1).u.x.iOrderByCol) = local2)))) Then
                c2fb_temp_4 = @(arg0->a(local0).u.x.iOrderByCol)
                c2fb_temp_5 = Cast(UShort, Cast(SQLITE_C_INT, (local1 + Cast(SQLITE_C_INT, 1ULL))))
                (*c2fb_temp_4) = c2fb_temp_5
                Goto c2fb_flow_2
            End If
        c2fb_flow_3:
            c2fb_temp_3 = local1
            local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_3 + 1)))
        Wend
        c2fb_flow_2:
        If (-Cast(SQLITE_C_INT, ((local1 >= arg1->nExpr)))) Then
            c2fb_temp_6 = @(arg0->a(local0).u.x.iOrderByCol)
            c2fb_temp_7 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_6) = c2fb_temp_7
        End If
    c2fb_flow_1:
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    Wend
    c2fb_flow_0:
End Sub

Private Function removeUnindexableInClauseTerms CDecl Alias "removeUnindexableInClauseTerms" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteWhereLoop Ptr, ByVal arg3 As SqliteExpr Ptr) As SqliteExpr Ptr
    Dim local0 As sqlite3 Ptr
    Dim local1 As SqliteSelect Ptr
    Dim local2 As SqliteExpr Ptr
    Dim c2fb_temp_0 As SqliteExpr Ptr
    Dim c2fb_temp_1 As SqliteSelect Ptr
    Dim c2fb_temp_2 As SqliteSelect Ptr
    Dim local3 As SqliteExprList Ptr
    Dim local4 As SqliteExprList Ptr
    Dim local5 As SqliteExprList Ptr
    Dim local6 As SqliteExprList Ptr
    Dim local7 As SQLITE_C_INT
    Dim local8 As SQLITE_C_INT
    Dim c2fb_temp_3 As SqliteExprList Ptr
    Dim c2fb_temp_4 As SqliteExprList Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim local9 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As u32 Ptr
    Dim c2fb_temp_9 As SQLITE_C_UINT
    Dim c2fb_temp_10 As SqliteExprList Ptr
    Dim c2fb_temp_11 As Any Ptr Ptr
    Dim c2fb_temp_12 As SqliteExpr Ptr
    Dim c2fb_temp_13 As UShort Ptr
    Dim c2fb_temp_14 As UShort
    Dim c2fb_temp_15 As SqliteExprList Ptr
    Dim c2fb_temp_16 As Any Ptr Ptr
    Dim c2fb_temp_17 As SqliteExpr Ptr
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As Any Ptr Ptr
    Dim c2fb_temp_20 As SqliteExprList Ptr
    Dim c2fb_temp_21 As Any Ptr Ptr
    Dim c2fb_temp_22 As SqliteExprList Ptr
    Dim c2fb_temp_23 As SQLITE_C_INT Ptr
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As SQLITE_C_INT
    Dim c2fb_temp_26 As u32 Ptr
    Dim c2fb_temp_27 As SQLITE_C_UINT
    Dim local10 As SqliteExpr Ptr
    Dim c2fb_temp_28 As Any Ptr Ptr
    Dim c2fb_temp_29 As SqliteExpr Ptr
    Dim c2fb_temp_30 As Any Ptr Ptr
    Dim c2fb_temp_31 As SqliteExpr Ptr
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As SQLITE_C_INT
    Dim c2fb_temp_34 As UShort Ptr
    Dim c2fb_temp_35 As UShort

    local0 = arg0->db
    ' C automatic storage declaration
    ' C automatic storage declaration
    c2fb_temp_0 = CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local0), CPtr(Any Ptr, arg3), Cast(SQLITE_C_INT, &O0ULL)))
    local2 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->mallocFailed) = Cast(SQLITE_C_INT, &O0ULL))))) Then
        c2fb_temp_1 = CPtr(SqliteSelect Ptr, local2->x.pSelect)
        local1 = c2fb_temp_1
        While local1
            ' C automatic storage declaration
            local4 = Cast(SQLITE_C_INT, &O0ULL)
            local5 = Cast(SQLITE_C_INT, &O0ULL)
            local6 = Cast(SQLITE_C_INT, &O0ULL)
            ' C automatic storage declaration
            local8 = Cast(SQLITE_C_INT, &O0ULL)
            ' C unused-parameter annotation
            c2fb_temp_3 = CPtr(SqliteExprList Ptr, local1->pEList)
            local3 = c2fb_temp_3
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, ((local1 = CPtr(SqliteSelect Ptr, local2->x.pSelect))))) Then
                c2fb_temp_4 = CPtr(SqliteExprList Ptr, CPtr(SqliteExpr Ptr, local2->pLeft)->x.pList)
                local4 = c2fb_temp_4
            End If
            c2fb_temp_5 = Cast(SQLITE_C_INT, arg1)
            local7 = c2fb_temp_5
            While (-Cast(SQLITE_C_INT, ((local7 < Cast(SQLITE_C_INT, arg2->nLTerm)))))
                If (-Cast(SQLITE_C_INT, ((CPtr(SqliteExpr Ptr, CPtr(SqliteWhereTerm Ptr Ptr, arg2->aLTerm)[local7]->pExpr) = arg3)))) Then
                    ' C automatic storage declaration
                    ' C unused-parameter annotation
                    c2fb_temp_7 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (CPtr(SqliteWhereTerm Ptr Ptr, arg2->aLTerm)[local7]->u.x.iField - Cast(SQLITE_C_INT, 1ULL))))
                    local9 = c2fb_temp_7
                    If (-Cast(SQLITE_C_INT, ((local9 <> local8)))) Then
                        c2fb_temp_8 = @((local2)->flags)
                        c2fb_temp_9 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_8)) And Cast(SQLITE_C_UINT, (Not Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H2000000ULL))))))))
                        (*c2fb_temp_8) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_8)) And Cast(SQLITE_C_UINT, (Not Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H2000000ULL)))))))))
                        c2fb_temp_9 = Cast(SQLITE_C_UINT, (*c2fb_temp_8))
                    End If
                    If ((-Cast(SQLITE_C_INT, ((CPtr(SqliteExpr Ptr, local3->a(local9).pExpr) = Cast(SQLITE_C_INT, &O0ULL)))))) Then
                        Goto c2fb_flow_3
                    End If
                    c2fb_temp_10 = CPtr(SqliteExprList Ptr, sqlite3ExprListAppend(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local5), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local3->a(local9).pExpr))))
                    local5 = c2fb_temp_10
                    c2fb_temp_11 = @(local3->a(local9).pExpr)
                    c2fb_temp_12 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                    (*c2fb_temp_11) = CPtr(Any Ptr, CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
                    c2fb_temp_12 = CPtr(SqliteExpr Ptr, (*c2fb_temp_11))
                    If local5 Then
                        c2fb_temp_13 = @(local5->a(Cast(SQLITE_C_INT, (local5->nExpr - Cast(SQLITE_C_INT, 1ULL)))).u.x.iOrderByCol)
                        c2fb_temp_14 = Cast(UShort, Cast(SQLITE_C_INT, (local9 + Cast(SQLITE_C_INT, 1ULL))))
                        (*c2fb_temp_13) = c2fb_temp_14
                    End If
                    If local4 Then
                        ' C unused-parameter annotation
                        c2fb_temp_15 = CPtr(SqliteExprList Ptr, sqlite3ExprListAppend(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local6), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local4->a(local9).pExpr))))
                        local6 = c2fb_temp_15
                        c2fb_temp_16 = @(local4->a(local9).pExpr)
                        c2fb_temp_17 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                        (*c2fb_temp_16) = CPtr(Any Ptr, CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
                        c2fb_temp_17 = CPtr(SqliteExpr Ptr, (*c2fb_temp_16))
                    End If
                    c2fb_temp_18 = local8
                    local8 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_18 + 1)))
                End If
            c2fb_flow_3:
                c2fb_temp_6 = local7
                local7 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 + 1)))
            Wend
            c2fb_flow_2:
            sqlite3ExprListDelete(CPtr(Any Ptr, local0), CPtr(Any Ptr, local3))
            If local4 Then
                sqlite3ExprListDelete(CPtr(Any Ptr, local0), CPtr(Any Ptr, local4))
                c2fb_temp_19 = @(CPtr(SqliteExpr Ptr, local2->pLeft)->x.pList)
                c2fb_temp_20 = local6
                (*c2fb_temp_19) = CPtr(Any Ptr, local6)
                c2fb_temp_20 = CPtr(SqliteExprList Ptr, (*c2fb_temp_19))
            End If
            c2fb_temp_21 = @(local1->pEList)
            c2fb_temp_22 = local5
            (*c2fb_temp_21) = CPtr(Any Ptr, local5)
            c2fb_temp_22 = CPtr(SqliteExprList Ptr, (*c2fb_temp_21))
            c2fb_temp_26 = @(local1->selId)
            c2fb_temp_23 = @(arg0->nSelect)
            c2fb_temp_24 = (*c2fb_temp_23)
            (*c2fb_temp_23) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_24 + 1)))
            c2fb_temp_25 = (*c2fb_temp_23)
            c2fb_temp_27 = Cast(SQLITE_C_UINT, c2fb_temp_25)
            (*c2fb_temp_26) = Cast(u32, Cast(SQLITE_C_UINT, c2fb_temp_25))
            c2fb_temp_27 = Cast(SQLITE_C_UINT, (*c2fb_temp_26))
            If (-Cast(SQLITE_C_INT, ((local6 AndAlso (-Cast(SQLITE_C_INT, ((local6->nExpr = Cast(SQLITE_C_INT, 1ULL))))))))) Then
                local10 = CPtr(SqliteExpr Ptr, local6->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr)
                c2fb_temp_28 = @(local6->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr)
                c2fb_temp_29 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                (*c2fb_temp_28) = CPtr(Any Ptr, CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))))
                c2fb_temp_29 = CPtr(SqliteExpr Ptr, (*c2fb_temp_28))
                sqlite3ExprDelete(CPtr(Any Ptr, local0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local2->pLeft)))
                c2fb_temp_30 = @(local2->pLeft)
                c2fb_temp_31 = local10
                (*c2fb_temp_30) = CPtr(Any Ptr, local10)
                c2fb_temp_31 = CPtr(SqliteExpr Ptr, (*c2fb_temp_30))
            End If
            ' C unused-parameter annotation
            If local5 Then
                adjustOrderByCol(CPtr(SqliteExprList Ptr, local1->pOrderBy), local5)
                adjustOrderByCol(CPtr(SqliteExprList Ptr, local1->pGroupBy), local5)
                c2fb_temp_32 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local7 = c2fb_temp_32
                While (-Cast(SQLITE_C_INT, ((local7 < local5->nExpr))))
                    c2fb_temp_34 = @(local5->a(local7).u.x.iOrderByCol)
                    c2fb_temp_35 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
                    (*c2fb_temp_34) = c2fb_temp_35
                c2fb_flow_5:
                    c2fb_temp_33 = local7
                    local7 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_33 + 1)))
                Wend
                c2fb_flow_4:
            End If
        c2fb_flow_1:
            c2fb_temp_2 = CPtr(SqliteSelect Ptr, local1->pPrior)
            local1 = c2fb_temp_2
        Wend
        c2fb_flow_0:
    End If
    Return local2
End Function

#ifndef SQLITE_OMIT_SUBQUERY
Private Sub codeINTerm CDecl Alias "codeINTerm" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pTerm As SqliteWhereTerm Ptr, _
    ByVal pLevel As SqliteWhereLevel Ptr, _
    ByVal equalityIndex As SQLITE_C_INT, _
    ByVal reverseOrder As SQLITE_C_INT, _
    ByVal targetRegister As SQLITE_C_INT _
)
    If pParse = 0 OrElse pParse->db = 0 OrElse pTerm = 0 OrElse _
       pTerm->pExpr = 0 OrElse pLevel = 0 OrElse pLevel->pWLoop = 0 OrElse _
       pParse->pVdbe = 0 OrElse targetRegister <= 0 Then Return

    Dim pExpression As SqliteExpr Ptr = pTerm->pExpr
    Dim pLoop As SqliteWhereLoop Ptr = pLevel->pWLoop
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pParse->pVdbe)
    If pExpression->op <> TK_IN OrElse equalityIndex < 0 OrElse _
       equalityIndex >= pLoop->nLTerm Then Return

    Dim indexType As SQLITE_C_INT = IN_INDEX_NOOP
    Dim indexCursor As SQLITE_C_INT = 0
    Dim equalityCount As SQLITE_C_INT = 0
    Dim registerMap As SQLITE_C_INT Ptr = 0
    Dim isReverse As SQLITE_C_INT = IIf(reverseOrder <> 0, 1, 0)
    Dim pIndex As SqliteIndex Ptr = CPtr(SqliteIndex Ptr, pLoop->u.btree.pIndex)

    If (pLoop->wsFlags And WHERE_VIRTUALTABLE) = 0 AndAlso _
       pIndex <> 0 AndAlso pIndex->aSortOrder <> 0 AndAlso _
       equalityIndex < pIndex->nKeyCol AndAlso _
       pIndex->aSortOrder[equalityIndex] <> 0 Then
        isReverse = IIf(isReverse = 0, 1, 0)
    End If

    For termIndex As SQLITE_C_INT = 0 To equalityIndex - 1
        Dim pEarlierTerm As SqliteWhereTerm Ptr = pLoop->aLTerm[termIndex]
        If pEarlierTerm <> 0 AndAlso pEarlierTerm->pExpr = pExpression Then
            disableTerm(pLevel, pTerm)
            Return
        End If
    Next

    For termIndex As SQLITE_C_INT = equalityIndex To pLoop->nLTerm - 1
        Dim pCurrentTerm As SqliteWhereTerm Ptr = pLoop->aLTerm[termIndex]
        If pCurrentTerm = 0 Then Return
        If pCurrentTerm->pExpr = pExpression Then equalityCount += 1
    Next

    If (pExpression->flags And EP_xIsSelect) = 0 OrElse _
       pExpression->x.pSelect = 0 OrElse _
       pExpression->x.pSelect->pEList = 0 OrElse _
       pExpression->x.pSelect->pEList->nExpr = 1 Then
        indexType = sqlite3FindInIndex( _
            pParse, pExpression, IN_INDEX_LOOP, 0, 0, @indexCursor)
    Else
        Dim db As sqlite3 Ptr = pParse->db
        Dim pModifiedExpression As SqliteExpr Ptr = _
            removeUnindexableInClauseTerms(pParse, equalityIndex, pLoop, pExpression)
        If equalityCount > 1 Then _
            pLoop->wsFlags And= Not CUInt(WHERE_IN_SEEKSCAN)
        If db->mallocFailed = 0 Then
            Dim nColumn As SQLITE_C_INT = pExpression->x.pSelect->pEList->nExpr
            If nColumn > 0 AndAlso _
               CULngInt(nColumn) <= &HFFFFFFFFFFFFFFFFULL \ SizeOf(SQLITE_C_INT) Then
                registerMap = CPtr(SQLITE_C_INT Ptr, _
                    sqlite3DbMallocZero(db, CULngInt(SizeOf(SQLITE_C_INT)) * nColumn))
            End If
            indexType = sqlite3FindInIndex( _
                pParse, pModifiedExpression, IN_INDEX_LOOP, 0, _
                registerMap, @indexCursor)
        End If
        sqlite3ExprDelete(db, pModifiedExpression)
    End If

    If indexType = IN_INDEX_INDEX_DESC Then _
        isReverse = IIf(isReverse = 0, 1, 0)
    sqlite3VdbeAddOp2(pVdbe, _
        IIf(isReverse <> 0, OP_Last, OP_Rewind), indexCursor, 0)

    pLoop->wsFlags Or= WHERE_IN_ABLE
    If pLevel->u.in.nIn = 0 Then _
        pLevel->addrNxt = sqlite3VdbeMakeLabel(pParse)
    If equalityIndex > 0 AndAlso _
       (pLoop->wsFlags And WHERE_IN_SEEKSCAN) = 0 Then _
        pLoop->wsFlags Or= WHERE_IN_EARLYOUT

    Dim oldInCount As SQLITE_C_INT = pLevel->u.in.nIn
    If oldInCount < 0 OrElse equalityCount < 0 OrElse _
       oldInCount > 2147483647 - equalityCount Then
        pLevel->u.in.nIn = 0
        sqlite3OomFault(pParse->db)
        sqlite3DbFree(pParse->db, registerMap)
        Return
    End If
    Dim newInCount As SQLITE_C_INT = oldInCount + equalityCount
    pLevel->u.in.nIn = newInCount
    If CULngInt(newInCount) > _
       &HFFFFFFFFFFFFFFFFULL \ SizeOf(SqliteInLoop) Then
        pLevel->u.in.nIn = 0
        sqlite3OomFault(pParse->db)
        sqlite3DbFree(pParse->db, registerMap)
        Return
    End If
    ' WhereInfo owns replacement blocks until the complete plan is released.
    pLevel->u.in.aInLoop = CPtr(SqliteInLoop Ptr, _
        sqlite3WhereRealloc(pTerm->pWC->pWInfo, pLevel->u.in.aInLoop, _
            CULngInt(SizeOf(SqliteInLoop)) * newInCount))
    Dim pInLoops As SqliteInLoop Ptr = pLevel->u.in.aInLoop
    If pInLoops <> 0 Then
        Dim mapIndex As SQLITE_C_INT = 0
        Dim inLoopIndex As SQLITE_C_INT = oldInCount
        For termIndex As SQLITE_C_INT = equalityIndex To pLoop->nLTerm - 1
            Dim pCurrentTerm As SqliteWhereTerm Ptr = pLoop->aLTerm[termIndex]
            If pCurrentTerm->pExpr = pExpression Then
                Dim pInLoop As SqliteInLoop Ptr = @pInLoops[inLoopIndex]
                Dim outputRegister As SQLITE_C_INT = _
                    targetRegister + termIndex - equalityIndex
                If indexType = IN_INDEX_ROWID Then
                    pInLoop->addrInTop = sqlite3VdbeAddOp2( _
                        pVdbe, OP_Rowid, indexCursor, outputRegister)
                Else
                    Dim columnIndex As SQLITE_C_INT = 0
                    If registerMap <> 0 Then
                        columnIndex = registerMap[mapIndex]
                        mapIndex += 1
                    End If
                    pInLoop->addrInTop = sqlite3VdbeAddOp3( _
                        pVdbe, OP_Column, indexCursor, columnIndex, outputRegister)
                End If
                sqlite3VdbeAddOp1(pVdbe, OP_IsNull, outputRegister)
                If termIndex = equalityIndex Then
                    pInLoop->iCur = indexCursor
                    pInLoop->eEndLoopOp = IIf(isReverse <> 0, OP_Prev, OP_Next)
                    If equalityIndex > 0 Then
                        pInLoop->iBase = targetRegister - termIndex
                        pInLoop->nPrefix = termIndex
                    Else
                        pInLoop->nPrefix = 0
                    End If
                Else
                    pInLoop->eEndLoopOp = OP_Noop
                End If
                inLoopIndex += 1
            End If
        Next

        If equalityIndex > 0 AndAlso _
           (pLoop->wsFlags And (WHERE_IN_SEEKSCAN Or WHERE_VIRTUALTABLE)) = 0 Then
            sqlite3VdbeAddOp3( _
                pVdbe, OP_SeekHit, pLevel->iIdxCur, 0, equalityIndex)
        End If
    Else
        pLevel->u.in.nIn = 0
    End If
    sqlite3DbFree(pParse->db, registerMap)
End Sub
#endif

Function sqlite3WhereCodeOneLoopStart CDecl Alias "sqlite3WhereCodeOneLoopStart" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteVdbe Ptr, ByVal arg2 As SqliteWhereInfo Ptr, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SqliteWhereLevel Ptr, ByVal arg5 As sqlite3_uint64) As sqlite3_uint64
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As SqliteWhereLoop Ptr
    Dim local6 As SqliteWhereClause Ptr
    Dim local7 As SqliteWhereTerm Ptr
    Dim local8 As sqlite3 Ptr
    Dim local9 As SqliteSrcItem Ptr
    Dim local10 As SQLITE_C_INT
    Dim local11 As SQLITE_C_INT
    Dim local12 As SQLITE_C_INT
    Dim local13 As SQLITE_C_INT
    Dim local14 As SqliteIndex Ptr
    Dim local15 As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteWhereClause Ptr
    Dim c2fb_temp_1 As sqlite3 Ptr
    Dim c2fb_temp_2 As SqliteWhereLoop Ptr
    Dim c2fb_temp_3 As SqliteSrcItem Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As sqlite3_uint64 Ptr
    Dim c2fb_temp_6 As sqlite3_uint64
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT Ptr
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT Ptr
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT Ptr
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SQLITE_C_INT Ptr
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim local16 As SQLITE_C_INT
    Dim local17 As SqliteSubquery Ptr
    Dim c2fb_temp_19 As SqliteSubquery Ptr
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As SQLITE_C_INT Ptr
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim c2fb_temp_23 As u8 Ptr
    Dim c2fb_temp_24 As UByte
    Dim local18 As SQLITE_C_INT
    Dim local19 As SQLITE_C_INT
    Dim local20 As SQLITE_C_INT
    Dim c2fb_temp_25 As SQLITE_C_INT
    Dim c2fb_temp_26 As SQLITE_C_INT
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim c2fb_temp_28 As SQLITE_C_INT
    Dim local21 As SQLITE_C_INT
    Dim c2fb_temp_29 As SqliteWhereTerm Ptr
    Dim c2fb_temp_30 As SQLITE_C_INT Ptr
    Dim c2fb_temp_31 As SQLITE_C_INT
    Dim local22 As SQLITE_C_INT
    Dim c2fb_temp_32 As SQLITE_C_INT Ptr
    Dim c2fb_temp_33 As SQLITE_C_INT
    Dim c2fb_temp_34 As SQLITE_C_INT
    Dim local23 As SQLITE_C_INT
    Dim c2fb_temp_35 As SQLITE_C_INT
    Dim local24 As SqliteExpr Ptr
    Dim c2fb_temp_36 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_37 As SQLITE_C_INT
    Dim c2fb_temp_38 As Any Ptr Ptr
    Dim c2fb_temp_39 As ZString Ptr
    Dim c2fb_temp_40 As SQLITE_C_INT Ptr
    Dim c2fb_temp_41 As SQLITE_C_INT
    Dim c2fb_temp_42 As u8 Ptr
    Dim c2fb_temp_43 As UByte
    Dim c2fb_temp_44 As SQLITE_C_INT Ptr
    Dim c2fb_temp_45 As SQLITE_C_INT
    Dim c2fb_temp_46 As SQLITE_C_INT
    Dim c2fb_temp_47 As SQLITE_C_INT
    Dim c2fb_temp_48 As SqliteWhereTerm Ptr
    Dim local25 As SqliteExpr Ptr
    Dim local26 As SqliteExpr Ptr
    Dim local27 As SqliteVdbeOp Ptr
    Dim local28 As SQLITE_C_INT
    Dim c2fb_temp_49 As SQLITE_C_INT
    Dim c2fb_temp_50 As SQLITE_C_INT
    Dim c2fb_temp_51 As SqliteVdbeOp Ptr
    Dim c2fb_temp_52 As SqliteExpr Ptr
    Dim local29 As SQLITE_C_INT
    Dim local30 As SqliteExpr Ptr
    Dim c2fb_temp_53 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_54 As SqliteExpr Ptr
    Dim c2fb_temp_55 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_56 As SqliteExpr Ptr
    Dim c2fb_temp_57 As SqliteExpr Ptr
    Dim c2fb_temp_58 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_59 As SqliteExpr Ptr
    Dim c2fb_temp_60 As SQLITE_C_INT Ptr
    Dim c2fb_temp_61 As SQLITE_C_INT
    Dim c2fb_temp_62 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_63 As SqliteExpr Ptr
    Dim c2fb_temp_64 As SqliteWhereTerm Ptr
    Dim c2fb_temp_65 As SQLITE_C_INT Ptr
    Dim c2fb_temp_66 As SQLITE_C_INT
    Dim c2fb_temp_67 As SQLITE_C_INT
    Dim c2fb_temp_68 As SQLITE_C_INT
    Dim c2fb_temp_69 As SQLITE_C_INT
    Dim c2fb_temp_70 As SQLITE_C_INT
    Dim c2fb_temp_71 As u8 Ptr
    Dim c2fb_temp_72 As UByte
    Dim local31 As SQLITE_C_INT
    Dim local32 As SQLITE_C_INT
    Dim local33 As SQLITE_C_INT
    Dim local34 As SqliteWhereTerm Ptr
    Dim local35 As SqliteWhereTerm Ptr
    Dim c2fb_temp_73 As SQLITE_C_INT
    Dim c2fb_temp_74 As SqliteWhereTerm Ptr
    Dim c2fb_temp_75 As SqliteWhereTerm Ptr
    Dim c2fb_temp_76 As SQLITE_C_INT
    Dim c2fb_temp_77 As SqliteWhereTerm Ptr
    Dim c2fb_temp_78 As SQLITE_C_INT
    Dim c2fb_temp_79 As SqliteWhereTerm Ptr
    Dim c2fb_temp_80 As SqliteWhereTerm Ptr
    Dim c2fb_temp_81 As SqliteWhereTerm Ptr
    Dim c2fb_temp_82 As SqliteWhereTerm Ptr
    Dim local36 As SqliteExpr Ptr
    Dim local37 As SQLITE_C_INT
    Dim local38 As SQLITE_C_INT
    Dim local39 As SQLITE_C_INT
    Dim local40(0 To 3) As UByte
    Dim c2fb_temp_83 As SqliteExpr Ptr
    Dim c2fb_temp_84 As SQLITE_C_INT
    Dim c2fb_temp_85 As SQLITE_C_INT
    Dim c2fb_temp_86 As SQLITE_C_INT
    Dim c2fb_temp_87 As SQLITE_C_INT
    Dim c2fb_temp_88 As SQLITE_C_INT
    Dim local41 As SqliteExpr Ptr
    Dim c2fb_temp_89 As SqliteExpr Ptr
    Dim c2fb_temp_90 As SQLITE_C_INT Ptr
    Dim c2fb_temp_91 As SQLITE_C_INT
    Dim c2fb_temp_92 As SQLITE_C_INT
    Dim c2fb_temp_93 As SQLITE_C_INT
    Dim c2fb_temp_94 As SQLITE_C_INT
    Dim c2fb_temp_95 As SQLITE_C_INT
    Dim c2fb_temp_96 As SQLITE_C_INT
    Dim c2fb_temp_97 As u8 Ptr
    Dim c2fb_temp_98 As UByte
    Dim c2fb_temp_99 As SQLITE_C_INT Ptr
    Dim c2fb_temp_100 As SQLITE_C_INT
    Dim c2fb_temp_101 As SQLITE_C_INT Ptr
    Dim c2fb_temp_102 As SQLITE_C_INT
    Dim c2fb_temp_103 As SQLITE_C_INT Ptr
    Dim c2fb_temp_104 As SQLITE_C_INT
    Dim c2fb_temp_105 As SQLITE_C_INT
    Dim c2fb_temp_106 As SQLITE_C_INT
    Static local42(0 To 7) As UByte = {Cast(UByte, Cast(SQLITE_C_INT, &O0ULL)), Cast(UByte, Cast(SQLITE_C_INT, &O0ULL)), Cast(UByte, Cast(SQLITE_C_INT, 36ULL)), Cast(UByte, Cast(SQLITE_C_INT, 32ULL)), Cast(UByte, Cast(SQLITE_C_INT, 24ULL)), Cast(UByte, Cast(SQLITE_C_INT, 21ULL)), Cast(UByte, Cast(SQLITE_C_INT, 23ULL)), Cast(UByte, Cast(SQLITE_C_INT, 22ULL))}
    Static local43(0 To 3) As UByte = {Cast(UByte, Cast(SQLITE_C_INT, 46ULL)), Cast(UByte, Cast(SQLITE_C_INT, 42ULL)), Cast(UByte, Cast(SQLITE_C_INT, 41ULL)), Cast(UByte, Cast(SQLITE_C_INT, 45ULL))}
    Dim local44 As UShort
    Dim local45 As UShort
    Dim local46 As UShort
    Dim local47 As SQLITE_C_INT
    Dim local48 As SqliteWhereTerm Ptr
    Dim local49 As SqliteWhereTerm Ptr
    Dim local50 As SQLITE_C_INT
    Dim local51 As SQLITE_C_INT
    Dim local52 As SQLITE_C_INT
    Dim local53 As SQLITE_C_INT
    Dim local54 As SQLITE_C_INT
    Dim local55 As SQLITE_C_INT
    Dim local56 As SQLITE_C_INT
    Dim local57 As ZString Ptr
    Dim local58 As ZString Ptr
    Dim local59 As UByte
    Dim local60 As UByte
    Dim local61 As SQLITE_C_INT
    Dim local62 As SQLITE_C_INT
    Dim local63 As SQLITE_C_INT
    Dim c2fb_temp_107 As SqliteIndex Ptr
    Dim c2fb_temp_108 As SQLITE_C_INT
    Dim c2fb_temp_109 As SQLITE_C_INT
    Dim c2fb_temp_110 As SQLITE_C_INT
    Dim c2fb_temp_111 As SqliteWhereTerm Ptr
    Dim c2fb_temp_112 As SQLITE_C_INT
    Dim c2fb_temp_113 As SQLITE_C_INT
    Dim c2fb_temp_114 As SqliteWhereTerm Ptr
    Dim c2fb_temp_115 As SQLITE_C_INT
    Dim c2fb_temp_116 As SQLITE_C_INT Ptr
    Dim c2fb_temp_117 As SQLITE_C_INT
    Dim c2fb_temp_118 As SQLITE_C_INT
    Dim c2fb_temp_119 As u32 Ptr
    Dim c2fb_temp_120 As SQLITE_C_UINT
    Dim c2fb_temp_121 As SQLITE_C_INT Ptr
    Dim c2fb_temp_122 As SQLITE_C_INT
    Dim c2fb_temp_123 As u32 Ptr
    Dim c2fb_temp_124 As SQLITE_C_UINT
    Dim c2fb_temp_125 As u32 Ptr
    Dim c2fb_temp_126 As SQLITE_C_UINT
    Dim c2fb_temp_127 As SQLITE_C_INT
    Dim c2fb_temp_128 As UByte
    Dim c2fb_temp_129 As SQLITE_C_INT
    Dim c2fb_temp_130 As UByte
    Dim c2fb_temp_131 As SQLITE_C_INT Ptr
    Dim c2fb_temp_132 As SQLITE_C_INT
    Dim c2fb_temp_133 As SQLITE_C_INT
    Dim c2fb_temp_134 As SQLITE_C_INT
    Dim c2fb_temp_135 As SQLITE_C_INT Ptr
    Dim c2fb_temp_136 As SQLITE_C_INT
    Dim c2fb_temp_137 As SQLITE_C_INT Ptr
    Dim c2fb_temp_138 As SQLITE_C_INT
    Dim local64 As SqliteWhereTerm Ptr
    Dim c2fb_temp_139 As SqliteWhereTerm Ptr
    Dim c2fb_temp_140 As SqliteWhereTerm Ptr
    Dim local65 As UByte
    Dim c2fb_temp_141 As UByte
    Dim c2fb_temp_142 As UByte
    Dim local66 As UByte
    Dim c2fb_temp_143 As UShort
    Dim c2fb_temp_144 As UShort
    Dim c2fb_temp_145 As SQLITE_C_INT
    Dim c2fb_temp_146 As ZString Ptr
    Dim c2fb_temp_147 As SQLITE_C_INT
    Dim c2fb_temp_148 As SQLITE_C_INT
    Dim c2fb_temp_149 As SQLITE_C_INT
    Dim c2fb_temp_150 As SQLITE_C_INT
    Dim c2fb_temp_151 As SQLITE_C_INT
    Dim local67 As SqliteExpr Ptr
    Dim c2fb_temp_152 As SQLITE_C_INT
    Dim c2fb_temp_153 As SQLITE_C_INT
    Dim c2fb_temp_154 As UByte
    Dim c2fb_temp_155 As SQLITE_C_INT
    Dim c2fb_temp_156 As SQLITE_C_INT
    Dim c2fb_temp_157 As SQLITE_C_INT
    Dim c2fb_temp_158 As SQLITE_C_INT
    Dim c2fb_temp_159 As SQLITE_C_INT
    Dim c2fb_temp_160 As SQLITE_C_INT
    Dim c2fb_temp_161 As SQLITE_C_INT
    Dim c2fb_temp_162 As SQLITE_C_INT
    Dim c2fb_temp_163 As SQLITE_C_INT
    Dim c2fb_temp_164 As SQLITE_C_INT
    Dim local68 As SqliteExpr Ptr
    Dim c2fb_temp_165 As SQLITE_C_INT
    Dim c2fb_temp_166 As SQLITE_C_INT
    Dim c2fb_temp_167 As SQLITE_C_INT
    Dim c2fb_temp_168 As SQLITE_C_INT
    Dim c2fb_temp_169 As SQLITE_C_INT Ptr
    Dim c2fb_temp_170 As SQLITE_C_INT
    Dim c2fb_temp_171 As SQLITE_C_INT
    Dim c2fb_temp_172 As SQLITE_C_INT
    Dim c2fb_temp_173 As SQLITE_C_INT
    Dim local69 As SqliteIndex Ptr
    Dim c2fb_temp_174 As SQLITE_C_INT
    Dim c2fb_temp_175 As SQLITE_C_INT
    Dim c2fb_temp_176 As SQLITE_C_INT
    Dim c2fb_temp_177 As SQLITE_C_INT
    Dim c2fb_temp_178 As u8 Ptr
    Dim c2fb_temp_179 As UByte
    Dim c2fb_temp_180 As u8 Ptr
    Dim c2fb_temp_181 As UByte
    Dim c2fb_temp_182 As u8 Ptr
    Dim c2fb_temp_183 As UByte
    Dim c2fb_temp_184 As SQLITE_C_INT Ptr
    Dim c2fb_temp_185 As SQLITE_C_INT
    Dim c2fb_temp_186 As u8 Ptr
    Dim c2fb_temp_187 As UByte
    Dim c2fb_temp_188 As u8 Ptr
    Dim c2fb_temp_189 As UByte
    Dim c2fb_temp_190 As SqliteIndex Ptr
    Dim local70 As SqliteWhereClause Ptr
    Dim local71 As SqliteSrcList Ptr
    Dim local72 As SqliteIndex Ptr
    Dim c2fb_temp_191 As SQLITE_C_INT Ptr
    Dim c2fb_temp_192 As SQLITE_C_INT
    Dim local73 As SQLITE_C_INT
    Dim c2fb_temp_193 As SQLITE_C_INT Ptr
    Dim c2fb_temp_194 As SQLITE_C_INT
    Dim c2fb_temp_195 As SQLITE_C_INT
    Dim local74 As SQLITE_C_INT
    Dim local75 As SQLITE_C_INT
    Dim local76 As SQLITE_C_INT
    Dim local77 As SQLITE_C_INT
    Dim local78 As SQLITE_C_INT
    Dim local79 As SQLITE_C_INT
    Dim local80 As SQLITE_C_INT
    Dim local81 As SqliteExpr Ptr
    Dim local82 As SqliteTable Ptr
    Dim c2fb_temp_196 As SqliteWhereTerm Ptr
    Dim c2fb_temp_197 As SqliteWhereClause Ptr
    Dim c2fb_temp_198 As u8 Ptr
    Dim c2fb_temp_199 As UByte
    Dim c2fb_temp_200 As SQLITE_C_INT Ptr
    Dim c2fb_temp_201 As SQLITE_C_INT
    Dim local83 As SQLITE_C_INT
    Dim local84 As SqliteSrcItem Ptr
    Dim c2fb_temp_202 As SQLITE_C_INT
    Dim c2fb_temp_203 As SqliteSrcList Ptr
    Dim c2fb_temp_204 As u32 Ptr
    Dim c2fb_temp_205 As SQLITE_C_UINT
    Dim c2fb_temp_206 As SQLITE_C_INT Ptr
    Dim c2fb_temp_207 As SQLITE_C_INT
    Dim c2fb_temp_208 As Any Ptr
    Dim c2fb_temp_209 As SqliteSrcItem Ptr
    Dim c2fb_temp_210 As SQLITE_C_INT
    Dim c2fb_temp_211 As SQLITE_C_INT
    Dim c2fb_temp_212 As Any Ptr
    Dim c2fb_temp_213 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_214 As SQLITE_C_INT
    Dim c2fb_temp_215 As SqliteSrcList Ptr
    Dim c2fb_temp_216 As SQLITE_C_INT Ptr
    Dim c2fb_temp_217 As SQLITE_C_INT
    Dim c2fb_temp_218 As SQLITE_C_INT
    Dim c2fb_temp_219 As SQLITE_C_INT
    Dim local85 As SqliteIndex Ptr
    Dim c2fb_temp_220 As SQLITE_C_INT Ptr
    Dim c2fb_temp_221 As SQLITE_C_INT
    Dim c2fb_temp_222 As SQLITE_C_INT
    Dim c2fb_temp_223 As SQLITE_C_INT Ptr
    Dim c2fb_temp_224 As SQLITE_C_INT
    Dim c2fb_temp_225 As SQLITE_C_INT
    Dim c2fb_temp_226 As SQLITE_C_INT
    Dim c2fb_temp_227 As SQLITE_C_INT
    Dim local86 As SQLITE_C_INT
    Dim c2fb_temp_228 As SQLITE_C_INT
    Dim c2fb_temp_229 As SQLITE_C_INT
    Dim local87 As SqliteExpr Ptr
    Dim c2fb_temp_230 As SqliteExpr Ptr
    Dim c2fb_temp_231 As SqliteExpr Ptr
    Dim c2fb_temp_232 As SqliteExpr Ptr
    Dim c2fb_temp_233 As SQLITE_C_INT
    Dim c2fb_temp_234 As SQLITE_C_INT
    Dim local88 As SqliteWhereTerm Ptr
    Dim local89 As SqliteWhereInfo Ptr
    Dim local90 As SqliteExpr Ptr
    Dim local91 As SqliteExpr Ptr
    Dim local92 As SQLITE_C_INT
    Dim c2fb_temp_235 As SqliteExpr Ptr
    Dim c2fb_temp_236 As SqliteExpr Ptr
    Dim c2fb_temp_237 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_238 As SqliteExpr Ptr
    Dim c2fb_temp_239 As SqliteExpr Ptr
    Dim c2fb_temp_240 As SqliteWhereInfo Ptr
    Dim local93 As SqliteWhereLoop Ptr
    Dim local94 As SQLITE_C_INT
    Dim local95 As SQLITE_C_INT
    Dim c2fb_temp_241 As SQLITE_C_INT
    Dim local96 As SqliteIndex Ptr
    Dim local97 As SQLITE_C_INT
    Dim local98 As SQLITE_C_INT
    Dim local99 As SQLITE_C_INT
    Dim c2fb_temp_242 As SQLITE_C_INT
    Dim c2fb_temp_243 As SQLITE_C_INT
    Dim c2fb_temp_244 As SQLITE_C_INT
    Dim local100 As SQLITE_C_INT
    Dim c2fb_temp_245 As SQLITE_C_INT
    Dim c2fb_temp_246 As SQLITE_C_INT
    Dim c2fb_temp_247 As SqliteWhereLoop Ptr
    Dim c2fb_temp_248 As SqliteIndex Ptr
    Dim c2fb_temp_249 As SqliteIndex Ptr
    Dim c2fb_temp_250 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_251 As SQLITE_C_INT
    Dim c2fb_temp_252 As Any Ptr Ptr
    Dim c2fb_temp_253 As SqliteIndex Ptr
    Dim c2fb_temp_254 As SQLITE_C_INT Ptr
    Dim c2fb_temp_255 As SQLITE_C_INT
    Dim c2fb_temp_256 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_257 As SqliteExpr Ptr
    Dim c2fb_temp_258 As SQLITE_C_INT Ptr
    Dim c2fb_temp_259 As SQLITE_C_INT
    Static local101(0 To 1) As UByte = {Cast(UByte, Cast(SQLITE_C_INT, 40ULL)), Cast(UByte, Cast(SQLITE_C_INT, 39ULL))}
    Static local102(0 To 1) As UByte = {Cast(UByte, Cast(SQLITE_C_INT, 36ULL)), Cast(UByte, Cast(SQLITE_C_INT, 32ULL))}
    Dim c2fb_temp_260 As u8 Ptr
    Dim c2fb_temp_261 As UByte
    Dim c2fb_temp_262 As u8 Ptr
    Dim c2fb_temp_263 As UByte
    Dim c2fb_temp_264 As SQLITE_C_INT Ptr
    Dim c2fb_temp_265 As SQLITE_C_INT
    Dim c2fb_temp_266 As SQLITE_C_INT Ptr
    Dim c2fb_temp_267 As SQLITE_C_INT
    Dim c2fb_temp_268 As u8 Ptr
    Dim c2fb_temp_269 As UByte
    Dim c2fb_temp_270 As SQLITE_C_INT
    Dim local103 As SQLITE_C_INT
    Dim c2fb_temp_271 As SqliteWhereTerm Ptr
    Dim c2fb_temp_272 As SQLITE_C_INT
    Dim c2fb_temp_273 As SQLITE_C_INT
    Dim c2fb_temp_274 As SqliteWhereTerm Ptr
    Dim local104 As SqliteExpr Ptr
    Dim local105 As SQLITE_C_INT
    Dim c2fb_temp_275 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_276 As SQLITE_C_INT
    Dim c2fb_temp_277 As SqliteExpr Ptr
    Dim c2fb_temp_278 As SQLITE_C_INT
    Dim c2fb_temp_279 As SQLITE_C_INT
    Dim local106 As SQLITE_C_UINT
    Dim c2fb_temp_280 As SQLITE_C_INT
    Dim c2fb_temp_281 As u16 Ptr
    Dim c2fb_temp_282 As UShort
    Dim c2fb_temp_283 As SQLITE_C_INT
    Dim c2fb_temp_284 As SqliteWhereTerm Ptr
    Dim c2fb_temp_285 As SQLITE_C_INT
    Dim c2fb_temp_286 As SQLITE_C_INT
    Dim c2fb_temp_287 As SqliteWhereTerm Ptr
    Dim local107 As SqliteExpr Ptr
    Dim local108 As SqliteExpr
    Dim local109 As SqliteWhereTerm Ptr
    Dim c2fb_temp_288 As SqliteExpr Ptr
    Dim c2fb_temp_289 As SqliteWhereTerm Ptr
    Dim c2fb_temp_290 As SqliteExpr
    Dim c2fb_temp_291 As SqliteExpr Ptr Ptr
    Dim c2fb_temp_292 As SqliteExpr Ptr
    Dim c2fb_temp_293 As u16 Ptr
    Dim c2fb_temp_294 As UShort
    Dim local110 As SqliteTable Ptr
    Dim local111 As SQLITE_C_INT
    Dim local112 As SQLITE_C_INT
    Dim local113 As SQLITE_C_INT
    Dim local114 As SqliteWhereRightJoin Ptr
    Dim c2fb_temp_295 As SqliteTable Ptr
    Dim c2fb_temp_296 As SQLITE_C_INT
    Dim c2fb_temp_297 As SQLITE_C_INT
    Dim local115 As SQLITE_C_INT
    Dim local116 As SqliteIndex Ptr
    Dim c2fb_temp_298 As SQLITE_C_INT
    Dim c2fb_temp_299 As SQLITE_C_INT
    Dim c2fb_temp_300 As SQLITE_C_INT
    Dim c2fb_temp_301 As SQLITE_C_INT
    Dim local117 As SQLITE_C_INT
    Dim c2fb_temp_302 As SQLITE_C_INT
    Dim c2fb_temp_303 As SQLITE_C_INT Ptr
    Dim c2fb_temp_304 As SQLITE_C_INT
    Dim local118 As SqliteWhereRightJoin Ptr
    Dim c2fb_temp_305 As SQLITE_C_INT Ptr
    Dim c2fb_temp_306 As SQLITE_C_INT
    Dim c2fb_temp_307 As u8 Ptr
    Dim c2fb_temp_308 As UByte
    Dim c2fb_temp_309 As SqliteWhereTerm Ptr
    Dim c2fb_temp_310 As SQLITE_C_INT
    Dim c2fb_temp_311 As SQLITE_C_INT
    Dim c2fb_temp_312 As SqliteWhereTerm Ptr
    Dim c2fb_temp_313 As u16 Ptr
    Dim c2fb_temp_314 As UShort

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
    local12 = Cast(SQLITE_C_INT, &O0ULL)
    local13 = Cast(SQLITE_C_INT, &O0ULL)
    local14 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    c2fb_temp_0 = CPtr(SqliteWhereClause Ptr, @(arg2->sWC))
    local6 = c2fb_temp_0
    c2fb_temp_1 = arg0->db
    local8 = c2fb_temp_1
    c2fb_temp_2 = arg4->pWLoop
    local5 = c2fb_temp_2
    c2fb_temp_3 = CPtr(SqliteSrcItem Ptr, @(arg2->pTabList->a(arg4->iFrom)))
    local9 = c2fb_temp_3
    c2fb_temp_4 = Cast(SQLITE_C_INT, local9->iCursor)
    local2 = c2fb_temp_4
    c2fb_temp_5 = CPtr(sqlite3_uint64 Ptr, @(arg4->notReady))
    c2fb_temp_6 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (arg5 And Cast(sqlite3_uint64, (Not sqlite3WhereGetMask(CPtr(SqliteWhereMaskSet Ptr, @(arg2->sMaskSet)), local2))))))
    (*c2fb_temp_5) = c2fb_temp_6
    c2fb_temp_7 = Cast(SQLITE_C_INT, Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, (arg2->revMask Shr arg3))) And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL)))))
    local4 = c2fb_temp_7
    ' empty C statement
    c2fb_temp_8 = CPtr(SQLITE_C_INT Ptr, @(arg4->addrNxt))
    c2fb_temp_9 = Cast(SQLITE_C_INT, arg4->addrBrk)
    (*c2fb_temp_8) = c2fb_temp_9
    c2fb_temp_10 = Cast(SQLITE_C_INT, c2fb_temp_9)
    local10 = c2fb_temp_10
    c2fb_temp_11 = CPtr(SQLITE_C_INT Ptr, @(arg4->addrCont))
    c2fb_temp_12 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
    (*c2fb_temp_11) = c2fb_temp_12
    c2fb_temp_13 = Cast(SQLITE_C_INT, c2fb_temp_12)
    local11 = c2fb_temp_13
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg4->iFrom) > Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local9[Cast(SQLITE_C_INT, &O0ULL)].fg.jointype) And Cast(SQLITE_C_INT, &H08ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        c2fb_temp_17 = CPtr(SQLITE_C_INT Ptr, @(arg4->iLeftJoin))
        c2fb_temp_14 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
        c2fb_temp_15 = (*c2fb_temp_14)
        (*c2fb_temp_14) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_15 + 1)))
        c2fb_temp_16 = (*c2fb_temp_14)
        c2fb_temp_18 = Cast(SQLITE_C_INT, c2fb_temp_16)
        (*c2fb_temp_17) = c2fb_temp_18
        sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, &O0ULL), arg4->iLeftJoin)
        ' empty C statement
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local9->fg.flags) Shr 6) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 138ULL), local9->iCursor, Cast(SQLITE_C_INT, 1ULL))
        End If
    End If
    If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local9->fg.flags) Shr 6) And Cast(SQLITE_C_UINT, &H1ULL))) Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C unused-parameter annotation
        c2fb_temp_19 = local9->u4.pSubq
        local17 = c2fb_temp_19
        c2fb_temp_20 = Cast(SQLITE_C_INT, local17->regReturn)
        local16 = c2fb_temp_20
        sqlite3VdbeAddOp3(arg1, Cast(SQLITE_C_INT, 11ULL), local16, Cast(SQLITE_C_INT, &O0ULL), local17->addrFillSub)
        c2fb_temp_21 = CPtr(SQLITE_C_INT Ptr, @(arg4->p2))
        c2fb_temp_22 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 12ULL), local16, local10))
        (*c2fb_temp_21) = c2fb_temp_22
        ' empty C statement
        ' empty C statement
        c2fb_temp_23 = CPtr(u8 Ptr, @(arg4->op))
        c2fb_temp_24 = Cast(UByte, Cast(SQLITE_C_INT, 9ULL))
        (*c2fb_temp_23) = Cast(u8, c2fb_temp_24)
        c2fb_temp_24 = Cast(UByte, (*c2fb_temp_23))
    Else
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000400ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            ' C automatic storage declaration
            ' C automatic storage declaration
            local20 = local5->nLTerm
            c2fb_temp_25 = Cast(SQLITE_C_INT, sqlite3GetTempRange(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, (local20 + Cast(SQLITE_C_INT, 2ULL)))))
            local18 = c2fb_temp_25
            c2fb_temp_26 = Cast(SQLITE_C_INT, arg4->addrBrk)
            local19 = c2fb_temp_26
            c2fb_temp_27 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local0 = c2fb_temp_27
            While (-Cast(SQLITE_C_INT, ((local0 < local20))))
                local21 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local18 + local0)) + Cast(SQLITE_C_INT, 2ULL)))
                c2fb_temp_29 = local5->aLTerm[local0]
                local7 = c2fb_temp_29
                If ((-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, &O0ULL)))))) Then
                    Goto c2fb_flow_1
                End If
                If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local7->eOperator) And Cast(SQLITE_C_INT, &H0001ULL))) Then
                    If Cast(SQLITE_C_UINT, ((IIf((-Cast(SQLITE_C_INT, (((local0) <= Cast(SQLITE_C_INT, 31ULL))))), Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))) Shl (local0))), Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))) And local5->u.vtab.mHandleIn)) Then
                        c2fb_temp_30 = CPtr(SQLITE_C_INT Ptr, @(arg0->nTab))
                        c2fb_temp_31 = (*c2fb_temp_30)
                        (*c2fb_temp_30) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_31 + 1)))
                        local22 = c2fb_temp_31
                        c2fb_temp_32 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
                        c2fb_temp_33 = (*c2fb_temp_32)
                        (*c2fb_temp_32) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_33 + 1)))
                        c2fb_temp_34 = (*c2fb_temp_32)
                        local23 = c2fb_temp_34
                        sqlite3CodeRhsOfIN(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local7->pExpr), local22, Cast(SQLITE_C_INT, &O0ULL))
                        sqlite3VdbeAddOp3(arg1, Cast(SQLITE_C_INT, 177ULL), local22, local21, local23)
                    Else
                        codeEqualityTerm(arg0, local7, arg4, local0, local4, local21)
                        c2fb_temp_35 = Cast(SQLITE_C_INT, arg4->addrNxt)
                        local19 = c2fb_temp_35
                    End If
                Else
                    local24 = local7->pExpr->pRight
                    codeExprOrVector(arg0, local24, local21, Cast(SQLITE_C_INT, 1ULL))
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local7->eMatchOp) = Cast(SQLITE_C_INT, 74ULL))))) AndAlso Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local5->u.vtab.flags) Shr 1) And Cast(SQLITE_C_UINT, &H1ULL))))))) Then
                        ' C unused-parameter annotation
                        ' C unused-parameter annotation
                        ' C unused-parameter annotation
                        sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, &O0ULL), arg2->pSelect->iOffset)
                        ' empty C statement
                    End If
                End If
            c2fb_flow_1:
                c2fb_temp_28 = local0
                local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_28 + 1)))
            Wend
            c2fb_flow_0:
            sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 73ULL), local5->u.vtab.idxNum, local18)
            sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 73ULL), local20, Cast(SQLITE_C_INT, (local18 + Cast(SQLITE_C_INT, 1ULL))))
            sqlite3VdbeAddOp4(arg1, Cast(SQLITE_C_INT, 6ULL), local2, local19, local18, CPtr(Const ZString Ptr, CPtr(ZString Ptr, local5->u.vtab.idxStr)), IIf(Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local5->u.vtab.flags) Shr 0) And Cast(SQLITE_C_UINT, &H1ULL))), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 7ULL)))), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))))
            ' empty C statement
            c2fb_temp_36 = CPtr(SQLITE_C_UINT Ptr, @(local5->u.vtab.flags))
            c2fb_temp_37 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            c2fb_temp_37 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_37) And Cast(SQLITE_C_UINT, &H1ULL)))
            (*c2fb_temp_36) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_36)) And Not(Cast(SQLITE_C_UINT, &H1ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_37) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 0)))
            c2fb_temp_37 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_37) And Cast(SQLITE_C_UINT, &H1ULL)))
            If local8->mallocFailed Then
                c2fb_temp_38 = CPtr(Any Ptr Ptr, @(local5->u.vtab.idxStr))
                c2fb_temp_39 = CPtr(ZString Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                (*c2fb_temp_38) = CPtr(Any Ptr, c2fb_temp_39)
                c2fb_temp_39 = CPtr(ZString Ptr, (*c2fb_temp_38))
            End If
            c2fb_temp_40 = CPtr(SQLITE_C_INT Ptr, @(arg4->p1))
            c2fb_temp_41 = Cast(SQLITE_C_INT, local2)
            (*c2fb_temp_40) = c2fb_temp_41
            c2fb_temp_42 = CPtr(u8 Ptr, @(arg4->op))
            c2fb_temp_43 = Cast(UByte, IIf(arg2->eOnePass, Cast(SQLITE_C_INT, 189ULL), Cast(SQLITE_C_INT, 65ULL)))
            (*c2fb_temp_42) = Cast(u8, c2fb_temp_43)
            c2fb_temp_43 = Cast(UByte, (*c2fb_temp_42))
            c2fb_temp_44 = CPtr(SQLITE_C_INT Ptr, @(arg4->p2))
            c2fb_temp_45 = Cast(SQLITE_C_INT, sqlite3VdbeCurrentAddr(arg1))
            (*c2fb_temp_44) = c2fb_temp_45
            ' C unused-parameter annotation
            c2fb_temp_46 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local0 = c2fb_temp_46
            While (-Cast(SQLITE_C_INT, ((local0 < local20))))
                c2fb_temp_48 = local5->aLTerm[local0]
                local7 = c2fb_temp_48
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local0 < Cast(SQLITE_C_INT, 16ULL))))) AndAlso Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local5->u.vtab.omitMask) Shr local0))) And Cast(SQLITE_C_INT, 1ULL))))))) Then
                    disableTerm(arg4, local7)
                    Goto c2fb_flow_3
                End If
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local7->eOperator) And Cast(SQLITE_C_INT, &H0001ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((IIf((-Cast(SQLITE_C_INT, (((local0) <= Cast(SQLITE_C_INT, 31ULL))))), Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))) Shl (local0))), Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))) And local5->u.vtab.mHandleIn))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, (local8->mallocFailed = 0))))))) Then
                    ' C automatic storage declaration
                    ' C automatic storage declaration
                    ' C automatic storage declaration
                    ' C automatic storage declaration
                    c2fb_temp_49 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    local28 = c2fb_temp_49
                    While ((-Cast(SQLITE_C_INT, ((local28 < arg4->u.in.nIn)))))
                        c2fb_temp_51 = CPtr(SqliteVdbeOp Ptr, sqlite3VdbeGetOp(arg1, CPtr(SqliteInLoopRecord Ptr, arg4->u.in.aInLoop)[local28].addrInTop))
                        local27 = c2fb_temp_51
                        If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local27->opcode) = Cast(SQLITE_C_INT, 96ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local27->p3 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local18 + local0)) + Cast(SQLITE_C_INT, 2ULL)))))))))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local27->opcode) = Cast(SQLITE_C_INT, 137ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local27->p2 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local18 + local0)) + Cast(SQLITE_C_INT, 2ULL)))))))))))))))) Then
                            ' empty C statement
                            sqlite3VdbeAddOp3(arg1, local27->opcode, local27->p1, local27->p2, local27->p3)
                            Goto c2fb_flow_4
                        End If
                    c2fb_flow_5:
                        c2fb_temp_50 = local28
                        local28 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_50 + 1)))
                    Wend
                    c2fb_flow_4:
                    c2fb_temp_52 = CPtr(SqliteExpr Ptr, sqlite3PExpr(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 54ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)))
                    local25 = c2fb_temp_52
                    If (-Cast(SQLITE_C_INT, (local8->mallocFailed = 0))) Then
                        local29 = local7->u.x.iField
                        local30 = local7->pExpr->pLeft
                        ' C unused-parameter annotation
                        If (-Cast(SQLITE_C_INT, ((local29 > Cast(SQLITE_C_INT, &O0ULL))))) Then
                            ' C unused-parameter annotation
                            ' C unused-parameter annotation
                            ' C unused-parameter annotation
                            c2fb_temp_53 = CPtr(SqliteExpr Ptr Ptr, @(local25->pLeft))
                            c2fb_temp_54 = local30->x.pList->a(Cast(SQLITE_C_INT, (local29 - Cast(SQLITE_C_INT, 1ULL)))).pExpr
                            (*c2fb_temp_53) = c2fb_temp_54
                        Else
                            c2fb_temp_55 = CPtr(SqliteExpr Ptr Ptr, @(local25->pLeft))
                            c2fb_temp_56 = local30
                            (*c2fb_temp_55) = c2fb_temp_56
                        End If
                        c2fb_temp_58 = CPtr(SqliteExpr Ptr Ptr, @(local25->pRight))
                        c2fb_temp_57 = CPtr(SqliteExpr Ptr, sqlite3Expr(CPtr(Any Ptr, local8), Cast(SQLITE_C_INT, 176ULL), Cast(SQLITE_C_INT, &O0ULL)))
                        local26 = c2fb_temp_57
                        c2fb_temp_59 = c2fb_temp_57
                        (*c2fb_temp_58) = c2fb_temp_59
                        If local26 Then
                            c2fb_temp_60 = CPtr(SQLITE_C_INT Ptr, @(local26->iTable))
                            c2fb_temp_61 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local18 + local0)) + Cast(SQLITE_C_INT, 2ULL))))
                            (*c2fb_temp_60) = c2fb_temp_61
                            sqlite3ExprIfFalse(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local25), arg4->addrCont, Cast(SQLITE_C_INT, &H10ULL))
                        End If
                        c2fb_temp_62 = CPtr(SqliteExpr Ptr Ptr, @(local25->pLeft))
                        c2fb_temp_63 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                        (*c2fb_temp_62) = c2fb_temp_63
                    End If
                    sqlite3ExprDelete(CPtr(Any Ptr, local8), CPtr(Any Ptr, local25))
                End If
            c2fb_flow_3:
                c2fb_temp_47 = local0
                local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_47 + 1)))
            Wend
            c2fb_flow_2:
        Else
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000100ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000004ULL) Or Cast(SQLITE_C_INT, &H00000001ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
                ' C unused-parameter annotation
                c2fb_temp_64 = local5->aLTerm[Cast(SQLITE_C_INT, &O0ULL)]
                local7 = c2fb_temp_64
                ' C unused-parameter annotation
                ' C unused-parameter annotation
                ' empty C statement
                c2fb_temp_65 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
                c2fb_temp_66 = (*c2fb_temp_65)
                (*c2fb_temp_65) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_66 + 1)))
                c2fb_temp_67 = (*c2fb_temp_65)
                c2fb_temp_68 = Cast(SQLITE_C_INT, c2fb_temp_67)
                local13 = c2fb_temp_68
                c2fb_temp_69 = Cast(SQLITE_C_INT, codeEqualityTerm(arg0, local7, arg4, Cast(SQLITE_C_INT, &O0ULL), local4, local13))
                local12 = c2fb_temp_69
                If (-Cast(SQLITE_C_INT, ((local12 <> local13)))) Then
                    sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local13)
                End If
                c2fb_temp_70 = Cast(SQLITE_C_INT, arg4->addrNxt)
                local3 = c2fb_temp_70
                If arg4->regFilter Then
                    sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 13ULL), local12, local3)
                    ' empty C statement
                    sqlite3VdbeAddOp4Int(arg1, Cast(SQLITE_C_INT, 66ULL), arg4->regFilter, local3, local12, Cast(SQLITE_C_INT, 1ULL))
                    ' empty C statement
                    filterPullDown(arg0, arg2, arg3, local3, arg5)
                End If
                sqlite3VdbeAddOp3(arg1, Cast(SQLITE_C_INT, 30ULL), local2, local3, local12)
                ' empty C statement
                c2fb_temp_71 = CPtr(u8 Ptr, @(arg4->op))
                c2fb_temp_72 = Cast(UByte, Cast(SQLITE_C_INT, 189ULL))
                (*c2fb_temp_71) = Cast(u8, c2fb_temp_72)
                c2fb_temp_72 = Cast(UByte, (*c2fb_temp_71))
            Else
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000100ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000002ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
                    local31 = Cast(SQLITE_C_INT, 189ULL)
                    ' C automatic storage declaration
                    local33 = Cast(SQLITE_C_INT, &O0ULL)
                    ' C automatic storage declaration
                    ' C automatic storage declaration
                    c2fb_temp_73 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    local0 = c2fb_temp_73
                    c2fb_temp_74 = CPtr(SqliteWhereTerm Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                    local35 = c2fb_temp_74
                    c2fb_temp_75 = c2fb_temp_74
                    local34 = c2fb_temp_75
                    If Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000020ULL)))) Then
                        c2fb_temp_76 = local0
                        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_76 + 1)))
                        c2fb_temp_77 = local5->aLTerm[c2fb_temp_76]
                        local34 = c2fb_temp_77
                    End If
                    If Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000010ULL)))) Then
                        c2fb_temp_78 = local0
                        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_78 + 1)))
                        c2fb_temp_79 = local5->aLTerm[c2fb_temp_78]
                        local35 = c2fb_temp_79
                    End If
                    ' C unused-parameter annotation
                    If local4 Then
                        c2fb_temp_80 = local34
                        local7 = c2fb_temp_80
                        c2fb_temp_81 = local35
                        local34 = c2fb_temp_81
                        c2fb_temp_82 = local7
                        local35 = c2fb_temp_82
                    End If
                    ' empty C statement
#ifdef SQLITE_ENABLE_CURSOR_HINTS
                    codeCursorHint(local9, arg2, arg4, local35)
#endif
                    If local34 Then
                        ' C automatic storage declaration
                        ' C automatic storage declaration
                        ' C automatic storage declaration
                        ' C automatic storage declaration
                        Erase local40
                        local40(0) = Cast(SQLITE_C_INT, 24ULL)
                        local40(1) = Cast(SQLITE_C_INT, 22ULL)
                        local40(2) = Cast(SQLITE_C_INT, 21ULL)
                        local40(3) = Cast(SQLITE_C_INT, 23ULL)
                        ' C unused-parameter annotation
                        ' C unused-parameter annotation
                        ' C unused-parameter annotation
                        ' C unused-parameter annotation
                        ' empty C statement
                        c2fb_temp_83 = local34->pExpr
                        local36 = c2fb_temp_83
                        ' C unused-parameter annotation
                        ' empty C statement
                        If sqlite3ExprIsVector(CPtr(Any Ptr, local36->pRight)) Then
                            c2fb_temp_84 = Cast(SQLITE_C_INT, sqlite3GetTempReg(CPtr(Any Ptr, arg0)))
                            local38 = c2fb_temp_84
                            c2fb_temp_85 = Cast(SQLITE_C_INT, c2fb_temp_84)
                            local37 = c2fb_temp_85
                            codeExprOrVector(arg0, local36->pRight, local37, Cast(SQLITE_C_INT, 1ULL))
                            ' empty C statement
                            ' empty C statement
                            ' empty C statement
                            ' empty C statement
                            c2fb_temp_86 = Cast(SQLITE_C_INT, local40(Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local36->op) - Cast(SQLITE_C_INT, 55ULL))) - Cast(SQLITE_C_INT, 1ULL)))) And Cast(SQLITE_C_INT, &H3ULL)))) Or Cast(SQLITE_C_INT, &H1ULL)))))
                            local39 = c2fb_temp_86
                            ' C unused-parameter annotation
                            ' C unused-parameter annotation
                            ' C unused-parameter annotation
                            ' C unused-parameter annotation
                        Else
                            c2fb_temp_87 = Cast(SQLITE_C_INT, sqlite3ExprCodeTemp(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local36->pRight), CPtr(SQLITE_C_INT Ptr, @(local38))))
                            local37 = c2fb_temp_87
                            disableTerm(arg4, local34)
                            c2fb_temp_88 = Cast(SQLITE_C_INT, local40((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local36->op) - Cast(SQLITE_C_INT, 55ULL))))))
                            local39 = c2fb_temp_88
                        End If
                        sqlite3VdbeAddOp3(arg1, local39, local2, local10, local37)
                        ' empty C statement
                        ' empty C statement
                        ' empty C statement
                        ' empty C statement
                        ' empty C statement
                        sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local38)
                    Else
                        sqlite3VdbeAddOp2(arg1, IIf(local4, Cast(SQLITE_C_INT, 32ULL), Cast(SQLITE_C_INT, 36ULL)), local2, arg4->addrHalt)
                        ' empty C statement
                        ' empty C statement
                    End If
                    If local35 Then
                        ' C automatic storage declaration
                        c2fb_temp_89 = local35->pExpr
                        local41 = c2fb_temp_89
                        ' C unused-parameter annotation
                        ' C unused-parameter annotation
                        ' empty C statement
                        ' empty C statement
                        c2fb_temp_90 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
                        c2fb_temp_91 = (*c2fb_temp_90)
                        (*c2fb_temp_90) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_91 + 1)))
                        c2fb_temp_92 = (*c2fb_temp_90)
                        c2fb_temp_93 = Cast(SQLITE_C_INT, c2fb_temp_92)
                        local33 = c2fb_temp_93
                        codeExprOrVector(arg0, local41->pRight, local33, Cast(SQLITE_C_INT, 1ULL))
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = sqlite3ExprIsVector(CPtr(Any Ptr, local41->pRight)))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local41->op) = Cast(SQLITE_C_INT, 57ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local41->op) = Cast(SQLITE_C_INT, 55ULL)))))))))))))) Then
                            c2fb_temp_94 = Cast(SQLITE_C_INT, IIf(local4, Cast(SQLITE_C_INT, 56ULL), Cast(SQLITE_C_INT, 58ULL)))
                            local31 = c2fb_temp_94
                        Else
                            c2fb_temp_95 = Cast(SQLITE_C_INT, IIf(local4, Cast(SQLITE_C_INT, 57ULL), Cast(SQLITE_C_INT, 55ULL)))
                            local31 = c2fb_temp_95
                        End If
                        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = sqlite3ExprIsVector(CPtr(Any Ptr, local41->pRight)))))) Then
                            disableTerm(arg4, local35)
                        End If
                    End If
                    c2fb_temp_96 = Cast(SQLITE_C_INT, sqlite3VdbeCurrentAddr(arg1))
                    local32 = c2fb_temp_96
                    c2fb_temp_97 = CPtr(u8 Ptr, @(arg4->op))
                    c2fb_temp_98 = Cast(UByte, IIf(local4, Cast(SQLITE_C_INT, 39ULL), Cast(SQLITE_C_INT, 40ULL)))
                    (*c2fb_temp_97) = Cast(u8, c2fb_temp_98)
                    c2fb_temp_98 = Cast(UByte, (*c2fb_temp_97))
                    c2fb_temp_99 = CPtr(SQLITE_C_INT Ptr, @(arg4->p1))
                    c2fb_temp_100 = Cast(SQLITE_C_INT, local2)
                    (*c2fb_temp_99) = c2fb_temp_100
                    c2fb_temp_101 = CPtr(SQLITE_C_INT Ptr, @(arg4->p2))
                    c2fb_temp_102 = Cast(SQLITE_C_INT, local32)
                    (*c2fb_temp_101) = c2fb_temp_102
                    ' C unused-parameter annotation
                    If (-Cast(SQLITE_C_INT, ((local31 <> Cast(SQLITE_C_INT, 189ULL))))) Then
                        c2fb_temp_103 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
                        c2fb_temp_104 = (*c2fb_temp_103)
                        (*c2fb_temp_103) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_104 + 1)))
                        c2fb_temp_105 = (*c2fb_temp_103)
                        c2fb_temp_106 = Cast(SQLITE_C_INT, c2fb_temp_105)
                        local12 = c2fb_temp_106
                        sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 137ULL), local2, local12)
                        sqlite3VdbeAddOp3(arg1, local31, local33, local10, local12)
                        ' empty C statement
                        ' empty C statement
                        ' empty C statement
                        ' empty C statement
                        sqlite3VdbeChangeP5(arg1, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H43ULL) Or Cast(SQLITE_C_INT, &H10ULL))))
                    End If
                Else
                    If Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000200ULL)))) Then
                        ' C static array storage
                        ' C static array storage
                        local44 = local5->u.btree.nEq
                        local45 = local5->u.btree.nBtm
                        local46 = local5->u.btree.nTop
                        ' C automatic storage declaration
                        local48 = Cast(SQLITE_C_INT, &O0ULL)
                        local49 = Cast(SQLITE_C_INT, &O0ULL)
                        ' C automatic storage declaration
                        ' C automatic storage declaration
                        ' C automatic storage declaration
                        ' C automatic storage declaration
                        ' C automatic storage declaration
                        local55 = Cast(SQLITE_C_INT, &O0ULL)
                        ' C automatic storage declaration
                        ' C automatic storage declaration
                        local58 = Cast(SQLITE_C_INT, &O0ULL)
                        local59 = Cast(SQLITE_C_INT, &O0ULL)
                        local60 = Cast(SQLITE_C_INT, &O0ULL)
                        ' C automatic storage declaration
                        local62 = Cast(SQLITE_C_INT, &O0ULL)
                        local63 = Cast(SQLITE_C_INT, &O0ULL)
                        c2fb_temp_107 = CPtr(SqliteIndex Ptr, local5->u.btree.pIndex)
                        local14 = c2fb_temp_107
                        c2fb_temp_108 = Cast(SQLITE_C_INT, arg4->iIdxCur)
                        local54 = c2fb_temp_108
                        ' C unused-parameter annotation
                        c2fb_temp_109 = Cast(SQLITE_C_INT, local44)
                        local0 = c2fb_temp_109
                        If Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000020ULL)))) Then
                            c2fb_temp_110 = local0
                            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_110 + 1)))
                            c2fb_temp_111 = local5->aLTerm[c2fb_temp_110]
                            local48 = c2fb_temp_111
                            c2fb_temp_112 = Cast(SQLITE_C_INT, (IIf((-Cast(SQLITE_C_INT, (((local55) > Cast(SQLITE_C_INT, (local5->u.btree.nBtm)))))), (local55), Cast(SQLITE_C_INT, (local5->u.btree.nBtm)))))
                            local55 = c2fb_temp_112
                            ' C unused-parameter annotation
                        End If
                        If Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000010ULL)))) Then
                            c2fb_temp_113 = local0
                            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_113 + 1)))
                            c2fb_temp_114 = local5->aLTerm[c2fb_temp_113]
                            local49 = c2fb_temp_114
                            c2fb_temp_115 = Cast(SQLITE_C_INT, (IIf((-Cast(SQLITE_C_INT, (((local55) > Cast(SQLITE_C_INT, (local5->u.btree.nTop)))))), (local55), Cast(SQLITE_C_INT, (local5->u.btree.nTop)))))
                            local55 = c2fb_temp_115
                            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local49->wtFlags) And Cast(SQLITE_C_INT, &H0100ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                                ' C unused-parameter annotation
                                ' C unused-parameter annotation
                                c2fb_temp_119 = CPtr(u32 Ptr, @(arg4->iLikeRepCntr))
                                c2fb_temp_116 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
                                c2fb_temp_117 = (*c2fb_temp_116)
                                (*c2fb_temp_116) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_117 + 1)))
                                c2fb_temp_118 = (*c2fb_temp_116)
                                c2fb_temp_120 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, c2fb_temp_118))
                                (*c2fb_temp_119) = Cast(u32, c2fb_temp_120)
                                c2fb_temp_120 = Cast(SQLITE_C_UINT, (*c2fb_temp_119))
                                sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, arg4->iLikeRepCntr))
                                ' empty C statement
                                c2fb_temp_121 = CPtr(SQLITE_C_INT Ptr, @(arg4->addrLikeRep))
                                c2fb_temp_122 = Cast(SQLITE_C_INT, sqlite3VdbeCurrentAddr(arg1))
                                (*c2fb_temp_121) = c2fb_temp_122
                                ' empty C statement
                                ' empty C statement
                                ' C unused-parameter annotation
                                c2fb_temp_123 = CPtr(u32 Ptr, @(arg4->iLikeRepCntr))
                                c2fb_temp_124 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_123)) Shl Cast(SQLITE_C_INT, 1ULL))))
                                (*c2fb_temp_123) = Cast(u32, c2fb_temp_124)
                                c2fb_temp_124 = Cast(SQLITE_C_UINT, (*c2fb_temp_123))
                                c2fb_temp_125 = CPtr(u32 Ptr, @(arg4->iLikeRepCntr))
                                c2fb_temp_126 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_125)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (local4 Xor ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(UByte Ptr, local14->aSortOrder)[local44]) = Cast(SQLITE_C_INT, 1ULL))))))))))))
                                (*c2fb_temp_125) = Cast(u32, c2fb_temp_126)
                                c2fb_temp_126 = Cast(SQLITE_C_UINT, (*c2fb_temp_125))
                            End If
                            If (-Cast(SQLITE_C_INT, ((local48 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                                c2fb_temp_127 = Cast(SQLITE_C_INT, local14->aiColumn[local44])
                                local0 = c2fb_temp_127
                                If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local0 >= Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local14->pTable->aCol[local0].flags) Shr 0) And Cast(SQLITE_C_UINT, &HFULL))) = Cast(SQLITE_C_INT, &O0ULL)))))))))) OrElse (-Cast(SQLITE_C_INT, ((local0 = (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 2ULL)))))))))))) Then
                                    c2fb_temp_128 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
                                    local59 = c2fb_temp_128
                                End If
                            End If
                        End If
                        ' C unused-parameter annotation
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000010ULL) Or Cast(SQLITE_C_INT, &H00000020ULL)))))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00080000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
                            ' C unused-parameter annotation
                            ' C unused-parameter annotation
                            ' empty C statement
                            c2fb_temp_129 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                            local55 = c2fb_temp_129
                            c2fb_temp_130 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
                            local59 = c2fb_temp_130
                            c2fb_temp_135 = CPtr(SQLITE_C_INT Ptr, @(arg4->regBignull))
                            c2fb_temp_131 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
                            c2fb_temp_132 = (*c2fb_temp_131)
                            (*c2fb_temp_131) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_132 + 1)))
                            c2fb_temp_133 = (*c2fb_temp_131)
                            c2fb_temp_134 = Cast(SQLITE_C_INT, c2fb_temp_133)
                            local62 = c2fb_temp_134
                            c2fb_temp_136 = Cast(SQLITE_C_INT, c2fb_temp_134)
                            (*c2fb_temp_135) = c2fb_temp_136
                            If arg4->iLeftJoin Then
                                sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, &O0ULL), local62)
                            End If
                            c2fb_temp_137 = CPtr(SQLITE_C_INT Ptr, @(arg4->addrBignull))
                            c2fb_temp_138 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
                            (*c2fb_temp_137) = c2fb_temp_138
                        End If
                        If ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local44) < Cast(SQLITE_C_INT, local14->nColumn))))) AndAlso (-Cast(SQLITE_C_INT, ((local4 = ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(UByte Ptr, local14->aSortOrder)[local44]) = Cast(SQLITE_C_INT, &O0ULL))))))))))))))) Then
                            local64 = local49
                            c2fb_temp_139 = local48
                            local49 = c2fb_temp_139
                            c2fb_temp_140 = local64
                            local48 = c2fb_temp_140
                            ' empty C statement
                            local65 = local59
                            c2fb_temp_141 = Cast(UByte, local60)
                            local59 = c2fb_temp_141
                            c2fb_temp_142 = Cast(UByte, local65)
                            local60 = c2fb_temp_142
                            ' empty C statement
                            local66 = local45
                            c2fb_temp_143 = Cast(UShort, local46)
                            local45 = c2fb_temp_143
                            c2fb_temp_144 = Cast(UShort, local66)
                            local46 = c2fb_temp_144
                            ' empty C statement
                        End If
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg3 > Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00100000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
                            sqlite3VdbeAddOp1(arg1, Cast(SQLITE_C_INT, 138ULL), local54)
                        End If
                        ' empty C statement
#ifdef SQLITE_ENABLE_CURSOR_HINTS
                        codeCursorHint(local9, arg2, arg4, local49)
#endif
                        c2fb_temp_145 = Cast(SQLITE_C_INT, codeAllEqualityTerms(arg0, arg4, local4, local55, CPtr(ZString Ptr Ptr, @(local57))))
                        local47 = c2fb_temp_145
                        ' C unused-parameter annotation
                        If (-Cast(SQLITE_C_INT, ((local57 AndAlso local46)))) Then
                            c2fb_temp_146 = CPtr(ZString Ptr, sqlite3DbStrDup(CPtr(Any Ptr, local8), CPtr(Const ZString Ptr, CPtr(Byte Ptr, @(CPtr(Byte Ptr, local57)[local44])))))
                            local58 = c2fb_temp_146
                        End If
                        c2fb_temp_147 = Cast(SQLITE_C_INT, (IIf(local62, arg4->addrBignull, arg4->addrNxt)))
                        local3 = c2fb_temp_147
                        ' empty C statement
                        ' empty C statement
                        ' empty C statement
                        ' empty C statement
                        c2fb_temp_148 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (local48 = 0))) OrElse Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local48->eOperator) And (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 56ULL) - Cast(SQLITE_C_INT, 54ULL))))))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 58ULL) - Cast(SQLITE_C_INT, 54ULL)))))))))))))))))
                        local50 = c2fb_temp_148
                        c2fb_temp_149 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (local49 = 0))) OrElse Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local49->eOperator) And (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 56ULL) - Cast(SQLITE_C_INT, 54ULL))))))) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Shl (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 58ULL) - Cast(SQLITE_C_INT, 54ULL)))))))))))))))))
                        local51 = c2fb_temp_149
                        c2fb_temp_150 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, ((local48 OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local44) > Cast(SQLITE_C_INT, &O0ULL))))))))))
                        local52 = c2fb_temp_150
                        c2fb_temp_151 = Cast(SQLITE_C_INT, local44)
                        local53 = c2fb_temp_151
                        If local48 Then
                            local67 = local48->pExpr->pRight
                            codeExprOrVector(arg0, local67, Cast(SQLITE_C_INT, (local47 + Cast(SQLITE_C_INT, local44))), local45)
                            whereLikeOptimizationStringFixup(arg1, arg4, local48)
                            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local48->wtFlags) And Cast(SQLITE_C_INT, &H0080ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso sqlite3ExprCanBeNull(CPtr(Any Ptr, local67)))))) Then
                                sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 51ULL), Cast(SQLITE_C_INT, (local47 + Cast(SQLITE_C_INT, local44))), local3)
                                ' empty C statement
                            End If
                            If local57 Then
                                updateRangeAffinityStr(local67, local45, CPtr(ZString Ptr, CPtr(Byte Ptr, @(CPtr(Byte Ptr, local57)[local44]))))
                            End If
                            c2fb_temp_152 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local53 + Cast(SQLITE_C_INT, local45))))
                            local53 = c2fb_temp_152
                            ' empty C statement
                            If (-Cast(SQLITE_C_INT, ((sqlite3ExprIsVector(CPtr(Any Ptr, local67)) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                                disableTerm(arg4, local48)
                            Else
                                c2fb_temp_153 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                                local50 = c2fb_temp_153
                            End If
                            c2fb_temp_154 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                            local59 = c2fb_temp_154
                        Else
                            If local59 Then
                                c2fb_temp_155 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                                local50 = c2fb_temp_155
                                sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, (local47 + Cast(SQLITE_C_INT, local44))))
                                c2fb_temp_156 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                                local52 = c2fb_temp_156
                                c2fb_temp_157 = local53
                                local53 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_157 + 1)))
                            Else
                                If local62 Then
                                    sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, (local47 + Cast(SQLITE_C_INT, local44))))
                                    c2fb_temp_158 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                                    local52 = c2fb_temp_158
                                    c2fb_temp_159 = local53
                                    local53 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_159 + 1)))
                                End If
                            End If
                        End If
                        codeApplyAffinity(arg0, local47, Cast(SQLITE_C_INT, (local53 - Cast(SQLITE_C_INT, local59))), local57)
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local5->nSkip) > Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local53 = Cast(SQLITE_C_INT, local5->nSkip))))))))) Then
                            ' empty C block
                        Else
                            If local62 Then
                                sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, 1ULL), local62)
                                ' empty C statement
                            End If
                            If arg4->regFilter Then
                                ' C unused-parameter annotation
                                sqlite3VdbeAddOp4Int(arg1, Cast(SQLITE_C_INT, 66ULL), arg4->regFilter, local3, local47, local44)
                                ' empty C statement
                                filterPullDown(arg0, arg2, arg3, local3, arg5)
                            End If
                            c2fb_temp_160 = Cast(SQLITE_C_INT, local42(Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local52 Shl Cast(SQLITE_C_INT, 2ULL)))) + (Cast(SQLITE_C_INT, (local50 Shl Cast(SQLITE_C_INT, 1ULL)))))) + local4))))
                            local56 = c2fb_temp_160
                            ' C unused-parameter annotation
                            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00100000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, ((local56 = Cast(SQLITE_C_INT, 23ULL))))))))) Then
                                ' C unused-parameter annotation
                                c2fb_temp_161 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(arg1, Cast(SQLITE_C_INT, 126ULL), Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local14->aiRowLogEst[Cast(SQLITE_C_INT, &O0ULL)]) + Cast(SQLITE_C_INT, 9ULL)))) \ Cast(SQLITE_C_INT, 10ULL)))))
                                local63 = c2fb_temp_161
                                If (-Cast(SQLITE_C_INT, ((local48 OrElse local49)))) Then
                                    sqlite3VdbeChangeP5(arg1, Cast(SQLITE_C_INT, 1ULL))
                                    sqlite3VdbeChangeP2(arg1, local63, Cast(SQLITE_C_INT, (sqlite3VdbeCurrentAddr(arg1) + Cast(SQLITE_C_INT, 1ULL))))
                                    c2fb_temp_162 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                                    local63 = c2fb_temp_162
                                End If
                                ' empty C statement
                            End If
                            sqlite3VdbeAddOp4Int(arg1, local56, local54, local3, local47, local53)
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
                            ' empty C statement
                            ' C unused-parameter annotation
                            If local62 Then
                                ' C unused-parameter annotation
                                ' C unused-parameter annotation
                                ' C unused-parameter annotation
                                sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 9ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, (sqlite3VdbeCurrentAddr(arg1) + Cast(SQLITE_C_INT, 2ULL))))
                                c2fb_temp_163 = Cast(SQLITE_C_INT, local42(Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local53 > Cast(SQLITE_C_INT, 1ULL)))))) * Cast(SQLITE_C_INT, 4ULL))) + Cast(SQLITE_C_INT, 2ULL))) + local4))))
                                local56 = c2fb_temp_163
                                sqlite3VdbeAddOp4Int(arg1, local56, local54, local3, local47, Cast(SQLITE_C_INT, (local53 - local50)))
                                ' empty C statement
                                ' empty C statement
                                ' empty C statement
                                ' empty C statement
                                ' empty C statement
                                ' empty C statement
                                ' empty C statement
                                ' empty C statement
                                ' empty C statement
                                ' C unused-parameter annotation
                            End If
                        End If
                        c2fb_temp_164 = Cast(SQLITE_C_INT, local44)
                        local53 = c2fb_temp_164
                        ' C unused-parameter annotation
                        If local49 Then
                            local68 = local49->pExpr->pRight
                            ' C unused-parameter annotation
                            codeExprOrVector(arg0, local68, Cast(SQLITE_C_INT, (local47 + Cast(SQLITE_C_INT, local44))), local46)
                            whereLikeOptimizationStringFixup(arg1, arg4, local49)
                            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local49->wtFlags) And Cast(SQLITE_C_INT, &H0080ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso sqlite3ExprCanBeNull(CPtr(Any Ptr, local68)))))) Then
                                sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 51ULL), Cast(SQLITE_C_INT, (local47 + Cast(SQLITE_C_INT, local44))), local3)
                                ' empty C statement
                            End If
                            If local58 Then
                                updateRangeAffinityStr(local68, local46, local58)
                                codeApplyAffinity(arg0, Cast(SQLITE_C_INT, (local47 + Cast(SQLITE_C_INT, local44))), local46, local58)
                            Else
                                ' C unused-parameter annotation
                            End If
                            c2fb_temp_165 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local53 + Cast(SQLITE_C_INT, local46))))
                            local53 = c2fb_temp_165
                            ' empty C statement
                            If (-Cast(SQLITE_C_INT, ((sqlite3ExprIsVector(CPtr(Any Ptr, local68)) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                                disableTerm(arg4, local49)
                            Else
                                c2fb_temp_166 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                                local51 = c2fb_temp_166
                            End If
                        Else
                            If local60 Then
                                If (-Cast(SQLITE_C_INT, ((local62 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                                    sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, (local47 + Cast(SQLITE_C_INT, local44))))
                                    c2fb_temp_167 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                                    local51 = c2fb_temp_167
                                End If
                                c2fb_temp_168 = local53
                                local53 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_168 + 1)))
                            End If
                        End If
                        If local57 Then
                            sqlite3DbNNFreeNN(CPtr(Any Ptr, local8), CPtr(Any Ptr, local57))
                        End If
                        If local58 Then
                            sqlite3DbNNFreeNN(CPtr(Any Ptr, local8), CPtr(Any Ptr, local58))
                        End If
                        c2fb_temp_169 = CPtr(SQLITE_C_INT Ptr, @(arg4->p2))
                        c2fb_temp_170 = Cast(SQLITE_C_INT, sqlite3VdbeCurrentAddr(arg1))
                        (*c2fb_temp_169) = c2fb_temp_170
                        If local53 Then
                            If local62 Then
                                sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 17ULL), local62, Cast(SQLITE_C_INT, (sqlite3VdbeCurrentAddr(arg1) + Cast(SQLITE_C_INT, 3ULL))))
                                ' empty C statement
                                ' empty C statement
                            End If
                            c2fb_temp_171 = Cast(SQLITE_C_INT, local43(Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local4 * Cast(SQLITE_C_INT, 2ULL))) + local51))))
                            local56 = c2fb_temp_171
                            sqlite3VdbeAddOp4Int(arg1, local56, local54, local3, local47, local53)
                            ' empty C statement
                            ' empty C statement
                            ' empty C statement
                            ' empty C statement
                            ' empty C statement
                            ' empty C statement
                            ' empty C statement
                            ' empty C statement
                            If local63 Then
                                sqlite3VdbeJumpHere(arg1, local63)
                            End If
                        End If
                        If local62 Then
                            ' C unused-parameter annotation
                            ' C unused-parameter annotation
                            ' C unused-parameter annotation
                            sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 16ULL), local62, Cast(SQLITE_C_INT, (sqlite3VdbeCurrentAddr(arg1) + Cast(SQLITE_C_INT, 2ULL))))
                            ' empty C statement
                            ' empty C statement
                            c2fb_temp_172 = Cast(SQLITE_C_INT, local43(Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local4 * Cast(SQLITE_C_INT, 2ULL))) + Cast(SQLITE_C_INT, local59)))))
                            local56 = c2fb_temp_172
                            sqlite3VdbeAddOp4Int(arg1, local56, local54, local3, local47, Cast(SQLITE_C_INT, (local53 + Cast(SQLITE_C_INT, local59))))
                            ' empty C statement
                            ' empty C statement
                            ' empty C statement
                            ' empty C statement
                            ' empty C statement
                            ' empty C statement
                            ' empty C statement
                            ' empty C statement
                        End If
                        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00040000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                            sqlite3VdbeAddOp3(arg1, Cast(SQLITE_C_INT, 127ULL), local54, local44, local44)
                        End If
                        c2fb_temp_173 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000040ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2->wctrlFlags) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0020ULL) Or Cast(SQLITE_C_INT, &H1000ULL))))))) = Cast(SQLITE_C_INT, &O0ULL))))))))))
                        local61 = c2fb_temp_173
                        If local61 Then
                            ' empty C block
                        Else
                            If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local14->pTable)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                                codeDeferredSeek(arg2, local14, local2, local54)
                            Else
                                If (-Cast(SQLITE_C_INT, ((local2 <> local54)))) Then
                                    local69 = CPtr(SqliteIndex Ptr, sqlite3PrimaryKeyIndex(CPtr(Any Ptr, local14->pTable)))
                                    c2fb_temp_174 = Cast(SQLITE_C_INT, sqlite3GetTempRange(CPtr(Any Ptr, arg0), local69->nKeyCol))
                                    local12 = c2fb_temp_174
                                    c2fb_temp_175 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                                    local0 = c2fb_temp_175
                                    While (-Cast(SQLITE_C_INT, ((local0 < Cast(SQLITE_C_INT, local69->nKeyCol)))))
                                        c2fb_temp_177 = Cast(SQLITE_C_INT, sqlite3TableColumnToIndex(CPtr(Any Ptr, local14), local69->aiColumn[local0]))
                                        local1 = c2fb_temp_177
                                        sqlite3VdbeAddOp3(arg1, Cast(SQLITE_C_INT, 96ULL), local54, local1, Cast(SQLITE_C_INT, (local12 + local0)))
                                    c2fb_flow_7:
                                        c2fb_temp_176 = local0
                                        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_176 + 1)))
                                    Wend
                                    c2fb_flow_6:
                                    sqlite3VdbeAddOp4Int(arg1, Cast(SQLITE_C_INT, 28ULL), local2, local11, local12, local69->nKeyCol)
                                    ' empty C statement
                                End If
                            End If
                        End If
                        If (-Cast(SQLITE_C_INT, ((arg4->iLeftJoin = Cast(SQLITE_C_INT, &O0ULL))))) Then
                            If (-Cast(SQLITE_C_INT, ((CPtr(SqliteExpr Ptr, local14->pPartIdxWhere) AndAlso (-Cast(SQLITE_C_INT, ((CPtr(SqliteWhereRightJoin Ptr, arg4->pRJ) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                                whereApplyPartialIndexConstraints(CPtr(SqliteExpr Ptr, local14->pPartIdxWhere), local2, local6)
                            End If
                        Else
                            ' empty C statement
                            ' C unused-parameter annotation
                        End If
                        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00001000ULL))))) OrElse Cast(SQLITE_C_UINT, ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg4->u.in.nIn AndAlso (-Cast(SQLITE_C_INT, ((local62 = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso whereLoopIsOneRow(local5))))))))))) Then
                            c2fb_temp_178 = CPtr(u8 Ptr, @(arg4->op))
                            c2fb_temp_179 = Cast(UByte, Cast(SQLITE_C_INT, 189ULL))
                            (*c2fb_temp_178) = Cast(u8, c2fb_temp_179)
                            c2fb_temp_179 = Cast(UByte, (*c2fb_temp_178))
                        Else
                            If local4 Then
                                c2fb_temp_180 = CPtr(u8 Ptr, @(arg4->op))
                                c2fb_temp_181 = Cast(UByte, Cast(SQLITE_C_INT, 39ULL))
                                (*c2fb_temp_180) = Cast(u8, c2fb_temp_181)
                                c2fb_temp_181 = Cast(UByte, (*c2fb_temp_180))
                            Else
                                c2fb_temp_182 = CPtr(u8 Ptr, @(arg4->op))
                                c2fb_temp_183 = Cast(UByte, Cast(SQLITE_C_INT, 40ULL))
                                (*c2fb_temp_182) = Cast(u8, c2fb_temp_183)
                                c2fb_temp_183 = Cast(UByte, (*c2fb_temp_182))
                            End If
                        End If
                        c2fb_temp_184 = CPtr(SQLITE_C_INT Ptr, @(arg4->p1))
                        c2fb_temp_185 = Cast(SQLITE_C_INT, local54)
                        (*c2fb_temp_184) = c2fb_temp_185
                        c2fb_temp_186 = CPtr(u8 Ptr, @(arg4->p3))
                        c2fb_temp_187 = Cast(UByte, IIf((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00010000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))), Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, &O0ULL)))
                        (*c2fb_temp_186) = Cast(u8, c2fb_temp_187)
                        c2fb_temp_187 = Cast(UByte, (*c2fb_temp_186))
                        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000000fULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                            c2fb_temp_188 = CPtr(u8 Ptr, @(arg4->p5))
                            c2fb_temp_189 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
                            (*c2fb_temp_188) = Cast(u8, c2fb_temp_189)
                            c2fb_temp_189 = Cast(UByte, (*c2fb_temp_188))
                        Else
                            ' C unused-parameter annotation
                        End If
                        If local61 Then
                            c2fb_temp_190 = CPtr(SqliteIndex Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                            local14 = c2fb_temp_190
                        End If
                    Else
                        If Cast(SQLITE_C_UINT, (local5->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00002000ULL)))) Then
                            ' C automatic storage declaration
                            ' C automatic storage declaration
                            local72 = Cast(SQLITE_C_INT, &O0ULL)
                            c2fb_temp_191 = CPtr(SQLITE_C_INT Ptr, @(arg0->nTab))
                            c2fb_temp_192 = (*c2fb_temp_191)
                            (*c2fb_temp_191) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_192 + 1)))
                            local73 = c2fb_temp_192
                            c2fb_temp_193 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
                            c2fb_temp_194 = (*c2fb_temp_193)
                            (*c2fb_temp_193) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_194 + 1)))
                            c2fb_temp_195 = (*c2fb_temp_193)
                            local74 = c2fb_temp_195
                            local75 = Cast(SQLITE_C_INT, &O0ULL)
                            local76 = Cast(SQLITE_C_INT, &O0ULL)
                            local77 = sqlite3VdbeMakeLabel(arg0)
                            ' C automatic storage declaration
                            local79 = Cast(SQLITE_C_INT, &O0ULL)
                            ' C automatic storage declaration
                            local81 = Cast(SQLITE_C_INT, &O0ULL)
                            local82 = local9->pSTab
                            c2fb_temp_196 = local5->aLTerm[Cast(SQLITE_C_INT, &O0ULL)]
                            local7 = c2fb_temp_196
                            ' C unused-parameter annotation
                            ' C unused-parameter annotation
                            ' C unused-parameter annotation
                            c2fb_temp_197 = CPtr(SqliteWhereClause Ptr, @(CPtr(SqliteWhereOrInfo Ptr, local7->u.pOrInfo)->wc))
                            local70 = c2fb_temp_197
                            c2fb_temp_198 = CPtr(u8 Ptr, @(arg4->op))
                            c2fb_temp_199 = Cast(UByte, Cast(SQLITE_C_INT, 69ULL))
                            (*c2fb_temp_198) = Cast(u8, c2fb_temp_199)
                            c2fb_temp_199 = Cast(UByte, (*c2fb_temp_198))
                            c2fb_temp_200 = CPtr(SQLITE_C_INT Ptr, @(arg4->p1))
                            c2fb_temp_201 = Cast(SQLITE_C_INT, local74)
                            (*c2fb_temp_200) = c2fb_temp_201
                            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg2->nLevel) > Cast(SQLITE_C_INT, 1ULL))))) OrElse Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local9->fg.flags) Shr 18) And Cast(SQLITE_C_UINT, &H1ULL))))))) Then
                                ' C automatic storage declaration
                                ' C automatic storage declaration
                                c2fb_temp_202 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2->nLevel) - arg3)) - Cast(SQLITE_C_INT, 1ULL))))
                                local83 = c2fb_temp_202
                                c2fb_temp_203 = CPtr(SqliteSrcList Ptr, CPtr(Any Ptr, sqlite3DbMallocRawNN(CPtr(Any Ptr, local8), (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, (SizeOf(SqliteSrcList) - SizeOf(SqliteSrcItem)))) + Cast(sqlite3_uint64, (Cast(sqlite3_uint64, (Cast(SQLITE_C_INT, (local83 + Cast(SQLITE_C_INT, 1ULL))))) * Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteSrcItem)))))))))))
                                local71 = c2fb_temp_203
                                If (-Cast(SQLITE_C_INT, ((local71 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                                    Return arg5
                                End If
                                c2fb_temp_204 = CPtr(u32 Ptr, @(local71->nAlloc))
                                c2fb_temp_205 = Cast(SQLITE_C_UINT, Cast(UByte, (Cast(SQLITE_C_INT, (local83 + Cast(SQLITE_C_INT, 1ULL))))))
                                (*c2fb_temp_204) = Cast(u32, c2fb_temp_205)
                                c2fb_temp_205 = Cast(SQLITE_C_UINT, (*c2fb_temp_204))
                                c2fb_temp_206 = CPtr(SQLITE_C_INT Ptr, @(local71->nSrc))
                                c2fb_temp_207 = Cast(SQLITE_C_INT, local71->nAlloc)
                                (*c2fb_temp_206) = c2fb_temp_207
                                c2fb_temp_208 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, CPtr(SqliteSrcItem Ptr, (@local71->a(0)))), CPtr(Const Any Ptr, local9), Cast(SQLITE_SIZE_T, SizeOf(SqliteSrcItem))))
                                c2fb_temp_209 = CPtr(SqliteSrcItem Ptr, (@arg2->pTabList->a(0)))
                                local84 = c2fb_temp_209
                                c2fb_temp_210 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                                local1 = c2fb_temp_210
                                While (-Cast(SQLITE_C_INT, ((local1 <= local83))))
                                    c2fb_temp_212 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, CPtr(SqliteSrcItem Ptr, @(local71->a(local1)))), CPtr(Const Any Ptr, CPtr(SqliteSrcItem Ptr, @(local84[arg4[local1].iFrom]))), Cast(SQLITE_SIZE_T, SizeOf(SqliteSrcItem))))
                                c2fb_flow_9:
                                    c2fb_temp_211 = local1
                                    local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_211 + 1)))
                                Wend
                                c2fb_flow_8:
                                c2fb_temp_213 = CPtr(SQLITE_C_UINT Ptr, @(local71->a(Cast(SQLITE_C_INT, &O0ULL)).fg.flags))
                                c2fb_temp_214 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                                c2fb_temp_214 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_214) And Cast(SQLITE_C_UINT, &H1ULL)))
                                (*c2fb_temp_213) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_213)) And Not(Cast(SQLITE_C_UINT, &H40000ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_214) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 18)))
                                c2fb_temp_214 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_214) And Cast(SQLITE_C_UINT, &H1ULL)))
                            Else
                                c2fb_temp_215 = arg2->pTabList
                                local71 = c2fb_temp_215
                            End If
                            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2->wctrlFlags) And Cast(SQLITE_C_INT, &H0010ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                                If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local82)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                                    c2fb_temp_216 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
                                    c2fb_temp_217 = (*c2fb_temp_216)
                                    (*c2fb_temp_216) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_217 + 1)))
                                    c2fb_temp_218 = (*c2fb_temp_216)
                                    c2fb_temp_219 = Cast(SQLITE_C_INT, c2fb_temp_218)
                                    local75 = c2fb_temp_219
                                    sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), local75)
                                Else
                                    local85 = CPtr(SqliteIndex Ptr, sqlite3PrimaryKeyIndex(CPtr(Any Ptr, local82)))
                                    c2fb_temp_220 = CPtr(SQLITE_C_INT Ptr, @(arg0->nTab))
                                    c2fb_temp_221 = (*c2fb_temp_220)
                                    (*c2fb_temp_220) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_221 + 1)))
                                    c2fb_temp_222 = Cast(SQLITE_C_INT, c2fb_temp_221)
                                    local75 = c2fb_temp_222
                                    sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 120ULL), local75, local85->nKeyCol)
                                    sqlite3VdbeSetP4KeyInfo(arg0, local85)
                                End If
                                c2fb_temp_223 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
                                c2fb_temp_224 = (*c2fb_temp_223)
                                (*c2fb_temp_223) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_224 + 1)))
                                c2fb_temp_225 = (*c2fb_temp_223)
                                c2fb_temp_226 = Cast(SQLITE_C_INT, c2fb_temp_225)
                                local76 = c2fb_temp_226
                            End If
                            c2fb_temp_227 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, &O0ULL), local74))
                            local78 = c2fb_temp_227
                            If (-Cast(SQLITE_C_INT, ((local6->nTerm > Cast(SQLITE_C_INT, 1ULL))))) Then
                                ' C automatic storage declaration
                                c2fb_temp_228 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                                local86 = c2fb_temp_228
                                While (-Cast(SQLITE_C_INT, ((local86 < local6->nTerm))))
                                    local87 = local6->a[local86].pExpr
                                    If (-Cast(SQLITE_C_INT, ((CPtr(SqliteWhereTerm Ptr, @(local6->a[local86])) = local7)))) Then
                                        Goto c2fb_flow_11
                                    End If
                                    ' empty C statement
                                    ' empty C statement
                                    ' empty C statement
                                    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local6->a[local86].wtFlags) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0004ULL))) Or Cast(SQLITE_C_INT, &H8000ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                                        Goto c2fb_flow_11
                                    End If
                                    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local6->a[local86].eOperator) And Cast(SQLITE_C_INT, &H3fffULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                                        Goto c2fb_flow_11
                                    End If
                                    If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local87)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H400000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                                        Goto c2fb_flow_11
                                    End If
                                    If (-Cast(SQLITE_C_INT, ((whereExprIsReady(arg2, arg4, local9, local87) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                                        Goto c2fb_flow_11
                                    End If
                                    c2fb_temp_230 = CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local8), CPtr(Any Ptr, local87), Cast(SQLITE_C_INT, &O0ULL)))
                                    local87 = c2fb_temp_230
                                    c2fb_temp_231 = CPtr(SqliteExpr Ptr, sqlite3ExprAnd(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local81), CPtr(Any Ptr, local87)))
                                    local81 = c2fb_temp_231
                                c2fb_flow_11:
                                    c2fb_temp_229 = local86
                                    local86 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_229 + 1)))
                                Wend
                                c2fb_flow_10:
                                If local81 Then
                                    c2fb_temp_232 = CPtr(SqliteExpr Ptr, sqlite3PExpr(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 44ULL) Or Cast(SQLITE_C_INT, &H10000ULL))), Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, local81)))
                                    local81 = c2fb_temp_232
                                End If
                            End If
                            sqlite3VdbeExplainText(arg0, Cast(SQLITE_C_INT, 1ULL), StrPtr(!"MULTI-INDEX OR"))
                            c2fb_temp_233 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                            local80 = c2fb_temp_233
                            While (-Cast(SQLITE_C_INT, ((local80 < local70->nTerm))))
                                local88 = CPtr(SqliteWhereTerm Ptr, @(local70->a[local80]))
                                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local88->leftCursor = local2)))) OrElse (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local88->eOperator) And Cast(SQLITE_C_INT, &H0400ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                                    ' C automatic storage declaration
                                    local90 = local88->pExpr
                                    ' C automatic storage declaration
                                    local92 = Cast(SQLITE_C_INT, &O0ULL)
                                    ' empty C statement
                                    c2fb_temp_235 = CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, local8), CPtr(Any Ptr, local90), Cast(SQLITE_C_INT, &O0ULL)))
                                    local90 = c2fb_temp_235
                                    c2fb_temp_236 = c2fb_temp_235
                                    local91 = c2fb_temp_236
                                    If local8->mallocFailed Then
                                        sqlite3ExprDelete(CPtr(Any Ptr, local8), CPtr(Any Ptr, local91))
                                        Goto c2fb_flow_13
                                    End If
                                    If local81 Then
                                        c2fb_temp_237 = CPtr(SqliteExpr Ptr Ptr, @(local81->pLeft))
                                        c2fb_temp_238 = local90
                                        (*c2fb_temp_237) = c2fb_temp_238
                                        c2fb_temp_239 = local81
                                        local90 = c2fb_temp_239
                                    End If
                                    sqlite3VdbeExplainInteger(arg0, Cast(SQLITE_C_INT, 1ULL), StrPtr(!"INDEX %d"), Cast(SQLITE_C_INT, (local80 + Cast(SQLITE_C_INT, 1ULL))))
                                    ' empty C statement
                                    c2fb_temp_240 = CPtr(SqliteWhereInfo Ptr, sqlite3WhereBegin(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local71), CPtr(Any Ptr, local90), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &H0020ULL), local73))
                                    local89 = c2fb_temp_240
                                    ' C unused-parameter annotation
                                    If local89 Then
                                        ' C automatic storage declaration
                                        local94 = sqlite3WhereExplainOneScan(arg0, local71, CPtr(SqliteWhereLevel Ptr, @(local89->a(Cast(SQLITE_C_INT, &O0ULL)))), Cast(SQLITE_C_INT, &O0ULL))
#ifdef SQLITE_ENABLE_STMT_SCANSTATUS
                                        sqlite3WhereAddScanStatus( _
                                            arg1, local71, _
                                            CPtr(SqliteWhereLevel Ptr, @(local89->a(Cast(SQLITE_C_INT, &O0ULL)))), _
                                            local94)
#endif
                                        ' C unused-parameter annotation
                                        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2->wctrlFlags) And Cast(SQLITE_C_INT, &H0010ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                                            local95 = (IIf(((-Cast(SQLITE_C_INT, ((local80 = Cast(SQLITE_C_INT, (local70->nTerm - Cast(SQLITE_C_INT, 1ULL)))))))), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), local80))
                                            If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local82)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                                                sqlite3ExprCodeGetColumnOfTable(CPtr(Any Ptr, arg1), CPtr(Any Ptr, local82), local2, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), local76)
                                                c2fb_temp_241 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp4Int(arg1, Cast(SQLITE_C_INT, 49ULL), local75, Cast(SQLITE_C_INT, &O0ULL), local76, local95))
                                                local92 = c2fb_temp_241
                                                ' empty C statement
                                            Else
                                                local96 = CPtr(SqliteIndex Ptr, sqlite3PrimaryKeyIndex(CPtr(Any Ptr, local82)))
                                                local97 = local96->nKeyCol
                                                ' C automatic storage declaration
                                                ' C automatic storage declaration
                                                c2fb_temp_242 = Cast(SQLITE_C_INT, sqlite3GetTempRange(CPtr(Any Ptr, arg0), local97))
                                                local99 = c2fb_temp_242
                                                c2fb_temp_243 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                                                local98 = c2fb_temp_243
                                                While (-Cast(SQLITE_C_INT, ((local98 < local97))))
                                                    local100 = local96->aiColumn[local98]
                                                    sqlite3ExprCodeGetColumnOfTable(CPtr(Any Ptr, arg1), CPtr(Any Ptr, local82), local2, local100, Cast(SQLITE_C_INT, (local99 + local98)))
                                                c2fb_flow_15:
                                                    c2fb_temp_244 = local98
                                                    local98 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_244 + 1)))
                                                Wend
                                                c2fb_flow_14:
                                                If local95 Then
                                                    c2fb_temp_245 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp4Int(arg1, Cast(SQLITE_C_INT, 29ULL), local75, Cast(SQLITE_C_INT, &O0ULL), local99, local97))
                                                    local92 = c2fb_temp_245
                                                    ' empty C statement
                                                End If
                                                If (-Cast(SQLITE_C_INT, ((local95 >= Cast(SQLITE_C_INT, &O0ULL))))) Then
                                                    sqlite3VdbeAddOp3(arg1, Cast(SQLITE_C_INT, 99ULL), local99, local97, local76)
                                                    sqlite3VdbeAddOp4Int(arg1, Cast(SQLITE_C_INT, 140ULL), local75, local76, local99, local97)
                                                    If local95 Then
                                                        sqlite3VdbeChangeP5(arg1, Cast(SQLITE_C_INT, &H10ULL))
                                                    End If
                                                End If
                                                sqlite3ReleaseTempRange(CPtr(Any Ptr, arg0), local99, local97)
                                            End If
                                        End If
                                        sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 10ULL), local74, local77)
                                        If local92 Then
                                            sqlite3VdbeJumpHere(arg1, local92)
                                        End If
                                        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local89->flags) Shr 1) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                                            c2fb_temp_246 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                                            local79 = c2fb_temp_246
                                        End If
                                        c2fb_temp_247 = local89->a(Cast(SQLITE_C_INT, &O0ULL)).pWLoop
                                        local93 = c2fb_temp_247
                                        ' C unused-parameter annotation
                                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local93->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000200ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local80 = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((CPtr(SqliteIndex Ptr, local93->u.btree.pIndex) = local72))))))))))))) AndAlso ((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local82)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) OrElse (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, (CPtr(SqliteIndex Ptr, local93->u.btree.pIndex))->flags) Shr 0) And Cast(SQLITE_C_UINT, &H3ULL))) = Cast(SQLITE_C_INT, 2ULL)))))) = 0)))))))))))) Then
                                            ' C unused-parameter annotation
                                            c2fb_temp_248 = CPtr(SqliteIndex Ptr, local93->u.btree.pIndex)
                                            local72 = c2fb_temp_248
                                        Else
                                            c2fb_temp_249 = CPtr(SqliteIndex Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                                            local72 = c2fb_temp_249
                                        End If
                                        If sqlite3WhereUsesDeferredSeek(CPtr(Any Ptr, local89)) Then
                                            c2fb_temp_250 = CPtr(SQLITE_C_UINT Ptr, @(arg2->flags))
                                            c2fb_temp_251 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                                            c2fb_temp_251 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_251) And Cast(SQLITE_C_UINT, &H1ULL)))
                                            (*c2fb_temp_250) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_250)) And Not(Cast(SQLITE_C_UINT, &H1ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_251) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 0)))
                                            c2fb_temp_251 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_251) And Cast(SQLITE_C_UINT, &H1ULL)))
                                        End If
                                        sqlite3WhereEnd(CPtr(Any Ptr, local89))
                                        sqlite3VdbeExplainPop(arg0)
                                    End If
                                    sqlite3ExprDelete(CPtr(Any Ptr, local8), CPtr(Any Ptr, local91))
                                End If
                            c2fb_flow_13:
                                c2fb_temp_234 = local80
                                local80 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_234 + 1)))
                            Wend
                            c2fb_flow_12:
                            sqlite3VdbeExplainPop(arg0)
                            ' C unused-parameter annotation
                            ' C unused-parameter annotation
                            ' C unused-parameter annotation
                            c2fb_temp_252 = CPtr(Any Ptr Ptr, @(arg4->u.pCoveringIdx))
                            c2fb_temp_253 = local72
                            (*c2fb_temp_252) = CPtr(Any Ptr, c2fb_temp_253)
                            c2fb_temp_253 = CPtr(SqliteIndex Ptr, (*c2fb_temp_252))
                            If local72 Then
                                c2fb_temp_254 = CPtr(SQLITE_C_INT Ptr, @(arg4->iIdxCur))
                                c2fb_temp_255 = Cast(SQLITE_C_INT, local73)
                                (*c2fb_temp_254) = c2fb_temp_255
                            End If
                            If local81 Then
                                c2fb_temp_256 = CPtr(SqliteExpr Ptr Ptr, @(local81->pLeft))
                                c2fb_temp_257 = CPtr(SqliteExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                                (*c2fb_temp_256) = c2fb_temp_257
                                sqlite3ExprDelete(CPtr(Any Ptr, local8), CPtr(Any Ptr, local81))
                            End If
                            sqlite3VdbeChangeP1(arg1, local78, sqlite3VdbeCurrentAddr(arg1))
                            sqlite3VdbeGoto(arg1, arg4->addrBrk)
                            sqlite3VdbeResolveLabel(arg1, local77)
                            ' C unused-parameter annotation
                            c2fb_temp_258 = CPtr(SQLITE_C_INT Ptr, @(arg4->p2))
                            c2fb_temp_259 = Cast(SQLITE_C_INT, sqlite3VdbeCurrentAddr(arg1))
                            (*c2fb_temp_258) = c2fb_temp_259
                            If (-Cast(SQLITE_C_INT, ((arg2->pTabList <> local71)))) Then
                                sqlite3DbFreeNN(CPtr(Any Ptr, local8), CPtr(Any Ptr, local71))
                            End If
                            If (-Cast(SQLITE_C_INT, (local79 = 0))) Then
                                disableTerm(arg4, local7)
                            End If
                        Else
#ifdef SQLITE_ENABLE_CURSOR_HINTS
                            codeCursorHint(local9, arg2, arg4, 0)
#endif
                            ' C static array storage
                            ' C static array storage
                            ' C unused-parameter annotation
                            If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local9->fg.flags) Shr 7) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                                c2fb_temp_260 = CPtr(u8 Ptr, @(arg4->op))
                                c2fb_temp_261 = Cast(UByte, Cast(SQLITE_C_INT, 189ULL))
                                (*c2fb_temp_260) = Cast(u8, c2fb_temp_261)
                                c2fb_temp_261 = Cast(UByte, (*c2fb_temp_260))
                            Else
                                ' empty C statement
                                c2fb_temp_262 = CPtr(u8 Ptr, @(arg4->op))
                                c2fb_temp_263 = Cast(UByte, local101(local4))
                                (*c2fb_temp_262) = Cast(u8, c2fb_temp_263)
                                c2fb_temp_263 = Cast(UByte, (*c2fb_temp_262))
                                c2fb_temp_264 = CPtr(SQLITE_C_INT Ptr, @(arg4->p1))
                                c2fb_temp_265 = Cast(SQLITE_C_INT, local2)
                                (*c2fb_temp_264) = c2fb_temp_265
                                c2fb_temp_266 = CPtr(SQLITE_C_INT Ptr, @(arg4->p2))
                                c2fb_temp_267 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 1ULL) + sqlite3VdbeAddOp2(arg1, local102(local4), local2, arg4->addrHalt))))
                                (*c2fb_temp_266) = c2fb_temp_267
                                ' empty C statement
                                ' empty C statement
                                c2fb_temp_268 = CPtr(u8 Ptr, @(arg4->p5))
                                c2fb_temp_269 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
                                (*c2fb_temp_268) = Cast(u8, c2fb_temp_269)
                                c2fb_temp_269 = Cast(UByte, (*c2fb_temp_268))
                            End If
                        End If
                    End If
                End If
            End If
        End If
    End If
    c2fb_temp_270 = Cast(SQLITE_C_INT, (IIf(local14, Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, 2ULL))))
    local15 = c2fb_temp_270
    Do
        local103 = Cast(SQLITE_C_INT, &O0ULL)
        c2fb_temp_271 = local6->a
        local7 = c2fb_temp_271
        c2fb_temp_272 = Cast(SQLITE_C_INT, local6->nTerm)
        local0 = c2fb_temp_272
        While (-Cast(SQLITE_C_INT, ((local0 > Cast(SQLITE_C_INT, &O0ULL)))))
            ' C automatic storage declaration
            local105 = Cast(SQLITE_C_INT, &O0ULL)
            ' empty C statement
            ' empty C statement
            If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local7->wtFlags) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0004ULL)))))) Then
                Goto c2fb_flow_19
            End If
            If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local7->prereqAll And arg4->notReady))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                ' empty C statement
                c2fb_temp_275 = CPtr(SQLITE_C_UINT Ptr, @(arg2->flags))
                c2fb_temp_276 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                c2fb_temp_276 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_276) And Cast(SQLITE_C_UINT, &H1ULL)))
                (*c2fb_temp_275) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_275)) And Not(Cast(SQLITE_C_UINT, &H2ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_276) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 1)))
                c2fb_temp_276 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_276) And Cast(SQLITE_C_UINT, &H1ULL)))
                Goto c2fb_flow_19
            End If
            c2fb_temp_277 = local7->pExpr
            local104 = c2fb_temp_277
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, ((whereExprIsReady(arg2, arg4, local9, local104) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                Goto c2fb_flow_19
            End If
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local15 = Cast(SQLITE_C_INT, 1ULL))))) AndAlso (-Cast(SQLITE_C_INT, (sqlite3ExprCoveredByIndex(CPtr(Any Ptr, local104), arg4->iTabCur, CPtr(Any Ptr, local14)) = 0))))))) Then
                c2fb_temp_278 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 2ULL))
                local103 = c2fb_temp_278
                Goto c2fb_flow_19
            End If
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local15 < Cast(SQLITE_C_INT, 3ULL))))) AndAlso (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local7->wtFlags) And Cast(SQLITE_C_INT, &H1000ULL)))))))) Then
                If (-Cast(SQLITE_C_INT, ((local103 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_279 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 3ULL))
                    local103 = c2fb_temp_279
                End If
                Goto c2fb_flow_19
            End If
            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local7->wtFlags) And Cast(SQLITE_C_INT, &H0200ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                local106 = arg4->iLikeRepCntr
                If (-Cast(SQLITE_C_INT, ((local106 > Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                    c2fb_temp_280 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(arg1, IIf((Cast(SQLITE_C_UINT, (local106 And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))), Cast(SQLITE_C_INT, 17ULL), Cast(SQLITE_C_INT, 16ULL)), Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, (local106 Shr Cast(SQLITE_C_INT, 1ULL)))))))
                    local105 = c2fb_temp_280
                    ' empty C statement
                    ' empty C statement
                End If
            End If
            sqlite3ExprIfFalse(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local104), local11, Cast(SQLITE_C_INT, &H10ULL))
            If local105 Then
                sqlite3VdbeJumpHere(arg1, local105)
            End If
            c2fb_temp_281 = CPtr(u16 Ptr, @(local7->wtFlags))
            c2fb_temp_282 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_281))) Or Cast(SQLITE_C_INT, &H0004ULL))))
            (*c2fb_temp_281) = Cast(u16, c2fb_temp_282)
            c2fb_temp_282 = Cast(UShort, (*c2fb_temp_281))
        c2fb_flow_19:
            c2fb_temp_273 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_273 - 1)))
            c2fb_temp_274 = local7
            local7 = (c2fb_temp_274 + 1)
        Wend
        c2fb_flow_18:
        c2fb_temp_283 = Cast(SQLITE_C_INT, local103)
        local15 = c2fb_temp_283
    c2fb_flow_17:
    Loop While (-Cast(SQLITE_C_INT, ((local15 > Cast(SQLITE_C_INT, &O0ULL)))))
    c2fb_flow_16:
    c2fb_temp_284 = local6->a
    local7 = c2fb_temp_284
    c2fb_temp_285 = Cast(SQLITE_C_INT, local6->nBase)
    local0 = c2fb_temp_285
    While (-Cast(SQLITE_C_INT, ((local0 > Cast(SQLITE_C_INT, &O0ULL)))))
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local7->wtFlags) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0004ULL)))))) Then
            Goto c2fb_flow_21
        End If
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local7->eOperator) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0080ULL))))))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_21
        End If
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local7->eOperator) And Cast(SQLITE_C_INT, &H0800ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_21
        End If
        If (-Cast(SQLITE_C_INT, ((local7->leftCursor <> local2)))) Then
            Goto c2fb_flow_21
        End If
        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local9->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H40ULL))) Or Cast(SQLITE_C_INT, &H10ULL)))))) Then
            Goto c2fb_flow_21
        End If
        c2fb_temp_288 = local7->pExpr
        local107 = c2fb_temp_288
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        c2fb_temp_289 = CPtr(SqliteWhereTerm Ptr, sqlite3WhereFindTerm(local6, local2, local7->u.x.leftColumn, arg5, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0001ULL))) Or Cast(SQLITE_C_INT, &H0080ULL))), Cast(SQLITE_C_INT, &O0ULL)))
        local109 = c2fb_temp_289
        If (-Cast(SQLITE_C_INT, ((local109 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_21
        End If
        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local109->wtFlags) And (Cast(SQLITE_C_INT, &H0004ULL)))) Then
            Goto c2fb_flow_21
        End If
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local109->pExpr)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000200ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            Goto c2fb_flow_21
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local109->eOperator) And Cast(SQLITE_C_INT, &H0001ULL)))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local109->pExpr)->flags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H001000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) AndAlso ((-Cast(SQLITE_C_INT, ((local109->pExpr->x.pSelect->pEList->nExpr > Cast(SQLITE_C_INT, 1ULL)))))))))) Then
            Goto c2fb_flow_21
        End If
        ' empty C statement
        ' empty C statement
        ' empty C statement
        ' empty C statement
        c2fb_temp_290 = (*local109->pExpr)
        local108 = c2fb_temp_290
        c2fb_temp_291 = CPtr(SqliteExpr Ptr Ptr, @(local108.pLeft))
        c2fb_temp_292 = local107->pLeft
        (*c2fb_temp_291) = c2fb_temp_292
        sqlite3ExprIfFalse(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, @(local108))), local11, Cast(SQLITE_C_INT, &H10ULL))
        c2fb_temp_293 = CPtr(u16 Ptr, @(local109->wtFlags))
        c2fb_temp_294 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_293))) Or Cast(SQLITE_C_INT, &H0004ULL))))
        (*c2fb_temp_293) = Cast(u16, c2fb_temp_294)
        c2fb_temp_294 = Cast(UShort, (*c2fb_temp_293))
    c2fb_flow_21:
        c2fb_temp_286 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_286 - 1)))
        c2fb_temp_287 = local7
        local7 = (c2fb_temp_287 + 1)
    Wend
    c2fb_flow_20:
    If CPtr(SqliteWhereRightJoin Ptr, arg4->pRJ) Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        local113 = Cast(SQLITE_C_INT, &O0ULL)
        local114 = CPtr(SqliteWhereRightJoin Ptr, arg4->pRJ)
        c2fb_temp_295 = arg2->pTabList->a(arg4->iFrom).pSTab
        local110 = c2fb_temp_295
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local110)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            c2fb_temp_296 = Cast(SQLITE_C_INT, sqlite3GetTempRange(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, 2ULL)))
            local112 = c2fb_temp_296
            sqlite3ExprCodeGetColumnOfTable(CPtr(Any Ptr, arg1), CPtr(Any Ptr, local110), arg4->iTabCur, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, (local112 + Cast(SQLITE_C_INT, 1ULL))))
            c2fb_temp_297 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
            local111 = c2fb_temp_297
        Else
            ' C automatic storage declaration
            local116 = CPtr(SqliteIndex Ptr, sqlite3PrimaryKeyIndex(CPtr(Any Ptr, local110)))
            c2fb_temp_298 = Cast(SQLITE_C_INT, local116->nKeyCol)
            local111 = c2fb_temp_298
            c2fb_temp_299 = Cast(SQLITE_C_INT, sqlite3GetTempRange(CPtr(Any Ptr, arg0), Cast(SQLITE_C_INT, (local111 + Cast(SQLITE_C_INT, 1ULL)))))
            local112 = c2fb_temp_299
            c2fb_temp_300 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local115 = c2fb_temp_300
            While (-Cast(SQLITE_C_INT, ((local115 < local111))))
                local117 = local116->aiColumn[local115]
                sqlite3ExprCodeGetColumnOfTable(CPtr(Any Ptr, arg1), CPtr(Any Ptr, local110), local2, local117, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (local112 + Cast(SQLITE_C_INT, 1ULL))) + local115)))
            c2fb_flow_23:
                c2fb_temp_301 = local115
                local115 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_301 + 1)))
            Wend
            c2fb_flow_22:
        End If
        c2fb_temp_302 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp4Int(arg1, Cast(SQLITE_C_INT, 29ULL), local114->iMatch, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, (local112 + Cast(SQLITE_C_INT, 1ULL))), local111))
        local113 = c2fb_temp_302
        ' empty C statement
        ' empty C statement
        sqlite3VdbeAddOp3(arg1, Cast(SQLITE_C_INT, 99ULL), Cast(SQLITE_C_INT, (local112 + Cast(SQLITE_C_INT, 1ULL))), local111, local112)
        sqlite3VdbeAddOp4Int(arg1, Cast(SQLITE_C_INT, 140ULL), local114->iMatch, local112, Cast(SQLITE_C_INT, (local112 + Cast(SQLITE_C_INT, 1ULL))), local111)
        If local114->regBloom Then
            sqlite3VdbeAddOp4Int(arg1, Cast(SQLITE_C_INT, 185ULL), local114->regBloom, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, (local112 + Cast(SQLITE_C_INT, 1ULL))), local111)
            sqlite3VdbeChangeP5(arg1, Cast(SQLITE_C_INT, &H10ULL))
        End If
        sqlite3VdbeJumpHere(arg1, local113)
        sqlite3ReleaseTempRange(CPtr(Any Ptr, arg0), local112, Cast(SQLITE_C_INT, (local111 + Cast(SQLITE_C_INT, 1ULL))))
    End If
    If arg4->iLeftJoin Then
        c2fb_temp_303 = CPtr(SQLITE_C_INT Ptr, @(arg4->addrFirst))
        c2fb_temp_304 = Cast(SQLITE_C_INT, sqlite3VdbeCurrentAddr(arg1))
        (*c2fb_temp_303) = c2fb_temp_304
        sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, 1ULL), arg4->iLeftJoin)
        ' empty C statement
        If (-Cast(SQLITE_C_INT, ((CPtr(SqliteWhereRightJoin Ptr, arg4->pRJ) = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_label_0
        End If
    End If
    If CPtr(SqliteWhereRightJoin Ptr, arg4->pRJ) Then
        local118 = CPtr(SqliteWhereRightJoin Ptr, arg4->pRJ)
        sqlite3VdbeAddOp2(arg1, Cast(SQLITE_C_INT, 76ULL), Cast(SQLITE_C_INT, &O0ULL), local118->regReturn)
        c2fb_temp_305 = CPtr(SQLITE_C_INT Ptr, @(local118->addrSubrtn))
        c2fb_temp_306 = Cast(SQLITE_C_INT, sqlite3VdbeCurrentAddr(arg1))
        (*c2fb_temp_305) = c2fb_temp_306
        ' C unused-parameter annotation
        c2fb_temp_307 = CPtr(u8 Ptr, @(arg0->withinRJSubrtn))
        c2fb_temp_308 = Cast(UByte, (*c2fb_temp_307))
        (*c2fb_temp_307) = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_308) + 1)))
        c2fb_label_0:
        c2fb_temp_309 = local6->a
        local7 = c2fb_temp_309
        c2fb_temp_310 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local0 = c2fb_temp_310
        While (-Cast(SQLITE_C_INT, ((local0 < local6->nBase))))
            ' empty C statement
            ' empty C statement
            If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local7->wtFlags) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0004ULL)))))) Then
                Goto c2fb_flow_25
            End If
            If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local7->prereqAll And arg4->notReady))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                ' C unused-parameter annotation
                Goto c2fb_flow_25
            End If
            If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local9->fg.jointype) And Cast(SQLITE_C_INT, &H40ULL))) Then
                Goto c2fb_flow_25
            End If
            ' C unused-parameter annotation
            sqlite3ExprIfFalse(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local7->pExpr), local11, Cast(SQLITE_C_INT, &H10ULL))
            c2fb_temp_313 = CPtr(u16 Ptr, @(local7->wtFlags))
            c2fb_temp_314 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_313))) Or Cast(SQLITE_C_INT, &H0004ULL))))
            (*c2fb_temp_313) = Cast(u16, c2fb_temp_314)
            c2fb_temp_314 = Cast(UShort, (*c2fb_temp_313))
        c2fb_flow_25:
            c2fb_temp_311 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_311 + 1)))
            c2fb_temp_312 = local7
            local7 = (c2fb_temp_312 + 1)
        Wend
        c2fb_flow_24:
    End If
    Return arg4->notReady
End Function

' c2fb skipped sqlite3WhereRightJoinLoop: outside the supported subset
/' end of sqlite3_bulk_wherecode_one_loop.bas '/
