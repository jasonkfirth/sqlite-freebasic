> Archived development notes. This chronology includes repeated runs, intermediate
> failures, and temporary fixtures. Use the current [qualification report](../QUALIFICATION.md)
> and the checked-in [test runner](../tests/run_upstream.sh) for reproducible results.

# SQLite FreeBASIC port

`fb_src/` is the FreeBASIC implementation tree for the SQLite engine.
`PORTING_INVENTORY.csv` tracks 211,790 lines of non-test-support sources and
build inputs before exclusions. The shell template (14,931 lines) and Tcl test
adapter (4,665 lines) stay outside the engine port, leaving 192,194 upstream
engine and public-ABI lines in scope. The inventory separately lists all 48 C
test-support files as out of scope, so test code remains in its original
language. The port proceeds in subsystems while preserving SQLite's C ABI.

`PORTING_FUNCTIONS.csv` tracks source-definition rows. A C function name can
appear more than once when mutually exclusive implementation files define it,
such as the MEM0, MEM1, and MEM2 allocators or the Unix and Windows VFS. Name
matching is an initial reconciliation signal; rows marked `Needs variant
port` identify alternate implementations that a same-named FreeBASIC body does
not cover. `FB body present` records source coverage, not full behavioral
parity.

The current index has bodies for 3,243 of 3,243 in-scope source definitions
(100% by row count) and 124,545 of 124,545 indexed function lines (100%).
All indexed function definitions now have FreeBASIC bodies.
That is roughly 64.8% of the 192,194 in-scope engine and public-ABI source
lines, measured as indexed function-definition lines divided by total
in-scope lines. This ratio is not a completeness score: the remaining lines
include declarations, macros, static data, comments, and generated interfaces.
Seven definitions under upstream `#if 0` are marked `Disabled upstream`; 13 of
3,263 indexed definitions are out of scope. Run
`make -C fb_src reconcile-function-status` to reconcile ordinary name matches.
The command preserves custom statuses such as `Needs variant port` and
`Disabled upstream`. Regenerate the index with
`c2fb functions ../src PORTING_FUNCTIONS.csv` when the SQLite source set
changes, then reconcile it again and re-audit duplicated names.

## Runtime checkpoint (2026-10-16)

The default and `SQLITE_ENABLE_PREUPDATE_HOOK` libraries build. The unchanged
upstream `test/hook.test` passes 103/103, including ALTER TABLE defaults,
WITHOUT ROWID updates, and nested triggers. A temporary Tcl bridge shim maps
extended code 531 to the symbolic name expected by `hook-3.6b`; a direct C ABI
probe confirms `sqlite3ErrName(531)` returns `SQLITE_CONSTRAINT_COMMITHOOK`.
The upstream test source remains unchanged.

`sqlite3BtreeOpen()` now applies `sqlite3TempInMemory()` when it opens an
unnamed TEMP database, so `PRAGMA temp_store` controls the TEMP pager as in
upstream. `sqlite3PagerOpen()` leaves journal mode OFF when an in-memory pager
was opened with journaling omitted, preserving the debug pager invariant. The
release, debug, and omit-deserialize temp-store probes pass. The unchanged
`pragma.test` TEMP-store checks pass (9.1.1, 9.2.1, and 9.3.1). `sqlite3VdbeExec`
follows the `OP_Init.P3` corruption target when `OP_Column` encounters a
malformed record, so `pragma-24.2` also passes. Right-edge B-tree insertion now
uses `balance_quick()` when the expanded root has no separator cells, matching
upstream page allocation. The 1,024-row insertion workload now matches the C
reference page count at every doubling step. The unchanged `pragma.test` passes
all 127 cases enabled by the FB Tcl bridge, with no tracked allocations. The
upstream test source remains unchanged.

This pass corrected four FreeBASIC runtime paths: parser lookaside accounting
for ALTER ADD schema reload, default semantic copies for multi-token Lemon
rules, rename-token preservation for identifier and expression-list names,
and `OP_SetCookie` handling when P4 is unused. `OP_ParseSchema` also permits an
unopened TEMP B-tree, `OP_Column` loads P4_MEM defaults for older rows, and
B-tree insertion preserves an exact-match index cursor during multi-row
WITHOUT ROWID updates. The source routines already had translated bodies, so
C2FB required no change for these repairs.

The unchanged upstream `hook.test` passes 103/103. `alter3.test` passes 43/43
with temporary `hexio_read` and `hexio_get_int` fixture helpers, and
`alter4.test` passes 42/42. `altercol.test` passes 257/257 with its VTab cases
enabled through a temporary schema-only echo module; the upstream test file is
unchanged. All tracked allocations are freed at shutdown. Default-profile C
probes verify ALTER defaults, `PRAGMA schema_version`, and multi-row WITHOUT
ROWID updates.

A direct C ABI smoke now exercises a three-row `:memory:` table with an
integer primary key, integer and text columns, and an index on the integer
column. It verifies table and forced-index scans, a range scan ordered by the
index while reading a non-indexed text column, NULL lookup, `COUNT(*)`, update,
delete, rollback, statement finalization, and connection close. All statements
return `SQLITE_DONE`, `sqlite3_close` returns `SQLITE_OK`, and lookaside usage
returns to zero after each finalized statement. The release and `SQLITE_DEBUG`
libraries pass this smoke.

`make -C fb_src check-interrupt` builds the library in temporary storage and
checks that a progress callback calling `sqlite3_interrupt()` stops a long
SQL preparation with `SQLITE_INTERRUPT`. The test removes its library, client,
and executable when it finishes. Pass `THREADSAFE=0` to check the no-op mutex
profile as well.

A second direct C ABI smoke uses a file-backed database. It creates parent and
child tables plus an index, inserts three rows, and checks ordered reads,
plain and aggregate `GROUP BY`, `LEFT JOIN` with `COUNT` and `SUM`, an `IN`
subquery, a correlated scalar subquery with `LIMIT`, scalar aggregate subqueries
using `COUNT(*)` and `MAX`, and close/reopen. The printed rows match the fixture
values, all statements return `SQLITE_DONE`, and both release and `SQLITE_DEBUG`
libraries pass. The debug profile marks persistent B-trees sharable, so this
also exercises recursive B-tree entry and table-lock cleanup. It does not test
two simultaneous connections using shared cache.

Function-expression cleanup previously leaked the argument list and its
expression because `sqlite3ExprAlloc` marked every new node `EP_Leaf`. The
allocator now leaves flags zeroed, matching SQLite; constructors mark leaf
nodes only where required. Release and debug C ABI probes now pass scalar and
aggregate functions with arguments, with lookaside usage returning to zero
after each finalized statement. UTF-16 `group_concat` returns `a:b` and closes
the connection successfully. This was an existing port bug, not a missing
routine, so no C2FB or FBC change was needed.

This caught several integration errors in existing bodies: index cursors were
rejected by the deferred-seek check; cursor cleanup skipped sorter destruction;
index metadata left `colNotIdxed` unset and misclassified non-covering scans;
aggregate helpers repeated `sqlite3ArrayAllocate` and `sqlite3ExprAlloc` calls,
leaving empty aggregate slots and an orphan expression; and ROLLBACK encoded a
FreeBASIC true value of -1 instead of the C opcode operand 1. The pager debug
assertions also exposed the missing `changeCountDone = tempFile` initialization
for temporary and in-memory pagers. These repairs are in the SQLite port; no
additional function bodies were needed. The aggregate allocation duplication
came from older generated module output; the C2FB source was left unchanged in
this run.

The file-backed probe also exposed integration issues in the existing B-tree
and aggregate bodies. Shared B-tree wrappers and cursor creation now use the
recursive `sqlite3BtreeEnter`/`sqlite3BtreeLeave` path, and transaction end
removes embedded schema/table-lock entries while maintaining shared transaction
counts. Cursor allocation no longer rejects an undefined VDBE cursor cell just
because its `db` field is unset. The older generated aggregate helper emitted
one `sqlite3VdbeAddOp1(OP_If, ...)` call twice; the integrated body now emits
and patches one instruction. No converter source or test source was changed.

The scalar aggregate probe exposed a VDBE finalization error: negative `P2`
operands on non-jump opcodes were being treated as jump-label references.
`resolveP2Values` now resolves negative operands only for opcodes marked
`OPFLG_JUMP`, preserving negative immediates such as `OP_AddImm P2=-1`. Scalar
`COUNT(*)` and `MAX` subqueries, including a correlated aggregate, now pass in
release and `SQLITE_DEBUG` builds.

The integrity and foreign-key probe then found three more integration defects.
`OP_IsType` now handles cached cursor serial types as well as register values,
and the generic `releasePage` path decrements duplicate references to page one
while the B-tree's base page-one reference retains its dedicated release path.
Savepoint rollback now passes an exact C integer boolean to cursor invalidation.
VDBE halt/reset cleanup also drains deferred trigger frames through
`closeAllCursors`. In release and debug builds, a failed foreign-key insert
followed by cascading delete, `ROLLBACK TO`, `RELEASE`, `foreign_key_check`,
`integrity_check`, and file reopen restores the original rows and closes with
`SQLITE_OK`; lookaside usage returns to zero. No converter or test source was
changed.

A trigger/view probe found an omitted Lemon default token copy: the
`createkw ::= CREATE` reduction did not preserve the CREATE token used to form
view SQL and trigger spans. It now copies the token into the result. Existing
trigger bodies also repeated side-effecting allocator and hash calls; those
calls now run once. `OP_Program` accepts SQLite's negative parameter-base
offsets and validates the final parent register used by `OP_Param`. The VDBE
`OP_Concat` handler now follows SQLite's `P2 || P1` operand order. Release and
debug C ABI probes pass CREATE VIEW, INSERT/UPDATE/DELETE triggers, OLD/NEW
values, `RAISE(ABORT)`, `RAISE(IGNORE)`, integrity checking, and close.

Attached-database testing exposed several transaction and parser-lifetime
defects. Opening a super-journal passes a null optional `pOutFlags`; the generic
OS wrapper and Unix VFS now accept that call. File rollback no longer clears
the page cache before journal playback, and internal playback preserves the
current page size while handling zero-record journal headers. Successful VDBE
commits now clear `DBFLAG_SchemaChange`, and `sqlite3RollbackAll` passes a
0/1 C boolean to B-tree rollback. The parser driver now frees transient tables,
triggers, variable lists, and VFS locks after parsing; nested SQL keeps the
outer parse's table/index/trigger state intact. This removes stale foreign-key
entries that had generated an `OpenRead` on root page zero. The executor also
passes root page zero and optional P4 text through `OP_TableLock` and
`OP_OpenRead` to the B-tree layer, as SQLite does.

Release and debug C ABI probes now pass file-backed `ROLLBACK`, foreign-key
cascade delete, savepoint rollback, `integrity_check`, and a two-file
super-journal transaction. Both attached databases preserve their committed
rows after a cross-database rollback, then detach and reopen successfully.

WAL runtime probes exposed missing transaction wiring and pager cleanup. WAL
writers now take the WAL write lock, append frames during phase one, and end
that transaction during phase two. Releasing the last page reference runs the
full pager teardown so WAL read locks do not remain held across transactions.
Full rollback rewinds uncommitted frames; savepoint rollback rewinds its frame
set and restores page images from the subjournal. Release and debug C ABI probes
pass writer commits, reader snapshot visibility, full rollback, nested
`ROLLBACK TO`, truncate checkpoint, `integrity_check`, and reopen. Existing
in-memory DML and savepoint probes also pass in both profiles. The WAL frame,
undo, and pager teardown bodies were already present as C2FB candidates, so this
work only added the missing pager branches and module bridges; no C2FB or FBC
source change was needed.

The unchanged upstream `test/wal.test` passes 581/581 on the C reference
fixture. The FreeBASIC `SQLITE_TEST` runner completes 581 test cases with zero
failures and no tracked leaks. Its temporary Tcl bridge loads the FreeBASIC
library in both the main and child processes, and matches the fixture's 1 KiB
page size, 64 KiB pending-byte offset, and current-directory capability. No
upstream test source was changed.

The initial WAL run exposed and fixed three port issues. Passive checkpoint
busy codes are cleared even when there is no iterator to backfill;
`wal-10.2.14` now reports a successful partial checkpoint. `sqlite3_log()` now
passes the full 10,000-byte stack-buffer capacity to the formatter instead of
`SizeOf(array)`, which is only one element in FreeBASIC; the recovery event in
`wal-23.4` now includes its formatted message. The pending-byte test control
now drives both the B-tree's reserved-page skip and Unix VFS lock offsets.
Auto-vacuum skips the 64 KiB lock page. `wal-8.2`, `wal-8.3`, and the
attached-database `wal-26` cases pass. The VDBE accepts SQLite's all-database sentinel only for
`OP_Checkpoint`; a direct C ABI `PRAGMA wal_checkpoint(TRUNCATE)` smoke passes.

The unchanged upstream `test/wal2.test` through `test/wal9.test` now pass
alongside `test/wal.test`: 1,843 cases total, with no failures or tracked
leaks. This exposed a checkpoint path that returned as soon as all WAL frames
were backfilled. RESTART and TRUNCATE must still wait for reader locks and
reset or truncate the WAL in that state; `walCheckpoint()` now skips only the
page-copy work. Read-only shared-memory mapping and recovered WAL-index frame
lookup also pass their WAL2/WAL3 cases. The temporary Tcl bridge links directly
to the FreeBASIC test library and provides its expected checkpoint command and
sync counters. No upstream test files changed. The ordinary release
shared-library build also passes. The affected functions already had
FreeBASIC bodies, so no C2FB or compiler change was needed.

The rollback-journal tests exposed a commit/reset interaction. When an explicit
`COMMIT` cannot acquire the exclusive lock, the write transaction must remain
open and `sqlite3_reset()` must return the prior `SQLITE_BUSY`. The VDBE halt
path now preserves that error, and journal finalization retains the zeroed
journal in exclusive or persistent mode until the lock is released. A direct
C ABI probe confirms that the uncommitted updates remain visible to their
connection after the busy commit. The unchanged `pager3.test` (13/13),
`pager4.test` (12/12), `jrnlmode.test` (82/82), and `jrnlmode2.test` (14/14)
pass; the initial multi-client section of `pager1.test` also passes through
`pager1-3.6`. Later `pager1` sections need a working test VFS helper in the
temporary runner, so the full file has not been counted as passing.

The raw `translate-simple` pass rejects pager bodies whose active code is still
surrounded by C preprocessor branches. C2FB's preprocessed file mode selects
the build branch before translating and is the applicable path for those
functions. The WAL fixes in this run were missing caller integration in
existing FreeBASIC bodies, so they did not require a C2FB change.

The preprocessed file-selective C2FB run emitted 127 pager candidates, including
`pagerStress`. Reviewing that candidate showed the rollback-mode spill path
should delegate writes to `pager_write_pagelist`; the FreeBASIC body now does
so, preserving the shared page-hash, size-hint, and backup updates. A direct C
ABI smoke with a one-page cache spilled 96 four-kilobyte blobs, rolled the
transaction back, committed the same workload, and passed `integrity_check`.

This is targeted runtime evidence, not a claim of full SQLite compatibility.
The upstream `testfixture` target has not been linked against the FreeBASIC
library because its full test-support and extension link still requires
unimplemented SQLite APIs. Selected unchanged upstream Tcl scripts run
through a temporary Tcl shell and C bridge linked to the FreeBASIC
`SQLITE_TEST` library; no upstream test source was changed.

Mutex initialization now selects a default, no-op, or caller-supplied callback
table. `SQLITE_CONFIG_MUTEX` copies a validated method table and
`SQLITE_CONFIG_GETMUTEX` returns the current methods. With
`SQLITE_THREAD_MISUSE_WARNINGS`, the default provider wraps connection mutexes
and logs contention for handles opened with NOMUTEX. Default, misuse-warning,
debug/abort, no-op/misuse, and `THREADSAFE=0` library builds pass; mutex runtime
behavior is unverified.

STAT4 value extraction now invokes eligible deterministic or slow-change SQL
functions while building sample probe values. The path is compiled only with
`SQLITE_ENABLE_STAT4`; that library profile builds, but runtime behavior is
unverified.

B-tree cursor setup now uses the upstream scratch-space allocator and clears a
cursor if that allocation fails. VDBE statement arrays use the unused opcode
allocation tail as shared scratch space, with one spill block when the tail
cannot hold all arrays. VDBE deletion releases register and variable payloads
before freeing either backing block. Default and debug library builds pass;
runtime allocation behavior is unverified. Page-one initialization opens WAL
files when the header requests WAL and applies the journal-mode synchronous
default to the matching database slot. Debug builds now check parent-child page pointers,
and the cursor-hint opcode dispatches range and table-cursor hints under
`SQLITE_ENABLE_CURSOR_HINTS`. Default, differing WAL-sync, and debug cursor-hint
library profiles build; runtime behavior is unverified.

Shared-cache B-tree opens now canonicalize database paths, match the VFS and
path against the shared list, increment `BtShared.nRef`, and link each B-tree
handle into address order for mutex entry. Close rolls back that handle and
frees the shared pager only after the last reference. Default, debug, and
`THREADSAFE=0` library builds pass; runtime shared-cache behavior is unverified.

Expression-list construction now routes through separate new-list and growth
helpers in `sqlite3_expr.bas`. They retain SQLite's four-item initial capacity,
double capacity as needed, initialize new items, and dispose of both the list
and pending expression when growth fails. The default library build passes;
runtime behavior remains unverified.

`sqlite3ExprDup()` preserves reduced/token-only input prefixes for ordinary
full copies, relocates inline token strings, and duplicates window definitions.
`EXPRDUP_REDUCE` requests now place each left/right expression tree in one
SQLite-owned buffer and mark its child nodes static, avoiding separate node
allocations. Copied Expr records remain full-sized because downstream
FreeBASIC readers do not consistently guard compact prefixes. A C ABI smoke
created a table with a default and CHECK expression, a view, and a trigger,
inserted data, reopened the database, and verified the view row and
`integrity_check`. Release and debug builds pass. Compact Expr records remain
unsupported; this path uses more memory than upstream SQLite.

`PORTING_PARSER_RULES.csv` tracks all 412 generated Lemon rules separately from
the C function ledger. All 348 rules with custom semantic actions now have
FreeBASIC cases; the other 64 use Lemon's default
semantic-value copy. Recent reductions handle parenthesized `FROM` lists,
including their source-item ownership transfers, and the DROP TABLE, VIEW,
INDEX, and TRIGGER commands. CREATE INDEX and ATTACH/DETACH are wired, as are
trigger creation, trigger command lists, DML trigger steps, and `RAISE`
expressions. DML reductions now construct UPDATE assignment lists, including
vector assignments, and dispatch DELETE, UPDATE, INSERT, UPSERT, and RETURNING
operations. IdList reductions use the dedicated parser minor field. The
expression reductions now include current-time functions, row vectors, pointer
expressions, scalar subqueries, `IN` subqueries and table-valued functions,
`EXISTS`, qualified column names, ordered function arguments, window
attachments, and parenthesized expression lists. ALTER TABLE column and
constraint operations, virtual-table declarations, window definitions, frame
bounds, FILTER, and OVER clauses are now connected to their existing engine
helpers.
`make -C fb_src regen-generated` refreshes this ledger with the parser rule IDs.

The latest default-profile C2FB sweep processed 79 tracked engine C inputs in
eight balanced batches, with no preprocessing failures. It emitted 127
procedure candidates, and none matched an uncovered function row. The focused
`SQLITE_TEST` plus `SQLITE_DEBUG` pass over `wal.c` emitted `walLockName` after
C2FB gained support for zero-initialized local static arrays. That helper is
integrated under the same guards as the C source. `walHandleException` has a
FreeBASIC body that releases transient WAL locks and restores deferred WAL-index
state, and it compiles in the SEH profile. The FreeBASIC WAL module still has no
`__try`/`__except` boundary to call it. The exception filter and fault injector
now have bodies with the upstream exception code and argument layout, and the
default, Windows SEH, and debug Windows SEH WAL objects compile. Without the
boundary, WAL operations do not invoke the filter, and injected faults are not
caught. Default and debug/test library builds pass; runtime behavior is
unverified. The Windows thread callback `sqlite3ThreadProc` is
also ported with the original StdCall convention and `_endthreadex`; the
Windows target build is unverified. The five constant-propagation helpers from
`select.c` are ported in `sqlite3_select_constant_propagation.bas` and now run
after FROM-subquery flattening in the table-backed SELECT path. The unchanged
`whereL.test` passes 28/28, including the join-order cases that require the
rewrite.

The B-tree `OP_Column` path now decodes only enough record header to reach the
requested column and reads overflow content through `vdbeColumnFromOverflow`.
Large table TEXT/BLOB values use the existing reference-counted string allocator
and cursor cleanup path. The default shared-library build passes; runtime
behavior is unverified. The SQLITE_DEBUG library now checks the fast record
comparators against generic Mem comparison and validates KeyInfo field limits;
that debug profile builds, but runtime assertion behavior is unverified.

The optional `SQLITE_ENABLE_IOTRACE` profile now exports `sqlite3IoTrace` and
formats normalized SQL for the callback at VDBE entry. The profile builds and
exports both trace symbols; callback output is unverified at runtime.

Initial follow-up passes translated `mem2.c` and `os_kv.c` with
`SQLITE_MEMDEBUG` and `SQLITE_OS_KV`, then `os_unix.c` with debug,
locking-style, timeout, and mmap options. Those passes emitted six and 14
candidates, all already represented by existing function bodies. C2FB rejected
the guarded MEM2 allocator because its shared record state and allocation
layout are outside the body subset; all 20 indexed `mem2.c` functions have
since been ported directly in `sqlite3_memdebug.bas`.

A later default-profile batch over 16 files emitted 66 procedure candidates:
36 compiled individually and 30 failed, but every passing name already had a
FreeBASIC body. The guard audit found that most remaining functions are behind
optional or platform-specific macros. Other skips use source-local globals or
calls through callback fields, which the current C2FB body subset does not
resolve.

A feature pass using `SQLITE_MAX_ATTACHED=32` and explain comments compiled six
candidate procedures, all already present in the port. C2FB skipped
`analyzeVdbeCommentIndexWithColumnName` on the `NEVER()` macro expansion, so
the helper and its three opcode-comment call sites were ported directly in
`sqlite3_analyze.bas`. The debug/explain library builds; runtime comment output
remains unverified.

A remaining-source batch processed 12 C inputs with debug, Unix locking, and
assertion-stub options. It emitted 76 candidates with no preprocessing
failures, but none matched an uncovered function row. A separate
`SQLITE_MAX_ATTACHED=32` pass exposed C array-typedef parameter decay and the
`sizeof(yDbMask)` extent. C2FB now emits `sqlite3DbMaskAllZero` with a `UByte
Ptr` parameter and the correct five-byte extent. The helper is integrated in
`sqlite3_build.bas` under `SQLITE_MAX_ATTACHED>30`; that module compiles in the
max-32 profile. Runtime behavior and the other wide-mask operations remain
unverified.

An earlier IOTRACE/SQLLOG candidate pass over `vdbeaux.c` did not produce an
uncovered body. `sqlite3VdbeIOTraceSql` is now ported in `sqlite3_iotrace.bas`
and called at VDBE entry; the feature build exports both trace symbols. The
SQLLOG callback now receives open, completed-statement, and close events when
`SQLITE_ENABLE_SQLLOG` is enabled; statement text is expanded before dispatch.
The SQLLOG feature library builds. `checkActiveVdbeCnt` also checks active,
reader, and writer counters after cursor cleanup and VDBE halt. Debug, IOTRACE,
and SQLLOG runtime output remains unverified.

The Unix VFS now uses `seekAndRead`, `seekAndWriteFd`, and `seekAndWrite` for
positioned I/O. Reads retry interrupted calls, report short reads after
zero-filling the remaining buffer, and preserve the last system error. Writes
retry interrupted calls and retain SQLite's short-write and disk-full results.
The close path logs descriptor errors without retrying `close()` after
`EINTR`, and last-error storage uses a shared helper.
The final inode-reference close drains its deferred-descriptor list through
`releaseInodeInfo` and `closePendingFds` before freeing the shared lock record.
The main-database open/close path checks link count and inode identity, and
`SQLITE_FCNTL_HAS_MOVED` reports path replacement or unlinking.
The VFS creates random, collision-checked temporary filenames under its temp
directory mutex and exposes them through `SQLITE_FCNTL_TEMPFILENAME`.
File controls query or change persistent-WAL and powersafe-overwrite flags.
Sector size and device capabilities are initialized lazily, including optional
F2FS atomic-write detection.
Descriptor diagnostics, null-I/O, file/VFS pointer, and VFS-name controls are
also handled by the Unix file-control callback.
Chunk-size and size-hint controls round requested growth and extend the file
before remapping when required. The WAL external-reader control checks for
conflicting reader locks in the shared-memory lock range.
The Unix VFS module compiles in normal and `SQLITE_TEST` profiles; runtime I/O
behavior remains unverified.

Unix WAL shared-memory opens now use SQLite's deadman-switch byte at offset
128. The first writable opener takes an exclusive lock, initializes the
shared-memory file, and downgrades to a shared lock; read-only openers can
retry after another process initializes it. Database exclusive locking checks
for another process's DMS lock before proceeding. The default library builds;
cross-process WAL locking behavior remains unverified.

A full SQLITE_DEBUG/SQLITE_ENABLE_TREETRACE loose pass also preprocessed all
80 engine C inputs without failures. It emitted 168 procedures; per-procedure
compilation passed 95 and failed 73. Two passing procedures lacked bodies in
the ledger at scan time: parseuriFunc and sqlite3VdbeMemValidStrRep. Both are
integrated. fpdecodeFunc is also ported; parseuri and fpdecode are registered
only in SQLITE_DEBUG builds (78 indexed C lines). sqlite3VdbeMemValidStrRep
sits beside its private numeric renderer with the string termination and
allocation checks restored. Follow-up repairs added six procedures for JSONB
debug output, WHERE term tracing, and VDBE opcode rewrite traces (119 indexed C
lines). The JSON debug parser is registered only in SQLITE_DEBUG builds. A
preceding debug batch also added seven procedures across ALTER, B-tree,
expression walking, SELECT planning, and VDBE Mem (112 indexed C lines). The
six-file VFS/pager/VDBE batch emitted 31 procedures; 17 compiled, and all 17
already had bodies in the ledger. The MEMDEBUG port now implements guarded
allocation headers, list maintenance, trailer and padding checks, allocation
type tags, size-bucket statistics, backtrace controls, title storage, dump
output, and allocation counts. `sqlite3_memory.bas` selects these callbacks
when `SQLITE_MEMDEBUG` is enabled. For `THREADSAFE=0`, the memory-journal
method table now initializes without a mutex, since that profile does not
support concurrent SQLite calls. A direct C API probe passes in-memory
`CREATE TABLE` and `SELECT 1`; the unchanged `altercol.test` also passes 257/257
under `SQLITE_MEMDEBUG` with no allocations left at shutdown.

The current C2FB executable was rebuilt from its latest FreeBASIC sources and
rerun across all 80 engine C inputs with SQLITE_DEBUG, TREETRACE, and
WHERETRACE enabled. Preprocessing had no failures and produced 164 procedure
candidates; the 160 in-scope names already had bodies, so this broad pass added
no coverage. A selected pass over `wherecode.c`, `where.c`, `mem2.c`, and
`malloc.c` enabled cursor hints, STAT4, and MEMDEBUG. It emitted 12 candidate
procedures, nine of which compiled individually. The new eight-line
`sqlite3IndexColumnAffinity` body is integrated with bounds and allocation
checks. Together with the WHERE trace helpers, all 107 indexed functions and
6,399 indexed function lines from `src/where.c` now have FreeBASIC bodies.

The C2FB record catalog now maps the local C `CCurHint` record to
`SqliteCursorHint` in `sqlite3_walker.bi`. That allowed a cursor-hint batch to
emit and compile all four procedures in `wherecode.c`. The port adds the missing
`codeCursorHintCheckExpr`, `codeCursorHintFixExpr`, and 100-line `codeCursorHint`
procedures, then wires the three hint call sites into
`sqlite3WhereCodeOneLoopStart` under `SQLITE_ENABLE_CURSOR_HINTS`. The full
debug/cursor-hint library and the combined debug/trace/cursor-hint/STAT4 library
build; the default library also builds. At this stage, `src/wherecode.c` had
bodies for 27 of 28 indexed functions and 2,528 of 2,569 indexed function lines.

A selected batch enabled `SQLITE_ENABLE_SORTER_REFERENCES` and
`SQLITE_ENABLE_STMT_SCANSTATUS` across `select.c` and `wherecode.c`. It emitted
six candidates, five compiled, and two new bodies are integrated:
`selectExprDefer` selects primary-key columns for deferred sorter reads, and
`sqlite3WhereAddScanStatus` records outer-loop and OR-subloop scan entries.
The sorter path now carries the extra expressions through row loading and
updates the sorter record metadata. The default and combined sorter-reference/
scan-status libraries build. All 28 indexed functions and 2,569 indexed
function lines from `src/wherecode.c` now have FreeBASIC bodies. At that point,
`src/select.c` had bodies for 102 of 109 indexed functions and 6,845 of 7,147
indexed lines.

One of the remaining SELECT helpers, `sqlite3JoinType`, is now ported in
`sqlite3_bulk_select_join_type.bas`. It matches the three token slots against
SQLite's accepted keywords, rejects incompatible join masks, and retains the
existing parser diagnostic. The default and sorter/scan-status libraries build
with this 53-line body included.

The Unix locking-style batch now includes the dot-file and flock lock,
unlock, reserved-lock check, and close procedures. Under
`SQLITE_ENABLE_LOCKING_STYLE`, `sqlite3_os_init()` registers `unix-dotfile`
and `unix-flock` VFS entries. Dot-file locking creates a sibling `.lock`
directory and maps an existing directory to `SQLITE_BUSY`; both styles use
the shared Unix open, I/O, and close paths. The guarded Apple profile now
registers `unix-nfs` with a split-range unlock to avoid stale NFS write locks.
Default, locking-style, and debug/test locking-style library builds pass, and
the Apple-guarded object compiles locally; runtime locking behavior is
unverified. WAL shared-memory mappings now group 32 KiB regions to the host
page size, keeping offsets aligned when the host page is 64 KiB or larger.
The default Unix I/O methods also expose version 3 `xFetch`/`xUnfetch`: they map
reads on demand within the configured size, retain reference counts, and fall
back to `xRead` if mapping fails. `SQLITE_FCNTL_MMAP_SIZE` changes the mapping
limit after outstanding references are released. Default and locking-style
libraries, plus a build with a nonzero default mmap size, pass; runtime mmap
behavior remains unverified. The Unix VFS now has bodies for 112 of 135
indexed functions and 4,213 of 5,514 indexed lines.

