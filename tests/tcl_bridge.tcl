# -----------------------------------------------------------------------------
# Project: SQLite FreeBASIC port
# File: tcl_bridge.tcl
# Purpose: Provide the small Tcl test surface used by the selected unchanged
#          SQLite upstream tests.
# Responsibilities: SQL helpers, feature checks, test accounting, and loading
#                   upstream test extensions from the qualification runner.
# This file intentionally does NOT contain the SQLite engine or test cases.
# -----------------------------------------------------------------------------

set ::fb_test_count 0
set ::fb_pass_count 0
set ::fb_fail_count 0
set ::fb_skip_count 0
set ::fb_features [dict create json 1 jsonb 1 vtab 1 windowfunc 1 fts3 0 fts5 0 rtree 0]

sqlite3 db test.db

proc fix_testname {nameVar} {
    upvar 1 $nameVar testName
    if {[info exists ::testprefix] && $::testprefix ne "" &&
        ![string match "${::testprefix}-*" $testName]} {
        set testName "${::testprefix}-$testName"
    }
}

proc fb_expected_matches {actual expected} {
    if {[regexp {^[~#]?/.*/$} $expected]} {
        set mode [string index $expected 0]
        set pattern [string range $expected 1 end-1]
        if {$mode eq "~"} {
            return [expr {![regexp $pattern $actual]}]
        }
        if {$mode eq "#"} {
            set expectedValues [split $pattern]
            set actualValues [split $actual]
            if {[llength $expectedValues] != [llength $actualValues]} {
                return 0
            }
            foreach got $actualValues wanted $expectedValues {
                if {![string is double -strict $got] ||
                    ![string is double -strict $wanted]} {
                    return 0
                }
                if {$got < 0.9*$wanted || $got > 1.1*$wanted} {
                    return 0
                }
            }
            return 1
        }
        return [regexp $pattern $actual]
    }
    if {[regexp {^~?\*.*\*$} $expected]} {
        if {[string index $expected 0] eq "~"} {
            return [expr {![string match [string range $expected 1 end] $actual]}]
        }
        return [string match $expected $actual]
    }
    return [string equal $actual $expected]
}

proc do_test {testName script expected} {
    fix_testname testName
    incr ::fb_test_count
    set code [catch {uplevel #0 $script} actual options]
    if {$code != 0} {
        incr ::fb_fail_count
        puts stderr "FAIL $testName: $actual"
        return $actual
    }
    if {![fb_expected_matches $actual $expected]} {
        incr ::fb_fail_count
        puts stderr "FAIL $testName"
        puts stderr "  expected: <$expected>"
        puts stderr "  actual:   <$actual>"
        return $actual
    }
    incr ::fb_pass_count
    return $actual
}

proc execsql {sql {database db}} {
    return [uplevel 1 [list $database eval $sql]]
}

proc catchsql {sql {database db}} {
    set code [catch {uplevel 1 [list $database eval $sql]} message]
    return [list $code $message]
}

proc do_execsql_test {args} {
    set database db
    if {[lindex $args 0] eq "-db"} {
        set database [lindex $args 1]
        set args [lrange $args 2 end]
    }
    if {[llength $args] == 2} {
        lassign $args testName sql
        set expected ""
    } elseif {[llength $args] == 3} {
        lassign $args testName sql expected
    } else {
        error "wrong # args: should be \"do_execsql_test ?-db DB? name sql ?result?\""
    }
    set expected [list {*}$expected]
    return [uplevel #0 [list do_test $testName [list execsql $sql $database] $expected]]
}

proc do_catchsql_test {testName sql expected} {
    set expected [list {*}$expected]
    return [uplevel #0 [list do_test $testName [list catchsql $sql] $expected]]
}

proc feature_expression {expression} {
    set translated $expression
    foreach token [lsort -unique [regexp -all -inline {!?[A-Za-z_][A-Za-z_0-9]*} $expression]] {
        set negated [string match "!*" $token]
        set feature [string trimleft $token "!"]
        set enabled [expr {[dict exists $::fb_features $feature] && [dict get $::fb_features $feature]}]
        set replacement [expr {$enabled ? 1 : 0}]
        if {$negated} {
            set replacement "!$replacement"
        }
        set translated [string map [list $token $replacement] $translated]
    }
    return [expr $translated]
}

proc capable {expression} {
    return [feature_expression $expression]
}

proc ifcapable {expression body {else ""} {elseBody ""}} {
    if {[feature_expression $expression]} {
        return [uplevel 1 $body]
    }
    if {[regexp {do_(test|execsql_test|catchsql_test)} $body]} {
        incr ::fb_skip_count
    }
    return [uplevel 1 $elseBody]
}

proc reset_db {} {
    catch {db close}
    foreach filename [glob -nocomplain test.db*] {
        file delete -force $filename
    }
    sqlite3 db ./test.db
}

proc load_static_extension {database name} {
    if {![info exists ::env(FB_TEST_EXTENSION_DIR)]} {
        error "FB_TEST_EXTENSION_DIR is not set"
    }
    switch -- $name {
        randomjson { set entrypoint sqlite3_randomjson_init }
        strdup     { set entrypoint sqlite3_strdup_init }
        default    { error "unsupported test extension: $name" }
    }
    set path [file join $::env(FB_TEST_EXTENSION_DIR) "$name.so"]
    $database enable_load_extension 1
    set escapedPath [string map [list ' ''] $path]
    set escapedEntrypoint [string map [list ' ''] $entrypoint]
    $database eval "SELECT load_extension('$escapedPath', '$escapedEntrypoint')"
}

proc finish_test {} {
    catch {db close}
    puts "RESULT suite=$::env(FB_TEST_SUITE) tests=$::fb_test_count passed=$::fb_pass_count failed=$::fb_fail_count skipped_blocks=$::fb_skip_count"
    if {$::fb_fail_count != 0} {
        exit 1
    }
    exit 0
}

# end of tcl_bridge.tcl
