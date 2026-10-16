/'
    Project: SQLite FreeBASIC port

    File: sqlite3_date_helpers.bas

    Purpose:

        Hold shared DateTime arithmetic and parsing primitives.

    Responsibilities:

        - Check an internal Julian-day millisecond value against SQLite's
          supported date range.
        - Parse fixed-width date components and store them through C varargs.
        - Convert between Julian days, calendar dates, and clock fields.
        - Parse timezone, clock, and calendar components using SQLite's limits.
        - Reset invalid date state and normalize raw numeric input.
        - Convert UTC values through the host C runtime's local-time routines.
        - Honor the alternate local-time callback installed by sqlite3_test_control().

    This file intentionally does NOT contain:

        - Date modifiers, formatting, or SQL date-function callbacks.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_date_types.bi"
#include once "sqlite3_global_data.bi"
#include once "sqlite3_fp.bi"
#include once "sqlite3_result.bi"

Declare Function sqlite3StrICmp CDecl Alias "sqlite3StrICmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3StmtCurrentTime CDecl Alias "sqlite3StmtCurrentTime" ( _
    ByVal pContext As Any Ptr _
) As sqlite3_int64
Declare Function sqlite3NotPureFunc CDecl Alias "sqlite3NotPureFunc" ( _
    ByVal pContext As SqliteResultContext Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3_result_error CDecl Alias "sqlite3_result_error" ( _
    ByVal pContext As Any Ptr, _
    ByVal zError As Const ZString Ptr, _
    ByVal nError As SQLITE_C_INT _
)
Declare Function sqlite3ConfigTestLocaltimeFault CDecl Alias "sqlite3ConfigTestLocaltimeFault" () As SQLITE_C_INT
Declare Function sqlite3ConfigTestAltLocaltime CDecl Alias "sqlite3ConfigTestAltLocaltime" () As Any Ptr

Type SqliteAlternateLocaltimeProc As Function CDecl ( _
    ByVal pTime As Any Ptr, _
    ByVal pTm As Any Ptr _
) As SQLITE_C_INT

Private Function dateIsSpace(ByVal character As UByte) As SQLITE_C_INT
    Return CInt((sqlite3CtypeMap(character) And &H01) <> 0)
End Function

Private Function dateIsDigit(ByVal character As UByte) As SQLITE_C_INT
    Return CInt((sqlite3CtypeMap(character) And &H04) <> 0)
End Function

Function osLocaltime CDecl Alias "osLocaltime" ( _
    ByVal pTime As time_t Ptr, _
    ByVal pTm As tm Ptr _
) As SQLITE_C_INT
    If CPtr(Any Ptr, pTime) = 0 OrElse CPtr(Any Ptr, pTm) = 0 Then Return 1

    If sqlite3ConfigTestLocaltimeFault() <> 0 Then
        Dim pAlternate As Any Ptr = sqlite3ConfigTestAltLocaltime()
        If pAlternate = 0 Then Return 1
        Dim alternateLocaltime As SqliteAlternateLocaltimeProc = _
            CPtr(SqliteAlternateLocaltimeProc, pAlternate)
        Return alternateLocaltime(CPtr(Any Ptr, pTime), CPtr(Any Ptr, pTm))
    End If

#if defined(__FB_WIN32__) OrElse defined(__FB_DOS__) OrElse _
    defined(__FB_AMIGA__) OrElse defined(__FB_NUTTX__)
    ' These CRTs do not expose localtime_r through the FreeBASIC time header.
    ' SQLite's static main mutex protects the CRT's shared tm result.
    Dim mutex As Any Ptr = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MAIN)
    If mutex <> 0 Then sqlite3_mutex_enter(mutex)
    Dim pLocalTime As tm Ptr = localtime(pTime)
    If pLocalTime <> 0 Then *pTm = *pLocalTime
    If mutex <> 0 Then sqlite3_mutex_leave(mutex)
    Return CInt(pLocalTime = 0)
#else
    Return CInt(localtime_r(pTime, pTm) = 0)
#endif
End Function

