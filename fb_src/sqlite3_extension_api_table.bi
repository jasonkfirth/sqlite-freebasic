/'
** 2006 June 7
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
    Project: SQLite FreeBASIC port
    File: sqlite3_extension_api_table.bi
    Purpose: Keep the C sqlite3_api_routines pointer layout for extensions.
    Source order: the preprocessed sqlite3Apis initializer.
    Unported API entries are null until their FreeBASIC bodies are present.

    Responsibilities:
        - Preserve every function-pointer slot and its C field order.
        - Point to ported API bodies and leave missing bodies null.

    This file intentionally does NOT contain:
        - SQLite API implementations or extension-load behavior.
'/
#ifndef SQLITE3_FB_EXTENSION_API_TABLE_BI
#define SQLITE3_FB_EXTENSION_API_TABLE_BI

Declare Function sqlite3_value_blob CDecl Alias "sqlite3_value_blob" () As Any Ptr
Declare Function sqlite3_value_bytes CDecl Alias "sqlite3_value_bytes" () As Any Ptr
Declare Function sqlite3_value_bytes16 CDecl Alias "sqlite3_value_bytes16" () As Any Ptr
Declare Function sqlite3_value_double CDecl Alias "sqlite3_value_double" () As Any Ptr
Declare Function sqlite3_value_int CDecl Alias "sqlite3_value_int" () As Any Ptr
Declare Function sqlite3_value_int64 CDecl Alias "sqlite3_value_int64" () As Any Ptr
Declare Function sqlite3_value_numeric_type CDecl Alias "sqlite3_value_numeric_type" () As Any Ptr
Declare Function sqlite3_value_text CDecl Alias "sqlite3_value_text" () As Any Ptr
Declare Function sqlite3_value_text16 CDecl Alias "sqlite3_value_text16" () As Any Ptr
Declare Function sqlite3_value_text16be CDecl Alias "sqlite3_value_text16be" () As Any Ptr
Declare Function sqlite3_value_text16le CDecl Alias "sqlite3_value_text16le" () As Any Ptr
Declare Function sqlite3_value_type CDecl Alias "sqlite3_value_type" () As Any Ptr
Declare Function sqlite3_memory_highwater CDecl Alias "sqlite3_memory_highwater" () As Any Ptr
Declare Function sqlite3_memory_used CDecl Alias "sqlite3_memory_used" () As Any Ptr
Declare Function sqlite3_status CDecl Alias "sqlite3_status" () As Any Ptr
Declare Function sqlite3_value_dup CDecl Alias "sqlite3_value_dup" () As Any Ptr
Declare Function sqlite3_value_free CDecl Alias "sqlite3_value_free" () As Any Ptr
Declare Function sqlite3_value_subtype CDecl Alias "sqlite3_value_subtype" () As Any Ptr
Declare Function sqlite3_status64 CDecl Alias "sqlite3_status64" () As Any Ptr
Declare Function sqlite3_value_pointer CDecl Alias "sqlite3_value_pointer" () As Any Ptr
Declare Function sqlite3_value_nochange CDecl Alias "sqlite3_value_nochange" () As Any Ptr
Declare Function sqlite3_str_new CDecl Alias "sqlite3_str_new" () As Any Ptr
Declare Function sqlite3_str_finish CDecl Alias "sqlite3_str_finish" () As Any Ptr
Declare Function sqlite3_str_append CDecl Alias "sqlite3_str_append" () As Any Ptr
Declare Function sqlite3_str_appendall CDecl Alias "sqlite3_str_appendall" () As Any Ptr
Declare Function sqlite3_str_appendchar CDecl Alias "sqlite3_str_appendchar" () As Any Ptr
Declare Function sqlite3_str_reset CDecl Alias "sqlite3_str_reset" () As Any Ptr
Declare Function sqlite3_str_errcode CDecl Alias "sqlite3_str_errcode" () As Any Ptr
Declare Function sqlite3_str_length CDecl Alias "sqlite3_str_length" () As Any Ptr
Declare Function sqlite3_str_value CDecl Alias "sqlite3_str_value" () As Any Ptr
Declare Function sqlite3_value_frombind CDecl Alias "sqlite3_value_frombind" () As Any Ptr
Declare Function sqlite3_vtab_in_first CDecl Alias "sqlite3_vtab_in_first" () As Any Ptr
Declare Function sqlite3_vtab_in_next CDecl Alias "sqlite3_vtab_in_next" () As Any Ptr
Declare Function sqlite3_value_encoding CDecl Alias "sqlite3_value_encoding" () As Any Ptr
Declare Function sqlite3_str_truncate CDecl Alias "sqlite3_str_truncate" () As Any Ptr
Declare Function sqlite3_str_free CDecl Alias "sqlite3_str_free" () As Any Ptr

