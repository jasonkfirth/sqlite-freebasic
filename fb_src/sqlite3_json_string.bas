/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_string.bas

    Purpose:

        Implement SQLite JSON's small-buffer string builder.

    Responsibilities:

        - Initialize and release the embedded or reference-counted output buffer.
        - Grow the buffer within SQLite's allocation limit.
        - Append bytes, characters, and separators while retaining error state.
        - Report allocation and nesting errors through the SQL function context.

    This file intentionally does NOT contain:

        - JSON grammar, JSONB parsing, SQL function callbacks, or output encoding.
'/ 

#lang "fb"
#include once "sqlite3_json_string.bi"
#include once "sqlite3_constants.bi"

Extern "C"
    Declare Function jsonSystemMemcpy CDecl Alias "memcpy" ( _
        ByVal pDestination As Any Ptr, _
        ByVal pSource As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
End Extern

Declare Function sqlite3RCStrNew CDecl Alias "sqlite3RCStrNew" (ByVal nByte As sqlite3_uint64) As ZString Ptr
Declare Function sqlite3RCStrResize CDecl Alias "sqlite3RCStrResize" (ByVal zData As ZString Ptr, ByVal nByte As sqlite3_uint64) As ZString Ptr
Declare Sub sqlite3RCStrUnref CDecl Alias "sqlite3RCStrUnref" (ByVal zData As Any Ptr)
Declare Sub sqlite3_result_error_nomem CDecl Alias "sqlite3_result_error_nomem" (ByVal pContext As Any Ptr)
Declare Sub sqlite3_result_error CDecl Alias "sqlite3_result_error" (ByVal pContext As Any Ptr, ByVal zError As Const ZString Ptr, ByVal nByte As SQLITE_C_INT)

/' ------------------------------------------------------------------------- '/
/' JsonString lifecycle and result errors '/
/' ------------------------------------------------------------------------- '/

Sub jsonStringZero CDecl Alias "jsonStringZero" ( _
    ByVal p As JsonString Ptr _
) Export
    If p = 0 Then Exit Sub
    ' Start in the structure's inline storage; heap allocation is deferred.
    p->zBuf = CPtr(ZString Ptr, @p->zSpace(0))
    p->nAlloc = SizeOf(p->zSpace)
    p->nUsed = 0
    p->bStatic = 1
End Sub

Sub jsonStringInit CDecl Alias "jsonStringInit" ( _
    ByVal p As JsonString Ptr, _
    ByVal pContext As Any Ptr _
) Export
    If p = 0 Then Exit Sub
    p->pCtx = pContext
    p->eErr = 0
    jsonStringZero(p)
End Sub

Sub jsonStringReset CDecl Alias "jsonStringReset" ( _
    ByVal p As JsonString Ptr _
) Export
    If p = 0 Then Exit Sub
    If p->bStatic = 0 AndAlso p->zBuf <> 0 Then sqlite3RCStrUnref(p->zBuf)
    jsonStringZero(p)
End Sub

Sub jsonStringOom CDecl Alias "jsonStringOom" ( _
    ByVal p As JsonString Ptr _
) Export
    If p = 0 Then Exit Sub
    p->eErr = p->eErr Or JSTRING_OOM
    If p->pCtx <> 0 Then sqlite3_result_error_nomem(p->pCtx)
    jsonStringReset(p)
End Sub

Sub jsonStringTooDeep CDecl Alias "jsonStringTooDeep" ( _
    ByVal p As JsonString Ptr _
) Export
    If p = 0 Then Exit Sub
    p->eErr = p->eErr Or JSTRING_TOODEEP
    If p->pCtx <> 0 Then _
        sqlite3_result_error(p->pCtx, StrPtr("JSON nested too deep"), -1)
    jsonStringReset(p)
End Sub

/' ------------------------------------------------------------------------- '/
/' Bounded buffer growth '/
/' ------------------------------------------------------------------------- '/

Private Sub jsonStringGrowFailure(ByVal p As JsonString Ptr)
    If p->bStatic <> 0 Then
        jsonStringOom(p)
    Else
        p->eErr = p->eErr Or JSTRING_OOM
        If p->zBuf <> 0 Then sqlite3RCStrUnref(p->zBuf)
        jsonStringZero(p)
    End If
End Sub

Private Function jsonStringEnsureCapacity( _
    ByVal p As JsonString Ptr, _
    ByVal nAdditional As sqlite3_uint64 _
) As SQLITE_C_INT
    If p = 0 OrElse p->zBuf = 0 Then Return SQLITE_MISUSE
    Dim maxAllocation As sqlite3_uint64 = CULngInt(SQLITE_MAX_ALLOCATION_SIZE)
    If nAdditional >= maxAllocation OrElse _
       p->nUsed > maxAllocation - nAdditional Then
        jsonStringOom(p)
        Return SQLITE_NOMEM
    End If
    If p->nUsed >= p->nAlloc OrElse _
       nAdditional >= p->nAlloc - p->nUsed Then
        If nAdditional > &HFFFFFFFFULL Then
            jsonStringOom(p)
            Return SQLITE_NOMEM
        End If
        Return jsonStringGrow(p, CUInt(nAdditional))
    End If
    Return SQLITE_OK
End Function

Function jsonStringGrow CDecl Alias "jsonStringGrow" ( _
    ByVal p As JsonString Ptr, _
    ByVal nByte As u32 _
) As SQLITE_C_INT Export
    If p = 0 Then Return SQLITE_MISUSE
    If nByte = 0 Then Return SQLITE_OK
    If p->bStatic <> 0 AndAlso p->eErr <> 0 Then Return 1
    If p->zBuf = 0 OrElse p->nUsed > p->nAlloc Then Return SQLITE_CORRUPT

    Dim maxAllocation As sqlite3_uint64 = CULngInt(SQLITE_MAX_ALLOCATION_SIZE)
    Dim currentAllocation As sqlite3_uint64 = p->nAlloc
    Dim requestedBytes As sqlite3_uint64 = CULngInt(nByte)
    Dim nTotal As sqlite3_uint64
    Dim allocationTooLarge As SQLITE_C_INT = 0

    If requestedBytes >= maxAllocation Then
        jsonStringGrowFailure(p)
        Return SQLITE_NOMEM
    End If

    If requestedBytes < currentAllocation Then
        If currentAllocation > maxAllocation \ 2 Then
            allocationTooLarge = 1
        Else
            nTotal = currentAllocation * 2
        End If
    Else
        If currentAllocation > maxAllocation - requestedBytes OrElse _
           currentAllocation + requestedBytes > maxAllocation - 10 Then
            allocationTooLarge = 1
        Else
            nTotal = currentAllocation + requestedBytes + 10
        End If
    End If

    If allocationTooLarge <> 0 OrElse _
       p->nUsed > maxAllocation - requestedBytes - 1 OrElse _
       nTotal <= p->nUsed + requestedBytes OrElse nTotal > maxAllocation Then
        jsonStringGrowFailure(p)
        Return SQLITE_NOMEM
    End If

    If p->bStatic <> 0 Then
        Dim zNew As ZString Ptr = sqlite3RCStrNew(nTotal)
        If zNew = 0 Then
            jsonStringOom(p)
            Return SQLITE_NOMEM
        End If
        If p->nUsed > 0 Then _
            jsonSystemMemcpy(zNew, p->zBuf, CULngInt(p->nUsed))
        p->zBuf = zNew
        p->bStatic = 0
    Else
        Dim zNew As ZString Ptr = sqlite3RCStrResize(p->zBuf, nTotal)
        If zNew = 0 Then
            ' RCStrResize releases the old buffer on allocation failure.
            p->zBuf = 0
            p->eErr = p->eErr Or JSTRING_OOM
            jsonStringZero(p)
            Return SQLITE_NOMEM
        End If
        p->zBuf = zNew
    End If
    p->nAlloc = nTotal
    Return SQLITE_OK
End Function

/' ------------------------------------------------------------------------- '/
/' Byte and character append operations '/
/' ------------------------------------------------------------------------- '/

Sub jsonStringExpandAndAppend CDecl Alias "jsonStringExpandAndAppend" ( _
    ByVal p As JsonString Ptr, _
    ByVal zInput As Const UByte Ptr, _
    ByVal nByte As u32 _
) Export
    If p = 0 OrElse zInput = 0 OrElse nByte = 0 Then Exit Sub
    If jsonStringGrow(p, nByte) <> SQLITE_OK Then Exit Sub
    jsonSystemMemcpy(CPtr(UByte Ptr, p->zBuf) + p->nUsed, zInput, nByte)
    p->nUsed += CULngInt(nByte)
End Sub

Sub jsonAppendRaw CDecl Alias "jsonAppendRaw" ( _
    ByVal p As JsonString Ptr, _
    ByVal zInput As Const UByte Ptr, _
    ByVal nByte As u32 _
) Export
    If p = 0 OrElse nByte = 0 OrElse zInput = 0 OrElse p->zBuf = 0 Then Exit Sub
    If p->nUsed >= p->nAlloc OrElse CULngInt(nByte) >= p->nAlloc - p->nUsed Then
        jsonStringExpandAndAppend(p, zInput, nByte)
    Else
        jsonSystemMemcpy(CPtr(UByte Ptr, p->zBuf) + p->nUsed, zInput, nByte)
        p->nUsed += CULngInt(nByte)
    End If
End Sub

Sub jsonAppendRawNZ CDecl Alias "jsonAppendRawNZ" ( _
    ByVal p As JsonString Ptr, _
    ByVal zInput As Const UByte Ptr, _
    ByVal nByte As u32 _
) Export
    If p = 0 OrElse nByte = 0 OrElse zInput = 0 Then Exit Sub
    jsonAppendRaw(p, zInput, nByte)
End Sub

Sub jsonAppendCharExpand CDecl Alias "jsonAppendCharExpand" ( _
    ByVal p As JsonString Ptr, _
    ByVal character As Byte _
) Export
    If p = 0 OrElse jsonStringGrow(p, 1) <> SQLITE_OK Then Exit Sub
    CPtr(UByte Ptr, p->zBuf)[p->nUsed] = CByte(character)
    p->nUsed += 1
End Sub

Sub jsonAppendChar CDecl Alias "jsonAppendChar" ( _
    ByVal p As JsonString Ptr, _
    ByVal character As Byte _
) Export
    If p = 0 OrElse p->zBuf = 0 Then Exit Sub
    If p->nUsed >= p->nAlloc Then
        jsonAppendCharExpand(p, character)
    Else
        CPtr(UByte Ptr, p->zBuf)[p->nUsed] = CByte(character)
        p->nUsed += 1
    End If
End Sub

Sub jsonStringTrimOneChar CDecl Alias "jsonStringTrimOneChar" ( _
    ByVal p As JsonString Ptr _
) Export
    If p <> 0 AndAlso p->eErr = 0 AndAlso p->nUsed > 0 Then p->nUsed -= 1
End Sub

Function jsonStringTerminate CDecl Alias "jsonStringTerminate" ( _
    ByVal p As JsonString Ptr _
) As SQLITE_C_INT Export
    If p = 0 Then Return 0
    jsonAppendChar(p, 0)
    jsonStringTrimOneChar(p)
    Return CInt(p->eErr = 0)
End Function

Sub jsonAppendSeparator CDecl Alias "jsonAppendSeparator" ( _
    ByVal p As JsonString Ptr _
) Export
    If p = 0 OrElse p->nUsed = 0 OrElse p->zBuf = 0 Then Exit Sub
    Dim lastByte As UByte = CPtr(UByte Ptr, p->zBuf)[p->nUsed - 1]
    If lastByte = Asc("[") OrElse lastByte = Asc("{") Then Exit Sub
    jsonAppendChar(p, Asc(","))
End Sub

/' ------------------------------------------------------------------------- '/
/' JSON quoting and control-byte escapes '/
/' ------------------------------------------------------------------------- '/

Sub jsonAppendControlChar CDecl Alias "jsonAppendControlChar" ( _
    ByVal p As JsonString Ptr, _
    ByVal character As u8 _
) Export
    If p = 0 OrElse character >= 32 Then Exit Sub
    If jsonStringEnsureCapacity(p, 7) <> SQLITE_OK Then Exit Sub

    ' ASCII control bytes 8, 9, 10, 12, and 13 have short JSON escapes.
    Dim shortEscape As UByte = 0
    Select Case character
    Case 8
        shortEscape = Asc("b")
    Case 9
        shortEscape = Asc("t")
    Case 10
        shortEscape = Asc("n")
    Case 12
        shortEscape = Asc("f")
    Case 13
        shortEscape = Asc("r")
    End Select

    Dim pOutput As UByte Ptr = CPtr(UByte Ptr, p->zBuf)
    pOutput[p->nUsed] = Asc(Chr(92))
    If shortEscape <> 0 Then
        pOutput[p->nUsed + 1] = shortEscape
        p->nUsed += 2
    Else
        Const hexDigits As String = "0123456789abcdef"
        pOutput[p->nUsed + 1] = Asc("u")
        pOutput[p->nUsed + 2] = Asc("0")
        pOutput[p->nUsed + 3] = Asc("0")
        pOutput[p->nUsed + 4] = CByte(Asc(hexDigits, (character Shr 4) + 1))
        pOutput[p->nUsed + 5] = CByte(Asc(hexDigits, (character And &HF) + 1))
        p->nUsed += 6
    End If
End Sub

Private Function jsonByteCanPassThrough(ByVal value As UByte) As SQLITE_C_INT
    ' JSON text permits UTF-8 bytes except controls below 0x20, quotes, and backslashes.
    If value < 32 OrElse value = Asc(Chr(34)) OrElse value = Asc(Chr(92)) Then Return 0
    Return 1
End Function

Sub jsonAppendString CDecl Alias "jsonAppendString" ( _
    ByVal p As JsonString Ptr, _
    ByVal zInput As Const UByte Ptr, _
    ByVal nByte As u32 _
) Export
    If p = 0 OrElse zInput = 0 Then Exit Sub
    ' Two extra bytes reserve the opening and closing JSON quotes.
    If jsonStringEnsureCapacity(p, CULngInt(nByte) + 2) <> SQLITE_OK Then Exit Sub

    jsonAppendChar(p, Asc(Chr(34)))
    Dim runStart As u32 = 0
    Dim index As u32 = 0
    While index < nByte
        Dim character As UByte = zInput[index]
        If jsonByteCanPassThrough(character) <> 0 Then
            index += 1
            Continue While
        End If

        If index > runStart Then
            jsonAppendRawNZ(p, zInput + runStart, index - runStart)
        End If

        Dim remaining As sqlite3_uint64 = CULngInt(nByte - index)
        If character = Asc(Chr(34)) OrElse character = Asc(Chr(92)) Then
            If jsonStringEnsureCapacity(p, remaining + 3) <> SQLITE_OK Then Exit Sub
            jsonAppendChar(p, Asc(Chr(92)))
            jsonAppendChar(p, CByte(character))
        Else
            If jsonStringEnsureCapacity(p, remaining + 7) <> SQLITE_OK Then Exit Sub
            jsonAppendControlChar(p, character)
        End If
        index += 1
        runStart = index
    Wend

    If index > runStart Then jsonAppendRawNZ(p, zInput + runStart, index - runStart)
    jsonAppendChar(p, Asc(Chr(34)))
End Sub

/' end of sqlite3_json_string.bas '/