Function getDigits CDecl Alias "getDigits" ( _
    ByVal zDateArgument As Const ZString Ptr, _
    ByVal zFormatArgument As Const ZString Ptr, _
    ... _
) As SQLITE_C_INT
    If zDateArgument = 0 OrElse zFormatArgument = 0 Then Return 0

    Dim zDate As Const UByte Ptr = CPtr(Const UByte Ptr, zDateArgument)
    Dim zFormat As Const UByte Ptr = CPtr(Const UByte Ptr, zFormatArgument)
    Dim arguments As cva_list = Any
    cva_start(arguments, zFormatArgument)

    Dim convertedCount As SQLITE_C_INT = 0
    Dim formatOffset As Long = 0
    Do
        Dim digitCountByte As UByte = zFormat[formatOffset]
        If digitCountByte = 0 Then Exit Do
        If zFormat[formatOffset + 1] = 0 OrElse _
           zFormat[formatOffset + 2] = 0 Then
            Exit Do
        End If

        Dim digitCount As Long = CLng(digitCountByte) - Asc("0")
        Dim minimumByte As UByte = zFormat[formatOffset + 1]
        Dim minimumValue As Long = CLng(minimumByte) - Asc("0")
        If digitCount < 0 OrElse digitCount > 9 OrElse _
           minimumValue < 0 OrElse minimumValue > 9 Then
            Exit Do
        End If

        Dim maximumValue As Long
        Select Case zFormat[formatOffset + 2]
        Case Asc("a")
            maximumValue = 12
        Case Asc("b")
            maximumValue = 14
        Case Asc("c")
            maximumValue = 24
        Case Asc("d")
            maximumValue = 31
        Case Asc("e")
            maximumValue = 59
        Case Asc("f")
            maximumValue = 14712
        Case Else
            Exit Do
        End Select

        Dim separatorByte As UByte = zFormat[formatOffset + 3]
        Dim value As Long = 0
        Dim digitIndex As Long = 0
        While digitIndex < digitCount
            Dim digitByte As UByte = zDate[digitIndex]
            If digitByte < Asc("0") OrElse digitByte > Asc("9") Then Exit While
            value = value * 10 + digitByte - Asc("0")
            digitIndex += 1
        Wend
        If digitIndex < digitCount Then Exit Do
        If value < minimumValue OrElse value > maximumValue Then Exit Do
        If separatorByte <> 0 AndAlso zDate[digitCount] <> separatorByte Then Exit Do

        Dim outputValue As SQLITE_C_INT Ptr = _
            cva_arg(arguments, SQLITE_C_INT Ptr)
        If outputValue = 0 Then Exit Do
        *outputValue = value
        zDate += digitCount + 1
        formatOffset += 4
        convertedCount += 1
        If separatorByte = 0 Then Exit Do
    Loop

    cva_end(arguments)
    Return convertedCount
End Function

Function validJulianDay CDecl Alias "validJulianDay" ( _
    ByVal iJD As sqlite3_int64 _
) As SQLITE_C_INT
    Return IIf(iJD >= 0 AndAlso _
               iJD <= (((Cast(sqlite3_int64, &H1A640)) Shl 32) Or &H1072FDFF), _
               1, 0)
End Function

Sub datetimeError CDecl Alias "datetimeError" ( _
    ByVal pDateTime As SqliteDateTime Ptr _
)
    If pDateTime = 0 Then Return

    pDateTime->iJD = 0
    pDateTime->Y = 0
    pDateTime->month = 0
    pDateTime->D = 0
    pDateTime->h = 0
    pDateTime->minute = 0
    pDateTime->tz = 0
    pDateTime->s = 0.0
    pDateTime->validJD = 0
    pDateTime->validYMD = 0
    pDateTime->validHMS = 0
    pDateTime->nFloor = 0
    pDateTime->rawS = 0
    pDateTime->useSubsec = 0
    pDateTime->isUtc = 0
    pDateTime->isLocal = 0
    pDateTime->isError = 1
End Sub

Sub setRawDateNumber CDecl Alias "setRawDateNumber" ( _
    ByVal pDateTime As SqliteDateTime Ptr, _
    ByVal value As Double _
)
    If pDateTime = 0 Then Return

    pDateTime->s = value
    pDateTime->rawS = 1
    If value >= 0.0 AndAlso value < 5373484.5 Then
        pDateTime->iJD = Cast(sqlite3_int64, Fix(value * 86400000.0 + 0.5))
        pDateTime->validJD = 1
    End If
