/'
    Project: SQLite FreeBASIC port

    File: sqlite3_date_sqlfunc.bas

    Purpose:

        Expose parsed DateTime values through SQLite's SQL date functions.

    Responsibilities:

        - Validate input values and apply their date modifiers.
        - Return Julian-day, Unix-epoch, date, time, datetime, and strftime results.
        - Provide current-date fallbacks when full date handling is omitted.
        - Register date functions and the debug date inspector under feature guards.

    This file intentionally does NOT contain:

        - A claim that compilation establishes behavior parity.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_date_types.bi"
#include once "sqlite3_result.bi"
#include once "sqlite3_straccum.bi"
#include once "sqlite3_vdbe_api.bi"

Declare Function sqlite3_context_db_handle CDecl Alias "sqlite3_context_db_handle" ( _
    ByVal pContext As Any Ptr _
) As Any Ptr
Declare Function sqlite3NotPureFunc CDecl Alias "sqlite3NotPureFunc" ( _
    ByVal pContext As SqliteResultContext Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3_result_double CDecl Alias "sqlite3_result_double" ( _
    ByVal pContext As Any Ptr, _
    ByVal value As Double _
)
Declare Sub sqlite3_result_int64 CDecl Alias "sqlite3_result_int64" ( _
    ByVal pContext As Any Ptr, _
    ByVal value As sqlite3_int64 _
)
Declare Sub sqlite3_result_null CDecl Alias "sqlite3_result_null" ( _
    ByVal pContext As Any Ptr _
)
Declare Sub sqlite3_result_error_nomem CDecl Alias "sqlite3_result_error_nomem" ( _
    ByVal pContext As Any Ptr _
)
Declare Sub sqlite3_result_text CDecl Alias "sqlite3_result_text" ( _
    ByVal pContext As Any Ptr, _
    ByVal zText As Const ZString Ptr, _
    ByVal byteCount As SQLITE_C_INT, _
    ByVal xDestroy As Any Ptr _
)
Declare Function sqlite3StmtCurrentTime CDecl Alias "sqlite3StmtCurrentTime" ( _
    ByVal pContext As Any Ptr _
) As sqlite3_int64
Declare Function sqlite3_user_data CDecl Alias "sqlite3_user_data" ( _
    ByVal pContext As Any Ptr _
) As Any Ptr
Declare Function sqlite3_mprintf CDecl Alias "sqlite3_mprintf" ( _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) As ZString Ptr
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal pMemory As Any Ptr)
Declare Sub sqlite3_result_str CDecl Alias "sqlite3_result_str" ( _
    ByVal pContext As Any Ptr, _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal ownership As SQLITE_C_INT _
)
Declare Sub sqlite3_str_appendf CDecl Alias "sqlite3_str_appendf" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Sub sqlite3InsertBuiltinFuncs CDecl Alias "sqlite3InsertBuiltinFuncs" ( _
    ByVal aDefinitions As SqliteFuncDef Ptr, _
    ByVal definitionCount As SQLITE_C_INT _
)

Declare Sub ctimeFunc CDecl Alias "ctimeFunc" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteVdbeMem Ptr Ptr)
Declare Sub cdateFunc CDecl Alias "cdateFunc" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteVdbeMem Ptr Ptr)
Declare Sub ctimestampFunc CDecl Alias "ctimestampFunc" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteVdbeMem Ptr Ptr)

Private Const SQLITE_FUNC_BUILTIN As u32 = &H00800000
Private Const DATE_BUILTIN_FLAGS As u32 = _
    SQLITE_FUNC_BUILTIN Or SQLITE_FUNC_SLOCHNG Or SQLITE_UTF8
Private Const PURE_DATE_FLAGS As u32 = _
    DATE_BUILTIN_FLAGS Or SQLITE_FUNC_CONSTANT
Private Const DATE_UNIX_EPOCH_OFFSET As sqlite3_int64 = 210866760000000
Private Const DATE_TIMEDIFF_OFFSET As sqlite3_int64 = 148699540800000
Private Dim Shared dateFunctionDefinitions(0 To 10) As SqliteFuncDef
Private Dim Shared dateFunctionsRegistered As u8 = 0

