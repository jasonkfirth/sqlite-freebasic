/'
    Project: SQLite FreeBASIC port

    File: sqlite3_uri.bas

    Purpose:

        Resolve a database URI into the VFS, open flags, and packed filename
        consumed by the pager and VFS layers.

    Responsibilities:

        - Decode file URI paths and name/value parameters.
        - Apply the mode, cache, and VFS options understood by sqlite3_open_v2.
        - Allocate the same packed filename layout used by pager filenames.

    This file intentionally does NOT contain:

        - Process-wide sqlite3_config(SQLITE_CONFIG_URI) state.
        - URI parsing for ATTACH statements.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_vfs.bi"
#include once "sqlite3_util_numeric.bi"

Declare Function sqlite3_malloc64 CDecl Alias "sqlite3_malloc64" ( _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" ( _
    ByVal p As Any Ptr _
)
Declare Sub sqlite3_free_filename CDecl Alias "sqlite3_free_filename" ( _
    ByVal zFilename As Const ZString Ptr _
)
Declare Function sqlite3_mprintf CDecl Alias "sqlite3_mprintf" ( _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) As ZString Ptr
Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal z As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3UriConfigEnabled CDecl Alias "sqlite3UriConfigEnabled" () As SQLITE_C_INT

Private Function uriInputLength( _
    ByVal zInput As Const UByte Ptr _
) As sqlite3_uint64
    If zInput = 0 Then Return CULngInt(SQLITE_MAX_ALLOCATION_SIZE) + 1

    Dim length As sqlite3_uint64 = 0
    While zInput[length] <> 0
        If length >= CULngInt(SQLITE_MAX_ALLOCATION_SIZE) Then _
            Return CULngInt(SQLITE_MAX_ALLOCATION_SIZE) + 1
        length += 1
    Wend
    Return length
End Function

Private Function addUriAllocationSize( _
    ByRef total As sqlite3_uint64, _
    ByVal additional As sqlite3_uint64 _
) As SQLITE_C_INT
    Dim maximum As sqlite3_uint64 = CULngInt(SQLITE_MAX_ALLOCATION_SIZE)
    If total > maximum OrElse additional > maximum - total Then Return 0
    total += additional
    Return 1
End Function

Private Function uriIsHexDigit(ByVal value As UByte) As SQLITE_C_INT
    If value >= Asc("0") AndAlso value <= Asc("9") Then Return 1
    If value >= Asc("a") AndAlso value <= Asc("f") Then Return 1
    If value >= Asc("A") AndAlso value <= Asc("F") Then Return 1
    Return 0
End Function

Private Function uriTextEquals( _
    ByVal zText As Const UByte Ptr, _
    ByVal zExpected As Const ZString Ptr _
) As SQLITE_C_INT
    If zText = 0 OrElse zExpected = 0 Then Return 0
    Dim pExpected As Const UByte Ptr = CPtr(Const UByte Ptr, zExpected)
    Dim index As SQLITE_C_INT = 0
    While pExpected[index] <> 0
        If zText[index] <> pExpected[index] Then Return 0
        index += 1
    Wend
    Return CInt(zText[index] = 0)
End Function

Private Function uriHasPrefix( _
    ByVal zUri As Const UByte Ptr, _
    ByVal uriLength As sqlite3_uint64, _
    ByVal startIndex As SQLITE_C_INT, _
    ByVal zPrefix As Const ZString Ptr _
) As SQLITE_C_INT
    If zUri = 0 OrElse zPrefix = 0 OrElse startIndex < 0 Then Return 0
    Dim pPrefix As Const UByte Ptr = CPtr(Const UByte Ptr, zPrefix)
    Dim prefixLength As SQLITE_C_INT = 0
    While pPrefix[prefixLength] <> 0
        prefixLength += 1
    Wend
    If CULngInt(startIndex) + CULngInt(prefixLength) > uriLength Then Return 0
    For index As SQLITE_C_INT = 0 To prefixLength - 1
        If zUri[startIndex + index] <> pPrefix[index] Then Return 0
    Next
    Return 1
End Function

