/'
    Project: SQLite FreeBASIC port

    File: sqlite3_bulk_arrayallocate.bas

    Purpose:

        Port SQLite's shared growable-array allocator from src/build.c.

    Responsibilities:

        - Grow the array when its entry count reaches a power-of-two capacity.
        - Zero the new slot and update the caller's count and index.
        - Preserve the old pointer and report allocation failure through pIdx.

    This file intentionally does NOT contain:

        - Array-specific ownership or element cleanup.
        - Runtime validation of the array's entry size.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"

Declare Function c2fb_crt_memset CDecl Alias "memset" ( _
    ByVal destination As Any Ptr, _
    ByVal value As SQLITE_C_INT, _
    ByVal byteCount As SQLITE_SIZE_T _
) As Any Ptr


Function sqlite3ArrayAllocate CDecl Alias "sqlite3ArrayAllocate" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal currentArray As Any Ptr, _
    ByVal entrySize As SQLITE_C_INT, _
    ByVal pEntryCount As SQLITE_C_INT Ptr, _
    ByVal pIndex As SQLITE_C_INT Ptr _
) As Any Ptr
    Dim entryCount As SQLITE_C_INT = *pEntryCount
    *pIndex = entryCount

    Dim n As sqlite3_int64 = entryCount
    If (n And (n - 1)) = 0 Then
        Dim newCapacity As sqlite3_int64
        If n = 0 Then
            newCapacity = 1
        Else
            newCapacity = n * 2
        End If

        Dim allocationSize As sqlite3_int64 = newCapacity * entrySize
        Dim pNewArray As Any Ptr = sqlite3DbRealloc( _
            db, currentArray, Cast(sqlite3_uint64, allocationSize))
        If pNewArray = 0 Then
            *pIndex = -1
            Return currentArray
        End If

        currentArray = pNewArray
    End If

    Dim pBytes As UByte Ptr = CPtr(UByte Ptr, currentArray)
    Dim zeroOffset As sqlite3_int64 = n * entrySize
    c2fb_crt_memset(CPtr(Any Ptr, @pBytes[zeroOffset]), 0, _
                    Cast(SQLITE_SIZE_T, entrySize))

    *pEntryCount = entryCount + 1
    Return currentArray
End Function

/' end of sqlite3_bulk_arrayallocate.bas '/
/'
/*
** 2001 September 15
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
*************************************************************************
*/
'/
