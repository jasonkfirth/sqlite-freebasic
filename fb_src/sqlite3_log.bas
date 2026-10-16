/'
    Project: SQLite FreeBASIC port

    File: sqlite3_log.bas

    Purpose:

        Format and deliver SQLite log messages through SQLITE_CONFIG_LOG.

    Responsibilities:

        - Avoid dynamic allocation while formatting a log message.
        - Truncate messages to SQLite's fixed log buffer limit.
        - Invoke the currently configured callback when logging is enabled.

    This file intentionally does NOT contain:

        - Log callback registration, which is part of sqlite3_config().
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_straccum.bi"

Declare Sub sqlite3ConfigGetLog CDecl Alias "sqlite3ConfigGetLog" ( _
    ByVal pCallback As Any Ptr Ptr, _
    ByVal pArgument As Any Ptr Ptr _
)
Declare Sub sqlite3_str_vappendf CDecl Alias "sqlite3_str_vappendf" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ByRef sourceArgs As Cva_List _
)

Private Const SQLITE_LOG_MESSAGE_LIMIT As SQLITE_C_INT = 10000

Private Type SqliteLogCallback As Sub CDecl ( _
    ByVal pArgument As Any Ptr, _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal zMessage As Const ZString Ptr _
)

Private Sub renderLogMsg CDecl Alias "renderLogMsg" ( _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal zFormat As Const ZString Ptr, _
    ByRef sourceArgs As Cva_List, _
    ByVal pCallback As Any Ptr, _
    ByVal pArgument As Any Ptr _
)
    ' Logging can occur while the allocator mutex is held, so use caller-owned
    ' stack storage for both the final message and printf's temporary fields.
    Dim messageBuffer(0 To SQLITE_LOG_MESSAGE_LIMIT - 1) As UByte
    Dim fieldBuffer(0 To SQLITE_LOG_MESSAGE_LIMIT - 1) As UByte
    Dim accumulation As sqlite3_str
    sqlite3StrAccumInit(@accumulation, 0, @messageBuffer(0), _
                        SQLITE_LOG_MESSAGE_LIMIT, 0)
    accumulation.pPrintfScratch = @fieldBuffer(0)
    accumulation.nPrintfScratch = SQLITE_LOG_MESSAGE_LIMIT
    sqlite3_str_vappendf(@accumulation, zFormat, sourceArgs)

    Dim zMessage As ZString Ptr = sqlite3StrAccumFinish(@accumulation)
    If zMessage = 0 OrElse pCallback = 0 Then Return
    Dim callback As SqliteLogCallback = CPtr(SqliteLogCallback, pCallback)
    callback(pArgument, errorCode, zMessage)
End Sub

Sub sqlite3_log CDecl Alias "sqlite3_log" ( _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) Export
    If zFormat = 0 Then Return

    Dim pCallback As Any Ptr = 0
    Dim pArgument As Any Ptr = 0
    sqlite3ConfigGetLog(@pCallback, @pArgument)
    If pCallback = 0 Then Return

    Dim args As Cva_List
    Cva_Start(args, zFormat)
    renderLogMsg(errorCode, zFormat, args, pCallback, pArgument)
    Cva_End(args)
End Sub

/' end of sqlite3_log.bas '/
