/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_iotrace.bas

    Purpose:

        Format the SQL label sent to SQLite's optional VDBE I/O trace hook.

    Responsibilities:

        - Export the optional sqlite3IoTrace callback pointer.
        - Emit bounded SQL text with leading and repeated whitespace normalized.

    This file intentionally does NOT contain:

        - The host trace callback, file handles, or test-shell commands.
        - SQLite VDBE dispatch or I/O operation formatting.
'/ 

#lang "fb"
#if defined(SQLITE_ENABLE_IOTRACE) AndAlso Not defined(SQLITE_OMIT_TRACE)
#include once "sqlite3_iotrace.bi"
#include once "sqlite3_global_data.bi"

Dim sqlite3IoTrace As SqliteIoTraceCallback = 0

Private Function ioTraceIsSpace(ByVal value As UByte) As SQLITE_C_INT
    Return CInt((sqlite3CtypeMap(value) And &H01) <> 0)
End Function

Sub sqlite3VdbeIOTraceSql CDecl Alias "sqlite3VdbeIOTraceSql" ( _
    ByVal pVdbe As SqliteVdbe Ptr _
) Export
    Dim xTrace As SqliteIoTraceCallback = sqlite3IoTrace
    If xTrace = 0 OrElse pVdbe = 0 OrElse pVdbe->nOp < 1 OrElse _
       pVdbe->aOp = 0 Then Exit Sub

    Dim pOp As SqliteVdbeOp Ptr = @pVdbe->aOp[0]
    If pOp->opcode <> OP_Init OrElse pOp->p4.z = 0 Then Exit Sub

    Dim zSql As ZString * 1000
    Dim copyIndex As Long = 0
    While copyIndex < 999 AndAlso pOp->p4.z[copyIndex] <> 0
        zSql[copyIndex] = pOp->p4.z[copyIndex]
        copyIndex += 1
    Wend
    zSql[copyIndex] = 0

    Dim readIndex As Long = 0
    While zSql[readIndex] <> 0 AndAlso _
          ioTraceIsSpace(CUByte(zSql[readIndex])) <> 0
        readIndex += 1
    Wend

    Dim writeIndex As Long = 0
    While zSql[readIndex] <> 0 AndAlso writeIndex < 999
        If ioTraceIsSpace(CUByte(zSql[readIndex])) <> 0 Then
            If writeIndex > 0 AndAlso zSql[writeIndex - 1] <> Asc(" ") Then
                zSql[writeIndex] = Asc(" ")
                writeIndex += 1
            End If
        Else
            zSql[writeIndex] = zSql[readIndex]
            writeIndex += 1
        End If
        readIndex += 1
    Wend
    zSql[writeIndex] = 0
    xTrace(StrPtr(!"SQL %s\n"), StrPtr(zSql))
End Sub
#endif

/' end of sqlite3_iotrace.bas '/