Function sqlite3ParseUri CDecl Alias "sqlite3ParseUri" ( _
    ByVal zDefaultVfs As Const ZString Ptr, _
    ByVal zUriText As Const ZString Ptr, _
    ByVal pFlags As SQLITE_C_UINT Ptr, _
    ByVal ppVfs As sqlite3_vfs Ptr Ptr, _
    ByVal pzFile As ZString Ptr Ptr, _
    ByVal pzErrMsg As ZString Ptr Ptr _
) As SQLITE_C_INT Export
    If zUriText = 0 OrElse pFlags = 0 OrElse ppVfs = 0 OrElse _
       pzFile = 0 OrElse pzErrMsg = 0 Then Return SQLITE_MISUSE

    ppVfs[0] = 0
    pzFile[0] = 0
    pzErrMsg[0] = 0

    Dim pUri As Const UByte Ptr = CPtr(Const UByte Ptr, zUriText)
    Dim nUri As sqlite3_uint64 = uriInputLength(pUri)
    If nUri > CULngInt(SQLITE_MAX_ALLOCATION_SIZE) - 8 Then Return SQLITE_NOMEM

    Dim flags As SQLITE_C_UINT = pFlags[0]
    Dim zVfs As Const ZString Ptr = zDefaultVfs
    Dim pAllocation As UByte Ptr = 0
    Dim pFile As UByte Ptr = 0
    Dim pVfs As sqlite3_vfs Ptr = 0
    Dim zError As ZString Ptr = 0
    Dim rc As SQLITE_C_INT = SQLITE_OK

    Dim isFileUri As SQLITE_C_INT = CInt( _
        (flags And SQLITE_OPEN_URI) <> 0 OrElse sqlite3UriConfigEnabled() <> 0)
    If isFileUri <> 0 AndAlso nUri >= 5 Then
        isFileUri = uriHasPrefix(pUri, nUri, 0, StrPtr("file:"))
    Else
        isFileUri = 0
    End If

    If isFileUri <> 0 Then
        Dim allocationBytes As sqlite3_uint64 = nUri + 8
        If nUri > 0 Then
            For inputIndex As sqlite3_uint64 = 0 To nUri - 1
                If pUri[inputIndex] = Asc("&") Then
                    If addUriAllocationSize(allocationBytes, 1) = 0 Then _
                        Return SQLITE_NOMEM
                End If
            Next
        End If

        flags Or= SQLITE_OPEN_URI
        pAllocation = CPtr(UByte Ptr, sqlite3_malloc64(allocationBytes))
        If pAllocation = 0 Then Return SQLITE_NOMEM
        For prefixIndex As SQLITE_C_INT = 0 To 3
            pAllocation[prefixIndex] = 0
        Next
        pFile = pAllocation + 4

        Dim iIn As LongInt = 5
        Dim iOut As LongInt = 0

#if defined(SQLITE_ALLOW_URI_AUTHORITY)
        If uriHasPrefix(pUri, nUri, 5, StrPtr("///")) <> 0 Then
            iIn = 7
            If uriHasPrefix(pUri, nUri, 7, StrPtr("///")) <> 0 Then iIn += 1
        ElseIf uriHasPrefix(pUri, nUri, 5, StrPtr("//localhost/")) <> 0 Then
            iIn = 16
        End If
#else
        If nUri > 6 AndAlso pUri[5] = Asc("/") AndAlso pUri[6] = Asc("/") Then
            iIn = 7
            While CULngInt(iIn) < nUri AndAlso pUri[iIn] <> 0 AndAlso _
                  pUri[iIn] <> Asc("/")
                iIn += 1
            Wend
            If iIn <> 7 AndAlso _
               (iIn <> 16 OrElse uriHasPrefix(pUri, nUri, 7, _
                                                StrPtr("localhost")) = 0) Then
                zError = sqlite3_mprintf(StrPtr("invalid uri authority: %.*s"), _
                    CLng(iIn - 7), CPtr(Const ZString Ptr, pUri + 7))
                rc = SQLITE_ERROR
            End If
        End If
