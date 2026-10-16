/'
** 2007 May 1
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
*************************************************************************
**
** This file contains code used to implement incremental BLOB I/O.
'/ 
/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_bulk_vdbeblob.bas

    Purpose:

        Operate on an existing incremental-BLOB handle.

    Responsibilities:

        - Preserve the private incremental-BLOB handle layout.
        - Validate byte ranges before accessing the B-tree cursor.
        - Hold the connection and cursor locks across each payload operation.
        - Finalize an invalidated statement after SQLITE_ABORT.
        - Report BLOB size, close a handle, and seek it to another row.

    This file intentionally does NOT contain:

        - BLOB handle opening or construction of the VDBE program.
        - The B-tree payload storage implementation.
        - A claim that compilation establishes runtime behavior parity.
'/ 

#lang "fb"

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_api_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_vdbe_cursor.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_vdbe_serial.bi"
#include once "sqlite3_btree.bi"
#include once "sqlite3_mutex.bi"

Declare Function sqlite3_finalize CDecl Alias "sqlite3_finalize" ( _
    ByVal pStatement As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_step CDecl Alias "sqlite3_step" ( _
    ByVal pStatement As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3_errmsg CDecl Alias "sqlite3_errmsg" ( _
    ByVal db As sqlite3 Ptr _
) As Const ZString Ptr
Declare Function sqlite3MPrintf CDecl Alias "sqlite3MPrintf" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal format As Const ZString Ptr, _
    ... _
) As ZString Ptr
Declare Function sqlite3LocateTable CDecl Alias "sqlite3LocateTable" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal flags As SQLITE_C_UINT, _
    ByVal tableName As Const ZString Ptr, _
    ByVal databaseName As Const ZString Ptr _
) As SqliteTable Ptr
Declare Function sqlite3OpenTempDatabase CDecl Alias "sqlite3OpenTempDatabase" ( _
    ByVal pParse As SqliteParseContext Ptr _
) As SQLITE_C_INT
Declare Function sqlite3ColumnIndex CDecl Alias "sqlite3ColumnIndex" ( _
    ByVal pTable As SqliteTable Ptr, _
    ByVal columnName As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3SchemaToIndex CDecl Alias "sqlite3SchemaToIndex" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pSchema As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3ParseObjectInit CDecl Alias "sqlite3ParseObjectInit" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal db As sqlite3 Ptr _
)
Declare Sub sqlite3ParseObjectReset CDecl Alias "sqlite3ParseObjectReset" ( _
    ByVal pParse As SqliteParseContext Ptr _
)

/' ------------------------------------------------------------------------- '/
/' Private sqlite3_blob handle layout                                          '/
/' ------------------------------------------------------------------------- '/

Type SqliteIncrblob
    nByte As SQLITE_C_INT
    iOffset As SQLITE_C_INT
    iCol As u16
    padding(0 To 5) As UByte
    pCsr As BtCursor Ptr
    pStmt As Any Ptr
    db As sqlite3 Ptr
    zDb As ZString Ptr
    pTab As SqliteTable Ptr
End Type

Private Const VDBEBLOB_TF_HAS_GENERATED As u32 = &H00000060
Private Const VDBEBLOB_EXPR_COLUMN As Short = -2
Private Const VDBEBLOB_MAX_SCHEMA_RETRY As SQLITE_C_INT = 50
Private Const VDBEBLOB_OP_LINE As SQLITE_C_INT = 0

/' ------------------------------------------------------------------------- '/
/' Shared payload read and write path                                          '/
/' ------------------------------------------------------------------------- '/

