#!/bin/sh
# -----------------------------------------------------------------------------
# Project: SQLite FreeBASIC port
# File: run_upstream.sh
# Purpose: Build a test-profile library and run selected unchanged SQLite Tcl
#          suites through the published Tcl bridge.
# Responsibilities: Pin the upstream test revision, build prerequisites, stage
#                   tests without writing into the upstream checkout, and
#                   report per-suite counts.
# This file intentionally does NOT modify upstream test files.
# -----------------------------------------------------------------------------
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
upstream_dir=${1:-${SQLITE_SOURCE_DIR:-}}
if [ -z "$upstream_dir" ]; then
    echo "usage: $0 SQLITE_SOURCE_DIR [json101.test ...]" >&2
    exit 2
fi
upstream_dir=$(CDPATH= cd -- "$upstream_dir" && pwd)
if [ "$#" -gt 0 ]; then
    shift
fi
expected_commit=$(tr -d '\r\n' < "$repo_dir/tests/upstream-commit.txt")
actual_commit=$(git -C "$upstream_dir" rev-parse HEAD)
if [ "$actual_commit" != "$expected_commit" ]; then
    echo "SQLite source commit mismatch" >&2
    echo "expected: $expected_commit" >&2
    echo "actual:   $actual_commit" >&2
    exit 2
fi
if [ "$(tr -d '\r\n' < "$upstream_dir/VERSION")" != "3.54.0" ]; then
    echo "SQLite VERSION does not match the qualification source" >&2
    exit 2
fi
if [ -n "$(git -C "$upstream_dir" status --porcelain --untracked-files=all -- test)" ]; then
    echo "upstream test tree has local changes or untracked files" >&2
    exit 2
fi

FBC=${FBC:-fbc}
CC=${CC:-cc}
TCLSH=${TCLSH:-tclsh}
MAKE=${MAKE:-make}
PKG_CONFIG=${PKG_CONFIG:-pkg-config}
TCL_CFLAGS=${TCL_CFLAGS:-}
TCL_LIBS=${TCL_LIBS:-}
if [ -z "$TCL_CFLAGS" ]; then
    TCL_CFLAGS=$($PKG_CONFIG --cflags tcl8.6 2>/dev/null || true)
fi
if [ -z "$TCL_CFLAGS" ]; then
    TCL_CFLAGS=-I/usr/include/tcl8.6
fi
if [ -z "$TCL_LIBS" ]; then
    TCL_LIBS=$($PKG_CONFIG --libs tcl8.6 2>/dev/null || true)
fi
if [ -z "$TCL_LIBS" ]; then
    TCL_LIBS=-ltcl8.6
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/sqlite-fb-qualification.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
mkdir -p "$work_dir/include" "$work_dir/extensions" "$work_dir/test" "$work_dir/run"

suite_list="${*:-json101.test json102.test json103.test json104.test json105.test json106.test json107.test json108.test json109.test json501.test json502.test jsonb01.test}"

for suite in $suite_list; do
    case "$suite" in
        *.test) ;;
        *) suite="$suite.test" ;;
    esac
    if ! git -C "$upstream_dir" ls-files --error-unmatch "test/$suite" >/dev/null 2>&1; then
        echo "test/$suite is not tracked at the pinned SQLite revision" >&2
        exit 2
    fi
done

fbc_version=$("$FBC" -version | sed -n '1p')
fbc_slug=$(printf '%s' "$fbc_version" | sed 's/[^A-Za-z0-9_-]/_/g')
fb_target="build/qualification/$fbc_slug/libsqlite3-fb-test.so"
fb_library="$repo_dir/fb_src/$fb_target"
if ! "$MAKE" -C "$repo_dir/fb_src" FBC="$FBC" CC="$CC" \
    TARGET="$fb_target" \
    FB_DEFINE_FLAGS='-d SQLITE_TEST' >"$work_dir/freebasic-build.log" 2>&1; then
    tail -80 "$work_dir/freebasic-build.log" >&2
    exit 1
fi

"$CC" -O2 -o "$work_dir/mksourceid" "$upstream_dir/tool/mksourceid.c"
(
    cd "$work_dir"
    "$TCLSH" "$upstream_dir/tool/mksqlite3h.tcl" "$upstream_dir" \
        -o "$work_dir/include/sqlite3.h"
)

# The Tcl shell uses the SQLite public C API, so every SQL operation below
# reaches the FreeBASIC library linked here.
# shellcheck disable=SC2086
"$CC" -O2 -DTCLSH \
    -I"$work_dir/include" -I"$upstream_dir/src" $TCL_CFLAGS \
    "$upstream_dir/src/tclsqlite.c" \
    -L"$(dirname -- "$fb_library")" \
    -Wl,-rpath,"$(dirname -- "$fb_library")" \
    -lsqlite3-fb-test $TCL_LIBS -ldl -lm \
    -o "$work_dir/tclsqlite-fb"

# shellcheck disable=SC2086
"$CC" -O2 -fPIC -shared -DSQLITE_TEST \
    -I"$work_dir/include" -I"$upstream_dir/src" $TCL_CFLAGS \
    "$repo_dir/tests/tcl_bridge.c" \
    -L"$(dirname -- "$fb_library")" \
    -Wl,-rpath,"$(dirname -- "$fb_library")" \
    -lsqlite3-fb-test $TCL_LIBS \
    -o "$work_dir/fb_tcl_bridge.so"

"$CC" -O2 -fPIC -shared -I"$work_dir/include" -I"$upstream_dir/src" \
    "$upstream_dir/ext/misc/randomjson.c" \
    -o "$work_dir/extensions/randomjson.so"
"$CC" -O2 -fPIC -shared -I"$work_dir/include" -I"$upstream_dir/src" \
    "$upstream_dir/ext/misc/strdup.c" \
    -o "$work_dir/extensions/strdup.so"

python3 - "$upstream_dir/test" "$work_dir/test" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
for path in source.rglob("*"):
    relative = path.relative_to(source)
    target = destination / relative
    if path.is_dir():
        target.mkdir(parents=True, exist_ok=True)
    elif path.is_file():
        if path.name == "tester.tcl" or path.suffix == ".db":
            continue
        if path.name.endswith(("-journal", "-wal", "-shm")):
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.symlink_to(path)
PY
cp "$repo_dir/tests/tcl_bridge.tcl" "$work_dir/test/tester.tcl"
ln -s "$upstream_dir/src" "$work_dir/src"
ln -s "$upstream_dir/ext" "$work_dir/ext"
ln -s "$upstream_dir/tool" "$work_dir/tool"

printf 'SQLite %s (%s)\n' "$(tr -d '\r\n' < "$upstream_dir/VERSION")" "$actual_commit"
printf '%s\n' "$fbc_version"
failed=0
for suite in $suite_list; do
    case "$suite" in
        *.test) ;;
        *) suite="$suite.test" ;;
    esac
    echo "Running unchanged test/$suite"
    run_dir="$work_dir/run/$suite"
    mkdir -p "$run_dir"
    if (
        cd "$run_dir"
        FB_TCL_BRIDGE="$work_dir/fb_tcl_bridge.so" \
        FB_TEST_EXTENSION_DIR="$work_dir/extensions" \
        FB_TEST_FILE="$work_dir/test/$suite" \
        FB_TEST_SUITE="$suite" \
        LD_LIBRARY_PATH="$(dirname -- "$fb_library")${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        "$work_dir/tclsqlite-fb" "$repo_dir/tests/run_one.tcl"
    ); then
        :
    else
        failed=1
    fi
done
if [ "$failed" -ne 0 ]; then
    exit 1
fi

# end of run_upstream.sh
