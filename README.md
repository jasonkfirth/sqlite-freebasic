# SQLite FreeBASIC port

[![Linux qualification](https://github.com/jasonkfirth/sqlite-freebasic/actions/workflows/linux-qualification.yml/badge.svg)](https://github.com/jasonkfirth/sqlite-freebasic/actions/workflows/linux-qualification.yml)

A FreeBASIC implementation of the SQLite engine, preserving SQLite's public C
ABI. The implementation is in [`fb_src/`](fb_src/); the checked-in generated
tables are supported by [`fb_tools/sqlite_codegen/`](fb_tools/sqlite_codegen/).
The included port source is dedicated to the public domain; see
[LICENSE.md](LICENSE.md).

## Build

To reproduce the current qualification, use the pinned upstream FreeBASIC
1.20.0 source revision listed in [QUALIFICATION.md](QUALIFICATION.md). Install
that compiler and GNU Make, then run:

```sh
make -C fb_src
```

This builds the checked-in FreeBASIC units and generated includes. Build
products go under `fb_src/build/`.

## Qualification

Automated qualification covers 45,981 unchanged upstream JSON and JSONB test
cases. Consolidated historical suite reports record 66,961 passing test
executions, counting repeated reports of the same suite once; those manual
runs span development and do not represent one configuration or a `quicktest`
run.

See [QUALIFICATION.md](QUALIFICATION.md) for the exact SQLite and FreeBASIC
source revisions, per-suite counts, compiler compatibility results, test
fixture adaptations, and a C-client comparison.

Run the selected unchanged upstream JSON tests against a checkout at the
pinned SQLite revision with:

```sh
./tests/run_upstream.sh /path/to/sqlite-source
```

The runner validates the checkout and rejects local edits to upstream test
files. GitHub Actions runs the same qualification on Linux.

## C client

[`examples/c_client/compare.sh`](examples/c_client/compare.sh) builds a small
public-API client against both libraries, verifies that each can read the
other's database file, and reports timing, memory, and library-size samples.

## Development history

The old chronological engineering log is retained in
[docs/DEVELOPMENT_HISTORY.md](docs/DEVELOPMENT_HISTORY.md). It contains
historical state and is not the current qualification record.

The optional C2FB translator is not included in this repository because its
own project declares GPL-3.0-or-later. Some source-regeneration targets in
`fb_src/Makefile` require that tool and an adjacent SQLite C source checkout.
