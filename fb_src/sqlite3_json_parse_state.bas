/'
    Project: SQLite FreeBASIC port

    File: sqlite3_json_parse_state.bas

    Purpose:

        Manage JSON parse-state ownership and the small per-statement cache.

    Responsibilities:

        - Release owned JSON text and JSONB buffers.
        - Maintain JsonParse reference counts.
        - Insert and search cached text-to-JSONB translations through VDBE auxdata.

    This file intentionally does NOT contain:

        - JSON parsing, JSONB conversion, cache invalidation policy, or SQL JSON callbacks.
'/ 

#lang "fb"
#include once "sqlite3_json_parse.bi"
#include once "sqlite3_json_string.bi"
#include once "sqlite3_constants.bi"

Declare Sub sqlite3RCStrUnref CDecl Alias "sqlite3RCStrUnref" (ByVal zData As Any Ptr)
Declare Function sqlite3_context_db_handle CDecl Alias "sqlite3_context_db_handle" (ByVal pContext As Any Ptr) As Any Ptr
Declare Function sqlite3_get_auxdata CDecl Alias "sqlite3_get_auxdata" (ByVal pContext As Any Ptr, ByVal argumentIndex As SQLITE_C_INT) As Any Ptr
Declare Sub sqlite3_set_auxdata CDecl Alias "sqlite3_set_auxdata" (ByVal pContext As Any Ptr, ByVal argumentIndex As SQLITE_C_INT, ByVal pAuxData As Any Ptr, ByVal pDelete As Any Ptr)
Declare Function sqlite3_value_type CDecl Alias "sqlite3_value_type" (ByVal pValue As Any Ptr) As SQLITE_C_INT
Declare Function sqlite3_value_text CDecl Alias "sqlite3_value_text" (ByVal pValue As Any Ptr) As Const ZString Ptr
Declare Function sqlite3_value_bytes CDecl Alias "sqlite3_value_bytes" (ByVal pValue As Any Ptr) As SQLITE_C_INT

/' ------------------------------------------------------------------------- '/
/' Parse-state lifetime '/
/' ------------------------------------------------------------------------- '/

Sub jsonParseReset CDecl Alias "jsonParseReset" ( _
    ByVal pParse As JsonParse Ptr _
) Export
    If pParse = 0 Then Exit Sub
    ' A cached parse must remain intact until its last holder releases it.
    If pParse->nJPRef > 1 Then Exit Sub
    If pParse->bJsonIsRCStr <> 0 Then
        If pParse->zJson <> 0 Then sqlite3RCStrUnref(pParse->zJson)
        pParse->zJson = 0
        pParse->nJson = 0
        pParse->bJsonIsRCStr = 0
    End If
    If pParse->nBlobAlloc <> 0 Then
        If pParse->aBlob <> 0 Then sqlite3DbFree(pParse->db, pParse->aBlob)
        pParse->aBlob = 0
        pParse->nBlob = 0
        pParse->nBlobAlloc = 0
    End If
End Sub

Sub jsonParseFree CDecl Alias "jsonParseFree" ( _
    ByVal pParse As JsonParse Ptr _
) Export
    If pParse = 0 Then Exit Sub
    If pParse->nJPRef > 1 Then
        pParse->nJPRef -= 1
        Exit Sub
    End If
    Dim db As sqlite3 Ptr = pParse->db
    jsonParseReset(pParse)
    sqlite3DbFree(db, pParse)
End Sub

/' ------------------------------------------------------------------------- '/
/' JSON translation cache '/
/' ------------------------------------------------------------------------- '/

Sub jsonCacheDelete CDecl Alias "jsonCacheDelete" ( _
    ByVal pCache As JsonCache Ptr _
) Export
    If pCache = 0 Then Exit Sub
    Dim entryCount As SQLITE_C_INT = pCache->nUsed
    If entryCount < 0 Then entryCount = 0
    If entryCount > JSON_CACHE_SIZE Then entryCount = JSON_CACHE_SIZE
    For i As SQLITE_C_INT = 0 To entryCount - 1
        jsonParseFree(pCache->a(i))
    Next
    sqlite3DbFree(pCache->db, pCache)
End Sub

Sub jsonCacheDeleteGeneric CDecl Alias "jsonCacheDeleteGeneric" ( _
    ByVal pCache As Any Ptr _
) Export
    jsonCacheDelete(CPtr(JsonCache Ptr, pCache))
End Sub

