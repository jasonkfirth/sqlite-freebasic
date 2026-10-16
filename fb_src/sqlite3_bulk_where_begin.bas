/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_bulk_where_begin.bas

    Purpose:

        Allocate WHERE planning state and generate the nested-loop plan.

    Responsibilities:

        - Allocate and initialize WhereInfo and its per-table levels.
        - Analyze WHERE terms and build candidate loops and automatic indexes.
        - Set up loop control, RIGHT JOIN handling, and query-plan state.
        - Record scan status for ordinary loops when enabled.
        - Keep translated private planning helpers beside sqlite3WhereBegin.

    This file intentionally does NOT contain:

        - Generate the per-loop VDBE body in sqlite3_bulk_wherecode_one_loop.bas.
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
#include once "sqlite3_vdbe_compare.bi"
#include once "sqlite3_walker.bi"
#include once "sqlite3_expr_types.bi"
#include once "sqlite3_vdbe_record.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_vtab_types.bi"
#include once "sqlite3_fault.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_util_numeric.bi"
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
Declare Function sqlite3ConfigCoveringIndexScanEnabled CDecl Alias "sqlite3ConfigCoveringIndexScanEnabled" () As SQLITE_C_INT
Declare Function sqlite3StrBINARYName CDecl Alias "sqlite3StrBINARYName" () As Const ZString Ptr
Declare Sub sqlite3WhereSplit CDecl Alias "sqlite3WhereSplit" (ByVal arg0 As SqliteWhereClause Ptr, ByVal arg1 As SqliteExpr Ptr, ByVal arg2 As UByte)
Declare Sub sqlite3WhereAddLimit CDecl Alias "sqlite3WhereAddLimit" (ByVal arg0 As SqliteWhereClause Ptr, ByVal arg1 As SqliteSelect Ptr)
Declare Sub sqlite3WhereTabFuncArgs CDecl Alias "sqlite3WhereTabFuncArgs" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcItem Ptr, ByVal arg2 As SqliteWhereClause Ptr)
Declare Sub sqlite3WhereClauseInit CDecl Alias "sqlite3WhereClauseInit" (ByVal arg0 As SqliteWhereClauseRecord Ptr, ByVal arg1 As SqliteWhereInfoRecord Ptr)
Declare Sub sqlite3WhereExprAnalyze CDecl Alias "sqlite3WhereExprAnalyze" (ByVal arg0 As SqliteSrcListRecord Ptr, ByVal arg1 As SqliteWhereClauseRecord Ptr)

Type c2fb_callback_8 As Sub CDecl(ByVal arg0 As Any Ptr)
Type c2fb_callback_85 As Function CDecl(ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As Any Ptr) As SQLITE_C_INT

Declare Sub createMask CDecl Alias "createMask" (ByVal arg0 As SqliteWhereMaskSet Ptr, ByVal arg1 As SQLITE_C_INT)
Declare Function findIndexCol CDecl Alias "findIndexCol" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteExprList Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SqliteIndex Ptr, ByVal arg4 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function indexColumnNotNull CDecl Alias "indexColumnNotNull" (ByVal arg0 As SqliteIndex Ptr, ByVal arg1 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function isDistinctRedundant CDecl Alias "isDistinctRedundant" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As SqliteWhereClause Ptr, ByVal arg3 As SqliteExprList Ptr) As SQLITE_C_INT
Declare Function estLog CDecl Alias "estLog" (ByVal arg0 As Short) As Short
Declare Sub translateColumnToCopy CDecl Alias "translateColumnToCopy" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SQLITE_C_INT)
Declare Function constraintCompatibleWithOuterJoin CDecl Alias "constraintCompatibleWithOuterJoin" (ByVal arg0 As Const SqliteWhereTerm Ptr, ByVal arg1 As Const SqliteSrcItem Ptr) As SQLITE_C_INT
Declare Function termCanDriveIndex CDecl Alias "termCanDriveIndex" (ByVal arg0 As Const SqliteWhereTerm Ptr, ByVal arg1 As Const SqliteSrcItem Ptr, ByVal arg2 As sqlite3_uint64) As SQLITE_C_INT
Declare Sub constructAutomaticIndex CDecl Alias "constructAutomaticIndex" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteWhereClause Ptr, ByVal arg2 As sqlite3_uint64, ByVal arg3 As SqliteWhereLevel Ptr)
Declare Sub sqlite3ConstructBloomFilter CDecl Alias "sqlite3ConstructBloomFilter" (ByVal arg0 As SqliteWhereInfo Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteWhereLevel Ptr, ByVal arg3 As sqlite3_uint64)
Declare Sub whereLoopInit CDecl Alias "whereLoopInit" (ByVal arg0 As SqliteWhereLoop Ptr)
Declare Sub whereLoopClear CDecl Alias "whereLoopClear" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteWhereLoop Ptr)
Declare Function whereLoopResize CDecl Alias "whereLoopResize" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteWhereLoop Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
Declare Sub whereInfoFree CDecl Alias "whereInfoFree" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteWhereInfo Ptr)
Declare Function exprNodePatternLengthEst CDecl Alias "exprNodePatternLengthEst" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function estLikePatternLength CDecl Alias "estLikePatternLength" (ByVal arg0 As SqliteExpr Ptr, ByVal arg1 As UShort) As SQLITE_C_INT
Declare Sub whereLoopOutputAdjust CDecl Alias "whereLoopOutputAdjust" (ByVal arg0 As SqliteWhereClause Ptr, ByVal arg1 As SqliteWhereLoop Ptr, ByVal arg2 As Short)
Declare Sub whereIndexedExprCleanup CDecl Alias "whereIndexedExprCleanup" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As Any Ptr)
Declare Function whereLoopAddBtree CDecl Alias "whereLoopAddBtree" (ByVal arg0 As SqliteWhereLoopBuilder Ptr, ByVal arg1 As sqlite3_uint64) As SQLITE_C_INT
Declare Function whereLoopAddOr CDecl Alias "whereLoopAddOr" (ByVal arg0 As SqliteWhereLoopBuilder Ptr, ByVal arg1 As sqlite3_uint64, ByVal arg2 As sqlite3_uint64) As SQLITE_C_INT
Declare Function whereLoopAddAll CDecl Alias "whereLoopAddAll" (ByVal arg0 As SqliteWhereLoopBuilder Ptr) As SQLITE_C_INT
Declare Function wherePathMatchSubqueryOB CDecl Alias "wherePathMatchSubqueryOB" (ByVal arg0 As SqliteWhereInfo Ptr, ByVal arg1 As SqliteWhereLoop Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SqliteExprList Ptr, ByVal arg5 As sqlite3_uint64 Ptr, ByVal arg6 As sqlite3_uint64 Ptr) As SQLITE_C_INT
Declare Function wherePathSatisfiesOrderBy CDecl Alias "wherePathSatisfiesOrderBy" (ByVal arg0 As SqliteWhereInfo Ptr, ByVal arg1 As SqliteExprList Ptr, ByVal arg2 As SqliteWherePath Ptr, ByVal arg3 As UShort, ByVal arg4 As UShort, ByVal arg5 As SqliteWhereLoop Ptr, ByVal arg6 As sqlite3_uint64 Ptr) As Byte
Declare Function whereSortingCost CDecl Alias "whereSortingCost" (ByVal arg0 As SqliteWhereInfo Ptr, ByVal arg1 As Short, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT) As Short
Declare Function computeMxChoice CDecl Alias "computeMxChoice" (ByVal arg0 As SqliteWhereInfo Ptr) As SQLITE_C_INT
Declare Function whereLoopIsNoBetter CDecl Alias "whereLoopIsNoBetter" (ByVal arg0 As Const SqliteWhereLoop Ptr, ByVal arg1 As Const SqliteWhereLoop Ptr) As SQLITE_C_INT
Declare Function wherePathSolver CDecl Alias "wherePathSolver" (ByVal arg0 As SqliteWhereInfo Ptr, ByVal arg1 As Short) As SQLITE_C_INT
Declare Sub whereInterstageHeuristic CDecl Alias "whereInterstageHeuristic" (ByVal arg0 As SqliteWhereInfo Ptr)
Declare Function whereShortCut CDecl Alias "whereShortCut" (ByVal arg0 As SqliteWhereLoopBuilder Ptr) As SQLITE_C_INT
Declare Function exprNodeIsDeterministic CDecl Alias "exprNodeIsDeterministic" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function exprIsDeterministic CDecl Alias "exprIsDeterministic" (ByVal arg0 As SqliteExpr Ptr) As SQLITE_C_INT
Declare Function whereOmitNoopJoin CDecl Alias "whereOmitNoopJoin" (ByVal arg0 As SqliteWhereInfo Ptr, ByVal arg1 As sqlite3_uint64) As sqlite3_uint64
Declare Sub whereCheckIfBloomFilterIsUseful CDecl Alias "whereCheckIfBloomFilterIsUseful" (ByVal arg0 As Const SqliteWhereInfo Ptr)
Declare Sub whereAddIndexedExpr CDecl Alias "whereAddIndexedExpr" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteIndex Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SqliteSrcItem Ptr)
Declare Sub whereReverseScanOrder CDecl Alias "whereReverseScanOrder" (ByVal arg0 As SqliteWhereInfo Ptr)
Declare Function sqlite3WhereBegin CDecl Alias "sqlite3WhereBegin" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As SqliteExpr Ptr, ByVal arg3 As SqliteExprList Ptr, ByVal arg4 As SqliteExprList Ptr, ByVal arg5 As SqliteSelect Ptr, ByVal arg6 As UShort, ByVal arg7 As SQLITE_C_INT) As SqliteWhereInfo Ptr
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
' c2fb skipped sqlite3WhereOutputRowCount: FreeBASIC body already exists
' c2fb skipped sqlite3WhereIsDistinct: FreeBASIC body already exists
' c2fb skipped sqlite3WhereIsOrdered: FreeBASIC body already exists
' c2fb skipped sqlite3WhereOrderByLimitOptLabel: FreeBASIC body already exists
' c2fb skipped sqlite3WhereMinMaxOptEarlyOut: FreeBASIC body already exists
' c2fb skipped sqlite3WhereContinueLabel: FreeBASIC body already exists
' c2fb skipped sqlite3WhereBreakLabel: FreeBASIC body already exists
' c2fb skipped sqlite3WhereOkOnePass: FreeBASIC body already exists
' c2fb skipped sqlite3WhereUsesDeferredSeek: FreeBASIC body already exists
' c2fb skipped whereOrMove: FreeBASIC body already exists
' c2fb skipped whereOrInsert: FreeBASIC body already exists
' c2fb skipped sqlite3WhereGetMask: FreeBASIC body already exists
' c2fb skipped sqlite3WhereMalloc: FreeBASIC body already exists
' c2fb skipped sqlite3WhereRealloc: FreeBASIC body already exists

/' ------------------------------------------------------------------------- '/
/' Translated WHERE plan initialization and loop selection '/
/' ------------------------------------------------------------------------- '/
Private Sub createMask CDecl Alias "createMask" (ByVal arg0 As SqliteWhereMaskSet Ptr, ByVal arg1 As SQLITE_C_INT)
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT

    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(SQLITE_C_INT Ptr, @(arg0->n))
    c2fb_temp_1 = (*c2fb_temp_0)
    (*c2fb_temp_0) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    c2fb_temp_2 = CPtr(SQLITE_C_INT Ptr, @(arg0->ix(c2fb_temp_1)))
    c2fb_temp_3 = Cast(SQLITE_C_INT, arg1)
    (*c2fb_temp_2) = c2fb_temp_3
End Sub

' c2fb skipped whereRightSubexprIsColumn: outside the supported subset
' c2fb skipped indexInAffinityOk: outside the supported subset
' c2fb skipped whereScanNext: FreeBASIC body already exists
' c2fb skipped whereScanInitIndexExpr: outside the supported subset
' c2fb skipped whereScanInit: FreeBASIC body already exists
' c2fb skipped sqlite3WhereFindTerm: FreeBASIC body already exists
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
        local2 = CPtr(SqliteExpr Ptr, sqlite3ExprSkipCollateAndLikely(CPtr(Any Ptr, arg1->a(local0).pExpr)))
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((local2 <> Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->op) = Cast(SQLITE_C_INT, 168ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->op) = Cast(SQLITE_C_INT, 170ULL)))))))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->iColumn) = Cast(SQLITE_C_INT, arg3->aiColumn[arg4]))))))))) AndAlso (-Cast(SQLITE_C_INT, ((local2->iTable = arg2)))))))) Then
            local3 = CPtr(sqlite3CollSeq Ptr, sqlite3ExprNNCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->a(local0).pExpr)))
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

Private Function isDistinctRedundant CDecl Alias "isDistinctRedundant" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As SqliteWhereClause Ptr, ByVal arg3 As SqliteExprList Ptr) As SQLITE_C_INT
    Dim local0 As SqliteTable Ptr
    Dim local1 As SqliteIndex Ptr
    Dim local2 As SQLITE_C_INT
    Dim local3 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SqliteTable Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim local4 As SqliteExpr Ptr
    Dim c2fb_temp_4 As SqliteIndex Ptr
    Dim c2fb_temp_5 As SqliteIndex Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, ((arg1->nSrc <> Cast(SQLITE_C_INT, 1ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = Cast(SQLITE_C_INT, arg1->a(Cast(SQLITE_C_INT, &O0ULL)).iCursor)
    local3 = c2fb_temp_0
    c2fb_temp_1 = arg1->a(Cast(SQLITE_C_INT, &O0ULL)).pSTab
    local0 = c2fb_temp_1
    c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local2 = c2fb_temp_2
    While (-Cast(SQLITE_C_INT, ((local2 < arg3->nExpr))))
        local4 = CPtr(SqliteExpr Ptr, sqlite3ExprSkipCollateAndLikely(CPtr(Any Ptr, arg3->a(local2).pExpr)))
        If ((-Cast(SQLITE_C_INT, ((local4 = Cast(SQLITE_C_INT, &O0ULL)))))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4->op) <> Cast(SQLITE_C_INT, 168ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4->op) <> Cast(SQLITE_C_INT, 170ULL))))))))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local4->iTable = local3)))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4->iColumn) < Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
    c2fb_flow_1:
        c2fb_temp_3 = local2
        local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_3 + 1)))
    Wend
    c2fb_flow_0:
    c2fb_temp_4 = CPtr(SqliteIndex Ptr, local0->pIndex)
    local1 = c2fb_temp_4
    While local1
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local1)->onError) <> Cast(SQLITE_C_INT, &O0ULL)))))) = 0))) Then
            Goto c2fb_flow_3
        End If
        If CPtr(SqliteExpr Ptr, local1->pPartIdxWhere) Then
            Goto c2fb_flow_3
        End If
        c2fb_temp_6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local2 = c2fb_temp_6
        While (-Cast(SQLITE_C_INT, ((local2 < Cast(SQLITE_C_INT, local1->nKeyCol)))))
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = CPtr(SqliteWhereTerm Ptr, sqlite3WhereFindTerm(arg2, local3, local2, Cast(sqlite3_uint64, (Not Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))), Cast(SQLITE_C_INT, &H0002ULL), local1)))))) Then
                If (-Cast(SQLITE_C_INT, ((findIndexCol(arg0, arg3, local3, local1, local2) < Cast(SQLITE_C_INT, &O0ULL))))) Then
                    Goto c2fb_flow_4
                End If
                If (-Cast(SQLITE_C_INT, ((indexColumnNotNull(local1, local2) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    Goto c2fb_flow_4
                End If
            End If
        c2fb_flow_5:
            c2fb_temp_7 = local2
            local2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_7 + 1)))
        Wend
        c2fb_flow_4:
        If (-Cast(SQLITE_C_INT, ((local2 = Cast(SQLITE_C_INT, local1->nKeyCol))))) Then
            Return Cast(SQLITE_C_INT, 1ULL)
        End If
    c2fb_flow_3:
        c2fb_temp_5 = local1->pNext
        local1 = c2fb_temp_5
    Wend
    c2fb_flow_2:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

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
            c2fb_temp_2 = CPtr(u8 Ptr, @(local1->opcode))
            c2fb_temp_3 = Cast(UByte, Cast(SQLITE_C_INT, 82ULL))
            (*c2fb_temp_2) = Cast(u8, c2fb_temp_3)
            c2fb_temp_3 = Cast(UByte, (*c2fb_temp_2))
            c2fb_temp_4 = CPtr(SQLITE_C_INT Ptr, @(local1->p1))
            c2fb_temp_5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local1->p2 + arg3)))
            (*c2fb_temp_4) = c2fb_temp_5
            c2fb_temp_6 = CPtr(SQLITE_C_INT Ptr, @(local1->p2))
            c2fb_temp_7 = Cast(SQLITE_C_INT, local1->p3)
            (*c2fb_temp_6) = c2fb_temp_7
            c2fb_temp_8 = CPtr(SQLITE_C_INT Ptr, @(local1->p3))
            c2fb_temp_9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_8) = c2fb_temp_9
            c2fb_temp_10 = CPtr(u16 Ptr, @(local1->p5))
            c2fb_temp_11 = Cast(UShort, Cast(SQLITE_C_INT, 2ULL))
            (*c2fb_temp_10) = Cast(u16, c2fb_temp_11)
            c2fb_temp_11 = Cast(UShort, (*c2fb_temp_10))
        Else
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->opcode) = Cast(SQLITE_C_INT, 137ULL))))) Then
                c2fb_temp_12 = CPtr(u8 Ptr, @(local1->opcode))
                c2fb_temp_13 = Cast(UByte, Cast(SQLITE_C_INT, 128ULL))
                (*c2fb_temp_12) = Cast(u8, c2fb_temp_13)
                c2fb_temp_13 = Cast(UByte, (*c2fb_temp_12))
                c2fb_temp_14 = CPtr(SQLITE_C_INT Ptr, @(local1->p1))
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
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg0->pExpr)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H000001ULL) Or Cast(SQLITE_C_INT, &H000002ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))) OrElse (-Cast(SQLITE_C_INT, ((arg0->pExpr->w.iJoin <> arg1->iCursor)))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H10ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg0->pExpr)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000002ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    Return Cast(SQLITE_C_INT, 1ULL)
End Function

' c2fb skipped columnIsGoodIndexCandidate: FreeBASIC body already exists
Private Function termCanDriveIndex CDecl Alias "termCanDriveIndex" (ByVal arg0 As Const SqliteWhereTerm Ptr, ByVal arg1 As Const SqliteSrcItem Ptr, ByVal arg2 As sqlite3_uint64) As SQLITE_C_INT
    Dim local0 As Byte
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As Byte

    ' C automatic storage declaration
    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, ((arg0->leftCursor <> arg1->iCursor)))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->eOperator) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0080ULL))))))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H40ULL))) Or Cast(SQLITE_C_INT, &H10ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (constraintCompatibleWithOuterJoin(arg0, arg1) = 0))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (arg0->prereqRight And arg2))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, arg0->u.x.leftColumn)
    local1 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, ((local1 < Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_1 = Cast(Byte, arg1->pSTab->aCol[local1].affinity)
    local0 = c2fb_temp_1
    If (-Cast(SQLITE_C_INT, (sqlite3IndexAffinityOk(CPtr(Any Ptr, arg0->pExpr), local0) = 0))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    ' empty C statement
    Return columnIsGoodIndexCandidate(CPtr(Const SqliteTable Ptr, arg1->pSTab), local1)
End Function

Private Sub constructAutomaticIndex CDecl Alias "constructAutomaticIndex" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteWhereClause Ptr, ByVal arg2 As sqlite3_uint64, ByVal arg3 As SqliteWhereLevel Ptr)
    Dim local0 As SQLITE_C_INT
    Dim local1 As SqliteWhereTerm Ptr
    Dim local2 As SqliteWhereTerm Ptr
    Dim local3 As SqliteIndex Ptr
    Dim local4 As SqliteVdbe Ptr
    Dim local5 As SQLITE_C_INT
    Dim local6 As SqliteTable Ptr
    Dim local7 As SQLITE_C_INT
    Dim local8 As SQLITE_C_INT
    Dim local9 As SQLITE_C_INT
    Dim local10 As SQLITE_C_INT
    Dim local11 As SQLITE_C_INT
    Dim local12 As sqlite3CollSeq Ptr
    Dim local13 As SqliteWhereLoop Ptr
    Dim local14 As ZString Ptr
    Dim local15 As sqlite3_uint64
    Dim local16 As sqlite3_uint64
    Dim local17 As UByte
    Dim local18 As UByte
    Dim local19 As SqliteExpr Ptr
    Dim local20 As SQLITE_C_INT
    Dim local21 As SqliteSrcList Ptr
    Dim local22 As SqliteSrcItem Ptr
    Dim local23 As SQLITE_C_INT
    Dim local24 As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteVdbe Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SqliteSrcList Ptr
    Dim c2fb_temp_4 As SqliteSrcItem Ptr
    Dim c2fb_temp_5 As SqliteTable Ptr
    Dim c2fb_temp_6 As SqliteWhereTerm Ptr
    Dim c2fb_temp_7 As SqliteWhereLoop Ptr
    Dim c2fb_temp_8 As sqlite3_uint64
    Dim c2fb_temp_9 As SqliteWhereTerm Ptr
    Dim c2fb_temp_10 As SqliteWhereTerm Ptr
    Dim local25 As SqliteExpr Ptr
    Dim c2fb_temp_11 As SqliteExpr Ptr
    Dim local26 As SQLITE_C_INT
    Dim local27 As sqlite3_uint64
    Dim c2fb_temp_12 As SQLITE_C_INT
    Dim c2fb_temp_13 As sqlite3_uint64
    Dim c2fb_temp_14 As UByte
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SqliteWhereTerm Ptr Ptr
    Dim c2fb_temp_17 As SqliteWhereTerm Ptr
    Dim c2fb_temp_18 As sqlite3_uint64
    Dim c2fb_temp_19 As u16 Ptr
    Dim c2fb_temp_20 As UShort
    Dim c2fb_temp_21 As u16 Ptr
    Dim c2fb_temp_22 As UShort
    Dim c2fb_temp_23 As u32 Ptr
    Dim c2fb_temp_24 As SQLITE_C_UINT
    Dim c2fb_temp_25 As sqlite3_uint64
    Dim c2fb_temp_26 As sqlite3_uint64
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim c2fb_temp_28 As SQLITE_C_INT
    Dim c2fb_temp_29 As sqlite3_uint64
    Dim c2fb_temp_30 As sqlite3_uint64
    Dim c2fb_temp_31 As SQLITE_C_INT
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As SQLITE_C_INT
    Dim c2fb_temp_34 As SQLITE_C_INT
    Dim c2fb_temp_35 As SQLITE_C_INT
    Dim c2fb_temp_36 As SqliteIndex Ptr
    Dim c2fb_temp_37 As Any Ptr Ptr
    Dim c2fb_temp_38 As SqliteIndex Ptr
    Dim c2fb_temp_39 As ZString Ptr Ptr
    Dim c2fb_temp_40 As ZString Ptr
    Dim c2fb_temp_41 As SqliteTable Ptr Ptr
    Dim c2fb_temp_42 As SqliteTable Ptr
    Dim c2fb_temp_43 As SQLITE_C_INT
    Dim c2fb_temp_44 As sqlite3_uint64
    Dim c2fb_temp_45 As SqliteWhereTerm Ptr
    Dim c2fb_temp_46 As SqliteWhereTerm Ptr
    Dim local28 As SQLITE_C_INT
    Dim local29 As sqlite3_uint64
    Dim c2fb_temp_47 As SQLITE_C_INT
    Dim c2fb_temp_48 As sqlite3_uint64
    Dim local30 As SqliteExpr Ptr
    Dim c2fb_temp_49 As sqlite3_uint64
    Dim c2fb_temp_50 As Short Ptr
    Dim c2fb_temp_51 As Short
    Dim c2fb_temp_52 As sqlite3CollSeq Ptr
    Dim c2fb_temp_53 As UByte
    Dim c2fb_temp_54 As ZString Ptr Ptr
    Dim c2fb_temp_55 As Const ZString Ptr
    Dim c2fb_temp_56 As SQLITE_C_INT
    Dim c2fb_temp_57 As SQLITE_C_INT
    Dim c2fb_temp_58 As SQLITE_C_INT
    Dim c2fb_temp_59 As Short Ptr
    Dim c2fb_temp_60 As Short
    Dim c2fb_temp_61 As ZString Ptr Ptr
    Dim c2fb_temp_62 As Const ZString Ptr
    Dim c2fb_temp_63 As SQLITE_C_INT
    Dim c2fb_temp_64 As SQLITE_C_INT
    Dim c2fb_temp_65 As SQLITE_C_INT
    Dim c2fb_temp_66 As Short Ptr
    Dim c2fb_temp_67 As Short
    Dim c2fb_temp_68 As ZString Ptr Ptr
    Dim c2fb_temp_69 As Const ZString Ptr
    Dim c2fb_temp_70 As SQLITE_C_INT
    Dim c2fb_temp_71 As Short Ptr
    Dim c2fb_temp_72 As Short
    Dim c2fb_temp_73 As ZString Ptr Ptr
    Dim c2fb_temp_74 As Const ZString Ptr
    Dim c2fb_temp_75 As SQLITE_C_INT Ptr
    Dim c2fb_temp_76 As SQLITE_C_INT
    Dim c2fb_temp_77 As SQLITE_C_INT Ptr
    Dim c2fb_temp_78 As SQLITE_C_INT
    Dim c2fb_temp_79 As SQLITE_C_INT Ptr
    Dim c2fb_temp_80 As SQLITE_C_INT
    Dim c2fb_temp_81 As SQLITE_C_INT
    Dim c2fb_temp_82 As SQLITE_C_INT Ptr
    Dim c2fb_temp_83 As SQLITE_C_INT
    Dim local31 As SQLITE_C_INT
    Dim local32 As SqliteSubquery Ptr
    Dim c2fb_temp_84 As SqliteSubquery Ptr
    Dim c2fb_temp_85 As SQLITE_C_INT
    Dim c2fb_temp_86 As SQLITE_C_INT
    Dim c2fb_temp_87 As SQLITE_C_INT
    Dim c2fb_temp_88 As SQLITE_C_INT
    Dim c2fb_temp_89 As SQLITE_C_INT
    Dim c2fb_temp_90 As u32 Ptr
    Dim c2fb_temp_91 As SQLITE_C_UINT
    Dim c2fb_temp_92 As SQLITE_C_INT
    Dim c2fb_temp_93 As SQLITE_C_INT
    Dim c2fb_temp_94 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_95 As SQLITE_C_INT

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
    ' C automatic storage declaration
    ' C automatic storage declaration
    local17 = Cast(SQLITE_C_INT, &O0ULL)
    local18 = Cast(SQLITE_C_INT, 1ULL)
    local19 = Cast(SQLITE_C_INT, &O0ULL)
    local20 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    local23 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    c2fb_temp_0 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    local4 = c2fb_temp_0
    ' C unused-parameter annotation
    c2fb_temp_1 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp0(local4, Cast(SQLITE_C_INT, 15ULL)))
    local5 = c2fb_temp_1
    ' empty C statement
    c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_2
    c2fb_temp_3 = arg1->pWInfo->pTabList
    local21 = c2fb_temp_3
    c2fb_temp_4 = CPtr(SqliteSrcItem Ptr, @(local21->a(arg3->iFrom)))
    local22 = c2fb_temp_4
    c2fb_temp_5 = local22->pSTab
    local6 = c2fb_temp_5
    c2fb_temp_6 = CPtr(SqliteWhereTerm Ptr, @(arg1->a[arg1->nTerm]))
    local2 = c2fb_temp_6
    c2fb_temp_7 = arg3->pWLoop
    local13 = c2fb_temp_7
    c2fb_temp_8 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))
    local15 = c2fb_temp_8
    c2fb_temp_9 = arg1->a
    local1 = c2fb_temp_9
    While (-Cast(SQLITE_C_INT, ((local1 < local2))))
        local25 = local1->pExpr
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1->wtFlags) And Cast(SQLITE_C_INT, &H0002ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso sqlite3ExprIsSingleTableConstraint(CPtr(Any Ptr, local25), CPtr(Any Ptr, local21), arg3->iFrom, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            c2fb_temp_11 = CPtr(SqliteExpr Ptr, sqlite3ExprAnd(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local19), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, local25), Cast(SQLITE_C_INT, &O0ULL))))))
            local19 = c2fb_temp_11
        End If
        If termCanDriveIndex(CPtr(Const SqliteWhereTerm Ptr, local1), CPtr(Const SqliteSrcItem Ptr, local22), arg2) Then
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C unused-parameter annotation
            c2fb_temp_12 = Cast(SQLITE_C_INT, local1->u.x.leftColumn)
            local26 = c2fb_temp_12
            c2fb_temp_13 = Cast(sqlite3_uint64, IIf((-Cast(SQLITE_C_INT, ((local26 >= (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))))))), (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))) - Cast(SQLITE_C_INT, 1ULL))))))), (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local26))))))
            local27 = c2fb_temp_13
            ' empty C statement
            ' empty C statement
            If (-Cast(SQLITE_C_INT, (local17 = 0))) Then
                sqlite3_log((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 28ULL) Or (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 1ULL) Shl Cast(SQLITE_C_INT, 8ULL))))))), StrPtr(!"automatic index on %s(%s)"), local6->zName, local6->aCol[local26].zCnName)
                c2fb_temp_14 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
                local17 = c2fb_temp_14
            End If
            If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local15 And local27))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                If whereLoopResize(arg0->db, local13, Cast(SQLITE_C_INT, (local0 + Cast(SQLITE_C_INT, 1ULL)))) Then
                    Goto c2fb_label_0
                End If
                c2fb_temp_15 = local0
                local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_15 + 1)))
                c2fb_temp_16 = CPtr(SqliteWhereTerm Ptr Ptr, @(local13->aLTerm[c2fb_temp_15]))
                c2fb_temp_17 = local1
                (*c2fb_temp_16) = c2fb_temp_17
                c2fb_temp_18 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local15 Or local27)))
                local15 = c2fb_temp_18
            End If
        End If
    c2fb_flow_1:
        c2fb_temp_10 = local1
        local1 = (c2fb_temp_10 + 1)
    Wend
    c2fb_flow_0:
    ' C unused-parameter annotation
    c2fb_temp_21 = CPtr(u16 Ptr, @(local13->u.btree.nEq))
    c2fb_temp_19 = CPtr(u16 Ptr, @(local13->nLTerm))
    c2fb_temp_20 = Cast(UShort, local0)
    (*c2fb_temp_19) = Cast(u16, c2fb_temp_20)
    c2fb_temp_20 = Cast(UShort, (*c2fb_temp_19))
    c2fb_temp_22 = Cast(UShort, c2fb_temp_20)
    (*c2fb_temp_21) = Cast(u16, c2fb_temp_22)
    c2fb_temp_22 = Cast(UShort, (*c2fb_temp_21))
    c2fb_temp_23 = CPtr(u32 Ptr, @(local13->wsFlags))
    c2fb_temp_24 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000001ULL) Or Cast(SQLITE_C_INT, &H00000040ULL))) Or Cast(SQLITE_C_INT, &H00000200ULL))) Or Cast(SQLITE_C_INT, &H00004000ULL))))
    (*c2fb_temp_23) = Cast(u32, c2fb_temp_24)
    c2fb_temp_24 = Cast(SQLITE_C_UINT, (*c2fb_temp_23))
    If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local6)->eTabType) = Cast(SQLITE_C_INT, 2ULL)))))) Then
        c2fb_temp_25 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))) And Cast(sqlite3_uint64, (Not local15)))))
        local16 = c2fb_temp_25
    Else
        c2fb_temp_26 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local22->colUsed And (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, (Not local15)) Or (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))) - Cast(SQLITE_C_INT, 1ULL)))))))))))))
        local16 = c2fb_temp_26
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local6)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))) Then
        c2fb_temp_27 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local10 = c2fb_temp_27
        While (-Cast(SQLITE_C_INT, ((local10 < Cast(SQLITE_C_INT, local6->nCol)))))
            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local6->aCol[local10].colFlags) And Cast(SQLITE_C_INT, &H0001ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                Goto c2fb_flow_3
            End If
            If (-Cast(SQLITE_C_INT, ((local10 >= Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))) - Cast(SQLITE_C_INT, 1ULL))))))) Then
                c2fb_temp_29 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local16 Or (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))) - Cast(SQLITE_C_INT, 1ULL))))))))))
                local16 = c2fb_temp_29
                Goto c2fb_flow_2
            End If
            If Cast(sqlite3_uint64, (local15 And (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local10)))))) Then
                Goto c2fb_flow_3
            End If
            c2fb_temp_30 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local16 Or (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local10)))))))
            local16 = c2fb_temp_30
        c2fb_flow_3:
            c2fb_temp_28 = local10
            local10 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_28 + 1)))
        Wend
        c2fb_flow_2:
    End If
    c2fb_temp_31 = Cast(SQLITE_C_INT, (IIf((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))) - Cast(SQLITE_C_INT, 1ULL)))) < Cast(SQLITE_C_INT, (local6->nCol)))))), (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))) - Cast(SQLITE_C_INT, 1ULL)))), Cast(SQLITE_C_INT, (local6->nCol)))))
    local11 = c2fb_temp_31
    ' empty C statement
    ' empty C statement
    c2fb_temp_32 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local10 = c2fb_temp_32
    While (-Cast(SQLITE_C_INT, ((local10 < local11))))
        If Cast(sqlite3_uint64, (local16 And (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local10)))))) Then
            c2fb_temp_34 = local0
            local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_34 + 1)))
        End If
    c2fb_flow_5:
        c2fb_temp_33 = local10
        local10 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_33 + 1)))
    Wend
    c2fb_flow_4:
    If Cast(sqlite3_uint64, (local22->colUsed And (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))) - Cast(SQLITE_C_INT, 1ULL))))))))) Then
        c2fb_temp_35 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local0 + Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local6->nCol) - (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))))) + Cast(SQLITE_C_INT, 1ULL))))))
        local0 = c2fb_temp_35
    End If
    ' C unused-parameter annotation
    c2fb_temp_36 = CPtr(SqliteIndex Ptr, sqlite3AllocateIndexObject(CPtr(Any Ptr, arg0->db), Cast(SQLITE_C_INT, (local0 + ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local6)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))), Cast(SQLITE_C_INT, &O0ULL), CPtr(ZString Ptr Ptr, @(local14))))
    local3 = c2fb_temp_36
    If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Goto c2fb_label_0
    End If
    c2fb_temp_37 = CPtr(Any Ptr Ptr, @(local13->u.btree.pIndex))
    c2fb_temp_38 = local3
    (*c2fb_temp_37) = CPtr(Any Ptr, c2fb_temp_38)
    c2fb_temp_38 = CPtr(SqliteIndex Ptr, (*c2fb_temp_37))
    c2fb_temp_39 = CPtr(ZString Ptr Ptr, @(local3->zName))
    c2fb_temp_40 = CPtr(ZString Ptr, StrPtr(!"auto-index"))
    (*c2fb_temp_39) = c2fb_temp_40
    c2fb_temp_41 = CPtr(SqliteTable Ptr Ptr, @(local3->pTable))
    c2fb_temp_42 = local6
    (*c2fb_temp_41) = c2fb_temp_42
    c2fb_temp_43 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local9 = c2fb_temp_43
    c2fb_temp_44 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))
    local15 = c2fb_temp_44
    c2fb_temp_45 = arg1->a
    local1 = c2fb_temp_45
    While (-Cast(SQLITE_C_INT, ((local1 < local2))))
        If termCanDriveIndex(CPtr(Const SqliteWhereTerm Ptr, local1), CPtr(Const SqliteSrcItem Ptr, local22), arg2) Then
            ' C automatic storage declaration
            ' C automatic storage declaration
            ' C unused-parameter annotation
            c2fb_temp_47 = Cast(SQLITE_C_INT, local1->u.x.leftColumn)
            local28 = c2fb_temp_47
            c2fb_temp_48 = Cast(sqlite3_uint64, IIf((-Cast(SQLITE_C_INT, ((local28 >= (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))))))), (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))) - Cast(SQLITE_C_INT, 1ULL))))))), (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local28))))))
            local29 = c2fb_temp_48
            ' empty C statement
            ' empty C statement
            If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local15 And local29))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                local30 = local1->pExpr
                c2fb_temp_49 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local15 Or local29)))
                local15 = c2fb_temp_49
                c2fb_temp_50 = CPtr(Short Ptr, @(local3->aiColumn[local9]))
                c2fb_temp_51 = Cast(Short, local1->u.x.leftColumn)
                (*c2fb_temp_50) = c2fb_temp_51
                c2fb_temp_52 = CPtr(sqlite3CollSeq Ptr, sqlite3ExprCompareCollSeq(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local30)))
                local12 = c2fb_temp_52
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, (sqlite3IsBinary(CPtr(Any Ptr, local12)) = 0))) Then
                    c2fb_temp_53 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                    local18 = c2fb_temp_53
                End If
                c2fb_temp_54 = CPtr(ZString Ptr Ptr, @(CPtr(Const ZString Ptr Ptr, local3->azColl)[local9]))
                c2fb_temp_55 = IIf(local12, CPtr(Const ZString Ptr, local12->zName), sqlite3StrBINARYName())
                (*c2fb_temp_54) = CPtr(ZString Ptr, c2fb_temp_55)
                c2fb_temp_55 = CPtr(Const ZString Ptr, (*c2fb_temp_54))
                c2fb_temp_56 = local9
                local9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_56 + 1)))
            End If
        End If
    c2fb_flow_7:
        c2fb_temp_46 = local1
        local1 = (c2fb_temp_46 + 1)
    Wend
    c2fb_flow_6:
    ' C unused-parameter annotation
    c2fb_temp_57 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local10 = c2fb_temp_57
    While (-Cast(SQLITE_C_INT, ((local10 < local11))))
        If Cast(sqlite3_uint64, (local16 And (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local10)))))) Then
            c2fb_temp_59 = CPtr(Short Ptr, @(local3->aiColumn[local9]))
            c2fb_temp_60 = Cast(Short, local10)
            (*c2fb_temp_59) = c2fb_temp_60
            c2fb_temp_61 = CPtr(ZString Ptr Ptr, @(CPtr(Const ZString Ptr Ptr, local3->azColl)[local9]))
            c2fb_temp_62 = sqlite3StrBINARYName()
            (*c2fb_temp_61) = CPtr(ZString Ptr, c2fb_temp_62)
            c2fb_temp_62 = CPtr(Const ZString Ptr, (*c2fb_temp_61))
            c2fb_temp_63 = local9
            local9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_63 + 1)))
        End If
    c2fb_flow_9:
        c2fb_temp_58 = local10
        local10 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_58 + 1)))
    Wend
    c2fb_flow_8:
    If Cast(sqlite3_uint64, (local22->colUsed And (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))) - Cast(SQLITE_C_INT, 1ULL))))))))) Then
        c2fb_temp_64 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))) - Cast(SQLITE_C_INT, 1ULL))))
        local10 = c2fb_temp_64
        While (-Cast(SQLITE_C_INT, ((local10 < Cast(SQLITE_C_INT, local6->nCol)))))
            c2fb_temp_66 = CPtr(Short Ptr, @(local3->aiColumn[local9]))
            c2fb_temp_67 = Cast(Short, local10)
            (*c2fb_temp_66) = c2fb_temp_67
            c2fb_temp_68 = CPtr(ZString Ptr Ptr, @(CPtr(Const ZString Ptr Ptr, local3->azColl)[local9]))
            c2fb_temp_69 = sqlite3StrBINARYName()
            (*c2fb_temp_68) = CPtr(ZString Ptr, c2fb_temp_69)
            c2fb_temp_69 = CPtr(Const ZString Ptr, (*c2fb_temp_68))
            c2fb_temp_70 = local9
            local9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_70 + 1)))
        c2fb_flow_11:
            c2fb_temp_65 = local10
            local10 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_65 + 1)))
        Wend
        c2fb_flow_10:
    End If
    ' C unused-parameter annotation
    If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local6)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
        c2fb_temp_71 = CPtr(Short Ptr, @(local3->aiColumn[local9]))
        c2fb_temp_72 = Cast(Short, (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))))
        (*c2fb_temp_71) = c2fb_temp_72
        c2fb_temp_73 = CPtr(ZString Ptr Ptr, @(CPtr(Const ZString Ptr Ptr, local3->azColl)[local9]))
        c2fb_temp_74 = sqlite3StrBINARYName()
        (*c2fb_temp_73) = CPtr(ZString Ptr, c2fb_temp_74)
        c2fb_temp_74 = CPtr(Const ZString Ptr, (*c2fb_temp_73))
    End If
    ' empty C statement
    ' C unused-parameter annotation
    c2fb_temp_77 = CPtr(SQLITE_C_INT Ptr, @(arg3->iIdxCur))
    c2fb_temp_75 = CPtr(SQLITE_C_INT Ptr, @(arg0->nTab))
    c2fb_temp_76 = (*c2fb_temp_75)
    (*c2fb_temp_75) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_76 + 1)))
    c2fb_temp_78 = Cast(SQLITE_C_INT, c2fb_temp_76)
    (*c2fb_temp_77) = c2fb_temp_78
    sqlite3VdbeAddOp2(local4, Cast(SQLITE_C_INT, 119ULL), arg3->iIdxCur, Cast(SQLITE_C_INT, (local0 + Cast(SQLITE_C_INT, 1ULL))))
    sqlite3VdbeSetP4KeyInfo(arg0, local3)
    ' empty C statement
    If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg0->db)->dbOptFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H00080000ULL)))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) AndAlso Cast(SQLITE_C_INT, local18))))) Then
        sqlite3WhereExplainBloomFilter(CPtr(Const SqliteParseContext Ptr, arg0), CPtr(Const SqliteWhereInfo Ptr, arg1->pWInfo), CPtr(Const SqliteWhereLevel Ptr, arg3))
        c2fb_temp_82 = CPtr(SQLITE_C_INT Ptr, @(arg3->regFilter))
        c2fb_temp_79 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
        c2fb_temp_80 = (*c2fb_temp_79)
        (*c2fb_temp_79) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_80 + 1)))
        c2fb_temp_81 = (*c2fb_temp_79)
        c2fb_temp_83 = Cast(SQLITE_C_INT, c2fb_temp_81)
        (*c2fb_temp_82) = c2fb_temp_83
        sqlite3VdbeAddOp2(local4, Cast(SQLITE_C_INT, 79ULL), Cast(SQLITE_C_INT, 10000ULL), arg3->regFilter)
    End If
    ' C unused-parameter annotation
    If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local22->fg.flags) Shr 6) And Cast(SQLITE_C_UINT, &H1ULL))) Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C unused-parameter annotation
        c2fb_temp_84 = local22->u4.pSubq
        local32 = c2fb_temp_84
        ' C unused-parameter annotation
        c2fb_temp_85 = Cast(SQLITE_C_INT, local32->regReturn)
        local31 = c2fb_temp_85
        c2fb_temp_86 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp2(local4, Cast(SQLITE_C_INT, 73ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)))
        local23 = c2fb_temp_86
        sqlite3VdbeAddOp3(local4, Cast(SQLITE_C_INT, 11ULL), local31, Cast(SQLITE_C_INT, &O0ULL), local32->addrFillSub)
        c2fb_temp_87 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(local4, Cast(SQLITE_C_INT, 12ULL), local31))
        local7 = c2fb_temp_87
        ' empty C statement
        ' empty C statement
    Else
        ' C unused-parameter annotation
        c2fb_temp_88 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp2(local4, Cast(SQLITE_C_INT, 36ULL), arg3->iTabCur, arg3->addrHalt))
        local7 = c2fb_temp_88
        ' empty C statement
    End If
    If local19 Then
        c2fb_temp_89 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
        local20 = c2fb_temp_89
        sqlite3ExprIfFalse(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local19), local20, Cast(SQLITE_C_INT, &H10ULL))
        c2fb_temp_90 = CPtr(u32 Ptr, @(local13->wsFlags))
        c2fb_temp_91 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_90)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00020000ULL)))))
        (*c2fb_temp_90) = Cast(u32, c2fb_temp_91)
        c2fb_temp_91 = Cast(SQLITE_C_UINT, (*c2fb_temp_90))
    End If
    c2fb_temp_92 = Cast(SQLITE_C_INT, sqlite3GetTempReg(CPtr(Any Ptr, arg0)))
    local8 = c2fb_temp_92
    c2fb_temp_93 = Cast(SQLITE_C_INT, sqlite3GenerateIndexKey(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local3), arg3->iTabCur, local8, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL)))
    local24 = c2fb_temp_93
    If arg3->regFilter Then
        ' C unused-parameter annotation
        sqlite3VdbeAddOp4Int(local4, Cast(SQLITE_C_INT, 185ULL), arg3->regFilter, Cast(SQLITE_C_INT, &O0ULL), local24, local13->u.btree.nEq)
    End If
    ' empty C statement
    sqlite3VdbeAddOp2(local4, Cast(SQLITE_C_INT, 140ULL), arg3->iIdxCur, local8)
    sqlite3VdbeChangeP5(local4, Cast(SQLITE_C_INT, &H10ULL))
    If local19 Then
        sqlite3VdbeResolveLabel(local4, local20)
    End If
    If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local22->fg.flags) Shr 6) And Cast(SQLITE_C_UINT, &H1ULL))) Then
        ' C unused-parameter annotation
        sqlite3VdbeChangeP2(local4, local23, Cast(SQLITE_C_INT, (local24 + local9)))
        ' empty C statement
        ' C unused-parameter annotation
        translateColumnToCopy(arg0, local7, arg3->iTabCur, local22->u4.pSubq->regResult, arg3->iIdxCur)
        sqlite3VdbeGoto(local4, local7)
        c2fb_temp_94 = CPtr(SQLITE_C_UINT Ptr, @(local22->fg.flags))
        c2fb_temp_95 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        c2fb_temp_95 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_95) And Cast(SQLITE_C_UINT, &H1ULL)))
        (*c2fb_temp_94) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_94)) And Not(Cast(SQLITE_C_UINT, &H40ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_95) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 6)))
        c2fb_temp_95 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_95) And Cast(SQLITE_C_UINT, &H1ULL)))
        sqlite3VdbeJumpHere(local4, local7)
    Else
        sqlite3VdbeAddOp2(local4, Cast(SQLITE_C_INT, 40ULL), arg3->iTabCur, Cast(SQLITE_C_INT, (local7 + Cast(SQLITE_C_INT, 1ULL))))
        ' empty C statement
        sqlite3VdbeChangeP5(local4, Cast(SQLITE_C_INT, 3ULL))
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local22->fg.jointype) And Cast(SQLITE_C_INT, &H08ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            sqlite3VdbeJumpHere(local4, local7)
        End If
    End If
    sqlite3ReleaseTempReg(CPtr(Any Ptr, arg0), local8)
    sqlite3VdbeJumpHere(local4, local5)
    ' empty C statement
    c2fb_label_0:
    sqlite3ExprDelete(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, local19))
