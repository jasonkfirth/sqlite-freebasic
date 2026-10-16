/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_api.bas

    Purpose:

        Expose scalar sqlite3_value type, numeric, and text accessors.

    Responsibilities:

        - Report SQLite storage classes from the Mem representation flags.
        - Convert scalar values through the VDBE integer and real helpers.
        - Apply numeric affinity for sqlite3_value_numeric_type.
        - Return text/blob pointers and encoding-aware byte counts.
        - Release transient value-list storage with its allocator callback.
        - Iterate packed right-hand-side values passed to virtual tables.

    This file intentionally does NOT contain:

        - Text/blob conversion algorithms, statement columns, or result APIs.
'/

#lang "fb"
#include once "sqlite3_vdbe_api.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_vdbe_mem_text.bi"
#include once "sqlite3_vdbe_affinity.bi"
#include once "sqlite3_vdbe_serial.bi"
#include once "sqlite3_varint.bi"
#include once "sqlite3_constants.bi"

Extern "C"
    Declare Function sqlite3VdbeApiMemcpy CDecl Alias "memcpy" ( _
        ByVal destination As Any Ptr, _
        ByVal source As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
    Declare Function sqlite3VdbeApiMemset CDecl Alias "memset" ( _
        ByVal p As Any Ptr, _
        ByVal value As SQLITE_C_INT, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
    Declare Function sqlite3VdbeApiMalloc64 CDecl Alias "sqlite3_malloc64" ( _
        ByVal nByte As sqlite3_uint64 _
    ) As Any Ptr
    Declare Sub sqlite3VdbeApiFree CDecl Alias "sqlite3_free" ( _
        ByVal p As Any Ptr _
    )
End Extern

Function sqlite3_value_type CDecl Alias "sqlite3_value_type" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return SQLITE_NULL
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    Dim flags As UShort = pMem->flags
    If (flags And MEM_NULL) <> 0 Then Return SQLITE_NULL
    If (flags And (MEM_REAL Or MEM_INTREAL)) <> 0 Then Return SQLITE_FLOAT
    If (flags And MEM_INT) <> 0 Then Return SQLITE_INTEGER
    If (flags And MEM_STR) <> 0 Then Return SQLITE_TEXT
    Return SQLITE_BLOB
End Function

Function sqlite3ValueIsOfClass CDecl Alias "sqlite3ValueIsOfClass" ( _
    ByVal pValue As Any Ptr, _
    ByVal pDestructor As Any Ptr _
) As SQLITE_C_INT Export
    If pValue = 0 Then Return 0
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pValue)
    If (pMem->flags And (MEM_STR Or MEM_BLOB)) = 0 OrElse _
       (pMem->flags And MEM_DYN) = 0 Then Return 0
    Dim xDestructor As sqlite3MemDestructor = _
        CPtr(sqlite3MemDestructor, pDestructor)
    Return CInt(pMem->xDel = xDestructor)
End Function

Function sqlite3_value_numeric_type CDecl Alias "sqlite3_value_numeric_type" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export

    If pArgument = 0 Then Return SQLITE_NULL
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    Dim valueType As SQLITE_C_INT = sqlite3_value_type(pMem)
    If valueType = SQLITE_TEXT Then
        sqlite3DbEnter(pMem->db)
        sqlite3ApplyNumericAffinity(pMem, 0)
        sqlite3DbLeave(pMem->db)
        valueType = sqlite3_value_type(pMem)
    End If
    Return valueType
End Function

Function sqlite3_value_double CDecl Alias "sqlite3_value_double" ( _
    ByVal pArgument As Any Ptr _
) As Double Export
    Return sqlite3VdbeRealValue(pArgument)
End Function

Function sqlite3_value_int64 CDecl Alias "sqlite3_value_int64" ( _
    ByVal pArgument As Any Ptr _
) As sqlite3_int64 Export
    Return sqlite3VdbeIntValue(pArgument)
End Function

Function sqlite3_value_int CDecl Alias "sqlite3_value_int" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export
    Dim integerValue As sqlite3_int64 = sqlite3VdbeIntValue(pArgument)
    Dim lowWord As ULong = CULng(integerValue And &HFFFFFFFF)
    Dim result As SQLITE_C_INT = 0
    ' C's out-of-range signed conversion is implementation-defined. SQLite's
    ' supported targets retain the low 32-bit two's-complement representation.
    sqlite3VdbeApiMemcpy(@result, @lowWord, SizeOf(result))
    Return result
End Function

Function sqlite3_value_encoding CDecl Alias "sqlite3_value_encoding" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export
    If pArgument = 0 Then Return 0
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    Return pMem->enc
End Function

Function sqlite3_value_subtype CDecl Alias "sqlite3_value_subtype" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_UINT Export
    If pArgument = 0 Then Return 0
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If (pMem->flags And MEM_SUBTYPE) <> 0 Then Return CUInt(pMem->eSubtype)
    Return 0
End Function

Private Function sqlite3VdbeApiStringEqual( _
    ByVal leftText As Const ZString Ptr, _
    ByVal rightText As Const ZString Ptr _
) As Long
    If leftText = 0 OrElse rightText = 0 Then Return 0
    Dim leftBytes As Const UByte Ptr = CPtr(Const UByte Ptr, leftText)
    Dim rightBytes As Const UByte Ptr = CPtr(Const UByte Ptr, rightText)
    Dim offset As Long = 0
    While leftBytes[offset] = rightBytes[offset]
        If leftBytes[offset] = 0 Then Return -1
        offset += 1
    Wend
    Return 0
End Function

Function sqlite3_value_pointer CDecl Alias "sqlite3_value_pointer" ( _
    ByVal pArgument As Any Ptr, _
    ByVal zType As Const ZString Ptr _
) As Any Ptr Export
    If pArgument = 0 OrElse zType = 0 Then Return 0
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    Dim requiredFlags As UShort = MEM_NULL Or MEM_TERM Or MEM_SUBTYPE
    If (pMem->flags And (MEM_TYPE_MASK Or MEM_TERM Or MEM_SUBTYPE)) <> requiredFlags Then Return 0
    If pMem->eSubtype <> Asc("p") Then Return 0
    If sqlite3VdbeApiStringEqual(pMem->u.zPType, zType) = 0 Then Return 0
    Return pMem->z
End Function

Function sqlite3_value_nochange CDecl Alias "sqlite3_value_nochange" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export
    If pArgument = 0 Then Return 0
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If (pMem->flags And (MEM_NULL Or MEM_ZERO)) = (MEM_NULL Or MEM_ZERO) Then Return 1
    Return 0
End Function

Function sqlite3_value_frombind CDecl Alias "sqlite3_value_frombind" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export
    If pArgument = 0 Then Return 0
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If (pMem->flags And MEM_FROM_BIND) <> 0 Then Return 1
    Return 0
End Function

Function sqlite3_value_dup CDecl Alias "sqlite3_value_dup" ( _
    ByVal pArgument As Const SqliteVdbeMem Ptr _
) As Any Ptr Export

    If pArgument = 0 Then Return 0
    Dim pOriginal As Const SqliteVdbeMem Ptr = pArgument
    Dim pNewValue As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, _
        sqlite3VdbeApiMalloc64(CULngInt(SizeOf(SqliteVdbeMem))))
    If pNewValue = 0 Then Return 0
    sqlite3VdbeApiMemset(pNewValue, 0, SizeOf(SqliteVdbeMem))

    pNewValue->u = pOriginal->u
    pNewValue->z = pOriginal->z
    pNewValue->n = pOriginal->n
    pNewValue->flags = pOriginal->flags And Not MEM_DYN
    pNewValue->enc = pOriginal->enc
    pNewValue->eSubtype = pOriginal->eSubtype
    pNewValue->db = 0

    If (pNewValue->flags And (MEM_STR Or MEM_BLOB)) <> 0 Then
        pNewValue->flags = pNewValue->flags And Not (MEM_STATIC Or MEM_DYN)
        pNewValue->flags = pNewValue->flags Or MEM_EPHEM
        If sqlite3VdbeMemMakeWriteable(pNewValue) <> SQLITE_OK Then
            sqlite3ValueFree(pNewValue)
            Return 0
        End If
    ElseIf (pNewValue->flags And MEM_NULL) <> 0 Then
        ' Pointer values are intentionally duplicated as ordinary NULL values.
        pNewValue->flags = pNewValue->flags And Not (MEM_TERM Or MEM_SUBTYPE)
    End If
    Return pNewValue
