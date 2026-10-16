/'
    Project: SQLite FreeBASIC port

    File: sqlite3_connection.bas

    Purpose:

        Open and close a main database connection through the public C ABI.

    Responsibilities:

        - Initialize per-connection allocation and error state.
        - Install the interrupt mutex before returning an opened connection.
        - Store, replace, and destroy named client data.
        - Retain dynamic VDBE error text until the next connection error.
        - Select a registered VFS and open the main B-tree.
        - Send optional SQLLOG open and close events at connection lifecycle boundaries.
        - Convert native UTF-16 filenames and set the initial database encoding.
        - Initialize and release per-connection collation sequences.
        - Close all connection B-trees and release connection state.
        - Provide the basic connection error and mutex accessors.
        - Allow extensions to set the connection error code and message.
        - Report the temporary-store mode selected for this connection.
        - Configure primary versus extended API result codes.
        - Report the transaction state of the main or temp schema.
        - Report whether temporary databases use memory storage.
        - Release unused pages from the main database pager cache.
        - Flush unreferenced dirty pages from an active main-database write transaction.
        - Report the current SQL error's byte offset.
        - Configure optional VFS blocking-lock timeouts.
        - Log null, unopened, and invalid handles through sqlite3_log().

    This file intentionally does NOT contain:

        - SQL preparation, VDBE execution, or ATTACH/DETACH statement handling.
        - URI filename parsing, configuration, or zombie statement cleanup.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_vfs.bi"
#include once "sqlite3_btree.bi"
#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_vdbe_mem_text.bi"
#include once "sqlite3_sqllog.bi"

#ifndef SQLITE_TEMP_STORE
#define SQLITE_TEMP_STORE 1
#endif

Declare Function sqlite3_initialize CDecl Alias "sqlite3_initialize" () As SQLITE_C_INT
Declare Function sqlite3SafetyCheckSickOrOk CDecl Alias "sqlite3SafetyCheckSickOrOk" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3_log CDecl Alias "sqlite3_log" ( _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Function sqlite3ErrStr CDecl Alias "sqlite3ErrStr" (ByVal resultCode As SQLITE_C_INT) As Const ZString Ptr
Declare Function sqlite3MallocZero CDecl Alias "sqlite3MallocZero" (ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Sub sqlite3Error CDecl Alias "sqlite3Error" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal errorCode As SQLITE_C_INT _
)
Declare Sub sqlite3ErrorWithMsg CDecl Alias "sqlite3ErrorWithMsg" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
)
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)
Declare Function sqlite3_malloc64 CDecl Alias "sqlite3_malloc64" ( _
    ByVal nByte As sqlite3_uint64 _
) As Any Ptr
Declare Function sqlite3ConnectionStrlen CDecl Alias "strlen" ( _
    ByVal zText As Const ZString Ptr _
) As SQLITE_SIZE_T
Declare Sub sqlite3_free_filename CDecl Alias "sqlite3_free_filename" ( _
    ByVal zFilename As Const ZString Ptr _
)
Declare Function sqlite3ParseUri CDecl Alias "sqlite3ParseUri" ( _
    ByVal zDefaultVfs As Const ZString Ptr, _
    ByVal zUri As Const ZString Ptr, _
    ByVal pFlags As SQLITE_C_UINT Ptr, _
    ByVal ppVfs As sqlite3_vfs Ptr Ptr, _
    ByVal pzFile As ZString Ptr Ptr, _
    ByVal pzErrMsg As ZString Ptr Ptr _
) As SQLITE_C_INT
Declare Function sqlite3SchemaGet CDecl Alias "sqlite3SchemaGet" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pBtree As Btree Ptr _
) As SqliteSchema Ptr
Declare Sub sqlite3SchemaClear CDecl Alias "sqlite3SchemaClear" ( _
    ByVal pSchema As Any Ptr _
)
Declare Function sqlite3FindDbName CDecl Alias "sqlite3FindDbName" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr _
) As SQLITE_C_INT
Declare Function sqlite3Utf16to8 CDecl Alias "sqlite3Utf16to8" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal z As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal enc As u8 _
) As ZString Ptr
Declare Function sqlite3CollationInitialize CDecl Alias "sqlite3CollationInitialize" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3CollationClear CDecl Alias "sqlite3CollationClear" ( _
    ByVal db As sqlite3 Ptr _
)
Type SqliteDbClientDataDestructor As Sub CDecl (ByVal pData As Any Ptr)
Declare Sub sqlite3SetTextEncoding CDecl Alias "sqlite3SetTextEncoding" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal encoding As u8 _
)
Declare Function sqlite3ConfigShouldUseConnectionMutex CDecl Alias "sqlite3ConfigShouldUseConnectionMutex" ( _
    ByVal openFlags As SQLITE_C_UINT _
) As SQLITE_C_INT
Declare Sub sqlite3ConfigGetLookaside CDecl Alias "sqlite3ConfigGetLookaside" ( _
    ByVal pSlotSize As SQLITE_C_INT Ptr, _
    ByVal pSlotCount As SQLITE_C_INT Ptr _
)
Declare Function sqlite3_stricmp CDecl Alias "sqlite3_stricmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr _
) As SQLITE_C_INT