End Sub

Private Sub sqlite3ConstructBloomFilter CDecl Alias "sqlite3ConstructBloomFilter" (ByVal arg0 As SqliteWhereInfo Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteWhereLevel Ptr, ByVal arg3 As sqlite3_uint64)
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim local2 As SQLITE_C_INT
    Dim local3 As Const SqliteWhereTerm Ptr
    Dim local4 As Const SqliteWhereTerm Ptr
    Dim local5 As SqliteParseContext Ptr
    Dim local6 As SqliteVdbe Ptr
    Dim local7 As SqliteWhereLoop Ptr
    Dim local8 As SQLITE_C_INT
    Dim local9 As SqliteIndexedExpr Ptr
    Dim local10 As SqliteIndexedExpr Ptr
    Dim c2fb_temp_0 As SqliteIndexedExpr Ptr
    Dim c2fb_temp_1 As SqliteIndexedExpr Ptr
    Dim c2fb_temp_2 As SqliteIndexedExpr Ptr Ptr
    Dim c2fb_temp_3 As SqliteIndexedExpr Ptr
    Dim c2fb_temp_4 As SqliteIndexedExpr Ptr Ptr
    Dim c2fb_temp_5 As SqliteIndexedExpr Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim local11 As Const SqliteSrcList Ptr
    Dim local12 As Const SqliteSrcItem Ptr
    Dim local13 As Const SqliteTable Ptr
    Dim local14 As sqlite3_uint64
    Dim local15 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SQLITE_C_INT Ptr
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As Const SqliteSrcList Ptr
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As Const SqliteSrcItem Ptr
    Dim c2fb_temp_17 As Const SqliteTable Ptr
    Dim c2fb_temp_18 As sqlite3_uint64
    Dim c2fb_temp_19 As sqlite3_uint64
    Dim c2fb_temp_20 As sqlite3_uint64
    Dim c2fb_temp_21 As SQLITE_C_INT
    Dim c2fb_temp_22 As Const SqliteWhereTerm Ptr
    Dim c2fb_temp_23 As Const SqliteWhereTerm Ptr
    Dim c2fb_temp_24 As Const SqliteWhereTerm Ptr
    Dim local16 As SqliteExpr Ptr
    Dim local17 As SQLITE_C_INT
    Dim local18 As SqliteIndex Ptr
    Dim local19 As SQLITE_C_INT
    Dim local20 As SQLITE_C_INT
    Dim local21 As SQLITE_C_INT
    Dim c2fb_temp_25 As SQLITE_C_INT
    Dim c2fb_temp_26 As SQLITE_C_INT
    Dim c2fb_temp_27 As u32 Ptr
    Dim c2fb_temp_28 As SQLITE_C_UINT
    Dim c2fb_temp_29 As SQLITE_C_INT
    Dim c2fb_temp_30 As SQLITE_C_INT
    Dim local22 As Const SqliteSrcItem Ptr
    Dim c2fb_temp_31 As SqliteWhereLevel Ptr
    Dim c2fb_temp_32 As Const SqliteSrcItem Ptr
    Dim c2fb_temp_33 As SqliteWhereLoop Ptr
    Dim c2fb_temp_34 As SqliteIndexedExpr Ptr Ptr
    Dim c2fb_temp_35 As SqliteIndexedExpr Ptr
    Dim c2fb_temp_36 As SqliteIndexedExpr Ptr Ptr
    Dim c2fb_temp_37 As SqliteIndexedExpr Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local5 = arg0->pParse
    local6 = CPtr(SqliteVdbe Ptr, local5->pVdbe)
    local7 = arg2->pWLoop
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    c2fb_temp_0 = local5->pIdxEpr
    local9 = c2fb_temp_0
    c2fb_temp_1 = local5->pIdxPartExpr
    local10 = c2fb_temp_1
    c2fb_temp_2 = CPtr(SqliteIndexedExpr Ptr Ptr, @(local5->pIdxEpr))
    c2fb_temp_3 = CPtr(SqliteIndexedExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_2) = c2fb_temp_3
    c2fb_temp_4 = CPtr(SqliteIndexedExpr Ptr Ptr, @(local5->pIdxPartExpr))
    c2fb_temp_5 = CPtr(SqliteIndexedExpr Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_4) = c2fb_temp_5
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_6 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp0(local6, Cast(SQLITE_C_INT, 15ULL)))
    local0 = c2fb_temp_6
    ' empty C statement
    Do
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        sqlite3WhereExplainBloomFilter(CPtr(Const SqliteParseContext Ptr, local5), CPtr(Const SqliteWhereInfo Ptr, arg0), CPtr(Const SqliteWhereLevel Ptr, arg2))
        c2fb_temp_7 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(local5))
        local2 = c2fb_temp_7
        c2fb_temp_8 = Cast(SQLITE_C_INT, arg2->iTabCur)
        local8 = c2fb_temp_8
        c2fb_temp_12 = CPtr(SQLITE_C_INT Ptr, @(arg2->regFilter))
        c2fb_temp_9 = CPtr(SQLITE_C_INT Ptr, @(local5->nMem))
        c2fb_temp_10 = (*c2fb_temp_9)
        (*c2fb_temp_9) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_10 + 1)))
        c2fb_temp_11 = (*c2fb_temp_9)
        c2fb_temp_13 = Cast(SQLITE_C_INT, c2fb_temp_11)
        (*c2fb_temp_12) = c2fb_temp_13
        c2fb_temp_14 = CPtr(Const SqliteSrcList Ptr, arg0->pTabList)
        local11 = c2fb_temp_14
        c2fb_temp_15 = Cast(SQLITE_C_INT, arg2->iFrom)
        local15 = c2fb_temp_15
        c2fb_temp_16 = CPtr(Const SqliteSrcItem Ptr, CPtr(SqliteSrcItem Ptr, @(local11->a(local15))))
        local12 = c2fb_temp_16
        ' C unused-parameter annotation
        c2fb_temp_17 = CPtr(Const SqliteTable Ptr, local12->pSTab)
        local13 = c2fb_temp_17
        ' C unused-parameter annotation
        c2fb_temp_18 = Cast(sqlite3_uint64, sqlite3LogEstToInt(local13->nRowLogEst))
        local14 = c2fb_temp_18
        If (-Cast(SQLITE_C_INT, ((local14 < Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 10000ULL)))))) Then
            c2fb_temp_19 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 10000ULL))
            local14 = c2fb_temp_19
        Else
            If (-Cast(SQLITE_C_INT, ((local14 > Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 10000000ULL)))))) Then
                c2fb_temp_20 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 10000000ULL))
                local14 = c2fb_temp_20
            End If
        End If
        ' C unused-parameter annotation
        sqlite3VdbeAddOp2(local6, Cast(SQLITE_C_INT, 79ULL), Cast(SQLITE_C_INT, local14), arg2->regFilter)
        c2fb_temp_21 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp1(local6, Cast(SQLITE_C_INT, 36ULL), local8))
        local1 = c2fb_temp_21
        ' empty C statement
        c2fb_temp_22 = CPtr(Const SqliteWhereTerm Ptr, CPtr(SqliteWhereTerm Ptr, @(arg0->sWC.a[arg0->sWC.nTerm])))
        local4 = c2fb_temp_22
        c2fb_temp_23 = CPtr(Const SqliteWhereTerm Ptr, arg0->sWC.a)
        local3 = c2fb_temp_23
        While (-Cast(SQLITE_C_INT, ((local3 < local4))))
            local16 = local3->pExpr
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local3->wtFlags) And Cast(SQLITE_C_INT, &H0002ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso sqlite3ExprIsSingleTableConstraint(CPtr(Any Ptr, local16), CPtr(Any Ptr, local11), local15, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                sqlite3ExprIfFalse(CPtr(Any Ptr, local5), CPtr(Any Ptr, local3->pExpr), local2, Cast(SQLITE_C_INT, &H10ULL))
            End If
        c2fb_flow_3:
            c2fb_temp_24 = local3
            local3 = (c2fb_temp_24 + 1)
        Wend
        c2fb_flow_2:
        If Cast(SQLITE_C_UINT, (local7->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000100ULL)))) Then
            local17 = sqlite3GetTempReg(CPtr(Any Ptr, local5))
            sqlite3VdbeAddOp2(local6, Cast(SQLITE_C_INT, 137ULL), local8, local17)
            sqlite3VdbeAddOp4Int(local6, Cast(SQLITE_C_INT, 185ULL), arg2->regFilter, Cast(SQLITE_C_INT, &O0ULL), local17, Cast(SQLITE_C_INT, 1ULL))
            sqlite3ReleaseTempReg(CPtr(Any Ptr, local5), local17)
        Else
            local18 = CPtr(SqliteIndex Ptr, local7->u.btree.pIndex)
            local19 = local7->u.btree.nEq
            local20 = sqlite3GetTempRange(CPtr(Any Ptr, local5), local19)
            ' C automatic storage declaration
            ' C unused-parameter annotation
            c2fb_temp_25 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local21 = c2fb_temp_25
            While (-Cast(SQLITE_C_INT, ((local21 < local19))))
                ' C unused-parameter annotation
                sqlite3ExprCodeLoadIndexColumn(CPtr(Any Ptr, local5), CPtr(Any Ptr, local18), local8, local21, Cast(SQLITE_C_INT, (local20 + local21)))
            c2fb_flow_5:
                c2fb_temp_26 = local21
                local21 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_26 + 1)))
            Wend
            c2fb_flow_4:
            sqlite3VdbeAddOp4Int(local6, Cast(SQLITE_C_INT, 185ULL), arg2->regFilter, Cast(SQLITE_C_INT, &O0ULL), local20, local19)
            sqlite3ReleaseTempRange(CPtr(Any Ptr, local5), local20, local19)
        End If
        sqlite3VdbeResolveLabel(local6, local2)
        sqlite3VdbeAddOp2(local6, Cast(SQLITE_C_INT, 40ULL), arg2->iTabCur, Cast(SQLITE_C_INT, (local1 + Cast(SQLITE_C_INT, 1ULL))))
        ' empty C statement
        sqlite3VdbeJumpHere(local6, local1)
        c2fb_temp_27 = CPtr(u32 Ptr, @(local7->wsFlags))
        c2fb_temp_28 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_27)) And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, &H00400000ULL)))))))
        (*c2fb_temp_27) = Cast(u32, c2fb_temp_28)
        c2fb_temp_28 = Cast(SQLITE_C_UINT, (*c2fb_temp_27))
        Do
            c2fb_temp_29 = arg1
            arg1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_29 + 1)))
            c2fb_temp_30 = arg1
            If ((-Cast(SQLITE_C_INT, ((c2fb_temp_30 < Cast(SQLITE_C_INT, arg0->nLevel))))) = 0) Then Goto c2fb_flow_6
            ' C automatic storage declaration
            c2fb_temp_31 = CPtr(SqliteWhereLevel Ptr, @(arg0->a(arg1)))
            arg2 = c2fb_temp_31
            c2fb_temp_32 = CPtr(Const SqliteSrcItem Ptr, CPtr(SqliteSrcItem Ptr, @(arg0->pTabList->a(arg2->iFrom))))
            local22 = c2fb_temp_32
            If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local22->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H40ULL)))))) Then
                Goto c2fb_flow_7
            End If
            c2fb_temp_33 = arg2->pWLoop
            local7 = c2fb_temp_33
            If ((-Cast(SQLITE_C_INT, ((local7 = Cast(SQLITE_C_INT, &O0ULL)))))) Then
                Goto c2fb_flow_7
            End If
            If Cast(sqlite3_uint64, (local7->prereq And arg3)) Then
                Goto c2fb_flow_7
            End If
            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local7->wsFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00400000ULL) Or Cast(SQLITE_C_INT, &H00000004ULL)))))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00400000ULL)))))) Then
                Goto c2fb_flow_6
            End If
        c2fb_flow_7:
        Loop
        c2fb_flow_6:
    c2fb_flow_1:
    Loop While (-Cast(SQLITE_C_INT, ((arg1 < Cast(SQLITE_C_INT, arg0->nLevel)))))
    c2fb_flow_0:
    sqlite3VdbeJumpHere(local6, local0)
    c2fb_temp_34 = CPtr(SqliteIndexedExpr Ptr Ptr, @(local5->pIdxEpr))
    c2fb_temp_35 = local9
    (*c2fb_temp_34) = c2fb_temp_35
    c2fb_temp_36 = CPtr(SqliteIndexedExpr Ptr Ptr, @(local5->pIdxPartExpr))
    c2fb_temp_37 = local10
    (*c2fb_temp_36) = c2fb_temp_37
End Sub

' c2fb skipped termFromWhereClause: outside the supported subset
' c2fb skipped allocateIndexInfo: FreeBASIC body already exists
' c2fb skipped freeIdxStr: outside the supported subset
' c2fb skipped freeIndexInfo: outside the supported subset
' c2fb skipped vtabBestIndex: outside the supported subset
' c2fb skipped whereRangeAdjust: outside the supported subset
' c2fb skipped whereRangeScanEst: outside the supported subset
Private Sub whereLoopInit CDecl Alias "whereLoopInit" (ByVal arg0 As SqliteWhereLoop Ptr)
    Dim c2fb_temp_0 As SqliteWhereTerm Ptr Ptr Ptr
    Dim c2fb_temp_1 As SqliteWhereTerm Ptr Ptr
    Dim c2fb_temp_2 As u16 Ptr
    Dim c2fb_temp_3 As UShort
    Dim c2fb_temp_4 As u16 Ptr
    Dim c2fb_temp_5 As UShort
    Dim c2fb_temp_6 As u32 Ptr
    Dim c2fb_temp_7 As SQLITE_C_UINT

    c2fb_temp_0 = CPtr(SqliteWhereTerm Ptr Ptr Ptr, @(arg0->aLTerm))
    c2fb_temp_1 = CPtr(SqliteWhereTerm Ptr Ptr, (@arg0->aLTermSpace(0)))
    (*c2fb_temp_0) = c2fb_temp_1
    c2fb_temp_2 = CPtr(u16 Ptr, @(arg0->nLTerm))
    c2fb_temp_3 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_2) = Cast(u16, c2fb_temp_3)
    c2fb_temp_3 = Cast(UShort, (*c2fb_temp_2))
    c2fb_temp_4 = CPtr(u16 Ptr, @(arg0->nLSlot))
    c2fb_temp_5 = Cast(UShort, (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, (Cast(SQLITE_C_INT, 3ULL) * SizeOf(SqliteWhereTerm Ptr)))) \ Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereTerm Ptr)))))))))
    (*c2fb_temp_4) = Cast(u16, c2fb_temp_5)
    c2fb_temp_5 = Cast(UShort, (*c2fb_temp_4))
    c2fb_temp_6 = CPtr(u32 Ptr, @(arg0->wsFlags))
    c2fb_temp_7 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_6) = Cast(u32, c2fb_temp_7)
    c2fb_temp_7 = Cast(SQLITE_C_UINT, (*c2fb_temp_6))
End Sub

' c2fb skipped whereLoopClearUnion: FreeBASIC body already exists
Private Sub whereLoopClear CDecl Alias "whereLoopClear" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteWhereLoop Ptr)
    Dim c2fb_temp_0 As SqliteWhereTerm Ptr Ptr Ptr
    Dim c2fb_temp_1 As SqliteWhereTerm Ptr Ptr
    Dim c2fb_temp_2 As u16 Ptr
    Dim c2fb_temp_3 As UShort
    Dim c2fb_temp_4 As u16 Ptr
    Dim c2fb_temp_5 As UShort
    Dim c2fb_temp_6 As u32 Ptr
    Dim c2fb_temp_7 As SQLITE_C_UINT

    If (-Cast(SQLITE_C_INT, ((arg1->aLTerm <> CPtr(SqliteWhereTerm Ptr Ptr, (@arg1->aLTermSpace(0))))))) Then
        sqlite3DbFreeNN(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->aLTerm))
        c2fb_temp_0 = CPtr(SqliteWhereTerm Ptr Ptr Ptr, @(arg1->aLTerm))
        c2fb_temp_1 = CPtr(SqliteWhereTerm Ptr Ptr, (@arg1->aLTermSpace(0)))
        (*c2fb_temp_0) = c2fb_temp_1
        c2fb_temp_2 = CPtr(u16 Ptr, @(arg1->nLSlot))
        c2fb_temp_3 = Cast(UShort, (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, (Cast(SQLITE_C_INT, 3ULL) * SizeOf(SqliteWhereTerm Ptr)))) \ Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereTerm Ptr)))))))))
        (*c2fb_temp_2) = Cast(u16, c2fb_temp_3)
        c2fb_temp_3 = Cast(UShort, (*c2fb_temp_2))
    End If
    whereLoopClearUnion(arg0, arg1)
    c2fb_temp_4 = CPtr(u16 Ptr, @(arg1->nLTerm))
    c2fb_temp_5 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_4) = Cast(u16, c2fb_temp_5)
    c2fb_temp_5 = Cast(UShort, (*c2fb_temp_4))
    c2fb_temp_6 = CPtr(u32 Ptr, @(arg1->wsFlags))
    c2fb_temp_7 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_6) = Cast(u32, c2fb_temp_7)
    c2fb_temp_7 = Cast(SQLITE_C_UINT, (*c2fb_temp_6))
End Sub

Private Function whereLoopResize CDecl Alias "whereLoopResize" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteWhereLoop Ptr, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SqliteWhereTerm Ptr Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SqliteWhereTerm Ptr Ptr
    Dim c2fb_temp_2 As Any Ptr
    Dim c2fb_temp_3 As SqliteWhereTerm Ptr Ptr Ptr
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
    c2fb_temp_2 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, local0), CPtr(Const Any Ptr, arg1->aLTerm), Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereTerm Ptr))) * Cast(sqlite3_uint64, arg1->nLSlot)))))
    If (-Cast(SQLITE_C_INT, ((arg1->aLTerm <> CPtr(SqliteWhereTerm Ptr Ptr, (@arg1->aLTermSpace(0))))))) Then
        sqlite3DbFreeNN(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1->aLTerm))
    End If
    c2fb_temp_3 = CPtr(SqliteWhereTerm Ptr Ptr Ptr, @(arg1->aLTerm))
    c2fb_temp_4 = local0
    (*c2fb_temp_3) = c2fb_temp_4
    c2fb_temp_5 = CPtr(u16 Ptr, @(arg1->nLSlot))
    c2fb_temp_6 = Cast(UShort, arg2)
    (*c2fb_temp_5) = Cast(u16, c2fb_temp_6)
    c2fb_temp_6 = Cast(UShort, (*c2fb_temp_5))
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

' c2fb skipped whereLoopXfer: outside the supported subset
' c2fb skipped whereLoopDelete: FreeBASIC body already exists
Private Sub whereInfoFree CDecl Alias "whereInfoFree" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As SqliteWhereInfo Ptr)
    Dim local0 As SqliteWhereLoop Ptr
    Dim c2fb_temp_0 As Any Ptr Ptr
    Dim c2fb_temp_1 As SqliteWhereLoop Ptr
    Dim local1 As SqliteWhereMemBlock Ptr
    Dim c2fb_temp_2 As Any Ptr Ptr
    Dim c2fb_temp_3 As SqliteWhereMemBlock Ptr

    ' C unused-parameter annotation
    ' C unused-parameter annotation
    sqlite3WhereClauseClear(CPtr(SqliteWhereClause Ptr, @(arg1->sWC)))
    While CPtr(SqliteWhereLoop Ptr, arg1->pLoops)
        local0 = CPtr(SqliteWhereLoop Ptr, arg1->pLoops)
        c2fb_temp_0 = CPtr(Any Ptr Ptr, @(arg1->pLoops))
        c2fb_temp_1 = CPtr(SqliteWhereLoop Ptr, local0->pNextLoop)
        (*c2fb_temp_0) = CPtr(Any Ptr, c2fb_temp_1)
        c2fb_temp_1 = CPtr(SqliteWhereLoop Ptr, (*c2fb_temp_0))
        whereLoopDelete(arg0, local0)
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    While CPtr(SqliteWhereMemBlock Ptr, arg1->pMemToFree)
        local1 = CPtr(SqliteWhereMemBlock Ptr, CPtr(SqliteWhereMemBlock Ptr, arg1->pMemToFree)->pNext)
        sqlite3DbNNFreeNN(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteWhereMemBlock Ptr, arg1->pMemToFree)))
        c2fb_temp_2 = CPtr(Any Ptr Ptr, @(arg1->pMemToFree))
        c2fb_temp_3 = local1
        (*c2fb_temp_2) = CPtr(Any Ptr, c2fb_temp_3)
        c2fb_temp_3 = CPtr(SqliteWhereMemBlock Ptr, (*c2fb_temp_2))
    c2fb_flow_3:
    Wend
    c2fb_flow_2:
    sqlite3DbNNFreeNN(CPtr(Any Ptr, arg0), CPtr(Any Ptr, arg1))
End Sub

' c2fb skipped whereLoopCheaperProperSubset: outside the supported subset
' c2fb skipped whereLoopAdjustCost: outside the supported subset
' c2fb skipped whereLoopFindLesser: outside the supported subset
' c2fb skipped whereLoopInsert: FreeBASIC body already exists
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
            c2fb_temp_11 = CPtr(SQLITE_C_INT Ptr, @(arg0->u.sz))
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
    Dim c2fb_temp_5 As c2fb_callback_85
    Dim c2fb_temp_6 As SqliteWalkerSelectCallback Ptr
    Dim c2fb_temp_7 As c2fb_callback_85

    ' C automatic storage declaration
    c2fb_temp_0 = CPtr(SQLITE_C_INT Ptr, @(local0.u.sz))
    c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_0) = c2fb_temp_1
    c2fb_temp_2 = CPtr(UShort Ptr, @(local0.eCode))
    c2fb_temp_3 = Cast(UShort, arg1)
    (*c2fb_temp_2) = c2fb_temp_3
    c2fb_temp_4 = CPtr(SqliteWalkerExprCallback Ptr, @(local0.xExprCallback))
    c2fb_temp_5 = CPtr(c2fb_callback_85, ProcPtr(exprNodePatternLengthEst))
    (*c2fb_temp_4) = Cast(SqliteWalkerExprCallback, c2fb_temp_5)
    c2fb_temp_5 = CPtr(c2fb_callback_85, (*c2fb_temp_4))
    c2fb_temp_6 = CPtr(SqliteWalkerSelectCallback Ptr, @(local0.xSelectCallback))
    c2fb_temp_7 = CPtr(c2fb_callback_85, ProcPtr(sqlite3SelectWalkFail))
    (*c2fb_temp_6) = Cast(SqliteWalkerSelectCallback, c2fb_temp_7)
    c2fb_temp_7 = CPtr(c2fb_callback_85, (*c2fb_temp_6))
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
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg0->pWInfo->pTabList->nSrc <= Cast(SQLITE_C_INT, 1ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((arg0->pWInfo->pOrderBy = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        Return
    End If
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, arg0->nBase)
    local3 = c2fb_temp_0
    c2fb_temp_1 = arg0->a
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
            c2fb_temp_6 = arg1->aLTerm[local4]
            local1 = c2fb_temp_6
            If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                Goto c2fb_flow_3
            End If
            If (-Cast(SQLITE_C_INT, ((local1 = local0)))) Then
                Goto c2fb_flow_2
            End If
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local1->iParent >= Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((CPtr(SqliteWhereTerm Ptr, @(arg0->a[local1->iParent]))) = local0)))))))) Then
                Goto c2fb_flow_2
            End If
        c2fb_flow_3:
            c2fb_temp_5 = local4
            local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_5 - 1)))
        Wend
        c2fb_flow_2:
        If (-Cast(SQLITE_C_INT, ((local4 < Cast(SQLITE_C_INT, &O0ULL))))) Then
            sqlite3ProgressCheck(CPtr(Any Ptr, arg0->pWInfo->pParse))
            If (-Cast(SQLITE_C_INT, ((arg1->maskSelf = local0->prereqAll)))) Then
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->eOperator) And Cast(SQLITE_C_INT, &H3fULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->pWInfo->pTabList->a(arg1->iTab).fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H40ULL))))))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                    c2fb_temp_7 = CPtr(u32 Ptr, @(arg1->wsFlags))
                    c2fb_temp_8 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_7)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00800000ULL)))))
                    (*c2fb_temp_7) = Cast(u32, c2fb_temp_8)
                    c2fb_temp_8 = Cast(SQLITE_C_UINT, (*c2fb_temp_7))
                End If
            End If
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local0->truthProb) <= Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_9 = CPtr(Short Ptr, @(arg1->nOut))
                c2fb_temp_10 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (*c2fb_temp_9)) + Cast(SQLITE_C_INT, local0->truthProb))))
                (*c2fb_temp_9) = c2fb_temp_10
            Else
                local6 = local0->pExpr
                c2fb_temp_11 = CPtr(Short Ptr, @(arg1->nOut))
                c2fb_temp_12 = (*c2fb_temp_11)
                (*c2fb_temp_11) = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_12) - 1)))
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->eOperator) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0080ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->wtFlags) And Cast(SQLITE_C_INT, &O0ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                    local7 = local6->pRight
                    local8 = arg0->pWInfo->pParse
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
                        c2fb_temp_15 = CPtr(u16 Ptr, @(local0->wtFlags))
                        c2fb_temp_16 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_15))) Or Cast(SQLITE_C_INT, &H2000ULL))))
                        (*c2fb_temp_15) = Cast(u16, c2fb_temp_16)
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
                            local12 = local6->x.pList->a(Cast(SQLITE_C_INT, &O0ULL)).pExpr
                            c2fb_temp_19 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, ((local10 = Cast(SQLITE_C_INT, 65ULL))))))
                            local10 = c2fb_temp_19
                            c2fb_temp_20 = Cast(SQLITE_C_INT, estLikePatternLength(local12, local10))
                            local11 = c2fb_temp_20
                            If (-Cast(SQLITE_C_INT, ((local11 > Cast(SQLITE_C_INT, &O0ULL))))) Then
                                c2fb_temp_21 = CPtr(Short Ptr, @(arg1->nOut))
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
        c2fb_temp_23 = CPtr(Short Ptr, @(arg1->nOut))
        c2fb_temp_24 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg2) - Cast(SQLITE_C_INT, local5))))
        (*c2fb_temp_23) = c2fb_temp_24
    End If
End Sub

' c2fb skipped whereRangeVectorLen: outside the supported subset
' c2fb skipped whereLoopAddBtreeIndex: FreeBASIC body already exists
' c2fb skipped indexMightHelpWithOrderBy: FreeBASIC body already exists
' c2fb skipped whereUsablePartialIndex: FreeBASIC body already exists
' c2fb skipped exprIsCoveredByIndex: outside the supported subset
' c2fb skipped whereIsCoveringIndexWalkCallback: outside the supported subset
' c2fb skipped whereIsCoveringIndex: FreeBASIC body already exists
Private Sub whereIndexedExprCleanup CDecl Alias "whereIndexedExprCleanup" (ByVal arg0 As sqlite3 Ptr, ByVal arg1 As Any Ptr)
    Dim local0 As SqliteIndexedExpr Ptr Ptr
    Dim local1 As SqliteIndexedExpr Ptr
    Dim c2fb_temp_0 As SqliteIndexedExpr Ptr Ptr
    Dim c2fb_temp_1 As SqliteIndexedExpr Ptr

    local0 = CPtr(SqliteIndexedExpr Ptr Ptr, arg1)
    While (-Cast(SQLITE_C_INT, (((*local0) <> Cast(SQLITE_C_INT, &O0ULL)))))
        local1 = (*local0)
        c2fb_temp_0 = CPtr(SqliteIndexedExpr Ptr Ptr, @((*local0)))
        c2fb_temp_1 = local1->pIENext
        (*c2fb_temp_0) = c2fb_temp_1
        sqlite3ExprDelete(CPtr(Any Ptr, arg0), CPtr(Any Ptr, CPtr(SqliteExpr Ptr, local1->pExpr)))
        sqlite3DbFreeNN(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local1))
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
End Sub