End Function

Sub sqlite3_value_free CDecl Alias "sqlite3_value_free" ( _
    ByVal pArgument As Any Ptr _
) Export
    sqlite3ValueFree(pArgument)
End Sub

Function sqlite3_value_blob CDecl Alias "sqlite3_value_blob" ( _
    ByVal pArgument As Any Ptr _
) As Any Ptr Export
    If pArgument = 0 Then Return 0
    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pArgument)
    If (pMem->flags And (MEM_BLOB Or MEM_STR)) <> 0 Then
        If sqlite3VdbeMemExpandBlob(pMem) <> SQLITE_OK Then Return 0
        pMem->flags = pMem->flags Or MEM_BLOB
        If pMem->n <> 0 Then Return pMem->z
        Return 0
    End If
    Return CPtr(Any Ptr, sqlite3_value_text(pArgument))
End Function

Function sqlite3_value_text CDecl Alias "sqlite3_value_text" ( _
    ByVal pArgument As Any Ptr _
) As Const UByte Ptr Export
    Return CPtr(Const UByte Ptr, sqlite3ValueText(pArgument, SQLITE_UTF8))
End Function

Function sqlite3_value_text16 CDecl Alias "sqlite3_value_text16" ( _
    ByVal pArgument As Any Ptr _
) As Any Ptr Export
    Return sqlite3ValueText(pArgument, SQLITE_UTF16NATIVE)
End Function

Function sqlite3_value_text16le CDecl Alias "sqlite3_value_text16le" ( _
    ByVal pArgument As Any Ptr _
) As Any Ptr Export
    Return sqlite3ValueText(pArgument, SQLITE_UTF16LE)
