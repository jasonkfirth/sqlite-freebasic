# SQLite FreeBASIC port build rules
#
# Build only the FreeBASIC source in this directory. The main SQLite build
# does not include this tree until the port has enough API coverage to link
# existing clients.

FBC ?= fbc
CC ?= cc
PYTHON ?= python3
THREADSAFE ?= 1
FEATURE_DEFINES ?=
BODY_TYPE_MAPS ?=
BODY_OPTIONS ?=
C2FB_BODY_OPTIONS = $(BODY_TYPE_MAPS) $(BODY_OPTIONS)
FB_DEFINE_FLAGS ?=
MEMDEBUG_BACKTRACE_FLAGS ?= $(if $(shell getconf GNU_LIBC_VERSION 2>/dev/null),-d SQLITE3_FB_GLIBC_BACKTRACE=1)
OS_KV_OPTIONAL ?= 0
INCLUDE_EXISTING ?= 0
TARGET ?= build/libsqlite3-fb.so
ifeq ($(THREADSAFE),0)
THREAD_FLAGS =
else
THREAD_FLAGS = -mt
endif
GEN_DIR = build/generated
CODEGEN = $(GEN_DIR)/sqlite_codegen
CANDIDATE_DIR ?= build/candidates
LOOSE_CANDIDATE_DIR ?= build/candidates-loose
SOURCES = sqlite3_metadata.bas sqlite3_compile_options.bas sqlite3_complete.bas sqlite3_tokenize.bas sqlite3_parser_tables.bas sqlite3_parser_driver.bas sqlite3_parser_semantics.bas sqlite3_parser_cleanup.bas sqlite3_prepare.bas sqlite3_exec.bas sqlite3_pragma.bas sqlite3_table.bas sqlite3_expr.bas sqlite3_cte.bas sqlite3_walker.bas sqlite3_window.bas sqlite3_delete_helpers.bas sqlite3_values.bas sqlite3_affinity.bas sqlite3_functions.bas sqlite3_json_string.bas sqlite3_json_values.bas sqlite3_json_hex.bas sqlite3_json_parse_state.bas sqlite3_json_text_scan.bas sqlite3_json_labels.bas sqlite3_json_blob.bas sqlite3_json_payload.bas sqlite3_json_validate.bas sqlite3_json_text_parse.bas sqlite3_json_parse_arg.bas sqlite3_json_return.bas sqlite3_json_valid.bas sqlite3_json_query.bas sqlite3_json_blob_text.bas sqlite3_select.bas sqlite3_select_constant_propagation.bas sqlite3_build.bas sqlite3_transaction.bas sqlite3_alter.bas sqlite3_insert.bas sqlite3_analyze.bas sqlite3_initialize.bas sqlite3_config.bas sqlite3_log.bas sqlite3_collation.bas sqlite3_connection.bas sqlite3_busy.bas sqlite3_interrupt.bas sqlite3_filename.bas sqlite3_uri.bas sqlite3_schema.bas sqlite3_shadow_tables.bas sqlite3_trigger_helpers.bas sqlite3_limit.bas sqlite3_db_status.bas sqlite3_memory.bas sqlite3_mutex.bas sqlite3_random.bas sqlite3_threads.bas sqlite3_btmutex.bas sqlite3_fault.bas sqlite3_status.bas sqlite3_db_memory.bas sqlite3_rowset.bas sqlite3_numeric.bas sqlite3_column.bas sqlite3_util_numeric.bas sqlite3_where_helpers.bas sqlite3_varint.bas sqlite3_fp.bas sqlite3_printf.bas sqlite3_vdbe_affinity.bas sqlite3_vdbe_compare.bas sqlite3_vdbe_serial.bas sqlite3_vdbe_record.bas sqlite3_vdbe_mem_text.bas sqlite3_vdbe_api.bas sqlite3_vdbe_mem.bas sqlite3_result.bas sqlite3_vdbe_core.bas sqlite3_vdbe_cursor.bas sqlite3_vdbe_exec.bas sqlite3_vdbe_trace.bas sqlite3_vdbe_stmt.bas sqlite3_utf.bas sqlite3_string_compare.bas sqlite3_string_utils.bas sqlite3_straccum.bas sqlite3_bitvec.bas sqlite3_hash.bas sqlite3_errors.bas sqlite3_pcache.bas sqlite3_os.bas sqlite3_os_unix.bas sqlite3_memjournal.bas sqlite3_memdb.bas sqlite3_pager.bas sqlite3_wal.bas sqlite3_btree.bas sqlite3_backup.bas
SOURCES += sqlite3_date_helpers.bas
SOURCES += sqlite3_db_config.bas
SOURCES += sqlite3_error_names.bas
SOURCES += sqlite3_test_control.bas
SOURCES += sqlite3_c2fb_intrinsics.bas
SOURCES += sqlite3_btree_integrity_helpers.bas
SOURCES += sqlite3_upsert.bas
SOURCES += sqlite3_date_modifier.bas
SOURCES += sqlite3_date_sqlfunc.bas
SOURCES += sqlite3_snapshot.bas
SOURCES += sqlite3_notify.bas
SOURCES += sqlite3_builtin_extensions.bas
SOURCES += sqlite3_hooks.bas
SOURCES += sqlite3_where_scan.bas
SOURCES += sqlite3_where_clause.bas
SOURCES += sqlite3_window_names.bas
SOURCES += sqlite3_iotrace.bas
SOURCES += sqlite3_vdbe_explain.bas sqlite3_treeview.bas sqlite3_opcode_names.bas
SOURCES += sqlite3_json_optional_callbacks.bas
SOURCES += sqlite3_vdbesort_init.bas
SOURCES += sqlite3_vdbesort_debug.bas
SOURCES += sqlite3_vtab_config.bas
SOURCES += sqlite3_vtab_overload.bas
SOURCES += sqlite3_memsys5.bas
SOURCES += sqlite3_memsys3.bas
SOURCES += sqlite3_memdebug.bas
SOURCES += sqlite3_debug_assert.bas
# C2FB-generated engine batches that passed per-procedure and grouped compiles.
SOURCES += sqlite3_pragma_data.bas sqlite3_pragma_helpers.bas
SOURCES += sqlite3_std_types.bas
SOURCES += $(wildcard sqlite3_bulk*.bas)