' c2fb skipped wherePartIdxExpr: FreeBASIC body already exists
Private Function whereLoopAddBtree CDecl Alias "whereLoopAddBtree" (ByVal arg0 As SqliteWhereLoopBuilder Ptr, ByVal arg1 As sqlite3_uint64) As SQLITE_C_INT
    Dim local0 As SqliteWhereInfo Ptr
    Dim local1 As SqliteIndex Ptr
    Dim local2 As SqliteIndex
    Dim local3(0 To 1) As Short
    Dim local4 As Short
    Dim local5 As SqliteSrcList Ptr
    Dim local6 As SqliteSrcItem Ptr
    Dim local7 As SqliteWhereLoop Ptr
    Dim local8 As SQLITE_C_INT
    Dim local9 As SQLITE_C_INT
    Dim local10 As SQLITE_C_INT
    Dim local11 As Short
    Dim local12 As SqliteWhereClause Ptr
    Dim local13 As SqliteTable Ptr
    Dim c2fb_temp_0 As SqliteWhereLoop Ptr
    Dim c2fb_temp_1 As SqliteWhereInfo Ptr
    Dim c2fb_temp_2 As SqliteSrcList Ptr
    Dim c2fb_temp_3 As SqliteSrcItem Ptr
    Dim c2fb_temp_4 As SqliteTable Ptr
    Dim c2fb_temp_5 As SqliteWhereClause Ptr
    Dim c2fb_temp_6 As SqliteIndex Ptr
    Dim c2fb_temp_7 As SqliteIndex Ptr
    Dim local14 As SqliteIndex Ptr
    Dim c2fb_temp_8 As Any Ptr
    Dim c2fb_temp_9 As u16 Ptr
    Dim c2fb_temp_10 As UShort
    Dim c2fb_temp_11 As u16 Ptr
    Dim c2fb_temp_12 As UShort
    Dim c2fb_temp_13 As Short Ptr Ptr
    Dim c2fb_temp_14 As Short Ptr
    Dim c2fb_temp_15 As Short Ptr Ptr
    Dim c2fb_temp_16 As Short Ptr
    Dim c2fb_temp_17 As u8 Ptr
    Dim c2fb_temp_18 As UByte
    Dim c2fb_temp_19 As SqliteTable Ptr Ptr
    Dim c2fb_temp_20 As SqliteTable Ptr
    Dim c2fb_temp_21 As Short Ptr
    Dim c2fb_temp_22 As Short
    Dim c2fb_temp_23 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As Short Ptr
    Dim c2fb_temp_26 As Short
    Dim c2fb_temp_27 As Short Ptr
    Dim c2fb_temp_28 As Short
    Dim c2fb_temp_29 As SqliteIndex Ptr
    Dim c2fb_temp_30 As SqliteIndex Ptr Ptr
    Dim c2fb_temp_31 As SqliteIndex Ptr
    Dim c2fb_temp_32 As SqliteIndex Ptr
    Dim c2fb_temp_33 As Short
    Dim local15 As Short
    Dim local16 As SqliteWhereTerm Ptr
    Dim local17 As SqliteWhereTerm Ptr
    Dim c2fb_temp_34 As Short
    Dim c2fb_temp_35 As SqliteWhereTerm Ptr
    Dim c2fb_temp_36 As SqliteWhereTerm Ptr
    Dim c2fb_temp_37 As u16 Ptr
    Dim c2fb_temp_38 As UShort
    Dim c2fb_temp_39 As u16 Ptr
    Dim c2fb_temp_40 As UShort
    Dim c2fb_temp_41 As Any Ptr Ptr
    Dim c2fb_temp_42 As SqliteIndex Ptr
    Dim c2fb_temp_43 As u16 Ptr
    Dim c2fb_temp_44 As UShort
    Dim c2fb_temp_45 As SqliteWhereTerm Ptr Ptr
    Dim c2fb_temp_46 As SqliteWhereTerm Ptr
    Dim c2fb_temp_47 As Short Ptr
    Dim c2fb_temp_48 As Short
    Dim c2fb_temp_49 As Short Ptr
    Dim c2fb_temp_50 As Short
    Dim c2fb_temp_51 As Short Ptr
    Dim c2fb_temp_52 As Short
    Dim c2fb_temp_53 As Short Ptr
    Dim c2fb_temp_54 As Short
    Dim c2fb_temp_55 As Short Ptr
    Dim c2fb_temp_56 As Short
    Dim c2fb_temp_57 As Short Ptr
    Dim c2fb_temp_58 As Short
    Dim c2fb_temp_59 As u32 Ptr
    Dim c2fb_temp_60 As SQLITE_C_UINT
    Dim c2fb_temp_61 As sqlite3_uint64 Ptr
    Dim c2fb_temp_62 As sqlite3_uint64
    Dim c2fb_temp_63 As SQLITE_C_INT
    Dim c2fb_temp_64 As SqliteIndex Ptr
    Dim c2fb_temp_65 As SQLITE_C_INT
    Dim c2fb_temp_66 As Short
    Dim c2fb_temp_67 As u16 Ptr
    Dim c2fb_temp_68 As UShort
    Dim c2fb_temp_69 As u16 Ptr
    Dim c2fb_temp_70 As UShort
    Dim c2fb_temp_71 As u16 Ptr
    Dim c2fb_temp_72 As UShort
    Dim c2fb_temp_73 As u16 Ptr
    Dim c2fb_temp_74 As UShort
    Dim c2fb_temp_75 As u16 Ptr
    Dim c2fb_temp_76 As UShort
    Dim c2fb_temp_77 As u16 Ptr
    Dim c2fb_temp_78 As UShort
    Dim c2fb_temp_79 As u8 Ptr
    Dim c2fb_temp_80 As UByte
    Dim c2fb_temp_81 As Short Ptr
    Dim c2fb_temp_82 As Short
    Dim c2fb_temp_83 As sqlite3_uint64 Ptr
    Dim c2fb_temp_84 As sqlite3_uint64
    Dim c2fb_temp_85 As Short Ptr
    Dim c2fb_temp_86 As Short
    Dim c2fb_temp_87 As Any Ptr Ptr
    Dim c2fb_temp_88 As SqliteIndex Ptr
    Dim c2fb_temp_89 As Any Ptr Ptr
    Dim c2fb_temp_90 As SqliteExprList Ptr
    Dim c2fb_temp_91 As SQLITE_C_INT
    Dim c2fb_temp_92 As u32 Ptr
    Dim c2fb_temp_93 As SQLITE_C_UINT
    Dim c2fb_temp_94 As u8 Ptr
    Dim c2fb_temp_95 As UByte
    Dim c2fb_temp_96 As Short Ptr
    Dim c2fb_temp_97 As Short
    Dim c2fb_temp_98 As u32 Ptr
    Dim c2fb_temp_99 As SQLITE_C_UINT
    Dim c2fb_temp_100 As Any Ptr Ptr
    Dim c2fb_temp_101 As SqliteExprList Ptr
    Dim c2fb_temp_102 As Short Ptr
    Dim c2fb_temp_103 As Short
    Dim c2fb_temp_104 As SQLITE_C_INT
    Dim c2fb_temp_105 As Short Ptr
    Dim c2fb_temp_106 As Short
    Dim local18 As sqlite3_uint64
    Dim c2fb_temp_107 As sqlite3_uint64
    Dim c2fb_temp_108 As u32 Ptr
    Dim c2fb_temp_109 As SQLITE_C_UINT
    Dim c2fb_temp_110 As sqlite3_uint64
    Dim c2fb_temp_111 As u32 Ptr
    Dim c2fb_temp_112 As SQLITE_C_UINT
    Dim local19 As SQLITE_C_UINT
    Dim c2fb_temp_113 As sqlite3_uint64
    Dim c2fb_temp_114 As u32 Ptr
    Dim c2fb_temp_115 As SQLITE_C_UINT
    Dim c2fb_temp_116 As u32 Ptr
    Dim c2fb_temp_117 As SQLITE_C_UINT
    Dim c2fb_temp_118 As u8 Ptr
    Dim c2fb_temp_119 As UByte
    Dim c2fb_temp_120 As Short Ptr
    Dim c2fb_temp_121 As Short
    Dim local20 As Short
    Dim local21 As SQLITE_C_INT
    Dim local22 As SQLITE_C_INT
    Dim local23 As SqliteWhereClause Ptr
    Dim c2fb_temp_122 As SQLITE_C_INT
    Dim c2fb_temp_123 As SQLITE_C_INT
    Dim local24 As SqliteWhereTerm Ptr
    Dim c2fb_temp_124 As Short
    Dim c2fb_temp_125 As Short
    Dim c2fb_temp_126 As Short
    Dim c2fb_temp_127 As Short Ptr
    Dim c2fb_temp_128 As Short
    Dim c2fb_temp_129 As Short Ptr
    Dim c2fb_temp_130 As Short
    Dim c2fb_temp_131 As SQLITE_C_INT
    Dim c2fb_temp_132 As Short Ptr
    Dim c2fb_temp_133 As Short
    Dim c2fb_temp_134 As u8 Ptr
    Dim c2fb_temp_135 As UByte
    Dim c2fb_temp_136 As SQLITE_C_INT
    Dim c2fb_temp_137 As u32 Ptr
    Dim c2fb_temp_138 As SQLITE_C_UINT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic array storage
    local4 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local8 = Cast(SQLITE_C_INT, &O0ULL)
    local9 = Cast(SQLITE_C_INT, 1ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    c2fb_temp_0 = arg0->pNew
    local7 = c2fb_temp_0
    c2fb_temp_1 = CPtr(SqliteWhereInfo Ptr, arg0->pWInfo)
    local0 = c2fb_temp_1
    c2fb_temp_2 = local0->pTabList
    local5 = c2fb_temp_2
    c2fb_temp_3 = CPtr(SqliteSrcItem Ptr, (CPtr(SqliteSrcItem Ptr, (@local5->a(0))) + local7->iTab))
    local6 = c2fb_temp_3
    c2fb_temp_4 = local6->pSTab
    local13 = c2fb_temp_4
    c2fb_temp_5 = CPtr(SqliteWhereClause Ptr, arg0->pWC)
    local12 = c2fb_temp_5
    ' C unused-parameter annotation
    If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local6->fg.flags) Shr 1) And Cast(SQLITE_C_UINT, &H1ULL))) Then
        ' C unused-parameter annotation
        c2fb_temp_6 = local6->u2.pIBIndex
        local1 = c2fb_temp_6
    Else
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local13)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))) Then
            c2fb_temp_7 = CPtr(SqliteIndex Ptr, local13->pIndex)
            local1 = c2fb_temp_7
        Else
            ' C automatic storage declaration
            c2fb_temp_8 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteIndex Ptr, @(local2))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteIndex))))
            c2fb_temp_9 = CPtr(u16 Ptr, @(local2.nKeyCol))
            c2fb_temp_10 = Cast(UShort, Cast(SQLITE_C_INT, 1ULL))
            (*c2fb_temp_9) = Cast(u16, c2fb_temp_10)
            c2fb_temp_10 = Cast(UShort, (*c2fb_temp_9))
            c2fb_temp_11 = CPtr(u16 Ptr, @(local2.nColumn))
            c2fb_temp_12 = Cast(UShort, Cast(SQLITE_C_INT, 1ULL))
            (*c2fb_temp_11) = Cast(u16, c2fb_temp_12)
            c2fb_temp_12 = Cast(UShort, (*c2fb_temp_11))
            c2fb_temp_13 = CPtr(Short Ptr Ptr, @(local2.aiColumn))
            c2fb_temp_14 = CPtr(Short Ptr, @(local4))
            (*c2fb_temp_13) = c2fb_temp_14
            c2fb_temp_15 = CPtr(Short Ptr Ptr, @(local2.aiRowLogEst))
            c2fb_temp_16 = CPtr(Short Ptr, (@local3(0)))
            (*c2fb_temp_15) = c2fb_temp_16
            c2fb_temp_17 = CPtr(u8 Ptr, @(local2.onError))
            c2fb_temp_18 = Cast(UByte, Cast(SQLITE_C_INT, 5ULL))
            (*c2fb_temp_17) = Cast(u8, c2fb_temp_18)
            c2fb_temp_18 = Cast(UByte, (*c2fb_temp_17))
            c2fb_temp_19 = CPtr(SqliteTable Ptr Ptr, @(local2.pTable))
            c2fb_temp_20 = local13
            (*c2fb_temp_19) = c2fb_temp_20
            c2fb_temp_21 = CPtr(Short Ptr, @(local2.szIdxRow))
            c2fb_temp_22 = Cast(Short, Cast(SQLITE_C_INT, 3ULL))
            (*c2fb_temp_21) = c2fb_temp_22
            c2fb_temp_23 = CPtr(SQLITE_C_UINT Ptr, @(local2.flags))
            c2fb_temp_24 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 3ULL))
            c2fb_temp_24 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_24) And Cast(SQLITE_C_UINT, &H3ULL)))
            (*c2fb_temp_23) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_23)) And Not(Cast(SQLITE_C_UINT, &H3ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_24) And Cast(SQLITE_C_UINT, &H3ULL)) Shl 0)))
            c2fb_temp_24 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_24) And Cast(SQLITE_C_UINT, &H3ULL)))
            c2fb_temp_25 = CPtr(Short Ptr, @(local3(Cast(SQLITE_C_INT, &O0ULL))))
            c2fb_temp_26 = Cast(Short, local13->nRowLogEst)
            (*c2fb_temp_25) = c2fb_temp_26
            c2fb_temp_27 = CPtr(Short Ptr, @(local3(Cast(SQLITE_C_INT, 1ULL))))
            c2fb_temp_28 = Cast(Short, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_27) = c2fb_temp_28
            c2fb_temp_29 = CPtr(SqliteIndex Ptr, local6->pSTab->pIndex)
            local14 = c2fb_temp_29
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local6->fg.flags) Shr 0) And Cast(SQLITE_C_UINT, &H1ULL))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_30 = CPtr(SqliteIndex Ptr Ptr, @(local2.pNext))
                c2fb_temp_31 = local14
                (*c2fb_temp_30) = c2fb_temp_31
            End If
            c2fb_temp_32 = CPtr(SqliteIndex Ptr, @(local2))
            local1 = c2fb_temp_32
        End If
    End If
    c2fb_temp_33 = Cast(Short, local13->nRowLogEst)
    local11 = c2fb_temp_33
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (CPtr(SqliteWhereOrSet Ptr, arg0->pOrSet) = 0))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->wctrlFlags) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H1000ULL) Or Cast(SQLITE_C_INT, &H0020ULL))))))) = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local0->pParse->db->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &H00008000ULL))))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local6->fg.flags) Shr 1) And Cast(SQLITE_C_UINT, &H1ULL))) = 0))))))) AndAlso (-Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local6->fg.flags) Shr 0) And Cast(SQLITE_C_UINT, &H1ULL))) = 0))))))) AndAlso (-Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local6->fg.flags) Shr 4) And Cast(SQLITE_C_UINT, &H1ULL))) = 0))))))) AndAlso (-Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local6->fg.flags) Shr 7) And Cast(SQLITE_C_UINT, &H1ULL))) = 0))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local6->fg.jointype) And Cast(SQLITE_C_INT, &H10ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        local17 = CPtr(SqliteWhereTerm Ptr, (local12->a + local12->nTerm))
        c2fb_temp_34 = Cast(Short, estLog(local11))
        local15 = c2fb_temp_34
        c2fb_temp_35 = local12->a
        local16 = c2fb_temp_35
        While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local16 < local17))))))))
            If Cast(sqlite3_uint64, (local16->prereqRight And local7->maskSelf)) Then
                Goto c2fb_flow_1
            End If
            If termCanDriveIndex(CPtr(Const SqliteWhereTerm Ptr, local16), CPtr(Const SqliteSrcItem Ptr, local6), Cast(SQLITE_C_INT, &O0ULL)) Then
                c2fb_temp_37 = CPtr(u16 Ptr, @(local7->u.btree.nEq))
                c2fb_temp_38 = Cast(UShort, Cast(SQLITE_C_INT, 1ULL))
                (*c2fb_temp_37) = Cast(u16, c2fb_temp_38)
                c2fb_temp_38 = Cast(UShort, (*c2fb_temp_37))
                c2fb_temp_39 = CPtr(u16 Ptr, @(local7->nSkip))
                c2fb_temp_40 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_39) = Cast(u16, c2fb_temp_40)
                c2fb_temp_40 = Cast(UShort, (*c2fb_temp_39))
                c2fb_temp_41 = CPtr(Any Ptr Ptr, @(local7->u.btree.pIndex))
                c2fb_temp_42 = CPtr(SqliteIndex Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                (*c2fb_temp_41) = CPtr(Any Ptr, c2fb_temp_42)
                c2fb_temp_42 = CPtr(SqliteIndex Ptr, (*c2fb_temp_41))
                c2fb_temp_43 = CPtr(u16 Ptr, @(local7->nLTerm))
                c2fb_temp_44 = Cast(UShort, Cast(SQLITE_C_INT, 1ULL))
                (*c2fb_temp_43) = Cast(u16, c2fb_temp_44)
                c2fb_temp_44 = Cast(UShort, (*c2fb_temp_43))
                c2fb_temp_45 = CPtr(SqliteWhereTerm Ptr Ptr, @(local7->aLTerm[Cast(SQLITE_C_INT, &O0ULL)]))
                c2fb_temp_46 = local16
                (*c2fb_temp_45) = c2fb_temp_46
                c2fb_temp_47 = CPtr(Short Ptr, @(local7->rSetup))
                c2fb_temp_48 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local15) + Cast(SQLITE_C_INT, local11))))
                (*c2fb_temp_47) = c2fb_temp_48
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local13)->eTabType) = Cast(SQLITE_C_INT, 2ULL)))))) = 0))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local13->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00004000ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
                    c2fb_temp_49 = CPtr(Short Ptr, @(local7->rSetup))
                    c2fb_temp_50 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (*c2fb_temp_49)) + Cast(SQLITE_C_INT, 28ULL))))
                    (*c2fb_temp_49) = c2fb_temp_50
                Else
                    c2fb_temp_51 = CPtr(Short Ptr, @(local7->rSetup))
                    c2fb_temp_52 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (*c2fb_temp_51)) - Cast(SQLITE_C_INT, 25ULL))))
                    (*c2fb_temp_51) = c2fb_temp_52
                End If
                ' empty C statement
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local7->rSetup) < Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_53 = CPtr(Short Ptr, @(local7->rSetup))
                    c2fb_temp_54 = Cast(Short, Cast(SQLITE_C_INT, &O0ULL))
                    (*c2fb_temp_53) = c2fb_temp_54
                End If
                c2fb_temp_55 = CPtr(Short Ptr, @(local7->nOut))
                c2fb_temp_56 = Cast(Short, Cast(SQLITE_C_INT, 43ULL))
                (*c2fb_temp_55) = c2fb_temp_56
                ' C unused-parameter annotation
                c2fb_temp_57 = CPtr(Short Ptr, @(local7->rRun))
                c2fb_temp_58 = Cast(Short, sqlite3LogEstAdd(local15, local7->nOut))
                (*c2fb_temp_57) = c2fb_temp_58
                c2fb_temp_59 = CPtr(u32 Ptr, @(local7->wsFlags))
                c2fb_temp_60 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00004000ULL))
                (*c2fb_temp_59) = Cast(u32, c2fb_temp_60)
                c2fb_temp_60 = Cast(SQLITE_C_UINT, (*c2fb_temp_59))
                c2fb_temp_61 = CPtr(sqlite3_uint64 Ptr, @(local7->prereq))
                c2fb_temp_62 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (arg1 Or local16->prereqRight)))
                (*c2fb_temp_61) = c2fb_temp_62
                c2fb_temp_63 = Cast(SQLITE_C_INT, whereLoopInsert(arg0, local7))
                local8 = c2fb_temp_63
            End If
        c2fb_flow_1:
            c2fb_temp_36 = local16
            local16 = (c2fb_temp_36 + 1)
        Wend
        c2fb_flow_0:
    End If
    While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso local1))))
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((CPtr(SqliteExpr Ptr, local1->pPartIdxWhere) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (whereUsablePartialIndex(local6->iCursor, local6->fg.jointype, local12, CPtr(SqliteExpr Ptr, local1->pPartIdxWhere)) = 0))))))) Then
            ' empty C statement
            Goto c2fb_flow_3
        End If
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->flags) Shr 8) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            Goto c2fb_flow_3
        End If
        c2fb_temp_66 = Cast(Short, local1->aiRowLogEst[Cast(SQLITE_C_INT, &O0ULL)])
        local11 = c2fb_temp_66
        c2fb_temp_67 = CPtr(u16 Ptr, @(local7->u.btree.nEq))
        c2fb_temp_68 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_67) = Cast(u16, c2fb_temp_68)
        c2fb_temp_68 = Cast(UShort, (*c2fb_temp_67))
        c2fb_temp_69 = CPtr(u16 Ptr, @(local7->u.btree.nBtm))
        c2fb_temp_70 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_69) = Cast(u16, c2fb_temp_70)
        c2fb_temp_70 = Cast(UShort, (*c2fb_temp_69))
        c2fb_temp_71 = CPtr(u16 Ptr, @(local7->u.btree.nTop))
        c2fb_temp_72 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_71) = Cast(u16, c2fb_temp_72)
        c2fb_temp_72 = Cast(UShort, (*c2fb_temp_71))
        c2fb_temp_73 = CPtr(u16 Ptr, @(local7->u.btree.nDistinctCol))
        c2fb_temp_74 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_73) = Cast(u16, c2fb_temp_74)
        c2fb_temp_74 = Cast(UShort, (*c2fb_temp_73))
        c2fb_temp_75 = CPtr(u16 Ptr, @(local7->nSkip))
        c2fb_temp_76 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_75) = Cast(u16, c2fb_temp_76)
        c2fb_temp_76 = Cast(UShort, (*c2fb_temp_75))
        c2fb_temp_77 = CPtr(u16 Ptr, @(local7->nLTerm))
        c2fb_temp_78 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_77) = Cast(u16, c2fb_temp_78)
        c2fb_temp_78 = Cast(UShort, (*c2fb_temp_77))
        c2fb_temp_79 = CPtr(u8 Ptr, @(local7->iSortIdx))
        c2fb_temp_80 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_79) = Cast(u8, c2fb_temp_80)
        c2fb_temp_80 = Cast(UByte, (*c2fb_temp_79))
        c2fb_temp_81 = CPtr(Short Ptr, @(local7->rSetup))
        c2fb_temp_82 = Cast(Short, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_81) = c2fb_temp_82
        c2fb_temp_83 = CPtr(sqlite3_uint64 Ptr, @(local7->prereq))
        c2fb_temp_84 = Cast(sqlite3_uint64, arg1)
        (*c2fb_temp_83) = c2fb_temp_84
        c2fb_temp_85 = CPtr(Short Ptr, @(local7->nOut))
        c2fb_temp_86 = Cast(Short, local11)
        (*c2fb_temp_85) = c2fb_temp_86
        c2fb_temp_87 = CPtr(Any Ptr Ptr, @(local7->u.btree.pIndex))
        c2fb_temp_88 = local1
        (*c2fb_temp_87) = CPtr(Any Ptr, c2fb_temp_88)
        c2fb_temp_88 = CPtr(SqliteIndex Ptr, (*c2fb_temp_87))
        c2fb_temp_89 = CPtr(Any Ptr Ptr, @(local7->u.btree.pOrderBy))
        c2fb_temp_90 = CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_89) = CPtr(Any Ptr, c2fb_temp_90)
        c2fb_temp_90 = CPtr(SqliteExprList Ptr, (*c2fb_temp_89))
        c2fb_temp_91 = Cast(SQLITE_C_INT, indexMightHelpWithOrderBy(arg0, local1, local6->iCursor))
        local10 = c2fb_temp_91
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->flags) Shr 0) And Cast(SQLITE_C_UINT, &H3ULL))) = Cast(SQLITE_C_INT, 3ULL))))) Then
            c2fb_temp_92 = CPtr(u32 Ptr, @(local7->wsFlags))
            c2fb_temp_93 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000100ULL))
            (*c2fb_temp_92) = Cast(u32, c2fb_temp_93)
            c2fb_temp_93 = Cast(SQLITE_C_UINT, (*c2fb_temp_92))
            c2fb_temp_94 = CPtr(u8 Ptr, @(local7->iSortIdx))
            c2fb_temp_95 = Cast(UByte, IIf(local10, local9, Cast(SQLITE_C_INT, &O0ULL)))
            (*c2fb_temp_94) = Cast(u8, c2fb_temp_95)
            c2fb_temp_95 = Cast(UByte, (*c2fb_temp_94))
            c2fb_temp_96 = CPtr(Short Ptr, @(local7->rRun))
            c2fb_temp_97 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local11) + Cast(SQLITE_C_INT, 16ULL))))
            (*c2fb_temp_96) = c2fb_temp_97
            ' empty C statement
            whereLoopOutputAdjust(local12, local7, local11)
            If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local6->fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local6->fg.flags) Shr 6) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                    c2fb_temp_98 = CPtr(u32 Ptr, @(local7->wsFlags))
                    c2fb_temp_99 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_98)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H02000000ULL)))))
                    (*c2fb_temp_98) = Cast(u32, c2fb_temp_99)
                    c2fb_temp_99 = Cast(SQLITE_C_UINT, (*c2fb_temp_98))
                End If
                If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local6->u4.pSubq->pSelect->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0002000ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                    c2fb_temp_100 = CPtr(Any Ptr Ptr, @(local7->u.btree.pOrderBy))
                    c2fb_temp_101 = local6->u4.pSubq->pSelect->pOrderBy
                    (*c2fb_temp_100) = CPtr(Any Ptr, c2fb_temp_101)
                    c2fb_temp_101 = CPtr(SqliteExprList Ptr, (*c2fb_temp_100))
                End If
            Else
                If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local6->fg.flags) Shr 18) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                    c2fb_temp_102 = CPtr(Short Ptr, @(local7->nOut))
                    c2fb_temp_103 = Cast(Short, Cast(SQLITE_C_INT, &O0ULL))
                    (*c2fb_temp_102) = c2fb_temp_103
                End If
            End If
            c2fb_temp_104 = Cast(SQLITE_C_INT, whereLoopInsert(arg0, local7))
            local8 = c2fb_temp_104
            c2fb_temp_105 = CPtr(Short Ptr, @(local7->nOut))
            c2fb_temp_106 = Cast(Short, local11)
            (*c2fb_temp_105) = c2fb_temp_106
            If local8 Then
                Goto c2fb_flow_2
            End If
        Else
            ' C automatic storage declaration
            If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->flags) Shr 5) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                c2fb_temp_107 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))
                local18 = c2fb_temp_107
                c2fb_temp_108 = CPtr(u32 Ptr, @(local7->wsFlags))
                c2fb_temp_109 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000040ULL) Or Cast(SQLITE_C_INT, &H00000200ULL))))
                (*c2fb_temp_108) = Cast(u32, c2fb_temp_109)
                c2fb_temp_109 = Cast(SQLITE_C_UINT, (*c2fb_temp_108))
            Else
                c2fb_temp_110 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local6->colUsed And local1->colNotIdxed)))
                local18 = c2fb_temp_110
                If CPtr(SqliteExpr Ptr, local1->pPartIdxWhere) Then
                    wherePartIdxExpr(local0->pParse, local1, CPtr(SqliteExpr Ptr, local1->pPartIdxWhere), CPtr(sqlite3_uint64 Ptr, @(local18)), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL))
                End If
                c2fb_temp_111 = CPtr(u32 Ptr, @(local7->wsFlags))
                c2fb_temp_112 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000200ULL))
                (*c2fb_temp_111) = Cast(u32, c2fb_temp_112)
                c2fb_temp_112 = Cast(SQLITE_C_UINT, (*c2fb_temp_111))
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local18 = (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))) - Cast(SQLITE_C_INT, 1ULL))))))))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->flags) Shr 11) And Cast(SQLITE_C_UINT, &H1ULL))) AndAlso (-Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->flags) Shr 10) And Cast(SQLITE_C_UINT, &H1ULL))) = 0))))))) AndAlso (-Cast(SQLITE_C_INT, ((local18 <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))))))))))))))) Then
                    local19 = whereIsCoveringIndex(local0, local1, local6->iCursor)
                    If (-Cast(SQLITE_C_INT, ((local19 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                        ' empty C statement
                        ' C unused-parameter annotation
                    Else
                        c2fb_temp_113 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))
                        local18 = c2fb_temp_113
                        c2fb_temp_114 = CPtr(u32 Ptr, @(local7->wsFlags))
                        c2fb_temp_115 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_114)) Or local19)))
                        (*c2fb_temp_114) = Cast(u32, c2fb_temp_115)
                        c2fb_temp_115 = Cast(SQLITE_C_UINT, (*c2fb_temp_114))
                        If Cast(SQLITE_C_UINT, (local19 And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000040ULL)))) Then
                            ' empty C statement
                        Else
                            ' C unused-parameter annotation
                            ' empty C statement
                        End If
                    End If
                Else
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local18 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local13)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) OrElse (-Cast(SQLITE_C_INT, ((local0->pSelect <> Cast(SQLITE_C_INT, &O0ULL))))))))) OrElse sqlite3FaultSim(Cast(SQLITE_C_INT, 700ULL))))))))))) Then
                        ' empty C statement
                        c2fb_temp_116 = CPtr(u32 Ptr, @(local7->wsFlags))
                        c2fb_temp_117 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000040ULL) Or Cast(SQLITE_C_INT, &H00000200ULL))))
                        (*c2fb_temp_116) = Cast(u32, c2fb_temp_117)
                        c2fb_temp_117 = Cast(SQLITE_C_UINT, (*c2fb_temp_116))
                    End If
                End If
            End If
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local10 OrElse (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local13)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))))))) OrElse (-Cast(SQLITE_C_INT, ((CPtr(SqliteExpr Ptr, local1->pPartIdxWhere) <> Cast(SQLITE_C_INT, &O0ULL))))))))) OrElse Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local6->fg.flags) Shr 1) And Cast(SQLITE_C_UINT, &H1ULL))))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local18 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->szIdxRow) < Cast(SQLITE_C_INT, local13->szTabRow)))))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->wctrlFlags) And Cast(SQLITE_C_INT, &H0004ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso sqlite3ConfigCoveringIndexScanEnabled())))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local0->pParse->db)->dbOptFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H00000020ULL)))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))))))))) Then
                c2fb_temp_118 = CPtr(u8 Ptr, @(local7->iSortIdx))
                c2fb_temp_119 = Cast(UByte, IIf(local10, local9, Cast(SQLITE_C_INT, &O0ULL)))
                (*c2fb_temp_118) = Cast(u8, c2fb_temp_119)
                c2fb_temp_119 = Cast(UByte, (*c2fb_temp_118))
                c2fb_temp_120 = CPtr(Short Ptr, @(local7->rRun))
                c2fb_temp_121 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local11) + Cast(SQLITE_C_INT, 1ULL))) + Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 15ULL) * Cast(SQLITE_C_INT, local1->szIdxRow)))) \ Cast(SQLITE_C_INT, local13->szTabRow))))))
                (*c2fb_temp_120) = c2fb_temp_121
                If (-Cast(SQLITE_C_INT, ((local18 <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                    local20 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local11) + Cast(SQLITE_C_INT, 16ULL)))
                    ' C automatic storage declaration
                    local22 = local6->iCursor
                    local23 = CPtr(SqliteWhereClause Ptr, @(local0->sWC))
                    c2fb_temp_122 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    local21 = c2fb_temp_122
                    While (-Cast(SQLITE_C_INT, ((local21 < local23->nTerm))))
                        local24 = CPtr(SqliteWhereTerm Ptr, @(local23->a[local21]))
                        If (-Cast(SQLITE_C_INT, (sqlite3ExprCoveredByIndex(CPtr(Any Ptr, local24->pExpr), local22, CPtr(Any Ptr, local1)) = 0))) Then
                            Goto c2fb_flow_4
                        End If
                        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local24->truthProb) <= Cast(SQLITE_C_INT, &O0ULL))))) Then
                            c2fb_temp_124 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local20) + Cast(SQLITE_C_INT, local24->truthProb))))
                            local20 = c2fb_temp_124
                        Else
                            c2fb_temp_125 = local20
                            local20 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_125) - 1)))
                            If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local24->eOperator) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0080ULL)))))) Then
                                c2fb_temp_126 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local20) - Cast(SQLITE_C_INT, 19ULL))))
                                local20 = c2fb_temp_126
                            End If
                        End If
                    c2fb_flow_5:
                        c2fb_temp_123 = local21
                        local21 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_123 + 1)))
                    Wend
                    c2fb_flow_4:
                    c2fb_temp_127 = CPtr(Short Ptr, @(local7->rRun))
                    c2fb_temp_128 = Cast(Short, sqlite3LogEstAdd(local7->rRun, local20))
                    (*c2fb_temp_127) = c2fb_temp_128
                End If
                ' empty C statement
                whereLoopOutputAdjust(local12, local7, local11)
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local6->fg.jointype) And Cast(SQLITE_C_INT, &H10ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso CPtr(SqliteExprList Ptr, local1->aColExpr))))) Then
                    ' empty C block
                Else
                    If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local6->fg.flags) Shr 18) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                        c2fb_temp_129 = CPtr(Short Ptr, @(local7->nOut))
                        c2fb_temp_130 = Cast(Short, Cast(SQLITE_C_INT, &O0ULL))
                        (*c2fb_temp_129) = c2fb_temp_130
                    End If
                    c2fb_temp_131 = Cast(SQLITE_C_INT, whereLoopInsert(arg0, local7))
                    local8 = c2fb_temp_131
                End If
                c2fb_temp_132 = CPtr(Short Ptr, @(local7->nOut))
                c2fb_temp_133 = Cast(Short, local11)
                (*c2fb_temp_132) = c2fb_temp_133
                If local8 Then
                    Goto c2fb_flow_2
                End If
            End If
        End If
        c2fb_temp_134 = CPtr(u8 Ptr, @(arg0->bldFlags1))
        c2fb_temp_135 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_134) = Cast(u8, c2fb_temp_135)
        c2fb_temp_135 = Cast(UByte, (*c2fb_temp_134))
        c2fb_temp_136 = Cast(SQLITE_C_INT, whereLoopAddBtreeIndex(arg0, local6, local1, Cast(SQLITE_C_INT, &O0ULL)))
        local8 = c2fb_temp_136
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->bldFlags1) = Cast(SQLITE_C_INT, &H0001ULL))))) Then
            c2fb_temp_137 = CPtr(u32 Ptr, @(local13->tabFlags))
            c2fb_temp_138 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_137)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000100ULL)))))
            (*c2fb_temp_137) = Cast(u32, c2fb_temp_138)
            c2fb_temp_138 = Cast(SQLITE_C_UINT, (*c2fb_temp_137))
        End If
    c2fb_flow_3:
        c2fb_temp_64 = (IIf(Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local6->fg.flags) Shr 1) And Cast(SQLITE_C_UINT, &H1ULL))), CPtr(SqliteIndex Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL))), local1->pNext))
        local1 = c2fb_temp_64
        c2fb_temp_65 = local9
        local9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_65 + 1)))
    Wend
    c2fb_flow_2:
    Return local8
End Function

