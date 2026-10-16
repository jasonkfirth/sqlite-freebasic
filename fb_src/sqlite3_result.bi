/'
    Project: SQLite FreeBASIC port

    File: sqlite3_result.bi

    Purpose:

        Preserve the function-definition and sqlite3_context layouts used by
        SQL function dispatch and result APIs.

    Responsibilities:

        - Define the function callback prefix, overload links, and hash/destructor union.
        - Match the fields that precede sqlite3_context.argv in vdbeInt.h.
        - Expose the result-cell pointer and error metadata to sqlite3_result_*.

    This file intentionally does NOT contain:

        - The Vdbe execution layout or SQL-function invocation code.
        - Aggregate-context allocation.
'/

#ifndef SQLITE3_FB_RESULT_BI
#define SQLITE3_FB_RESULT_BI

#include once "sqlite3_vdbe_mem_types.bi"
#include once "sqlite3_parser_types.bi"

Type SqliteFuncDefPrefix
    nArg As Short
    reserved As u16
    funcFlags As u32
    pUserData As Any Ptr
End Type

Type SqliteScalarFunction As Sub CDecl ( _
    ByVal pContext As Any Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal pArguments As SqliteVdbeMem Ptr Ptr _
)

Type SqliteAggregateFinalFunction As Sub CDecl ( _
    ByVal pContext As Any Ptr _
)

' Reference-counted application-function destructor allocated by registration.
Type SqliteFuncDestructor
    nRef As SQLITE_C_INT
    xDestroy As SqliteDbDestructor
    pUserData As Any Ptr
End Type

Union SqliteFuncDefUnion
    pHash As Any Ptr
    pDestructor As SqliteFuncDestructor Ptr
End Union

Type SqliteFuncDef
    nArg As Short
    reserved As u16
    funcFlags As u32
    pUserData As Any Ptr
    ' Same-name overloads are linked here for built-in resolution.
    pNext As Any Ptr
    xSFunc As SqliteScalarFunction
    xFinalize As Any Ptr
    xValue As Any Ptr
    xInverse As Any Ptr
    zName As Const ZString Ptr
    ' C's pHash/pDestructor union occupies one pointer-sized slot.
    u As Any Ptr
End Type

Type SqliteResultContext
    pOut As SqliteVdbeMem Ptr
    pFunc As Any Ptr
    pMem As SqliteVdbeMem Ptr
    pVdbe As Any Ptr
    iOp As SQLITE_C_INT
    isError As SQLITE_C_INT
    enc As u8
    skipFlag As u8
    argc As u16
    argv(0 To 0) As SqliteVdbeMem Ptr
End Type

#ifdef SQLITE_ENABLE_PERCENTILE
Declare Function sqlite3VdbeFuncName CDecl Alias "sqlite3VdbeFuncName" ( _
    ByVal pContext As SqliteResultContext Ptr _
) As Const ZString Ptr
#endif

Declare Function sqlite3FindBuiltinFunction CDecl Alias "sqlite3FindBuiltinFunction" ( _
    ByVal zName As Const ZString Ptr, _
    ByVal argumentCount As SQLITE_C_INT _
) As SqliteFuncDef Ptr
Declare Function sqlite3FindFunction CDecl Alias "sqlite3FindFunction" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal argumentCount As SQLITE_C_INT, _
    ByVal textEncoding As u8, _
    ByVal createFlag As u8 _
) As SqliteFuncDef Ptr
Declare Function sqlite3_aggregate_context CDecl Alias "sqlite3_aggregate_context" ( _
    ByVal pContext As Any Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As Any Ptr
Declare Function sqlite3_aggregate_count CDecl Alias "sqlite3_aggregate_count" ( _
    ByVal pContext As Any Ptr _
) As SQLITE_C_INT

#endif

/' end of sqlite3_result.bi '/
