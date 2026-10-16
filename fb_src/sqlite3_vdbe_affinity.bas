/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_affinity.bas

    Purpose:

        Apply SQLite column affinities to VDBE value cells.

    Responsibilities:

        - Port numeric affinity parsing and integer-first representation.
        - Classify numeric-looking Mem values without changing their flags.
        - Dispatch TEXT, BLOB, NONE, and numeric affinity behavior.

    This file intentionally does NOT contain:

        - Bytecode execution or SQL column affinity selection.
'/

#lang "fb"
#include once "sqlite3_vdbe_affinity.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_vdbe_mem_text.bi"
#include once "sqlite3_numeric.bi"

Private Function sqlite3VdbeMemAlsoAnInt( _
    ByVal pMem As SqliteVdbeMem Ptr, _
    ByVal realValue As Double, _
    ByVal pIntegerValue As sqlite3_int64 Ptr _
) As SQLITE_C_INT
    If pMem = 0 OrElse pIntegerValue = 0 Then Return 0
    Dim integerValue As sqlite3_int64 = sqlite3RealToI64(realValue)
    If sqlite3RealSameAsInt(realValue, integerValue) <> 0 Then
        *pIntegerValue = integerValue
        Return 1
    End If
    If pMem->z = 0 Then Return 0
    If sqlite3Atoi64(pMem->z, pIntegerValue, pMem->n, pMem->enc) = 0 Then Return 1
    Return 0
End Function

Sub sqlite3ApplyNumericAffinity CDecl Alias "sqlite3ApplyNumericAffinity" ( _
    ByVal pArgument As Any Ptr, _
    ByVal tryForInteger As SQLITE_C_INT _
) Export

    If pArgument = 0 Then Exit Sub
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If (pMem->flags And (MEM_STR Or MEM_INT Or MEM_REAL Or MEM_INTREAL)) <> MEM_STR Then Exit Sub

    Dim realValue As Double = 0.0
    Dim parseStatus As SQLITE_C_INT = sqlite3MemRealValueRC(pMem, @realValue)
    If parseStatus <= 0 Then Exit Sub

    If (parseStatus And 2) = 0 AndAlso _
       sqlite3VdbeMemAlsoAnInt(pMem, realValue, @pMem->u.i) <> 0 Then
        pMem->flags = pMem->flags Or MEM_INT
    Else
        pMem->u.r = realValue
        pMem->flags = pMem->flags Or MEM_REAL
        If tryForInteger <> 0 Then sqlite3VdbeIntegerAffinity(pMem)
    End If

    pMem->flags = pMem->flags And Not MEM_STR
End Sub

Private Function sqlite3VdbeComputeNumericType(ByVal pMem As SqliteVdbeMem Ptr) As UShort
    Dim rc As SQLITE_C_INT
    Dim integerValue As sqlite3_int64 = 0
    If pMem = 0 Then Return MEM_UNDEFINED

    If sqlite3VdbeMemExpandBlob(pMem) <> SQLITE_OK Then
        pMem->u.i = 0
        Return MEM_INT
    End If

    rc = sqlite3MemRealValueRC(pMem, @pMem->u.r)
    If rc <= 0 Then
        If (rc And 2) = 0 AndAlso _
           sqlite3Atoi64(pMem->z, @integerValue, pMem->n, pMem->enc) <= 1 Then
            pMem->u.i = integerValue
            Return MEM_INT
        End If
        Return MEM_REAL
    End If

    If (rc And 2) = 0 AndAlso _
       sqlite3Atoi64(pMem->z, @integerValue, pMem->n, pMem->enc) = 0 Then
        pMem->u.i = integerValue
        Return MEM_INT
    End If
    Return MEM_REAL
End Function

Function sqlite3VdbeNumericType CDecl Alias "sqlite3VdbeNumericType" ( _
    ByVal pArgument As Any Ptr _
) As UShort Export
    If pArgument = 0 Then Return MEM_NULL
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    Dim numericFlags As UShort = pMem->flags And (MEM_INT Or MEM_REAL Or MEM_INTREAL Or MEM_NULL)
    If numericFlags <> 0 Then Return numericFlags
    If (pMem->flags And (MEM_STR Or MEM_BLOB)) = 0 Then Return MEM_UNDEFINED
    Return sqlite3VdbeComputeNumericType(pMem)
End Function

Private Sub sqlite3VdbeApplyAffinity( _
    ByVal pMem As SqliteVdbeMem Ptr, _
    ByVal affinity As u8, _
    ByVal enc As u8 _
)
    If pMem = 0 Then Exit Sub
    If affinity >= SQLITE_AFF_NUMERIC Then
        If (pMem->flags And MEM_INT) = 0 Then
            If (pMem->flags And (MEM_REAL Or MEM_INTREAL)) = 0 Then
                If (pMem->flags And MEM_STR) <> 0 Then sqlite3ApplyNumericAffinity(pMem, 1)
            ElseIf affinity <= SQLITE_AFF_REAL Then
                sqlite3VdbeIntegerAffinity(pMem)
            End If
        End If
    ElseIf affinity = SQLITE_AFF_TEXT Then
        If (pMem->flags And MEM_STR) = 0 AndAlso _
           (pMem->flags And (MEM_REAL Or MEM_INT Or MEM_INTREAL)) <> 0 Then
            sqlite3VdbeMemStringify(pMem, enc, 1)
        End If
        pMem->flags = pMem->flags And Not (MEM_REAL Or MEM_INT Or MEM_INTREAL)
    End If
End Sub

Sub sqlite3ValueApplyAffinity CDecl Alias "sqlite3ValueApplyAffinity" ( _
    ByVal pArgument As Any Ptr, _
    ByVal affinity As u8, _
    ByVal enc As u8 _
) Export
    sqlite3VdbeApplyAffinity(CPtr(SqliteVdbeMem Ptr, pArgument), affinity, enc)
End Sub

/' end of sqlite3_vdbe_affinity.bas '/
