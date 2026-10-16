/'
    Project: SQLite FreeBASIC port

    File: sqlite3_backup.bas

    Purpose:

        Provide backup-state accessors and helpers for the backup API.

    Responsibilities:

        - Match the destination page size to the source B-tree.
        - Classify BUSY and LOCKED results as retryable backup outcomes.
        - Return remaining and source page counts from a backup context.
        - Allocate backup state and retain the destination schema name.
        - Detach finished backups and reset page progress after source changes.
        - Copy modified source pages into active backups through pager callbacks.
        - Copy a complete B-tree file for the VACUUM subsystem.

    This file intentionally does NOT contain:

        - VACUUM statement parsing, planning, or VDBE generation.
'/ 

#lang "fb"
#include once "sqlite3_constants.bi"
#include once "sqlite3_api_constants.bi"
#include once "sqlite3_btree.bi"
#include once "sqlite3_vfs.bi"
#include once "sqlite3_pager.bi"
#include once "sqlite3_mutex.bi"
#include once "sqlite3_parser_types.bi"
#include once "sqlite3_varint.bi"
#include once "sqlite3_backup_types.bi"

Declare Function sqlite3MisuseError CDecl Alias "sqlite3MisuseError" ( _
    ByVal lineNumber As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Sub sqlite3LeaveMutexAndCloseZombie CDecl Alias "sqlite3LeaveMutexAndCloseZombie" ( _
    ByVal dbArgument As Any Ptr _
)
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" ( _
    ByVal allocation As Any Ptr _
)
Declare Function c2fb_crt_memcpy CDecl Alias "memcpy" ( _
    ByVal destination As Any Ptr, _
    ByVal source As Const Any Ptr, _
    ByVal byteCount As SQLITE_SIZE_T _
) As Any Ptr
Declare Function c2fb_crt_memset CDecl Alias "memset" ( _
    ByVal destination As Any Ptr, _
    ByVal value As SQLITE_C_INT, _
    ByVal byteCount As SQLITE_SIZE_T _
) As Any Ptr
Declare Function sqlite3MallocZero CDecl Alias "sqlite3MallocZero" ( _
    ByVal byteCount As sqlite3_uint64 _
) As Any Ptr
Declare Function sqlite3Strlen30 CDecl Alias "sqlite3Strlen30" ( _
    ByVal zText As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3FindDbName CDecl Alias "sqlite3FindDbName" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3OpenTempDatabase CDecl Alias "sqlite3OpenTempDatabase" ( _
    ByVal pParse As SqliteParseContext Ptr _
) As SQLITE_C_INT
Declare Function sqlite3SafetyCheckOk CDecl Alias "sqlite3SafetyCheckOk" ( _
    ByVal db As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3ParseObjectInit CDecl Alias "sqlite3ParseObjectInit" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal db As sqlite3 Ptr _
)
Declare Sub sqlite3ParseObjectReset CDecl Alias "sqlite3ParseObjectReset" ( _
    ByVal pParse As SqliteParseContext Ptr _
)
Declare Sub sqlite3ResetAllSchemasOfConnection CDecl Alias "sqlite3ResetAllSchemasOfConnection" ( _
    ByVal db As Any Ptr _
)
Declare Sub attachBackupObject CDecl Alias "attachBackupObject" ( _
    ByVal pBackup As SqliteBackupContext Ptr _
)

' Source line numbers used by SQLITE_MISUSE_BKPT in src/backup.c.
Private Const BACKUP_REMAINING_MISUSE_LINE As SQLITE_C_INT = 657
Private Const BACKUP_PAGECOUNT_MISUSE_LINE As SQLITE_C_INT = 671
Private Const BACKUP_INIT_MISUSE_LINE As SQLITE_C_INT = 151
Private Const BACKUP_STEP_MISUSE_LINE As SQLITE_C_INT = 332
' SQLITE_IOERR_NOMEM is SQLITE_IOERR with the NOMEM extended-code byte (12).
Private Const BACKUP_IOERR_NOMEM_CODE As SQLITE_C_INT = SQLITE_IOERR Or &H0C00

Private Function setDestPgsz CDecl Alias "setDestPgsz" ( _
    ByVal pDestination As Btree Ptr, _
    ByVal pSource As Btree Ptr _
) As SQLITE_C_INT
    If pDestination = 0 OrElse pSource = 0 Then Return SQLITE_MISUSE
    Return sqlite3BtreeSetPageSize(pDestination, _
        sqlite3BtreeGetPageSize(pSource), 0, 0)
End Function

Private Function findBtree CDecl Alias "findBtree" ( _
    ByVal pErrorDb As sqlite3 Ptr, _
    ByVal db As sqlite3 Ptr, _
    ByVal zDatabase As Const ZString Ptr _
) As Btree Ptr
    If pErrorDb = 0 OrElse db = 0 OrElse zDatabase = 0 Then Return 0

    Dim databaseIndex As SQLITE_C_INT = sqlite3FindDbName(db, zDatabase)
    If databaseIndex = 1 Then
        Dim parseContext As SqliteParseContext
        sqlite3ParseObjectInit(@parseContext, db)
        If sqlite3OpenTempDatabase(@parseContext) <> SQLITE_OK Then
            sqlite3ErrorWithMsg(pErrorDb, parseContext.rc, StrPtr("%s"), _
                                parseContext.zErrMsg)
            sqlite3DbFree(pErrorDb, parseContext.zErrMsg)
            sqlite3ParseObjectReset(@parseContext)
            Return 0
        End If
        sqlite3DbFree(pErrorDb, parseContext.zErrMsg)
        sqlite3ParseObjectReset(@parseContext)
    End If

    If databaseIndex < 0 Then
        sqlite3ErrorWithMsg(pErrorDb, SQLITE_ERROR, _
                            StrPtr("unknown database %s"), zDatabase)
        Return 0
    End If

    Return CPtr(Btree Ptr, db->aDb(databaseIndex).pBt)
End Function

Private Function checkReadTransaction CDecl Alias "checkReadTransaction" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pBtree As Btree Ptr _
) As SQLITE_C_INT
    If db = 0 OrElse pBtree = 0 Then Return SQLITE_MISUSE
    If sqlite3BtreeTxnState(pBtree) <> TRANS_NONE Then
        sqlite3ErrorWithMsg(db, SQLITE_ERROR, _
                            StrPtr("destination database is in use"))
        Return SQLITE_ERROR
    End If
    Return SQLITE_OK
