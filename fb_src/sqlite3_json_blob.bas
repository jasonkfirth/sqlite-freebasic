/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_blob.bas

    Purpose:

        Build and resize JSONB nodes in a JsonParse buffer.

    Responsibilities:

        - Grow owned JSONB storage within SQLite's allocation limit.
        - Copy borrowed JSONB data into editable storage when requested.
        - Append node headers and payloads using SQLite's compact size encoding.
        - Patch node payload sizes after their contents have been emitted.

    This file intentionally does NOT contain:

        - JSON text parsing, JSONB validation, or path and edit operations.
'/ 

#lang "fb"
#include once "sqlite3_json_parse.bi"
#include once "sqlite3_constants.bi"

Extern "C"
    Declare Function jsonBlobMemcpy CDecl Alias "memcpy" ( _
        ByVal pDestination As Any Ptr, _
        ByVal pSource As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
    Declare Function jsonBlobMemmove CDecl Alias "memmove" ( _
        ByVal pDestination As Any Ptr, _
        ByVal pSource As Const Any Ptr, _
        ByVal nByte As SQLITE_SIZE_T _
    ) As Any Ptr
End Extern

Private Sub jsonBlobSetOom(ByVal pParse As JsonParse Ptr)
    If pParse <> 0 Then pParse->oom = 1
End Sub

Function jsonBlobExpand CDecl Alias "jsonBlobExpand" ( _
    ByVal pParse As JsonParse Ptr, _
    ByVal requiredSize As sqlite3_uint64 _
) As SQLITE_C_INT Export
    If pParse = 0 Then Return 1
    If pParse->oom <> 0 Then Return 1
    If pParse->nBlobAlloc <> 0 Then
        If pParse->aBlob = 0 OrElse pParse->nBlob > pParse->nBlobAlloc Then
            jsonBlobSetOom(pParse)
            Return 1
        End If
        If requiredSize <= CULngInt(pParse->nBlobAlloc) Then Return 0
    End If

    Dim maximumSize As sqlite3_uint64 = CULngInt(SQLITE_MAX_ALLOCATION_SIZE)
    If requiredSize > maximumSize OrElse pParse->db = 0 OrElse _
       (pParse->nBlobAlloc = 0 AndAlso pParse->aBlob <> 0) Then
        jsonBlobSetOom(pParse)
        Return 1
    End If

    Dim newSize As sqlite3_uint64 = 100
    If pParse->nBlobAlloc <> 0 Then _
        newSize = CULngInt(pParse->nBlobAlloc) * 2
    If newSize < requiredSize Then
        If requiredSize > maximumSize - 100 Then
            jsonBlobSetOom(pParse)
            Return 1
        End If
        newSize = requiredSize + 100
    End If
    If newSize >= &H7FFFFFFF OrElse newSize > maximumSize Then
        jsonBlobSetOom(pParse)
        Return 1
    End If

    Dim pNew As UByte Ptr = CPtr(UByte Ptr, _
        sqlite3DbRealloc(pParse->db, pParse->aBlob, newSize))
    If pNew = 0 Then
        jsonBlobSetOom(pParse)
        Return 1
    End If
    pParse->aBlob = pNew
    pParse->nBlobAlloc = CUInt(newSize)
    Return 0
End Function

Function jsonBlobMakeEditable CDecl Alias "jsonBlobMakeEditable" ( _
    ByVal pParse As JsonParse Ptr, _
    ByVal extraBytes As u32 _
) As SQLITE_C_INT Export
    If pParse = 0 OrElse pParse->bReadOnly <> 0 Then Return 0
    If pParse->oom <> 0 Then Return 0
    If pParse->nBlobAlloc > 0 Then Return 1
    If pParse->nBlob > 0 AndAlso pParse->aBlob = 0 Then
        jsonBlobSetOom(pParse)
        Return 0
    End If

    Dim oldBlob As UByte Ptr = pParse->aBlob
    Dim requiredSize As sqlite3_uint64 = _
        CULngInt(pParse->nBlob) + CULngInt(extraBytes)
    pParse->aBlob = 0
    If jsonBlobExpand(pParse, requiredSize) <> 0 Then Return 0
    If pParse->nBlob > 0 Then _
        jsonBlobMemcpy(pParse->aBlob, oldBlob, pParse->nBlob)
    Return 1
End Function

Sub jsonBlobExpandAndAppendOneByte CDecl Alias "jsonBlobExpandAndAppendOneByte" ( _
    ByVal pParse As JsonParse Ptr, _
    ByVal value As u8 _
) Export
    If pParse = 0 OrElse pParse->nBlob = &HFFFFFFFFUL Then
        jsonBlobSetOom(pParse)
        Exit Sub
    End If
    Dim requiredSize As sqlite3_uint64 = CULngInt(pParse->nBlob) + 1
    If jsonBlobExpand(pParse, requiredSize) <> 0 Then Exit Sub
    pParse->aBlob[pParse->nBlob] = value
    pParse->nBlob += 1
End Sub

Sub jsonBlobAppendOneByte CDecl Alias "jsonBlobAppendOneByte" ( _
    ByVal pParse As JsonParse Ptr, _
    ByVal value As u8 _
) Export
    If pParse = 0 OrElse pParse->oom <> 0 Then Exit Sub
    If pParse->nBlob >= pParse->nBlobAlloc Then
        jsonBlobExpandAndAppendOneByte(pParse, value)
    ElseIf pParse->aBlob <> 0 Then
        pParse->aBlob[pParse->nBlob] = value
        pParse->nBlob += 1
    Else
        jsonBlobSetOom(pParse)
    End If
End Sub

Sub jsonBlobExpandAndAppendNode CDecl Alias "jsonBlobExpandAndAppendNode" ( _
    ByVal pParse As JsonParse Ptr, _
    ByVal nodeType As u8, _
    ByVal payloadSize As sqlite3_uint64, _
    ByVal pPayload As Const Any Ptr _
) Export
    If pParse = 0 Then Exit Sub
    Dim maximumSize As sqlite3_uint64 = CULngInt(SQLITE_MAX_ALLOCATION_SIZE)
    If payloadSize > maximumSize OrElse _
       CULngInt(pParse->nBlob) > maximumSize - payloadSize OrElse _
       CULngInt(pParse->nBlob) + payloadSize > maximumSize - 9 Then
        jsonBlobSetOom(pParse)
        Exit Sub
    End If
    Dim requiredSize As sqlite3_uint64 = _
        CULngInt(pParse->nBlob) + payloadSize + 9
    If jsonBlobExpand(pParse, requiredSize) <> 0 Then Exit Sub
    jsonBlobAppendNode(pParse, nodeType, payloadSize, pPayload)
End Sub

Sub jsonBlobAppendNode CDecl Alias "jsonBlobAppendNode" ( _
    ByVal pParse As JsonParse Ptr, _
    ByVal nodeType As u8, _
    ByVal payloadSize As sqlite3_uint64, _
    ByVal pPayload As Const Any Ptr _
) Export
    If pParse = 0 OrElse pParse->oom <> 0 Then Exit Sub
    If nodeType > &HF OrElse payloadSize > CULngInt(SQLITE_MAX_ALLOCATION_SIZE) Then
        jsonBlobSetOom(pParse)
        Exit Sub
    End If
    Dim maximumSize As sqlite3_uint64 = CULngInt(SQLITE_MAX_ALLOCATION_SIZE)
    If CULngInt(pParse->nBlob) > maximumSize - payloadSize OrElse _
       CULngInt(pParse->nBlob) + payloadSize > maximumSize - 9 Then
        jsonBlobSetOom(pParse)
        Exit Sub
    End If
    If pParse->nBlobAlloc = 0 OrElse _
       CULngInt(pParse->nBlob) + payloadSize + 9 > pParse->nBlobAlloc Then
        jsonBlobExpandAndAppendNode(pParse, nodeType, payloadSize, pPayload)
        Exit Sub
    End If

    Dim startOffset As sqlite3_uint64 = CULngInt(pParse->nBlob)
    Dim pOutput As UByte Ptr = pParse->aBlob + startOffset
    Dim headerBytes As SQLITE_C_INT
    If payloadSize <= 11 Then
        pOutput[0] = nodeType Or (CULng(payloadSize) Shl 4)
        headerBytes = 1
    ElseIf payloadSize <= &HFF Then
        pOutput[0] = nodeType Or &HC0
        pOutput[1] = CByte(payloadSize And &HFF)
        headerBytes = 2
    ElseIf payloadSize <= &HFFFF Then
        pOutput[0] = nodeType Or &HD0
        pOutput[1] = CByte((payloadSize Shr 8) And &HFF)
        pOutput[2] = CByte(payloadSize And &HFF)
        headerBytes = 3
    Else
        pOutput[0] = nodeType Or &HE0
        pOutput[1] = CByte((payloadSize Shr 24) And &HFF)
        pOutput[2] = CByte((payloadSize Shr 16) And &HFF)
        pOutput[3] = CByte((payloadSize Shr 8) And &HFF)
        pOutput[4] = CByte(payloadSize And &HFF)
        headerBytes = 5
    End If
    pParse->nBlob += CUInt(headerBytes)

    If pPayload <> 0 Then
        If payloadSize > 0 Then
            jsonBlobMemcpy(pParse->aBlob + pParse->nBlob, pPayload, payloadSize)
        End If
        pParse->nBlob += CUInt(payloadSize)
    End If
End Sub

Function jsonBlobChangePayloadSize CDecl Alias "jsonBlobChangePayloadSize" ( _
    ByVal pParse As JsonParse Ptr, _
    ByVal nodeOffset As u32, _
    ByVal payloadSize As u32 _
) As SQLITE_C_INT Export
    If pParse = 0 OrElse pParse->oom <> 0 Then Return 0
    If pParse->aBlob = 0 OrElse nodeOffset >= pParse->nBlob Then Return 0

    Dim pNode As UByte Ptr = pParse->aBlob + nodeOffset
    Dim oldSizeClass As UByte = pNode[0] Shr 4
    Dim extraBytes As SQLITE_C_INT
    Select Case oldSizeClass
    Case Is <= 11
        extraBytes = 0
    Case 12
        extraBytes = 1
    Case 13
        extraBytes = 2
    Case 14
        extraBytes = 4
    Case Else
        extraBytes = 8
    End Select

    Dim neededBytes As SQLITE_C_INT
    If payloadSize <= 11 Then
        neededBytes = 0
    ElseIf payloadSize <= &HFF Then
        neededBytes = 1
    ElseIf payloadSize <= &HFFFF Then
        neededBytes = 2
    Else
        neededBytes = 4
    End If
    Dim sizeDelta As SQLITE_C_INT = neededBytes - extraBytes

    If sizeDelta > 0 Then
        Dim newSize As sqlite3_uint64 = CULngInt(pParse->nBlob) + sizeDelta
        If newSize > pParse->nBlobAlloc AndAlso _
           jsonBlobExpand(pParse, newSize) <> 0 Then Return 0
        pNode = pParse->aBlob + nodeOffset
        jsonBlobMemmove(pNode + 1 + sizeDelta, pNode + 1, _
                        CULngInt(pParse->nBlob - (nodeOffset + 1)))
    ElseIf sizeDelta < 0 Then
        Dim oldPayloadOffset As SQLITE_C_INT = 1 - sizeDelta
        If CULngInt(nodeOffset) + oldPayloadOffset > pParse->nBlob Then Return 0
        jsonBlobMemmove(pNode + 1, pNode + oldPayloadOffset, _
                        CULngInt(pParse->nBlob - nodeOffset - oldPayloadOffset))
    End If
    If sizeDelta <> 0 Then _
        pParse->nBlob = CUInt(CLngInt(pParse->nBlob) + sizeDelta)
    pNode = pParse->aBlob + nodeOffset

    If neededBytes = 0 Then
        pNode[0] = (pNode[0] And &HF) Or CByte((payloadSize Shl 4) And &HF0)
    ElseIf neededBytes = 1 Then
        pNode[0] = (pNode[0] And &HF) Or &HC0
        pNode[1] = CByte(payloadSize And &HFF)
    ElseIf neededBytes = 2 Then
        pNode[0] = (pNode[0] And &HF) Or &HD0
        pNode[1] = CByte((payloadSize Shr 8) And &HFF)
        pNode[2] = CByte(payloadSize And &HFF)
    Else
        pNode[0] = (pNode[0] And &HF) Or &HE0
        pNode[1] = CByte((payloadSize Shr 24) And &HFF)
        pNode[2] = CByte((payloadSize Shr 16) And &HFF)
        pNode[3] = CByte((payloadSize Shr 8) And &HFF)
        pNode[4] = CByte(payloadSize And &HFF)
    End If
    Return sizeDelta
End Function

/' end of sqlite3_json_blob.bas '/
