/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_mem.bas

    Purpose:

        Port VDBE Mem lifecycle, scalar setters, and numeric value paths.

    Responsibilities:

        - Initialize value cells and release owned heap or destructor content.
        - Allocate standalone sqlite3_value cells and set their text content.
        - Store NULL, integer, real, zero-blob, and RowSet values.
        - Copy or borrow bounded record payload ranges from B-tree cursors.
        - Extract and convert numeric values using sqlite3Atoi64 and sqlite3AtoF.
        - Keep connection-owned allocations on the database allocator path.
        - Check debug Mem invariants and format Mem values for VDBE traces.

    This file intentionally does NOT contain:

        - The decimal parser implementation, affinity dispatch and text conversion, comparison, or aggregate finalization.
        - Full text/blob ownership and encoding conversion behavior.
'/

#lang "fb"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_btree.bi"
#include once "sqlite3_result.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_rowset.bi"
#include once "sqlite3_numeric.bi"
#include once "sqlite3_fp.bi"
#include once "sqlite3_straccum.bi"
#include once "sqlite3_debug_assert.bi"
#include once "sqlite3_vdbe_core.bi"

Extern "C"
    Declare Function sqlite3SystemMemcpy CDecl Alias "memcpy" ( _
        ByVal destination As Any Ptr, _
        ByVal source As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
    Declare Function sqlite3SystemMemset CDecl Alias "memset" ( _
        ByVal p As Any Ptr, _
        ByVal value As SQLITE_C_INT, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
    Declare Function sqlite3SystemMemmove CDecl Alias "memmove" ( _
        ByVal destination As Any Ptr, _
        ByVal source As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
    Declare Function sqlite3SystemStrlen CDecl Alias "strlen" ( _
        ByVal z As Const ZString Ptr _
    ) As SQLITE_SIZE_T
End Extern

#ifdef SQLITE_DEBUG
Extern "C"
    Declare Sub sqlite3VdbeMemDebugAppendf CDecl Alias "sqlite3_str_appendf" ( _
        ByVal pAccumulator As sqlite3_str Ptr, _
        ByVal zFormat As Const ZString Ptr, _
        ... _
    )
End Extern
Declare Sub sqlite3DebugPrintf CDecl Alias "sqlite3DebugPrintf" (ByVal zFormat As Const ZString Ptr, ...)
#endif

Dim Shared sqlite3EmptyPointerType As ZString * 1 = ""

Private Function sqlite3MemIsDynamic(ByVal pMem As SqliteVdbeMem Ptr) As Long
    If (pMem->flags And (MEM_DYN Or MEM_AGG)) <> 0 Then Return -1
    Return 0
End Function

Private Function sqlite3MemIsRowSet(ByVal pMem As SqliteVdbeMem Ptr) As Long
    If pMem = 0 OrElse (pMem->flags And (MEM_BLOB Or MEM_DYN)) <> (MEM_BLOB Or MEM_DYN) Then
        Return 0
    End If
    If pMem->xDel = @sqlite3RowSetDelete Then Return -1
    Return 0
End Function

Private Sub sqlite3MemSetTypeFlag( _
    ByVal pMem As SqliteVdbeMem Ptr, _
    ByVal valueType As UShort _
)
    pMem->flags = (pMem->flags And Not (MEM_TYPE_MASK Or MEM_ZERO)) Or valueType
End Sub

Function sqlite3RealToI64 CDecl Alias "sqlite3RealToI64" ( _
    ByVal value As Double _
) As sqlite3_int64 Export

    If value <> value Then Return 0
    If value < -9223372036854774784.0 Then Return -9223372036854775807 - 1
    If value > 9223372036854774784.0 Then Return 9223372036854775807
    ' C's real-to-integer cast truncates toward zero; CLngInt rounds, so use Fix first.
    Return CLngInt(Fix(value))
End Function

Function sqlite3RealSameAsInt CDecl Alias "sqlite3RealSameAsInt" ( _
    ByVal value As Double, _
    ByVal integerValue As sqlite3_int64 _
) As SQLITE_C_INT Export

    If value = 0.0 Then Return 1
    If integerValue < -2251799813685248 OrElse integerValue >= 2251799813685248 Then Return 0
    If value = CDbl(integerValue) Then Return 1
    Return 0
End Function

Function sqlite3VdbeIntValue CDecl Alias "sqlite3VdbeIntValue" ( _
    ByVal pArgument As Any Ptr _
) As sqlite3_int64 Export

    If pArgument = 0 Then Return 0
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If sqlite3MemIsRowSet(pMem) <> 0 Then Return 0
    If (pMem->flags And (MEM_INT Or MEM_INTREAL)) <> 0 Then Return pMem->u.i
    If (pMem->flags And MEM_REAL) <> 0 Then Return sqlite3RealToI64(pMem->u.r)
    If (pMem->flags And (MEM_STR Or MEM_BLOB)) <> 0 AndAlso pMem->z <> 0 Then
        Dim value As sqlite3_int64 = 0
        sqlite3Atoi64(pMem->z, @value, pMem->n, pMem->enc)
        Return value
    End If
    Return 0
End Function

Function sqlite3VdbeMemIntegerify CDecl Alias "sqlite3VdbeMemIntegerify" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return SQLITE_MISUSE
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If sqlite3MemIsRowSet(pMem) <> 0 OrElse (pMem->flags And MEM_AGG) <> 0 Then Return SQLITE_MISUSE
    pMem->u.i = sqlite3VdbeIntValue(pMem)
    sqlite3MemSetTypeFlag(pMem, MEM_INT)
    Return SQLITE_OK
End Function

Sub sqlite3VdbeIntegerAffinity CDecl Alias "sqlite3VdbeIntegerAffinity" ( _
    ByVal pArgument As Any Ptr _
) Export

    If pArgument = 0 Then Exit Sub
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If sqlite3MemIsRowSet(pMem) <> 0 Then Exit Sub
    If (pMem->flags And MEM_INTREAL) <> 0 Then
        sqlite3MemSetTypeFlag(pMem, MEM_INT)
    ElseIf (pMem->flags And MEM_REAL) <> 0 Then
        Dim value As sqlite3_int64 = sqlite3RealToI64(pMem->u.r)
        If pMem->u.r = CDbl(value) AndAlso _
           value <> (-9223372036854775807 - 1) AndAlso _
           value <> 9223372036854775807 Then
            pMem->u.i = value
            sqlite3MemSetTypeFlag(pMem, MEM_INT)
        End If
    End If
End Sub

Private Function sqlite3MemRealValueRCSlowPath( _
    ByVal pMem As SqliteVdbeMem Ptr, _
    ByVal pValue As Double Ptr _
) As SQLITE_C_INT
    *pValue = 0.0
    If pMem->enc = SQLITE_UTF8 Then
        If pMem->n < 0 OrElse pMem->n >= SQLITE_MAX_ALLOCATION_SIZE Then Return 0
        Dim copySize As ULongInt = CULngInt(pMem->n) + 1
        Dim zCopy As UByte Ptr = CPtr(UByte Ptr, sqlite3DbMallocRaw(pMem->db, copySize))
        If zCopy = 0 Then Return 0
        sqlite3SystemMemcpy(zCopy, pMem->z, CULng(pMem->n))
        zCopy[pMem->n] = 0
        Dim rc As SQLITE_C_INT = sqlite3AtoF(CPtr(Const ZString Ptr, zCopy), pValue)
        sqlite3DbFree(pMem->db, zCopy)
        Return rc
    End If

    If pMem->enc <> SQLITE_UTF16LE AndAlso pMem->enc <> SQLITE_UTF16BE Then Return 0
    Dim byteCount As Long = pMem->n And Not 1
    Dim copySize As ULongInt = CULngInt(byteCount \ 2) + 2
    Dim zCopy As UByte Ptr = CPtr(UByte Ptr, sqlite3DbMallocRaw(pMem->db, copySize))
    If zCopy = 0 Then Return 0

    Dim sourceOffset As Long = 0
    Dim destinationOffset As Long = 0
    While sourceOffset < byteCount - 1
        If pMem->enc = SQLITE_UTF16LE Then
            zCopy[destinationOffset] = pMem->z[sourceOffset]
            If pMem->z[sourceOffset + 1] <> 0 Then Exit While
        Else
            If pMem->z[sourceOffset] <> 0 Then Exit While
            zCopy[destinationOffset] = pMem->z[sourceOffset + 1]
        End If
        sourceOffset += 2
        destinationOffset += 1
    Wend
    zCopy[destinationOffset] = 0
    Dim rc As SQLITE_C_INT = sqlite3AtoF(CPtr(Const ZString Ptr, zCopy), pValue)
    If sourceOffset < byteCount Then rc = -100
    sqlite3DbFree(pMem->db, zCopy)
    Return rc
End Function

Function sqlite3MemRealValueRC CDecl Alias "sqlite3MemRealValueRC" ( _
    ByVal pMemArgument As Any Ptr, _
    ByVal pValue As Double Ptr _
) As SQLITE_C_INT Export

    If pValue = 0 Then Return SQLITE_MISUSE
    *pValue = 0.0
    If pMemArgument = 0 Then Return SQLITE_MISUSE
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pMemArgument)
    If (pMem->flags And (MEM_STR Or MEM_BLOB)) = 0 Then Return 0
    If pMem->z = 0 OrElse pMem->n = 0 Then Return 0

    If pMem->enc = SQLITE_UTF8 AndAlso (pMem->flags And MEM_TERM) <> 0 Then
        Return sqlite3AtoF(CPtr(Const ZString Ptr, pMem->z), pValue)
    End If
    Return sqlite3MemRealValueRCSlowPath(pMem, pValue)
End Function

Function sqlite3VdbeRealValue CDecl Alias "sqlite3VdbeRealValue" ( _
    ByVal pArgument As Any Ptr _
) As Double Export

    If pArgument = 0 Then Return 0.0
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If (pMem->flags And MEM_REAL) <> 0 Then Return pMem->u.r
    If (pMem->flags And (MEM_INT Or MEM_INTREAL)) <> 0 Then Return CDbl(pMem->u.i)
    If (pMem->flags And (MEM_STR Or MEM_BLOB)) <> 0 Then
        Dim value As Double = 0.0
        sqlite3MemRealValueRC(pMem, @value)
        Return value
    End If
    Return 0.0
End Function

Function sqlite3VdbeBooleanValue CDecl Alias "sqlite3VdbeBooleanValue" ( _
    ByVal pArgument As Any Ptr, _
    ByVal ifNull As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return ifNull
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If (pMem->flags And (MEM_INT Or MEM_INTREAL)) <> 0 Then
        If pMem->u.i <> 0 Then Return 1
        Return 0
    End If
    If (pMem->flags And MEM_NULL) <> 0 Then Return ifNull
    If sqlite3VdbeRealValue(pMem) <> 0.0 Then Return 1
    Return 0
End Function

Function sqlite3VdbeMemRealify CDecl Alias "sqlite3VdbeMemRealify" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return SQLITE_MISUSE
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If sqlite3MemIsRowSet(pMem) <> 0 OrElse (pMem->flags And MEM_AGG) <> 0 Then Return SQLITE_MISUSE
    pMem->u.r = sqlite3VdbeRealValue(pMem)
    sqlite3MemSetTypeFlag(pMem, MEM_REAL)
    Return SQLITE_OK
End Function

Function sqlite3VdbeMemNumerify CDecl Alias "sqlite3VdbeMemNumerify" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return SQLITE_MISUSE
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If sqlite3MemIsRowSet(pMem) <> 0 OrElse (pMem->flags And MEM_AGG) <> 0 Then Return SQLITE_MISUSE
    If (pMem->flags And (MEM_INT Or MEM_REAL Or MEM_INTREAL Or MEM_NULL)) = 0 Then
        If (pMem->flags And (MEM_STR Or MEM_BLOB)) = 0 Then Return SQLITE_MISUSE
        Dim parseStatus As SQLITE_C_INT = sqlite3MemRealValueRC(pMem, @pMem->u.r)
        Dim integerValue As sqlite3_int64 = 0
        Dim integerStatus As SQLITE_C_INT = 2
        If (parseStatus And 2) = 0 Then
            integerStatus = sqlite3Atoi64(pMem->z, @integerValue, pMem->n, pMem->enc)
        End If
        If ((parseStatus And 2) = 0 AndAlso integerStatus < 2) OrElse _
           sqlite3RealSameAsInt(pMem->u.r, sqlite3RealToI64(pMem->u.r)) <> 0 Then
            If integerStatus >= 2 OrElse (parseStatus And 2) <> 0 Then
                integerValue = sqlite3RealToI64(pMem->u.r)
            End If
            pMem->u.i = integerValue
            sqlite3MemSetTypeFlag(pMem, MEM_INT)
        Else
            sqlite3MemSetTypeFlag(pMem, MEM_REAL)
        End If
    End If
    pMem->flags = pMem->flags And Not (MEM_STR Or MEM_BLOB Or MEM_ZERO)
    Return SQLITE_OK
End Function

Private Sub sqlite3MemClearExternal(ByVal pMem As SqliteVdbeMem Ptr)
    If pMem = 0 Then Exit Sub
    If (pMem->flags And MEM_AGG) <> 0 Then
        Dim pFunction As Any Ptr = pMem->u.pDef
        If pFunction <> 0 Then sqlite3VdbeMemFinalize(pMem, pFunction)
    End If
    If (pMem->flags And MEM_DYN) <> 0 Then
        Dim xDel As sqlite3MemDestructor = pMem->xDel
        Dim z As UByte Ptr = pMem->z
        pMem->flags = MEM_NULL
        pMem->xDel = 0
        If xDel <> 0 Then xDel(z)
    End If
End Sub

Private Function sqlite3MemIsTransientDestructor(ByVal xDel As sqlite3MemDestructor) As Long
    Dim xTransient As sqlite3MemDestructor = CPtr(sqlite3MemDestructor, -1)
    If xDel = xTransient Then Return -1
    Return 0
End Function

Private Function sqlite3MemIsDynamicDestructor(ByVal xDel As sqlite3MemDestructor) As Long
    If xDel = @sqlite3RowSetClear Then Return -1
    Return 0
End Function

Sub sqlite3VdbeMemInit CDecl Alias "sqlite3VdbeMemInit" ( _
    ByVal pArgument As Any Ptr, _
    ByVal db As sqlite3 Ptr, _
    ByVal flags As u16 _
) Export

    If pArgument = 0 Then Exit Sub
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    pMem->u.i = 0
    pMem->z = 0
    pMem->n = 0
    pMem->flags = flags And MEM_TYPE_MASK
    pMem->enc = SQLITE_UTF8
    pMem->eSubtype = 0
    pMem->db = db
    pMem->szMalloc = 0
    pMem->uTemp = 0
    pMem->zMalloc = 0
    pMem->xDel = 0
#ifdef SQLITE_DEBUG
    pMem->pScopyFrom = 0
    pMem->mScopyFlags = 0
    pMem->bScopy = 0
#endif
End Sub

Function sqlite3ValueNew CDecl Alias "sqlite3ValueNew" ( _
    ByVal db As sqlite3 Ptr _
) As Any Ptr Export
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, _
        sqlite3DbMallocZero(db, SizeOf(SqliteVdbeMem)))
    If pMem = 0 Then Return 0
    pMem->flags = MEM_NULL
    pMem->db = db
    Return pMem
End Function

Sub sqlite3VdbeMemSetNull CDecl Alias "sqlite3VdbeMemSetNull" ( _
    ByVal pArgument As Any Ptr _
) Export

    If pArgument = 0 Then Exit Sub
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    sqlite3MemClearExternal(pMem)
    pMem->flags = MEM_NULL
End Sub

Sub sqlite3ValueSetNull CDecl Alias "sqlite3ValueSetNull" ( _
    ByVal pValue As Any Ptr _
) Export
    sqlite3VdbeMemSetNull(pValue)
End Sub

Sub sqlite3ValueSetStr CDecl Alias "sqlite3ValueSetStr" ( _
    ByVal pValue As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal z As Const Any Ptr, _
    ByVal enc As u8, _
    ByVal xDestructor As sqlite3MemDestructor _
) Export
    If pValue = 0 Then Return
    sqlite3VdbeMemSetStr(pValue, CPtr(Const ZString Ptr, z), nByte, enc, xDestructor)
End Sub

Private Function sqlite3VdbeMemAddTerminator(ByVal pMem As SqliteVdbeMem Ptr) As SQLITE_C_INT
    If pMem = 0 Then Return SQLITE_MISUSE
    If pMem->n > &H7FFFFFFC Then Return SQLITE_TOOBIG
    Dim rc As SQLITE_C_INT = sqlite3VdbeMemGrow(pMem, pMem->n + 3, 1)
    If rc <> SQLITE_OK Then Return rc
    pMem->z[pMem->n] = 0
    pMem->z[pMem->n + 1] = 0
    pMem->z[pMem->n + 2] = 0
    pMem->flags = pMem->flags Or MEM_TERM
    Return SQLITE_OK
End Function

Function sqlite3VdbeMemGrow CDecl Alias "sqlite3VdbeMemGrow" ( _
    ByVal pArgument As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal keepContent As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pArgument = 0 OrElse nByte <= 0 Then Return SQLITE_MISUSE
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If sqlite3MemIsRowSet(pMem) <> 0 OrElse (pMem->flags And MEM_AGG) <> 0 Then Return SQLITE_MISUSE
    If keepContent <> 0 AndAlso nByte < pMem->n Then Return SQLITE_MISUSE

    If pMem->szMalloc > 0 AndAlso keepContent <> 0 AndAlso pMem->z = pMem->zMalloc Then
        pMem->zMalloc = CPtr(UByte Ptr, sqlite3DbReallocOrFree( _
            pMem->db, pMem->z, CULngInt(nByte)))
        pMem->z = pMem->zMalloc
        keepContent = 0
    Else
        If pMem->szMalloc > 0 Then sqlite3DbFree(pMem->db, pMem->zMalloc)
        pMem->zMalloc = CPtr(UByte Ptr, sqlite3DbMallocRaw(pMem->db, CULngInt(nByte)))
    End If

    If pMem->zMalloc = 0 Then
        sqlite3VdbeMemSetNull(pMem)
        pMem->z = 0
        pMem->szMalloc = 0
        pMem->zMalloc = 0
        Return SQLITE_NOMEM
    End If
    pMem->szMalloc = sqlite3DbMallocSize(pMem->db, pMem->zMalloc)

    If keepContent <> 0 AndAlso pMem->z <> 0 AndAlso pMem->n > 0 Then
        sqlite3SystemMemcpy(pMem->zMalloc, pMem->z, CUInt(pMem->n))
    End If
    If (pMem->flags And MEM_DYN) <> 0 Then
        Dim xDel As sqlite3MemDestructor = pMem->xDel
        Dim oldZ As UByte Ptr = pMem->z
        pMem->xDel = 0
        If xDel <> 0 Then xDel(oldZ)
    End If
    pMem->z = pMem->zMalloc
    pMem->flags = pMem->flags And Not (MEM_DYN Or MEM_EPHEM Or MEM_STATIC)
    Return SQLITE_OK
End Function

Function sqlite3VdbeMemClearAndResize CDecl Alias "sqlite3VdbeMemClearAndResize" ( _
    ByVal pArgument As Any Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pArgument = 0 OrElse nByte <= 0 Then Return SQLITE_MISUSE
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If sqlite3MemIsRowSet(pMem) <> 0 OrElse (pMem->flags And MEM_AGG) <> 0 Then Return SQLITE_MISUSE
    If pMem->szMalloc < nByte Then Return sqlite3VdbeMemGrow(pMem, nByte, 0)
    If (pMem->flags And MEM_DYN) <> 0 Then sqlite3VdbeMemSetNull(pMem)
    pMem->z = pMem->zMalloc
    pMem->flags = pMem->flags And (MEM_NULL Or MEM_INT Or MEM_REAL Or MEM_INTREAL)
    Return SQLITE_OK
End Function

/' Copy a range from the current B-tree record into Mem-owned storage. '/
Function sqlite3VdbeMemFromBtree CDecl Alias "sqlite3VdbeMemFromBtree" ( _
    ByVal pCursorArgument As Any Ptr, _
    ByVal offset As u32, _
    ByVal amount As u32, _
    ByVal pMemArgument As Any Ptr _
) As SQLITE_C_INT Export
    If pCursorArgument = 0 OrElse pMemArgument = 0 Then Return SQLITE_MISUSE
    Dim pCursor As BtCursor Ptr = CPtr(BtCursor Ptr, pCursorArgument)
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pMemArgument)
    pMem->flags = MEM_NULL

    If amount >= SQLITE_MAX_ALLOCATION_SIZE Then Return SQLITE_NOMEM
    Dim maximumRecordSize As sqlite3_int64 = sqlite3BtreeMaxRecordSize(pCursor)
    If maximumRecordSize < 0 OrElse _
       CULngInt(amount) + CULngInt(offset) > CULngInt(maximumRecordSize) Then _
        Return SQLITE_CORRUPT

    Dim rc As SQLITE_C_INT = sqlite3VdbeMemClearAndResize( _
        pMem, CInt(amount + 1))
    If rc <> SQLITE_OK Then Return rc

    rc = sqlite3BtreePayload(pCursor, offset, amount, pMem->z)
    If rc <> SQLITE_OK Then
        sqlite3VdbeMemRelease(pMem)
        Return rc
    End If

    pMem->z[CLng(amount)] = 0
    pMem->flags = MEM_BLOB
    pMem->n = CInt(amount)
    Return SQLITE_OK
End Function

/' Borrow local-page payload bytes when possible; copy overflow bytes into Mem. '/
Function sqlite3VdbeMemFromBtreeZeroOffset CDecl Alias "sqlite3VdbeMemFromBtreeZeroOffset" ( _
    ByVal pCursorArgument As Any Ptr, _
    ByVal amount As u32, _
    ByVal pMemArgument As Any Ptr _
) As SQLITE_C_INT Export
    If pCursorArgument = 0 OrElse pMemArgument = 0 Then Return SQLITE_MISUSE
    Dim pCursor As BtCursor Ptr = CPtr(BtCursor Ptr, pCursorArgument)
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pMemArgument)
    If sqlite3MemIsRowSet(pMem) <> 0 OrElse _
       (pMem->flags And (MEM_DYN Or MEM_AGG)) <> 0 Then Return SQLITE_MISUSE
    If sqlite3BtreeCursorIsValidNN(pCursor) = 0 Then Return SQLITE_ABORT

    Dim available As u32 = 0
    pMem->z = CPtr(UByte Ptr, sqlite3BtreePayloadFetch(pCursor, @available))
    If pMem->z = 0 AndAlso amount > 0 Then Return SQLITE_ABORT

    If amount <= available Then
        pMem->flags = MEM_BLOB Or MEM_EPHEM
        pMem->n = CInt(amount)
    Else
        Return sqlite3VdbeMemFromBtree(pCursor, 0, amount, pMem)
    End If
    Return SQLITE_OK
End Function

Function sqlite3VdbeMemExpandBlob CDecl Alias "sqlite3VdbeMemExpandBlob" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return SQLITE_MISUSE
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If (pMem->flags And MEM_ZERO) = 0 Then Return SQLITE_OK
    If sqlite3MemIsRowSet(pMem) <> 0 OrElse (pMem->flags And MEM_AGG) <> 0 Then Return SQLITE_MISUSE

    Dim nByte As LongInt = CLngInt(pMem->n) + CLngInt(pMem->u.nZero)
    If nByte <= 0 Then
        If (pMem->flags And MEM_BLOB) = 0 Then Return SQLITE_OK
        nByte = 1
    End If
    If nByte > &H7FFFFFFF Then Return SQLITE_TOOBIG
    Dim rc As SQLITE_C_INT = sqlite3VdbeMemGrow(pMem, CLng(nByte), 1)
    If rc <> SQLITE_OK Then Return rc
    If pMem->u.nZero > 0 Then
        sqlite3SystemMemset(pMem->z + pMem->n, 0, CUInt(pMem->u.nZero))
    End If
    pMem->n += pMem->u.nZero
    pMem->flags = pMem->flags And Not (MEM_ZERO Or MEM_TERM)
    pMem->u.nZero = 0
    Return SQLITE_OK
End Function

Function sqlite3VdbeMemMakeWriteable CDecl Alias "sqlite3VdbeMemMakeWriteable" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return SQLITE_MISUSE
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If sqlite3MemIsRowSet(pMem) <> 0 OrElse (pMem->flags And MEM_AGG) <> 0 Then Return SQLITE_MISUSE
    If (pMem->flags And (MEM_STR Or MEM_BLOB)) <> 0 Then
        Dim rc As SQLITE_C_INT = sqlite3VdbeMemExpandBlob(pMem)
        If rc <> SQLITE_OK Then Return rc
        If pMem->szMalloc = 0 OrElse pMem->z <> pMem->zMalloc Then
            rc = sqlite3VdbeMemAddTerminator(pMem)
            If rc <> SQLITE_OK Then Return rc
        End If
    End If
    pMem->flags = pMem->flags And Not MEM_EPHEM
    Return SQLITE_OK
End Function

Function sqlite3VdbeMemNulTerminate CDecl Alias "sqlite3VdbeMemNulTerminate" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return SQLITE_MISUSE
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If (pMem->flags And (MEM_TERM Or MEM_STR)) <> MEM_STR Then Return SQLITE_OK
    Return sqlite3VdbeMemAddTerminator(pMem)
End Function

Private Sub sqlite3VdbeMemCopyPrefix( _
    ByVal pTo As SqliteVdbeMem Ptr, _
    ByVal pFrom As Const SqliteVdbeMem Ptr _
)
    pTo->u = pFrom->u
    pTo->z = pFrom->z
    pTo->n = pFrom->n
    pTo->flags = pFrom->flags
    pTo->enc = pFrom->enc
    pTo->eSubtype = pFrom->eSubtype
End Sub

Function sqlite3VdbeMemCopy CDecl Alias "sqlite3VdbeMemCopy" ( _
    ByVal pToArgument As Any Ptr, _
    ByVal pFromArgument As Any Ptr _
) As SQLITE_C_INT Export

    If pToArgument = 0 OrElse pFromArgument = 0 Then Return SQLITE_MISUSE
    If pToArgument = pFromArgument Then Return SQLITE_OK
    Dim pTo As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pToArgument)
    Dim pFrom As Const SqliteVdbeMem Ptr = CPtr(Const SqliteVdbeMem Ptr, pFromArgument)
    If sqlite3MemIsRowSet(CPtr(SqliteVdbeMem Ptr, pFrom)) <> 0 OrElse _
       (pFrom->flags And MEM_AGG) <> 0 OrElse (pTo->flags And MEM_AGG) <> 0 Then
        Return SQLITE_MISUSE
    End If
    If (pTo->flags And MEM_DYN) <> 0 Then sqlite3MemClearExternal(pTo)
    sqlite3VdbeMemCopyPrefix(pTo, pFrom)
#ifdef SQLITE_DEBUG
    pTo->pScopyFrom = 0
    pTo->mScopyFlags = 0
    pTo->bScopy = 0
#endif
    pTo->flags = pTo->flags And Not MEM_DYN
    If (pTo->flags And (MEM_STR Or MEM_BLOB)) <> 0 AndAlso _
       (pFrom->flags And MEM_STATIC) = 0 Then
        pTo->flags = pTo->flags Or MEM_EPHEM
        Return sqlite3VdbeMemMakeWriteable(pTo)
    End If
    Return SQLITE_OK
End Function

Sub sqlite3VdbeMemShallowCopy CDecl Alias "sqlite3VdbeMemShallowCopy" ( _
    ByVal pToArgument As Any Ptr, _
    ByVal pFromArgument As Const Any Ptr, _
    ByVal sourceType As SQLITE_C_INT _
) Export

    If pToArgument = 0 OrElse pFromArgument = 0 OrElse pToArgument = pFromArgument Then Exit Sub
    Dim pTo As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pToArgument)
    Dim pFrom As Const SqliteVdbeMem Ptr = CPtr(Const SqliteVdbeMem Ptr, pFromArgument)
    If pTo->db <> pFrom->db OrElse sqlite3MemIsRowSet(CPtr(SqliteVdbeMem Ptr, pFrom)) <> 0 OrElse _
       (sourceType <> MEM_EPHEM AndAlso sourceType <> MEM_STATIC) Then Exit Sub
    If (pTo->flags And MEM_AGG) <> 0 Then Exit Sub
    If (pTo->flags And MEM_DYN) <> 0 Then sqlite3MemClearExternal(pTo)
    sqlite3VdbeMemCopyPrefix(pTo, pFrom)
    If (pFrom->flags And MEM_STATIC) = 0 Then
        pTo->flags = pTo->flags And Not (MEM_DYN Or MEM_STATIC Or MEM_EPHEM)
        pTo->flags = pTo->flags Or sourceType
    End If