End Sub

Sub computeJD CDecl Alias "computeJD" (ByVal pDateTime As SqliteDateTime Ptr)
    If pDateTime = 0 OrElse pDateTime->validJD <> 0 Then Return

    Dim yearValue As SQLITE_C_INT
    Dim monthValue As SQLITE_C_INT
    Dim dayValue As SQLITE_C_INT
    If pDateTime->validYMD <> 0 Then
        yearValue = pDateTime->Y
        monthValue = pDateTime->month
        dayValue = pDateTime->D
    Else
        yearValue = 2000
        monthValue = 1
        dayValue = 1
        If pDateTime->validHMS <> 0 AndAlso pDateTime->h = 24 Then
            pDateTime->h = 0
            dayValue = 2
        End If
    End If

    If yearValue < -4713 OrElse yearValue > 9999 OrElse pDateTime->rawS <> 0 Then
        datetimeError(pDateTime)
        Return
    End If

    If monthValue <= 2 Then
        yearValue -= 1
        monthValue += 12
    End If

    Dim century As SQLITE_C_INT = (yearValue + 4800) \ 100
    Dim correction As SQLITE_C_INT = 38 - century + (century \ 4)
    Dim yearDays As SQLITE_C_INT = (36525 * (yearValue + 4716)) \ 100
    Dim monthDays As SQLITE_C_INT = (306001 * (monthValue + 1)) \ 10000
    Dim julianDays As Double = CDbl(yearDays) + CDbl(monthDays) + _
                               CDbl(dayValue) + CDbl(correction) - 1524.5
    pDateTime->iJD = Cast(sqlite3_int64, Fix(julianDays * 86400000.0))
    pDateTime->validJD = 1

    If pDateTime->validHMS <> 0 Then
        pDateTime->iJD += pDateTime->h * 3600000 + _
                          pDateTime->minute * 60000 + _
                          Cast(sqlite3_int64, Fix(pDateTime->s * 1000.0 + 0.5))
        If pDateTime->tz <> 0 Then
            pDateTime->iJD -= pDateTime->tz * 60000
            pDateTime->validYMD = 0
            pDateTime->validHMS = 0
            pDateTime->tz = 0
            pDateTime->isUtc = 1
            pDateTime->isLocal = 0
        End If
    End If
End Sub

Sub computeYMD CDecl Alias "computeYMD" (ByVal pDateTime As SqliteDateTime Ptr)
    If pDateTime = 0 OrElse pDateTime->validYMD <> 0 Then Return
    If pDateTime->validJD = 0 Then
        pDateTime->Y = 2000
        pDateTime->month = 1
        pDateTime->D = 1
    ElseIf validJulianDay(pDateTime->iJD) = 0 Then
        datetimeError(pDateTime)
        Return
    Else
        Dim julianDay As SQLITE_C_INT = _
            Cast(SQLITE_C_INT, (pDateTime->iJD + 43200000) \ 86400000)
        Dim century As SQLITE_C_INT = _
            Cast(SQLITE_C_INT, Fix((CDbl(julianDay) + 32044.75) / 36524.25)) - 52
        Dim aValue As SQLITE_C_INT = _
            julianDay + 1 + century - ((century + 100) \ 4) + 25
        Dim bValue As SQLITE_C_INT = aValue + 1524
        Dim cValue As SQLITE_C_INT = _
            Cast(SQLITE_C_INT, Fix((CDbl(bValue) - 122.1) / 365.25))
        Dim dValue As SQLITE_C_INT = (36525 * (cValue And 32767)) \ 100
        Dim eValue As SQLITE_C_INT = _
            Cast(SQLITE_C_INT, Fix(CDbl(bValue - dValue) / 30.6001))
        Dim xValue As SQLITE_C_INT = Cast(SQLITE_C_INT, Fix(30.6001 * eValue))
        pDateTime->D = bValue - dValue - xValue
        If eValue < 14 Then
            pDateTime->month = eValue - 1
        Else
            pDateTime->month = eValue - 13
        End If
        If pDateTime->month > 2 Then
            pDateTime->Y = cValue - 4716
        Else
            pDateTime->Y = cValue - 4715
        End If
    End If
    pDateTime->validYMD = 1