#endif

        If rc = SQLITE_OK Then
            Dim eState As SQLITE_C_INT = 0
            While CULngInt(iIn) < nUri AndAlso pUri[iIn] <> 0 AndAlso _
                  pUri[iIn] <> Asc("#")
                Dim c As SQLITE_C_INT = pUri[iIn]
                iIn += 1

                If c = Asc("%") AndAlso CULngInt(iIn + 1) < nUri AndAlso _
                   uriIsHexDigit(pUri[iIn]) <> 0 AndAlso _
                   uriIsHexDigit(pUri[iIn + 1]) <> 0 Then
                    Dim octet As SQLITE_C_INT = _
                        CInt(sqlite3HexToInt(pUri[iIn])) Shl 4
                    iIn += 1
                    octet += sqlite3HexToInt(pUri[iIn])
                    iIn += 1

                    If octet = 0 Then
#if defined(SQLITE_ENABLE_URI_00_ERROR)
                        zError = sqlite3_mprintf(StrPtr("unexpected %%00 in uri"))
                        rc = SQLITE_ERROR
                        Exit While
#else
                        While CULngInt(iIn) < nUri AndAlso pUri[iIn] <> 0 AndAlso _
                              pUri[iIn] <> Asc("#") AndAlso _
                              (eState <> 0 OrElse pUri[iIn] <> Asc("?")) AndAlso _
                              (eState <> 1 OrElse _
                                (pUri[iIn] <> Asc("=") AndAlso _
                                 pUri[iIn] <> Asc("&"))) AndAlso _
                              (eState <> 2 OrElse pUri[iIn] <> Asc("&"))
                            iIn += 1
                        Wend
                        Continue While