' c2fb skipped isLimitTerm: outside the supported subset
' c2fb skipped allConstraintsUsed: outside the supported subset
' c2fb skipped whereLoopAddVirtualOne: FreeBASIC body already exists
' c2fb skipped sqlite3_vtab_collation: FreeBASIC body already exists
' c2fb skipped sqlite3_vtab_in: FreeBASIC body already exists
' c2fb skipped sqlite3_vtab_rhs_value: FreeBASIC body already exists
' c2fb skipped sqlite3_vtab_distinct: FreeBASIC body already exists
' c2fb skipped sqlite3VtabUsesAllSchemas: FreeBASIC body already exists
' c2fb skipped whereLoopAddVirtual: FreeBASIC body already exists
Private Function whereLoopAddOr CDecl Alias "whereLoopAddOr" (ByVal arg0 As SqliteWhereLoopBuilder Ptr, ByVal arg1 As sqlite3_uint64, ByVal arg2 As sqlite3_uint64) As SQLITE_C_INT
    Dim local0 As SqliteWhereInfo Ptr
    Dim local1 As SqliteWhereClause Ptr
    Dim local2 As SqliteWhereLoop Ptr
    Dim local3 As SqliteWhereTerm Ptr
    Dim local4 As SqliteWhereTerm Ptr
    Dim local5 As SQLITE_C_INT
    Dim local6 As SQLITE_C_INT
    Dim local7 As SqliteWhereClause
    Dim local8 As SqliteWhereLoopBuilder
    Dim local9 As SqliteWhereOrSet
    Dim local10 As SqliteWhereOrSet
    Dim local11 As SqliteSrcItem Ptr
    Dim c2fb_temp_0 As SqliteWhereClause Ptr
    Dim c2fb_temp_1 As SqliteWhereTerm Ptr
    Dim c2fb_temp_2 As SqliteWhereLoop Ptr
    Dim c2fb_temp_3 As Any Ptr
    Dim c2fb_temp_4 As SqliteSrcItem Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SqliteWhereTerm Ptr
    Dim c2fb_temp_7 As SqliteWhereTerm Ptr
    Dim local12 As Const SqliteWhereClause Ptr
    Dim local13 As Const SqliteWhereTerm Ptr
    Dim local14 As SqliteWhereTerm Ptr
    Dim local15 As SQLITE_C_INT
    Dim local16 As SQLITE_C_INT
    Dim local17 As SQLITE_C_INT
    Dim c2fb_temp_8 As SqliteWhereLoopBuilder
    Dim c2fb_temp_9 As Any Ptr Ptr
    Dim c2fb_temp_10 As SqliteWhereOrSet Ptr
    Dim c2fb_temp_11 As SqliteWhereTerm Ptr
    Dim c2fb_temp_12 As SqliteWhereTerm Ptr
    Dim c2fb_temp_13 As Any Ptr Ptr
    Dim c2fb_temp_14 As SqliteWhereClause Ptr
    Dim c2fb_temp_15 As SqliteWhereInfo Ptr Ptr
    Dim c2fb_temp_16 As SqliteWhereInfo Ptr
    Dim c2fb_temp_17 As SqliteWhereClause Ptr Ptr
    Dim c2fb_temp_18 As SqliteWhereClause Ptr
    Dim c2fb_temp_19 As u8 Ptr
    Dim c2fb_temp_20 As UByte
    Dim c2fb_temp_21 As SQLITE_C_INT Ptr
    Dim c2fb_temp_22 As SQLITE_C_INT
    Dim c2fb_temp_23 As SQLITE_C_INT Ptr
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As SqliteWhereTerm Ptr Ptr
    Dim c2fb_temp_26 As SqliteWhereTerm Ptr
    Dim c2fb_temp_27 As Any Ptr Ptr
    Dim c2fb_temp_28 As SqliteWhereClause Ptr
    Dim c2fb_temp_29 As u16 Ptr
    Dim c2fb_temp_30 As UShort
    Dim c2fb_temp_31 As SQLITE_C_INT
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As SQLITE_C_INT
    Dim c2fb_temp_34 As u16 Ptr
    Dim c2fb_temp_35 As UShort
    Dim c2fb_temp_36 As SQLITE_C_INT
    Dim local18 As SqliteWhereOrSet
    Dim c2fb_temp_37 As u16 Ptr
    Dim c2fb_temp_38 As UShort
    Dim c2fb_temp_39 As SQLITE_C_INT
    Dim c2fb_temp_40 As SQLITE_C_INT
    Dim c2fb_temp_41 As SQLITE_C_INT
    Dim c2fb_temp_42 As SQLITE_C_INT
    Dim c2fb_temp_43 As u16 Ptr
    Dim c2fb_temp_44 As UShort
    Dim c2fb_temp_45 As SqliteWhereTerm Ptr Ptr
    Dim c2fb_temp_46 As SqliteWhereTerm Ptr
    Dim c2fb_temp_47 As u32 Ptr
    Dim c2fb_temp_48 As SQLITE_C_UINT
    Dim c2fb_temp_49 As Short Ptr
    Dim c2fb_temp_50 As Short
    Dim c2fb_temp_51 As u8 Ptr
    Dim c2fb_temp_52 As UByte
    Dim c2fb_temp_53 As Any Ptr
    Dim c2fb_temp_54 As SQLITE_C_INT
    Dim c2fb_temp_55 As SQLITE_C_INT
    Dim c2fb_temp_56 As Short Ptr
    Dim c2fb_temp_57 As Short
    Dim c2fb_temp_58 As Short Ptr
    Dim c2fb_temp_59 As Short
    Dim c2fb_temp_60 As sqlite3_uint64 Ptr
    Dim c2fb_temp_61 As sqlite3_uint64
    Dim c2fb_temp_62 As SQLITE_C_INT

    local0 = CPtr(SqliteWhereInfo Ptr, arg0->pWInfo)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local5 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    c2fb_temp_0 = CPtr(SqliteWhereClause Ptr, arg0->pWC)
    local1 = c2fb_temp_0
    c2fb_temp_1 = CPtr(SqliteWhereTerm Ptr, (local1->a + local1->nTerm))
    local4 = c2fb_temp_1
    c2fb_temp_2 = arg0->pNew
    local2 = c2fb_temp_2
    c2fb_temp_3 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteWhereOrSet Ptr, @(local9))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereOrSet))))
    c2fb_temp_4 = CPtr(SqliteSrcItem Ptr, (CPtr(SqliteSrcItem Ptr, (@local0->pTabList->a(0))) + local2->iTab))
    local11 = c2fb_temp_4
    c2fb_temp_5 = Cast(SQLITE_C_INT, local11->iCursor)
    local6 = c2fb_temp_5
    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local11->fg.jointype) And Cast(SQLITE_C_INT, &H10ULL))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_6 = local1->a
    local3 = c2fb_temp_6
    While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local3 < local4)))) AndAlso (-Cast(SQLITE_C_INT, ((local5 = Cast(SQLITE_C_INT, &O0ULL)))))))))
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local3->eOperator) And Cast(SQLITE_C_INT, &H0200ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (CPtr(SqliteWhereOrInfo Ptr, local3->u.pOrInfo)->indexable And local2->maskSelf))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
            local12 = CPtr(SqliteWhereClause Ptr, @(CPtr(SqliteWhereOrInfo Ptr, local3->u.pOrInfo)->wc))
            local13 = CPtr(SqliteWhereTerm Ptr, @(local12->a[local12->nTerm]))
            ' C automatic storage declaration
            local15 = Cast(SQLITE_C_INT, 1ULL)
            ' C automatic storage declaration
            ' C automatic storage declaration
            c2fb_temp_8 = (*arg0)
            local8 = c2fb_temp_8
            c2fb_temp_9 = CPtr(Any Ptr Ptr, @(local8.pOrSet))
            c2fb_temp_10 = CPtr(SqliteWhereOrSet Ptr, @(local10))
            (*c2fb_temp_9) = CPtr(Any Ptr, c2fb_temp_10)
            c2fb_temp_10 = CPtr(SqliteWhereOrSet Ptr, (*c2fb_temp_9))
            ' empty C statement
            c2fb_temp_11 = local12->a
            local14 = c2fb_temp_11
            While (-Cast(SQLITE_C_INT, ((local14 < local13))))
                If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local14->eOperator) And Cast(SQLITE_C_INT, &H0400ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_13 = CPtr(Any Ptr Ptr, @(local8.pWC))
                    c2fb_temp_14 = CPtr(SqliteWhereClause Ptr, @(CPtr(SqliteWhereAndInfo Ptr, local14->u.pAndInfo)->wc))
                    (*c2fb_temp_13) = CPtr(Any Ptr, c2fb_temp_14)
                    c2fb_temp_14 = CPtr(SqliteWhereClause Ptr, (*c2fb_temp_13))
                Else
                    If (-Cast(SQLITE_C_INT, ((local14->leftCursor = local6)))) Then
                        c2fb_temp_15 = CPtr(SqliteWhereInfo Ptr Ptr, @(local7.pWInfo))
                        c2fb_temp_16 = local1->pWInfo
                        (*c2fb_temp_15) = c2fb_temp_16
                        c2fb_temp_17 = CPtr(SqliteWhereClause Ptr Ptr, @(local7.pOuter))
                        c2fb_temp_18 = local1
                        (*c2fb_temp_17) = c2fb_temp_18
                        c2fb_temp_19 = CPtr(u8 Ptr, @(local7.op))
                        c2fb_temp_20 = Cast(UByte, Cast(SQLITE_C_INT, 44ULL))
                        (*c2fb_temp_19) = Cast(u8, c2fb_temp_20)
                        c2fb_temp_20 = Cast(UByte, (*c2fb_temp_19))
                        c2fb_temp_21 = CPtr(SQLITE_C_INT Ptr, @(local7.nTerm))
                        c2fb_temp_22 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                        (*c2fb_temp_21) = c2fb_temp_22
                        c2fb_temp_23 = CPtr(SQLITE_C_INT Ptr, @(local7.nBase))
                        c2fb_temp_24 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                        (*c2fb_temp_23) = c2fb_temp_24
                        c2fb_temp_25 = CPtr(SqliteWhereTerm Ptr Ptr, @(local7.a))
                        c2fb_temp_26 = local14
                        (*c2fb_temp_25) = c2fb_temp_26
                        c2fb_temp_27 = CPtr(Any Ptr Ptr, @(local8.pWC))
                        c2fb_temp_28 = CPtr(SqliteWhereClause Ptr, @(local7))
                        (*c2fb_temp_27) = CPtr(Any Ptr, c2fb_temp_28)
                        c2fb_temp_28 = CPtr(SqliteWhereClause Ptr, (*c2fb_temp_27))
                    Else
                        Goto c2fb_flow_3
                    End If
                End If
                c2fb_temp_29 = CPtr(u16 Ptr, @(local10.n))
                c2fb_temp_30 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_29) = Cast(u16, c2fb_temp_30)
                c2fb_temp_30 = Cast(UShort, (*c2fb_temp_29))
                If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local11->pSTab)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))) Then
                    c2fb_temp_31 = Cast(SQLITE_C_INT, whereLoopAddVirtual(CPtr(SqliteWhereLoopBuilder Ptr, @(local8)), arg1, arg2))
                    local5 = c2fb_temp_31
                Else
                    c2fb_temp_32 = Cast(SQLITE_C_INT, whereLoopAddBtree(CPtr(SqliteWhereLoopBuilder Ptr, @(local8)), arg1))
                    local5 = c2fb_temp_32
                End If
                If (-Cast(SQLITE_C_INT, ((local5 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_33 = Cast(SQLITE_C_INT, whereLoopAddOr(CPtr(SqliteWhereLoopBuilder Ptr, @(local8)), arg1, arg2))
                    local5 = c2fb_temp_33
                End If
                ' empty C statement
                ' empty C statement
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local10.n) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_34 = CPtr(u16 Ptr, @(local9.n))
                    c2fb_temp_35 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
                    (*c2fb_temp_34) = Cast(u16, c2fb_temp_35)
                    c2fb_temp_35 = Cast(UShort, (*c2fb_temp_34))
                    Goto c2fb_flow_2
                Else
                    If local15 Then
                        whereOrMove(CPtr(SqliteWhereOrSet Ptr, @(local9)), CPtr(SqliteWhereOrSet Ptr, @(local10)))
                        c2fb_temp_36 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                        local15 = c2fb_temp_36
                    Else
                        ' C automatic storage declaration
                        whereOrMove(CPtr(SqliteWhereOrSet Ptr, @(local18)), CPtr(SqliteWhereOrSet Ptr, @(local9)))
                        c2fb_temp_37 = CPtr(u16 Ptr, @(local9.n))
                        c2fb_temp_38 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
                        (*c2fb_temp_37) = Cast(u16, c2fb_temp_38)
                        c2fb_temp_38 = Cast(UShort, (*c2fb_temp_37))
                        c2fb_temp_39 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                        local16 = c2fb_temp_39
                        While (-Cast(SQLITE_C_INT, ((local16 < Cast(SQLITE_C_INT, local18.n)))))
                            c2fb_temp_41 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                            local17 = c2fb_temp_41
                            While (-Cast(SQLITE_C_INT, ((local17 < Cast(SQLITE_C_INT, local10.n)))))
                                whereOrInsert(CPtr(SqliteWhereOrSet Ptr, @(local9)), Cast(sqlite3_uint64, (local18.a(local16).prereq Or local10.a(local17).prereq)), sqlite3LogEstAdd(local18.a(local16).rRun, local10.a(local17).rRun), sqlite3LogEstAdd(local18.a(local16).nOut, local10.a(local17).nOut))
                            c2fb_flow_7:
                                c2fb_temp_42 = local17
                                local17 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_42 + 1)))
                            Wend
                            c2fb_flow_6:
                        c2fb_flow_5:
                            c2fb_temp_40 = local16
                            local16 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_40 + 1)))
                        Wend
                        c2fb_flow_4:
                    End If
                End If
            c2fb_flow_3:
                c2fb_temp_12 = local14
                local14 = (c2fb_temp_12 + 1)
            Wend
            c2fb_flow_2:
            c2fb_temp_43 = CPtr(u16 Ptr, @(local2->nLTerm))
            c2fb_temp_44 = Cast(UShort, Cast(SQLITE_C_INT, 1ULL))
            (*c2fb_temp_43) = Cast(u16, c2fb_temp_44)
            c2fb_temp_44 = Cast(UShort, (*c2fb_temp_43))
            c2fb_temp_45 = CPtr(SqliteWhereTerm Ptr Ptr, @(local2->aLTerm[Cast(SQLITE_C_INT, &O0ULL)]))
            c2fb_temp_46 = local3
            (*c2fb_temp_45) = c2fb_temp_46
            c2fb_temp_47 = CPtr(u32 Ptr, @(local2->wsFlags))
            c2fb_temp_48 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00002000ULL))
            (*c2fb_temp_47) = Cast(u32, c2fb_temp_48)
            c2fb_temp_48 = Cast(SQLITE_C_UINT, (*c2fb_temp_47))
            c2fb_temp_49 = CPtr(Short Ptr, @(local2->rSetup))
            c2fb_temp_50 = Cast(Short, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_49) = c2fb_temp_50
            c2fb_temp_51 = CPtr(u8 Ptr, @(local2->iSortIdx))
            c2fb_temp_52 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_51) = Cast(u8, c2fb_temp_52)
            c2fb_temp_52 = Cast(UByte, (*c2fb_temp_51))
            c2fb_temp_53 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteWhereLoopUnion Ptr, @(local2->u))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereLoopUnion))))
            c2fb_temp_54 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local16 = c2fb_temp_54
            While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local5 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local16 < Cast(SQLITE_C_INT, local9.n)))))))))
                c2fb_temp_56 = CPtr(Short Ptr, @(local2->rRun))
                c2fb_temp_57 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local9.a(local16).rRun) + Cast(SQLITE_C_INT, 1ULL))))
                (*c2fb_temp_56) = c2fb_temp_57
                c2fb_temp_58 = CPtr(Short Ptr, @(local2->nOut))
                c2fb_temp_59 = Cast(Short, local9.a(local16).nOut)
                (*c2fb_temp_58) = c2fb_temp_59
                c2fb_temp_60 = CPtr(sqlite3_uint64 Ptr, @(local2->prereq))
                c2fb_temp_61 = Cast(sqlite3_uint64, local9.a(local16).prereq)
                (*c2fb_temp_60) = c2fb_temp_61
                c2fb_temp_62 = Cast(SQLITE_C_INT, whereLoopInsert(arg0, local2))
                local5 = c2fb_temp_62
            c2fb_flow_9:
                c2fb_temp_55 = local16
                local16 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_55 + 1)))
            Wend
            c2fb_flow_8:
            ' empty C statement
        End If
    c2fb_flow_1:
        c2fb_temp_7 = local3
        local3 = (c2fb_temp_7 + 1)
    Wend
    c2fb_flow_0:
    Return local5
End Function

Private Function whereLoopAddAll CDecl Alias "whereLoopAddAll" (ByVal arg0 As SqliteWhereLoopBuilder Ptr) As SQLITE_C_INT
    Dim local0 As SqliteWhereInfo Ptr
    Dim local1 As sqlite3_uint64
    Dim local2 As sqlite3_uint64
    Dim local3 As SQLITE_C_INT
    Dim local4 As SqliteSrcList Ptr
    Dim local5 As SqliteSrcItem Ptr
    Dim local6 As SqliteSrcItem Ptr
    Dim local7 As sqlite3 Ptr
    Dim local8 As SQLITE_C_INT
    Dim local9 As SQLITE_C_INT
    Dim local10 As SQLITE_C_INT
    Dim local11 As SqliteWhereLoop Ptr
    Dim c2fb_temp_0 As SqliteWhereLoop Ptr
    Dim c2fb_temp_1 As u32 Ptr
    Dim c2fb_temp_2 As SQLITE_C_UINT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SqliteSrcItem Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SqliteSrcItem Ptr
    Dim local12 As sqlite3_uint64
    Dim c2fb_temp_7 As u8 Ptr
    Dim c2fb_temp_8 As UByte
    Dim c2fb_temp_9 As u32 Ptr
    Dim c2fb_temp_10 As SQLITE_C_UINT
    Dim c2fb_temp_11 As sqlite3_uint64 Ptr
    Dim c2fb_temp_12 As sqlite3_uint64
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As sqlite3_uint64
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim local13 As SqliteWhereClause Ptr
    Dim local14 As SqliteWhereTerm Ptr
    Dim local15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SqliteWhereTerm Ptr
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As SqliteWhereTerm Ptr
    Dim c2fb_temp_20 As sqlite3_uint64
    Dim c2fb_temp_21 As sqlite3_uint64
    Dim local16 As SqliteSrcItem Ptr
    Dim c2fb_temp_22 As SqliteSrcItem Ptr
    Dim c2fb_temp_23 As SqliteSrcItem Ptr
    Dim c2fb_temp_24 As sqlite3_uint64
    Dim c2fb_temp_25 As SQLITE_C_INT
    Dim c2fb_temp_26 As SQLITE_C_INT
    Dim c2fb_temp_27 As SQLITE_C_INT
    Dim c2fb_temp_28 As sqlite3_uint64
    Dim c2fb_temp_29 As SQLITE_C_INT

    local0 = CPtr(SqliteWhereInfo Ptr, arg0->pWInfo)
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    local2 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    local4 = local0->pTabList
    ' C automatic storage declaration
    local6 = CPtr(SqliteSrcItem Ptr, @(local4->a(local0->nLevel)))
    local7 = local0->pParse->db
    local8 = Cast(SQLITE_C_INT, &O0ULL)
    local9 = Cast(SQLITE_C_INT, &O0ULL)
    local10 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    c2fb_temp_0 = arg0->pNew
    local11 = c2fb_temp_0
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_1 = CPtr(u32 Ptr, @(arg0->iPlanLimit))
    c2fb_temp_2 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 20000ULL))
    (*c2fb_temp_1) = Cast(u32, c2fb_temp_2)
    c2fb_temp_2 = Cast(SQLITE_C_UINT, (*c2fb_temp_1))
    c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local3 = c2fb_temp_3
    c2fb_temp_4 = CPtr(SqliteSrcItem Ptr, (@local4->a(0)))
    local5 = c2fb_temp_4
    While (-Cast(SQLITE_C_INT, ((local5 < local6))))
        local12 = Cast(SQLITE_C_INT, &O0ULL)
        c2fb_temp_7 = CPtr(u8 Ptr, @(local11->iTab))
        c2fb_temp_8 = Cast(UByte, local3)
        (*c2fb_temp_7) = Cast(u8, c2fb_temp_8)
        c2fb_temp_8 = Cast(UByte, (*c2fb_temp_7))
        c2fb_temp_9 = CPtr(u32 Ptr, @(arg0->iPlanLimit))
        c2fb_temp_10 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_9)) + Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1000ULL)))))
        (*c2fb_temp_9) = Cast(u32, c2fb_temp_10)
        c2fb_temp_10 = Cast(SQLITE_C_UINT, (*c2fb_temp_9))
        c2fb_temp_11 = CPtr(sqlite3_uint64 Ptr, @(local11->maskSelf))
        c2fb_temp_12 = Cast(sqlite3_uint64, sqlite3WhereGetMask(CPtr(SqliteWhereMaskSet Ptr, @(local0->sMaskSet)), local5->iCursor))
        (*c2fb_temp_11) = c2fb_temp_12
        If (-Cast(SQLITE_C_INT, ((local9 OrElse (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local5->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H20ULL) Or Cast(SQLITE_C_INT, &H02ULL))) Or Cast(SQLITE_C_INT, &H40ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local5->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H40ULL) Or Cast(SQLITE_C_INT, &H02ULL)))))) Then
                ' empty C statement
                ' empty C statement
                c2fb_temp_13 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                local10 = c2fb_temp_13
            End If
            c2fb_temp_14 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local1 Or local2)))
            local1 = c2fb_temp_14
            c2fb_temp_15 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local5->fg.jointype) And Cast(SQLITE_C_INT, &H10ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))))
            local9 = c2fb_temp_15
        Else
            If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local5->fg.flags) Shr 18) And Cast(SQLITE_C_UINT, &H1ULL))) Then
                local13 = CPtr(SqliteWhereClause Ptr, @(local0->sWC))
                ' C automatic storage declaration
                ' C automatic storage declaration
                c2fb_temp_16 = Cast(SQLITE_C_INT, local13->nBase)
                local15 = c2fb_temp_16
                c2fb_temp_17 = local13->a
                local14 = c2fb_temp_17
                While (-Cast(SQLITE_C_INT, ((local15 > Cast(SQLITE_C_INT, &O0ULL)))))
                    If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local11->maskSelf And local14->prereqAll))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                        c2fb_temp_20 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local1 Or (Cast(sqlite3_uint64, (local14->prereqAll And (Cast(sqlite3_uint64, (local11->maskSelf - Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL)))))))))))
                        local1 = c2fb_temp_20
                    End If
                c2fb_flow_3:
                    c2fb_temp_18 = local15
                    local15 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_18 - 1)))
                    c2fb_temp_19 = local14
                    local14 = (c2fb_temp_19 + 1)
                Wend
                c2fb_flow_2:
            Else
                If (-Cast(SQLITE_C_INT, (local10 = 0))) Then
                    c2fb_temp_21 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))
                    local1 = c2fb_temp_21
                End If
            End If
        End If
        If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local5->pSTab)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))) Then
            ' C automatic storage declaration
            c2fb_temp_22 = CPtr(SqliteSrcItem Ptr, @(local5[Cast(SQLITE_C_INT, 1ULL)]))
            local16 = c2fb_temp_22
            While (-Cast(SQLITE_C_INT, ((local16 < local6))))
                If (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local16->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H20ULL) Or Cast(SQLITE_C_INT, &H02ULL))))))) Then
                    c2fb_temp_24 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local12 Or sqlite3WhereGetMask(CPtr(SqliteWhereMaskSet Ptr, @(local0->sMaskSet)), local16->iCursor))))
                    local12 = c2fb_temp_24
                End If
            c2fb_flow_5:
                c2fb_temp_23 = local16
                local16 = (c2fb_temp_23 + 1)
            Wend
            c2fb_flow_4:
            c2fb_temp_25 = Cast(SQLITE_C_INT, whereLoopAddVirtual(arg0, local1, local12))
            local8 = c2fb_temp_25
        Else
            c2fb_temp_26 = Cast(SQLITE_C_INT, whereLoopAddBtree(arg0, local1))
            local8 = c2fb_temp_26
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso Cast(SQLITE_C_INT, CPtr(SqliteWhereClause Ptr, arg0->pWC)->hasOr))))) Then
            c2fb_temp_27 = Cast(SQLITE_C_INT, whereLoopAddOr(arg0, local1, local12))
            local8 = c2fb_temp_27
        End If
        c2fb_temp_28 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local2 Or local11->maskSelf)))
        local2 = c2fb_temp_28
        If (-Cast(SQLITE_C_INT, ((local8 OrElse Cast(SQLITE_C_INT, local7->mallocFailed))))) Then
            If (-Cast(SQLITE_C_INT, ((local8 = Cast(SQLITE_C_INT, 101ULL))))) Then
                sqlite3_log(Cast(SQLITE_C_INT, 28ULL), StrPtr(!"abbreviated query algorithm search"))
                c2fb_temp_29 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local8 = c2fb_temp_29
            Else
                Goto c2fb_flow_0
            End If
        End If
    c2fb_flow_1:
        c2fb_temp_5 = local3
        local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_5 + 1)))
        c2fb_temp_6 = local5
        local5 = (c2fb_temp_6 + 1)
    Wend
    c2fb_flow_0:
    whereLoopClear(local7, local11)
    Return local8
End Function

Private Function wherePathMatchSubqueryOB CDecl Alias "wherePathMatchSubqueryOB" (ByVal arg0 As SqliteWhereInfo Ptr, ByVal arg1 As SqliteWhereLoop Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SQLITE_C_INT, ByVal arg4 As SqliteExprList Ptr, ByVal arg5 As sqlite3_uint64 Ptr, ByVal arg6 As sqlite3_uint64 Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim local2 As UByte
    Dim local3 As UByte
    Dim local4 As SqliteExpr Ptr
    Dim local5 As SqliteExprList Ptr
    Dim c2fb_temp_0 As SqliteExprList Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SqliteExpr Ptr
    Dim local6 As UByte
    Dim local7 As UByte
    Dim c2fb_temp_7 As UByte
    Dim c2fb_temp_8 As UByte
    Dim c2fb_temp_9 As sqlite3_uint64 Ptr
    Dim c2fb_temp_10 As sqlite3_uint64
    Dim c2fb_temp_11 As sqlite3_uint64 Ptr
    Dim c2fb_temp_12 As sqlite3_uint64

    ' C automatic storage declaration
    ' C automatic storage declaration
    local2 = Cast(SQLITE_C_INT, &O0ULL)
    local3 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    c2fb_temp_0 = CPtr(SqliteExprList Ptr, arg1->u.btree.pOrderBy)
    local5 = c2fb_temp_0
    ' C unused-parameter annotation
    c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_1
    While (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local0)))) And (*arg6)))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))))))
        ' empty C block
    c2fb_flow_1:
        c2fb_temp_2 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_2 + 1)))
    Wend
    c2fb_flow_0:
    c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local1 = c2fb_temp_3
    While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local1 < local5->nExpr)))) AndAlso (-Cast(SQLITE_C_INT, ((local0 < arg4->nExpr))))))))
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local5->a(local1).u.x.iOrderByCol) = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_2
        End If
        c2fb_temp_6 = arg4->a(local0).pExpr
        local4 = c2fb_temp_6
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4->op) <> Cast(SQLITE_C_INT, 168ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4->op) <> Cast(SQLITE_C_INT, 170ULL))))))))) Then
            Goto c2fb_flow_2
        End If
        If (-Cast(SQLITE_C_INT, ((local4->iTable <> arg3)))) Then
            Goto c2fb_flow_2
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local4->iColumn) <> Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local5->a(local1).u.x.iOrderByCol) - Cast(SQLITE_C_INT, 1ULL))))))) Then
            Goto c2fb_flow_2
        End If
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->wctrlFlags) And Cast(SQLITE_C_INT, &H0040ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
            local6 = arg4->a(local0).fg.sortFlags
            local7 = local5->a(local1).fg.sortFlags
            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local7) And Cast(SQLITE_C_INT, &H02ULL)))) <> (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local6) And Cast(SQLITE_C_INT, &H02ULL)))))))) Then
                Goto c2fb_flow_2
            End If
            c2fb_temp_7 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local7) And Cast(SQLITE_C_INT, &H01ULL))))
            local3 = c2fb_temp_7
            If (-Cast(SQLITE_C_INT, ((local1 > Cast(SQLITE_C_INT, &O0ULL))))) Then
                If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local2) Xor Cast(SQLITE_C_INT, local3)))) <> (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local6) And Cast(SQLITE_C_INT, &H01ULL)))))))) Then
                    Goto c2fb_flow_2
                End If
            Else
                c2fb_temp_8 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local3) Xor (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local6) And Cast(SQLITE_C_INT, &H01ULL)))))))
                local2 = c2fb_temp_8
                If local2 Then
                    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H02000000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                        Goto c2fb_flow_2
                    End If
                    c2fb_temp_9 = CPtr(sqlite3_uint64 Ptr, @((*arg5)))
                    c2fb_temp_10 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, ((*c2fb_temp_9) Or (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (arg2)))))))
                    (*c2fb_temp_9) = c2fb_temp_10
                End If
            End If
        End If
        c2fb_temp_11 = CPtr(sqlite3_uint64 Ptr, @((*arg6)))
        c2fb_temp_12 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, ((*c2fb_temp_11) Or (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local0)))))))
        (*c2fb_temp_11) = c2fb_temp_12
    c2fb_flow_3:
        c2fb_temp_4 = local1
        local1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_4 + 1)))
        c2fb_temp_5 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_5 + 1)))
    Wend
    c2fb_flow_2:
    Return (-Cast(SQLITE_C_INT, ((local1 > Cast(SQLITE_C_INT, &O0ULL)))))
End Function