Private Sub logBadConnection(ByVal zType As Const ZString Ptr)
    sqlite3_log(SQLITE_MISUSE, _
        StrPtr("API call with %s database connection pointer"), zType)
End Sub
Private Dim Shared sqlite3EmptyFilename16 As UShort = 0

Private Sub sqlite3ConnectionSetError(ByVal db As sqlite3 Ptr, ByVal errorCode As SQLITE_C_INT)
    If db = 0 Then Exit Sub
    db->errorCode = errorCode
    If db->pErr <> 0 Then sqlite3ValueSetNull(db->pErr)
    If errorCode = SQLITE_OK Then db->errByteOffset = -1

    ' Allocation failures are not system errors. Preserve SQLite's previous
    ' errno for those, and capture the VFS error for I/O and open failures.
    If errorCode = SQLITE_IOERR_NOMEM Then Exit Sub
    Dim primaryCode As SQLITE_C_INT = errorCode And &HFF
    If primaryCode = SQLITE_CANTOPEN OrElse primaryCode = SQLITE_IOERR Then
        db->iSysErrno = sqlite3OsGetLastError(CPtr(sqlite3_vfs Ptr, db->pVfs))
    End If
End Sub

Function sqlite3SafetyCheckOk CDecl Alias "sqlite3SafetyCheckOk" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT Export

    If db = 0 Then
        logBadConnection(StrPtr("NULL"))
        Return 0
    End If
    If db->isZombie <> 0 Then
        logBadConnection(StrPtr("invalid"))
        Return 0
    End If
    If db->isOpen <> SQLITE_CONNECTION_OPEN Then
        If sqlite3SafetyCheckSickOrOk(db) <> 0 Then _
            logBadConnection(StrPtr("unopened"))
        Return 0
    End If
    Return 1
End Function

Function sqlite3SafetyCheckSickOrOk CDecl Alias "sqlite3SafetyCheckSickOrOk" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT Export

    If db = 0 Then Return 0
    If db->isZombie = 0 AndAlso _
       (db->isOpen = SQLITE_CONNECTION_OPEN OrElse _
        db->isOpen = SQLITE_CONNECTION_FAILED) Then Return 1
    logBadConnection(StrPtr("invalid"))
    Return 0
End Function

Private Function sqlite3ConnectionClientNameEqual( _
    ByVal pClientData As SqliteDbClientData Ptr, _
    ByVal zName As Const ZString Ptr _
) As SQLITE_C_INT
    If pClientData = 0 OrElse zName = 0 Then Return 0
    Dim nameOffset As SQLITE_SIZE_T = 3 * SizeOf(Any Ptr)
    Dim zStoredName As Const UByte Ptr = _
        CPtr(Const UByte Ptr, CPtr(UByte Ptr, pClientData) + nameOffset)
    Dim zRequestedName As Const UByte Ptr = CPtr(Const UByte Ptr, zName)
    While zStoredName[0] = zRequestedName[0]
        If zStoredName[0] = 0 Then Return 1
        zStoredName += 1
        zRequestedName += 1
    Wend
    Return 0