End Function

Private Function backupTruncateFile CDecl Alias "backupTruncateFile" ( _
    ByVal pFile As sqlite3_file Ptr, _
    ByVal targetSize As sqlite3_int64 _
) As SQLITE_C_INT
    If pFile = 0 OrElse pFile->pMethods = 0 Then Return SQLITE_IOERR
    Dim currentSize As sqlite3_int64 = 0
    Dim resultCode As SQLITE_C_INT = sqlite3OsFileSize(pFile, @currentSize)
    If resultCode = SQLITE_OK AndAlso currentSize > targetSize Then
        resultCode = sqlite3OsTruncate(pFile, targetSize)
    End If
    Return resultCode
End Function

' The destination handle is held only for initialization. Callers must not
' use it concurrently until the backup finishes.
Function sqlite3_backup_init CDecl Alias "sqlite3_backup_init" ( _
    ByVal pDestDb As sqlite3 Ptr, _
    ByVal zDestDb As Const ZString Ptr, _
    ByVal pSrcDb As sqlite3 Ptr, _
    ByVal zSrcDb As Const ZString Ptr _
) As SqliteBackupContext Ptr Export
#ifdef SQLITE_ENABLE_API_ARMOR
    If sqlite3SafetyCheckOk(pSrcDb) = 0 OrElse _
       sqlite3SafetyCheckOk(pDestDb) = 0 Then
        sqlite3MisuseError(BACKUP_INIT_MISUSE_LINE)
        Return 0
    End If
#endif
    If pDestDb = 0 OrElse pSrcDb = 0 OrElse zDestDb = 0 OrElse zSrcDb = 0 Then _
        Return 0

    sqlite3_mutex_enter(pSrcDb->mutex)
    sqlite3_mutex_enter(pDestDb->mutex)

    Dim pBackup As SqliteBackupContext Ptr = 0
    If pSrcDb = pDestDb Then
        sqlite3ErrorWithMsg(pDestDb, SQLITE_ERROR, _
                            StrPtr("source and destination must be distinct"))
    Else
        Dim destinationNameLength As SQLITE_C_INT = sqlite3Strlen30(zDestDb)
        If destinationNameLength >= 0 Then
            Dim allocationSize As sqlite3_uint64 = _
                Cast(sqlite3_uint64, SizeOf(SqliteBackupContext)) + _
                Cast(sqlite3_uint64, destinationNameLength) + 1
            pBackup = CPtr(SqliteBackupContext Ptr, _
                           sqlite3MallocZero(allocationSize))
        End If

        If pBackup = 0 Then
            sqlite3Error(pDestDb, SQLITE_NOMEM)
        Else
            pBackup->zDestDb = CPtr(ZString Ptr, _
                CPtr(UByte Ptr, pBackup) + SizeOf(SqliteBackupContext))
            c2fb_crt_memcpy(CPtr(Any Ptr, pBackup->zDestDb), _
                CPtr(Const Any Ptr, zDestDb), _
                Cast(SQLITE_SIZE_T, destinationNameLength))
        End If
    End If

    If pBackup <> 0 Then
        Dim pDestBtree As Btree Ptr = findBtree(pDestDb, pDestDb, zDestDb)
        pBackup->pSrc = findBtree(pDestDb, pSrcDb, zSrcDb)
        pBackup->pDestDb = pDestDb
        pBackup->pSrcDb = pSrcDb
        pBackup->iNext = 1
        pBackup->isAttached = 0

        If pBackup->pSrc = 0 OrElse pDestBtree = 0 OrElse _
           checkReadTransaction(pDestDb, pDestBtree) <> SQLITE_OK Then
            sqlite3_free(CPtr(Any Ptr, pBackup))
            pBackup = 0
        End If
    End If

    If pBackup <> 0 Then pBackup->pSrc->nBackup += 1
    sqlite3_mutex_leave(pDestDb->mutex)
    sqlite3_mutex_leave(pSrcDb->mutex)
    Return pBackup
