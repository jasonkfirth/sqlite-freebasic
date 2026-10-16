/'
    Project: SQLite FreeBASIC port

    File: sqlite3_vdbe_mem_types.bi

    Purpose:

        Define the VDBE Mem value-cell layout from src/vdbeInt.h.

    Responsibilities:

        - Preserve the common non-debug C field order and widths.
        - Define value flags used by src/vdbemem.c.
        - Define the stack-owned context used by STAT4 sample value allocation.
        - Declare the lifecycle, scalar-value, and B-tree payload entry points.
        - Declare helpers that initialize array slots as SQLite value cells.

    This file intentionally does NOT contain:

        - General text encoding conversion or general SQL affinity operations.
        - Aggregate function storage or debug-only Mem fields.
'/

#ifndef SQLITE3_FB_VDBE_MEM_TYPES_BI
#define SQLITE3_FB_VDBE_MEM_TYPES_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_db_types.bi"

#define MEM_UNDEFINED 0
#define MEM_NULL 1
#define MEM_STR 2
#define MEM_INT 4
#define MEM_REAL 8
#define MEM_BLOB 16
#define MEM_INTREAL 32
#define MEM_FROM_BIND 64
#define MEM_CLEARED 256
#define MEM_TERM 512
#define MEM_ZERO 1024
#define MEM_SUBTYPE 2048
#define MEM_AFF_MASK &H003F
#define MEM_TYPE_MASK &H0DBF
#define MEM_DYN 4096
#define MEM_STATIC 8192
#define MEM_EPHEM 16384
#define MEM_AGG 32768

Type sqlite3MemDestructor As Sub CDecl (ByVal p As Any Ptr)

Union sqlite3MemValue
    r As Double
    i As sqlite3_int64
    nZero As SQLITE_C_INT
    ' The pointee is treated as immutable; FreeBASIC's union field stores the
    ' native pointer shape without a C-level const qualifier.
    zPType As ZString Ptr
    pDef As Any Ptr
End Union

Type SqliteVdbeMem
    u As sqlite3MemValue
    z As UByte Ptr
    n As SQLITE_C_INT
    flags As UShort
    enc As u8
    eSubtype As u8
    db As sqlite3 Ptr
    szMalloc As SQLITE_C_INT
    uTemp As u32
    zMalloc As UByte Ptr
    xDel As sqlite3MemDestructor
#ifdef SQLITE_DEBUG
    pScopyFrom As SqliteVdbeMem Ptr
    mScopyFlags As UShort
    bScopy As u8
#endif
End Type