Private Function wherePathSatisfiesOrderBy CDecl Alias "wherePathSatisfiesOrderBy" (ByVal arg0 As SqliteWhereInfo Ptr, ByVal arg1 As SqliteExprList Ptr, ByVal arg2 As SqliteWherePath Ptr, ByVal arg3 As UShort, ByVal arg4 As UShort, ByVal arg5 As SqliteWhereLoop Ptr, ByVal arg6 As sqlite3_uint64 Ptr) As Byte
    Dim local0 As UByte
    Dim local1 As UByte
    Dim local2 As UByte
    Dim local3 As UByte
    Dim local4 As UByte
    Dim local5 As UByte
    Dim local6 As UShort
    Dim local7 As UShort
    Dim local8 As UShort
    Dim local9 As UShort
    Dim local10 As SQLITE_C_INT
    Dim local11 As SQLITE_C_INT
    Dim local12 As SQLITE_C_INT
    Dim local13 As SQLITE_C_INT
    Dim local14 As SQLITE_C_INT
    Dim local15 As SqliteWhereLoop Ptr
    Dim local16 As SqliteWhereTerm Ptr
    Dim local17 As SqliteExpr Ptr
    Dim local18 As sqlite3CollSeq Ptr
    Dim local19 As SqliteIndex Ptr
    Dim local20 As sqlite3 Ptr
    Dim local21 As sqlite3_uint64
    Dim local22 As sqlite3_uint64
    Dim local23 As sqlite3_uint64
    Dim local24 As sqlite3_uint64
    Dim c2fb_temp_0 As UShort
    Dim c2fb_temp_1 As UByte
    Dim c2fb_temp_2 As sqlite3_uint64
    Dim c2fb_temp_3 As sqlite3_uint64
    Dim c2fb_temp_4 As sqlite3_uint64
    Dim c2fb_temp_5 As UShort
    Dim c2fb_temp_6 As UShort
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As sqlite3_uint64
    Dim c2fb_temp_10 As SqliteWhereLoop Ptr
    Dim c2fb_temp_11 As SqliteWhereLoop Ptr
    Dim c2fb_temp_12 As sqlite3_uint64
    Dim c2fb_temp_13 As UByte
    Dim c2fb_temp_14 As SQLITE_C_INT
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As SqliteExpr Ptr
    Dim c2fb_temp_18 As SqliteWhereTerm Ptr
    Dim c2fb_temp_19 As SQLITE_C_INT
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim local25 As SqliteParseContext Ptr
    Dim local26 As sqlite3CollSeq Ptr
    Dim local27 As Const SqliteExpr Ptr
    Dim local28 As sqlite3CollSeq Ptr
    Dim local29 As Byte
    Dim c2fb_temp_21 As Byte
    Dim c2fb_temp_22 As sqlite3_uint64
    Dim c2fb_temp_23 As UShort
    Dim c2fb_temp_24 As UByte
    Dim c2fb_temp_25 As UShort
    Dim c2fb_temp_26 As SqliteIndex Ptr
    Dim c2fb_temp_27 As UShort
    Dim c2fb_temp_28 As SqliteIndex Ptr
    Dim c2fb_temp_29 As UShort
    Dim c2fb_temp_30 As UShort
    Dim c2fb_temp_31 As UByte
    Dim c2fb_temp_32 As UByte
    Dim c2fb_temp_33 As UByte
    Dim c2fb_temp_34 As UByte
    Dim c2fb_temp_35 As SQLITE_C_INT
    Dim c2fb_temp_36 As SQLITE_C_INT
    Dim local30 As UByte
    Dim local31 As UShort
    Dim c2fb_temp_37 As UByte
    Dim local32 As SqliteExpr Ptr
    Dim c2fb_temp_38 As SQLITE_C_INT
    Dim c2fb_temp_39 As SQLITE_C_INT
    Dim c2fb_temp_40 As UByte
    Dim c2fb_temp_41 As SQLITE_C_INT
    Dim c2fb_temp_42 As UByte
    Dim c2fb_temp_43 As SQLITE_C_INT
    Dim c2fb_temp_44 As SQLITE_C_INT
    Dim c2fb_temp_45 As UByte
    Dim c2fb_temp_46 As UByte
    Dim c2fb_temp_47 As UByte
    Dim c2fb_temp_48 As UByte
    Dim c2fb_temp_49 As SQLITE_C_INT
    Dim c2fb_temp_50 As SQLITE_C_INT
    Dim c2fb_temp_51 As SqliteExpr Ptr
    Dim c2fb_temp_52 As UByte
    Dim local33 As SqliteExpr Ptr
    Dim c2fb_temp_53 As sqlite3CollSeq Ptr
    Dim c2fb_temp_54 As u16 Ptr
    Dim c2fb_temp_55 As UShort
    Dim c2fb_temp_56 As UByte
    Dim c2fb_temp_57 As UByte
    Dim c2fb_temp_58 As UByte
    Dim c2fb_temp_59 As sqlite3_uint64 Ptr
    Dim c2fb_temp_60 As sqlite3_uint64
    Dim c2fb_temp_61 As UByte
    Dim c2fb_temp_62 As u32 Ptr
    Dim c2fb_temp_63 As SQLITE_C_UINT
    Dim c2fb_temp_64 As UByte
    Dim c2fb_temp_65 As UByte
    Dim c2fb_temp_66 As sqlite3_uint64
    Dim c2fb_temp_67 As UByte
    Dim c2fb_temp_68 As UByte
    Dim c2fb_temp_69 As sqlite3_uint64
    Dim c2fb_temp_70 As SQLITE_C_INT
    Dim c2fb_temp_71 As SQLITE_C_INT
    Dim local34 As SqliteExpr Ptr
    Dim local35 As sqlite3_uint64
    Dim c2fb_temp_72 As SqliteExpr Ptr
    Dim c2fb_temp_73 As sqlite3_uint64
    Dim c2fb_temp_74 As sqlite3_uint64
    Dim c2fb_temp_75 As SQLITE_C_INT
    Dim c2fb_temp_76 As SQLITE_C_INT
    Dim local36 As sqlite3_uint64

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
    local20 = arg0->pParse->db
    local21 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg4) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local20)->dbOptFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H00000040ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = Cast(UShort, arg1->nExpr)
    local9 = c2fb_temp_0
    ' empty C statement
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local9) > Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))) - Cast(SQLITE_C_INT, 1ULL))))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_1 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
    local3 = c2fb_temp_1
    c2fb_temp_2 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local9)))) - Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL)))))
    local22 = c2fb_temp_2
    c2fb_temp_3 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))
    local23 = c2fb_temp_3
    c2fb_temp_4 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))
    local24 = c2fb_temp_4
    c2fb_temp_5 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0080ULL))) Or Cast(SQLITE_C_INT, &H0100ULL))))
    local6 = c2fb_temp_5
    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg3) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0800ULL) Or Cast(SQLITE_C_INT, &H0002ULL))) Or Cast(SQLITE_C_INT, &H0001ULL)))))) Then
        c2fb_temp_6 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local6) Or Cast(SQLITE_C_INT, &H0001ULL))))
        local6 = c2fb_temp_6
    End If
    c2fb_temp_7 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local10 = c2fb_temp_7
    While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3) AndAlso (-Cast(SQLITE_C_INT, ((local21 < local22)))))))) AndAlso (-Cast(SQLITE_C_INT, ((local10 <= Cast(SQLITE_C_INT, arg4)))))))))
        If (-Cast(SQLITE_C_INT, ((local10 > Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_9 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local24 Or local15->maskSelf)))
            local24 = c2fb_temp_9
        End If
        If (-Cast(SQLITE_C_INT, ((local10 < Cast(SQLITE_C_INT, arg4))))) Then
            c2fb_temp_10 = CPtr(SqliteWhereLoop Ptr Ptr, arg2->aLoop)[local10]
            local15 = c2fb_temp_10
            If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg3) And Cast(SQLITE_C_INT, &H0800ULL))) Then
                Goto c2fb_flow_1
            End If
        Else
            c2fb_temp_11 = arg5
            local15 = c2fb_temp_11
        End If
        If Cast(SQLITE_C_UINT, (local15->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000400ULL)))) Then
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local15->u.vtab.isOrdered) AndAlso (-Cast(SQLITE_C_INT, ((arg0->pOrderBy = arg1)))))))) Then
                c2fb_temp_12 = Cast(sqlite3_uint64, local22)
                local21 = c2fb_temp_12
            Else
                c2fb_temp_13 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                local3 = c2fb_temp_13
            End If
            Goto c2fb_flow_0
        End If
        c2fb_temp_14 = Cast(SQLITE_C_INT, arg0->pTabList->a(local15->iTab).iCursor)
        local13 = c2fb_temp_14
        c2fb_temp_15 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local11 = c2fb_temp_15
        While (-Cast(SQLITE_C_INT, ((local11 < Cast(SQLITE_C_INT, local9)))))
            If Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local11)))) And local21)) Then
                Goto c2fb_flow_3
            End If
            c2fb_temp_17 = CPtr(SqliteExpr Ptr, sqlite3ExprSkipCollateAndLikely(CPtr(Any Ptr, arg1->a(local11).pExpr)))
            local17 = c2fb_temp_17
            If ((-Cast(SQLITE_C_INT, ((local17 = Cast(SQLITE_C_INT, &O0ULL)))))) Then
                Goto c2fb_flow_3
            End If
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local17->op) <> Cast(SQLITE_C_INT, 168ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local17->op) <> Cast(SQLITE_C_INT, 170ULL))))))))) Then
                Goto c2fb_flow_3
            End If
            If (-Cast(SQLITE_C_INT, ((local17->iTable <> local13)))) Then
                Goto c2fb_flow_3
            End If
            c2fb_temp_18 = CPtr(SqliteWhereTerm Ptr, sqlite3WhereFindTerm(CPtr(SqliteWhereClause Ptr, @(arg0->sWC)), local13, local17->iColumn, Cast(sqlite3_uint64, (Not local24)), local6, Cast(SQLITE_C_INT, &O0ULL)))
            local16 = c2fb_temp_18
            If (-Cast(SQLITE_C_INT, ((local16 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                Goto c2fb_flow_3
            End If
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local16->eOperator) = Cast(SQLITE_C_INT, &H0001ULL))))) Then
                ' C unused-parameter annotation
                c2fb_temp_19 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local12 = c2fb_temp_19
                While (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local12 < Cast(SQLITE_C_INT, local15->nLTerm))))) AndAlso (-Cast(SQLITE_C_INT, ((local16 <> local15->aLTerm[local12]))))))))
                    ' empty C block
                c2fb_flow_5:
                    c2fb_temp_20 = local12
                    local12 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_20 + 1)))
                Wend
                c2fb_flow_4:
                If (-Cast(SQLITE_C_INT, ((local12 >= Cast(SQLITE_C_INT, local15->nLTerm))))) Then
                    Goto c2fb_flow_3
                End If
            End If
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local16->eOperator) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0080ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local17->iColumn) >= Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                local25 = arg0->pParse
                local26 = CPtr(sqlite3CollSeq Ptr, sqlite3ExprNNCollSeq(CPtr(Any Ptr, local25), CPtr(Any Ptr, arg1->a(local11).pExpr)))
                local27 = local16->pExpr
                local28 = CPtr(sqlite3CollSeq Ptr, sqlite3ExprCompareCollSeq(CPtr(Any Ptr, local25), CPtr(Any Ptr, local27)))
                ' C automatic storage declaration
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local28 = Cast(SQLITE_C_INT, &O0ULL))))) OrElse sqlite3StrICmp(CPtr(Const ZString Ptr, local26->zName), CPtr(Const ZString Ptr, local28->zName)))))) Then
                    Goto c2fb_flow_3
                End If
                c2fb_temp_21 = Cast(Byte, sqlite3ExprAffinity(CPtr(Any Ptr, local27->pRight)))
                local29 = c2fb_temp_21
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local29) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local29) <> Cast(SQLITE_C_INT, sqlite3ExprAffinity(CPtr(Any Ptr, local27->pLeft))))))))))) Then
                    Goto c2fb_flow_3
                End If
                ' empty C statement
            End If
            c2fb_temp_22 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local21 Or (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local11)))))))
            local21 = c2fb_temp_22
        c2fb_flow_3:
            c2fb_temp_16 = local11
            local11 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_16 + 1)))
        Wend
        c2fb_flow_2:
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local15->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00001000ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            If Cast(SQLITE_C_UINT, (local15->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000100ULL)))) Then
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((CPtr(SqliteExprList Ptr, local15->u.btree.pOrderBy) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local20)->dbOptFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H10000000ULL)))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) AndAlso wherePathMatchSubqueryOB(arg0, local15, local10, local13, arg1, arg6, CPtr(sqlite3_uint64 Ptr, @(local21))))))) Then
                    c2fb_temp_23 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
                    local8 = c2fb_temp_23
                    c2fb_temp_24 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                    local3 = c2fb_temp_24
                Else
                    c2fb_temp_25 = Cast(UShort, Cast(SQLITE_C_INT, 1ULL))
                    local8 = c2fb_temp_25
                End If
                c2fb_temp_26 = CPtr(SqliteIndex Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                local19 = c2fb_temp_26
                c2fb_temp_27 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
                local7 = c2fb_temp_27
            Else
                c2fb_temp_28 = CPtr(SqliteIndex Ptr, local15->u.btree.pIndex)
                local19 = c2fb_temp_28
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((c2fb_temp_28) = Cast(SQLITE_C_INT, &O0ULL))))) OrElse Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local19->flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))))))) Then
                    Return Cast(SQLITE_C_INT, &O0ULL)
                Else
                    c2fb_temp_29 = Cast(UShort, local19->nKeyCol)
                    local7 = c2fb_temp_29
                    c2fb_temp_30 = Cast(UShort, local19->nColumn)
                    local8 = c2fb_temp_30
                    ' C unused-parameter annotation
                    ' C unused-parameter annotation
                    c2fb_temp_31 = Cast(UByte, (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local19)->onError) <> Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local15->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00008000ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))))
                    local3 = c2fb_temp_31
                End If
            End If
            c2fb_temp_32 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
            local0 = c2fb_temp_32
            c2fb_temp_33 = Cast(UByte, c2fb_temp_32)
            local1 = c2fb_temp_33
            c2fb_temp_34 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
            local4 = c2fb_temp_34
            c2fb_temp_35 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local12 = c2fb_temp_35
            While (-Cast(SQLITE_C_INT, ((local12 < Cast(SQLITE_C_INT, local8)))))
                local30 = Cast(SQLITE_C_INT, 1ULL)
                ' C unused-parameter annotation
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local12 < Cast(SQLITE_C_INT, local15->u.btree.nEq))))) AndAlso (-Cast(SQLITE_C_INT, ((local12 >= Cast(SQLITE_C_INT, local15->nSkip))))))))) Then
                    local31 = local15->aLTerm[local12]->eOperator
                    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local31) And Cast(SQLITE_C_INT, local6)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local31) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0100ULL) Or Cast(SQLITE_C_INT, &H0080ULL)))))) Then
                            ' empty C statement
                            ' empty C statement
                            ' empty C statement
                            c2fb_temp_37 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                            local3 = c2fb_temp_37
                        End If
                        Goto c2fb_flow_7
                    Else
                        If (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local31) And Cast(SQLITE_C_INT, &H0001ULL)))) Then
                            local32 = local15->aLTerm[local12]->pExpr
                            c2fb_temp_38 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local12 + Cast(SQLITE_C_INT, 1ULL))))
                            local11 = c2fb_temp_38
                            While (-Cast(SQLITE_C_INT, ((local11 < Cast(SQLITE_C_INT, local15->u.btree.nEq)))))
                                If (-Cast(SQLITE_C_INT, ((local15->aLTerm[local11]->pExpr = local32)))) Then
                                    ' C unused-parameter annotation
                                    c2fb_temp_40 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                                    local30 = c2fb_temp_40
                                    Goto c2fb_flow_8
                                End If
                            c2fb_flow_9:
                                c2fb_temp_39 = local11
                                local11 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_39 + 1)))
                            Wend
                            c2fb_flow_8:
                        End If
                    End If
                End If
                If local19 Then
                    c2fb_temp_41 = Cast(SQLITE_C_INT, local19->aiColumn[local12])
                    local14 = c2fb_temp_41
                    c2fb_temp_42 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, CPtr(UByte Ptr, local19->aSortOrder)[local12]) And Cast(SQLITE_C_INT, &H01ULL))))
                    local2 = c2fb_temp_42
                    If (-Cast(SQLITE_C_INT, ((local14 = Cast(SQLITE_C_INT, local19->pTable->iPKey))))) Then
                        c2fb_temp_43 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))))
                        local14 = c2fb_temp_43
                    End If
                Else
                    c2fb_temp_44 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))))
                    local14 = c2fb_temp_44
                    c2fb_temp_45 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                    local2 = c2fb_temp_45
                End If
                If local3 Then
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local14 >= Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((local12 >= Cast(SQLITE_C_INT, local15->u.btree.nEq))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local19->pTable->aCol[local14].flags) Shr 0) And Cast(SQLITE_C_UINT, &HFULL))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                        c2fb_temp_46 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                        local3 = c2fb_temp_46
                    End If
                    If (-Cast(SQLITE_C_INT, ((local14 = (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 2ULL)))))))) Then
                        c2fb_temp_47 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                        local3 = c2fb_temp_47
                    End If
                End If
                c2fb_temp_48 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                local5 = c2fb_temp_48
                c2fb_temp_49 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local11 = c2fb_temp_49
                While (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local30) AndAlso (-Cast(SQLITE_C_INT, ((local11 < Cast(SQLITE_C_INT, local9)))))))))
                    If Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local11)))) And local21)) Then
                        Goto c2fb_flow_11
                    End If
                    c2fb_temp_51 = CPtr(SqliteExpr Ptr, sqlite3ExprSkipCollateAndLikely(CPtr(Any Ptr, arg1->a(local11).pExpr)))
                    local17 = c2fb_temp_51
                    ' empty C statement
                    ' empty C statement
                    If ((-Cast(SQLITE_C_INT, ((local17 = Cast(SQLITE_C_INT, &O0ULL)))))) Then
                        Goto c2fb_flow_11
                    End If
                    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg3) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0040ULL) Or Cast(SQLITE_C_INT, &H0080ULL))))))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        c2fb_temp_52 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                        local30 = c2fb_temp_52
                    End If
                    If (-Cast(SQLITE_C_INT, ((local14 >= (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))))))) Then
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local17->op) <> Cast(SQLITE_C_INT, 168ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local17->op) <> Cast(SQLITE_C_INT, 170ULL))))))))) Then
                            Goto c2fb_flow_11
                        End If
                        If (-Cast(SQLITE_C_INT, ((local17->iTable <> local13)))) Then
                            Goto c2fb_flow_11
                        End If
                        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local17->iColumn) <> local14)))) Then
                            Goto c2fb_flow_11
                        End If
                    Else
                        local33 = CPtr(SqliteExprList Ptr, local19->aColExpr)->a(local12).pExpr
                        If sqlite3ExprCompareSkip(CPtr(Any Ptr, local17), CPtr(Any Ptr, local33), local13) Then
                            Goto c2fb_flow_11
                        End If
                    End If
                    If (-Cast(SQLITE_C_INT, ((local14 <> (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))))))) Then
                        c2fb_temp_53 = CPtr(sqlite3CollSeq Ptr, sqlite3ExprNNCollSeq(CPtr(Any Ptr, arg0->pParse), CPtr(Any Ptr, arg1->a(local11).pExpr)))
                        local18 = c2fb_temp_53
                        If (-Cast(SQLITE_C_INT, ((sqlite3StrICmp(CPtr(Const ZString Ptr, local18->zName), CPtr(Const ZString Ptr Ptr, local19->azColl)[local12]) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                            Goto c2fb_flow_11
                        End If
                    End If
                    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg3) And Cast(SQLITE_C_INT, &H0080ULL))) Then
                        c2fb_temp_54 = CPtr(u16 Ptr, @(local15->u.btree.nDistinctCol))
                        c2fb_temp_55 = Cast(UShort, Cast(SQLITE_C_INT, (local12 + Cast(SQLITE_C_INT, 1ULL))))
                        (*c2fb_temp_54) = Cast(u16, c2fb_temp_55)
                        c2fb_temp_55 = Cast(UShort, (*c2fb_temp_54))
                    End If
                    c2fb_temp_56 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
                    local5 = c2fb_temp_56
                    Goto c2fb_flow_10
                c2fb_flow_11:
                    c2fb_temp_50 = local11
                    local11 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_50 + 1)))
                Wend
                c2fb_flow_10:
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local5) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg3) And Cast(SQLITE_C_INT, &H0040ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                    If local0 Then
                        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1) Xor Cast(SQLITE_C_INT, local2)))) <> (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->a(local11).fg.sortFlags) And Cast(SQLITE_C_INT, &H01ULL)))))))) Then
                            c2fb_temp_57 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                            local5 = c2fb_temp_57
                        End If
                    Else
                        c2fb_temp_58 = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local2) Xor (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->a(local11).fg.sortFlags) And Cast(SQLITE_C_INT, &H01ULL)))))))
                        local1 = c2fb_temp_58
                        If local1 Then
                            c2fb_temp_59 = CPtr(sqlite3_uint64 Ptr, @((*arg6)))
                            c2fb_temp_60 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, ((*c2fb_temp_59) Or (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local10)))))))
                            (*c2fb_temp_59) = c2fb_temp_60
                        End If
                        c2fb_temp_61 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
                        local0 = c2fb_temp_61
                    End If
                End If
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local5) AndAlso (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->a(local11).fg.sortFlags) And Cast(SQLITE_C_INT, &H02ULL)))))))) Then
                    If (-Cast(SQLITE_C_INT, ((local12 = Cast(SQLITE_C_INT, local15->u.btree.nEq))))) Then
                        c2fb_temp_62 = CPtr(u32 Ptr, @(local15->wsFlags))
                        c2fb_temp_63 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_62)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00080000ULL)))))
                        (*c2fb_temp_62) = Cast(u32, c2fb_temp_63)
                        c2fb_temp_63 = Cast(SQLITE_C_UINT, (*c2fb_temp_62))
                    Else
                        c2fb_temp_64 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                        local5 = c2fb_temp_64
                    End If
                End If
                If local5 Then
                    If (-Cast(SQLITE_C_INT, ((local14 = (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))))))) Then
                        ' empty C statement
                        c2fb_temp_65 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
                        local4 = c2fb_temp_65
                    End If
                    c2fb_temp_66 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local21 Or (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local11)))))))
                    local21 = c2fb_temp_66
                Else
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local12 = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local12 < Cast(SQLITE_C_INT, local7))))))))) Then
                        ' empty C statement
                        c2fb_temp_67 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                        local3 = c2fb_temp_67
                    End If
                    Goto c2fb_flow_6
                End If
            c2fb_flow_7:
                c2fb_temp_36 = local12
                local12 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_36 + 1)))
            Wend
            c2fb_flow_6:
            If local4 Then
                ' empty C statement
                c2fb_temp_68 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
                local3 = c2fb_temp_68
            End If
        End If
        If local3 Then
            c2fb_temp_69 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local23 Or local15->maskSelf)))
            local23 = c2fb_temp_69
            c2fb_temp_70 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local11 = c2fb_temp_70
            While (-Cast(SQLITE_C_INT, ((local11 < Cast(SQLITE_C_INT, local9)))))
                ' C automatic storage declaration
                ' C automatic storage declaration
                If Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local11)))) And local21)) Then
                    Goto c2fb_flow_13
                End If
                c2fb_temp_72 = arg1->a(local11).pExpr
                local34 = c2fb_temp_72
                c2fb_temp_73 = Cast(sqlite3_uint64, sqlite3WhereExprUsage(CPtr(SqliteWhereMaskSet Ptr, @(arg0->sMaskSet)), local34))
                local35 = c2fb_temp_73
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local35 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, (sqlite3ExprIsConstant(Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, local34)) = 0))))))) Then
                    Goto c2fb_flow_13
                End If
                If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local35 And Cast(sqlite3_uint64, (Not local23))))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                    c2fb_temp_74 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local21 Or (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local11)))))))
                    local21 = c2fb_temp_74
                End If
            c2fb_flow_13:
                c2fb_temp_71 = local11
                local11 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_71 + 1)))
            Wend
            c2fb_flow_12:
        End If
    c2fb_flow_1:
        c2fb_temp_8 = local10
        local10 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_8 + 1)))
    Wend
    c2fb_flow_0:
    If (-Cast(SQLITE_C_INT, ((local21 = local22)))) Then
        Return Cast(Byte, local9)
    End If
    If (-Cast(SQLITE_C_INT, (local3 = 0))) Then
        c2fb_temp_75 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local9) - Cast(SQLITE_C_INT, 1ULL))))
        local11 = c2fb_temp_75
        While (-Cast(SQLITE_C_INT, ((local11 > Cast(SQLITE_C_INT, &O0ULL)))))
            local36 = IIf(((-Cast(SQLITE_C_INT, ((local11 < (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL)))))))))))), Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local11)))) - Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL)))), Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))
            If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local21 And local36))) = local36)))) Then
                Return local11
            End If
        c2fb_flow_15:
            c2fb_temp_76 = local11
            local11 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_76 - 1)))
        Wend
        c2fb_flow_14:
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    Return Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))
End Function

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
    c2fb_temp_0 = Cast(Short, sqlite3LogEst(Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (arg0->pSelect->pEList->nExpr + Cast(SQLITE_C_INT, 59ULL)))) \ Cast(SQLITE_C_INT, 30ULL)))))
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

Private Function computeMxChoice CDecl Alias "computeMxChoice" (ByVal arg0 As SqliteWhereInfo Ptr) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SqliteWhereLoop Ptr
    Dim local2 As SqliteSrcItem Ptr
    Dim local3 As SQLITE_C_INT
    Dim local4 As sqlite3_uint64
    Dim local5 As sqlite3_uint64
    Dim local6 As SqliteWhereLoop Ptr
    Dim c2fb_temp_0 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SqliteSrcItem Ptr
    Dim c2fb_temp_3 As SqliteWhereLoop Ptr
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As sqlite3_uint64
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As sqlite3_uint64
    Dim local7 As SQLITE_C_INT
    Dim local8 As Short
    Dim local9 As sqlite3_uint64
    Dim local10 As SqliteSrcItem Ptr
    Dim c2fb_temp_8 As SqliteSrcItem Ptr
    Dim c2fb_temp_9 As SqliteWhereLoop Ptr
    Dim c2fb_temp_10 As SqliteWhereLoop Ptr
    Dim c2fb_temp_11 As SqliteWhereLoop Ptr
    Dim c2fb_temp_12 As sqlite3_uint64
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As sqlite3_uint64
    Dim c2fb_temp_15 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_16 As SQLITE_C_INT
    Dim c2fb_temp_17 As Short
    Dim c2fb_temp_18 As SqliteWhereLoop Ptr
    Dim c2fb_temp_19 As SqliteWhereLoop Ptr
    Dim c2fb_temp_20 As Short
    Dim c2fb_temp_21 As Short
    Dim c2fb_temp_22 As SqliteWhereLoop Ptr
    Dim c2fb_temp_23 As SqliteWhereLoop Ptr
    Dim c2fb_temp_24 As Short Ptr
    Dim c2fb_temp_25 As Short

    local0 = arg0->nLevel
    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local0 >= Cast(SQLITE_C_INT, 4ULL))))) AndAlso (-Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg0->flags) Shr 4) And Cast(SQLITE_C_UINT, &H1ULL))) = 0))))))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg0->pParse->db)->dbOptFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H20000000ULL)))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        local5 = Cast(SQLITE_C_INT, &O0ULL)
        ' C automatic storage declaration
        c2fb_temp_0 = CPtr(SQLITE_C_UINT Ptr, @(arg0->flags))
        c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
        c2fb_temp_1 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_1) And Cast(SQLITE_C_UINT, &H1ULL)))
        (*c2fb_temp_0) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_0)) And Not(Cast(SQLITE_C_UINT, &H10ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_1) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 4)))
        c2fb_temp_1 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_1) And Cast(SQLITE_C_UINT, &H1ULL)))
        ' C unused-parameter annotation
        c2fb_temp_2 = CPtr(SqliteSrcItem Ptr, (@arg0->pTabList->a(0)))
        local2 = c2fb_temp_2
        c2fb_temp_3 = CPtr(SqliteWhereLoop Ptr, arg0->pLoops)
        local6 = c2fb_temp_3
        c2fb_temp_4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local3 = c2fb_temp_4
        c2fb_temp_5 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))
        local4 = c2fb_temp_5
        While (-Cast(SQLITE_C_INT, ((local3 < local0))))
            local7 = Cast(SQLITE_C_INT, &O0ULL)
            ' C automatic storage declaration
            local9 = Cast(SQLITE_C_INT, &O0ULL)
            ' C automatic storage declaration
            c2fb_temp_8 = CPtr(SqliteSrcItem Ptr, (local2 + local3))
            local10 = c2fb_temp_8
            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local10->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H20ULL) Or Cast(SQLITE_C_INT, &H02ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local3 + Cast(SQLITE_C_INT, 3ULL))) > local0)))) Then
                    Goto c2fb_flow_0
                End If
                While (-Cast(SQLITE_C_INT, ((local6 AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local6->iTab) <= local3))))))))
                    c2fb_temp_9 = CPtr(SqliteWhereLoop Ptr, local6->pNextLoop)
                    local6 = c2fb_temp_9
                c2fb_flow_3:
                Wend
                c2fb_flow_2:
            End If
            c2fb_temp_10 = local6
            local1 = c2fb_temp_10
            While local1
                If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local2[local1->iTab].fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H20ULL) Or Cast(SQLITE_C_INT, &H02ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                    Goto c2fb_flow_4
                End If
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local1->prereq And local4))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local1->maskSelf And local9))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local1->maskSelf And local5))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
                    If (-Cast(SQLITE_C_INT, ((local2[local1->iTab].pSTab = local10->pSTab)))) Then
                        c2fb_temp_12 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local5 Or local4)))
                        local5 = c2fb_temp_12
                    Else
                        c2fb_temp_13 = local7
                        local7 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_13 + 1)))
                        c2fb_temp_14 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local9 Or local1->maskSelf)))
                        local9 = c2fb_temp_14
                    End If
                End If
            c2fb_flow_5:
                c2fb_temp_11 = CPtr(SqliteWhereLoop Ptr, local1->pNextLoop)
                local1 = c2fb_temp_11
            Wend
            c2fb_flow_4:
            If (-Cast(SQLITE_C_INT, ((local7 <= Cast(SQLITE_C_INT, 2ULL))))) Then
                Goto c2fb_flow_1
            End If
            c2fb_temp_15 = CPtr(SQLITE_C_UINT Ptr, @(arg0->flags))
            c2fb_temp_16 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
            c2fb_temp_16 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_16) And Cast(SQLITE_C_UINT, &H1ULL)))
            (*c2fb_temp_15) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_15)) And Not(Cast(SQLITE_C_UINT, &H20ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_16) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 5)))
            c2fb_temp_16 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_16) And Cast(SQLITE_C_UINT, &H1ULL)))
            c2fb_temp_17 = Cast(Short, (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 32768ULL)))))
            local8 = c2fb_temp_17
            c2fb_temp_18 = local6
            local1 = c2fb_temp_18
            While local1
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->iTab) < local3)))) Then
                    Goto c2fb_flow_7
                End If
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->iTab) > local3)))) Then
                    Goto c2fb_flow_6
                End If
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->rRun) > Cast(SQLITE_C_INT, local8))))) Then
                    c2fb_temp_20 = Cast(Short, local1->rRun)
                    local8 = c2fb_temp_20
                End If
            c2fb_flow_7:
                c2fb_temp_19 = CPtr(SqliteWhereLoop Ptr, local1->pNextLoop)
                local1 = c2fb_temp_19
            Wend
            c2fb_flow_6:
            If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local8) < (Cast(SQLITE_C_INT, 32767ULL))))))) Then
                c2fb_temp_21 = local8
                local8 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_21) + 1)))
            End If
            c2fb_temp_22 = local6
            local1 = c2fb_temp_22
            While local1
                If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local1->maskSelf And local9))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                    Goto c2fb_flow_9
                End If
                If local1->nLTerm Then
                    Goto c2fb_flow_9
                End If
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->rRun) < Cast(SQLITE_C_INT, local8))))) Then
                    c2fb_temp_24 = CPtr(Short Ptr, @(local1->rRun))
                    c2fb_temp_25 = Cast(Short, local8)
                    (*c2fb_temp_24) = c2fb_temp_25
                End If
            c2fb_flow_9:
                c2fb_temp_23 = CPtr(SqliteWhereLoop Ptr, local1->pNextLoop)
                local1 = c2fb_temp_23
            Wend
            c2fb_flow_8:
        c2fb_flow_1:
            c2fb_temp_6 = local3
            local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_6 + 1)))
            c2fb_temp_7 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local4 Shl Cast(SQLITE_C_INT, 1ULL))))
            local4 = c2fb_temp_7
        Wend
        c2fb_flow_0:
    End If
    Return IIf(Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, arg0->flags) Shr 5) And Cast(SQLITE_C_UINT, &H1ULL))), Cast(SQLITE_C_INT, 18ULL), Cast(SQLITE_C_INT, 12ULL))
End Function

Private Function whereLoopIsNoBetter CDecl Alias "whereLoopIsNoBetter" (ByVal arg0 As Const SqliteWhereLoop Ptr, ByVal arg1 As Const SqliteWhereLoop Ptr) As SQLITE_C_INT
    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg0->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000200ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (arg1->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000200ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, CPtr(SqliteIndex Ptr, arg0->u.btree.pIndex)->szIdxRow) < Cast(SQLITE_C_INT, CPtr(SqliteIndex Ptr, arg1->u.btree.pIndex)->szIdxRow))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    Return Cast(SQLITE_C_INT, 1ULL)
End Function

