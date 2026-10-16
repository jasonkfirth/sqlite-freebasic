/'
    Project: SQLite FreeBASIC port

    File: sqlite3_filename.bas

    Purpose:

        Create, inspect, and adjust filenames passed to SQLite VFS methods.

    Responsibilities:

        - Store database, URI parameter, journal, and WAL names in pager order.
        - Return pointers to the packed database, parameter, journal, and WAL parts.
        - Release filenames allocated by sqlite3_create_filename().
        - Apply the optional short-suffix rewrite for 8.3-compatible names.

    This file intentionally does NOT contain:

        - URI parsing for sqlite3_open().
        - Validation for pointers not produced by SQLite's filename APIs.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_numeric.bi"

Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal z As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_malloc64 CDecl Alias "sqlite3_malloc64" ( _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" ( _
    ByVal p As Any Ptr _
)
Declare Function sqlite3GetBoolean CDecl Alias "sqlite3GetBoolean" ( _
    ByVal z As Const ZString Ptr, _
    ByVal defaultValue As u8 _
) As u8
Declare Function sqlite3_uri_boolean CDecl Alias "sqlite3_uri_boolean" ( _
    ByVal zFilename As Const ZString Ptr, _
    ByVal zParam As Const ZString Ptr, _
    ByVal defaultValue As SQLITE_C_INT _
) As SQLITE_C_INT

Private Function filenameTextLength( _
    ByVal z As Const UByte Ptr _
) As sqlite3_uint64
    If z = 0 Then Return CULngInt(SQLITE_MAX_ALLOCATION_SIZE) + 1

    Dim length As sqlite3_uint64 = 0
    While z[length] <> 0
        If length >= CULngInt(SQLITE_MAX_ALLOCATION_SIZE) Then _
            Return CULngInt(SQLITE_MAX_ALLOCATION_SIZE) + 1
        length += 1
    Wend
    Return length
End Function

Private Function addFilenameSize( _
    ByRef total As sqlite3_uint64, _
    ByVal additional As sqlite3_uint64 _
) As SQLITE_C_INT
    Dim maximum As sqlite3_uint64 = CULngInt(SQLITE_MAX_ALLOCATION_SIZE)
    If total > maximum OrElse additional > maximum - total Then Return 0
    total += additional
    Return 1
End Function

Private Function appendText CDecl Alias "appendText" ( _
    ByVal pOut As UByte Ptr, _
    ByVal zText As Const ZString Ptr _
) As UByte Ptr
    If pOut = 0 OrElse zText = 0 Then Return 0

    Dim pText As Const UByte Ptr = CPtr(Const UByte Ptr, zText)
    Dim length As sqlite3_uint64 = filenameTextLength(pText)
    If length > CULngInt(SQLITE_MAX_ALLOCATION_SIZE) Then Return 0
    If length > 0 Then
        For byteIndex As sqlite3_uint64 = 0 To length - 1
            pOut[byteIndex] = pText[byteIndex]
        Next
    End If
    pOut[length] = 0
    Return pOut + length + 1
End Function

Private Function databaseName CDecl Alias "databaseName" ( _
    ByVal zName As Const ZString Ptr _
) As Const ZString Ptr
    Dim pName As Const UByte Ptr = CPtr(Const UByte Ptr, zName)

    ' VFS filenames point into a pager-owned buffer with four NUL bytes
    ' immediately before the database-name segment.
    While pName[-1] <> 0 OrElse pName[-2] <> 0 OrElse _
          pName[-3] <> 0 OrElse pName[-4] <> 0
        pName -= 1
    Wend

    Return CPtr(Const ZString Ptr, pName)
End Function