End Function

Private Function isFatalError CDecl Alias "isFatalError" ( _
    ByVal resultCode As SQLITE_C_INT _
) As SQLITE_C_INT
    If resultCode = SQLITE_OK OrElse resultCode = SQLITE_BUSY OrElse _
       resultCode = SQLITE_LOCKED Then Return 0
    Return 1
End Function

' A source page may span multiple destination pages when page sizes differ.
Private Function backupOnePage CDecl Alias "backupOnePage" ( _
    ByVal pBackup As SqliteBackupContext Ptr, _
    ByVal sourcePageNumber As u32, _
    ByVal sourceData As Const UByte Ptr, _
    ByVal isUpdate As SQLITE_C_INT _
) As SQLITE_C_INT
    If pBackup = 0 OrElse pBackup->pSrc = 0 OrElse _
       pBackup->pDest = 0 OrElse sourceData = 0 Then
        Return SQLITE_MISUSE
    End If

    Dim destinationPager As Pager Ptr = sqlite3BtreePager(pBackup->pDest)
    Dim sourcePageSize As SQLITE_C_INT = _
        sqlite3BtreeGetPageSize(pBackup->pSrc)
    Dim destinationPageSize As SQLITE_C_INT = _
        sqlite3BtreeGetPageSize(pBackup->pDest)
    If destinationPager = 0 OrElse sourcePageSize <= 0 OrElse _
       destinationPageSize <= 0 Then
        Return SQLITE_MISUSE
    End If

    Dim copySize As SQLITE_C_INT = sourcePageSize
    If destinationPageSize < copySize Then copySize = destinationPageSize

    Dim pageEnd As sqlite3_int64 = _
        Cast(sqlite3_int64, sourcePageNumber) * Cast(sqlite3_int64, sourcePageSize)
    Dim pageOffset As sqlite3_int64 = pageEnd - sourcePageSize
    Dim resultCode As SQLITE_C_INT = SQLITE_OK
    Dim destinationPendingPage As u32 = _
        Cast(u32, (PENDING_BYTE \ destinationPageSize) + 1)

    While resultCode = SQLITE_OK AndAlso pageOffset < pageEnd
        Dim destinationPageNumber As u32 = _
            Cast(u32, (pageOffset \ destinationPageSize) + 1)

        If destinationPageNumber <> destinationPendingPage Then
            Dim destinationPage As PgHdr Ptr = 0
            resultCode = sqlite3PagerGet(destinationPager, _
                                         destinationPageNumber, _
                                         @destinationPage, 0)
            If resultCode = SQLITE_OK Then
                resultCode = sqlite3PagerWrite(destinationPage)
            End If

            If resultCode = SQLITE_OK Then
                Dim sourceOffset As SQLITE_C_INT = _
                    Cast(SQLITE_C_INT, pageOffset Mod sourcePageSize)
                Dim destinationOffset As SQLITE_C_INT = _
                    Cast(SQLITE_C_INT, pageOffset Mod destinationPageSize)
                Dim sourcePageData As Const UByte Ptr = _
                    CPtr(Const UByte Ptr, sourceData + sourceOffset)
                Dim destinationPageData As UByte Ptr = _
                    CPtr(UByte Ptr, sqlite3PagerGetData(destinationPage))
                Dim copyDestination As Any Ptr = _
                    CPtr(Any Ptr, destinationPageData + destinationOffset)

                c2fb_crt_memcpy(copyDestination, sourcePageData, _
                    Cast(SQLITE_SIZE_T, copySize))

                ' Clear the first extra byte so the B-tree reparses the page.
                Dim extraData As UByte Ptr = _
                    CPtr(UByte Ptr, sqlite3PagerGetExtra(destinationPage))
                If extraData <> 0 Then extraData[0] = 0

                If pageOffset = 0 AndAlso isUpdate = 0 Then
                    sqlite3Put4byte(destinationPageData + 28, _
                                    sqlite3BtreeLastPage(pBackup->pSrc))
                End If
            End If

            sqlite3PagerUnref(destinationPage)
        End If

        pageOffset += destinationPageSize
    Wend

    Return resultCode
