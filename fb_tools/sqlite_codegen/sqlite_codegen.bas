/'
    Project: SQLite FreeBASIC port tools

    File: sqlite_codegen.bas

    Purpose:

        Convert SQLite's generated C token, keyword, parser-rule, and opcode
        tables and selected global lookup data into FreeBASIC include files
        used by the native port.

    Responsibilities:

        - Convert Lemon TK_ definitions from parse.h into FreeBASIC defines.
        - Convert keyword arrays from keywordhash.h into immutable FB arrays.
        - Convert generated OP_ values from opcodes.h into FreeBASIC defines.
        - Convert OPFLG_JUMP metadata from opcodes.h into an immutable array.
        - Extract SQLite's ASCII lowercase and character-class maps from global.c.
        - Map selected Lemon productions and destructor-bearing nonterminals to IDs.
        - Validate names, dimensions, values, and duplicate token definitions.

    This file intentionally does NOT contain:

        - A general-purpose C parser or C-to-FreeBASIC source translator.
        - SQLite runtime or test code.
'/

#lang "fb"

Private Const MODE_TOKENS As Integer = 1
Private Const MODE_KEYWORDS As Integer = 2
Private Const MODE_CLASSES As Integer = 3
Private Const ARRAY_CHAR As Integer = 1
Private Const ARRAY_NUMBER As Integer = 2
Private Const ARRAY_TOKEN As Integer = 3
Private Const ARRAY_SIGNED_NUMBER As Integer = 4

Private Type PragmaTableEntry
    name As String
    typeCode As ULongInt
    flags As ULongInt
    columnStart As ULongInt
    columnCount As ULongInt
    argument As ULongInt
End Type

Private Sub ReportError(ByVal message As String)
    Print "sqlite_codegen: " & message
    End 1
End Sub

Private Function IsSpaceByte(ByVal c As Integer) As Integer
    Select Case c
    Case 9, 10, 13, 32
        Return -1
    End Select
    Return 0
End Function

Private Function IsAsciiDigit(ByVal c As Integer) As Integer
    Return CInt(c >= Asc("0") AndAlso c <= Asc("9"))
End Function

Private Function IsAsciiAlpha(ByVal c As Integer) As Integer
    Return CInt((c >= Asc("A") AndAlso c <= Asc("Z")) OrElse _
                (c >= Asc("a") AndAlso c <= Asc("z")))
End Function

Private Function ContainsIdentifier(ByRef sourceText As String, ByVal identifierText As String) As Integer
    Dim searchPosition As Integer = 1
    While searchPosition <= Len(sourceText)
        Dim foundPosition As Integer = InStr(searchPosition, sourceText, identifierText)
        If foundPosition = 0 Then Return 0

        Dim beforeIdentifier As Integer = 0
        If foundPosition > 1 Then
            Dim previousByte As Integer = Asc(sourceText, foundPosition - 1)
            beforeIdentifier = CInt(IsAsciiAlpha(previousByte) <> 0 OrElse _
                IsAsciiDigit(previousByte) <> 0 OrElse previousByte = Asc("_"))
        End If
        Dim afterPosition As Integer = foundPosition + Len(identifierText)
        Dim afterIdentifier As Integer = 0
        If afterPosition <= Len(sourceText) Then
            Dim nextByte As Integer = Asc(sourceText, afterPosition)
            afterIdentifier = CInt(IsAsciiAlpha(nextByte) <> 0 OrElse _
                IsAsciiDigit(nextByte) <> 0 OrElse nextByte = Asc("_"))
        End If
        If beforeIdentifier = 0 AndAlso afterIdentifier = 0 Then Return -1
        searchPosition = foundPosition + Len(identifierText)
    Wend
    Return 0
End Function

Private Function CsvField(ByVal value As String) As String
    Dim escaped As String = Chr(34)
    For position As Integer = 1 To Len(value)
        Dim currentByte As String = Mid(value, position, 1)
        escaped &= currentByte
        If currentByte = Chr(34) Then escaped &= currentByte
    Next
    Return escaped & Chr(34)
End Function

Private Function HexDigitValue(ByVal c As Integer) As Integer
    If c >= Asc("0") AndAlso c <= Asc("9") Then Return c - Asc("0")
    If c >= Asc("a") AndAlso c <= Asc("f") Then Return c - Asc("a") + 10
    If c >= Asc("A") AndAlso c <= Asc("F") Then Return c - Asc("A") + 10
    Return -1
End Function

