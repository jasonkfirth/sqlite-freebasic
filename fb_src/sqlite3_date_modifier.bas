/'
    Project: SQLite FreeBASIC port

    File: sqlite3_date_modifier.bas

    Purpose:

        Apply one SQLite date/time modifier to a DateTime value.

    Responsibilities:

        - Preserve the source order and bounds for calendar and clock modifiers.
        - Normalize raw numbers, Julian days, weekday offsets, and unit shifts.
        - Route local-time conversions through the DateTime helper layer.

    This file intentionally does NOT contain:

        - The SQL date/time result formatters or modifier-list iteration.
        - A claim that compilation establishes behavior parity.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_date_types.bi"
#include once "sqlite3_global_data.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_result.bi"
#include once "sqlite3_fp.bi"

Declare Function sqlite3_context_db_handle CDecl Alias "sqlite3_context_db_handle" ( _
    ByVal pContext As Any Ptr _
) As Any Ptr
Declare Function sqlite3NotPureFunc CDecl Alias "sqlite3NotPureFunc" ( _
    ByVal pContext As SqliteResultContext Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3_result_error CDecl Alias "sqlite3_result_error" ( _
    ByVal pContext As Any Ptr, _
    ByVal zError As Const ZString Ptr, _
    ByVal nError As SQLITE_C_INT _
)
Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal z As Const ZString Ptr _
) As SQLITE_C_INT

' These units are expressed in the Julian-day millisecond representation used
' by DateTime.iJD. The offset converts Unix seconds to that representation.
Private Const DATE_MILLISECONDS_PER_DAY As sqlite3_int64 = 86400000
Private Const DATE_MILLISECONDS_PER_MINUTE As sqlite3_int64 = 60000
Private Const DATE_MILLISECONDS_AT_NOON As sqlite3_int64 = 43200000
Private Const DATE_UNIX_EPOCH_OFFSET As sqlite3_int64 = 210866760000000
Private Const DATE_MAX_JULIAN_MILLISECONDS As Double = 464269060800000.0

Private Function dateTextEquals( _
    ByVal zText As Const UByte Ptr, _
    ByVal zLiteral As Const ZString Ptr _
) As SQLITE_C_INT
    If zText = 0 OrElse zLiteral = 0 Then Return 0
    Dim zExpected As Const UByte Ptr = CPtr(Const UByte Ptr, zLiteral)
    Dim index As Long = 0
    While zExpected[index] <> 0
        If zText[index] = 0 Then Return 0
        If sqlite3UpperToLower(zText[index]) <> _
           sqlite3UpperToLower(zExpected[index]) Then Return 0
        index += 1
    Wend
    Return CInt(zText[index] = 0)
End Function

Private Function dateTextPrefixEquals( _
    ByVal zText As Const UByte Ptr, _
    ByVal zLiteral As Const ZString Ptr, _
    ByVal byteCount As SQLITE_C_INT _
) As SQLITE_C_INT
    If zText = 0 OrElse zLiteral = 0 OrElse byteCount < 0 Then Return 0
    Dim zExpected As Const UByte Ptr = CPtr(Const UByte Ptr, zLiteral)
    For index As Long = 0 To byteCount - 1
        If zText[index] = 0 OrElse zExpected[index] = 0 Then Return 0
        If sqlite3UpperToLower(zText[index]) <> _
           sqlite3UpperToLower(zExpected[index]) Then Return 0
    Next
    Return CInt(zExpected[byteCount] = 0)
End Function

Private Function dateContainsMinus(ByVal zText As Const UByte Ptr) As SQLITE_C_INT
    If zText = 0 Then Return 0
    Dim index As Long = 0
    While zText[index] <> 0
        If zText[index] = Asc("-") Then Return 1
        index += 1
    Wend
    Return 0
End Function

Private Function dateModifierIsSpace(ByVal character As UByte) As SQLITE_C_INT
    Return CInt((sqlite3CtypeMap(character) And &H01) <> 0)
End Function

Private Function dateModifierIsDigit(ByVal character As UByte) As SQLITE_C_INT
    Return CInt((sqlite3CtypeMap(character) And &H04) <> 0)
End Function

Private Function dateDivideTowardZero( _
    ByVal numerator As SQLITE_C_INT, _
    ByVal denominator As SQLITE_C_INT _
) As SQLITE_C_INT
    Return Cast(SQLITE_C_INT, Fix(CDbl(numerator) / CDbl(denominator)))
End Function