End Function

' The pager holds the source BtShared mutex while processing these updates.
Private Sub backupUpdate CDecl Alias "backupUpdate" ( _
    ByVal pFirstBackup As SqliteBackupContext Ptr, _
    ByVal sourcePageNumber As u32, _
    ByVal sourceData As Const UByte Ptr _
)
    Dim pBackup As SqliteBackupContext Ptr = pFirstBackup
    While pBackup <> 0
        If isFatalError(pBackup->rc) = 0 AndAlso _
           sourcePageNumber < pBackup->iNext Then
            If pBackup->pDestDb <> 0 Then
                sqlite3_mutex_enter(pBackup->pDestDb->mutex)
                Dim resultCode As SQLITE_C_INT = _
                    backupOnePage(pBackup, sourcePageNumber, sourceData, 1)
                sqlite3_mutex_leave(pBackup->pDestDb->mutex)
                If resultCode <> SQLITE_OK Then pBackup->rc = resultCode
            Else
                pBackup->rc = SQLITE_MISUSE
            End If
        End If
        pBackup = CPtr(SqliteBackupContext Ptr, pBackup->pNext)
    Wend
End Sub

' Copy source pages, update the destination schema, and commit the final image.
Function sqlite3_backup_step CDecl Alias "sqlite3_backup_step" ( _
    ByVal backupArgument As Any Ptr, _
    ByVal pageLimit As SQLITE_C_INT _
) As SQLITE_C_INT Export
#ifdef SQLITE_ENABLE_API_ARMOR
    If backupArgument = 0 Then
        sqlite3MisuseError(BACKUP_STEP_MISUSE_LINE)
        Return SQLITE_MISUSE
    End If