End Function

Private Sub sqlite3ConnectionClearClientData(ByVal db As sqlite3 Ptr)
    If db = 0 Then Return
    While db->pDbData <> 0
        Dim pClientData As SqliteDbClientData Ptr = db->pDbData
        db->pDbData = pClientData->pNext
        If pClientData->xDestructor <> 0 Then
            Dim xDestructor As SqliteDbClientDataDestructor = _
                CPtr(SqliteDbClientDataDestructor, pClientData->xDestructor)
            xDestructor(pClientData->pData)
        End If
        sqlite3_free(pClientData)
    Wend
End Sub

Declare Sub sqlite3LeaveMutexAndCloseZombie CDecl Alias "sqlite3LeaveMutexAndCloseZombie" ( _
    ByVal db As sqlite3 Ptr _
)
Declare Sub sqlite3ConnectionDisconnectVtabs CDecl Alias "sqlite3ConnectionDisconnectVtabs" ( _
    ByVal db As sqlite3 Ptr _
)

Private Function sqlite3ConnectionClose( _
    ByVal db As sqlite3 Ptr, _
    ByVal allowZombie As SQLITE_C_INT _
) As SQLITE_C_INT

    If db = 0 Then Return SQLITE_OK
    If db->isOpen = 0 AndAlso db->isZombie = 0 Then Return SQLITE_MISUSE
    sqlite3DbEnter(db)

    ' Drop connection-owned virtual-table instances before checking whether
    ' statements or backups keep the handle busy.
    sqlite3ConnectionDisconnectVtabs(db)

    If db->pVdbe <> 0 Then
        If allowZombie <> 0 Then
            db->isZombie = 1
            db->eOpenState = SQLITE_STATE_ZOMBIE
            sqlite3ConnectionSetError(db, SQLITE_OK)
            sqlite3DbLeave(db)
            Return SQLITE_OK
        End If
        sqlite3ErrorWithMsg(db, SQLITE_BUSY, StrPtr( _
            "unable to close due to unfinalized statements or unfinished backups"))
        sqlite3DbLeave(db)
        Return SQLITE_BUSY
    End If

    ' A backup holds its source B-tree even when no SQL statement is active.
    For databaseIndex As SQLITE_C_INT = 0 To db->nDb - 1
        Dim pBackupBtree As Btree Ptr = CPtr(Btree Ptr, db->aDb(databaseIndex).pBt)
        If pBackupBtree <> 0 AndAlso sqlite3BtreeIsInBackup(pBackupBtree) <> 0 Then
            If allowZombie <> 0 Then
                db->isZombie = 1
                db->eOpenState = SQLITE_STATE_ZOMBIE
                sqlite3ConnectionSetError(db, SQLITE_OK)
                sqlite3DbLeave(db)
                Return SQLITE_OK
            End If
            sqlite3ErrorWithMsg(db, SQLITE_BUSY, StrPtr( _
                "unable to close due to unfinalized statements or unfinished backups"))
            sqlite3DbLeave(db)
            Return SQLITE_BUSY
        End If
    Next

    Dim hasOpenCursor As SQLITE_C_INT = 0
    For databaseIndex As SQLITE_C_INT = 0 To db->nDb - 1
        Dim pBtree As Btree Ptr = CPtr(Btree Ptr, db->aDb(databaseIndex).pBt)
        If pBtree <> 0 AndAlso pBtree->pBt <> 0 Then
            ' Shared-cache cursors from other connections do not prevent this
            ' database handle from closing.
            Dim pCursor As BtCursor Ptr = CPtr(BtCursor Ptr, pBtree->pBt->pCursor)
            While pCursor <> 0
                If pCursor->pBtree = pBtree Then
                    hasOpenCursor = 1
                    Exit For
                End If
                pCursor = pCursor->pNext
            Wend
            If hasOpenCursor <> 0 Then Exit For
        End If
    Next
    If hasOpenCursor <> 0 Then
        If allowZombie <> 0 Then
            db->isZombie = 1
            db->eOpenState = SQLITE_STATE_ZOMBIE
            sqlite3ConnectionSetError(db, SQLITE_OK)
            sqlite3DbLeave(db)
            Return SQLITE_OK
        End If
        sqlite3ErrorWithMsg(db, SQLITE_BUSY, StrPtr( _
            "unable to close due to unfinalized statements or unfinished backups"))
        sqlite3DbLeave(db)
        Return SQLITE_BUSY
    End If

