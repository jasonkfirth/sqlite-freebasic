/'
    Project: SQLite FreeBASIC port

    File: sqlite3_window.bas

    Purpose:

        Normalize window-frame offset expressions during parsing.

    Responsibilities:

        - Keep constant offsets for later validation.
        - Replace non-constant offsets with NULL after rename unmapping.

    This file intentionally does NOT contain:

        - Window definitions, frame planning, or window-function execution.
'/ 

#lang "fb"
#include once "sqlite3_expr_types.bi"

Declare Sub sqlite3RenameExprUnmap CDecl Alias "sqlite3RenameExprUnmap" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
)

Private Sub noopValueFunc CDecl Alias "noopValueFunc" (ByVal pContext As Any Ptr)
    ' Some built-in window functions implement their result directly in VDBE code.
End Sub

Private Function sqlite3WindowOffsetExpr CDecl Alias "sqlite3WindowOffsetExpr" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExprArgument As SqliteExpr Ptr _
) As SqliteExpr Ptr
    If pParse = 0 OrElse pParse->db = 0 Then Return pExprArgument
    Dim pExpr As SqliteExpr Ptr = pExprArgument
    If pExpr = 0 Then Return 0
    If sqlite3ExprIsConstant(0, pExpr) = 0 Then
        If pParse->eParseMode >= PARSE_MODE_RENAME Then
            sqlite3RenameExprUnmap(pParse, pExpr)
        End If
        sqlite3ExprDelete(pParse->db, pExpr)
        pExpr = CPtr(SqliteExpr Ptr, sqlite3ExprAlloc(pParse->db, TK_NULL, 0, 0))
    End If
    Return pExpr
End Function

/' end of sqlite3_window.bas '/
