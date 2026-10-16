# Qualification report

This report separates the current reproducible run from older development
notes. The current runner executes each listed test file once and reports the
number of upstream `do_test` calls. It does not count retries, repeated manual
runs, or the C reference run as additional port cases.

## Source revisions

- SQLite: `3.54.0`, commit [`64c2f58d739e7ca1633a7b7fbe7e5bf053f29ef5`](https://github.com/sqlite/sqlite/commit/64c2f58d739e7ca1633a7b7fbe7e5bf053f29ef5), dated 2026-10-08.
- FreeBASIC qualification compiler: upstream `1.20.0`, source commit [`5714d10adb21ba0d5d65d7d497ac32f509bb95ff`](https://github.com/freebasic/fbc/commit/5714d10adb21ba0d5d65d7d497ac32f509bb95ff). This source was built without maintainer patches using the official 1.10.1 bootstrap compiler.
- Earlier official compiler release checked: [`FreeBASIC 1.10.1`](https://github.com/freebasic/fbc/releases/tag/1.10.1), source commit [`14dbf158b85bfe24ed4a56f2d16d499423e38594`](https://github.com/freebasic/fbc/commit/14dbf158b85bfe24ed4a56f2d16d499423e38594).

The official upstream 1.20.0 compiler build passed all selected JSON tests below. The 1.10.1 release builds the FreeBASIC test library, but four cases fail: `json101-1.4` and `json101-1.4b` return `-1.0` where the test expects integer `-1`; `json103-400` and `json103-410` report a malformed database during JSON window aggregation. The other 45,977 cases pass under 1.10.1. This release is therefore not fully qualified for the current test set.

**Compiler compatibility:** the tested port does not require the maintainer's FBC fork for this configuration. It is qualified with upstream FBC 1.20.0. FreeBASIC 1.10.1 is too old to reproduce the complete JSON qualification.

## Reproducible upstream tests

Command:

```sh
./tests/run_upstream.sh /path/to/sqlite-source
```

The runner checks out no files itself. It requires the exact SQLite commit above, verifies the upstream `test/` tree is unmodified, builds a test-profile FreeBASIC library, and runs each test in an isolated temporary directory.

| Upstream test file | Passed | Failed | Skipped capability blocks |
|---|---:|---:|---:|
| `json101.test` | 281 | 0 | 0 |
| `json102.test` | 316 | 0 | 0 |
| `json103.test` | 14 | 0 | 0 |
| `json104.test` | 33 | 0 | 0 |
| `json105.test` | 52 | 0 | 0 |
| `json106.test` | 45,000 | 0 | 0 |
| `json107.test` | 15 | 0 | 0 |
| `json108.test` | 17 | 0 | 0 |
| `json109.test` | 17 | 0 | 0 |
| `json501.test` | 184 | 0 | 0 |
| `json502.test` | 12 | 0 | 0 |
| `jsonb01.test` | 40 | 0 | 0 |
| **Total** | **45,981** | **0** | **0** |

Every test file ran once. The stock SQLite C `testfixture` reports 45,982 for
this selection because its final reporting routine increments its counter
once after the test cases; the case table above counts the 45,981 actual test
invocations.

This is a selected qualification, not the complete SQLite test suite. The
runner currently covers JSON and JSONB tests; other suite results in the
archived engineering log are historical manual runs and are not part of this
CI total.

## Relationship to SQLite's quicktest target

At the pinned SQLite revision, `make quicktest` is an alias for `devtest` in
[`main.mk`](https://github.com/sqlite/sqlite/blob/64c2f58d739e7ca1633a7b7fbe7e5bf053f29ef5/main.mk#L1943).
`devtest` invokes the test runner's `mdevtest` plan. SQLite documents that plan
as the `veryquick` Tcl suite plus fuzz tests under two build configurations,
one debug and one non-debug ([test runner documentation](https://github.com/sqlite/sqlite/blob/64c2f58d739e7ca1633a7b7fbe7e5bf053f29ef5/doc/testrunner.md#L266)).
That is a multi-build qualification, so a single test count needs to say
whether it counts distinct cases, executions across both builds, or fuzz
inputs. The separate `test/quick.test` script runs the Tcl suite named
`quick`; it is not the implementation of the `make quicktest` target.

The current FreeBASIC CI does not claim to pass either `make quicktest` or the
full `quick`/`veryquick` Tcl suite. Its published Tcl bridge implements the
commands needed by the JSON and JSONB suites listed above. The roughly 46,000
case count therefore describes those selected tests only.

## Tcl bridge and fixture adaptations

The runner builds upstream `src/tclsqlite.c` as a Tcl shell and links it to the
FreeBASIC test library. The upstream `.test` files are symlinked into a
temporary test directory without edits. The replacement `tester.tcl` is
[`tests/tcl_bridge.tcl`](tests/tcl_bridge.tcl), which provides the SQL helpers,
case accounting, capability checks, database reset, and extension-loading
commands used by the selected suites.

[`tests/tcl_bridge.c`](tests/tcl_bridge.c) exposes
`sqlite3_test_control_pending_byte` by calling the port's
`sqlite3_test_control()` API. The runner builds the upstream `randomjson.c` and
`strdup.c` test extensions as shared modules and loads them through SQLite's
extension API. The bridge implements only the commands needed by this selected
suite; it is not a replacement for SQLite's full `testfixture` program.

## C-client sample

[`examples/c_client/demo.c`](examples/c_client/demo.c) exercises the public C
API with a prepared-statement workload. The comparison was run on 64-bit Linux
with SQLite 3.54.0 and upstream FBC 1.20.0. Both libraries used `-O2`; the
client inserted 100,000 rows in memory. The script made one warm-up run and
reported the median of five measured runs.

| Metric | FreeBASIC library | Upstream C library |
|---|---:|---:|
| Shared library size | 1,548,392 bytes | 1,225,576 bytes |
| Median elapsed time | 0.247 s | 0.055 s |
| Median throughput | 404,682 rows/s | 1,806,900 rows/s |
| SQLite allocator use after workload | 3,415,608 bytes | 3,396,632 bytes |
| Peak process RSS | 7,536 KiB | 6,228 KiB |

The databases passed in both directions: the FreeBASIC client wrote a file
that upstream SQLite verified, and upstream SQLite wrote a file that the
FreeBASIC client verified. These are one-host measurements. The database-file
exchange is deterministic; timing and RSS can vary by host.