Private Function wherePathSolver CDecl Alias "wherePathSolver" (ByVal arg0 As SqliteWhereInfo Ptr, ByVal arg1 As Short) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim local2 As SqliteParseContext Ptr
    Dim local3 As SQLITE_C_INT
    Dim local4 As SQLITE_C_INT
    Dim local5 As SQLITE_C_INT
    Dim local6 As SQLITE_C_INT
    Dim local7 As SQLITE_C_INT
    Dim local8 As Short
    Dim local9 As Short
    Dim local10 As SQLITE_C_INT
    Dim local11 As SQLITE_C_INT
    Dim local12 As SqliteWherePath Ptr
    Dim local13 As SqliteWherePath Ptr
    Dim local14 As SqliteWherePath Ptr
    Dim local15 As SqliteWherePath Ptr
    Dim local16 As SqliteWhereLoop Ptr
    Dim local17 As SqliteWhereLoop Ptr Ptr
    Dim local18 As Short Ptr
    Dim local19 As ZString Ptr
    Dim local20 As SQLITE_C_INT
    Dim c2fb_temp_0 As SqliteParseContext Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SQLITE_C_INT
    Dim c2fb_temp_8 As SQLITE_C_INT
    Dim c2fb_temp_9 As SQLITE_C_INT
    Dim c2fb_temp_10 As ZString Ptr
    Dim c2fb_temp_11 As SqliteWherePath Ptr
    Dim c2fb_temp_12 As SqliteWherePath Ptr
    Dim c2fb_temp_13 As Any Ptr
    Dim c2fb_temp_14 As SqliteWhereLoop Ptr Ptr
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As SqliteWherePath Ptr
    Dim c2fb_temp_17 As SQLITE_C_INT
    Dim c2fb_temp_18 As SqliteWherePath Ptr
    Dim c2fb_temp_19 As SqliteWhereLoop Ptr Ptr
    Dim c2fb_temp_20 As Any Ptr Ptr
    Dim c2fb_temp_21 As SqliteWhereLoop Ptr Ptr
    Dim c2fb_temp_22 As Short Ptr
    Dim c2fb_temp_23 As Any Ptr
    Dim c2fb_temp_24 As Short Ptr
    Dim c2fb_temp_25 As Short
    Dim c2fb_temp_26 As SQLITE_C_INT
    Dim c2fb_temp_27 As Byte Ptr
    Dim c2fb_temp_28 As Byte
    Dim c2fb_temp_29 As SQLITE_C_INT
    Dim c2fb_temp_30 As SQLITE_C_INT
    Dim c2fb_temp_31 As SQLITE_C_INT
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As SqliteWherePath Ptr
    Dim c2fb_temp_34 As SQLITE_C_INT
    Dim c2fb_temp_35 As SqliteWherePath Ptr
    Dim c2fb_temp_36 As SqliteWhereLoop Ptr
    Dim c2fb_temp_37 As SqliteWhereLoop Ptr
    Dim local21 As Short
    Dim local22 As Short
    Dim local23 As Short
    Dim local24 As Byte
    Dim local25 As sqlite3_uint64
    Dim local26 As sqlite3_uint64
    Dim c2fb_temp_38 As Short
    Dim c2fb_temp_39 As Short
    Dim c2fb_temp_40 As Short
    Dim c2fb_temp_41 As Short
    Dim c2fb_temp_42 As sqlite3_uint64
    Dim c2fb_temp_43 As Byte
    Dim c2fb_temp_44 As sqlite3_uint64
    Dim c2fb_temp_45 As Byte
    Dim c2fb_temp_46 As sqlite3_uint64
    Dim c2fb_temp_47 As Short Ptr
    Dim c2fb_temp_48 As Short
    Dim c2fb_temp_49 As Short
    Dim c2fb_temp_50 As Short
    Dim c2fb_temp_51 As Short
    Dim c2fb_temp_52 As SQLITE_C_INT
    Dim c2fb_temp_53 As SqliteWherePath Ptr
    Dim c2fb_temp_54 As SQLITE_C_INT
    Dim c2fb_temp_55 As SqliteWherePath Ptr
    Dim c2fb_temp_56 As SQLITE_C_INT
    Dim c2fb_temp_57 As SQLITE_C_INT
    Dim c2fb_temp_58 As SQLITE_C_INT
    Dim c2fb_temp_59 As SqliteWherePath Ptr
    Dim c2fb_temp_60 As sqlite3_uint64 Ptr
    Dim c2fb_temp_61 As sqlite3_uint64
    Dim c2fb_temp_62 As sqlite3_uint64 Ptr
    Dim c2fb_temp_63 As sqlite3_uint64
    Dim c2fb_temp_64 As Short Ptr
    Dim c2fb_temp_65 As Short
    Dim c2fb_temp_66 As Short Ptr
    Dim c2fb_temp_67 As Short
    Dim c2fb_temp_68 As Short Ptr
    Dim c2fb_temp_69 As Short
    Dim c2fb_temp_70 As Byte Ptr
    Dim c2fb_temp_71 As Byte
    Dim c2fb_temp_72 As Any Ptr
    Dim c2fb_temp_73 As Any Ptr Ptr
    Dim c2fb_temp_74 As SqliteWhereLoop Ptr
    Dim c2fb_temp_75 As SQLITE_C_INT
    Dim c2fb_temp_76 As Short
    Dim c2fb_temp_77 As Short
    Dim c2fb_temp_78 As SQLITE_C_INT
    Dim c2fb_temp_79 As SqliteWherePath Ptr
    Dim c2fb_temp_80 As SQLITE_C_INT
    Dim c2fb_temp_81 As SqliteWherePath Ptr
    Dim c2fb_temp_82 As Short
    Dim c2fb_temp_83 As Short
    Dim c2fb_temp_84 As SQLITE_C_INT
    Dim c2fb_temp_85 As SqliteWherePath Ptr
    Dim c2fb_temp_86 As SqliteWherePath Ptr
    Dim c2fb_temp_87 As SqliteWherePath Ptr
    Dim c2fb_temp_88 As SQLITE_C_INT
    Dim c2fb_temp_89 As SqliteWherePath Ptr
    Dim c2fb_temp_90 As SQLITE_C_INT
    Dim c2fb_temp_91 As SQLITE_C_INT
    Dim local27 As SqliteWhereLevel Ptr
    Dim c2fb_temp_92 As SqliteWhereLoop Ptr
    Dim c2fb_temp_93 As SqliteWhereLoop Ptr Ptr
    Dim c2fb_temp_94 As SqliteWhereLoop Ptr
    Dim c2fb_temp_95 As u8 Ptr
    Dim c2fb_temp_96 As UByte
    Dim c2fb_temp_97 As SQLITE_C_INT Ptr
    Dim c2fb_temp_98 As SQLITE_C_INT
    Dim local28 As sqlite3_uint64
    Dim local29 As SQLITE_C_INT
    Dim c2fb_temp_99 As u8 Ptr
    Dim c2fb_temp_100 As UByte
    Dim c2fb_temp_101 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_102 As SQLITE_C_INT
    Dim c2fb_temp_103 As Byte Ptr
    Dim c2fb_temp_104 As Byte
    Dim c2fb_temp_105 As u8 Ptr
    Dim c2fb_temp_106 As UByte
    Dim c2fb_temp_107 As sqlite3_uint64 Ptr
    Dim c2fb_temp_108 As sqlite3_uint64
    Dim c2fb_temp_109 As Byte Ptr
    Dim c2fb_temp_110 As Byte
    Dim local30 As SQLITE_C_UINT
    Dim local31 As sqlite3_uint64
    Dim local32 As SQLITE_C_INT
    Dim c2fb_temp_111 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_112 As SQLITE_C_INT
    Dim c2fb_temp_113 As sqlite3_uint64 Ptr
    Dim c2fb_temp_114 As sqlite3_uint64
    Dim c2fb_temp_115 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_116 As SQLITE_C_INT
    Dim local33 As sqlite3_uint64
    Dim local34 As SQLITE_C_INT
    Dim c2fb_temp_117 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_118 As SQLITE_C_INT
    Dim c2fb_temp_119 As sqlite3_uint64 Ptr
    Dim c2fb_temp_120 As sqlite3_uint64
    Dim c2fb_temp_121 As Short Ptr
    Dim c2fb_temp_122 As Short

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local6 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    local8 = Cast(SQLITE_C_INT, &O0ULL)
    local9 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local18 = Cast(SQLITE_C_INT, &O0ULL)
    ' C automatic storage declaration
    ' C automatic storage declaration
    c2fb_temp_0 = arg0->pParse
    local2 = c2fb_temp_0
    c2fb_temp_1 = Cast(SQLITE_C_INT, arg0->nLevel)
    local1 = c2fb_temp_1
    ' empty C statement
    If (-Cast(SQLITE_C_INT, ((local1 <= Cast(SQLITE_C_INT, 1ULL))))) Then
        c2fb_temp_2 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
        local0 = c2fb_temp_2
    Else
        If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, 2ULL))))) Then
            c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 5ULL))
            local0 = c2fb_temp_3
        Else
            If local2->nErr Then
                c2fb_temp_4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                local0 = c2fb_temp_4
            Else
                c2fb_temp_5 = Cast(SQLITE_C_INT, computeMxChoice(arg0))
                local0 = c2fb_temp_5
            End If
        End If
    End If
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg0->pOrderBy = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        c2fb_temp_6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local7 = c2fb_temp_6
    Else
        c2fb_temp_7 = Cast(SQLITE_C_INT, arg0->pOrderBy->nExpr)
        local7 = c2fb_temp_7
    End If
    c2fb_temp_8 = Cast(SQLITE_C_INT, Cast(sqlite3_uint64, (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWherePath))) + Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereLoop Ptr))) * Cast(sqlite3_uint64, local1)))))) * Cast(sqlite3_uint64, local0))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 2ULL)))))
    local20 = c2fb_temp_8
    c2fb_temp_9 = Cast(SQLITE_C_INT, Cast(sqlite3_uint64, (Cast(sqlite3_uint64, local20) + Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(Short))) * Cast(sqlite3_uint64, local7))))))
    local20 = c2fb_temp_9
    c2fb_temp_10 = CPtr(ZString Ptr, CPtr(Any Ptr, sqlite3DbMallocRawNN(CPtr(Any Ptr, local2->db), local20)))
    local19 = c2fb_temp_10
    If (-Cast(SQLITE_C_INT, ((local19 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, 7ULL)
    End If
    c2fb_temp_11 = CPtr(SqliteWherePath Ptr, local19)
    local13 = c2fb_temp_11
    c2fb_temp_12 = CPtr(SqliteWherePath Ptr, (local13 + local0))
    local12 = c2fb_temp_12
    c2fb_temp_13 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, local12), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteWherePath))))
    c2fb_temp_14 = CPtr(SqliteWhereLoop Ptr Ptr, (CPtr(SqliteWherePath Ptr, (local12 + local0))))
    local17 = c2fb_temp_14
    c2fb_temp_15 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (local0 * Cast(SQLITE_C_INT, 2ULL))))
    local4 = c2fb_temp_15
    c2fb_temp_16 = local13
    local14 = c2fb_temp_16
    While (-Cast(SQLITE_C_INT, ((local4 > Cast(SQLITE_C_INT, &O0ULL)))))
        c2fb_temp_20 = CPtr(Any Ptr Ptr, @(local14->aLoop))
        c2fb_temp_21 = local17
        (*c2fb_temp_20) = CPtr(Any Ptr, c2fb_temp_21)
        c2fb_temp_21 = CPtr(SqliteWhereLoop Ptr Ptr, (*c2fb_temp_20))
    c2fb_flow_1:
        c2fb_temp_17 = local4
        local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_17 - 1)))
        c2fb_temp_18 = local14
        local14 = (c2fb_temp_18 + 1)
        c2fb_temp_19 = CPtr(SqliteWhereLoop Ptr Ptr, (local17 + local1))
        local17 = c2fb_temp_19
    Wend
    c2fb_flow_0:
    If local7 Then
        c2fb_temp_22 = CPtr(Short Ptr, local17)
        local18 = c2fb_temp_22
        c2fb_temp_23 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, local18), Cast(SQLITE_C_INT, &O0ULL), Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(Short))) * Cast(sqlite3_uint64, local7)))))
    End If
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_24 = CPtr(Short Ptr, @(local12[Cast(SQLITE_C_INT, &O0ULL)].nRow))
    c2fb_temp_25 = Cast(Short, (IIf((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local2->nQueryLoop)) < (Cast(SQLITE_C_INT, 48ULL)))))), Cast(SQLITE_C_INT, (local2->nQueryLoop)), (Cast(SQLITE_C_INT, 48ULL)))))
    (*c2fb_temp_24) = c2fb_temp_25
    ' C unused-parameter annotation
    c2fb_temp_26 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
    local11 = c2fb_temp_26
    ' C unused-parameter annotation
    If local7 Then
        c2fb_temp_27 = CPtr(Byte Ptr, @(local12[Cast(SQLITE_C_INT, &O0ULL)].isOrdered))
        c2fb_temp_28 = Cast(Byte, IIf((-Cast(SQLITE_C_INT, ((local1 > Cast(SQLITE_C_INT, &O0ULL))))), Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), local7))
        (*c2fb_temp_27) = c2fb_temp_28
    End If
    c2fb_temp_29 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local3 = c2fb_temp_29
    While (-Cast(SQLITE_C_INT, ((local3 < local1))))
        c2fb_temp_31 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local10 = c2fb_temp_31
        c2fb_temp_32 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local4 = c2fb_temp_32
        c2fb_temp_33 = local12
        local14 = c2fb_temp_33
        While (-Cast(SQLITE_C_INT, ((local4 < local11))))
            c2fb_temp_36 = CPtr(SqliteWhereLoop Ptr, arg0->pLoops)
            local16 = c2fb_temp_36
            While local16
                ' C automatic storage declaration
                ' C automatic storage declaration
                ' C automatic storage declaration
                ' C automatic storage declaration
                ' C automatic storage declaration
                ' C automatic storage declaration
                If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local16->prereq And Cast(sqlite3_uint64, (Not local14->maskLoop))))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                    Goto c2fb_flow_7
                End If
                If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local16->maskSelf And local14->maskLoop))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                    Goto c2fb_flow_7
                End If
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local16->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00004000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local14->nRow) < Cast(SQLITE_C_INT, 3ULL))))))))) Then
                    ' C unused-parameter annotation
                    Goto c2fb_flow_7
                End If
                c2fb_temp_38 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local16->rRun) + Cast(SQLITE_C_INT, local14->nRow))))
                local23 = c2fb_temp_38
                If local16->rSetup Then
                    c2fb_temp_39 = Cast(Short, sqlite3LogEstAdd(local16->rSetup, local23))
                    local23 = c2fb_temp_39
                End If
                c2fb_temp_40 = Cast(Short, sqlite3LogEstAdd(local23, local14->rUnsort))
                local23 = c2fb_temp_40
                c2fb_temp_41 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local14->nRow) + Cast(SQLITE_C_INT, local16->nOut))))
                local21 = c2fb_temp_41
                c2fb_temp_42 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local14->maskLoop Or local16->maskSelf)))
                local25 = c2fb_temp_42
                c2fb_temp_43 = Cast(Byte, local14->isOrdered)
                local24 = c2fb_temp_43
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local24) < Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_44 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))
                    local26 = c2fb_temp_44
                    c2fb_temp_45 = Cast(Byte, wherePathSatisfiesOrderBy(arg0, arg0->pOrderBy, local14, arg0->wctrlFlags, local3, local16, CPtr(sqlite3_uint64 Ptr, @(local26))))
                    local24 = c2fb_temp_45
                Else
                    c2fb_temp_46 = Cast(sqlite3_uint64, local14->revLoop)
                    local26 = c2fb_temp_46
                End If
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local24) >= Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local24) < local7)))))))) Then
                    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local18[local24]) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                        c2fb_temp_47 = CPtr(Short Ptr, @(local18[local24]))
                        c2fb_temp_48 = Cast(Short, whereSortingCost(arg0, arg1, local7, local24))
                        (*c2fb_temp_47) = c2fb_temp_48
                    End If
                    c2fb_temp_49 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, sqlite3LogEstAdd(local23, local18[local24])) + Cast(SQLITE_C_INT, 3ULL))))
                    local22 = c2fb_temp_49
                    ' empty C statement
                Else
                    c2fb_temp_50 = Cast(Short, local23)
                    local22 = c2fb_temp_50
                    c2fb_temp_51 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local23) - Cast(SQLITE_C_INT, 2ULL))))
                    local23 = c2fb_temp_51
                End If
                ' empty C statement
                c2fb_temp_52 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local5 = c2fb_temp_52
                c2fb_temp_53 = local13
                local15 = c2fb_temp_53
                While (-Cast(SQLITE_C_INT, ((local5 < local10))))
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local15->maskLoop = local25)))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local15->isOrdered) Xor Cast(SQLITE_C_INT, local24)))) And Cast(SQLITE_C_INT, &H80ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, (local1 - Cast(SQLITE_C_INT, 1ULL)))))))))))))))) Then
                        ' empty C statement
                        Goto c2fb_flow_8
                    End If
                c2fb_flow_9:
                    c2fb_temp_54 = local5
                    local5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_54 + 1)))
                    c2fb_temp_55 = local15
                    local15 = (c2fb_temp_55 + 1)
                Wend
                c2fb_flow_8:
                If (-Cast(SQLITE_C_INT, ((local5 >= local10)))) Then
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local10 >= local0)))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local22) > Cast(SQLITE_C_INT, local8))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local22) = Cast(SQLITE_C_INT, local8))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local23) >= Cast(SQLITE_C_INT, local9))))))))))))))))))) Then
                        Goto c2fb_flow_7
                    End If
                    If (-Cast(SQLITE_C_INT, ((local10 < local0)))) Then
                        c2fb_temp_56 = local10
                        local10 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_56 + 1)))
                        c2fb_temp_57 = Cast(SQLITE_C_INT, c2fb_temp_56)
                        local5 = c2fb_temp_57
                    Else
                        c2fb_temp_58 = Cast(SQLITE_C_INT, local6)
                        local5 = c2fb_temp_58
                    End If
                    c2fb_temp_59 = CPtr(SqliteWherePath Ptr, @(local13[local5]))
                    local15 = c2fb_temp_59
                Else
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local15->rCost) < Cast(SQLITE_C_INT, local22)))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local15->rCost) = Cast(SQLITE_C_INT, local22))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local15->nRow) < Cast(SQLITE_C_INT, local21)))))))))))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local15->rCost) = Cast(SQLITE_C_INT, local22))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local15->nRow) = Cast(SQLITE_C_INT, local21))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local15->rUnsort) < Cast(SQLITE_C_INT, local23)))))))))))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local15->rCost) = Cast(SQLITE_C_INT, local22))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local15->nRow) = Cast(SQLITE_C_INT, local21))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local15->rUnsort) = Cast(SQLITE_C_INT, local23))))))))) AndAlso whereLoopIsNoBetter(CPtr(Const SqliteWhereLoop Ptr, local16), CPtr(Const SqliteWhereLoop Ptr, CPtr(SqliteWhereLoop Ptr Ptr, local15->aLoop)[local3]))))))))))) Then
                        ' empty C statement
                        Goto c2fb_flow_7
                    End If
                    ' empty C statement
                End If
                c2fb_temp_60 = CPtr(sqlite3_uint64 Ptr, @(local15->maskLoop))
                c2fb_temp_61 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local14->maskLoop Or local16->maskSelf)))
                (*c2fb_temp_60) = c2fb_temp_61
                c2fb_temp_62 = CPtr(sqlite3_uint64 Ptr, @(local15->revLoop))
                c2fb_temp_63 = Cast(sqlite3_uint64, local26)
                (*c2fb_temp_62) = c2fb_temp_63
                c2fb_temp_64 = CPtr(Short Ptr, @(local15->nRow))
                c2fb_temp_65 = Cast(Short, local21)
                (*c2fb_temp_64) = c2fb_temp_65
                c2fb_temp_66 = CPtr(Short Ptr, @(local15->rCost))
                c2fb_temp_67 = Cast(Short, local22)
                (*c2fb_temp_66) = c2fb_temp_67
                c2fb_temp_68 = CPtr(Short Ptr, @(local15->rUnsort))
                c2fb_temp_69 = Cast(Short, local23)
                (*c2fb_temp_68) = c2fb_temp_69
                c2fb_temp_70 = CPtr(Byte Ptr, @(local15->isOrdered))
                c2fb_temp_71 = Cast(Byte, local24)
                (*c2fb_temp_70) = c2fb_temp_71
                c2fb_temp_72 = CPtr(Any Ptr, c2fb_crt_memcpy(CPtr(Any Ptr, CPtr(SqliteWhereLoop Ptr Ptr, local15->aLoop)), CPtr(Const Any Ptr, CPtr(SqliteWhereLoop Ptr Ptr, local14->aLoop)), Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereLoop Ptr))) * Cast(sqlite3_uint64, local3)))))
                c2fb_temp_73 = CPtr(Any Ptr Ptr, @(CPtr(SqliteWhereLoop Ptr Ptr, local15->aLoop)[local3]))
                c2fb_temp_74 = local16
                (*c2fb_temp_73) = CPtr(Any Ptr, c2fb_temp_74)
                c2fb_temp_74 = CPtr(SqliteWhereLoop Ptr, (*c2fb_temp_73))
                If (-Cast(SQLITE_C_INT, ((local10 >= local0)))) Then
                    c2fb_temp_75 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                    local6 = c2fb_temp_75
                    c2fb_temp_76 = Cast(Short, local13[Cast(SQLITE_C_INT, &O0ULL)].rCost)
                    local8 = c2fb_temp_76
                    c2fb_temp_77 = Cast(Short, local13[Cast(SQLITE_C_INT, &O0ULL)].nRow)
                    local9 = c2fb_temp_77
                    c2fb_temp_78 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                    local5 = c2fb_temp_78
                    c2fb_temp_79 = CPtr(SqliteWherePath Ptr, @(local13[Cast(SQLITE_C_INT, 1ULL)]))
                    local15 = c2fb_temp_79
                    While (-Cast(SQLITE_C_INT, ((local5 < local0))))
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local15->rCost) > Cast(SQLITE_C_INT, local8))))) OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local15->rCost) = Cast(SQLITE_C_INT, local8))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local15->rUnsort) > Cast(SQLITE_C_INT, local9)))))))))))))) Then
                            c2fb_temp_82 = Cast(Short, local15->rCost)
                            local8 = c2fb_temp_82
                            c2fb_temp_83 = Cast(Short, local15->rUnsort)
                            local9 = c2fb_temp_83
                            c2fb_temp_84 = Cast(SQLITE_C_INT, local5)
                            local6 = c2fb_temp_84
                        End If
                    c2fb_flow_11:
                        c2fb_temp_80 = local5
                        local5 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_80 + 1)))
                        c2fb_temp_81 = local15
                        local15 = (c2fb_temp_81 + 1)
                    Wend
                    c2fb_flow_10:
                End If
            c2fb_flow_7:
                c2fb_temp_37 = CPtr(SqliteWhereLoop Ptr, local16->pNextLoop)
                local16 = c2fb_temp_37
            Wend
            c2fb_flow_6:
        c2fb_flow_5:
            c2fb_temp_34 = local4
            local4 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_34 + 1)))
            c2fb_temp_35 = local14
            local14 = (c2fb_temp_35 + 1)
        Wend
        c2fb_flow_4:
        c2fb_temp_85 = local13
        local14 = c2fb_temp_85
        c2fb_temp_86 = local12
        local13 = c2fb_temp_86
        c2fb_temp_87 = local14
        local12 = c2fb_temp_87
        c2fb_temp_88 = Cast(SQLITE_C_INT, local10)
        local11 = c2fb_temp_88
    c2fb_flow_3:
        c2fb_temp_30 = local3
        local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_30 + 1)))
    Wend
    c2fb_flow_2:
    If (-Cast(SQLITE_C_INT, ((local11 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3ErrorMsg(CPtr(Any Ptr, local2), StrPtr(!"no query solution"))
        sqlite3DbFreeNN(CPtr(Any Ptr, local2->db), CPtr(Any Ptr, local19))
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    ' C unused-parameter annotation
    c2fb_temp_89 = local12
    local14 = c2fb_temp_89
    ' C unused-parameter annotation
    c2fb_temp_90 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local3 = c2fb_temp_90
    While (-Cast(SQLITE_C_INT, ((local3 < local1))))
        local27 = CPtr(SqliteWhereLevel Ptr, (CPtr(SqliteWhereLevel Ptr, (@arg0->a(0))) + local3))
        c2fb_temp_93 = CPtr(SqliteWhereLoop Ptr Ptr, @(local27->pWLoop))
        c2fb_temp_92 = CPtr(SqliteWhereLoop Ptr Ptr, local14->aLoop)[local3]
        local16 = c2fb_temp_92
        c2fb_temp_94 = c2fb_temp_92
        (*c2fb_temp_93) = c2fb_temp_94
        c2fb_temp_95 = CPtr(u8 Ptr, @(local27->iFrom))
        c2fb_temp_96 = Cast(UByte, local16->iTab)
        (*c2fb_temp_95) = Cast(u8, c2fb_temp_96)
        c2fb_temp_96 = Cast(UByte, (*c2fb_temp_95))
        c2fb_temp_97 = CPtr(SQLITE_C_INT Ptr, @(local27->iTabCur))
        c2fb_temp_98 = Cast(SQLITE_C_INT, arg0->pTabList->a(local27->iFrom).iCursor)
        (*c2fb_temp_97) = c2fb_temp_98
    c2fb_flow_13:
        c2fb_temp_91 = local3
        local3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_91 + 1)))
    Wend
    c2fb_flow_12:
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->wctrlFlags) And Cast(SQLITE_C_INT, &H0100ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->wctrlFlags) And Cast(SQLITE_C_INT, &H0080ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->eDistinct) = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso Cast(SQLITE_C_INT, arg1))))) Then
        ' C automatic storage declaration
        local29 = wherePathSatisfiesOrderBy(arg0, arg0->pResultSet, local14, Cast(SQLITE_C_INT, &H0080ULL), Cast(SQLITE_C_INT, (local1 - Cast(SQLITE_C_INT, 1ULL))), CPtr(SqliteWhereLoop Ptr Ptr, local14->aLoop)[Cast(SQLITE_C_INT, (local1 - Cast(SQLITE_C_INT, 1ULL)))], CPtr(sqlite3_uint64 Ptr, @(local28)))
        If (-Cast(SQLITE_C_INT, ((local29 = arg0->pResultSet->nExpr)))) Then
            c2fb_temp_99 = CPtr(u8 Ptr, @(arg0->eDistinct))
            c2fb_temp_100 = Cast(UByte, Cast(SQLITE_C_INT, 2ULL))
            (*c2fb_temp_99) = Cast(u8, c2fb_temp_100)
            c2fb_temp_100 = Cast(UByte, (*c2fb_temp_99))
        End If
    End If
    c2fb_temp_101 = CPtr(SQLITE_C_UINT Ptr, @(arg0->flags))
    c2fb_temp_102 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    c2fb_temp_102 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_102) And Cast(SQLITE_C_UINT, &H1ULL)))
    (*c2fb_temp_101) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_101)) And Not(Cast(SQLITE_C_UINT, &H4ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_102) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 2)))
    c2fb_temp_102 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_102) And Cast(SQLITE_C_UINT, &H1ULL)))
    If arg0->pOrderBy Then
        c2fb_temp_103 = CPtr(Byte Ptr, @(arg0->nOBSat))
        c2fb_temp_104 = Cast(Byte, local14->isOrdered)
        (*c2fb_temp_103) = c2fb_temp_104
        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->wctrlFlags) And Cast(SQLITE_C_INT, &H0080ULL))) Then
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local14->isOrdered) = arg0->pOrderBy->nExpr)))) Then
                c2fb_temp_105 = CPtr(u8 Ptr, @(arg0->eDistinct))
                c2fb_temp_106 = Cast(UByte, Cast(SQLITE_C_INT, 2ULL))
                (*c2fb_temp_105) = Cast(u8, c2fb_temp_106)
                c2fb_temp_106 = Cast(UByte, (*c2fb_temp_105))
            End If
            ' C unused-parameter annotation
        Else
            c2fb_temp_107 = CPtr(sqlite3_uint64 Ptr, @(arg0->revMask))
            c2fb_temp_108 = Cast(sqlite3_uint64, local14->revLoop)
            (*c2fb_temp_107) = c2fb_temp_108
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->nOBSat) <= Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_109 = CPtr(Byte Ptr, @(arg0->nOBSat))
                c2fb_temp_110 = Cast(Byte, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_109) = c2fb_temp_110
                If (-Cast(SQLITE_C_INT, ((local1 > Cast(SQLITE_C_INT, &O0ULL))))) Then
                    local30 = CPtr(SqliteWhereLoop Ptr Ptr, local14->aLoop)[Cast(SQLITE_C_INT, (local1 - Cast(SQLITE_C_INT, 1ULL)))]->wsFlags
                    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local30 And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00001000ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local30 And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000100ULL) Or Cast(SQLITE_C_INT, &H00000004ULL)))))))) <> Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000100ULL) Or Cast(SQLITE_C_INT, &H00000004ULL))))))))))))) Then
                        local31 = Cast(SQLITE_C_INT, &O0ULL)
                        local32 = wherePathSatisfiesOrderBy(arg0, arg0->pOrderBy, local14, Cast(SQLITE_C_INT, &H0800ULL), Cast(SQLITE_C_INT, (local1 - Cast(SQLITE_C_INT, 1ULL))), CPtr(SqliteWhereLoop Ptr Ptr, local14->aLoop)[Cast(SQLITE_C_INT, (local1 - Cast(SQLITE_C_INT, 1ULL)))], CPtr(sqlite3_uint64 Ptr, @(local31)))
                        ' empty C statement
                        ' empty C statement
                        If (-Cast(SQLITE_C_INT, ((local32 = arg0->pOrderBy->nExpr)))) Then
                            c2fb_temp_111 = CPtr(SQLITE_C_UINT Ptr, @(arg0->flags))
                            c2fb_temp_112 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                            c2fb_temp_112 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_112) And Cast(SQLITE_C_UINT, &H1ULL)))
                            (*c2fb_temp_111) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_111)) And Not(Cast(SQLITE_C_UINT, &H4ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_112) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 2)))
                            c2fb_temp_112 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_112) And Cast(SQLITE_C_UINT, &H1ULL)))
                            c2fb_temp_113 = CPtr(sqlite3_uint64 Ptr, @(arg0->revMask))
                            c2fb_temp_114 = Cast(sqlite3_uint64, local31)
                            (*c2fb_temp_113) = c2fb_temp_114
                        End If
                    End If
                End If
            Else
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local1 AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->nOBSat) = Cast(SQLITE_C_INT, 1ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->wctrlFlags) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0001ULL) Or Cast(SQLITE_C_INT, &H0002ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                    c2fb_temp_115 = CPtr(SQLITE_C_UINT Ptr, @(arg0->flags))
                    c2fb_temp_116 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                    c2fb_temp_116 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_116) And Cast(SQLITE_C_UINT, &H1ULL)))
                    (*c2fb_temp_115) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_115)) And Not(Cast(SQLITE_C_UINT, &H4ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_116) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 2)))
                    c2fb_temp_116 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_116) And Cast(SQLITE_C_UINT, &H1ULL)))
                End If
            End If
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->wctrlFlags) And Cast(SQLITE_C_INT, &H0200ULL)))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg0->nOBSat) = arg0->pOrderBy->nExpr)))))))) AndAlso (-Cast(SQLITE_C_INT, ((local1 > Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            local33 = Cast(SQLITE_C_INT, &O0ULL)
            local34 = wherePathSatisfiesOrderBy(arg0, arg0->pOrderBy, local14, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, (local1 - Cast(SQLITE_C_INT, 1ULL))), CPtr(SqliteWhereLoop Ptr Ptr, local14->aLoop)[Cast(SQLITE_C_INT, (local1 - Cast(SQLITE_C_INT, 1ULL)))], CPtr(sqlite3_uint64 Ptr, @(local33)))
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, ((local34 = arg0->pOrderBy->nExpr)))) Then
                c2fb_temp_117 = CPtr(SQLITE_C_UINT Ptr, @(arg0->flags))
                c2fb_temp_118 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                c2fb_temp_118 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_118) And Cast(SQLITE_C_UINT, &H1ULL)))
                (*c2fb_temp_117) = Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (*c2fb_temp_117)) And Not(Cast(SQLITE_C_UINT, &H8ULL))) Or ((Cast(SQLITE_C_UINT, c2fb_temp_118) And Cast(SQLITE_C_UINT, &H1ULL)) Shl 3)))
                c2fb_temp_118 = Cast(SQLITE_C_INT, (Cast(SQLITE_C_UINT, c2fb_temp_118) And Cast(SQLITE_C_UINT, &H1ULL)))
                c2fb_temp_119 = CPtr(sqlite3_uint64 Ptr, @(arg0->revMask))
                c2fb_temp_120 = Cast(sqlite3_uint64, local33)
                (*c2fb_temp_119) = c2fb_temp_120
            End If
        End If
    End If
    c2fb_temp_121 = CPtr(Short Ptr, @(arg0->nRowOut))
    c2fb_temp_122 = Cast(Short, local14->nRow)
    (*c2fb_temp_121) = c2fb_temp_122
    sqlite3DbFreeNN(CPtr(Any Ptr, local2->db), CPtr(Any Ptr, local19))
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Sub whereInterstageHeuristic CDecl Alias "whereInterstageHeuristic" (ByVal arg0 As SqliteWhereInfo Ptr)
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local1 As SqliteWhereLoop Ptr
    Dim local2 As UByte
    Dim local3 As SqliteWhereLoop Ptr
    Dim c2fb_temp_2 As SqliteWhereLoop Ptr
    Dim c2fb_temp_3 As SqliteWhereLoop Ptr
    Dim c2fb_temp_4 As sqlite3_uint64 Ptr
    Dim c2fb_temp_5 As sqlite3_uint64

    ' C automatic storage declaration
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((local0 < Cast(SQLITE_C_INT, arg0->nLevel)))))
        local1 = arg0->a(local0).pWLoop
        If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_0
        End If
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local1->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000400ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            Goto c2fb_flow_0
        End If
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local1->wsFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000001ULL) Or Cast(SQLITE_C_INT, &H00000008ULL))) Or Cast(SQLITE_C_INT, &H00000004ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            local2 = local1->iTab
            ' C automatic storage declaration
            c2fb_temp_2 = CPtr(SqliteWhereLoop Ptr, arg0->pLoops)
            local3 = c2fb_temp_2
            While local3
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local3->iTab) <> Cast(SQLITE_C_INT, local2))))) Then
                    Goto c2fb_flow_3
                End If
                If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local3->wsFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0000000fULL) Or Cast(SQLITE_C_INT, &H00004000ULL)))))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                    Goto c2fb_flow_3
                End If
                c2fb_temp_4 = CPtr(sqlite3_uint64 Ptr, @(local3->prereq))
                c2fb_temp_5 = Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))))
                (*c2fb_temp_4) = c2fb_temp_5
            c2fb_flow_3:
                c2fb_temp_3 = CPtr(SqliteWhereLoop Ptr, local3->pNextLoop)
                local3 = c2fb_temp_3
            Wend
            c2fb_flow_2:
        Else
            Goto c2fb_flow_0
        End If
    c2fb_flow_1:
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    Wend
    c2fb_flow_0:
End Sub

Private Function whereShortCut CDecl Alias "whereShortCut" (ByVal arg0 As SqliteWhereLoopBuilder Ptr) As SQLITE_C_INT
    Dim local0 As SqliteWhereInfo Ptr
    Dim local1 As SqliteSrcItem Ptr
    Dim local2 As SqliteWhereClause Ptr
    Dim local3 As SqliteWhereTerm Ptr
    Dim local4 As SqliteWhereLoop Ptr
    Dim local5 As SQLITE_C_INT
    Dim local6 As SQLITE_C_INT
    Dim local7 As SqliteTable Ptr
    Dim local8 As SqliteIndex Ptr
    Dim local9 As SqliteWhereScan
    Dim c2fb_temp_0 As SqliteWhereInfo Ptr
    Dim c2fb_temp_1 As SqliteSrcItem Ptr
    Dim c2fb_temp_2 As SqliteTable Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SqliteWhereClause Ptr
    Dim c2fb_temp_5 As SqliteWhereLoop Ptr
    Dim c2fb_temp_6 As u32 Ptr
    Dim c2fb_temp_7 As SQLITE_C_UINT
    Dim c2fb_temp_8 As u16 Ptr
    Dim c2fb_temp_9 As UShort
    Dim c2fb_temp_10 As SqliteWhereTerm Ptr
    Dim c2fb_temp_11 As SqliteWhereTerm Ptr
    Dim c2fb_temp_12 As u32 Ptr
    Dim c2fb_temp_13 As SQLITE_C_UINT
    Dim c2fb_temp_14 As SqliteWhereTerm Ptr Ptr
    Dim c2fb_temp_15 As SqliteWhereTerm Ptr
    Dim c2fb_temp_16 As u16 Ptr
    Dim c2fb_temp_17 As UShort
    Dim c2fb_temp_18 As u16 Ptr
    Dim c2fb_temp_19 As UShort
    Dim c2fb_temp_20 As Short Ptr
    Dim c2fb_temp_21 As Short
    Dim c2fb_temp_22 As SqliteIndex Ptr
    Dim c2fb_temp_23 As SqliteIndex Ptr
    Dim local10 As SQLITE_C_INT
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As SQLITE_C_INT
    Dim c2fb_temp_26 As SQLITE_C_INT
    Dim c2fb_temp_27 As SqliteWhereTerm Ptr
    Dim c2fb_temp_28 As SqliteWhereTerm Ptr
    Dim c2fb_temp_29 As SqliteWhereTerm Ptr Ptr
    Dim c2fb_temp_30 As SqliteWhereTerm Ptr
    Dim c2fb_temp_31 As u32 Ptr
    Dim c2fb_temp_32 As SQLITE_C_UINT
    Dim c2fb_temp_33 As u32 Ptr
    Dim c2fb_temp_34 As SQLITE_C_UINT
    Dim c2fb_temp_35 As u16 Ptr
    Dim c2fb_temp_36 As UShort
    Dim c2fb_temp_37 As u16 Ptr
    Dim c2fb_temp_38 As UShort
    Dim c2fb_temp_39 As Any Ptr Ptr
    Dim c2fb_temp_40 As SqliteIndex Ptr
    Dim c2fb_temp_41 As Short Ptr
    Dim c2fb_temp_42 As Short
    Dim c2fb_temp_43 As Short Ptr
    Dim c2fb_temp_44 As Short
    Dim c2fb_temp_45 As SqliteWhereLoop Ptr Ptr
    Dim c2fb_temp_46 As SqliteWhereLoop Ptr
    Dim c2fb_temp_47 As sqlite3_uint64 Ptr
    Dim c2fb_temp_48 As sqlite3_uint64
    Dim c2fb_temp_49 As SQLITE_C_INT Ptr
    Dim c2fb_temp_50 As SQLITE_C_INT
    Dim c2fb_temp_51 As Short Ptr
    Dim c2fb_temp_52 As Short
    Dim c2fb_temp_53 As Byte Ptr
    Dim c2fb_temp_54 As Byte
    Dim c2fb_temp_55 As u8 Ptr
    Dim c2fb_temp_56 As UByte
    Dim c2fb_temp_57 As u32 Ptr
    Dim c2fb_temp_58 As SQLITE_C_UINT

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
    c2fb_temp_0 = CPtr(SqliteWhereInfo Ptr, arg0->pWInfo)
    local0 = c2fb_temp_0
    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->wctrlFlags) And Cast(SQLITE_C_INT, &H0020ULL))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    ' C unused-parameter annotation
    c2fb_temp_1 = CPtr(SqliteSrcItem Ptr, (@local0->pTabList->a(0)))
    local1 = c2fb_temp_1
    c2fb_temp_2 = local1->pSTab
    local7 = c2fb_temp_2
    If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local7)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 1) And Cast(SQLITE_C_UINT, &H1ULL))) OrElse Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 0) And Cast(SQLITE_C_UINT, &H1ULL))))))) Then
        ' empty C statement
        ' empty C statement
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_3 = Cast(SQLITE_C_INT, local1->iCursor)
    local5 = c2fb_temp_3
    c2fb_temp_4 = CPtr(SqliteWhereClause Ptr, @(local0->sWC))
    local2 = c2fb_temp_4
    c2fb_temp_5 = arg0->pNew
    local4 = c2fb_temp_5
    c2fb_temp_6 = CPtr(u32 Ptr, @(local4->wsFlags))
    c2fb_temp_7 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_6) = Cast(u32, c2fb_temp_7)
    c2fb_temp_7 = Cast(SQLITE_C_UINT, (*c2fb_temp_6))
    c2fb_temp_8 = CPtr(u16 Ptr, @(local4->nSkip))
    c2fb_temp_9 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_8) = Cast(u16, c2fb_temp_9)
    c2fb_temp_9 = Cast(UShort, (*c2fb_temp_8))
    c2fb_temp_10 = CPtr(SqliteWhereTerm Ptr, whereScanInit(CPtr(SqliteWhereScan Ptr, @(local9)), local2, local5, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0080ULL))), Cast(SQLITE_C_INT, &O0ULL)))
    local3 = c2fb_temp_10
    While (-Cast(SQLITE_C_INT, ((local3 AndAlso local3->prereqRight))))
        c2fb_temp_11 = CPtr(SqliteWhereTerm Ptr, whereScanNext(CPtr(SqliteWhereScan Ptr, @(local9))))
        local3 = c2fb_temp_11
    c2fb_flow_1:
    Wend
    c2fb_flow_0:
    If local3 Then
        ' empty C statement
        c2fb_temp_12 = CPtr(u32 Ptr, @(local4->wsFlags))
        c2fb_temp_13 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000001ULL) Or Cast(SQLITE_C_INT, &H00000100ULL))) Or Cast(SQLITE_C_INT, &H00001000ULL))))
        (*c2fb_temp_12) = Cast(u32, c2fb_temp_13)
        c2fb_temp_13 = Cast(SQLITE_C_UINT, (*c2fb_temp_12))
        c2fb_temp_14 = CPtr(SqliteWhereTerm Ptr Ptr, @(local4->aLTerm[Cast(SQLITE_C_INT, &O0ULL)]))
        c2fb_temp_15 = local3
        (*c2fb_temp_14) = c2fb_temp_15
        c2fb_temp_16 = CPtr(u16 Ptr, @(local4->nLTerm))
        c2fb_temp_17 = Cast(UShort, Cast(SQLITE_C_INT, 1ULL))
        (*c2fb_temp_16) = Cast(u16, c2fb_temp_17)
        c2fb_temp_17 = Cast(UShort, (*c2fb_temp_16))
        c2fb_temp_18 = CPtr(u16 Ptr, @(local4->u.btree.nEq))
        c2fb_temp_19 = Cast(UShort, Cast(SQLITE_C_INT, 1ULL))
        (*c2fb_temp_18) = Cast(u16, c2fb_temp_19)
        c2fb_temp_19 = Cast(UShort, (*c2fb_temp_18))
        c2fb_temp_20 = CPtr(Short Ptr, @(local4->rRun))
        c2fb_temp_21 = Cast(Short, Cast(SQLITE_C_INT, 33ULL))
        (*c2fb_temp_20) = c2fb_temp_21
    Else
        c2fb_temp_22 = CPtr(SqliteIndex Ptr, local7->pIndex)
        local8 = c2fb_temp_22
        While local8
            ' C automatic storage declaration
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local8)->onError) <> Cast(SQLITE_C_INT, &O0ULL)))))) = 0))) OrElse (-Cast(SQLITE_C_INT, ((CPtr(SqliteExpr Ptr, local8->pPartIdxWhere) <> Cast(SQLITE_C_INT, &O0ULL))))))))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local8->nKeyCol) > (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, (Cast(SQLITE_C_INT, 3ULL) * SizeOf(SqliteWhereTerm Ptr)))) \ Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereTerm Ptr)))))))))))))))) Then
                Goto c2fb_flow_3
            End If
            c2fb_temp_24 = Cast(SQLITE_C_INT, IIf(Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local8->flags) Shr 3) And Cast(SQLITE_C_UINT, &H1ULL))), (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0002ULL) Or Cast(SQLITE_C_INT, &H0080ULL)))), Cast(SQLITE_C_INT, &H0002ULL)))
            local10 = c2fb_temp_24
            c2fb_temp_25 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
            local6 = c2fb_temp_25
            While (-Cast(SQLITE_C_INT, ((local6 < Cast(SQLITE_C_INT, local8->nKeyCol)))))
                c2fb_temp_27 = CPtr(SqliteWhereTerm Ptr, whereScanInit(CPtr(SqliteWhereScan Ptr, @(local9)), local2, local5, local6, local10, local8))
                local3 = c2fb_temp_27
                While (-Cast(SQLITE_C_INT, ((local3 AndAlso local3->prereqRight))))
                    c2fb_temp_28 = CPtr(SqliteWhereTerm Ptr, whereScanNext(CPtr(SqliteWhereScan Ptr, @(local9))))
                    local3 = c2fb_temp_28
                c2fb_flow_7:
                Wend
                c2fb_flow_6:
                If (-Cast(SQLITE_C_INT, ((local3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    Goto c2fb_flow_4
                End If
                ' empty C statement
                c2fb_temp_29 = CPtr(SqliteWhereTerm Ptr Ptr, @(local4->aLTerm[local6]))
                c2fb_temp_30 = local3
                (*c2fb_temp_29) = c2fb_temp_30
            c2fb_flow_5:
                c2fb_temp_26 = local6
                local6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_26 + 1)))
            Wend
            c2fb_flow_4:
            If (-Cast(SQLITE_C_INT, ((local6 <> Cast(SQLITE_C_INT, local8->nKeyCol))))) Then
                Goto c2fb_flow_3
            End If
            c2fb_temp_31 = CPtr(u32 Ptr, @(local4->wsFlags))
            c2fb_temp_32 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000001ULL) Or Cast(SQLITE_C_INT, &H00001000ULL))) Or Cast(SQLITE_C_INT, &H00000200ULL))))
            (*c2fb_temp_31) = Cast(u32, c2fb_temp_32)
            c2fb_temp_32 = Cast(SQLITE_C_UINT, (*c2fb_temp_31))
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local8->flags) Shr 5) And Cast(SQLITE_C_UINT, &H1ULL))) OrElse (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local1->colUsed And local8->colNotIdxed))) = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
                c2fb_temp_33 = CPtr(u32 Ptr, @(local4->wsFlags))
                c2fb_temp_34 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_33)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000040ULL)))))
                (*c2fb_temp_33) = Cast(u32, c2fb_temp_34)
                c2fb_temp_34 = Cast(SQLITE_C_UINT, (*c2fb_temp_33))
            End If
            c2fb_temp_35 = CPtr(u16 Ptr, @(local4->nLTerm))
            c2fb_temp_36 = Cast(UShort, local6)
            (*c2fb_temp_35) = Cast(u16, c2fb_temp_36)
            c2fb_temp_36 = Cast(UShort, (*c2fb_temp_35))
            c2fb_temp_37 = CPtr(u16 Ptr, @(local4->u.btree.nEq))
            c2fb_temp_38 = Cast(UShort, local6)
            (*c2fb_temp_37) = Cast(u16, c2fb_temp_38)
            c2fb_temp_38 = Cast(UShort, (*c2fb_temp_37))
            c2fb_temp_39 = CPtr(Any Ptr Ptr, @(local4->u.btree.pIndex))
            c2fb_temp_40 = local8
            (*c2fb_temp_39) = CPtr(Any Ptr, c2fb_temp_40)
            c2fb_temp_40 = CPtr(SqliteIndex Ptr, (*c2fb_temp_39))
            c2fb_temp_41 = CPtr(Short Ptr, @(local4->rRun))
            c2fb_temp_42 = Cast(Short, Cast(SQLITE_C_INT, 39ULL))
            (*c2fb_temp_41) = c2fb_temp_42
            Goto c2fb_flow_2
        c2fb_flow_3:
            c2fb_temp_23 = local8->pNext
            local8 = c2fb_temp_23
        Wend
        c2fb_flow_2:
    End If
    If local4->wsFlags Then
        c2fb_temp_43 = CPtr(Short Ptr, @(local4->nOut))
        c2fb_temp_44 = Cast(Short, Cast(Short, Cast(SQLITE_C_INT, 1ULL)))
        (*c2fb_temp_43) = c2fb_temp_44
        c2fb_temp_45 = CPtr(SqliteWhereLoop Ptr Ptr, @(local0->a(Cast(SQLITE_C_INT, &O0ULL)).pWLoop))
        c2fb_temp_46 = local4
        (*c2fb_temp_45) = c2fb_temp_46
        ' C unused-parameter annotation
        c2fb_temp_47 = CPtr(sqlite3_uint64 Ptr, @(local4->maskSelf))
        c2fb_temp_48 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))
        (*c2fb_temp_47) = c2fb_temp_48
        c2fb_temp_49 = CPtr(SQLITE_C_INT Ptr, @(local0->a(Cast(SQLITE_C_INT, &O0ULL)).iTabCur))
        c2fb_temp_50 = Cast(SQLITE_C_INT, local5)
        (*c2fb_temp_49) = c2fb_temp_50
        c2fb_temp_51 = CPtr(Short Ptr, @(local0->nRowOut))
        c2fb_temp_52 = Cast(Short, Cast(SQLITE_C_INT, 1ULL))
        (*c2fb_temp_51) = c2fb_temp_52
        If local0->pOrderBy Then
            c2fb_temp_53 = CPtr(Byte Ptr, @(local0->nOBSat))
            c2fb_temp_54 = Cast(Byte, local0->pOrderBy->nExpr)
            (*c2fb_temp_53) = c2fb_temp_54
        End If
        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local0->wctrlFlags) And Cast(SQLITE_C_INT, &H0100ULL))) Then
            c2fb_temp_55 = CPtr(u8 Ptr, @(local0->eDistinct))
            c2fb_temp_56 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
            (*c2fb_temp_55) = Cast(u8, c2fb_temp_56)
            c2fb_temp_56 = Cast(UByte, (*c2fb_temp_55))
        End If
        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local9.iEquiv) > Cast(SQLITE_C_INT, 1ULL))))) Then
            c2fb_temp_57 = CPtr(u32 Ptr, @(local4->wsFlags))
            c2fb_temp_58 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_57)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00200000ULL)))))
            (*c2fb_temp_57) = Cast(u32, c2fb_temp_58)
            c2fb_temp_58 = Cast(SQLITE_C_UINT, (*c2fb_temp_57))
        End If
        Return Cast(SQLITE_C_INT, 1ULL)
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function exprNodeIsDeterministic CDecl Alias "exprNodeIsDeterministic" (ByVal arg0 As SqliteWalker Ptr, ByVal arg1 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim c2fb_temp_0 As UShort Ptr
    Dim c2fb_temp_1 As UShort

    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, arg1->op) = Cast(SQLITE_C_INT, 172ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H100000ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        c2fb_temp_0 = CPtr(UShort Ptr, @(arg0->eCode))
        c2fb_temp_1 = Cast(UShort, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_0) = c2fb_temp_1
        Return Cast(SQLITE_C_INT, 2ULL)
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

Private Function exprIsDeterministic CDecl Alias "exprIsDeterministic" (ByVal arg0 As SqliteExpr Ptr) As SQLITE_C_INT
    Dim local0 As SqliteWalker
    Dim c2fb_temp_0 As Any Ptr
    Dim c2fb_temp_1 As UShort Ptr
    Dim c2fb_temp_2 As UShort
    Dim c2fb_temp_3 As SqliteWalkerExprCallback Ptr
    Dim c2fb_temp_4 As c2fb_callback_85
    Dim c2fb_temp_5 As SqliteWalkerSelectCallback Ptr
    Dim c2fb_temp_6 As c2fb_callback_85

    ' C automatic storage declaration
    c2fb_temp_0 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local0))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteWalker))))
    c2fb_temp_1 = CPtr(UShort Ptr, @(local0.eCode))
    c2fb_temp_2 = Cast(UShort, Cast(SQLITE_C_INT, 1ULL))
    (*c2fb_temp_1) = c2fb_temp_2
    c2fb_temp_3 = CPtr(SqliteWalkerExprCallback Ptr, @(local0.xExprCallback))
    c2fb_temp_4 = CPtr(c2fb_callback_85, ProcPtr(exprNodeIsDeterministic))
    (*c2fb_temp_3) = Cast(SqliteWalkerExprCallback, c2fb_temp_4)
    c2fb_temp_4 = CPtr(c2fb_callback_85, (*c2fb_temp_3))
    c2fb_temp_5 = CPtr(SqliteWalkerSelectCallback Ptr, @(local0.xSelectCallback))
    c2fb_temp_6 = CPtr(c2fb_callback_85, ProcPtr(sqlite3SelectWalkFail))
    (*c2fb_temp_5) = Cast(SqliteWalkerSelectCallback, c2fb_temp_6)
    c2fb_temp_6 = CPtr(c2fb_callback_85, (*c2fb_temp_5))
    sqlite3WalkExpr(CPtr(Any Ptr, CPtr(SqliteWalker Ptr, @(local0))), CPtr(Any Ptr, arg0))
    Return local0.eCode