Private Function isDate CDecl Alias "isDate" ( _
    ByVal pContextArgument As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr, _
    ByVal pDateTime As SqliteDateTime Ptr _
) As SQLITE_C_INT
    If pContextArgument = 0 OrElse pDateTime = 0 OrElse argumentCount < 0 Then _
        Return 1
    If argumentCount > 0 AndAlso pArguments = 0 Then Return 1
    *pDateTime = Type<SqliteDateTime>(0)

    Dim pContext As SqliteResultContext Ptr = _
        CPtr(SqliteResultContext Ptr, pContextArgument)
    If argumentCount = 0 Then
        If sqlite3NotPureFunc(pContext) = 0 Then Return 1
        Return setDateTimeToCurrent(pContextArgument, pDateTime)
    End If

    Dim valueType As SQLITE_C_INT = sqlite3_value_type(pArguments[0])
    If valueType = SQLITE_FLOAT OrElse valueType = SQLITE_INTEGER Then
        setRawDateNumber(pDateTime, sqlite3_value_double(pArguments[0]))
    Else
        Dim zDate As Const UByte Ptr = sqlite3_value_text(pArguments[0])
        If zDate = 0 OrElse _
           parseDateOrTime(pContextArgument, CPtr(Const ZString Ptr, zDate), _
                           pDateTime) <> 0 Then Return 1
    End If

    For argumentIndex As SQLITE_C_INT = 1 To argumentCount - 1
        Dim zModifier As Const UByte Ptr = _
            sqlite3_value_text(pArguments[argumentIndex])
        Dim modifierLength As SQLITE_C_INT = _
            sqlite3_value_bytes(pArguments[argumentIndex])
        If zModifier = 0 OrElse _
           parseModifier(pContextArgument, CPtr(Const ZString Ptr, zModifier), _
                         modifierLength, pDateTime, argumentIndex) <> 0 Then
            Return 1
        End If
    Next

    computeJD(pDateTime)
    If pDateTime->isError <> 0 OrElse validJulianDay(pDateTime->iJD) = 0 Then _
        Return 1

    If argumentCount = 1 AndAlso pDateTime->validYMD <> 0 AndAlso _
       pDateTime->D > 28 Then
        ' Keep the computed Julian day so an overflowing day normalizes on read.
        pDateTime->validYMD = 0
    End If
    Return 0
End Function

Private Sub writeTwoDigits( _
    ByVal zBuffer As UByte Ptr, _
    ByVal offset As SQLITE_C_INT, _
    ByVal value As SQLITE_C_INT _
)
    zBuffer[offset] = Asc("0") + (value \ 10) Mod 10
    zBuffer[offset + 1] = Asc("0") + value Mod 10
End Sub

Private Sub writeFourDigits( _
    ByVal zBuffer As UByte Ptr, _
    ByVal offset As SQLITE_C_INT, _
    ByVal value As SQLITE_C_INT _
)
    zBuffer[offset] = Asc("0") + (value \ 1000) Mod 10
    zBuffer[offset + 1] = Asc("0") + (value \ 100) Mod 10
    zBuffer[offset + 2] = Asc("0") + (value \ 10) Mod 10
    zBuffer[offset + 3] = Asc("0") + value Mod 10
End Sub

Private Sub juliandayFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    Dim value As SqliteDateTime = Type<SqliteDateTime>(0)
    If isDate(pContext, argumentCount, pArguments, @value) = 0 Then
        computeJD(@value)
        sqlite3_result_double(pContext, CDbl(value.iJD) / 86400000.0)
    End If
End Sub

Private Sub unixepochFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    Dim value As SqliteDateTime = Type<SqliteDateTime>(0)
    If isDate(pContext, argumentCount, pArguments, @value) <> 0 Then Return
    computeJD(@value)
    If value.useSubsec <> 0 Then
        sqlite3_result_double(pContext, _
            CDbl(value.iJD - (21086676LL * 10000000LL)) / 1000.0)
    Else
        sqlite3_result_int64(pContext, _
            (value.iJD \ 1000) - (21086676LL * 10000LL))
    End If