#ifdef SQLITE_DEBUG
    ' SQLite stores its debug-only shallow-copy backpointer through the
    ' C-const source argument; this annotation never changes the copied Mem.
    pTo->pScopyFrom = CPtr(SqliteVdbeMem Ptr, pFrom)
    pTo->mScopyFlags = pFrom->flags
    CPtr(SqliteVdbeMem Ptr, pFrom)->bScopy = 1
#endif
End Sub

Private Sub sqlite3VdbeMemReleaseAndSetInt64( _
    ByVal pMem As SqliteVdbeMem Ptr, _
    ByVal value As sqlite3_int64 _
)
    sqlite3VdbeMemSetNull(pMem)
    pMem->u.i = value
    pMem->flags = MEM_INT
End Sub

Sub sqlite3VdbeMemSetInt64 CDecl Alias "sqlite3VdbeMemSetInt64" ( _
    ByVal pArgument As Any Ptr, _
    ByVal value As sqlite3_int64 _
) Export

    If pArgument = 0 Then Exit Sub
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If (pMem->flags And MEM_AGG) <> 0 Then Exit Sub
    If sqlite3MemIsDynamic(pMem) Then
        sqlite3VdbeMemReleaseAndSetInt64(pMem, value)
    Else
        pMem->u.i = value
        pMem->flags = MEM_INT
    End If