End Function

Function sqlite3_value_text16be CDecl Alias "sqlite3_value_text16be" ( _
    ByVal pArgument As Any Ptr _
) As Any Ptr Export
    Return sqlite3ValueText(pArgument, SQLITE_UTF16BE)
End Function

Function sqlite3_value_bytes CDecl Alias "sqlite3_value_bytes" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export
    Return sqlite3ValueBytes(pArgument, SQLITE_UTF8)
End Function

Function sqlite3_value_bytes16 CDecl Alias "sqlite3_value_bytes16" ( _
    ByVal pArgument As Any Ptr _
) As SQLITE_C_INT Export
    Return sqlite3ValueBytes(pArgument, SQLITE_UTF16NATIVE)
End Function

Sub sqlite3VdbeValueListFree CDecl Alias "sqlite3VdbeValueListFree" ( _
    ByVal pToDelete As Any Ptr _
) Export
    sqlite3VdbeApiFree(pToDelete)
End Sub

/' Validate the private iterator payload before dereferencing application data. '/
Private Function valueFromValueList( _
    ByVal pValue As Any Ptr, _
    ByVal ppOut As Any Ptr Ptr, _
    ByVal advance As SQLITE_C_INT _
) As SQLITE_C_INT
    If ppOut = 0 Then Return SQLITE_MISUSE
    ppOut[0] = 0
    If pValue = 0 Then Return SQLITE_MISUSE

    Dim pMem As SqliteVdbeMem Ptr = CPtr(SqliteVdbeMem Ptr, pValue)
    If (pMem->flags And MEM_DYN) = 0 OrElse _
       pMem->xDel <> @sqlite3VdbeValueListFree Then Return SQLITE_ERROR

    Dim pList As SqliteValueList Ptr = CPtr(SqliteValueList Ptr, _
        sqlite3_value_pointer(pMem, StrPtr("ValueList")))
    If pList = 0 OrElse pList->pCsr = 0 OrElse pList->pOut = 0 OrElse _
       pList->pOut->db = 0 Then Return SQLITE_ERROR

    Dim rc As SQLITE_C_INT
    If advance <> 0 Then
        rc = sqlite3BtreeNext(pList->pCsr, 0)
    Else
        Dim ignoredEmpty As SQLITE_C_INT = 0
        rc = sqlite3BtreeFirst(pList->pCsr, @ignoredEmpty)
        If sqlite3BtreeEof(pList->pCsr) <> 0 Then rc = SQLITE_DONE
    End If
    If rc <> SQLITE_OK Then Return rc

    Dim payloadSize As u32 = sqlite3BtreePayloadSize(pList->pCsr)
    If payloadSize < 2 Then Return SQLITE_CORRUPT

    Dim rawRecord As SqliteVdbeMem
    sqlite3VdbeMemInit(@rawRecord, 0, MEM_NULL)
    rc = sqlite3VdbeMemFromBtreeZeroOffset(pList->pCsr, payloadSize, @rawRecord)
    If rc <> SQLITE_OK Then
        sqlite3VdbeMemRelease(@rawRecord)
        Return rc
    End If

    Dim zRecord As Const UByte Ptr = rawRecord.z
    Dim serialType As u32 = 0
    If zRecord = 0 Then
        sqlite3VdbeMemRelease(@rawRecord)
        Return SQLITE_CORRUPT
    End If
    Dim serialTypeBytes As u8 = sqlite3GetVarint32(zRecord + 1, @serialType)
    Dim dataOffset As u32 = 1 + serialTypeBytes
    If serialTypeBytes = 0 OrElse dataOffset > payloadSize Then
        sqlite3VdbeMemRelease(@rawRecord)
        Return SQLITE_CORRUPT
    End If

    Dim serialBytes As u32 = sqlite3VdbeSerialTypeLen(serialType)
    If serialBytes > payloadSize - dataOffset Then
        sqlite3VdbeMemRelease(@rawRecord)
        Return SQLITE_CORRUPT
    End If

    sqlite3VdbeSerialGet(zRecord + dataOffset, serialType, pList->pOut)
    pList->pOut->enc = pList->pOut->db->enc
    If (pList->pOut->flags And MEM_EPHEM) <> 0 Then _
        rc = sqlite3VdbeMemMakeWriteable(pList->pOut)
    sqlite3VdbeMemRelease(@rawRecord)

    If rc = SQLITE_OK Then ppOut[0] = pList->pOut
    Return rc
End Function

Function sqlite3_vtab_in_first CDecl Alias "sqlite3_vtab_in_first" ( _
    ByVal pValue As Any Ptr, _
    ByVal ppOut As Any Ptr Ptr _
) As SQLITE_C_INT Export
    Return valueFromValueList(pValue, ppOut, 0)
End Function

Function sqlite3_vtab_in_next CDecl Alias "sqlite3_vtab_in_next" ( _
    ByVal pValue As Any Ptr, _
    ByVal ppOut As Any Ptr Ptr _
) As SQLITE_C_INT Export
    Return valueFromValueList(pValue, ppOut, 1)
End Function

/' end of sqlite3_vdbe_api.bas '/