End Sub

Private Sub timediffFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If argumentCount <> 2 OrElse pArguments = 0 Then Return

    Dim firstDate As SqliteDateTime = Type<SqliteDateTime>(0)
    Dim secondDate As SqliteDateTime = Type<SqliteDateTime>(0)
    If isDate(pContext, 1, @pArguments[0], @firstDate) <> 0 OrElse _
       isDate(pContext, 1, @pArguments[1], @secondDate) <> 0 Then Return

    computeYMD_HMS(@firstDate)
    computeYMD_HMS(@secondDate)

    Dim sign As UByte
    Dim yearDifference As SQLITE_C_INT
    Dim monthDifference As SQLITE_C_INT

    If firstDate.iJD >= secondDate.iJD Then
        sign = Asc("+")
        yearDifference = firstDate.Y - secondDate.Y
        If yearDifference <> 0 Then
            secondDate.Y = firstDate.Y
            secondDate.validJD = 0
            computeJD(@secondDate)
        End If

        monthDifference = firstDate.month - secondDate.month
        If monthDifference < 0 Then
            yearDifference -= 1
            monthDifference += 12
        End If
        If monthDifference <> 0 Then
            secondDate.month = firstDate.month
            secondDate.validJD = 0
            computeJD(@secondDate)
        End If

        While firstDate.iJD < secondDate.iJD
            monthDifference -= 1
            If monthDifference < 0 Then
                monthDifference = 11
                yearDifference -= 1
            End If
            secondDate.month -= 1
            If secondDate.month < 1 Then
                secondDate.month = 12
                secondDate.Y -= 1
            End If
            secondDate.validJD = 0
            computeJD(@secondDate)
        Wend

        firstDate.iJD -= secondDate.iJD
        firstDate.iJD += DATE_TIMEDIFF_OFFSET
    Else
        sign = Asc("-")
        yearDifference = secondDate.Y - firstDate.Y
        If yearDifference <> 0 Then
            secondDate.Y = firstDate.Y
            secondDate.validJD = 0
            computeJD(@secondDate)
        End If

        monthDifference = secondDate.month - firstDate.month
        If monthDifference < 0 Then
            yearDifference -= 1
            monthDifference += 12
        End If
        If monthDifference <> 0 Then
            secondDate.month = firstDate.month
            secondDate.validJD = 0
            computeJD(@secondDate)
        End If

        While firstDate.iJD > secondDate.iJD
            monthDifference -= 1
            If monthDifference < 0 Then
                monthDifference = 11
                yearDifference -= 1
            End If
            secondDate.month += 1
            If secondDate.month > 12 Then
                secondDate.month = 1
                secondDate.Y += 1
            End If
            secondDate.validJD = 0
            computeJD(@secondDate)
        Wend

        firstDate.iJD = secondDate.iJD - firstDate.iJD
        firstDate.iJD += DATE_TIMEDIFF_OFFSET
    End If

    clearYMD_HMS_TZ(@firstDate)
    computeYMD_HMS(@firstDate)

    Dim result As sqlite3_str
    sqlite3StrAccumInit(@result, 0, 0, 0, 100)
    sqlite3_str_appendf(@result, _
        StrPtr("%c%04d-%02d-%02d %02d:%02d:%06.3f"), _
        CInt(sign), yearDifference, monthDifference, firstDate.D - 1, _
        firstDate.h, firstDate.minute, firstDate.s)
    sqlite3_result_str(pContext, @result, SQLITE_XFER)
End Sub

