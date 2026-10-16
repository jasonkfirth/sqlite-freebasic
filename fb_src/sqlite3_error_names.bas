/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_error_names.bas

    Purpose:

        Return the symbolic name of a primary or extended SQLite result code.

    Responsibilities:

        - Match exact extended codes before falling back to their primary code.
        - Format unknown codes into process-lifetime shared storage.

    This file intentionally does NOT contain:

        - Error messages, localization, or per-connection error state.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"

Declare Function sqlite3_snprintf CDecl Alias "sqlite3_snprintf" ( _
    ByVal bufferSize As SQLITE_C_INT, _
    ByVal zBuffer As ZString Ptr, _
    ByVal zFormat As Const ZString Ptr, _
    ... _
) As ZString Ptr

Private Dim Shared sqlite3UnknownErrorNameBuffer As ZString * 50

Private Function sqlite3ErrorNameForCode( _
    ByVal resultCode As SQLITE_C_INT _
) As Const ZString Ptr
    Select Case resultCode
    Case SQLITE_OK: Return StrPtr("SQLITE_OK")
    Case SQLITE_ERROR: Return StrPtr("SQLITE_ERROR")
    Case SQLITE_ERROR_SNAPSHOT: Return StrPtr("SQLITE_ERROR_SNAPSHOT")
    Case SQLITE_ERROR_RETRY: Return StrPtr("SQLITE_ERROR_RETRY")
    Case SQLITE_ERROR_MISSING_COLLSEQ: Return StrPtr("SQLITE_ERROR_MISSING_COLLSEQ")
    Case SQLITE_INTERNAL: Return StrPtr("SQLITE_INTERNAL")
    Case SQLITE_PERM: Return StrPtr("SQLITE_PERM")
    Case SQLITE_ABORT: Return StrPtr("SQLITE_ABORT")
    Case SQLITE_ABORT_ROLLBACK: Return StrPtr("SQLITE_ABORT_ROLLBACK")
    Case SQLITE_BUSY: Return StrPtr("SQLITE_BUSY")
    Case SQLITE_BUSY_RECOVERY: Return StrPtr("SQLITE_BUSY_RECOVERY")
    Case SQLITE_BUSY_SNAPSHOT: Return StrPtr("SQLITE_BUSY_SNAPSHOT")
    Case SQLITE_LOCKED: Return StrPtr("SQLITE_LOCKED")
    Case SQLITE_LOCKED_SHAREDCACHE: Return StrPtr("SQLITE_LOCKED_SHAREDCACHE")
    Case SQLITE_NOMEM: Return StrPtr("SQLITE_NOMEM")
    Case SQLITE_READONLY: Return StrPtr("SQLITE_READONLY")
    Case SQLITE_READONLY_RECOVERY: Return StrPtr("SQLITE_READONLY_RECOVERY")
    Case SQLITE_READONLY_CANTINIT: Return StrPtr("SQLITE_READONLY_CANTINIT")
    Case SQLITE_READONLY_ROLLBACK: Return StrPtr("SQLITE_READONLY_ROLLBACK")
    Case SQLITE_READONLY_DBMOVED: Return StrPtr("SQLITE_READONLY_DBMOVED")
    Case SQLITE_READONLY_DIRECTORY: Return StrPtr("SQLITE_READONLY_DIRECTORY")
    Case SQLITE_INTERRUPT: Return StrPtr("SQLITE_INTERRUPT")
    Case SQLITE_IOERR: Return StrPtr("SQLITE_IOERR")
    Case SQLITE_IOERR_READ: Return StrPtr("SQLITE_IOERR_READ")
    Case SQLITE_IOERR_SHORT_READ: Return StrPtr("SQLITE_IOERR_SHORT_READ")
    Case SQLITE_IOERR_WRITE: Return StrPtr("SQLITE_IOERR_WRITE")
    Case SQLITE_IOERR_FSYNC: Return StrPtr("SQLITE_IOERR_FSYNC")
    Case SQLITE_IOERR_DIR_FSYNC: Return StrPtr("SQLITE_IOERR_DIR_FSYNC")
    Case SQLITE_IOERR_TRUNCATE: Return StrPtr("SQLITE_IOERR_TRUNCATE")
    Case SQLITE_IOERR_FSTAT: Return StrPtr("SQLITE_IOERR_FSTAT")
    Case SQLITE_IOERR_UNLOCK: Return StrPtr("SQLITE_IOERR_UNLOCK")
    Case SQLITE_IOERR_RDLOCK: Return StrPtr("SQLITE_IOERR_RDLOCK")
    Case SQLITE_IOERR_DELETE: Return StrPtr("SQLITE_IOERR_DELETE")
    Case SQLITE_IOERR_NOMEM: Return StrPtr("SQLITE_IOERR_NOMEM")
    Case SQLITE_IOERR_ACCESS: Return StrPtr("SQLITE_IOERR_ACCESS")
    Case SQLITE_IOERR_CHECKRESERVEDLOCK: Return StrPtr("SQLITE_IOERR_CHECKRESERVEDLOCK")
    Case SQLITE_IOERR_LOCK: Return StrPtr("SQLITE_IOERR_LOCK")
    Case SQLITE_IOERR_CLOSE: Return StrPtr("SQLITE_IOERR_CLOSE")
    Case SQLITE_IOERR_DIR_CLOSE: Return StrPtr("SQLITE_IOERR_DIR_CLOSE")
    Case SQLITE_IOERR_SHMOPEN: Return StrPtr("SQLITE_IOERR_SHMOPEN")
    Case SQLITE_IOERR_SHMSIZE: Return StrPtr("SQLITE_IOERR_SHMSIZE")
    Case SQLITE_IOERR_SHMLOCK: Return StrPtr("SQLITE_IOERR_SHMLOCK")
    Case SQLITE_IOERR_SHMMAP: Return StrPtr("SQLITE_IOERR_SHMMAP")
    Case SQLITE_IOERR_SEEK: Return StrPtr("SQLITE_IOERR_SEEK")
    Case SQLITE_IOERR_DELETE_NOENT: Return StrPtr("SQLITE_IOERR_DELETE_NOENT")
    Case SQLITE_IOERR_MMAP: Return StrPtr("SQLITE_IOERR_MMAP")
    Case SQLITE_IOERR_GETTEMPPATH: Return StrPtr("SQLITE_IOERR_GETTEMPPATH")
    Case SQLITE_IOERR_CONVPATH: Return StrPtr("SQLITE_IOERR_CONVPATH")
    Case SQLITE_CORRUPT: Return StrPtr("SQLITE_CORRUPT")
    Case SQLITE_CORRUPT_VTAB: Return StrPtr("SQLITE_CORRUPT_VTAB")
    Case SQLITE_NOTFOUND: Return StrPtr("SQLITE_NOTFOUND")
    Case SQLITE_FULL: Return StrPtr("SQLITE_FULL")
    Case SQLITE_CANTOPEN: Return StrPtr("SQLITE_CANTOPEN")
    Case SQLITE_CANTOPEN_NOTEMPDIR: Return StrPtr("SQLITE_CANTOPEN_NOTEMPDIR")
    Case SQLITE_CANTOPEN_ISDIR: Return StrPtr("SQLITE_CANTOPEN_ISDIR")
    Case SQLITE_CANTOPEN_FULLPATH: Return StrPtr("SQLITE_CANTOPEN_FULLPATH")
    Case SQLITE_CANTOPEN_CONVPATH: Return StrPtr("SQLITE_CANTOPEN_CONVPATH")
    Case SQLITE_CANTOPEN_SYMLINK: Return StrPtr("SQLITE_CANTOPEN_SYMLINK")
    Case SQLITE_PROTOCOL: Return StrPtr("SQLITE_PROTOCOL")
    Case SQLITE_EMPTY: Return StrPtr("SQLITE_EMPTY")
    Case SQLITE_SCHEMA: Return StrPtr("SQLITE_SCHEMA")
    Case SQLITE_TOOBIG: Return StrPtr("SQLITE_TOOBIG")
    Case SQLITE_CONSTRAINT: Return StrPtr("SQLITE_CONSTRAINT")
    Case SQLITE_CONSTRAINT_UNIQUE: Return StrPtr("SQLITE_CONSTRAINT_UNIQUE")
    Case SQLITE_CONSTRAINT_TRIGGER: Return StrPtr("SQLITE_CONSTRAINT_TRIGGER")
    Case SQLITE_CONSTRAINT_FOREIGNKEY: Return StrPtr("SQLITE_CONSTRAINT_FOREIGNKEY")
    Case SQLITE_CONSTRAINT_CHECK: Return StrPtr("SQLITE_CONSTRAINT_CHECK")
    Case SQLITE_CONSTRAINT_PRIMARYKEY: Return StrPtr("SQLITE_CONSTRAINT_PRIMARYKEY")
    Case SQLITE_CONSTRAINT_NOTNULL: Return StrPtr("SQLITE_CONSTRAINT_NOTNULL")
    Case SQLITE_CONSTRAINT_COMMITHOOK: Return StrPtr("SQLITE_CONSTRAINT_COMMITHOOK")
    Case SQLITE_CONSTRAINT_VTAB: Return StrPtr("SQLITE_CONSTRAINT_VTAB")
    Case SQLITE_CONSTRAINT_FUNCTION: Return StrPtr("SQLITE_CONSTRAINT_FUNCTION")
    Case SQLITE_CONSTRAINT_ROWID: Return StrPtr("SQLITE_CONSTRAINT_ROWID")
    Case SQLITE_MISMATCH: Return StrPtr("SQLITE_MISMATCH")
    Case SQLITE_MISUSE: Return StrPtr("SQLITE_MISUSE")
    Case SQLITE_NOLFS: Return StrPtr("SQLITE_NOLFS")
    Case SQLITE_AUTH: Return StrPtr("SQLITE_AUTH")
    Case SQLITE_FORMAT: Return StrPtr("SQLITE_FORMAT")
    Case SQLITE_RANGE: Return StrPtr("SQLITE_RANGE")
    Case SQLITE_NOTADB: Return StrPtr("SQLITE_NOTADB")
    Case SQLITE_ROW: Return StrPtr("SQLITE_ROW")
    Case SQLITE_NOTICE: Return StrPtr("SQLITE_NOTICE")
    Case SQLITE_NOTICE_RECOVER_WAL: Return StrPtr("SQLITE_NOTICE_RECOVER_WAL")
    Case SQLITE_NOTICE_RECOVER_ROLLBACK: Return StrPtr("SQLITE_NOTICE_RECOVER_ROLLBACK")
    Case SQLITE_NOTICE_RBU: Return StrPtr("SQLITE_NOTICE_RBU")
    Case SQLITE_WARNING: Return StrPtr("SQLITE_WARNING")
    Case SQLITE_WARNING_AUTOINDEX: Return StrPtr("SQLITE_WARNING_AUTOINDEX")
    Case SQLITE_DONE: Return StrPtr("SQLITE_DONE")
    End Select
    Return 0
End Function

Function sqlite3ErrName CDecl Alias "sqlite3ErrName" ( _
    ByVal resultCode As SQLITE_C_INT _
) As Const ZString Ptr Export
    Dim originalCode As SQLITE_C_INT = resultCode
    For passIndex As SQLITE_C_INT = 0 To 1
        Dim zName As Const ZString Ptr = sqlite3ErrorNameForCode(resultCode)
        If zName <> 0 Then Return zName
        resultCode = resultCode And &HFF
    Next

    sqlite3_snprintf(SizeOf(sqlite3UnknownErrorNameBuffer), _
                     @sqlite3UnknownErrorNameBuffer, _
                     StrPtr("SQLITE_UNKNOWN(%d)"), originalCode)
    Return @sqlite3UnknownErrorNameBuffer
End Function

/' end of sqlite3_error_names.bas '/