End Sub

Sub sqlite3MemSetArrayInt64 CDecl Alias "sqlite3MemSetArrayInt64" ( _
    ByVal pMemArrayArgument As Any Ptr, _
    ByVal iIndex As SQLITE_C_INT, _
    ByVal value As sqlite3_int64 _
) Export
    If pMemArrayArgument = 0 OrElse iIndex < 0 Then Exit Sub

    ' SQLite supplies an initialized array and a valid slot index. The C
    ' helper receives no element count, so the upper bound belongs to caller.
    Dim pMemArray As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pMemArrayArgument)
    sqlite3VdbeMemSetInt64(@pMemArray[iIndex], value)
End Sub

Sub sqlite3VdbeMemSetDouble CDecl Alias "sqlite3VdbeMemSetDouble" ( _
    ByVal pArgument As Any Ptr, _
    ByVal value As Double _
) Export

    If pArgument = 0 Then Exit Sub
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If (pMem->flags And MEM_AGG) <> 0 Then Exit Sub
    sqlite3VdbeMemSetNull(pMem)
    If value = value Then
        pMem->u.r = value
        pMem->flags = MEM_REAL
    End If
End Sub

Sub sqlite3VdbeMemMove CDecl Alias "sqlite3VdbeMemMove" ( _
    ByVal pToArgument As Any Ptr, _
    ByVal pFromArgument As Any Ptr _
) Export

    If pToArgument = 0 OrElse pFromArgument = 0 OrElse pToArgument = pFromArgument Then Exit Sub
    Dim pTo As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pToArgument)
    Dim pFrom As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pFromArgument)
    If pTo->db <> 0 AndAlso pFrom->db <> 0 AndAlso pTo->db <> pFrom->db Then Exit Sub
    If (pTo->flags And MEM_AGG) <> 0 Then Exit Sub
    sqlite3VdbeMemRelease(pTo)
    pTo[0] = pFrom[0]
    pFrom->flags = MEM_NULL
    pFrom->szMalloc = 0