#ifdef SQLITE_ENABLE_SQLLOG
    sqlite3SqllogInvoke(db, 0, 2)
#endif
    sqlite3ConnectionClearClientData(db)
    db->isZombie = 1
    db->eOpenState = SQLITE_STATE_ZOMBIE
    sqlite3LeaveMutexAndCloseZombie(db)
    Return SQLITE_OK
End Function

Sub sqlite3ConnectionFinishZombie CDecl Alias "sqlite3ConnectionFinishZombie" ( _
    ByVal db As sqlite3 Ptr _
)
    If db = 0 OrElse db->isZombie = 0 OrElse db->pVdbe <> 0 Then Return
    sqlite3ConnectionClose(db, 0)
End Sub

Function sqlite3_open_v2 CDecl Alias "sqlite3_open_v2" ( _
    ByVal zFilename As Const ZString Ptr, _
    ByVal ppDb As sqlite3 Ptr Ptr, _
    ByVal requestedFlags As SQLITE_C_INT, _
    ByVal zVfs As Const ZString Ptr _
) As SQLITE_C_INT Export
    If ppDb = 0 Then Return SQLITE_MISUSE
    ppDb[0] = 0
    Dim rc As SQLITE_C_INT = openDatabase( _
        zFilename, ppDb, CULng(requestedFlags), zVfs)
    If ppDb[0] <> 0 Then
        Dim interruptMutexResult As SQLITE_C_INT = _
            sqlite3DbInterruptMutexInitialize(ppDb[0])
        If interruptMutexResult <> SQLITE_OK Then
            Dim failedDatabase As sqlite3 Ptr = ppDb[0]
            ppDb[0] = 0
            sqlite3ConnectionClose(failedDatabase, 0)
            Return interruptMutexResult
        End If
    End If
#ifdef SQLITE_ENABLE_SQLLOG
    sqlite3SqllogInvoke(ppDb[0], zFilename, 0)
#endif
    Return rc
End Function

Function sqlite3_open CDecl Alias "sqlite3_open" ( _
    ByVal zFilename As Const ZString Ptr, _
    ByVal ppDb As sqlite3 Ptr Ptr _
) As SQLITE_C_INT Export
    Return sqlite3_open_v2(zFilename, ppDb, SQLITE_OPEN_READWRITE Or SQLITE_OPEN_CREATE, 0)
End Function

#ifndef SQLITE_OMIT_UTF16
Function sqlite3_open16 CDecl Alias "sqlite3_open16" ( _
    ByVal zFilename As Any Ptr, _
    ByVal ppDb As sqlite3 Ptr Ptr _
) As SQLITE_C_INT Export
    If ppDb = 0 Then Return SQLITE_MISUSE
    ppDb[0] = 0

    Dim rc As SQLITE_C_INT = sqlite3_initialize()
    If rc <> SQLITE_OK Then Return rc

    Dim pInput As Any Ptr = zFilename
    If pInput = 0 Then pInput = @sqlite3EmptyFilename16
    Dim zFilename8 As ZString Ptr = sqlite3Utf16to8( _
        0, pInput, -1, SQLITE_UTF16NATIVE)
    If zFilename8 = 0 Then Return SQLITE_NOMEM

    rc = sqlite3_open_v2(zFilename8, ppDb, _
        SQLITE_OPEN_READWRITE Or SQLITE_OPEN_CREATE, 0)
    If rc = SQLITE_OK AndAlso ppDb[0] <> 0 Then
        Dim db As sqlite3 Ptr = ppDb[0]
        If db->aDb(0).pSchema <> 0 AndAlso _
           (db->aDb(0).pSchema->schemaFlags And DB_SchemaLoaded) = 0 Then
            sqlite3SetTextEncoding(db, SQLITE_UTF16NATIVE)
            db->aDb(0).pSchema->enc = SQLITE_UTF16NATIVE
        End If
    End If

    sqlite3_free(zFilename8)
    Return rc And &HFF