End Function

Private Function whereOmitNoopJoin CDecl Alias "whereOmitNoopJoin" (ByVal arg0 As SqliteWhereInfo Ptr, ByVal arg1 As sqlite3_uint64) As sqlite3_uint64
    Dim local0 As SQLITE_C_INT
    Dim local1 As sqlite3_uint64
    Dim local2 As SQLITE_C_INT
    Dim c2fb_temp_0 As sqlite3_uint64
    Dim c2fb_temp_1 As sqlite3_uint64
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_INT
    Dim c2fb_temp_4 As SQLITE_C_INT
    Dim local3 As SqliteWhereTerm Ptr
    Dim local4 As SqliteWhereTerm Ptr
    Dim local5 As SqliteSrcItem Ptr
    Dim local6 As SqliteWhereLoop Ptr
    Dim local7 As sqlite3_uint64
    Dim c2fb_temp_5 As SqliteWhereLoop Ptr
    Dim c2fb_temp_6 As SqliteSrcItem Ptr
    Dim c2fb_temp_7 As SqliteWhereTerm Ptr
    Dim c2fb_temp_8 As SqliteWhereTerm Ptr
    Dim c2fb_temp_9 As SqliteWhereTerm Ptr
    Dim c2fb_temp_10 As sqlite3_uint64
    Dim c2fb_temp_11 As sqlite3_uint64 Ptr
    Dim c2fb_temp_12 As sqlite3_uint64
    Dim c2fb_temp_13 As sqlite3_uint64
    Dim c2fb_temp_14 As SqliteWhereTerm Ptr
    Dim c2fb_temp_15 As SqliteWhereTerm Ptr
    Dim c2fb_temp_16 As u16 Ptr
    Dim c2fb_temp_17 As UShort
    Dim c2fb_temp_18 As sqlite3_uint64 Ptr
    Dim c2fb_temp_19 As sqlite3_uint64
    Dim local8 As SQLITE_C_INT
    Dim c2fb_temp_20 As Any Ptr
    Dim c2fb_temp_21 As u8 Ptr
    Dim c2fb_temp_22 As UByte

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(sqlite3_uint64, sqlite3WhereExprListUsage(CPtr(SqliteWhereMaskSet Ptr, @(arg0->sMaskSet)), arg0->pResultSet))
    local1 = c2fb_temp_0
    If arg0->pOrderBy Then
        c2fb_temp_1 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local1 Or sqlite3WhereExprListUsage(CPtr(SqliteWhereMaskSet Ptr, @(arg0->sMaskSet)), arg0->pOrderBy))))
        local1 = c2fb_temp_1
    End If
    c2fb_temp_2 = Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->pTabList->a(Cast(SQLITE_C_INT, &O0ULL)).fg.jointype) And Cast(SQLITE_C_INT, &H40ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))))
    local2 = c2fb_temp_2
    c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->nLevel) - Cast(SQLITE_C_INT, 1ULL))))
    local0 = c2fb_temp_3
    While (-Cast(SQLITE_C_INT, ((local0 >= Cast(SQLITE_C_INT, 1ULL)))))
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        c2fb_temp_5 = arg0->a(local0).pWLoop
        local6 = c2fb_temp_5
        c2fb_temp_6 = CPtr(SqliteSrcItem Ptr, @(arg0->pTabList->a(local6->iTab)))
        local5 = c2fb_temp_6
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local5->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H10ULL))))))) <> Cast(SQLITE_C_INT, &H08ULL))))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->wctrlFlags) And Cast(SQLITE_C_INT, &H0100ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local6->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00001000ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
            Goto c2fb_flow_1
        End If
        If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local1 And local6->maskSelf))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            Goto c2fb_flow_1
        End If
        c2fb_temp_7 = CPtr(SqliteWhereTerm Ptr, (arg0->sWC.a + arg0->sWC.nTerm))
        local4 = c2fb_temp_7
        c2fb_temp_8 = arg0->sWC.a
        local3 = c2fb_temp_8
        While (-Cast(SQLITE_C_INT, ((local3 < local4))))
            If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local3->prereqAll And local6->maskSelf))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local3->pExpr)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000001ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))) OrElse (-Cast(SQLITE_C_INT, ((local3->pExpr->w.iJoin <> local5->iCursor)))))))) Then
                    Goto c2fb_flow_2
                End If
            End If
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local2 AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local3->pExpr)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000002ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) AndAlso ((-Cast(SQLITE_C_INT, ((local3->pExpr->w.iJoin = local5->iCursor))))))))) Then
                Goto c2fb_flow_2
            End If
        c2fb_flow_3:
            c2fb_temp_9 = local3
            local3 = (c2fb_temp_9 + 1)
        Wend
        c2fb_flow_2:
        If (-Cast(SQLITE_C_INT, ((local3 < local4)))) Then
            Goto c2fb_flow_1
        End If
        ' empty C statement
        c2fb_temp_10 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local0)))) - Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL)))))
        local7 = c2fb_temp_10
        ' empty C statement
        c2fb_temp_11 = CPtr(sqlite3_uint64 Ptr, @(arg0->revMask))
        c2fb_temp_12 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, (local7 And arg0->revMask))) Or (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, (arg0->revMask Shr Cast(SQLITE_C_INT, 1ULL)))) And Cast(sqlite3_uint64, (Not local7))))))))
        (*c2fb_temp_11) = c2fb_temp_12
        c2fb_temp_13 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (arg1 And Cast(sqlite3_uint64, (Not local6->maskSelf)))))
        arg1 = c2fb_temp_13
        c2fb_temp_14 = arg0->sWC.a
        local3 = c2fb_temp_14
        While (-Cast(SQLITE_C_INT, ((local3 < local4))))
            If (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local3->prereqAll And local6->maskSelf))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                c2fb_temp_16 = CPtr(u16 Ptr, @(local3->wtFlags))
                c2fb_temp_17 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_16))) Or Cast(SQLITE_C_INT, &H0004ULL))))
                (*c2fb_temp_16) = Cast(u16, c2fb_temp_17)
                c2fb_temp_17 = Cast(UShort, (*c2fb_temp_16))
                c2fb_temp_18 = CPtr(sqlite3_uint64 Ptr, @(local3->prereqAll))
                c2fb_temp_19 = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_18) = c2fb_temp_19
            End If
        c2fb_flow_5:
            c2fb_temp_15 = local3
            local3 = (c2fb_temp_15 + 1)
        Wend
        c2fb_flow_4:
        If (-Cast(SQLITE_C_INT, ((local0 <> Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->nLevel) - Cast(SQLITE_C_INT, 1ULL))))))) Then
            local8 = Cast(sqlite3_uint64, (Cast(sqlite3_uint64, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg0->nLevel) - Cast(SQLITE_C_INT, 1ULL))) - local0)))) * Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereLevel)))))
            c2fb_temp_20 = CPtr(Any Ptr, c2fb_crt_memmove(CPtr(Any Ptr, CPtr(SqliteWhereLevel Ptr, @(arg0->a(local0)))), CPtr(Const Any Ptr, CPtr(SqliteWhereLevel Ptr, @(arg0->a(Cast(SQLITE_C_INT, (local0 + Cast(SQLITE_C_INT, 1ULL))))))), local8))
        End If
        c2fb_temp_21 = CPtr(u8 Ptr, @(arg0->nLevel))
        c2fb_temp_22 = Cast(UByte, (*c2fb_temp_21))
        (*c2fb_temp_21) = Cast(UByte, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, c2fb_temp_22) - 1)))
        ' C unused-parameter annotation
    c2fb_flow_1:
        c2fb_temp_4 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_4 - 1)))
    Wend
    c2fb_flow_0:
    Return arg1
End Function

Private Sub whereCheckIfBloomFilterIsUseful CDecl Alias "whereCheckIfBloomFilterIsUseful" (ByVal arg0 As Const SqliteWhereInfo Ptr)
    Dim local0 As SQLITE_C_INT
    Dim local1 As Short
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local2 As SqliteWhereLoop Ptr
    Dim local3 As SQLITE_C_UINT
    Dim local4 As SqliteSrcItem Ptr
    Dim local5 As SqliteTable Ptr
    Dim c2fb_temp_2 As u32 Ptr
    Dim c2fb_temp_3 As SQLITE_C_UINT
    Dim c2fb_temp_4 As u32 Ptr
    Dim c2fb_temp_5 As SQLITE_C_UINT
    Dim c2fb_temp_6 As u32 Ptr
    Dim c2fb_temp_7 As SQLITE_C_UINT
    Dim c2fb_temp_8 As Short

    ' C automatic storage declaration
    local1 = Cast(SQLITE_C_INT, &O0ULL)
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((local0 < Cast(SQLITE_C_INT, arg0->nLevel)))))
        local2 = arg0->a(local0).pWLoop
        local3 = (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00800000ULL) Or Cast(SQLITE_C_INT, &H00000001ULL))))
        local4 = CPtr(SqliteSrcItem Ptr, @(arg0->pTabList->a(local2->iTab)))
        local5 = local4->pSTab
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local5->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000010ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            Goto c2fb_flow_0
        End If
        c2fb_temp_2 = CPtr(u32 Ptr, @(local5->tabFlags))
        c2fb_temp_3 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_2)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000100ULL)))))
        (*c2fb_temp_2) = Cast(u32, c2fb_temp_3)
        c2fb_temp_3 = Cast(SQLITE_C_UINT, (*c2fb_temp_2))
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local0 >= Cast(SQLITE_C_INT, 1ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local2->wsFlags And local3))) = local3)))))))) AndAlso sqlite3WhereLoopBloomable(CPtr(Const SqliteWhereLoop Ptr, local2)))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1) > Cast(SQLITE_C_INT, local5->nRowLogEst))))))))) Then
            ' empty C statement
            c2fb_temp_4 = CPtr(u32 Ptr, @(local2->wsFlags))
            c2fb_temp_5 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_4)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00400000ULL)))))
            (*c2fb_temp_4) = Cast(u32, c2fb_temp_5)
            c2fb_temp_5 = Cast(SQLITE_C_UINT, (*c2fb_temp_4))
            c2fb_temp_6 = CPtr(u32 Ptr, @(local2->wsFlags))
            c2fb_temp_7 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_6)) And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, &H00000040ULL)))))))
            (*c2fb_temp_6) = Cast(u32, c2fb_temp_7)
            c2fb_temp_7 = Cast(SQLITE_C_UINT, (*c2fb_temp_6))
            ' empty C statement
        End If
        c2fb_temp_8 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local1) + Cast(SQLITE_C_INT, local2->nOut))))
        local1 = c2fb_temp_8
    c2fb_flow_1:
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    Wend
    c2fb_flow_0:
End Sub

Private Sub whereAddIndexedExpr CDecl Alias "whereAddIndexedExpr" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteIndex Ptr, ByVal arg2 As SQLITE_C_INT, ByVal arg3 As SqliteSrcItem Ptr)
    Dim local0 As SQLITE_C_INT
    Dim local1 As SqliteIndexedExpr Ptr
    Dim local2 As SqliteTable Ptr
    Dim c2fb_temp_0 As SqliteTable Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim local3 As SqliteExpr Ptr
    Dim local4 As SQLITE_C_INT
    Dim c2fb_temp_3 As SqliteExpr Ptr
    Dim c2fb_temp_4 As SqliteExpr Ptr
    Dim c2fb_temp_5 As SqliteIndexedExpr Ptr
    Dim c2fb_temp_6 As SqliteIndexedExpr Ptr Ptr
    Dim c2fb_temp_7 As SqliteIndexedExpr Ptr
    Dim c2fb_temp_8 As Any Ptr Ptr
    Dim c2fb_temp_9 As SqliteExpr Ptr
    Dim c2fb_temp_10 As SQLITE_C_INT Ptr
    Dim c2fb_temp_11 As SQLITE_C_INT
    Dim c2fb_temp_12 As SQLITE_C_INT Ptr
    Dim c2fb_temp_13 As SQLITE_C_INT
    Dim c2fb_temp_14 As SQLITE_C_INT Ptr
    Dim c2fb_temp_15 As SQLITE_C_INT
    Dim c2fb_temp_16 As u8 Ptr
    Dim c2fb_temp_17 As UByte
    Dim c2fb_temp_18 As u8 Ptr
    Dim c2fb_temp_19 As UByte
    Dim c2fb_temp_20 As SqliteIndexedExpr Ptr Ptr
    Dim c2fb_temp_21 As SqliteIndexedExpr Ptr
    Dim local5 As Any Ptr
    Dim c2fb_temp_22 As Any Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    c2fb_temp_0 = arg1->pTable
    local2 = c2fb_temp_0
    c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_1
    While (-Cast(SQLITE_C_INT, ((local0 < Cast(SQLITE_C_INT, arg1->nColumn)))))
        ' C automatic storage declaration
        local4 = arg1->aiColumn[local0]
        If (-Cast(SQLITE_C_INT, ((local4 = (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 2ULL)))))))) Then
            c2fb_temp_3 = CPtr(SqliteExprList Ptr, arg1->aColExpr)->a(local0).pExpr
            local3 = c2fb_temp_3
        Else
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local4 >= Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local2->aCol[local4].colFlags) And Cast(SQLITE_C_INT, &H0020ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                c2fb_temp_4 = CPtr(SqliteExpr Ptr, sqlite3ColumnExpr(CPtr(Any Ptr, local2), CPtr(Any Ptr, CPtr(SqliteColumn Ptr, @(local2->aCol[local4])))))
                local3 = c2fb_temp_4
            Else
                Goto c2fb_flow_1
            End If
        End If
        If sqlite3ExprIsConstant(Cast(SQLITE_C_INT, &O0ULL), CPtr(Any Ptr, local3)) Then
            Goto c2fb_flow_1
        End If
        c2fb_temp_5 = CPtr(SqliteIndexedExpr Ptr, CPtr(Any Ptr, sqlite3DbMallocRaw(CPtr(Any Ptr, arg0->db), Cast(SQLITE_SIZE_T, SizeOf(SqliteIndexedExpr)))))
        local1 = c2fb_temp_5
        If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
            Goto c2fb_flow_0
        End If
        c2fb_temp_6 = CPtr(SqliteIndexedExpr Ptr Ptr, @(local1->pIENext))
        c2fb_temp_7 = arg0->pIdxEpr
        (*c2fb_temp_6) = c2fb_temp_7
        c2fb_temp_8 = CPtr(Any Ptr Ptr, @(local1->pExpr))
        c2fb_temp_9 = CPtr(SqliteExpr Ptr, sqlite3ExprDup(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, local3), Cast(SQLITE_C_INT, &O0ULL)))
        (*c2fb_temp_8) = CPtr(Any Ptr, c2fb_temp_9)
        c2fb_temp_9 = CPtr(SqliteExpr Ptr, (*c2fb_temp_8))
        c2fb_temp_10 = CPtr(SQLITE_C_INT Ptr, @(local1->iDataCur))
        c2fb_temp_11 = Cast(SQLITE_C_INT, arg3->iCursor)
        (*c2fb_temp_10) = c2fb_temp_11
        c2fb_temp_12 = CPtr(SQLITE_C_INT Ptr, @(local1->iIdxCur))
        c2fb_temp_13 = Cast(SQLITE_C_INT, arg2)
        (*c2fb_temp_12) = c2fb_temp_13
        c2fb_temp_14 = CPtr(SQLITE_C_INT Ptr, @(local1->iIdxCol))
        c2fb_temp_15 = Cast(SQLITE_C_INT, local0)
        (*c2fb_temp_14) = c2fb_temp_15
        c2fb_temp_16 = CPtr(u8 Ptr, @(local1->bMaybeNullRow))
        c2fb_temp_17 = Cast(UByte, (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg3->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H08ULL) Or Cast(SQLITE_C_INT, &H40ULL))) Or Cast(SQLITE_C_INT, &H10ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))))
        (*c2fb_temp_16) = Cast(u8, c2fb_temp_17)
        c2fb_temp_17 = Cast(UByte, (*c2fb_temp_16))
        If CPtr(Const ZString Ptr, sqlite3IndexAffinityStr(CPtr(Any Ptr, arg0->db), CPtr(Any Ptr, arg1))) Then
            c2fb_temp_18 = CPtr(u8 Ptr, @(local1->aff))
            c2fb_temp_19 = Cast(UByte, CPtr(Byte Ptr, arg1->zColAff)[local0])
            (*c2fb_temp_18) = Cast(u8, c2fb_temp_19)
            c2fb_temp_19 = Cast(UByte, (*c2fb_temp_18))
        End If
        c2fb_temp_20 = CPtr(SqliteIndexedExpr Ptr Ptr, @(arg0->pIdxEpr))
        c2fb_temp_21 = local1
        (*c2fb_temp_20) = c2fb_temp_21
        If (-Cast(SQLITE_C_INT, ((local1->pIENext = Cast(SQLITE_C_INT, &O0ULL))))) Then
            local5 = CPtr(Any Ptr, CPtr(SqliteIndexedExpr Ptr Ptr, @(arg0->pIdxEpr)))
            c2fb_temp_22 = CPtr(Any Ptr, sqlite3ParserAddCleanup(CPtr(Any Ptr, arg0), ProcPtr(whereIndexedExprCleanup), local5))
        End If
    c2fb_flow_1:
        c2fb_temp_2 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_2 + 1)))
    Wend
    c2fb_flow_0:
End Sub

Private Sub whereReverseScanOrder CDecl Alias "whereReverseScanOrder" (ByVal arg0 As SqliteWhereInfo Ptr)
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim local1 As SqliteSrcItem Ptr
    Dim c2fb_temp_2 As sqlite3_uint64 Ptr
    Dim c2fb_temp_3 As sqlite3_uint64

    ' C automatic storage declaration
    c2fb_temp_0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local0 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((local0 < arg0->pTabList->nSrc))))
        local1 = CPtr(SqliteSrcItem Ptr, @(arg0->pTabList->a(local0)))
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 9) And Cast(SQLITE_C_UINT, &H1ULL))) = 0))) OrElse (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local1->u2.pCteUse->eM10d) <> Cast(SQLITE_C_INT, &O0ULL))))))))) OrElse ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local1->fg.flags) Shr 2) And Cast(SQLITE_C_UINT, &H1ULL))) = Cast(SQLITE_C_INT, &O0ULL)))))))))) OrElse (-Cast(SQLITE_C_INT, ((local1->u4.pSubq->pSelect->pOrderBy = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            c2fb_temp_2 = CPtr(sqlite3_uint64 Ptr, @(arg0->revMask))
            c2fb_temp_3 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, ((*c2fb_temp_2) Or (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 1ULL))) Shl (local0)))))))
            (*c2fb_temp_2) = c2fb_temp_3
        End If
    c2fb_flow_1:
        c2fb_temp_1 = local0
        local0 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_1 + 1)))
    Wend
    c2fb_flow_0:
End Sub