End Sub

Sub sqlite3VdbeMemSetPointer CDecl Alias "sqlite3VdbeMemSetPointer" ( _
    ByVal pArgument As Any Ptr, _
    ByVal pPointer As Any Ptr, _
    ByVal zPointerType As Const ZString Ptr, _
    ByVal xDestructor As sqlite3MemDestructor _
) Export

    If pArgument = 0 Then Exit Sub
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If (pMem->flags And MEM_AGG) <> 0 Then Exit Sub
    sqlite3VdbeMemRelease(pMem)
    If zPointerType = 0 Then
        pMem->u.zPType = @sqlite3EmptyPointerType
    Else
        pMem->u.zPType = CPtr(ZString Ptr, zPointerType)
    End If
    pMem->z = CPtr(UByte Ptr, pPointer)
    pMem->n = 0
    pMem->szMalloc = 0
    pMem->zMalloc = 0
    pMem->flags = MEM_NULL Or MEM_DYN Or MEM_SUBTYPE Or MEM_TERM
    pMem->eSubtype = Asc("p")
    If xDestructor = 0 Then
        pMem->xDel = @sqlite3NoopDestructor
    Else
        pMem->xDel = xDestructor
    End If
End Sub

Function sqlite3VdbeMemHandleBom CDecl Alias "sqlite3VdbeMemHandleBom" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return SQLITE_MISUSE
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    Dim bomEncoding As u8 = 0
    If pMem->n > 1 AndAlso pMem->z <> 0 Then
        If pMem->z[0] = &HFE AndAlso pMem->z[1] = &HFF Then
            bomEncoding = SQLITE_UTF16BE
        ElseIf pMem->z[0] = &HFF AndAlso pMem->z[1] = &HFE Then
            bomEncoding = SQLITE_UTF16LE
        End If
    End If
    If bomEncoding = 0 Then Return SQLITE_OK

    Dim rc As SQLITE_C_INT = sqlite3VdbeMemMakeWriteable(pMem)
    If rc <> SQLITE_OK Then Return rc
    pMem->n -= 2
    If pMem->n > 0 Then sqlite3SystemMemmove(pMem->z, pMem->z + 2, CUInt(pMem->n))
    pMem->z[pMem->n] = 0
    pMem->z[pMem->n + 1] = 0
    pMem->flags = pMem->flags Or MEM_TERM
    pMem->enc = bomEncoding
    Return SQLITE_OK
