/'
    Project: SQLite FreeBASIC port

    File: sqlite3_straccum.bas

    Purpose:

        Port SQLite's growable string accumulator operations from src/printf.c.

    Responsibilities:

        - Grow bounded buffers through SQLite's allocator.
        - Append byte spans and repeated characters.
        - Finish, reset, truncate, and inspect sqlite3_str values.
        - Preserve the allocation-failure sentinel behavior.

    This file intentionally does NOT contain:

        - Format conversion, variadic APIs, or SQL expression rendering.
'/

#lang "fb"
#include once "sqlite3_straccum.bi"
#include once "sqlite3_constants.bi"

Extern "C"
    Declare Function sqlite3SystemMemcpy CDecl Alias "memcpy" ( _
        ByVal pTarget As Any Ptr, _
        ByVal pSource As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
End Extern

Declare Function sqlite3_malloc64 CDecl Alias "sqlite3_malloc64" (ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" (ByVal z As Const ZString Ptr) As SQLITE_C_INT
Declare Function sqlite3ErrorToParser CDecl Alias "sqlite3ErrorToParser" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal errorCode As SQLITE_C_INT _
) As SQLITE_C_INT

Private Const SQLITE_STRACCUM_MAX_LENGTH As ULongInt = &H7FFFFFFF

Dim Shared As Const sqlite3_str sqlite3OomStr = _
    Type<sqlite3_str>(0, 0, 0, 0, 0, SQLITE_NOMEM, 0, 0, 0)

Private Function sqlite3StrAccumIsMalloced(ByVal pAccum As sqlite3_str Ptr) As Long
    If pAccum = 0 Then Return 0
    Return IIf((pAccum->printfFlags And SQLITE_PRINTF_MALLOCED) <> 0, -1, 0)
End Function

Sub sqlite3StrAccumInit CDecl Alias "sqlite3StrAccumInit" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal db As sqlite3 Ptr, _
    ByVal zBase As UByte Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal maxByte As SQLITE_C_INT _
) Export

    If pAccum = 0 Then Return
    pAccum->zText = zBase
    pAccum->db = db
    pAccum->nAlloc = IIf(nByte > 0, CUInt(nByte), 0)
    pAccum->mxAlloc = IIf(maxByte > 0, CUInt(maxByte), 0)
    pAccum->nChar = 0
    pAccum->accError = 0
    pAccum->printfFlags = 0
    pAccum->pPrintfScratch = 0
    pAccum->nPrintfScratch = 0
End Sub

Sub sqlite3StrAccumSetError CDecl Alias "sqlite3StrAccumSetError" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal errorCode As u8 _
) Export

    If pAccum = 0 OrElse (errorCode <> SQLITE_NOMEM AndAlso errorCode <> SQLITE_TOOBIG) Then Return
    pAccum->accError = errorCode
    If pAccum->mxAlloc <> 0 Then sqlite3_str_reset(pAccum)
    If errorCode = SQLITE_TOOBIG AndAlso pAccum->db <> 0 Then
        sqlite3ErrorToParser(pAccum->db, SQLITE_TOOBIG)
    End If
End Sub

Function sqlite3StrAccumEnlarge CDecl Alias "sqlite3StrAccumEnlarge" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal nByte As sqlite3_int64 _
) As SQLITE_C_INT Export

    If pAccum = 0 OrElse nByte < 0 Then Return 0
    If pAccum->accError <> 0 Then Return 0

    Dim needed As ULongInt = CULngInt(pAccum->nChar) + CULngInt(nByte) + 1
    If needed <= pAccum->nAlloc Then Return CLng(pAccum->nAlloc - pAccum->nChar - 1)

    If pAccum->mxAlloc = 0 Then
        sqlite3StrAccumSetError(pAccum, SQLITE_TOOBIG)
        If pAccum->nAlloc <= pAccum->nChar Then Return 0
        Return CLng(pAccum->nAlloc - pAccum->nChar - 1)
    End If

    If needed > SQLITE_STRACCUM_MAX_LENGTH Then
        sqlite3_str_reset(pAccum)
        sqlite3StrAccumSetError(pAccum, SQLITE_TOOBIG)
        Return 0
    End If

    Dim newSize As ULongInt = needed
    If newSize + pAccum->nChar <= pAccum->mxAlloc Then newSize += pAccum->nChar
    If newSize > pAccum->mxAlloc Then
        sqlite3_str_reset(pAccum)
        sqlite3StrAccumSetError(pAccum, SQLITE_TOOBIG)
        Return 0
    End If

    Dim pOld As Any Ptr = 0
    If sqlite3StrAccumIsMalloced(pAccum) <> 0 Then pOld = pAccum->zText
    Dim pNew As Any Ptr = sqlite3DbRealloc(pAccum->db, pOld, newSize)
    If pNew = 0 Then
        sqlite3_str_reset(pAccum)
        sqlite3StrAccumSetError(pAccum, SQLITE_NOMEM)
        Return 0
    End If

    If sqlite3StrAccumIsMalloced(pAccum) = 0 AndAlso pAccum->nChar > 0 Then
        If pAccum->zText = 0 Then
            sqlite3DbFree(pAccum->db, pNew)
            sqlite3StrAccumSetError(pAccum, SQLITE_MISUSE)
            Return 0
        End If
        sqlite3SystemMemcpy(pNew, pAccum->zText, pAccum->nChar)
    End If

    pAccum->zText = CPtr(UByte Ptr, pNew)
    pAccum->nAlloc = CUInt(sqlite3DbMallocSize(pAccum->db, pNew))
    pAccum->printfFlags = pAccum->printfFlags Or SQLITE_PRINTF_MALLOCED
    Return CLng(nByte)
