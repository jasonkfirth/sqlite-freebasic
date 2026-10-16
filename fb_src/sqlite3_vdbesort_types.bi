/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbesort_types.bi

    Purpose:

        Describe the fixed sorter records and VdbeSorter flexible-tail layout.

    Responsibilities:

        - Map the PMA reader, writer, merge, task, and sorter records.
        - Keep the one-element tail placeholder needed for VdbeSorter offsets.
        - Share sorter layouts between repair code and C2FB candidates.

    This file intentionally does NOT contain:

        - Sort scheduling, PMA I/O, merge logic, or cursor traversal.
        - Runtime validation of C and FreeBASIC record offsets.
'/ 

#ifndef SQLITE3_FB_VDBESORT_TYPES_BI
#define SQLITE3_FB_VDBESORT_TYPES_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_vdbe_record.bi"
#include once "sqlite3_vdbe_compare.bi"

Declare Sub vdbeMergeEngineFree CDecl Alias "vdbeMergeEngineFree" ( _
    ByVal pMerger As Any Ptr _
)

Type SqliteSorterFilePrefix
    pFd As Any Ptr
    iEof As sqlite3_int64
End Type

Type SqliteSorterListPrefix
    pList As Any Ptr
    aMemory As UByte Ptr
    szPMA As sqlite3_int64
End Type

Union SqliteSorterRecordUnion
    pNext As Any Ptr
    iNext As SQLITE_C_INT
End Union

Type SqliteSorterRecordPrefix
    nVal As SQLITE_C_INT
    u As SqliteSorterRecordUnion
End Type

Type SqlitePmaReaderPrefix
    iReadOff As sqlite3_int64
    iEof As sqlite3_int64
    nAlloc As SQLITE_C_INT
    nKey As SQLITE_C_INT
    pFd As Any Ptr
    aAlloc As UByte Ptr
    aKey As UByte Ptr
    aBuffer As UByte Ptr
    nBuffer As SQLITE_C_INT
    aMap As UByte Ptr
    pIncr As Any Ptr
End Type

Type SqliteMergeEnginePrefix
    nTree As SQLITE_C_INT
    pTask As Any Ptr
    aTree As SQLITE_C_INT Ptr
    aReadr As SqlitePmaReaderPrefix Ptr
End Type

Type SqliteIncrMergerPrefix
    pTask As Any Ptr
    pMerger As SqliteMergeEnginePrefix Ptr
    iStartOff As sqlite3_int64
    mxSz As SQLITE_C_INT
    bEof As SQLITE_C_INT
    bUseThread As SQLITE_C_INT
    aFile(0 To 1) As SqliteSorterFilePrefix
End Type

Type SqliteSortSubtaskPrefix
    pThread As Any Ptr
    bDone As SQLITE_C_INT
    nPMA As SQLITE_C_INT
    pSorter As Any Ptr
    pUnpacked As sqlite3VdbeUnpackedRecord Ptr
    list As SqliteSorterListPrefix
    xCompare As Any Ptr
    file As SqliteSorterFilePrefix
    file2 As SqliteSorterFilePrefix
    nSpill As sqlite3_uint64
End Type

' The C record ends in a flexible array. FreeBASIC uses one placeholder task;
' C2FB subtracts that element when it translates offsetof(VdbeSorter, aTask).
Type SqliteVdbeSorterPrefix
    mnPmaSize As SQLITE_C_INT
    mxPmaSize As SQLITE_C_INT
    mxKeysize As SQLITE_C_INT
    pgsz As SQLITE_C_INT
    pReader As Any Ptr
    pMerger As Any Ptr
    db As sqlite3 Ptr
    pKeyInfo As sqlite3VdbeKeyInfoPrefix Ptr
    pUnpacked As sqlite3VdbeUnpackedRecord Ptr
    list As SqliteSorterListPrefix
    iMemory As SQLITE_C_INT
    nMemory As SQLITE_C_INT
    bUsePMA As u8
    bUseThreads As u8
    iPrev As u8
    nTask As u8
    typeMask As u8
    aTask(0 To 0) As SqliteSortSubtaskPrefix
End Type

Type SqlitePmaWriter
    eFWErr As SQLITE_C_INT
    aBuffer As UByte Ptr
    nBuffer As SQLITE_C_INT
    iBufStart As SQLITE_C_INT
    iBufEnd As SQLITE_C_INT
    iWriteOff As sqlite3_int64
    pFd As Any Ptr
    nPmaSpill As sqlite3_uint64
End Type

Declare Function vdbeIncrMergerNew CDecl Alias "vdbeIncrMergerNew" ( _
    ByVal pTask As SqliteSortSubtaskPrefix Ptr, _
    ByVal pMerger As SqliteMergeEnginePrefix Ptr, _
    ByVal ppOut As SqliteIncrMergerPrefix Ptr Ptr _
) As SQLITE_C_INT

Declare Function sqlite3ConfigCoreMutexEnabled CDecl Alias "sqlite3ConfigCoreMutexEnabled" () As SQLITE_C_INT
Declare Function sqlite3ConfigSmallMallocEnabled CDecl Alias "sqlite3ConfigSmallMallocEnabled" () As SQLITE_C_INT
Declare Function sqlite3ConfigPmaSizeValue CDecl Alias "sqlite3ConfigPmaSizeValue" () As SQLITE_C_UINT

Const SQLITE_VDBESORT_MAX_PMASZ As sqlite3_int64 = &H20000000LL
Const SQLITE_VDBESORT_MAX_MERGE_COUNT As SQLITE_C_INT = 16
Const SQLITE_VDBESORT_TYPE_INTEGER As u8 = &H01
Const SQLITE_VDBESORT_TYPE_TEXT As u8 = &H02
Const SQLITE_VDBESORT_TYPE_REAL As u8 = &H04

#endif

/' end of sqlite3_vdbesort_types.bi '/