Private Function filenameStringEquals( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT
    If zLeft = 0 OrElse zRight = 0 Then Return 0
    Dim pLeft As Const UByte Ptr = CPtr(Const UByte Ptr, zLeft)
    Dim pRight As Const UByte Ptr = CPtr(Const UByte Ptr, zRight)
    Dim byteIndex As sqlite3_uint64 = 0
    While pLeft[byteIndex] <> 0 AndAlso pRight[byteIndex] <> 0
        If pLeft[byteIndex] <> pRight[byteIndex] Then Return 0
        byteIndex += 1
    Wend
    Return CInt(pLeft[byteIndex] = 0 AndAlso pRight[byteIndex] = 0)
End Function

Private Function uriParameter CDecl Alias "uriParameter" ( _
    ByVal zDatabase As Const ZString Ptr, _
    ByVal zParam As Const ZString Ptr _
) As Const ZString Ptr
    If zDatabase = 0 OrElse zParam = 0 Then Return 0

    Dim pName As Const UByte Ptr = CPtr(Const UByte Ptr, zDatabase)
    pName += sqlite3Strlen30(zDatabase) + 1
    While pName[0] <> 0
        Dim pValue As Const UByte Ptr = _
            pName + sqlite3Strlen30(CPtr(Const ZString Ptr, pName)) + 1
        If filenameStringEquals(CPtr(Const ZString Ptr, pName), zParam) <> 0 Then _
            Return CPtr(Const ZString Ptr, pValue)
        pName = pValue + sqlite3Strlen30(CPtr(Const ZString Ptr, pValue)) + 1
    Wend
    Return 0
End Function

Function sqlite3_create_filename CDecl Alias "sqlite3_create_filename" ( _
    ByVal zDatabase As Const ZString Ptr, _
    ByVal zJournal As Const ZString Ptr, _
    ByVal zWal As Const ZString Ptr, _
    ByVal nParam As SQLITE_C_INT, _
    ByVal azParam As Const ZString Ptr Ptr _
) As Const ZString Ptr Export
    If zDatabase = 0 OrElse zJournal = 0 OrElse zWal = 0 OrElse nParam < 0 Then _
        Return 0

    Dim parameterCount As sqlite3_uint64 = CULngInt(nParam) * 2
    Dim totalBytes As sqlite3_uint64 = 10
    Dim databaseLength As sqlite3_uint64 = _
        filenameTextLength(CPtr(Const UByte Ptr, zDatabase))
    Dim journalLength As sqlite3_uint64 = _
        filenameTextLength(CPtr(Const UByte Ptr, zJournal))
    Dim walLength As sqlite3_uint64 = _
        filenameTextLength(CPtr(Const UByte Ptr, zWal))

    If databaseLength > CULngInt(SQLITE_MAX_ALLOCATION_SIZE) OrElse _
       journalLength > CULngInt(SQLITE_MAX_ALLOCATION_SIZE) OrElse _
       walLength > CULngInt(SQLITE_MAX_ALLOCATION_SIZE) Then Return 0
    If addFilenameSize(totalBytes, databaseLength) = 0 OrElse _
       addFilenameSize(totalBytes, journalLength) = 0 OrElse _
       addFilenameSize(totalBytes, walLength) = 0 Then Return 0

    ' Every parameter needs at least its terminating NUL, so reject an
    ' impossible count before reading the caller's pointer array.
    If parameterCount > CULngInt(SQLITE_MAX_ALLOCATION_SIZE) - totalBytes Then _
        Return 0
    If parameterCount > 0 AndAlso CPtr(Any Ptr, azParam) = 0 Then Return 0

    If parameterCount > 0 Then
        For parameterIndex As sqlite3_uint64 = 0 To parameterCount - 1
            Dim zParam As Const ZString Ptr = azParam[parameterIndex]
            If zParam = 0 Then Return 0
            Dim parameterLength As sqlite3_uint64 = _
                filenameTextLength(CPtr(Const UByte Ptr, zParam))
            If parameterLength > CULngInt(SQLITE_MAX_ALLOCATION_SIZE) OrElse _
               addFilenameSize(totalBytes, parameterLength + 1) = 0 Then Return 0
        Next
    End If

    Dim pAllocation As UByte Ptr = CPtr(UByte Ptr, sqlite3_malloc64(totalBytes))
    If pAllocation = 0 Then Return 0
    For prefixIndex As SQLITE_C_INT = 0 To 3
        pAllocation[prefixIndex] = 0
    Next

    Dim pWrite As UByte Ptr = pAllocation + 4
    pWrite = appendText(pWrite, zDatabase)
    If pWrite = 0 Then
        sqlite3_free(pAllocation)
        Return 0
    End If
    If parameterCount > 0 Then
        For parameterIndex As sqlite3_uint64 = 0 To parameterCount - 1
            pWrite = appendText(pWrite, azParam[parameterIndex])
            If pWrite = 0 Then
                sqlite3_free(pAllocation)
                Return 0
            End If
        Next
    End If
    pWrite[0] = 0
    pWrite += 1
    pWrite = appendText(pWrite, zJournal)
    If pWrite = 0 Then
        sqlite3_free(pAllocation)
        Return 0
    End If
    pWrite = appendText(pWrite, zWal)
    If pWrite = 0 Then
        sqlite3_free(pAllocation)
        Return 0
    End If
    If pWrite + 2 <> pAllocation + totalBytes Then
        sqlite3_free(pAllocation)
        Return 0
    End If
    pWrite[0] = 0
    pWrite[1] = 0

    Return CPtr(Const ZString Ptr, pAllocation + 4)
End Function

Sub sqlite3_free_filename CDecl Alias "sqlite3_free_filename" ( _
    ByVal zFilename As Const ZString Ptr _
) Export
    If zFilename = 0 Then Exit Sub
    Dim pDatabase As Const UByte Ptr = _
        CPtr(Const UByte Ptr, databaseName(zFilename))
    sqlite3_free(CPtr(Any Ptr, pDatabase - 4))
End Sub

Function sqlite3_uri_parameter CDecl Alias "sqlite3_uri_parameter" ( _
    ByVal zFilename As Const ZString Ptr, _
    ByVal zParam As Const ZString Ptr _
) As Const ZString Ptr Export
    If zFilename = 0 OrElse zParam = 0 Then Return 0
    Return uriParameter(databaseName(zFilename), zParam)
End Function

Function sqlite3_uri_key CDecl Alias "sqlite3_uri_key" ( _
    ByVal zFilename As Const ZString Ptr, _
    ByVal parameterNumber As SQLITE_C_INT _
) As Const ZString Ptr Export
    If zFilename = 0 OrElse parameterNumber < 0 Then Return 0

    Dim pParam As Const UByte Ptr = CPtr(Const UByte Ptr, databaseName(zFilename))
    pParam += sqlite3Strlen30(CPtr(Const ZString Ptr, pParam)) + 1
    Dim currentNumber As SQLITE_C_INT = 0
    While pParam[0] <> 0 AndAlso currentNumber < parameterNumber
        pParam += sqlite3Strlen30(CPtr(Const ZString Ptr, pParam)) + 1
        pParam += sqlite3Strlen30(CPtr(Const ZString Ptr, pParam)) + 1
        currentNumber += 1
    Wend
    If pParam[0] = 0 Then Return 0
    Return CPtr(Const ZString Ptr, pParam)
End Function

Function sqlite3_uri_boolean CDecl Alias "sqlite3_uri_boolean" ( _
    ByVal zFilename As Const ZString Ptr, _
    ByVal zParam As Const ZString Ptr, _
    ByVal defaultValue As SQLITE_C_INT _
) As SQLITE_C_INT Export
    Dim defaultBoolean As u8 = CByte(defaultValue <> 0)
    Dim zValue As Const ZString Ptr = sqlite3_uri_parameter(zFilename, zParam)
    If zValue = 0 Then Return defaultBoolean
    Return sqlite3GetBoolean(zValue, defaultBoolean)
End Function

Function sqlite3_uri_int64 CDecl Alias "sqlite3_uri_int64" ( _
    ByVal zFilename As Const ZString Ptr, _
    ByVal zParam As Const ZString Ptr, _
    ByVal defaultValue As sqlite3_int64 _
) As sqlite3_int64 Export
    Dim zValue As Const ZString Ptr = sqlite3_uri_parameter(zFilename, zParam)
    If zValue = 0 Then Return defaultValue

    Dim parsedValue As sqlite3_int64
    If sqlite3DecOrHexToI64(zValue, @parsedValue) = 0 Then Return parsedValue
    Return defaultValue
End Function

Function sqlite3_filename_database CDecl Alias "sqlite3_filename_database" ( _
    ByVal zFilename As Const ZString Ptr _
) As Const ZString Ptr Export
    If zFilename = 0 Then Return 0
    Return databaseName(zFilename)
End Function

Function sqlite3_filename_journal CDecl Alias "sqlite3_filename_journal" ( _
    ByVal zFilename As Const ZString Ptr _
) As Const ZString Ptr Export
    If zFilename = 0 Then Return 0

    Dim zSegment As Const UByte Ptr = _
        CPtr(Const UByte Ptr, databaseName(zFilename))
    zSegment += sqlite3Strlen30(CPtr(Const ZString Ptr, zSegment)) + 1

    While zSegment[0] <> 0
        zSegment += sqlite3Strlen30(CPtr(Const ZString Ptr, zSegment)) + 1
        zSegment += sqlite3Strlen30(CPtr(Const ZString Ptr, zSegment)) + 1
    Wend

    Return CPtr(Const ZString Ptr, zSegment + 1)
End Function

Function sqlite3_filename_wal CDecl Alias "sqlite3_filename_wal" ( _
    ByVal zFilename As Const ZString Ptr _
) As Const ZString Ptr Export
#if defined(SQLITE_OMIT_WAL)
    Return 0
#else
    Dim zWal As Const ZString Ptr = sqlite3_filename_journal(zFilename)
    If zWal = 0 Then Return 0

    Dim pWal As Const UByte Ptr = CPtr(Const UByte Ptr, zWal)
    pWal += sqlite3Strlen30(zWal) + 1
    Return CPtr(Const ZString Ptr, pWal)
#endif
End Function

#if defined(SQLITE_ENABLE_8_3_NAMES)
Sub sqlite3FileSuffix3 CDecl Alias "sqlite3FileSuffix3" ( _
    ByVal zBaseFilename As Const ZString Ptr, _
    ByVal zFilename As ZString Ptr _
) Export

    If zFilename = 0 Then Exit Sub
#if SQLITE_ENABLE_8_3_NAMES < 2
    If zBaseFilename = 0 Then Exit Sub
    If sqlite3_uri_boolean(zBaseFilename, StrPtr("8_3_names"), 0) = 0 Then Exit Sub
#endif

    Dim z As UByte Ptr = CPtr(UByte Ptr, zFilename)
    Dim size As SQLITE_C_INT = sqlite3Strlen30(CPtr(Const ZString Ptr, zFilename))
    If size <= 0 Then Exit Sub

    Dim i As SQLITE_C_INT = size - 1
    While i > 0 AndAlso z[i] <> Asc("/") AndAlso z[i] <> Asc(".")
        i -= 1
    Wend
    If z[i] <> Asc(".") OrElse size <= i + 4 Then Exit Sub

    ' The replacement suffix ends with the original NUL byte. Copying from
    ' left to right is safe because the shortened destination precedes it.
    Dim sourceIndex As SQLITE_C_INT = size - 3
    For byteIndex As SQLITE_C_INT = 0 To 3
        z[i + 1 + byteIndex] = z[sourceIndex + byteIndex]
    Next
End Sub
#endif

/' end of sqlite3_filename.bas '/
