/*
    Project: SQLite FreeBASIC port
    ------------------------------

    File: demo.c

    Purpose:

        Exercise SQLite's public C API with a prepared-statement workload
        that can run against either the FreeBASIC port or upstream SQLite.

    Responsibilities:

        - Create or verify a deterministic database file.
        - Run an in-memory insert and aggregate workload.
        - Report elapsed time, SQLite allocator usage, and Linux peak RSS.

    This file intentionally does NOT contain:

        - SQLite implementation code.
        - Engine-specific calls outside the public SQLite API.
*/
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/resource.h>
#include "sqlite3.h"

/* Keep the demo bounded so expected checksums fit in signed 64-bit values. */
#define DEMO_MAX_ROWS ((sqlite3_int64)10000000)
#define PAYLOAD_LENGTH 18

static int report_error(sqlite3 *db, const char *operation, int rc){
    const char *message = db ? sqlite3_errmsg(db) : "no database handle";
    fprintf(stderr, "%s failed: %s (SQLite result %d)\n", operation, message, rc);
    return 1;
}

static int execute_sql(sqlite3 *db, const char *sql){
    char *message = NULL;
    int rc = sqlite3_exec(db, sql, NULL, NULL, &message);
    if( rc!=SQLITE_OK ){
        fprintf(stderr, "SQL failed: %s\n", message ? message : sqlite3_errmsg(db));
        sqlite3_free(message);
        return rc;
    }
    sqlite3_free(message);
    return SQLITE_OK;
}

static int populate_database(sqlite3 *db, sqlite3_int64 rows){
    sqlite3_stmt *statement = NULL;
    sqlite3_int64 row;
    int rc;

    rc = execute_sql(db,
        "PRAGMA journal_mode=OFF;"
        "PRAGMA synchronous=OFF;"
        "BEGIN;"
        "DROP TABLE IF EXISTS items;"
        "CREATE TABLE items(id INTEGER PRIMARY KEY, value INTEGER NOT NULL, payload TEXT NOT NULL);"
    );
    if( rc!=SQLITE_OK ) return report_error(db, "database setup", rc);

    rc = sqlite3_prepare_v2(
        db,
        "INSERT INTO items(id,value,payload) VALUES(?1,?2,?3)",
        -1,
        &statement,
        NULL
    );
    if( rc!=SQLITE_OK ) return report_error(db, "prepare insert", rc);

    for(row=1; row<=rows; row++){
        char payload[32];
        int length = snprintf(payload, sizeof(payload), "value-%012" PRId64, (int64_t)row);
        if( length!=PAYLOAD_LENGTH ){
            sqlite3_finalize(statement);
            return report_error(db, "format payload", SQLITE_ERROR);
        }

        rc = sqlite3_bind_int64(statement, 1, row);
        if( rc==SQLITE_OK ) rc = sqlite3_bind_int64(statement, 2, row*7);
        if( rc==SQLITE_OK ) rc = sqlite3_bind_text(statement, 3, payload, length, SQLITE_TRANSIENT);
        if( rc==SQLITE_OK ) rc = sqlite3_step(statement);
        if( rc!=SQLITE_DONE ){
            sqlite3_finalize(statement);
            return report_error(db, "insert row", rc);
        }

        rc = sqlite3_reset(statement);
        if( rc!=SQLITE_OK ){
            sqlite3_finalize(statement);
            return report_error(db, "reset insert", rc);
        }
        rc = sqlite3_clear_bindings(statement);
        if( rc!=SQLITE_OK ){
            sqlite3_finalize(statement);
            return report_error(db, "clear insert bindings", rc);
        }
    }

    rc = sqlite3_finalize(statement);
    if( rc!=SQLITE_OK ) return report_error(db, "finalize insert", rc);
    rc = execute_sql(db, "COMMIT;");
    if( rc!=SQLITE_OK ) return report_error(db, "commit", rc);
    return 0;
}

static int verify_database(sqlite3 *db, sqlite3_int64 rows){
    sqlite3_stmt *statement = NULL;
    sqlite3_int64 actual_rows;
    sqlite3_int64 actual_sum;
    sqlite3_int64 actual_payload_bytes;
    sqlite3_int64 expected_sum = rows * (rows + 1) / 2 * 7;
    sqlite3_int64 expected_payload_bytes = rows * PAYLOAD_LENGTH;
    int rc;

    rc = sqlite3_prepare_v2(
        db,
        "SELECT count(*), sum(value), sum(length(payload)) FROM items",
        -1,
        &statement,
        NULL
    );
    if( rc!=SQLITE_OK ) return report_error(db, "prepare verification", rc);
    rc = sqlite3_step(statement);
    if( rc!=SQLITE_ROW ){
        sqlite3_finalize(statement);
        return report_error(db, "read verification", rc);
    }
    actual_rows = sqlite3_column_int64(statement, 0);
    actual_sum = sqlite3_column_int64(statement, 1);
    actual_payload_bytes = sqlite3_column_int64(statement, 2);
    rc = sqlite3_finalize(statement);
    if( rc!=SQLITE_OK ) return report_error(db, "finalize verification", rc);

    if( actual_rows!=rows || actual_sum!=expected_sum ||
        actual_payload_bytes!=expected_payload_bytes ){
        fprintf(stderr,
            "verification mismatch: rows=%" PRId64 "/%" PRId64
            " sum=%" PRId64 "/%" PRId64
            " payload-bytes=%" PRId64 "/%" PRId64 "\n",
            (int64_t)actual_rows, (int64_t)rows,
            (int64_t)actual_sum, (int64_t)expected_sum,
            (int64_t)actual_payload_bytes, (int64_t)expected_payload_bytes
        );
        return 1;
    }
    return 0;
}

