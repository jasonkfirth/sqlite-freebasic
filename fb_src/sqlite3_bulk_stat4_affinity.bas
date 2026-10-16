/'
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
** This module contains the STAT4 index-column affinity accessor.
'/

/' ------------------------------------------------------------------------- '/
/' SQLite FreeBASIC port                                                      '/
/' ------------------------------------------------------------------------- '/

/' Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_bulk_stat4_affinity.bas

    Purpose:

        Return the affinity byte for one index column when STAT4 is enabled.

    Responsibilities:

        - Lazily obtain the index affinity string.
        - Check the requested column before indexing the affinity bytes.

    This file intentionally does NOT contain:

        - STAT4 sample estimation or index construction.
'/

#lang "fb"
#ifdef SQLITE_ENABLE_STAT4

#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_db_types.bi"
#include once "sqlite3_schema_types.bi"
#include once "sqlite3_debug_assert.bi"

Declare Function sqlite3IndexAffinityStr CDecl Alias "sqlite3IndexAffinityStr" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pIndex As SqliteIndex Ptr _
) As Const ZString Ptr

Function sqlite3IndexColumnAffinity CDecl Alias "sqlite3IndexColumnAffinity" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pIndex As SqliteIndex Ptr, _
    ByVal columnIndex As SQLITE_C_INT _
) As Byte
    If db = 0 OrElse pIndex = 0 Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("database and index pointers are valid"))
#endif
        Return SQLITE_AFF_BLOB
    End If

    If columnIndex < 0 OrElse columnIndex >= pIndex->nColumn Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("index column number is in range"))
#endif
        Return SQLITE_AFF_BLOB
    End If

    If pIndex->zColAff = 0 Then
        If sqlite3IndexAffinityStr(db, pIndex) = 0 Then _
            Return SQLITE_AFF_BLOB
    End If

    If pIndex->zColAff = 0 Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("index affinity string is available"))
#endif
        Return SQLITE_AFF_BLOB
    End If

    Dim affinity As UByte = _
        CPtr(Const UByte Ptr, pIndex->zColAff)[columnIndex]
    If affinity = 0 Then
#ifdef SQLITE_DEBUG
        sqlite3DebugAssert(StrPtr("index column affinity byte is initialized"))
#endif
        Return SQLITE_AFF_BLOB
    End If
    Return affinity
End Function

#endif

/' end of sqlite3_bulk_stat4_affinity.bas '/
