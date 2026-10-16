/'
    Project: SQLite FreeBASIC port

    File: sqlite3_pragma_helpers.bas

    Purpose:

        Attach the result-column names associated with one PRAGMA.

    Responsibilities:

        - Select the default PRAGMA name when no column list is defined.
        - Read explicit column labels from generated stable storage.

    This file intentionally does NOT contain:

        - PRAGMA dispatch or virtual-table callback behavior.
'/

#lang "fb"
#include once "sqlite3_constants.bi"
#include once "sqlite3_pragma_helpers.bi"

Sub setPragmaResultColumnNames CDecl Alias "setPragmaResultColumnNames" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pPragma As Const SqlitePragmaName Ptr _
)
    If pVdbe = 0 OrElse pPragma = 0 Then Exit Sub

    Dim columnCount As UByte = pPragma->nPragCName
    If columnCount = 0 Then
        sqlite3VdbeSetNumCols(pVdbe, 1)
        sqlite3VdbeSetColName(pVdbe, 0, COLNAME_NAME, pPragma->zName, 0)
        Exit Sub
    End If

    Dim firstColumn As UByte = pPragma->iPragCName
    If CLng(firstColumn) + CLng(columnCount) > SQLITE3_PRAGMA_COLUMN_NAME_COUNT Then Exit Sub
    Dim columnNames As Const ZString Ptr Ptr = sqlite3PragmaColumnNameTable()
    If columnNames = 0 Then Exit Sub

    sqlite3VdbeSetNumCols(pVdbe, columnCount)
    For columnIndex As Long = 0 To CLng(columnCount) - 1
        sqlite3VdbeSetColName(pVdbe, columnIndex, COLNAME_NAME, _
            columnNames[CLng(firstColumn) + columnIndex], 0)
    Next
End Sub

Sub sqlite3PragmaFunctionListUserLine CDecl Alias "sqlite3PragmaFunctionListUserLine" ( _
    ByVal pVdbe As SqliteVdbe Ptr, _
    ByVal pFunction As Const SqliteFuncDef Ptr, _
    ByVal showInternFuncs As SQLITE_C_INT _
)
    If pVdbe = 0 OrElse pFunction = 0 OrElse pFunction->xSFunc = 0 Then Exit Sub

    If (pFunction->funcFlags And SQLITE_FUNC_INTERNAL) <> 0 AndAlso _
       showInternFuncs = 0 Then Exit Sub

    Dim typeName As Const ZString Ptr
    If pFunction->xValue <> 0 Then
        typeName = StrPtr(!"w")
    ElseIf pFunction->xFinalize <> 0 Then
        typeName = StrPtr(!"a")
    Else
        typeName = StrPtr(!"s")
    End If

    Dim encodingName As Const ZString Ptr
    Select Case pFunction->funcFlags And SQLITE_FUNC_ENCODING_MASK
    Case SQLITE_UTF8
        encodingName = StrPtr(!"utf8")
    Case SQLITE_UTF16LE
        encodingName = StrPtr(!"utf16le")
    Case SQLITE_UTF16BE
        encodingName = StrPtr(!"utf16be")
    Case Else
        encodingName = 0
    End Select

    Dim flagMask As u32 = SQLITE_DETERMINISTIC Or SQLITE_DIRECTONLY Or _
        SQLITE_SUBTYPE Or SQLITE_INNOCUOUS Or SQLITE_FUNC_INTERNAL
    If showInternFuncs <> 0 Then flagMask = &HFFFFFFFF
    Dim visibleFlags As u32 = (pFunction->funcFlags And flagMask) Xor SQLITE_INNOCUOUS

    sqlite3VdbeMultiLoad(pVdbe, 1, StrPtr(!"sissii"), pFunction->zName, _
        Cast(SQLITE_C_INT, 0), typeName, encodingName, _
        Cast(SQLITE_C_INT, pFunction->nArg), Cast(SQLITE_C_INT, visibleFlags))
End Sub

/' end of sqlite3_pragma_helpers.bas '/