Private Sub datetimeFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    Dim value As SqliteDateTime = Type<SqliteDateTime>(0)
    If isDate(pContext, argumentCount, pArguments, @value) <> 0 Then Return

    computeYMD_HMS(@value)
    Dim zBuffer(0 To 31) As UByte
    Dim yearValue As SQLITE_C_INT = value.Y
    If yearValue < 0 Then yearValue = -yearValue
    writeFourDigits(@zBuffer(0), 1, yearValue)
    zBuffer(5) = Asc("-")
    writeTwoDigits(@zBuffer(0), 6, value.month)
    zBuffer(8) = Asc("-")
    writeTwoDigits(@zBuffer(0), 9, value.D)
    zBuffer(11) = Asc(" ")
    writeTwoDigits(@zBuffer(0), 12, value.h)
    zBuffer(14) = Asc(":")
    writeTwoDigits(@zBuffer(0), 15, value.minute)
    zBuffer(17) = Asc(":")

    Dim textLength As SQLITE_C_INT
    If value.useSubsec <> 0 Then
        Dim milliseconds As SQLITE_C_INT = _
            Cast(SQLITE_C_INT, Fix(1000.0 * value.s + 0.5))
        zBuffer(18) = Asc("0") + (milliseconds \ 10000) Mod 10
        zBuffer(19) = Asc("0") + (milliseconds \ 1000) Mod 10
        zBuffer(20) = Asc(".")
        zBuffer(21) = Asc("0") + (milliseconds \ 100) Mod 10
        zBuffer(22) = Asc("0") + (milliseconds \ 10) Mod 10
        zBuffer(23) = Asc("0") + milliseconds Mod 10
        zBuffer(24) = 0
        textLength = 24
    Else
        Dim seconds As SQLITE_C_INT = Cast(SQLITE_C_INT, Fix(value.s))
        writeTwoDigits(@zBuffer(0), 18, seconds)
        zBuffer(20) = 0
        textLength = 20
    End If

    Dim textStart As SQLITE_C_INT = 1
    If value.Y < 0 Then
        zBuffer(0) = Asc("-")
        textStart = 0
    Else
        textLength -= 1
    End If
    ' -1 is SQLite's SQLITE_TRANSIENT destructor sentinel: copy before return.
    sqlite3_result_text(pContext, _
        CPtr(Const ZString Ptr, @zBuffer(textStart)), textLength, CPtr(Any Ptr, -1))
End Sub

Private Sub timeFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    Dim value As SqliteDateTime = Type<SqliteDateTime>(0)
    If isDate(pContext, argumentCount, pArguments, @value) <> 0 Then Return

    computeHMS(@value)
    Dim zBuffer(0 To 15) As UByte
    writeTwoDigits(@zBuffer(0), 0, value.h)
    zBuffer(2) = Asc(":")
    writeTwoDigits(@zBuffer(0), 3, value.minute)
    zBuffer(5) = Asc(":")
    Dim textLength As SQLITE_C_INT
    If value.useSubsec <> 0 Then
        Dim milliseconds As SQLITE_C_INT = _
            Cast(SQLITE_C_INT, Fix(1000.0 * value.s + 0.5))
        zBuffer(6) = Asc("0") + (milliseconds \ 10000) Mod 10
        zBuffer(7) = Asc("0") + (milliseconds \ 1000) Mod 10
        zBuffer(8) = Asc(".")
        zBuffer(9) = Asc("0") + (milliseconds \ 100) Mod 10
        zBuffer(10) = Asc("0") + (milliseconds \ 10) Mod 10
        zBuffer(11) = Asc("0") + milliseconds Mod 10
        zBuffer(12) = 0
        textLength = 12
    Else
        Dim seconds As SQLITE_C_INT = Cast(SQLITE_C_INT, Fix(value.s))
        writeTwoDigits(@zBuffer(0), 6, seconds)
        zBuffer(8) = 0
        textLength = 8
    End If
    sqlite3_result_text(pContext, CPtr(Const ZString Ptr, @zBuffer(0)), _
                        textLength, CPtr(Any Ptr, -1))
End Sub