End Sub

Sub computeHMS CDecl Alias "computeHMS" (ByVal pDateTime As SqliteDateTime Ptr)
    If pDateTime = 0 OrElse pDateTime->validHMS <> 0 Then Return

    computeJD(pDateTime)
    Dim dayMilliseconds As SQLITE_C_INT = _
        Cast(SQLITE_C_INT, (pDateTime->iJD + 43200000) Mod 86400000)
    pDateTime->s = CDbl(dayMilliseconds Mod 60000) / 1000.0
    Dim dayMinutes As SQLITE_C_INT = dayMilliseconds \ 60000
    pDateTime->minute = dayMinutes Mod 60
    pDateTime->h = dayMinutes \ 60
    pDateTime->rawS = 0
    pDateTime->validHMS = 1
End Sub

Sub computeYMD_HMS CDecl Alias "computeYMD_HMS" (ByVal pDateTime As SqliteDateTime Ptr)
    If pDateTime = 0 Then Return
    computeYMD(pDateTime)
    computeHMS(pDateTime)
End Sub

Function parseTimezone CDecl Alias "parseTimezone" ( _
    ByVal zDateArgument As Const ZString Ptr, _
    ByVal pDateTime As SqliteDateTime Ptr _
) As SQLITE_C_INT
    If zDateArgument = 0 OrElse pDateTime = 0 Then Return 1

    Dim zDate As Const UByte Ptr = CPtr(Const UByte Ptr, zDateArgument)
    Dim sign As SQLITE_C_INT = 0
    Dim hourValue As SQLITE_C_INT = 0
    Dim minuteValue As SQLITE_C_INT = 0
    While dateIsSpace(zDate[0]) <> 0
        zDate += 1
    Wend
    pDateTime->tz = 0

    Select Case zDate[0]
    Case Asc("-")
        sign = -1
    Case Asc("+")
        sign = 1
    Case Asc("Z"), Asc("z")
        zDate += 1
        pDateTime->isLocal = 0
        pDateTime->isUtc = 1
        GoTo zulu_time
    Case Else
        Return CInt(zDate[0] <> 0)
    End Select

    zDate += 1
    If getDigits(CPtr(Const ZString Ptr, zDate), StrPtr("20b:20e"), _
                 @hourValue, @minuteValue) <> 2 Then
        Return 1
    End If
    zDate += 5
    pDateTime->tz = sign * (minuteValue + hourValue * 60)
    If pDateTime->tz = 0 Then
        pDateTime->isLocal = 0
        pDateTime->isUtc = 1
    End If

zulu_time:
    While dateIsSpace(zDate[0]) <> 0
        zDate += 1
    Wend
    Return CInt(zDate[0] <> 0)
End Function

Function parseHhMmSs CDecl Alias "parseHhMmSs" ( _
    ByVal zDateArgument As Const ZString Ptr, _
    ByVal pDateTime As SqliteDateTime Ptr _
) As SQLITE_C_INT
    If zDateArgument = 0 OrElse pDateTime = 0 Then Return 1

    Dim zDate As Const UByte Ptr = CPtr(Const UByte Ptr, zDateArgument)
    Dim hourValue As SQLITE_C_INT = 0
    Dim minuteValue As SQLITE_C_INT = 0
    Dim secondValue As SQLITE_C_INT = 0
    Dim fraction As Double = 0.0
    If getDigits(CPtr(Const ZString Ptr, zDate), StrPtr("20c:20e"), _
                 @hourValue, @minuteValue) <> 2 Then
        Return 1
    End If
    zDate += 5

    If zDate[0] = Asc(":") Then
        zDate += 1
        If getDigits(CPtr(Const ZString Ptr, zDate), StrPtr("20e"), _
                     @secondValue) <> 1 Then
            Return 1
        End If
        zDate += 2
        If zDate[0] = Asc(".") AndAlso dateIsDigit(zDate[1]) <> 0 Then
            Dim scale As Double = 1.0
            zDate += 1
            While dateIsDigit(zDate[0]) <> 0
                fraction = fraction * 10.0 + (zDate[0] - Asc("0"))
                scale *= 10.0
                zDate += 1
            Wend
            fraction /= scale
            If fraction > 0.999 Then fraction = 0.999
        End If
    End If

    If hourValue = 24 AndAlso _
       (minuteValue <> 0 OrElse secondValue <> 0 OrElse fraction <> 0.0) Then
        Return 1
    End If

    pDateTime->validJD = 0
    pDateTime->rawS = 0
    pDateTime->validHMS = 1
    pDateTime->h = hourValue
    pDateTime->minute = minuteValue
    pDateTime->s = secondValue + fraction
    Return parseTimezone(CPtr(Const ZString Ptr, zDate), pDateTime)