#endif
    If backupArgument = 0 Then Return SQLITE_MISUSE

    Dim pBackup As SqliteBackupContext Ptr = _
        CPtr(SqliteBackupContext Ptr, backupArgument)
    If pBackup->pSrcDb = 0 OrElse pBackup->pSrc = 0 Then _
        Return SQLITE_MISUSE

    sqlite3_mutex_enter(pBackup->pSrcDb->mutex)
    sqlite3BtreeEnter(pBackup->pSrc)
    If pBackup->pDestDb <> 0 Then
        sqlite3_mutex_enter(pBackup->pDestDb->mutex)
    End If

    Dim resultCode As SQLITE_C_INT = pBackup->rc
    If isFatalError(resultCode) = 0 Then
        Dim sourcePager As Pager Ptr = sqlite3BtreePager(pBackup->pSrc)
        Dim pDest As Btree Ptr = 0
        Dim destinationPager As Pager Ptr = 0
        Dim sourcePageCount As SQLITE_C_INT = -1
        Dim closeSourceTransaction As SQLITE_C_INT = 0
        Dim sourcePageSize As SQLITE_C_INT = 0
        Dim destinationPageSize As SQLITE_C_INT = 0
        Dim destinationJournalMode As SQLITE_C_INT = 0

        If pBackup->pDestDb <> 0 AndAlso pBackup->pSrc->pBt <> 0 AndAlso _
           pBackup->pSrc->pBt->inTransaction = TRANS_WRITE Then
            resultCode = SQLITE_BUSY
        Else
            resultCode = SQLITE_OK
        End If

        If resultCode = SQLITE_OK AndAlso _
           sqlite3BtreeTxnState(pBackup->pSrc) = TRANS_NONE Then
            resultCode = sqlite3BtreeBeginTrans(pBackup->pSrc, 0, 0)
            closeSourceTransaction = 1
        End If

        pDest = pBackup->pDest
        If pDest = 0 Then
            pDest = findBtree(pBackup->pDestDb, pBackup->pDestDb, _
                              pBackup->zDestDb)
        End If
        If pDest = 0 Then
            resultCode = SQLITE_ERROR
        Else
            destinationPager = sqlite3BtreePager(pDest)
        End If

        If pBackup->bDestLocked = 0 AndAlso resultCode = SQLITE_OK AndAlso _
           setDestPgsz(pDest, pBackup->pSrc) = SQLITE_NOMEM Then
            resultCode = SQLITE_NOMEM
        End If

        If resultCode = SQLITE_OK AndAlso pBackup->bDestLocked = 0 Then
            resultCode = sqlite3BtreeBeginTrans( _
                pDest, 2, CPtr(SQLITE_C_INT Ptr, @pBackup->iDestSchema))
            If resultCode = SQLITE_OK Then
                pBackup->bDestLocked = 1
                pBackup->pDest = pDest
            End If
        End If

        If resultCode = SQLITE_OK Then
            sourcePageSize = sqlite3BtreeGetPageSize(pBackup->pSrc)
            destinationPageSize = sqlite3BtreeGetPageSize(pBackup->pDest)
            destinationPager = sqlite3BtreePager(pBackup->pDest)
            destinationJournalMode = _
                sqlite3PagerGetJournalMode(destinationPager)
            If (destinationJournalMode = PAGER_JOURNALMODE_WAL OrElse _
                sqlite3PagerIsMemdb(destinationPager) <> 0) AndAlso _
               sourcePageSize <> destinationPageSize Then
                resultCode = SQLITE_READONLY
            End If
        End If

        sourcePageCount = Cast(SQLITE_C_INT, _
            sqlite3BtreeLastPage(pBackup->pSrc))
        Dim sourcePageLimit As u32 = Cast(u32, sourcePageCount)
        Dim sourcePendingPage As u32 = 0
        If resultCode = SQLITE_OK Then
            If sourcePageSize > 0 Then
                sourcePendingPage = Cast(u32, _
                    (PENDING_BYTE \ sourcePageSize) + 1)
            Else
                resultCode = SQLITE_CORRUPT
            End If
        End If
        Dim pagesProcessed As SQLITE_C_INT = 0

        While (pageLimit < 0 OrElse pagesProcessed < pageLimit) AndAlso _
              pBackup->iNext <= sourcePageLimit AndAlso _
              resultCode = SQLITE_OK
            Dim sourcePageNumber As u32 = pBackup->iNext
            If sourcePageNumber <> sourcePendingPage Then
                Dim sourcePage As PgHdr Ptr = 0
                resultCode = sqlite3PagerGet(sourcePager, sourcePageNumber, _
                                             @sourcePage, PAGER_GET_READONLY)
                If resultCode = SQLITE_OK Then
                    resultCode = backupOnePage( _
                        pBackup, sourcePageNumber, _
                        CPtr(Const UByte Ptr, sqlite3PagerGetData(sourcePage)), 0)
                    sqlite3PagerUnref(sourcePage)
                End If
            End If
            pBackup->iNext += 1
            pagesProcessed += 1
        Wend

        If resultCode = SQLITE_OK Then
            pBackup->nPagecount = sourcePageLimit
            pBackup->nRemaining = Cast(u32, sourcePageCount + 1) - _
                                  pBackup->iNext
            If pBackup->iNext > sourcePageLimit Then
                resultCode = SQLITE_DONE
            ElseIf pBackup->isAttached = 0 Then
                attachBackupObject(pBackup)
            End If
        End If

        If resultCode = SQLITE_DONE Then
            If sourcePageCount = 0 Then
                resultCode = sqlite3BtreeNewDb(pBackup->pDest)
                sourcePageCount = 1
            End If
            If resultCode = SQLITE_OK OrElse resultCode = SQLITE_DONE Then
                resultCode = sqlite3BtreeUpdateMeta( _
                    pBackup->pDest, 1, pBackup->iDestSchema + 1)
            End If
            If resultCode = SQLITE_OK Then
                If pBackup->pDestDb <> 0 Then
                    sqlite3ResetAllSchemasOfConnection(pBackup->pDestDb)
                End If
                If destinationJournalMode = PAGER_JOURNALMODE_WAL Then
                    resultCode = sqlite3BtreeSetVersion(pBackup->pDest, 2)
                End If
            End If

            If resultCode = SQLITE_OK Then
                Dim destinationPagesToKeep As SQLITE_C_INT
                If sourcePageSize < destinationPageSize Then
                    Dim pageSizeRatio As SQLITE_C_INT = _
                        destinationPageSize \ sourcePageSize
                    destinationPagesToKeep = _
                        (sourcePageCount + pageSizeRatio - 1) \ pageSizeRatio
                    Dim destinationPendingPage As SQLITE_C_INT = _
                        Cast(SQLITE_C_INT, _
                            (PENDING_BYTE \ destinationPageSize) + 1)
                    If destinationPagesToKeep = destinationPendingPage Then
                        destinationPagesToKeep -= 1
                    End If
                Else
                    destinationPagesToKeep = sourcePageCount * _
                        (sourcePageSize \ destinationPageSize)
                End If

                If sourcePageSize < destinationPageSize Then
                    Dim fileSize As sqlite3_int64 = _
                        Cast(sqlite3_int64, sourcePageSize) * sourcePageCount
                    Dim pFile As sqlite3_file Ptr = _
                        sqlite3PagerFile(destinationPager)
                    Dim destinationFilePageCount As SQLITE_C_INT = 0
                    If pFile = 0 Then
                        resultCode = SQLITE_IOERR
                    Else
                        sqlite3PagerPagecount(destinationPager, _
                                              @destinationFilePageCount)
                    End If

                    Dim destinationPageNumber As u32 = _
                        Cast(u32, destinationPagesToKeep)
                    Dim destinationPendingPage As u32 = _
                        Cast(u32, (PENDING_BYTE \ destinationPageSize) + 1)
                    While resultCode = SQLITE_OK AndAlso _
                          destinationPageNumber <= _
                              Cast(u32, destinationFilePageCount)
                        If destinationPageNumber <> destinationPendingPage Then
                            Dim destinationPage As PgHdr Ptr = 0
                            resultCode = sqlite3PagerGet( _
                                destinationPager, destinationPageNumber, _
                                @destinationPage, 0)
                            If resultCode = SQLITE_OK Then
                                resultCode = sqlite3PagerWrite(destinationPage)
                                sqlite3PagerUnref(destinationPage)
                            End If
                        End If
                        destinationPageNumber += 1
                    Wend

                    If resultCode = SQLITE_OK Then
                        resultCode = sqlite3PagerCommitPhaseOne( _
                            destinationPager, 0, 1)
                    End If

                    Dim pendingByteEnd As sqlite3_int64 = _
                        Cast(sqlite3_int64, PENDING_BYTE) + _
                        destinationPageSize
                    Dim sourceDataEnd As sqlite3_int64 = fileSize
                    If pendingByteEnd < sourceDataEnd Then _
                        sourceDataEnd = pendingByteEnd
                    Dim fileOffset As sqlite3_int64 = _
                        Cast(sqlite3_int64, PENDING_BYTE) + sourcePageSize

                    While resultCode = SQLITE_OK AndAlso fileOffset < sourceDataEnd
                        Dim sourcePageNumber As u32 = _
                            Cast(u32, (fileOffset \ sourcePageSize) + 1)
                        Dim sourcePage As PgHdr Ptr = 0
                        resultCode = sqlite3PagerGet(sourcePager, _
                            sourcePageNumber, @sourcePage, 0)
                        If resultCode = SQLITE_OK Then
                            Dim pageData As Any Ptr = _
                                sqlite3PagerGetData(sourcePage)
                            resultCode = sqlite3OsWrite( _
                                pFile, pageData, sourcePageSize, fileOffset)
                        End If
                        sqlite3PagerUnref(sourcePage)
                        fileOffset += sourcePageSize
                    Wend

                    If resultCode = SQLITE_OK Then
                        resultCode = backupTruncateFile(pFile, fileSize)
                    End If
                    If resultCode = SQLITE_OK Then
                        resultCode = sqlite3PagerSync(destinationPager, 0)
                    End If
                Else
                    sqlite3PagerTruncateImage(destinationPager, _
                        Cast(u32, destinationPagesToKeep))
                    resultCode = sqlite3PagerCommitPhaseOne( _
                        destinationPager, 0, 0)
                End If

                If resultCode = SQLITE_OK Then
                    resultCode = sqlite3BtreeCommitPhaseTwo(pBackup->pDest, 0)
                    If resultCode = SQLITE_OK Then resultCode = SQLITE_DONE
                End If
            End If
        End If

