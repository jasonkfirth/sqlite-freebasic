/'
    Project: SQLite FreeBASIC port

    File: sqlite3_date_types.bi

    Purpose:

        Define the date conversion state shared by SQLite date helpers.

    Responsibilities:

        - Store Julian day, calendar, clock, and timezone values.
        - Track which parts of the date are currently valid.
        - Preserve raw-number, error, UTC, local-time, and subsecond flags.

    This file intentionally does NOT contain:

        - Date parsing, calendar conversion, or SQL callback logic.
'/ 

#ifndef SQLITE3_FB_DATE_TYPES_BI
#define SQLITE3_FB_DATE_TYPES_BI

#include once "sqlite3_types.bi"
#include once "crt/time.bi"

' The source C bitfields are read and written as boolean state, so each flag
' gets a byte here instead of sharing a compiler-specific packed bitfield.
Type SqliteDateTime
    iJD As sqlite3_int64
    Y As SQLITE_C_INT
    month As SQLITE_C_INT
    D As SQLITE_C_INT
    h As SQLITE_C_INT
    minute As SQLITE_C_INT
    tz As SQLITE_C_INT
    s As Double
    validJD As Byte
    validYMD As Byte
    validHMS As Byte
    nFloor As Byte
    rawS As UByte
    isError As UByte
    useSubsec As UByte
    isUtc As UByte
    isLocal As UByte
End Type

Declare Function getDigits CDecl Alias "getDigits" ( _
    ByVal zDate As Const ZString Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) As SQLITE_C_INT
Declare Sub datetimeError CDecl Alias "datetimeError" (ByVal pDateTime As SqliteDateTime Ptr)
Declare Sub setRawDateNumber CDecl Alias "setRawDateNumber" ( _
    ByVal pDateTime As SqliteDateTime Ptr, _
    ByVal value As Double _
)
Declare Sub computeJD CDecl Alias "computeJD" (ByVal pDateTime As SqliteDateTime Ptr)
Declare Sub computeYMD CDecl Alias "computeYMD" (ByVal pDateTime As SqliteDateTime Ptr)
Declare Sub computeHMS CDecl Alias "computeHMS" (ByVal pDateTime As SqliteDateTime Ptr)
Declare Sub computeYMD_HMS CDecl Alias "computeYMD_HMS" (ByVal pDateTime As SqliteDateTime Ptr)
Declare Function parseTimezone CDecl Alias "parseTimezone" ( _
    ByVal zDate As Const ZString Ptr, _
    ByVal pDateTime As SqliteDateTime Ptr _
) As SQLITE_C_INT
Declare Function parseHhMmSs CDecl Alias "parseHhMmSs" ( _
    ByVal zDate As Const ZString Ptr, _
    ByVal pDateTime As SqliteDateTime Ptr _
) As SQLITE_C_INT
Declare Function parseYyyyMmDd CDecl Alias "parseYyyyMmDd" ( _
    ByVal zDate As Const ZString Ptr, _
    ByVal pDateTime As SqliteDateTime Ptr _
) As SQLITE_C_INT
Declare Function setDateTimeToCurrent CDecl Alias "setDateTimeToCurrent" ( _
    ByVal pContext As Any Ptr, _
    ByVal pDateTime As SqliteDateTime Ptr _
) As SQLITE_C_INT
Declare Function osLocaltime CDecl Alias "osLocaltime" ( _
    ByVal pTime As time_t Ptr, _
    ByVal pTm As tm Ptr _
) As SQLITE_C_INT
Declare Function toLocaltime CDecl Alias "toLocaltime" ( _
    ByVal pDateTime As SqliteDateTime Ptr, _
    ByVal pContext As Any Ptr _
) As SQLITE_C_INT
Declare Function parseDateOrTime CDecl Alias "parseDateOrTime" ( _
    ByVal pContext As Any Ptr, _
    ByVal zDate As Const ZString Ptr, _
    ByVal pDateTime As SqliteDateTime Ptr _
) As SQLITE_C_INT
Declare Function parseModifier CDecl Alias "parseModifier" ( _
    ByVal pContext As Any Ptr, _
    ByVal zModifier As Const ZString Ptr, _
    ByVal modifierLength As SQLITE_C_INT, _
    ByVal pDateTime As SqliteDateTime Ptr, _
    ByVal modifierIndex As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Sub autoAdjustDate CDecl Alias "autoAdjustDate" (ByVal pDateTime As SqliteDateTime Ptr)
Declare Function validJulianDay CDecl Alias "validJulianDay" ( _
    ByVal iJD As sqlite3_int64 _
) As SQLITE_C_INT
Declare Sub computeFloor CDecl Alias "computeFloor" (ByVal pDateTime As SqliteDateTime Ptr)
Declare Sub clearYMD_HMS_TZ CDecl Alias "clearYMD_HMS_TZ" (ByVal pDateTime As SqliteDateTime Ptr)
Declare Function daysAfterJan01 CDecl Alias "daysAfterJan01" (ByVal pDateTime As SqliteDateTime Ptr) As SQLITE_C_INT
Declare Function daysAfterMonday CDecl Alias "daysAfterMonday" (ByVal pDateTime As SqliteDateTime Ptr) As SQLITE_C_INT
Declare Function daysAfterSunday CDecl Alias "daysAfterSunday" (ByVal pDateTime As SqliteDateTime Ptr) As SQLITE_C_INT

#endif

/' end of sqlite3_date_types.bi '/