Private Function FileNameOnly(ByVal path As String) As String
    Dim i As Integer
    For i = Len(path) To 1 Step -1
        Dim c As Integer = Asc(path, i)
        If c = Asc("/") OrElse c = Asc("\") Then Return Mid(path, i + 1)
    Next
    Return path
End Function

Private Function IsTokenName(ByVal tokenName As String) As Integer
    Dim i As Integer

    If Len(tokenName) < 4 Then Return 0
    If Left(tokenName, 3) <> "TK_" Then Return 0

    For i = 4 To Len(tokenName)
        Dim c As Integer = Asc(tokenName, i)
        If IsAsciiDigit(c) = 0 AndAlso IsAsciiAlpha(c) = 0 AndAlso c <> Asc("_") Then
            Return 0
        End If
    Next

    Return -1
End Function

Private Function IsOpcodeName(ByVal opcodeName As String) As Integer
    If Len(opcodeName) < 4 OrElse Left(opcodeName, 3) <> "OP_" Then Return 0
    For i As Integer = 4 To Len(opcodeName)
        Dim c As Integer = Asc(opcodeName, i)
        If IsAsciiDigit(c) = 0 AndAlso IsAsciiAlpha(c) = 0 AndAlso c <> Asc("_") Then Return 0
    Next
    Return -1
End Function

Private Function ParseOpcodeValue(ByVal valueText As String, ByRef value As UInteger) As Integer
    If Len(valueText) = 0 Then Return 0
    For i As Integer = 1 To Len(valueText)
        If IsAsciiDigit(Asc(valueText, i)) = 0 Then Return 0
    Next
    Dim parsed As LongInt = Val(valueText)
    If parsed < 0 OrElse parsed >= 255 Then Return 0
    value = CUInt(parsed)
    Return -1
End Function

Private Sub GenerateOpcodeDefines(ByVal inputPath As String, ByVal outputPath As String)
    Dim names() As String
    Dim values() As UInteger
    Dim opcodeProperties(0 To 255) As UByte
    ReDim names(0 To 255)
    ReDim values(0 To 255)
    For i As Integer = 0 To UBound(opcodeProperties)
        opcodeProperties(i) = 0
    Next
    Dim opcodeCount As Integer = 0
    Dim maxOpcode As Integer = -1
    Dim inputFile As Integer = FreeFile
    Open inputPath For Input As #inputFile
    Dim lineText As String

    While Not EOF(inputFile)
        Line Input #inputFile, lineText
        lineText = Trim(lineText)
        If Left(lineText, 8) = "#define " Then
            Dim rest As String = Mid(lineText, 9)
            Dim nameLength As Integer = 0
            While nameLength < Len(rest) AndAlso IsSpaceByte(Asc(rest, nameLength + 1)) = 0
                nameLength += 1
            Wend
            Dim opcodeName As String = Left(rest, nameLength)
            If IsOpcodeName(opcodeName) <> 0 Then
                Dim valueText As String = LTrim(Mid(rest, nameLength + 1))
                Dim valueLength As Integer = 0
                While valueLength < Len(valueText) AndAlso _
                      IsSpaceByte(Asc(valueText, valueLength + 1)) = 0 AndAlso _
                      Mid(valueText, valueLength + 1, 2) <> "/*"
                    valueLength += 1
                Wend
                Dim opcodeValue As UInteger
                If ParseOpcodeValue(Left(valueText, valueLength), opcodeValue) = 0 Then
                    Close #inputFile
                    ReportError("unsupported opcode value for " & opcodeName & " in " & inputPath)
                End If
                If opcodeValue > UBound(opcodeProperties) Then
                    Close #inputFile
                    ReportError("opcode value exceeds the configured property table")
                End If
                For i As Integer = 0 To opcodeCount - 1
                    If names(i) = opcodeName Then
                        Close #inputFile
                        ReportError("duplicate opcode definition " & opcodeName & " in " & inputPath)
                    End If
                    If values(i) = opcodeValue Then
                        Close #inputFile
                        ReportError("duplicate opcode value " & Trim(Str(opcodeValue)) & " in " & inputPath)
                    End If
                Next
                If opcodeCount >= UBound(names) Then
                    Close #inputFile
                    ReportError("opcode table exceeds the configured entry limit")
                End If
                names(opcodeCount) = opcodeName
                values(opcodeCount) = opcodeValue
                If CInt(opcodeValue) > maxOpcode Then maxOpcode = CInt(opcodeValue)
                Dim propertyStart As Integer = InStr(valueText, "/*")
                If propertyStart > 0 Then
                    Dim propertyText As String = LCase(LTrim(Mid(valueText, propertyStart + 2)))
                    If Left(propertyText, 4) = "jump" Then opcodeProperties(opcodeValue) = 1
                End If
                opcodeCount += 1
            End If
        End If
    Wend
    Close #inputFile
    If opcodeCount < 100 Then ReportError("opcode table appears incomplete in " & inputPath)

    Dim outputFile As Integer = FreeFile
    Open outputPath For Output As #outputFile
    Print #outputFile, "/'"
    Print #outputFile, "    Project: SQLite FreeBASIC port"
    Print #outputFile, ""
    Print #outputFile, "    File: " & FileNameOnly(outputPath)
    Print #outputFile, ""
    Print #outputFile, "    Purpose: Define opcode numbers and jump metadata from src/vdbe.c."
    Print #outputFile, "    Generated by fb_tools/sqlite_codegen/sqlite_codegen.bas."
    Print #outputFile, "    Do not edit this file by hand."
    Print #outputFile, "'/"
    Print #outputFile, ""
    For i As Integer = 0 To opcodeCount - 1
        Print #outputFile, "#define " & names(i) & " " & Trim(Str(values(i)))
    Next
    Print #outputFile, ""
    Print #outputFile, "#define SQLITE_OPCODE_COUNT " & Trim(Str(maxOpcode + 1))
    Print #outputFile, "#define OPFLG_JUMP 1"
    Print #outputFile, ""

    Dim propertyValues As String = ""
    For i As Integer = 0 To maxOpcode
        If i > 0 Then propertyValues &= ", "
        propertyValues &= Trim(Str(opcodeProperties(i)))
    Next
    Print #outputFile, "Dim Shared As Const UByte sqlite3OpcodeProperty(0 To " & _
        Trim(Str(maxOpcode)) & ") = {" & propertyValues & "}"
    Print #outputFile, ""
    Print #outputFile, "/' end of " & FileNameOnly(outputPath) & " '/"
    Close #outputFile
    Print "converted " & Trim(Str(opcodeCount)) & " opcode values; output " & outputPath
End Sub

Private Sub GenerateOpcodeNames(ByVal inputPath As String, ByVal outputPath As String)
    Dim names(0 To 255) As String
    Dim synopses(0 To 255) As String
    Dim nameCount As Integer = 0
    Dim maxOpcode As Integer = -1
    Dim inputFile As Integer = FreeFile
    Open inputPath For Input As #inputFile
    Dim lineText As String

    While Not EOF(inputFile)
        Line Input #inputFile, lineText
        lineText = Trim(lineText)
        If Left(lineText, 8) = "#define " Then
            Dim rest As String = Mid(lineText, 9)
            Dim nameLength As Integer = 0
            While nameLength < Len(rest) AndAlso IsSpaceByte(Asc(rest, nameLength + 1)) = 0
                nameLength += 1
            Wend
            Dim opcodeName As String = Left(rest, nameLength)
            If IsOpcodeName(opcodeName) <> 0 Then
                Dim valueText As String = LTrim(Mid(rest, nameLength + 1))
                Dim valueLength As Integer = 0
                While valueLength < Len(valueText) AndAlso _
                      IsSpaceByte(Asc(valueText, valueLength + 1)) = 0 AndAlso _
                      Mid(valueText, valueLength + 1, 2) <> "/*"
                    valueLength += 1
                Wend
                Dim opcodeValue As UInteger
                If ParseOpcodeValue(Left(valueText, valueLength), opcodeValue) = 0 OrElse _
                   opcodeValue > UBound(names) Then
                    Close #inputFile
                    ReportError("unsupported opcode value for " & opcodeName & " in " & inputPath)
                End If
                If names(opcodeValue) <> "" Then
                    Close #inputFile
                    ReportError("duplicate opcode value " & Trim(Str(opcodeValue)) & " in " & inputPath)
                End If
                names(opcodeValue) = Mid(opcodeName, 4)
                Dim synopsisPosition As Integer = InStr(LCase(lineText), "synopsis:")
                If synopsisPosition > 0 Then
                    Dim synopsisText As String = Mid(lineText, synopsisPosition + 9)
                    Dim commentEnd As Integer = InStr(synopsisText, "*/")
                    If commentEnd > 0 Then synopsisText = Left(synopsisText, commentEnd - 1)
                    synopsisText = Trim(synopsisText)
                    If InStr(synopsisText, "\") > 0 OrElse InStr(synopsisText, Chr(34)) > 0 Then
                        Close #inputFile
                        ReportError("unsupported character in opcode synopsis for " & opcodeName)
                    End If
                    synopses(opcodeValue) = synopsisText
                End If
                nameCount += 1
                If CInt(opcodeValue) > maxOpcode Then maxOpcode = CInt(opcodeValue)
            End If
        End If
    Wend
    Close #inputFile
    If nameCount < 100 OrElse maxOpcode < 0 Then _
        ReportError("opcode table appears incomplete in " & inputPath)
    For i As Integer = 0 To maxOpcode
        If names(i) = "" Then _
            ReportError("opcode table has a missing value " & Trim(Str(i)) & " in " & inputPath)
    Next

    Dim outputFile As Integer = FreeFile
    Open outputPath For Output As #outputFile
    Print #outputFile, "/'"
    Print #outputFile, "    Project: SQLite FreeBASIC port"
    Print #outputFile, ""
    Print #outputFile, "    File: " & FileNameOnly(outputPath)
    Print #outputFile, ""
    Print #outputFile, "    Purpose: Return the symbolic name for each generated VDBE opcode."
    Print #outputFile, "    Source: " & inputPath
    Print #outputFile, "    Generated by fb_tools/sqlite_codegen/sqlite_codegen.bas."
    Print #outputFile, "    Do not edit this file by hand."
    Print #outputFile, "'/"
    Print #outputFile, ""
    Print #outputFile, "#lang ""fb"""
    Print #outputFile, "#include once ""sqlite3_types.bi"""
    Print #outputFile, "#include once ""sqlite3_opcodes.bi"""
    Print #outputFile, ""
    Print #outputFile, "Function sqlite3OpcodeName CDecl Alias ""sqlite3OpcodeName"" ( _"
    Print #outputFile, "    ByVal opcode As SQLITE_C_INT _"
    Print #outputFile, ") As Const ZString Ptr Export"
    Print #outputFile, "    Select Case opcode"
    For i As Integer = 0 To maxOpcode
        Dim opcodeLiteral As String = names(i)
        If synopses(i) <> "" Then opcodeLiteral &= Chr(92) & "0" & synopses(i)
        Print #outputFile, "    Case " & Trim(Str(i)) & ": Return StrPtr(!""" & opcodeLiteral & """)"
    Next
    Print #outputFile, "    Case Else: Return StrPtr(""Unknown"")"
    Print #outputFile, "    End Select"
    Print #outputFile, "End Function"
    Print #outputFile, ""
    Print #outputFile, "/' end of " & FileNameOnly(outputPath) & " '/"
    Close #outputFile
    Print "converted " & Trim(Str(nameCount)) & " opcode names; output " & outputPath
End Sub

Private Function ParseTokenCode(ByVal codeText As String, ByRef code As UInteger) As Integer
    Dim i As Integer

    If Len(codeText) = 0 Then Return 0
    For i = 1 To Len(codeText)
        If IsAsciiDigit(Asc(codeText, i)) = 0 Then Return 0
    Next

    Dim value As LongInt = Val(codeText)
    If value < 1 OrElse value > 65535 Then Return 0
    code = CUInt(value)
    Return -1
End Function

Private Sub GenerateTokenDefines(ByVal inputPath As String, ByVal outputPath As String)
    Dim inputFile As Integer = FreeFile
    Open inputPath For Input As #inputFile

    Dim names() As String
    Dim values() As UInteger
    ReDim names(0 To 15)
    ReDim values(0 To 15)
    Dim tokenCount As Integer = 0
    Dim lineText As String

    While Not EOF(inputFile)
        Line Input #inputFile, lineText
        lineText = Trim(lineText)

        If Left(lineText, 8) = "#define " Then
            Dim remainder As String = Mid(lineText, 9)
            Dim p As Integer = 1

            While p <= Len(remainder) AndAlso IsSpaceByte(Asc(remainder, p)) = 0
                p += 1
            Wend

            Dim tokenName As String = Left(remainder, p - 1)
            While p <= Len(remainder) AndAlso IsSpaceByte(Asc(remainder, p))
                p += 1
            Wend

            Dim valueStart As Integer = p
            While p <= Len(remainder) AndAlso IsAsciiDigit(Asc(remainder, p))
                p += 1
            Wend

            Dim valueText As String = Mid(remainder, valueStart, p - valueStart)
            While p <= Len(remainder) AndAlso IsSpaceByte(Asc(remainder, p))
                p += 1
            Wend

            If Left(tokenName, 3) = "TK_" Then
                Dim tokenValue As UInteger
                If IsTokenName(tokenName) = 0 OrElse ParseTokenCode(valueText, tokenValue) = 0 OrElse p <= Len(remainder) Then
                    Close #inputFile
                    ReportError("invalid TK_ definition in " & inputPath & ": " & lineText)
                End If

                Dim i As Integer
                For i = 0 To tokenCount - 1
                    If names(i) = tokenName Then
                        Close #inputFile
                        ReportError("duplicate token name " & tokenName)
                    End If
                    If values(i) = tokenValue Then
                        Close #inputFile
                        ReportError("duplicate token number " & Trim(Str(tokenValue)))
                    End If
                Next

                If tokenCount > UBound(names) Then
                    ReDim Preserve names(0 To UBound(names) * 2 + 1)
                    ReDim Preserve values(0 To UBound(values) * 2 + 1)
                End If

                names(tokenCount) = tokenName
                values(tokenCount) = tokenValue
                tokenCount += 1
            End If
        End If
    Wend
    Close #inputFile

    If tokenCount = 0 Then ReportError("no TK_ definitions found in " & inputPath)

    Dim outputFile As Integer = FreeFile
    Open outputPath For Output As #outputFile
    Print #outputFile, "/'"
    Print #outputFile, "    Project: SQLite FreeBASIC port"
    Print #outputFile, ""
    Print #outputFile, "    File: " & FileNameOnly(outputPath)
    Print #outputFile, ""
    Print #outputFile, "    Purpose:"
    Print #outputFile, ""
    Print #outputFile, "        Provide token IDs generated from SQLite's Lemon grammar."
    Print #outputFile, ""
    Print #outputFile, "    Generated by fb_tools/sqlite_codegen/sqlite_codegen.bas."
    Print #outputFile, "    Do not edit this file by hand."
    Print #outputFile, "'/"
    Print #outputFile, ""
    Print #outputFile, "#ifndef SQLITE3_FB_TOKENS_BI"
    Print #outputFile, "#define SQLITE3_FB_TOKENS_BI"
    Print #outputFile, ""

    Dim i As Integer
    For i = 0 To tokenCount - 1
        Print #outputFile, "#define " & names(i) & " " & Trim(Str(values(i)))
    Next

    Print #outputFile, ""
    Print #outputFile, "#endif"
    Print #outputFile, ""
    Print #outputFile, "/' end of " & FileNameOnly(outputPath) & " '/"
    Close #outputFile

    Print "wrote " & Trim(Str(tokenCount)) & " token defines to " & outputPath
End Sub

Private Function SkipCWhitespaceAndComments(ByRef source As String, ByRef p As Integer) As Integer
    Dim n As Integer = Len(source)

    Do While p <= n
        If IsSpaceByte(Asc(source, p)) Then
            p += 1
        ElseIf Asc(source, p) = Asc("/") AndAlso p < n AndAlso Asc(source, p + 1) = Asc("*") Then
            p += 2
            Do While p < n AndAlso Not (Asc(source, p) = Asc("*") AndAlso Asc(source, p + 1) = Asc("/"))
                p += 1
            Loop
            If p >= n Then Return 0
            p += 2
        Else
            Exit Do
        End If
    Loop

    Return -1
End Function

Private Function ExtractCArray( _
    ByRef cText As String, _
    ByVal arrayName As String, _
    ByVal arrayKind As Integer, _
    ByRef declaredSize As Integer, _
    ByRef errorText As String _
) As String

    Dim declaration As String = arrayName & "["
    Dim searchStart As Integer = 1
    Dim declarationPos As Integer = 0
    Dim p As Integer = 0
    Dim sizeStart As Integer = 0

    Do
        declarationPos = InStr(searchStart, cText, declaration)
        If declarationPos = 0 Then Exit Do

        p = declarationPos + Len(declaration)
        sizeStart = p
        While p <= Len(cText) AndAlso IsAsciiDigit(Asc(cText, p))
            p += 1
        Wend
        If p > sizeStart AndAlso p <= Len(cText) AndAlso Asc(cText, p) = Asc("]") Then Exit Do
        searchStart = declarationPos + Len(declaration)
    Loop

    If declarationPos = 0 OrElse p = sizeStart OrElse p > Len(cText) OrElse Asc(cText, p) <> Asc("]") Then
        errorText = "invalid C array size for " & arrayName
        Return ""
    End If

    declaredSize = CInt(Val(Mid(cText, sizeStart, p - sizeStart)))
    If declaredSize <= 0 OrElse declaredSize > 4096 Then
        errorText = "unsupported C array size for " & arrayName
        Return ""
    End If

    Dim openBrace As Integer = InStr(p, cText, "{")
    If openBrace = 0 Then
        errorText = "missing initializer for " & arrayName
        Return ""
    End If
    Dim closeBrace As Integer = InStr(openBrace + 1, cText, "}")
    If closeBrace = 0 Then
        errorText = "unterminated initializer for " & arrayName
        Return ""
    End If

    Dim body As String = Mid(cText, openBrace + 1, closeBrace - openBrace - 1)
    p = 1
    Dim itemCount As Integer = 0
    Dim outputValues As String = ""

    While p <= Len(body)
        If SkipCWhitespaceAndComments(body, p) = 0 Then
            errorText = "unterminated comment in " & arrayName
            Return ""
        End If
        If p > Len(body) Then Exit While

        Dim item As String = ""
        Dim c As Integer = Asc(body, p)

        If arrayKind = ARRAY_CHAR Then
            If c <> Asc("'") OrElse p + 2 > Len(body) OrElse Asc(body, p + 2) <> Asc("'") Then
                errorText = "expected a single-character C literal in " & arrayName
                Return ""
            End If
            Dim charValue As Integer = Asc(body, p + 1)
            If charValue < 32 OrElse charValue > 126 Then
                errorText = "non-ASCII C literal in " & arrayName
                Return ""
            End If
            item = Trim(Str(charValue))
            p += 3
        ElseIf IsAsciiDigit(c) Then
            Dim valueStart As Integer = p
            While p <= Len(body) AndAlso IsAsciiDigit(Asc(body, p))
                p += 1
            Wend
            Dim valueText As String = Mid(body, valueStart, p - valueStart)
            Dim numericValue As LongInt = Val(valueText)
            Dim maxValue As LongInt = 255
            If arrayName = "aKWOffset" Then maxValue = 65535
            If numericValue > maxValue Then
                errorText = "numeric value outside target type in " & arrayName
                Return ""
            End If
            item = valueText
        ElseIf arrayKind = ARRAY_TOKEN AndAlso IsAsciiAlpha(c) Then
            Dim nameStart As Integer = p
            While p <= Len(body)
                c = Asc(body, p)
                If IsAsciiAlpha(c) = 0 AndAlso IsAsciiDigit(c) = 0 AndAlso c <> Asc("_") Then Exit While
                p += 1
            Wend
            item = Mid(body, nameStart, p - nameStart)
            If IsTokenName(item) = 0 Then
                errorText = "invalid token name in " & arrayName & ": " & item
                Return ""
            End If
        Else
            errorText = "unexpected initializer value in " & arrayName
            Return ""
        End If

        itemCount += 1
        If itemCount > declaredSize Then
            errorText = "too many initializer values in " & arrayName
            Return ""
        End If
        If itemCount > 1 Then outputValues &= ", "
        outputValues &= item

        If SkipCWhitespaceAndComments(body, p) = 0 Then
            errorText = "unterminated comment in " & arrayName
            Return ""
        End If
        If p <= Len(body) Then
            If Asc(body, p) <> Asc(",") Then
                errorText = "expected comma in " & arrayName
                Return ""
            End If
            p += 1
        End If
    Wend

    If itemCount = 0 Then
        errorText = "empty initializer in " & arrayName
        Return ""
    End If

    While itemCount < declaredSize
        outputValues &= ", 0"
        itemCount += 1
    Wend

    Return outputValues
End Function

Private Sub GenerateKeywordData(ByVal inputPath As String, ByVal outputPath As String)
    Dim inputFile As Integer = FreeFile
    Open inputPath For Input As #inputFile
    Dim sourceText As String = ""
    Dim lineText As String
    While Not EOF(inputFile)
        Line Input #inputFile, lineText
        sourceText &= lineText & Chr(10)
    Wend
    Close #inputFile

    Dim cNames(0 To 5) As String
    Dim fbNames(0 To 5) As String
    Dim typeNames(0 To 5) As String
    Dim kinds(0 To 5) As Integer
    Dim sizes(0 To 5) As Integer
    Dim initializers(0 To 5) As String
    Dim i As Integer

    cNames(0) = "zKWText"
    cNames(1) = "aKWHash"
    cNames(2) = "aKWNext"
    cNames(3) = "aKWLen"
    cNames(4) = "aKWOffset"
    cNames(5) = "aKWCode"

    fbNames(0) = "sqlite3KeywordText"
    fbNames(1) = "sqlite3KeywordHash"
    fbNames(2) = "sqlite3KeywordNext"
    fbNames(3) = "sqlite3KeywordLength"
    fbNames(4) = "sqlite3KeywordOffset"
    fbNames(5) = "sqlite3KeywordCodeTable"

    typeNames(0) = "UByte"
    typeNames(1) = "UByte"
    typeNames(2) = "UByte"
    typeNames(3) = "UByte"
    typeNames(4) = "UShort"
    typeNames(5) = "UByte"

    kinds(0) = ARRAY_CHAR
    kinds(1) = ARRAY_NUMBER
    kinds(2) = ARRAY_NUMBER
    kinds(3) = ARRAY_NUMBER
    kinds(4) = ARRAY_NUMBER
    kinds(5) = ARRAY_TOKEN

    Dim errorText As String
    For i = 0 To 5
        initializers(i) = ExtractCArray(sourceText, cNames(i), kinds(i), sizes(i), errorText)
        If Len(errorText) > 0 Then ReportError(errorText & " in " & inputPath)
    Next

    If sizes(5) < 2 OrElse sizes(5) <> sizes(2) OrElse sizes(5) <> sizes(3) OrElse _
       sizes(5) <> sizes(4) Then
        ReportError("keyword arrays have inconsistent dimensions")
    End If

    Dim outputFile As Integer = FreeFile
    Open outputPath For Output As #outputFile
    Print #outputFile, "/'"
    Print #outputFile, "    Project: SQLite FreeBASIC port"
    Print #outputFile, ""
    Print #outputFile, "    File: " & FileNameOnly(outputPath)
    Print #outputFile, ""
    Print #outputFile, "    Purpose:"
    Print #outputFile, ""
    Print #outputFile, "        Hold keyword tables generated from SQLite's tokenizer rules."
    Print #outputFile, ""
    Print #outputFile, "    Generated by fb_tools/sqlite_codegen/sqlite_codegen.bas."
    Print #outputFile, "    Do not edit this file by hand."
    Print #outputFile, "'/"
    Print #outputFile, ""
    Print #outputFile, "#include once ""sqlite3_tokens.bi"""
    Print #outputFile, ""

    For i = 0 To 5
        Print #outputFile, "Dim Shared As Const " & typeNames(i) & " " & fbNames(i) & _
            "(0 To " & Trim(Str(sizes(i) - 1)) & ") = {" & initializers(i) & "}"
    Next

    Print #outputFile, ""
    Print #outputFile, "#define SQLITE_N_KEYWORD " & Trim(Str(sizes(5) - 1))
    Print #outputFile, ""
    Print #outputFile, "/' end of " & FileNameOnly(outputPath) & " '/"
    Close #outputFile

    Print "wrote keyword data to " & outputPath
End Sub

Private Sub GenerateCharacterClasses(ByVal inputPath As String, ByVal outputPath As String)
    Dim inputFile As Integer = FreeFile
    Open inputPath For Input As #inputFile
    Dim sourceText As String = ""
    Dim lineText As String
    While Not EOF(inputFile)
        Line Input #inputFile, lineText
        sourceText &= lineText & Chr(10)
    Wend
    Close #inputFile

    Dim arrayPos As Integer = InStr(sourceText, "static const unsigned char aiClass[]")
    If arrayPos = 0 Then ReportError("missing aiClass table in " & inputPath)
    Dim asciiPos As Integer = InStr(arrayPos, sourceText, "#ifdef SQLITE_ASCII")
    If asciiPos = 0 Then ReportError("missing ASCII aiClass table in " & inputPath)
    Dim asciiEnd As Integer = InStr(asciiPos, sourceText, "#endif")
    If asciiEnd = 0 Then ReportError("unterminated ASCII aiClass table in " & inputPath)

    Dim rawTable As String = Mid(sourceText, asciiPos, asciiEnd - asciiPos)
    Dim tableValues(0 To 255) As UByte
    Dim valueCount As Integer = 0
    Dim p As Integer = 1

    While p <= Len(rawTable)
        If Asc(rawTable, p) = Asc("/") AndAlso p < Len(rawTable) AndAlso Asc(rawTable, p + 1) = Asc("*") Then
            p += 2
            Do While p < Len(rawTable) AndAlso Not (Asc(rawTable, p) = Asc("*") AndAlso Asc(rawTable, p + 1) = Asc("/"))
                p += 1
            Loop
            If p >= Len(rawTable) Then ReportError("unterminated comment in aiClass")
            p += 2
        ElseIf IsAsciiDigit(Asc(rawTable, p)) Then
            Dim valueStart As Integer = p
            While p <= Len(rawTable) AndAlso IsAsciiDigit(Asc(rawTable, p))
                p += 1
            Wend
            Dim value As LongInt = Val(Mid(rawTable, valueStart, p - valueStart))
            If value > 31 Then ReportError("invalid character class value in aiClass")
            If valueCount > UBound(tableValues) Then ReportError("too many character class entries in aiClass")
            tableValues(valueCount) = CByte(value)
            valueCount += 1
        Else
            p += 1
        End If
    Wend

    If valueCount <> 256 Then ReportError("expected 256 ASCII character classes, found " & Trim(Str(valueCount)))

    Dim initializer As String = ""
    Dim i As Integer
    For i = 0 To 255
        If i > 0 Then initializer &= ", "
        initializer &= Trim(Str(tableValues(i)))
    Next

    Dim outputFile As Integer = FreeFile
    Open outputPath For Output As #outputFile
    Print #outputFile, "/'"
    Print #outputFile, "    Project: SQLite FreeBASIC port"
    Print #outputFile, ""
    Print #outputFile, "    File: " & FileNameOnly(outputPath)
    Print #outputFile, ""
    Print #outputFile, "    Purpose:"
    Print #outputFile, ""
    Print #outputFile, "        Hold the ASCII byte classes used by SQLite's tokenizer."
    Print #outputFile, ""
    Print #outputFile, "    Generated by fb_tools/sqlite_codegen/sqlite_codegen.bas."
    Print #outputFile, "    Do not edit this file by hand."
    Print #outputFile, "'/"
    Print #outputFile, ""
    Print #outputFile, "Dim Shared As Const UByte sqlite3TokenCharacterClass(0 To 255) = {" & initializer & "}"
    Print #outputFile, ""
    Print #outputFile, "/' end of " & FileNameOnly(outputPath) & " '/"
    Close #outputFile

    Print "wrote 256 character classes to " & outputPath
End Sub

Private Sub GenerateGlobalData(ByVal inputPath As String, ByVal outputPath As String)
    Dim inputFile As Integer = FreeFile
    Open inputPath For Input As #inputFile
    Dim sourceText As String = ""
    Dim lineText As String
    While Not EOF(inputFile)
        Line Input #inputFile, lineText
        sourceText &= lineText & Chr(10)
    Wend
    Close #inputFile

    Dim arrayPosition As Integer = InStr(sourceText, "sqlite3UpperToLower[] = {")
    If arrayPosition = 0 Then ReportError("missing sqlite3UpperToLower table in " & inputPath)
    Dim asciiPosition As Integer = InStr(arrayPosition, sourceText, "#ifdef SQLITE_ASCII")
    If asciiPosition = 0 Then ReportError("missing ASCII sqlite3UpperToLower table in " & inputPath)
    Dim asciiEnd As Integer = InStr(asciiPosition, sourceText, "#endif")
    If asciiEnd = 0 Then ReportError("unterminated ASCII sqlite3UpperToLower table in " & inputPath)

    Dim rawTable As String = Mid(sourceText, asciiPosition, asciiEnd - asciiPosition)
    Dim tableValues(0 To 255) As UByte
    Dim valueCount As Integer = 0
    Dim position As Integer = 1
    While position <= Len(rawTable)
        If SkipCWhitespaceAndComments(rawTable, position) = 0 Then _
            ReportError("unterminated comment in sqlite3UpperToLower")
        If position > Len(rawTable) Then Exit While
        If IsAsciiDigit(Asc(rawTable, position)) Then
            Dim valueStart As Integer = position
            While position <= Len(rawTable) AndAlso IsAsciiDigit(Asc(rawTable, position))
                position += 1
            Wend
            Dim value As LongInt = Val(Mid(rawTable, valueStart, position - valueStart))
            If value < 0 OrElse value > 255 Then _
                ReportError("invalid byte value in sqlite3UpperToLower")
            If valueCount > UBound(tableValues) Then _
                ReportError("too many sqlite3UpperToLower entries")
            tableValues(valueCount) = CByte(value)
            valueCount += 1
        Else
            position += 1
        End If
    Wend
    If valueCount <> 256 Then _
        ReportError("expected 256 ASCII sqlite3UpperToLower entries, found " & Trim(Str(valueCount)))

    Dim initializer As String = ""
    For i As Integer = 0 To UBound(tableValues)
        If i > 0 Then initializer &= ", "
        initializer &= Trim(Str(tableValues(i)))
    Next

    Dim ctypePosition As Integer = InStr(sourceText, "sqlite3CtypeMap[256] = {")
    If ctypePosition = 0 Then ReportError("missing sqlite3CtypeMap table in " & inputPath)
    Dim ctypeOpen As Integer = InStr(ctypePosition, sourceText, "{")
    If ctypeOpen = 0 Then ReportError("missing sqlite3CtypeMap initializer in " & inputPath)
    Dim ctypeClose As Integer = 0
    Dim braceDepth As Integer = 1
    Dim comment As Integer = 0
    Dim quoteByte As Integer = 0
    position = ctypeOpen + 1
    While position <= Len(sourceText)
        Dim currentByte As Integer = Asc(sourceText, position)
        If comment <> 0 Then
            If currentByte = Asc("*") AndAlso position < Len(sourceText) AndAlso _
               Asc(sourceText, position + 1) = Asc("/") Then
                comment = 0
                position += 2
                Continue While
            End If
        ElseIf quoteByte <> 0 Then
            If currentByte = Asc(Chr(92)) Then
                position += 2
                Continue While
            ElseIf currentByte = quoteByte Then
                quoteByte = 0
            End If
        ElseIf currentByte = Asc("/") AndAlso position < Len(sourceText) AndAlso _
               Asc(sourceText, position + 1) = Asc("*") Then
            comment = -1
            position += 2
            Continue While
        ElseIf currentByte = Asc(Chr(34)) OrElse currentByte = Asc("'") Then
            quoteByte = currentByte
        ElseIf currentByte = Asc("{") Then
            braceDepth += 1
        ElseIf currentByte = Asc("}") Then
            braceDepth -= 1
            If braceDepth = 0 Then
                ctypeClose = position
                Exit While
            End If
        End If
        position += 1
    Wend
    If ctypeClose = 0 Then _
        ReportError("unterminated sqlite3CtypeMap initializer in " & inputPath)
    Dim rawCtype As String = Mid(sourceText, ctypeOpen + 1, ctypeClose - ctypeOpen - 1)
    Dim ctypeValues(0 To 255) As UByte
    Dim ctypeCount As Integer = 0
    position = 1
    While position <= Len(rawCtype)
        If SkipCWhitespaceAndComments(rawCtype, position) = 0 Then _
            ReportError("unterminated comment before sqlite3CtypeMap value at " & Trim(Str(position)))
        If position > Len(rawCtype) Then Exit While
        Dim value As LongInt = 0
        If position + 1 <= Len(rawCtype) AndAlso _
           Mid(LCase(rawCtype), position, 2) = "0x" Then
            position += 2
            Dim digitStart As Integer = position
            While position <= Len(rawCtype)
                Dim digit As Integer = HexDigitValue(Asc(rawCtype, position))
                If digit < 0 Then Exit While
                If value > (255 - digit) \ 16 Then _
                    ReportError("hex byte value outside target range in sqlite3CtypeMap")
                value = value * 16 + digit
                position += 1
            Wend
            If position = digitStart Then ReportError("invalid hex value in sqlite3CtypeMap")
        ElseIf IsAsciiDigit(Asc(rawCtype, position)) <> 0 Then
            Dim valueStart As Integer = position
            While position <= Len(rawCtype) AndAlso IsAsciiDigit(Asc(rawCtype, position)) <> 0
                position += 1
            Wend
            value = Val(Mid(rawCtype, valueStart, position - valueStart))
            If value > 255 Then ReportError("byte value outside target range in sqlite3CtypeMap")
        Else
            ReportError("unexpected initializer value in sqlite3CtypeMap")
        End If
        If ctypeCount > UBound(ctypeValues) Then _
            ReportError("too many sqlite3CtypeMap entries")
        ctypeValues(ctypeCount) = CByte(value)
        ctypeCount += 1
        If SkipCWhitespaceAndComments(rawCtype, position) = 0 Then _
            ReportError("unterminated comment after sqlite3CtypeMap value at " & Trim(Str(position)))
        If position <= Len(rawCtype) Then
            If Asc(rawCtype, position) <> Asc(",") Then _
                ReportError("expected comma in sqlite3CtypeMap")
            position += 1
        End If
    Wend
    If ctypeCount <> 256 Then _
        ReportError("expected 256 sqlite3CtypeMap entries, found " & Trim(Str(ctypeCount)))

    Dim ctypeInitializer As String = ""
    For i As Integer = 0 To UBound(ctypeValues)
        If i > 0 Then ctypeInitializer &= ", "
        ctypeInitializer &= Trim(Str(ctypeValues(i)))
    Next

    Dim outputFile As Integer = FreeFile
    Open outputPath For Output As #outputFile
    Print #outputFile, "/'"
    Print #outputFile, "    Project: SQLite FreeBASIC port"
    Print #outputFile, ""
    Print #outputFile, "    File: " & FileNameOnly(outputPath)
    Print #outputFile, ""
    Print #outputFile, "    Purpose: Hold global lookup data generated from src/global.c."
    Print #outputFile, ""
    Print #outputFile, "    Generated by fb_tools/sqlite_codegen/sqlite_codegen.bas."
    Print #outputFile, "    Do not edit this file by hand."
    Print #outputFile, "'/"
    Print #outputFile, ""
    Print #outputFile, "Dim Shared As Const UByte sqlite3UpperToLower(0 To 255) = {" & initializer & "}"
    Print #outputFile, "Dim Shared As Const UByte sqlite3CtypeMap(0 To 255) = {" & ctypeInitializer & "}"
    Print #outputFile, ""
    Print #outputFile, "/' end of " & FileNameOnly(outputPath) & " '/"
    Close #outputFile
    Print "wrote 256 lowercase-map bytes and 256 character-class bytes to " & outputPath
End Sub

Private Function ExtractNumericArray( _
    ByRef cText As String, _
    ByVal arrayName As String, _
    ByVal minValue As LongInt, _
    ByVal maxValue As LongInt, _
    ByRef itemCount As Integer, _
    ByRef errorText As String _
) As String

    Dim marker As String = arrayName & "[] = {"
    Dim declarationPos As Integer = InStr(cText, marker)
    If declarationPos = 0 Then
        errorText = "missing parser table " & arrayName
        Return ""
    End If

    Dim openBrace As Integer = declarationPos + Len(marker) - 1
    Dim closeBrace As Integer = InStr(openBrace + 1, cText, "}")
    If closeBrace = 0 Then
        errorText = "unterminated parser table " & arrayName
        Return ""
    End If

    Dim body As String = Mid(cText, openBrace + 1, closeBrace - openBrace - 1)
    Dim p As Integer = 1
    Dim values As String = ""
    itemCount = 0

    While p <= Len(body)
        If SkipCWhitespaceAndComments(body, p) = 0 Then
            errorText = "unterminated comment in parser table " & arrayName
            Return ""
        End If
        If p > Len(body) Then Exit While

        Dim itemStart As Integer = p
        If Asc(body, p) = Asc("-") Then p += 1
        Dim digitStart As Integer = p
        While p <= Len(body) AndAlso IsAsciiDigit(Asc(body, p))
            p += 1
        Wend
        If p = digitStart Then
            errorText = "invalid integer in parser table " & arrayName
            Return ""
        End If

        Dim item As String = Mid(body, itemStart, p - itemStart)
        Dim value As LongInt = Val(item)
        If value < minValue OrElse value > maxValue Then
            errorText = "value outside target type in parser table " & arrayName
            Return ""
        End If

        itemCount += 1
        If itemCount > 32767 Then
            errorText = "parser table is too large: " & arrayName
            Return ""
        End If
        If itemCount > 1 Then
            If itemCount Mod 16 = 1 Then
                values &= ", _" & Chr(10) & "    "
            Else
                values &= ", "
            End If
        End If
        values &= item

        If SkipCWhitespaceAndComments(body, p) = 0 Then
            errorText = "unterminated comment in parser table " & arrayName
            Return ""
        End If
        If p <= Len(body) Then
            If Asc(body, p) <> Asc(",") Then
                errorText = "expected comma in parser table " & arrayName
                Return ""
            End If
            p += 1
        End If
    Wend

    If itemCount = 0 Then errorText = "empty parser table " & arrayName
    Return values
End Function

Private Function ExtractParserDefine(ByRef cText As String, ByVal macroName As String, ByRef value As LongInt) As Integer
    Dim p As Integer
    Dim lineText As String
    Dim sourcePos As Integer = 1

    While sourcePos <= Len(cText)
        Dim lineEnd As Integer = InStr(sourcePos, cText, Chr(10))
        If lineEnd = 0 Then lineEnd = Len(cText) + 1
        lineText = Trim(Mid(cText, sourcePos, lineEnd - sourcePos))
        sourcePos = lineEnd + 1

        If Left(lineText, 8) = "#define " Then
            Dim remainder As String = Mid(lineText, 9)
            p = 1
            While p <= Len(remainder) AndAlso IsSpaceByte(Asc(remainder, p)) = 0
                p += 1
            Wend
            If Left(remainder, p - 1) = macroName Then
                While p <= Len(remainder) AndAlso IsSpaceByte(Asc(remainder, p))
                    p += 1
                Wend
                If p <= Len(remainder) AndAlso Asc(remainder, p) = Asc("(") Then p += 1
                While p <= Len(remainder) AndAlso IsSpaceByte(Asc(remainder, p))
                    p += 1
                Wend
                Dim valueStart As Integer = p
                If p <= Len(remainder) AndAlso Asc(remainder, p) = Asc("-") Then p += 1
                Dim digitStart As Integer = p
                While p <= Len(remainder) AndAlso IsAsciiDigit(Asc(remainder, p))
                    p += 1
                Wend
                If p = digitStart Then Return 0
                value = Val(Mid(remainder, valueStart, p - valueStart))
                Return 1
            End If
        End If
    Wend

    Return 0
End Function

Private Sub GenerateParserTables(ByVal inputPath As String, ByVal outputPath As String)
    Dim inputFile As Integer = FreeFile
    Open inputPath For Input As #inputFile
    Dim cText As String = ""
    Dim lineText As String
    While Not EOF(inputFile)
        Line Input #inputFile, lineText
        cText &= lineText & Chr(10)
    Wend
    Close #inputFile

    Dim macroNames(0 To 23) As String
    Dim macroValues(0 To 23) As LongInt
    macroNames(0) = "YYNOCODE"
    macroNames(1) = "YYWILDCARD"
    macroNames(2) = "YYNSTATE"
    macroNames(3) = "YYNRULE"
    macroNames(4) = "YYNRULE_WITH_ACTION"
    macroNames(5) = "YYNTOKEN"
    macroNames(6) = "YY_MAX_SHIFT"
    macroNames(7) = "YY_MIN_SHIFTREDUCE"
    macroNames(8) = "YY_MAX_SHIFTREDUCE"
    macroNames(9) = "YY_ERROR_ACTION"
    macroNames(10) = "YY_ACCEPT_ACTION"
    macroNames(11) = "YY_NO_ACTION"
    macroNames(12) = "YY_MIN_REDUCE"
    macroNames(13) = "YY_MAX_REDUCE"
    macroNames(14) = "YY_MIN_DSTRCTR"
    macroNames(15) = "YY_MAX_DSTRCTR"
    macroNames(16) = "YY_ACTTAB_COUNT"
    macroNames(17) = "YY_SHIFT_COUNT"
    macroNames(18) = "YY_SHIFT_MIN"
    macroNames(19) = "YY_SHIFT_MAX"
    macroNames(20) = "YY_REDUCE_COUNT"
    macroNames(21) = "YY_REDUCE_MIN"
    macroNames(22) = "YY_REDUCE_MAX"
    macroNames(23) = "YYSTACKDEPTH"

    Dim i As Integer
    For i = 0 To UBound(macroNames)
        If ExtractParserDefine(cText, macroNames(i), macroValues(i)) = 0 Then
            ReportError("missing or non-numeric parser macro " & macroNames(i))
        End If
    Next

    Dim cArrayNames(0 To 7) As String
    Dim fbArrayNames(0 To 7) As String
    Dim typeNames(0 To 7) As String
    Dim minValues(0 To 7) As LongInt
    Dim maxValues(0 To 7) As LongInt
    Dim itemCounts(0 To 7) As Integer
    Dim initializers(0 To 7) As String

    cArrayNames(0) = "yy_action"
    cArrayNames(1) = "yy_lookahead"
    cArrayNames(2) = "yy_shift_ofst"
    cArrayNames(3) = "yy_reduce_ofst"
    cArrayNames(4) = "yy_default"
    cArrayNames(5) = "yyFallback"
    cArrayNames(6) = "yyRuleInfoLhs"
    cArrayNames(7) = "yyRuleInfoNRhs"

    fbArrayNames(0) = "sqlite3YyAction"
    fbArrayNames(1) = "sqlite3YyLookahead"
    fbArrayNames(2) = "sqlite3YyShiftOfst"
    fbArrayNames(3) = "sqlite3YyReduceOfst"
    fbArrayNames(4) = "sqlite3YyDefault"
    fbArrayNames(5) = "sqlite3YyFallback"
    fbArrayNames(6) = "sqlite3YyRuleInfoLhs"
    fbArrayNames(7) = "sqlite3YyRuleInfoNRhs"

    typeNames(0) = "UShort"
    typeNames(1) = "UShort"
    typeNames(2) = "UShort"
    typeNames(3) = "Short"
    typeNames(4) = "UShort"
    typeNames(5) = "UShort"
    typeNames(6) = "UShort"
    typeNames(7) = "Byte"

    For i = 0 To 7
        minValues(i) = 0
        maxValues(i) = 65535
    Next
    minValues(3) = -32768
    maxValues(3) = 32767
    minValues(7) = -128
    maxValues(7) = 127

    Dim errorText As String
    For i = 0 To 7
        initializers(i) = ExtractNumericArray(cText, cArrayNames(i), minValues(i), _
            maxValues(i), itemCounts(i), errorText)
        If Len(errorText) > 0 Then ReportError(errorText & " in " & inputPath)
    Next

    If itemCounts(0) <> macroValues(16) OrElse itemCounts(1) < itemCounts(0) OrElse _
       itemCounts(2) <> macroValues(17) + 1 OrElse itemCounts(3) <> macroValues(20) + 1 OrElse _
       itemCounts(4) <> macroValues(2) OrElse itemCounts(5) <> macroValues(5) OrElse _
       itemCounts(6) <> macroValues(3) OrElse itemCounts(7) <> macroValues(3) Then
        ReportError("parser table lengths do not match Lemon's control macros")
    End If

    Dim outputFile As Integer = FreeFile
    Open outputPath For Output As #outputFile
    Print #outputFile, "/'"
    Print #outputFile, "    Project: SQLite FreeBASIC port"
    Print #outputFile, ""
    Print #outputFile, "    File: " & FileNameOnly(outputPath)
    Print #outputFile, ""
    Print #outputFile, "    Purpose:"
    Print #outputFile, ""
    Print #outputFile, "        Store Lemon's generated parser tables in FreeBASIC form."
    Print #outputFile, ""
    Print #outputFile, "    Generated by fb_tools/sqlite_codegen/sqlite_codegen.bas."
    Print #outputFile, "    Do not edit this file by hand."
    Print #outputFile, "'/"
    Print #outputFile, ""

    For i = 0 To UBound(macroNames)
        Print #outputFile, "#define " & macroNames(i) & " " & Trim(Str(macroValues(i)))
    Next
    Print #outputFile, ""

    For i = 0 To 7
        Print #outputFile, "Dim Shared As Const " & typeNames(i) & " " & fbArrayNames(i) & _
            "(0 To " & Trim(Str(itemCounts(i) - 1)) & ") = {" & initializers(i) & "}"
    Next

    Print #outputFile, ""
    Print #outputFile, "/' end of " & FileNameOnly(outputPath) & " '/"
    Close #outputFile

    Print "wrote parser tables to " & outputPath
End Sub

Private Sub GenerateParserRuleIds( _
    ByVal inputPath As String, _
    ByVal outputPath As String, _
    ByVal semanticSourcePath As String, _
    ByVal ledgerOutputPath As String _
)
    Dim inputFile As Integer = FreeFile
    Open inputPath For Input As #inputFile
    Dim cText As String = ""
    Dim lineText As String
    While Not EOF(inputFile)
        Line Input #inputFile, lineText
        cText &= lineText & Chr(10)
    Wend
    Close #inputFile

    Dim ruleMarker As String = "yyRuleName[] = {"
    Dim markerPosition As Integer = InStr(cText, ruleMarker)
    If markerPosition = 0 Then ReportError("missing yyRuleName table in " & inputPath)
    Dim bodyStart As Integer = markerPosition + Len(ruleMarker)
    Dim bodyEnd As Integer = InStr(bodyStart, cText, "};")
    If bodyEnd = 0 Then ReportError("unterminated yyRuleName table in " & inputPath)
    Dim body As String = Mid(cText, bodyStart, bodyEnd - bodyStart)

    Dim ruleNames(0 To 2047) As String
    Dim ruleCount As Integer = 0
    Dim position As Integer = 1
    While position <= Len(body)
        If Asc(body, position) <> Asc(Chr(34)) Then
            position += 1
            Continue While
        End If

        position += 1
        Dim ruleText As String = ""
        Dim closedString As Integer = 0
        While position <= Len(body)
            Dim valueByte As Integer = Asc(body, position)
            position += 1
            If valueByte = Asc(Chr(34)) Then
                closedString = 1
                Exit While
            ElseIf valueByte = Asc("\\") Then
                If position > Len(body) Then _
                    ReportError("unterminated escape in yyRuleName table")
                ruleText &= Chr(Asc(body, position))
                position += 1
            Else
                ruleText &= Chr(valueByte)
            End If
        Wend
        If closedString = 0 Then ReportError("unterminated string in yyRuleName table")
        If ruleCount > UBound(ruleNames) Then _
            ReportError("yyRuleName table exceeds the configured entry limit")
        ruleNames(ruleCount) = ruleText
        ruleCount += 1
    Wend
    If ruleCount < 100 Then ReportError("yyRuleName table appears incomplete in " & inputPath)

    Dim symbolMarker As String = "yyTokenName[] = {"
    Dim symbolMarkerPosition As Integer = InStr(cText, symbolMarker)
    If symbolMarkerPosition = 0 Then ReportError("missing yyTokenName table in " & inputPath)
    Dim symbolBodyStart As Integer = symbolMarkerPosition + Len(symbolMarker)
    Dim symbolBodyEnd As Integer = InStr(symbolBodyStart, cText, "};")
    If symbolBodyEnd = 0 Then ReportError("unterminated yyTokenName table in " & inputPath)
    Dim symbolBody As String = Mid( _
        cText, symbolBodyStart, symbolBodyEnd - symbolBodyStart)
    Dim symbolNames(0 To 2047) As String
    Dim symbolCount As Integer = 0
    position = 1
    While position <= Len(symbolBody)
        If Asc(symbolBody, position) <> Asc(Chr(34)) Then
            position += 1
            Continue While
        End If

        position += 1
        Dim symbolText As String = ""
        Dim closedString As Integer = 0
        While position <= Len(symbolBody)
            Dim valueByte As Integer = Asc(symbolBody, position)
            position += 1
            If valueByte = Asc(Chr(34)) Then
                closedString = 1
                Exit While
            ElseIf valueByte = Asc("\\") Then
                If position > Len(symbolBody) Then _
                    ReportError("unterminated escape in yyTokenName table")
                symbolText &= Chr(Asc(symbolBody, position))
                position += 1
            Else
                symbolText &= Chr(valueByte)
            End If
        Wend
        If closedString = 0 Then ReportError("unterminated string in yyTokenName table")
        If symbolCount > UBound(symbolNames) Then _
            ReportError("yyTokenName table exceeds the configured entry limit")
        symbolNames(symbolCount) = symbolText
        symbolCount += 1
    Wend
    If symbolCount < 100 Then _
        ReportError("yyTokenName table appears incomplete in " & inputPath)

    Dim selectedMacros(0 To 105) As String
    Dim selectedRules(0 To 105) As String
    selectedMacros(0) = "YYRULE_SCANPT_EMPTY"
    selectedRules(0) = "scanpt ::="
    selectedMacros(1) = "YYRULE_CMDX_CMD"
    selectedRules(1) = "cmdx ::= cmd"
    selectedMacros(2) = "YYRULE_CMD_SELECT"
    selectedRules(2) = "cmd ::= select"
    selectedMacros(3) = "YYRULE_SELECT_SELECTNOWITH"
    selectedRules(3) = "select ::= selectnowith"
    selectedMacros(4) = "YYRULE_ONESELECT"
    selectedRules(4) = "oneselect ::= SELECT distinct selcollist from where_opt groupby_opt having_opt orderby_opt limit_opt"
    selectedMacros(5) = "YYRULE_DISTINCT"
    selectedRules(5) = "distinct ::= DISTINCT"
    selectedMacros(6) = "YYRULE_ALL"
    selectedRules(6) = "distinct ::= ALL"
    selectedMacros(7) = "YYRULE_DISTINCT_EMPTY"
    selectedRules(7) = "distinct ::="
    selectedMacros(8) = "YYRULE_SCLP_EMPTY"
    selectedRules(8) = "sclp ::="
    selectedMacros(9) = "YYRULE_SELCOLLIST_EXPR"
    selectedRules(9) = "selcollist ::= sclp scanpt expr scanpt as"
    selectedMacros(10) = "YYRULE_AS_NM"
    selectedRules(10) = "as ::= AS nm"
    selectedMacros(11) = "YYRULE_AS_EMPTY"
    selectedRules(11) = "as ::="
    selectedMacros(12) = "YYRULE_FROM_EMPTY"
    selectedRules(12) = "from ::="
    selectedMacros(13) = "YYRULE_ORDERBY_EMPTY"
    selectedRules(13) = "orderby_opt ::="
    selectedMacros(14) = "YYRULE_GROUPBY_EMPTY"
    selectedRules(14) = "groupby_opt ::="
    selectedMacros(15) = "YYRULE_HAVING_EMPTY"
    selectedRules(15) = "having_opt ::="
    selectedMacros(16) = "YYRULE_LIMIT_EMPTY"
    selectedRules(16) = "limit_opt ::="
    selectedMacros(17) = "YYRULE_WHERE_EMPTY"
    selectedRules(17) = "where_opt ::="
    selectedMacros(18) = "YYRULE_EXPR_PAREN"
    selectedRules(18) = "expr ::= LP expr RP"
    selectedMacros(19) = "YYRULE_TERM_NULL_FLOAT_BLOB"
    selectedRules(19) = "term ::= NULL|FLOAT|BLOB"
    selectedMacros(20) = "YYRULE_TERM_STRING"
    selectedRules(20) = "term ::= STRING"
    selectedMacros(21) = "YYRULE_TERM_INTEGER"
    selectedRules(21) = "term ::= INTEGER"
    selectedMacros(22) = "YYRULE_EXPR_VARIABLE"
    selectedRules(22) = "expr ::= VARIABLE"
    selectedMacros(23) = "YYRULE_EXPR_AND"
    selectedRules(23) = "expr ::= expr AND expr"
    selectedMacros(24) = "YYRULE_EXPR_OR"
    selectedRules(24) = "expr ::= expr OR expr"
    selectedMacros(25) = "YYRULE_EXPR_RELATIONAL"
    selectedRules(25) = "expr ::= expr LT|GT|GE|LE expr"
    selectedMacros(26) = "YYRULE_EXPR_EQUALITY"
    selectedRules(26) = "expr ::= expr EQ|NE expr"
    selectedMacros(27) = "YYRULE_EXPR_BITWISE"
    selectedRules(27) = "expr ::= expr BITAND|BITOR|LSHIFT|RSHIFT expr"
    selectedMacros(28) = "YYRULE_EXPR_ADDITIVE"
    selectedRules(28) = "expr ::= expr PLUS|MINUS expr"
    selectedMacros(29) = "YYRULE_EXPR_MULTIPLICATIVE"
    selectedRules(29) = "expr ::= expr STAR|SLASH|REM expr"
    selectedMacros(30) = "YYRULE_EXPR_CONCAT"
    selectedRules(30) = "expr ::= expr CONCAT expr"
    selectedMacros(31) = "YYRULE_EXPR_NOT"
    selectedRules(31) = "expr ::= NOT expr"
    selectedMacros(32) = "YYRULE_EXPR_BITNOT"
    selectedRules(32) = "expr ::= BITNOT expr"
    selectedMacros(33) = "YYRULE_EXPR_UNARY_SIGN"
    selectedRules(33) = "expr ::= PLUS|MINUS expr"
    selectedMacros(34) = "YYRULE_SELECTNOWITH_ONESELECT"
    selectedRules(34) = "selectnowith ::= oneselect"
    selectedMacros(35) = "YYRULE_SCLP_SELCOLLIST_COMMA"
    selectedRules(35) = "sclp ::= selcollist COMMA"
    selectedMacros(36) = "YYRULE_AS_ID_STRING"
    selectedRules(36) = "as ::= ID|STRING"
    selectedMacros(37) = "YYRULE_EXPR_TERM"
    selectedRules(37) = "expr ::= term"
    selectedMacros(38) = "YYRULE_EXPRLIST_NEXPRLIST"
    selectedRules(38) = "exprlist ::= nexprlist"
    selectedMacros(39) = "YYRULE_VALUES_ROW"
    selectedRules(39) = "values ::= VALUES LP nexprlist RP"
    selectedMacros(40) = "YYRULE_ONSELECT_VALUES"
    selectedRules(40) = "oneselect ::= values"
    selectedMacros(41) = "YYRULE_ONSELECT_MVALUES"
    selectedRules(41) = "oneselect ::= mvalues"
    selectedMacros(42) = "YYRULE_MVALUES_FIRST_ROW"
    selectedRules(42) = "mvalues ::= values COMMA LP nexprlist RP"
    selectedMacros(43) = "YYRULE_MVALUES_NEXT_ROW"
    selectedRules(43) = "mvalues ::= mvalues COMMA LP nexprlist RP"
    selectedMacros(44) = "YYRULE_NEXPRLIST_APPEND"
    selectedRules(44) = "nexprlist ::= nexprlist COMMA expr"
    selectedMacros(45) = "YYRULE_NEXPRLIST_FIRST"
    selectedRules(45) = "nexprlist ::= expr"
    selectedMacros(46) = "YYRULE_LIMIT_EXPR"
    selectedRules(46) = "limit_opt ::= LIMIT expr"
    selectedMacros(47) = "YYRULE_LIMIT_OFFSET"
    selectedRules(47) = "limit_opt ::= LIMIT expr OFFSET expr"
    selectedMacros(48) = "YYRULE_LIMIT_COMMA"
    selectedRules(48) = "limit_opt ::= LIMIT expr COMMA expr"
    selectedMacros(49) = "YYRULE_WHERE_EXPR"
    selectedRules(49) = "where_opt ::= WHERE expr"
    selectedMacros(50) = "YYRULE_EXPR_NULL_TEST"
    selectedRules(50) = "expr ::= expr ISNULL|NOTNULL"
    selectedMacros(51) = "YYRULE_EXPR_NOT_NULL"
    selectedRules(51) = "expr ::= expr NOT NULL"
    selectedMacros(52) = "YYRULE_EXPR_IS"
    selectedRules(52) = "expr ::= expr IS expr"
    selectedMacros(53) = "YYRULE_EXPR_IS_NOT"
    selectedRules(53) = "expr ::= expr IS NOT expr"
    selectedMacros(54) = "YYRULE_EXPR_IS_NOT_DISTINCT"
    selectedRules(54) = "expr ::= expr IS NOT DISTINCT FROM expr"
    selectedMacros(55) = "YYRULE_EXPR_IS_DISTINCT"
    selectedRules(55) = "expr ::= expr IS DISTINCT FROM expr"
    selectedMacros(56) = "YYRULE_CAST_EXPR"
    selectedRules(56) = "expr ::= CAST LP expr AS typetoken RP"
    selectedMacros(57) = "YYRULE_TYPETOKEN_EMPTY"
    selectedRules(57) = "typetoken ::="
    selectedMacros(58) = "YYRULE_TYPETOKEN_PAREN"
    selectedRules(58) = "typetoken ::= typename LP signed RP"
    selectedMacros(59) = "YYRULE_TYPETOKEN_PAREN_TWO"
    selectedRules(59) = "typetoken ::= typename LP signed COMMA signed RP"
    selectedMacros(60) = "YYRULE_TYPENAME_APPEND"
    selectedRules(60) = "typename ::= typename ID|STRING"
    selectedMacros(61) = "YYRULE_TYPETOKEN_TYPENAME"
    selectedRules(61) = "typetoken ::= typename"
    selectedMacros(62) = "YYRULE_TYPENAME_IDS"
    selectedRules(62) = "typename ::= ID|STRING"
    selectedMacros(63) = "YYRULE_BETWEEN_OP"
    selectedRules(63) = "between_op ::= BETWEEN"
    selectedMacros(64) = "YYRULE_NOT_BETWEEN_OP"
    selectedRules(64) = "between_op ::= NOT BETWEEN"
    selectedMacros(65) = "YYRULE_EXPR_BETWEEN"
    selectedRules(65) = "expr ::= expr between_op expr AND expr"
    selectedMacros(66) = "YYRULE_EXPR_CASE"
    selectedRules(66) = "expr ::= CASE case_operand case_exprlist case_else END"
    selectedMacros(67) = "YYRULE_CASE_EXPRLIST_APPEND"
    selectedRules(67) = "case_exprlist ::= case_exprlist WHEN expr THEN expr"
    selectedMacros(68) = "YYRULE_CASE_EXPRLIST_FIRST"
    selectedRules(68) = "case_exprlist ::= WHEN expr THEN expr"
    selectedMacros(69) = "YYRULE_CASE_ELSE_EXPR"
    selectedRules(69) = "case_else ::= ELSE expr"
    selectedMacros(70) = "YYRULE_CASE_ELSE_EMPTY"
    selectedRules(70) = "case_else ::="
    selectedMacros(71) = "YYRULE_CASE_OPERAND_EMPTY"
    selectedRules(71) = "case_operand ::="
    selectedMacros(72) = "YYRULE_EXPR_FUNCTION"
    selectedRules(72) = "expr ::= ID|INDEXED|JOIN_KW LP distinct exprlist RP"
    selectedMacros(73) = "YYRULE_IN_OP_IN"
    selectedRules(73) = "in_op ::= IN"
    selectedMacros(74) = "YYRULE_IN_OP_NOT_IN"
    selectedRules(74) = "in_op ::= NOT IN"
    selectedMacros(75) = "YYRULE_EXPR_IN_LIST"
    selectedRules(75) = "expr ::= expr in_op LP exprlist RP"
    selectedMacros(76) = "YYRULE_EXPRLIST_EMPTY"
    selectedRules(76) = "exprlist ::="
    selectedMacros(77) = "YYRULE_SELECTNOWITH_COMPOUND"
    selectedRules(77) = "selectnowith ::= selectnowith multiselect_op oneselect"
    selectedMacros(78) = "YYRULE_MULTISELECT_UNION_ALL"
    selectedRules(78) = "multiselect_op ::= UNION ALL"
    selectedMacros(79) = "YYRULE_LIKEOP_NOT"
    selectedRules(79) = "likeop ::= NOT LIKE_KW|MATCH"
    selectedMacros(80) = "YYRULE_EXPR_LIKE"
    selectedRules(80) = "expr ::= expr likeop expr"
    selectedMacros(81) = "YYRULE_EXPR_LIKE_ESCAPE"
    selectedRules(81) = "expr ::= expr likeop expr ESCAPE expr"
    selectedMacros(82) = "YYRULE_EXPR_ID"
    selectedRules(82) = "expr ::= ID|INDEXED|JOIN_KW"
    selectedMacros(83) = "YYRULE_TERM_QNUMBER"
    selectedRules(83) = "term ::= QNUMBER"
    selectedMacros(84) = "YYRULE_SELECT_WITH"
    selectedRules(84) = "select ::= WITH wqlist selectnowith"
    selectedMacros(85) = "YYRULE_SELECT_WITH_RECURSIVE"
    selectedRules(85) = "select ::= WITH RECURSIVE wqlist selectnowith"
    selectedMacros(86) = "YYRULE_WITH_WQLIST"
    selectedRules(86) = "with ::= WITH wqlist"
    selectedMacros(87) = "YYRULE_WITH_RECURSIVE_WQLIST"
    selectedRules(87) = "with ::= WITH RECURSIVE wqlist"
    selectedMacros(88) = "YYRULE_WQAS_AS"
    selectedRules(88) = "wqas ::= AS"
    selectedMacros(89) = "YYRULE_WQAS_MATERIALIZED"
    selectedRules(89) = "wqas ::= AS MATERIALIZED"
    selectedMacros(90) = "YYRULE_WQAS_NOT_MATERIALIZED"
    selectedRules(90) = "wqas ::= AS NOT MATERIALIZED"
    selectedMacros(91) = "YYRULE_WQITEM"
    selectedRules(91) = "wqitem ::= withnm eidlist_opt wqas LP select RP"
    selectedMacros(92) = "YYRULE_WITHNM"
    selectedRules(92) = "withnm ::= nm"
    selectedMacros(93) = "YYRULE_WQLIST_WQITEM"
    selectedRules(93) = "wqlist ::= wqitem"
    selectedMacros(94) = "YYRULE_WQLIST_COMMA_WQITEM"
    selectedRules(94) = "wqlist ::= wqlist COMMA wqitem"
    selectedMacros(95) = "YYRULE_EXPR_COLLATE"
    selectedRules(95) = "expr ::= expr COLLATE ID|STRING"
    selectedMacros(96) = "YYRULE_CMD_BEGIN_TRANSTYPE_TRANS_OPT"
    selectedRules(96) = "cmd ::= BEGIN transtype trans_opt"
    selectedMacros(97) = "YYRULE_TRANSTYPE_EMPTY"
    selectedRules(97) = "transtype ::="
    selectedMacros(98) = "YYRULE_TRANSTYPE_DEFERRED"
    selectedRules(98) = "transtype ::= DEFERRED"
    selectedMacros(99) = "YYRULE_TRANSTYPE_IMMEDIATE"
    selectedRules(99) = "transtype ::= IMMEDIATE"
    selectedMacros(100) = "YYRULE_TRANSTYPE_EXCLUSIVE"
    selectedRules(100) = "transtype ::= EXCLUSIVE"
    selectedMacros(101) = "YYRULE_CMD_COMMIT_END_TRANS_OPT"
    selectedRules(101) = "cmd ::= COMMIT|END trans_opt"
    selectedMacros(102) = "YYRULE_CMD_ROLLBACK_TRANS_OPT"
    selectedRules(102) = "cmd ::= ROLLBACK trans_opt"
    selectedMacros(103) = "YYRULE_CMD_SAVEPOINT_NM"
    selectedRules(103) = "cmd ::= SAVEPOINT nm"
    selectedMacros(104) = "YYRULE_CMD_RELEASE_SAVEPOINT_OPT_NM"
    selectedRules(104) = "cmd ::= RELEASE savepoint_opt nm"
    selectedMacros(105) = "YYRULE_CMD_ROLLBACK_TRANS_OPT_TO_SAVEPOINT_OPT_NM"
    selectedRules(105) = "cmd ::= ROLLBACK trans_opt TO savepoint_opt nm"
    Dim selectedValues(0 To 105) As Integer
    For selectedIndex As Integer = 0 To UBound(selectedMacros)
        selectedValues(selectedIndex) = -1
        For ruleIndex As Integer = 0 To ruleCount - 1
            If ruleNames(ruleIndex) = selectedRules(selectedIndex) Then
                If selectedValues(selectedIndex) >= 0 Then _
                    ReportError("duplicate grammar production: " & selectedRules(selectedIndex))
                selectedValues(selectedIndex) = ruleIndex
            End If
        Next
        If selectedValues(selectedIndex) < 0 Then _
            ReportError("missing grammar production: " & selectedRules(selectedIndex))
    Next

    Dim semanticFile As Integer = FreeFile
    Open semanticSourcePath For Input As #semanticFile
    Dim semanticSource As String = ""
    While Not EOF(semanticFile)
        Line Input #semanticFile, lineText
        semanticSource &= lineText & Chr(10)
    Wend
    Close #semanticFile

    Dim parserRuleActionLabels(0 To ruleCount - 1) As String
    For selectedIndex As Integer = 0 To UBound(selectedMacros)
        If ContainsIdentifier(semanticSource, selectedMacros(selectedIndex)) <> 0 Then _
            parserRuleActionLabels(selectedValues(selectedIndex)) = selectedMacros(selectedIndex)
    Next
    For ruleIndex As Integer = 0 To ruleCount - 1
        Dim numericMacro As String = "YYRULE_ID_" & Trim(Str(ruleIndex))
        If ContainsIdentifier(semanticSource, numericMacro) <> 0 Then _
            parserRuleActionLabels(ruleIndex) = numericMacro
    Next

    Dim actionCountPosition As Integer = InStr(cText, "#define YYNRULE_WITH_ACTION")
    If actionCountPosition = 0 Then _
        ReportError("missing YYNRULE_WITH_ACTION in " & inputPath)
    Dim actionCountEnd As Integer = InStr(actionCountPosition, cText, Chr(10))
    If actionCountEnd = 0 Then ReportError("invalid YYNRULE_WITH_ACTION in " & inputPath)
    Dim actionCountLine As String = Mid( _
        cText, actionCountPosition, actionCountEnd - actionCountPosition)
    Dim actionCount As Integer = Val(Trim(Mid(actionCountLine, Len("#define YYNRULE_WITH_ACTION") + 1)))
    If actionCount < 0 OrElse actionCount > ruleCount Then _
        ReportError("invalid YYNRULE_WITH_ACTION value in " & inputPath)

    Dim ledgerFile As Integer = FreeFile
    Open ledgerOutputPath For Output As #ledgerFile
    Print #ledgerFile, """Rule ID"",""Lemon production"",""Action class"",""Port status"",""FreeBASIC rule label"",""Notes"""
    Dim handledActionCount As Integer = 0
    Dim pendingActionCount As Integer = 0
    For ruleIndex As Integer = 0 To ruleCount - 1
        Dim actionClass As String
        Dim portStatus As String
        Dim ruleLabel As String = parserRuleActionLabels(ruleIndex)
        Dim rowNote As String
        If ruleIndex >= actionCount Then
            actionClass = "Default semantic copy"
            portStatus = "Default semantic copy"
            rowNote = "Lemon applies its default semantic value copy."
        Else
            actionClass = "Custom semantic action"
            If ruleLabel <> "" Then
                portStatus = "FB action present"
                rowNote = "Handled by sqlite3ParserSemanticReduce."
                handledActionCount += 1
            Else
                portStatus = "Needs mapping"
                ruleLabel = "YYRULE_ID_" & Trim(Str(ruleIndex))
                rowNote = ""
                pendingActionCount += 1
            End If
        End If
        Print #ledgerFile, CsvField(Trim(Str(ruleIndex))) & "," & _
            CsvField(ruleNames(ruleIndex)) & "," & CsvField(actionClass) & "," & _
            CsvField(portStatus) & "," & CsvField(ruleLabel) & "," & CsvField(rowNote)
    Next
    Close #ledgerFile

    Dim selectedSymbolMacros(0 To 50) As String
    Dim selectedSymbols(0 To 50) As String
    selectedSymbolMacros(0) = "YYSYM_EXPR"
    selectedSymbols(0) = "expr"
    selectedSymbolMacros(1) = "YYSYM_TERM"
    selectedSymbols(1) = "term"
    selectedSymbolMacros(2) = "YYSYM_SELCOLLIST"
    selectedSymbols(2) = "selcollist"
    selectedSymbolMacros(3) = "YYSYM_SCLP"
    selectedSymbols(3) = "sclp"
    selectedSymbolMacros(4) = "YYSYM_SELECT"
    selectedSymbols(4) = "select"
    selectedSymbolMacros(5) = "YYSYM_SELECTNOWITH"
    selectedSymbols(5) = "selectnowith"
    selectedSymbolMacros(6) = "YYSYM_ONESELECT"
    selectedSymbols(6) = "oneselect"
    selectedSymbolMacros(7) = "YYSYM_NEXPRLIST"
    selectedSymbols(7) = "nexprlist"
    selectedSymbolMacros(8) = "YYSYM_VALUES"
    selectedSymbols(8) = "values"
    selectedSymbolMacros(9) = "YYSYM_MVALUES"
    selectedSymbols(9) = "mvalues"
    selectedSymbolMacros(10) = "YYSYM_LIMIT_OPT"
    selectedSymbols(10) = "limit_opt"
    selectedSymbolMacros(11) = "YYSYM_WHERE_OPT"
    selectedSymbols(11) = "where_opt"
    selectedSymbolMacros(12) = "YYSYM_CASE_EXPRLIST"
    selectedSymbols(12) = "case_exprlist"
    selectedSymbolMacros(13) = "YYSYM_CASE_ELSE"
    selectedSymbols(13) = "case_else"
    selectedSymbolMacros(14) = "YYSYM_CASE_OPERAND"
    selectedSymbols(14) = "case_operand"
    selectedSymbolMacros(15) = "YYSYM_EXPRLIST"
    selectedSymbols(15) = "exprlist"
    selectedSymbolMacros(16) = "YYSYM_HAVING_OPT"
    selectedSymbols(16) = "having_opt"
    selectedSymbolMacros(17) = "YYSYM_WHERE_OPT_RET"
    selectedSymbols(17) = "where_opt_ret"
    selectedSymbolMacros(18) = "YYSYM_VINTO"
    selectedSymbols(18) = "vinto"
    selectedSymbolMacros(19) = "YYSYM_WHEN_CLAUSE"
    selectedSymbols(19) = "when_clause"
    selectedSymbolMacros(20) = "YYSYM_KEY_OPT"
    selectedSymbols(20) = "key_opt"
    selectedSymbolMacros(21) = "YYSYM_FILTER_CLAUSE"
    selectedSymbols(21) = "filter_clause"
    selectedSymbolMacros(22) = "YYSYM_EIDLIST_OPT"
    selectedSymbols(22) = "eidlist_opt"
    selectedSymbolMacros(23) = "YYSYM_SORTLIST"
    selectedSymbols(23) = "sortlist"
    selectedSymbolMacros(24) = "YYSYM_EIDLIST"
    selectedSymbols(24) = "eidlist"
    selectedSymbolMacros(25) = "YYSYM_GROUPBY_OPT"
    selectedSymbols(25) = "groupby_opt"
    selectedSymbolMacros(26) = "YYSYM_ORDERBY_OPT"
    selectedSymbols(26) = "orderby_opt"
    selectedSymbolMacros(27) = "YYSYM_SETLIST"
    selectedSymbols(27) = "setlist"
    selectedSymbolMacros(28) = "YYSYM_PAREN_EXPRLIST"
    selectedSymbols(28) = "paren_exprlist"
    selectedSymbolMacros(29) = "YYSYM_PART_OPT"
    selectedSymbols(29) = "part_opt"
    selectedSymbolMacros(30) = "YYSYM_FULLNAME"
    selectedSymbols(30) = "fullname"
    selectedSymbolMacros(31) = "YYSYM_FROM"
    selectedSymbols(31) = "from"
    selectedSymbolMacros(32) = "YYSYM_SELTABLIST"
    selectedSymbols(32) = "seltablist"
    selectedSymbolMacros(33) = "YYSYM_STL_PREFIX"
    selectedSymbols(33) = "stl_prefix"
    selectedSymbolMacros(34) = "YYSYM_XFULLNAME"
    selectedSymbols(34) = "xfullname"
    selectedSymbolMacros(35) = "YYSYM_WQLIST"
    selectedSymbols(35) = "wqlist"
    selectedSymbolMacros(36) = "YYSYM_WINDOW_CLAUSE"
    selectedSymbols(36) = "window_clause"
    selectedSymbolMacros(37) = "YYSYM_WINDOWDEFN_LIST"
    selectedSymbols(37) = "windowdefn_list"
    selectedSymbolMacros(38) = "YYSYM_IDLIST"
    selectedSymbols(38) = "idlist"
    selectedSymbolMacros(39) = "YYSYM_IDLIST_OPT"
    selectedSymbols(39) = "idlist_opt"
    selectedSymbolMacros(40) = "YYSYM_FILTER_OVER"
    selectedSymbols(40) = "filter_over"
    selectedSymbolMacros(41) = "YYSYM_WINDOWDEFN"
    selectedSymbols(41) = "windowdefn"
    selectedSymbolMacros(42) = "YYSYM_WINDOW"
    selectedSymbols(42) = "window"
    selectedSymbolMacros(43) = "YYSYM_FRAME_OPT"
    selectedSymbols(43) = "frame_opt"
    selectedSymbolMacros(44) = "YYSYM_OVER_CLAUSE"
    selectedSymbols(44) = "over_clause"
    selectedSymbolMacros(45) = "YYSYM_TRIGGER_CMD_LIST"
    selectedSymbols(45) = "trigger_cmd_list"
    selectedSymbolMacros(46) = "YYSYM_TRIGGER_CMD"
    selectedSymbols(46) = "trigger_cmd"
    selectedSymbolMacros(47) = "YYSYM_TRIGGER_EVENT"
    selectedSymbols(47) = "trigger_event"
    selectedSymbolMacros(48) = "YYSYM_FRAME_BOUND"
    selectedSymbols(48) = "frame_bound"
    selectedSymbolMacros(49) = "YYSYM_FRAME_BOUND_S"
    selectedSymbols(49) = "frame_bound_s"
    selectedSymbolMacros(50) = "YYSYM_FRAME_BOUND_E"
    selectedSymbols(50) = "frame_bound_e"
    Dim selectedSymbolValues(0 To 15) As Integer
    For selectedIndex As Integer = 0 To UBound(selectedSymbols)
        selectedSymbolValues(selectedIndex) = -1
        For symbolIndex As Integer = 0 To symbolCount - 1
            If symbolNames(symbolIndex) = selectedSymbols(selectedIndex) Then
                If selectedSymbolValues(selectedIndex) >= 0 Then _
                    ReportError("duplicate parser symbol: " & selectedSymbols(selectedIndex))
                selectedSymbolValues(selectedIndex) = symbolIndex
            End If
        Next
        If selectedSymbolValues(selectedIndex) < 0 Then _
            ReportError("missing parser symbol: " & selectedSymbols(selectedIndex))
    Next

    Dim outputFile As Integer = FreeFile
    Open outputPath For Output As #outputFile
    Print #outputFile, "/'"
    Print #outputFile, "    Project: SQLite FreeBASIC port"
    Print #outputFile, ""
    Print #outputFile, "    File: " & FileNameOnly(outputPath)
    Print #outputFile, ""
    Print #outputFile, "    Purpose: Map grammar rules and selected symbols to generated IDs."
    Print #outputFile, ""
    Print #outputFile, "    Generated by fb_tools/sqlite_codegen/sqlite_codegen.bas."
    Print #outputFile, "    Do not edit this file by hand."
    Print #outputFile, "'/"
    Print #outputFile, ""
    Print #outputFile, "#ifndef SQLITE3_FB_PARSER_RULE_IDS_BI"
    Print #outputFile, "#define SQLITE3_FB_PARSER_RULE_IDS_BI"
    Print #outputFile, ""
    For selectedIndex As Integer = 0 To UBound(selectedMacros)
        Print #outputFile, "#define " & selectedMacros(selectedIndex) & " " & _
            Trim(Str(selectedValues(selectedIndex)))
    Next
    ' Keep a numeric name for every Lemon rule so semantic actions can be
    ' ported incrementally without hand-maintained rule-number constants.
    For ruleIndex As Integer = 0 To ruleCount - 1
        Print #outputFile, "#define YYRULE_ID_" & Trim(Str(ruleIndex)) & " " & _
            Trim(Str(ruleIndex))
    Next
    For selectedIndex As Integer = 0 To UBound(selectedSymbolMacros)
        Print #outputFile, "#define " & selectedSymbolMacros(selectedIndex) & " " & _
            Trim(Str(selectedSymbolValues(selectedIndex)))
    Next
    Print #outputFile, ""
    Print #outputFile, "#endif"
    Print #outputFile, ""
    Print #outputFile, "/' end of " & FileNameOnly(outputPath) & " '/"
    Close #outputFile

    Print "wrote " & Trim(Str(UBound(selectedMacros) + 1)) & " named parser rule IDs, " & _
        Trim(Str(ruleCount)) & " numeric parser rule IDs, and " & _
        Trim(Str(UBound(selectedSymbolMacros) + 1)) & _
        " parser symbol IDs to " & outputPath
    Print "wrote parser action ledger: " & Trim(Str(handledActionCount)) & _
        " implemented, " & Trim(Str(pendingActionCount)) & " requiring mapping to " & _
        ledgerOutputPath
End Sub

Private Function SkipPragmaInputTrivia( _
    ByRef sourceText As String, ByRef position As Integer _
) As Integer
    Do While position <= Len(sourceText)
        If IsSpaceByte(Asc(sourceText, position)) <> 0 Then
            position += 1
        ElseIf Mid(sourceText, position, 2) = "/*" Then
            If SkipCWhitespaceAndComments(sourceText, position) = 0 Then Return 0
        ElseIf Asc(sourceText, position) = Asc("#") Then
            While position <= Len(sourceText) AndAlso _
                  Asc(sourceText, position) <> 10 AndAlso Asc(sourceText, position) <> 13
                position += 1
            Wend
        Else
            Exit Do
        End If
    Loop
    Return -1
End Function

Private Function ReadPragmaField( _
    ByRef sourceText As String, ByRef position As Integer, _
    ByRef fieldText As String, ByRef delimiter As Integer _
) As Integer
    fieldText = ""
    delimiter = 0
    If SkipPragmaInputTrivia(sourceText, position) = 0 Then Return 0
    Dim start As Integer = position
    Dim quote As Integer = 0
    Dim escaped As Integer = 0
    Dim parenDepth As Integer = 0

    While position <= Len(sourceText)
        Dim c As Integer = Asc(sourceText, position)
        If quote <> 0 Then
            If escaped <> 0 Then
                escaped = 0
            ElseIf c = Asc("\") Then
                escaped = -1
            ElseIf c = quote Then
                quote = 0
            End If
        ElseIf c = 34 Then
            quote = c
        ElseIf c = Asc("(") Then
            parenDepth += 1
        ElseIf c = Asc(")") Then
            If parenDepth = 0 Then Return 0
            parenDepth -= 1
        ElseIf c = Asc("/") AndAlso Mid(sourceText, position, 2) = "/*" Then
            position += 2
            While position <= Len(sourceText) AndAlso Mid(sourceText, position, 2) <> "*/"
                position += 1
            Wend
            If position > Len(sourceText) Then Return 0
            position += 2
            Continue While
        ElseIf parenDepth = 0 AndAlso (c = Asc(",") OrElse c = Asc("}")) Then
            fieldText = Trim(Mid(sourceText, start, position - start))
            delimiter = c
            position += 1
            Return CInt(fieldText <> "")
        End If
        position += 1
    Wend
    Return 0
End Function

Private Function ParsePragmaIntegerTerm( _
    ByVal inputText As String, ByRef value As ULongInt _
) As Integer
    Dim text As String = Trim(inputText)
    Dim invert As Integer = 0
    If Left(text, 1) = "~" Then
        invert = -1
        text = Trim(Mid(text, 2))
    End If
    Dim cTypeCasts(0 To 5) As String
    cTypeCasts(0) = "(u64)"
    cTypeCasts(1) = "(u32)"
    cTypeCasts(2) = "(u16)"
    cTypeCasts(3) = "(u8)"
    cTypeCasts(4) = "(sqlite3_uint64)"
    cTypeCasts(5) = "(sqlite3_int64)"
    For castIndex As Integer = 0 To UBound(cTypeCasts)
        Dim castPosition As Integer = InStr(LCase(text), cTypeCasts(castIndex))
        While castPosition > 0
            text = Left(text, castPosition - 1) & _
                   Mid(text, castPosition + Len(cTypeCasts(castIndex)))
            castPosition = InStr(LCase(text), cTypeCasts(castIndex))
        Wend
    Next
    While Len(text) >= 2 AndAlso Left(text, 1) = "(" AndAlso Right(text, 1) = ")"
        text = Trim(Mid(text, 2, Len(text) - 2))
    Wend
    While Len(text) > 0 AndAlso _
          (Right(LCase(text), 1) = "u" OrElse Right(LCase(text), 1) = "l")
        text = Left(text, Len(text) - 1)
    Wend
    If Len(text) = 0 Then Return 0

    Dim negative As Integer = 0
    If Left(text, 1) = "-" Then
        negative = -1
        text = Mid(text, 2)
    End If
    Dim parsed As ULongInt = 0
    Dim parenDepth As Integer = 0
    For shiftPosition As Integer = 1 To Len(text) - 1
        Dim currentByte As Integer = Asc(text, shiftPosition)
        If currentByte = Asc("(") Then
            parenDepth += 1
        ElseIf currentByte = Asc(")") Then
            parenDepth -= 1
            If parenDepth < 0 Then Return 0
        ElseIf parenDepth = 0 AndAlso Mid(text, shiftPosition, 2) = "<<" Then
            Dim leftValue As ULongInt
            Dim shiftValue As ULongInt
            If ParsePragmaIntegerTerm(Left(text, shiftPosition - 1), leftValue) = 0 OrElse _
               ParsePragmaIntegerTerm(Mid(text, shiftPosition + 2), shiftValue) = 0 OrElse _
               shiftValue >= 64ULL Then Return 0
            parsed = leftValue Shl CInt(shiftValue)
            If invert <> 0 Then parsed = Not parsed
            value = parsed
            Return -1
        End If
    Next
    If parenDepth <> 0 Then Return 0
    If Left(LCase(text), 2) = "0x" Then
        If Len(text) <= 2 Then Return 0
        For i As Integer = 3 To Len(text)
            Dim digit As Integer = HexDigitValue(Asc(text, i))
            If digit < 0 OrElse parsed > (&HFFFFFFFFFFFFFFFFULL - CULngInt(digit)) \ 16ULL Then Return 0
            parsed = parsed * 16ULL + CULngInt(digit)
        Next
    Else
        For i As Integer = 1 To Len(text)
            If IsAsciiDigit(Asc(text, i)) = 0 Then Return 0
            Dim digit As ULongInt = CULngInt(Asc(text, i) - Asc("0"))
            If parsed > (&HFFFFFFFFFFFFFFFFULL - digit) \ 10ULL Then Return 0
            parsed = parsed * 10ULL + digit
        Next
    End If
    If negative <> 0 Then parsed = 0ULL - parsed
    If invert <> 0 Then parsed = Not parsed
    value = parsed
    Return -1
End Function

Private Function ParsePragmaIntegerExpression( _
    ByVal inputText As String, ByRef value As ULongInt _
) As Integer
    Dim text As String = Trim(inputText)
    Dim start As Integer = 1
    Dim parenDepth As Integer = 0
    Dim combined As ULongInt = 0
    Dim termCount As Integer = 0
    For position As Integer = 1 To Len(text) + 1
        Dim c As Integer = IIf(position <= Len(text), Asc(text, position), Asc("|"))
        If c = Asc("(") Then parenDepth += 1
        If c = Asc(")") Then parenDepth -= 1
        If c = Asc("|") AndAlso parenDepth = 0 Then
            Dim termValue As ULongInt
            If ParsePragmaIntegerTerm(Mid(text, start, position - start), termValue) = 0 Then Return 0
            combined = combined Or termValue
            termCount += 1
            start = position + 1
        End If
    Next
    If termCount = 0 OrElse parenDepth <> 0 Then Return 0
    value = combined
    Return -1
End Function

Private Function ParsePragmaNameField(ByVal inputText As String, ByRef pragmaName As String) As Integer
    Dim text As String = Trim(inputText)
    If Len(text) < 2 OrElse Left(text, 1) <> Chr(34) OrElse Right(text, 1) <> Chr(34) Then Return 0
    pragmaName = Mid(text, 2, Len(text) - 2)
    If Len(pragmaName) = 0 OrElse Len(pragmaName) >= 64 Then Return 0
    For i As Integer = 1 To Len(pragmaName)
        Dim c As Integer = Asc(pragmaName, i)
        If IsAsciiAlpha(c) = 0 AndAlso IsAsciiDigit(c) = 0 AndAlso c <> Asc("_") Then Return 0
    Next
    Return -1
End Function

Private Sub GeneratePragmaTable( _
    ByVal inputPath As String, ByVal headerPath As String, ByVal sourcePath As String _
)
    Dim inputFile As Integer = FreeFile
    If Open(inputPath For Input As #inputFile) <> 0 Then ReportError("cannot read preprocessed PRAGMA source: " & inputPath)
    Dim sourceText As String = ""
    Dim lineText As String
    While Not EOF(inputFile)
        Line Input #inputFile, lineText
        sourceText &= lineText & Chr(10)
    Wend
    Close #inputFile

    Dim tableMarker As String = "static const PragmaName aPragmaName[]"
    Dim tableStart As Integer = InStr(sourceText, tableMarker)
    If tableStart = 0 Then ReportError("missing aPragmaName table in " & inputPath)
    Dim openBrace As Integer = InStr(tableStart + Len(tableMarker), sourceText, "{")
    If openBrace = 0 Then ReportError("missing aPragmaName initializer in " & inputPath)
    Dim position As Integer = openBrace + 1
    Dim entries(0 To 255) As PragmaTableEntry
    Dim entryCount As Integer = 0
    Dim foundEnd As Integer = 0

    Do While position <= Len(sourceText)
        If SkipPragmaInputTrivia(sourceText, position) = 0 Then _
            ReportError("unterminated comment in aPragmaName table")
        If position > Len(sourceText) Then Exit Do
        Dim c As Integer = Asc(sourceText, position)
        If c = Asc("}") Then
            position += 1
            foundEnd = -1
            Exit Do
        ElseIf c = Asc(",") Then
            position += 1
            Continue Do
        ElseIf c <> Asc("{") Then
            ReportError("expected aPragmaName record at byte " & Trim(Str(position)))
        End If
        position += 1
        Dim fields(0 To 5) As String
        For fieldIndex As Integer = 0 To 5
            Dim delimiter As Integer
            If ReadPragmaField(sourceText, position, fields(fieldIndex), delimiter) = 0 Then _
                ReportError("invalid aPragmaName field " & Trim(Str(fieldIndex)))
            If fieldIndex < 5 AndAlso delimiter <> Asc(",") Then _
                ReportError("expected comma in aPragmaName record")
            If fieldIndex = 5 AndAlso delimiter <> Asc("}") Then _
                ReportError("expected aPragmaName record terminator")
        Next
        If entryCount > UBound(entries) Then ReportError("aPragmaName exceeds the configured row limit")
        With entries(entryCount)
            If ParsePragmaNameField(fields(0), .name) = 0 Then _
                ReportError("invalid PRAGMA name: " & fields(0))
            If ParsePragmaIntegerExpression(fields(1), .typeCode) = 0 OrElse _
               ParsePragmaIntegerExpression(fields(2), .flags) = 0 OrElse _
               ParsePragmaIntegerExpression(fields(3), .columnStart) = 0 OrElse _
               ParsePragmaIntegerExpression(fields(4), .columnCount) = 0 OrElse _
               ParsePragmaIntegerExpression(fields(5), .argument) = 0 Then _
                ReportError("invalid numeric field in PRAGMA record " & .name)
            If .typeCode > 255 OrElse .flags > 255 OrElse .columnStart > 255 OrElse .columnCount > 255 Then _
                ReportError("byte field out of range in PRAGMA record " & .name)
        End With
        entryCount += 1
    Loop
    If foundEnd = 0 OrElse entryCount = 0 Then ReportError("unterminated or empty aPragmaName table")
    If entryCount > 255 Then ReportError("aPragmaName row count exceeds the supported 8-bit cursor index")

    Dim columnMarker As String = "static const char *const pragCName[]"
    Dim columnStart As Integer = InStr(sourceText, columnMarker)
    If columnStart = 0 Then ReportError("missing pragCName table in " & inputPath)
    Dim columnOpen As Integer = InStr(columnStart + Len(columnMarker), sourceText, "{")
    If columnOpen = 0 Then ReportError("missing pragCName initializer in " & inputPath)
    Dim columnNames(0 To 255) As String
    Dim columnCount As Integer = 0
    position = columnOpen + 1
    Dim foundColumnEnd As Integer = 0
    Do While position <= Len(sourceText)
        If SkipPragmaInputTrivia(sourceText, position) = 0 Then _
            ReportError("unterminated comment in pragCName table")
        If position > Len(sourceText) Then Exit Do
        If Asc(sourceText, position) = Asc("}") Then
            position += 1
            foundColumnEnd = -1
            Exit Do
        End If
        Dim columnText As String
        Dim delimiter As Integer
        If ReadPragmaField(sourceText, position, columnText, delimiter) = 0 Then _
            ReportError("invalid pragCName entry at byte " & Trim(Str(position)))
        If delimiter <> Asc(",") AndAlso delimiter <> Asc("}") Then _
            ReportError("invalid pragCName delimiter")
        Dim columnName As String
        If ParsePragmaNameField(columnText, columnName) = 0 Then _
            ReportError("invalid pragma result column name: " & columnText)
        If columnCount > UBound(columnNames) Then ReportError("pragCName exceeds the configured row limit")
        columnNames(columnCount) = columnName
        columnCount += 1
        If delimiter = Asc("}") Then
            foundColumnEnd = -1
            Exit Do
        End If
    Loop
    If foundColumnEnd = 0 OrElse columnCount = 0 Then _
        ReportError("unterminated or empty pragCName table")

    Dim maxNameWidth As Integer = 1
    For i As Integer = 0 To entryCount - 1
        If Len(entries(i).name) + 1 > maxNameWidth Then maxNameWidth = Len(entries(i).name) + 1
    Next
    Dim maxColumnNameWidth As Integer = 1
    For i As Integer = 0 To columnCount - 1
        If Len(columnNames(i)) + 1 > maxColumnNameWidth Then _
            maxColumnNameWidth = Len(columnNames(i)) + 1
    Next

    Dim headerFile As Integer = FreeFile
    Open headerPath For Output As #headerFile
    Print #headerFile, "/'"
    Print #headerFile, "    Project: SQLite FreeBASIC port"
    Print #headerFile, ""
    Print #headerFile, "    File: " & FileNameOnly(headerPath)
    Print #headerFile, ""
    Print #headerFile, "    Purpose: Declare the generated, sorted PRAGMA-name table."
    Print #headerFile, ""
    Print #headerFile, "    Generated by fb_tools/sqlite_codegen/sqlite_codegen.bas."
    Print #headerFile, "    Do not edit this file by hand."
    Print #headerFile, "'/"
    Print #headerFile, ""
    Print #headerFile, "#ifndef SQLITE3_FB_PRAGMA_DATA_BI"
    Print #headerFile, "#define SQLITE3_FB_PRAGMA_DATA_BI"
    Print #headerFile, "#define SQLITE3_PRAGMA_NAME_COUNT " & Trim(Str(entryCount))
    Print #headerFile, "#define SQLITE3_PRAGMA_COLUMN_NAME_COUNT " & Trim(Str(columnCount))
    Print #headerFile, "Declare Function sqlite3PragmaNameTable CDecl Alias ""sqlite3PragmaNameTable"" () As Const SqlitePragmaName Ptr"
    Print #headerFile, "Declare Function sqlite3PragmaColumnNameTable CDecl Alias ""sqlite3PragmaColumnNameTable"" () As Const ZString Ptr Ptr"
    Print #headerFile, "#endif"
    Print #headerFile, ""
    Print #headerFile, "/' end of " & FileNameOnly(headerPath) & " '/"
    Close #headerFile

    Dim outputFile As Integer = FreeFile
    Open sourcePath For Output As #outputFile
    Print #outputFile, "/'"
    Print #outputFile, "    Project: SQLite FreeBASIC port"
    Print #outputFile, ""
    Print #outputFile, "    File: " & FileNameOnly(sourcePath)
    Print #outputFile, ""
    Print #outputFile, "    Purpose: Store the C-ordered PRAGMA-name and metadata table."
    Print #outputFile, ""
    Print #outputFile, "    Generated by fb_tools/sqlite_codegen/sqlite_codegen.bas."
    Print #outputFile, "    Do not edit this file by hand."
    Print #outputFile, "'/"
    Print #outputFile, ""
    Print #outputFile, "#lang ""fb"""
    Print #outputFile, "#include once ""sqlite3_types.bi"""
    Print #outputFile, "#include once ""sqlite3_constants.bi"""
    Print #outputFile, "#include once ""sqlite3_db_types.bi"""
    Print #outputFile, "#include once ""sqlite3_pragma_types.bi"""
    Print #outputFile, ""
    Print #outputFile, "Private Dim Shared As Const ZString * " & Trim(Str(maxNameWidth)) & _
        " sqlite3PragmaNameText(0 To " & Trim(Str(entryCount - 1)) & ") = { _"
    For i As Integer = 0 To entryCount - 1
        Dim suffix As String = IIf(i < entryCount - 1, "", "}")
        Dim continuation As String = IIf(i < entryCount - 1, ", _", "")
        Print #outputFile, "    """ & entries(i).name & """" & continuation & suffix
    Next
    Print #outputFile, ""
    Print #outputFile, "Private Dim Shared As Const SqlitePragmaName sqlite3PragmaNameEntries(0 To " & _
        Trim(Str(entryCount - 1)) & ") = { _"
    For i As Integer = 0 To entryCount - 1
        Dim recordText As String = "    Type<SqlitePragmaName>(" & _
            "CPtr(Const ZString Ptr, @sqlite3PragmaNameText(" & Trim(Str(i)) & ")), " & _
            "Cast(u8, " & Trim(Str(entries(i).typeCode)) & "), " & _
            "Cast(u8, " & Trim(Str(entries(i).flags)) & "), " & _
            "Cast(u8, " & Trim(Str(entries(i).columnStart)) & "), " & _
            "Cast(u8, " & Trim(Str(entries(i).columnCount)) & "), " & _
            "Cast(sqlite3_uint64, &H" & Hex(entries(i).argument) & "ULL))"
        If i < entryCount - 1 Then
            recordText &= ", _"
        Else
            recordText &= "}"
        End If
        Print #outputFile, recordText
    Next
    Print #outputFile, ""
    Print #outputFile, "Private Dim Shared As Const ZString * " & Trim(Str(maxColumnNameWidth)) & _
        " sqlite3PragmaColumnNameText(0 To " & Trim(Str(columnCount - 1)) & ") = { _"
    For i As Integer = 0 To columnCount - 1
        Dim suffix As String = IIf(i < columnCount - 1, "", "}")
        Dim continuation As String = IIf(i < columnCount - 1, ", _", "")
        Print #outputFile, "    """ & columnNames(i) & """" & continuation & suffix
    Next
    Print #outputFile, ""
    Print #outputFile, "Private Dim Shared As Const ZString Ptr sqlite3PragmaColumnNameEntries(0 To " & _
        Trim(Str(columnCount - 1)) & ") = { _"
    For i As Integer = 0 To columnCount - 1
        Dim suffix As String = IIf(i < columnCount - 1, ", _", "}")
        Print #outputFile, "    CPtr(Const ZString Ptr, @sqlite3PragmaColumnNameText(" & _
            Trim(Str(i)) & "))" & suffix
    Next
    Print #outputFile, ""
    Print #outputFile, "Function sqlite3PragmaNameTable CDecl Alias ""sqlite3PragmaNameTable"" () As Const SqlitePragmaName Ptr"
    Print #outputFile, "    Return @sqlite3PragmaNameEntries(0)"
    Print #outputFile, "End Function"
    Print #outputFile, ""
    Print #outputFile, "Function sqlite3PragmaColumnNameTable CDecl Alias ""sqlite3PragmaColumnNameTable"" () As Const ZString Ptr Ptr"
    Print #outputFile, "    Return @sqlite3PragmaColumnNameEntries(0)"
    Print #outputFile, "End Function"
    Print #outputFile, ""
    Print #outputFile, "/' end of " & FileNameOnly(sourcePath) & " '/"
    Close #outputFile

    Print "wrote " & Trim(Str(entryCount)) & " PRAGMA metadata entries and " & _
        Trim(Str(columnCount)) & " result-column names to " & sourcePath
End Sub

Private Sub PrintUsage()
    Print "Usage: sqlite_codegen tokens <parse.h> <output.bi>"
    Print "       sqlite_codegen keywords <keywordhash.h> <output.bi>"
    Print "       sqlite_codegen classes <tokenize.c> <output.bi>"
    Print "       sqlite_codegen global-data <global.c> <output.bi>"
    Print "       sqlite_codegen pragma-table <pragma.i> <output.bi> <output.bas>"
    Print "       sqlite_codegen opcodes <opcodes.h> <output.bi>"
    Print "       sqlite_codegen opcode-names <opcodes.h> <output.bas>"
    Print "       sqlite_codegen parser-tables <parse.c> <output.bi>"
    Print "       sqlite_codegen parser-rule-ids <parse.c> <output.bi> <semantics.bas> <ledger.csv>"
    End 2
End Sub

Select Case LCase(Command(1))
Case "tokens"
    If Len(Command(2)) = 0 OrElse Len(Command(3)) = 0 Then PrintUsage()
    GenerateTokenDefines(Command(2), Command(3))
Case "keywords"
    If Len(Command(2)) = 0 OrElse Len(Command(3)) = 0 Then PrintUsage()
    GenerateKeywordData(Command(2), Command(3))
Case "classes"
    If Len(Command(2)) = 0 OrElse Len(Command(3)) = 0 Then PrintUsage()
    GenerateCharacterClasses(Command(2), Command(3))
Case "global-data"
    If Len(Command(2)) = 0 OrElse Len(Command(3)) = 0 Then PrintUsage()
    GenerateGlobalData(Command(2), Command(3))
Case "opcodes"
    If Len(Command(2)) = 0 OrElse Len(Command(3)) = 0 Then PrintUsage()
    GenerateOpcodeDefines(Command(2), Command(3))
Case "opcode-names"
    If Len(Command(2)) = 0 OrElse Len(Command(3)) = 0 Then PrintUsage()
    GenerateOpcodeNames(Command(2), Command(3))
Case "parser-tables"
    If Len(Command(2)) = 0 OrElse Len(Command(3)) = 0 Then PrintUsage()
    GenerateParserTables(Command(2), Command(3))
Case "parser-rule-ids"
    If Len(Command(2)) = 0 OrElse Len(Command(3)) = 0 OrElse _
       Len(Command(4)) = 0 OrElse Len(Command(5)) = 0 Then PrintUsage()
    GenerateParserRuleIds(Command(2), Command(3), Command(4), Command(5))
Case "pragma-table"
    If Len(Command(2)) = 0 OrElse Len(Command(3)) = 0 OrElse Len(Command(4)) = 0 Then PrintUsage()
    GeneratePragmaTable(Command(2), Command(3), Command(4))
Case Else
    PrintUsage()
End Select

/' end of sqlite_codegen.bas '/