Private Function blobReadWrite( _
    ByVal pBlobHandle As Any Ptr, _
    ByVal pBuffer As Any Ptr, _
    ByVal byteCount As SQLITE_C_INT, _
    ByVal byteOffset As SQLITE_C_INT, _
    ByVal writeOperation As SQLITE_C_INT _
) As SQLITE_C_INT
    If pBlobHandle = 0 Then Return SQLITE_MISUSE

    Dim pBlob As SqliteIncrblob Ptr = CPtr(SqliteIncrblob Ptr, pBlobHandle)
    If pBlob->db = 0 Then Return SQLITE_MISUSE
    Dim db As sqlite3 Ptr = pBlob->db

    sqlite3_mutex_enter(db->mutex)
    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pBlob->pStmt)
    Dim endOffset As sqlite3_int64 = _
        Cast(sqlite3_int64, byteOffset) + Cast(sqlite3_int64, byteCount)

    If byteCount < 0 OrElse byteOffset < 0 OrElse _
       endOffset > Cast(sqlite3_int64, pBlob->nByte) Then
        ' A range error is transient; the handle remains usable.
        rc = SQLITE_ERROR
    ElseIf pVdbe = 0 OrElse pBlob->pCsr = 0 Then
        rc = SQLITE_ABORT
    ElseIf byteCount > 0 AndAlso pBuffer = 0 Then
        rc = SQLITE_MISUSE
    Else
        Dim cursorOffset As sqlite3_uint64 = _
            CULngInt(pBlob->iOffset) + CULngInt(byteOffset)
        If pBlob->iOffset < 0 OrElse cursorOffset > &HFFFFFFFFULL Then
            rc = SQLITE_CORRUPT
        Else
            sqlite3BtreeEnterCursor(pBlob->pCsr)
            If writeOperation <> 0 Then
                rc = sqlite3BtreePutData(pBlob->pCsr, _
                    Cast(u32, cursorOffset), Cast(u32, byteCount), pBuffer)
            Else
                rc = sqlite3BtreePayloadChecked(pBlob->pCsr, _
                    Cast(u32, cursorOffset), Cast(u32, byteCount), pBuffer)
            End If
#if SQLITE_THREADSAFE > 0
            sqlite3BtreeLeaveCursor(pBlob->pCsr)
#endif

            If rc = SQLITE_ABORT Then
                sqlite3VdbeFinalize(pVdbe)
                pBlob->pStmt = 0
            Else
                pVdbe->rc = rc
            End If
        End If
    End If

    sqlite3Error(db, rc)
    rc = sqlite3ApiExit(db, rc)
    sqlite3_mutex_leave(db->mutex)
    Return rc
End Function

/' ------------------------------------------------------------------------- '/
/' Public incremental BLOB byte access                                        '/
/' ------------------------------------------------------------------------- '/

Function sqlite3_blob_read CDecl Alias "sqlite3_blob_read" ( _
    ByVal pBlob As Any Ptr, _
    ByVal pBuffer As Any Ptr, _
    ByVal byteCount As SQLITE_C_INT, _
    ByVal byteOffset As SQLITE_C_INT _
) As SQLITE_C_INT
    Return blobReadWrite(pBlob, pBuffer, byteCount, byteOffset, 0)
End Function

Function sqlite3_blob_write CDecl Alias "sqlite3_blob_write" ( _
    ByVal pBlob As Any Ptr, _
    ByVal pBuffer As Const Any Ptr, _
    ByVal byteCount As SQLITE_C_INT, _
    ByVal byteOffset As SQLITE_C_INT _
) As SQLITE_C_INT
    Return blobReadWrite(pBlob, CPtr(Any Ptr, pBuffer), byteCount, byteOffset, 1)
End Function

Function sqlite3_blob_bytes CDecl Alias "sqlite3_blob_bytes" ( _
    ByVal pBlobHandle As Any Ptr _
) As SQLITE_C_INT
    If pBlobHandle = 0 Then Return 0
    Dim pBlob As SqliteIncrblob Ptr = CPtr(SqliteIncrblob Ptr, pBlobHandle)
    If pBlob->pStmt = 0 Then Return 0
    Return pBlob->nByte
End Function

