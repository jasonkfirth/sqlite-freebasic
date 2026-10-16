/'
    Project: SQLite FreeBASIC port

    File: sqlite3_window_names.bas

    Purpose:

        Own stable names for built-in window functions that SQLite compares by
        pointer identity during registration and VDBE code generation.

    Responsibilities:

        - Return one process-lifetime string address for each built-in name.
        - Keep registration and C2FB-translated comparisons on the same bytes.

    This file intentionally does NOT contain:

        - Window function registration or callback implementations.
        - Window frame planning or VDBE instruction generation.
'/
#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_window_state.bi"

Private Function sqlite3WindowNameRowNumber() As Const ZString Ptr
    Static zName As ZString * 11 = "row_number"
    Return StrPtr(zName)
End Function

Private Function sqlite3WindowNameDenseRank() As Const ZString Ptr
    Static zName As ZString * 11 = "dense_rank"
    Return StrPtr(zName)
End Function

Private Function sqlite3WindowNameRank() As Const ZString Ptr
    Static zName As ZString * 5 = "rank"
    Return StrPtr(zName)
End Function

Private Function sqlite3WindowNamePercentRank() As Const ZString Ptr
    Static zName As ZString * 13 = "percent_rank"
    Return StrPtr(zName)
End Function

Private Function sqlite3WindowNameCumeDist() As Const ZString Ptr
    Static zName As ZString * 10 = "cume_dist"
    Return StrPtr(zName)
End Function

Private Function sqlite3WindowNameNtile() As Const ZString Ptr
    Static zName As ZString * 6 = "ntile"
    Return StrPtr(zName)
End Function

Private Function sqlite3WindowNameLastValue() As Const ZString Ptr
    Static zName As ZString * 11 = "last_value"
    Return StrPtr(zName)
End Function

Private Function sqlite3WindowNameNthValue() As Const ZString Ptr
    Static zName As ZString * 10 = "nth_value"
    Return StrPtr(zName)
End Function

Private Function sqlite3WindowNameFirstValue() As Const ZString Ptr
    Static zName As ZString * 12 = "first_value"
    Return StrPtr(zName)
End Function

Private Function sqlite3WindowNameLead() As Const ZString Ptr
    Static zName As ZString * 5 = "lead"
    Return StrPtr(zName)
End Function

Private Function sqlite3WindowNameLag() As Const ZString Ptr
    Static zName As ZString * 4 = "lag"
    Return StrPtr(zName)
End Function

Function sqlite3WindowFunctionName CDecl Alias "sqlite3WindowFunctionName" ( _
    ByVal nameId As SQLITE_C_INT _
) As Const ZString Ptr
    Select Case nameId
    Case SQLITE_WINDOW_NAME_ROW_NUMBER: Return sqlite3WindowNameRowNumber()
    Case SQLITE_WINDOW_NAME_DENSE_RANK: Return sqlite3WindowNameDenseRank()
    Case SQLITE_WINDOW_NAME_RANK: Return sqlite3WindowNameRank()
    Case SQLITE_WINDOW_NAME_PERCENT_RANK: Return sqlite3WindowNamePercentRank()
    Case SQLITE_WINDOW_NAME_CUME_DIST: Return sqlite3WindowNameCumeDist()
    Case SQLITE_WINDOW_NAME_NTILE: Return sqlite3WindowNameNtile()
    Case SQLITE_WINDOW_NAME_LAST_VALUE: Return sqlite3WindowNameLastValue()
    Case SQLITE_WINDOW_NAME_NTH_VALUE: Return sqlite3WindowNameNthValue()
    Case SQLITE_WINDOW_NAME_FIRST_VALUE: Return sqlite3WindowNameFirstValue()
    Case SQLITE_WINDOW_NAME_LEAD: Return sqlite3WindowNameLead()
    Case SQLITE_WINDOW_NAME_LAG: Return sqlite3WindowNameLag()
    End Select
    Return 0
End Function

/' end of sqlite3_window_names.bas '/