' C stores only function pointers in this struct; the pointer array preserves offsets.
Private Dim Shared sqlite3Apis(0 To 278) As Any Ptr
Private Dim Shared sqlite3ApiTableReady As u8

Private Function sqlite3InitializeApiTable() As SQLITE_C_INT
    Dim pInitializationMutex As Any Ptr = sqlite3_mutex_alloc(SQLITE_MUTEX_STATIC_MASTER)
#if SQLITE_THREADSAFE <> 0
    If pInitializationMutex = 0 Then Return SQLITE_MISUSE
#endif
    If pInitializationMutex <> 0 Then sqlite3_mutex_enter(pInitializationMutex)
    If sqlite3ApiTableReady = 0 Then
        sqlite3Apis(0) = CPtr(Any Ptr, ProcPtr(sqlite3_aggregate_context))
        sqlite3Apis(1) = CPtr(Any Ptr, ProcPtr(sqlite3_aggregate_count))
        sqlite3Apis(2) = CPtr(Any Ptr, ProcPtr(sqlite3_bind_blob))
        sqlite3Apis(3) = CPtr(Any Ptr, ProcPtr(sqlite3_bind_double))
        sqlite3Apis(4) = CPtr(Any Ptr, ProcPtr(sqlite3_bind_int))
        sqlite3Apis(5) = CPtr(Any Ptr, ProcPtr(sqlite3_bind_int64))
        sqlite3Apis(6) = CPtr(Any Ptr, ProcPtr(sqlite3_bind_null))
        sqlite3Apis(7) = CPtr(Any Ptr, ProcPtr(sqlite3_bind_parameter_count))
        sqlite3Apis(8) = CPtr(Any Ptr, ProcPtr(sqlite3_bind_parameter_index))
        sqlite3Apis(9) = CPtr(Any Ptr, ProcPtr(sqlite3_bind_parameter_name))
        sqlite3Apis(10) = CPtr(Any Ptr, ProcPtr(sqlite3_bind_text))
        sqlite3Apis(11) = CPtr(Any Ptr, ProcPtr(sqlite3_bind_text16))
        sqlite3Apis(12) = CPtr(Any Ptr, ProcPtr(sqlite3_bind_value))
        sqlite3Apis(13) = CPtr(Any Ptr, ProcPtr(sqlite3_busy_handler))
        sqlite3Apis(14) = CPtr(Any Ptr, ProcPtr(sqlite3_busy_timeout))
        sqlite3Apis(15) = CPtr(Any Ptr, ProcPtr(sqlite3_changes))
        sqlite3Apis(16) = CPtr(Any Ptr, ProcPtr(sqlite3_close))
        sqlite3Apis(17) = CPtr(Any Ptr, ProcPtr(sqlite3_collation_needed))
        sqlite3Apis(18) = CPtr(Any Ptr, ProcPtr(sqlite3_collation_needed16))
        sqlite3Apis(19) = CPtr(Any Ptr, ProcPtr(sqlite3_column_blob))
        sqlite3Apis(20) = CPtr(Any Ptr, ProcPtr(sqlite3_column_bytes))
        sqlite3Apis(21) = CPtr(Any Ptr, ProcPtr(sqlite3_column_bytes16))
        sqlite3Apis(22) = CPtr(Any Ptr, ProcPtr(sqlite3_column_count))
        sqlite3Apis(25) = CPtr(Any Ptr, ProcPtr(sqlite3_column_decltype))
        sqlite3Apis(26) = CPtr(Any Ptr, ProcPtr(sqlite3_column_decltype16))
        sqlite3Apis(27) = CPtr(Any Ptr, ProcPtr(sqlite3_column_double))
        sqlite3Apis(28) = CPtr(Any Ptr, ProcPtr(sqlite3_column_int))
        sqlite3Apis(29) = CPtr(Any Ptr, ProcPtr(sqlite3_column_int64))
        sqlite3Apis(30) = CPtr(Any Ptr, ProcPtr(sqlite3_column_name))
        sqlite3Apis(31) = CPtr(Any Ptr, ProcPtr(sqlite3_column_name16))
        sqlite3Apis(36) = CPtr(Any Ptr, ProcPtr(sqlite3_column_text))
        sqlite3Apis(37) = CPtr(Any Ptr, ProcPtr(sqlite3_column_text16))
        sqlite3Apis(38) = CPtr(Any Ptr, ProcPtr(sqlite3_column_type))
        sqlite3Apis(39) = CPtr(Any Ptr, ProcPtr(sqlite3_column_value))
        sqlite3Apis(40) = CPtr(Any Ptr, ProcPtr(sqlite3_commit_hook))
        sqlite3Apis(41) = CPtr(Any Ptr, ProcPtr(sqlite3_complete))
        sqlite3Apis(42) = CPtr(Any Ptr, ProcPtr(sqlite3_complete16))
        sqlite3Apis(43) = CPtr(Any Ptr, ProcPtr(sqlite3_create_collation))
        sqlite3Apis(44) = CPtr(Any Ptr, ProcPtr(sqlite3_create_collation16))
        sqlite3Apis(45) = CPtr(Any Ptr, ProcPtr(sqlite3_create_function))
        sqlite3Apis(46) = CPtr(Any Ptr, ProcPtr(sqlite3_create_function16))
        sqlite3Apis(47) = CPtr(Any Ptr, ProcPtr(sqlite3_create_module))
        sqlite3Apis(48) = CPtr(Any Ptr, ProcPtr(sqlite3_data_count))
        sqlite3Apis(49) = CPtr(Any Ptr, ProcPtr(sqlite3_db_handle))
        sqlite3Apis(50) = CPtr(Any Ptr, ProcPtr(sqlite3_declare_vtab))
        sqlite3Apis(51) = CPtr(Any Ptr, ProcPtr(sqlite3_enable_shared_cache))
        sqlite3Apis(52) = CPtr(Any Ptr, ProcPtr(sqlite3_errcode))
        sqlite3Apis(53) = CPtr(Any Ptr, ProcPtr(sqlite3_errmsg))
        sqlite3Apis(54) = CPtr(Any Ptr, ProcPtr(sqlite3_errmsg16))
        sqlite3Apis(55) = CPtr(Any Ptr, ProcPtr(sqlite3_exec))
        sqlite3Apis(56) = CPtr(Any Ptr, ProcPtr(sqlite3_expired))
        sqlite3Apis(57) = CPtr(Any Ptr, ProcPtr(sqlite3_finalize))
        sqlite3Apis(58) = CPtr(Any Ptr, ProcPtr(sqlite3_free))
        sqlite3Apis(59) = CPtr(Any Ptr, ProcPtr(sqlite3_free_table))
        sqlite3Apis(60) = CPtr(Any Ptr, ProcPtr(sqlite3_get_autocommit))
        sqlite3Apis(61) = CPtr(Any Ptr, ProcPtr(sqlite3_get_auxdata))
        sqlite3Apis(62) = CPtr(Any Ptr, ProcPtr(sqlite3_get_table))
        sqlite3Apis(64) = CPtr(Any Ptr, ProcPtr(sqlite3_interrupt))
        sqlite3Apis(65) = CPtr(Any Ptr, ProcPtr(sqlite3_last_insert_rowid))
        sqlite3Apis(66) = CPtr(Any Ptr, ProcPtr(sqlite3_libversion))
        sqlite3Apis(67) = CPtr(Any Ptr, ProcPtr(sqlite3_libversion_number))
        sqlite3Apis(68) = CPtr(Any Ptr, ProcPtr(sqlite3_malloc))
        sqlite3Apis(69) = CPtr(Any Ptr, ProcPtr(sqlite3_mprintf))
        sqlite3Apis(70) = CPtr(Any Ptr, ProcPtr(sqlite3_open))
        sqlite3Apis(71) = CPtr(Any Ptr, ProcPtr(sqlite3_open16))
        sqlite3Apis(72) = CPtr(Any Ptr, ProcPtr(sqlite3_prepare))
        sqlite3Apis(73) = CPtr(Any Ptr, ProcPtr(sqlite3_prepare16))
        sqlite3Apis(74) = CPtr(Any Ptr, ProcPtr(sqlite3_profile))
        sqlite3Apis(75) = CPtr(Any Ptr, ProcPtr(sqlite3_progress_handler))
        sqlite3Apis(76) = CPtr(Any Ptr, ProcPtr(sqlite3_realloc))
        sqlite3Apis(77) = CPtr(Any Ptr, ProcPtr(sqlite3_reset))
        sqlite3Apis(78) = CPtr(Any Ptr, ProcPtr(sqlite3_result_blob))
        sqlite3Apis(79) = CPtr(Any Ptr, ProcPtr(sqlite3_result_double))
        sqlite3Apis(80) = CPtr(Any Ptr, ProcPtr(sqlite3_result_error))
        sqlite3Apis(81) = CPtr(Any Ptr, ProcPtr(sqlite3_result_error16))
        sqlite3Apis(82) = CPtr(Any Ptr, ProcPtr(sqlite3_result_int))
        sqlite3Apis(83) = CPtr(Any Ptr, ProcPtr(sqlite3_result_int64))
        sqlite3Apis(84) = CPtr(Any Ptr, ProcPtr(sqlite3_result_null))
        sqlite3Apis(85) = CPtr(Any Ptr, ProcPtr(sqlite3_result_text))
        sqlite3Apis(86) = CPtr(Any Ptr, ProcPtr(sqlite3_result_text16))
        sqlite3Apis(87) = CPtr(Any Ptr, ProcPtr(sqlite3_result_text16be))
        sqlite3Apis(88) = CPtr(Any Ptr, ProcPtr(sqlite3_result_text16le))
        sqlite3Apis(89) = CPtr(Any Ptr, ProcPtr(sqlite3_result_value))
        sqlite3Apis(90) = CPtr(Any Ptr, ProcPtr(sqlite3_rollback_hook))
        sqlite3Apis(91) = CPtr(Any Ptr, ProcPtr(sqlite3_set_authorizer))
        sqlite3Apis(92) = CPtr(Any Ptr, ProcPtr(sqlite3_set_auxdata))
        sqlite3Apis(93) = CPtr(Any Ptr, ProcPtr(sqlite3_snprintf))
        sqlite3Apis(94) = CPtr(Any Ptr, ProcPtr(sqlite3_step))
        sqlite3Apis(95) = CPtr(Any Ptr, ProcPtr(sqlite3_table_column_metadata))
        sqlite3Apis(96) = CPtr(Any Ptr, ProcPtr(sqlite3_thread_cleanup))
        sqlite3Apis(97) = CPtr(Any Ptr, ProcPtr(sqlite3_total_changes))
        sqlite3Apis(98) = CPtr(Any Ptr, ProcPtr(sqlite3_trace))
        sqlite3Apis(99) = CPtr(Any Ptr, ProcPtr(sqlite3_transfer_bindings))
        sqlite3Apis(100) = CPtr(Any Ptr, ProcPtr(sqlite3_update_hook))
        sqlite3Apis(101) = CPtr(Any Ptr, ProcPtr(sqlite3_user_data))
        sqlite3Apis(102) = CPtr(Any Ptr, ProcPtr(sqlite3_value_blob))
        sqlite3Apis(103) = CPtr(Any Ptr, ProcPtr(sqlite3_value_bytes))
        sqlite3Apis(104) = CPtr(Any Ptr, ProcPtr(sqlite3_value_bytes16))
        sqlite3Apis(105) = CPtr(Any Ptr, ProcPtr(sqlite3_value_double))
        sqlite3Apis(106) = CPtr(Any Ptr, ProcPtr(sqlite3_value_int))
        sqlite3Apis(107) = CPtr(Any Ptr, ProcPtr(sqlite3_value_int64))
        sqlite3Apis(108) = CPtr(Any Ptr, ProcPtr(sqlite3_value_numeric_type))
        sqlite3Apis(109) = CPtr(Any Ptr, ProcPtr(sqlite3_value_text))
        sqlite3Apis(110) = CPtr(Any Ptr, ProcPtr(sqlite3_value_text16))
        sqlite3Apis(111) = CPtr(Any Ptr, ProcPtr(sqlite3_value_text16be))
        sqlite3Apis(112) = CPtr(Any Ptr, ProcPtr(sqlite3_value_text16le))
        sqlite3Apis(113) = CPtr(Any Ptr, ProcPtr(sqlite3_value_type))
        sqlite3Apis(114) = CPtr(Any Ptr, ProcPtr(sqlite3_vmprintf))
        sqlite3Apis(115) = CPtr(Any Ptr, ProcPtr(sqlite3_overload_function))
        sqlite3Apis(116) = CPtr(Any Ptr, ProcPtr(sqlite3_prepare_v2))
        sqlite3Apis(117) = CPtr(Any Ptr, ProcPtr(sqlite3_prepare16_v2))
        sqlite3Apis(118) = CPtr(Any Ptr, ProcPtr(sqlite3_clear_bindings))
        sqlite3Apis(119) = CPtr(Any Ptr, ProcPtr(sqlite3_create_module_v2))
        sqlite3Apis(120) = CPtr(Any Ptr, ProcPtr(sqlite3_bind_zeroblob))
        sqlite3Apis(121) = CPtr(Any Ptr, ProcPtr(sqlite3_blob_bytes))
        sqlite3Apis(122) = CPtr(Any Ptr, ProcPtr(sqlite3_blob_close))
        sqlite3Apis(123) = CPtr(Any Ptr, ProcPtr(sqlite3_blob_open))
        sqlite3Apis(124) = CPtr(Any Ptr, ProcPtr(sqlite3_blob_read))
        sqlite3Apis(125) = CPtr(Any Ptr, ProcPtr(sqlite3_blob_write))
        sqlite3Apis(126) = CPtr(Any Ptr, ProcPtr(sqlite3_create_collation_v2))
        sqlite3Apis(127) = CPtr(Any Ptr, ProcPtr(sqlite3_file_control))
        sqlite3Apis(128) = CPtr(Any Ptr, ProcPtr(sqlite3_memory_highwater))
        sqlite3Apis(129) = CPtr(Any Ptr, ProcPtr(sqlite3_memory_used))
        sqlite3Apis(130) = CPtr(Any Ptr, ProcPtr(sqlite3_mutex_alloc))
        sqlite3Apis(131) = CPtr(Any Ptr, ProcPtr(sqlite3_mutex_enter))
        sqlite3Apis(132) = CPtr(Any Ptr, ProcPtr(sqlite3_mutex_free))
        sqlite3Apis(133) = CPtr(Any Ptr, ProcPtr(sqlite3_mutex_leave))
        sqlite3Apis(134) = CPtr(Any Ptr, ProcPtr(sqlite3_mutex_try))
        sqlite3Apis(135) = CPtr(Any Ptr, ProcPtr(sqlite3_open_v2))
        sqlite3Apis(136) = CPtr(Any Ptr, ProcPtr(sqlite3_release_memory))
        sqlite3Apis(137) = CPtr(Any Ptr, ProcPtr(sqlite3_result_error_nomem))
        sqlite3Apis(138) = CPtr(Any Ptr, ProcPtr(sqlite3_result_error_toobig))
        sqlite3Apis(139) = CPtr(Any Ptr, ProcPtr(sqlite3_sleep))
        sqlite3Apis(140) = CPtr(Any Ptr, ProcPtr(sqlite3_soft_heap_limit))
        sqlite3Apis(141) = CPtr(Any Ptr, ProcPtr(sqlite3_vfs_find))
        sqlite3Apis(142) = CPtr(Any Ptr, ProcPtr(sqlite3_vfs_register))
        sqlite3Apis(143) = CPtr(Any Ptr, ProcPtr(sqlite3_vfs_unregister))
        sqlite3Apis(144) = CPtr(Any Ptr, ProcPtr(sqlite3_threadsafe))
        sqlite3Apis(145) = CPtr(Any Ptr, ProcPtr(sqlite3_result_zeroblob))
        sqlite3Apis(146) = CPtr(Any Ptr, ProcPtr(sqlite3_result_error_code))
        sqlite3Apis(147) = CPtr(Any Ptr, ProcPtr(sqlite3_test_control))
        sqlite3Apis(148) = CPtr(Any Ptr, ProcPtr(sqlite3_randomness))
        sqlite3Apis(149) = CPtr(Any Ptr, ProcPtr(sqlite3_context_db_handle))
        sqlite3Apis(150) = CPtr(Any Ptr, ProcPtr(sqlite3_extended_result_codes))
        sqlite3Apis(151) = CPtr(Any Ptr, ProcPtr(sqlite3_limit))
        sqlite3Apis(152) = CPtr(Any Ptr, ProcPtr(sqlite3_next_stmt))
        sqlite3Apis(153) = CPtr(Any Ptr, ProcPtr(sqlite3_sql))
        sqlite3Apis(154) = CPtr(Any Ptr, ProcPtr(sqlite3_status))
        sqlite3Apis(155) = CPtr(Any Ptr, ProcPtr(sqlite3_backup_finish))
        sqlite3Apis(156) = CPtr(Any Ptr, ProcPtr(sqlite3_backup_init))
        sqlite3Apis(157) = CPtr(Any Ptr, ProcPtr(sqlite3_backup_pagecount))
        sqlite3Apis(158) = CPtr(Any Ptr, ProcPtr(sqlite3_backup_remaining))
        sqlite3Apis(159) = CPtr(Any Ptr, ProcPtr(sqlite3_backup_step))
        sqlite3Apis(160) = CPtr(Any Ptr, ProcPtr(sqlite3_compileoption_get))
        sqlite3Apis(161) = CPtr(Any Ptr, ProcPtr(sqlite3_compileoption_used))
        sqlite3Apis(162) = CPtr(Any Ptr, ProcPtr(sqlite3_create_function_v2))
        sqlite3Apis(163) = CPtr(Any Ptr, ProcPtr(sqlite3_db_config))
        sqlite3Apis(164) = CPtr(Any Ptr, ProcPtr(sqlite3_db_mutex))
        sqlite3Apis(165) = CPtr(Any Ptr, ProcPtr(sqlite3_db_status))
        sqlite3Apis(166) = CPtr(Any Ptr, ProcPtr(sqlite3_extended_errcode))
        sqlite3Apis(167) = CPtr(Any Ptr, ProcPtr(sqlite3_log))
        sqlite3Apis(168) = CPtr(Any Ptr, ProcPtr(sqlite3_soft_heap_limit64))
        sqlite3Apis(169) = CPtr(Any Ptr, ProcPtr(sqlite3_sourceid))
        sqlite3Apis(170) = CPtr(Any Ptr, ProcPtr(sqlite3_stmt_status))
        sqlite3Apis(171) = CPtr(Any Ptr, ProcPtr(sqlite3_strnicmp))
        sqlite3Apis(173) = CPtr(Any Ptr, ProcPtr(sqlite3_wal_autocheckpoint))
        sqlite3Apis(174) = CPtr(Any Ptr, ProcPtr(sqlite3_wal_checkpoint))
        sqlite3Apis(175) = CPtr(Any Ptr, ProcPtr(sqlite3_wal_hook))
        sqlite3Apis(176) = CPtr(Any Ptr, ProcPtr(sqlite3_blob_reopen))
        sqlite3Apis(177) = CPtr(Any Ptr, ProcPtr(sqlite3_vtab_config))
        sqlite3Apis(178) = CPtr(Any Ptr, ProcPtr(sqlite3_vtab_on_conflict))
        sqlite3Apis(179) = CPtr(Any Ptr, ProcPtr(sqlite3_close_v2))
        sqlite3Apis(180) = CPtr(Any Ptr, ProcPtr(sqlite3_db_filename))
        sqlite3Apis(181) = CPtr(Any Ptr, ProcPtr(sqlite3_db_readonly))
        sqlite3Apis(182) = CPtr(Any Ptr, ProcPtr(sqlite3_db_release_memory))
        sqlite3Apis(183) = CPtr(Any Ptr, ProcPtr(sqlite3_errstr))
        sqlite3Apis(184) = CPtr(Any Ptr, ProcPtr(sqlite3_stmt_busy))
        sqlite3Apis(185) = CPtr(Any Ptr, ProcPtr(sqlite3_stmt_readonly))
        sqlite3Apis(186) = CPtr(Any Ptr, ProcPtr(sqlite3_stricmp))
        sqlite3Apis(187) = CPtr(Any Ptr, ProcPtr(sqlite3_uri_boolean))
        sqlite3Apis(188) = CPtr(Any Ptr, ProcPtr(sqlite3_uri_int64))
        sqlite3Apis(189) = CPtr(Any Ptr, ProcPtr(sqlite3_uri_parameter))
        sqlite3Apis(190) = CPtr(Any Ptr, ProcPtr(sqlite3_vsnprintf))
        sqlite3Apis(191) = CPtr(Any Ptr, ProcPtr(sqlite3_wal_checkpoint_v2))
        sqlite3Apis(192) = CPtr(Any Ptr, ProcPtr(sqlite3_auto_extension))
        sqlite3Apis(193) = CPtr(Any Ptr, ProcPtr(sqlite3_bind_blob64))
        sqlite3Apis(194) = CPtr(Any Ptr, ProcPtr(sqlite3_bind_text64))
        sqlite3Apis(195) = CPtr(Any Ptr, ProcPtr(sqlite3_cancel_auto_extension))
        sqlite3Apis(196) = CPtr(Any Ptr, ProcPtr(sqlite3_load_extension))
        sqlite3Apis(197) = CPtr(Any Ptr, ProcPtr(sqlite3_malloc64))
        sqlite3Apis(198) = CPtr(Any Ptr, ProcPtr(sqlite3_msize))
        sqlite3Apis(199) = CPtr(Any Ptr, ProcPtr(sqlite3_realloc64))
        sqlite3Apis(200) = CPtr(Any Ptr, ProcPtr(sqlite3_reset_auto_extension))
        sqlite3Apis(201) = CPtr(Any Ptr, ProcPtr(sqlite3_result_blob64))
        sqlite3Apis(202) = CPtr(Any Ptr, ProcPtr(sqlite3_result_text64))
        sqlite3Apis(203) = CPtr(Any Ptr, ProcPtr(sqlite3_strglob))
        sqlite3Apis(204) = CPtr(Any Ptr, ProcPtr(sqlite3_value_dup))
        sqlite3Apis(205) = CPtr(Any Ptr, ProcPtr(sqlite3_value_free))
        sqlite3Apis(206) = CPtr(Any Ptr, ProcPtr(sqlite3_result_zeroblob64))
        sqlite3Apis(207) = CPtr(Any Ptr, ProcPtr(sqlite3_bind_zeroblob64))
        sqlite3Apis(208) = CPtr(Any Ptr, ProcPtr(sqlite3_value_subtype))
        sqlite3Apis(209) = CPtr(Any Ptr, ProcPtr(sqlite3_result_subtype))
        sqlite3Apis(210) = CPtr(Any Ptr, ProcPtr(sqlite3_status64))
        sqlite3Apis(211) = CPtr(Any Ptr, ProcPtr(sqlite3_strlike))
        sqlite3Apis(212) = CPtr(Any Ptr, ProcPtr(sqlite3_db_cacheflush))
        sqlite3Apis(213) = CPtr(Any Ptr, ProcPtr(sqlite3_system_errno))
        sqlite3Apis(214) = CPtr(Any Ptr, ProcPtr(sqlite3_trace_v2))
        sqlite3Apis(215) = CPtr(Any Ptr, ProcPtr(sqlite3_expanded_sql))
        sqlite3Apis(216) = CPtr(Any Ptr, ProcPtr(sqlite3_set_last_insert_rowid))
        sqlite3Apis(217) = CPtr(Any Ptr, ProcPtr(sqlite3_prepare_v3))
        sqlite3Apis(218) = CPtr(Any Ptr, ProcPtr(sqlite3_prepare16_v3))
        sqlite3Apis(219) = CPtr(Any Ptr, ProcPtr(sqlite3_bind_pointer))
        sqlite3Apis(220) = CPtr(Any Ptr, ProcPtr(sqlite3_result_pointer))
        sqlite3Apis(221) = CPtr(Any Ptr, ProcPtr(sqlite3_value_pointer))
        sqlite3Apis(222) = CPtr(Any Ptr, ProcPtr(sqlite3_vtab_nochange))
        sqlite3Apis(223) = CPtr(Any Ptr, ProcPtr(sqlite3_value_nochange))
        sqlite3Apis(224) = CPtr(Any Ptr, ProcPtr(sqlite3_vtab_collation))
        sqlite3Apis(225) = CPtr(Any Ptr, ProcPtr(sqlite3_keyword_count))
        sqlite3Apis(226) = CPtr(Any Ptr, ProcPtr(sqlite3_keyword_name))
        sqlite3Apis(227) = CPtr(Any Ptr, ProcPtr(sqlite3_keyword_check))
        sqlite3Apis(228) = CPtr(Any Ptr, ProcPtr(sqlite3_str_new))
        sqlite3Apis(229) = CPtr(Any Ptr, ProcPtr(sqlite3_str_finish))
        sqlite3Apis(230) = CPtr(Any Ptr, ProcPtr(sqlite3_str_appendf))
        sqlite3Apis(231) = CPtr(Any Ptr, ProcPtr(sqlite3_str_vappendf))
        sqlite3Apis(232) = CPtr(Any Ptr, ProcPtr(sqlite3_str_append))
        sqlite3Apis(233) = CPtr(Any Ptr, ProcPtr(sqlite3_str_appendall))
        sqlite3Apis(234) = CPtr(Any Ptr, ProcPtr(sqlite3_str_appendchar))
        sqlite3Apis(235) = CPtr(Any Ptr, ProcPtr(sqlite3_str_reset))
        sqlite3Apis(236) = CPtr(Any Ptr, ProcPtr(sqlite3_str_errcode))
        sqlite3Apis(237) = CPtr(Any Ptr, ProcPtr(sqlite3_str_length))
        sqlite3Apis(238) = CPtr(Any Ptr, ProcPtr(sqlite3_str_value))
        sqlite3Apis(239) = CPtr(Any Ptr, ProcPtr(sqlite3_create_window_function))
        sqlite3Apis(241) = CPtr(Any Ptr, ProcPtr(sqlite3_stmt_isexplain))
        sqlite3Apis(242) = CPtr(Any Ptr, ProcPtr(sqlite3_value_frombind))
        sqlite3Apis(243) = CPtr(Any Ptr, ProcPtr(sqlite3_drop_modules))
        sqlite3Apis(244) = CPtr(Any Ptr, ProcPtr(sqlite3_hard_heap_limit64))
        sqlite3Apis(245) = CPtr(Any Ptr, ProcPtr(sqlite3_uri_key))
        sqlite3Apis(246) = CPtr(Any Ptr, ProcPtr(sqlite3_filename_database))
        sqlite3Apis(247) = CPtr(Any Ptr, ProcPtr(sqlite3_filename_journal))
        sqlite3Apis(248) = CPtr(Any Ptr, ProcPtr(sqlite3_filename_wal))
        sqlite3Apis(249) = CPtr(Any Ptr, ProcPtr(sqlite3_create_filename))
        sqlite3Apis(250) = CPtr(Any Ptr, ProcPtr(sqlite3_free_filename))
        sqlite3Apis(251) = CPtr(Any Ptr, ProcPtr(sqlite3_database_file_object))
        sqlite3Apis(252) = CPtr(Any Ptr, ProcPtr(sqlite3_txn_state))
        sqlite3Apis(253) = CPtr(Any Ptr, ProcPtr(sqlite3_changes64))
        sqlite3Apis(254) = CPtr(Any Ptr, ProcPtr(sqlite3_total_changes64))
        sqlite3Apis(255) = CPtr(Any Ptr, ProcPtr(sqlite3_autovacuum_pages))
        sqlite3Apis(256) = CPtr(Any Ptr, ProcPtr(sqlite3_error_offset))
        sqlite3Apis(257) = CPtr(Any Ptr, ProcPtr(sqlite3_vtab_rhs_value))
        sqlite3Apis(258) = CPtr(Any Ptr, ProcPtr(sqlite3_vtab_distinct))
        sqlite3Apis(259) = CPtr(Any Ptr, ProcPtr(sqlite3_vtab_in))
        sqlite3Apis(260) = CPtr(Any Ptr, ProcPtr(sqlite3_vtab_in_first))
        sqlite3Apis(261) = CPtr(Any Ptr, ProcPtr(sqlite3_vtab_in_next))