Function sqlite3_blob_close CDecl Alias "sqlite3_blob_close" ( _
    ByVal pBlobHandle As Any Ptr _
) As SQLITE_C_INT
    If pBlobHandle = 0 Then Return SQLITE_OK
    Dim pBlob As SqliteIncrblob Ptr = CPtr(SqliteIncrblob Ptr, pBlobHandle)
    If pBlob->db = 0 Then Return SQLITE_MISUSE

    Dim db As sqlite3 Ptr = pBlob->db
    Dim pStatement As Any Ptr = pBlob->pStmt
    sqlite3_mutex_enter(db->mutex)
    sqlite3DbFree(db, pBlob)
    sqlite3_mutex_leave(db->mutex)
    Return sqlite3_finalize(pStatement)
End Function

Private Function blobSeekToRow( _
    ByVal pBlob As SqliteIncrblob Ptr, _
    ByVal rowid As sqlite3_int64, _
    ByVal pzError As ZString Ptr Ptr _
) As SQLITE_C_INT
    If pBlob = 0 OrElse pBlob->db = 0 OrElse pBlob->pStmt = 0 OrElse _
       pzError = 0 Then Return SQLITE_MISUSE

    Dim db As sqlite3 Ptr = pBlob->db
    Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pBlob->pStmt)
    Dim zError As ZString Ptr = 0
    sqlite3VdbeMemSetInt64(@pVdbe->aMem[1], rowid)

    Dim rc As SQLITE_C_INT
    If pVdbe->pc > 4 Then
        If pVdbe->aOp = 0 OrElse pVdbe->nOp <= 4 OrElse _
           pVdbe->aOp[4].opcode <> OP_NotExists Then Return SQLITE_CORRUPT
        pVdbe->pc = 4
        rc = sqlite3VdbeExec(pVdbe)
    Else
        rc = sqlite3_step(pBlob->pStmt)
    End If

    If rc = SQLITE_ROW Then
        If pVdbe->apCsr = 0 OrElse pVdbe->apCsr[0] = 0 Then
            rc = SQLITE_CORRUPT
        Else
            Dim pCursor As SqliteVdbeCursor Ptr = pVdbe->apCsr[0]
            If pCursor->eCurType <> CURTYPE_BTREE OrElse pCursor->nField < 0 Then
                rc = SQLITE_CORRUPT
            Else
                Dim pTypes As u32 Ptr = CPtr(u32 Ptr, _
                    CPtr(UByte Ptr, pCursor) + SizeOf(SqliteVdbeCursor))
                Dim serialType As u32 = 0
                If pCursor->nHdrParsed > pBlob->iCol Then _
                    serialType = pTypes[pBlob->iCol]

                If serialType < 12 Then
                    Dim typeName As Const ZString Ptr = StrPtr(!"integer")
                    If serialType = 0 Then
                        typeName = StrPtr(!"null")
                    ElseIf serialType = 7 Then
                        typeName = StrPtr(!"real")
                    End If
                    zError = sqlite3MPrintf(db, _
                        StrPtr(!"cannot open value of type %s"), typeName)
                    rc = SQLITE_ERROR
                    sqlite3_finalize(pBlob->pStmt)
                    pBlob->pStmt = 0
                Else
                    Dim offsetIndex As SQLITE_C_INT = _
                        Cast(SQLITE_C_INT, pBlob->iCol) + pCursor->nField
                    If offsetIndex < 0 OrElse _
                       offsetIndex > 2 * Cast(SQLITE_C_INT, pCursor->nField) Then
                        rc = SQLITE_CORRUPT
                    Else
                        pBlob->iOffset = Cast(SQLITE_C_INT, pTypes[offsetIndex])
                        pBlob->nByte = Cast(SQLITE_C_INT, _
                            sqlite3VdbeSerialTypeLen(serialType))
                        pBlob->pCsr = pCursor->uc.pCursor
                        If pBlob->pCsr = 0 Then
                            rc = SQLITE_CORRUPT
                        Else
                            sqlite3BtreeIncrblobCursor(pBlob->pCsr)
                        End If
                    End If
                End If
            End If
        End If
    End If

    If rc = SQLITE_ROW Then
        rc = SQLITE_OK
    ElseIf pBlob->pStmt Then
        rc = sqlite3_finalize(pBlob->pStmt)
        pBlob->pStmt = 0
        If rc = SQLITE_OK Then
            zError = sqlite3MPrintf(db, StrPtr(!"no such rowid: %lld"), rowid)
            rc = SQLITE_ERROR
        Else
            zError = sqlite3MPrintf(db, StrPtr(!"%s"), sqlite3_errmsg(db))
        End If
    End If

    *pzError = zError
    Return rc