End Function

Function sqlite3StrAccumEnlargeIfNeeded CDecl Alias "sqlite3StrAccumEnlargeIfNeeded" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal nByte As sqlite3_int64 _
) As SQLITE_C_INT Export

    If pAccum = 0 Then Return SQLITE_MISUSE
    If nByte < 0 Then Return SQLITE_MISUSE
    If CULngInt(nByte) + pAccum->nChar + 1 > pAccum->nAlloc Then
        sqlite3StrAccumEnlarge(pAccum, nByte)
    End If
    Return pAccum->accError
End Function

Private Sub enlargeAndAppend CDecl Alias "enlargeAndAppend" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zText As Const UByte Ptr, _
    ByVal nByte As SQLITE_C_INT _
)
    If pAccum = 0 OrElse nByte <= 0 OrElse pAccum->accError <> 0 Then Return
    Dim nCopy As SQLITE_C_INT = sqlite3StrAccumEnlarge(pAccum, nByte)
    If nCopy <= 0 Then Return
    If zText = 0 Then
        sqlite3StrAccumSetError(pAccum, SQLITE_MISUSE)
        Return
    End If
    If pAccum->zText = 0 Then
        sqlite3StrAccumSetError(pAccum, SQLITE_MISUSE)
        Return
    End If
    sqlite3SystemMemcpy(pAccum->zText + pAccum->nChar, zText, CULng(nCopy))
    pAccum->nChar = CUInt(CULngInt(pAccum->nChar) + CULngInt(nCopy))
End Sub

Sub sqlite3_str_appendchar CDecl Alias "sqlite3_str_appendchar" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal count As SQLITE_C_INT, _
    ByVal character As Byte _
) Export

    If pAccum = 0 OrElse count <= 0 OrElse pAccum->accError <> 0 Then Return
    Dim nCopy As ULongInt = CULng(count)
    If CULngInt(pAccum->nChar) + nCopy + 1 > pAccum->nAlloc Then
        Dim available As SQLITE_C_INT = sqlite3StrAccumEnlarge(pAccum, count)
        If available <= 0 Then Return
        nCopy = CULng(available)
    End If
    If pAccum->zText = 0 Then
        sqlite3StrAccumSetError(pAccum, SQLITE_MISUSE)
        Return
    End If
    For i As ULongInt = 0 To nCopy - 1
        pAccum->zText[pAccum->nChar + i] = CByte(character)
    Next
    pAccum->nChar = CUInt(CULngInt(pAccum->nChar) + nCopy)
End Sub

Sub sqlite3_str_append CDecl Alias "sqlite3_str_append" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zText As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT _
) Export

    If pAccum = 0 OrElse nByte < 0 OrElse pAccum->accError <> 0 Then Return
    If nByte = 0 Then Return
    If zText = 0 Then
        sqlite3StrAccumSetError(pAccum, SQLITE_MISUSE)
        Return
    End If
    If CULngInt(pAccum->nChar) + CULngInt(nByte) >= pAccum->nAlloc Then
        enlargeAndAppend(pAccum, CPtr(Const UByte Ptr, zText), nByte)
    ElseIf pAccum->zText <> 0 Then
        sqlite3SystemMemcpy(pAccum->zText + pAccum->nChar, zText, CULng(nByte))
        pAccum->nChar += CUInt(nByte)
    Else
        sqlite3StrAccumSetError(pAccum, SQLITE_MISUSE)
    End If
End Sub

Sub sqlite3_str_appendall CDecl Alias "sqlite3_str_appendall" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal zText As Const ZString Ptr _
) Export

    If zText = 0 Then Return
    Dim nByte As SQLITE_C_INT = sqlite3Strlen30(zText)
    sqlite3_str_append(pAccum, zText, nByte)
End Sub