#ifdef SQLITE_DEBUG
        If closeSourceTransaction <> 0 Then
            sqlite3BtreeCommitPhaseOne(pBackup->pSrc, 0)
            sqlite3BtreeCommitPhaseTwo(pBackup->pSrc, 0)
        End If
#endif

        If resultCode = BACKUP_IOERR_NOMEM_CODE Then resultCode = SQLITE_NOMEM
        pBackup->rc = resultCode
    End If

    If pBackup->pDestDb <> 0 Then
        sqlite3_mutex_leave(pBackup->pDestDb->mutex)
    End If
    sqlite3BtreeLeave(pBackup->pSrc)
    sqlite3_mutex_leave(pBackup->pSrcDb->mutex)
    Return resultCode
End Function

Function sqlite3_backup_remaining CDecl Alias "sqlite3_backup_remaining" ( _
    ByVal backupArgument As Any Ptr _
) As SQLITE_C_INT Export
#ifdef SQLITE_ENABLE_API_ARMOR
    If backupArgument = 0 Then
        sqlite3MisuseError(BACKUP_REMAINING_MISUSE_LINE)
        Return 0
    End If
#endif
    Dim pBackup As SqliteBackupContext Ptr = _
        CPtr(SqliteBackupContext Ptr, backupArgument)
    Return Cast(SQLITE_C_INT, pBackup->nRemaining)
End Function

Function sqlite3_backup_pagecount CDecl Alias "sqlite3_backup_pagecount" ( _
    ByVal backupArgument As Any Ptr _
) As SQLITE_C_INT Export
#ifdef SQLITE_ENABLE_API_ARMOR
    If backupArgument = 0 Then
        sqlite3MisuseError(BACKUP_PAGECOUNT_MISUSE_LINE)
        Return 0
    End If
#endif
    Dim pBackup As SqliteBackupContext Ptr = _
        CPtr(SqliteBackupContext Ptr, backupArgument)
    Return Cast(SQLITE_C_INT, pBackup->nPagecount)
End Function

