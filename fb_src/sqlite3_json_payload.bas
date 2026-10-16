/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_payload.bas

    Purpose:

        Decode JSONB node headers and validate their payload spans.

    Responsibilities:

        - Decode compact, 1-byte, 2-byte, 4-byte, and constrained 8-byte sizes.
        - Check header and payload bounds against current and pending edit sizes.
        - Provide the common, inline-shaped, and semi-inline helper entry points.

    This file intentionally does NOT contain:

        - Recursive JSONB validation, traversal, or JSON text conversion.
'/ 

#lang "fb"
#include once "sqlite3_json_parse.bi"

Private Function jsonPayloadFits( _
    ByVal pParse As Const JsonParse Ptr, _
    ByVal index As u32, _
    ByVal payloadSize As u32, _
    ByVal headerSize As u32 _
) As SQLITE_C_INT
    If pParse = 0 Then Return 0
    Dim endOffset As sqlite3_uint64 = _
        CULngInt(index) + CULngInt(payloadSize) + CULngInt(headerSize)
    Dim actualLimit As sqlite3_uint64 = CULngInt(pParse->nBlob)
    Dim adjustedLimit As sqlite3_int64 = _
        CLngInt(pParse->nBlob) - CLngInt(pParse->delta)
    If endOffset > actualLimit AndAlso _
       (adjustedLimit < 0 OrElse endOffset > CULngInt(adjustedLimit)) Then Return 0
    Return 1
End Function

Function jsonbPayloadSizeWide CDecl Alias "jsonbPayloadSizeWide" ( _
    ByVal pParse As Const JsonParse Ptr, _
    ByVal index As u32, _
    ByVal pPayloadSize As u32 Ptr, _
    ByVal headerType As u8 _
) As u32 Export
    If pPayloadSize = 0 Then Return 0
    pPayloadSize[0] = 0
    If pParse = 0 OrElse pParse->aBlob = 0 OrElse _
       index >= pParse->nBlob OrElse headerType < 13 OrElse headerType > 15 Then _
        Return 0

    Dim payloadSize As u32
    Dim headerSize As u32
    If headerType = 13 Then
        If pParse->nBlob - index <= 2 Then Return 0
        payloadSize = (CULng(pParse->aBlob[index + 1]) Shl 8) Or _
                      CULng(pParse->aBlob[index + 2])
        headerSize = 3
    ElseIf headerType = 14 Then
        If pParse->nBlob - index <= 4 Then Return 0
        payloadSize = (CULng(pParse->aBlob[index + 1]) Shl 24) Or _
                      (CULng(pParse->aBlob[index + 2]) Shl 16) Or _
                      (CULng(pParse->aBlob[index + 3]) Shl 8) Or _
                      CULng(pParse->aBlob[index + 4])
        headerSize = 5
    Else
        If pParse->nBlob - index <= 8 OrElse _
           pParse->aBlob[index + 1] <> 0 OrElse _
           pParse->aBlob[index + 2] <> 0 OrElse _
           pParse->aBlob[index + 3] <> 0 OrElse _
           pParse->aBlob[index + 4] <> 0 Then Return 0
        payloadSize = (CULng(pParse->aBlob[index + 5]) Shl 24) Or _
                      (CULng(pParse->aBlob[index + 6]) Shl 16) Or _
                      (CULng(pParse->aBlob[index + 7]) Shl 8) Or _
                      CULng(pParse->aBlob[index + 8])
        headerSize = 9
    End If

    If jsonPayloadFits(pParse, index, payloadSize, headerSize) = 0 Then Return 0
    pPayloadSize[0] = payloadSize
    Return headerSize
End Function

Function jsonbPayloadSize CDecl Alias "jsonbPayloadSize" ( _
    ByVal pParse As Const JsonParse Ptr, _
    ByVal index As u32, _
    ByVal pPayloadSize As u32 Ptr _
) As u32 Export
    If pPayloadSize = 0 Then Return 0
    pPayloadSize[0] = 0
    If pParse = 0 OrElse pParse->aBlob = 0 OrElse index >= pParse->nBlob Then Return 0

    Dim headerType As u8 = pParse->aBlob[index] Shr 4
    Dim payloadSize As u32
    Dim headerSize As u32
    If headerType <= 11 Then
        payloadSize = headerType
        headerSize = 1
    ElseIf headerType = 12 Then
        If pParse->nBlob - index <= 1 Then Return 0
        payloadSize = pParse->aBlob[index + 1]
        headerSize = 2
    Else
        Return jsonbPayloadSizeWide(pParse, index, pPayloadSize, headerType)
    End If

    If jsonPayloadFits(pParse, index, payloadSize, headerSize) = 0 Then Return 0
    pPayloadSize[0] = payloadSize
    Return headerSize
End Function

Function jsonbPayloadSizeInline CDecl Alias "jsonbPayloadSizeInline" ( _
    ByVal pParse As Const JsonParse Ptr, _
    ByVal index As u32, _
    ByVal pPayloadSize As u32 Ptr _
) As u32 Export
    Return jsonbPayloadSize(pParse, index, pPayloadSize)
End Function

Function jsonbPayloadSizeSemiInline CDecl Alias "jsonbPayloadSizeSemiInline" ( _
    ByVal pParse As Const JsonParse Ptr, _
    ByVal index As u32, _
    ByVal pPayloadSize As u32 Ptr _
) As u32 Export
    Return jsonbPayloadSize(pParse, index, pPayloadSize)
End Function

/' end of sqlite3_json_payload.bas '/
