/'
    Project: SQLite FreeBASIC port

    File: sqlite3_pragma_helpers.bi

    Purpose:

        Declare local helpers shared by PRAGMA code-generation modules.

    Responsibilities:

        - Expose result-column setup for generated PRAGMA statements.
        - Expose one-row formatting for user-defined functions.

    This file intentionally does NOT contain:

        - PRAGMA dispatch or virtual-table callback behavior.
'/

#ifndef SQLITE3_FB_PRAGMA_HELPERS_BI
#define SQLITE3_FB_PRAGMA_HELPERS_BI

#include once "sqlite3_pragma_types.bi"
#include once "sqlite3_vdbe_core.bi"

Declare Sub setPragmaResultColumnNames CDecl Alias "setPragmaResultColumnNames" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pPragma As Const SqlitePragmaName Ptr _
)

Declare Sub sqlite3PragmaFunctionListUserLine CDecl Alias "sqlite3PragmaFunctionListUserLine" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pFunction As Const SqliteFuncDef Ptr, _
    ByVal showInternFuncs As SQLITE_C_INT _
)

#endif

/' end of sqlite3_pragma_helpers.bi '/