End Function
#endif

Function sqlite3_close CDecl Alias "sqlite3_close" (ByVal db As sqlite3 Ptr) As SQLITE_C_INT Export
    Return sqlite3ConnectionClose(db, 0)
End Function

Function sqlite3_close_v2 CDecl Alias "sqlite3_close_v2" (ByVal db As sqlite3 Ptr) As SQLITE_C_INT Export
    Return sqlite3ConnectionClose(db, 1)
End Function

Function sqlite3_get_clientdata CDecl Alias "sqlite3_get_clientdata" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr _
) As Any Ptr Export
    If db = 0 OrElse zName = 0 Then Return 0
    sqlite3_mutex_enter(db->mutex)
    Dim pClientData As SqliteDbClientData Ptr = db->pDbData
    While pClientData <> 0
        If sqlite3ConnectionClientNameEqual(pClientData, zName) <> 0 Then
            Dim pResult As Any Ptr = pClientData->pData
            sqlite3_mutex_leave(db->mutex)
            Return pResult
        End If
        pClientData = pClientData->pNext
    Wend
    sqlite3_mutex_leave(db->mutex)
    Return 0
End Function

Function sqlite3_set_clientdata CDecl Alias "sqlite3_set_clientdata" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal pData As Any Ptr, _
    ByVal xDestructorArgument As Any Ptr _
) As SQLITE_C_INT Export
    If db = 0 OrElse zName = 0 Then Return SQLITE_MISUSE

    Dim xDestructor As SqliteDbClientDataDestructor = _
        CPtr(SqliteDbClientDataDestructor, xDestructorArgument)
    sqlite3_mutex_enter(db->mutex)

    Dim pPrevious As SqliteDbClientData Ptr = 0
    Dim pClientData As SqliteDbClientData Ptr = db->pDbData
    While pClientData <> 0
        If sqlite3ConnectionClientNameEqual(pClientData, zName) <> 0 Then Exit While
        pPrevious = pClientData
        pClientData = pClientData->pNext
    Wend

    If pClientData <> 0 Then
        If pClientData->xDestructor <> 0 Then
            Dim xOldDestructor As SqliteDbClientDataDestructor = _
                CPtr(SqliteDbClientDataDestructor, pClientData->xDestructor)
            xOldDestructor(pClientData->pData)
        End If
        If pData = 0 Then
            If pPrevious = 0 Then
                db->pDbData = pClientData->pNext
            Else
                pPrevious->pNext = pClientData->pNext
            End If
            sqlite3_free(pClientData)
            sqlite3_mutex_leave(db->mutex)
            Return SQLITE_OK
        End If
        pClientData->pData = pData
        pClientData->xDestructor = xDestructorArgument
        sqlite3_mutex_leave(db->mutex)
        Return SQLITE_OK
    End If

    If pData = 0 Then
        sqlite3_mutex_leave(db->mutex)
        Return SQLITE_OK
    End If

    Dim nameLength As SQLITE_SIZE_T = sqlite3ConnectionStrlen(zName)
    Dim nameOffset As SQLITE_SIZE_T = 3 * SizeOf(Any Ptr)
    Dim maxAllocation As SQLITE_SIZE_T = CULngInt(SQLITE_MAX_ALLOCATION_SIZE)
    If nameLength >= maxAllocation OrElse nameOffset >= maxAllocation - nameLength Then
        If xDestructor <> 0 Then xDestructor(pData)
        sqlite3_mutex_leave(db->mutex)
        Return SQLITE_NOMEM
    End If

    Dim allocationBytes As sqlite3_uint64 = nameOffset + nameLength + 1
    pClientData = CPtr(SqliteDbClientData Ptr, sqlite3_malloc64(allocationBytes))
    If pClientData = 0 Then
        If xDestructor <> 0 Then xDestructor(pData)
        sqlite3_mutex_leave(db->mutex)
        Return SQLITE_NOMEM
    End If
    pClientData->pNext = db->pDbData
    pClientData->pData = pData
    pClientData->xDestructor = xDestructorArgument

    Dim zDestination As UByte Ptr = _
        CPtr(UByte Ptr, pClientData) + nameOffset
    Dim zSource As Const UByte Ptr = CPtr(Const UByte Ptr, zName)
    For iByte As SQLITE_SIZE_T = 0 To nameLength
        zDestination[iByte] = zSource[iByte]
    Next
    db->pDbData = pClientData
    sqlite3_mutex_leave(db->mutex)
    Return SQLITE_OK