The matching C2FB release-profile pass over `os_unix.c` enabled
`SQLITE_ENABLE_LOCKING_STYLE`, `SQLITE_ENABLE_SETLK_TIMEOUT`, and
`SQLITE_ENABLE_BATCH_ATOMIC_WRITE` with `NDEBUG=1`. It emitted 12 procedure
candidates; four compiled individually. The remaining flock helper closure was
ported together and included in the passing locking-style library build.
The latest loose source-aware pass emitted 13 simple procedures, all of which
already had bodies. The missing NFS unlock and timeout helper were then ported
as a guarded group, with `unix-nfs` method selection and VFS registration.
An Apple-macro C2FB pass used a temporary `TargetConditionals.h` stub for
preprocessing and emitted 16 simple procedures. Two uncovered helpers,
`proxyGetHostID` and `proxyCreateConchPathname`, came from that batch; four
additional proxy file/path helpers were ported together. The file-open helper
uses the Unix internal open path with no-follow and deferred-descriptor reuse.
At that checkpoint, the conch break and retry helpers had Apple-guarded bodies,
but `proxyTakeConch` and proxy method switching remained incomplete.
Apple-profile objects compile with `HAVE_GETHOSTUUID=0`, `HAVE_GETHOSTUUID=1`
plus `SQLITE_TEST`, and a `LOCKPROXYDIR` override; no native Apple runtime was
used. The proxy lock state machine was still unmapped at that checkpoint.

The refreshed loose C2FB pass translated all 80 engine C inputs without a
preprocessing failure. It emitted 164 procedures; the individual-procedure
screen checked 161, with 87 compiling and 74 failing. Every emitted name
already has a port body, so this broad pass added no coverage. A pager pass with
`SQLITE_DEBUG`, `SQLITE_CHECK_PAGES`, and `SQLITE_TEST` exposed four missing
page-hash helpers that compile individually. They are integrated into the
pager path, with the page check called before a page is made writable.
The debug `print_pager_state()` routine was rejected for its static local
buffer, so it now uses a module-static buffer with `sqlite3_snprintf()`.
`sqlite3PagerStats()` is also implemented under `SQLITE_TEST`; its C static
array became a module static array. The default library and a full
`SQLITE_DEBUG`/`SQLITE_CHECK_PAGES`/`SQLITE_TEST` library build pass. Runtime
page-hash, debug output, and test-hook behavior remains unverified.

