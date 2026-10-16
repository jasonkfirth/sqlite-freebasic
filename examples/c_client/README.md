# C client comparison

`demo.c` uses only SQLite's public C API. The comparison script builds it once
against the FreeBASIC shared library and once against the C amalgamation from
the pinned upstream SQLite checkout.

Run the test command with an unmodified upstream SQLite checkout at the pinned
revision:

```sh
examples/c_client/compare.sh /path/to/sqlite-source 100000
```

The script checks that both libraries can read the same database file in turn,
then runs the same in-memory insert and aggregate workload. It reports
shared-library sizes, raw timing samples, and the median of five
measured runs after one warm-up. Each run also reports SQLite allocator usage
and Linux peak resident memory. The output is a local measurement, not a
performance guarantee.

The C library uses `cc -O2`; the FreeBASIC library uses `-O 2`. Both are built
from the same SQLite source version and target the same 64-bit Linux host.

The default workload inserts 100,000 rows. `DEMO_ROWS` sets a different count
when it is not passed on the command line.