#endif
                    End If
                    c = octet
                ElseIf eState = 1 AndAlso _
                       (c = Asc("&") OrElse c = Asc("=")) Then
                    If pFile[iOut - 1] = 0 Then
                        While CULngInt(iIn) < nUri AndAlso pUri[iIn] <> 0 AndAlso _
                              pUri[iIn] <> Asc("#") AndAlso _
                              pUri[iIn - 1] <> Asc("&")
                            iIn += 1
                        Wend
                        Continue While
                    End If
                    If c = Asc("&") Then
                        pFile[iOut] = 0
                        iOut += 1
                    Else
                        eState = 2
                    End If
                    c = 0
                ElseIf (eState = 0 AndAlso c = Asc("?")) OrElse _
                       (eState = 2 AndAlso c = Asc("&")) Then
                    c = 0
                    eState = 1
                End If

                pFile[iOut] = CByte(c)
                iOut += 1
            Wend

            If rc = SQLITE_OK Then
                If eState = 1 Then
                    pFile[iOut] = 0
                    iOut += 1
                End If
                For tailIndex As SQLITE_C_INT = 0 To 3
                    pFile[iOut + tailIndex] = 0
                Next

                Dim pOption As UByte Ptr = pFile + _
                    sqlite3Strlen30(CPtr(Const ZString Ptr, pFile)) + 1
                While pOption[0] <> 0
                    Dim nOption As SQLITE_C_INT = _
                        sqlite3Strlen30(CPtr(Const ZString Ptr, pOption))
                    Dim pValue As UByte Ptr = pOption + nOption + 1
                    Dim nValue As SQLITE_C_INT = _
                        sqlite3Strlen30(CPtr(Const ZString Ptr, pValue))
                    Dim mask As SQLITE_C_UINT = 0
                    Dim modeLimit As SQLITE_C_UINT = 0
                    Dim zModeType As Const ZString Ptr = 0

                    If nOption = 3 AndAlso _
                       uriTextEquals(pOption, StrPtr("vfs")) <> 0 Then
                        zVfs = CPtr(Const ZString Ptr, pValue)
                    ElseIf nOption = 5 AndAlso _
                           uriTextEquals(pOption, StrPtr("cache")) <> 0 Then
                        mask = SQLITE_OPEN_SHAREDCACHE Or SQLITE_OPEN_PRIVATECACHE
                        modeLimit = mask
                        zModeType = StrPtr("cache")
                        Dim mode As SQLITE_C_UINT = 0
                        If nValue = 6 AndAlso _
                           uriTextEquals(pValue, StrPtr("shared")) <> 0 Then
                            mode = SQLITE_OPEN_SHAREDCACHE
                        ElseIf nValue = 7 AndAlso _
                               uriTextEquals(pValue, StrPtr("private")) <> 0 Then
                            mode = SQLITE_OPEN_PRIVATECACHE
                        End If
                        If mode = 0 Then
                            zError = sqlite3_mprintf( _
                                StrPtr("no such %s mode: %s"), _
                                zModeType, CPtr(Const ZString Ptr, pValue))
                            rc = SQLITE_ERROR
                        ElseIf (mode And Not SQLITE_OPEN_MEMORY) > modeLimit Then
                            zError = sqlite3_mprintf( _
                                StrPtr("%s mode not allowed: %s"), _
                                zModeType, CPtr(Const ZString Ptr, pValue))
                            rc = SQLITE_PERM
                        Else
                            flags = (flags And Not mask) Or mode
                        End If
                    ElseIf nOption = 4 AndAlso _
                           uriTextEquals(pOption, StrPtr("mode")) <> 0 Then
                        mask = SQLITE_OPEN_READONLY Or SQLITE_OPEN_READWRITE Or _
                               SQLITE_OPEN_CREATE Or SQLITE_OPEN_MEMORY
                        modeLimit = mask And flags
                        zModeType = StrPtr("access")
                        Dim mode As SQLITE_C_UINT = 0
                        If nValue = 2 AndAlso _
                           uriTextEquals(pValue, StrPtr("ro")) <> 0 Then
                            mode = SQLITE_OPEN_READONLY
                        ElseIf nValue = 2 AndAlso _
                               uriTextEquals(pValue, StrPtr("rw")) <> 0 Then
                            mode = SQLITE_OPEN_READWRITE
                        ElseIf nValue = 3 AndAlso _
                               uriTextEquals(pValue, StrPtr("rwc")) <> 0 Then
                            mode = SQLITE_OPEN_READWRITE Or SQLITE_OPEN_CREATE
                        ElseIf nValue = 6 AndAlso _
                               uriTextEquals(pValue, StrPtr("memory")) <> 0 Then
                            mode = SQLITE_OPEN_MEMORY
                        End If
                        If mode = 0 Then
                            zError = sqlite3_mprintf( _
                                StrPtr("no such %s mode: %s"), _
                                zModeType, CPtr(Const ZString Ptr, pValue))
                            rc = SQLITE_ERROR
                        ElseIf (mode And Not SQLITE_OPEN_MEMORY) > modeLimit Then
                            zError = sqlite3_mprintf( _
                                StrPtr("%s mode not allowed: %s"), _
                                zModeType, CPtr(Const ZString Ptr, pValue))
                            rc = SQLITE_PERM
                        Else
                            flags = (flags And Not mask) Or mode
                        End If
                    End If

                    If rc <> SQLITE_OK Then Exit While
                    pOption = pValue + nValue + 1
                Wend
            End If
        End If
    Else
        Dim allocationBytes As sqlite3_uint64 = nUri + 8
        pAllocation = CPtr(UByte Ptr, sqlite3_malloc64(allocationBytes))
        If pAllocation = 0 Then Return SQLITE_NOMEM
        For prefixIndex As SQLITE_C_INT = 0 To 3
            pAllocation[prefixIndex] = 0
        Next
        pFile = pAllocation + 4
        If nUri > 0 Then
            For inputIndex As sqlite3_uint64 = 0 To nUri - 1
                pFile[inputIndex] = pUri[inputIndex]
            Next
        End If
        For tailIndex As SQLITE_C_INT = 0 To 3
            pFile[nUri + tailIndex] = 0
        Next
        flags And= Not SQLITE_OPEN_URI
    End If

    If rc = SQLITE_OK Then
        pVfs = sqlite3_vfs_find(zVfs)
        If pVfs = 0 Then
            zError = sqlite3_mprintf(StrPtr("no such vfs: %s"), zVfs)
            rc = SQLITE_ERROR
        End If
    End If

    If rc <> SQLITE_OK AndAlso pFile <> 0 Then
        sqlite3_free_filename(CPtr(Const ZString Ptr, pFile))
        pFile = 0
    End If

    pFlags[0] = flags
    ppVfs[0] = pVfs
    pzFile[0] = CPtr(ZString Ptr, pFile)
    pzErrMsg[0] = zError
    Return rc
End Function

/' end of sqlite3_uri.bas '/