Function sqlite3WhereBegin CDecl Alias "sqlite3WhereBegin" (ByVal arg0 As SqliteParseContext Ptr, ByVal arg1 As SqliteSrcList Ptr, ByVal arg2 As SqliteExpr Ptr, ByVal arg3 As SqliteExprList Ptr, ByVal arg4 As SqliteExprList Ptr, ByVal arg5 As SqliteSelect Ptr, ByVal arg6 As UShort, ByVal arg7 As SQLITE_C_INT) As SqliteWhereInfo Ptr
    Dim local0 As SQLITE_C_INT
    Dim local1 As SQLITE_C_INT
    Dim local2 As SqliteWhereInfo Ptr
    Dim local3 As SqliteVdbe Ptr
    Dim local4 As sqlite3_uint64
    Dim local5 As SqliteWhereLoopBuilder
    Dim local6 As SqliteWhereMaskSet Ptr
    Dim local7 As SqliteWhereLevel Ptr
    Dim local8 As SqliteWhereLoop Ptr
    Dim local9 As SQLITE_C_INT
    Dim local10 As sqlite3 Ptr
    Dim local11 As SQLITE_C_INT
    Dim local12 As UByte
    Dim c2fb_temp_0 As sqlite3 Ptr
    Dim c2fb_temp_1 As Any Ptr
    Dim c2fb_temp_2 As SqliteExprList Ptr
    Dim c2fb_temp_3 As UShort
    Dim c2fb_temp_4 As UShort
    Dim c2fb_temp_5 As SQLITE_C_INT
    Dim c2fb_temp_6 As SQLITE_C_INT
    Dim c2fb_temp_7 As SqliteWhereInfo Ptr
    Dim c2fb_temp_8 As SqliteWhereInfo Ptr
    Dim c2fb_temp_9 As SqliteParseContext Ptr Ptr
    Dim c2fb_temp_10 As SqliteParseContext Ptr
    Dim c2fb_temp_11 As SqliteSrcList Ptr Ptr
    Dim c2fb_temp_12 As SqliteSrcList Ptr
    Dim c2fb_temp_13 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_14 As SqliteExprList Ptr
    Dim c2fb_temp_15 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_16 As SqliteExprList Ptr
    Dim c2fb_temp_17 As SQLITE_C_INT Ptr
    Dim c2fb_temp_18 As SQLITE_C_INT
    Dim c2fb_temp_19 As SQLITE_C_INT Ptr
    Dim c2fb_temp_20 As SQLITE_C_INT
    Dim c2fb_temp_21 As u8 Ptr
    Dim c2fb_temp_22 As UByte
    Dim c2fb_temp_23 As SQLITE_C_INT Ptr
    Dim c2fb_temp_24 As SQLITE_C_INT
    Dim c2fb_temp_25 As SQLITE_C_INT Ptr
    Dim c2fb_temp_26 As SQLITE_C_INT
    Dim c2fb_temp_27 As u16 Ptr
    Dim c2fb_temp_28 As UShort
    Dim c2fb_temp_29 As Short Ptr
    Dim c2fb_temp_30 As Short
    Dim c2fb_temp_31 As SQLITE_C_INT Ptr
    Dim c2fb_temp_32 As SQLITE_C_INT
    Dim c2fb_temp_33 As SqliteSelect Ptr Ptr
    Dim c2fb_temp_34 As SqliteSelect Ptr
    Dim c2fb_temp_35 As Any Ptr
    Dim c2fb_temp_36 As Any Ptr
    Dim c2fb_temp_37 As SqliteWhereMaskSet Ptr
    Dim c2fb_temp_38 As SQLITE_C_INT Ptr
    Dim c2fb_temp_39 As SQLITE_C_INT
    Dim c2fb_temp_40 As SQLITE_C_INT Ptr
    Dim c2fb_temp_41 As SQLITE_C_INT
    Dim c2fb_temp_42 As Any Ptr Ptr
    Dim c2fb_temp_43 As SqliteWhereInfo Ptr
    Dim c2fb_temp_44 As Any Ptr Ptr
    Dim c2fb_temp_45 As SqliteWhereClause Ptr
    Dim c2fb_temp_46 As SqliteWhereLoop Ptr Ptr
    Dim c2fb_temp_47 As SqliteWhereLoop Ptr
    Dim c2fb_temp_48 As Byte Ptr
    Dim c2fb_temp_49 As Byte
    Dim c2fb_temp_50 As u8 Ptr
    Dim c2fb_temp_51 As UByte
    Dim c2fb_temp_52 As SQLITE_C_INT
    Dim c2fb_temp_53 As SQLITE_C_INT
    Dim c2fb_temp_54 As SQLITE_C_INT
    Dim c2fb_temp_55 As SQLITE_C_INT
    Dim c2fb_temp_56 As SQLITE_C_INT
    Dim local13 As SqliteWhereTerm Ptr
    Dim local14 As SqliteExpr Ptr
    Dim c2fb_temp_57 As SqliteExpr Ptr
    Dim c2fb_temp_58 As u16 Ptr
    Dim c2fb_temp_59 As UShort
    Dim c2fb_temp_60 As UShort
    Dim c2fb_temp_61 As u16 Ptr
    Dim c2fb_temp_62 As UShort
    Dim c2fb_temp_63 As u8 Ptr
    Dim c2fb_temp_64 As UByte
    Dim c2fb_temp_65 As u16 Ptr
    Dim c2fb_temp_66 As UShort
    Dim c2fb_temp_67 As SqliteExprList Ptr Ptr
    Dim c2fb_temp_68 As SqliteExprList Ptr
    Dim c2fb_temp_69 As SQLITE_C_INT
    Dim c2fb_temp_70 As Short Ptr
    Dim c2fb_temp_71 As Short
    Dim c2fb_temp_72 As sqlite3_uint64
    Dim c2fb_temp_73 As sqlite3_uint64
    Dim c2fb_temp_74 As SQLITE_C_INT
    Dim c2fb_temp_75 As Short Ptr
    Dim c2fb_temp_76 As Short
    Dim local15 As SQLITE_C_INT
    Dim local16 As SQLITE_C_INT
    Dim c2fb_temp_77 As u8 Ptr
    Dim c2fb_temp_78 As UByte
    Dim c2fb_temp_79 As UByte
    Dim c2fb_temp_80 As u32 Ptr
    Dim c2fb_temp_81 As SQLITE_C_UINT
    Dim c2fb_temp_82 As SQLITE_C_INT
    Dim c2fb_temp_83 As SqliteWhereLevel Ptr
    Dim c2fb_temp_84 As SQLITE_C_INT
    Dim c2fb_temp_85 As SqliteWhereLevel Ptr
    Dim local17 As SqliteTable Ptr
    Dim local18 As SQLITE_C_INT
    Dim local19 As SqliteSrcItem Ptr
    Dim c2fb_temp_86 As SqliteSrcItem Ptr
    Dim c2fb_temp_87 As SqliteTable Ptr
    Dim c2fb_temp_88 As SQLITE_C_INT
    Dim c2fb_temp_89 As SqliteWhereLoop Ptr
    Dim c2fb_temp_90 As SQLITE_C_INT Ptr
    Dim c2fb_temp_91 As SQLITE_C_INT
    Dim c2fb_temp_92 As SQLITE_C_INT Ptr
    Dim c2fb_temp_93 As SQLITE_C_INT
    Dim c2fb_temp_94 As SQLITE_C_INT Ptr
    Dim c2fb_temp_95 As SQLITE_C_INT
    Dim c2fb_temp_96 As SQLITE_C_INT Ptr
    Dim c2fb_temp_97 As SQLITE_C_INT
    Dim local20 As Const ZString Ptr
    Dim local21 As SQLITE_C_INT
    Dim local22 As SQLITE_C_INT
    Dim c2fb_temp_98 As SQLITE_C_INT
    Dim c2fb_temp_99 As SQLITE_C_INT Ptr
    Dim c2fb_temp_100 As SQLITE_C_INT
    Dim local23 As sqlite3_uint64
    Dim local24 As SQLITE_C_INT
    Dim c2fb_temp_101 As sqlite3_uint64
    Dim c2fb_temp_102 As SQLITE_C_INT
    Dim local25 As SqliteIndex Ptr
    Dim local26 As SQLITE_C_INT
    Dim local27 As SQLITE_C_INT
    Dim c2fb_temp_103 As SQLITE_C_INT
    Dim c2fb_temp_104 As SQLITE_C_INT
    Dim local28 As SqliteIndex Ptr
    Dim c2fb_temp_105 As SQLITE_C_INT
    Dim c2fb_temp_106 As SQLITE_C_INT
    Dim c2fb_temp_107 As SqliteIndex Ptr
    Dim c2fb_temp_108 As SQLITE_C_INT
    Dim c2fb_temp_109 As SQLITE_C_INT Ptr
    Dim c2fb_temp_110 As SQLITE_C_INT
    Dim c2fb_temp_111 As SQLITE_C_INT
    Dim c2fb_temp_112 As SQLITE_C_INT
    Dim c2fb_temp_113 As SQLITE_C_INT Ptr
    Dim c2fb_temp_114 As SQLITE_C_INT
    Dim c2fb_temp_115 As SQLITE_C_INT
    Dim c2fb_temp_116 As SQLITE_C_INT Ptr
    Dim c2fb_temp_117 As SQLITE_C_INT
    Dim c2fb_temp_118 As Any Ptr Ptr
    Dim c2fb_temp_119 As SqliteWhereRightJoin Ptr
    Dim c2fb_temp_120 As SQLITE_C_INT
    Dim local29 As SqliteWhereRightJoin Ptr
    Dim local30 As SQLITE_C_INT
    Dim c2fb_temp_121 As SQLITE_C_INT Ptr
    Dim c2fb_temp_122 As SQLITE_C_INT
    Dim c2fb_temp_123 As SQLITE_C_INT Ptr
    Dim c2fb_temp_124 As SQLITE_C_INT
    Dim c2fb_temp_125 As SQLITE_C_INT Ptr
    Dim c2fb_temp_126 As SQLITE_C_INT
    Dim c2fb_temp_127 As SQLITE_C_INT
    Dim c2fb_temp_128 As SQLITE_C_INT Ptr
    Dim c2fb_temp_129 As SQLITE_C_INT
    Dim local31 As sqlite3VdbeKeyInfoPrefix Ptr
    Dim c2fb_temp_130 As SQLITE_C_INT
    Dim c2fb_temp_131 As sqlite3VdbeKeyInfoPrefix Ptr
    Dim c2fb_temp_132 As Any Ptr Ptr
    Dim c2fb_temp_133 As sqlite3CollSeq Ptr
    Dim c2fb_temp_134 As UByte Ptr
    Dim c2fb_temp_135 As UByte
    Dim local32 As SqliteIndex Ptr
    Dim c2fb_temp_136 As SQLITE_C_INT
    Dim c2fb_temp_137 As SQLITE_C_INT Ptr
    Dim c2fb_temp_138 As SQLITE_C_INT
    Dim c2fb_temp_139 As SQLITE_C_INT
    Dim c2fb_temp_140 As SQLITE_C_INT Ptr
    Dim c2fb_temp_141 As SQLITE_C_INT
    Dim c2fb_temp_142 As SQLITE_C_INT Ptr
    Dim c2fb_temp_143 As SQLITE_C_INT
    Dim c2fb_temp_144 As u32 Ptr
    Dim c2fb_temp_145 As SQLITE_C_UINT
    Dim c2fb_temp_146 As Byte Ptr
    Dim c2fb_temp_147 As Byte
    Dim c2fb_temp_148 As u8 Ptr
    Dim c2fb_temp_149 As UByte
    Dim c2fb_temp_150 As SQLITE_C_INT Ptr
    Dim c2fb_temp_151 As SQLITE_C_INT
    Dim c2fb_temp_152 As SQLITE_C_INT
    Dim c2fb_temp_153 As SQLITE_C_INT
    Dim local33 As SQLITE_C_INT
    Dim local34 As SQLITE_C_INT
    Dim local35 As SqliteSrcItem Ptr
    Dim c2fb_temp_154 As SqliteWhereLevel Ptr
    Dim c2fb_temp_155 As SQLITE_C_INT
    Dim c2fb_temp_156 As SqliteSrcItem Ptr
    Dim local36 As SqliteSubquery Ptr
    Dim local37 As SQLITE_C_INT
    Dim c2fb_temp_157 As SqliteSubquery Ptr
    Dim c2fb_temp_158 As SQLITE_C_INT
    Dim c2fb_temp_159 As SQLITE_C_INT
    Dim c2fb_temp_160 As SQLITE_C_INT
    Dim c2fb_temp_161 As SQLITE_C_INT Ptr
    Dim c2fb_temp_162 As SQLITE_C_INT
    Dim c2fb_temp_163 As sqlite3_uint64
    Dim c2fb_temp_164 As SQLITE_C_INT Ptr
    Dim c2fb_temp_165 As SQLITE_C_INT
    Dim c2fb_temp_166 As SQLITE_C_INT Ptr
    Dim c2fb_temp_167 As SQLITE_C_INT
    Dim c2fb_temp_168 As Short Ptr
    Dim c2fb_temp_169 As Short

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local3 = CPtr(SqliteVdbe Ptr, arg0->pVdbe)
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    local12 = Cast(SQLITE_C_INT, &O0ULL)
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = arg0->db
    local10 = c2fb_temp_0
    c2fb_temp_1 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteWhereLoopBuilder Ptr, @(local5))), Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereLoopBuilder))))
    ' empty C statement
    If (-Cast(SQLITE_C_INT, ((arg3 AndAlso (-Cast(SQLITE_C_INT, ((arg3->nExpr >= (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))))))))))) Then
        c2fb_temp_2 = CPtr(SqliteExprList Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        arg3 = c2fb_temp_2
        c2fb_temp_3 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg6) And Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, &H0100ULL))))))
        arg6 = c2fb_temp_3
        c2fb_temp_4 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg6) Or Cast(SQLITE_C_INT, &H2000ULL))))
        arg6 = c2fb_temp_4
    End If
    ' empty C statement
    If (-Cast(SQLITE_C_INT, ((arg1->nSrc > (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))))))) Then
        sqlite3ErrorMsg(CPtr(Any Ptr, arg0), StrPtr(!"at most %d tables in a join"), (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))))
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_5 = Cast(SQLITE_C_INT, IIf((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg6) And Cast(SQLITE_C_INT, &H0020ULL)))), Cast(SQLITE_C_INT, 1ULL), arg1->nSrc))
    local1 = c2fb_temp_5
    c2fb_temp_6 = Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, ((Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, (SizeOf(SqliteWhereInfo) - SizeOf(SqliteWhereLevel)))) + Cast(sqlite3_uint64, (Cast(sqlite3_uint64, (local1)) * Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereLevel)))))))) + Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 7ULL))))) And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, 7ULL))))))))
    local0 = c2fb_temp_6
    c2fb_temp_7 = CPtr(SqliteWhereInfo Ptr, CPtr(Any Ptr, sqlite3DbMallocRawNN(CPtr(Any Ptr, local10), Cast(sqlite3_uint64, (Cast(sqlite3_uint64, local0) + Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereLoop))))))))
    local2 = c2fb_temp_7
    If local10->mallocFailed Then
        sqlite3DbFree(CPtr(Any Ptr, local10), CPtr(Any Ptr, local2))
        c2fb_temp_8 = CPtr(SqliteWhereInfo Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
        local2 = c2fb_temp_8
        Goto c2fb_label_0
    End If
    c2fb_temp_9 = CPtr(SqliteParseContext Ptr Ptr, @(local2->pParse))
    c2fb_temp_10 = arg0
    (*c2fb_temp_9) = c2fb_temp_10
    c2fb_temp_11 = CPtr(SqliteSrcList Ptr Ptr, @(local2->pTabList))
    c2fb_temp_12 = arg1
    (*c2fb_temp_11) = c2fb_temp_12
    c2fb_temp_13 = CPtr(SqliteExprList Ptr Ptr, @(local2->pOrderBy))
    c2fb_temp_14 = arg3
    (*c2fb_temp_13) = c2fb_temp_14
    c2fb_temp_15 = CPtr(SqliteExprList Ptr Ptr, @(local2->pResultSet))
    c2fb_temp_16 = arg4
    (*c2fb_temp_15) = c2fb_temp_16
    c2fb_temp_19 = CPtr(SQLITE_C_INT Ptr, @(local2->aiCurOnePass(Cast(SQLITE_C_INT, &O0ULL))))
    c2fb_temp_17 = CPtr(SQLITE_C_INT Ptr, @(local2->aiCurOnePass(Cast(SQLITE_C_INT, 1ULL))))
    c2fb_temp_18 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))
    (*c2fb_temp_17) = c2fb_temp_18
    c2fb_temp_20 = Cast(SQLITE_C_INT, c2fb_temp_18)
    (*c2fb_temp_19) = c2fb_temp_20
    c2fb_temp_21 = CPtr(u8 Ptr, @(local2->nLevel))
    c2fb_temp_22 = Cast(UByte, local1)
    (*c2fb_temp_21) = Cast(u8, c2fb_temp_22)
    c2fb_temp_22 = Cast(UByte, (*c2fb_temp_21))
    c2fb_temp_25 = CPtr(SQLITE_C_INT Ptr, @(local2->iBreak))
    c2fb_temp_23 = CPtr(SQLITE_C_INT Ptr, @(local2->iContinue))
    c2fb_temp_24 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
    (*c2fb_temp_23) = c2fb_temp_24
    c2fb_temp_26 = Cast(SQLITE_C_INT, c2fb_temp_24)
    (*c2fb_temp_25) = c2fb_temp_26
    c2fb_temp_27 = CPtr(u16 Ptr, @(local2->wctrlFlags))
    c2fb_temp_28 = Cast(UShort, arg6)
    (*c2fb_temp_27) = Cast(u16, c2fb_temp_28)
    c2fb_temp_28 = Cast(UShort, (*c2fb_temp_27))
    c2fb_temp_29 = CPtr(Short Ptr, @(local2->iLimit))
    c2fb_temp_30 = Cast(Short, arg7)
    (*c2fb_temp_29) = c2fb_temp_30
    c2fb_temp_31 = CPtr(SQLITE_C_INT Ptr, @(local2->savedNQueryLoop))
    c2fb_temp_32 = Cast(SQLITE_C_INT, arg0->nQueryLoop)
    (*c2fb_temp_31) = c2fb_temp_32
    c2fb_temp_33 = CPtr(SqliteSelect Ptr Ptr, @(local2->pSelect))
    c2fb_temp_34 = arg5
    (*c2fb_temp_33) = c2fb_temp_34
    c2fb_temp_35 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(Byte Ptr, @(local2->nOBSat))), Cast(SQLITE_C_INT, &O0ULL), Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, @(CPtr(SqliteWhereInfo Ptr, 0)->sWC))) - Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, @(CPtr(SqliteWhereInfo Ptr, 0)->nOBSat)))))))
    c2fb_temp_36 = CPtr(Any Ptr, c2fb_crt_memset(CPtr(Any Ptr, CPtr(SqliteWhereLevel Ptr, @(local2->a(Cast(SQLITE_C_INT, &O0ULL))))), Cast(SQLITE_C_INT, &O0ULL), Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereLoop))) + Cast(sqlite3_uint64, (Cast(sqlite3_uint64, local1) * Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereLevel)))))))))
    ' C unused-parameter annotation
    c2fb_temp_37 = CPtr(SqliteWhereMaskSet Ptr, @(local2->sMaskSet))
    local6 = c2fb_temp_37
    c2fb_temp_38 = CPtr(SQLITE_C_INT Ptr, @(local6->n))
    c2fb_temp_39 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_38) = c2fb_temp_39
    c2fb_temp_40 = CPtr(SQLITE_C_INT Ptr, @(local6->ix(Cast(SQLITE_C_INT, &O0ULL))))
    c2fb_temp_41 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 99ULL))))
    (*c2fb_temp_40) = c2fb_temp_41
    c2fb_temp_42 = CPtr(Any Ptr Ptr, @(local5.pWInfo))
    c2fb_temp_43 = local2
    (*c2fb_temp_42) = CPtr(Any Ptr, c2fb_temp_43)
    c2fb_temp_43 = CPtr(SqliteWhereInfo Ptr, (*c2fb_temp_42))
    c2fb_temp_44 = CPtr(Any Ptr Ptr, @(local5.pWC))
    c2fb_temp_45 = CPtr(SqliteWhereClause Ptr, @(local2->sWC))
    (*c2fb_temp_44) = CPtr(Any Ptr, c2fb_temp_45)
    c2fb_temp_45 = CPtr(SqliteWhereClause Ptr, (*c2fb_temp_44))
    c2fb_temp_46 = CPtr(SqliteWhereLoop Ptr Ptr, @(local5.pNew))
    c2fb_temp_47 = CPtr(SqliteWhereLoop Ptr, (CPtr(ZString Ptr, (CPtr(Byte Ptr, (CPtr(ZString Ptr, local2))) + local0))))
    (*c2fb_temp_46) = c2fb_temp_47
    ' C unused-parameter annotation
    whereLoopInit(local5.pNew)
    sqlite3WhereClauseInit(CPtr(SqliteWhereClause Ptr, @(local2->sWC)), local2)
    sqlite3WhereSplit(CPtr(SqliteWhereClause Ptr, @(local2->sWC)), arg2, Cast(SQLITE_C_INT, 44ULL))
    If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        If arg3 Then
            c2fb_temp_48 = CPtr(Byte Ptr, @(local2->nOBSat))
            c2fb_temp_49 = Cast(Byte, arg3->nExpr)
            (*c2fb_temp_48) = c2fb_temp_49
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg6) And Cast(SQLITE_C_INT, &H0100ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local10)->dbOptFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H00000010ULL)))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
            c2fb_temp_50 = CPtr(u8 Ptr, @(local2->eDistinct))
            c2fb_temp_51 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
            (*c2fb_temp_50) = Cast(u8, c2fb_temp_51)
            c2fb_temp_51 = Cast(UByte, (*c2fb_temp_50))
        End If
        If (-Cast(SQLITE_C_INT, (((local2->pSelect) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local2->pSelect->selFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000400ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
            sqlite3VdbeExplainText(arg0, Cast(SQLITE_C_INT, &O0ULL), StrPtr(!"SCAN CONSTANT ROW"))
        End If
    Else
        c2fb_temp_52 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local9 = c2fb_temp_52
        Do
            createMask(local6, arg1->a(local9).iCursor)
            sqlite3WhereTabFuncArgs(arg0, CPtr(SqliteSrcItem Ptr, @(arg1->a(local9))), CPtr(SqliteWhereClause Ptr, @(local2->sWC)))
        c2fb_flow_1:
            c2fb_temp_53 = local9
            local9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_53 + 1)))
            c2fb_temp_54 = local9
        Loop While (-Cast(SQLITE_C_INT, (((c2fb_temp_54) < arg1->nSrc))))
        c2fb_flow_0:
    End If
    sqlite3WhereExprAnalyze(arg1, CPtr(SqliteWhereClause Ptr, @(local2->sWC)))
    If (-Cast(SQLITE_C_INT, ((arg5 AndAlso arg5->pLimit)))) Then
        sqlite3WhereAddLimit(CPtr(SqliteWhereClause Ptr, @(local2->sWC)), arg5)
    End If
    If arg0->nErr Then
        Goto c2fb_label_0
    End If
    c2fb_temp_55 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local9 = c2fb_temp_55
    While (-Cast(SQLITE_C_INT, ((local9 < CPtr(SqliteWhereClause Ptr, local5.pWC)->nBase))))
        local13 = CPtr(SqliteWhereTerm Ptr, @(CPtr(SqliteWhereClause Ptr, local5.pWC)->a[local9]))
        ' C automatic storage declaration
        If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local13->wtFlags) And Cast(SQLITE_C_INT, &H0002ULL))) Then
            Goto c2fb_flow_3
        End If
        c2fb_temp_57 = local13->pExpr
        local14 = c2fb_temp_57
        ' C unused-parameter annotation
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local13->prereqAll = Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_INT, &O0ULL))))) OrElse exprIsDeterministic(local14)))))))))) AndAlso (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local14)->flags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H000002ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg1->a(Cast(SQLITE_C_INT, &O0ULL)).fg.jointype) And Cast(SQLITE_C_INT, &H40ULL)))) <> Cast(SQLITE_C_INT, &O0ULL)))))))))) = 0))))))) Then
            sqlite3ExprIfFalse(CPtr(Any Ptr, arg0), CPtr(Any Ptr, local14), local2->iBreak, Cast(SQLITE_C_INT, &H10ULL))
            c2fb_temp_58 = CPtr(u16 Ptr, @(local13->wtFlags))
            c2fb_temp_59 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_58))) Or Cast(SQLITE_C_INT, &H0004ULL))))
            (*c2fb_temp_58) = Cast(u16, c2fb_temp_59)
            c2fb_temp_59 = Cast(UShort, (*c2fb_temp_58))
        End If
    c2fb_flow_3:
        c2fb_temp_56 = local9
        local9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_56 + 1)))
    Wend
    c2fb_flow_2:
    If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg6) And Cast(SQLITE_C_INT, &H0100ULL))) Then
        If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local10)->dbOptFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H00000010ULL)))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
            c2fb_temp_60 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg6) And Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, &H0100ULL))))))
            arg6 = c2fb_temp_60
            c2fb_temp_61 = CPtr(u16 Ptr, @(local2->wctrlFlags))
            c2fb_temp_62 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_61))) And Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, &H0100ULL))))))
            (*c2fb_temp_61) = Cast(u16, c2fb_temp_62)
            c2fb_temp_62 = Cast(UShort, (*c2fb_temp_61))
        Else
            If isDistinctRedundant(arg0, arg1, CPtr(SqliteWhereClause Ptr, @(local2->sWC)), arg4) Then
                c2fb_temp_63 = CPtr(u8 Ptr, @(local2->eDistinct))
                c2fb_temp_64 = Cast(UByte, Cast(SQLITE_C_INT, 1ULL))
                (*c2fb_temp_63) = Cast(u8, c2fb_temp_64)
                c2fb_temp_64 = Cast(UByte, (*c2fb_temp_63))
            Else
                If (-Cast(SQLITE_C_INT, ((arg3 = Cast(SQLITE_C_INT, &O0ULL))))) Then
                    c2fb_temp_65 = CPtr(u16 Ptr, @(local2->wctrlFlags))
                    c2fb_temp_66 = Cast(UShort, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, Cast(UShort, (*c2fb_temp_65))) Or Cast(SQLITE_C_INT, &H0080ULL))))
                    (*c2fb_temp_65) = Cast(u16, c2fb_temp_66)
                    c2fb_temp_66 = Cast(UShort, (*c2fb_temp_65))
                    c2fb_temp_67 = CPtr(SqliteExprList Ptr Ptr, @(local2->pOrderBy))
                    c2fb_temp_68 = arg4
                    (*c2fb_temp_67) = c2fb_temp_68
                End If
            End If
        End If
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local1 <> Cast(SQLITE_C_INT, 1ULL))))) OrElse (-Cast(SQLITE_C_INT, ((whereShortCut(CPtr(SqliteWhereLoopBuilder Ptr, @(local5))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        c2fb_temp_69 = Cast(SQLITE_C_INT, whereLoopAddAll(CPtr(SqliteWhereLoopBuilder Ptr, @(local5))))
        local11 = c2fb_temp_69
        If local11 Then
            Goto c2fb_label_0
        End If
        ' empty C statement
        wherePathSolver(local2, Cast(SQLITE_C_INT, &O0ULL))
        If local10->mallocFailed Then
            Goto c2fb_label_0
        End If
        If local2->pOrderBy Then
            whereInterstageHeuristic(local2)
            wherePathSolver(local2, IIf((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->nRowOut) < Cast(SQLITE_C_INT, &O0ULL))))), Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local2->nRowOut) + Cast(SQLITE_C_INT, 1ULL)))))
            If local10->mallocFailed Then
                Goto c2fb_label_0
            End If
        End If
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local2->wctrlFlags) And Cast(SQLITE_C_INT, &H0100ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            ' empty C statement
            c2fb_temp_70 = CPtr(Short Ptr, @(local2->nRowOut))
            c2fb_temp_71 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (*c2fb_temp_70)) - Cast(SQLITE_C_INT, 30ULL))))
            (*c2fb_temp_70) = c2fb_temp_71
        End If
    End If
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local2->pOrderBy = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(sqlite3_uint64, (local10->flags And Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &H00001000ULL))))) <> Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
        whereReverseScanOrder(local2)
    End If
    If arg0->nErr Then
        Goto c2fb_label_0
    End If
    ' C unused-parameter annotation
    c2fb_temp_72 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (Not Cast(sqlite3_uint64, Cast(SQLITE_C_INT, &O0ULL)))))
    local4 = c2fb_temp_72
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->nLevel) >= Cast(SQLITE_C_INT, 2ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((arg4 <> Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg6) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H0400ULL) Or Cast(SQLITE_C_INT, &H2000ULL))))))))))))))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local10)->dbOptFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H00000100ULL)))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
        c2fb_temp_73 = Cast(sqlite3_uint64, whereOmitNoopJoin(local2, local4))
        local4 = c2fb_temp_73
        c2fb_temp_74 = Cast(SQLITE_C_INT, local2->nLevel)
        local1 = c2fb_temp_74
        ' C unused-parameter annotation
    End If
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->nLevel) >= Cast(SQLITE_C_INT, 2ULL))))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local10)->dbOptFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H00080000ULL)))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
        whereCheckIfBloomFilterIsUseful(CPtr(Const SqliteWhereInfo Ptr, local2))
    End If
    c2fb_temp_75 = CPtr(Short Ptr, @(local2->pParse->nQueryLoop))
    c2fb_temp_76 = Cast(Short, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, (*c2fb_temp_75)) + Cast(SQLITE_C_INT, local2->nRowOut))))
    (*c2fb_temp_75) = c2fb_temp_76
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg6) And Cast(SQLITE_C_INT, &H0004ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
        local15 = local2->a(Cast(SQLITE_C_INT, &O0ULL)).pWLoop->wsFlags
        local16 = (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (local15 And Cast(SQLITE_C_INT, &H00001000ULL)))) <> Cast(SQLITE_C_INT, &O0ULL)))))
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, ((local16 OrElse ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) <> (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg6) And Cast(SQLITE_C_INT, &H0008ULL)))))))) AndAlso (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (arg1->a(Cast(SQLITE_C_INT, &O0ULL)).pSTab)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))) = 0))))))) AndAlso ((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) = (Cast(SQLITE_C_INT, (local15 And Cast(SQLITE_C_INT, &H00002000ULL)))))))) OrElse (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg6) And Cast(SQLITE_C_INT, &H0010ULL))))))))))))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local10)->dbOptFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H08000000ULL)))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))))))))) Then
            c2fb_temp_77 = CPtr(u8 Ptr, @(local2->eOnePass))
            c2fb_temp_78 = Cast(UByte, IIf(local16, Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, 2ULL)))
            (*c2fb_temp_77) = Cast(u8, c2fb_temp_78)
            c2fb_temp_78 = Cast(UByte, (*c2fb_temp_77))
            If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((arg1->a(Cast(SQLITE_C_INT, &O0ULL)).pSTab)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) AndAlso (Cast(SQLITE_C_INT, (local15 And Cast(SQLITE_C_INT, &H00000040ULL)))))))) Then
                If Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg6) And Cast(SQLITE_C_INT, &H0008ULL))) Then
                    c2fb_temp_79 = Cast(UByte, Cast(SQLITE_C_INT, &H08ULL))
                    local12 = c2fb_temp_79
                End If
                c2fb_temp_80 = CPtr(u32 Ptr, @(local2->a(Cast(SQLITE_C_INT, &O0ULL)).pWLoop->wsFlags))
                c2fb_temp_81 = Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (local15 And Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, &H00000040ULL)))))))
                (*c2fb_temp_80) = Cast(u32, c2fb_temp_81)
                c2fb_temp_81 = Cast(SQLITE_C_UINT, (*c2fb_temp_80))
            End If
        End If
    End If
    c2fb_temp_82 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local9 = c2fb_temp_82
    c2fb_temp_83 = CPtr(SqliteWhereLevel Ptr, (@local2->a(0)))
    local7 = c2fb_temp_83
    While (-Cast(SQLITE_C_INT, ((local9 < local1))))
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        c2fb_temp_86 = CPtr(SqliteSrcItem Ptr, @(arg1->a(local7->iFrom)))
        local19 = c2fb_temp_86
        c2fb_temp_87 = local19->pSTab
        local17 = c2fb_temp_87
        c2fb_temp_88 = Cast(SQLITE_C_INT, sqlite3SchemaToIndex(CPtr(Any Ptr, local10), CPtr(Any Ptr, CPtr(SqliteSchema Ptr, local17->pSchema))))
        local18 = c2fb_temp_88
        c2fb_temp_89 = local7->pWLoop
        local8 = c2fb_temp_89
        c2fb_temp_90 = CPtr(SQLITE_C_INT Ptr, @(local7->addrBrk))
        c2fb_temp_91 = Cast(SQLITE_C_INT, sqlite3VdbeMakeLabel(arg0))
        (*c2fb_temp_90) = c2fb_temp_91
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local9 = Cast(SQLITE_C_INT, &O0ULL))))) OrElse (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local19[Cast(SQLITE_C_INT, &O0ULL)].fg.jointype) And Cast(SQLITE_C_INT, &H08ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
            c2fb_temp_92 = CPtr(SQLITE_C_INT Ptr, @(local7->addrHalt))
            c2fb_temp_93 = Cast(SQLITE_C_INT, local7->addrBrk)
            (*c2fb_temp_92) = c2fb_temp_93
        Else
            If CPtr(SqliteWhereRightJoin Ptr, local2->a(Cast(SQLITE_C_INT, (local9 - Cast(SQLITE_C_INT, 1ULL)))).pRJ) Then
                c2fb_temp_94 = CPtr(SQLITE_C_INT Ptr, @(local7->addrHalt))
                c2fb_temp_95 = Cast(SQLITE_C_INT, local2->a(Cast(SQLITE_C_INT, (local9 - Cast(SQLITE_C_INT, 1ULL)))).addrBrk)
                (*c2fb_temp_94) = c2fb_temp_95
            Else
                c2fb_temp_96 = CPtr(SQLITE_C_INT Ptr, @(local7->addrHalt))
                c2fb_temp_97 = Cast(SQLITE_C_INT, local2->a(Cast(SQLITE_C_INT, (local9 - Cast(SQLITE_C_INT, 1ULL)))).addrHalt)
                (*c2fb_temp_96) = c2fb_temp_97
            End If
        End If
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local17->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00004000ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) OrElse ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local17)->eTabType) = Cast(SQLITE_C_INT, 2ULL)))))))))) Then
            ' empty C block
        Else
            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local8->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000400ULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
                local20 = CPtr(Const ZString Ptr, CPtr(SqliteVTable Ptr, sqlite3GetVTable(CPtr(Any Ptr, local10), CPtr(Any Ptr, local17))))
                local21 = local19->iCursor
                sqlite3VdbeAddOp4(local3, Cast(SQLITE_C_INT, 175ULL), local21, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL), local20, (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 12ULL)))))
            Else
                If ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (local17)->eTabType) = Cast(SQLITE_C_INT, 1ULL)))))) Then
                    ' empty C block
                Else
                    If (-Cast(SQLITE_C_INT, ((((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local8->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000040ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg6) And Cast(SQLITE_C_INT, &H0020ULL)))) = Cast(SQLITE_C_INT, &O0ULL)))))))))) OrElse (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local19->fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H40ULL) Or Cast(SQLITE_C_INT, &H10ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                        local22 = Cast(SQLITE_C_INT, 114ULL)
                        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->eOnePass) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                            c2fb_temp_98 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 116ULL))
                            local22 = c2fb_temp_98
                            c2fb_temp_99 = CPtr(SQLITE_C_INT Ptr, @(local2->aiCurOnePass(Cast(SQLITE_C_INT, &O0ULL))))
                            c2fb_temp_100 = Cast(SQLITE_C_INT, local19->iCursor)
                            (*c2fb_temp_99) = c2fb_temp_100
                        End If
                        ' empty C statement
                        sqlite3OpenTable(CPtr(Any Ptr, arg0), local19->iCursor, local18, CPtr(Any Ptr, local17), local22)
                        ' C unused-parameter annotation
                        ' empty C statement
                        ' empty C statement
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->eOnePass) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local17->nCol) < (Cast(SQLITE_C_INT, (Cast(sqlite3_uint64, (Cast(sqlite3_uint64, Cast(SQLITE_SIZE_T, SizeOf(sqlite3_uint64))) * Cast(sqlite3_uint64, Cast(SQLITE_C_INT, 8ULL))))))))))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local17->tabFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000060ULL) Or Cast(SQLITE_C_INT, &H00000080ULL)))))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local8->wsFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00004000ULL) Or Cast(SQLITE_C_INT, &H00400000ULL)))))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) Then
                            local23 = local19->colUsed
                            local24 = Cast(SQLITE_C_INT, &O0ULL)
                            While local23
                                ' empty C block
                            c2fb_flow_7:
                                c2fb_temp_101 = Cast(sqlite3_uint64, Cast(sqlite3_uint64, (local23 Shr Cast(SQLITE_C_INT, 1ULL))))
                                local23 = c2fb_temp_101
                                c2fb_temp_102 = local24
                                local24 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_102 + 1)))
                            Wend
                            c2fb_flow_6:
                            sqlite3VdbeChangeP4(local3, Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))), CPtr(Const ZString Ptr, (CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_LONG, (local24)))))), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 3ULL)))))
                            ' C unused-parameter annotation
                        End If
                        sqlite3VdbeChangeP5(local3, local12)
                        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((local9 >= Cast(SQLITE_C_INT, 2ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local19[Cast(SQLITE_C_INT, &O0ULL)].fg.jointype) And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H40ULL) Or Cast(SQLITE_C_INT, &H08ULL))))))) = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((local7->addrHalt = local2->a(Cast(SQLITE_C_INT, &O0ULL)).addrHalt)))))))) Then
                            sqlite3VdbeAddOp2(local3, Cast(SQLITE_C_INT, 37ULL), local19->iCursor, local2->iBreak)
                            ' empty C statement
                        End If
                    Else
                        sqlite3TableLock(CPtr(Any Ptr, arg0), local18, local17->tnum, Cast(SQLITE_C_INT, &O0ULL), CPtr(Const ZString Ptr, local17->zName))
                    End If
                End If
            End If
        End If
        If Cast(SQLITE_C_UINT, (local8->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000200ULL)))) Then
            local25 = CPtr(SqliteIndex Ptr, local8->u.btree.pIndex)
            ' C automatic storage declaration
            local27 = Cast(SQLITE_C_INT, 114ULL)
            ' C unused-parameter annotation
            If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local17)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) = 0))) AndAlso ((-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, (local25)->flags) Shr 0) And Cast(SQLITE_C_UINT, &H3ULL))) = Cast(SQLITE_C_INT, 2ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg6) And Cast(SQLITE_C_INT, &H0020ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                c2fb_temp_103 = Cast(SQLITE_C_INT, local7->iTabCur)
                local26 = c2fb_temp_103
                c2fb_temp_104 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local27 = c2fb_temp_104
            Else
                If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->eOnePass) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                    local28 = CPtr(SqliteIndex Ptr, local19->pSTab->pIndex)
                    c2fb_temp_105 = Cast(SQLITE_C_INT, arg7)
                    local26 = c2fb_temp_105
                    ' C unused-parameter annotation
                    While (-Cast(SQLITE_C_INT, (((local28) AndAlso (-Cast(SQLITE_C_INT, ((local28 <> local25))))))))
                        c2fb_temp_106 = local26
                        local26 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_106 + 1)))
                        c2fb_temp_107 = local28->pNext
                        local28 = c2fb_temp_107
                    c2fb_flow_9:
                    Wend
                    c2fb_flow_8:
                    c2fb_temp_108 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 116ULL))
                    local27 = c2fb_temp_108
                    c2fb_temp_109 = CPtr(SQLITE_C_INT Ptr, @(local2->aiCurOnePass(Cast(SQLITE_C_INT, 1ULL))))
                    c2fb_temp_110 = Cast(SQLITE_C_INT, local26)
                    (*c2fb_temp_109) = c2fb_temp_110
                Else
                    If (-Cast(SQLITE_C_INT, ((arg7 AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg6) And Cast(SQLITE_C_INT, &H0020ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                        c2fb_temp_111 = Cast(SQLITE_C_INT, arg7)
                        local26 = c2fb_temp_111
                        c2fb_temp_112 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 113ULL))
                        local27 = c2fb_temp_112
                    Else
                        c2fb_temp_113 = CPtr(SQLITE_C_INT Ptr, @(arg0->nTab))
                        c2fb_temp_114 = (*c2fb_temp_113)
                        (*c2fb_temp_113) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_114 + 1)))
                        c2fb_temp_115 = Cast(SQLITE_C_INT, c2fb_temp_114)
                        local26 = c2fb_temp_115
                        If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local25->flags) Shr 11) And Cast(SQLITE_C_UINT, &H1ULL))) AndAlso ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local10)->dbOptFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, &H01000000ULL)))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))))))) Then
                            whereAddIndexedExpr(arg0, local25, local26, local19)
                        End If
                        If (-Cast(SQLITE_C_INT, ((CPtr(SqliteExpr Ptr, local25->pPartIdxWhere) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local19->fg.jointype) And Cast(SQLITE_C_INT, &H10ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
                            wherePartIdxExpr(arg0, local25, CPtr(SqliteExpr Ptr, local25->pPartIdxWhere), Cast(SQLITE_C_INT, &O0ULL), local26, local19)
                        End If
                    End If
                End If
            End If
            c2fb_temp_116 = CPtr(SQLITE_C_INT Ptr, @(local7->iIdxCur))
            c2fb_temp_117 = Cast(SQLITE_C_INT, local26)
            (*c2fb_temp_116) = c2fb_temp_117
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            ' C unused-parameter annotation
            If local27 Then
                sqlite3VdbeAddOp3(local3, local27, local26, local25->tnum, local18)
                sqlite3VdbeSetP4KeyInfo(arg0, local25)
                If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local8->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H0000000fULL))))) <> Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local8->wsFlags And Cast(SQLITE_C_UINT, (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00000002ULL) Or Cast(SQLITE_C_INT, &H00008000ULL)))))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local8->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00080000ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local8->wsFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00100000ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local2->wctrlFlags) And Cast(SQLITE_C_INT, &H0001ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))))))) AndAlso (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, local2->eDistinct) <> Cast(SQLITE_C_INT, 2ULL))))))))) Then
                    sqlite3VdbeChangeP5(local3, Cast(SQLITE_C_INT, &H02ULL))
                End If
                ' empty C statement
            End If
        End If
        If (-Cast(SQLITE_C_INT, ((local18 >= Cast(SQLITE_C_INT, &O0ULL))))) Then
            sqlite3CodeVerifySchema(CPtr(Any Ptr, arg0), local18)
        End If
        c2fb_temp_120 = 0
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, local19->fg.jointype) And Cast(SQLITE_C_INT, &H10ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            c2fb_temp_118 = CPtr(Any Ptr Ptr, @(local7->pRJ))
            c2fb_temp_119 = CPtr(SqliteWhereRightJoin Ptr, CPtr(Any Ptr, sqlite3WhereMalloc(local2, Cast(SQLITE_SIZE_T, SizeOf(SqliteWhereRightJoin)))))
            (*c2fb_temp_118) = CPtr(Any Ptr, c2fb_temp_119)
            c2fb_temp_119 = CPtr(SqliteWhereRightJoin Ptr, (*c2fb_temp_118))
            c2fb_temp_120 = (-Cast(SQLITE_C_INT, ((-Cast(SQLITE_C_INT, (((c2fb_temp_119) <> Cast(SQLITE_C_INT, &O0ULL))))) <> 0)))
        End If
        If c2fb_temp_120 Then
            local29 = CPtr(SqliteWhereRightJoin Ptr, local7->pRJ)
            local30 = Cast(SQLITE_C_INT, &O0ULL)
            c2fb_temp_123 = CPtr(SQLITE_C_INT Ptr, @(local29->iMatch))
            c2fb_temp_121 = CPtr(SQLITE_C_INT Ptr, @(arg0->nTab))
            c2fb_temp_122 = (*c2fb_temp_121)
            (*c2fb_temp_121) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_122 + 1)))
            c2fb_temp_124 = Cast(SQLITE_C_INT, c2fb_temp_122)
            (*c2fb_temp_123) = c2fb_temp_124
            c2fb_temp_128 = CPtr(SQLITE_C_INT Ptr, @(local29->regReturn))
            c2fb_temp_125 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
            c2fb_temp_126 = (*c2fb_temp_125)
            (*c2fb_temp_125) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_126 + 1)))
            c2fb_temp_127 = (*c2fb_temp_125)
            c2fb_temp_129 = Cast(SQLITE_C_INT, c2fb_temp_127)
            (*c2fb_temp_128) = c2fb_temp_129
            sqlite3VdbeAddOp2(local3, Cast(SQLITE_C_INT, 77ULL), Cast(SQLITE_C_INT, &O0ULL), local29->regReturn)
            ' C unused-parameter annotation
            If ((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, ((local17)->tabFlags And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &H00000080ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))) Then
                ' C automatic storage declaration
                sqlite3VdbeAddOp2(local3, Cast(SQLITE_C_INT, 120ULL), local29->iMatch, Cast(SQLITE_C_INT, 1ULL))
                c2fb_temp_130 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
                local30 = c2fb_temp_130
                c2fb_temp_131 = CPtr(sqlite3VdbeKeyInfoPrefix Ptr, sqlite3KeyInfoAlloc(CPtr(Any Ptr, arg0->db), Cast(SQLITE_C_INT, 1ULL), Cast(SQLITE_C_INT, &O0ULL)))
                local31 = c2fb_temp_131
                If local31 Then
                    c2fb_temp_132 = CPtr(Any Ptr Ptr, @(local31->aColl(Cast(SQLITE_C_INT, &O0ULL))))
                    c2fb_temp_133 = CPtr(sqlite3CollSeq Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
                    (*c2fb_temp_132) = CPtr(Any Ptr, c2fb_temp_133)
                    c2fb_temp_133 = CPtr(sqlite3CollSeq Ptr, (*c2fb_temp_132))
                    c2fb_temp_134 = CPtr(UByte Ptr, @(local31->aSortFlags[Cast(SQLITE_C_INT, &O0ULL)]))
                    c2fb_temp_135 = Cast(UByte, Cast(SQLITE_C_INT, &O0ULL))
                    (*c2fb_temp_134) = c2fb_temp_135
                    sqlite3VdbeAppendP4(local3, CPtr(Any Ptr, local31), (Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 9ULL)))))
                End If
            Else
                local32 = CPtr(SqliteIndex Ptr, sqlite3PrimaryKeyIndex(CPtr(Any Ptr, local17)))
                sqlite3VdbeAddOp2(local3, Cast(SQLITE_C_INT, 120ULL), local29->iMatch, local32->nKeyCol)
                sqlite3VdbeSetP4KeyInfo(arg0, local32)
                c2fb_temp_136 = Cast(SQLITE_C_INT, sqlite3IndexBloomable(CPtr(Any Ptr, local32), local32->nKeyCol))
                local30 = c2fb_temp_136
            End If
            If local30 Then
                c2fb_temp_140 = CPtr(SQLITE_C_INT Ptr, @(local29->regBloom))
                c2fb_temp_137 = CPtr(SQLITE_C_INT Ptr, @(arg0->nMem))
                c2fb_temp_138 = (*c2fb_temp_137)
                (*c2fb_temp_137) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_138 + 1)))
                c2fb_temp_139 = (*c2fb_temp_137)
                c2fb_temp_141 = Cast(SQLITE_C_INT, c2fb_temp_139)
                (*c2fb_temp_140) = c2fb_temp_141
                sqlite3VdbeAddOp2(local3, Cast(SQLITE_C_INT, 79ULL), Cast(SQLITE_C_INT, 65536ULL), local29->regBloom)
            Else
                c2fb_temp_142 = CPtr(SQLITE_C_INT Ptr, @(local29->regBloom))
                c2fb_temp_143 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                (*c2fb_temp_142) = c2fb_temp_143
            End If
            c2fb_temp_144 = CPtr(u32 Ptr, @(local8->wsFlags))
            c2fb_temp_145 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_144)) And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, &H00000040ULL)))))))
            (*c2fb_temp_144) = Cast(u32, c2fb_temp_145)
            c2fb_temp_145 = Cast(SQLITE_C_UINT, (*c2fb_temp_144))
            c2fb_temp_146 = CPtr(Byte Ptr, @(local2->nOBSat))
            c2fb_temp_147 = Cast(Byte, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_146) = c2fb_temp_147
            c2fb_temp_148 = CPtr(u8 Ptr, @(local2->eDistinct))
            c2fb_temp_149 = Cast(UByte, Cast(SQLITE_C_INT, 3ULL))
            (*c2fb_temp_148) = Cast(u8, c2fb_temp_149)
            c2fb_temp_149 = Cast(UByte, (*c2fb_temp_148))
        End If
    c2fb_flow_5:
        c2fb_temp_84 = local9
        local9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_84 + 1)))
        c2fb_temp_85 = local7
        local7 = (c2fb_temp_85 + 1)
    Wend
    c2fb_flow_4:
    c2fb_temp_150 = CPtr(SQLITE_C_INT Ptr, @(local2->iTop))
    c2fb_temp_151 = Cast(SQLITE_C_INT, sqlite3VdbeCurrentAddr(local3))
    (*c2fb_temp_150) = c2fb_temp_151
    If local10->mallocFailed Then
        Goto c2fb_label_0
    End If
    c2fb_temp_152 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
    local9 = c2fb_temp_152
    While (-Cast(SQLITE_C_INT, ((local9 < local1))))
        ' C automatic storage declaration
        ' C automatic storage declaration
        ' C automatic storage declaration
        If arg0->nErr Then
            Goto c2fb_label_0
        End If
        c2fb_temp_154 = CPtr(SqliteWhereLevel Ptr, @(local2->a(local9)))
        local7 = c2fb_temp_154
        c2fb_temp_155 = Cast(SQLITE_C_INT, local7->pWLoop->wsFlags)
        local34 = c2fb_temp_155
        c2fb_temp_156 = CPtr(SqliteSrcItem Ptr, @(arg1->a(local7->iFrom)))
        local35 = c2fb_temp_156
        If Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local35->fg.flags) Shr 5) And Cast(SQLITE_C_UINT, &H1ULL))) Then
            ' C automatic storage declaration
            local37 = Cast(SQLITE_C_INT, &O0ULL)
            ' C unused-parameter annotation
            c2fb_temp_157 = local35->u4.pSubq
            local36 = c2fb_temp_157
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, local35->fg.flags) Shr 4) And Cast(SQLITE_C_UINT, &H1ULL))) = Cast(SQLITE_C_INT, &O0ULL))))) Then
                c2fb_temp_158 = Cast(SQLITE_C_INT, sqlite3VdbeAddOp0(local3, Cast(SQLITE_C_INT, 15ULL)))
                local37 = c2fb_temp_158
                ' empty C statement
            Else
                c2fb_temp_159 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
                local37 = c2fb_temp_159
            End If
            sqlite3VdbeAddOp2(local3, Cast(SQLITE_C_INT, 10ULL), local36->regReturn, local36->addrFillSub)
            ' empty C statement
            If local37 Then
                sqlite3VdbeJumpHere(local3, local37)
            End If
        End If
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (local34 And (Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, &H00004000ULL) Or Cast(SQLITE_C_INT, &H00400000ULL))))))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
            If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (local34 And Cast(SQLITE_C_INT, &H00004000ULL)))) <> Cast(SQLITE_C_INT, &O0ULL))))) Then
                constructAutomaticIndex(arg0, CPtr(SqliteWhereClause Ptr, @(local2->sWC)), local4, local7)
            Else
                sqlite3ConstructBloomFilter(local2, local9, local7, local4)
            End If
            If local10->mallocFailed Then
                Goto c2fb_label_0
            End If
        End If
        c2fb_temp_160 = Cast(SQLITE_C_INT, sqlite3WhereExplainOneScan(arg0, arg1, local7, arg6))
        local33 = c2fb_temp_160
        c2fb_temp_161 = CPtr(SQLITE_C_INT Ptr, @(local7->addrBody))
        c2fb_temp_162 = Cast(SQLITE_C_INT, sqlite3VdbeCurrentAddr(local3))
        (*c2fb_temp_161) = c2fb_temp_162
        c2fb_temp_163 = Cast(sqlite3_uint64, sqlite3WhereCodeOneLoopStart(arg0, local3, local2, local9, local7, local4))
        local4 = c2fb_temp_163
        c2fb_temp_164 = CPtr(SQLITE_C_INT Ptr, @(local2->iContinue))
        c2fb_temp_165 = Cast(SQLITE_C_INT, local7->addrCont)
        (*c2fb_temp_164) = c2fb_temp_165
        If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (local34 And Cast(SQLITE_C_INT, &H00002000ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, arg6) And Cast(SQLITE_C_INT, &H0020ULL)))) = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
#ifdef SQLITE_ENABLE_STMT_SCANSTATUS
            sqlite3WhereAddScanStatus(local3, arg1, local7, local33)
#else
            ' C unused-parameter annotation
#endif
        End If
    c2fb_flow_11:
        c2fb_temp_153 = local9
        local9 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_153 + 1)))
    Wend
    c2fb_flow_10:
    ' empty C statement
    c2fb_temp_166 = CPtr(SQLITE_C_INT Ptr, @(local2->iEndWhere))
    c2fb_temp_167 = Cast(SQLITE_C_INT, sqlite3VdbeCurrentAddr(local3))
    (*c2fb_temp_166) = c2fb_temp_167
    Return local2
    c2fb_label_0:
    If local2 Then
        c2fb_temp_168 = CPtr(Short Ptr, @(arg0->nQueryLoop))
        c2fb_temp_169 = Cast(Short, local2->savedNQueryLoop)
        (*c2fb_temp_168) = c2fb_temp_169
        whereInfoFree(local10, local2)
    End If
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function

' c2fb skipped sqlite3WhereEnd: outside the supported subset
/' end of sqlite3_bulk_where_begin.bas '/