#ifndef SQLITE_OMIT_DESERIALIZE
        sqlite3Apis(262) = CPtr(Any Ptr, ProcPtr(sqlite3_deserialize))
#endif
#ifndef SQLITE_OMIT_DESERIALIZE
        sqlite3Apis(263) = CPtr(Any Ptr, ProcPtr(sqlite3_serialize))
#endif
        sqlite3Apis(264) = CPtr(Any Ptr, ProcPtr(sqlite3_db_name))
        sqlite3Apis(265) = CPtr(Any Ptr, ProcPtr(sqlite3_value_encoding))
        sqlite3Apis(266) = CPtr(Any Ptr, ProcPtr(sqlite3_is_interrupted))
        sqlite3Apis(267) = CPtr(Any Ptr, ProcPtr(sqlite3_stmt_explain))
        sqlite3Apis(268) = CPtr(Any Ptr, ProcPtr(sqlite3_get_clientdata))
        sqlite3Apis(269) = CPtr(Any Ptr, ProcPtr(sqlite3_set_clientdata))
        sqlite3Apis(270) = CPtr(Any Ptr, ProcPtr(sqlite3_setlk_timeout))
        sqlite3Apis(271) = CPtr(Any Ptr, ProcPtr(sqlite3_set_errmsg))
        sqlite3Apis(272) = CPtr(Any Ptr, ProcPtr(sqlite3_db_status64))
        sqlite3Apis(273) = CPtr(Any Ptr, ProcPtr(sqlite3_str_truncate))
        sqlite3Apis(274) = CPtr(Any Ptr, ProcPtr(sqlite3_str_free))
        sqlite3Apis(277) = CPtr(Any Ptr, ProcPtr(sqlite3_incomplete))
        sqlite3Apis(278) = CPtr(Any Ptr, ProcPtr(sqlite3_result_str))
        sqlite3ApiTableReady = 1
    End If
    If pInitializationMutex <> 0 Then sqlite3_mutex_leave(pInitializationMutex)
    Return SQLITE_OK
End Function
#endif

/' end of sqlite3_extension_api_table.bi '/