End Function

Function parseYyyyMmDd CDecl Alias "parseYyyyMmDd" ( _
    ByVal zDateArgument As Const ZString Ptr, _
    ByVal pDateTime As SqliteDateTime Ptr _
) As SQLITE_C_INT
    If zDateArgument = 0 OrElse pDateTime = 0 Then Return 1

    Dim zDate As Const UByte Ptr = CPtr(Const UByte Ptr, zDateArgument)
    Dim isNegativeYear As SQLITE_C_INT = 0
    Dim yearValue As SQLITE_C_INT = 0
    Dim monthValue As SQLITE_C_INT = 0
    Dim dayValue As SQLITE_C_INT = 0
    If zDate[0] = Asc("-") Then
        zDate += 1
        isNegativeYear = 1
    End If
    If getDigits(CPtr(Const ZString Ptr, zDate), StrPtr("40f-21a-21d"), _
                 @yearValue, @monthValue, @dayValue) <> 3 Then
        Return 1
    End If
    zDate += 10
    While dateIsSpace(zDate[0]) <> 0 OrElse zDate[0] = Asc("T")
        zDate += 1
    Wend

    If parseHhMmSs(CPtr(Const ZString Ptr, zDate), pDateTime) <> 0 Then
        If zDate[0] <> 0 Then Return 1
        pDateTime->validHMS = 0
    End If

    pDateTime->validJD = 0
    pDateTime->validYMD = 1
    pDateTime->Y = IIf(isNegativeYear <> 0, -yearValue, yearValue)
    pDateTime->month = monthValue
    pDateTime->D = dayValue
    computeFloor(pDateTime)
    If pDateTime->tz <> 0 Then computeJD(pDateTime)
    Return 0
End Function

Function setDateTimeToCurrent CDecl Alias "setDateTimeToCurrent" ( _
    ByVal pContext As Any Ptr, _
    ByVal pDateTime As SqliteDateTime Ptr _
) As SQLITE_C_INT
    If pContext = 0 OrElse pDateTime = 0 Then Return 1

    pDateTime->iJD = sqlite3StmtCurrentTime(pContext)
    If pDateTime->iJD > 0 Then
        pDateTime->validJD = 1
        pDateTime->isUtc = 1
        pDateTime->isLocal = 0
        clearYMD_HMS_TZ(pDateTime)
        Return 0
    End If
    Return 1
End Function

Function parseDateOrTime CDecl Alias "parseDateOrTime" ( _
    ByVal pContext As Any Ptr, _
    ByVal zDate As Const ZString Ptr, _
    ByVal pDateTime As SqliteDateTime Ptr _
) As SQLITE_C_INT
    If pContext = 0 OrElse zDate = 0 OrElse pDateTime = 0 Then Return 1

    If parseYyyyMmDd(zDate, pDateTime) = 0 Then Return 0
    If parseHhMmSs(zDate, pDateTime) = 0 Then Return 0
    Dim pResultContext As SqliteResultContext Ptr = _
        CPtr(SqliteResultContext Ptr, pContext)
    If sqlite3StrICmp(zDate, StrPtr("now")) = 0 AndAlso _
       sqlite3NotPureFunc(pResultContext) <> 0 Then
        Return setDateTimeToCurrent(pContext, pDateTime)
    End If

    Dim numericValue As Double = 0.0
    If sqlite3AtoF(zDate, @numericValue) > 0 Then
        setRawDateNumber(pDateTime, numericValue)
        Return 0
    End If
    If (sqlite3StrICmp(zDate, StrPtr("subsec")) = 0 OrElse _
        sqlite3StrICmp(zDate, StrPtr("subsecond")) = 0) AndAlso _
       sqlite3NotPureFunc(pResultContext) <> 0 Then
        pDateTime->useSubsec = 1
        Return setDateTimeToCurrent(pContext, pDateTime)
    End If
    Return 1