Private Sub dateFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    Dim value As SqliteDateTime = Type<SqliteDateTime>(0)
    If isDate(pContext, argumentCount, pArguments, @value) <> 0 Then Return

    computeYMD(@value)
    Dim zBuffer(0 To 15) As UByte
    Dim yearValue As SQLITE_C_INT = value.Y
    If yearValue < 0 Then yearValue = -yearValue
    writeFourDigits(@zBuffer(0), 1, yearValue)
    zBuffer(5) = Asc("-")
    writeTwoDigits(@zBuffer(0), 6, value.month)
    zBuffer(8) = Asc("-")
    writeTwoDigits(@zBuffer(0), 9, value.D)
    zBuffer(11) = 0
    Dim textStart As SQLITE_C_INT = 1
    Dim textLength As SQLITE_C_INT = 10
    If value.Y < 0 Then
        zBuffer(0) = Asc("-")
        textStart = 0
        textLength = 11
    End If
    sqlite3_result_text(pContext, _
        CPtr(Const ZString Ptr, @zBuffer(textStart)), textLength, CPtr(Any Ptr, -1))
End Sub

Private Sub strftimeFunc CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse argumentCount = 0 OrElse pArguments = 0 Then Return
    Dim zFormat As Const UByte Ptr = sqlite3_value_text(pArguments[0])
    If zFormat = 0 Then Return

    Dim value As SqliteDateTime = Type<SqliteDateTime>(0)
    If isDate(pContext, argumentCount - 1, pArguments + 1, @value) <> 0 Then Return
    Dim pDatabase As sqlite3 Ptr = CPtr(sqlite3 Ptr, _
        sqlite3_context_db_handle(pContext))
    Dim pResult As sqlite3_str Ptr = sqlite3_str_new(pDatabase)
    If pResult = 0 Then
        sqlite3_result_error_nomem(pContext)
        Return
    End If

    computeJD(@value)
    computeYMD_HMS(@value)
    Dim index As SQLITE_C_INT = 0
    Dim literalStart As SQLITE_C_INT = 0
    While zFormat[index] <> 0
        If zFormat[index] <> Asc("%") Then
            index += 1
            Continue While
        End If

        If literalStart < index Then
            sqlite3_str_append(pResult, _
                CPtr(Const ZString Ptr, zFormat + literalStart), _
                index - literalStart)
        End If
        index += 1
        literalStart = index + 1
        Dim conversion As UByte = zFormat[index]
        Select Case conversion
        Case Asc("d")
            sqlite3_str_appendf(pResult, StrPtr("%02d"), value.D)
        Case Asc("e")
            sqlite3_str_appendf(pResult, StrPtr("%2d"), value.D)
        Case Asc("f")
            Dim seconds As Double = value.s
            If seconds > 59.999 Then seconds = 59.999
            sqlite3_str_appendf(pResult, StrPtr("%06.3f"), seconds)
        Case Asc("F")
            sqlite3_str_appendf(pResult, StrPtr("%04d-%02d-%02d"), _
                value.Y, value.month, value.D)
        Case Asc("G"), Asc("g")
            Dim isoDate As SqliteDateTime = value
            isoDate.iJD += (3 - daysAfterMonday(@value)) * 86400000
            isoDate.validYMD = 0
            computeYMD(@isoDate)
            If conversion = Asc("g") Then
                sqlite3_str_appendf(pResult, StrPtr("%02d"), isoDate.Y Mod 100)
            Else
                sqlite3_str_appendf(pResult, StrPtr("%04d"), isoDate.Y)
            End If
        Case Asc("H")
            sqlite3_str_appendf(pResult, StrPtr("%02d"), value.h)
        Case Asc("k")
            sqlite3_str_appendf(pResult, StrPtr("%2d"), value.h)
        Case Asc("I"), Asc("l")
            Dim hour12 As SQLITE_C_INT = value.h
            If hour12 > 12 Then hour12 -= 12
            If hour12 = 0 Then hour12 = 12
            If conversion = Asc("I") Then
                sqlite3_str_appendf(pResult, StrPtr("%02d"), hour12)
            Else
                sqlite3_str_appendf(pResult, StrPtr("%2d"), hour12)
            End If
        Case Asc("j")
            sqlite3_str_appendf(pResult, StrPtr("%03d"), _
                                daysAfterJan01(@value) + 1)
        Case Asc("J")
            sqlite3_str_appendf(pResult, StrPtr("%.16g"), _
                                CDbl(value.iJD) / 86400000.0)
        Case Asc("m")
            sqlite3_str_appendf(pResult, StrPtr("%02d"), value.month)
        Case Asc("M")
            sqlite3_str_appendf(pResult, StrPtr("%02d"), value.minute)
        Case Asc("p"), Asc("P")
            If value.h >= 12 Then
                If conversion = Asc("p") Then
                    sqlite3_str_append(pResult, StrPtr("PM"), 2)
                Else
                    sqlite3_str_append(pResult, StrPtr("pm"), 2)
                End If
            Else
                If conversion = Asc("p") Then
                    sqlite3_str_append(pResult, StrPtr("AM"), 2)
                Else
                    sqlite3_str_append(pResult, StrPtr("am"), 2)
                End If
            End If
        Case Asc("R")
            sqlite3_str_appendf(pResult, StrPtr("%02d:%02d"), _
                                value.h, value.minute)
        Case Asc("s")
            If value.useSubsec <> 0 Then
                sqlite3_str_appendf(pResult, StrPtr("%.3f"), _
                    CDbl(value.iJD - DATE_UNIX_EPOCH_OFFSET) / 1000.0)
            Else
                Dim unixSeconds As sqlite3_int64 = _
                    (value.iJD \ 1000) - (21086676LL * 10000LL)
                sqlite3_str_appendf(pResult, StrPtr("%lld"), unixSeconds)
            End If
        Case Asc("S")
            sqlite3_str_appendf(pResult, StrPtr("%02d"), _
                                Cast(SQLITE_C_INT, Fix(value.s)))
        Case Asc("T")
            sqlite3_str_appendf(pResult, StrPtr("%02d:%02d:%02d"), _
                value.h, value.minute, Cast(SQLITE_C_INT, Fix(value.s)))
        Case Asc("u"), Asc("w")
            Dim weekday As SQLITE_C_INT = daysAfterSunday(@value)
            Dim weekdayByte As Byte = Asc("0") + weekday
            If weekdayByte = Asc("0") AndAlso conversion = Asc("u") Then _
                weekdayByte = Asc("7")
            sqlite3_str_appendchar(pResult, 1, weekdayByte)
        Case Asc("U")
            Dim weekNumber As SQLITE_C_INT = _
                (daysAfterJan01(@value) - daysAfterSunday(@value) + 7) \ 7
            sqlite3_str_appendf(pResult, StrPtr("%02d"), weekNumber)
        Case Asc("V")
            Dim isoDate As SqliteDateTime = value
            isoDate.iJD += (3 - daysAfterMonday(@value)) * 86400000
            isoDate.validYMD = 0
            computeYMD(@isoDate)
            sqlite3_str_appendf(pResult, StrPtr("%02d"), _
                                daysAfterJan01(@isoDate) \ 7 + 1)
        Case Asc("W")
            Dim weekNumber As SQLITE_C_INT = _
                (daysAfterJan01(@value) - daysAfterMonday(@value) + 7) \ 7
            sqlite3_str_appendf(pResult, StrPtr("%02d"), weekNumber)
        Case Asc("Y")
            sqlite3_str_appendf(pResult, StrPtr("%04d"), value.Y)
        Case Asc("%")
            sqlite3_str_appendchar(pResult, 1, Asc("%"))
        Case Else
            sqlite3_str_free(pResult)
            Return
        End Select
        index += 1
    Wend

    If literalStart < index Then
        sqlite3_str_append(pResult, _
            CPtr(Const ZString Ptr, zFormat + literalStart), _
            index - literalStart)
    End If
    sqlite3_result_str(pContext, pResult, SQLITE_FINISH)