End Function

Function sqlite3_blob_reopen CDecl Alias "sqlite3_blob_reopen" ( _
    ByVal pBlobHandle As Any Ptr, _
    ByVal rowid As sqlite3_int64 _
) As SQLITE_C_INT
    If pBlobHandle = 0 Then Return SQLITE_MISUSE
    Dim pBlob As SqliteIncrblob Ptr = CPtr(SqliteIncrblob Ptr, pBlobHandle)
    If pBlob->db = 0 Then Return SQLITE_MISUSE

    Dim db As sqlite3 Ptr = pBlob->db
    sqlite3_mutex_enter(db->mutex)
    Dim rc As SQLITE_C_INT
    If pBlob->pStmt = 0 Then
        rc = SQLITE_ABORT
    Else
        Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pBlob->pStmt)
        pVdbe->rc = SQLITE_OK
        Dim zError As ZString Ptr = 0
        rc = blobSeekToRow(pBlob, rowid, @zError)
        If rc <> SQLITE_OK Then
            If zError Then
                sqlite3ErrorWithMsg(db, rc, StrPtr(!"%s"), zError)
            Else
                sqlite3ErrorWithMsg(db, rc, 0)
            End If
            sqlite3DbFree(db, zError)
        End If
    End If
    rc = sqlite3ApiExit(db, rc)
    sqlite3_mutex_leave(db->mutex)
    Return rc
End Function

Function sqlite3_blob_open CDecl Alias "sqlite3_blob_open" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal databaseName As Const ZString Ptr, _
    ByVal tableName As Const ZString Ptr, _
    ByVal columnName As Const ZString Ptr, _
    ByVal rowid As sqlite3_int64, _
    ByVal writeFlag As SQLITE_C_INT, _
    ByVal ppBlob As Any Ptr Ptr _
) As SQLITE_C_INT
    If ppBlob = 0 Then Return SQLITE_MISUSE
    ppBlob[0] = 0
    If db = 0 OrElse tableName = 0 OrElse columnName = 0 Then _
        Return SQLITE_MISUSE

    Dim writable As SQLITE_C_INT = IIf(writeFlag <> 0, 1, 0)
    sqlite3_mutex_enter(db->mutex)
    Dim pBlob As SqliteIncrblob Ptr = CPtr(SqliteIncrblob Ptr, _
        sqlite3DbMallocZero(db, CULngInt(SizeOf(SqliteIncrblob))))
    Dim pParse As SqliteParseContext
    Dim pTable As SqliteTable Ptr = 0
    Dim databaseIndex As SQLITE_C_INT = -1
    Dim columnIndex As SQLITE_C_INT = -1
    Dim zError As ZString Ptr = 0
    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim attempt As SQLITE_C_INT = 0

    Do
        sqlite3ParseObjectInit(@pParse, db)
        If pBlob = 0 Then
            rc = SQLITE_NOMEM
            Exit Do
        End If

        sqlite3DbFree(db, zError)
        zError = 0
        sqlite3BtreeEnterAll(db)

        Do
            pTable = sqlite3LocateTable(@pParse, 0, tableName, databaseName)
            If pTable AndAlso pTable->eTabType = TABTYP_VTAB Then
                sqlite3ErrorMsg(@pParse, StrPtr(!"cannot open virtual table: %s"), tableName)
                pTable = 0
            End If
            If pTable AndAlso (pTable->tabFlags And TF_WithoutRowid) <> 0 Then
                sqlite3ErrorMsg(@pParse, _
                    StrPtr(!"cannot open table without rowid: %s"), tableName)
                pTable = 0
            End If
            If pTable AndAlso _
               (pTable->tabFlags And VDBEBLOB_TF_HAS_GENERATED) <> 0 Then
                sqlite3ErrorMsg(@pParse, _
                    StrPtr(!"cannot open table with generated columns: %s"), tableName)
                pTable = 0
            End If
            If pTable AndAlso pTable->eTabType = TABTYP_VIEW Then
                sqlite3ErrorMsg(@pParse, StrPtr(!"cannot open view: %s"), tableName)
                pTable = 0
            End If

            If pTable = 0 Then
                rc = SQLITE_ERROR
                Exit Do
            End If

            databaseIndex = sqlite3SchemaToIndex(db, pTable->pSchema)
            If databaseIndex < 0 OrElse databaseIndex >= db->nDb Then
                sqlite3ErrorMsg(@pParse, StrPtr(!"no such database: %s"), databaseName)
                rc = SQLITE_ERROR
                Exit Do
            End If
            If databaseIndex = 1 AndAlso sqlite3OpenTempDatabase(@pParse) <> SQLITE_OK Then
                rc = SQLITE_ERROR
                Exit Do
            End If

            pBlob->pTab = pTable
            pBlob->zDb = CPtr(ZString Ptr, db->aDb(databaseIndex).zDbSName)

            columnIndex = sqlite3ColumnIndex(pTable, columnName)
            If columnIndex < 0 Then
                zError = sqlite3MPrintf(db, _
                    StrPtr(!"no such column: \"%s\""), columnName)
                rc = SQLITE_ERROR
                Exit Do
            End If

            If writable <> 0 Then
                Dim zFault As Const ZString Ptr = 0