End Function

Function sqlite3VdbeMemSetStr CDecl Alias "sqlite3VdbeMemSetStr" ( _
    ByVal pArgument As Any Ptr, _
    ByVal z As Const ZString Ptr, _
    ByVal nByteInput As sqlite3_int64, _
    ByVal enc As u8, _
    ByVal xDestructor As sqlite3MemDestructor _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return SQLITE_MISUSE
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If sqlite3MemIsRowSet(pMem) <> 0 OrElse (pMem->flags And MEM_AGG) <> 0 Then Return SQLITE_MISUSE
    If z = 0 Then
        sqlite3VdbeMemSetNull(pMem)
        Return SQLITE_OK
    End If
    If enc <> 0 AndAlso enc <> SQLITE_UTF8 AndAlso _
       enc <> SQLITE_UTF16LE AndAlso enc <> SQLITE_UTF16BE AndAlso _
       enc <> SQLITE_UTF16 Then Return SQLITE_MISUSE
    If enc = 0 AndAlso nByteInput < 0 Then Return SQLITE_MISUSE

    Dim nByte As sqlite3_int64 = nByteInput
    Dim textEncoding As u8 = enc
    Dim newFlags As UShort
    Dim lengthLimit As SQLITE_C_INT = SQLITE_MAX_LENGTH
    If pMem->db <> 0 Then lengthLimit = pMem->db->lengthLimit

    If nByte < 0 Then
        If textEncoding = SQLITE_UTF8 Then
            nByte = sqlite3SystemStrlen(z)
        Else
            If textEncoding = SQLITE_UTF16 Then textEncoding = SQLITE_UTF16NATIVE
            Dim z16 As Const UByte Ptr = CPtr(Const UByte Ptr, z)
            nByte = 0
            While nByte <= lengthLimit AndAlso (z16[nByte] Or z16[nByte + 1]) <> 0
                nByte += 2
            Wend
        End If
        newFlags = MEM_STR Or MEM_TERM
    ElseIf textEncoding = 0 Then
        newFlags = MEM_BLOB
        textEncoding = SQLITE_UTF8
    Else
        newFlags = MEM_STR
        If textEncoding = SQLITE_UTF16 Then textEncoding = SQLITE_UTF16NATIVE
    End If

    If nByte > lengthLimit Then
        If xDestructor <> 0 AndAlso sqlite3MemIsTransientDestructor(xDestructor) = 0 Then
            If sqlite3MemIsDynamicDestructor(xDestructor) <> 0 Then
                sqlite3DbFree(pMem->db, CPtr(Any Ptr, z))
            Else
                xDestructor(CPtr(Any Ptr, z))
            End If
        End If
        sqlite3VdbeMemSetNull(pMem)
        Return SQLITE_TOOBIG
    End If

    If sqlite3MemIsTransientDestructor(xDestructor) <> 0 Then
        Dim nCopy As sqlite3_int64 = nByte
        If (newFlags And MEM_TERM) <> 0 Then
            If textEncoding = SQLITE_UTF8 Then
                nCopy += 1
            Else
                nCopy += 2
            End If
        End If
        Dim nAlloc As sqlite3_int64 = nCopy
        If nAlloc < 32 Then nAlloc = 32
        If nAlloc > &H7FFFFFFF Then Return SQLITE_TOOBIG
        Dim rc As SQLITE_C_INT = sqlite3VdbeMemClearAndResize(pMem, CLng(nAlloc))
        If rc <> SQLITE_OK Then Return SQLITE_NOMEM
        If nCopy > 0 Then sqlite3SystemMemcpy(pMem->z, z, CUInt(nCopy))
    Else
        sqlite3VdbeMemRelease(pMem)
        pMem->z = CPtr(UByte Ptr, z)
        If sqlite3MemIsDynamicDestructor(xDestructor) <> 0 Then
            pMem->zMalloc = pMem->z
            pMem->szMalloc = sqlite3DbMallocSize(pMem->db, pMem->zMalloc)
            pMem->xDel = 0
        Else
            pMem->xDel = xDestructor
            If xDestructor = 0 Then
                newFlags = newFlags Or MEM_STATIC
            Else
                newFlags = newFlags Or MEM_DYN
            End If
        End If
    End If

    pMem->n = CLng(nByte And &H7FFFFFFF)
    pMem->flags = newFlags
    pMem->enc = textEncoding
    If textEncoding > SQLITE_UTF8 Then Return sqlite3VdbeMemHandleBom(pMem)
    Return SQLITE_OK
End Function

Function sqlite3VdbeMemSetText CDecl Alias "sqlite3VdbeMemSetText" ( _
    ByVal pArgument As Any Ptr, _
    ByVal z As Const ZString Ptr, _
    ByVal nByte As sqlite3_int64, _
    ByVal xDestructor As sqlite3MemDestructor _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return SQLITE_MISUSE
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If pMem->db = 0 Then Return SQLITE_MISUSE
    Return sqlite3VdbeMemSetStr(pMem, z, nByte, SQLITE_UTF8, xDestructor)
End Function

Sub sqlite3VdbeMemSetZeroBlob CDecl Alias "sqlite3VdbeMemSetZeroBlob" ( _
    ByVal pArgument As Any Ptr, _
    ByVal nZero As SQLITE_C_INT _
) Export

    If pArgument = 0 Then Exit Sub
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If (pMem->flags And MEM_AGG) <> 0 Then Exit Sub
    sqlite3VdbeMemRelease(pMem)
    pMem->flags = MEM_BLOB Or MEM_ZERO
    pMem->n = 0
    pMem->u.nZero = IIf(nZero < 0, 0, nZero)
    pMem->enc = SQLITE_UTF8
    pMem->z = 0
End Sub

Sub sqlite3VdbeMemRelease CDecl Alias "sqlite3VdbeMemRelease" ( _
    ByVal pArgument As Any Ptr _
) Export

    If pArgument = 0 Then Exit Sub
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    sqlite3MemClearExternal(pMem)
    If pMem->szMalloc <> 0 Then
        sqlite3DbFree(pMem->db, pMem->zMalloc)
        pMem->szMalloc = 0
        pMem->zMalloc = 0
    End If
    pMem->z = 0
End Sub

Function sqlite3VdbeMemFinalize CDecl Alias "sqlite3VdbeMemFinalize" ( _
    ByVal pMemArgument As Any Ptr, _
    ByVal pFunctionArgument As Any Ptr _
) As SQLITE_C_INT Export
    If pMemArgument = 0 OrElse pFunctionArgument = 0 Then Return SQLITE_MISUSE
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pMemArgument)
    Dim pFunction As SqliteFuncDef Ptr = _
        CPtr(SqliteFuncDef Ptr, pFunctionArgument)
    If pMem->db = 0 OrElse pFunction->xFinalize = 0 Then Return SQLITE_MISUSE
    If (pMem->flags And Not (MEM_NULL Or MEM_AGG)) <> 0 OrElse _
       ((pMem->flags And MEM_AGG) <> 0 AndAlso pMem->u.pDef <> pFunction) Then _
        Return SQLITE_CORRUPT

    Dim result As SqliteVdbeMem
    sqlite3VdbeMemInit(@result, pMem->db, MEM_NULL)
    Dim context As SqliteResultContext
    context.pOut = @result
    context.pFunc = pFunction
    context.pMem = pMem
    context.pVdbe = 0
    context.iOp = 0
    context.isError = 0
    context.enc = pMem->db->enc
    context.skipFlag = 0
    context.argc = 0
    context.argv(0) = 0
    Dim xFinalize As SqliteAggregateFinalFunction = _
        CPtr(SqliteAggregateFinalFunction, pFunction->xFinalize)
    xFinalize(@context)

    If pMem->szMalloc > 0 Then sqlite3DbFree(pMem->db, pMem->zMalloc)
    pMem->szMalloc = 0
    pMem->zMalloc = 0
    pMem->z = 0
    pMem->flags = MEM_NULL
    pMem->n = 0
    pMem->xDel = 0
    pMem->u.i = 0
    sqlite3VdbeMemMove(pMem, @result)
    Return context.isError
End Function

Function sqlite3VdbeMemAggValue CDecl Alias "sqlite3VdbeMemAggValue" ( _
    ByVal pAccumArgument As Any Ptr, _
    ByVal pOutputArgument As Any Ptr, _
    ByVal pFunctionArgument As Any Ptr _
) As SQLITE_C_INT Export
    If pAccumArgument = 0 OrElse pOutputArgument = 0 OrElse _
       pFunctionArgument = 0 Then Return SQLITE_MISUSE
    Dim pAccum As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pAccumArgument)
    Dim pOutput As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pOutputArgument)
    Dim pFunction As SqliteFuncDef Ptr = _
        CPtr(SqliteFuncDef Ptr, pFunctionArgument)
    If pFunction->xValue = 0 OrElse pAccum->db = 0 OrElse _
       pOutput->db <> pAccum->db Then Return SQLITE_MISUSE

    sqlite3VdbeMemSetNull(pOutput)
    Dim context As SqliteResultContext
    context.pOut = pOutput
    context.pFunc = pFunction
    context.pMem = pAccum
    context.pVdbe = 0
    context.iOp = 0
    context.isError = 0
    context.enc = pAccum->db->enc
    context.skipFlag = 0
    context.argc = 0
    context.argv(0) = 0
    Dim xValue As SqliteAggregateFinalFunction = _
        CPtr(SqliteAggregateFinalFunction, pFunction->xValue)
    xValue(@context)
    Return context.isError
