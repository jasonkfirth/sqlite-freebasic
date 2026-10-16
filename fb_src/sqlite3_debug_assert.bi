/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_debug_assert.bi

    Purpose:

        Declare the centralized debug assertion failure handler.

    Responsibilities:

        - Expose the debug-only assertion callback to engine modules.

    This file intentionally does NOT contain:

        - Release-build assertion policy or test-runner logic.
'/

#ifndef SQLITE3_FB_DEBUG_ASSERT_BI
#define SQLITE3_FB_DEBUG_ASSERT_BI

#ifdef SQLITE_DEBUG
Declare Sub sqlite3DebugAssert CDecl Alias "sqlite3DebugAssert" ( _
    ByVal zExpression As Const ZString Ptr _
)
#endif

#endif

/' end of sqlite3_debug_assert.bi '/