#ifndef SQLITE_OMIT_FOREIGN_KEY
                If (db->flags And SQLITE_ForeignKeys) <> 0 Then
                    Dim pForeignKey As SqliteFKey Ptr = pTable->u.tab.pFKey
                    While pForeignKey
                        For foreignKeyColumn As SQLITE_C_INT = _
                            0 To pForeignKey->nCol - 1
                            If pForeignKey->aCol(foreignKeyColumn).iFrom = columnIndex Then
                                zFault = StrPtr(!"foreign key")
                                Exit For
                            End If
                        Next
                        pForeignKey = pForeignKey->pNextFrom
                    Wend
                End If
#endif
                Dim pIndex As SqliteIndex Ptr = CPtr(SqliteIndex Ptr, pTable->pIndex)
                While pIndex
                    For indexColumn As SQLITE_C_INT = 0 To pIndex->nKeyCol - 1
                        If pIndex->aiColumn[indexColumn] = columnIndex OrElse _
                           pIndex->aiColumn[indexColumn] = VDBEBLOB_EXPR_COLUMN Then
                            zFault = StrPtr(!"indexed")
                            Exit For
                        End If
                    Next
                    pIndex = CPtr(SqliteIndex Ptr, pIndex->pNext)
                Wend

                If zFault Then
                    zError = sqlite3MPrintf(db, _
                        StrPtr(!"cannot open %s column for writing"), zFault)
                    rc = SQLITE_ERROR
                    Exit Do
                End If
            End If

            pBlob->pStmt = sqlite3VdbeCreate(@pParse)
            If pBlob->pStmt = 0 Then
                rc = SQLITE_NOMEM
                Exit Do
            End If
            Dim pVdbe As SqliteVdbe Ptr = CPtr(SqliteVdbe Ptr, pBlob->pStmt)
            Dim pSchema As SqliteSchema Ptr = _
                CPtr(SqliteSchema Ptr, pTable->pSchema)
            sqlite3VdbeAddOp4Int(pVdbe, OP_Transaction, databaseIndex, writable, _
                pSchema->schema_cookie, pSchema->iGeneration)
            sqlite3VdbeChangeP5(pVdbe, 1)
            If sqlite3VdbeCurrentAddr(pVdbe) <> 2 Then
                rc = SQLITE_CORRUPT
                Exit Do
            End If

            Dim openBlobOps(0 To 5) As SqliteVdbeOpList
            openBlobOps(0).opcode = OP_TableLock
            openBlobOps(0).p1 = 0
            openBlobOps(0).p2 = 0
            openBlobOps(0).p3 = 0
            openBlobOps(1).opcode = OP_OpenRead
            openBlobOps(1).p1 = 0
            openBlobOps(1).p2 = 0
            openBlobOps(1).p3 = 0
            openBlobOps(2).opcode = OP_NotExists
            openBlobOps(2).p1 = 0
            openBlobOps(2).p2 = 5
            openBlobOps(2).p3 = 1
            openBlobOps(3).opcode = OP_Column
            openBlobOps(3).p1 = 0
            openBlobOps(3).p2 = 0
            openBlobOps(3).p3 = 1
            openBlobOps(4).opcode = OP_ResultRow
            openBlobOps(4).p1 = 1
            openBlobOps(4).p2 = 0
            openBlobOps(4).p3 = 0
            openBlobOps(5).opcode = OP_Halt
            openBlobOps(5).p1 = 0
            openBlobOps(5).p2 = 0
            openBlobOps(5).p3 = 0

            Dim pOp As SqliteVdbeOp Ptr = sqlite3VdbeAddOpList( _
                pVdbe, 6, @openBlobOps(0), VDBEBLOB_OP_LINE)
            sqlite3VdbeUsesBtree(pVdbe, databaseIndex)
            If db->mallocFailed <> 0 Then
                rc = SQLITE_NOMEM
                Exit Do
            End If
            If pOp = 0 Then
                rc = SQLITE_NOMEM
                Exit Do
            End If

