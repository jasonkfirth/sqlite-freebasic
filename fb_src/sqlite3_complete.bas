/'
    Project: SQLite FreeBASIC port

    File: sqlite3_complete.bas

    Purpose:

        Determine whether SQL input ends at a complete statement boundary.

    Responsibilities:

        - Port sqlite3_incomplete() and sqlite3_complete() from src/complete.c.
        - Scan native UTF-16 input for sqlite3_complete16().

    This file intentionally does NOT contain:

        - SQL grammar validation or statement execution.
        - Database initialization or value-object allocation.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"

/' ------------------------------------------------------------------------- '/
/' Input character helpers '/
/' ------------------------------------------------------------------------- '/

Private Function sqlite3CompleteReadChar( _
    ByVal z As Const UByte Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal isLittleEndian As SQLITE_C_INT _
) As SQLITE_C_INT

    If nByte = 1 Then
        Return z[0]
    End If

    If isLittleEndian Then
        Return CUInt(z[0]) Or (CUInt(z[1]) Shl 8)
    End If

    Return (CUInt(z[0]) Shl 8) Or CUInt(z[1])
End Function

Private Function sqlite3CompleteIsIdChar(ByVal c As SQLITE_C_INT) As SQLITE_C_INT
    If c > &H7F Then Return -1

    Select Case c
    Case &H24, &H30 To &H39, &H41 To &H5A, &H5F, &H61 To &H7A
        Return -1
    End Select

    Return 0
End Function

Private Function sqlite3CompleteLowerAscii(ByVal c As SQLITE_C_INT) As SQLITE_C_INT
    If c >= &H41 AndAlso c <= &H5A Then Return c + &H20
    Return c
End Function

Private Function sqlite3CompleteWordEquals( _
    ByVal z As Const UByte Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal isLittleEndian As SQLITE_C_INT, _
    ByVal zWord As Const UByte Ptr, _
    ByVal nWord As SQLITE_C_INT, _
    ByVal nId As LongInt _
) As SQLITE_C_INT

    Dim i As LongInt

    If nId <> nWord Then Return 0

    For i = 0 To nWord - 1
        If sqlite3CompleteLowerAscii( _
            sqlite3CompleteReadChar(z + (i * nByte), nByte, isLittleEndian) _
        ) <> zWord[i] Then
            Return 0
        End If
    Next

    Return 1
End Function

/' ------------------------------------------------------------------------- '/
/' Completeness state machine '/
/' ------------------------------------------------------------------------- '/

' These token IDs index the transition table below.
Private Const TK_SEMI As UByte = 0
Private Const TK_WS As UByte = 1
Private Const TK_OTHER As UByte = 2
Private Const TK_EXPLAIN As UByte = 3
Private Const TK_CREATE As UByte = 4
Private Const TK_TEMP As UByte = 5
Private Const TK_TRIGGER As UByte = 6
Private Const TK_END As UByte = 7

' These states follow the state numbering in src/complete.c.
Private Const ST_NOTHING As UByte = 0
Private Const ST_START As UByte = 1
Private Const ST_NORMAL As UByte = 2
Private Const ST_EXPLAIN As UByte = 3
Private Const ST_CREATE As UByte = 4
Private Const ST_TRIGGER As UByte = 5
Private Const ST_SEMI As UByte = 6
Private Const ST_END As UByte = 7

' The public incomplete-result format stores parenthesis depth in 32 bits.
Private Const COMPLETE_MAX_PAREN_COUNT As LongInt = 2147483647
Private Const COMPLETE_MIN_PAREN_COUNT As LongInt = -2147483647 - 1

/'
    The transition table handles CREATE TRIGGER specially. A trigger body
    ends with a semicolon, END, and another semicolon; ordinary SQL statements
    need only the final semicolon. Rows are states and columns are token IDs.
'/
Dim Shared As Const UByte sqlite3CompleteTransitions(0 To 63) = { _
    1, 0, 2, 3, 4, 2, 2, 2, _
    1, 1, 2, 3, 4, 2, 2, 2, _
    1, 2, 2, 2, 2, 2, 2, 2, _
    1, 3, 3, 2, 4, 2, 2, 2, _
    1, 4, 2, 2, 2, 4, 5, 2, _
    6, 5, 5, 5, 5, 5, 5, 5, _
    6, 6, 5, 5, 5, 5, 5, 7, _
    1, 7, 5, 5, 5, 5, 5, 5 _
}