# SQLite omits both the memory VFS and the serialize/deserialize APIs together.
ifneq ($(findstring SQLITE_OMIT_DESERIALIZE,$(FB_DEFINE_FLAGS)),)
SOURCES := $(filter-out sqlite3_memdb.bas sqlite3_bulk_memdb_serialization.bas sqlite3_bulk36_memdb.bas sqlite3_bulk39_memdb.bas,$(SOURCES))
endif

# Windows VFS helpers are preprocessed out of Unix builds.
SOURCES += sqlite3_os_win_helpers.bas sqlite3_os_win_memory.bas
ifeq ($(OS_KV_OPTIONAL),1)
SOURCES += sqlite3_os_kv_optional.bas
endif
GENERATED_HEADERS = sqlite3_tokens.bi sqlite3_keyword_data.bi sqlite3_character_classes.bi sqlite3_global_data.bi sqlite3_parser_tables.bi sqlite3_parser_rule_ids.bi sqlite3_opcodes.bi sqlite3_api_constants.bi sqlite3_fp10_tables.bi sqlite3_api_declarations.bi sqlite3_internal_api_declarations.bi sqlite3_extension_api_table.bi sqlite3_pragma_data.bi sqlite3_std_types.bi

.PHONY: all clean check-interrupt regen-generated regen-api-declarations reconcile-function-status regen-extension-api-table regen-pragma-data bulk-candidates bulk-candidate-files bulk-candidate-files-loose check-bulk-candidates bulk-candidates-loose check-bulk-candidates-loose check-bulk-candidate-files-loose

all: $(TARGET)

$(TARGET): $(SOURCES) sqlite3_opcode_names.bas $(GENERATED_HEADERS) sqlite3_constants.bi sqlite3_types.bi sqlite3_mutex.bi sqlite3_status.bi sqlite3_db_types.bi sqlite3_stat4_types.bi sqlite3_percentile_types.bi sqlite3_parser_types.bi sqlite3_parser_token.bi sqlite3_expr_types.bi sqlite3_walker.bi sqlite3_window_state.bi sqlite3_fkey_types.bi sqlite3_schema_types.bi sqlite3_where_types.bi sqlite3_resolve_types.bi sqlite3_agginfo_types.bi sqlite3_walk_contexts.bi sqlite3_hash_types.bi sqlite3_bitvec.bi sqlite3_rowset.bi sqlite3_numeric.bi sqlite3_util_numeric.bi sqlite3_varint.bi sqlite3_fp.bi sqlite3_fault.bi sqlite3_vdbe_affinity.bi sqlite3_vdbe_compare.bi sqlite3_vdbe_serial.bi sqlite3_vdbe_record.bi sqlite3_vdbe_api.bi sqlite3_vdbe_mem_text.bi sqlite3_vdbe_mem_types.bi sqlite3_vdbe_core.bi sqlite3_vdbe_cursor.bi sqlite3_treeview_types.bi sqlite3_vdbesort_types.bi sqlite3_dbstat_types.bi sqlite3_result.bi sqlite3_straccum.bi sqlite3_json_string.bi sqlite3_json_values.bi sqlite3_json_parse.bi sqlite3_json_query.bi sqlite3_json_vtab_types.bi sqlite3_pcache.bi sqlite3_pcache1_types.bi sqlite3_vfs.bi sqlite3_os_kv_types.bi sqlite3_memjournal.bi sqlite3_memdb.bi sqlite3_pager.bi sqlite3_btree.bi sqlite3_integrity_types.bi sqlite3_insert_helpers.bi sqlite3_backup_types.bi sqlite3_memory_methods.bi sqlite3_date_types.bi sqlite3_vtab_types.bi sqlite3_carray_types.bi sqlite3_bytecode_vtab_types.bi sqlite3_pragma_types.bi sqlite3_pragma_helpers.bi sqlite3_std_types.bi sqlite3_collation.bi sqlite3.map
	mkdir -p $(dir $@)
	$(FBC) $(THREAD_FLAGS) -dll -d SQLITE_THREADSAFE=$(THREADSAFE) $(FB_DEFINE_FLAGS) \
		$(MEMDEBUG_BACKTRACE_FLAGS) \
		-Wl --version-script,sqlite3.map -x $@ $(SOURCES)