End Function

Function sqlite3_get_autocommit CDecl Alias "sqlite3_get_autocommit" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT Export
    If sqlite3SafetyCheckOk(db) = 0 Then Return 0
    sqlite3_mutex_enter(db->mutex)
    Dim result As SQLITE_C_INT = db->autoCommit
    sqlite3_mutex_leave(db->mutex)
    Return result
End Function

Function sqlite3_errmsg CDecl Alias "sqlite3_errmsg" (ByVal db As sqlite3 Ptr) As Const ZString Ptr Export
    If db = 0 Then Return sqlite3ErrStr(SQLITE_NOMEM)
    If sqlite3SafetyCheckSickOrOk(db) = 0 Then Return sqlite3ErrStr(SQLITE_MISUSE)
    sqlite3DbEnter(db)
    Dim zMessage As Const ZString Ptr = 0
    If db->mallocFailed <> 0 Then
        zMessage = sqlite3ErrStr(SQLITE_NOMEM)
    ElseIf db->errorCode <> SQLITE_OK AndAlso db->pErr <> 0 Then
        zMessage = CPtr(Const ZString Ptr, sqlite3ValueText(db->pErr, SQLITE_UTF8))
    End If
    If zMessage = 0 Then zMessage = sqlite3ErrStr(db->errorCode)
    sqlite3DbLeave(db)
    Return zMessage
End Function

Function sqlite3_set_errmsg CDecl Alias "sqlite3_set_errmsg" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal errorCode As SQLITE_C_INT, _
    ByVal zMessage As Const ZString Ptr _
) As SQLITE_C_INT Export
    If sqlite3SafetyCheckOk(db) = 0 Then Return SQLITE_MISUSE
    sqlite3_mutex_enter(db->mutex)
    If zMessage <> 0 Then
        sqlite3ErrorWithMsg(db, errorCode, StrPtr("%s"), zMessage)
    Else
        sqlite3Error(db, errorCode)
    End If
    Dim resultCode As SQLITE_C_INT = sqlite3ApiExit(db, SQLITE_OK)
    sqlite3_mutex_leave(db->mutex)
    Return resultCode
End Function

Function sqlite3_errcode CDecl Alias "sqlite3_errcode" (ByVal db As sqlite3 Ptr) As SQLITE_C_INT Export
    If db = 0 Then Return SQLITE_NOMEM
    If sqlite3SafetyCheckSickOrOk(db) = 0 Then Return SQLITE_MISUSE
    sqlite3_mutex_enter(db->mutex)
    Dim resultCode As SQLITE_C_INT = db->errorCode And db->errMask
    If db->mallocFailed <> 0 Then resultCode = SQLITE_NOMEM
    sqlite3_mutex_leave(db->mutex)
    Return resultCode
End Function

Function sqlite3_extended_errcode CDecl Alias "sqlite3_extended_errcode" (ByVal db As sqlite3 Ptr) As SQLITE_C_INT Export
    If db = 0 Then Return SQLITE_NOMEM
    If sqlite3SafetyCheckSickOrOk(db) = 0 Then Return SQLITE_MISUSE
    sqlite3_mutex_enter(db->mutex)
    Dim resultCode As SQLITE_C_INT = db->errorCode
    If db->mallocFailed <> 0 Then resultCode = SQLITE_NOMEM
    sqlite3_mutex_leave(db->mutex)
    Return resultCode