static int parse_row_count(const char *text, sqlite3_int64 *rows){
    char *end = NULL;
    long long parsed;

    errno = 0;
    parsed = strtoll(text, &end, 10);
    if( errno!=0 || end==text || *end!='\0' || parsed<1 || parsed>DEMO_MAX_ROWS ){
        fprintf(stderr, "row count must be between 1 and %" PRId64 "\n", (int64_t)DEMO_MAX_ROWS);
        return 1;
    }
    *rows = (sqlite3_int64)parsed;
    return 0;
}

static double monotonic_seconds(void){
    struct timespec value;
    if( clock_gettime(CLOCK_MONOTONIC, &value)!=0 ) return -1.0;
    return (double)value.tv_sec + (double)value.tv_nsec / 1000000000.0;
}

static int run_benchmark(sqlite3_int64 rows){
    sqlite3 *db = NULL;
    struct rusage usage;
    double started;
    double finished;
    double elapsed;
    long peak_rss_kib = -1;
    sqlite3_int64 memory_used;
    sqlite3_int64 checksum = rows * (rows + 1) / 2 * 7;
    int rc;

    rc = sqlite3_open(":memory:", &db);
    if( rc!=SQLITE_OK ){
        int result = report_error(db, "open in-memory database", rc);
        if( db ) sqlite3_close(db);
        return result;
    }

    started = monotonic_seconds();
    if( started<0.0 ){
        sqlite3_close(db);
        fprintf(stderr, "clock_gettime(CLOCK_MONOTONIC) failed\n");
        return 1;
    }
    if( populate_database(db, rows)!=0 || verify_database(db, rows)!=0 ){
        sqlite3_close(db);
        return 1;
    }
    finished = monotonic_seconds();
    elapsed = finished - started;
    memory_used = sqlite3_memory_used();
    if( getrusage(RUSAGE_SELF, &usage)==0 ) peak_rss_kib = usage.ru_maxrss;

    printf(
        "BENCH engine=%s rows=%" PRId64 " elapsed_seconds=%.3f"
        " rows_per_second=%.0f sqlite_memory_used_bytes=%" PRId64
        " peak_rss_kib=%ld checksum=%" PRId64 "\n",
        sqlite3_libversion(), (int64_t)rows, elapsed,
        elapsed>0.0 ? (double)rows/elapsed : 0.0,
        (int64_t)memory_used, peak_rss_kib, (int64_t)checksum
    );

    rc = sqlite3_close(db);
    if( rc!=SQLITE_OK ) return report_error(db, "close in-memory database", rc);
    return 0;
}

static void print_usage(const char *program){
    fprintf(stderr,
        "usage:\n"
        "  %s seed DATABASE ROWS\n"
        "  %s check DATABASE ROWS\n"
        "  %s bench ROWS\n",
        program, program, program
    );
}

int main(int argc, char **argv){
    sqlite3_int64 rows;
    sqlite3 *db = NULL;
    int rc;
    int result;

    if( argc==3 && strcmp(argv[1], "bench")==0 ){
        if( parse_row_count(argv[2], &rows)!=0 ) return 2;
        return run_benchmark(rows);
    }
    if( argc!=4 || (strcmp(argv[1], "seed")!=0 && strcmp(argv[1], "check")!=0) ){
        print_usage(argv[0]);
        return 2;
    }
    if( parse_row_count(argv[3], &rows)!=0 ) return 2;

    rc = sqlite3_open(argv[2], &db);
    if( rc!=SQLITE_OK ){
        result = report_error(db, "open database", rc);
        if( db ) sqlite3_close(db);
        return result;
    }

    if( strcmp(argv[1], "seed")==0 ){
        result = populate_database(db, rows);
    }else{
        result = verify_database(db, rows);
    }
    if( result==0 ){
        printf("OK operation=%s engine=%s rows=%" PRId64 "\n",
            argv[1], sqlite3_libversion(), (int64_t)rows);
    }

    rc = sqlite3_close(db);
    if( rc!=SQLITE_OK ) return report_error(db, "close database", rc);
    return result;
}

/* end of demo.c */