# The process-wide directory globals are declared through this shared include.
$(TARGET): sqlite3_process_globals.bi sqlite3_os_test.bi sqlite3_mutex_windows.bi sqlite3_os_win_types.bi

$(TARGET): sqlite3_os_unix_types.bi

$(TARGET): sqlite3_vdbe_test.bi

$(TARGET): sqlite3_os_win_syscall_types.bi sqlite3_os_win_syscall_dispatch.bi sqlite3_os_win_syscall_table.bi

$(TARGET): sqlite3_win_exception_types.bi

$(TARGET): sqlite3_memdb_types.bi

$(TARGET): sqlite3_memsys3_types.bi

$(TARGET): sqlite3_dbpage_types.bi

$(TARGET): sqlite3_bulk_feature_dbpage.bas

$(TARGET): sqlite3_iotrace.bi

$(TARGET): sqlite3_sqllog.bi

regen-generated:
	mkdir -p $(GEN_DIR)
	$(CC) -O2 -o $(GEN_DIR)/lemon ../tool/lemon.c
	$(GEN_DIR)/lemon -q -d$(abspath $(GEN_DIR)) \
		-T$(abspath ../tool/lempar.c) $(abspath ../src/parse.y)
	$(CC) -O2 -o $(GEN_DIR)/mkkeywordhash ../tool/mkkeywordhash.c
	cd $(GEN_DIR) && ./mkkeywordhash > keywordhash.h
	$(FBC) -w all -x $(CODEGEN) ../fb_tools/sqlite_codegen/sqlite_codegen.bas
	$(CODEGEN) tokens $(GEN_DIR)/parse.h sqlite3_tokens.bi
	$(CODEGEN) keywords $(GEN_DIR)/keywordhash.h sqlite3_keyword_data.bi
	$(CODEGEN) classes ../src/tokenize.c sqlite3_character_classes.bi
	$(CODEGEN) global-data ../src/global.c sqlite3_global_data.bi
	$(CODEGEN) parser-tables $(GEN_DIR)/parse.c sqlite3_parser_tables.bi
	$(CODEGEN) parser-rule-ids $(GEN_DIR)/parse.c sqlite3_parser_rule_ids.bi \
		sqlite3_parser_semantics.bas PORTING_PARSER_RULES.csv
	cat $(GEN_DIR)/parse.h ../src/vdbe.c | tclsh ../tool/mkopcodeh.tcl > $(GEN_DIR)/opcodes.h
	$(CODEGEN) opcodes $(GEN_DIR)/opcodes.h sqlite3_opcodes.bi
	$(CODEGEN) opcode-names $(GEN_DIR)/opcodes.h sqlite3_opcode_names.bas

regen-api-declarations:
	$(MAKE) -C ../fb_tools/c2fb FBC='$(FBC)' converter
	../fb_tools/c2fb/build/c2fb ../src/sqlite.h.in sqlite3_api_declarations.bi
	../fb_tools/c2fb/build/c2fb defines ../src/sqlite.h.in sqlite3_api_constants.bi
	../fb_tools/c2fb/build/c2fb fp-tables ../src/util.c sqlite3_fp10_tables.bi
	../fb_tools/c2fb/build/c2fb ../src/sqliteInt.h sqlite3_internal_api_declarations.bi

reconcile-function-status:
	$(MAKE) -C ../fb_tools/c2fb FBC='$(FBC)' converter
	../fb_tools/c2fb/build/c2fb reconcile-functions PORTING_FUNCTIONS.csv .