End Function

Sub sqlite3ValueFree CDecl Alias "sqlite3ValueFree" ( _
    ByVal pArgument As Any Ptr _
) Export

    If pArgument = 0 Then Exit Sub
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    sqlite3VdbeMemRelease(pMem)
    sqlite3DbFree(pMem->db, pArgument)
End Sub

Sub sqlite3VdbeMemReleaseMalloc CDecl Alias "sqlite3VdbeMemReleaseMalloc" ( _
    ByVal pArgument As Any Ptr _
) Export

    If pArgument = 0 Then Exit Sub
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If sqlite3MemIsDynamic(pMem) Then
        sqlite3VdbeMemRelease(pMem)
    ElseIf pMem->szMalloc <> 0 Then
        sqlite3DbFree(pMem->db, pMem->zMalloc)
        pMem->szMalloc = 0
        pMem->zMalloc = 0
        pMem->z = 0
    End If
End Sub

Function sqlite3VdbeMemSetRowSet CDecl Alias "sqlite3VdbeMemSetRowSet" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return SQLITE_MISUSE
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If pMem->db = 0 OrElse (pMem->flags And MEM_AGG) <> 0 Then Return SQLITE_MISUSE
    sqlite3VdbeMemRelease(pMem)
    Dim pRowSet As Any Ptr = sqlite3RowSetInit(pMem->db)
    If pRowSet = 0 Then Return SQLITE_NOMEM
    pMem->z = CPtr(UByte Ptr, pRowSet)
    pMem->flags = MEM_BLOB Or MEM_DYN
    pMem->xDel = @sqlite3RowSetDelete
    Return SQLITE_OK
