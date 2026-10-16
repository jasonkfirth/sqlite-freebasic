/*
    Project: SQLite FreeBASIC port
    ------------------------------

    File: tcl_bridge.c

    Purpose:

        Expose the pending-byte test control to the Tcl runner.

    Responsibilities:

        - Validate the Tcl argument as a signed 64-bit integer.
        - Forward it through sqlite3_test_control().
        - Return SQLite's previous pending-byte setting to the caller.

    This file intentionally does NOT contain:

        - SQLite implementation code.
        - Test cases or test-runner policy.
*/
#include <tcl.h>
#include "sqlite3.h"

static int pendingByteCommand(
    ClientData clientData,
    Tcl_Interp *interp,
    int argumentCount,
    Tcl_Obj *const arguments[]
){
    Tcl_WideInt pendingByte;
    int previous;

    (void)clientData;
    if( argumentCount!=2 ){
        Tcl_WrongNumArgs(interp, 1, arguments, "pending-byte");
        return TCL_ERROR;
    }
    if( Tcl_GetWideIntFromObj(interp, arguments[1], &pendingByte)!=TCL_OK ){
        return TCL_ERROR;
    }
    previous = sqlite3_test_control(
        SQLITE_TESTCTRL_PENDING_BYTE,
        (sqlite3_int64)pendingByte
    );
    Tcl_SetObjResult(interp, Tcl_NewIntObj(previous));
    return TCL_OK;
}

int Fbtclbridge_Init(Tcl_Interp *interp){
    if( Tcl_PkgRequire(interp, "Tcl", "8.6", 0)==NULL ){
        return TCL_ERROR;
    }
    Tcl_CreateObjCommand(
        interp,
        "sqlite3_test_control_pending_byte",
        pendingByteCommand,
        NULL,
        NULL
    );
    return Tcl_PkgProvide(interp, "fbsqlite3testbridge", "1.0");
}

/* end of tcl_bridge.c */