' State-to-incomplete-reason mapping from src/complete.c.
Dim Shared As Const UByte sqlite3CompleteStateMap(0 To 7) = {0, 0, 1, 1, 1, 3, 2, 1}

' Keyword storage is fixed and immutable so scans do not allocate memory.
Dim Shared As Const ZString * 7 sqlite3CompleteWordCreate = "create"
Dim Shared As Const ZString * 8 sqlite3CompleteWordTrigger = "trigger"
Dim Shared As Const ZString * 5 sqlite3CompleteWordTemp = "temp"
Dim Shared As Const ZString * 10 sqlite3CompleteWordTemporary = "temporary"
Dim Shared As Const ZString * 4 sqlite3CompleteWordEnd = "end"
Dim Shared As Const ZString * 8 sqlite3CompleteWordExplain = "explain"

Private Function sqlite3IncompleteImpl( _
    ByVal zStart As Const UByte Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As LongInt

    Dim state As UByte = ST_NOTHING
    Dim token As UByte = TK_OTHER
    Dim pending As UByte = 0
    Dim nParen As LongInt = 0
    Dim isLittleEndian As SQLITE_C_INT = 1
    Dim endianMarker As UShort = 1
    Dim zSql As Const UByte Ptr = zStart
    Dim c As SQLITE_C_INT

    If zSql = 0 Then Return SQLITE_MISUSE

    If nByte = 2 Then
        If CPtr(UByte Ptr, @endianMarker)[0] = 1 Then
            isLittleEndian = 1
        Else
            isLittleEndian = 0
        End If
    End If

    Do While sqlite3CompleteReadChar(zSql, nByte, isLittleEndian) <> 0
        c = sqlite3CompleteReadChar(zSql, nByte, isLittleEndian)

        Select Case c
        Case Asc(";")
            token = TK_SEMI

        Case Asc(" "), 9, 10, 12, 13
            ' ASCII space, horizontal tab, line feed, form feed, and CR.
            token = TK_WS

        Case Asc("/")
            If sqlite3CompleteReadChar(zSql + nByte, nByte, isLittleEndian) <> Asc("*") Then
                token = TK_OTHER
            Else
                zSql += nByte * 2
                Do While sqlite3CompleteReadChar(zSql, nByte, isLittleEndian) <> 0 AndAlso _
                    (sqlite3CompleteReadChar(zSql, nByte, isLittleEndian) <> Asc("*") OrElse _
                     sqlite3CompleteReadChar(zSql + nByte, nByte, isLittleEndian) <> Asc("/"))
                    zSql += nByte
                Loop
                If sqlite3CompleteReadChar(zSql, nByte, isLittleEndian) = 0 Then
                    pending = Asc("/")
                    GoTo incomplete_finish
                End If
                zSql += nByte
                token = TK_WS
            End If

        Case Asc("-")
            If sqlite3CompleteReadChar(zSql + nByte, nByte, isLittleEndian) <> Asc("-") Then
                token = TK_OTHER
            Else
                Do While sqlite3CompleteReadChar(zSql, nByte, isLittleEndian) <> 0 AndAlso _
                    sqlite3CompleteReadChar(zSql, nByte, isLittleEndian) <> 10
                    zSql += nByte
                Loop
                If sqlite3CompleteReadChar(zSql, nByte, isLittleEndian) = 0 Then
                    pending = Asc("-")
                    GoTo incomplete_finish
                End If
                token = TK_WS
            End If

        Case Asc("[")
            zSql += nByte
            Do While sqlite3CompleteReadChar(zSql, nByte, isLittleEndian) <> 0 AndAlso _
                sqlite3CompleteReadChar(zSql, nByte, isLittleEndian) <> Asc("]")
                zSql += nByte
            Loop
            If sqlite3CompleteReadChar(zSql, nByte, isLittleEndian) = 0 Then
                pending = Asc("]")
                GoTo incomplete_finish
            End If
            token = TK_OTHER

        Case Asc("`"), Asc(""""), Asc("'")
            Dim quoteChar As SQLITE_C_INT = c
            zSql += nByte
            Do While sqlite3CompleteReadChar(zSql, nByte, isLittleEndian) <> 0 AndAlso _
                sqlite3CompleteReadChar(zSql, nByte, isLittleEndian) <> quoteChar
                zSql += nByte
            Loop
            If sqlite3CompleteReadChar(zSql, nByte, isLittleEndian) = 0 Then
                pending = CByte(quoteChar)
                GoTo incomplete_finish
            End If
            token = TK_OTHER

        Case Asc("(")
            nParen += 1
            token = TK_OTHER

        Case Asc(")")
            nParen -= 1
            token = TK_OTHER

        Case Else
            If sqlite3CompleteIsIdChar(c) Then
                Dim nId As LongInt = 1
                Dim zNext As Const UByte Ptr = zSql + nByte
                Do While sqlite3CompleteIsIdChar( _
                    sqlite3CompleteReadChar(zNext, nByte, isLittleEndian) _
                )
                    nId += 1
                    zNext += nByte
                Loop

                Select Case sqlite3CompleteLowerAscii(c)
                Case Asc("c")
                    If sqlite3CompleteWordEquals(zSql, nByte, isLittleEndian, _
                        CPtr(Const UByte Ptr, @sqlite3CompleteWordCreate), 6, nId) Then
                        token = TK_CREATE
                    Else
                        token = TK_OTHER
                    End If

                Case Asc("t")
                    If sqlite3CompleteWordEquals(zSql, nByte, isLittleEndian, _
                        CPtr(Const UByte Ptr, @sqlite3CompleteWordTrigger), 7, nId) Then
                        token = TK_TRIGGER
                    ElseIf sqlite3CompleteWordEquals(zSql, nByte, isLittleEndian, _
                        CPtr(Const UByte Ptr, @sqlite3CompleteWordTemp), 4, nId) OrElse _
                        sqlite3CompleteWordEquals(zSql, nByte, isLittleEndian, _
                        CPtr(Const UByte Ptr, @sqlite3CompleteWordTemporary), 9, nId) Then
                        token = TK_TEMP
                    Else
                        token = TK_OTHER
                    End If

                Case Asc("e")
                    If sqlite3CompleteWordEquals(zSql, nByte, isLittleEndian, _
                        CPtr(Const UByte Ptr, @sqlite3CompleteWordEnd), 3, nId) Then
                        token = TK_END
                    ElseIf sqlite3CompleteWordEquals(zSql, nByte, isLittleEndian, _
                        CPtr(Const UByte Ptr, @sqlite3CompleteWordExplain), 7, nId) Then
                        token = TK_EXPLAIN
                    Else
                        token = TK_OTHER
                    End If

                Case Else
                    token = TK_OTHER
                End Select

                zSql += (nId - 1) * nByte
            Else
                token = TK_OTHER
            End If
        End Select

        state = sqlite3CompleteTransitions(CLng(state) * 8 + token)
        zSql += nByte
    Loop

incomplete_finish:
    If state = ST_NOTHING AndAlso pending = 0 Then Return SQLITE_EMPTY
    If state = ST_START Then nParen = 0

    ' Clamp before packing the count to avoid a narrowing overflow.
    If nParen > COMPLETE_MAX_PAREN_COUNT Then nParen = COMPLETE_MAX_PAREN_COUNT
    If nParen < COMPLETE_MIN_PAREN_COUNT Then nParen = COMPLETE_MIN_PAREN_COUNT

    Dim result As ULongInt = CULngInt(CUInt(nParen)) Shl 32
    result = result Or (CULngInt(pending) Shl 16)
    result = result Or (CULngInt(sqlite3CompleteStateMap(state)) Shl 8)
    If state > ST_START OrElse pending <> 0 Then result = result Or 1

    Return Cast(LongInt, result)
End Function

Function sqlite3_incomplete CDecl Alias "sqlite3_incomplete" ( _
    ByVal zSql As Const UByte Ptr _
) As LongInt Export
    Return sqlite3IncompleteImpl(zSql, 1)
End Function

Function sqlite3_complete CDecl Alias "sqlite3_complete" ( _
    ByVal zSql As Const UByte Ptr _
) As SQLITE_C_INT Export
    If sqlite3IncompleteImpl(zSql, 1) = SQLITE_OK Then Return 1
    Return 0
End Function

Function sqlite3_complete16 CDecl Alias "sqlite3_complete16" ( _
    ByVal zSql As Const Any Ptr _
) As SQLITE_C_INT Export
    ' UTF-16 is scanned as native-endian code units without allocating a copy.
    If sqlite3IncompleteImpl(CPtr(Const UByte Ptr, zSql), 2) = SQLITE_OK Then Return 1
    Return 0
End Function

/' end of sqlite3_complete.bas '/
