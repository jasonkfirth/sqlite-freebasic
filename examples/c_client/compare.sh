#!/bin/sh
# -----------------------------------------------------------------------------
# Project: SQLite FreeBASIC port
# File: compare.sh
# Purpose: Build the C client against the FreeBASIC port and a C reference,
#          verify database-file exchange, and report comparable measurements.
# Responsibilities: Pin the upstream source, build both libraries, run the
#                   same workload, and report library sizes and process memory.
# This file intentionally does NOT modify the upstream source checkout.
# -----------------------------------------------------------------------------
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
upstream_dir=${1:-${SQLITE_SOURCE_DIR:-}}
if [ -z "$upstream_dir" ]; then
    echo "usage: $0 SQLITE_SOURCE_DIR [ROWS]" >&2
    exit 2
fi
upstream_dir=$(CDPATH= cd -- "$upstream_dir" && pwd)
if [ "$#" -gt 0 ]; then
    shift
fi
rows=${1:-${DEMO_ROWS:-100000}}
repeats=${DEMO_REPEATS:-5}
case "$repeats" in
    ''|*[!0-9]*) echo "DEMO_REPEATS must be a positive integer" >&2; exit 2 ;;
esac
if [ "$repeats" -lt 1 ]; then
    echo "DEMO_REPEATS must be a positive integer" >&2
    exit 2
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
    echo "SQLite VERSION does not match the comparison source" >&2
    exit 2
fi

FBC=${FBC:-fbc}
CC=${CC:-cc}
MAKE=${MAKE:-make}
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/sqlite-fb-client.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
mkdir -p "$work_dir/upstream" "$work_dir/bin"
git -C "$upstream_dir" archive "$expected_commit" | tar -xf - -C "$work_dir/upstream"

(
    cd "$work_dir/upstream"
    ./configure --disable-tcl --disable-readline > "$work_dir/configure.log" 2>&1
    "$MAKE" sqlite3.c > "$work_dir/upstream-build.log" 2>&1
)
if [ ! -s "$work_dir/upstream/sqlite3.c" ]; then
    cat "$work_dir/configure.log" >&2
    cat "$work_dir/upstream-build.log" >&2
    echo "upstream amalgamation was not generated" >&2
    exit 1
fi

fbc_version=$("$FBC" -version | sed -n '1p')
fbc_slug=$(printf '%s' "$fbc_version" | sed 's/[^A-Za-z0-9_-]/_/g')
fb_target="build/benchmark/$fbc_slug/libsqlite3-fb.so"
fb_library="$repo_dir/fb_src/$fb_target"
if ! "$MAKE" -C "$repo_dir/fb_src" FBC="$FBC" CC="$CC" \
    TARGET="$fb_target" FB_DEFINE_FLAGS='-O 2' >"$work_dir/freebasic-build.log" 2>&1; then
    tail -80 "$work_dir/freebasic-build.log" >&2
    exit 1
fi

"$CC" -O2 -fPIC -shared -DSQLITE_THREADSAFE=1 \
    -I"$work_dir/upstream" "$work_dir/upstream/sqlite3.c" \
    -ldl -lm -lpthread -o "$work_dir/libsqlite3-upstream.so"

"$CC" -O2 -std=c99 -I"$work_dir/upstream" \
    "$repo_dir/examples/c_client/demo.c" \
    -L"$(dirname -- "$fb_library")" \
    -Wl,-rpath,"$(dirname -- "$fb_library")" \
    -lsqlite3-fb -ldl -lm -o "$work_dir/bin/demo-fb"
"$CC" -O2 -std=c99 -I"$work_dir/upstream" \
    "$repo_dir/examples/c_client/demo.c" \
    -L"$work_dir" -Wl,-rpath,"$work_dir" \
    -lsqlite3-upstream -ldl -lm -o "$work_dir/bin/demo-upstream"

printf 'SQLite source: %s (%s)\n' "$(tr -d '\r\n' < "$upstream_dir/VERSION")" "$actual_commit"
printf 'FreeBASIC compiler: %s\n' "$fbc_version"
printf '\nLibrary sizes (bytes)\n'
stat -c '%n %s' "$fb_library" "$work_dir/libsqlite3-upstream.so"

printf '\nDatabase-file exchange\n'
"$work_dir/bin/demo-fb" seed "$work_dir/from-freebasic.db" "$rows"
"$work_dir/bin/demo-upstream" check "$work_dir/from-freebasic.db" "$rows"
"$work_dir/bin/demo-upstream" seed "$work_dir/from-upstream.db" "$rows"
"$work_dir/bin/demo-fb" check "$work_dir/from-upstream.db" "$rows"

run_benchmarks(){
    label=$1
    executable=$2
    output="$work_dir/$label.bench"
    "$executable" bench "$rows" >/dev/null
    iteration=1
    while [ "$iteration" -le "$repeats" ]; do
        "$executable" bench "$rows"
        iteration=$((iteration + 1))
    done > "$output"
    printf '\n%s workload (%s measured runs after one warm-up)\n' "$label" "$repeats"
    cat "$output"
    python3 - "$label" "$repeats" "$output" <<'PYBENCH'
import statistics
import sys

label, count, filename = sys.argv[1:]
measurements = []
with open(filename, encoding="utf-8") as source:
    for line in source:
        values = dict(item.split("=", 1) for item in line.split()[1:])
        measurements.append({
            "elapsed_seconds": float(values["elapsed_seconds"]),
            "rows_per_second": float(values["rows_per_second"]),
            "sqlite_memory_used_bytes": int(values["sqlite_memory_used_bytes"]),
            "peak_rss_kib": int(values["peak_rss_kib"]),
        })
if len(measurements) != int(count):
    raise SystemExit(f"expected {count} benchmark runs, found {len(measurements)}")
print(
    "MEDIAN label={} samples={} elapsed_seconds={:.3f} rows_per_second={:.0f} "
    "sqlite_memory_used_bytes={} peak_rss_kib={}".format(
        label,
        count,
        statistics.median(x["elapsed_seconds"] for x in measurements),
        statistics.median(x["rows_per_second"] for x in measurements),
        int(statistics.median(x["sqlite_memory_used_bytes"] for x in measurements)),
        int(statistics.median(x["peak_rss_kib"] for x in measurements)),
    )
)
PYBENCH
}

run_benchmarks freebasic "$work_dir/bin/demo-fb"
run_benchmarks upstream "$work_dir/bin/demo-upstream"

# end of compare.sh
