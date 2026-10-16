/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_bulk50_os_unix.bas

    Purpose:

        Preserve three portable Unix VFS helpers from src/os_unix.c that
        compile through the C2FB translation path.

    Responsibilities:

        - Route the POSIX VFS open callback to the FreeBASIC system-call alias.
        - Report Unix VFS errors through SQLite's centralized log callback.
        - Select and perform the platform sync operation for a file descriptor.

    This file intentionally does NOT contain:

        - UnixFile or inode state and locking logic.
        - Platform VFS table construction or registration.
'/

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"

Declare Sub sqlite3_log CDecl Alias "sqlite3_log" (ByVal arg0 As SQLITE_C_INT, ByVal arg1 As Const ZString Ptr, ...)

Declare Function unixOpen CDecl Alias "open" ( ByVal zPath As Const ZString Ptr, ByVal flags As SQLITE_C_INT, ByVal mode As SQLITE_C_UINT ) As SQLITE_C_INT

Declare Function unixFsync CDecl Alias "fsync" (ByVal fd As SQLITE_C_INT) As SQLITE_C_INT

Declare Function unixErrnoLocation CDecl Alias "__errno_location" () As SQLITE_C_INT Ptr

Declare Function posixOpen CDecl Alias "posixOpen" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT

Declare Function unixLogErrorAtLine CDecl Alias "unixLogErrorAtLine" (ByVal arg0 As SQLITE_C_INT, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT

Declare Function full_fsync CDecl Alias "full_fsync" (ByVal arg0 As SQLITE_C_INT, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT

Private Function posixOpen CDecl Alias "posixOpen" (ByVal arg0 As Const ZString Ptr, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
    Return unixOpen(arg0, arg1, arg2)
End Function

Private Function unixLogErrorAtLine CDecl Alias "unixLogErrorAtLine" (ByVal arg0 As SQLITE_C_INT, ByVal arg1 As Const ZString Ptr, ByVal arg2 As Const ZString Ptr, ByVal arg3 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As ZString Ptr
    Dim local1 As SQLITE_C_INT
    Dim c2fb_temp_0 As ZString Ptr
    Dim c2fb_temp_1 As Const ZString Ptr

    ' C automatic storage declaration
    local1 = ((*CPtr(SQLITE_C_INT Ptr, unixErrnoLocation())))
    c2fb_temp_0 = CPtr(ZString Ptr, StrPtr(!""))
    local0 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, ((arg2 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        c2fb_temp_1 = StrPtr(!"")
        arg2 = c2fb_temp_1
    End If
    sqlite3_log(arg0, StrPtr(!"os_unix.c:%d: (%d) %s(%s) - %s"), arg3, local1, arg1, arg2, local0)
    Return arg0
End Function

Private Function full_fsync CDecl Alias "full_fsync" (ByVal arg0 As SQLITE_C_INT, ByVal arg1 As SQLITE_C_INT, ByVal arg2 As SQLITE_C_INT) As SQLITE_C_INT
    Dim local0 As SQLITE_C_INT
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As SQLITE_C_INT

    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_INT, unixFsync(arg0))
    local0 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, &O0ULL) AndAlso (-Cast(SQLITE_C_INT, ((local0 <> Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL))))))))))) Then
        c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        local0 = c2fb_temp_1
    End If
    Return local0
End Function

/' end of sqlite3_bulk50_os_unix.bas '/