End Function

Sub sqlite3NoopDestructor CDecl Alias "sqlite3NoopDestructor" ( _
    ByVal p As Any Ptr _
) Export
    ' The callback exists for ownership contracts that require a destructor.
End Sub

#ifdef SQLITE_DEBUG
Function sqlite3VdbeCheckMemInvariants CDecl Alias "sqlite3VdbeCheckMemInvariants" ( _
    ByVal pMem As SqliteVdbeMem Ptr _
) As SQLITE_C_INT
    If pMem = 0 Then Return 0

    Dim flags As ULongInt = CULngInt(pMem->flags)
    If (flags And MEM_DYN) <> 0 AndAlso pMem->xDel = 0 Then
        sqlite3DebugAssert(StrPtr("MEM_Dyn requires a destructor"))
        Return 0
    End If
    If (flags And MEM_DYN) <> 0 AndAlso pMem->szMalloc <> 0 Then
        sqlite3DebugAssert(StrPtr("MEM_Dyn and szMalloc are mutually exclusive"))
        Return 0
    End If

    Dim numericFlags As ULongInt = flags And (MEM_INT Or MEM_REAL Or MEM_INTREAL)
    If numericFlags <> 0 AndAlso (numericFlags And (numericFlags - 1)) <> 0 Then
        sqlite3DebugAssert(StrPtr("at most one numeric Mem type flag is set"))
        Return 0
    End If

    If (flags And MEM_NULL) <> 0 Then
        If (flags And (MEM_INT Or MEM_REAL Or MEM_STR Or MEM_BLOB Or MEM_AGG)) <> 0 Then
            sqlite3DebugAssert(StrPtr("MEM_Null is exclusive with value type flags"))
            Return 0
        End If
        If (flags And (MEM_TERM Or MEM_SUBTYPE)) = (MEM_TERM Or MEM_SUBTYPE) Then
            Dim ownerCount As Long = 0
            If (flags And MEM_DYN) <> 0 Then ownerCount += 1
            If (flags And MEM_EPHEM) <> 0 Then ownerCount += 1
            If (flags And MEM_STATIC) <> 0 Then ownerCount += 1
            If ownerCount > 1 Then
                sqlite3DebugAssert(StrPtr("pointer Mem has at most one ownership flag"))
                Return 0
            End If
            Const POINTER_NULL_FLAGS As ULongInt = _
                MEM_NULL Or MEM_TERM Or MEM_SUBTYPE Or MEM_FROM_BIND Or _
                MEM_DYN Or MEM_EPHEM Or MEM_STATIC
            If (flags And Not POINTER_NULL_FLAGS) <> 0 Then
                sqlite3DebugAssert(StrPtr("pointer Mem has no unrelated flags"))
                Return 0
            End If
        End If
    ElseIf (flags And MEM_CLEARED) <> 0 Then
        sqlite3DebugAssert(StrPtr("MEM_Cleared is only valid on NULL"))
        Return 0
    End If

    If pMem->szMalloc <> 0 Then
        If pMem->szMalloc < 0 OrElse pMem->db = 0 Then
            sqlite3DebugAssert(StrPtr("allocated Mem has valid allocator state"))
            Return 0
        End If
        Dim actualBytes As SQLITE_C_INT = sqlite3DbMallocSize(pMem->db, pMem->zMalloc)
        If flags = MEM_UNDEFINED Then
            If pMem->szMalloc > actualBytes Then
                sqlite3DebugAssert(StrPtr("undefined Mem allocation does not exceed its block"))
                Return 0
            End If
        ElseIf pMem->szMalloc <> actualBytes Then
            sqlite3DebugAssert(StrPtr("Mem size matches its allocated block"))
            Return 0
        End If
    End If

    If (flags And (MEM_STR Or MEM_BLOB)) <> 0 AndAlso pMem->n > 0 Then
        Dim ownerCount As Long = 0
        If pMem->szMalloc > 0 AndAlso pMem->z = pMem->zMalloc Then ownerCount += 1
        If (flags And MEM_DYN) <> 0 Then ownerCount += 1
        If (flags And MEM_EPHEM) <> 0 Then ownerCount += 1
        If (flags And MEM_STATIC) <> 0 Then ownerCount += 1
        If ownerCount <> 1 Then
            sqlite3DebugAssert(StrPtr("string or blob Mem has exactly one storage owner"))
            Return 0
        End If
    End If
    Return 1
End Function