#ifdef SQLITE_OMIT_SHARED_CACHE
            pOp[0].opcode = OP_Noop
#else
            pOp[0].p1 = databaseIndex
            pOp[0].p2 = pTable->tnum
            pOp[0].p3 = writable
            sqlite3VdbeChangeP4(pVdbe, 2, pTable->zName, P4_TRANSIENT)
#endif
            If writable <> 0 Then pOp[1].opcode = OP_OpenWrite
            pOp[1].p2 = pTable->tnum
            pOp[1].p3 = databaseIndex
            pOp[1].p4type = P4_INT32
            pOp[1].p4.i = pTable->nCol + 1
            pOp[3].p2 = pTable->nCol
            pParse.nVar = 0
            pParse.nMem = 1
            pParse.nTab = 1
            sqlite3VdbeMakeReady(pVdbe, @pParse)
            Exit Do
        Loop

        sqlite3BtreeLeaveAll(db)
        If pParse.zErrMsg <> 0 Then
            sqlite3DbFree(db, zError)
            zError = pParse.zErrMsg
            pParse.zErrMsg = 0
        End If
        If rc <> SQLITE_OK OrElse db->mallocFailed <> 0 Then
            If db->mallocFailed <> 0 AndAlso rc = SQLITE_OK Then rc = SQLITE_NOMEM
            Exit Do
        End If

        pBlob->iCol = Cast(u16, columnIndex)
        pBlob->db = db
        rc = blobSeekToRow(pBlob, rowid, @zError)
        attempt += 1
        If attempt >= VDBEBLOB_MAX_SCHEMA_RETRY OrElse rc <> SQLITE_SCHEMA Then _
            Exit Do
        sqlite3ParseObjectReset(@pParse)
    Loop

    If rc = SQLITE_OK AndAlso db->mallocFailed = 0 Then
        ppBlob[0] = pBlob
    Else
        If pBlob AndAlso pBlob->pStmt Then sqlite3VdbeFinalize(pBlob->pStmt)
        sqlite3DbFree(db, pBlob)
    End If
    If zError Then
        sqlite3ErrorWithMsg(db, rc, StrPtr(!"%s"), zError)
    Else
        sqlite3ErrorWithMsg(db, rc, 0)
    End If
    sqlite3DbFree(db, zError)
    sqlite3ParseObjectReset(@pParse)
    rc = sqlite3ApiExit(db, rc)
    sqlite3_mutex_leave(db->mutex)
    Return rc
End Function

/' end of sqlite3_bulk_vdbeblob.bas '/