End Sub

Private Sub sqlite3CurrentTimeCallback CDecl Alias "ctimeFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    ' C's current_time() delegates to time() with no input parameters.
    timeFunc(pContext, 0, 0)
End Sub

Private Sub sqlite3CurrentDateCallback CDecl Alias "cdateFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    dateFunc(pContext, 0, 0)
End Sub

Private Sub sqlite3CurrentTimestampCallback CDecl Alias "ctimestampFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    datetimeFunc(pContext, 0, 0)
End Sub

#ifdef SQLITE_OMIT_DATETIME_FUNCS
Private Sub currentTimeFunc CDecl Alias "currentTimeFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 Then Return

    Dim zFormat As Const ZString Ptr = _
        CPtr(Const ZString Ptr, sqlite3_user_data(pContext))
    If zFormat = 0 Then Return

    Dim currentTime As sqlite3_int64 = sqlite3StmtCurrentTime(pContext)
    If currentTime <= 0 Then Return

    Dim epochSeconds As time_t = Cast(time_t, _
        (currentTime \ 1000) - (DATE_UNIX_EPOCH_OFFSET \ 1000))
    Dim tmValue As tm = Type<tm>(0)
    Dim pLocalTime As tm Ptr
    Dim pMutex As Any Ptr = sqlite3_mutex_alloc(SQLITE_MUTEX_STATIC_MAIN)

    ' gmtime returns storage shared by the C runtime. SQLite's static main
    ' mutex protects the copy on CRTs without gmtime_r.
    sqlite3_mutex_enter(pMutex)
    pLocalTime = gmtime(@epochSeconds)
    If pLocalTime <> 0 Then tmValue = *pLocalTime
    sqlite3_mutex_leave(pMutex)
    If pLocalTime = 0 Then Return

    Dim zBuffer As ZString * 20 = ""
    strftime(@zBuffer, 20, CPtr(ZString Ptr, zFormat), @tmValue)
    sqlite3_result_text(pContext, @zBuffer, -1, CPtr(Any Ptr, -1))