End Function

Function sqlite3_extended_result_codes CDecl Alias "sqlite3_extended_result_codes" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal onOff As SQLITE_C_INT _
) As SQLITE_C_INT Export
    If sqlite3SafetyCheckOk(db) = 0 Then Return SQLITE_MISUSE
    sqlite3_mutex_enter(db->mutex)
    If onOff <> 0 Then
        db->errMask = -1
    Else
        db->errMask = &HFF
    End If
    sqlite3_mutex_leave(db->mutex)
    Return SQLITE_OK
End Function

Function sqlite3_error_offset CDecl Alias "sqlite3_error_offset" (ByVal db As sqlite3 Ptr) As SQLITE_C_INT Export
    If sqlite3SafetyCheckSickOrOk(db) = 0 OrElse db->errorCode = SQLITE_OK Then Return -1
    Return db->errByteOffset
End Function

Function sqlite3_db_mutex CDecl Alias "sqlite3_db_mutex" (ByVal db As sqlite3 Ptr) As Any Ptr Export
    If db = 0 Then Return 0
    Return db->mutex
End Function

Function sqlite3TempInMemory CDecl Alias "sqlite3TempInMemory" ( _
    ByVal db As Const sqlite3 Ptr _
) As SQLITE_C_INT Export
#if SQLITE_TEMP_STORE = 1
    If db = 0 Then Return 0
    Return CInt(db->temp_store = 2)
#elseif SQLITE_TEMP_STORE = 2
    If db = 0 Then Return 1
    Return CInt(db->temp_store <> 1)
#elseif SQLITE_TEMP_STORE = 3
    Return 1
#else
    Return 0
#endif
End Function

Function sqlite3_system_errno CDecl Alias "sqlite3_system_errno" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT Export
    If db = 0 Then Return 0

    sqlite3_mutex_enter(db->mutex)
    Dim systemError As SQLITE_C_INT = db->iSysErrno
    sqlite3_mutex_leave(db->mutex)
    Return systemError
End Function

Function sqlite3_db_filename CDecl Alias "sqlite3_db_filename" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zDbName As Const ZString Ptr _
) As Const ZString Ptr Export
    If db = 0 Then Return 0
    Dim databaseIndex As SQLITE_C_INT = 0
    If zDbName <> 0 Then databaseIndex = sqlite3FindDbName(db, zDbName)
    If databaseIndex < 0 OrElse databaseIndex >= db->nDb Then Return 0
    Dim pBtree As Btree Ptr = CPtr(Btree Ptr, db->aDb(databaseIndex).pBt)
    If pBtree = 0 Then Return 0
    Return sqlite3BtreeGetFilename(pBtree)
End Function

Function sqlite3_db_readonly CDecl Alias "sqlite3_db_readonly" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zDbName As Const ZString Ptr _
) As SQLITE_C_INT Export
    If db = 0 Then Return -1
    Dim databaseIndex As SQLITE_C_INT = 0
    If zDbName <> 0 Then databaseIndex = sqlite3FindDbName(db, zDbName)
    If databaseIndex < 0 OrElse databaseIndex >= db->nDb Then Return -1
    Dim pBtree As Btree Ptr = CPtr(Btree Ptr, db->aDb(databaseIndex).pBt)
    If pBtree = 0 Then Return -1
    Return sqlite3BtreeIsReadonly(pBtree)
End Function

Function sqlite3_db_name CDecl Alias "sqlite3_db_name" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal index As SQLITE_C_INT _
) As Const ZString Ptr Export
    If db = 0 OrElse index < 0 OrElse index >= db->nDb Then Return 0
    Return db->aDb(index).zDbSName
End Function