End Function

Function toLocaltime CDecl Alias "toLocaltime" ( _
    ByVal pDateTime As SqliteDateTime Ptr, _
    ByVal pContext As Any Ptr _
) As SQLITE_C_INT
    If pDateTime = 0 OrElse pContext = 0 Then Return SQLITE_MISUSE

    Dim localFields As tm = Type<tm>(0)
    Dim yearDifference As SQLITE_C_INT = 0
    computeJD(pDateTime)

    ' The C runtime local-time conversion is unreliable outside 1970 through
    ' 2038 on several platforms. Reuse an equivalent year in that interval.
    Dim firstSupportedJulianMs As sqlite3_int64 = _
        Cast(sqlite3_int64, 2108667600) * 100000
    Dim lastSupportedJulianMs As sqlite3_int64 = _
        Cast(sqlite3_int64, 2130141456) * 100000
    Dim timeValue As time_t
    If pDateTime->iJD < firstSupportedJulianMs OrElse _
       pDateTime->iJD > lastSupportedJulianMs Then
        Dim adjustedDate As SqliteDateTime = *pDateTime
        computeYMD_HMS(@adjustedDate)
        Dim yearRemainder As SQLITE_C_INT = _
            adjustedDate.Y - Cast(SQLITE_C_INT, Fix(CDbl(adjustedDate.Y) / 4.0)) * 4
        yearDifference = (2000 + yearRemainder) - adjustedDate.Y
        adjustedDate.Y += yearDifference
        adjustedDate.validJD = 0
        computeJD(@adjustedDate)
        timeValue = Cast(time_t, (adjustedDate.iJD \ 1000) - _
                         Cast(sqlite3_int64, 21086676) * 10000)
    Else
        timeValue = Cast(time_t, (pDateTime->iJD \ 1000) - _
                         Cast(sqlite3_int64, 21086676) * 10000)
    End If

    If osLocaltime(@timeValue, @localFields) <> 0 Then
        sqlite3_result_error(pContext, StrPtr("local time unavailable"), -1)
        Return SQLITE_ERROR
    End If

    pDateTime->Y = localFields.tm_year + 1900 - yearDifference
    pDateTime->month = localFields.tm_mon + 1
    pDateTime->D = localFields.tm_mday
    pDateTime->h = localFields.tm_hour
    pDateTime->minute = localFields.tm_min
    pDateTime->s = localFields.tm_sec + CDbl(pDateTime->iJD Mod 1000) * 0.001
    pDateTime->validYMD = 1
    pDateTime->validHMS = 1
    pDateTime->validJD = 0
    pDateTime->rawS = 0
    pDateTime->tz = 0
    pDateTime->isError = 0
    Return SQLITE_OK
End Function

Sub autoAdjustDate CDecl Alias "autoAdjustDate" ( _
    ByVal pDateTime As SqliteDateTime Ptr _
)
    If pDateTime = 0 Then Return

    If pDateTime->rawS = 0 OrElse pDateTime->validJD <> 0 Then
        pDateTime->rawS = 0
    Else
        Dim minUnixSeconds As sqlite3_int64 = _
            -Cast(sqlite3_int64, 21086676) * 10000
        Dim maxUnixSeconds As sqlite3_int64 = _
            Cast(sqlite3_int64, 25340230) * 10000 + 799
        If pDateTime->s >= CDbl(minUnixSeconds) AndAlso _
           pDateTime->s <= CDbl(maxUnixSeconds) Then
            Dim julianMilliseconds As Double = _
                pDateTime->s * 1000.0 + 210866760000000.0
            clearYMD_HMS_TZ(pDateTime)
            pDateTime->iJD = Cast(sqlite3_int64, Fix(julianMilliseconds + 0.5))
            pDateTime->validJD = 1
            pDateTime->rawS = 0
        End If
    End If
End Sub

/' end of sqlite3_date_helpers.bas '/
