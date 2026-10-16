/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_db_config.bas

    Purpose:

        Apply per-connection configuration options through SQLite's variadic
        sqlite3_db_config() API.

    Responsibilities:

        - Lock the connection while reading or changing its configuration.
        - Read option-specific values using FreeBASIC's C varargs interface.
        - Update database flags and expire prepared statements when required.

    This file intentionally does NOT contain:

        - Process-wide sqlite3_config() settings.
        - Connection allocation or destruction.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_mutex.bi"

Declare Function setupLookaside CDecl Alias "setupLookaside" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pBuffer As Any Ptr, _
    ByVal slotSize As SQLITE_C_INT, _
    ByVal slotCount As SQLITE_C_INT _
) As SQLITE_C_INT

Declare Sub sqlite3ExpirePreparedStatements CDecl Alias "sqlite3ExpirePreparedStatements" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal resetSchema As SQLITE_C_INT _
)

#if defined(SQLITE_ENABLE_API_ARMOR)
Declare Function sqlite3SafetyCheckOk CDecl Alias "sqlite3SafetyCheckOk" ( _
    ByVal db As sqlite3 Ptr _
) As SQLITE_C_INT
Declare Function sqlite3MisuseError CDecl Alias "sqlite3MisuseError" ( _
    ByVal sourceLine As SQLITE_C_INT _
) As SQLITE_C_INT
#endif

Private Type SqliteDbConfigFlagOperation
    op As SQLITE_C_INT
    mask As sqlite3_uint64
End Type

' The option-to-flag table is immutable after module initialization. Keep the
' order from src/main.c because the search exits after the first match.
Private Dim Shared sqlite3DbConfigFlagOperations(0 To 20) As _
    SqliteDbConfigFlagOperation = { _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_ENABLE_FKEY, SQLITE_ForeignKeys), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_ENABLE_TRIGGER, SQLITE_EnableTrigger), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_ENABLE_VIEW, SQLITE_EnableView), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_ENABLE_FTS3_TOKENIZER, SQLITE_Fts3Tokenizer), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION, SQLITE_LoadExtension), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_NO_CKPT_ON_CLOSE, SQLITE_NoCkptOnClose), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_ENABLE_QPSG, SQLITE_EnableQPSG), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_TRIGGER_EQP, SQLITE_TriggerEQP), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_RESET_DATABASE, SQLITE_ResetDatabase), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_DEFENSIVE, SQLITE_Defensive), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_WRITABLE_SCHEMA, _
                                      SQLITE_WriteSchema Or SQLITE_NoSchemaError), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_LEGACY_ALTER_TABLE, SQLITE_LegacyAlter), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_DQS_DDL, SQLITE_DqsDDL), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_DQS_DML, SQLITE_DqsDML), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_LEGACY_FILE_FORMAT, SQLITE_LegacyFileFmt), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_TRUSTED_SCHEMA, SQLITE_TrustedSchema), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_STMT_SCANSTATUS, SQLITE_StmtScanStatus), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_REVERSE_SCANORDER, SQLITE_ReverseOrder), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_ENABLE_ATTACH_CREATE, SQLITE_AttachCreate), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_ENABLE_ATTACH_WRITE, SQLITE_AttachWrite), _
    Type<SqliteDbConfigFlagOperation>(SQLITE_DBCONFIG_ENABLE_COMMENTS, SQLITE_Comments) _
}

Function sqlite3_db_config CDecl Alias "sqlite3_db_config" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal op As SQLITE_C_INT, _
    ... _
) As SQLITE_C_INT Export
#if defined(SQLITE_ENABLE_API_ARMOR)
    If sqlite3SafetyCheckOk(db) = 0 Then Return sqlite3MisuseError(972)
#endif

    sqlite3_mutex_enter(db->mutex)

    Dim args As Cva_List
    Cva_Start(args, op)
    Dim rc As SQLITE_C_INT = SQLITE_OK

    Select Case op
    Case SQLITE_DBCONFIG_MAINDBNAME
        db->aDb(0).zDbSName = Cva_Arg(args, Const ZString Ptr)

    Case SQLITE_DBCONFIG_LOOKASIDE
        Dim pBuffer As Any Ptr = Cva_Arg(args, Any Ptr)
        Dim slotSize As SQLITE_C_INT = Cva_Arg(args, SQLITE_C_INT)
        Dim slotCount As SQLITE_C_INT = Cva_Arg(args, SQLITE_C_INT)
        rc = setupLookaside(db, pBuffer, slotSize, slotCount)

    Case SQLITE_DBCONFIG_FP_DIGITS
        Dim requestedDigits As SQLITE_C_INT = Cva_Arg(args, SQLITE_C_INT)
        Dim pActualDigits As SQLITE_C_INT Ptr = Cva_Arg(args, SQLITE_C_INT Ptr)
        If requestedDigits > 3 AndAlso requestedDigits < 24 Then _
            db->nFpDigit = CByte(requestedDigits)
        If pActualDigits <> 0 Then pActualDigits[0] = db->nFpDigit

    Case Else
        rc = SQLITE_ERROR
        For flagIndex As SQLITE_C_INT = 0 To UBound(sqlite3DbConfigFlagOperations)
            Dim flagOperation As SqliteDbConfigFlagOperation Ptr = _
                @sqlite3DbConfigFlagOperations(flagIndex)
            If flagOperation->op <> op Then Continue For

            Dim onOff As SQLITE_C_INT = Cva_Arg(args, SQLITE_C_INT)
            Dim pResult As SQLITE_C_INT Ptr = Cva_Arg(args, SQLITE_C_INT Ptr)
            Dim oldFlags As sqlite3_uint64 = db->flags

            If onOff > 0 Then
                db->flags = db->flags Or flagOperation->mask
            ElseIf onOff = 0 Then
                db->flags = db->flags And Not flagOperation->mask
            End If

            If oldFlags <> db->flags Then sqlite3ExpirePreparedStatements(db, 0)
            If pResult <> 0 Then _
                pResult[0] = CInt((db->flags And flagOperation->mask) <> 0)

            rc = SQLITE_OK
            Exit For
        Next
    End Select

    Cva_End(args)
    sqlite3_mutex_leave(db->mutex)
    Return rc
End Function

/' end of sqlite3_db_config.bas '/
