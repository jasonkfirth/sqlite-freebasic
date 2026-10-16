# -----------------------------------------------------------------------------
# Project: SQLite FreeBASIC port
# File: run_one.tcl
# Purpose: Load the Tcl test bridge and source one unchanged upstream test.
# This file intentionally does NOT contain test cases or engine code.
# -----------------------------------------------------------------------------

load $::env(FB_TCL_BRIDGE) Fbtclbridge
set ::argv0 $::env(FB_TEST_FILE)
set ::argv {}
source $::argv0

# end of run_one.tcl