End Sub
#endif

#ifndef SQLITE_OMIT_DATETIME_FUNCS
#ifdef SQLITE_DEBUG
Private Sub datedebugFunc CDecl Alias "datedebugFunc" ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)
    If pContext = 0 OrElse argumentCount < 0 Then Return
    If argumentCount > 0 AndAlso pArguments = 0 Then Return

    Dim value As SqliteDateTime = Type<SqliteDateTime>(0)
    If isDate(pContext, argumentCount, pArguments, @value) <> 0 Then Return

    Dim zJson As ZString Ptr = sqlite3_mprintf( _
        StrPtr("{iJD:%lld,Y:%d,M:%d,D:%d,h:%d,m:%d,tz:%d,s:%.3f,validJD:%d,validYMD:%d,validHMS:%d,nFloor:%d,rawS:%d,isError:%d,useSubsec:%d,isUtc:%d,isLocal:%d}"), _
        value.iJD, value.Y, value.month, value.D, value.h, value.minute, value.tz, _
        value.s, Cast(SQLITE_C_INT, value.validJD), _
        Cast(SQLITE_C_INT, value.validYMD), Cast(SQLITE_C_INT, value.validHMS), _
        Cast(SQLITE_C_INT, value.nFloor), Cast(SQLITE_C_INT, value.rawS), _
        Cast(SQLITE_C_INT, value.isError), Cast(SQLITE_C_INT, value.useSubsec), _
        Cast(SQLITE_C_INT, value.isUtc), Cast(SQLITE_C_INT, value.isLocal))
    sqlite3_result_text(pContext, zJson, -1, _
        CPtr(Any Ptr, ProcPtr(sqlite3_free)))
End Sub
#endif
#endif

Sub sqlite3RegisterDateTimeFunctions CDecl Alias "sqlite3RegisterDateTimeFunctions" ()
    If dateFunctionsRegistered <> 0 Then Return
    Dim definitionCount As SQLITE_C_INT = 0