A Windows-focused loose C2FB pass preprocessed `os_win.c` with
`SQLITE_OS_WIN=1` and `_WIN32=1`, emitting 14 candidates. Eight compile
individually; seven mapped to uncovered rows and are now implemented in the
guarded `sqlite3_os_win_helpers.bas` module: the UTF-8 directory setter, the
no-lock callbacks, sector-size query, UNC-path check, and temp-directory state
check. The eighth candidate wrapped the UTF-16 directory setter before that
conversion path was ported. The helper module now includes the
UTF-16 directory setters, UTF-8/UTF-16 and ANSI/OEM conversion helpers and
wrappers, the native filename conversion helper, VFS error formatting,
last-error, dynamic-library, debug-output, I/O-retry, file-handle, and mapping
callbacks, the Win32 sleep wrapper and callback, and both VFS clock callbacks.
It compiles in the default Unix library build and as separate debug/test and
release-profile objects with `SQLITE_OS_WIN=1`; a native Windows compiler and
runtime have not been used. Four more small path helpers now
recognize long-path, drive-letter, and verbatim prefixes, and append a trailing
separator within the supplied buffer. At that checkpoint, the module covered
65 Windows functions and 1,249 indexed C lines. C2FB now maps common Windows SDK scalar and pointer
types and reads the WinFile layouts from `sqlite3_os_win_types.bi`. A
source-name-preserving pass over the Windows-preprocessed `os_win.c` emitted 23
procedures; 12 compile individually. It exposed the mode-bit and device
characteristic callbacks, then the record layouts exposed shared-memory lock
and mapping candidates. The shared-memory lock, file-handle helpers, and
ordinary-file mmap fetch/unfetch callbacks were integrated in later batches.
The Windows backend now initializes the 60-entry syscall table before VFS
registration and connects its set/get/next callbacks to all four VFS variants.
Typed dispatch aliases route overrideable Win32 calls in the VFS and optional
heap allocator through the table. Table updates follow SQLite's unsynchronized
configuration model, so set overrides before concurrent I/O. Cygwin builds now
populate the POSIX syscall slots and convert UTF-8 paths through
`cygwin_conv_path`. Full-path resolution checks and follows symbolic links,
builds the Cygwin working-directory prefix, and simplifies the resulting path.
Temporary-directory lookup also checks the Cygwin environment variables and
standard POSIX locations. The branch follows Cygwin's documented size-query
call for `cygwin_conv_path` and its POSIX-to-wide-Windows conversion flags
([Cygwin API documentation](https://cygwin.com/cygwin/doc/preview/cygwin-api/func-cygwin-conv-path.html)).
FreeBASIC generated C for the Cygwin target; the object stage could not run
because `cygwin-gcc` is not installed, and native Cygwin runtime behavior is
unverified. Shared-memory mutex callbacks and the barrier are also in the
module.
The initial `mutex_w32.c` C2FB pass emitted no in-scope bodies because the
converter does not lower Interlocked operations or Windows lock records. The Windows backend now
implements all 11 indexed mutex functions (201 C lines) across
`sqlite3_mutex_windows.bi` and `sqlite3_os_win_helpers.bas`. Recursive locks use
`CRITICAL_SECTION`; fast and static locks use exclusive `SRWLOCK`s, with the
static lock storage aligned to the upstream 128-byte stride. Its debug,
release, misuse-warning, no-op, and single-thread objects compile under the
local FreeBASIC compiler with `SQLITE_OS_WIN=1`; a native Windows compiler and
runtime have not been used. Optional Windows mutex `OSTRACE`
messages are not ported. The Unix debug mutex queries now inspect this port's
shared bookkeeping mutex instead of the upstream per-inode mutex. C2FB still
rejects `lockTrace` at its indirect
syscall call, so that 47-line helper wraps the port's `unixFcntlRaw` dispatcher.
The `SQLITE_DEBUG`/`SQLITE_LOCK_TRACE` library profile builds; trace output is
unverified.

Since the previous checkpoint, this continuation added 28 function bodies
covering 716 indexed C lines. C2FB
ledger reconciliation now scans executable `.bi` bodies as well as `.bas`
modules, so included platform implementations are counted automatically.

The `SQLITE_ENABLE_SETLK_TIMEOUT` path now carries per-connection timeout and
block-on-connect settings through the Unix file-control interface and WAL
writer locks. The B-tree transaction path sets and clears the WAL connection
context, and stops busy-handler retries after a timed lock. The full
`SQLITE_DEBUG`/`SQLITE_TEST` build with timeout mode 1 and the full `SQLITE_TEST`
build with timeout mode 2 pass; runtime lock behavior remains unverified. The
pager's two `SQLITE_TEST` I/O-error suppression routines are implemented and
called around pager close. The Unix VFS test profile exports the C-named I/O
error, disk-full, open-file, and sync counters and applies pending I/O faults
to its read, write, sync, truncate, size, lock, delete, access, and temp-open
operations. The pager ledger now covers all 152 indexed functions and 5,104
function lines. Default, `SQLITE_TEST`, debug/test/setlk mode 1, and test/setlk
mode 2 library builds pass; no C test suite has been run and runtime fault
recovery and lock behavior remain unverified.

A feature-aware C2FB batch covered 17 remaining core files, including the B-tree,
planner, VDBE, allocator, and mutex sources. The batch emitted 92 unique
procedure names; 91 non-helper procedures were compiled individually, with 47
compiling and 44 still needing converter or dependency repairs. The 12-file
remainder ran as four independent C2FB processes with separate output
directories before their candidates were merged. Two Unix debug helpers from
these passes are now integrated: `azFileLock` supplies OS trace lock labels
(the port does not yet include its OSTRACE call sites), and
`assertLockingArrayOk` checks shared counts against exclusive owners after
SHM lock updates. Candidate compilation does not establish runtime behavior.

The default shared-library link audit found `sqlite3ParserSemanticReduce` was
implemented but its source module was missing from the build list; adding the
module resolves that reference. `sqlite3SubqueryColumnTypes` now propagates
affinity, type names, and collation to transient tables for resolved compound
SELECTs. `sqlite3CodeSubselect` emits scalar and EXISTS subquery subroutines.
`sqlite3CodeRhsOfIN` fills an ephemeral index with the RHS list or SELECT and
preserves expression affinity and collation. It now reuses completed
uncorrelated SELECT RHS subroutines when the select ID and affinity match;
correlated SELECTs and variable expression lists are still regenerated, and
eligible one-time SELECT RHS subroutines also use Bloom filters when all
comparison collations are BINARY and the optimization is enabled. The active
SELECT compiler now accepts `SRT_Mem`, `SRT_Exists`, and `SRT_Set` destinations
for tableless, table-backed, and aggregate results. Scalar, EXISTS, and IN-SELECT subqueries
therefore reach the expression subroutines. The default library builds, and its
dynamic symbol audit finds no unresolved internal SQLite names. Runtime
behavior has not been tested.

The CREATE TABLE reducer now handles table setup, type names, table options,
defaults, NOT NULL, primary keys, unique/check constraints, collations, and
column and table foreign keys. `sqlite3AddColumn` stores standard types in the
packed column flags and custom types beside the column name. The foreign-key
builder links definitions into the child table and parent-name hash. Constraint
runtime behavior, generated columns, virtual-table actions, and most DML parser
actions remain unverified or unmapped; this parser slice has only been
build-checked.

A selected debug/trace batch used `SQLITE_ENABLE_TREETRACE` and the loose
candidate target. It preprocessed 12 files and emitted 74 procedures; 25 of 74
compiled individually. After fixing C2FB's runtime-alias call mapping, a fresh
TreeView-only pass compiled all six emitted procedures, including five
previously missing bodies: `sqlite3TreeViewExpr`,
`sqlite3TreeViewSrcList`, and the DELETE, INSERT, and UPDATE renderers. The
manual `sqlite3TreeViewBareExprList` port completes the remaining renderer.
Candidate-only assert suppression made those bodies parseable; the integrated
expression and source-list procedures restore their C invariants through the
central debug assertion handler. The TreeView ledger is now 35 of 35 functions
and 1,189 of 1,189 indexed C lines. The earlier cursor-hint batch also added
`codeCursorHintIsOrFunction`; a manual B-tree hint getter and two TreeView list
renderers followed. The pager/VDBE debug work adds the savepoint count check,
two truncate-constraint helpers, the pager-state validator, and the RIGHT JOIN
subroutine jump validator (217 indexed C lines). The pager-state validator is
also called while opening a savepoint; the jump validator runs for generated
RIGHT JOIN subroutines. At that point the index was 2,938 functions. The full default
and debug/TREETRACE library builds pass; runtime behavior remains unverified.

The debug bitmap dumper now recursively prints small bitmaps, hash entries, and
child bitmaps through SQLite's centralized debug printer. `bitvec.c` has bodies
for all 10 indexed functions and 281 indexed C lines. At that point the index
was 2,940 functions; debug output remains unverified at runtime.

The function-registration batch now includes `functionDestroy`,
`sqlite3CreateFunc`, `createFunctionApi`, and
`sqlite3_create_window_function` (201 C lines). C2FB maps the fixed
`FuncDestructor` record. The full threaded library builds and exports the
window-function API; `window5.test` and a C API destructor probe now verify
registration, replacement, and connection-close cleanup. C2FB's declaration
token limit is now 256, up from 96; the 100-token nested callback signature in
`createFunctionApi` now converts. With existing-body filtering disabled, the
`main.c` pass emitted 101 candidates; the helper and window wrapper pass an
isolated compiler screen. The preceding whole-tree pass preprocessed all 80
engine files without failures; its only new candidate was the fault-injection
initializer, which was ported because `main.c` calls it during connection open.

C2FB now retains parenthesized, multi-digit array bounds from preprocessed C
records, sizes the port-owned `sqlite3` record for its allocation, and maps
`aHardLimit` to the table shared with `sqlite3_limit`. The generated
`sqlite3_limit` candidate compiles. C2FB now translates `openDatabase` through
its built-in extension loop. The 331-line body is integrated with port-specific
setup for inline database slots, the main B-tree handle, and cached length
limit. The built-in callback table retains the fault-simulation hook used by
the C test API. The full default library build passes; runtime behavior remains
unverified.

The variadic conversion pass now recognizes C implementation signatures ending
in `...`, maps `va_list` to FreeBASIC `Cva_List`, and lowers preprocessed
`va_start`, `va_end`, and typed `va_arg` builtins. The pass exposed the
`sqlite3_db_config()` option table and connection-field mapping as remaining
barriers for that routine, so its 89-line body is ported in
`sqlite3_db_config.bas`. It covers the complete default-profile option table,
including lookaside and floating-point digit settings. The full threaded
library build passes and exports `sqlite3_db_config`; runtime behavior is
unverified.

The `sqlite3_test_control()` dispatcher is now ported in
`sqlite3_test_control.bas` using FreeBASIC's C varargs support. It connects the
PRNG save/restore/seed controls, fault and benign-allocation hooks, Bitvec test
program, per-connection flags, local-time fault override, schema checks,
`OP_Once` reset threshold, sorter mapping limit, imposter-table setup, result
int-real control, trace flags, LogEst conversion, and AtoF conversion. The
supporting state lives in `sqlite3_config.bas`; `sqlite3OsRandomness()` and
`osLocaltime()` now honor its test overrides. `sqlite3BitvecBuiltinTest()` and
the debug-aware `sqlite3BtreeSeekCount()` are represented. The full threaded
library build passes. Runtime behavior remains unverified; parser-coverage,
VDBE-coverage, and debug-only tuning profiles remain unverified.

The `sqlite3Initialize()` process-initialization body is a private helper called
by the public `sqlite3_initialize()` wrapper. The wrapper now uses SQLite's
initialized-state fast path and memory barrier, so allocator calls made under
the static main mutex do not recursively enter the non-recursive initialization
lock. The automatic-extension C ABI smoke exercises this path while growing the
registry. `sqlite3ErrName()` maps primary and extended result codes to their
symbolic names and returns unknown codes through a reusable static buffer. The
`src/main.c` ledger has bodies for all 126 indexed functions and all 4,297
indexed function lines.

The C2FB record catalog now maps the memory VFS `MemStore` and `MemFile` records
to shared internal layouts. That mapping enabled the loose C2FB pass to emit
`sqlite3_serialize()` and `sqlite3_deserialize()` together. Their bodies are
integrated in `sqlite3_bulk_memdb_serialization.bas`; the VFS-specific
`memdbFromDbSchema()` helper stays beside the store state. The full threaded
library build passes; runtime behavior is unverified.

The variadic C body for `sqlite3VdbeExplain()` now translates through C2FB's
`Cva_List` support. The regenerated internal declaration maps C `va_list` to
`ByRef Cva_List`, matching the FreeBASIC formatter implementation. The
27-line candidate passed per-procedure compilation and the full library build;
runtime EXPLAIN output remains unverified.

The optional `SQLITE_ENABLE_SNAPSHOT` path now includes the public get/open/
recover APIs, the pager bridge, WAL snapshot validation and read-lock selection,
and checkpoint recovery (14 functions, 242 C lines). The full threaded library
build passes with snapshots enabled; the API-armor snapshot module also compiles.
The default threaded library rebuild passes afterward. Runtime behavior remains
unverified.

The latest C2FB pass preprocessed all 80 engine source files without failures.
The converter now preserves pointee `const` through pointer-to-pointer
indexing, resolves aliased FreeBASIC records, lowers mapped member offsets, and
indexes C function signatures after removing compiler attributes. An earlier
integration series added 42 functions and 9,492 upstream C lines. These include
`sqlite3InitOne`, `sqlite3AddCollateType`,
`constructAutomaticIndex`, WHERE path solving and ordering, VDBE numeric and
memory helpers, INSERT constraint generation, `sqlite3Update`, and the 677-line
`sqlite3WhereBegin` with the 1,365-line `sqlite3WhereCodeOneLoopStart`. The
expression batch adds `sqlite3ExprCodeTarget` and `sqlite3FindInIndex`; the
SELECT batch adds compound-query merge, output generation, subquery flattening,
and EXISTS-to-join procedures. The full threaded library builds; runtime
behavior remains unverified.

The latest loose C2FB refresh preprocessed all 80 engine C files without
failures and emitted 15 procedures from `btree.c`, `vtab.c`, and `vdbe.c`.
All 15 passed the per-procedure compiler screen. Six new in-scope bodies were
integrated: B-tree freelist, overflow, and page-tree integrity checks
(`checkList`, `checkTreePage`, `sqlite3BtreeIntegrityCheck`; 494 C lines),
virtual-table parser setup and token extension (`sqlite3VtabBeginParse`,
`sqlite3VtabArgExtend`; 53 lines), and the VDBE index-key comparator
(`vdbeIndexKeyCompare`; 25 lines). The B-tree module keeps its private helper
closure beside the integrity traversal. Integrity state and progress/diagnostic
helpers live in `sqlite3_integrity_types.bi` and
`sqlite3_btree_integrity_helpers.bas`. A populated, indexed database passes
`PRAGMA integrity_check` in release and debug builds; broader corruption
diagnostics remain unverified.

The follow-up expression batch adds `exprIdxCover` and
`sqlite3ExprCoveredByIndex` (25 indexed C lines). C2FB now maps the fixed
`IdxCover` record stored through the Walker union. Exact C record-owner lookup
now preserves field types when a C tag such as `Walker` maps to a differently
named FreeBASIC type. The two bodies were integrated from upstream and compile
with the full library.

A follow-up corrected unary dereference of `const T **`: the pointed-to pointer
slot remains writable while a single pointer to const data remains read-only.
A targeted main.c conversion then emitted `sqlite3_table_column_metadata` (111
C lines), including its optional pointer outputs. The next full-tree refresh
again processed all 80 engine C files without preprocessing failures and found
no further in-scope candidates; the only new body was the test-only
`sqlite3TestExtInit`, which remains out of scope. The threaded library build
passes with the metadata API included.

The shared-cache default now has a stored FreeBASIC flag, a C2FB-visible
getter, and the `sqlite3_enable_shared_cache` setter in `sqlite3_config.bas`.
At this earlier checkpoint, `openDatabase` was still unmapped. It was later
ported in `sqlite3_bulk_open_database.bas`; shared-cache connection behavior
remains unverified at runtime.

The `RETURNING` context now maps to `SqliteReturning`, including its embedded
Trigger and TriggerStep layouts. The C2FB cleanup callback and the parse-time
trigger setup are integrated (50 C lines); the setup call formats its transient
name with the port's existing `sqlite3_snprintf`. The full library build passes.

A fixed `VdbeFrame` layout now lets C2FB translate frame cleanup and restoration
plus cursor closure (56 C lines). The five-candidate helper group compiled
individually, and the full library build passes.

The optional `SQLITE_ENABLE_NORMALIZE` profile now has the two double-quoted
identifier list routines and VDBE deletion cleanup (24 C lines). Their module
and the full threaded library build with `SQLITE_ENABLE_NORMALIZE=1` pass; the
default threaded library build passes as well.

C2FB now emits initialized scalar C statics as procedure-local FreeBASIC
`Static` storage. This added `sqlite3BtreeFakeValidCursor` (5 C lines), whose
persistent byte backs the B-tree cursor-state sentinel; its candidate compiled
individually. The latest full-tree scan had no additional in-scope candidates.

The initial 80-file candidate screen emitted 74 bodies in ten source files,
with 55 passing its per-procedure compile screen. A later loose whole-tree
refresh took about 8½ minutes, preprocessed all 80 engine files without failures,
and emitted 36 bodies in six source files; 25 compiled individually. The
remaining batch exposed local dependencies that blocked several entry points.
The repair pass added seven indexed functions covering 652 C lines:
`multiSelect`, `multiSelectValues`, `accessPayload`, `allocateSpace`,
`insertCell`, `insertCellFast`, and `vdbeSorterCompareReal`.

The next loose refresh again preprocessed all 80 engine files without failures
and emitted five candidate bodies in three source files; four compiled
individually. The port added `sqlite3WhereEnd`, its RIGHT JOIN unmatched-row
pass, and the VDBE statement-savepoint helper and wrapper, covering 567 C lines.
The complete threaded library builds; runtime behavior remains unverified.

A targeted B-tree conversion maps `BtreePayload` to `SqliteBtreePayload` and
retains the exported `sqlite3PendingByte` integer. It emitted six unmapped
routines for payload construction, auto-vacuum, and root-page creation/removal,
along with 18 helper bodies. All 24 procedures compile individually. The
existing incremental-vacuum and commit paths now call the translated C helpers
for page-count calculation and page relocation. This batch covers 609 indexed
C lines, and the full threaded library builds; runtime behavior remains
unverified.

A second targeted B-tree pass lowers GCC's 16-bit byte-swap read through fixed-
width FreeBASIC helpers. It added cell-size validation, index-cell comparison,
backward cursor traversal, and database-page clearing, covering another 173 C
lines. All 20 candidate procedures compile individually; the full threaded
library builds, and runtime behavior remains unverified.

A pointer qualifier correction and typed pointer difference lowering
unlocked `rebuildPage`, `pageFreeArray`, and `editPage`, adding 233 C lines.
Their nine-procedure helper closure compiles individually, and the threaded
library builds. C2FB now treats a trailing top-level pointer `const` separately
from pointee `const`, and computes compatible pointer differences in element
units.

A VDBE auxiliary pass maps the serial-type length table and the fixed
`UnpackedRecord` layout, which enables automatic locals for mapped records. It
adds `sqlite3VdbeAllocUnpackedRecord`, the integer and string comparison
specializations, `sqlite3VdbeFindCompare`, and `sqlite3VdbeIdxRowid` (256 C
lines). All five candidates compile individually, and the full threaded
library builds; runtime behavior remains unverified.

The pager write cluster now covers `pager_write`, `pager_open_journal`,
`openSubJournal`, `pager_write_pagelist`, `writeJournalHdr`, `syncJournal`,
`pager_incr_changecounter`, `writeSuperJournal`, and `pagerOpenSavepoint`
(668 indexed C lines).
Journal sync invalidates a stale following header before committing the page
count and honors SAFE_APPEND and SEQUENTIAL capabilities.
Dirty-page output applies the VFS size hint, refreshes page hashes, and updates
database-version and backup state. Super-journal records use SQLite’s signed-byte
checksum and truncate any persistent-journal tail after the record. Savepoint
creation initializes bitvecs and captures WAL state. The full threaded library
build passes; runtime behavior remains unverified.

The B-tree allocator now follows the upstream freelist search modes. The
generic wrapper selects any available page, while auto-vacuum and root-page
paths request exact or less-than-or-equal pages where the C source requires it.
It also skips pending-byte and pointer-map pages when extending the database.
The full threaded library build passes; runtime behavior is unverified.

The earlier WHERE batches added `sqlite3WhereBegin` and
`sqlite3WhereCodeOneLoopStart` with their IN-loop and indexed-expression
helpers.

The ALTER conversion work maps SQLite's five-field `RenameCtx`, preserves
`const void *` types, and recognizes the record's fixed layout. That enabled a
33-procedure conversion batch from `src/alter.c`; nine previously missing
engine functions are now integrated, covering 577 upstream C lines. The built-in
registration path now calls `sqlite3AlterFunctions()` unless ALTER TABLE is
omitted. The full library builds; runtime behavior remains unverified.

A focused follow-up on `src/pragma.c` mapped its generated `pragCName` column
table to stable storage, enabling C2FB to translate `pragmaVtabConnect`. The
pragma virtual-table callback table and `sqlite3PragmaVtabRegister()` are now
integrated; all 30 indexed functions in `pragma.c` have FreeBASIC bodies,
covering 2,816 C lines. The full library builds; runtime behavior remains
unverified.

The date module now includes `currentTimeFunc` for builds that omit full date
handling and the `datedebugFunc` JSON callback in debug builds. The date module
compiles in the default, omit-datetime, and debug profiles; the full default
library build passes. Runtime behavior remains unverified.

The no-op mutex source now exposes a static nine-callback method table and the
`SQLITE_MUTEX_NOOP` default selector. The mutex module compiles in threaded,
single-thread no-op, and debug no-op profiles. Full library builds pass with
both `THREADSAFE=1` and `THREADSAFE=0`. Runtime behavior remains unverified.

The Unix pthread backend now exposes its typed callback adapters and a static
method table through `sqlite3DefaultMutex()`. All 11 indexed functions in
`src/mutex_unix.c` have FreeBASIC bodies (240 C lines). Both full library
threading profiles build; runtime behavior remains unverified.

The ATTACH port now includes `attachFunc`, `sqlite3Attach`, and `sqlite3Detach`,
alongside the existing VDBE code generator and cleanup helpers. C2FB maps the
fixed `Db` slot size; the port uses its preallocated database-slot array instead
of reallocating C's `aDb` pointer. All 15 indexed functions in `src/attach.c`
have bodies (523 C lines). The full threaded library builds; runtime behavior
remains unverified.

C2FB now recognizes the fixed `Trigger` and `TriggerStep` records, which enabled
`sqlite3BeginTrigger`; the debug-only `onErrorText` helper is also ported.
`src/trigger.c` now has bodies for all 33 indexed functions (1,295 C lines).
The trigger module compiles with `SQLITE_DEBUG`, and the full libraries build in
both threading profiles. Runtime behavior remains unverified.

The earlier repaired batch added 18 indexed functions and 3,148 C function
lines, including `sqlite3Pragma` at 2,372 C lines and its generated 66-name,
57-column metadata. The other additions cover B-tree page insertion, JSONB
extraction and updates, `sqlite3Reprepare`, expression generation, VDBE type
naming, value text conversion, and window value checks. The load-extension
table has 279 C-ordered pointer slots; 255 currently point to FreeBASIC bodies,
with unavailable APIs left null.

The PRAGMA-name and result-column tables are generated by the FreeBASIC
`sqlite_codegen` tool from the preprocessed `pragma.c` source. The loose
whole-tree target refreshes them together with the candidate bodies.

A focused C2FB pass on `src/where.c` emitted 11 procedures with their local
helper closure. The new `sqlite3_bulk_where_loop_generation.bas` adds
`termCanDriveIndex`, `whereLoopAddBtree`, `whereLoopAddOr`, `whereLoopAddAll`,
and `whereReverseScanOrder`, covering 568 indexed C lines. C2FB now resolves
FreeBASIC type aliases before field matching, casts opaque pointer fields using
their actual storage types, and accepts the fixed planner records used by this
build profile. The candidate module compiles and the full library build passes;
runtime behavior remains unverified.

A focused `src/whereexpr.c` pass then emitted 16 procedures with helper closure.
The new `sqlite3_bulk_whereexpr_analysis.bas` adds seven missing functions,
including `exprAnalyze`, its OR-term helper, and the auxiliary virtual-table
operator check. This covers 945 indexed C lines and completes body coverage for
all 31 indexed `whereexpr.c` functions. C2FB now handles the existing uppercase
map, stable BINARY collation-name pointer, arrays of fixed planner records, and
local C callback variables. The generated candidate module compiles and the
full library builds; runtime behavior remains unverified. The loose repair queue
is empty. The earlier typed SELECT batch compiled 10 of 13 procedures
individually and enabled six SELECT expansion bodies.

The SELECT path now constructs join terms for NATURAL, USING, and ON clauses,
resolves FROM terms against nested WITH contexts, expands SELECT sources, and
rewrites compound SELECTs with ORDER BY expressions. These bodies compile as
part of the library; runtime behavior is unverified.

WHERE bytecode generation now has IN-loop setup, equality-term register
handling, index affinity selection, and Bloom-filter pull-down. The full
library build passes; runtime behavior remains unverified.

The Unix VFS now supplies C-named unlock and close adapters over its Linux
lock and close paths. Apple NFS split-range unlock is unsupported. The full
library build passes; runtime behavior remains unverified.

SELECT flattening now substitutes output columns through expressions, nested
SELECTs, and window definitions while preserving join flags, outer-join nullability,
and collation.

The load-extension API resolves platform-library callbacks, initializes the
extension function table, and records loaded handles on each connection. The
automatic-extension registry now supports register, cancel, reset, and callback
invocation outside its static mutex. Missing API bodies leave null table entries.
The full library build passes; runtime behavior is unverified.

The public UTF-8 and UTF-16 prepare APIs now use the shared lock-and-prepare
path. It checks schema locks, validates schema cookies after parse errors,
retries schema and transient parser errors, and releases parser-owned state
before returning. The library build passes; prepare behavior is unverified at
runtime.

C2FB now adds declarations for referenced public FreeBASIC procedures when their
bodies are in sibling `.bas` files without a shared `.bi` declaration. This made
isolated candidate checks reflect the full build's cross-module interfaces. It
unlocked `sqlite3BtreeCheckpoint` and `doWalCallbacks`; the port now also includes
`sqlite3Checkpoint`, `sqlite3_wal_checkpoint_v2`, `sqlite3_wal_checkpoint`,
`readDbPage`, `pagerUndoCallback`, `pagerRollbackWal`, `appendOnePathElement`,
and `appendAllPathElements`. The three pager rollback
functions cover 107 indexed C lines. The Unix VFS now normalizes path components
and follows symbolic links, selects database-matching journal/WAL permissions,
reserves low file descriptors, syncs the directory after creating a journal or
WAL file, and chooses temporary directories from the public override, environment,
and standard Unix locations. The public `sqlite3_temp_directory` and
`sqlite3_data_directory` C symbols are exported. The full thread-safe library
build passes. The Unix VFS also provides dlopen/dlsym/dlerror/dlclose callbacks
when loadable extensions are enabled. `sqlite3_bulk_loadext.bas` implements the
high-level loader, authorization check, suffix and entry-point fallback,
extension API initialization, and per-connection handle cleanup. A C ABI smoke
using SQLite's `test/testloadext.c` verified the disabled-by-default behavior,
implicit `.so` suffix and entry-point resolution, extension API calls, SQL
function registration, and handle cleanup on close. A second C ABI smoke
verified automatic extension registration and invocation, duplicate
suppression, registry reset, and cancellation. Broader extension error paths
remain unverified.
The aggregate analyzer reuses existing aggregate allocation helpers and tracks index-backed
expressions, ORDER BY/DISTINCT metadata, and column/function references. The full library
build passes; runtime behavior remains unverified.

A VDBE cleanup batch adds PMA reader and merge teardown, sorter task joins, sorter reset/close, and B-tree, sorter, and virtual-table cursor release. These procedures cover 191 indexed C lines across sqlite3_bulk_vdbesort_repair.bas and sqlite3_bulk43_vdbe_cursor_cleanup.bas. The full library build passes; runtime behavior is unverified.

The sorter PMA batch now provides 66 of 66 indexed bodies from `src/vdbesort.c`
(1,929 indexed C lines), including PMA readers and writers, in-memory sorting,
incremental merge scheduling, sorter cursor operations, and initialization.
The fixed sorter layouts and flexible `VdbeSorter.aTask` tail are shared through
`sqlite3_vdbesort_types.bi`; `sqlite3VdbeSorterInit()` also uses the configured
PMA threshold and small-allocation setting. Four worker-debug helpers compile
with `SQLITE_DEBUG_SORTER_THREADS=1`. A C API probe forced file-backed PMAs with
`SQLITE_CONFIG_PMASZ=1` and `temp_store=FILE`: release and debug-symbol builds
sorted 50,000 out-of-order rows.
EXPLAIN showed all five sorter opcodes, both probes reported a sort, and
finalize/close left lookaside usage at zero. `strace` observed two temporary
files opened and removed during the 50,000-row run.

The WAL utility batch adds page-size decoding, WAL-size configuration and truncation, heap-memory mode reporting, and header restart state. The single-frame read helper now reads WAL payload bytes and zero-fills a caller buffer tail when it exceeds the page size. Hash-page mapping and collision-chain search now locate the newest committed frame for a database page. Frame salt/checksum validation, hash append/cleanup, and read-frame lookup now cover recovery prerequisites. WAL-index recovery now has a body that rebuilds the frame hashes under recovery locks and publishes the recovered header; it compiles, but runtime behavior is unverified. The read-transaction path now reads or rebuilds the WAL-index header, handles unreliable read-only shared memory, selects a stable reader mark, and releases transaction locks. The full library build passes; runtime behavior is unverified. Frame writes cover writer locks, WAL frame encoding, WAL-file sync boundaries, checksum repair after overwrites, wal-index publication, rollback callbacks, and savepoints. The full library build passes; runtime behavior is unverified. The checkpoint iterator and passive/full/restart/truncate paths also build; runtime checkpoint behavior is unverified. SETLK-timeout and SEH accessors are present behind their feature guards. The SQLITE_DEBUG plus SQLITE_USE_SEH profile also checks the tracked WAL lock mask against reader, writer, and checkpoint state; that profile builds, but runtime assertions remain unverified.

The B-tree overflow cleanup path now maps `getOverflowPage()` and
`clearCellOverflow()`. Auto-vacuum databases use the pointer map to locate a
next overflow page when possible, with a page-read fallback. Cleanup keeps the
existing chain-length and page-reference checks. The full library build passes;
overflow runtime behavior is unverified.

The B-tree balance cluster now maps `balance_deeper()`, `balance_quick()`,
`balance_nonroot()`, and `balance()`. Root expansion repairs pointer maps after
copying node contents, and the quick right-edge path uses caller-owned divider
scratch. The balance planner repairs child and overflow pointer maps for auto-vacuum.
The planner counts a table-leaf overflow cell when it moves that cell to a new
sibling, and quick balance uses the validated saved size for queued scratch
cells. Newly allocated internal siblings now use a valid empty old-cell range,
and page rebuilds use cached cell sizes so earlier writes cannot change the
sizes of later source cells. The 50,000-row release and debug-symbol probes
exercise deeper internal-page balancing, PMA merge, sorted output, and clean
finalize/close.

The cursor movement path now maps `btreeMoveto()`,
`btreeRestoreCursorPosition()`, `btreeNext()`, and `moveToLeftmost()`. Packed
index keys use the record-unpack path, while table seeks use the rowid path.
The next-key helper runs after the exported wrapper restores cursor state. The
full library build passes; cursor runtime behavior is unverified.

The pager savepoint path now maps `subjournalPage()` and
`subjournalPageIfRequired()` and uses the `subjRequiresPage()` predicate. It
updates later savepoint truncation flags and advances the subjournal record
count even when rollback journaling is off, following SQLite’s C behavior.
The full library build passes; pager runtime behavior is unverified.

The pager now reads committed page counts from the WAL before falling back to
database file size, and hot-journal detection checks the journal header before
rollback playback. The WAL handle and index records are defined in
`sqlite3_wal_types.bi`, with optional fields guarded alongside `src/wal.c`.
Both the WAL implementation and conversion candidates use these declarations.
Default and ZIPVFS library builds pass; profile layout parity and runtime
behavior remain unverified.

The WAL layer now opens handles, allocates and maps wal-index pages, reads and
publishes the duplicated wal-index headers with checksums and shared-memory
barriers, and switches Pager into WAL mode when requested. WAL-index recovery,
frame lookup, frame reads, and the read-transaction path now compile with the
library. Frame writes, rollback, and savepoint handling now compile; WAL
checkpoint code now builds; checkpoint and end-to-end WAL behavior are unverified.

An earlier C2FB fix preserved pointer depth when an indexed C pointer-to-pointer
field uses opaque `Any Ptr` storage. The refreshed whole-tree scan emitted 89
procedures in 14 modules. Thirty-nine candidate compiles passed: 38 were bodies
already present and one was a test-only hook. Forty-nine unported engine bodies
still fail on dependencies or unsupported statements; one already-ported pager
helper also failed inside a dependency closure. This pass found no additional
ready engine body beyond the PCache1 batch.

The preprocessed C2FB pass scans the default source profile for all 80 engine C
files. Adding layouts for `sqlite3_index_info` and its hidden planner tail
unlocked five WHERE procedures and the JSON callback `jsonEachBestIndex`.
Bounded integer constant array expressions, the exact `CellArray` layout, and
typed B-tree page callbacks then unlocked `populateCellCache` and
`computeCellSize`. `sqlite3_vtab_collation()` is also implemented directly over
the new public and hidden index-info layouts.

A full sweep at that stage emitted 395 procedures in 46 source modules. After
correcting the const-qualified `sqlite3MemCompare` and `sqlite3BlobCompare`
declarations and adding the missing internal callback declarations, all 395
procedures compile individually. Thirty-three newly mapped procedures,
covering 1,014 upstream function lines, are integrated in bulk modules 20
through 35. This includes the virtual-table allocator `allocateIndexInfo`.
The per-procedure check does not assess runtime behavior. Other accepted output
was already mapped or outside the indexed engine scope.

An earlier C2FB sweep emitted 405 procedures across 47 source modules. Mapping
`sqlite3.suppressErr`, `sqlite3.eOpenState`, and `VdbeOp.p4.pVtab` let all 405
candidates compile individually. At that stage, 403 were integrated; the
test-only `sqlite3TestExtInit` stays out of scope, and `sqlite3Close` was
deferred pending the `sqlite3LeaveMutexAndCloseZombie` cleanup path. Nine newly
indexed functions added 275 upstream function lines to the coverage ledger. A follow-up
dependency pass added another 20 indexed functions, including table and AST
cleanup, shared-cache locks, window cleanup, authorization, column defaults,
and WAL callbacks. The full library build passes and the unresolved SQLite
symbol count fell from 39 to 30. A later layout extension mapped FKey,
Trigger, TriggerStep, IdList, Subquery, and Upsert records. It enabled 23
compile-clean FK/Trigger procedures and four UPSERT procedures; the FK delete
path, IdList lookup, and UPSERT allocation/cleanup entry points are also
ported. Adding `Parse.eOrconf` then let the full-tree sweep compile all 614
candidate bodies across 66 modules. The port now integrates 424 preprocessed
body definitions across 47 modules, excluding the test-only hook. This added
16 newly indexed functions and 557 upstream function lines, including
`codeTriggerProgram` and `sqlite3Close`. At that stage, `sqlite3Close` still
depended on the unported `sqlite3LeaveMutexAndCloseZombie` cleanup path. A follow-up ported
`sqlite3CollapseDatabaseArray` against the fixed-size database-slot layout.
The rename-token map and UPSERT allocator also have bodies now. A fresh
preprocessed sweep over all 80 engine C files emitted 423 procedure definitions
across 47 source modules; every emitted module compiled. It added
`renameTokenFree` and `renameParseCleanup` to the ALTER batch. The candidate
directory retained 20 older candidate files, so the combined checker reported
634 bodies across 67 files; 423 is the fresh sweep count. A subsequent isolated
pass checked 418 bodies across 47 nonempty modules; all 47 compiled. Candidate
body counts do not by themselves represent new source coverage. A manual port of
`sqlite3VtabCreateModule` reduced unresolved SQLite symbols to 25. A source-list
batch then added `sqlite3SrcListEnlarge`, `sqlite3SrcListAppend`, and
`sqlite3SrcListAppendList`. A copy layer added `sqlite3IdListDup` and
`sqlite3SrcListDup`, and `sqlite3SelectDup` now delegates FROM-list copying to
the mapped source-list routine. A follow-on parser pass added FROM-term assembly, ON/USING cleanup, subquery
attachment and detachment, table-valued function arguments, and INDEXED BY
metadata. Rename expression-list cleanup now maps list names back to source
tokens. `sqlite3OpenTempDatabase` opens the TEMP B-tree with the pending page
size. AUTOINCREMENT now reserves its rowid registers, initializes the sequence cursor, tracks maximum rowids, and emits sequence writeback. Index affinity caching, the optional NULL-trim MakeRecord flag, and updated-column checks for constraint expressions are also ported. The full library build passes with 22 unresolved SQLite symbols. The library is not ready for
the upstream SQLite suites. These checks establish compiler acceptance, not
runtime behavior parity.

A fresh C2FB sweep scanned all 80 engine C files and emitted 424 procedure
definitions across 47 modules. The 419 candidate function bodies compile as
grouped modules after adding a shared declaration for
`sqlite3VdbeSetP4KeyInfo`. Comparing their names with earlier modules showed
that 417 were already-ported private procedures emitted again as local
helpers. `sqlite3TestExtInit` remains out of scope. Only `fkLookupParent` added
a new in-scope function, covering 141 upstream lines; `sqlite3_bulk40_fkey.bas`
keeps that body without the redundant candidates. The library build passes and
the unresolved SQLite dynamic symbol count remains 22.

The next preprocessed sweep emitted 420 bodies across 47 modules, and every
module compiled. Inventory comparison showed that 419 were private helper
copies for functions already mapped elsewhere; the remaining body was the
out-of-scope `sqlite3TestExtInit`. Those copies remain in the candidate tree
instead of being added to the library. C2FB also confirmed that
`sqlite3RunVacuum()` depends on a variadic `execSqlF()` it cannot translate.
The 285-line runner is now ported manually in `sqlite3_bulk_vacuum.bas`,
including `VACUUM INTO` file checks, schema and row copying, metadata
preservation, B-tree replacement, and cleanup. The full library build passes;
the dynamic undefined SQLite symbol count is still 22. No SQLite runtime suite
has been run against the port.

Mapping `DbFixer` to its embedded `Walker` record and verifying the fixed
`Select` layout let C2FB translate five schema-fixer procedures from
`src/attach.c`. `fixSelectCb()` writes C bitfields, so its six `SrcItem.fg`
flags are set through explicit masks in `sqlite3_walker.bi`; `sqlite3FixInit()`
and the callback are implemented in `sqlite3_bulk_attachfix.bas`. The seven
procedures cover 135 upstream lines. At that stage the full library build
passed with 22 undefined SQLite symbols; it reports a generated-C const-qualification warning
on the `sqlite3FixInit()` schema-fixer type pointer. Runtime behavior remains
unverified.

Mapping `AuthContext` to the parser's saved authorization state let C2FB
translate `sqlite3AuthContextPush()` and `sqlite3AuthContextPop()` from
`src/auth.c`. Their two bodies cover 16 upstream lines and compile in
`sqlite3_bulk_authctx.bas`. The full library build passes with 22 unresolved
SQLite symbols.

Adding `Parse.sLastToken` to the port and updating it before each parser token
submission made all 47 groups in the refreshed C2FB sweep compile. It exposed
`sqlite3CreateView()` and `sqlite3FinishTrigger()`, translated across 194
upstream lines, plus `sqlite3ShadowTableName()`. Mapping the complete `Table`
record and the packed `sqlite3InitInfo` flags let C2FB translate
`sqlite3StartTable()`; direct writes to the separately stored unsigned
`checkSchema` bitfield are now width-masked. `sqlite3CheckObjectName()` is also
ported manually. At that stage the library build passed with 23 unresolved
SQLite symbols. `sqlite3EndTable()`, `sqlite3NestedParse()`, and
`sqlite3CreateIndex()` now have bodies. The manual index builder is integrated
with table creation, including the WITHOUT ROWID path; index runtime behavior
remains unverified.

Mapping C `Window` to the complete `SqliteWalkerWindow` layout and adding the
private aggregate state records let C2FB translate 31 more indexed functions
from `src/window.c`, covering 529 upstream lines. The new module contains the
rank, percent-rank, cumulative distribution, ntile, nth-value, first-value,
and last-value callbacks, plus window allocation, linking, comparison, and copy
helpers. Its local `sqlite3WindowOffsetExpr()` copy calls the now-ported
`sqlite3RenameExprUnmap()` path. CTE cleanup now reaches the ported
`sqlite3SelectPrep()` and translated recursive CTE generator. The full library
build passes. A 20-row `WITH RECURSIVE ... UNION ALL` C API probe returns the
expected sequence in release and debug builds; other recursive CTE cases remain
unverified.

Mapping the generated `PragmaName` record and pragma virtual-table cursor
layouts let C2FB translate 10 more callbacks from `src/pragma.c`, covering 149
upstream lines. `sqlite3_bulk_pragma_vtab.bas` implements cursor open, close,
filter, iteration, column, rowid, and best-index callbacks. The full library
build passes with the same 27 unresolved SQLite symbols.

Mapping `JsonParent`, `JsonEachCursor`, and `JsonEachConnection` to the JSON
parser, path-string, and virtual-table layouts enabled 10 more C2FB bodies
from `src/json.c`, covering 127 upstream lines. The new module ports cursor
creation, cleanup, reset, end-of-scan, path-length, malformed-input, and rowid
helpers. At this checkpoint, JSON row-value production, module registration,
and scan callbacks were still outstanding. They were later added in
`sqlite3_bulk_json_vtab.bas`; JSON virtual-table runtime behavior remains
unverified.
The full library build passes with 27 unresolved SQLite symbols.

After the window and JSON layout mappings, a fresh C2FB sweep emitted 482
candidate bodies across 48 source files; all 48 groups compiled. Five new
indexed functions covering 79 lines are integrated in
`sqlite3_bulk_expr_windows.bas`, `sqlite3_bulk_select_windows.bas`, and
`sqlite3_bulk_resolve_windows.bas`. They discover window functions during
expression walks, attach function `ORDER BY` terms, and apply window-specific
checks during SELECT push-down and resolution. The full library build still
has 27 unresolved SQLite symbols.

Mapping `NameContext` to its parser, source-list, SELECT, and upsert records
enabled a loose C2FB batch for the resolver core. `sqlite3_bulk_resolve_core.bas`
now contains `resolveExprStep`, `resolveSelectStep`, `lookupName`,
`sqlite3ResolveExprNames()`, `sqlite3ResolveExprListNames()`, and
`sqlite3ResolveSelectNames()`, plus their local callbacks. The ALTER rename
walkers and `sqlite3RenameExprUnmap()` are also ported. Nested CTE name
resolution reaches `sqlite3SelectPrep()`, and compound SELECTs now dispatch to
the translated multi-select path, including recursive CTE generation. Runtime
behavior remains unverified.

The fixed `AggInfo`, column-entry, and function-entry records enabled 12
aggregate-analysis helpers from `src/expr.c` and `src/select.c`, covering 465
upstream lines. `sqlite3_bulk_aggregate_expr.bas` creates aggregate
column/function entries and persists their references; the SELECT module
assigns accumulator registers, updates aggregate inputs, and applies indexed
expression optimizations. `sqlite3ArrayAllocate()` is also ported.

Mapping `RefSrcList` and `CheckOnCtx` enabled 20 more walker helpers, covering
889 upstream lines. These scan expression references and validate join clauses.
A follow-up sweep found four additional functions covering 87 lines for
deterministic expressions, column defaults, RETURNING subqueries, and table
transfer checks. The last full-tree loose C2FB sweep emitted 658 candidate
bodies across 53 nonempty source groups. Twenty-five groups compiled together;
per-procedure checks compiled 534 of the 658 bodies. Ninety-five still-unported
indexed procedures depended on unresolved helpers at that snapshot. A targeted
repair since that sweep added `whereLoopInsert()` and `whereLoopXfer()`, then
integrated `whereLoopAddBtreeIndex()` and `whereShortCut()`. Those four bodies
add 650 upstream function lines. The full library build passes with 27
unresolved SQLite symbols, including `sqlite3SelectPrep()` and the remaining
DDL, foreign-key, VDBE, and virtual-table entry points.

The converter's loose-candidate mode keeps callers whose private helpers have
not translated, so larger source batches can be staged and repaired together.
The default candidate mode still filters those callers before compilation.
C2FB now removes FreeBASIC macro-name collisions that differ only by C
identifier case, and emits named procedure-pointer aliases for generated
callback signatures. Internal declarations expose already-ported helpers to
candidate modules, including B-tree page helpers, virtual-table index-info
allocation, VDBE P4 cleanup, and the pager WAL capability check.
`sqlite3VdbeClearObject()` is integrated with its local memory and opcode
cleanup helpers. Targeted B-tree batches added page initialization and cursor
walking, page-format decoding, node-content copying, and loop insertion. The
shared B-tree interface now exposes existing page, cell-parser, and pointer-map
helpers that those modules reuse. The planner now ports WHERE scanning,
temporary term allocation, term insertion, expression-use masks, and limit
term generation. Two candidate routines, `whereLoopAddBtreeIndex()` and
`whereShortCut()`, also compile with the shared loop insertion path.

The query-planner pass now includes `sqlite3_where_scan.bas` for scanner state,
term matching, and index affinity checks; `sqlite3_where_clause.bas` for
WhereTerm growth and WhereInfo-owned allocation; and
`sqlite3_bulk_where_expr_terms.bas` for expression-use masks, clause splitting,
and limit terms. `sqlite3_bulk_where_scan_queries.bas` adds indexed-term lookup
and DISTINCT redundancy checks.

The next WHERE pass added `whereLoopAddVirtualOne()` (180 indexed C lines)
and `whereLoopAddVirtual()` (123 indexed C lines). `decodeIntArray()` from
`src/analyze.c` is also translated as a source-local helper. A full C2FB sweep
emitted 536 candidate bodies across 48 source groups, and all 48 groups
compiled after exposing the shared `sqlite3WhereFindTerm()` declaration.
Most emitted bodies were duplicate local implementations needed to compile
candidate groups in isolation; those duplicate modules were consolidated or
discarded. The test-only `sqlite3TestExtInit()` candidate was excluded. The
loose sweep emitted 656 bodies across 53 source groups; 25 groups compiled,
while 28 groups still fail on untranslated helpers. Eighty still-missing
indexed candidates in that report cover 3,899 C lines. The trigger group now
has a FreeBASIC `triggerStepAllocate()` and the `sqlite3TriggerInsertStep()`,
`sqlite3TriggerUpdateStep()`, `sqlite3TriggerDeleteStep()`, and
`sqlite3TriggerSelectStep()` bodies in `sqlite3_bulk36_trigger.bas`.
The virtual-table group now has `vtabCallConstructor()` and its three
connect, create, and eponymous-table callers in `sqlite3_bulk36_vtab.bas`.
The expression modules now include the reduced Expr copy-size helpers,
`sqlite3ExprIsIIF()`, `sqlite3ExprCodeExprList()`, and the expression implication
walkers, including the RIGHT JOIN-aware non-NULL-row check. The expression-list
code generator lives beside its private constant-analysis helper in
`sqlite3_expr.bas`.
`sqlite3_bulk_vdbeblob.bas` now owns the incremental-BLOB handle layout,
open/read/write/reopen/close routines, size query, and shared row-seek path.
The complete FreeBASIC library builds with 13 unresolved SQLite symbols. No
SQLite runtime test suite has been run against this port.

The default STAT1 `ANALYZE` path now creates or clears `sqlite_stat1`, scans
table indexes, emits the per-prefix distinct-count bytecode, writes the new
statistics, and schedules `OP_LoadAnalysis`. The `stat_init`, `stat_push`, and
`stat_get` callbacks use a variable-sized accumulator allocated through
SQLite's database allocator. STAT4 sampling is not included. The full library
build passes; runtime behavior is unverified.

`sqlite3LimitWhere()` now builds the primary-key subquery used to implement
ORDER BY and LIMIT for DELETE and UPDATE. The public code preserves source-list
ownership, indexed-by cleanup, and CTE-use accounting while constructing the
row-key IN expression.

After C2FB began filtering already-ported private bodies while retaining
transitive helpers needed by new candidates, the cached sweep fell from 654 to
155 candidate bodies. The assignment-lowering fix then reduced it to 151; 68
compile individually. `sqlite3FkDropTable()` is integrated in
`sqlite3_bulk36_fkey.bas`; its call to `sqlite3DeleteFrom()` is still
unresolved.

C2FB assignment lowering now freezes a converted right-hand value before
writing it to its target, so a call on the right-hand side is evaluated once.
The converted foreign-key candidate set had eight of nine procedures compile
with their helper closure. `isSetNullAction()`, `sqlite3FkCheck()`,
`fkActionTrigger()`, and `sqlite3FkActions()` are now integrated in
`sqlite3_bulk36_fkey.bas` and `sqlite3_bulk41_fkey_check.bas`. The unresolved
set includes `sqlite3DeleteFrom()`, `sqlite3Insert()`, `sqlite3Update()`,
`sqlite3SelectPrep()`, `sqlite3WhereBegin()`, and `sqlite3WhereEnd()`.
`sqlite3CodeRowTriggerDirect()` compiles cached trigger subprograms and emits
`OP_Program` calls. `sqlite3CodeRowTrigger()` selects matching triggers,
`codeReturningTrigger()` generates inline RETURNING rows, and
`sqlite3TriggerColmask()` uses cached old/new column masks.

The VDBE auxiliary port now resolves symbolic jump labels and transfers
completed opcode arrays through `sqlite3VdbeTakeOpArray()`. The trigger module
uses that path to cache trigger programs while preserving parser error state
and trigger column masks. `sqlite3GenerateColumnNames()` supplies the result
names needed by the RETURNING path.

The date subsystem now has FreeBASIC bodies for all 36 indexed functions
(1,380 of 1,380 function lines). It parses timestamps and modifiers, converts
Julian-day/calendar/time state, handles local time, and registers
`julianday()`, `unixepoch()`, `date()`, `time()`, `datetime()`, `strftime()`,
`timediff()`, the three `current_*` callbacks, the `datedebug()` diagnostic,
and the `SQLITE_OMIT_DATETIME_FUNCS` current-time fallback.

The current source files port the version and source-identity entry points
from `src/main.c`, the statement-completeness functions from `src/complete.c`,
tokenization plus keyword inspection from `src/tokenize.c`, and UTF-8/UTF-16
conversion and length helpers from `src/utf.c`. Lemon's parser tables, action lookups,
allocation, stack growth, push-token transition loop, and tokenizer-to-parser
runner are ported. A small subset of grammar actions now builds literal
expressions and expression lists, then compiles tableless SELECTs, compound
`UNION`, `UNION ALL`, `INTERSECT`, and `EXCEPT` chains, plus single- or
multi-row VALUES clauses. Supported values
include integers, reals, digit-separated numeric literals, strings, blobs,
NULL, TRUE/FALSE, bound parameters, unary and binary operators, and simple
or searched CASE expressions. Constant-list `IN`/`NOT IN` tests and the
`coalesce()`, `ifnull()`, and `nullif()` calls use specialized lowering;
`typeof()` uses the registered scalar callback path.
Lemon reduce lookup accepts nonterminal symbols, pure-reduce goto states stay
encoded as reduce states, and the parser runner preserves caller-owned Parse
state during nested SQL parsing. An early C API smoke found that nested
`OP_ParseSchema` SQL failed while parsing `AND`, and that a later close could
return `SQLITE_MISUSE`. Subsequent parser and cleanup repairs fixed those
cases: a current C ABI probe creates a table, reads its row through
`SELECT * FROM sqlite_master`, and closes with `SQLITE_OK`. VDBE make-ready
also clears the cursor-pointer array before execution; without that
initialization, `sqlite3StartTable` could reuse stale opcode bytes as a
cursor address and crash in `sqlite3BtreeCloseCursor`.
Transaction grammar actions generate `OP_Transaction`, `OP_AutoCommit`, and
`OP_Savepoint` instructions. BEGIN, COMMIT, ROLLBACK, and savepoint commands
now call `sqlite3AuthCheck()` with SQLite's transaction action and operation
name before emitting those instructions. The VDBE tracks selected databases
in its B-tree masks, starts transactions and opens B-tree cursors by database
index, and finalizes active B-trees through SQLite's two-phase commit path.
Release/debug C ABI probes and the unchanged `attach.test` through
`attach4.test` suites exercise attached-database behavior; the suite results
are recorded near the end of this log.
Logical `AND` folds a known false input when the expression is outside a join
constraint, and defers releasing its unused inputs until preparation finishes.
Planner helpers also inspect boolean tokens, signed integer expressions, and
bound integer parameters while recording when a later bind requires reprepare.
Walker-based constant analysis now handles outer-join terms, fixed columns,
per-cursor table constants, constant scalar-function flags, and legacy schema
defaults that contain bound parameters.
Expression comparison now checks mapped operators, token text, child nodes,
and expression-list ordering. It returns indeterminate for variable-to-literal
matching and window-function comparisons that need unported state.
Vector expressions expose their width and SELECT/list field expressions.
Deep copies preserve token, child-expression, ExprList, compound SELECT,
CTE-owned state, and mapped FROM-list entries. SrcList copies duplicate owned
names, ON/USING and table-function expressions, retain shared table references,
and increment CTE-use counts. `sqlite3SelectDup` now uses this path for its
FROM lists. Reduced/token-only nodes and window definitions remain unsupported
by the shared-buffer duplication path. Ordinary expression copies preserve
reduced and token-only prefixes and duplicate attached window-function state
through `sqlite3WindowDup()`.
SELECT-column wrappers preserve their borrowed SELECT owner. Tableless SELECT
expressions containing row-value vectors now route through SQLite's shared
expression bytecode emitter, including contiguous vector evaluation and row
comparison handling. Runtime behavior is unverified.
`sqlite3_cte.bas` appends CTE entries with duplicate-name checks, duplicates
CTE names, column lists, and supported SELECT trees, and releases CTE-owned
allocations. Parser reductions construct CTE lists, push cleanup ownership, and
attach WITH clauses to parsed SELECTs. `sqlite3_bulk39_select.bas` resolves CTE
names and expands FROM-term references. The active SELECT path materializes CTE
FROM terms, ordinary derived tables, and views through shared fill subroutines.
Multiple references to the same CTE reuse one cursor; correlated subqueries
are recomputed for each outer row. Tableless literal and VALUES bodies and
table-backed queries use the existing SELECT paths. Compound SELECTs dispatch
through the translated multi-select implementation, including recursive CTE
queues. Table-backed simple and grouped aggregate CTE bodies also write to
ephemeral destinations. Window SELECTs use the translated rewrite, initialization,
and frame-code paths through the table-backed scan compiler. Source-less
ungrouped and grouped aggregate CTE bodies now use the aggregate analyzer and
accumulator paths; flattening and coroutine optimizations for FROM subqueries
are not integrated. The full library build passes; runtime behavior is
unverified.
GROUP BY constant analysis accepts matching terms only when BINARY collation
is known; unresolved column collations remain conservative false negatives.
The single-table constraint helper also checks outer-join provenance and
subquery constancy against the selected FROM item.
Affinity analysis identifies literal and rowid expressions that do not need
an additional OP_Affinity conversion.
Expression height is now calculated across children, lists, and compound
SELECT terms before the configured depth limit is checked.
The bytewise BINARY comparator and its CollSeq predicate are in
`sqlite3_vdbe_compare.bas`; registration and lookup for custom collations are
still outstanding.
Simple SELECT statements also support constant WHERE expressions,
`IS`/`IS NOT` null-safe comparisons, `IS NULL` predicates, and LIMIT/OFFSET
counters. CAST to BLOB, TEXT, NUMERIC, INTEGER, and REAL affinities and
BETWEEN/NOT BETWEEN expressions are also available for tableless queries.
The VDBE is created on demand through `sqlite3GetVdbe()`, and the expression
walker can visit expression children, expression lists, compound SELECT terms,
FROM subqueries, and table-valued-function arguments. Window expression terms
are included when requested by the walker callbacks. The CTE stack callback
unwinds the active WITH clause after compound SELECT walks. SELECT preparation
resolves and expands CTE references; CTE FROM terms, ordinary derived tables,
and views use materialization, and recursive CTEs use the translated compound
dispatcher.
Runtime behavior remains unverified.
UTF-8 `sqlite3_prepare()`/`_v2()`/`_v3()` and UTF-16 `sqlite3_prepare16()`/
`_v2()`/`_v3()` return a ready VDBE and the tail after the first statement;
UTF-16 tail offsets are mapped back to the original input.
`sqlite3_errmsg16()` returns connection error text in native UTF-16.
Basic table-backed SELECTs now run `sqlite3SelectPrep()` for source expansion
and name resolution, then `sqlite3WhereBegin()`/`sqlite3WhereEnd()` for source
scans and WHERE filtering. Result expressions use SQLite's expression code
generator, and LIMIT/OFFSET counters are emitted in the scan loop. ORDER BY
uses index order when the planner proves it and a bounded ephemeral index for
LIMIT/OFFSET queries that need a temporary sort; unbounded sorts use the
translated sorter. DISTINCT uses an ephemeral duplicate set. Simple table-backed aggregate
queries without GROUP BY and grouped queries use SQLite's aggregate analysis,
accumulator, sorter, and finalization helpers; HAVING filters the completed
aggregate row. Recursive CTE code generation is connected through the compound
dispatcher, table-backed aggregate CTE bodies can materialize into ephemeral
tables, and window SELECTs use the translated rewrite and frame-code path;
runtime behavior is unverified. Source-less ungrouped and grouped aggregate
SELECTs and CTE bodies use the shared aggregate analyzer and accumulator
paths. A no-FROM WHERE clause filters the implicit single input row; grouped
code emits no group when that row is rejected. Ungrouped aggregate SELECTs accept top-level
DISTINCT and ORDER BY; grouped aggregate output also sorts and removes duplicate
result rows. Grouped and ungrouped aggregate paths apply LIMIT and OFFSET,
including after grouped output sorting or duplicate removal. Aggregate DISTINCT,
ORDER BY, and FILTER use the accumulator helper paths. Runtime behavior is
unverified.

All custom grammar actions have handlers. Parser finalization now mirrors all
50 active Lemon `%destructor` symbols from `src/parse.y`, including expression
and list values, SELECT and source lists, CTEs, windows, trigger steps, ID lists,
and window-frame bounds. Stack values are cleared before destruction so a
second finalization cannot release them again. Parser cleanup behavior remains
unverified at runtime.
`sqlite3_exec()` now loops over prepared statements and delivers result rows
to the supplied C callback for this supported subset. It applies
`sqlite3ApiExit()` before returning so the connection error mask controls
whether callers receive primary or extended result codes. `sqlite3_get_table()`
collects those callback rows into SQLite-owned strings, with
`sqlite3_free_table()` releasing the flattened result.
The registered progress callback is checked during implemented SELECT code
generation and while the VDBE counts virtual-machine steps.
Parser diagnostics retain a formatted message and token byte offset through
prepare cleanup, then transfer the message to the connection's error value.
Prepared-statement metadata includes binding, column access, status counters,
expiration state, and original SQL text. `sqlite3_expanded_sql()` substitutes
bound values as SQL literals using SQLite's tokenizer and value formatter.
The library also contains the default
system-backed allocation routines from `src/mem1.c`
and `src/malloc.c`. `SQLITE_CONFIG_MALLOC` can replace the callback table,
`SQLITE_CONFIG_GETMALLOC` returns it, and the `SQLITE_ZERO_MALLOC` build profile
selects the upstream all-failing allocator callbacks. The public connection
layer now opens and closes one main
database through `sqlite3_open()`/`sqlite3_open_v2()` and exposes error,
system-error, offset, mutex, database-name lookup, pager filename, read-only, autocommit-state,
transaction-state, and temporary-store-mode APIs, along with `sqlite3_set_errmsg()`,
extended-result-code configuration, named `sqlite3_get_clientdata()` and
`sqlite3_set_clientdata()` entries with destructor ownership, write-transaction
cache flushing, and main-pager memory release. `sqlite3_setlk_timeout()` keeps
the default build's range check and success result; the optional set-lock
feature remains unsupported. `sqlite3_busy_handler()` and
`sqlite3_busy_timeout()` configure the callback used by B-tree pager locks.
`sqlite3_interrupt()` signals active VDBE execution through a separate
per-connection lock; the executor checks the flag between instructions.
Invalid connection handles are
reported through the configured log callback. `sqlite3_limit()` initializes and
updates all 15 per-connection limit classes. SQL length, value length, column count,
expression depth, compound SELECT terms, parser-stack growth, VDBE opcode
allocation, variable numbers, function arguments, and LIKE/GLOB pattern length
use the connection's configured limits. `SQLITE_LIMIT_ATTACHED` is checked by
ATTACH, and `SQLITE_LIMIT_TRIGGER_DEPTH` is enforced during trigger generation
and nested VDBE program entry. `SQLITE_LIMIT_SCHEMA` is checked as schema rows
are loaded. Sorter initialization caps worker tasks using
`SQLITE_LIMIT_WORKER_THREADS` and `SQLITE_MAX_WORKER_THREADS`. These paths build;
runtime behavior is unverified.
`sqlite3_compileoption_get()` and `sqlite3_compileoption_used()` report the
sorted FreeBASIC build-profile options. `ENABLE_URI_00_ERROR` appears only in
builds compiled with `SQLITE_ENABLE_URI_00_ERROR`; the strict URI profile passes
uri2.test 22/22 and uri.test 99/99.
Main, temp, and attached schema slots receive initialized schema hash
containers. `sqlite3InitOne()` reads each database's `sqlite_schema` rows and
passes them through the init callback that builds table, index, and trigger
objects. Schema loading and reload behavior remain unverified at runtime.
`sqlite3ReadOnlyShadowTables()` checks defensive mode against VDBE execution
and virtual-table synchronization state.
The TEMP trigger-presence helper is in `sqlite3_trigger_helpers.bas`.
`sqlite3_filename.bas` allocates and frees the pager's packed VFS filename
layout and exposes its database, journal, WAL, and URI parameter segments. When
`SQLITE_ENABLE_8_3_NAMES` is enabled, it also applies SQLite's optional short
suffix rewrite to journal, WAL, and shared-memory filenames.
`sqlite3GetBoolean()` handles SQLite's shared boolean spellings for URI and
PRAGMA values. `sqlite3_uri.bas` parses `file:` URIs for both
`sqlite3_open_v2()` and `ATTACH`, including path escapes, VFS, cache, and
access-mode parameters. `sqlite3_config.bas` implements the
pre-initialization `SQLITE_CONFIG_URI`, `SQLITE_CONFIG_MALLOC`, and
`SQLITE_CONFIG_GETMALLOC` options, the SINGLETHREAD, MULTITHREAD, and SERIALIZED
mutex modes, `SQLITE_CONFIG_PAGECACHE`, default lookaside settings,
`SQLITE_CONFIG_MEMSTATUS`, `SQLITE_CONFIG_PCACHE_HDRSZ`, and
`SQLITE_CONFIG_MEMDB_MAXSIZE` for the memory-database VFS when deserialize
support is enabled. The memory layer
routes allocation, reallocation, sizing, and shutdown through the configured
`sqlite3_mem_methods`, with the system allocator as its default. `SQLITE_CONFIG_LOG`
and `sqlite3_log()` use the configured callback and fixed-size stack buffers.
The formatter blocks scratch-buffer growth for no-allocation accumulators,
including the logger. `SQLITE_CONFIG_PCACHE` now returns its documented no-op
success, while `SQLITE_CONFIG_GETPCACHE` returns `SQLITE_ERROR`. The
`SQLITE_CONFIG_ROWID_IN_VIEW` case reports zero when the compatibility feature
is absent and updates stored-view visibility flags when
`SQLITE_ALLOW_ROWID_IN_VIEW` is enabled. Under
`SQLITE_ENABLE_SORTER_REFERENCES`, `SQLITE_CONFIG_SORTERREF_SIZE` now sets the
threshold used to mark untyped BLOB columns for sorter references. The default
and combined sorter-reference/rowid-in-view builds pass with zero unresolved
SQLite symbols; runtime behavior is unverified.
`SQLITE_CONFIG_WIN32_HEAPSIZE` now writes the shared heap-size setting
consumed by the Windows allocator. The config and allocator modules compile
with `SQLITE_OS_WIN` and `SQLITE_WIN32_MALLOC` enabled. The default library
build passes; native Windows runtime behavior is unverified.
`SQLITE_OMIT_DESERIALIZE` now follows upstream source omission: the build
excludes the memory VFS, both serializer implementations, and the retained
C2FB helper candidates from `memdb.c`; those modules also carry source-level
guards. C2FB emits compile-time guards around the serializer extension-table
slots so those entries remain NULL. Release and debug omit-profile libraries
build with no exported `sqlite3_serialize`, `sqlite3_deserialize`, or
`sqlite3MemdbInit` symbols. A
loaded C extension confirmed that both slots are NULL; the default profile
retains both slots, and a C ABI smoke serialized a database, deserialized it
into a second connection, and read the stored row in release and debug builds.
`SQLITE_CONFIG_MEMDB_MAXSIZE` also returns `SQLITE_ERROR` in the omit profile,
matching `src/main.c`. The existing C2FB suite passes 10,754 behavior
comparisons in each of its native and GCC backend runs.

Build the omitted profile with:

```sh
make -C fb_src TARGET=build/libsqlite3-fb-omit-deserialize.so \
  FB_DEFINE_FLAGS='-d SQLITE_OMIT_DESERIALIZE=1'
```
FROM-subquery rowid visibility also follows `SQLITE_CONFIG_ROWID_IN_VIEW`.
The resolver applies SQLite's view/base-table rowid candidate precedence and
mode 2 resolves view rowids to `NULL`. The SELECT optimizer blocks unsafe
`rowid IS NULL` predicate pushdown, and declaration-type lookup leaves view
rowid metadata unset without indexing before the result list. Default, mode-1,
and mode-2 builds pass with zero unresolved SQLite symbols; runtime SQL
behavior remains unverified.
`sqlite3_open16()` converts native UTF-16 filenames and selects the main
schema encoding before schema loading. The UTF-16 prepare, prepare-v2, and
prepare-v3 APIs share the bounded UTF-16-to-UTF-8 parser path and map the tail
pointer back to the input encoding. Release and debug C ABI smokes opened a
UTF-16 database, checked its encoding, used all three prepare variants, and
registered a UTF-16 custom collation that ordered rows correctly after reopen.
`sqlite3_hooks.bas` stores trace, profile, commit, rollback, update, and
optional pre-update callbacks under the connection mutex. The VDBE dispatches
statement trace callbacks from OP_Init/OP_Trace and profile callbacks when a
step completes or the statement is reset or finalized. Main-B-tree commits
and VDBE rollback paths invoke commit and rollback hooks. Successful rowid-table
Insert/Delete opcodes invoke the update hook with the database and table names.
With `SQLITE_ENABLE_PREUPDATE_HOOK`, OP_Insert and OP_Delete invoke the
registered pre-update callback before changing the B-tree row. The dispatcher
distinguishes insert, update, and delete, supplies the update register for new
values, and supports WITHOUT ROWID no-op insert notifications. Default and
pre-update-enabled library builds pass with zero unresolved SQLite symbols;
the two upstream VDBE callback call sites are both represented. Runtime callback
behavior remains unverified.
`sqlite3_collation.bas` stores per-connection collation sequences, registers
BINARY, ASCII-only NOCASE, and RTRIM, and exposes the UTF-8/UTF-16 registration
and collation-needed APIs. `sqlite3ExprCollSeq()` resolves explicit COLLATE
nodes and declared column collations from the table schema, then passes those
sequences to expression comparison code. Broader planner and index-codegen
collation integration remains incomplete.
Per-connection status handles all 14 public `SQLITE_DBSTATUS_*` operations.
Lookaside usage and high-water reset now include both large and 128-byte slot
pools. Runtime status behavior remains unverified. Windows mutex callbacks
have since been ported; their native Windows runtime behavior remains
unverified, and optional OSTRACE messages are not ported.
Process-wide status counters, serialized automatic initialization,
and Unix pthread/no-op mutex APIs are implemented. `sqlite3ThreadCreate()` and
`sqlite3ThreadJoin()` use pthreads in thread-safe builds and run the callback
synchronously when threading is disabled or pthread creation fails. The
single-thread debug mutex profile tracks allocation type and enter/leave counts;
the release profile retains the no-op marker mutex.
Case-insensitive string comparison and 8-bit hashing, the public LIKE/GLOB
matching APIs, and the SQL `like()`/`glob()` callbacks from `src/util.c` and
`src/func.c` are also ported. Bounded string length, in-place dequoting, and
Token initialization helpers from `src/util.c`, plus the public
`sqlite3_errstr()` API and per-connection error set/clear and formatted-message
helpers from `src/util.c`, are ported as well. Build with `make -C fb_src`; the
shared library is written under `fb_src/build/`.

The pager and B-tree bitmap primitive from `src/bitvec.c` is ported, including
its compact bitmap, sparse hash, recursive subdivision, and mutation paths.
Its debugger display and built-in test-program runner are intentionally left
with the upstream test and debug support.

The generic case-insensitive hash table from `src/hash.c` and its internal
structure layouts from `src/hash.h` are ported. Hash growth remains
opportunistic: an allocation failure leaves lookups on the existing table or
linear list, matching SQLite's non-fatal rehash behavior.

The database-aware allocator paths from `src/malloc.c` now include per-connection
OOM latching, lookaside-aware non-null free entry points, pnBytesFreed accounting,
and a two-size lookaside pool with large slots and 128-byte slots. Reallocation
can copy a lookaside allocation into a larger heap block using the original slot
size.
The benign-allocation callbacks
from `src/fault.c` are in `sqlite3_fault.bas`. Unix worker creation and join
from `src/threads.c` are in `sqlite3_threads.bas`; single-thread builds and
pthread creation failures run worker callbacks synchronously. The public
`sqlite3*` handle is
opaque, so `sqlite3_db_types.bi` defines the FreeBASIC port's private connection
state. `src/rowset.c` is ported on top of that allocator, including batch tests,
tree merging, and sorted extraction.

`sqlite3_status()`, `sqlite3_status64()`, `sqlite3_memory_used()`, and
`sqlite3_memory_highwater()` are backed by synchronized counters. Heap
allocation and reallocation update memory-used, allocation-count, and largest
request values. The deprecated `sqlite3_memory_alarm()` ABI remains a no-op.
Public malloc and realloc entry points run automatic initialization unless
`SQLITE_OMIT_AUTOINIT` is selected.
Soft and hard heap-limit APIs update allocator state, the hard limit is enforced
by malloc/realloc, and `sqlite3HeapNearlyFull()` reports the soft-limit state.
`sqlite3_release_memory()` returns zero unless SQLite is built with
`SQLITE_ENABLE_MEMORY_MANAGEMENT`. That optional profile evicts clean,
unpinned pages from the shared page-cache LRU and its full library profile
builds. A negative byte request passes through as SQLite's release-all
sentinel. `SQLITE_CONFIG_PAGECACHE`
preserves the caller's buffer and slot settings, then applies them during
initialization through `sqlite3PCacheBufferSetup()`. Heap fallback allocations
flow through the page-cache overflow and size counters; caller-owned fixed
slots are not returned by `sqlite3_release_memory()`. Runtime allocator and
page-pool behavior is unverified.
`sqlite3_db_status()` and `sqlite3_db_status64()` report/reset lookaside
counts, page-cache memory/hits/misses/writes/spills across attached databases,
deferred foreign-key state, and temporary-buffer spill bytes. The
`SQLITE_DBSTATUS_STMT_USED` case estimates statement-owned bytes by walking VDBEs
under `pnBytesFreed` mode with lookaside temporarily disabled, without unlinking
statements or running value destructors. VDBE deletion also applies
opcode/argument-mask filtering to auxdata
and invokes its destructor callbacks. The `SQLITE_DBSTATUS_SCHEMA_USED` case
counts schema hash storage and measures table/trigger allocations through the
same non-destructive `pnBytesFreed` path while all attached B-trees are entered.
Runtime status behavior is unverified.

The page-reference and dirty-list layer from `src/pcache.c` is implemented in
`sqlite3_pcache.bas`, with its pager-facing layouts in `sqlite3_pcache.bi`.
The current default backend uses a page-number hash table and a clean-page
LRU. It supports page fetch, release, dirty-list ordering, spill callbacks,
rekeying, truncation, cache sizing, shrink, and fixed-slot allocation through
`sqlite3PCacheBufferSetup()`. The backend can recycle clean, unpinned pages
across caches when their allocation sizes match, and allocates a per-cache bulk
page block when a cache first needs storage. `SQLITE_CONFIG_PCACHE2` selects a
caller-supplied method table. The sanity check verifies dirty-list membership,
back-links, and page-state flags. Cache operations rely on the owning pager to
serialize access. Table-backed SELECT and DML paths now reach the pager and
B-tree layers; runtime behavior remains unverified.

The public `sqlite3_file`, `sqlite3_io_methods`, and `sqlite3_vfs` layouts and
the OS dispatch wrappers from `src/os.c` are in `sqlite3_vfs.bi` and
`sqlite3_os.bas`. The VFS list supports registration, lookup, and removal under
SQLite's main mutex. `sqlite3_initialize()` calls `sqlite3OsInit()`, which
installs a Linux x86-64 VFS from
`sqlite3_os_unix.bas` with positioned reads and writes, file synchronization,
truncation, path handling, randomness, time, POSIX database byte-range locks,
and shared-memory mapping and lock methods. The Linux VFS and public extension
loader implement dynamic library open/symbol/close dispatch; runtime extension
loading remains unverified, and unsupported extension API entries stay null.
Syscall overrides, file-fetch mmap, and other Unix targets remain outstanding.
WAL read/write and checkpoint code now builds; runtime and cross-platform
behavior remain unverified.

The SQLite-level PRNG from `src/random.c` is in `sqlite3_random.bas`. It
implements ChaCha20 block generation, buffered byte consumption, VFS seeding,
serialized access through SQLite's static PRNG mutex, and state save/restore
hooks used by `sqlite3_test_control()`.

The pager now has its state layout and a read path in `sqlite3_pager.bi` and
`sqlite3_pager.bas`. It opens a VFS-backed database, creates its page cache,
acquires a shared database lock, reads and zero-fills pages, and releases page
references. It parses and replays hot rollback journals before returning the
database image, including page checksums and super-journal presence checks.
It can create rollback journals, save original page images before mutation,
protect all pages sharing a larger disk sector, flush database pages after
syncing the journal, spill unreferenced dirty pages after an exclusive-lock
upgrade, report cache hit/miss/write/spill counts, commit or roll back a
single-file transaction, and
capture or restore statement savepoints through a sub-journal. The sub-journal
uses linked memory chunks, keeps up to the configured statement-journal limit
in memory, and can spill to a temporary VFS file. Page move/rekey support is
now present for B-tree relocation. Full multi-database super-journal
completion and mmap page access remain outstanding. WAL frame and checkpoint bodies
compile, but runtime behavior is unverified.

`sqlite3_memjournal.bas` implements the journal's `sqlite3_file` methods. Its
VFS spill path saves the memory-journal state, opens the real file, and copies
each chunk before releasing the memory copy. If opening or copying fails, the
original memory journal is restored so pager rollback can still read it.

`sqlite3_memdb.bas` implements the memory database VFS. It stores each database
as a resizable byte array with a 1 GiB default limit, implements SQLite's
shared/reserved/exclusive lock transitions, and implements xFetch/xUnfetch for
fixed-size stores. Names beginning with `/` share one store across open handles;
other names receive a private store. Dynamic loading, time, randomness, and
sleep requests pass through to the underlying VFS. `sqlite3_serialize()` and
`sqlite3_deserialize()` are implemented in
`sqlite3_bulk_memdb_serialization.bas`; they copy pager pages or attach a
caller-owned buffer to the memory store. Release and debug C ABI smokes cover
serialization, deserialization, ownership transfer, and row readback. Other
memory-VFS sharing and locking behavior remains unverified.

The first B-tree layer is in `sqlite3_btree.bi` and `sqlite3_btree.bas`. It
opens and closes a single B-tree handle through the pager, binds pager pages to
`MemPage` state, validates page headers, cell offsets, and freeblock chains,
decodes table and index cells, and calculates local versus overflow payload
sizes. It lazily allocates one shared schema blob per `BtShared` and invokes
its registered destructor when the B-tree closes. It exposes the pager handle,
clears write-transaction content tracking,
and releases temporary page space. The freelist content bitvec marks leaf pages
freed during a write transaction, so reusing them preserves original page bytes
for rollback; the map is cleared when the write transaction ends. Helper
Free-page release accepts a held page or checks the pager cache first; it reads
an uncached page only when secure-delete or trunk-page conversion needs the
contents. Helper routines construct local leaf cells and write overflow payload
chains, reusing freelist pages or extending the
database when auto-vacuum is off. A companion routine releases bounded
overflow chains back to the freelist. The module also has page-local allocation/defragmentation, cell
removal, leaf insertion, deferred overflow-cell queuing, right-edge table-leaf
split and root-expansion helpers, sibling selection/divider detachment,
CellArray assembly and size caching, ordered-cell page rebuild/insert/free/edit
helpers, sibling-page distribution planning and application for the
non-auto-vacuum path, including safe page-edit order, parent divider updates,
root collapse, and unused-page reclamation, plus same-size payload overwrite
primitives. `sqlite3BtreeInsert()` now builds and replaces table/index cells,
saves other cursors on the same root, and connects the balance steps through
parent-overflow recursion. `sqlite3BtreeDelete()` frees cell overflow chains,
replaces internal index separators, balances underfull pages, and preserves
cursor positions when requested. Checked payload reads and incremental-blob
range writes cover local and overflow-page content. B-tree entry counts,
row-count estimates, and preformatted row transfer support VDBE operations.
The cursor restore path re-seeks saved table and index positions. Cache/spill
sizing, pager flags, page-size/reserve controls,
secure-delete and auto-vacuum mode accessors, cursor-state queries, cursor
pinning/hints, transaction/backup status, and database format-version setting
are also implemented. Cursors can be tripped after rollback, and a table
can be cleared through its open cursor. Pointer-map lookup and I/O, allocation
and free-page marking, overflow-owner entries, child-map refresh after page
rebuilds, parent-pointer repair, and page-relocation primitives are integrated.
Incremental vacuum and the default full auto-vacuum commit/truncate path are
also implemented. Auto-vacuum root creation and drop relocation now preserve
root-page ordering and pointer-map entries. Custom vacuum-page callbacks and
shared-cache B-tree mutex entry/leave helpers are in `sqlite3_btmutex.bas`;
attached-B-tree lock ordering and shared-cache table locks remain. The SQL
VACUUM command now reaches `sqlite3RunVacuum()` and the B-tree replacement path.
A single handle
can start read/write
transactions, commit or roll them back, access page-one
metadata, create empty table/index root pages when auto-vacuum is off, traverse
metadata, create roots with auto-vacuum page placement, traverse table/index
cursors, search integer rowids, and search unpacked index keys through the VDBE
record comparator. It can read payloads from overflow chains, save cursor
positions, clear a table/index tree, and drop roots while keeping the
auto-vacuum root range compact.

The VDBE `Mem` cell layout and its NULL, integer, real, text/blob setters,
zero-blob, pointer, RowSet, move, copy, writable-buffer, UTF-16 BOM, B-tree
payload-read, and release paths are in `sqlite3_vdbe_mem_types.bi` and
`sqlite3_vdbe_mem.bas`. Bounded
UTF-8/UTF-16 integer parsing, decimal/hex integer token conversion, 32-bit
integer extraction, and the VDBE integer value, integerify, real clamp, integer
affinity, numeric affinity in `sqlite3_vdbe_affinity.bas`, and decimal-to-real
conversion helpers are also ported. The decimal parser and real renderer use
SQLite's power-of-ten tables and fixed-width multiplication path. UTF-8/UTF-16
translation, integer/real stringification, and value text/byte accessors are
implemented in `sqlite3_vdbe_mem_text.bas` and `sqlite3_vdbe_api.bas`. The public
value API also includes numeric accessors, pointer-type checks,
encoding/subtype/nochange/from-bind queries, duplication/freeing, and the
transient value-list allocator callback. Virtual-table context helpers report
unchanged columns and iterate packed right-hand-side values in a B-tree value
list. Statement time is cached on the VDBE for the duration of one execution.
Value-level affinity dispatch, numeric
type classification, numeric/text CAST helpers,
integer-versus-real comparison,
Mem NULL/numeric/TEXT/BLOB comparison, and record serial-type length/value
decoding, serial-type selection, and field payload encoding are implemented.
The `sqlite3_result_*` family now writes integer, real, NULL, pointer, subtype,
text, blob, zero-blob, and copied-value results into the VDBE output cell. It
also tracks result errors, destructor ownership, and output encoding through
the `sqlite3_context` prefix in `sqlite3_result.bi`; SQL-function invocation
is implemented for the statically registered `abs()`, `char()`, `instr()`,
`length()`, `octet_length()`, `lower()`, `upper()`, `hex()`, `unhex()`,
`random()`, `randomblob()`, `round()`, `sign()`, `substr()`, `unicode()`,
`zeroblob()`, `concat()`, `concat_ws()`, `replace()`, `trim()`, `ltrim()`,
`rtrim()`, `typeof()`, `quote()`, `unistr_quote()`, `unistr()`,
`sqlite_version()`, `sqlite_source_id()`, `sqlite_compileoption_used()`,
`sqlite_compileoption_get()`, `last_insert_rowid()`, `changes()`,
`total_changes()`, `subtype()`, `like()`, and `glob()` functions through
`OP_Function`. SQL `printf()` and `format()` use SQLite value arguments in the
shared formatter. The registered `nullif()` callback gets its collation from
`OP_CollSeq`; the supported tableless compiler also lowers `nullif()` directly.
LIKE pattern calls support the single-character ESCAPE argument;
infix LIKE, GLOB, and MATCH actions build function nodes with the C argument
order (pattern, value, optional ESCAPE), with `NOT` as an outer expression
node. Built-ins are indexed by SQLite's 23-slot function-name hash, and
overload selection scores argument counts and text encoding like
`matchQuality()` in `src/callback.c`.
The unchanged `func2.test` (99 tests), `func9.test` (17 tests), and `date.test`
through `date5.test` (10 tests combined) pass. `func9.test` covers Unicode
escapes, including `hex(unistr(\UFFFFFFFF))` returning `F7BFBFBF`. That test
exposed a byte lookup table declared as `ZString Ptr` and indexed as bytes;
the hex callback now uses `Const UByte Ptr`. A direct C probe verifies
`hex('abc')` returns `616263`. A separate C API probe registers and invokes a
custom scalar function successfully.
The unchanged `expr.test` (539 tests) and `expr2.test` (9 tests) also pass
with no failures or tracked allocation leaks. This run caught three port
mismatches: LIKE/GLOB returned `-1` for true, function error text was
discarded by the VDBE, and unary minus of the exact decimal 2^63 value
became REAL. The port now emits canonical 0/1 comparison results,
preserves scalar-function error text, and emits `INT64_MIN` for that
unary-minus case.
The `sqlite3_create_function()` and `sqlite3_create_function_v2()` APIs
register per-connection scalar and aggregate callbacks and invoke their destructor on
replacement, deletion, allocation failure, or connection close.
Scalar callbacks can retrieve and replace per-argument auxdata through
`sqlite3_get_auxdata()` and `sqlite3_set_auxdata()`; statement reset runs the
registered destructor callbacks.
`sqlite3_create_function16()` converts its UTF-16 function name to UTF-8 before
registration. `sqlite3_progress_handler()` calls the registered C callback at
the requested VDBE instruction interval and interrupts execution when it asks
to stop. Aggregate context and step/final dispatch support the built-in
`count()`, `sum()`, `total()`, `avg()`, `min()`, `max()`, `group_concat()`,
and `string_agg()` functions and direct aggregate calls in tableless, single-row
SELECTs. `group_concat()` uses the separator from each non-NULL step row.
Multi-argument `min()` and `max()` use the scalar comparison callbacks.
Table-backed aggregates without GROUP BY use the aggregate analyzer and
accumulator path for basic scans; grouping and aggregate modifiers remain
unsupported. Built-in window
aggregate callbacks, SELECT rewriting, and VDBE frame-code generation now have
FreeBASIC bodies. The default thread-safe library build passes, but window
runtime behavior remains unverified.
`sqlite3VdbeRecordPack` assembles a record blob from already-affinitized Mem
cells; `sqlite3VdbeRecordUnpack` decodes bounded record data into Mem fields.
SQLite varint readers/writers and fixed-width big-endian integer helpers are in
`sqlite3_varint.bas`. `sqlite3VdbeRecordCompare` compares record keys through
Mem ordering and collation callbacks. The executor applies OP_MakeRecord
affinities, packs records, reads table columns, probes index keys with Found,
NotFound, and NoConflict, inserts and deletes index entries, and extracts the
rowid from an index record. Per-register affinity and table-backed aggregate
grouping are wired into the executor and SELECT compiler. Dispatch cases now
exist for all generated opcode labels; semantic behavior remains unverified.

`sqlite3_vdbe_core.bi` now defines the common-build `Vdbe`, `VdbeOp`, and
`VdbeOpList` layouts. `sqlite3_vdbe_core.bas` creates a builder with its initial
`OP_Init`, retains statement SQL, emits integer, real, string, jump, and opcode
list instructions, grows the opcode array, tracks main-B-tree dependencies,
and links owned subprograms for deletion.
It handles transient/static/dynamic string and integer P4 values, stores result
column names, and implements operand-patching and jump-target helpers.
`sqlite3_opcodes.bi` now includes
generated jump-opcode metadata used to adjust relative P2 targets in opcode
lists. Parse-schema setup and coroutine cleanup are included for the single
main database represented in the current connection layout.
`sqlite3VdbeMakeReady()` allocates register, variable, argument, and
cursor-pointer arrays, resolves labels, and rewinds a prepared VDBE into READY
state. In `SQLITE_DEBUG` builds, the core checks opcode reservation,
no-result-row, and abort-journal invariants. Its abortability checker walks
the main opcode program and reachable P4 subprograms. `sqlite3_vdbe_exec.bas`
dispatches main-database transactions, metadata-cookie reads/writes, ANALYZE
statistics reloads, database-root destruction, schema-entry reloads, and
in-memory DROP cleanup,
OpenRead/OpenWrite/ReopenIdx/OpenEphemeral/OpenAutoindex/OpenDup/SorterOpen/OpenPseudo/Close,
Rewind/Sort/SorterSort/Last/SeekEnd/Next/SorterNext/Prev, InitCoroutine/Yield/
EndCoroutine, CollSeq initialization, SeekHit bounds, IfEmpty/IfNotOpen,
Pagecount/MaxPgcnt, IncrVacuum, strict-table TypeCheck, ResetCount, SoftNull,
subtype get/set/clear, ElseEq, sorter insert, compare, row-key, and
reset operations, vector
OP_Compare/OP_Jump with register permutations and KeyInfo collation ordering, table
SeekLT/LE/GE/GT and SeekRowid/NotExists, Rowid/IdxRowid,
DeferredSeek/FinishSeek, NullRow and cursor tests, Column, Count/Clear, RowData,
CreateBtree, NewRowid, Sequence/MemMax, table and index Insert/Delete,
Found/NotFound/NoConflict, index SeekLT/LE/GE/GT and IdxLE/GT/LT/GE, MakeRecord,
Gosub/Return, BeginSubrtn, AggInverse/AggValue callbacks, jumps,
integer/real/string and bound values,
register copies/moves, affinity, arithmetic, bitwise and shift operations,
comparisons, boolean logic, IS TRUE/FALSE, Cast/RealAffinity, Concat, OffsetLimit,
ZeroOrNull, OP_Function/OP_PureFunc calls, integer checks, NULL ranges,
RowSetAdd/Read/Test, FilterAdd/Filter bloom-filter checks, Destroy, ParseSchema,
DropTable/DropIndex/DropTrigger, foreign-key counter/jump/check opcodes, result rows,
HaltIfNull constraint checks, and halt. Autocommit toggles,
named-savepoint bookkeeping, and statement savepoints for writes inside explicit
transactions are represented. Coroutine transfers keep the resume address in
the designated VDBE register; `EndCoroutine` returns to the caller's P2 target.
`sqlite3_step()` drives the loop.
Reset can halt a partially stepped VDBE before it is reused or finalized.
`sqlite3_vdbe_trace.bas` expands bound SQL and dispatches statement and profile
callbacks through the registered connection hooks.
The VDBE core tracks change-count and expiration flags; successful execution
records the statement and cumulative change totals through
`sqlite3VdbeSetChanges()`. It resets the step result, formats VDBE-owned errors,
and checks immediate/deferred foreign-key counters at halt. INSERT, UPDATE, and
DELETE generation call the foreign-key check/action helpers; INSERT and UPDATE
also generate NOT NULL, CHECK, and uniqueness constraint bytecode. Constraint
runtime behavior remains unverified. The core exposes the database handle,
prepare flags, and subprogram state.
`sqlite3_vdbe_cursor.bi` defines the VdbeCursor prefix and
`sqlite3_vdbe_cursor.bas` allocates its variable-sized record metadata and
embedded B-tree cursor storage. Sorter initialization, writes, merging, row-key
lookup, and iteration are connected to sorter opcodes; ephemeral cursors use
transient B-trees; OpenDup creates independent cursors over shared ephemeral
tables. Bloom filter operations reuse the C2FB-translated hash routine.
The Bloom-filter path was exercised with a 20-row IN-subquery: FilterAdd and
Filter were emitted, ten matches produced ten filter hits and ten misses, and
finalizing the statement left no lookaside slots in use. A NOCASE comparison
correctly skipped the filter. Release and debug probes passed. The foreign-key
cascade probe also exercised RowSetAdd/RowSetRead and removed the expected child
rows. `sqlite3SelectCompileFromClause()` now applies
`fromClauseTermCanBeCoroutine()` and sends eligible FROM-subqueries through the
SRT_Coroutine path; the WHERE loop yields each row and rewrites column reads to
the coroutine's result registers. A sorted-LIMIT C API probe returned the five
expected values with two InitCoroutine ops, two Yield ops, and one EndCoroutine
op. Default and NOT MATERIALIZED single-use CTEs also used coroutines; an
AS MATERIALIZED CTE and a multiply referenced default CTE stayed on the shared
ephemeral-table path and returned the expected rows. Disabling SQLITE_Coroutines
through SQLITE_TESTCTRL_OPTIMIZATIONS retained the same result and selected
materialization. These CTE cases passed in release and debug builds.
A LEFT JOIN with an ordered-LIMIT derived table stayed materialized and retained
the unmatched row with NULL columns in both builds.
PMA sorter runtime is now verified by the probes described above.
DDL runtime behavior remains unverified. Destroy uses the existing B-tree drop
routine, updates schema root pages after autovacuum movement, and resets the
affected schema if a later error rolls the operation back. ParseSchema uses the
ported initializer callback for filtered schema reloads and `sqlite3InitOne`
for full schema reinitialization. `OP_ColumnsUsed` records its 64-bit mask when
enabled, and debug `OP_Abortable` checks use the VDBE journal invariant.
Virtual-table cursors and attached-database coordination are represented, and
the executor has dispatch cases for all 192 generated opcodes. Complete
halt/error parity and parts of SQL compilation remain incomplete.
`sqlite3_prepare.bas` implements the UTF-8 prepare APIs for the current parser
subset. It copies the input buffer for bounded parsing, stops after the first
compiled statement, maps the parser tail back to the caller's buffer, and keeps
SQL text for v2/v3 statements. The parser context is freed after compilation
and detached from the ready VDBE.
`sqlite3_vdbe_stmt.bas` exposes the connection handle, retained SQL, EXPLAIN,
read-only, busy-state, statement-list, reset/finalize, and bind-parameter metadata APIs. It also
logs NULL/finalized-statement misuse, supports parameter-name lookup, integer/real/NULL/text/blob/pointer/zeroblob
bindings, copy-from-value binding, clearing all bindings, and transferring
bindings between statements on the same connection. Statement counters
can be read or reset; MEMUSED currently accounts for opcode storage, P4 values,
SQL text, errors, and result-column names. Reset/finalize clean VDBE resources
and close zombie connections after their last statement. Full frame/auxiliary
allocation accounting remains outstanding. The module also exposes result
column count, data count, type/value/text/blob accessors, names, declared types,
and optional database/table/origin metadata from the current result-row state.

`sqlite3_util_numeric.bas` adds the standalone integer helpers from `src/util.c`:
checked signed arithmetic, unsigned decimal parsing, logarithmic row estimates,
NaN/overflow classification, hex digit and blob decoding, byte swapping, and
packed VList name mappings.
`sqlite3_where_helpers.bas` contains `src/where.c`'s standalone `estLog` cost
conversion and `allConstraintsUsed()` virtual-table constraint helper, kept
separate from the still-unported query planner.
`sqlite3_date_helpers.bas` adds `validJulianDay()` with the 64-bit upper bound
used by SQLite's internal date representation.
`sqlite3_pragma.bas` also includes the one-column text result helper used by
PRAGMA implementations.
`sqlite3_snapshot.bas` implements snapshot get/open/recover/compare/free when
`SQLITE_ENABLE_SNAPSHOT` is enabled. The snapshot profile builds; runtime
behavior remains unverified.
`sqlite3_backup_types.bi` preserves the private backup-context field layout;
`sqlite3_backup.bas` returns the remaining and source page counts, finalizes
backup handles, restarts page progress after external changes, and copies
modified pages through the pager callback. `sqlite3_backup_init()` allocates
state and resolves named B-trees. `sqlite3_backup_step()` copies pages, handles
destination page-size rules, updates schema metadata, and commits the
destination. The VACUUM-specific `sqlite3BtreeCopyFile()` wrapper is now
available for its B-tree replacement stage. `sqlite3RunVacuum()` now performs
the temporary-schema rebuild, preserves selected database metadata, replaces
the B-tree for ordinary VACUUM, and writes a separate target for VACUUM INTO.
`sqlite3ParseObjectInit()` establishes the per-connection parse context used
when opening a named TEMP source or destination database.
`sqlite3_bulk_attachfix.bas` maps schema references in views, triggers, and
indexes to the database that owns them, rejects cross-database stored queries,
and walks trigger steps, CTEs, and expressions while preserving the parser's
error state.
`sqlite3_bulk_authctx.bas` pushes and restores `Parse.zAuthContext` around
authorization checks using the matching stack-owned context layout.
`sqlite3_bulk_create_view.bas` builds view metadata and copies the defining
SELECT into the schema. `sqlite3_bulk_finish_trigger.bas` validates and stores
trigger schema references and SQL text. `sqlite3_bulk_shadow_table.bas`
resolves a shadow table's virtual-table owner before delegating suffix checks
to its module. `sqlite3_bulk_start_table.bas` validates the schema and reserves
the table's schema row and B-tree root page. Final schema generation now has a
body in `sqlite3_bulk_create_table_repair.bas`; `sqlite3CreateIndex()` remains
an unresolved dependency. `sqlite3_bulk_objectname.bas` checks
reserved names and verifies schema-initialization object names.
`sqlite3_bulk39_main.bas` now closes zombie connections after all statements
and backup objects finish, releasing attached B-trees, schemas, collations,
virtual-table modules, extensions, and connection state. Function-registry
cleanup uses the port's `pUserFunctions` list and `sqlite3DbFunctionDestroy`;
both the hand written registry and generated `FuncDef.u` entries now release
the reference-counted destructor record. `window5.test` verifies the window
callback teardown path.
Mapping the private `sqlite3_backup` record in C2FB unlocked three more
compiler-clean bodies: `attachBackupObject`, `sqlite3_backup_finish`, and
`sqlite3BackupRestart`. The page-copy helper, pager update callback,
`sqlite3_backup_init()`, and the 269-line `sqlite3_backup_step()` routine were
ported alongside those candidates. The 49-line `sqlite3BtreeCopyFile()` helper
is now implemented; `sqlite3RunVacuum()` handles the B-tree rewrite and
temporary-database cleanup.
`sqlite3_pager.bas` also exposes SQLite's sector-size clamp, page-number,
cache-reference, backup-pointer, journal-mode safety, and exclusive-lock
helpers.

`sqlite3_straccum.bas` implements the bounded `sqlite3_str` buffer lifecycle:
append, growth, finish, reset, truncate, and inspection. It also routes a
too-large error into an active parser context through `sqlite3ErrorToParser`.
`sqlite3_printf.bas` adds integer, floating-point, string, SQL quote, and JSON
format conversions, along with `sqlite3_str_vappendf`, `sqlite3_str_appendf`,
`sqlite3_mprintf`, `sqlite3_vmprintf`, and bounded snprintf APIs. The internal
`SQLITE_PRINTF_SQLFUNC` argument mode backs the registered SQL `printf()` and
`format()` functions, and `sqlite3RecordErrorOffsetOfExpr()` records expression
token offsets. Internal `%S` and expression form `%#T` formatting remain
outstanding. The log renderer uses stack buffers, and the debug formatter uses
the C runtime output stream. Token byte offsets and the public
`sqlite3_error_offset()` accessor are connected to the syntax parser.
Reference-counted string allocation, resize, and release operations are in the
same module.

`sqlite3_json_string.bas` ports the JSON accumulator lifecycle, byte appends,
quoted-string escaping, and control-byte escapes, using the existing
reference-counted string allocator. It retains the 100-byte inline buffer
before growing to dynamic storage and reports allocation and nesting errors
through the SQL function context. `sqlite3_json_hex.bas` ports hexadecimal
conversion and escape-shape checks.

`sqlite3_json_parse_state.bas` defines the JSONB parse object lifecycle and
four-entry per-statement translation cache stored through VDBE auxdata. JSON
text parsing and JSONB validation use that state.
`sqlite3_json_parse_arg.bas` selects validated JSONB input or parses text,
promotes retained text to reference-counted storage, and manages editable cache
copies.
`sqlite3_json_valid.bas` implements and registers the one- and two-argument
`json_valid()` overloads, including JSON5 and superficial/strict JSONB flags.
`sqlite3_json_query.bas` implements JSON path lookup and the `json_type()` and
`json_array_length()` callbacks. JSONB path edits back `json_insert()`,
`json_replace()`, `json_set()`, and `json_remove()`; merge-patch and array
insertion use the same edit path. The unchanged suites json102.test through
json109.test, json501.test, json502.test, and jsonb01.test now pass 45,711
enabled assertions with no tracked leaks. This includes 45,001 randomized
JSON and JSON5 invariant assertions in json106.test, plus JSONB path edits,
array insertion, pretty output, and json_each/json_tree queries. The temporary
runner loads the upstream randomjson and strdup test extensions dynamically;
test sources remain unchanged.
`sqlite3_json_values.bas` converts SQL scalar values into JSON output and
implements the one-argument `json()`/`jsonb()` callbacks plus `json_quote()`,
`json_array()`, and `jsonb_array()`.
`sqlite3_json_return.bas` transfers generated output as text or JSONB and keeps
reference-counted storage and cache ownership consistent. `jsonReturnParse()`
selects JSONB blob output or canonical JSON text from a parsed value.
`sqlite3_json_blob_text.bas` renders JSONB scalars, strings, arrays, and objects
back into JSON text.
`sqlite3_json_blob.bas` provides bounded JSONB buffer growth, node append, and
payload-size patching for the parser and later edit operations.
`sqlite3_json_payload.bas` decodes compact and extended node headers and checks
payload spans against both the stored blob length and pending edit size.
`sqlite3_json_validate.bas` recursively validates JSONB scalar payloads, string
escapes, arrays, and object key/value pairs; `jsonArgIsJsonb()` uses it to
distinguish valid JSONB blobs from text-compatible blobs.
`sqlite3_json_text_parse.bas` recursively translates JSON/JSON5 strings,
numbers, arrays, objects, and keywords into JSONB nodes. The text-to-JSONB
parser and completion wrapper are ported and called by the argument dispatcher.
`sqlite3_json_text_scan.bas` recognizes JSON5 whitespace/comments and decodes
one bounded escape sequence, including Unicode surrogate pairs and continued
lines. `sqlite3_json_labels.bas` compares raw UTF-8 labels with escaped JSON
labels. Object constructors, JSON aggregates, pretty rendering, and the
`json_each`/`json_tree` table-valued functions have registered callbacks.
Their runtime behavior remains unverified.

`PORTING_INVENTORY.csv` tracks every `src/` input listed in SQLite's core
`SRC` list, plus generated parser/opcode/PRAGMA inputs and the later test-runner
bridge. It records port status and upstream line count by source file.
`PORTING_FUNCTIONS.csv`, generated by `fb_tools/c2fb/c2fb.bas functions src`,
indexes 3,263 C function-definition rows across 80 in-scope source files with
line spans and rough size classes. Alternate definitions behind preprocessor
conditions share one row. Its initial status column is `Needs mapping` so newly
indexed functions can be reconciled as the port proceeds. Run
`make -C fb_src reconcile-function-status` to mark rows with a matching
FreeBASIC body; this reports body presence, not semantic completeness.
The inventory excludes SQLite extensions and test implementation files. The
tests themselves remain upstream and in their current languages. SQLite's
engine is over 200,000 source lines, so this is a staged port of its subsystems,
not a small conversion of a handful of files.

The existing tests remain in their current languages. SQLite's `testfixture`
build uses private implementation symbols, while the Tcl extension path uses
the public `sqlite3_*` API. Once the FreeBASIC library implements enough of
that API, the Tcl extension can be linked against it and the existing Tcl
regression scripts can exercise the port. Reusing `testfixture` will also
require a deliberate compatibility layer for its private test hooks.

The remaining implementation order is:

1. Custom allocator configuration, per-connection status, and process initialization.
2. VFS and operating-system interfaces, including the Windows mutex backend.
3. Remaining Lemon semantic actions and destructors, then name resolution.
4. Table-backed SELECT, DDL/DML compilation, and the virtual database engine.
5. B-tree, pager, rollback journal, and WAL.
6. Remaining public API coverage, test hooks, and optional extensions.

The source files `sqlite3_tokens.bi`, `sqlite3_keyword_data.bi`,
`sqlite3_character_classes.bi`, `sqlite3_parser_tables.bi`,
`sqlite3_parser_rule_ids.bi`,
`sqlite3_api_constants.bi`, `sqlite3_fp10_tables.bi`, `sqlite3_opcodes.bi`,
`sqlite3_global_data.bi`,
`sqlite3_api_declarations.bi`, and
`sqlite3_internal_api_declarations.bi` are generated.
`fb_tools/sqlite_codegen/`
contains the FreeBASIC converter that reads Lemon's `parse.h`, SQLite's
generated `keywordhash.h`, parser tables, the selected grammar rule and symbol
names used by semantic actions and stack cleanup, the opcode table, the ASCII
character table in `src/tokenize.c`, and the ASCII lowercase map in
`src/global.c`. IDs are regenerated from Lemon's name tables so grammar
changes do not silently redirect handlers or destructors.
Run `make -C fb_src regen-generated` to regenerate those includes after
changing the SQLite grammar or tokenizer tables.

`fb_tools/c2fb/` contains a FreeBASIC C-header converter. It emits reusable
declarations for the public API and internal functions, 493 public numeric
constants from `sqlite.h.in`, and the power-of-ten words used by `sqlite3AtoF`.
It preserves the parser's `Token` value layout in the generated internal ABI
declarations and reports variadic declarations and unsupported constants.
It emits C variadic prototypes as FreeBASIC `...` declarations.
Unknown typedef scalars are emitted as C `int` and need review before use.
Its `translate-simple-tree` mode emits candidate bodies for a conservative
subset of local declarations, assignments, conditionals, loops, returns, and
selected pointer and structure expressions. The expression parser preserves C
grouping, integer boolean values, known arithmetic types, scalar casts, ASCII
character constants, and nested conditional expressions. It skips conditional
C branches and any function containing unsupported statements or types.
It also handles typedef chains, known call signatures, forward/private helpers,
static string literals, primitive size queries, multiple declarations, lexical
scopes, fixed local arrays, and loop exits or named jumps. The port's declared
array fields select the correct FreeBASIC indexing syntax. Missing structure
fields and opaque child-pointer layouts still need review or type mapping.
Run `make -C fb_src check-bulk-candidates` to generate a preprocessed batch and
write `fb_src/build/candidates/compile-report.csv` with compiler diagnostics.
Files with missing layouts or other compilation failures make the check return
a nonzero status. Review each candidate's layout and dependencies before
integration. `make -C fb_tools/c2fb test` compares the supported conversion
behavior against compiled C using both FreeBASIC backends.
Use `make -C fb_src bulk-candidate-files SOURCE_FILES='carray.c,vdbevtab.c'`
to regenerate a selected source batch without preprocessing the full tree.
Set `FEATURE_DEFINES` and `CANDIDATE_DIR` for the intended profile and output.
For wider debug branches, `bulk-candidate-files-loose` accepts the same source
selection and feature definitions while keeping callers with unconverted local
helpers. `C2FB_DISABLE_ASSERTS=1` suppresses expanded C assertions only in the
candidate preprocessor input; candidate files mark this and required checks
must be restored before integration. Use `check-bulk-candidate-files-loose`
with matching `FBC` feature flags to compile-screen the selected batch.
Regenerate declarations and constants with `make -C fb_src regen-api-declarations`.

FreeBASIC is also part of the work: port code will be used to exercise the
compiler, and reproducible compiler defects can be fixed in the compiler
checkout at `/home/jkfirth/fbc/src`. Before changing the compiler, reduce the
issue to a small FreeBASIC program and confirm at least one compiler defect:
valid FreeBASIC is rejected; backends disagree semantically; generated code
violates documented FreeBASIC behavior; an internal invariant is broken;
target or host behavior differs where the language requires consistency; or
the compiler crashes, corrupts state, or emits invalid output. Port-specific
assumptions belong in this tree.

The version string and source ID in `sqlite3_metadata.bas` describe the
upstream check-in represented by this checkout. Update them with the SQLite
version and source ID when rebasing the port.

For C ABI declarations, use FreeBASIC `Long` for C `int` and `LongInt` for
SQLite's 64-bit integer types. On the current 64-bit target, FreeBASIC
`Integer` is 64 bits and does not match SQLite's 32-bit `int` parameters.

<!-- end of README.md -->

The WAL read-transaction cluster now maps walIndexReadHdr(), walBeginShmUnreliable(), and walTryBeginRead(), then connects the C2FB-generated read-transaction entry points and lock teardown. The default thread-safe library build passes; WAL runtime behavior is unverified.

The WAL writer cluster now begins and ends writer transactions, restarts the WAL when reader marks permit it, encodes and writes frames, recomputes checksums after in-place changes, updates the wal-index, and handles rollback/savepoint state. The default thread-safe library build passes; WAL runtime behavior is unverified.

The WAL checkpoint cluster now builds a sorted iterator over frame pages, copies safe frames into the database, syncs checkpoint data, tracks backfill progress, and handles passive, full, restart, and truncate modes. The default thread-safe library build passes; checkpoint runtime behavior is unverified.

WAL close, commit-callback retrieval, exclusive-mode transitions, and file-handle accessors now have bodies. The ZIPVFS frame-size accessor remains behind its feature guard. The default thread-safe build passes; WAL runtime behavior is unverified.

The latest pager batch translates transaction finalization, WAL read-transaction begin, checkpoint forwarding, and WAL callback retrieval together with their local helper closure. It passes the default thread-safe library build; runtime behavior is unverified.

The Pager WAL write path now includes pagerWalFrames and pager_write_changecounter. It filters pages past the commit size, updates page-1 version metadata, forwards frames to WAL, and notifies backups after successful writes. The full build passes; runtime behavior is unverified.

The C2FB window batch now covers all 62 indexed functions in `src/window.c`
(2,113 indexed C lines). Its 11 newly integrated routines generate aggregate,
peer, row-return, and frame VDBE code through `sqlite3WindowCodeStep()`.
Stable name and no-op callback accessors preserve the pointer comparisons used
by SQLite's built-in window functions. All 15 translated procedures passed
per-procedure compiler checks, and the full thread-safe library build passes.

The unchanged `window1.test` now executes all 348 cases. It passes the named-
window view, trigger INSERT SELECT, and tuple-IN cases that previously failed
or crashed. Source-less SELECTs now dispatch to window rewriting after name
resolution attaches the window list. EXISTS and discard destinations drop
unneeded ORDER BY and DISTINCT clauses before that rewrite. Simple SELECTs now
open `SRT_EphemTab` destinations before writing rows; this fixes view
materialization during UPDATE ... RETURNING at 73.2. The suite passes 348/348
and leaves 1,760 bytes in 28 SQLite allocations. The temporary Tcl bridge
advertises `windowfunc` so these upstream cases execute.
The unchanged `select1.test` passes 200/200 with its existing 304-byte
shutdown allocation; `select2.test` passes 22/22. The earlier `with1.test`
through `with3.test` runs occurred before the bridge enabled its CTE option, so
their 2/2 results were close-file checks only and did not cover CTE behavior.
The bridge cannot start `exists.test` because it lacks the Tcl helper
`faultsim_delete_and_reopen`.
The release, `SQLITE_TEST`, math-enabled, and statement-scanstatus library
profiles build with the latest SELECT destination handling.

The DROP TABLE and DROP VIEW parser actions now read `ifexists` from the
correct Lemon stack slot. This restores errors for nonexistent objects while
preserving `IF EXISTS`; `view-17.1` and `view-17.2` now pass. The unchanged
`view.test` run reaches view-32.1, then stops because the temporary Tcl bridge
does not accept `SQLITE_LIMIT_EXPR_DEPTH`. Before that bridge limit, view-29.1
still reports a malformed schema after an earlier rejected CREATE VIEW.

The REAL text rendering path now preserves a decimal marker for plain integral
REAL values, and the internal `%!` formatting flag keeps that marker when
formatting with `%g`. This fixes the distinction between `8` and `8.0` in
`quote()` output. The unchanged `windowA.test` passes all 20 cases with no
SQLite allocation leaks. The release, math-enabled, and statement-scanstatus
shared libraries also rebuild successfully with this formatting change.

Two runtime fixes restore aggregate-context reset and zero-argument aggregate
execution in the VDBE. `sqlite3SelectDup()` now copies window definitions and
rebuilds the cloned SELECT's window-function list, matching upstream. The
tuple-vector semantic action now reads the expression list from the correct
Lemon stack slot. These changes let trigger INSERT SELECT and windowed tuple-IN
queries generate their input records. No C2FB changes were needed because the
relevant window copy helpers were already translated; the gap was in the
manual SELECT-copy and parser integrations.

`sqlite3_create_window_function()` now allocates a user-function definition
when `sqlite3FindFunction()` is called with its create flag. A direct C API
probe registers a sliding `winsum()` callback and returns `1, 3, 5` as expected.
With a temporary test-only Tcl bridge helper, unchanged `window5.test` now
passes 9/9 and reports no tracked allocation leaks.

The per-connection `sqlite3RegisterLikeFunctions()` path is now implemented
beside the private `likeFunc` callback. It re-registers the two- and
three-argument LIKE overloads and applies case-sensitivity flags; the full
threaded library build passes, while runtime LIKE reconfiguration is unverified.

Virtual-table coverage is now 39 of 39 indexed functions (1,062 C lines):
`sqlite3_declare_vtab()` parses module-declared columns, `sqlite3_vtab_config()`
applies constructor options, `sqlite3VtabOverloadFunction()` handles module
function overrides, and `callFinaliser()` routes commit and rollback callbacks.
The full library build passes; virtual-table runtime behavior is unverified.

The DBSTAT module now has bodies for all 19 indexed functions (681 C lines).
Shared `StatTable`, `StatCursor`, `StatPage`, and `StatCell` layouts let C2FB
translate the page scan and column callbacks; its constructor, ZIPVFS offset
helper, and module registration were adapted manually. The default library
build passes, and the DBSTAT-enabled module compiles; runtime scan behavior is
unverified.

The DBSTAT module now has bodies for all 19 indexed functions (681 C lines).
The shared `SqliteDbstatTable`, `SqliteDbstatCursor`, `SqliteDbstatPage`, and
`SqliteDbstatCell` layouts let C2FB translate the page scan and column callbacks;
the module constructor, ZIPVFS size helper, and registration table are adapted
manually. The default library build passes, and the DBSTAT-enabled module
compiles; runtime scan behavior is unverified.


The all-source C2FB pass now preprocesses all 80 engine C files without
failures and can regenerate candidates even for functions that already have
FreeBASIC bodies. Its 897 emitted procedures were compile-checked individually;
449 compile on their own. All emitted names already matched existing bodies, so
this was a broad converter audit rather than a coverage increase. The failed
checks identify compiler and helper-closure blockers in the existing source
groups.

The later focused C2FB passes compiled 88 selected-source candidates and 24
candidates from a loose residual-module pass. All passing names already had
bodies in the ledger, so these passes added no source coverage. `allocSpace` is
now ported in `sqlite3_vdbe_core.bas`; it reuses unused opcode-array storage and
places any remainder in one fallback allocation.

Optional scalar math and percentile callbacks now register through the
FreeBASIC function table with SQLite's feature flags and callback user data.
ceilingFunc and logFunc are ported alongside the converted math and percentile
callbacks. The optional SQLITE_SOUNDEX profile also ports and registers
soundexFunc. The default, combined math/percentile, soundex-only, and combined
scalar-feature library builds pass; runtime behavior remains unverified.


The optional FILESTAT and WALSTAT profile now registers sqlite_filestat() and
sqlite_walstat(). C2FB translated both callbacks; the port also supplies the
pager forwarding routine and WAL-index/checkpoint JSON helpers. The enabled
library builds. The Windows SEH exception handler used by SQLite around WAL
diagnostics is not reproduced, and diagnostic runtime behavior remains
unverified.


The SQLITE_ENABLE_STMT_SCANSTATUS profile now collects scan entries, records
VDBE instruction ranges, and exposes sqlite3_stmt_scanstatus_v2() output
including frame-aware cycle totals. Its full library build passes, and the
scanstatus symbols have definitions in the shared library; runtime behavior
remains unverified.


The SQLITE_ENABLE_PREUPDATE_HOOK profile now includes the VDBE callback producer, old/new row-value accessors, and the
count, trigger-depth, and blob-write APIs. The enabled library builds; callback
behavior remains unverified at runtime.


The public sqlite3_stmt_explain() setter now updates the packed EXPLAIN mode,
uses the existing reprepare path when needed, and refreshes result-column
counts. Default and combined optional-feature library builds pass; runtime
behavior remains unverified.

The statement execution path now follows SQLite's `sqlite3Step` and outer
`sqlite3_step` split. It starts and resets VDBEs, accounts for active readers
and writers, transfers saved-SQL errors, invokes profile callbacks, and retries
schema invalidation through `sqlite3Reprepare`. VDBE halt handling releases
the matching reader and writer counts. This adds 136 indexed C lines, alongside
the two VDBE halt-accounting changes. The default threaded library builds;
runtime behavior remains unverified.

The EXPLAIN path now generates opcode names with embedded synopsis text from the
same `opcodes.h` used for opcode constants. It formats P4 values, recursively
renders cursor-hint expressions, translates opcode synopsis placeholders, walks
trigger subprograms, and populates EXPLAIN and EXPLAIN QUERY PLAN rows. These
bodies add 372 indexed C lines. The FreeBASIC `sqlite_codegen opcode-names` mode
regenerates the opcode names as part of `make -C fb_src regen-generated`. The
default threaded library builds, and the source module compiles with
`SQLITE_ENABLE_EXPLAIN_COMMENTS` and `SQLITE_ENABLE_CURSOR_HINTS`; runtime output
remains unverified.

VDBE explain-comment support now formats variadic opcode comments and prints
the SQL text retained by a debug VDBE. Debug register traces now print Mem
values and check Mem ownership invariants. Build that profile with:

The parser and query debug tree renderer now covers 27 of 35 indexed functions
(410 of 1,189 indexed C lines). Its indentation state is defined in
`sqlite3_treeview_types.bi`; the `SQLITE_DEBUG` library builds, but
runtime output remains unverified.

```sh
make -C fb_src TARGET=build/libsqlite3-fb-debug.so \
  FB_DEFINE_FLAGS='-d SQLITE_DEBUG=1 -d SQLITE_ENABLE_EXPLAIN_COMMENTS=1'
```

The debug library builds. Runtime trace output is unverified; the coverage-only
`test_addop_breakpoint` hook remains outside the port.

The JSON virtual-table callback table now registers `json_each`, `json_tree`,
`jsonb_each`, and `jsonb_tree`. Its filter accepts text or JSONB input with an
optional root path, and its column callback returns each row's key, value,
type, atom, id, parent, full key, path, and source JSON. This adds 199 indexed C
lines and connects the existing eponymous-table lookup path. The default
threaded library builds; JSON virtual-table behavior remains unverified at
runtime.

The JSON registration table now includes the JSON and JSONB scalar overloads,
the extraction operators, pretty printing, error-position reporting, and the
four JSON group aggregates. The new pretty/error/aggregate callbacks add 195
indexed C lines. The default library builds; runtime function behavior remains
unverified. The debug batch provides `jsonDebugPrintBlob()`, `jsonShowParse()`,
and `jsonParseFunc()`; the `json_parse()` SQL callback is registered only in
`SQLITE_DEBUG` builds. Runtime behavior remains unverified.

JSON path lookup now also performs insert, replace, delete, and set edits. It
builds nested JSONB object/array tails when an edit creates missing path
components, then repairs the affected parent sizes. This adds the 31-line
`jsonCreateEditSubstructure` helper and restores edit-mode handling in the
existing path traversal. The default library builds; mutation behavior remains
unverified at runtime.

The converter now accepts a comma-separated source-file selection through
`make -C fb_src bulk-candidate-files SOURCE_FILES='carray.c,vdbevtab.c'`. This
keeps iterative batch conversion scoped to the files whose layouts or parser
support have just changed. Its new private layouts cover the CARRAY bind/cursor
records and bytecode-vtab records; pointer-level `const` no longer prevents
prototype generation. The selected CARRAY, DBSTAT, and bytecode-vtab pass
produced 14 candidate callback bodies, of which 13 filled previously missing
functions. Each candidate compiled individually.

The CARRAY source now has FreeBASIC bodies for all 14 indexed functions and
331 C lines. The bytecode-vtab source has bodies for all 12 indexed functions
and 311 C lines. `sqlite3_carray_bind_v2` copies transient numeric, text, and
iovec data into SQLite-owned storage, checks allocation-size arithmetic, and
retains the caller's destructor for non-transient data. Both virtual tables
have stable callback tables and feature-guarded registration paths. The
combined CARRAY, DBSTAT, and bytecode-vtab feature library builds; runtime
behavior remains unverified.

The optional `sqlite_dbpage` virtual table now has bodies for all 16 indexed
functions, covering 371 C lines. The `DbpageTable` and `DbpageCursor` records
are mapped explicitly, and the static module callback table is registered in
the built-in extension list. The `SQLITE_ENABLE_DBPAGE_VTAB` library builds;
runtime behavior remains unverified.
Build the feature profile with:

```sh
make -C fb_src TARGET=build/libsqlite3-fb-dbpage.so \
  FB_DEFINE_FLAGS='-d SQLITE_ENABLE_DBPAGE_VTAB=1'
```

The MEMSYS5 module now participates in the build when enabled and is selected
through `SQLITE_CONFIG_HEAP`. The full debug/MEMSYS5 library and the default
threaded library build; allocator and debug behavior remain unverified at
runtime. Debug assertion failures go through a single log-and-abort helper.

The optional MEMSYS3 allocator has translated allocation and free-list
procedures, a manual heap initializer and callback table, and a checked
pool-index calculation in `memsys3FreeUnsafe`. `sqlite3Memsys3Dump` now emits
chunk metadata, small and hashed free lists, and current and peak usage to
stdout or a file. It checks chunk boundaries before reading tail metadata and
uses the SQLite debug assertion handler for inconsistent headers. A temporary C
ABI smoke configured the MEMSYS3 callbacks, allocated and freed blocks, and
verified the debug dump output. Default and `SQLITE_DEBUG` MEMSYS3 library
builds pass; broader allocator behavior remains unverified. The debug dump
candidate was generated with C2FB's preprocessed file mode and assertion
suppression, then integrated with debug assertions restored. No converter change
was needed for this routine.
Build the optional allocator with:

```sh
make -C fb_src TARGET=build/libsqlite3-fb-memsys3.so \
  FB_DEFINE_FLAGS='-d SQLITE_ENABLE_MEMSYS3=1'
```

Repeated C2FB batches and manual backend/registration ports now cover all 39
`os_kv.c` functions and 618 indexed C lines. The optional Unix VFS includes
file-backed record reads and writes, binary decoding, file callbacks, VFS
tables, and registration. The `SQLITE3_FB_OS_KV_DEFAULT` profile routes
`sqlite3_os_init()` through the K/V VFS registration and returns `SQLITE_OK`
from `sqlite3_os_end()`. The optional Unix and standalone default-VFS profiles
build; runtime behavior remains unverified.
Build the Unix optional profile with:

```sh
make -C fb_src TARGET=build/libsqlite3-fb-oskv.so OS_KV_OPTIONAL=1 \
  FB_DEFINE_FLAGS='-d SQLITE3_FB_OS_KV_OPTIONAL=1'
```

Build the standalone profile that makes `kvvfs` the default VFS with:

```sh
make -C fb_src TARGET=build/libsqlite3-fb-oskv-default.so OS_KV_OPTIONAL=1 \
  FB_DEFINE_FLAGS='-d SQLITE3_FB_OS_KV_OPTIONAL=1 -d SQLITE3_FB_OS_KV_DEFAULT=1'
```

The Linux Unix VFS now includes C-named aliases for xOpen, POSIX xLock, close,
read, write, truncate, sync, and access callbacks, plus `robust_ftruncate`,
`unixGetpagesize`, and `unixSleep`. Shared inode and SHM bookkeeping use the
same process-wide mutex wrappers as upstream. Debug and FILESTAT builds now
describe POSIX advisory locks from `/proc/<pid>/fdinfo`, including held
database and WAL locks, and report SHM and inode state in the file-stat JSON.
The Unix VFS exposes version 3 system-call set/get/next callbacks, and its
common POSIX wrappers dispatch through the override table. As in the upstream
implementation, changing that table is not synchronized with concurrent I/O,
so configure overrides before database operations begin. Main-database opens
also reuse deferred descriptors when the device, inode, and read mode match;
runtime descriptor reuse is unverified.
All 135 indexed Unix functions now have bodies (5,514 indexed C lines); this
source signal does not establish semantic parity. The xOpen/xLock adapters use
the port's UnixFile and UnixLockInfo layouts. Apple proxy conch acquisition,
path switching, file controls, lock callbacks, AFP byte-range locking, and the
`unix-afp` VFS run through guarded method tables. VxWorks canonical path IDs
and named-semaphore locking are also represented. Native Apple and VxWorks
runtime behavior remains unverified, and automatic filesystem-based proxy
selection is still unmapped. The Windows source index now
has bodies for 109 of 109 functions (3,594 of 3,594 indexed C lines). The
dedicated `sqlite3_os_win_memory.bas` module supplies the optional Win32 heap
callbacks, method table, compact operation, and reset operation; the general
allocator selects it under `SQLITE_OS_WIN` and `SQLITE_WIN32_MALLOC`. The Win32
alertable worker wait retries completion notifications.
Guarded helper and allocator objects compile in local base,
debug/heap-validation, and process-heap profiles; native Windows and Cygwin
object builds and runtime behavior remain unverified.

The latest source-aware C2FB pass expanded `os_win.c` against MinGW headers and
used a 32,768-entry declaration bound while retaining 8,192-entry function
workspaces. It emitted 26 simple procedures and skipped 5,720 unsupported or
duplicate candidates. It identified the allocator's `winMemRoundup` identity
callback. The isolated candidate checker still lacks some WinFile and helper
declarations for larger Windows batches; the integrated guarded objects compile.

The latest bulk C2FB sweep covered `os_unix.c`, `os_win.c`, and `wal.c`; the
default-profile candidates were already represented in the port. An Apple
locking-style sweep emitted eight simple procedures, also already present, and
rejected the remaining proxy callbacks at `unixFile` member access. I ported
the proxy group together in `sqlite3_os_unix.bas`: path switching, transform,
GET/SET file controls, reserved-lock checking, lock/unlock callbacks, and method
table routing now use the conch helpers. The transform path includes the
read-only filesystem fallback using Darwin's `statfs` layout, guarded by a
size check against [Apple's `statfs` definition](https://github.com/apple/darwin-xnu/blob/main/bsd/sys/mount.h).
`fillInUnixFile` now owns common post-open setup and selects the registered
no-lock, POSIX, dot-file, flock, and NFS methods. POSIX byte-range operations
route through `unixFileLock`, and final WAL shared-memory disposal goes through
`unixShmPurge`. Apple-profile object builds pass with `HAVE_GETHOSTUUID=0` and
with `SQLITE_TEST`, `HAVE_GETHOSTUUID=1`, and a `LOCKPROXYDIR` override. The
default threaded library build passes. Native Apple runtime behavior and
automatic filesystem-based proxy selection remain unverified. The source
index now has bodies for all 3,243 in-scope definitions and all 124,545 indexed
function lines; source-body coverage does not establish semantic parity.

The latest Unix pass connected VxWorks path-ID lifetime and named-semaphore
callbacks, then added the Apple AFP `fsctl` lock group and registered
`unix-afp`. AFP lock transitions share the inode counters and use the common
Unix mutex; proxy path lookup now understands the AFP context record. Default
threaded library and Apple locking-style objects compile, including the Apple
`SQLITE_TEST` profile. Apple errno lookup now uses Darwin's `__error()` and
Darwin's EAGAIN, ETIMEDOUT, and ENOLCK values; lock-error classification also
matches SQLite's transient-error set. C2FB now scans private layouts in
implementation `.bas` files, maps the Unix C records to `UnixFile` and
`UnixLockInfo`, and lowers mapped local struct declarations and `sizeof`
expressions. The Apple profile translated 22 candidates, including
`afpSetLock`, `afpCheckReservedLock`, and `afpLock`; loose mode translated 45,
including all five AFP callbacks after retaining callers with unresolved local
helpers. The Unix private records now live in `sqlite3_os_unix_types.bi`, which
is included by both the backend and separate C2FB candidate modules. C2FB also
suppresses a second prototype when its C and FreeBASIC indexes describe the
same helper. An isolated strict-candidate compile accepts the translated AFP
set-lock, reserved-lock check, and lock callbacks. The full loose candidate
still depends on helpers outside the translated subset, and the strict profile
does not yet translate AFP unlock/close. These candidates have not replaced the
hand-integrated AFP implementation. The macro-generated `afpIoFinderImpl`
remains outside the body translator. A Windows-profile C2FB pass now converts
`winSetSystemCall`, `winGetSystemCall`, and `winNextSystemCall` from
`os_win.c`. It maps the file-local `win_syscall` array through an explicit
FreeBASIC name and counts its aggregate initializer; the focused candidate
object compiles. These callbacks are now implemented in the Windows VFS helper;
the override table initializes before VFS registration, and typed dispatch
aliases route its supported Win32 entries through the table. The Cygwin
full-path branch now uses the same table for POSIX path conversion and symlink
resolution, and its temporary-directory search follows Cygwin's environment.
FBC generated C for the Cygwin target with `-target cygwin -r`; no Cygwin object
or runtime verification is available because `cygwin-gcc` is not installed.
Native Apple, VxWorks, and Windows runtime behavior remains unverified.

A VDBE DDL pass now dispatches OP_Destroy, OP_ParseSchema, and the three
OP_Drop* cleanup instructions. The executor uses the existing translated
B-tree, schema initializer, and unlink routines; no C2FB changes were needed
for this gap. Follow-up dispatch now includes IfEmpty, Pagecount/MaxPgcnt,
IncrVacuum, SqlExec, Vacuum, IntegrityCk/IFindKey, strict-table TypeCheck,
ReopenIdx, Program/Param trigger frames, ResetCount, SoftNull, subtype, ElseEq,
AggInverse, and AggValue, and gives CollSeq and SeekHit their runtime state
changes.
The executor now has dispatch cases for all 192 generated opcode labels;
compile-time feature guards still control which optional handlers are built.
Strict-table `TypeCheck` applies column affinity, checks the resulting Mem type
against the packed standard-type nibble, handles generated columns, and reports
`SQLITE_CONSTRAINT_DATATYPE` with the table and column names. `ReopenIdx`
clears an existing index cursor when its root is unchanged and opens a replacement
when the root changes.
Window aggregate inverse/value operations use the registered callbacks and
VDBE accumulator cells; aggregate and window runtime behavior remains unverified.
Trigger Program frames allocate and reuse child Mem/cursor storage, map OLD/NEW
registers through Param, and restore the caller when a successful child Halt runs.
Trigger runtime behavior remains unverified.
SqlExec saves and restores authorization, trace, and analysis-limit state around
nested sqlite3_exec calls. Vacuum calls the translated database rewrite routine.
IntegrityCk calls the B-tree integrity walker for each selected root page;
IFindKey applies the expression-index floating-point tolerance helper.
Default and debug/column-mask library builds pass. Runtime behavior remains
unverified.

A follow-up VDBE pass added virtual-table cursor, filter, column, rowid, update,
transaction, create, destroy, rename, `IN` value-list, and integrity-check
operations. It also adds aggregate-step fallback, cursor pin/unpin, row-size
branching, preformatted row transfer, shared-cache table locks, WAL checkpoint
and journal-mode changes, and the optional `sqlite_offset()` opcode. The
shared-cache B-tree lock wrapper was already available as a C2FB translation;
this pass did not require converter changes. The default threaded library
build passes, and the executor compiles with `SQLITE_ENABLE_OFFSET_SQL_FUNC`.
The executor also compiles in the `SQLITE_DEBUG` plus column-mask profile.
Runtime behavior is unverified; no SQLite tests were run in this pass.

The authorizer callback repair now invokes `xAuth` once per authorization
action. C2FB's older translated `realAuthCheck` body had emitted the callback
twice; `sqlite3_set_authorizer()` also now honors `SQLITE_ENABLE_API_ARMOR`.
Transaction and savepoint generation performs its corresponding parse-time
authorization checks. The default threaded library build passes, and the
authorizer modules compile with API armor enabled. Runtime behavior remains
unverified; no SQLite tests were run.

The attached-database VDBE pass now records B-tree and shared-cache lock masks
for each database, dispatches `OP_Transaction`, `OP_OpenRead`, `OP_OpenWrite`,
`OP_ReopenIdx`, `OP_CreateBtree`, and `OP_Clear` with database indices, and
routes commit finalization through the translated `vdbeCommit()` two-phase
commit helper. Savepoint operations now visit each attached B-tree and preserve
deferred-constraint snapshots in the Savepoint record layout. Thirteen repeated
side-effecting calls in the translated commit helper were corrected to reuse
their first result. The full threaded library builds with both the default and
`SQLITE_MAX_ATTACHED=32` profiles; VDBE shared-lock entry/leave code handles
the byte-array mask in the large profile. The source ledger lists all 3,243
in-scope definitions as present and its C2FB repair queue is empty, so this pass
needed no converter change. Runtime behavior is unverified; no SQLite tests
were run.

The release VDBE executor now guards `sqlite3VdbeIncrWriteCounter` at its
declaration and all five call sites with `SQLITE_DEBUG`, matching the upstream
empty macro in non-debug builds. Full release, debug, and
`SQLITE_MAX_ATTACHED=32` library builds pass. An SQLite-internal dynamic-symbol
audit finds no undefined SQLite symbols in the release, debug, or
`SQLITE_MAX_ATTACHED=32` libraries. The debug library still exports the
counter helper. Runtime behavior is unverified.

`SQLITE_DBSTATUS_SCHEMA_USED` now counts the schema hash tables and walks table
and trigger allocations through the non-destructive `pnBytesFreed` path, across
all attached databases. Release, `SQLITE_DEBUG`, and
`SQLITE_ENABLE_MEMORY_MANAGEMENT` library builds pass, and each has zero
undefined SQLite symbols. C2FB's repair queue is empty and the latest candidate
sweep found no uncovered body, so this change reused existing translated
deletion routines. Status behavior is unverified; no SQLite tests were run.

Parser finalization now dispatches all 50 active Lemon `%destructor` symbols
from `src/parse.y` in stack-pop order, including source lists, ID lists, CTEs,
windows, trigger steps, and frame-bound expressions. The FreeBASIC parser-ID
generator now emits those nonterminal IDs alongside the existing reduction
IDs. A static comparison against the generated Lemon `yy_destructor` found no
missing symbol IDs or cleanup cases. Release and debug full-library builds
pass with no undefined SQLite symbols; parser error cleanup remains unverified
at runtime.

The `SQLITE_DBSTATUS_STMT_USED` sizing walk now temporarily disables lookaside
while VDBEs are measured, then restores it before clearing `pnBytesFreed`, as
`src/status.c` does. The full release library build passes; runtime status
behavior is unverified.

Compound SELECT reductions now carry the operator token for `UNION`, `EXCEPT`,
and `INTERSECT` as well as `UNION ALL`. A compound right-hand SELECT is wrapped
as a FROM-subquery before linking, matching the `src/parse.y` action. Release
and debug library builds pass. Compound SELECT runtime behavior remains
unverified; no SQLite tests were run.

Window-expression duplication uses `sqlite3WindowDup()` and clears the
copied Window pointer before allocation so OOM cleanup cannot release the
source expression's window. The `SQLITE_OMIT_WINDOWFUNC` library profile also
builds after adding the upstream feature guards around window-only code in the
translated resolver, SELECT planning, expression walkers, cleanup, and parser
paths. The expression-duplication smoke exercises window definitions only
through compilation; separate window tests cover query execution.

The full `SQLITE_ENABLE_PERCENTILE` library profile builds and has no undefined
SQLite symbols. The earlier inventory note about a duplicate declaration in
`sqlite3_analyze.bas` was stale; the profile needed no source or C2FB repair.
Percentile runtime behavior remains unverified.

IN-SELECT code generation now allocates an OP_Blob Bloom filter for eligible
one-time RHS subroutines, attaches the comparison KeyInfo before compiling the
SELECT, and passes the register through the SELECT destination so OP_FilterAdd
populates it. The OP_Once P3 register then enables OP_Filter probes in
`sqlite3ExprCodeIN`. Non-BINARY comparison collations and disabled optimization
profiles skip the filter. A source audit found 2,653 adjacent assignments in
139 older bulk-generated files that evaluated a captured C expression twice;
the port now reuses the C2FB temporary for the following local assignment.
This prevents duplicated allocator calls, VDBE emissions, and other expression
side effects. A second pass repaired 1,384 more adjacent captured-value
duplicates across 135 bulk files, including pointer stores. That pass fixed a
derived-table prepare leak in `sqlite3ExpandSubquery`; release and debug probes now finalize
simple, limited, and ordered FROM-subqueries with zero lookaside slots in use
and close successfully. A 100-iteration same-connection repeat also kept
lookaside usage at zero after each finalize. The current C2FB preprocessed-tree
output does not emit the audited duplicate patterns; these repairs required no
C2FB source change. Release and debug libraries build. Targeted Bloom,
function-call, DML, join, attached-database, foreign-key, savepoint, rollback,
and integrity probes pass.

C2FB now maps SQLite's `SubrtnSig` record to the existing
`SqliteSubroutineSignature` layout and lowers mixed string/integer
`sqlite3VdbeExplain` calls through a fixed adapter. Its `include-existing` path
now stages mapped bodies for comparison and filters duplicate declarations
against FreeBASIC call signatures. The isolated `expr.c` candidate pass emitted
169 procedures; 101 compiled individually and 68 still fail on unresolved
helper dependencies or layout mismatches. The candidate pass used the converter
build before a follow-up private-helper declaration refinement. The latest
converter failure note is stale: the current converter completed a fresh
preprocessed `expr.c` conversion, and the emitted candidates contained no
adjacent duplicate temp-to-assignment evaluations. The 68 procedures still need
dependency or layout work, though all already have port bodies. The Bloom
branch was integrated into the existing SQLite helper after comparing the
generated candidate with upstream.

`SQLITE_DBSTATUS_LOOKASIDE_USED` now counts both large and small lookaside
slots. Reset reattaches each pool's free list to its initial list and refreshes
the aggregate slot counters. Release, debug, and `SQLITE_OMIT_TWOSIZE_LOOKASIDE`
library builds pass with zero unresolved SQLite symbols; status behavior is
unverified at runtime.

The pager now builds with both `SQLITE_ENABLE_SNAPSHOT` and
`SQLITE_OMIT_WAL`. WAL-only pager operations are excluded or stubbed under the
same feature guard used by upstream, and snapshot get/open/recover return
`SQLITE_ERROR` when WAL support is omitted. The default release,
snapshot-with-WAL, and snapshot-without-WAL builds pass; each has zero
unresolved SQLite symbols. No SQLite runtime tests were run for these profiles.

The current function index contains FreeBASIC bodies for all 3,243 in-scope
SQLite source definitions, and `PORTING_REPAIR_QUEUE.csv` has no missing-body
entries. The separate `expr.c` candidate audit still has 68 procedures that do
not compile individually because of unresolved helper dependencies or layout
mismatches; those functions already have port bodies, so they are not missing
routines. This pager feature-guard pass exposed no converter defect and needed
changes in the SQLite port only. Body presence and successful linking do not
establish semantic parity; the direct API smoke above covers only the listed
table, index, aggregate, transaction, and cleanup cases.

The initialization mutex now uses the reference-counted lifetime from
`src/main.c`: concurrent and recursive initialization callers share it, and
the final caller frees it after leaving the lock. This removes a 56-byte
process-memory remainder that survived database close. A direct C ABI
lifecycle probe reports zero bytes after initialize, close, and shutdown in
both release and `SQLITE_DEBUG` builds. A fresh run of the unchanged upstream
`test/main.test` through the C Tcl shell linked to the FreeBASIC `SQLITE_TEST`
library passes 56/56 tests with no tracked allocations at finalization. Its
thread tests are skipped because the temporary Tcl bridge lacks the `sqlthread`
command; the linked library reports `sqlite3_threadsafe() == 1`. Sixteen threads
making 3,200 concurrent `sqlite3_initialize()` calls also complete without
errors in release and debug builds; shutdown leaves zero tracked bytes.
The 50,000-row external-sort probe still passes in release and debug builds,
including all five sorter opcodes and zero lookaside usage after close.

No C2FB change was needed for this repair. The function ledger has no missing
in-scope routine bodies, and the 68 `expr.c` candidates with individual
compile blockers already have integrated FreeBASIC bodies; their blockers are
helper dependencies or record layouts rather than conversion throughput.

The unchanged upstream `test/select1.test`, `test/select2.test`, and
`test/select3.test` files now run through a temporary C Tcl shell linked to
the FreeBASIC library, using SQLite's per-file slave-interpreter lifecycle.
Their assertions pass: 200/200, 22/22, and 92/92. The close-all-files checks
pass in all three suites. `select2.test` and `select3.test` end with zero
tracked allocations; `select1.test` retains 304 bytes in six allocations and
needs a separate leak trace. The `SQLITE_TEST` VDBE search, found, and sort
counters now match `select2.test`'s planner checks. Temporary `BTREE_SINGLE`
handles close with their last cursor, and connection close now releases the
main, TEMP, and attached B-trees. The `group_concat()` separator is omitted
for the first non-NULL input. This pass found no C2FB conversion limitation.

The multi-row VALUES coroutine is now implemented in `sqlite3_values.bas`.
`sqlite3SelectNew` reserves the first SrcItem used by its zero-source-list
selects, and the SELECT materializer now reuses a coroutine already emitted
while parsing VALUES. Compound SELECT compilation passes its LIMIT counter
through each no-FROM term and does not decrement it twice. Compound output
names remain those of the left-most term.

The unchanged upstream `select1.test` through `select4.test` files pass all
assertions: 200/200, 22/22, 92/92, and 125/125. `select2.test` and
`select3.test` finish with no tracked allocations. `select1.test` retains
304 bytes in six allocations, and `select4.test` retains 576 bytes in eight
allocations; both pass their assertions and close-all-files checks. The
per-file slave runner and Tcl shell shim live in `/tmp`; upstream test files
were not modified.

These failures were in existing FreeBASIC SELECT and VALUES code, so this
repair did not require a C2FB change. The function ledger still has bodies
for all 3,243 indexed in-scope definitions. This test sample verifies the
listed query paths only; it is not full SQLite behavioral parity.

The unchanged `test/select7.test` initially exposed a mixed VALUES fallback:
double-quoted identifiers force UNION ALL terms, then a later constant row
starts a coroutine. The port now exempts VALUES terms from the ordinary
compound SELECT limit, emits a single VALUES term without consuming its
`pNext` compound sibling, and allows an `SF_Values` coroutine wrapper through
FROM-clause code generation. VDBE label resolution also permits unused labels
without an allocated label array while still validating every referenced jump
label. These repairs keep negative immediate operands separate from jump
targets and reject invalid label references before dereferencing them.

The unchanged upstream `select1.test` through `select7.test` files now pass
592/592 assertions. `select2`, `select3`, `select5`, `select6`, and `select7`
finish with no tracked allocations; `select1` retains 304 bytes in six
allocations and `select4` retains 576 bytes in eight allocations. In
`select7.test`, the 16-row DQS VALUES insert succeeds with
`SQLITE_LIMIT_COMPOUND_SELECT` set to 10. C2FB and FBC were unchanged: each
routine involved already had a body, and the failures were in FreeBASIC path
integration and validation.

The unchanged `test/select8.test` and `test/select9.test` also pass: 5/5 and
36,718/36,718 assertions, with no tracked allocation leaks. Across `select1`
through `select9`, 37,315 assertions pass. `select9` exposed two more SELECT
integration defects. `OP_ResetSorter` now clears sorter rows without resetting
the cursor's `OP_SequenceTest` counter, so partial ORDER BY sorting retains its
prefix groups. The LIMIT decrement emitted by `sqlite3SelectEmitOutputRow` is
now limited to an active sorter path, avoiding a second decrement when an
index already satisfies ORDER BY.

The C2FB-generated `flattenSubquery` body now handles the compound UNION ALL
view cases covered by `select9.test`. After preparation rewrites a collated
compound into a FROM-subquery, the SELECT dispatcher rechecks `pPrior` and
routes the rewritten tree through FROM code generation. The view queries use
their indexes and avoid a temporary sort, and the collated compound ORDER BY
cases pass. No C2FB or FBC source change was needed; the conversion body was
already present, and the remaining defects were in caller integration and
VDBE/SELECT runtime paths. Other compound flattening shapes still need
coverage.

The unchanged upstream `select1.test` through `select9.test`, plus
`selectA.test`, `selectB.test`, and `selectC.test`, now pass 37,749/37,749
enabled assertions through a temporary Tcl shell linked to the FreeBASIC
`SQLITE_TEST` library. The harness links the search, sort, and transfer-
optimization counters, and supplies the fixture's `optimization_control` and
selected `sqlite3_db_config` names; no upstream test files were changed. The
test library used:

```sh
make TARGET=build/libsqlite3-fb-test.so FBC='fbc -g -export' FB_DEFINE_FLAGS='-d SQLITE_TEST=1'
```

The temporary Tcl binding and fixture runner are under `/tmp/sqlite_fb_tests`.
`select1` retains 304 bytes in six allocations,
`select4` retains 576 bytes in eight allocations, and `selectA` retains 288
bytes in four allocations. The other listed suites report no tracked
allocations at finalization.

These runs found and repaired four integration defects. `sqlite3HexToBlob`
now treats its byte-count argument as the caller-provided number of hex digits,
which already excludes the closing quote; the manual SELECT literal path now
passes that same length. The B-tree cell parser accepts bounded reads from
`BtShared.pTmpSpace` as well as database pages, so the preformatted cell built
by `sqlite3BtreeTransferRow` can be validated before `OP_Insert`. The VDBE
cursor allocator now closes any existing cursor type, including a sorter,
before reusing its memory register. `sqlite3BtreeInsert` also accepts any
signed index-comparison result and uses its sign, matching the B-tree API
contract.

`sqlite3Select` now restores the EXPLAIN QUERY PLAN parent after each completed
SELECT path. This keeps compound merge branches as siblings and fixes the
`selectA-4.1.2` plan shape. The C2FB-generated `flattenSubquery` body was already
present; these were FreeBASIC integration and runtime fixes, so no C2FB or FBC
source change was needed. Source-body coverage remains 64.8% of the indexed
in-scope engine and public API code; at the recent source-body throughput, the
remaining body volume is about three days of work. Full semantic parity will
take substantially longer than completing the source-body inventory.

The standard release library also builds after these changes. The `SQLITE_TEST`
library builds with the VDBE search/sort counters exported for the temporary C
Tcl fixture adapter.

The latest unchanged B-tree regressions pass `delete.test` (58/58),
`delete3.test` (4/4), and `delete4.test` (30/30), with all tracked allocations
released at shutdown. `insert2.test` passes all 29 assertions but reports 16
bytes in two allocations at shutdown. The full `select1` through `select9`,
`selectA`, `selectB`, and `selectC` group still passes 37,749/37,749
assertions; `select1`, `select4`, and `selectA` retain the previously recorded
1,168 bytes in 18 allocations, while the other SELECT files finish without
tracked allocations.

These B-tree tests found several state and boundary defects in existing ported
routines. Commit phase two now changes `BtShared.inTransaction` from write to
read before the shared writer is dropped when another VDBE still holds a read
transaction. `moveToRoot` now clears the saved cursor key before opening the
root for a `CURSOR_REQUIRESEEK` cursor, keeping `pKey` and `eState` consistent.
Cursor restoration also preserves the search comparison in `skipNext`, as the
upstream routine does. The delete tests cover nested trigger deletes and a
WITHOUT ROWID delete spanning multiple indexes.

Large-delete cases additionally exposed two page-boundary errors. Leaf-page
redistribution now subtracts moved cell bytes from the next-page fill count,
and defragmentation accepts a cell beginning at the final valid four-byte
offset. No C2FB or compiler changes were needed: each affected routine already
had a FreeBASIC body. Source-body coverage remains 64.8% of the indexed
in-scope engine and public API code; at the recent source-body throughput, the
remaining body volume is about three days of work. Full semantic parity will
take substantially longer than completing the source-body inventory.

The VDBE halt path now includes the constraint detail stored in OP_Halt P4,
and OP_AutoCommit supplies the specific message for COMMIT, ROLLBACK, and
BEGIN when no matching transaction state exists. The first unchanged
`update.test` run passed 135/136 assertions; its remaining query-plan mismatch
was traced and repaired below. All 71 `insert.test`
assertions pass. `insert4.test` passes all 83 assertions, including
transfer-optimization selection and conflict rollback, once the temporary Tcl
bridge links the port's `sqlite3_xferopt_count` test counter. The bridge also
supports the `LEGACY_FILE_FORMAT` and `DEFENSIVE` db-config names required by
upstream fixtures. The initial `insert.test` run reported 160 bytes in 18
allocations, and the earlier `insert4.test` run reported 3,872 bytes in 36
allocations. The duplicate expression-list append and default/RETURNING text
copies described below account for those leaks.

`insert4.test` exposed a signed-rowid cell-size defect: the ordinary B-tree
cell builder and OP_RowCell transfer builder used the generic 7-bit length
for keys whose high byte is set, while SQLite's ninth varint byte carries all
eight remaining bits. Both builders now share the upstream-compatible
9-byte rowid length rule. The reduced C API case and all signed-rowid conflict
cases in `insert4.test` pass. The `SQLITE_TEST` optimizer counter increments
after the optimizer's semantic checks, matching upstream even when generated
code includes a runtime empty-destination guard. C2FB and FBC were unchanged;
the converter already produced the optimizer body, and the failures were in
FreeBASIC cell construction and test instrumentation.

The CHECK-constraint leak trace found older integrated bodies that evaluated
side-effecting C assignment values twice. `sqlite3AddCheckConstraint` appended
the expression list twice, `sqlite3AddDefaultValue` duplicated the default
span twice, and `sqlite3ExpandReturning` duplicated each output name twice.
These bodies now store the value already captured in a temporary. A fresh
C2FB `build.c` pass emits one `sqlite3ExprListAppend` call for
`sqlite3AddCheckConstraint`, so no converter source change was needed. The
unchanged upstream `insert.test` and `insert4.test` now pass 71/71 and 83/83
assertions with all SQLite allocations freed. A focused memdebug probe
covering DEFAULT, CHECK, and `RETURNING *` also closes with `SQLITE_OK` and
zero live allocations.

The `update-21.12` query plan was missing the correlated-subquery EXPLAIN
parent and the FROM-subquery co-routine parents. `sqlite3CodeSubselect` now
emits the scalar-subquery and reused-subquery rows, and SELECT subquery setup
labels co-routines and materializations with SQLite's internal source-item
formatter. SELECT planning now initializes and refines `nSelectRow` from the
WHERE output estimate. This restores the expected CTE/window plan hierarchy,
automatic covering index, and Bloom filter. Unchanged `update.test` now passes
136/136 assertions with all allocations freed. The unchanged `analyze.test`
passes 2/2. The unchanged `where.test` file now passes all 322 assertions in a
math-enabled `SQLITE_TEST` build, with all SQLite allocations freed. In the
default profile, the only failure is `where-30.1`, which needs the optional
`log()` math function. Its
`where-5.1` through `where-5.15` counter checks pass after the VDBE `OP_Prev`
and `OP_SorterNext` success paths were aligned with upstream's `SQLITE_TEST`
search counter. `where-6.1` and all `where-6.9` cases now pass. `ANALYZE`
previously reported `SQLITE_NOMEM` because `analyzeOneTable` reserved only the
first saved index-prefix register; reserving the full prefix and trailing
rowid slot keeps analyzer registers out of the VDBE cursor cells. The ORDER BY
cases also depended on `sqlite3ExprCollSeq` resolving an implicit column
collation to the database default. The port now does that lookup, matching
upstream's `BINARY` fallback. The two `where-27` overflow cases now pass after
`compare2pow63` was changed to index the boundary as bytes, preserving the
`INT64_MAX` literal as an integer. The former `where-14` order failures came
from `sqlite3AffinityType` omitting the declared-column size estimate used by
covering-index planning. The port now records `Column.szEst`; the planner sees
that the automatic index is smaller than the table and selects its expected
covering scan. A C2FB pass over `where.c` emitted 91 candidate procedures,
including the upstream automatic-index loop branch already present in the
integrated planner. A preprocessed C2FB `include-existing` pass over
`build.c` emitted 127 candidates, including a `sqlite3AffinityType` candidate
that compiles in isolation. This gap was in the existing handwritten body, so
no C2FB source change was needed.

A separate `SQLITE_ENABLE_MATH_FUNCTIONS` test build registers `log()` and runs
the full `where.test` file. The SELECT path caps grouped-query output at 100
rows (`sqlite3LogEst(100) = 66`) before publishing the estimate to later CTE
uses. This matches SQLite's aggregate estimate and lets the planner choose the
automatic indexes in `where-30.1`; all 322 assertions now pass, with all
tracked allocations freed.

The simple aggregate SELECT path now uses SQLite's `WHERE_ORDERBY_MIN` and
`WHERE_ORDERBY_MAX` flags and emits the corresponding early-out after the
aggregate update. Scalar `min()` and `max()` pass the selected function
collation into `sqlite3MemCompare`. Together, these changes make the unchanged
`collate4.test` pass all 109 assertions.

VACUUM now accepts `OP_Vacuum P2=0`, which means no output filename register.
The `OP_IdxInsert` path also accepts a NULL register when `OPFLAG_PREFORMAT`
marks a preceding `OP_RowCell` copy. `OP_AutoCommit` now follows SQLite's
active-writer check for COMMIT and allows the nested `BEGIN` used by VACUUM.
The unchanged `vacuum.test` passes 2/2, and `collateB.test` passes 16/16; both
finish with all tracked allocations freed.

The earlier `where-6.7.2` fixed-LIMIT plan mismatch is resolved. The table-
backed SELECT path now passes the bounded LIMIT estimate and `SF_FixedLimit`
into `sqlite3WhereBegin`, along with its ORDER BY LIMIT sorter label. The
unchanged `where.test` through `whereN.test` run passes 3,044 cases in the
current SQLITE_TEST profile; broader LIMIT costing parity remains unverified.

The unchanged `select1.test` through `select9.test` and `selectA.test` through
`selectC.test` pass 37,749 assertions. `select1`, `select4`, and `selectA`
retain 304, 576, and 288 bytes respectively; the other files free all tracked
allocations. Schema loading now uses `db->init.busy` while resolving column
collations, so an unavailable collation remains attached to its table until a
query needs it. The unchanged `collate3.test` passes 73/73. The unchanged
`collate2`, `collate4`, `collate5`, `collate6`, `collate7`, `collate8`,
`collate9`, and `collateA` suites also pass. The temporary Tcl bridge provides
the upstream test-only `sqlite3_create_collation_v2` and
`sqlite_delete_collation` commands needed by `collate7`. It still stops
`collate1` at the unavailable `do_faultsim_test` helper.

After the final cursor-state fix, the default `SQLITE_TEST` rerun of the 12 SELECT suites, `collate2.test` through `collateB.test`, and `vacuum.test` reported zero SQLite test errors across 38,223 cases. `select1`, `select4`, and `selectA` still leave 304, 576, and 288 bytes respectively, so the test harness exits nonzero for those three suites despite zero test errors.

The C callback probe also found `sqlite3_exec()` returning an extended error code while extended-code mode was disabled. The wrapper now applies `sqlite3ApiExit()` before returning, matching the configured error mask; forward and reverse probes match SQLite in both modes: primary code `SQLITE_ABORT` by default and extended code `SQLITE_ABORT_ROLLBACK` when extended-code mode is enabled, with the same rollback error message.

The unchanged `trans3.test` passes all 10 tests, `rollback2.test` passes 139, and `savepoint4.test` plus `savepoint5.test` pass 7 combined. The transaction run exposed that `sqlite3BtreeNext` and `sqlite3BtreePrevious` treated a tripped `CURSOR_FAULT` as end-of-file. Both wrappers now restore every non-valid cursor state before stepping, so the stored `SQLITE_ABORT_ROLLBACK` reaches the caller. Forward and reverse index-scan C callback probes now return “abort due to ROLLBACK”; the passing test runs free all tracked allocations.

The default release, default `SQLITE_TEST`, math-enabled `SQLITE_TEST`, and
`SQLITE_ENABLE_STMT_SCANSTATUS` library builds pass with the current ANALYZE,
collation, numeric, SELECT, VDBE, and EXPLAIN changes. In the math-enabled
profile, the selected where, SELECT, collation, and VACUUM suites pass 38,281
assertions with zero failures. The three noted SELECT suites retain small
allocations at test finalization. The SQLite test files remain unchanged; runs
use the temporary Tcl bridge described above.

Grouped aggregate output now reuses the saved GROUP BY key when the result
column is named by a GROUP BY ordinal. This avoids reevaluating volatile
expressions such as `random()` for the output row. When GROUP BY and ORDER BY
lists compare equal, the existing group sorter also supplies the requested
order, so the SELECT path does not open a redundant second sorter. The
unchanged `distinct2.test` now reports zero errors across 51 tests, including
`distinct2-5030`; its harness still reports 864 bytes in 12 allocations at
shutdown, matching the earlier failing run. The direct C probe returns
`0 1 2 3 4` for both the deterministic and random grouped queries.

After this SELECT change, the unchanged `select1.test` through `selectC.test`
pass all 37,749 assertions. `select1`, `select4`, and `selectA` retain their
known 304, 576, and 288 byte shutdown allocations. Release, `SQLITE_TEST`,
math-enabled, and statement-scanstatus library profiles all build. No C2FB
change was needed: the required `sqlite3ExprToRegister` routine was already
ported, and this defect was in grouped-query integration rather than a missing
converter translation. Source-body coverage remains 64.8% of the indexed
in-scope engine and public API code.

Aggregate DISTINCT planning now passes the aggregate argument and, for grouped
queries, the GROUP BY keys to the WHERE planner. The aggregate bytecode follows
the planner's `UNIQUE` or `ORDERED` result and removes the unused ephemeral
table open, including both reset sites in the grouped path. The unchanged
`distinctagg.test` now passes 72/72 assertions with all tracked allocations
freed; its tests confirm both the index-based temporary-table eliminations and
the result values. The unchanged `select1.test` through `selectC.test` still
pass all 37,749 assertions, and `distinct2.test` passes all 51 assertions.
Their previously recorded shutdown allocations remain in `select1`,
`select4`, `selectA`, and `distinct2`. Release, `SQLITE_TEST`, math-enabled,
and statement-scanstatus profiles all build after the planner integration.
The existing C2FB-generated WHERE planner and helper bodies provide the
`WHERE_DISTINCT_*` result; SELECT now connects that result to aggregate
bytecode generation.

The first unchanged PRAGMA suites now run against the port. Pager opening and
page-size changes advance the pager data version through `pager_reset()`, and
`sqlite3PagerSharedLock()` calls the same reset when the on-disk file version
changes. The unchanged `pragma3.test` passes 21/21, including a child-process
commit that advances another connection's `PRAGMA data_version`. The
unchanged `pragma.test`, `pragma2.test`, and `pragma4.test` through
`pragma6.test` pass 96 more assertions, 117 total, with no tracked leaks.

For corrupt databases, the integrity walker now initializes only the page
header so it can report bad cell layouts. Once it reports structural errors,
the PRAGMA path skips row-level scans that would revisit those damaged cells
and abort. This keeps `integrity_check` and `quick_check` usable on the
corrupted fixture in `pragma6.test`. The test bridge supplies child-process,
statement-introspection, and hex-database helpers; the upstream Tcl files are
unchanged. Release, `SQLITE_TEST`, math-enabled, and statement-scanstatus
profiles build with these pager and PRAGMA changes.

Ordinary `SELECT DISTINCT` now supplies `WHERE_WANT_DISTINCT` to the planner
and uses its UNIQUE or ORDERED result. Matching DISTINCT and ORDER BY lists
share the grouped query path, and a source-less SELECT accepts DISTINCT for
its single implicit row. The skip-ahead optimization in the translated
`sqlite3WhereEnd` path now stays off for LEFT JOIN levels; this avoids seeking
past a NULL-extended row after ANALYZE. The unchanged `distinct.test` passes
88/88 with no tracked leaks. `distinct2.test` passes 51/51 assertions, with
its earlier 864-byte shutdown allocation still reported. `distinctagg.test`
passes 72/72, and `select1.test` through `selectC.test` pass 37,749 assertions.
Release, `SQLITE_TEST`, math-enabled, and statement-scanstatus builds pass.
These fixes use existing converted planner routines; C2FB and FBC sources were
unchanged. Source-body coverage remains 64.8% of the indexed in-scope engine
and public API code.

A view regression exposed two VDBE integration defects. Ordinary statement failures were passing their SQLite error code to `sqlite3RollbackAll`, although B-tree rollback accepts `SQLITE_OK` for an ordinary abort and reserves `SQLITE_ABORT_ROLLBACK` for cursor faults. Failed statements now roll back their statement savepoint before closing it, and whole-transaction aborts use the ordinary rollback code. The grouped aggregate `ORDER BY ... LIMIT` path now opens an ephemeral B-tree for top-N trimming; unbounded sorting continues to use the sorter.

The unchanged `view.test` now passes 121/121, including `view-29.0/.1` and grouped aggregate cases `view-9.2` through `view-9.6`. `trans3.test` passes 10/10, `savepoint4.test` 2/2, and `savepoint5.test` 5/5. Release, `SQLITE_TEST`, math-enabled, and statement-scanstatus libraries build. The view suite still reports 7,504 bytes in 138 shutdown allocations. No missing routine caused these failures, so no C2FB change was needed.

Virtual-table planning and JSON path checks exposed three connected runtime
issues. The VDBE now resolves jump labels and the maximum
`OP_VFilter`/`OP_VUpdate` argument count before allocating its argument vector.
The translated `allocateIndexInfo` compares against `TABTYP_VTAB`, and JSON
`each` carries the selected root token through payload validation so a path
such as `$.items` walks the chosen array rather than treating its parent-object
label as the row. The unchanged `json101.test` passes all 283 test cases, and
all tracked allocations are freed at shutdown.

SQLite's printf regression also covered buffer growth and special values.
`%c` now retains the original UTF-8 codepoint when a precision larger than
the stack buffer requires reallocation. The float renderer receives
the zero-pad flag, which makes alternate-form infinity render as `9.0e+999`
(or its negative form) and zero-padded NaN render as `null`. A release-library
C ABI probe passes for a root-path `json_each` query, both infinity encodings,
a 1,000-deep JSON array built with `%.1000c`, and 500 repeated `%c` bytes.
The release library builds successfully.

The direct JSON virtual-table memory probe traced the remaining connection
allocations to a close-path gap: `sqlite3_close()` was not disconnecting cached
virtual tables or rolling back virtual-table transactions before its busy-state
check. The shared close path now performs both operations, matching SQLite's
close order. The direct `json_each` probe returns to zero tracked bytes and
allocations after close and shutdown; the unchanged `json101.test` also passes
283/283 with no tracked allocations remaining.

C2FB's SQLite body profile now maps all four public virtual-table planner
records. Its `__builtin_offsetof` translation handles a trailing flexible
pointer array represented by a one-element FreeBASIC placeholder, and its
regression compiles the candidate and compares offsets and allocation sizes
with C for several planner sizes. The extracted `allocateIndexInfo` candidate
compiles. The full C2FB suite passes: 10,745 C/FreeBASIC behavior comparisons
in both native and GCC modes, with 150 candidates accepted and 31 unsupported
functions rejected. Source-body coverage remains approximately 64.8% of the
indexed in-scope engine and public API code.

Recursive CTE code generation now accepts FIFO and queue destinations for
simple aggregate anchors and emits their completed rows through the shared
SELECT destination path. Safe subquery ORDER BY elision prevents recursive
queries from repeatedly evaluating an irrelevant ordered subquery. The
min/max aggregate callback now uses SQLite's skip-accumulator signal for NULL
and non-improving values, and `OP_AggStep` consumes that signal as a request to
preserve the existing accumulator. SELECT flattening also skips compound
terms, and parse errors stop later name resolution from replacing the original
diagnostic.

The source-less SELECT path now adds SQLite's `SCAN CONSTANT ROW` explanation
entry. Repeated unmodified view or derived-table aliases reuse their first
materialization with `OP_OpenDup`; the matching `isSelfJoinView()` body was
already available from C2FB in `sqlite3_bulk39_select.bas`, so this repair only
connected existing translated code to SELECT materialization.

With CTE and virtual-table support enabled in the temporary test bridge, the
unchanged `with2.test` passes 73/73 with no tracked leaks, `with3.test` passes
15/15, `with4.test` passes 8/8, and `with5.test` passes 19/19. The `with2`
bridge uses upstream `ext/misc/series.c`; its earlier no-module stub skipped
the virtual-table case. At this point,
`with1.test` passed 118/119; the later parser-semantic update recorded below
fixed the remaining `with1-26.0` diagnostic. The suite reported 576 bytes in
8 shutdown allocations. `view.test` passes 121/121 after self-join materialization
reuse, with its existing 7,504-byte shutdown allocation. `with3.test` leaves
304 bytes in 6 allocations. SQLite upstream test files remain unchanged.
Release and `SQLITE_TEST` library profiles build with these changes.

The function ledger currently has FreeBASIC bodies for all 3,243 in-scope
indexed definitions; 13 test/debug-only definitions are out of scope and 7
upstream definitions are disabled. The broader source-body coverage estimate
remains 64.8% because it includes source that is not represented by this
function ledger.

`sqlite3SelectCompileExpr()` now handles SQLite's planner-only
`likely()`/`unlikely()`/`likelihood()` wrappers by compiling the value argument
directly. It also delegates integer literals to the shared `codeInteger()`
path, fixing wide hexadecimal literals. `OP_AggFinal` now retrieves the error
text from the finalizer result without trying to stringify an already-text
value, preserving `SQLITE_ERROR` for `sum()` overflow. The SELECT emitter passes
`length()`, `typeof()`, and `octet_length()` flags through to `OP_Column`, whose
overflow path can skip payload pages when only record metadata is needed.

With the temporary C test adapter extended for the upstream Tcl APIs,
`func3.test` passes 37/37 with no tracked leaks. The unchanged `func.test`
executes all 15,030 cases with zero test errors; the harness reports 288 bytes
in 4 remaining SQLite allocations at shutdown. The later parser-semantic
update brings `with1.test` to 119/119 with no tracked leaks. No upstream test
source was changed.

The temporary C test adapter now includes the upstream test-only SQL functions
and Tcl commands needed to execute `func.test` without changing its source.
The unchanged `func4.test` passes 185/185 with no tracked leaks. No C2FB change
was needed for the SELECT expression repair: the shared C2FB `codeInteger()`
and inline-function paths were already available; the dedicated SELECT emitter
now connects to those behaviors and transfers metadata-only column hints to the
VDBE.

`sqlite3ExprCodeCopy()` now preserves the upstream null-expression path, which
lets omitted INSERT columns emit `OP_Null`. `sqlite3MayAbort()` now records the
abort flag on the top-level parse context, so trigger subprograms participate in
the parent statement journal. With the unchanged upstream trigger tests,
`trigger1.test`, `trigger3.test`, and `trigger4.test` pass 79/79, 25/25, and
25/25 with no tracked leaks. `trigger5.test` through `trigger9.test` also pass
3/3, 8/8, 12/12, 3/3, and 30/30 with no tracked leaks. `trigger2.test` passes
72/72 assertions but leaves 336 bytes in 10 allocations at shutdown. The
temporary Tcl bridge advertises trigger support, maps
`SQLITE_LIMIT_TRIGGER_STEPS`, and supplies the test-only `randstr()` function
needed by `trigger9.test`; no upstream test file was modified. C2FB needed no
change for these fixes: its generated expression switch already preserved the
null fallback, while the missing behavior was in the hand-maintained
expression-copy and parse-context helpers.

A loose preprocessed C2FB sweep covered all 80 engine C inputs with no
preprocessing failures and wrote isolated candidates under
`build/candidates-sweep/`. It translated 694 simple-function candidates and
skipped 2,465 unsupported or duplicate bodies. Candidate files remain review
artifacts rather than linked sources; those counts do not establish semantic
parity.

The sweep exposed an extension API table regeneration bug. The owner module
includes the table it generates, so C2FB had treated declarations in the old
table as independent bindings and omitted them from the replacement. The API
adapter now excludes the stable owner include while scanning declarations,
even when a profile-specific table is written to a separate build directory,
and recognizes public `Alias` bodies in the FreeBASIC source directory. This
includes the generated `sqlite3_keyword_*` APIs, which do not have ordinary C
function rows in the ledger. The default extension table now backs 268/279
slots; the remaining 11 are omitted by upstream deprecated or feature-gated
entries. Both release and `SQLITE_TEST` builds succeed. The unchanged
`keyword1.test` passes 118/118 with no tracked leaks, and a loaded C extension
calls `sqlite3_keyword_count()` through the generated API table and receives
147. The unchanged `loadext.test` passes through `loadext-4.4`; the temporary
test bridge then stops at the test-only `do_malloc_test` helper, which is not
implemented there.

The C2FB regression suite passes 10,745 C/FreeBASIC behavior comparisons on
both native and GCC backends, accepts 150 candidates, and rejects 31 unsupported
functions. It now also checks that API body aliases survive repeated table
generation when the owner includes the stable table name and the generated
output is in a separate directory.

An include-existing conversion of `src/build.c` emitted 127 candidates. Its
`sqlite3CreateView()` body evaluates `sqlite3ExprListDup()` once and stores that
result for `pCheck`. The already integrated body came from an older conversion
and called the allocator twice. Updating the stored expression removed the
leaks in `altercol.test` groups 8, 12, and 19; the full 257-test file now passes
with no tracked allocations left at shutdown. The current converter already
produces the corrected code for this case.

The latest loose C2FB sweep covered all 80 engine C inputs and emitted 694
simple-function candidates. The function ledger already has FreeBASIC bodies
for all 3,243 in-scope definitions, so this sweep did not reveal a missing
indexed routine that a broad converter change could safely supply. The
remaining skips include unsupported type/layout cases and duplicate bodies;
they need targeted work with their owning subsystem. The 64.8% ratio above
measures indexed function-definition lines against all in-scope lines; it is
separate from the 100% function-row count and does not measure semantic parity.

The feature-enabled C2FB pass over `select.c` supplied the missing
`columnTypeImpl()` and `generateColumnTypes()` variants. With
`SQLITE_ENABLE_COLUMN_METADATA`, the SELECT path now copies database, table,
and origin names into result-column metadata. A feature-profile library build
and direct C smoke test pass for `SELECT a FROM t`, a view, a nested subquery,
and an expression result; the test also loads a C extension and confirms the
database/table/origin API slots are populated. The UTF-16 metadata functions
compile but were not exercised. The generated feature API table backed 274 of
279 slots; the default table was restored to 268 of 279. Default release and
`SQLITE_TEST` library profiles also build after the conditional SELECT changes.
The C smoke used the system SQLite 3.46.1 headers because this checkout lacks
the generated 3.54.0 `sqlite3.h`; it checks the stable extension API prefix,
but a same-version header remains a stronger ABI check.

The unchanged upstream `with1.test` now passes 119/119, and `altercol.test`
passes 257/257 after the parser changes; both finish with no tracked leaks.
The default release and `SQLITE_TEST` plus preupdate-hook builds succeed.
Its syntax diagnostic exposed drift in two hand-maintained parser actions:
`cmd ::= select` now follows `DBFLAG_EncodingFixed`/`sqlite3ReadSchema()` and
always deletes the temporary SELECT, while `cmdx ::= cmd` no longer turns the
existing parse result into a parser-action failure after `sqlite3FinishCoding()`.
The parser driver distinguishes a token syntax failure from a semantic-action
failure so the syntax diagnostic replaces an earlier name-resolution message,
matching the upstream `%syntax_error` action. No C2FB change was needed.

`join8.test` exposed a dispatch error in `sqlite3Analyze()`: an unqualified
object name was treated as a database name even when no attached schema matched.
The port now falls through to table/index lookup in that case, matching
`src/analyze.c`. This lets `ANALYZE sqlite_schema` create `sqlite_stat1`; the
unchanged `analyze.test` passes 42/42 and `join8.test` passes 107/107, including
the expected Bloom-filter query plan. Both finish with no tracked leaks. The
test bridge registers the upstream C series module; no upstream test source
was changed, and no C2FB update was needed.

The `bloom1.test` run found that the `expr IN ()` parser action had omitted
SQLite's empty-list, singleton-constant, singleton-subquery, and vector-list
paths. Restoring those reductions prevents an empty expression list from
reaching `sqlite3FindInIndex()` as a null list and preserves aggregate function
classification. The SELECT path now also emits the missing DISTINCT temporary
B-tree row in EXPLAIN QUERY PLAN. `bloom1.test` passes 29/29; `in.test` through
`in5.test` pass 128/128, 2001/2001, 38/38, 83/83, and 46/46 respectively, with
all tracked allocations freed.

The `in2.test` 2000-row stress loop exposed a divider-size check that used the
page-local B-tree cell parser on a buffer located in a sibling page or balance
scratch. The port now parses that cell against its known buffer length. The
unchanged `in2.test` passes 2001/2001 with no tracked leaks. The B-tree and
parser repairs were in hand-maintained paths; no C2FB change was needed.

The unchanged `index.test` exposed a parser stack-offset error in the `DROP
INDEX` action. It read the `INDEX` keyword token as the `IF EXISTS` flag, so
`DROP INDEX missing_name` could silently succeed. The action now reads the flag
from the correct RHS slot. The large BLOB workload in `index4.test` exposed a
second issue: index searches descended past exact keys stored in interior
separator cells. The B-tree search now leaves the cursor on an exact interior
match. `index.test` passes 101/101, `index2.test` 9/9, `index3.test` 12/12,
`index4.test` 10/10, and `btree01.test` 216/216, all with no tracked leaks. No
C2FB or compiler change was needed.


The partial-index cases in `index9.test` exposed a missing bound-variable
comparison in `sqlite3ExprCompare()`. The port now compares a bound `TK_VARIABLE`
with a literal when QPSG is disabled and marks the prepared VDBE for reprepare
when the binding changes. Unchanged `index9.test` passes 25/25, including the
64-bit integer boundary cases, and `indexA.test` passes 150/150; both finish
with no tracked leaks.

The B-tree follow-up also passes `btree02.test` (4/4) after the temporary test
bridge registered upstream's `eval` extension. The unchanged `in2.test` stress
file passes 2001/2001 again after the interior-index-cell search fix.

The unchanged `index8.test` exposed missing planner metadata for a literal
LIMIT. The SELECT path emitted the counter but left `nSelectRow` unconstrained
and omitted `SF_FixedLimit` when entering WHERE planning. It now passes the
bounded estimate and flag, and supplies the planner's ORDER BY LIMIT label to
the sorter context. This makes the non-covering `t1abd` case choose a table scan,
matching upstream. Removing a duplicate OFFSET check lets `selectInnerLoop`
apply OFFSET after DISTINCT filtering. `index8.test` passes 6/6, `limit.test`
124/124, `limit2.test` 26/26, `orderby8.test` 202/202, and `select1.test`
200/200, all with no tracked leaks.


The ORDER BY regression sweep now passes `orderby1.test` (66/66),
`orderby2.test` through `orderby7.test`, `orderby8.test` (202/202),
`orderby9.test`, `orderbyA.test` (100/100), and `orderbyB.test`, all with no
tracked leaks. The grouped aggregate path passes GROUP BY expressions and flags
to WHERE planning. It processes adjacent groups directly when the selected scan
provides group order, and uses the grouping sorter when it does not. A separate
ORDER BY sorter is emitted only when that scan or grouping order cannot satisfy
the requested order. This brings both result rows and EXPLAIN sort counts in
`orderbyA.test` into line with upstream. No C2FB or FBC change was required; the
SELECT and WHERE routine bodies were already present in FreeBASIC.


The VDBE numeric-affinity regression sweep caught a `MustBeInt` mismatch: text
values were numerically converted, but an already-REAL value such as `2.0` was
never promoted to an integer when it had no fractional part. `OP_MustBeInt` now
applies integer affinity after numeric parsing, matching upstream while still
rejecting `2.5`.

All 15 unchanged upstream window test files now pass 2,907 assertions with no
tracked SQLite allocation leaks. Temporary Tcl bridge helpers expose the
upstream window and aggregate test commands; no upstream test sources changed.
`window5.test` covers custom window callback registration and connection-close
cleanup. Its teardown case exposed a layout mismatch: the hand written function
registry treated `FuncDef.u` as a callback pointer, while SQLite stores a
reference-counted destructor record there. The registry now increments,
releases, and frees that record according to its reference count. A separate C
API probe verifies destructor callbacks run once on replacement and once on
connection close.

`windowE.test` exposed a precise-mode floating point mismatch in Kahan summation.
A reduced FreeBASIC testcase showed FBC reassociating floating point expressions
even with `-fpmode precise`. The compiler optimizer now preserves floating
point grouping in precise mode while retaining reassociation in fast mode. The
patched compiler passes its complete unit suite (1,617,124 assertions), and the
upstream `windowE.test` cases now return the expected large-integer moving
sums. A release C API probe confirms custom sliding callbacks return 1, 3, 5;
integral REAL `nth_value` offsets are accepted while fractional offsets still
raise the documented error.

The selected neighboring suites also pass after these shared changes:
`limit.test` (124/124), `limit2.test` (26/26), `index8.test` (6/6),
`orderbyA.test` (100/100), and `select1.test` (200/200), all without tracked
leaks. The upstream test files remain unchanged.

The unchanged printf suites now pass `printf.test` (1,437 cases) and
`printf2.test` (51 cases), and `cast.test` passes its 1 case. The C reference
`testfixture` passes the same `printf.test` with 1,439 cases. The temporary FB
Tcl bridge uses SQLite's status API and reports zero outstanding allocations
after each run. Its allocator-fault injection command is a no-op, so the FB
`printf` OOM-injection branch is not verified. The formatter fixes cover the
optional printf precision limit, SQLite's 32-bit width parsing, incomplete
format specifiers, pointer-case output, floating-point grouping, and lowercase
JSON control escapes. A release C API probe verifies oversized widths fail
before allocating large fields and that large fixed-format values use
SQLite's 16-significant-digit rounding.

The unchanged SELECT stress suites `select2.test` through `selectG.test` pass
37,586 cases, including all 36,717 cases in `select9.test`. The write-side
follow-up suites `insert.test` through `insert5.test`, `update.test` and
`update2.test`, and `delete.test` through `delete4.test` pass 494 cases with
zero tracked allocations remaining.
`update2.test` and `delete4.test` first exposed a malformed-record error in
`OP_NotFound`: the port allocated `nAllField` cells, while SQLite allocates
`nKeyField + 1` for a decoded index key. Matching that capacity rule resolves
the WITHOUT ROWID update and trigger-delete failures. The upstream test files
remain unchanged; temporary Tcl support links the port's VDBE counters and
registers upstream-only helper functions.

The unchanged `where.test` now passes 322/322 in a rebuilt math-enabled test
profile. This run exercises the final VDBE record-unpack fix as well as the
planner cases that call the optional `log()` function; SQLite memory status
returns to zero.


The VDBE GLOB regression exposed the P3/P5 behavior missing from `OP_String`.
The LIKE/GLOB prefix loop revisits its lower-bound literal once; upstream marks
that second value as a BLOB so the next text-index seek exits. The port now
applies the same type change. A temporary Tcl adapter provides `sqlite3_exec`
and advertises the build's default `like_match_blobs` capability. Unchanged
`like.test`, `like2.test`, `like3.test`, `where2.test` through `where9.test`,
and `whereA.test` through `whereC.test` pass 2,988 cases total with zero
tracked SQLite allocations remaining.
No routine was missing, so C2FB was unchanged.


The VDBE covering-index tests exposed a missing `OP_Column` path. When
`OP_DeferredSeek` supplies a `P4_INTARRAY` map, the requested table column can
be read from the current index record if that column is covered. The port now
uses that map instead of seeking the table. `whereD.test` passes 62/62, and the
unchanged `select1.test` through `selectG.test` pass 37,785 cases with zero
tracked SQLite allocations.

The expression-index sweep exposed a DDL name-context layout error.
`SqliteNestedNameContextUnion` was a sequential record, shifting `ncFlags` from
byte offset 40 to 64. Declaring it as a FreeBASIC `Union` restores the C layout.
The resolver now sees `NC_IdxExpr` and rejects nondeterministic functions and
subqueries. The unchanged `indexexpr1.test` passes 117/117, including its
`integrity_check` case.


The unchanged `pragma4.test` passes 108/108 with the temporary Tcl bridge
providing the statement column-count and SQLite log callbacks; tracked memory
returns to zero.


The SELECT constant-propagation helper is now connected after FROM-subquery
flattening. Its affinity guard follows SQLite's expression API:
`sqlite3ExprAffinity()` returns zero for an expression with no affinity, while
`SQLITE_AFF_NONE` is the separate tagged affinity value. The previous comparison
rejected all eligible constants, leaving the routine's translated body inert.
The unchanged `whereL.test` now passes 28/28, including the expected index order
and omitted ORDER BY sorter. `select1.test` through `selectH.test` pass 37,803
cases; `where.test` and `where2.test` through `whereN.test` pass 3,044 cases
with capability-appropriate adapters. Each run reports zero outstanding SQLite
allocations.

This issue did not expose a missing routine or a C2FB conversion limitation;
C2FB was left unchanged.

The unchanged upstream `pragma.test` passes 145/145 cases enabled by the
FreeBASIC Tcl adapter, including the schema-version cases. Its schema-cookie cases exposed
an API difference: a legacy `sqlite3_prepare()` statement must return
`SQLITE_ERROR` from `sqlite3_step()` after invalidation, while finalize retains
`SQLITE_SCHEMA`. The step wrapper now preserves that behavior and keeps
automatic reprepare for saved-SQL statements such as `sqlite3_prepare_v2()`.
Targeted C ABI probes confirm both paths. This was a statement API repair, not
a missing routine or a C2FB conversion limitation, so C2FB was unchanged.

The temporary Tcl bridge now dispatches `sqlite3_prepare` to the legacy C API
and `sqlite3_prepare_v2` to the saved-SQL API. This made the unchanged schema
tests usable against the port. They exposed two active-statement
mismatches: collation changes checked `nVdbeExec` instead of `nVdbeActive`, and
function replacement returned a generic busy message. Both paths now match
SQLite's active-VDBE guard and error text. `schema.test` passes 52/52,
`schema2.test` through `schema5.test` pass another 107 cases, and `schema6.test`
passes 21/21. The 180 schema cases and 145 pragma cases report no tracked
allocations remaining. The bridge uses the upstream Tcl test VFS and a temporary
`md5file` helper; test files remain unchanged.

The unchanged `alter.test` exposed a parser-action offset error in the vector
assignment rule `setlist ::= LP idlist RP EQ expr`. The FreeBASIC action read
RHS slot -2 (`RP`) instead of -3 (`idlist`), passing a pointer into the SQL
text to vector cleanup. The unchanged `alter-19.1` reproducer crashed in the
port but completed in the C ABI reference. Correcting the stack slot makes
`alter-19.1` through `alter-19.3` pass. C and FreeBASIC probes report the same
Lemon stack layout, so no compiler change was needed. The full `alter.test`
now passes all 118 cases enabled by the temporary adapter, with no tracked
leaks; the C reference passes all 123 cases. The adapter now provides the
upstream `sqlite3_exec`, test-control, and rename-test helpers. The upstream
test file remains unchanged.

The unchanged `altercons.test` exposed another hand-written Lemon action error:
rule 298 (`ALTER TABLE ... ALTER ... DROP NOT NULL`) has nine right-hand-side
symbols, but its FreeBASIC guard expected eight and rejected the reduction
before calling the already-ported ALTER routine. The guard now expects nine.
All explicit `rhsCount` checks match their Lemon productions after the fix.
`altercons.test` passes 189/189 and `altercons2.test` passes 70/70 through the
temporary Tcl adapter, with no tracked allocations remaining. The C reference
passes the same unchanged `altercons.test`. This was a parser-action count
error, so no C2FB or FBC change was needed.

The unchanged `alterdropcol.test` exposed a WITHOUT ROWID cursor-state mismatch
in the already-ported B-tree insert path. Upstream only saves the cursor for
later restoration if page balancing invalidated it. The FreeBASIC path forced
that restoration after every `BTREE_SAVEPOSITION` insert, so `OP_Next` could not
advance after rewriting a row. It now keeps the cursor on the replaced key
unless balancing moved it, and skips an unnecessary seek when the caller
already supplied the saved position. `alterdropcol.test` passes all 101 cases
enabled by the adapter; the C reference passes all 103. Both runs report no
tracked allocations remaining. This was a B-tree behavior repair, not a missing
function body, so C2FB and FBC remain unchanged.

The WITHOUT ROWID suite then exposed missing error-mask handling in the public
`sqlite3_reset()` and `sqlite3_finalize()` wrappers. Both now keep the extended
error in connection state while returning the value masked by `db->errMask`,
matching `sqlite3ApiExit()`. A default-profile C ABI probe confirms primary
`SQLITE_CONSTRAINT` returns with extended result codes off and code 787 with
them on. The unchanged `without_rowid3.test` passes 1,198/1,198 enabled cases;
the C reference passes 1,198/1,198. The selected batch also passes
`without_rowid1.test` (83), `without_rowid2.test` (10),
`without_rowid4.test` (88), `without_rowid5.test` (33),
`without_rowid6.test` (22), and `without_rowid7.test` (22), along with
`altercons3.test` (30) and `alterdropcol2.test` (24). These 1,510 cases report
no tracked allocations remaining. The temporary Tcl bridge supplies the
upstream test-only commands and a schema-only echo virtual table; test sources
remain unchanged.

The foreign-key sweep exposed two more semantic mismatches. The parser now
stops as soon as semantic code sets a non-OK `Parse.rc`; it no longer parses
later statements and replaces an earlier foreign-key mismatch with a syntax
error. The VDBE halt path now checks immediate and deferred foreign keys after
`OR FAIL` conflicts, so an FK violation overrides a later UNIQUE error and
rolls back the statement as SQLite does. The unchanged `fkey1.test` through
`fkey8.test` pass 1,441 cases enabled by the port profile, with no tracked
allocations remaining. The C reference passes 1,445; its four additional cases
require FTS5. The temporary Tcl bridge supplies the unchanged tests' prepare,
error-code, db-status, bind, column, trace, and statement-journal helpers.

The unchanged trigger suite passes 711 assertions across `trigger1.test`
through `trigger9.test`, `triggerA.test` through `triggerG.test`, and
`triggerupfrom.test`. Adding the trigger-depth and trigger-step limit names to
the temporary Tcl bridge and setting its default depth unblocked
`trigger1.test` and `triggerC.test`. `triggerA.test` also runs, but its
`do_malloc_test` cases use the adapter's no-op allocator-failure hook and do
not provide out-of-memory coverage. The completed runs report no tracked
allocation leaks. The trigger failures were in test-adapter setup; no missing
routine required a C2FB change, and the upstream test files remain unchanged.

The follow-up CTE and view checks pass `with6.test` (30/30) in the
math-enabled test profile, `withM.test` (32/32), `view2.test` (5/5), and
`view3.test` (2/2), all with no tracked allocations remaining. `withM.test`
exposed a crash when a persistent `CANTOPEN` fault rejected a temporary B-tree
open during a recursive CTE. The failed pager had a null file-handle pointer,
but translated cleanup helpers assumed that pointer was always present. The
pager cleanup now checks the pointer before reading its I/O methods or
requesting device characteristics. A focused `CANTOPEN` fault case and the
full `withM.test` pass. Its OOM cases still use the adapter's no-op memory
failure hook, so they do not exercise allocation failures. `with6.test` uses
the optional math functions and the temporary runner's optimizer-control
adapter; no SQLite test source or C2FB code changed.

The 1 KiB `SQLITE_TEST` profile now matches the default page size used by
upstream `testfixture`. In that profile the unchanged `pager2.test` passes
2,003/2,003 enabled cases with no tracked leaks; the C reference passes
2,004/2,004, including one shared-cache case disabled in the port profile.
The savepoint stress cases exposed an incomplete main-journal rollback path:
it stopped at one journal segment instead of continuing across later journal
headers. `pagerPlaybackSavepoint()` now follows the upstream multi-segment
playback order and uses the existing page replay helper. Journal-mode OFF
rollback also follows SQLite's no-journal path, so the pager does not return
to reader state with a cache whose writes cannot be rolled back. A reduced
savepoint repro, the journal-off rollback case, and the full pager2 suite pass.
After this repair, `pager3.test` (13/13), `pager4.test` (12/12),
`jrnlmode.test` (98/98), and `jrnlmode2.test` (14/14) also pass with no
tracked leaks.

With the page-size-aligned profile and updated temporary bridge,
`trigger1.test` through `trigger9.test`, `triggerA.test` through
`triggerG.test`, and `triggerupfrom.test` still pass 711/711. The unchanged
`fkey1.test` through `fkey8.test` pass all 1,441 cases enabled by the profile,
with no tracked leaks; four additional C-reference cases require FTS5. The
statement-journal helper reads the flag from the FreeBASIC VDBE layout.
At this stage, `pager1.test` reached 1,382 assertions and reported 34 errors,
including missing test-only commands, unsupported I/O fault cases, and
pager/index mismatches. That run was superseded by the rollback repair below.
The large-sector case pager1-42.2 now passes after the FreeBASIC
pagerWriteLargeSector path was aligned with SQLite's sector journaling:
it skips the reserved lock page, journals and dirties each co-resident page,
and propagates the journal-sync requirement across the sector. A focused
large-sector update and integrity-check repro passes 5/5, and pager2.test
still passes 2,003/2,003; both runs report no tracked allocation leaks.
fkey8.test passes 38/38 with no tracked leaks. Default, 1 KiB test, and
math-enabled test libraries rebuild successfully. This was a repair to an
existing FreeBASIC body, so no C2FB or FBC change was needed.

The B-tree payload reader now preserves the byte offset within an overflow
page while it follows earlier pages in the chain. Before this repair, reading
a field that began on a later overflow page restarted that page at byte zero;
a 1,600-byte update could rotate the stored text. The same-table update and
two-column overflow repros now pass. The unchanged update.test (142/142) and
insert.test (77/77) pass, and all 45,001 randomized JSON invariant cases
pass. OP_Seek* also clears a deferred cursor position before each new seek,
as SQLite does; rowid-15.1 and rowid-15.2 now pass. The same overflow offset
repair also fixes pager1-31.1. The FB rowid.test run reaches 249 cases with
one remaining adapter limitation: rowid-12.4 expects a disk-full fault,
which this runner does not inject. Its C reference passes 249/249. The latest
pager1.test now passes all 1,382 cases; its cross-process and
same-process multi-client lock sections now pass after the rollback repair
below. pager1-19.1, pager1-31.1, pager1-32.1, pager1-33.1, pager1-42.2,
pager1-44.2, and pager1-44.3 also pass. The latest run reports no errors
and no tracked leaks.

The temporary Tcl bridge does not collect actual pager reference counts for
the `sqlite3_pager_refcounts` helper. `pager1.27.1` does not assert that
diagnostic list; its transaction and SQL cases still execute.

The unchanged backup suites now pass in the `SQLITE_DEBUG`, 1 KiB page-size
test profile used to match upstream `testfixture`: `backup.test` passes
869/869 and `backup2.test` passes 16/16, with no tracked allocations left at
shutdown. Connection close now reports `SQLITE_BUSY` with SQLite's public
unfinished-statement/backup message while a backup retains a source B-tree.
The backup step also closes the temporary source read transaction in the
debug profile, following upstream's `TESTONLY` cleanup; this lets the
multi-connection writer cases run as they do under `testfixture`. Error
precedence for a detached destination remains intact. These were repairs to
existing FreeBASIC bodies, so no C2FB change was needed.

The pager1 multi-client tests exposed a rollback failure after an autocommit
write hit `SQLITE_BUSY`. `sqlite3PagerRollback()` first tried to synchronize
the journal through `pagerSyncJournal()`, which requires an exclusive lock.
When another connection still held a shared read lock, rollback stopped before
restoring the changed pages in the cache. The same connection then observed
rows from the failed update. The live rollback path now calls the existing
C2FB-translated `pager_playback()` through `pagerPlaybackBridge()`, matching
SQLite's journal replay path without that extra lock request. A reduced
two-connection repro now leaves the original rows intact, matching the C
reference. The unchanged `pager1.test` cross-process and same-process locking
sections pass. `pager2.test` (2,003/2,003), `pager3.test` (13/13),
`pager4.test` (12/12), `jrnlmode.test` (98/98), and `jrnlmode2.test` (14/14)
also pass with no tracked leaks. The backup regression set remains green:
`backup.test` (869/869), `backup2.test` (16/16), `backup4.test` (12/12),
`backup5.test` (20/20), `update.test` (142/142), and `insert.test` (77/77),
all with no tracked leaks. No C2FB or FBC change was required.

`pager1-19.1` exposed an auto-vacuum limitation in the B-tree transfer
optimization used by VACUUM. The port rejected preformatted overflow cells
for auto-vacuum databases, and its insertion path did not refresh the first
overflow page's pointer-map entry after the destination page was selected.
`sqlite3BtreeTransferRow()` now permits auto-vacuum allocation through the
pointer-map-aware allocator, and `sqlite3BtreeInsert()` records the first
overflow page against the final destination leaf as SQLite does. The unchanged
`pager1-19.1` passes. `vacuum.test` (41/41) and `vacuum6.test` (35/35) pass
in regular and `SQLITE_DEBUG` profiles. `vacuum2.test` (1/1),
`vacuum3.test` (110/110), `vacuum4.test` (2/2),
`autovacuum.test` (338/338), `incrvacuum2.test` (31/31), and
`incrvacuum3.test` (53/53) pass with no tracked leaks. The `vacuum5.test`
VFS-open-order check now passes 22/22 with no tracked leaks. The mismatch was
an eager open in transient pagers. The CTE's transient B-tree remains in
cache until it needs a spill, so PagerOpen now allocates an unopened file
handle and pagerOpentemp opens it only when disk backing is needed. The focused
CTE VFS trace matches the C reference. These repairs used existing pager and
B-tree bodies; no C2FB or FBC change was needed. After this pager change,
`backup.test` (869/869), `backup2.test` (16/16), `backup4.test` (12/12),
`backup5.test` (20/20), `update.test` (142/142), and `insert.test` (77/77)
still pass with no tracked leaks.

The unchanged `autovacuum2.test` passes 9/9 against the FreeBASIC library.
It verifies the callback's schema and page-count arguments, callback-selected
database shrink size, callback removal, and a zero-page result that disables
auto-vacuum. A temporary Tcl adapter mirrors the existing `test1.c` command;
the upstream test remains unchanged, and all tracked allocations are freed.
The ported `sqlite3_autovacuum_pages()` routine and B-tree callback path needed
no source changes for this test. No C2FB or FBC change was needed.

The `pager1-44.2` and `pager1-44.3` cases exposed an extra clamp in
`sqlite3PagerMaxPageCount()`. SQLite lets `OP_MaxPgcnt` set the limit using the
live B-tree page count, even when the pager's cached `dbSize` is larger during
an uncommitted auto-vacuum shrink. The pager's journal playback restores the
maximum from the original database size on rollback. Removing the `dbSize`
clamp matches that contract; both unchanged cases now pass, and the full
`pager1.test` failure count falls from 24 to 18, with no tracked leaks. No
C2FB or FBC change was needed.

`pager1-33.1` exposed a Unix VFS mismatch: `unixDelete()` ignored `ENOENT`,
allowing COMMIT to succeed after the rollback journal had been moved away.
It now returns `SQLITE_IOERR_DELETE_NOENT`, matching SQLite. The same suite
also found `pagerWriteDirtyPages()` truncating every committed database to
its logical page count, even when the VFS had preallocated more space. The
commit path now calls `pager_truncate()` after page writes only when the
logical image extends past the highest page written, and after journal
finalization only when written pages exceed the final image. The focused
diagnostic retains its 20 MiB file size after commit. `pager1-32.1` and
`pager1-33.1` pass, as do `pager2.test` (2,003/2,003), `vacuum.test` (41/41),
`vacuum3.test` (110/110), `vacuum6.test` (35/35), `autovacuum.test` (338/338),
and `incrvacuum3.test` (53/53), with no tracked leaks. The unchanged full
`pager1.test` now passes 1,382/1,382 with no tracked leaks.

The remaining pager1 cases found two more source-level differences. URI option
names and the `file:` scheme prefix were read through `ZString Ptr[index]`,
which does not index the C string bytes; the URI parser now uses byte-pointer
indexing. The four shared-memory and URI cases pass. Pager open also checks
that the resolved database path plus the eight-byte `-journal` suffix fits
`mxPathname`. Hot-journal recovery now checks the VFS output flags and returns
`SQLITE_CANTOPEN` if a read/write journal open falls back to read-only. These
fixes complete the 1,382-case pager1 run. No C2FB or FBC change was needed.


The unchanged URI suite exposed that Pager kept the database and sidecar paths
as separate allocations, dropping URI query options before the VFS xOpen call.
Pager now uses sqlite3_create_filename() to retain the four-byte database
prefix, URI key/value tail, journal path, and WAL path in one allocation, and
releases it with sqlite3_free_filename(). The temporary Tcl bridge adds the
existing sqlite3_open, sqlite3_errmsg, and sqlite3_errcode test helpers.
Upstream test files remain unchanged. uri.test passes 117/117 and
openv2.test 7/7 with no tracked leaks.


The SQLITE_DEBUG pager1 run caught an inverted guard in renameTokenCheckAll():
the translated assertion fired when mallocFailed was clear and no parser error
was present. Its condition now matches C, and both the focused pager1-18.5
case and full SQLITE_DEBUG pager1.test pass, with no tracked leaks.


The URI-00-error feature profile rejects `%00` escapes as SQLite specifies and
reports `ENABLE_URI_00_ERROR` through the compile-option API. The unchanged
uri2.test passes 22/22, and uri.test passes 99 cases with the strict profile
capability enabled. The regular profile's uri.test passes 117/117.


The unchanged attached-database suites `attach.test`, `attach2.test`,
`attach3.test`, and `attach4.test` pass 106, 70, 32, and 13 cases respectively
through the FreeBASIC `SQLITE_TEST` library, with no tracked allocation leaks.
The temporary Tcl adapter supplies the fixture's `sqlite3_db_filename`,
`SQLITE_LIMIT_ATTACHED`, and deprecated soft-heap-limit commands. This profile
reports that multithreaded tests are skipped. All 15 indexed functions in
`src/attach.c` already had FreeBASIC bodies, so this pass found no missing
routines and required no C2FB or FBC change. The upstream test files remain
unchanged.


The unchanged OOM-focused suites now also pass with no tracked allocation
leaks: `altermalloc.test` 4,109/4,109 (including the echo virtual-table case),
`alterfault.test` 3,109/3,109, `exprfault.test` 543/543, and
`schemafault.test` 86/86. The temporary echo adapter maps upstream numeric
connection pointers back to their Tcl database commands. The ATTACH suite's
shared-cache branch remains disabled in this fixture.

This coverage exposed three more OOM parity issues. `sqlite3OomFault()` now
disables lookaside, interrupts an active VDBE, and propagates the error through
outer parser contexts; the Lemon allocation-failure path calls it. This keeps
nested schema and ALTER failures as `SQLITE_NOMEM`. `sqlite3_exec()` now checks
the statement's OOM state when `sqlite3_column_text()` returns NULL, before
passing that value to a row callback as SQL NULL. Nested SQL now preserves the
nested error message so the outer Parse can report and free it.
`sqlite3SelectDup()` now attaches each copied source list to its owning Select
before later allocations, so OOM cleanup can use the full Select destructor.
This fixed the two qualified-name leaks in `schemafault.test`. Together, these
changes bring the schema, expression, ALTER, and ATTACH OOM suites to zero
failures and zero tracked leaks. The upstream test files remain unchanged; no
C2FB or FBC changes were needed.


The unchanged `attachmalloc.test` passes all 1,821 allocation-failure cases
enabled by this fixture, with no tracked leaks. Its shared-cache branch is
disabled here; the C reference fixture runs 3,041 cases including that branch.
The tests exposed two missed OOM paths in existing FreeBASIC bodies.
`sqlite3CreateIndex()` now checks the value returned by `sqlite3HashInsert()`:
the hash helper returns the uninserted index when its generic allocation fails,
without setting a connection's `mallocFailed` flag. `sqlite3SelectNew()` now
allocates its Select node before its child lists and releases the complete
source list when construction fails. The former issue caused the transient
failure at allocation 259 to be reported as success; the latter left qualified
schema names allocated during `ATTACH` schema loading. No missing routine or
C2FB/FBC change was needed, and the upstream test files remain unchanged.

The unchanged `wherefault.test` now passes 5,082 injected-allocation cases in
the FreeBASIC `SQLITE_TEST` build, with no tracked allocations at shutdown.
Failure injection found three more ownership errors in `sqlite3_select.bas`:
discarded ORDER BY lists remained attached when cleanup registration failed,
failed column-name copies leaked a partially built NATURAL JOIN USING list, and
failed comparison-expression allocation leaked the left side of that
comparison. Cleanup now takes ownership before registration, and local lists
and expressions are released on allocation failure. The temporary runner skips
multithreaded tests; the upstream test file is unchanged. These routines were
already implemented, so no C2FB change was needed.

The join regression sweep covered 3,228 cases across the unchanged `join`,
`join2` through `join9`, `joinA`, `joinB` through `joinF`, `joinH`, `joinI`,
and `joinD` scripts. All 3,228 assertions pass, and each run ends with no
tracked allocations. The SELECT path applies outer-join strength
reduction; both `join5-7.4` and `join5-7.2` now produce the reference plans.
The OR plan fix masks temporary opcode flags to SQLite's stored low byte in
`sqlite3PExpr()` and `sqlite3ExprAlloc()`. The parser driver now handles
Lemon's syntax-error flag before honoring `SQLITE_DONE`, so the invalid
lookahead after a completed statement reports `USING` without parsing the
remaining `(b);` tail as a new statement. `join3.test` passes 130/130 when the
temporary runner supplies SQLite's 64-bit `bitmask_size`; `join8.test` passes
106/106 with a temporary adapter that loads the upstream `series` extension.
The upstream test scripts remain unchanged.

After the expression-opcode fix, the unchanged `where.test` also passes 322/322
in the math-enabled `SQLITE_TEST` profile, and `wherefault.test` passes
5,082/5,082 with no tracked allocations. The non-math fixture reports one
missing `log()` function for `where-30.1`, so the math-enabled result is the
applicable WHERE-suite run. After the parser-driver change, `select1.test`
passes 199/199 and `select2.test` passes 21/21, both with no tracked leaks.
The unchanged INSERT, UPDATE, DELETE, and UPSERT suites (`insert.test` through
`insert5.test`, `update.test`, `update2.test`, `delete.test` through
`delete4.test`, and `upsert1.test` through `upsert5.test`) also pass 964/964,
with clean leak summaries. The temporary Tcl adapter routes the upstream
`ENABLE_QPSG` request through the connection's `config enable_qpsg` command;
all upstream test files remain unchanged.

Virtual-table interface checks using the unchanged upstream `qpvtab` module
pass `vtabdistinct.test` (5/5) and `vtabrhs1.test` (8/8), with no tracked
allocations. The echo-module runner now compiles upstream `src/test8.c` as a
test adapter, so the unchanged `vtab1.test` exercises SQLite's echo module.
The FreeBASIC fixture profile passes its 212 enabled cases with no tracked
leaks. The C `testfixture` baseline passes 223/223; its additional 11 cases
are guarded by `ifcapable fts3`, and FTS3 is not compiled into the FreeBASIC
test profile.

A C2FB audit found no missing routine behind the join failures. Both causes
were integration errors in existing FreeBASIC code: high opcode flags were
rejected by expression constructors, and the parser driver honored
`SQLITE_DONE` before reporting a syntax error on the lookahead. No C2FB or FBC
change was needed.

The unchanged `pragma.test` passes 127/127 after a pager-cache fix for small
file-backed TEMP databases. When phase one skipped writing a TEMP database
because fewer than 25% of its cache pages were dirty, phase two incorrectly
marked every cached page clean and discarded the only committed copy. The
FreeBASIC pager now uses SQLite's `pagerFlushOnCommit` condition in both commit
phases and keeps writable dirty pages cached when the backing file was not
flushed. That exposed a second parity issue: committed TEMP pages can need a
cache spill after the pager returns to reader state, so `pagerStress()` must
not reject those spills based on the pager state. A direct `cache_size=1`
reproduction now succeeds. The unchanged `tempdb.test`, `tempdb2.test`,
`temptable.test`, and `temptable2.test` suites pass 6/6, 8/8, 63/63, and
256/256 respectively. `pager1.test` passes 1,382/1,382, `pager3.test` passes
13/13, and `wherefault.test` passes 5,082/5,082. All these runs report no
tracked allocation leaks.

The backup cases in `temptable2.test` exposed one related classification
mismatch: SQLite's `sqlite3PagerIsMemdb()` includes file-backed TEMP pagers when
checking whether a backup may change page size. The FreeBASIC implementation
now matches that rule. The updated `SQLITE_TEST` library also passes
`pragma.test` 127/127, and the release library has been rebuilt after these
changes.
`tempfault.test` passes 6,381/6,381 cases through the temporary bridge with
VFS OOM injection enabled and no tracked allocation leaks. The unchanged C
`testfixture` baseline passes 16,419/16,419. The group 3 savepoint fault cases
now pass, including the deterministic `SQLITE_FULL` failure during
`ROLLBACK TO` that previously left duplicate references in the index tree.
The fault exposed a missing special-error branch in the existing
`sqlite3VdbeHalt` body: SQLite rolls back the statement when a `FULL` or
`NOMEM` error has a statement journal, and rolls back the full transaction
when no statement journal can restore consistency. The FreeBASIC halt path
now follows that decision for `FULL`, `NOMEM`, `IOERR`, and `INTERRUPT` errors.
The unchanged `sortfault.test` also passes 23,295/23,295 with no tracked leaks.
No C2FB or FBC changes were needed, and the upstream test scripts remain
unchanged.

The index-family sweep passes 776 assertions across `index.test` through
`index9.test`, `indexA.test`, `indexedby.test`, and `indexexpr1.test` through
`indexexpr3.test`, with no tracked allocation leaks. `index7.test` found a
cursor-restore bound error for WITHOUT ROWID records: the restore buffer was
set to the total payload field count instead of the key field count plus its
tie-break field. `indexexpr2.test` found a grouped scalar subquery whose LIMIT
exit label also ran on normal scan completion; the final group is now emitted
before that exit path. After the repair, `select1.test` through `select4.test`
pass 435/435, `aggnested.test` 48/48, and `aggorderby.test` 30/30. `index6`
and `index7` use the unchanged upstream
wholenumber extension, `indexexpr2` uses the unchanged explain extension, and
`index9` uses the test bridge's QPSG adapter. No upstream test files changed.

The unchanged backup API suites also pass: `backup.test` 869/869 and
`backup2.test` 16/16 under `SQLITE_DEBUG` (matching the C test fixture's
debug-only source-transaction cleanup), `backup4.test` 12/12,
`backup5.test` 20/20, `backup_malloc.test` 62/62, and `backup_ioerr.test`
52/52. The pragma follow-up suites pass `pragma2.test` 1/1, `pragma3.test`
24/24, `pragma4.test` 108/108, and `pragma5.test` 6/6. The temporary
`pragma3` runner loads the FreeBASIC-backed Tcl extension in its child process;
the upstream test contents remain unchanged. These runs end with no tracked
allocation leaks.

The next planner sweep passed 3,009 assertions across automatic-index,
quick-check, WHERE, skip-scan, ORDER BY, transitive-constraint, and covering
index tests. This includes `autoindex2.test` through `autoindex5.test`,
`where2.test` through `whereN.test`, `wherelimit.test` through
`wherelimit3.test`, `skipscan1.test`, `orderby1.test`, `orderby2.test`,
`transitive1.test`, `coveridxscan.test`, and `quickcheck.test`. The temporary
test runners match the C fixture's `like_match_blobs` setting and expose its
optimizer controls. A direct release C-API probe also confirms that
`SQLITE_CONFIG_COVERING_INDEX_SCAN` changes the scan order after shutdown and
reinitialization. The upstream tests remain unchanged, and these runs end
without tracked allocations.

The unchanged `IN` operator suites pass 2,363/2,363 across `in.test` through
`in7.test`, with no tracked allocations. `in6.test` exposed that the VDBE
treated `OP_IfNoHope` as a no-op, so composite-index `IN` probes did not stop
after a prior seek had established the needed key prefix. The VDBE now checks
the cursor's `seekHit` value before falling through to the normal NotFound
lookup. This was a behavior repair in the existing executor; no C2FB or FBC
change was needed.

After the index and aggregate changes, `btreefault.test` passes 124/124,
`indexfault.test` passes its active 1/1 case, and `wherefault.test` passes
5,082/5,082, all with no tracked allocation leaks.

Sorter coverage now includes `sort.test` 92/92, `sort2.test` 13/13,
`sort3.test` 7/7, `sort4.test` 11/11, and `sort5.test` 16/16, all leak-clean.
`sort4.test` used temporary harness adapters for its sorter verifier and worker
thread limit. `sort.test` exposed that the memjournal initializer rejected a
null static mutex after `SQLITE_CONFIG_SINGLETHREAD`, although runtime
single-thread mode makes one-time method-table initialization safe. The
FreeBASIC pager now follows the C behavior in this case. A `SQLITE_TEST`-only
heap-sentinel hook lets the unchanged sort test drive the same fake-heap state
as SQLite's test helper.

`sortfault.test` passes 23,295/23,295 assertions with no tracked allocation
leaks. It previously stopped because the port lacked the test-only VFS OOM
switch. The `sqlite3Os*` wrappers now reproduce upstream `DO_OS_MALLOC_TEST`
behavior at the same VFS dispatch boundaries, including the in-memory journal
exception and file-control exclusions. The unchanged Tcl test runs through a
temporary bridge that exposes the test switch and existing SQLite test
helpers. The sorter suite was rerun after the pager/B-tree rollback changes.


Shared-cache validation now covers the unchanged upstream `shared.test`
(207 enabled cases), `shared2.test` (13), `shared3.test` (16), `shared4.test`
(17), `shared6.test` (40), `shared7.test` (5), `shared8.test` (11),
`shared9.test` (17), `sharedlock.test` (13), `sharedA.test` (9), and
`sharedB.test` (102): 450 cases with no tracked leaks. Four optional
`shared.test` checks use the fixture-only
`sqlite3_shared_cache_report` command, and three `shared9.test` checks require
FTS3. The test runner directly links the FreeBASIC library and supplies the
shared-cache and UTF-16 fixture commands; parent and child processes receive
the same 64 KiB pending-byte setting.

These tests found three existing port defects. B-tree rollback now sets the
shared state back to `TRANS_READ` before ending the writer transaction, and
connection close checks only cursors owned by that handle. The Unix VFS now
registers `unix-none` with no-lock file methods. The VDBE abort path returns
`SQLITE_ERROR` while retaining the original error in `pVdbe->rc`; its
`OP_Transaction` busy path keeps the program counter for retry. The unchanged
`tempfault.test` passes 6,081 enabled cases and `sortfault.test` passes
23,295/23,295, both without tracked leaks. The full WAL suite still passes
1,843/1,843. Upstream test files were not changed.

The unchanged `shared_err.test` completes with 0 errors out of 6,569 reported
tests. Its I/O-fault phase passes 6,567 assertions through a temporary Tcl
bridge that calls the port's PRNG save/restore controls and links the I/O-fault
counters. The runner explicitly skips its 8 allocator-failure groups because
this profile has no allocation-failure hook; `finish_test` reports all tracked
allocations freed. A temporary adapter around unchanged `src/test_thread.c`
provides the real worker-thread path used by `sharedA.test` and `sharedB.test`;
both suites pass with no tracked leaks. `sharedA.test` steps a prepared
statement on a worker thread during another handle's rollback. Upstream test
files remain unchanged.

The unchanged `thread001.test` and `thread002.test` now pass 52/52 and 15/15
with no tracked leaks. Both run the upstream `src/test_thread.c` worker code;
`thread001` covers same-handle, separate-handle, and shared-cache writers, while
`thread002` overlaps transactions across three attached databases. These runs
found that VDBE execution was not holding the shared B-tree mutex while it read
cursor pages. The executor now acquires/releases VDBE-declared B-tree locks for
each execution slice and during halt cleanup. `sqlite3BtreeEnterAll()` and
`sqlite3BtreeLeaveAll()` now cover every shared attached database, and the
aggregate SELECT compiler no longer marks `mayAbort` without an abort-capable
VDBE opcode. Release `thread001`/`thread002` and debug `thread001`/`thread002`
all pass.

After these source changes, the ordinary release target
`build/libsqlite3-fb.so` rebuilt successfully and reports up to date.

The source-line tracker remains at 124,545 of 192,194 in-scope upstream lines
(64.8%); all 3,243 in-scope indexed function entries have FreeBASIC bodies.
This is body coverage, not full behavioral parity. No C2FB change was needed:
the failures came from missing lock integration and one extra error-analysis
call, not missing indexed SQLite routine bodies. The allocator-failure groups
in `shared_err.test` remain unavailable in this profile.

## Authorizer and TEMP authorization checkpoint (2026-10-16)

The unchanged `auth.test`, `auth2.test`, and `auth3.test` pass 343, 15, and 10
test cases with no tracked leaks. `temptable.test` passes 62/62. These runs
found that FreeBASIC represents a true comparison as -1, while the parser's
TEMP action must pass the C integer value 1 to `sqlite3StartTable`; the action
now stores exactly 0 or 1. SELECT compilation also emits SQLite's
`SQLITE_SELECT` authorization event, and unreferenced FROM terms receive the
empty-column `SQLITE_READ` event.

The FreeBASIC test library uses the same 1,024-byte default page size as the
C fixture, and its Tcl bridge forwards the fixture's 64 KiB pending-byte
setting. This matters when a database uses 8,192-byte pages: page 9 holds the
reserved lock byte and `PRAGMA page_count` reports 10, matching C. The
temporary runner also exposes the fixture's `sqlite3_backup`,
`atomic_batch_write`, and `test_error` support commands and sets `TEMP_STORE`
to the profile's value of 1.

With that fixture setup, the unchanged `temptable.test`, `temptable2.test`,
`tempdb.test`, `tempdb2.test`, `temptable3.test`, and `temptrigger.test` pass
62, 256, 6, 8, 3, and 1 test cases respectively, with no tracked leaks.
Upstream Tcl tests remain unchanged.

These fixes were in parser semantic values and SELECT integration. No C2FB or
FBC change was needed.

## JSON runtime checkpoint (2026-10-16)

The unchanged `json101.test` through `json109.test`, `json501.test`,
`json502.test`, and `jsonb01.test` pass 45,993 cases with no tracked leaks.
The temporary Tcl bridge supplies `strdup()` and loads the upstream C
`randomjson` test extension against the FreeBASIC library; JSON test files were
not modified.

## Virtual-table runtime checkpoint (2026-10-16)

The unchanged `vtab1.test` passes all 212 cases enabled in the FreeBASIC test
profile, with no tracked leaks. Its `vtab1-23.3.1` regression calls
`DROP TABLE` from an `eval()` callback while the outer statement still has an
`OP_VUpdate` pending. The nested drop clears the VTable's `pVtab`; SQLite
returns `SQLITE_LOCKED` when the outer VDBE reaches `OP_VUpdate`. The port
previously returned `SQLITE_READONLY` for the same state. The VDBE now returns
`SQLITE_LOCKED` when that wrapper has no virtual-table instance or module.

The C reference passes 223/223 cases. Its additional 11 FTS3-only cases are
disabled in the FreeBASIC profile. Both the test-profile and ordinary release
libraries rebuilt successfully after the fix. No C2FB or FBC change was
needed.

## Bit-vector runtime checkpoint (2026-10-16)

The unchanged `bitvec.test` passes 72/72 cases in both the FreeBASIC profile
and C `testfixture`, with no tracked leaks. The temporary Tcl bridge exposes
the upstream test2 command by calling the port's `SQLITE_TESTCTRL_BITVEC_TEST`;
it also installs a C-compatible allocator fault-simulation wrapper before
SQLite initializes. The run includes the upstream allocation-failure
iterations.

The first bit-vector run found mismatches in ordinary set and clear checks.
The reference comparison converted a FreeBASIC Boolean directly to
`SQLITE_C_INT`, producing -1 for true where the C `!= 0` expression produces
1. The reference check now stores 0 or 1 explicitly. No C2FB or FBC change
was needed.

The current focused checkpoints cover 46,981 passing cases across authorizer,
TEMP, JSON, virtual-table, and bit-vector suites. This is not a whole-suite
count; the VTab profile omits 11 FTS3-only cases.