Private Function parseNumericDateModifier( _
    ByVal pContext As Any Ptr, _
    ByVal zStart As Const UByte Ptr, _
    ByVal pDateTime As SqliteDateTime Ptr, _
    ByVal modifierIndex As SQLITE_C_INT _
) As SQLITE_C_INT
    If pContext = 0 OrElse zStart = 0 OrElse pDateTime = 0 Then Return 1

    Dim z As Const UByte Ptr = zStart
    Dim zAfter As Const UByte Ptr
    Dim originalSign As UByte = z[0]
    Dim scanLength As SQLITE_C_INT = 1
    Dim yearValue As SQLITE_C_INT = 0
    Dim rc As SQLITE_C_INT = 1
    Dim monthCarry As SQLITE_C_INT
    While z[scanLength] <> 0
        If z[scanLength] = Asc(":") OrElse _
           dateModifierIsSpace(z[scanLength]) <> 0 Then Exit While
        If z[scanLength] = Asc("-") Then
            If scanLength = 5 AndAlso _
               getDigits(CPtr(Const ZString Ptr, z + 1), StrPtr("40f"), @yearValue) = 1 Then
                Exit While
            End If
            If scanLength = 6 AndAlso _
               getDigits(CPtr(Const ZString Ptr, z + 1), StrPtr("50f"), @yearValue) = 1 Then
                Exit While
            End If
        End If
        scanLength += 1
    Wend

    Dim pDb As sqlite3 Ptr = _
        CPtr(sqlite3 Ptr, sqlite3_context_db_handle(pContext))
    Dim zNumber As ZString Ptr = sqlite3DbStrNDup( _
        pDb, CPtr(Const ZString Ptr, z), CULngInt(scanLength))
    If zNumber = 0 Then Return 1
    Dim value As Double = 0.0
    Dim conversionRc As SQLITE_C_INT = sqlite3AtoF(zNumber, @value)
    sqlite3DbFree(pDb, zNumber)
    If conversionRc <= 0 Then Return 1

    If z[scanLength] = Asc("-") Then
        If originalSign <> Asc("+") AndAlso originalSign <> Asc("-") Then Return 1
        Dim dateYear As SQLITE_C_INT = 0
        Dim dateMonth As SQLITE_C_INT = 0
        Dim dateDay As SQLITE_C_INT = 0
        If scanLength = 5 Then
            If getDigits(CPtr(Const ZString Ptr, z + 1), _
                         StrPtr("40f-20a-20d"), _
                         @dateYear, @dateMonth, @dateDay) <> 3 Then Return 1
        ElseIf scanLength = 6 Then
            If getDigits(CPtr(Const ZString Ptr, z + 1), _
                         StrPtr("50f-20a-20d"), _
                         @dateYear, @dateMonth, @dateDay) <> 3 Then Return 1
            z += 1
        Else
            Return 1
        End If
        If dateMonth >= 12 OrElse dateDay >= 31 Then Return 1

        computeYMD_HMS(pDateTime)
        pDateTime->validJD = 0
        If originalSign = Asc("-") Then
            pDateTime->Y -= dateYear
            pDateTime->month -= dateMonth
            dateDay = -dateDay
        Else
            pDateTime->Y += dateYear
            pDateTime->month += dateMonth
        End If
        If pDateTime->month > 0 Then
            monthCarry = dateDivideTowardZero(pDateTime->month - 1, 12)
        Else
            monthCarry = dateDivideTowardZero(pDateTime->month - 12, 12)
        End If
        pDateTime->Y += monthCarry
        pDateTime->month -= monthCarry * 12
        computeFloor(pDateTime)
        computeJD(pDateTime)
        pDateTime->validHMS = 0
        pDateTime->validYMD = 0
        pDateTime->iJD += Cast(sqlite3_int64, dateDay) * _
                          DATE_MILLISECONDS_PER_DAY
        If z[11] = 0 Then Return 0

        Dim hourCheck As SQLITE_C_INT = 0
        Dim minuteCheck As SQLITE_C_INT = 0
        If dateModifierIsSpace(z[11]) = 0 OrElse _
           getDigits(CPtr(Const ZString Ptr, z + 12), StrPtr("20c:20e"), _
                     @hourCheck, @minuteCheck) <> 2 Then Return 1
        zAfter = z + 12
        scanLength = 2
    Else
        zAfter = z
    End If

    If zAfter[scanLength] = Asc(":") Then
        Dim zTime As Const UByte Ptr = zAfter
        If dateModifierIsDigit(zTime[0]) = 0 Then zTime += 1
        Dim timeOffset As SqliteDateTime = Type<SqliteDateTime>(0)
        If parseHhMmSs(CPtr(Const ZString Ptr, zTime), @timeOffset) <> 0 Then Return 1
        computeJD(@timeOffset)
        timeOffset.iJD -= DATE_MILLISECONDS_AT_NOON
        Dim wholeDays As sqlite3_int64 = Cast(sqlite3_int64, _
            Fix(CDbl(timeOffset.iJD) / CDbl(DATE_MILLISECONDS_PER_DAY)))
        timeOffset.iJD -= wholeDays * DATE_MILLISECONDS_PER_DAY
        If originalSign = Asc("-") Then timeOffset.iJD = -timeOffset.iJD
        computeJD(pDateTime)
        clearYMD_HMS_TZ(pDateTime)
        pDateTime->iJD += timeOffset.iJD
        Return 0
    End If

    z = zAfter + scanLength
    While dateModifierIsSpace(z[0]) <> 0
        z += 1
    Wend
    Dim unitLength As SQLITE_C_INT = _
        sqlite3Strlen30(CPtr(Const ZString Ptr, z))
    If unitLength < 3 OrElse unitLength > 10 Then Return 1
    If sqlite3UpperToLower(z[unitLength - 1]) = Asc("s") Then unitLength -= 1

    computeJD(pDateTime)
    pDateTime->nFloor = 0
    Dim rounder As Double = IIf(value < 0.0, -0.5, 0.5)
    Dim unitIndex As SQLITE_C_INT = -1
    Dim unitLimit As Single = 0.0
    Dim unitScale As Single = 0.0
    Select Case unitLength
    Case 3
        If dateTextPrefixEquals(z, StrPtr("day"), 3) <> 0 Then
            unitIndex = 3
            unitLimit = 5373485.0
            unitScale = 86400.0
        End If
    Case 4
        If dateTextPrefixEquals(z, StrPtr("hour"), 4) <> 0 Then
            unitIndex = 2
            unitLimit = 1.2897E+11
            unitScale = 3600.0
        ElseIf dateTextPrefixEquals(z, StrPtr("year"), 4) <> 0 Then
            unitIndex = 5
            unitLimit = 14713.0
            unitScale = 31536000.0
        End If
    Case 5
        If dateTextPrefixEquals(z, StrPtr("month"), 5) <> 0 Then
            unitIndex = 4
            unitLimit = 176546.0
            unitScale = 2592000.0
        End If
    Case 6
        If dateTextPrefixEquals(z, StrPtr("second"), 6) <> 0 Then
            unitIndex = 0
            unitLimit = 4.6427E+14
            unitScale = 1.0
        ElseIf dateTextPrefixEquals(z, StrPtr("minute"), 6) <> 0 Then
            unitIndex = 1
            unitLimit = 7.7379E+12
            unitScale = 60.0
        End If
    End Select

    If unitIndex >= 0 AndAlso value > -CDbl(unitLimit) AndAlso _
       value < CDbl(unitLimit) Then
        Select Case unitIndex
        Case 4
            Dim wholeMonths As SQLITE_C_INT = _
                Cast(SQLITE_C_INT, Fix(value))
            computeYMD_HMS(pDateTime)
            pDateTime->month += wholeMonths
            If pDateTime->month > 0 Then
                monthCarry = dateDivideTowardZero(pDateTime->month - 1, 12)
            Else
                monthCarry = dateDivideTowardZero(pDateTime->month - 12, 12)
            End If
            pDateTime->Y += monthCarry
            pDateTime->month -= monthCarry * 12
            computeFloor(pDateTime)
            pDateTime->validJD = 0
            value -= wholeMonths
        Case 5
            Dim wholeYears As SQLITE_C_INT = Cast(SQLITE_C_INT, Fix(value))
            computeYMD_HMS(pDateTime)
            pDateTime->Y += wholeYears
            computeFloor(pDateTime)
            pDateTime->validJD = 0
            value -= wholeYears
        End Select
        computeJD(pDateTime)
        pDateTime->iJD += Cast(sqlite3_int64, _
            Fix(value * 1000.0 * CDbl(unitScale) + rounder))
        rc = 0
    End If
    clearYMD_HMS_TZ(pDateTime)
    Return rc
