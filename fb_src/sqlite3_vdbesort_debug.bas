/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbesort_debug.bas

    Purpose:

        Report sorter worker activity when SQLite debug tracing is enabled.

    Responsibilities:

        - Format timestamped worker, rewind, populate, and blocking events.
        - Keep debug output behind SQLITE_DEBUG_SORTER_THREADS.

    This file intentionally does NOT contain:

        - Sorter scheduling or data movement.
        - Output in the default build, where SQLite compiles these calls away.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_vfs.bi"
#include once "sqlite3_vdbesort_types.bi"

#if defined(SQLITE_DEBUG_SORTER_THREADS)
Extern "C"
    Extern stderr Alias "stderr" As Any Ptr
    Declare Function sqlite3SorterDebugFprintf CDecl Alias "fprintf" ( _
        ByVal stream As Any Ptr, _
        ByVal formatString As Const ZString Ptr, _
        ... _
    ) As SQLITE_C_INT
End Extern
#endif

Private Sub sqlite3SorterDebugPrintTask ( _
    ByVal timestamp As sqlite3_int64, _
    ByVal taskPrefix As Const ZString Ptr, _
    ByVal taskIndex As SQLITE_C_INT, _
    ByVal eventName As Const ZString Ptr _
)
#if defined(SQLITE_DEBUG_SORTER_THREADS)
    If taskPrefix = 0 OrElse taskPrefix[0] = 0 Then
        sqlite3SorterDebugFprintf(stderr, StrPtr(!"%lld:%d %s\n"), _
            timestamp, taskIndex, eventName)
    Else
        sqlite3SorterDebugFprintf(stderr, StrPtr(!"%lld:%s%d %s\n"), _
            timestamp, taskPrefix, taskIndex, eventName)
    End If
#else
    ' The upstream C definitions are preprocessor no-op macros in this profile.
#endif
End Sub

Private Function sqlite3SorterDebugTaskIndex ( _
    ByVal pTask As SqliteSortSubtaskPrefix Ptr _
) As SQLITE_C_INT
    If pTask = 0 OrElse pTask->pSorter = 0 Then Return 0
    Dim pSorter As SqliteVdbeSorterPrefix Ptr = _
        CPtr(SqliteVdbeSorterPrefix Ptr, pTask->pSorter)
    Dim taskAddress As sqlite3_uint64 = Cast(sqlite3_uint64, pTask)
    Dim firstTaskAddress As sqlite3_uint64 = _
        Cast(sqlite3_uint64, @pSorter->aTask(0))
    If taskAddress < firstTaskAddress Then Return 0
    Return Cast(SQLITE_C_INT, _
        (taskAddress - firstTaskAddress) \ SizeOf(SqliteSortSubtaskPrefix))
End Function

Private Sub vdbeSorterWorkDebug CDecl Alias "vdbeSorterWorkDebug" ( _
    ByVal pTask As SqliteSortSubtaskPrefix Ptr, _
    ByVal eventName As Const ZString Ptr _
)
#if defined(SQLITE_DEBUG_SORTER_THREADS)
    If pTask = 0 OrElse pTask->pSorter = 0 Then Exit Sub
    Dim pSorter As SqliteVdbeSorterPrefix Ptr = _
        CPtr(SqliteVdbeSorterPrefix Ptr, pTask->pSorter)
    Dim timestamp As sqlite3_int64 = 0
    sqlite3OsCurrentTimeInt64(CPtr(sqlite3_vfs Ptr, pSorter->db->pVfs), _
                              @timestamp)
    sqlite3SorterDebugPrintTask(timestamp, 0, _
        sqlite3SorterDebugTaskIndex(pTask), eventName)
#else
#endif
End Sub

Private Sub vdbeSorterRewindDebug CDecl Alias "vdbeSorterRewindDebug" ( _
    ByVal eventName As Const ZString Ptr _
)
#if defined(SQLITE_DEBUG_SORTER_THREADS)
    Dim timestamp As sqlite3_int64 = 0
    Dim pVfs As sqlite3_vfs Ptr = sqlite3_vfs_find(0)
    If pVfs Then sqlite3OsCurrentTimeInt64(pVfs, @timestamp)
    sqlite3SorterDebugFprintf(stderr, StrPtr(!"%lld:X %s\n"), _
        timestamp, eventName)
#else
#endif
End Sub

Private Sub vdbeSorterPopulateDebug CDecl Alias "vdbeSorterPopulateDebug" ( _
    ByVal pTask As SqliteSortSubtaskPrefix Ptr, _
    ByVal eventName As Const ZString Ptr _
)
#if defined(SQLITE_DEBUG_SORTER_THREADS)
    If pTask = 0 OrElse pTask->pSorter = 0 Then Exit Sub
    Dim pSorter As SqliteVdbeSorterPrefix Ptr = _
        CPtr(SqliteVdbeSorterPrefix Ptr, pTask->pSorter)
    Dim timestamp As sqlite3_int64 = 0
    sqlite3OsCurrentTimeInt64(CPtr(sqlite3_vfs Ptr, pSorter->db->pVfs), _
                              @timestamp)
    sqlite3SorterDebugPrintTask(timestamp, StrPtr(!"bg"), _
        sqlite3SorterDebugTaskIndex(pTask), eventName)
#else
#endif
End Sub

Private Sub vdbeSorterBlockDebug CDecl Alias "vdbeSorterBlockDebug" ( _
    ByVal pTask As SqliteSortSubtaskPrefix Ptr, _
    ByVal blocked As SQLITE_C_INT, _
    ByVal eventName As Const ZString Ptr _
)
#if defined(SQLITE_DEBUG_SORTER_THREADS)
    If blocked = 0 OrElse pTask = 0 OrElse pTask->pSorter = 0 Then Exit Sub
    Dim pSorter As SqliteVdbeSorterPrefix Ptr = _
        CPtr(SqliteVdbeSorterPrefix Ptr, pTask->pSorter)
    Dim timestamp As sqlite3_int64 = 0
    sqlite3OsCurrentTimeInt64(CPtr(sqlite3_vfs Ptr, pSorter->db->pVfs), _
                              @timestamp)
    sqlite3SorterDebugFprintf(stderr, StrPtr(!"%lld:main %s\n"), _
        timestamp, eventName)
#else
#endif
End Sub

/' end of sqlite3_vdbesort_debug.bas '/