#ifndef SQLITE_OMIT_DATETIME_FUNCS
    With dateFunctionDefinitions(0)
        .nArg = -1
        .funcFlags = PURE_DATE_FLAGS
        .xSFunc = @juliandayFunc
        .zName = StrPtr("julianday")
    End With
    With dateFunctionDefinitions(1)
        .nArg = -1
        .funcFlags = PURE_DATE_FLAGS
        .xSFunc = @unixepochFunc
        .zName = StrPtr("unixepoch")
    End With
    With dateFunctionDefinitions(2)
        .nArg = -1
        .funcFlags = PURE_DATE_FLAGS
        .xSFunc = @dateFunc
        .zName = StrPtr("date")
    End With
    With dateFunctionDefinitions(3)
        .nArg = -1
        .funcFlags = PURE_DATE_FLAGS
        .xSFunc = @timeFunc
        .zName = StrPtr("time")
    End With
    With dateFunctionDefinitions(4)
        .nArg = -1
        .funcFlags = PURE_DATE_FLAGS
        .xSFunc = @datetimeFunc
        .zName = StrPtr("datetime")
    End With
    With dateFunctionDefinitions(5)
        .nArg = 0
        .funcFlags = DATE_BUILTIN_FLAGS
        .xSFunc = @sqlite3CurrentTimeCallback
        .zName = StrPtr("current_time")
    End With
    With dateFunctionDefinitions(6)
        .nArg = 0
        .funcFlags = DATE_BUILTIN_FLAGS
        .xSFunc = @sqlite3CurrentDateCallback
        .zName = StrPtr("current_date")
    End With
    With dateFunctionDefinitions(7)
        .nArg = 0
        .funcFlags = DATE_BUILTIN_FLAGS
        .xSFunc = @sqlite3CurrentTimestampCallback
        .zName = StrPtr("current_timestamp")
    End With
    With dateFunctionDefinitions(8)
        .nArg = -1
        .funcFlags = PURE_DATE_FLAGS
        .xSFunc = @strftimeFunc
        .zName = StrPtr("strftime")
    End With
    With dateFunctionDefinitions(9)
        .nArg = 2
        .funcFlags = PURE_DATE_FLAGS
        .xSFunc = @timediffFunc
        .zName = StrPtr("timediff")
    End With
#ifdef SQLITE_DEBUG
    With dateFunctionDefinitions(10)
        .nArg = -1
        .funcFlags = PURE_DATE_FLAGS
        .xSFunc = @datedebugFunc
        .zName = StrPtr("datedebug")
    End With
    definitionCount = 11
#else
    definitionCount = 10
#endif
    sqlite3InsertBuiltinFuncs(@dateFunctionDefinitions(0), _
                              definitionCount)
#else
    With dateFunctionDefinitions(0)
        .nArg = 0
        .funcFlags = DATE_BUILTIN_FLAGS
        .pUserData = CPtr(Any Ptr, StrPtr("%H:%M:%S"))
        .xSFunc = @currentTimeFunc
        .zName = StrPtr("current_time")
    End With
    With dateFunctionDefinitions(1)
        .nArg = 0
        .funcFlags = DATE_BUILTIN_FLAGS
        .pUserData = CPtr(Any Ptr, StrPtr("%Y-%m-%d"))
        .xSFunc = @currentTimeFunc
        .zName = StrPtr("current_date")
    End With
    With dateFunctionDefinitions(2)
        .nArg = 0
        .funcFlags = DATE_BUILTIN_FLAGS
        .pUserData = CPtr(Any Ptr, StrPtr("%Y-%m-%d %H:%M:%S"))
        .xSFunc = @currentTimeFunc
        .zName = StrPtr("current_timestamp")
    End With
    sqlite3InsertBuiltinFuncs(@dateFunctionDefinitions(0), 3)
#endif
    dateFunctionsRegistered = 1
End Sub

/' ------------------------------------------------------------------------- '/
/' Legacy current-time callback entry points                                '/
/' ------------------------------------------------------------------------- '/

Private Sub ctimeFunc CDecl Alias "ctimeFunc" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteVdbeMem Ptr Ptr)
    ' C unused-parameter annotation
    timeFunc(arg0, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL))
End Sub

Private Sub cdateFunc CDecl Alias "cdateFunc" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteVdbeMem Ptr Ptr)
    ' C unused-parameter annotation
    dateFunc(arg0, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL))
End Sub

Private Sub ctimestampFunc CDecl Alias "ctimestampFunc" (ByVal arg0 As SqliteResultContext Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SqliteVdbeMem Ptr Ptr)
    ' C unused-parameter annotation
    datetimeFunc(arg0, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL))
End Sub

/' end of sqlite3_date_sqlfunc.bas '/