' Pager callbacks hold the source BtShared mutex while adding this object to the list.
Private Sub attachBackupObject CDecl Alias "attachBackupObject" (ByVal arg0 As SqliteBackupContext Ptr)
    Dim local0 As SqliteBackupContext Ptr Ptr
    Dim c2fb_temp_0 As SqliteBackupContext Ptr Ptr
    Dim c2fb_temp_1 As Any Ptr Ptr
    Dim c2fb_temp_2 As SqliteBackupContext Ptr
    Dim c2fb_temp_3 As SqliteBackupContext Ptr Ptr
    Dim c2fb_temp_4 As SqliteBackupContext Ptr
    Dim c2fb_temp_5 As SQLITE_C_INT Ptr
    Dim c2fb_temp_6 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(SqliteBackupContext Ptr Ptr, sqlite3PagerBackupPtr(CPtr(Pager Ptr, sqlite3BtreePager(arg0->pSrc))))
    local0 = CPtr(SqliteBackupContext Ptr Ptr, sqlite3PagerBackupPtr(CPtr(Pager Ptr, sqlite3BtreePager(arg0->pSrc))))
    c2fb_temp_1 = @(arg0->pNext)
    c2fb_temp_2 = (*local0)
    (*c2fb_temp_1) = CPtr(Any Ptr, (*local0))
    c2fb_temp_2 = CPtr(SqliteBackupContext Ptr, (*c2fb_temp_1))
    c2fb_temp_3 = @((*local0))
    c2fb_temp_4 = arg0
    (*c2fb_temp_3) = arg0
    c2fb_temp_5 = @(arg0->isAttached)
    c2fb_temp_6 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
    (*c2fb_temp_5) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
End Sub


' Lock order follows backup_finish(): source connection, source B-tree, then destination connection.
Function sqlite3_backup_finish CDecl Alias "sqlite3_backup_finish" (ByVal arg0 As SqliteBackupContext Ptr) As SQLITE_C_INT Export
    Dim local0 As SqliteBackupContext Ptr Ptr
    Dim local1 As sqlite3 Ptr
    Dim local2 As SQLITE_C_INT
    Dim c2fb_temp_0 As sqlite3 Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT Ptr
    Dim c2fb_temp_2 As SQLITE_C_INT
    Dim c2fb_temp_3 As SqliteBackupContext Ptr Ptr
    Dim c2fb_temp_4 As SqliteBackupContext Ptr Ptr
    Dim c2fb_temp_5 As SqliteBackupContext Ptr Ptr
    Dim c2fb_temp_6 As SqliteBackupContext Ptr
    Dim c2fb_temp_7 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, ((arg0 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = arg0->pSrcDb
    local1 = arg0->pSrcDb
    sqlite3_mutex_enter(local1->mutex)
    sqlite3BtreeEnter(arg0->pSrc)
    If arg0->pDestDb Then
        sqlite3_mutex_enter(arg0->pDestDb->mutex)
    End If
    If arg0->pDestDb Then
        c2fb_temp_1 = @(arg0->pSrc->nBackup)
        c2fb_temp_2 = (*c2fb_temp_1)
        (*c2fb_temp_1) = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, (c2fb_temp_2 - 1)))
    End If
    If arg0->isAttached Then
        c2fb_temp_3 = CPtr(SqliteBackupContext Ptr Ptr, sqlite3PagerBackupPtr(CPtr(Pager Ptr, sqlite3BtreePager(arg0->pSrc))))
        local0 = CPtr(SqliteBackupContext Ptr Ptr, sqlite3PagerBackupPtr(CPtr(Pager Ptr, sqlite3BtreePager(arg0->pSrc))))
        ' C unused-parameter annotation
        While (-Cast(SQLITE_C_INT, (((*local0) <> arg0))))
            c2fb_temp_4 = CPtr(SqliteBackupContext Ptr Ptr, @(((*local0))->pNext))
            local0 = CPtr(SqliteBackupContext Ptr Ptr, @(((*local0))->pNext))
            ' C unused-parameter annotation
        c2fb_flow_1:
        Wend
        c2fb_flow_0:
        c2fb_temp_5 = @((*local0))
        c2fb_temp_6 = CPtr(SqliteBackupContext Ptr, arg0->pNext)
        (*c2fb_temp_5) = CPtr(SqliteBackupContext Ptr, arg0->pNext)
    End If
    If arg0->pDest Then
        sqlite3BtreeRollback(arg0->pDest, Cast(SQLITE_C_INT, &O0ULL), Cast(SQLITE_C_INT, &O0ULL))
    End If
    c2fb_temp_7 = Cast(SQLITE_C_INT, IIf(((-Cast(SQLITE_C_INT, ((arg0->rc = Cast(SQLITE_C_INT, 101ULL)))))), Cast(SQLITE_C_INT, &O0ULL), arg0->rc))
    local2 = Cast(SQLITE_C_INT, IIf(((-Cast(SQLITE_C_INT, ((arg0->rc = Cast(SQLITE_C_INT, 101ULL)))))), Cast(SQLITE_C_INT, &O0ULL), arg0->rc))
    If arg0->pDestDb Then
        sqlite3Error(CPtr(Any Ptr, arg0->pDestDb), local2)
        sqlite3LeaveMutexAndCloseZombie(CPtr(Any Ptr, arg0->pDestDb))
    End If
    sqlite3BtreeLeave(arg0->pSrc)
    If arg0->pDestDb Then
        sqlite3_free(CPtr(Any Ptr, arg0))
    End If
    sqlite3LeaveMutexAndCloseZombie(CPtr(Any Ptr, local1))
    Return local2