Function sqlite3_txn_state CDecl Alias "sqlite3_txn_state" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zSchema As Const ZString Ptr _
) As SQLITE_C_INT Export
    If sqlite3SafetyCheckOk(db) = 0 Then Return -1

    sqlite3DbEnter(db)
    Dim transactionState As SQLITE_C_INT = -1
    Dim databaseIndex As SQLITE_C_INT = 0
    If zSchema <> 0 Then databaseIndex = sqlite3FindDbName(db, zSchema)
    If databaseIndex >= 0 AndAlso databaseIndex < db->nDb Then
        Dim pBtree As Btree Ptr = _
            CPtr(Btree Ptr, db->aDb(databaseIndex).pBt)
        If pBtree = 0 Then
            transactionState = SQLITE_TXN_NONE
        Else
            transactionState = sqlite3BtreeTxnState(pBtree)
        End If
    End If
    sqlite3DbLeave(db)
    Return transactionState
End Function

Function sqlite3_db_release_memory CDecl Alias "sqlite3_db_release_memory" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT Export
    If sqlite3SafetyCheckOk(db) = 0 Then Return SQLITE_MISUSE

    sqlite3DbEnter(db)
    Dim pBtree As Btree Ptr = CPtr(Btree Ptr, db->pMainBtree)
    If pBtree <> 0 AndAlso pBtree->pBt <> 0 Then
        Dim pBt As BtShared Ptr = pBtree->pBt
        sqlite3_mutex_enter(pBt->mutex)
        If pBt->pPager <> 0 Then sqlite3PagerShrink(pBt->pPager)
        sqlite3_mutex_leave(pBt->mutex)
    End If
    sqlite3DbLeave(db)
    Return SQLITE_OK
End Function

Function sqlite3_db_cacheflush CDecl Alias "sqlite3_db_cacheflush" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT Export
    If sqlite3SafetyCheckOk(db) = 0 Then Return SQLITE_MISUSE

    sqlite3DbEnter(db)
    Dim rc As SQLITE_C_INT = SQLITE_OK
    Dim pBtree As Btree Ptr = CPtr(Btree Ptr, db->pMainBtree)
    If pBtree <> 0 AndAlso pBtree->pBt <> 0 AndAlso pBtree->inTrans = TRANS_WRITE Then
        Dim pBt As BtShared Ptr = pBtree->pBt
        sqlite3_mutex_enter(pBt->mutex)
        If pBt->pPager = 0 Then
            rc = SQLITE_MISUSE
        Else
            rc = sqlite3PagerFlush(pBt->pPager)
        End If
        sqlite3_mutex_leave(pBt->mutex)
    End If
    sqlite3DbLeave(db)
    Return rc
End Function

Function sqlite3_setlk_timeout CDecl Alias "sqlite3_setlk_timeout" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal milliseconds As SQLITE_C_INT, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT Export
#ifdef SQLITE_ENABLE_API_ARMOR
    If sqlite3SafetyCheckOk(db) = 0 Then Return SQLITE_MISUSE
#endif
    If milliseconds < -1 Then Return SQLITE_RANGE
#ifdef SQLITE_ENABLE_SETLK_TIMEOUT
    If db = 0 Then Return SQLITE_MISUSE
    sqlite3_mutex_enter(db->mutex)
    db->setlkTimeout = milliseconds
    db->setlkFlags = flags
    ' Update already-open pagers before the connection releases its mutex.
    Dim blockOnConnect As SQLITE_C_INT = _
        IIf((flags And SQLITE_SETLK_BLOCK_ON_CONNECT) <> 0, 1, 0)
    sqlite3BtreeEnterAll(db)
    For databaseIndex As SQLITE_C_INT = 0 To db->nDb - 1
        Dim pBtree As Btree Ptr = CPtr(Btree Ptr, db->aDb(databaseIndex).pBt)
        If pBtree <> 0 Then
            Dim pPager As Pager Ptr = sqlite3BtreePager(pBtree)
            Dim pFile As sqlite3_file Ptr = sqlite3PagerFile(pPager)
            If pFile <> 0 Then _
                sqlite3OsFileControlHint(pFile, SQLITE_FCNTL_BLOCK_ON_CONNECT, @blockOnConnect)
        End If
    Next
    sqlite3BtreeLeaveAll(db)
    sqlite3_mutex_leave(db->mutex)
#endif
    Return SQLITE_OK
End Function

/' end of sqlite3_connection.bas '/