bulk-candidates: regen-generated
	rm -rf "$(CANDIDATE_DIR)"
	mkdir -p "$(CANDIDATE_DIR)"
	$(MAKE) -C ../fb_tools/c2fb FBC='$(FBC)' converter
	../fb_tools/c2fb/build/c2fb translate-preprocessed-tree ../src $(GEN_DIR) '$(CANDIDATE_DIR)' . '$(CC)' '$(THREADSAFE)' 0 '$(FEATURE_DEFINES)' '$(INCLUDE_EXISTING)' $(C2FB_BODY_OPTIONS)
	../fb_tools/c2fb/build/c2fb reconcile-functions PORTING_FUNCTIONS.csv .
	../fb_tools/c2fb/build/c2fb api-routines $(CANDIDATE_DIR)/.c2fb_preprocessed/loadext.i PORTING_FUNCTIONS.csv sqlite3_bulk_loadext.bas sqlite3_extension_api_table.bi

bulk-candidate-files: regen-generated
	rm -rf "$(CANDIDATE_DIR)"
	mkdir -p "$(CANDIDATE_DIR)"
	$(MAKE) -C ../fb_tools/c2fb FBC='$(FBC)' converter
	../fb_tools/c2fb/build/c2fb translate-preprocessed-files ../src $(GEN_DIR) '$(CANDIDATE_DIR)' . '$(CC)' '$(THREADSAFE)' 0 '$(FEATURE_DEFINES)' '$(INCLUDE_EXISTING)' '$(SOURCE_FILES)' $(C2FB_BODY_OPTIONS)
	../fb_tools/c2fb/build/c2fb reconcile-functions PORTING_FUNCTIONS.csv .

bulk-candidate-files-loose: regen-generated
	rm -rf "$(LOOSE_CANDIDATE_DIR)"
	mkdir -p "$(LOOSE_CANDIDATE_DIR)"
	$(MAKE) -C ../fb_tools/c2fb FBC='$(FBC)' converter
	../fb_tools/c2fb/build/c2fb translate-preprocessed-files ../src $(GEN_DIR) '$(LOOSE_CANDIDATE_DIR)' . '$(CC)' '$(THREADSAFE)' 1 '$(FEATURE_DEFINES)' '$(INCLUDE_EXISTING)' '$(SOURCE_FILES)' $(C2FB_BODY_OPTIONS)
	../fb_tools/c2fb/build/c2fb reconcile-functions PORTING_FUNCTIONS.csv .

check-bulk-candidates: bulk-candidates
	$(MAKE) -C ../fb_tools/c2fb check-candidates FBC='$(FBC)' THREADSAFE='$(THREADSAFE)' \
		CANDIDATE_DIR='$(abspath $(CANDIDATE_DIR))' FB_SOURCE_DIR='$(abspath .)'

bulk-candidates-loose: regen-generated
	rm -rf "$(LOOSE_CANDIDATE_DIR)"
	mkdir -p "$(LOOSE_CANDIDATE_DIR)"
	$(MAKE) -C ../fb_tools/c2fb FBC='$(FBC)' converter
	../fb_tools/c2fb/build/c2fb translate-preprocessed-tree ../src $(GEN_DIR) \
		'$(LOOSE_CANDIDATE_DIR)' . '$(CC)' '$(THREADSAFE)' 1 '$(FEATURE_DEFINES)' '$(INCLUDE_EXISTING)' $(C2FB_BODY_OPTIONS)
	$(CODEGEN) pragma-table $(LOOSE_CANDIDATE_DIR)/.c2fb_preprocessed/pragma.i \
		sqlite3_pragma_data.bi sqlite3_pragma_data.bas
	../fb_tools/c2fb/build/c2fb reconcile-functions PORTING_FUNCTIONS.csv .
	../fb_tools/c2fb/build/c2fb api-routines $(LOOSE_CANDIDATE_DIR)/.c2fb_preprocessed/loadext.i PORTING_FUNCTIONS.csv sqlite3_bulk_loadext.bas sqlite3_extension_api_table.bi

regen-extension-api-table: bulk-candidates-loose

regen-pragma-data: bulk-candidates-loose

check-bulk-candidates-loose: bulk-candidates-loose
	$(MAKE) -C ../fb_tools/c2fb check-candidates FBC='$(FBC)' THREADSAFE='$(THREADSAFE)' \
		CANDIDATE_DIR='$(abspath $(LOOSE_CANDIDATE_DIR))' FB_SOURCE_DIR='$(abspath .)'

check-bulk-candidate-files-loose: bulk-candidate-files-loose
	$(MAKE) -C ../fb_tools/c2fb check-candidates FBC='$(FBC)' THREADSAFE='$(THREADSAFE)' \
		CANDIDATE_DIR='$(abspath $(LOOSE_CANDIDATE_DIR))' FB_SOURCE_DIR='$(abspath .)'

check-interrupt:
	$(PYTHON) tests/test_interrupt_progress.py --fbc '$(FBC)' --make '$(MAKE)' \
		--threadsafe '$(THREADSAFE)'

clean:
	rm -rf build

# end of fb_src/Makefile