Sub sqlite3VdbeMemPrettyPrint CDecl Alias "sqlite3VdbeMemPrettyPrint" ( _
    ByVal pMem As SqliteVdbeMem Ptr, _
    ByVal accumulatorArgument As Any Ptr _
)
    If pMem = 0 OrElse accumulatorArgument = 0 Then Exit Sub
    Dim pAccumulator As sqlite3_str Ptr = CPtr(sqlite3_str Ptr, accumulatorArgument)
    Dim flags As ULongInt = CULngInt(pMem->flags)

    If (flags And MEM_BLOB) <> 0 Then
        Dim ownership As ULongInt = flags And (MEM_DYN Or MEM_STATIC Or MEM_EPHEM)
        Dim ownerCode As Byte = Asc("s")
        If (ownership And (MEM_DYN Or MEM_STATIC)) = (MEM_DYN Or MEM_STATIC) OrElse _
           (ownership And (MEM_DYN Or MEM_EPHEM)) = (MEM_DYN Or MEM_EPHEM) OrElse _
           (ownership And (MEM_STATIC Or MEM_EPHEM)) = (MEM_STATIC Or MEM_EPHEM) Then
            sqlite3DebugAssert(StrPtr("Mem string/blob has one owner flag"))
        End If
        If (flags And MEM_DYN) <> 0 Then
            ownerCode = Asc("z")
        ElseIf (flags And MEM_STATIC) <> 0 Then
            ownerCode = Asc("t")
        ElseIf (flags And MEM_EPHEM) <> 0 Then
            ownerCode = Asc("e")
        End If
        sqlite3VdbeMemDebugAppendf(pAccumulator, StrPtr(!"%cx["), CInt(ownerCode))
        If pMem->n > 0 Then
            If pMem->z = 0 Then
                sqlite3DebugAssert(StrPtr("nonempty blob Mem has data"))
                Return
            End If
            Dim displayedBytes As SQLITE_C_INT = IIf(pMem->n < 25, pMem->n, 25)
            For iByte As SQLITE_C_INT = 0 To displayedBytes - 1
                sqlite3VdbeMemDebugAppendf(pAccumulator, StrPtr(!"%02X"), CInt(pMem->z[iByte]))
            Next
            sqlite3VdbeMemDebugAppendf(pAccumulator, StrPtr("|"))
            For iByte As SQLITE_C_INT = 0 To displayedBytes - 1
                Dim displayByte As Byte = CByte(pMem->z[iByte])
                If displayByte < &H20 OrElse displayByte > &H7E Then displayByte = Asc(".")
                sqlite3_str_appendchar(pAccumulator, 1, displayByte)
            Next
        Else
            sqlite3VdbeMemDebugAppendf(pAccumulator, StrPtr("|"))
        End If
        sqlite3VdbeMemDebugAppendf(pAccumulator, StrPtr("]"))
        If (flags And MEM_ZERO) <> 0 Then _
            sqlite3VdbeMemDebugAppendf(pAccumulator, StrPtr("+%dz"), pMem->u.nZero)
    ElseIf (flags And MEM_STR) <> 0 Then
        Dim ownership As ULongInt = flags And (MEM_DYN Or MEM_STATIC Or MEM_EPHEM)
        Dim ownerCode As Byte = Asc("s")
        If (ownership And (MEM_DYN Or MEM_STATIC)) = (MEM_DYN Or MEM_STATIC) OrElse _
           (ownership And (MEM_DYN Or MEM_EPHEM)) = (MEM_DYN Or MEM_EPHEM) OrElse _
           (ownership And (MEM_STATIC Or MEM_EPHEM)) = (MEM_STATIC Or MEM_EPHEM) Then
            sqlite3DebugAssert(StrPtr("Mem string/blob has one owner flag"))
        End If
        If (flags And MEM_DYN) <> 0 Then
            ownerCode = Asc("z")
        ElseIf (flags And MEM_STATIC) <> 0 Then
            ownerCode = Asc("t")
        ElseIf (flags And MEM_EPHEM) <> 0 Then
            ownerCode = Asc("e")
        End If
        sqlite3VdbeMemDebugAppendf(pAccumulator, StrPtr(!" %c%d["), _
                                   CInt(ownerCode), pMem->n)
        If pMem->n > 0 Then
            If pMem->z = 0 Then
                sqlite3DebugAssert(StrPtr("nonempty string Mem has data"))
                Return
            End If
            Dim displayedBytes As SQLITE_C_INT = IIf(pMem->n < 25, pMem->n, 25)
            For iByte As SQLITE_C_INT = 0 To displayedBytes - 1
                Dim displayByte As Byte = CByte(pMem->z[iByte])
                If displayByte < &H20 OrElse displayByte > &H7F Then displayByte = Asc(".")
                sqlite3_str_appendchar(pAccumulator, 1, displayByte)
            Next
        End If
        Dim encodingName As Const ZString Ptr
        Select Case pMem->enc
        Case SQLITE_UTF8: encodingName = StrPtr(!"(8)")
        Case SQLITE_UTF16LE: encodingName = StrPtr(!"(16LE)")
        Case SQLITE_UTF16BE: encodingName = StrPtr(!"(16BE)")
        Case Else
            encodingName = StrPtr(!"(X)")
        End Select
        sqlite3VdbeMemDebugAppendf(pAccumulator, StrPtr(!"]%s"), encodingName)
        If (flags And MEM_TERM) <> 0 Then _
            sqlite3VdbeMemDebugAppendf(pAccumulator, StrPtr("(0-term)"))
    End If
End Sub
#ifdef SQLITE_DEBUG
/' This flag is HI(0x0400000), matching SQLITE_VdbeTrace in sqliteInt.h. '/
Private Const SQLITE_VDBE_TRACE_MASK As sqlite3_uint64 = &H0040000000000000ULL

Sub sqlite3VdbeMemAboutToChange CDecl Alias "sqlite3VdbeMemAboutToChange" ( _
    ByVal pVdbeArgument As Any Ptr, _
    ByVal pMem As SqliteVdbeMem Ptr _
) Export
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pVdbeArgument)
    If pVdbe = 0 OrElse pMem = 0 OrElse pVdbe->db = 0 OrElse _
       pVdbe->aMem = 0 OrElse pVdbe->nMem < 0 Then
        sqlite3DebugAssert(StrPtr("Vdbe and Mem pointers are valid"))
        Exit Sub
    End If

    If pMem->bScopy <> 0 Then
        Dim firstMemAddress As ULongInt = CULngInt(CPtr(Any Ptr, pVdbe->aMem))
        Dim changedMemAddress As ULongInt = CULngInt(CPtr(Any Ptr, pMem))
        If changedMemAddress < firstMemAddress Then
            sqlite3DebugAssert(StrPtr("pMem points into the VDBE register array"))
            Exit Sub
        End If
        Dim changedMemOffset As ULongInt = changedMemAddress - firstMemAddress
        If changedMemOffset Mod SizeOf(SqliteVdbeMem) <> 0 OrElse _
           changedMemOffset \ SizeOf(SqliteVdbeMem) > CULngInt(pVdbe->nMem) Then
            sqlite3DebugAssert(StrPtr("pMem is aligned within the VDBE register array"))
            Exit Sub
        End If
        Dim changedRegister As SQLITE_C_INT = _
            CInt(changedMemOffset \ SizeOf(SqliteVdbeMem))

        If pVdbe->nMem > 1 Then
            For copyIndex As SQLITE_C_INT = 1 To pVdbe->nMem - 1
                Dim pShallowCopy As SqliteVdbeMem Ptr = pVdbe->aMem + copyIndex
                If pShallowCopy->pScopyFrom = pMem Then
                    If (pVdbe->db->flags And SQLITE_VDBE_TRACE_MASK) <> 0 Then
                        sqlite3DebugPrintf( _
                            StrPtr(!"Invalidate R[%d] due to change in R[%d]\n"), _
                            copyIndex, changedRegister)
                    End If

                    Dim matchingFlags As UShort = _
                        pMem->flags And pShallowCopy->flags And pShallowCopy->mScopyFlags
                    If (matchingFlags And (MEM_INT Or MEM_INTREAL)) <> 0 AndAlso _
                       pMem->u.i <> pShallowCopy->u.i Then _
                        sqlite3DebugAssert(StrPtr("shallow-copy integer value has not changed"))

                    pShallowCopy->flags = MEM_UNDEFINED
                    pShallowCopy->pScopyFrom = 0
                End If
            Next
        End If
        pMem->bScopy = 0
    End If
    pMem->pScopyFrom = 0
End Sub
#endif

#endif

/' end of sqlite3_vdbe_mem.bas '/