#ifdef SQLITE_DEBUG
Declare Function sqlite3VdbeCheckMemInvariants CDecl Alias "sqlite3VdbeCheckMemInvariants" ( _
    ByVal pMem As SqliteVdbeMem Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3VdbeMemPrettyPrint CDecl Alias "sqlite3VdbeMemPrettyPrint" ( _
    ByVal pMem As SqliteVdbeMem Ptr, _
    ByVal pAccumulator As Any Ptr _
)
Declare Function sqlite3VdbeMemIsRowSet CDecl Alias "sqlite3VdbeMemIsRowSet" ( _
    ByVal pMem As Const SqliteVdbeMem Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3VdbeMemAboutToChange CDecl Alias "sqlite3VdbeMemAboutToChange" ( _
    ByVal pVdbe As Any Ptr, _
    ByVal pMem As SqliteVdbeMem Ptr _
)
Declare Function sqlite3VdbeMemValidStrRep CDecl Alias "sqlite3VdbeMemValidStrRep" ( _
    ByVal pMem As SqliteVdbeMem Ptr _
) As SQLITE_C_INT
#endif

' Stack context passed through STAT4 value extraction and allocation helpers.
Type SqliteValueNewStat4Context
    pParse As Any Ptr
    pIdx As Any Ptr
    ppRec As Any Ptr
    iVal As SQLITE_C_INT
End Type

Declare Sub sqlite3VdbeMemInit CDecl Alias "sqlite3VdbeMemInit" ( _
    ByVal pMem As Any Ptr, _
    ByVal db As sqlite3 Ptr, _
    ByVal flags As u16 _
)
Declare Sub sqlite3VdbeMemSetNull CDecl Alias "sqlite3VdbeMemSetNull" (ByVal pMem As Any Ptr)
Declare Sub sqlite3ValueSetNull CDecl Alias "sqlite3ValueSetNull" (ByVal pValue As Any Ptr)
Declare Function sqlite3VdbeMemGrow CDecl Alias "sqlite3VdbeMemGrow" ( _
    ByVal pMem As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal keepContent As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3VdbeMemClearAndResize CDecl Alias "sqlite3VdbeMemClearAndResize" ( _
    ByVal pMem As Any Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3VdbeMemFromBtree CDecl Alias "sqlite3VdbeMemFromBtree" ( _
    ByVal pCursor As Any Ptr, _
    ByVal offset As u32, _
    ByVal amount As u32, _
    ByVal pMem As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeMemFromBtreeZeroOffset CDecl Alias "sqlite3VdbeMemFromBtreeZeroOffset" ( _
    ByVal pCursor As Any Ptr, _
    ByVal amount As u32, _
    ByVal pMem As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeMemMakeWriteable CDecl Alias "sqlite3VdbeMemMakeWriteable" ( _
    ByVal pMem As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeMemExpandBlob CDecl Alias "sqlite3VdbeMemExpandBlob" ( _
    ByVal pMem As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeMemNulTerminate CDecl Alias "sqlite3VdbeMemNulTerminate" ( _
    ByVal pMem As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3ValueIsOfClass CDecl Alias "sqlite3ValueIsOfClass" ( _
    ByVal pValue As Any Ptr, _
    ByVal pDestructor As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeMemCopy CDecl Alias "sqlite3VdbeMemCopy" ( _
    ByVal pTo As Any Ptr, _
    ByVal pFrom As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeIntValue CDecl Alias "sqlite3VdbeIntValue" (ByVal pMem As Any Ptr) As sqlite3_int64
Declare Function sqlite3VdbeMemTooBig CDecl Alias "sqlite3VdbeMemTooBig" ( _
    ByVal pMem As SqliteVdbeMem Ptr _
) As SQLITE_C_INT
Declare Function sqlite3MemRealValueRC CDecl Alias "sqlite3MemRealValueRC" ( _
    ByVal pMem As Any Ptr, _
    ByVal pResult As Double Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeRealValue CDecl Alias "sqlite3VdbeRealValue" ( _
    ByVal pMem As Any Ptr _
) As Double
Declare Function sqlite3VdbeBooleanValue CDecl Alias "sqlite3VdbeBooleanValue" ( _
    ByVal pMem As Any Ptr, _
    ByVal ifNull As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3RealSameAsInt CDecl Alias "sqlite3RealSameAsInt" ( _
    ByVal value As Double, _
    ByVal integerValue As sqlite3_int64 _
) As SQLITE_C_INT
Declare Function sqlite3RealToI64 CDecl Alias "sqlite3RealToI64" ( _
    ByVal value As Double _
) As sqlite3_int64
Declare Function sqlite3VdbeMemIntegerify CDecl Alias "sqlite3VdbeMemIntegerify" ( _
    ByVal pMem As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeMemRealify CDecl Alias "sqlite3VdbeMemRealify" ( _
    ByVal pMem As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeMemNumerify CDecl Alias "sqlite3VdbeMemNumerify" ( _
    ByVal pMem As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3VdbeIntegerAffinity CDecl Alias "sqlite3VdbeIntegerAffinity" ( _
    ByVal pMem As Any Ptr _
)
Declare Sub sqlite3VdbeMemShallowCopy CDecl Alias "sqlite3VdbeMemShallowCopy" ( _
    ByVal pTo As Any Ptr, _
    ByVal pFrom As Const Any Ptr, _
    ByVal sourceType As SQLITE_C_INT _
)
Declare Sub sqlite3VdbeMemSetInt64 CDecl Alias "sqlite3VdbeMemSetInt64" ( _
    ByVal pMem As Any Ptr, _
    ByVal value As sqlite3_int64 _
)
Declare Sub sqlite3VdbeMemSetDouble CDecl Alias "sqlite3VdbeMemSetDouble" ( _
    ByVal pMem As Any Ptr, _
    ByVal value As Double _
)
Declare Sub sqlite3VdbeMemMove CDecl Alias "sqlite3VdbeMemMove" ( _
    ByVal pTo As Any Ptr, _
    ByVal pFrom As Any Ptr _
)
Declare Sub sqlite3VdbeMemSetPointer CDecl Alias "sqlite3VdbeMemSetPointer" ( _
    ByVal pMem As Any Ptr, _
    ByVal pPointer As Any Ptr, _
    ByVal zPointerType As Const ZString Ptr, _
    ByVal xDestructor As sqlite3MemDestructor _
)
Declare Function sqlite3VdbeMemSetStr CDecl Alias "sqlite3VdbeMemSetStr" ( _
    ByVal pMem As Any Ptr, _
    ByVal z As Const ZString Ptr, _
    ByVal nByte As sqlite3_int64, _
    ByVal enc As u8, _
    ByVal xDestructor As sqlite3MemDestructor _
) As SQLITE_C_INT
Declare Function sqlite3VdbeMemSetText CDecl Alias "sqlite3VdbeMemSetText" ( _
    ByVal pMem As Any Ptr, _
    ByVal z As Const ZString Ptr, _
    ByVal nByte As sqlite3_int64, _
    ByVal xDestructor As sqlite3MemDestructor _
) As SQLITE_C_INT
Declare Function sqlite3VdbeMemHandleBom CDecl Alias "sqlite3VdbeMemHandleBom" ( _
    ByVal pMem As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3VdbeMemSetZeroBlob CDecl Alias "sqlite3VdbeMemSetZeroBlob" ( _
    ByVal pMem As Any Ptr, _
    ByVal nZero As SQLITE_C_INT _
)
Declare Sub sqlite3VdbeMemRelease CDecl Alias "sqlite3VdbeMemRelease" (ByVal pMem As Any Ptr)
Declare Sub sqlite3VdbeMemReleaseMalloc CDecl Alias "sqlite3VdbeMemReleaseMalloc" (ByVal pMem As Any Ptr)
Declare Function sqlite3VdbeMemFinalize CDecl Alias "sqlite3VdbeMemFinalize" ( _
    ByVal pMem As Any Ptr, _
    ByVal pFunction As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3VdbeMemAggValue CDecl Alias "sqlite3VdbeMemAggValue" ( _
    ByVal pAccum As Any Ptr, _
    ByVal pOutput As Any Ptr, _
    ByVal pFunction As Any Ptr _
) As SQLITE_C_INT
Declare Function sqlite3ValueNew CDecl Alias "sqlite3ValueNew" ( _
    ByVal db As sqlite3 Ptr _
) As Any Ptr
Declare Sub sqlite3ValueSetStr CDecl Alias "sqlite3ValueSetStr" ( _
    ByVal pValue As Any Ptr, _
    ByVal nByte As SQLITE_C_INT, _
    ByVal z As Const Any Ptr, _
    ByVal enc As u8, _
    ByVal xDestructor As sqlite3MemDestructor _
)
Declare Sub sqlite3ValueFree CDecl Alias "sqlite3ValueFree" (ByVal pValue As Any Ptr)
Declare Function sqlite3VdbeMemSetRowSet CDecl Alias "sqlite3VdbeMemSetRowSet" ( _
    ByVal pMem As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3MemSetArrayInt64 CDecl Alias "sqlite3MemSetArrayInt64" ( _
    ByVal pMemArray As Any Ptr, _
    ByVal iIndex As SQLITE_C_INT, _
    ByVal value As sqlite3_int64 _
)
Declare Sub sqlite3NoopDestructor CDecl Alias "sqlite3NoopDestructor" (ByVal p As Any Ptr)

#endif

/' end of sqlite3_vdbe_mem_types.bi '/