Private Function strAccumFinishRealloc CDecl Alias "strAccumFinishRealloc" ( _
    ByVal pAccum As sqlite3_str Ptr _
) As ZString Ptr
    If pAccum = 0 OrElse pAccum->mxAlloc = 0 OrElse _
       sqlite3StrAccumIsMalloced(pAccum) <> 0 Then Return 0

    Dim nByte As ULongInt = CULngInt(pAccum->nChar) + 1
    Dim pText As Any Ptr = sqlite3DbMallocRaw(pAccum->db, nByte)
    If pText = 0 Then
        sqlite3StrAccumSetError(pAccum, SQLITE_NOMEM)
    ElseIf pAccum->zText = 0 Then
        sqlite3DbFree(pAccum->db, pText)
        pText = 0
    Else
        sqlite3SystemMemcpy(pText, pAccum->zText, nByte)
        pAccum->printfFlags = pAccum->printfFlags Or SQLITE_PRINTF_MALLOCED
    End If
    pAccum->zText = CPtr(UByte Ptr, pText)
    Return CPtr(ZString Ptr, pText)
End Function

Function sqlite3StrAccumFinish CDecl Alias "sqlite3StrAccumFinish" ( _
    ByVal pAccum As sqlite3_str Ptr _
) As ZString Ptr Export

    If pAccum = 0 OrElse pAccum->zText = 0 Then Return 0
    pAccum->zText[pAccum->nChar] = 0
    If pAccum->mxAlloc <> 0 AndAlso sqlite3StrAccumIsMalloced(pAccum) = 0 Then
        Return strAccumFinishRealloc(pAccum)
    End If
    Return CPtr(ZString Ptr, pAccum->zText)
End Function

Function sqlite3_str_new CDecl Alias "sqlite3_str_new" ( _
    ByVal db As sqlite3 Ptr _
) As sqlite3_str Ptr Export

    Dim pAccum As sqlite3_str Ptr = CPtr(sqlite3_str Ptr, sqlite3_malloc64(SizeOf(sqlite3_str)))
    If pAccum = 0 Then Return CPtr(sqlite3_str Ptr, @sqlite3OomStr)
    Dim maxLength As SQLITE_C_INT = SQLITE_MAX_LENGTH
    If db <> 0 Then maxLength = db->lengthLimit
    sqlite3StrAccumInit(pAccum, 0, 0, 0, maxLength)
    Return pAccum
End Function

Function sqlite3_str_finish CDecl Alias "sqlite3_str_finish" ( _
    ByVal pAccum As sqlite3_str Ptr _
) As ZString Ptr Export

    If pAccum = 0 OrElse pAccum = @sqlite3OomStr Then Return 0
    Dim zResult As ZString Ptr = sqlite3StrAccumFinish(pAccum)
    sqlite3_free(pAccum)
    Return zResult
End Function

Sub sqlite3_str_reset CDecl Alias "sqlite3_str_reset" ( _
    ByVal pAccum As sqlite3_str Ptr _
) Export

    If pAccum = 0 OrElse pAccum = @sqlite3OomStr Then Return
    If sqlite3StrAccumIsMalloced(pAccum) <> 0 Then
        sqlite3DbFree(pAccum->db, pAccum->zText)
        pAccum->printfFlags = pAccum->printfFlags And Not SQLITE_PRINTF_MALLOCED
    End If
    pAccum->nAlloc = 0
    pAccum->nChar = 0
    pAccum->zText = 0
End Sub

Sub sqlite3_str_free CDecl Alias "sqlite3_str_free" ( _
    ByVal pAccum As sqlite3_str Ptr _
) Export

    If pAccum = 0 OrElse pAccum = @sqlite3OomStr Then Return
    sqlite3_str_reset(pAccum)
    sqlite3_free(pAccum)
End Sub

Function sqlite3_str_errcode CDecl Alias "sqlite3_str_errcode" ( _
    ByVal pAccum As sqlite3_str Ptr _
) As SQLITE_C_INT Export

    If pAccum = 0 Then Return SQLITE_NOMEM
    Return pAccum->accError
End Function

Function sqlite3_str_length CDecl Alias "sqlite3_str_length" ( _
    ByVal pAccum As sqlite3_str Ptr _
) As SQLITE_C_INT Export

    If pAccum = 0 Then Return 0
    Return CLng(pAccum->nChar)
End Function

Sub sqlite3_str_truncate CDecl Alias "sqlite3_str_truncate" ( _
    ByVal pAccum As sqlite3_str Ptr, _
    ByVal nByte As SQLITE_C_INT _
) Export

    If pAccum = 0 OrElse nByte < 0 OrElse CUInt(nByte) >= pAccum->nChar Then Return
    pAccum->nChar = CUInt(nByte)
    If pAccum->zText <> 0 Then pAccum->zText[pAccum->nChar] = 0
End Sub

Function sqlite3_str_value CDecl Alias "sqlite3_str_value" ( _
    ByVal pAccum As sqlite3_str Ptr _
) As ZString Ptr Export

    If pAccum = 0 OrElse pAccum->nChar = 0 OrElse pAccum->zText = 0 Then Return 0
    pAccum->zText[pAccum->nChar] = 0
    Return CPtr(ZString Ptr, pAccum->zText)
End Function

/' end of sqlite3_straccum.bas '/