Function jsonCacheInsert CDecl Alias "jsonCacheInsert" ( _
    ByVal pContext As Any Ptr, _
    ByVal pParse As JsonParse Ptr _
) As SQLITE_C_INT Export
    If pContext = 0 OrElse pParse = 0 Then Return SQLITE_MISUSE
    If pParse->zJson = 0 OrElse pParse->bJsonIsRCStr = 0 OrElse _
       pParse->delta <> 0 OrElse pParse->nBlobAlloc = 0 Then _
        Return SQLITE_CORRUPT

    Dim db As sqlite3 Ptr = CPtr(sqlite3 Ptr, sqlite3_context_db_handle(pContext))
    If db = 0 OrElse pParse->db <> db Then Return SQLITE_MISUSE
    Dim pCache As JsonCache Ptr = CPtr(JsonCache Ptr, _
        sqlite3_get_auxdata(pContext, JSON_CACHE_ID))
    If pCache = 0 Then
        pCache = CPtr(JsonCache Ptr, sqlite3DbMallocZero(db, SizeOf(JsonCache)))
        If pCache = 0 Then Return SQLITE_NOMEM
        pCache->db = db
        sqlite3_set_auxdata(pContext, JSON_CACHE_ID, pCache, _
                            CPtr(Any Ptr, @jsonCacheDeleteGeneric))
        pCache = CPtr(JsonCache Ptr, sqlite3_get_auxdata(pContext, JSON_CACHE_ID))
        If pCache = 0 Then Return SQLITE_NOMEM
    End If
    If pCache->db <> db OrElse pCache->nUsed < 0 OrElse _
       pCache->nUsed > JSON_CACHE_SIZE Then Return SQLITE_CORRUPT

    If pCache->nUsed = JSON_CACHE_SIZE Then
        jsonParseFree(pCache->a(0))
        For i As SQLITE_C_INT = 1 To JSON_CACHE_SIZE - 1
            pCache->a(i - 1) = pCache->a(i)
        Next
        pCache->nUsed -= 1
    End If
    If pParse->nJPRef = &HFFFFFFFFUL Then Return SQLITE_TOOBIG
    pParse->eEdit = 0
    pParse->nJPRef += 1
    pParse->bReadOnly = 1
    pCache->a(pCache->nUsed) = pParse
    pCache->nUsed += 1
    Return SQLITE_OK
End Function

Private Function jsonCacheTextEqual( _
    ByVal zLeft As Const UByte Ptr, _
    ByVal zRight As Const UByte Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As SQLITE_C_INT
    If zLeft = 0 OrElse zRight = 0 OrElse nByte < 0 Then Return 0
    For i As SQLITE_C_INT = 0 To nByte - 1
        If zLeft[i] <> zRight[i] Then Return 0
    Next
    Return 1
End Function

Function jsonCacheSearch CDecl Alias "jsonCacheSearch" ( _
    ByVal pContext As Any Ptr, _
    ByVal pValue As Any Ptr _
) As JsonParse Ptr Export
    If pContext = 0 OrElse pValue = 0 Then Return 0
    If sqlite3_value_type(pValue) <> SQLITE_TEXT Then Return 0
    Dim zJson As Const ZString Ptr = sqlite3_value_text(pValue)
    If zJson = 0 Then Return 0
    Dim nJson As SQLITE_C_INT = sqlite3_value_bytes(pValue)
    If nJson < 0 Then Return 0

    Dim pCache As JsonCache Ptr = CPtr(JsonCache Ptr, _
        sqlite3_get_auxdata(pContext, JSON_CACHE_ID))
    If pCache = 0 OrElse pCache->nUsed <= 0 OrElse _
       pCache->nUsed > JSON_CACHE_SIZE Then Return 0

    Dim matchedIndex As SQLITE_C_INT = -1
    For i As SQLITE_C_INT = 0 To pCache->nUsed - 1
        If pCache->a(i) <> 0 AndAlso pCache->a(i)->zJson = zJson Then
            matchedIndex = i
            Exit For
        End If
    Next
    If matchedIndex < 0 Then
        For i As SQLITE_C_INT = 0 To pCache->nUsed - 1
            Dim pEntry As JsonParse Ptr = pCache->a(i)
            If pEntry <> 0 AndAlso pEntry->nJson = nJson AndAlso _
               jsonCacheTextEqual(CPtr(Const UByte Ptr, pEntry->zJson), _
                                  CPtr(Const UByte Ptr, zJson), nJson) <> 0 Then
                matchedIndex = i
                Exit For
            End If
        Next
    End If
    If matchedIndex < 0 Then Return 0

    Dim pMatch As JsonParse Ptr = pCache->a(matchedIndex)
    If matchedIndex < pCache->nUsed - 1 Then
        For i As SQLITE_C_INT = matchedIndex To pCache->nUsed - 2
            pCache->a(i) = pCache->a(i + 1)
        Next
        pCache->a(pCache->nUsed - 1) = pMatch
    End If
    If pMatch->delta <> 0 Then Return 0
    Return pMatch
End Function

/' end of sqlite3_json_parse_state.bas '/