End Function


' Pager callbacks call this with the source BtShared mutex held. Reset every backup in the list.
Sub sqlite3BackupRestart CDecl Alias "sqlite3BackupRestart" (ByVal arg0 As SqliteBackupContext Ptr)
    Dim local0 As SqliteBackupContext Ptr
    Dim c2fb_temp_0 As SqliteBackupContext Ptr
    Dim c2fb_temp_1 As SqliteBackupContext Ptr
    Dim c2fb_temp_2 As u32 Ptr
    Dim c2fb_temp_3 As SQLITE_C_UINT

    ' C automatic storage declaration
    c2fb_temp_0 = arg0
    local0 = arg0
    While local0
        ' C unused-parameter annotation
        c2fb_temp_2 = @(local0->iNext)
        c2fb_temp_3 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))
        (*c2fb_temp_2) = Cast(u32, Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))
        c2fb_temp_3 = Cast(SQLITE_C_UINT, (*c2fb_temp_2))
    c2fb_flow_1:
        c2fb_temp_1 = CPtr(SqliteBackupContext Ptr, local0->pNext)
        local0 = CPtr(SqliteBackupContext Ptr, local0->pNext)
    Wend
    c2fb_flow_0:
End Sub

Sub sqlite3BackupUpdate CDecl Alias "sqlite3BackupUpdate" ( _
    ByVal backupArgument As Any Ptr, _
    ByVal sourcePageNumber As u32, _
    ByVal sourceData As Const UByte Ptr _
)
    If backupArgument = 0 Then Return
    backupUpdate(CPtr(SqliteBackupContext Ptr, backupArgument), _
                 sourcePageNumber, sourceData)
End Sub


#ifndef SQLITE_OMIT_VACUUM
Function sqlite3BtreeCopyFile CDecl Alias "sqlite3BtreeCopyFile" ( _
    ByVal pDestination As Btree Ptr, _
    ByVal pSource As Btree Ptr _
) As SQLITE_C_INT
    If pDestination = 0 OrElse pSource = 0 OrElse _
       pDestination->pBt = 0 OrElse pSource->pBt = 0 Then
        Return SQLITE_MISUSE
    End If

    sqlite3BtreeEnter(pDestination)
    sqlite3BtreeEnter(pSource)
    Dim resultCode As SQLITE_C_INT = SQLITE_OK
    Dim pFile As sqlite3_file Ptr = _
        sqlite3PagerFile(sqlite3BtreePager(pDestination))

    If pFile = 0 Then
        resultCode = SQLITE_IOERR
    ElseIf pFile->pMethods <> 0 Then
        Dim outputSize As sqlite3_int64 = _
            Cast(sqlite3_int64, sqlite3BtreeGetPageSize(pSource)) * _
            Cast(sqlite3_int64, sqlite3BtreeLastPage(pSource))
        resultCode = sqlite3OsFileControl( _
            pFile, SQLITE_FCNTL_OVERWRITE, @outputSize)
        If resultCode = SQLITE_NOTFOUND Then resultCode = SQLITE_OK
    End If

    If resultCode = SQLITE_OK Then
        Dim backup As SqliteBackupContext
        c2fb_crt_memset(CPtr(Any Ptr, @backup), 0, _
                        Cast(SQLITE_SIZE_T, SizeOf(SqliteBackupContext)))
        backup.pSrcDb = pSource->db
        backup.pSrc = pSource
        backup.pDest = pDestination
        backup.iNext = 1

        ' SQLite caps a database at 0x7fffffff pages. Copying that many
        ' pages in one step makes B-tree file replacement a single backup.
        sqlite3_backup_step(@backup, &H7FFFFFFF)
        resultCode = sqlite3_backup_finish(@backup)
        If resultCode = SQLITE_OK Then
            pDestination->pBt->btsFlags = _
                pDestination->pBt->btsFlags And Not BTS_PAGESIZE_FIXED
        Else
            sqlite3PagerClearCache(sqlite3BtreePager(backup.pDest))
        End If
    End If

    sqlite3BtreeLeave(pSource)
    sqlite3BtreeLeave(pDestination)
    Return resultCode
End Function
#endif

/' end of sqlite3_backup.bas '/