End Function

Function parseModifier CDecl Alias "parseModifier" ( _
    ByVal pContext As Any Ptr, _
    ByVal zModifier As Const ZString Ptr, _
    ByVal modifierLength As SQLITE_C_INT, _
    ByVal pDateTime As SqliteDateTime Ptr, _
    ByVal modifierIndex As SQLITE_C_INT _
) As SQLITE_C_INT
    If pContext = 0 OrElse zModifier = 0 OrElse pDateTime = 0 OrElse _
       modifierLength < 0 Then Return 1

    Dim z As Const UByte Ptr = CPtr(Const UByte Ptr, zModifier)
    Dim zAfter As Const UByte Ptr
    Dim rc As SQLITE_C_INT = 1
    Dim realValue As Double = 0.0
    Dim firstByte As UByte = z[0]
    Select Case sqlite3UpperToLower(firstByte)
    Case Asc("a")
        If dateTextEquals(z, StrPtr("auto")) <> 0 Then
            If modifierIndex > 1 Then Return 1
            autoAdjustDate(pDateTime)
            rc = 0
        End If

    Case Asc("c")
        If dateTextEquals(z, StrPtr("ceiling")) <> 0 Then
            computeJD(pDateTime)
            clearYMD_HMS_TZ(pDateTime)
            pDateTime->nFloor = 0
            rc = 0
        End If

    Case Asc("e")
        If dateTextPrefixEquals(z, StrPtr("end of "), 7) = 0 Then Exit Select
        If pDateTime->validJD = 0 AndAlso pDateTime->validYMD = 0 AndAlso _
           pDateTime->validHMS = 0 Then Return rc
        zAfter = z + 7
        computeYMD(pDateTime)
        pDateTime->validHMS = 1
        pDateTime->h = 23
        pDateTime->minute = 59
        pDateTime->s = 59.999
        pDateTime->rawS = 0
        pDateTime->tz = 0
        pDateTime->validJD = 0
        If dateTextEquals(zAfter, StrPtr("month")) <> 0 Then
            pDateTime->D = 1
            pDateTime->month += 1
            If pDateTime->month > 12 Then
                pDateTime->Y += 1
                pDateTime->month = 1
            End If
            computeFloor(pDateTime)
            computeJD(pDateTime)
            pDateTime->iJD -= (pDateTime->nFloor + 1) * _
                              DATE_MILLISECONDS_PER_DAY
            clearYMD_HMS_TZ(pDateTime)
            rc = 0
        ElseIf dateTextEquals(zAfter, StrPtr("year")) <> 0 Then
            pDateTime->month = 12
            pDateTime->D = 31
            rc = 0
        ElseIf dateTextEquals(zAfter, StrPtr("day")) <> 0 Then
            rc = 0
        End If

    Case Asc("f")
        If dateTextEquals(z, StrPtr("floor")) <> 0 Then
            computeJD(pDateTime)
            pDateTime->iJD -= pDateTime->nFloor * DATE_MILLISECONDS_PER_DAY
            clearYMD_HMS_TZ(pDateTime)
            rc = 0
        End If

    Case Asc("j")
        If dateTextEquals(z, StrPtr("julianday")) <> 0 Then
            If modifierIndex > 1 Then Return 1
            If pDateTime->validJD <> 0 AndAlso pDateTime->rawS <> 0 Then
                pDateTime->rawS = 0
                rc = 0
            End If
        End If

    Case Asc("l")
        If dateTextEquals(z, StrPtr("localtime")) <> 0 AndAlso _
           sqlite3NotPureFunc(CPtr(SqliteResultContext Ptr, pContext)) <> 0 Then
            If pDateTime->isLocal <> 0 Then
                rc = 0
            Else
                rc = toLocaltime(pDateTime, pContext)
            End If
            pDateTime->isUtc = 0
            pDateTime->isLocal = 1
        End If

    Case Asc("u")
        If dateTextEquals(z, StrPtr("unixepoch")) <> 0 AndAlso _
           pDateTime->rawS <> 0 Then
            If modifierIndex > 1 Then Return 1
            Dim julianMilliseconds As Double = _
                pDateTime->s * 1000.0 + CDbl(DATE_UNIX_EPOCH_OFFSET)
            If julianMilliseconds >= 0.0 AndAlso _
               julianMilliseconds < DATE_MAX_JULIAN_MILLISECONDS Then
                clearYMD_HMS_TZ(pDateTime)
                pDateTime->iJD = Cast(sqlite3_int64, Fix(julianMilliseconds + 0.5))
                pDateTime->validJD = 1
                pDateTime->rawS = 0
                rc = 0
            End If
        ElseIf dateTextEquals(z, StrPtr("utc")) <> 0 AndAlso _
               sqlite3NotPureFunc(CPtr(SqliteResultContext Ptr, pContext)) <> 0 Then
            If pDateTime->isUtc = 0 Then
                computeJD(pDateTime)
                Dim originalJulianMs As sqlite3_int64 = pDateTime->iJD
                Dim guessedJulianMs As sqlite3_int64 = originalJulianMs
                Dim previousError As sqlite3_int64 = 0
                Dim retryCount As SQLITE_C_INT = 0
                Do
                    Dim adjustedLocal As SqliteDateTime = Type<SqliteDateTime>(0)
                    guessedJulianMs -= previousError
                    adjustedLocal.iJD = guessedJulianMs
                    adjustedLocal.validJD = 1
                    rc = toLocaltime(@adjustedLocal, pContext)
                    If rc <> 0 Then Return rc
                    computeJD(@adjustedLocal)
                    previousError = adjustedLocal.iJD - originalJulianMs
                    If previousError = 0 OrElse retryCount >= 3 Then Exit Do
                    retryCount += 1
                Loop
                *pDateTime = Type<SqliteDateTime>(0)
                pDateTime->iJD = guessedJulianMs
                pDateTime->validJD = 1
                pDateTime->isUtc = 1
                pDateTime->isLocal = 0
            End If
            rc = 0
        End If

    Case Asc("w")
        If dateTextPrefixEquals(z, StrPtr("weekday "), 8) <> 0 Then
            If sqlite3AtoF(CPtr(Const ZString Ptr, z + 8), @realValue) > 0 AndAlso _
               realValue >= -6.0 AndAlso realValue <= 6.0 Then
                Dim weekday As SQLITE_C_INT = _
                    Cast(SQLITE_C_INT, Fix(realValue))
                If realValue = CDbl(weekday) Then
                    computeYMD_HMS(pDateTime)
                    pDateTime->tz = 0
                    pDateTime->validJD = 0
                    computeJD(pDateTime)
                    Dim currentWeekday As sqlite3_int64 = _
                        ((pDateTime->iJD + 129600000) \ DATE_MILLISECONDS_PER_DAY) Mod 7
                    If weekday < 0 Then weekday = -weekday
                    If currentWeekday <> weekday Then
                        If currentWeekday > weekday Then currentWeekday -= 7
                        pDateTime->iJD += (weekday - currentWeekday) * _
                                          DATE_MILLISECONDS_PER_DAY
                        If dateContainsMinus(z + 8) <> 0 Then _
                            pDateTime->iJD -= 7 * DATE_MILLISECONDS_PER_DAY
                    End If
                    clearYMD_HMS_TZ(pDateTime)
                    rc = 0
                End If
            End If
        End If

    Case Asc("s")
        If dateTextPrefixEquals(z, StrPtr("start of "), 9) = 0 Then
            If dateTextEquals(z, StrPtr("subsec")) <> 0 OrElse _
               dateTextEquals(z, StrPtr("subsecond")) <> 0 Then
                pDateTime->useSubsec = 1
                rc = 0
            End If
            Exit Select
        End If
        If pDateTime->validJD = 0 AndAlso pDateTime->validYMD = 0 AndAlso _
           pDateTime->validHMS = 0 Then Return rc
        zAfter = z + 9
        computeYMD(pDateTime)
        pDateTime->validHMS = 1
        pDateTime->h = 0
        pDateTime->minute = 0
        pDateTime->s = 0.0
        pDateTime->rawS = 0
        pDateTime->tz = 0
        pDateTime->validJD = 0
        If dateTextEquals(zAfter, StrPtr("month")) <> 0 Then
            pDateTime->D = 1
            rc = 0
        ElseIf dateTextEquals(zAfter, StrPtr("year")) <> 0 Then
            pDateTime->month = 1
            pDateTime->D = 1
            rc = 0
        ElseIf dateTextEquals(zAfter, StrPtr("day")) <> 0 Then
            rc = 0
        End If

    Case Asc("+"), Asc("-"), Asc("0") To Asc("9")
        rc = parseNumericDateModifier(pContext, z, pDateTime, modifierIndex)
    End Select
    Return rc
End Function

' Date unit modifiers are separated here to keep the top-level modifier switch
' readable while preserving the source's ordered numeric, date, and time paths.


/' end of sqlite3_date_modifier.bas '/
