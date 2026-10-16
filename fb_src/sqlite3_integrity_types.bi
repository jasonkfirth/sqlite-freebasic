/'
    Project: SQLite FreeBASIC port
    File: sqlite3_integrity_types.bi

    Purpose:

        Define the private state passed through B-tree integrity checking.

    Responsibilities:

        - Track page references, errors, progress, and row counts.
        - Retain the page, database, and error-accumulation state.
        - Keep the formatter scratch fields required by the port's sqlite3_str.

    This file intentionally does NOT contain:

        - A public C ABI record or storage shared with C callers.
        - Integrity-check traversal or error-formatting behavior.
'/ 

#ifndef SQLITE3_FB_INTEGRITY_TYPES_BI
#define SQLITE3_FB_INTEGRITY_TYPES_BI

#include once "sqlite3_btree.bi"
#include once "sqlite3_straccum.bi"

' IntegrityCk is stack-local to B-tree integrity checking. Its embedded
' accumulator uses the port's extended sqlite3_str storage, so code that clears
' this context uses SizeOf(SqliteIntegrityCk), not a C sizeof result.
Type SqliteIntegrityCk
    pBt As BtShared Ptr
    pPager As Pager Ptr
    aPgRef As UByte Ptr
    nCkPage As u32
    mxErr As SQLITE_C_INT
    nErr As SQLITE_C_INT
    rc As SQLITE_C_INT
    nStep As u32
    nAbove As u8
    zPfx As Const ZString Ptr
    v0 As u32
    v1 As u32
    v2 As SQLITE_C_INT
    errMsg As sqlite3_str
    heap As u32 Ptr
    db As sqlite3 Ptr
    nRow As sqlite3_int64
#ifdef SQLITE_DEBUG
    mxHeap As u32
#endif
End Type

Declare Sub checkProgress CDecl Alias "checkProgress" ( _
    ByVal pCheck As SqliteIntegrityCk Ptr _
)
Declare Sub checkOom CDecl Alias "checkOom" ( _
    ByVal pCheck As SqliteIntegrityCk Ptr _
)
Declare Sub setPageReferenced CDecl Alias "setPageReferenced" ( _
    ByVal pCheck As SqliteIntegrityCk Ptr, _
    ByVal pageNumber As u32 _
)
Declare Sub checkAppendMsg CDecl Alias "checkAppendMsg" (ByVal pCheck As SqliteIntegrityCk Ptr, ByVal zFormat As Const ZString Ptr, ...)

#endif

/' end of sqlite3_integrity_types.bi '/
