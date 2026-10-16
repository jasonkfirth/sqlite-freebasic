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
** Internal interface definitions for SQLite.
**
'/ 
/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_fkey_types.bi

    Purpose:

        Describe the foreign-key, trigger, and trigger-program records.

    Responsibilities:

        - Preserve the C prefix fields used to unlink and free foreign keys.
        - Preserve the full Trigger and TriggerStep pointer order.
        - Preserve the TriggerPrg prefix used by parser trigger-action checks.
        - Keep foreign-key column storage as a trailing flexible array.

    This file intentionally does NOT contain:

        - Foreign-key action generation or trigger execution.
        - A claim that these layouts cover every optional SQLite field.
'/ 

#ifndef SQLITE3_FB_FKEY_TYPES_BI
#define SQLITE3_FB_FKEY_TYPES_BI

#include once "sqlite3_types.bi"

' These one-byte values match the trigger timing flags in sqliteInt.h.
#define TRIGGER_BEFORE 1
#define TRIGGER_AFTER 2

Type SqliteTriggerStep
    op As u8
    orconf As u8
    pTrig As Any Ptr
    pSelect As Any Ptr
    pSrc As Any Ptr
    pWhere As Any Ptr
    pExprList As Any Ptr
    pIdList As Any Ptr
    pUpsert As Any Ptr
    zSpan As ZString Ptr
    pNext As SqliteTriggerStep Ptr
    pLast As SqliteTriggerStep Ptr
End Type

Type SqliteTrigger
    zName As ZString Ptr
    table As ZString Ptr
    op As u8
    tr_tm As u8
    bReturning As u8
    pWhen As Any Ptr
    pColumns As Any Ptr
    pSchema As Any Ptr
    pTabSchema As Any Ptr
    step_list As SqliteTriggerStep Ptr
    pNext As SqliteTrigger Ptr
End Type

' TriggerPrg is owned by Parse. Foreign-key action checks inspect this record
' to distinguish a generated SET NULL trigger from an ordinary trigger.
Type SqliteTriggerPrg
    pTrigger As SqliteTrigger Ptr
    pNext As SqliteTriggerPrg Ptr
    pProgram As Any Ptr
    orconf As SQLITE_C_INT
    aColmask(0 To 1) As u32
End Type

Type SqliteFKeyColumn
    iFrom As SQLITE_C_INT
    zCol As ZString Ptr
End Type

Type SqliteFKey
    pFrom As Any Ptr
    pNextFrom As SqliteFKey Ptr
    zTo As ZString Ptr
    pNextTo As SqliteFKey Ptr
    pPrevTo As SqliteFKey Ptr
    nCol As SQLITE_C_INT
    isDeferred As u8
    aAction(0 To 1) As u8
    apTrigger(0 To 1) As SqliteTrigger Ptr
    aCol(0 To 0) As SqliteFKeyColumn
End Type

#endif

/' end of sqlite3_fkey_types.bi '/
